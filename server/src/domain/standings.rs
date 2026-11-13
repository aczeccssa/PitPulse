use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DriverStanding {
    pub season: i64,
    pub position: i64,
    pub driver_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub driver_number: Option<String>,
    pub driver_name: String,
    pub constructor: String,
    #[serde(default)]
    pub constructor_ids: Vec<String>,
    pub points: f64,
    pub wins: i64,
    pub source: String,
    pub fetched_at: String,
    pub revision: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConstructorStanding {
    pub season: i64,
    pub position: i64,
    pub constructor_id: String,
    pub constructor_name: String,
    pub points: f64,
    pub wins: i64,
    pub source: String,
    pub fetched_at: String,
    pub revision: i64,
}
