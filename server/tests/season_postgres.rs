use std::time::{SystemTime, UNIX_EPOCH};

use axum::{
    body::{Body, to_bytes},
    http::{Request, StatusCode},
};
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    server,
    storage::{postgres::Postgres, sqlite::Database},
};
use serde_json::Value;
use tower::ServiceExt;

async fn response(router: &axum::Router, path: &str) -> (StatusCode, Value) {
    let response = router
        .clone()
        .oneshot(Request::get(path).body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = to_bytes(response.into_body(), 4 * 1024 * 1024)
        .await
        .unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

#[tokio::test]
#[ignore = "requires a disposable Postgres database and PITPULSE_TEST_DATABASE_URL"]
async fn imported_history_matches_http_contract_with_clean_sqlite() {
    let dsn = std::env::var("PITPULSE_TEST_DATABASE_URL").expect("set PITPULSE_TEST_DATABASE_URL");
    let read_dsn = std::env::var("PITPULSE_TEST_READ_DATABASE_URL").unwrap_or_else(|_| dsn.clone());
    let read_role = std::env::var("PITPULSE_TEST_READER_ROLE").ok();
    let schema = format!(
        "pitpulse_test_{}_{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let postgres = Postgres::new(&dsn, &schema, false).unwrap();
    postgres.migrate(read_role.as_deref()).await.unwrap();
    let temp = tempfile::tempdir().unwrap();
    let fixture = temp.path().join("fixture.sqlite");
    let legacy = Database::open(&fixture).await.unwrap();
    legacy.migrate().await.unwrap();
    let fixture_sql = rusqlite::Connection::open(&fixture).unwrap();
    fixture_sql.execute_batch(
        "INSERT INTO meetings (id, season, round, name, country, location, start_date, end_date, source, fetched_at, jolpica_round_id)
         VALUES ('2024:1', 2024, 1, 'Fixture GP', 'Fixture Country', 'Fixture City', '2024-03-01', '2024-03-03', 'fixture', '2024-03-01T01:00:00Z', 'fixture-round');
         INSERT INTO sessions (id, meeting_id, session_type, start_time, status, source, fetched_at, openf1_session_key)
         VALUES ('2024:1:race', '2024:1', 'race', '2024-03-03T10:00:00+01:00', 'scheduled', 'fixture', '2024-03-01T01:00:00Z', 8001);
         INSERT INTO session_results (session_id, position, classification, driver_id, driver_name, constructor_id, team, points, source, fetched_at, revision, quality, driver_number)
         VALUES ('2024:1:race', 2, 'classified', 'test-driver', 'Fixture Driver', 'test-team', 'Fixture Team', 18.0, 'fixture', '2024-03-03T10:30:00Z', 1, 'provisional', NULL),
                ('2024:1:race', 1, 'classified', 'test-driver', 'Fixture Driver', 'test-team', 'Fixture Team', 25.0, 'fixture', '2024-03-03T10:31:00Z', 2, 'final', '55');
         INSERT INTO driver_standings (season, position, driver_id, driver_name, constructor, points, wins, source, fetched_at, quality, constructor_ids, driver_number)
         VALUES (2024, 1, 'test-driver', 'Fixture Driver', 'Fixture Team', 25.0, 1, 'fixture', '2024-03-03T10:31:00Z', 'final', '[\"test-team\",\"prior-team\"]', '55');
         INSERT INTO constructor_standings (season, position, constructor_id, constructor_name, points, wins, source, fetched_at, quality)
         VALUES (2024, 1, 'test-team', 'Fixture Team', 25.0, 1, 'fixture', '2024-03-03T10:31:00Z', 'final');
         INSERT INTO provider_identity_cache (season, drivers_json, constructors_json, fetched_at)
         VALUES (2024, '[{\"driverId\":\"test-driver\"}]', '[]', '2024-03-03T10:31:00Z');
         INSERT INTO next_season_schedule (season, events_json, revision, checked_at, updated_at)
         VALUES (2025, '[{\"round\":1,\"startDate\":\"2025-03-01\"}]', 1, '2024-11-01T00:00:00Z', '2024-11-01T00:00:00Z');"
    ).unwrap();
    let report = postgres.import_sqlite(&fixture, false).await.unwrap();
    assert!(
        report
            .iter()
            .any(|table| table.inserted == 2 && table.verified == 2)
    );
    for verify_only in [false, true] {
        let report = postgres.import_sqlite(&fixture, verify_only).await.unwrap();
        assert!(
            report
                .iter()
                .all(|table| table.inserted == 0 && table.verified == table.source as u64)
        );
    }
    let clean_path = temp.path().join("clean.sqlite");
    let clean = Database::open(&clean_path).await.unwrap();
    clean.migrate().await.unwrap();
    let reader = clean.with_season_reader(Postgres::new(&read_dsn, &schema, true).unwrap());
    let instant = "2024-03-03T08:59:59Z";
    let (expected_next, _) = legacy.next_meeting_at(Some(2024), instant).await.unwrap();
    let (actual_next, _) = reader.next_meeting_at(Some(2024), instant).await.unwrap();
    assert!(expected_next.is_some());
    assert_eq!(actual_next, expected_next);
    assert_eq!(
        reader.racing_seasons_before(2026).await.unwrap(),
        vec![2024]
    );
    assert_eq!(
        reader.identity_cache(2024).await.unwrap(),
        legacy.identity_cache(2024).await.unwrap()
    );
    assert_eq!(
        reader.published_schedule_openings().await.unwrap(),
        legacy.published_schedule_openings().await.unwrap()
    );
    let legacy_router = server::router(AppState::new(AppConfig::default(), legacy));
    let reader_router = server::router(AppState::new(AppConfig::default(), reader));
    for path in [
        "/api/v1/calendar?season=2024",
        "/api/v1/meetings/next?season=2024",
        "/api/v1/sessions/2024:1:race/results",
        "/api/v1/sessions/2024:1:unknown/results",
        "/api/v1/standings/drivers?season=2024",
        "/api/v1/standings/constructors?season=2024",
    ] {
        assert_eq!(
            response(&reader_router, path).await,
            response(&legacy_router, path).await,
            "{path}"
        );
    }
    let clean = rusqlite::Connection::open(&clean_path).unwrap();
    assert_eq!(
        clean
            .query_row("SELECT count(*) FROM meetings", [], |row| row
                .get::<_, i64>(0))
            .unwrap(),
        0
    );
}

#[tokio::test]
#[ignore = "requires a disposable Postgres database and PITPULSE_TEST_DATABASE_URL"]
async fn publisher_replays_revisions_without_writing_local_history() {
    use pitpulse_server::{domain::calendar::Meeting, error::StorageError};
    use serde_json::json;

    let dsn = std::env::var("PITPULSE_TEST_DATABASE_URL").expect("set PITPULSE_TEST_DATABASE_URL");
    let read_dsn = std::env::var("PITPULSE_TEST_READ_DATABASE_URL").unwrap_or_else(|_| dsn.clone());
    let read_role = std::env::var("PITPULSE_TEST_READER_ROLE").ok();
    let schema = format!(
        "pitpulse_test_publish_{}_{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    let postgres = Postgres::new(&dsn, &schema, false).unwrap();
    postgres.migrate(read_role.as_deref()).await.unwrap();
    let temp = tempfile::tempdir().unwrap();
    let state_path = temp.path().join("publisher.sqlite");
    let state = Database::open(&state_path).await.unwrap();
    state.migrate().await.unwrap();
    let publisher = state.clone().with_season_publisher(postgres.clone());
    let reader = state
        .clone()
        .with_season_reader(Postgres::new(&read_dsn, &schema, true).unwrap());
    let mut meeting: Meeting = serde_json::from_value(json!({
        "id":"2024:1", "season":2024, "round":1, "name":"Fixture GP", "country":"Fixture Country",
        "location":"Fixture City", "startDate":"2024-03-01", "endDate":"2024-03-03", "status":"scheduled",
        "sessions":[{"id":"2024:1:race", "meetingId":"2024:1", "sessionType":"race",
        "startTime":"2024-03-03T10:00:00Z", "status":"scheduled", "openf1SessionKey":8001,
        "jolpicaSessionId":"fixture-race"}]
    })).unwrap();
    meeting.jolpica_round_id = Some("fixture-round".into());
    let early = "2024-03-03T10:30:00Z";
    let late = "2024-03-03T10:40:00Z";
    assert!(matches!(
        reader.replace_calendar(&[meeting.clone()], early).await,
        Err(StorageError::SeasonReadOnly)
    ));
    assert_eq!(
        publisher
            .replace_calendar(&[meeting.clone()], early)
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        publisher
            .replace_calendar(&[meeting.clone()], early)
            .await
            .unwrap(),
        1
    );
    let mut updated = meeting.clone();
    updated.name = "Fixture Revised GP".into();
    assert_eq!(
        publisher.replace_calendar(&[updated], late).await.unwrap(),
        2
    );
    assert_eq!(
        publisher
            .replace_calendar(&[meeting.clone()], early)
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        reader.calendar(Some(2024)).await.unwrap().0[0].name,
        "Fixture Revised GP"
    );
    let mut first = serde_json::from_value::<pitpulse_server::domain::results::SessionResult>(json!({
        "sessionId":"2024:1:race", "position":2, "classification":"classified", "driverId":"fixture-driver",
        "driverName":"Fixture Driver", "constructorId":"fixture-team", "team":"Fixture Team", "points":18.0,
        "source":"fixture", "fetchedAt":early, "revision":0, "quality":"provisional"
    })).unwrap();
    assert!(matches!(
        reader
            .replace_session_results(vec![first.clone()], "provisional")
            .await,
        Err(StorageError::SeasonReadOnly)
    ));
    let (a, b) = tokio::join!(
        publisher.replace_session_results(vec![first.clone()], "provisional"),
        publisher.replace_session_results(vec![first.clone()], "provisional")
    );
    assert_eq!(a.unwrap(), 1);
    assert_eq!(b.unwrap(), 1);
    let mut revised = first.clone();
    revised.position = Some(1);
    revised.points = Some(25.0);
    revised.fetched_at = late.into();
    // Current provider revisions can remain provisional. A replay of the prior
    // provisional snapshot still must not restore its older classification.
    assert_eq!(
        publisher
            .replace_session_results(vec![revised.clone()], "provisional")
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        publisher
            .replace_session_results(vec![first.clone()], "provisional")
            .await
            .unwrap(),
        2
    );
    first.fetched_at = "2024-03-04T00:00:00Z".into();
    assert_eq!(
        publisher
            .replace_session_results(vec![first.clone()], "partial")
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        publisher
            .replace_session_results(vec![], "provisional")
            .await
            .unwrap(),
        0
    );
    assert!(matches!(
        publisher
            .replace_session_results(vec![first.clone(), first], "provisional")
            .await,
        Err(StorageError::SeasonDataInvalid)
    ));
    let (rows, meta) = reader.session_results("2024:1:race").await.unwrap();
    assert_eq!(meta.revision, 2);
    assert_eq!(rows[0].points, Some(25.0));
    assert_eq!(rows[0].fetched_at, late);

    let mut drivers = serde_json::from_value::<Vec<pitpulse_server::domain::standings::DriverStanding>>(json!([{
        "season":2024, "position":1, "driverId":"fixture-driver", "driverName":"Fixture Driver", "constructor":"Fixture Team",
        "constructorIds":["fixture-team", "prior-team"], "points":25.0, "wins":1, "source":"fixture", "fetchedAt":early, "revision":0
    }])).unwrap();
    assert_eq!(
        publisher
            .replace_driver_standings(drivers.clone())
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        publisher
            .replace_driver_standings(drivers.clone())
            .await
            .unwrap(),
        1
    );
    let old_drivers = drivers.clone();
    drivers[0].points = 26.0;
    drivers[0].fetched_at = late.into();
    assert_eq!(
        publisher.replace_driver_standings(drivers).await.unwrap(),
        2
    );
    assert_eq!(
        publisher
            .replace_driver_standings(old_drivers)
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        reader.driver_standings(Some(2024)).await.unwrap().0[0].points,
        26.0
    );
    let constructors = serde_json::from_value::<Vec<pitpulse_server::domain::standings::ConstructorStanding>>(json!([{
        "season":2024, "position":1, "constructorId":"fixture-team", "constructorName":"Fixture Team", "points":25.0,
        "wins":1, "source":"fixture", "fetchedAt":early, "revision":0
    }])).unwrap();
    assert_eq!(
        publisher
            .replace_constructor_standings(constructors.clone())
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        publisher
            .replace_constructor_standings(constructors)
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        reader.constructor_standings(Some(2024)).await.unwrap().0[0].points,
        25.0
    );
    publisher
        .save_identity_cache(
            2024,
            &[json!({"driverId":"fixture-driver"})],
            &[json!({"constructorId":"fixture-team"})],
            early,
        )
        .await
        .unwrap();
    assert!(reader.identity_cache(2024).await.unwrap().is_some());
    for _ in 0..2 {
        publisher
            .store_provider_mappings(
                vec![("fixture".into(), "raw".into(), "fixture-driver".into())],
                vec![("fixture".into(), "raw".into(), "fixture-team".into())],
            )
            .await
            .unwrap();
        publisher
            .save_next_season_schedule(
                2025,
                json!([{"id":"fixture","round":1,"name":"Fixture GP","location":"Fixture City","startDate":"2025-03-01","endDate":"2025-03-03"}]).to_string(),
                early.into(),
            )
            .await
            .unwrap();
    }
    assert_eq!(
        reader
            .published_schedule_openings()
            .await
            .unwrap()
            .get(&2025)
            .unwrap(),
        "2025-03-01"
    );
    assert_eq!(
        reader
            .next_season_schedule(2025)
            .await
            .unwrap()
            .unwrap()
            .revision,
        1
    );
    publisher
        .sync_begin("fixture", "fixture-retry-state", early)
        .await
        .unwrap();
    assert!(
        state
            .sync_status("fixture", "fixture-retry-state")
            .await
            .unwrap()
            .is_some()
    );
    let local = rusqlite::Connection::open(&state_path).unwrap();
    for table in [
        "meetings",
        "sessions",
        "session_results",
        "driver_standings",
        "constructor_standings",
        "provider_mappings",
        "driver_mappings",
        "constructor_mappings",
        "provider_identity_cache",
        "calendar_snapshots",
        "next_season_schedule",
    ] {
        assert_eq!(
            local
                .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r
                    .get::<_, i64>(0))
                .unwrap(),
            0,
            "{table}"
        );
    }
    // An explicitly selected legacy SQLite database is still usable for rollback.
    assert_eq!(state.replace_calendar(&[meeting], early).await.unwrap(), 1);
    assert_eq!(
        state.calendar(Some(2024)).await.unwrap().0[0].name,
        "Fixture GP"
    );
}
