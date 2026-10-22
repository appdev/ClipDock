use super::*;
use crate::{CaptureTextRequest, ItemMutation, ItemMutationStatus, PageRequest, SourceConfidence};
use rusqlite::{params, Connection};
use tempfile::TempDir;

fn seed(connection: &Connection, id: &str, text: &str) {
    connection.execute("INSERT INTO clipboard_items
        (id,type,summary,primary_text,content_hash,first_copied_at_ms,last_copied_at_ms,created_at_ms,updated_at_ms)
        VALUES (?1,'text','synthetic',?2,?1,1,1,1,1)", params![id,text]).unwrap();
}

fn captured(core: &mut ClipboardCore, text: &str) -> String {
    core.capture_text(CaptureTextRequest {
        text: text.into(),
        detected_link: None,
        display_rtf_relative_path: None,
        display_rtf_mime_type: None,
        display_rtf_byte_count: 0,
        source_bundle_id: None,
        source_app_name: None,
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::Unknown,
        pasteboard_change_count: 1,
        self_write_token: None,
    })
    .unwrap()
    .item_id
}

#[test]
fn lightweight_projection_preserves_metadata_search_and_full_lookup() {
    let root = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let body = format!("{} hiddenneedle", "x".repeat(700));
    let id = captured(&mut core, &body);
    core.set_item_pinboard_membership(&id, DEFAULT_PINBOARD_ID, true)
        .unwrap();
    let query = ItemQuery {
        search_text: Some("hiddenneedle".into()),
        ..Default::default()
    };
    let full = core
        .list_items(query.clone(), PageRequest::default())
        .unwrap();
    let page = core.list_entries(query, PageRequest::default()).unwrap();
    assert_eq!(page.total_count, full.total_count);
    assert_eq!(page.has_more, full.has_more);
    assert_eq!(
        page.items[0].text_preview.as_deref(),
        Some("x".repeat(500).as_str())
    );
    assert!(page.items[0].preview_truncated);
    let mut expected = full.items[0].clone();
    expected.primary_text = None;
    assert_eq!(page.items[0].item, expected);
    let value = serde_json::to_value(&page.items[0]).unwrap();
    assert_eq!(value["id"], id);
    assert!(value.get("item").is_none());
    assert!(value["primary_text"].is_null());
    assert_eq!(core.get_item(&id).unwrap(), Some(full.items[0].clone()));
    core.delete_item(&id).unwrap();
    assert!(core
        .list_entries(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .is_empty());
    let results = core
        .get_items(vec![id.clone(), "missing".into(), id.clone()])
        .unwrap();
    assert_eq!(results[0].item, results[2].item);
    assert_eq!(results[0].item_id, id);
    assert_eq!(
        results[0].item.as_ref().unwrap().primary_text.as_deref(),
        Some(body.as_str())
    );
    assert!(results[1].item.is_none());
    assert!(core.get_items(vec![id; 201]).is_err());
    assert!(core.get_items(Vec::new()).unwrap().is_empty());
}

#[test]
fn unicode_projection_matches_foundation_counts_and_scalar_safe_utf16_boundaries() {
    let root = TempDir::new().unwrap();
    let core = ClipboardCore::open(root.path()).unwrap();
    let fixtures = [
        ("\u{200b} e\u{301} 👩‍👩‍👧‍👦 🇺🇸\r\n", 5, 17),
        ("\r\n", 0, 2),
        (" a\r\nb\rc\nd ", 7, 10),
        ("\u{0085}a\r\nb\u{0085}", 3, 6),
        ("a\u{0085}b", 3, 3),
        ("", 0, 0),
    ];
    for (index, (text, graphemes, scalars)) in fixtures.into_iter().enumerate() {
        let id = format!("fixture-{index}");
        seed(&core.connection, &id, text);
        let page = core
            .list_entries(ItemQuery::default(), PageRequest::default())
            .unwrap();
        let entry = page.items.iter().find(|entry| entry.item.id == id).unwrap();
        assert_eq!(entry.trimmed_grapheme_count, Some(graphemes));
        assert_eq!(entry.scalar_count, Some(scalars));
        let scalar_page = core
            .list_entries_with_metrics(ItemQuery::default(), PageRequest::default(), false)
            .unwrap();
        let scalar_entry = scalar_page
            .items
            .iter()
            .find(|entry| entry.item.id == id)
            .unwrap();
        let mut expected = entry.clone();
        expected.trimmed_grapheme_count = None;
        assert_eq!(scalar_entry, &expected);
        assert!(serde_json::to_value(scalar_entry).unwrap()["trimmed_grapheme_count"].is_null());
    }
    let text = format!("{}😀tail", "a".repeat(499));
    seed(&core.connection, "boundary", &text);
    let page = core
        .list_entries(ItemQuery::default(), PageRequest::default())
        .unwrap();
    let entry = page
        .items
        .iter()
        .find(|entry| entry.item.id == "boundary")
        .unwrap();
    assert_eq!(
        entry.text_preview.as_ref().unwrap().encode_utf16().count(),
        499
    );
    assert!(entry.preview_truncated);
    core.connection
        .execute(
            "UPDATE clipboard_items SET type='rich_text' WHERE id='boundary'",
            [],
        )
        .unwrap();
    assert!(core
        .list_entries(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .iter()
        .find(|entry| entry.item.id == "boundary")
        .unwrap()
        .item
        .primary_text
        .is_none());
    core.connection
        .execute(
            "UPDATE clipboard_items SET type='file' WHERE id='boundary'",
            [],
        )
        .unwrap();
    let file = core
        .list_entries(ItemQuery::default(), PageRequest::default())
        .unwrap()
        .items
        .into_iter()
        .find(|entry| entry.item.id == "boundary")
        .unwrap();
    assert_eq!(file.item.primary_text.as_deref(), Some(text.as_str()));
    assert!(file.text_preview.is_none());
}

#[test]
fn page_snapshot_includes_count_rows_and_related_records_during_writes() {
    for lightweight in [true, false] {
        let root = TempDir::new().unwrap();
        let mut core = ClipboardCore::open(root.path()).unwrap();
        seed(&core.connection, "item", "body");
        core.connection
            .execute("UPDATE clipboard_items SET type='file' WHERE id='item'", [])
            .unwrap();
        core.set_item_pinboard_membership("item", DEFAULT_PINBOARD_ID, true)
            .unwrap();
        core.connection
            .execute(
                "INSERT INTO clipboard_file_items
            (id,item_id,order_index,path,file_name,created_at_ms,updated_at_ms)
            VALUES ('file','item',0,'/synthetic/old','old',1,1)",
                [],
            )
            .unwrap();
        let writer = Connection::open(core.database_path()).unwrap();
        super::queries::QUERY_READ_HOOK.with(|hook| {
            *hook.borrow_mut() = Some(Box::new(move |stage| {
                if stage == "after_count" {
                    seed(&writer, "concurrent", "new");
                }
                if stage == "after_rows" {
                    writer
                        .execute("DELETE FROM pinboard_items WHERE item_id='item'", [])
                        .unwrap();
                    writer
                        .execute(
                            "UPDATE clipboard_file_items SET file_name='new' WHERE id='file'",
                            [],
                        )
                        .unwrap();
                }
            }))
        });
        let (items, total_count) = if lightweight {
            let page = core
                .list_entries(ItemQuery::default(), PageRequest::default())
                .unwrap();
            (
                page.items
                    .into_iter()
                    .map(|entry| entry.item)
                    .collect::<Vec<_>>(),
                page.total_count,
            )
        } else {
            let page = core
                .list_items(ItemQuery::default(), PageRequest::default())
                .unwrap();
            (page.items, page.total_count)
        };
        super::queries::QUERY_READ_HOOK.with(|hook| *hook.borrow_mut() = None);
        assert_eq!(total_count, 1);
        assert_eq!(items.len(), 1);
        assert!(items[0].is_pinned);
        assert_eq!(items[0].pinboard_ids, vec![DEFAULT_PINBOARD_ID]);
        assert_eq!(items[0].file_items[0].file_name, "old");
        assert!(core.connection.is_autocommit());
        assert_eq!(
            core.list_entries(ItemQuery::default(), PageRequest::default())
                .unwrap()
                .total_count,
            2
        );
    }
}

#[test]
fn pages_remain_bounded_and_pinboard_beyond_history_capacity_is_reachable() {
    let root = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let transaction = core.connection.transaction().unwrap();
    for index in 0..5_101 {
        let id = format!("item-{index:05}");
        seed(&transaction, &id, "synthetic");
        transaction.execute("INSERT INTO pinboard_items(pinboard_id,item_id,pinned_at_ms,display_order,created_at_ms,updated_at_ms) VALUES (?1,?2,1,?3,1,1)",
            params![DEFAULT_PINBOARD_ID,id,index]).unwrap();
    }
    transaction.commit().unwrap();
    let query = ItemQuery {
        pinboard_id: Some(DEFAULT_PINBOARD_ID.into()),
        ..Default::default()
    };
    let first = core
        .list_entries(
            query.clone(),
            PageRequest {
                limit: 10_000,
                offset: 0,
            },
        )
        .unwrap();
    assert_eq!(first.items.len(), 200);
    assert_eq!(first.total_count, 5_101);
    assert!(first.has_more);
    for offset in [200, 350, 450, 5_000] {
        let page = core
            .list_entries(query.clone(), PageRequest { limit: 200, offset })
            .unwrap();
        assert_eq!(page.items[0].item.id, format!("item-{offset:05}"));
        assert_eq!(page.items.len(), if offset == 5_000 { 101 } else { 200 });
        assert_eq!(page.has_more, offset != 5_000);
    }
}

#[test]
fn mutations_preserve_duplicates_zero_and_ordinary_failures() {
    let root = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let id = captured(&mut core, "batch");
    let requests = vec![
        ItemMutation::RecordCopied {
            item_id: id.clone(),
        },
        ItemMutation::RecordCopied {
            item_id: id.clone(),
        },
        ItemMutation::Delete {
            item_id: " ".into(),
        },
        ItemMutation::SetPinboardMembership {
            item_id: id.clone(),
            pinboard_id: DEFAULT_PINBOARD_ID.into(),
            is_member: true,
        },
        ItemMutation::SetPinboardMembership {
            item_id: id.clone(),
            pinboard_id: DEFAULT_PINBOARD_ID.into(),
            is_member: true,
        },
        ItemMutation::Delete {
            item_id: id.clone(),
        },
        ItemMutation::Delete {
            item_id: id.clone(),
        },
    ];
    let result = core.mutate_items(requests).unwrap();
    assert!(!result.session_fault);
    assert_eq!(
        result
            .outcomes
            .iter()
            .map(|item| item.affected_count)
            .collect::<Vec<_>>(),
        vec![1, 1, 0, 1, 1, 1, 0]
    );
    assert_eq!(result.outcomes[2].status, ItemMutationStatus::Failed);
    assert_eq!(result.outcomes[2].committed, Some(false));
    assert_eq!(result.outcomes[6].status, ItemMutationStatus::ZeroAffected);
    assert_eq!(core.get_item(&id).unwrap().unwrap().copy_count, 3);
    assert!(core
        .mutate_items(vec![ItemMutation::Delete { item_id: id }; 201])
        .is_err());
    assert!(core.mutate_items(Vec::new()).unwrap().outcomes.is_empty());
}

#[test]
fn mutation_database_fault_stops_after_committed_prefix() {
    let root = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    for id in ["first", "bad", "last"] {
        seed(&core.connection, id, "body");
    }
    core.connection
        .execute_batch(
            "CREATE TRIGGER injected_failure BEFORE UPDATE ON clipboard_items WHEN OLD.id='bad'
        BEGIN SELECT RAISE(ABORT, 'injected database fault'); END;",
        )
        .unwrap();
    let result = core
        .mutate_items(
            ["first", "bad", "last"]
                .into_iter()
                .map(|id| ItemMutation::RecordCopied { item_id: id.into() })
                .collect(),
        )
        .unwrap();
    assert!(result.session_fault);
    assert!(result.termination_reason.is_some());
    assert_eq!(
        result
            .outcomes
            .iter()
            .map(|outcome| outcome.status)
            .collect::<Vec<_>>(),
        vec![
            ItemMutationStatus::Applied,
            ItemMutationStatus::Failed,
            ItemMutationStatus::NotAttempted
        ]
    );
    assert_eq!(result.outcomes[1].committed, None);
    assert_eq!(core.get_item("first").unwrap().unwrap().copy_count, 2);
    assert_eq!(core.get_item("last").unwrap().unwrap().copy_count, 1);
}

#[test]
fn delete_reports_committed_cleanup_failure_and_continues() {
    let root = TempDir::new().unwrap();
    let mut core = ClipboardCore::open(root.path()).unwrap();
    let id = captured(&mut core, "delete");
    let next = captured(&mut core, "next");
    std::fs::write(root.path().join("assets/blocked"), b"synthetic blocker").unwrap();
    core.connection
        .execute(
            "INSERT INTO clipboard_assets(id,item_id,kind,relative_path,created_at_ms)
        VALUES ('blocked',?1,'payload','assets/blocked/child',1)",
            [&id],
        )
        .unwrap();
    let result = core
        .mutate_items(vec![
            ItemMutation::Delete {
                item_id: id.clone(),
            },
            ItemMutation::RecordCopied {
                item_id: next.clone(),
            },
        ])
        .unwrap();
    assert!(!result.session_fault);
    assert_eq!(result.outcomes[0].status, ItemMutationStatus::Failed);
    assert_eq!(result.outcomes[0].committed, Some(true));
    assert!(result.outcomes[0].requires_refresh);
    assert_eq!(result.outcomes[1].status, ItemMutationStatus::Applied);
    assert!(core.get_item(&id).unwrap().is_none());
}

#[test]
#[ignore = "synthetic timing evidence; run in release mode with --nocapture"]
fn synthetic_list_projection_benchmark() {
    use std::time::Instant;
    fn percentiles(mut values: Vec<u128>) -> (u128, u128) {
        values.sort();
        (
            values[values.len() / 2],
            values[(values.len() * 95).div_ceil(100) - 1],
        )
    }
    fn sample(core: &ClipboardCore, lightweight: bool, metrics: bool) -> (usize, u128, u128, u128) {
        let start = Instant::now();
        let page = PageRequest {
            limit: 200,
            offset: 0,
        };
        let (json, query_us, serialize_us) = if lightweight {
            let result = core
                .list_entries_with_metrics(ItemQuery::default(), page, metrics)
                .unwrap();
            let query_us = start.elapsed().as_micros();
            let serialize = Instant::now();
            let json = serde_json::to_vec(&result.items).unwrap();
            (json, query_us, serialize.elapsed().as_micros())
        } else {
            let result = core.list_items(ItemQuery::default(), page).unwrap();
            let query_us = start.elapsed().as_micros();
            let serialize = Instant::now();
            let json = serde_json::to_vec(&result.items).unwrap();
            (json, query_us, serialize.elapsed().as_micros())
        };
        let decode = Instant::now();
        if lightweight {
            std::hint::black_box(
                serde_json::from_slice::<Vec<crate::ClipboardListEntry>>(&json).unwrap(),
            );
        } else {
            std::hint::black_box(
                serde_json::from_slice::<Vec<crate::ClipboardItemSummary>>(&json).unwrap(),
            );
        }
        (
            json.len(),
            query_us,
            serialize_us,
            decode.elapsed().as_micros(),
        )
    }
    for (name, kind, body) in [
        ("short", "text", "synthetic short text ".repeat(4)),
        ("ascii16k", "text", "a".repeat(16_384)),
        ("mixed16k", "text", "中😀e\u{301}abcdab".repeat(1_024)),
        ("rich16k", "rich_text", "a".repeat(16_384)),
        ("image_control", "image", String::new()),
        ("large256k", "text", "a".repeat(262_144)),
    ] {
        let root = TempDir::new().unwrap();
        let mut core = ClipboardCore::open_without_history_maintenance(root.path()).unwrap();
        let transaction = core.connection.transaction().unwrap();
        for index in 0..200 {
            seed(&transaction, &format!("benchmark-{index}"), &body);
        }
        transaction
            .execute("UPDATE clipboard_items SET type=?1", [kind])
            .unwrap();
        transaction.commit().unwrap();
        for (lightweight, metrics) in [(false, true), (true, true), (true, false)] {
            if let Some(directory) = std::env::var_os("CLIPDOCK_BENCHMARK_FIXTURES") {
                let directory = std::path::PathBuf::from(directory);
                std::fs::create_dir_all(&directory).unwrap();
                let page = PageRequest {
                    limit: 200,
                    offset: 0,
                };
                let json = if lightweight {
                    serde_json::to_vec(
                        &core
                            .list_entries_with_metrics(ItemQuery::default(), page, metrics)
                            .unwrap()
                            .items,
                    )
                    .unwrap()
                } else {
                    serde_json::to_vec(&core.list_items(ItemQuery::default(), page).unwrap().items)
                        .unwrap()
                };
                let suffix = if metrics {
                    lightweight.to_string()
                } else {
                    "scalar".to_string()
                };
                std::fs::write(directory.join(format!("{name}-{suffix}.json")), json).unwrap();
            }
            for cold_connection in [true, false] {
                let mut query = Vec::new();
                let mut serialize = Vec::new();
                let mut decode = Vec::new();
                let mut bytes = 0;
                let iterations = if cold_connection { 10 } else { 30 };
                for _ in 0..iterations {
                    let measurement = if cold_connection {
                        let reopened =
                            ClipboardCore::open_without_history_maintenance(root.path()).unwrap();
                        sample(&reopened, lightweight, metrics)
                    } else {
                        sample(&core, lightweight, metrics)
                    };
                    bytes = measurement.0;
                    query.push(measurement.1);
                    serialize.push(measurement.2);
                    decode.push(measurement.3);
                }
                let (q50, q95) = percentiles(query);
                let (s50, s95) = percentiles(serialize);
                let (d50, d95) = percentiles(decode);
                println!("A1 scenario={name} rows=200 body_bytes={} lightweight={lightweight} grapheme_metrics={metrics} cold_connection={cold_connection} n={iterations} json_bytes={bytes} query_us={q50}/{q95} serialize_us={s50}/{s95} rust_decode_us={d50}/{d95}",body.len());
            }
        }
        let mut lookup = Vec::new();
        for _ in 0..30 {
            let start = Instant::now();
            std::hint::black_box(core.get_item("benchmark-0").unwrap());
            lookup.push(start.elapsed().as_micros());
        }
        let (p50, p95) = percentiles(lookup);
        println!("A1 lookup scenario={name} n=30 get_item_us={p50}/{p95}");
    }
}
