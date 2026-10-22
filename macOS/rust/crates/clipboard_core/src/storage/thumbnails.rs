use crate::domain::ItemManagementResult;
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use rusqlite::{params, OptionalExtension};
use std::path::{Path, PathBuf};

use super::support::{
    insert_asset, normalize_item_id, normalize_relative_asset_path, stable_hash_bytes,
};
use super::ClipboardCore;

impl ClipboardCore {
    pub fn image_payload_path(&self, item_id: &str) -> Result<Option<PathBuf>> {
        self.image_asset_path(item_id, "payload")
    }

    pub fn image_thumbnail_path(&self, item_id: &str) -> Result<Option<PathBuf>> {
        self.image_asset_path(item_id, "thumbnail")
    }

    fn image_asset_path(&self, item_id: &str, kind: &str) -> Result<Option<PathBuf>> {
        let item_id = normalize_item_id(item_id)?;
        let relative_path: Option<String> = self
            .connection
            .query_row(
                r#"SELECT a.relative_path FROM clipboard_items i
               INNER JOIN clipboard_assets a ON a.item_id = i.id AND a.kind = ?2
               WHERE i.id = ?1 AND i.type = 'image' AND i.deleted_at_ms IS NULL
                 AND i.payload_state = 'ready'
               ORDER BY a.created_at_ms DESC, a.id DESC LIMIT 1"#,
                params![item_id, kind],
                |row| row.get(0),
            )
            .optional()?;
        let Some(relative_path) = relative_path else {
            return Ok(None);
        };
        match controlled_image_path(self.root_dir()?, &relative_path) {
            Ok(path) => Ok(Some(path)),
            Err(error)
                if error.code == CoreErrorCode::IoFailed
                    && !self.root_dir()?.join(&relative_path).try_exists()? =>
            {
                Ok(None)
            }
            Err(error) => Err(error),
        }
    }

    /// Register an already generated thumbnail without treating it as a new copy.
    pub fn set_item_thumbnail(
        &mut self,
        item_id: &str,
        relative_path: &str,
        mime_type: &str,
        width: i64,
        height: i64,
    ) -> Result<ItemManagementResult> {
        self.with_asset_registration(vec![relative_path.to_owned()], |core, lifecycle| {
            core.set_item_thumbnail_locked(
                item_id,
                relative_path,
                mime_type,
                width,
                height,
                lifecycle,
            )
        })
    }
    fn set_item_thumbnail_locked(
        &mut self,
        item_id: &str,
        relative_path: &str,
        mime_type: &str,
        width: i64,
        height: i64,
        lifecycle: &super::asset_lifecycle::ManagedAssetGuard,
    ) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id)?;
        if width <= 0 || height <= 0 {
            return Err(invalid_asset("thumbnail dimensions must be positive"));
        }
        let relative_path = normalize_relative_asset_path(relative_path)?;
        if !(relative_path.starts_with("assets/") || relative_path.starts_with("thumbnails/")) {
            return Err(invalid_asset(
                "image asset must be inside assets or thumbnails",
            ));
        }
        let data = lifecycle.read_bytes(&relative_path, 16 * 1024 * 1024)?;
        let valid_header = match mime_type {
            "image/png" => data.starts_with(b"\x89PNG\r\n\x1a\n"),
            "image/webp" => data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WEBP"),
            "image/jpeg" => data.starts_with(&[0xff, 0xd8, 0xff]),
            _ => false,
        };
        if !valid_header {
            return Err(invalid_asset(
                "thumbnail MIME type does not match its image header",
            ));
        }
        let digest = stable_hash_bytes(&data);
        let transaction = self.connection.transaction()?;
        let active_image: bool = transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM clipboard_items WHERE id = ?1 AND type = 'image' AND deleted_at_ms IS NULL AND payload_state = 'ready')",
            params![item_id], |row| row.get(0),
        )?;
        if !active_image {
            drop(transaction);
            return Ok(ItemManagementResult { affected_count: 0 });
        }
        transaction.execute(
            "DELETE FROM clipboard_assets WHERE item_id = ?1 AND kind = 'thumbnail'",
            params![item_id],
        )?;
        insert_asset(
            &transaction,
            &item_id,
            "thumbnail",
            mime_type,
            &relative_path,
            data.len() as i64,
            Some(width),
            Some(height),
            &digest,
            now_ms(),
        )?;
        transaction.commit()?;
        // The normal maintenance pass reclaims any superseded thumbnail file.
        Ok(ItemManagementResult { affected_count: 1 })
    }
}

fn controlled_image_path(root: &Path, relative_path: &str) -> Result<PathBuf> {
    let relative_path = normalize_relative_asset_path(relative_path)?;
    if !(relative_path.starts_with("assets/") || relative_path.starts_with("thumbnails/")) {
        return Err(invalid_asset(
            "image asset must be inside assets or thumbnails",
        ));
    }
    let root = root.canonicalize()?;
    let path = root.join(relative_path).canonicalize()?;
    if !path.starts_with(&root) || !path.is_file() {
        return Err(invalid_asset(
            "image asset must be a file inside app support",
        ));
    }
    Ok(path)
}

fn invalid_asset(message: &str) -> CoreError {
    CoreError::new(CoreErrorCode::InvalidInput, message)
}
