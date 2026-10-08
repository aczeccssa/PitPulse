use std::sync::Arc;

use tokio::sync::watch;

use crate::{
    config::AppConfig, domain::live::LiveStatus, services::live_state::LiveState,
    storage::sqlite::Database,
};

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<AppConfig>,
    pub database: Database,
    pub live: LiveState,
}

impl AppState {
    pub fn new(config: AppConfig, database: Database) -> Self {
        let live = LiveState::new(LiveStatus::Disconnected);
        Self {
            config: Arc::new(config),
            database,
            live,
        }
    }
}

pub type SharedLiveSender = Arc<watch::Sender<crate::domain::live::LiveSnapshot>>;
