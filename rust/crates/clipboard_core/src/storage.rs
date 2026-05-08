use crate::domain::{
    CaptureFilesRequest, CaptureImageRequest, CaptureResult, CaptureTextRequest,
    ClipboardItemSummary, ClipboardItemType, CoreInfo, ItemManagementResult, ItemPage, ItemQuery,
    MaintenanceResult, PageRequest, PreferencesDocument, PreviewState, SourceAppPage,
    SourceAppSummary, SourceConfidence,
};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::migrations::run_migrations;
use crate::time::now_ms;
use crate::{CURRENT_SCHEMA_VERSION, DATABASE_FILE_NAME};
use rusqlite::types::Value;
use rusqlite::{params, params_from_iter, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

const MILLIS_PER_DAY: i64 = 24 * 60 * 60 * 1000;

struct SourceAppInput<'a> {
    bundle_id: Option<&'a str>,
    app_name: Option<&'a str>,
    bundle_path: Option<&'a str>,
    icon_relative_path: Option<&'a str>,
}

pub struct ClipboardCore {
    database_path: PathBuf,
    connection: Connection,
}

impl ClipboardCore {
    pub fn open(app_support_dir: impl AsRef<Path>) -> Result<Self> {
        let app_support_dir = app_support_dir.as_ref();
        fs::create_dir_all(app_support_dir)?;

        for directory in ["assets", "thumbnails", "app-icons", "staging"] {
            fs::create_dir_all(app_support_dir.join(directory))?;
        }

        let database_path = app_support_dir.join(DATABASE_FILE_NAME);
        let mut connection = Connection::open(&database_path).map_err(|error| {
            CoreError::new(CoreErrorCode::DatabaseUnavailable, error.to_string())
                .with_detail("path", database_path.display().to_string())
        })?;

        connection
            .execute_batch(
                r#"
                PRAGMA foreign_keys = ON;
                PRAGMA journal_mode = WAL;
                "#,
            )
            .map_err(|error| {
                CoreError::new(CoreErrorCode::DatabaseUnavailable, error.to_string())
                    .with_detail("path", database_path.display().to_string())
            })?;

        run_migrations(&mut connection)?;
        seed_default_preferences(&connection)?;

        let mut core = Self {
            database_path,
            connection,
        };
        let preferences = core.get_preferences()?;
        core.apply_history_preferences(&preferences)?;

        Ok(core)
    }

    pub fn info(&self) -> Result<CoreInfo> {
        let item_count = self.active_item_count(&ItemQuery::default())?;
        Ok(CoreInfo {
            database_path: self.database_path.display().to_string(),
            schema_version: CURRENT_SCHEMA_VERSION,
            item_count,
        })
    }

    pub fn get_preferences(&self) -> Result<PreferencesDocument> {
        let value_json: String = self.connection.query_row(
            "SELECT value_json FROM preference_documents WHERE id = 'current'",
            [],
            |row| row.get(0),
        )?;
        parse_preferences_document(&value_json)
    }

    pub fn update_preferences(
        &mut self,
        preferences: PreferencesDocument,
    ) -> Result<PreferencesDocument> {
        let preferences = preferences.normalized();
        let value_json = serde_json::to_string(&preferences).map_err(|error| {
            CoreError::new(
                CoreErrorCode::InvalidInput,
                format!("preferences serialization failed: {error}"),
            )
        })?;
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        transaction.execute(
            r#"
            UPDATE preference_documents
            SET schema_version = ?1, value_json = ?2, updated_at_ms = ?3
            WHERE id = 'current'
            "#,
            params![CURRENT_SCHEMA_VERSION, value_json, now],
        )?;
        transaction.commit()?;
        self.apply_history_preferences(&preferences)?;
        Ok(preferences)
    }

    pub fn database_path(&self) -> &Path {
        &self.database_path
    }

    pub fn run_maintenance(&mut self) -> Result<MaintenanceResult> {
        let root = self
            .database_path
            .parent()
            .ok_or_else(|| {
                CoreError::new(
                    CoreErrorCode::IoFailed,
                    "database path does not have a parent directory",
                )
            })?
            .to_path_buf();
        let removable_asset_paths = self.removable_asset_paths()?;
        let mut result = MaintenanceResult::default();

        for relative_path in unique_strings(removable_asset_paths) {
            if let Some(byte_count) = delete_relative_file(&root, &relative_path)? {
                result.deleted_asset_file_count += 1;
                result.reclaimed_bytes += byte_count;
            }
        }

        let referenced_asset_paths = self.referenced_asset_paths()?;
        for relative_path in collect_maintenance_files(&root)? {
            if should_remove_unreferenced_file(&relative_path, &referenced_asset_paths) {
                if let Some(byte_count) = delete_relative_file(&root, &relative_path)? {
                    result.deleted_orphan_file_count += 1;
                    result.reclaimed_bytes += byte_count;
                }
            }
        }
        remove_empty_maintenance_directories(&root)?;

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
        let source_app_name = request.source_app_name.clone();
        let source_confidence = request.source_confidence;
        let size_bytes = normalized_text.len() as i64;
        let transaction = self.connection.transaction()?;

        let existing = transaction
            .query_row(
                "SELECT id, copy_count FROM clipboard_items WHERE content_hash = ?1 AND deleted_at_ms IS NULL",
                params![content_hash],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional()?;

        let (item_id, copy_count, inserted) = match existing {
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
                        source_app_id,
                        source_app_name,
                        source_confidence.as_str(),
                        item_id
                    ],
                )?;
                (item_id, next_copy_count, false)
            }
            None => {
                let item_id = format!("item_{}", &content_hash[..24]);
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
                        source_app_id,
                        source_app_name,
                        source_confidence.as_str(),
                        now,
                        size_bytes
                    ],
                )?;
                (item_id, 1, true)
            }
        };

        let capture_id = stable_hash(&format!(
            "{}:{}:{}",
            item_id, request.pasteboard_change_count, now
        ));
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
                request.pasteboard_change_count,
                request.self_write_token,
                now
            ],
        )?;

        let rowid = transaction.query_row(
            "SELECT rowid FROM clipboard_items WHERE id = ?1",
            params![item_id],
            |row| row.get::<_, i64>(0),
        )?;
        let source_name_for_fts = request.source_app_name.unwrap_or_default();
        transaction.execute(
            r#"
            INSERT OR REPLACE INTO clipboard_items_fts (rowid, summary, primary_text, source_app_name)
            VALUES (?1, ?2, ?3, ?4)
            "#,
            params![rowid, summary, normalized_text, source_name_for_fts],
        )?;

        transaction.commit()?;

        let preferences = self.get_preferences()?;
        self.apply_history_preferences(&preferences)?;

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
        let root = self.database_path.parent().ok_or_else(|| {
            CoreError::new(
                CoreErrorCode::IoFailed,
                "database path does not have a parent directory",
            )
        })?;
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
        let source_app_name = request.source_app_name.clone();
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

        let existing = transaction
            .query_row(
                "SELECT id, copy_count FROM clipboard_items WHERE content_hash = ?1 AND deleted_at_ms IS NULL",
                params![content_hash],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional()?;

        let (item_id, copy_count, inserted) = match existing {
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
                        source_app_id,
                        source_app_name,
                        source_confidence.as_str(),
                        byte_count,
                        item_id
                    ],
                )?;
                (item_id, next_copy_count, false)
            }
            None => {
                let item_id = format!("item_{}", &content_hash[..24]);
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
                        source_app_id,
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

        let capture_id = stable_hash(&format!(
            "{}:{}:{}",
            item_id, request.pasteboard_change_count, now
        ));
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
                request.pasteboard_change_count,
                request.self_write_token,
                now
            ],
        )?;

        let rowid = transaction.query_row(
            "SELECT rowid FROM clipboard_items WHERE id = ?1",
            params![item_id],
            |row| row.get::<_, i64>(0),
        )?;
        let source_name_for_fts = request.source_app_name.unwrap_or_default();
        transaction.execute(
            r#"
            INSERT OR REPLACE INTO clipboard_items_fts (rowid, summary, primary_text, source_app_name)
            VALUES (?1, ?2, '', ?3)
            "#,
            params![rowid, summary, source_name_for_fts],
        )?;

        transaction.commit()?;

        let preferences = self.get_preferences()?;
        self.apply_history_preferences(&preferences)?;

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
        let root = self.database_path.parent().ok_or_else(|| {
            CoreError::new(
                CoreErrorCode::IoFailed,
                "database path does not have a parent directory",
            )
        })?;
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
        let source_app_name = request.source_app_name.clone();
        let source_confidence = request.source_confidence;
        let size_bytes = request
            .snapshot_byte_count
            .max(primary_text.as_bytes().len() as i64);
        let transaction = self.connection.transaction()?;

        let existing = transaction
            .query_row(
                "SELECT id, copy_count FROM clipboard_items WHERE content_hash = ?1 AND deleted_at_ms IS NULL",
                params![content_hash],
                |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
            )
            .optional()?;

        let (item_id, copy_count, inserted) = match existing {
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
                        source_app_id,
                        source_app_name,
                        source_confidence.as_str(),
                        size_bytes,
                        item_id
                    ],
                )?;
                (item_id, next_copy_count, false)
            }
            None => {
                let item_id = format!("item_{}", &content_hash[..24]);
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
                        source_app_id,
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
            params![format_id, item_id, primary_text.as_bytes().len() as i64],
        )?;

        let capture_id = stable_hash(&format!(
            "{}:{}:{}",
            item_id, request.pasteboard_change_count, now
        ));
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
                request.pasteboard_change_count,
                request.self_write_token,
                now
            ],
        )?;

        let rowid = transaction.query_row(
            "SELECT rowid FROM clipboard_items WHERE id = ?1",
            params![item_id],
            |row| row.get::<_, i64>(0),
        )?;
        let source_name_for_fts = request.source_app_name.unwrap_or_default();
        transaction.execute(
            r#"
            INSERT OR REPLACE INTO clipboard_items_fts (rowid, summary, primary_text, source_app_name)
            VALUES (?1, ?2, ?3, ?4)
            "#,
            params![rowid, summary, primary_text, source_name_for_fts],
        )?;

        transaction.commit()?;

        let preferences = self.get_preferences()?;
        self.apply_history_preferences(&preferences)?;

        Ok(CaptureResult {
            item_id,
            content_hash,
            copy_count,
            inserted,
        })
    }

    pub fn list_items(&self, query: ItemQuery, page: PageRequest) -> Result<ItemPage> {
        let page = page.normalized();
        let total_count = self.active_item_count(&query)?;
        let mut sql = String::from(
            r#"
            SELECT
                i.id,
                i.type,
                i.summary,
                i.primary_text,
                i.content_hash,
                i.source_app_id,
                COALESCE(s.name, i.source_app_name),
                ic.relative_path,
                (
                    SELECT a.relative_path
                    FROM clipboard_assets a
                    WHERE a.item_id = i.id AND a.kind IN ('thumbnail', 'payload', 'file_snapshot')
                    ORDER BY
                        CASE a.kind
                            WHEN 'thumbnail' THEN 0
                            WHEN 'payload' THEN 1
                            ELSE 2
                        END,
                        a.created_at_ms DESC
                    LIMIT 1
                ),
                (
                    SELECT a.relative_path
                    FROM clipboard_assets a
                    WHERE a.item_id = i.id AND a.kind IN ('payload', 'file_snapshot')
                    ORDER BY
                        CASE a.kind WHEN 'payload' THEN 0 ELSE 1 END,
                        a.created_at_ms DESC
                    LIMIT 1
                ),
                i.source_confidence,
                i.first_copied_at_ms,
                i.last_copied_at_ms,
                i.copy_count,
                i.is_pinned,
                i.size_bytes,
                i.preview_state
            FROM clipboard_items i
            LEFT JOIN source_apps s ON s.id = i.source_app_id
            LEFT JOIN source_app_icons ic ON ic.source_app_id = s.id
            WHERE i.deleted_at_ms IS NULL
            "#,
        );

        let mut filter_params = append_query_filters(&mut sql, &query);
        sql.push_str(" ORDER BY i.is_pinned DESC, i.last_copied_at_ms DESC LIMIT ? OFFSET ?");
        filter_params.push(Value::Integer(page.limit));
        filter_params.push(Value::Integer(page.offset));

        let mut statement = self.connection.prepare(&sql)?;
        let rows = statement.query_map(params_from_iter(filter_params.iter()), map_item_summary)?;

        let items = rows.collect::<std::result::Result<Vec<_>, _>>()?;
        let items: Vec<ClipboardItemSummary> = items
            .into_iter()
            .map(|item| self.with_absolute_paths(item))
            .collect();

        Ok(ItemPage {
            has_more: page.offset + (items.len() as i64) < total_count,
            items,
            total_count,
        })
    }

    pub fn list_source_apps(&self, page: PageRequest) -> Result<SourceAppPage> {
        let page = page.normalized();
        let total_count = self.active_source_app_count()?;
        let mut statement = self.connection.prepare(
            r#"
            SELECT
                s.id,
                s.bundle_id,
                s.name,
                (
                    SELECT ic.relative_path
                    FROM source_app_icons ic
                    WHERE ic.source_app_id = s.id
                    ORDER BY ic.updated_at_ms DESC
                    LIMIT 1
                ) AS icon_path,
                COUNT(i.id) AS item_count,
                MAX(i.last_copied_at_ms) AS last_copied_at_ms
            FROM source_apps s
            INNER JOIN clipboard_items i ON i.source_app_id = s.id
            WHERE i.deleted_at_ms IS NULL
            GROUP BY s.id, s.bundle_id, s.name
            ORDER BY last_copied_at_ms DESC, s.name COLLATE NOCASE ASC
            LIMIT ?1 OFFSET ?2
            "#,
        )?;
        let rows = statement.query_map(params![page.limit, page.offset], map_source_app_summary)?;
        let apps = rows
            .collect::<std::result::Result<Vec<_>, _>>()?
            .into_iter()
            .map(|app| self.with_absolute_source_app_path(app))
            .collect::<Vec<_>>();

        Ok(SourceAppPage {
            has_more: page.offset + (apps.len() as i64) < total_count,
            apps,
            total_count,
        })
    }

    pub fn set_item_pinned(
        &mut self,
        item_id: impl AsRef<str>,
        is_pinned: bool,
    ) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE clipboard_items
            SET is_pinned = ?1, updated_at_ms = ?2
            WHERE id = ?3 AND deleted_at_ms IS NULL
            "#,
            params![if is_pinned { 1 } else { 0 }, now, item_id],
        )? as i64;

        Ok(ItemManagementResult { affected_count })
    }

    pub fn delete_item(&mut self, item_id: impl AsRef<str>) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE clipboard_items
            SET deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE id = ?2 AND deleted_at_ms IS NULL
            "#,
            params![now, item_id],
        )? as i64;

        Ok(ItemManagementResult { affected_count })
    }

    pub fn clear_items(&mut self, query: ItemQuery) -> Result<ItemManagementResult> {
        let now = now_ms();
        let mut sql = String::from(
            r#"
            UPDATE clipboard_items
            SET deleted_at_ms = ?, updated_at_ms = ?
            WHERE id IN (
                SELECT i.id
                FROM clipboard_items i
                LEFT JOIN source_apps s ON s.id = i.source_app_id
                WHERE i.deleted_at_ms IS NULL
                    AND i.is_pinned = 0
            "#,
        );
        let mut query_params = append_query_filters(&mut sql, &query);
        sql.push_str(")");

        let mut params = Vec::with_capacity(query_params.len() + 2);
        params.push(Value::Integer(now));
        params.push(Value::Integer(now));
        params.append(&mut query_params);

        let affected_count = self
            .connection
            .execute(&sql, params_from_iter(params.iter()))? as i64;

        Ok(ItemManagementResult { affected_count })
    }

    fn apply_history_preferences(&mut self, preferences: &PreferencesDocument) -> Result<i64> {
        let preferences = preferences.clone().normalized();
        let now = now_ms();
        let retention_cutoff = now - preferences.history.retention_days * MILLIS_PER_DAY;
        let transaction = self.connection.transaction()?;
        let retention_deleted = transaction.execute(
            r#"
            UPDATE clipboard_items
            SET deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE deleted_at_ms IS NULL
                AND is_pinned = 0
                AND last_copied_at_ms < ?2
            "#,
            params![now, retention_cutoff],
        )?;
        let max_items_deleted = transaction.execute(
            r#"
            WITH ranked_items AS (
                SELECT
                    rowid,
                    ROW_NUMBER() OVER (
                        ORDER BY last_copied_at_ms DESC, id DESC
                    ) AS rank
                FROM clipboard_items
                WHERE deleted_at_ms IS NULL
                    AND is_pinned = 0
            )
            UPDATE clipboard_items
            SET deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE rowid IN (
                SELECT rowid
                FROM ranked_items
                WHERE rank > ?2
            )
            "#,
            params![now, preferences.history.max_items],
        )?;
        transaction.commit()?;

        Ok((retention_deleted + max_items_deleted) as i64)
    }

    fn active_item_count(&self, query: &ItemQuery) -> Result<i64> {
        let mut sql = String::from(
            r#"
            SELECT COUNT(*)
            FROM clipboard_items i
            LEFT JOIN source_apps s ON s.id = i.source_app_id
            WHERE i.deleted_at_ms IS NULL
            "#,
        );
        let filter_params = append_query_filters(&mut sql, query);
        let count =
            self.connection
                .query_row(&sql, params_from_iter(filter_params.iter()), |row| {
                    row.get::<_, i64>(0)
                })?;

        Ok(count)
    }

    fn active_source_app_count(&self) -> Result<i64> {
        let count = self.connection.query_row(
            r#"
            SELECT COUNT(DISTINCT i.source_app_id)
            FROM clipboard_items i
            WHERE i.deleted_at_ms IS NULL AND i.source_app_id IS NOT NULL
            "#,
            [],
            |row| row.get::<_, i64>(0),
        )?;

        Ok(count)
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
        let paths = statement
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
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

        Ok(paths.into_iter().collect())
    }

    fn upsert_source_app(&self, input: SourceAppInput<'_>, now: i64) -> Result<Option<String>> {
        let app_name = input
            .app_name
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let bundle_id = input
            .bundle_id
            .map(str::trim)
            .filter(|value| !value.is_empty());

        let Some(app_name) = app_name else {
            return Ok(None);
        };

        let derived_key = bundle_id
            .map(|value| format!("bundle:{value}"))
            .unwrap_or_else(|| format!("name:{}", app_name.to_lowercase()));
        let source_app_id = format!("source_{}", &stable_hash(&derived_key)[..24]);

        self.connection.execute(
            r#"
            INSERT INTO source_apps (
                id, bundle_id, derived_key, name, bundle_path,
                last_seen_at_ms, created_at_ms, updated_at_ms
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?6)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                bundle_path = excluded.bundle_path,
                last_seen_at_ms = excluded.last_seen_at_ms,
                updated_at_ms = excluded.updated_at_ms
            "#,
            params![
                source_app_id,
                bundle_id,
                if bundle_id.is_some() {
                    None::<String>
                } else {
                    Some(derived_key)
                },
                app_name,
                input.bundle_path,
                now
            ],
        )?;

        if let Some(relative_path) = input
            .icon_relative_path
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let cache_key = format!("{}:{relative_path}", source_app_id);
            let icon_id = format!("icon_{}", &stable_hash(&cache_key)[..24]);
            self.connection.execute(
                r#"
                INSERT INTO source_app_icons (
                    id, source_app_id, cache_key, relative_path,
                    byte_count, created_at_ms, updated_at_ms
                )
                VALUES (?1, ?2, ?3, ?4, 0, ?5, ?5)
                ON CONFLICT(cache_key) DO UPDATE SET
                    relative_path = excluded.relative_path,
                    updated_at_ms = excluded.updated_at_ms
                "#,
                params![icon_id, source_app_id, cache_key, relative_path, now],
            )?;
        }

        Ok(Some(source_app_id))
    }

    fn with_absolute_paths(&self, mut item: ClipboardItemSummary) -> ClipboardItemSummary {
        if let Some(relative_path) = item.source_app_icon_path.take() {
            if let Some(root) = self.database_path.parent() {
                item.source_app_icon_path = Some(root.join(relative_path).display().to_string());
            }
        }
        if let Some(relative_path) = item.preview_asset_path.take() {
            if let Some(root) = self.database_path.parent() {
                item.preview_asset_path = Some(root.join(relative_path).display().to_string());
            }
        }
        if let Some(relative_path) = item.payload_asset_path.take() {
            if let Some(root) = self.database_path.parent() {
                item.payload_asset_path = Some(root.join(relative_path).display().to_string());
            }
        }
        item
    }

    fn with_absolute_source_app_path(&self, mut app: SourceAppSummary) -> SourceAppSummary {
        if let Some(relative_path) = app.icon_path.take() {
            if let Some(root) = self.database_path.parent() {
                app.icon_path = Some(root.join(relative_path).display().to_string());
            }
        }
        app
    }
}

fn normalize_text(text: &str) -> String {
    text.trim_matches(|character: char| character == '\0')
        .trim()
        .to_string()
}

fn classify_text(text: &str) -> ClipboardItemType {
    let lower = text.to_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        ClipboardItemType::Link
    } else {
        ClipboardItemType::Text
    }
}

fn summarize_text(text: &str) -> String {
    const MAX_CHARS: usize = 180;
    let collapsed = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut summary = collapsed.chars().take(MAX_CHARS).collect::<String>();
    if collapsed.chars().count() > MAX_CHARS {
        summary.push('…');
    }
    summary
}

fn summarize_image(width: i64, height: i64) -> String {
    if width > 0 && height > 0 {
        format!("图片 {} x {}", width, height)
    } else {
        "图片".to_string()
    }
}

fn summarize_files(file_paths: &[String]) -> String {
    let first_name = file_paths
        .first()
        .and_then(|path| Path::new(path).file_name())
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .or_else(|| file_paths.first().map(String::as_str))
        .unwrap_or("文件");

    if file_paths.len() == 1 {
        first_name.to_string()
    } else {
        format!("{} 个文件 · {}", file_paths.len(), first_name)
    }
}

fn positive_dimension(value: i64) -> Option<i64> {
    (value > 0).then_some(value)
}

fn normalize_file_paths(file_paths: &[String]) -> Result<Vec<String>> {
    let mut seen = HashSet::new();
    let mut normalized_paths = Vec::new();

    for path in file_paths {
        let normalized_path = path.trim_matches('\0').to_string();
        if normalized_path.is_empty() {
            continue;
        }

        if seen.insert(normalized_path.clone()) {
            normalized_paths.push(normalized_path);
        }
    }

    if normalized_paths.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "file capture must contain at least one file path",
        ));
    }

    Ok(normalized_paths)
}

fn file_paths_fingerprint(file_paths: &[String]) -> String {
    let mut sorted_paths = file_paths.to_vec();
    sorted_paths.sort();
    sorted_paths.join("\n")
}

fn normalize_relative_asset_path(value: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "asset path cannot be empty",
        ));
    }

    let path = Path::new(value);
    if path.is_absolute()
        || path.components().any(|component| {
            matches!(
                component,
                std::path::Component::ParentDir | std::path::Component::RootDir
            )
        })
    {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "asset path must be relative to app support directory",
        ));
    }

    Ok(value.to_string())
}

fn unique_strings(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut unique_values = Vec::new();
    for value in values {
        if seen.insert(value.clone()) {
            unique_values.push(value);
        }
    }
    unique_values
}

fn delete_relative_file(root: &Path, relative_path: &str) -> Result<Option<i64>> {
    let relative_path = normalize_relative_asset_path(relative_path)?;
    let path = root.join(relative_path);
    let metadata = match fs::metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("path", path.display().to_string()));
        }
    };

    if !metadata.is_file() {
        return Ok(None);
    }

    fs::remove_file(&path).map_err(|error| {
        CoreError::new(CoreErrorCode::IoFailed, error.to_string())
            .with_detail("path", path.display().to_string())
    })?;
    Ok(Some(metadata.len() as i64))
}

fn collect_maintenance_files(root: &Path) -> Result<Vec<String>> {
    let mut files = Vec::new();
    for directory in ["assets", "thumbnails", "app-icons", "staging"] {
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
    relative_path: &str,
    referenced_paths: &HashSet<String>,
) -> bool {
    if relative_path.starts_with("staging/") {
        return true;
    }

    (relative_path.starts_with("assets/")
        || relative_path.starts_with("thumbnails/")
        || relative_path.starts_with("app-icons/"))
        && !referenced_paths.contains(relative_path)
}

fn remove_empty_maintenance_directories(root: &Path) -> Result<()> {
    for directory in ["assets", "thumbnails", "app-icons", "staging"] {
        remove_empty_child_directories(&root.join(directory))?;
    }
    Ok(())
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

fn hash_file(path: &Path) -> Result<String> {
    let data = fs::read(path).map_err(|error| {
        CoreError::new(CoreErrorCode::IoFailed, error.to_string())
            .with_detail("path", path.display().to_string())
    })?;
    Ok(stable_hash_bytes(&data))
}

fn stable_hash_bytes(value: &[u8]) -> String {
    let digest = Sha256::digest(value);
    digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>()
}

fn stable_hash(value: &str) -> String {
    stable_hash_bytes(value.as_bytes())
}

fn insert_asset(
    transaction: &rusqlite::Transaction<'_>,
    item_id: &str,
    kind: &str,
    mime_type: &str,
    relative_path: &str,
    byte_count: i64,
    width: Option<i64>,
    height: Option<i64>,
    content_hash: &str,
    now: i64,
) -> Result<()> {
    let asset_id = format!(
        "asset_{}",
        &stable_hash(&format!("{item_id}:{kind}:{content_hash}"))[..24]
    );
    transaction.execute(
        r#"
        INSERT OR IGNORE INTO clipboard_assets (
            id, item_id, kind, mime_type, relative_path, byte_count,
            width, height, content_hash, created_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
        "#,
        params![
            asset_id,
            item_id,
            kind,
            mime_type,
            relative_path,
            byte_count,
            width,
            height,
            content_hash,
            now
        ],
    )?;
    Ok(())
}

fn seed_default_preferences(connection: &Connection) -> Result<()> {
    let now = now_ms();
    let preferences = serde_json::to_string(&PreferencesDocument::default()).map_err(|error| {
        CoreError::new(
            CoreErrorCode::InvalidInput,
            format!("default preferences serialization failed: {error}"),
        )
    })?;

    connection.execute(
        r#"
        INSERT OR IGNORE INTO preference_documents (id, schema_version, value_json, updated_at_ms)
        VALUES ('current', ?1, ?2, ?3)
        "#,
        params![CURRENT_SCHEMA_VERSION, preferences, now],
    )?;
    Ok(())
}

fn parse_preferences_document(value_json: &str) -> Result<PreferencesDocument> {
    serde_json::from_str::<PreferencesDocument>(value_json)
        .map(PreferencesDocument::normalized)
        .map_err(|error| {
            CoreError::new(
                CoreErrorCode::InvalidInput,
                format!("preferences json is invalid: {error}"),
            )
        })
}

fn normalize_item_id(item_id: &str) -> Result<String> {
    let value = item_id.trim();
    if value.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "item id cannot be empty",
        ));
    }

    Ok(value.to_string())
}

fn append_query_filters(sql: &mut String, query: &ItemQuery) -> Vec<Value> {
    let mut params = Vec::new();

    if let Some(item_type) = query.item_type {
        sql.push_str(" AND i.type = ?");
        params.push(Value::Text(item_type.as_str().to_string()));
    }

    if let Some(source_app_id) = query.source_app_id.as_deref() {
        sql.push_str(" AND i.source_app_id = ?");
        params.push(Value::Text(source_app_id.to_string()));
    }

    if let Some(search_text) = query
        .search_text
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        sql.push_str(
            r#"
            AND (
                i.rowid IN (
                    SELECT rowid
                    FROM clipboard_items_fts
                    WHERE clipboard_items_fts MATCH ?
                )
                OR i.summary LIKE ? ESCAPE '\'
                OR COALESCE(i.primary_text, '') LIKE ? ESCAPE '\'
                OR COALESCE(s.name, i.source_app_name, '') LIKE ? ESCAPE '\'
            )
            "#,
        );
        params.push(Value::Text(make_fts_query(search_text)));
        let like_query = make_like_query(search_text);
        params.push(Value::Text(like_query.clone()));
        params.push(Value::Text(like_query.clone()));
        params.push(Value::Text(like_query));
    }

    params
}

fn make_fts_query(search_text: &str) -> String {
    let terms = search_text
        .split_whitespace()
        .map(|term| term.trim_matches(|character: char| character.is_ascii_punctuation()))
        .filter(|term| !term.is_empty())
        .take(8)
        .map(|term| format!("\"{}\"", term.replace('"', "\"\"")))
        .collect::<Vec<_>>();

    if terms.is_empty() {
        format!("\"{}\"", search_text.replace('"', "\"\""))
    } else {
        terms.join(" AND ")
    }
}

fn make_like_query(search_text: &str) -> String {
    let escaped = search_text
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_");
    format!("%{escaped}%")
}

fn map_item_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<ClipboardItemSummary> {
    let item_type = row.get::<_, String>(1)?;
    let source_confidence = row.get::<_, String>(10)?;
    let preview_state = row.get::<_, String>(16)?;

    Ok(ClipboardItemSummary {
        id: row.get(0)?,
        item_type: ClipboardItemType::from_storage(&item_type),
        summary: row.get(2)?,
        primary_text: row.get(3)?,
        content_hash: row.get(4)?,
        source_app_id: row.get(5)?,
        source_app_name: row.get(6)?,
        source_app_icon_path: row.get(7)?,
        preview_asset_path: row.get(8)?,
        payload_asset_path: row.get(9)?,
        source_confidence: SourceConfidence::from_storage(&source_confidence),
        first_copied_at_ms: row.get(11)?,
        last_copied_at_ms: row.get(12)?,
        copy_count: row.get(13)?,
        is_pinned: row.get::<_, i64>(14)? == 1,
        size_bytes: row.get(15)?,
        preview_state: PreviewState::from_storage(&preview_state),
    })
}

fn map_source_app_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<SourceAppSummary> {
    Ok(SourceAppSummary {
        id: row.get(0)?,
        bundle_id: row.get(1)?,
        name: row.get(2)?,
        icon_path: row.get(3)?,
        item_count: row.get(4)?,
        last_copied_at_ms: row.get(5)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::CoreErrorCode;
    use tempfile::TempDir;

    fn open_temp_core() -> (TempDir, ClipboardCore) {
        let temp_dir = TempDir::new().expect("temp dir");
        let core = ClipboardCore::open(temp_dir.path()).expect("open core");
        (temp_dir, core)
    }

    #[test]
    fn open_creates_database_schema_and_asset_directories() {
        let (temp_dir, core) = open_temp_core();

        assert!(temp_dir.path().join(DATABASE_FILE_NAME).exists());
        assert!(temp_dir.path().join("assets").is_dir());
        assert!(temp_dir.path().join("thumbnails").is_dir());
        assert!(temp_dir.path().join("app-icons").is_dir());
        assert!(temp_dir.path().join("staging").is_dir());
        assert_eq!(core.info().unwrap().schema_version, CURRENT_SCHEMA_VERSION);

        let migration_count: i64 = core
            .connection
            .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(migration_count, 1);
    }

    #[test]
    fn new_database_lists_empty_history() {
        let (_, core) = open_temp_core();
        let page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();

        assert!(page.items.is_empty());
        assert_eq!(page.total_count, 0);
        assert!(!page.has_more);
    }

    #[test]
    fn capture_text_inserts_source_and_updates_empty_history() {
        let (_, mut core) = open_temp_core();

        let result = core
            .capture_text(CaptureTextRequest {
                text: "Hello from Safari".to_string(),
                source_bundle_id: Some("com.apple.Safari".to_string()),
                source_app_name: Some("Safari".to_string()),
                source_bundle_path: Some("/Applications/Safari.app".to_string()),
                source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: 10,
                self_write_token: None,
            })
            .unwrap();

        assert!(result.inserted);
        assert_eq!(result.copy_count, 1);

        let page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();
        assert_eq!(page.total_count, 1);
        assert_eq!(page.items.len(), 1);
        assert_eq!(page.items[0].summary, "Hello from Safari");
        assert_eq!(page.items[0].source_app_name.as_deref(), Some("Safari"));
        assert!(page.items[0]
            .source_app_icon_path
            .as_deref()
            .unwrap()
            .ends_with("app-icons/safari.tiff"));

        let capture_count: i64 = core
            .connection
            .query_row("SELECT COUNT(*) FROM clipboard_captures", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(capture_count, 1);

        let fts_count: i64 = core
            .connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH 'Safari'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(fts_count, 1);
    }

    #[test]
    fn capture_text_deduplicates_by_content_hash() {
        let (_, mut core) = open_temp_core();

        let request = CaptureTextRequest {
            text: "https://example.com".to_string(),
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        };

        let first = core.capture_text(request.clone()).unwrap();
        let second = core
            .capture_text(CaptureTextRequest {
                pasteboard_change_count: 2,
                ..request
            })
            .unwrap();

        assert!(first.inserted);
        assert!(!second.inserted);
        assert_eq!(first.item_id, second.item_id);
        assert_eq!(second.copy_count, 2);

        let page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();
        assert_eq!(page.total_count, 1);
        assert_eq!(page.items[0].item_type, ClipboardItemType::Link);
        assert_eq!(page.items[0].copy_count, 2);
    }

    #[test]
    fn capture_image_inserts_asset_preview_and_source() {
        let (temp_dir, mut core) = open_temp_core();
        fs::write(
            temp_dir.path().join("assets/sample.png"),
            b"sample image payload",
        )
        .expect("payload");
        fs::write(
            temp_dir.path().join("thumbnails/sample.png"),
            b"sample image thumbnail",
        )
        .expect("thumbnail");

        let result = core
            .capture_image(CaptureImageRequest {
                payload_relative_path: "assets/sample.png".to_string(),
                preview_relative_path: Some("thumbnails/sample.png".to_string()),
                mime_type: Some("image/png".to_string()),
                width: 640,
                height: 360,
                byte_count: 20,
                source_bundle_id: Some("com.apple.Preview".to_string()),
                source_app_name: Some("Preview".to_string()),
                source_bundle_path: Some("/System/Applications/Preview.app".to_string()),
                source_icon_relative_path: Some("app-icons/preview.tiff".to_string()),
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: 33,
                self_write_token: None,
            })
            .unwrap();

        assert!(result.inserted);
        assert_eq!(result.copy_count, 1);

        let page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();
        assert_eq!(page.total_count, 1);
        assert_eq!(page.items[0].item_type, ClipboardItemType::Image);
        assert_eq!(page.items[0].summary, "图片 640 x 360");
        assert_eq!(page.items[0].source_app_name.as_deref(), Some("Preview"));
        assert!(page.items[0]
            .preview_asset_path
            .as_deref()
            .unwrap()
            .ends_with("thumbnails/sample.png"));

        let asset_count: i64 = core
            .connection
            .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(asset_count, 2);

        let capture_count: i64 = core
            .connection
            .query_row("SELECT COUNT(*) FROM clipboard_captures", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(capture_count, 1);

        let fts_count: i64 = core
            .connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH 'Preview'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(fts_count, 1);
    }

    #[test]
    fn capture_files_inserts_snapshot_and_source() {
        let (temp_dir, mut core) = open_temp_core();
        fs::create_dir_all(temp_dir.path().join("assets/file-snapshots")).expect("snapshot dir");
        fs::write(
            temp_dir.path().join("assets/file-snapshots/files.json"),
            r#"{"paths":["/Users/evan/Desktop/report.pdf","/Users/evan/Desktop/design.sketch"]}"#,
        )
        .expect("snapshot");

        let result = core
            .capture_files(CaptureFilesRequest {
                file_paths: vec![
                    "/Users/evan/Desktop/report.pdf".to_string(),
                    "/Users/evan/Desktop/design.sketch".to_string(),
                ],
                snapshot_relative_path: Some("assets/file-snapshots/files.json".to_string()),
                snapshot_byte_count: 78,
                source_bundle_id: Some("com.apple.finder".to_string()),
                source_app_name: Some("Finder".to_string()),
                source_bundle_path: Some("/System/Library/CoreServices/Finder.app".to_string()),
                source_icon_relative_path: Some("app-icons/finder.tiff".to_string()),
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: 44,
                self_write_token: None,
            })
            .unwrap();

        assert!(result.inserted);
        assert_eq!(result.copy_count, 1);

        let page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();
        assert_eq!(page.total_count, 1);
        assert_eq!(page.items[0].item_type, ClipboardItemType::File);
        assert_eq!(page.items[0].summary, "2 个文件 · report.pdf");
        assert!(page.items[0]
            .primary_text
            .as_deref()
            .unwrap()
            .contains("design.sketch"));
        assert_eq!(page.items[0].source_app_name.as_deref(), Some("Finder"));
        assert!(page.items[0]
            .payload_asset_path
            .as_deref()
            .unwrap()
            .ends_with("assets/file-snapshots/files.json"));

        let asset_count: i64 = core
            .connection
            .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(asset_count, 1);

        let format_count: i64 = core
            .connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_formats WHERE uti = 'public.file-url'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(format_count, 1);
    }

    #[test]
    fn list_items_filters_by_type_and_search_text() {
        let (temp_dir, mut core) = open_temp_core();
        core.capture_text(CaptureTextRequest {
            text: "Alpha search target from Safari".to_string(),
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
        fs::write(
            temp_dir.path().join("assets/filter.png"),
            b"filter image payload",
        )
        .expect("payload");
        core.capture_image(CaptureImageRequest {
            payload_relative_path: "assets/filter.png".to_string(),
            preview_relative_path: None,
            mime_type: Some("image/png".to_string()),
            width: 400,
            height: 300,
            byte_count: 20,
            source_bundle_id: Some("com.apple.Preview".to_string()),
            source_app_name: Some("Preview".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();

        let image_page = core
            .list_items(
                ItemQuery {
                    item_type: Some(ClipboardItemType::Image),
                    ..ItemQuery::default()
                },
                PageRequest::default(),
            )
            .unwrap();
        assert_eq!(image_page.total_count, 1);
        assert_eq!(image_page.items[0].item_type, ClipboardItemType::Image);

        let search_page = core
            .list_items(
                ItemQuery {
                    search_text: Some("Alpha Safari".to_string()),
                    ..ItemQuery::default()
                },
                PageRequest::default(),
            )
            .unwrap();
        assert_eq!(search_page.total_count, 1);
        assert_eq!(
            search_page.items[0].source_app_name.as_deref(),
            Some("Safari")
        );
    }

    #[test]
    fn list_source_apps_and_filter_items_by_source_app_id() {
        let (temp_dir, mut core) = open_temp_core();
        core.capture_text(CaptureTextRequest {
            text: "Source filter text from Safari".to_string(),
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        fs::write(
            temp_dir.path().join("assets/source-preview.png"),
            b"source filter image payload",
        )
        .expect("payload");
        core.capture_image(CaptureImageRequest {
            payload_relative_path: "assets/source-preview.png".to_string(),
            preview_relative_path: None,
            mime_type: Some("image/png".to_string()),
            width: 120,
            height: 90,
            byte_count: 27,
            source_bundle_id: Some("com.apple.Preview".to_string()),
            source_app_name: Some("Preview".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: Some("app-icons/preview.tiff".to_string()),
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();

        let source_page = core
            .list_source_apps(PageRequest {
                limit: 10,
                offset: 0,
            })
            .unwrap();
        assert_eq!(source_page.total_count, 2);
        assert_eq!(source_page.apps.len(), 2);
        assert_eq!(source_page.apps[0].name, "Preview");
        assert_eq!(source_page.apps[0].item_count, 1);
        assert!(source_page.apps[0]
            .icon_path
            .as_deref()
            .unwrap()
            .ends_with("app-icons/preview.tiff"));

        let safari = source_page
            .apps
            .iter()
            .find(|app| app.name == "Safari")
            .expect("Safari source");
        let safari_page = core
            .list_items(
                ItemQuery {
                    source_app_id: Some(safari.id.clone()),
                    ..ItemQuery::default()
                },
                PageRequest::default(),
            )
            .unwrap();
        assert_eq!(safari_page.total_count, 1);
        assert_eq!(
            safari_page.items[0].source_app_name.as_deref(),
            Some("Safari")
        );
    }

    #[test]
    fn item_management_pins_and_soft_deletes_single_item() {
        let (_, mut core) = open_temp_core();
        let pinned = core
            .capture_text(CaptureTextRequest {
                text: "Pinned management sample".to_string(),
                source_bundle_id: Some("com.apple.TextEdit".to_string()),
                source_app_name: Some("TextEdit".to_string()),
                source_bundle_path: None,
                source_icon_relative_path: None,
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: 1,
                self_write_token: None,
            })
            .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(2));
        core.capture_text(CaptureTextRequest {
            text: "Regular management sample".to_string(),
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();

        let pin_result = core.set_item_pinned(&pinned.item_id, true).unwrap();
        let page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();

        assert_eq!(pin_result.affected_count, 1);
        assert_eq!(page.items[0].id, pinned.item_id);
        assert!(page.items[0].is_pinned);

        let delete_result = core.delete_item(&pinned.item_id).unwrap();
        let page_after_delete = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();
        let soft_deleted_count: i64 = core
            .connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE id = ?1 AND deleted_at_ms IS NOT NULL",
                params![pinned.item_id],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(delete_result.affected_count, 1);
        assert_eq!(page_after_delete.total_count, 1);
        assert_eq!(soft_deleted_count, 1);
    }

    #[test]
    fn clear_items_soft_deletes_matching_unpinned_items_only() {
        let (_, mut core) = open_temp_core();
        let pinned = core
            .capture_text(CaptureTextRequest {
                text: "Clear scope pinned text".to_string(),
                source_bundle_id: Some("com.apple.TextEdit".to_string()),
                source_app_name: Some("TextEdit".to_string()),
                source_bundle_path: None,
                source_icon_relative_path: None,
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: 1,
                self_write_token: None,
            })
            .unwrap();
        core.set_item_pinned(&pinned.item_id, true).unwrap();
        core.capture_text(CaptureTextRequest {
            text: "Clear scope removable text".to_string(),
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();
        core.capture_text(CaptureTextRequest {
            text: "Different scope sample".to_string(),
            source_bundle_id: Some("com.apple.Notes".to_string()),
            source_app_name: Some("Notes".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 3,
            self_write_token: None,
        })
        .unwrap();

        let clear_result = core
            .clear_items(ItemQuery {
                item_type: Some(ClipboardItemType::Text),
                search_text: Some("Clear scope".to_string()),
                ..ItemQuery::default()
            })
            .unwrap();
        let page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();

        assert_eq!(clear_result.affected_count, 1);
        assert_eq!(page.total_count, 2);
        assert!(page.items.iter().any(|item| item.id == pinned.item_id));
        assert!(page
            .items
            .iter()
            .all(|item| item.summary != "Clear scope removable text"));
    }

    #[test]
    fn default_preferences_document_is_seeded() {
        let (_, core) = open_temp_core();

        let preferences = core.get_preferences().unwrap();
        let row: (i64, String) = core
            .connection
            .query_row(
                "SELECT schema_version, value_json FROM preference_documents WHERE id = 'current'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();

        assert_eq!(row.0, CURRENT_SCHEMA_VERSION);
        assert!(row.1.contains("\"default_panel_height\":320"));
        assert_eq!(preferences.general.default_panel_height, 320);
        assert_eq!(preferences.history.max_items, 500);
        assert_eq!(preferences.appearance.mode, "system");
        assert!(preferences.ignore_list.ignored_app_identifiers.is_empty());
        assert!(preferences.ignore_list.window_title_keywords.is_empty());
        assert!(!preferences.ignore_list.skip_unknown_source);
    }

    #[test]
    fn preferences_update_persists_normalized_document() {
        let (_, mut core) = open_temp_core();
        let mut preferences = core.get_preferences().unwrap();
        preferences.general.default_panel_height = 999;
        preferences.history.max_items = 10;
        preferences.history.retention_days = 999;
        preferences.history.record_images = false;
        preferences.history.record_files = true;
        preferences.appearance.mode = "neon".to_string();
        preferences.appearance.item_density = "compact".to_string();
        preferences.ignore_list.ignored_app_identifiers = vec![
            "  com.apple.Terminal  ".to_string(),
            "terminal".to_string(),
            "COM.APPLE.TERMINAL".to_string(),
            "".to_string(),
        ];
        preferences.ignore_list.window_title_keywords = vec![
            " 密码 ".to_string(),
            "验证码".to_string(),
            "密码".to_string(),
        ];
        preferences.ignore_list.skip_unknown_source = true;

        let saved = core.update_preferences(preferences).unwrap();
        let reloaded = core.get_preferences().unwrap();

        assert_eq!(saved.general.default_panel_height, 560);
        assert_eq!(saved.history.max_items, 50);
        assert_eq!(saved.history.retention_days, 365);
        assert!(!saved.history.record_images);
        assert!(saved.history.record_files);
        assert_eq!(saved.appearance.mode, "system");
        assert_eq!(saved.appearance.item_density, "compact");
        assert_eq!(
            saved.ignore_list.ignored_app_identifiers,
            vec!["com.apple.Terminal".to_string(), "terminal".to_string()]
        );
        assert_eq!(
            saved.ignore_list.window_title_keywords,
            vec!["密码".to_string(), "验证码".to_string()]
        );
        assert!(saved.ignore_list.skip_unknown_source);
        assert_eq!(reloaded, saved);
    }

    #[test]
    fn preferences_parse_keeps_backward_compatible_missing_ignore_list() {
        let legacy_json = r#"
        {
            "general": {
                "launch_at_login": false,
                "show_menu_bar_item": true,
                "default_panel_height": 320
            },
            "history": {
                "max_items": 500,
                "retention_days": 30,
                "record_images": true,
                "record_files": false
            },
            "appearance": {
                "mode": "system",
                "item_density": "standard",
                "preview_popover_enabled": true
            }
        }
        "#;

        let preferences = parse_preferences_document(legacy_json).unwrap();

        assert!(preferences.ignore_list.ignored_app_identifiers.is_empty());
        assert!(preferences.ignore_list.window_title_keywords.is_empty());
        assert!(!preferences.ignore_list.skip_unknown_source);
    }

    #[test]
    fn preferences_update_prunes_history_to_max_items() {
        let (_, mut core) = open_temp_core();
        for index in 0..55 {
            core.capture_text(CaptureTextRequest {
                text: format!("Max item pruning sample {index:02}"),
                source_bundle_id: Some("com.apple.TextEdit".to_string()),
                source_app_name: Some("TextEdit".to_string()),
                source_bundle_path: None,
                source_icon_relative_path: None,
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: index,
                self_write_token: None,
            })
            .unwrap();
        }

        let mut preferences = core.get_preferences().unwrap();
        preferences.history.max_items = 50;
        preferences.history.retention_days = 365;
        core.update_preferences(preferences).unwrap();

        let active_page = core
            .list_items(
                ItemQuery::default(),
                PageRequest {
                    limit: 200,
                    offset: 0,
                },
            )
            .unwrap();
        let deleted_count: i64 = core
            .connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items WHERE deleted_at_ms IS NOT NULL",
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(active_page.total_count, 50);
        assert_eq!(active_page.items.len(), 50);
        assert_eq!(deleted_count, 5);
        assert!(active_page
            .items
            .iter()
            .any(|item| item.summary == "Max item pruning sample 54"));
        assert!(!active_page
            .items
            .iter()
            .any(|item| item.summary == "Max item pruning sample 00"));
    }

    #[test]
    fn preferences_update_prunes_history_by_retention_days() {
        let (_, mut core) = open_temp_core();
        let old_result = core
            .capture_text(CaptureTextRequest {
                text: "Old retention sample".to_string(),
                source_bundle_id: Some("com.apple.TextEdit".to_string()),
                source_app_name: Some("TextEdit".to_string()),
                source_bundle_path: None,
                source_icon_relative_path: None,
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: 1,
                self_write_token: None,
            })
            .unwrap();
        core.capture_text(CaptureTextRequest {
            text: "Fresh retention sample".to_string(),
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();

        let old_timestamp = now_ms() - 3 * MILLIS_PER_DAY;
        core.connection
            .execute(
                r#"
                UPDATE clipboard_items
                SET first_copied_at_ms = ?1, last_copied_at_ms = ?1, updated_at_ms = ?1
                WHERE id = ?2
                "#,
                params![old_timestamp, old_result.item_id],
            )
            .unwrap();

        let mut preferences = core.get_preferences().unwrap();
        preferences.history.max_items = 500;
        preferences.history.retention_days = 1;
        core.update_preferences(preferences).unwrap();

        let active_page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();
        let deleted_summary: String = core
            .connection
            .query_row(
                "SELECT summary FROM clipboard_items WHERE deleted_at_ms IS NOT NULL",
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(active_page.total_count, 1);
        assert_eq!(active_page.items[0].summary, "Fresh retention sample");
        assert_eq!(deleted_summary, "Old retention sample");
    }

    #[test]
    fn maintenance_purges_soft_deleted_items_and_assets() {
        let (temp_dir, mut core) = open_temp_core();
        let payload_path = temp_dir.path().join("assets/deleted.png");
        let thumbnail_path = temp_dir.path().join("thumbnails/deleted.png");
        fs::write(&payload_path, b"deleted image payload").expect("payload");
        fs::write(&thumbnail_path, b"deleted image thumbnail").expect("thumbnail");

        let result = core
            .capture_image(CaptureImageRequest {
                payload_relative_path: "assets/deleted.png".to_string(),
                preview_relative_path: Some("thumbnails/deleted.png".to_string()),
                mime_type: Some("image/png".to_string()),
                width: 320,
                height: 180,
                byte_count: 21,
                source_bundle_id: Some("com.apple.Preview".to_string()),
                source_app_name: Some("Preview".to_string()),
                source_bundle_path: None,
                source_icon_relative_path: None,
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: 90,
                self_write_token: None,
            })
            .unwrap();
        core.connection
            .execute(
                "UPDATE clipboard_items SET deleted_at_ms = ?1 WHERE id = ?2",
                params![now_ms(), result.item_id],
            )
            .unwrap();

        let maintenance = core.run_maintenance().unwrap();

        assert_eq!(maintenance.purged_item_count, 1);
        assert_eq!(maintenance.deleted_asset_row_count, 2);
        assert_eq!(maintenance.deleted_asset_file_count, 2);
        assert!(maintenance.reclaimed_bytes > 0);
        assert!(!payload_path.exists());
        assert!(!thumbnail_path.exists());

        let item_count: i64 = core
            .connection
            .query_row("SELECT COUNT(*) FROM clipboard_items", [], |row| row.get(0))
            .unwrap();
        let asset_count: i64 = core
            .connection
            .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
                row.get(0)
            })
            .unwrap();
        let fts_count: i64 = core
            .connection
            .query_row(
                "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH 'Preview'",
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(item_count, 0);
        assert_eq!(asset_count, 0);
        assert_eq!(fts_count, 0);
    }

    #[test]
    fn maintenance_removes_orphan_files_and_keeps_active_assets() {
        let (temp_dir, mut core) = open_temp_core();
        let payload_path = temp_dir.path().join("assets/active.png");
        let thumbnail_path = temp_dir.path().join("thumbnails/active.png");
        let icon_path = temp_dir.path().join("app-icons/preview.tiff");
        fs::create_dir_all(icon_path.parent().unwrap()).expect("icon dir");
        fs::write(&payload_path, b"active image payload").expect("payload");
        fs::write(&thumbnail_path, b"active image thumbnail").expect("thumbnail");
        fs::write(&icon_path, b"active app icon").expect("icon");
        core.capture_image(CaptureImageRequest {
            payload_relative_path: "assets/active.png".to_string(),
            preview_relative_path: Some("thumbnails/active.png".to_string()),
            mime_type: Some("image/png".to_string()),
            width: 640,
            height: 480,
            byte_count: 20,
            source_bundle_id: Some("com.apple.Preview".to_string()),
            source_app_name: Some("Preview".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: Some("app-icons/preview.tiff".to_string()),
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 91,
            self_write_token: None,
        })
        .unwrap();

        let orphan_asset = temp_dir.path().join("assets/orphan.bin");
        let orphan_thumbnail = temp_dir.path().join("thumbnails/orphan.png");
        let orphan_icon = temp_dir.path().join("app-icons/orphan.tiff");
        let orphan_snapshot = temp_dir.path().join("assets/file-snapshots/orphan.json");
        let staging_file = temp_dir.path().join("staging/leftover.tmp");
        fs::create_dir_all(orphan_snapshot.parent().unwrap()).expect("snapshot dir");
        fs::write(&orphan_asset, b"orphan asset").expect("orphan asset");
        fs::write(&orphan_thumbnail, b"orphan thumbnail").expect("orphan thumbnail");
        fs::write(&orphan_icon, b"orphan icon").expect("orphan icon");
        fs::write(&orphan_snapshot, b"orphan snapshot").expect("orphan snapshot");
        fs::write(&staging_file, b"staging leftover").expect("staging");

        let maintenance = core.run_maintenance().unwrap();

        assert_eq!(maintenance.purged_item_count, 0);
        assert_eq!(maintenance.deleted_asset_row_count, 0);
        assert_eq!(maintenance.deleted_asset_file_count, 0);
        assert_eq!(maintenance.deleted_orphan_file_count, 5);
        assert!(payload_path.exists());
        assert!(thumbnail_path.exists());
        assert!(icon_path.exists());
        assert!(!orphan_asset.exists());
        assert!(!orphan_thumbnail.exists());
        assert!(!orphan_icon.exists());
        assert!(!orphan_snapshot.exists());
        assert!(!staging_file.exists());

        let active_page = core
            .list_items(ItemQuery::default(), PageRequest::default())
            .unwrap();
        assert_eq!(active_page.total_count, 1);
        assert_eq!(active_page.items[0].item_type, ClipboardItemType::Image);
    }

    #[test]
    fn fts_external_content_table_exists() {
        let (_, core) = open_temp_core();

        let table_count: i64 = core
            .connection
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE name = 'clipboard_items_fts'",
                [],
                |row| row.get(0),
            )
            .unwrap();

        assert_eq!(table_count, 1);
    }

    #[test]
    fn migration_checksum_mismatch_is_reported() {
        let (temp_dir, core) = open_temp_core();
        core.connection
            .execute(
                "UPDATE schema_migrations SET checksum = 'changed' WHERE version = 1",
                [],
            )
            .unwrap();
        drop(core);

        let error = match ClipboardCore::open(temp_dir.path()) {
            Ok(_) => panic!("expected checksum mismatch"),
            Err(error) => error,
        };
        assert_eq!(error.code, CoreErrorCode::MigrationChecksumMismatch);
    }
}
