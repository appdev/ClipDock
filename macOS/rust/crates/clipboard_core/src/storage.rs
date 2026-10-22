mod backup;
mod asset_lifecycle;
#[cfg(test)]
mod asset_lifecycle_tests;
mod capture;
mod link_metadata;
#[cfg(test)]
mod list_mutation_tests;
mod maintenance;
mod mutations;
mod pending_images;
mod preferences;
pub(crate) mod preferences_patch;
mod queries;
#[cfg(test)]
mod remediation_tests;
mod source_apps;
mod support;
#[cfg(test)]
mod tests;
mod text_metrics;
mod thumbnails;

use crate::domain::{ClipboardItemSummary, CoreInfo, ItemQuery, SourceAppSummary};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::migrations::run_migrations;
use crate::{register_simple_tokenizer, CURRENT_SCHEMA_VERSION, DATABASE_FILE_NAME};
use rusqlite::Connection;
use std::cell::RefCell;
use std::fs;
use std::path::{Path, PathBuf};

use self::preferences::seed_default_preferences;
pub use backup::BackupResult;

pub struct ClipboardCore {
    database_path: PathBuf,
    connection: Connection,
    text_metrics: RefCell<text_metrics::TextMetricsCache>,
}

impl ClipboardCore {
    pub fn open(app_support_dir: impl AsRef<Path>) -> Result<Self> {
        Self::open_impl(app_support_dir.as_ref(), true)
    }

    /// Settings remain accessible when optional history maintenance fails.
    pub fn open_without_history_maintenance(app_support_dir: impl AsRef<Path>) -> Result<Self> {
        Self::open_impl(app_support_dir.as_ref(), false)
    }

    /// Backup opening must preserve history regardless of retention settings.
    pub fn open_for_backup(app_support_dir: impl AsRef<Path>) -> Result<Self> {
        Self::open_impl(app_support_dir.as_ref(), false)
    }

    fn open_impl(app_support_dir: &Path, apply_maintenance: bool) -> Result<Self> {
        fs::create_dir_all(app_support_dir)?;

        for directory in ["assets", "thumbnails", "app-icons", "staging", ".staging"] {
            fs::create_dir_all(app_support_dir.join(directory))?;
        }

        let database_path = app_support_dir.join(DATABASE_FILE_NAME);
        let mut connection = Connection::open(&database_path).map_err(|error| {
            CoreError::new(CoreErrorCode::DatabaseUnavailable, error.to_string())
                .with_detail("path", database_path.display().to_string())
        })?;

        connection
            .execute_batch(
                r#"
                PRAGMA foreign_keys = ON;
                PRAGMA journal_mode = WAL;
                "#,
            )
            .map_err(|error| {
                CoreError::new(CoreErrorCode::DatabaseUnavailable, error.to_string())
                    .with_detail("path", database_path.display().to_string())
            })?;

        register_simple_tokenizer(&connection)?;
        run_migrations(&mut connection)?;
        seed_default_preferences(&connection)?;

        let mut core = Self {
            database_path,
            connection,
            text_metrics: RefCell::new(text_metrics::TextMetricsCache::default()),
        };
        if apply_maintenance {
            core.reconcile_pending_asset_files()?;
            core.apply_current_history_preferences()?;
        }

        Ok(core)
    }

    pub fn info(&self) -> Result<CoreInfo> {
        let item_count = self.active_item_count(&ItemQuery::default())?;
        Ok(CoreInfo {
            database_path: self.database_path.display().to_string(),
            schema_version: CURRENT_SCHEMA_VERSION,
            item_count,
        })
    }

    pub fn database_path(&self) -> &Path {
        &self.database_path
    }

    /// Cheap stamps used by the FFI session cache before reusing a connection.
    pub fn schema_identity(&self) -> Result<(i64, i64)> {
        let cookie = self
            .connection
            .query_row("PRAGMA schema_version", [], |row| row.get(0))?;
        let version = self.connection.query_row(
            "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
            [],
            |row| row.get(0),
        )?;
        Ok((cookie, version))
    }

    fn root_dir(&self) -> Result<&Path> {
        self.database_path.parent().ok_or_else(|| {
            CoreError::new(
                CoreErrorCode::IoFailed,
                "database path does not have a parent directory",
            )
        })
    }

    fn with_absolute_paths(&self, mut item: ClipboardItemSummary) -> ClipboardItemSummary {
        if let Some(root) = self.database_path.parent() {
            if let Some(relative_path) = item.source_app_icon_path.take() {
                item.source_app_icon_path = Some(root.join(relative_path).display().to_string());
            }
            if let Some(relative_path) = item.preview_asset_path.take() {
                item.preview_asset_path = Some(root.join(relative_path).display().to_string());
            }
            if let Some(relative_path) = item.payload_asset_path.take() {
                item.payload_asset_path = Some(root.join(relative_path).display().to_string());
            }
            if let Some(link_metadata) = item.link_metadata.as_mut() {
                if let Some(relative_path) = link_metadata.icon_asset_path.take() {
                    link_metadata.icon_asset_path =
                        Some(root.join(relative_path).display().to_string());
                }
                if let Some(relative_path) = link_metadata.image_asset_path.take() {
                    link_metadata.image_asset_path =
                        Some(root.join(relative_path).display().to_string());
                }
            }
        }
        item
    }

    fn with_absolute_source_app_path(&self, mut app: SourceAppSummary) -> SourceAppSummary {
        if let Some(relative_path) = app.icon_path.take() {
            if let Some(root) = self.database_path.parent() {
                app.icon_path = Some(root.join(relative_path).display().to_string());
            }
        }
        app
    }

    fn normalize_pinboard_id(pinboard_id: impl AsRef<str>) -> String {
        let trimmed = pinboard_id.as_ref().trim();
        if trimmed.is_empty() {
            DEFAULT_PINBOARD_ID.to_string()
        } else {
            trimmed.to_string()
        }
    }
}

pub(crate) const DEFAULT_PINBOARD_ID: &str = "default";
