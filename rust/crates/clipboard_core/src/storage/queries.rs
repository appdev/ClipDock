use crate::domain::{
    ClipboardFileItemSummary, ClipboardItemSummary, ClipboardItemType, ItemManagementResult,
    ItemPage, ItemQuery, LinkMetadataState, LinkMetadataSummary, PageRequest, PinboardPage,
    PinboardSummary, PayloadState, PreviewState, SourceAppPage, SourceAppSummary, SourceConfidence,
};
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use crate::ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION;
use rusqlite::types::Value;
use rusqlite::{params, params_from_iter, Transaction};
use std::collections::HashMap;

use super::support::normalize_item_id;
use super::{ClipboardCore, DEFAULT_PINBOARD_ID};

const DEFAULT_PINBOARD_TITLE: &str = "未命名";
const PINBOARD_COLOR_CODES: [i64; 7] = [
    4_293_940_557,
    4_294_620_928,
    4_290_925_536,
    4_279_606_035,
    4_283_973_119,
    4_293_088_528,
    4_284_242_835,
];

impl ClipboardCore {
    pub fn list_items(&self, query: ItemQuery, page: PageRequest) -> Result<ItemPage> {
        let page = page.normalized();
        let total_count = self.active_item_count(&query)?;
        let pinboard_id = query
            .pinboard_id
            .as_deref()
            .map(Self::normalize_pinboard_id);
        let mut sql = format!(
            r#"
            SELECT
                i.id,
                i.type,
                i.summary,
                i.primary_text,
                i.content_hash,
                i.source_app_id,
                COALESCE(s.name, i.source_app_name),
                ic.relative_path,
                CASE
                    WHEN ic.header_color_cache_version == {ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION}
                    THEN ic.header_color_argb
                    ELSE NULL
                END,
                (
                    SELECT a.relative_path
                    FROM clipboard_assets a
                    WHERE a.item_id = i.id AND a.kind IN ('thumbnail', 'payload', 'file_snapshot')
                    ORDER BY
                        CASE a.kind
                            WHEN 'thumbnail' THEN 0
                            WHEN 'payload' THEN 1
                            ELSE 2
                        END,
                        a.created_at_ms DESC
                    LIMIT 1
                ),
                (
                    SELECT a.relative_path
                    FROM clipboard_assets a
                    WHERE a.item_id = i.id AND a.kind IN ('payload', 'file_snapshot')
                    ORDER BY
                        CASE a.kind WHEN 'payload' THEN 0 ELSE 1 END,
                        a.created_at_ms DESC
                    LIMIT 1
                ),
                i.source_confidence,
                i.first_copied_at_ms,
                i.last_copied_at_ms,
                i.copy_count,
                CASE WHEN EXISTS (
                    SELECT 1
                    FROM pinboard_items pi_state
                    INNER JOIN pinboards pb_state ON pb_state.id = pi_state.pinboard_id
                    WHERE pi_state.item_id = i.id
                        AND pb_state.deleted_at_ms IS NULL
                ) THEN 1 ELSE 0 END,
                i.size_bytes,
                i.preview_state,
                i.payload_state,
                lm.canonical_url,
                lm.display_url,
                lm.host,
                lm.title,
                lm.site_name,
                lm.icon_relative_path,
                lm.image_relative_path,
                lm.metadata_state,
                lm.fetched_at_ms
            FROM clipboard_items i
            LEFT JOIN source_apps s ON s.id = i.source_app_id
            LEFT JOIN source_app_icons ic ON ic.id = (
                SELECT latest_ic.id
                FROM source_app_icons latest_ic
                WHERE latest_ic.source_app_id = s.id
                ORDER BY latest_ic.updated_at_ms DESC
                LIMIT 1
            )
            LEFT JOIN link_metadata lm ON lm.item_id = i.id
            "#
        );

        let mut filter_params = Vec::new();
        if let Some(pinboard_id) = pinboard_id.as_deref() {
            sql.push_str(
                r#"
                INNER JOIN pinboard_items pi_filter ON pi_filter.item_id = i.id
                INNER JOIN pinboards pb_filter ON pb_filter.id = pi_filter.pinboard_id
                "#,
            );
            filter_params.push(Value::Text(pinboard_id.to_string()));
        }
        sql.push_str(" WHERE i.deleted_at_ms IS NULL");
        if pinboard_id.is_some() {
            sql.push_str(
                r#"
                AND pi_filter.pinboard_id = ?
                AND pb_filter.deleted_at_ms IS NULL
                "#,
            );
        }
        filter_params.extend(append_query_filters(&mut sql, &query));
        if pinboard_id.is_some() {
            sql.push_str(
                " ORDER BY pi_filter.display_order ASC, pi_filter.pinned_at_ms DESC, i.last_copied_at_ms DESC",
            );
        } else {
            sql.push_str(" ORDER BY i.last_copied_at_ms DESC, i.id DESC");
        }
        sql.push_str(" LIMIT ? OFFSET ?");
        filter_params.push(Value::Integer(page.limit));
        filter_params.push(Value::Integer(page.offset));

        let mut statement = self.connection.prepare(&sql)?;
        let rows = statement.query_map(params_from_iter(filter_params.iter()), map_item_summary)?;

        let mut items = rows.collect::<std::result::Result<Vec<_>, _>>()?;
        let file_items_by_item = self.file_items_for_items(&items)?;
        for item in &mut items {
            item.file_items = file_items_by_item
                .get(item.id.as_str())
                .cloned()
                .unwrap_or_default();
        }
        let items: Vec<ClipboardItemSummary> = items
            .into_iter()
            .map(|item| self.with_absolute_paths(item))
            .collect();

        Ok(ItemPage {
            has_more: page.offset + (items.len() as i64) < total_count,
            items,
            total_count,
        })
    }

    fn file_items_for_items(
        &self,
        items: &[ClipboardItemSummary],
    ) -> Result<HashMap<String, Vec<ClipboardFileItemSummary>>> {
        let item_ids: Vec<&str> = items
            .iter()
            .filter(|item| item.item_type == ClipboardItemType::File)
            .map(|item| item.id.as_str())
            .collect();
        if item_ids.is_empty() {
            return Ok(HashMap::new());
        }

        let placeholders = std::iter::repeat("?")
            .take(item_ids.len())
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!(
            r#"
            SELECT
                item_id,
                path,
                file_name,
                file_extension,
                byte_count,
                is_directory,
                width,
                height,
                content_type
            FROM clipboard_file_items
            WHERE item_id IN ({placeholders})
            ORDER BY item_id ASC, order_index ASC
            "#
        );
        let mut statement = self.connection.prepare(&sql)?;
        let rows = statement.query_map(params_from_iter(item_ids.iter()), |row| {
            Ok((
                row.get::<_, String>(0)?,
                ClipboardFileItemSummary {
                    path: row.get(1)?,
                    file_name: row.get(2)?,
                    file_extension: row.get(3)?,
                    byte_count: row.get(4)?,
                    is_directory: row.get::<_, i64>(5)? == 1,
                    width: row.get(6)?,
                    height: row.get(7)?,
                    content_type: row.get(8)?,
                },
            ))
        })?;

        let mut file_items_by_item: HashMap<String, Vec<ClipboardFileItemSummary>> = HashMap::new();
        for row in rows {
            let (item_id, file_item) = row?;
            file_items_by_item
                .entry(item_id)
                .or_default()
                .push(file_item);
        }
        Ok(file_items_by_item)
    }

    pub fn list_source_apps(&self, page: PageRequest) -> Result<SourceAppPage> {
        let page = page.normalized();
        let total_count = self.active_source_app_count()?;
        let mut statement = self.connection.prepare(
            r#"
            SELECT
                s.id,
                s.bundle_id,
                s.name,
                (
                    SELECT ic.relative_path
                    FROM source_app_icons ic
                    WHERE ic.source_app_id = s.id
                    ORDER BY ic.updated_at_ms DESC
                    LIMIT 1
                ) AS icon_path,
                (
                    SELECT
                        CASE
                            WHEN ic.header_color_cache_version == ?3 THEN ic.header_color_argb
                            ELSE NULL
                        END
                    FROM source_app_icons ic
                    WHERE ic.source_app_id = s.id
                    ORDER BY ic.updated_at_ms DESC
                    LIMIT 1
                ) AS icon_header_color,
                COUNT(i.id) AS item_count,
                MAX(i.last_copied_at_ms) AS last_copied_at_ms
            FROM source_apps s
            INNER JOIN clipboard_items i ON i.source_app_id = s.id
            WHERE i.deleted_at_ms IS NULL
            GROUP BY s.id, s.bundle_id, s.name
            ORDER BY last_copied_at_ms DESC, s.name COLLATE NOCASE ASC
            LIMIT ?1 OFFSET ?2
            "#,
        )?;
        let rows = statement.query_map(
            params![
                page.limit,
                page.offset,
                ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION
            ],
            map_source_app_summary,
        )?;
        let apps = rows
            .collect::<std::result::Result<Vec<_>, _>>()?
            .into_iter()
            .map(|app| self.with_absolute_source_app_path(app))
            .collect::<Vec<_>>();

        Ok(SourceAppPage {
            has_more: page.offset + (apps.len() as i64) < total_count,
            apps,
            total_count,
        })
    }

    pub fn list_pinboards(&self) -> Result<PinboardPage> {
        let mut statement = self.connection.prepare(
            r#"
            SELECT
                p.id,
                p.title,
                p.color_code,
                p.sort_order,
                COUNT(i.id) AS item_count,
                p.created_at_ms,
                p.updated_at_ms
            FROM pinboards p
            LEFT JOIN pinboard_items pi ON pi.pinboard_id = p.id
            LEFT JOIN clipboard_items i ON i.id = pi.item_id AND i.deleted_at_ms IS NULL
            WHERE p.deleted_at_ms IS NULL
            GROUP BY p.id, p.title, p.color_code, p.sort_order, p.created_at_ms, p.updated_at_ms
            ORDER BY p.sort_order ASC, p.updated_at_ms DESC
            "#,
        )?;
        let pinboards = statement
            .query_map([], map_pinboard_summary)?
            .collect::<std::result::Result<Vec<_>, _>>()?
            .into_iter()
            .filter(|pinboard| !(pinboard.id == DEFAULT_PINBOARD_ID && pinboard.item_count == 0))
            .collect::<Vec<_>>();

        Ok(PinboardPage {
            total_count: pinboards.len() as i64,
            pinboards,
        })
    }

    pub fn create_pinboard(
        &mut self,
        title: impl AsRef<str>,
        color_code: Option<i64>,
    ) -> Result<PinboardSummary> {
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        let sort_order = next_pinboard_sort_order(&transaction)?;
        let pinboard_id = next_pinboard_id(&transaction, now)?;
        let title = normalize_optional_pinboard_title(title.as_ref());
        let color_code = normalized_pinboard_color(color_code, sort_order);

        transaction.execute(
            r#"
            INSERT INTO pinboards (
                id, title, system_kind, sort_order, color_code, created_at_ms, updated_at_ms
            )
            VALUES (?1, ?2, 'custom', ?3, ?4, ?5, ?5)
            "#,
            params![pinboard_id, title, sort_order, color_code, now],
        )?;

        let summary = active_pinboard_summary(&transaction, &pinboard_id)?;
        transaction.commit()?;
        Ok(summary)
    }

    pub fn rename_pinboard(
        &mut self,
        pinboard_id: impl AsRef<str>,
        title: impl AsRef<str>,
    ) -> Result<PinboardSummary> {
        let pinboard_id = Self::normalize_pinboard_id(pinboard_id.as_ref());
        let title = normalize_required_pinboard_title(title.as_ref())?;
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        let affected_count = transaction.execute(
            r#"
            UPDATE pinboards
            SET title = ?1, updated_at_ms = ?2
            WHERE id = ?3 AND deleted_at_ms IS NULL
            "#,
            params![title, now, pinboard_id],
        )?;
        if affected_count == 0 {
            return Err(invalid_pinboard_error(&pinboard_id));
        }

        let summary = active_pinboard_summary(&transaction, &pinboard_id)?;
        transaction.commit()?;
        Ok(summary)
    }

    pub fn update_pinboard_color(
        &mut self,
        pinboard_id: impl AsRef<str>,
        color_code: i64,
    ) -> Result<PinboardSummary> {
        let pinboard_id = Self::normalize_pinboard_id(pinboard_id.as_ref());
        let color_code = normalized_pinboard_color(Some(color_code), 0);
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        let affected_count = transaction.execute(
            r#"
            UPDATE pinboards
            SET color_code = ?1, updated_at_ms = ?2
            WHERE id = ?3 AND deleted_at_ms IS NULL
            "#,
            params![color_code, now, pinboard_id],
        )?;
        if affected_count == 0 {
            return Err(invalid_pinboard_error(&pinboard_id));
        }

        let summary = active_pinboard_summary(&transaction, &pinboard_id)?;
        transaction.commit()?;
        Ok(summary)
    }

    pub fn delete_pinboard(
        &mut self,
        pinboard_id: impl AsRef<str>,
    ) -> Result<ItemManagementResult> {
        let pinboard_id = Self::normalize_pinboard_id(pinboard_id.as_ref());
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        if !active_pinboard_exists(&transaction, &pinboard_id)? {
            return Ok(ItemManagementResult { affected_count: 0 });
        }

        let deleted_item_count = transaction.execute(
            r#"
            UPDATE clipboard_items
            SET is_pinned = 0, deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE deleted_at_ms IS NULL
                AND id IN (
                    SELECT item_id
                    FROM pinboard_items
                    WHERE pinboard_id = ?2
                )
                AND NOT EXISTS (
                    SELECT 1
                    FROM pinboard_items pi_keep
                    INNER JOIN pinboards pb_keep ON pb_keep.id = pi_keep.pinboard_id
                    WHERE pi_keep.item_id = clipboard_items.id
                        AND pi_keep.pinboard_id <> ?2
                        AND pb_keep.deleted_at_ms IS NULL
                )
            "#,
            params![now, &pinboard_id],
        )? as i64;

        transaction.execute(
            r#"
            UPDATE clipboard_items
            SET is_pinned = 1, updated_at_ms = ?1
            WHERE deleted_at_ms IS NULL
                AND id IN (
                    SELECT item_id
                    FROM pinboard_items
                    WHERE pinboard_id = ?2
                )
                AND EXISTS (
                    SELECT 1
                    FROM pinboard_items pi_keep
                    INNER JOIN pinboards pb_keep ON pb_keep.id = pi_keep.pinboard_id
                    WHERE pi_keep.item_id = clipboard_items.id
                        AND pi_keep.pinboard_id <> ?2
                        AND pb_keep.deleted_at_ms IS NULL
                )
            "#,
            params![now, &pinboard_id],
        )?;

        transaction.execute(
            "DELETE FROM pinboard_items WHERE pinboard_id = ?1",
            params![&pinboard_id],
        )?;
        transaction.execute(
            r#"
            UPDATE pinboards
            SET deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE id = ?2 AND deleted_at_ms IS NULL
            "#,
            params![now, &pinboard_id],
        )?;

        transaction.commit()?;
        if deleted_item_count > 0 {
            self.purge_soft_deleted_items_and_assets()?;
        }
        Ok(ItemManagementResult {
            affected_count: deleted_item_count,
        })
    }

    pub fn set_item_pinboard_membership(
        &mut self,
        item_id: impl AsRef<str>,
        pinboard_id: impl AsRef<str>,
        is_member: bool,
    ) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let pinboard_id = Self::normalize_pinboard_id(pinboard_id.as_ref());
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        let item_exists = active_item_exists(&transaction, &item_id)?;
        let affected_count =
            if item_exists && ensure_active_pinboard(&transaction, &pinboard_id, now)? {
                if is_member {
                    let display_order = next_pinboard_display_order(&transaction, &pinboard_id)?;
                    transaction.execute(
                        r#"
                    INSERT OR IGNORE INTO pinboard_items (
                        pinboard_id,
                        item_id,
                        display_order,
                        pinned_at_ms,
                        created_at_ms,
                        updated_at_ms
                    )
                    VALUES (?1, ?2, ?3, ?4, ?4, ?4)
                    "#,
                        params![pinboard_id, item_id, display_order, now],
                    )?;
                } else {
                    transaction.execute(
                        "DELETE FROM pinboard_items WHERE pinboard_id = ?1 AND item_id = ?2",
                        params![pinboard_id, item_id],
                    )?;
                }

                refresh_item_pin_cache(&transaction, &item_id, now)?;
                1
            } else {
                0
            };
        transaction.commit()?;

        Ok(ItemManagementResult { affected_count })
    }

    pub fn delete_item(&mut self, item_id: impl AsRef<str>) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let now = now_ms();
        let transaction = self.connection.transaction()?;
        transaction.execute(
            "DELETE FROM pinboard_items WHERE item_id = ?1",
            params![item_id],
        )?;
        let affected_count = transaction.execute(
            r#"
            UPDATE clipboard_items
            SET is_pinned = 0, deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE id = ?2 AND deleted_at_ms IS NULL
            "#,
            params![now, item_id],
        )? as i64;
        transaction.commit()?;
        if affected_count > 0 {
            self.purge_soft_deleted_items_and_assets()?;
        }

        Ok(ItemManagementResult { affected_count })
    }

    pub fn record_item_copied(&mut self, item_id: impl AsRef<str>) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE clipboard_items
            SET
                last_copied_at_ms = ?1,
                copy_count = copy_count + 1,
                updated_at_ms = ?1
            WHERE id = ?2 AND deleted_at_ms IS NULL
            "#,
            params![now, item_id],
        )? as i64;

        Ok(ItemManagementResult { affected_count })
    }

    pub fn clear_items(&mut self, query: ItemQuery) -> Result<ItemManagementResult> {
        if query.pinboard_id.is_some() {
            return Ok(ItemManagementResult { affected_count: 0 });
        }

        let now = now_ms();
        let mut sql = String::from(
            r#"
            UPDATE clipboard_items
            SET deleted_at_ms = ?, updated_at_ms = ?
            WHERE id IN (
                SELECT i.id
                FROM clipboard_items i
                LEFT JOIN source_apps s ON s.id = i.source_app_id
                WHERE i.deleted_at_ms IS NULL
                    AND NOT EXISTS (
                        SELECT 1
                        FROM pinboard_items pi_clear
                        INNER JOIN pinboards pb_clear ON pb_clear.id = pi_clear.pinboard_id
                        WHERE pi_clear.item_id = i.id
                            AND pb_clear.deleted_at_ms IS NULL
                    )
            "#,
        );
        let mut query_params = append_query_filters(&mut sql, &query);
        sql.push(')');

        let mut params = Vec::with_capacity(query_params.len() + 2);
        params.push(Value::Integer(now));
        params.push(Value::Integer(now));
        params.append(&mut query_params);

        let affected_count = self
            .connection
            .execute(&sql, params_from_iter(params.iter()))? as i64;
        if affected_count > 0 {
            self.purge_soft_deleted_items_and_assets()?;
        }

        Ok(ItemManagementResult { affected_count })
    }

    pub(super) fn active_item_count(&self, query: &ItemQuery) -> Result<i64> {
        let pinboard_id = query
            .pinboard_id
            .as_deref()
            .map(Self::normalize_pinboard_id);
        let mut sql = String::from(
            r#"
            SELECT COUNT(*)
            FROM clipboard_items i
            LEFT JOIN source_apps s ON s.id = i.source_app_id
            "#,
        );
        let mut filter_params = Vec::new();
        if let Some(pinboard_id) = pinboard_id.as_deref() {
            sql.push_str(
                r#"
                INNER JOIN pinboard_items pi_filter ON pi_filter.item_id = i.id
                INNER JOIN pinboards pb_filter ON pb_filter.id = pi_filter.pinboard_id
                "#,
            );
            filter_params.push(Value::Text(pinboard_id.to_string()));
        }
        sql.push_str(" WHERE i.deleted_at_ms IS NULL");
        if pinboard_id.is_some() {
            sql.push_str(
                r#"
                AND pi_filter.pinboard_id = ?
                AND pb_filter.deleted_at_ms IS NULL
                "#,
            );
        }
        filter_params.extend(append_query_filters(&mut sql, query));
        let count =
            self.connection
                .query_row(&sql, params_from_iter(filter_params.iter()), |row| {
                    row.get::<_, i64>(0)
                })?;

        Ok(count)
    }

    fn active_source_app_count(&self) -> Result<i64> {
        let count = self.connection.query_row(
            r#"
            SELECT COUNT(DISTINCT i.source_app_id)
            FROM clipboard_items i
            WHERE i.deleted_at_ms IS NULL AND i.source_app_id IS NOT NULL
            "#,
            [],
            |row| row.get::<_, i64>(0),
        )?;

        Ok(count)
    }
}

fn append_query_filters(sql: &mut String, query: &ItemQuery) -> Vec<Value> {
    let mut params = Vec::new();

    if let Some(item_type) = query.item_type {
        sql.push_str(" AND i.type = ?");
        params.push(Value::Text(item_type.as_str().to_string()));
    }

    if let Some(source_app_id) = query.source_app_id.as_deref() {
        sql.push_str(" AND i.source_app_id = ?");
        params.push(Value::Text(source_app_id.to_string()));
    }

    if let Some(search_text) = query
        .search_text
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        sql.push_str(
            r#"
            AND (
                i.rowid IN (
                    SELECT rowid
                    FROM clipboard_items_fts
                    WHERE clipboard_items_fts MATCH ?
                )
                OR i.summary LIKE ? ESCAPE '\'
                OR COALESCE(i.primary_text, '') LIKE ? ESCAPE '\'
                OR COALESCE(s.name, i.source_app_name, '') LIKE ? ESCAPE '\'
            )
            "#,
        );
        params.push(Value::Text(make_fts_query(search_text)));
        let like_query = make_like_query(search_text);
        params.push(Value::Text(like_query.clone()));
        params.push(Value::Text(like_query.clone()));
        params.push(Value::Text(like_query));
    }

    params
}

fn active_item_exists(transaction: &Transaction<'_>, item_id: &str) -> rusqlite::Result<bool> {
    transaction
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM clipboard_items WHERE id = ?1 AND deleted_at_ms IS NULL)",
            params![item_id],
            |row| row.get::<_, i64>(0),
        )
        .map(|value| value == 1)
}

fn ensure_default_pinboard(transaction: &Transaction<'_>, now: i64) -> rusqlite::Result<()> {
    transaction.execute(
        r#"
        INSERT OR IGNORE INTO pinboards (
            id, title, system_kind, sort_order, color_code, created_at_ms, updated_at_ms
        )
        VALUES (?1, '固定', 'default_pins', 0, ?2, ?3, ?3)
        "#,
        params![DEFAULT_PINBOARD_ID, PINBOARD_COLOR_CODES[0], now],
    )?;
    Ok(())
}

fn ensure_active_pinboard(
    transaction: &Transaction<'_>,
    pinboard_id: &str,
    now: i64,
) -> rusqlite::Result<bool> {
    if pinboard_id == DEFAULT_PINBOARD_ID {
        ensure_default_pinboard(transaction, now)?;
    }

    transaction
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM pinboards WHERE id = ?1 AND deleted_at_ms IS NULL)",
            params![pinboard_id],
            |row| row.get::<_, i64>(0),
        )
        .map(|value| value == 1)
}

fn active_pinboard_exists(
    transaction: &Transaction<'_>,
    pinboard_id: &str,
) -> rusqlite::Result<bool> {
    transaction
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM pinboards WHERE id = ?1 AND deleted_at_ms IS NULL)",
            params![pinboard_id],
            |row| row.get::<_, i64>(0),
        )
        .map(|value| value == 1)
}

fn active_pinboard_summary(
    transaction: &Transaction<'_>,
    pinboard_id: &str,
) -> Result<PinboardSummary> {
    transaction
        .query_row(
            r#"
            SELECT
                p.id,
                p.title,
                p.color_code,
                p.sort_order,
                COUNT(i.id) AS item_count,
                p.created_at_ms,
                p.updated_at_ms
            FROM pinboards p
            LEFT JOIN pinboard_items pi ON pi.pinboard_id = p.id
            LEFT JOIN clipboard_items i ON i.id = pi.item_id AND i.deleted_at_ms IS NULL
            WHERE p.id = ?1 AND p.deleted_at_ms IS NULL
            GROUP BY p.id, p.title, p.color_code, p.sort_order, p.created_at_ms, p.updated_at_ms
            "#,
            params![pinboard_id],
            map_pinboard_summary,
        )
        .map_err(|_| invalid_pinboard_error(pinboard_id))
}

fn next_pinboard_sort_order(transaction: &Transaction<'_>) -> rusqlite::Result<i64> {
    transaction.query_row(
        "SELECT COALESCE(MAX(sort_order) + 1, 0) FROM pinboards WHERE deleted_at_ms IS NULL",
        [],
        |row| row.get::<_, i64>(0),
    )
}

fn next_pinboard_id(transaction: &Transaction<'_>, now: i64) -> rusqlite::Result<String> {
    for suffix in 0..1000 {
        let candidate = if suffix == 0 {
            format!("pinboard-{now}")
        } else {
            format!("pinboard-{now}-{suffix}")
        };
        let exists: i64 = transaction.query_row(
            "SELECT EXISTS(SELECT 1 FROM pinboards WHERE id = ?1)",
            params![candidate],
            |row| row.get(0),
        )?;
        if exists == 0 {
            return Ok(candidate);
        }
    }

    Ok(format!("pinboard-{now}-overflow"))
}

fn normalize_optional_pinboard_title(value: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        DEFAULT_PINBOARD_TITLE.to_string()
    } else {
        trimmed.to_string()
    }
}

fn normalize_required_pinboard_title(value: &str) -> Result<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "pinboard title must not be empty",
        ));
    }
    Ok(trimmed.to_string())
}

fn normalized_pinboard_color(value: Option<i64>, sort_order: i64) -> i64 {
    match value.filter(|color_code| *color_code > 0) {
        Some(color_code) => color_code,
        None => {
            let index = sort_order.rem_euclid(PINBOARD_COLOR_CODES.len() as i64) as usize;
            PINBOARD_COLOR_CODES[index]
        }
    }
}

fn invalid_pinboard_error(pinboard_id: &str) -> CoreError {
    CoreError::new(CoreErrorCode::InvalidInput, "pinboard does not exist")
        .with_detail("pinboard_id", pinboard_id)
}

fn next_pinboard_display_order(
    transaction: &Transaction<'_>,
    pinboard_id: &str,
) -> rusqlite::Result<i64> {
    transaction.query_row(
        "SELECT COALESCE(MAX(display_order) + 1, 0) FROM pinboard_items WHERE pinboard_id = ?1",
        params![pinboard_id],
        |row| row.get::<_, i64>(0),
    )
}

fn refresh_item_pin_cache(
    transaction: &Transaction<'_>,
    item_id: &str,
    now: i64,
) -> rusqlite::Result<()> {
    transaction.execute(
        r#"
        UPDATE clipboard_items
        SET
            is_pinned = CASE WHEN EXISTS (
                SELECT 1
                FROM pinboard_items pi_cache
                INNER JOIN pinboards pb_cache ON pb_cache.id = pi_cache.pinboard_id
                WHERE pi_cache.item_id = clipboard_items.id
                    AND pb_cache.deleted_at_ms IS NULL
            ) THEN 1 ELSE 0 END,
            updated_at_ms = ?1
        WHERE id = ?2 AND deleted_at_ms IS NULL
        "#,
        params![now, item_id],
    )?;
    Ok(())
}

fn make_fts_query(search_text: &str) -> String {
    let terms = search_text
        .split_whitespace()
        .map(|term| term.trim_matches(|character: char| character.is_ascii_punctuation()))
        .filter(|term| !term.is_empty())
        .take(8)
        .map(|term| format!("\"{}\"", term.replace('"', "\"\"")))
        .collect::<Vec<_>>();

    if terms.is_empty() {
        format!("\"{}\"", search_text.replace('"', "\"\""))
    } else {
        terms.join(" AND ")
    }
}

fn make_like_query(search_text: &str) -> String {
    let escaped = search_text
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_");
    format!("%{escaped}%")
}

fn map_item_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<ClipboardItemSummary> {
    let item_type = row.get::<_, String>(1)?;
    let source_confidence = row.get::<_, String>(11)?;
    let preview_state = row.get::<_, String>(17)?;
    let payload_state = row.get::<_, String>(18)?;
    let canonical_url = row.get::<_, Option<String>>(19)?;
    let link_metadata = match canonical_url {
        Some(canonical_url) => {
            let metadata_state = row.get::<_, Option<String>>(26)?;
            Some(LinkMetadataSummary {
                canonical_url,
                display_url: row.get(20)?,
                host: row.get(21)?,
                title: row.get(22)?,
                site_name: row.get(23)?,
                icon_asset_path: row.get(24)?,
                image_asset_path: row.get(25)?,
                metadata_state: LinkMetadataState::from_storage(
                    metadata_state.as_deref().unwrap_or("failed"),
                ),
                fetched_at_ms: row.get(27)?,
            })
        }
        None => None,
    };

    Ok(ClipboardItemSummary {
        id: row.get(0)?,
        item_type: ClipboardItemType::from_storage(&item_type),
        summary: row.get(2)?,
        primary_text: row.get(3)?,
        content_hash: row.get(4)?,
        source_app_id: row.get(5)?,
        source_app_name: row.get(6)?,
        source_app_icon_path: row.get(7)?,
        source_app_icon_header_color: row.get(8)?,
        preview_asset_path: row.get(9)?,
        payload_asset_path: row.get(10)?,
        source_confidence: SourceConfidence::from_storage(&source_confidence),
        first_copied_at_ms: row.get(12)?,
        last_copied_at_ms: row.get(13)?,
        copy_count: row.get(14)?,
        is_pinned: row.get::<_, i64>(15)? == 1,
        size_bytes: row.get(16)?,
        preview_state: PreviewState::from_storage(&preview_state),
        payload_state: PayloadState::from_storage(&payload_state),
        file_items: Vec::new(),
        link_metadata,
    })
}

fn map_source_app_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<SourceAppSummary> {
    Ok(SourceAppSummary {
        id: row.get(0)?,
        bundle_id: row.get(1)?,
        name: row.get(2)?,
        icon_path: row.get(3)?,
        icon_header_color: row.get(4)?,
        item_count: row.get(5)?,
        last_copied_at_ms: row.get(6)?,
    })
}

fn map_pinboard_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<PinboardSummary> {
    Ok(PinboardSummary {
        id: row.get(0)?,
        title: row.get(1)?,
        color_code: row.get(2)?,
        sort_order: row.get(3)?,
        item_count: row.get(4)?,
        created_at_ms: row.get(5)?,
        updated_at_ms: row.get(6)?,
    })
}

#[cfg(test)]
mod tests {
    use super::{make_fts_query, make_like_query};

    #[test]
    fn make_fts_query_joins_normalized_terms() {
        assert_eq!(make_fts_query(" alpha  beta... "), "\"alpha\" AND \"beta\"");
    }

    #[test]
    fn make_like_query_escapes_sql_wildcards() {
        assert_eq!(make_like_query("100%_done\\"), "%100\\%\\_done\\\\%");
    }
}
