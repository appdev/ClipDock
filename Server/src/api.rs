use async_trait::async_trait;
use axum::{
    body::{to_bytes, Body},
    extract::{rejection::JsonRejection, FromRequest, Path, Request, State},
    http::{HeaderMap, StatusCode, Uri},
    routing::{any, get, post, put},
    Json, Router,
};
use clipdock_sync_contract::{
    ASSET_DIGEST_ALGORITHM_BLAKE3, ASSET_KINDS, ASSET_KIND_LINK_PREVIEW, ASSET_KIND_SOURCE_ICON,
    ASSET_KIND_THUMBNAIL, CONTENT_HASH_ALGORITHM_BLAKE3, EVENT_TYPES, IMAGE_ASSET_MIME_TYPES,
};
use serde::de::DeserializeOwned;
use serde::Serialize;
use sqlx::SqlitePool;
use tower::ServiceBuilder;

use crate::{
    assets::{AssetStore, UploadAssetResponse, DEFAULT_IMAGE_ASSET_MAX_BYTES, THUMBNAIL_MAX_BYTES},
    auth::{self, CreateSyncRequest, JoinSyncRequest},
    config::Config,
    errors::{ok, AppError, SuccessEnvelope},
    events::{self, PushEventsRequest},
    p2p::{self, ReportEndpointRequest, UpsertAssetProviderRequest},
    realtime::{self, EventHub},
    PROTOCOL_VERSION,
};

struct ApiJson<T>(T);

#[async_trait]
impl<S, T> FromRequest<S> for ApiJson<T>
where
    S: Send + Sync + 'static,
    T: DeserializeOwned + 'static,
{
    type Rejection = AppError;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        match Json::<T>::from_request(req, state).await {
            Ok(Json(value)) => Ok(Self(value)),
            Err(rejection) => Err(json_rejection_to_app_error(rejection)),
        }
    }
}

fn json_rejection_to_app_error(rejection: JsonRejection) -> AppError {
    match rejection {
        JsonRejection::MissingJsonContentType(_) => {
            AppError::UnsupportedMediaType("unsupported_json_content_type")
        }
        JsonRejection::JsonSyntaxError(_) => AppError::BadRequest("malformed_json"),
        JsonRejection::JsonDataError(_) => AppError::BadRequest("invalid_json"),
        JsonRejection::BytesRejection(_) => AppError::BadRequest("invalid_json_body"),
        _ => AppError::BadRequest("invalid_json"),
    }
}

#[derive(Clone)]
pub struct AppState {
    pub pool: SqlitePool,
    pub config: Config,
    pub assets: AssetStore,
    pub realtime: EventHub,
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1", any(protocol_v1_retired))
        .route("/v1/*path", any(protocol_v1_retired))
        .route("/v2/info", get(info))
        .route("/v2/sync/create", post(create_sync))
        .route("/v2/sync/join", post(join_sync))
        .route("/v2/sync/invites", post(create_invite))
        .route("/v2/events", post(push_events).get(pull_events))
        .route("/v2/ws", get(realtime::ws_handler))
        .route("/v2/snapshot", get(snapshot))
        .route("/v2/assets/:digest", put(upload_asset).get(download_asset))
        .route("/v2/p2p/endpoint", put(report_p2p_endpoint))
        .route("/v2/p2p/devices", get(list_p2p_devices))
        .route(
            "/v2/p2p/assets/:asset_id/providers",
            get(list_p2p_asset_providers),
        )
        .route(
            "/v2/p2p/assets/:asset_id/providers/me",
            put(upsert_p2p_asset_provider).delete(delete_p2p_asset_provider),
        )
        .with_state(state)
        .layer(ServiceBuilder::new().layer(axum::extract::DefaultBodyLimit::disable()))
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
}

async fn health() -> Json<SuccessEnvelope<HealthResponse>> {
    ok(HealthResponse { status: "ok" })
}

async fn protocol_v1_retired() -> AppError {
    AppError::UpgradeRequired("protocol_v1_retired")
}

#[derive(Serialize)]
struct InfoResponse {
    protocol_version: u8,
    sync_id: String,
    device_id: String,
    device_name: String,
    event_types: Vec<&'static str>,
    asset_kinds: Vec<&'static str>,
    asset_mime_types: Vec<&'static str>,
    content_hash_algorithms: Vec<&'static str>,
    asset_digest_algorithms: Vec<&'static str>,
    max_asset_bytes: usize,
    thumbnail_max_bytes: usize,
    thumbnail_normal_target_bytes: usize,
    thumbnail_detail_target_bytes: usize,
    asset_max_dimension_px: u32,
    asset_max_pixels: u64,
    per_kind_asset_max_bytes: serde_json::Value,
    p2p: p2p::P2pCapabilities,
}

async fn info(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<SuccessEnvelope<InfoResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(InfoResponse {
        protocol_version: PROTOCOL_VERSION,
        sync_id: auth.sync_group_id,
        device_id: auth.device_id,
        device_name: auth.device_name,
        event_types: EVENT_TYPES.to_vec(),
        asset_kinds: ASSET_KINDS.to_vec(),
        asset_mime_types: IMAGE_ASSET_MIME_TYPES.to_vec(),
        content_hash_algorithms: vec![CONTENT_HASH_ALGORITHM_BLAKE3],
        asset_digest_algorithms: vec![ASSET_DIGEST_ALGORITHM_BLAKE3],
        max_asset_bytes: state.config.max_asset_bytes,
        thumbnail_max_bytes: crate::assets::THUMBNAIL_MAX_BYTES,
        thumbnail_normal_target_bytes: crate::assets::THUMBNAIL_NORMAL_TARGET_BYTES,
        thumbnail_detail_target_bytes: crate::assets::THUMBNAIL_DETAIL_TARGET_BYTES,
        asset_max_dimension_px: crate::assets::ASSET_MAX_DIMENSION_PX,
        asset_max_pixels: crate::assets::ASSET_MAX_PIXELS,
        per_kind_asset_max_bytes: per_kind_asset_max_bytes(&state.assets),
        p2p: p2p::capabilities(),
    }))
}

fn per_kind_asset_max_bytes(assets: &AssetStore) -> serde_json::Value {
    let mut values = serde_json::Map::new();
    values.insert(
        ASSET_KIND_THUMBNAIL.to_string(),
        serde_json::json!(assets.max_bytes_for_kind(ASSET_KIND_THUMBNAIL)),
    );
    values.insert(
        ASSET_KIND_SOURCE_ICON.to_string(),
        serde_json::json!(assets.max_bytes_for_kind(ASSET_KIND_SOURCE_ICON)),
    );
    values.insert(
        ASSET_KIND_LINK_PREVIEW.to_string(),
        serde_json::json!(assets.max_bytes_for_kind(ASSET_KIND_LINK_PREVIEW)),
    );
    serde_json::Value::Object(values)
}

async fn create_sync(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<CreateSyncRequest>,
) -> Result<Json<SuccessEnvelope<auth::CreateSyncResponse>>, AppError> {
    let response = auth::create_sync(&state.pool, request).await?;
    Ok(ok(response))
}

async fn join_sync(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<JoinSyncRequest>,
) -> Result<Json<SuccessEnvelope<auth::JoinSyncResponse>>, AppError> {
    let response = auth::join_sync(&state.pool, request).await?;
    Ok(ok(response))
}

async fn create_invite(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<SuccessEnvelope<auth::CreateInviteResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    let response = auth::create_invite(&state.pool, &auth).await?;
    Ok(ok(response))
}

async fn push_events(
    State(state): State<AppState>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<PushEventsRequest>,
) -> Result<Json<SuccessEnvelope<events::PushEventsResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(events::push_events(
        &state.pool,
        &state.realtime,
        auth,
        request,
    )
    .await?))
}

async fn pull_events(
    State(state): State<AppState>,
    headers: HeaderMap,
    uri: Uri,
) -> Result<Json<SuccessEnvelope<events::PullEventsResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    let (after_seq, limit) = events::parse_event_query(uri.query())?;
    Ok(ok(
        events::pull_events(&state.pool, auth, after_seq, limit).await?
    ))
}

async fn snapshot(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<SuccessEnvelope<events::SnapshotResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(events::snapshot(&state.pool, auth).await?))
}

async fn upload_asset(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(digest): Path<String>,
    body: Body,
) -> Result<(StatusCode, Json<SuccessEnvelope<UploadAssetResponse>>), AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    let kind = headers
        .get("x-clipdock-asset-kind")
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .ok_or(AppError::BadRequest("missing_asset_metadata"))?;
    let cap = match kind {
        ASSET_KIND_THUMBNAIL => state.config.max_asset_bytes.min(THUMBNAIL_MAX_BYTES),
        ASSET_KIND_SOURCE_ICON | ASSET_KIND_LINK_PREVIEW => state
            .config
            .max_asset_bytes
            .min(DEFAULT_IMAGE_ASSET_MAX_BYTES),
        _ => return Err(AppError::BadRequest("unsupported_asset_kind")),
    };
    let bytes = to_bytes(body, cap + 1)
        .await
        .map_err(|_| AppError::PayloadTooLarge("asset_too_large"))?;
    if bytes.len() > cap {
        return Err(AppError::PayloadTooLarge("asset_too_large"));
    }
    let response = state
        .assets
        .upload(&state.pool, auth, digest, &headers, bytes)
        .await?;
    Ok((StatusCode::OK, ok(response)))
}

async fn download_asset(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(digest): Path<String>,
) -> Result<axum::response::Response, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    state.assets.download(&state.pool, auth, digest).await
}

async fn report_p2p_endpoint(
    State(state): State<AppState>,
    headers: HeaderMap,
    ApiJson(request): ApiJson<ReportEndpointRequest>,
) -> Result<Json<SuccessEnvelope<p2p::ReportEndpointResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(p2p::report_endpoint(&state.pool, auth, request).await?))
}

async fn list_p2p_devices(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<SuccessEnvelope<p2p::ListDevicesResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(p2p::list_devices(&state.pool, auth).await?))
}

async fn upsert_p2p_asset_provider(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(asset_id): Path<String>,
    ApiJson(request): ApiJson<UpsertAssetProviderRequest>,
) -> Result<Json<SuccessEnvelope<p2p::UpsertAssetProviderResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(p2p::upsert_asset_provider(
        &state.pool,
        auth,
        asset_id,
        request,
    )
    .await?))
}

async fn delete_p2p_asset_provider(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(asset_id): Path<String>,
) -> Result<Json<SuccessEnvelope<p2p::DeleteAssetProviderResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(
        p2p::delete_asset_provider(&state.pool, auth, asset_id).await?
    ))
}

async fn list_p2p_asset_providers(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(asset_id): Path<String>,
) -> Result<Json<SuccessEnvelope<p2p::ListAssetProvidersResponse>>, AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    Ok(ok(
        p2p::list_asset_providers(&state.pool, auth, asset_id).await?
    ))
}
