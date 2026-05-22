use crate::domain::PreferencesDocument;
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use crate::CURRENT_SCHEMA_VERSION;
use rusqlite::{params, Connection};

use super::ClipboardCore;

const MILLIS_PER_DAY: i64 = 24 * 60 * 60 * 1000;
const DEFAULT_PRIVACY_IGNORE_APPS_SCHEMA_VERSION: i64 = 10;
const DEFAULT_OPEN_PANEL_SHORTCUT_SCHEMA_VERSION: i64 = 11;
const SHORTCUT_OPTIONS_SCHEMA_VERSION: i64 = 12;
const LEGACY_DEFAULT_OPEN_PANEL_KEY_CODE: i64 = 9;

impl ClipboardCore {
    pub fn get_preferences(&self) -> Result<PreferencesDocument> {
        let value_json: String = self.connection.query_row(
            "SELECT value_json FROM preference_documents WHERE id = 'current'",
            [],
            |row| row.get(0),
        )?;
        parse_preferences_document(&value_json)
    }

    pub fn update_preferences(
        &mut self,
        preferences: PreferencesDocument,
    ) -> Result<PreferencesDocument> {
        let preferences = preferences.normalized();
        let value_json = serde_json::to_string(&preferences).map_err(|error| {
            CoreError::new(
                CoreErrorCode::InvalidInput,
                format!("preferences serialization failed: {error}"),
            )
        })?;
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        transaction.execute(
            r#"
            UPDATE preference_documents
            SET schema_version = ?1, value_json = ?2, updated_at_ms = ?3
            WHERE id = 'current'
            "#,
            params![CURRENT_SCHEMA_VERSION, value_json, now],
        )?;
        transaction.commit()?;
        self.apply_history_preferences(&preferences)?;
        Ok(preferences)
    }

    pub(super) fn apply_history_preferences(
        &mut self,
        preferences: &PreferencesDocument,
    ) -> Result<i64> {
        let preferences = preferences.clone().normalized();
        let now = now_ms();
        let retention_cutoff = now - preferences.history.retention_days * MILLIS_PER_DAY;
        let transaction = self.connection.transaction()?;
        let retention_deleted = transaction.execute(
            r#"
            UPDATE clipboard_items
            SET deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE deleted_at_ms IS NULL
                AND NOT EXISTS (
                    SELECT 1
                    FROM pinboard_items pi_retention
                    INNER JOIN pinboards pb_retention ON pb_retention.id = pi_retention.pinboard_id
                    WHERE pi_retention.item_id = clipboard_items.id
                        AND pb_retention.deleted_at_ms IS NULL
                )
                AND last_copied_at_ms < ?2
            "#,
            params![now, retention_cutoff],
        )?;
        let max_items_deleted = transaction.execute(
            r#"
            WITH ranked_items AS (
                SELECT
                    rowid,
                    ROW_NUMBER() OVER (
                        ORDER BY last_copied_at_ms DESC, id DESC
                    ) AS rank
                FROM clipboard_items
                WHERE deleted_at_ms IS NULL
                    AND NOT EXISTS (
                        SELECT 1
                        FROM pinboard_items pi_limit
                        INNER JOIN pinboards pb_limit ON pb_limit.id = pi_limit.pinboard_id
                        WHERE pi_limit.item_id = clipboard_items.id
                            AND pb_limit.deleted_at_ms IS NULL
                    )
            )
            UPDATE clipboard_items
            SET deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE rowid IN (
                SELECT rowid
                FROM ranked_items
                WHERE rank > ?2
            )
            "#,
            params![now, preferences.history.max_items],
        )?;
        transaction.commit()?;

        let deleted_count = (retention_deleted + max_items_deleted) as i64;
        if deleted_count > 0 {
            self.purge_soft_deleted_items_and_assets()?;
        }

        Ok(deleted_count)
    }
}

pub(super) fn seed_default_preferences(connection: &Connection) -> Result<()> {
    let now = now_ms();
    let preferences = serde_json::to_string(&PreferencesDocument::default()).map_err(|error| {
        CoreError::new(
            CoreErrorCode::InvalidInput,
            format!("default preferences serialization failed: {error}"),
        )
    })?;

    connection.execute(
        r#"
        INSERT OR IGNORE INTO preference_documents (id, schema_version, value_json, updated_at_ms)
        VALUES ('current', ?1, ?2, ?3)
        "#,
        params![CURRENT_SCHEMA_VERSION, preferences, now],
    )?;
    migrate_default_privacy_ignore_apps(connection)?;
    migrate_default_open_panel_shortcut(connection)?;
    migrate_shortcut_options(connection)?;
    Ok(())
}

pub(super) fn parse_preferences_document(value_json: &str) -> Result<PreferencesDocument> {
    serde_json::from_str::<PreferencesDocument>(value_json)
        .map(PreferencesDocument::normalized)
        .map_err(|error| {
            CoreError::new(
                CoreErrorCode::InvalidInput,
                format!("preferences json is invalid: {error}"),
            )
        })
}

fn migrate_default_privacy_ignore_apps(connection: &Connection) -> Result<()> {
    let (schema_version, value_json): (i64, String) = connection.query_row(
        "SELECT schema_version, value_json FROM preference_documents WHERE id = 'current'",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    if schema_version >= DEFAULT_PRIVACY_IGNORE_APPS_SCHEMA_VERSION {
        return Ok(());
    }

    let mut preferences = parse_preferences_document(&value_json)?;
    for identifier in PreferencesDocument::default()
        .ignore_list
        .ignored_app_identifiers
    {
        if !preferences
            .ignore_list
            .ignored_app_identifiers
            .iter()
            .any(|value| value.eq_ignore_ascii_case(&identifier))
        {
            preferences
                .ignore_list
                .ignored_app_identifiers
                .push(identifier);
        }
    }
    let preferences = preferences.normalized();
    let value_json = serde_json::to_string(&preferences).map_err(|error| {
        CoreError::new(
            CoreErrorCode::InvalidInput,
            format!("default ignore app migration serialization failed: {error}"),
        )
    })?;

    connection.execute(
        r#"
        UPDATE preference_documents
        SET schema_version = ?1, value_json = ?2, updated_at_ms = ?3
        WHERE id = 'current'
        "#,
        params![
            DEFAULT_PRIVACY_IGNORE_APPS_SCHEMA_VERSION,
            value_json,
            now_ms()
        ],
    )?;
    Ok(())
}

fn migrate_default_open_panel_shortcut(connection: &Connection) -> Result<()> {
    let (schema_version, value_json): (i64, String) = connection.query_row(
        "SELECT schema_version, value_json FROM preference_documents WHERE id = 'current'",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    if schema_version >= DEFAULT_OPEN_PANEL_SHORTCUT_SCHEMA_VERSION {
        return Ok(());
    }

    let mut preferences = parse_preferences_document(&value_json)?;
    let shortcut = &preferences.shortcuts.open_panel;
    if shortcut.as_ref().is_some_and(|shortcut| {
        shortcut.key_code == LEGACY_DEFAULT_OPEN_PANEL_KEY_CODE
            && shortcut.modifiers == vec!["command".to_string(), "shift".to_string()]
    }) {
        preferences.shortcuts.open_panel = PreferencesDocument::default().shortcuts.open_panel;
    }
    let preferences = preferences.normalized();
    let value_json = serde_json::to_string(&preferences).map_err(|error| {
        CoreError::new(
            CoreErrorCode::InvalidInput,
            format!("default shortcut migration serialization failed: {error}"),
        )
    })?;

    connection.execute(
        r#"
        UPDATE preference_documents
        SET schema_version = ?1, value_json = ?2, updated_at_ms = ?3
        WHERE id = 'current'
        "#,
        params![CURRENT_SCHEMA_VERSION, value_json, now_ms()],
    )?;
    Ok(())
}

fn migrate_shortcut_options(connection: &Connection) -> Result<()> {
    let (schema_version, value_json): (i64, String) = connection.query_row(
        "SELECT schema_version, value_json FROM preference_documents WHERE id = 'current'",
        [],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )?;

    if schema_version >= SHORTCUT_OPTIONS_SCHEMA_VERSION {
        return Ok(());
    }

    let preferences = parse_preferences_document(&value_json)?.normalized();
    let value_json = serde_json::to_string(&preferences).map_err(|error| {
        CoreError::new(
            CoreErrorCode::InvalidInput,
            format!("shortcut options migration serialization failed: {error}"),
        )
    })?;

    connection.execute(
        r#"
        UPDATE preference_documents
        SET schema_version = ?1, value_json = ?2, updated_at_ms = ?3
        WHERE id = 'current'
        "#,
        params![CURRENT_SCHEMA_VERSION, value_json, now_ms()],
    )?;
    Ok(())
}
