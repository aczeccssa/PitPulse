use std::time::{Duration, Instant};

use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::{
        calendar::Meeting,
        live::{LiveLocation, LiveSnapshot, LiveTelemetry, LiveWeather},
        standings::DriverStanding,
    },
    server,
    services::circuits::{GEOMETRY, distance},
    storage::sqlite::Database,
};
use serde_json::{Value, json};

const FIXTURE: &str = include_str!("../../tests/fixtures/singapore-sprint-demo.json");

fn frame(base: &LiveSnapshot, points: &[[f64; 2]], elapsed: f64, utc: &str) -> LiveSnapshot {
    let mut snapshot = base.clone();
    snapshot.updated_at = Some(utc.into());
    snapshot.last_transport_at = Some(utc.into());
    snapshot.lap_count = Some(8 + (elapsed / 92.0) as i64 % 12);
    let lengths: Vec<f64> = points
        .windows(2)
        .map(|p| distance(p[0][0], p[0][1], p[1][0], p[1][1]))
        .collect();
    let total: f64 = lengths.iter().sum();
    assert!(
        total > 4000.0,
        "demo must use the actual bundled circuit outline"
    );
    for (index, driver) in snapshot.drivers.iter_mut().enumerate() {
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
        // Synthetic geographic motion exists only in this explicit replay example.
        driver.location = Some(LiveLocation {
            x: 0.0,
            y: 0.0,
            utc: utc.into(),
            status: Some("OnTrack".into()),
            longitude: Some(a[0] + (b[0] - a[0]) * fraction),
            latitude: Some(a[1] + (b[1] - a[1]) * fraction),
        });
        let wave = (phase * std::f64::consts::TAU * 9.0).sin();
        driver.telemetry = Some(LiveTelemetry {
            utc: utc.into(),
            speed: Some(190.0 + wave * 105.0),
            rpm: Some(10300.0 + wave * 1800.0),
            gear: Some((5.0 + wave * 3.0).round()),
            throttle: Some(if wave < -0.7 { 15.0 } else { 100.0 }),
            brake: Some(if wave < -0.7 { 100.0 } else { 0.0 }),
            drs: Some(if wave > 0.8 { 12.0 } else { 0.0 }),
        });
        driver.lap_count = snapshot.lap_count;
        if index > 0 {
            driver.gap = Some(format!(
                "+{:.3}",
                index as f64 * 1.35 + (elapsed / 7.0).sin() * 0.3
            ));
        }
    }
    snapshot.weather = Some(LiveWeather {
        utc: utc.into(),
        air_temp: Some(29.5),
        track_temp: Some(34.2),
        humidity: Some(78.0),
        pressure: Some(1008.0),
        wind_speed: Some(2.4),
        wind_direction: Some(140.0),
        rainfall: Some(false),
    });
    snapshot.race_control = Some(vec![
        json!({"id":"mock-green", "utc":utc, "Message":"MOCK · GREEN LIGHT — TRACK CLEAR", "Category":"Flag", "Flag":"GREEN", "lap":snapshot.lap_count}),
        json!({"id":"mock-limits", "utc":utc, "Message":"MOCK · CAR 12 — TRACK LIMITS AT TURN 7", "Category":"Other", "driverNumber":"12", "lap":7}),
    ]);
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
        let mut timer = tokio::time::interval(Duration::from_millis(100));
        timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            timer.tick().await;
            if let Ok(utc) = replay_state.database.utc_now().await {
                replay_state.live.publish(
                    frame(&snapshot, &points, started.elapsed().as_secs_f64(), &utc),
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
        let a = frame(&base, &points, 0.0, "2026-10-11T06:00:00Z");
        let b = frame(&base, &points, 1.0, "2026-10-11T06:00:01Z");
        assert_eq!(
            a.source_mode,
            pitpulse_server::domain::live::LiveSourceMode::Replay
        );
        assert!(a.session_id.as_ref().unwrap().starts_with("mock-"));
        assert_eq!(a.drivers.len(), 22);
        assert_ne!(a.drivers[0].location, b.drivers[0].location);
        assert_eq!(
            b.drivers[0].telemetry.as_ref().unwrap().utc,
            b.updated_at.unwrap()
        );
        assert!(b.team_radio.is_empty());
        assert_eq!(b.total_laps, Some(19));
    }
}
