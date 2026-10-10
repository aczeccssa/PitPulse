use std::time::{Duration, SystemTime, UNIX_EPOCH};

use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;

use crate::{
    app_state::AppState,
    domain::calendar::{Meeting, Session, SessionType},
    domain::live::{LiveSourceMode, LiveStatus},
    error::ProviderError,
    providers::f1_live::{
        client::{F1LiveClient, F1LiveError, F1LiveUpdate},
        reducer::LiveTopicReducer,
    },
    services::{
        results_sync::{ResultsSync, SyncOutcome},
        sync::CalendarSync,
    },
};

const PROVIDER: &str = "jolpica-alpha";
const OPENF1_PROVIDER: &str = "openf1";
const TICK: Duration = Duration::from_secs(30);
const SIX_HOURS: Duration = Duration::from_secs(6 * 60 * 60);

pub struct SchedulerTasks(Vec<JoinHandle<()>>);

impl SchedulerTasks {
    pub async fn shutdown(self) {
        for task in &self.0 {
            task.abort();
        }
        for task in self.0 {
            let _ = task.await;
        }
    }
}

pub fn spawn(state: AppState) -> SchedulerTasks {
    let scheduler_state = state.clone();
    let scheduler = tokio::spawn(async move {
        let sync = ResultsSync {
            jolpica: scheduler_state.jolpica.clone(),
            openf1: scheduler_state.openf1.clone(),
            timeout: Duration::from_secs(8),
        };
        let mut identities = if let Some(season) = current_season(&scheduler_state).await {
            sync.cached_identity_maps(&scheduler_state.database, season)
                .await
                .ok()
                .flatten()
        } else {
            None
        };
        let mut interval = tokio::time::interval(TICK);
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            interval.tick().await;
            if let Err(error) = sync_cycle(&scheduler_state, &sync, &mut identities).await {
                tracing::warn!(%error, "scheduled sync cycle failed");
            }
        }
    });
    let analysis = tokio::spawn(crate::services::analysis::preload(state.clone()));
    let live = tokio::spawn(run_live_supervisor(state));
    SchedulerTasks(vec![scheduler, live, analysis])
}

async fn run_live_supervisor(state: AppState) {
    if !state.config.providers.f1_live_enabled {
        state
            .live
            .reset(LiveStatus::Disconnected, LiveSourceMode::Live, "disabled");
        return;
    }

    let client = F1LiveClient::new(
        true,
        "https://livetiming.formula1.com/signalrcore".to_string(),
    );
    let mut failures = 0usize;
    loop {
        state
            .live
            .reset(LiveStatus::Disconnected, LiveSourceMode::Live, "connecting");
        let mut reducer = LiveTopicReducer::default();
        let (update_tx, mut update_rx) = mpsc::channel(256);
        let (stop_tx, stop_rx) = oneshot::channel();
        let access_token = state.config.providers.f1_live_access_token.clone();
        let connection = client.run(access_token, update_tx, stop_rx);
        tokio::pin!(connection);
        let mut freshness = tokio::time::interval(Duration::from_secs(1));
        freshness.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        freshness.tick().await;

        let result = loop {
            tokio::select! {
                update = update_rx.recv() => match update {
                    Some(update) => {
                        apply_live_update(&state, &mut reducer, update).await;
                        if state.live.current().source_status == LiveStatus::Connected {
                            if failures > 0 {
                                tracing::info!(session_id = ?state.live.current().session_id, "F1 Live subscription recovered");
                            }
                            failures = 0;
                        }
                    },
                    None => break Err(F1LiveError::ChannelClosed),
                },
                result = &mut connection => break result,
                _ = freshness.tick() => {
                    let stale_after = Duration::from_secs(state.config.live.stale_after_seconds.max(1));
                    let disconnect_after = Duration::from_secs(
                        state.config.live.disconnect_after_seconds.max(state.config.live.stale_after_seconds.saturating_add(1)),
                    );
                    if state.live.check_freshness(stale_after, disconnect_after) {
                        let _ = stop_tx.send(());
                        break Err(F1LiveError::Disconnected);
                    }
                }
            }
        };

        let error = result.err().unwrap_or(F1LiveError::Disconnected);
        let reason = if matches!(error, F1LiveError::Disconnected)
            && state.live.current().status_reason.as_deref() == Some("upstream_silent")
        {
            "upstream_silent"
        } else {
            error.reason()
        };
        state.live.mark_status(LiveStatus::Disconnected, reason);
        if matches!(error, F1LiveError::Unauthorized | F1LiveError::Forbidden) {
            failures = 0;
            tokio::time::sleep(Duration::from_secs(300)).await;
            continue;
        }
        let delay = [5, 15, 30, 60, 300][failures.min(4)];
        failures = failures.saturating_add(1);
        tracing::warn!(reason, retry_after_seconds = delay, "F1 Live disconnected");
        tokio::time::sleep(Duration::from_secs(delay)).await;
    }
}

async fn apply_live_update(state: &AppState, reducer: &mut LiveTopicReducer, update: F1LiveUpdate) {
    let Ok(received_at) = state.database.utc_now().await else {
        tracing::warn!("failed to timestamp F1 Live update");
        return;
    };
    let value = match update {
        F1LiveUpdate::InitialSnapshot(value) | F1LiveUpdate::Feed(value) => value,
        F1LiveUpdate::TransportHeartbeat => {
            let mut snapshot = state.live.current().clone();
            snapshot.last_transport_at = Some(received_at);
            state.live.publish(snapshot, false);
            return;
        }
    };
    let Some(reduced) = reducer.apply_batch(&value, &received_at) else {
        return;
    };
    let data_updated = reduced.data_updated;
    let mut snapshot = reduced.snapshot;
    if !data_updated {
        let current = state.live.current();
        snapshot.source_status = current.source_status;
        snapshot.status_reason.clone_from(&current.status_reason);
    }
    state.live.publish(snapshot, data_updated);
}

async fn sync_cycle(
    state: &AppState,
    results: &ResultsSync,
    identities: &mut Option<crate::providers::results::IdentityMaps>,
) -> Result<(), String> {
    if !state.jolpica.enabled {
        return Ok(());
    }
    let now = state
        .database
        .utc_now()
        .await
        .map_err(|error| error.to_string())?;
    let season = now
        .get(..4)
        .and_then(|year| year.parse::<i64>().ok())
        .filter(|year| (1950..=9999).contains(year))
        .ok_or_else(|| "cannot determine current season".to_string())?;

    let cached_calendar = state
        .database
        .calendar(Some(season))
        .await
        .map_err(|error| error.to_string())?
        .0;
    let calendar_delay =
        if has_session_within(&cached_calendar, &now, Duration::from_secs(24 * 60 * 60)) {
            Duration::from_secs(30 * 60)
        } else {
            SIX_HOURS
        };
    let calendar_key = format!("calendar-{season}");
    if periodic_due(
        &state.database,
        PROVIDER,
        &calendar_key,
        &now,
        calendar_delay,
    )
    .await?
    {
        let attempt = begin_job(&state.database, PROVIDER, &calendar_key, &now).await?;
        let sync = CalendarSync {
            jolpica: state.jolpica.clone(),
            openf1: state.openf1.clone(),
            timeout: Duration::from_secs(8),
        };
        match sync.sync_season_once(&state.database, season).await {
            Ok(meetings) => {
                tracing::info!(season, count = meetings.len(), "calendar cache refreshed");
                record_success(
                    &state.database,
                    PROVIDER,
                    &calendar_key,
                    calendar_delay,
                    None,
                )
                .await?;
            }
            Err(error) => {
                record_failure(
                    &state.database,
                    PROVIDER,
                    &calendar_key,
                    attempt,
                    error,
                    None,
                )
                .await?
            }
        }
    }

    if state.openf1.enabled {
        let endpoint = format!("calendar-{season}");
        if periodic_due(
            &state.database,
            OPENF1_PROVIDER,
            &endpoint,
            &now,
            calendar_delay,
        )
        .await?
        {
            let attempt = begin_job(&state.database, OPENF1_PROVIDER, &endpoint, &now).await?;
            let sync = CalendarSync {
                jolpica: state.jolpica.clone(),
                openf1: state.openf1.clone(),
                timeout: Duration::from_secs(8),
            };
            match sync.supplement_openf1_once(&state.database, season).await {
                Ok(count) => {
                    tracing::debug!(
                        season,
                        mapped_sessions = count,
                        "OpenF1 calendar supplement refreshed"
                    );
                    record_success(
                        &state.database,
                        OPENF1_PROVIDER,
                        &endpoint,
                        calendar_delay,
                        None,
                    )
                    .await?;
                }
                Err(error) => {
                    record_failure(
                        &state.database,
                        OPENF1_PROVIDER,
                        &endpoint,
                        attempt,
                        error,
                        None,
                    )
                    .await?
                }
            }
        }
    }

    let now = state
        .database
        .utc_now()
        .await
        .map_err(|error| error.to_string())?;
    let identity_key = format!("identity-{season}");
    if periodic_due(&state.database, PROVIDER, &identity_key, &now, SIX_HOURS).await? {
        let attempt = begin_job(&state.database, PROVIDER, &identity_key, &now).await?;
        match results
            .load_identity_maps_once(&state.database, season)
            .await
        {
            Ok(maps) => {
                *identities = Some(maps);
                record_success(&state.database, PROVIDER, &identity_key, SIX_HOURS, None).await?;
            }
            Err(error) => {
                record_failure(
                    &state.database,
                    PROVIDER,
                    &identity_key,
                    attempt,
                    error,
                    None,
                )
                .await?
            }
        }
    }

    let Some(identities) = identities.as_ref() else {
        return Ok(());
    };
    let driver_key = format!("standings-drivers-{season}");
    if periodic_due(&state.database, PROVIDER, &driver_key, &now, SIX_HOURS).await? {
        let attempt = begin_job(&state.database, PROVIDER, &driver_key, &now).await?;
        match results
            .sync_driver_standings_once(&state.database, season, identities)
            .await
        {
            Ok(_) => {
                record_success(&state.database, PROVIDER, &driver_key, SIX_HOURS, None).await?
            }
            Err(error) => {
                record_failure(&state.database, PROVIDER, &driver_key, attempt, error, None).await?
            }
        }
    }
    let constructor_key = format!("standings-constructors-{season}");
    if periodic_due(&state.database, PROVIDER, &constructor_key, &now, SIX_HOURS).await? {
        let attempt = begin_job(&state.database, PROVIDER, &constructor_key, &now).await?;
        match results
            .sync_constructor_standings_once(&state.database, season, identities)
            .await
        {
            Ok(_) => {
                record_success(&state.database, PROVIDER, &constructor_key, SIX_HOURS, None).await?
            }
            Err(error) => {
                record_failure(
                    &state.database,
                    PROVIDER,
                    &constructor_key,
                    attempt,
                    error,
                    None,
                )
                .await?
            }
        }
    }

    let now = state
        .database
        .utc_now()
        .await
        .map_err(|error| error.to_string())?;
    let now_seconds =
        parse_utc_seconds(&now).ok_or_else(|| "database returned invalid UTC time".to_string())?;
    let meetings = state
        .database
        .calendar(Some(season))
        .await
        .map_err(|error| error.to_string())?
        .0;
    for meeting in meetings
        .iter()
        .filter(|meeting| meeting.status.as_str() != "cancelled")
    {
        for session in meeting
            .sessions
            .iter()
            .filter(|session| session.status.as_str() != "cancelled")
        {
            let (end_at, note) = estimated_end(session);
            let Some(end_seconds) = parse_utc_seconds(&end_at) else {
                continue;
            };
            if end_seconds > now_seconds {
                continue;
            }
            let endpoint = format!("results-{}", session.id);
            if !result_due(&state.database, PROVIDER, &endpoint, &now).await? {
                continue;
            }
            let previous = state
                .database
                .sync_status(PROVIDER, &endpoint)
                .await
                .map_err(|error| error.to_string())?
                .map(|status| status.retry_count)
                .unwrap_or(0);
            state
                .database
                .sync_begin(PROVIDER, &endpoint, &now)
                .await
                .map_err(|error| error.to_string())?;
            match results
                .sync_session_once(&state.database, meeting, session, identities)
                .await
            {
                Ok(SyncOutcome::Stored { retry_after }) => {
                    let age = now_seconds.saturating_sub(end_seconds);
                    record_success(
                        &state.database,
                        PROVIDER,
                        &endpoint,
                        result_refresh_delay(age).max(retry_after.unwrap_or_default()),
                        note.as_deref(),
                    )
                    .await?;
                }
                Ok(SyncOutcome::NoResult) => {
                    record_empty(
                        &state.database,
                        PROVIDER,
                        &endpoint,
                        previous,
                        note.as_deref(),
                    )
                    .await?;
                }
                Err(error) => {
                    record_failure(
                        &state.database,
                        PROVIDER,
                        &endpoint,
                        previous,
                        error,
                        note.as_deref(),
                    )
                    .await?
                }
            }
        }
    }
    Ok(())
}

async fn current_season(state: &AppState) -> Option<i64> {
    state.database.utc_now().await.ok()?.get(..4)?.parse().ok()
}

async fn periodic_due(
    database: &crate::storage::sqlite::Database,
    provider: &str,
    endpoint: &str,
    now: &str,
    interval: Duration,
) -> Result<bool, String> {
    let Some(status) = database
        .sync_status(provider, endpoint)
        .await
        .map_err(|error| error.to_string())?
    else {
        return Ok(true);
    };
    if status.last_error.is_some()
        && status
            .next_retry_at
            .as_deref()
            .is_some_and(|next| next > now)
    {
        return Ok(false);
    }
    let Some(last_success) = status.last_success_at.as_deref() else {
        return Ok(true);
    };
    Ok(interval_elapsed(now, last_success, interval))
}

fn interval_elapsed(now: &str, last_success: &str, interval: Duration) -> bool {
    match (parse_utc_seconds(now), parse_utc_seconds(last_success)) {
        (Some(now), Some(last)) => now.saturating_sub(last) >= interval.as_secs() as i64,
        _ => true,
    }
}

async fn result_due(
    database: &crate::storage::sqlite::Database,
    provider: &str,
    endpoint: &str,
    now: &str,
) -> Result<bool, String> {
    Ok(database
        .sync_status(provider, endpoint)
        .await
        .map_err(|error| error.to_string())?
        .and_then(|status| status.next_retry_at)
        .is_none_or(|next| next.as_str() <= now))
}

async fn begin_job(
    database: &crate::storage::sqlite::Database,
    provider: &str,
    endpoint: &str,
    now: &str,
) -> Result<u32, String> {
    let attempt = database
        .sync_status(provider, endpoint)
        .await
        .map_err(|error| error.to_string())?
        .map(|status| status.retry_count)
        .unwrap_or(0);
    database
        .sync_begin(provider, endpoint, now)
        .await
        .map_err(|error| error.to_string())?;
    Ok(attempt)
}

async fn record_success(
    database: &crate::storage::sqlite::Database,
    provider: &str,
    endpoint: &str,
    delay: Duration,
    note: Option<&str>,
) -> Result<(), String> {
    let now = database
        .utc_now()
        .await
        .map_err(|error| error.to_string())?;
    let next = add_seconds(&now, delay.as_secs() as i64)
        .ok_or_else(|| "invalid UTC deadline".to_string())?;
    database
        .sync_succeeded(provider, endpoint, &now, &next, note)
        .await
        .map_err(|error| error.to_string())
}

async fn record_empty(
    database: &crate::storage::sqlite::Database,
    provider: &str,
    endpoint: &str,
    previous_retries: u32,
    note: Option<&str>,
) -> Result<(), String> {
    let now = database
        .utc_now()
        .await
        .map_err(|error| error.to_string())?;
    let next = add_seconds(&now, no_result_delay(previous_retries).as_secs() as i64)
        .ok_or_else(|| "invalid UTC deadline".to_string())?;
    database
        .sync_empty(provider, endpoint, &now, &next, note)
        .await
        .map_err(|error| error.to_string())
}

async fn record_failure(
    database: &crate::storage::sqlite::Database,
    provider: &str,
    endpoint: &str,
    previous_retries: u32,
    error: ProviderError,
    note: Option<&str>,
) -> Result<(), String> {
    let now = database
        .utc_now()
        .await
        .map_err(|error| error.to_string())?;
    let delay = failure_retry_delay(
        previous_retries.saturating_add(1),
        error.retry_after(),
        jitter(),
    );
    let next = add_seconds(&now, delay.as_secs() as i64)
        .ok_or_else(|| "invalid UTC deadline".to_string())?;
    let summary = error.to_string().chars().take(300).collect::<String>();
    database
        .sync_failed(provider, endpoint, &now, &next, &summary, note)
        .await
        .map_err(|error| error.to_string())
}

fn has_session_within(meetings: &[Meeting], now: &str, horizon: Duration) -> bool {
    let Some(now) = parse_utc_seconds(now) else {
        return false;
    };
    meetings
        .iter()
        .filter(|meeting| meeting.status.as_str() != "cancelled")
        .flat_map(|meeting| meeting.sessions.iter())
        .filter(|session| session.status.as_str() != "cancelled")
        .filter_map(|session| parse_utc_seconds(&session.start_time))
        .any(|start| start >= now && start - now <= horizon.as_secs() as i64)
}

fn estimated_end(session: &Session) -> (String, Option<String>) {
    if let Some(end) = session
        .end_time
        .as_deref()
        .filter(|value| parse_utc_seconds(value).is_some())
    {
        return (end.to_string(), None);
    }
    let hours = match session.session_type {
        SessionType::Race => 2,
        SessionType::Fp1
        | SessionType::Fp2
        | SessionType::Fp3
        | SessionType::Qualifying
        | SessionType::SprintQualifying
        | SessionType::Sprint => 1,
    };
    let note = format!("estimated_end=startTime+{hours}h; probe_only");
    (
        add_seconds(&session.start_time, hours * 60 * 60).unwrap_or_default(),
        Some(note),
    )
}

fn result_refresh_delay(age_seconds: i64) -> Duration {
    if age_seconds < 24 * 60 * 60 {
        Duration::from_secs(30 * 60)
    } else if age_seconds < 72 * 60 * 60 {
        Duration::from_secs(60 * 60)
    } else {
        SIX_HOURS
    }
}

fn no_result_delay(previous_retries: u32) -> Duration {
    Duration::from_secs(match previous_retries {
        0 => 2 * 60,
        1 => 4 * 60,
        _ => 5 * 60,
    })
}

fn failure_retry_delay(attempt: u32, retry_after: Option<Duration>, jitter: Duration) -> Duration {
    let shift = attempt.saturating_sub(1).min(10);
    let base = Duration::from_secs(30_u64.saturating_mul(1_u64 << shift));
    let backoff = base.saturating_add(jitter.min(base / 5)).min(SIX_HOURS);
    retry_after.map_or(backoff, |provider| provider.max(backoff))
}

fn jitter() -> Duration {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .subsec_nanos();
    Duration::from_secs((nanos % 7) as u64)
}

pub(crate) fn parse_utc_seconds(value: &str) -> Option<i64> {
    let date = value.get(..19)?;
    let year: i64 = date.get(0..4)?.parse().ok()?;
    let month: i64 = date.get(5..7)?.parse().ok()?;
    let day: i64 = date.get(8..10)?.parse().ok()?;
    let hour: i64 = date.get(11..13)?.parse().ok()?;
    let minute: i64 = date.get(14..16)?.parse().ok()?;
    let second: i64 = date.get(17..19)?.parse().ok()?;
    if !(1..=12).contains(&month)
        || !(1..=31).contains(&day)
        || hour > 23
        || minute > 59
        || second > 60
    {
        return None;
    }
    let offset = &value[19..];
    let offset_seconds = if offset.is_empty() || offset.starts_with('Z') {
        0
    } else {
        let sign = match offset.as_bytes().first()? {
            b'+' => 1,
            b'-' => -1,
            _ => return None,
        };
        let hours: i64 = offset.get(1..3)?.parse().ok()?;
        let minutes: i64 = offset.get(4..6)?.parse().ok()?;
        sign * (hours * 3600 + minutes * 60)
    };
    Some(
        days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
            - offset_seconds,
    )
}

pub(crate) fn add_seconds(value: &str, seconds: i64) -> Option<String> {
    let epoch = parse_utc_seconds(value)?.checked_add(seconds)?;
    let days = epoch.div_euclid(86400);
    let seconds = epoch.rem_euclid(86400);
    let (year, month, day) = civil_from_days(days);
    Some(format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}Z",
        seconds / 3600,
        seconds / 60 % 60,
        seconds % 60
    ))
}

fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = year - i64::from(month <= 2);
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let adjusted_month = month + if month > 2 { -3 } else { 9 };
    let day_of_year = (153 * adjusted_month + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146097 + day_of_era - 719468
}

fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let days = days + 719468;
    let era = days.div_euclid(146097);
    let day_of_era = days - era * 146097;
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    let year = year_of_era + era * 400;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_prime = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_prime + 2) / 5 + 1;
    let month = month_prime + if month_prime < 10 { 3 } else { -9 };
    (year + i64::from(month <= 2), month, day)
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Json, Router, extract::State};
    use serde_json::{Value, json};
    use std::sync::{
        Arc,
        atomic::AtomicUsize,
        atomic::{AtomicBool, Ordering},
    };
    use tempfile::TempDir;
    use tokio::net::TcpListener;

    #[test]
    fn test_session_result_deadlines_and_estimated_end_cross_midnight() {
        assert_eq!(
            result_refresh_delay(24 * 60 * 60 - 1),
            Duration::from_secs(1800)
        );
        assert_eq!(
            result_refresh_delay(24 * 60 * 60),
            Duration::from_secs(3600)
        );
        assert_eq!(result_refresh_delay(72 * 60 * 60), SIX_HOURS);
        assert_eq!(
            add_seconds("2026-10-09T23:30:00Z", 7200).as_deref(),
            Some("2026-10-10T01:30:00Z")
        );
        assert_eq!(
            parse_utc_seconds("2026-10-10T03:30:00+02:00"),
            parse_utc_seconds("2026-10-10T01:30:00Z")
        );
        let start = "2026-10-09T00:00:00Z";
        assert_eq!(
            estimated_end(&session(SessionType::Fp1, start)).0,
            "2026-10-09T01:00:00Z"
        );
        assert_eq!(
            estimated_end(&session(SessionType::Qualifying, start)).0,
            "2026-10-09T01:00:00Z"
        );
        assert_eq!(
            estimated_end(&session(SessionType::Sprint, start)).0,
            "2026-10-09T01:00:00Z"
        );
        assert_eq!(
            estimated_end(&session(SessionType::Race, start)).0,
            "2026-10-09T02:00:00Z"
        );
    }

    #[test]
    fn test_no_result_and_failure_backoff_are_injectable_and_bounded() {
        assert_eq!(no_result_delay(0), Duration::from_secs(120));
        assert_eq!(no_result_delay(1), Duration::from_secs(240));
        assert_eq!(no_result_delay(9), Duration::from_secs(300));
        assert_eq!(
            failure_retry_delay(1, None, Duration::from_secs(5)),
            Duration::from_secs(35)
        );
        assert_eq!(failure_retry_delay(32, None, Duration::ZERO), SIX_HOURS);
        assert_eq!(
            failure_retry_delay(1, Some(Duration::from_secs(8 * 60 * 60)), Duration::ZERO),
            Duration::from_secs(8 * 60 * 60)
        );
    }

    #[test]
    fn test_calendar_due_window_ignores_cancelled_sessions() {
        let mut meeting = Meeting {
            id: "2026:1".into(),
            season: 2026,
            round: Some(1),
            jolpica_round_id: None,
            name: "Race".into(),
            country_code: None,
            country: "".into(),
            location: "".into(),
            start_date: "2026-10-10T00:00:00Z".into(),
            end_date: "2026-10-10T00:00:00Z".into(),
            status: crate::domain::calendar::MeetingStatus::Scheduled,
            sessions: vec![],
            source: None,
            fetched_at: None,
            source_updated_at: None,
            revision: None,
        };
        meeting.sessions.push(Session {
            id: "cancelled".into(),
            meeting_id: meeting.id.clone(),
            session_type: SessionType::Race,
            start_time: "2026-10-09T20:00:00Z".into(),
            end_time: None,
            status: crate::domain::calendar::SessionStatus::Cancelled,
            jolpica_session_id: None,
            openf1_session_key: None,
        });
        assert!(!has_session_within(
            &[meeting],
            "2026-10-09T12:00:00Z",
            Duration::from_secs(86400)
        ));
    }

    #[test]
    fn test_injected_periodic_clock_and_pre_session_horizon_boundaries() {
        let now = "2026-10-09T12:00:00Z";
        assert!(!interval_elapsed(now, "2026-10-09T06:00:01Z", SIX_HOURS));
        assert!(interval_elapsed(now, "2026-10-09T06:00:00Z", SIX_HOURS));
        let meeting = Meeting {
            id: "2026:1".into(),
            season: 2026,
            round: Some(1),
            jolpica_round_id: None,
            name: "Race".into(),
            country_code: None,
            country: String::new(),
            location: String::new(),
            start_date: "2026-10-10T12:00:00Z".into(),
            end_date: "2026-10-10T12:00:00Z".into(),
            status: crate::domain::calendar::MeetingStatus::Scheduled,
            sessions: vec![session(SessionType::Race, "2026-10-10T12:00:00Z")],
            source: None,
            fetched_at: None,
            source_updated_at: None,
            revision: None,
        };
        assert!(has_session_within(
            std::slice::from_ref(&meeting),
            now,
            Duration::from_secs(24 * 60 * 60)
        ));
        let next_day = Meeting {
            sessions: vec![session(SessionType::Race, "2026-10-10T12:00:01Z")],
            ..meeting
        };
        assert!(!has_session_within(
            &[next_day],
            now,
            Duration::from_secs(24 * 60 * 60)
        ));
    }

    fn session(session_type: SessionType, start: &str) -> Session {
        Session {
            id: "session".into(),
            meeting_id: "meeting".into(),
            session_type,
            start_time: start.into(),
            end_time: None,
            status: crate::domain::calendar::SessionStatus::Scheduled,
            jolpica_session_id: None,
            openf1_session_key: None,
        }
    }

    #[tokio::test]
    async fn test_scheduler_shutdown_cancels_pending_job_and_joins_it() {
        struct CancelOnDrop(Arc<AtomicBool>);
        impl Drop for CancelOnDrop {
            fn drop(&mut self) {
                self.0.store(true, Ordering::SeqCst);
            }
        }

        let dropped = Arc::new(AtomicBool::new(false));
        let guard = CancelOnDrop(dropped.clone());
        let task = tokio::spawn(async move {
            let _guard = guard;
            std::future::pending::<()>().await;
        });
        tokio::task::yield_now().await;
        SchedulerTasks(vec![task]).shutdown().await;
        assert!(dropped.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn test_mock_scheduler_polls_empty_sessions_once_and_records_no_result() {
        #[derive(Default)]
        struct Counts {
            calls: AtomicUsize,
            active: AtomicUsize,
            max_active: AtomicUsize,
        }
        async fn empty_results(State(counts): State<Arc<Counts>>) -> Json<Value> {
            counts.calls.fetch_add(1, Ordering::SeqCst);
            let active = counts.active.fetch_add(1, Ordering::SeqCst) + 1;
            counts.max_active.fetch_max(active, Ordering::SeqCst);
            tokio::time::sleep(Duration::from_millis(10)).await;
            counts.active.fetch_sub(1, Ordering::SeqCst);
            Json(json!({"metadata":{"timestamp":"2026-10-09T00:00:00Z"},"data":{"results":[]}}))
        }

        let temp = TempDir::new().unwrap();
        let path = temp.path().join("scheduler.sqlite");
        let database = crate::storage::sqlite::Database::open(&path).await.unwrap();
        database.migrate().await.unwrap();
        let fixture: Value = serde_json::from_str(include_str!(
            "../tests/fixtures/jolpica-alpha-2026-australia.json"
        ))
        .unwrap();
        let meetings = crate::providers::jolpica::decode_alpha_schedule(&fixture).unwrap();
        database
            .replace_calendar(&meetings, "2026-10-09T00:00:00Z")
            .await
            .unwrap();
        let now = database.utc_now().await.unwrap();
        let next = add_seconds(&now, 24 * 60 * 60).unwrap();
        for endpoint in [
            "calendar-2026",
            "identity-2026",
            "standings-drivers-2026",
            "standings-constructors-2026",
        ] {
            database
                .sync_succeeded(PROVIDER, endpoint, &now, &next, None)
                .await
                .unwrap();
        }

        let counts = Arc::new(Counts::default());
        let app = Router::new()
            .fallback(empty_results)
            .with_state(counts.clone());
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let upstream = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        let mut config = crate::config::AppConfig::default();
        config.database.path = path;
        config.providers.openf1_enabled = false;
        let mut state = crate::app_state::AppState::new(config, database.clone());
        state.jolpica = crate::providers::jolpica::JolpicaProvider::with_base_url(
            reqwest::Client::new(),
            format!("http://{address}"),
        );
        let mut openf1 = crate::providers::openf1::OpenF1Provider::with_base_url(
            reqwest::Client::new(),
            format!("http://{address}"),
        );
        openf1.enabled = false;
        let sync = ResultsSync {
            jolpica: state.jolpica.clone(),
            openf1,
            timeout: Duration::from_secs(2),
        };
        let drivers = [json!({
            "driverId":"leclerc",
            "permanentNumber":"16",
            "url":"https://en.wikipedia.org/wiki/Charles_Leclerc"
        })];
        let constructors = [json!({
            "constructorId":"ferrari",
            "name":"Ferrari",
            "url":"https://en.wikipedia.org/wiki/Scuderia_Ferrari"
        })];
        let mut identities = Some(crate::providers::results::IdentityMaps::from_ergast(
            &drivers,
            &constructors,
        ));

        sync_cycle(&state, &sync, &mut identities).await.unwrap();
        let requested = counts.calls.load(Ordering::SeqCst);
        assert_eq!(requested, meetings[0].sessions.len());
        assert_eq!(counts.max_active.load(Ordering::SeqCst), 1);
        for session in &meetings[0].sessions {
            let status = database
                .sync_status(PROVIDER, &format!("results-{}", session.id))
                .await
                .unwrap()
                .unwrap();
            assert_eq!(status.retry_count, 1);
            assert!(status.last_error.is_none());
        }

        sync_cycle(&state, &sync, &mut identities).await.unwrap();
        assert_eq!(counts.calls.load(Ordering::SeqCst), requested);
        upstream.abort();
    }
}
