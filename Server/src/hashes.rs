use std::fmt;

use crate::errors::AppError;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentHash {
    inner: clipdock_sync_contract::ContentHash,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AssetDigest {
    inner: clipdock_sync_contract::AssetDigest,
}

impl ContentHash {
    pub fn parse(value: &str) -> Result<Self, AppError> {
        clipdock_sync_contract::ContentHash::parse_strict(value)
            .map(|inner| Self { inner })
            .map_err(|error| AppError::BadRequest(error.code()))
    }

    pub fn is_valid(value: &str) -> bool {
        Self::parse(value).is_ok()
    }
}

impl AssetDigest {
    pub fn parse(value: &str) -> Result<Self, AppError> {
        clipdock_sync_contract::AssetDigest::parse_strict(value)
            .map(|inner| Self { inner })
            .map_err(|error| AppError::BadRequest(error.code()))
    }

    pub fn from_bytes(bytes: &[u8]) -> Self {
        Self {
            inner: clipdock_sync_contract::AssetDigest::from_bytes(bytes),
        }
    }

    pub fn algorithm(&self) -> &'static str {
        self.inner.algorithm()
    }

    pub fn hex(&self) -> &str {
        self.inner.hex()
    }

    pub fn as_str(&self) -> &str {
        self.inner.as_str()
    }
}

impl fmt::Display for AssetDigest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}
