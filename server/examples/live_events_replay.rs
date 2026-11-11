use std::{
    fs::File,
    io::BufReader,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

use anyhow::{Context, ensure};
use flate2::read::GzDecoder;
use pitpulse_server::{
    app_state::AppState,
    config::AppConfig,
    domain::live::{LiveSnapshot, LiveSourceMode, LiveStatus},
    server,
    services::live_state::LiveState,
    storage::sqlite::Database,
};
use serde::Deserialize;
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

const DEFAULT_F1_FILE: &str = "f1-sao-paulo-2026.json.gz";
const DEFAULT_WEC_FILE: &str = "wec-monza-2026.json.gz";
const DEFAULT_HOLD_SECONDS: u64 = 10;

#[derive(Debug, Deserialize)]
struct ReplayFile {
    #[serde(default)]
    meta: serde_json::Value,
    frames: Vec<ReplayFrame>,
}

#[derive(Debug, Deserialize)]
struct ReplayFrame {
    t: f64,
    // Kept as raw JSON so startup only parses the file once; the typed snapshot
    // is decoded at 1 Hz when it is published (a debug-build LiveSnapshot is
    // large enough that eager decoding delays the first frame by minutes).
    snapshot: serde_json::Value,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    install_tracing();

    let mut config = AppConfig::load(None).context("load local server settings")?;
    config.providers.jolpica_enabled = false;
    config.providers.openf1_enabled = false;
    config.providers.f1_live_enabled = false;
    config.providers.wec_live_enabled = false;
    config.database.path = std::env::temp_dir().join(format!(
        "pitpulse-live-events-replay-{}.sqlite",
        std::process::id()
    ));

    let database = Database::open(&config.database.path).await?;
    database.migrate().await?;
    let state = AppState::new(config, database);

    let directory = replay_directory();
    let speed = std::env::var("F1_COMPANION_REPLAY_SPEED")
        .ok()
        .and_then(|value| value.parse::<f64>().ok())
        .filter(|value| value.is_finite() && *value > 0.0)
        .unwrap_or(1.0);
    let hold = std::env::var("F1_COMPANION_REPLAY_HOLD_SECONDS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .unwrap_or(DEFAULT_HOLD_SECONDS);
    let f1_path = replay_path(&directory, "F1_COMPANION_REPLAY_F1_FILE", DEFAULT_F1_FILE);
    let wec_path = replay_path(&directory, "F1_COMPANION_REPLAY_WEC_FILE", DEFAULT_WEC_FILE);
    ensure!(
        f1_path.is_file(),
        "missing F1 replay {}; run python3 scripts/prepare-live-replay.py",
        f1_path.display()
    );
    ensure!(
        wec_path.is_file(),
        "missing WEC replay {}; run python3 scripts/prepare-live-replay.py",
        wec_path.display()
    );

    let f1 = tokio::spawn(supervised(
        "f1",
        state.clone(),
        state.live.clone(),
        f1_path,
        speed,
        hold,
    ));
    let wec = tokio::spawn(supervised(
        "wec",
        state.clone(),
        state.live_wec.clone(),
        wec_path,
        speed,
        hold,
    ));

    tracing::info!(
        address = %state.config.server.bind,
        speed,
        hold_seconds = hold,
        "starting dual-series recorded Live replay"
    );
    let result = server::serve(state).await;
    f1.abort();
    wec.abort();
    let _ = f1.await;
    let _ = wec.await;
    result.context("replay server stopped unexpectedly")
}

async fn supervised(
    label: &'static str,
    state: AppState,
    live: LiveState,
    path: PathBuf,
    speed: f64,
    hold_seconds: u64,
) {
    if let Err(error) = replay(state, live, path, speed, hold_seconds).await {
        tracing::error!(series = label, error = %error, "recorded replay stopped");
    }
}

async fn replay(
    state: AppState,
    live: LiveState,
    path: PathBuf,
    speed: f64,
    hold_seconds: u64,
) -> anyhow::Result<()> {
    let replay = tokio::task::spawn_blocking(move || load(&path)).await??;
    ensure!(!replay.frames.is_empty(), "replay file has no frames");
    serde_json::from_value::<LiveSnapshot>(replay.frames[0].snapshot.clone())
        .context("decode first replay frame")?;
    let series = replay
        .meta
        .get("series")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("replay")
        .to_string();
    let duration = replay.frames.last().map_or(0.0, |frame| frame.t);
    loop {
        let started = Instant::now();
        for frame in &replay.frames {
            let target = (frame.t / speed).max(0.0);
            let elapsed = started.elapsed().as_secs_f64();
            if target > elapsed + 0.001 {
                tokio::time::sleep(Duration::from_secs_f64(target - elapsed)).await;
            }
            publish(&state, &live, &frame.snapshot, &series).await?;
        }
        tracing::info!(
            %series,
            source_seconds = duration,
            hold_seconds,
            "recorded replay finished; holding the final classification before looping"
        );
        for _ in 0..hold_seconds {
            if let Some(frame) = replay.frames.last() {
                publish(&state, &live, &frame.snapshot, &series).await?;
            }
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
        tracing::info!(%series, "looping recorded replay from the start");
    }
}

fn load(path: &Path) -> anyhow::Result<ReplayFile> {
    let file = File::open(path).with_context(|| format!("open replay {}", path.display()))?;
    let reader = BufReader::new(file);
    if path
        .extension()
        .is_some_and(|extension| extension.eq_ignore_ascii_case("gz"))
    {
        serde_json::from_reader(GzDecoder::new(reader))
            .with_context(|| format!("decode replay {}", path.display()))
    } else {
        serde_json::from_reader(reader).with_context(|| format!("decode replay {}", path.display()))
    }
}

async fn publish(
    state: &AppState,
    live: &LiveState,
    source: &serde_json::Value,
    series: &str,
) -> anyhow::Result<()> {
    let now = state.database.utc_now().await?;
    let mut snapshot: LiveSnapshot =
        serde_json::from_value(source.clone()).context("decode replay frame")?;
    snapshot.source_status = LiveStatus::Connected;
    snapshot.source_mode = LiveSourceMode::Replay;
    snapshot.status_reason = Some(format!("recorded_replay:{series}"));
    snapshot.updated_at = Some(now.clone());
    snapshot.last_transport_at = Some(now);
    live.publish(snapshot, true);
    Ok(())
}

fn replay_directory() -> PathBuf {
    std::env::var_os("F1_COMPANION_REPLAY_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let project = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .map(Path::to_path_buf)
                .unwrap_or_default();
            project.join("server/target/replay-data")
        })
}

fn replay_path(directory: &Path, variable: &str, default: &str) -> PathBuf {
    std::env::var_os(variable)
        .map(PathBuf::from)
        .unwrap_or_else(|| directory.join(default))
}

fn install_tracing() {
    tracing_subscriber::registry()
        .with(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,pitpulse_server=info")),
        )
        .with(tracing_subscriber::fmt::layer().with_target(false))
        .init();
}
