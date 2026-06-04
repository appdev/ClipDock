use clipdock_sync_contract::{
    PayloadAssetUpdate as PayloadAssetUpdateShape, ThumbnailMetadata, EVENT_TYPE_ITEM_DELETE,
    EVENT_TYPE_ITEM_PAYLOAD_ASSET_UPDATE, EVENT_TYPE_ITEM_UPSERT, ITEM_TYPE_IMAGE,
    P2P_PROVIDER_KIND_IMAGE_PAYLOAD,
};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sqlx::{Row, SqlitePool};

use crate::{auth::DeviceAuth, db, errors::AppError, hashes::ContentHash, realtime::EventHub};

#[derive(Deserialize)]
pub struct PushEventsRequest {
    pub events: Vec<IncomingEvent>,
}

#[derive(Deserialize)]
pub struct IncomingEvent {
    pub client_event_id: String,
    #[serde(rename = "type")]
    pub event_type: String,
    pub content_hash: String,
    #[serde(default)]
    pub item_type: Option<String>,
    #[serde(default)]
    pub payload: Option<Value>,
    #[serde(default)]
    pub copy_count_delta: Option<i64>,
}

#[derive(Serialize)]
pub struct PushEventsResponse {
    pub events: Vec<PushedEvent>,
    pub next_cursor: i64,
}

#[derive(Serialize)]
pub struct PushedEvent {
    pub client_event_id: String,
    pub server_seq: i64,
    pub duplicate: bool,
}

#[derive(Serialize)]
pub struct PullEventsResponse {
    pub events: Vec<EventOut>,
    pub next_cursor: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct EventOut {
    pub server_seq: i64,
    pub device_id: String,
    pub client_event_id: String,
    #[serde(rename = "type")]
    pub event_type: String,
    pub content_hash: String,
    pub item_type: Option<String>,
    pub payload: Option<Value>,
    pub copy_count_delta: Option<i64>,
    pub created_at_ms: i64,
}

#[derive(Serialize)]
pub struct SnapshotResponse {
    pub snapshot_seq: i64,
    pub items: Vec<SnapshotItem>,
    pub tombstones: Vec<SnapshotTombstone>,
}

#[derive(Serialize)]
pub struct SnapshotItem {
    pub content_hash: String,
    pub item_type: String,
    pub payload: Value,
    pub copy_count: i64,
    pub updated_at_ms: i64,
    pub last_server_seq: i64,
}

#[derive(Serialize)]
pub struct SnapshotTombstone {
    pub content_hash: String,
    pub deleted_at_ms: i64,
    pub last_server_seq: i64,
}

pub fn validate_content_hash(value: &str) -> bool {
    ContentHash::is_valid(value)
}

pub async fn push_events(
    pool: &SqlitePool,
    realtime: &EventHub,
    auth: DeviceAuth,
    request: PushEventsRequest,
) -> Result<PushEventsResponse, AppError> {
    if request.events.is_empty() {
        return Err(AppError::BadRequest("empty_batch"));
    }
    if request
        .events
        .iter()
        .any(|event| event.event_type == EVENT_TYPE_ITEM_PAYLOAD_ASSET_UPDATE)
        && request.events.len() != 1
    {
        return Err(AppError::BadRequest(
            "payload_asset_update_must_be_single_event",
        ));
    }

    let mut tx = pool.begin().await?;
    let mut pushed = Vec::with_capacity(request.events.len());
    let mut inserted_server_seqs = Vec::new();

    for event in request.events {
        validate_incoming(&event)?;

        if let Some(server_seq) = sqlx::query(
            "SELECT server_seq FROM sync_events WHERE device_id = ? AND client_event_id = ?",
        )
        .bind(&auth.device_id)
        .bind(&event.client_event_id)
        .fetch_optional(&mut *tx)
        .await?
        .map(|row| row.get::<i64, _>("server_seq"))
        {
            pushed.push(PushedEvent {
                client_event_id: event.client_event_id,
                server_seq,
                duplicate: true,
            });
            continue;
        }

        let payload_json = event
            .payload
            .as_ref()
            .map(serde_json::to_string)
            .transpose()
            .map_err(|error| AppError::Internal(error.to_string()))?;
        let thumbnail = validate_thumbnail_payload(&mut tx, &auth, &event).await?;
        let payload_update = validate_payload_asset_update(&mut tx, &auth, &event).await?;
        let normalized_copy_count_delta = match event.event_type.as_str() {
            EVENT_TYPE_ITEM_UPSERT => Some(event.copy_count_delta.unwrap_or(1)),
            _ => None,
        };
        let now = db::now_ms().await;
        let result = sqlx::query(
            "INSERT OR IGNORE INTO sync_events(
                sync_group_id, device_id, client_event_id, event_type, content_hash, item_type,
                payload_json, copy_count_delta, created_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&auth.sync_group_id)
        .bind(&auth.device_id)
        .bind(&event.client_event_id)
        .bind(&event.event_type)
        .bind(&event.content_hash)
        .bind(&event.item_type)
        .bind(&payload_json)
        .bind(normalized_copy_count_delta)
        .bind(now)
        .execute(&mut *tx)
        .await?;

        if result.rows_affected() == 0 {
            let server_seq = sqlx::query(
                "SELECT server_seq FROM sync_events WHERE device_id = ? AND client_event_id = ?",
            )
            .bind(&auth.device_id)
            .bind(&event.client_event_id)
            .fetch_one(&mut *tx)
            .await?
            .get::<i64, _>("server_seq");
            pushed.push(PushedEvent {
                client_event_id: event.client_event_id,
                server_seq,
                duplicate: true,
            });
            continue;
        }

        let server_seq = sqlx::query("SELECT last_insert_rowid() AS id")
            .fetch_one(&mut *tx)
            .await?
            .get::<i64, _>("id");

        match event.event_type.as_str() {
            EVENT_TYPE_ITEM_UPSERT => {
                let item_type = event.item_type.as_deref().expect("validated item_type");
                let payload_json = payload_json.as_deref().expect("validated payload");
                let delta = normalized_copy_count_delta.expect("validated copy_count_delta");
                let update = sqlx::query(
                    "UPDATE sync_items
                     SET item_type = ?, payload_json = ?, copy_count = copy_count + ?,
                         deleted_at_ms = NULL, updated_at_ms = ?, last_server_seq = ?
                     WHERE sync_group_id = ? AND content_hash = ?",
                )
                .bind(item_type)
                .bind(payload_json)
                .bind(delta)
                .bind(now)
                .bind(server_seq)
                .bind(&auth.sync_group_id)
                .bind(&event.content_hash)
                .execute(&mut *tx)
                .await?;
                if update.rows_affected() == 0 {
                    sqlx::query(
                        "INSERT INTO sync_items(
                            sync_group_id, content_hash, item_type, payload_json, copy_count,
                            updated_at_ms, last_server_seq
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)",
                    )
                    .bind(&auth.sync_group_id)
                    .bind(&event.content_hash)
                    .bind(item_type)
                    .bind(payload_json)
                    .bind(delta)
                    .bind(now)
                    .bind(server_seq)
                    .execute(&mut *tx)
                    .await?;
                }
                if let Some(thumbnail) = thumbnail {
                    replace_thumbnail_link(&mut tx, &auth, &event.content_hash, &thumbnail.digest)
                        .await?;
                } else {
                    clear_thumbnail_link(&mut tx, &auth, &event.content_hash).await?;
                }
            }
            EVENT_TYPE_ITEM_DELETE => {
                let update = sqlx::query(
                    "UPDATE sync_items
                     SET deleted_at_ms = COALESCE(deleted_at_ms, ?),
                         updated_at_ms = ?, last_server_seq = ?
                     WHERE sync_group_id = ? AND content_hash = ?",
                )
                .bind(now)
                .bind(now)
                .bind(server_seq)
                .bind(&auth.sync_group_id)
                .bind(&event.content_hash)
                .execute(&mut *tx)
                .await?;
                if update.rows_affected() == 0 {
                    sqlx::query(
                        "INSERT INTO sync_items(
                            sync_group_id, content_hash, copy_count, deleted_at_ms, updated_at_ms, last_server_seq
                        ) VALUES (?, ?, 0, ?, ?, ?)",
                    )
                    .bind(&auth.sync_group_id)
                    .bind(&event.content_hash)
                    .bind(now)
                    .bind(now)
                    .bind(server_seq)
                    .execute(&mut *tx)
                    .await?;
                }
                clear_thumbnail_link(&mut tx, &auth, &event.content_hash).await?;
            }
            EVENT_TYPE_ITEM_PAYLOAD_ASSET_UPDATE => {
                let update = payload_update.expect("validated payload update");
                let row = sqlx::query(
                    "SELECT payload_json
                     FROM sync_items
                     WHERE sync_group_id = ? AND content_hash = ?",
                )
                .bind(&auth.sync_group_id)
                .bind(&event.content_hash)
                .fetch_one(&mut *tx)
                .await?;
                let payload_json_value: Option<String> = row.try_get("payload_json")?;
                let mut payload = payload_json_value
                    .as_deref()
                    .map(serde_json::from_str::<Value>)
                    .transpose()
                    .map_err(|error| AppError::Internal(error.to_string()))?
                    .and_then(|value| match value {
                        Value::Object(map) => Some(map),
                        _ => None,
                    })
                    .unwrap_or_default();
                payload.insert(
                    "payload_asset_id".to_string(),
                    Value::String(update.asset_id.clone()),
                );
                payload.insert("asset_id".to_string(), Value::String(update.asset_id));
                let merged_payload_json = serde_json::to_string(&Value::Object(payload))
                    .map_err(|error| AppError::Internal(error.to_string()))?;
                sqlx::query(
                    "UPDATE sync_items
                     SET payload_json = ?, last_server_seq = ?
                     WHERE sync_group_id = ? AND content_hash = ?",
                )
                .bind(&merged_payload_json)
                .bind(server_seq)
                .bind(&auth.sync_group_id)
                .bind(&event.content_hash)
                .execute(&mut *tx)
                .await?;
            }
            _ => return Err(AppError::BadRequest("invalid_event_type")),
        }

        pushed.push(PushedEvent {
            client_event_id: event.client_event_id,
            server_seq,
            duplicate: false,
        });
        inserted_server_seqs.push(server_seq);
    }

    let next_cursor = latest_seq_tx(&mut tx, &auth.sync_group_id).await?;
    tx.commit().await?;

    if !inserted_server_seqs.is_empty() {
        let events = events_by_server_seq(pool, &auth.sync_group_id, &inserted_server_seqs).await?;
        realtime.broadcast(&auth.sync_group_id, events).await;
    }

    Ok(PushEventsResponse {
        events: pushed,
        next_cursor,
    })
}

pub fn parse_event_query(query: Option<&str>) -> Result<(i64, i64), AppError> {
    let mut after_seq = 0_i64;
    let mut limit = 500_i64;

    if let Some(query) = query {
        for pair in query.split('&').filter(|pair| !pair.is_empty()) {
            let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
            match key {
                "after_seq" => {
                    after_seq = value
                        .parse::<i64>()
                        .map_err(|_| AppError::BadRequest("invalid_cursor"))?;
                    if after_seq < 0 {
                        return Err(AppError::BadRequest("invalid_cursor"));
                    }
                }
                "limit" => {
                    limit = value
                        .parse::<i64>()
                        .map_err(|_| AppError::BadRequest("invalid_limit"))?;
                    if limit <= 0 {
                        return Err(AppError::BadRequest("invalid_limit"));
                    }
                    limit = limit.min(1000);
                }
                _ => {}
            }
        }
    }

    Ok((after_seq, limit))
}

pub async fn pull_events(
    pool: &SqlitePool,
    auth: DeviceAuth,
    after_seq: i64,
    limit: i64,
) -> Result<PullEventsResponse, AppError> {
    let rows = sqlx::query(
        "SELECT server_seq, device_id, client_event_id, event_type, content_hash,
                item_type, payload_json, copy_count_delta, created_at_ms
         FROM sync_events
         WHERE sync_group_id = ? AND server_seq > ?
         ORDER BY server_seq ASC
         LIMIT ?",
    )
    .bind(&auth.sync_group_id)
    .bind(after_seq)
    .bind(limit)
    .fetch_all(pool)
    .await?;

    let mut events = Vec::with_capacity(rows.len());
    for row in rows {
        let payload_json: Option<String> = row.try_get("payload_json")?;
        let payload = payload_json
            .map(|value| serde_json::from_str(&value))
            .transpose()
            .map_err(|error| AppError::Internal(error.to_string()))?;
        events.push(EventOut {
            server_seq: row.try_get("server_seq")?,
            device_id: row.try_get("device_id")?,
            client_event_id: row.try_get("client_event_id")?,
            event_type: row.try_get("event_type")?,
            content_hash: row.try_get("content_hash")?,
            item_type: row.try_get("item_type")?,
            payload,
            copy_count_delta: row.try_get("copy_count_delta")?,
            created_at_ms: row.try_get("created_at_ms")?,
        });
    }

    let latest = latest_seq(pool, &auth.sync_group_id).await?;
    let next_cursor = events
        .last()
        .map(|event| event.server_seq)
        .unwrap_or_else(|| after_seq.min(latest));
    Ok(PullEventsResponse {
        events,
        next_cursor: next_cursor.max(latest.min(after_seq)),
    })
}

pub async fn snapshot(pool: &SqlitePool, auth: DeviceAuth) -> Result<SnapshotResponse, AppError> {
    let mut tx = pool.begin().await?;
    let snapshot_seq = latest_seq_tx(&mut tx, &auth.sync_group_id).await?;

    let item_rows = sqlx::query(
        "SELECT content_hash, item_type, payload_json, copy_count, updated_at_ms, last_server_seq
         FROM sync_items
         WHERE sync_group_id = ? AND deleted_at_ms IS NULL AND last_server_seq <= ?
         ORDER BY content_hash ASC",
    )
    .bind(&auth.sync_group_id)
    .bind(snapshot_seq)
    .fetch_all(&mut *tx)
    .await?;

    let tombstone_rows = sqlx::query(
        "SELECT content_hash, deleted_at_ms, last_server_seq
         FROM sync_items
         WHERE sync_group_id = ? AND deleted_at_ms IS NOT NULL AND last_server_seq <= ?
         ORDER BY content_hash ASC",
    )
    .bind(&auth.sync_group_id)
    .bind(snapshot_seq)
    .fetch_all(&mut *tx)
    .await?;

    let mut items = Vec::with_capacity(item_rows.len());
    for row in item_rows {
        let item_type: Option<String> = row.try_get("item_type")?;
        let payload_json: Option<String> = row.try_get("payload_json")?;
        items.push(SnapshotItem {
            content_hash: row.try_get("content_hash")?,
            item_type: item_type.unwrap_or_default(),
            payload: payload_json
                .as_deref()
                .map(serde_json::from_str)
                .transpose()
                .map_err(|error| AppError::Internal(error.to_string()))?
                .unwrap_or(Value::Null),
            copy_count: row.try_get("copy_count")?,
            updated_at_ms: row.try_get("updated_at_ms")?,
            last_server_seq: row.try_get("last_server_seq")?,
        });
    }

    let mut tombstones = Vec::with_capacity(tombstone_rows.len());
    for row in tombstone_rows {
        tombstones.push(SnapshotTombstone {
            content_hash: row.try_get("content_hash")?,
            deleted_at_ms: row.try_get("deleted_at_ms")?,
            last_server_seq: row.try_get("last_server_seq")?,
        });
    }

    tx.commit().await?;
    Ok(SnapshotResponse {
        snapshot_seq,
        items,
        tombstones,
    })
}

pub async fn latest_seq(pool: &SqlitePool, sync_group_id: &str) -> Result<i64, sqlx::Error> {
    sqlx::query(
        "SELECT COALESCE(MAX(server_seq), 0) AS latest
         FROM sync_events
         WHERE sync_group_id = ?",
    )
    .bind(sync_group_id)
    .fetch_one(pool)
    .await
    .map(|row| row.get::<i64, _>("latest"))
}

pub async fn events_by_server_seq(
    pool: &SqlitePool,
    sync_group_id: &str,
    server_seqs: &[i64],
) -> Result<Vec<EventOut>, AppError> {
    let mut events = Vec::with_capacity(server_seqs.len());
    for server_seq in server_seqs {
        let row = sqlx::query(
            "SELECT server_seq, device_id, client_event_id, event_type, content_hash,
                    item_type, payload_json, copy_count_delta, created_at_ms
             FROM sync_events
             WHERE sync_group_id = ? AND server_seq = ?",
        )
        .bind(sync_group_id)
        .bind(server_seq)
        .fetch_one(pool)
        .await?;
        let payload_json: Option<String> = row.try_get("payload_json")?;
        let payload = payload_json
            .map(|value| serde_json::from_str(&value))
            .transpose()
            .map_err(|error| AppError::Internal(error.to_string()))?;
        events.push(EventOut {
            server_seq: row.try_get("server_seq")?,
            device_id: row.try_get("device_id")?,
            client_event_id: row.try_get("client_event_id")?,
            event_type: row.try_get("event_type")?,
            content_hash: row.try_get("content_hash")?,
            item_type: row.try_get("item_type")?,
            payload,
            copy_count_delta: row.try_get("copy_count_delta")?,
            created_at_ms: row.try_get("created_at_ms")?,
        });
    }
    events.sort_by_key(|event| event.server_seq);
    Ok(events)
}

async fn latest_seq_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    sync_group_id: &str,
) -> Result<i64, sqlx::Error> {
    sqlx::query(
        "SELECT COALESCE(MAX(server_seq), 0) AS latest
         FROM sync_events
         WHERE sync_group_id = ?",
    )
    .bind(sync_group_id)
    .fetch_one(&mut **tx)
    .await
    .map(|row| row.get::<i64, _>("latest"))
}

fn validate_incoming(event: &IncomingEvent) -> Result<(), AppError> {
    if event.client_event_id.trim().is_empty() || event.client_event_id.len() > 128 {
        return Err(AppError::BadRequest("invalid_client_event_id"));
    }
    if !validate_content_hash(&event.content_hash) {
        return Err(AppError::BadRequest("invalid_content_hash"));
    }
    match event.event_type.as_str() {
        EVENT_TYPE_ITEM_UPSERT => {
            let delta = event.copy_count_delta.unwrap_or(1);
            if !(1..=100).contains(&delta) {
                return Err(AppError::BadRequest("invalid_copy_count_delta"));
            }
            if event
                .item_type
                .as_deref()
                .unwrap_or_default()
                .trim()
                .is_empty()
            {
                return Err(AppError::BadRequest("invalid_item_type"));
            }
            if event.payload.is_none() {
                return Err(AppError::BadRequest("invalid_payload"));
            }
        }
        EVENT_TYPE_ITEM_DELETE => {}
        EVENT_TYPE_ITEM_PAYLOAD_ASSET_UPDATE => {
            if event.copy_count_delta.is_some() {
                return Err(AppError::BadRequest(
                    "payload_asset_update_copy_count_delta_not_allowed",
                ));
            }
            if event.item_type.as_deref() != Some(ITEM_TYPE_IMAGE) {
                return Err(AppError::BadRequest(
                    "payload_asset_update_invalid_item_type",
                ));
            }
            if event.payload.is_none() {
                return Err(AppError::BadRequest("invalid_payload_asset_update_payload"));
            }
        }
        _ => return Err(AppError::BadRequest("invalid_event_type")),
    }
    Ok(())
}

#[derive(Debug)]
struct ThumbnailReference {
    digest: String,
}

#[derive(Debug)]
struct PayloadAssetUpdate {
    asset_id: String,
}

async fn validate_thumbnail_payload(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    auth: &DeviceAuth,
    event: &IncomingEvent,
) -> Result<Option<ThumbnailReference>, AppError> {
    if event.event_type != EVENT_TYPE_ITEM_UPSERT {
        return Ok(None);
    }
    let payload = event
        .payload
        .as_ref()
        .and_then(Value::as_object)
        .ok_or(AppError::BadRequest("invalid_payload"))?;
    let Some(metadata) = ThumbnailMetadata::parse_shape_strict(event.item_type.as_deref(), payload)
        .map_err(|error| AppError::BadRequest(error.code()))?
    else {
        return Ok(None);
    };
    let digest = metadata.digest.as_str();
    crate::assets::validate_digest(digest)?;
    let mime_type = metadata.mime_type.as_str();
    let byte_count = metadata.byte_count;
    let width = metadata.width;
    let height = metadata.height;

    let row = sqlx::query(
        "SELECT kind, mime_type, size_bytes, width_px, height_px
         FROM sync_assets
         WHERE sync_group_id = ? AND digest = ?",
    )
    .bind(&auth.sync_group_id)
    .bind(digest)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(AppError::BadRequest("thumbnail_asset_not_found"))?;

    let kind: String = row.try_get("kind")?;
    let stored_mime: String = row.try_get("mime_type")?;
    let stored_size: i64 = row.try_get("size_bytes")?;
    let stored_width: Option<i64> = row.try_get("width_px")?;
    let stored_height: Option<i64> = row.try_get("height_px")?;
    if stored_width.is_none() || stored_height.is_none() {
        return Err(AppError::BadRequest("thumbnail_asset_dimensions_missing"));
    }
    if kind != "thumbnail"
        || stored_mime != mime_type
        || stored_size != byte_count
        || stored_width != Some(width)
        || stored_height != Some(height)
    {
        return Err(AppError::BadRequest("thumbnail_asset_metadata_mismatch"));
    }
    Ok(Some(ThumbnailReference {
        digest: digest.to_string(),
    }))
}

async fn validate_payload_asset_update(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    auth: &DeviceAuth,
    event: &IncomingEvent,
) -> Result<Option<PayloadAssetUpdate>, AppError> {
    if event.event_type != EVENT_TYPE_ITEM_PAYLOAD_ASSET_UPDATE {
        return Ok(None);
    }
    let payload = event
        .payload
        .as_ref()
        .and_then(Value::as_object)
        .ok_or(AppError::BadRequest("invalid_payload_asset_update_payload"))?;
    let asset_update = validate_payload_asset_update_payload(payload)?;
    let asset_id = asset_update.asset_id;

    let item_row = sqlx::query(
        "SELECT item_type, deleted_at_ms
         FROM sync_items
         WHERE sync_group_id = ? AND content_hash = ?",
    )
    .bind(&auth.sync_group_id)
    .bind(&event.content_hash)
    .fetch_optional(&mut **tx)
    .await?
    .ok_or(AppError::Conflict("payload_asset_update_item_missing"))?;
    let deleted_at: Option<i64> = item_row.try_get("deleted_at_ms")?;
    if deleted_at.is_some() {
        return Err(AppError::Conflict("payload_asset_update_item_deleted"));
    }
    let item_type: Option<String> = item_row.try_get("item_type")?;
    if item_type.as_deref() != Some(ITEM_TYPE_IMAGE) {
        return Err(AppError::Conflict(
            "payload_asset_update_item_type_mismatch",
        ));
    }

    let provider_rows = sqlx::query(
        "SELECT device_id, kind
         FROM asset_providers
         WHERE sync_group_id = ? AND asset_id = ?",
    )
    .bind(&auth.sync_group_id)
    .bind(&asset_id)
    .fetch_all(&mut **tx)
    .await?;
    if provider_rows.is_empty() {
        return Err(AppError::Conflict(
            "payload_asset_update_provider_not_found",
        ));
    }
    let same_device = provider_rows
        .iter()
        .find(|row| row.get::<String, _>("device_id") == auth.device_id);
    let Some(provider_row) = same_device else {
        return Err(AppError::Conflict(
            "payload_asset_update_provider_wrong_device",
        ));
    };
    let provider_kind: String = provider_row.try_get("kind")?;
    if provider_kind != P2P_PROVIDER_KIND_IMAGE_PAYLOAD {
        return Err(AppError::Conflict(
            "payload_asset_update_provider_wrong_kind",
        ));
    }

    Ok(Some(PayloadAssetUpdate { asset_id }))
}

fn validate_payload_asset_update_payload(
    payload: &Map<String, Value>,
) -> Result<PayloadAssetUpdateShape, AppError> {
    PayloadAssetUpdateShape::parse_shape_strict(payload)
        .map_err(|error| AppError::BadRequest(error.code()))
}

async fn replace_thumbnail_link(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    auth: &DeviceAuth,
    content_hash: &str,
    digest: &str,
) -> Result<(), AppError> {
    clear_thumbnail_link(tx, auth, content_hash).await?;
    sqlx::query(
        "INSERT INTO sync_item_assets(sync_group_id, content_hash, asset_digest, role)
         VALUES (?, ?, ?, 'thumbnail')",
    )
    .bind(&auth.sync_group_id)
    .bind(content_hash)
    .bind(digest)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

async fn clear_thumbnail_link(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    auth: &DeviceAuth,
    content_hash: &str,
) -> Result<(), AppError> {
    sqlx::query(
        "DELETE FROM sync_item_assets
         WHERE sync_group_id = ? AND content_hash = ? AND role = 'thumbnail'",
    )
    .bind(&auth.sync_group_id)
    .bind(content_hash)
    .execute(&mut **tx)
    .await?;
    Ok(())
}
