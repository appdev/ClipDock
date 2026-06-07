use crate::domain::ItemManagementResult;
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use crate::ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION;
use rusqlite::{params, OptionalExtension};

use super::support::stable_hash;
use super::ClipboardCore;
use std::path::{Component, Path, PathBuf};

const MIN_OPAQUE_ARGB: i64 = 0xFF00_0000;
const MAX_OPAQUE_ARGB: i64 = 0xFFFF_FFFF;

pub(super) struct SourceAppInput<'a> {
    pub bundle_id: Option<&'a str>,
    pub app_name: Option<&'a str>,
    pub bundle_path: Option<&'a str>,
    pub icon_relative_path: Option<&'a str>,
}

impl ClipboardCore {
    pub fn active_source_icon_header_color_cache_version() -> i64 {
        ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION
    }

    pub fn update_source_app_icon_header_color(
        &mut self,
        source_app_id: impl AsRef<str>,
        source_app_icon_path: impl AsRef<str>,
        header_color_argb: i64,
        allow_latest_without_path: bool,
    ) -> Result<ItemManagementResult> {
        let source_app_id = normalize_source_app_id(source_app_id.as_ref())?;
        let header_color_argb = normalize_header_color_argb(header_color_argb)?;
        let expected_relative_path =
            self.normalize_expected_icon_path(source_app_icon_path.as_ref())?;
        let now = now_ms();

        let affected_count = match expected_relative_path {
            Some(relative_path) => self.connection.execute(
                r#"
                UPDATE source_app_icons
                SET
                    header_color_argb = ?1,
                    header_color_cache_version = ?2,
                    header_color_updated_at_ms = ?3
                WHERE source_app_id = ?4 AND relative_path = ?5
                "#,
                params![
                    header_color_argb,
                    ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION,
                    now,
                    source_app_id,
                    relative_path
                ],
            )?,
            None if allow_latest_without_path => self.connection.execute(
                r#"
                UPDATE source_app_icons
                SET
                    header_color_argb = ?1,
                    header_color_cache_version = ?2,
                    header_color_updated_at_ms = ?3
                WHERE id = (
                    SELECT id
                    FROM source_app_icons
                    WHERE source_app_id = ?4
                    ORDER BY updated_at_ms DESC
                    LIMIT 1
                )
                "#,
                params![
                    header_color_argb,
                    ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION,
                    now,
                    source_app_id
                ],
            )?,
            None => 0,
        } as i64;

        Ok(ItemManagementResult { affected_count })
    }

    pub(super) fn upsert_source_app(
        &self,
        input: SourceAppInput<'_>,
        now: i64,
    ) -> Result<Option<String>> {
        let app_name = input
            .app_name
            .map(str::trim)
            .filter(|value| !value.is_empty());
        let bundle_id = input
            .bundle_id
            .map(str::trim)
            .filter(|value| !value.is_empty());

        let Some(app_name) = app_name else {
            return Ok(None);
        };

        let derived_key = bundle_id
            .map(|value| format!("bundle:{value}"))
            .unwrap_or_else(|| format!("name:{}", app_name.to_lowercase()));
        let existing_source_app_id = if let Some(bundle_id) = bundle_id {
            self.connection
                .query_row(
                    "SELECT id FROM source_apps WHERE bundle_id = ?1",
                    params![bundle_id],
                    |row| row.get::<_, String>(0),
                )
                .optional()?
        } else {
            self.connection
                .query_row(
                    "SELECT id FROM source_apps WHERE derived_key = ?1",
                    params![&derived_key],
                    |row| row.get::<_, String>(0),
                )
                .optional()?
        };
        let source_app_id = existing_source_app_id
            .unwrap_or_else(|| format!("source_{}", &stable_hash(&derived_key)[..24]));

        self.connection.execute(
            r#"
            INSERT INTO source_apps (
                id, bundle_id, derived_key, name, bundle_path,
                last_seen_at_ms, created_at_ms, updated_at_ms
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?6)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                bundle_path = excluded.bundle_path,
                last_seen_at_ms = excluded.last_seen_at_ms,
                updated_at_ms = excluded.updated_at_ms
            "#,
            params![
                source_app_id,
                bundle_id,
                if bundle_id.is_some() {
                    None::<String>
                } else {
                    Some(derived_key)
                },
                app_name,
                input.bundle_path,
                now
            ],
        )?;

        if let Some(relative_path) = input
            .icon_relative_path
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let cache_key = format!("{}:{relative_path}", source_app_id);
            let icon_id = format!("icon_{}", &stable_hash(&cache_key)[..24]);
            self.connection.execute(
                "DELETE FROM source_app_icons WHERE source_app_id = ?1 AND relative_path <> ?2",
                params![source_app_id, relative_path],
            )?;
            self.connection.execute(
                r#"
                INSERT INTO source_app_icons (
                    id, source_app_id, cache_key, relative_path,
                    byte_count, created_at_ms, updated_at_ms
                )
                VALUES (?1, ?2, ?3, ?4, 0, ?5, ?5)
                ON CONFLICT(cache_key) DO UPDATE SET
                    relative_path = excluded.relative_path,
                    updated_at_ms = excluded.updated_at_ms
                "#,
                params![icon_id, source_app_id, cache_key, relative_path, now],
            )?;
        }

        Ok(Some(source_app_id))
    }

    fn normalize_expected_icon_path(&self, value: &str) -> Result<Option<String>> {
        normalize_expected_icon_path(self.root_dir()?, value)
    }
}

fn normalize_source_app_id(value: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "source app id cannot be empty",
        ));
    }
    Ok(value.to_string())
}

fn normalize_header_color_argb(value: i64) -> Result<i64> {
    if (MIN_OPAQUE_ARGB..=MAX_OPAQUE_ARGB).contains(&value) {
        Ok(value)
    } else {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "source app icon header color must be an opaque positive Int64 ARGB value",
        ))
    }
}

fn normalize_expected_icon_path(app_support_dir: &Path, value: &str) -> Result<Option<String>> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }

    let input_path = Path::new(trimmed);
    let relative_path = if input_path.is_absolute() {
        let root = normalize_absolute_path(app_support_dir)?;
        let absolute = normalize_absolute_path(input_path)?;
        let relative = absolute.strip_prefix(&root).map_err(|_| {
            CoreError::new(
                CoreErrorCode::InvalidInput,
                "absolute source app icon path must be under app support directory",
            )
        })?;
        relative_path_to_db_form(relative)?
    } else {
        relative_input_to_db_form(trimmed)?
    };

    if relative_path.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "source app icon path cannot resolve to app support root",
        ));
    }
    Ok(Some(relative_path))
}

fn normalize_absolute_path(path: &Path) -> Result<PathBuf> {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::Prefix(prefix) => normalized.push(prefix.as_os_str()),
            Component::RootDir => normalized.push(component.as_os_str()),
            Component::CurDir => {}
            Component::Normal(value) => normalized.push(value),
            Component::ParentDir => {
                if !normalized.pop() {
                    return Err(CoreError::new(
                        CoreErrorCode::InvalidInput,
                        "absolute source app icon path cannot escape root",
                    ));
                }
            }
        }
    }
    Ok(normalized)
}

fn relative_path_to_db_form(path: &Path) -> Result<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(value) => {
                let value = value.to_str().ok_or_else(|| {
                    CoreError::new(
                        CoreErrorCode::InvalidInput,
                        "source app icon path is not UTF-8",
                    )
                })?;
                parts.push(value.to_string());
            }
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(CoreError::new(
                    CoreErrorCode::InvalidInput,
                    "source app icon path must stay inside app support directory",
                ));
            }
        }
    }
    Ok(parts.join("/"))
}

fn relative_input_to_db_form(value: &str) -> Result<String> {
    let normalized_separators = value.replace('\\', "/");
    let mut parts: Vec<&str> = Vec::new();
    for part in normalized_separators.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if parts.pop().is_none() {
                    return Err(CoreError::new(
                        CoreErrorCode::InvalidInput,
                        "relative source app icon path cannot escape app support directory",
                    ));
                }
            }
            value => parts.push(value),
        }
    }
    Ok(parts.join("/"))
}
