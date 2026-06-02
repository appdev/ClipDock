mod domain;
mod error;
mod migrations;
mod storage;
mod time;

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
pub use error::{CoreError, CoreErrorCode, Result};
pub use storage::ClipboardCore;

pub const DATABASE_FILE_NAME: &str = "clipboard.sqlite";
pub const CURRENT_SCHEMA_VERSION: i64 = 13;
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
