mod common;

use std::path::Path;

use axum::http::{Method, StatusCode};
use clipdock_sync_server::lifecycle::{self, EMPTY_SPACE_RETENTION_MS};
use common::{asset_digest, content_hash, upsert_event, TestServer};
use sqlx::{Row, SqlitePool};

#[tokio::test]
async fn empty_since_tracks_active_device_count() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;

    assert_eq!(empty_since_ms(&server.pool, &sync.sync_id).await, None);

    sqlx::query("UPDATE devices SET revoked_at_ms = ? WHERE id = ?")
        .bind(1_i64)
        .bind(&sync.device.id)
        .execute(&server.pool)
        .await
        .expect("revoke device");

    assert!(empty_since_ms(&server.pool, &sync.sync_id).await.is_some());

    sqlx::query("UPDATE devices SET revoked_at_ms = NULL WHERE id = ?")
        .bind(&sync.device.id)
        .execute(&server.pool)
        .await
        .expect("unrevoke device");

    assert_eq!(empty_since_ms(&server.pool, &sync.sync_id).await, None);
}

#[tokio::test]
async fn cleanup_keeps_empty_space_before_ten_day_retention() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let empty_since_ms = 10_000_i64;

    sqlx::query("UPDATE devices SET revoked_at_ms = ? WHERE id = ?")
        .bind(empty_since_ms)
        .bind(&sync.device.id)
        .execute(&server.pool)
        .await
        .expect("revoke device");
    sqlx::query("UPDATE sync_groups SET empty_since_ms = ? WHERE id = ?")
        .bind(empty_since_ms)
        .bind(&sync.sync_id)
        .execute(&server.pool)
        .await
        .expect("backdate empty marker");

    let deleted = lifecycle::run_empty_space_cleanup_once_at(
        &server.pool,
        &server.assets,
        empty_since_ms + EMPTY_SPACE_RETENTION_MS - 1,
    )
    .await
    .expect("cleanup before retention");

    assert_eq!(deleted, 0);
    assert_eq!(
        count_rows(&server.pool, "sync_groups", "id", &sync.sync_id).await,
        1
    );
}

#[tokio::test]
async fn cleanup_deletes_expired_empty_space_database_rows_and_assets() {
    let server = TestServer::new().await;
    let sync = server.create_sync().await;
    let content_hash = content_hash("expired-space-item");
    let asset_bytes = b"expired space thumbnail".to_vec();
    let digest = asset_digest(&asset_bytes);

    let push = server
        .json(
            Method::POST,
            "/v2/events",
            Some(&sync.device.token),
            upsert_event("cleanup-upsert", &content_hash, 1),
            &[],
        )
        .await;
    assert_eq!(push.status, StatusCode::OK, "{:?}", push.body);

    let asset_uri = format!("/v2/assets/{digest}");
    let upload = server
        .raw(
            Method::PUT,
            &asset_uri,
            Some(&sync.device.token),
            asset_bytes.clone(),
            &[
                ("content-type", "image/png"),
                ("x-clipdock-asset-kind", "thumbnail"),
            ],
        )
        .await;
    assert_eq!(upload.status, StatusCode::OK, "{:?}", upload.body);

    sqlx::query(
        "INSERT INTO sync_item_assets(sync_group_id, content_hash, asset_digest, role)
         VALUES (?, ?, ?, 'thumbnail')",
    )
    .bind(&sync.sync_id)
    .bind(&content_hash)
    .bind(&digest)
    .execute(&server.pool)
    .await
    .expect("insert item asset link");
    sqlx::query(
        "INSERT INTO sync_file_items(sync_group_id, content_hash, file_name, file_size, uti)
         VALUES (?, ?, 'cleanup.png', ?, 'public.png')",
    )
    .bind(&sync.sync_id)
    .bind(&content_hash)
    .bind(asset_bytes.len() as i64)
    .execute(&server.pool)
    .await
    .expect("insert file metadata");
    sqlx::query(
        "INSERT INTO sync_link_metadata(sync_group_id, content_hash, url, title, description, preview_asset_digest)
         VALUES (?, ?, 'https://example.com', 'Cleanup', 'Expired space', ?)",
    )
    .bind(&sync.sync_id)
    .bind(&content_hash)
    .bind(&digest)
    .execute(&server.pool)
    .await
    .expect("insert link metadata");
    sqlx::query(
        "INSERT INTO device_sync_state(sync_group_id, device_id, last_acked_seq, updated_at_ms)
         VALUES (?, ?, 1, 1)",
    )
    .bind(&sync.sync_id)
    .bind(&sync.device.id)
    .execute(&server.pool)
    .await
    .expect("insert sync state");
    sqlx::query(
        "INSERT INTO device_p2p_endpoints(
             sync_group_id, device_id, endpoint_id, relay_url, direct_addresses_json,
             capabilities_json, quality_json, updated_at_ms, expires_at_ms
         ) VALUES (?, ?, 'endpoint-cleanup', NULL, '[]', '{}', '{}', 1, 2)",
    )
    .bind(&sync.sync_id)
    .bind(&sync.device.id)
    .execute(&server.pool)
    .await
    .expect("insert p2p endpoint");
    sqlx::query(
        "INSERT INTO asset_providers(
             sync_group_id, asset_id, device_id, kind, byte_count, mime_type,
             availability, quality_json, updated_at_ms, expires_at_ms
         ) VALUES (?, ?, ?, 'thumbnail', ?, 'image/png', 'online', '{}', 1, 2)",
    )
    .bind(&sync.sync_id)
    .bind(&digest)
    .bind(&sync.device.id)
    .bind(asset_bytes.len() as i64)
    .execute(&server.pool)
    .await
    .expect("insert asset provider");

    let asset_path = sqlx::query("SELECT path FROM sync_assets WHERE sync_group_id = ?")
        .bind(&sync.sync_id)
        .fetch_one(&server.pool)
        .await
        .expect("asset path")
        .get::<String, _>("path");
    assert!(Path::new(&asset_path).exists());

    let now_ms = 2_000_000_000_i64;
    let empty_since_ms = now_ms - EMPTY_SPACE_RETENTION_MS - 1;
    sqlx::query("UPDATE devices SET revoked_at_ms = ? WHERE id = ?")
        .bind(empty_since_ms)
        .bind(&sync.device.id)
        .execute(&server.pool)
        .await
        .expect("revoke last device");
    sqlx::query("UPDATE sync_groups SET empty_since_ms = ? WHERE id = ?")
        .bind(empty_since_ms)
        .bind(&sync.sync_id)
        .execute(&server.pool)
        .await
        .expect("backdate empty marker");

    let deleted = lifecycle::run_empty_space_cleanup_once_at(&server.pool, &server.assets, now_ms)
        .await
        .expect("cleanup expired empty space");

    assert_eq!(deleted, 1);
    for table in [
        "pairing_codes",
        "devices",
        "sync_items",
        "sync_events",
        "sync_assets",
        "sync_item_assets",
        "device_p2p_endpoints",
        "asset_providers",
        "sync_file_items",
        "sync_link_metadata",
        "device_sync_state",
    ] {
        assert_eq!(
            count_rows(&server.pool, table, "sync_group_id", &sync.sync_id).await,
            0,
            "{table} should be empty for deleted sync space"
        );
    }
    assert_eq!(
        count_rows(&server.pool, "sync_groups", "id", &sync.sync_id).await,
        0
    );
    assert!(!Path::new(&asset_path).exists());
}

async fn empty_since_ms(pool: &SqlitePool, sync_group_id: &str) -> Option<i64> {
    sqlx::query("SELECT empty_since_ms FROM sync_groups WHERE id = ?")
        .bind(sync_group_id)
        .fetch_one(pool)
        .await
        .expect("query empty marker")
        .try_get("empty_since_ms")
        .expect("empty marker value")
}

async fn count_rows(pool: &SqlitePool, table: &str, id_column: &str, id: &str) -> i64 {
    let statement = format!("SELECT COUNT(*) AS count FROM {table} WHERE {id_column} = ?");
    sqlx::query(&statement)
        .bind(id)
        .fetch_one(pool)
        .await
        .unwrap_or_else(|error| panic!("count {table}: {error}"))
        .get::<i64, _>("count")
}
