use axum::http::Method;
use clipdock_sync_server::{config::Config, db, migrations};
use sqlx::Row;

mod common;

use common::TestServer;

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
