use super::*;
use crate::error::CoreErrorCode;
use crate::time::now_ms;
use crate::{
    CaptureFilesRequest, CaptureImageRequest, CaptureTextRequest, ClipboardItemType, ItemQuery,
    PageRequest, SourceConfidence, CURRENT_SCHEMA_VERSION, DATABASE_FILE_NAME,
};
use rusqlite::params;
use std::fs;
use tempfile::TempDir;

fn open_temp_core() -> (TempDir, ClipboardCore) {
    let temp_dir = TempDir::new().expect("temp dir");
    let core = ClipboardCore::open(temp_dir.path()).expect("open core");
    (temp_dir, core)
}

#[test]
fn open_creates_database_schema_and_asset_directories() {
    let (temp_dir, core) = open_temp_core();

    assert!(temp_dir.path().join(DATABASE_FILE_NAME).exists());
    assert!(temp_dir.path().join("assets").is_dir());
    assert!(temp_dir.path().join("thumbnails").is_dir());
    assert!(temp_dir.path().join("app-icons").is_dir());
    assert!(temp_dir.path().join("staging").is_dir());
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
fn capture_text_deduplicates_by_content_hash() {
    let (_, mut core) = open_temp_core();

    let request = CaptureTextRequest {
        text: "https://example.com".to_string(),
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
fn list_items_filters_by_type_and_search_text() {
    let (temp_dir, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Alpha search target from Safari".to_string(),
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
fn list_source_apps_and_filter_items_by_source_app_id() {
    let (temp_dir, mut core) = open_temp_core();
    core.capture_text(CaptureTextRequest {
        text: "Source filter text from Safari".to_string(),
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
fn item_management_pins_and_soft_deletes_single_item() {
    let (_, mut core) = open_temp_core();
    let pinned = core
        .capture_text(CaptureTextRequest {
            text: "Pinned management sample".to_string(),
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
    let soft_deleted_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items WHERE id = ?1 AND deleted_at_ms IS NOT NULL",
            params![pinned.item_id],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(delete_result.affected_count, 1);
    assert_eq!(page_after_delete.total_count, 1);
    assert_eq!(soft_deleted_count, 1);
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
fn clear_items_soft_deletes_matching_unpinned_items_only() {
    let (_, mut core) = open_temp_core();
    let pinned = core
        .capture_text(CaptureTextRequest {
            text: "Clear scope pinned text".to_string(),
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
    assert_eq!(preferences.history.max_items, 500);
    assert_eq!(preferences.appearance.mode, "system");
    assert_eq!(preferences.shortcuts.open_panel.key_code, 9);
    assert_eq!(
        preferences.shortcuts.open_panel.modifiers,
        vec!["command".to_string(), "shift".to_string()]
    );
    assert!(preferences.ignore_list.ignored_app_identifiers.is_empty());
    assert!(preferences.ignore_list.window_title_keywords.is_empty());
    assert!(!preferences.ignore_list.skip_unknown_source);
}

#[test]
fn preferences_update_persists_normalized_document() {
    let (_, mut core) = open_temp_core();
    let mut preferences = core.get_preferences().unwrap();
    preferences.general.default_panel_height = 999;
    preferences.history.max_items = 10;
    preferences.history.retention_days = 999;
    preferences.history.record_images = false;
    preferences.history.record_files = true;
    preferences.appearance.mode = "neon".to_string();
    preferences.appearance.item_density = "compact".to_string();
    preferences.shortcuts.open_panel.key_code = 11;
    preferences.shortcuts.open_panel.modifiers = vec![
        "shift".to_string(),
        "cmd".to_string(),
        "alt".to_string(),
        "command".to_string(),
        "ignored".to_string(),
    ];
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

    assert_eq!(saved.general.default_panel_height, 560);
    assert_eq!(saved.history.max_items, 50);
    assert_eq!(saved.history.retention_days, 365);
    assert!(!saved.history.record_images);
    assert!(saved.history.record_files);
    assert_eq!(saved.appearance.mode, "system");
    assert_eq!(saved.appearance.item_density, "compact");
    assert_eq!(saved.shortcuts.open_panel.key_code, 11);
    assert_eq!(
        saved.shortcuts.open_panel.modifiers,
        vec![
            "command".to_string(),
            "option".to_string(),
            "shift".to_string()
        ]
    );
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
    preferences.shortcuts.open_panel.key_code = 999;
    preferences.shortcuts.open_panel.modifiers = vec!["shift".to_string()];

    let saved = core.update_preferences(preferences).unwrap();

    assert_eq!(saved.shortcuts.open_panel.key_code, 9);
    assert_eq!(
        saved.shortcuts.open_panel.modifiers,
        vec!["command".to_string(), "shift".to_string()]
    );
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

    assert!(preferences.ignore_list.ignored_app_identifiers.is_empty());
    assert!(preferences.ignore_list.window_title_keywords.is_empty());
    assert!(!preferences.ignore_list.skip_unknown_source);
}

#[test]
fn preferences_update_prunes_history_to_max_items() {
    let (_, mut core) = open_temp_core();
    for index in 0..55 {
        core.capture_text(CaptureTextRequest {
            text: format!("Max item pruning sample {index:02}"),
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
    core.update_preferences(preferences).unwrap();

    let active_page = core
        .list_items(
            ItemQuery::default(),
            PageRequest {
                limit: 200,
                offset: 0,
            },
        )
        .unwrap();
    let deleted_count: i64 = core
        .connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items WHERE deleted_at_ms IS NOT NULL",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(active_page.total_count, 50);
    assert_eq!(active_page.items.len(), 50);
    assert_eq!(deleted_count, 5);
    assert!(active_page
        .items
        .iter()
        .any(|item| item.summary == "Max item pruning sample 54"));
    assert!(!active_page
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
    let deleted_summary: String = core
        .connection
        .query_row(
            "SELECT summary FROM clipboard_items WHERE deleted_at_ms IS NOT NULL",
            [],
            |row| row.get(0),
        )
        .unwrap();

    assert_eq!(active_page.total_count, 1);
    assert_eq!(active_page.items[0].summary, "Fresh retention sample");
    assert_eq!(deleted_summary, "Old retention sample");
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
    assert_eq!(maintenance.deleted_orphan_file_count, 5);
    assert!(payload_path.exists());
    assert!(thumbnail_path.exists());
    assert!(icon_path.exists());
    assert!(!orphan_asset.exists());
    assert!(!orphan_thumbnail.exists());
    assert!(!orphan_icon.exists());
    assert!(!orphan_snapshot.exists());
    assert!(!staging_file.exists());

    let active_page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(active_page.total_count, 1);
    assert_eq!(active_page.items[0].item_type, ClipboardItemType::Image);
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
