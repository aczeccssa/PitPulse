use crate::{
    api::dto::Meta, app_state::AppState, domain::calendar::Meeting, providers::resources::Resource,
};
use axum::{
    Json,
    extract::{Path, State},
    http::{StatusCode, header},
    response::{IntoResponse, Response},
};
use serde_json::json;

fn failure(code: &'static str) -> Response {
    let status = match code {
        "not_found" | "unknown_radar_frame" => StatusCode::NOT_FOUND,
        "invalid_tile" | "invalid_audio_path" => StatusCode::BAD_REQUEST,
        "upstream_rate_limited" => StatusCode::TOO_MANY_REQUESTS,
        _ => StatusCode::SERVICE_UNAVAILABLE,
    };
    (
        status,
        [(header::CACHE_CONTROL, "no-store")],
        Json(json!({"error":{"code":code,"message":code}})),
    )
        .into_response()
}
async fn meeting(state: &AppState, id: &str) -> Result<Meeting, &'static str> {
    state
        .database
        .calendar(None)
        .await
        .map_err(|_| "database_error")?
        .0
        .into_iter()
        .find(|m| m.id == id)
        .ok_or("not_found")
}
pub async fn config(State(state): State<AppState>) -> Response {
    ([(header::CACHE_CONTROL,"no-store")],Json(json!({"data":{"publicToken":state.config.providers.mapbox_public_token,"style":"mapbox://styles/mapbox/standard","version":"3.32.0"},"meta":Meta::empty()}))).into_response()
}
pub async fn geometry(State(state): State<AppState>, Path(id): Path<String>) -> Response {
    match meeting(&state, &id).await {
        Ok(meeting) => {
            let data = meeting
                .circuit
                .as_ref()
                .map(|c| crate::services::circuits::geometry(c, meeting.season))
                .unwrap_or_else(
                    || json!({"geometry":null,"status":"location_unavailable","calibrated":false}),
                );
            Json(json!({"data":data,"meta":Meta::from_cache(Some("f1-circuits".into()),None,1,false)})).into_response()
        }
        Err(e) => failure(e),
    }
}
pub async fn weather(State(state): State<AppState>, Path(id): Path<String>) -> Response {
    let result = async {
        let meeting = meeting(&state, &id).await?;
        let now = state
            .database
            .utc_now()
            .await
            .map_err(|_| "database_error")?;
        let (forecast, meta) = state.weather.forecast(&meeting, &now).await?;
        if forecast["status"] != "past_event" {
            return Ok((forecast, meta));
        }
        // Historical observations are already archived with the session bundle.
        // Never query a forecast provider again for a completed weekend.
        let mut hours = Vec::new();
        for session in &meeting.sessions {
            let bundle = state.database
                .analysis_cache(&format!("session:{}:bundle", session.id))
                .await.map_err(|_| "database_error")?;
            if let Some(bundle) = bundle {
                hours.extend(historical_weather(&bundle["data"], &session.id));
            }
        }
        hours.sort_by(|a, b| a["utc"].as_str().cmp(&b["utc"].as_str()));
        let available = !hours.is_empty();
        Ok((json!({"status": if available { "historical" } else { "history_pending" }, "hours": hours}),
            Meta::from_cache(Some("openf1-archive".into()), None, 1, false)))
    }
    .await;
    match result {
        Ok((data, meta)) => Json(json!({"data":data,"meta":meta})).into_response(),
        Err(e) => failure(e),
    }
}
pub async fn radar_frames(State(state): State<AppState>) -> Response {
    let result = async {
        let now = state
            .database
            .utc_now()
            .await
            .map_err(|_| "database_error")?;
        state.radar.frames(&now).await
    }
    .await;
    match result {
        Ok((data, meta)) => Json(json!({"data":data,"meta":meta})).into_response(),
        Err(e) => failure(e),
    }
}
pub async fn radar_tile(
    State(state): State<AppState>,
    Path((kind, frame, z, x, y)): Path<(String, u64, u32, u32, u32)>,
) -> Response {
    if kind != "radar" && kind != "coverage" {
        return failure("invalid_tile");
    }
    let result = async {
        let now = state
            .database
            .utc_now()
            .await
            .map_err(|_| "database_error")?;
        state
            .radar
            .tile(frame, z, x, y, kind == "coverage", &now)
            .await
    }
    .await;
    match result {
        Ok(r) => binary(r, "rainviewer"),
        Err(e) => failure(e),
    }
}
pub async fn radio(
    State(state): State<AppState>,
    Path((session, id)): Path<(String, String)>,
) -> Response {
    let (path, capture) = {
        let snapshot = state.live.current();
        if snapshot.session_id.as_deref() != Some(&session) {
            return failure("not_found");
        }
        let Some(entry) = snapshot.team_radio.iter().find(|r| r.id == id) else {
            return failure("not_found");
        };
        let Some(path) = snapshot.session_path.clone() else {
            return failure("not_found");
        };
        (path, entry.path.clone())
    };
    let result = async {
        let now = state
            .database
            .utc_now()
            .await
            .map_err(|_| "database_error")?;
        state.radio.audio(&path, &capture, &now).await
    }
    .await;
    match result {
        Ok(r) => binary(r, "f1-live"),
        Err(e) => failure(e),
    }
}
fn binary(resource: Resource, source: &str) -> Response {
    (
        [
            (header::CONTENT_TYPE, resource.content_type),
            (header::CACHE_CONTROL, "private, no-store".into()),
            (
                header::HeaderName::from_static("x-pitpulse-source"),
                source.into(),
            ),
            (
                header::HeaderName::from_static("x-pitpulse-fetched-at"),
                resource.fetched_at,
            ),
            (
                header::HeaderName::from_static("x-pitpulse-stale"),
                resource.stale.to_string(),
            ),
        ],
        resource.bytes,
    )
        .into_response()
}

fn historical_weather(bundle: &serde_json::Value, session: &str) -> Vec<serde_json::Value> {
    bundle["weather"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|sample| {
            let utc = crate::services::analysis::normalize_date(sample["date"].as_str()?)?;
            Some(json!({
                "utc": utc, "sessionId": session,
                "airTemp": sample["airTemperature"],
                "trackTemp": sample["trackTemperature"],
                "humidity": sample["humidity"],
                "rainfall": sample["rainfall"],
                "windSpeed": sample["windSpeed"],
                "windDirection": sample["windDirection"],
                "pressure": sample["pressure"]
            }))
        })
        .collect()
}

#[cfg(test)]
mod weather_tests {
    use super::*;
    #[test]
    fn historical_observations_preserve_measurements_without_inventing_forecasts() {
        let rows = historical_weather(
            &json!({"weather":[
                {"date":"2026-11-08T17:00:00.123Z","airTemperature":27.5,"trackTemperature":42,"rainfall":0,"windSpeed":2.1},
                {"date":"invalid","airTemperature":99}
            ]}),
            "2026:20:race",
        );
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0]["sessionId"], "2026:20:race");
        assert_eq!(rows[0]["airTemp"], 27.5);
        assert_eq!(rows[0]["trackTemp"], 42);
        assert!(rows[0].get("precipitationProbability").is_none());
        assert!(rows[0]["humidity"].is_null());
    }
}
