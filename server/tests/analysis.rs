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
    let result: SessionResult = serde_json::from_value(json!({"sessionId":"2024:1:race","position":1,"classification":"classified","driverId":"leclerc","driverNumber":"16","driverName":"Charles Leclerc","constructorId":"ferrari","team":"Ferrari","laps":2,"points":25.,"source":"fixture","fetchedAt":"2024-03-02T18:00:00Z","revision":1,"quality":"partial"})).unwrap();
    db.replace_session_results(vec![result], "partial")
        .await
        .unwrap();
    db.save_identity_cache(2024, &[json!({"driverId":"leclerc","permanentNumber":"16","givenName":"Charles","familyName":"Leclerc"})], &[], "2024-03-02T18:00:00Z").await.unwrap();
    let standing: DriverStanding = serde_json::from_value(json!({"season":2024,"position":1,"driverId":"leclerc","driverName":"Charles Leclerc","constructor":"Ferrari","constructorIds":["ferrari"],"points":25.,"wins":1,"source":"fixture","fetchedAt":"2024-03-02T18:00:00Z","revision":1})).unwrap();
    db.replace_driver_standings(vec![standing]).await.unwrap();
    let mut config = AppConfig::default();
    config.providers.jolpica_enabled = false;
    (AppState::new(config, db), temp)
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
async fn test_direct_bundle_readers_rehydrate_shared_snapshot() {
    let (state, _temp) = state().await;
    let shared = json!({
        "data": {
            "laps": [{"driverNumber":16,"lapNumber":1,"lapDuration":90.0,"isPitOutLap":false}],
            "stints": [],
            "pit": [{"driverNumber":16,"stopDuration":2.4}],
            "positions": [],
            "weather": [{
                "date":"2024-03-02T15:00:00Z","airTemperature":27.5,
                "trackTemperature":42.0,"humidity":40,"rainfall":0,
                "windSpeed":2.1,"windDirection":180,"pressure":1012
            }],
            "raceControl": [],
            "grid": [{"driverNumber":16,"position":2}],
            "warnings": []
        },
        "meta": {"fetchedAt":"2024-03-02T18:00:00Z"}
    });
    state
        .database
        .save_analysis_cache("session:2024:1:race:shared:fixture", &shared)
        .await
        .unwrap();
    let bundle = json!({
        "data": {
            "drivers": [{"driverNumber":16,"fullName":"Charles Leclerc","teamName":"Ferrari"}],
            "laps": null,
            "stints": null,
            "pit": null,
            "positions": null,
            "weather": null,
            "raceControl": null,
            "grid": null,
            "warnings": null
        },
        "meta": {
            "schemaVersion": 1,
            "revision": 1,
            "quality": "partial",
            "stale": false,
            "source": "fixture",
            "fetchedAt": "2024-03-02T18:00:00Z",
            "analysisStatus": "ready",
            "analysisCacheSchema": "pitpulse:v2:shared-reference",
            "bundleFingerprint": "fixture"
        }
    });
    state
        .database
        .save_analysis_cache("session:2024:1:race:bundle", &bundle)
        .await
        .unwrap();

    let app = server::router(state);
    let (status, season) = read(app.clone(), "/api/v1/results/season?season=2024", false).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        season["data"][0]["sessions"]["race"]["rows"][0]["gridPosition"],
        2
    );
    let (status, home) = read(app.clone(), "/api/v1/home?season=2024", false).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(home["data"]["pitStop"][0]["time"], 2.4);
    let (status, weather) = read(app, "/api/v1/meetings/2024:1/weather", false).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(weather["data"]["status"], "historical");
    assert_eq!(weather["data"]["hours"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn test_expired_shared_cache_preserves_lap_telemetry_while_refreshing() {
    let (mut state, _temp) = state().await;
    state.openf1.enabled = false;
    let laps = json!([{"driverNumber": 16, "lapNumber": 1, "lapDuration": 90.5}]);
    let car_data = json!([{"speed": 240, "nGear": 7}]);
    let location = json!([{"x": 1.0, "y": 2.0, "z": 0.0}]);
    let fetched_at = "2000-01-01T00:00:00Z";
    state
        .database
        .save_analysis_cache(
            "session:2024:1:race:shared:fixture",
            &json!({"data": {"laps": laps}, "meta": {"fetchedAt": fetched_at}}),
        )
        .await
        .unwrap();

    let entry = json!({
        "data": {"selectedLap": 1, "carData": car_data, "location": location},
        "meta": {
            "fetchedAt": fetched_at,
            "analysisStatus": "ready",
            "stale": false,
            "analysisCacheSchema": "pitpulse:v2:shared-reference",
            "bundleFingerprint": "fixture"
        }
    });
    for lap in [0, 1] {
        state
            .database
            .save_analysis_cache(&format!("session:2024:1:race:leclerc:{lap}"), &entry)
            .await
            .unwrap();
    }

    let app = server::router(state);
    for query in ["", "?lap=1"] {
        let path = format!("/api/v1/sessions/2024:1:race/drivers/leclerc/analysis{query}");
        let (status, response) = read(app.clone(), &path, false).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(response["data"]["carData"], car_data);
        assert_eq!(response["data"]["location"], location);
        assert_eq!(response["data"]["laps"], laps);
        assert_eq!(response["data"]["selectedLap"], 1);
        assert_eq!(response["meta"]["analysisStatus"], "loading");
        assert_eq!(response["meta"]["stale"], true);
        assert_eq!(response["meta"]["fetchedAt"], fetched_at);
        assert!(response["meta"].get("analysisCacheSchema").is_none());
        assert!(response["meta"].get("bundleFingerprint").is_none());
    }
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
    let (mut state, temp) = state().await;
    state.openf1 = OpenF1Provider::with_base_url(reqwest::Client::new(), &base);
    let fresh_config = (*state.config).clone();
    let upstream_provider = state.openf1.clone();
    let database = state.database.clone();
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
    let bundle = database
        .analysis_cache("session:2024:1:race:bundle")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        bundle["meta"]["analysisCacheSchema"],
        "pitpulse:v2:shared-reference"
    );
    let fingerprint = bundle["meta"]["bundleFingerprint"]
        .as_str()
        .unwrap()
        .to_string();
    let shared = database
        .analysis_cache(&format!("session:2024:1:race:shared:{fingerprint}"))
        .await
        .unwrap()
        .unwrap();
    let bundle_data = shared["data"].clone();
    assert_eq!(bundle_data["laps"].as_array().unwrap().len(), 2);
    assert!(
        bundle_data["carData"].as_array().unwrap().is_empty(),
        "shared bundle must not retain telemetry from a different selected lap"
    );
    assert!(
        database
            .analysis_cache("session:2024:1:race:leclerc:base")
            .await
            .unwrap()
            .is_none(),
        "base is derived from the bundle and must not be materialized"
    );
    let reopened = Database::open(&temp.path().join("test.sqlite"))
        .await
        .unwrap();
    let (_, derived) = read(
        server::router(AppState::new(AppConfig::default(), reopened)),
        url,
        false,
    )
    .await;
    assert_eq!(derived, data);

    // A cached per-lap envelope keeps its original selected lap when no lap
    // query is supplied. The derived base must not overwrite that field.
    let cached_lap = url.to_string() + "?lap=1";
    let (_, first) = read(app.clone(), &cached_lap, false).await;
    assert_eq!(first["data"]["selectedLap"], 1);
    let restarted = Database::open(&temp.path().join("test.sqlite"))
        .await
        .unwrap();
    let (_, second) = read(
        server::router(AppState::new(AppConfig::default(), restarted)),
        &cached_lap,
        false,
    )
    .await;
    assert_eq!(second["data"]["selectedLap"], first["data"]["selectedLap"]);

    // The fallback's selected lap remains derived from its timing data, even
    // when a cached per-lap envelope was generated for a different lap.
    let (_, fallback) = read(
        server::router(AppState::new(AppConfig::default(), database.clone())),
        url,
        false,
    )
    .await;
    assert_eq!(fallback["data"]["selectedLap"], 1);
    for value in [&data, &derived, &first, &second, &fallback] {
        assert!(
            value["meta"].get("analysisCacheSchema").is_none(),
            "internal shared-reference metadata must not escape the API"
        );
        assert!(
            value["meta"].get("bundleFingerprint").is_none(),
            "internal bundle fingerprint must not escape the API"
        );
    }
    assert_eq!(data["data"]["laps"][0]["durationSector1"], Value::Null);
    assert_eq!(data["data"]["carData"][0]["nGear"], 7);
    assert_eq!(data["data"]["pit"], json!([]));
    assert_eq!(data["data"]["warnings"].as_array().unwrap().len(), 1);
    let calls = count.load(Ordering::SeqCst);
    let (_, cached) = read(app.clone(), url, false).await;
    assert_eq!(data, cached);
    assert_eq!(count.load(Ordering::SeqCst), calls);

    // A stripped cache entry without its immutable shared snapshot must not be
    // served as complete data. The refresh path rebuilds the snapshot first.
    let shared_key = format!("session:2024:1:race:shared:{fingerprint}");
    let database_path = temp.path().join("test.sqlite");
    let cache = database
        .analysis_cache("session:2024:1:race:leclerc:0")
        .await
        .unwrap()
        .unwrap();
    let missing_reference = json!({
        "data": {
            "location": cache["data"]["location"].clone(),
            "carData": cache["data"]["carData"].clone(),
            "selectedLap": cache["data"]["selectedLap"].clone(),
            "driver": cache["data"]["driver"].clone()
        },
        "meta": {
            "schemaVersion": 1, "revision": 1, "quality": "partial", "stale": true,
            "source": "openf1", "fetchedAt": "2000-01-01T00:00:00Z",
            "analysisStatus": "failed", "analysisCacheSchema": "pitpulse:v2:shared-reference",
            "bundleFingerprint": "missing-snapshot"
        }
    });
    {
        let connection = rusqlite::Connection::open(&database_path).unwrap();
        let stored = serde_json::to_vec(&missing_reference).unwrap();
        connection
            .execute(
                "UPDATE analysis_cache SET value_json=?1, fetched_at=?2 WHERE cache_key=?3",
                rusqlite::params![
                    stored,
                    cache["meta"]["fetchedAt"].as_str().unwrap(),
                    "session:2024:1:race:leclerc:0"
                ],
            )
            .unwrap();
    }
    let mut evicted_state = AppState::new(fresh_config, database.clone());
    evicted_state.openf1 = upstream_provider;
    let evicted_app = server::router(evicted_state);
    let (status, stale) = read(evicted_app.clone(), url, false).await;
    assert_eq!(status, StatusCode::OK);
    for field in [
        "laps",
        "stints",
        "pit",
        "positions",
        "weather",
        "raceControl",
        "grid",
        "warnings",
    ] {
        assert!(
            !stale["data"][field].is_null(),
            "{field} must not be exposed as null"
        );
    }
    let (_, rebuilt) = ready(evicted_app, url).await;
    assert_eq!(rebuilt["data"], data["data"]);
    assert_eq!(rebuilt["meta"]["analysisStatus"], "ready");
    assert!(
        database
            .analysis_cache(&shared_key)
            .await
            .unwrap()
            .is_some()
    );
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
async fn test_analysis_archive_retains_history_and_migration_keeps_results() {
    let (state, _temp) = state().await;
    assert_eq!(state.database.user_version().await.unwrap(), 11);
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
            .is_some()
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

#[tokio::test]
async fn test_missing_session_laps_respect_persisted_cooldown() {
    async fn upstream(
        State(laps_calls): State<Arc<AtomicUsize>>,
        Path(resource): Path<String>,
    ) -> impl IntoResponse {
        if resource == "laps" {
            laps_calls.fetch_add(1, Ordering::SeqCst);
            return StatusCode::NOT_FOUND.into_response();
        }
        Json(json!([])).into_response()
    }

    let calls = Arc::new(AtomicUsize::new(0));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let upstream_app = Router::new()
        .route("/v1/{resource}", get(upstream))
        .with_state(calls.clone());
    let task = tokio::spawn(async move { axum::serve(listener, upstream_app).await.unwrap() });

    let (mut state, temp) = state().await;
    state.openf1 = OpenF1Provider::with_base_url(reqwest::Client::new(), &base);
    let url = "/api/v1/sessions/2024:1:race/drivers/leclerc/analysis";
    let (_, first) = ready(server::router(state.clone()), url).await;
    assert_eq!(first["meta"]["analysisStatus"], "failed");
    assert_eq!(calls.load(Ordering::SeqCst), 1);

    let five_minutes_ago: String = rusqlite::Connection::open(temp.path().join("test.sqlite"))
        .unwrap()
        .query_row(
            "SELECT strftime('%Y-%m-%dT%H:%M:%SZ','now','-5 minutes')",
            [],
            |row| row.get(0),
        )
        .unwrap();
    for key in [
        "session:2024:1:race:bundle",
        "session:2024:1:race:leclerc:0",
    ] {
        let mut value = state.database.analysis_cache(key).await.unwrap().unwrap();
        value["meta"]["fetchedAt"] = json!(five_minutes_ago);
        state
            .database
            .save_analysis_cache(key, &value)
            .await
            .unwrap();
    }

    let mut restarted = AppState::new((*state.config).clone(), state.database.clone());
    restarted.openf1 = state.openf1.clone();
    let (_, result) = ready(server::router(restarted), url).await;
    assert_eq!(result["meta"]["analysisStatus"], "failed");
    assert_eq!(calls.load(Ordering::SeqCst), 1);
    task.abort();
}

#[tokio::test]
async fn test_historical_backfill_prefers_unattempted_session_to_expired_failure() {
    let (mut state, _temp) = state().await;
    let (meetings, _) = state.database.calendar(Some(2024)).await.unwrap();
    let mut meeting = meetings.into_iter().next().unwrap();
    let mut later = meeting.sessions[0].clone();
    later.id = "2024:1:qualifying".into();
    later.session_type = pitpulse_server::domain::calendar::SessionType::Qualifying;
    later.openf1_session_key = Some(11);
    later.start_time = "2024-03-02T15:01:00Z".into();
    let mut result = state
        .database
        .session_results("2024:1:race")
        .await
        .unwrap()
        .0
        .remove(0);
    result.session_id = later.id.clone();
    meeting.sessions.push(later);
    state
        .database
        .replace_calendar(&[meeting], "2024-03-02T18:00:00Z")
        .await
        .unwrap();
    state
        .database
        .replace_session_results(vec![result], "partial")
        .await
        .unwrap();
    let failed = json!({
        "data": {"laps": []},
        "meta": {"fetchedAt": "2024-03-03T00:00:00Z", "analysisStatus": "failed"}
    });
    state
        .database
        .save_analysis_cache("session:2024:1:race:bundle", &failed)
        .await
        .unwrap();

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let upstream = Router::new().route(
        "/v1/{resource}",
        get(|Path(resource): Path<String>, Query(params): Query<HashMap<String, String>>| async move {
            assert_eq!(params["session_key"], "11");
            Json(if resource == "laps" { json!([{"driver_number":16,"lap_number":1}]) } else { json!([]) })
        }),
    );
    let upstream_task = tokio::spawn(async move { axum::serve(listener, upstream).await.unwrap() });
    state.openf1 = OpenF1Provider::with_base_url(reqwest::Client::new(), &base);
    let database = state.database.clone();
    let preload_task = tokio::spawn(pitpulse_server::services::analysis::preload(state));
    let bundle = tokio::time::timeout(std::time::Duration::from_secs(25), async {
        loop {
            if let Some(value) = database
                .analysis_cache("session:2024:1:qualifying:bundle")
                .await
                .unwrap()
            {
                break value;
            }
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
        }
    })
    .await
    .unwrap();
    assert_eq!(bundle["meta"]["analysisStatus"], "ready");
    assert_eq!(
        database
            .analysis_cache("session:2024:1:race:bundle")
            .await
            .unwrap(),
        Some(failed)
    );
    preload_task.abort();
    upstream_task.abort();
}
