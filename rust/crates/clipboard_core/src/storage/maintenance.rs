use crate::domain::MaintenanceResult;
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use std::collections::HashSet;
use std::fs;
use std::path::Path;

use super::pending_images::{
    active_pending_image_staged_paths, mark_pending_jobs_deleted_for_items,
    purge_expired_pending_image_tombstones, terminal_pending_image_staged_paths,
};
use super::support::{delete_relative_file, unique_strings};
use super::ClipboardCore;

const UNKNOWN_STAGING_FILE_GRACE_MS: i64 = 24 * 60 * 60 * 1000;

impl ClipboardCore {
    pub fn run_maintenance(&mut self) -> Result<MaintenanceResult> {
        let root = self.root_dir()?.to_path_buf();
        let mut result = self.purge_soft_deleted_items_and_assets()?;
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        let terminal_pending_staged_paths = terminal_pending_image_staged_paths(&transaction)?
            .into_iter()
            .collect::<HashSet<_>>();
        let active_pending_staged_paths = active_pending_image_staged_paths(&transaction, now)?
            .into_iter()
            .collect::<HashSet<_>>();
        let _ = purge_expired_pending_image_tombstones(&transaction, now)?;
        transaction.commit()?;

        let referenced_asset_paths = self.referenced_asset_paths()?;
        for relative_path in collect_maintenance_files(&root)? {
            if should_remove_unreferenced_file(
                &root,
                &relative_path,
                &referenced_asset_paths,
                &active_pending_staged_paths,
                &terminal_pending_staged_paths,
                now,
            )? {
                if let Some(byte_count) = delete_relative_file(&root, &relative_path)? {
                    result.deleted_orphan_file_count += 1;
                    result.reclaimed_bytes += byte_count;
                }
            }
        }
        remove_empty_maintenance_directories(&root)?;

        Ok(result)
    }

    pub(super) fn purge_soft_deleted_items_and_assets(&mut self) -> Result<MaintenanceResult> {
        let root = self.root_dir()?.to_path_buf();
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        mark_pending_jobs_deleted_for_items(&transaction, now)?;
        transaction.commit()?;

        let removable_asset_paths = self.removable_asset_paths()?;
        let mut result = MaintenanceResult::default();

        for relative_path in unique_strings(removable_asset_paths) {
            if let Some(byte_count) = delete_relative_file(&root, &relative_path)? {
                result.deleted_asset_file_count += 1;
                result.reclaimed_bytes += byte_count;
            }
        }

        let transaction = self.connection.transaction()?;
        result.deleted_asset_row_count = transaction.execute(
            r#"
            DELETE FROM clipboard_assets
            WHERE item_id IN (
                SELECT id
                FROM clipboard_items
                WHERE deleted_at_ms IS NOT NULL
            )
            OR item_id NOT IN (
                SELECT id
                FROM clipboard_items
            )
            "#,
            [],
        )? as i64;
        result.purged_item_count = transaction.execute(
            "DELETE FROM clipboard_items WHERE deleted_at_ms IS NOT NULL",
            [],
        )? as i64;
        transaction.execute(
            "INSERT INTO clipboard_items_fts(clipboard_items_fts) VALUES('rebuild')",
            [],
        )?;
        transaction.commit()?;

        Ok(result)
    }

    fn removable_asset_paths(&self) -> Result<Vec<String>> {
        let mut statement = self.connection.prepare(
            r#"
            SELECT a.relative_path
            FROM clipboard_assets a
            LEFT JOIN clipboard_items i ON i.id = a.item_id
            WHERE i.id IS NULL OR i.deleted_at_ms IS NOT NULL
            "#,
        )?;
        let mut paths = statement
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let mut link_statement = self.connection.prepare(
            r#"
            SELECT lm.icon_relative_path, lm.image_relative_path
            FROM link_metadata lm
            LEFT JOIN clipboard_items i ON i.id = lm.item_id
            WHERE i.id IS NULL OR i.deleted_at_ms IS NOT NULL
            "#,
        )?;
        for row in link_statement.query_map([], |row| {
            Ok((
                row.get::<_, Option<String>>(0)?,
                row.get::<_, Option<String>>(1)?,
            ))
        })? {
            let (icon_path, image_path) = row?;
            paths.extend(icon_path);
            paths.extend(image_path);
        }
        Ok(paths)
    }

    fn referenced_asset_paths(&self) -> Result<HashSet<String>> {
        let mut paths = Vec::new();
        let mut asset_statement = self.connection.prepare(
            r#"
            SELECT a.relative_path
            FROM clipboard_assets a
            INNER JOIN clipboard_items i ON i.id = a.item_id
            WHERE i.deleted_at_ms IS NULL
            "#,
        )?;
        paths.extend(
            asset_statement
                .query_map([], |row| row.get::<_, String>(0))?
                .collect::<std::result::Result<Vec<_>, _>>()?,
        );

        let mut icon_statement = self.connection.prepare(
            r#"
            SELECT relative_path
            FROM source_app_icons
            "#,
        )?;
        paths.extend(
            icon_statement
                .query_map([], |row| row.get::<_, String>(0))?
                .collect::<std::result::Result<Vec<_>, _>>()?,
        );

        let mut link_statement = self.connection.prepare(
            r#"
            SELECT lm.icon_relative_path, lm.image_relative_path
            FROM link_metadata lm
            INNER JOIN clipboard_items i ON i.id = lm.item_id
            WHERE i.deleted_at_ms IS NULL
            "#,
        )?;
        for row in link_statement.query_map([], |row| {
            Ok((
                row.get::<_, Option<String>>(0)?,
                row.get::<_, Option<String>>(1)?,
            ))
        })? {
            let (icon_path, image_path) = row?;
            paths.extend(icon_path);
            paths.extend(image_path);
        }

        Ok(paths.into_iter().collect())
    }
}

fn collect_maintenance_files(root: &Path) -> Result<Vec<String>> {
    let mut files = Vec::new();
    for directory in ["assets", "thumbnails", "app-icons", "staging", ".staging"] {
        collect_files_in_directory(&root.join(directory), directory, &mut files)?;
    }
    Ok(files)
}

fn collect_files_in_directory(
    directory: &Path,
    relative_prefix: &str,
    files: &mut Vec<String>,
) -> Result<()> {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => {
            return Err(CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("path", directory.display().to_string()));
        }
    };

    for entry in entries {
        let entry =
            entry.map_err(|error| CoreError::new(CoreErrorCode::IoFailed, error.to_string()))?;
        let path = entry.path();
        let file_name = entry.file_name().to_string_lossy().to_string();
        let relative_path = format!("{relative_prefix}/{file_name}");
        let file_type = entry.file_type().map_err(|error| {
            CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("path", path.display().to_string())
        })?;

        if file_type.is_dir() {
            collect_files_in_directory(&path, &relative_path, files)?;
        } else if file_type.is_file() {
            files.push(relative_path);
        }
    }

    Ok(())
}

fn should_remove_unreferenced_file(
    root: &Path,
    relative_path: &str,
    referenced_paths: &HashSet<String>,
    active_pending_staged_paths: &HashSet<String>,
    terminal_pending_staged_paths: &HashSet<String>,
    now_ms: i64,
) -> Result<bool> {
    if relative_path.starts_with("staging/") || relative_path.starts_with(".staging/") {
        if active_pending_staged_paths.contains(relative_path) {
            return Ok(false);
        }
        if terminal_pending_staged_paths.contains(relative_path) {
            return Ok(true);
        }
        return Ok(staging_file_is_conservatively_old(
            &root.join(relative_path),
            now_ms,
        )?);
    }

    Ok((relative_path.starts_with("assets/")
        || relative_path.starts_with("thumbnails/")
        || relative_path.starts_with("app-icons/"))
        && !referenced_paths.contains(relative_path))
}

fn remove_empty_maintenance_directories(root: &Path) -> Result<()> {
    for directory in ["assets", "thumbnails", "app-icons", "staging", ".staging"] {
        remove_empty_child_directories(&root.join(directory))?;
    }
    Ok(())
}

fn staging_file_is_conservatively_old(path: &Path, now_ms: i64) -> Result<bool> {
    let metadata = match fs::metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => {
            return Err(CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("path", path.display().to_string()));
        }
    };
    let modified = match metadata.modified() {
        Ok(modified) => modified,
        Err(_) => return Ok(false),
    };
    let modified_ms = modified
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis().min(i64::MAX as u128) as i64)
        .unwrap_or(0);
    Ok(now_ms.saturating_sub(modified_ms) >= UNKNOWN_STAGING_FILE_GRACE_MS)
}

fn remove_empty_child_directories(directory: &Path) -> Result<()> {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => {
            return Err(CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("path", directory.display().to_string()));
        }
    };

    for entry in entries {
        let entry =
            entry.map_err(|error| CoreError::new(CoreErrorCode::IoFailed, error.to_string()))?;
        let path = entry.path();
        let file_type = entry.file_type().map_err(|error| {
            CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("path", path.display().to_string())
        })?;
        if file_type.is_dir() {
            remove_empty_child_directories(&path)?;
            match fs::remove_dir(&path) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::DirectoryNotEmpty => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => {
                    return Err(CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                        .with_detail("path", path.display().to_string()));
                }
            }
        }
    }

    Ok(())
}
