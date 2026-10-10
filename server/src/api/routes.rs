use std::collections::HashMap;

use axum::{
    Json, Router,
    extract::{Path, Query, State},
    response::Html,
    routing::get,
};
use serde_json::json;

use crate::{api::dto::HealthResponse, app_state::AppState, error::ApiError};

pub fn build_router(state: AppState) -> Router<AppState> {
    Router::new()
        .route("/", get(index))
        .route("/api/v1/health", get(health))
        .route("/api/v1/calendar", get(calendar))
        .route("/api/v1/meetings/next", get(next_meeting))
        .route("/api/v1/sessions/{sessionId}/results", get(session_results))
        .route("/api/v1/standings/drivers", get(driver_standings))
        .route("/api/v1/standings/constructors", get(constructor_standings))
        .route(
            "/api/v1/sessions/{sessionId}/drivers/{driverId}/analysis",
            get(crate::services::analysis::session_analysis),
        )
        .route(
            "/api/v1/standings/{kind}/{id}/analysis",
            get(crate::services::analysis::season_analysis),
        )
        .route("/api/v1/live/snapshot", get(live_snapshot))
        .route("/api/v1/live/stream", get(crate::api::sse::live_stream))
        .with_state(state)
}

async fn index() -> Html<&'static str> {
    Html("PitPulse API is running")
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

async fn live_snapshot(State(state): State<AppState>) -> Json<serde_json::Value> {
    Json(json!({"data": state.live.current().clone()}))
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
