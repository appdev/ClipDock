use clipdock_sync_contract::{
    is_p2p_availability, is_p2p_provider_kind, P2pAssetId, AVAILABILITY_ONLINE, BLAKE3_PREFIX,
    P2P_PROVIDER_KINDS, SHA256_PREFIX,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};

use crate::{auth::DeviceAuth, db, errors::AppError};

pub const P2P_ENDPOINT_TTL_MS: i64 = 2 * 60 * 1000;
pub const P2P_PROVIDER_TTL_MS: i64 = 5 * 60 * 1000;

const MAX_TTL_MS: i64 = 30 * 60 * 1000;
const MAX_TEXT_BYTES: usize = 1024;
const MAX_JSON_BYTES: usize = 4096;
const MAX_DIRECT_ADDRESSES: usize = 16;

#[derive(Serialize)]
pub struct P2pCapabilities {
    pub enabled: bool,
    pub transport: &'static str,
    pub endpoint_ttl_ms: i64,
    pub provider_ttl_ms: i64,
    pub asset_id_prefixes: Vec<&'static str>,
    pub provider_kinds: Vec<&'static str>,
    pub quality_reports: bool,
}

#[derive(Deserialize)]
pub struct ReportEndpointRequest {
    pub endpoint_id: String,
    #[serde(default)]
    pub relay_url: Option<String>,
    #[serde(default)]
    pub direct_addresses: Vec<String>,
    #[serde(default)]
    pub capabilities: Option<Value>,
    #[serde(default)]
    pub quality: Option<Value>,
    #[serde(default)]
    pub ttl_ms: Option<i64>,
}

#[derive(Serialize)]
pub struct ReportEndpointResponse {
    pub device_id: String,
    pub endpoint: EndpointOut,
}

#[derive(Serialize)]
pub struct ListDevicesResponse {
    pub devices: Vec<DeviceEndpointOut>,
}

#[derive(Serialize)]
pub struct DeviceEndpointOut {
    pub device_id: String,
    pub device_name: String,
    pub endpoint: EndpointOut,
}

#[derive(Clone, Serialize)]
pub struct EndpointOut {
    pub endpoint_id: String,
    pub relay_url: Option<String>,
    pub direct_addresses: Vec<String>,
    pub capabilities: Value,
    pub quality: Value,
    pub updated_at_ms: i64,
    pub expires_at_ms: i64,
}

#[derive(Deserialize)]
pub struct UpsertAssetProviderRequest {
    pub kind: String,
    #[serde(default)]
    pub byte_count: Option<i64>,
    #[serde(default)]
    pub mime_type: Option<String>,
    #[serde(default)]
    pub availability: Option<String>,
    #[serde(default)]
    pub quality: Option<Value>,
    #[serde(default)]
    pub ttl_ms: Option<i64>,
}

#[derive(Serialize)]
pub struct UpsertAssetProviderResponse {
    pub asset_id: String,
    pub provider: AssetProviderOut,
}

#[derive(Serialize)]
pub struct DeleteAssetProviderResponse {
    pub asset_id: String,
    pub removed: bool,
}

#[derive(Serialize)]
pub struct ListAssetProvidersResponse {
    pub asset_id: String,
    pub providers: Vec<AssetProviderOut>,
}

#[derive(Serialize)]
pub struct AssetProviderOut {
    pub device_id: String,
    pub device_name: String,
    pub kind: String,
    pub byte_count: Option<i64>,
    pub mime_type: Option<String>,
    pub availability: String,
    pub quality: Value,
    pub updated_at_ms: i64,
    pub expires_at_ms: i64,
    pub endpoint: Option<EndpointOut>,
}

pub fn capabilities() -> P2pCapabilities {
    P2pCapabilities {
        enabled: true,
        transport: "iroh-blobs",
        endpoint_ttl_ms: P2P_ENDPOINT_TTL_MS,
        provider_ttl_ms: P2P_PROVIDER_TTL_MS,
        asset_id_prefixes: vec![SHA256_PREFIX, BLAKE3_PREFIX],
        provider_kinds: P2P_PROVIDER_KINDS.to_vec(),
        quality_reports: true,
    }
}

pub async fn report_endpoint(
    pool: &SqlitePool,
    auth: DeviceAuth,
    request: ReportEndpointRequest,
) -> Result<ReportEndpointResponse, AppError> {
    let endpoint_id = validate_text(request.endpoint_id, MAX_TEXT_BYTES, "invalid_endpoint_id")?;
    let relay_url = validate_optional_text(request.relay_url, MAX_TEXT_BYTES, "invalid_relay_url")?;
    let direct_addresses = validate_direct_addresses(request.direct_addresses)?;
    let capabilities = validate_json_object(request.capabilities, "invalid_capabilities")?;
    let quality = validate_json_object(request.quality, "invalid_quality")?;
    let ttl_ms = validate_ttl(request.ttl_ms, P2P_ENDPOINT_TTL_MS, "invalid_endpoint_ttl")?;
    let now = db::now_ms().await;
    let expires_at_ms = now + ttl_ms;
    let direct_addresses_json = serialize_json(&direct_addresses)?;
    let capabilities_json = serialize_json(&capabilities)?;
    let quality_json = serialize_json(&quality)?;

    sqlx::query(
        "INSERT INTO device_p2p_endpoints(
            sync_group_id, device_id, endpoint_id, relay_url, direct_addresses_json,
            capabilities_json, quality_json, updated_at_ms, expires_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sync_group_id, device_id) DO UPDATE SET
            endpoint_id = excluded.endpoint_id,
            relay_url = excluded.relay_url,
            direct_addresses_json = excluded.direct_addresses_json,
            capabilities_json = excluded.capabilities_json,
            quality_json = excluded.quality_json,
            updated_at_ms = excluded.updated_at_ms,
            expires_at_ms = excluded.expires_at_ms",
    )
    .bind(&auth.sync_group_id)
    .bind(&auth.device_id)
    .bind(&endpoint_id)
    .bind(&relay_url)
    .bind(&direct_addresses_json)
    .bind(&capabilities_json)
    .bind(&quality_json)
    .bind(now)
    .bind(expires_at_ms)
    .execute(pool)
    .await?;

    Ok(ReportEndpointResponse {
        device_id: auth.device_id,
        endpoint: EndpointOut {
            endpoint_id,
            relay_url,
            direct_addresses,
            capabilities,
            quality,
            updated_at_ms: now,
            expires_at_ms,
        },
    })
}

pub async fn list_devices(
    pool: &SqlitePool,
    auth: DeviceAuth,
) -> Result<ListDevicesResponse, AppError> {
    let now = db::now_ms().await;
    let rows = sqlx::query(
        "SELECT d.id AS device_id, d.name AS device_name, e.endpoint_id, e.relay_url,
                e.direct_addresses_json, e.capabilities_json, e.quality_json,
                e.updated_at_ms, e.expires_at_ms
         FROM device_p2p_endpoints e
         JOIN devices d ON d.id = e.device_id
         WHERE e.sync_group_id = ? AND e.expires_at_ms >= ? AND d.revoked_at_ms IS NULL
         ORDER BY e.updated_at_ms DESC",
    )
    .bind(&auth.sync_group_id)
    .bind(now)
    .fetch_all(pool)
    .await?;

    let mut devices = Vec::with_capacity(rows.len());
    for row in rows {
        devices.push(DeviceEndpointOut {
            device_id: row.try_get("device_id")?,
            device_name: row.try_get("device_name")?,
            endpoint: endpoint_from_row(&row)?,
        });
    }
    Ok(ListDevicesResponse { devices })
}

pub async fn upsert_asset_provider(
    pool: &SqlitePool,
    auth: DeviceAuth,
    asset_id: String,
    request: UpsertAssetProviderRequest,
) -> Result<UpsertAssetProviderResponse, AppError> {
    validate_asset_id(&asset_id)?;
    let kind = validate_provider_kind(request.kind)?;
    let byte_count = validate_byte_count(request.byte_count)?;
    let mime_type = validate_optional_text(request.mime_type, MAX_TEXT_BYTES, "invalid_mime_type")?;
    if let Some(mime_type) = &mime_type {
        if !mime_type.contains('/') {
            return Err(AppError::BadRequest("invalid_mime_type"));
        }
    }
    let availability = validate_availability(request.availability)?;
    let quality = validate_json_object(request.quality, "invalid_quality")?;
    let ttl_ms = validate_ttl(request.ttl_ms, P2P_PROVIDER_TTL_MS, "invalid_provider_ttl")?;
    let now = db::now_ms().await;
    let expires_at_ms = if availability == "offline" {
        now
    } else {
        now + ttl_ms
    };
    let quality_json = serialize_json(&quality)?;

    sqlx::query(
        "INSERT INTO asset_providers(
            sync_group_id, asset_id, device_id, kind, byte_count, mime_type, availability,
            quality_json, updated_at_ms, expires_at_ms
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(sync_group_id, asset_id, device_id) DO UPDATE SET
            kind = excluded.kind,
            byte_count = excluded.byte_count,
            mime_type = excluded.mime_type,
            availability = excluded.availability,
            quality_json = excluded.quality_json,
            updated_at_ms = excluded.updated_at_ms,
            expires_at_ms = excluded.expires_at_ms",
    )
    .bind(&auth.sync_group_id)
    .bind(&asset_id)
    .bind(&auth.device_id)
    .bind(&kind)
    .bind(byte_count)
    .bind(&mime_type)
    .bind(&availability)
    .bind(&quality_json)
    .bind(now)
    .bind(expires_at_ms)
    .execute(pool)
    .await?;

    let provider = get_provider_for_device(pool, &auth.sync_group_id, &asset_id, &auth.device_id)
        .await?
        .ok_or(AppError::Internal(
            "stored provider was not readable".to_string(),
        ))?;
    Ok(UpsertAssetProviderResponse { asset_id, provider })
}

pub async fn delete_asset_provider(
    pool: &SqlitePool,
    auth: DeviceAuth,
    asset_id: String,
) -> Result<DeleteAssetProviderResponse, AppError> {
    validate_asset_id(&asset_id)?;
    let now = db::now_ms().await;
    let result = sqlx::query(
        "UPDATE asset_providers
         SET availability = 'offline', updated_at_ms = ?, expires_at_ms = ?
         WHERE sync_group_id = ? AND asset_id = ? AND device_id = ?",
    )
    .bind(now)
    .bind(now)
    .bind(&auth.sync_group_id)
    .bind(&asset_id)
    .bind(&auth.device_id)
    .execute(pool)
    .await?;
    Ok(DeleteAssetProviderResponse {
        asset_id,
        removed: result.rows_affected() > 0,
    })
}

pub async fn list_asset_providers(
    pool: &SqlitePool,
    auth: DeviceAuth,
    asset_id: String,
) -> Result<ListAssetProvidersResponse, AppError> {
    validate_asset_id(&asset_id)?;
    let now = db::now_ms().await;
    let rows = sqlx::query(
        "SELECT p.device_id, d.name AS device_name, p.kind, p.byte_count, p.mime_type,
                p.availability, p.quality_json, p.updated_at_ms, p.expires_at_ms,
                e.endpoint_id, e.relay_url, e.direct_addresses_json,
                e.capabilities_json, e.quality_json AS endpoint_quality_json,
                e.updated_at_ms AS endpoint_updated_at_ms,
                e.expires_at_ms AS endpoint_expires_at_ms
         FROM asset_providers p
         JOIN devices d ON d.id = p.device_id
         LEFT JOIN device_p2p_endpoints e
            ON e.sync_group_id = p.sync_group_id
           AND e.device_id = p.device_id
           AND e.expires_at_ms >= ?
         WHERE p.sync_group_id = ?
           AND p.asset_id = ?
           AND p.availability != 'offline'
           AND p.expires_at_ms >= ?
           AND d.revoked_at_ms IS NULL
         ORDER BY p.updated_at_ms DESC",
    )
    .bind(now)
    .bind(&auth.sync_group_id)
    .bind(&asset_id)
    .bind(now)
    .fetch_all(pool)
    .await?;

    let mut providers = Vec::with_capacity(rows.len());
    for row in rows {
        providers.push(provider_from_row(&row)?);
    }
    Ok(ListAssetProvidersResponse {
        asset_id,
        providers,
    })
}

fn validate_asset_id(value: &str) -> Result<(), AppError> {
    P2pAssetId::parse_strict(value)
        .map(|_| ())
        .map_err(|error| AppError::BadRequest(error.code()))
}

fn validate_provider_kind(value: String) -> Result<String, AppError> {
    let value = value.trim().to_string();
    if is_p2p_provider_kind(&value) {
        Ok(value)
    } else {
        Err(AppError::BadRequest("unsupported_provider_kind"))
    }
}

fn validate_availability(value: Option<String>) -> Result<String, AppError> {
    let value = value.unwrap_or_else(|| AVAILABILITY_ONLINE.to_string());
    let value = value.trim().to_string();
    if is_p2p_availability(&value) {
        Ok(value)
    } else {
        Err(AppError::BadRequest("invalid_availability"))
    }
}

fn validate_byte_count(value: Option<i64>) -> Result<Option<i64>, AppError> {
    if matches!(value, Some(count) if count < 0) {
        Err(AppError::BadRequest("invalid_byte_count"))
    } else {
        Ok(value)
    }
}

fn validate_ttl(
    value: Option<i64>,
    default_ttl_ms: i64,
    error_code: &'static str,
) -> Result<i64, AppError> {
    let value = value.unwrap_or(default_ttl_ms);
    if value <= 0 || value > MAX_TTL_MS {
        return Err(AppError::BadRequest(error_code));
    }
    Ok(value)
}

fn validate_text(
    value: String,
    max_bytes: usize,
    error_code: &'static str,
) -> Result<String, AppError> {
    let value = value.trim().to_string();
    if value.is_empty()
        || value.len() > max_bytes
        || value.chars().any(|character| character.is_control())
    {
        return Err(AppError::BadRequest(error_code));
    }
    Ok(value)
}

fn validate_optional_text(
    value: Option<String>,
    max_bytes: usize,
    error_code: &'static str,
) -> Result<Option<String>, AppError> {
    value
        .map(|value| validate_text(value, max_bytes, error_code))
        .transpose()
}

fn validate_direct_addresses(values: Vec<String>) -> Result<Vec<String>, AppError> {
    if values.len() > MAX_DIRECT_ADDRESSES {
        return Err(AppError::BadRequest("invalid_direct_addresses"));
    }
    values
        .into_iter()
        .map(|value| validate_text(value, MAX_TEXT_BYTES, "invalid_direct_addresses"))
        .collect()
}

fn validate_json_object(value: Option<Value>, error_code: &'static str) -> Result<Value, AppError> {
    let value = match value {
        Some(Value::Null) | None => json!({}),
        Some(value) => value,
    };
    if !value.is_object() {
        return Err(AppError::BadRequest(error_code));
    }
    let serialized = serialize_json(&value)?;
    if serialized.len() > MAX_JSON_BYTES {
        return Err(AppError::BadRequest(error_code));
    }
    Ok(value)
}

fn serialize_json<T: Serialize>(value: &T) -> Result<String, AppError> {
    serde_json::to_string(value).map_err(|error| AppError::Internal(error.to_string()))
}

fn parse_json<T: DeserializeOwned>(value: &str) -> Result<T, AppError> {
    serde_json::from_str(value).map_err(|error| AppError::Internal(error.to_string()))
}

async fn get_provider_for_device(
    pool: &SqlitePool,
    sync_group_id: &str,
    asset_id: &str,
    device_id: &str,
) -> Result<Option<AssetProviderOut>, AppError> {
    let now = db::now_ms().await;
    let row = sqlx::query(
        "SELECT p.device_id, d.name AS device_name, p.kind, p.byte_count, p.mime_type,
                p.availability, p.quality_json, p.updated_at_ms, p.expires_at_ms,
                e.endpoint_id, e.relay_url, e.direct_addresses_json,
                e.capabilities_json, e.quality_json AS endpoint_quality_json,
                e.updated_at_ms AS endpoint_updated_at_ms,
                e.expires_at_ms AS endpoint_expires_at_ms
         FROM asset_providers p
         JOIN devices d ON d.id = p.device_id
         LEFT JOIN device_p2p_endpoints e
            ON e.sync_group_id = p.sync_group_id
           AND e.device_id = p.device_id
           AND e.expires_at_ms >= ?
         WHERE p.sync_group_id = ? AND p.asset_id = ? AND p.device_id = ?
           AND d.revoked_at_ms IS NULL",
    )
    .bind(now)
    .bind(sync_group_id)
    .bind(asset_id)
    .bind(device_id)
    .fetch_optional(pool)
    .await?;
    row.map(|row| provider_from_row(&row)).transpose()
}

fn endpoint_from_row(row: &sqlx::sqlite::SqliteRow) -> Result<EndpointOut, AppError> {
    let direct_addresses_json: String = row.try_get("direct_addresses_json")?;
    let capabilities_json: String = row.try_get("capabilities_json")?;
    let quality_json: String = row.try_get("quality_json")?;
    Ok(EndpointOut {
        endpoint_id: row.try_get("endpoint_id")?,
        relay_url: row.try_get("relay_url")?,
        direct_addresses: parse_json(&direct_addresses_json)?,
        capabilities: parse_json(&capabilities_json)?,
        quality: parse_json(&quality_json)?,
        updated_at_ms: row.try_get("updated_at_ms")?,
        expires_at_ms: row.try_get("expires_at_ms")?,
    })
}

fn optional_endpoint_from_provider_row(
    row: &sqlx::sqlite::SqliteRow,
) -> Result<Option<EndpointOut>, AppError> {
    let Some(endpoint_id) = row.try_get::<Option<String>, _>("endpoint_id")? else {
        return Ok(None);
    };
    let direct_addresses_json: String = row.try_get("direct_addresses_json")?;
    let capabilities_json: String = row.try_get("capabilities_json")?;
    let quality_json: String = row.try_get("endpoint_quality_json")?;
    Ok(Some(EndpointOut {
        endpoint_id,
        relay_url: row.try_get("relay_url")?,
        direct_addresses: parse_json(&direct_addresses_json)?,
        capabilities: parse_json(&capabilities_json)?,
        quality: parse_json(&quality_json)?,
        updated_at_ms: row.try_get("endpoint_updated_at_ms")?,
        expires_at_ms: row.try_get("endpoint_expires_at_ms")?,
    }))
}

fn provider_from_row(row: &sqlx::sqlite::SqliteRow) -> Result<AssetProviderOut, AppError> {
    let endpoint = optional_endpoint_from_provider_row(row)?;
    let mut availability: String = row.try_get("availability")?;
    if endpoint.is_none() && availability == "online" {
        availability = "last_seen".to_string();
    }
    let quality_json: String = row.try_get("quality_json")?;
    Ok(AssetProviderOut {
        device_id: row.try_get("device_id")?,
        device_name: row.try_get("device_name")?,
        kind: row.try_get("kind")?,
        byte_count: row.try_get("byte_count")?,
        mime_type: row.try_get("mime_type")?,
        availability,
        quality: parse_json(&quality_json)?,
        updated_at_ms: row.try_get("updated_at_ms")?,
        expires_at_ms: row.try_get("expires_at_ms")?,
        endpoint,
    })
}
