use clipboard_core::SourceConfidence;

#[derive(Clone, Debug)]
pub struct ClipboardSource {
    pub process_id: Option<u32>,
    pub path: Option<String>,
    pub name: Option<String>,
    pub confidence: SourceConfidence,
}

impl Default for ClipboardSource {
    fn default() -> Self {
        Self {
            process_id: None,
            path: None,
            name: None,
            confidence: SourceConfidence::Unknown,
        }
    }
}

#[cfg(target_os = "windows")]
pub fn sequence() -> Result<Option<u32>, String> {
    let value = unsafe { windows_sys::Win32::System::DataExchange::GetClipboardSequenceNumber() };
    if value == 0 {
        Err("clipboard sequence unavailable".into())
    } else {
        Ok(Some(value))
    }
}

#[cfg(not(target_os = "windows"))]
pub fn sequence() -> Result<Option<u32>, String> {
    Ok(None)
}

#[cfg(target_os = "windows")]
pub fn source() -> ClipboardSource {
    use windows_sys::Win32::{
        Foundation::CloseHandle,
        System::{
            DataExchange::GetClipboardOwner,
            Threading::{
                OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION,
            },
        },
        UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId},
    };
    unsafe {
        let owner = GetClipboardOwner();
        let window = if owner.is_null() {
            GetForegroundWindow()
        } else {
            owner
        };
        if window.is_null() {
            return ClipboardSource::default();
        }
        let mut pid = 0;
        if GetWindowThreadProcessId(window, &mut pid) == 0 || pid == 0 {
            return ClipboardSource::default();
        }
        // Foreground fallback is context, not proof that this process wrote it.
        let owner_pid = (!owner.is_null()).then_some(pid);
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if process.is_null() {
            return ClipboardSource {
                process_id: owner_pid,
                ..Default::default()
            };
        }
        let mut path = vec![0u16; 32768];
        let mut length = path.len() as u32;
        let ok = QueryFullProcessImageNameW(process, 0, path.as_mut_ptr(), &mut length);
        CloseHandle(process);
        if ok == 0 {
            return ClipboardSource {
                process_id: owner_pid,
                ..Default::default()
            };
        }
        let path = String::from_utf16_lossy(&path[..length as usize]);
        let name = path.rsplit(['\\', '/']).next().map(str::to_string);
        ClipboardSource {
            process_id: owner_pid,
            path: Some(path),
            name,
            confidence: if owner.is_null() {
                SourceConfidence::Low
            } else {
                SourceConfidence::High
            },
        }
    }
}

#[cfg(not(target_os = "windows"))]
pub fn source() -> ClipboardSource {
    ClipboardSource::default()
}

/// BITMAPV5HEADER followed by bottom-up BGRA rows, without a bitmap file header.
#[cfg(any(target_os = "windows", test))]
pub fn dibv5_bytes(width: u32, height: u32, rgba: &[u8]) -> Result<Vec<u8>, String> {
    let stride = (width as usize).checked_mul(4).ok_or("image too large")?;
    let byte_count = stride
        .checked_mul(height as usize)
        .ok_or("image too large")?;
    if width == 0
        || height == 0
        || width > i32::MAX as u32
        || height > i32::MAX as u32
        || byte_count != rgba.len()
        || byte_count > u32::MAX as usize
    {
        return Err("invalid RGBA dimensions".into());
    }
    let mut dib = vec![0u8; 124usize.checked_add(byte_count).ok_or("image too large")?];
    let fields = [
        (0, 124u32),
        (4, width),
        (8, height),
        (16, 3),
        (20, byte_count as u32),
        (40, 0x00ff0000),
        (44, 0x0000ff00),
        (48, 0x000000ff),
        (52, 0xff000000),
        (56, 0x73524742),
        (108, 4),
    ];
    for (offset, value) in fields {
        dib[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    }
    dib[12..14].copy_from_slice(&1u16.to_le_bytes());
    dib[14..16].copy_from_slice(&32u16.to_le_bytes());
    for y in 0..height as usize {
        let src = &rgba[y * stride..(y + 1) * stride];
        let dst = 124 + (height as usize - 1 - y) * stride;
        for (pixel, target) in src
            .chunks_exact(4)
            .zip(dib[dst..dst + stride].chunks_exact_mut(4))
        {
            target.copy_from_slice(&[pixel[2], pixel[1], pixel[0], pixel[3]]);
        }
    }
    Ok(dib)
}

#[cfg(target_os = "windows")]
pub fn write_text(owner: usize, text: &str) -> Result<(), String> {
    let _clipboard = clipboard_win::Clipboard::new_for(owner as clipboard_win::types::HWND)
        .map_err(|e| e.to_string())?;
    clipboard_win::raw::set_string(text).map_err(|e| e.to_string())
}

#[cfg(target_os = "windows")]
pub fn write_image(owner: usize, image: &image::RgbaImage) -> Result<(), String> {
    use std::io::Cursor;
    let dib = dibv5_bytes(image.width(), image.height(), image.as_raw())?;
    let mut png = Cursor::new(Vec::new());
    image
        .write_to(&mut png, image::ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    let png_format =
        clipboard_win::raw::register_format("PNG").ok_or("PNG clipboard format unavailable")?;
    let _clipboard = clipboard_win::Clipboard::new_for(owner as clipboard_win::types::HWND)
        .map_err(|e| e.to_string())?;
    clipboard_win::raw::empty().map_err(|e| e.to_string())?;
    clipboard_win::raw::set_without_clear(png_format.get(), png.get_ref())
        .map_err(|e| e.to_string())?;
    clipboard_win::raw::set_without_clear(17, &dib).map_err(|e| e.to_string())
}

#[cfg(not(target_os = "windows"))]
pub fn write_text(_owner: usize, text: &str) -> Result<(), String> {
    arboard::Clipboard::new()
        .and_then(|mut c| c.set_text(text.to_string()))
        .map_err(|e| e.to_string())
}

#[cfg(not(target_os = "windows"))]
pub fn write_image(_owner: usize, image: &image::RgbaImage) -> Result<(), String> {
    arboard::Clipboard::new()
        .and_then(|mut c| {
            c.set_image(arboard::ImageData {
                width: image.width() as usize,
                height: image.height() as usize,
                bytes: std::borrow::Cow::Borrowed(image.as_raw()),
            })
        })
        .map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dib_has_v5_header_masks_and_bottom_up_bgra_pixels() {
        let dib = dibv5_bytes(1, 2, &[255, 0, 0, 128, 0, 255, 0, 255]).unwrap();
        assert_eq!(dib.len(), 132);
        assert_eq!(&dib[..4], &124u32.to_le_bytes());
        assert_eq!(&dib[52..56], &0xff000000u32.to_le_bytes());
        assert_eq!(&dib[124..], &[0, 255, 0, 255, 0, 0, 255, 128]);
        assert!(dibv5_bytes(2, 2, &[0; 4]).is_err());
        assert!(dibv5_bytes(u32::MAX, u32::MAX, &[]).is_err());
    }
}
