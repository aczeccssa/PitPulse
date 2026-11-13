use std::{
    net::{IpAddr, Ipv4Addr, SocketAddr},
    time::Duration,
};

use anyhow::Context;
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::{
        live::{LiveSourceMode, LiveStatus},
        standings::DriverStanding,
    },
    providers::f1_live::reducer::LiveTopicReducer,
    server,
    storage::sqlite::Database,
};
use serde_json::Value;

#[path = "support/singapore_sprint.rs"]
mod singapore_sprint;

const FIXTURE: &str = include_str!("../tests/fixtures/f1-live-replay.json");

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let scenario = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "normal".to_string());
    anyhow::ensure!(
        [
            "normal",
            "missing-fields",
            "stale",
            "disconnected",
            "finished",
            "session-switch",
            "singapore-sprint"
        ]
        .contains(&scenario.as_str()),
        "usage: cargo run --example live_replay -- [normal|missing-fields|stale|disconnected|finished|session-switch|singapore-sprint]"
    );
    let mut config = AppConfig::load(None).context("load local server settings")?;
    config.server.bind =
        SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), config.server.bind.port());
    config.providers.f1_live_enabled = false;
    config.database.path = std::env::temp_dir().join(format!(
        "pitpulse-live-replay-{}.sqlite",
        std::process::id()
    ));
    if scenario == "stale" || scenario == "disconnected" {
        config.live.stale_after_seconds = 2;
    }
    if scenario == "stale" {
        config.live.disconnect_after_seconds = 600;
    }
    if scenario == "disconnected" {
        config.live.disconnect_after_seconds = 4;
    }
    let database = Database::open(&config.database.path).await?;
    database.migrate().await?;
    if scenario == "singapore-sprint" {
        return singapore_sprint::run(config, database).await;
    }
    if scenario != "missing-fields" {
        let fetched_at = database.utc_now().await?;
        let season = fetched_at[..4].parse::<i64>()?;
        database
            .replace_driver_standings(
                [
                    ("sample-one", "Sample Driver One"),
                    ("sample-two", "Sample Driver Two"),
                ]
                .into_iter()
                .enumerate()
                .map(|(index, (id, name))| DriverStanding {
                    driver_number: None,
                    season,
                    position: index as i64 + 1,
                    driver_id: id.into(),
                    driver_name: name.into(),
                    constructor: "Sample Team".into(),
                    constructor_ids: vec![],
                    points: 0.0,
                    wins: 0,
                    source: "fixture_replay".into(),
                    fetched_at: fetched_at.clone(),
                    revision: 1,
                })
                .collect(),
            )
            .await?;
    }
    let state = AppState::new(config, database);
    let freshness_state = state.clone();
    let freshness_scenario = scenario.clone();
    let freshness = if matches!(scenario.as_str(), "stale" | "disconnected") {
        Some(tokio::spawn(async move {
            while freshness_state.live.subscriber_count() == 0 {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
            let mut interval = tokio::time::interval(Duration::from_millis(200));
            loop {
                interval.tick().await;
                if freshness_state.live.check_freshness(
                    Duration::from_secs(freshness_state.config.live.stale_after_seconds),
                    Duration::from_secs(freshness_state.config.live.disconnect_after_seconds),
                ) && freshness_scenario == "disconnected"
                {
                    break;
                }
            }
        }))
    } else {
        None
    };
    let replay_state = state.clone();
    let replay_scenario = scenario.clone();
    let replay = tokio::spawn(async move {
        let fixture = serde_json::from_str::<Value>(FIXTURE).expect("replay fixture is valid JSON");
        let mut lap = 4i64;
        let mut update = 0usize;
        loop {
            if replay_scenario == "disconnected" && update > 0 {
                tokio::time::sleep(Duration::from_secs(5)).await;
                continue;
            }
            let Ok(received_at) = replay_state.database.utc_now().await else {
                tracing::warn!("could not timestamp replay fixture");
                tokio::time::sleep(Duration::from_secs(5)).await;
                continue;
            };
            let mut message = fixture.clone();
            if replay_scenario == "missing-fields" {
                message["LapCount"]["CurrentLap"] = Value::Null;
                message["LapCount"]["TotalLaps"] = Value::Null;
                message["TimingData"]["Lines"]["44"]["Sectors"] = Value::Null;
                message["TimingData"]["Lines"]["44"]
                    .as_object_mut()
                    .unwrap()
                    .remove("GapToLeader");
                message["RaceControlMessages"]["Messages"]["1"] =
                    serde_json::json!({"Category": "Other", "NewField": true});
            }
            if replay_scenario == "session-switch" && update >= 2 {
                message["SessionInfo"]["Key"] = "replay-session-2".into();
                message["SessionInfo"]["Name"] = "Replay Qualifying".into();
                message["SessionInfo"]["Type"] = "Qualifying".into();
            }
            if replay_scenario == "session-switch" && update == 1 {
                message["SessionStatus"]["Status"] = "Finished".into();
            }
            if replay_scenario == "finished" && update >= 1 {
                message["SessionStatus"]["Status"] = "Finished".into();
            }
            if replay_scenario != "missing-fields" {
                message["LapCount"]["CurrentLap"]["Value"] = (lap % 7 + 1).into();
                message["TimingData"]["Lines"]["44"]["Sectors"][0]["Segments"][0]["Status"] =
                    Value::from(if update.is_multiple_of(2) { 2049 } else { 2051 });
            }
            for line in message["TimingData"]["Lines"]
                .as_object_mut()
                .unwrap()
                .values_mut()
            {
                line["NumberOfLaps"] = (lap % 7 + 1).into();
            }
            if let Some(mut reduced) =
                LiveTopicReducer::default().apply_batch(&message, &received_at)
            {
                reduced.snapshot.source_mode = LiveSourceMode::Replay;
                reduced.snapshot.source_status = LiveStatus::Connected;
                reduced.snapshot.status_reason = Some("fixture_replay".to_string());
                replay_state
                    .live
                    .publish(reduced.snapshot, reduced.data_updated);
            }
            lap += 1;
            update += 1;
            if update == 1 && matches!(replay_scenario.as_str(), "finished" | "session-switch") {
                while replay_state.live.subscriber_count() == 0 {
                    tokio::time::sleep(Duration::from_millis(50)).await;
                }
            }
            if replay_scenario == "stale" {
                loop {
                    tokio::time::sleep(Duration::from_secs(30)).await;
                }
            }
            let delay = if replay_scenario == "session-switch" && update == 2 {
                // Hold Finished across a periodic SSE snapshot before publishing the next Session.
                let delay =
                    Duration::from_secs(replay_state.config.live.snapshot_interval_seconds + 5);
                assert!(
                    delay.as_secs()
                        > replay_state
                            .config
                            .live
                            .snapshot_interval_seconds
                            .clamp(10, 30)
                );
                delay
            } else {
                Duration::from_secs(5)
            };
            tokio::time::sleep(delay).await;
        }
    });
    tracing::info!(address = %state.config.server.bind, scenario = %scenario, "starting loopback-only explicit Live replay; data is synthetic fixture only");
    let result = server::serve(state).await;
    replay.abort();
    let _ = replay.await;
    if let Some(freshness) = freshness {
        freshness.abort();
        let _ = freshness.await;
    }
    result.context("replay server stopped unexpectedly")
}
