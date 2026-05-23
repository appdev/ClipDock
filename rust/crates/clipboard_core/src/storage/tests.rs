use super::*;
use crate::error::CoreErrorCode;
use crate::migrations::MIGRATIONS;
use crate::time::now_ms;
use crate::{
    CaptureDetectedLink, CaptureFilesRequest, CaptureImageRequest, CapturePendingImageRequest,
    CaptureResult, CaptureRichTextRequest, CaptureTextRequest, CapturedFileMetadata,
    ClipboardItemType, CompleteLinkMetadataFetchRequest, CompletePendingImagePayloadRequest,
    FailPendingImagePayloadRequest, ItemQuery, LinkMetadataState, PageRequest, PreferencesDocument,
    RecoverPendingImagesRequest, SourceConfidence, ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION,
    CURRENT_SCHEMA_VERSION, DATABASE_FILE_NAME,
};
use rusqlite::{params, Connection};
use sha2::{Digest, Sha256};
use std::fs;
use tempfile::TempDir;

fn open_temp_core() -> (TempDir, ClipboardCore) {
    let temp_dir = TempDir::new().expect("temp dir");
    let core = ClipboardCore::open(temp_dir.path()).expect("open core");
    (temp_dir, core)
}

fn capture_pending_link(core: &mut ClipboardCore, text: &str, url: &str) -> CaptureResult {
    let host = url
        .trim_start_matches("https://")
        .trim_start_matches("http://")
        .split(['/', '?', '#'])
        .next()
        .unwrap_or("example.com")
        .to_string();
    core.capture_text(CaptureTextRequest {
        text: text.to_string(),
        detected_link: Some(CaptureDetectedLink {
            original_text: text.to_string(),
            canonical_url: url.to_string(),
            display_url: url.to_string(),
            host,
            metadata_state: LinkMetadataState::Pending,
        }),
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 1,
        self_write_token: None,
    })
    .unwrap()
}

fn text_capture_request(text: &str, change_count: i64) -> CaptureTextRequest {
    CaptureTextRequest {
        text: text.to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.example.TestApp".to_string()),
        source_app_name: Some("TestApp".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: change_count,
        self_write_token: None,
    }
}

fn pending_image_request(
    owner_session_id: &str,
    thumbnail_relative_path: &str,
    reserved_payload_relative_path: &str,
    staged_payload_relative_path: &str,
    width: i64,
    height: i64,
    thumbnail_byte_count: i64,
) -> CapturePendingImageRequest {
    CapturePendingImageRequest {
        owner_session_id: owner_session_id.to_string(),
        thumbnail_relative_path: thumbnail_relative_path.to_string(),
        reserved_payload_relative_path: reserved_payload_relative_path.to_string(),
        staged_payload_relative_path: staged_payload_relative_path.to_string(),
        mime_type: "image/webp".to_string(),
        width,
        height,
        thumbnail_width: width.min(420).max(1),
        thumbnail_height: height.min(420).max(1),
        thumbnail_byte_count,
        source_bundle_id: Some("com.apple.Preview".to_string()),
        source_app_name: Some("Preview".to_string()),
        source_bundle_path: Some("/System/Applications/Preview.app".to_string()),
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 77,
        self_write_token: None,
        lease_duration_ms: Some(60_000),
        cleanup_after_duration_ms: Some(60_000),
    }
}

fn write_test_webp(root: &std::path::Path, relative_path: &str, payload: &[u8]) {
    let path = root.join(relative_path);
    fs::create_dir_all(path.parent().unwrap()).expect("webp parent");
    fs::write(path, test_webp_bytes(payload)).expect("webp file");
}

fn write_test_rtf(root: &std::path::Path, relative_path: &str, payload: &[u8]) {
    let path = root.join(relative_path);
    fs::create_dir_all(path.parent().unwrap()).expect("rtf parent");
    fs::write(path, payload).expect("rtf file");
}

fn test_webp_byte_count(payload: &[u8]) -> i64 {
    test_webp_bytes(payload).len() as i64
}

fn test_webp_bytes(payload: &[u8]) -> Vec<u8> {
    let mut bytes = b"RIFF".to_vec();
    bytes.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    bytes.extend_from_slice(b"WEBP");
    bytes.extend_from_slice(payload);
    bytes
}

fn stable_hash_for_test(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>()
}

#[test]
fn open_creates_database_schema_and_asset_directories() {
    let (temp_dir, core) = open_temp_core();

    assert!(temp_dir.path().join(DATABASE_FILE_NAME).exists());
    assert!(temp_dir.path().join("assets").is_dir());
    assert!(temp_dir.path().join("thumbnails").is_dir());
    assert!(temp_dir.path().join("app-icons").is_dir());
    assert!(temp_dir.path().join("staging").is_dir());
    assert!(temp_dir.path().join(".staging").is_dir());
    assert_eq!(core.info().unwrap().schema_version, CURRENT_SCHEMA_VERSION);

    let migration_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(migration_count, CURRENT_SCHEMA_VERSION);
}

#[test]
fn new_database_lists_empty_history() {
    let (_, core) = open_temp_core();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();

    assert!(page.items.is_empty());
    assert_eq!(page.total_count, 0);
    assert!(!page.has_more);
}

#[test]
fn capture_text_inserts_source_and_updates_empty_history() {
    let (_, mut core) = open_temp_core();

    let result = core
        .capture_text(CaptureTextRequest {
            text: "Hello from Safari".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: Some("/Applications/Safari.app".to_string()),
            source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 10,
            self_write_token: None,
        })
        .unwrap();

    assert!(result.inserted);
    assert_eq!(result.copy_count, 1);

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.total_count, 1);
    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].summary, "Hello from Safari");
    assert_eq!(page.items[0].source_app_name.as_deref(), Some("Safari"));
    assert!(page.items[0]
        .source_app_icon_path
        .as_deref()
        .unwrap()
        .ends_with("app-icons/safari.tiff"));

    let capture_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_captures", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(capture_count, 1);

    let fts_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH 'Safari'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(fts_count, 1);
}

#[test]
fn updating_source_icon_replaces_previous_icon_row() {
    let (_, mut core) = open_temp_core();

    core.capture_text(CaptureTextRequest {
        text: "First icon path".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: Some("/Applications/Safari.app".to_string()),
        source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 10,
        self_write_token: None,
    })
    .unwrap();
    core.capture_text(CaptureTextRequest {
        text: "Second icon path".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: Some("/Applications/Safari.app".to_string()),
        source_icon_relative_path: Some("app-icons/safari.png".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 11,
        self_write_token: None,
    })
    .unwrap();

    let icon_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM source_app_icons", [], |row| {
            row.get(0)
        })
        .unwrap();
    let icon_path: String = core
        .connection
        .query_row("SELECT relative_path FROM source_app_icons", [], |row| {
            row.get(0)
        })
        .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();

    assert_eq!(icon_count, 1);
    assert_eq!(icon_path, "app-icons/safari.png");
    assert_eq!(page.items.len(), 2);
    assert!(page.items.iter().all(|item| item
        .source_app_icon_path
        .as_deref()
        .is_some_and(|path| path.ends_with("app-icons/safari.png"))));
}

#[test]
fn source_app_icon_header_color_roundtrips_after_reopen() {
    let (temp_dir, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Header color cache".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: Some("/Applications/Safari.app".to_string()),
        source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 20,
        self_write_token: None,
    })
    .unwrap();

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let item = &page.items[0];
    let source_app_id = item.source_app_id.as_deref().unwrap();
    let source_icon_path = item.source_app_icon_path.as_deref().unwrap();
    let original_icon_updated_at_ms: i64 = core
        .connection
        .query_row(
            "SELECT updated_at_ms FROM source_app_icons WHERE source_app_id = ?1",
            params![source_app_id],
            |row| row.get(0),
        )
        .unwrap();

    let color = 0xFF33_6699;
    let result = core
        .update_source_app_icon_header_color(source_app_id, source_icon_path, color, false)
        .unwrap();
    assert_eq!(result.affected_count, 1);

    let icon_row: (i64, i64, i64) = core
        .connection
        .query_row(
            r#"
            SELECT header_color_argb, header_color_cache_version, updated_at_ms
            FROM source_app_icons
            WHERE source_app_id = ?1
            "#,
            params![source_app_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(icon_row.0, color);
    assert_eq!(icon_row.1, ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION);
    assert_eq!(icon_row.2, original_icon_updated_at_ms);

    drop(core);
    let reopened = ClipboardCore::open(temp_dir.path()).unwrap();
    let item_page = reopened
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(item_page.items[0].source_app_icon_header_color, Some(color));

    let app_page = reopened.list_source_apps(PageRequest::default()).unwrap();
    assert_eq!(app_page.apps[0].icon_header_color, Some(color));
}

#[test]
fn stale_source_app_icon_header_color_version_is_not_surfaced() {
    let (_, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Stale header color".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 21,
        self_write_token: None,
    })
    .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let source_app_id = page.items[0].source_app_id.as_deref().unwrap();
    let source_icon_path = page.items[0].source_app_icon_path.as_deref().unwrap();

    core.update_source_app_icon_header_color(source_app_id, source_icon_path, 0xFFAA_5500, false)
        .unwrap();
    core.connection
        .execute(
            "UPDATE source_app_icons SET header_color_cache_version = ?1 WHERE source_app_id = ?2",
            params![
                ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION - 1,
                source_app_id
            ],
        )
        .unwrap();

    let item_page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let app_page = core.list_source_apps(PageRequest::default()).unwrap();

    assert_eq!(item_page.items[0].source_app_icon_header_color, None);
    assert_eq!(app_page.apps[0].icon_header_color, None);
}

#[test]
fn source_app_icon_header_color_write_requires_matching_path() {
    let (_, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Mismatched icon path".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 22,
        self_write_token: None,
    })
    .unwrap();
    let source_app_id = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items[0]
        .source_app_id
        .clone()
        .unwrap();

    let result = core
        .update_source_app_icon_header_color(
            &source_app_id,
            "app-icons/other.tiff",
            0xFF00_8899,
            false,
        )
        .unwrap();
    let color_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM source_app_icons WHERE header_color_argb IS NOT NULL",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(result.affected_count, 0);
    assert_eq!(color_count, 0);
}

#[test]
fn source_app_icon_header_color_accepts_absolute_swift_returned_path() {
    let (temp_dir, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Absolute icon path".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 23,
        self_write_token: None,
    })
    .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let source_app_id = page.items[0].source_app_id.as_deref().unwrap();
    let absolute_icon_path = temp_dir.path().join("nested/../app-icons/./safari.tiff");

    let result = core
        .update_source_app_icon_header_color(
            source_app_id,
            absolute_icon_path.display().to_string(),
            0xFF10_2030,
            false,
        )
        .unwrap();
    let stored_path: String = core
        .connection
        .query_row(
            "SELECT relative_path FROM source_app_icons WHERE header_color_argb = ?1",
            params![0xFF10_2030_i64],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(result.affected_count, 1);
    assert_eq!(stored_path, "app-icons/safari.tiff");
}

#[test]
fn capture_text_deduplicates_by_content_hash() {
    let (_, mut core) = open_temp_core();

    let request = CaptureTextRequest {
        text: "https://example.com".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 1,
        self_write_token: None,
    };

    let first = core.capture_text(request.clone()).unwrap();
    let second = core
        .capture_text(CaptureTextRequest {
            pasteboard_change_count: 2,
            ..request
        })
        .unwrap();

    assert!(first.inserted);
    assert!(!second.inserted);
    assert_eq!(first.item_id, second.item_id);
    assert_eq!(second.copy_count, 2);

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.total_count, 1);
    assert_eq!(page.items[0].item_type, ClipboardItemType::Link);
    assert_eq!(page.items[0].copy_count, 2);
}

#[test]
fn capture_text_classifies_hex_rgb_colors_with_normalized_storage() {
    let (_, mut core) = open_temp_core();
    let accepted = [
        ("#ff00aa", "#FF00AA", true),
        ("ff00aa", "#FF00AA", false),
        ("#FF00AA", "#FF00AA", false),
        ("FF00AA", "#FF00AA", false),
        ("  #0a1B2c\n", "#0A1B2C", true),
    ];

    for (index, (value, expected_hex, expected_inserted)) in accepted.iter().enumerate() {
        let result = core
            .capture_text(text_capture_request(value, index as i64 + 1))
            .unwrap();
        assert_eq!(result.inserted, *expected_inserted);
        assert_eq!(
            result.content_hash,
            stable_hash_for_test(&format!("color:{expected_hex}"))
        );
    }

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.total_count, 2);

    let color_item = page
        .items
        .iter()
        .find(|item| item.summary == "#FF00AA")
        .expect("normalized color item");
    assert_eq!(color_item.item_type, ClipboardItemType::Color);
    assert_eq!(color_item.primary_text.as_deref(), Some("#FF00AA"));
    assert_eq!(color_item.copy_count, 4);

    let second_color = page
        .items
        .iter()
        .find(|item| item.summary == "#0A1B2C")
        .expect("trimmed normalized color item");
    assert_eq!(second_color.item_type, ClipboardItemType::Color);
    assert_eq!(second_color.primary_text.as_deref(), Some("#0A1B2C"));
}

#[test]
fn capture_text_keeps_near_miss_color_inputs_as_text() {
    let (_, mut core) = open_temp_core();
    let near_misses = [
        "#FFF",
        "#FFFFFFFF",
        "rgb(255,0,0)",
        "hsl(0, 100%, 50%)",
        "red",
        "0xFF00AA",
        "#FF00AG",
        "#FF00AA extra",
    ];

    for (index, value) in near_misses.iter().enumerate() {
        core.capture_text(text_capture_request(value, index as i64 + 1))
            .unwrap();
    }

    let page = core
        .list_items(
            ItemQuery {
                item_type: Some(ClipboardItemType::Color),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(page.total_count, 0);

    let text_page = core
        .list_items(
            ItemQuery {
                item_type: Some(ClipboardItemType::Text),
                ..ItemQuery::default()
            },
            PageRequest {
                limit: 20,
                offset: 0,
            },
        )
        .unwrap();
    assert_eq!(text_page.total_count, near_misses.len() as i64);
}

#[test]
fn capture_text_color_hash_is_distinct_from_text_hash_and_writes_no_assets() {
    let (_, mut core) = open_temp_core();
    let captured = core
        .capture_text(text_capture_request("ff00aa", 1))
        .unwrap();

    assert_eq!(captured.content_hash, stable_hash_for_test("color:#FF00AA"));
    assert_ne!(captured.content_hash, stable_hash_for_test("text:ff00aa"));
    assert_ne!(captured.content_hash, stable_hash_for_test("text:#FF00AA"));

    let asset_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(asset_count, 0);
}

#[test]
fn capture_text_color_filter_and_search_compose() {
    let (_, mut core) = open_temp_core();
    core.capture_text(text_capture_request("#11aa22", 1))
        .unwrap();
    core.capture_text(text_capture_request("Alpha #11AA22 note", 2))
        .unwrap();
    core.capture_text(text_capture_request("#334455", 3))
        .unwrap();

    let color_search_page = core
        .list_items(
            ItemQuery {
                item_type: Some(ClipboardItemType::Color),
                search_text: Some("#11AA22".to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(color_search_page.total_count, 1);
    assert_eq!(
        color_search_page.items[0].item_type,
        ClipboardItemType::Color
    );
    assert_eq!(color_search_page.items[0].summary, "#11AA22");

    let text_search_page = core
        .list_items(
            ItemQuery {
                item_type: Some(ClipboardItemType::Text),
                search_text: Some("#11AA22".to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(text_search_page.total_count, 1);
    assert_eq!(text_search_page.items[0].summary, "Alpha #11AA22 note");
}

#[test]
fn capture_detected_link_keeps_priority_over_color_classification() {
    let (_, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "#ff00aa".to_string(),
        detected_link: Some(CaptureDetectedLink {
            original_text: "#ff00aa".to_string(),
            canonical_url: "https://example.com/color".to_string(),
            display_url: "example.com/color".to_string(),
            host: "example.com".to_string(),
            metadata_state: LinkMetadataState::Pending,
        }),
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 1,
        self_write_token: None,
    })
    .unwrap();

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.total_count, 1);
    assert_eq!(page.items[0].item_type, ClipboardItemType::Link);
    assert_eq!(page.items[0].summary, "example.com/color");
    assert_eq!(page.items[0].primary_text.as_deref(), Some("#ff00aa"));
}

#[test]
fn record_item_copied_updates_recent_order_and_copy_count() {
    let (_, mut core) = open_temp_core();
    let old = core
        .capture_text(CaptureTextRequest {
            text: "Older copied item".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: None,
            source_app_name: Some("Notes".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    core.capture_text(CaptureTextRequest {
        text: "Newer copied item".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: None,
        source_app_name: Some("Notes".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 2,
        self_write_token: None,
    })
    .unwrap();

    let baseline = now_ms() - 60_000;
    core.connection
        .execute(
            r#"
            UPDATE clipboard_items
            SET last_copied_at_ms = CASE summary
                WHEN 'Older copied item' THEN ?1
                WHEN 'Newer copied item' THEN ?2
                ELSE last_copied_at_ms
            END
            "#,
            params![baseline, baseline + 1_000],
        )
        .unwrap();

    let result = core.record_item_copied(&old.item_id).unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();

    assert_eq!(result.affected_count, 1);
    assert_eq!(page.items[0].id, old.item_id);
    assert_eq!(page.items[0].summary, "Older copied item");
    assert_eq!(page.items[0].copy_count, 2);
    assert!(page.items[0].last_copied_at_ms > baseline + 1_000);
}

#[test]
fn capture_detected_link_persists_metadata_summary() {
    let (_, mut core) = open_temp_core();

    let result = core
        .capture_text(CaptureTextRequest {
            text: "example.com/docs".to_string(),
            detected_link: Some(CaptureDetectedLink {
                original_text: "example.com/docs".to_string(),
                canonical_url: "https://example.com/docs".to_string(),
                display_url: "https://example.com/docs".to_string(),
                host: "example.com".to_string(),
                metadata_state: LinkMetadataState::Pending,
            }),
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 3,
            self_write_token: None,
        })
        .unwrap();

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let item = &page.items[0];
    let link_metadata = item.link_metadata.as_ref().expect("link metadata");

    assert_eq!(item.id, result.item_id);
    assert_eq!(item.item_type, ClipboardItemType::Link);
    assert_eq!(item.primary_text.as_deref(), Some("example.com/docs"));
    assert_eq!(link_metadata.canonical_url, "https://example.com/docs");
    assert_eq!(link_metadata.display_url, "https://example.com/docs");
    assert_eq!(link_metadata.host, "example.com");
    assert_eq!(link_metadata.metadata_state, LinkMetadataState::Pending);
}

#[test]
fn claim_link_metadata_batch_marks_candidates_fetching() {
    let (_, mut core) = open_temp_core();
    let result = capture_pending_link(
        &mut core,
        "https://example.com/docs",
        "https://example.com/docs",
    );

    let candidates = core
        .claim_link_metadata_fetch_batch(3, 60_000)
        .expect("claim batch");

    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].item_id, result.item_id);
    assert_eq!(candidates[0].canonical_url, "https://example.com/docs");
    assert_eq!(candidates[0].fetch_attempts, 0);
    assert!(candidates[0].lease_started_at_ms > 0);

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(
        page.items[0].link_metadata.as_ref().unwrap().metadata_state,
        LinkMetadataState::Fetching
    );
}

#[test]
fn complete_link_metadata_fetch_requires_matching_lease() {
    let (_, mut core) = open_temp_core();
    let result = capture_pending_link(
        &mut core,
        "https://example.com/docs",
        "https://example.com/docs",
    );
    let candidate = core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .unwrap()
        .remove(0);

    let stale = core
        .complete_link_metadata_fetch(CompleteLinkMetadataFetchRequest {
            item_id: result.item_id.clone(),
            lease_started_at_ms: candidate.lease_started_at_ms - 1,
            canonical_url: "https://example.com/docs".to_string(),
            display_url: "example.com/docs".to_string(),
            host: "example.com".to_string(),
            title: Some("Example Docs".to_string()),
            site_name: Some("Example".to_string()),
            icon_relative_path: Some("assets/link-icons/example.png".to_string()),
            image_relative_path: Some("assets/link-previews/example.jpg".to_string()),
        })
        .unwrap();
    assert_eq!(stale.affected_count, 0);

    let completed = core
        .complete_link_metadata_fetch(CompleteLinkMetadataFetchRequest {
            item_id: result.item_id,
            lease_started_at_ms: candidate.lease_started_at_ms,
            canonical_url: "https://example.com/docs".to_string(),
            display_url: "example.com/docs".to_string(),
            host: "example.com".to_string(),
            title: Some("Example Docs".to_string()),
            site_name: Some("Example".to_string()),
            icon_relative_path: Some("assets/link-icons/example.png".to_string()),
            image_relative_path: Some("assets/link-previews/example.jpg".to_string()),
        })
        .unwrap();
    assert_eq!(completed.affected_count, 1);

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let metadata = page.items[0].link_metadata.as_ref().unwrap();
    assert_eq!(metadata.metadata_state, LinkMetadataState::Ready);
    assert_eq!(metadata.title.as_deref(), Some("Example Docs"));
    assert_eq!(metadata.display_url, "example.com/docs");
    assert!(metadata
        .icon_asset_path
        .as_deref()
        .unwrap()
        .ends_with("assets/link-icons/example.png"));
}

#[test]
fn recapturing_ready_link_without_assets_marks_metadata_stale() {
    let (_, mut core) = open_temp_core();
    let result = capture_pending_link(
        &mut core,
        "https://example.com/no-assets",
        "https://example.com/no-assets",
    );
    let candidate = core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .unwrap()
        .remove(0);
    core.complete_link_metadata_fetch(CompleteLinkMetadataFetchRequest {
        item_id: result.item_id.clone(),
        lease_started_at_ms: candidate.lease_started_at_ms,
        canonical_url: "https://example.com/no-assets".to_string(),
        display_url: "example.com/no-assets".to_string(),
        host: "example.com".to_string(),
        title: Some("No assets".to_string()),
        site_name: Some("Example".to_string()),
        icon_relative_path: None,
        image_relative_path: None,
    })
    .unwrap();

    capture_pending_link(
        &mut core,
        "https://example.com/no-assets",
        "https://example.com/no-assets",
    );

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let metadata = page.items[0].link_metadata.as_ref().unwrap();
    assert_eq!(metadata.metadata_state, LinkMetadataState::Stale);

    let candidates = core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .expect("claim stale no-asset link");
    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].item_id, result.item_id);
}

#[test]
fn recapturing_ready_link_with_assets_keeps_metadata_ready() {
    let (_, mut core) = open_temp_core();
    let result = capture_pending_link(
        &mut core,
        "https://example.com/with-assets",
        "https://example.com/with-assets",
    );
    let candidate = core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .unwrap()
        .remove(0);
    core.complete_link_metadata_fetch(CompleteLinkMetadataFetchRequest {
        item_id: result.item_id.clone(),
        lease_started_at_ms: candidate.lease_started_at_ms,
        canonical_url: "https://example.com/with-assets".to_string(),
        display_url: "example.com/with-assets".to_string(),
        host: "example.com".to_string(),
        title: Some("With assets".to_string()),
        site_name: Some("Example".to_string()),
        icon_relative_path: Some("assets/link-icons/example.png".to_string()),
        image_relative_path: None,
    })
    .unwrap();

    capture_pending_link(
        &mut core,
        "https://example.com/with-assets",
        "https://example.com/with-assets",
    );

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let metadata = page.items[0].link_metadata.as_ref().unwrap();
    assert_eq!(metadata.metadata_state, LinkMetadataState::Ready);
    assert!(metadata
        .icon_asset_path
        .as_deref()
        .unwrap()
        .ends_with("assets/link-icons/example.png"));
    assert!(core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .expect("claim batch")
        .is_empty());
}

#[test]
fn privacy_sensitive_failure_does_not_auto_retry() {
    let (_, mut core) = open_temp_core();
    let result = capture_pending_link(
        &mut core,
        "https://localhost/token",
        "https://localhost/token",
    );
    let candidate = core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .unwrap()
        .remove(0);

    let failed = core
        .fail_link_metadata_fetch(
            &result.item_id,
            candidate.lease_started_at_ms,
            "privacy_sensitive",
            None,
        )
        .unwrap();
    assert_eq!(failed.affected_count, 1);
    assert!(core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .unwrap()
        .is_empty());
    assert!(core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .unwrap()
        .is_empty());
}

#[test]
fn recapturing_privacy_sensitive_failure_resets_metadata_pending() {
    let (_, mut core) = open_temp_core();
    let result = capture_pending_link(
        &mut core,
        "http://127.0.0.1:23000/",
        "http://127.0.0.1:23000/",
    );
    let candidate = core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .unwrap()
        .remove(0);

    core.fail_link_metadata_fetch(
        &result.item_id,
        candidate.lease_started_at_ms,
        "privacy_sensitive",
        None,
    )
    .unwrap();

    let recaptured = capture_pending_link(
        &mut core,
        "http://127.0.0.1:23000/",
        "http://127.0.0.1:23000/",
    );
    assert_eq!(recaptured.item_id, result.item_id);

    let metadata: (String, Option<String>, Option<i64>) = core
        .connection
        .query_row(
            r#"
            SELECT metadata_state, failure_code, next_retry_at_ms
            FROM link_metadata
            WHERE item_id = ?1
            "#,
            params![result.item_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(metadata, ("pending".to_string(), None, None));

    let candidates = core
        .claim_link_metadata_fetch_batch(1, 60_000)
        .expect("claim reset privacy failure");
    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].item_id, recaptured.item_id);
}

#[test]
fn capture_rich_text_inserts_rtf_asset_and_payload_path() {
    let (temp_dir, mut core) = open_temp_core();
    let rtf = br#"{\rtf1\ansi{\fonttbl\f0 Helvetica;}\f0\b Bold rich text\b0}"#;
    write_test_rtf(temp_dir.path(), "assets/rich-text/sample.rtf", rtf);

    let result = core
        .capture_rich_text(CaptureRichTextRequest {
            text: "Bold rich text".to_string(),
            rtf_relative_path: "assets/rich-text/sample.rtf".to_string(),
            mime_type: Some("application/rtf".to_string()),
            byte_count: rtf.len() as i64,
            content_hash: Some("swift-ignored".to_string()),
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 41,
            self_write_token: None,
        })
        .unwrap();

    assert!(result.inserted);
    assert_eq!(result.copy_count, 1);
    assert_ne!(result.content_hash, "swift-ignored");

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.total_count, 1);
    let item = &page.items[0];
    assert_eq!(item.item_type, ClipboardItemType::RichText);
    assert_eq!(item.primary_text.as_deref(), Some("Bold rich text"));
    assert_eq!(item.summary, "Bold rich text");
    assert!(item
        .preview_asset_path
        .as_deref()
        .unwrap()
        .ends_with("assets/rich-text/sample.rtf"));
    assert!(item
        .payload_asset_path
        .as_deref()
        .unwrap()
        .ends_with("assets/rich-text/sample.rtf"));

    let asset_kind: String = core
        .connection
        .query_row(
            "SELECT kind FROM clipboard_assets WHERE item_id = ?1",
            params![item.id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(asset_kind, "rtf");
}

#[test]
fn capture_rich_text_deduplicates_by_rtf_digest_not_plain_text() {
    let (temp_dir, mut core) = open_temp_core();
    let first_rtf = br#"{\rtf1\ansi\b Same plain\b0}"#;
    let second_rtf = br#"{\rtf1\ansi\i Same plain\i0}"#;
    write_test_rtf(temp_dir.path(), "assets/rich-text/first.rtf", first_rtf);
    write_test_rtf(temp_dir.path(), "assets/rich-text/second.rtf", second_rtf);
    write_test_rtf(temp_dir.path(), "assets/rich-text/duplicate.rtf", first_rtf);

    let first = core
        .capture_rich_text(CaptureRichTextRequest {
            text: "Same plain".to_string(),
            rtf_relative_path: "assets/rich-text/first.rtf".to_string(),
            mime_type: Some("application/rtf".to_string()),
            byte_count: first_rtf.len() as i64,
            content_hash: None,
            source_bundle_id: None,
            source_app_name: None,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    let second = core
        .capture_rich_text(CaptureRichTextRequest {
            text: "Same plain".to_string(),
            rtf_relative_path: "assets/rich-text/second.rtf".to_string(),
            mime_type: Some("application/rtf".to_string()),
            byte_count: second_rtf.len() as i64,
            content_hash: None,
            source_bundle_id: None,
            source_app_name: None,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();
    let duplicate = core
        .capture_rich_text(CaptureRichTextRequest {
            text: "Same plain".to_string(),
            rtf_relative_path: "assets/rich-text/duplicate.rtf".to_string(),
            mime_type: Some("application/rtf".to_string()),
            byte_count: first_rtf.len() as i64,
            content_hash: None,
            source_bundle_id: None,
            source_app_name: None,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 3,
            self_write_token: None,
        })
        .unwrap();

    assert_ne!(first.item_id, second.item_id);
    assert_eq!(duplicate.item_id, first.item_id);
    assert_eq!(duplicate.copy_count, 2);
    assert!(!duplicate.inserted);

    let total_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_items", [], |row| row.get(0))
        .unwrap();
    assert_eq!(total_count, 2);
}

#[test]
fn list_items_exposes_rtf_payload_only_for_rich_text() {
    let (temp_dir, mut core) = open_temp_core();
    let rtf = br#"{\rtf1\ansi\b Rich\b0}"#;
    write_test_rtf(temp_dir.path(), "assets/rich-text/rich.rtf", rtf);
    let rich = core
        .capture_rich_text(CaptureRichTextRequest {
            text: "Rich".to_string(),
            rtf_relative_path: "assets/rich-text/rich.rtf".to_string(),
            mime_type: Some("application/rtf".to_string()),
            byte_count: rtf.len() as i64,
            content_hash: None,
            source_bundle_id: None,
            source_app_name: None,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 4,
            self_write_token: None,
        })
        .unwrap();
    let text = core.capture_text(text_capture_request("Plain", 5)).unwrap();
    core.connection
        .execute(
            r#"
            INSERT INTO clipboard_assets (
                id, item_id, kind, mime_type, relative_path, byte_count, created_at_ms
            )
            VALUES ('asset_manual_text_rtf', ?1, 'rtf', 'application/rtf', 'assets/rich-text/rich.rtf', ?2, 1)
            "#,
            params![text.item_id, rtf.len() as i64],
        )
        .unwrap();

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let rich_item = page
        .items
        .iter()
        .find(|item| item.id == rich.item_id)
        .unwrap();
    let text_item = page
        .items
        .iter()
        .find(|item| item.id == text.item_id)
        .unwrap();

    assert!(rich_item.payload_asset_path.is_some());
    assert!(rich_item.preview_asset_path.is_some());
    assert!(text_item.preview_asset_path.is_some());
    assert!(text_item.payload_asset_path.is_none());
}

#[test]
fn capture_text_with_display_rtf_exposes_preview_without_payload() {
    let (temp_dir, mut core) = open_temp_core();
    let rtf = br#"{\rtf1\ansi{\colortbl;\red0\green128\blue0;}\cf1 Code\cf0}"#;
    write_test_rtf(temp_dir.path(), "assets/rich-text/text-display.rtf", rtf);

    let mut request = text_capture_request("Code", 6);
    request.display_rtf_relative_path = Some("assets/rich-text/text-display.rtf".to_string());
    request.display_rtf_mime_type = Some("application/rtf".to_string());
    request.display_rtf_byte_count = rtf.len() as i64;
    let captured = core.capture_text(request).unwrap();

    let item = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .into_iter()
        .find(|item| item.id == captured.item_id)
        .unwrap();

    assert_eq!(item.item_type, ClipboardItemType::Text);
    assert!(item
        .preview_asset_path
        .as_deref()
        .is_some_and(|path| path.ends_with("assets/rich-text/text-display.rtf")));
    assert!(item.payload_asset_path.is_none());
}

#[test]
fn capture_text_plain_only_recapture_clears_stale_display_rtf_association() {
    let (temp_dir, mut core) = open_temp_core();
    let rtf = br#"{\rtf1\ansi{\colortbl;\red0\green128\blue0;}\cf1 Code\cf0}"#;
    write_test_rtf(temp_dir.path(), "assets/rich-text/stale-display.rtf", rtf);

    let mut styled_request = text_capture_request("Code", 6);
    styled_request.display_rtf_relative_path =
        Some("assets/rich-text/stale-display.rtf".to_string());
    styled_request.display_rtf_mime_type = Some("application/rtf".to_string());
    styled_request.display_rtf_byte_count = rtf.len() as i64;
    let first = core.capture_text(styled_request).unwrap();
    let second = core.capture_text(text_capture_request("Code", 7)).unwrap();

    assert_eq!(second.item_id, first.item_id);
    assert_eq!(second.copy_count, 2);
    assert!(!second.inserted);

    let item = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .into_iter()
        .find(|item| item.id == first.item_id)
        .unwrap();

    assert_eq!(item.item_type, ClipboardItemType::Text);
    assert!(item.preview_asset_path.is_none());
    assert!(item.payload_asset_path.is_none());

    let rtf_asset_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_assets WHERE item_id = ?1 AND kind = 'rtf'",
            params![&item.id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(rtf_asset_count, 0);
    assert!(temp_dir
        .path()
        .join("assets/rich-text/stale-display.rtf")
        .exists());
}

#[test]
fn capture_image_inserts_asset_preview_and_source() {
    let (temp_dir, mut core) = open_temp_core();
    fs::write(
        temp_dir.path().join("assets/sample.png"),
        b"sample image payload",
    )
    .expect("payload");
    fs::write(
        temp_dir.path().join("thumbnails/sample.png"),
        b"sample image thumbnail",
    )
    .expect("thumbnail");

    let result = core
        .capture_image(CaptureImageRequest {
            payload_relative_path: "assets/sample.png".to_string(),
            preview_relative_path: Some("thumbnails/sample.png".to_string()),
            mime_type: Some("image/png".to_string()),
            width: 640,
            height: 360,
            byte_count: 20,
            source_bundle_id: Some("com.apple.Preview".to_string()),
            source_app_name: Some("Preview".to_string()),
            source_bundle_path: Some("/System/Applications/Preview.app".to_string()),
            source_icon_relative_path: Some("app-icons/preview.tiff".to_string()),
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 33,
            self_write_token: None,
        })
        .unwrap();

    assert!(result.inserted);
    assert_eq!(result.copy_count, 1);

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.total_count, 1);
    assert_eq!(page.items[0].item_type, ClipboardItemType::Image);
    assert_eq!(page.items[0].summary, "图片 640 x 360");
    assert_eq!(page.items[0].source_app_name.as_deref(), Some("Preview"));
    assert!(page.items[0]
        .preview_asset_path
        .as_deref()
        .unwrap()
        .ends_with("thumbnails/sample.png"));

    let asset_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(asset_count, 2);

    let capture_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_captures", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(capture_count, 1);

    let fts_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH 'Preview'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(fts_count, 1);
}

#[test]
fn capture_pending_image_inserts_thumbnail_visible_row_without_payload() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(
        temp_dir.path(),
        "thumbnails/pending.webp",
        b"pending thumbnail",
    );

    let result = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/pending.webp",
            "assets/pending.webp",
            ".staging/image-captures/pending-payload.webp",
            640,
            360,
            test_webp_byte_count(b"pending thumbnail"),
        ))
        .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();

    assert!(result.inserted);
    assert_eq!(page.total_count, 1);
    assert_eq!(page.items[0].item_type, ClipboardItemType::Image);
    assert_eq!(page.items[0].payload_state.as_str(), "pending");
    assert!(page.items[0].payload_asset_path.is_none());
    assert!(page.items[0]
        .preview_asset_path
        .as_deref()
        .is_some_and(|path| path.ends_with("thumbnails/pending.webp")));
}

#[test]
fn capture_pending_image_validates_metadata_and_relative_paths() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(
        temp_dir.path(),
        "thumbnails/pending-validation.webp",
        b"thumb",
    );

    let mut bad_mime = pending_image_request(
        "session-a",
        "thumbnails/pending-validation.webp",
        "assets/pending-validation.webp",
        ".staging/image-captures/pending-validation.webp",
        20,
        10,
        test_webp_byte_count(b"thumb"),
    );
    bad_mime.mime_type = "image/png".to_string();
    assert_eq!(
        core.capture_pending_image(bad_mime).unwrap_err().code,
        CoreErrorCode::InvalidInput
    );

    let mut bad_path = pending_image_request(
        "session-a",
        "../pending-validation.webp",
        "assets/pending-validation.webp",
        ".staging/image-captures/pending-validation.webp",
        20,
        10,
        test_webp_byte_count(b"thumb"),
    );
    bad_path.mime_type = "image/webp".to_string();
    assert_eq!(
        core.capture_pending_image(bad_path).unwrap_err().code,
        CoreErrorCode::InvalidInput
    );

    let bad_count = pending_image_request(
        "session-a",
        "thumbnails/pending-validation.webp",
        "assets/pending-validation.webp",
        ".staging/image-captures/pending-validation.webp",
        20,
        10,
        1,
    );
    assert_eq!(
        core.capture_pending_image(bad_count).unwrap_err().code,
        CoreErrorCode::InvalidInput
    );
}

#[test]
fn complete_pending_image_payload_moves_staged_to_reserved_and_enables_payload() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(temp_dir.path(), "thumbnails/ready.webp", b"ready thumbnail");
    let pending = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/ready.webp",
            "assets/ready.webp",
            ".staging/image-captures/ready-payload.webp",
            640,
            360,
            test_webp_byte_count(b"ready thumbnail"),
        ))
        .unwrap();
    write_test_webp(
        temp_dir.path(),
        ".staging/image-captures/ready-payload.webp",
        b"ready payload",
    );

    let completed = core
        .complete_pending_image_payload(CompletePendingImagePayloadRequest {
            job_id: pending.job_id.clone(),
            staged_payload_relative_path: ".staging/image-captures/ready-payload.webp".to_string(),
            mime_type: "image/webp".to_string(),
            width: 640,
            height: 360,
            byte_count: test_webp_byte_count(b"ready payload"),
        })
        .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();

    assert_eq!(completed.status, "ready");
    assert_eq!(
        completed.effective_item_id.as_deref(),
        Some(pending.item_id.as_str())
    );
    assert!(completed.content_hash.is_some());
    assert!(completed.cleaned_relative_paths.is_empty());
    assert!(temp_dir.path().join("assets/ready.webp").exists());
    assert!(!temp_dir
        .path()
        .join(".staging/image-captures/ready-payload.webp")
        .exists());
    assert_eq!(page.items[0].payload_state.as_str(), "ready");
    assert!(page.items[0]
        .payload_asset_path
        .as_deref()
        .is_some_and(|path| path.ends_with("assets/ready.webp")));
    assert_eq!(page.items[0].item_type, ClipboardItemType::Image);
}

#[test]
fn deleting_pending_image_keeps_tombstone_and_late_completion_deletes_exact_staged_file() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(temp_dir.path(), "thumbnails/deleted-pending.webp", b"thumb");
    let pending = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/deleted-pending.webp",
            "assets/deleted-pending.webp",
            ".staging/image-captures/deleted-pending.webp",
            40,
            20,
            test_webp_byte_count(b"thumb"),
        ))
        .unwrap();

    core.delete_item(&pending.item_id).unwrap();
    let job_row: (String, Option<String>) = core
        .connection
        .query_row(
            "SELECT state, item_id FROM pending_image_jobs WHERE job_id = ?1",
            params![pending.job_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(job_row, ("deleted".to_string(), None));

    write_test_webp(
        temp_dir.path(),
        ".staging/image-captures/deleted-pending.webp",
        b"late payload",
    );
    let completed = core
        .complete_pending_image_payload(CompletePendingImagePayloadRequest {
            job_id: pending.job_id,
            staged_payload_relative_path: ".staging/image-captures/deleted-pending.webp"
                .to_string(),
            mime_type: "image/webp".to_string(),
            width: 40,
            height: 20,
            byte_count: test_webp_byte_count(b"late payload"),
        })
        .unwrap();

    assert_eq!(completed.status, "deleted");
    assert_eq!(
        completed.cleaned_relative_paths,
        vec![".staging/image-captures/deleted-pending.webp".to_string()]
    );
    assert!(!temp_dir
        .path()
        .join(".staging/image-captures/deleted-pending.webp")
        .exists());
    assert!(!temp_dir.path().join("assets/deleted-pending.webp").exists());
}

#[test]
fn completion_after_tombstone_purge_deletes_nothing_and_returns_not_pending() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(temp_dir.path(), "thumbnails/purged-pending.webp", b"thumb");
    let pending = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/purged-pending.webp",
            "assets/purged-pending.webp",
            ".staging/image-captures/purged-pending.webp",
            40,
            20,
            test_webp_byte_count(b"thumb"),
        ))
        .unwrap();
    core.delete_item(&pending.item_id).unwrap();
    core.connection
        .execute(
            "UPDATE pending_image_jobs SET cleanup_after_ms = 0 WHERE job_id = ?1",
            params![pending.job_id],
        )
        .unwrap();
    core.run_maintenance().unwrap();
    write_test_webp(
        temp_dir.path(),
        ".staging/image-captures/purged-pending.webp",
        b"late payload",
    );

    let completed = core
        .complete_pending_image_payload(CompletePendingImagePayloadRequest {
            job_id: pending.job_id,
            staged_payload_relative_path: ".staging/image-captures/purged-pending.webp".to_string(),
            mime_type: "image/webp".to_string(),
            width: 40,
            height: 20,
            byte_count: test_webp_byte_count(b"late payload"),
        })
        .unwrap();

    assert_eq!(completed.status, "not_pending");
    assert!(completed.cleaned_relative_paths.is_empty());
    assert!(temp_dir
        .path()
        .join(".staging/image-captures/purged-pending.webp")
        .exists());
}

#[test]
fn completion_with_staged_path_mismatch_does_not_delete_caller_path() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(temp_dir.path(), "thumbnails/mismatch.webp", b"thumb");
    let pending = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/mismatch.webp",
            "assets/mismatch.webp",
            ".staging/image-captures/mismatch.webp",
            40,
            20,
            test_webp_byte_count(b"thumb"),
        ))
        .unwrap();
    write_test_webp(
        temp_dir.path(),
        ".staging/image-captures/caller-controlled.webp",
        b"payload",
    );

    let completed = core
        .complete_pending_image_payload(CompletePendingImagePayloadRequest {
            job_id: pending.job_id,
            staged_payload_relative_path: ".staging/image-captures/caller-controlled.webp"
                .to_string(),
            mime_type: "image/webp".to_string(),
            width: 40,
            height: 20,
            byte_count: test_webp_byte_count(b"payload"),
        })
        .unwrap();

    assert_eq!(completed.status, "staged_path_mismatch");
    assert!(completed.cleaned_relative_paths.is_empty());
    assert!(temp_dir
        .path()
        .join(".staging/image-captures/caller-controlled.webp")
        .exists());
}

#[test]
fn duplicate_pending_image_completion_merges_into_existing_ready_item() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(temp_dir.path(), "assets/existing.webp", b"same payload");
    let existing = core
        .capture_image(CaptureImageRequest {
            payload_relative_path: "assets/existing.webp".to_string(),
            preview_relative_path: None,
            mime_type: Some("image/webp".to_string()),
            width: 40,
            height: 20,
            byte_count: test_webp_byte_count(b"same payload"),
            source_bundle_id: Some("com.apple.Preview".to_string()),
            source_app_name: Some("Preview".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    write_test_webp(temp_dir.path(), "thumbnails/duplicate.webp", b"thumb");
    let pending = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/duplicate.webp",
            "assets/duplicate.webp",
            ".staging/image-captures/duplicate.webp",
            40,
            20,
            test_webp_byte_count(b"thumb"),
        ))
        .unwrap();
    write_test_webp(
        temp_dir.path(),
        ".staging/image-captures/duplicate.webp",
        b"same payload",
    );

    let completed = core
        .complete_pending_image_payload(CompletePendingImagePayloadRequest {
            job_id: pending.job_id.clone(),
            staged_payload_relative_path: ".staging/image-captures/duplicate.webp".to_string(),
            mime_type: "image/webp".to_string(),
            width: 40,
            height: 20,
            byte_count: test_webp_byte_count(b"same payload"),
        })
        .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let job_row: (String, Option<String>) = core
        .connection
        .query_row(
            "SELECT state, effective_item_id FROM pending_image_jobs WHERE job_id = ?1",
            params![pending.job_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();

    assert_eq!(completed.status, "merged");
    assert_eq!(
        completed.effective_item_id.as_deref(),
        Some(existing.item_id.as_str())
    );
    assert!(completed.content_hash.is_some());
    assert_eq!(
        completed.cleaned_relative_paths,
        vec![
            ".staging/image-captures/duplicate.webp".to_string(),
            "thumbnails/duplicate.webp".to_string(),
        ]
    );
    assert_eq!(job_row, ("merged".to_string(), Some(existing.item_id)));
    assert_eq!(page.total_count, 1);
    assert!(!temp_dir.path().join("thumbnails/duplicate.webp").exists());
    assert!(!temp_dir
        .path()
        .join(".staging/image-captures/duplicate.webp")
        .exists());
}

#[test]
fn fail_and_recover_pending_images_mark_payload_failed_and_clean_staged_files() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(temp_dir.path(), "thumbnails/failed.webp", b"thumb");
    let failed_pending = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/failed.webp",
            "assets/failed.webp",
            ".staging/image-captures/failed.webp",
            40,
            20,
            test_webp_byte_count(b"thumb"),
        ))
        .unwrap();
    write_test_webp(
        temp_dir.path(),
        ".staging/image-captures/failed.webp",
        b"failed payload",
    );

    let failed = core
        .fail_pending_image_payload(FailPendingImagePayloadRequest {
            job_id: failed_pending.job_id,
            staged_payload_relative_path: Some(".staging/image-captures/failed.webp".to_string()),
            failure_code: "encoding_failed".to_string(),
        })
        .unwrap();
    assert_eq!(failed.status, "failed");
    assert!(!temp_dir
        .path()
        .join(".staging/image-captures/failed.webp")
        .exists());

    write_test_webp(temp_dir.path(), "thumbnails/recover.webp", b"thumb");
    let recover_pending = core
        .capture_pending_image(pending_image_request(
            "old-session",
            "thumbnails/recover.webp",
            "assets/recover.webp",
            ".staging/image-captures/recover.webp",
            40,
            20,
            test_webp_byte_count(b"thumb"),
        ))
        .unwrap();
    core.connection
        .execute(
            "UPDATE pending_image_jobs SET lease_expires_at_ms = 0 WHERE job_id = ?1",
            params![recover_pending.job_id],
        )
        .unwrap();

    let recovered = core
        .recover_pending_images(RecoverPendingImagesRequest {
            owner_session_id: "new-session".to_string(),
        })
        .unwrap();
    let payload_state: String = core
        .connection
        .query_row(
            "SELECT payload_state FROM clipboard_items WHERE id = ?1",
            params![recover_pending.item_id],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(recovered.affected_count, 1);
    assert_eq!(payload_state, "failed");
}

#[test]
fn maintenance_preserves_active_pending_staging_and_purges_terminal_staging_and_tombstones() {
    let (temp_dir, mut core) = open_temp_core();
    write_test_webp(temp_dir.path(), "thumbnails/lease.webp", b"thumb");
    let pending = core
        .capture_pending_image(pending_image_request(
            "session-a",
            "thumbnails/lease.webp",
            "assets/lease.webp",
            ".staging/image-captures/lease.webp",
            40,
            20,
            test_webp_byte_count(b"thumb"),
        ))
        .unwrap();
    write_test_webp(
        temp_dir.path(),
        ".staging/image-captures/lease.webp",
        b"active staged payload",
    );

    core.run_maintenance().unwrap();
    assert!(temp_dir
        .path()
        .join(".staging/image-captures/lease.webp")
        .exists());

    core.connection
        .execute(
            r#"
            UPDATE pending_image_jobs
            SET state = 'failed', cleanup_after_ms = 0, completed_at_ms = 1
            WHERE job_id = ?1
            "#,
            params![pending.job_id],
        )
        .unwrap();
    core.run_maintenance().unwrap();

    let job_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM pending_image_jobs WHERE job_id = ?1",
            params![pending.job_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(job_count, 0);
    assert!(!temp_dir
        .path()
        .join(".staging/image-captures/lease.webp")
        .exists());
}

#[test]
fn capture_files_inserts_snapshot_and_source() {
    let (temp_dir, mut core) = open_temp_core();
    fs::create_dir_all(temp_dir.path().join("assets/file-snapshots")).expect("snapshot dir");
    fs::write(
        temp_dir.path().join("assets/file-snapshots/files.json"),
        r#"{"paths":["/Users/evan/Desktop/report.pdf","/Users/evan/Desktop/design.sketch"]}"#,
    )
    .expect("snapshot");

    let result = core
        .capture_files(CaptureFilesRequest {
            file_paths: vec![
                "/Users/evan/Desktop/report.pdf".to_string(),
                "/Users/evan/Desktop/design.sketch".to_string(),
            ],
            file_items: vec![],
            preview_relative_path: None,
            preview_mime_type: None,
            preview_width: None,
            preview_height: None,
            preview_byte_count: 0,
            snapshot_relative_path: Some("assets/file-snapshots/files.json".to_string()),
            snapshot_byte_count: 78,
            source_bundle_id: Some("com.apple.finder".to_string()),
            source_app_name: Some("Finder".to_string()),
            source_bundle_path: Some("/System/Library/CoreServices/Finder.app".to_string()),
            source_icon_relative_path: Some("app-icons/finder.tiff".to_string()),
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 44,
            self_write_token: None,
        })
        .unwrap();

    assert!(result.inserted);
    assert_eq!(result.copy_count, 1);

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.total_count, 1);
    assert_eq!(page.items[0].item_type, ClipboardItemType::File);
    assert_eq!(page.items[0].summary, "2 个文件 · report.pdf");
    assert!(page.items[0]
        .primary_text
        .as_deref()
        .unwrap()
        .contains("design.sketch"));
    assert_eq!(page.items[0].source_app_name.as_deref(), Some("Finder"));
    assert!(page.items[0]
        .payload_asset_path
        .as_deref()
        .unwrap()
        .ends_with("assets/file-snapshots/files.json"));

    let asset_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(asset_count, 1);

    let format_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_formats WHERE uti = 'public.file-url'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(format_count, 1);
}

#[test]
fn capture_files_persists_structured_file_metadata() {
    let (temp_dir, mut core) = open_temp_core();
    let first_file = temp_dir.path().join("frame.png");
    let second_file = temp_dir.path().join("movie.mov");
    let thumbnail_file = temp_dir.path().join("thumbnails/file-preview.png");
    fs::create_dir_all(thumbnail_file.parent().unwrap()).expect("thumbnail dir");
    fs::write(&first_file, vec![1_u8; 64]).expect("first file");
    fs::write(&second_file, vec![2_u8; 128]).expect("second file");
    fs::write(&thumbnail_file, b"file thumbnail").expect("thumbnail file");
    let first_path = first_file.display().to_string();
    let second_path = second_file.display().to_string();

    core.capture_files(CaptureFilesRequest {
        file_paths: vec![first_path.clone(), second_path.clone()],
        file_items: vec![
            CapturedFileMetadata {
                path: first_path.clone(),
                file_name: "frame.png".to_string(),
                file_extension: Some("png".to_string()),
                byte_count: 64,
                is_directory: false,
                width: Some(1920),
                height: Some(1080),
                content_type: Some("public.png".to_string()),
            },
            CapturedFileMetadata {
                path: second_path.clone(),
                file_name: "movie.mov".to_string(),
                file_extension: Some("mov".to_string()),
                byte_count: 128,
                is_directory: false,
                width: Some(1280),
                height: Some(720),
                content_type: Some("com.apple.quicktime-movie".to_string()),
            },
        ],
        preview_relative_path: Some("thumbnails/file-preview.png".to_string()),
        preview_mime_type: Some("image/png".to_string()),
        preview_width: Some(420),
        preview_height: Some(320),
        preview_byte_count: 14,
        snapshot_relative_path: None,
        snapshot_byte_count: 0,
        source_bundle_id: Some("com.apple.finder".to_string()),
        source_app_name: Some("Finder".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 45,
        self_write_token: None,
    })
    .unwrap();

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let item = &page.items[0];

    assert_eq!(item.payload_asset_path, None);
    assert!(item
        .preview_asset_path
        .as_deref()
        .is_some_and(|path| path.ends_with("thumbnails/file-preview.png")));
    assert_eq!(item.size_bytes, 192);
    assert_eq!(item.file_items.len(), 2);
    assert_eq!(item.file_items[0].path, first_path);
    assert_eq!(item.file_items[0].byte_count, 64);
    assert_eq!(item.file_items[0].width, Some(1920));
    assert_eq!(item.file_items[0].height, Some(1080));
    assert_eq!(item.file_items[1].path, second_path);
    assert_eq!(
        item.file_items[1].content_type.as_deref(),
        Some("com.apple.quicktime-movie")
    );
}

#[test]
fn list_items_filters_by_type_and_search_text() {
    let (temp_dir, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Alpha search target from Safari".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 1,
        self_write_token: None,
    })
    .unwrap();
    fs::write(
        temp_dir.path().join("assets/filter.png"),
        b"filter image payload",
    )
    .expect("payload");
    core.capture_image(CaptureImageRequest {
        payload_relative_path: "assets/filter.png".to_string(),
        preview_relative_path: None,
        mime_type: Some("image/png".to_string()),
        width: 400,
        height: 300,
        byte_count: 20,
        source_bundle_id: Some("com.apple.Preview".to_string()),
        source_app_name: Some("Preview".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 2,
        self_write_token: None,
    })
    .unwrap();

    let image_page = core
        .list_items(
            ItemQuery {
                item_type: Some(ClipboardItemType::Image),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(image_page.total_count, 1);
    assert_eq!(image_page.items[0].item_type, ClipboardItemType::Image);

    let search_page = core
        .list_items(
            ItemQuery {
                search_text: Some("Alpha Safari".to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(search_page.total_count, 1);
    assert_eq!(
        search_page.items[0].source_app_name.as_deref(),
        Some("Safari")
    );
}

#[test]
fn list_items_searches_full_primary_text_beyond_ui_preview_prefix() {
    let (_temp_dir, mut core) = open_temp_core();
    let late_token = "late-token-after-ui-preview-500";
    let long_text = format!("{} {}", "a".repeat(520), late_token);
    let captured = core
        .capture_text(CaptureTextRequest {
            text: long_text.clone(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 3,
            self_write_token: None,
        })
        .unwrap();

    let search_page = core
        .list_items(
            ItemQuery {
                search_text: Some(late_token.to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();

    assert_eq!(search_page.total_count, 1);
    assert_eq!(search_page.items[0].id, captured.item_id);
    assert_eq!(
        search_page.items[0].primary_text.as_deref(),
        Some(long_text.as_str())
    );
}

#[test]
fn list_items_search_handles_simple_tokenizer_edge_cases() {
    let (_, mut core) = open_temp_core();
    core.capture_text(text_capture_request("Punctuation !!! target", 1))
        .unwrap();
    core.capture_text(text_capture_request("Emoji 😀 target", 2))
        .unwrap();
    core.capture_text(text_capture_request("Apostrophe can't target", 3))
        .unwrap();
    core.capture_text(text_capture_request("Wildcard %_ target", 4))
        .unwrap();

    let punctuation_query = ItemQuery {
        search_text: Some("!!!".to_string()),
        ..ItemQuery::default()
    };
    let punctuation_page = core
        .list_items(punctuation_query.clone(), PageRequest::default())
        .unwrap();
    assert_eq!(punctuation_page.total_count, 1);
    assert_eq!(punctuation_page.items[0].summary, "Punctuation !!! target");
    assert_eq!(core.active_item_count(&punctuation_query).unwrap(), 1);

    let emoji_query = ItemQuery {
        search_text: Some("😀".to_string()),
        ..ItemQuery::default()
    };
    let emoji_page = core
        .list_items(emoji_query.clone(), PageRequest::default())
        .unwrap();
    assert_eq!(emoji_page.total_count, 1);
    assert_eq!(emoji_page.items[0].summary, "Emoji 😀 target");
    assert_eq!(core.active_item_count(&emoji_query).unwrap(), 1);

    let apostrophe_query = ItemQuery {
        search_text: Some("can't".to_string()),
        ..ItemQuery::default()
    };
    let apostrophe_page = core
        .list_items(apostrophe_query.clone(), PageRequest::default())
        .unwrap();
    assert_eq!(apostrophe_page.total_count, 1);
    assert_eq!(apostrophe_page.items[0].summary, "Apostrophe can't target");
    assert_eq!(core.active_item_count(&apostrophe_query).unwrap(), 1);

    let wildcard_query = ItemQuery {
        search_text: Some("%_".to_string()),
        ..ItemQuery::default()
    };
    let wildcard_page = core
        .list_items(wildcard_query.clone(), PageRequest::default())
        .unwrap();
    assert_eq!(wildcard_page.total_count, 1);
    assert_eq!(wildcard_page.items[0].summary, "Wildcard %_ target");
    assert_eq!(core.active_item_count(&wildcard_query).unwrap(), 1);

    let clear_result = core.clear_items(emoji_query).unwrap();
    assert_eq!(clear_result.affected_count, 1);
    let remaining_page = core
        .list_items(
            ItemQuery {
                search_text: Some("😀".to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(remaining_page.total_count, 0);
}

#[test]
fn list_items_searches_chinese_exact_and_pinyin() {
    let (_, mut core) = open_temp_core();
    let captured = core
        .capture_text(text_capture_request("我将点燃星海计划", 1))
        .unwrap();

    let chinese_page = core
        .list_items(
            ItemQuery {
                search_text: Some("星海".to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(chinese_page.total_count, 1);
    assert_eq!(chinese_page.items[0].id, captured.item_id);

    let pinyin_page = core
        .list_items(
            ItemQuery {
                search_text: Some("xing hai".to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(pinyin_page.total_count, 1);
    assert_eq!(pinyin_page.items[0].id, captured.item_id);
}

#[test]
fn list_source_apps_and_filter_items_by_source_app_id() {
    let (temp_dir, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Source filter text from Safari".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: Some("app-icons/safari.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 1,
        self_write_token: None,
    })
    .unwrap();
    std::thread::sleep(std::time::Duration::from_millis(2));
    fs::write(
        temp_dir.path().join("assets/source-preview.png"),
        b"source filter image payload",
    )
    .expect("payload");
    core.capture_image(CaptureImageRequest {
        payload_relative_path: "assets/source-preview.png".to_string(),
        preview_relative_path: None,
        mime_type: Some("image/png".to_string()),
        width: 120,
        height: 90,
        byte_count: 27,
        source_bundle_id: Some("com.apple.Preview".to_string()),
        source_app_name: Some("Preview".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: Some("app-icons/preview.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 2,
        self_write_token: None,
    })
    .unwrap();

    let source_page = core
        .list_source_apps(PageRequest {
            limit: 10,
            offset: 0,
        })
        .unwrap();
    assert_eq!(source_page.total_count, 2);
    assert_eq!(source_page.apps.len(), 2);
    assert_eq!(source_page.apps[0].name, "Preview");
    assert_eq!(source_page.apps[0].item_count, 1);
    assert!(source_page.apps[0]
        .icon_path
        .as_deref()
        .unwrap()
        .ends_with("app-icons/preview.tiff"));

    let safari = source_page
        .apps
        .iter()
        .find(|app| app.name == "Safari")
        .expect("Safari source");
    let safari_page = core
        .list_items(
            ItemQuery {
                source_app_id: Some(safari.id.clone()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(safari_page.total_count, 1);
    assert_eq!(
        safari_page.items[0].source_app_name.as_deref(),
        Some("Safari")
    );
}

#[test]
fn item_management_pins_and_deletes_single_item() {
    let (_, mut core) = open_temp_core();
    let pinned = core
        .capture_text(CaptureTextRequest {
            text: "Pinned management sample".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    std::thread::sleep(std::time::Duration::from_millis(2));
    let regular = core
        .capture_text(CaptureTextRequest {
            text: "Regular management sample".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();

    let pin_result = core
        .set_item_pinboard_membership(&pinned.item_id, DEFAULT_PINBOARD_ID, true)
        .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();

    assert_eq!(pin_result.affected_count, 1);
    assert_eq!(page.items[0].id, regular.item_id);
    assert!(page
        .items
        .iter()
        .any(|item| item.id == pinned.item_id && item.is_pinned));

    let delete_result = core.delete_item(&pinned.item_id).unwrap();
    let page_after_delete = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let deleted_item_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items WHERE id = ?1",
            params![pinned.item_id],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(delete_result.affected_count, 1);
    assert_eq!(page_after_delete.total_count, 1);
    assert_eq!(deleted_item_count, 0);
}

#[test]
fn deleting_image_item_removes_generated_payload_and_thumbnail_files() {
    let (temp_dir, mut core) = open_temp_core();
    let payload_path = temp_dir.path().join("assets/deleted-image.webp");
    let thumbnail_path = temp_dir.path().join("thumbnails/deleted-image.webp");
    fs::write(&payload_path, b"deleted image payload").expect("payload");
    fs::write(&thumbnail_path, b"deleted image thumbnail").expect("thumbnail");

    let image = core
        .capture_image(CaptureImageRequest {
            payload_relative_path: "assets/deleted-image.webp".to_string(),
            preview_relative_path: Some("thumbnails/deleted-image.webp".to_string()),
            mime_type: Some("image/webp".to_string()),
            width: 320,
            height: 180,
            byte_count: 21,
            source_bundle_id: Some("com.apple.Preview".to_string()),
            source_app_name: Some("Preview".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 90,
            self_write_token: None,
        })
        .unwrap();

    let delete_result = core.delete_item(&image.item_id).unwrap();

    let item_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items WHERE id = ?1",
            params![image.item_id],
            |row| row.get(0),
        )
        .unwrap();
    let asset_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
            row.get(0)
        })
        .unwrap();

    assert_eq!(delete_result.affected_count, 1);
    assert_eq!(item_count, 0);
    assert_eq!(asset_count, 0);
    assert!(!payload_path.exists());
    assert!(!thumbnail_path.exists());
}

#[test]
fn empty_default_pinboard_is_hidden_until_used() {
    let (_, core) = open_temp_core();

    let pinboards = core.list_pinboards().unwrap();

    assert_eq!(pinboards.total_count, 0);
    assert!(pinboards.pinboards.is_empty());
}

#[test]
fn pinned_items_enter_default_pinboard_and_leave_on_unpin() {
    let (_, mut core) = open_temp_core();
    let pinned = core
        .capture_text(CaptureTextRequest {
            text: "Pinboard membership sample".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();

    let pin_result = core
        .set_item_pinboard_membership(&pinned.item_id, DEFAULT_PINBOARD_ID, true)
        .unwrap();
    let pinboards = core.list_pinboards().unwrap();
    let pinned_page = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(DEFAULT_PINBOARD_ID.to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    let membership_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM pinboard_items WHERE pinboard_id = ?1 AND item_id = ?2",
            params![DEFAULT_PINBOARD_ID, pinned.item_id],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(pin_result.affected_count, 1);
    assert_eq!(pinboards.total_count, 1);
    assert_eq!(pinboards.pinboards[0].title, "固定");
    assert_eq!(pinboards.pinboards[0].item_count, 1);
    assert_eq!(pinned_page.total_count, 1);
    assert_eq!(pinned_page.items[0].id, pinned.item_id);
    assert!(pinned_page.items[0].is_pinned);
    assert_eq!(membership_count, 1);

    let unpin_result = core
        .set_item_pinboard_membership(&pinned.item_id, DEFAULT_PINBOARD_ID, false)
        .unwrap();
    let pinned_page_after_unpin = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(DEFAULT_PINBOARD_ID.to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();

    assert_eq!(unpin_result.affected_count, 1);
    assert_eq!(pinned_page_after_unpin.total_count, 0);
}

#[test]
fn pinboard_crud_updates_title_color_and_deletes_owned_items() {
    let (_, mut core) = open_temp_core();
    let first = core
        .capture_text(CaptureTextRequest {
            text: "Pinboard CRUD owned item".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    let second = core
        .capture_text(CaptureTextRequest {
            text: "Pinboard CRUD shared item".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.Notes".to_string()),
            source_app_name: Some("Notes".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();

    let board = core
        .create_pinboard("  Research  ", Some(4_294_620_928))
        .unwrap();
    let renamed = core.rename_pinboard(&board.id, "  AI Clips  ").unwrap();
    let recolored = core
        .update_pinboard_color(&board.id, 4_290_925_536)
        .unwrap();
    core.set_item_pinboard_membership(&first.item_id, &board.id, true)
        .unwrap();
    core.set_item_pinboard_membership(&second.item_id, &board.id, true)
        .unwrap();
    core.set_item_pinboard_membership(&second.item_id, DEFAULT_PINBOARD_ID, true)
        .unwrap();

    let before_delete = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(board.id.clone()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    let delete_result = core.delete_pinboard(&board.id).unwrap();
    let active_page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let deleted_board_page = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(board.id.clone()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    let default_board_page = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(DEFAULT_PINBOARD_ID.to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();

    assert_eq!(board.title, "Research");
    assert_eq!(board.color_code, 4_294_620_928);
    assert_eq!(renamed.title, "AI Clips");
    assert_eq!(recolored.color_code, 4_290_925_536);
    assert_eq!(before_delete.total_count, 2);
    assert_eq!(delete_result.affected_count, 1);
    assert!(!active_page
        .items
        .iter()
        .any(|item| item.id == first.item_id));
    assert!(active_page
        .items
        .iter()
        .any(|item| item.id == second.item_id));
    assert_eq!(deleted_board_page.total_count, 0);
    assert_eq!(default_board_page.total_count, 1);
    assert_eq!(default_board_page.items[0].id, second.item_id);
}

#[test]
fn delete_pinboard_cleans_many_items_in_bulk_and_keeps_shared_members() {
    let (_, mut core) = open_temp_core();
    let board = core
        .create_pinboard("Bulk delete", Some(4_294_620_928))
        .unwrap();
    let shared_board = core
        .create_pinboard("Shared survivors", Some(4_283_973_119))
        .unwrap();

    let mut shared_ids = Vec::new();
    for index in 0..120 {
        let captured = core
            .capture_text(CaptureTextRequest {
                text: format!("Bulk Pinboard item {index}"),
                detected_link: None,
                display_rtf_relative_path: None,
                display_rtf_mime_type: None,
                display_rtf_byte_count: 0,
                source_bundle_id: Some("com.apple.TextEdit".to_string()),
                source_app_name: Some("TextEdit".to_string()),
                source_bundle_path: None,
                source_icon_relative_path: None,
                source_confidence: SourceConfidence::High,
                pasteboard_change_count: index + 10,
                self_write_token: None,
            })
            .unwrap();
        core.set_item_pinboard_membership(&captured.item_id, &board.id, true)
            .unwrap();
        if index % 12 == 0 {
            core.set_item_pinboard_membership(&captured.item_id, &shared_board.id, true)
                .unwrap();
            shared_ids.push(captured.item_id);
        }
    }

    let delete_result = core.delete_pinboard(&board.id).unwrap();
    let deleted_board_page = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(board.id.clone()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    let shared_page = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(shared_board.id.clone()),
                ..ItemQuery::default()
            },
            PageRequest {
                limit: 200,
                offset: 0,
            },
        )
        .unwrap();
    let active_page = core
        .list_items(
            ItemQuery::default(),
            PageRequest {
                limit: 200,
                offset: 0,
            },
        )
        .unwrap();

    assert_eq!(delete_result.affected_count, 110);
    assert_eq!(deleted_board_page.total_count, 0);
    assert_eq!(shared_page.total_count, shared_ids.len() as i64);
    assert_eq!(active_page.total_count, shared_ids.len() as i64);
    for shared_id in shared_ids {
        assert!(active_page.items.iter().any(|item| item.id == shared_id));
    }
}

#[test]
fn pinned_items_survive_history_retention_and_max_item_pruning() {
    let (_, mut core) = open_temp_core();
    let pinned = core
        .capture_text(CaptureTextRequest {
            text: "Protected pinboard item".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    core.set_item_pinboard_membership(&pinned.item_id, DEFAULT_PINBOARD_ID, true)
        .unwrap();
    core.capture_text(CaptureTextRequest {
        text: "Removable old item".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 2,
        self_write_token: None,
    })
    .unwrap();

    let old_timestamp = now_ms() - 400 * 24 * 60 * 60 * 1000;
    core.connection
        .execute(
            "UPDATE clipboard_items SET last_copied_at_ms = ?1 WHERE summary IN (?2, ?3)",
            params![
                old_timestamp,
                "Protected pinboard item",
                "Removable old item"
            ],
        )
        .unwrap();

    let mut preferences = core.get_preferences().unwrap();
    preferences.history.retention_days = 1;
    preferences.history.max_items = 1;
    core.update_preferences(preferences).unwrap();

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let pinned_page = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(DEFAULT_PINBOARD_ID.to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();

    assert_eq!(page.total_count, 1);
    assert_eq!(page.items[0].id, pinned.item_id);
    assert_eq!(pinned_page.total_count, 1);
    assert_eq!(pinned_page.items[0].id, pinned.item_id);
}

#[test]
fn clear_items_deletes_matching_unpinned_items_only() {
    let (_, mut core) = open_temp_core();
    let pinned = core
        .capture_text(CaptureTextRequest {
            text: "Clear scope pinned text".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    core.set_item_pinboard_membership(&pinned.item_id, DEFAULT_PINBOARD_ID, true)
        .unwrap();
    core.capture_text(CaptureTextRequest {
        text: "Clear scope removable text".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Safari".to_string()),
        source_app_name: Some("Safari".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 2,
        self_write_token: None,
    })
    .unwrap();
    core.capture_text(CaptureTextRequest {
        text: "Different scope sample".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.Notes".to_string()),
        source_app_name: Some("Notes".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 3,
        self_write_token: None,
    })
    .unwrap();

    let clear_result = core
        .clear_items(ItemQuery {
            item_type: Some(ClipboardItemType::Text),
            search_text: Some("Clear scope".to_string()),
            ..ItemQuery::default()
        })
        .unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();

    assert_eq!(clear_result.affected_count, 1);
    assert_eq!(page.total_count, 2);
    assert!(page.items.iter().any(|item| item.id == pinned.item_id));
    assert!(page
        .items
        .iter()
        .all(|item| item.summary != "Clear scope removable text"));
}

#[test]
fn default_preferences_document_is_seeded() {
    let (_, core) = open_temp_core();

    let preferences = core.get_preferences().unwrap();
    let row: (i64, String) = core
        .connection
        .query_row(
            "SELECT schema_version, value_json FROM preference_documents WHERE id = 'current'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();

    assert_eq!(row.0, CURRENT_SCHEMA_VERSION);
    assert!(row.1.contains("\"default_panel_height\":320"));
    assert_eq!(preferences.general.default_panel_height, 320);
    assert!(row.1.contains("\"copy_completion_hud_enabled\":true"));
    assert!(preferences.general.copy_completion_hud_enabled);
    assert!(row.1.contains("\"external_copy_sound_enabled\":true"));
    assert!(preferences.general.external_copy_sound_enabled);
    assert_eq!(preferences.history.max_items, 5000);
    assert_eq!(preferences.appearance.mode, "system");
    assert!(preferences.link_preview.web_preview_enabled);
    let open_panel = preferences.shortcuts.open_panel.as_ref().unwrap();
    assert_eq!(open_panel.key_code, 7);
    assert_eq!(
        open_panel.modifiers,
        vec!["command".to_string(), "shift".to_string()]
    );
    assert_eq!(
        preferences
            .shortcuts
            .previous_pinboard
            .as_ref()
            .map(|shortcut| (shortcut.key_code, shortcut.modifiers.clone())),
        Some((123, vec!["command".to_string()]))
    );
    assert_eq!(
        preferences
            .shortcuts
            .next_pinboard
            .as_ref()
            .map(|shortcut| (shortcut.key_code, shortcut.modifiers.clone())),
        Some((124, vec!["command".to_string()]))
    );
    assert_eq!(preferences.shortcuts.quick_paste_modifier, "command");
    assert_eq!(preferences.shortcuts.plain_text_modifier, "shift");
    assert!(!preferences.shortcuts.paste_directly_to_target);
    assert!(!preferences.shortcuts.always_paste_as_plain_text);
    assert_eq!(
        preferences.ignore_list.ignored_app_identifiers,
        vec![
            "com.apple.Passwords".to_string(),
            "com.apple.keychainaccess".to_string()
        ]
    );
    assert!(row.1.contains(
        "\"ignored_app_identifiers\":[\"com.apple.Passwords\",\"com.apple.keychainaccess\"]"
    ));
    assert!(preferences.ignore_list.window_title_keywords.is_empty());
    assert!(!preferences.ignore_list.skip_unknown_source);
}

#[test]
fn old_empty_ignore_list_is_migrated_once_to_default_privacy_apps() {
    let temp_dir = TempDir::new().expect("temp dir");
    let core = ClipboardCore::open(temp_dir.path()).expect("open core");
    let mut old_preferences = PreferencesDocument::default();
    old_preferences.ignore_list.ignored_app_identifiers.clear();
    let old_json = serde_json::to_string(&old_preferences).unwrap();
    core.connection
        .execute(
            r#"
            UPDATE preference_documents
            SET schema_version = 9, value_json = ?1
            WHERE id = 'current'
            "#,
            params![old_json],
        )
        .unwrap();
    drop(core);

    let mut migrated = ClipboardCore::open(temp_dir.path()).expect("reopen migrated core");
    let migrated_preferences = migrated.get_preferences().unwrap();
    let row_schema_version: i64 = migrated
        .connection
        .query_row(
            "SELECT schema_version FROM preference_documents WHERE id = 'current'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(row_schema_version, CURRENT_SCHEMA_VERSION);
    assert_eq!(
        migrated_preferences.ignore_list.ignored_app_identifiers,
        vec![
            "com.apple.Passwords".to_string(),
            "com.apple.keychainaccess".to_string()
        ]
    );

    let mut user_preferences = migrated_preferences;
    user_preferences.ignore_list.ignored_app_identifiers.clear();
    let saved = migrated.update_preferences(user_preferences).unwrap();
    assert!(saved.ignore_list.ignored_app_identifiers.is_empty());
    drop(migrated);

    let reopened = ClipboardCore::open(temp_dir.path()).expect("reopen after explicit removal");
    assert!(reopened
        .get_preferences()
        .unwrap()
        .ignore_list
        .ignored_app_identifiers
        .is_empty());
}

#[test]
fn old_default_open_panel_shortcut_is_migrated_to_current_default() {
    let temp_dir = TempDir::new().expect("temp dir");
    let core = ClipboardCore::open(temp_dir.path()).expect("open core");
    let mut old_preferences = PreferencesDocument::default();
    let shortcut = old_preferences.shortcuts.open_panel.as_mut().unwrap();
    shortcut.key_code = 9;
    shortcut.modifiers = vec!["command".to_string(), "shift".to_string()];
    let old_json = serde_json::to_string(&old_preferences).unwrap();
    core.connection
        .execute(
            r#"
            UPDATE preference_documents
            SET schema_version = 10, value_json = ?1
            WHERE id = 'current'
            "#,
            params![old_json],
        )
        .unwrap();
    drop(core);

    let migrated = ClipboardCore::open(temp_dir.path()).expect("reopen migrated core");
    let migrated_preferences = migrated.get_preferences().unwrap();
    let row_schema_version: i64 = migrated
        .connection
        .query_row(
            "SELECT schema_version FROM preference_documents WHERE id = 'current'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(row_schema_version, CURRENT_SCHEMA_VERSION);
    let open_panel = migrated_preferences.shortcuts.open_panel.as_ref().unwrap();
    assert_eq!(open_panel.key_code, 7);
    assert_eq!(
        open_panel.modifiers,
        vec!["command".to_string(), "shift".to_string()]
    );
    assert_eq!(
        migrated_preferences.shortcuts.quick_paste_modifier,
        "command"
    );
    assert_eq!(migrated_preferences.shortcuts.plain_text_modifier, "shift");
}

#[test]
fn preferences_update_persists_normalized_document() {
    let (_, mut core) = open_temp_core();
    let mut preferences = core.get_preferences().unwrap();
    preferences.general.default_panel_height = 999;
    preferences.general.copy_completion_hud_enabled = false;
    preferences.general.external_copy_sound_enabled = false;
    preferences.history.max_items = 10;
    preferences.history.retention_days = 999;
    preferences.history.record_images = false;
    preferences.history.record_files = true;
    preferences.appearance.mode = "neon".to_string();
    preferences.appearance.item_density = "compact".to_string();
    preferences.link_preview.web_preview_enabled = false;
    let shortcut = preferences.shortcuts.open_panel.as_mut().unwrap();
    shortcut.key_code = 11;
    shortcut.modifiers = vec![
        "shift".to_string(),
        "cmd".to_string(),
        "alt".to_string(),
        "command".to_string(),
        "ignored".to_string(),
    ];
    preferences.shortcuts.quick_paste_modifier = "ctrl".to_string();
    preferences.shortcuts.plain_text_modifier = "alt".to_string();
    preferences.shortcuts.paste_directly_to_target = true;
    preferences.shortcuts.always_paste_as_plain_text = true;
    preferences.ignore_list.ignored_app_identifiers = vec![
        "  com.apple.Terminal  ".to_string(),
        "terminal".to_string(),
        "COM.APPLE.TERMINAL".to_string(),
        "".to_string(),
    ];
    preferences.ignore_list.window_title_keywords = vec![
        " 密码 ".to_string(),
        "验证码".to_string(),
        "密码".to_string(),
    ];
    preferences.ignore_list.skip_unknown_source = true;

    let saved = core.update_preferences(preferences).unwrap();
    let reloaded = core.get_preferences().unwrap();

    assert_eq!(saved.general.default_panel_height, 999);
    assert!(!saved.general.copy_completion_hud_enabled);
    assert!(!saved.general.external_copy_sound_enabled);
    assert_eq!(saved.history.max_items, 5000);
    assert_eq!(saved.history.retention_days, 365);
    assert!(saved.history.record_images);
    assert!(saved.history.record_files);
    assert_eq!(saved.appearance.mode, "system");
    assert_eq!(saved.appearance.item_density, "compact");
    assert!(!saved.link_preview.web_preview_enabled);
    let open_panel = saved.shortcuts.open_panel.as_ref().unwrap();
    assert_eq!(open_panel.key_code, 11);
    assert_eq!(
        open_panel.modifiers,
        vec![
            "command".to_string(),
            "option".to_string(),
            "shift".to_string()
        ]
    );
    assert_eq!(saved.shortcuts.quick_paste_modifier, "control");
    assert_eq!(saved.shortcuts.plain_text_modifier, "option");
    assert!(saved.shortcuts.paste_directly_to_target);
    assert!(saved.shortcuts.always_paste_as_plain_text);
    assert_eq!(
        saved.ignore_list.ignored_app_identifiers,
        vec!["com.apple.Terminal".to_string(), "terminal".to_string()]
    );
    assert_eq!(
        saved.ignore_list.window_title_keywords,
        vec!["密码".to_string(), "验证码".to_string()]
    );
    assert!(saved.ignore_list.skip_unknown_source);
    assert_eq!(reloaded, saved);
}

#[test]
fn preferences_update_falls_back_when_shortcut_is_not_recordable() {
    let (_, mut core) = open_temp_core();
    let mut preferences = core.get_preferences().unwrap();
    let shortcut = preferences.shortcuts.open_panel.as_mut().unwrap();
    shortcut.key_code = 999;
    shortcut.modifiers = vec!["shift".to_string()];

    let saved = core.update_preferences(preferences).unwrap();

    let open_panel = saved.shortcuts.open_panel.as_ref().unwrap();
    assert_eq!(open_panel.key_code, 7);
    assert_eq!(
        open_panel.modifiers,
        vec!["command".to_string(), "shift".to_string()]
    );
}

#[test]
fn preferences_update_keeps_unassigned_shortcuts() {
    let (_, mut core) = open_temp_core();
    let mut preferences = core.get_preferences().unwrap();
    preferences.shortcuts.open_panel = None;
    preferences.shortcuts.next_pinboard = None;
    preferences.shortcuts.previous_pinboard = None;

    let saved = core.update_preferences(preferences).unwrap();
    let reloaded = core.get_preferences().unwrap();

    assert!(saved.shortcuts.open_panel.is_none());
    assert!(saved.shortcuts.next_pinboard.is_none());
    assert!(saved.shortcuts.previous_pinboard.is_none());
    assert_eq!(reloaded, saved);
}

#[test]
fn preferences_parse_keeps_backward_compatible_missing_ignore_list() {
    let legacy_json = r#"
    {
        "general": {
            "launch_at_login": false,
            "show_menu_bar_item": true,
            "default_panel_height": 320
        },
        "history": {
            "max_items": 500,
            "retention_days": 30,
            "record_images": true,
            "record_files": false
        },
        "appearance": {
            "mode": "system",
            "item_density": "standard",
            "preview_popover_enabled": true
        }
    }
    "#;

    let preferences = preferences::parse_preferences_document(legacy_json).unwrap();

    assert!(preferences.general.copy_completion_hud_enabled);
    assert!(preferences.general.external_copy_sound_enabled);
    assert_eq!(
        preferences.ignore_list.ignored_app_identifiers,
        vec![
            "com.apple.Passwords".to_string(),
            "com.apple.keychainaccess".to_string()
        ]
    );
    assert!(preferences.ignore_list.window_title_keywords.is_empty());
    assert_eq!(preferences.history.max_items, 5000);
    assert!(preferences.history.record_images);
    assert!(preferences.history.record_files);
    assert!(preferences.link_preview.web_preview_enabled);
    assert!(!preferences.shortcuts.paste_directly_to_target);
    assert!(!preferences.shortcuts.always_paste_as_plain_text);
    assert!(!preferences.ignore_list.skip_unknown_source);
}

#[test]
fn preferences_update_keeps_internal_max_items_as_high_guard() {
    let (_, mut core) = open_temp_core();
    for index in 0..55 {
        core.capture_text(CaptureTextRequest {
            text: format!("Max item pruning sample {index:02}"),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: index,
            self_write_token: None,
        })
        .unwrap();
    }

    let mut preferences = core.get_preferences().unwrap();
    preferences.history.max_items = 50;
    preferences.history.retention_days = 365;
    let saved = core.update_preferences(preferences).unwrap();

    let active_page = core
        .list_items(
            ItemQuery::default(),
            PageRequest {
                limit: 200,
                offset: 0,
            },
        )
        .unwrap();

    assert_eq!(saved.history.max_items, 5000);
    assert_eq!(active_page.total_count, 55);
    assert_eq!(active_page.items.len(), 55);
    assert!(active_page
        .items
        .iter()
        .any(|item| item.summary == "Max item pruning sample 54"));
    assert!(active_page
        .items
        .iter()
        .any(|item| item.summary == "Max item pruning sample 00"));
}

#[test]
fn preferences_update_prunes_history_by_retention_days() {
    let (_, mut core) = open_temp_core();
    let old_result = core
        .capture_text(CaptureTextRequest {
            text: "Old retention sample".to_string(),
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.TextEdit".to_string()),
            source_app_name: Some("TextEdit".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    core.capture_text(CaptureTextRequest {
        text: "Fresh retention sample".to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: Some("com.apple.TextEdit".to_string()),
        source_app_name: Some("TextEdit".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 2,
        self_write_token: None,
    })
    .unwrap();

    let old_timestamp = now_ms() - 3 * 24 * 60 * 60 * 1000;
    core.connection
        .execute(
            r#"
            UPDATE clipboard_items
            SET first_copied_at_ms = ?1, last_copied_at_ms = ?1, updated_at_ms = ?1
            WHERE id = ?2
            "#,
            params![old_timestamp, old_result.item_id],
        )
        .unwrap();

    let mut preferences = core.get_preferences().unwrap();
    preferences.history.max_items = 500;
    preferences.history.retention_days = 1;
    core.update_preferences(preferences).unwrap();

    let active_page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let old_item_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items WHERE summary = 'Old retention sample'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let old_fts_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH 'Old'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(active_page.total_count, 1);
    assert_eq!(active_page.items[0].summary, "Fresh retention sample");
    assert_eq!(old_item_count, 0);
    assert_eq!(old_fts_count, 0);
}

#[test]
fn retention_update_purges_generated_assets_but_keeps_user_files() {
    let (temp_dir, mut core) = open_temp_core();
    let user_dir = TempDir::new().expect("user dir");
    let user_file_path = user_dir.path().join("Quarterly Report.pdf");
    fs::write(&user_file_path, b"user-owned file").expect("user file");

    let payload_path = temp_dir.path().join("assets/old-image.png");
    let thumbnail_path = temp_dir.path().join("thumbnails/old-image.png");
    let snapshot_path = temp_dir.path().join("assets/file-snapshots/old-files.json");
    fs::create_dir_all(snapshot_path.parent().unwrap()).expect("snapshot dir");
    fs::write(&payload_path, b"old image payload").expect("payload");
    fs::write(&thumbnail_path, b"old image thumbnail").expect("thumbnail");
    fs::write(&snapshot_path, b"{\"paths\":[\"Quarterly Report.pdf\"]}").expect("snapshot");

    core.capture_image(CaptureImageRequest {
        payload_relative_path: "assets/old-image.png".to_string(),
        preview_relative_path: Some("thumbnails/old-image.png".to_string()),
        mime_type: Some("image/png".to_string()),
        width: 320,
        height: 180,
        byte_count: 17,
        source_bundle_id: Some("com.apple.Preview".to_string()),
        source_app_name: Some("Preview".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 30,
        self_write_token: None,
    })
    .unwrap();
    core.capture_files(CaptureFilesRequest {
        file_paths: vec![user_file_path.display().to_string()],
        file_items: vec![],
        preview_relative_path: None,
        preview_mime_type: None,
        preview_width: None,
        preview_height: None,
        preview_byte_count: 0,
        snapshot_relative_path: Some("assets/file-snapshots/old-files.json".to_string()),
        snapshot_byte_count: 35,
        source_bundle_id: Some("com.apple.finder".to_string()),
        source_app_name: Some("Finder".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 31,
        self_write_token: None,
    })
    .unwrap();

    let old_timestamp = now_ms() - 3 * 24 * 60 * 60 * 1000;
    core.connection
        .execute(
            r#"
            UPDATE clipboard_items
            SET first_copied_at_ms = ?1, last_copied_at_ms = ?1, updated_at_ms = ?1
            "#,
            params![old_timestamp],
        )
        .unwrap();

    let mut preferences = core.get_preferences().unwrap();
    preferences.history.retention_days = 1;
    core.update_preferences(preferences).unwrap();

    let active_page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let item_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_items", [], |row| row.get(0))
        .unwrap();
    let asset_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
            row.get(0)
        })
        .unwrap();
    let format_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_formats", [], |row| {
            row.get(0)
        })
        .unwrap();
    let capture_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_captures", [], |row| {
            row.get(0)
        })
        .unwrap();

    assert_eq!(active_page.total_count, 0);
    assert_eq!(item_count, 0);
    assert_eq!(asset_count, 0);
    assert_eq!(format_count, 0);
    assert_eq!(capture_count, 0);
    assert!(!payload_path.exists());
    assert!(!thumbnail_path.exists());
    assert!(!snapshot_path.exists());
    assert!(user_file_path.exists());
}

#[test]
fn maintenance_purges_soft_deleted_items_and_assets() {
    let (temp_dir, mut core) = open_temp_core();
    let payload_path = temp_dir.path().join("assets/deleted.png");
    let thumbnail_path = temp_dir.path().join("thumbnails/deleted.png");
    fs::write(&payload_path, b"deleted image payload").expect("payload");
    fs::write(&thumbnail_path, b"deleted image thumbnail").expect("thumbnail");

    let result = core
        .capture_image(CaptureImageRequest {
            payload_relative_path: "assets/deleted.png".to_string(),
            preview_relative_path: Some("thumbnails/deleted.png".to_string()),
            mime_type: Some("image/png".to_string()),
            width: 320,
            height: 180,
            byte_count: 21,
            source_bundle_id: Some("com.apple.Preview".to_string()),
            source_app_name: Some("Preview".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 90,
            self_write_token: None,
        })
        .unwrap();
    core.connection
        .execute(
            "UPDATE clipboard_items SET deleted_at_ms = ?1 WHERE id = ?2",
            params![now_ms(), result.item_id],
        )
        .unwrap();

    let maintenance = core.run_maintenance().unwrap();

    assert_eq!(maintenance.purged_item_count, 1);
    assert_eq!(maintenance.deleted_asset_row_count, 2);
    assert_eq!(maintenance.deleted_asset_file_count, 2);
    assert!(maintenance.reclaimed_bytes > 0);
    assert!(!payload_path.exists());
    assert!(!thumbnail_path.exists());

    let item_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_items", [], |row| row.get(0))
        .unwrap();
    let asset_count: i64 = core
        .connection
        .query_row("SELECT COUNT(*) FROM clipboard_assets", [], |row| {
            row.get(0)
        })
        .unwrap();
    let fts_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH 'Preview'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(item_count, 0);
    assert_eq!(asset_count, 0);
    assert_eq!(fts_count, 0);
}

#[test]
fn maintenance_removes_orphan_files_and_keeps_active_assets() {
    let (temp_dir, mut core) = open_temp_core();
    let payload_path = temp_dir.path().join("assets/active.png");
    let thumbnail_path = temp_dir.path().join("thumbnails/active.png");
    let icon_path = temp_dir.path().join("app-icons/preview.tiff");
    fs::create_dir_all(icon_path.parent().unwrap()).expect("icon dir");
    fs::write(&payload_path, b"active image payload").expect("payload");
    fs::write(&thumbnail_path, b"active image thumbnail").expect("thumbnail");
    fs::write(&icon_path, b"active app icon").expect("icon");
    core.capture_image(CaptureImageRequest {
        payload_relative_path: "assets/active.png".to_string(),
        preview_relative_path: Some("thumbnails/active.png".to_string()),
        mime_type: Some("image/png".to_string()),
        width: 640,
        height: 480,
        byte_count: 20,
        source_bundle_id: Some("com.apple.Preview".to_string()),
        source_app_name: Some("Preview".to_string()),
        source_bundle_path: None,
        source_icon_relative_path: Some("app-icons/preview.tiff".to_string()),
        source_confidence: SourceConfidence::High,
        pasteboard_change_count: 91,
        self_write_token: None,
    })
    .unwrap();

    let orphan_asset = temp_dir.path().join("assets/orphan.bin");
    let orphan_thumbnail = temp_dir.path().join("thumbnails/orphan.png");
    let orphan_icon = temp_dir.path().join("app-icons/orphan.tiff");
    let orphan_snapshot = temp_dir.path().join("assets/file-snapshots/orphan.json");
    let staging_file = temp_dir.path().join("staging/leftover.tmp");
    fs::create_dir_all(orphan_snapshot.parent().unwrap()).expect("snapshot dir");
    fs::write(&orphan_asset, b"orphan asset").expect("orphan asset");
    fs::write(&orphan_thumbnail, b"orphan thumbnail").expect("orphan thumbnail");
    fs::write(&orphan_icon, b"orphan icon").expect("orphan icon");
    fs::write(&orphan_snapshot, b"orphan snapshot").expect("orphan snapshot");
    fs::write(&staging_file, b"staging leftover").expect("staging");

    let maintenance = core.run_maintenance().unwrap();

    assert_eq!(maintenance.purged_item_count, 0);
    assert_eq!(maintenance.deleted_asset_row_count, 0);
    assert_eq!(maintenance.deleted_asset_file_count, 0);
    assert_eq!(maintenance.deleted_orphan_file_count, 4);
    assert!(payload_path.exists());
    assert!(thumbnail_path.exists());
    assert!(icon_path.exists());
    assert!(!orphan_asset.exists());
    assert!(!orphan_thumbnail.exists());
    assert!(!orphan_icon.exists());
    assert!(!orphan_snapshot.exists());
    assert!(staging_file.exists());

    let active_page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(active_page.total_count, 1);
    assert_eq!(active_page.items[0].item_type, ClipboardItemType::Image);
}

#[test]
fn maintenance_preserves_and_purges_link_metadata_assets() {
    let (temp_dir, mut core) = open_temp_core();
    let icon_path = temp_dir.path().join("assets/link-icons/example.png");
    let image_path = temp_dir.path().join("assets/link-previews/example.png");
    fs::create_dir_all(icon_path.parent().unwrap()).expect("link icon dir");
    fs::create_dir_all(image_path.parent().unwrap()).expect("link image dir");
    fs::write(&icon_path, b"link icon").expect("icon");
    fs::write(&image_path, b"link preview").expect("image");

    let result = core
        .capture_text(CaptureTextRequest {
            text: "https://example.com".to_string(),
            detected_link: Some(CaptureDetectedLink {
                original_text: "https://example.com".to_string(),
                canonical_url: "https://example.com".to_string(),
                display_url: "https://example.com".to_string(),
                host: "example.com".to_string(),
                metadata_state: LinkMetadataState::Ready,
            }),
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id: Some("com.apple.Safari".to_string()),
            source_app_name: Some("Safari".to_string()),
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::High,
            pasteboard_change_count: 92,
            self_write_token: None,
        })
        .unwrap();
    core.connection
        .execute(
            r#"
            UPDATE link_metadata
            SET icon_relative_path = 'assets/link-icons/example.png',
                image_relative_path = 'assets/link-previews/example.png'
            WHERE item_id = ?1
            "#,
            params![result.item_id],
        )
        .unwrap();

    let active_maintenance = core.run_maintenance().unwrap();
    assert_eq!(active_maintenance.deleted_orphan_file_count, 0);
    assert!(icon_path.exists());
    assert!(image_path.exists());

    core.connection
        .execute(
            "UPDATE clipboard_items SET deleted_at_ms = ?1 WHERE id = ?2",
            params![now_ms(), result.item_id],
        )
        .unwrap();

    let deleted_maintenance = core.run_maintenance().unwrap();
    assert_eq!(deleted_maintenance.purged_item_count, 1);
    assert_eq!(deleted_maintenance.deleted_asset_file_count, 2);
    assert!(!icon_path.exists());
    assert!(!image_path.exists());
}

#[test]
fn fts_external_content_table_exists() {
    let (_, core) = open_temp_core();

    let table_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE name = 'clipboard_items_fts'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(table_count, 1);
}

#[test]
fn fresh_database_creates_simple_tokenizer_fts() {
    let (_, core) = open_temp_core();

    let table_sql: String = core
        .connection
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_items_fts'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let simple_query: String = core
        .connection
        .query_row("SELECT simple_query('国')", [], |row| row.get(0))
        .unwrap();

    assert!(table_sql.contains("tokenize = 'simple disable_stopword'"));
    assert_eq!(simple_query, "(g+u+o* OR gu+o* OR guo*)");
}

#[test]
fn raw_migration_helper_registers_simple_tokenizer() {
    let temp_dir = TempDir::new().expect("temp dir");
    let db_path = temp_dir.path().join(DATABASE_FILE_NAME);
    let mut connection = Connection::open(&db_path).expect("open db");

    apply_migrations_through(&mut connection, CURRENT_SCHEMA_VERSION);

    let simple_query: String = connection
        .query_row("SELECT simple_query('星')", [], |row| row.get(0))
        .unwrap();
    let table_sql: String = connection
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_items_fts'",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert!(simple_query.contains("xing"));
    assert!(table_sql.contains("tokenize = 'simple disable_stopword'"));
}

#[test]
fn v13_migration_rebuilds_fts_with_existing_rows_searchable() {
    let temp_dir = TempDir::new().expect("temp dir");
    let db_path = temp_dir.path().join(DATABASE_FILE_NAME);
    let mut connection = Connection::open(&db_path).expect("open v12 db");
    apply_migrations_through(&mut connection, 12);
    let now = now_ms();
    connection
        .execute(
            r#"
            INSERT INTO clipboard_items (
                id,
                type,
                summary,
                primary_text,
                content_hash,
                source_confidence,
                first_copied_at_ms,
                last_copied_at_ms,
                created_at_ms,
                updated_at_ms
            )
            VALUES (
                'legacy-simple-tokenizer-item',
                'text',
                '旧数据 星海计划',
                '旧数据 星海计划',
                'legacy-simple-tokenizer-hash',
                'high',
                ?1,
                ?1,
                ?1,
                ?1
            )
            "#,
            params![now],
        )
        .unwrap();
    drop(connection);

    let core = ClipboardCore::open(temp_dir.path()).expect("migrate v13 db");
    let row_schema_version: i64 = core
        .connection
        .query_row("SELECT MAX(version) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .unwrap();
    let table_sql: String = core
        .connection
        .query_row(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'clipboard_items_fts'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let pinyin_page = core
        .list_items(
            ItemQuery {
                search_text: Some("xing hai".to_string()),
                ..ItemQuery::default()
            },
            PageRequest::default(),
        )
        .unwrap();

    assert_eq!(row_schema_version, CURRENT_SCHEMA_VERSION);
    assert!(table_sql.contains("tokenize = 'simple disable_stopword'"));
    assert_eq!(pinyin_page.total_count, 1);
    assert_eq!(pinyin_page.items[0].id, "legacy-simple-tokenizer-item");
}

#[test]
fn migration_checksum_mismatch_is_reported() {
    let (temp_dir, core) = open_temp_core();
    core.connection
        .execute(
            "UPDATE schema_migrations SET checksum = 'changed' WHERE version = 1",
            [],
        )
        .unwrap();
    drop(core);

    let error = match ClipboardCore::open(temp_dir.path()) {
        Ok(_) => panic!("expected checksum mismatch"),
        Err(error) => error,
    };
    assert_eq!(error.code, CoreErrorCode::MigrationChecksumMismatch);
}

#[test]
fn v7_migration_maps_disabled_link_metadata_states() {
    let temp_dir = seed_v6_database_with_disabled_link_metadata();
    let mut core = ClipboardCore::open(temp_dir.path()).expect("migrate core");

    let rows = core
        .connection
        .prepare(
            r#"
            SELECT item_id, metadata_state, failure_code, fetched_at_ms, next_retry_at_ms, title
            FROM link_metadata
            ORDER BY item_id
            "#,
        )
        .unwrap()
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, Option<i64>>(3)?,
                row.get::<_, Option<i64>>(4)?,
                row.get::<_, Option<String>>(5)?,
            ))
        })
        .unwrap()
        .collect::<rusqlite::Result<Vec<_>>>()
        .unwrap();

    assert_eq!(rows.len(), 3);
    assert_eq!(
        rows[0],
        (
            "item_pending".to_string(),
            "pending".to_string(),
            None,
            None,
            None,
            Some("Pending Cache".to_string())
        )
    );
    assert_eq!(
        rows[1],
        (
            "item_privacy".to_string(),
            "failed".to_string(),
            Some("privacy_sensitive".to_string()),
            None,
            None,
            Some("Privacy Cache".to_string())
        )
    );
    assert_eq!(
        rows[2],
        (
            "item_ready".to_string(),
            "ready".to_string(),
            None,
            Some(4_000),
            None,
            Some("Ready Cache".to_string())
        )
    );

    assert!(core
        .claim_link_metadata_fetch_batch(10, 60_000)
        .unwrap()
        .iter()
        .all(|candidate| candidate.item_id != "item_privacy"));
}

#[test]
fn v7_link_metadata_schema_rejects_disabled_and_keeps_indexes() {
    let temp_dir = seed_v6_database_with_disabled_link_metadata();
    let core = ClipboardCore::open(temp_dir.path()).expect("migrate core");
    let now = now_ms();

    core.connection
        .execute(
            r#"
            INSERT INTO clipboard_items (
                id,
                type,
                summary,
                primary_text,
                content_hash,
                source_confidence,
                first_copied_at_ms,
                last_copied_at_ms,
                created_at_ms,
                updated_at_ms
            )
            VALUES (
                'new_disabled',
                'link',
                'https://example.com/disabled',
                'https://example.com/disabled',
                'hash-new-disabled',
                'high',
                ?1,
                ?1,
                ?1,
                ?1
            )
            "#,
            params![now],
        )
        .unwrap();

    let disabled_insert = core.connection.execute(
        r#"
        INSERT INTO link_metadata (
            item_id,
            original_text,
            canonical_url,
            display_url,
            host,
            metadata_state,
            created_at_ms,
            updated_at_ms
        )
        VALUES (
            'new_disabled',
            'https://example.com/disabled',
            'https://example.com/disabled',
            'example.com/disabled',
            'example.com',
            'disabled',
            1,
            1
        )
        "#,
        [],
    );
    assert!(disabled_insert.is_err());

    let index_count: i64 = core
        .connection
        .query_row(
            r#"
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'index'
                AND name IN ('ix_link_metadata_state_retry', 'ix_link_metadata_canonical_url')
            "#,
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(index_count, 2);
}

#[test]
fn v8_migration_adds_nullable_source_icon_header_color_columns() {
    let temp_dir = TempDir::new().expect("temp dir");
    let db_path = temp_dir.path().join(DATABASE_FILE_NAME);
    let mut connection = Connection::open(&db_path).expect("open v7 db");
    apply_migrations_through(&mut connection, 7);

    let before_count: i64 = connection
        .query_row(
            r#"
            SELECT COUNT(*)
            FROM pragma_table_info('source_app_icons')
            WHERE name IN (
                'header_color_argb',
                'header_color_cache_version',
                'header_color_updated_at_ms'
            )
            "#,
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(before_count, 0);
    drop(connection);

    let core = ClipboardCore::open(temp_dir.path()).expect("migrate v8 db");
    let columns = core
        .connection
        .prepare(
            r#"
            SELECT name, type, "notnull"
            FROM pragma_table_info('source_app_icons')
            WHERE name IN (
                'header_color_argb',
                'header_color_cache_version',
                'header_color_updated_at_ms'
            )
            ORDER BY name
            "#,
        )
        .unwrap()
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
            ))
        })
        .unwrap()
        .collect::<rusqlite::Result<Vec<_>>>()
        .unwrap();

    assert_eq!(
        columns,
        vec![
            ("header_color_argb".to_string(), "INTEGER".to_string(), 0),
            (
                "header_color_cache_version".to_string(),
                "INTEGER".to_string(),
                0
            ),
            (
                "header_color_updated_at_ms".to_string(),
                "INTEGER".to_string(),
                0
            ),
        ]
    );
}

#[test]
fn v9_migration_adds_payload_state_and_pending_image_jobs() {
    let temp_dir = TempDir::new().expect("temp dir");
    let db_path = temp_dir.path().join(DATABASE_FILE_NAME);
    let mut connection = Connection::open(&db_path).expect("open v8 db");
    apply_migrations_through(&mut connection, 8);
    drop(connection);

    let core = ClipboardCore::open(temp_dir.path()).expect("migrate v9 db");
    let payload_state_column: (String, i64, String) = core
        .connection
        .query_row(
            r#"
            SELECT type, "notnull", dflt_value
            FROM pragma_table_info('clipboard_items')
            WHERE name = 'payload_state'
            "#,
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    let pending_table_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'pending_image_jobs'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    let index_count: i64 = core
        .connection
        .query_row(
            r#"
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type = 'index'
                AND name IN (
                    'ix_pending_image_jobs_state_lease',
                    'ix_pending_image_jobs_cleanup',
                    'ix_pending_image_jobs_requested_item',
                    'ux_pending_image_jobs_active_reserved_payload',
                    'ux_pending_image_jobs_active_staged_payload',
                    'ux_pending_image_jobs_active_item'
                )
            "#,
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(
        payload_state_column,
        ("TEXT".to_string(), 1, "'ready'".to_string())
    );
    assert_eq!(pending_table_count, 1);
    assert_eq!(index_count, 6);
}

fn seed_v6_database_with_disabled_link_metadata() -> TempDir {
    let temp_dir = TempDir::new().expect("temp dir");
    let db_path = temp_dir.path().join(DATABASE_FILE_NAME);
    let mut connection = Connection::open(&db_path).expect("open v6 db");
    apply_migrations_through(&mut connection, 6);

    insert_v6_disabled_link_metadata(
        &connection,
        "item_ready",
        None,
        Some(4_000),
        Some(9_000),
        "Ready Cache",
    );
    insert_v6_disabled_link_metadata(
        &connection,
        "item_privacy",
        Some("privacy_sensitive"),
        None,
        Some(9_000),
        "Privacy Cache",
    );
    insert_v6_disabled_link_metadata(
        &connection,
        "item_pending",
        Some("provider_error"),
        None,
        Some(9_000),
        "Pending Cache",
    );

    drop(connection);
    temp_dir
}

fn apply_migrations_through(connection: &mut Connection, max_version: i64) {
    crate::register_simple_tokenizer(connection).unwrap();
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
        .unwrap();

    for migration in MIGRATIONS
        .iter()
        .filter(|migration| migration.version <= max_version)
    {
        connection.execute_batch(migration.sql).unwrap();
        connection
            .execute(
                "INSERT INTO schema_migrations (version, name, checksum, applied_at_ms) VALUES (?1, ?2, ?3, ?4)",
                params![
                    migration.version,
                    migration.name,
                    test_checksum(migration.sql),
                    now_ms()
                ],
            )
            .unwrap();
    }
}

fn insert_v6_disabled_link_metadata(
    connection: &Connection,
    item_id: &str,
    failure_code: Option<&str>,
    fetched_at_ms: Option<i64>,
    next_retry_at_ms: Option<i64>,
    title: &str,
) {
    let now = now_ms();
    connection
        .execute(
            r#"
            INSERT INTO clipboard_items (
                id,
                type,
                summary,
                primary_text,
                content_hash,
                source_confidence,
                first_copied_at_ms,
                last_copied_at_ms,
                created_at_ms,
                updated_at_ms
            )
            VALUES (?1, 'link', ?2, ?2, ?3, 'high', ?4, ?4, ?4, ?4)
            "#,
            params![
                item_id,
                format!("https://example.com/{item_id}"),
                format!("hash-{item_id}"),
                now
            ],
        )
        .unwrap();

    connection
        .execute(
            r#"
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
            VALUES (
                ?1,
                ?2,
                ?2,
                ?3,
                'example.com',
                ?4,
                'Example',
                'assets/link-icons/example.png',
                'assets/link-previews/example.jpg',
                'disabled',
                ?5,
                2,
                3000,
                ?6,
                ?7,
                ?8,
                ?8
            )
            "#,
            params![
                item_id,
                format!("https://example.com/{item_id}"),
                format!("example.com/{item_id}"),
                title,
                failure_code,
                fetched_at_ms,
                next_retry_at_ms,
                now
            ],
        )
        .unwrap();
}

fn test_checksum(sql: &str) -> String {
    let digest = Sha256::digest(sql.as_bytes());
    digest
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<String>()
}
