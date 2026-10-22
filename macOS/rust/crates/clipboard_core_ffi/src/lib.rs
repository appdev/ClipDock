mod asset_ffi;
mod sessions;
use asset_ffi::{
    cleanup_uncommitted_assets, encode_lossless_webp_to_staging, publish_reserved_asset,
    reserve_asset, reserve_existing_asset, stage_reserved_asset,
};
use sessions::{with_core, with_core_batch, with_core_without_maintenance};

use clipboard_core::{
    CaptureDetectedLink, CaptureFilesRequest, CaptureImageRequest, CapturePendingImageRequest,
    CaptureRichTextRequest, CaptureTextRequest, CapturedFileMetadata, ClipboardCore,
    ClipboardItemType, CompleteLinkMetadataFetchRequest, CompletePendingImagePayloadRequest,
    FailPendingImagePayloadRequest, ItemManagementResult, ItemQuery, LinkMetadataFetchCandidate,
    LinkMetadataState, MaintenanceResult, PageRequest, PendingImageCaptureResult,
    PendingImageCompletionResult, PinboardPage, PreferencesDocument, RecoverPendingImagesRequest,
    SourceConfidence,
};
use clipboard_core::{CoreError, CoreErrorCode, ItemMutation, PreferencesPatch};
use serde::{Deserialize, Serialize};

#[swift_bridge::bridge]
mod ffi {
    #[swift_bridge(swift_repr = "struct")]
    struct CoreBackupResult {
        ok: bool,
        exported_count: i64,
        imported_count: i64,
        skipped_count: i64,
        error_code: String,
        message: String,
    }

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
    struct CoreJSONResult {
        ok: bool,
        result_json: String,
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

    #[swift_bridge(swift_repr = "struct")]
    struct CoreWebPEncodeResult {
        ok: bool,
        bytes: Vec<u8>,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreAdaptiveWebPEncodeResult {
        ok: bool,
        bytes: Vec<u8>,
        width: i64,
        height: i64,
        quality: i64,
        score: f64,
        selected_tier: String,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreSvgRasterizeResult {
        ok: bool,
        bytes: Vec<u8>,
        width: i64,
        height: i64,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CoreLinkMetadataFetchBatchResult {
        ok: bool,
        candidates_json: String,
        error_code: String,
        message_key: String,
    }

    #[swift_bridge(swift_repr = "struct")]
    struct CorePendingImageResult {
        ok: bool,
        result_json: String,
        error_code: String,
        message_key: String,
    }

    extern "Rust" {
        fn reserve_asset(
            app_support_dir: String,
            relative_path: String,
            staged_relative_path: String,
        ) -> CoreJSONResult;
        fn reserve_existing_asset(app_support_dir: String, relative_path: String)
            -> CoreJSONResult;
        fn stage_reserved_asset(
            app_support_dir: String,
            reservation_json: String,
            bytes: &[u8],
        ) -> CoreJSONResult;
        fn publish_reserved_asset(
            app_support_dir: String,
            reservation_json: String,
        ) -> CoreJSONResult;
        fn encode_lossless_webp_to_staging(
            app_support_dir: String,
            reservation_json: String,
            rgba: &[u8],
            width: i64,
            height: i64,
            max_bytes: i64,
        ) -> CoreJSONResult;
        fn cleanup_uncommitted_assets(
            app_support_dir: String,
            relative_paths_json: String,
        ) -> CoreJSONResult;
        fn metadata_url_policy_json(request_json: String) -> CoreJSONResult;
        fn metadata_limits_json(request_json: String) -> CoreJSONResult;
        fn metadata_retry_at_json(request_json: String) -> CoreJSONResult;
        fn parse_metadata_html_json(request_json: String) -> CoreJSONResult;
        fn evaluate_capture_policy_json(request_json: String) -> CoreJSONResult;
        fn analyze_capture_text_json(request_json: String) -> CoreJSONResult;
        fn plan_copy_json(request_json: String) -> CoreJSONResult;
        fn open_core(app_support_dir: String) -> CoreOpenResult;
        fn export_backup(app_support_dir: String, path: String) -> CoreBackupResult;
        fn import_backup(app_support_dir: String, path: String) -> CoreBackupResult;
        fn open_core_without_maintenance(app_support_dir: String) -> CoreOpenResult;
        fn get_preferences_without_maintenance(app_support_dir: String) -> CorePreferencesResult;
        fn patch_preferences(app_support_dir: String, patch_json: String) -> CoreJSONResult;
        fn get_item(app_support_dir: String, item_id: String) -> CoreJSONResult;
        fn get_items(app_support_dir: String, ordered_ids_json: String) -> CoreJSONResult;
        fn mutate_items(app_support_dir: String, requests_json: String) -> CoreJSONResult;
        fn list_entries(
            app_support_dir: String,
            limit: i64,
            offset: i64,
            item_type: String,
            source_app_id: String,
            pinboard_id: String,
            search_text: String,
        ) -> CoreListResult;
        fn active_source_icon_header_color_cache_version() -> i64;
        fn blake3_digest(bytes: &[u8]) -> String;
        fn encode_webp_lossless_rgba(rgba: &[u8], width: i64, height: i64) -> CoreWebPEncodeResult;
        fn encode_adaptive_thumbnail_webp_rgba(
            rgba: &[u8],
            width: i64,
            height: i64,
            normal_target_bytes: i64,
            detail_target_bytes: i64,
            max_bytes: i64,
        ) -> CoreAdaptiveWebPEncodeResult;
        fn rasterize_svg_to_png(
            svg: &[u8],
            max_width: i64,
            max_height: i64,
        ) -> CoreSvgRasterizeResult;
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
        fn rename_item(app_support_dir: String, item_id: String, title: String) -> CoreItemManagementResult;
        fn record_item_copied(app_support_dir: String, item_id: String)
            -> CoreItemManagementResult;
        fn update_source_app_icon_header_color(
            app_support_dir: String,
            source_app_id: String,
            source_app_icon_path: String,
            header_color_argb: i64,
            allow_latest_without_path: bool,
        ) -> CoreItemManagementResult;
        fn clear_items(
            app_support_dir: String,
            item_type: String,
            source_app_id: String,
            search_text: String,
        ) -> CoreItemManagementResult;
        fn claim_link_metadata_fetch_batch(
            app_support_dir: String,
            limit: i64,
            lease_timeout_ms: i64,
        ) -> CoreLinkMetadataFetchBatchResult;
        fn complete_link_metadata_fetch(
            app_support_dir: String,
            request_json: String,
        ) -> CoreItemManagementResult;
        fn fail_link_metadata_fetch(
            app_support_dir: String,
            item_id: String,
            lease_started_at_ms: i64,
            failure_code: String,
            next_retry_at_ms: i64,
        ) -> CoreItemManagementResult;
        fn capture_text(
            app_support_dir: String,
            text: String,
            link_original_text: String,
            link_canonical_url: String,
            link_display_url: String,
            link_host: String,
            link_metadata_state: String,
            display_rtf_relative_path: String,
            display_rtf_mime_type: String,
            display_rtf_byte_count: i64,
            source_bundle_id: String,
            source_app_name: String,
            source_bundle_path: String,
            source_icon_relative_path: String,
            source_confidence: String,
            pasteboard_change_count: i64,
            self_write_token: String,
        ) -> CoreCaptureResult;
        fn capture_rich_text(app_support_dir: String, request_json: String) -> CoreCaptureResult;
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
        fn capture_pending_image(
            app_support_dir: String,
            request_json: String,
        ) -> CorePendingImageResult;
        fn complete_pending_image_payload(
            app_support_dir: String,
            request_json: String,
        ) -> CorePendingImageResult;
        fn fail_pending_image_payload(
            app_support_dir: String,
            request_json: String,
        ) -> CorePendingImageResult;
        fn recover_pending_images(
            app_support_dir: String,
            request_json: String,
        ) -> CoreItemManagementResult;
        fn capture_files(
            app_support_dir: String,
            files_json: String,
            preview_relative_path: String,
            preview_mime_type: String,
            preview_width: i64,
            preview_height: i64,
            preview_byte_count: i64,
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
    preferences_response(with_core(app_support_dir, |core| core.get_preferences()))
}

fn get_preferences_without_maintenance(app_support_dir: String) -> ffi::CorePreferencesResult {
    preferences_response(with_core_without_maintenance(app_support_dir, |core| {
        core.get_preferences()
    }))
}

fn preferences_response(
    result: clipboard_core::Result<PreferencesDocument>,
) -> ffi::CorePreferencesResult {
    match result {
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

    match with_core(app_support_dir, |core| core.update_preferences(preferences)) {
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
    match with_core(app_support_dir, |core| core.run_maintenance()) {
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
    match with_core(app_support_dir, |core| core.list_pinboards()) {
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
    match with_core(app_support_dir, |core| {
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
    match with_core(app_support_dir, |core| {
        core.rename_pinboard(pinboard_id, title).map(|_| ())
    }) {
        Ok(()) => item_management_result(ItemManagementResult { affected_count: 1 }),
        Err(error) => item_management_error_result(error),
    }
}

fn rename_item(
    app_support_dir: String,
    item_id: String,
    title: String,
) -> ffi::CoreItemManagementResult {
    match with_core(app_support_dir, |core| core.rename_item(item_id, title)) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn update_pinboard_color(
    app_support_dir: String,
    pinboard_id: String,
    color_code: i64,
) -> ffi::CoreItemManagementResult {
    match with_core(app_support_dir, |core| {
        core.update_pinboard_color(pinboard_id, color_code)
            .map(|_| ())
    }) {
        Ok(()) => item_management_result(ItemManagementResult { affected_count: 1 }),
        Err(error) => item_management_error_result(error),
    }
}

fn delete_pinboard(app_support_dir: String, pinboard_id: String) -> ffi::CoreItemManagementResult {
    match with_core(app_support_dir, |core| core.delete_pinboard(pinboard_id)) {
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
    match with_core(app_support_dir, |core| {
        core.set_item_pinboard_membership(item_id, pinboard_id, is_member)
    }) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn export_backup(app_support_dir: String, path: String) -> ffi::CoreBackupResult {
    backup_result(
        with_core_without_maintenance(app_support_dir, |core| core.export_backup(path)),
    )
}

fn import_backup(app_support_dir: String, path: String) -> ffi::CoreBackupResult {
    backup_result(
        with_core_without_maintenance(app_support_dir, |core| core.import_backup(path)),
    )
}

fn backup_result(
    result: clipboard_core::Result<clipboard_core::BackupResult>,
) -> ffi::CoreBackupResult {
    match result {
        Ok(result) => ffi::CoreBackupResult {
            ok: true,
            exported_count: result.exported_count,
            imported_count: result.imported_count,
            skipped_count: result.skipped_count,
            error_code: String::new(),
            message: String::new(),
        },
        Err(error) => ffi::CoreBackupResult {
            ok: false,
            exported_count: 0,
            imported_count: 0,
            skipped_count: 0,
            error_code: error.code.as_str().into(),
            message: error.message,
        },
    }
}

fn delete_item(app_support_dir: String, item_id: String) -> ffi::CoreItemManagementResult {
    match with_core(app_support_dir, |core| core.delete_item(item_id)) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn record_item_copied(app_support_dir: String, item_id: String) -> ffi::CoreItemManagementResult {
    match with_core(app_support_dir, |core| core.record_item_copied(item_id)) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn update_source_app_icon_header_color(
    app_support_dir: String,
    source_app_id: String,
    source_app_icon_path: String,
    header_color_argb: i64,
    allow_latest_without_path: bool,
) -> ffi::CoreItemManagementResult {
    match with_core(app_support_dir, |core| {
        core.update_source_app_icon_header_color(
            source_app_id,
            source_app_icon_path,
            header_color_argb,
            allow_latest_without_path,
        )
    }) {
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

    match with_core(app_support_dir, |core| core.clear_items(query)) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn claim_link_metadata_fetch_batch(
    app_support_dir: String,
    limit: i64,
    lease_timeout_ms: i64,
) -> ffi::CoreLinkMetadataFetchBatchResult {
    match with_core(app_support_dir, |core| {
        core.claim_link_metadata_fetch_batch(limit, lease_timeout_ms)
    }) {
        Ok(candidates) => link_metadata_fetch_batch_result(candidates),
        Err(error) => ffi::CoreLinkMetadataFetchBatchResult {
            ok: false,
            candidates_json: "[]".to_string(),
            error_code: error.code.as_str().to_string(),
            message_key: error.message_key().to_string(),
        },
    }
}

fn complete_link_metadata_fetch(
    app_support_dir: String,
    request_json: String,
) -> ffi::CoreItemManagementResult {
    let request = match serde_json::from_str::<CompleteLinkMetadataFetchRequest>(&request_json) {
        Ok(request) => request,
        Err(_error) => {
            return ffi::CoreItemManagementResult {
                ok: false,
                affected_count: 0,
                error_code: "invalid_input".to_string(),
                message_key: "clipboard.error.invalid_input".to_string(),
            };
        }
    };

    match with_core(app_support_dir, |core| {
        core.complete_link_metadata_fetch(request)
    }) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn fail_link_metadata_fetch(
    app_support_dir: String,
    item_id: String,
    lease_started_at_ms: i64,
    failure_code: String,
    next_retry_at_ms: i64,
) -> ffi::CoreItemManagementResult {
    match with_core(app_support_dir, |core| {
        core.fail_link_metadata_fetch(
            item_id,
            lease_started_at_ms,
            failure_code,
            optional_i64(next_retry_at_ms),
        )
    }) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn link_metadata_fetch_batch_result(
    candidates: Vec<LinkMetadataFetchCandidate>,
) -> ffi::CoreLinkMetadataFetchBatchResult {
    ffi::CoreLinkMetadataFetchBatchResult {
        ok: true,
        candidates_json: serde_json::to_string(&candidates).unwrap_or_else(|_| "[]".to_string()),
        error_code: String::new(),
        message_key: String::new(),
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
    open_response(with_core(app_support_dir, |core| core.info()))
}

fn open_core_without_maintenance(app_support_dir: String) -> ffi::CoreOpenResult {
    open_response(with_core_without_maintenance(app_support_dir, |core| {
        core.info()
    }))
}

fn open_response(result: clipboard_core::Result<clipboard_core::CoreInfo>) -> ffi::CoreOpenResult {
    match result {
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
    }
}

fn active_source_icon_header_color_cache_version() -> i64 {
    ClipboardCore::active_source_icon_header_color_cache_version()
}

fn blake3_digest(bytes: &[u8]) -> String {
    blake3::hash(bytes).to_hex().to_string()
}

fn encode_webp_lossless_rgba(rgba: &[u8], width: i64, height: i64) -> ffi::CoreWebPEncodeResult {
    let width = match u32::try_from(width) {
        Ok(width) if width > 0 => width,
        _ => return webp_encode_error("invalid_input"),
    };
    let height = match u32::try_from(height) {
        Ok(height) if height > 0 => height,
        _ => return webp_encode_error("invalid_input"),
    };
    let expected_len = match (width as usize)
        .checked_mul(height as usize)
        .and_then(|pixel_count| pixel_count.checked_mul(4))
    {
        Some(expected_len) => expected_len,
        None => return webp_encode_error("invalid_input"),
    };
    if rgba.len() != expected_len {
        return webp_encode_error("invalid_input");
    }

    let encoder = webp::Encoder::from_rgba(rgba, width, height);
    let encoded = encoder.encode_lossless();
    let bytes = encoded.to_vec();
    if bytes.is_empty() {
        return webp_encode_error("encoding_failed");
    }

    ffi::CoreWebPEncodeResult {
        ok: true,
        bytes,
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn encode_adaptive_thumbnail_webp_rgba(
    rgba: &[u8],
    width: i64,
    height: i64,
    normal_target_bytes: i64,
    detail_target_bytes: i64,
    max_bytes: i64,
) -> ffi::CoreAdaptiveWebPEncodeResult {
    let width = match u32::try_from(width) {
        Ok(width) if width > 0 => width,
        _ => return adaptive_webp_encode_error("invalid_input"),
    };
    let height = match u32::try_from(height) {
        Ok(height) if height > 0 => height,
        _ => return adaptive_webp_encode_error("invalid_input"),
    };
    let normal_target = match usize::try_from(normal_target_bytes) {
        Ok(value) if value > 0 => value,
        _ => return adaptive_webp_encode_error("invalid_input"),
    };
    let detail_target = match usize::try_from(detail_target_bytes) {
        Ok(value) if value >= normal_target => value,
        _ => return adaptive_webp_encode_error("invalid_input"),
    };
    let max_bytes = match usize::try_from(max_bytes) {
        Ok(value) if value >= detail_target => value,
        _ => return adaptive_webp_encode_error("invalid_input"),
    };
    let expected_len = match (width as usize)
        .checked_mul(height as usize)
        .and_then(|pixel_count| pixel_count.checked_mul(4))
    {
        Some(expected_len) => expected_len,
        None => return adaptive_webp_encode_error("invalid_input"),
    };
    if rgba.len() != expected_len {
        return adaptive_webp_encode_error("invalid_input");
    }

    match clipdock_thumbnail_codec::encode_adaptive_thumbnail_webp_rgba(
        rgba,
        width,
        height,
        normal_target,
        detail_target,
        max_bytes,
    ) {
        Ok(Some(candidate)) => ffi::CoreAdaptiveWebPEncodeResult {
            ok: true,
            bytes: candidate.bytes,
            width: candidate.width as i64,
            height: candidate.height as i64,
            quality: i64::from(candidate.quality),
            score: candidate.score,
            selected_tier: candidate.tier,
            error_code: String::new(),
            message_key: String::new(),
        },
        Ok(None) => adaptive_webp_encode_error("no_candidate"),
        Err(code) => adaptive_webp_encode_error(code),
    }
}

fn webp_encode_error(code: &str) -> ffi::CoreWebPEncodeResult {
    ffi::CoreWebPEncodeResult {
        ok: false,
        bytes: Vec::new(),
        error_code: code.to_string(),
        message_key: "clipboard.error.image_encoding_failed".to_string(),
    }
}

fn adaptive_webp_encode_error(code: &str) -> ffi::CoreAdaptiveWebPEncodeResult {
    ffi::CoreAdaptiveWebPEncodeResult {
        ok: false,
        bytes: Vec::new(),
        width: 0,
        height: 0,
        quality: 0,
        score: 0.0,
        selected_tier: String::new(),
        error_code: code.to_string(),
        message_key: "clipboard.error.image_encoding_failed".to_string(),
    }
}

fn rasterize_svg_to_png(
    svg: &[u8],
    max_width: i64,
    max_height: i64,
) -> ffi::CoreSvgRasterizeResult {
    const MAX_SVG_BYTES: usize = 512 * 1024;
    const MAX_RASTER_EDGE: u32 = 1024;

    let max_width = match u32::try_from(max_width) {
        Ok(value) if value > 0 => value.min(MAX_RASTER_EDGE),
        _ => return svg_rasterize_error("invalid_input"),
    };
    let max_height = match u32::try_from(max_height) {
        Ok(value) if value > 0 => value.min(MAX_RASTER_EDGE),
        _ => return svg_rasterize_error("invalid_input"),
    };
    if svg.is_empty() || svg.len() > MAX_SVG_BYTES {
        return svg_rasterize_error("invalid_input");
    }

    match rasterize_svg_to_png_impl(svg, max_width, max_height) {
        Ok((bytes, width, height)) => ffi::CoreSvgRasterizeResult {
            ok: true,
            bytes,
            width: i64::from(width),
            height: i64::from(height),
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(code) => svg_rasterize_error(code),
    }
}

fn rasterize_svg_to_png_impl(
    svg: &[u8],
    max_width: u32,
    max_height: u32,
) -> Result<(Vec<u8>, u32, u32), &'static str> {
    let mut options = resvg::usvg::Options::default();
    options.resources_dir = None;
    options.image_href_resolver = resvg::usvg::ImageHrefResolver {
        resolve_data: resvg::usvg::ImageHrefResolver::default_data_resolver(),
        resolve_string: Box::new(|_, _| None),
    };

    let tree = resvg::usvg::Tree::from_data(svg, &options).map_err(|_| "invalid_svg")?;
    let svg_size = tree.size();
    let source_width = svg_size.width();
    let source_height = svg_size.height();
    if !source_width.is_finite()
        || !source_height.is_finite()
        || source_width <= 0.0
        || source_height <= 0.0
    {
        return Err("invalid_svg");
    }

    let scale = (max_width as f32 / source_width)
        .min(max_height as f32 / source_height)
        .min(1.0);
    let width = ((source_width * scale).ceil() as u32).clamp(1, max_width);
    let height = ((source_height * scale).ceil() as u32).clamp(1, max_height);
    let mut pixmap = resvg::tiny_skia::Pixmap::new(width, height).ok_or("rasterize_failed")?;
    let transform = resvg::tiny_skia::Transform::from_scale(
        width as f32 / source_width,
        height as f32 / source_height,
    );
    resvg::render(&tree, transform, &mut pixmap.as_mut());
    let bytes = pixmap.encode_png().map_err(|_| "encoding_failed")?;
    if bytes.is_empty() {
        return Err("encoding_failed");
    }
    Ok((bytes, width, height))
}

fn svg_rasterize_error(code: &str) -> ffi::CoreSvgRasterizeResult {
    ffi::CoreSvgRasterizeResult {
        ok: false,
        bytes: Vec::new(),
        width: 0,
        height: 0,
        error_code: code.to_string(),
        message_key: "clipboard.error.image_encoding_failed".to_string(),
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
    display_rtf_relative_path: String,
    display_rtf_mime_type: String,
    display_rtf_byte_count: i64,
    source_bundle_id: String,
    source_app_name: String,
    source_bundle_path: String,
    source_icon_relative_path: String,
    source_confidence: String,
    pasteboard_change_count: i64,
    self_write_token: String,
) -> ffi::CoreCaptureResult {
    match with_core(app_support_dir, |core| {
        core.capture_text(CaptureTextRequest {
            text,
            detected_link: capture_detected_link(
                link_original_text,
                link_canonical_url,
                link_display_url,
                link_host,
                link_metadata_state,
            ),
            display_rtf_relative_path: optional_string(display_rtf_relative_path),
            display_rtf_mime_type: optional_string(display_rtf_mime_type),
            display_rtf_byte_count,
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

fn capture_rich_text(app_support_dir: String, request_json: String) -> ffi::CoreCaptureResult {
    let request = match serde_json::from_str::<CaptureRichTextRequest>(&request_json) {
        Ok(request) => request,
        Err(_) => {
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

    match with_core(app_support_dir, |core| core.capture_rich_text(request)) {
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
    match with_core(app_support_dir, |core| {
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

fn capture_pending_image(
    app_support_dir: String,
    request_json: String,
) -> ffi::CorePendingImageResult {
    let request = match serde_json::from_str::<CapturePendingImageRequest>(&request_json) {
        Ok(request) => request,
        Err(_) => return pending_image_error_result("invalid_input"),
    };

    match with_core(app_support_dir, |core| core.capture_pending_image(request)) {
        Ok(result) => pending_image_capture_result(result),
        Err(error) => pending_image_core_error_result(error),
    }
}

fn complete_pending_image_payload(
    app_support_dir: String,
    request_json: String,
) -> ffi::CorePendingImageResult {
    let request = match serde_json::from_str::<CompletePendingImagePayloadRequest>(&request_json) {
        Ok(request) => request,
        Err(_) => return pending_image_error_result("invalid_input"),
    };

    match with_core(app_support_dir, |core| {
        core.complete_pending_image_payload(request)
    }) {
        Ok(result) => pending_image_completion_result(result),
        Err(error) => pending_image_core_error_result(error),
    }
}

fn fail_pending_image_payload(
    app_support_dir: String,
    request_json: String,
) -> ffi::CorePendingImageResult {
    let request = match serde_json::from_str::<FailPendingImagePayloadRequest>(&request_json) {
        Ok(request) => request,
        Err(_) => return pending_image_error_result("invalid_input"),
    };

    match with_core(app_support_dir, |core| {
        core.fail_pending_image_payload(request)
    }) {
        Ok(result) => pending_image_completion_result(result),
        Err(error) => pending_image_core_error_result(error),
    }
}

fn recover_pending_images(
    app_support_dir: String,
    request_json: String,
) -> ffi::CoreItemManagementResult {
    let request = match serde_json::from_str::<RecoverPendingImagesRequest>(&request_json) {
        Ok(request) => request,
        Err(_) => {
            return ffi::CoreItemManagementResult {
                ok: false,
                affected_count: 0,
                error_code: "invalid_input".to_string(),
                message_key: "clipboard.error.invalid_input".to_string(),
            };
        }
    };

    match with_core(app_support_dir, |core| core.recover_pending_images(request)) {
        Ok(result) => item_management_result(result),
        Err(error) => item_management_error_result(error),
    }
}

fn pending_image_capture_result(result: PendingImageCaptureResult) -> ffi::CorePendingImageResult {
    ffi::CorePendingImageResult {
        ok: true,
        result_json: serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string()),
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn pending_image_completion_result(
    result: PendingImageCompletionResult,
) -> ffi::CorePendingImageResult {
    ffi::CorePendingImageResult {
        ok: true,
        result_json: serde_json::to_string(&result).unwrap_or_else(|_| "{}".to_string()),
        error_code: String::new(),
        message_key: String::new(),
    }
}

fn pending_image_error_result(code: &str) -> ffi::CorePendingImageResult {
    ffi::CorePendingImageResult {
        ok: false,
        result_json: "{}".to_string(),
        error_code: code.to_string(),
        message_key: "clipboard.error.invalid_input".to_string(),
    }
}

fn pending_image_core_error_result(
    error: clipboard_core::CoreError,
) -> ffi::CorePendingImageResult {
    ffi::CorePendingImageResult {
        ok: false,
        result_json: "{}".to_string(),
        error_code: error.code.as_str().to_string(),
        message_key: error.message_key().to_string(),
    }
}

fn capture_files(
    app_support_dir: String,
    files_json: String,
    preview_relative_path: String,
    preview_mime_type: String,
    preview_width: i64,
    preview_height: i64,
    preview_byte_count: i64,
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

    match with_core(app_support_dir, |core| {
        core.capture_files(CaptureFilesRequest {
            file_paths,
            file_items,
            preview_relative_path: optional_string(preview_relative_path),
            preview_mime_type: optional_string(preview_mime_type),
            preview_width: optional_i64(preview_width),
            preview_height: optional_i64(preview_height),
            preview_byte_count,
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

fn json_response<T: Serialize>(result: clipboard_core::Result<T>) -> ffi::CoreJSONResult {
    match result.and_then(|value| {
        serde_json::to_string(&value)
            .map_err(|error| CoreError::new(CoreErrorCode::InvalidInput, error.to_string()))
    }) {
        Ok(result_json) => ffi::CoreJSONResult {
            ok: true,
            result_json,
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(error) => ffi::CoreJSONResult {
            ok: false,
            result_json: "null".into(),
            error_code: error.code.as_str().into(),
            message_key: error.message_key().into(),
        },
    }
}

fn evaluate_capture_policy_json(request_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<clipboard_core::CapturePolicyInput>(&request_json)
            .and_then(|input| clipboard_core::evaluate_capture_policy(&input)),
    )
}

fn metadata_url_policy_json(request_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<clipboard_core::metadata::MetadataURLFacts>(&request_json)
            .map(|facts| clipboard_core::metadata::metadata_url_policy(&facts)),
    )
}
fn metadata_limits_json(request_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<clipboard_core::metadata::MetadataCompatibilityProfile>(&request_json)
            .map(clipboard_core::metadata::metadata_limits),
    )
}
fn metadata_retry_at_json(request_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<clipboard_core::metadata::MetadataRetryRequest>(&request_json).map(
            |request| {
                clipboard_core::metadata::metadata_retry_at_ms(
                    request.fetch_attempts,
                    request.now_ms,
                )
            },
        ),
    )
}
fn parse_metadata_html_json(request_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<clipboard_core::metadata::MetadataHTMLRequest>(&request_json).map(
            |request| {
                clipboard_core::metadata::parse_metadata_html(
                    &request.html,
                    &request.base_url,
                    request.profile,
                )
            },
        ),
    )
}

fn plan_copy_json(request_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<clipboard_core::copy_plan::CopyPlanRequest>(&request_json)
            .and_then(clipboard_core::copy_plan::plan_copy),
    )
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AnalyzeCaptureTextRequest {
    text: String,
    native_link_hint: Option<CaptureDetectedLink>,
}

fn analyze_capture_text_json(request_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<AnalyzeCaptureTextRequest>(&request_json).and_then(|input| {
            clipboard_core::analyze_capture_text(&input.text, input.native_link_hint)
        }),
    )
}

fn decode_json<T: serde::de::DeserializeOwned>(json: &str) -> clipboard_core::Result<T> {
    serde_json::from_str(json)
        .map_err(|error| CoreError::new(CoreErrorCode::InvalidInput, error.to_string()))
}

fn patch_preferences(app_support_dir: String, patch_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<PreferencesPatch>(&patch_json).and_then(|patch| {
            with_core_without_maintenance(app_support_dir, |core| core.patch_preferences(patch))
        }),
    )
}

fn get_item(app_support_dir: String, item_id: String) -> ffi::CoreJSONResult {
    json_response(with_core(app_support_dir, |core| core.get_item(&item_id)))
}

fn get_items(app_support_dir: String, ordered_ids_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<Vec<String>>(&ordered_ids_json).and_then(|ids| {
            validate_batch_size(ids.len())?;
            with_core(app_support_dir, |core| core.get_items(ids))
        }),
    )
}

fn mutate_items(app_support_dir: String, requests_json: String) -> ffi::CoreJSONResult {
    json_response(
        decode_json::<Vec<ItemMutation>>(&requests_json).and_then(|requests| {
            validate_batch_size(requests.len())?;
            with_core_batch(app_support_dir, |core| core.mutate_items(requests))
        }),
    )
}

fn validate_batch_size(count: usize) -> clipboard_core::Result<()> {
    if count > clipboard_core::MAX_ITEM_BATCH_SIZE {
        Err(CoreError::new(
            CoreErrorCode::InvalidInput,
            "at most 200 requests are allowed",
        ))
    } else {
        Ok(())
    }
}

fn list_entries(
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
    let result = with_core(app_support_dir, |core| {
        core.list_entries(query, PageRequest { limit, offset })
    })
    .and_then(|page| {
        serde_json::to_string(&page.items)
            .map(|json| (page, json))
            .map_err(|error| CoreError::new(CoreErrorCode::InvalidInput, error.to_string()))
    });
    match result {
        Ok((page, items_json)) => ffi::CoreListResult {
            ok: true,
            total_count: page.total_count,
            has_more: page.has_more,
            items_json,
            error_code: String::new(),
            message_key: String::new(),
        },
        Err(error) => ffi::CoreListResult {
            ok: false,
            total_count: 0,
            has_more: false,
            items_json: "[]".into(),
            error_code: error.code.as_str().into(),
            message_key: error.message_key().into(),
        },
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

    match with_core(app_support_dir, |core| {
        core.list_items(query, PageRequest { limit, offset })
    }) {
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
    match with_core(app_support_dir, |core| {
        core.list_source_apps(PageRequest { limit, offset })
    }) {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pure_policy_analysis_and_copy_plan_contracts_never_enter_a_core_session() {
        let sessions_before = sessions::session_access_count();
        let mut input = serde_json::json!({"profile":"mac_os_v1", "source_candidate_keys":["editor"],
            "application_rule_keys":["", "editor"], "skip_unknown_source":true,
            "source_confidence":"low", "has_owner":false, "title_match_index":0, "title_rule_count":1});
        let result = evaluate_capture_policy_json(input.to_string());
        assert!(result.ok);
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&result.result_json).unwrap(),
            serde_json::json!({"skip":true,"reason":"source_application","matched_rule_index":1})
        );
        input["title_match_index"] = serde_json::json!(1);
        let invalid = evaluate_capture_policy_json(input.to_string());
        assert!(!invalid.ok);
        assert_eq!(invalid.error_code, "invalid_input");
        let text =
            analyze_capture_text_json(r##"{"text":" #ff00aa ","native_link_hint":null}"##.into());
        assert!(text.ok);
        let analysis: serde_json::Value = serde_json::from_str(&text.result_json).unwrap();
        assert_eq!(analysis["item_type"], "color");
        assert_eq!(analysis["primary_text"], "#FF00AA");
        assert!(analysis["detected_link"].is_null());
        assert!(!analyze_capture_text_json(r#"{"text":" ","native_link_hint":null}"#.into()).ok);
        let copy = plan_copy_json(
            serde_json::json!({"ordered_ids":[],"mode":"original",
            "capabilities":"mac_os_v1","items":[],"file_facts":[]})
            .to_string(),
        );
        assert!(copy.ok);
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&copy.result_json).unwrap()["reason"],
            "empty_selection"
        );
        assert_eq!(sessions::session_access_count(), sessions_before);
    }

    pub(super) fn synthetic_text(path: &std::path::Path, body: &str) -> String {
        ClipboardCore::open(path)
            .unwrap()
            .capture_text(CaptureTextRequest {
                text: body.into(),
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
    fn list_lookup_and_batch_json_contracts_preserve_complete_text() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().display().to_string();
        let body = "synthetic ".repeat(150);
        let id = synthetic_text(root.path(), &body);
        let list = list_entries(
            path.clone(),
            50,
            0,
            String::new(),
            String::new(),
            String::new(),
            String::new(),
        );
        assert!(list.ok);
        let rows: serde_json::Value = serde_json::from_str(&list.items_json).unwrap();
        assert!(rows[0]["primary_text"].is_null());
        assert_eq!(
            rows[0]["text_preview"]
                .as_str()
                .unwrap()
                .encode_utf16()
                .count(),
            500
        );
        let lookup = get_items(
            path.clone(),
            serde_json::json!([id, "missing", id]).to_string(),
        );
        assert!(lookup.ok);
        let rows: serde_json::Value = serde_json::from_str(&lookup.result_json).unwrap();
        assert_eq!(rows[0]["item"]["primary_text"], body.trim());
        assert_eq!(rows[0], rows[2]);
        assert!(rows[1]["item"].is_null());
        let batch = mutate_items(
            path.clone(),
            serde_json::json!([
            {"kind":"record_copied","item_id":id}, {"kind":"delete","item_id":" "},
            {"kind":"record_copied","item_id":id}])
            .to_string(),
        );
        assert!(batch.ok);
        let result: serde_json::Value = serde_json::from_str(&batch.result_json).unwrap();
        assert_eq!(result["outcomes"][1]["status"], "failed");
        assert_eq!(result["outcomes"][2]["request_index"], 2);
        let item: serde_json::Value =
            serde_json::from_str(&get_item(path.clone(), id).result_json).unwrap();
        assert_eq!(item["copy_count"], 3);
        assert!(!mutate_items(path.clone(), "[{\"kind\":\"unknown\"}]".into()).ok);
        assert!(
            !get_items(
                path,
                serde_json::to_string(&vec!["synthetic"; 201]).unwrap()
            )
            .ok
        );
    }

    #[test]
    fn cold_and_cached_preferences_work_when_history_cleanup_fails() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().display().to_string();
        let id = synthetic_text(root.path(), "maintenance fixture");
        let connection =
            rusqlite::Connection::open(root.path().join(clipboard_core::DATABASE_FILE_NAME))
                .unwrap();
        connection
            .execute(
                "UPDATE clipboard_items SET last_copied_at_ms=1 WHERE id=?1",
                [&id],
            )
            .unwrap();
        connection
            .execute(
                "INSERT INTO clipboard_assets(id,item_id,kind,relative_path,created_at_ms)
            VALUES ('block',?1,'payload','assets/block/child',1)",
                [&id],
            )
            .unwrap();
        std::fs::write(root.path().join("assets/block"), b"fixture").unwrap();
        assert!(!open_core(path.clone()).ok);
        assert!(open_core_without_maintenance(path.clone()).ok);
        for _ in 0..2 {
            assert!(get_preferences_without_maintenance(path.clone()).ok);
        }
        let saved = patch_preferences(path.clone(), "{\"appearance\":{\"mode\":\"dark\"}}".into());
        assert!(saved.ok);
        let result: serde_json::Value = serde_json::from_str(&saved.result_json).unwrap();
        assert_eq!(result["document"]["appearance"]["mode"], "dark");
        assert_eq!(result["maintenance"]["status"], "not_needed");
        // Re-arm expiration: the failed open already committed its soft delete.
        connection
            .execute(
                "UPDATE clipboard_items SET deleted_at_ms=NULL WHERE id=?1",
                [&id],
            )
            .unwrap();
        let warning =
            patch_preferences(path.clone(), "{\"history\":{\"retention_days\":7}}".into());
        assert!(warning.ok);
        let result: serde_json::Value = serde_json::from_str(&warning.result_json).unwrap();
        assert_eq!(result["maintenance"]["status"], "warning");
        assert!(get_preferences_without_maintenance(path).ok);
        let broken = tempfile::tempdir().unwrap();
        std::fs::write(
            broken.path().join(clipboard_core::DATABASE_FILE_NAME),
            b"not a sqlite database",
        )
        .unwrap();
        assert!(!open_core_without_maintenance(broken.path().display().to_string()).ok);
    }

    #[test]
    fn rasterizes_static_svg_to_png() {
        let svg = br##"
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
          <rect width="512" height="512" fill="#1A5FB8" rx="112"/>
          <rect x="84" y="126" width="222" height="64" fill="#FFFFFF" rx="24"/>
        </svg>
        "##;

        let result = rasterize_svg_to_png(svg, 128, 128);

        assert!(result.ok, "{}", result.error_code);
        assert_eq!(result.width, 128);
        assert_eq!(result.height, 128);
        assert_eq!(&result.bytes[..8], b"\x89PNG\r\n\x1a\n");
    }

    #[test]
    fn rasterize_svg_rejects_oversized_input() {
        let oversized_svg = vec![b' '; 512 * 1024 + 1];

        let result = rasterize_svg_to_png(&oversized_svg, 128, 128);

        assert!(!result.ok);
        assert_eq!(result.error_code, "invalid_input");
        assert!(result.bytes.is_empty());
    }

    #[test]
    fn rasterize_svg_ignores_external_image_references() {
        let svg = br##"
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">
          <rect width="128" height="128" fill="#1A5FB8"/>
          <image href="file:///etc/passwd" x="0" y="0" width="128" height="128"/>
        </svg>
        "##;

        let result = rasterize_svg_to_png(svg, 128, 128);

        assert!(result.ok, "{}", result.error_code);
        assert_eq!(result.width, 128);
        assert_eq!(result.height, 128);
    }
}
