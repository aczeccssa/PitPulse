use std::collections::BTreeMap;

use crate::{
    api::dto::Meta,
    app_state::AppState,
    domain::calendar::{Meeting, Session, SessionStatus},
    providers::resources::Resource,
    scheduler::parse_utc_seconds,
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
    if let Some((year, _)) = id.split_once(":formula1:")
        && let Ok(year) = year.parse()
    {
        return crate::services::next_schedule::calendar(&state.database, year)
            .await
            .map_err(|_| "database_error")?
            .and_then(|(meetings, _)| meetings.into_iter().find(|m| m.id == id))
            .ok_or("not_found");
    }
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
        let now_seconds = parse_utc_seconds(&now).ok_or("invalid_time")?;
        let (forecast, forecast_meta) = state.weather.forecast(&meeting, &now).await?;
        let forecast_hours = forecast["hours"].as_array().cloned().unwrap_or_default();
        // Finished sessions have fixed observations; upcoming sessions keep the
        // forecast. A forecast window that starts today would otherwise drop the
        // sessions that already ran yesterday.
        let mut measured = Vec::new();
        for session in &meeting.sessions {
            if session.status == SessionStatus::Cancelled {
                continue;
            }
            let Some(end) = session_end_seconds(session) else {
                continue;
            };
            if end >= now_seconds {
                continue;
            }
            let bundle = crate::services::analysis::cached_session_bundle(&state, &session.id)
                .await
                .map_err(|_| "database_error")?;
            let mut rows = bundle
                .map(|bundle| historical_weather(&bundle["data"], &session.id))
                .unwrap_or_default();
            if rows.is_empty()
                && state.openf1.enabled
                && let Some(key) = session.openf1_session_key
            {
                match state.weather.observations(key, &session.id, &now).await {
                    Ok((observed, _)) => rows = observed,
                    Err(error) => {
                        tracing::warn!(session = %session.id, %error, "OpenF1 session weather unavailable");
                    }
                }
            }
            measured.extend(rows);
        }
        let hours = merge_weather_hours(&forecast_hours, &measured);
        if hours.is_empty() {
            let status = match forecast["status"].as_str() {
                Some("past_event") => "history_pending",
                Some(status) => status,
                None => "outside_forecast_window",
            };
            return Ok((json!({"status": status, "hours": []}), forecast_meta));
        }
        let any_forecast = hours.iter().any(|hour| hour["sessionId"].is_null());
        let any_measured = hours.iter().any(|hour| !hour["sessionId"].is_null());
        let status = if any_forecast { "available" } else { "historical" };
        let source = match (any_forecast, any_measured) {
            (true, true) => "open-meteo+openf1",
            (true, false) => "open-meteo",
            _ => "openf1-archive",
        };
        Ok((
            json!({"status": status, "hours": hours}),
            Meta::from_cache(Some(source.into()), None, 1, false),
        ))
    }
    .await;
    match result {
        Ok((data, meta)) => Json(json!({"data":data,"meta":meta})).into_response(),
        Err(e) => failure(e),
    }
}

fn session_end_seconds(session: &Session) -> Option<i64> {
    let start = parse_utc_seconds(&session.start_time)?;
    Some(
        session
            .end_time
            .as_deref()
            .and_then(parse_utc_seconds)
            .unwrap_or(start + 7200),
    )
}

/// One row per hour, with measured observations replacing the forecast for the
/// same hour. Clients look weather up by the hour a session starts in.
fn merge_weather_hours(
    forecast: &[serde_json::Value],
    measured: &[serde_json::Value],
) -> Vec<serde_json::Value> {
    let mut hours = BTreeMap::new();
    for row in forecast.iter().chain(measured.iter()) {
        let Some(utc) = row["utc"].as_str().and_then(parse_utc_seconds) else {
            continue;
        };
        hours.insert(utc.div_euclid(3600), row.clone());
    }
    hours.into_values().collect()
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

    #[test]
    fn merged_hours_prefer_measured_observations_for_finished_sessions() {
        let forecast = vec![
            json!({"utc":"2026-11-21T19:00:00Z","airTemp":21,"precipitationProbability":40}),
            json!({"utc":"2026-11-22T02:00:00Z","airTemp":18,"precipitationProbability":10}),
        ];
        let measured = vec![
            json!({"utc":"2026-11-21T19:05:00Z","sessionId":"2026:22:qualifying","airTemp":24,"rainfall":0}),
            json!({"utc":"2026-11-21T19:55:00Z","sessionId":"2026:22:qualifying","airTemp":23,"rainfall":1}),
        ];
        let hours = merge_weather_hours(&forecast, &measured);
        assert_eq!(hours.len(), 2);
        assert_eq!(hours[0]["sessionId"], "2026:22:qualifying");
        assert_eq!(hours[0]["airTemp"], 23);
        assert_eq!(hours[0]["rainfall"], 1);
        assert!(hours[0]["precipitationProbability"].is_null());
        assert_eq!(hours[1]["precipitationProbability"], 10);
        assert!(hours[1]["sessionId"].is_null());
    }
}
