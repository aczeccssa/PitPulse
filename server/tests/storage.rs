use pitpulse_server::{
    domain::{
        results::SessionResult,
        standings::{ConstructorStanding, DriverStanding},
    },
    providers::jolpica::decode_alpha_schedule,
    storage::sqlite::Database,
};
use serde_json::Value;
use tempfile::TempDir;

#[tokio::test]
async fn test_database_migrates_and_answers_health_query() {
    let temp = TempDir::new().unwrap();
    let database = Database::open(&temp.path().join("pitpulse.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    database.health_check().await.unwrap();
}

#[tokio::test]
async fn test_sync_deadline_and_identity_cache_survive_database_reopen() {
    let temp = TempDir::new().unwrap();
    let path = temp.path().join("sync-state.sqlite");
    let database = Database::open(&path).await.unwrap();
    database.migrate().await.unwrap();
    database
        .sync_begin(
            "jolpica-alpha",
            "results-2026:1:race",
            "2026-10-09T08:00:00Z",
        )
        .await
        .unwrap();
    database
        .sync_failed(
            "jolpica-alpha",
            "results-2026:1:race",
            "2026-10-09T08:00:01Z",
            "2026-10-09T08:03:01Z",
            "provider returned HTTP 429",
            Some("estimated_end=startTime+2h; probe_only"),
        )
        .await
        .unwrap();
    database
        .save_identity_cache(
            2026,
            &[serde_json::json!({"driverId":"leclerc"})],
            &[serde_json::json!({"constructorId":"ferrari"})],
            "2026-10-09T08:00:00Z",
        )
        .await
        .unwrap();
    drop(database);

    let database = Database::open(&path).await.unwrap();
    database.migrate().await.unwrap();
    let status = database
        .sync_status("jolpica-alpha", "results-2026:1:race")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(status.retry_count, 1);
    assert_eq!(
        status.last_error.as_deref(),
        Some("provider returned HTTP 429")
    );
    assert_eq!(
        status.next_retry_at.as_deref(),
        Some("2026-10-09T08:03:01Z")
    );
    assert_eq!(
        status.schedule_note.as_deref(),
        Some("estimated_end=startTime+2h; probe_only")
    );
    let (drivers, constructors) = database.identity_cache(2026).await.unwrap().unwrap();
    assert_eq!(drivers[0]["driverId"], "leclerc");
    assert_eq!(constructors[0]["constructorId"], "ferrari");
}

#[tokio::test]
async fn test_calendar_revision_hash_ignores_fetch_metadata_and_tracks_schedule_content() {
    let temp = TempDir::new().unwrap();
    let database = Database::open(&temp.path().join("calendar-hash.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    let mut meetings = decode_alpha_schedule(&payload).unwrap();
    database
        .replace_calendar(&meetings, "2026-10-09T00:00:00Z")
        .await
        .unwrap();
    let (_, first_meta) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(first_meta.revision, 1);

    meetings[0].fetched_at = Some("2026-10-09T01:00:00Z".into());
    meetings[0].source_updated_at = Some("2026-10-09T01:00:00Z".into());
    database
        .replace_calendar(&meetings, "2026-10-09T01:00:00Z")
        .await
        .unwrap();
    let (_, unchanged_meta) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(unchanged_meta.revision, 1);

    meetings[0].sessions.reverse();
    meetings[0].name.push_str(" corrected");
    database
        .replace_calendar(&meetings, "2026-10-09T02:00:00Z")
        .await
        .unwrap();
    let (_, changed_meta) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(changed_meta.revision, 2);

    meetings[0].source = Some("openf1".into());
    database
        .replace_calendar(&meetings, "2026-10-09T03:00:00Z")
        .await
        .unwrap();
    let (_, source_meta) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(source_meta.revision, 3);
    meetings[0].circuit = Some(
        serde_json::json!({"id":"albert_park","name":"Albert Park","latitude":-37.8497,"longitude":144.968}),
    );
    database
        .replace_calendar(&meetings, "2026-10-09T04:00:00Z")
        .await
        .unwrap();
    let (rows, meta) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(meta.revision, 4);
    assert_eq!(rows[0].circuit, meetings[0].circuit);
}

#[tokio::test]
async fn test_version_three_upgrade_preserves_cached_results_and_adds_nullable_fields() {
    let temp = TempDir::new().unwrap();
    let path = temp.path().join("version-three.sqlite");
    {
        let connection = rusqlite::Connection::open(&path).unwrap();
        connection
            .execute_batch(include_str!("../src/storage/migrations/0001_init.sql"))
            .unwrap();
        connection
            .execute_batch(include_str!(
                "../src/storage/migrations/0002_calendar_contract.sql"
            ))
            .unwrap();
        connection
            .execute_batch(include_str!(
                "../src/storage/migrations/0003_nullable_meeting_round.sql"
            ))
            .unwrap();
        connection
            .execute_batch(
                "INSERT INTO meetings (id,season,round,name,country,location,start_date,end_date,source,fetched_at) VALUES ('2026:1',2026,1,'Test Grand Prix','Australia','Melbourne','2026-10-08T20:00:00Z','2026-10-08T22:00:00Z','jolpica-alpha','2026-10-08T23:00:00Z');
                 INSERT INTO sessions (id,meeting_id,session_type,start_time,status,source,fetched_at) VALUES ('2026:1:race','2026:1','race','2026-10-08T20:00:00Z','finished','jolpica-alpha','2026-10-08T23:00:00Z');
                 INSERT INTO session_results (session_id,position,classification,driver_id,driver_name,constructor_id,team,time,points,source,fetched_at,revision,quality) VALUES ('2026:1:race',1,'classified','leclerc','Charles Leclerc','ferrari','Ferrari','1:20.123',25,'jolpica-alpha','2026-10-08T23:00:00Z',7,'provisional');
                 PRAGMA user_version = 3;",
            )
            .unwrap();
    }
    let database = Database::open(&path).await.unwrap();
    database.migrate().await.unwrap();
    assert_eq!(database.user_version().await.unwrap(), 8);
    let (meetings, _) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(meetings.len(), 1);
    assert!(meetings[0].circuit.is_none());
    let (rows, meta) = database.session_results("2026:1:race").await.unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].revision, 7);
    assert_eq!(rows[0].constructor_id, "ferrari");
    assert_eq!(rows[0].best_lap, None);
    assert_eq!(rows[0].q1, None);
    assert_eq!(rows[0].race_time, None);
    assert_eq!(rows[0].driver_number, None);
    assert_eq!(meta.revision, 7);
}

async fn database_with_session(temp: &TempDir) -> (Database, String) {
    let database = Database::open(&temp.path().join("pitpulse.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    let payload: Value =
        serde_json::from_str(include_str!("fixtures/jolpica-alpha-2026-australia.json")).unwrap();
    let meetings = decode_alpha_schedule(&payload).unwrap();
    let session_id = meetings[0].sessions[0].id.clone();
    database
        .replace_calendar(&meetings, "2026-10-09T00:00:00Z")
        .await
        .unwrap();
    (database, session_id)
}

fn result(session_id: &str, classification: &str, points: f64, quality: &str) -> SessionResult {
    SessionResult {
        driver_number: None,
        session_id: session_id.into(),
        position: Some(1),
        classification: classification.into(),
        driver_id: "leclerc".into(),
        driver_name: "Charles Leclerc".into(),
        constructor_id: "ferrari".into(),
        team: "Ferrari".into(),
        time: Some("1:20.123".into()),
        best_lap: Some("1:19.456".into()),
        q1: None,
        q2: None,
        q3: None,
        race_time: None,
        gap: Some("0.000".into()),
        laps: Some(58),
        points: Some(points),
        source: "jolpica-alpha".into(),
        source_updated_at: Some("2026-10-08T23:59:00Z".into()),
        fetched_at: "2026-10-09T00:00:00Z".into(),
        revision: 1,
        quality: quality.into(),
    }
}

#[tokio::test]
async fn test_result_snapshots_upgrade_atomically_and_expose_latest_revision_only() {
    let temp = TempDir::new().unwrap();
    let (database, session_id) = database_with_session(&temp).await;
    assert_eq!(
        database
            .replace_session_results(
                vec![result(&session_id, "classified", 0.0, "partial")],
                "partial"
            )
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        database
            .replace_session_results(
                vec![result(&session_id, "classified", 0.0, "provisional")],
                "provisional"
            )
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        database
            .replace_session_results(Vec::new(), "partial")
            .await
            .unwrap(),
        0
    );
    assert_eq!(
        database
            .replace_session_results(
                vec![result(&session_id, "classified", 0.0, "provisional")],
                "provisional"
            )
            .await
            .unwrap(),
        2
    );
    let (rows, meta) = database.session_results(&session_id).await.unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].revision, 2);
    assert_eq!(rows[0].best_lap.as_deref(), Some("1:19.456"));
    assert_eq!(meta.revision, 2);
    assert_eq!(
        meta.source_updated_at.as_deref(),
        Some("2026-10-08T23:59:00Z")
    );

    let mut corrected = result(&session_id, "DSQ", 0.0, "provisional");
    corrected.position = None;
    assert_eq!(
        database
            .replace_session_results(vec![corrected], "provisional")
            .await
            .unwrap(),
        3
    );
    assert_eq!(
        database
            .replace_session_results(
                vec![result(&session_id, "classified", 25.0, "provisional")],
                "provisional"
            )
            .await
            .unwrap(),
        4
    );
    assert_eq!(
        database
            .replace_session_results(
                vec![result(&session_id, "classified", 20.0, "partial")],
                "partial"
            )
            .await
            .unwrap(),
        4
    );

    let broken = vec![result(&session_id, "classified", 0.0, "provisional"); 2];
    assert!(
        database
            .replace_session_results(broken, "provisional")
            .await
            .is_err()
    );
    let (rows, _) = database.session_results(&session_id).await.unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].revision, 4);
    assert_eq!(rows[0].classification, "classified");
    assert_eq!(rows[0].points, Some(25.0));
}

#[tokio::test]
async fn test_standings_revisions_retain_constructor_identity_and_empty_fetch_keeps_cache() {
    let temp = TempDir::new().unwrap();
    let database = Database::open(&temp.path().join("standings.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    let row = DriverStanding {
        driver_number: Some("16".into()),
        season: 2026,
        position: 1,
        driver_id: "leclerc".into(),
        driver_name: "Charles Leclerc".into(),
        constructor: "Ferrari".into(),
        constructor_ids: vec!["ferrari".into()],
        points: 25.0,
        wins: 1,
        source: "jolpica-ergast".into(),
        fetched_at: "2026-10-09T00:00:00Z".into(),
        revision: 1,
    };
    assert_eq!(
        database
            .replace_driver_standings(vec![row.clone()])
            .await
            .unwrap(),
        1
    );
    assert_eq!(
        database.replace_driver_standings(Vec::new()).await.unwrap(),
        0
    );
    let mut same = row.clone();
    same.fetched_at = "2026-10-09T01:00:00Z".into();
    assert_eq!(
        database.replace_driver_standings(vec![same]).await.unwrap(),
        1
    );
    let mut changed = row;
    changed.points = 26.0;
    assert_eq!(
        database
            .replace_driver_standings(vec![changed.clone()])
            .await
            .unwrap(),
        2
    );
    changed.source = "test-source-correction".into();
    assert_eq!(
        database
            .replace_driver_standings(vec![changed])
            .await
            .unwrap(),
        3
    );
    let (rows, meta) = database.driver_standings(Some(2026)).await.unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].constructor_ids, vec!["ferrari"]);
    assert_eq!(rows[0].driver_number.as_deref(), Some("16"));
    let mut corrected = rows[0].clone();
    corrected.driver_number = Some("44".into());
    assert_eq!(
        database
            .replace_driver_standings(vec![corrected])
            .await
            .unwrap(),
        4
    );
    assert_eq!(
        database.driver_standings(Some(2026)).await.unwrap().0[0]
            .driver_number
            .as_deref(),
        Some("44")
    );
    assert_eq!(rows[0].revision, 3);
    assert_eq!(rows[0].source, "test-source-correction");
    assert_eq!(meta.revision, 3);

    assert_eq!(
        database
            .replace_constructor_standings(vec![ConstructorStanding {
                season: 2026,
                position: 1,
                constructor_id: "ferrari".into(),
                constructor_name: "Ferrari".into(),
                points: 25.0,
                wins: 1,
                source: "jolpica-ergast".into(),
                fetched_at: "2026-10-09T00:00:00Z".into(),
                revision: 1,
            }])
            .await
            .unwrap(),
        1
    );
    let (constructors, _) = database.constructor_standings(Some(2026)).await.unwrap();
    assert_eq!(constructors[0].constructor_id, "ferrari");
}

#[tokio::test]
async fn test_result_driver_number_roundtrip_and_number_only_revision() {
    let temp = TempDir::new().unwrap();
    let (database, session_id) = database_with_session(&temp).await;
    let mut row = result(&session_id, "classified", 25.0, "provisional");
    row.driver_number = Some("16".into());
    assert_eq!(
        database
            .replace_session_results(vec![row.clone()], "provisional")
            .await
            .unwrap(),
        1
    );
    let loaded = database.session_results(&session_id).await.unwrap().0;
    assert_eq!(loaded[0].driver_number.as_deref(), Some("16"));
    row.driver_number = Some("44".into());
    assert_eq!(
        database
            .replace_session_results(vec![row], "provisional")
            .await
            .unwrap(),
        2
    );
    assert_eq!(
        database.session_results(&session_id).await.unwrap().0[0]
            .driver_number
            .as_deref(),
        Some("44")
    );
    database.migrate().await.unwrap();
    assert_eq!(database.user_version().await.unwrap(), 8);
}
