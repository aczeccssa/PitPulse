use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionResult {
    pub session_id: String,
    pub position: i64,
    pub classification: String,
    pub driver_id: String,
    pub driver_name: String,
    pub team: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gap: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub laps: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub points: Option<f64>,
    pub source: String,
    pub source_updated_at: Option<String>,
    pub fetched_at: String,
    pub revision: i64,
    pub quality: String,
}
