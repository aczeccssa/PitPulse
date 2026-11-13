use std::time::{Duration, Instant};

use base64::{Engine, engine::general_purpose::STANDARD};
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::{
        calendar::Meeting,
        live::{LiveSnapshot, LiveSourceMode, LiveStatus},
        standings::DriverStanding,
    },
    providers::f1_live::reducer::LiveTopicReducer,
    server,
    services::circuits::{GEOMETRY, calibration, distance},
    storage::sqlite::Database,
};
use serde_json::{Value, json};

const FIXTURE: &str = include_str!("../../tests/fixtures/singapore-sprint-demo.json");

fn compressed(value: Value) -> Value {
    use std::io::Write;
    let mut encoder = flate2::write::DeflateEncoder::new(Vec::new(), flate2::Compression::fast());
    encoder
        .write_all(&serde_json::to_vec(&value).unwrap())
        .unwrap();
    json!(STANDARD.encode(encoder.finish().unwrap()))
}

fn position_xy(longitude: f64, latitude: f64) -> (f64, f64) {
    let calibration = calibration("61", 2026).expect("Singapore 2026 calibration is valid");
    let [a, b, c] = calibration.anchors;
    let blon = b.longitude - a.longitude;
    let clon = c.longitude - a.longitude;
    let blat = b.latitude - a.latitude;
    let clat = c.latitude - a.latitude;
    let determinant = blon * clat - clon * blat;
    let lon = longitude - a.longitude;
    let lat = latitude - a.latitude;
    let u = (lon * clat - clon * lat) / determinant;
    let v = (blon * lat - lon * blat) / determinant;
    (
        a.x + u * (b.x - a.x) + v * (c.x - a.x),
        a.y + u * (b.y - a.y) + v * (c.y - a.y),
    )
}

fn sample_utc(received_at: &str, elapsed: f64) -> String {
    let second = received_at
        .split('.')
        .next()
        .unwrap_or(received_at)
        .trim_end_matches('Z');
    format!("{second}.{:03}Z", (elapsed.fract() * 1000.0) as u16)
}

fn frame(
    base: &LiveSnapshot,
    points: &[[f64; 2]],
    elapsed: f64,
    received_at: &str,
    reducer: &mut LiveTopicReducer,
) -> LiveSnapshot {
    let utc = sample_utc(received_at, elapsed);
    let lengths: Vec<f64> = points
        .windows(2)
        .map(|p| distance(p[0][0], p[0][1], p[1][0], p[1][1]))
        .collect();
    let total: f64 = lengths.iter().sum();
    assert!(
        total > 4000.0,
        "demo must use the actual bundled circuit outline"
    );
    let mut drivers = serde_json::Map::new();
    let mut lines = serde_json::Map::new();
    let mut positions = serde_json::Map::new();
    let mut telemetry = serde_json::Map::new();
    for (index, driver) in base.drivers.iter().enumerate() {
        let phase = (elapsed / 92.0 - index as f64 * 0.009).rem_euclid(1.0);
        let mut remaining = phase * total;
        let mut segment = 0;
        while segment < lengths.len() - 1 && remaining > lengths[segment] {
            remaining -= lengths[segment];
            segment += 1;
        }
        let fraction = remaining / lengths[segment].max(0.001);
        let a = points[segment];
        let b = points[segment + 1];
        let (x, y) = position_xy(
            a[0] + (b[0] - a[0]) * fraction,
            a[1] + (b[1] - a[1]) * fraction,
        );
        let wave = (phase * std::f64::consts::TAU * 9.0).sin();
        let number = &driver.number;
        drivers.insert(
            number.clone(),
            json!({
                "RacingNumber": number,
                "FullName": driver.name,
                "Tla": driver.name.as_deref().and_then(|name| name.split_whitespace().last()),
                "TeamName": driver.team,
            }),
        );
        lines.insert(number.clone(), json!({
            "Position": index + 1,
            "NumberOfLaps": 8 + (elapsed / 92.0) as i64 % 12,
            "GapToLeader": if index == 0 { "LEADER".to_string() } else { format!("+{:.3}", index as f64 * 1.35 + (elapsed / 7.0).sin() * 0.3) },
        }));
        positions.insert(number.clone(), json!({"X":x,"Y":y,"Status":"OnTrack"}));
        telemetry.insert(
            number.clone(),
            json!({"Channels": {
                "0": 10300.0 + wave * 1800.0,
                "2": 190.0 + wave * 105.0,
                "3": (5.0 + wave * 3.0).round(),
                "4": if wave < -0.7 { 15.0 } else { 100.0 },
                "5": if wave < -0.7 { 100.0 } else { 0.0 },
                "45": if wave > 0.8 { 12.0 } else { 0.0 },
            }}),
        );
    }
    let lap_count = 8 + (elapsed / 92.0) as i64 % 12;
    let feed = json!({
        "SessionInfo": {"Key":"mock-singapore-2026-sprint","Name":"Sprint · MOCK","Type":"Sprint","Path":"2026/singapore/sprint/","Meeting":{"Name":"Singapore Grand Prix · MOCK","Country":{"Name":"Singapore"},"Circuit":{"Key":"61","ShortName":"Marina Bay"}}},
        "SessionStatus": {"Status":"Started"},
        "DriverList": drivers,
        "TimingData": {"Lines":lines},
        "LapCount": {"CurrentLap":{"Value":lap_count},"TotalLaps":19},
        "Position.z": compressed(json!({"Position":[{"Timestamp":utc,"Entries":positions}]})),
        "CarData.z": compressed(json!({"Entries":[{"Utc":utc,"Cars":telemetry}]})),
        "WeatherData": {"AirTemp":"29.5","TrackTemp":"34.2","Humidity":"78","Pressure":"1008","WindSpeed":"2.4","WindDirection":"140","Rainfall":"0"},
        "RaceControlMessages": {"Messages":{"1":{"Utc":utc,"Message":"MOCK · GREEN LIGHT — TRACK CLEAR","Category":"Flag","Flag":"GREEN"},"2":{"Utc":utc,"Message":"MOCK · CAR 12 — TRACK LIMITS AT TURN 7","Category":"Other","RacingNumber":"12"}}}
    });
    let mut snapshot = reducer
        .apply_batch(&feed, received_at)
        .expect("mock feed is accepted")
        .snapshot;
    snapshot.source_mode = LiveSourceMode::Replay;
    snapshot.source_status = LiveStatus::Connected;
    snapshot.status_reason = Some("fixture_replay".to_string());
    snapshot
}

pub async fn run(mut config: AppConfig, database: Database) -> anyhow::Result<()> {
    config.providers.jolpica_enabled = false;
    config.providers.openf1_enabled = false;
    let fixture: Value = serde_json::from_str(FIXTURE)?;
    let meeting: Meeting = serde_json::from_value(fixture["meeting"].clone())?;
    let now = database.utc_now().await?;
    database.replace_calendar(&[meeting], &now).await?;
    let snapshot: LiveSnapshot = serde_json::from_value(fixture["snapshot"].clone())?;
    database
        .replace_driver_standings(
            snapshot
                .drivers
                .iter()
                .enumerate()
                .map(|(index, d)| DriverStanding {
                    driver_number: Some(d.number.clone()),
                    season: 2026,
                    position: index as i64 + 1,
                    driver_id: d
                        .name
                        .as_ref()
                        .unwrap()
                        .split_whitespace()
                        .last()
                        .unwrap()
                        .to_lowercase(),
                    driver_name: d.name.clone().unwrap(),
                    constructor: d.team.clone().unwrap(),
                    constructor_ids: vec![],
                    points: 0.0,
                    wins: 0,
                    source: "fixture_mock".into(),
                    fetched_at: now.clone(),
                    revision: 1,
                })
                .collect(),
        )
        .await?;
    let geometry: Value = serde_json::from_str(GEOMETRY)?;
    let points: Vec<[f64; 2]> = serde_json::from_value(
        geometry["features"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["properties"]["id"] == "sg-2008")
            .unwrap()["geometry"]["coordinates"]
            .clone(),
    )?;
    let state = AppState::new(config, database);
    let replay_state = state.clone();
    let replay = tokio::spawn(async move {
        let started = Instant::now();
        let mut reducer = LiveTopicReducer::default();
        let mut timer = tokio::time::interval(Duration::from_millis(100));
        timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            timer.tick().await;
            if let Ok(utc) = replay_state.database.utc_now().await {
                replay_state.live.publish(
                    frame(
                        &snapshot,
                        &points,
                        started.elapsed().as_secs_f64(),
                        &utc,
                        &mut reducer,
                    ),
                    true,
                );
            }
        }
    });
    println!(
        "Singapore Sprint MOCK replay on {}; all timing, weather and car positions are synthetic",
        state.config.server.bind
    );
    let result = server::serve(state).await;
    replay.abort();
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn demo_is_explicit_replay_with_fresh_moving_cars_and_no_audio() {
        let fixture: Value = serde_json::from_str(FIXTURE).unwrap();
        let base: LiveSnapshot = serde_json::from_value(fixture["snapshot"].clone()).unwrap();
        let points = [
            [103.864, 1.29],
            [103.884, 1.29],
            [103.884, 1.31],
            [103.864, 1.29],
        ];
        let mut reducer = LiveTopicReducer::default();
        let a = frame(&base, &points, 0.0, "2026-10-11T06:00:00Z", &mut reducer);
        let b = frame(&base, &points, 0.1, "2026-10-11T06:00:00Z", &mut reducer);
        assert_eq!(
            a.source_mode,
            pitpulse_server::domain::live::LiveSourceMode::Replay
        );
        assert!(a.session_id.as_ref().unwrap().starts_with("mock-"));
        assert_eq!(a.drivers.len(), 22);
        assert_ne!(a.drivers[0].location, b.drivers[0].location);
        assert_eq!(b.position_diagnostics.as_ref().unwrap().received, 22);
        assert_eq!(b.position_diagnostics.as_ref().unwrap().decoded, 22);
        assert_eq!(b.position_diagnostics.as_ref().unwrap().calibrated, 22);
        assert!(
            b.drivers
                .iter()
                .all(|driver| driver.location.as_ref().is_some_and(|position| {
                    position.received_at.as_deref() == Some("2026-10-11T06:00:00Z")
                        && position.longitude.is_some()
                        && position.latitude.is_some()
                }))
        );
        assert_eq!(
            b.drivers[0].telemetry.as_ref().unwrap().utc,
            "2026-10-11T06:00:00.100000000Z"
        );
        assert_eq!(
            b.drivers[0]
                .telemetry
                .as_ref()
                .unwrap()
                .received_at
                .as_deref(),
            Some("2026-10-11T06:00:00Z")
        );
        assert!(b.team_radio.is_empty());
        assert_eq!(b.total_laps, Some(19));
    }
}
