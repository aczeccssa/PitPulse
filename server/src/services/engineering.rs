//! Engineering reports collected, stored and aggregated by PitPulse.
use crate::{app_state::AppState, error::ApiError};
use axum::{
    Json,
    extract::{Query, State},
};
use serde_json::{Value, json};
use std::collections::HashMap;

fn season(params: &HashMap<String, String>) -> Result<i64, ApiError> {
    params
        .get("season")
        .and_then(|v| v.parse().ok())
        .filter(|v| (1950..=2100).contains(v))
        .ok_or(ApiError::InvalidQuery {
            field: "season".into(),
            error: "expected a year from 1950 to 2100".into(),
        })
}

/// Engineering archives only cover the seasons the collector actually
/// imported. Earlier seasons are not offered at all, so clients remove the
/// section instead of showing an empty table or a zero total.
pub const POWER_UNIT_FIRST_SEASON: i64 = 2025;
pub const DESTRUCTORS_FIRST_SEASON: i64 = 2026;

/// Which engineering sections exist for a season. This is the single place the
/// server states availability; the dashboard hides what is not offered.
pub fn features(year: i64) -> Value {
    json!({
        "season": year,
        "powerUnit": year >= POWER_UNIT_FIRST_SEASON,
        "destructors": year >= DESTRUCTORS_FIRST_SEASON,
    })
}

fn ensure_offered(section: &str, year: i64, first_season: i64) -> Result<(), ApiError> {
    if year >= first_season {
        return Ok(());
    }
    Err(ApiError::NotOffered {
        section: section.to_string(),
        first_season,
    })
}

fn empty_report(resource: &str) -> Value {
    let data = if resource.starts_with("home-") {
        json!({})
    } else {
        json!([])
    };
    json!({"data":data,"meta":{"source":"PitPulse archive","fetchedAt":null,"stale":false,"unavailable":true}})
}

fn fastest_stop(bundle: &Value, round: i64, country: &str) -> Option<Value> {
    bundle["data"]["pit"].as_array()?.iter().filter_map(|pit| {
        // lane/pitDuration includes transit time and must never stand in for
        // stationary stopDuration when the upstream did not report it.
        let seconds = pit["stopDuration"]
            .as_f64()
            .filter(|seconds| seconds.is_finite() && *seconds > 0.)?;
        let number = pit["driverNumber"].as_i64()?;
        let driver = bundle["data"]["drivers"]
            .as_array()?
            .iter()
            .find(|driver| driver["driverNumber"].as_i64() == Some(number))?;
        Some(json!({"time":seconds,"driverNumber":number,"driverName":driver["fullName"],"team":driver["teamName"],"round":round,"country":country}))
    }).min_by(|a,b|a["time"].as_f64().unwrap().total_cmp(&b["time"].as_f64().unwrap()))
}

async fn pit_stops(state: &AppState, year: i64) -> Result<Value, ApiError> {
    let (meetings, calendar_meta) = state.database.calendar(Some(year)).await?;
    let mut stops = Vec::new();
    let mut covered = Vec::new();
    for meeting in meetings {
        let Some(round) = meeting.round else { continue };
        for session in meeting
            .sessions
            .iter()
            .filter(|s| s.session_type.as_str() == "race")
        {
            if let Some(bundle) =
                crate::services::analysis::cached_session_bundle(state, &session.id).await?
                && let Some(stop) = fastest_stop(&bundle, round, &meeting.country)
            {
                covered.push(round);
                stops.push(stop);
            }
        }
    }
    stops.sort_by(|a, b| {
        a["time"]
            .as_f64()
            .unwrap()
            .total_cmp(&b["time"].as_f64().unwrap())
    });
    stops.truncate(3);
    let unavailable = stops.is_empty();
    Ok(
        json!({"data":stops,"meta":{"source":"PitPulse timing archive","fetchedAt":state.database.utc_now().await?,"stale":calendar_meta.stale && state.database.uses_central_season_data(),"unavailable":unavailable,"coverage":{"rounds":covered,"complete":false}}}),
    )
}

/// Whether a `pitpulse:fia:*` report already covers the whole season. While the
/// FIA collector has only re-imported some rounds, its archive is partial and
/// the reader must keep the complete legacy season record visible.
fn fia_complete(value: &Value) -> bool {
    value["meta"]["coverage"]["complete"] == true
}

/// Pick the report to serve: the authoritative FIA archive when it is fully
/// collected; otherwise the complete legacy season archive so engineering tabs
/// never go empty during the migration; only return an honest empty report when
/// neither archive exists.
fn select_report(fia: Option<Value>, legacy: Option<Value>, resource: &str) -> Value {
    match fia.as_ref().filter(|value| fia_complete(value)) {
        Some(value) => value.clone(),
        None => legacy.or(fia).unwrap_or_else(|| empty_report(resource)),
    }
}

async fn report(state: &AppState, resource: &str, year: i64) -> Result<Value, ApiError> {
    // The FIA archive (pitpulse:fia:*) is authoritative once fully collected.
    // Until every round is imported, fall back to the complete season record in
    // the legacy engineering:* keys so Destructors, PU penalties and the Home
    // crash-cost metric keep showing the full season instead of loading empty.
    let fia = state
        .database
        .analysis_cache(&format!("pitpulse:fia:{resource}:{year}"))
        .await?;
    let legacy = state
        .database
        .analysis_cache(&format!("engineering:{resource}:{year}"))
        .await?;
    Ok(select_report(fia, legacy, resource))
}

/// Capability map for one season; the dashboard hides sections it does not
/// offer instead of rendering an empty archive.
pub async fn season_features(
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    Ok(Json(json!({"data": features(season(&params)?)})))
}

pub async fn tech(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    Ok(Json(
        report(&state, "tech-updates", season(&params)?).await?,
    ))
}

pub async fn power_unit(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    let year = season(&params)?;
    ensure_offered("power-unit", year, POWER_UNIT_FIRST_SEASON)?;
    let usage = report(&state, "used-elements", year).await?;
    let elements = report(&state, "elements", year).await?;
    let penalties = report(&state, "used-elements/penalties", year).await?;
    let stale = [&usage, &elements, &penalties]
        .iter()
        .any(|value| value["meta"]["stale"] == true);
    Ok(Json(
        json!({"data":{"usage":usage["data"],"elements":elements["data"],"penalties":penalties["data"]},"meta":{"source":"PitPulse · FIA reports","stale":stale,"sections":{"usage":usage["meta"],"elements":elements["meta"],"penalties":penalties["meta"]}}}),
    ))
}

pub async fn destructors(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    let year = season(&params)?;
    ensure_offered("destructors", year, DESTRUCTORS_FIRST_SEASON)?;
    let incidents = report(&state, "destructors-championship", year).await?;
    let corrections = report(&state, "destructors-championship-diffs", year).await?;
    Ok(Json(
        json!({"data":{"rows":incidents["data"],"corrections":corrections["data"]},"meta":{"source":"PitPulse archive","stale":incidents["meta"]["stale"]==true,"sections":{"incidents":incidents["meta"],"corrections":corrections["meta"]}}}),
    ))
}

pub async fn home(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    let year = season(&params)?;
    let mut data = serde_json::Map::new();
    let mut sections = serde_json::Map::new();
    for (name, resource) in [
        ("tech", "home-tech"),
        ("pu", "home-pu"),
        ("crashes", "home-crashes"),
    ] {
        let response = report(&state, resource, year).await?;
        data.insert(name.into(), response["data"].clone());
        sections.insert(name.into(), response["meta"].clone());
    }
    let pit = pit_stops(&state, year).await?;
    data.insert("pitStop".into(), pit["data"].clone());
    sections.insert("pitStop".into(), pit["meta"].clone());
    let stale = sections.values().any(|m| m["stale"] == true);
    Ok(Json(
        json!({"data":data,"meta":{"source":"PitPulse archive","stale":stale,"sections":sections}}),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_season_validation() {
        assert!(season(&HashMap::from([("season".into(), "bad".into())])).is_err());
        assert_eq!(
            season(&HashMap::from([("season".into(), "2026".into())])).unwrap(),
            2026
        );
    }
    #[test]
    fn test_sections_are_not_offered_before_their_first_season() {
        assert_eq!(features(2024)["powerUnit"], false);
        assert_eq!(features(2025)["powerUnit"], true);
        assert_eq!(features(2025)["destructors"], false);
        assert_eq!(features(2026)["destructors"], true);
        assert!(ensure_offered("power-unit", 2024, POWER_UNIT_FIRST_SEASON).is_err());
        assert!(ensure_offered("power-unit", 2025, POWER_UNIT_FIRST_SEASON).is_ok());
        assert!(ensure_offered("destructors", 2025, DESTRUCTORS_FIRST_SEASON).is_err());
        assert!(ensure_offered("destructors", 2026, DESTRUCTORS_FIRST_SEASON).is_ok());
    }

    #[test]
    fn missing_report_does_not_claim_zero_or_upstream_failure() {
        let report = empty_report("home-crashes");
        assert!(report["data"]["seasonTotal"].is_null());
        assert_eq!(report["meta"]["unavailable"], true);
        assert_eq!(report["meta"]["stale"], false);
    }
    #[test]
    fn partial_fia_archive_serves_complete_legacy_season() {
        let resource = "destructors-championship";
        let legacy = json!({"data":[{"round":1,"team":"Ferrari"}],"meta":{
            "source":"Formula 1 Dashboard","stale":false,"unavailable":false}});
        // FIA archive only covers round 20 (not complete): the reader keeps the
        // complete legacy season visible instead of the partial new archive.
        let partial_fia = json!({"data":[],"meta":{"coverage":{"complete":false}}});
        let served = select_report(Some(partial_fia), Some(legacy.clone()), resource);
        assert_eq!(served["data"][0]["round"], 1);
        assert_eq!(served["meta"]["unavailable"], false);
        // Once the FIA archive is complete it becomes authoritative.
        let complete_fia = json!({"data":[{"round":20}],"meta":{"coverage":{"complete":true}}});
        let served = select_report(Some(complete_fia), Some(legacy), resource);
        assert_eq!(served["data"][0]["round"], 20);
        // With no archive at all, an honest empty report is returned.
        let served = select_report(None, None, resource);
        assert_eq!(served["meta"]["unavailable"], true);
    }
    #[test]
    fn stationary_stop_does_not_fall_back_to_lane_duration() {
        let bundle = json!({"data":{"drivers":[{"driverNumber":16,"fullName":"Charles Leclerc","teamName":"Ferrari"}],"pit":[{"driverNumber":16,"pitDuration":1.2,"laneDuration":1.2},{"driverNumber":16,"stopDuration":2.4},{"driverNumber":16,"stopDuration":0.0}]}});
        assert_eq!(fastest_stop(&bundle, 1, "Bahrain").unwrap()["time"], 2.4);
        assert!(
            fastest_stop(
                &json!({"data":{"drivers":[],"pit":[{"driverNumber":16,"pitDuration":1.2}]}}),
                1,
                "Bahrain"
            )
            .is_none()
        );
    }
}
