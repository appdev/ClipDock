use clipboard_core::{
    CaptureDetectedLink, CaptureFilesRequest, CaptureImageRequest, CaptureTextRequest,
    CapturedFileMetadata, ClipboardCore, ClipboardItemType, ItemManagementResult, ItemQuery,
    LinkMetadataState, MaintenanceResult, PageRequest, PinboardPage, PreferencesDocument,
    SourceConfidence,
};
use serde::Deserialize;

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct CoreOpenResult {
        ok: bool,
        database_path: String,
        schema_version: i64,
        item_count: i64,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreListResult {
        ok: bool,
        total_count: i64,
        has_more: bool,
        items_json: String,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreSourceAppsResult {
        ok: bool,
        total_count: i64,
        has_more: bool,
        apps_json: String,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CorePinboardsResult {
        ok: bool,
        total_count: i64,
        pinboards_json: String,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreCaptureResult {
        ok: bool,
        item_id: String,
        content_hash: String,
        copy_count: i64,
        inserted: bool,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CorePreferencesResult {
        ok: bool,
        schema_version: i64,
        preferences_json: String,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreMaintenanceResult {
        ok: bool,
        purged_item_count: i64,
        deleted_asset_row_count: i64,
        deleted_asset_file_count: i64,
        deleted_orphan_file_count: i64,
        reclaimed_bytes: i64,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreItemManagementResult {
        ok: bool,
        affected_count: i64,
        error_code: String,
        message_key: String,
    }

    extern "Rust" {
        fn open_core(app_support_dir: String) -> CoreOpenResult;
        fn run_maintenance(app_support_dir: String) -> CoreMaintenanceResult;
        fn get_preferences(app_support_dir: String) -> CorePreferencesResult;
        fn update_preferences(
            app_support_dir: String,
            preferences_json: String,
        ) -> CorePreferencesResult;
        fn list_items(
            app_support_dir: String,
            limit: i64,
            offset: i64,
            item_type: String,
            source_app_id: String,
            pinboard_id: String,
            search_text: String,
        ) -> CoreListResult;
        fn list_source_apps(
            app_support_dir: String,
            limit: i64,
            offset: i64,
        ) -> CoreSourceAppsResult;
        fn list_pinboards(app_support_dir: String) -> CorePinboardsResult;
        fn create_pinboard(
            app_support_dir: String,
            title: String,
            color_code: i64,
        ) -> CoreItemManagementResult;
        fn rename_pinboard(
            app_support_dir: String,
            pinboard_id: String,
            title: String,
        ) -> CoreItemManagementResult;
        fn update_pinboard_color(
            app_support_dir: String,
            pinboard_id: String,
            color_code: i64,
        ) -> CoreItemManagementResult;
        fn delete_pinboard(
            app_support_dir: String,
            pinboard_id: String,
        ) -> CoreItemManagementResult;
        fn set_item_pinboard_membership(
            app_support_dir: String,
            item_id: String,
            pinboard_id: String,
            is_member: bool,
        ) -> CoreItemManagementResult;
        fn delete_item(app_support_dir: String, item_id: String) -> CoreItemManagementResult;
        fn clear_items(
            app_support_dir: String,
            item_type: String,
            source_app_id: String,
            search_text: String,
        ) -> CoreItemManagementResult;
        fn capture_text(
            app_support_dir: String,
            text: String,
            link_original_text: String,
            link_canonical_url: String,
            link_display_url: String,
            link_host: String,
            link_metadata_state: String,
            source_bundle_id: String,
            source_app_name: String,
            source_bundle_path: String,
            source_icon_relative_path: String,
            source_confidence: String,
            pasteboard_change_count: i64,
            self_write_token: String,
        ) -> CoreCaptureResult;
        fn capture_image(
            app_support_dir: String,
            payload_relative_path: String,
            preview_relative_path: String,
            mime_type: String,
            width: i64,
            height: i64,
            byte_count: i64,
            source_bundle_id: String,
            source_app_name: String,
            source_bundle_path: String,
            source_icon_relative_path: String,
            source_confidence: String,
            pasteboard_change_count: i64,
            self_write_token: String,
        ) -> CoreCaptureResult;
        fn capture_files(
            app_support_dir: String,
            files_json: String,
            snapshot_relative_path: String,
            snapshot_byte_count: i64,
            source_bundle_id: String,
            source_app_name: String,
            source_bundle_path: String,
            source_icon_relative_path: String,
            source_confidence: String,
            pasteboard_change_count: i64,
            self_write_token: String,
        ) -> CoreCaptureResult;
    }
}

fn get_preferences(app_support_dir: String) -> ffi::CorePreferencesResult {
    match ClipboardCore::open(app_support_dir).and_then(|core| core.get_preferences()) {
        Ok(preferences) => preferences_result(preferences),
        Err(error) => ffi::CorePreferencesResult {
            ok: false,
            schema_version: 0,
            preferences_json: "{}".to_string(),
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn update_preferences(
    app_support_dir: String,
    preferences_json: String,
) -> ffi::CorePreferencesResult {
    let preferences = match serde_json::from_str::<PreferencesDocument>(&preferences_json) {
        Ok(preferences) => preferences,
        Err(_error) => {
            return ffi::CorePreferencesResult {
                ok: false,
                schema_version: 0,
                preferences_json: "{}".to_string(),
                error_code: "invalid_input".to_string(),
                message_key: "clipboard.error.invalid_input".to_string(),
            };
        }
    };

    match ClipboardCore::open(app_support_dir)
        .and_then(|mut core| core.update_preferences(preferences))
    {
        Ok(preferences) => preferences_result(preferences),
        Err(error) => ffi::CorePreferencesResult {
            ok: false,
            schema_version: 0,
            preferences_json: "{}".to_string(),
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn preferences_result(preferences: PreferencesDocument) -> ffi::CorePreferencesResult {
    ffi::CorePreferencesResult {
        ok: true,
        schema_version: clipboard_core::CURRENT_SCHEMA_VERSION,
        preferences_json: serde_json::to_string(&preferences).unwrap_or_else(|_| "{}".to_string()),
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn run_maintenance(app_support_dir: String) -> ffi::CoreMaintenanceResult {
    match ClipboardCore::open(app_support_dir).and_then(|mut core| core.run_maintenance()) {
        Ok(result) => maintenance_result(result),
        Err(error) => ffi::CoreMaintenanceResult {
            ok: false,
            purged_item_count: 0,
            deleted_asset_row_count: 0,
            deleted_asset_file_count: 0,
            deleted_orphan_file_count: 0,
            reclaimed_bytes: 0,
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn maintenance_result(result: MaintenanceResult) -> ffi::CoreMaintenanceResult {
    ffi::CoreMaintenanceResult {
        ok: true,
        purged_item_count: result.purged_item_count,
        deleted_asset_row_count: result.deleted_asset_row_count,
        deleted_asset_file_count: result.deleted_asset_file_count,
        deleted_orphan_file_count: result.deleted_orphan_file_count,
        reclaimed_bytes: result.reclaimed_bytes,
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn list_pinboards(app_support_dir: String) -> ffi::CorePinboardsResult {
    match ClipboardCore::open(app_support_dir).and_then(|core| core.list_pinboards()) {
        Ok(page) => pinboards_result(page),
        Err(error) => ffi::CorePinboardsResult {
            ok: false,
            total_count: 0,
            pinboards_json: "[]".to_string(),
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn pinboards_result(page: PinboardPage) -> ffi::CorePinboardsResult {
    ffi::CorePinboardsResult {
        ok: true,
        total_count: page.total_count,
        pinboards_json: serde_json::to_string(&page.pinboards).unwrap_or_else(|_| "[]".to_string()),
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn create_pinboard(
    app_support_dir: String,
    title: String,
    color_code: i64,
) -> ffi::CoreItemManagementResult {
    match ClipboardCore::open(app_support_dir).and_then(|mut core| {
        core.create_pinboard(title, optional_i64(color_code))
            .map(|_| ())
    }) {
        Ok(()) => item_management_result(ItemManagementResult { affected_count: 1 }),
        Err(error) => item_management_error_result(error),
    }
}

fn rename_pinboard(
    app_support_dir: String,
    pinboard_id: String,
    title: String,
) -> ffi::CoreItemManagementResult {
    match ClipboardCore::open(app_support_dir)
        .and_then(|mut core| core.rename_pinboard(pinboard_id, title).map(|_| ()))
    {
        Ok(()) => item_management_result(ItemManagementResult { affected_count: 1 }),
        Err(error) => item_management_error_result(error),
    }
}

fn update_pinboard_color(
    app_support_dir: String,
    pinboard_id: String,
    color_code: i64,
) -> ffi::CoreItemManagementResult {
    match ClipboardCore::open(app_support_dir).and_then(|mut core| {
        core.update_pinboard_color(pinboard_id, color_code)
            .map(|_| ())
    }) {
        Ok(()) => item_management_result(ItemManagementResult { affected_count: 1 }),
        Err(error) => item_management_error_result(error),
    }
}

fn delete_pinboard(app_support_dir: String, pinboard_id: String) -> ffi::CoreItemManagementResult {
    match ClipboardCore::open(app_support_dir)
        .and_then(|mut core| core.delete_pinboard(pinboard_id))
    {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn set_item_pinboard_membership(
    app_support_dir: String,
    item_id: String,
    pinboard_id: String,
    is_member: bool,
) -> ffi::CoreItemManagementResult {
    match ClipboardCore::open(app_support_dir)
        .and_then(|mut core| core.set_item_pinboard_membership(item_id, pinboard_id, is_member))
    {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn delete_item(app_support_dir: String, item_id: String) -> ffi::CoreItemManagementResult {
    match ClipboardCore::open(app_support_dir).and_then(|mut core| core.delete_item(item_id)) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn clear_items(
    app_support_dir: String,
    item_type: String,
    source_app_id: String,
    search_text: String,
) -> ffi::CoreItemManagementResult {
    let query = ItemQuery {
        item_type: parse_item_type(&item_type),
        source_app_id: optional_string(source_app_id),
        pinboard_id: None,
        search_text: optional_string(search_text),
    };

    match ClipboardCore::open(app_support_dir).and_then(|mut core| core.clear_items(query)) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn item_management_result(result: ItemManagementResult) -> ffi::CoreItemManagementResult {
    ffi::CoreItemManagementResult {
        ok: true,
        affected_count: result.affected_count,
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn item_management_error_result(error: clipboard_core::CoreError) -> ffi::CoreItemManagementResult {
    ffi::CoreItemManagementResult {
        ok: false,
        affected_count: 0,
        error_code: error.code.as_str().to_string(),
        message_key: error.message_key().to_string(),
    }
}

fn open_core(app_support_dir: String) -> ffi::CoreOpenResult {
    match ClipboardCore::open(app_support_dir) {
        Ok(core) => match core.info() {
            Ok(info) => ffi::CoreOpenResult {
                ok: true,
                database_path: info.database_path,
                schema_version: info.schema_version,
                item_count: info.item_count,
                error_code: String::new(),
                message_key: String::new(),
            },
            Err(error) => ffi::CoreOpenResult {
                ok: false,
                database_path: String::new(),
                schema_version: 0,
                item_count: 0,
                error_code: error.code.as_str().to_string(),
                message_key: error.message_key().to_string(),
            },
        },
        Err(error) => ffi::CoreOpenResult {
            ok: false,
            database_path: String::new(),
            schema_version: 0,
            item_count: 0,
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn capture_text(
    app_support_dir: String,
    text: String,
    link_original_text: String,
    link_canonical_url: String,
    link_display_url: String,
    link_host: String,
    link_metadata_state: String,
    source_bundle_id: String,
    source_app_name: String,
    source_bundle_path: String,
    source_icon_relative_path: String,
    source_confidence: String,
    pasteboard_change_count: i64,
    self_write_token: String,
) -> ffi::CoreCaptureResult {
    match ClipboardCore::open(app_support_dir).and_then(|mut core| {
        core.capture_text(CaptureTextRequest {
            text,
            detected_link: capture_detected_link(
                link_original_text,
                link_canonical_url,
                link_display_url,
                link_host,
                link_metadata_state,
            ),
            source_bundle_id: optional_string(source_bundle_id),
            source_app_name: optional_string(source_app_name),
            source_bundle_path: optional_string(source_bundle_path),
            source_icon_relative_path: optional_string(source_icon_relative_path),
            source_confidence: parse_source_confidence(&source_confidence),
            pasteboard_change_count,
            self_write_token: optional_string(self_write_token),
        })
    }) {
        Ok(result) => ffi::CoreCaptureResult {
            ok: true,
            item_id: result.item_id,
            content_hash: result.content_hash,
            copy_count: result.copy_count,
            inserted: result.inserted,
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(error) => ffi::CoreCaptureResult {
            ok: false,
            item_id: String::new(),
            content_hash: String::new(),
            copy_count: 0,
            inserted: false,
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn capture_detected_link(
    original_text: String,
    canonical_url: String,
    display_url: String,
    host: String,
    metadata_state: String,
) -> Option<CaptureDetectedLink> {
    let canonical_url = canonical_url.trim().to_string();
    let host = host.trim().to_string();
    if canonical_url.is_empty() || host.is_empty() {
        return None;
    }

    Some(CaptureDetectedLink {
        original_text,
        canonical_url,
        display_url,
        host,
        metadata_state: parse_link_metadata_state(&metadata_state),
    })
}

fn capture_image(
    app_support_dir: String,
    payload_relative_path: String,
    preview_relative_path: String,
    mime_type: String,
    width: i64,
    height: i64,
    byte_count: i64,
    source_bundle_id: String,
    source_app_name: String,
    source_bundle_path: String,
    source_icon_relative_path: String,
    source_confidence: String,
    pasteboard_change_count: i64,
    self_write_token: String,
) -> ffi::CoreCaptureResult {
    match ClipboardCore::open(app_support_dir).and_then(|mut core| {
        core.capture_image(CaptureImageRequest {
            payload_relative_path,
            preview_relative_path: optional_string(preview_relative_path),
            mime_type: optional_string(mime_type),
            width,
            height,
            byte_count,
            source_bundle_id: optional_string(source_bundle_id),
            source_app_name: optional_string(source_app_name),
            source_bundle_path: optional_string(source_bundle_path),
            source_icon_relative_path: optional_string(source_icon_relative_path),
            source_confidence: parse_source_confidence(&source_confidence),
            pasteboard_change_count,
            self_write_token: optional_string(self_write_token),
        })
    }) {
        Ok(result) => ffi::CoreCaptureResult {
            ok: true,
            item_id: result.item_id,
            content_hash: result.content_hash,
            copy_count: result.copy_count,
            inserted: result.inserted,
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(error) => ffi::CoreCaptureResult {
            ok: false,
            item_id: String::new(),
            content_hash: String::new(),
            copy_count: 0,
            inserted: false,
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn capture_files(
    app_support_dir: String,
    files_json: String,
    snapshot_relative_path: String,
    snapshot_byte_count: i64,
    source_bundle_id: String,
    source_app_name: String,
    source_bundle_path: String,
    source_icon_relative_path: String,
    source_confidence: String,
    pasteboard_change_count: i64,
    self_write_token: String,
) -> ffi::CoreCaptureResult {
    let files_payload = match serde_json::from_str::<CaptureFilesPayload>(&files_json) {
        Ok(files_payload) => files_payload,
        Err(_error) => {
            return ffi::CoreCaptureResult {
                ok: false,
                item_id: String::new(),
                content_hash: String::new(),
                copy_count: 0,
                inserted: false,
                error_code: "invalid_input".to_string(),
                message_key: "clipboard.error.invalid_input".to_string(),
            };
        }
    };
    let (file_paths, file_items) = files_payload.into_parts();

    match ClipboardCore::open(app_support_dir).and_then(|mut core| {
        core.capture_files(CaptureFilesRequest {
            file_paths,
            file_items,
            snapshot_relative_path: optional_string(snapshot_relative_path),
            snapshot_byte_count,
            source_bundle_id: optional_string(source_bundle_id),
            source_app_name: optional_string(source_app_name),
            source_bundle_path: optional_string(source_bundle_path),
            source_icon_relative_path: optional_string(source_icon_relative_path),
            source_confidence: parse_source_confidence(&source_confidence),
            pasteboard_change_count,
            self_write_token: optional_string(self_write_token),
        })
    }) {
        Ok(result) => ffi::CoreCaptureResult {
            ok: true,
            item_id: result.item_id,
            content_hash: result.content_hash,
            copy_count: result.copy_count,
            inserted: result.inserted,
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(error) => ffi::CoreCaptureResult {
            ok: false,
            item_id: String::new(),
            content_hash: String::new(),
            copy_count: 0,
            inserted: false,
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum CaptureFilesPayload {
    Metadata(Vec<CapturedFileMetadata>),
    Paths(Vec<String>),
}

impl CaptureFilesPayload {
    fn into_parts(self) -> (Vec<String>, Vec<CapturedFileMetadata>) {
        match self {
            Self::Metadata(file_items) => {
                let file_paths = file_items.iter().map(|item| item.path.clone()).collect();
                (file_paths, file_items)
            }
            Self::Paths(file_paths) => (file_paths, Vec::new()),
        }
    }
}

fn list_items(
    app_support_dir: String,
    limit: i64,
    offset: i64,
    item_type: String,
    source_app_id: String,
    pinboard_id: String,
    search_text: String,
) -> ffi::CoreListResult {
    let query = ItemQuery {
        item_type: parse_item_type(&item_type),
        source_app_id: optional_string(source_app_id),
        pinboard_id: optional_string(pinboard_id),
        search_text: optional_string(search_text),
    };

    match ClipboardCore::open(app_support_dir)
        .and_then(|core| core.list_items(query, PageRequest { limit, offset }))
    {
        Ok(page) => ffi::CoreListResult {
            ok: true,
            total_count: page.total_count,
            has_more: page.has_more,
            items_json: serde_json::to_string(&page.items).unwrap_or_else(|_| "[]".to_string()),
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(error) => ffi::CoreListResult {
            ok: false,
            total_count: 0,
            has_more: false,
            items_json: "[]".to_string(),
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn list_source_apps(app_support_dir: String, limit: i64, offset: i64) -> ffi::CoreSourceAppsResult {
    match ClipboardCore::open(app_support_dir)
        .and_then(|core| core.list_source_apps(PageRequest { limit, offset }))
    {
        Ok(page) => ffi::CoreSourceAppsResult {
            ok: true,
            total_count: page.total_count,
            has_more: page.has_more,
            apps_json: serde_json::to_string(&page.apps).unwrap_or_else(|_| "[]".to_string()),
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(error) => ffi::CoreSourceAppsResult {
            ok: false,
            total_count: 0,
            has_more: false,
            apps_json: "[]".to_string(),
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn optional_string(value: String) -> Option<String> {
    let value = value.trim().to_string();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn optional_i64(value: i64) -> Option<i64> {
    if value > 0 {
        Some(value)
    } else {
        None
    }
}

fn parse_source_confidence(value: &str) -> SourceConfidence {
    match value {
        "high" => SourceConfidence::High,
        "medium" => SourceConfidence::Medium,
        "low" => SourceConfidence::Low,
        _ => SourceConfidence::Unknown,
    }
}

fn parse_link_metadata_state(value: &str) -> LinkMetadataState {
    match value {
        "fetching" => LinkMetadataState::Fetching,
        "ready" => LinkMetadataState::Ready,
        "failed" => LinkMetadataState::Failed,
        "disabled" => LinkMetadataState::Disabled,
        "stale" => LinkMetadataState::Stale,
        _ => LinkMetadataState::Pending,
    }
}

fn parse_item_type(value: &str) -> Option<ClipboardItemType> {
    match value {
        "text" => Some(ClipboardItemType::Text),
        "link" => Some(ClipboardItemType::Link),
        "image" => Some(ClipboardItemType::Image),
        "file" => Some(ClipboardItemType::File),
        "color" => Some(ClipboardItemType::Color),
        "rich_text" => Some(ClipboardItemType::RichText),
        _ => None,
    }
}
