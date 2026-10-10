use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LiveStatus {
    Connected,
    Stale,
    Disconnected,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LiveSourceMode {
    #[default]
    Live,
    Replay,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveSector {
    pub value: Option<String>,
    pub personal_fastest: Option<bool>,
    pub overall_fastest: Option<bool>,
    pub segments: Vec<Option<i64>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sectors: Option<Vec<LiveSector>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub in_pit: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retired: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveSnapshot {
    pub schema_version: u32,
    pub state_version: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
    pub session_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub meeting_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country_code: Option<String>,
    pub source_status: LiveStatus,
    #[serde(default)]
    pub source_mode: LiveSourceMode,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub track_status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lap_count: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub total_laps: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub updated_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_transport_at: Option<String>,
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
            meeting_name: None,
            country_code: None,
            source_status: LiveStatus::Disconnected,
            source_mode: LiveSourceMode::Live,
            status_reason: Some("not_connected".to_string()),
            session_type: None,
            session_status: None,
            track_status: None,
            lap_count: None,
            total_laps: None,
            updated_at: None,
            last_transport_at: None,
            drivers: Vec::new(),
            race_control: None,
        }
    }
}
