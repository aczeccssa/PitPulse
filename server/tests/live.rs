use std::time::Duration;

use axum::{body::Body, http::Request};
use futures_util::StreamExt;
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::live::{LiveSnapshot, LiveSourceMode, LiveStatus},
    server,
    storage::sqlite::Database,
};
use serde_json::Value;
use tempfile::TempDir;
use tower::ServiceExt;

async fn test_state() -> (AppState, TempDir) {
    let temp = tempfile::tempdir().expect("create temp dir");
    let mut config = AppConfig::default();
    config.database.path = temp.path().join("live.sqlite");
    let database = Database::open(&config.database.path)
        .await
        .expect("open database");
    database.migrate().await.expect("migrate database");
    (AppState::new(config, database), temp)
}

#[tokio::test]
async fn test_snapshot_returns_replay_source_without_claiming_live() {
    let (state, _temp) = test_state().await;
    let replay = LiveSnapshot {
        source_mode: LiveSourceMode::Replay,
        source_status: LiveStatus::Connected,
        status_reason: Some("fixture_replay".to_string()),
        session_name: Some("Replay Practice".to_string()),
        lap_count: Some(4),
        ..LiveSnapshot::default()
    };
    state.live.publish(replay, true);
    let response = server::router(state)
        .oneshot(
            Request::builder()
                .uri("/api/v1/live/snapshot")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(value["data"]["sourceMode"], "replay");
    assert_eq!(value["data"]["sourceStatus"], "connected");
    assert_eq!(value["data"]["lapCount"], 4);
}

#[tokio::test]
async fn test_live_stream_starts_with_full_snapshot_and_emits_status_immediately() {
    let (state, _temp) = test_state().await;
    let mut snapshot = LiveSnapshot {
        source_mode: LiveSourceMode::Replay,
        source_status: LiveStatus::Connected,
        session_id: Some("replay-session-1".to_string()),
        lap_count: Some(4),
        ..LiveSnapshot::default()
    };
    snapshot.state_version = 1;
    state.live.publish(snapshot, true);
    let response = server::router(state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/v1/live/stream")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let mut chunks = response.into_body().into_data_stream();
    let first = tokio::time::timeout(Duration::from_secs(1), chunks.next())
        .await
        .expect("initial event is immediate")
        .expect("SSE stream remains open")
        .unwrap();
    let first = String::from_utf8(first.to_vec()).unwrap();
    assert!(first.contains("event: snapshot"));
    assert!(first.contains("\"sessionId\":\"replay-session-1\""));
    assert!(first.contains("\"sourceMode\":\"replay\""));

    state.live.mark_status(LiveStatus::Stale, "data_stale");
    let next = tokio::time::timeout(Duration::from_secs(1), chunks.next())
        .await
        .expect("status change is immediate")
        .expect("SSE stream remains open")
        .unwrap();
    assert!(
        String::from_utf8(next.to_vec())
            .unwrap()
            .contains("\"sourceStatus\":\"stale\"")
    );
}

#[tokio::test(start_paused = true)]
async fn test_live_stream_coalesces_bursts_and_slow_reader_gets_latest() {
    let (state, _temp) = test_state().await;
    state.live.publish(
        LiveSnapshot {
            source_status: LiveStatus::Connected,
            ..LiveSnapshot::default()
        },
        true,
    );
    let response = server::router(state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/v1/live/stream")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let mut chunks = response.into_body().into_data_stream();
    chunks.next().await.unwrap().unwrap();
    for lap in 1..=40 {
        let mut s = (*state.live.current()).clone();
        s.lap_count = Some(lap);
        state.live.publish(s, true);
    }
    assert!(
        tokio::time::timeout(Duration::from_millis(99), chunks.next())
            .await
            .is_err()
    );
    let next = tokio::time::timeout(Duration::from_millis(2), chunks.next())
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert!(
        String::from_utf8(next.to_vec())
            .unwrap()
            .contains("\"lapCount\":40")
    );
    for lap in 41..=80 {
        let mut s = (*state.live.current()).clone();
        s.lap_count = Some(lap);
        state.live.publish(s, true);
    }
    tokio::time::sleep(Duration::from_millis(300)).await;
    let latest = chunks.next().await.unwrap().unwrap();
    assert!(
        String::from_utf8(latest.to_vec())
            .unwrap()
            .contains("\"lapCount\":80")
    );
    assert!(
        tokio::time::timeout(Duration::from_millis(100), chunks.next())
            .await
            .is_err()
    );
}
