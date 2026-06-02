use anyhow::{anyhow, Result};
use sha2::{Digest, Sha256};
use sqlx::{Row, SqlitePool};

use crate::db;

pub const MIGRATION_VERSION: i64 = 1;

const MIGRATION_SQL: &str = r#"
CREATE TABLE IF NOT EXISTS sync_groups (
    id TEXT PRIMARY KEY,
    created_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS devices (
    id TEXT PRIMARY KEY,
    sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
    name TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE,
    created_at_ms INTEGER NOT NULL,
    revoked_at_ms INTEGER
);

CREATE TABLE IF NOT EXISTS pairing_codes (
    code_hash TEXT PRIMARY KEY,
    sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
    created_by_device_id TEXT NOT NULL REFERENCES devices(id),
    created_at_ms INTEGER NOT NULL,
    expires_at_ms INTEGER NOT NULL,
    consumed_at_ms INTEGER,
    consumed_by_device_id TEXT REFERENCES devices(id)
);

CREATE TABLE IF NOT EXISTS sync_items (
    sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
    content_hash TEXT NOT NULL,
    item_type TEXT,
    payload_json TEXT,
    copy_count INTEGER NOT NULL DEFAULT 0,
    deleted_at_ms INTEGER,
    updated_at_ms INTEGER NOT NULL,
    last_server_seq INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(sync_group_id, content_hash)
);

CREATE TABLE IF NOT EXISTS sync_events (
    server_seq INTEGER PRIMARY KEY AUTOINCREMENT,
    sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
    device_id TEXT NOT NULL REFERENCES devices(id),
    client_event_id TEXT NOT NULL,
    event_type TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    item_type TEXT,
    payload_json TEXT,
    copy_count_delta INTEGER,
    created_at_ms INTEGER NOT NULL,
    UNIQUE(device_id, client_event_id)
);

CREATE TABLE IF NOT EXISTS sync_assets (
    sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
    digest TEXT NOT NULL,
    kind TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size_bytes INTEGER NOT NULL,
    path TEXT NOT NULL,
    created_by_device_id TEXT NOT NULL REFERENCES devices(id),
    created_at_ms INTEGER NOT NULL,
    PRIMARY KEY(sync_group_id, digest)
);

CREATE TABLE IF NOT EXISTS sync_item_assets (
    sync_group_id TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    asset_digest TEXT NOT NULL,
    role TEXT NOT NULL,
    PRIMARY KEY(sync_group_id, content_hash, asset_digest, role),
    FOREIGN KEY(sync_group_id, content_hash) REFERENCES sync_items(sync_group_id, content_hash),
    FOREIGN KEY(sync_group_id, asset_digest) REFERENCES sync_assets(sync_group_id, digest)
);

CREATE TABLE IF NOT EXISTS device_p2p_endpoints (
    sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
    device_id TEXT NOT NULL REFERENCES devices(id),
    endpoint_id TEXT NOT NULL,
    relay_url TEXT,
    direct_addresses_json TEXT NOT NULL,
    capabilities_json TEXT NOT NULL,
    quality_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    expires_at_ms INTEGER NOT NULL,
    PRIMARY KEY(sync_group_id, device_id)
);

CREATE TABLE IF NOT EXISTS asset_providers (
    sync_group_id TEXT NOT NULL REFERENCES sync_groups(id),
    asset_id TEXT NOT NULL,
    device_id TEXT NOT NULL REFERENCES devices(id),
    kind TEXT NOT NULL,
    byte_count INTEGER,
    mime_type TEXT,
    availability TEXT NOT NULL,
    quality_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    expires_at_ms INTEGER NOT NULL,
    PRIMARY KEY(sync_group_id, asset_id, device_id)
);

CREATE TABLE IF NOT EXISTS sync_file_items (
    sync_group_id TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    file_name TEXT,
    file_size INTEGER,
    uti TEXT,
    PRIMARY KEY(sync_group_id, content_hash),
    FOREIGN KEY(sync_group_id, content_hash) REFERENCES sync_items(sync_group_id, content_hash)
);

CREATE TABLE IF NOT EXISTS sync_link_metadata (
    sync_group_id TEXT NOT NULL,
    content_hash TEXT NOT NULL,
    url TEXT,
    title TEXT,
    description TEXT,
    preview_asset_digest TEXT,
    PRIMARY KEY(sync_group_id, content_hash),
    FOREIGN KEY(sync_group_id, content_hash) REFERENCES sync_items(sync_group_id, content_hash),
    FOREIGN KEY(sync_group_id, preview_asset_digest) REFERENCES sync_assets(sync_group_id, digest)
);

CREATE INDEX IF NOT EXISTS idx_pairing_codes_group ON pairing_codes(sync_group_id);
CREATE INDEX IF NOT EXISTS idx_sync_events_group_seq ON sync_events(sync_group_id, server_seq);
CREATE INDEX IF NOT EXISTS idx_sync_events_content_hash ON sync_events(sync_group_id, content_hash);
CREATE INDEX IF NOT EXISTS idx_sync_items_deleted_at ON sync_items(sync_group_id, deleted_at_ms);
CREATE INDEX IF NOT EXISTS idx_device_p2p_endpoints_group_expires ON device_p2p_endpoints(sync_group_id, expires_at_ms);
CREATE INDEX IF NOT EXISTS idx_device_p2p_endpoints_endpoint_id ON device_p2p_endpoints(endpoint_id);
CREATE INDEX IF NOT EXISTS idx_asset_providers_asset_expires ON asset_providers(sync_group_id, asset_id, expires_at_ms);
CREATE INDEX IF NOT EXISTS idx_asset_providers_device ON asset_providers(sync_group_id, device_id);
"#;

pub fn migration_checksum() -> String {
    let digest = Sha256::digest(MIGRATION_SQL.as_bytes());
    hex::encode(digest)
}

pub async fn migrate(pool: &SqlitePool) -> Result<()> {
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS sync_schema_migrations (
            version INTEGER PRIMARY KEY,
            checksum TEXT NOT NULL,
            applied_at_ms INTEGER NOT NULL
        )",
    )
    .execute(pool)
    .await?;

    if let Some(row) = sqlx::query("SELECT checksum FROM sync_schema_migrations WHERE version = ?")
        .bind(MIGRATION_VERSION)
        .fetch_optional(pool)
        .await?
    {
        let stored: String = row.try_get("checksum")?;
        let expected = migration_checksum();
        if stored != expected {
            return Err(anyhow!("migration checksum mismatch for version 1"));
        }
        return Ok(());
    }

    let mut tx = pool.begin().await?;
    for statement in MIGRATION_SQL.split(';') {
        let trimmed = statement.trim();
        if !trimmed.is_empty() {
            sqlx::query(trimmed).execute(&mut *tx).await?;
        }
    }
    sqlx::query(
        "INSERT INTO sync_schema_migrations(version, checksum, applied_at_ms) VALUES (?, ?, ?)",
    )
    .bind(MIGRATION_VERSION)
    .bind(migration_checksum())
    .bind(db::now_ms().await)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(())
}
