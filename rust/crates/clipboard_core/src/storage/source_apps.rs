use crate::error::Result;
use rusqlite::params;

use super::support::stable_hash;
use super::ClipboardCore;

pub(super) struct SourceAppInput<'a> {
    pub bundle_id: Option<&'a str>,
    pub app_name: Option<&'a str>,
    pub bundle_path: Option<&'a str>,
    pub icon_relative_path: Option<&'a str>,
}

impl ClipboardCore {
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
        let source_app_id = format!("source_{}", &stable_hash(&derived_key)[..24]);

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
}
