use serde::{Deserialize, Serialize};

use crate::domain::quality::{DataQuality, SCHEMA_VERSION};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HealthResponse {
    pub status: String,
    pub database: bool,
    pub live: bool,
    pub version: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Meta {
    pub schema_version: u32,
    pub revision: u64,
    pub stale: bool,
    pub quality: DataQuality,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fetched_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_updated_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sync_status: Option<SyncStatus>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SyncStatus {
    pub last_attempt_at: String,
    pub last_success_at: Option<String>,
    pub next_retry_at: Option<String>,
    pub last_error: Option<String>,
    pub retry_count: u32,
    pub schedule_note: Option<String>,
}

impl Meta {
    pub fn empty() -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            revision: 0,
            stale: true,
            quality: DataQuality::Pending,
            source: None,
            fetched_at: None,
            source_updated_at: None,
            sync_status: None,
        }
    }

    pub fn from_cache(
        source: Option<String>,
        fetched_at: Option<String>,
        revision: u64,
        stale: bool,
    ) -> Self {
        Self {
            schema_version: SCHEMA_VERSION,
            revision,
            stale,
            quality: if stale {
                DataQuality::Stale
            } else {
                DataQuality::Provisional
            },
            source,
            fetched_at,
            // Provider update time is unknown unless explicitly supplied by the provider.
            source_updated_at: None,
            sync_status: None,
        }
    }
}
