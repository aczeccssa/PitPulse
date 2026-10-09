use std::{
    path::PathBuf,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU8, Ordering},
    },
    time::Duration,
};

use axum::{
    Json, Router,
    extract::{Path, State},
    http::{StatusCode, header},
    response::{IntoResponse, Response},
    routing::{get, post},
};
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::calendar::SessionType,
    providers::{jolpica::JolpicaProvider, openf1::OpenF1Provider},
    server,
    services::{results_sync::ResultsSync, sync::CalendarSync},
    storage::sqlite::Database,
};
use reqwest::Client;
use serde_json::{Value, json};
use tempfile::TempDir;
use tokio::net::TcpListener;

const SEASON: i64 = 2026;
const CALENDAR: &str = include_str!("../tests/fixtures/jolpica-alpha-2026-australia.json");
const RACE_RESULT: &str = include_str!("../tests/fixtures/jolpica-result-race.json");

struct FixtureState {
    revision: AtomicU8,
    rate_limited: AtomicBool,
    penalty_corrected: AtomicBool,
}

struct AcceptanceHarness {
    fixture: Arc<FixtureState>,
    database: Database,
    calendar_sync: CalendarSync,
    results_sync: ResultsSync,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let requested_path = std::env::args_os().nth(1).map(PathBuf::from);
    let requested_api_port = std::env::args_os()
        .nth(2)
        .map(|port| port.to_string_lossy().parse::<u16>())
        .transpose()?
        .unwrap_or(0);
    let requested_control_port = std::env::args_os()
        .nth(3)
        .map(|port| port.to_string_lossy().parse::<u16>())
        .transpose()?
        .unwrap_or(0);
    let temporary = if requested_path.is_none() {
        Some(TempDir::new()?)
    } else {
        None
    };
    let database_path = requested_path.unwrap_or_else(|| {
        temporary
            .as_ref()
            .expect("temporary directory was created")
            .path()
            .join("pitpulse.sqlite")
    });
    if let Some(parent) = database_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let database = Database::open(&database_path).await?;
    database.migrate().await?;

    let fixture = Arc::new(FixtureState {
        revision: AtomicU8::new(1),
        rate_limited: AtomicBool::new(false),
        penalty_corrected: AtomicBool::new(false),
    });
    let upstream_listener = TcpListener::bind("127.0.0.1:0").await?;
    let upstream_address = upstream_listener.local_addr()?;
    let upstream_url = format!("http://{upstream_address}");
    let upstream = Router::new()
        .route("/f1/alpha/schedules/{season}/", get(schedule))
        .route("/f1/alpha/results/{round}/{code}/", get(session_result))
        .route("/ergast/f1/{season}/{file}", get(ergast_rows))
        .with_state(fixture.clone());
    tokio::spawn(async move { axum::serve(upstream_listener, upstream).await.unwrap() });

    let client = Client::builder()
        .user_agent("PitPulse local acceptance")
        .build()?;
    let mut config = AppConfig::default();
    config.server.bind = "127.0.0.1:0".parse()?;
    config.providers.openf1_enabled = false;
    config.security.require_token = false;
    let mut state = AppState::new(config, database.clone());
    state.jolpica = JolpicaProvider::with_base_url(client.clone(), upstream_url);
    state.openf1 = OpenF1Provider::with_base_url(client, "http://127.0.0.1:1");
    state.openf1.enabled = false;

    let calendar_sync = CalendarSync {
        jolpica: state.jolpica.clone(),
        openf1: state.openf1.clone(),
        timeout: Duration::from_secs(8),
    };
    let results_sync = ResultsSync {
        jolpica: state.jolpica.clone(),
        openf1: state.openf1.clone(),
        timeout: Duration::from_secs(8),
    };
    let harness = Arc::new(AcceptanceHarness {
        fixture: fixture.clone(),
        database: database.clone(),
        calendar_sync,
        results_sync,
    });
    let reused_persisted_fixtures = fixtures_are_persisted(&database).await?;
    if !reused_persisted_fixtures {
        sync_fixtures(&harness).await?;
    }

    let api_listener = TcpListener::bind(("127.0.0.1", requested_api_port)).await?;
    let api_address = api_listener.local_addr()?;
    let api_task = tokio::spawn(async move {
        axum::serve(api_listener, server::router(state))
            .await
            .unwrap()
    });

    let control_listener = TcpListener::bind(("127.0.0.1", requested_control_port)).await?;
    let control_address = control_listener.local_addr()?;
    let controls = Router::new()
        .route("/revision/{revision}", post(set_revision))
        .route(
            "/penalty-correction/{enabled}",
            post(set_penalty_correction),
        )
        .route("/rate-limit/{enabled}", post(set_rate_limit))
        .route("/sync", post(sync_now))
        .route("/status", get(control_status))
        .with_state(harness);
    let control_task =
        tokio::spawn(async move { axum::serve(control_listener, controls).await.unwrap() });

    println!("API=http://{api_address}");
    println!("CONTROL=http://{control_address}");
    println!("DATABASE={}", database_path.display());
    println!(
        "Fixture data: {}",
        if reused_persisted_fixtures {
            "reusing persisted Australia 2026 calendar, race results, WDC/WCC and 2025 standings."
        } else {
            "synced Australia 2026 calendar, race results, WDC/WCC and 2025 standings fallback."
        }
    );
    tokio::signal::ctrl_c().await?;
    api_task.abort();
    control_task.abort();
    Ok(())
}

async fn fixtures_are_persisted(database: &Database) -> anyhow::Result<bool> {
    let (meetings, _) = database.calendar(Some(SEASON)).await?;
    let (results, _) = database.session_results("2026:1:race").await?;
    let (drivers, _) = database.driver_standings(Some(SEASON)).await?;
    let (constructors, _) = database.constructor_standings(Some(SEASON)).await?;
    let (old_season_drivers, _) = database.driver_standings(Some(SEASON - 1)).await?;
    Ok(!meetings.is_empty()
        && !results.is_empty()
        && !drivers.is_empty()
        && !constructors.is_empty()
        && !old_season_drivers.is_empty())
}

async fn sync_fixtures(harness: &AcceptanceHarness) -> anyhow::Result<()> {
    let now = harness.database.utc_now().await?;
    harness
        .database
        .sync_begin("jolpica-alpha", "calendar-2026", &now)
        .await?;
    if let Err(error) = harness
        .calendar_sync
        .sync_season_once(&harness.database, SEASON)
        .await
    {
        harness
            .database
            .sync_failed(
                "jolpica-alpha",
                "calendar-2026",
                &now,
                &now,
                &error.to_string(),
                None,
            )
            .await?;
        return Err(error.into());
    }
    harness
        .database
        .sync_succeeded("jolpica-alpha", "calendar-2026", &now, &now, None)
        .await?;
    let identities = harness
        .results_sync
        .load_identity_maps_once(&harness.database, SEASON)
        .await?;
    let (meetings, _) = harness.database.calendar(Some(SEASON)).await?;
    let meeting = meetings
        .iter()
        .find(|meeting| meeting.name == "Australian Grand Prix")
        .ok_or_else(|| anyhow::anyhow!("fixture calendar did not contain Australian Grand Prix"))?;
    let session = meeting
        .sessions
        .iter()
        .find(|session| session.session_type == SessionType::Race)
        .ok_or_else(|| anyhow::anyhow!("fixture calendar did not contain a race session"))?;
    harness
        .results_sync
        .sync_session_once(&harness.database, meeting, session, &identities)
        .await?;
    harness
        .results_sync
        .sync_driver_standings_once(&harness.database, SEASON, &identities)
        .await?;
    harness
        .results_sync
        .sync_constructor_standings_once(&harness.database, SEASON, &identities)
        .await?;
    let old_season_identities = harness
        .results_sync
        .load_identity_maps_once(&harness.database, SEASON - 1)
        .await?;
    harness
        .results_sync
        .sync_driver_standings_once(&harness.database, SEASON - 1, &old_season_identities)
        .await?;
    harness
        .results_sync
        .sync_constructor_standings_once(&harness.database, SEASON - 1, &old_season_identities)
        .await?;
    Ok(())
}

async fn schedule(State(state): State<Arc<FixtureState>>, Path(_season): Path<String>) -> Response {
    if state.rate_limited.load(Ordering::Relaxed) {
        return limited();
    }
    Json(serde_json::from_str::<Value>(CALENDAR).expect("checked-in calendar fixture is valid"))
        .into_response()
}

async fn session_result(
    State(state): State<Arc<FixtureState>>,
    Path((_round, _code)): Path<(String, String)>,
) -> Response {
    if state.rate_limited.load(Ordering::Relaxed) {
        return limited();
    }
    let mut payload: Value =
        serde_json::from_str(RACE_RESULT).expect("checked-in result fixture is valid");
    let revision = state.revision.load(Ordering::Relaxed).max(1);
    if let Some(row) = payload.pointer_mut("/data/results/0") {
        row["points"] = json!(24 + revision);
        if state.penalty_corrected.load(Ordering::Relaxed) {
            row["position"] = json!(2);
            row["position_text"] = json!("2");
            row["time"] = json!("1:25.123");
            row["gap"] = json!("+5.000");
            row["points"] = json!(18);
        }
    }
    payload["data"]["results"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "driver": {
                "id": "acceptance_fallback_driver",
                "given_name": "Fallback",
                "family_name": "Driver",
                "wikipedia": "https://example.invalid/fallback-driver"
            },
            "team": {
                "id": "acceptance_fallback_team",
                "name": "Unknown Team",
                "wikipedia": "https://example.invalid/fallback-team"
            },
            "position": null,
            "position_text": "DSQ",
            "is_classified": false,
            "time": null,
            "gap": null,
            "laps": null,
            "components": {},
            "status": "DISQUALIFIED",
            "points": 0
        }));
    Json(payload).into_response()
}

async fn ergast_rows(
    State(state): State<Arc<FixtureState>>,
    Path((_season, file)): Path<(String, String)>,
) -> Response {
    if state.rate_limited.load(Ordering::Relaxed) {
        return limited();
    }
    let driver = json!({"driverId":"leclerc","permanentNumber":"16","url":"http://en.wikipedia.org/wiki/Charles_Leclerc","givenName":"Charles","familyName":"Leclerc"});
    let constructor = json!({"constructorId":"ferrari","name":"Ferrari","url":"https://en.wikipedia.org/wiki/Scuderia_Ferrari"});
    let rows = match file.as_str() {
        "drivers.json" => json!({"DriverTable":{"Drivers":[driver]}}),
        "constructors.json" => json!({"ConstructorTable":{"Constructors":[constructor]}}),
        "driverStandings.json" => {
            json!({"StandingsTable":{"StandingsLists":[{"DriverStandings":[{"position":"1","points":"25.0","wins":"1","Driver":driver,"Constructors":[constructor]}]}]}})
        }
        "constructorStandings.json" => {
            json!({"StandingsTable":{"StandingsLists":[{"ConstructorStandings":[{"position":"1","points":"25.0","wins":"1","Constructor":constructor}]}]}})
        }
        _ => return StatusCode::NOT_FOUND.into_response(),
    };
    let mut response = json!({"MRData":{"total":"1","limit":"100","offset":"0"}});
    for (key, value) in rows.as_object().expect("fixture rows must be an object") {
        response["MRData"][key] = value.clone();
    }
    Json(response).into_response()
}

fn limited() -> Response {
    (
        StatusCode::TOO_MANY_REQUESTS,
        [(header::RETRY_AFTER, "2")],
        Json(json!({"error":"fixture rate limit"})),
    )
        .into_response()
}

async fn set_revision(
    State(harness): State<Arc<AcceptanceHarness>>,
    Path(revision): Path<u8>,
) -> Json<Value> {
    harness
        .fixture
        .revision
        .store(revision.max(1), Ordering::Relaxed);
    Json(json!({"revision": revision.max(1)}))
}

async fn set_rate_limit(
    State(harness): State<Arc<AcceptanceHarness>>,
    Path(enabled): Path<bool>,
) -> Json<Value> {
    harness
        .fixture
        .rate_limited
        .store(enabled, Ordering::Relaxed);
    Json(json!({"rateLimited": enabled}))
}

async fn set_penalty_correction(
    State(harness): State<Arc<AcceptanceHarness>>,
    Path(enabled): Path<bool>,
) -> Json<Value> {
    harness
        .fixture
        .penalty_corrected
        .store(enabled, Ordering::Relaxed);
    Json(json!({"penaltyCorrected": enabled}))
}

async fn sync_now(State(harness): State<Arc<AcceptanceHarness>>) -> Response {
    match sync_fixtures(&harness).await {
        Ok(()) => Json(json!({"status":"ok"})).into_response(),
        Err(error) => (
            StatusCode::BAD_GATEWAY,
            Json(json!({"error": error.to_string()})),
        )
            .into_response(),
    }
}

async fn control_status(State(harness): State<Arc<AcceptanceHarness>>) -> Json<Value> {
    Json(json!({
        "revision": harness.fixture.revision.load(Ordering::Relaxed),
        "rateLimited": harness.fixture.rate_limited.load(Ordering::Relaxed),
        "penaltyCorrected": harness.fixture.penalty_corrected.load(Ordering::Relaxed)
    }))
}
