use std::{
    collections::HashMap,
    future::Future,
    hash::Hash,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use axum::{
    body::{Body, Bytes, to_bytes},
    extract::{Request, State},
    http::{Method, StatusCode, Uri, header},
    middleware::Next,
    response::{IntoResponse, Response},
};
use tokio::sync::Mutex as AsyncMutex;
use tower::ServiceExt;

use crate::{app_state::AppState, services::season_results::SeasonArchive};

const DASHBOARD_HEADER: &str = "x-pitpulse-dashboard";
const TTL: Duration = Duration::from_secs(60);
const PATHS: &[&str] = &[
    "/api/v1/calendar",
    "/api/v1/standings/drivers",
    "/api/v1/standings/constructors",
    "/api/v1/home",
    "/api/v1/results/season",
    "/api/v1/tech-updates",
    "/api/v1/pu-elements",
    "/api/v1/destructors-championship",
    "/api/v1/features",
];

#[derive(Default)]
pub(crate) struct DashboardCache {
    responses: Cache<(&'static str, i64), Bytes>,
    pub(crate) archives: Cache<i64, Arc<SeasonArchive>>,
}

type Slot<T> = Arc<AsyncMutex<Option<(Instant, T)>>>;

pub(crate) struct Cache<K, T> {
    entries: Mutex<HashMap<K, Slot<T>>>,
}

impl<K, T> Default for Cache<K, T> {
    fn default() -> Self {
        Self {
            entries: Mutex::default(),
        }
    }
}

impl<K: Eq + Hash + Copy, T: Clone> Cache<K, T> {
    pub(crate) async fn get_or_load<E>(
        &self,
        key: K,
        limit: usize,
        load: impl Future<Output = Result<T, E>>,
    ) -> Result<T, E> {
        let slot = {
            let mut entries = self.entries.lock().expect("dashboard cache");
            if !entries.contains_key(&key) && entries.len() >= limit {
                // Evict the oldest idle entry. Never start a second load for a busy key.
                let oldest = entries
                    .iter()
                    .filter(|(_, slot)| Arc::strong_count(slot) == 1)
                    .min_by_key(|(_, slot)| {
                        slot.try_lock()
                            .ok()
                            .and_then(|item| item.as_ref().map(|(time, _)| *time))
                    })
                    .map(|(&key, _)| key);
                if let Some(oldest) = oldest {
                    entries.remove(&oldest);
                }
            }
            if entries.len() >= limit && !entries.contains_key(&key) {
                None
            } else {
                Some(Arc::clone(entries.entry(key).or_default()))
            }
        };
        let Some(slot) = slot else {
            return load.await;
        };
        let mut item = slot.lock().await;
        if let Some((time, data)) = &*item
            && time.elapsed() < TTL
        {
            return Ok(data.clone());
        }
        let data = load.await?;
        *item = Some((Instant::now(), data.clone()));
        Ok(data)
    }
}

fn cache_key(uri: &Uri) -> Option<(&'static str, i64)> {
    let path = PATHS.iter().copied().find(|&path| path == uri.path())?;
    let year = uri.query()?.strip_prefix("season=")?;
    if year.len() != 4 || !year.bytes().all(|byte| byte.is_ascii_digit()) {
        return None;
    }
    let season = year.parse().ok()?;
    (crate::services::FIRST_SEASON..=2100)
        .contains(&season)
        .then_some((path, season))
}

pub(crate) async fn cache_response(
    State(state): State<AppState>,
    request: Request,
    next: Next,
) -> Response {
    if state.database.uses_central_season_data() {
        return next.run(request).await;
    }
    let Some(key) = cache_key(request.uri()).filter(|_| {
        request.method() == Method::GET
            && request
                .headers()
                .get(DASHBOARD_HEADER)
                .is_some_and(|v| v == "1")
    }) else {
        return next.run(request).await;
    };
    let result = state
        .dashboard
        .responses
        .get_or_load(key, 36, async {
            let response = next.run(request).await;
            if !response.status().is_success() {
                return Err(response);
            }
            to_bytes(response.into_body(), usize::MAX)
                .await
                .map_err(|error| {
                    tracing::error!(%error, "failed to read dashboard response body");
                    StatusCode::INTERNAL_SERVER_ERROR.into_response()
                })
        })
        .await;
    match result {
        Ok(data) => ([(header::CONTENT_TYPE, "application/json")], data).into_response(),
        Err(response) => response,
    }
}

pub(crate) async fn warm(state: AppState) {
    let Ok(now) = state.database.utc_now().await else {
        return;
    };
    let Some(year) = now.get(..4) else { return };
    // These are internal reads of the same handlers and cache used by the authenticated router.
    let router = super::routes::build_router(state.clone()).with_state(state);
    for path in PATHS {
        let request = Request::builder()
            .uri(format!("{path}?season={year}"))
            .header(DASHBOARD_HEADER, "1")
            .body(Body::empty())
            .expect("warm dashboard request");
        let _ = router.clone().oneshot(request).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn cache_shares_work_expires_and_retries_failed_loads() {
        let cache = Cache::default();
        let (first, concurrent) = tokio::join!(
            cache.get_or_load(2026, 2, async {
                tokio::task::yield_now().await;
                Ok::<_, ()>("latest")
            }),
            cache.get_or_load(2026, 2, async { panic!("duplicate load") }),
        );
        assert_eq!(first, Ok("latest"));
        assert_eq!(concurrent, Ok::<_, ()>("latest"));
        let slot = cache.entries.lock().unwrap().get(&2026).unwrap().clone();
        *slot.lock().await = Some((Instant::now() - TTL, "expired"));
        assert_eq!(cache.get_or_load(2026, 2, async { Err(()) }).await, Err(()));
        assert_eq!(
            cache
                .get_or_load(2026, 2, async { Ok::<_, ()>("recovered") })
                .await,
            Ok("recovered")
        );
        assert_eq!(
            cache
                .get_or_load(2025, 2, async { Ok::<_, ()>("prior") })
                .await,
            Ok("prior")
        );
    }

    #[test]
    fn cache_keys_are_limited_to_first_level_season_reads() {
        for path in PATHS {
            let uri = format!("{path}?season=2026").parse().unwrap();
            assert_eq!(cache_key(&uri), Some((*path, 2026)));
        }
        for uri in [
            "/api/v1/live/snapshot?season=2026",
            "/api/v1/results/season?season=+2026",
            "/api/v1/results/season?season=2024&season=2026",
        ] {
            assert!(cache_key(&uri.parse().unwrap()).is_none());
        }
    }
}
