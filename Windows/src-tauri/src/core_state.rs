use std::path::PathBuf;
use std::sync::Mutex;

use clipboard_core::{ClipboardCore, ItemBatchMutationResult, ItemMutation};
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

pub const HISTORY_CHANGED_EVENT: &str = "history-changed";

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryChanged {
    pub revision: u64,
    pub reason: String,
}

struct CoreSession {
    core: Option<ClipboardCore>,
    revision: u64,
}

/// Tauri-managed wrapper around the shared `clipboard_core` storage engine.
///
/// `ClipboardCore` owns a synchronous `rusqlite` connection, so it is guarded
/// by a `Mutex`. Tauri commands acquire the lock for the duration of a single
/// storage operation. The same crate (and therefore the same schema, content
/// hashing, and local history logic) also backs the macOS client.
pub struct CoreState {
    core: Mutex<CoreSession>,
    root_dir: PathBuf,
    pub preferences_gate: Mutex<()>,
    pub thumbnail_gate: Mutex<()>,
    pub maintenance_warning: Mutex<Option<String>>,
}

impl CoreState {
    /// Open (creating if needed) the ClipDock database under the platform's
    /// app-local data directory. Mirrors the macOS layout: a `ClipDock`
    /// directory containing `clipboard.sqlite` plus the asset subdirectories
    /// that `ClipboardCore::open` provisions.
    pub fn initialize(app: &AppHandle) -> Result<Self, String> {
        let root_dir = app
            .path()
            .app_local_data_dir()
            .map_err(|error| format!("app data directory unavailable: {error}"))?
            .join("ClipDock");

        Self::open_root(root_dir)
    }

    fn open_root(root_dir: PathBuf) -> Result<Self, String> {
        Self::open_root_with_maintenance(root_dir, ClipboardCore::apply_current_history_preferences)
    }

    fn open_root_with_maintenance(
        root_dir: PathBuf,
        maintenance: impl FnOnce(&mut ClipboardCore) -> clipboard_core::Result<i64>,
    ) -> Result<Self, String> {
        let mut core = ClipboardCore::open_without_history_maintenance(&root_dir)
            .map_err(|error| format!("failed to open clipboard database: {error:?}"))?;
        let maintenance_warning = maintenance(&mut core)
            .err()
            .map(|error| error.code.as_str().to_string());

        Ok(Self {
            core: Mutex::new(CoreSession {
                core: Some(core),
                revision: 0,
            }),
            root_dir,
            preferences_gate: Mutex::new(()),
            thumbnail_gate: Mutex::new(()),
            maintenance_warning: Mutex::new(maintenance_warning),
        })
    }

    /// Run a closure with mutable access to the underlying core. Poisoned
    /// locks are surfaced as a recoverable error string rather than panicking
    /// the command thread.
    pub fn with_core<T>(
        &self,
        action: impl FnOnce(&mut ClipboardCore) -> Result<T, String>,
    ) -> Result<T, String> {
        let mut guard = self
            .core
            .lock()
            .map_err(|_| "clipboard core lock poisoned".to_string())?;
        action(self.ensure_core(&mut guard)?)
    }

    pub fn read_with_revision<T>(
        &self,
        action: impl FnOnce(&mut ClipboardCore) -> Result<T, String>,
    ) -> Result<(T, u64), String> {
        let mut guard = self
            .core
            .lock()
            .map_err(|_| "clipboard core lock poisoned".to_string())?;
        let result = action(self.ensure_core(&mut guard)?)?;
        Ok((result, guard.revision))
    }

    /// Errors can occur after a core transaction committed (for example during
    /// retention maintenance). Always invalidate readers, but never replay the write.
    pub fn mutate<T>(
        &self,
        app: &AppHandle,
        reason: &str,
        action: impl FnOnce(&mut ClipboardCore) -> Result<T, String>,
    ) -> Result<T, String> {
        let (result, revision) = {
            let mut guard = self
                .core
                .lock()
                .map_err(|_| "clipboard core lock poisoned".to_string())?;
            let result = action(self.ensure_core(&mut guard)?);
            guard.revision = guard.revision.saturating_add(1);
            (result, guard.revision)
        };
        let _ = app.emit(
            HISTORY_CHANGED_EVENT,
            HistoryChanged {
                revision,
                reason: if result.is_ok() { reason } else { "reconcile" }.to_string(),
            },
        );
        result
    }

    fn ensure_core<'a>(
        &self,
        session: &'a mut CoreSession,
    ) -> Result<&'a mut ClipboardCore, String> {
        if session.core.is_none() {
            session.core = Some(
                ClipboardCore::open_without_history_maintenance(&self.root_dir)
                    .map_err(|error| error.to_string())?,
            );
        }
        Ok(session.core.as_mut().expect("initialized core"))
    }

    pub fn mutate_batch(
        &self,
        app: &AppHandle,
        mutations: Vec<ItemMutation>,
    ) -> Result<ItemBatchMutationResult, String> {
        let (result, revision) = self.batch_with_revision(|core| core.mutate_items(mutations))?;
        let _ = app.emit(
            HISTORY_CHANGED_EVENT,
            HistoryChanged {
                revision,
                reason: "reconcile".into(),
            },
        );
        result
    }

    fn batch_with_revision(
        &self,
        operation: impl FnOnce(&mut ClipboardCore) -> clipboard_core::Result<ItemBatchMutationResult>,
    ) -> Result<(Result<ItemBatchMutationResult, String>, u64), String> {
        let mut guard = self
            .core
            .lock()
            .map_err(|_| "clipboard core lock poisoned")?;
        let result = operation(self.ensure_core(&mut guard)?);
        if result.as_ref().is_ok_and(|batch| batch.session_fault) {
            guard.core = None;
        }
        guard.revision = guard.revision.saturating_add(1);
        Ok((result.map_err(|error| error.to_string()), guard.revision))
    }

    /// Absolute path to the ClipDock root directory (database + assets).
    pub fn root_dir(&self) -> &PathBuf {
        &self.root_dir
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn batch_session_fault_invalidates_connection_without_replaying_committed_work() {
        let directory = tempfile::tempdir().unwrap();
        let state = CoreState::open_root(directory.path().into()).unwrap();
        let calls = std::cell::Cell::new(0);
        let (result, revision) = state
            .batch_with_revision(|core| {
                calls.set(calls.get() + 1);
                core.patch_preferences(clipboard_core::PreferencesPatch {
                    ignore_list: Some(clipboard_core::IgnoreListPreferencesPatch {
                        ignored_app_identifiers: Some(vec!["AlreadyCommitted.exe".into()]),
                        ..Default::default()
                    }),
                    ..Default::default()
                })?;
                Ok(ItemBatchMutationResult {
                    outcomes: vec![],
                    session_fault: true,
                    termination_reason: None,
                })
            })
            .unwrap();
        assert!(result.unwrap().session_fault);
        assert_eq!(revision, 1);
        assert!(state.core.lock().unwrap().core.is_none());
        let preferences = state
            .with_core(|core| core.get_preferences().map_err(|error| error.to_string()))
            .unwrap();
        assert_eq!(
            preferences.ignore_list.ignored_app_identifiers,
            ["AlreadyCommitted.exe"]
        );
        assert!(state.core.lock().unwrap().core.is_some());
        assert_eq!(calls.get(), 1);
    }

    #[test]
    fn settings_remain_readable_and_writable_when_startup_maintenance_fails() {
        let directory = tempfile::tempdir().unwrap();
        let state = CoreState::open_root_with_maintenance(directory.path().into(), |_| {
            Err(clipboard_core::CoreError::new(
                clipboard_core::CoreErrorCode::IoFailed,
                "injected maintenance failure",
            ))
        })
        .unwrap();
        assert_eq!(
            state.maintenance_warning.lock().unwrap().as_deref(),
            Some("io_failed")
        );
        state
            .with_core(|core| {
                core.get_preferences().map_err(|error| error.to_string())?;
                let patch = clipboard_core::PreferencesPatch {
                    ignore_list: Some(clipboard_core::IgnoreListPreferencesPatch {
                        ignored_app_identifiers: Some(vec!["Private.exe".into()]),
                        ..Default::default()
                    }),
                    ..Default::default()
                };
                let saved = core
                    .patch_preferences(patch)
                    .map_err(|error| error.to_string())?;
                assert_eq!(
                    saved.document.ignore_list.ignored_app_identifiers,
                    ["Private.exe"]
                );
                Ok(())
            })
            .unwrap();
    }
}
