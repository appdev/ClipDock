mod clipboard_bridge;
mod native_assets;

use serde::Serialize;
use std::{thread, time::Duration};
use tauri::{Emitter, Manager, PhysicalPosition, PhysicalSize};

#[cfg(target_os = "macos")]
use objc2_app_kit::{NSWindow, NSWindowCollectionBehavior};
#[cfg(target_os = "macos")]
use objc2_core_graphics::{CGWindowLevelForKey, CGWindowLevelKey};

const DEFAULT_PANEL_HEIGHT: f64 = 320.0;
const MINIMUM_PANEL_HEIGHT: f64 = 260.0;
const MAXIMUM_HEIGHT_RATIO: f64 = 0.3;
const OUTER_MARGIN: f64 = 10.0;
const CLIPBOARD_CHANGED_EVENT: &str = "clipboard-changed";

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
struct PanelFrame {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

fn clamped_panel_height(height: f64, screen_height: f64) -> f64 {
    let maximum = MINIMUM_PANEL_HEIGHT.max(screen_height * MAXIMUM_HEIGHT_RATIO);
    height.max(MINIMUM_PANEL_HEIGHT).min(maximum)
}

fn bottom_panel_frame(screen: PanelFrame, preferred_height: f64) -> PanelFrame {
    let height = clamped_panel_height(preferred_height, screen.height);
    PanelFrame {
        x: screen.x + OUTER_MARGIN,
        y: screen.y + OUTER_MARGIN,
        width: (screen.width - OUTER_MARGIN * 2.0).max(0.0),
        height,
    }
}

#[tauri::command]
fn panel_frame_for_screen(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    preferred_height: Option<f64>,
) -> PanelFrame {
    bottom_panel_frame(
        PanelFrame {
            x,
            y,
            width,
            height,
        },
        preferred_height.unwrap_or(DEFAULT_PANEL_HEIGHT),
    )
}

fn configure_initial_panel_window(app: &tauri::AppHandle) -> tauri::Result<()> {
    let Some(window) = app.get_webview_window("main") else {
        return Ok(());
    };

    window.set_decorations(false)?;
    window.set_skip_taskbar(true)?;
    configure_platform_always_on_top(&window)?;

    let monitor = window
        .current_monitor()?
        .or(window.primary_monitor()?)
        .or_else(|| {
            window
                .available_monitors()
                .ok()
                .and_then(|mut monitors| monitors.pop())
        });

    let Some(monitor) = monitor else {
        return Ok(());
    };

    let scale_factor = monitor.scale_factor();
    let monitor_size = monitor.size();
    let monitor_position = monitor.position();
    let logical_screen = PanelFrame {
        x: f64::from(monitor_position.x) / scale_factor,
        y: f64::from(monitor_position.y) / scale_factor,
        width: f64::from(monitor_size.width) / scale_factor,
        height: f64::from(monitor_size.height) / scale_factor,
    };
    let logical_frame = bottom_panel_frame(logical_screen, DEFAULT_PANEL_HEIGHT);
    let physical_position =
        bottom_aligned_physical_position(logical_screen, logical_frame, OUTER_MARGIN, scale_factor);
    let physical_size = PhysicalSize::new(
        (logical_frame.width * scale_factor).round() as u32,
        (logical_frame.height * scale_factor).round() as u32,
    );

    window.set_size(physical_size)?;
    window.set_position(physical_position)?;
    window.show()?;
    window.set_focus()?;
    elevate_panel_above_dock(&window)?;
    Ok(())
}

fn start_clipboard_event_monitor(app: tauri::AppHandle) {
    thread::spawn(move || {
        let mut last_change_key: Option<String> = None;
        loop {
            match clipboard_bridge::read_clipboard_snapshot(app.clone()) {
                Ok(Some(snapshot)) => {
                    if last_change_key.as_deref() != Some(snapshot.change_key()) {
                        last_change_key = Some(snapshot.change_key().to_string());
                        emit_clipboard_snapshot(&app, snapshot);
                    }
                }
                Ok(None) => {
                    last_change_key = None;
                }
                Err(_) => {}
            }
            thread::sleep(Duration::from_millis(800));
        }
    });
}

fn emit_clipboard_snapshot(app: &tauri::AppHandle, snapshot: clipboard_bridge::ClipboardSnapshot) {
    let Some(window) = app.get_webview_window("main") else {
        return;
    };
    let _ = window.emit(CLIPBOARD_CHANGED_EVENT, snapshot.clone());
    let Ok(payload) = serde_json::to_string(&snapshot) else {
        return;
    };
    let script = format!(
        "window.__clipdockHandleClipboardSnapshot?.({payload});\
         window.dispatchEvent(new CustomEvent('clipdock-native-clipboard-changed', {{ detail: {payload} }}));"
    );
    let _ = window.eval(&script);
}

#[cfg(target_os = "macos")]
fn configure_platform_always_on_top(_window: &tauri::WebviewWindow) -> tauri::Result<()> {
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn configure_platform_always_on_top(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    window.set_always_on_top(true)
}

fn bottom_aligned_physical_position(
    logical_screen: PanelFrame,
    logical_frame: PanelFrame,
    bottom_margin: f64,
    scale_factor: f64,
) -> PhysicalPosition<i32> {
    PhysicalPosition::new(
        (logical_frame.x * scale_factor).round() as i32,
        ((logical_screen.y + logical_screen.height - bottom_margin - logical_frame.height)
            * scale_factor)
            .round() as i32,
    )
}

#[cfg(target_os = "macos")]
fn elevate_panel_above_dock(window: &tauri::WebviewWindow) -> tauri::Result<()> {
    let ns_window = window.ns_window()?;
    let dock_level = CGWindowLevelForKey(CGWindowLevelKey::DockWindowLevelKey);
    let top_panel_level = dock_level as isize + 1;
    unsafe {
        let ns_window = &*(ns_window.cast::<NSWindow>());
        ns_window.setCollectionBehavior(
            NSWindowCollectionBehavior::CanJoinAllSpaces
                | NSWindowCollectionBehavior::FullScreenAuxiliary
                | NSWindowCollectionBehavior::IgnoresCycle
                | NSWindowCollectionBehavior::Transient,
        );
        ns_window.setCanHide(false);
        ns_window.setHidesOnDeactivate(false);
        ns_window.setLevel(top_panel_level);
        ns_window.orderFrontRegardless();
    }
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn elevate_panel_above_dock(_window: &tauri::WebviewWindow) -> tauri::Result<()> {
    Ok(())
}

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            panel_frame_for_screen,
            clipboard_bridge::read_clipboard_snapshot,
            clipboard_bridge::write_clipboard_image,
            clipboard_bridge::write_clipboard_text,
            native_assets::resolve_panel_native_assets
        ])
        .setup(|app| {
            configure_initial_panel_window(app.handle())?;
            start_clipboard_event_monitor(app.handle().clone());
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("failed to run ClipDock panel app");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bottom_panel_frame_applies_macos_margins_and_height_clamp() {
        let frame = bottom_panel_frame(
            PanelFrame {
                x: -1440.0,
                y: -40.0,
                width: 1440.0,
                height: 900.0,
            },
            999.0,
        );

        assert_eq!(frame.x, -1430.0);
        assert_eq!(frame.y, -30.0);
        assert_eq!(frame.width, 1420.0);
        assert_eq!(frame.height, 270.0);
    }

    #[test]
    fn panel_height_never_falls_below_minimum() {
        assert_eq!(clamped_panel_height(120.0, 400.0), 260.0);
        assert_eq!(clamped_panel_height(600.0, 400.0), 260.0);
    }

    #[test]
    fn bottom_position_uses_full_screen_frame_to_cover_dock_area() {
        let position = bottom_aligned_physical_position(
            PanelFrame {
                x: 0.0,
                y: 0.0,
                width: 1920.0,
                height: 1080.0,
            },
            PanelFrame {
                x: 10.0,
                y: 10.0,
                width: 1900.0,
                height: 320.0,
            },
            OUTER_MARGIN,
            1.0,
        );

        assert_eq!(position.x, 10);
        assert_eq!(position.y, 750);
    }
}
