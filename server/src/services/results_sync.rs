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
    pub async fn load_identity_maps_once(
        &self,
        database: &Database,
        season: i64,
    ) -> Result<IdentityMaps, ProviderError> {
        let (drivers, constructors) = tokio::join!(
            tokio::time::timeout(
                self.timeout,
                self.jolpica.ergast_rows_once(season, "drivers")
            ),
            tokio::time::timeout(
                self.timeout,
                self.jolpica.ergast_rows_once(season, "constructors")
            ),
        );
        let drivers = timed_provider_result(drivers, format!("identity/drivers/{season}"))?;
        let constructors =
            timed_provider_result(constructors, format!("identity/constructors/{season}"))?;
        let identities = IdentityMaps::from_ergast(&drivers, &constructors);
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
        database
            .store_provider_mappings(driver_mappings, constructor_mappings)
            .await
            .map_err(|error| ProviderError::Decode {
                url: "sqlite".to_string(),
                error: error.to_string(),
            })?;
        let fetched_at = database.utc_now().await.map_err(storage_error)?;
        database
            .save_identity_cache(season, &drivers, &constructors, &fetched_at)
            .await
            .map_err(storage_error)?;
        Ok(identities)
    }

    pub async fn cached_identity_maps(
        &self,
        database: &Database,
        season: i64,
    ) -> Result<Option<IdentityMaps>, ProviderError> {
        let Some((drivers, constructors)) = database
            .identity_cache(season)
            .await
            .map_err(storage_error)?
        else {
            return Ok(None);
        };
        Ok(Some(IdentityMaps::from_ergast(&drivers, &constructors)))
    }

    pub async fn sync_driver_standings_once(
        &self,
        database: &Database,
        season: i64,
        identities: &IdentityMaps,
    ) -> Result<bool, ProviderError> {
        let rows = tokio::time::timeout(
            self.timeout,
            self.jolpica.ergast_rows_once(season, "driverStandings"),
        )
        .await
        .map_err(|_| ProviderError::Transport {
            url: format!("driverStandings/{season}"),
            error: "request timed out".to_string(),
        })??;
        if rows.is_empty() {
            return Ok(false);
        }
        let fetched_at = database.utc_now().await.map_err(storage_error)?;
        let snapshot = identities.decode_driver_standings(&rows, season, &fetched_at);
        if snapshot.is_empty() {
            return Ok(false);
        }
        database
            .replace_driver_standings(snapshot)
            .await
            .map_err(storage_error)?;
        Ok(true)
    }

    pub async fn sync_constructor_standings_once(
        &self,
        database: &Database,
        season: i64,
        identities: &IdentityMaps,
    ) -> Result<bool, ProviderError> {
        let rows = tokio::time::timeout(
            self.timeout,
            self.jolpica
                .ergast_rows_once(season, "constructorStandings"),
        )
        .await
        .map_err(|_| ProviderError::Transport {
            url: format!("constructorStandings/{season}"),
            error: "request timed out".to_string(),
        })??;
        if rows.is_empty() {
            return Ok(false);
        }
        let fetched_at = database.utc_now().await.map_err(storage_error)?;
        let snapshot = identities.decode_constructor_standings(&rows, season, &fetched_at);
        if snapshot.is_empty() {
            return Ok(false);
        }
        database
            .replace_constructor_standings(snapshot)
            .await
            .map_err(storage_error)?;
        Ok(true)
    }

    pub async fn sync_session_once(
        &self,
        database: &Database,
        meeting: &Meeting,
        session: &Session,
        identities: &IdentityMaps,
    ) -> Result<SyncOutcome, ProviderError> {
        let (expected, expected_error) = if self.openf1.enabled {
            if let Some(key) = session.openf1_session_key {
                match tokio::time::timeout(self.timeout, self.openf1.drivers_once(key)).await {
                    Ok(Ok(rows)) => (rows, None),
                    Ok(Err(error)) => (Vec::new(), Some(error)),
                    Err(_) => (
                        Vec::new(),
                        Some(ProviderError::Transport {
                            url: format!("openf1/drivers/{key}"),
                            error: "request timed out".to_string(),
                        }),
                    ),
                }
            } else {
                (Vec::new(), None)
            }
        } else {
            (Vec::new(), None)
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

        let round_id = meeting.jolpica_round_id.as_deref();
        let alpha = async {
            let Some(round_id) = round_id else {
                return Err(ProviderError::MissingField {
                    field: "meeting.jolpicaRoundId".to_string(),
                });
            };
            let payload = tokio::time::timeout(
                self.timeout,
                self.jolpica
                    .alpha_results_once(round_id, alpha_code(session.session_type)),
            )
            .await
            .map_err(|_| ProviderError::Transport {
                url: format!("alpha/results/{round_id}"),
                error: "request timed out".to_string(),
            })??;
            let fetched_at = database.utc_now().await.map_err(storage_error)?;
            Ok::<_, ProviderError>(decode_alpha_candidate(
                &payload,
                identities,
                session,
                &expected,
                &fetched_at,
            ))
        };
        let openf1 = async {
            let key = session
                .openf1_session_key
                .ok_or_else(|| ProviderError::MissingField {
                    field: "session.openF1SessionKey".to_string(),
                })?;
            let rows = tokio::time::timeout(self.timeout, self.openf1.session_result_once(key))
                .await
                .map_err(|_| ProviderError::Transport {
                    url: format!("openf1/session_result/{key}"),
                    error: "request timed out".to_string(),
                })??;
            let fetched_at = database.utc_now().await.map_err(storage_error)?;
            Ok::<_, ProviderError>(identities.decode_openf1_results(
                &rows,
                &expected,
                &session.id,
                session.session_type,
                expected.len(),
                &fetched_at,
            ))
        };

        let (selected, errors) = if is_practice(session.session_type)
            && self.openf1.enabled
            && session.openf1_session_key.is_some()
        {
            tokio::pin!(alpha);
            tokio::pin!(openf1);
            let (first, alpha_first) = tokio::select! {
                biased;
                result = &mut alpha => (result.map(Some), true),
                result = &mut openf1 => (result.map(|(rows, quality)| Some((Candidate { rows, quality }, None))), false),
            };
            if first.as_ref().is_ok_and(|candidate| {
                candidate
                    .as_ref()
                    .is_some_and(|(candidate, _)| candidate.quality == DataQuality::Provisional)
            }) {
                (first.unwrap(), Vec::new())
            } else {
                let second = if alpha_first {
                    openf1
                        .await
                        .map(|(rows, quality)| Some((Candidate { rows, quality }, None)))
                } else {
                    alpha.await.map(Some)
                };
                let mut errors = expected_error.into_iter().collect::<Vec<_>>();
                let first = match first {
                    Ok(candidate) => candidate,
                    Err(error) => {
                        errors.push(error);
                        None
                    }
                };
                let second = match second {
                    Ok(candidate) => candidate,
                    Err(error) => {
                        errors.push(error);
                        None
                    }
                };
                (choose_candidates(first, second), errors)
            }
        } else {
            match alpha.await {
                Ok(candidate) => (Some(candidate), expected_error.into_iter().collect()),
                Err(error) => return Err(error),
            }
        };
        let Some((candidate, alpha_payload)) = selected else {
            return Err(errors
                .into_iter()
                .next()
                .unwrap_or_else(|| ProviderError::MissingField {
                    field: format!("results/{}", session.id),
                }));
        };
        if candidate.rows.is_empty() {
            if let Some(error) = errors.into_iter().next() {
                return Err(error);
            }
            return Ok(SyncOutcome::NoResult);
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
            .map_err(storage_error)?;
        Ok(SyncOutcome::Stored {
            retry_after: errors
                .into_iter()
                .filter_map(|error| error.retry_after())
                .max(),
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncOutcome {
    Stored { retry_after: Option<Duration> },
    NoResult,
}

fn storage_error(error: impl std::fmt::Display) -> ProviderError {
    ProviderError::Decode {
        url: "sqlite".to_string(),
        error: error.to_string(),
    }
}

fn timed_provider_result<T>(
    result: Result<Result<T, ProviderError>, tokio::time::error::Elapsed>,
    url: String,
) -> Result<T, ProviderError> {
    result.map_err(|_| ProviderError::Transport {
        url,
        error: "request timed out".to_string(),
    })?
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
