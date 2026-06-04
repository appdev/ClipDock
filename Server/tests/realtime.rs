mod common;

use axum::http::{Method, StatusCode};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use sqlx::Row;
use tokio::time::{timeout, Duration};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{client::IntoClientRequest, Error as WsError, Message},
};

use common::{content_hash, upsert_event, TestServer};

#[tokio::test]
async fn websocket_rejects_bad_auth_cursor_and_protocol() {
    let server = TestServer::new().await;
    let device = server.register().await;
    let live = server.spawn_http().await;

    let unauthorized = connect_async(live.ws_url("/v2/ws?cursor=0&protocol_version=2")).await;
    assert_http_error(unauthorized, StatusCode::UNAUTHORIZED);

    let invalid_cursor = connect_with_token(
        &live.ws_url("/v2/ws?cursor=-1&protocol_version=2"),
        &device.token,
    )
    .await;
    assert_http_error(invalid_cursor, StatusCode::BAD_REQUEST);

    let unsupported_protocol = connect_with_token(
        &live.ws_url("/v2/ws?cursor=0&protocol_version=1"),
        &device.token,
    )
    .await;
    assert_http_error(unsupported_protocol, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn websocket_broadcasts_same_sync_only_and_ack_is_monotonic() {
    let server = TestServer::new().await;
    let first = server.create_sync().await;
    let joined = server.join_sync(&first.pairing_code).await;
    let isolated = server.create_sync().await;
    let live = server.spawn_http().await;

    let (mut same_sync_socket, _) = connect_with_token(
        &live.ws_url("/v2/ws?cursor=0&protocol_version=2"),
        &joined.token,
    )
    .await
    .expect("same sync websocket");
    let hello = read_json(&mut same_sync_socket).await;
    assert_eq!(hello["type"], "hello");

    let (mut isolated_socket, _) = connect_with_token(
        &live.ws_url("/v2/ws?cursor=0&protocol_version=2"),
        &isolated.device.token,
    )
    .await
    .expect("isolated websocket");
    let isolated_hello = read_json(&mut isolated_socket).await;
    assert_eq!(isolated_hello["type"], "hello");

    let hash = content_hash("same-sync-realtime");
    let push = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&first.device.token),
            upsert_event("realtime-1", &hash, 1),
            &[],
        )
        .await;
    assert_eq!(push.status, StatusCode::OK, "{:?}", push.body);
    let server_seq = push.body["data"]["events"][0]["server_seq"]
        .as_i64()
        .unwrap();

    let batch = read_json(&mut same_sync_socket).await;
    assert_eq!(batch["type"], "event_batch");
    assert_eq!(batch["events"][0]["server_seq"], server_seq);
    assert_eq!(batch["events"][0]["content_hash"], hash);

    let no_cross_sync = timeout(Duration::from_millis(150), isolated_socket.next()).await;
    assert!(
        no_cross_sync.is_err(),
        "cross-sync socket received an event"
    );

    same_sync_socket
        .send(Message::Text(
            json!({"type":"ack","server_seq": -1}).to_string(),
        ))
        .await
        .expect("send negative ack");
    let invalid_ack = read_json(&mut same_sync_socket).await;
    assert_eq!(invalid_ack["type"], "error");
    assert_eq!(invalid_ack["code"], "invalid_ack");

    same_sync_socket
        .send(Message::Text(
            json!({"type":"ack","server_seq": server_seq + 100}).to_string(),
        ))
        .await
        .expect("send future ack");
    let future_ack = read_json(&mut same_sync_socket).await;
    assert_eq!(future_ack["code"], "future_ack");

    same_sync_socket
        .send(Message::Text(
            json!({"type":"ack","server_seq": server_seq}).to_string(),
        ))
        .await
        .expect("send valid ack");
    same_sync_socket
        .send(Message::Text(
            json!({"type":"ack","server_seq": server_seq}).to_string(),
        ))
        .await
        .expect("send duplicate ack");
    same_sync_socket
        .send(Message::Text(
            json!({"type":"ack","server_seq": 0}).to_string(),
        ))
        .await
        .expect("send stale ack");

    tokio::time::sleep(Duration::from_millis(50)).await;
    let stored_ack = sqlx::query(
        "SELECT last_acked_seq FROM device_sync_state WHERE sync_group_id = ? AND device_id = ?",
    )
    .bind(&first.sync_id)
    .bind(&joined.id)
    .fetch_one(&server.pool)
    .await
    .expect("stored ack")
    .get::<i64, _>("last_acked_seq");
    assert_eq!(stored_ack, server_seq);
}

#[tokio::test]
async fn duplicate_replay_does_not_broadcast_but_mixed_batch_broadcasts_new_events() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let listener = server.join_sync(&sync.pairing_code).await;
    let live = server.spawn_http().await;
    let (mut socket, _) = connect_with_token(
        &live.ws_url("/v2/ws?cursor=0&protocol_version=2"),
        &listener.token,
    )
    .await
    .expect("websocket");
    assert_eq!(read_json(&mut socket).await["type"], "hello");

    let first_hash = content_hash("duplicate-broadcast");
    let first = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&sync.device.token),
            upsert_event("dup-1", &first_hash, 1),
            &[],
        )
        .await;
    assert_eq!(first.status, StatusCode::OK, "{:?}", first.body);
    assert_eq!(
        read_json(&mut socket).await["events"]
            .as_array()
            .unwrap()
            .len(),
        1
    );

    let duplicate = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&sync.device.token),
            upsert_event("dup-1", &first_hash, 1),
            &[],
        )
        .await;
    assert_eq!(duplicate.status, StatusCode::OK, "{:?}", duplicate.body);
    assert!(timeout(Duration::from_millis(150), socket.next())
        .await
        .is_err());

    let second_hash = content_hash("mixed-new");
    let mixed = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&sync.device.token),
            json!({
                "events": [
                    {
                        "client_event_id": "dup-1",
                        "type": "item_upsert",
                        "content_hash": first_hash,
                        "item_type": "text",
                        "payload": {"text": "duplicate"},
                        "copy_count_delta": 1
                    },
                    {
                        "client_event_id": "mixed-new-1",
                        "type": "item_upsert",
                        "content_hash": second_hash,
                        "item_type": "text",
                        "payload": {"text": "new"},
                        "copy_count_delta": 1
                    }
                ]
            }),
            &[],
        )
        .await;
    assert_eq!(mixed.status, StatusCode::OK, "{:?}", mixed.body);
    let mixed_batch = read_json(&mut socket).await;
    assert_eq!(mixed_batch["type"], "event_batch");
    let events = mixed_batch["events"].as_array().unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(events[0]["content_hash"], second_hash);
}

#[tokio::test]
async fn global_server_seq_interleaving_does_not_advance_other_sync_cursor() {
    let server = TestServer::new().await;
    let first = server.create_sync().await;
    let second = server.create_sync().await;

    let first_push = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&first.device.token),
            upsert_event("first-global", &content_hash("first-global"), 1),
            &[],
        )
        .await;
    assert_eq!(first_push.status, StatusCode::OK, "{:?}", first_push.body);
    let first_seq = first_push.body["data"]["events"][0]["server_seq"]
        .as_i64()
        .unwrap();

    let second_push = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&second.device.token),
            upsert_event("second-global", &content_hash("second-global"), 1),
            &[],
        )
        .await;
    assert_eq!(second_push.status, StatusCode::OK, "{:?}", second_push.body);
    let second_seq = second_push.body["data"]["events"][0]["server_seq"]
        .as_i64()
        .unwrap();
    assert!(second_seq > first_seq);

    let first_pull = server
        .empty(
            Method::GET,
            "/v2/events?after_seq=0&limit=10",
            Some(&first.device.token),
        )
        .await;
    assert_eq!(first_pull.status, StatusCode::OK, "{:?}", first_pull.body);
    assert_eq!(
        first_pull.body["data"]["events"].as_array().unwrap().len(),
        1
    );
    assert_eq!(first_pull.body["data"]["next_cursor"], first_seq);

    let after_first = format!("/v2/events?after_seq={first_seq}&limit=10");
    let no_more = server
        .empty(Method::GET, &after_first, Some(&first.device.token))
        .await;
    assert_eq!(no_more.status, StatusCode::OK, "{:?}", no_more.body);
    assert_eq!(no_more.body["data"]["events"].as_array().unwrap().len(), 0);
    assert_eq!(no_more.body["data"]["next_cursor"], first_seq);
}

async fn connect_with_token(
    url: &str,
    token: &str,
) -> Result<
    (
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        tokio_tungstenite::tungstenite::handshake::client::Response,
    ),
    WsError,
> {
    let mut request = url.into_client_request().expect("websocket request");
    request
        .headers_mut()
        .insert("Authorization", format!("Bearer {token}").parse().unwrap());
    connect_async(request).await
}

fn assert_http_error<T>(result: Result<T, WsError>, status: StatusCode) {
    match result {
        Err(WsError::Http(response)) => assert_eq!(response.status(), status),
        Ok(_) => panic!("expected HTTP {status}, got successful websocket"),
        Err(error) => panic!("expected HTTP {status}, got websocket error {error}"),
    }
}

async fn read_json<S>(socket: &mut S) -> Value
where
    S: StreamExt<Item = Result<Message, WsError>> + Unpin,
{
    match socket.next().await {
        Some(Ok(Message::Text(text))) => {
            serde_json::from_str(&text).expect("json websocket message")
        }
        other => panic!("expected websocket text json, got {other:?}"),
    }
}
