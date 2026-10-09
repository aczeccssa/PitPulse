use std::time::Duration;

use serde_json::Value;

use crate::{
    app_state::AppState,
    domain::calendar::Meeting,
    error::ProviderError,
    providers::{jolpica::JolpicaProvider, openf1::OpenF1Provider},
    storage::sqlite::Database,
};

#[derive(Debug, Clone, Copy)]
#[allow(dead_code)]
pub enum SyncTarget {
    Calendar,
    Results,
    Standings,
}

#[derive(Debug, Clone)]
pub struct CalendarSync {
    pub jolpica: JolpicaProvider,
    pub openf1: OpenF1Provider,
    pub timeout: Duration,
}

impl CalendarSync {
    pub async fn sync_season(
        &self,
        database: &Database,
        season: i64,
    ) -> Result<Vec<Meeting>, ProviderError> {
        let fetch = async {
            let mut meetings = self.jolpica.season_calendar(season).await?;
            if let (Ok(open_meetings), Ok(open_sessions)) = (
                self.openf1.meetings(season).await,
                self.openf1.sessions(season).await,
            ) {
                crate::providers::openf1::supplement_calendar(
                    &mut meetings,
                    &open_meetings,
                    &open_sessions,
                );
            }
            Ok::<_, ProviderError>(meetings)
        };
        let meetings = tokio::time::timeout(self.timeout, fetch)
            .await
            .map_err(|_| ProviderError::Transport {
                url: "calendar".to_string(),
                error: "request timed out".to_string(),
            })??;
        let fetched_at = database
            .utc_now()
            .await
            .map_err(|error| ProviderError::Decode {
                url: "sqlite".to_string(),
                error: error.to_string(),
            })?;
        database
            .replace_calendar(&meetings, &fetched_at)
            .await
            .map_err(|error| ProviderError::Decode {
                url: "sqlite".to_string(),
                error: error.to_string(),
            })?;
        Ok(meetings)
    }

    pub async fn sync_fixture(
        &self,
        database: &Database,
        payload: &Value,
    ) -> Result<Vec<Meeting>, ProviderError> {
        let meetings = crate::providers::jolpica::decode_alpha_schedule(payload)?;
        database
            .replace_calendar(&meetings, "2026-10-08T00:00:00Z")
            .await
            .map_err(|error| ProviderError::Decode {
                url: "sqlite".to_string(),
                error: error.to_string(),
            })?;
        Ok(meetings)
    }
}

pub fn spawn_startup_calendar_sync(state: AppState) {
    tokio::spawn(async move {
        let season = match state.database.utc_now().await {
            Ok(now) => now
                .get(..4)
                .and_then(|year| year.parse::<i64>().ok())
                .filter(|year| (1950..=9999).contains(year)),
            Err(error) => {
                tracing::warn!(%error, "cannot determine current season for startup sync");
                return;
            }
        };
        let Some(season) = season else {
            tracing::warn!("cannot determine current season for startup sync");
            return;
        };
        let sync = CalendarSync {
            jolpica: state.jolpica.clone(),
            openf1: state.openf1.clone(),
            timeout: Duration::from_secs(8),
        };
        match sync.sync_season(&state.database, season).await {
            Ok(meetings) => tracing::info!(count = meetings.len(), "calendar cache refreshed"),
            Err(error) => {
                tracing::warn!(error = %error, "calendar refresh failed; serving cached calendar")
            }
        }
        crate::services::results_sync::ResultsSync {
            jolpica: state.jolpica.clone(),
            openf1: state.openf1.clone(),
            timeout: Duration::from_secs(8),
        }
        .sync_startup(&state.database, season)
        .await;
    });
}
