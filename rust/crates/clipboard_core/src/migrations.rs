use crate::error::{CoreError, CoreErrorCode, Result};
use crate::time::now_ms;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};

pub struct Migration {
    pub version: i64,
    pub name: &'static str,
    pub sql: &'static str,
}

pub const MIGRATIONS: &[Migration] = &[
    Migration {
        version: 1,
        name: "initial_clipboard_history_schema",
        sql: INITIAL_SCHEMA,
    },
    Migration {
        version: 2,
        name: "local_pinboards_schema",
        sql: PINBOARDS_SCHEMA,
    },
    Migration {
        version: 3,
        name: "recent_history_index_without_pin_sort",
        sql: RECENT_HISTORY_INDEX_WITHOUT_PIN_SORT,
    },
    Migration {
        version: 4,
        name: "full_pinboard_management_schema",
        sql: FULL_PINBOARD_MANAGEMENT_SCHEMA,
    },
    Migration {
        version: 5,
        name: "link_metadata_schema",
        sql: LINK_METADATA_SCHEMA,
    },
    Migration {
        version: 6,
        name: "file_items_metadata_schema",
        sql: FILE_ITEMS_METADATA_SCHEMA,
    },
    Migration {
        version: 7,
        name: "link_metadata_without_disabled_state",
        sql: LINK_METADATA_WITHOUT_DISABLED_STATE,
    },
    Migration {
        version: 8,
        name: "source_app_icon_header_color_cache",
        sql: SOURCE_APP_ICON_HEADER_COLOR_CACHE_SCHEMA,
    },
    Migration {
        version: 9,
        name: "pending_image_payload_lifecycle",
        sql: PENDING_IMAGE_PAYLOAD_LIFECYCLE_SCHEMA,
    },
    Migration {
        version: 10,
        name: "default_privacy_ignore_apps_preference_version",
        sql: DEFAULT_PRIVACY_IGNORE_APPS_PREFERENCE_VERSION,
    },
    Migration {
        version: 11,
        name: "default_open_panel_shortcut_preference_version",
        sql: DEFAULT_OPEN_PANEL_SHORTCUT_PREFERENCE_VERSION,
    },
];

pub fn run_migrations(connection: &mut Connection) -> Result<()> {
    connection
        .execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                checksum TEXT NOT NULL,
                applied_at_ms INTEGER NOT NULL
            );
            "#,
        )
        .map_err(|error| CoreError::new(CoreErrorCode::MigrationFailed, error.to_string()))?;

    let transaction = connection
        .transaction()
        .map_err(|error| CoreError::new(CoreErrorCode::MigrationFailed, error.to_string()))?;

    for migration in MIGRATIONS {
        let expected_checksum = checksum(migration.sql);
        let stored_checksum = transaction
            .query_row(
                "SELECT checksum FROM schema_migrations WHERE version = ?1",
                params![migration.version],
                |row| row.get::<_, String>(0),
            )
            .optional()
            .map_err(|error| CoreError::new(CoreErrorCode::MigrationFailed, error.to_string()))?;

        match stored_checksum {
            Some(stored_checksum) if stored_checksum != expected_checksum => {
                return Err(CoreError::new(
                    CoreErrorCode::MigrationChecksumMismatch,
                    "applied migration checksum differs from compiled migration",
                )
                .with_detail("version", migration.version.to_string())
                .with_detail("name", migration.name)
                .with_detail("stored_checksum", stored_checksum)
                .with_detail("expected_checksum", expected_checksum));
            }
            Some(_) => continue,
            None => {
                transaction.execute_batch(migration.sql).map_err(|error| {
                    CoreError::new(CoreErrorCode::MigrationFailed, error.to_string())
                        .with_detail("version", migration.version.to_string())
                        .with_detail("name", migration.name)
                })?;
                transaction
                    .execute(
                        "INSERT INTO schema_migrations (version, name, checksum, applied_at_ms) VALUES (?1, ?2, ?3, ?4)",
                        params![migration.version, migration.name, expected_checksum, now_ms()],
                    )
                    .map_err(|error| CoreError::new(CoreErrorCode::MigrationFailed, error.to_string()))?;
            }
        }
    }

    transaction
        .commit()
        .map_err(|error| CoreError::new(CoreErrorCode::MigrationFailed, error.to_string()))?;
    Ok(())
}

fn checksum(sql: &str) -> String {
    let digest = Sha256::digest(sql.as_bytes());
    digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>()
}

const INITIAL_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS source_apps (
    id TEXT PRIMARY KEY,
    bundle_id TEXT,
    derived_key TEXT,
    name TEXT NOT NULL,
    bundle_path TEXT,
    last_seen_at_ms INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    CHECK (bundle_id IS NOT NULL OR derived_key IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_source_apps_bundle_id
    ON source_apps(bundle_id)
    WHERE bundle_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_source_apps_derived_key
    ON source_apps(derived_key)
    WHERE derived_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS source_app_icons (
    id TEXT PRIMARY KEY,
    source_app_id TEXT NOT NULL REFERENCES source_apps(id) ON DELETE CASCADE,
    cache_key TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    byte_count INTEGER NOT NULL DEFAULT 0,
    width INTEGER,
    height INTEGER,
    content_hash TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_source_app_icons_cache_key
    ON source_app_icons(cache_key);

CREATE TABLE IF NOT EXISTS clipboard_items (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('text', 'link', 'image', 'file', 'color', 'rich_text', 'unknown')),
    summary TEXT NOT NULL,
    primary_text TEXT,
    content_hash TEXT NOT NULL,
    source_app_id TEXT REFERENCES source_apps(id) ON DELETE SET NULL,
    source_app_name TEXT,
    source_confidence TEXT NOT NULL DEFAULT 'unknown'
        CHECK (source_confidence IN ('high', 'medium', 'low', 'unknown')),
    first_copied_at_ms INTEGER NOT NULL,
    last_copied_at_ms INTEGER NOT NULL,
    copy_count INTEGER NOT NULL DEFAULT 1 CHECK (copy_count >= 1),
    is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),
    size_bytes INTEGER NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
    preview_state TEXT NOT NULL DEFAULT 'ready'
        CHECK (preview_state IN ('ready', 'deferred', 'too_large', 'missing_source', 'failed')),
    deleted_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_clipboard_items_hash_active
    ON clipboard_items(content_hash)
    WHERE deleted_at_ms IS NULL;

CREATE INDEX IF NOT EXISTS ix_clipboard_items_recent
    ON clipboard_items(is_pinned DESC, last_copied_at_ms DESC)
    WHERE deleted_at_ms IS NULL;

CREATE INDEX IF NOT EXISTS ix_clipboard_items_type_recent
    ON clipboard_items(type, last_copied_at_ms DESC)
    WHERE deleted_at_ms IS NULL;

CREATE TABLE IF NOT EXISTS clipboard_captures (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    source_app_id TEXT REFERENCES source_apps(id) ON DELETE SET NULL,
    source_confidence TEXT NOT NULL DEFAULT 'unknown'
        CHECK (source_confidence IN ('high', 'medium', 'low', 'unknown')),
    pasteboard_change_count INTEGER NOT NULL,
    self_write_token TEXT,
    captured_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_clipboard_captures_item_time
    ON clipboard_captures(item_id, captured_at_ms DESC);

CREATE TABLE IF NOT EXISTS clipboard_formats (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    uti TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('primary', 'alternative', 'metadata')),
    storage TEXT NOT NULL CHECK (storage IN ('inline', 'staged_asset', 'external_reference')),
    byte_count INTEGER NOT NULL DEFAULT 0 CHECK (byte_count >= 0)
);

CREATE INDEX IF NOT EXISTS ix_clipboard_formats_item
    ON clipboard_formats(item_id);

CREATE TABLE IF NOT EXISTS clipboard_assets (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('payload', 'thumbnail', 'rtf', 'file_snapshot')),
    mime_type TEXT,
    relative_path TEXT NOT NULL,
    byte_count INTEGER NOT NULL DEFAULT 0 CHECK (byte_count >= 0),
    width INTEGER,
    height INTEGER,
    content_hash TEXT,
    created_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_clipboard_assets_item
    ON clipboard_assets(item_id, kind);

CREATE TABLE IF NOT EXISTS preference_documents (
    id TEXT PRIMARY KEY CHECK (id = 'current'),
    schema_version INTEGER NOT NULL,
    value_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS preference_entries (
    namespace TEXT NOT NULL,
    key TEXT NOT NULL,
    value_json TEXT NOT NULL,
    value_type TEXT NOT NULL CHECK (value_type IN ('bool', 'int', 'float', 'string', 'object', 'array')),
    schema_version INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (namespace, key)
);

CREATE TABLE IF NOT EXISTS ignored_app_rules (
    id TEXT PRIMARY KEY,
    bundle_id TEXT,
    app_name TEXT,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS ignored_title_rules (
    id TEXT PRIMARY KEY,
    keyword TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_items_fts USING fts5(
    summary,
    primary_text,
    source_app_name,
    content = 'clipboard_items',
    content_rowid = 'rowid',
    tokenize = 'unicode61'
);
"#;

const PINBOARDS_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS pinboards (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    system_kind TEXT NOT NULL DEFAULT 'custom'
        CHECK (system_kind IN ('default_pins', 'custom')),
    sort_order INTEGER NOT NULL DEFAULT 0,
    deleted_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_pinboards_sort
    ON pinboards(sort_order ASC, updated_at_ms DESC)
    WHERE deleted_at_ms IS NULL;

CREATE TABLE IF NOT EXISTS pinboard_items (
    pinboard_id TEXT NOT NULL REFERENCES pinboards(id) ON DELETE CASCADE,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    display_order INTEGER NOT NULL DEFAULT 0,
    pinned_at_ms INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (pinboard_id, item_id)
);

CREATE INDEX IF NOT EXISTS ix_pinboard_items_order
    ON pinboard_items(pinboard_id, display_order ASC, pinned_at_ms DESC);

CREATE INDEX IF NOT EXISTS ix_pinboard_items_item
    ON pinboard_items(item_id);

INSERT OR IGNORE INTO pinboards (
    id, title, system_kind, sort_order, created_at_ms, updated_at_ms
)
VALUES (
    'default',
    '固定',
    'default_pins',
    0,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000,
    CAST(strftime('%s', 'now') AS INTEGER) * 1000
);

INSERT OR IGNORE INTO pinboard_items (
    pinboard_id,
    item_id,
    display_order,
    pinned_at_ms,
    created_at_ms,
    updated_at_ms
)
SELECT
    'default',
    id,
    ROW_NUMBER() OVER (ORDER BY last_copied_at_ms DESC, id DESC) - 1,
    updated_at_ms,
    updated_at_ms,
    updated_at_ms
FROM clipboard_items
WHERE is_pinned = 1
    AND deleted_at_ms IS NULL;
"#;

const RECENT_HISTORY_INDEX_WITHOUT_PIN_SORT: &str = r#"
DROP INDEX IF EXISTS ix_clipboard_items_recent;

CREATE INDEX IF NOT EXISTS ix_clipboard_items_recent
    ON clipboard_items(last_copied_at_ms DESC, id DESC)
    WHERE deleted_at_ms IS NULL;
"#;

const FULL_PINBOARD_MANAGEMENT_SCHEMA: &str = r#"
ALTER TABLE pinboards ADD COLUMN color_code INTEGER NOT NULL DEFAULT 4293940557;

DROP INDEX IF EXISTS ix_pinboards_sort;

CREATE INDEX IF NOT EXISTS ix_pinboards_active_sort
    ON pinboards(sort_order ASC, updated_at_ms DESC)
    WHERE deleted_at_ms IS NULL;
"#;

const LINK_METADATA_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS link_metadata (
    item_id TEXT PRIMARY KEY REFERENCES clipboard_items(id) ON DELETE CASCADE,
    original_text TEXT NOT NULL,
    canonical_url TEXT NOT NULL,
    display_url TEXT NOT NULL,
    host TEXT NOT NULL,
    title TEXT,
    site_name TEXT,
    icon_relative_path TEXT,
    image_relative_path TEXT,
    metadata_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (metadata_state IN ('pending', 'fetching', 'ready', 'failed', 'disabled', 'stale')),
    failure_code TEXT,
    fetch_attempts INTEGER NOT NULL DEFAULT 0 CHECK (fetch_attempts >= 0),
    last_requested_at_ms INTEGER,
    fetched_at_ms INTEGER,
    next_retry_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_link_metadata_state_retry
    ON link_metadata(metadata_state, next_retry_at_ms, updated_at_ms);

CREATE INDEX IF NOT EXISTS ix_link_metadata_canonical_url
    ON link_metadata(canonical_url);
"#;

const FILE_ITEMS_METADATA_SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS clipboard_file_items (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    order_index INTEGER NOT NULL CHECK (order_index >= 0),
    path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_extension TEXT,
    byte_count INTEGER NOT NULL DEFAULT 0 CHECK (byte_count >= 0),
    is_directory INTEGER NOT NULL DEFAULT 0 CHECK (is_directory IN (0, 1)),
    width INTEGER,
    height INTEGER,
    content_type TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_clipboard_file_items_order
    ON clipboard_file_items(item_id, order_index);

CREATE INDEX IF NOT EXISTS ix_clipboard_file_items_item
    ON clipboard_file_items(item_id);

CREATE INDEX IF NOT EXISTS ix_clipboard_file_items_path
    ON clipboard_file_items(path);
"#;

const LINK_METADATA_WITHOUT_DISABLED_STATE: &str = r#"
DROP INDEX IF EXISTS ix_link_metadata_state_retry;
DROP INDEX IF EXISTS ix_link_metadata_canonical_url;

ALTER TABLE link_metadata RENAME TO link_metadata_v6;

CREATE TABLE link_metadata (
    item_id TEXT PRIMARY KEY REFERENCES clipboard_items(id) ON DELETE CASCADE,
    original_text TEXT NOT NULL,
    canonical_url TEXT NOT NULL,
    display_url TEXT NOT NULL,
    host TEXT NOT NULL,
    title TEXT,
    site_name TEXT,
    icon_relative_path TEXT,
    image_relative_path TEXT,
    metadata_state TEXT NOT NULL DEFAULT 'pending'
        CHECK (metadata_state IN ('pending', 'fetching', 'ready', 'failed', 'stale')),
    failure_code TEXT,
    fetch_attempts INTEGER NOT NULL DEFAULT 0 CHECK (fetch_attempts >= 0),
    last_requested_at_ms INTEGER,
    fetched_at_ms INTEGER,
    next_retry_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

INSERT INTO link_metadata (
    item_id,
    original_text,
    canonical_url,
    display_url,
    host,
    title,
    site_name,
    icon_relative_path,
    image_relative_path,
    metadata_state,
    failure_code,
    fetch_attempts,
    last_requested_at_ms,
    fetched_at_ms,
    next_retry_at_ms,
    created_at_ms,
    updated_at_ms
)
SELECT
    item_id,
    original_text,
    canonical_url,
    display_url,
    host,
    title,
    site_name,
    icon_relative_path,
    image_relative_path,
    CASE
        WHEN metadata_state = 'disabled' AND failure_code = 'privacy_sensitive' THEN 'failed'
        WHEN metadata_state = 'disabled' AND fetched_at_ms IS NOT NULL AND failure_code IS NULL THEN 'ready'
        WHEN metadata_state = 'disabled' THEN 'pending'
        ELSE metadata_state
    END,
    CASE
        WHEN metadata_state = 'disabled' AND failure_code = 'privacy_sensitive' THEN failure_code
        WHEN metadata_state = 'disabled' THEN NULL
        ELSE failure_code
    END,
    fetch_attempts,
    last_requested_at_ms,
    fetched_at_ms,
    CASE
        WHEN metadata_state = 'disabled' THEN NULL
        ELSE next_retry_at_ms
    END,
    created_at_ms,
    updated_at_ms
FROM link_metadata_v6;

DROP TABLE link_metadata_v6;

CREATE INDEX IF NOT EXISTS ix_link_metadata_state_retry
    ON link_metadata(metadata_state, next_retry_at_ms, updated_at_ms);

CREATE INDEX IF NOT EXISTS ix_link_metadata_canonical_url
    ON link_metadata(canonical_url);
"#;

const SOURCE_APP_ICON_HEADER_COLOR_CACHE_SCHEMA: &str = r#"
ALTER TABLE source_app_icons
    ADD COLUMN header_color_argb INTEGER;

ALTER TABLE source_app_icons
    ADD COLUMN header_color_cache_version INTEGER;

ALTER TABLE source_app_icons
    ADD COLUMN header_color_updated_at_ms INTEGER;
"#;

const PENDING_IMAGE_PAYLOAD_LIFECYCLE_SCHEMA: &str = r#"
ALTER TABLE clipboard_items
    ADD COLUMN payload_state TEXT NOT NULL DEFAULT 'ready'
        CHECK (payload_state IN ('pending', 'ready', 'failed'));

CREATE TABLE IF NOT EXISTS pending_image_jobs (
    job_id TEXT PRIMARY KEY,
    requested_item_id TEXT NOT NULL,
    item_id TEXT REFERENCES clipboard_items(id) ON DELETE SET NULL,
    effective_item_id TEXT,
    owner_session_id TEXT NOT NULL,
    thumbnail_relative_path TEXT NOT NULL,
    reserved_payload_relative_path TEXT NOT NULL,
    staged_payload_relative_path TEXT NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('pending', 'ready', 'failed', 'deleted', 'merged')),
    failure_code TEXT,
    lease_expires_at_ms INTEGER NOT NULL,
    cleanup_after_ms INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    completed_at_ms INTEGER
);

CREATE INDEX IF NOT EXISTS ix_pending_image_jobs_state_lease
    ON pending_image_jobs(state, lease_expires_at_ms);

CREATE INDEX IF NOT EXISTS ix_pending_image_jobs_cleanup
    ON pending_image_jobs(cleanup_after_ms);

CREATE INDEX IF NOT EXISTS ix_pending_image_jobs_requested_item
    ON pending_image_jobs(requested_item_id);

CREATE UNIQUE INDEX IF NOT EXISTS ux_pending_image_jobs_active_reserved_payload
    ON pending_image_jobs(reserved_payload_relative_path)
    WHERE state = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS ux_pending_image_jobs_active_staged_payload
    ON pending_image_jobs(staged_payload_relative_path)
    WHERE state = 'pending';

CREATE UNIQUE INDEX IF NOT EXISTS ux_pending_image_jobs_active_item
    ON pending_image_jobs(item_id)
    WHERE state = 'pending' AND item_id IS NOT NULL;
"#;

const DEFAULT_PRIVACY_IGNORE_APPS_PREFERENCE_VERSION: &str = r#"
SELECT 1;
"#;

const DEFAULT_OPEN_PANEL_SHORTCUT_PREFERENCE_VERSION: &str = r#"
SELECT 1;
"#;
