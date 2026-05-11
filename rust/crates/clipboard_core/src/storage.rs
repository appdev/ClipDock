mod capture;
mod maintenance;
mod preferences;
mod queries;
mod source_apps;
mod support;
#[cfg(test)]
mod tests;

use crate::domain::{ClipboardItemSummary, CoreInfo, ItemQuery, SourceAppSummary};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::migrations::run_migrations;
use crate::{CURRENT_SCHEMA_VERSION, DATABASE_FILE_NAME};
use rusqlite::Connection;
use std::fs;
use std::path::{Path, PathBuf};

use self::preferences::seed_default_preferences;

pub struct ClipboardCore {
    database_path: PathBuf,
    connection: Connection,
}

impl ClipboardCore {
    pub fn open(app_support_dir: impl AsRef<Path>) -> Result<Self> {
        let app_support_dir = app_support_dir.as_ref();
        fs::create_dir_all(app_support_dir)?;

        for directory in ["assets", "thumbnails", "app-icons", "staging"] {
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

        run_migrations(&mut connection)?;
        seed_default_preferences(&connection)?;

        let mut core = Self {
            database_path,
            connection,
        };
        let preferences = core.get_preferences()?;
        core.apply_history_preferences(&preferences)?;

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
