use std::collections::BTreeMap;
use std::fmt;
use std::io;

pub type Result<T> = std::result::Result<T, CoreError>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoreErrorCode {
    DatabaseUnavailable,
    MigrationFailed,
    MigrationChecksumMismatch,
    InvalidInput,
    IoFailed,
    SearchFailed,
}

impl CoreErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::DatabaseUnavailable => "database_unavailable",
            Self::MigrationFailed => "migration_failed",
            Self::MigrationChecksumMismatch => "migration_checksum_mismatch",
            Self::InvalidInput => "invalid_input",
            Self::IoFailed => "io_failed",
            Self::SearchFailed => "search_failed",
        }
    }

    pub fn message_key(self) -> &'static str {
        match self {
            Self::DatabaseUnavailable => "clipboard.error.database_unavailable",
            Self::MigrationFailed => "clipboard.error.migration_failed",
            Self::MigrationChecksumMismatch => "clipboard.error.migration_checksum_mismatch",
            Self::InvalidInput => "clipboard.error.invalid_input",
            Self::IoFailed => "clipboard.error.io_failed",
            Self::SearchFailed => "clipboard.error.search_failed",
        }
    }

    pub fn recoverable(self) -> bool {
        matches!(
            self,
            Self::DatabaseUnavailable | Self::IoFailed | Self::SearchFailed
        )
    }
}

#[derive(Debug, Clone)]
pub struct CoreError {
    pub code: CoreErrorCode,
    pub message: String,
    pub details: BTreeMap<String, String>,
}

impl CoreError {
    pub fn new(code: CoreErrorCode, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
            details: BTreeMap::new(),
        }
    }

    pub fn with_detail(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.details.insert(key.into(), value.into());
        self
    }

    pub fn message_key(&self) -> &'static str {
        self.code.message_key()
    }

    pub fn recoverable(&self) -> bool {
        self.code.recoverable()
    }
}

impl fmt::Display for CoreError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code.as_str(), self.message)
    }
}

impl std::error::Error for CoreError {}

impl From<rusqlite::Error> for CoreError {
    fn from(error: rusqlite::Error) -> Self {
        Self::new(CoreErrorCode::DatabaseUnavailable, error.to_string())
    }
}

impl From<io::Error> for CoreError {
    fn from(error: io::Error) -> Self {
        Self::new(CoreErrorCode::IoFailed, error.to_string())
    }
}
