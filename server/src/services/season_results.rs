//! Read-only season projection over stored results and historical analysis bundles.
use crate::{
    api::dto::Meta,
    app_state::AppState,
    domain::{
        calendar::{Meeting, MeetingStatus, Session},
        results::SessionResult,
    },
    error::{ApiError, StorageError},
    storage::postgres::CacheKey,
};
use axum::{
    Json,
    extract::{Query, State},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::{collections::HashMap, sync::Arc};

type Layout = (String, Option<String>);

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TimedLap {
    millis: u64,
    time: String,
    driver_name: String,
    team: String,
    session_type: String,
    year: i64,
}

#[derive(Clone, Serialize, Deserialize)]
struct Weekend {
    entry: Value,
    layout: Option<Layout>,
    best: Option<TimedLap>,
}

#[derive(Clone, Serialize, Deserialize)]
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

    let current = Box::pin(archive(&state, season)).await?;
    let earlier = if current
        .weekends
        .iter()
        .any(|weekend| weekend.best.is_some())
    {
        Box::pin(prior_records(&state, season))
            .await?
            .into_iter()
            .collect()
    } else {
        HashMap::new()
    };
    let entries = project_weekends(&current.weekends, earlier);
    Ok(Json(json!({"data":entries,"meta":current.meta})))
}

type LapRecords = Vec<(Layout, TimedLap)>;

async fn prior_records(state: &AppState, season: i64) -> Result<LapRecords, StorageError> {
    let load = async {
        let mut earlier = HashMap::new();
        for year in state.database.racing_seasons_before(season).await? {
            if let Some(reader) = state.database.season_reader() {
                let ((meetings, _), results, history) = tokio::try_join!(
                    state.database.calendar(Some(year)),
                    reader.season_results(year),
                    season_history(state, year),
                )?;
                let mut meetings = meetings;
                meetings.sort_by(|a, b| a.start_date.cmp(&b.start_date));
                for meeting in meetings {
                    let mut best = None;
                    for session in &meeting.sessions {
                        if let Some((rows, _)) = results.sessions.get(&session.id) {
                            for row in rows {
                                let historical =
                                    historical_entry(&history, &meeting, session, &row.driver_id);
                                record_lap(
                                    &mut best,
                                    official_lap(row, historical),
                                    row,
                                    &meeting,
                                    session,
                                );
                            }
                        }
                    }
                    update_record(&mut earlier, layout(&meeting).as_ref(), best.as_ref());
                }
            } else {
                for weekend in &Box::pin(archive(state, year)).await?.weekends {
                    update_record(&mut earlier, weekend.layout.as_ref(), weekend.best.as_ref());
                }
            }
        }
        Ok(earlier.into_iter().collect())
    };
    if let Some(reader) = state
        .database
        .season_reader()
        .filter(|reader| reader.has_disk_cache())
    {
        state.database.analysis_generation(reader).await?;
        return reader
            .cached(
                CacheKey::LapRecords(season),
                Box::pin(load),
                |_| true,
                |_| {},
            )
            .await;
    }
    load.await
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
            update_record(&mut earlier, weekend.layout.as_ref(), weekend.best.as_ref());
        }
        entries.push(entry);
    }
    entries
}

fn update_record(
    records: &mut HashMap<Layout, TimedLap>,
    layout: Option<&Layout>,
    best: Option<&TimedLap>,
) {
    if let (Some(layout), Some(best)) = (layout, best)
        && records
            .get(layout)
            .is_none_or(|previous| best.millis < previous.millis)
    {
        records.insert(layout.clone(), best.clone());
    }
}

async fn archive(state: &AppState, season: i64) -> Result<Arc<SeasonArchive>, StorageError> {
    if let Some(reader) = state.database.season_reader() {
        if reader.has_disk_cache() {
            state.database.analysis_generation(reader).await?;
            return reader
                .cached(
                    CacheKey::Archive(season),
                    Box::pin(load_archive(state, season)),
                    |archive| !archive.weekends.is_empty(),
                    |archive| {
                        let archive = Arc::make_mut(archive);
                        mark_stale(&mut archive.meta);
                        for weekend in &mut archive.weekends {
                            crate::api::dashboard_cache::mark_response_stale(&mut weekend.entry);
                        }
                    },
                )
                .await;
        }
        return Box::pin(load_archive(state, season)).await;
    }
    state
        .dashboard
        .archives
        .get_or_load(season, 4, Box::pin(load_archive(state, season)))
        .await
}

fn mark_stale(meta: &mut Meta) {
    meta.stale = true;
    meta.quality = crate::domain::quality::DataQuality::Stale;
}

async fn load_archive(state: &AppState, season: i64) -> Result<Arc<SeasonArchive>, StorageError> {
    let ((mut meetings, mut meta), batch) = if let Some(reader) = state.database.season_reader() {
        let (calendar, results) = tokio::try_join!(
            state.database.calendar(Some(season)),
            reader.season_results(season)
        )?;
        (calendar, Some(results))
    } else {
        (state.database.calendar(Some(season)).await?, None)
    };
    if batch.as_ref().is_some_and(|batch| batch.stale) {
        mark_stale(&mut meta);
    }
    meetings.sort_by(|a, b| a.start_date.cmp(&b.start_date));
    let history = season_history(state, season).await?;
    let mut weekends = Vec::new();
    for meeting in meetings {
        let mut sessions = serde_json::Map::new();
        let mut best: Option<TimedLap> = None;
        for session in &meeting.sessions {
            let (rows, mut result_meta) = match &batch {
                Some(batch) => batch
                    .sessions
                    .get(&session.id)
                    .cloned()
                    .unwrap_or_else(|| (Vec::new(), Meta::empty())),
                None => state.database.session_results(&session.id).await?,
            };
            if batch.as_ref().is_some_and(|batch| batch.stale) && !rows.is_empty() {
                mark_stale(&mut result_meta);
            }
            let bundle = if rows.is_empty() {
                Value::Null
            } else {
                crate::services::analysis::cached_session_bundle(state, &session.id)
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
            let mut projected = Vec::with_capacity(rows.len());
            for raw in &rows {
                let mut row = json!(raw);
                crate::api::media::public_bindings().add_result_media(&mut row, meeting.season);
                let number = raw
                    .driver_number
                    .as_deref()
                    .and_then(|n| n.parse::<i64>().ok());
                let grid = bundle["data"]["grid"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|g| number.is_some() && g["driverNumber"].as_i64() == number)
                    .map(|g| g["position"].clone());
                let historical = historical_entry(&history, &meeting, session, &raw.driver_id);
                row["gridPosition"] = grid
                    .or_else(|| historical.map(|h| h["grid"].clone()))
                    .unwrap_or(Value::Null);
                let official = official_lap(raw, historical);
                record_lap(&mut best, official, raw, &meeting, session);
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
                projected.push(row);
            }
            sessions.insert(
                session.session_type.as_str().into(),
                json!({"rows":projected,"meta":result_meta}),
            );
        }
        let mut meeting_json = json!(&meeting);
        if let Some(circuit) = &meeting.circuit {
            let geometry = crate::services::circuits::geometry(circuit, season);
            if let Some(meters) = geometry["geometry"]["properties"]["length"].as_f64() {
                meeting_json["circuit"]["lengthKm"] = json!(meters / 1000.);
            }
        }
        let layout = layout(&meeting);
        weekends.push(Weekend {
            entry: json!({"meeting":meeting_json,"sessions":sessions}),
            layout,
            best,
        });
    }
    Ok(Arc::new(SeasonArchive { weekends, meta }))
}

async fn season_history(state: &AppState, season: i64) -> Result<Value, StorageError> {
    Ok(state
        .database
        .analysis_cache(&format!("season:{season}:bundle"))
        .await?
        .unwrap_or(Value::Null))
}

fn layout(meeting: &Meeting) -> Option<Layout> {
    let circuit = meeting.circuit.as_ref()?;
    Some((
        circuit["id"].as_str()?.to_owned(),
        circuit["layoutId"]
            .as_str()
            .or_else(|| circuit["layout"].as_str())
            .map(str::to_owned),
    ))
}

fn historical_entry<'a>(
    history: &'a Value,
    meeting: &Meeting,
    session: &Session,
    driver: &str,
) -> Option<&'a Value> {
    let kind = session.session_type.as_str();
    if !matches!(kind, "race" | "sprint") {
        return None;
    }
    history["data"]["rounds"]
        .as_array()?
        .iter()
        .filter(|r| {
            r["round"].as_i64() == meeting.round
                && (r["sessionType"] == "Sprint") == (kind == "sprint")
        })
        .flat_map(|r| r["entries"].as_array().into_iter().flatten())
        .find(|r| r["driverId"].as_str() == Some(driver))
}

fn official_lap<'a>(
    row: &'a SessionResult,
    historical: Option<&'a Value>,
) -> Option<(u64, &'a str)> {
    [&row.best_lap, &row.q1, &row.q2, &row.q3]
        .into_iter()
        .filter_map(|time| time.as_deref())
        .chain(historical.and_then(|row| row["fastestLap"].as_str()))
        .filter_map(|time| Some((lap_millis(time)?, time)))
        .min_by_key(|(millis, _)| *millis)
}

fn record_lap(
    best: &mut Option<TimedLap>,
    official: Option<(u64, &str)>,
    row: &SessionResult,
    meeting: &Meeting,
    session: &Session,
) {
    if let Some((millis, time)) = official
        && meeting.round.is_some()
        && meeting.status != MeetingStatus::Cancelled
        && best.as_ref().is_none_or(|current| millis < current.millis)
    {
        *best = Some(TimedLap {
            millis,
            time: time.to_owned(),
            driver_name: row.driver_name.clone(),
            team: row.team.clone(),
            session_type: session.session_type.as_str().to_owned(),
            year: meeting.season,
        });
    }
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
        for weekend in [
            timed_weekend("a", "gp", "1:17.5", 2024),
            timed_weekend("a", "gp", "1:19.2", 2025),
        ] {
            update_record(&mut earlier, weekend.layout.as_ref(), weekend.best.as_ref());
        }
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
