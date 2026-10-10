use std::{
    net::SocketAddr,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use axum::{
    Json, Router,
    extract::State,
    http::{StatusCode, header::RETRY_AFTER},
    response::IntoResponse,
    routing::get,
};
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::calendar::{Meeting, MeetingStatus, Session, SessionStatus, SessionType},
    providers::{jolpica::JolpicaProvider, openf1::OpenF1Provider},
    server,
    services::results_sync::{ResultsSync, SyncOutcome},
    storage::sqlite::Database,
};
use serde_json::{Value, json};
use tempfile::TempDir;
use tokio::net::TcpListener;
use tower::ServiceExt;

async fn mock_drivers() -> Json<Value> {
    Json(
        json!({"MRData":{"total":"1","limit":"100","offset":"0","url":"http://127.0.0.1/ergast/f1/2026/drivers.json","DriverTable":{"Drivers":[{"driverId":"leclerc","permanentNumber":"16","url":"https://en.wikipedia.org/wiki/Charles_Leclerc","givenName":"Charles","familyName":"Leclerc"}]}}}),
    )
}

async fn mock_constructors() -> Json<Value> {
    Json(
        json!({"MRData":{"total":"1","limit":"100","offset":"0","url":"http://127.0.0.1/ergast/f1/2026/constructors.json","ConstructorTable":{"Constructors":[{"constructorId":"ferrari","name":"Ferrari","url":"https://en.wikipedia.org/wiki/Scuderia_Ferrari"}]}}}),
    )
}

async fn mock_driver_standings() -> Json<Value> {
    Json(
        json!({"MRData":{"total":"1","limit":"100","offset":"0","url":"http://127.0.0.1/ergast/f1/2026/driverStandings.json","StandingsTable":{"StandingsLists":[{"DriverStandings":[{"position":"1","points":"25.0","wins":"1","Driver":{"driverId":"leclerc","givenName":"Charles","familyName":"Leclerc"},"Constructors":[{"constructorId":"ferrari","name":"Ferrari"}]}]}]}}}),
    )
}

async fn mock_constructor_standings() -> Json<Value> {
    Json(
        json!({"MRData":{"total":"1","limit":"100","offset":"0","url":"http://127.0.0.1/ergast/f1/2026/constructorStandings.json","StandingsTable":{"StandingsLists":[{"ConstructorStandings":[{"position":"1","points":"25.0","wins":"1","Constructor":{"constructorId":"ferrari","name":"Ferrari"}}]}]}}}),
    )
}

async fn mock_alpha_race() -> Json<Value> {
    Json(
        json!({"metadata":{"timestamp":"2026-10-08T23:59:00Z"},"data":{"results":[{"driver":{"id":"driver_leclerc","given_name":"Charles","family_name":"Leclerc","wikipedia":"http://en.wikipedia.org/wiki/Charles_Leclerc"},"team":{"id":"team_ferrari","name":"Ferrari","wikipedia":"https://en.wikipedia.org/wiki/Scuderia_Ferrari"},"position":1,"position_text":"1","is_classified":true,"time":"1:20.123","laps":58,"points":25}]}}),
    )
}

async fn mock_openf1_drivers() -> Json<Value> {
    Json(json!([{"driver_number":16,"full_name":"Charles Leclerc","team_name":"Ferrari"}]))
}

#[tokio::test]
async fn test_sprint_fallback_preserves_primary_priority_rate_limit_and_cached_results() {
    type Counts = Arc<(AtomicUsize, AtomicUsize)>;
    async fn alpha(State(counts): State<Counts>) -> axum::response::Response {
        match counts.0.load(Ordering::SeqCst) {
            1 => mock_alpha_race().await.into_response(),
            3 => (
                StatusCode::TOO_MANY_REQUESTS,
                [(RETRY_AFTER, "120")],
                Json(json!({})),
            )
                .into_response(),
            _ => Json(json!({"data":{"results":[]}})).into_response(),
        }
    }
    async fn supplement(State(counts): State<Counts>) -> axum::response::Response {
        counts.1.fetch_add(1, Ordering::SeqCst);
        match counts.0.load(Ordering::SeqCst) {
            2 => Json(json!([])).into_response(),
            4 => StatusCode::SERVICE_UNAVAILABLE.into_response(),
            _ => Json(json!([{"driver_number":16,"position":1,"duration":1800.125,"number_of_laps":20,"dnf":false,"dns":false,"dsq":false}])).into_response(),
        }
    }
    let counts = Arc::new((AtomicUsize::new(0), AtomicUsize::new(0)));
    let app = Router::new()
        .route("/ergast/f1/2026/drivers.json", get(mock_drivers))
        .route("/ergast/f1/2026/constructors.json", get(mock_constructors))
        .route("/f1/alpha/results/round_test/SR/", get(alpha))
        .route("/v1/drivers", get(mock_openf1_drivers))
        .route("/v1/session_result", get(supplement))
        .with_state(counts.clone());
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let upstream = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let temp = TempDir::new().unwrap();
    let database = Database::open(&temp.path().join("pitpulse.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    let session = Session {
        id: "2026:1:sprint".into(),
        meeting_id: "2026:1".into(),
        session_type: SessionType::Sprint,
        start_time: "2026-10-08T20:00:00Z".into(),
        end_time: Some("2026-10-08T21:00:00Z".into()),
        status: SessionStatus::Scheduled,
        jolpica_session_id: None,
        openf1_session_key: Some(10),
    };
    let meeting = Meeting {
        id: "2026:1".into(),
        season: 2026,
        round: Some(1),
        jolpica_round_id: Some("round_test".into()),
        name: "Test Grand Prix".into(),
        country: "Australia".into(),
        country_code: Some("AU".into()),
        location: "Melbourne".into(),
        start_date: session.start_time.clone(),
        end_date: session.start_time.clone(),
        status: MeetingStatus::Scheduled,
        sessions: vec![session.clone()],
        source: Some("jolpica-alpha".into()),
        fetched_at: None,
        source_updated_at: None,
        revision: None,
    };
    database
        .replace_calendar(std::slice::from_ref(&meeting), "2026-10-08T23:00:00Z")
        .await
        .unwrap();
    let mut sync = ResultsSync {
        jolpica: JolpicaProvider::with_base_url(reqwest::Client::new(), &base),
        openf1: OpenF1Provider::with_base_url(reqwest::Client::new(), &base),
        timeout: Duration::from_secs(2),
    };
    let identities = sync.load_identity_maps_once(&database, 2026).await.unwrap();
    assert_eq!(
        sync.sync_session_once(&database, &meeting, &session, &identities)
            .await
            .unwrap(),
        SyncOutcome::Stored { retry_after: None }
    );
    let (rows, meta) = database.session_results(&session.id).await.unwrap();
    assert_eq!(rows[0].driver_id, "leclerc");
    assert_eq!(rows[0].laps, Some(20));
    assert_eq!(rows[0].points, None);
    assert_eq!(meta.source.as_deref(), Some("openf1"));
    assert_eq!(meta.quality.as_str(), "provisional");
    counts.0.store(1, Ordering::SeqCst);
    sync.sync_session_once(&database, &meeting, &session, &identities)
        .await
        .unwrap();
    assert_eq!(counts.1.load(Ordering::SeqCst), 1);
    let cached = database.session_results(&session.id).await.unwrap();
    assert_eq!(cached.1.source.as_deref(), Some("jolpica-alpha"));
    counts.0.store(2, Ordering::SeqCst);
    assert_eq!(
        sync.sync_session_once(&database, &meeting, &session, &identities)
            .await
            .unwrap(),
        SyncOutcome::NoResult
    );
    let unchanged = database.session_results(&session.id).await.unwrap();
    assert_eq!(unchanged.0, cached.0);
    assert_eq!(unchanged.1.revision, cached.1.revision);
    counts.0.store(3, Ordering::SeqCst);
    assert_eq!(
        sync.sync_session_once(&database, &meeting, &session, &identities)
            .await
            .unwrap(),
        SyncOutcome::Stored {
            retry_after: Some(Duration::from_secs(120))
        }
    );
    let cached = database.session_results(&session.id).await.unwrap();
    counts.0.store(4, Ordering::SeqCst);
    assert!(
        sync.sync_session_once(&database, &meeting, &session, &identities)
            .await
            .is_err()
    );
    assert_eq!(
        database.session_results(&session.id).await.unwrap().0,
        cached.0
    );
    counts.0.store(0, Ordering::SeqCst);
    let before = counts.1.load(Ordering::SeqCst);
    sync.openf1.enabled = false;
    assert_eq!(
        sync.sync_session_once(&database, &meeting, &session, &identities)
            .await
            .unwrap(),
        SyncOutcome::NoResult
    );
    sync.openf1.enabled = true;
    let without_key = Session {
        openf1_session_key: None,
        ..session
    };
    assert_eq!(
        sync.sync_session_once(&database, &meeting, &without_key, &identities)
            .await
            .unwrap(),
        SyncOutcome::NoResult
    );
    assert_eq!(counts.1.load(Ordering::SeqCst), before);
    upstream.abort();
}

#[tokio::test]
async fn test_split_sync_targets_fetch_and_preserve_results_and_both_standings() {
    let app = Router::new()
        .route("/ergast/f1/2026/drivers.json", get(mock_drivers))
        .route("/ergast/f1/2026/constructors.json", get(mock_constructors))
        .route(
            "/ergast/f1/2026/driverStandings.json",
            get(mock_driver_standings),
        )
        .route(
            "/ergast/f1/2026/constructorStandings.json",
            get(mock_constructor_standings),
        )
        .route("/f1/alpha/results/round_test/R/", get(mock_alpha_race))
        .route("/v1/drivers", get(mock_openf1_drivers));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address: SocketAddr = listener.local_addr().unwrap();
    let upstream = tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    let base = format!("http://{address}");

    let temp = TempDir::new().unwrap();
    let database = Database::open(&temp.path().join("pitpulse.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    let session = Session {
        id: "2026:1:race".into(),
        meeting_id: "2026:1".into(),
        session_type: SessionType::Race,
        start_time: "2026-10-08T20:00:00Z".into(),
        end_time: Some("2026-10-08T22:00:00Z".into()),
        status: SessionStatus::Scheduled,
        jolpica_session_id: Some("session_test".into()),
        openf1_session_key: Some(10),
    };
    database
        .replace_calendar(
            &[Meeting {
                id: "2026:1".into(),
                season: 2026,
                round: Some(1),
                jolpica_round_id: Some("round_test".into()),
                name: "Test Grand Prix".into(),
                country: "Australia".into(),
                country_code: Some("AU".into()),
                location: "Melbourne".into(),
                start_date: session.start_time.clone(),
                end_date: session.start_time.clone(),
                status: MeetingStatus::Scheduled,
                sessions: vec![session],
                source: Some("jolpica-alpha".into()),
                fetched_at: None,
                source_updated_at: None,
                revision: None,
            }],
            "2026-10-08T23:00:00Z",
        )
        .await
        .unwrap();

    let sync = ResultsSync {
        jolpica: JolpicaProvider::with_base_url(reqwest::Client::new(), &base),
        openf1: OpenF1Provider::with_base_url(reqwest::Client::new(), &base),
        timeout: Duration::from_secs(2),
    };
    let identities = sync.load_identity_maps_once(&database, 2026).await.unwrap();
    assert!(
        sync.sync_driver_standings_once(&database, 2026, &identities)
            .await
            .unwrap()
    );
    assert!(
        sync.sync_constructor_standings_once(&database, 2026, &identities)
            .await
            .unwrap()
    );
    let (meetings, _) = database.calendar(Some(2026)).await.unwrap();
    assert_eq!(
        sync.sync_session_once(
            &database,
            &meetings[0],
            &meetings[0].sessions[0],
            &identities
        )
        .await
        .unwrap(),
        SyncOutcome::Stored { retry_after: None }
    );
    let (cached_results, results_meta) = database.session_results("2026:1:race").await.unwrap();
    let (_, driver_meta) = database.driver_standings(Some(2026)).await.unwrap();
    upstream.abort();
    assert!(
        sync.sync_session_once(
            &database,
            &meetings[0],
            &meetings[0].sessions[0],
            &identities
        )
        .await
        .is_err()
    );
    let (after_failure, after_failure_meta) =
        database.session_results("2026:1:race").await.unwrap();
    let (_, after_driver_meta) = database.driver_standings(Some(2026)).await.unwrap();
    assert_eq!(after_failure, cached_results);
    assert_eq!(after_failure_meta.revision, results_meta.revision);
    assert_eq!(after_driver_meta.revision, driver_meta.revision);

    let config = AppConfig {
        database: pitpulse_server::config::DatabaseConfig {
            path: temp.path().join("pitpulse.sqlite"),
        },
        ..AppConfig::default()
    };
    let state = AppState::new(config, database);
    for uri in [
        "/api/v1/sessions/2026:1:race/results",
        "/api/v1/standings/drivers?season=2026",
        "/api/v1/standings/constructors?season=2026",
    ] {
        let response = server::router(state.clone())
            .oneshot(
                axum::http::Request::builder()
                    .uri(uri)
                    .body(axum::body::Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), axum::http::StatusCode::OK, "{uri}");
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let value: Value = serde_json::from_slice(&body).unwrap();
        assert!(!value["data"].as_array().unwrap().is_empty(), "{uri}");
        assert_eq!(
            value["meta"]["source"],
            if uri.contains("/results") {
                "jolpica-alpha"
            } else {
                "jolpica-ergast"
            }
        );
        assert!(value["meta"]["fetchedAt"].as_str().unwrap().ends_with('Z'));
        if uri.contains("/results") {
            assert_eq!(value["meta"]["sourceUpdatedAt"], "2026-10-08T23:59:00Z");
            assert_eq!(value["meta"]["quality"], "provisional");
            assert_eq!(value["meta"]["revision"], 1);
        } else {
            assert!(value["meta"]["sourceUpdatedAt"].is_null());
        }
    }
}
