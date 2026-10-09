use std::{net::SocketAddr, time::Duration};

use axum::{Json, Router, routing::get};
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::calendar::{Meeting, MeetingStatus, Session, SessionStatus, SessionType},
    providers::{jolpica::JolpicaProvider, openf1::OpenF1Provider},
    server,
    services::results_sync::ResultsSync,
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
async fn test_startup_sync_fetches_and_serves_results_and_both_standings() {
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
    sync.sync_startup(&database, 2026).await;
    let (cached_results, results_meta) = database.session_results("2026:1:race").await.unwrap();
    let (_, driver_meta) = database.driver_standings(Some(2026)).await.unwrap();
    upstream.abort();
    sync.sync_startup(&database, 2026).await;
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
