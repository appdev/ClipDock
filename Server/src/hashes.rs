use std::fmt;

use crate::errors::AppError;

const BLAKE3_PREFIX: &str = "blake3:";
const HEX_LEN: usize = 64;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ContentHash {
    value: String,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AssetDigest {
    value: String,
    hex: String,
}

impl ContentHash {
    pub fn parse(value: &str) -> Result<Self, AppError> {
        validate_blake3_prefixed(value).map(|hex| Self {
            value: format!("{BLAKE3_PREFIX}{hex}"),
        })
    }

    pub fn is_valid(value: &str) -> bool {
        Self::parse(value).is_ok()
    }
}

impl AssetDigest {
    pub fn parse(value: &str) -> Result<Self, AppError> {
        validate_blake3_prefixed(value).map(|hex| Self {
            value: format!("{BLAKE3_PREFIX}{hex}"),
            hex: hex.to_string(),
        })
    }

    pub fn from_bytes(bytes: &[u8]) -> Self {
        let hex = blake3::hash(bytes).to_hex().to_string();
        Self {
            value: format!("{BLAKE3_PREFIX}{hex}"),
            hex,
        }
    }

    pub fn algorithm(&self) -> &'static str {
        "blake3"
    }

    pub fn hex(&self) -> &str {
        &self.hex
    }

    pub fn as_str(&self) -> &str {
        &self.value
    }
}

impl fmt::Display for AssetDigest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.value)
    }
}

fn validate_blake3_prefixed(value: &str) -> Result<&str, AppError> {
    let Some(hex) = value.strip_prefix(BLAKE3_PREFIX) else {
        return Err(AppError::BadRequest("invalid_digest_algorithm"));
    };
    if hex.len() != HEX_LEN {
        return Err(AppError::BadRequest("invalid_digest"));
    }
    if !hex
        .bytes()
        .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        return Err(AppError::BadRequest("invalid_digest"));
    }
    Ok(hex)
}
