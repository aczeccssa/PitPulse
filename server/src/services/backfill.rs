//! Offline historical import. JSON Lines on stdout can be retained as a coverage report.
use std::{future::Future, ops::RangeInclusive, time::Duration};

use anyhow::{Result, ensure};
use serde_json::json;

use crate::{
    app_state::AppState,
    domain::calendar::{MeetingStatus, SessionStatus, SessionType},
    error::ProviderError,
    services::{
        analysis,
        results_sync::{ResultsSync, SyncOutcome},
        sync::CalendarSync,
    },
};

pub fn seasons(input: &str) -> Result<RangeInclusive<i64>> {
    let (start, end) = input.split_once("..").unwrap_or((input, input));
    let (start, end) = (start.parse()?, end.parse()?);
    ensure!(
        2021 <= start && start <= end && end <= 2026,
        "expected a season or inclusive range within 2021..2026"
    );
    Ok(start..=end)
}

async fn retry<T, F: Future<Output = Result<T, ProviderError>>>(
    mut request: impl FnMut() -> F,
) -> Result<T, ProviderError> {
    for attempt in 0..3 {
        match request().await {
            Err(error) if error.is_retryable() && attempt < 2 => {
                tokio::time::sleep(
                    error
                        .retry_after()
                        .unwrap_or(Duration::from_secs(2 << attempt)),
                )
                .await;
            }
            result => return result,
        }
    }
    unreachable!()
}

pub async fn run(state: AppState, seasons: RangeInclusive<i64>, resume: bool) -> Result<()> {
    let mut failures = Vec::new();
    for season in seasons {
        if let Err(error) = import_season(&state, season, resume).await {
            eprintln!("{season}: {error}");
            println!(
                "{}",
                json!({"season":season,"quality":"stale","reason":error.to_string()})
            );
            failures.push(season);
        }
    }
    ensure!(failures.is_empty(), "incomplete imports for {failures:?}");
    Ok(())
}

async fn import_season(state: &AppState, season: i64, resume: bool) -> Result<()> {
    let db = &state.database;
    let mut failed = false;
    let mut openf1 = state.openf1.clone();
    openf1.enabled &= season >= 2023;
    let calendar = CalendarSync {
        jolpica: state.jolpica.clone(),
        openf1: openf1.clone(),
        timeout: Duration::from_secs(90),
    };
    let results = ResultsSync {
        jolpica: state.jolpica.clone(),
        openf1,
        timeout: calendar.timeout,
    };
    let mut jolpica_only = results.openf1.clone();
    jolpica_only.enabled = false;
    let primary = ResultsSync {
        jolpica: results.jolpica.clone(),
        openf1: jolpica_only,
        timeout: results.timeout,
    };
    retry(|| calendar.sync_season_once(db, season)).await?;
    if calendar.openf1.enabled
        && let Err(error) = retry(|| calendar.supplement_openf1_once(db, season)).await
    {
        eprintln!("{season} OpenF1 calendar: {error}");
    }
    let identities = retry(|| results.load_identity_maps_once(db, season)).await?;
    ensure!(
        retry(|| results.sync_driver_standings_once(db, season, &identities)).await?,
        "empty {season} driver standings"
    );
    ensure!(
        retry(|| results.sync_constructor_standings_once(db, season, &identities)).await?,
        "empty {season} constructor standings"
    );
    let race = retry(|| state.jolpica.entity_races_once(season, "", "", "results")).await?;
    let sprint = retry(|| state.jolpica.entity_races_once(season, "", "", "sprint")).await?;
    ensure!(!race.is_empty(), "empty {season} race history");
    analysis::refresh_season(state, season, Some([race, sprint])).await?;
    let now = db.utc_now().await?;
    let (mut meetings, _) = db.calendar(Some(season)).await?;
    meetings.sort_by_key(|m| m.round);
    for mut meeting in meetings {
        meeting
            .sessions
            .sort_by(|a, b| a.start_time.cmp(&b.start_time));
        for session in &meeting.sessions {
            let (existing, _) = db.session_results(&session.id).await?;
            let mut reason = None;
            let mut stale = false;
            if meeting.status == MeetingStatus::Cancelled
                || session.status == SessionStatus::Cancelled
            {
                reason = Some("cancelled".into());
            } else if session.start_time >= now {
                reason = Some("scheduled".into());
            } else if !resume
                || existing.len() < 20
                || session.session_type == SessionType::SprintQualifying
                    && existing
                        .iter()
                        .any(|row| row.q1.as_deref().is_some_and(|time| !time.contains(':')))
            {
                let mut outcome =
                    retry(|| primary.sync_session_once(db, &meeting, session, &identities)).await;
                if results.openf1.enabled
                    && session.openf1_session_key.is_some()
                    && matches!(
                        session.session_type,
                        SessionType::Fp1
                            | SessionType::Fp2
                            | SessionType::Fp3
                            | SessionType::Sprint
                            | SessionType::SprintQualifying
                    )
                    && !matches!(outcome, Ok(SyncOutcome::Stored { .. }))
                {
                    outcome =
                        retry(|| results.sync_session_once(db, &meeting, session, &identities))
                            .await;
                }
                match outcome {
                    Ok(SyncOutcome::Stored { retry_after }) => {
                        if let Some(delay) = retry_after {
                            tokio::time::sleep(delay).await;
                        }
                    }
                    Ok(SyncOutcome::NoResult) => reason = Some("no upstream results".into()),
                    Err(error) => {
                        failed |= error.is_retryable();
                        stale = !existing.is_empty();
                        reason = Some(error.to_string());
                    }
                }
            }
            let (rows, meta) = db.session_results(&session.id).await?;
            if rows.len() < 20 && reason.is_none() {
                reason = Some(format!(
                    "upstream classification has {} entries",
                    rows.len()
                ));
            }
            println!(
                "{}",
                json!({"season":season,"round":meeting.round,"meetingId":meeting.id,"sessionId":session.id,"sessionType":session.session_type,"rows":rows.len(),"quality":if rows.is_empty() {"unavailable"} else if stale {"stale"} else {meta.quality.as_str()},"reason":reason})
            );
        }
    }

    ensure!(!failed, "transient upstream gaps remain; rerun to retry");
    Ok(())
}
