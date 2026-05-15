mod domain;
mod error;
mod migrations;
mod storage;
mod time;

pub use domain::{
    CaptureDetectedLink, CaptureFilesRequest, CaptureImageRequest, CaptureResult,
    CaptureTextRequest, CapturedFileMetadata, ClipboardFileItemSummary, ClipboardItemSummary,
    ClipboardItemType, CompleteLinkMetadataFetchRequest, CoreInfo, ItemManagementResult, ItemPage,
    ItemQuery, LinkMetadataFetchCandidate, LinkMetadataState, LinkMetadataSummary,
    MaintenanceResult, PageRequest, PinboardPage, PinboardSummary, PreferencesDocument,
    PreviewState, SourceAppPage, SourceAppSummary, SourceConfidence,
};
pub use error::{CoreError, CoreErrorCode, Result};
pub use storage::ClipboardCore;

pub const DATABASE_FILE_NAME: &str = "clipboard.sqlite";
pub const CURRENT_SCHEMA_VERSION: i64 = 8;
pub const ACTIVE_SOURCE_ICON_HEADER_COLOR_CACHE_VERSION: i64 = 1;
