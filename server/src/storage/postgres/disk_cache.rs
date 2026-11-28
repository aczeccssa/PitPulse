//! Instance-local, disposable storage for generation-tagged season data.
use std::{
    path::Path,
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use rusqlite::{Connection, OptionalExtension, params};
use tokio::task::spawn_blocking;

use crate::error::StorageError;

// Leave room for SQLite indexes/page overhead. PRAGMA max_page_count also
// bounds the database itself, independently of our LRU payload accounting.
const PAGE_SIZE: u64 = 4096;
const ENTRY_OVERHEAD: u64 = 256;

#[derive(Clone)]
pub(super) struct DiskCache {
    connection: Arc<Mutex<Connection>>,
    budget: u64,
}

pub(super) struct Stored {
    pub generation: i64,
    pub loaded_at: i64,
    pub can_fallback: bool,
    pub bytes: Vec<u8>,
}

impl DiskCache {
    pub async fn open(
        path: &Path,
        namespace: String,
        max_bytes: u64,
    ) -> Result<Self, StorageError> {
        let path = path.to_owned();
        let connection = spawn_blocking(move || -> Result<_, StorageError> {
            let mut connection = Connection::open(path)?;
            connection.busy_timeout(Duration::from_millis(500))?;
            // The file contains derivative data only. A crash discards any
            // uncommitted transaction. Incremental vacuum reuses freed pages.
            connection.execute_batch(
                "PRAGMA journal_mode=DELETE; PRAGMA auto_vacuum=INCREMENTAL; PRAGMA cache_size=-2048;
                 CREATE TABLE IF NOT EXISTS identity (namespace TEXT NOT NULL);
                 CREATE TABLE IF NOT EXISTS entries (
                     key TEXT PRIMARY KEY, generation INTEGER NOT NULL, loaded_at INTEGER NOT NULL,
                     can_fallback INTEGER NOT NULL, used INTEGER NOT NULL, bytes BLOB NOT NULL
                 ) WITHOUT ROWID;
                 CREATE INDEX IF NOT EXISTS entries_lru ON entries(used, key);
                 CREATE TABLE IF NOT EXISTS confirmed (id INTEGER PRIMARY KEY CHECK(id=1),
                     generation INTEGER NOT NULL, checked_at INTEGER NOT NULL);",
            )?;
            let tx = connection.transaction()?;
            let previous: Option<String> = tx
                .query_row("SELECT namespace FROM identity", [], |r| r.get(0))
                .optional()?;
            if previous.as_deref() != Some(&namespace) {
                tx.execute_batch("DELETE FROM entries; DELETE FROM confirmed; DELETE FROM identity;")?;
                tx.execute("INSERT INTO identity VALUES (?1)", [namespace])?;
            }
            trim(&tx, max_bytes * 3 / 4)?;
            tx.commit()?;
            connection.execute_batch("PRAGMA incremental_vacuum;")?;
            let limit = max_bytes / PAGE_SIZE;
            let pages: u64 = connection.query_row(&format!("PRAGMA max_page_count={limit}"), [], |row| row.get(0))?;
            if pages > limit {
                // A lowered budget can be smaller than the physical file even
                // after trimming. Clear the disposable data and shrink it.
                connection.execute_batch("DELETE FROM entries; DELETE FROM confirmed; VACUUM;")?;
                connection.pragma_update(None, "max_page_count", limit)?;
            }
            Ok(connection)
        })
        .await??;
        Ok(Self {
            connection: Arc::new(Mutex::new(connection)),
            budget: max_bytes * 3 / 4,
        })
    }

    pub async fn read(&self, key: String) -> Option<Stored> {
        self.run(move |db| {
            let result = db
                .query_row(
                    "SELECT generation, loaded_at, can_fallback, bytes FROM entries WHERE key=?1",
                    [&key],
                    |row| {
                        Ok(Stored {
                            generation: row.get(0)?,
                            loaded_at: row.get(1)?,
                            can_fallback: row.get(2)?,
                            bytes: row.get(3)?,
                        })
                    },
                )
                .optional()?;
            if result.is_some() {
                db.execute(
                    "UPDATE entries SET used=MAX(used+1, ?2) WHERE key=?1",
                    params![key, epoch_micros()],
                )?;
            }
            Ok(result)
        })
        .await
        .flatten()
    }

    pub async fn write(&self, key: String, stored: Stored) {
        let size = stored.bytes.len() as u64 + ENTRY_OVERHEAD;
        if size > self.budget {
            return;
        }
        let budget = self.budget;
        self.run(move |db| {
            let tx = db.transaction()?;
            tx.execute("DELETE FROM entries WHERE key=?1", [&key])?;
            trim(&tx, budget - size)?;
            tx.execute(
                "INSERT INTO entries VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![
                    key,
                    stored.generation,
                    stored.loaded_at,
                    stored.can_fallback,
                    epoch_micros(),
                    stored.bytes
                ],
            )?;
            tx.commit()
        })
        .await;
    }

    pub async fn confirmation(&self) -> Option<(i64, i64)> {
        self.run(|db| {
            db.query_row(
                "SELECT generation, checked_at FROM confirmed WHERE id=1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
        })
        .await
        .flatten()
    }

    pub async fn confirm(&self, generation: i64, checked_at: i64) {
        self.run(move |db| {
            db.execute(
                "INSERT INTO confirmed VALUES(1, ?1, ?2) ON CONFLICT(id) DO UPDATE SET
                 generation=excluded.generation, checked_at=excluded.checked_at",
                params![generation, checked_at],
            )
        })
        .await;
    }

    pub async fn bytes(&self) -> Option<u64> {
        self.run(|db| {
            db.query_row(
                "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()",
                [],
                |r| r.get(0),
            )
        })
        .await
    }

    async fn run<T: Send + 'static>(
        &self,
        operation: impl FnOnce(&mut Connection) -> rusqlite::Result<T> + Send + 'static,
    ) -> Option<T> {
        let connection = self.connection.clone();
        match spawn_blocking(move || operation(&mut connection.lock().expect("season disk cache")))
            .await
        {
            Ok(Ok(value)) => Some(value),
            Ok(Err(error)) => {
                tracing::warn!(%error, "local season cache I/O failed");
                None
            }
            Err(error) => {
                tracing::warn!(%error, "local season cache worker failed");
                None
            }
        }
    }
}

fn trim(db: &Connection, budget: u64) -> rusqlite::Result<()> {
    // Window sum walks the oldest entries once, only when eviction is needed.
    let bytes: u64 = db.query_row(
        "SELECT COALESCE(SUM(length(bytes)+?1),0) FROM entries",
        [ENTRY_OVERHEAD],
        |r| r.get(0),
    )?;
    if bytes > budget {
        db.execute(
            "DELETE FROM entries WHERE key IN (SELECT key FROM (
                 SELECT key, SUM(length(bytes)+?1) OVER (ORDER BY used DESC, key DESC) AS retained
                 FROM entries
             ) WHERE retained>?2)",
            params![ENTRY_OVERHEAD, budget],
        )?;
    }
    Ok(())
}

fn epoch_micros() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_micros() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(value: &[u8]) -> Stored {
        Stored {
            generation: 7,
            loaded_at: 100,
            can_fallback: true,
            bytes: value.to_vec(),
        }
    }

    #[tokio::test]
    async fn disk_cache_persists_generation_and_isolates_origins() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cache.sqlite");
        let first = DiskCache::open(&path, "database-a:schema".into(), 1024 * 1024)
            .await
            .unwrap();
        first.write("calendar:2026".into(), entry(b"season")).await;
        first.confirm(7, 100).await;
        assert_eq!(first.confirmation().await, Some((7, 100)));
        assert_eq!(
            first.read("calendar:2026".into()).await.unwrap().bytes,
            b"season"
        );
        drop(first);
        let reopened = DiskCache::open(&path, "database-a:schema".into(), 1024 * 1024)
            .await
            .unwrap();
        assert_eq!(reopened.confirmation().await, Some((7, 100)));
        assert_eq!(
            reopened
                .read("calendar:2026".into())
                .await
                .unwrap()
                .generation,
            7
        );
        drop(reopened);
        let other = DiskCache::open(&path, "database-b:schema".into(), 1024 * 1024)
            .await
            .unwrap();
        assert!(other.read("calendar:2026".into()).await.is_none());
        assert!(other.confirmation().await.is_none());
    }

    #[tokio::test]
    async fn disk_cache_lru_and_file_budget_are_bounded() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("cache.sqlite");
        let cache = DiskCache::open(&path, "database:schema".into(), 128 * 1024)
            .await
            .unwrap();
        for index in 0..40 {
            let key = format!("entry:{index}");
            let payload = vec![index as u8; 12 * 1024];
            cache.write(key.clone(), entry(&payload)).await;
        }
        assert!(cache.bytes().await.unwrap() <= 128 * 1024);
        assert!(cache.read("entry:39".into()).await.is_some());
        assert!(cache.read("entry:0".into()).await.is_none());
    }
}
