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

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveDriver {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub location: Option<LiveLocation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub telemetry: Option<LiveTelemetry>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub class_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub class_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub class_position: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub manufacturer: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tire_compound: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tire_age_laps: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub energy_percent: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveLocation {
    pub x: f64,
    pub y: f64,
    pub utc: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub received_at: Option<String>,
    pub status: Option<String>,
    pub longitude: Option<f64>,
    pub latitude: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveTelemetry {
    pub utc: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub received_at: Option<String>,
    pub rpm: Option<f64>,
    pub speed: Option<f64>,
    pub gear: Option<f64>,
    pub throttle: Option<f64>,
    pub brake: Option<f64>,
    pub drs: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct LivePositionDiagnostics {
    pub received: usize,
    pub decoded: usize,
    pub calibrated: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveWeather {
    pub utc: String,
    pub air_temp: Option<f64>,
    pub track_temp: Option<f64>,
    pub humidity: Option<f64>,
    pub pressure: Option<f64>,
    pub wind_speed: Option<f64>,
    pub wind_direction: Option<f64>,
    pub rainfall: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveRadio {
    pub id: String,
    pub utc: String,
    pub driver_number: String,
    #[serde(skip)]
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LiveSnapshot {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub series: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub circuit_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub circuit_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub weather: Option<LiveWeather>,
    #[serde(default)]
    pub team_radio: Vec<LiveRadio>,
    #[serde(skip)]
    pub session_path: Option<String>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub position_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub position_diagnostics: Option<LivePositionDiagnostics>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub time_remaining_seconds: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub elapsed_seconds: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_time_based: Option<bool>,
}

impl Default for LiveSnapshot {
    fn default() -> Self {
        Self {
            schema_version: 1,
            series: None,
            circuit_key: None,
            circuit_name: None,
            weather: None,
            team_radio: Vec::new(),
            session_path: None,
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
            position_status: None,
            position_diagnostics: None,
            time_remaining_seconds: None,
            elapsed_seconds: None,
            is_time_based: None,
        }
    }
}
