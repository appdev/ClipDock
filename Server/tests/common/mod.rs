#![allow(dead_code)]

use axum::{
    body::{to_bytes, Body},
    http::{header, Method, Request, StatusCode},
    Router,
};
use clipdock_sync_server::{
    api::{self, AppState},
    assets::AssetStore,
    config::Config,
    db, migrations,
    realtime::EventHub,
};
use serde_json::{json, Value};
use sqlx::SqlitePool;
use tempfile::TempDir;
use tower::ServiceExt;

pub struct TestServer {
    pub app: Router,
    pub pool: SqlitePool,
    pub assets: AssetStore,
    _temp_dir: TempDir,
}

impl TestServer {
    pub async fn new() -> Self {
        let temp_dir = tempfile::tempdir().expect("create temp dir");
        let config = Config::for_tests(temp_dir.path());
        let pool = db::connect(&config).await.expect("connect test sqlite");
        migrations::migrate(&pool)
            .await
            .expect("migrate test sqlite");
        let assets = AssetStore::new(config.asset_dir.clone(), config.max_asset_bytes)
            .await
            .expect("create asset store");
        let app = api::router(AppState {
            pool: pool.clone(),
            config,
            assets: assets.clone(),
            realtime: EventHub::new(),
        });
        Self {
            app,
            pool,
            assets,
            _temp_dir: temp_dir,
        }
    }

    pub async fn register(&self) -> Device {
        self.create_sync().await.device
    }

    pub async fn create_sync(&self) -> SyncHandle {
        let response = self
            .json(
                Method::POST,
                "/v2/sync/create",
                None,
                json!({"device_name": "test-device"}),
                &[],
            )
            .await;
        assert_eq!(response.status, StatusCode::OK, "{:?}", response.body);
        SyncHandle {
            sync_id: response.body["data"]["sync_id"]
                .as_str()
                .expect("sync id")
                .to_string(),
            pairing_code: response.body["data"]["pairing_code"]
                .as_str()
                .expect("pairing code")
                .to_string(),
            device: Device {
                id: response.body["data"]["device_id"]
                    .as_str()
                    .expect("device id")
                    .to_string(),
                token: response.body["data"]["token"]
                    .as_str()
                    .expect("device token")
                    .to_string(),
            },
        }
    }

    pub async fn join_sync(&self, pairing_code: &str) -> Device {
        let response = self
            .json(
                Method::POST,
                "/v2/sync/join",
                None,
                json!({"pairing_code": pairing_code, "device_name": "joined-device"}),
                &[],
            )
            .await;
        assert_eq!(response.status, StatusCode::OK, "{:?}", response.body);
        Device {
            id: response.body["data"]["device_id"]
                .as_str()
                .expect("device id")
                .to_string(),
            token: response.body["data"]["token"]
                .as_str()
                .expect("device token")
                .to_string(),
        }
    }

    pub async fn json(
        &self,
        method: Method,
        uri: &str,
        token: Option<&str>,
        body: Value,
        extra_headers: &[(&str, &str)],
    ) -> TestResponse {
        let mut builder = Request::builder()
            .method(method)
            .uri(uri)
            .header(header::CONTENT_TYPE, "application/json");
        if let Some(token) = token {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {token}"));
        }
        for (name, value) in extra_headers {
            builder = builder.header(*name, *value);
        }
        let request = builder
            .body(Body::from(body.to_string()))
            .expect("build json request");
        self.send(request).await
    }

    pub async fn empty(&self, method: Method, uri: &str, token: Option<&str>) -> TestResponse {
        let mut builder = Request::builder().method(method).uri(uri);
        if let Some(token) = token {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {token}"));
        }
        self.send(builder.body(Body::empty()).expect("build request"))
            .await
    }

    pub async fn raw(
        &self,
        method: Method,
        uri: &str,
        token: Option<&str>,
        bytes: Vec<u8>,
        extra_headers: &[(&str, &str)],
    ) -> RawResponse {
        let mut builder = Request::builder().method(method).uri(uri);
        if let Some(token) = token {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {token}"));
        }
        for (name, value) in extra_headers {
            builder = builder.header(*name, *value);
        }
        let response = self
            .app
            .clone()
            .oneshot(builder.body(Body::from(bytes)).expect("build raw request"))
            .await
            .expect("send raw request");
        let status = response.status();
        let headers = response.headers().clone();
        let body = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("read body")
            .to_vec();
        RawResponse {
            status,
            headers,
            body,
        }
    }

    async fn send(&self, request: Request<Body>) -> TestResponse {
        let response = self
            .app
            .clone()
            .oneshot(request)
            .await
            .expect("send request");
        let status = response.status();
        let body_bytes = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("read body");
        let body = serde_json::from_slice(&body_bytes).unwrap_or_else(|_| {
            panic!(
                "response body was not json: {}",
                String::from_utf8_lossy(&body_bytes)
            )
        });
        TestResponse { status, body }
    }

    pub async fn spawn_http(&self) -> LiveServer {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind live test server");
        let addr = listener.local_addr().expect("live server addr");
        let app = self.app.clone();
        let handle = tokio::spawn(async move {
            axum::serve(listener, app)
                .await
                .expect("serve live test server");
        });
        LiveServer {
            base_url: format!("http://{addr}"),
            handle,
        }
    }
}

pub struct LiveServer {
    pub base_url: String,
    handle: tokio::task::JoinHandle<()>,
}

impl LiveServer {
    pub fn ws_url(&self, path: &str) -> String {
        format!(
            "ws://{}{}",
            self.base_url.trim_start_matches("http://"),
            path
        )
    }
}

impl Drop for LiveServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

pub struct Device {
    pub id: String,
    pub token: String,
}

pub struct SyncHandle {
    pub sync_id: String,
    pub pairing_code: String,
    pub device: Device,
}

pub struct TestResponse {
    pub status: StatusCode,
    pub body: Value,
}

pub struct RawResponse {
    pub status: StatusCode,
    pub headers: axum::http::HeaderMap,
    pub body: Vec<u8>,
}

pub fn content_hash(label: &str) -> String {
    format!("blake3:{}", blake3::hash(label.as_bytes()).to_hex())
}

pub fn asset_digest(bytes: &[u8]) -> String {
    format!("blake3:{}", blake3::hash(bytes).to_hex())
}

pub fn upsert_event(client_event_id: &str, content_hash: &str, delta: i64) -> Value {
    json!({
        "events": [{
            "client_event_id": client_event_id,
            "type": "item_upsert",
            "content_hash": content_hash,
            "item_type": "text",
            "payload": {"text": content_hash},
            "copy_count_delta": delta
        }]
    })
}

pub fn delete_event(client_event_id: &str, content_hash: &str) -> Value {
    json!({
        "events": [{
            "client_event_id": client_event_id,
            "type": "item_delete",
            "content_hash": content_hash
        }]
    })
}
