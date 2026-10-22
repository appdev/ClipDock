use clipboard_core::{
    CaptureImageRequest, CaptureResult, CaptureTextRequest, ClipboardItemType,
    HistoryPreferencesPatch, IgnoreListPreferencesPatch, ItemBatchMutationResult,
    ItemManagementResult, ItemMutation, ItemPage, ItemQuery, ListEntryPage, PageRequest,
    PinboardPage, PinboardSummary, PreferencesDocument, PreferencesMaintenance,
    PreferencesMaintenanceStatus, PreferencesPatch, PreferencesPatchResult, SourceConfidence,
};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_dialog::DialogExt;

use crate::core_state::CoreState;

#[tauri::command]
pub async fn transfer_clipboard_backup(
    app: tauri::AppHandle,
    importing: bool,
) -> Result<Option<clipboard_core::BackupResult>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut dialog = app
            .dialog()
            .file()
            .add_filter("ClipDock backup", &["clipdock"]);
        if let Some(window) = app.get_webview_window("preferences") {
            dialog = dialog.set_parent(&window);
        }
        let selected = if importing {
            dialog.set_title("导入数据").blocking_pick_file()
        } else {
            dialog
                .set_title("导出数据")
                .set_file_name("ClipDock.clipdock")
                .blocking_save_file()
        };
        let Some(selected) = selected else {
            return Ok(None);
        };
        let path = selected.into_path().map_err(|e| e.to_string())?;
        // Keep resource I/O off the capture connection's mutex. SQLite provides
        // the backup snapshot and the short merge transaction's synchronization.
        let mut core = clipboard_core::ClipboardCore::open_for_backup(
            app.state::<CoreState>().root_dir(),
        )
        .map_err(|e| e.to_string())?;
        let result = if importing {
            core.import_backup(&path)
        } else {
            core.export_backup(&path)
        }
        .map_err(|e| e.to_string())?;
        if importing {
            app.state::<CoreState>().mutate(&app, "backup", |_| Ok(()))?;
            let _ = app.emit("clipdock://backup-imported", &result);
        }
        Ok(Some(result))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CoreInfoResult {
    pub database_path: String,
    pub schema_version: i64,
    pub item_count: i64,
}

#[derive(Serialize)]
pub struct HistoryPage {
    #[serde(flatten)]
    page: ItemPage,
    revision: u64,
}

#[derive(Serialize)]
pub struct HistoryEntryPage {
    #[serde(flatten)]
    page: ListEntryPage,
    revision: u64,
}

#[tauri::command]
pub async fn list_clipboard_entries(
    app: AppHandle,
    item_type: Option<String>,
    source_app_id: Option<String>,
    pinboard_id: Option<String>,
    search_text: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<HistoryEntryPage, String> {
    run_blocking(app, move |_app, state| {
        let query = ItemQuery {
            item_type: item_type.map(|value| ClipboardItemType::from_storage(&value)),
            source_app_id,
            pinboard_id,
            search_text,
        };
        let page = PageRequest {
            limit: limit.unwrap_or(50),
            offset: offset.unwrap_or(0),
        }
        .normalized();
        let (page, revision) = state.read_with_revision(|core| {
            core.list_entries_with_metrics(query, page, false)
                .map_err(|error| error.to_string())
        })?;
        Ok(HistoryEntryPage { page, revision })
    })
    .await
}

#[tauri::command]
pub async fn mutate_clipboard_items(
    app: AppHandle,
    mutations: Vec<ItemMutation>,
) -> Result<ItemBatchMutationResult, String> {
    run_blocking(app, move |app, state| state.mutate_batch(app, mutations)).await
}

/// Basic diagnostics about the storage engine: database location, applied
/// schema version, and active item count.
#[tauri::command]
pub async fn core_info(app: AppHandle) -> Result<CoreInfoResult, String> {
    run_blocking(app, move |_app, state| {
        state.with_core(|core| {
            let info = core.info().map_err(|error| error.to_string())?;
            Ok(CoreInfoResult {
                database_path: info.database_path,
                schema_version: info.schema_version,
                item_count: info.item_count,
            })
        })
    })
    .await
}

/// Page through stored clipboard items, optionally filtered by type, source
/// app, pinboard, or full-text search.
#[tauri::command]
pub async fn list_clipboard_items(
    app: AppHandle,
    item_type: Option<String>,
    source_app_id: Option<String>,
    pinboard_id: Option<String>,
    search_text: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<HistoryPage, String> {
    run_blocking(app, move |_app, state| {
        let query = ItemQuery {
            item_type: item_type.map(|value| ClipboardItemType::from_storage(&value)),
            source_app_id,
            pinboard_id,
            search_text,
        };
        let page = PageRequest {
            limit: limit.unwrap_or(50),
            offset: offset.unwrap_or(0),
        }
        .normalized();

        let (page, revision) = state.read_with_revision(|core| {
            core.list_items(query, page)
                .map_err(|error| error.to_string())
        })?;
        Ok(HistoryPage { page, revision })
    })
    .await
}

/// List all custom pinboards plus their item counts.
#[tauri::command]
pub async fn list_pinboards(app: AppHandle) -> Result<PinboardPage, String> {
    run_blocking(app, move |_app, state| {
        state.with_core(|core| core.list_pinboards().map_err(|error| error.to_string()))
    })
    .await
}

#[tauri::command]
pub async fn create_pinboard(
    app: AppHandle,
    title: String,
    color_code: Option<i64>,
) -> Result<PinboardSummary, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "pinboards", |core| {
            core.create_pinboard(title, color_code)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

#[tauri::command]
pub async fn rename_pinboard(
    app: AppHandle,
    pinboard_id: String,
    title: String,
) -> Result<PinboardSummary, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "pinboards", |core| {
            core.rename_pinboard(pinboard_id, title)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

#[tauri::command]
pub async fn update_pinboard_color(
    app: AppHandle,
    pinboard_id: String,
    color_code: i64,
) -> Result<PinboardSummary, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "pinboards", |core| {
            core.update_pinboard_color(pinboard_id, color_code)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

#[tauri::command]
pub async fn delete_pinboard(
    app: AppHandle,
    pinboard_id: String,
) -> Result<ItemManagementResult, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "pinboards", |core| {
            core.delete_pinboard(pinboard_id)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

/// Add or remove an item from a pinboard.
#[tauri::command]
pub async fn set_item_pinboard_membership(
    app: AppHandle,
    item_id: String,
    pinboard_id: String,
    is_member: bool,
) -> Result<ItemManagementResult, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "membership", |core| {
            core.set_item_pinboard_membership(item_id, pinboard_id, is_member)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

/// Update the card label without changing its clipboard payload.
#[tauri::command]
pub async fn rename_clipboard_item(
    app: AppHandle,
    item_id: String,
    title: String,
) -> Result<ItemManagementResult, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "rename", |core| {
            core.rename_item(item_id, title)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

/// Soft-delete a single clipboard item.
#[tauri::command]
pub async fn delete_clipboard_item(
    app: AppHandle,
    item_id: String,
) -> Result<ItemManagementResult, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "delete", |core| {
            core.delete_item(item_id).map_err(|error| error.to_string())
        })
    })
    .await
}

/// Bump an item's copy count and recency when the user re-copies it.
#[tauri::command]
pub async fn record_clipboard_item_copied(
    app: AppHandle,
    item_id: String,
) -> Result<ItemManagementResult, String> {
    run_blocking(app, move |app, state| {
        state.mutate(app, "copy", |core| {
            core.record_item_copied(item_id)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

/// Clear items matching an optional filter (defaults to clearing unpinned
/// history when no filter is supplied).
#[tauri::command]
pub async fn clear_clipboard_items(
    app: AppHandle,
    item_type: Option<String>,
    source_app_id: Option<String>,
    pinboard_id: Option<String>,
    search_text: Option<String>,
) -> Result<ItemManagementResult, String> {
    run_blocking(app, move |app, state| {
        let query = ItemQuery {
            item_type: item_type.map(|value| ClipboardItemType::from_storage(&value)),
            source_app_id,
            pinboard_id,
            search_text,
        };
        state.mutate(app, "clear", |core| {
            core.clear_items(query).map_err(|error| error.to_string())
        })
    })
    .await
}

/// Persist a captured text (or detected-link) clipboard entry.
#[tauri::command]
pub async fn capture_clipboard_text(
    app: AppHandle,
    text: String,
    source_app_name: Option<String>,
    source_bundle_id: Option<String>,
    self_write_token: Option<String>,
) -> Result<CaptureResult, String> {
    run_blocking(app, move |app, state| {
        let request = CaptureTextRequest {
            text,
            detected_link: None,
            display_rtf_relative_path: None,
            display_rtf_mime_type: None,
            display_rtf_byte_count: 0,
            source_bundle_id,
            source_app_name,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 0,
            self_write_token,
        };
        state.mutate(app, "capture", |core| {
            core.capture_text(request)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

/// Persist a captured image clipboard entry. `payload_relative_path` is
/// relative to the ClipDock data root (see `CoreState::root_dir`).
#[tauri::command]
pub async fn capture_clipboard_image(
    app: AppHandle,
    payload_relative_path: String,
    width: i64,
    height: i64,
    byte_count: i64,
    mime_type: Option<String>,
    source_app_name: Option<String>,
    self_write_token: Option<String>,
) -> Result<CaptureResult, String> {
    run_blocking(app, move |app, state| {
        let request = CaptureImageRequest {
            payload_relative_path,
            preview_relative_path: None,
            mime_type,
            width,
            height,
            byte_count,
            source_bundle_id: None,
            source_app_name,
            source_bundle_path: None,
            source_icon_relative_path: None,
            source_confidence: SourceConfidence::Unknown,
            pasteboard_change_count: 0,
            self_write_token,
        };
        state.mutate(app, "capture", |core| {
            core.capture_image(request)
                .map_err(|error| error.to_string())
        })
    })
    .await
}

/// Read the full preferences document.
#[tauri::command]
pub async fn get_preferences(app: AppHandle) -> Result<PreferencesDocument, String> {
    run_blocking(app, move |_app, state| {
        state.with_core(|core| core.get_preferences().map_err(|error| error.to_string()))
    })
    .await
}

#[derive(Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CapturePreferencesPatch {
    #[serde(default, deserialize_with = "present_patch_field")]
    pub retention_days: Option<i64>,
    #[serde(default, deserialize_with = "present_patch_field")]
    pub retention_forever: Option<bool>,
    #[serde(default, deserialize_with = "present_patch_field")]
    pub ignored_app_identifiers: Option<Vec<String>>,
}

fn present_patch_field<'de, D: serde::Deserializer<'de>, T: Deserialize<'de>>(
    deserializer: D,
) -> Result<Option<T>, D::Error> {
    T::deserialize(deserializer).map(Some)
}

#[derive(Serialize)]
pub struct CapturePreferencesState {
    #[serde(flatten)]
    document: PreferencesDocument,
    revision: u64,
    warnings: Vec<CapturePreferencesWarning>,
    maintenance: Option<PreferencesMaintenance>,
}

#[derive(Debug, Serialize)]
pub struct CapturePreferencesWarning {
    stage: &'static str,
    code: String,
}

fn maintenance_warnings(state: &CoreState) -> Vec<CapturePreferencesWarning> {
    state
        .maintenance_warning
        .lock()
        .ok()
        .and_then(|warning| warning.clone())
        .map(|code| {
            vec![CapturePreferencesWarning {
                stage: "history_maintenance",
                code,
            }]
        })
        .unwrap_or_default()
}

fn capture_preferences_state(state: &CoreState) -> Result<CapturePreferencesState, String> {
    let (document, revision) = state
        .read_with_revision(|core| core.get_preferences().map_err(|error| error.to_string()))?;
    Ok(CapturePreferencesState {
        document,
        revision,
        warnings: maintenance_warnings(state),
        maintenance: None,
    })
}

impl CapturePreferencesPatch {
    fn into_core(self) -> Result<PreferencesPatch, String> {
        if let Some(days) = self.retention_days {
            if ![1, 7, 30, 365].contains(&days) {
                return Err("unsupported retention period".into());
            }
        }
        if let Some(rules) = &self.ignored_app_identifiers {
            if rules.len() > 64 || rules.iter().any(|rule| rule.chars().count() > 120) {
                return Err("use at most 64 application names, each at most 120 characters".into());
            }
        }
        Ok(PreferencesPatch {
            history: (self.retention_days.is_some() || self.retention_forever.is_some()).then_some(
                HistoryPreferencesPatch {
                    retention_days: self.retention_days,
                    retention_forever: self.retention_forever,
                },
            ),
            ignore_list: self
                .ignored_app_identifiers
                .map(|rules| IgnoreListPreferencesPatch {
                    ignored_app_identifiers: Some(rules),
                    ..Default::default()
                }),
            ..Default::default()
        })
    }
}

fn save_capture_patch(
    core: &mut clipboard_core::ClipboardCore,
    patch: PreferencesPatch,
    write_marker: impl FnOnce() -> std::io::Result<()>,
) -> Result<(PreferencesPatchResult, Option<CapturePreferencesWarning>), String> {
    let saved = core
        .patch_preferences(patch)
        .map_err(|error| error.to_string())?;
    let warning = write_marker().err().map(|_| CapturePreferencesWarning {
        stage: "legacy_marker",
        code: "io_failed".into(),
    });
    Ok((saved, warning))
}

/// Only the Windows capture settings are writable here; preserve all other fields.
#[tauri::command]
pub async fn patch_capture_preferences(
    app: AppHandle,
    patch: CapturePreferencesPatch,
    migrate_legacy: Option<bool>,
) -> Result<CapturePreferencesState, String> {
    run_blocking(app, move |app, state| {
        let _gate = state
            .preferences_gate
            .lock()
            .map_err(|_| "preferences lock poisoned")?;
        let marker = state.root_dir().join("windows-preferences-migrated-v1");
        if migrate_legacy == Some(true) && marker.exists() {
            return capture_preferences_state(state);
        }
        let patch = patch.into_core()?;
        let (result, marker_warning) = state.mutate(app, "preferences", |core| {
            save_capture_patch(core, patch, || std::fs::write(marker, b"1"))
        })?;
        if let Ok(mut warning) = state.maintenance_warning.lock() {
            match result.maintenance.status {
                PreferencesMaintenanceStatus::Applied => *warning = None,
                PreferencesMaintenanceStatus::Warning => *warning = result.maintenance.code.clone(),
                PreferencesMaintenanceStatus::NotNeeded => {}
            }
        }
        let mut warnings = maintenance_warnings(state);
        warnings.extend(marker_warning);
        let (_, revision) = state.read_with_revision(|_| Ok(()))?;
        let saved = CapturePreferencesState {
            document: result.document,
            revision,
            warnings,
            maintenance: Some(result.maintenance),
        };
        let _ = app.emit("capture-preferences-changed", &saved);
        Ok(saved)
    })
    .await
}

async fn run_blocking<T, F>(app: AppHandle, action: F) -> Result<T, String>
where
    T: Send + 'static,
    F: FnOnce(&AppHandle, &CoreState) -> Result<T, String> + Send + 'static,
{
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<CoreState>();
        action(&app, &state)
    })
    .await
    .map_err(|error| error.to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn narrow_preferences_patch_preserves_unrelated_and_concurrently_saved_fields() {
        let directory = tempfile::tempdir().unwrap();
        let mut core = clipboard_core::ClipboardCore::open(directory.path()).unwrap();
        let mut preferences = PreferencesDocument::default();
        preferences.appearance.mode = "dark".into();
        preferences.ignore_list.skip_unknown_source = true;
        preferences.ignore_list.window_title_keywords = vec!["Private".into()];
        core.update_preferences(preferences).unwrap();
        let patch = CapturePreferencesPatch {
            ignored_app_identifiers: Some(vec!["KeePass.exe".into()]),
            ..Default::default()
        }
        .into_core()
        .unwrap();
        core.patch_preferences(patch).unwrap();
        let patch = CapturePreferencesPatch {
            retention_days: Some(7),
            retention_forever: Some(false),
            ..Default::default()
        }
        .into_core()
        .unwrap();
        let preferences = core.patch_preferences(patch).unwrap().document;
        assert_eq!(preferences.history.retention_days, 7);
        assert_eq!(
            preferences.ignore_list.ignored_app_identifiers,
            ["KeePass.exe"]
        );
        assert_eq!(preferences.appearance.mode, "dark");
        assert!(preferences.ignore_list.skip_unknown_source);
        assert_eq!(preferences.ignore_list.window_title_keywords, ["Private"]);
        assert!(serde_json::from_str::<CapturePreferencesPatch>(r#"{"maxItems":10}"#).is_err());
        assert!(
            serde_json::from_str::<CapturePreferencesPatch>(r#"{"retentionDays":null}"#).is_err()
        );
        assert!(CapturePreferencesPatch {
            retention_days: Some(0),
            ..Default::default()
        }
        .into_core()
        .is_err());
    }

    #[test]
    fn marker_failure_returns_committed_authority_without_reapplying_the_patch() {
        let directory = tempfile::tempdir().unwrap();
        let mut core = clipboard_core::ClipboardCore::open(directory.path()).unwrap();
        let patch = CapturePreferencesPatch {
            ignored_app_identifiers: Some(vec!["Private.exe".into()]),
            ..Default::default()
        }
        .into_core()
        .unwrap();
        let (saved, warning) = save_capture_patch(&mut core, patch, || {
            Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "injected marker failure",
            ))
        })
        .unwrap();
        assert_eq!(
            saved.document.ignore_list.ignored_app_identifiers,
            ["Private.exe"]
        );
        assert_eq!(
            core.get_preferences()
                .unwrap()
                .ignore_list
                .ignored_app_identifiers,
            ["Private.exe"]
        );
        assert_eq!(warning.unwrap().stage, "legacy_marker");
    }
}
