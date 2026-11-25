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

    #[error("season data center unavailable")]
    SeasonUnavailable,

    #[error("season data configuration: {0}")]
    SeasonConfig(&'static str),

    #[error("season data operation failed (Postgres SQLSTATE {0})")]
    SeasonPostgres(String),

    #[error("season data import: {0}")]
    SeasonImport(String),

    #[error("season data is invalid")]
    SeasonDataInvalid,

    #[error("season data writer is disabled")]
    SeasonReadOnly,

    #[error("analysis cache entry is corrupted: {0}")]
    CorruptCache(String),
}

impl From<tokio_postgres::Error> for StorageError {
    fn from(error: tokio_postgres::Error) -> Self {
        // Do not propagate database diagnostics: payloads and authentication
        // details may appear in driver errors.
        match error.code().map(|code| code.code()) {
            None | Some("57014" | "57P01" | "57P02" | "57P03") => Self::SeasonUnavailable,
            Some(code) if code.starts_with("08") => Self::SeasonUnavailable,
            Some(code) => Self::SeasonPostgres(code.to_owned()),
        }
    }
}

impl IntoResponse for StorageError {
    fn into_response(self) -> Response {
        if matches!(self, Self::SeasonUnavailable) {
            return (
                StatusCode::SERVICE_UNAVAILABLE,
                [(axum::http::header::RETRY_AFTER, "5")],
                Json(json!({"error": {"code": "season_data_unavailable", "message": "season data center unavailable"}})),
            ).into_response();
        }
        tracing::error!(error = %self, "storage operation failed");
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({"error": {"code": "database_error", "message": "database operation failed"}})),
        )
            .into_response()
    }
}

#[derive(Debug, Error)]
pub enum ProviderError {
    #[error("provider request failed for {url}: {error}")]
    Transport { url: String, error: String },

    #[error("provider returned HTTP {status} for {url}")]
    Http {
        url: String,
        status: u16,
        retry_after: Option<std::time::Duration>,
    },

    #[error("provider response could not be decoded for {url}: {error}")]
    Decode { url: String, error: String },

    #[error("invalid provider URL {url}: {error}")]
    InvalidUrl { url: String, error: String },

    #[error("provider pagination exceeded for {url}")]
    Pagination { url: String },

    #[error("provider payload missing required field {field}")]
    MissingField { field: String },
}

impl ProviderError {
    pub fn is_retryable(&self) -> bool {
        match self {
            Self::Transport { .. } | Self::Pagination { .. } => true,
            Self::Http { status, .. } => *status == 429 || (500..600).contains(status),
            _ => false,
        }
    }

    pub fn retry_after(&self) -> Option<std::time::Duration> {
        match self {
            Self::Http { retry_after, .. } => *retry_after,
            _ => None,
        }
    }
}

#[derive(Debug, Error)]
pub enum ApiError {
    #[error("resource not found")]
    NotFound,

    /// A section the product does not offer for this season. It is not a
    /// missing record: clients must hide the section instead of retrying.
    #[error("{section} is not offered before {first_season}")]
    NotOffered { section: String, first_season: i64 },

    #[error("invalid query parameter {field}: {error}")]
    InvalidQuery { field: String, error: String },

    #[error("refresh queue is full")]
    RefreshQueueFull,

    #[error("refresh scheduler is unavailable")]
    RefreshUnavailable,

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
            Self::NotOffered {
                section,
                first_season,
            } => (
                StatusCode::NOT_FOUND,
                Json(json!({"error": {
                    "code": "not_offered",
                    "section": section,
                    "firstSeason": first_season,
                    "message": format!("{section} is offered from {first_season} on")
                }})),
            )
                .into_response(),
            Self::RefreshQueueFull => (
                StatusCode::SERVICE_UNAVAILABLE,
                [(axum::http::header::RETRY_AFTER, "5")],
                Json(json!({"error": {"code": "refresh_queue_full", "message": "refresh queue is full"}})),
            )
                .into_response(),
            Self::RefreshUnavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"error": {"code": "refresh_unavailable", "message": "refresh scheduler is unavailable"}})),
            )
                .into_response(),
            Self::Storage(error) => error.into_response(),
        }
    }
}
