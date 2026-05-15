use crate::domain::{
    CompleteLinkMetadataFetchRequest, ItemManagementResult, LinkMetadataFetchCandidate,
};
use crate::error::Result;
use crate::time::now_ms;
use rusqlite::params;

use super::support::{normalize_item_id, normalize_relative_asset_path};
use super::ClipboardCore;

impl ClipboardCore {
    pub fn claim_link_metadata_fetch_batch(
        &mut self,
        limit: i64,
        lease_timeout_ms: i64,
    ) -> Result<Vec<LinkMetadataFetchCandidate>> {
        let limit = limit.clamp(1, 20);
        let lease_timeout_ms = lease_timeout_ms.max(1);
        let now = now_ms();
        let stale_before_ms = now.saturating_sub(lease_timeout_ms);
        let transaction = self.connection.transaction()?;

        let mut candidates = {
            let mut statement = transaction.prepare(
                r#"
                SELECT
                    lm.item_id,
                    lm.canonical_url,
                    lm.display_url,
                    lm.host,
                    lm.fetch_attempts
                FROM link_metadata lm
                INNER JOIN clipboard_items i ON i.id = lm.item_id
                WHERE i.deleted_at_ms IS NULL
                    AND (
                        lm.metadata_state IN ('pending', 'stale')
                        OR (
                            lm.metadata_state = 'failed'
                            AND lm.next_retry_at_ms IS NOT NULL
                            AND lm.next_retry_at_ms <= ?1
                        )
                        OR (
                            lm.metadata_state = 'fetching'
                            AND lm.last_requested_at_ms IS NOT NULL
                            AND lm.last_requested_at_ms <= ?2
                        )
                    )
                ORDER BY i.last_copied_at_ms DESC, lm.updated_at_ms ASC
                LIMIT ?3
                "#,
            )?;
            let rows = statement.query_map(params![now, stale_before_ms, limit], |row| {
                Ok(LinkMetadataFetchCandidate {
                    item_id: row.get(0)?,
                    canonical_url: row.get(1)?,
                    display_url: row.get(2)?,
                    host: row.get(3)?,
                    fetch_attempts: row.get(4)?,
                    lease_started_at_ms: now,
                })
            })?;
            rows.collect::<rusqlite::Result<Vec<_>>>()?
        };

        for candidate in &mut candidates {
            let affected_count = transaction.execute(
                r#"
                UPDATE link_metadata
                SET metadata_state = 'fetching',
                    last_requested_at_ms = ?1,
                    fetch_attempts = fetch_attempts + 1,
                    updated_at_ms = ?1
                WHERE item_id = ?2
                    AND metadata_state IN ('pending', 'stale', 'failed', 'fetching')
                "#,
                params![now, candidate.item_id],
            )?;
            if affected_count == 0 {
                candidate.lease_started_at_ms = 0;
            }
        }
        candidates.retain(|candidate| candidate.lease_started_at_ms > 0);

        transaction.commit()?;
        Ok(candidates)
    }

    pub fn complete_link_metadata_fetch(
        &mut self,
        request: CompleteLinkMetadataFetchRequest,
    ) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(&request.item_id)?;
        let canonical_url = non_empty_or(request.canonical_url, "");
        let display_url = non_empty_or(request.display_url, &canonical_url);
        let host = non_empty_or(request.host, "");
        let icon_relative_path = normalize_optional_asset_path(request.icon_relative_path)?;
        let image_relative_path = normalize_optional_asset_path(request.image_relative_path)?;
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE link_metadata
            SET canonical_url = ?1,
                display_url = ?2,
                host = ?3,
                title = ?4,
                site_name = ?5,
                icon_relative_path = ?6,
                image_relative_path = ?7,
                metadata_state = 'ready',
                failure_code = NULL,
                fetched_at_ms = ?8,
                next_retry_at_ms = NULL,
                updated_at_ms = ?8
            WHERE item_id = ?9
                AND metadata_state = 'fetching'
                AND last_requested_at_ms = ?10
            "#,
            params![
                canonical_url,
                display_url,
                host,
                optional_non_empty(request.title),
                optional_non_empty(request.site_name),
                icon_relative_path,
                image_relative_path,
                now,
                item_id,
                request.lease_started_at_ms
            ],
        )? as i64;

        Ok(ItemManagementResult { affected_count })
    }

    pub fn fail_link_metadata_fetch(
        &mut self,
        item_id: impl AsRef<str>,
        lease_started_at_ms: i64,
        failure_code: impl AsRef<str>,
        next_retry_at_ms: Option<i64>,
    ) -> Result<ItemManagementResult> {
        let item_id = normalize_item_id(item_id.as_ref())?;
        let failure_code = non_empty_or(failure_code.as_ref().to_string(), "provider_error");
        let now = now_ms();
        let affected_count = self.connection.execute(
            r#"
            UPDATE link_metadata
            SET metadata_state = 'failed',
                failure_code = ?1,
                next_retry_at_ms = ?2,
                updated_at_ms = ?3
            WHERE item_id = ?4
                AND metadata_state = 'fetching'
                AND last_requested_at_ms = ?5
            "#,
            params![
                failure_code,
                next_retry_at_ms.filter(|value| *value > 0),
                now,
                item_id,
                lease_started_at_ms
            ],
        )? as i64;

        Ok(ItemManagementResult { affected_count })
    }
}

fn optional_non_empty(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim();
        (!trimmed.is_empty()).then(|| trimmed.to_string())
    })
}

fn normalize_optional_asset_path(value: Option<String>) -> Result<Option<String>> {
    value
        .map(|value| normalize_relative_asset_path(&value))
        .transpose()
}

fn non_empty_or(value: String, fallback: &str) -> String {
    let value = value.trim();
    if value.is_empty() {
        fallback.to_string()
    } else {
        value.to_string()
    }
}
