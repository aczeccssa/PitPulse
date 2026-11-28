use std::path::Path;

use rusqlite::{Connection, OpenFlags, types::ValueRef};
use serde_json::{Map, Value};

use crate::{error::StorageError, services::FIRST_SEASON};

use super::Postgres;

struct Table {
    name: &'static str,
    key: &'static [&'static str],
    scope: &'static str,
    skip_id: bool,
}

const TABLES: &[Table] = &[
    Table {
        name: "meetings",
        key: &["id"],
        scope: "season >= ?1",
        skip_id: false,
    },
    Table {
        name: "sessions",
        key: &["id"],
        scope: "meeting_id IN (SELECT id FROM meetings WHERE season >= ?1)",
        skip_id: false,
    },
    Table {
        name: "session_results",
        key: &["session_id", "revision", "driver_id"],
        scope: "session_id IN (SELECT s.id FROM sessions s JOIN meetings m ON m.id = s.meeting_id WHERE m.season >= ?1)",
        skip_id: true,
    },
    Table {
        name: "driver_standings",
        key: &["season", "driver_id"],
        scope: "season >= ?1",
        skip_id: true,
    },
    Table {
        name: "constructor_standings",
        key: &["season", "constructor_id"],
        scope: "season >= ?1",
        skip_id: true,
    },
    Table {
        name: "provider_mappings",
        key: &["provider", "provider_id"],
        scope: "(meeting_id IS NULL AND session_id IS NULL) OR meeting_id IN (SELECT id FROM meetings WHERE season >= ?1) OR session_id IN (SELECT s.id FROM sessions s JOIN meetings m ON m.id = s.meeting_id WHERE m.season >= ?1)",
        skip_id: false,
    },
    Table {
        name: "driver_mappings",
        key: &["provider", "provider_id"],
        scope: "?1 IS NOT NULL",
        skip_id: false,
    },
    Table {
        name: "constructor_mappings",
        key: &["provider", "provider_id"],
        scope: "?1 IS NOT NULL",
        skip_id: false,
    },
    Table {
        name: "provider_identity_cache",
        key: &["season"],
        scope: "season >= ?1",
        skip_id: false,
    },
    Table {
        name: "calendar_snapshots",
        key: &["season"],
        scope: "season >= ?1",
        skip_id: false,
    },
    Table {
        name: "next_season_schedule",
        key: &["season"],
        scope: "season >= ?1",
        skip_id: false,
    },
];

struct Snapshot {
    table: &'static Table,
    rows: Vec<Value>,
    excluded: i64,
}

#[derive(Debug, serde::Serialize)]
pub struct ImportCount {
    pub table: &'static str,
    pub source: usize,
    pub excluded: i64,
    pub inserted: u64,
    pub verified: u64,
}

impl Postgres {
    /// Check source natural keys and every column. Existing conflicting values
    /// abort the entire transaction instead of overwriting a newer publication.
    pub async fn import_sqlite(
        &self,
        source: &Path,
        check_only: bool,
    ) -> Result<Vec<ImportCount>, StorageError> {
        let source = source.to_owned();
        let snapshots = tokio::task::spawn_blocking(move || load(&source)).await??;
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        let mut report = Vec::with_capacity(snapshots.len());
        let mut changed = false;
        for snapshot in snapshots {
            let Table { name, key, .. } = snapshot.table;
            let incoming = format!("jsonb_populate_recordset(NULL::{name}, $1)");
            let keys = key.join(", ");
            let insert = format!(
                "INSERT INTO {name} SELECT src.* FROM {incoming} src ON CONFLICT ({keys}) DO NOTHING"
            );
            let check = format!(
                "SELECT count(*) FROM {incoming} src JOIN {name} dest USING ({keys}) WHERE to_jsonb(src) = to_jsonb(dest)"
            );
            let mut count = ImportCount {
                table: name,
                source: snapshot.rows.len(),
                excluded: snapshot.excluded,
                inserted: 0,
                verified: 0,
            };
            for batch in snapshot.rows.chunks(500) {
                let batch = Value::Array(batch.to_vec());
                if !check_only {
                    count.inserted += tx.execute(&insert, &[&batch]).await?;
                }
                let verified: i64 = tx.query_one(&check, &[&batch]).await?.get(0);
                count.verified += verified as u64;
            }
            if count.verified != count.source as u64 {
                return Err(StorageError::SeasonImport(format!(
                    "{name}: matched {} of {} source rows",
                    count.verified, count.source
                )));
            }
            changed |= count.inserted != 0;
            report.push(count);
        }
        if changed {
            tx.execute(
                "UPDATE dataset_generation SET generation = generation + 1 WHERE singleton",
                &[],
            )
            .await?;
        }
        tx.commit().await?;
        Ok(report)
    }
}

fn load(path: &Path) -> Result<Vec<Snapshot>, StorageError> {
    let mut connection = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    let tx = connection.transaction()?;
    let version: i64 = tx.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if !matches!(version, 11 | 12) {
        return Err(StorageError::SeasonImport(format!(
            "expected a migrated SQLite v11 or v12 snapshot, got v{version}"
        )));
    }
    for table in ["sessions", "session_results"] {
        let violated: bool = tx.query_row(
            &format!("SELECT EXISTS(SELECT 1 FROM pragma_foreign_key_check('{table}'))"),
            [],
            |row| row.get(0),
        )?;
        if violated {
            return Err(StorageError::SeasonImport(format!(
                "{table}: SQLite foreign key check failed"
            )));
        }
    }
    let mut snapshots = Vec::with_capacity(TABLES.len());
    for table in TABLES {
        let total: i64 =
            tx.query_row(&format!("SELECT count(*) FROM {}", table.name), [], |row| {
                row.get(0)
            })?;
        let sql = format!(
            "SELECT * FROM {} WHERE {} ORDER BY {}",
            table.name,
            table.scope,
            table.key.join(", ")
        );
        let mut stmt = tx.prepare(&sql)?;
        let columns: Vec<String> = stmt
            .column_names()
            .iter()
            .map(ToString::to_string)
            .collect();
        let mut rows = stmt.query([FIRST_SEASON])?;
        let mut values = Vec::new();
        while let Some(row) = rows.next()? {
            let mut record = Map::new();
            for (index, name) in columns.iter().enumerate() {
                if table.skip_id && name == "id" {
                    continue;
                }
                let value = match row.get_ref(index)? {
                    ValueRef::Null => Value::Null,
                    ValueRef::Integer(value) => Value::from(value),
                    ValueRef::Real(value) if value.is_finite() => Value::from(value),
                    ValueRef::Text(value) => {
                        Value::from(std::str::from_utf8(value).map_err(|_| {
                            StorageError::SeasonImport(format!(
                                "{}: invalid UTF-8 in {name}",
                                table.name
                            ))
                        })?)
                    }
                    _ => {
                        return Err(StorageError::SeasonImport(format!(
                            "{}: unsupported value in {name}",
                            table.name
                        )));
                    }
                };
                record.insert(name.clone(), value);
            }
            values.push(Value::Object(record));
        }
        snapshots.push(Snapshot {
            table,
            excluded: total - values.len() as i64,
            rows: values,
        });
    }
    Ok(snapshots)
}
