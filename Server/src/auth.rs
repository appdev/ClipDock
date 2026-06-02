use axum::http::HeaderMap;
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use rand::{Rng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};

use crate::{db, errors::AppError};

const PAIRING_CODE_ALPHABET: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
const PAIRING_CODE_LENGTH: usize = 5;
const PAIRING_CODE_TTL_MS: i64 = 10 * 60 * 1000;
const MAX_PAIRING_CODE_ATTEMPTS: usize = 32;

#[derive(Clone, Debug)]
pub struct DeviceAuth {
    pub device_id: String,
    pub device_name: String,
    pub sync_group_id: String,
}

#[derive(Deserialize)]
pub struct CreateSyncRequest {
    pub device_name: String,
}

#[derive(Serialize)]
pub struct CreateSyncResponse {
    pub sync_id: String,
    pub pairing_code: String,
    pub pairing_expires_at_ms: i64,
    pub device_id: String,
    pub token: String,
}

#[derive(Deserialize)]
pub struct JoinSyncRequest {
    pub pairing_code: String,
    pub device_name: String,
}

#[derive(Serialize)]
pub struct JoinSyncResponse {
    pub sync_id: String,
    pub device_id: String,
    pub token: String,
}

#[derive(Serialize)]
pub struct CreateInviteResponse {
    pub sync_id: String,
    pub pairing_code: String,
    pub pairing_expires_at_ms: i64,
}

pub fn hash_token(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

pub fn generate_device_token() -> String {
    let mut bytes = [0_u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    format!("cds_{}", URL_SAFE_NO_PAD.encode(bytes))
}

pub fn generate_id(prefix: &str) -> String {
    let mut bytes = [0_u8; 18];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    format!("{prefix}{}", URL_SAFE_NO_PAD.encode(bytes))
}

pub fn generate_pairing_code() -> String {
    let mut rng = rand::rngs::OsRng;
    (0..PAIRING_CODE_LENGTH)
        .map(|_| {
            let index = rng.gen_range(0..PAIRING_CODE_ALPHABET.len());
            PAIRING_CODE_ALPHABET[index] as char
        })
        .collect()
}

pub fn normalize_pairing_code(value: &str) -> Result<String, AppError> {
    let normalized = value.trim().to_ascii_uppercase();
    if normalized.len() != PAIRING_CODE_LENGTH
        || !normalized.bytes().all(|byte| byte.is_ascii_alphanumeric())
    {
        return Err(AppError::BadRequest("invalid_pairing_code"));
    }
    Ok(normalized)
}

pub fn hash_pairing_code(code: &str) -> String {
    hex::encode(Sha256::digest(code.as_bytes()))
}

pub fn constant_time_eq(left: &str, right: &str) -> bool {
    if left.len() != right.len() {
        return false;
    }
    left.as_bytes()
        .iter()
        .zip(right.as_bytes())
        .fold(0_u8, |diff, (a, b)| diff | (a ^ b))
        == 0
}

struct NewDevice {
    id: String,
    token: String,
    token_hash: String,
}

fn validate_device_name(name: &str) -> Result<String, AppError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(AppError::BadRequest("invalid_device_name"));
    }
    Ok(name.to_string())
}

fn new_device() -> NewDevice {
    let token = generate_device_token();
    let token_hash = hash_token(&token);
    let device_id = format!("dev_{}", &token_hash[..24]);
    NewDevice {
        id: device_id,
        token,
        token_hash,
    }
}

pub async fn create_sync(
    pool: &SqlitePool,
    request: CreateSyncRequest,
) -> Result<CreateSyncResponse, AppError> {
    let device_name = validate_device_name(&request.device_name)?;
    let sync_id = generate_id("sync_");
    let device = new_device();
    let now = db::now_ms().await;

    let mut tx = pool.begin().await?;
    sqlx::query("INSERT INTO sync_groups(id, created_at_ms) VALUES (?, ?)")
        .bind(&sync_id)
        .bind(now)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "INSERT INTO devices(id, sync_group_id, name, token_hash, created_at_ms)
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&device.id)
    .bind(&sync_id)
    .bind(device_name)
    .bind(&device.token_hash)
    .bind(now)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    let invite = create_invite_for_group(pool, &sync_id, &device.id).await?;
    Ok(CreateSyncResponse {
        sync_id,
        pairing_code: invite.pairing_code,
        pairing_expires_at_ms: invite.pairing_expires_at_ms,
        device_id: device.id,
        token: device.token,
    })
}

pub async fn join_sync(
    pool: &SqlitePool,
    request: JoinSyncRequest,
) -> Result<JoinSyncResponse, AppError> {
    let code = normalize_pairing_code(&request.pairing_code)?;
    let code_hash = hash_pairing_code(&code);
    let device_name = validate_device_name(&request.device_name)?;
    let device = new_device();
    let now = db::now_ms().await;

    let mut tx = pool.begin().await?;
    let row = sqlx::query(
        "SELECT sync_group_id
         FROM pairing_codes
         WHERE code_hash = ? AND consumed_at_ms IS NULL AND expires_at_ms >= ?",
    )
    .bind(&code_hash)
    .bind(now)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::Forbidden("invalid_pairing_code"))?;
    let sync_id: String = row.try_get("sync_group_id")?;

    sqlx::query(
        "INSERT INTO devices(id, sync_group_id, name, token_hash, created_at_ms)
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&device.id)
    .bind(&sync_id)
    .bind(device_name)
    .bind(&device.token_hash)
    .bind(now)
    .execute(&mut *tx)
    .await?;

    let consumed = sqlx::query(
        "UPDATE pairing_codes
         SET consumed_at_ms = ?, consumed_by_device_id = ?
         WHERE code_hash = ? AND consumed_at_ms IS NULL AND expires_at_ms >= ?",
    )
    .bind(now)
    .bind(&device.id)
    .bind(&code_hash)
    .bind(now)
    .execute(&mut *tx)
    .await?;
    if consumed.rows_affected() == 0 {
        return Err(AppError::Forbidden("invalid_pairing_code"));
    }
    tx.commit().await?;

    Ok(JoinSyncResponse {
        sync_id,
        device_id: device.id,
        token: device.token,
    })
}

pub async fn create_invite(
    pool: &SqlitePool,
    auth: &DeviceAuth,
) -> Result<CreateInviteResponse, AppError> {
    create_invite_for_group(pool, &auth.sync_group_id, &auth.device_id).await
}

async fn create_invite_for_group(
    pool: &SqlitePool,
    sync_group_id: &str,
    created_by_device_id: &str,
) -> Result<CreateInviteResponse, AppError> {
    let now = db::now_ms().await;
    let expires_at_ms = now + PAIRING_CODE_TTL_MS;
    for _ in 0..MAX_PAIRING_CODE_ATTEMPTS {
        let pairing_code = generate_pairing_code();
        let code_hash = hash_pairing_code(&pairing_code);
        let inserted = sqlx::query(
            "INSERT OR IGNORE INTO pairing_codes(
                code_hash, sync_group_id, created_by_device_id, created_at_ms, expires_at_ms
            ) VALUES (?, ?, ?, ?, ?)",
        )
        .bind(code_hash)
        .bind(sync_group_id)
        .bind(created_by_device_id)
        .bind(now)
        .bind(expires_at_ms)
        .execute(pool)
        .await?;
        if inserted.rows_affected() == 1 {
            return Ok(CreateInviteResponse {
                sync_id: sync_group_id.to_string(),
                pairing_code,
                pairing_expires_at_ms: expires_at_ms,
            });
        }
    }

    Err(AppError::Internal(
        "could not allocate pairing code".to_string(),
    ))
}

pub async fn require_device(
    pool: &SqlitePool,
    headers: &HeaderMap,
) -> Result<DeviceAuth, AppError> {
    let auth = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .ok_or(AppError::Unauthorized("unauthorized"))?;
    let token = auth
        .strip_prefix("Bearer ")
        .ok_or(AppError::Unauthorized("unauthorized"))?;
    if !token.starts_with("cds_") {
        return Err(AppError::Unauthorized("unauthorized"));
    }
    let token_hash = hash_token(token);
    let row = sqlx::query(
        "SELECT id, sync_group_id, name, revoked_at_ms FROM devices WHERE token_hash = ?",
    )
    .bind(token_hash)
    .fetch_optional(pool)
    .await?;
    let Some(row) = row else {
        return Err(AppError::Unauthorized("unauthorized"));
    };
    let revoked_at_ms: Option<i64> = row.try_get("revoked_at_ms")?;
    if revoked_at_ms.is_some() {
        return Err(AppError::Forbidden("revoked_device"));
    }
    Ok(DeviceAuth {
        device_id: row.try_get("id")?,
        device_name: row.try_get("name")?,
        sync_group_id: row.try_get("sync_group_id")?,
    })
}
