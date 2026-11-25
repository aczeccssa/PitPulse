use std::collections::{BTreeMap, HashMap};

use serde_json::Value;
use tokio_postgres::{IsolationLevel, Row};

use crate::{
    api::dto::Meta,
    domain::{
        calendar::{Meeting, MeetingStatus, Session, SessionStatus, SessionType},
        results::SessionResult,
        standings::{ConstructorStanding, DriverStanding},
    },
    error::StorageError,
    storage::sqlite::{ScheduleSnapshot, meta_from_snapshot},
};

use super::Postgres;

const MEETING_COLUMNS: &str = "id, season, round, name, country, location, start_date, end_date,
    country_code, status, source, fetched_at, source_updated_at, revision, jolpica_round_id, circuit_json";

impl Postgres {
    pub(crate) async fn racing_seasons_before(
        &self,
        season: i64,
    ) -> Result<Vec<i64>, StorageError> {
        self.client().await?.query(
            "SELECT DISTINCT season FROM meetings WHERE round IS NOT NULL AND season >= $1 AND season < $2 ORDER BY season",
            &[&crate::services::FIRST_SEASON, &season],
        ).await?.into_iter().map(|row| Ok(row.try_get(0)?)).collect()
    }

    pub(crate) async fn calendar(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<Meeting>, Meta), StorageError> {
        self.calendar_at(season, None).await
    }

    pub(crate) async fn next_meeting_at(
        &self,
        season: Option<i64>,
        now: &str,
    ) -> Result<(Option<Meeting>, Meta), StorageError> {
        let (meetings, meta) = self.calendar_at(season, Some(now)).await?;
        Ok((meetings.into_iter().next(), meta))
    }

    async fn calendar_at(
        &self,
        season: Option<i64>,
        now: Option<&str>,
    ) -> Result<(Vec<Meeting>, Meta), StorageError> {
        let mut client = self.client().await?;
        let tx = client
            .build_transaction()
            .read_only(true)
            .isolation_level(IsolationLevel::RepeatableRead)
            .start()
            .await?;
        let meetings = match now {
            None => tx.query(&format!(
                "SELECT {MEETING_COLUMNS} FROM meetings WHERE ($1::bigint IS NULL OR season = $1) ORDER BY COALESCE(round, 9999), id COLLATE \"C\""
            ), &[&season]).await?,
            Some(now) => tx.query(&format!(
                "SELECT {MEETING_COLUMNS} FROM meetings WHERE id = (
                    SELECT m.id FROM meetings m JOIN sessions s ON s.meeting_id = m.id
                    WHERE m.status = 'scheduled' AND s.status = 'scheduled'
                      AND ($1::bigint IS NULL OR m.season = $1)
                      AND season_timestamp(s.start_time) >= season_timestamp($2)
                    ORDER BY season_timestamp(s.start_time), s.id COLLATE \"C\", m.id COLLATE \"C\" LIMIT 1)"
            ), &[&season, &now]).await?,
        };
        let mut meetings = meetings
            .iter()
            .map(meeting)
            .collect::<Result<Vec<_>, _>>()?;
        if !meetings.is_empty() {
            let ids: Vec<_> = meetings.iter().map(|meeting| meeting.id.as_str()).collect();
            let sessions = tx.query(
                "SELECT id, meeting_id, session_type, start_time, end_time, status, jolpica_session_id, openf1_session_key
                 FROM sessions WHERE meeting_id = ANY($1::text[]) ORDER BY start_time COLLATE \"C\", id COLLATE \"C\"",
                &[&ids],
            ).await?;
            let mut by_meeting: HashMap<String, Vec<Session>> = HashMap::new();
            for session in sessions.iter().map(session) {
                let session = session?;
                by_meeting
                    .entry(session.meeting_id.clone())
                    .or_default()
                    .push(session);
            }
            for meeting in &mut meetings {
                meeting.sessions = by_meeting.remove(&meeting.id).unwrap_or_default();
            }
        }
        let meta = tx.query_opt(
            "SELECT source, fetched_at, COALESCE((SELECT MAX(revision) FROM calendar_snapshots WHERE ($1::bigint IS NULL OR season = $1)), max_revision),
                    COALESCE(now() - season_timestamp(oldest) > interval '6 hours', TRUE)
             FROM (SELECT source, fetched_at, MIN(fetched_at COLLATE \"C\") OVER () AS oldest, MAX(revision) OVER () AS max_revision
                   FROM meetings WHERE ($1::bigint IS NULL OR season = $1)
                   ORDER BY fetched_at COLLATE \"C\" DESC, id COLLATE \"C\" LIMIT 1) snapshot",
            &[&season],
        ).await?;
        let meta = match meta {
            Some(row) => standings_meta(&row)?,
            None => Meta::empty(),
        };
        tx.commit().await?;
        Ok((meetings, meta))
    }

    pub(crate) async fn session_season(
        &self,
        session_id: &str,
    ) -> Result<Option<i64>, StorageError> {
        self.client().await?.query_opt(
            "SELECT meetings.season FROM sessions JOIN meetings ON meetings.id = sessions.meeting_id WHERE sessions.id = $1",
            &[&session_id],
        ).await?.map(|row| Ok(row.try_get(0)?)).transpose()
    }

    pub(crate) async fn session_results(
        &self,
        session_id: &str,
    ) -> Result<(Vec<SessionResult>, Meta), StorageError> {
        let rows = self.client().await?.query(
            "SELECT session_id, position, classification, driver_id, driver_name, constructor_id, team, time, best_lap, q1, q2, q3,
                    race_time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality, driver_number,
                    COALESCE(now() - season_timestamp(fetched_at) > interval '6 hours', TRUE)
             FROM session_results WHERE session_id = $1 AND revision = (SELECT MAX(revision) FROM session_results WHERE session_id = $1)
             ORDER BY position NULLS LAST, driver_id COLLATE \"C\"",
            &[&session_id],
        ).await?;
        let results = rows
            .iter()
            .map(session_result)
            .collect::<Result<Vec<_>, _>>()?;
        let meta = match results.first() {
            Some(first) => meta_from_snapshot(
                first.source.clone(),
                first.source_updated_at.clone(),
                first.fetched_at.clone(),
                first.revision,
                &first.quality,
                rows[0].try_get(22)?,
            ),
            None => Meta::empty(),
        };
        Ok((results, meta))
    }

    pub(crate) async fn driver_standings(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<DriverStanding>, Meta), StorageError> {
        let rows = self.client().await?.query(
            "SELECT season, position, driver_id, driver_name, constructor, points, wins, source, fetched_at, revision, constructor_ids, driver_number,
                    COALESCE(now() - season_timestamp(fetched_at) > interval '6 hours', TRUE)
             FROM driver_standings WHERE season = COALESCE($1, EXTRACT(YEAR FROM now())::bigint) ORDER BY position, driver_id COLLATE \"C\"",
            &[&season],
        ).await?;
        let rows_and_meta = rows
            .iter()
            .map(driver_standing)
            .collect::<Result<Vec<_>, _>>()?;
        let meta = match latest_revision(&rows_and_meta, |row| row.revision) {
            Some(index) => {
                let row = &rows_and_meta[index];
                Meta::from_cache(
                    Some(row.source.clone()),
                    Some(row.fetched_at.clone()),
                    row.revision.max(0) as u64,
                    rows[index].try_get(12)?,
                )
            }
            None => Meta::empty(),
        };
        Ok((rows_and_meta, meta))
    }

    pub(crate) async fn constructor_standings(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<ConstructorStanding>, Meta), StorageError> {
        let rows = self.client().await?.query(
            "SELECT season, position, constructor_id, constructor_name, points, wins, source, fetched_at, revision,
                    COALESCE(now() - season_timestamp(fetched_at) > interval '6 hours', TRUE)
             FROM constructor_standings WHERE season = COALESCE($1, EXTRACT(YEAR FROM now())::bigint) ORDER BY position, constructor_id COLLATE \"C\"",
            &[&season],
        ).await?;
        let rows_and_meta = rows
            .iter()
            .map(constructor_standing)
            .collect::<Result<Vec<_>, _>>()?;
        let meta = match latest_revision(&rows_and_meta, |row| row.revision) {
            Some(index) => {
                let row = &rows_and_meta[index];
                Meta::from_cache(
                    Some(row.source.clone()),
                    Some(row.fetched_at.clone()),
                    row.revision.max(0) as u64,
                    rows[index].try_get(9)?,
                )
            }
            None => Meta::empty(),
        };
        Ok((rows_and_meta, meta))
    }

    pub(crate) async fn identity_cache(
        &self,
        season: i64,
    ) -> Result<Option<(Vec<Value>, Vec<Value>)>, StorageError> {
        self.client().await?.query_opt(
            "SELECT drivers_json, constructors_json FROM provider_identity_cache WHERE season = $1",
            &[&season],
        ).await?.map(|row| Ok((
            serde_json::from_str(row.try_get(0)?).unwrap_or_default(),
            serde_json::from_str(row.try_get(1)?).unwrap_or_default(),
        ))).transpose()
    }

    pub(crate) async fn next_season_schedule(
        &self,
        season: i64,
    ) -> Result<Option<ScheduleSnapshot>, StorageError> {
        self.client().await?.query_opt(
            "SELECT events_json, revision, checked_at, updated_at FROM next_season_schedule WHERE season = $1",
            &[&season],
        ).await?.map(|row| Ok(ScheduleSnapshot {
            events: serde_json::from_str(row.try_get(0)?).map_err(|_| StorageError::SeasonDataInvalid)?,
            revision: u64::try_from(row.try_get::<_, i64>(1)?).map_err(|_| StorageError::SeasonDataInvalid)?,
            checked_at: row.try_get(2)?,
            updated_at: row.try_get(3)?,
        })).transpose()
    }

    pub(crate) async fn published_schedule_openings(
        &self,
    ) -> Result<BTreeMap<i64, String>, StorageError> {
        self.client().await?.query(
            "SELECT schedule.season, min((event.value ->> 'startDate') COLLATE \"C\")
             FROM next_season_schedule schedule CROSS JOIN LATERAL jsonb_array_elements(schedule.events_json::jsonb) event
             WHERE jsonb_typeof(event.value -> 'round') = 'number' AND (event.value ->> 'round') ~ '^-?[0-9]+$'
             GROUP BY schedule.season",
            &[],
        ).await?.into_iter().map(|row| Ok((row.try_get(0)?, row.try_get(1)?))).collect()
    }
}

fn latest_revision<T>(rows: &[T], revision: impl Fn(&T) -> i64) -> Option<usize> {
    rows.iter()
        .enumerate()
        .max_by_key(|(index, row)| (revision(row), std::cmp::Reverse(*index)))
        .map(|(index, _)| index)
}

fn standings_meta(row: &Row) -> Result<Meta, StorageError> {
    Ok(Meta::from_cache(
        row.try_get(0)?,
        row.try_get(1)?,
        row.try_get::<_, i64>(2)?.max(0) as u64,
        row.try_get(3)?,
    ))
}

fn meeting(row: &Row) -> Result<Meeting, StorageError> {
    Ok(Meeting {
        id: row.try_get(0)?,
        season: row.try_get(1)?,
        round: row.try_get(2)?,
        jolpica_round_id: row.try_get(14)?,
        circuit: row
            .try_get::<_, Option<String>>(15)?
            .and_then(|v| serde_json::from_str(&v).ok()),
        name: row.try_get(3)?,
        country: row.try_get(4)?,
        country_code: row.try_get(8)?,
        location: row.try_get(5)?,
        start_date: row.try_get(6)?,
        end_date: row.try_get(7)?,
        status: MeetingStatus::parse(&row.try_get::<_, String>(9)?),
        sessions: Vec::new(),
        source: row.try_get(10)?,
        fetched_at: row.try_get(11)?,
        source_updated_at: row.try_get(12)?,
        revision: row.try_get(13)?,
    })
}
fn session(row: &Row) -> Result<Session, StorageError> {
    Ok(Session {
        id: row.try_get(0)?,
        meeting_id: row.try_get(1)?,
        session_type: SessionType::parse(&row.try_get::<_, String>(2)?)
            .unwrap_or(SessionType::Race),
        start_time: row.try_get(3)?,
        end_time: row.try_get(4)?,
        status: SessionStatus::parse(&row.try_get::<_, String>(5)?),
        jolpica_session_id: row.try_get(6)?,
        openf1_session_key: row.try_get(7)?,
    })
}
fn session_result(row: &Row) -> Result<SessionResult, StorageError> {
    Ok(SessionResult {
        session_id: row.try_get(0)?,
        position: row.try_get(1)?,
        classification: row.try_get(2)?,
        driver_id: row.try_get(3)?,
        driver_name: row.try_get(4)?,
        constructor_id: row.try_get(5)?,
        team: row.try_get(6)?,
        time: row.try_get(7)?,
        best_lap: row.try_get(8)?,
        q1: row.try_get(9)?,
        q2: row.try_get(10)?,
        q3: row.try_get(11)?,
        race_time: row.try_get(12)?,
        gap: row.try_get(13)?,
        laps: row.try_get(14)?,
        points: row.try_get(15)?,
        source: row.try_get(16)?,
        source_updated_at: row.try_get(17)?,
        fetched_at: row.try_get(18)?,
        revision: row.try_get(19)?,
        quality: row.try_get(20)?,
        driver_number: row.try_get(21)?,
    })
}
fn driver_standing(row: &Row) -> Result<DriverStanding, StorageError> {
    Ok(DriverStanding {
        season: row.try_get(0)?,
        position: row.try_get(1)?,
        driver_id: row.try_get(2)?,
        driver_name: row.try_get(3)?,
        constructor: row.try_get(4)?,
        points: row.try_get(5)?,
        wins: row.try_get(6)?,
        source: row.try_get(7)?,
        fetched_at: row.try_get(8)?,
        revision: row.try_get(9)?,
        constructor_ids: serde_json::from_str(&row.try_get::<_, String>(10)?).unwrap_or_default(),
        driver_number: row.try_get(11)?,
    })
}
fn constructor_standing(row: &Row) -> Result<ConstructorStanding, StorageError> {
    Ok(ConstructorStanding {
        season: row.try_get(0)?,
        position: row.try_get(1)?,
        constructor_id: row.try_get(2)?,
        constructor_name: row.try_get(3)?,
        points: row.try_get(4)?,
        wins: row.try_get(5)?,
        source: row.try_get(6)?,
        fetched_at: row.try_get(7)?,
        revision: row.try_get(8)?,
    })
}
