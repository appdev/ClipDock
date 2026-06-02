mod common;

use axum::http::{header, Method, StatusCode};

use common::TestServer;

#[tokio::test]
async fn health_is_unauthenticated_but_v1_info_requires_auth() {
    let server = TestServer::new().await;

    let health = server.empty(Method::GET, "/health", None).await;
    assert_eq!(health.status, StatusCode::OK, "{:?}", health.body);
    assert_eq!(health.body["protocol_version"], 1);

    let info = server.empty(Method::GET, "/v1/info", None).await;
    assert_eq!(info.status, StatusCode::UNAUTHORIZED);
    assert_eq!(info.body["error"]["code"], "unauthorized");
}

#[tokio::test]
async fn create_sync_returns_pairing_code_and_device_tokens_are_not_stored_plaintext() {
    let server = TestServer::new().await;

    let sync = server.create_sync().await;
    assert_eq!(sync.pairing_code.len(), 5);
    assert!(sync
        .pairing_code
        .bytes()
        .all(|byte| byte.is_ascii_alphanumeric()));
    let device = sync.device;
    assert!(device.token.starts_with("cds_"));

    let stored_token: Option<String> =
        sqlx::query_scalar("SELECT token_hash FROM devices WHERE id = ? AND token_hash = ?")
            .bind(&device.id)
            .bind(&device.token)
            .fetch_optional(&server.pool)
            .await
            .expect("query token storage");
    assert!(stored_token.is_none());
}

#[tokio::test]
async fn sync_create_malformed_json_returns_protocol_error_envelope() {
    let server = TestServer::new().await;
    let response = server
        .raw(
            Method::POST,
            "/v1/sync/create",
            None,
            br#"{"device_name":"broken""#.to_vec(),
            &[("content-type", "application/json")],
        )
        .await;

    assert_eq!(response.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        response.headers.get(header::CONTENT_TYPE).unwrap(),
        "application/json"
    );
    let body: serde_json::Value = serde_json::from_slice(&response.body).unwrap();
    assert_eq!(body["protocol_version"], 1);
    assert_eq!(body["error"]["code"], "malformed_json");
}

#[tokio::test]
async fn sync_create_unsupported_json_content_type_returns_protocol_error_envelope() {
    let server = TestServer::new().await;
    let response = server
        .raw(
            Method::POST,
            "/v1/sync/create",
            None,
            br#"{"device_name":"test-device"}"#.to_vec(),
            &[("content-type", "text/plain")],
        )
        .await;

    assert_eq!(response.status, StatusCode::UNSUPPORTED_MEDIA_TYPE);
    assert_eq!(
        response.headers.get(header::CONTENT_TYPE).unwrap(),
        "application/json"
    );
    let body: serde_json::Value = serde_json::from_slice(&response.body).unwrap();
    assert_eq!(body["protocol_version"], 1);
    assert_eq!(body["error"]["code"], "unsupported_json_content_type");
}

#[tokio::test]
async fn pairing_code_join_shares_the_same_sync_space_and_is_single_use() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let joined = server.join_sync(&sync.pairing_code).await;

    let original_info = server
        .empty(Method::GET, "/v1/info", Some(&sync.device.token))
        .await;
    let joined_info = server
        .empty(Method::GET, "/v1/info", Some(&joined.token))
        .await;
    assert_eq!(original_info.status, StatusCode::OK);
    assert_eq!(joined_info.status, StatusCode::OK);
    assert_eq!(original_info.body["data"]["sync_id"], sync.sync_id);
    assert_eq!(joined_info.body["data"]["sync_id"], sync.sync_id);
    assert_eq!(original_info.body["data"]["device_id"], sync.device.id);
    assert_eq!(joined_info.body["data"]["device_id"], joined.id);
    assert_eq!(original_info.body["data"]["device_name"], "test-device");
    assert_eq!(joined_info.body["data"]["device_name"], "joined-device");

    let reused = server
        .json(
            Method::POST,
            "/v1/sync/join",
            None,
            serde_json::json!({"pairing_code": sync.pairing_code, "device_name": "late-device"}),
            &[],
        )
        .await;
    assert_eq!(reused.status, StatusCode::FORBIDDEN);
    assert_eq!(reused.body["error"]["code"], "invalid_pairing_code");
}

#[tokio::test]
async fn authenticated_device_can_create_a_fresh_invite_for_its_sync_space() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let first_join = server.join_sync(&sync.pairing_code).await;

    let invite = server
        .empty(Method::POST, "/v1/sync/invites", Some(&first_join.token))
        .await;
    assert_eq!(invite.status, StatusCode::OK, "{:?}", invite.body);
    assert_eq!(invite.body["data"]["sync_id"], sync.sync_id);
    let fresh_code = invite.body["data"]["pairing_code"].as_str().unwrap();

    let second_join = server.join_sync(fresh_code).await;
    let info = server
        .empty(Method::GET, "/v1/info", Some(&second_join.token))
        .await;
    assert_eq!(info.body["data"]["sync_id"], sync.sync_id);
}

#[tokio::test]
async fn revoked_device_token_returns_forbidden() {
    let server = TestServer::new().await;
    let device = server.register().await;
    sqlx::query("UPDATE devices SET revoked_at_ms = 1 WHERE id = ?")
        .bind(&device.id)
        .execute(&server.pool)
        .await
        .expect("revoke device");

    let response = server
        .empty(Method::GET, "/v1/info", Some(&device.token))
        .await;
    assert_eq!(response.status, StatusCode::FORBIDDEN);
    assert_eq!(response.body["error"]["code"], "revoked_device");
}
