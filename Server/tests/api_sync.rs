mod common;

use axum::http::{Method, StatusCode};
use serde_json::json;
use sqlx::Row;

use common::{content_hash, delete_event, upsert_event, TestServer};

#[tokio::test]
async fn duplicate_push_does_not_increment_copy_count() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("duplicate-item");
    let body = upsert_event("event-1", &hash, 7);

    let first = server
        .json(
            Method::POST,
            "/v1/events",
            Some(&device.token),
            body.clone(),
            &[],
        )
        .await;
    assert_eq!(first.status, StatusCode::OK, "{:?}", first.body);
    assert_eq!(first.body["data"]["events"][0]["duplicate"], false);

    let replay = server
        .json(Method::POST, "/v1/events", Some(&device.token), body, &[])
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
            "/v1/events",
            Some(&first.device.token),
            upsert_event("space-event", &hash, 1),
            &[],
        )
        .await;
    assert_eq!(push.status, StatusCode::OK, "{:?}", push.body);

    let first_pull = server
        .empty(
            Method::GET,
            "/v1/events?after_seq=0&limit=10",
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
            "/v1/events?after_seq=0&limit=10",
            Some(&second.device.token),
        )
        .await;
    assert_eq!(
        second_pull.body["data"]["events"].as_array().unwrap().len(),
        0
    );
    assert_eq!(second_pull.body["data"]["next_cursor"], 0);

    let second_snapshot = server
        .empty(Method::GET, "/v1/snapshot", Some(&second.device.token))
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
        "/v1/events",
        Some(&device.token),
        body.clone(),
        &[],
    );
    let second = server.json(Method::POST, "/v1/events", Some(&device.token), body, &[]);
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
            "/v1/events",
            Some(&device.token),
            upsert_event("cursor-1", &hash, 1),
            &[],
        )
        .await;
    assert_eq!(push.status, StatusCode::OK, "{:?}", push.body);

    let pull = server
        .empty(
            Method::GET,
            "/v1/events?after_seq=0&limit=1",
            Some(&device.token),
        )
        .await;
    assert_eq!(pull.status, StatusCode::OK, "{:?}", pull.body);
    assert_eq!(pull.body["data"]["events"].as_array().unwrap().len(), 1);
    assert_eq!(pull.body["data"]["next_cursor"], 1);

    for uri in [
        "/v1/events?after_seq=-1",
        "/v1/events?after_seq=abc",
        "/v1/events?after_seq=9223372036854775808",
    ] {
        let response = server.empty(Method::GET, uri, Some(&device.token)).await;
        assert_eq!(response.status, StatusCode::BAD_REQUEST, "{uri}");
        assert_eq!(response.body["error"]["code"], "invalid_cursor");
    }

    let invalid_limit = server
        .empty(Method::GET, "/v1/events?limit=0", Some(&device.token))
        .await;
    assert_eq!(invalid_limit.status, StatusCode::BAD_REQUEST);
    assert_eq!(invalid_limit.body["error"]["code"], "invalid_limit");

    let beyond = server
        .empty(
            Method::GET,
            "/v1/events?after_seq=999&limit=10",
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
            "/v1/events",
            Some(&device.token),
            upsert_event("snap-1", &first_hash, 1),
            &[],
        )
        .await;
    assert_eq!(first.status, StatusCode::OK, "{:?}", first.body);

    let snapshot = server
        .empty(Method::GET, "/v1/snapshot", Some(&device.token))
        .await;
    assert_eq!(snapshot.status, StatusCode::OK, "{:?}", snapshot.body);
    let snapshot_seq = snapshot.body["data"]["snapshot_seq"].as_i64().unwrap();
    assert_eq!(snapshot_seq, 1);

    let second = server
        .json(
            Method::POST,
            "/v1/events",
            Some(&device.token),
            upsert_event("snap-2", &second_hash, 1),
            &[],
        )
        .await;
    assert_eq!(second.status, StatusCode::OK, "{:?}", second.body);

    let uri = format!("/v1/events?after_seq={snapshot_seq}");
    let later = server.empty(Method::GET, &uri, Some(&device.token)).await;
    assert_eq!(later.status, StatusCode::OK, "{:?}", later.body);
    assert_eq!(later.body["data"]["events"].as_array().unwrap().len(), 1);
    assert_eq!(later.body["data"]["events"][0]["content_hash"], second_hash);
}

#[tokio::test]
async fn tombstone_propagates_and_later_same_content_upsert_is_rejected() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let hash = content_hash("deleted-content");

    let delete = server
        .json(
            Method::POST,
            "/v1/events",
            Some(&device.token),
            delete_event("delete-1", &hash),
            &[],
        )
        .await;
    assert_eq!(delete.status, StatusCode::OK, "{:?}", delete.body);

    let snapshot = server
        .empty(Method::GET, "/v1/snapshot", Some(&device.token))
        .await;
    assert_eq!(snapshot.status, StatusCode::OK, "{:?}", snapshot.body);
    assert_eq!(snapshot.body["data"]["tombstones"][0]["content_hash"], hash);

    let upsert = server
        .json(
            Method::POST,
            "/v1/events",
            Some(&device.token),
            upsert_event("upsert-after-delete", &hash, 1),
            &[],
        )
        .await;
    assert_eq!(upsert.status, StatusCode::CONFLICT);
    assert_eq!(upsert.body["error"]["code"], "item_deleted");
}

#[tokio::test]
async fn event_validation_rejects_delta_outside_contract() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let response = server
        .json(
            Method::POST,
            "/v1/events",
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
