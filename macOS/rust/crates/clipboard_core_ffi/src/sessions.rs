//! Process-local connections. The registry never holds its lock while SQLite runs.
use clipboard_core::{ClipboardCore, CoreError, CoreErrorCode, Result, DATABASE_FILE_NAME};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Condvar, Mutex, OnceLock};

const MAX_SESSIONS: usize = 8;

#[cfg(test)]
thread_local! {
    static SESSION_ACCESS_COUNT: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

#[cfg(test)]
pub(super) fn session_access_count() -> usize {
    SESSION_ACCESS_COUNT.with(std::cell::Cell::get)
}

#[derive(PartialEq, Eq)]
struct FileIdentity {
    #[cfg(unix)]
    device: u64,
    #[cfg(unix)]
    inode: u64,
    #[cfg(not(unix))]
    created: Option<std::time::SystemTime>,
}

impl FileIdentity {
    fn read(path: &Path) -> Result<Option<Self>> {
        let metadata = match fs::metadata(path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            Ok(Some(Self {
                device: metadata.dev(),
                inode: metadata.ino(),
            }))
        }
        #[cfg(not(unix))]
        Ok(Some(Self {
            created: metadata.created().ok(),
        }))
    }
}

struct Session {
    core: ClipboardCore,
    identity: FileIdentity,
    schema: (i64, i64),
}

struct Entry {
    session: Arc<Mutex<Option<Session>>>,
    last_used: u64,
}

#[derive(Default)]
struct Registry {
    entries: HashMap<PathBuf, Entry>,
    clock: u64,
}

struct SessionCache {
    registry: Mutex<Registry>,
    available: Condvar,
    capacity: usize,
    #[cfg(test)]
    open_count: std::sync::atomic::AtomicUsize,
    #[cfg(test)]
    preflight_count: std::sync::atomic::AtomicUsize,
}

// A lease includes callers waiting for the per-database lock. None may be evicted.
struct Lease<'a> {
    session: Option<Arc<Mutex<Option<Session>>>>,
    cache: &'a SessionCache,
}

impl Drop for Lease<'_> {
    fn drop(&mut self) {
        // Synchronize release with capacity waiters to avoid a missed wakeup.
        let _registry = self
            .cache
            .registry
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        self.session.take();
        self.cache.available.notify_all();
    }
}

impl SessionCache {
    fn new(capacity: usize) -> Self {
        Self {
            registry: Mutex::new(Registry::default()),
            available: Condvar::new(),
            capacity: capacity.max(1),
            #[cfg(test)]
            open_count: std::sync::atomic::AtomicUsize::new(0),
            #[cfg(test)]
            preflight_count: std::sync::atomic::AtomicUsize::new(0),
        }
    }

    fn acquire(&self, path: &Path) -> Result<Lease<'_>> {
        let mut registry = self
            .registry
            .lock()
            .map_err(|_| unavailable("session registry lock failed"))?;
        loop {
            registry.clock = registry.clock.wrapping_add(1);
            let clock = registry.clock;
            if let Some(entry) = registry.entries.get_mut(path) {
                entry.last_used = clock;
                return Ok(Lease {
                    session: Some(Arc::clone(&entry.session)),
                    cache: self,
                });
            }
            let evicted = if registry.entries.len() >= self.capacity {
                let oldest = registry
                    .entries
                    .iter()
                    .filter(|(_, entry)| Arc::strong_count(&entry.session) == 1)
                    .min_by_key(|(_, entry)| entry.last_used)
                    .map(|(path, _)| path.clone());
                match oldest {
                    Some(path) => registry.entries.remove(&path),
                    None => {
                        registry = self
                            .available
                            .wait(registry)
                            .map_err(|_| unavailable("session registry wait failed"))?;
                        continue;
                    }
                }
            } else {
                None
            };
            let session = Arc::new(Mutex::new(None));
            registry.entries.insert(
                path.to_path_buf(),
                Entry {
                    session: Arc::clone(&session),
                    last_used: clock,
                },
            );
            drop(registry);
            drop(evicted); // Closing SQLite may checkpoint; never do that under the registry lock.
            return Ok(Lease {
                session: Some(session),
                cache: self,
            });
        }
    }

    fn with_core<T>(
        &self,
        path: impl AsRef<Path>,
        operation: impl FnOnce(&mut ClipboardCore) -> Result<T>,
    ) -> Result<T> {
        self.with_core_options(path, true, operation, |_| false)
    }

    fn with_core_options<T>(
        &self,
        path: impl AsRef<Path>,
        maintenance: bool,
        operation: impl FnOnce(&mut ClipboardCore) -> Result<T>,
        invalidate: impl FnOnce(&T) -> bool,
    ) -> Result<T> {
        #[cfg(test)]
        SESSION_ACCESS_COUNT.with(|count| count.set(count.get() + 1));
        fs::create_dir_all(path.as_ref())?;
        let path = path.as_ref().canonicalize()?;
        let database_path = path.join(DATABASE_FILE_NAME);
        let lease = self.acquire(&path)?;
        let slot = lease.session.as_ref().expect("active session lease");
        let mut session = match slot.lock() {
            Ok(session) => session,
            Err(error) => {
                let mut session = error.into_inner();
                *session = None;
                slot.clear_poison();
                session
            }
        };
        let identity = FileIdentity::read(&database_path)?;
        let reusable = session.as_ref().is_some_and(|session| {
            identity.as_ref() == Some(&session.identity)
                && session.core.schema_identity().ok() == Some(session.schema)
        });
        #[cfg(test)]
        if maintenance {
            self.preflight_count
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        if !reusable {
            *session = None;
            let core = if maintenance {
                ClipboardCore::open(&path)?
            } else {
                ClipboardCore::open_without_history_maintenance(&path)?
            };
            let schema = core.schema_identity()?;
            let identity = FileIdentity::read(&database_path)?
                .ok_or_else(|| unavailable("database disappeared while opening"))?;
            *session = Some(Session {
                core,
                identity,
                schema,
            });
            #[cfg(test)]
            self.open_count
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        let result = (|| {
            let core = &mut session.as_mut().expect("initialized session").core;
            if reusable && maintenance {
                core.apply_current_history_preferences()?;
            }
            operation(core)
        })();
        if result.as_ref().err().is_some_and(|error| {
            matches!(
                error.code,
                CoreErrorCode::DatabaseUnavailable
                    | CoreErrorCode::MigrationFailed
                    | CoreErrorCode::MigrationChecksumMismatch
                    | CoreErrorCode::RecoveryRequired
            )
        }) || result.as_ref().ok().is_some_and(invalidate)
        {
            *session = None;
        }
        // No retry: a mutation may have committed before its follow-up work failed.
        result
    }
}

pub(super) fn with_core<T>(
    path: impl AsRef<Path>,
    operation: impl FnOnce(&mut ClipboardCore) -> Result<T>,
) -> Result<T> {
    cache().with_core(path, operation)
}

fn cache() -> &'static SessionCache {
    static CACHE: OnceLock<SessionCache> = OnceLock::new();
    CACHE.get_or_init(|| SessionCache::new(MAX_SESSIONS))
}

pub(super) fn with_core_without_maintenance<T>(
    path: impl AsRef<Path>,
    operation: impl FnOnce(&mut ClipboardCore) -> Result<T>,
) -> Result<T> {
    cache().with_core_options(path, false, operation, |_| false)
}

pub(super) fn with_core_batch(
    path: impl AsRef<Path>,
    operation: impl FnOnce(&mut ClipboardCore) -> Result<clipboard_core::ItemBatchMutationResult>,
) -> Result<clipboard_core::ItemBatchMutationResult> {
    cache().with_core_options(path, true, operation, |result| result.session_fault)
}

fn unavailable(message: &str) -> CoreError {
    CoreError::new(CoreErrorCode::DatabaseUnavailable, message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        mpsc, Barrier,
    };
    use std::thread;
    use std::time::Duration;
    use tempfile::TempDir;

    #[test]
    fn recovery_required_batch_evicts_session_and_does_not_replay_committed_mutations() {
        use clipboard_core::{ItemMutation, ItemMutationStatus};
        let root = TempDir::new().unwrap();
        let first = super::super::tests::synthetic_text(root.path(), "first");
        let bad = super::super::tests::synthetic_text(root.path(), "bad");
        let last = super::super::tests::synthetic_text(root.path(), "last");
        // Pin the actual FFI cache entry so unrelated parallel tests cannot evict it.
        let lease = cache()
            .acquire(&root.path().canonicalize().unwrap())
            .unwrap();
        with_core_without_maintenance(root.path(), |core| core.info()).unwrap();
        let connection = rusqlite::Connection::open(root.path().join(DATABASE_FILE_NAME)).unwrap();
        connection
            .execute_batch(
                "INSERT INTO pending_image_jobs
            (job_id,requested_item_id,owner_session_id,thumbnail_relative_path,
             reserved_payload_relative_path,staged_payload_relative_path,state,
             lease_expires_at_ms,cleanup_after_ms,created_at_ms,updated_at_ms)
            VALUES ('conflict','synthetic-item','synthetic-owner','thumbnails/missing.webp',
                'assets/conflict.webp','.staging/conflict.webp','pending',
                9223372036854775807,9223372036854775807,1,1);",
            )
            .unwrap();
        fs::write(root.path().join("assets/conflict.webp"), b"final").unwrap();
        fs::write(root.path().join(".staging/conflict.webp"), b"staged").unwrap();
        let attempts = std::cell::Cell::new(0);
        let result = with_core_batch(root.path(), |core| {
            attempts.set(attempts.get() + 1);
            core.mutate_items(vec![
                ItemMutation::RecordCopied {
                    item_id: first.clone(),
                },
                ItemMutation::Delete {
                    item_id: bad.clone(),
                },
                ItemMutation::RecordCopied {
                    item_id: last.clone(),
                },
            ])
        })
        .unwrap();
        assert_eq!(attempts.get(), 1);
        assert!(result.session_fault);
        assert_eq!(result.termination_reason.unwrap().code, "recovery_required");
        assert_eq!(result.outcomes[0].status, ItemMutationStatus::Applied);
        assert_eq!(result.outcomes[1].status, ItemMutationStatus::Failed);
        assert_eq!(result.outcomes[1].committed, Some(true));
        assert!(result.outcomes[1].requires_refresh);
        assert_eq!(result.outcomes[2].status, ItemMutationStatus::NotAttempted);
        assert!(lease.session.as_ref().unwrap().lock().unwrap().is_none());
        // Recovery remains unresolved, but a fresh no-maintenance session can read
        // committed data. Neither the successful prefix nor the deletion is retried.
        let counts = with_core_without_maintenance(root.path(), |core| {
            Ok((
                core.get_item(&first)?.unwrap().copy_count,
                core.get_item(&last)?.unwrap().copy_count,
            ))
        })
        .unwrap();
        assert_eq!(counts, (2, 1));
        assert!(connection
            .query_row(
                "SELECT deleted_at_ms IS NOT NULL FROM clipboard_items WHERE id=?1",
                [&bad],
                |row| row.get::<_, bool>(0)
            )
            .unwrap());
        assert_eq!(attempts.get(), 1);
    }

    #[test]
    fn batch_fault_returned_as_ok_evicts_session_without_replay() {
        let root = TempDir::new().unwrap();
        drop(ClipboardCore::open(root.path()).unwrap());
        let connection = rusqlite::Connection::open(root.path().join(DATABASE_FILE_NAME)).unwrap();
        connection.execute_batch("INSERT INTO clipboard_items
            (id,type,summary,primary_text,content_hash,first_copied_at_ms,last_copied_at_ms,created_at_ms,updated_at_ms)
            VALUES ('first','text','a','a','first',1,1,1,1),('bad','text','b','b','bad',1,1,1,1),('last','text','c','c','last',1,1,1,1);
            CREATE TRIGGER injected BEFORE UPDATE ON clipboard_items WHEN OLD.id='bad'
            BEGIN SELECT RAISE(ABORT,'injected'); END;").unwrap();
        let cache = SessionCache::new(1);
        let result = cache
            .with_core_options(
                root.path(),
                false,
                |core| {
                    core.mutate_items(
                        ["first", "bad", "last"]
                            .into_iter()
                            .map(|id| clipboard_core::ItemMutation::RecordCopied {
                                item_id: id.into(),
                            })
                            .collect(),
                    )
                },
                |result| result.session_fault,
            )
            .unwrap();
        assert!(result.session_fault);
        assert_eq!(
            result.outcomes[2].status,
            clipboard_core::ItemMutationStatus::NotAttempted
        );
        let first = cache
            .with_core_options(root.path(), false, |core| core.get_item("first"), |_| false)
            .unwrap()
            .unwrap();
        assert_eq!(first.copy_count, 2);
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn batch_runs_one_preflight_and_keeps_each_duplicate_operation() {
        let root = TempDir::new().unwrap();
        let cache = SessionCache::new(1);
        let result = cache
            .with_core_options(
                root.path(),
                true,
                |core| {
                    core.mutate_items(vec![
                        clipboard_core::ItemMutation::RecordCopied {
                            item_id: "missing".into()
                        };
                        200
                    ])
                },
                |result| result.session_fault,
            )
            .unwrap();
        assert_eq!(result.outcomes.len(), 200);
        assert_eq!(cache.preflight_count.load(Ordering::Relaxed), 1);
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 1);
    }

    #[test]
    #[ignore = "synthetic batch timing; run in release mode with --nocapture"]
    fn synthetic_batch_benchmark() {
        for size in [50, 200] {
            for batch in [false, true] {
                let root = TempDir::new().unwrap();
                let cache = SessionCache::new(1);
                let id =
                    super::super::tests::synthetic_text(root.path(), "synthetic batch benchmark");
                let mut timings = Vec::new();
                for _ in 0..31 {
                    let start = std::time::Instant::now();
                    if batch {
                        cache
                            .with_core_options(
                                root.path(),
                                true,
                                |core| {
                                    core.mutate_items(vec![
                                            clipboard_core::ItemMutation::RecordCopied {
                                                item_id: id.clone()
                                            };
                                            size
                                        ])
                                },
                                |result| result.session_fault,
                            )
                            .unwrap();
                    } else {
                        for _ in 0..size {
                            cache
                                .with_core(root.path(), |core| core.record_item_copied(&id))
                                .unwrap();
                        }
                    }
                    timings.push(start.elapsed().as_micros());
                }
                let first = timings.remove(0);
                timings.sort();
                println!("batch={batch} size={size} first_us={first} median_us={} p95_us={} maintenance_calls={} session_opens={} item_transactions={}",
                    timings[15],timings[28],cache.preflight_count.load(Ordering::Relaxed),cache.open_count.load(Ordering::Relaxed),31*size);
            }
        }
    }

    #[test]
    fn reuses_connections_and_canonical_paths_with_bounded_idle_entries() {
        let cache = SessionCache::new(2);
        let first = TempDir::new().unwrap();
        let second = TempDir::new().unwrap();
        let third = TempDir::new().unwrap();
        for _ in 0..3 {
            cache.with_core(first.path(), |core| core.info()).unwrap();
        }
        cache
            .with_core(first.path().join("."), |core| core.info())
            .unwrap();
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 1);
        #[cfg(unix)]
        {
            let aliases = TempDir::new().unwrap();
            std::os::unix::fs::symlink(first.path(), aliases.path().join("alias")).unwrap();
            cache
                .with_core(aliases.path().join("alias"), |core| core.info())
                .unwrap();
            assert_eq!(cache.open_count.load(Ordering::Relaxed), 1);
        }
        cache.with_core(second.path(), |core| core.info()).unwrap();
        cache.with_core(third.path(), |core| core.info()).unwrap();
        assert_eq!(cache.registry.lock().unwrap().entries.len(), 2);
        cache.with_core(first.path(), |core| core.info()).unwrap();
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 4);
    }

    #[test]
    fn concurrent_same_database_initializes_once_and_serializes_operations() {
        let cache = Arc::new(SessionCache::new(2));
        let directory = TempDir::new().unwrap();
        let start = Arc::new(Barrier::new(5));
        let active = Arc::new(AtomicUsize::new(0));
        let workers: Vec<_> = (0..4)
            .map(|_| {
                let (cache, start, active, path) = (
                    cache.clone(),
                    start.clone(),
                    active.clone(),
                    directory.path().to_path_buf(),
                );
                thread::spawn(move || {
                    start.wait();
                    cache
                        .with_core(path, |core| {
                            assert_eq!(active.fetch_add(1, Ordering::SeqCst), 0);
                            let result = core.info();
                            assert_eq!(active.fetch_sub(1, Ordering::SeqCst), 1);
                            result
                        })
                        .unwrap();
                })
            })
            .collect();
        start.wait();
        for worker in workers {
            worker.join().unwrap();
        }
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn other_database_does_not_wait_for_busy_session() {
        let cache = Arc::new(SessionCache::new(2));
        let first = TempDir::new().unwrap();
        let second = TempDir::new().unwrap();
        let (entered, entered_rx) = mpsc::channel();
        let (release, release_rx) = mpsc::channel();
        let worker_cache = cache.clone();
        let worker_path = first.path().to_path_buf();
        let worker = thread::spawn(move || {
            worker_cache
                .with_core(worker_path, |_| {
                    entered.send(()).unwrap();
                    release_rx.recv_timeout(Duration::from_secs(5)).unwrap();
                    Ok(())
                })
                .unwrap()
        });
        entered_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        cache.with_core(second.path(), |core| core.info()).unwrap();
        release.send(()).unwrap();
        worker.join().unwrap();
    }

    #[test]
    fn capacity_waits_for_active_leases_without_creating_an_extra_connection() {
        let cache = Arc::new(SessionCache::new(1));
        let first = TempDir::new().unwrap();
        let second = TempDir::new().unwrap();
        let lease = cache.acquire(first.path()).unwrap();
        let (done, done_rx) = mpsc::channel();
        let other = cache.clone();
        let path = second.path().to_path_buf();
        let worker = thread::spawn(move || {
            other.with_core(path, |core| core.info()).unwrap();
            done.send(()).unwrap();
        });
        assert!(done_rx.recv_timeout(Duration::from_millis(50)).is_err());
        drop(lease);
        done_rx.recv_timeout(Duration::from_secs(5)).unwrap();
        worker.join().unwrap();
        assert_eq!(cache.registry.lock().unwrap().entries.len(), 1);
    }

    #[test]
    fn directory_recreation_and_schema_changes_reopen_connections() {
        let cache = SessionCache::new(2);
        let parent = TempDir::new().unwrap();
        let path = parent.path().join("recreated");
        cache.with_core(&path, |core| core.info()).unwrap();
        fs::remove_dir_all(&path).unwrap();
        cache.with_core(&path, |core| core.info()).unwrap();
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 2);
        let connection = rusqlite::Connection::open(path.join(DATABASE_FILE_NAME)).unwrap();
        connection
            .execute("CREATE TABLE outside_schema(value TEXT)", [])
            .unwrap();
        cache.with_core(&path, |core| core.info()).unwrap();
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 3);
        // A migration record alone does not change PRAGMA schema_version.
        connection.execute("INSERT INTO schema_migrations(version,name,checksum,applied_at_ms) VALUES(999,'future','future',0)", []).unwrap();
        assert_eq!(
            cache.with_core(&path, |core| core.info()).unwrap_err().code,
            CoreErrorCode::MigrationFailed
        );
        connection
            .execute("DELETE FROM schema_migrations WHERE version=999", [])
            .unwrap();
        cache.with_core(&path, |core| core.info()).unwrap();
    }

    #[test]
    fn external_preferences_are_visible_and_expiration_runs_without_capture() {
        let cache = SessionCache::new(2);
        let directory = TempDir::new().unwrap();
        cache
            .with_core(directory.path(), |core| core.info())
            .unwrap();
        let connection =
            rusqlite::Connection::open(directory.path().join(DATABASE_FILE_NAME)).unwrap();
        connection.execute("UPDATE preference_documents SET value_json = json_set(value_json, '$.history.retention_forever', json('true'))", []).unwrap();
        assert!(
            cache
                .with_core(directory.path(), |core| core.get_preferences())
                .unwrap()
                .history
                .retention_forever
        );
        cache
            .with_core(directory.path(), |core| {
                core.capture_text(clipboard_core::CaptureTextRequest {
                    text: "will expire".into(),
                    detected_link: None,
                    display_rtf_relative_path: None,
                    display_rtf_mime_type: None,
                    display_rtf_byte_count: 0,
                    source_bundle_id: None,
                    source_app_name: None,
                    source_bundle_path: None,
                    source_icon_relative_path: None,
                    source_confidence: clipboard_core::SourceConfidence::Unknown,
                    pasteboard_change_count: 1,
                    self_write_token: None,
                })
            })
            .unwrap();
        connection
            .execute("UPDATE clipboard_items SET last_copied_at_ms=1", [])
            .unwrap();
        assert_eq!(
            cache
                .with_core(directory.path(), |core| core.info())
                .unwrap()
                .item_count,
            1
        );
        connection.execute("UPDATE preference_documents SET value_json = json_set(value_json, '$.history.retention_forever', json('false'))", []).unwrap();
        assert_eq!(
            cache
                .with_core(directory.path(), |core| core.info())
                .unwrap()
                .item_count,
            0
        );
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn errors_do_not_replay_mutations_and_next_call_can_recover() {
        let cache = SessionCache::new(1);
        let directory = TempDir::new().unwrap();
        let calls = AtomicUsize::new(0);
        let result: Result<()> = cache.with_core(directory.path(), |_| {
            calls.fetch_add(1, Ordering::SeqCst);
            Err(unavailable("injected failure after mutation"))
        });
        assert!(result.is_err());
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        cache
            .with_core(directory.path(), |core| core.info())
            .unwrap();
        assert_eq!(cache.open_count.load(Ordering::Relaxed), 2);
    }
}
#[test]
fn recovery_required_evicts_the_uncertain_session_without_replaying() {
    let root = tempfile::tempdir().unwrap();
    let cache = SessionCache::new(1);
    let attempts = std::cell::Cell::new(0);
    let result: clipboard_core::Result<()> = cache.with_core_options(
        root.path(),
        false,
        |_core| {
            attempts.set(attempts.get() + 1);
            Err(CoreError::new(
                CoreErrorCode::RecoveryRequired,
                "synthetic uncertain rollback",
            ))
        },
        |_| false,
    );
    assert_eq!(result.unwrap_err().code, CoreErrorCode::RecoveryRequired);
    assert_eq!(attempts.get(), 1);
    cache
        .with_core_options(root.path(), false, |core| core.get_preferences(), |_| false)
        .unwrap();
    assert_eq!(
        cache.open_count.load(std::sync::atomic::Ordering::Relaxed),
        2
    );
}
