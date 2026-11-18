use std::collections::HashMap;

use axum::{
    Json, Router,
    body::Body,
    extract::{Path, Query, State},
    http::{HeaderValue, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use serde_json::json;

use crate::{api::dto::HealthResponse, app_state::AppState, error::ApiError};

const INDEX_HTML: &str = include_str!("../../resources/web/index.html");
const APP_CSS: &str = include_str!("../../resources/web/app.css");
const APP_JS: &str = include_str!("../../resources/web/app.js");
const THEME_JS: &str = include_str!("../../resources/web/theme.js");
const MANIFEST: &str = include_str!("../../resources/web/manifest.webmanifest");
const APPLE_TOUCH_ICON: &[u8] = include_bytes!("../../resources/web/apple-touch-icon.png");
const BRAND_MARK: &[u8] = include_bytes!("../../resources/web/brand-mark.png");
const ICON_192: &[u8] = include_bytes!("../../resources/web/icon-192.png");
const ICON_512: &[u8] = include_bytes!("../../resources/web/icon-512.png");

include!(concat!(env!("OUT_DIR"), "/motorsport_assets.rs"));
include!(concat!(env!("OUT_DIR"), "/motorsport_legacy_assets.rs"));
include!(concat!(env!("OUT_DIR"), "/motorsport_index.rs"));

/// The shell is served only to browsers holding the session cookie issued by
/// the `/?token=` bootstrap. It contains no data; every API call it makes is
/// still authenticated.
const SHELL_CSP: &str = "default-src 'self'; img-src 'self' data:; style-src 'self'; \
script-src 'self'; connect-src 'self'; manifest-src 'self'; base-uri 'none'; \
form-action 'none'; frame-ancestors 'none'";

pub fn build_router(state: AppState) -> Router<AppState> {
    Router::new()
        .route("/api/v1/calendar", get(calendar))
        .route("/api/v1/home", get(crate::services::engineering::home))
        .route(
            "/api/v1/tech-updates",
            get(crate::services::engineering::tech),
        )
        .route(
            "/api/v1/pu-elements",
            get(crate::services::engineering::power_unit),
        )
        .route(
            "/api/v1/destructors-championship",
            get(crate::services::engineering::destructors),
        )
        .route(
            "/api/v1/features",
            get(crate::services::engineering::season_features),
        )
        .route(
            "/api/v1/results/season",
            get(crate::services::season_results::overview),
        )
        .route("/api/v1/standings/drivers", get(driver_standings))
        .route("/api/v1/standings/constructors", get(constructor_standings))
        .route_layer(axum::middleware::from_fn_with_state(
            state.clone(),
            super::dashboard_cache::cache_response,
        ))
        .route("/api/v1/health", get(health))
        .route("/api/v1/meetings/next", get(next_meeting))
        .route("/api/v1/sessions/{sessionId}/results", get(session_results))
        .route(
            "/api/v1/sessions/{sessionId}/drivers/{driverId}/analysis",
            get(crate::services::analysis::session_analysis),
        )
        .route(
            "/api/v1/standings/{kind}/{id}/analysis",
            get(crate::services::analysis::season_analysis),
        )
        .route("/api/v1/maps/config", get(super::maps::config))
        .route(
            "/api/v1/meetings/{meetingId}/geometry",
            get(super::maps::geometry),
        )
        .route(
            "/api/v1/meetings/{meetingId}/weather",
            get(super::maps::weather),
        )
        .route("/api/v1/weather/radar", get(super::maps::radar_frames))
        .route(
            "/api/v1/weather/tiles/{kind}/{frame}/{z}/{x}/{y}",
            get(super::maps::radar_tile),
        )
        .route("/api/v1/live/radio/{session}/{id}", get(super::maps::radio))
        .route("/api/v1/live/snapshot", get(live_snapshot))
        .route("/api/v1/live/stream", get(crate::api::sse::live_stream))
        .route("/api/v1/refresh", post(crate::api::refresh::refresh))
        .with_state(state)
}

/// Web shell for the self-hosted dashboard, behind the browser session guard.
pub async fn index() -> Response {
    let mut response = INDEX_HTML.into_response();
    let headers = response.headers_mut();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/html; charset=utf-8"),
    );
    private_shell_cache(headers);
    headers.insert(
        header::HeaderName::from_static("content-security-policy"),
        HeaderValue::from_static(SHELL_CSP),
    );
    headers.insert(
        header::REFERRER_POLICY,
        HeaderValue::from_static("no-referrer"),
    );
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    response
}

pub async fn app_css() -> Response {
    text_asset(APP_CSS, "text/css; charset=utf-8")
}

pub async fn app_js() -> Response {
    text_asset(APP_JS, "text/javascript; charset=utf-8")
}

/// Runs before the first paint so the page never flashes the wrong theme.
pub async fn theme_js() -> Response {
    text_asset(THEME_JS, "text/javascript; charset=utf-8")
}

pub async fn manifest() -> Response {
    text_asset(MANIFEST, "application/manifest+json")
}

pub async fn apple_touch_icon() -> Response {
    icon_asset(APPLE_TOUCH_ICON)
}

pub async fn brand_mark() -> Response {
    icon_asset(BRAND_MARK)
}

pub async fn icon_192() -> Response {
    icon_asset(ICON_192)
}

pub async fn icon_512() -> Response {
    icon_asset(ICON_512)
}

/// Season artwork (`{season}/{kind}/{id}.png`), the flags that still live beside
/// the shell, and the index that tells the page which of them exist. Public like
/// the app icons: the dashboard only reads them.
pub async fn motorsport_asset(Path(path): Path<String>) -> Response {
    if path == "assets.js" {
        return script_asset(MOTORSPORT_INDEX_JS);
    }
    let found = MOTORSPORT_ASSETS
        .iter()
        .find(|(name, _)| *name == path.as_str())
        .or_else(|| {
            MOTORSPORT_LEGACY_ASSETS
                .iter()
                .find(|(name, _)| *name == path.as_str())
        });
    match found {
        Some((_, bytes)) => icon_asset(bytes),
        None => (
            axum::http::StatusCode::NOT_FOUND,
            [
                (header::CONTENT_TYPE, "text/plain; charset=utf-8"),
                (header::CACHE_CONTROL, "public, max-age=300"),
            ],
            "not found",
        )
            .into_response(),
    }
}

fn script_asset(body: &'static str) -> Response {
    let mut response = body.into_response();
    let headers = response.headers_mut();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/javascript; charset=utf-8"),
    );
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=300"),
    );
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    response
}

fn text_asset(body: &'static str, content_type: &'static str) -> Response {
    let mut response = body.into_response();
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static(content_type));
    private_shell_cache(headers);
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    response
}

/// Authenticated shell responses must not be handed to another browser by a
/// shared cache, so they are private and keyed on the session cookie.
fn private_shell_cache(headers: &mut axum::http::HeaderMap) {
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("private, no-cache"),
    );
    headers.insert(header::VARY, HeaderValue::from_static("Cookie"));
}

fn icon_asset(bytes: &'static [u8]) -> Response {
    let mut response = Body::from(bytes).into_response();
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, HeaderValue::from_static("image/png"));
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=86400"),
    );
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );
    response
}

pub async fn favicon_ico() -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "image/x-icon"),
            (header::CACHE_CONTROL, "public, max-age=86400"),
        ],
        include_bytes!("../../resources/branding/favicon.ico").as_slice(),
    )
}

pub async fn favicon_png() -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "image/png"),
            (header::CACHE_CONTROL, "public, max-age=86400"),
        ],
        include_bytes!("../../resources/branding/favicon.png").as_slice(),
    )
}

async fn health(State(state): State<AppState>) -> Result<Json<HealthResponse>, ApiError> {
    let database_healthy = state.database.health_check().await.is_ok();
    let live_healthy =
        state.live.current().source_status != crate::domain::live::LiveStatus::Disconnected;

    Ok(Json(HealthResponse {
        status: if database_healthy { "ok" } else { "degraded" }.to_string(),
        database: database_healthy,
        live: live_healthy,
        version: env!("CARGO_PKG_VERSION").to_string(),
    }))
}

async fn calendar(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let season = parse_season(&params)?;
    let (meetings, mut meta) = state.database.calendar(season).await?;
    let season_id = match season {
        Some(season) => season,
        None => current_year(&state).await?,
    };
    meta.sync_status = state
        .database
        .sync_status("jolpica-alpha", &format!("calendar-{season_id}"))
        .await?;
    Ok(Json(json!({"data": meetings, "meta": meta})))
}

async fn next_meeting(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let season = parse_season(&params)?;
    let (meeting, mut meta) = state.database.next_meeting(season).await?;
    let season_id = match season {
        Some(season) => season,
        None => current_year(&state).await?,
    };
    meta.sync_status = state
        .database
        .sync_status("jolpica-alpha", &format!("calendar-{season_id}"))
        .await?;
    Ok(Json(json!({"data": meeting, "meta": meta})))
}

async fn session_results(
    State(state): State<AppState>,
    Path(session_id): Path<String>,
) -> Result<Json<serde_json::Value>, ApiError> {
    if !state.database.session_exists(&session_id).await? {
        return Err(ApiError::NotFound);
    }
    let (results, mut meta) = state.database.session_results(&session_id).await?;
    meta.sync_status = state
        .database
        .sync_status("jolpica-alpha", &format!("results-{session_id}"))
        .await?;
    if results.is_empty() {
        meta.quality = crate::domain::quality::DataQuality::Pending;
        meta.stale = false;
    }
    Ok(Json(json!({"data": results, "meta": meta})))
}

async fn driver_standings(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let season = parse_season(&params)?;
    let (standings, mut meta) = state.database.driver_standings(season).await?;
    let season_id = match season {
        Some(season) => season,
        None => current_year(&state).await?,
    };
    meta.sync_status = state
        .database
        .sync_status("jolpica-alpha", &format!("standings-drivers-{season_id}"))
        .await?;
    if standings.is_empty() {
        meta.quality = crate::domain::quality::DataQuality::Pending;
        meta.stale = false;
    }
    Ok(Json(json!({"data": standings, "meta": meta})))
}

async fn constructor_standings(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let season = parse_season(&params)?;
    let (standings, mut meta) = state.database.constructor_standings(season).await?;
    let season_id = match season {
        Some(season) => season,
        None => current_year(&state).await?,
    };
    meta.sync_status = state
        .database
        .sync_status(
            "jolpica-alpha",
            &format!("standings-constructors-{season_id}"),
        )
        .await?;
    if standings.is_empty() {
        meta.quality = crate::domain::quality::DataQuality::Pending;
        meta.stale = false;
    }
    Ok(Json(json!({"data": standings, "meta": meta})))
}

async fn live_snapshot(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let series = params.get("series").map(String::as_str).unwrap_or("f1");
    let live = state
        .live_for(series)
        .ok_or_else(|| ApiError::InvalidQuery {
            field: "series".to_string(),
            error: "expected f1 or wec".to_string(),
        })?;
    Ok(Json(json!({"data": live.current().clone()})))
}

fn parse_season(params: &HashMap<String, String>) -> Result<Option<i64>, ApiError> {
    let season = params
        .get("season")
        .map(|value| {
            value
                .parse::<i64>()
                .map_err(|error| ApiError::InvalidQuery {
                    field: "season".to_string(),
                    error: error.to_string(),
                })
        })
        .transpose()?;
    if season.is_some_and(|year| !(1950..=9999).contains(&year)) {
        return Err(ApiError::InvalidQuery {
            field: "season".to_string(),
            error: "season must be between 1950 and 9999".to_string(),
        });
    }
    // Seasons before the product range were removed from the archive. Refusing
    // them here also stops the on-demand refresh from importing them again.
    if season.is_some_and(|year| year < crate::services::FIRST_SEASON) {
        return Err(ApiError::NotOffered {
            section: "season".to_string(),
            first_season: crate::services::FIRST_SEASON,
        });
    }
    Ok(season)
}

async fn current_year(state: &AppState) -> Result<i64, ApiError> {
    let now = state.database.utc_now().await?;
    now.get(..4)
        .and_then(|year| year.parse().ok())
        .ok_or_else(|| ApiError::InvalidQuery {
            field: "season".to_string(),
            error: "current UTC year is unavailable".to_string(),
        })
}

#[cfg(test)]
mod motorsport_assets_tests {
    use super::*;

    #[test]
    fn embedded_artwork_covers_every_kind() {
        for kind in ["driver-photo", "helmet", "car-side", "team-logo"] {
            assert!(
                MOTORSPORT_ASSETS
                    .iter()
                    .any(|(name, _)| name.contains(&format!("/{kind}/"))),
                "no {kind} artwork is embedded"
            );
        }
    }

    #[test]
    fn embedded_keys_are_relative_paths() {
        for (name, bytes) in MOTORSPORT_ASSETS {
            assert!(name.ends_with(".png"), "unexpected asset key {name}");
            assert!(
                !name.starts_with("resources/"),
                "asset key keeps a filesystem prefix: {name}"
            );
            assert!(!bytes.is_empty(), "empty asset {name}");
        }
    }

    #[test]
    fn index_lists_every_embedded_asset() {
        for (name, _) in MOTORSPORT_ASSETS {
            let stem = name.strip_suffix(".png").expect("png suffix");
            assert!(
                MOTORSPORT_INDEX_JS.contains(&format!("\"{stem}\":1")),
                "the browser index is missing {stem}"
            );
        }
    }

    #[test]
    fn every_country_code_has_a_flag() {
        for code in crate::domain::country::ALPHA2_CODES {
            let name = format!("flag-{}.png", code.to_ascii_lowercase());
            assert!(
                MOTORSPORT_LEGACY_ASSETS.iter().any(|(key, _)| *key == name),
                "no flag artwork for {code} ({name})"
            );
        }
    }

    #[test]
    fn legacy_flags_stay_on_the_flat_path() {
        assert!(
            MOTORSPORT_LEGACY_ASSETS
                .iter()
                .any(|(name, _)| *name == "flag-gb.png"),
            "the flags moved out of the shell directory"
        );
        for (name, _) in MOTORSPORT_LEGACY_ASSETS {
            assert!(!name.contains('/'), "legacy key must stay flat: {name}");
        }
    }
}
