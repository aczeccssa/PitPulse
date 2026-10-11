use std::sync::Arc;

use tokio::sync::watch;

use crate::{
    config::AppConfig,
    domain::live::LiveStatus,
    providers::{jolpica::JolpicaProvider, openf1::OpenF1Provider},
    services::live_state::LiveState,
    storage::sqlite::Database,
};

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<AppConfig>,
    pub database: Database,
    pub live: LiveState,
    pub jolpica: JolpicaProvider,
    pub openf1: OpenF1Provider,
    pub weather: crate::providers::weather::WeatherProvider,
    pub radar: crate::providers::radar::RadarProvider,
    pub radio: crate::providers::radio::RadioProvider,
    pub analysis: crate::services::analysis::AnalysisCache,
}

impl AppState {
    pub fn new(config: AppConfig, database: Database) -> Self {
        let live = LiveState::new(LiveStatus::Disconnected);
        let jolpica = JolpicaProvider::new(&config.providers).expect("jolpica client");
        let openf1 = OpenF1Provider::new(&config.providers).expect("openf1 client");
        let weather = crate::providers::weather::WeatherProvider::new(&config.providers.user_agent);
        let radar = crate::providers::radar::RadarProvider::new(&config.providers.user_agent);
        let radio = crate::providers::radio::RadioProvider::new(&config.providers.user_agent);
        Self {
            config: Arc::new(config),
            weather,
            radar,
            radio,
            database,
            live,
            jolpica,
            openf1,
            analysis: crate::services::analysis::AnalysisCache::default(),
        }
    }
}

pub type SharedLiveSender = Arc<watch::Sender<crate::domain::live::LiveSnapshot>>;
