use axum::http::Method;
use clipdock_sync_server::{config::Config, db, migrations};
use sqlx::Row;

mod common;

use common::TestServer;

#[tokio::test]
async fn fresh_migration_applies_v1_to_v4() {
    let temp_dir = tempfile::tempdir().expect("temp dir");
    let config = Config::for_tests(temp_dir.path());
    let pool = db::connect(&config).await.expect("connect");

    migrations::migrate(&pool).await.expect("migrate");

    let versions = sqlx::query("SELECT version FROM sync_schema_migrations ORDER BY version")
        .fetch_all(&pool)
        .await
        .expect("migration versions")
        .into_iter()
        .map(|row| row.get::<i64, _>("version"))
        .collect::<Vec<_>>();
    assert_eq!(versions, vec![1, 2, 3, 4]);

    let sync_state_table_exists = sqlx::query(
        "SELECT COUNT(*) AS count FROM sqlite_master WHERE type = 'table' AND name = 'device_sync_state'",
    )
    .fetch_one(&pool)
    .await
    .expect("device_sync_state exists")
    .get::<i64, _>("count");
    assert_eq!(sync_state_table_exists, 1);

    let empty_since_column_exists = sqlx::query(
        "SELECT COUNT(*) AS count FROM pragma_table_info('sync_groups') WHERE name = 'empty_since_ms'",
    )
    .fetch_one(&pool)
    .await
    .expect("empty_since_ms column exists")
    .get::<i64, _>("count");
    assert_eq!(empty_since_column_exists, 1);

    let trigger_count = sqlx::query(
        "SELECT COUNT(*) AS count
         FROM sqlite_master
         WHERE type = 'trigger' AND name IN (
             'sync_groups_mark_empty_after_insert',
             'devices_clear_empty_after_insert',
             'devices_mark_empty_after_delete',
             'devices_mark_empty_after_revoke',
             'devices_clear_empty_after_unrevoke'
         )",
    )
    .fetch_one(&pool)
    .await
    .expect("empty-space triggers exist")
    .get::<i64, _>("count");
    assert_eq!(trigger_count, 5);

    let asset_dimension_columns = sqlx::query(
        "SELECT COUNT(*) AS count
         FROM pragma_table_info('sync_assets')
         WHERE name IN ('width_px', 'height_px')",
    )
    .fetch_one(&pool)
    .await
    .expect("asset dimension columns exist")
    .get::<i64, _>("count");
    assert_eq!(asset_dimension_columns, 2);

    let thumbnail_unique_index = sqlx::query(
        "SELECT COUNT(*) AS count
         FROM sqlite_master
         WHERE type = 'index' AND name = 'ux_sync_item_assets_one_thumbnail_per_item'",
    )
    .fetch_one(&pool)
    .await
    .expect("thumbnail unique index exists")
    .get::<i64, _>("count");
    assert_eq!(thumbnail_unique_index, 1);
}

#[tokio::test]
async fn v1_database_upgrades_to_v4() {
    let temp_dir = tempfile::tempdir().expect("temp dir");
    let config = Config::for_tests(temp_dir.path());
    let pool = db::connect(&config).await.expect("connect");
    sqlx::query(
        "CREATE TABLE sync_schema_migrations (
            version INTEGER PRIMARY KEY,
            checksum TEXT NOT NULL,
            applied_at_ms INTEGER NOT NULL
        )",
    )
    .execute(&pool)
    .await
    .expect("create migrations table");
    sqlx::query(
        "INSERT INTO sync_schema_migrations(version, checksum, applied_at_ms)
         VALUES (1, ?, 1)",
    )
    .bind(migrations::migration_checksum())
    .execute(&pool)
    .await
    .expect("insert v1 checksum");
    sqlx::query("CREATE TABLE sync_groups (id TEXT PRIMARY KEY, created_at_ms INTEGER NOT NULL)")
        .execute(&pool)
        .await
        .expect("create v1 table subset");
    sqlx::query(
        "CREATE TABLE devices (
            id TEXT PRIMARY KEY,
            sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
            name TEXT NOT NULL,
            token_hash TEXT NOT NULL UNIQUE,
            created_at_ms INTEGER NOT NULL,
            revoked_at_ms INTEGER
        )",
    )
    .execute(&pool)
    .await
    .expect("create devices table");
    sqlx::query(
        "CREATE TABLE sync_items (
            sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
            content_hash TEXT NOT NULL,
            item_type TEXT,
            payload_json TEXT,
            copy_count INTEGER NOT NULL DEFAULT 0,
            deleted_at_ms INTEGER,
            updated_at_ms INTEGER NOT NULL,
            last_server_seq INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY(sync_group_id, content_hash)
        )",
    )
    .execute(&pool)
    .await
    .expect("create sync_items table");
    sqlx::query(
        "CREATE TABLE sync_assets (
            sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
            digest TEXT NOT NULL,
            kind TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size_bytes INTEGER NOT NULL,
            path TEXT NOT NULL,
            created_by_device_id TEXT NOT NULL REFERENCES devices(id),
            created_at_ms INTEGER NOT NULL,
            PRIMARY KEY(sync_group_id, digest)
        )",
    )
    .execute(&pool)
    .await
    .expect("create sync_assets table");
    sqlx::query(
        "CREATE TABLE sync_item_assets (
            sync_group_id TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            asset_digest TEXT NOT NULL,
            role TEXT NOT NULL,
            PRIMARY KEY(sync_group_id, content_hash, asset_digest, role)
        )",
    )
    .execute(&pool)
    .await
    .expect("create sync_item_assets table");

    migrations::migrate(&pool).await.expect("upgrade to v4");

    let versions = sqlx::query("SELECT version FROM sync_schema_migrations ORDER BY version")
        .fetch_all(&pool)
        .await
        .expect("migration versions")
        .into_iter()
        .map(|row| row.get::<i64, _>("version"))
        .collect::<Vec<_>>();
    assert_eq!(versions, vec![1, 2, 3, 4]);
}

#[tokio::test]
async fn migration_checksum_mismatch_is_rejected() {
    let temp_dir = tempfile::tempdir().expect("temp dir");
    let config = Config::for_tests(temp_dir.path());
    let pool = db::connect(&config).await.expect("connect");
    sqlx::query(
        "CREATE TABLE sync_schema_migrations (
            version INTEGER PRIMARY KEY,
            checksum TEXT NOT NULL,
            applied_at_ms INTEGER NOT NULL
        )",
    )
    .execute(&pool)
    .await
    .expect("create migrations table");
    sqlx::query(
        "INSERT INTO sync_schema_migrations(version, checksum, applied_at_ms)
         VALUES (1, 'wrong', 1)",
    )
    .execute(&pool)
    .await
    .expect("insert bad checksum");

    let error = migrations::migrate(&pool)
        .await
        .expect_err("checksum mismatch");
    assert!(error.to_string().contains("migration checksum mismatch"));
}

#[tokio::test]
async fn sqlite_pragmas_enable_wal_and_foreign_keys() {
    let server = TestServer::new().await;
    let journal_mode = sqlx::query("PRAGMA journal_mode")
        .fetch_one(&server.pool)
        .await
        .expect("journal mode")
        .get::<String, _>("journal_mode");
    assert_eq!(journal_mode.to_lowercase(), "wal");

    let foreign_keys = sqlx::query("PRAGMA foreign_keys")
        .fetch_one(&server.pool)
        .await
        .expect("foreign keys")
        .get::<i64, _>("foreign_keys");
    assert_eq!(foreign_keys, 1);

    let health = server.empty(Method::GET, "/health", None).await;
    assert_eq!(health.status, axum::http::StatusCode::OK);
}
