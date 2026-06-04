use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
};

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        State,
    },
    http::{HeaderMap, Uri},
    response::Response,
};
use futures_util::{SinkExt, StreamExt};
use serde::Serialize;
use serde_json::Value;
use sqlx::SqlitePool;
use tokio::sync::{mpsc, Mutex};

use crate::{
    api::AppState,
    auth::{self, DeviceAuth},
    db,
    errors::AppError,
    events::{self, EventOut},
    PROTOCOL_VERSION,
};

const CHANNEL_CAPACITY: usize = 64;

#[derive(Clone, Default)]
pub struct EventHub {
    inner: Arc<HubInner>,
}

#[derive(Default)]
struct HubInner {
    next_subscriber_id: AtomicU64,
    subscribers: Mutex<HashMap<String, HashMap<u64, mpsc::Sender<HubMessage>>>>,
}

#[derive(Clone, Debug)]
enum HubMessage {
    EventBatch(EventBatch),
}

#[derive(Clone, Debug, Serialize)]
pub struct EventBatch {
    #[serde(rename = "type")]
    message_type: &'static str,
    batch_id: String,
    from_seq: i64,
    to_seq: i64,
    events: Vec<EventOut>,
}

#[derive(Serialize)]
struct HelloMessage {
    #[serde(rename = "type")]
    message_type: &'static str,
    protocol_version: u8,
    sync_id: String,
    device_id: String,
    latest_seq: i64,
    cursor: i64,
}

#[derive(Serialize)]
struct CatchupRequiredMessage {
    #[serde(rename = "type")]
    message_type: &'static str,
    after_seq: i64,
    latest_seq: i64,
    reason: &'static str,
}

#[derive(Serialize)]
struct ErrorMessage {
    #[serde(rename = "type")]
    message_type: &'static str,
    code: &'static str,
    message: String,
}

pub(crate) struct Subscription {
    sync_group_id: String,
    subscriber_id: u64,
    receiver: mpsc::Receiver<HubMessage>,
}

impl EventHub {
    pub fn new() -> Self {
        Self::default()
    }

    pub(crate) async fn subscribe(&self, sync_group_id: &str) -> Subscription {
        let subscriber_id = self
            .inner
            .next_subscriber_id
            .fetch_add(1, Ordering::Relaxed)
            .saturating_add(1);
        let (sender, receiver) = mpsc::channel(CHANNEL_CAPACITY);
        let mut subscribers = self.inner.subscribers.lock().await;
        subscribers
            .entry(sync_group_id.to_string())
            .or_default()
            .insert(subscriber_id, sender);
        Subscription {
            sync_group_id: sync_group_id.to_string(),
            subscriber_id,
            receiver,
        }
    }

    pub async fn unsubscribe(&self, sync_group_id: &str, subscriber_id: u64) {
        let mut subscribers = self.inner.subscribers.lock().await;
        if let Some(group) = subscribers.get_mut(sync_group_id) {
            group.remove(&subscriber_id);
            if group.is_empty() {
                subscribers.remove(sync_group_id);
            }
        }
    }

    pub async fn broadcast(&self, sync_group_id: &str, events: Vec<EventOut>) {
        if events.is_empty() {
            return;
        }
        let from_seq = events
            .first()
            .map(|event| event.server_seq)
            .unwrap_or_default();
        let to_seq = events
            .last()
            .map(|event| event.server_seq)
            .unwrap_or(from_seq);
        let batch = EventBatch {
            message_type: "event_batch",
            batch_id: format!("{sync_group_id}:{from_seq}:{to_seq}"),
            from_seq,
            to_seq,
            events,
        };
        let mut subscribers = self.inner.subscribers.lock().await;
        let Some(group) = subscribers.get_mut(sync_group_id) else {
            return;
        };
        let mut overflowed = Vec::new();
        for (subscriber_id, sender) in group.iter() {
            match sender.try_send(HubMessage::EventBatch(batch.clone())) {
                Ok(()) => {}
                Err(mpsc::error::TrySendError::Full(_))
                | Err(mpsc::error::TrySendError::Closed(_)) => {
                    overflowed.push(*subscriber_id);
                }
            }
        }
        for subscriber_id in overflowed {
            group.remove(&subscriber_id);
        }
        if group.is_empty() {
            subscribers.remove(sync_group_id);
        }
    }
}

pub async fn ws_handler(
    State(state): State<AppState>,
    headers: HeaderMap,
    uri: Uri,
    ws: WebSocketUpgrade,
) -> Result<Response, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    let cursor = parse_ws_query(uri.query())?;
    let subscription = state.realtime.subscribe(&auth.sync_group_id).await;
    let latest_seq = events::latest_seq(&state.pool, &auth.sync_group_id).await?;
    Ok(ws.on_upgrade(move |socket| {
        handle_socket(state, auth, cursor, latest_seq, subscription, socket)
    }))
}

fn parse_ws_query(query: Option<&str>) -> Result<i64, AppError> {
    let mut cursor = None;
    let mut protocol_version = None;
    if let Some(query) = query {
        for pair in query.split('&').filter(|pair| !pair.is_empty()) {
            let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
            match key {
                "cursor" => {
                    let parsed = value
                        .parse::<i64>()
                        .map_err(|_| AppError::BadRequest("invalid_cursor"))?;
                    if parsed < 0 {
                        return Err(AppError::BadRequest("invalid_cursor"));
                    }
                    cursor = Some(parsed);
                }
                "protocol_version" => {
                    let parsed = value
                        .parse::<u8>()
                        .map_err(|_| AppError::BadRequest("unsupported_protocol_version"))?;
                    protocol_version = Some(parsed);
                }
                _ => {}
            }
        }
    }
    if protocol_version != Some(PROTOCOL_VERSION) {
        return Err(AppError::BadRequest("unsupported_protocol_version"));
    }
    cursor.ok_or(AppError::BadRequest("invalid_cursor"))
}

async fn handle_socket(
    state: AppState,
    auth: DeviceAuth,
    cursor: i64,
    latest_seq: i64,
    mut subscription: Subscription,
    socket: WebSocket,
) {
    let (mut sender, mut receiver) = socket.split();
    let hello = HelloMessage {
        message_type: "hello",
        protocol_version: PROTOCOL_VERSION,
        sync_id: auth.sync_group_id.clone(),
        device_id: auth.device_id.clone(),
        latest_seq,
        cursor,
    };
    if send_json(&mut sender, &hello).await.is_err() {
        state
            .realtime
            .unsubscribe(&subscription.sync_group_id, subscription.subscriber_id)
            .await;
        return;
    }
    if cursor < latest_seq {
        let catchup = CatchupRequiredMessage {
            message_type: "catchup_required",
            after_seq: cursor,
            latest_seq,
            reason: "cursor_behind",
        };
        if send_json(&mut sender, &catchup).await.is_err() {
            state
                .realtime
                .unsubscribe(&subscription.sync_group_id, subscription.subscriber_id)
                .await;
            return;
        }
    }

    loop {
        tokio::select! {
            inbound = receiver.next() => {
                match inbound {
                    Some(Ok(Message::Text(text))) => {
                        match parse_client_message(&text) {
                            Ok(Some(server_seq)) => {
                                if let Err(error) = ack_server_seq(&state.pool, &auth, server_seq).await {
                                    let _ = send_error(&mut sender, error.code(), error.to_string()).await;
                                }
                            }
                            Ok(None) => {
                                let _ = send_error(&mut sender, "unknown_message", "unknown_message".to_string()).await;
                            }
                            Err(_) => {
                                let _ = send_error(&mut sender, "malformed_json", "malformed_json".to_string()).await;
                                let _ = sender.send(Message::Close(None)).await;
                                break;
                            }
                        }
                    }
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Ok(_)) => {
                        let _ = send_error(&mut sender, "unknown_message", "unknown_message".to_string()).await;
                    }
                    Some(Err(_)) => break,
                }
            }
            hub_message = subscription.receiver.recv() => {
                match hub_message {
                    Some(HubMessage::EventBatch(batch)) => {
                        if send_json(&mut sender, &batch).await.is_err() {
                            break;
                        }
                    }
                    None => {
                        let _ = send_error(&mut sender, "slow_consumer", "slow_consumer".to_string()).await;
                        let _ = sender.send(Message::Close(None)).await;
                        break;
                    }
                }
            }
        }
    }

    state
        .realtime
        .unsubscribe(&subscription.sync_group_id, subscription.subscriber_id)
        .await;
}

async fn send_json<T: Serialize>(
    sender: &mut futures_util::stream::SplitSink<WebSocket, Message>,
    value: &T,
) -> Result<(), axum::Error> {
    let text = serde_json::to_string(value).expect("websocket message serializes");
    sender.send(Message::Text(text)).await
}

async fn send_error(
    sender: &mut futures_util::stream::SplitSink<WebSocket, Message>,
    code: &'static str,
    message: String,
) -> Result<(), axum::Error> {
    send_json(
        sender,
        &ErrorMessage {
            message_type: "error",
            code,
            message,
        },
    )
    .await
}

fn parse_client_message(text: &str) -> Result<Option<i64>, serde_json::Error> {
    let value: Value = serde_json::from_str(text)?;
    if value
        .get("type")
        .and_then(Value::as_str)
        .is_some_and(|message_type| message_type == "ack")
    {
        return Ok(value.get("server_seq").and_then(Value::as_i64));
    }
    Ok(None)
}

async fn ack_server_seq(
    pool: &SqlitePool,
    auth: &DeviceAuth,
    server_seq: i64,
) -> Result<(), AppError> {
    if server_seq < 0 {
        return Err(AppError::BadRequest("invalid_ack"));
    }
    let latest_seq = events::latest_seq(pool, &auth.sync_group_id).await?;
    if server_seq > latest_seq {
        return Err(AppError::BadRequest("future_ack"));
    }
    let now = db::now_ms().await;
    sqlx::query(
        "INSERT INTO device_sync_state(sync_group_id, device_id, last_acked_seq, updated_at_ms)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(sync_group_id, device_id) DO UPDATE SET
            last_acked_seq = MAX(device_sync_state.last_acked_seq, excluded.last_acked_seq),
            updated_at_ms = CASE
                WHEN excluded.last_acked_seq > device_sync_state.last_acked_seq THEN excluded.updated_at_ms
                ELSE device_sync_state.updated_at_ms
            END",
    )
    .bind(&auth.sync_group_id)
    .bind(&auth.device_id)
    .bind(server_seq)
    .bind(now)
    .execute(pool)
    .await?;
    Ok(())
}

#[cfg(test)]
pub async fn last_acked_seq(
    pool: &SqlitePool,
    sync_group_id: &str,
    device_id: &str,
) -> Result<i64, sqlx::Error> {
    use sqlx::Row;

    sqlx::query(
        "SELECT COALESCE(MAX(last_acked_seq), 0) AS last_acked_seq
         FROM device_sync_state
         WHERE sync_group_id = ? AND device_id = ?",
    )
    .bind(sync_group_id)
    .bind(device_id)
    .fetch_one(pool)
    .await
    .map(|row| row.get::<i64, _>("last_acked_seq"))
}
