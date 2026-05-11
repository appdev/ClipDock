use crate::domain::{
    ClipboardItemSummary, ClipboardItemType, ItemManagementResult, ItemPage, ItemQuery,
    PageRequest, PreviewState, SourceAppPage, SourceAppSummary, SourceConfidence,
};
use crate::error::Result;
use crate::time::now_ms;
use rusqlite::types::Value;
use rusqlite::{params, params_from_iter};

use super::support::normalize_item_id;
use super::ClipboardCore;

impl ClipboardCore {
    pub fn list_items(&self, query: ItemQuery, page: PageRequest) -> Result<ItemPage> {
        let page = page.normalized();
        let total_count = self.active_item_count(&query)?;
        let mut sql = String::from(
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
                i.is_pinned,
                i.size_bytes,
                i.preview_state
            FROM clipboard_items i
            LEFT JOIN source_apps s ON s.id = i.source_app_id
            LEFT JOIN source_app_icons ic ON ic.source_app_id = s.id
            WHERE i.deleted_at_ms IS NULL
            "#,
        );

        let mut filter_params = append_query_filters(&mut sql, &query);
        sql.push_str(" ORDER BY i.is_pinned DESC, i.last_copied_at_ms DESC LIMIT ? OFFSET ?");
        filter_params.push(Value::Integer(page.limit));
        filter_params.push(Value::Integer(page.offset));

        let mut statement = self.connection.prepare(&sql)?;
        let rows = statement.query_map(params_from_iter(filter_params.iter()), map_item_summary)?;

        let items = rows.collect::<std::result::Result<Vec<_>, _>>()?;
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
        let rows = statement.query_map(params![page.limit, page.offset], map_source_app_summary)?;
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

    pub fn set_item_pinned(
        &mut self,
        item_id: impl AsRef<str>,
        is_pinned: bool,
    ) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE clipboard_items
            SET is_pinned = ?1, updated_at_ms = ?2
            WHERE id = ?3 AND deleted_at_ms IS NULL
            "#,
            params![if is_pinned { 1 } else { 0 }, now, item_id],
        )? as i64;

        Ok(ItemManagementResult { affected_count })
    }

    pub fn delete_item(&mut self, item_id: impl AsRef<str>) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE clipboard_items
            SET deleted_at_ms = ?1, updated_at_ms = ?1
            WHERE id = ?2 AND deleted_at_ms IS NULL
            "#,
            params![now, item_id],
        )? as i64;

        Ok(ItemManagementResult { affected_count })
    }

    pub fn clear_items(&mut self, query: ItemQuery) -> Result<ItemManagementResult> {
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
                    AND i.is_pinned = 0
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

        Ok(ItemManagementResult { affected_count })
    }

    pub(super) fn active_item_count(&self, query: &ItemQuery) -> Result<i64> {
        let mut sql = String::from(
            r#"
            SELECT COUNT(*)
            FROM clipboard_items i
            LEFT JOIN source_apps s ON s.id = i.source_app_id
            WHERE i.deleted_at_ms IS NULL
            "#,
        );
        let filter_params = append_query_filters(&mut sql, query);
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
    let source_confidence = row.get::<_, String>(10)?;
    let preview_state = row.get::<_, String>(16)?;

    Ok(ClipboardItemSummary {
        id: row.get(0)?,
        item_type: ClipboardItemType::from_storage(&item_type),
        summary: row.get(2)?,
        primary_text: row.get(3)?,
        content_hash: row.get(4)?,
        source_app_id: row.get(5)?,
        source_app_name: row.get(6)?,
        source_app_icon_path: row.get(7)?,
        preview_asset_path: row.get(8)?,
        payload_asset_path: row.get(9)?,
        source_confidence: SourceConfidence::from_storage(&source_confidence),
        first_copied_at_ms: row.get(11)?,
        last_copied_at_ms: row.get(12)?,
        copy_count: row.get(13)?,
        is_pinned: row.get::<_, i64>(14)? == 1,
        size_bytes: row.get(15)?,
        preview_state: PreviewState::from_storage(&preview_state),
    })
}

fn map_source_app_summary(row: &rusqlite::Row<'_>) -> rusqlite::Result<SourceAppSummary> {
    Ok(SourceAppSummary {
        id: row.get(0)?,
        bundle_id: row.get(1)?,
        name: row.get(2)?,
        icon_path: row.get(3)?,
        item_count: row.get(4)?,
        last_copied_at_ms: row.get(5)?,
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
