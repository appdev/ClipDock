use std::path::PathBuf;

use axum::{
    body::Body,
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use bytes::Bytes;
use serde::Serialize;
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};
use tokio::io::AsyncWriteExt;

use crate::{auth::DeviceAuth, db, errors::AppError, events::validate_content_hash};

const ALLOWED_KINDS: &[&str] = &["thumbnail", "source_icon", "link_preview"];
const ALLOWED_MIME_TYPES: &[&str] = &["image/png", "image/jpeg", "image/webp"];

#[derive(Clone, Debug)]
pub struct AssetStore {
    root: PathBuf,
    max_asset_bytes: usize,
}

#[derive(Serialize)]
pub struct UploadAssetResponse {
    pub digest: String,
    pub kind: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub already_exists: bool,
}

impl AssetStore {
    pub async fn new(root: PathBuf, max_asset_bytes: usize) -> Result<Self, AppError> {
        tokio::fs::create_dir_all(root.join("objects")).await?;
        tokio::fs::create_dir_all(root.join("staging")).await?;
        Ok(Self {
            root,
            max_asset_bytes,
        })
    }

    pub async fn upload(
        &self,
        pool: &SqlitePool,
        auth: DeviceAuth,
        digest: String,
        headers: &HeaderMap,
        bytes: Bytes,
    ) -> Result<UploadAssetResponse, AppError> {
        validate_digest(&digest)?;
        let kind = required_header(headers, "x-clipdock-asset-kind")?;
        let mime_type = required_header(headers, header::CONTENT_TYPE.as_str())?;
        if !ALLOWED_KINDS.contains(&kind.as_str()) {
            return Err(AppError::BadRequest("unsupported_asset_kind"));
        }
        if !ALLOWED_MIME_TYPES.contains(&mime_type.as_str()) {
            return Err(AppError::BadRequest("unsupported_mime_type"));
        }
        if bytes.len() > self.max_asset_bytes {
            return Err(AppError::PayloadTooLarge("asset_too_large"));
        }

        let computed = format!("sha256:{}", hex::encode(Sha256::digest(&bytes)));
        if computed != digest {
            return Err(AppError::BadRequest("bad_digest"));
        }

        if let Some(row) = sqlx::query(
            "SELECT kind, mime_type, size_bytes
             FROM sync_assets
             WHERE sync_group_id = ? AND digest = ?",
        )
        .bind(&auth.sync_group_id)
        .bind(&digest)
        .fetch_optional(pool)
        .await?
        {
            let existing_kind: String = row.try_get("kind")?;
            let existing_mime: String = row.try_get("mime_type")?;
            let existing_size: i64 = row.try_get("size_bytes")?;
            if existing_kind == kind
                && existing_mime == mime_type
                && existing_size == bytes.len() as i64
            {
                return Ok(UploadAssetResponse {
                    digest,
                    kind,
                    mime_type,
                    size_bytes: existing_size,
                    already_exists: true,
                });
            }
            return Err(AppError::Conflict("metadata_conflict"));
        }

        let object_path = self.object_path(&auth.sync_group_id, &digest)?;
        if let Some(parent) = object_path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        let staging_path = self.root.join("staging").join(format!(
            "{}-{}.tmp",
            auth.sync_group_id,
            digest.trim_start_matches("sha256:")
        ));

        let mut file = tokio::fs::File::create(&staging_path).await?;
        file.write_all(&bytes).await?;
        file.sync_all().await?;
        drop(file);
        tokio::fs::rename(&staging_path, &object_path).await?;

        sqlx::query(
            "INSERT INTO sync_assets(
                sync_group_id, digest, kind, mime_type, size_bytes, path, created_by_device_id, created_at_ms
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&auth.sync_group_id)
        .bind(&digest)
        .bind(&kind)
        .bind(&mime_type)
        .bind(bytes.len() as i64)
        .bind(object_path.to_string_lossy().as_ref())
        .bind(&auth.device_id)
        .bind(db::now_ms().await)
        .execute(pool)
        .await?;

        Ok(UploadAssetResponse {
            digest,
            kind,
            mime_type,
            size_bytes: bytes.len() as i64,
            already_exists: false,
        })
    }

    pub async fn download(
        &self,
        pool: &SqlitePool,
        auth: DeviceAuth,
        digest: String,
    ) -> Result<Response, AppError> {
        validate_digest(&digest)?;
        let row = sqlx::query(
            "SELECT kind, mime_type, path
             FROM sync_assets
             WHERE sync_group_id = ? AND digest = ?",
        )
        .bind(&auth.sync_group_id)
        .bind(&digest)
        .fetch_optional(pool)
        .await?
        .ok_or(AppError::BadRequest("asset_not_found"))?;

        let kind: String = row.try_get("kind")?;
        let mime_type: String = row.try_get("mime_type")?;
        let path: String = row.try_get("path")?;
        let bytes = tokio::fs::read(path).await?;

        let response = Response::builder()
            .status(StatusCode::OK)
            .header(header::CONTENT_TYPE, mime_type)
            .header("x-clipdock-asset-kind", kind)
            .body(Body::from(bytes))
            .map_err(|error| AppError::Internal(error.to_string()))?;
        Ok(response)
    }

    fn object_path(&self, sync_group_id: &str, digest: &str) -> Result<PathBuf, AppError> {
        validate_digest(digest)?;
        let hex = digest.trim_start_matches("sha256:");
        Ok(self.root.join("objects").join(sync_group_id).join(hex))
    }
}

impl IntoResponse for UploadAssetResponse {
    fn into_response(self) -> Response {
        (StatusCode::OK, crate::errors::ok(self)).into_response()
    }
}

pub fn validate_digest(value: &str) -> Result<(), AppError> {
    if validate_content_hash(value) {
        Ok(())
    } else {
        Err(AppError::BadRequest("invalid_digest"))
    }
}

fn required_header(headers: &HeaderMap, name: &str) -> Result<String, AppError> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or(AppError::BadRequest("missing_asset_metadata"))
}
