//! Process-local cache for canonical queries. The database generation is a
//! separate, coalesced probe so a warm query does no SQL between probes.
use std::{
    any::Any,
    collections::HashMap,
    future::Future,
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering::Relaxed},
    },
    time::Duration,
};

use tokio::{sync::Mutex as AsyncMutex, time::Instant};

use crate::error::StorageError;

const RETRY: Duration = Duration::from_secs(1);
const QUERY_DEADLINE: Duration = Duration::from_secs(4);

#[derive(Clone, Copy)]
pub struct SeasonCacheConfig {
    pub capacity: usize,
    pub ttl: Duration,
    /// Total age since the last successful query, including the fresh TTL.
    pub max_stale: Duration,
    pub revision_interval: Duration,
    pub query_deadline: Duration,
}

impl Default for SeasonCacheConfig {
    fn default() -> Self {
        Self {
            capacity: 512,
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
}

// Each variant has exactly one value type, set by its Postgres read method.
#[derive(Clone, Eq, PartialEq, Hash)]
pub(super) enum Key {
    RacingSeasons(i64),
    Calendar(Option<i64>),
    SessionSeason(String),
    SessionResults(String),
    Drivers(i64),
    Constructors(i64),
    Identity(i64),
    Schedule(i64),
    ScheduleOpenings,
}

pub(super) struct Cache {
    config: SeasonCacheConfig,
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
}

struct Entry {
    value: Box<dyn Any + Send + Sync>,
    generation: i64,
    loaded: Instant,
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

    pub(super) fn stats(&self) -> SeasonCacheStats {
        SeasonCacheStats {
            hits: self.hits.load(Relaxed),
            stale_hits: self.stale_hits.load(Relaxed),
            origin_loads: self.origin_loads.load(Relaxed),
            revision_checks: self.revision_checks.load(Relaxed),
            evictions: self.evictions.load(Relaxed),
            unavailable: self.unavailable.load(Relaxed),
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
            slots.remove(&victim);
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
                *state = Generation {
                    value: Some(value),
                    check_after: Some(Instant::now() + self.config.revision_interval),
                    offline: false,
                };
                Ok(value)
            }
            Err(StorageError::SeasonUnavailable) => {
                state.offline = true;
                state.check_after = Some(Instant::now() + RETRY);
                Err(StorageError::SeasonUnavailable)
            }
            Err(error) => Err(error),
        }
    }

    pub(super) async fn get<T: Clone + Send + Sync + 'static>(
        &self,
        key: Key,
        probe: impl Future<Output = Result<i64, StorageError>>,
        load: impl Future<Output = Result<T, StorageError>>,
        can_fallback: impl FnOnce(&T) -> bool,
        mark_stale: impl FnOnce(&mut T),
    ) -> Result<T, StorageError> {
        if self.config.capacity == 0 {
            let result = self.load(load).await;
            if matches!(result, Err(StorageError::SeasonUnavailable)) {
                self.unavailable.fetch_add(1, Relaxed);
            }
            return result;
        }
        let Some(slot) = self.slot(key) else {
            // All slots are active. Keep their single-flight guarantee and
            // avoid an unbounded origin burst for new, distinct keys.
            self.unavailable.fetch_add(1, Relaxed);
            return Err(StorageError::SeasonUnavailable);
        };
        let mut slot = slot.lock().await;
        let generation = self.generation(probe).await;
        let now = Instant::now();
        slot.used = Some(now);
        let generation = match generation {
            Ok(generation) => generation,
            Err(StorageError::SeasonUnavailable) => return self.fallback(&slot, mark_stale),
            Err(error) => return Err(error),
        };
        if let Some(entry) = &slot.entry
            && entry.generation == generation
            && now.duration_since(entry.loaded) < self.config.ttl
        {
            self.hits.fetch_add(1, Relaxed);
            return Ok(clone_value(entry));
        }
        if slot.retry_after.is_some_and(|due| due > now) {
            return self.fallback(&slot, mark_stale);
        }
        match self.load(load).await {
            Ok(data) => {
                slot.entry = Some(Entry {
                    can_fallback: can_fallback(&data),
                    value: Box::new(data.clone()),
                    generation,
                    loaded: Instant::now(),
                });
                slot.retry_after = None;
                Ok(data)
            }
            Err(StorageError::SeasonUnavailable) => {
                slot.retry_after = Some(Instant::now() + RETRY);
                self.fallback(&slot, mark_stale)
            }
            Err(error) => Err(error),
        }
    }

    fn fallback<T: Clone + 'static>(
        &self,
        slot: &Slot,
        mark_stale: impl FnOnce(&mut T),
    ) -> Result<T, StorageError> {
        if let Some(entry) = &slot.entry
            && entry.can_fallback
            && entry.loaded.elapsed() < self.config.max_stale
        {
            self.stale_hits.fetch_add(1, Relaxed);
            let mut data = clone_value(entry);
            mark_stale(&mut data);
            return Ok(data);
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
