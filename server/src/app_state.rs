use std::sync::Arc;

use tokio::sync::{broadcast, watch};

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
    pub live_wec: LiveState,
    pub jolpica: JolpicaProvider,
    pub openf1: OpenF1Provider,
    pub weather: crate::providers::weather::WeatherProvider,
    pub radar: crate::providers::radar::RadarProvider,
    pub radio: crate::providers::radio::RadioProvider,
    pub analysis: crate::services::analysis::AnalysisCache,
    pub(crate) dashboard: Arc<crate::api::dashboard_cache::DashboardCache>,
    #[cfg(unix)]
    pub(crate) publisher: Option<crate::publisher_bridge::PublisherClient>,
    pub refresh_queue: crate::api::refresh::RefreshQueue,
    pub refresh_events: broadcast::Sender<crate::api::refresh::DataRefreshEvent>,
}

impl AppState {
    pub fn new(config: AppConfig, database: Database) -> Self {
        let live = LiveState::new(LiveStatus::Disconnected);
        let live_wec = LiveState::new(LiveStatus::Disconnected);
        let jolpica = JolpicaProvider::new(&config.providers).expect("jolpica client");
        let openf1 = OpenF1Provider::new(&config.providers).expect("openf1 client");
        let weather = crate::providers::weather::WeatherProvider::new(&config.providers.user_agent);
        let radar = crate::providers::radar::RadarProvider::new(&config.providers.user_agent);
        let radio = crate::providers::radio::RadioProvider::new(&config.providers.user_agent);
        let (refresh_events, _) = broadcast::channel(32);
        Self {
            config: Arc::new(config),
            weather,
            radar,
            radio,
            database,
            live,
            live_wec,
            jolpica,
            openf1,
            analysis: crate::services::analysis::AnalysisCache::default(),
            dashboard: Arc::default(),
            #[cfg(unix)]
            publisher: None,
            refresh_queue: crate::api::refresh::RefreshQueue::default(),
            refresh_events,
        }
    }

    #[cfg(unix)]
    pub fn with_publisher_socket(mut self, path: &std::path::Path) -> anyhow::Result<Self> {
        self.publisher = Some(crate::publisher_bridge::PublisherClient::new(path)?);
        Ok(self)
    }

    pub(crate) async fn season_sync_status(
        &self,
        endpoint: &str,
    ) -> Result<Option<crate::api::dto::SyncStatus>, crate::error::StorageError> {
        if self.database.uses_central_season_data() {
            #[cfg(unix)]
            if let Some(publisher) = &self.publisher {
                return Ok(publisher.sync_status(endpoint).await);
            }
            return Ok(None);
        }
        self.database.sync_status("jolpica-alpha", endpoint).await
    }

    pub fn live_for(&self, series: &str) -> Option<&LiveState> {
        match series {
            "f1" => Some(&self.live),
            "wec" => Some(&self.live_wec),
            _ => None,
        }
    }
}

pub type SharedLiveSender = Arc<watch::Sender<crate::domain::live::LiveSnapshot>>;
