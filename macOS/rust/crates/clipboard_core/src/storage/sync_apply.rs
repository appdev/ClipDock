use crate::domain::{
    ClipboardItemType, ItemManagementResult, PreviewState, SyncApplyEventsRequest,
    SyncApplyOutcome, SyncApplySnapshotRequest, SyncEventRecord, SyncLocalPendingRequest,
    SyncProgress, SyncSnapshotItemRecord, SyncSnapshotTombstoneRecord,
};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use rusqlite::{params, OptionalExtension, Transaction};
use serde_json::{Map, Value};
use std::collections::BTreeSet;

use super::capture::{find_existing_item, make_item_id, update_search_index};
use super::support::stable_hash;
use super::ClipboardCore;

const ANDROID_PLATFORM_SOURCE_APP_NAME: &str = "Android";
const ANDROID_PLATFORM_SOURCE_BUNDLE_ID: &str = "app.clipdock.platform.android";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ApplySource {
    Event { copy_count_delta: i64 },
    Snapshot { copy_count: i64 },
}

#[derive(Debug)]
struct SyncClientState {
    cursor: i64,
    snapshot_seq: i64,
}

#[derive(Debug)]
struct SyncItemState {
    item_id: Option<String>,
    provenance: String,
    last_server_seq: i64,
}

#[derive(Debug)]
struct RemoteItemMapping {
    item_type: ClipboardItemType,
    summary: String,
    primary_text: Option<String>,
    source_app_name: Option<String>,
    source_bundle_id: Option<String>,
    size_bytes: i64,
    preview_state: &'static str,
    payload_state: &'static str,
    link: Option<RemoteLinkMapping>,
    file: Option<RemoteFileMapping>,
    asset: Option<RemoteAssetMapping>,
}

#[derive(Debug)]
struct RemoteLinkMapping {
    original_text: String,
    canonical_url: String,
    display_url: String,
    host: String,
    title: Option<String>,
    site_name: Option<String>,
    metadata_state: &'static str,
}

#[derive(Debug)]
struct RemoteFileMapping {
    path: String,
    file_name: String,
    file_extension: Option<String>,
    byte_count: i64,
    is_directory: bool,
    width: Option<i64>,
    height: Option<i64>,
    content_type: Option<String>,
}

#[derive(Debug)]
struct RemoteAssetMapping {
    asset_id: String,
    kind: String,
    mime_type: Option<String>,
    byte_count: Option<i64>,
    file_name: Option<String>,
    source_payload_json: String,
}

impl ClipboardCore {
    pub fn get_sync_progress(
        &mut self,
        sync_id: impl AsRef<str>,
        device_id: impl AsRef<str>,
    ) -> Result<SyncProgress> {
        let sync_id = normalize_non_empty(sync_id.as_ref(), "sync_id")?;
        let device_id = normalize_non_empty(device_id.as_ref(), "device_id")?;
        let transaction = self.connection.transaction()?;
        let state = ensure_sync_client_state(&transaction, &sync_id, &device_id)?;
        transaction.commit()?;
        Ok(SyncProgress {
            sync_id,
            device_id,
            cursor: state.cursor,
            snapshot_seq: state.snapshot_seq,
        })
    }

    pub fn mark_sync_local_pending(
        &mut self,
        request: SyncLocalPendingRequest,
    ) -> Result<ItemManagementResult> {
        let sync_id = normalize_non_empty(&request.sync_id, "sync_id")?;
        let content_hash = normalize_content_hash(&request.content_hash)?;
        let client_event_id = normalize_non_empty(&request.client_event_id, "client_event_id")?;
        let transaction = self.connection.transaction()?;
        let item_id = request
            .item_id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
            .or_else(|| {
                active_item_id_for_hash(&transaction, &content_hash)
                    .ok()
                    .flatten()
            });
        let now = now_ms();
        let affected_count = transaction.execute(
            r#"
            INSERT INTO sync_item_state (
                sync_id, content_hash, item_id, provenance, local_status,
                local_pending_event_id, updated_at_ms
            )
            VALUES (?1, ?2, ?3, 'local_pending_upload', 'pending_upload', ?4, ?5)
            ON CONFLICT(sync_id, content_hash) DO UPDATE SET
                item_id = COALESCE(excluded.item_id, sync_item_state.item_id),
                provenance = 'local_pending_upload',
                local_status = 'pending_upload',
                local_pending_event_id = excluded.local_pending_event_id,
                updated_at_ms = excluded.updated_at_ms
            "#,
            params![sync_id, content_hash, item_id, client_event_id, now],
        )? as i64;
        transaction.commit()?;
        Ok(ItemManagementResult { affected_count })
    }

    pub fn apply_sync_events(
        &mut self,
        request: SyncApplyEventsRequest,
    ) -> Result<SyncApplyOutcome> {
        let sync_id = normalize_non_empty(&request.sync_id, "sync_id")?;
        let device_id = normalize_non_empty(&request.device_id, "device_id")?;
        if request.next_cursor < 0 {
            return Err(sync_error(
                CoreErrorCode::SyncCursorRegression,
                "next cursor cannot be negative",
            ));
        }

        let transaction = self.connection.transaction()?;
        let state = ensure_sync_client_state(&transaction, &sync_id, &device_id)?;
        if request.events.is_empty() {
            if request.next_cursor < state.cursor {
                return Err(sync_error(
                    CoreErrorCode::SyncCursorRegression,
                    "empty batch next cursor regressed",
                ));
            }
            update_client_cursor(
                &transaction,
                &sync_id,
                request.next_cursor,
                state.snapshot_seq,
            )?;
            transaction.commit()?;
            return Ok(SyncApplyOutcome {
                cursor: request.next_cursor,
                snapshot_seq: state.snapshot_seq,
                changed_item_ids: Vec::new(),
            });
        }

        let mut previous_new_seq = None;
        let mut required_cursor = state.cursor;
        let mut changed_item_ids = BTreeSet::new();

        for event in &request.events {
            if event.server_seq <= state.cursor {
                continue;
            }
            if event.server_seq <= 0 {
                return Err(sync_error(
                    CoreErrorCode::SyncInvalidEvent,
                    "server_seq must be positive",
                ));
            }
            if previous_new_seq.is_some_and(|previous| event.server_seq <= previous) {
                return Err(sync_error(
                    CoreErrorCode::SyncOrderingRegression,
                    "event batch is not strictly increasing",
                ));
            }
            previous_new_seq = Some(event.server_seq);
            required_cursor = required_cursor.max(event.server_seq);

            let content_hash = normalize_content_hash(&event.content_hash)?;
            if event.device_id == device_id {
                apply_own_event(&transaction, &sync_id, event, &content_hash)?;
                continue;
            }

            match event.event_type.as_str() {
                "item_upsert" => {
                    let item_id = apply_upsert_event(&transaction, &sync_id, event, &content_hash)?;
                    changed_item_ids.insert(item_id);
                }
                "item_delete" => {
                    if let Some(item_id) =
                        apply_delete_event(&transaction, &sync_id, event, &content_hash)?
                    {
                        changed_item_ids.insert(item_id);
                    }
                }
                _ => {
                    return Err(sync_error(
                        CoreErrorCode::SyncInvalidEvent,
                        "unknown sync event type",
                    ));
                }
            }
        }

        if request.next_cursor < required_cursor {
            return Err(sync_error(
                CoreErrorCode::SyncCursorRegression,
                "next cursor is behind applied events",
            ));
        }
        update_client_cursor(
            &transaction,
            &sync_id,
            request.next_cursor,
            state.snapshot_seq,
        )?;
        transaction.commit()?;

        Ok(SyncApplyOutcome {
            cursor: request.next_cursor,
            snapshot_seq: state.snapshot_seq,
            changed_item_ids: changed_item_ids.into_iter().collect(),
        })
    }

    pub fn apply_sync_snapshot(
        &mut self,
        request: SyncApplySnapshotRequest,
    ) -> Result<SyncApplyOutcome> {
        let sync_id = normalize_non_empty(&request.sync_id, "sync_id")?;
        let device_id = normalize_non_empty(&request.device_id, "device_id")?;
        if request.snapshot_seq < 0 {
            return Err(sync_error(
                CoreErrorCode::SyncCursorRegression,
                "snapshot_seq cannot be negative",
            ));
        }

        let transaction = self.connection.transaction()?;
        let _state = ensure_sync_client_state(&transaction, &sync_id, &device_id)?;
        let mut changed_item_ids = BTreeSet::new();

        for item in &request.items {
            if item.last_server_seq < 0 || item.last_server_seq > request.snapshot_seq {
                return Err(sync_error(
                    CoreErrorCode::SyncInvalidEvent,
                    "snapshot item sequence is invalid",
                ));
            }
            let content_hash = normalize_content_hash(&item.content_hash)?;
            let item_id = apply_upsert_snapshot(&transaction, &sync_id, item, &content_hash)?;
            changed_item_ids.insert(item_id);
        }

        for tombstone in &request.tombstones {
            if tombstone.last_server_seq < 0 || tombstone.last_server_seq > request.snapshot_seq {
                return Err(sync_error(
                    CoreErrorCode::SyncInvalidEvent,
                    "snapshot tombstone sequence is invalid",
                ));
            }
            let content_hash = normalize_content_hash(&tombstone.content_hash)?;
            if let Some(item_id) =
                apply_snapshot_tombstone(&transaction, &sync_id, tombstone, &content_hash)?
            {
                changed_item_ids.insert(item_id);
            }
        }

        update_client_cursor(
            &transaction,
            &sync_id,
            request.snapshot_seq,
            request.snapshot_seq,
        )?;
        transaction.commit()?;

        Ok(SyncApplyOutcome {
            cursor: request.snapshot_seq,
            snapshot_seq: request.snapshot_seq,
            changed_item_ids: changed_item_ids.into_iter().collect(),
        })
    }
}

fn ensure_sync_client_state(
    transaction: &Transaction<'_>,
    sync_id: &str,
    device_id: &str,
) -> Result<SyncClientState> {
    let now = now_ms();
    transaction.execute(
        r#"
        INSERT OR IGNORE INTO sync_client_state (
            sync_id, device_id, cursor, snapshot_seq, updated_at_ms
        )
        VALUES (?1, ?2, 0, 0, ?3)
        "#,
        params![sync_id, device_id, now],
    )?;

    let (stored_device_id, cursor, snapshot_seq): (String, i64, i64) = transaction.query_row(
        "SELECT device_id, cursor, snapshot_seq FROM sync_client_state WHERE sync_id = ?1",
        params![sync_id],
        |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
    )?;
    if stored_device_id != device_id {
        return Err(sync_error(
            CoreErrorCode::SyncIdentityMismatch,
            "sync_id is registered to another device_id",
        ));
    }
    if cursor < 0 || snapshot_seq < 0 || snapshot_seq > cursor {
        return Err(sync_error(
            CoreErrorCode::SyncCursorRegression,
            "local sync progress is corrupted",
        ));
    }
    Ok(SyncClientState {
        cursor,
        snapshot_seq,
    })
}

fn update_client_cursor(
    transaction: &Transaction<'_>,
    sync_id: &str,
    cursor: i64,
    snapshot_seq: i64,
) -> Result<()> {
    if cursor < 0 || snapshot_seq < 0 || snapshot_seq > cursor {
        return Err(sync_error(
            CoreErrorCode::SyncCursorRegression,
            "invalid local sync progress update",
        ));
    }
    transaction.execute(
        r#"
        UPDATE sync_client_state
        SET cursor = ?2, snapshot_seq = ?3, updated_at_ms = ?4
        WHERE sync_id = ?1
        "#,
        params![sync_id, cursor, snapshot_seq, now_ms()],
    )?;
    Ok(())
}

fn apply_own_event(
    transaction: &Transaction<'_>,
    sync_id: &str,
    event: &SyncEventRecord,
    content_hash: &str,
) -> Result<()> {
    let provenance = if event.event_type == "item_delete" {
        "remote_deleted"
    } else {
        "synced_local"
    };
    transaction.execute(
        r#"
        INSERT INTO sync_item_state (
            sync_id, content_hash, item_id, provenance, local_status,
            last_server_seq, last_client_event_id, local_pending_event_id, updated_at_ms
        )
        VALUES (
            ?1,
            ?2,
            (SELECT id FROM clipboard_items WHERE content_hash = ?2 ORDER BY deleted_at_ms IS NULL DESC LIMIT 1),
            ?3,
            ?4,
            ?5,
            ?6,
            NULL,
            ?7
        )
        ON CONFLICT(sync_id, content_hash) DO UPDATE SET
            item_id = COALESCE(sync_item_state.item_id, excluded.item_id),
            provenance = excluded.provenance,
            local_status = excluded.local_status,
            last_server_seq = MAX(sync_item_state.last_server_seq, excluded.last_server_seq),
            last_client_event_id = excluded.last_client_event_id,
            local_pending_event_id = NULL,
            updated_at_ms = excluded.updated_at_ms
        "#,
        params![
            sync_id,
            content_hash,
            provenance,
            if event.event_type == "item_delete" {
                "deleted"
            } else {
                "uploaded"
            },
            event.server_seq,
            event.client_event_id,
            now_ms()
        ],
    )?;
    Ok(())
}

fn apply_upsert_event(
    transaction: &Transaction<'_>,
    sync_id: &str,
    event: &SyncEventRecord,
    content_hash: &str,
) -> Result<String> {
    let payload = event.payload.as_ref().ok_or_else(|| {
        sync_error(
            CoreErrorCode::SyncInvalidEvent,
            "item_upsert event is missing payload",
        )
    })?;
    let item_type =
        normalize_non_empty(event.item_type.as_deref().unwrap_or_default(), "item_type")?;
    upsert_remote_item(
        transaction,
        sync_id,
        content_hash,
        Some(&event.device_id),
        Some(&event.client_event_id),
        event.server_seq,
        event.created_at_ms,
        &item_type,
        payload,
        ApplySource::Event {
            copy_count_delta: event.copy_count_delta.unwrap_or(1).max(1),
        },
    )
}

fn apply_upsert_snapshot(
    transaction: &Transaction<'_>,
    sync_id: &str,
    item: &SyncSnapshotItemRecord,
    content_hash: &str,
) -> Result<String> {
    upsert_remote_item(
        transaction,
        sync_id,
        content_hash,
        None,
        None,
        item.last_server_seq,
        item.updated_at_ms,
        &item.item_type,
        &item.payload,
        ApplySource::Snapshot {
            copy_count: item.copy_count.max(1),
        },
    )
}

#[allow(clippy::too_many_arguments)]
fn upsert_remote_item(
    transaction: &Transaction<'_>,
    sync_id: &str,
    content_hash: &str,
    remote_device_id: Option<&str>,
    client_event_id: Option<&str>,
    server_seq: i64,
    event_time_ms: i64,
    raw_item_type: &str,
    payload: &Value,
    source: ApplySource,
) -> Result<String> {
    let object = payload.as_object().ok_or_else(|| {
        sync_error(
            CoreErrorCode::SyncInvalidEvent,
            "sync item payload must be an object",
        )
    })?;
    let mapping = map_remote_item(raw_item_type, object)?;
    let source_app_id = upsert_source_app(
        transaction,
        mapping.source_bundle_id.as_deref(),
        mapping.source_app_name.as_deref(),
        event_time_ms,
    )?;
    let existing = find_existing_item(transaction, content_hash)?
        .or_else(|| any_item_for_hash(transaction, content_hash).ok().flatten());
    let item_id;
    let copy_count;

    match existing {
        Some((existing_item_id, existing_copy_count)) => {
            item_id = existing_item_id;
            copy_count = match source {
                ApplySource::Event { copy_count_delta } => existing_copy_count + copy_count_delta,
                ApplySource::Snapshot { copy_count } => copy_count,
            }
            .max(1);
            let first_copied_at_ms: i64 = transaction.query_row(
                "SELECT first_copied_at_ms FROM clipboard_items WHERE id = ?1",
                params![item_id],
                |row| row.get(0),
            )?;
            transaction.execute(
                r#"
                UPDATE clipboard_items
                SET
                    type = ?1,
                    summary = ?2,
                    primary_text = ?3,
                    source_app_id = ?4,
                    source_app_name = ?5,
                    source_confidence = 'unknown',
                    first_copied_at_ms = ?6,
                    last_copied_at_ms = ?7,
                    copy_count = ?8,
                    size_bytes = ?9,
                    preview_state = ?10,
                    payload_state = ?11,
                    deleted_at_ms = NULL,
                    updated_at_ms = ?7
                WHERE id = ?12
                "#,
                params![
                    mapping.item_type.as_str(),
                    mapping.summary,
                    mapping.primary_text,
                    source_app_id,
                    mapping.source_app_name,
                    first_copied_at_ms,
                    event_time_ms,
                    copy_count,
                    mapping.size_bytes,
                    mapping.preview_state,
                    effective_payload_state(transaction, &item_id, &mapping)?,
                    item_id
                ],
            )?;
        }
        None => {
            item_id = make_item_id(content_hash);
            copy_count = match source {
                ApplySource::Event { copy_count_delta } => copy_count_delta.max(1),
                ApplySource::Snapshot { copy_count } => copy_count.max(1),
            };
            transaction.execute(
                r#"
                INSERT INTO clipboard_items (
                    id, type, summary, primary_text, content_hash,
                    source_app_id, source_app_name, source_confidence,
                    first_copied_at_ms, last_copied_at_ms, copy_count,
                    is_pinned, size_bytes, preview_state, payload_state,
                    created_at_ms, updated_at_ms
                )
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 'unknown', ?8, ?8, ?9, 0, ?10, ?11, ?12, ?8, ?8)
                "#,
                params![
                    item_id,
                    mapping.item_type.as_str(),
                    mapping.summary,
                    mapping.primary_text,
                    content_hash,
                    source_app_id,
                    mapping.source_app_name,
                    event_time_ms,
                    copy_count,
                    mapping.size_bytes,
                    mapping.preview_state,
                    mapping.payload_state
                ],
            )?;
        }
    }

    if mapping.item_type == ClipboardItemType::Link {
        if let Some(link) = mapping.link.as_ref() {
            upsert_link_metadata(transaction, &item_id, link, event_time_ms)?;
        }
    } else {
        transaction.execute(
            "DELETE FROM link_metadata WHERE item_id = ?1",
            params![item_id],
        )?;
    }

    if mapping.item_type == ClipboardItemType::File {
        if let Some(file) = mapping.file.as_ref() {
            replace_remote_file_item(transaction, &item_id, file, event_time_ms)?;
        }
    } else {
        transaction.execute(
            "DELETE FROM clipboard_file_items WHERE item_id = ?1",
            params![item_id],
        )?;
    }

    if let Some(asset) = mapping.asset.as_ref() {
        upsert_remote_asset(transaction, sync_id, content_hash, asset, event_time_ms)?;
    }
    update_search_index(
        transaction,
        &item_id,
        &mapping.summary,
        mapping.primary_text.as_deref().unwrap_or_default(),
        mapping.source_app_name.as_deref().unwrap_or_default(),
    )?;
    upsert_synced_remote_state(
        transaction,
        sync_id,
        content_hash,
        &item_id,
        remote_device_id,
        client_event_id,
        server_seq,
    )?;
    Ok(item_id)
}

fn apply_delete_event(
    transaction: &Transaction<'_>,
    sync_id: &str,
    event: &SyncEventRecord,
    content_hash: &str,
) -> Result<Option<String>> {
    apply_tombstone(
        transaction,
        sync_id,
        content_hash,
        event.server_seq,
        Some(&event.device_id),
        Some(&event.client_event_id),
        event.created_at_ms,
    )
}

fn apply_snapshot_tombstone(
    transaction: &Transaction<'_>,
    sync_id: &str,
    tombstone: &SyncSnapshotTombstoneRecord,
    content_hash: &str,
) -> Result<Option<String>> {
    apply_tombstone(
        transaction,
        sync_id,
        content_hash,
        tombstone.last_server_seq,
        None,
        None,
        tombstone.deleted_at_ms,
    )
}

fn apply_tombstone(
    transaction: &Transaction<'_>,
    sync_id: &str,
    content_hash: &str,
    server_seq: i64,
    device_id: Option<&str>,
    client_event_id: Option<&str>,
    deleted_at_ms: i64,
) -> Result<Option<String>> {
    let state = sync_item_state(transaction, sync_id, content_hash)?;
    let item_id = state
        .as_ref()
        .and_then(|state| state.item_id.clone())
        .or_else(|| {
            active_item_id_for_hash(transaction, content_hash)
                .ok()
                .flatten()
        });
    let mut applied_to_local = false;
    let mut changed_item_id = None;

    let can_delete = state.as_ref().is_some_and(|state| {
        matches!(
            state.provenance.as_str(),
            "synced_remote" | "synced_local" | "remote_deleted"
        ) && state.last_server_seq < server_seq
    });
    if can_delete {
        if let Some(item_id) = item_id.as_deref() {
            let affected = transaction.execute(
                r#"
                UPDATE clipboard_items
                SET deleted_at_ms = COALESCE(deleted_at_ms, ?2), updated_at_ms = ?2
                WHERE id = ?1 AND deleted_at_ms IS NULL
                "#,
                params![item_id, deleted_at_ms],
            )?;
            applied_to_local = affected > 0;
            if applied_to_local {
                changed_item_id = Some(item_id.to_string());
            }
        }
    }

    transaction.execute(
        r#"
        INSERT OR IGNORE INTO sync_tombstones (
            sync_id, content_hash, server_seq, device_id, client_event_id,
            deleted_at_ms, applied_to_local, created_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        "#,
        params![
            sync_id,
            content_hash,
            server_seq,
            device_id,
            client_event_id,
            deleted_at_ms,
            if applied_to_local { 1 } else { 0 },
            now_ms()
        ],
    )?;

    if can_delete || item_id.is_none() {
        transaction.execute(
            r#"
            INSERT INTO sync_item_state (
                sync_id, content_hash, item_id, provenance, local_status,
                last_server_seq, last_remote_device_id, last_client_event_id, updated_at_ms
            )
            VALUES (?1, ?2, ?3, 'remote_deleted', 'deleted', ?4, ?5, ?6, ?7)
            ON CONFLICT(sync_id, content_hash) DO UPDATE SET
                item_id = COALESCE(sync_item_state.item_id, excluded.item_id),
                provenance = CASE
                    WHEN sync_item_state.provenance = 'local_pending_upload' THEN sync_item_state.provenance
                    ELSE 'remote_deleted'
                END,
                local_status = CASE
                    WHEN sync_item_state.provenance = 'local_pending_upload' THEN sync_item_state.local_status
                    ELSE 'deleted'
                END,
                last_server_seq = MAX(sync_item_state.last_server_seq, excluded.last_server_seq),
                last_remote_device_id = excluded.last_remote_device_id,
                last_client_event_id = excluded.last_client_event_id,
                updated_at_ms = excluded.updated_at_ms
            "#,
            params![
                sync_id,
                content_hash,
                item_id,
                server_seq,
                device_id,
                client_event_id,
                now_ms()
            ],
        )?;
    }

    Ok(changed_item_id)
}

fn upsert_synced_remote_state(
    transaction: &Transaction<'_>,
    sync_id: &str,
    content_hash: &str,
    item_id: &str,
    remote_device_id: Option<&str>,
    client_event_id: Option<&str>,
    server_seq: i64,
) -> Result<()> {
    transaction.execute(
        r#"
        INSERT INTO sync_item_state (
            sync_id, content_hash, item_id, provenance, local_status,
            last_server_seq, last_remote_device_id, last_client_event_id, updated_at_ms
        )
        VALUES (?1, ?2, ?3, 'synced_remote', 'uploaded', ?4, ?5, ?6, ?7)
        ON CONFLICT(sync_id, content_hash) DO UPDATE SET
            item_id = excluded.item_id,
            provenance = CASE
                WHEN sync_item_state.provenance = 'local_pending_upload' THEN sync_item_state.provenance
                ELSE 'synced_remote'
            END,
            local_status = CASE
                WHEN sync_item_state.provenance = 'local_pending_upload' THEN sync_item_state.local_status
                ELSE 'uploaded'
            END,
            last_server_seq = MAX(sync_item_state.last_server_seq, excluded.last_server_seq),
            last_remote_device_id = COALESCE(excluded.last_remote_device_id, sync_item_state.last_remote_device_id),
            last_client_event_id = COALESCE(excluded.last_client_event_id, sync_item_state.last_client_event_id),
            updated_at_ms = excluded.updated_at_ms
        "#,
        params![
            sync_id,
            content_hash,
            item_id,
            server_seq,
            remote_device_id,
            client_event_id,
            now_ms()
        ],
    )?;
    Ok(())
}

fn map_remote_item(raw_item_type: &str, object: &Map<String, Value>) -> Result<RemoteItemMapping> {
    let item_type = ClipboardItemType::from_storage(raw_item_type);
    let (source_app_name, source_bundle_id) = remote_source_identity(object);
    let source_payload_json = serde_json::to_string(object).unwrap_or_else(|_| "{}".to_string());
    let asset_id = payload_string(object, &["payload_asset_id", "asset_id"]);
    let byte_count = payload_i64(object, &["byte_count", "size_bytes"]).filter(|value| *value >= 0);
    let mime_type = payload_string(object, &["mime_type", "content_type"]);
    let file_name = payload_string(object, &["file_name", "filename", "title"]);

    let mapping = match item_type {
        ClipboardItemType::Text => {
            let primary_text = payload_string(object, &["text", "primary_text", "summary"])
                .ok_or_else(|| {
                    sync_error(
                        CoreErrorCode::SyncInvalidEvent,
                        "text payload is missing text",
                    )
                })?;
            RemoteItemMapping {
                item_type,
                summary: payload_string(object, &["summary", "title", "line_preview"])
                    .unwrap_or_else(|| summarize_remote_text(&primary_text)),
                primary_text: Some(primary_text.clone()),
                source_app_name,
                source_bundle_id,
                size_bytes: primary_text.len() as i64,
                preview_state: PreviewState::Ready.as_str(),
                payload_state: "ready",
                link: None,
                file: None,
                asset: None,
            }
        }
        ClipboardItemType::Link => {
            let canonical_url =
                payload_string(object, &["url", "canonical_url", "display_url", "text"])
                    .ok_or_else(|| {
                        sync_error(
                            CoreErrorCode::SyncInvalidEvent,
                            "link payload is missing url",
                        )
                    })?;
            let display_url = payload_string(object, &["display_url", "url"])
                .unwrap_or_else(|| canonical_url.clone());
            let host =
                payload_string(object, &["host"]).unwrap_or_else(|| host_from_url(&canonical_url));
            let title = payload_string(object, &["title"]);
            let site_name = payload_string(object, &["site_name"]);
            let primary_text = payload_string(object, &["text", "display_url", "url"])
                .unwrap_or_else(|| display_url.clone());
            RemoteItemMapping {
                item_type,
                summary: title
                    .clone()
                    .or_else(|| (!host.is_empty()).then(|| host.clone()))
                    .unwrap_or_else(|| display_url.clone()),
                primary_text: Some(primary_text.clone()),
                source_app_name,
                source_bundle_id,
                size_bytes: primary_text.len() as i64,
                preview_state: PreviewState::Ready.as_str(),
                payload_state: "ready",
                link: Some(RemoteLinkMapping {
                    original_text: primary_text,
                    canonical_url,
                    display_url,
                    host,
                    title,
                    site_name,
                    metadata_state: if payload_has_any(
                        object,
                        &[
                            "title",
                            "site_name",
                            "icon_asset_id",
                            "image_asset_id",
                            "icon_url",
                            "image_url",
                        ],
                    ) {
                        "ready"
                    } else {
                        "pending"
                    },
                }),
                file: None,
                asset: None,
            }
        }
        ClipboardItemType::Color => {
            let color = payload_string(object, &["hex", "color", "summary"]).ok_or_else(|| {
                sync_error(
                    CoreErrorCode::SyncInvalidEvent,
                    "color payload is missing hex",
                )
            })?;
            RemoteItemMapping {
                item_type,
                summary: color.clone(),
                primary_text: Some(color.clone()),
                source_app_name,
                source_bundle_id,
                size_bytes: color.len() as i64,
                preview_state: PreviewState::Ready.as_str(),
                payload_state: "ready",
                link: None,
                file: None,
                asset: None,
            }
        }
        ClipboardItemType::RichText => {
            let primary_text =
                payload_string(object, &["plain_text", "text", "summary"]).unwrap_or_default();
            let asset = asset_id.map(|asset_id| RemoteAssetMapping {
                asset_id,
                kind: "payload".to_string(),
                mime_type,
                byte_count,
                file_name,
                source_payload_json: source_payload_json.clone(),
            });
            RemoteItemMapping {
                item_type,
                summary: payload_string(object, &["summary", "plain_text", "text"])
                    .unwrap_or_else(|| "Rich Text".to_string()),
                primary_text: (!primary_text.is_empty()).then_some(primary_text.clone()),
                source_app_name,
                source_bundle_id,
                size_bytes: byte_count.unwrap_or(primary_text.len() as i64).max(0),
                preview_state: PreviewState::Ready.as_str(),
                payload_state: if asset.is_some() {
                    "remote_only"
                } else {
                    "ready"
                },
                link: None,
                file: None,
                asset,
            }
        }
        ClipboardItemType::Image => {
            let name = file_name.unwrap_or_else(|| "Image".to_string());
            let asset = asset_id.map(|asset_id| RemoteAssetMapping {
                asset_id,
                kind: "payload".to_string(),
                mime_type,
                byte_count,
                file_name: Some(name.clone()),
                source_payload_json: source_payload_json.clone(),
            });
            RemoteItemMapping {
                item_type,
                summary: payload_string(object, &["summary", "title"]).unwrap_or(name),
                primary_text: None,
                source_app_name,
                source_bundle_id,
                size_bytes: byte_count.unwrap_or(0).max(0),
                preview_state: PreviewState::MissingSource.as_str(),
                payload_state: if asset.is_some() {
                    "remote_only"
                } else {
                    "failed"
                },
                link: None,
                file: None,
                asset,
            }
        }
        ClipboardItemType::File => {
            let name = file_name.unwrap_or_else(|| "Remote File".to_string());
            let remote_id = asset_id
                .clone()
                .unwrap_or_else(|| stable_hash(&source_payload_json));
            let path = payload_string(object, &["path", "local_path"])
                .unwrap_or_else(|| format!("clipdock-remote://{remote_id}"));
            let extension = name.rsplit_once('.').map(|(_, value)| value.to_string());
            let asset = asset_id.map(|asset_id| RemoteAssetMapping {
                asset_id,
                kind: "payload".to_string(),
                mime_type: mime_type.clone(),
                byte_count,
                file_name: Some(name.clone()),
                source_payload_json: source_payload_json.clone(),
            });
            RemoteItemMapping {
                item_type,
                summary: payload_string(object, &["summary", "title"])
                    .unwrap_or_else(|| name.clone()),
                primary_text: Some(path.clone()),
                source_app_name,
                source_bundle_id,
                size_bytes: byte_count.unwrap_or(0).max(0),
                preview_state: PreviewState::MissingSource.as_str(),
                payload_state: if path.starts_with("clipdock-remote://") {
                    "remote_only"
                } else {
                    "ready"
                },
                link: None,
                file: Some(RemoteFileMapping {
                    path,
                    file_name: name,
                    file_extension: extension,
                    byte_count: byte_count.unwrap_or(0).max(0),
                    is_directory: payload_bool(object, &["is_directory"]).unwrap_or(false),
                    width: payload_i64(object, &["width"]).filter(|value| *value > 0),
                    height: payload_i64(object, &["height"]).filter(|value| *value > 0),
                    content_type: mime_type,
                }),
                asset,
            }
        }
        ClipboardItemType::Unknown => {
            let primary_text = payload_string(object, &["text", "summary"]);
            RemoteItemMapping {
                item_type,
                summary: payload_string(object, &["title", "summary", "text"])
                    .unwrap_or_else(|| "Unknown".to_string()),
                primary_text,
                source_app_name,
                source_bundle_id,
                size_bytes: byte_count.unwrap_or(0).max(0),
                preview_state: PreviewState::Ready.as_str(),
                payload_state: "ready",
                link: None,
                file: None,
                asset: None,
            }
        }
    };

    Ok(mapping)
}

fn remote_source_identity(object: &Map<String, Value>) -> (Option<String>, Option<String>) {
    let source_platform =
        payload_string(object, &["source_platform", "origin_platform", "platform"])
            .map(|value| value.trim().to_ascii_lowercase());

    if source_platform.as_deref() == Some("android") {
        return (
            Some(ANDROID_PLATFORM_SOURCE_APP_NAME.to_string()),
            Some(ANDROID_PLATFORM_SOURCE_BUNDLE_ID.to_string()),
        );
    }

    (
        payload_string(object, &["source_app_name", "source"]),
        payload_string(object, &["source_bundle_id", "bundle_id"]),
    )
}

fn effective_payload_state(
    transaction: &Transaction<'_>,
    item_id: &str,
    mapping: &RemoteItemMapping,
) -> Result<&'static str> {
    if mapping.payload_state != "remote_only" {
        return Ok(mapping.payload_state);
    }
    let has_local_payload: bool = transaction.query_row(
        r#"
        SELECT EXISTS(
            SELECT 1
            FROM clipboard_assets
            WHERE item_id = ?1
                AND kind IN ('payload', 'rtf', 'file_snapshot')
        )
        "#,
        params![item_id],
        |row| row.get::<_, i64>(0).map(|value| value == 1),
    )?;
    Ok(if has_local_payload {
        "ready"
    } else {
        "remote_only"
    })
}

fn upsert_source_app(
    transaction: &Transaction<'_>,
    bundle_id: Option<&str>,
    app_name: Option<&str>,
    now: i64,
) -> Result<Option<String>> {
    let app_name = app_name.map(str::trim).filter(|value| !value.is_empty());
    let bundle_id = bundle_id.map(str::trim).filter(|value| !value.is_empty());
    let Some(app_name) = app_name else {
        return Ok(None);
    };
    let derived_key = bundle_id
        .map(|value| format!("bundle:{value}"))
        .unwrap_or_else(|| format!("name:{}", app_name.to_lowercase()));
    let source_app_id = format!("source_{}", &stable_hash(&derived_key)[..24]);
    transaction.execute(
        r#"
        INSERT INTO source_apps (
            id, bundle_id, derived_key, name, bundle_path,
            last_seen_at_ms, created_at_ms, updated_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, NULL, ?5, ?5, ?5)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
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
            now
        ],
    )?;
    Ok(Some(source_app_id))
}

fn upsert_link_metadata(
    transaction: &Transaction<'_>,
    item_id: &str,
    link: &RemoteLinkMapping,
    now: i64,
) -> Result<()> {
    transaction.execute(
        r#"
        INSERT INTO link_metadata (
            item_id, original_text, canonical_url, display_url, host,
            title, site_name, metadata_state, created_at_ms, updated_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)
        ON CONFLICT(item_id) DO UPDATE SET
            original_text = excluded.original_text,
            canonical_url = excluded.canonical_url,
            display_url = excluded.display_url,
            host = excluded.host,
            title = excluded.title,
            site_name = excluded.site_name,
            metadata_state = excluded.metadata_state,
            failure_code = NULL,
            updated_at_ms = excluded.updated_at_ms
        "#,
        params![
            item_id,
            link.original_text,
            link.canonical_url,
            link.display_url,
            link.host,
            link.title,
            link.site_name,
            link.metadata_state,
            now
        ],
    )?;
    Ok(())
}

fn replace_remote_file_item(
    transaction: &Transaction<'_>,
    item_id: &str,
    file: &RemoteFileMapping,
    now: i64,
) -> Result<()> {
    transaction.execute(
        "DELETE FROM clipboard_file_items WHERE item_id = ?1",
        params![item_id],
    )?;
    let id = format!(
        "file_item_{}",
        &stable_hash(&format!("{item_id}:0:{}", file.path))[..24]
    );
    transaction.execute(
        r#"
        INSERT INTO clipboard_file_items (
            id, item_id, order_index, path, file_name, file_extension,
            byte_count, is_directory, width, height, content_type,
            created_at_ms, updated_at_ms
        )
        VALUES (?1, ?2, 0, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11)
        "#,
        params![
            id,
            item_id,
            file.path,
            file.file_name,
            file.file_extension,
            file.byte_count,
            if file.is_directory { 1 } else { 0 },
            file.width,
            file.height,
            file.content_type,
            now
        ],
    )?;
    Ok(())
}

fn upsert_remote_asset(
    transaction: &Transaction<'_>,
    sync_id: &str,
    content_hash: &str,
    asset: &RemoteAssetMapping,
    now: i64,
) -> Result<()> {
    transaction.execute(
        r#"
        INSERT INTO sync_remote_assets (
            sync_id, content_hash, asset_id, kind, mime_type, byte_count,
            file_name, source_payload_json, updated_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
        ON CONFLICT(sync_id, content_hash, kind) DO UPDATE SET
            asset_id = excluded.asset_id,
            mime_type = excluded.mime_type,
            byte_count = excluded.byte_count,
            file_name = excluded.file_name,
            source_payload_json = excluded.source_payload_json,
            updated_at_ms = excluded.updated_at_ms
        "#,
        params![
            sync_id,
            content_hash,
            asset.asset_id,
            asset.kind,
            asset.mime_type,
            asset.byte_count,
            asset.file_name,
            asset.source_payload_json,
            now
        ],
    )?;
    Ok(())
}

fn sync_item_state(
    transaction: &Transaction<'_>,
    sync_id: &str,
    content_hash: &str,
) -> Result<Option<SyncItemState>> {
    transaction
        .query_row(
            r#"
            SELECT item_id, provenance, last_server_seq
            FROM sync_item_state
            WHERE sync_id = ?1 AND content_hash = ?2
            "#,
            params![sync_id, content_hash],
            |row| {
                Ok(SyncItemState {
                    item_id: row.get(0)?,
                    provenance: row.get(1)?,
                    last_server_seq: row.get(2)?,
                })
            },
        )
        .optional()
        .map_err(Into::into)
}

fn active_item_id_for_hash(
    transaction: &Transaction<'_>,
    content_hash: &str,
) -> Result<Option<String>> {
    transaction
        .query_row(
            "SELECT id FROM clipboard_items WHERE content_hash = ?1 AND deleted_at_ms IS NULL",
            params![content_hash],
            |row| row.get(0),
        )
        .optional()
        .map_err(Into::into)
}

fn any_item_for_hash(
    transaction: &Transaction<'_>,
    content_hash: &str,
) -> Result<Option<(String, i64)>> {
    transaction
        .query_row(
            "SELECT id, copy_count FROM clipboard_items WHERE content_hash = ?1 ORDER BY deleted_at_ms IS NULL DESC LIMIT 1",
            params![content_hash],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()
        .map_err(Into::into)
}

fn normalize_content_hash(value: &str) -> Result<String> {
    let value = value.trim();
    let Some(hash) = value.strip_prefix("blake3:") else {
        return Err(sync_error(
            CoreErrorCode::SyncInvalidEvent,
            "content_hash must be blake3 lowercase hex",
        ));
    };
    if hash.len() == 64
        && hash
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        Ok(hash.to_string())
    } else {
        Err(sync_error(
            CoreErrorCode::SyncInvalidEvent,
            "content_hash must be blake3 lowercase hex",
        ))
    }
}

fn normalize_non_empty(value: &str, field: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            format!("{field} cannot be empty"),
        ))
    } else {
        Ok(value.to_string())
    }
}

fn payload_string(object: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    keys.iter().find_map(|key| {
        object
            .get(*key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    })
}

fn payload_i64(object: &Map<String, Value>, keys: &[&str]) -> Option<i64> {
    keys.iter()
        .find_map(|key| object.get(*key).and_then(Value::as_i64))
}

fn payload_bool(object: &Map<String, Value>, keys: &[&str]) -> Option<bool> {
    keys.iter()
        .find_map(|key| object.get(*key).and_then(Value::as_bool))
}

fn payload_has_any(object: &Map<String, Value>, keys: &[&str]) -> bool {
    keys.iter().any(|key| {
        object.get(*key).is_some_and(|value| match value {
            Value::Null => false,
            Value::String(value) => !value.trim().is_empty(),
            _ => true,
        })
    })
}

fn summarize_remote_text(value: &str) -> String {
    let trimmed = value.trim();
    let first_line = trimmed.lines().next().unwrap_or(trimmed);
    let mut summary = first_line.chars().take(80).collect::<String>();
    if summary.is_empty() {
        summary = "Text".to_string();
    }
    summary
}

fn host_from_url(url: &str) -> String {
    let Some(separator) = url.find("://") else {
        return String::new();
    };
    let after_scheme = &url[separator + 3..];
    let host_end = after_scheme
        .find(|character| matches!(character, '/' | '?' | '#'))
        .unwrap_or(after_scheme.len());
    after_scheme[..host_end]
        .trim()
        .trim_matches('.')
        .to_ascii_lowercase()
}

fn sync_error(code: CoreErrorCode, message: &str) -> CoreError {
    CoreError::new(code, message)
}
