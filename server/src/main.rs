use std::path::PathBuf;

use anyhow::Context;
use pitpulse_server::{
    app_state::AppState, config::AppConfig, scheduler, server, storage::sqlite::Database,
};
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    install_tracing()?;

    let config_path = std::env::var("F1_COMPANION_CONFIG").ok().map(PathBuf::from);
    let config = AppConfig::load(config_path.as_deref())?;
    tracing::info!(bind = %config.server.bind, db = %config.database.path.display(), "starting PitPulse");

    let database = Database::open(&config.database.path).await?;
    database.migrate().await?;

    let state = AppState::new(config, database);
    scheduler::spawn(state.clone());

    server::serve(state)
        .await
        .context("server stopped unexpectedly")?;
    Ok(())
}

fn install_tracing() -> anyhow::Result<()> {
    let fmt_layer = tracing_subscriber::fmt::layer()
        .with_target(false)
        .with_thread_ids(false);
    tracing_subscriber::registry()
        .with(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .with(fmt_layer)
        .init();
    Ok(())
}
