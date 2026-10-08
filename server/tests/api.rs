use axum::{
    body::Body,
    http::{Request, StatusCode, header},
};
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
                .uri("/api/v1/calendar")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(missing.status(), StatusCode::UNAUTHORIZED);

    let authorized = server::router(state)
        .oneshot(
            Request::builder()
                .uri("/api/v1/calendar")
                .header(header::AUTHORIZATION, "Bearer test-token")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(authorized.status(), StatusCode::OK);
}
