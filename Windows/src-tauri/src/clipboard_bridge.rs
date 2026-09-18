use clipboard_core::{
    CaptureImageRequest, CaptureTextRequest, ClipboardCore, ClipboardItemSummary, ItemQuery,
    PageRequest, SourceConfidence,
};
use image::{ImageReader, RgbaImage};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{borrow::Cow, fs, path::PathBuf};
use tauri::{AppHandle, Manager};

use crate::core_state::CoreState;

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardSnapshot {
    change_key: String,
    kind: ClipboardSnapshotKind,
    text: Option<String>,
    image_path: Option<String>,
    image_width: Option<u32>,
    image_height: Option<u32>,
    stored_item: Option<ClipboardItemSummary>,
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
enum ClipboardSnapshotKind {
    Text,
    Image,
}

impl ClipboardSnapshot {
    pub fn change_key(&self) -> &str {
        &self.change_key
    }
}

#[tauri::command]
pub fn read_clipboard_snapshot(app: AppHandle) -> Result<Option<ClipboardSnapshot>, String> {
    let mut clipboard = arboard::Clipboard::new().map_err(|error| error.to_string())?;

    if let Ok(text) = clipboard.get_text() {
        if !text.is_empty() {
            let change_key = clipboard_text_change_key(&text);
            return Ok(Some(ClipboardSnapshot {
                change_key,
                kind: ClipboardSnapshotKind::Text,
                text: Some(text),
                image_path: None,
                image_width: None,
                image_height: None,
                stored_item: None,
            }));
        }
    }

    let Ok(image) = clipboard.get_image() else {
        return Ok(None);
    };

    let width = image.width as u32;
    let height = image.height as u32;
    let bytes = image.bytes.into_owned();
    let change_key = clipboard_image_change_key(width, height, &bytes);
    let image_path = save_clipboard_image(&app, &change_key, width, height, bytes)?;

    Ok(Some(ClipboardSnapshot {
        change_key,
        kind: ClipboardSnapshotKind::Image,
        text: None,
        image_path: Some(image_path.display().to_string()),
        image_width: Some(width),
        image_height: Some(height),
        stored_item: None,
    }))
}

/// Persist a freshly detected clipboard snapshot into the shared
/// `clipboard_core` database so history survives restarts.
///
/// Best-effort: failures are logged but never interrupt the capture pipeline,
/// since the live UI event is emitted regardless. Re-copying existing content
/// is handled by the core (it bumps `copy_count` rather than duplicating).
pub fn persist_snapshot(app: &AppHandle, snapshot: &mut ClipboardSnapshot) {
    let Some(state) = app.try_state::<CoreState>() else {
        return;
    };

    let result = match snapshot.kind {
        ClipboardSnapshotKind::Text => persist_text_snapshot(&state, snapshot),
        ClipboardSnapshotKind::Image => persist_image_snapshot(&state, snapshot),
    };

    match result {
        Ok(item) => snapshot.stored_item = item,
        Err(message) => eprintln!("clipboard persistence failed: {message}"),
    }
}

fn persist_text_snapshot(
    state: &CoreState,
    snapshot: &ClipboardSnapshot,
) -> Result<Option<ClipboardItemSummary>, String> {
    let Some(text) = snapshot.text.clone() else {
        return Ok(None);
    };
    if text.is_empty() {
        return Ok(None);
    }

    let request = CaptureTextRequest {
        text,
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
    };

    state.with_core(|core| {
        let captured = core
            .capture_text(request)
            .map_err(|error| error.to_string())?;
        captured_item_summary(core, &captured.item_id)
    })
}

fn persist_image_snapshot(
    state: &CoreState,
    snapshot: &ClipboardSnapshot,
) -> Result<Option<ClipboardItemSummary>, String> {
    let Some(source_path) = snapshot.image_path.as_deref() else {
        return Ok(None);
    };

    // `capture_image` hashes the payload file relative to the core data root,
    // so copy the captured PNG into `<root>/assets/` before recording it.
    let relative_path = format!("assets/clipboard-image-{}.png", snapshot.change_key);
    let destination = state.root_dir().join(&relative_path);

    if !destination.exists() {
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent).map_err(|error| error.to_string())?;
        }
        fs::copy(source_path, &destination).map_err(|error| error.to_string())?;
    }

    let byte_count = fs::metadata(&destination)
        .map(|metadata| metadata.len() as i64)
        .unwrap_or(0);

    let request = CaptureImageRequest {
        payload_relative_path: relative_path,
        preview_relative_path: None,
        mime_type: Some("image/png".to_string()),
        width: snapshot.image_width.unwrap_or(0) as i64,
        height: snapshot.image_height.unwrap_or(0) as i64,
        byte_count,
        source_bundle_id: None,
        source_app_name: None,
        source_bundle_path: None,
        source_icon_relative_path: None,
        source_confidence: SourceConfidence::Unknown,
        pasteboard_change_count: 0,
        self_write_token: None,
    };

    state.with_core(|core| {
        let captured = core
            .capture_image(request)
            .map_err(|error| error.to_string())?;
        captured_item_summary(core, &captured.item_id)
    })
}

// Captures sort first by copy time. Keep paging for timestamp ties instead of
// guessing an id from the clipboard hash; recaptures must retain custom titles.
fn captured_item_summary(
    core: &ClipboardCore,
    id: &str,
) -> Result<Option<ClipboardItemSummary>, String> {
    let mut offset = 0;
    loop {
        let page = core
            .list_items(ItemQuery::default(), PageRequest { limit: 100, offset })
            .map_err(|error| error.to_string())?;
        if let Some(item) = page.items.into_iter().find(|item| item.id == id) {
            return Ok(Some(item));
        }
        if !page.has_more {
            return Ok(None);
        }
        offset += 100;
    }
}

#[tauri::command]
pub fn write_clipboard_text(text: String) -> Result<String, String> {
    let change_key = clipboard_text_change_key(&text);
    let mut clipboard = arboard::Clipboard::new().map_err(|error| error.to_string())?;
    clipboard
        .set_text(text)
        .map_err(|error| error.to_string())?;
    Ok(change_key)
}

#[tauri::command]
pub fn write_clipboard_image(image_path: String) -> Result<String, String> {
    let rgba = ImageReader::open(&image_path)
        .map_err(|error| error.to_string())?
        .decode()
        .map_err(|error| error.to_string())?
        .to_rgba8();
    let width = rgba.width();
    let height = rgba.height();
    let bytes = rgba.into_raw();
    let change_key = clipboard_image_change_key(width, height, &bytes);
    let mut clipboard = arboard::Clipboard::new().map_err(|error| error.to_string())?;
    clipboard
        .set_image(arboard::ImageData {
            width: width as usize,
            height: height as usize,
            bytes: Cow::Owned(bytes),
        })
        .map_err(|error| error.to_string())?;
    Ok(change_key)
}

fn save_clipboard_image(
    app: &AppHandle,
    change_key: &str,
    width: u32,
    height: u32,
    bytes: Vec<u8>,
) -> Result<PathBuf, String> {
    let image_dir = app
        .path()
        .app_local_data_dir()
        .map_err(|error| error.to_string())?
        .join("native-assets")
        .join("clipboard-images");
    fs::create_dir_all(&image_dir).map_err(|error| error.to_string())?;

    let output = image_dir.join(format!("clipboard-image-{change_key}.png"));
    if output.exists() {
        return Ok(output);
    }

    let Some(buffer) = RgbaImage::from_raw(width, height, bytes) else {
        return Err(format!(
            "clipboard image has invalid {width}x{height} RGBA buffer"
        ));
    };
    buffer.save(&output).map_err(|error| error.to_string())?;
    Ok(output)
}

fn clipboard_text_change_key(text: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"text:");
    hasher.update(text.as_bytes());
    hex_digest(&hasher.finalize())
}

fn clipboard_image_change_key(width: u32, height: u32, bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(b"image:");
    hasher.update(width.to_be_bytes());
    hasher.update(height.to_be_bytes());
    hasher.update(bytes);
    hex_digest(&hasher.finalize())
}

fn hex_digest(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(HEX[(byte >> 4) as usize] as char);
        output.push(HEX[(byte & 0x0f) as usize] as char);
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captured_summary_preserves_durable_identity_and_custom_title() {
        let dir = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(dir.path()).unwrap();
        let capture = core
            .capture_text(CaptureTextRequest {
                text: "synthetic clipboard payload".into(),
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
            })
            .unwrap();
        core.rename_item(&capture.item_id, "保留名称").unwrap();
        let item = captured_item_summary(&core, &capture.item_id)
            .unwrap()
            .unwrap();
        assert_eq!(item.id, capture.item_id);
        assert_eq!(item.custom_title.as_deref(), Some("保留名称"));
        assert_eq!(
            item.primary_text.as_deref(),
            Some("synthetic clipboard payload")
        );
        assert!(captured_item_summary(&core, "missing-item")
            .unwrap()
            .is_none());
    }

    #[test]
    fn text_change_key_is_stable_and_content_specific() {
        assert_eq!(
            clipboard_text_change_key("ClipDock"),
            clipboard_text_change_key("ClipDock")
        );
        assert_ne!(
            clipboard_text_change_key("ClipDock"),
            clipboard_text_change_key("ClipDock ")
        );
    }

    #[test]
    fn image_change_key_includes_dimensions() {
        let bytes = vec![255, 0, 0, 255];

        assert_ne!(
            clipboard_image_change_key(1, 1, &bytes),
            clipboard_image_change_key(2, 1, &bytes)
        );
    }
}
