use reqwest::Client;
use serde_json::Value;

use crate::{
    domain::{
        calendar::{
            Meeting, MeetingStatus, Session, SessionStatus, SessionType, meeting_id, session_id,
        },
        country::country_code,
        quality::ProviderAvailability,
    },
    error::ProviderError,
    providers::http::{
        get_json, get_json_once, get_pages, get_pages_once, shared_client, with_query,
    },
};

pub const SOURCE: &str = "jolpica-alpha";

#[derive(Debug, Clone)]
pub struct JolpicaProvider {
    pub client: Client,
    pub enabled: bool,
    pub base_url: String,
}

impl JolpicaProvider {
    pub fn new(config: &crate::config::ProvidersConfig) -> Result<Self, reqwest::Error> {
        Ok(Self {
            client: shared_client(&config.user_agent)?,
            enabled: config.jolpica_enabled,
            base_url: "https://api.jolpi.ca".to_string(),
        })
    }

    pub fn with_base_url(client: Client, base_url: impl Into<String>) -> Self {
        Self {
            client,
            enabled: true,
            base_url: base_url.into(),
        }
    }

    pub async fn raw(&self, path: &str) -> Result<Value, ProviderError> {
        get_json(&self.client, &format!("{}{}", self.base_url, path)).await
    }

    pub async fn season_calendar(&self, season: i64) -> Result<Vec<Meeting>, ProviderError> {
        let url = format!("{}/f1/alpha/schedules/{season}/", self.base_url);
        let payload = get_json(&self.client, &url).await?;
        decode_alpha_schedule(&payload)
    }

    pub async fn season_calendar_once(&self, season: i64) -> Result<Vec<Meeting>, ProviderError> {
        let url = format!("{}/f1/alpha/schedules/{season}/", self.base_url);
        decode_alpha_schedule(&get_json_once(&self.client, &url).await?)
    }

    pub async fn ergast_races(&self, season: i64) -> Result<Vec<Value>, ProviderError> {
        let url = with_query(
            &self.base_url,
            &format!("/ergast/f1/{season}/races.json"),
            &[("limit", "100".to_string())],
        )?;
        let mut races = Vec::new();
        get_pages(&self.client, &url, |page| {
            let rows = page
                .pointer("/MRData/RaceTable/Races")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default();
            races.extend(rows);
            Ok(())
        })
        .await?;
        Ok(races)
    }

    pub async fn alpha_results(&self, round_id: &str, code: &str) -> Result<Value, ProviderError> {
        let encoded = urlencoding_placeholder(round_id);
        self.raw(&format!("/f1/alpha/results/{encoded}/{code}/"))
            .await
    }

    pub async fn alpha_results_once(
        &self,
        round_id: &str,
        code: &str,
    ) -> Result<Value, ProviderError> {
        let encoded = urlencoding_placeholder(round_id);
        get_json_once(
            &self.client,
            &format!("{}/f1/alpha/results/{encoded}/{code}/", self.base_url),
        )
        .await
    }

    pub async fn ergast_rows(
        &self,
        season: i64,
        endpoint: &str,
    ) -> Result<Vec<Value>, ProviderError> {
        let url = with_query(
            &self.base_url,
            &format!("/ergast/f1/{season}/{endpoint}.json"),
            &[("limit", "100".to_string())],
        )?;
        let mut rows = Vec::new();
        get_pages(&self.client, &url, |page| {
            let collection = match endpoint {
                "drivers" => page.pointer("/MRData/DriverTable/Drivers"),
                "constructors" => page.pointer("/MRData/ConstructorTable/Constructors"),
                "driverStandings" => {
                    page.pointer("/MRData/StandingsTable/StandingsLists/0/DriverStandings")
                }
                "constructorStandings" => {
                    page.pointer("/MRData/StandingsTable/StandingsLists/0/ConstructorStandings")
                }
                _ => None,
            };
            rows.extend(
                collection
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default(),
            );
            Ok(())
        })
        .await?;
        Ok(rows)
    }

    pub async fn entity_races_once(
        &self,
        season: i64,
        kind: &str,
        id: &str,
        endpoint: &str,
    ) -> Result<Vec<Value>, ProviderError> {
        let path = if kind.is_empty() && id.is_empty() {
            format!("/ergast/f1/{season}/{endpoint}.json")
        } else {
            format!("/ergast/f1/{season}/{kind}/{id}/{endpoint}.json")
        };
        let url = with_query(&self.base_url, &path, &[("limit", "100".into())])?;
        let mut rows = Vec::new();
        get_pages_once(&self.client, &url, |page| {
            rows.extend(
                page.pointer("/MRData/RaceTable/Races")
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default(),
            );
            Ok(())
        })
        .await?;
        Ok(rows)
    }

    pub async fn ergast_rows_once(
        &self,
        season: i64,
        endpoint: &str,
    ) -> Result<Vec<Value>, ProviderError> {
        let url = with_query(
            &self.base_url,
            &format!("/ergast/f1/{season}/{endpoint}.json"),
            &[("limit", "100".to_string())],
        )?;
        let mut rows = Vec::new();
        get_pages_once(&self.client, &url, |page| {
            let collection = match endpoint {
                "drivers" => page.pointer("/MRData/DriverTable/Drivers"),
                "constructors" => page.pointer("/MRData/ConstructorTable/Constructors"),
                "driverStandings" => {
                    page.pointer("/MRData/StandingsTable/StandingsLists/0/DriverStandings")
                }
                "constructorStandings" => {
                    page.pointer("/MRData/StandingsTable/StandingsLists/0/ConstructorStandings")
                }
                _ => None,
            };
            rows.extend(
                collection
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default(),
            );
            Ok(())
        })
        .await?;
        Ok(rows)
    }
}

fn urlencoding_placeholder(value: &str) -> String {
    value
        .replace('%', "%25")
        .replace('/', "%2F")
        .replace('?', "%3F")
        .replace('#', "%23")
}

pub fn decode_alpha_schedule(payload: &Value) -> Result<Vec<Meeting>, ProviderError> {
    let events = payload
        .pointer("/data/events")
        .and_then(Value::as_array)
        .ok_or_else(|| ProviderError::MissingField {
            field: "data.events".to_string(),
        })?;
    let season = payload.pointer("/data/year").and_then(Value::as_i64);
    let mut meetings = Vec::new();
    for event in events {
        if let Some(meeting) = decode_event(event, season)? {
            meetings.push(meeting);
        }
    }
    meetings.sort_by_key(|meeting| (meeting.round.unwrap_or(i64::MAX), meeting.id.clone()));
    Ok(meetings)
}

fn decode_event(event: &Value, season: Option<i64>) -> Result<Option<Meeting>, ProviderError> {
    let round = event
        .get("round")
        .ok_or_else(|| ProviderError::MissingField {
            field: "round".to_string(),
        })?;
    let name = text(round, "name").unwrap_or_else(|| "Unnamed meeting".to_string());
    if name.to_ascii_lowercase().contains("testing") {
        return Ok(None);
    }
    let season = season.unwrap_or(2026);
    let provider_round = text(round, "id").unwrap_or_else(|| name.clone());
    let round_number = round.get("number").and_then(Value::as_i64);
    let id = meeting_id(season, round_number, &provider_round);
    let cancelled = round
        .get("is_cancelled")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let circuit = event.get("circuit").cloned().unwrap_or(Value::Null);
    let country = text(&circuit, "country").unwrap_or_default();
    let schedule = event
        .get("schedule")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let mut sessions = Vec::new();
    for item in &schedule {
        if let Some(session_type) = item
            .get("code")
            .and_then(Value::as_str)
            .and_then(SessionType::from_provider)
        {
            let start = normalize_timestamp(
                item.get("timestamp")
                    .and_then(Value::as_str)
                    .unwrap_or_default(),
            )
            .unwrap_or_else(|| "1970-01-01T00:00:00Z".to_string());
            let session_cancelled = item
                .get("sessions")
                .and_then(Value::as_array)
                .and_then(|rows| rows.first())
                .and_then(|row| row.get("is_cancelled"))
                .and_then(Value::as_bool)
                .unwrap_or(cancelled);
            let provider_session = item
                .pointer("/sessions/0/id")
                .and_then(Value::as_str)
                .map(str::to_string);
            sessions.push(Session {
                id: session_id(&id, session_type),
                meeting_id: id.clone(),
                session_type,
                start_time: start,
                end_time: None,
                status: if session_cancelled || cancelled {
                    SessionStatus::Cancelled
                } else {
                    SessionStatus::Scheduled
                },
                jolpica_session_id: provider_session,
                openf1_session_key: None,
            });
        }
    }
    let start_date = sessions
        .first()
        .map(|session| session.start_time.clone())
        .unwrap_or_else(|| "1970-01-01T00:00:00Z".to_string());
    let end_date = sessions
        .last()
        .map(|session| session.start_time.clone())
        .unwrap_or_else(|| start_date.clone());
    Ok(Some(Meeting {
        id,
        season,
        round: round_number,
        jolpica_round_id: Some(provider_round),
        name,
        country_code: country_code(
            &text(&circuit, "country_code").unwrap_or_else(|| country.clone()),
        )
        .or_else(|| country_code(&country)),
        country,
        location: text(&circuit, "locality").unwrap_or_default(),
        start_date,
        end_date,
        status: if cancelled {
            MeetingStatus::Cancelled
        } else {
            MeetingStatus::Scheduled
        },
        sessions,
        source: Some(SOURCE.to_string()),
        fetched_at: None,
        source_updated_at: event
            .pointer("/metadata/timestamp")
            .and_then(Value::as_str)
            .map(str::to_string),
        revision: None,
    }))
}

pub fn fp1_availability(payload: &Value) -> ProviderAvailability {
    let rows = payload
        .pointer("/data/results")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    if rows.is_empty() {
        return ProviderAvailability::Blocked;
    }
    let missing = rows.iter().any(|row| {
        row.get("position").is_none()
            || row
                .get("driver")
                .and_then(|driver| driver.get("id"))
                .is_none()
            || row.get("time").and_then(Value::as_str).is_none()
    });
    if missing {
        ProviderAvailability::Partial
    } else {
        ProviderAvailability::Available
    }
}

pub fn result_position(row: &Value) -> Option<i64> {
    let text = row
        .get("position_text")
        .and_then(Value::as_str)
        .unwrap_or_default();
    if text.eq_ignore_ascii_case("NC")
        || text.eq_ignore_ascii_case("DNS")
        || text.eq_ignore_ascii_case("DNF")
        || text.eq_ignore_ascii_case("DSQ")
        || row.get("is_classified") == Some(&Value::Bool(false))
    {
        return None;
    }
    row.get("position")
        .and_then(Value::as_i64)
        .filter(|value| *value > 0)
}

fn text(value: &Value, field: &str) -> Option<String> {
    value
        .get(field)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|text| !text.is_empty())
        .map(str::to_string)
}

pub fn normalize_timestamp(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        return None;
    }
    let with_zone = if value.ends_with('Z') || value.contains('+') {
        value.to_string()
    } else {
        format!("{value}Z")
    };
    let normalized = with_zone.replace("+00:00", "Z");
    chrono_free_rfc3339(&normalized).then_some(normalized)
}

fn chrono_free_rfc3339(value: &str) -> bool {
    let Some((date, time)) = value.split_once('T') else {
        return false;
    };
    let time = time.trim_end_matches('Z');
    date.len() == 10 && time.len() >= 8 && date.as_bytes().get(4) == Some(&b'-')
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_alpha_weekend_fixture_decodes_sessions_and_utc() {
        let regular: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-alpha-2026-australia.json"
        ))
        .unwrap();
        let sprint: Value = serde_json::from_str(include_str!(
            "../../tests/fixtures/jolpica-alpha-2026-china.json"
        ))
        .unwrap();
        let regular = decode_alpha_schedule(&regular).unwrap();
        let sprint = decode_alpha_schedule(&sprint).unwrap();
        assert_eq!(regular[0].country_code.as_deref(), Some("AU"));
        assert!(
            regular[0]
                .sessions
                .iter()
                .any(|session| session.session_type == SessionType::Fp3)
        );
        assert!(
            sprint[0]
                .sessions
                .iter()
                .any(|session| session.session_type == SessionType::Sprint)
        );
        assert!(
            regular[0]
                .sessions
                .iter()
                .all(|session| session.start_time.ends_with('Z'))
        );
    }

    #[test]
    fn test_missing_session_field_is_not_invented() {
        let payload = serde_json::json!({"data": {"events": [{"round": {"id": "round_x", "number": 1, "name": "Test"}, "circuit": {"country": "Unknownland"}, "schedule": [{"code": "FP1"}]}]}});
        let meetings = decode_alpha_schedule(&payload).unwrap();
        assert_eq!(meetings[0].country_code, None);
        assert_eq!(meetings[0].sessions[0].end_time, None);
    }

    #[test]
    fn test_nc_position_is_not_zero() {
        let row =
            serde_json::json!({"position": 17, "position_text": "NC", "is_classified": false});
        assert_eq!(result_position(&row), None);
    }
}
