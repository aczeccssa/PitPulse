use crate::{
    app_state::AppState,
    error::ApiError,
    providers::results::IdentityMaps,
    scheduler::{add_seconds, parse_utc_seconds},
};
use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::sync::Mutex;

#[derive(Clone, Default)]
pub struct AnalysisCache {
    entries: Arc<Mutex<HashMap<String, (Instant, Value)>>>,
    pending: Arc<Mutex<HashSet<String>>>,
    worker: Arc<Mutex<()>>,
}

fn invalid(error: impl Into<String>) -> ApiError {
    ApiError::InvalidQuery {
        field: "analysis".into(),
        error: error.into(),
    }
}

fn fresh(at: &Instant, value: &Value) -> bool {
    let failed = value["meta"]["analysisStatus"] == "failed";
    at.elapsed() < Duration::from_secs(if failed { 120 } else { 1800 })
}

fn camel(value: Value) -> Value {
    match value {
        Value::Array(rows) => Value::Array(rows.into_iter().map(camel).collect()),
        Value::Object(rows) => Value::Object(
            rows.into_iter()
                .map(|(key, value)| {
                    let mut parts = key.split('_');
                    let mut name = parts.next().unwrap_or_default().to_string();
                    for part in parts {
                        let mut chars = part.chars();
                        if let Some(c) = chars.next() {
                            name.push(c.to_ascii_uppercase());
                            name.extend(chars);
                        }
                    }
                    (name, camel(value))
                })
                .collect(),
        ),
        other => other,
    }
}

fn historical_grid(races: &[Value], round: i64, collection: &str) -> Vec<Value> {
    let Some(race) = races
        .iter()
        .find(|race| race["round"].as_str().and_then(|n| n.parse::<i64>().ok()) == Some(round))
    else {
        return Vec::new();
    };
    race[collection]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|row| {
            let number = row["Driver"]["permanentNumber"]
                .as_str()?
                .parse::<i64>()
                .ok()?;
            let position = row["grid"].as_str()?.parse::<i64>().ok()?;
            if number <= 0 || position < 0 {
                return None;
            }
            Some(json!({"driverNumber":number,"position":position,"lapDuration":null}))
        })
        .collect()
}

async fn section(
    state: &AppState,
    resource: &str,
    params: &[(String, String)],
    warnings: &mut Vec<String>,
) -> Vec<Value> {
    let started = Instant::now();
    match state.openf1.analysis_rows(resource, params).await {
        Ok(rows) => {
            tracing::info!(
                resource,
                rows = rows.len(),
                elapsed_ms = started.elapsed().as_millis() as u64,
                "analysis resource loaded"
            );
            rows.into_iter().map(camel).collect()
        }
        Err(error) => {
            tracing::warn!(resource, %error, elapsed_ms = started.elapsed().as_millis() as u64, "analysis resource unavailable");
            warnings.push(format!("{resource}: {error}"));
            Vec::new()
        }
    }
}

pub(crate) fn normalize_date(value: &str) -> Option<String> {
    let prefix = value.get(..19)?;
    let suffix = value.get(19..)?;
    let suffix = if let Some(fraction) = suffix.strip_prefix('.') {
        let end = fraction.find(|c: char| !c.is_ascii_digit())?;
        &fraction[end..]
    } else {
        suffix
    };
    let date = format!("{prefix}{suffix}");
    parse_utc_seconds(&date)?;
    Some(date)
}

fn selected_lap(laps: &[Value], requested: Option<i64>) -> Option<&Value> {
    laps.iter()
        .filter(|row| {
            row["dateStart"].as_str().is_some()
                && row["lapDuration"]
                    .as_f64()
                    .is_some_and(|v| v > 0. && v < 600.)
                && row["isPitOutLap"] != true
        })
        .filter(|row| requested.is_none_or(|lap| row["lapNumber"].as_i64() == Some(lap)))
        .min_by(|a, b| {
            a["lapDuration"]
                .as_f64()
                .unwrap()
                .total_cmp(&b["lapDuration"].as_f64().unwrap())
        })
}

fn envelope(data: Value, now: &str, source: &str) -> Value {
    json!({"data":data,"meta":{"schemaVersion":1,"revision":1,"quality":"partial","stale":false,"source":source,"fetchedAt":now,"analysisStatus":"ready"}})
}

fn insert(cache: &mut HashMap<String, (Instant, Value)>, key: String, value: Value) {
    if cache.len() >= 128
        && !cache.contains_key(&key)
        && let Some(oldest) = cache
            .iter()
            .min_by_key(|(_, v)| v.0)
            .map(|(k, _)| k.clone())
    {
        cache.remove(&oldest);
    }
    cache.insert(key, (Instant::now(), value));
}

fn retain_sections(data: &mut Value, previous: &Value) -> bool {
    let mut stale = false;
    for field in [
        "location",
        "carData",
        "laps",
        "stints",
        "pit",
        "positions",
        "weather",
        "raceControl",
        "grid",
    ] {
        if data[field].as_array().is_some_and(Vec::is_empty)
            && previous[field]
                .as_array()
                .is_some_and(|rows| !rows.is_empty())
        {
            data[field] = previous[field].clone();
            data["warnings"]
                .as_array_mut()
                .unwrap()
                .push(json!(format!("{field}: 显示上次缓存")));
            stale = true;
        }
    }
    if stale {
        if data["driver"].is_null() {
            data["driver"] = previous["driver"].clone();
        }
        if data["selectedLap"].is_null() {
            data["selectedLap"] = previous["selectedLap"].clone();
        }
    }
    stale
}

#[derive(Clone)]
enum Job {
    Session {
        session: String,
        driver: String,
        lap: Option<i64>,
    },
    Season {
        season: i64,
        kind: String,
        id: String,
    },
}
impl Job {
    fn key(&self) -> String {
        match self {
            Self::Session {
                session,
                driver,
                lap,
            } => format!("session:{session}:{driver}:{}", lap.unwrap_or(0)),
            Self::Season { season, kind, id } => format!("season:{season}:{kind}:{id}"),
        }
    }
}

impl AnalysisCache {
    async fn read(&self, state: &AppState, key: &str) -> Result<Option<Value>, ApiError> {
        let cached = { self.entries.lock().await.get(key).cloned() };
        if let Some((_, value)) = cached {
            return Ok(Some(value));
        }
        let value = state.database.analysis_cache(key).await?;
        if let Some(value) = &value {
            insert(
                &mut *self.entries.lock().await,
                key.to_string(),
                value.clone(),
            );
        }
        Ok(value)
    }
    async fn put(&self, state: &AppState, key: String, value: Value) -> Result<(), ApiError> {
        state.database.save_analysis_cache(&key, &value).await?;
        insert(&mut *self.entries.lock().await, key, value);
        Ok(())
    }
}

fn fresh_value(value: &Value) -> bool {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let age = value["meta"]["fetchedAt"]
        .as_str()
        .and_then(parse_utc_seconds)
        .map(|at| now.saturating_sub(at).max(0) as u64);
    age.is_some_and(|age| {
        Instant::now()
            .checked_sub(Duration::from_secs(age))
            .is_some_and(|at| fresh(&at, value))
    })
}

fn empty_session() -> Value {
    json!({"laps":[],"stints":[],"pit":[],"positions":[],"weather":[],"raceControl":[],"grid":[],"location":[],"carData":[],"warnings":[],"driver":null})
}

async fn session_context(
    state: &AppState,
    session_id: &str,
    driver_id: &str,
) -> Result<
    (
        crate::domain::calendar::Meeting,
        crate::domain::calendar::Session,
    ),
    ApiError,
> {
    let season = session_id
        .split(':')
        .next()
        .and_then(|s| s.parse::<i64>().ok())
        .filter(|s| (2000..=2100).contains(s))
        .ok_or_else(|| invalid("invalid session"))?;
    let meetings = state.database.calendar(Some(season)).await?.0;
    let (meeting, session) = meetings
        .iter()
        .find_map(|m| {
            m.sessions
                .iter()
                .find(|s| s.id == session_id)
                .map(|s| (m.clone(), s.clone()))
        })
        .ok_or(ApiError::NotFound)?;
    if !state
        .database
        .session_results(session_id)
        .await?
        .0
        .iter()
        .any(|r| r.driver_id == driver_id)
    {
        return Err(ApiError::NotFound);
    }
    Ok((meeting, session))
}

async fn queue(state: &AppState, job: Job) {
    let key = job.key();
    let mut pending = state.analysis.pending.lock().await;
    if pending.len() >= 64 || !pending.insert(key) {
        return;
    }
    drop(pending);
    let state = state.clone();
    tokio::spawn(async move {
        execute(&state, job).await;
    });
}

async fn execute(state: &AppState, job: Job) {
    let key = job.key();
    let _worker = state.analysis.worker.lock().await;
    let cached = state.analysis.read(state, &key).await.ok().flatten();
    if !cached.as_ref().is_some_and(fresh_value) {
        tracing::info!(analysis_key = %key, "analysis refresh started");
        let result = match &job {
            Job::Session {
                session,
                driver,
                lap,
            } => refresh_session(state, session, driver, *lap).await,
            Job::Season { season, .. } => refresh_season(state, *season).await,
        };
        if let Err(error) = result {
            tracing::warn!(analysis_key = %key, %error, "analysis refresh failed");
            let now = state.database.utc_now().await.unwrap_or_default();
            let mut value = cached.unwrap_or_else(|| {
                envelope(
                    match job {
                        Job::Session { .. } => empty_session(),
                        _ => json!({"rounds":[],"warnings":[]}),
                    },
                    &now,
                    "analysis",
                )
            });
            value["meta"]["analysisStatus"] = json!("failed");
            value["meta"]["analysisError"] = json!("分析刷新失败，保留可用缓存；稍后重试。");
            value["meta"]["stale"] = json!(true);
            value["meta"]["fetchedAt"] = json!(now);
            let _ = state.analysis.put(state, key.clone(), value).await;
        }
        tracing::info!(analysis_key = %key, "analysis refresh finished");
    }
    state.analysis.pending.lock().await.remove(&key);
}

async fn response(
    state: &AppState,
    job: Job,
    fallback: Option<Value>,
) -> Result<Json<Value>, ApiError> {
    let cached = state.analysis.read(state, &job.key()).await?;
    if let Some(value) = &cached
        && fresh_value(value)
    {
        return Ok(Json(value.clone()));
    }
    queue(state, job.clone()).await;
    let now = state.database.utc_now().await?;
    let source = match job {
        Job::Session { .. } => "openf1",
        _ => "jolpica-ergast",
    };
    let mut value = cached.or(fallback).unwrap_or_else(|| {
        envelope(
            if source == "openf1" {
                empty_session()
            } else {
                json!({"rounds":[],"warnings":[]})
            },
            &now,
            source,
        )
    });
    let stale = value["meta"]["stale"] == true || !fresh_value(&value);
    value["meta"]["analysisStatus"] = json!("loading");
    // Cached content keeps its timestamp and is readable during the background refresh.
    value["meta"]["stale"] = json!(stale);
    Ok(Json(value))
}

pub async fn session_analysis(
    State(state): State<AppState>,
    Path((session, driver)): Path<(String, String)>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    let lap = query
        .get("lap")
        .map(|s| s.parse::<i64>().map_err(|_| invalid("invalid lap")))
        .transpose()?;
    if lap.is_some_and(|n| !(1..=200).contains(&n)) {
        return Err(invalid("lap must be 1...200"));
    }
    session_context(&state, &session, &driver).await?;
    let mut base = state
        .analysis
        .read(&state, &format!("session:{session}:{driver}:base"))
        .await?;
    if let Some(value) = &mut base
        && let Some(laps) = value["data"]["laps"].as_array()
    {
        if lap.is_some() && !laps.is_empty() && selected_lap(laps, lap).is_none() {
            return Err(invalid("lap has no complete timing interval"));
        }
        value["data"]["selectedLap"] = selected_lap(laps, lap)
            .map(|r| r["lapNumber"].clone())
            .unwrap_or(Value::Null);
    }
    response(
        &state,
        Job::Session {
            session,
            driver,
            lap,
        },
        base,
    )
    .await
}

pub async fn season_analysis(
    State(state): State<AppState>,
    Path((kind, id)): Path<(String, String)>,
    Query(query): Query<HashMap<String, String>>,
) -> Result<Json<Value>, ApiError> {
    let season = query
        .get("season")
        .and_then(|s| s.parse::<i64>().ok())
        .filter(|s| (2000..=2100).contains(s))
        .ok_or_else(|| invalid("invalid season"))?;
    if !["drivers", "constructors"].contains(&kind.as_str()) {
        return Err(ApiError::NotFound);
    }
    if id.is_empty()
        || !id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err(invalid("invalid identity"));
    }
    let known = if kind == "drivers" {
        state
            .database
            .driver_standings(Some(season))
            .await?
            .0
            .iter()
            .any(|r| r.driver_id == id)
    } else {
        state
            .database
            .constructor_standings(Some(season))
            .await?
            .0
            .iter()
            .any(|r| r.constructor_id == id)
    };
    if !known {
        return Err(ApiError::NotFound);
    }
    response(&state, Job::Season { season, kind, id }, None).await
}

async fn session_bundle(
    state: &AppState,
    meeting: &crate::domain::calendar::Meeting,
    session: &crate::domain::calendar::Session,
) -> Result<Value, ApiError> {
    let key = format!("session:{}:bundle", session.id);
    let previous = state.analysis.read(state, &key).await?;
    if let Some(value) = &previous
        && fresh_value(value)
    {
        return Ok(value["data"].clone());
    }
    let now = state.database.utc_now().await?;
    let mut warnings = Vec::new();
    let mut data = empty_session();
    data["drivers"] = json!([]);
    if let Some(key) = session.openf1_session_key.filter(|_| state.openf1.enabled) {
        let params = vec![("session_key".into(), key.to_string())];
        for (resource, field) in [
            ("drivers", "drivers"),
            ("laps", "laps"),
            ("stints", "stints"),
            ("pit", "pit"),
            ("position", "positions"),
            ("weather", "weather"),
            ("race_control", "raceControl"),
            ("starting_grid", "grid"),
        ] {
            data[field] = json!(section(state, resource, &params, &mut warnings).await);
        }
    } else {
        warnings.push("该 Session 无可用 OpenF1 关联，或 Provider 未启用。".into());
    }
    if data["grid"].as_array().is_some_and(Vec::is_empty)
        && state.jolpica.enabled
        && matches!(
            session.session_type,
            crate::domain::calendar::SessionType::Race
                | crate::domain::calendar::SessionType::Sprint
        )
        && let Some(round) = meeting.round
    {
        let sprint = session.session_type == crate::domain::calendar::SessionType::Sprint;
        let endpoint = if sprint { "sprint" } else { "results" };
        match tokio::time::timeout(
            Duration::from_secs(10),
            state
                .jolpica
                .entity_races_once(meeting.season, "", "", endpoint),
        )
        .await
        {
            Ok(Ok(races)) => {
                let grid = historical_grid(
                    &races,
                    round,
                    if sprint { "SprintResults" } else { "Results" },
                );
                if !grid.is_empty() {
                    data["grid"] = json!(grid);
                    warnings.push("grid: 发车位来自 Jolpica 比赛记录。".into());
                }
            }
            _ => warnings.push("grid: Jolpica 发车位补充暂不可用。".into()),
        }
    }
    data["warnings"] = json!(warnings);
    let stale = if let Some(previous) = &previous {
        retain_sections(&mut data, &previous["data"])
    } else {
        false
    };
    if data["drivers"].as_array().is_some_and(Vec::is_empty)
        && let Some(previous) = &previous
    {
        data["drivers"] = previous["data"]["drivers"].clone();
    }
    let mut value = envelope(data.clone(), &now, "openf1");
    value["meta"]["stale"] = json!(stale);
    if data["laps"].as_array().is_none_or(Vec::is_empty) {
        value["meta"]["analysisStatus"] = json!("failed");
    }
    state.analysis.put(state, key, value).await?;
    let identity = state
        .database
        .identity_cache(meeting.season)
        .await?
        .map(|(d, c)| IdentityMaps::from_ergast(&d, &c));
    for result in state.database.session_results(&session.id).await?.0 {
        let data = project_session(
            &data,
            &result.driver_id,
            identity.as_ref(),
            result.driver_number.as_deref().and_then(|n| n.parse().ok()),
            Some(&result.driver_name),
        );
        let key = format!("session:{}:{}:base", session.id, result.driver_id);
        let failed = data["laps"].as_array().is_none_or(Vec::is_empty);
        let mut value = envelope(data, &now, "openf1");
        if failed {
            value["meta"]["analysisStatus"] = json!("failed");
            value["meta"]["analysisError"] = json!("场次详细数据尚不可用，请检查数据源关联。");
        }
        value["meta"]["stale"] = json!(stale);
        state.analysis.put(state, key, value).await?;
    }
    Ok(data)
}

fn project_session(
    bundle: &Value,
    driver: &str,
    identity: Option<&IdentityMaps>,
    session_number: Option<i64>,
    session_name: Option<&str>,
) -> Value {
    let roster_number = (|| {
        let name = session_name?
            .split_whitespace()
            .collect::<Vec<_>>()
            .join(" ")
            .to_lowercase();
        let mut matches = bundle["drivers"].as_array()?.iter().filter(|row| {
            row["fullName"].as_str().is_some_and(|candidate| {
                candidate
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ")
                    .to_lowercase()
                    == name
            })
        });
        let first = matches.next()?;
        if matches.next().is_some() {
            return None;
        }
        first["driverNumber"].as_i64()
    })();
    let session_number = roster_number.or(session_number);
    let mut data = empty_session();
    data["warnings"] = json!(bundle["warnings"].as_array().cloned().unwrap_or_default());
    let matches: Vec<_> = bundle["drivers"]
        .as_array()
        .into_iter()
        .flatten()
        .filter(|r| {
            r["driverNumber"].as_i64().is_some_and(|n| {
                session_number.map_or_else(
                    || {
                        identity.and_then(|i| i.driver_for_number(n)) == Some(driver)
                            || driver == format!("openf1:{n}")
                    },
                    |expected| n == expected,
                )
            })
        })
        .collect();
    if matches.len() != 1 {
        data["warnings"]
            .as_array_mut()
            .unwrap()
            .push(json!("车手身份无法唯一关联到该 Session，未读取遥测。"));
        return data;
    }
    data["driver"] = matches[0].clone();
    let number = &matches[0]["driverNumber"];
    for field in ["laps", "stints", "pit", "positions"] {
        data[field] = json!(
            bundle[field]
                .as_array()
                .into_iter()
                .flatten()
                .filter(|r| &r["driverNumber"] == number)
                .cloned()
                .collect::<Vec<_>>()
        );
    }
    for field in ["weather", "raceControl", "grid"] {
        data[field] = bundle[field].clone();
    }
    data
}

async fn refresh_session(
    state: &AppState,
    session_id: &str,
    driver: &str,
    requested: Option<i64>,
) -> Result<(), ApiError> {
    let (meeting, session) = session_context(state, session_id, driver).await?;
    let bundle = session_bundle(state, &meeting, &session).await?;
    let identity = state
        .database
        .identity_cache(meeting.season)
        .await?
        .map(|(d, c)| IdentityMaps::from_ergast(&d, &c));
    let result = state
        .database
        .session_results(session_id)
        .await?
        .0
        .into_iter()
        .find(|result| result.driver_id == driver);
    let session_number = result
        .as_ref()
        .and_then(|result| result.driver_number.as_deref().and_then(|n| n.parse().ok()));
    let mut data = project_session(
        &bundle,
        driver,
        identity.as_ref(),
        session_number,
        result.as_ref().map(|result| result.driver_name.as_str()),
    );
    let now = state.database.utc_now().await?;
    let key = Job::Session {
        session: session_id.into(),
        driver: driver.into(),
        lap: requested,
    }
    .key();
    let previous = state.analysis.read(state, &key).await?;
    let laps = data["laps"].as_array().cloned().unwrap_or_default();
    if !laps.is_empty() {
        state
            .analysis
            .put(
                state,
                format!("session:{session_id}:{driver}:base"),
                envelope(data.clone(), &now, "openf1"),
            )
            .await?;
    }
    if let Some(lap) = selected_lap(&laps, requested) {
        data["selectedLap"] = lap["lapNumber"].clone();
        if let (Some(start), Some(key), Some(number)) = (
            lap["dateStart"].as_str().and_then(normalize_date),
            session.openf1_session_key,
            data["driver"]["driverNumber"].as_i64(),
        ) {
            let end = add_seconds(
                &start,
                lap["lapDuration"].as_f64().unwrap().ceil() as i64 + 1,
            )
            .unwrap();
            let params = vec![
                ("session_key".into(), key.to_string()),
                ("driver_number".into(), number.to_string()),
                ("date>=".into(), start),
                ("date<=".into(), end),
            ];
            let mut warnings: Vec<String> =
                serde_json::from_value(data["warnings"].clone()).unwrap_or_default();
            data["location"] = json!(section(state, "location", &params, &mut warnings).await);
            data["carData"] = json!(section(state, "car_data", &params, &mut warnings).await);
            data["warnings"] = json!(warnings);
        }
    } else if requested.is_some() {
        return Err(invalid("lap has no complete timing interval"));
    }
    let stale = previous
        .as_ref()
        .is_some_and(|v| retain_sections(&mut data, &v["data"]));
    let failed = data["laps"].as_array().is_none_or(Vec::is_empty);
    let mut value = envelope(data, &now, "openf1");
    value["meta"]["stale"] = json!(stale);
    if failed {
        value["meta"]["analysisStatus"] = json!("failed");
        value["meta"]["analysisError"] = json!("圈速来源暂未提供数据，可稍后重试。");
    }
    state.analysis.put(state, key, value).await
}

fn retain_rounds(rows: &mut Vec<Value>, previous: &[Value]) -> bool {
    let mut stale = false;
    for old in previous {
        if !rows
            .iter()
            .any(|new| new["round"] == old["round"] && new["sessionType"] == old["sessionType"])
        {
            rows.push(old.clone());
            stale = true;
        }
    }
    stale
}

fn project_rounds(races: &[Value], kind: &str, id: &str) -> Vec<Value> {
    races
        .iter()
        .filter_map(|race| {
            let entries: Vec<_> = race["entries"]
                .as_array()?
                .iter()
                .filter(|r| {
                    if kind == "drivers" {
                        r["driverId"] == id
                    } else {
                        r["constructorId"] == id
                    }
                })
                .cloned()
                .collect();
            if entries.is_empty() {
                return None;
            }
            let mut row = race.clone();
            row["entries"] = json!(entries);
            Some(row)
        })
        .collect()
}

async fn refresh_season(state: &AppState, season: i64) -> Result<(), ApiError> {
    let now = state.database.utc_now().await?;
    let bundle_key = format!("season:{season}:bundle");
    let old_bundle = state.analysis.read(state, &bundle_key).await?;
    let bundle = if let Some(value) = &old_bundle
        && fresh_value(value)
    {
        value.clone()
    } else {
        let mut warnings = Vec::new();
        let mut rows = Vec::new();
        if state.jolpica.enabled {
            for (endpoint, label, collection) in [
                ("results", "正赛", "Results"),
                ("sprint", "Sprint", "SprintResults"),
            ] {
                match state
                    .jolpica
                    .entity_races_once(season, "", "", endpoint)
                    .await
                {
                    Ok(races) => {
                        for race in races {
                            let entries = race
                                .get(collection)
                                .and_then(Value::as_array)
                                .cloned()
                                .unwrap_or_default();
                            rows.push(json!({"round":race["round"].as_str().and_then(|s|s.parse::<i64>().ok()),"raceName":race["raceName"],"date":race["date"],"circuitName":race["Circuit"]["circuitName"],"country":race["Circuit"]["Location"]["country"],"sessionType":label,"entries":entries.iter().map(|row|json!({"driverName":format!("{} {}",row["Driver"]["givenName"].as_str().unwrap_or_default(),row["Driver"]["familyName"].as_str().unwrap_or_default()),"driverId":row["Driver"]["driverId"],"constructorId":row["Constructor"]["constructorId"],"position":row["position"].as_str().and_then(|s|s.parse::<i64>().ok()),"points":row["points"].as_str().and_then(|s|s.parse::<f64>().ok()),"laps":row["laps"].as_str().and_then(|s|s.parse::<i64>().ok()),"status":row["status"],"grid":row["grid"].as_str().and_then(|s|s.parse::<i64>().ok())})).collect::<Vec<_>>()}));
                        }
                    }
                    Err(error) => warnings.push(format!("{endpoint}: {error}")),
                }
            }
        } else {
            warnings.push("积分历史来源未启用。".into());
        }
        let stale = if let Some(old) = &old_bundle
            && let Some(old) = old["data"]["rounds"].as_array()
        {
            retain_rounds(&mut rows, old)
        } else {
            false
        };
        rows.sort_by_key(|r| (r["round"].as_i64().unwrap_or(0), r["sessionType"] == "正赛"));
        let mut value = envelope(
            json!({"rounds":rows,"warnings":warnings}),
            &now,
            "jolpica-ergast",
        );
        value["meta"]["stale"] = json!(stale);
        if value["data"]["rounds"].as_array().is_none_or(Vec::is_empty) {
            value["meta"]["analysisStatus"] = json!("failed");
        }
        state.analysis.put(state, bundle_key, value.clone()).await?;
        value
    };
    let mut entities: Vec<_> = state
        .database
        .driver_standings(Some(season))
        .await?
        .0
        .iter()
        .map(|r| ("drivers", r.driver_id.clone()))
        .collect();
    entities.extend(
        state
            .database
            .constructor_standings(Some(season))
            .await?
            .0
            .iter()
            .map(|r| ("constructors", r.constructor_id.clone())),
    );
    for (kind, id) in entities {
        let key = Job::Season {
            season,
            kind: kind.into(),
            id: id.clone(),
        }
        .key();
        let mut rows = project_rounds(
            bundle["data"]["rounds"]
                .as_array()
                .map(Vec::as_slice)
                .unwrap_or(&[]),
            kind,
            &id,
        );
        let previous = state.analysis.read(state, &key).await?;
        let mut value = bundle.clone();
        if let Some(old) = previous
            && let Some(old) = old["data"]["rounds"].as_array()
            && retain_rounds(&mut rows, old)
        {
            value["meta"]["stale"] = json!(true);
        }
        if rows.is_empty() {
            value["meta"]["analysisStatus"] = json!("failed");
            value["meta"]["analysisError"] = json!("该对象的逐站明细尚未提供，可稍后重试。");
        }
        value["data"]["rounds"] = json!(rows);
        state.analysis.put(state, key, value).await?;
    }
    Ok(())
}

pub async fn preload(state: AppState) {
    let mut interval = tokio::time::interval(Duration::from_secs(60));
    interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        interval.tick().await;
        if let Err(error) = preload_cycle(&state).await {
            tracing::warn!(%error,"analysis preload failed");
        }
    }
}

async fn preload_job(state: &AppState, job: Job) {
    let key = job.key();
    if state
        .analysis
        .read(state, &key)
        .await
        .ok()
        .flatten()
        .as_ref()
        .is_some_and(fresh_value)
    {
        return;
    }
    if !state.analysis.pending.lock().await.insert(key) {
        return;
    }
    execute(state, job).await;
}

async fn preload_cycle(state: &AppState) -> Result<(), ApiError> {
    let now = state.database.utc_now().await?;
    let season: i64 = now[..4].parse().map_err(|_| invalid("invalid year"))?;
    let mut sessions: Vec<_> = state
        .database
        .calendar(Some(season))
        .await?
        .0
        .iter()
        .flat_map(|m| m.sessions.clone())
        .filter(|s| s.start_time <= now)
        .collect();
    sessions.sort_by(|a, b| b.start_time.cmp(&a.start_time));
    let mut latest = None;
    for session in sessions {
        let mut results = state.database.session_results(&session.id).await?.0;
        if !results.is_empty() && session.openf1_session_key.is_some() {
            results.sort_by_key(|r| (r.position.unwrap_or(i64::MAX), r.driver_id.clone()));
            latest = Some((session, results));
            break;
        }
    }
    if let Some((session, results)) = &latest
        && let Some(first) = results.first()
    {
        preload_job(
            state,
            Job::Session {
                session: session.id.clone(),
                driver: first.driver_id.clone(),
                lap: None,
            },
        )
        .await;
    }
    if let Some(row) = state
        .database
        .driver_standings(Some(season))
        .await?
        .0
        .first()
    {
        preload_job(
            state,
            Job::Season {
                season,
                kind: "drivers".into(),
                id: row.driver_id.clone(),
            },
        )
        .await;
    }
    if let Some((session, results)) = latest {
        for row in results.into_iter().skip(1) {
            preload_job(
                state,
                Job::Session {
                    session: session.id.clone(),
                    driver: row.driver_id,
                    lap: None,
                },
            )
            .await;
        }
    }
    // Backfill one historical session per cycle, retaining the latest-session
    // priority above and avoiding an unbounded upstream burst at startup.
    let mut history: Vec<_> = state
        .database
        .calendar(None)
        .await?
        .0
        .into_iter()
        .flat_map(|meeting| meeting.sessions)
        .filter(|session| {
            session.start_time <= now
                && session.status != crate::domain::calendar::SessionStatus::Cancelled
                && session.openf1_session_key.is_some()
        })
        .collect();
    history.sort_by(|a, b| a.start_time.cmp(&b.start_time));
    for session in history {
        let key = format!("session:{}:bundle", session.id);
        let cached = state.analysis.read(state, &key).await?;
        if cached.as_ref().is_some_and(|value| {
            value["data"]["laps"]
                .as_array()
                .is_some_and(|rows| !rows.is_empty())
        }) {
            continue;
        }
        if cached.as_ref().is_some_and(fresh_value) {
            continue;
        }
        let results = state.database.session_results(&session.id).await?.0;
        if let Some(result) = results.first() {
            preload_job(
                state,
                Job::Session {
                    session: session.id,
                    driver: result.driver_id.clone(),
                    lap: None,
                },
            )
            .await;
            break;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_historical_grid_uses_exact_round_and_preserves_pitlane_start() {
        let races = vec![
            json!({"round":"1","Results":[{"Driver":{"permanentNumber":"16"},"grid":"2"}]}),
            json!({"round":"2","Results":[{"Driver":{"permanentNumber":"1"},"grid":"0"},{"Driver":{"permanentNumber":"44"},"grid":null}]}),
        ];
        assert_eq!(
            historical_grid(&races, 2, "Results"),
            vec![json!({"driverNumber":1,"position":0,"lapDuration":null})]
        );
        assert!(historical_grid(&races, 3, "Results").is_empty());
    }

    #[test]
    fn test_shared_session_and_season_projection_keep_exact_driver_identity() {
        let identity = IdentityMaps::from_ergast(
            &[
                json!({"driverId":"leclerc","permanentNumber":"16"}),
                json!({"driverId":"hamilton","permanentNumber":"44"}),
            ],
            &[],
        );
        let bundle = json!({"drivers":[{"driverNumber":16,"fullName":"Charles LECLERC"},{"driverNumber":44,"fullName":"Paul ARON"}],"laps":[{"driverNumber":16,"lapNumber":1},{"driverNumber":44,"lapNumber":2}],"stints":[],"pit":[],"positions":[],"weather":[],"raceControl":[],"grid":[],"warnings":[]});
        let named = project_session(
            &bundle,
            "paul_aron",
            Some(&identity),
            None,
            Some("Paul Aron"),
        );
        assert_eq!(named["laps"][0]["driverNumber"], 44);
        // A practice classification may carry the season number rather than
        // this session's car number. The unique session roster owns identity.
        let corrected = project_session(
            &bundle,
            "paul_aron",
            Some(&identity),
            Some(16),
            Some("Paul Aron"),
        );
        assert_eq!(corrected["driver"]["driverNumber"], 44);
        assert_eq!(corrected["laps"][0]["driverNumber"], 44);
        let reserve = project_session(&bundle, "reserve_driver", Some(&identity), Some(44), None);
        assert_eq!(reserve["laps"][0]["driverNumber"], 44);
        assert_eq!(reserve["laps"].as_array().unwrap().len(), 1);
        assert!(
            project_session(&bundle, "reserve_driver", Some(&identity), Some(99), None)["laps"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        let data = project_session(&bundle, "leclerc", Some(&identity), None, None);
        assert_eq!(data["laps"].as_array().unwrap().len(), 1);
        assert_eq!(data["laps"][0]["driverNumber"], 16);
        assert!(
            project_session(&bundle, "unknown", Some(&identity), None, None)["laps"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        let races = vec![
            json!({"round":1,"entries":[{"driverId":"leclerc","constructorId":"ferrari","points":null},{"driverId":"hamilton","constructorId":"ferrari","points":8},{"driverId":"other","constructorId":"mercedes","points":3}]}),
        ];
        assert_eq!(
            project_rounds(&races, "drivers", "leclerc")[0]["entries"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            project_rounds(&races, "constructors", "ferrari")[0]["entries"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert!(project_rounds(&races, "drivers", "unknown").is_empty());
    }
    #[test]
    fn test_lap_selection_and_fractional_window() {
        let rows = vec![
            json!({"lapNumber":1,"lapDuration":80.,"dateStart":"2026-10-10T23:59:59.123000+00:00","isPitOutLap":true}),
            json!({"lapNumber":2,"lapDuration":90.,"dateStart":"2026-10-10T23:59:59.123000+00:00"}),
        ];
        assert_eq!(selected_lap(&rows, None).unwrap()["lapNumber"], 2);
        assert!(selected_lap(&rows, Some(1)).is_none());
        let start = normalize_date(rows[1]["dateStart"].as_str().unwrap()).unwrap();
        assert_eq!(add_seconds(&start, 91).unwrap(), "2026-10-11T00:01:30Z");
        assert_eq!(
            camel(json!({"duration_sector_1":null,"n_gear":8})),
            json!({"durationSector1":null,"nGear":8})
        );
    }
    #[test]
    fn test_partial_history_retains_missing_rounds_and_updated_values_win() {
        let previous = vec![
            json!({"round":1,"sessionType":"Sprint","points":8}),
            json!({"round":1,"sessionType":"正赛","points":25}),
        ];
        let mut rows = vec![json!({"round":1,"sessionType":"正赛","points":18})];
        assert!(retain_rounds(&mut rows, &previous));
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0]["points"], 18);
        assert_eq!(rows[1]["points"], 8);
        assert!(!retain_rounds(&mut rows, &previous));
    }
    #[test]
    fn test_failed_sections_retain_known_samples_and_never_overwrite_new_values() {
        let old = json!({"laps":[{"lapNumber":1}],"location":[{"x":10}],"pit":[{"lapNumber":4}],"selectedLap":1,"driver":{"driverNumber":16}});
        let mut data = json!({"laps":[],"location":[],"pit":[{"lapNumber":5}],"warnings":[]});
        assert!(retain_sections(&mut data, &old));
        assert_eq!(data["laps"], old["laps"]);
        assert_eq!(data["pit"][0]["lapNumber"], 5);
        assert_eq!(data["selectedLap"], 1);
        assert_eq!(data["warnings"].as_array().unwrap().len(), 2);
    }
    #[test]
    fn test_cache_failure_retries_before_complete_data_expires() {
        let at = Instant::now() - Duration::from_secs(121);
        assert!(fresh(&at, &json!({"data":{"warnings":[]}})));
        assert!(!fresh(
            &at,
            &json!({"meta":{"analysisStatus":"failed"},"data":{"warnings":["unavailable"]}})
        ));
        assert!(!fresh(
            &(Instant::now() - Duration::from_secs(1801)),
            &json!({"data":{"warnings":[]}})
        ));
    }
    #[test]
    fn test_analysis_cache_bound() {
        let mut cache = HashMap::new();
        for n in 0..200 {
            insert(&mut cache, n.to_string(), json!({}));
        }
        assert_eq!(cache.len(), 128);
    }
}
