use axum::{
    Json,
    extract::{Request, State},
    http::{StatusCode, header},
    middleware::Next,
    response::{IntoResponse, Response},
};
use serde_json::json;

use crate::{
    api::web_auth::{allows_read_only, bearer_matches, cookie_matches},
    app_state::AppState,
};

pub async fn require_bearer_token(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Response {
    authorize(&state, request, next, true).await
}

pub(super) async fn require_mcp_token(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Response {
    authorize(&state, request, next, false).await
}

async fn authorize(
    state: &AppState,
    request: Request,
    next: Next,
    allow_web_session: bool,
) -> Response {
    if !state.config.security.require_token {
        return next.run(request).await;
    }

    let expected = state
        .config
        .security
        .token
        .as_ref()
        .expect("token checked during config validation");

    // The bearer token grants the full API. The browser session the dashboard
    // bootstraps is a separate, derived credential and only admits reads, so a
    // cookie copied out of a browser cannot mutate server state.
    let authorized = bearer_matches(request.headers(), expected)
        || (allow_web_session
            && !request.uri().path().starts_with("/api/v1/media/")
            && allows_read_only(request.method())
            && cookie_matches(request.headers(), expected));

    if authorized {
        next.run(request).await
    } else {
        (
            StatusCode::UNAUTHORIZED,
            [
                (header::WWW_AUTHENTICATE, "Bearer realm=\"PitPulse\""),
                (header::CACHE_CONTROL, "no-store"),
            ],
            Json(json!({"error": {"code": "unauthorized", "message": "bearer token required"}})),
        )
            .into_response()
    }
}
