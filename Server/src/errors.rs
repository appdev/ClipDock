use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::Serialize;

use crate::PROTOCOL_VERSION;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("{0}")]
    BadRequest(&'static str),
    #[error("{0}")]
    Unauthorized(&'static str),
    #[error("{0}")]
    Forbidden(&'static str),
    #[error("{0}")]
    UnsupportedMediaType(&'static str),
    #[error("{0}")]
    Conflict(&'static str),
    #[error("{0}")]
    PayloadTooLarge(&'static str),
    #[error("{0}")]
    Internal(String),
}

impl AppError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::BadRequest(code)
            | Self::Unauthorized(code)
            | Self::Forbidden(code)
            | Self::UnsupportedMediaType(code)
            | Self::Conflict(code)
            | Self::PayloadTooLarge(code) => code,
            Self::Internal(_) => "internal_error",
        }
    }

    pub fn status(&self) -> StatusCode {
        match self {
            Self::BadRequest(_) => StatusCode::BAD_REQUEST,
            Self::Unauthorized(_) => StatusCode::UNAUTHORIZED,
            Self::Forbidden(_) => StatusCode::FORBIDDEN,
            Self::UnsupportedMediaType(_) => StatusCode::UNSUPPORTED_MEDIA_TYPE,
            Self::Conflict(_) => StatusCode::CONFLICT,
            Self::PayloadTooLarge(_) => StatusCode::PAYLOAD_TOO_LARGE,
            Self::Internal(_) => StatusCode::INTERNAL_SERVER_ERROR,
        }
    }
}

impl From<sqlx::Error> for AppError {
    fn from(value: sqlx::Error) -> Self {
        Self::Internal(value.to_string())
    }
}

impl From<std::io::Error> for AppError {
    fn from(value: std::io::Error) -> Self {
        Self::Internal(value.to_string())
    }
}

#[derive(Serialize)]
pub struct SuccessEnvelope<T: Serialize> {
    pub protocol_version: u8,
    pub data: T,
}

#[derive(Serialize)]
pub struct ErrorEnvelope {
    pub protocol_version: u8,
    pub error: ErrorBody,
}

#[derive(Serialize)]
pub struct ErrorBody {
    pub code: &'static str,
    pub message: String,
}

pub fn ok<T: Serialize>(data: T) -> Json<SuccessEnvelope<T>> {
    Json(SuccessEnvelope {
        protocol_version: PROTOCOL_VERSION,
        data,
    })
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = self.status();
        let body = Json(ErrorEnvelope {
            protocol_version: PROTOCOL_VERSION,
            error: ErrorBody {
                code: self.code(),
                message: self.to_string(),
            },
        });
        (status, body).into_response()
    }
}
