mod domain;
mod error;
mod migrations;
mod storage;
mod time;

pub use domain::{
    CaptureFilesRequest, CaptureImageRequest, CaptureResult, CaptureTextRequest,
    ClipboardItemSummary, ClipboardItemType, CoreInfo, ItemManagementResult, ItemPage, ItemQuery,
    MaintenanceResult, PageRequest, PreferencesDocument, PreviewState, SourceAppPage,
    SourceAppSummary, SourceConfidence,
};
pub use error::{CoreError, CoreErrorCode, Result};
pub use storage::ClipboardCore;

pub const DATABASE_FILE_NAME: &str = "clipboard.sqlite";
pub const CURRENT_SCHEMA_VERSION: i64 = 1;
