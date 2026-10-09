use std::time::Duration;

use serde_json::Value;

use crate::{
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

    pub async fn sync_season_once(
        &self,
        database: &Database,
        season: i64,
    ) -> Result<Vec<Meeting>, ProviderError> {
        let mut meetings =
            tokio::time::timeout(self.timeout, self.jolpica.season_calendar_once(season))
                .await
                .map_err(|_| ProviderError::Transport {
                    url: "calendar".to_string(),
                    error: "request timed out".to_string(),
                })??;
        if let Ok((cached, _)) = database.calendar(Some(season)).await {
            preserve_openf1_schedule(&cached, &mut meetings);
        }
        if meetings.is_empty() {
            return Err(ProviderError::MissingField {
                field: "non-empty calendar".to_string(),
            });
        }
        meetings.sort_by_key(|meeting| (meeting.round.unwrap_or(i64::MAX), meeting.id.clone()));
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

    pub async fn supplement_openf1_once(
        &self,
        database: &Database,
        season: i64,
    ) -> Result<usize, ProviderError> {
        if !self.openf1.enabled {
            return Ok(0);
        }
        let (mut meetings, _) =
            database
                .calendar(Some(season))
                .await
                .map_err(|error| ProviderError::Decode {
                    url: "sqlite".to_string(),
                    error: error.to_string(),
                })?;
        if meetings.is_empty() {
            return Err(ProviderError::MissingField {
                field: "cached calendar before OpenF1 supplement".to_string(),
            });
        }
        let openf1_meetings = tokio::time::timeout(self.timeout, self.openf1.meetings_once(season))
            .await
            .map_err(|_| ProviderError::Transport {
                url: "openf1/meetings".to_string(),
                error: "request timed out".to_string(),
            })??;
        let openf1_sessions = tokio::time::timeout(self.timeout, self.openf1.sessions_once(season))
            .await
            .map_err(|_| ProviderError::Transport {
                url: "openf1/sessions".to_string(),
                error: "request timed out".to_string(),
            })??;
        crate::providers::openf1::supplement_calendar(
            &mut meetings,
            &openf1_meetings,
            &openf1_sessions,
        );
        let mapped_sessions = meetings
            .iter()
            .flat_map(|meeting| meeting.sessions.iter())
            .filter(|session| session.openf1_session_key.is_some())
            .count();
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
        Ok(mapped_sessions)
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

fn preserve_openf1_schedule(cached: &[Meeting], incoming: &mut [Meeting]) {
    for meeting in incoming {
        let Some(previous) = cached.iter().find(|item| item.id == meeting.id) else {
            continue;
        };
        if meeting.country_code.is_none() {
            meeting.country_code = previous.country_code.clone();
        }
        for session in &mut meeting.sessions {
            let Some(previous) = previous.sessions.iter().find(|item| item.id == session.id) else {
                continue;
            };
            if session.end_time.is_none() {
                session.end_time = previous.end_time.clone();
            }
            if session.openf1_session_key.is_none() {
                session.openf1_session_key = previous.openf1_session_key;
            }
            if previous.status.as_str() == "cancelled" && session.status.as_str() != "cancelled" {
                session.status = previous.status;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_alpha_refresh_preserves_cached_openf1_keys_and_end_times() {
        let payload: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-alpha-2026-australia.json"
        ))
        .unwrap();
        let mut cached = crate::providers::jolpica::decode_alpha_schedule(&payload).unwrap();
        let mut incoming = cached.clone();
        cached[0].sessions[0].end_time = Some("2026-10-10T12:00:00Z".into());
        cached[0].sessions[0].openf1_session_key = Some(55);
        incoming[0].sessions[0].end_time = None;
        incoming[0].sessions[0].openf1_session_key = None;

        preserve_openf1_schedule(&cached, &mut incoming);
        assert_eq!(
            incoming[0].sessions[0].end_time.as_deref(),
            Some("2026-10-10T12:00:00Z")
        );
        assert_eq!(incoming[0].sessions[0].openf1_session_key, Some(55));
    }
}
