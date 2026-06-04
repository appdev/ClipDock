mod common;

use axum::http::{Method, StatusCode};
use serde_json::json;

use common::TestServer;

fn p2p_asset_id(label: &str) -> String {
    format!("blake3:{}", blake3::hash(label.as_bytes()).to_hex())
}

#[tokio::test]
async fn p2p_endpoint_reporting_is_visible_only_inside_the_sync_space() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let joined = server.join_sync(&sync.pairing_code).await;
    let unrelated = server.create_sync().await;

    let info = server
        .empty(Method::GET, "/v2/info", Some(&sync.device.token))
        .await;
    assert_eq!(info.status, StatusCode::OK, "{:?}", info.body);
    assert_eq!(info.body["data"]["p2p"]["enabled"], true);
    assert_eq!(info.body["data"]["p2p"]["transport"], "iroh-blobs");

    let report = server
        .json(
            Method::PUT,
            "/v2/p2p/endpoint",
            Some(&sync.device.token),
            json!({
                "endpoint_id": "iroh-node-a",
                "relay_url": "https://relay.example.invalid",
                "direct_addresses": ["/ip4/192.168.1.10/udp/4433/quic-v1"],
                "capabilities": {"blob_transfer": true, "transport": "iroh-blobs"},
                "quality": {"path_type": "direct", "rtt_ms": 14, "throughput_bytes_per_sec": 8000000}
            }),
            &[],
        )
        .await;
    assert_eq!(report.status, StatusCode::OK, "{:?}", report.body);
    assert_eq!(report.body["data"]["device_id"], sync.device.id);
    assert_eq!(
        report.body["data"]["endpoint"]["endpoint_id"],
        "iroh-node-a"
    );

    let joined_devices = server
        .empty(Method::GET, "/v2/p2p/devices", Some(&joined.token))
        .await;
    assert_eq!(
        joined_devices.status,
        StatusCode::OK,
        "{:?}",
        joined_devices.body
    );
    let devices = joined_devices.body["data"]["devices"].as_array().unwrap();
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0]["device_id"], sync.device.id);
    assert_eq!(devices[0]["endpoint"]["quality"]["path_type"], "direct");

    let unrelated_devices = server
        .empty(
            Method::GET,
            "/v2/p2p/devices",
            Some(&unrelated.device.token),
        )
        .await;
    assert_eq!(unrelated_devices.status, StatusCode::OK);
    assert_eq!(
        unrelated_devices.body["data"]["devices"]
            .as_array()
            .unwrap()
            .len(),
        0
    );
}

#[tokio::test]
async fn p2p_asset_providers_are_scoped_and_can_be_unregistered() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let joined = server.join_sync(&sync.pairing_code).await;
    let unrelated = server.create_sync().await;
    let asset_id = p2p_asset_id("large-file");

    let endpoint = server
        .json(
            Method::PUT,
            "/v2/p2p/endpoint",
            Some(&sync.device.token),
            json!({
                "endpoint_id": "iroh-node-provider",
                "capabilities": {"blob_transfer": true},
                "quality": {"path_type": "relay", "rtt_ms": 82}
            }),
            &[],
        )
        .await;
    assert_eq!(endpoint.status, StatusCode::OK, "{:?}", endpoint.body);

    let provider_uri = format!("/v2/p2p/assets/{asset_id}/providers/me");
    let register = server
        .json(
            Method::PUT,
            &provider_uri,
            Some(&sync.device.token),
            json!({
                "kind": "file_payload",
                "byte_count": 7340032,
                "mime_type": "application/pdf",
                "quality": {"last_probe_path": "relay", "throughput_bytes_per_sec": 3200000}
            }),
            &[],
        )
        .await;
    assert_eq!(register.status, StatusCode::OK, "{:?}", register.body);
    assert_eq!(register.body["data"]["asset_id"], asset_id);
    assert_eq!(register.body["data"]["provider"]["availability"], "online");

    let providers_uri = format!("/v2/p2p/assets/{asset_id}/providers");
    let joined_lookup = server
        .empty(Method::GET, &providers_uri, Some(&joined.token))
        .await;
    assert_eq!(
        joined_lookup.status,
        StatusCode::OK,
        "{:?}",
        joined_lookup.body
    );
    let providers = joined_lookup.body["data"]["providers"].as_array().unwrap();
    assert_eq!(providers.len(), 1);
    assert_eq!(providers[0]["device_id"], sync.device.id);
    assert_eq!(
        providers[0]["endpoint"]["endpoint_id"],
        "iroh-node-provider"
    );
    assert_eq!(providers[0]["endpoint"]["quality"]["path_type"], "relay");

    let unrelated_lookup = server
        .empty(Method::GET, &providers_uri, Some(&unrelated.device.token))
        .await;
    assert_eq!(unrelated_lookup.status, StatusCode::OK);
    assert_eq!(
        unrelated_lookup.body["data"]["providers"]
            .as_array()
            .unwrap()
            .len(),
        0
    );

    let unregister = server
        .empty(Method::DELETE, &provider_uri, Some(&sync.device.token))
        .await;
    assert_eq!(unregister.status, StatusCode::OK, "{:?}", unregister.body);
    assert_eq!(unregister.body["data"]["removed"], true);

    let after_unregister = server
        .empty(Method::GET, &providers_uri, Some(&joined.token))
        .await;
    assert_eq!(after_unregister.status, StatusCode::OK);
    assert_eq!(
        after_unregister.body["data"]["providers"]
            .as_array()
            .unwrap()
            .len(),
        0
    );
}

#[tokio::test]
async fn p2p_asset_providers_accept_iroh_blake3_hashes() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let joined = server.join_sync(&sync.pairing_code).await;
    let asset_id = "blake3:m5tc73yctukegc4csotnjt2ghx4pbrttwq7thwdqb6aqnmoa5hgq";

    let provider_uri = format!("/v2/p2p/assets/{asset_id}/providers/me");
    let register = server
        .json(
            Method::PUT,
            &provider_uri,
            Some(&sync.device.token),
            json!({
                "kind": "image_payload",
                "byte_count": 70,
                "mime_type": "image/png",
                "quality": {"transport": "iroh-blobs", "blob_ticket": "blob-test"}
            }),
            &[],
        )
        .await;
    assert_eq!(register.status, StatusCode::OK, "{:?}", register.body);
    assert_eq!(register.body["data"]["asset_id"], asset_id);

    let providers_uri = format!("/v2/p2p/assets/{asset_id}/providers");
    let lookup = server
        .empty(Method::GET, &providers_uri, Some(&joined.token))
        .await;
    assert_eq!(lookup.status, StatusCode::OK, "{:?}", lookup.body);
    assert_eq!(
        lookup.body["data"]["providers"].as_array().unwrap().len(),
        1
    );
}

#[tokio::test]
async fn p2p_rejects_invalid_endpoint_and_provider_metadata() {
    let server = TestServer::new().await;
    let device = server.register().await;

    let invalid_endpoint = server
        .json(
            Method::PUT,
            "/v2/p2p/endpoint",
            Some(&device.token),
            json!({"endpoint_id": "", "capabilities": []}),
            &[],
        )
        .await;
    assert_eq!(invalid_endpoint.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        invalid_endpoint.body["error"]["code"],
        "invalid_endpoint_id"
    );

    let invalid_asset = server
        .json(
            Method::PUT,
            "/v2/p2p/assets/not-a-hash/providers/me",
            Some(&device.token),
            json!({"kind": "file_payload"}),
            &[],
        )
        .await;
    assert_eq!(invalid_asset.status, StatusCode::BAD_REQUEST);
    assert_eq!(invalid_asset.body["error"]["code"], "invalid_asset_id");

    let unsupported_kind = server
        .json(
            Method::PUT,
            "/v2/p2p/assets/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/providers/me",
            Some(&device.token),
            json!({"kind": "avatar"}),
            &[],
        )
        .await;
    assert_eq!(unsupported_kind.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        unsupported_kind.body["error"]["code"],
        "unsupported_provider_kind"
    );

    let invalid_quality = server
        .json(
            Method::PUT,
            "/v2/p2p/assets/sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/providers/me",
            Some(&device.token),
            json!({"kind": "file_payload", "quality": []}),
            &[],
        )
        .await;
    assert_eq!(invalid_quality.status, StatusCode::BAD_REQUEST);
    assert_eq!(invalid_quality.body["error"]["code"], "invalid_quality");
}

#[tokio::test]
async fn expired_p2p_endpoints_are_not_used_for_discovery_or_provider_lookup() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let joined = server.join_sync(&sync.pairing_code).await;
    let asset_id = p2p_asset_id("stale-provider");

    let endpoint = server
        .json(
            Method::PUT,
            "/v2/p2p/endpoint",
            Some(&sync.device.token),
            json!({"endpoint_id": "soon-stale-node"}),
            &[],
        )
        .await;
    assert_eq!(endpoint.status, StatusCode::OK, "{:?}", endpoint.body);

    let provider_uri = format!("/v2/p2p/assets/{asset_id}/providers/me");
    let register = server
        .json(
            Method::PUT,
            &provider_uri,
            Some(&sync.device.token),
            json!({"kind": "image_payload", "byte_count": 1024, "mime_type": "image/png"}),
            &[],
        )
        .await;
    assert_eq!(register.status, StatusCode::OK, "{:?}", register.body);

    sqlx::query("UPDATE device_p2p_endpoints SET expires_at_ms = 0 WHERE device_id = ?")
        .bind(&sync.device.id)
        .execute(&server.pool)
        .await
        .expect("expire endpoint");

    let devices = server
        .empty(Method::GET, "/v2/p2p/devices", Some(&joined.token))
        .await;
    assert_eq!(devices.status, StatusCode::OK, "{:?}", devices.body);
    assert_eq!(devices.body["data"]["devices"].as_array().unwrap().len(), 0);

    let providers_uri = format!("/v2/p2p/assets/{asset_id}/providers");
    let lookup = server
        .empty(Method::GET, &providers_uri, Some(&joined.token))
        .await;
    assert_eq!(lookup.status, StatusCode::OK, "{:?}", lookup.body);
    let providers = lookup.body["data"]["providers"].as_array().unwrap();
    assert_eq!(providers.len(), 1);
    assert_eq!(providers[0]["availability"], "last_seen");
    assert!(providers[0]["endpoint"].is_null());
}
