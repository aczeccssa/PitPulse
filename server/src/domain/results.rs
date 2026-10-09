use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SessionResult {
    pub session_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub position: Option<i64>,
    pub classification: String,
    pub driver_id: String,
    pub driver_name: String,
    pub constructor_id: String,
    pub team: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub time: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub best_lap: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q1: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q2: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q3: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub race_time: Option<String>,
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

impl SessionResult {
    #[allow(dead_code)]
    pub fn classification_from_flags(
        position_text: Option<&str>,
        dnf: bool,
        dns: bool,
        dsq: bool,
    ) -> String {
        if dsq {
            return "DSQ".to_string();
        }
        if dns {
            return "DNS".to_string();
        }
        if dnf {
            return "DNF".to_string();
        }
        match position_text
            .unwrap_or_default()
            .trim()
            .to_ascii_uppercase()
            .as_str()
        {
            "NC" => "NC".to_string(),
            "DNS" | "DNF" | "DSQ" => position_text.unwrap_or_default().to_ascii_uppercase(),
            _ => "classified".to_string(),
        }
    }
}
