use std::path::PathBuf;

use anyhow::Context;
use pitpulse_server::{
    app_state::AppState, config::AppConfig, scheduler, server, storage::sqlite::Database,
};
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    install_tracing()?;

    let args: Vec<_> = std::env::args().skip(1).collect();
    if args.first().is_some_and(|arg| arg == "season-data") {
        return season_data(&args[1..]).await;
    }
    let config_path = std::env::var("F1_COMPANION_CONFIG").ok().map(PathBuf::from);
    let config = AppConfig::load(config_path.as_deref())?;
    let (args, resume) = match args.strip_suffix(&[String::from("--resume")]) {
        Some(prefix) if !prefix.is_empty() => (prefix, true),
        _ => (args.as_slice(), false),
    };
    let seasons = match args {
        [] => None,
        [command, option, range] if command == "backfill" && option == "--season" => {
            Some(pitpulse_server::services::backfill::seasons(range)?)
        }
        _ => anyhow::bail!("usage: pitpulse-server [backfill --season YEAR[..YEAR] [--resume]]"),
    };
    tracing::info!(bind = %config.server.bind, db = %config.database.path.display(), "starting PitPulse");

    let database = Database::open(&config.database.path).await?;
    database.migrate().await?;
    let database = match std::env::var("PITPULSE_SEASON_READ_DATABASE_URL") {
        Ok(url) => {
            use pitpulse_server::storage::postgres::{DEFAULT_SCHEMA, Postgres};
            let schema = std::env::var("PITPULSE_SEASON_SCHEMA")
                .unwrap_or_else(|_| DEFAULT_SCHEMA.to_owned());
            database.with_season_reader(Postgres::new(&url, &schema, true)?)
        }
        Err(std::env::VarError::NotPresent) => database,
        Err(_) => anyhow::bail!("PITPULSE_SEASON_READ_DATABASE_URL is not valid UTF-8"),
    };
    if seasons.is_some() && database.uses_central_season_data() {
        anyhow::bail!("local backfill is disabled with central season data");
    }

    let state = AppState::new(config, database);
    if let Some(seasons) = seasons {
        return pitpulse_server::services::backfill::run(state, seasons, resume).await;
    }
    let background = scheduler::spawn(state.clone());

    let result = server::serve(state).await;
    background.shutdown().await;
    result.context("server stopped unexpectedly")
}

async fn season_data(args: &[String]) -> anyhow::Result<()> {
    use pitpulse_server::storage::postgres::{DEFAULT_SCHEMA, Postgres};

    let schema =
        std::env::var("PITPULSE_SEASON_SCHEMA").unwrap_or_else(|_| DEFAULT_SCHEMA.to_owned());
    let database = || -> anyhow::Result<Postgres> {
        let url = std::env::var("PITPULSE_SEASON_WRITE_DATABASE_URL")
            .context("PITPULSE_SEASON_WRITE_DATABASE_URL must be set")?;
        Ok(Postgres::new(&url, &schema, false)?)
    };
    match args {
        [command] if command == "migrate" => {
            let role = std::env::var("PITPULSE_SEASON_READER_ROLE").ok();
            database()?.migrate(role.as_deref()).await?;
            println!("Season data schema v1 ready");
        }
        [command, source] if matches!(command.as_str(), "import" | "verify") => {
            let report = database()?
                .import_sqlite(std::path::Path::new(source), command == "verify")
                .await?;
            println!("{}", serde_json::to_string_pretty(&report)?);
        }
        _ => anyhow::bail!(
            "usage: pitpulse-server season-data [migrate | import SQLITE_PATH | verify SQLITE_PATH]"
        ),
    }
    Ok(())
}

fn install_tracing() -> anyhow::Result<()> {
    let fmt_layer = tracing_subscriber::fmt::layer()
        .with_writer(std::io::stderr)
        .with_target(false)
        .with_thread_ids(false);
    tracing_subscriber::registry()
        .with(
            EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("info,signalr_client=off")),
        )
        .with(fmt_layer)
        .init();
    Ok(())
}
