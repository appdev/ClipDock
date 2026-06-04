mod common;

use axum::http::{Method, StatusCode};
use clipdock_sync_contract::{
    AssetDigest, ContentHash, P2pAssetId, PayloadAssetUpdate, ThumbnailMetadata,
    ASSET_KIND_LINK_PREVIEW, ASSET_KIND_SOURCE_ICON, ASSET_KIND_THUMBNAIL,
};
use serde_json::Value;

use common::TestServer;

#[test]
fn shared_contract_fixtures_match_server_validators() {
    let fixture = fixture();

    for value in fixture["ids"]["content_hash"]["valid_strict"]
        .as_array()
        .expect("valid content hash fixtures")
    {
        assert!(ContentHash::parse_strict(value.as_str().unwrap()).is_ok());
    }
    for value in fixture["ids"]["content_hash"]["invalid_strict"]
        .as_array()
        .expect("invalid content hash fixtures")
    {
        assert!(ContentHash::parse_strict(value.as_str().unwrap()).is_err());
    }
    for value in fixture["ids"]["asset_digest"]["valid_strict"]
        .as_array()
        .expect("valid asset digest fixtures")
    {
        assert!(AssetDigest::parse_strict(value.as_str().unwrap()).is_ok());
    }
    for value in fixture["ids"]["p2p_asset_id"]["valid_strict"]
        .as_array()
        .expect("valid p2p asset id fixtures")
    {
        assert!(P2pAssetId::parse_strict(value.as_str().unwrap()).is_ok());
    }

    let events = fixture["events"].as_object().expect("events");
    let image = events["image_upsert_with_thumbnail"]["payload"]
        .as_object()
        .expect("image payload");
    assert!(ThumbnailMetadata::parse_shape_strict(Some("image"), image)
        .unwrap()
        .is_some());
    let payload_update = events["payload_asset_update"]["payload"]
        .as_object()
        .expect("payload update");
    assert!(PayloadAssetUpdate::parse_shape_strict(payload_update).is_ok());
}

#[tokio::test]
async fn v2_info_matches_shared_contract_fixture() {
    let fixture = fixture();
    let expected = fixture["info"].as_object().expect("info fixture");
    let server = TestServer::new().await;
    let device = server.register().await;

    let response = server
        .empty(Method::GET, "/v2/info", Some(&device.token))
        .await;

    assert_eq!(response.status, StatusCode::OK, "{:?}", response.body);
    let data = &response.body["data"];
    assert_eq!(data["protocol_version"], expected["protocol_version"]);
    assert_eq!(data["event_types"], expected["event_types"]);
    assert_eq!(data["asset_kinds"], expected["asset_kinds"]);
    assert_eq!(data["asset_mime_types"], expected["asset_mime_types"]);
    assert_eq!(
        data["content_hash_algorithms"],
        expected["content_hash_algorithms"]
    );
    assert_eq!(
        data["asset_digest_algorithms"],
        expected["asset_digest_algorithms"]
    );
    assert_eq!(
        data["thumbnail_normal_target_bytes"],
        expected["thumbnail_normal_target_bytes"]
    );
    assert_eq!(
        data["thumbnail_detail_target_bytes"],
        expected["thumbnail_detail_target_bytes"]
    );
    assert_eq!(data["thumbnail_max_bytes"], expected["thumbnail_max_bytes"]);
    assert_eq!(
        data["asset_max_dimension_px"],
        expected["asset_max_dimension_px"]
    );
    assert_eq!(data["asset_max_pixels"], expected["asset_max_pixels"]);
    assert_eq!(
        data["per_kind_asset_max_bytes"][ASSET_KIND_THUMBNAIL],
        expected["thumbnail_max_bytes"]
    );
    assert!(data["per_kind_asset_max_bytes"][ASSET_KIND_SOURCE_ICON]
        .as_u64()
        .is_some_and(|value| value > 0));
    assert!(data["per_kind_asset_max_bytes"][ASSET_KIND_LINK_PREVIEW]
        .as_u64()
        .is_some_and(|value| value > 0));
    assert_eq!(
        data["p2p"]["provider_kinds"],
        expected["p2p_provider_kinds"]
    );
}

fn fixture() -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../shared/fixtures/sync_contract/protocol_fixtures.json");
    let text = std::fs::read_to_string(path).expect("shared sync contract fixture");
    serde_json::from_str(&text).expect("parse shared sync contract fixture")
}
