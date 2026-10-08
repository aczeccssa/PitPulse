use std::path::PathBuf;

use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("failed to read configuration file {path}: {error}")]
    Io {
        path: PathBuf,
        error: std::io::Error,
    },

    #[error("invalid configuration file {path}: {error}")]
    Parse {
        path: PathBuf,
        error: toml::de::Error,
    },

    #[error("invalid configuration value {field}: {error}")]
    InvalidValue { field: String, error: String },

    #[error("F1_COMPANION_TOKEN cannot be empty")]
    EmptyToken,

    #[error("security.require_token is enabled but F1_COMPANION_TOKEN is missing")]
    MissingRequiredToken,
}

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("database operation failed: {0}")]
    Sqlite(#[from] rusqlite::Error),

    #[error("database path unavailable: {0}")]
    Io(#[from] std::io::Error),

    #[error("blocking database task failed: {0}")]
    Task(#[from] tokio::task::JoinError),
}

impl IntoResponse for StorageError {
    fn into_response(self) -> Response {
        tracing::error!(error = %self, "storage operation failed");
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({"error": {"code": "database_error", "message": "database operation failed"}})),
        )
            .into_response()
    }
}

#[derive(Debug, Error)]
pub enum ApiError {
    #[error("resource not found")]
    NotFound,

    #[error("invalid query parameter {field}: {error}")]
    InvalidQuery { field: String, error: String },

    #[error("storage error: {0}")]
    Storage(#[from] StorageError),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        match self {
            Self::InvalidQuery { field, error } => (
                StatusCode::BAD_REQUEST,
                Json(json!({"error": {"code": "invalid_query", "field": field, "message": error}})),
            )
                .into_response(),
            Self::NotFound => (
                StatusCode::NOT_FOUND,
                Json(json!({"error": {"code": "not_found", "message": "resource not found"}})),
            )
                .into_response(),
            Self::Storage(error) => error.into_response(),
        }
    }
}
