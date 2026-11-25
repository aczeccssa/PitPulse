use std::collections::HashMap;

use axum::{
    Json, Router,
    extract::{DefaultBodyLimit, Path, Query, Request, State, rejection::JsonRejection},
    http::{HeaderMap, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Response},
    routing::post,
};
use serde::Deserialize;
use serde_json::{Value, json};

use crate::{app_state::AppState, error::ApiError};

use super::{middleware::require_mcp_token, routes};

const PROTOCOL_VERSIONS: &[&str] = &["2025-11-25", "2025-06-18"];

pub(crate) fn router(state: AppState) -> Router<AppState> {
    Router::new()
        .route("/mcp", post(post_message))
        .route_layer(DefaultBodyLimit::max(64 * 1024))
        .route_layer(middleware::from_fn_with_state(state, require_mcp_token))
        .route_layer(middleware::from_fn(reject_browser_origin))
}

async fn reject_browser_origin(request: Request, next: Next) -> Response {
    // Only native and server-to-server clients are allowed, including when
    // authentication is disabled for local development.
    if request.headers().contains_key(header::ORIGIN) {
        return StatusCode::FORBIDDEN.into_response();
    }
    next.run(request).await
}

async fn post_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Result<Json<Value>, JsonRejection>,
) -> Response {
    if headers.get_all("mcp-protocol-version").iter().count() > 1
        || headers.get("mcp-protocol-version").is_some_and(|version| {
            !version
                .to_str()
                .is_ok_and(|version| PROTOCOL_VERSIONS.contains(&version))
        })
    {
        return StatusCode::BAD_REQUEST.into_response();
    }

    let message = match body {
        Ok(Json(value)) => value,
        Err(JsonRejection::JsonSyntaxError(_)) => {
            return (
                StatusCode::BAD_REQUEST,
                rpc_error(Value::Null, -32700, "Parse error"),
            )
                .into_response();
        }
        Err(error) => return error.into_response(),
    };
    let method = message["method"].as_str();
    let id = message.get("id");
    let valid_id = id.is_none_or(|id| id.is_string() || id.is_i64() || id.is_u64());
    if message["jsonrpc"] != "2.0" || method.is_none() || !valid_id {
        return (
            StatusCode::BAD_REQUEST,
            rpc_error(Value::Null, -32600, "Invalid request"),
        )
            .into_response();
    }

    let Some(id) = id else {
        // The server never sends requests or creates sessions. In particular,
        // notifications/initialized is acknowledged without a JSON-RPC body.
        return StatusCode::ACCEPTED.into_response();
    };
    let params = message.get("params");
    if params.is_some_and(|params| !params.is_object()) {
        return rpc_error(id.clone(), -32602, "Invalid params").into_response();
    }
    let result = match method {
        Some("initialize") => {
            let Some(version) = params.and_then(|p| p["protocolVersion"].as_str()) else {
                return rpc_error(id.clone(), -32602, "protocolVersion is required")
                    .into_response();
            };
            let version = if PROTOCOL_VERSIONS.contains(&version) {
                version
            } else {
                PROTOCOL_VERSIONS[0]
            };
            json!({
                "protocolVersion": version,
                "serverInfo": {"name": "pitpulse", "version": env!("CARGO_PKG_VERSION")},
                "capabilities": {"tools": {}}
            })
        }
        Some("ping") => json!({}),
        Some("tools/list") => json!({"tools": tools()}),
        Some("tools/call") => match call_tool(state, params).await {
            Ok(result) => result,
            Err(message) => return rpc_error(id.clone(), -32602, message).into_response(),
        },
        _ => return rpc_error(id.clone(), -32601, "Method not found").into_response(),
    };
    Json(json!({"jsonrpc": "2.0", "id": id, "result": result})).into_response()
}

fn rpc_error(id: Value, code: i32, message: &str) -> Json<Value> {
    Json(json!({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}))
}

fn tools() -> [Value; 6] {
    let season = json!({"season": {
        "type": "integer", "minimum": crate::services::FIRST_SEASON, "maximum": 9999,
        "description": "Season year. Defaults to the current season."
    }});
    [
        read_tool(
            "get_calendar",
            "List scheduled F1 meetings and sessions.",
            &season,
            &[],
        ),
        read_tool(
            "get_next_meeting",
            "Get the next scheduled F1 meeting.",
            &season,
            &[],
        ),
        read_tool(
            "get_driver_standings",
            "Get F1 driver standings.",
            &season,
            &[],
        ),
        read_tool(
            "get_constructor_standings",
            "Get F1 constructor standings.",
            &season,
            &[],
        ),
        read_tool(
            "get_session_results",
            "Get classifications for an F1 session.",
            &json!({"sessionId": {"type": "string", "minLength": 1}}),
            &["sessionId"],
        ),
        read_tool(
            "get_live_snapshot",
            "Get the latest F1 or WEC timing snapshot.",
            &json!({"series": {"type": "string", "enum": ["f1", "wec"], "default": "f1"}}),
            &[],
        ),
    ]
}

fn read_tool(name: &str, description: &str, properties: &Value, required: &[&str]) -> Value {
    json!({
        "name": name, "description": description,
        "inputSchema": {
            "type": "object", "properties": properties, "required": required, "additionalProperties": false
        },
        "annotations": {"readOnlyHint": true, "openWorldHint": false}
    })
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SeasonArgs {
    season: Option<i64>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SessionArgs {
    session_id: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct LiveArgs {
    series: Option<String>,
}

fn arguments<T: serde::de::DeserializeOwned>(args: Option<&Value>) -> Result<T, &'static str> {
    if args.is_some_and(|args| !args.is_object()) {
        return Err("Tool arguments must be an object");
    }
    serde_json::from_value(args.cloned().unwrap_or_else(|| json!({})))
        .map_err(|_| "Invalid tool arguments")
}

async fn call_tool(state: AppState, params: Option<&Value>) -> Result<Value, &'static str> {
    let params = params.ok_or("Tool name is required")?;
    let name = params["name"].as_str().ok_or("Tool name is required")?;
    let args = params.get("arguments");
    let state = State(state);
    let result = match name {
        "get_calendar"
        | "get_next_meeting"
        | "get_driver_standings"
        | "get_constructor_standings" => {
            let args: SeasonArgs = arguments(args)?;
            let query = Query(
                args.season
                    .into_iter()
                    .map(|year| ("season".into(), year.to_string()))
                    .collect(),
            );
            match name {
                "get_calendar" => routes::calendar(state, query).await,
                "get_next_meeting" => routes::next_meeting(state, query).await,
                "get_driver_standings" => routes::driver_standings(state, query).await,
                _ => routes::constructor_standings(state, query).await,
            }
        }
        "get_session_results" => {
            let args: SessionArgs = arguments(args)?;
            if args.session_id.trim().is_empty() {
                return Err("sessionId must not be blank");
            }
            routes::session_results(state, Path(args.session_id)).await
        }
        "get_live_snapshot" => {
            let args: LiveArgs = arguments(args)?;
            let mut query = HashMap::new();
            if let Some(series) = args.series {
                query.insert("series".to_owned(), series);
            }
            routes::live_snapshot(state, Query(query)).await
        }
        _ => return Err("Unknown tool"),
    };
    Ok(match result {
        Ok(Json(data)) => json!({"content": [{"type": "text", "text": data.to_string()}]}),
        Err(error) => {
            let text = match error {
                ApiError::Storage(_) => {
                    tracing::error!(%error, "MCP tool failed");
                    "Database operation failed".to_owned()
                }
                _ => error.to_string(),
            };
            json!({"isError": true, "content": [{"type": "text", "text": text}]})
        }
    })
}
