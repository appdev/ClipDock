//! Native codecs stage bytes without opening SQLite or holding the root lock.
use super::{decode_json, ffi, json_response, with_core_without_maintenance};
use clipboard_core::{AssetReservation, AssetStore, CoreError, CoreErrorCode};

const MAX_PIXELS: u64 = 64 * 1024 * 1024;
const MAX_ENCODED_BYTES: usize = 256 * 1024 * 1024;
const MAX_WEBP_DIMENSION: u32 = 16_383;

pub(super) fn reserve_asset(
    app_support_dir: String,
    relative_path: String,
    staged_relative_path: String,
) -> ffi::CoreJSONResult {
    json_response((|| {
        Ok(AssetStore::open(app_support_dir)?.reserve(
            &relative_path,
            (!staged_relative_path.is_empty()).then_some(staged_relative_path.as_str()),
        )?)
    })())
}

pub(super) fn reserve_existing_asset(
    app_support_dir: String,
    relative_path: String,
) -> ffi::CoreJSONResult {
    json_response((|| {
        Ok(AssetStore::open(app_support_dir)?.reserve_existing(&relative_path)?)
    })())
}

pub(super) fn stage_reserved_asset(
    app_support_dir: String,
    reservation_json: String,
    bytes: &[u8],
) -> ffi::CoreJSONResult {
    json_response((|| {
        if bytes.is_empty() || bytes.len() > MAX_ENCODED_BYTES {
            return Err(invalid("encoded asset exceeds the byte budget"));
        }
        let reservation = decode_json::<AssetReservation>(&reservation_json)?;
        Ok(AssetStore::open(app_support_dir)?.stage_reserved(&reservation, bytes)?)
    })())
}

pub(super) fn publish_reserved_asset(
    app_support_dir: String,
    reservation_json: String,
) -> ffi::CoreJSONResult {
    json_response((|| {
        let reservation = decode_json::<AssetReservation>(&reservation_json)?;
        Ok(AssetStore::open(app_support_dir)?.publish(&reservation)?)
    })())
}

pub(super) fn encode_lossless_webp_to_staging(
    app_support_dir: String,
    reservation_json: String,
    rgba: &[u8],
    width: i64,
    height: i64,
    max_bytes: i64,
) -> ffi::CoreJSONResult {
    json_response((|| {
        let (width, height, max_bytes) =
            validate_encode_input(rgba.len(), width, height, max_bytes)?;
        let reservation = decode_json::<AssetReservation>(&reservation_json)?;
        let store = AssetStore::open(app_support_dir)?;
        // libwebp keeps the encoded allocation in Rust. No encoded Vec crosses
        // FFI and no root/SQLite guard spans encoding or the large staging write.
        let encoder = webp::Encoder::from_rgba(rgba, width, height);
        let encoded = encoder.encode_lossless();
        if encoded.is_empty() || encoded.len() > max_bytes {
            return Err(invalid("lossless image exceeds the encoded byte budget"));
        }
        Ok(store.stage_reserved(&reservation, &encoded)?)
    })())
}

fn validate_encode_input(
    byte_count: usize,
    width: i64,
    height: i64,
    max_bytes: i64,
) -> clipboard_core::Result<(u32, u32, usize)> {
    let width = u32::try_from(width).map_err(|_| invalid("invalid image width"))?;
    let height = u32::try_from(height).map_err(|_| invalid("invalid image height"))?;
    let pixels = u64::from(width) * u64::from(height);
    let expected = pixels
        .checked_mul(4)
        .and_then(|value| usize::try_from(value).ok());
    let max_bytes = usize::try_from(max_bytes).map_err(|_| invalid("invalid output budget"))?;
    if width == 0
        || height == 0
        || width > MAX_WEBP_DIMENSION
        || height > MAX_WEBP_DIMENSION
        || pixels > MAX_PIXELS
        || expected != Some(byte_count)
        || max_bytes == 0
        || max_bytes > MAX_ENCODED_BYTES
    {
        return Err(invalid("image exceeds the lossless encoding budget"));
    }
    Ok((width, height, max_bytes))
}

pub(super) fn cleanup_uncommitted_assets(
    app_support_dir: String,
    relative_paths_json: String,
) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<Vec<String>>(&relative_paths_json).and_then(|paths| {
            let mut entered_core = false;
            let result = with_core_without_maintenance(app_support_dir.clone(), |core| {
                entered_core = true;
                core.cleanup_uncommitted_assets(paths.clone())
            });
            if result.is_err() && !entered_core {
                // Storage could not open. Release only our claim, never remove a
                // file whose commit status is unknown. Maintenance checks it later.
                let _ = AssetStore::open(&app_support_dir)
                    .and_then(|store| store.abandon_owned_paths(&paths));
            }
            result
        }),
    )
}

fn invalid(message: &str) -> CoreError {
    CoreError::new(CoreErrorCode::InvalidInput, message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lossless_budget_rejects_overflow_dimensions_and_mismatched_input_before_encoding() {
        for (length, width, height, budget) in [
            (4, 0, 1, 100),
            (4, -1, 1, 100),
            (4, i64::MAX, i64::MAX, 100),
            (4, 1, 1, 0),
            (3, 1, 1, 100),
            (4, 16_384, 1, 100),
            (4, 1, 1, MAX_ENCODED_BYTES as i64 + 1),
        ] {
            assert!(validate_encode_input(length, width, height, budget).is_err());
        }
        assert_eq!(validate_encode_input(4, 1, 1, 100).unwrap(), (1, 1, 100));
    }

    #[test]
    fn direct_staging_returns_metadata_preserves_alpha_and_never_opens_a_session() {
        let root = tempfile::tempdir().unwrap();
        let root_string = root.path().to_str().unwrap().to_owned();
        let store = AssetStore::open(root.path()).unwrap();
        let reservation = store.reserve("assets/transparent.webp", None).unwrap();
        let before = super::super::sessions::session_access_count();
        let pixels = [0, 0, 0, 0, 23, 45, 67, 128, 90, 80, 70, 255];
        let result = encode_lossless_webp_to_staging(
            root_string.clone(),
            serde_json::to_string(&reservation).unwrap(),
            &pixels,
            3,
            1,
            1024,
        );
        assert!(result.ok, "{}", result.error_code);
        assert_eq!(super::super::sessions::session_access_count(), before);
        assert!(!root.path().join("assets/transparent.webp").exists());
        let staged: AssetReservation = serde_json::from_str(&result.result_json).unwrap();
        let bytes = std::fs::read(root.path().join(&staged.staged_relative_path)).unwrap();
        assert_eq!(staged.byte_count as usize, bytes.len());
        assert_eq!(
            staged.content_hash.as_deref(),
            Some(blake3::hash(&bytes).to_hex().as_str())
        );
        let decoded = webp::Decoder::new(&bytes).decode().unwrap();
        assert_eq!(&*decoded, &pixels);
        let rejected = encode_lossless_webp_to_staging(
            root_string,
            serde_json::to_string(&reservation).unwrap(),
            &pixels,
            3,
            1,
            1,
        );
        assert!(!rejected.ok);
        assert_eq!(
            std::fs::read(root.path().join(&staged.staged_relative_path)).unwrap(),
            bytes
        );
    }
}
