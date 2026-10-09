use std::{path::Path, sync::Arc};

use rusqlite::{Connection, OptionalExtension};
use tokio::{sync::Mutex, task::spawn_blocking};

use crate::{
    api::dto::Meta,
    domain::{
        calendar::{Meeting, MeetingStatus, Session, SessionStatus, SessionType},
        quality::DataQuality,
        results::SessionResult,
        standings::{ConstructorStanding, DriverStanding},
    },
    error::StorageError,
};

const MIGRATION_0001: &str = include_str!("migrations/0001_init.sql");
const MIGRATION_0002: &str = include_str!("migrations/0002_calendar_contract.sql");
const MIGRATION_0003: &str = include_str!("migrations/0003_nullable_meeting_round.sql");
const MIGRATION_0004: &str = include_str!("migrations/0004_results.sql");

#[derive(Clone)]
pub struct Database {
    connection: Arc<Mutex<Connection>>,
}

impl Database {
    pub async fn open(path: &Path) -> Result<Self, StorageError> {
        let path = path.to_path_buf();
        let connection = spawn_blocking(move || -> Result<Connection, StorageError> {
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            Ok(Connection::open(path)?)
        })
        .await??;

        connection.execute_batch(
            "PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;",
        )?;
        Ok(Self {
            connection: Arc::new(Mutex::new(connection)),
        })
    }

    pub async fn migrate(&self) -> Result<(), StorageError> {
        let connection = Arc::clone(&self.connection);
        spawn_blocking(move || apply_migrations(&connection.blocking_lock())).await??;
        Ok(())
    }

    pub async fn health_check(&self) -> Result<(), StorageError> {
        let connection = Arc::clone(&self.connection);
        spawn_blocking(move || {
            let connection = connection.blocking_lock();
            connection.query_row("SELECT 1", [], |_| Ok(()))?;
            Ok::<_, rusqlite::Error>(())
        })
        .await??;
        Ok(())
    }

    pub async fn utc_now(&self) -> Result<String, StorageError> {
        let connection = Arc::clone(&self.connection);
        let now = spawn_blocking(move || {
            connection.blocking_lock().query_row(
                "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')",
                [],
                |row| row.get(0),
            )
        })
        .await??;
        Ok(now)
    }

    pub async fn calendar(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<Meeting>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let result = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT id, season, round, name, country, location, start_date, end_date, \
                        country_code, status, source, fetched_at, source_updated_at, revision, jolpica_round_id \
                 FROM meetings WHERE (?1 IS NULL OR season = ?1) ORDER BY COALESCE(round, 9999), id",
            )?;
            let mut meetings = Vec::new();
            let rows = statement.query_map([season], |row| {
                Ok(Meeting {
                    id: row.get(0)?,
                    season: row.get(1)?,
                    round: row.get(2)?,
                    jolpica_round_id: row.get(14)?,
                    name: row.get(3)?,
                    country: row.get(4)?,
                    country_code: row.get(8)?,
                    location: row.get(5)?,
                    start_date: row.get(6)?,
                    end_date: row.get(7)?,
                    status: MeetingStatus::parse(&row.get::<_, String>(9)?),
                    sessions: Vec::new(),
                    source: row.get(10)?,
                    fetched_at: row.get(11)?,
                    source_updated_at: row.get(12)?,
                    revision: row.get(13)?,
                })
            })?;
            for row in rows {
                let mut meeting = row?;
                meeting.sessions = load_sessions(&connection, &meeting.id)?;
                meetings.push(meeting);
            }
            let meta = calendar_meta(&connection, season)?;
            Ok::<_, rusqlite::Error>((meetings, meta))
        })
        .await?
        .map_err(StorageError::from)?;

        Ok(result)
    }

    pub async fn next_meeting(
        &self,
        season: Option<i64>,
    ) -> Result<(Option<Meeting>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let result = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let now: String = connection.query_row(
                "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')",
                [],
                |row| row.get(0),
            )?;
            next_meeting_at(&connection, season, &now)
        })
        .await?
        .map_err(StorageError::from)?;
        Ok(result)
    }

    #[doc(hidden)]
    pub async fn next_meeting_at(
        &self,
        season: Option<i64>,
        now: &str,
    ) -> Result<(Option<Meeting>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let now = now.to_string();
        let result = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            next_meeting_at(&connection, season, &now)
        })
        .await?
        .map_err(StorageError::from)?;
        Ok(result)
    }

    pub async fn session_results(
        &self,
        session_id: &str,
    ) -> Result<(Vec<SessionResult>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let lookup_id = session_id.to_string();
        let results = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT session_id, position, classification, driver_id, driver_name, constructor_id, team, time, best_lap, q1, q2, q3, race_time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality
                 FROM session_results WHERE session_id = ?1 AND revision = (SELECT MAX(revision) FROM session_results WHERE session_id = ?1) ORDER BY position IS NULL, position",
            )?;
            let rows = statement.query_map([&lookup_id], |row| {
                Ok(SessionResult {
                    session_id: row.get(0)?,
                    position: row.get(1)?,
                    classification: row.get(2)?,
                    driver_id: row.get(3)?,
                    driver_name: row.get(4)?,
                    constructor_id: row.get(5)?,
                    team: row.get(6)?,
                    time: row.get(7)?,
                    best_lap: row.get(8)?,
                    q1: row.get(9)?,
                    q2: row.get(10)?,
                    q3: row.get(11)?,
                    race_time: row.get(12)?,
                    gap: row.get(13)?,
                    laps: row.get(14)?,
                    points: row.get(15)?,
                    source: row.get(16)?,
                    source_updated_at: row.get(17)?,
                    fetched_at: row.get(18)?,
                    revision: row.get(19)?,
                    quality: row.get(20)?,
                })
            })?;
            rows.collect::<Result<Vec<_>, _>>()
        }).await??;
        let meta = self.session_results_meta(session_id).await?;
        Ok((results, meta))
    }

    pub async fn session_exists(&self, session_id: &str) -> Result<bool, StorageError> {
        let connection = Arc::clone(&self.connection);
        let session_id = session_id.to_string();
        Ok(spawn_blocking(move || -> Result<bool, rusqlite::Error> {
            connection.blocking_lock().query_row(
                "SELECT EXISTS(SELECT 1 FROM sessions WHERE id = ?1)",
                [&session_id],
                |row| row.get(0),
            )
        })
        .await??)
    }

    async fn session_results_meta(&self, session_id: &str) -> Result<Meta, StorageError> {
        let connection = Arc::clone(&self.connection);
        let session_id = session_id.to_string();
        Ok(spawn_blocking(move || -> Result<Meta, rusqlite::Error> {
            let connection = connection.blocking_lock();
            connection.query_row(
                "SELECT source, source_updated_at, fetched_at, revision, quality, COALESCE(julianday('now') - julianday(fetched_at) > 0.25, 1)
                 FROM session_results WHERE session_id = ?1 ORDER BY revision DESC LIMIT 1",
                [&session_id],
                |row| {
                    let source: String = row.get(0)?;
                    let source_updated_at: Option<String> = row.get(1)?;
                    let fetched_at: String = row.get(2)?;
                    let revision: i64 = row.get(3)?;
                    let quality: String = row.get(4)?;
                    let stale: bool = row.get(5)?;
                    Ok(meta_from_snapshot(
                        source,
                        source_updated_at,
                        fetched_at,
                        revision,
                        &quality,
                        stale,
                    ))
                },
            ).optional().map(|meta| meta.unwrap_or_else(Meta::empty))
        }).await??)
    }

    pub async fn driver_standings(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<DriverStanding>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let rows = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT season, position, driver_id, driver_name, constructor, points, wins, source, fetched_at, revision, constructor_ids
                 FROM driver_standings WHERE season = COALESCE(?1, CAST(strftime('%Y','now') AS INTEGER)) ORDER BY position",
            )?;
            let rows = statement.query_map([season], |row| {
                Ok(DriverStanding {
                    season: row.get(0)?,
                    position: row.get(1)?,
                    driver_id: row.get(2)?,
                    driver_name: row.get(3)?,
                    constructor: row.get(4)?,
                    points: row.get(5)?,
                    wins: row.get(6)?,
                    source: row.get(7)?,
                    fetched_at: row.get(8)?,
                    revision: row.get(9)?,
                    constructor_ids: serde_json::from_str(&row.get::<_, String>(10)?).unwrap_or_default(),
                })
            })?;
            rows.collect::<Result<Vec<_>, _>>()
        }).await??;
        let meta = self.standings_meta("driver_standings", season).await?;
        Ok((rows, meta))
    }

    pub async fn constructor_standings(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<ConstructorStanding>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let rows = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT season, position, constructor_id, constructor_name, points, wins, source, fetched_at, revision
                 FROM constructor_standings WHERE season = COALESCE(?1, CAST(strftime('%Y','now') AS INTEGER)) ORDER BY position",
            )?;
            let rows = statement.query_map([season], |row| {
                Ok(ConstructorStanding {
                    season: row.get(0)?,
                    position: row.get(1)?,
                    constructor_id: row.get(2)?,
                    constructor_name: row.get(3)?,
                    points: row.get(4)?,
                    wins: row.get(5)?,
                    source: row.get(6)?,
                    fetched_at: row.get(7)?,
                    revision: row.get(8)?,
                })
            })?;
            rows.collect::<Result<Vec<_>, _>>()
        }).await??;
        let meta = self.standings_meta("constructor_standings", season).await?;
        Ok((rows, meta))
    }

    async fn standings_meta(
        &self,
        table: &'static str,
        season: Option<i64>,
    ) -> Result<Meta, StorageError> {
        let connection = Arc::clone(&self.connection);
        Ok(spawn_blocking(move || -> Result<Meta, rusqlite::Error> {
            let connection = connection.blocking_lock();
            let sql = format!("SELECT source, fetched_at, revision, COALESCE(julianday('now') - julianday(fetched_at) > 0.25, 1) FROM {table} WHERE season = COALESCE(?1, CAST(strftime('%Y','now') AS INTEGER)) ORDER BY revision DESC LIMIT 1");
            connection.query_row(&sql, [season], |row| {
                let source: String = row.get(0)?;
                let fetched_at: String = row.get(1)?;
                let revision: i64 = row.get(2)?;
                let stale: bool = row.get(3)?;
                Ok(Meta::from_cache(Some(source), Some(fetched_at), revision.max(0) as u64, stale))
            }).optional().map(|meta| meta.unwrap_or_else(Meta::empty))
        }).await??)
    }

    pub async fn replace_session_results(
        &self,
        mut rows: Vec<SessionResult>,
        quality: &str,
    ) -> Result<i64, StorageError> {
        let Some(session_id) = rows.first().map(|row| row.session_id.clone()) else {
            return Ok(0);
        };
        if rows.iter().any(|row| row.session_id != session_id) {
            return Err(StorageError::Sqlite(rusqlite::Error::InvalidQuery));
        }
        let quality = quality.to_string();
        for row in &mut rows {
            row.quality = quality.clone();
        }
        let connection = Arc::clone(&self.connection);
        Ok(spawn_blocking(move || -> Result<i64, rusqlite::Error> {
            let mut connection = connection.blocking_lock();
            let tx = connection.transaction()?;
            let mut old = load_latest_results(&tx, &session_id)?;
            old.sort_by(|a, b| a.driver_id.cmp(&b.driver_id));
            rows.sort_by(|a, b| a.driver_id.cmp(&b.driver_id));
            let current_revision = old.iter().map(|row| row.revision).max().unwrap_or(0);
            if !old.is_empty() && quality_rank(&quality) < quality_rank(&old[0].quality) {
                tx.rollback()?;
                return Ok(current_revision);
            }
            if quality == "partial"
                && old.first().is_some_and(|latest| latest.quality == "partial")
                && rows.len() < old.len()
            {
                tx.rollback()?;
                return Ok(current_revision);
            }
            let unchanged = old.len() == rows.len()
                && old.iter().zip(&rows).all(|(a, b)| same_result_content(a, b));
            let revision = if unchanged { current_revision } else { current_revision + 1 };
            for row in &mut rows {
                row.revision = revision;
                row.quality = quality.to_string();
            }
            if unchanged {
                for row in &rows {
                    tx.execute(
                        "UPDATE session_results SET source_updated_at=?1, fetched_at=?2, quality=?3 WHERE session_id=?4 AND revision=?5 AND driver_id=?6",
                        rusqlite::params![row.source_updated_at, row.fetched_at, quality, session_id, revision, row.driver_id],
                    )?;
                }
            } else {
                for row in &rows {
                    tx.execute(
                        "INSERT INTO session_results (session_id, position, classification, driver_id, driver_name, constructor_id, team, time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality, best_lap, q1, q2, q3, race_time)
                         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)",
                        rusqlite::params![row.session_id, row.position, row.classification, row.driver_id, row.driver_name, row.constructor_id, row.team, row.time, row.gap, row.laps, row.points, row.source, row.source_updated_at, row.fetched_at, revision, quality, row.best_lap, row.q1, row.q2, row.q3, row.race_time],
                    )?;
                }
            }
            tx.commit()?;
            Ok(revision)
        }).await??)
    }

    pub async fn replace_driver_standings(
        &self,
        rows: Vec<DriverStanding>,
    ) -> Result<i64, StorageError> {
        let Some(season) = rows.first().map(|row| row.season) else {
            return Ok(0);
        };
        let connection = Arc::clone(&self.connection);
        Ok(spawn_blocking(move || -> Result<i64, rusqlite::Error> {
            let mut connection = connection.blocking_lock();
            let tx = connection.transaction()?;
            let old_revision: i64 = tx.query_row("SELECT COALESCE(MAX(revision), 0) FROM driver_standings WHERE season=?1", [season], |row| row.get(0))?;
            let mut old = tx.prepare("SELECT position, driver_id, driver_name, constructor, points, wins, constructor_ids, source FROM driver_standings WHERE season=?1 ORDER BY position")?;
            let old_rows = old.query_map([season], |row| Ok((row.get::<_,i64>(0)?, row.get::<_,String>(1)?, row.get::<_,String>(2)?, row.get::<_,String>(3)?, row.get::<_,f64>(4)?, row.get::<_,i64>(5)?, row.get::<_,String>(6)?, row.get::<_,String>(7)?)))?.collect::<Result<Vec<_>,_>>()?;
            drop(old);
            let mut incoming = rows.clone();
            incoming.sort_by(|a,b| a.position.cmp(&b.position));
            let unchanged = old_rows.len() == incoming.len() && old_rows.iter().zip(&incoming).all(|(a,b)| a.0==b.position && a.1==b.driver_id && a.2==b.driver_name && a.3==b.constructor && a.4==b.points && a.5==b.wins && a.6==serde_json::to_string(&b.constructor_ids).unwrap_or_default() && a.7==b.source);
            let revision = if unchanged { old_revision } else { old_revision + 1 };
            tx.execute("DELETE FROM driver_standings WHERE season=?1", [season])?;
            for row in incoming {
                tx.execute("INSERT INTO driver_standings (season,position,driver_id,driver_name,constructor,points,wins,source,source_updated_at,fetched_at,revision,quality,constructor_ids) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,NULL,?9,?10,'provisional',?11)", rusqlite::params![row.season,row.position,row.driver_id,row.driver_name,row.constructor,row.points,row.wins,row.source,row.fetched_at,revision,serde_json::to_string(&row.constructor_ids).unwrap_or_else(|_| "[]".to_string())])?;
            }
            tx.commit()?;
            Ok(revision)
        }).await??)
    }

    pub async fn replace_constructor_standings(
        &self,
        rows: Vec<ConstructorStanding>,
    ) -> Result<i64, StorageError> {
        let Some(season) = rows.first().map(|row| row.season) else {
            return Ok(0);
        };
        let connection = Arc::clone(&self.connection);
        Ok(spawn_blocking(move || -> Result<i64, rusqlite::Error> {
            let mut connection = connection.blocking_lock();
            let tx = connection.transaction()?;
            let old_revision: i64 = tx.query_row("SELECT COALESCE(MAX(revision), 0) FROM constructor_standings WHERE season=?1", [season], |row| row.get(0))?;
            let mut old = tx.prepare("SELECT position,constructor_id,constructor_name,points,wins,source FROM constructor_standings WHERE season=?1 ORDER BY position")?;
            let old_rows = old.query_map([season], |row| Ok((row.get::<_,i64>(0)?,row.get::<_,String>(1)?,row.get::<_,String>(2)?,row.get::<_,f64>(3)?,row.get::<_,i64>(4)?,row.get::<_,String>(5)?)))?.collect::<Result<Vec<_>,_>>()?;
            drop(old);
            let mut incoming = rows;
            incoming.sort_by(|a,b| a.position.cmp(&b.position));
            let unchanged = old_rows.len() == incoming.len() && old_rows.iter().zip(&incoming).all(|(a,b)| a.0==b.position && a.1==b.constructor_id && a.2==b.constructor_name && a.3==b.points && a.4==b.wins && a.5==b.source);
            let revision = if unchanged { old_revision } else { old_revision + 1 };
            tx.execute("DELETE FROM constructor_standings WHERE season=?1", [season])?;
            for row in incoming {
                tx.execute("INSERT INTO constructor_standings (season,position,constructor_id,constructor_name,points,wins,source,source_updated_at,fetched_at,revision,quality) VALUES (?1,?2,?3,?4,?5,?6,?7,NULL,?8,?9,'provisional')", rusqlite::params![row.season,row.position,row.constructor_id,row.constructor_name,row.points,row.wins,row.source,row.fetched_at,revision])?;
            }
            tx.commit()?;
            Ok(revision)
        }).await??)
    }

    pub async fn store_provider_mappings(
        &self,
        drivers: Vec<(String, String, String)>,
        constructors: Vec<(String, String, String)>,
    ) -> Result<(), StorageError> {
        let connection = Arc::clone(&self.connection);
        spawn_blocking(move || {
            let mut connection = connection.blocking_lock();
            let tx = connection.transaction()?;
            for (provider, provider_id, canonical_id) in drivers {
                tx.execute("INSERT INTO driver_mappings(provider,provider_id,canonical_id) VALUES (?1,?2,?3) ON CONFLICT(provider,provider_id) DO UPDATE SET canonical_id=excluded.canonical_id", rusqlite::params![provider,provider_id,canonical_id])?;
            }
            for (provider, provider_id, canonical_id) in constructors {
                tx.execute("INSERT INTO constructor_mappings(provider,provider_id,canonical_id) VALUES (?1,?2,?3) ON CONFLICT(provider,provider_id) DO UPDATE SET canonical_id=excluded.canonical_id", rusqlite::params![provider,provider_id,canonical_id])?;
            }
            tx.commit()
        }).await??;
        Ok(())
    }

    pub async fn replace_calendar(
        &self,
        meetings: &[Meeting],
        fetched_at: &str,
    ) -> Result<u64, StorageError> {
        let meetings = meetings.to_vec();
        let fetched_at = fetched_at.to_string();
        let connection = Arc::clone(&self.connection);
        let revision = spawn_blocking(move || {
            upsert_calendar(&connection.blocking_lock(), &meetings, &fetched_at)
        })
        .await??;
        Ok(revision)
    }

    pub async fn user_version(&self) -> Result<i64, StorageError> {
        let connection = Arc::clone(&self.connection);
        let version = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            connection.query_row("PRAGMA user_version", [], |row| row.get(0))
        })
        .await??;
        Ok(version)
    }
}

fn meta_from_snapshot(
    source: String,
    source_updated_at: Option<String>,
    fetched_at: String,
    revision: i64,
    quality: &str,
    stale: bool,
) -> Meta {
    let quality = if stale {
        DataQuality::Stale
    } else {
        match quality {
            "partial" => DataQuality::Partial,
            "final" => DataQuality::Final,
            "pending" => DataQuality::Pending,
            _ => DataQuality::Provisional,
        }
    };
    Meta {
        schema_version: crate::domain::quality::SCHEMA_VERSION,
        revision: revision.max(0) as u64,
        stale,
        quality,
        source: Some(source),
        fetched_at: Some(fetched_at),
        source_updated_at,
    }
}

fn quality_rank(value: &str) -> u8 {
    match value {
        "partial" => 1,
        "provisional" => 2,
        "final" => 3,
        _ => 0,
    }
}

fn same_result_content(old: &SessionResult, new: &SessionResult) -> bool {
    let mut old = old.clone();
    let mut new = new.clone();
    old.fetched_at.clear();
    new.fetched_at.clear();
    old.source_updated_at = None;
    new.source_updated_at = None;
    old.revision = 0;
    new.revision = 0;
    old == new
}

fn load_latest_results(
    connection: &Connection,
    session_id: &str,
) -> Result<Vec<SessionResult>, rusqlite::Error> {
    let mut statement = connection.prepare(
        "SELECT session_id, position, classification, driver_id, driver_name, constructor_id, team, time, best_lap, q1, q2, q3, race_time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality
         FROM session_results WHERE session_id=?1 AND revision=(SELECT MAX(revision) FROM session_results WHERE session_id=?1) ORDER BY driver_id",
    )?;
    let rows = statement.query_map([session_id], |row| {
        Ok(SessionResult {
            session_id: row.get(0)?,
            position: row.get(1)?,
            classification: row.get(2)?,
            driver_id: row.get(3)?,
            driver_name: row.get(4)?,
            constructor_id: row.get(5)?,
            team: row.get(6)?,
            time: row.get(7)?,
            best_lap: row.get(8)?,
            q1: row.get(9)?,
            q2: row.get(10)?,
            q3: row.get(11)?,
            race_time: row.get(12)?,
            gap: row.get(13)?,
            laps: row.get(14)?,
            points: row.get(15)?,
            source: row.get(16)?,
            source_updated_at: row.get(17)?,
            fetched_at: row.get(18)?,
            revision: row.get(19)?,
            quality: row.get(20)?,
        })
    })?;
    rows.collect()
}

fn load_sessions(
    connection: &Connection,
    meeting_id: &str,
) -> Result<Vec<Session>, rusqlite::Error> {
    let mut statement = connection.prepare(
        "SELECT id, meeting_id, session_type, start_time, end_time, status, jolpica_session_id, openf1_session_key \
         FROM sessions WHERE meeting_id = ?1 ORDER BY start_time",
    )?;
    let rows = statement.query_map([meeting_id], |row| {
        let raw_type: String = row.get(2)?;
        Ok(Session {
            id: row.get(0)?,
            meeting_id: row.get(1)?,
            session_type: SessionType::parse(&raw_type).unwrap_or(SessionType::Race),
            start_time: row.get(3)?,
            end_time: row.get(4)?,
            status: SessionStatus::parse(&row.get::<_, String>(5)?),
            jolpica_session_id: row.get(6)?,
            openf1_session_key: row.get(7)?,
        })
    })?;
    rows.collect()
}

fn next_meeting_at(
    connection: &Connection,
    season: Option<i64>,
    now: &str,
) -> Result<(Option<Meeting>, Meta), rusqlite::Error> {
    let meeting_id = connection
        .query_row(
            "SELECT m.id FROM meetings m JOIN sessions s ON s.meeting_id = m.id \
             WHERE m.status = 'scheduled' AND s.status = 'scheduled' \
               AND (?1 IS NULL OR m.season = ?1) \
               AND julianday(s.start_time) >= julianday(?2) \
             ORDER BY julianday(s.start_time), s.id, m.id LIMIT 1",
            rusqlite::params![season, now],
            |row| row.get::<_, String>(0),
        )
        .optional()?;

    let meeting = match meeting_id {
        Some(id) => connection
            .query_row(
                "SELECT id, season, round, name, country, location, start_date, end_date, \
                        country_code, status, source, fetched_at, source_updated_at, revision, jolpica_round_id \
                 FROM meetings WHERE id = ?1",
                [&id],
                |row| {
                    Ok(Meeting {
                        id: row.get(0)?,
                        season: row.get(1)?,
                        round: row.get(2)?,
                        jolpica_round_id: row.get(14)?,
                        name: row.get(3)?,
                        country: row.get(4)?,
                        country_code: row.get(8)?,
                        location: row.get(5)?,
                        start_date: row.get(6)?,
                        end_date: row.get(7)?,
                        status: MeetingStatus::parse(&row.get::<_, String>(9)?),
                        sessions: Vec::new(),
                        source: row.get(10)?,
                        fetched_at: row.get(11)?,
                        source_updated_at: row.get(12)?,
                        revision: row.get(13)?,
                    })
                },
            )
            .optional()?
            .map(|mut meeting| {
                meeting.sessions = load_sessions(connection, &meeting.id)?;
                Ok::<_, rusqlite::Error>(meeting)
            })
            .transpose()?,
        None => None,
    };

    Ok((meeting, calendar_meta(connection, season)?))
}

fn calendar_meta(connection: &Connection, season: Option<i64>) -> Result<Meta, rusqlite::Error> {
    connection.query_row(
        "SELECT source, MAX(fetched_at), MAX(revision), \
                COALESCE(julianday('now') - julianday(MIN(fetched_at)) > 0.25, 1) \
         FROM meetings WHERE (?1 IS NULL OR season = ?1)",
        [season],
        |row| {
            let fetched_at: Option<String> = row.get(1)?;
            if fetched_at.is_none() {
                return Ok(Meta::empty());
            }
            Ok(Meta::from_cache(
                row.get(0)?,
                fetched_at,
                row.get::<_, Option<i64>>(2)?.unwrap_or(0) as u64,
                row.get(3)?,
            ))
        },
    )
}

fn apply_migrations(connection: &Connection) -> Result<(), StorageError> {
    let version: i64 = connection.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if version < 1 {
        connection.execute_batch(MIGRATION_0001)?;
        connection.execute_batch("PRAGMA user_version = 1;")?;
    }
    let version: i64 = connection.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if version < 2 {
        connection.execute_batch(MIGRATION_0002)?;
        connection.execute_batch("PRAGMA user_version = 2;")?;
    }
    let version: i64 = connection.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if version < 3 {
        connection.execute_batch(MIGRATION_0003)?;
        connection.execute_batch("PRAGMA user_version = 3;")?;
    }
    let version: i64 = connection.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if version < 4 {
        connection.execute_batch(MIGRATION_0004)?;
        connection.execute_batch("PRAGMA user_version = 4;")?;
    }
    Ok(())
}

fn upsert_calendar(
    connection: &Connection,
    meetings: &[Meeting],
    fetched_at: &str,
) -> Result<u64, rusqlite::Error> {
    let tx = connection.unchecked_transaction()?;
    let mut max_revision = 0_u64;
    for meeting in meetings {
        let existing = tx.query_row(
            "SELECT start_date, end_date, status, revision FROM meetings WHERE id = ?1",
            [&meeting.id],
            |row| {
                Ok((
                    row.get::<_, String>(0)?,
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, i64>(3)?,
                ))
            },
        );
        let revision = match existing {
            Ok((start, end, status, revision)) => {
                let changed = start != meeting.start_date
                    || end != meeting.end_date
                    || status != meeting.status.as_str();
                if changed { revision + 1 } else { revision }
            }
            Err(rusqlite::Error::QueryReturnedNoRows) => 1,
            Err(error) => return Err(error),
        };
        max_revision = max_revision.max(revision as u64);
        tx.execute(
            "INSERT INTO meetings (id, season, round, name, country, country_code, location, start_date, end_date, status, source, source_updated_at, fetched_at, revision, jolpica_round_id, openf1_meeting_key) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16) \
             ON CONFLICT(id) DO UPDATE SET season=excluded.season, round=excluded.round, name=excluded.name, country=excluded.country, country_code=excluded.country_code, location=excluded.location, start_date=excluded.start_date, end_date=excluded.end_date, status=excluded.status, source=excluded.source, source_updated_at=excluded.source_updated_at, fetched_at=excluded.fetched_at, revision=excluded.revision, jolpica_round_id=excluded.jolpica_round_id, openf1_meeting_key=excluded.openf1_meeting_key",
            rusqlite::params![meeting.id, meeting.season, meeting.round, meeting.name, meeting.country, meeting.country_code, meeting.location, meeting.start_date, meeting.end_date, meeting.status.as_str(), meeting.source.clone().unwrap_or_else(|| "jolpica-alpha".to_string()), meeting.source_updated_at, fetched_at, revision, meeting.jolpica_round_id, None::<i64>],
        )?;
        if let Some(round_id) = &meeting.jolpica_round_id {
            insert_mapping(&tx, "jolpica-alpha", round_id, Some(&meeting.id), None)?;
        }
        let mut seen = Vec::new();
        for session in &meeting.sessions {
            seen.push(session.id.clone());
            let existing_session = tx.query_row(
                "SELECT start_time, end_time, status, revision FROM sessions WHERE id = ?1",
                [&session.id],
                |row| {
                    Ok((
                        row.get::<_, String>(0)?,
                        row.get::<_, Option<String>>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, i64>(3)?,
                    ))
                },
            );
            let session_revision = match existing_session {
                Ok((start, end, status, revision)) => {
                    let changed = start != session.start_time
                        || end != session.end_time
                        || status != session.status.as_str();
                    if changed { revision + 1 } else { revision }
                }
                Err(rusqlite::Error::QueryReturnedNoRows) => 1,
                Err(error) => return Err(error),
            };
            tx.execute(
                "INSERT INTO sessions (id, meeting_id, session_type, start_time, end_time, status, source, provider_session_id, source_updated_at, fetched_at, revision, jolpica_session_id, openf1_session_key) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13) \
                 ON CONFLICT(id) DO UPDATE SET start_time=excluded.start_time, end_time=excluded.end_time, status=excluded.status, source=excluded.source, provider_session_id=excluded.provider_session_id, source_updated_at=excluded.source_updated_at, fetched_at=excluded.fetched_at, revision=excluded.revision, jolpica_session_id=excluded.jolpica_session_id, openf1_session_key=excluded.openf1_session_key",
                rusqlite::params![session.id, session.meeting_id, session.session_type.as_str(), session.start_time, session.end_time, session.status.as_str(), meeting.source.clone().unwrap_or_else(|| "jolpica-alpha".to_string()), session.jolpica_session_id, meeting.source_updated_at, fetched_at, session_revision, session.jolpica_session_id, session.openf1_session_key],
            )?;
            if let Some(provider_id) = &session.jolpica_session_id {
                insert_mapping(
                    &tx,
                    "jolpica-alpha",
                    provider_id,
                    Some(&meeting.id),
                    Some(&session.id),
                )?;
            }
            if let Some(key) = session.openf1_session_key {
                insert_mapping(
                    &tx,
                    "openf1",
                    &key.to_string(),
                    Some(&meeting.id),
                    Some(&session.id),
                )?;
            }
        }
        let placeholders = seen.iter().map(|_| "?").collect::<Vec<_>>().join(",");
        if !seen.is_empty() {
            let sql = format!(
                "DELETE FROM sessions WHERE meeting_id = ?1 AND id NOT IN ({placeholders})"
            );
            let mut params: Vec<&dyn rusqlite::ToSql> = vec![&meeting.id];
            for id in &seen {
                params.push(id);
            }
            tx.execute(&sql, params.as_slice())?;
        }
    }
    tx.commit()?;
    Ok(max_revision)
}

fn insert_mapping(
    tx: &rusqlite::Transaction,
    provider: &str,
    provider_id: &str,
    meeting_id: Option<&str>,
    session_id: Option<&str>,
) -> Result<(), rusqlite::Error> {
    tx.execute(
        "INSERT INTO provider_mappings (provider, provider_id, meeting_id, session_id) VALUES (?1, ?2, ?3, ?4) \
         ON CONFLICT(provider, provider_id) DO UPDATE SET meeting_id=excluded.meeting_id, session_id=excluded.session_id",
        rusqlite::params![provider, provider_id, meeting_id, session_id],
    )?;
    Ok(())
}
