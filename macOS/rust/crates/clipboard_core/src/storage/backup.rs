use super::ClipboardCore;
use crate::error::{CoreError, CoreErrorCode, Result};
use crate::{migrations::run_migrations, register_simple_tokenizer, CURRENT_SCHEMA_VERSION};
use rusqlite::{
    params, params_from_iter, types::Value as SqlValue, Connection, OpenFlags, OptionalExtension,
    TransactionBehavior,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::Path;

// Only business data crosses the archive boundary. Preferences, capture jobs and
// device/sync state always belong to the receiving installation.
const TABLES: &[&str] = &[
    "source_apps",
    "source_app_icons",
    "clipboard_items",
    "clipboard_formats",
    "clipboard_assets",
    "clipboard_file_items",
    "link_metadata",
    "pinboards",
    "pinboard_items",
];
// ponytail: v1 requires the same storage schema; add archive migrations when that schema changes.
const FORMAT_VERSION: i64 = 1;
const MAX_METADATA_BYTES: i64 = 64 * 1024 * 1024;
type Record = BTreeMap<String, Value>;
type Records = BTreeMap<String, Vec<Record>>;

#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BackupResult {
    pub exported_count: i64,
    pub imported_count: i64,
    pub skipped_count: i64,
}

impl ClipboardCore {
    pub fn export_backup(&mut self, destination: impl AsRef<Path>) -> Result<BackupResult> {
        let destination = destination.as_ref();
        let root = self.root_dir()?.canonicalize()?;
        let parent = destination
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or(Path::new("."));
        if parent.canonicalize()?.starts_with(&root) {
            return Err(invalid(
                "Choose a backup location outside ClipDock's data directory",
            ));
        }
        let temporary = tempfile::NamedTempFile::new_in(parent)?;
        let mut archive = Connection::open(temporary.path())?;
        archive.execute_batch(
            "CREATE TABLE backup_info (format_version INTEGER NOT NULL, schema_version INTEGER NOT NULL);
             CREATE TABLE backup_rows (table_name TEXT NOT NULL, data_json TEXT NOT NULL);
             CREATE TABLE backup_assets (path TEXT NOT NULL UNIQUE, hash TEXT NOT NULL, data BLOB NOT NULL);",
        )?;
        let snapshot = self.connection.transaction()?;
        let records = read_business_records(&snapshot)?;
        validate_items(&records)?;
        let output = archive.transaction()?;
        output.execute(
            "INSERT INTO backup_info VALUES (?1, ?2)",
            params![FORMAT_VERSION, CURRENT_SCHEMA_VERSION],
        )?;
        let mut metadata_bytes = 0;
        for &table in TABLES {
            for row in &records[table] {
                let json = serde_json::to_string(row).map_err(|e| invalid(e.to_string()))?;
                metadata_bytes += json.len() as i64;
                if metadata_bytes > MAX_METADATA_BYTES {
                    return Err(invalid("Backup metadata is too large"));
                }
                output.execute(
                    "INSERT INTO backup_rows VALUES (?1, ?2)",
                    params![table, json],
                )?;
            }
        }
        for path in asset_paths(&records)? {
            let absolute = root.join(&path).canonicalize()?;
            if !absolute.starts_with(&root) || !absolute.is_file() {
                return Err(invalid("Backup resource is outside the data directory"));
            }
            let mut input = File::open(absolute)?;
            let size = i32::try_from(input.metadata()?.len())
                .map_err(|_| invalid("Backup resource is too large"))?;
            output.execute(
                "INSERT INTO backup_assets VALUES (?1, '', zeroblob(?2))",
                params![path, size],
            )?;
            let id = output.last_insert_rowid();
            let hash = {
                let mut blob = output.blob_open("main", "backup_assets", "data", id, false)?;
                let (hash, copied) = copy_hashed(&mut input, &mut blob)?;
                if copied != size as u64 {
                    return Err(invalid("Backup resource changed during export; try again"));
                }
                hash
            };
            output.execute(
                "UPDATE backup_assets SET hash = ?1 WHERE rowid = ?2",
                params![hash, id],
            )?;
        }
        output.commit()?;
        snapshot.commit()?;
        archive.close().map_err(|(_, e)| CoreError::from(e))?;
        temporary.as_file().sync_all()?;
        temporary
            .persist(destination)
            .map_err(|e| CoreError::from(e.error))?;
        Ok(BackupResult {
            exported_count: records["clipboard_items"].len() as i64,
            ..Default::default()
        })
    }

    pub fn import_backup(&mut self, source: impl AsRef<Path>) -> Result<BackupResult> {
        let mut archive = Connection::open_with_flags(source, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
        archive.execute_batch("PRAGMA trusted_schema = OFF; PRAGMA query_only = ON;")?;
        // Keep one read snapshot through validation and extraction, even if the
        // selected file is modified by another process while importing.
        let archive = archive.transaction()?;
        let check: String = archive.query_row("PRAGMA integrity_check", [], |r| r.get(0))?;
        if check != "ok" {
            return Err(invalid("Backup database is damaged"));
        }
        let versions: (i64, i64) = archive.query_row(
            "SELECT format_version, schema_version FROM backup_info",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        if versions != (FORMAT_VERSION, CURRENT_SCHEMA_VERSION) {
            return Err(invalid(
                "Unsupported backup version; use a matching version of ClipDock",
            ));
        }
        let metadata_bytes: i64 = archive.query_row(
            "SELECT COALESCE(SUM(length(CAST(data_json AS BLOB))), 0) FROM backup_rows",
            [],
            |r| r.get(0),
        )?;
        if metadata_bytes > MAX_METADATA_BYTES {
            return Err(invalid("Backup metadata is too large"));
        }
        let mut records: Records = TABLES.iter().map(|t| (t.to_string(), Vec::new())).collect();
        let mut statement =
            archive.prepare("SELECT table_name, data_json FROM backup_rows ORDER BY rowid")?;
        let mut rows = statement.query([])?;
        while let Some(row) = rows.next()? {
            let table: String = row.get(0)?;
            let json: String = row.get(1)?;
            let record: Record = serde_json::from_str(&json).map_err(|e| invalid(e.to_string()))?;
            records
                .get_mut(&table)
                .ok_or_else(|| invalid("Unknown backup record type"))?
                .push(record);
        }
        validate_items(&records)?;
        validate_records(&records)?;
        let paths = asset_paths(&records)?;
        let asset_count: i64 =
            archive.query_row("SELECT COUNT(*) FROM backup_assets", [], |r| r.get(0))?;
        if asset_count != paths.len() as i64 {
            return Err(invalid("Backup resources do not match its records"));
        }

        let root = self.root_dir()?.canonicalize()?;
        // A unique owned directory prevents archive paths from overwriting files
        // already used by the current library; Drop removes it on any failure.
        let asset_directory = tempfile::Builder::new()
            .prefix("import-")
            .tempdir_in(root.join(".staging"))?;
        let prefix = format!(
            "assets/{}",
            asset_directory
                .path()
                .file_name()
                .unwrap()
                .to_string_lossy()
        );
        let mut imported_paths = HashMap::new();
        for path in paths {
            let (id, hash): (i64, String) = archive.query_row(
                "SELECT rowid, hash FROM backup_assets WHERE path = ?1",
                [&path],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )?;
            let mut blob = archive.blob_open("main", "backup_assets", "data", id, true)?;
            let name = format!(
                "{}.{}",
                blake3::hash(path.as_bytes()).to_hex(),
                Path::new(&path)
                    .extension()
                    .and_then(|s| s.to_str())
                    .unwrap_or("bin")
            );
            let output_path = asset_directory.path().join(&name);
            fs::create_dir_all(output_path.parent().unwrap())?;
            let mut output = File::create(output_path)?;
            if copy_hashed(&mut blob, &mut output)?.0 != hash {
                return Err(invalid("Backup resource checksum mismatch"));
            }
            output.sync_all()?;
            imported_paths.insert(path, format!("{prefix}/{name}"));
        }

        // Asset I/O is complete before taking the write lock. Captures can keep
        // writing while a large archive is read and verified.
        let transaction = self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?;
        let mut sources = HashMap::new();
        for row in &records["source_apps"] {
            let id = field(row, "id")?;
            let existing: Option<String> = transaction.query_row(
                "SELECT id FROM source_apps WHERE id = ?1 OR bundle_id = ?2 OR derived_key = ?3 LIMIT 1",
                params![id, sql_value(&row["bundle_id"])?, sql_value(&row["derived_key"]) ?], |r| r.get(0),
            ).optional()?;
            if let Some(existing) = existing {
                sources.insert(id.to_string(), existing);
            } else {
                insert_record(&transaction, "source_apps", row)?;
                sources.insert(id.to_string(), id.to_string());
            }
        }
        for row in &records["source_app_icons"] {
            let exists: bool = transaction.query_row(
                "SELECT EXISTS(SELECT 1 FROM source_app_icons WHERE id = ?1 OR cache_key = ?2)",
                params![field(row, "id")?, field(row, "cache_key")?],
                |r| r.get(0),
            )?;
            if !exists {
                let mut row = row.clone();
                remap(&mut row, "source_app_id", &sources)?;
                remap(&mut row, "relative_path", &imported_paths)?;
                insert_record(&transaction, "source_app_icons", &row)?;
            }
        }
        let mut result = BackupResult::default();
        let mut items = HashMap::new();
        let mut inserted_items = HashSet::new();
        for row in &records["clipboard_items"] {
            let id = field(row, "id")?;
            let existing: Option<String> = transaction.query_row("SELECT id FROM clipboard_items WHERE content_hash = ?1 AND deleted_at_ms IS NULL", [field(row, "content_hash")?], |r| r.get(0)).optional()?;
            if let Some(existing) = existing {
                items.insert(id.to_string(), existing);
                result.skipped_count += 1;
            } else {
                let mut row = row.clone();
                remap(&mut row, "source_app_id", &sources)?;
                insert_record(&transaction, "clipboard_items", &row)?;
                items.insert(id.to_string(), id.to_string());
                inserted_items.insert(id.to_string());
                result.imported_count += 1;
            }
        }
        for table in [
            "clipboard_formats",
            "clipboard_assets",
            "clipboard_file_items",
            "link_metadata",
        ] {
            for row in &records[table] {
                if !inserted_items.contains(field(row, "item_id")?) {
                    continue;
                }
                let mut row = row.clone();
                for key in ["relative_path", "icon_relative_path", "image_relative_path"] {
                    remap(&mut row, key, &imported_paths)?;
                }
                insert_record(&transaction, table, &row)?;
            }
        }
        for row in &records["pinboards"] {
            let exists: bool = transaction.query_row(
                "SELECT EXISTS(SELECT 1 FROM pinboards WHERE id = ?1)",
                [field(row, "id")?],
                |r| r.get(0),
            )?;
            if !exists {
                insert_record(&transaction, "pinboards", row)?;
            } else {
                transaction.execute(
                    "UPDATE pinboards SET deleted_at_ms = NULL WHERE id = ?1",
                    [field(row, "id")?],
                )?;
            }
        }
        for row in &records["pinboard_items"] {
            let mut row = row.clone();
            remap(&mut row, "item_id", &items)?;
            let exists: bool = transaction.query_row("SELECT EXISTS(SELECT 1 FROM pinboard_items WHERE pinboard_id = ?1 AND item_id = ?2)", params![field(&row, "pinboard_id")?, field(&row, "item_id")?], |r| r.get(0))?;
            if !exists {
                insert_record(&transaction, "pinboard_items", &row)?;
            }
        }
        transaction.execute("UPDATE clipboard_items SET is_pinned = EXISTS(SELECT 1 FROM pinboard_items pi JOIN pinboards pb ON pb.id = pi.pinboard_id WHERE pi.item_id = clipboard_items.id AND pb.deleted_at_ms IS NULL)", [])?;
        transaction.execute(
            "INSERT INTO clipboard_items_fts(clipboard_items_fts) VALUES('rebuild')",
            [],
        )?;
        // Discard extracted resources belonging only to skipped duplicates.
        let referenced = asset_paths(&read_business_records(&transaction)?)?;
        for path in imported_paths.values().filter(|p| !referenced.contains(*p)) {
            fs::remove_file(
                asset_directory
                    .path()
                    .join(Path::new(path).file_name().unwrap()),
            )?;
        }
        let has_assets = imported_paths.values().any(|p| referenced.contains(p));
        let destination = root.join(&prefix);
        if has_assets {
            if destination.try_exists()? {
                return Err(invalid(
                    "Import resource directory already exists; try again",
                ));
            }
            fs::rename(asset_directory.path(), &destination)?;
        }
        if let Err(error) = transaction.commit() {
            if has_assets {
                let _ = fs::remove_dir_all(destination);
            }
            return Err(error.into());
        }
        Ok(result)
    }
}

fn read_business_records(connection: &Connection) -> Result<Records> {
    let mut result = Records::new();
    for &table in TABLES {
        let condition = match table {
            "clipboard_items" | "pinboards" => "deleted_at_ms IS NULL",
            "clipboard_formats" | "clipboard_assets" | "clipboard_file_items" | "link_metadata" => "item_id IN (SELECT id FROM clipboard_items WHERE deleted_at_ms IS NULL)",
            "pinboard_items" => "item_id IN (SELECT id FROM clipboard_items WHERE deleted_at_ms IS NULL) AND pinboard_id IN (SELECT id FROM pinboards WHERE deleted_at_ms IS NULL)",
            _ => "1",
        };
        let mut statement =
            connection.prepare(&format!("SELECT * FROM {table} WHERE {condition}"))?;
        let columns = statement
            .column_names()
            .iter()
            .map(|s| s.to_string())
            .collect::<Vec<_>>();
        let mut rows = statement.query([])?;
        let mut records = Vec::new();
        while let Some(row) = rows.next()? {
            let mut record = Record::new();
            for (i, column) in columns.iter().enumerate() {
                let value = match row.get::<_, SqlValue>(i)? {
                    SqlValue::Null => Value::Null,
                    SqlValue::Integer(n) => Value::from(n),
                    SqlValue::Text(s) => Value::String(s),
                    _ => return Err(invalid("Unsupported backup field type")),
                };
                record.insert(column.clone(), value);
            }
            records.push(record);
        }
        result.insert(table.to_string(), records);
    }
    Ok(result)
}

fn validate_records(records: &Records) -> Result<()> {
    // Recreate our own trusted schema and constraints; never load SQL from a backup.
    let mut check = Connection::open_in_memory()?;
    register_simple_tokenizer(&check)?;
    run_migrations(&mut check)?;
    check.execute_batch(
        "PRAGMA foreign_keys = ON; DELETE FROM pinboard_items; DELETE FROM pinboards;",
    )?;
    for &table in TABLES {
        let mut statement = check.prepare(&format!("PRAGMA table_info({table})"))?;
        let columns = statement
            .query_map([], |r| r.get::<_, String>(1))?
            .collect::<std::result::Result<BTreeSet<_>, _>>()?;
        for row in &records[table] {
            if row.keys().cloned().collect::<BTreeSet<_>>() != columns {
                return Err(invalid("Invalid backup columns"));
            }
            insert_record(&check, table, row)?;
        }
    }
    let violation = check.prepare("PRAGMA foreign_key_check")?.exists([])?;
    if violation {
        return Err(invalid("Invalid backup relationships"));
    }
    let missing_payload: bool = check.query_row(
        "SELECT EXISTS(SELECT 1 FROM clipboard_items i WHERE
         (i.type = 'image' AND i.payload_state = 'ready' AND NOT EXISTS
             (SELECT 1 FROM clipboard_assets a WHERE a.item_id = i.id AND a.kind = 'payload'))
         OR (i.type = 'rich_text' AND NOT EXISTS
             (SELECT 1 FROM clipboard_assets a WHERE a.item_id = i.id AND a.kind = 'rtf')))",
        [],
        |r| r.get(0),
    )?;
    if missing_payload {
        return Err(invalid("Backup is missing required clipboard content"));
    }
    Ok(())
}

fn insert_record(connection: &Connection, table: &str, row: &Record) -> Result<()> {
    // Column names are accepted only after matching our trusted schema above,
    // or were read directly from our own database while exporting.
    let columns = row
        .keys()
        .map(|s| format!("\"{}\"", s.replace('"', "\"\"")))
        .collect::<Vec<_>>()
        .join(",");
    let placeholders = vec!["?"; row.len()].join(",");
    let values = row.values().map(sql_value).collect::<Result<Vec<_>>>()?;
    connection.execute(
        &format!("INSERT INTO {table} ({columns}) VALUES ({placeholders})"),
        params_from_iter(values),
    )?;
    Ok(())
}

fn sql_value(value: &Value) -> Result<SqlValue> {
    match value {
        Value::Null => Ok(SqlValue::Null),
        Value::String(s) => Ok(SqlValue::Text(s.clone())),
        Value::Number(n) => n
            .as_i64()
            .map(SqlValue::Integer)
            .ok_or_else(|| invalid("Invalid backup number")),
        _ => Err(invalid("Invalid backup field")),
    }
}

fn validate_items(records: &Records) -> Result<()> {
    for row in &records["clipboard_items"] {
        if matches!(field(row, "payload_state")?, "pending" | "remote_only") {
            return Err(invalid(
                "Some images are not stored locally yet; try again after processing finishes",
            ));
        }
        if row.get("deleted_at_ms") != Some(&Value::Null) {
            return Err(invalid("Backup contains deleted records"));
        }
    }
    for row in &records["pinboards"] {
        if row.get("deleted_at_ms") != Some(&Value::Null) {
            return Err(invalid("Backup contains deleted pinboards"));
        }
    }
    Ok(())
}

fn asset_paths(records: &Records) -> Result<BTreeSet<String>> {
    let mut paths = BTreeSet::new();
    for (table, keys) in [
        ("source_app_icons", &["relative_path"][..]),
        ("clipboard_assets", &["relative_path"][..]),
        (
            "link_metadata",
            &["icon_relative_path", "image_relative_path"][..],
        ),
    ] {
        for row in &records[table] {
            for key in keys {
                if let Some(Value::String(path)) = row.get(*key) {
                    let parts = path.split('/').collect::<Vec<_>>();
                    if parts.len() < 2
                        || !["assets", "thumbnails", "app-icons"].contains(&parts[0])
                        || parts.iter().any(|p| {
                            p.is_empty() || *p == "." || *p == ".." || p.contains(['\\', ':', '\0'])
                        })
                    {
                        return Err(invalid("Unsafe backup resource path"));
                    }
                    paths.insert(path.clone());
                }
            }
        }
    }
    Ok(paths)
}

fn field<'a>(row: &'a Record, key: &str) -> Result<&'a str> {
    row.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| invalid(format!("Missing backup field: {key}")))
}

fn remap(row: &mut Record, key: &str, mapping: &HashMap<String, String>) -> Result<()> {
    if let Some(Value::String(value)) = row.get_mut(key) {
        *value = mapping
            .get(value)
            .ok_or_else(|| invalid("Missing backup reference"))?
            .clone();
    }
    Ok(())
}

fn copy_hashed(input: &mut impl Read, output: &mut impl Write) -> Result<(String, u64)> {
    let mut hash = blake3::Hasher::new();
    let mut buffer = [0u8; 64 * 1024];
    let mut copied = 0;
    loop {
        let count = input.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
        output.write_all(&buffer[..count])?;
        copied += count as u64;
    }
    Ok((hash.finalize().to_hex().to_string(), copied))
}

fn invalid(message: impl Into<String>) -> CoreError {
    CoreError::new(CoreErrorCode::InvalidInput, message)
}
