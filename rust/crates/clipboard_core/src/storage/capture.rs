use crate::domain::{
    CaptureFilesRequest, CaptureImageRequest, CaptureResult, CaptureTextRequest, SourceConfidence,
};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use rusqlite::{params, OptionalExtension, Transaction};
use std::fs;

use super::source_apps::SourceAppInput;
use super::support::{
    classify_text, file_paths_fingerprint, hash_file, insert_asset, normalize_file_paths,
    normalize_relative_asset_path, normalize_text, positive_dimension, stable_hash,
    summarize_files, summarize_image, summarize_text,
};
use super::ClipboardCore;

impl ClipboardCore {
    pub fn capture_text(&mut self, request: CaptureTextRequest) -> Result<CaptureResult> {
        let normalized_text = normalize_text(&request.text);
        if normalized_text.is_empty() {
            return Err(CoreError::new(
                CoreErrorCode::InvalidInput,
                "text capture cannot be empty",
            ));
        }

        let now = now_ms();
        let item_type = classify_text(&normalized_text);
        let summary = summarize_text(&normalized_text);
        let content_hash = stable_hash(&format!("{}:{normalized_text}", item_type.as_str()));
        let source_app_id = self.upsert_source_app(
            SourceAppInput {
                bundle_id: request.source_bundle_id.as_deref(),
                app_name: request.source_app_name.as_deref(),
                bundle_path: request.source_bundle_path.as_deref(),
                icon_relative_path: request.source_icon_relative_path.as_deref(),
            },
            now,
        )?;
        let source_app_name = request.source_app_name.as_deref();
        let source_confidence = request.source_confidence;
        let size_bytes = normalized_text.len() as i64;
        let transaction = self.connection.transaction()?;

        let (item_id, copy_count, inserted) = match find_existing_item(&transaction, &content_hash)?
        {
            Some((item_id, copy_count)) => {
                let next_copy_count = copy_count + 1;
                transaction.execute(
                    r#"
                    UPDATE clipboard_items
                    SET
                        last_copied_at_ms = ?1,
                        copy_count = ?2,
                        source_app_id = ?3,
                        source_app_name = ?4,
                        source_confidence = ?5,
                        updated_at_ms = ?1
                    WHERE id = ?6
                    "#,
                    params![
                        now,
                        next_copy_count,
                        source_app_id.as_deref(),
                        source_app_name,
                        source_confidence.as_str(),
                        item_id
                    ],
                )?;
                (item_id, next_copy_count, false)
            }
            None => {
                let item_id = make_item_id(&content_hash);
                transaction.execute(
                    r#"
                    INSERT INTO clipboard_items (
                        id, type, summary, primary_text, content_hash,
                        source_app_id, source_app_name, source_confidence,
                        first_copied_at_ms, last_copied_at_ms, copy_count,
                        is_pinned, size_bytes, preview_state,
                        created_at_ms, updated_at_ms
                    )
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9, 1, 0, ?10, 'ready', ?9, ?9)
                    "#,
                    params![
                        item_id,
                        item_type.as_str(),
                        summary,
                        normalized_text,
                        content_hash,
                        source_app_id.as_deref(),
                        source_app_name,
                        source_confidence.as_str(),
                        now,
                        size_bytes
                    ],
                )?;
                (item_id, 1, true)
            }
        };

        record_capture_event(
            &transaction,
            &item_id,
            source_app_id.as_deref(),
            source_confidence,
            request.pasteboard_change_count,
            request.self_write_token.as_deref(),
            now,
        )?;
        update_search_index(
            &transaction,
            &item_id,
            &summary,
            &normalized_text,
            source_app_name.unwrap_or_default(),
        )?;

        transaction.commit()?;
        self.apply_post_capture()?;

        Ok(CaptureResult {
            item_id,
            content_hash,
            copy_count,
            inserted,
        })
    }

    pub fn capture_image(&mut self, request: CaptureImageRequest) -> Result<CaptureResult> {
        let payload_relative_path = normalize_relative_asset_path(&request.payload_relative_path)?;
        let preview_relative_path = request
            .preview_relative_path
            .as_deref()
            .map(normalize_relative_asset_path)
            .transpose()?;
        let root = self.root_dir()?.to_path_buf();
        let payload_path = root.join(&payload_relative_path);
        let asset_digest = hash_file(&payload_path)?;
        let now = now_ms();
        let summary = summarize_image(request.width, request.height);
        let content_hash = stable_hash(&format!("image:{asset_digest}"));
        let source_app_id = self.upsert_source_app(
            SourceAppInput {
                bundle_id: request.source_bundle_id.as_deref(),
                app_name: request.source_app_name.as_deref(),
                bundle_path: request.source_bundle_path.as_deref(),
                icon_relative_path: request.source_icon_relative_path.as_deref(),
            },
            now,
        )?;
        let source_app_name = request.source_app_name.as_deref();
        let source_confidence = request.source_confidence;
        let byte_count = if request.byte_count > 0 {
            request.byte_count
        } else {
            fs::metadata(&payload_path)?.len() as i64
        };
        let width = positive_dimension(request.width);
        let height = positive_dimension(request.height);
        let mime_type = request
            .mime_type
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("image/png")
            .to_string();
        let transaction = self.connection.transaction()?;

        let (item_id, copy_count, inserted) = match find_existing_item(&transaction, &content_hash)?
        {
            Some((item_id, copy_count)) => {
                let next_copy_count = copy_count + 1;
                transaction.execute(
                    r#"
                    UPDATE clipboard_items
                    SET
                        summary = ?1,
                        last_copied_at_ms = ?2,
                        copy_count = ?3,
                        source_app_id = ?4,
                        source_app_name = ?5,
                        source_confidence = ?6,
                        size_bytes = ?7,
                        preview_state = 'ready',
                        updated_at_ms = ?2
                    WHERE id = ?8
                    "#,
                    params![
                        summary,
                        now,
                        next_copy_count,
                        source_app_id.as_deref(),
                        source_app_name,
                        source_confidence.as_str(),
                        byte_count,
                        item_id
                    ],
                )?;
                (item_id, next_copy_count, false)
            }
            None => {
                let item_id = make_item_id(&content_hash);
                transaction.execute(
                    r#"
                    INSERT INTO clipboard_items (
                        id, type, summary, primary_text, content_hash,
                        source_app_id, source_app_name, source_confidence,
                        first_copied_at_ms, last_copied_at_ms, copy_count,
                        is_pinned, size_bytes, preview_state,
                        created_at_ms, updated_at_ms
                    )
                    VALUES (?1, 'image', ?2, NULL, ?3, ?4, ?5, ?6, ?7, ?7, 1, 0, ?8, 'ready', ?7, ?7)
                    "#,
                    params![
                        item_id,
                        summary,
                        content_hash,
                        source_app_id.as_deref(),
                        source_app_name,
                        source_confidence.as_str(),
                        now,
                        byte_count
                    ],
                )?;
                (item_id, 1, true)
            }
        };

        insert_asset(
            &transaction,
            &item_id,
            "payload",
            &mime_type,
            &payload_relative_path,
            byte_count,
            width,
            height,
            &asset_digest,
            now,
        )?;

        if let Some(preview_relative_path) = preview_relative_path.as_deref() {
            let preview_path = root.join(preview_relative_path);
            let preview_digest = hash_file(&preview_path)?;
            let preview_byte_count = fs::metadata(&preview_path)?.len() as i64;
            insert_asset(
                &transaction,
                &item_id,
                "thumbnail",
                &mime_type,
                preview_relative_path,
                preview_byte_count,
                width,
                height,
                &preview_digest,
                now,
            )?;
        }

        let format_id = format!(
            "format_{}",
            &stable_hash(&format!("{item_id}:primary:{asset_digest}"))[..24]
        );
        transaction.execute(
            r#"
            INSERT OR IGNORE INTO clipboard_formats (
                id, item_id, uti, role, storage, byte_count
            )
            VALUES (?1, ?2, ?3, 'primary', 'staged_asset', ?4)
            "#,
            params![format_id, item_id, mime_type, byte_count],
        )?;

        record_capture_event(
            &transaction,
            &item_id,
            source_app_id.as_deref(),
            source_confidence,
            request.pasteboard_change_count,
            request.self_write_token.as_deref(),
            now,
        )?;
        update_search_index(
            &transaction,
            &item_id,
            &summary,
            "",
            source_app_name.unwrap_or_default(),
        )?;

        transaction.commit()?;
        self.apply_post_capture()?;

        Ok(CaptureResult {
            item_id,
            content_hash,
            copy_count,
            inserted,
        })
    }

    pub fn capture_files(&mut self, request: CaptureFilesRequest) -> Result<CaptureResult> {
        let file_paths = normalize_file_paths(&request.file_paths)?;
        let primary_text = file_paths.join("\n");
        let summary = summarize_files(&file_paths);
        let content_hash = stable_hash(&format!("file:{}", file_paths_fingerprint(&file_paths)));
        let snapshot_relative_path = request
            .snapshot_relative_path
            .as_deref()
            .map(normalize_relative_asset_path)
            .transpose()?;
        let root = self.root_dir()?.to_path_buf();
        let now = now_ms();
        let source_app_id = self.upsert_source_app(
            SourceAppInput {
                bundle_id: request.source_bundle_id.as_deref(),
                app_name: request.source_app_name.as_deref(),
                bundle_path: request.source_bundle_path.as_deref(),
                icon_relative_path: request.source_icon_relative_path.as_deref(),
            },
            now,
        )?;
        let source_app_name = request.source_app_name.as_deref();
        let source_confidence = request.source_confidence;
        let size_bytes = request.snapshot_byte_count.max(primary_text.len() as i64);
        let transaction = self.connection.transaction()?;

        let (item_id, copy_count, inserted) = match find_existing_item(&transaction, &content_hash)?
        {
            Some((item_id, copy_count)) => {
                let next_copy_count = copy_count + 1;
                transaction.execute(
                    r#"
                    UPDATE clipboard_items
                    SET
                        summary = ?1,
                        primary_text = ?2,
                        last_copied_at_ms = ?3,
                        copy_count = ?4,
                        source_app_id = ?5,
                        source_app_name = ?6,
                        source_confidence = ?7,
                        size_bytes = ?8,
                        preview_state = 'ready',
                        updated_at_ms = ?3
                    WHERE id = ?9
                    "#,
                    params![
                        summary,
                        primary_text,
                        now,
                        next_copy_count,
                        source_app_id.as_deref(),
                        source_app_name,
                        source_confidence.as_str(),
                        size_bytes,
                        item_id
                    ],
                )?;
                (item_id, next_copy_count, false)
            }
            None => {
                let item_id = make_item_id(&content_hash);
                transaction.execute(
                    r#"
                    INSERT INTO clipboard_items (
                        id, type, summary, primary_text, content_hash,
                        source_app_id, source_app_name, source_confidence,
                        first_copied_at_ms, last_copied_at_ms, copy_count,
                        is_pinned, size_bytes, preview_state,
                        created_at_ms, updated_at_ms
                    )
                    VALUES (?1, 'file', ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, 1, 0, ?9, 'ready', ?8, ?8)
                    "#,
                    params![
                        item_id,
                        summary,
                        primary_text,
                        content_hash,
                        source_app_id.as_deref(),
                        source_app_name,
                        source_confidence.as_str(),
                        now,
                        size_bytes
                    ],
                )?;
                (item_id, 1, true)
            }
        };

        if let Some(snapshot_relative_path) = snapshot_relative_path.as_deref() {
            let snapshot_path = root.join(snapshot_relative_path);
            let snapshot_digest = hash_file(&snapshot_path)?;
            let snapshot_byte_count = fs::metadata(&snapshot_path)?.len() as i64;
            insert_asset(
                &transaction,
                &item_id,
                "file_snapshot",
                "application/json",
                snapshot_relative_path,
                snapshot_byte_count,
                None,
                None,
                &snapshot_digest,
                now,
            )?;
        }

        let format_id = format!(
            "format_{}",
            &stable_hash(&format!("{item_id}:primary:file-url"))[..24]
        );
        transaction.execute(
            r#"
            INSERT OR IGNORE INTO clipboard_formats (
                id, item_id, uti, role, storage, byte_count
            )
            VALUES (?1, ?2, 'public.file-url', 'primary', 'inline', ?3)
            "#,
            params![format_id, item_id, primary_text.len() as i64],
        )?;

        record_capture_event(
            &transaction,
            &item_id,
            source_app_id.as_deref(),
            source_confidence,
            request.pasteboard_change_count,
            request.self_write_token.as_deref(),
            now,
        )?;
        update_search_index(
            &transaction,
            &item_id,
            &summary,
            &primary_text,
            source_app_name.unwrap_or_default(),
        )?;

        transaction.commit()?;
        self.apply_post_capture()?;

        Ok(CaptureResult {
            item_id,
            content_hash,
            copy_count,
            inserted,
        })
    }

    fn apply_post_capture(&mut self) -> Result<()> {
        let preferences = self.get_preferences()?;
        self.apply_history_preferences(&preferences)?;
        Ok(())
    }
}

fn make_item_id(content_hash: &str) -> String {
    format!("item_{}", &content_hash[..24])
}

fn find_existing_item(
    transaction: &Transaction<'_>,
    content_hash: &str,
) -> Result<Option<(String, i64)>> {
    transaction
        .query_row(
            "SELECT id, copy_count FROM clipboard_items WHERE content_hash = ?1 AND deleted_at_ms IS NULL",
            params![content_hash],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
        )
        .optional()
        .map_err(Into::into)
}

fn record_capture_event(
    transaction: &Transaction<'_>,
    item_id: &str,
    source_app_id: Option<&str>,
    source_confidence: SourceConfidence,
    pasteboard_change_count: i64,
    self_write_token: Option<&str>,
    now: i64,
) -> Result<()> {
    let capture_id = stable_hash(&format!("{item_id}:{pasteboard_change_count}:{now}"));
    transaction.execute(
        r#"
        INSERT OR IGNORE INTO clipboard_captures (
            id, item_id, source_app_id, source_confidence,
            pasteboard_change_count, self_write_token, captured_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
        "#,
        params![
            format!("capture_{capture_id}"),
            item_id,
            source_app_id,
            source_confidence.as_str(),
            pasteboard_change_count,
            self_write_token,
            now
        ],
    )?;
    Ok(())
}

fn update_search_index(
    transaction: &Transaction<'_>,
    item_id: &str,
    summary: &str,
    primary_text: &str,
    source_app_name: &str,
) -> Result<()> {
    let rowid = transaction.query_row(
        "SELECT rowid FROM clipboard_items WHERE id = ?1",
        params![item_id],
        |row| row.get::<_, i64>(0),
    )?;
    transaction.execute(
        r#"
        INSERT OR REPLACE INTO clipboard_items_fts (rowid, summary, primary_text, source_app_name)
        VALUES (?1, ?2, ?3, ?4)
        "#,
        params![rowid, summary, primary_text, source_app_name],
    )?;
    Ok(())
}
