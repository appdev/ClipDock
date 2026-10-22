//! Filesystem-only managed assets. Database decisions belong to clipboard_core.
//! A reservation lease may span asynchronous work; the lifecycle guard must not.
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

#[cfg(unix)]
mod unix;
#[cfg(unix)]
use unix::Directory;
#[cfg(not(unix))]
mod unsupported;
#[cfg(not(unix))]
use unsupported::Directory;

const RESERVATIONS: &str = ".asset-reservations";
pub const MAX_ENCODED_ASSET_BYTES: usize = 256 * 1024 * 1024;
#[cfg(test)]
thread_local! {
    static FAIL_EXISTING_MANIFEST_SAVE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
    static STAGE_AFTER_CREATE: std::cell::RefCell<Option<Box<dyn FnOnce()>>> = const { std::cell::RefCell::new(None) };
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AssetReservation {
    pub reservation_id: String,
    pub relative_path: String,
    pub staged_relative_path: String,
    pub byte_count: u64,
    pub content_hash: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    version: u8,
    asset: AssetReservation,
    existing: bool,
}

struct Lease {
    _file: File,
}
type LeaseKey = (PathBuf, String);
fn leases() -> &'static Mutex<HashMap<LeaseKey, Arc<Lease>>> {
    static LEASES: OnceLock<Mutex<HashMap<LeaseKey, Arc<Lease>>>> = OnceLock::new();
    LEASES.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(Clone)]
pub struct AssetStore {
    directory: Arc<Directory>,
    root: PathBuf,
}
pub struct AssetLifecycleGuard {
    store: AssetStore,
    _lock: File,
}

fn invalid(message: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, message.into())
}
fn poisoned() -> io::Error {
    io::Error::other("asset reservation registry poisoned")
}
fn manifest_path(id: &str) -> String {
    format!("{RESERVATIONS}/{id}.json")
}
fn lease_path(id: &str) -> String {
    format!("{RESERVATIONS}/{id}.lease")
}
fn new_id() -> String {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    blake3::hash(
        format!(
            "{}:{now}:{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        )
        .as_bytes(),
    )
    .to_hex()[..32]
        .to_owned()
}

/// Strict DB-form paths. External captured file paths never enter this service.
pub fn validate_relative_path(path: &str) -> io::Result<()> {
    validate_components(path)?;
    if !matches!(
        path.split('/').next(),
        Some("assets" | "thumbnails" | "app-icons" | "staging" | ".staging")
    ) {
        return Err(invalid("asset path is outside managed directories"));
    }
    Ok(())
}
fn validate_components(path: &str) -> io::Result<()> {
    if path.contains(['\\', ':', '\0'])
        || path
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
        || !path.contains('/')
    {
        return Err(invalid(
            "asset path must contain only normal relative components",
        ));
    }
    Ok(())
}

impl AssetStore {
    pub fn open(root: impl AsRef<Path>) -> io::Result<Self> {
        let directory = Directory::open(root.as_ref())?;
        let root = root.as_ref().canonicalize()?;
        Ok(Self {
            directory: Arc::new(directory),
            root,
        })
    }
    pub fn root(&self) -> &Path {
        &self.root
    }
    /// Fallback when storage cannot be opened: abandon ownership without
    /// deleting evidence. A later maintenance pass must consult the database.
    pub fn abandon_owned_paths(&self, paths: &[String]) -> io::Result<()> {
        self.lock_lifecycle()?.release_owned_for_paths(paths)?;
        Ok(())
    }
    pub fn lock_lifecycle(&self) -> io::Result<AssetLifecycleGuard> {
        let lock = self.directory.open_lock(".asset-lifecycle.lock")?;
        lock.lock()?;
        Ok(AssetLifecycleGuard {
            store: self.clone(),
            _lock: lock,
        })
    }
    pub fn reserve(
        &self,
        final_relative_path: &str,
        staged_relative_path: Option<&str>,
    ) -> io::Result<AssetReservation> {
        let guard = self.lock_lifecycle()?;
        guard.reserve(final_relative_path, staged_relative_path, false)
    }
    pub fn reserve_existing(&self, relative_path: &str) -> io::Result<AssetReservation> {
        let guard = self.lock_lifecycle()?;
        let receipt = guard.reserve(relative_path, None, true)?;
        drop(guard);
        let result = (|| {
            // The lease protects this bounded streaming read without root lock.
            let mut file = self.directory.read(relative_path)?;
            if file.metadata()?.len() > MAX_ENCODED_ASSET_BYTES as u64 {
                return Err(invalid("asset exceeds read budget"));
            }
            let mut digest = blake3::Hasher::new();
            let mut buffer = [0; 64 * 1024];
            let mut count = 0u64;
            loop {
                let size = file.read(&mut buffer)?;
                if size == 0 {
                    break;
                }
                count += size as u64;
                if count > MAX_ENCODED_ASSET_BYTES as u64 {
                    return Err(invalid("asset exceeds read budget"));
                }
                digest.update(&buffer[..size]);
            }
            let mut updated = receipt.clone();
            updated.byte_count = count;
            updated.content_hash = Some(digest.finalize().to_hex().to_string());
            let guard = self.lock_lifecycle()?;
            guard.require_owned(&receipt.reservation_id)?;
            let mut manifest = guard.matching_manifest(&updated)?;
            manifest.asset = updated.clone();
            guard.save_manifest(&manifest)?;
            Ok(updated)
        })();
        if result.is_err() {
            // Every failure after reserve releases exactly this claim, even if
            // reacquiring the filesystem guard itself is what failed.
            leases()
                .lock()
                .map_err(|_| poisoned())?
                .remove(&(self.root.clone(), receipt.reservation_id.clone()));
            if let Ok(guard) = self.lock_lifecycle() {
                let _ = guard.forget_inactive_reservation(&receipt);
            }
        }
        result
    }
    pub fn stage_encoded(
        &self,
        final_relative_path: &str,
        staged_relative_path: Option<&str>,
        bytes: &[u8],
    ) -> io::Result<AssetReservation> {
        let receipt = self.reserve(final_relative_path, staged_relative_path)?;
        let result = self.stage_reserved(&receipt, bytes);
        if result.is_err() {
            // This convenience call cannot return the receipt on failure. Keep
            // evidence but never strand an inaccessible live lease.
            leases()
                .lock()
                .map_err(|_| poisoned())?
                .remove(&(self.root.clone(), receipt.reservation_id));
        }
        result
    }
    pub fn stage_reserved(
        &self,
        receipt: &AssetReservation,
        bytes: &[u8],
    ) -> io::Result<AssetReservation> {
        if bytes.is_empty() || bytes.len() > MAX_ENCODED_ASSET_BYTES {
            return Err(invalid("encoded asset is empty or exceeds byte budget"));
        }
        let guard = self.lock_lifecycle()?;
        let mut manifest = guard.matching_manifest(receipt)?;
        if manifest.existing {
            return Err(invalid("an existing reservation is immutable"));
        }
        let lease = leases()
            .lock()
            .map_err(|_| poisoned())?
            .get(&(self.root.clone(), receipt.reservation_id.clone()))
            .cloned()
            .ok_or_else(|| invalid("reservation is no longer owned by this process"))?;
        let mut file = self
            .directory
            .create_new(&manifest.asset.staged_relative_path)?;
        drop(guard);
        #[cfg(test)]
        STAGE_AFTER_CREATE.with(|slot| {
            if let Some(hook) = slot.borrow_mut().take() {
                hook();
            }
        });
        // No database/lifecycle lock during potentially large writes or hashing.
        file.write_all(bytes)?;
        file.sync_all()?;
        manifest.asset.byte_count = bytes.len() as u64;
        manifest.asset.content_hash = Some(blake3::hash(bytes).to_hex().to_string());
        let guard = self.lock_lifecycle()?;
        if !leases()
            .lock()
            .map_err(|_| poisoned())?
            .contains_key(&(self.root.clone(), receipt.reservation_id.clone()))
        {
            return Err(io::Error::new(
                io::ErrorKind::Interrupted,
                "reservation released while writing",
            ));
        }
        guard.save_manifest(&manifest)?;
        drop(lease);
        Ok(manifest.asset)
    }
    pub fn publish(&self, receipt: &AssetReservation) -> io::Result<AssetReservation> {
        let guard = self.lock_lifecycle()?;
        guard.require_owned(&receipt.reservation_id)?;
        let manifest = guard.matching_manifest(receipt)?;
        if manifest.asset.byte_count == 0 || manifest.asset.content_hash.is_none() {
            return Err(invalid("reservation has no completed encoded asset"));
        }
        if !manifest.existing {
            guard.rename(
                &manifest.asset.staged_relative_path,
                &manifest.asset.relative_path,
            )?;
        }
        Ok(manifest.asset)
    }
    pub fn read_bounded(&self, relative_path: &str, limit: usize) -> io::Result<Vec<u8>> {
        validate_relative_path(relative_path)?;
        let file = self.directory.read(relative_path)?;
        if file.metadata()?.len() > limit as u64 {
            return Err(invalid("asset exceeds read budget"));
        }
        let mut data = Vec::new();
        file.take(limit.saturating_add(1) as u64)
            .read_to_end(&mut data)?;
        if data.len() > limit {
            return Err(invalid("asset exceeds read budget"));
        }
        Ok(data)
    }
}

impl AssetLifecycleGuard {
    fn require_owned(&self, id: &str) -> io::Result<()> {
        if !leases()
            .lock()
            .map_err(|_| poisoned())?
            .contains_key(&(self.store.root.clone(), id.to_owned()))
        {
            return Err(invalid("reservation is no longer owned by this process"));
        }
        Ok(())
    }
    fn reserve(
        &self,
        final_path: &str,
        staged_path: Option<&str>,
        existing: bool,
    ) -> io::Result<AssetReservation> {
        validate_relative_path(final_path)?;
        let id = new_id();
        let staged_path = staged_path
            .map(str::to_owned)
            .unwrap_or_else(|| format!(".staging/reservations/{id}.part"));
        validate_relative_path(&staged_path)?;
        if !(staged_path.starts_with("staging/") || staged_path.starts_with(".staging/"))
            || staged_path == final_path
        {
            return Err(invalid("staged asset must use a distinct staging path"));
        }
        if existing {
            self.store.directory.read(final_path)?;
        } else if self.exists(final_path)? {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "final asset already exists",
            ));
        }
        if self.exists(&staged_path)? {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "staged asset already exists",
            ));
        }
        if !existing
            && self.manifests()?.iter().any(|m| {
                m.asset.relative_path == final_path || m.asset.staged_relative_path == staged_path
            })
        {
            return Err(io::Error::new(
                io::ErrorKind::AlreadyExists,
                "asset path already reserved",
            ));
        }
        let lease_file = self.store.directory.create_new(&lease_path(&id))?;
        lease_file.lock()?;
        let asset = AssetReservation {
            reservation_id: id.clone(),
            relative_path: final_path.into(),
            staged_relative_path: staged_path,
            byte_count: 0,
            content_hash: None,
        };
        self.save_manifest(&Manifest {
            version: 1,
            asset: asset.clone(),
            existing,
        })?;
        leases().lock().map_err(|_| poisoned())?.insert(
            (self.store.root.clone(), id),
            Arc::new(Lease { _file: lease_file }),
        );
        Ok(asset)
    }
    fn save_manifest(&self, manifest: &Manifest) -> io::Result<()> {
        #[cfg(test)]
        if manifest.existing
            && manifest.asset.content_hash.is_some()
            && FAIL_EXISTING_MANIFEST_SAVE.with(|flag| flag.replace(false))
        {
            return Err(io::Error::other("injected manifest-save failure"));
        }
        let path = manifest_path(&manifest.asset.reservation_id);
        let temporary = format!("{RESERVATIONS}/{}.tmp", new_id());
        let mut file = self.store.directory.create_new(&temporary)?;
        file.write_all(&serde_json::to_vec(manifest)?)?;
        file.sync_all()?;
        self.store.directory.replace(&temporary, &path)
    }
    fn matching_manifest(&self, receipt: &AssetReservation) -> io::Result<Manifest> {
        if receipt.reservation_id.len() != 32
            || !receipt
                .reservation_id
                .bytes()
                .all(|b| b.is_ascii_hexdigit())
        {
            return Err(invalid("invalid reservation ID"));
        }
        let manifest: Manifest = serde_json::from_reader(
            self.store
                .directory
                .read(&manifest_path(&receipt.reservation_id))?,
        )?;
        if manifest.version != 1
            || manifest.asset.relative_path != receipt.relative_path
            || manifest.asset.staged_relative_path != receipt.staged_relative_path
        {
            return Err(invalid("reservation identity mismatch"));
        }
        Ok(manifest)
    }
    fn manifests(&self) -> io::Result<Vec<Manifest>> {
        let mut result = Vec::new();
        for path in self.store.directory.files(RESERVATIONS)? {
            if path.ends_with(".json") {
                let manifest: Manifest =
                    serde_json::from_reader(self.store.directory.read(&path)?)?;
                if manifest.version != 1 {
                    return Err(invalid("unsupported reservation manifest"));
                }
                validate_relative_path(&manifest.asset.relative_path)?;
                validate_relative_path(&manifest.asset.staged_relative_path)?;
                result.push(manifest);
            }
        }
        Ok(result)
    }
    pub fn reservations(&self) -> io::Result<Vec<AssetReservation>> {
        Ok(self.manifests()?.into_iter().map(|m| m.asset).collect())
    }
    pub fn reservation_is_active(&self, receipt: &AssetReservation) -> io::Result<bool> {
        let file = self
            .store
            .directory
            .read_write(&lease_path(&receipt.reservation_id))?;
        match file.try_lock() {
            Ok(()) => Ok(false),
            Err(std::fs::TryLockError::WouldBlock) => Ok(true),
            Err(std::fs::TryLockError::Error(error)) => Err(error),
        }
    }
    /// Release one owned claim per requested asset (shared existing icons may
    /// have several independent claims). Does not delete any asset or manifest.
    pub fn release_owned_for_paths(&self, paths: &[String]) -> io::Result<Vec<AssetReservation>> {
        let all = self.reservations()?;
        let mut remaining = paths.iter().collect::<HashSet<_>>();
        let mut registry = leases().lock().map_err(|_| poisoned())?;
        let mut released = Vec::new();
        for receipt in all {
            let key = (self.store.root.clone(), receipt.reservation_id.clone());
            if !registry.contains_key(&key) {
                continue;
            }
            if remaining.contains(&receipt.relative_path)
                || remaining.contains(&receipt.staged_relative_path)
            {
                remaining.remove(&receipt.relative_path);
                remaining.remove(&receipt.staged_relative_path);
                registry.remove(&key);
                released.push(receipt);
            }
        }
        Ok(released)
    }
    pub fn forget_inactive_reservation(&self, receipt: &AssetReservation) -> io::Result<()> {
        if self.reservation_is_active(receipt)? {
            return Err(io::Error::new(
                io::ErrorKind::WouldBlock,
                "asset writer is still active",
            ));
        }
        self.store
            .directory
            .delete(&manifest_path(&receipt.reservation_id))?;
        self.store
            .directory
            .delete(&lease_path(&receipt.reservation_id))?;
        Ok(())
    }
    /// Remove only lock/temporary metadata with no manifest or active owner.
    /// The root lock ensures reserve/save cannot be midway through publication.
    pub fn cleanup_abandoned_metadata(&self) -> io::Result<()> {
        for path in self.store.directory.files(RESERVATIONS)? {
            if path.ends_with(".tmp") {
                self.store.directory.delete(&path)?;
            } else if let Some(id) = path
                .strip_prefix(&format!("{RESERVATIONS}/"))
                .and_then(|p| p.strip_suffix(".lease"))
            {
                match self.store.directory.read(&manifest_path(id)) {
                    Ok(_) => continue,
                    Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error),
                }
                let file = self.store.directory.read_write(&path)?;
                match file.try_lock() {
                    Ok(()) => {
                        self.store.directory.delete(&path)?;
                    }
                    Err(std::fs::TryLockError::WouldBlock) => {}
                    Err(std::fs::TryLockError::Error(error)) => return Err(error),
                }
            }
        }
        Ok(())
    }
    pub fn read(&self, path: &str) -> io::Result<File> {
        validate_relative_path(path)?;
        self.store.directory.read(path)
    }
    pub fn require_completed_if_reserved(&self, path: &str) -> io::Result<()> {
        for manifest in self.manifests()? {
            if !manifest.existing
                && (manifest.asset.relative_path == path
                    || manifest.asset.staged_relative_path == path)
                && (manifest.asset.byte_count == 0 || manifest.asset.content_hash.is_none())
            {
                return Err(invalid("reserved asset has not finished staging"));
            }
        }
        Ok(())
    }
    pub fn exists(&self, path: &str) -> io::Result<bool> {
        match self.read(path) {
            Ok(_) => Ok(true),
            Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(false),
            Err(e) => Err(e),
        }
    }
    pub fn rename(&self, from: &str, to: &str) -> io::Result<()> {
        validate_relative_path(from)?;
        validate_relative_path(to)?;
        self.store.directory.rename(from, to)
    }
    pub fn delete(&self, path: &str) -> io::Result<Option<u64>> {
        validate_relative_path(path)?;
        self.store.directory.delete(path)
    }
    pub fn managed_files(&self) -> io::Result<Vec<String>> {
        let mut files = Vec::new();
        for directory in ["assets", "thumbnails", "app-icons", "staging", ".staging"] {
            files.extend(self.store.directory.files(directory)?);
        }
        Ok(files)
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    #[test]
    fn completed_staging_is_required_and_publish_never_replaces() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let reserved = store
            .reserve("assets/test.bin", Some(".staging/test.bin"))
            .unwrap();
        assert!(store.publish(&reserved).is_err());
        let ready = store.stage_reserved(&reserved, b"lossless bytes").unwrap();
        assert_eq!(ready.byte_count, 14);
        assert_eq!(
            ready.content_hash.as_deref(),
            Some(blake3::hash(b"lossless bytes").to_hex().as_str())
        );
        store.publish(&reserved).unwrap(); // Metadata comes from the authority.
        assert_eq!(
            std::fs::read(root.path().join("assets/test.bin")).unwrap(),
            b"lossless bytes"
        );
        assert!(store.reserve("assets/test.bin", None).is_err());
        assert!(store.publish(&ready).is_err());
    }

    #[test]
    fn independent_existing_claims_are_settled_one_at_a_time() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let receipt = store
            .stage_encoded("app-icons/icon.png", None, b"icon")
            .unwrap();
        store.publish(&receipt).unwrap();
        let second = store.reserve_existing("app-icons/icon.png").unwrap();
        let guard = store.lock_lifecycle().unwrap();
        let released = guard
            .release_owned_for_paths(&[receipt.relative_path.clone()])
            .unwrap();
        assert_eq!(released.len(), 1);
        let active = guard
            .reservations()
            .unwrap()
            .iter()
            .filter(|r| guard.reservation_is_active(r).unwrap())
            .count();
        assert_eq!(active, 1);
        drop(guard);
        // Either claim may be consumed first; a later registration remains protected.
        assert_ne!(receipt.reservation_id, second.reservation_id);
    }

    #[test]
    fn late_publish_after_cleanup_cannot_resurrect_a_claim() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let receipt = store
            .stage_encoded("assets/late.png", None, b"png")
            .unwrap();
        let guard = store.lock_lifecycle().unwrap();
        guard
            .release_owned_for_paths(&[receipt.relative_path.clone()])
            .unwrap();
        drop(guard); // Manifest intentionally remains as recovery evidence.
        assert!(store.publish(&receipt).is_err());
        assert!(store.stage_reserved(&receipt, b"replacement").is_err());
        assert!(!root.path().join("assets/late.png").exists());
    }

    #[test]
    fn oversized_existing_file_releases_only_its_own_claim() {
        let root = tempfile::tempdir().unwrap();
        std::fs::create_dir(root.path().join("assets")).unwrap();
        let path = root.path().join("assets/oversized.bin");
        File::create(&path)
            .unwrap()
            .set_len(MAX_ENCODED_ASSET_BYTES as u64 + 1)
            .unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        assert!(store.reserve_existing("assets/oversized.bin").is_err());
        assert!(store
            .lock_lifecycle()
            .unwrap()
            .reservations()
            .unwrap()
            .is_empty());
        assert!(path.exists());
    }

    #[test]
    fn final_existing_manifest_failure_releases_only_the_failed_claim() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let original = store
            .stage_encoded("app-icons/shared.png", None, b"icon")
            .unwrap();
        store.publish(&original).unwrap();
        FAIL_EXISTING_MANIFEST_SAVE.with(|flag| flag.set(true));
        assert!(store.reserve_existing(&original.relative_path).is_err());
        let guard = store.lock_lifecycle().unwrap();
        assert_eq!(guard.reservations().unwrap().len(), 1);
        assert!(guard.reservation_is_active(&original).unwrap());
        assert!(root.path().join(&original.relative_path).exists());
    }

    #[test]
    fn controlled_operations_reject_symlink_parents_and_leaves() {
        let root = tempfile::tempdir().unwrap();
        let outside = tempfile::tempdir().unwrap();
        std::fs::write(outside.path().join("valuable"), b"unchanged").unwrap();
        std::fs::create_dir(root.path().join("assets")).unwrap();
        symlink(outside.path(), root.path().join("assets/escape")).unwrap();
        symlink(
            outside.path().join("valuable"),
            root.path().join("assets/link"),
        )
        .unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        assert!(store.reserve("assets/escape/new", None).is_err());
        assert!(store.reserve_existing("assets/link").is_err());
        let guard = store.lock_lifecycle().unwrap();
        assert!(guard.delete("assets/escape/valuable").is_err());
        assert!(guard.delete("assets/link").is_err());
        assert_eq!(
            std::fs::read(outside.path().join("valuable")).unwrap(),
            b"unchanged"
        );
        assert!(guard.managed_files().unwrap().is_empty());
    }

    #[test]
    fn two_instances_serialize_lifecycle_without_holding_it_for_reservations() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let receipt = store.reserve("assets/later", None).unwrap();
        let guard = store.lock_lifecycle().unwrap();
        let other = AssetStore::open(root.path()).unwrap();
        let (sender, receiver) = std::sync::mpsc::channel();
        let thread = std::thread::spawn(move || {
            let guard = other.lock_lifecycle().unwrap();
            sender
                .send(guard.reservation_is_active(&receipt).unwrap())
                .unwrap();
        });
        assert!(receiver
            .recv_timeout(std::time::Duration::from_millis(30))
            .is_err());
        drop(guard);
        assert!(receiver
            .recv_timeout(std::time::Duration::from_secs(2))
            .unwrap());
        thread.join().unwrap();
    }

    #[test]
    fn lifecycle_file_lock_is_observed_by_another_process() {
        const KEY: &str = "CLIPDOCK_ASSET_LOCK_TEST_ROOT";
        if let Some(root) = std::env::var_os(KEY) {
            let file = std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(Path::new(&root).join(".asset-lifecycle.lock"))
                .unwrap();
            assert!(matches!(
                file.try_lock(),
                Err(std::fs::TryLockError::WouldBlock)
            ));
            return;
        }
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let _guard = store.lock_lifecycle().unwrap();
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "tests::lifecycle_file_lock_is_observed_by_another_process",
            ])
            .env(KEY, root.path())
            .status()
            .unwrap();
        assert!(status.success());
    }

    #[test]
    fn partial_staging_cannot_publish_and_cancellation_retains_evidence_until_writer_exits() {
        let root = tempfile::tempdir().unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let receipt = store.reserve("assets/partial.png", None).unwrap();
        let worker_store = store.clone();
        let worker_receipt = receipt.clone();
        let (ready_tx, ready_rx) = std::sync::mpsc::channel();
        let (resume_tx, resume_rx) = std::sync::mpsc::channel();
        let worker = std::thread::spawn(move || {
            STAGE_AFTER_CREATE.with(|slot| {
                *slot.borrow_mut() = Some(Box::new(move || {
                    ready_tx.send(()).unwrap();
                    resume_rx.recv().unwrap();
                }))
            });
            worker_store.stage_reserved(&worker_receipt, b"encoded bytes")
        });
        ready_rx
            .recv_timeout(std::time::Duration::from_secs(2))
            .unwrap();
        assert!(store.publish(&receipt).is_err());
        store
            .abandon_owned_paths(&[receipt.relative_path.clone()])
            .unwrap();
        assert!(store
            .lock_lifecycle()
            .unwrap()
            .reservation_is_active(&receipt)
            .unwrap());
        resume_tx.send(()).unwrap();
        assert!(worker.join().unwrap().is_err());
        assert!(!store
            .lock_lifecycle()
            .unwrap()
            .reservation_is_active(&receipt)
            .unwrap());
        assert!(!root.path().join(&receipt.relative_path).exists());
    }
}
