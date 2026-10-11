use axum::{
    Json, Router,
    body::Body,
    extract::{Path, Query, State},
    http::{Request, StatusCode, Uri, header},
    response::IntoResponse,
    routing::get,
};
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::{calendar::Meeting, results::SessionResult, standings::DriverStanding},
    providers::{jolpica::JolpicaProvider, openf1::OpenF1Provider},
    server,
    storage::sqlite::Database,
};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    },
};
use tempfile::TempDir;
use tower::ServiceExt;

async fn state() -> (AppState, TempDir) {
    let temp = tempfile::tempdir().unwrap();
    let db = Database::open(&temp.path().join("test.sqlite"))
        .await
        .unwrap();
    db.migrate().await.unwrap();
    let meeting: Meeting = serde_json::from_value(json!({"id":"2024:1","season":2024,"round":1,"name":"Test","country":"Bahrain","location":"Sakhir","startDate":"2024-03-01T00:00:00Z","endDate":"2024-03-02T23:00:00Z","status":"scheduled","sessions":[{"id":"2024:1:race","meetingId":"2024:1","sessionType":"race","startTime":"2024-03-02T15:00:00Z","endTime":"2024-03-02T17:00:00Z","status":"finished","openf1SessionKey":10}]})).unwrap();
    db.replace_calendar(&[meeting], "2024-03-02T18:00:00Z")
        .await
        .unwrap();
    let result: SessionResult = serde_json::from_value(json!({"sessionId":"2024:1:race","position":1,"classification":"classified","driverId":"leclerc","driverName":"Charles Leclerc","constructorId":"ferrari","team":"Ferrari","laps":2,"points":25.,"source":"fixture","fetchedAt":"2024-03-02T18:00:00Z","revision":1,"quality":"partial"})).unwrap();
    db.replace_session_results(vec![result], "partial")
        .await
        .unwrap();
    db.save_identity_cache(2024, &[json!({"driverId":"leclerc","permanentNumber":"16","givenName":"Charles","familyName":"Leclerc"})], &[], "2024-03-02T18:00:00Z").await.unwrap();
    let standing: DriverStanding = serde_json::from_value(json!({"season":2024,"position":1,"driverId":"leclerc","driverName":"Charles Leclerc","constructor":"Ferrari","constructorIds":["ferrari"],"points":25.,"wins":1,"source":"fixture","fetchedAt":"2024-03-02T18:00:00Z","revision":1})).unwrap();
    db.replace_driver_standings(vec![standing]).await.unwrap();
    (AppState::new(AppConfig::default(), db), temp)
}

async fn read(app: Router, url: &str, token: bool) -> (StatusCode, Value) {
    let mut request = Request::builder().uri(url);
    if token {
        request = request.header(header::AUTHORIZATION, "Bearer fixture");
    }
    let response = app
        .oneshot(request.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), 4_000_000)
        .await
        .unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

async fn ready(app: Router, url: &str) -> (StatusCode, Value) {
    for _ in 0..300 {
        let value = read(app.clone(), url, false).await;
        if value.1["meta"]["analysisStatus"] != "loading" {
            return value;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    }
    panic!("background analysis did not finish");
}

#[tokio::test]
async fn test_analysis_authorization_validation_and_unknown_entity() {
    let (mut state, _temp) = state().await;
    let mut config = (*state.config).clone();
    config.security.require_token = true;
    config.security.token = Some("fixture".into());
    state.config = Arc::new(config);
    let app = server::router(state);
    for path in [
        "/api/v1/sessions/2024:1:race/drivers/leclerc/analysis",
        "/api/v1/standings/drivers/leclerc/analysis?season=2024",
    ] {
        assert_eq!(
            read(app.clone(), path, false).await.0,
            StatusCode::UNAUTHORIZED
        );
    }
    assert_eq!(
        read(
            app.clone(),
            "/api/v1/sessions/2024:1:race/drivers/leclerc/analysis?lap=201",
            true
        )
        .await
        .0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        read(
            app.clone(),
            "/api/v1/standings/drivers/leclerc/analysis?season=oops",
            true
        )
        .await
        .0,
        StatusCode::BAD_REQUEST
    );
    assert_eq!(
        read(
            app.clone(),
            "/api/v1/sessions/2024:1:race/drivers/unknown/analysis",
            true
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        read(
            app,
            "/api/v1/standings/drivers/unknown/analysis?season=2024",
            true
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
}

#[tokio::test]
async fn test_analysis_historical_identity_bounded_telemetry_partial_sections_and_cache() {
    async fn upstream(
        State(count): State<Arc<AtomicUsize>>,
        Path(resource): Path<String>,
        Query(params): Query<HashMap<String, String>>,
        uri: Uri,
    ) -> axum::response::Response {
        count.fetch_add(1, Ordering::SeqCst);
        assert_eq!(params["session_key"], "10");
        if ["location", "car_data"].contains(&resource.as_str()) {
            assert_eq!(params["driver_number"], "16");
        }
        let rows = match resource.as_str() {
            "drivers" => json!([{"driver_number":16,"full_name":"Charles Leclerc"}]),
            "laps" => {
                json!([{"driver_number":16,"lap_number":1,"lap_duration":90.,"date_start":"2024-03-02T15:00:00.123000+00:00","duration_sector_1":null,"duration_sector_2":30.},{"driver_number":16,"lap_number":2,"lap_duration":91.,"date_start":"2024-03-02T15:01:30Z"}])
            }
            "location" | "car_data" => {
                assert!(!uri.query().unwrap().contains("date%3E%3D"));
                assert_eq!(params["date>"], "2024-03-02T15:00:00+00:00");
                assert_eq!(params["date<"], "2024-03-02T15:01:31Z");
                if resource == "location" {
                    json!([{"date":"2024-03-02T15:00:00Z","x":1.,"y":2.}])
                } else {
                    json!([{"date":"2024-03-02T15:00:00Z","speed":240,"throttle":null,"n_gear":7}])
                }
            }
            "pit" => return StatusCode::NOT_FOUND.into_response(),
            _ => json!([]),
        };
        Json(rows).into_response()
    }
    let count = Arc::new(AtomicUsize::new(0));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let upstream_app = Router::new()
        .route("/v1/{resource}", get(upstream))
        .with_state(count.clone());
    let task = tokio::spawn(async move { axum::serve(listener, upstream_app).await.unwrap() });
    let (mut state, _temp) = state().await;
    state.openf1 = OpenF1Provider::with_base_url(reqwest::Client::new(), &base);
    let app = server::router(state);
    let url = "/api/v1/sessions/2024:1:race/drivers/leclerc/analysis";
    let start = std::time::Instant::now();
    let (status, pending) = read(app.clone(), url, false).await;
    assert!(start.elapsed() < std::time::Duration::from_secs(1));
    assert_eq!(status, StatusCode::OK);
    assert_eq!(pending["meta"]["analysisStatus"], "loading");
    let (status, data) = ready(app.clone(), url).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(data["data"]["selectedLap"], 1);
    assert_eq!(data["data"]["laps"][0]["durationSector1"], Value::Null);
    assert_eq!(data["data"]["carData"][0]["nGear"], 7);
    assert_eq!(data["data"]["pit"], json!([]));
    assert_eq!(data["data"]["warnings"].as_array().unwrap().len(), 1);
    let calls = count.load(Ordering::SeqCst);
    let (_, cached) = read(app, url, false).await;
    assert_eq!(data, cached);
    assert_eq!(count.load(Ordering::SeqCst), calls);
    task.abort();
}

#[tokio::test]
async fn test_season_analysis_preserves_nullable_points_and_sprint_history() {
    async fn results(Path(endpoint): Path<String>) -> Json<Value> {
        let sprint = endpoint == "sprint.json";
        Json(
            json!({"MRData":{"total":"1","limit":"100","offset":"0","RaceTable":{"Races":[{"round":"1","raceName":"Test GP","date":"2024-03-02","Circuit":{"circuitName":"Test","Location":{"country":"Bahrain"}},if sprint {"SprintResults"} else {"Results"}:[{"Driver":{"driverId":"leclerc","givenName":"Charles","familyName":"Leclerc"},"position":"1","points":if sprint {Value::Null} else {json!("25")},"grid":"2","laps":"57","status":"Finished"}]}]}}}),
        )
    }
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let app = Router::new().route("/ergast/f1/2024/{endpoint}", get(results));
    let task = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let (mut state, _temp) = state().await;
    state.jolpica = JolpicaProvider::with_base_url(reqwest::Client::new(), &base);
    let (status, data) = ready(
        server::router(state),
        "/api/v1/standings/drivers/leclerc/analysis?season=2024",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(data["data"]["rounds"].as_array().unwrap().len(), 2);
    assert_eq!(data["data"]["rounds"][0]["sessionType"], "Sprint");
    assert_eq!(
        data["data"]["rounds"][0]["entries"][0]["points"],
        Value::Null
    );
    assert_eq!(data["data"]["rounds"][1]["entries"][0]["points"], 25.);
    task.abort();
}

#[tokio::test]
async fn test_loading_deduplicates_and_does_not_block_persisted_or_stale_cache() {
    use tokio::sync::Notify;
    type Gate = Arc<(AtomicUsize, Notify)>;
    async fn slow(State(gate): State<Gate>) -> Json<Value> {
        gate.0.fetch_add(1, Ordering::SeqCst);
        gate.1.notified().await;
        Json(json!([]))
    }
    let gate = Arc::new((AtomicUsize::new(0), Notify::new()));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let app = Router::new()
        .route("/v1/drivers", get(slow))
        .with_state(gate.clone());
    let upstream = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let (mut state, temp) = state().await;
    state.openf1 = OpenF1Provider::with_base_url(reqwest::Client::new(), base);
    state.jolpica.enabled = false;
    let app = server::router(state.clone());
    let url = "/api/v1/sessions/2024:1:race/drivers/leclerc/analysis";
    for _ in 0..5 {
        let (_, data) = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            read(app.clone(), url, false),
        )
        .await
        .unwrap();
        assert_eq!(data["meta"]["analysisStatus"], "loading");
    }
    tokio::time::timeout(std::time::Duration::from_secs(1), async {
        while gate.0.load(Ordering::SeqCst) == 0 {
            tokio::time::sleep(std::time::Duration::from_millis(5)).await;
        }
    })
    .await
    .unwrap();
    let now = state.database.utc_now().await.unwrap();
    let old = json!({"data":{"rounds":[{"round":1,"entries":[{"points":25}]}],"warnings":[]},"meta":{"schemaVersion":1,"revision":1,"quality":"partial","source":"fixture","stale":false,"fetchedAt":now,"analysisStatus":"ready"}});
    state
        .database
        .save_analysis_cache("season:2024:drivers:leclerc", &old)
        .await
        .unwrap();
    let (_, data) = tokio::time::timeout(
        std::time::Duration::from_secs(1),
        read(
            app.clone(),
            "/api/v1/standings/drivers/leclerc/analysis?season=2024",
            false,
        ),
    )
    .await
    .unwrap();
    assert_eq!(data, old);
    assert_eq!(gate.0.load(Ordering::SeqCst), 1);
    let database = Database::open(&temp.path().join("test.sqlite"))
        .await
        .unwrap();
    database.migrate().await.unwrap();
    let mut restarted = AppState::new(AppConfig::default(), database);
    restarted.jolpica.enabled = false;
    restarted.openf1.enabled = false;
    let (_, data) = read(
        server::router(restarted.clone()),
        "/api/v1/standings/drivers/leclerc/analysis?season=2024",
        false,
    )
    .await;
    assert_eq!(data, old);
    let mut expired = old.clone();
    expired["meta"]["fetchedAt"] = json!("2024-01-01T00:00:00Z");
    // A fresh AppState reloads the expired persisted driver cache without waiting for providers.
    restarted
        .database
        .save_analysis_cache("season:2024:drivers:leclerc", &expired)
        .await
        .unwrap();
    let mut restarted = AppState::new((*restarted.config).clone(), restarted.database.clone());
    restarted.jolpica.enabled = false;
    restarted.openf1.enabled = false;
    let (_, data) = read(
        server::router(restarted),
        "/api/v1/standings/drivers/leclerc/analysis?season=2024",
        false,
    )
    .await;
    assert_eq!(data["data"], old["data"]);
    assert_eq!(data["meta"]["stale"], true);
    assert_eq!(data["meta"]["analysisStatus"], "loading");
    upstream.abort();
}

#[tokio::test]
async fn test_analysis_storage_is_bounded_and_migration_keeps_results() {
    let (state, _temp) = state().await;
    assert_eq!(state.database.user_version().await.unwrap(), 7);
    assert_eq!(
        state
            .database
            .session_results("2024:1:race")
            .await
            .unwrap()
            .0
            .len(),
        1
    );
    for n in 0..140 {
        let value = json!({"data":{"sample":n},"meta":{"fetchedAt":"2026-10-10T00:00:00Z"}});
        state
            .database
            .save_analysis_cache(&format!("test:{n}"), &value)
            .await
            .unwrap();
    }
    assert!(
        state
            .database
            .analysis_cache("test:0")
            .await
            .unwrap()
            .is_none()
    );
    assert_eq!(
        state
            .database
            .analysis_cache("test:139")
            .await
            .unwrap()
            .unwrap()["data"]["sample"],
        139
    );
    state.database.migrate().await.unwrap();
    assert_eq!(
        state
            .database
            .session_results("2024:1:race")
            .await
            .unwrap()
            .0
            .len(),
        1
    );
}
