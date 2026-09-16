use std::path::PathBuf;
use std::sync::Mutex;

use clipboard_core::ClipboardCore;
use tauri::{AppHandle, Manager};

/// Tauri-managed wrapper around the shared `clipboard_core` storage engine.
///
/// `ClipboardCore` owns a synchronous `rusqlite` connection, so it is guarded
/// by a `Mutex`. Tauri commands acquire the lock for the duration of a single
/// storage operation. The same crate (and therefore the same schema, content
/// hashing, and local history logic) also backs the macOS client.
pub struct CoreState {
    core: Mutex<ClipboardCore>,
    root_dir: PathBuf,
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

        let core = ClipboardCore::open(&root_dir)
            .map_err(|error| format!("failed to open clipboard database: {error:?}"))?;

        Ok(Self {
            core: Mutex::new(core),
            root_dir,
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
        action(&mut guard)
    }

    /// Absolute path to the ClipDock root directory (database + assets).
    pub fn root_dir(&self) -> &PathBuf {
        &self.root_dir
    }
}
