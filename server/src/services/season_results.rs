//! Read-only season projection over stored results and historical analysis bundles.
use crate::{app_state::AppState, error::ApiError};
use axum::{
    Json,
    extract::{Query, State},
};
use serde_json::{Value, json};
use std::collections::HashMap;

pub async fn overview(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    let season = params
        .get("season")
        .and_then(|v| v.parse::<i64>().ok())
        .filter(|v| (1950..=2100).contains(v))
        .ok_or(ApiError::NotFound)?;
    if season < crate::services::FIRST_SEASON {
        return Err(ApiError::NotOffered {
            section: "season".to_string(),
            first_season: crate::services::FIRST_SEASON,
        });
    }

    let (meetings, meta) = state.database.calendar(Some(season)).await?;
    let history = state
        .database
        .analysis_cache(&format!("season:{season}:bundle"))
        .await?
        .unwrap_or(Value::Null);
    let mut entries = Vec::new();
    for meeting in meetings {
        let mut sessions = serde_json::Map::new();
        for session in &meeting.sessions {
            let (rows, result_meta) = state.database.session_results(&session.id).await?;
            let bundle = state
                .database
                .analysis_cache(&format!("session:{}:bundle", session.id))
                .await?
                .unwrap_or(Value::Null);
            let mut rows = json!(rows);
            for row in rows.as_array_mut().into_iter().flatten() {
                let number = row["driverNumber"]
                    .as_str()
                    .and_then(|n| n.parse::<i64>().ok());
                let grid = bundle["data"]["grid"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|g| number.is_some() && g["driverNumber"].as_i64() == number)
                    .map(|g| g["position"].clone());
                let historical = history["data"]["rounds"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter(|r| {
                        matches!(session.session_type.as_str(), "race" | "sprint")
                            && r["round"].as_i64() == meeting.round
                            && (r["sessionType"] == "Sprint")
                                == (session.session_type.as_str() == "sprint")
                    })
                    .flat_map(|r| r["entries"].as_array().into_iter().flatten())
                    .find(|r| r["driverId"] == row["driverId"]);
                row["gridPosition"] = grid
                    .or_else(|| historical.map(|h| h["grid"].clone()))
                    .unwrap_or(Value::Null);
                let fastest = bundle["data"]["laps"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .filter(|lap| {
                        number.is_some()
                            && lap["driverNumber"].as_i64() == number
                            && lap["isPitOutLap"] != true
                    })
                    .filter_map(|lap| lap["lapDuration"].as_f64())
                    .filter(|s| *s > 0. && *s < 600.)
                    .min_by(f64::total_cmp);
                if row["bestLap"].is_null()
                    && let Some(time) = historical.and_then(|h| h["fastestLap"].as_str())
                {
                    row["bestLap"] = json!(time);
                }
                if let Some(seconds) = fastest {
                    row["bestLap"] = json!(format!(
                        "{}:{:06.3}",
                        (seconds / 60.).floor() as u64,
                        seconds % 60.
                    ));
                }
            }
            sessions.insert(
                session.session_type.as_str().into(),
                json!({"rows":rows,"meta":result_meta}),
            );
        }
        let mut meeting_json = json!(&meeting);
        if let Some(circuit) = &meeting.circuit {
            let geometry = crate::services::circuits::geometry(circuit, season);
            if let Some(meters) = geometry["geometry"]["properties"]["length"].as_f64() {
                meeting_json["circuit"]["lengthKm"] = json!(meters / 1000.);
            }
        }
        entries.push(json!({"meeting":meeting_json,"sessions":sessions}));
    }
    Ok(Json(json!({"data":entries,"meta":meta})))
}
