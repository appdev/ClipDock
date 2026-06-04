use std::{error::Error, fmt};

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

pub const PROTOCOL_VERSION: u8 = 2;
pub const PROTOCOL_V1_RETIRED_ERROR: &str = "protocol_v1_retired";

pub const CONTENT_HASH_ALGORITHM_BLAKE3: &str = "blake3";
pub const ASSET_DIGEST_ALGORITHM_BLAKE3: &str = "blake3";
pub const BLAKE3_PREFIX: &str = "blake3:";
pub const SHA256_PREFIX: &str = "sha256:";
pub const HEX_HASH_LEN: usize = 64;
pub const IROH_BLAKE3_BASE32_LEN: usize = 52;

pub const EVENT_TYPE_ITEM_UPSERT: &str = "item_upsert";
pub const EVENT_TYPE_ITEM_DELETE: &str = "item_delete";
pub const EVENT_TYPE_ITEM_PAYLOAD_ASSET_UPDATE: &str = "item_payload_asset_update";
pub const EVENT_TYPES: &[&str] = &[
    EVENT_TYPE_ITEM_UPSERT,
    EVENT_TYPE_ITEM_DELETE,
    EVENT_TYPE_ITEM_PAYLOAD_ASSET_UPDATE,
];

pub const ITEM_TYPE_IMAGE: &str = "image";

pub const ASSET_KIND_THUMBNAIL: &str = "thumbnail";
pub const ASSET_KIND_SOURCE_ICON: &str = "source_icon";
pub const ASSET_KIND_LINK_PREVIEW: &str = "link_preview";
pub const ASSET_KINDS: &[&str] = &[
    ASSET_KIND_THUMBNAIL,
    ASSET_KIND_SOURCE_ICON,
    ASSET_KIND_LINK_PREVIEW,
];

pub const P2P_PROVIDER_KIND_IMAGE_PAYLOAD: &str = "image_payload";
pub const P2P_PROVIDER_KIND_FILE_PAYLOAD: &str = "file_payload";
pub const P2P_PROVIDER_KIND_THUMBNAIL: &str = "thumbnail";
pub const P2P_PROVIDER_KINDS: &[&str] = &[
    P2P_PROVIDER_KIND_IMAGE_PAYLOAD,
    P2P_PROVIDER_KIND_FILE_PAYLOAD,
    P2P_PROVIDER_KIND_THUMBNAIL,
];

pub const AVAILABILITY_ONLINE: &str = "online";
pub const AVAILABILITY_LAST_SEEN: &str = "last_seen";
pub const AVAILABILITY_OFFLINE: &str = "offline";
pub const P2P_AVAILABILITY_VALUES: &[&str] = &[
    AVAILABILITY_ONLINE,
    AVAILABILITY_LAST_SEEN,
    AVAILABILITY_OFFLINE,
];

pub const MIME_IMAGE_PNG: &str = "image/png";
pub const MIME_IMAGE_JPEG: &str = "image/jpeg";
pub const MIME_IMAGE_WEBP: &str = "image/webp";
pub const IMAGE_ASSET_MIME_TYPES: &[&str] = &[MIME_IMAGE_PNG, MIME_IMAGE_JPEG, MIME_IMAGE_WEBP];
pub const SYNC_THUMBNAIL_MIME_TYPE: &str = MIME_IMAGE_WEBP;

pub const THUMBNAIL_DIGEST_FIELD: &str = "thumbnail_digest";
pub const THUMBNAIL_MIME_TYPE_FIELD: &str = "thumbnail_mime_type";
pub const THUMBNAIL_BYTE_COUNT_FIELD: &str = "thumbnail_byte_count";
pub const THUMBNAIL_WIDTH_FIELD: &str = "thumbnail_width";
pub const THUMBNAIL_HEIGHT_FIELD: &str = "thumbnail_height";
pub const THUMBNAIL_FIELDS: &[&str] = &[
    THUMBNAIL_DIGEST_FIELD,
    THUMBNAIL_MIME_TYPE_FIELD,
    THUMBNAIL_BYTE_COUNT_FIELD,
    THUMBNAIL_WIDTH_FIELD,
    THUMBNAIL_HEIGHT_FIELD,
];

pub const PAYLOAD_ASSET_ID_FIELD: &str = "payload_asset_id";
pub const ASSET_ID_FIELD: &str = "asset_id";

pub const THUMBNAIL_NORMAL_TARGET_BYTES: usize = 262_144;
pub const THUMBNAIL_DETAIL_TARGET_BYTES: usize = 393_216;
pub const THUMBNAIL_MAX_BYTES: usize = 786_432;
pub const DEFAULT_IMAGE_ASSET_MAX_BYTES: usize = 2 * 1024 * 1024;
pub const ASSET_MAX_DIMENSION_PX: u32 = 8_192;
pub const ASSET_MAX_PIXELS: u64 = 16_777_216;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ThumbnailPolicy {
    pub normal_target_bytes: usize,
    pub detail_target_bytes: usize,
    pub max_bytes: usize,
}

pub const THUMBNAIL_POLICY: ThumbnailPolicy = ThumbnailPolicy {
    normal_target_bytes: THUMBNAIL_NORMAL_TARGET_BYTES,
    detail_target_bytes: THUMBNAIL_DETAIL_TARGET_BYTES,
    max_bytes: THUMBNAIL_MAX_BYTES,
};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContractError {
    code: &'static str,
}

impl ContractError {
    pub const fn new(code: &'static str) -> Self {
        Self { code }
    }

    pub const fn code(&self) -> &'static str {
        self.code
    }
}

impl fmt::Display for ContractError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.code)
    }
}

impl Error for ContractError {}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ContentHash {
    value: String,
}

impl ContentHash {
    pub fn parse_strict(value: &str) -> Result<Self, ContractError> {
        let hex = parse_prefixed_lower_hex(value, BLAKE3_PREFIX, "invalid_content_hash")?;
        Ok(Self {
            value: format!("{BLAKE3_PREFIX}{hex}"),
        })
    }

    pub fn normalize_client(value: &str) -> Result<Self, ContractError> {
        let trimmed = value.trim().to_ascii_lowercase();
        if let Some(hex) = trimmed.strip_prefix(BLAKE3_PREFIX) {
            return parse_lower_hex(hex, HEX_HASH_LEN, "invalid_content_hash").map(|_| Self {
                value: format!("{BLAKE3_PREFIX}{hex}"),
            });
        }
        parse_lower_hex(&trimmed, HEX_HASH_LEN, "invalid_content_hash").map(|_| Self {
            value: format!("{BLAKE3_PREFIX}{trimmed}"),
        })
    }

    pub fn from_utf8_bytes(bytes: &[u8]) -> Self {
        let hex = blake3::hash(bytes).to_hex().to_string();
        Self {
            value: format!("{BLAKE3_PREFIX}{hex}"),
        }
    }

    pub fn as_str(&self) -> &str {
        &self.value
    }

    pub fn local_key(&self) -> &str {
        self.value
            .strip_prefix(BLAKE3_PREFIX)
            .expect("ContentHash always stores the blake3 prefix")
    }
}

impl fmt::Display for ContentHash {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.value)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AssetDigest {
    value: String,
    hex: String,
}

impl AssetDigest {
    pub fn parse_strict(value: &str) -> Result<Self, ContractError> {
        let hex = parse_prefixed_lower_hex(value, BLAKE3_PREFIX, "invalid_digest")?;
        Ok(Self {
            value: format!("{BLAKE3_PREFIX}{hex}"),
            hex: hex.to_string(),
        })
    }

    pub fn from_bytes(bytes: &[u8]) -> Self {
        let hex = blake3::hash(bytes).to_hex().to_string();
        Self {
            value: format!("{BLAKE3_PREFIX}{hex}"),
            hex,
        }
    }

    pub fn algorithm(&self) -> &'static str {
        ASSET_DIGEST_ALGORITHM_BLAKE3
    }

    pub fn hex(&self) -> &str {
        &self.hex
    }

    pub fn as_str(&self) -> &str {
        &self.value
    }
}

impl fmt::Display for AssetDigest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.value)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct P2pAssetId {
    value: String,
}

impl P2pAssetId {
    pub fn parse_strict(value: &str) -> Result<Self, ContractError> {
        if let Some(hex) = value.strip_prefix(SHA256_PREFIX) {
            parse_lower_hex(hex, HEX_HASH_LEN, "invalid_asset_id")?;
            return Ok(Self {
                value: value.to_string(),
            });
        }
        if let Some(hash) = value.strip_prefix(BLAKE3_PREFIX) {
            if is_lower_hex(hash, HEX_HASH_LEN) || is_iroh_base32_hash(hash) {
                return Ok(Self {
                    value: value.to_string(),
                });
            }
        }
        Err(ContractError::new("invalid_asset_id"))
    }

    pub fn as_str(&self) -> &str {
        &self.value
    }
}

impl fmt::Display for P2pAssetId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.value)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ThumbnailMetadata {
    pub digest: String,
    pub mime_type: String,
    pub byte_count: i64,
    pub width: i64,
    pub height: i64,
}

impl ThumbnailMetadata {
    pub fn parse_shape_strict(
        item_type: Option<&str>,
        payload: &Map<String, Value>,
    ) -> Result<Option<Self>, ContractError> {
        let present_count = THUMBNAIL_FIELDS
            .iter()
            .filter(|field| payload.contains_key(**field))
            .count();
        if present_count == 0 {
            return Ok(None);
        }
        if item_type != Some(ITEM_TYPE_IMAGE) || present_count != THUMBNAIL_FIELDS.len() {
            return Err(ContractError::new("invalid_thumbnail_payload"));
        }

        let digest = required_string(payload, THUMBNAIL_DIGEST_FIELD, "invalid_thumbnail_payload")?;
        AssetDigest::parse_strict(digest)
            .map_err(|_| ContractError::new("invalid_thumbnail_payload"))?;
        let mime_type = required_string(
            payload,
            THUMBNAIL_MIME_TYPE_FIELD,
            "invalid_thumbnail_payload",
        )?;
        let byte_count = required_positive_i64(
            payload,
            THUMBNAIL_BYTE_COUNT_FIELD,
            "invalid_thumbnail_payload",
        )?;
        let width =
            required_positive_i64(payload, THUMBNAIL_WIDTH_FIELD, "invalid_thumbnail_payload")?;
        let height =
            required_positive_i64(payload, THUMBNAIL_HEIGHT_FIELD, "invalid_thumbnail_payload")?;
        Ok(Some(Self {
            digest: digest.to_string(),
            mime_type: mime_type.to_string(),
            byte_count,
            width,
            height,
        }))
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PayloadAssetUpdate {
    pub asset_id: String,
}

impl PayloadAssetUpdate {
    pub fn parse_shape_strict(payload: &Map<String, Value>) -> Result<Self, ContractError> {
        if payload
            .keys()
            .any(|key| key != PAYLOAD_ASSET_ID_FIELD && key != ASSET_ID_FIELD)
        {
            return Err(ContractError::new("invalid_payload_asset_update_payload"));
        }
        let asset_id = required_string(
            payload,
            PAYLOAD_ASSET_ID_FIELD,
            "invalid_payload_asset_update_payload",
        )?;
        P2pAssetId::parse_strict(asset_id)
            .map_err(|_| ContractError::new("invalid_payload_asset_update_payload"))?;
        if let Some(alias) = payload.get(ASSET_ID_FIELD) {
            let alias = alias
                .as_str()
                .filter(|value| !value.trim().is_empty())
                .ok_or(ContractError::new("invalid_payload_asset_update_payload"))?;
            if alias != asset_id {
                return Err(ContractError::new("invalid_payload_asset_update_payload"));
            }
        }
        Ok(Self {
            asset_id: asset_id.to_string(),
        })
    }
}

pub fn is_asset_kind(value: &str) -> bool {
    ASSET_KINDS.contains(&value)
}

pub fn is_image_asset_mime_type(value: &str) -> bool {
    IMAGE_ASSET_MIME_TYPES.contains(&value)
}

pub fn is_p2p_provider_kind(value: &str) -> bool {
    P2P_PROVIDER_KINDS.contains(&value)
}

pub fn is_p2p_availability(value: &str) -> bool {
    P2P_AVAILABILITY_VALUES.contains(&value)
}

pub fn default_max_bytes_for_asset_kind(kind: &str) -> usize {
    match kind {
        ASSET_KIND_THUMBNAIL => THUMBNAIL_MAX_BYTES,
        ASSET_KIND_SOURCE_ICON | ASSET_KIND_LINK_PREVIEW => DEFAULT_IMAGE_ASSET_MAX_BYTES,
        _ => DEFAULT_IMAGE_ASSET_MAX_BYTES,
    }
}

fn parse_prefixed_lower_hex<'a>(
    value: &'a str,
    prefix: &str,
    error_code: &'static str,
) -> Result<&'a str, ContractError> {
    let Some(hex) = value.strip_prefix(prefix) else {
        return Err(ContractError::new(error_code));
    };
    parse_lower_hex(hex, HEX_HASH_LEN, error_code)
}

fn parse_lower_hex<'a>(
    value: &'a str,
    expected_len: usize,
    error_code: &'static str,
) -> Result<&'a str, ContractError> {
    if is_lower_hex(value, expected_len) {
        Ok(value)
    } else {
        Err(ContractError::new(error_code))
    }
}

fn is_lower_hex(value: &str, expected_len: usize) -> bool {
    value.len() == expected_len
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn is_iroh_base32_hash(value: &str) -> bool {
    value.len() == IROH_BLAKE3_BASE32_LEN
        && value
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || (b'2'..=b'7').contains(&byte))
}

fn required_string<'a>(
    payload: &'a Map<String, Value>,
    key: &str,
    error_code: &'static str,
) -> Result<&'a str, ContractError> {
    payload
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or(ContractError::new(error_code))
}

fn required_positive_i64(
    payload: &Map<String, Value>,
    key: &str,
    error_code: &'static str,
) -> Result<i64, ContractError> {
    payload
        .get(key)
        .and_then(Value::as_i64)
        .filter(|value| *value > 0)
        .ok_or(ContractError::new(error_code))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Value {
        serde_json::from_str(include_str!(
            "../../../fixtures/sync_contract/protocol_fixtures.json"
        ))
        .expect("shared protocol fixtures")
    }

    #[test]
    fn id_fixtures_match_contract() {
        let fixture = fixture();
        for value in fixture["ids"]["content_hash"]["valid_strict"]
            .as_array()
            .expect("valid content hashes")
        {
            assert!(ContentHash::parse_strict(value.as_str().unwrap()).is_ok());
        }
        for value in fixture["ids"]["content_hash"]["invalid_strict"]
            .as_array()
            .expect("invalid content hashes")
        {
            assert!(ContentHash::parse_strict(value.as_str().unwrap()).is_err());
        }
        for entry in fixture["ids"]["content_hash"]["client_normalize"]
            .as_array()
            .expect("client normalize entries")
        {
            let input = entry["input"].as_str().unwrap();
            let expected = entry["expected"].as_str().unwrap();
            assert_eq!(
                ContentHash::normalize_client(input).unwrap().as_str(),
                expected
            );
        }
        for value in fixture["ids"]["asset_digest"]["valid_strict"]
            .as_array()
            .expect("valid asset digests")
        {
            assert!(AssetDigest::parse_strict(value.as_str().unwrap()).is_ok());
        }
        for value in fixture["ids"]["asset_digest"]["invalid_strict"]
            .as_array()
            .expect("invalid asset digests")
        {
            assert!(AssetDigest::parse_strict(value.as_str().unwrap()).is_err());
        }
        for value in fixture["ids"]["p2p_asset_id"]["valid_strict"]
            .as_array()
            .expect("valid p2p asset ids")
        {
            assert!(P2pAssetId::parse_strict(value.as_str().unwrap()).is_ok());
        }
        for value in fixture["ids"]["p2p_asset_id"]["invalid_strict"]
            .as_array()
            .expect("invalid p2p asset ids")
        {
            assert!(P2pAssetId::parse_strict(value.as_str().unwrap()).is_err());
        }
    }

    #[test]
    fn event_shape_fixtures_match_contract() {
        let fixture = fixture();
        let events = fixture["events"].as_object().expect("events");
        let image_payload = events["image_upsert_with_thumbnail"]["payload"]
            .as_object()
            .expect("image payload");
        let metadata =
            ThumbnailMetadata::parse_shape_strict(Some(ITEM_TYPE_IMAGE), image_payload).unwrap();
        assert!(metadata.is_some());

        let no_thumbnail_payload = events["image_upsert_without_thumbnail"]["payload"]
            .as_object()
            .expect("image without thumbnail");
        assert_eq!(
            ThumbnailMetadata::parse_shape_strict(Some(ITEM_TYPE_IMAGE), no_thumbnail_payload)
                .unwrap(),
            None
        );

        let partial_payload = events["invalid_partial_thumbnail"]["payload"]
            .as_object()
            .expect("partial payload");
        assert_eq!(
            ThumbnailMetadata::parse_shape_strict(Some(ITEM_TYPE_IMAGE), partial_payload)
                .unwrap_err()
                .code(),
            "invalid_thumbnail_payload"
        );

        let non_image_payload = events["invalid_non_image_thumbnail"]["payload"]
            .as_object()
            .expect("non image payload");
        assert_eq!(
            ThumbnailMetadata::parse_shape_strict(Some("text"), non_image_payload)
                .unwrap_err()
                .code(),
            "invalid_thumbnail_payload"
        );

        let payload_update = events["payload_asset_update"]["payload"]
            .as_object()
            .expect("payload update");
        assert!(PayloadAssetUpdate::parse_shape_strict(payload_update).is_ok());

        let extra = events["invalid_payload_asset_update_extra"]["payload"]
            .as_object()
            .expect("extra payload update");
        assert_eq!(
            PayloadAssetUpdate::parse_shape_strict(extra)
                .unwrap_err()
                .code(),
            "invalid_payload_asset_update_payload"
        );

        let mismatch = events["invalid_payload_asset_update_mismatch"]["payload"]
            .as_object()
            .expect("mismatch payload update");
        assert_eq!(
            PayloadAssetUpdate::parse_shape_strict(mismatch)
                .unwrap_err()
                .code(),
            "invalid_payload_asset_update_payload"
        );
    }

    #[test]
    fn info_fixture_matches_constants() {
        let fixture = fixture();
        let info = fixture["info"].as_object().expect("info");
        assert_eq!(
            info["protocol_version"].as_u64(),
            Some(PROTOCOL_VERSION as u64)
        );
        assert_eq!(
            info["event_types"].as_array().unwrap().len(),
            EVENT_TYPES.len()
        );
        assert_eq!(
            info["asset_kinds"].as_array().unwrap().len(),
            ASSET_KINDS.len()
        );
        assert_eq!(
            info["thumbnail_normal_target_bytes"].as_u64(),
            Some(THUMBNAIL_NORMAL_TARGET_BYTES as u64)
        );
        assert_eq!(
            info["thumbnail_detail_target_bytes"].as_u64(),
            Some(THUMBNAIL_DETAIL_TARGET_BYTES as u64)
        );
        assert_eq!(
            info["thumbnail_max_bytes"].as_u64(),
            Some(THUMBNAIL_MAX_BYTES as u64)
        );
    }
}
