use async_trait::async_trait;
use axum::{
    body::Bytes,
    extract::{rejection::JsonRejection, FromRequest, Path, Request, State},
    http::{HeaderMap, StatusCode, Uri},
    routing::{get, post, put},
    Json, Router,
};
use serde::de::DeserializeOwned;
use serde::Serialize;
use sqlx::SqlitePool;
use tower::ServiceBuilder;

use crate::{
    assets::{AssetStore, UploadAssetResponse},
    auth::{self, CreateSyncRequest, JoinSyncRequest},
    config::Config,
    errors::{ok, AppError, SuccessEnvelope},
    events::{self, PushEventsRequest},
    p2p::{self, ReportEndpointRequest, UpsertAssetProviderRequest},
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
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/info", get(info))
        .route("/v1/sync/create", post(create_sync))
        .route("/v1/sync/join", post(join_sync))
        .route("/v1/sync/invites", post(create_invite))
        .route("/v1/events", post(push_events).get(pull_events))
        .route("/v1/snapshot", get(snapshot))
        .route("/v1/assets/:digest", put(upload_asset).get(download_asset))
        .route("/v1/p2p/endpoint", put(report_p2p_endpoint))
        .route("/v1/p2p/devices", get(list_p2p_devices))
        .route(
            "/v1/p2p/assets/:asset_id/providers",
            get(list_p2p_asset_providers),
        )
        .route(
            "/v1/p2p/assets/:asset_id/providers/me",
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

#[derive(Serialize)]
struct InfoResponse {
    protocol_version: u8,
    sync_id: String,
    device_id: String,
    device_name: String,
    event_types: Vec<&'static str>,
    asset_kinds: Vec<&'static str>,
    asset_mime_types: Vec<&'static str>,
    max_asset_bytes: usize,
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
        event_types: vec!["item_upsert", "item_delete"],
        asset_kinds: vec!["thumbnail", "source_icon", "link_preview"],
        asset_mime_types: vec!["image/png", "image/jpeg", "image/webp"],
        max_asset_bytes: state.config.max_asset_bytes,
        p2p: p2p::capabilities(),
    }))
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
    Ok(ok(events::push_events(&state.pool, auth, request).await?))
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
    body: Bytes,
) -> Result<(StatusCode, Json<SuccessEnvelope<UploadAssetResponse>>), AppError> {
    let auth = auth::require_device(&state.pool, &headers).await?;
    let response = state
        .assets
        .upload(&state.pool, auth, digest, &headers, body)
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
