mod common;

use axum::http::{Method, StatusCode};
use serde_json::json;
use sqlx::Row;

use common::{asset_digest, content_hash, delete_event, png_1x1, upsert_event, TestServer};

#[tokio::test]
async fn duplicate_push_does_not_increment_copy_count() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("duplicate-item");
    let body = upsert_event("event-1", &hash, 7);

    let first = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            body.clone(),
            &[],
        )
        .await;
    assert_eq!(first.status, StatusCode::OK, "{:?}", first.body);
    assert_eq!(first.body["data"]["events"][0]["duplicate"], false);

    let replay = server
        .json(Method::POST, "/v2/events", Some(&device.token), body, &[])
        .await;
    assert_eq!(replay.status, StatusCode::OK, "{:?}", replay.body);
    assert_eq!(replay.body["data"]["events"][0]["duplicate"], true);

    let row = sqlx::query("SELECT copy_count FROM sync_items WHERE content_hash = ?")
        .bind(&hash)
        .fetch_one(&server.pool)
        .await
        .expect("copy count row");
    assert_eq!(row.get::<i64, _>("copy_count"), 7);
}

#[tokio::test]
async fn independent_sync_spaces_do_not_share_events_or_snapshots() {
    let server = TestServer::new().await;
    let first = server.create_sync().await;
    let second = server.create_sync().await;
    let hash = content_hash("space-isolation");

    let push = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&first.device.token),
            upsert_event("space-event", &hash, 1),
            &[],
        )
        .await;
    assert_eq!(push.status, StatusCode::OK, "{:?}", push.body);

    let first_pull = server
        .empty(
            Method::GET,
            "/v2/events?after_seq=0&limit=10",
            Some(&first.device.token),
        )
        .await;
    assert_eq!(
        first_pull.body["data"]["events"].as_array().unwrap().len(),
        1
    );

    let second_pull = server
        .empty(
            Method::GET,
            "/v2/events?after_seq=0&limit=10",
            Some(&second.device.token),
        )
        .await;
    assert_eq!(
        second_pull.body["data"]["events"].as_array().unwrap().len(),
        0
    );
    assert_eq!(second_pull.body["data"]["next_cursor"], 0);

    let second_snapshot = server
        .empty(Method::GET, "/v2/snapshot", Some(&second.device.token))
        .await;
    assert_eq!(
        second_snapshot.body["data"]["items"]
            .as_array()
            .unwrap()
            .len(),
        0
    );
}

#[tokio::test]
async fn concurrent_duplicate_push_is_idempotent() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("concurrent-duplicate");
    let body = upsert_event("same-event", &hash, 4);

    let first = server.json(
        Method::POST,
        "/v2/events",
        Some(&device.token),
        body.clone(),
        &[],
    );
    let second = server.json(Method::POST, "/v2/events", Some(&device.token), body, &[]);
    let (first, second) = tokio::join!(first, second);
    assert_eq!(first.status, StatusCode::OK, "{:?}", first.body);
    assert_eq!(second.status, StatusCode::OK, "{:?}", second.body);

    let row = sqlx::query("SELECT copy_count FROM sync_items WHERE content_hash = ?")
        .bind(&hash)
        .fetch_one(&server.pool)
        .await
        .expect("copy count row");
    assert_eq!(row.get::<i64, _>("copy_count"), 4);
}

#[tokio::test]
async fn cursor_replay_invalid_cursor_and_beyond_latest() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("cursor-item");
    let push = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            upsert_event("cursor-1", &hash, 1),
            &[],
        )
        .await;
    assert_eq!(push.status, StatusCode::OK, "{:?}", push.body);

    let pull = server
        .empty(
            Method::GET,
            "/v2/events?after_seq=0&limit=1",
            Some(&device.token),
        )
        .await;
    assert_eq!(pull.status, StatusCode::OK, "{:?}", pull.body);
    assert_eq!(pull.body["data"]["events"].as_array().unwrap().len(), 1);
    assert_eq!(pull.body["data"]["next_cursor"], 1);

    for uri in [
        "/v2/events?after_seq=-1",
        "/v2/events?after_seq=abc",
        "/v2/events?after_seq=9223372036854775808",
    ] {
        let response = server.empty(Method::GET, uri, Some(&device.token)).await;
        assert_eq!(response.status, StatusCode::BAD_REQUEST, "{uri}");
        assert_eq!(response.body["error"]["code"], "invalid_cursor");
    }

    let invalid_limit = server
        .empty(Method::GET, "/v2/events?limit=0", Some(&device.token))
        .await;
    assert_eq!(invalid_limit.status, StatusCode::BAD_REQUEST);
    assert_eq!(invalid_limit.body["error"]["code"], "invalid_limit");

    let beyond = server
        .empty(
            Method::GET,
            "/v2/events?after_seq=999&limit=10",
            Some(&device.token),
        )
        .await;
    assert_eq!(beyond.status, StatusCode::OK, "{:?}", beyond.body);
    assert_eq!(beyond.body["data"]["events"].as_array().unwrap().len(), 0);
    assert_eq!(beyond.body["data"]["next_cursor"], 1);
}

#[tokio::test]
async fn snapshot_then_pull_later_event() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let first_hash = content_hash("snapshot-first");
    let second_hash = content_hash("snapshot-second");

    let first = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            upsert_event("snap-1", &first_hash, 1),
            &[],
        )
        .await;
    assert_eq!(first.status, StatusCode::OK, "{:?}", first.body);

    let snapshot = server
        .empty(Method::GET, "/v2/snapshot", Some(&device.token))
        .await;
    assert_eq!(snapshot.status, StatusCode::OK, "{:?}", snapshot.body);
    let snapshot_seq = snapshot.body["data"]["snapshot_seq"].as_i64().unwrap();
    assert_eq!(snapshot_seq, 1);

    let second = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            upsert_event("snap-2", &second_hash, 1),
            &[],
        )
        .await;
    assert_eq!(second.status, StatusCode::OK, "{:?}", second.body);

    let uri = format!("/v2/events?after_seq={snapshot_seq}");
    let later = server.empty(Method::GET, &uri, Some(&device.token)).await;
    assert_eq!(later.status, StatusCode::OK, "{:?}", later.body);
    assert_eq!(later.body["data"]["events"].as_array().unwrap().len(), 1);
    assert_eq!(later.body["data"]["events"][0]["content_hash"], second_hash);
}

#[tokio::test]
async fn tombstone_propagates_and_later_same_content_upsert_restores_item() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("deleted-content");

    let delete = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            delete_event("delete-1", &hash),
            &[],
        )
        .await;
    assert_eq!(delete.status, StatusCode::OK, "{:?}", delete.body);

    let snapshot = server
        .empty(Method::GET, "/v2/snapshot", Some(&device.token))
        .await;
    assert_eq!(snapshot.status, StatusCode::OK, "{:?}", snapshot.body);
    assert_eq!(snapshot.body["data"]["tombstones"][0]["content_hash"], hash);

    let upsert = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            upsert_event("upsert-after-delete", &hash, 1),
            &[],
        )
        .await;
    assert_eq!(upsert.status, StatusCode::OK, "{:?}", upsert.body);

    let restored_snapshot = server
        .empty(Method::GET, "/v2/snapshot", Some(&device.token))
        .await;
    assert_eq!(
        restored_snapshot.status,
        StatusCode::OK,
        "{:?}",
        restored_snapshot.body
    );
    assert_eq!(
        restored_snapshot.body["data"]["tombstones"]
            .as_array()
            .unwrap()
            .len(),
        0
    );
    assert_eq!(
        restored_snapshot.body["data"]["items"][0]["content_hash"],
        hash
    );
}

#[tokio::test]
async fn event_validation_rejects_delta_outside_contract() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let response = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "bad-delta",
                    "type": "item_upsert",
                    "content_hash": content_hash("bad-delta"),
                    "item_type": "text",
                    "payload": {"text": "x"},
                    "copy_count_delta": 101
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(response.status, StatusCode::BAD_REQUEST);
    assert_eq!(response.body["error"]["code"], "invalid_copy_count_delta");
}

#[tokio::test]
async fn image_upsert_materializes_thumbnail_fields_and_link() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("image-with-thumbnail");
    let (digest, byte_count) = upload_test_thumbnail(&server, &device.token).await;

    let upsert = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "image-thumb-upsert",
                    "type": "item_upsert",
                    "content_hash": hash,
                    "item_type": "image",
                    "payload": {
                        "file_name": "image.png",
                        "mime_type": "image/png",
                        "byte_count": 100,
                        "thumbnail_digest": digest,
                        "thumbnail_mime_type": "image/png",
                        "thumbnail_byte_count": byte_count,
                        "thumbnail_width": 1,
                        "thumbnail_height": 1
                    },
                    "copy_count_delta": 1
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(upsert.status, StatusCode::OK, "{:?}", upsert.body);

    let link_count = sqlx::query(
        "SELECT COUNT(*) AS count
         FROM sync_item_assets
         WHERE content_hash = ? AND role = 'thumbnail'",
    )
    .bind(&hash)
    .fetch_one(&server.pool)
    .await
    .expect("thumbnail link")
    .get::<i64, _>("count");
    assert_eq!(link_count, 1);

    let snapshot = server
        .empty(Method::GET, "/v2/snapshot", Some(&device.token))
        .await;
    assert_eq!(snapshot.status, StatusCode::OK, "{:?}", snapshot.body);
    let payload = &snapshot.body["data"]["items"][0]["payload"];
    assert_eq!(payload["thumbnail_digest"], digest);
    assert_eq!(payload["thumbnail_width"], 1);

    let clear = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "image-thumb-clear",
                    "type": "item_upsert",
                    "content_hash": hash,
                    "item_type": "image",
                    "payload": {
                        "file_name": "image.png",
                        "mime_type": "image/png",
                        "byte_count": 100
                    },
                    "copy_count_delta": 1
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(clear.status, StatusCode::OK, "{:?}", clear.body);
    let link_count = sqlx::query(
        "SELECT COUNT(*) AS count
         FROM sync_item_assets
         WHERE content_hash = ? AND role = 'thumbnail'",
    )
    .bind(&hash)
    .fetch_one(&server.pool)
    .await
    .expect("thumbnail link cleared")
    .get::<i64, _>("count");
    assert_eq!(link_count, 0);
}

#[tokio::test]
async fn thumbnail_fields_are_all_or_none_and_image_only() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("bad-thumbnail-fields");

    let partial = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "partial-thumbnail",
                    "type": "item_upsert",
                    "content_hash": hash,
                    "item_type": "image",
                    "payload": {
                        "file_name": "image.png",
                        "thumbnail_digest": "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                    },
                    "copy_count_delta": 1
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(partial.status, StatusCode::BAD_REQUEST);
    assert_eq!(partial.body["error"]["code"], "invalid_thumbnail_payload");

    let non_image = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "text-thumbnail",
                    "type": "item_upsert",
                    "content_hash": content_hash("text-thumbnail"),
                    "item_type": "text",
                    "payload": {
                        "text": "not an image",
                        "thumbnail_digest": "blake3:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                        "thumbnail_mime_type": "image/png",
                        "thumbnail_byte_count": 1,
                        "thumbnail_width": 1,
                        "thumbnail_height": 1
                    },
                    "copy_count_delta": 1
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(non_image.status, StatusCode::BAD_REQUEST);
    assert_eq!(non_image.body["error"]["code"], "invalid_thumbnail_payload");
}

#[tokio::test]
async fn payload_asset_update_merges_p2p_metadata_without_reordering_or_copy_count() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("delayed-payload-asset");
    let asset_id = content_hash("p2p-image-payload");

    let upsert = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "delayed-image-upsert",
                    "type": "item_upsert",
                    "content_hash": hash,
                    "item_type": "image",
                    "payload": {
                        "file_name": "image.png",
                        "mime_type": "image/png",
                        "byte_count": 100
                    },
                    "copy_count_delta": 3
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(upsert.status, StatusCode::OK, "{:?}", upsert.body);
    let before = sync_item_row(&server, &hash).await;

    let provider_uri = format!("/v2/p2p/assets/{asset_id}/providers/me");
    let provider = server
        .json(
            Method::PUT,
            &provider_uri,
            Some(&device.token),
            json!({
                "kind": "image_payload",
                "byte_count": 100,
                "mime_type": "image/png",
                "availability": "online"
            }),
            &[],
        )
        .await;
    assert_eq!(provider.status, StatusCode::OK, "{:?}", provider.body);

    let update = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "payload-asset-update",
                    "type": "item_payload_asset_update",
                    "content_hash": hash,
                    "item_type": "image",
                    "payload": {
                        "payload_asset_id": asset_id,
                        "asset_id": asset_id
                    }
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(update.status, StatusCode::OK, "{:?}", update.body);

    let after = sync_item_row(&server, &hash).await;
    assert_eq!(after.copy_count, before.copy_count);
    assert_eq!(after.updated_at_ms, before.updated_at_ms);
    assert!(after.last_server_seq > before.last_server_seq);

    let snapshot = server
        .empty(Method::GET, "/v2/snapshot", Some(&device.token))
        .await;
    let payload = &snapshot.body["data"]["items"][0]["payload"];
    assert_eq!(payload["payload_asset_id"], asset_id);
    assert_eq!(payload["asset_id"], asset_id);

    let pull = server
        .empty(Method::GET, "/v2/events?after_seq=1", Some(&device.token))
        .await;
    assert_eq!(
        pull.body["data"]["events"][0]["type"],
        "item_payload_asset_update"
    );
}

#[tokio::test]
async fn payload_asset_update_rejects_invalid_lifecycle_and_payload_cases() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("payload-update-rejections");
    let asset_id = content_hash("missing-provider");

    let missing_item = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            payload_update_body("missing-item-update", &hash, &asset_id),
            &[],
        )
        .await;
    assert_eq!(missing_item.status, StatusCode::CONFLICT);
    assert_eq!(
        missing_item.body["error"]["code"],
        "payload_asset_update_item_missing"
    );

    let upsert = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [{
                    "client_event_id": "non-image-upsert",
                    "type": "item_upsert",
                    "content_hash": hash,
                    "item_type": "text",
                    "payload": {"text": "x"},
                    "copy_count_delta": 1
                }]
            }),
            &[],
        )
        .await;
    assert_eq!(upsert.status, StatusCode::OK);

    let non_image = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            payload_update_body("non-image-update", &hash, &asset_id),
            &[],
        )
        .await;
    assert_eq!(non_image.status, StatusCode::CONFLICT);
    assert_eq!(
        non_image.body["error"]["code"],
        "payload_asset_update_item_type_mismatch"
    );

    let mixed_batch = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&device.token),
            json!({
                "events": [
                    {
                        "client_event_id": "normal-in-mixed",
                        "type": "item_upsert",
                        "content_hash": content_hash("normal-in-mixed"),
                        "item_type": "text",
                        "payload": {"text": "x"},
                        "copy_count_delta": 1
                    },
                    {
                        "client_event_id": "update-in-mixed",
                        "type": "item_payload_asset_update",
                        "content_hash": hash,
                        "item_type": "image",
                        "payload": {"payload_asset_id": asset_id, "asset_id": asset_id}
                    }
                ]
            }),
            &[],
        )
        .await;
    assert_eq!(mixed_batch.status, StatusCode::BAD_REQUEST);
    assert_eq!(
        mixed_batch.body["error"]["code"],
        "payload_asset_update_must_be_single_event"
    );
}

struct SyncItemRow {
    copy_count: i64,
    updated_at_ms: i64,
    last_server_seq: i64,
}

async fn sync_item_row(server: &TestServer, hash: &str) -> SyncItemRow {
    let row = sqlx::query(
        "SELECT copy_count, updated_at_ms, last_server_seq
         FROM sync_items
         WHERE content_hash = ?",
    )
    .bind(hash)
    .fetch_one(&server.pool)
    .await
    .expect("sync item row");
    SyncItemRow {
        copy_count: row.get("copy_count"),
        updated_at_ms: row.get("updated_at_ms"),
        last_server_seq: row.get("last_server_seq"),
    }
}

async fn upload_test_thumbnail(server: &TestServer, token: &str) -> (String, i64) {
    let bytes = png_1x1();
    let digest = asset_digest(&bytes);
    let upload = server
        .raw(
            Method::PUT,
            &format!("/v2/assets/{digest}"),
            Some(token),
            bytes.clone(),
            &[
                ("content-type", "image/png"),
                ("x-clipdock-asset-kind", "thumbnail"),
                ("x-clipdock-asset-width", "1"),
                ("x-clipdock-asset-height", "1"),
            ],
        )
        .await;
    assert_eq!(upload.status, StatusCode::OK, "{:?}", upload.body);
    (digest, bytes.len() as i64)
}

fn payload_update_body(client_event_id: &str, hash: &str, asset_id: &str) -> serde_json::Value {
    json!({
        "events": [{
            "client_event_id": client_event_id,
            "type": "item_payload_asset_update",
            "content_hash": hash,
            "item_type": "image",
            "payload": {
                "payload_asset_id": asset_id,
                "asset_id": asset_id
            }
        }]
    })
}
