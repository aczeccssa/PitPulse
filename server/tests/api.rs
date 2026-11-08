use axum::{
    body::Body,
    http::{Request, StatusCode, header},
};
use pitpulse_server::domain::standings::{ConstructorStanding, DriverStanding};
use pitpulse_server::{app_state::AppState, config::AppConfig, server, storage::sqlite::Database};
use serde_json::Value;
use tempfile::TempDir;
use tower::ServiceExt;

async fn test_state() -> (AppState, TempDir) {
    let temp = tempfile::tempdir().expect("create temp dir");
    let mut config = AppConfig::default();
    config.database.path = temp.path().join("pitpulse.sqlite");
    let database = Database::open(&config.database.path)
        .await
        .expect("open database");
    database.migrate().await.expect("migrate database");
    let state = AppState::new(config, database);
    (state, temp)
}

#[tokio::test]
async fn test_health_without_required_token_returns_ok() {
    let (state, _temp) = test_state().await;
    let response = server::router(state)
        .oneshot(
            Request::builder()
                .uri("/api/v1/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_calendar_returns_stale_empty_meta() {
    let (state, _temp) = test_state().await;
    let response = server::router(state)
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
    assert_eq!(value["data"], serde_json::json!([]));
    assert_eq!(value["meta"]["schemaVersion"], 1);
    assert_eq!(value["meta"]["stale"], true);
    assert!(value["meta"].get("syncStatus").is_none());
}

#[tokio::test]
async fn test_calendar_meta_includes_persisted_sync_status_when_available() {
    let (state, _temp) = test_state().await;
    state
        .database
        .sync_failed(
            "jolpica-alpha",
            "calendar-2026",
            "2026-10-09T08:00:00Z",
            "2026-10-09T08:05:00Z",
            "provider returned HTTP 429",
            None,
        )
        .await
        .unwrap();
    let response = server::router(state)
        .oneshot(
            Request::builder()
                .uri("/api/v1/calendar?season=2026")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(value["meta"]["syncStatus"]["retryCount"], 1);
    assert_eq!(
        value["meta"]["syncStatus"]["nextRetryAt"],
        "2026-10-09T08:05:00Z"
    );
}

#[tokio::test]
async fn test_bearer_token_is_enforced_when_enabled() {
    let (mut state, _temp) = test_state().await;
    let mut config = AppConfig::default();
    config.security.require_token = true;
    config.security.token = Some("test-token".to_string());
    state.config = std::sync::Arc::new(config);

    let missing = server::router(state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/v1/standings/drivers?season=2026")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::UNAUTHORIZED);

    let missing_constructor = server::router(state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/v1/standings/constructors?season=2026")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing_constructor.status(), StatusCode::UNAUTHORIZED);

    let missing_refresh = server::router(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/refresh")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(r#"{"season":2026,"target":"calendar"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing_refresh.status(), StatusCode::UNAUTHORIZED);

    let authorized = server::router(state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/v1/standings/constructors?season=2026")
                .header(header::AUTHORIZATION, "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(authorized.status(), StatusCode::OK);

    let authorized_driver = server::router(state)
        .oneshot(
            Request::builder()
                .uri("/api/v1/standings/drivers?season=2026")
                .header(header::AUTHORIZATION, "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(authorized_driver.status(), StatusCode::OK);
}

#[tokio::test]
async fn test_unknown_session_and_invalid_standings_season_are_rejected() {
    let (state, _temp) = test_state().await;
    let router = server::router(state);
    let missing = router
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v1/sessions/unknown/results")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::NOT_FOUND);
    let invalid = router
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v1/standings/drivers?season=not-a-year")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(invalid.status(), StatusCode::BAD_REQUEST);
    let invalid_zero = router
        .oneshot(
            Request::builder()
                .uri("/api/v1/standings/constructors?season=0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(invalid_zero.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn test_manual_refresh_requires_valid_target_and_session_scope() {
    let (state, _temp) = test_state().await;
    let router = server::router(state);
    for (body, expected) in [
        (
            r#"{"season":1949,"target":"calendar"}"#,
            StatusCode::BAD_REQUEST,
        ),
        (
            r#"{"season":2026,"target":"results"}"#,
            StatusCode::BAD_REQUEST,
        ),
        (
            r#"{"season":2026,"target":"calendar","sessionId":"unknown"}"#,
            StatusCode::BAD_REQUEST,
        ),
        (
            r#"{"season":2026,"target":"results","sessionId":"unknown"}"#,
            StatusCode::NOT_FOUND,
        ),
    ] {
        let response = router
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/api/v1/refresh")
                    .header(header::CONTENT_TYPE, "application/json")
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), expected);
    }
}

#[tokio::test]
async fn test_nonempty_standings_endpoints_return_snapshot_meta() {
    let (state, _temp) = test_state().await;
    let season = state
        .database
        .utc_now()
        .await
        .unwrap()
        .get(..4)
        .unwrap()
        .parse::<i64>()
        .unwrap();
    let fetched_at = state.database.utc_now().await.unwrap();
    state
        .database
        .replace_driver_standings(vec![DriverStanding {
            season,
            position: 1,
            driver_id: "leclerc".into(),
            driver_name: "Charles Leclerc".into(),
            constructor: "Ferrari".into(),
            constructor_ids: vec!["ferrari".into()],
            points: 25.0,
            wins: 1,
            source: "jolpica-ergast".into(),
            fetched_at: fetched_at.clone(),
            revision: 1,
        }])
        .await
        .unwrap();
    state
        .database
        .replace_constructor_standings(vec![ConstructorStanding {
            season,
            position: 1,
            constructor_id: "ferrari".into(),
            constructor_name: "Ferrari".into(),
            points: 25.0,
            wins: 1,
            source: "jolpica-ergast".into(),
            fetched_at,
            revision: 1,
        }])
        .await
        .unwrap();
    let response = server::router(state.clone())
        .oneshot(
            Request::builder()
                .uri(format!("/api/v1/standings/drivers?season={season}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let value: Value = serde_json::from_slice(
        &axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(value["data"][0]["driverId"], "leclerc");
    assert_eq!(value["data"][0]["constructorIds"][0], "ferrari");
    assert_eq!(value["meta"]["source"], "jolpica-ergast");
    assert_eq!(value["meta"]["quality"], "provisional");

    let default_season = server::router(state.clone())
        .oneshot(
            Request::builder()
                .uri("/api/v1/standings/drivers")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(default_season.status(), StatusCode::OK);
    let default_value: Value = serde_json::from_slice(
        &axum::body::to_bytes(default_season.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(default_value["data"][0]["season"], season);

    let constructors = server::router(state)
        .oneshot(
            Request::builder()
                .uri(format!("/api/v1/standings/constructors?season={season}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(constructors.status(), StatusCode::OK);
    let constructor_value: Value = serde_json::from_slice(
        &axum::body::to_bytes(constructors.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(constructor_value["data"][0]["constructorId"], "ferrari");
}

#[tokio::test]
async fn test_map_weather_radar_and_radio_routes_are_authenticated_and_lookup_only() {
    let (mut state, _temp) = test_state().await;
    let mut config = AppConfig::default();
    config.security.require_token = true;
    config.security.token = Some("test-token".into());
    config.providers.mapbox_public_token = Some("pk.test-public".into());
    state.config = std::sync::Arc::new(config);
    let router = server::router(state);
    for path in [
        "/api/v1/maps/config",
        "/api/v1/meetings/unknown/geometry",
        "/api/v1/meetings/unknown/weather",
        "/api/v1/weather/radar",
        "/api/v1/weather/tiles/radar/0/7/0/0",
        "/api/v1/live/radio/unknown/0",
    ] {
        let response = router
            .clone()
            .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED, "{path}");
    }
    let response = router
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v1/maps/config")
                .header(header::AUTHORIZATION, "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
    let body = axum::body::to_bytes(response.into_body(), 65536)
        .await
        .unwrap();
    let value: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(value["data"]["publicToken"], "pk.test-public");
    assert!(!String::from_utf8_lossy(&body).contains("test-token"));
    for (path, status) in [
        ("/api/v1/live/radio/unknown/0", StatusCode::NOT_FOUND),
        (
            "/api/v1/weather/tiles/radar/0/8/0/0",
            StatusCode::BAD_REQUEST,
        ),
        (
            "/api/v1/weather/tiles/bogus/0/0/0/0",
            StatusCode::BAD_REQUEST,
        ),
    ] {
        let response = router
            .clone()
            .oneshot(
                Request::builder()
                    .uri(path)
                    .header(header::AUTHORIZATION, "Bearer test-token")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), status, "{path}");
        let body = axum::body::to_bytes(response.into_body(), 65536)
            .await
            .unwrap();
        assert!(serde_json::from_slice::<Value>(&body).unwrap()["error"]["code"].is_string());
    }
}
