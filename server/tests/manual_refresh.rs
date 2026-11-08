use axum::{
    Json, Router,
    body::Body,
    http::{Request, StatusCode, header::RETRY_AFTER},
    response::IntoResponse,
    routing::get,
};
use pitpulse_server::{
    app_state::AppState, config::AppConfig, providers::jolpica::JolpicaProvider, scheduler, server,
    storage::sqlite::Database,
};
use serde_json::{Value, json};
use tempfile::TempDir;
use tokio::net::TcpListener;
use tower::ServiceExt;

async fn rate_limited() -> impl IntoResponse {
    (
        StatusCode::TOO_MANY_REQUESTS,
        [(RETRY_AFTER, "120")],
        Json(json!({})),
    )
}

#[tokio::test]
async fn test_manual_refresh_reports_upstream_rate_limit_and_retry_deadline() {
    let upstream_app = Router::new().route("/f1/alpha/schedules/2026/", get(rate_limited));
    let upstream_listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base_url = format!("http://{}", upstream_listener.local_addr().unwrap());
    let upstream = tokio::spawn(async move {
        axum::serve(upstream_listener, upstream_app).await.unwrap();
    });

    let temp = TempDir::new().unwrap();
    let mut config = AppConfig::default();
    config.database.path = temp.path().join("pitpulse.sqlite");
    config.providers.f1_live_enabled = false;
    config.providers.openf1_enabled = false;
    let database = Database::open(&config.database.path).await.unwrap();
    database.migrate().await.unwrap();
    let mut state = AppState::new(config, database);
    state.jolpica = JolpicaProvider::with_base_url(reqwest::Client::new(), base_url);
    state.openf1.enabled = false;
    let scheduler = scheduler::spawn(state.clone());

    let response = server::router(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/refresh")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"season":2026,"target":"calendar"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let event: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(event["status"], "rateLimited");
    assert!(event["retryAfter"].as_str().is_some());

    let status = state
        .database
        .sync_status("jolpica-alpha", "calendar-2026")
        .await
        .unwrap()
        .unwrap();
    assert_eq!(status.retry_count, 1);
    assert!(status.last_error.unwrap().contains("429"));
    assert!(status.next_retry_at.is_some());

    scheduler.shutdown().await;
    upstream.abort();
}
