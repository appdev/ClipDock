use super::*;

#[test]
fn backup_restores_image_bytes_and_external_file_references() {
    let (source_root, mut source) = open_temp_core();
    write_test_webp(
        source_root.path(),
        "assets/original.webp",
        b"synthetic original",
    );
    write_test_webp(
        source_root.path(),
        "thumbnails/preview.webp",
        b"synthetic preview",
    );
    let image = source
        .capture_image(CaptureImageRequest {
            payload_relative_path: "assets/original.webp".into(),
            preview_relative_path: Some("thumbnails/preview.webp".into()),
            mime_type: Some("image/webp".into()),
            width: 20,
            height: 20,
            byte_count: 0,
            source_bundle_id: None,
            source_app_name: None,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 1,
            self_write_token: None,
        })
        .unwrap();
    let file = source
        .capture_files(CaptureFilesRequest {
            file_paths: vec!["/synthetic/original.txt".into()],
            file_items: vec![],
            preview_relative_path: None,
            preview_mime_type: None,
            preview_width: None,
            preview_height: None,
            preview_byte_count: 0,
            snapshot_relative_path: None,
            snapshot_byte_count: 0,
            source_bundle_id: None,
            source_app_name: None,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 2,
            self_write_token: None,
        })
        .unwrap();
    let outside = TempDir::new().unwrap();
    let archive = outside.path().join("image.clipdock");
    source.export_backup(&archive).unwrap();
    let (target_root, mut target) = open_temp_core();
    assert_eq!(target.import_backup(&archive).unwrap().imported_count, 2);
    let restored = target.get_item(&image.item_id).unwrap().unwrap();
    assert_eq!(
        fs::read(restored.payload_asset_path.unwrap()).unwrap(),
        test_webp_bytes(b"synthetic original")
    );
    assert_eq!(
        fs::read(restored.preview_asset_path.unwrap()).unwrap(),
        test_webp_bytes(b"synthetic preview")
    );
    assert_eq!(
        target.get_item(&file.item_id).unwrap().unwrap().file_items[0].path,
        "/synthetic/original.txt"
    );
    assert_eq!(
        fs::read_dir(target_root.path().join(".staging"))
            .unwrap()
            .count(),
        0
    );
    let malformed = Connection::open(&archive).unwrap();
    malformed
        .execute(
            "DELETE FROM backup_rows WHERE table_name = 'clipboard_assets'",
            [],
        )
        .unwrap();
    malformed.execute("DELETE FROM backup_assets", []).unwrap();
    assert!(
        target.import_backup(&archive).is_err(),
        "ready images require their payload even when deduplicated"
    );
}

#[test]
fn backup_open_does_not_prune_existing_history_when_import_is_invalid() {
    let (root, mut core) = open_temp_core();
    core.capture_text(text_capture_request(
        "Keep expired history until normal maintenance",
        1,
    ))
    .unwrap();
    core.connection
        .execute("UPDATE clipboard_items SET last_copied_at_ms = 0", [])
        .unwrap();
    drop(core);
    let mut core = ClipboardCore::open_for_backup(root.path()).unwrap();
    assert!(core
        .import_backup(root.path().join("nonexistent.clipdock"))
        .is_err());
    assert_eq!(core.info().unwrap().item_count, 1);
}

#[test]
fn backup_roundtrip_merges_records_titles_assets_and_pinboards_idempotently() {
    let (source_dir, mut source) = open_temp_core();
    let archive_dir = TempDir::new().unwrap();
    let archive = archive_dir.path().join("history.clipdock");
    let text = source
        .capture_text(text_capture_request("备份内容", 1))
        .unwrap();
    source.rename_item(&text.item_id, "备份标题").unwrap();
    let board = source.create_pinboard("工作", None).unwrap();
    source
        .set_item_pinboard_membership(&text.item_id, &board.id, true)
        .unwrap();
    write_test_rtf(
        source_dir.path(),
        "assets/rich-text/example.rtf",
        b"{\\rtf1 Synthetic backup}",
    );
    let rich = source
        .capture_rich_text(CaptureRichTextRequest {
            text: "Rich backup".into(),
            rtf_relative_path: "assets/rich-text/example.rtf".into(),
            mime_type: Some("text/rtf".into()),
            byte_count: 0,
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
    assert_eq!(source.export_backup(&archive).unwrap().exported_count, 2);
    let (target_dir, mut target) = open_temp_core();
    let existing = target
        .capture_text(text_capture_request("Existing record", 1))
        .unwrap();
    let prefs = target.get_preferences().unwrap();
    let result = target.import_backup(&archive).unwrap();
    assert_eq!((result.imported_count, result.skipped_count), (2, 0));
    assert!(target.get_item(&existing.item_id).unwrap().is_some());
    let restored = target.get_item(&text.item_id).unwrap().unwrap();
    assert_eq!(restored.custom_title.as_deref(), Some("备份标题"));
    assert_eq!(
        target
            .list_items(
                ItemQuery {
                    pinboard_id: Some(board.id),
                    ..Default::default()
                },
                PageRequest::default()
            )
            .unwrap()
            .total_count,
        1
    );
    let restored_rich = target.get_item(&rich.item_id).unwrap().unwrap();
    assert_eq!(
        fs::read(restored_rich.payload_asset_path.unwrap()).unwrap(),
        b"{\\rtf1 Synthetic backup}"
    );
    assert_eq!(target.get_preferences().unwrap(), prefs);
    assert_eq!(
        target
            .list_items(
                ItemQuery {
                    search_text: Some("备份标题".into()),
                    ..Default::default()
                },
                PageRequest::default()
            )
            .unwrap()
            .total_count,
        1
    );
    target.rename_item(&text.item_id, "本地改名").unwrap();
    let repeated = target.import_backup(&archive).unwrap();
    assert_eq!((repeated.imported_count, repeated.skipped_count), (0, 2));
    assert_eq!(
        target
            .get_item(&text.item_id)
            .unwrap()
            .unwrap()
            .custom_title
            .as_deref(),
        Some("本地改名")
    );
    drop(target);
    let target = ClipboardCore::open(target_dir.path()).unwrap();
    assert_eq!(target.info().unwrap().item_count, 3);
}

#[test]
fn backup_invalid_input_preserves_existing_history() {
    let (root, mut core) = open_temp_core();
    let item = core
        .capture_text(text_capture_request("Keep me", 1))
        .unwrap();
    let invalid = root.path().join("invalid.clipdock");
    fs::write(&invalid, b"not a backup").unwrap();
    assert!(core.import_backup(&invalid).is_err());
    assert_eq!(
        core.get_item(&item.item_id)
            .unwrap()
            .unwrap()
            .primary_text
            .as_deref(),
        Some("Keep me")
    );
    assert!(core
        .export_backup(core.database_path().to_path_buf())
        .is_err());
    assert_eq!(core.info().unwrap().item_count, 1);
}

#[test]
fn backup_corrupt_assets_and_paths_roll_back_without_leaving_files() {
    let (root, mut source) = open_temp_core();
    write_test_rtf(root.path(), "assets/rich-text/a.rtf", b"{\\rtf1 Backup}");
    source
        .capture_rich_text(CaptureRichTextRequest {
            text: "A".into(),
            rtf_relative_path: "assets/rich-text/a.rtf".into(),
            mime_type: None,
            byte_count: 0,
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
    let outside = TempDir::new().unwrap();
    let file = outside.path().join("backup.clipdock");
    source.export_backup(&file).unwrap();
    let (target_root, mut target) = open_temp_core();
    let existing = target
        .capture_text(text_capture_request("Keep", 1))
        .unwrap();
    let archive = Connection::open(&file).unwrap();
    archive
        .execute("UPDATE backup_assets SET hash = 'corrupt'", [])
        .unwrap();
    assert!(target.import_backup(&file).is_err());
    assert_eq!(target.info().unwrap().item_count, 1);
    assert!(target.get_item(&existing.item_id).unwrap().is_some());
    assert_eq!(
        fs::read_dir(target_root.path().join("assets"))
            .unwrap()
            .count(),
        0
    );
    archive.execute("UPDATE backup_rows SET data_json = json_set(data_json, '$.relative_path', 'assets/../../outside') WHERE table_name = 'clipboard_assets'", []).unwrap();
    assert!(target.import_backup(&file).is_err());
    assert_eq!(target.info().unwrap().item_count, 1);
    assert!(!outside.path().join("outside").exists());
    archive
        .execute(
            "DELETE FROM backup_rows WHERE table_name = 'clipboard_assets'",
            [],
        )
        .unwrap();
    archive.execute("DELETE FROM backup_assets", []).unwrap();
    assert!(
        target.import_backup(&file).is_err(),
        "ready rich text requires its original RTF"
    );
    assert_eq!(target.info().unwrap().item_count, 1);
    assert_eq!(
        fs::read_dir(target_root.path().join(".staging"))
            .unwrap()
            .count(),
        0
    );
}

#[test]
fn backup_rejects_unsupported_versions_and_invalid_relations() {
    let (_root, mut source) = open_temp_core();
    let item = source
        .capture_text(text_capture_request("Record", 1))
        .unwrap();
    source
        .set_item_pinboard_membership(&item.item_id, "default", true)
        .unwrap();
    let outside = TempDir::new().unwrap();
    let file = outside.path().join("backup.clipdock");
    source.export_backup(&file).unwrap();
    let (_target_root, mut target) = open_temp_core();
    let archive = Connection::open(&file).unwrap();
    archive
        .execute("UPDATE backup_info SET format_version = 999", [])
        .unwrap();
    assert!(target.import_backup(&file).is_err());
    archive
        .execute("UPDATE backup_info SET format_version = 1", [])
        .unwrap();
    archive.execute("UPDATE backup_rows SET data_json = json_set(data_json, '$.item_id', 'missing') WHERE table_name = 'pinboard_items'", []).unwrap();
    assert!(target.import_backup(&file).is_err());
    assert_eq!(target.info().unwrap().item_count, 0);
}

#[test]
fn backup_failed_export_preserves_previous_backup_and_skips_deleted_data() {
    let (root, mut source) = open_temp_core();
    let deleted = source
        .capture_text(text_capture_request("Deleted", 1))
        .unwrap();
    source.delete_item(&deleted.item_id).unwrap();
    let outside = TempDir::new().unwrap();
    let file = outside.path().join("backup.clipdock");
    assert_eq!(source.export_backup(&file).unwrap().exported_count, 0);
    let original = fs::read(&file).unwrap();
    write_test_webp(root.path(), "thumbnails/pending.webp", b"synthetic");
    source
        .capture_pending_image(pending_image_request(
            "session",
            "thumbnails/pending.webp",
            "assets/pending.webp",
            ".staging/pending.webp",
            20,
            20,
            test_webp_byte_count(b"synthetic"),
        ))
        .unwrap();
    assert!(source.export_backup(&file).is_err());
    assert_eq!(fs::read(&file).unwrap(), original);
}

#[test]
fn backup_duplicate_content_with_different_id_merges_pinboard_membership() {
    let (_root, mut source) = open_temp_core();
    let item = source
        .capture_text(text_capture_request("Same content", 1))
        .unwrap();
    let board = source.create_pinboard("Imported pins", None).unwrap();
    source
        .set_item_pinboard_membership(&item.item_id, &board.id, true)
        .unwrap();
    let outside = TempDir::new().unwrap();
    let file = outside.path().join("backup.clipdock");
    source.export_backup(&file).unwrap();
    let archive = Connection::open(&file).unwrap();
    archive.execute("UPDATE backup_rows SET data_json = json_set(data_json, '$.id', 'different-id') WHERE table_name = 'clipboard_items'", []).unwrap();
    archive.execute("UPDATE backup_rows SET data_json = json_set(data_json, '$.item_id', 'different-id') WHERE table_name IN ('clipboard_formats', 'pinboard_items')", []).unwrap();
    let (_target_root, mut target) = open_temp_core();
    target
        .capture_text(text_capture_request("Same content", 1))
        .unwrap();
    let result = target.import_backup(&file).unwrap();
    assert_eq!((result.imported_count, result.skipped_count), (0, 1));
    let page = target
        .list_items(
            ItemQuery {
                pinboard_id: Some(board.id),
                ..Default::default()
            },
            PageRequest::default(),
        )
        .unwrap();
    assert_eq!(page.total_count, 1);
    assert_eq!(page.items[0].id, item.item_id);
}
