use std::{path::Path, sync::Arc};

use rusqlite::Connection;
use tokio::{sync::Mutex, task::spawn_blocking};

use crate::{
    api::dto::Meta,
    domain::{
        calendar::Meeting,
        results::SessionResult,
        standings::{ConstructorStanding, DriverStanding},
    },
    error::StorageError,
};

const MIGRATION_0001: &str = include_str!("migrations/0001_init.sql");

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
        spawn_blocking(move || {
            let connection = connection.blocking_lock();
            connection.execute_batch(MIGRATION_0001)?;
            connection.execute_batch("PRAGMA user_version = 1;")?;
            Ok::<_, rusqlite::Error>(())
        })
        .await??;
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

    pub async fn calendar(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<Meeting>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let result = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT id, season, round, name, country, location, start_date, end_date \
                 FROM meetings WHERE (?1 IS NULL OR season = ?1) ORDER BY round",
            )?;
            let mut meetings = Vec::new();
            let rows = statement.query_map([season], |row| {
                Ok(Meeting {
                    id: row.get(0)?,
                    season: row.get(1)?,
                    round: row.get(2)?,
                    name: row.get(3)?,
                    country: row.get(4)?,
                    location: row.get(5)?,
                    start_date: row.get(6)?,
                    end_date: row.get(7)?,
                    sessions: Vec::new(),
                })
            })?;
            for row in rows {
                meetings.push(row?);
            }
            Ok::<_, rusqlite::Error>(meetings)
        })
        .await??;

        Ok((result, Meta::empty()))
    }

    pub async fn next_meeting(&self) -> Result<(Option<Meeting>, Meta), StorageError> {
        let (meetings, meta) = self.calendar(None).await?;
        Ok((meetings.into_iter().next(), meta))
    }

    pub async fn session_results(
        &self,
        session_id: &str,
    ) -> Result<(Vec<SessionResult>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let session_id = session_id.to_string();
        let result = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT session_id, position, classification, driver_id, driver_name, team, time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality \
                 FROM session_results WHERE session_id = ?1 ORDER BY position",
            )?;
            let mut results = Vec::new();
            let rows = statement.query_map([&session_id], |row| {
                Ok(SessionResult {
                    session_id: row.get(0)?,
                    position: row.get(1)?,
                    classification: row.get(2)?,
                    driver_id: row.get(3)?,
                    driver_name: row.get(4)?,
                    team: row.get(5)?,
                    time: row.get(6)?,
                    gap: row.get(7)?,
                    laps: row.get(8)?,
                    points: row.get(9)?,
                    source: row.get(10)?,
                    source_updated_at: row.get(11)?,
                    fetched_at: row.get(12)?,
                    revision: row.get(13)?,
                    quality: row.get(14)?,
                })
            })?;
            for row in rows {
                results.push(row?);
            }
            Ok::<_, rusqlite::Error>(results)
        })
        .await??;
        Ok((result, Meta::empty()))
    }

    pub async fn driver_standings(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<DriverStanding>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let result = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT season, position, driver_id, driver_name, constructor, points, wins, source, fetched_at, revision \
                 FROM driver_standings WHERE (?1 IS NULL OR season = ?1) ORDER BY position",
            )?;
            let mut standings = Vec::new();
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
                })
            })?;
            for row in rows {
                standings.push(row?);
            }
            Ok::<_, rusqlite::Error>(standings)
        })
        .await??;
        Ok((result, Meta::empty()))
    }

    pub async fn constructor_standings(
        &self,
        season: Option<i64>,
    ) -> Result<(Vec<ConstructorStanding>, Meta), StorageError> {
        let connection = Arc::clone(&self.connection);
        let result = spawn_blocking(move || {
            let connection = connection.blocking_lock();
            let mut statement = connection.prepare(
                "SELECT season, position, constructor_id, constructor_name, points, wins, source, fetched_at, revision \
                 FROM constructor_standings WHERE (?1 IS NULL OR season = ?1) ORDER BY position",
            )?;
            let mut standings = Vec::new();
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
            for row in rows {
                standings.push(row?);
            }
            Ok::<_, rusqlite::Error>(standings)
        })
        .await??;
        Ok((result, Meta::empty()))
    }
}
