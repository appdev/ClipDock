use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
    str::FromStr,
    sync::{Arc, Mutex, OnceLock},
    time::{Duration, Instant},
};

use anyhow::{anyhow, bail, Context, Result};
use iroh::{protocol::Router, Endpoint, NodeAddr, RelayMode, SecretKey};
use iroh_blobs::{
    net_protocol::Blobs,
    rpc::client::blobs::{MemClient, WrapOption},
    store::{fs::Store as FsStore, ExportFormat, ExportMode},
    ticket::BlobTicket,
    util::SetTagOption,
};
use tokio::runtime::Runtime;

type P2PBlobs = Blobs<FsStore>;

static GLOBAL_NODE: OnceLock<Mutex<Option<Arc<ManagedP2PNode>>>> = OnceLock::new();

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct P2PNodeOutcome {
    pub ok: bool,
    pub endpoint_id: String,
    pub relay_url: String,
    pub direct_addresses_json: String,
    pub error_code: String,
    pub message_key: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct P2PProvideOutcome {
    pub ok: bool,
    pub asset_id: String,
    pub blob_hash: String,
    pub blob_ticket: String,
    pub byte_count: i64,
    pub error_code: String,
    pub message_key: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct P2PDownloadOutcome {
    pub ok: bool,
    pub output_path: String,
    pub blob_hash: String,
    pub local_bytes: i64,
    pub downloaded_bytes: i64,
    pub elapsed_ms: i64,
    pub error_code: String,
    pub message_key: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct P2PProbeOutcome {
    pub ok: bool,
    pub reachable: bool,
    pub remote_node_id: String,
    pub path_type: String,
    pub connect_ms: i64,
    pub rtt_ms: i64,
    pub error_code: String,
    pub message_key: String,
}

#[derive(Clone, Debug)]
struct NodeSnapshot {
    endpoint_id: String,
    relay_url: String,
    direct_addresses: Vec<String>,
}

struct ManagedP2PNode {
    app_support_dir: PathBuf,
    runtime: Runtime,
    router: Router,
    _blobs: P2PBlobs,
    client: MemClient,
}

pub fn start_node(app_support_dir: String, timeout_ms: i64) -> P2PNodeOutcome {
    let timeout = timeout_duration(timeout_ms);
    match ensure_global_node(app_support_dir, timeout)
        .and_then(|node| node.snapshot(timeout))
        .map(node_outcome)
    {
        Ok(outcome) => outcome,
        Err(error) => node_error(error),
    }
}

pub fn stop_node(timeout_ms: i64) -> P2PNodeOutcome {
    let timeout = timeout_duration(timeout_ms);
    let node = match take_global_node() {
        Ok(node) => node,
        Err(error) => return node_error(error),
    };
    if let Some(node) = node {
        if let Err(error) = node.shutdown(timeout) {
            return node_error(error);
        }
    }
    P2PNodeOutcome {
        ok: true,
        ..P2PNodeOutcome::default()
    }
}

pub fn provide_file(
    app_support_dir: String,
    file_path: String,
    timeout_ms: i64,
) -> P2PProvideOutcome {
    let timeout = timeout_duration(timeout_ms);
    match ensure_global_node(app_support_dir, timeout).and_then(|node| {
        let path = resolve_existing_file(&node.app_support_dir, &file_path)?;
        node.provide_file(path, timeout)
    }) {
        Ok(outcome) => outcome,
        Err(error) => provide_error(error),
    }
}

pub fn download_file(
    app_support_dir: String,
    blob_ticket: String,
    output_path: String,
    timeout_ms: i64,
) -> P2PDownloadOutcome {
    let timeout = timeout_duration(timeout_ms);
    match ensure_global_node(app_support_dir, timeout).and_then(|node| {
        let output_path = resolve_output_path(&node.app_support_dir, &output_path)?;
        node.download_file(blob_ticket, output_path, timeout)
    }) {
        Ok(outcome) => outcome,
        Err(error) => download_error(error),
    }
}

pub fn probe_ticket(
    app_support_dir: String,
    blob_ticket: String,
    timeout_ms: i64,
) -> P2PProbeOutcome {
    let timeout = timeout_duration(timeout_ms);
    match ensure_global_node(app_support_dir, timeout)
        .and_then(|node| node.probe_ticket(blob_ticket, timeout))
    {
        Ok(outcome) => outcome,
        Err(error) => probe_error(error),
    }
}

fn ensure_global_node(app_support_dir: String, timeout: Duration) -> Result<Arc<ManagedP2PNode>> {
    let app_support_dir = prepare_app_support_dir(app_support_dir)?;
    let existing = {
        let guard = global_node()
            .lock()
            .map_err(|_| anyhow!("p2p global node lock poisoned"))?;
        guard
            .as_ref()
            .filter(|node| node.app_support_dir == app_support_dir)
            .cloned()
    };
    if let Some(node) = existing {
        return Ok(node);
    }

    if let Some(old_node) = take_global_node()? {
        old_node.shutdown(timeout)?;
    }

    let (node, _) = ManagedP2PNode::start(app_support_dir, timeout, true)?;
    let node = Arc::new(node);
    let mut guard = global_node()
        .lock()
        .map_err(|_| anyhow!("p2p global node lock poisoned"))?;
    *guard = Some(node.clone());
    Ok(node)
}

fn take_global_node() -> Result<Option<Arc<ManagedP2PNode>>> {
    let mut guard = global_node()
        .lock()
        .map_err(|_| anyhow!("p2p global node lock poisoned"))?;
    Ok(guard.take())
}

fn global_node() -> &'static Mutex<Option<Arc<ManagedP2PNode>>> {
    GLOBAL_NODE.get_or_init(|| Mutex::new(None))
}

impl ManagedP2PNode {
    fn start(
        app_support_dir: PathBuf,
        timeout: Duration,
        use_default_discovery: bool,
    ) -> Result<(Self, NodeSnapshot)> {
        let blob_dir = app_support_dir.join("p2p-blobs");
        fs::create_dir_all(&blob_dir).with_context(|| {
            format!("failed creating p2p blob directory {}", blob_dir.display())
        })?;
        let secret_key = load_or_create_secret_key(&app_support_dir)?;
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("clipdock-p2p")
            .enable_all()
            .build()
            .context("failed building p2p runtime")?;

        let (router, blobs, client, snapshot) = runtime.block_on(async move {
            let mut endpoint_builder = Endpoint::builder().secret_key(secret_key);
            if use_default_discovery {
                endpoint_builder = endpoint_builder.discovery_n0();
            } else {
                endpoint_builder = endpoint_builder.relay_mode(RelayMode::Disabled);
            }
            let endpoint = endpoint_builder
                .bind()
                .await
                .context("failed binding iroh endpoint")?;
            let blobs = Blobs::persistent(&blob_dir)
                .await
                .context("failed opening iroh blob store")?
                .build(&endpoint);
            let router = Router::builder(endpoint)
                .accept(iroh_blobs::ALPN, blobs.clone())
                .spawn();
            let client = blobs.client().clone();
            let snapshot = snapshot_endpoint(router.endpoint(), timeout).await;
            Ok::<_, anyhow::Error>((router, blobs, client, snapshot))
        })?;

        Ok((
            Self {
                app_support_dir,
                runtime,
                router,
                _blobs: blobs,
                client,
            },
            snapshot,
        ))
    }

    fn snapshot(&self, timeout: Duration) -> Result<NodeSnapshot> {
        let endpoint = self.router.endpoint().clone();
        Ok(self
            .runtime
            .block_on(async move { snapshot_endpoint(&endpoint, timeout).await }))
    }

    fn provide_file(&self, file_path: PathBuf, timeout: Duration) -> Result<P2PProvideOutcome> {
        let endpoint = self.router.endpoint().clone();
        let client = self.client.clone();
        self.runtime.block_on(async move {
            let started = client
                .add_from_path(file_path, false, SetTagOption::Auto, WrapOption::NoWrap)
                .await
                .context("failed starting blob import")?;
            let blob = tokio::time::timeout(timeout, started.finish())
                .await
                .context("blob import timed out")?
                .context("failed importing blob")?;
            let node_addr = node_addr_for_ticket(&endpoint, timeout).await;
            let ticket = BlobTicket::new(node_addr, blob.hash, blob.format)
                .context("failed creating blob ticket")?;
            let hash = blob.hash.to_string();
            Ok(P2PProvideOutcome {
                ok: true,
                asset_id: format!("blake3:{hash}"),
                blob_hash: hash,
                blob_ticket: ticket.to_string(),
                byte_count: u64_to_i64(blob.size),
                error_code: String::new(),
                message_key: String::new(),
            })
        })
    }

    fn download_file(
        &self,
        blob_ticket: String,
        output_path: PathBuf,
        timeout: Duration,
    ) -> Result<P2PDownloadOutcome> {
        let client = self.client.clone();
        self.runtime.block_on(async move {
            let ticket = BlobTicket::from_str(blob_ticket.trim()).context("invalid blob ticket")?;
            if let Some(parent) = output_path.parent() {
                fs::create_dir_all(parent).with_context(|| {
                    format!("failed creating output directory {}", parent.display())
                })?;
            }

            let started_at = Instant::now();
            let download = client
                .download(ticket.hash(), ticket.node_addr().clone())
                .await
                .context("failed starting blob download")?;
            let download_outcome = tokio::time::timeout(timeout, download.finish())
                .await
                .context("blob download timed out")?
                .context("failed downloading blob")?;
            let export = client
                .export(
                    ticket.hash(),
                    output_path.clone(),
                    ExportFormat::Blob,
                    ExportMode::Copy,
                )
                .await
                .context("failed starting blob export")?;
            tokio::time::timeout(timeout, export.finish())
                .await
                .context("blob export timed out")?
                .context("failed exporting blob")?;

            Ok(P2PDownloadOutcome {
                ok: true,
                output_path: output_path.to_string_lossy().into_owned(),
                blob_hash: ticket.hash().to_string(),
                local_bytes: u64_to_i64(download_outcome.local_size),
                downloaded_bytes: u64_to_i64(download_outcome.downloaded_size),
                elapsed_ms: duration_to_i64_ms(started_at.elapsed()),
                error_code: String::new(),
                message_key: String::new(),
            })
        })
    }

    fn probe_ticket(&self, blob_ticket: String, timeout: Duration) -> Result<P2PProbeOutcome> {
        let endpoint = self.router.endpoint().clone();
        self.runtime.block_on(async move {
            let ticket = BlobTicket::from_str(blob_ticket.trim()).context("invalid blob ticket")?;
            let started_at = Instant::now();
            let connection = tokio::time::timeout(
                timeout,
                endpoint.connect(ticket.node_addr().clone(), iroh_blobs::ALPN),
            )
            .await
            .context("p2p probe timed out")?
            .context("p2p probe connect failed")?;
            let stats = connection.stats();
            let remote_node_id = connection
                .remote_node_id()
                .map(|node_id| node_id.to_string())
                .unwrap_or_default();
            let path_type = if ticket.node_addr().relay_url.is_some()
                && ticket.node_addr().direct_addresses.is_empty()
            {
                "relay_or_discovery"
            } else {
                "direct_or_relay"
            };
            connection.close(0u32.into(), b"clipdock probe complete");
            Ok(P2PProbeOutcome {
                ok: true,
                reachable: true,
                remote_node_id,
                path_type: path_type.to_string(),
                connect_ms: duration_to_i64_ms(started_at.elapsed()),
                rtt_ms: duration_to_i64_ms(stats.path.rtt),
                error_code: String::new(),
                message_key: String::new(),
            })
        })
    }

    fn shutdown(&self, timeout: Duration) -> Result<()> {
        let router = self.router.clone();
        self.runtime.block_on(async move {
            tokio::time::timeout(timeout, router.shutdown())
                .await
                .context("p2p shutdown timed out")?
                .context("p2p shutdown failed")
        })
    }
}

fn prepare_app_support_dir(app_support_dir: String) -> Result<PathBuf> {
    let trimmed = app_support_dir.trim();
    if trimmed.is_empty() {
        bail!("missing app support directory");
    }
    let path = PathBuf::from(trimmed);
    fs::create_dir_all(&path)
        .with_context(|| format!("failed creating app support directory {}", path.display()))?;
    path.canonicalize()
        .with_context(|| format!("failed resolving app support directory {}", path.display()))
}

fn load_or_create_secret_key(app_support_dir: &Path) -> Result<SecretKey> {
    let key_path = app_support_dir.join("p2p-node-secret.hex");
    if key_path.exists() {
        let stored = fs::read_to_string(&key_path)
            .with_context(|| format!("failed reading p2p node key {}", key_path.display()))?;
        return SecretKey::from_str(stored.trim())
            .with_context(|| format!("failed parsing p2p node key {}", key_path.display()));
    }

    let secret_key = SecretKey::generate(rand::rngs::OsRng);
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(&key_path)
        .with_context(|| format!("failed creating p2p node key {}", key_path.display()))?;
    file.write_all(secret_key.to_string().as_bytes())
        .with_context(|| format!("failed writing p2p node key {}", key_path.display()))?;
    file.write_all(b"\n")
        .with_context(|| format!("failed finalizing p2p node key {}", key_path.display()))?;
    Ok(secret_key)
}

fn resolve_existing_file(app_support_dir: &Path, file_path: &str) -> Result<PathBuf> {
    let trimmed = file_path.trim();
    if trimmed.is_empty() {
        bail!("missing file path");
    }
    let path = PathBuf::from(trimmed);
    let path = if path.is_absolute() {
        path
    } else {
        app_support_dir.join(path)
    };
    let path = path
        .canonicalize()
        .with_context(|| format!("failed resolving file {}", path.display()))?;
    let metadata = fs::metadata(&path)
        .with_context(|| format!("failed reading file metadata {}", path.display()))?;
    if !metadata.is_file() {
        bail!("p2p provider only supports regular files");
    }
    Ok(path)
}

fn resolve_output_path(app_support_dir: &Path, output_path: &str) -> Result<PathBuf> {
    let trimmed = output_path.trim();
    if trimmed.is_empty() {
        bail!("missing output path");
    }
    let path = PathBuf::from(trimmed);
    if path.is_absolute() {
        Ok(path)
    } else {
        Ok(app_support_dir.join(path))
    }
}

async fn snapshot_endpoint(endpoint: &Endpoint, timeout: Duration) -> NodeSnapshot {
    let endpoint_id = endpoint.node_id().to_string();
    let node_addr = tokio::time::timeout(timeout, endpoint.node_addr())
        .await
        .ok()
        .and_then(Result::ok);
    snapshot_from_node_addr(endpoint_id, node_addr)
}

async fn node_addr_for_ticket(endpoint: &Endpoint, timeout: Duration) -> NodeAddr {
    tokio::time::timeout(timeout, endpoint.node_addr())
        .await
        .ok()
        .and_then(Result::ok)
        .unwrap_or_else(|| endpoint.node_id().into())
}

fn snapshot_from_node_addr(endpoint_id: String, node_addr: Option<NodeAddr>) -> NodeSnapshot {
    let Some(node_addr) = node_addr else {
        return NodeSnapshot {
            endpoint_id,
            relay_url: String::new(),
            direct_addresses: Vec::new(),
        };
    };
    NodeSnapshot {
        endpoint_id,
        relay_url: node_addr
            .relay_url
            .as_ref()
            .map(ToString::to_string)
            .unwrap_or_default(),
        direct_addresses: node_addr
            .direct_addresses
            .iter()
            .map(ToString::to_string)
            .collect(),
    }
}

fn node_outcome(snapshot: NodeSnapshot) -> P2PNodeOutcome {
    P2PNodeOutcome {
        ok: true,
        endpoint_id: snapshot.endpoint_id,
        relay_url: snapshot.relay_url,
        direct_addresses_json: serde_json::to_string(&snapshot.direct_addresses)
            .unwrap_or_else(|_| "[]".to_string()),
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn timeout_duration(timeout_ms: i64) -> Duration {
    if timeout_ms <= 0 {
        Duration::from_secs(10)
    } else {
        Duration::from_millis(timeout_ms as u64)
    }
}

fn duration_to_i64_ms(duration: Duration) -> i64 {
    u64_to_i64(duration.as_millis().min(i64::MAX as u128) as u64)
}

fn u64_to_i64(value: u64) -> i64 {
    value.min(i64::MAX as u64) as i64
}

fn node_error(error: anyhow::Error) -> P2PNodeOutcome {
    P2PNodeOutcome {
        ok: false,
        error_code: "p2p_node_failed".to_string(),
        message_key: p2p_error_message(error),
        ..P2PNodeOutcome::default()
    }
}

fn provide_error(error: anyhow::Error) -> P2PProvideOutcome {
    P2PProvideOutcome {
        ok: false,
        error_code: "p2p_provide_failed".to_string(),
        message_key: p2p_error_message(error),
        ..P2PProvideOutcome::default()
    }
}

fn download_error(error: anyhow::Error) -> P2PDownloadOutcome {
    P2PDownloadOutcome {
        ok: false,
        error_code: "p2p_download_failed".to_string(),
        message_key: p2p_error_message(error),
        ..P2PDownloadOutcome::default()
    }
}

fn probe_error(error: anyhow::Error) -> P2PProbeOutcome {
    P2PProbeOutcome {
        ok: false,
        reachable: false,
        error_code: "p2p_probe_failed".to_string(),
        message_key: p2p_error_message(error),
        ..P2PProbeOutcome::default()
    }
}

fn p2p_error_message(error: anyhow::Error) -> String {
    let message = error.to_string();
    if message.is_empty() {
        "clipboard.error.p2p_failed".to_string()
    } else {
        message
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_nodes_provide_probe_and_download_file() -> Result<()> {
        let provider_root = tempfile::tempdir()?;
        let receiver_root = tempfile::tempdir()?;
        let source_path = provider_root.path().join("source.txt");
        fs::write(&source_path, b"clipdock p2p loopback")?;
        let timeout = Duration::from_secs(10);

        let (provider, _) =
            ManagedP2PNode::start(provider_root.path().to_path_buf(), timeout, false)?;
        let (receiver, _) =
            ManagedP2PNode::start(receiver_root.path().to_path_buf(), timeout, false)?;

        let provided = provider.provide_file(source_path, timeout)?;
        assert!(provided.ok);
        assert!(provided.asset_id.starts_with("blake3:"));
        assert!(provided.blob_ticket.starts_with("blob"));

        let probe = receiver.probe_ticket(provided.blob_ticket.clone(), timeout)?;
        assert!(probe.ok);
        assert!(probe.reachable);
        assert!(!probe.remote_node_id.is_empty());

        let output_path = receiver_root.path().join("downloaded.txt");
        let downloaded =
            receiver.download_file(provided.blob_ticket, output_path.clone(), timeout)?;
        assert!(downloaded.ok);
        assert_eq!(fs::read(&output_path)?, b"clipdock p2p loopback");

        provider.shutdown(timeout)?;
        receiver.shutdown(timeout)?;
        Ok(())
    }

    #[test]
    fn node_id_persists_for_same_app_support_directory() -> Result<()> {
        let app_root = tempfile::tempdir()?;
        let timeout = Duration::from_secs(10);

        let (first, first_snapshot) =
            ManagedP2PNode::start(app_root.path().to_path_buf(), timeout, false)?;
        first.shutdown(timeout)?;

        let (second, second_snapshot) =
            ManagedP2PNode::start(app_root.path().to_path_buf(), timeout, false)?;
        second.shutdown(timeout)?;

        assert_eq!(first_snapshot.endpoint_id, second_snapshot.endpoint_id);
        assert!(app_root.path().join("p2p-node-secret.hex").is_file());
        Ok(())
    }
}
