use super::*;
use crate::{
    CaptureImageRequest, CaptureTextRequest, PageRequest, PreferencesDocument, SourceConfidence,
};
use rusqlite::params;
use tempfile::TempDir;

fn request(text: &str, source: &str) -> CaptureTextRequest {
    CaptureTextRequest {
        text: text.into(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: None,
        source_app_name: Some(source.into()),
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::Unknown,
        pasteboard_change_count: 1,
        self_write_token: None,
    }
}

fn integrity(core: &ClipboardCore) {
    core.connection.execute(
        "INSERT INTO clipboard_items_fts(clipboard_items_fts, rank) VALUES('integrity-check', 1)", [],
    ).unwrap();
}

fn matches(core: &ClipboardCore, query: &str) -> i64 {
    core.connection
        .query_row(
            "SELECT COUNT(*) FROM clipboard_items_fts WHERE clipboard_items_fts MATCH ?1",
            [query],
            |row| row.get(0),
        )
        .unwrap()
}

#[test]
fn recapture_removes_old_source_tokens_and_purge_does_not_rebuild_unrelated_rows() {
    let directory = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(directory.path()).unwrap();
    let item = core
        .capture_text(request("kept text", "OldSource"))
        .unwrap();
    core.capture_text(request("kept text", "NewSource"))
        .unwrap();
    assert_eq!(matches(&core, "OldSource"), 0);
    assert_eq!(matches(&core, "NewSource"), 1);
    integrity(&core);

    // An unindexed fixture distinguishes incremental deletion from rebuilding all content.
    core.connection.execute("INSERT INTO clipboard_items (id,type,summary,primary_text,content_hash,first_copied_at_ms,last_copied_at_ms,created_at_ms,updated_at_ms) VALUES ('fixture','text','UnindexedToken','UnindexedToken','fixture',?1,?1,?1,?1)", [crate::time::now_ms()]).unwrap();
    core.delete_item(item.item_id).unwrap();
    assert_eq!(matches(&core, "NewSource"), 0);
    assert_eq!(matches(&core, "UnindexedToken"), 0);
    core.run_maintenance().unwrap();
    assert_eq!(matches(&core, "UnindexedToken"), 0);
}

#[test]
fn v17_repairs_legacy_tokens_and_rejects_future_schema() {
    let directory = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(directory.path()).unwrap();
    core.capture_text(request("legacy text", "OldSource"))
        .unwrap();
    core.connection
        .execute(
            "UPDATE clipboard_items SET source_app_name = 'NewSource'",
            [],
        )
        .unwrap();
    core.connection.execute("INSERT INTO clipboard_items_fts(rowid,summary,primary_text,source_app_name) SELECT rowid,summary,primary_text,source_app_name FROM clipboard_items", []).unwrap();
    core.connection
        .execute("DELETE FROM schema_migrations WHERE version = 17", [])
        .unwrap();
    drop(core);
    let core = ClipboardCore::open(directory.path()).unwrap();
    assert_eq!(matches(&core, "OldSource"), 0);
    assert_eq!(matches(&core, "NewSource"), 1);
    integrity(&core);
    core.connection.execute("INSERT INTO schema_migrations(version,name,checksum,applied_at_ms) VALUES (999,'future','future',0)", []).unwrap();
    drop(core);
    assert_eq!(
        ClipboardCore::open(directory.path()).err().unwrap().code,
        CoreErrorCode::MigrationFailed
    );
}

#[test]
fn search_candidate_page_preserves_total_and_pinboard_memberships() {
    let directory = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(directory.path()).unwrap();
    let first = core
        .capture_text(request("needle %_\\ exact", "Source"))
        .unwrap();
    core.capture_text(request("second needle", "Source"))
        .unwrap();
    core.set_item_pinboard_membership(&first.item_id, "default", true)
        .unwrap();
    let query = ItemQuery {
        search_text: Some("needle".into()),
        ..Default::default()
    };
    let page = core
        .list_items(
            query.clone(),
            PageRequest {
                limit: 1,
                offset: 0,
            },
        )
        .unwrap();
    assert_eq!(page.total_count, 2);
    assert_eq!(page.items.len(), 1);
    assert!(page.has_more);
    let beyond = core
        .list_items(
            query,
            PageRequest {
                limit: 1,
                offset: 500,
            },
        )
        .unwrap();
    assert_eq!(beyond.total_count, 2);
    assert!(beyond.items.is_empty());
    assert!(!beyond.has_more);
    let literal = core
        .list_items(
            ItemQuery {
                search_text: Some("%_\\".into()),
                ..Default::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(literal.total_count, 1);
    assert_eq!(literal.items[0].pinboard_ids, vec!["default"]);
    let additional = core.create_pinboard("Additional", None).unwrap();
    core.set_item_pinboard_membership(&first.item_id, &additional.id, true)
        .unwrap();
    let both = core
        .list_items(
            ItemQuery {
                pinboard_id: Some(additional.id.clone()),
                ..Default::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(
        both.items[0].pinboard_ids,
        vec!["default".to_string(), additional.id.clone()]
    );
    core.delete_pinboard(&additional.id).unwrap();
    core.delete_item(&first.item_id).unwrap();
    let pinboard = core
        .list_items(
            ItemQuery {
                pinboard_id: Some("default".into()),
                search_text: Some("needle".into()),
                ..Default::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(pinboard.total_count, 1);
    assert_eq!(pinboard.items[0].id, first.item_id);
    assert_eq!(pinboard.items[0].pinboard_ids, vec!["default"]);
    let absent = core
        .list_items(
            ItemQuery {
                search_text: Some("absenttoken".into()),
                ..Default::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(absent.total_count, 0);
    assert!(absent.items.is_empty());
}

#[test]
fn forever_retains_old_rows_but_enforces_maximum_and_old_json_defaults_false() {
    let directory = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(directory.path()).unwrap();
    let mut preferences = core.get_preferences().unwrap();
    preferences.history.retention_forever = true;
    core.update_preferences(preferences.clone()).unwrap();
    let old = core.capture_text(request("old pinned", "Source")).unwrap();
    core.set_item_pinboard_membership(&old.item_id, "default", true)
        .unwrap();
    core.connection
        .execute("UPDATE clipboard_items SET last_copied_at_ms = 1", [])
        .unwrap();
    let transaction = core.connection.transaction().unwrap();
    for index in 0..5001 {
        transaction.execute("INSERT INTO clipboard_items (id,type,summary,primary_text,content_hash,first_copied_at_ms,last_copied_at_ms,created_at_ms,updated_at_ms) VALUES (?1,'text','old','old',?1,1,?2,1,1)", params![format!("seed-{index}"), index + 1]).unwrap();
    }
    transaction
        .execute(
            "INSERT INTO clipboard_items_fts(clipboard_items_fts) VALUES('rebuild')",
            [],
        )
        .unwrap();
    transaction.commit().unwrap();
    assert_eq!(core.apply_current_history_preferences().unwrap(), 1);
    assert_eq!(core.info().unwrap().item_count, 5001);
    integrity(&core);
    preferences.history.retention_forever = false;
    core.update_preferences(preferences).unwrap();
    assert_eq!(core.info().unwrap().item_count, 1);
    integrity(&core);
    let mut json = serde_json::to_value(PreferencesDocument::default()).unwrap();
    json["history"]
        .as_object_mut()
        .unwrap()
        .remove("retention_forever");
    let decoded: PreferencesDocument = serde_json::from_value(json).unwrap();
    assert!(!decoded.history.retention_forever);
}

#[test]
fn thumbnails_are_registered_without_recapture_and_paths_are_confined() {
    let directory = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(directory.path()).unwrap();
    let png = b"\x89PNG\r\n\x1a\npayload";
    fs::write(directory.path().join("assets/image.png"), png).unwrap();
    let item = core
        .capture_image(CaptureImageRequest {
            payload_relative_path: "assets/image.png".into(),
            preview_relative_path: None,
            mime_type: Some("image/png".into()),
            width: 100,
            height: 100,
            byte_count: png.len() as i64,
            source_bundle_id: None,
            source_app_name: None,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    let before = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .remove(0);
    assert!(core.image_thumbnail_path(&item.item_id).unwrap().is_none());
    fs::write(
        directory.path().join("thumbnails/small.png"),
        b"\x89PNG\r\n\x1a\nthumb",
    )
    .unwrap();
    assert_eq!(
        core.set_item_thumbnail(&item.item_id, "thumbnails/small.png", "image/png", 20, 20)
            .unwrap()
            .affected_count,
        1
    );
    let after = core
        .list_items(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .remove(0);
    assert_eq!(after.copy_count, before.copy_count);
    assert_eq!(after.last_copied_at_ms, before.last_copied_at_ms);
    assert!(after
        .preview_asset_path
        .unwrap()
        .ends_with("thumbnails/small.png"));
    assert!(core
        .image_payload_path(&item.item_id)
        .unwrap()
        .unwrap()
        .ends_with("assets/image.png"));
    assert!(core
        .image_thumbnail_path(&item.item_id)
        .unwrap()
        .unwrap()
        .ends_with("thumbnails/small.png"));
    assert!(core
        .set_item_thumbnail(&item.item_id, "../outside.png", "image/png", 20, 20)
        .is_err());
    assert!(core
        .set_item_thumbnail(&item.item_id, "thumbnails/small.png", "image/webp", 20, 20)
        .is_err());
    #[cfg(unix)]
    {
        let outside = TempDir::new().unwrap();
        fs::write(outside.path().join("outside.png"), png).unwrap();
        std::os::unix::fs::symlink(
            outside.path().join("outside.png"),
            directory.path().join("thumbnails/escape.png"),
        )
        .unwrap();
        assert!(core
            .set_item_thumbnail(&item.item_id, "thumbnails/escape.png", "image/png", 20, 20)
            .is_err());
    }
    fs::remove_file(directory.path().join("thumbnails/small.png")).unwrap();
    assert!(core.image_thumbnail_path(&item.item_id).unwrap().is_none());
    core.delete_item(&item.item_id).unwrap();
    assert!(core.image_payload_path(&item.item_id).unwrap().is_none());
    assert!(core.image_thumbnail_path(&item.item_id).unwrap().is_none());
}
