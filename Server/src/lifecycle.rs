use std::time::Duration;

use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::{assets::AssetStore, db};

pub const EMPTY_SPACE_RETENTION_MS: i64 = 10 * 24 * 60 * 60 * 1000;
const EMPTY_SPACE_CLEANUP_INTERVAL: Duration = Duration::from_secs(60 * 60);

pub async fn run_empty_space_cleanup_loop(pool: SqlitePool, assets: AssetStore) {
    loop {
        match run_empty_space_cleanup_once(&pool, &assets).await {
            Ok(deleted) if deleted > 0 => {
                eprintln!("Deleted {deleted} empty ClipDock sync space(s)");
            }
            Ok(_) => {}
            Err(error) => {
                eprintln!("Empty sync-space cleanup failed: {error}");
            }
        }
        tokio::time::sleep(EMPTY_SPACE_CLEANUP_INTERVAL).await;
    }
}

pub async fn run_empty_space_cleanup_once(pool: &SqlitePool, assets: &AssetStore) -> Result<usize> {
    let now = db::now_ms().await;
    run_empty_space_cleanup_once_at(pool, assets, now).await
}

pub async fn run_empty_space_cleanup_once_at(
    pool: &SqlitePool,
    assets: &AssetStore,
    now_ms: i64,
) -> Result<usize> {
    reconcile_empty_sync_groups_at(pool, now_ms).await?;

    let cutoff_ms = now_ms - EMPTY_SPACE_RETENTION_MS;
    let sync_group_ids = expired_empty_sync_groups(pool, cutoff_ms).await?;
    let mut deleted = 0_usize;
    for sync_group_id in sync_group_ids {
        if delete_sync_group_data(pool, &sync_group_id).await? {
            assets.delete_sync_group_objects(&sync_group_id).await?;
            deleted += 1;
        }
    }
    Ok(deleted)
}

pub async fn reconcile_empty_sync_groups(pool: &SqlitePool) -> Result<()> {
    let now = db::now_ms().await;
    reconcile_empty_sync_groups_at(pool, now).await
}

pub async fn reconcile_empty_sync_groups_at(pool: &SqlitePool, now_ms: i64) -> Result<()> {
    sqlx::query(
        "UPDATE sync_groups
         SET empty_since_ms = ?
         WHERE empty_since_ms IS NULL
           AND NOT EXISTS (
               SELECT 1
               FROM devices
               WHERE devices.sync_group_id = sync_groups.id
                 AND devices.revoked_at_ms IS NULL
           )",
    )
    .bind(now_ms)
    .execute(pool)
    .await?;

    sqlx::query(
        "UPDATE sync_groups
         SET empty_since_ms = NULL
         WHERE empty_since_ms IS NOT NULL
           AND EXISTS (
               SELECT 1
               FROM devices
               WHERE devices.sync_group_id = sync_groups.id
                 AND devices.revoked_at_ms IS NULL
           )",
    )
    .execute(pool)
    .await?;

    Ok(())
}

async fn expired_empty_sync_groups(pool: &SqlitePool, cutoff_ms: i64) -> Result<Vec<String>> {
    let rows = sqlx::query(
        "SELECT id
         FROM sync_groups
         WHERE empty_since_ms IS NOT NULL
           AND empty_since_ms <= ?
           AND NOT EXISTS (
               SELECT 1
               FROM devices
               WHERE devices.sync_group_id = sync_groups.id
                 AND devices.revoked_at_ms IS NULL
           )
         ORDER BY empty_since_ms ASC",
    )
    .bind(cutoff_ms)
    .fetch_all(pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|row| row.get::<String, _>("id"))
        .collect())
}

async fn delete_sync_group_data(pool: &SqlitePool, sync_group_id: &str) -> Result<bool> {
    let mut tx = pool.begin().await?;
    let active_devices = sqlx::query(
        "SELECT COUNT(*) AS count
         FROM devices
         WHERE sync_group_id = ? AND revoked_at_ms IS NULL",
    )
    .bind(sync_group_id)
    .fetch_one(&mut *tx)
    .await?
    .get::<i64, _>("count");
    if active_devices > 0 {
        tx.commit().await?;
        return Ok(false);
    }

    for table in [
        "sync_link_metadata",
        "sync_file_items",
        "sync_item_assets",
        "device_sync_state",
        "device_p2p_endpoints",
        "asset_providers",
        "sync_events",
        "sync_assets",
        "sync_items",
        "pairing_codes",
        "devices",
    ] {
        let statement = format!("DELETE FROM {table} WHERE sync_group_id = ?");
        sqlx::query(&statement)
            .bind(sync_group_id)
            .execute(&mut *tx)
            .await?;
    }

    let deleted = sqlx::query("DELETE FROM sync_groups WHERE id = ?")
        .bind(sync_group_id)
        .execute(&mut *tx)
        .await?
        .rows_affected();

    tx.commit().await?;
    Ok(deleted > 0)
}
