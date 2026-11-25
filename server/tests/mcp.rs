use axum::{
    Router,
    body::{Body, to_bytes},
    http::{Request, Response, StatusCode, header},
};
use pitpulse_server::{
    api::web_auth::{WEB_COOKIE, session_value},
    app_state::AppState,
    config::AppConfig,
    server,
    storage::sqlite::Database,
};
use serde_json::{Value, json};
use tempfile::TempDir;
use tower::ServiceExt;

const TOKEN: &str = "test-api-token";

async fn app(token: Option<&str>) -> (Router, TempDir) {
    let dir = tempfile::tempdir().unwrap();
    let mut config = AppConfig::default();
    config.database.path = dir.path().join("mcp.sqlite");
    config.security.require_token = token.is_some();
    config.security.token = token.map(str::to_owned);
    let database = Database::open(&config.database.path).await.unwrap();
    database.migrate().await.unwrap();
    (server::router(AppState::new(config, database)), dir)
}

fn mcp(body: Value) -> Request<Body> {
    Request::post("/mcp")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .body(Body::from(body.to_string()))
        .unwrap()
}

fn rpc(method: &str, params: Value) -> Request<Body> {
    mcp(json!({"jsonrpc": "2.0", "id": "request-1", "method": method, "params": params}))
}

fn authorize(request: &mut Request<Body>, token: &str) {
    request.headers_mut().insert(
        header::AUTHORIZATION,
        format!("Bearer {token}").parse().unwrap(),
    );
}

async fn send(app: &Router, request: Request<Body>) -> Response<Body> {
    app.clone().oneshot(request).await.unwrap()
}

async fn payload(response: Response<Body>) -> Value {
    serde_json::from_slice(&to_bytes(response.into_body(), 1024 * 1024).await.unwrap()).unwrap()
}

#[tokio::test]
async fn mcp_and_rest_share_the_configured_bearer() {
    let (app, _dir) = app(Some(TOKEN)).await;
    for (token, expected) in [
        (None, StatusCode::UNAUTHORIZED),
        (Some("wrong"), StatusCode::UNAUTHORIZED),
        (Some(TOKEN), StatusCode::OK),
    ] {
        let mut mcp_request = rpc("tools/list", json!({}));
        let mut rest_request = Request::get("/api/v1/health").body(Body::empty()).unwrap();
        if let Some(token) = token {
            authorize(&mut mcp_request, token);
            authorize(&mut rest_request, token);
        }
        for request in [mcp_request, rest_request] {
            let response = send(&app, request).await;
            assert_eq!(response.status(), expected);
            if expected == StatusCode::UNAUTHORIZED {
                assert_eq!(
                    response.headers()[header::WWW_AUTHENTICATE],
                    "Bearer realm=\"PitPulse\""
                );
                assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
            }
        }
    }
}

#[tokio::test]
async fn mcp_does_not_accept_dashboard_cookies_or_query_tokens() {
    let (app, _dir) = app(Some(TOKEN)).await;
    let cookie = format!("{WEB_COOKIE}={}", session_value(TOKEN));
    let rest = Request::get("/api/v1/health")
        .header(header::COOKIE, &cookie)
        .body(Body::empty())
        .unwrap();
    assert_eq!(send(&app, rest).await.status(), StatusCode::OK);
    let mut request = rpc("tools/list", json!({}));
    *request.uri_mut() = format!("/mcp?token={TOKEN}").parse().unwrap();
    request
        .headers_mut()
        .insert(header::COOKIE, cookie.parse().unwrap());
    assert_eq!(send(&app, request).await.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn mcp_negotiates_and_returns_the_same_snapshot_as_rest() {
    let (app, _dir) = app(Some(TOKEN)).await;
    let mut initialize = rpc(
        "initialize",
        json!({
            "protocolVersion": "2025-06-18",
            "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}
        }),
    );
    authorize(&mut initialize, TOKEN);
    let response = send(&app, initialize).await;
    assert_eq!(response.status(), StatusCode::OK);
    assert!(!response.headers().contains_key("mcp-session-id"));
    let initialized = payload(response).await;
    assert_eq!(initialized["id"], "request-1");
    assert_eq!(initialized["result"]["protocolVersion"], "2025-06-18");
    assert_eq!(initialized["result"]["capabilities"]["tools"], json!({}));

    let mut notification = mcp(json!({"jsonrpc": "2.0", "method": "notifications/initialized"}));
    authorize(&mut notification, TOKEN);
    let response = send(&app, notification).await;
    assert_eq!(response.status(), StatusCode::ACCEPTED);
    assert!(to_bytes(response.into_body(), 1).await.unwrap().is_empty());

    let mut list = rpc("tools/list", json!({}));
    list.headers_mut()
        .insert("mcp-protocol-version", "2025-06-18".parse().unwrap());
    authorize(&mut list, TOKEN);
    let tools = payload(send(&app, list).await).await["result"]["tools"].clone();
    let tools = tools.as_array().unwrap();
    assert_eq!(tools.len(), 6);
    assert!(
        tools
            .iter()
            .all(|tool| tool["annotations"]["readOnlyHint"] == true)
    );
    assert!(tools.iter().any(|tool| tool["name"] == "get_live_snapshot"));

    let mut call = rpc(
        "tools/call",
        json!({"name": "get_live_snapshot", "arguments": {"series": "wec"}}),
    );
    authorize(&mut call, TOKEN);
    let response = send(&app, call).await;
    assert_eq!(response.status(), StatusCode::OK);
    let mcp_data: Value = serde_json::from_str(
        payload(response).await["result"]["content"][0]["text"]
            .as_str()
            .unwrap(),
    )
    .unwrap();
    let rest = Request::get("/api/v1/live/snapshot?series=wec")
        .header(header::AUTHORIZATION, format!("Bearer {TOKEN}"))
        .body(Body::empty())
        .unwrap();
    assert_eq!(mcp_data, payload(send(&app, rest).await).await);
}

#[tokio::test]
async fn mcp_local_mode_rejects_origins_and_handles_protocol_errors() {
    let (app, _dir) = app(None).await;
    let mut request = rpc("ping", json!({}));
    request
        .headers_mut()
        .insert(header::ORIGIN, "https://example.invalid".parse().unwrap());
    assert_eq!(send(&app, request).await.status(), StatusCode::FORBIDDEN);
    let mut request = rpc("ping", json!({}));
    request
        .headers_mut()
        .insert("mcp-protocol-version", "unsupported".parse().unwrap());
    assert_eq!(send(&app, request).await.status(), StatusCode::BAD_REQUEST);

    let get = Request::get("/mcp").body(Body::empty()).unwrap();
    assert_eq!(
        send(&app, get).await.status(),
        StatusCode::METHOD_NOT_ALLOWED
    );
    let response = send(&app, rpc("ping", json!({}))).await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(payload(response).await["result"], json!({}));

    let invalid_arguments = rpc(
        "tools/call",
        json!({"name": "get_calendar", "arguments": {"season": "2026"}}),
    );
    assert_eq!(
        payload(send(&app, invalid_arguments).await).await["error"]["code"],
        -32602
    );
    let positional_arguments = rpc(
        "tools/call",
        json!({"name": "get_calendar", "arguments": [2026]}),
    );
    assert_eq!(
        payload(send(&app, positional_arguments).await).await["error"]["code"],
        -32602
    );
    let unavailable = rpc(
        "tools/call",
        json!({"name": "get_session_results", "arguments": {"sessionId": "missing"}}),
    );
    assert_eq!(
        payload(send(&app, unavailable).await).await["result"]["isError"],
        true
    );
    let unknown_method = rpc("unknown", json!({}));
    assert_eq!(
        payload(send(&app, unknown_method).await).await["error"]["code"],
        -32601
    );
}
