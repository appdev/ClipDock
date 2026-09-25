use clipboard_core::{
    CaptureImageRequest, CaptureResult, CaptureTextRequest, ClipboardItemType, ItemManagementResult,
    ItemPage, ItemQuery, PageRequest, PinboardPage, PinboardSummary, PreferencesDocument,
    SourceConfidence,
};
use serde::Serialize;
use tauri::{Emitter, Manager, State};
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

/// Basic diagnostics about the storage engine: database location, applied
/// schema version, and active item count.
#[tauri::command]
pub fn core_info(state: State<'_, CoreState>) -> Result<CoreInfoResult, String> {
    state.with_core(|core| {
        let info = core.info().map_err(|error| error.to_string())?;
        Ok(CoreInfoResult {
            database_path: info.database_path,
            schema_version: info.schema_version,
            item_count: info.item_count,
        })
    })
}

/// Page through stored clipboard items, optionally filtered by type, source
/// app, pinboard, or full-text search.
#[tauri::command]
pub fn list_clipboard_items(
    state: State<'_, CoreState>,
    item_type: Option<String>,
    source_app_id: Option<String>,
    pinboard_id: Option<String>,
    search_text: Option<String>,
    limit: Option<i64>,
    offset: Option<i64>,
) -> Result<ItemPage, String> {
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

    state.with_core(|core| core.list_items(query, page).map_err(|error| error.to_string()))
}

/// List all custom pinboards plus their item counts.
#[tauri::command]
pub fn list_pinboards(state: State<'_, CoreState>) -> Result<PinboardPage, String> {
    state.with_core(|core| core.list_pinboards().map_err(|error| error.to_string()))
}

#[tauri::command]
pub fn create_pinboard(
    state: State<'_, CoreState>,
    title: String,
    color_code: Option<i64>,
) -> Result<PinboardSummary, String> {
    state.with_core(|core| {
        core.create_pinboard(title, color_code)
            .map_err(|error| error.to_string())
    })
}

#[tauri::command]
pub fn rename_pinboard(
    state: State<'_, CoreState>,
    pinboard_id: String,
    title: String,
) -> Result<PinboardSummary, String> {
    state.with_core(|core| {
        core.rename_pinboard(pinboard_id, title)
            .map_err(|error| error.to_string())
    })
}

#[tauri::command]
pub fn update_pinboard_color(
    state: State<'_, CoreState>,
    pinboard_id: String,
    color_code: i64,
) -> Result<PinboardSummary, String> {
    state.with_core(|core| {
        core.update_pinboard_color(pinboard_id, color_code)
            .map_err(|error| error.to_string())
    })
}

#[tauri::command]
pub fn delete_pinboard(
    state: State<'_, CoreState>,
    pinboard_id: String,
) -> Result<ItemManagementResult, String> {
    state.with_core(|core| {
        core.delete_pinboard(pinboard_id)
            .map_err(|error| error.to_string())
    })
}

/// Add or remove an item from a pinboard.
#[tauri::command]
pub fn set_item_pinboard_membership(
    state: State<'_, CoreState>,
    item_id: String,
    pinboard_id: String,
    is_member: bool,
) -> Result<ItemManagementResult, String> {
    state.with_core(|core| {
        core.set_item_pinboard_membership(item_id, pinboard_id, is_member)
            .map_err(|error| error.to_string())
    })
}

/// Update the card label without changing its clipboard payload.
#[tauri::command]
pub fn rename_clipboard_item(
    state: State<'_, CoreState>,
    item_id: String,
    title: String,
) -> Result<ItemManagementResult, String> {
    state.with_core(|core| {
        core.rename_item(item_id, title)
            .map_err(|error| error.to_string())
    })
}

/// Soft-delete a single clipboard item.
#[tauri::command]
pub fn delete_clipboard_item(
    state: State<'_, CoreState>,
    item_id: String,
) -> Result<ItemManagementResult, String> {
    state.with_core(|core| core.delete_item(item_id).map_err(|error| error.to_string()))
}

/// Bump an item's copy count and recency when the user re-copies it.
#[tauri::command]
pub fn record_clipboard_item_copied(
    state: State<'_, CoreState>,
    item_id: String,
) -> Result<ItemManagementResult, String> {
    state.with_core(|core| {
        core.record_item_copied(item_id)
            .map_err(|error| error.to_string())
    })
}

/// Clear items matching an optional filter (defaults to clearing unpinned
/// history when no filter is supplied).
#[tauri::command]
pub fn clear_clipboard_items(
    state: State<'_, CoreState>,
    item_type: Option<String>,
    source_app_id: Option<String>,
    pinboard_id: Option<String>,
    search_text: Option<String>,
) -> Result<ItemManagementResult, String> {
    let query = ItemQuery {
        item_type: item_type.map(|value| ClipboardItemType::from_storage(&value)),
        source_app_id,
        pinboard_id,
        search_text,
    };
    state.with_core(|core| core.clear_items(query).map_err(|error| error.to_string()))
}

/// Persist a captured text (or detected-link) clipboard entry.
#[tauri::command]
pub fn capture_clipboard_text(
    state: State<'_, CoreState>,
    text: String,
    source_app_name: Option<String>,
    source_bundle_id: Option<String>,
    self_write_token: Option<String>,
) -> Result<CaptureResult, String> {
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
    state.with_core(|core| core.capture_text(request).map_err(|error| error.to_string()))
}

/// Persist a captured image clipboard entry. `payload_relative_path` is
/// relative to the ClipDock data root (see `CoreState::root_dir`).
#[tauri::command]
pub fn capture_clipboard_image(
    state: State<'_, CoreState>,
    payload_relative_path: String,
    width: i64,
    height: i64,
    byte_count: i64,
    mime_type: Option<String>,
    source_app_name: Option<String>,
    self_write_token: Option<String>,
) -> Result<CaptureResult, String> {
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
    state.with_core(|core| core.capture_image(request).map_err(|error| error.to_string()))
}

/// Read the full preferences document.
#[tauri::command]
pub fn get_preferences(state: State<'_, CoreState>) -> Result<PreferencesDocument, String> {
    state.with_core(|core| core.get_preferences().map_err(|error| error.to_string()))
}

/// Replace the preferences document, returning the normalized result.
#[tauri::command]
pub fn update_preferences(
    state: State<'_, CoreState>,
    preferences: PreferencesDocument,
) -> Result<PreferencesDocument, String> {
    state.with_core(|core| {
        core.update_preferences(preferences)
            .map_err(|error| error.to_string())
    })
}
