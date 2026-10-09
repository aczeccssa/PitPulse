use std::time::Duration;

use serde_json::Value;

use crate::{
    domain::{
        calendar::{Meeting, Session, SessionType},
        quality::DataQuality,
        results::SessionResult,
    },
    error::ProviderError,
    providers::{jolpica::JolpicaProvider, openf1::OpenF1Provider, results::IdentityMaps},
    storage::sqlite::Database,
};

type ProviderMappings = Vec<(String, String, String)>;

pub struct ResultsSync {
    pub jolpica: JolpicaProvider,
    pub openf1: OpenF1Provider,
    pub timeout: Duration,
}

struct Candidate {
    rows: Vec<SessionResult>,
    quality: DataQuality,
}

impl ResultsSync {
    pub async fn sync_startup(&self, database: &Database, season: i64) {
        if !self.jolpica.enabled {
            return;
        }
        let (driver_rows, constructor_rows) = tokio::join!(
            tokio::time::timeout(self.timeout, self.jolpica.ergast_rows(season, "drivers")),
            tokio::time::timeout(
                self.timeout,
                self.jolpica.ergast_rows(season, "constructors")
            ),
        );
        let drivers = provider_rows(driver_rows, "drivers").unwrap_or_default();
        let constructors = provider_rows(constructor_rows, "constructors").unwrap_or_default();
        let identities = IdentityMaps::from_ergast(&drivers, &constructors);
        let (driver_standings, constructor_standings) = tokio::join!(
            tokio::time::timeout(
                self.timeout,
                self.jolpica.ergast_rows(season, "driverStandings")
            ),
            tokio::time::timeout(
                self.timeout,
                self.jolpica.ergast_rows(season, "constructorStandings")
            ),
        );
        if let Some(rows) = provider_rows(driver_standings, "driverStandings") {
            match database.utc_now().await {
                Ok(fetched_at) => {
                    let snapshot = identities.decode_driver_standings(&rows, season, &fetched_at);
                    if !snapshot.is_empty()
                        && let Err(error) = database.replace_driver_standings(snapshot).await
                    {
                        tracing::warn!(%error, "driver standings persistence failed");
                    }
                }
                Err(error) => tracing::warn!(%error, "driver standings fetch time unavailable"),
            }
        }
        if let Some(rows) = provider_rows(constructor_standings, "constructorStandings") {
            match database.utc_now().await {
                Ok(fetched_at) => {
                    let snapshot =
                        identities.decode_constructor_standings(&rows, season, &fetched_at);
                    if !snapshot.is_empty()
                        && let Err(error) = database.replace_constructor_standings(snapshot).await
                    {
                        tracing::warn!(%error, "constructor standings persistence failed");
                    }
                }
                Err(error) => {
                    tracing::warn!(%error, "constructor standings fetch time unavailable")
                }
            }
        }
        let driver_mappings = drivers
            .iter()
            .filter_map(|row| {
                let id = row["driverId"].as_str()?;
                Some(("jolpica-ergast".to_string(), id.to_string(), id.to_string()))
            })
            .collect();
        let constructor_mappings = constructors
            .iter()
            .filter_map(|row| {
                let id = row["constructorId"].as_str()?;
                Some(("jolpica-ergast".to_string(), id.to_string(), id.to_string()))
            })
            .collect();
        if let Err(error) = database
            .store_provider_mappings(driver_mappings, constructor_mappings)
            .await
        {
            tracing::warn!(%error, "provider identity mappings could not be stored");
        }

        let now = match database.utc_now().await {
            Ok(now) => now,
            Err(error) => {
                tracing::warn!(%error, "cannot read UTC time for result sync");
                return;
            }
        };
        let meetings = match database.calendar(Some(season)).await {
            Ok((meetings, _)) => meetings,
            Err(error) => {
                tracing::warn!(%error, "cannot read cached calendar for result sync");
                return;
            }
        };
        let meeting = meetings
            .into_iter()
            .filter(|meeting| meeting.status.as_str() != "cancelled")
            .filter_map(|meeting| {
                let end = meeting
                    .sessions
                    .iter()
                    .find(|session| session.session_type == SessionType::Race)
                    .and_then(|session| session.end_time.as_deref())?;
                (end <= now.as_str()).then_some((end.to_string(), meeting))
            })
            .max_by(|a, b| a.0.cmp(&b.0))
            .map(|(_, meeting)| meeting);
        let Some(meeting) = meeting else {
            tracing::info!(
                season,
                "no completed meeting with a verified session end time"
            );
            return;
        };
        for session in meeting.sessions.iter().filter(|session| {
            session.status.as_str() != "cancelled"
                && session
                    .end_time
                    .as_deref()
                    .is_some_and(|end| end <= now.as_str())
        }) {
            if let Err(error) = self
                .sync_session(database, &meeting, session, &identities)
                .await
            {
                tracing::warn!(session_id = %session.id, %error, "session result sync failed; preserving cache");
            }
        }
    }

    async fn sync_session(
        &self,
        database: &Database,
        meeting: &Meeting,
        session: &Session,
        identities: &IdentityMaps,
    ) -> Result<(), ProviderError> {
        let Some(round_id) = meeting.jolpica_round_id.as_deref() else {
            return Ok(());
        };
        let expected = if self.openf1.enabled {
            if let Some(key) = session.openf1_session_key {
                tokio::time::timeout(self.timeout, self.openf1.drivers(key))
                    .await
                    .ok()
                    .and_then(Result::ok)
                    .unwrap_or_default()
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };
        let openf1_driver_mappings = expected
            .iter()
            .filter_map(|driver| {
                let number = driver["driver_number"].as_i64()?;
                let canonical = identities.driver_for_number(number)?;
                Some((
                    "openf1".to_string(),
                    number.to_string(),
                    canonical.to_string(),
                ))
            })
            .collect::<Vec<_>>();
        let openf1_constructor_mappings = expected
            .iter()
            .filter_map(|driver| {
                let name = driver["team_name"].as_str()?;
                let canonical = identities.constructor_for_name(name)?;
                Some((
                    "openf1".to_string(),
                    name.to_string(),
                    canonical.to_string(),
                ))
            })
            .collect::<Vec<_>>();
        if let Err(error) = database
            .store_provider_mappings(openf1_driver_mappings, openf1_constructor_mappings)
            .await
        {
            tracing::warn!(%error, "OpenF1 identity mappings could not be stored");
        }

        let alpha = async {
            let payload = tokio::time::timeout(
                self.timeout,
                self.jolpica
                    .alpha_results(round_id, alpha_code(session.session_type)),
            )
            .await
            .ok()
            .and_then(Result::ok)?;
            let fetched_at = database.utc_now().await.ok()?;
            Some(decode_alpha_candidate(
                &payload,
                identities,
                session,
                &expected,
                &fetched_at,
            ))
        };
        let openf1 = async {
            let key = session.openf1_session_key?;
            let rows = tokio::time::timeout(self.timeout, self.openf1.session_result(key))
                .await
                .ok()
                .and_then(Result::ok)?;
            let fetched_at = database.utc_now().await.ok()?;
            Some(identities.decode_openf1_results(
                &rows,
                &expected,
                &session.id,
                session.session_type,
                expected.len(),
                &fetched_at,
            ))
        };

        let selected = if is_practice(session.session_type)
            && self.openf1.enabled
            && session.openf1_session_key.is_some()
        {
            tokio::pin!(alpha);
            tokio::pin!(openf1);
            let (first, alpha_first) = tokio::select! {
                biased;
                result = &mut alpha => (result, true),
                result = &mut openf1 => (result.map(|(rows, quality)| (Candidate { rows, quality }, None)), false),
            };
            if first
                .as_ref()
                .is_some_and(|(candidate, _)| candidate.quality == DataQuality::Provisional)
            {
                first
            } else {
                let second = if alpha_first {
                    openf1
                        .await
                        .map(|(rows, quality)| (Candidate { rows, quality }, None))
                } else {
                    alpha.await
                };
                choose_candidates(first, second)
            }
        } else {
            alpha.await
        };
        let Some((candidate, alpha_payload)) = selected else {
            return Ok(());
        };
        if candidate.rows.is_empty() {
            return Ok(());
        }
        if let Some(payload) = alpha_payload {
            let (drivers, constructors) = alpha_mappings(&payload, identities);
            if let Err(error) = database
                .store_provider_mappings(drivers, constructors)
                .await
            {
                tracing::warn!(%error, "Alpha identity mappings could not be stored");
            }
        }
        database
            .replace_session_results(candidate.rows, candidate.quality.as_str())
            .await
            .map_err(|error| ProviderError::Decode {
                url: "sqlite".to_string(),
                error: error.to_string(),
            })?;
        Ok(())
    }
}

fn decode_alpha_candidate(
    payload: &Value,
    identities: &IdentityMaps,
    session: &Session,
    expected: &[Value],
    fetched_at: &str,
) -> (Candidate, Option<Value>) {
    let (rows, quality) = identities.decode_alpha_results(
        payload,
        &session.id,
        session.session_type,
        expected,
        fetched_at,
    );
    (Candidate { rows, quality }, Some(payload.clone()))
}

fn alpha_mappings(
    payload: &Value,
    identities: &IdentityMaps,
) -> (ProviderMappings, ProviderMappings) {
    let mut drivers = Vec::new();
    let mut constructors = Vec::new();
    for row in payload
        .pointer("/data/results")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        if let (Some(raw), Some(url)) = (
            row["driver"]["id"].as_str(),
            row["driver"]["wikipedia"].as_str(),
        ) && let Some(canonical) = identities.driver_for_wikipedia(url)
        {
            drivers.push(("jolpica-alpha".into(), raw.into(), canonical.into()));
        }
        if let (Some(raw), Some(url)) = (
            row["team"]["id"].as_str(),
            row["team"]["wikipedia"].as_str(),
        ) && let Some(canonical) = identities.constructor_for_wikipedia(url)
        {
            constructors.push(("jolpica-alpha".into(), raw.into(), canonical.into()));
        }
    }
    (drivers, constructors)
}

fn choose_candidates(
    a: Option<(Candidate, Option<Value>)>,
    b: Option<(Candidate, Option<Value>)>,
) -> Option<(Candidate, Option<Value>)> {
    match (a, b) {
        (Some(a), Some(b)) => {
            if a.0.quality == DataQuality::Provisional && b.0.quality != DataQuality::Provisional {
                Some(a)
            } else if b.0.quality == DataQuality::Provisional
                && a.0.quality != DataQuality::Provisional
            {
                Some(b)
            } else if mapped_count(&a.0.rows) > mapped_count(&b.0.rows) {
                Some(a)
            } else if mapped_count(&b.0.rows) > mapped_count(&a.0.rows) {
                Some(b)
            } else if a.1.is_some() {
                Some(a)
            } else {
                Some(b)
            }
        }
        (Some(one), None) | (None, Some(one)) => Some(one),
        (None, None) => None,
    }
}

fn mapped_count(rows: &[SessionResult]) -> usize {
    rows.iter()
        .filter(|row| !row.driver_id.contains(':') && !row.constructor_id.contains(':'))
        .count()
}

fn provider_rows(
    result: Result<Result<Vec<Value>, ProviderError>, tokio::time::error::Elapsed>,
    endpoint: &str,
) -> Option<Vec<Value>> {
    match result {
        Ok(Ok(rows)) => Some(rows),
        Ok(Err(error)) => {
            tracing::warn!(endpoint, %error, "provider lookup failed");
            None
        }
        Err(_) => {
            tracing::warn!(endpoint, "provider lookup timed out");
            None
        }
    }
}

fn is_practice(session: SessionType) -> bool {
    matches!(
        session,
        SessionType::Fp1 | SessionType::Fp2 | SessionType::Fp3
    )
}

fn alpha_code(session: SessionType) -> &'static str {
    match session {
        SessionType::Fp1 => "FP1",
        SessionType::Fp2 => "FP2",
        SessionType::Fp3 => "FP3",
        SessionType::SprintQualifying => "SQ",
        SessionType::Sprint => "SR",
        SessionType::Qualifying => "Q",
        SessionType::Race => "R",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(driver_id: &str, constructor_id: &str, source: &str) -> SessionResult {
        SessionResult {
            session_id: "2026:1:fp1".into(),
            position: Some(1),
            classification: "classified".into(),
            driver_id: driver_id.into(),
            driver_name: "Driver".into(),
            constructor_id: constructor_id.into(),
            team: "Team".into(),
            time: None,
            best_lap: None,
            q1: None,
            q2: None,
            q3: None,
            race_time: None,
            gap: None,
            laps: None,
            points: None,
            source: source.into(),
            source_updated_at: None,
            fetched_at: "2026-10-09T00:00:00Z".into(),
            revision: 1,
            quality: "partial".into(),
        }
    }

    fn candidate(rows: Vec<SessionResult>, quality: DataQuality) -> Candidate {
        Candidate { rows, quality }
    }

    #[test]
    fn test_practice_candidates_prefer_complete_then_coverage_then_alpha_tie() {
        let alpha = candidate(
            vec![row(
                "jolpica-alpha:1",
                "jolpica-alpha:team",
                "jolpica-alpha",
            )],
            DataQuality::Partial,
        );
        let openf1 = candidate(
            vec![
                row("driver-a", "team-a", "openf1"),
                row("driver-b", "team-b", "openf1"),
            ],
            DataQuality::Partial,
        );
        let selected = choose_candidates(
            Some((alpha, Some(serde_json::json!({"data": {"results": []}})))),
            Some((openf1, None)),
        )
        .unwrap();
        assert_eq!(selected.0.rows[0].source, "openf1");

        let alpha = candidate(
            vec![row("driver-a", "team-a", "jolpica-alpha")],
            DataQuality::Partial,
        );
        let openf1 = candidate(
            vec![row("driver-a", "team-a", "openf1")],
            DataQuality::Partial,
        );
        let selected = choose_candidates(
            Some((alpha, Some(serde_json::json!({"data": {"results": []}})))),
            Some((openf1, None)),
        )
        .unwrap();
        assert_eq!(selected.0.rows[0].source, "jolpica-alpha");

        let alpha = candidate(vec![row("a", "a", "jolpica-alpha")], DataQuality::Partial);
        let openf1 = candidate(vec![row("b", "b", "openf1")], DataQuality::Provisional);
        let selected = choose_candidates(
            Some((alpha, Some(serde_json::json!({"data": {"results": []}})))),
            Some((openf1, None)),
        )
        .unwrap();
        assert_eq!(selected.0.quality, DataQuality::Provisional);
        assert_eq!(selected.0.rows[0].source, "openf1");
    }
}
