mod domain;
mod error;
mod migrations;
mod storage;
mod time;

pub use domain::{
    CaptureDetectedLink, CaptureFilesRequest, CaptureImageRequest, CaptureResult,
    CaptureTextRequest, CapturedFileMetadata, ClipboardFileItemSummary, ClipboardItemSummary,
    ClipboardItemType, CoreInfo, ItemManagementResult, ItemPage, ItemQuery, LinkMetadataState,
    LinkMetadataSummary, MaintenanceResult, PageRequest, PinboardPage, PinboardSummary,
    PreferencesDocument, PreviewState, SourceAppPage, SourceAppSummary, SourceConfidence,
};
pub use error::{CoreError, CoreErrorCode, Result};
pub use storage::ClipboardCore;

pub const DATABASE_FILE_NAME: &str = "clipboard.sqlite";
pub const CURRENT_SCHEMA_VERSION: i64 = 6;
