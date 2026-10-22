pub mod capture_policy;
pub mod copy_plan;
mod domain;
mod error;
pub mod metadata;
mod migrations;
mod storage;
pub mod text_analysis;
mod time;

pub use capture_policy::{
    evaluate_capture_policy, normalize_windows_capture_key, windows_capture_source_keys,
    CapturePolicyDecision, CapturePolicyInput, CapturePolicyProfile, CapturePolicyReason,
};
pub use text_analysis::{analyze_capture_text, CaptureTextAnalysis};

pub use clipdock_asset_store::{AssetLifecycleGuard, AssetReservation, AssetStore};
pub use domain::MAX_ITEM_BATCH_SIZE;
pub use domain::{
    CaptureDetectedLink, CaptureFilesRequest, CaptureImageRequest, CapturePendingImageRequest,
    CaptureResult, CaptureRichTextRequest, CaptureTextRequest, CapturedFileMetadata,
    ClipboardFileItemSummary, ClipboardItemSummary, ClipboardItemType,
    CompleteLinkMetadataFetchRequest, CompletePendingImagePayloadRequest, CoreInfo,
    FailPendingImagePayloadRequest, ItemManagementResult, ItemPage, ItemQuery,
    LinkMetadataFetchCandidate, LinkMetadataState, LinkMetadataSummary, MaintenanceResult,
    PageRequest, PayloadState, PendingImageCaptureResult, PendingImageCompletionResult,
    PinboardPage, PinboardSummary, PreferencesDocument, PreviewState, RecoverPendingImagesRequest,
    SourceAppPage, SourceAppSummary, SourceConfidence,
};
pub use domain::{
    ClipboardListEntry, ItemBatchMutationResult, ItemLookupResult, ItemMutation, ItemMutationError,
    ItemMutationOutcome, ItemMutationStatus, ListEntryPage,
};
pub use error::{CoreError, CoreErrorCode, Result};
pub use storage::preferences_patch::*;
pub use storage::{BackupResult, ClipboardCore};

pub const DATABASE_FILE_NAME: &str = "clipboard.sqlite";
pub const CURRENT_SCHEMA_VERSION: i64 = 18;
pub const ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION: i64 = 1;

pub(crate) fn register_simple_tokenizer(connection: &rusqlite::Connection) -> Result<()> {
    sqlite_simple_tokenizer::load(connection).map_err(|error| {
        CoreError::new(
            CoreErrorCode::DatabaseUnavailable,
            "failed to register SQLite simple tokenizer",
        )
        .with_detail("source", format!("{error:?}"))
    })
}
