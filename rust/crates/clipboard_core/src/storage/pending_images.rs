use crate::domain::{
    CapturePendingImageRequest, CompletePendingImagePayloadRequest, FailPendingImagePayloadRequest,
    ItemManagementResult, PendingImageCaptureResult, PendingImageCompletionResult,
    RecoverPendingImagesRequest, SourceConfidence,
};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use rusqlite::{params, OptionalExtension, Transaction, TransactionBehavior};
use std::fs;
use std::path::Path;

use super::capture::{make_item_id, record_capture_event, update_search_index};
use super::source_apps::SourceAppInput;
use super::support::{
    delete_relative_file, hash_file, insert_asset, normalize_relative_asset_path,
    positive_dimension, stable_hash,
};
use super::ClipboardCore;

const IMAGE_WEBP_MIME_TYPE: &str = "image/webp";
const DEFAULT_PENDING_IMAGE_LEASE_MS: i64 = 10 * 60 * 1000;
const DEFAULT_PENDING_IMAGE_CLEANUP_MS: i64 = 24 * 60 * 60 * 1000;

#[derive(Debug, Clone)]
struct PendingImageJob {
    job_id: String,
    item_id: Option<String>,
    effective_item_id: Option<String>,
    thumbnail_relative_path: String,
    reserved_payload_relative_path: String,
    staged_payload_relative_path: String,
    state: String,
}

impl ClipboardCore {
    pub fn capture_pending_image(
        &mut self,
        request: CapturePendingImageRequest,
    ) -> Result<PendingImageCaptureResult> {
        validate_webp_mime(&request.mime_type)?;
        validate_positive_dimensions(request.width, request.height)?;
        validate_positive_dimensions(request.thumbnail_width, request.thumbnail_height)?;
        let thumbnail_byte_count = validate_positive_byte_count(request.thumbnail_byte_count)?;

        let owner_session_id = normalize_required(&request.owner_session_id, "owner session id")?;
        let thumbnail_relative_path =
            normalize_expected_relative_path(&request.thumbnail_relative_path, "thumbnails/")?;
        let reserved_payload_relative_path =
            normalize_expected_relative_path(&request.reserved_payload_relative_path, "assets/")?;
        let staged_payload_relative_path =
            normalize_staged_relative_path(&request.staged_payload_relative_path)?;
        let root = self.root_dir()?.to_path_buf();
        let thumbnail_path = root.join(&thumbnail_relative_path);
        validate_existing_file(&thumbnail_path, thumbnail_byte_count)?;
        validate_webp_file(&thumbnail_path)?;
        let thumbnail_digest = hash_file(&thumbnail_path)?;
        let staged_path = root.join(&staged_payload_relative_path);
        if staged_path.exists() {
            return Err(CoreError::new(
                CoreErrorCode::InvalidInput,
                "staged payload path must be empty before pending capture",
            )
            .with_detail("path", staged_payload_relative_path));
        }

        let now = now_ms();
        let content_hash = stable_hash(&format!(
            "image-pending:{thumbnail_digest}:{reserved_payload_relative_path}:{staged_payload_relative_path}:{now}:{}",
            request.pasteboard_change_count
        ));
        let item_id = make_item_id(&content_hash);
        let job_id = format!(
            "pending_image_{}",
            &stable_hash(&format!("{item_id}:{now}"))[..24]
        );
        let summary = super::support::summarize_image(request.width, request.height);
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
        let lease_duration_ms =
            normalized_duration(request.lease_duration_ms, DEFAULT_PENDING_IMAGE_LEASE_MS);
        let cleanup_duration_ms = normalized_duration(
            request.cleanup_after_duration_ms,
            DEFAULT_PENDING_IMAGE_CLEANUP_MS,
        );

        let transaction = self.connection.transaction()?;
        transaction.execute(
            r#"
            INSERT INTO clipboard_items (
                id, type, summary, primary_text, content_hash,
                source_app_id, source_app_name, source_confidence,
                first_copied_at_ms, last_copied_at_ms, copy_count,
                is_pinned, size_bytes, preview_state, payload_state,
                created_at_ms, updated_at_ms
            )
            VALUES (?1, 'image', ?2, NULL, ?3, ?4, ?5, ?6, ?7, ?7, 1, 0, ?8, 'ready', 'pending', ?7, ?7)
            "#,
            params![
                item_id,
                summary,
                content_hash,
                source_app_id.as_deref(),
                source_app_name,
                source_confidence.as_str(),
                now,
                thumbnail_byte_count
            ],
        )?;

        insert_asset(
            &transaction,
            &item_id,
            "thumbnail",
            IMAGE_WEBP_MIME_TYPE,
            &thumbnail_relative_path,
            thumbnail_byte_count,
            positive_dimension(request.thumbnail_width),
            positive_dimension(request.thumbnail_height),
            &thumbnail_digest,
            now,
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
        transaction.execute(
            r#"
            INSERT INTO pending_image_jobs (
                job_id,
                requested_item_id,
                item_id,
                effective_item_id,
                owner_session_id,
                thumbnail_relative_path,
                reserved_payload_relative_path,
                staged_payload_relative_path,
                state,
                failure_code,
                lease_expires_at_ms,
                cleanup_after_ms,
                created_at_ms,
                updated_at_ms,
                completed_at_ms
            )
            VALUES (?1, ?2, ?2, NULL, ?3, ?4, ?5, ?6, 'pending', NULL, ?7, ?8, ?9, ?9, NULL)
            "#,
            params![
                job_id,
                item_id,
                owner_session_id,
                thumbnail_relative_path,
                reserved_payload_relative_path,
                staged_payload_relative_path,
                now.saturating_add(lease_duration_ms),
                now.saturating_add(cleanup_duration_ms),
                now
            ],
        )?;
        transaction.commit()?;
        self.apply_post_capture()?;

        Ok(PendingImageCaptureResult {
            job_id,
            item_id,
            content_hash,
            copy_count: 1,
            inserted: true,
        })
    }

    pub fn complete_pending_image_payload(
        &mut self,
        request: CompletePendingImagePayloadRequest,
    ) -> Result<PendingImageCompletionResult> {
        validate_webp_mime(&request.mime_type)?;
        validate_positive_dimensions(request.width, request.height)?;
        let byte_count = validate_positive_byte_count(request.byte_count)?;
        let job_id = normalize_required(&request.job_id, "job id")?;
        let root = self.root_dir()?.to_path_buf();
        let now = now_ms();
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let Some(job) = load_pending_image_job(&transaction, &job_id)? else {
            transaction.commit()?;
            return Ok(PendingImageCompletionResult::not_pending());
        };
        let staged_payload_relative_path =
            normalize_staged_relative_path(&request.staged_payload_relative_path)?;
        if staged_payload_relative_path != job.staged_payload_relative_path {
            transaction.commit()?;
            return Ok(PendingImageCompletionResult {
                status: "staged_path_mismatch".to_string(),
                job_id: Some(job.job_id),
                item_id: job.item_id,
                effective_item_id: job.effective_item_id,
                content_hash: None,
                cleaned_relative_paths: Vec::new(),
                affected_count: 0,
            });
        }

        if job.state != "pending" {
            transaction.commit()?;
            let mut result = terminal_completion_result(&job);
            if matches!(job.state.as_str(), "deleted" | "merged") {
                if delete_relative_file(&root, &job.staged_payload_relative_path)?.is_some() {
                    result
                        .cleaned_relative_paths
                        .push(job.staged_payload_relative_path.clone());
                }
            }
            return Ok(result);
        }

        let item_id = match active_pending_item_id(&transaction, &job)? {
            Some(item_id) => item_id,
            None => {
                mark_pending_job_terminal(
                    &transaction,
                    &job.job_id,
                    "deleted",
                    None,
                    Some("item_deleted"),
                    now,
                )?;
                transaction.commit()?;
                let _ = delete_relative_file(&root, &job.staged_payload_relative_path)?;
                return Ok(PendingImageCompletionResult {
                    status: "deleted".to_string(),
                    job_id: Some(job.job_id),
                    item_id: None,
                    effective_item_id: None,
                    content_hash: None,
                    cleaned_relative_paths: vec![job.staged_payload_relative_path],
                    affected_count: 1,
                });
            }
        };

        let staged_path = root.join(&job.staged_payload_relative_path);
        validate_existing_file(&staged_path, byte_count)?;
        validate_webp_file(&staged_path)?;
        let payload_digest = hash_file(&staged_path)?;
        let content_hash = stable_hash(&format!("image:{payload_digest}"));

        if let Some((duplicate_item_id, _)) =
            super::capture::find_existing_item(&transaction, &content_hash)?
        {
            merge_pending_image_into_duplicate(
                &transaction,
                &item_id,
                &duplicate_item_id,
                &job,
                now,
            )?;
            transaction.commit()?;
            let _ = delete_relative_file(&root, &job.staged_payload_relative_path)?;
            let _ = delete_relative_file(&root, &job.thumbnail_relative_path)?;
            return Ok(PendingImageCompletionResult {
                status: "merged".to_string(),
                job_id: Some(job.job_id),
                item_id: None,
                effective_item_id: Some(duplicate_item_id),
                content_hash: Some(content_hash),
                cleaned_relative_paths: vec![
                    job.staged_payload_relative_path,
                    job.thumbnail_relative_path,
                ],
                affected_count: 1,
            });
        }

        let reserved_payload_relative_path =
            normalize_expected_relative_path(&job.reserved_payload_relative_path, "assets/")?;
        let final_path = root.join(&reserved_payload_relative_path);
        if final_path.exists() {
            return Err(CoreError::new(
                CoreErrorCode::InvalidInput,
                "reserved payload path already exists",
            )
            .with_detail("path", final_path.display().to_string()));
        }
        if let Some(parent) = final_path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::rename(&staged_path, &final_path).map_err(|error| {
            CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("source", staged_path.display().to_string())
                .with_detail("destination", final_path.display().to_string())
        })?;
        let final_path_needs_compensation = true;
        complete_pending_image_item(
            &transaction,
            &item_id,
            &job,
            &reserved_payload_relative_path,
            &payload_digest,
            &content_hash,
            request.width,
            request.height,
            byte_count,
            now,
        )?;

        match transaction.commit() {
            Ok(()) => Ok(PendingImageCompletionResult {
                status: "ready".to_string(),
                job_id: Some(job.job_id),
                item_id: Some(item_id.clone()),
                effective_item_id: Some(item_id),
                content_hash: Some(content_hash),
                cleaned_relative_paths: Vec::new(),
                affected_count: 1,
            }),
            Err(error) => {
                if final_path_needs_compensation {
                    let _ = fs::remove_file(&final_path);
                }
                Err(error.into())
            }
        }
    }

    pub fn fail_pending_image_payload(
        &mut self,
        request: FailPendingImagePayloadRequest,
    ) -> Result<PendingImageCompletionResult> {
        let job_id = normalize_required(&request.job_id, "job id")?;
        let failure_code = normalize_required(&request.failure_code, "failure code")?;
        let staged_request = request
            .staged_payload_relative_path
            .as_deref()
            .map(normalize_staged_relative_path)
            .transpose()?;
        let root = self.root_dir()?.to_path_buf();
        let now = now_ms();
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let Some(job) = load_pending_image_job(&transaction, &job_id)? else {
            transaction.commit()?;
            return Ok(PendingImageCompletionResult::not_pending());
        };

        if job.state == "pending" {
            mark_pending_job_terminal(
                &transaction,
                &job.job_id,
                "failed",
                job.effective_item_id.as_deref(),
                Some(&failure_code),
                now,
            )?;
            if let Some(item_id) = job.item_id.as_deref() {
                transaction.execute(
                    r#"
                    UPDATE clipboard_items
                    SET payload_state = 'failed', updated_at_ms = ?1
                    WHERE id = ?2 AND deleted_at_ms IS NULL
                    "#,
                    params![now, item_id],
                )?;
            }
        }
        transaction.commit()?;

        if staged_request.as_deref() == Some(job.staged_payload_relative_path.as_str()) {
            let _ = delete_relative_file(&root, &job.staged_payload_relative_path)?;
        }
        let cleaned_relative_paths =
            if staged_request.as_deref() == Some(job.staged_payload_relative_path.as_str()) {
                vec![job.staged_payload_relative_path.clone()]
            } else {
                Vec::new()
            };

        Ok(PendingImageCompletionResult {
            status: "failed".to_string(),
            job_id: Some(job.job_id),
            item_id: job.item_id,
            effective_item_id: job.effective_item_id,
            content_hash: None,
            cleaned_relative_paths,
            affected_count: 1,
        })
    }

    pub fn recover_pending_images(
        &mut self,
        request: RecoverPendingImagesRequest,
    ) -> Result<ItemManagementResult> {
        let owner_session_id = normalize_required(&request.owner_session_id, "owner session id")?;
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE pending_image_jobs
            SET state = 'failed',
                failure_code = 'lease_expired',
                cleanup_after_ms = ?1,
                updated_at_ms = ?2,
                completed_at_ms = COALESCE(completed_at_ms, ?2)
            WHERE state = 'pending'
                AND owner_session_id <> ?3
                AND lease_expires_at_ms <= ?2
            "#,
            params![
                now.saturating_add(DEFAULT_PENDING_IMAGE_CLEANUP_MS),
                now,
                owner_session_id
            ],
        )? as i64;
        self.connection.execute(
            r#"
            UPDATE clipboard_items
            SET payload_state = 'failed', updated_at_ms = ?1
            WHERE payload_state = 'pending'
                AND id IN (
                    SELECT item_id
                    FROM pending_image_jobs
                    WHERE state = 'failed'
                        AND failure_code = 'lease_expired'
                        AND updated_at_ms = ?1
                )
            "#,
            params![now],
        )?;
        Ok(ItemManagementResult { affected_count })
    }
}

impl PendingImageCompletionResult {
    fn not_pending() -> Self {
        Self {
            status: "not_pending".to_string(),
            job_id: None,
            item_id: None,
            effective_item_id: None,
            content_hash: None,
            cleaned_relative_paths: Vec::new(),
            affected_count: 0,
        }
    }
}

pub(super) fn mark_pending_jobs_deleted_for_items(
    transaction: &Transaction<'_>,
    now: i64,
) -> Result<()> {
    transaction.execute(
        r#"
        UPDATE pending_image_jobs
        SET state = 'deleted',
            item_id = NULL,
            failure_code = COALESCE(failure_code, 'item_deleted'),
            cleanup_after_ms = ?1,
            updated_at_ms = ?2,
            completed_at_ms = COALESCE(completed_at_ms, ?2)
        WHERE state = 'pending'
            AND item_id IN (
                SELECT id
                FROM clipboard_items
                WHERE deleted_at_ms IS NOT NULL
            )
        "#,
        params![now.saturating_add(DEFAULT_PENDING_IMAGE_CLEANUP_MS), now],
    )?;
    Ok(())
}

pub(super) fn terminal_pending_image_staged_paths(
    transaction: &Transaction<'_>,
) -> Result<Vec<String>> {
    let mut statement = transaction.prepare(
        r#"
        SELECT staged_payload_relative_path
        FROM pending_image_jobs
        WHERE state IN ('failed', 'deleted', 'merged')
        "#,
    )?;
    let paths = statement
        .query_map([], |row| row.get::<_, String>(0))?
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(CoreError::from)?;
    Ok(paths)
}

pub(super) fn active_pending_image_staged_paths(
    transaction: &Transaction<'_>,
    now: i64,
) -> Result<Vec<String>> {
    let mut statement = transaction.prepare(
        r#"
        SELECT staged_payload_relative_path
        FROM pending_image_jobs
        WHERE state = 'pending' AND lease_expires_at_ms > ?1
        "#,
    )?;
    let paths = statement
        .query_map(params![now], |row| row.get::<_, String>(0))?
        .collect::<std::result::Result<Vec<_>, _>>()
        .map_err(CoreError::from)?;
    Ok(paths)
}

pub(super) fn purge_expired_pending_image_tombstones(
    transaction: &Transaction<'_>,
    now: i64,
) -> Result<i64> {
    let count = transaction.execute(
        r#"
        DELETE FROM pending_image_jobs
        WHERE state IN ('ready', 'failed', 'deleted', 'merged')
            AND cleanup_after_ms <= ?1
        "#,
        params![now],
    )? as i64;
    Ok(count)
}

fn complete_pending_image_item(
    transaction: &Transaction<'_>,
    item_id: &str,
    job: &PendingImageJob,
    payload_relative_path: &str,
    payload_digest: &str,
    content_hash: &str,
    width: i64,
    height: i64,
    byte_count: i64,
    now: i64,
) -> Result<()> {
    let summary = super::support::summarize_image(width, height);
    insert_asset(
        transaction,
        item_id,
        "payload",
        IMAGE_WEBP_MIME_TYPE,
        payload_relative_path,
        byte_count,
        positive_dimension(width),
        positive_dimension(height),
        payload_digest,
        now,
    )?;
    let format_id = format!(
        "format_{}",
        &stable_hash(&format!("{item_id}:primary:{payload_digest}"))[..24]
    );
    transaction.execute(
        r#"
        INSERT OR IGNORE INTO clipboard_formats (
            id, item_id, uti, role, storage, byte_count
        )
        VALUES (?1, ?2, ?3, 'primary', 'staged_asset', ?4)
        "#,
        params![format_id, item_id, IMAGE_WEBP_MIME_TYPE, byte_count],
    )?;
    transaction.execute(
        r#"
        UPDATE clipboard_items
        SET summary = ?1,
            content_hash = ?2,
            size_bytes = ?3,
            preview_state = 'ready',
            payload_state = 'ready',
            updated_at_ms = ?4
        WHERE id = ?5 AND deleted_at_ms IS NULL
        "#,
        params![summary, content_hash, byte_count, now, item_id],
    )?;
    mark_pending_job_terminal(transaction, &job.job_id, "ready", None, None, now)?;
    update_search_index(transaction, item_id, &summary, "", "")?;
    Ok(())
}

fn merge_pending_image_into_duplicate(
    transaction: &Transaction<'_>,
    pending_item_id: &str,
    duplicate_item_id: &str,
    job: &PendingImageJob,
    now: i64,
) -> Result<()> {
    let pending = transaction.query_row(
        r#"
        SELECT copy_count, source_app_id, source_app_name, source_confidence, last_copied_at_ms
        FROM clipboard_items
        WHERE id = ?1
        "#,
        params![pending_item_id],
        |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, Option<String>>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, i64>(4)?,
            ))
        },
    )?;
    let pending_source_confidence = SourceConfidence::from_storage(&pending.3);
    transaction.execute(
        r#"
        UPDATE clipboard_items
        SET
            last_copied_at_ms = MAX(last_copied_at_ms, ?1),
            copy_count = copy_count + ?2,
            source_app_id = ?3,
            source_app_name = ?4,
            source_confidence = ?5,
            payload_state = 'ready',
            updated_at_ms = ?6
        WHERE id = ?7 AND deleted_at_ms IS NULL
        "#,
        params![
            pending.4,
            pending.0.max(1),
            pending.1.as_deref(),
            pending.2.as_deref(),
            pending_source_confidence.as_str(),
            now,
            duplicate_item_id
        ],
    )?;
    transaction.execute(
        "UPDATE clipboard_captures SET item_id = ?1 WHERE item_id = ?2",
        params![duplicate_item_id, pending_item_id],
    )?;
    transaction.execute(
        r#"
        INSERT OR IGNORE INTO pinboard_items (
            pinboard_id, item_id, display_order, pinned_at_ms, created_at_ms, updated_at_ms
        )
        SELECT pinboard_id, ?1, display_order, pinned_at_ms, created_at_ms, ?3
        FROM pinboard_items
        WHERE item_id = ?2
        "#,
        params![duplicate_item_id, pending_item_id, now],
    )?;
    transaction.execute(
        "DELETE FROM pinboard_items WHERE item_id = ?1",
        params![pending_item_id],
    )?;
    transaction.execute(
        r#"
        UPDATE clipboard_items
        SET is_pinned = CASE WHEN EXISTS (
            SELECT 1
            FROM pinboard_items
            WHERE item_id = ?1
        ) THEN 1 ELSE is_pinned END,
        updated_at_ms = ?2
        WHERE id = ?1
        "#,
        params![duplicate_item_id, now],
    )?;
    mark_pending_job_terminal(
        transaction,
        &job.job_id,
        "merged",
        Some(duplicate_item_id),
        None,
        now,
    )?;
    transaction.execute(
        "DELETE FROM clipboard_items WHERE id = ?1",
        params![pending_item_id],
    )?;
    transaction.execute(
        "INSERT INTO clipboard_items_fts(clipboard_items_fts) VALUES('rebuild')",
        [],
    )?;
    Ok(())
}

fn load_pending_image_job(
    transaction: &Transaction<'_>,
    job_id: &str,
) -> Result<Option<PendingImageJob>> {
    transaction
        .query_row(
            r#"
            SELECT
                job_id,
                item_id,
                effective_item_id,
                thumbnail_relative_path,
                reserved_payload_relative_path,
                staged_payload_relative_path,
                state
            FROM pending_image_jobs
            WHERE job_id = ?1
            "#,
            params![job_id],
            |row| {
                Ok(PendingImageJob {
                    job_id: row.get(0)?,
                    item_id: row.get(1)?,
                    effective_item_id: row.get(2)?,
                    thumbnail_relative_path: row.get(3)?,
                    reserved_payload_relative_path: row.get(4)?,
                    staged_payload_relative_path: row.get(5)?,
                    state: row.get(6)?,
                })
            },
        )
        .optional()
        .map_err(Into::into)
}

fn active_pending_item_id(
    transaction: &Transaction<'_>,
    job: &PendingImageJob,
) -> Result<Option<String>> {
    let Some(item_id) = job.item_id.as_deref() else {
        return Ok(None);
    };
    let active = transaction.query_row(
        r#"
            SELECT EXISTS(
                SELECT 1
                FROM clipboard_items
                WHERE id = ?1
                    AND deleted_at_ms IS NULL
                    AND payload_state = 'pending'
            )
            "#,
        params![item_id],
        |row| row.get::<_, i64>(0),
    )? == 1;
    Ok(active.then(|| item_id.to_string()))
}

fn mark_pending_job_terminal(
    transaction: &Transaction<'_>,
    job_id: &str,
    state: &str,
    effective_item_id: Option<&str>,
    failure_code: Option<&str>,
    now: i64,
) -> Result<()> {
    transaction.execute(
        r#"
        UPDATE pending_image_jobs
        SET state = ?1,
            effective_item_id = COALESCE(?2, effective_item_id),
            failure_code = COALESCE(?3, failure_code),
            cleanup_after_ms = ?4,
            updated_at_ms = ?5,
            completed_at_ms = COALESCE(completed_at_ms, ?5)
        WHERE job_id = ?6
        "#,
        params![
            state,
            effective_item_id,
            failure_code,
            now.saturating_add(DEFAULT_PENDING_IMAGE_CLEANUP_MS),
            now,
            job_id
        ],
    )?;
    Ok(())
}

fn terminal_completion_result(job: &PendingImageJob) -> PendingImageCompletionResult {
    PendingImageCompletionResult {
        status: job.state.clone(),
        job_id: Some(job.job_id.clone()),
        item_id: job.item_id.clone(),
        effective_item_id: job.effective_item_id.clone(),
        content_hash: None,
        cleaned_relative_paths: Vec::new(),
        affected_count: 0,
    }
}

fn validate_webp_mime(mime_type: &str) -> Result<()> {
    if mime_type.trim().eq_ignore_ascii_case(IMAGE_WEBP_MIME_TYPE) {
        Ok(())
    } else {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "pending image payloads must use image/webp",
        ))
    }
}

fn validate_positive_dimensions(width: i64, height: i64) -> Result<()> {
    if width > 0 && height > 0 {
        Ok(())
    } else {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "image dimensions must be positive",
        ))
    }
}

fn validate_positive_byte_count(byte_count: i64) -> Result<i64> {
    if byte_count > 0 {
        Ok(byte_count)
    } else {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "image byte count must be positive",
        ))
    }
}

fn validate_existing_file(path: &Path, expected_byte_count: i64) -> Result<()> {
    let metadata = fs::metadata(path).map_err(|error| {
        CoreError::new(CoreErrorCode::IoFailed, error.to_string())
            .with_detail("path", path.display().to_string())
    })?;
    if !metadata.is_file() || metadata.len() as i64 != expected_byte_count {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "image file byte count does not match metadata",
        )
        .with_detail("path", path.display().to_string())
        .with_detail("expected_byte_count", expected_byte_count.to_string())
        .with_detail("actual_byte_count", metadata.len().to_string()));
    }
    Ok(())
}

fn validate_webp_file(path: &Path) -> Result<()> {
    let bytes = fs::read(path).map_err(|error| {
        CoreError::new(CoreErrorCode::IoFailed, error.to_string())
            .with_detail("path", path.display().to_string())
    })?;
    if bytes.len() >= 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Ok(())
    } else {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "image file is not a WebP payload",
        )
        .with_detail("path", path.display().to_string()))
    }
}

fn normalize_required(value: &str, label: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            format!("{label} cannot be empty"),
        ))
    } else {
        Ok(value.to_string())
    }
}

fn normalize_expected_relative_path(value: &str, prefix: &str) -> Result<String> {
    let path = normalize_relative_asset_path(value)?;
    if path.starts_with(prefix) {
        Ok(path)
    } else {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "asset path uses an unexpected directory",
        )
        .with_detail("path", path)
        .with_detail("expected_prefix", prefix))
    }
}

fn normalize_staged_relative_path(value: &str) -> Result<String> {
    let path = normalize_relative_asset_path(value)?;
    if path.starts_with("staging/") || path.starts_with(".staging/") {
        Ok(path)
    } else {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "staged payload path uses an unexpected directory",
        )
        .with_detail("path", path))
    }
}

fn normalized_duration(value: Option<i64>, default_value: i64) -> i64 {
    value
        .filter(|duration| *duration > 0)
        .unwrap_or(default_value)
}
