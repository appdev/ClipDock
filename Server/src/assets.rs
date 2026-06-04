use std::{path::PathBuf, sync::Arc};

use axum::{
    body::Body,
    http::{header, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
};
use bytes::Bytes;
use clipdock_sync_contract::{
    is_asset_kind, is_image_asset_mime_type, ASSET_KIND_LINK_PREVIEW, ASSET_KIND_SOURCE_ICON,
    ASSET_KIND_THUMBNAIL, MIME_IMAGE_JPEG, MIME_IMAGE_PNG, MIME_IMAGE_WEBP,
};
use image::ImageFormat;
use serde::Serialize;
use sqlx::{Row, SqlitePool};
use tokio::{io::AsyncWriteExt, sync::Semaphore};

use crate::{auth::DeviceAuth, db, errors::AppError, hashes::AssetDigest};

pub use clipdock_sync_contract::{
    ASSET_MAX_DIMENSION_PX, ASSET_MAX_PIXELS, DEFAULT_IMAGE_ASSET_MAX_BYTES,
    THUMBNAIL_DETAIL_TARGET_BYTES, THUMBNAIL_MAX_BYTES, THUMBNAIL_NORMAL_TARGET_BYTES,
};

#[derive(Clone, Debug)]
pub struct AssetStore {
    root: PathBuf,
    max_asset_bytes: usize,
    decode_semaphore: Arc<Semaphore>,
}

#[derive(Serialize)]
pub struct UploadAssetResponse {
    pub digest: String,
    pub kind: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub width_px: i64,
    pub height_px: i64,
    pub already_exists: bool,
}

impl AssetStore {
    pub async fn new(root: PathBuf, max_asset_bytes: usize) -> Result<Self, AppError> {
        tokio::fs::create_dir_all(root.join("objects")).await?;
        tokio::fs::create_dir_all(root.join("staging")).await?;
        let decode_parallelism = std::thread::available_parallelism()
            .map(|value| value.get())
            .unwrap_or(1)
            .clamp(1, 4);
        Ok(Self {
            root,
            max_asset_bytes,
            decode_semaphore: Arc::new(Semaphore::new(decode_parallelism)),
        })
    }

    pub fn max_bytes_for_kind(&self, kind: &str) -> usize {
        self.max_asset_bytes.min(default_max_bytes_for_kind(kind))
    }

    pub async fn upload(
        &self,
        pool: &SqlitePool,
        auth: DeviceAuth,
        digest: String,
        headers: &HeaderMap,
        bytes: Bytes,
    ) -> Result<UploadAssetResponse, AppError> {
        let parsed_digest =
            AssetDigest::parse(&digest).map_err(|_| AppError::BadRequest("invalid_digest"))?;
        let kind = required_header(headers, "x-clipdock-asset-kind")?;
        let mime_type =
            normalized_content_type(&required_header(headers, header::CONTENT_TYPE.as_str())?);
        if !is_asset_kind(&kind) {
            return Err(AppError::BadRequest("unsupported_asset_kind"));
        }
        if !is_image_asset_mime_type(&mime_type) {
            return Err(AppError::BadRequest("unsupported_mime_type"));
        }
        let width_px = required_u32_header(headers, "x-clipdock-asset-width")?;
        let height_px = required_u32_header(headers, "x-clipdock-asset-height")?;
        validate_dimensions(width_px, height_px)?;
        let max_bytes = self.max_bytes_for_kind(&kind);
        if bytes.len() > max_bytes {
            return Err(AppError::PayloadTooLarge("asset_too_large"));
        }

        let computed = AssetDigest::from_bytes(&bytes);
        if computed.as_str() != digest {
            return Err(AppError::BadRequest("bad_digest"));
        }
        if let Some(row) = sqlx::query(
            "SELECT kind, mime_type, size_bytes, width_px, height_px
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
            let existing_width: Option<i64> = row.try_get("width_px")?;
            let existing_height: Option<i64> = row.try_get("height_px")?;
            if existing_kind == kind
                && existing_mime == mime_type
                && existing_size == bytes.len() as i64
            {
                let decoded = self
                    .decode_image(&mime_type, bytes.clone(), width_px, height_px)
                    .await?;
                match (existing_width, existing_height) {
                    (Some(existing_width), Some(existing_height))
                        if existing_width == decoded.width as i64
                            && existing_height == decoded.height as i64 =>
                    {
                        return Ok(UploadAssetResponse {
                            digest,
                            kind,
                            mime_type,
                            size_bytes: existing_size,
                            width_px: existing_width,
                            height_px: existing_height,
                            already_exists: true,
                        });
                    }
                    (None, None) => {
                        sqlx::query(
                            "UPDATE sync_assets
                             SET width_px = ?, height_px = ?
                             WHERE sync_group_id = ? AND digest = ?",
                        )
                        .bind(decoded.width as i64)
                        .bind(decoded.height as i64)
                        .bind(&auth.sync_group_id)
                        .bind(&digest)
                        .execute(pool)
                        .await?;
                        return Ok(UploadAssetResponse {
                            digest,
                            kind,
                            mime_type,
                            size_bytes: existing_size,
                            width_px: decoded.width as i64,
                            height_px: decoded.height as i64,
                            already_exists: true,
                        });
                    }
                    _ => return Err(AppError::Conflict("metadata_conflict")),
                }
            }
            return Err(AppError::Conflict("metadata_conflict"));
        }

        let decoded = self
            .decode_image(&mime_type, bytes.clone(), width_px, height_px)
            .await?;
        let object_path = self.object_path(&auth.sync_group_id, &parsed_digest)?;
        if let Some(parent) = object_path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        let staging_path = self.root.join("staging").join(format!(
            "{}-{}-{}.tmp",
            auth.sync_group_id,
            parsed_digest.algorithm(),
            parsed_digest.hex()
        ));

        let mut file = tokio::fs::File::create(&staging_path).await?;
        file.write_all(&bytes).await?;
        file.sync_all().await?;
        drop(file);
        tokio::fs::rename(&staging_path, &object_path).await?;

        sqlx::query(
            "INSERT INTO sync_assets(
                sync_group_id, digest, kind, mime_type, size_bytes, path,
                created_by_device_id, created_at_ms, width_px, height_px
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&auth.sync_group_id)
        .bind(&digest)
        .bind(&kind)
        .bind(&mime_type)
        .bind(bytes.len() as i64)
        .bind(object_path.to_string_lossy().as_ref())
        .bind(&auth.device_id)
        .bind(db::now_ms().await)
        .bind(decoded.width as i64)
        .bind(decoded.height as i64)
        .execute(pool)
        .await?;

        Ok(UploadAssetResponse {
            digest,
            kind,
            mime_type,
            size_bytes: bytes.len() as i64,
            width_px: decoded.width as i64,
            height_px: decoded.height as i64,
            already_exists: false,
        })
    }

    async fn decode_image(
        &self,
        mime_type: &str,
        bytes: Bytes,
        width_px: u32,
        height_px: u32,
    ) -> Result<DecodedImageMetadata, AppError> {
        let expected_format = image_format_for_mime_type(mime_type)?;
        let _permit = self
            .decode_semaphore
            .clone()
            .acquire_owned()
            .await
            .map_err(|error| AppError::Internal(error.to_string()))?;
        let decoded =
            tokio::task::spawn_blocking(move || decode_image_metadata(&bytes, expected_format))
                .await
                .map_err(|error| AppError::Internal(error.to_string()))??;
        if decoded.width != width_px || decoded.height != height_px {
            return Err(AppError::BadRequest("asset_dimension_mismatch"));
        }
        Ok(decoded)
    }

    pub async fn download(
        &self,
        pool: &SqlitePool,
        auth: DeviceAuth,
        digest: String,
    ) -> Result<Response, AppError> {
        AssetDigest::parse(&digest).map_err(|_| AppError::BadRequest("invalid_digest"))?;
        let row = sqlx::query(
            "SELECT kind, mime_type, size_bytes, path, width_px, height_px
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
        let size_bytes: i64 = row.try_get("size_bytes")?;
        let path: String = row.try_get("path")?;
        let width_px: Option<i64> = row.try_get("width_px")?;
        let height_px: Option<i64> = row.try_get("height_px")?;
        let bytes = tokio::fs::read(path).await?;

        let mut builder = Response::builder()
            .status(StatusCode::OK)
            .header(header::CONTENT_TYPE, mime_type)
            .header(header::CONTENT_LENGTH, size_bytes.to_string())
            .header("x-clipdock-asset-kind", kind);
        if let (Some(width_px), Some(height_px)) = (width_px, height_px) {
            builder = builder
                .header("x-clipdock-asset-width", width_px.to_string())
                .header("x-clipdock-asset-height", height_px.to_string());
        }
        let response = builder
            .body(Body::from(bytes))
            .map_err(|error| AppError::Internal(error.to_string()))?;
        Ok(response)
    }

    fn object_path(&self, sync_group_id: &str, digest: &AssetDigest) -> Result<PathBuf, AppError> {
        Ok(self
            .root
            .join("objects")
            .join(sync_group_id)
            .join(digest.algorithm())
            .join(digest.hex()))
    }

    pub async fn delete_sync_group_objects(&self, sync_group_id: &str) -> Result<(), AppError> {
        let path = self.root.join("objects").join(sync_group_id);
        match tokio::fs::remove_dir_all(path).await {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }
}

impl IntoResponse for UploadAssetResponse {
    fn into_response(self) -> Response {
        (StatusCode::OK, crate::errors::ok(self)).into_response()
    }
}

pub fn validate_digest(value: &str) -> Result<(), AppError> {
    AssetDigest::parse(value)
        .map(|_| ())
        .map_err(|_| AppError::BadRequest("invalid_digest"))
}

fn required_header(headers: &HeaderMap, name: &str) -> Result<String, AppError> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .ok_or(AppError::BadRequest("missing_asset_metadata"))
}

fn required_u32_header(headers: &HeaderMap, name: &str) -> Result<u32, AppError> {
    let value = headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or(AppError::BadRequest("missing_asset_dimensions"))?;
    value
        .parse::<u32>()
        .map_err(|_| AppError::BadRequest("missing_asset_dimensions"))
}

fn normalized_content_type(value: &str) -> String {
    value
        .split(';')
        .next()
        .unwrap_or(value)
        .trim()
        .to_ascii_lowercase()
}

fn default_max_bytes_for_kind(kind: &str) -> usize {
    match kind {
        ASSET_KIND_THUMBNAIL => THUMBNAIL_MAX_BYTES,
        ASSET_KIND_SOURCE_ICON | ASSET_KIND_LINK_PREVIEW => DEFAULT_IMAGE_ASSET_MAX_BYTES,
        _ => DEFAULT_IMAGE_ASSET_MAX_BYTES,
    }
}

fn image_format_for_mime_type(mime_type: &str) -> Result<ImageFormat, AppError> {
    match mime_type {
        MIME_IMAGE_PNG => Ok(ImageFormat::Png),
        MIME_IMAGE_JPEG => Ok(ImageFormat::Jpeg),
        MIME_IMAGE_WEBP => Ok(ImageFormat::WebP),
        _ => Err(AppError::BadRequest("unsupported_mime_type")),
    }
}

fn validate_dimensions(width: u32, height: u32) -> Result<(), AppError> {
    if width == 0 || height == 0 {
        return Err(AppError::BadRequest("asset_dimension_mismatch"));
    }
    if width > ASSET_MAX_DIMENSION_PX || height > ASSET_MAX_DIMENSION_PX {
        return Err(AppError::BadRequest("asset_dimensions_too_large"));
    }
    let pixels = u64::from(width) * u64::from(height);
    if pixels > ASSET_MAX_PIXELS {
        return Err(AppError::BadRequest("asset_pixels_too_large"));
    }
    Ok(())
}

#[derive(Debug)]
struct DecodedImageMetadata {
    width: u32,
    height: u32,
}

fn decode_image_metadata(
    bytes: &[u8],
    expected_format: ImageFormat,
) -> Result<DecodedImageMetadata, AppError> {
    let guessed_format =
        image::guess_format(bytes).map_err(|_| AppError::BadRequest("asset_decode_failed"))?;
    if guessed_format != expected_format {
        return Err(AppError::BadRequest("asset_mime_mismatch"));
    }
    let image = image::load_from_memory_with_format(bytes, expected_format)
        .map_err(|_| AppError::BadRequest("asset_decode_failed"))?;
    let width = image.width();
    let height = image.height();
    validate_dimensions(width, height)?;
    Ok(DecodedImageMetadata { width, height })
}
