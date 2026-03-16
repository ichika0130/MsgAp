use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

use crate::config;

// ── Error variants ────────────────────────────────────────────────────────────

#[derive(Debug)]
pub enum ValidationKind {
    InvalidCoords,
    ContentEmpty,
    ContentTooLong,
    InvalidRadius,
}

#[derive(Debug)]
pub enum AppError {
    Validation(ValidationKind),
    Database(#[allow(dead_code)] sqlx::Error),
    NotFound,
}

// ── IntoResponse — looks up the flavour text from the loaded config ───────────

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let strings = config::strings();

        let (status, message) = match self {
            AppError::Validation(kind) => {
                let msg = match kind {
                    ValidationKind::InvalidCoords  => &strings.errors.validation.invalid_coords,
                    ValidationKind::ContentEmpty   => &strings.errors.validation.content_empty,
                    ValidationKind::ContentTooLong => &strings.errors.validation.content_too_long,
                    ValidationKind::InvalidRadius  => &strings.errors.validation.invalid_radius,
                };
                (StatusCode::BAD_REQUEST, msg.clone())
            }
            AppError::Database(_) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                strings.errors.database.connection_lost.clone(),
            ),
            AppError::NotFound => (
                StatusCode::NOT_FOUND,
                strings.errors.database.not_found.clone(),
            ),
        };

        (status, Json(json!({ "error": message }))).into_response()
    }
}

// ── Conversion from sqlx errors ───────────────────────────────────────────────

impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self {
        if matches!(e, sqlx::Error::RowNotFound) {
            AppError::NotFound
        } else {
            AppError::Database(e)
        }
    }
}
