use crate::domain::{
    CaptureDetectedLink, CaptureFilesRequest, CaptureImageRequest, CaptureResult,
    CaptureTextRequest, CapturedFileMetadata, LinkMetadataState, SourceConfidence,
};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use rusqlite::{params, OptionalExtension, Transaction};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

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
        let detected_link = normalized_detected_link(&normalized_text, request.detected_link);
        let item_type = detected_link
            .as_ref()
            .map(|_| crate::domain::ClipboardItemType::Link)
            .unwrap_or_else(|| classify_text(&normalized_text));
        let summary = detected_link
            .as_ref()
            .map(|link| link.display_url.clone())
            .unwrap_or_else(|| summarize_text(&normalized_text));
        let content_hash = detected_link
            .as_ref()
            .map(|link| stable_hash(&format!("link:{}", link.canonical_url)))
            .unwrap_or_else(|| stable_hash(&format!("{}:{normalized_text}", item_type.as_str())));
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
        if let Some(detected_link) = detected_link.as_ref() {
            upsert_link_metadata(&transaction, &item_id, detected_link, now)?;
        }

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
        let file_items = captured_file_metadata_for_paths(&file_paths, &request.file_items);
        let primary_text = file_paths.join("\n");
        let summary = summarize_files(&file_paths);
        let content_hash = stable_hash(&format!("file:{}", file_paths_fingerprint(&file_paths)));
        let snapshot_relative_path = request
            .snapshot_relative_path
            .as_deref()
            .map(normalize_relative_asset_path)
            .transpose()?;
        let preview_relative_path = request
            .preview_relative_path
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
        let metadata_byte_count: i64 = file_items.iter().map(|item| item.byte_count.max(0)).sum();
        let size_bytes = metadata_byte_count
            .max(request.preview_byte_count)
            .max(request.snapshot_byte_count)
            .max(primary_text.len() as i64);
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

        replace_file_items(&transaction, &item_id, &file_items, now)?;

        if let Some(preview_relative_path) = preview_relative_path.as_deref() {
            let preview_path = root.join(preview_relative_path);
            let preview_digest = hash_file(&preview_path)?;
            let preview_byte_count = fs::metadata(&preview_path)?.len() as i64;
            let preview_mime_type = request
                .preview_mime_type
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or("image/png");
            insert_asset(
                &transaction,
                &item_id,
                "thumbnail",
                preview_mime_type,
                preview_relative_path,
                preview_byte_count,
                positive_dimension(request.preview_width.unwrap_or_default()),
                positive_dimension(request.preview_height.unwrap_or_default()),
                &preview_digest,
                now,
            )?;
        }

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

fn normalized_detected_link(
    normalized_text: &str,
    detected_link: Option<CaptureDetectedLink>,
) -> Option<CaptureDetectedLink> {
    match detected_link {
        Some(link) if is_valid_detected_link(&link) => Some(CaptureDetectedLink {
            original_text: non_empty_or(link.original_text, normalized_text),
            canonical_url: link.canonical_url.trim().to_string(),
            display_url: non_empty_or(link.display_url, normalized_text),
            host: link.host.trim().to_ascii_lowercase(),
            metadata_state: link.metadata_state,
        }),
        _ => fallback_detected_link(normalized_text),
    }
}

fn is_valid_detected_link(link: &CaptureDetectedLink) -> bool {
    let canonical_url = link.canonical_url.trim().to_ascii_lowercase();
    let host = link.host.trim();
    !host.is_empty()
        && (canonical_url.starts_with("https://") || canonical_url.starts_with("http://"))
}

fn fallback_detected_link(normalized_text: &str) -> Option<CaptureDetectedLink> {
    let lower = normalized_text.to_ascii_lowercase();
    if !(lower.starts_with("https://") || lower.starts_with("http://")) {
        return None;
    }

    let host = host_from_http_url(normalized_text)?;
    Some(CaptureDetectedLink {
        original_text: normalized_text.to_string(),
        canonical_url: normalized_text.to_string(),
        display_url: normalized_text.to_string(),
        host,
        metadata_state: LinkMetadataState::Pending,
    })
}

fn host_from_http_url(url: &str) -> Option<String> {
    let scheme_separator = url.find("://")?;
    let after_scheme = &url[scheme_separator + 3..];
    let host_end = after_scheme
        .find(|character| matches!(character, '/' | '?' | '#'))
        .unwrap_or(after_scheme.len());
    let host = after_scheme[..host_end].trim().trim_matches('.');
    if host.is_empty() {
        None
    } else {
        Some(host.to_ascii_lowercase())
    }
}

fn non_empty_or(value: String, fallback: &str) -> String {
    let value = value.trim();
    if value.is_empty() {
        fallback.to_string()
    } else {
        value.to_string()
    }
}

fn upsert_link_metadata(
    transaction: &Transaction<'_>,
    item_id: &str,
    link: &CaptureDetectedLink,
    now: i64,
) -> Result<()> {
    transaction.execute(
        r#"
        INSERT INTO link_metadata (
            item_id,
            original_text,
            canonical_url,
            display_url,
            host,
            metadata_state,
            created_at_ms,
            updated_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
        ON CONFLICT(item_id) DO UPDATE SET
            original_text = excluded.original_text,
            canonical_url = excluded.canonical_url,
            display_url = excluded.display_url,
            host = excluded.host,
            metadata_state = CASE
                WHEN link_metadata.metadata_state = 'ready' THEN link_metadata.metadata_state
                ELSE link_metadata.metadata_state
            END,
            updated_at_ms = excluded.updated_at_ms
        "#,
        params![
            item_id,
            link.original_text.as_str(),
            link.canonical_url.as_str(),
            link.display_url.as_str(),
            link.host.as_str(),
            link.metadata_state.as_str(),
            now
        ],
    )?;
    Ok(())
}

fn captured_file_metadata_for_paths(
    file_paths: &[String],
    provided_items: &[CapturedFileMetadata],
) -> Vec<CapturedFileMetadata> {
    let provided_by_path: HashMap<String, &CapturedFileMetadata> = provided_items
        .iter()
        .map(|item| (normalized_metadata_path(&item.path), item))
        .collect();

    file_paths
        .iter()
        .map(|path| {
            let normalized_path = normalized_metadata_path(path);
            provided_by_path
                .get(&normalized_path)
                .map(|metadata| normalized_file_metadata(&normalized_path, Some(metadata)))
                .unwrap_or_else(|| normalized_file_metadata(&normalized_path, None))
        })
        .collect()
}

fn normalized_metadata_path(path: &str) -> String {
    Path::new(path).to_string_lossy().trim().to_string()
}

fn normalized_file_metadata(
    path: &str,
    provided: Option<&&CapturedFileMetadata>,
) -> CapturedFileMetadata {
    let path_value = path.trim().to_string();
    let path_ref = Path::new(&path_value);
    let metadata = fs::metadata(path_ref).ok();
    let is_directory = provided.map(|item| item.is_directory).unwrap_or_else(|| {
        metadata
            .as_ref()
            .map(|value| value.is_dir())
            .unwrap_or(false)
    });
    let byte_count = provided
        .map(|item| item.byte_count.max(0))
        .unwrap_or_else(|| {
            metadata
                .as_ref()
                .map(|value| {
                    if value.is_dir() {
                        0
                    } else {
                        value.len() as i64
                    }
                })
                .unwrap_or(0)
        });
    let file_name = provided
        .and_then(|item| non_empty_optional(item.file_name.as_str()))
        .or_else(|| {
            path_ref
                .file_name()
                .map(|value| value.to_string_lossy().to_string())
                .filter(|value| !value.trim().is_empty())
        })
        .unwrap_or_else(|| path_value.clone());
    let file_extension = provided
        .and_then(|item| item.file_extension.as_deref().and_then(non_empty_optional))
        .or_else(|| {
            path_ref
                .extension()
                .map(|value| value.to_string_lossy().to_string())
                .filter(|value| !value.trim().is_empty())
        });

    CapturedFileMetadata {
        path: path_value,
        file_name,
        file_extension,
        byte_count,
        is_directory,
        width: provided.and_then(|item| positive_optional_dimension(item.width)),
        height: provided.and_then(|item| positive_optional_dimension(item.height)),
        content_type: provided
            .and_then(|item| item.content_type.as_deref().and_then(non_empty_optional)),
    }
}

fn non_empty_optional(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn positive_optional_dimension(value: Option<i64>) -> Option<i64> {
    value.filter(|dimension| *dimension > 0)
}

fn replace_file_items(
    transaction: &Transaction<'_>,
    item_id: &str,
    file_items: &[CapturedFileMetadata],
    now: i64,
) -> Result<()> {
    transaction.execute(
        "DELETE FROM clipboard_file_items WHERE item_id = ?1",
        params![item_id],
    )?;

    for (index, item) in file_items.iter().enumerate() {
        let id = format!(
            "file_item_{}",
            &stable_hash(&format!("{item_id}:{}:{}", index, item.path))[..24]
        );
        transaction.execute(
            r#"
            INSERT INTO clipboard_file_items (
                id, item_id, order_index, path, file_name, file_extension,
                byte_count, is_directory, width, height, content_type,
                created_at_ms, updated_at_ms
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?12)
            "#,
            params![
                id,
                item_id,
                index as i64,
                item.path,
                item.file_name,
                item.file_extension,
                item.byte_count,
                if item.is_directory { 1 } else { 0 },
                item.width,
                item.height,
                item.content_type,
                now
            ],
        )?;
    }

    Ok(())
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
