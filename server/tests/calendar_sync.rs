use std::time::Duration;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    providers::{
        http::next_page,
        jolpica::{decode_alpha_schedule, fp1_availability, result_position},
        openf1,
    },
    services::sync::CalendarSync,
    storage::sqlite::Database,
};
use serde_json::{Value, json};
use tempfile::TempDir;
use tower::ServiceExt;

async fn database() -> (Database, TempDir) {
    let temp = tempfile::tempdir().unwrap();
    let database = Database::open(&temp.path().join("pitpulse.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    (database, temp)
}

fn sync() -> CalendarSync {
    CalendarSync {
        jolpica: pitpulse_server::providers::jolpica::JolpicaProvider::with_base_url(
            reqwest::Client::new(),
            "http://127.0.0.1:9",
        ),
        openf1: openf1::OpenF1Provider::with_base_url(reqwest::Client::new(), "http://127.0.0.1:9"),
        timeout: Duration::from_millis(20),
    }
}

#[tokio::test]
async fn test_fixture_sync_makes_calendar_api_nonempty() {
    let (database, temp) = database().await;
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    sync().sync_fixture(&database, &payload).await.unwrap();

    let mut config = AppConfig::default();
    config.database.path = temp.path().join("pitpulse.sqlite");
    let state = AppState::new(config, database);
    let response = pitpulse_server::server::router(state)
        .oneshot(
            Request::builder()
                .uri("/api/v1/calendar?season=2026")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value: Value = serde_json::from_slice(&body).unwrap();
    assert!(!value["data"].as_array().unwrap().is_empty());
    assert_eq!(value["data"][0]["sessions"][0]["sessionType"], "fp1");
    assert_eq!(value["meta"]["schemaVersion"], 1);
    assert_eq!(value["meta"]["stale"], true);
}

#[tokio::test]
async fn test_repeat_sync_is_idempotent_until_time_changes() {
    let (database, _temp) = database().await;
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    sync().sync_fixture(&database, &payload).await.unwrap();
    sync().sync_fixture(&database, &payload).await.unwrap();
    let (first, _) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(first[0].revision, Some(1));
    assert_eq!(first[0].sessions.len(), 5);

    let mut changed = payload.clone();
    changed["data"]["events"][0]["schedule"][0]["timestamp"] = json!("2026-03-06T02:00:00Z");
    sync().sync_fixture(&database, &changed).await.unwrap();
    let (second, _) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(second[0].revision, Some(2));
    assert_eq!(second[0].sessions.len(), 5);
}

#[tokio::test]
async fn test_edge_calendar_covers_sprint_cancel_unknown_country() {
    let payload: Value = serde_json::from_str(include_str!(
        "fixtures/jolpica-alpha-2026-calendar-edge.json"
    ))
    .unwrap();
    let meetings = decode_alpha_schedule(&payload).unwrap();
    assert_eq!(meetings.len(), 4, "pre-season testing is excluded");
    assert!(meetings.iter().any(|meeting| {
        meeting
            .sessions
            .iter()
            .any(|session| session.session_type.as_str() == "sprint")
    }));
    assert!(
        meetings
            .iter()
            .any(|meeting| meeting.status.as_str() == "cancelled" && meeting.round.is_none())
    );
    assert!(
        meetings
            .iter()
            .any(|meeting| meeting.country_code.is_none() && meeting.country == "Unknownland")
    );
}

#[tokio::test]
async fn test_next_meeting_uses_future_scheduled_session_and_excludes_cancelled() {
    let (database, _temp) = database().await;
    let mut payload: Value = serde_json::from_str(include_str!(
        "fixtures/jolpica-alpha-2026-calendar-edge.json"
    ))
    .unwrap();
    for event in payload["data"]["events"].as_array_mut().unwrap() {
        if event["round"]["is_cancelled"] == Value::Bool(true) {
            event["round"]["number"] = json!(4);
        }
    }
    sync().sync_fixture(&database, &payload).await.unwrap();

    let (china, _) = database
        .next_meeting_at(Some(2026), "2026-03-10T00:00:00Z")
        .await
        .unwrap();
    assert_eq!(china.unwrap().name, "Chinese Grand Prix");

    let (mystery, _) = database
        .next_meeting_at(Some(2026), "2026-03-20T00:00:00Z")
        .await
        .unwrap();
    assert_eq!(mystery.unwrap().name, "Mystery Grand Prix");

    let (none, _) = database
        .next_meeting_at(Some(2026), "2026-05-01T00:00:00Z")
        .await
        .unwrap();
    assert!(none.is_none());
}

#[tokio::test]
async fn test_pagination_and_nullable_result_position() {
    let page: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-ergast-page.json")).unwrap();
    let next = next_page(&page).unwrap();
    assert!(next.contains("offset=1"));
    assert!(next.contains("limit=1"));
    assert!(next.contains("season=2026"));

    let fp1: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-fp1-available.json")).unwrap();
    assert_eq!(fp1_availability(&fp1).as_str(), "available");
    let race: Value = serde_json::from_str(include_str!("fixtures/jolpica-race-nc.json")).unwrap();
    assert_eq!(result_position(&race["data"]["results"][0]), None);
    let openf1: Value =
        serde_json::from_str(include_str!("fixtures/openf1-race-null-position.json")).unwrap();
    assert_eq!(openf1::result_position(&openf1[1]), None);
}

#[tokio::test]
async fn test_old_database_upgrades_and_timeout_keeps_cache() {
    let temp = tempfile::tempdir().unwrap();
    let path = temp.path().join("legacy.sqlite");
    {
        let connection = rusqlite::Connection::open(&path).unwrap();
        connection
            .execute_batch(include_str!("../src/storage/migrations/0001_init.sql"))
            .unwrap();
        connection
            .execute_batch("PRAGMA user_version = 1;")
            .unwrap();
    }
    let database = Database::open(&path).await.unwrap();
    database.migrate().await.unwrap();
    assert_eq!(database.user_version().await.unwrap(), 8);
    database.migrate().await.unwrap();

    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    sync().sync_fixture(&database, &payload).await.unwrap();
    let error = sync().sync_season(&database, 2026).await.unwrap_err();
    assert!(error.to_string().contains("timed out") || error.to_string().contains("failed"));
    let (cached, meta) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(cached.len(), 1);
    assert!(meta.stale);
}

#[tokio::test]
async fn test_empty_results_are_pending_not_server_error() {
    let (database, temp) = database().await;
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    sync().sync_fixture(&database, &payload).await.unwrap();
    let mut config = AppConfig::default();
    config.database.path = temp.path().join("pitpulse.sqlite");
    let state = AppState::new(config, database);
    let response = pitpulse_server::server::router(state)
        .oneshot(
            Request::builder()
                .uri("/api/v1/sessions/2026:1:fp1/results")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(value["data"], json!([]));
    assert_eq!(value["meta"]["quality"], "pending");
}

#[tokio::test]
async fn test_server_fetch_time_is_not_provider_update_time() {
    let (database, _temp) = database().await;
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    let meetings = decode_alpha_schedule(&payload).unwrap();
    let fetched_at = database.utc_now().await.unwrap();
    assert!(fetched_at.ends_with('Z'));
    database
        .replace_calendar(&meetings, &fetched_at)
        .await
        .unwrap();
    let (_, meta) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(meta.fetched_at.as_deref(), Some(fetched_at.as_str()));
    assert!(
        meta.source_updated_at.is_none(),
        "unknown provider timestamp must not be fabricated"
    );
}

#[tokio::test]
async fn test_expired_calendar_is_stale_until_successful_refresh() {
    let (database, _temp) = database().await;
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    let meetings = decode_alpha_schedule(&payload).unwrap();
    database
        .replace_calendar(&meetings, "2000-01-01T00:00:00Z")
        .await
        .unwrap();
    let (cached, meta) = database.calendar(Some(2026)).await.unwrap();
    assert!(!cached.is_empty());
    assert!(meta.stale);
    assert_eq!(serde_json::to_value(meta.quality).unwrap(), "stale");
    let (_, next_meta) = database.next_meeting(Some(2026)).await.unwrap();
    assert!(next_meta.stale);

    let now = database.utc_now().await.unwrap();
    database.replace_calendar(&meetings, &now).await.unwrap();
    let (_, refreshed_meta) = database.calendar(Some(2026)).await.unwrap();
    assert!(!refreshed_meta.stale);
}

#[test]
fn test_brazil_alias_links_all_sessions_without_linking_other_events() {
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    let mut meetings = decode_alpha_schedule(&payload).unwrap();
    meetings[0].name = "Brazilian Grand Prix".into();
    let open_meetings = vec![
        json!({"meeting_name":"São Paulo Grand Prix","meeting_key":1299,"is_cancelled":false}),
    ];
    let sessions: Vec<_> = meetings[0].sessions.iter().enumerate().map(|(i,s)| json!({"meeting_key":1299,"session_name":s.session_type.as_str(),"session_key":11405+i,"date_end":"2026-11-08T19:00:00Z"})).collect();
    openf1::supplement_calendar(&mut meetings, &open_meetings, &sessions);
    assert!(
        meetings[0]
            .sessions
            .iter()
            .all(|s| s.openf1_session_key.is_some())
    );
    meetings[0].name = "Australian Grand Prix".into();
    for session in &mut meetings[0].sessions {
        session.openf1_session_key = None;
    }
    openf1::supplement_calendar(&mut meetings, &open_meetings, &sessions);
    assert!(
        meetings[0]
            .sessions
            .iter()
            .all(|s| s.openf1_session_key.is_none())
    );
}
