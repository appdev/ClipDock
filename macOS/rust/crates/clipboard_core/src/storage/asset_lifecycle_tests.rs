#![cfg(unix)]
use super::ClipboardCore;
use crate::*;
use serde_json::json;
use std::sync::{Arc, Barrier};

fn image_request(path: &str) -> CaptureImageRequest {
    serde_json::from_value(json!({"payload_relative_path":path,"mime_type":"image/png",
        "width":2,"height":2,"byte_count":0,"source_confidence":"unknown","pasteboard_change_count":1})).unwrap()
}
fn webp(body: &[u8]) -> Vec<u8> {
    let mut bytes = b"RIFF\0\0\0\0WEBP".to_vec();
    bytes.extend(body);
    bytes
}
fn pending(
    core: &mut ClipboardCore,
    store: &AssetStore,
) -> (PendingImageCaptureResult, AssetReservation, Vec<u8>) {
    let thumb = store
        .stage_encoded("thumbnails/pending.webp", None, &webp(b"thumb"))
        .unwrap();
    store.publish(&thumb).unwrap();
    let payload = store
        .reserve("assets/pending.webp", Some(".staging/exact-pending.webp"))
        .unwrap();
    let result = core.capture_pending_image(serde_json::from_value(json!({
        "owner_session_id":"synthetic-owner", "thumbnail_relative_path":thumb.relative_path,
        "reserved_payload_relative_path":payload.relative_path,"staged_payload_relative_path":payload.staged_relative_path,
        "mime_type":"image/webp","width":2,"height":2,"thumbnail_width":2,"thumbnail_height":2,
        "thumbnail_byte_count":thumb.byte_count,"source_confidence":"unknown","pasteboard_change_count":1
    })).unwrap()).unwrap();
    (result, payload, webp(b"full payload"))
}
fn completion(
    job: &PendingImageCaptureResult,
    payload: &AssetReservation,
    bytes: &[u8],
) -> CompletePendingImagePayloadRequest {
    CompletePendingImagePayloadRequest {
        job_id: job.job_id.clone(),
        staged_payload_relative_path: payload.staged_relative_path.clone(),
        mime_type: "image/webp".into(),
        width: 2,
        height: 2,
        byte_count: bytes.len() as i64,
    }
}

#[test]
fn recovery_required_after_committed_delete_stops_batch_without_replaying_prefix() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let (_, receipt, bytes) = pending(&mut core, &store);
    core.connection.execute_batch("INSERT INTO clipboard_items
        (id,type,summary,primary_text,content_hash,first_copied_at_ms,last_copied_at_ms,created_at_ms,updated_at_ms)
        VALUES ('first','text','a','a','first',1,1,1,1),('bad','text','b','b','bad',1,1,1,1),('last','text','c','c','last',1,1,1,1);").unwrap();
    store.stage_reserved(&receipt, &bytes).unwrap();
    store
        .lock_lifecycle()
        .unwrap()
        .rename(&receipt.staged_relative_path, &receipt.relative_path)
        .unwrap();
    // Simulate conflicting crash evidence: neither location is a committed asset.
    std::fs::write(root.path().join(&receipt.staged_relative_path), b"conflict").unwrap();

    let result = core
        .mutate_items(vec![
            ItemMutation::RecordCopied {
                item_id: "first".into(),
            },
            ItemMutation::Delete {
                item_id: "bad".into(),
            },
            ItemMutation::RecordCopied {
                item_id: "last".into(),
            },
        ])
        .unwrap();
    assert!(result.session_fault);
    assert_eq!(result.termination_reason.unwrap().code, "recovery_required");
    assert_eq!(result.outcomes[0].status, ItemMutationStatus::Applied);
    assert_eq!(result.outcomes[1].status, ItemMutationStatus::Failed);
    assert_eq!(result.outcomes[1].committed, Some(true));
    assert!(result.outcomes[1].requires_refresh);
    assert_eq!(result.outcomes[2].status, ItemMutationStatus::NotAttempted);
    assert_eq!(result.outcomes[2].committed, Some(false));
    assert_eq!(core.get_item("first").unwrap().unwrap().copy_count, 2);
    assert_eq!(core.get_item("last").unwrap().unwrap().copy_count, 1);
    assert!(core
        .connection
        .query_row(
            "SELECT deleted_at_ms IS NOT NULL FROM clipboard_items WHERE id='bad'",
            [],
            |row| row.get::<_, bool>(0)
        )
        .unwrap());
    assert!(root.path().join(&receipt.relative_path).exists());
    assert!(root.path().join(&receipt.staged_relative_path).exists());
}

#[test]
fn published_native_asset_survives_async_registration_and_parallel_maintenance() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let asset = store
        .stage_encoded("assets/awaiting.png", None, b"synthetic image")
        .unwrap();
    let barrier = Arc::new(Barrier::new(2));
    let other_barrier = barrier.clone();
    let root_path = root.path().to_owned();
    let thread = std::thread::spawn(move || {
        let mut other = ClipboardCore::open(root_path).unwrap();
        other_barrier.wait();
        other.run_maintenance().unwrap();
        other_barrier.wait();
    });
    store.publish(&asset).unwrap();
    barrier.wait();
    barrier.wait();
    assert!(root.path().join(&asset.relative_path).exists());
    let captured = core
        .capture_image(image_request(&asset.relative_path))
        .unwrap();
    core.cleanup_uncommitted_assets(vec![asset.relative_path.clone()])
        .unwrap();
    core.run_maintenance().unwrap();
    assert!(core.get_item(&captured.item_id).unwrap().is_some());
    assert!(root.path().join(&asset.relative_path).exists());
    assert!(store
        .lock_lifecycle()
        .unwrap()
        .reservations()
        .unwrap()
        .is_empty());
    thread.join().unwrap();
}

#[test]
fn database_failure_releases_unregistered_claims_and_dedup_cleans_only_the_new_path() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let failed = store
        .stage_encoded("assets/failure.png", None, b"image")
        .unwrap();
    store.publish(&failed).unwrap();
    core.connection.execute_batch("CREATE TRIGGER reject_capture BEFORE INSERT ON clipboard_items BEGIN SELECT RAISE(ABORT,'injected'); END;").unwrap();
    assert!(core
        .capture_image(image_request(&failed.relative_path))
        .is_err());
    assert!(!root.path().join(&failed.relative_path).exists());
    assert!(store
        .lock_lifecycle()
        .unwrap()
        .reservations()
        .unwrap()
        .is_empty());
    core.connection
        .execute_batch("DROP TRIGGER reject_capture;")
        .unwrap();
    let original = store
        .stage_encoded("assets/original.png", None, b"same image")
        .unwrap();
    store.publish(&original).unwrap();
    let first = core
        .capture_image(image_request(&original.relative_path))
        .unwrap();
    let duplicate = store
        .stage_encoded("assets/duplicate.png", None, b"same image")
        .unwrap();
    store.publish(&duplicate).unwrap();
    let second = core
        .capture_image(image_request(&duplicate.relative_path))
        .unwrap();
    assert_eq!(first.item_id, second.item_id);
    assert!(root.path().join(&original.relative_path).exists());
    assert!(!root.path().join(&duplicate.relative_path).exists());
}

#[test]
fn pending_reservation_survives_registration_until_payload_completion() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let (job, receipt, bytes) = pending(&mut core, &store);
    core.run_maintenance().unwrap();
    assert!(store
        .lock_lifecycle()
        .unwrap()
        .reservation_is_active(&receipt)
        .unwrap());
    store.stage_reserved(&receipt, &bytes).unwrap();
    core.run_maintenance().unwrap();
    assert_eq!(
        core.complete_pending_image_payload(completion(&job, &receipt, &bytes))
            .unwrap()
            .status,
        "ready"
    );
    core.cleanup_uncommitted_assets(vec![
        receipt.relative_path.clone(),
        receipt.staged_relative_path.clone(),
    ])
    .unwrap();
    assert!(root.path().join(&receipt.relative_path).exists());
    assert!(!root.path().join(&receipt.staged_relative_path).exists());
    assert!(store
        .lock_lifecycle()
        .unwrap()
        .reservations()
        .unwrap()
        .is_empty());
    let late = core
        .fail_pending_image_payload(FailPendingImagePayloadRequest {
            job_id: job.job_id,
            staged_payload_relative_path: Some(receipt.staged_relative_path),
            failure_code: "late_cancel".into(),
        })
        .unwrap();
    assert_eq!(late.status, "ready");
    assert!(root.path().join(&receipt.relative_path).exists());
}

#[test]
fn pending_sql_and_commit_failure_restore_staging_and_reopen_safely() {
    for commit_failure in [false, true] {
        let root = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(root.path()).unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let (job, receipt, bytes) = pending(&mut core, &store);
        store.stage_reserved(&receipt, &bytes).unwrap();
        let sql = if commit_failure {
            "CREATE TABLE deferred_failure(item_id TEXT REFERENCES clipboard_items(id) DEFERRABLE INITIALLY DEFERRED); CREATE TRIGGER fail_ready AFTER UPDATE OF payload_state ON clipboard_items WHEN NEW.payload_state='ready' BEGIN INSERT INTO deferred_failure VALUES('missing'); END;"
        } else {
            "CREATE TRIGGER fail_ready BEFORE UPDATE OF payload_state ON clipboard_items WHEN NEW.payload_state='ready' BEGIN SELECT RAISE(ABORT,'injected SQL failure'); END;"
        };
        core.connection.execute_batch(sql).unwrap();
        assert!(core
            .complete_pending_image_payload(completion(&job, &receipt, &bytes))
            .is_err());
        assert!(!root.path().join(&receipt.relative_path).exists());
        assert_eq!(
            std::fs::read(root.path().join(&receipt.staged_relative_path)).unwrap(),
            bytes
        );
        drop(core);
        let mut reopened = ClipboardCore::open(root.path()).unwrap();
        reopened
            .connection
            .execute_batch("DROP TRIGGER fail_ready;")
            .unwrap();
        assert_eq!(
            reopened
                .complete_pending_image_payload(completion(&job, &receipt, &bytes))
                .unwrap()
                .status,
            "ready"
        );
        assert!(root.path().join(&receipt.relative_path).exists());
    }
}

#[test]
fn rename_crash_reconciliation_restores_uncommitted_file_and_keeps_preferences_reachable() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let (job, receipt, bytes) = pending(&mut core, &store);
    store.stage_reserved(&receipt, &bytes).unwrap();
    store
        .lock_lifecycle()
        .unwrap()
        .rename(&receipt.staged_relative_path, &receipt.relative_path)
        .unwrap();
    drop(core); // Simulates process stopping after rename and before SQLite commit.
    let mut reopened = ClipboardCore::open(root.path()).unwrap();
    assert!(!root.path().join(&receipt.relative_path).exists());
    assert!(root.path().join(&receipt.staged_relative_path).exists());
    store
        .lock_lifecycle()
        .unwrap()
        .rename(&receipt.staged_relative_path, &receipt.relative_path)
        .unwrap();
    std::fs::write(
        root.path().join(&receipt.staged_relative_path),
        b"conflicting evidence",
    )
    .unwrap();
    assert_eq!(
        reopened.run_maintenance().unwrap_err().code,
        CoreErrorCode::RecoveryRequired
    );
    drop(reopened);
    let settings = ClipboardCore::open_without_history_maintenance(root.path()).unwrap();
    assert!(settings.get_preferences().is_ok());
    assert!(root.path().join(&receipt.relative_path).exists());
    assert!(root.path().join(&receipt.staged_relative_path).exists());
    assert!(settings.get_item(&job.item_id).unwrap().is_some());
}

#[test]
fn committed_asset_recovery_keeps_final_and_restores_missing_final_from_matching_staging() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let (job, receipt, bytes) = pending(&mut core, &store);
    store.stage_reserved(&receipt, &bytes).unwrap();
    core.complete_pending_image_payload(completion(&job, &receipt, &bytes))
        .unwrap();
    store
        .lock_lifecycle()
        .unwrap()
        .rename(&receipt.relative_path, &receipt.staged_relative_path)
        .unwrap();
    drop(core);
    let reopened = ClipboardCore::open(root.path()).unwrap();
    assert_eq!(
        std::fs::read(root.path().join(&receipt.relative_path)).unwrap(),
        bytes
    );
    assert!(!root.path().join(&receipt.staged_relative_path).exists());
    assert_eq!(
        reopened
            .get_item(&job.item_id)
            .unwrap()
            .unwrap()
            .payload_state,
        PayloadState::Ready
    );
}

#[test]
fn abandoned_reservations_are_reclaimed_but_shared_active_references_survive_purge() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let abandoned = store
        .stage_encoded("assets/abandoned.png", None, b"abandoned")
        .unwrap();
    store.publish(&abandoned).unwrap();
    store
        .abandon_owned_paths(&[abandoned.relative_path.clone()])
        .unwrap();
    let reclaimed = core.run_maintenance().unwrap();
    assert_eq!(reclaimed.reclaimed_bytes, b"abandoned".len() as i64);
    assert!(!root.path().join(&abandoned.relative_path).exists());
    for (path, bytes) in [
        ("assets/first.png", b"first".as_slice()),
        ("assets/second.png", b"second"),
    ] {
        let receipt = store.stage_encoded(path, None, bytes).unwrap();
        store.publish(&receipt).unwrap();
        core.capture_image(image_request(path)).unwrap();
    }
    let first = core
        .connection
        .query_row(
            "SELECT item_id FROM clipboard_assets WHERE relative_path='assets/first.png'",
            [],
            |row| row.get::<_, String>(0),
        )
        .unwrap();
    core.connection.execute("UPDATE clipboard_assets SET relative_path='assets/first.png' WHERE relative_path='assets/second.png'",[]).unwrap();
    core.delete_item(first).unwrap();
    assert!(root.path().join("assets/first.png").exists());
}

#[test]
fn pending_completion_cannot_publish_incomplete_reserved_staging() {
    let root = tempfile::tempdir().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let store = AssetStore::open(root.path()).unwrap();
    let (job, receipt, bytes) = pending(&mut core, &store);
    let path = root.path().join(&receipt.staged_relative_path);
    std::fs::create_dir_all(path.parent().unwrap()).unwrap();
    std::fs::write(&path, &bytes).unwrap(); // Writer has not saved completed metadata.
    assert!(core
        .complete_pending_image_payload(completion(&job, &receipt, &bytes))
        .is_err());
    assert!(path.exists());
    assert!(!root.path().join(&receipt.relative_path).exists());
    assert_eq!(
        core.get_item(&job.item_id).unwrap().unwrap().payload_state,
        PayloadState::Pending
    );
}

#[test]
fn late_owned_complete_and_failure_release_assets_after_tombstone_purge() {
    for fail in [false, true] {
        let root = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(root.path()).unwrap();
        let store = AssetStore::open(root.path()).unwrap();
        let (job, receipt, bytes) = pending(&mut core, &store);
        core.delete_item(&job.item_id).unwrap();
        core.connection
            .execute(
                "UPDATE pending_image_jobs SET cleanup_after_ms=0 WHERE job_id=?1",
                [&job.job_id],
            )
            .unwrap();
        core.run_maintenance().unwrap();
        store.stage_reserved(&receipt, &bytes).unwrap();
        let result = if fail {
            core.fail_pending_image_payload(FailPendingImagePayloadRequest {
                job_id: job.job_id.clone(),
                staged_payload_relative_path: Some(receipt.staged_relative_path.clone()),
                failure_code: "late".into(),
            })
            .unwrap()
        } else {
            core.complete_pending_image_payload(completion(&job, &receipt, &bytes))
                .unwrap()
        };
        assert_eq!(result.status, "not_pending");
        assert!(!root.path().join(&receipt.staged_relative_path).exists());
        assert!(store
            .lock_lifecycle()
            .unwrap()
            .reservations()
            .unwrap()
            .is_empty());
    }
}
