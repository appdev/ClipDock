use std::{
    path::{Path, PathBuf},
    ptr,
    sync::Mutex,
    time::{Duration, Instant},
};

use anyhow::{anyhow, Context, Result};
use iroh::{protocol::Router, Endpoint, NodeAddr};
use iroh_blobs::{
    net_protocol::Blobs,
    rpc::client::blobs::WrapOption,
    store::{mem, ExportFormat, ExportMode},
    ticket::BlobTicket,
    util::SetTagOption,
};
use jni::{
    objects::{JClass, JString},
    sys::jstring,
    JNIEnv,
};
use once_cell::sync::Lazy;
use serde::{Deserialize, Serialize};
use serde_json::json;
use tokio::runtime::{Builder, Runtime};

static NODE: Lazy<Mutex<Option<P2pNode>>> = Lazy::new(|| Mutex::new(None));

#[derive(Debug, Deserialize)]
struct StartConfig {
    #[serde(default = "default_addr_timeout_ms")]
    addr_timeout_ms: u64,
}

#[derive(Debug, Serialize)]
struct EndpointInfo {
    endpoint_id: String,
    relay_url: Option<String>,
    direct_addresses: Vec<String>,
}

#[derive(Debug, Serialize)]
struct ImportResult {
    asset_id: String,
    ticket: String,
    hash: String,
    format: String,
    byte_count: u64,
    endpoint: EndpointInfo,
}

#[derive(Debug, Serialize)]
struct DownloadResult {
    output_path: String,
    byte_count: u64,
    downloaded_bytes: u64,
    local_bytes: u64,
    elapsed_ms: u128,
}

struct P2pNode {
    runtime: Runtime,
    router: Router,
    blobs: Blobs<mem::Store>,
    addr_timeout: Duration,
}

impl P2pNode {
    fn start(config: StartConfig) -> Result<Self> {
        let runtime = Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("clipdock-p2p")
            .enable_all()
            .build()
            .context("failed to create p2p runtime")?;
        let (router, blobs) = runtime.block_on(async {
            let endpoint = Endpoint::builder()
                .discovery_n0()
                .bind()
                .await
                .context("failed to bind iroh endpoint")?;
            let blobs = Blobs::memory().build(&endpoint);
            let router = Router::builder(endpoint)
                .accept(iroh_blobs::ALPN, blobs.clone())
                .spawn();
            Ok::<_, anyhow::Error>((router, blobs))
        })?;
        Ok(Self {
            runtime,
            router,
            blobs,
            addr_timeout: Duration::from_millis(config.addr_timeout_ms),
        })
    }

    fn endpoint_info(&self) -> Result<EndpointInfo> {
        self.runtime.block_on(async {
            let addr = timed_node_addr(self.router.endpoint(), self.addr_timeout).await;
            Ok(endpoint_info_from_addr(addr))
        })
    }

    fn import_blob(&self, path: PathBuf) -> Result<ImportResult> {
        ensure_readable_file(&path)?;
        let byte_count = std::fs::metadata(&path)
            .with_context(|| format!("failed to read metadata for {}", path.display()))?
            .len();
        self.runtime.block_on(async {
            let blob = self
                .blobs
                .client()
                .add_from_path(path.clone(), true, SetTagOption::Auto, WrapOption::NoWrap)
                .await
                .context("failed to import blob path")?
                .finish()
                .await
                .context("failed to finish blob import")?;
            let node_addr = timed_node_addr(self.router.endpoint(), self.addr_timeout).await;
            let endpoint = endpoint_info_from_addr(node_addr.clone());
            let ticket = BlobTicket::new(node_addr, blob.hash, blob.format)
                .context("failed to create blob ticket")?;
            let hash = blob.hash.to_string();
            Ok(ImportResult {
                asset_id: format!("blake3:{hash}"),
                ticket: ticket.to_string(),
                hash,
                format: format!("{:?}", blob.format).to_lowercase(),
                byte_count,
                endpoint,
            })
        })
    }

    fn download_blob(&self, ticket: &str, output_path: PathBuf) -> Result<DownloadResult> {
        if ticket.trim().is_empty() {
            return Err(anyhow!("empty blob ticket"));
        }
        ensure_parent_dir(&output_path)?;
        let ticket: BlobTicket = ticket.parse().context("failed to parse blob ticket")?;
        let started = Instant::now();
        self.runtime.block_on(async {
            let outcome = self
                .blobs
                .client()
                .download(ticket.hash(), ticket.node_addr().clone())
                .await
                .context("failed to start blob download")?
                .finish()
                .await
                .context("failed to finish blob download")?;
            self.blobs
                .client()
                .export(
                    ticket.hash(),
                    output_path.clone(),
                    ExportFormat::Blob,
                    ExportMode::Copy,
                )
                .await
                .context("failed to start blob export")?
                .finish()
                .await
                .context("failed to finish blob export")?;
            let byte_count = std::fs::metadata(&output_path)
                .with_context(|| {
                    format!("failed to read downloaded file {}", output_path.display())
                })?
                .len();
            Ok(DownloadResult {
                output_path: output_path.to_string_lossy().into_owned(),
                byte_count,
                downloaded_bytes: outcome.downloaded_size,
                local_bytes: outcome.local_size,
                elapsed_ms: started.elapsed().as_millis(),
            })
        })
    }

    fn shutdown(self) -> Result<()> {
        let P2pNode {
            runtime, router, ..
        } = self;
        runtime
            .block_on(async move { router.shutdown().await })
            .context("failed to shutdown iroh router")
    }
}

async fn timed_node_addr(endpoint: &Endpoint, timeout: Duration) -> NodeAddr {
    match tokio::time::timeout(timeout, endpoint.node_addr()).await {
        Ok(Ok(addr)) => addr,
        _ => endpoint.node_id().into(),
    }
}

fn endpoint_info_from_addr(addr: NodeAddr) -> EndpointInfo {
    EndpointInfo {
        endpoint_id: addr.node_id.to_string(),
        relay_url: addr.relay_url.as_ref().map(ToString::to_string),
        direct_addresses: addr
            .direct_addresses
            .iter()
            .map(ToString::to_string)
            .collect(),
    }
}

fn ensure_readable_file(path: &Path) -> Result<()> {
    if !path.is_absolute() {
        return Err(anyhow!("path must be absolute"));
    }
    let metadata = std::fs::metadata(path)
        .with_context(|| format!("failed to read file metadata {}", path.display()))?;
    if !metadata.is_file() {
        return Err(anyhow!("path is not a file"));
    }
    Ok(())
}

fn ensure_parent_dir(path: &Path) -> Result<()> {
    if !path.is_absolute() {
        return Err(anyhow!("output path must be absolute"));
    }
    let parent = path
        .parent()
        .ok_or_else(|| anyhow!("output path has no parent directory"))?;
    std::fs::create_dir_all(parent)
        .with_context(|| format!("failed to create output directory {}", parent.display()))
}

fn default_addr_timeout_ms() -> u64 {
    3_000
}

fn start_node(config_json: &str) -> Result<EndpointInfo> {
    let config = serde_json::from_str::<StartConfig>(config_json).unwrap_or(StartConfig {
        addr_timeout_ms: default_addr_timeout_ms(),
    });
    let mut guard = NODE.lock().map_err(|_| anyhow!("p2p node lock poisoned"))?;
    if guard.is_none() {
        *guard = Some(P2pNode::start(config)?);
    }
    guard
        .as_ref()
        .ok_or_else(|| anyhow!("p2p node unavailable"))?
        .endpoint_info()
}

fn endpoint_info() -> Result<EndpointInfo> {
    let guard = NODE.lock().map_err(|_| anyhow!("p2p node lock poisoned"))?;
    guard
        .as_ref()
        .ok_or_else(|| anyhow!("p2p node is not started"))?
        .endpoint_info()
}

fn import_blob(path: &str) -> Result<ImportResult> {
    let guard = NODE.lock().map_err(|_| anyhow!("p2p node lock poisoned"))?;
    guard
        .as_ref()
        .ok_or_else(|| anyhow!("p2p node is not started"))?
        .import_blob(PathBuf::from(path))
}

fn download_blob(ticket: &str, output_path: &str) -> Result<DownloadResult> {
    let guard = NODE.lock().map_err(|_| anyhow!("p2p node lock poisoned"))?;
    guard
        .as_ref()
        .ok_or_else(|| anyhow!("p2p node is not started"))?
        .download_blob(ticket, PathBuf::from(output_path))
}

fn shutdown_node() -> Result<()> {
    let node = {
        let mut guard = NODE.lock().map_err(|_| anyhow!("p2p node lock poisoned"))?;
        guard.take()
    };
    if let Some(node) = node {
        node.shutdown()?;
    }
    Ok(())
}

fn success_json<T: Serialize>(data: T) -> String {
    json!({
        "ok": true,
        "data": data,
    })
    .to_string()
}

fn error_json(error: anyhow::Error) -> String {
    json!({
        "ok": false,
        "error_code": "p2p_error",
        "message": error.to_string(),
    })
    .to_string()
}

fn response_json<T: Serialize>(result: Result<T>) -> String {
    match result {
        Ok(data) => success_json(data),
        Err(error) => error_json(error),
    }
}

fn env_string(env: &mut JNIEnv, value: JString) -> Result<String> {
    Ok(env
        .get_string(&value)
        .context("failed to read JNI string")?
        .into())
}

fn jni_response(env: &mut JNIEnv, value: String) -> jstring {
    env.new_string(value)
        .map(|output| output.into_raw())
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "system" fn Java_com_apkdv_clipdock_p2p_NativeP2pBridge_nativeStartNode(
    mut env: JNIEnv,
    _class: JClass,
    config_json: JString,
) -> jstring {
    let result = env_string(&mut env, config_json).and_then(|config| start_node(&config));
    jni_response(&mut env, response_json(result))
}

#[no_mangle]
pub extern "system" fn Java_com_apkdv_clipdock_p2p_NativeP2pBridge_nativeEndpointInfo(
    mut env: JNIEnv,
    _class: JClass,
) -> jstring {
    jni_response(&mut env, response_json(endpoint_info()))
}

#[no_mangle]
pub extern "system" fn Java_com_apkdv_clipdock_p2p_NativeP2pBridge_nativeImportBlob(
    mut env: JNIEnv,
    _class: JClass,
    path: JString,
) -> jstring {
    let result = env_string(&mut env, path).and_then(|path| import_blob(&path));
    jni_response(&mut env, response_json(result))
}

#[no_mangle]
pub extern "system" fn Java_com_apkdv_clipdock_p2p_NativeP2pBridge_nativeDownloadBlob(
    mut env: JNIEnv,
    _class: JClass,
    ticket: JString,
    output_path: JString,
) -> jstring {
    let result = env_string(&mut env, ticket).and_then(|ticket| {
        env_string(&mut env, output_path)
            .and_then(|output_path| download_blob(&ticket, &output_path))
    });
    jni_response(&mut env, response_json(result))
}

#[no_mangle]
pub extern "system" fn Java_com_apkdv_clipdock_p2p_NativeP2pBridge_nativeShutdown(
    mut env: JNIEnv,
    _class: JClass,
) -> jstring {
    jni_response(&mut env, response_json(shutdown_node()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loopback_downloads_blob_between_two_nodes() {
        let dir = tempfile::tempdir().expect("tempdir");
        let source_path = dir.path().join("source.bin");
        let output_path = dir.path().join("nested").join("downloaded.bin");
        std::fs::write(&source_path, b"clipdock-p2p-loopback").expect("write source");

        let provider = P2pNode::start(StartConfig {
            addr_timeout_ms: 5_000,
        })
        .expect("provider node");
        let receiver = P2pNode::start(StartConfig {
            addr_timeout_ms: 5_000,
        })
        .expect("receiver node");

        let imported = provider.import_blob(source_path).expect("import blob");
        let downloaded = receiver
            .download_blob(&imported.ticket, output_path.clone())
            .expect("download blob");

        assert_eq!(downloaded.byte_count, 21);
        assert_eq!(
            std::fs::read(output_path).expect("read output"),
            b"clipdock-p2p-loopback"
        );
        assert!(imported.asset_id.starts_with("blake3:"));

        receiver.shutdown().expect("receiver shutdown");
        provider.shutdown().expect("provider shutdown");
    }

    #[test]
    fn rejects_relative_paths() {
        let node = P2pNode::start(StartConfig {
            addr_timeout_ms: 1_000,
        })
        .expect("node");
        let error = node
            .import_blob(PathBuf::from("relative-file"))
            .unwrap_err();
        assert!(error.to_string().contains("path must be absolute"));
        node.shutdown().expect("shutdown");
    }
}
