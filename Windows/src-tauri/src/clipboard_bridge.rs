use image::{ImageReader, RgbaImage};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{borrow::Cow, fs, path::PathBuf};
use tauri::{AppHandle, Manager};

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardSnapshot {
    change_key: String,
    kind: ClipboardSnapshotKind,
    text: Option<String>,
    image_path: Option<String>,
    image_width: Option<u32>,
    image_height: Option<u32>,
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
    }))
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
