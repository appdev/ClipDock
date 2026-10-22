use super::ClipboardCore;
#[cfg(unix)]
use crate::{AssetReservation, AssetStore};
use crate::{CoreError, CoreErrorCode, ItemManagementResult, Result};
use std::collections::HashSet;
use std::fs::File;
use std::io::Read;
#[cfg(not(unix))]
use std::path::PathBuf;

/// Unix uses fd-relative no-follow operations. Windows retains its existing
/// native asset adapter until its separate platform validation gate passes.
pub(super) struct ManagedAssetGuard {
    #[cfg(not(unix))]
    root: PathBuf,
    #[cfg(unix)]
    inner: crate::AssetLifecycleGuard,
}

impl ClipboardCore {
    pub(super) fn with_asset_registration<T>(
        &mut self,
        paths: Vec<String>,
        operation: impl FnOnce(&mut Self, &ManagedAssetGuard) -> Result<T>,
    ) -> Result<T> {
        let guard = self.asset_lifecycle()?;
        let result = operation(self, &guard);
        // The operation has returned, so its SQLite transaction has completed
        // or dropped. Release ownership even when reference lookup then fails.
        let cleanup = self.settle_asset_paths(&guard, &paths);
        match (result, cleanup) {
            (Ok(value), Ok(_)) => Ok(value),
            (Ok(_), Err(error)) => Err(error.with_detail("mutation_committed", "true")),
            (Err(error), _) => Err(error),
        }
    }
    pub(super) fn asset_lifecycle(&self) -> Result<ManagedAssetGuard> {
        let root = self.root_dir()?.to_path_buf();
        Ok(ManagedAssetGuard {
            #[cfg(unix)]
            inner: AssetStore::open(&root)?.lock_lifecycle()?,
            #[cfg(not(unix))]
            root,
        })
    }

    /// Release only this process's owned reservations, after checking current
    /// authoritative references. No caller-provided path authorizes deletion.
    pub fn cleanup_uncommitted_assets(
        &mut self,
        paths: Vec<String>,
    ) -> Result<ItemManagementResult> {
        let guard = self.asset_lifecycle()?;
        let affected_count = self.settle_asset_paths(&guard, &paths)?;
        Ok(ItemManagementResult { affected_count })
    }

    pub(super) fn settle_asset_paths(
        &self,
        guard: &ManagedAssetGuard,
        paths: &[String],
    ) -> Result<i64> {
        #[cfg(unix)]
        {
            let released = guard.inner.release_owned_for_paths(paths)?;
            self.cleanup_inactive_reservations(guard, released)
                .map(|(count, _)| count)
        }
        #[cfg(not(unix))]
        {
            let _ = (guard, paths);
            Ok(0)
        }
    }

    pub(super) fn cleanup_abandoned_reservations(
        &self,
        guard: &ManagedAssetGuard,
    ) -> Result<(i64, i64)> {
        #[cfg(unix)]
        {
            guard.inner.cleanup_abandoned_metadata()?;
            self.cleanup_inactive_reservations(guard, guard.inner.reservations()?)
        }
        #[cfg(not(unix))]
        {
            let _ = guard;
            Ok((0, 0))
        }
    }

    #[cfg(unix)]
    fn cleanup_inactive_reservations(
        &self,
        guard: &ManagedAssetGuard,
        receipts: Vec<AssetReservation>,
    ) -> Result<(i64, i64)> {
        if !self.connection.is_autocommit() {
            return Err(CoreError::new(
                CoreErrorCode::RecoveryRequired,
                "asset reference authority is still inside an unfinished transaction",
            ));
        }
        let references = self.asset_references(true)?;
        let active = guard.active_reservation_paths()?;
        let mut deleted = 0;
        let mut reclaimed = 0;
        for receipt in receipts {
            if guard.inner.reservation_is_active(&receipt)? {
                continue;
            }
            for path in [&receipt.relative_path, &receipt.staged_relative_path] {
                if !references.contains(path) && !active.contains(path) {
                    if let Some(bytes) = guard.delete(path)? {
                        deleted += 1;
                        reclaimed += bytes;
                    }
                }
            }
            guard.inner.forget_inactive_reservation(&receipt)?;
        }
        Ok((deleted, reclaimed))
    }

    /// Must be called after taking the lifecycle guard, never a cached snapshot.
    pub(super) fn asset_references(&self, include_pending: bool) -> Result<HashSet<String>> {
        let mut statement = self.connection.prepare(
            "SELECT a.relative_path FROM clipboard_assets a JOIN clipboard_items i ON i.id=a.item_id WHERE i.deleted_at_ms IS NULL
             UNION SELECT relative_path FROM source_app_icons
             UNION SELECT lm.icon_relative_path FROM link_metadata lm JOIN clipboard_items i ON i.id=lm.item_id WHERE i.deleted_at_ms IS NULL AND lm.icon_relative_path IS NOT NULL
             UNION SELECT lm.image_relative_path FROM link_metadata lm JOIN clipboard_items i ON i.id=lm.item_id WHERE i.deleted_at_ms IS NULL AND lm.image_relative_path IS NOT NULL")?;
        let mut references = statement
            .query_map([], |row| row.get::<_, String>(0))?
            .collect::<std::result::Result<HashSet<_>, _>>()?;
        if include_pending {
            let mut statement = self.connection.prepare("SELECT thumbnail_relative_path, reserved_payload_relative_path, staged_payload_relative_path FROM pending_image_jobs WHERE state='pending'")?;
            for row in statement.query_map([], |row| {
                Ok([row.get::<_, String>(0)?, row.get(1)?, row.get(2)?])
            })? {
                references.extend(row?);
            }
        }
        Ok(references)
    }

    pub(super) fn delete_unreferenced_asset(
        &self,
        guard: &ManagedAssetGuard,
        path: &str,
    ) -> Result<Option<i64>> {
        if self.asset_references(true)?.contains(path)
            || guard.active_reservation_paths()?.contains(path)
        {
            return Ok(None);
        }
        guard.delete(path)
    }

    pub(super) fn reconcile_pending_asset_files(&self) -> Result<()> {
        let guard = self.asset_lifecycle()?;
        self.reconcile_pending_asset_files_locked(&guard)
    }

    pub(super) fn reconcile_pending_asset_files_locked(
        &self,
        guard: &ManagedAssetGuard,
    ) -> Result<()> {
        let mut statement = self.connection.prepare("SELECT job_id,state,reserved_payload_relative_path,staged_payload_relative_path FROM pending_image_jobs")?;
        let jobs = statement
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, String>(3)?,
                ))
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        drop(statement);
        let references = self.asset_references(false)?;
        for (job_id, state, final_path, staged_path) in jobs {
            let final_exists = guard.exists(&final_path)?;
            let staged_exists = guard.exists(&staged_path)?;
            if references.contains(&final_path) {
                if !final_exists && staged_exists && state == "ready" {
                    let expected: Option<String> = self.connection.query_row("SELECT content_hash FROM clipboard_assets WHERE relative_path=?1 LIMIT 1", [&final_path], |row| row.get(0)).ok();
                    if expected.as_deref() != Some(guard.hash(&staged_path)?.as_str()) {
                        return Err(recovery_required(
                            "committed pending asset digest does not match staging",
                            &job_id,
                        ));
                    }
                    guard
                        .rename(&staged_path, &final_path)
                        .map_err(|error| recovery_required(error.to_string(), &job_id))?;
                }
                continue;
            }
            if final_exists {
                if staged_exists {
                    return Err(recovery_required(
                        "both uncommitted pending asset locations exist",
                        &job_id,
                    ));
                }
                guard
                    .rename(&final_path, &staged_path)
                    .map_err(|error| recovery_required(error.to_string(), &job_id))?;
            }
        }
        Ok(())
    }
}

pub(super) fn recovery_required(message: impl Into<String>, job_id: &str) -> CoreError {
    CoreError::new(CoreErrorCode::RecoveryRequired, message).with_detail("job_id", job_id)
}

impl ManagedAssetGuard {
    pub(super) fn read(&self, path: &str) -> Result<File> {
        #[cfg(unix)]
        {
            self.inner.require_completed_if_reserved(path)?;
            Ok(self.inner.read(path)?)
        }
        #[cfg(not(unix))]
        {
            Ok(File::open(self.root.join(
                super::support::normalize_relative_asset_path(path)?,
            ))?)
        }
    }
    pub(super) fn read_bytes(&self, path: &str, max_bytes: usize) -> Result<Vec<u8>> {
        let file = self.read(path)?;
        if file.metadata()?.len() > max_bytes as u64 {
            return Err(CoreError::new(
                CoreErrorCode::InvalidInput,
                "asset exceeds byte budget",
            ));
        }
        let mut data = Vec::new();
        file.take(max_bytes as u64 + 1).read_to_end(&mut data)?;
        if data.len() > max_bytes {
            return Err(CoreError::new(
                CoreErrorCode::InvalidInput,
                "asset exceeds byte budget",
            ));
        }
        Ok(data)
    }
    pub(super) fn hash(&self, path: &str) -> Result<String> {
        let mut file = self.read(path)?;
        let budget = clipdock_asset_store::MAX_ENCODED_ASSET_BYTES as u64;
        if file.metadata()?.len() > budget {
            return Err(CoreError::new(
                CoreErrorCode::InvalidInput,
                "asset exceeds hash byte budget",
            ));
        }
        let mut digest = blake3::Hasher::new();
        let mut buffer = [0u8; 64 * 1024];
        let mut count = 0u64;
        loop {
            let read = file.read(&mut buffer)?;
            if read == 0 {
                break;
            }
            count = count.saturating_add(read as u64);
            if count > budget {
                return Err(CoreError::new(
                    CoreErrorCode::InvalidInput,
                    "asset exceeds hash byte budget",
                ));
            }
            digest.update(&buffer[..read]);
        }
        Ok(digest.finalize().to_hex().to_string())
    }
    pub(super) fn exists(&self, path: &str) -> Result<bool> {
        #[cfg(unix)]
        {
            Ok(self.inner.exists(path)?)
        }
        #[cfg(not(unix))]
        {
            Ok(self
                .root
                .join(super::support::normalize_relative_asset_path(path)?)
                .try_exists()?)
        }
    }
    pub(super) fn rename(&self, from: &str, to: &str) -> Result<()> {
        #[cfg(unix)]
        {
            Ok(self.inner.rename(from, to)?)
        }
        #[cfg(not(unix))]
        {
            let target = self
                .root
                .join(super::support::normalize_relative_asset_path(to)?);
            if let Some(parent) = target.parent() {
                std::fs::create_dir_all(parent)?;
            }
            Ok(std::fs::rename(
                self.root
                    .join(super::support::normalize_relative_asset_path(from)?),
                target,
            )?)
        }
    }
    pub(super) fn delete(&self, path: &str) -> Result<Option<i64>> {
        #[cfg(unix)]
        {
            Ok(self
                .inner
                .delete(path)?
                .map(|n| n.min(i64::MAX as u64) as i64))
        }
        #[cfg(not(unix))]
        {
            super::support::delete_relative_file(&self.root, path)
        }
    }
    pub(super) fn active_reservation_paths(&self) -> Result<HashSet<String>> {
        let mut paths = HashSet::new();
        #[cfg(unix)]
        for reservation in self.inner.reservations()? {
            if self.inner.reservation_is_active(&reservation)? {
                paths.insert(reservation.relative_path);
                paths.insert(reservation.staged_relative_path);
            }
        }
        Ok(paths)
    }
    pub(super) fn managed_files(&self) -> Result<Vec<String>> {
        #[cfg(unix)]
        {
            Ok(self.inner.managed_files()?)
        }
        #[cfg(not(unix))]
        {
            super::maintenance::collect_maintenance_files(&self.root)
        }
    }
}
