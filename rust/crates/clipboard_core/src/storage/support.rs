use crate::domain::ClipboardItemType;
use crate::error::{CoreError, CoreErrorCode, Result};
use rusqlite::params;
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs;
use std::path::Path;

pub(super) fn normalize_text(text: &str) -> String {
    text.trim_matches(|character: char| character == '\0')
        .trim()
        .to_string()
}

pub(super) fn classify_text(text: &str) -> ClipboardItemType {
    let lower = text.to_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") {
        ClipboardItemType::Link
    } else if normalize_hex_color(text).is_some() {
        ClipboardItemType::Color
    } else {
        ClipboardItemType::Text
    }
}

pub(super) fn normalize_hex_color(text: &str) -> Option<String> {
    let hex = text.strip_prefix('#').unwrap_or(text);
    if hex.len() != 6 || !hex.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }

    Some(format!("#{}", hex.to_ascii_uppercase()))
}

pub(super) fn summarize_text(text: &str) -> String {
    const MAX_CHARS: usize = 180;
    let collapsed = text.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut summary = collapsed.chars().take(MAX_CHARS).collect::<String>();
    if collapsed.chars().count() > MAX_CHARS {
        summary.push('…');
    }
    summary
}

pub(super) fn summarize_image(width: i64, height: i64) -> String {
    if width > 0 && height > 0 {
        format!("图片 {} x {}", width, height)
    } else {
        "图片".to_string()
    }
}

pub(super) fn summarize_files(file_paths: &[String]) -> String {
    let first_name = file_paths
        .first()
        .and_then(|path| Path::new(path).file_name())
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .or_else(|| file_paths.first().map(String::as_str))
        .unwrap_or("文件");

    if file_paths.len() == 1 {
        first_name.to_string()
    } else {
        format!("{} 个文件 · {}", file_paths.len(), first_name)
    }
}

pub(super) fn positive_dimension(value: i64) -> Option<i64> {
    (value > 0).then_some(value)
}

pub(super) fn normalize_file_paths(file_paths: &[String]) -> Result<Vec<String>> {
    let mut seen = HashSet::new();
    let mut normalized_paths = Vec::new();

    for path in file_paths {
        let normalized_path = path.trim_matches('\0').to_string();
        if normalized_path.is_empty() {
            continue;
        }

        if seen.insert(normalized_path.clone()) {
            normalized_paths.push(normalized_path);
        }
    }

    if normalized_paths.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "file capture must contain at least one file path",
        ));
    }

    Ok(normalized_paths)
}

pub(super) fn file_paths_fingerprint(file_paths: &[String]) -> String {
    let mut sorted_paths = file_paths.to_vec();
    sorted_paths.sort();
    sorted_paths.join("\n")
}

pub(super) fn normalize_relative_asset_path(value: &str) -> Result<String> {
    let value = value.trim();
    if value.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "asset path cannot be empty",
        ));
    }

    let path = Path::new(value);
    if path.is_absolute()
        || path.components().any(|component| {
            matches!(
                component,
                std::path::Component::ParentDir | std::path::Component::RootDir
            )
        })
    {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "asset path must be relative to app support directory",
        ));
    }

    Ok(value.to_string())
}

pub(super) fn delete_relative_file(root: &Path, relative_path: &str) -> Result<Option<i64>> {
    let relative_path = normalize_relative_asset_path(relative_path)?;
    let path = root.join(relative_path);
    let metadata = match fs::metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(CoreError::new(CoreErrorCode::IoFailed, error.to_string())
                .with_detail("path", path.display().to_string()));
        }
    };

    if !metadata.is_file() {
        return Ok(None);
    }

    fs::remove_file(&path).map_err(|error| {
        CoreError::new(CoreErrorCode::IoFailed, error.to_string())
            .with_detail("path", path.display().to_string())
    })?;
    Ok(Some(metadata.len() as i64))
}

pub(super) fn unique_strings(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut unique_values = Vec::new();
    for value in values {
        if seen.insert(value.clone()) {
            unique_values.push(value);
        }
    }
    unique_values
}

pub(super) fn hash_file(path: &Path) -> Result<String> {
    let data = fs::read(path).map_err(|error| {
        CoreError::new(CoreErrorCode::IoFailed, error.to_string())
            .with_detail("path", path.display().to_string())
    })?;
    Ok(stable_hash_bytes(&data))
}

pub(super) fn stable_hash_bytes(value: &[u8]) -> String {
    let digest = Sha256::digest(value);
    digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>()
}

pub(super) fn stable_hash(value: &str) -> String {
    stable_hash_bytes(value.as_bytes())
}

pub(super) fn insert_asset(
    transaction: &rusqlite::Transaction<'_>,
    item_id: &str,
    kind: &str,
    mime_type: &str,
    relative_path: &str,
    byte_count: i64,
    width: Option<i64>,
    height: Option<i64>,
    content_hash: &str,
    now: i64,
) -> Result<()> {
    let asset_id = format!(
        "asset_{}",
        &stable_hash(&format!("{item_id}:{kind}:{content_hash}"))[..24]
    );
    transaction.execute(
        r#"
        INSERT OR IGNORE INTO clipboard_assets (
            id, item_id, kind, mime_type, relative_path, byte_count,
            width, height, content_hash, created_at_ms
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
        "#,
        params![
            asset_id,
            item_id,
            kind,
            mime_type,
            relative_path,
            byte_count,
            width,
            height,
            content_hash,
            now
        ],
    )?;
    Ok(())
}

pub(super) fn normalize_item_id(item_id: &str) -> Result<String> {
    let value = item_id.trim();
    if value.is_empty() {
        return Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "item id cannot be empty",
        ));
    }

    Ok(value.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_relative_asset_path_rejects_absolute_and_parent_paths() {
        assert!(normalize_relative_asset_path("assets/example.png").is_ok());
        assert!(normalize_relative_asset_path("/tmp/example.png").is_err());
        assert!(normalize_relative_asset_path("../example.png").is_err());
    }

    #[test]
    fn normalize_file_paths_deduplicates_and_requires_at_least_one_value() {
        let values = vec![
            "\0".to_string(),
            "/tmp/a.txt".to_string(),
            "/tmp/a.txt".to_string(),
            "/tmp/b.txt".to_string(),
        ];

        assert_eq!(
            normalize_file_paths(&values).unwrap(),
            vec!["/tmp/a.txt".to_string(), "/tmp/b.txt".to_string()]
        );
        assert!(normalize_file_paths(&["".to_string()]).is_err());
    }
}
