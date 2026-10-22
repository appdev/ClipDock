use crate::{
    clipboard_platform::{self as platform, ClipboardSource},
    core_state::CoreState,
};
use clipboard_core::copy_plan::{
    plan_copy, CopyAssetKind, CopyAssetRef, CopyCapabilities, CopyComposition, CopyInputItem,
    CopyMode, CopyNativeFileFacts, CopyPlan, CopyPlanRequest, CopyRepresentation,
};
use clipboard_core::{
    evaluate_capture_policy, normalize_windows_capture_key, windows_capture_source_keys,
    CaptureImageRequest, CapturePolicyInput, CapturePolicyProfile, CaptureTextRequest,
    ClipboardCore, ClipboardItemSummary, ClipboardItemType, PreferencesDocument,
};
use image::{ImageReader, RgbaImage};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::{fs, sync::Mutex, thread, time::Duration};
use tauri::{AppHandle, Emitter, Manager};

#[derive(Default)]
pub struct ClipboardMonitorState(Mutex<MonitorState>);

#[derive(Default)]
pub struct ClipboardCopyIntentState(Mutex<CopyIntent>);

#[derive(Default)]
struct CopyIntent {
    session_id: u64,
    intent_id: u64,
}

impl ClipboardCopyIntentState {
    fn new_session(&self) -> Result<u64, String> {
        let mut current = self
            .0
            .lock()
            .map_err(|_| "clipboard copy intent lock poisoned")?;
        current.session_id = current
            .session_id
            .checked_add(1)
            .ok_or("clipboard copy session exhausted")?;
        current.intent_id = 0;
        Ok(current.session_id)
    }

    fn accept(&self, session_id: u64, intent_id: u64) -> Result<bool, String> {
        let mut current = self
            .0
            .lock()
            .map_err(|_| "clipboard copy intent lock poisoned")?;
        if session_id != current.session_id || intent_id <= current.intent_id {
            return Ok(false);
        }
        current.intent_id = intent_id;
        Ok(true)
    }

    fn write_if_current<T>(
        &self,
        session_id: u64,
        intent_id: u64,
        write: impl FnOnce() -> Result<T, String>,
    ) -> Result<Option<T>, String> {
        // Hold the intent gate through the native write: a new intent either
        // supersedes preparation, or starts after this write has completed.
        let current = self
            .0
            .lock()
            .map_err(|_| "clipboard copy intent lock poisoned")?;
        if current.session_id != session_id || current.intent_id != intent_id {
            return Ok(None);
        }
        write().map(Some)
    }
}

#[derive(Debug, Serialize)]
pub struct ClipboardCopyResult {
    status: &'static str,
    record_warning: Option<String>,
}

impl ClipboardCopyResult {
    fn superseded() -> Self {
        Self {
            status: "superseded",
            record_warning: None,
        }
    }
}

fn commit_copy<Ready>(
    gate: &ClipboardCopyIntentState,
    session_id: u64,
    intent_id: u64,
    prepare: impl FnOnce() -> Result<Ready, String>,
    write: impl FnOnce(&mut Ready) -> Result<(), String>,
    record: impl FnOnce() -> Result<(), String>,
) -> Result<ClipboardCopyResult, String> {
    // Waiting for the monitor must leave the intent gate available to cancellation.
    // Release preparation guards as well as the intent gate before recording in DB.
    let written = {
        let mut ready = prepare()?;
        gate.write_if_current(session_id, intent_id, || write(&mut ready))?
    };
    if written.is_none() {
        return Ok(ClipboardCopyResult::superseded());
    }
    Ok(ClipboardCopyResult {
        status: "written",
        record_warning: record().err(),
    })
}

enum StoredCopyPayload {
    Text(String),
    Image(std::path::PathBuf),
}

struct StoredCopyPlan {
    payload: StoredCopyPayload,
    included_ids: Vec<String>,
}

fn stored_copy_plan(core: &ClipboardCore, item_id: &str) -> Result<StoredCopyPlan, String> {
    let item = core
        .get_item(item_id)
        .map_err(|error| error.to_string())?
        .ok_or("clipboard history item no longer exists")?;
    let image_path = if item.item_type == ClipboardItemType::Image {
        core.image_payload_path(item_id)
            .map_err(|error| error.to_string())?
    } else {
        None
    };
    plan_stored_copy(item, image_path)
}

fn plan_stored_copy(
    item: ClipboardItemSummary,
    image_path: Option<std::path::PathBuf>,
) -> Result<StoredCopyPlan, String> {
    // Only this native hydration step can assign a managed path. The pure
    // planner returns the opaque key; no frontend path becomes authoritative.
    let payload_key = "hydrated_image_payload";
    let request = CopyPlanRequest {
        ordered_ids: vec![item.id.clone()],
        mode: CopyMode::Original,
        capabilities: CopyCapabilities::WindowsV1,
        file_facts: vec![CopyNativeFileFacts {
            item_id: item.id.clone(),
            content_hash: item.content_hash.clone(),
            payload_asset: image_path.as_ref().map(|_| CopyAssetRef {
                kind: CopyAssetKind::ManagedAsset,
                key: payload_key.into(),
            }),
            file_candidates: vec![],
        }],
        items: vec![CopyInputItem {
            item_id: item.id,
            content_hash: item.content_hash,
            item_type: item.item_type,
            primary_text: item.primary_text,
            summary: item.summary,
            payload_state: item.payload_state,
            canonical_url: item.link_metadata.map(|metadata| metadata.canonical_url),
            first_file_path: item.file_items.first().map(|file| file.path.clone()),
        }],
    };
    match plan_copy(request).map_err(|error| error.to_string())? {
        CopyPlan::Ready {
            composition: CopyComposition::Single,
            mut items,
            included_ids,
            ..
        } if items.len() == 1 && items[0].representations.len() == 1 => {
            let payload = match items.remove(0).representations.remove(0) {
                CopyRepresentation::Text { text } => StoredCopyPayload::Text(text),
                CopyRepresentation::Image { asset }
                    if asset.kind == CopyAssetKind::ManagedAsset && asset.key == payload_key =>
                {
                    StoredCopyPayload::Image(image_path.ok_or("image payload unavailable")?)
                }
                _ => return Err("unsupported Windows clipboard representation".into()),
            };
            Ok(StoredCopyPlan {
                payload,
                included_ids,
            })
        }
        CopyPlan::Unsupported { reason, .. } => Err(reason),
        _ => Err("unsupported Windows clipboard composition".into()),
    }
}

#[tauri::command]
pub fn begin_clipboard_copy_session(app: AppHandle) -> Result<u64, String> {
    app.state::<ClipboardCopyIntentState>().new_session()
}

#[tauri::command]
pub fn cancel_clipboard_copy(
    app: AppHandle,
    session_id: u64,
    intent_id: u64,
) -> Result<(), String> {
    app.state::<ClipboardCopyIntentState>()
        .accept(session_id, intent_id)
        .map(|_| ())
}

#[tauri::command]
pub async fn write_clipboard_item(
    app: AppHandle,
    item_id: String,
    session_id: u64,
    intent_id: u64,
) -> Result<ClipboardCopyResult, String> {
    write_intended_clipboard(app, CopySource::StoredItem(item_id), session_id, intent_id).await
}

#[tauri::command]
pub async fn write_clipboard_text_intent(
    app: AppHandle,
    text: String,
    session_id: u64,
    intent_id: u64,
) -> Result<ClipboardCopyResult, String> {
    write_intended_clipboard(app, CopySource::Text(text), session_id, intent_id).await
}

enum CopySource {
    StoredItem(String),
    Text(String),
}

async fn write_intended_clipboard(
    app: AppHandle,
    source: CopySource,
    session_id: u64,
    intent_id: u64,
) -> Result<ClipboardCopyResult, String> {
    if !app
        .state::<ClipboardCopyIntentState>()
        .accept(session_id, intent_id)?
    {
        return Ok(ClipboardCopyResult::superseded());
    }
    let owner = owner_handle(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let StoredCopyPlan {
            payload,
            included_ids,
        } = match source {
            CopySource::StoredItem(item_id) => app
                .state::<CoreState>()
                .with_core(|core| stored_copy_plan(core, &item_id))?,
            CopySource::Text(text) => StoredCopyPlan {
                payload: StoredCopyPayload::Text(text),
                included_ids: vec![],
            },
        };
        // Decode outside the database and intent locks.
        let payload = match payload {
            StoredCopyPayload::Text(text) => Payload::Text(text),
            StoredCopyPayload::Image(path) => Payload::Image(decode_image(&path)?),
        };
        let change_key = payload.change_key();
        let monitor = app.state::<ClipboardMonitorState>();
        commit_copy(
            &app.state::<ClipboardCopyIntentState>(),
            session_id,
            intent_id,
            || {
                monitor
                    .0
                    .lock()
                    .map_err(|_| "clipboard monitor lock poisoned".to_string())
            },
            |monitor| {
                match &payload {
                    Payload::Text(text) => platform::write_text(owner, text)?,
                    Payload::Image(image) => platform::write_image(owner, image)?,
                    Payload::Empty => return Err("empty copy payload".into()),
                }
                monitor.fallback_self_write = Some(change_key);
                Ok(())
            },
            || {
                let warnings: Vec<_> = included_ids
                    .into_iter()
                    .filter_map(|id| record_copy(&app, Some(id)).err())
                    .collect();
                if warnings.is_empty() {
                    Ok(())
                } else {
                    Err(warnings.join("; "))
                }
            },
        )
    })
    .await
    .map_err(|error| error.to_string())?
}

#[derive(Default)]
struct MonitorState {
    completed_sequence: Option<u32>,
    fallback_key: Option<String>,
    fallback_self_write: Option<String>,
}

impl MonitorState {
    fn unchanged(&self, sequence: Option<u32>) -> bool {
        sequence.is_some() && sequence == self.completed_sequence
    }

    fn read_stable<T>(
        &self,
        before: Option<u32>,
        read: impl FnOnce() -> Result<T, String>,
        mut sequence: impl FnMut() -> Result<Option<u32>, String>,
    ) -> Result<Option<T>, String> {
        if self.unchanged(before) || before != sequence()? {
            return Ok(None);
        }
        let payload = read()?;
        if before != sequence()? {
            return Ok(None);
        }
        Ok(Some(payload))
    }

    fn read_preflighted<T>(
        &mut self,
        before: Option<u32>,
        source: &ClipboardSource,
        preferences: &PreferencesDocument,
        read: impl FnOnce() -> Result<T, String>,
        mut sequence: impl FnMut() -> Result<Option<u32>, String>,
    ) -> Result<Option<T>, String> {
        if self.unchanged(before) {
            return Ok(None);
        }
        if source.process_id == Some(std::process::id()) || ignores_source(source, preferences)? {
            if before == sequence()? {
                self.completed_sequence = before;
            }
            return Ok(None);
        }
        // The source and preferences can take time to resolve. Recheck before
        // touching payload as well as afterward; changed events remain retryable.
        self.read_stable(before, read, sequence)
    }
}

enum Payload {
    Text(String),
    Image(RgbaImage),
    Empty,
}

impl Payload {
    fn change_key(&self) -> String {
        let mut hash = Sha256::new();
        match self {
            Self::Text(text) => {
                hash.update(b"text:");
                hash.update(text.as_bytes());
            }
            Self::Image(image) => {
                hash.update(b"image:");
                hash.update(image.width().to_be_bytes());
                hash.update(image.height().to_be_bytes());
                hash.update(image.as_raw());
            }
            Self::Empty => hash.update(b"empty"),
        }
        format!("{:x}", hash.finalize())
    }
}

fn read_payload() -> Result<Payload, String> {
    let mut clipboard = arboard::Clipboard::new().map_err(|e| e.to_string())?;
    match clipboard.get_text() {
        Ok(text) if !text.trim().is_empty() => return Ok(Payload::Text(text)),
        Ok(_) | Err(arboard::Error::ContentNotAvailable) => {}
        Err(error) => return Err(error.to_string()),
    }
    match clipboard.get_image() {
        Ok(image) => {
            let width = u32::try_from(image.width).map_err(|_| "image too wide")?;
            let height = u32::try_from(image.height).map_err(|_| "image too tall")?;
            RgbaImage::from_raw(width, height, image.bytes.into_owned())
                .map(Payload::Image)
                .ok_or_else(|| "invalid clipboard RGBA data".into())
        }
        Err(arboard::Error::ContentNotAvailable) => Ok(Payload::Empty),
        Err(error) => Err(error.to_string()),
    }
}

pub fn ignores_source(
    source: &ClipboardSource,
    preferences: &PreferencesDocument,
) -> Result<bool, String> {
    evaluate_capture_policy(&CapturePolicyInput {
        profile: CapturePolicyProfile::WindowsV1,
        source_candidate_keys: windows_capture_source_keys(
            source.name.as_deref(),
            source.path.as_deref(),
        ),
        application_rule_keys: preferences
            .ignore_list
            .ignored_app_identifiers
            .iter()
            .map(|rule| normalize_windows_capture_key(rule))
            .collect(),
        skip_unknown_source: preferences.ignore_list.skip_unknown_source,
        source_confidence: source.confidence,
        has_owner: source.process_id.is_some(),
        title_match_index: None,
        title_rule_count: 0,
    })
    .map(|decision| decision.skip)
    .map_err(|error| error.to_string())
}

pub fn start_monitor(app: AppHandle) {
    thread::spawn(move || loop {
        let state = app.state::<CoreState>();
        // The first webview imports legacy rules before any payload is read.
        if state
            .root_dir()
            .join("windows-preferences-migrated-v1")
            .exists()
            && poll_once(&app).is_err()
        {
            let _ = app.emit(
                "clipboard-capture-error",
                "剪贴板读取或保存失败；正在核对历史记录",
            );
        }
        thread::sleep(Duration::from_millis(800));
    });
}

fn poll_once(app: &AppHandle) -> Result<(), String> {
    let state = app.state::<CoreState>();
    let monitor = app.state::<ClipboardMonitorState>();
    let mut monitor = monitor
        .0
        .lock()
        .map_err(|_| "clipboard monitor lock poisoned")?;
    let before = platform::sequence()?;
    if monitor.unchanged(before) {
        return Ok(());
    }
    let source = platform::source();
    let _preferences_gate = state
        .preferences_gate
        .lock()
        .map_err(|_| "preferences lock poisoned")?;
    let preferences = state.with_core(|core| core.get_preferences().map_err(|e| e.to_string()))?;
    // Do not encode, write files or touch storage before validating the read.
    let Some(payload) = monitor.read_preflighted(
        before,
        &source,
        &preferences,
        read_payload,
        platform::sequence,
    )?
    else {
        return Ok(());
    };
    let key = payload.change_key();
    if before.is_none() {
        if monitor.fallback_self_write.as_deref() == Some(&key) {
            monitor.fallback_self_write = None;
            monitor.fallback_key = Some(key);
            return Ok(());
        }
        if monitor.fallback_key.as_deref() == Some(&key) {
            return Ok(());
        }
    }
    match payload {
        Payload::Empty => {
            monitor.completed_sequence = before;
            monitor.fallback_key = Some(key);
            Ok(())
        }
        Payload::Text(text) => {
            // Consume the DB attempt even on error: core maintenance can fail after commit.
            monitor.completed_sequence = before;
            monitor.fallback_key = Some(key);
            state.mutate(app, "capture", |core| {
                core.capture_text(CaptureTextRequest {
                    text,
                    detected_link: None,
                    display_rtf_relative_path: None,
                    display_rtf_mime_type: None,
                    display_rtf_byte_count: 0,
                    source_bundle_id: None,
                    source_app_name: source.name,
                    source_bundle_path: source.path,
                    source_icon_relative_path: None,
                    source_confidence: source.confidence,
                    pasteboard_change_count: i64::from(before.unwrap_or(0)),
                    self_write_token: None,
                })
                .map_err(|e| e.to_string())
            })?;
            Ok(())
        }
        Payload::Image(image) => {
            let relative_path = format!("assets/clipboard-{key}.png");
            let path = state.root_dir().join(&relative_path);
            if !path.exists() {
                save_png_atomically(&image, &path)?;
            }
            let bytes = fs::metadata(&path).map_err(|e| e.to_string())?.len() as i64;
            monitor.completed_sequence = before;
            monitor.fallback_key = Some(key);
            let result = state.mutate(app, "capture", |core| {
                core.capture_image(CaptureImageRequest {
                    payload_relative_path: relative_path,
                    preview_relative_path: None,
                    mime_type: Some("image/png".into()),
                    width: image.width() as i64,
                    height: image.height() as i64,
                    byte_count: bytes,
                    source_bundle_id: None,
                    source_app_name: source.name,
                    source_bundle_path: source.path,
                    source_icon_relative_path: None,
                    source_confidence: source.confidence,
                    pasteboard_change_count: i64::from(before.unwrap_or(0)),
                    self_write_token: None,
                })
                .map_err(|e| e.to_string())
            })?;
            // Failure here does not replay a successful capture. Visible cards retry.
            let _gate = state
                .thumbnail_gate
                .lock()
                .map_err(|_| "thumbnail lock poisoned")?;
            let _ = store_thumbnail(app, &result.item_id, &image);
            Ok(())
        }
    }
}

fn owner_handle(app: &AppHandle) -> Result<usize, String> {
    #[cfg(target_os = "windows")]
    {
        app.get_webview_window("main")
            .ok_or("main window unavailable")?
            .hwnd()
            .map(|hwnd| hwnd.0 as usize)
            .map_err(|e| e.to_string())
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = app;
        Ok(0)
    }
}

#[tauri::command]
pub async fn write_clipboard_text(
    app: AppHandle,
    text: String,
    item_id: Option<String>,
) -> Result<(), String> {
    let owner = owner_handle(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let monitor = app.state::<ClipboardMonitorState>();
        let mut monitor = monitor
            .0
            .lock()
            .map_err(|_| "clipboard monitor lock poisoned")?;
        platform::write_text(owner, &text)?;
        monitor.fallback_self_write = Some(Payload::Text(text).change_key());
        drop(monitor);
        record_copy(&app, item_id)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
pub async fn write_clipboard_image(app: AppHandle, item_id: String) -> Result<(), String> {
    let owner = owner_handle(&app)?;
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<CoreState>();
        let path = state
            .with_core(|core| core.image_payload_path(&item_id).map_err(|e| e.to_string()))?
            .ok_or("image payload unavailable")?;
        let image = decode_image(&path)?;
        let monitor = app.state::<ClipboardMonitorState>();
        let mut monitor = monitor
            .0
            .lock()
            .map_err(|_| "clipboard monitor lock poisoned")?;
        platform::write_image(owner, &image)?;
        monitor.fallback_self_write = Some(Payload::Image(image).change_key());
        drop(monitor);
        record_copy(&app, Some(item_id))
    })
    .await
    .map_err(|e| e.to_string())?
}

fn record_copy(app: &AppHandle, item_id: Option<String>) -> Result<(), String> {
    if let Some(item_id) = item_id {
        let result = app.state::<CoreState>().mutate(app, "copy", |core| {
            core.record_item_copied(item_id).map_err(|e| e.to_string())
        })?;
        if result.affected_count == 0 {
            return Err("clipboard written, but the history item no longer exists".into());
        }
    }
    Ok(())
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ThumbnailResult {
    pub item_id: String,
    pub path: Option<String>,
}

#[tauri::command]
pub async fn ensure_image_thumbnail(
    app: AppHandle,
    item_id: String,
) -> Result<ThumbnailResult, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<CoreState>();
        let _gate = state
            .thumbnail_gate
            .lock()
            .map_err(|_| "thumbnail lock poisoned")?;
        let path =
            state.with_core(|core| core.image_payload_path(&item_id).map_err(|e| e.to_string()))?;
        let Some(path) = path else {
            return Ok(ThumbnailResult {
                item_id,
                path: None,
            });
        };
        if let Some(thumbnail) = state.with_core(|core| {
            core.image_thumbnail_path(&item_id)
                .map_err(|e| e.to_string())
        })? {
            return Ok(ThumbnailResult {
                item_id,
                path: Some(thumbnail.to_string_lossy().into_owned()),
            });
        }
        let image = decode_image(&path)?;
        let path = store_thumbnail(&app, &item_id, &image)?;
        Ok(ThumbnailResult { item_id, path })
    })
    .await
    .map_err(|e| e.to_string())?
}

fn decode_image(path: &std::path::Path) -> Result<RgbaImage, String> {
    let mut reader = ImageReader::open(path).map_err(|e| e.to_string())?;
    // Retain image's default decoder allocation limits (512 MiB), including legacy payloads.
    reader.limits(image::Limits::default());
    reader
        .decode()
        .map_err(|e| e.to_string())
        .map(|image| image.to_rgba8())
}

fn store_thumbnail(
    app: &AppHandle,
    item_id: &str,
    image: &RgbaImage,
) -> Result<Option<String>, String> {
    let state = app.state::<CoreState>();
    if let Some(path) = state.with_core(|core| {
        core.image_thumbnail_path(item_id)
            .map_err(|e| e.to_string())
    })? {
        return Ok(Some(path.to_string_lossy().into_owned()));
    }
    let thumbnail = image::imageops::thumbnail(image, 420, 420);
    let name = format!("{:x}", Sha256::digest(item_id.as_bytes()));
    let relative = format!("thumbnails/windows-{name}.png");
    let path = state.root_dir().join(&relative);
    save_png_atomically(&thumbnail, &path)?;
    let result = state.with_core(|core| {
        core.set_item_thumbnail(
            item_id,
            &relative,
            "image/png",
            thumbnail.width() as i64,
            thumbnail.height() as i64,
        )
        .map_err(|e| e.to_string())
    })?;
    if result.affected_count == 0 {
        let _ = fs::remove_file(&path);
        return Ok(None);
    }
    Ok(Some(path.to_string_lossy().into_owned()))
}

fn save_png_atomically(image: &RgbaImage, path: &std::path::Path) -> Result<(), String> {
    let temporary = path.with_extension("tmp.png");
    let result = image
        .save(&temporary)
        .map_err(|e| e.to_string())
        .and_then(|_| fs::rename(&temporary, path).map_err(|e| e.to_string()));
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    use clipboard_core::SourceConfidence;

    #[test]
    fn waiting_for_monitor_allows_cancellation_before_the_stale_write() {
        use std::sync::{mpsc, Arc};

        let gate = Arc::new(ClipboardCopyIntentState::default());
        let session = gate.new_session().unwrap();
        gate.accept(session, 1).unwrap();
        let monitor = Arc::new(Mutex::new(()));
        let monitor_guard = monitor.lock().unwrap();
        let (waiting_tx, waiting_rx) = mpsc::channel();
        let worker_gate = gate.clone();
        let worker_monitor = monitor.clone();
        let worker = thread::spawn(move || {
            commit_copy(
                &worker_gate,
                session,
                1,
                || {
                    waiting_tx.send(()).unwrap();
                    worker_monitor.lock().map_err(|_| "monitor poisoned".into())
                },
                |_| panic!("cancelled preparation must not write"),
                || panic!("cancelled preparation must not record"),
            )
        });
        waiting_rx.recv_timeout(Duration::from_secs(2)).unwrap();
        let (cancel_tx, cancel_rx) = mpsc::channel();
        let cancel_gate = gate.clone();
        let cancellation = thread::spawn(move || {
            // Cancellation and a new copy both advance this same ordered intent.
            cancel_tx.send(cancel_gate.accept(session, 2)).unwrap();
        });
        let cancelled_while_waiting = cancel_rx.recv_timeout(Duration::from_secs(2));
        drop(monitor_guard);
        cancellation.join().unwrap();
        let copied = worker.join();
        assert!(cancelled_while_waiting.unwrap().unwrap());
        assert_eq!(copied.unwrap().unwrap().status, "superseded");
    }

    #[test]
    fn record_copy_runs_after_monitor_and_intent_guards_are_released() {
        let gate = ClipboardCopyIntentState::default();
        let session = gate.new_session().unwrap();
        gate.accept(session, 1).unwrap();
        let monitor = Mutex::new(());
        let result = commit_copy(
            &gate,
            session,
            1,
            || monitor.lock().map_err(|_| "monitor poisoned".into()),
            |_| Ok(()),
            || {
                assert!(monitor.try_lock().is_ok());
                assert!(gate.0.try_lock().is_ok());
                Err("injected record failure".into())
            },
        )
        .unwrap();
        assert_eq!(result.status, "written");
        assert!(result.record_warning.is_some());
    }

    #[test]
    fn successful_write_survives_record_failure_without_replaying_the_writer() {
        let gate = ClipboardCopyIntentState::default();
        let session = gate.new_session().unwrap();
        gate.accept(session, 1).unwrap();
        let writes = std::cell::Cell::new(0);
        let result = commit_copy(
            &gate,
            session,
            1,
            || Ok(()),
            |_| {
                writes.set(writes.get() + 1);
                Ok(())
            },
            || Err("injected record failure".into()),
        )
        .unwrap();
        assert_eq!(result.status, "written");
        assert!(result.record_warning.is_some());
        assert_eq!(writes.get(), 1);
        gate.accept(session, 2).unwrap();
        let superseded = commit_copy(
            &gate,
            session,
            1,
            || Ok(()),
            |_| panic!("must not write"),
            || panic!("must not record"),
        )
        .unwrap();
        assert_eq!(superseded.status, "superseded");
        assert!(commit_copy(
            &gate,
            session,
            2,
            || Ok(()),
            |_| Err("write failed".into()),
            || panic!("failed write must not record")
        )
        .is_err());
    }

    #[test]
    fn superseded_copy_does_not_call_the_writer() {
        let gate = ClipboardCopyIntentState::default();
        let session = gate.new_session().unwrap();
        assert!(gate.accept(session, 1).unwrap());
        assert!(gate.accept(session, 2).unwrap());
        assert!(!gate.accept(session, 1).unwrap());
        assert!(gate
            .write_if_current::<()>(session, 1, || panic!("stale preparation must never write"))
            .unwrap()
            .is_none());
        let writes = std::cell::Cell::new(0);
        gate.write_if_current(session, 2, || {
            writes.set(writes.get() + 1);
            Ok(())
        })
        .unwrap();
        assert_eq!(writes.get(), 1);
        gate.accept(session, 3).unwrap(); // Explicit cancellation uses the same ordering.
        assert!(gate
            .write_if_current::<()>(session, 2, || panic!("cancelled copy must never write"))
            .unwrap()
            .is_none());
        let reloaded = gate.new_session().unwrap();
        assert!(!gate.accept(session, 100).unwrap());
        assert!(gate.accept(reloaded, 1).unwrap());
    }

    #[test]
    fn stored_copy_reads_full_text_and_preserves_hidden_pinned_items() {
        let directory = tempfile::tempdir().unwrap();
        let mut core = ClipboardCore::open(directory.path()).unwrap();
        let text = format!("{}full-tail", "preview ".repeat(150));
        let captured = core
            .capture_text(CaptureTextRequest {
                text: text.clone(),
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
            .unwrap();
        core.set_item_pinboard_membership(&captured.item_id, "default", true)
            .unwrap();
        core.delete_item(&captured.item_id).unwrap();
        let plan = stored_copy_plan(&core, &captured.item_id).unwrap();
        assert_eq!(plan.included_ids, [captured.item_id.clone()]);
        match plan.payload {
            StoredCopyPayload::Text(payload) => assert_eq!(payload, text),
            _ => panic!("expected full text"),
        }
        assert!(stored_copy_plan(&core, "item_missing").is_err());
    }

    #[test]
    fn shared_copy_plan_preserves_windows_text_fallbacks_and_image_requirements() {
        let fixtures: Vec<ClipboardItemSummary> = serde_json::from_str(include_str!(
            "../../src/panel/fixtures/clipboard-list-entries.json"
        ))
        .unwrap();
        let base = fixtures
            .iter()
            .find(|item| item.item_type == ClipboardItemType::Text)
            .unwrap();
        let link = fixtures
            .iter()
            .find(|item| item.item_type == ClipboardItemType::Link)
            .unwrap();
        let expect_text = |item: ClipboardItemSummary, text: &str| {
            let id = item.id.clone();
            let plan = plan_stored_copy(item, None).unwrap();
            assert_eq!(plan.included_ids, [id]);
            match plan.payload {
                StoredCopyPayload::Text(actual) => assert_eq!(actual, text),
                _ => panic!("Windows compatibility plan must use text"),
            }
        };
        expect_text(link.clone(), "https://example.test/docs?q=1");
        let mut rich_text = base.clone();
        rich_text.item_type = ClipboardItemType::RichText;
        rich_text.primary_text = Some("full rich text body".into());
        expect_text(rich_text, "full rich text body");
        let mut file = base.clone();
        file.item_type = ClipboardItemType::File;
        file.file_items = vec![clipboard_core::ClipboardFileItemSummary {
            path: "C:\\External\\fixture.txt".into(),
            file_name: "fixture.txt".into(),
            file_extension: Some("txt".into()),
            byte_count: 12,
            is_directory: false,
            width: None,
            height: None,
            content_type: None,
        }];
        expect_text(file, "C:\\External\\fixture.txt");
        let mut color = base.clone();
        color.item_type = ClipboardItemType::Color;
        color.summary = "#123456".into();
        color.primary_text = Some("ignored legacy body".into());
        expect_text(color, "#123456");

        let mut image = base.clone();
        image.item_type = ClipboardItemType::Image;
        let native_path = std::path::PathBuf::from("synthetic-native-image.png");
        assert!(plan_stored_copy(image.clone(), None).is_err());
        let plan = plan_stored_copy(image.clone(), Some(native_path.clone())).unwrap();
        assert_eq!(plan.included_ids, [image.id.clone()]);
        match plan.payload {
            StoredCopyPayload::Image(path) => assert_eq!(path, native_path),
            _ => panic!("ready image must retain the native path"),
        }
        image.payload_state = clipboard_core::PayloadState::Pending;
        assert!(plan_stored_copy(image, Some(native_path)).is_err());
    }

    #[test]
    fn ignores_exact_process_names_stems_and_paths_without_substring_matches() {
        let mut preferences = PreferencesDocument::default();
        preferences.ignore_list.ignored_app_identifiers = vec!["KEEPASS.EXE".into()];
        let source = ClipboardSource {
            path: Some("C:\\Apps\\KeePass.exe".into()),
            ..Default::default()
        };
        assert!(ignores_source(&source, &preferences).unwrap());
        preferences.ignore_list.ignored_app_identifiers = vec!["keep".into()];
        assert!(!ignores_source(&source, &preferences).unwrap());
        preferences.ignore_list.skip_unknown_source = true;
        assert!(ignores_source(&ClipboardSource::default(), &preferences).unwrap());
        let fallback = ClipboardSource {
            name: Some("Notepad.exe".into()),
            confidence: SourceConfidence::Low,
            ..Default::default()
        };
        assert!(ignores_source(&fallback, &preferences).unwrap());
    }

    #[test]
    fn capture_preflight_rejects_sources_without_reading_payload() {
        let mut monitor = MonitorState::default();
        let mut preferences = PreferencesDocument::default();
        preferences.ignore_list.ignored_app_identifiers = vec!["privaté".into()];
        let source = ClipboardSource {
            process_id: Some(u32::MAX),
            name: Some("PRIVATÉ.EXE".into()),
            confidence: SourceConfidence::High,
            ..Default::default()
        };
        assert!(monitor
            .read_preflighted(
                Some(1),
                &source,
                &preferences,
                || Err::<(), _>("filtered source must never read payload".into()),
                || Ok(Some(1)),
            )
            .unwrap()
            .is_none());
        assert_eq!(monitor.completed_sequence, Some(1));

        preferences.ignore_list.ignored_app_identifiers.clear();
        preferences.ignore_list.skip_unknown_source = true;
        for source in [
            ClipboardSource {
                process_id: None,
                ..source.clone()
            },
            ClipboardSource {
                confidence: SourceConfidence::Low,
                ..source.clone()
            },
            ClipboardSource {
                name: None,
                ..source.clone()
            },
            ClipboardSource {
                process_id: Some(std::process::id()),
                ..source.clone()
            },
        ] {
            assert!(monitor
                .read_preflighted(
                    Some(2),
                    &source,
                    &preferences,
                    || Err::<(), _>("unknown or self source must never read payload".into()),
                    || Ok(Some(3)),
                )
                .unwrap()
                .is_none());
            // A changed sequence was not consumed by the rejected old context.
            assert_eq!(monitor.completed_sequence, Some(1));
        }
        assert!(!ignores_source(&source, &preferences).unwrap());
    }

    #[test]
    fn sequence_gate_skips_unchanged_images_and_discards_reads_changed_midflight() {
        let monitor = MonitorState {
            completed_sequence: Some(10),
            ..Default::default()
        };
        let reads = std::cell::Cell::new(0);
        let read_image = || {
            reads.set(reads.get() + 1);
            Ok(RgbaImage::new(2, 2))
        };
        assert!(monitor
            .read_stable(Some(10), read_image, || panic!(
                "unchanged sequence must not read"
            ))
            .unwrap()
            .is_none());
        assert_eq!(reads.get(), 0);
        assert!(monitor
            .read_stable(Some(11), read_image, || Ok(Some(12)))
            .unwrap()
            .is_none());
        assert_eq!(reads.get(), 0); // Changed during preflight: no payload read.
        let mut sequence = [Some(11), Some(12)].into_iter();
        assert!(monitor
            .read_stable(Some(11), read_image, || Ok(sequence.next().unwrap()))
            .unwrap()
            .is_none());
        assert_eq!(reads.get(), 1);
        assert_eq!(monitor.completed_sequence, Some(10));
        assert!(monitor
            .read_stable(Some(12), read_image, || Ok(Some(12)))
            .unwrap()
            .is_some());
        assert_eq!(reads.get(), 2);
        assert!(monitor
            .read_stable(Some(12), || Err::<(), _>("busy".into()), || Ok(Some(12)))
            .is_err());
        assert_eq!(monitor.completed_sequence, Some(10));
    }
}
