//! Read-only season projection over stored results and historical analysis bundles.
use crate::{api::dto::Meta, app_state::AppState, error::ApiError};
use axum::{
    Json,
    extract::{Query, State},
};
use serde::Serialize;
use serde_json::{Value, json};
use std::{collections::HashMap, sync::Arc};

type Layout = (String, Option<String>);

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct TimedLap {
    millis: u64,
    time: String,
    driver_name: String,
    team: String,
    session_type: String,
    year: i64,
}

struct Weekend {
    entry: Value,
    layout: Option<Layout>,
    best: Option<TimedLap>,
}

pub(crate) struct SeasonArchive {
    weekends: Vec<Weekend>,
    meta: Meta,
}

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

    let current = archive(&state, season).await?;
    let mut earlier = HashMap::new();
    if current
        .weekends
        .iter()
        .any(|weekend| weekend.best.is_some())
    {
        for year in state.database.racing_seasons_before(season).await? {
            for weekend in &archive(&state, year).await?.weekends {
                update_record(&mut earlier, weekend);
            }
        }
    }
    let entries = project_weekends(&current.weekends, earlier);
    Ok(Json(json!({"data":entries,"meta":current.meta})))
}

fn project_weekends(weekends: &[Weekend], mut earlier: HashMap<Layout, TimedLap>) -> Vec<Value> {
    let mut entries = Vec::with_capacity(weekends.len());
    for weekend in weekends {
        let mut entry = weekend.entry.clone();
        if let Some(best) = &weekend.best {
            let previous = weekend
                .layout
                .as_ref()
                .and_then(|layout| earlier.get(layout));
            entry["fastestLaps"] = json!({"weekend":best,"previous":previous});
            update_record(&mut earlier, weekend);
        }
        entries.push(entry);
    }
    entries
}

fn update_record(records: &mut HashMap<Layout, TimedLap>, weekend: &Weekend) {
    if let (Some(layout), Some(best)) = (&weekend.layout, &weekend.best)
        && records
            .get(layout)
            .is_none_or(|previous| best.millis < previous.millis)
    {
        records.insert(layout.clone(), best.clone());
    }
}

async fn archive(state: &AppState, season: i64) -> Result<Arc<SeasonArchive>, ApiError> {
    state
        .dashboard
        .archives
        .get_or_load(season, 4, load_archive(state, season))
        .await
}

async fn load_archive(state: &AppState, season: i64) -> Result<Arc<SeasonArchive>, ApiError> {
    let (mut meetings, meta) = state.database.calendar(Some(season)).await?;
    meetings.sort_by(|a, b| a.start_date.cmp(&b.start_date));
    let history = state
        .database
        .analysis_cache(&format!("season:{season}:bundle"))
        .await?
        .unwrap_or(Value::Null);
    let mut weekends = Vec::new();
    for meeting in meetings {
        let mut sessions = serde_json::Map::new();
        let mut best: Option<TimedLap> = None;
        for session in &meeting.sessions {
            let (rows, result_meta) = state.database.session_results(&session.id).await?;
            let bundle = if rows.is_empty() {
                Value::Null
            } else {
                state
                    .database
                    .analysis_cache(&format!("session:{}:bundle", session.id))
                    .await?
                    .unwrap_or(Value::Null)
            };
            let mut lap_times = HashMap::<i64, f64>::new();
            for lap in bundle["data"]["laps"].as_array().into_iter().flatten() {
                if let (Some(driver), Some(seconds)) =
                    (lap["driverNumber"].as_i64(), lap["lapDuration"].as_f64())
                    && lap["isPitOutLap"] != true
                    && seconds > 0.
                    && seconds < 600.
                {
                    let best = lap_times.entry(driver).or_insert(seconds);
                    *best = best.min(seconds);
                }
            }
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
                let official = ["bestLap", "q1", "q2", "q3"]
                    .iter()
                    .filter_map(|&key| row[key].as_str())
                    .chain(historical.and_then(|h| h["fastestLap"].as_str()))
                    .filter_map(|time| Some((lap_millis(time)?, time)))
                    .min_by_key(|(millis, _)| *millis);
                if let Some((millis, time)) = official
                    && meeting.round.is_some()
                    && meeting.status != crate::domain::calendar::MeetingStatus::Cancelled
                    && best.as_ref().is_none_or(|current| millis < current.millis)
                {
                    best = Some(TimedLap {
                        millis,
                        time: time.to_owned(),
                        driver_name: row["driverName"].as_str().unwrap_or_default().to_owned(),
                        team: row["team"].as_str().unwrap_or_default().to_owned(),
                        session_type: session.session_type.as_str().to_owned(),
                        year: season,
                    });
                }
                if row["bestLap"].is_null() {
                    row["bestLap"] = official
                        .map(|(_, time)| json!(time))
                        .or_else(|| {
                            number.and_then(|n| lap_times.get(&n)).map(|seconds| {
                                let millis = (seconds * 1000.).round() as u64;
                                json!(format!(
                                    "{}:{:02}.{:03}",
                                    millis / 60000,
                                    millis / 1000 % 60,
                                    millis % 1000
                                ))
                            })
                        })
                        .unwrap_or(Value::Null);
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
        let layout = meeting.circuit.as_ref().and_then(|circuit| {
            Some((
                circuit["id"].as_str()?.to_owned(),
                circuit["layoutId"]
                    .as_str()
                    .or_else(|| circuit["layout"].as_str())
                    .map(str::to_owned),
            ))
        });
        weekends.push(Weekend {
            entry: json!({"meeting":meeting_json,"sessions":sessions}),
            layout,
            best,
        });
    }
    Ok(Arc::new(SeasonArchive { weekends, meta }))
}

fn lap_millis(time: &str) -> Option<u64> {
    let (minutes, seconds) = time.split_once(':')?;
    let (seconds, fraction) = seconds.split_once('.')?;
    if seconds.len() != 2
        || fraction.is_empty()
        || fraction.len() > 3
        || !time
            .bytes()
            .all(|b| b.is_ascii_digit() || b == b':' || b == b'.')
    {
        return None;
    }
    let minutes: u64 = minutes.parse().ok()?;
    let seconds: u64 = seconds.parse().ok()?;
    if minutes >= 10 || seconds >= 60 {
        return None;
    }
    let millis = minutes * 60000
        + seconds * 1000
        + fraction.parse::<u64>().ok()? * 10u64.pow(3 - fraction.len() as u32);
    (millis > 0).then_some(millis)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn timed_weekend(circuit: &str, layout: &str, time: &str, year: i64) -> Weekend {
        Weekend {
            entry: json!({}),
            layout: Some((circuit.into(), Some(layout.into()))),
            best: Some(TimedLap {
                millis: lap_millis(time).unwrap(),
                time: time.into(),
                driver_name: "Example Driver".into(),
                team: "Example Team".into(),
                session_type: "qualifying".into(),
                year,
            }),
        }
    }

    #[test]
    fn weekend_comparison_uses_fastest_prior_time_for_the_same_layout() {
        let mut earlier = HashMap::new();
        update_record(&mut earlier, &timed_weekend("a", "gp", "1:17.5", 2024));
        update_record(&mut earlier, &timed_weekend("a", "gp", "1:19.2", 2025));
        let rows = project_weekends(
            &[
                timed_weekend("a", "short", "0:58.123", 2026),
                timed_weekend("b", "gp", "1:14.1", 2026),
                timed_weekend("a", "gp", "1:17.123", 2026),
                timed_weekend("a", "gp", "1:18.000", 2026),
            ],
            earlier,
        );
        assert!(rows[0]["fastestLaps"]["previous"].is_null());
        assert!(rows[1]["fastestLaps"]["previous"].is_null());
        assert_eq!(rows[2]["fastestLaps"]["previous"]["millis"], 77500);
        assert_eq!(rows[2]["fastestLaps"]["previous"]["year"], 2024);
        assert_eq!(rows[3]["fastestLaps"]["previous"]["millis"], 77123);
        assert_eq!(lap_millis("1:60.001"), None);
        assert_eq!(lap_millis("0:00.000"), None);
    }
}
