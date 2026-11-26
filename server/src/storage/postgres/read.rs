use std::{
    collections::{BTreeMap, HashMap},
    future::Future,
    sync::Arc,
};

use serde_json::Value;
use tokio_postgres::{IsolationLevel, Row};

use crate::{
    api::dto::Meta,
    domain::{
        calendar::{Meeting, MeetingStatus, Session, SessionStatus, SessionType},
        quality::DataQuality,
        results::SessionResult,
        standings::{ConstructorStanding, DriverStanding},
    },
    error::StorageError,
    storage::sqlite::{ScheduleSnapshot, meta_from_snapshot},
};

use super::{Postgres, cache::Key};

pub(super) const RESULT_COLUMNS: &str = "session_id, position, classification, driver_id, driver_name, constructor_id, team, time, best_lap, q1, q2, q3, race_time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality, driver_number";

const MEETING_COLUMNS: &str = "id, season, round, name, country, location, start_date, end_date,
    country_code, status, source, fetched_at, source_updated_at, revision, jolpica_round_id, circuit_json";

struct CalendarSnapshot {
    meetings: Vec<Meeting>,
    // Each candidate is (UTC microseconds, meeting index). The SQL query
    // supplies the legacy tie-break ordering before we index the list.
    next: Vec<(i64, usize)>,
    meta: Meta,
}

impl Postgres {
    async fn query_racing_seasons_before(&self, season: i64) -> Result<Vec<i64>, StorageError> {
        self.client().await?.query(
            "SELECT DISTINCT season FROM meetings WHERE round IS NOT NULL AND season >= $1 AND season < $2 ORDER BY season",
            &[&crate::services::FIRST_SEASON, &season],
        ).await?.into_iter().map(|row| Ok(row.try_get(0)?)).collect()
    }

    pub(crate) async fn calendar(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<Meeting>, Meta), StorageError> {
        let (snapshot, meta) = self.calendar_snapshot(season).await?;
        Ok((snapshot.meetings.clone(), meta))
    }

    pub(crate) async fn next_meeting_at(
        &self,
        season: Option<i64>,
        now: &str,
    ) -> Result<(Option<Meeting>, Meta), StorageError> {
        use crate::scheduler::parse_utc_seconds;
        let Some(now_micros) = parse_utc_seconds(now)
            .filter(|_| now.is_ascii() && now.len() == 20 && now.ends_with('Z'))
            .and_then(|seconds| seconds.checked_mul(1_000_000))
        else {
            // Explicit historical lookups also accept offsets/fractions. The
            // actual HTTP path supplies a whole-second UTC timestamp.
            let snapshot = self.query_calendar(season, Some(now)).await?;
            return Ok((snapshot.meetings.into_iter().next(), snapshot.meta));
        };
        let (snapshot, meta) = self.calendar_snapshot(season).await?;
        let index = snapshot
            .next
            .partition_point(|&(time, _)| time < now_micros);
        let next = snapshot
            .next
            .get(index)
            .map(|&(_, index)| snapshot.meetings[index].clone());
        Ok((next, meta))
    }

    async fn calendar_snapshot(
        &self,
        season: Option<i64>,
    ) -> Result<(Arc<CalendarSnapshot>, Meta), StorageError> {
        self.cached(
            Key::Calendar(season),
            async {
                let snapshot = self.query_calendar(season, None).await?;
                let meta = snapshot.meta.clone();
                Ok((Arc::new(snapshot), meta))
            },
            |_| true,
            stale_meta,
        )
        .await
    }

    async fn cached<T: Clone + Send + Sync + 'static>(
        &self,
        key: Key,
        load: impl Future<Output = Result<T, StorageError>>,
        can_fallback: impl FnOnce(&T) -> bool,
        mark_stale: impl FnOnce(&mut T),
    ) -> Result<T, StorageError> {
        self.cache
            .get(
                key,
                self.dataset_generation(),
                load,
                can_fallback,
                mark_stale,
            )
            .await
    }

    pub(crate) async fn racing_seasons_before(
        &self,
        season: i64,
    ) -> Result<Vec<i64>, StorageError> {
        self.cached(
            Key::RacingSeasons(season),
            self.query_racing_seasons_before(season),
            |rows| !rows.is_empty(),
            |_| {},
        )
        .await
    }

    pub(crate) async fn session_season(&self, id: &str) -> Result<Option<i64>, StorageError> {
        self.cached(
            Key::SessionSeason(id.to_owned()),
            self.query_session_season(id),
            Option::is_some,
            |_| {},
        )
        .await
    }

    pub(crate) async fn session_results(
        &self,
        id: &str,
    ) -> Result<(Vec<SessionResult>, Meta), StorageError> {
        self.cached(
            Key::SessionResults(id.to_owned()),
            self.query_session_results(id),
            |(rows, _)| !rows.is_empty(),
            stale_meta,
        )
        .await
    }

    pub(crate) async fn driver_standings(
        &self,
        season: i64,
    ) -> Result<(Vec<DriverStanding>, Meta), StorageError> {
        self.cached(
            Key::Drivers(season),
            self.query_driver_standings(season),
            |(rows, _)| !rows.is_empty(),
            stale_meta,
        )
        .await
    }

    pub(crate) async fn constructor_standings(
        &self,
        season: i64,
    ) -> Result<(Vec<ConstructorStanding>, Meta), StorageError> {
        self.cached(
            Key::Constructors(season),
            self.query_constructor_standings(season),
            |(rows, _)| !rows.is_empty(),
            stale_meta,
        )
        .await
    }

    pub(crate) async fn identity_cache(
        &self,
        season: i64,
    ) -> Result<Option<(Vec<Value>, Vec<Value>)>, StorageError> {
        self.cached(
            Key::Identity(season),
            self.query_identity_cache(season),
            Option::is_some,
            |_| {},
        )
        .await
    }

    pub(crate) async fn next_season_schedule(
        &self,
        season: i64,
    ) -> Result<Option<ScheduleSnapshot>, StorageError> {
        self.cached(
            Key::Schedule(season),
            self.query_next_season_schedule(season),
            Option::is_some,
            |snapshot| {
                if let Some(snapshot) = snapshot {
                    snapshot.stale = true;
                }
            },
        )
        .await
    }

    pub(crate) async fn published_schedule_openings(
        &self,
    ) -> Result<BTreeMap<i64, String>, StorageError> {
        self.cached(
            Key::ScheduleOpenings,
            self.query_published_schedule_openings(),
            |rows| !rows.is_empty(),
            |_| {},
        )
        .await
    }

    async fn query_calendar(
        &self,
        season: Option<i64>,
        now: Option<&str>,
    ) -> Result<CalendarSnapshot, StorageError> {
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
        let mut next = Vec::new();
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
            if now.is_none() {
                let indexes: HashMap<_, _> =
                    ids.iter().enumerate().map(|(i, id)| (*id, i)).collect();
                let candidates = tx.query(
                    "SELECT s.meeting_id, (EXTRACT(EPOCH FROM season_timestamp(s.start_time)) * 1000000)::bigint AS micros
                     FROM sessions s JOIN meetings m ON m.id=s.meeting_id
                     WHERE s.meeting_id = ANY($1::text[]) AND m.status='scheduled' AND s.status='scheduled'
                     ORDER BY micros, s.id COLLATE \"C\", m.id COLLATE \"C\"",
                    &[&ids],
                ).await?;
                for candidate in candidates {
                    if let Some(micros) = candidate.try_get::<_, Option<i64>>(1)? {
                        next.push((micros, indexes[candidate.try_get::<_, &str>(0)?]));
                    }
                }
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
        Ok(CalendarSnapshot {
            meetings,
            next,
            meta,
        })
    }

    async fn query_session_season(&self, session_id: &str) -> Result<Option<i64>, StorageError> {
        self.client().await?.query_opt(
            "SELECT meetings.season FROM sessions JOIN meetings ON meetings.id = sessions.meeting_id WHERE sessions.id = $1",
            &[&session_id],
        ).await?.map(|row| Ok(row.try_get(0)?)).transpose()
    }

    async fn query_session_results(
        &self,
        session_id: &str,
    ) -> Result<(Vec<SessionResult>, Meta), StorageError> {
        let rows = self.client().await?.query(
            &format!("SELECT {RESULT_COLUMNS},
                    COALESCE(now() - season_timestamp(fetched_at) > interval '6 hours', TRUE)
             FROM session_results WHERE session_id = $1 AND revision = (SELECT MAX(revision) FROM session_results WHERE session_id = $1)
             ORDER BY position NULLS LAST, driver_id COLLATE \"C\""),
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

    async fn query_driver_standings(
        &self,
        season: i64,
    ) -> Result<(Vec<DriverStanding>, Meta), StorageError> {
        let rows = self.client().await?.query(
            "SELECT season, position, driver_id, driver_name, constructor, points, wins, source, fetched_at, revision, constructor_ids, driver_number,
                    COALESCE(now() - season_timestamp(fetched_at) > interval '6 hours', TRUE)
             FROM driver_standings WHERE season = $1 ORDER BY position, driver_id COLLATE \"C\"",
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

    async fn query_constructor_standings(
        &self,
        season: i64,
    ) -> Result<(Vec<ConstructorStanding>, Meta), StorageError> {
        let rows = self.client().await?.query(
            "SELECT season, position, constructor_id, constructor_name, points, wins, source, fetched_at, revision,
                    COALESCE(now() - season_timestamp(fetched_at) > interval '6 hours', TRUE)
             FROM constructor_standings WHERE season = $1 ORDER BY position, constructor_id COLLATE \"C\"",
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

    async fn query_identity_cache(
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

    async fn query_next_season_schedule(
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
            stale: false,
        })).transpose()
    }

    async fn query_published_schedule_openings(
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

fn stale_meta<T>((_, meta): &mut (T, Meta)) {
    meta.stale = true;
    meta.quality = DataQuality::Stale;
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
pub(super) fn session_result(row: &Row) -> Result<SessionResult, StorageError> {
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
