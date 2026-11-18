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
async fn incomplete_fia_archive_serves_complete_legacy_season_record() {
    let (state, _temp) = test_state().await;
    // While the FIA archive is incomplete, the reader keeps the complete
    // legacy season record visible instead of serving an empty report.
    state
        .database
        .save_analysis_cache(
            "engineering:tech-updates:2026",
            &serde_json::json!({"data":[{"team":"legacy season record"}],"meta":{"source":"legacy","unavailable":false}}),
        )
        .await
        .unwrap();

    let response = server::router(state)
        .oneshot(get("/api/v1/tech-updates?season=2026"))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = serde_json::from_slice(
        &axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    // Fallback keeps the full season visible until the FIA archive is complete.
    assert_eq!(
        body["data"],
        serde_json::json!([{"team":"legacy season record"}])
    );
    assert_eq!(body["meta"]["unavailable"], false);
}

#[tokio::test]
async fn engineering_authors_to_complete_fia_archive_takes_precedence() {
    let (state, _temp) = test_state().await;
    // Once the FIA archive reports complete coverage it is authoritative, even
    // when a legacy season record still exists.
    state
        .database
        .save_analysis_cache(
            "pitpulse:fia:tech-updates:2026",
            &serde_json::json!({"data":[{"team":"fia archive"}],"meta":{"coverage":{"complete":true}}}),
        )
        .await
        .unwrap();
    state
        .database
        .save_analysis_cache(
            "engineering:tech-updates:2026",
            &serde_json::json!({"data":[{"team":"legacy season record"}],"meta":{"source":"legacy"}}),
        )
        .await
        .unwrap();

    let response = server::router(state)
        .oneshot(get("/api/v1/tech-updates?season=2026"))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body: Value = serde_json::from_slice(
        &axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    assert_eq!(body["data"], serde_json::json!([{"team":"fia archive"}]));
}

const SHELL_PATHS: [(&str, &str); 5] = [
    ("/", "text/html; charset=utf-8"),
    ("/app.css", "text/css; charset=utf-8"),
    ("/app.js", "text/javascript; charset=utf-8"),
    ("/theme.js", "text/javascript; charset=utf-8"),
    ("/manifest.webmanifest", "application/manifest+json"),
];

fn get(path: &str) -> Request<Body> {
    Request::builder().uri(path).body(Body::empty()).unwrap()
}

fn get_with_cookie(path: &str, cookie: &str) -> Request<Body> {
    Request::builder()
        .uri(path)
        .header(header::COOKIE, cookie)
        .body(Body::empty())
        .unwrap()
}

#[tokio::test]
async fn test_web_shell_requires_bootstrapped_session_while_icons_stay_public() {
    let (mut state, _temp) = test_state().await;
    let mut config = AppConfig::default();
    config.security.require_token = true;
    config.security.token = Some("test-token".to_string());
    state.config = std::sync::Arc::new(config);
    let router = server::router(state);
    let session_cookie = format!(
        "pitpulse_web={}",
        pitpulse_server::api::web_auth::session_value("test-token")
    );

    // Icons carry no data and are fetched by browsers and the OS without
    // credentials, so they stay public.
    for (path, content_type, signature) in [
        ("/favicon.png?v=2", "image/png", &b"\x89PNG\r\n\x1a\n"[..]),
        (
            "/favicon.ico",
            "image/x-icon",
            &b"\x00\x00\x01\x00\x03\x00"[..],
        ),
        ("/icon-192.png", "image/png", &b"\x89PNG\r\n\x1a\n"[..]),
        ("/icon-512.png", "image/png", &b"\x89PNG\r\n\x1a\n"[..]),
        (
            "/apple-touch-icon.png",
            "image/png",
            &b"\x89PNG\r\n\x1a\n"[..],
        ),
        ("/brand-mark.png", "image/png", &b"\x89PNG\r\n\x1a\n"[..]),
        (
            "/motorsport/2026/helmet/hamilton.png",
            "image/png",
            &b"\x89PNG\r\n\x1a\n"[..],
        ),
        (
            "/motorsport/2026/team-logo/ferrari.png",
            "image/png",
            &b"\x89PNG\r\n\x1a\n"[..],
        ),
        (
            "/motorsport/2026/team-logo/mercedes-dark.png",
            "image/png",
            &b"\x89PNG\r\n\x1a\n"[..],
        ),
        (
            "/motorsport/flag-gb.png",
            "image/png",
            &b"\x89PNG\r\n\x1a\n"[..],
        ),
    ] {
        let response = router.clone().oneshot(get(path)).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK, "{path}");
        assert_eq!(response.headers()[header::CONTENT_TYPE], content_type);
        assert_eq!(
            response.headers()[header::CACHE_CONTROL],
            "public, max-age=86400"
        );
        let bytes = axum::body::to_bytes(response.into_body(), 512 * 1024)
            .await
            .unwrap();
        assert!(bytes.starts_with(signature));
    }

    // Artwork that is not part of the bundle is a plain 404, not a guess.
    // The browser index is script, cached briefly so a new season is picked up
    // without a hard refresh.
    let response = router
        .clone()
        .oneshot(get("/motorsport/assets.js"))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response.headers()[header::CONTENT_TYPE],
        "text/javascript; charset=utf-8"
    );
    assert_eq!(
        response.headers()[header::CACHE_CONTROL],
        "public, max-age=300"
    );

    for path in [
        "/motorsport/2026/helmet/nobody.png",
        "/motorsport/2021/driver-photo/vettel.png",
        "/motorsport/../../Cargo.toml",
        "/motorsport/",
    ] {
        let response = router.clone().oneshot(get(path)).await.unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND, "{path}");
    }

    // The shell is part of the service: without a session it is not served at
    // all, and the refusal page carries no assets, no data and no token.
    for (path, _) in SHELL_PATHS {
        let response = router.clone().oneshot(get(path)).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED, "{path}");
        assert_eq!(
            response.headers()[header::CONTENT_TYPE],
            "text/html; charset=utf-8",
            "{path}"
        );
        assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
        assert!(response.headers().get(header::SET_COOKIE).is_none());
        let body = axum::body::to_bytes(response.into_body(), 64 * 1024)
            .await
            .unwrap();
        let text = String::from_utf8_lossy(&body);
        assert!(text.contains("需要访问权限"), "{path}");
        assert!(!text.contains("app.js"), "{path}");
        assert!(!text.contains("test-token"), "{path}");
    }

    // A wrong bootstrap token is refused without issuing a cookie.
    let response = router.clone().oneshot(get("/?token=wrong")).await.unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert!(response.headers().get(header::SET_COOKIE).is_none());

    // The right one exchanges the deployment token for a derived, HttpOnly
    // session cookie and redirects the browser back to a clean URL.
    let response = router
        .clone()
        .oneshot(get("/?token=test-token"))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(response.headers()[header::LOCATION], "/");
    assert_eq!(response.headers()[header::CACHE_CONTROL], "no-store");
    let cookie = response.headers()[header::SET_COOKIE]
        .to_str()
        .unwrap()
        .to_string();
    assert!(cookie.starts_with(&session_cookie), "{cookie}");
    assert!(cookie.contains("; Path=/"), "{cookie}");
    assert!(cookie.contains("; HttpOnly"), "{cookie}");
    assert!(cookie.contains("; SameSite=Lax"), "{cookie}");
    assert!(cookie.contains("; Max-Age="), "{cookie}");
    assert!(!cookie.contains("Secure"), "{cookie}");
    assert!(!cookie.contains("test-token"), "{cookie}");

    // Behind the TLS proxy the cookie is marked Secure.
    let response = router
        .clone()
        .oneshot(
            Request::builder()
                .uri("/?token=test-token")
                .header("x-forwarded-proto", "https")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert!(
        response.headers()[header::SET_COOKIE]
            .to_str()
            .unwrap()
            .contains("; Secure")
    );

    // With the session cookie the shell and its assets are served, private to
    // that browser.
    for (path, content_type) in SHELL_PATHS {
        let response = router
            .clone()
            .oneshot(get_with_cookie(path, &session_cookie))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK, "{path}");
        assert_eq!(response.headers()[header::CONTENT_TYPE], content_type);
        assert_eq!(
            response.headers()[header::CACHE_CONTROL],
            "private, no-cache",
            "{path}"
        );
        assert_eq!(response.headers()[header::VARY], "Cookie", "{path}");
    }

    let response = router
        .clone()
        .oneshot(get_with_cookie("/", &session_cookie))
        .await
        .unwrap();
    let html = axum::body::to_bytes(response.into_body(), 64 * 1024)
        .await
        .unwrap();
    let html = std::str::from_utf8(&html).unwrap();
    assert!(html.contains("href=\"/app.css\""));
    assert!(html.contains("src=\"/app.js\""));
    assert!(html.contains("href=\"/manifest.webmanifest\""));
    // The topbar carries the real brand mark, not an inline placeholder.
    assert!(html.contains("src=\"/brand-mark.png\""));
    assert!(!html.contains("auth-dialog"));
    assert!(!html.contains("lock-btn"));
    assert!(!html.contains("api-meta"));
    assert!(!html.contains("<footer"));
    // Icons are versioned so a restyled set is fetched instead of cached.
    assert!(html.contains("/favicon.png?v=2"));

    let response = router
        .clone()
        .oneshot(get_with_cookie("/", &session_cookie))
        .await
        .unwrap();
    let csp = response
        .headers()
        .get("content-security-policy")
        .unwrap()
        .to_str()
        .unwrap();
    assert!(csp.contains("default-src 'self'"));
    assert!(csp.contains("frame-ancestors 'none'"));

    // The same cookie is a read-only API credential: GETs work, writes do not.
    for path in [
        "/api/v1/health",
        "/api/v1/calendar",
        "/api/v1/live/snapshot",
    ] {
        let response = router
            .clone()
            .oneshot(get_with_cookie(path, &session_cookie))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK, "{path}");
    }
    let response = router
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/refresh")
                .header(header::COOKIE, &session_cookie)
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(r#"{"season":2026,"target":"calendar"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    // A stale or forged cookie is refused.
    for cookie in ["pitpulse_web=bogus", "other=value"] {
        let response = router
            .clone()
            .oneshot(get_with_cookie("/", cookie))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED, "{cookie}");
    }

    // Scripted and CLI callers keep full access with the bearer token.
    for path in ["/", "/api/v1/health"] {
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
        assert_eq!(response.status(), StatusCode::OK, "{path}");
    }

    for path in [
        "/api/v1/health",
        "/api/v1/calendar",
        "/api/v1/live/snapshot",
    ] {
        let response = router.clone().oneshot(get(path)).await.unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED, "{path}");
    }
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
            driver_number: None,
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
