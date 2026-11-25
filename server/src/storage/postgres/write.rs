//! Only the headless publisher calls these methods. Each logical snapshot and
//! its reader generation are committed together, under the import/write lock.
use std::collections::{BTreeMap, BTreeSet};

use deadpool_postgres::Transaction;
use serde_json::{Value, json};

use crate::{
    domain::{
        calendar::Meeting,
        results::SessionResult,
        standings::{ConstructorStanding, DriverStanding},
    },
    error::StorageError,
    providers::f1_schedule::ScheduleEvent,
    services::FIRST_SEASON,
    storage::sqlite::{quality_rank, same_result_content, stable_calendar_hash},
};

use super::{
    Postgres,
    read::{RESULT_COLUMNS, session_result},
};

async fn finish(tx: Transaction<'_>, changed: bool) -> Result<(), StorageError> {
    if changed {
        tx.execute(
            "UPDATE dataset_generation SET generation = generation + 1 WHERE singleton",
            &[],
        )
        .await?;
    }
    tx.commit().await?;
    Ok(())
}

fn supported(season: i64) -> Result<(), StorageError> {
    if !(FIRST_SEASON..=9999).contains(&season) {
        return Err(StorageError::SeasonDataInvalid);
    }
    Ok(())
}

// All current publisher timestamps are normalized UTC. Imported timestamps
// can carry offsets, so compare through the same parser used by readers.
async fn older(tx: &Transaction<'_>, previous: &str, incoming: &str) -> Result<bool, StorageError> {
    let row = tx
        .query_one(
            "SELECT COALESCE(season_timestamp($1) > season_timestamp($2), FALSE)",
            &[&previous, &incoming],
        )
        .await?;
    Ok(row.get(0))
}

impl Postgres {
    pub(crate) async fn replace_session_results(
        &self,
        mut rows: Vec<SessionResult>,
        quality: &str,
    ) -> Result<i64, StorageError> {
        let Some(first) = rows.first() else {
            return Ok(0);
        };
        let session_id = first.session_id.clone();
        let fetched_at = first.fetched_at.clone();
        let mut drivers = BTreeSet::new();
        if rows.iter().any(|row| {
            row.session_id != session_id
                || row.fetched_at != fetched_at
                || row.driver_id.is_empty()
                || !drivers.insert(row.driver_id.as_str())
                || row.points.is_some_and(|points| !points.is_finite())
        }) || quality_rank(quality) == 0
        {
            return Err(StorageError::SeasonDataInvalid);
        }
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        let season = tx.query_opt("SELECT m.season FROM meetings m JOIN sessions s ON s.meeting_id = m.id WHERE s.id = $1", &[&session_id]).await?
            .ok_or(StorageError::SeasonDataInvalid)?.get(0);
        supported(season)?;
        let old = tx.query(&format!(
            "SELECT {RESULT_COLUMNS} FROM session_results WHERE session_id = $1 AND revision =
             (SELECT MAX(revision) FROM session_results WHERE session_id = $1) ORDER BY driver_id COLLATE \"C\""
        ), &[&session_id]).await?.iter().map(session_result).collect::<Result<Vec<_>, _>>()?;
        let revision = old.first().map_or(0, |row| row.revision);
        if let Some(previous) = old.first() {
            if older(&tx, &previous.fetched_at, &fetched_at).await? {
                return Ok(revision);
            }
            if quality_rank(quality) < quality_rank(&previous.quality)
                || (quality == "partial" && previous.quality == "partial" && rows.len() < old.len())
            {
                // A lower-quality candidate can repair missing fields on matching
                // rows, but cannot replace a classification or freshen its source.
                let incoming = rows;
                rows = old.clone();
                for row in &mut rows {
                    if let Some(new) = incoming.iter().find(|new| {
                        new.driver_id == row.driver_id
                            && new.driver_name == row.driver_name
                            && new.constructor_id == row.constructor_id
                            && new.team == row.team
                            && new.source == row.source
                            && new.position == row.position
                            && new.classification == row.classification
                            && new.time == row.time
                    }) {
                        row.best_lap = row.best_lap.clone().or_else(|| new.best_lap.clone());
                        row.driver_number = row
                            .driver_number
                            .clone()
                            .or_else(|| new.driver_number.clone());
                        row.q1 = row.q1.clone().or_else(|| new.q1.clone());
                        row.q2 = row.q2.clone().or_else(|| new.q2.clone());
                        row.q3 = row.q3.clone().or_else(|| new.q3.clone());
                        row.race_time = row.race_time.clone().or_else(|| new.race_time.clone());
                    }
                }
            } else {
                for row in &mut rows {
                    row.quality = quality.to_owned();
                }
            }
        } else {
            for row in &mut rows {
                row.quality = quality.to_owned();
            }
        }
        rows.sort_by(|a, b| a.driver_id.cmp(&b.driver_id));
        let same_content = rows.len() == old.len()
            && rows
                .iter()
                .zip(&old)
                .all(|(a, b)| same_result_content(a, b));
        let revision = if same_content { revision } else { revision + 1 };
        for row in &mut rows {
            row.revision = revision;
        }
        if rows == old {
            return Ok(revision);
        }
        let incoming = Value::Array(rows.iter().map(|row| json!({
            "session_id":row.session_id,"position":row.position,"classification":row.classification,
            "driver_id":row.driver_id,"driver_number":row.driver_number,"driver_name":row.driver_name,
            "constructor_id":row.constructor_id,"team":row.team,"time":row.time,"best_lap":row.best_lap,
            "q1":row.q1,"q2":row.q2,"q3":row.q3,"race_time":row.race_time,"gap":row.gap,"laps":row.laps,
            "points":row.points,"source":row.source,"source_updated_at":row.source_updated_at,
            "fetched_at":row.fetched_at,"revision":row.revision,"quality":row.quality
        })).collect());
        tx.execute("INSERT INTO session_results SELECT * FROM jsonb_populate_recordset(NULL::session_results, $1)
            ON CONFLICT (session_id, revision, driver_id) DO UPDATE SET
            source_updated_at = excluded.source_updated_at, fetched_at = excluded.fetched_at", &[&incoming]).await?;
        finish(tx, true).await?;
        Ok(revision)
    }

    pub(crate) async fn replace_driver_standings(
        &self,
        rows: Vec<DriverStanding>,
    ) -> Result<i64, StorageError> {
        let Some(first) = rows.first() else {
            return Ok(0);
        };
        let season = first.season;
        let mut incoming = Vec::with_capacity(rows.len());
        for row in rows {
            if row.season != season || row.driver_id.is_empty() || !row.points.is_finite() {
                return Err(StorageError::SeasonDataInvalid);
            }
            incoming.push(json!({
                "season":row.season,"position":row.position,"driver_id":row.driver_id,
                "driver_number":row.driver_number,"driver_name":row.driver_name,"constructor":row.constructor,
                "constructor_ids":serde_json::to_string(&row.constructor_ids).map_err(|_| StorageError::SeasonDataInvalid)?,
                "points":row.points,"wins":row.wins,"source":row.source,"fetched_at":row.fetched_at
            }));
        }
        self.replace_standings("driver_standings", "driver_id", season, incoming)
            .await
    }

    pub(crate) async fn replace_constructor_standings(
        &self,
        rows: Vec<ConstructorStanding>,
    ) -> Result<i64, StorageError> {
        let Some(first) = rows.first() else {
            return Ok(0);
        };
        let season = first.season;
        let mut incoming = Vec::with_capacity(rows.len());
        for row in rows {
            if row.season != season || row.constructor_id.is_empty() || !row.points.is_finite() {
                return Err(StorageError::SeasonDataInvalid);
            }
            incoming.push(json!({
                "season":row.season,"position":row.position,"constructor_id":row.constructor_id,
                "constructor_name":row.constructor_name,"points":row.points,"wins":row.wins,
                "source":row.source,"fetched_at":row.fetched_at
            }));
        }
        self.replace_standings("constructor_standings", "constructor_id", season, incoming)
            .await
    }

    async fn replace_standings(
        &self,
        table: &str,
        key: &str,
        season: i64,
        mut rows: Vec<Value>,
    ) -> Result<i64, StorageError> {
        supported(season)?;
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        let old = tx
            .query(
                &format!(
                    "SELECT to_jsonb(t) FROM {table} t WHERE season=$1 ORDER BY {key} COLLATE \"C\""
                ),
                &[&season],
            )
            .await?
            .into_iter()
            .map(|row| row.get::<_, Value>(0))
            .collect::<Vec<_>>();
        rows.sort_by(|a, b| a[key].as_str().cmp(&b[key].as_str()));
        let revision = old
            .iter()
            .filter_map(|row| row["revision"].as_i64())
            .max()
            .unwrap_or(0);
        let fetched_at = rows[0]["fetched_at"]
            .as_str()
            .ok_or(StorageError::SeasonDataInvalid)?;
        if rows
            .iter()
            .any(|row| row["fetched_at"].as_str() != Some(fetched_at))
            || rows.windows(2).any(|pair| pair[0][key] == pair[1][key])
        {
            return Err(StorageError::SeasonDataInvalid);
        }
        if let Some(previous) = old.first().and_then(|row| row["fetched_at"].as_str())
            && older(&tx, previous, fetched_at).await?
        {
            return Ok(revision);
        }
        let same_content = old.len() == rows.len()
            && old.iter().zip(&rows).all(|(a, b)| {
                b.as_object().is_some_and(|obj| {
                    obj.iter().all(|(column, value)| {
                        column == "fetched_at"
                            || if column == "points" {
                                a[column].as_f64() == value.as_f64()
                            } else {
                                a[column] == *value
                            }
                    })
                })
            });
        let revision = if same_content { revision } else { revision + 1 };
        for (index, row) in rows.iter_mut().enumerate() {
            row["revision"] = json!(revision);
            row["quality"] = if same_content {
                old[index]["quality"].clone()
            } else {
                json!("provisional")
            };
            row["source_updated_at"] = if same_content {
                old[index]["source_updated_at"].clone()
            } else {
                Value::Null
            };
        }
        if same_content
            && old
                .iter()
                .zip(&rows)
                .all(|(a, b)| a["fetched_at"] == b["fetched_at"])
        {
            return Ok(revision);
        }
        tx.execute(&format!("DELETE FROM {table} WHERE season=$1"), &[&season])
            .await?;
        tx.execute(
            &format!(
                "INSERT INTO {table} SELECT * FROM jsonb_populate_recordset(NULL::{table}, $1)"
            ),
            &[&Value::Array(rows)],
        )
        .await?;
        finish(tx, true).await?;
        Ok(revision)
    }

    pub(crate) async fn save_identity_cache(
        &self,
        season: i64,
        drivers: &[Value],
        constructors: &[Value],
        fetched_at: &str,
    ) -> Result<(), StorageError> {
        supported(season)?;
        if drivers.is_empty() || constructors.is_empty() {
            return Ok(());
        }
        let drivers =
            serde_json::to_string(drivers).map_err(|_| StorageError::SeasonDataInvalid)?;
        let constructors =
            serde_json::to_string(constructors).map_err(|_| StorageError::SeasonDataInvalid)?;
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        let changed = tx.execute(
            "INSERT INTO provider_identity_cache VALUES ($1,$2,$3,$4) ON CONFLICT (season) DO UPDATE
             SET drivers_json=excluded.drivers_json, constructors_json=excluded.constructors_json, fetched_at=excluded.fetched_at
             WHERE (provider_identity_cache.drivers_json, provider_identity_cache.constructors_json, provider_identity_cache.fetched_at)
             IS DISTINCT FROM (excluded.drivers_json, excluded.constructors_json, excluded.fetched_at)
             AND NOT COALESCE(season_timestamp(provider_identity_cache.fetched_at) > season_timestamp(excluded.fetched_at), FALSE)",
            &[&season, &drivers, &constructors, &fetched_at],
        ).await?;
        finish(tx, changed > 0).await
    }

    pub(crate) async fn save_next_season_schedule(
        &self,
        season: i64,
        events_json: &str,
        now: &str,
    ) -> Result<(), StorageError> {
        supported(season)?;
        if !serde_json::from_str::<Vec<ScheduleEvent>>(events_json)
            .is_ok_and(|events| !events.is_empty())
        {
            return Err(StorageError::SeasonDataInvalid);
        }
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        let changed = tx.execute(
            "INSERT INTO next_season_schedule VALUES ($1,$2,1,$3,$3) ON CONFLICT (season) DO UPDATE
             SET revision=next_season_schedule.revision + (next_season_schedule.events_json <> excluded.events_json)::int,
             updated_at=CASE WHEN next_season_schedule.events_json <> excluded.events_json THEN excluded.updated_at ELSE next_season_schedule.updated_at END,
             events_json=excluded.events_json, checked_at=excluded.checked_at
             WHERE (next_season_schedule.events_json, next_season_schedule.checked_at)
             IS DISTINCT FROM (excluded.events_json, excluded.checked_at)
             AND NOT COALESCE(season_timestamp(next_season_schedule.checked_at) > season_timestamp(excluded.checked_at), FALSE)",
            &[&season, &events_json, &now],
        ).await?;
        finish(tx, changed > 0).await
    }

    pub(crate) async fn store_provider_mappings(
        &self,
        drivers: Vec<(String, String, String)>,
        constructors: Vec<(String, String, String)>,
    ) -> Result<(), StorageError> {
        if drivers.is_empty() && constructors.is_empty() {
            return Ok(());
        }
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        let mut changed = 0;
        for (table, mappings) in [
            ("driver_mappings", drivers),
            ("constructor_mappings", constructors),
        ] {
            for (provider, id, canonical) in mappings {
                changed += tx.execute(&format!("INSERT INTO {table} VALUES ($1,$2,$3) ON CONFLICT (provider, provider_id)
                    DO UPDATE SET canonical_id=excluded.canonical_id WHERE {table}.canonical_id IS DISTINCT FROM excluded.canonical_id"),
                    &[&provider, &id, &canonical],
                ).await?;
            }
        }
        finish(tx, changed > 0).await
    }

    pub(crate) async fn replace_calendar(
        &self,
        meetings: &[Meeting],
        fetched_at: &str,
    ) -> Result<u64, StorageError> {
        if meetings.is_empty() {
            return Ok(0);
        }
        let mut seasons = BTreeMap::<i64, Vec<&Meeting>>::new();
        for meeting in meetings {
            supported(meeting.season)?;
            if meeting
                .sessions
                .iter()
                .any(|session| session.meeting_id != meeting.id)
            {
                return Err(StorageError::SeasonDataInvalid);
            }
            seasons.entry(meeting.season).or_default().push(meeting);
        }
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        let mut revision = 0;
        let mut changed = false;
        for (season, meetings) in seasons {
            let previous = tx
                .query_one(
                    "SELECT MAX(revision), MAX(season_timestamp(fetched_at)) > season_timestamp($2)
                FROM meetings WHERE season=$1",
                    &[&season, &fetched_at],
                )
                .await?;
            let previous_revision = previous.get::<_, Option<i64>>(0).unwrap_or(0);
            let snapshot = tx
                .query_opt(
                    "SELECT content_hash,revision FROM calendar_snapshots WHERE season=$1",
                    &[&season],
                )
                .await?;
            if previous.get::<_, Option<bool>>(1) == Some(true) {
                revision = revision.max(
                    snapshot
                        .as_ref()
                        .map_or(previous_revision, |row| row.get(1)),
                );
                continue;
            }
            let mut content_changed = false;
            for meeting in &meetings {
                let source = meeting.source.as_deref().unwrap_or("jolpica-alpha");
                let circuit = meeting.circuit.as_ref().map(Value::to_string);
                let old_meeting_revision = tx
                    .query_opt("SELECT revision FROM meetings WHERE id=$1", &[&meeting.id])
                    .await?
                    .map(|row| row.get::<_, i64>(0));
                let updated = tx.query_opt(
                    "INSERT INTO meetings (id,season,round,name,country,country_code,location,start_date,end_date,status,source,source_updated_at,fetched_at,jolpica_round_id,circuit_json)
                     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
                     ON CONFLICT (id) DO UPDATE SET season=excluded.season,round=excluded.round,name=excluded.name,
                       country=excluded.country,country_code=excluded.country_code,location=excluded.location,start_date=excluded.start_date,
                       end_date=excluded.end_date,status=excluded.status,source=excluded.source,source_updated_at=excluded.source_updated_at,
                       fetched_at=excluded.fetched_at,jolpica_round_id=excluded.jolpica_round_id,circuit_json=excluded.circuit_json,
                       revision=meetings.revision + ((meetings.season,meetings.round,meetings.name,meetings.country,meetings.country_code,
                       meetings.location,meetings.start_date,meetings.end_date,meetings.status,meetings.source,meetings.jolpica_round_id,meetings.circuit_json)
                       IS DISTINCT FROM (excluded.season,excluded.round,excluded.name,excluded.country,excluded.country_code,
                       excluded.location,excluded.start_date,excluded.end_date,excluded.status,excluded.source,excluded.jolpica_round_id,excluded.circuit_json))::int
                     WHERE (to_jsonb(meetings) - 'revision' - 'openf1_meeting_key') IS DISTINCT FROM
                           (to_jsonb(excluded) - 'revision' - 'openf1_meeting_key') RETURNING revision",
                    &[&meeting.id,&season,&meeting.round,&meeting.name,&meeting.country,&meeting.country_code,&meeting.location,
                      &meeting.start_date,&meeting.end_date,&meeting.status.as_str(),&source,&meeting.source_updated_at,&fetched_at,
                      &meeting.jolpica_round_id,&circuit],
                ).await?;
                if let Some(row) = updated {
                    changed = true;
                    content_changed |= old_meeting_revision != Some(row.get(0));
                }
                if let Some(id) = &meeting.jolpica_round_id {
                    changed |= upsert_provider_mapping(&tx, "jolpica-alpha", id, &meeting.id, None)
                        .await?;
                }
                let mut session_ids = Vec::new();
                for session in &meeting.sessions {
                    session_ids.push(session.id.as_str());
                    let old_session_revision = tx
                        .query_opt("SELECT revision FROM sessions WHERE id=$1", &[&session.id])
                        .await?
                        .map(|row| row.get::<_, i64>(0));
                    let updated = tx.query_opt(
                        "INSERT INTO sessions (id,meeting_id,session_type,start_time,end_time,status,source,provider_session_id,source_updated_at,fetched_at,jolpica_session_id,openf1_session_key)
                         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$8,$11)
                         ON CONFLICT(id) DO UPDATE SET start_time=excluded.start_time,end_time=excluded.end_time,status=excluded.status,
                         source=excluded.source,provider_session_id=excluded.provider_session_id,source_updated_at=excluded.source_updated_at,
                         fetched_at=excluded.fetched_at,jolpica_session_id=excluded.jolpica_session_id,openf1_session_key=excluded.openf1_session_key,
                         revision=sessions.revision + ((sessions.start_time,sessions.end_time,sessions.status,sessions.source,sessions.provider_session_id,sessions.openf1_session_key)
                         IS DISTINCT FROM (excluded.start_time,excluded.end_time,excluded.status,excluded.source,excluded.provider_session_id,excluded.openf1_session_key))::int
                         WHERE (to_jsonb(sessions) - 'revision') IS DISTINCT FROM (to_jsonb(excluded) - 'revision') RETURNING revision",
                        &[&session.id,&meeting.id,&session.session_type.as_str(),&session.start_time,&session.end_time,&session.status.as_str(),
                          &source,&session.jolpica_session_id,&meeting.source_updated_at,&fetched_at,&session.openf1_session_key],
                    ).await?;
                    if let Some(row) = updated {
                        changed = true;
                        content_changed |= old_session_revision != Some(row.get(0));
                    }
                    if let Some(id) = &session.jolpica_session_id {
                        changed |= upsert_provider_mapping(
                            &tx,
                            "jolpica-alpha",
                            id,
                            &meeting.id,
                            Some(&session.id),
                        )
                        .await?;
                    }
                    if let Some(key) = session.openf1_session_key {
                        changed |= upsert_provider_mapping(
                            &tx,
                            "openf1",
                            &key.to_string(),
                            &meeting.id,
                            Some(&session.id),
                        )
                        .await?;
                    }
                }
                if !session_ids.is_empty() {
                    let deleted = tx.execute("DELETE FROM sessions WHERE meeting_id=$1 AND id <> ALL($2::text[])
                        AND NOT EXISTS (SELECT 1 FROM session_results WHERE session_id=sessions.id)", &[&meeting.id,&session_ids]).await?;
                    content_changed |= deleted > 0;
                    changed |= deleted > 0;
                }
            }
            let hash = stable_calendar_hash(&meetings);
            let current = match snapshot {
                Some(ref row) if row.get::<_, String>(0) == hash => row.get(1),
                Some(ref row) => row.get::<_, i64>(1) + 1,
                None => {
                    previous_revision.max(1) + i64::from(previous_revision > 0 && content_changed)
                }
            };
            changed |= tx.execute("INSERT INTO calendar_snapshots VALUES ($1,$2,$3) ON CONFLICT (season) DO UPDATE
                SET content_hash=excluded.content_hash,revision=excluded.revision
                WHERE (calendar_snapshots.content_hash,calendar_snapshots.revision) IS DISTINCT FROM (excluded.content_hash,excluded.revision)",
                &[&season,&hash,&current]).await? > 0;
            revision = revision.max(current);
        }
        finish(tx, changed).await?;
        Ok(revision as u64)
    }
}

async fn upsert_provider_mapping(
    tx: &Transaction<'_>,
    provider: &str,
    id: &str,
    meeting_id: &str,
    session_id: Option<&str>,
) -> Result<bool, StorageError> {
    Ok(tx.execute("INSERT INTO provider_mappings VALUES ($1,$2,$3,$4) ON CONFLICT (provider,provider_id) DO UPDATE
        SET meeting_id=excluded.meeting_id,session_id=excluded.session_id WHERE (provider_mappings.meeting_id,provider_mappings.session_id)
        IS DISTINCT FROM (excluded.meeting_id,excluded.session_id)", &[&provider,&id,&meeting_id,&session_id]).await? > 0)
}
