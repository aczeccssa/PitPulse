use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LiveStatus {
    Connected,
    Stale,
    Disconnected,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveDriver {
    pub number: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub team: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub position: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub gap: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub interval: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lap_count: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_lap: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub best_lap: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LiveSnapshot {
    pub schema_version: u32,
    pub state_version: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    pub session_name: Option<String>,
    pub source_status: LiveStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub track_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    pub drivers: Vec<LiveDriver>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub race_control: Option<Vec<serde_json::Value>>,
}

impl Default for LiveSnapshot {
    fn default() -> Self {
        Self {
            schema_version: 1,
            state_version: 0,
            session_id: None,
            session_name: None,
            source_status: LiveStatus::Disconnected,
            status_reason: Some("not_connected".to_string()),
            track_status: None,
            updated_at: None,
            drivers: Vec::new(),
            race_control: None,
        }
    }
}
