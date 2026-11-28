//! Process-local cache for canonical queries. The database generation is a
//! separate, coalesced probe so a warm query does no SQL between probes.
use std::{
    any::Any,
    collections::HashMap,
    future::Future,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, AtomicUsize, Ordering::Relaxed},
    },
    time::{Duration, SystemTime, UNIX_EPOCH},
};

use tokio::{sync::Mutex as AsyncMutex, time::Instant};

use super::disk_cache::{DiskCache, Stored};
use crate::error::StorageError;
use serde::{Serialize, de::DeserializeOwned};

const RETRY: Duration = Duration::from_secs(1);
const QUERY_DEADLINE: Duration = Duration::from_secs(4);

#[derive(Clone, Copy)]
pub struct SeasonCacheConfig {
    pub capacity: usize,
    pub memory_bytes: usize,
    pub disk_bytes: u64,
    pub ttl: Duration,
    /// Maximum outage age since the last successful load or generation confirmation.
    pub max_stale: Duration,
    pub revision_interval: Duration,
    pub query_deadline: Duration,
}

impl Default for SeasonCacheConfig {
    fn default() -> Self {
        Self {
            capacity: 512,
            memory_bytes: 32 * 1024 * 1024,
            disk_bytes: 64 * 1024 * 1024,
            ttl: Duration::from_secs(60),
            max_stale: Duration::from_secs(6 * 3600),
            revision_interval: Duration::from_secs(5),
            query_deadline: QUERY_DEADLINE,
        }
    }
}

impl SeasonCacheConfig {
    pub fn from_env() -> Result<Self, StorageError> {
        fn value(name: &'static str, default: u64, max: u64) -> Result<u64, StorageError> {
            let invalid = || StorageError::SeasonConfig(name);
            match std::env::var(name) {
                Ok(v) => v
                    .parse::<u64>()
                    .ok()
                    .filter(|v| *v <= max)
                    .ok_or_else(invalid),
                Err(std::env::VarError::NotPresent) => Ok(default),
                Err(_) => Err(invalid()),
            }
        }
        let default = Self::default();
        Ok(Self {
            memory_bytes: value(
                "PITPULSE_SEASON_CACHE_MEMORY_BYTES",
                default.memory_bytes as u64,
                128 * 1024 * 1024,
            )? as usize,
            disk_bytes: value(
                "PITPULSE_SEASON_CACHE_DISK_BYTES",
                default.disk_bytes,
                128 * 1024 * 1024,
            )?,
            capacity: value(
                "PITPULSE_SEASON_CACHE_CAPACITY",
                default.capacity as u64,
                8192,
            )? as usize,
            ttl: Duration::from_secs(value(
                "PITPULSE_SEASON_CACHE_TTL_SECONDS",
                default.ttl.as_secs(),
                3600,
            )?),
            max_stale: Duration::from_secs(value(
                "PITPULSE_SEASON_CACHE_MAX_STALE_SECONDS",
                default.max_stale.as_secs(),
                86400,
            )?),
            revision_interval: Duration::from_secs(
                value(
                    "PITPULSE_SEASON_CACHE_REVISION_SECONDS",
                    default.revision_interval.as_secs(),
                    60,
                )?
                .max(1),
            ),
            query_deadline: Duration::from_secs(
                value(
                    "PITPULSE_SEASON_QUERY_DEADLINE_SECONDS",
                    default.query_deadline.as_secs(),
                    30,
                )?
                .max(1),
            ),
        })
    }
}

#[derive(Clone, Copy, Debug, Default, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SeasonCacheStats {
    pub hits: u64,
    pub stale_hits: u64,
    pub origin_loads: u64,
    pub revision_checks: u64,
    pub evictions: u64,
    pub unavailable: u64,
    pub memory_bytes: usize,
    pub disk_bytes: Option<u64>,
    pub disk_hits: u64,
}

// Each variant has exactly one value type, set by its Postgres read method.
#[derive(Clone, Eq, PartialEq, Hash, Serialize)]
pub(crate) enum Key {
    RacingSeasons(i64),
    Calendar(Option<i64>),
    SessionSeason(String),
    SessionResults(String),
    Drivers(i64),
    Constructors(i64),
    Identity(i64),
    Schedule(i64),
    ScheduleOpenings,
    SeasonResults(i64),
    Archive(i64, i64, i64),
    LapRecords(i64, i64, i64),
    Response(&'static str, i64, i64, i64),
}

impl Key {
    fn derived(&self) -> bool {
        matches!(
            self,
            Self::Archive(..) | Self::LapRecords(..) | Self::Response(..)
        )
    }
}

pub(super) struct Cache {
    config: SeasonCacheConfig,
    pub(super) disk: Option<DiskCache>,
    disk_hits: AtomicU64,
    memory_bytes: AtomicUsize,
    slots: Mutex<HashMap<Key, Arc<AsyncMutex<Slot>>>>,
    generation: AsyncMutex<Generation>,
    hits: AtomicU64,
    stale_hits: AtomicU64,
    origin_loads: AtomicU64,
    revision_checks: AtomicU64,
    evictions: AtomicU64,
    unavailable: AtomicU64,
}

#[derive(Default)]
struct Generation {
    value: Option<i64>,
    check_after: Option<Instant>,
    offline: bool,
    confirmed_at: Option<i64>,
}

struct Entry {
    value: Box<dyn Any + Send + Sync>,
    generation: i64,
    loaded: Instant,
    loaded_at: i64,
    bytes: usize,
    // Successful negative/empty reads can be fresh, but only known data
    // (or explicitly modeled empty calendars) can be served during outages.
    can_fallback: bool,
}

#[derive(Default)]
struct Slot {
    entry: Option<Entry>,
    used: Option<Instant>,
    retry_after: Option<Instant>,
}

impl Cache {
    pub(super) fn new(config: SeasonCacheConfig) -> Self {
        Self {
            config,
            disk: None,
            disk_hits: 0.into(),
            memory_bytes: 0.into(),
            slots: Mutex::default(),
            generation: AsyncMutex::default(),
            hits: 0.into(),
            stale_hits: 0.into(),
            origin_loads: 0.into(),
            revision_checks: 0.into(),
            evictions: 0.into(),
            unavailable: 0.into(),
        }
    }

    pub(super) fn enabled(&self) -> bool {
        self.config.capacity != 0
    }

    pub(super) fn stats(&self) -> SeasonCacheStats {
        SeasonCacheStats {
            hits: self.hits.load(Relaxed),
            stale_hits: self.stale_hits.load(Relaxed),
            origin_loads: self.origin_loads.load(Relaxed),
            revision_checks: self.revision_checks.load(Relaxed),
            evictions: self.evictions.load(Relaxed),
            unavailable: self.unavailable.load(Relaxed),
            memory_bytes: self.memory_bytes.load(Relaxed),
            disk_bytes: None,
            disk_hits: self.disk_hits.load(Relaxed),
        }
    }

    pub(super) async fn current_generation(
        &self,
        probe: impl Future<Output = Result<i64, StorageError>>,
    ) -> Result<i64, StorageError> {
        match self.generation(probe).await {
            Ok(generation) => Ok(generation),
            Err(StorageError::SeasonUnavailable) => self
                .generation
                .lock()
                .await
                .value
                .ok_or(StorageError::SeasonUnavailable),
            Err(error) => Err(error),
        }
    }

    fn slot(&self, key: Key) -> Option<Arc<AsyncMutex<Slot>>> {
        let mut slots = self.slots.lock().expect("season cache");
        if let Some(slot) = slots.get(&key) {
            return Some(slot.clone());
        }
        if slots.len() >= self.config.capacity {
            let victim = slots
                .iter()
                .filter(|(_, slot)| Arc::strong_count(slot) == 1)
                .min_by_key(|(_, slot)| slot.try_lock().expect("idle slot").used)
                .map(|(key, _)| key.clone())?;
            if let Some(slot) = slots.remove(&victim)
                && let Some(entry) = &slot.try_lock().expect("idle slot").entry
            {
                self.memory_bytes.fetch_sub(entry.bytes, Relaxed);
            }
            self.evictions.fetch_add(1, Relaxed);
        }
        Some(slots.entry(key).or_default().clone())
    }

    async fn generation(
        &self,
        probe: impl Future<Output = Result<i64, StorageError>>,
    ) -> Result<i64, StorageError> {
        let mut state = self.generation.lock().await;
        if state.check_after.is_some_and(|due| due > Instant::now()) {
            return if state.offline {
                Err(StorageError::SeasonUnavailable)
            } else {
                state.value.ok_or(StorageError::SeasonDataInvalid)
            };
        }
        self.revision_checks.fetch_add(1, Relaxed);
        match within_deadline(self.config.query_deadline, probe).await {
            Ok(value) => {
                let checked_at = epoch_seconds();
                if let Some(disk) = &self.disk {
                    disk.confirm(value, checked_at).await;
                }
                *state = Generation {
                    value: Some(value),
                    check_after: Some(Instant::now() + self.config.revision_interval),
                    offline: false,
                    confirmed_at: Some(checked_at),
                };
                Ok(value)
            }
            Err(StorageError::SeasonUnavailable) => {
                if state.value.is_none()
                    && let Some(disk) = &self.disk
                    && let Some((generation, checked_at)) = disk.confirmation().await
                {
                    state.value = Some(generation);
                    state.confirmed_at = Some(checked_at);
                }
                state.offline = true;
                state.check_after = Some(Instant::now() + RETRY);
                Err(StorageError::SeasonUnavailable)
            }
            Err(error) => Err(error),
        }
    }

    pub(super) async fn get<T: Clone + Serialize + DeserializeOwned + Send + Sync + 'static>(
        &self,
        key: Key,
        probe: impl Future<Output = Result<i64, StorageError>>,
        load: impl Future<Output = Result<T, StorageError>>,
        can_fallback: impl FnOnce(&T) -> bool,
        mark_stale: impl Fn(&mut T),
    ) -> Result<T, StorageError> {
        if self.config.capacity == 0 {
            let result = self.load(load).await;
            if matches!(result, Err(StorageError::SeasonUnavailable)) {
                self.unavailable.fetch_add(1, Relaxed);
            }
            return result;
        }
        let Some(slot) = self.slot(key.clone()) else {
            self.unavailable.fetch_add(1, Relaxed);
            return Err(StorageError::SeasonUnavailable);
        };
        let mut slot = slot.lock().await;
        let generation = self.generation(probe).await;
        let now = Instant::now();
        slot.used = Some(now);
        let disk_key = self
            .disk
            .as_ref()
            .map(|_| serde_json::to_string(&key).expect("season cache key"));
        let mut disk_entry = None;
        if slot.entry.is_none()
            && let (Some(disk), Some(key)) = (&self.disk, &disk_key)
            && let Some(stored) = disk.read(key.clone()).await
            && let Ok(data) = serde_json::from_slice::<T>(&stored.bytes)
        {
            self.disk_hits.fetch_add(1, Relaxed);
            let age = elapsed_since(stored.loaded_at).unwrap_or(Duration::MAX);
            let entry = Entry {
                value: Box::new(data),
                generation: stored.generation,
                loaded: now.checked_sub(age).unwrap_or(now),
                loaded_at: stored.loaded_at,
                bytes: stored.bytes.len().saturating_mul(4).saturating_add(512),
                can_fallback: stored.can_fallback,
            };
            disk_entry = self.retain(&mut slot, entry);
        }
        let entry = slot.entry.as_ref().or(disk_entry.as_ref());
        let generation = match generation {
            Ok(generation) => generation,
            Err(StorageError::SeasonUnavailable)
                if key.derived() && !matches!(key, Key::LapRecords(..)) =>
            {
                return self.fallback(entry, &mark_stale).await;
            }
            Err(StorageError::SeasonUnavailable) if matches!(key, Key::LapRecords(..)) => {
                return self.fallback(entry, &mark_stale).await;
            }
            Err(StorageError::SeasonUnavailable) => return self.fallback(entry, &mark_stale).await,
            Err(error) => return Err(error),
        };
        let ttl = match key {
            // Canonical entries are validated by generation between TTLs. When
            // persistent storage is on, only the derived views need a short TTL.
            Key::Archive(..) | Key::Response(..) if self.disk.is_some() => self.config.ttl,
            Key::LapRecords(..) if self.disk.is_some() => Duration::MAX,
            _ if self.disk.is_some() && !self.config.ttl.is_zero() => Duration::MAX,
            _ => self.config.ttl,
        };
        if let Some(entry) = entry
            && entry.generation == generation
            && (ttl == Duration::MAX || now.saturating_duration_since(entry.loaded) < ttl)
        {
            self.hits.fetch_add(1, Relaxed);
            return Ok(clone_value(entry));
        }
        if slot.retry_after.is_some_and(|due| due > now) {
            return self.fallback(entry, &mark_stale).await;
        }
        let result = if key.derived() {
            load.await
        } else {
            self.load(load).await
        };
        match result {
            Ok(data) => {
                let can_fallback = can_fallback(&data);
                // Nested origin reads can have fallen back while building a
                // projection. Never publish that rebuild under a newer generation.
                let same_generation = {
                    let state = self.generation.lock().await;
                    !state.offline && state.value == Some(generation)
                };
                if same_generation && let Ok(bytes) = serde_json::to_vec(&data) {
                    let loaded_at = epoch_seconds();
                    let weight = bytes.len().saturating_mul(4).saturating_add(512);
                    if let (Some(disk), Some(key)) = (&self.disk, disk_key) {
                        disk.write(
                            key,
                            Stored {
                                generation,
                                loaded_at,
                                can_fallback,
                                bytes,
                            },
                        )
                        .await;
                    }
                    self.retain(
                        &mut slot,
                        Entry {
                            value: Box::new(data.clone()),
                            generation,
                            loaded: Instant::now(),
                            loaded_at,
                            bytes: weight,
                            can_fallback,
                        },
                    );
                }
                slot.retry_after = None;
                Ok(data)
            }
            Err(StorageError::SeasonUnavailable) => {
                slot.retry_after = Some(Instant::now() + RETRY);
                self.fallback(slot.entry.as_ref().or(disk_entry.as_ref()), &mark_stale)
                    .await
            }
            Err(error) => Err(error),
        }
    }

    // Return the entry to this request if it cannot be retained. Active
    // slots are never evicted and the byte budget is enforced under the map lock.
    fn retain(&self, slot: &mut Slot, entry: Entry) -> Option<Entry> {
        let mut slots = self.slots.lock().expect("season cache");
        if entry.bytes > self.config.memory_bytes {
            return Some(entry);
        }
        let old_bytes = slot.entry.as_ref().map_or(0, |old| old.bytes);
        while self.memory_bytes.load(Relaxed) - old_bytes + entry.bytes > self.config.memory_bytes {
            let Some(key) = slots
                .iter()
                .filter(|(_, slot)| Arc::strong_count(slot) == 1)
                .filter_map(|(key, slot)| {
                    let slot = slot.try_lock().expect("idle slot");
                    slot.entry
                        .as_ref()
                        .map(|entry| (key.clone(), slot.used, entry.bytes))
                })
                .min_by_key(|(_, used, _)| *used)
            else {
                return Some(entry);
            };
            slots.remove(&key.0);
            self.memory_bytes.fetch_sub(key.2, Relaxed);
            self.evictions.fetch_add(1, Relaxed);
        }
        if let Some(old) = slot.entry.take() {
            self.memory_bytes.fetch_sub(old.bytes, Relaxed);
        }
        self.memory_bytes.fetch_add(entry.bytes, Relaxed);
        slot.entry = Some(entry);
        None
    }

    async fn fallback<T: Clone + 'static>(
        &self,
        entry: Option<&Entry>,
        mark_stale: impl FnOnce(&mut T),
    ) -> Result<T, StorageError> {
        if let Some(entry) = entry
            && entry.can_fallback
        {
            let age = if self.disk.is_some() {
                let state = self.generation.lock().await;
                let validated = if state.value == Some(entry.generation) {
                    state
                        .confirmed_at
                        .unwrap_or(entry.loaded_at)
                        .max(entry.loaded_at)
                } else {
                    entry.loaded_at
                };
                elapsed_since(validated).unwrap_or(Duration::MAX)
            } else {
                entry.loaded.elapsed()
            };
            if age < self.config.max_stale {
                self.stale_hits.fetch_add(1, Relaxed);
                let mut data = clone_value(entry);
                mark_stale(&mut data);
                return Ok(data);
            }
        }
        self.unavailable.fetch_add(1, Relaxed);
        Err(StorageError::SeasonUnavailable)
    }

    async fn load<T>(
        &self,
        load: impl Future<Output = Result<T, StorageError>>,
    ) -> Result<T, StorageError> {
        self.origin_loads.fetch_add(1, Relaxed);
        within_deadline(self.config.query_deadline, load).await
    }
}

fn epoch_seconds() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

fn elapsed_since(at: i64) -> Option<Duration> {
    u64::try_from(epoch_seconds().checked_sub(at)?)
        .ok()
        .map(Duration::from_secs)
}

fn clone_value<T: Clone + 'static>(entry: &Entry) -> T {
    entry
        .value
        .downcast_ref::<T>()
        .expect("type agrees with season cache key")
        .clone()
}

async fn within_deadline<T>(
    deadline: Duration,
    operation: impl Future<Output = Result<T, StorageError>>,
) -> Result<T, StorageError> {
    tokio::time::timeout(deadline, operation)
        .await
        .map_err(|_| StorageError::SeasonUnavailable)?
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::advance;

    fn cache() -> Cache {
        Cache::new(SeasonCacheConfig {
            capacity: 2,
            ttl: Duration::from_secs(4),
            max_stale: Duration::from_secs(10),
            revision_interval: Duration::from_secs(2),
            ..Default::default()
        })
    }

    async fn get(
        cache: &Cache,
        key: i64,
        generation: Result<i64, StorageError>,
        load: impl Future<Output = Result<i32, StorageError>>,
    ) -> Result<i32, StorageError> {
        cache
            .get(
                Key::RacingSeasons(key),
                async { generation },
                load,
                |n| *n > 0,
                |n| *n = -*n,
            )
            .await
    }

    #[tokio::test(start_paused = true)]
    async fn coalesces_and_keeps_recently_used_values_until_ttl() {
        let cache = cache();
        let load = || async {
            tokio::task::yield_now().await;
            Ok(10)
        };
        let (first, second, third) = tokio::join!(
            get(&cache, 1, Ok(1), load()),
            get(&cache, 1, Ok(1), load()),
            get(&cache, 1, Ok(1), load()),
        );
        assert_eq!([first.unwrap(), second.unwrap(), third.unwrap()], [10; 3]);
        assert_eq!(cache.stats().origin_loads, 1);
        assert_eq!(cache.stats().revision_checks, 1);
        assert_eq!(cache.stats().hits, 2);
        assert_eq!(get(&cache, 2, Ok(1), async { Ok(20) }).await.unwrap(), 20);
        advance(Duration::from_secs(1)).await;
        assert_eq!(
            get(&cache, 1, Ok(1), async { panic!("warm key hit origin") })
                .await
                .unwrap(),
            10
        );
        advance(Duration::from_secs(1)).await;
        get(&cache, 3, Ok(1), async { Ok(30) }).await.unwrap();
        assert_eq!(cache.stats().evictions, 1);
        assert_eq!(
            get(&cache, 1, Ok(1), async { panic!("recent key was evicted") })
                .await
                .unwrap(),
            10
        );
        assert_eq!(get(&cache, 2, Ok(1), async { Ok(21) }).await.unwrap(), 21);
        advance(Duration::from_secs(2)).await;
        assert_eq!(get(&cache, 1, Ok(1), async { Ok(11) }).await.unwrap(), 11);
    }

    #[tokio::test(start_paused = true)]
    async fn revisions_invalidate_before_ttl_and_outages_respect_max_age() {
        let cache = cache();
        let down = || Err(StorageError::SeasonUnavailable);
        let no_load = || async { panic!("no origin query expected") };
        assert_eq!(get(&cache, 1, Ok(1), async { Ok(10) }).await.unwrap(), 10);
        assert_eq!(get(&cache, 2, Ok(1), async { Ok(0) }).await.unwrap(), 0);
        advance(Duration::from_secs(2)).await;
        assert_eq!(get(&cache, 1, Ok(2), async { Ok(20) }).await.unwrap(), 20);
        advance(Duration::from_secs(2)).await;
        let (a, b, missing) = tokio::join!(
            get(&cache, 1, down(), no_load()),
            get(&cache, 1, down(), no_load()),
            get(&cache, 2, down(), no_load())
        );
        assert_eq!([a.unwrap(), b.unwrap()], [-20; 2]);
        assert!(matches!(missing, Err(StorageError::SeasonUnavailable)));
        assert_eq!(cache.stats().revision_checks, 3);
        assert_eq!(cache.stats().origin_loads, 3);
        assert_eq!(cache.stats().stale_hits, 2);
        advance(Duration::from_secs(8)).await;
        assert!(matches!(
            get(&cache, 1, down(), no_load()).await,
            Err(StorageError::SeasonUnavailable)
        ));
        advance(RETRY).await;
        assert_eq!(get(&cache, 1, Ok(2), async { Ok(21) }).await.unwrap(), 21);
    }

    #[test]
    fn derived_keys_include_both_generations() {
        assert!(Key::Archive(2026, 1, 7) != Key::Archive(2026, 2, 7));
        assert!(Key::Archive(2026, 1, 7) != Key::Archive(2026, 1, 8));
        assert!(Key::LapRecords(2026, 1, 7) != Key::LapRecords(2026, 2, 7));
        assert!(Key::LapRecords(2026, 1, 7) != Key::LapRecords(2026, 1, 8));
        assert!(
            Key::Response("/api/v1/home", 2026, 1, 7) != Key::Response("/api/v1/home", 2026, 2, 7)
        );
        assert!(
            Key::Response("/api/v1/home", 2026, 1, 7) != Key::Response("/api/v1/home", 2026, 1, 8)
        );
    }

    #[test]
    fn zero_disk_budget_keeps_memory_cache_enabled() {
        let config = SeasonCacheConfig {
            disk_bytes: 0,
            ..Default::default()
        };
        assert!(Cache::new(config).enabled());
    }

    #[tokio::test]
    async fn oversized_replacement_preserves_existing_entry() {
        let config = SeasonCacheConfig {
            memory_bytes: 1024,
            ..Default::default()
        };
        let cache = Cache::new(config);
        assert_eq!(get(&cache, 1, Ok(1), async { Ok(10) }).await.unwrap(), 10);
        let slot = cache.slot(Key::RacingSeasons(1)).unwrap();
        {
            let mut slot = slot.lock().await;
            let retained = cache.retain(
                &mut slot,
                Entry {
                    value: Box::new(20),
                    generation: 1,
                    loaded: Instant::now(),
                    loaded_at: epoch_seconds(),
                    bytes: 2048,
                    can_fallback: true,
                },
            );
            assert!(retained.is_some());
            assert_eq!(
                slot.entry
                    .as_ref()
                    .and_then(|entry| entry.value.downcast_ref::<i32>()),
                Some(&10)
            );
        }
    }

    #[tokio::test]
    async fn cached_misses_and_derived_values_are_not_offline_snapshots() {
        let cache = Cache::new(SeasonCacheConfig::default());
        let missing = cache
            .get(
                Key::Response("/api/v1/home", 2099, 0, 1),
                async { Ok(1) },
                async {
                    Ok::<_, StorageError>(
                        serde_json::json!({"meta":{"unavailable":true,"stale":false}}),
                    )
                },
                |value| value["meta"]["unavailable"] != true,
                |_| {},
            )
            .await
            .unwrap();
        assert_eq!(missing["meta"]["unavailable"], true);
        assert!(
            !cache
                .slot(Key::Response("/api/v1/home", 2099, 0, 1))
                .unwrap()
                .try_lock()
                .unwrap()
                .entry
                .as_ref()
                .unwrap()
                .can_fallback
        );
        assert!(matches!(
            cache
                .get::<Vec<(String, i64)>>(
                    Key::LapRecords(2026, 0, 1),
                    async { Err(StorageError::SeasonUnavailable) },
                    async { Err::<Vec<(String, i64)>, _>(StorageError::SeasonUnavailable) },
                    |_| true,
                    |_| {},
                )
                .await,
            Err(StorageError::SeasonUnavailable)
        ));
    }

    #[tokio::test(start_paused = true)]
    async fn failed_same_key_query_is_shared_and_retried() {
        let cache = cache();
        let (a, b) = tokio::join!(
            get(&cache, 1, Ok(1), async {
                tokio::task::yield_now().await;
                Err(StorageError::SeasonUnavailable)
            }),
            get(&cache, 1, Ok(1), async {
                panic!("failure was not coalesced")
            }),
        );
        assert!(matches!(a, Err(StorageError::SeasonUnavailable)));
        assert!(matches!(b, Err(StorageError::SeasonUnavailable)));
        assert_eq!(cache.stats().origin_loads, 1);
        advance(RETRY).await;
        assert_eq!(get(&cache, 1, Ok(1), async { Ok(1) }).await.unwrap(), 1);
    }
}
