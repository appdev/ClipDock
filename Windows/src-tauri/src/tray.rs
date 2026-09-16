//! System tray icon and menu. Provides quick access to panel visibility,
//! preferences, diagnostics, and quit. Menu items that need the
//! webview (preferences, diagnostics) emit events the frontend handles; the
//! rest act directly on the backend.

use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{App, Emitter, Manager};

pub const EVENT_OPEN_PREFERENCES: &str = "clipdock://open-preferences";
pub const EVENT_COPY_DIAGNOSTICS: &str = "clipdock://copy-diagnostics";

/// Build the tray icon with its menu during app setup.
pub fn setup_tray(app: &App) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show_panel", "显示面板", true, None::<&str>)?;
    let hide = MenuItem::with_id(app, "hide_panel", "隐藏面板", true, None::<&str>)?;
    let preferences = MenuItem::with_id(app, "preferences", "偏好设置…", true, None::<&str>)?;
    let diagnostics = MenuItem::with_id(
        app,
        "copy_diagnostics",
        "复制剪贴板诊断信息",
        true,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;

    let menu = Menu::with_items(
        app,
        &[
            &show,
            &hide,
            &PredefinedMenuItem::separator(app)?,
            &preferences,
            &diagnostics,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;

    let mut builder = TrayIconBuilder::with_id("clipdock-tray")
        .tooltip("ClipDock")
        .menu(&menu)
        .on_menu_event(|app, event| handle_menu_event(app, event.id.as_ref()));

    if let Some(icon) = app.default_window_icon().cloned() {
        builder = builder.icon(icon);
    }

    builder.build(app)?;
    Ok(())
}

fn handle_menu_event(app: &tauri::AppHandle, id: &str) {
    match id {
        "show_panel" => {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
        "hide_panel" => {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.hide();
            }
        }
        "preferences" => {
            let _ = app.emit(EVENT_OPEN_PREFERENCES, ());
        }
        "copy_diagnostics" => {
            let _ = app.emit(EVENT_COPY_DIAGNOSTICS, ());
        }
        "quit" => {
            app.exit(0);
        }
        _ => {}
    }
}
