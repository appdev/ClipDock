//! Integration coverage for the storage round-trip that the Windows Tauri
//! commands rely on. These exercise `clipboard_core` exactly as the command
//! layer does (capture -> list), and verify the central "history survives a
//! restart" guarantee by reopening the database against the same directory.

use clipboard_core::{
    CaptureImageRequest, CaptureTextRequest, ClipboardCore, ClipboardItemType, ItemQuery,
    PageRequest, SourceConfidence,
};
use std::fs;

fn text_request(text: &str) -> CaptureTextRequest {
    CaptureTextRequest {
        text: text.to_string(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: None,
        source_app_name: None,
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::Unknown,
        pasteboard_change_count: 0,
        self_write_token: None,
    }
}

#[test]
fn lightweight_list_json_matches_the_frontend_contract_fixture() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(dir.path()).unwrap();
    let full_text = format!("{}tail outside preview", "a😀".repeat(260));
    core.capture_text(text_request(&full_text)).unwrap();
    let mut link = text_request("https://example.test/docs?q=1");
    link.detected_link = Some(clipboard_core::CaptureDetectedLink {
        original_text: link.text.clone(),
        canonical_url: link.text.clone(),
        display_url: "example.test/docs?q=1".into(),
        host: "example.test".into(),
        metadata_state: clipboard_core::LinkMetadataState::Pending,
    });
    core.capture_text(link).unwrap();
    let mut values: Vec<serde_json::Value> = core
        .list_entries_with_metrics(ItemQuery::default(), PageRequest::default(), false)
        .unwrap()
        .items
        .into_iter()
        .map(|entry| {
            let mut value = serde_json::to_value(entry).unwrap();
            value["id"] = format!("fixture_{}", value["item_type"].as_str().unwrap()).into();
            value["content_hash"] = "fixture_hash".into();
            value["first_copied_at_ms"] = 0.into();
            value["last_copied_at_ms"] = 0.into();
            value
        })
        .collect();
    values.sort_by_key(|value| value["item_type"].as_str().unwrap().to_string());
    let actual = serde_json::to_value(values).unwrap();
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../src/panel/fixtures/clipboard-list-entries.json");
    if std::env::var_os("CLIPDOCK_UPDATE_LIST_FIXTURE").is_some() {
        fs::write(
            &path,
            format!("{}\n", serde_json::to_string_pretty(&actual).unwrap()),
        )
        .unwrap();
    }
    let expected: serde_json::Value = serde_json::from_slice(&fs::read(path).unwrap()).unwrap();
    assert_eq!(actual, expected);
}

#[test]
fn capture_text_round_trips_through_list() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut core = ClipboardCore::open(dir.path()).expect("open core");

    core.capture_text(text_request("hello clipdock"))
        .expect("capture text");

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .expect("list items");

    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].item_type, ClipboardItemType::Text);
    assert_eq!(page.items[0].summary, "hello clipdock");
}

#[test]
fn recapturing_same_text_bumps_copy_count_without_duplicating() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut core = ClipboardCore::open(dir.path()).expect("open core");

    core.capture_text(text_request("repeated")).expect("first");
    core.capture_text(text_request("repeated")).expect("second");

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .expect("list items");

    assert_eq!(
        page.items.len(),
        1,
        "duplicate content must not create a row"
    );
    assert_eq!(page.items[0].copy_count, 2);
}

#[test]
fn history_survives_reopening_the_database() {
    let dir = tempfile::tempdir().expect("tempdir");

    {
        let mut core = ClipboardCore::open(dir.path()).expect("open core");
        core.capture_text(text_request("persisted entry"))
            .expect("capture text");
    }

    // Reopen against the same directory, mirroring an app restart.
    let core = ClipboardCore::open(dir.path()).expect("reopen core");
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .expect("list items");

    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].summary, "persisted entry");
}

#[test]
fn renamed_card_survives_restart_search_and_recapture_without_changing_payload() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(dir.path()).unwrap();
    let captured = core
        .capture_text(text_request("original clipboard payload"))
        .unwrap();
    let original = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .remove(0);
    assert_eq!(
        core.rename_item(&captured.item_id, "  工作资料  ")
            .unwrap()
            .affected_count,
        1
    );
    drop(core);
    let mut core = ClipboardCore::open(dir.path()).unwrap();
    let renamed = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .remove(0);
    assert_eq!(renamed.custom_title.as_deref(), Some("工作资料"));
    assert_eq!(renamed.primary_text, original.primary_text);
    assert_eq!(renamed.last_copied_at_ms, original.last_copied_at_ms);
    assert_eq!(renamed.copy_count, original.copy_count);
    for text in ["工作", "gongzuo", "ziliao"] {
        let query = ItemQuery {
            search_text: Some(text.into()),
            ..Default::default()
        };
        assert_eq!(
            core.list_items(query, PageRequest::default())
                .unwrap()
                .items
                .len(),
            1,
            "{text}"
        );
    }
    let repeated = core
        .capture_text(text_request("original clipboard payload"))
        .unwrap();
    assert_eq!(repeated.item_id, captured.item_id);
    assert_eq!(
        core.list_items(ItemQuery::default(), PageRequest::default())
            .unwrap()
            .items[0]
            .custom_title
            .as_deref(),
        Some("工作资料")
    );
    core.rename_item(&captured.item_id, "  ").unwrap();
    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap();
    assert_eq!(page.items[0].custom_title, None);
    let query = ItemQuery {
        search_text: Some("gongzuo".into()),
        ..Default::default()
    };
    assert!(core
        .list_items(query, PageRequest::default())
        .unwrap()
        .items
        .is_empty());
    assert_eq!(
        core.rename_item("missing-item", "name")
            .unwrap()
            .affected_count,
        0
    );
}

#[test]
fn capture_image_records_payload_relative_to_root() {
    let dir = tempfile::tempdir().expect("tempdir");
    let mut core = ClipboardCore::open(dir.path()).expect("open core");

    // `ClipboardCore::open` provisions an `assets/` directory under the root;
    // the Windows capture path writes the PNG there before recording it.
    let relative_path = "assets/clipboard-image-test.png";
    let payload_path = dir.path().join(relative_path);
    fs::write(&payload_path, b"fake-png-bytes").expect("write payload");

    let request = CaptureImageRequest {
        payload_relative_path: relative_path.to_string(),
        preview_relative_path: None,
        mime_type: Some("image/png".to_string()),
        width: 320,
        height: 200,
        byte_count: 0,
        source_bundle_id: None,
        source_app_name: None,
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::Unknown,
        pasteboard_change_count: 0,
        self_write_token: None,
    };

    core.capture_image(request).expect("capture image");

    let page = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .expect("list items");

    assert_eq!(page.items.len(), 1);
    assert_eq!(page.items[0].item_type, ClipboardItemType::Image);
}

#[test]
fn authoritative_id_membership_copy_and_delete_survive_restart() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(dir.path()).unwrap();
    let captured = core
        .capture_text(text_request("Windows durable item"))
        .unwrap();
    let other = core.create_pinboard("Work", None).unwrap();
    assert!(captured.item_id.starts_with("item_"));
    assert_eq!(
        core.set_item_pinboard_membership(captured.item_id.clone(), "default", true)
            .unwrap()
            .affected_count,
        1
    );
    core.set_item_pinboard_membership(captured.item_id.clone(), other.id.clone(), true)
        .unwrap();
    assert_eq!(
        core.record_item_copied(captured.item_id.clone())
            .unwrap()
            .affected_count,
        1
    );
    assert_eq!(core.delete_item("item_missing").unwrap().affected_count, 0);
    assert_eq!(
        core.delete_item(captured.item_id.clone())
            .unwrap()
            .affected_count,
        1
    );
    drop(core);

    let mut core = ClipboardCore::open(dir.path()).unwrap();
    assert!(core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .is_empty());
    let query = |board: String| ItemQuery {
        pinboard_id: Some(board),
        ..Default::default()
    };
    let pinned = core
        .list_items(query("default".into()), PageRequest::default())
        .unwrap();
    assert_eq!(pinned.items[0].id, captured.item_id);
    assert_eq!(pinned.items[0].copy_count, 2);
    assert!(pinned.items[0].pinboard_ids.contains(&other.id));
    core.set_item_pinboard_membership(captured.item_id.clone(), "default", false)
        .unwrap();
    assert!(core
        .list_items(query("default".into()), PageRequest::default())
        .unwrap()
        .items
        .is_empty());
    assert_eq!(
        core.list_items(query(other.id), PageRequest::default())
            .unwrap()
            .items[0]
            .id,
        captured.item_id
    );
}

#[test]
fn legacy_image_thumbnail_registration_keeps_authoritative_id_and_copy_count() {
    let dir = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(dir.path()).unwrap();
    let payload = image::RgbaImage::from_pixel(840, 420, image::Rgba([10, 20, 30, 128]));
    payload.save(dir.path().join("assets/full.png")).unwrap();
    let request = CaptureImageRequest {
        payload_relative_path: "assets/full.png".into(),
        preview_relative_path: None,
        mime_type: Some("image/png".into()),
        width: 840,
        height: 420,
        byte_count: 0,
        source_bundle_id: None,
        source_app_name: None,
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::Unknown,
        pasteboard_change_count: 0,
        self_write_token: None,
    };
    let captured = core.capture_image(request).unwrap();
    let before = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .remove(0);
    assert!(core
        .image_thumbnail_path(&captured.item_id)
        .unwrap()
        .is_none());
    let small = image::imageops::thumbnail(&payload, 420, 420);
    small.save(dir.path().join("thumbnails/small.png")).unwrap();
    assert_eq!(
        core.set_item_thumbnail(
            &captured.item_id,
            "thumbnails/small.png",
            "image/png",
            420,
            210
        )
        .unwrap()
        .affected_count,
        1
    );
    drop(core);
    let core = ClipboardCore::open(dir.path()).unwrap();
    let after = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .remove(0);
    assert_eq!(after.id, before.id);
    assert_eq!(after.copy_count, before.copy_count);
    assert_eq!(after.last_copied_at_ms, before.last_copied_at_ms);
    assert_ne!(
        core.image_thumbnail_path(&captured.item_id).unwrap(),
        core.image_payload_path(&captured.item_id).unwrap()
    );
    assert_eq!(
        after.preview_asset_path.as_deref(),
        Some(dir.path().join("thumbnails/small.png").to_str().unwrap())
    );
}
