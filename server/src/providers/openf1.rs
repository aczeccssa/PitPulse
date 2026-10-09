use std::{sync::Arc, time::Duration};

use reqwest::Client;
use serde_json::Value;
use tokio::sync::Mutex;

use crate::{
    domain::{
        calendar::{Meeting, SessionStatus, SessionType},
        country::country_code,
        quality::ProviderAvailability,
    },
    error::ProviderError,
    providers::http::{get_json_with_min_interval, shared_client, with_query},
};

pub const SOURCE: &str = "openf1";

#[derive(Debug, Clone)]
pub struct OpenF1Provider {
    pub client: Client,
    pub enabled: bool,
    pub base_url: String,
    last_request: Arc<Mutex<Option<tokio::time::Instant>>>,
}

impl OpenF1Provider {
    pub fn new(config: &crate::config::ProvidersConfig) -> Result<Self, reqwest::Error> {
        Ok(Self {
            client: shared_client(&config.user_agent)?,
            enabled: config.openf1_enabled,
            base_url: "https://api.openf1.org".to_string(),
            last_request: Arc::new(Mutex::new(None)),
        })
    }

    pub fn with_base_url(client: Client, base_url: impl Into<String>) -> Self {
        Self {
            client,
            enabled: true,
            base_url: base_url.into(),
            last_request: Arc::new(Mutex::new(None)),
        }
    }

    pub async fn raw(&self, path: &str) -> Result<Value, ProviderError> {
        self.request(&format!("{}{}", self.base_url, path)).await
    }

    async fn request(&self, url: &str) -> Result<Value, ProviderError> {
        get_json_with_min_interval(
            &self.client,
            url,
            &self.last_request,
            Duration::from_millis(350),
        )
        .await
    }

    pub async fn meetings(&self, season: i64) -> Result<Vec<Value>, ProviderError> {
        let url = with_query(
            &self.base_url,
            "/v1/meetings",
            &[("year", season.to_string())],
        )?;
        let payload = self.request(&url).await?;
        payload
            .as_array()
            .cloned()
            .ok_or_else(|| ProviderError::MissingField {
                field: "meetings".to_string(),
            })
    }

    pub async fn sessions(&self, season: i64) -> Result<Vec<Value>, ProviderError> {
        let url = with_query(
            &self.base_url,
            "/v1/sessions",
            &[("year", season.to_string())],
        )?;
        let payload = self.request(&url).await?;
        payload
            .as_array()
            .cloned()
            .ok_or_else(|| ProviderError::MissingField {
                field: "sessions".to_string(),
            })
    }

    pub async fn session_result(&self, session_key: i64) -> Result<Vec<Value>, ProviderError> {
        let url = with_query(
            &self.base_url,
            "/v1/session_result",
            &[("session_key", session_key.to_string())],
        )?;
        let payload = self.request(&url).await?;
        payload
            .as_array()
            .cloned()
            .ok_or_else(|| ProviderError::MissingField {
                field: "session_result".to_string(),
            })
    }

    pub async fn drivers(&self, session_key: i64) -> Result<Vec<Value>, ProviderError> {
        let url = with_query(
            &self.base_url,
            "/v1/drivers",
            &[("session_key", session_key.to_string())],
        )?;
        let payload = self.request(&url).await?;
        payload
            .as_array()
            .cloned()
            .ok_or_else(|| ProviderError::MissingField {
                field: "drivers".to_string(),
            })
    }
}

#[allow(dead_code)]
pub fn supplement_calendar(
    meetings: &mut [Meeting],
    openf1_meetings: &[Value],
    sessions: &[Value],
) {
    for meeting in meetings.iter_mut() {
        let Some(candidate) = openf1_meetings
            .iter()
            .find(|row| same_meeting(meeting, row))
        else {
            continue;
        };
        if meeting.country_code.is_none() {
            meeting.country_code = candidate
                .get("country_code")
                .and_then(Value::as_str)
                .and_then(country_code);
        }
        let meeting_key = candidate.get("meeting_key").and_then(Value::as_i64);
        for session in &mut meeting.sessions {
            if let Some(row) = sessions.iter().find(|row| {
                row.get("meeting_key").and_then(Value::as_i64) == meeting_key
                    && row
                        .get("session_name")
                        .and_then(Value::as_str)
                        .and_then(SessionType::from_provider)
                        == Some(session.session_type)
            }) {
                session.openf1_session_key = row.get("session_key").and_then(Value::as_i64);
                session.end_time = row
                    .get("date_end")
                    .and_then(Value::as_str)
                    .map(|value| value.replace("+00:00", "Z"));
                if row.get("is_cancelled").and_then(Value::as_bool) == Some(true) {
                    session.status = SessionStatus::Cancelled;
                }
            }
        }
    }
}

#[allow(dead_code)]
fn same_meeting(meeting: &Meeting, row: &Value) -> bool {
    let name = row
        .get("meeting_name")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let cancelled = row
        .get("is_cancelled")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    name.eq_ignore_ascii_case(&meeting.name)
        && cancelled == (meeting.status == crate::domain::calendar::MeetingStatus::Cancelled)
}

pub fn result_position(row: &Value) -> Option<i64> {
    row.get("position")
        .and_then(Value::as_i64)
        .filter(|value| *value > 0)
}

pub fn fp1_availability(rows: &[Value]) -> ProviderAvailability {
    if rows.is_empty() {
        return ProviderAvailability::Blocked;
    }
    if rows
        .iter()
        .any(|row| result_position(row).is_none() || row.get("driver_number").is_none())
    {
        ProviderAvailability::Partial
    } else {
        ProviderAvailability::Available
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_openf1_null_position_stays_null() {
        let row = serde_json::json!({"position": null, "dnf": true, "driver_number": 14});
        assert_eq!(result_position(&row), None);
    }
}
