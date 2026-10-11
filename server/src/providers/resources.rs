use crate::api::dto::Meta;
use reqwest::Client;
use std::{collections::HashMap, sync::Arc, time::Duration};
use tokio::{sync::Mutex, time::Instant};

#[derive(Clone)]
pub struct ResourceCache {
    client: Client,
    state: Arc<Mutex<CacheState>>,
    minimum_interval: Duration,
}
#[derive(Default)]
struct CacheState {
    entries: HashMap<String, Resource>,
    last_request: Option<Instant>,
    retry_at: Option<Instant>,
}
#[derive(Clone)]
pub struct Resource {
    pub bytes: Vec<u8>,
    pub content_type: String,
    pub fetched_at: String,
    pub stored_at: Instant,
    pub stale: bool,
}
impl ResourceCache {
    pub fn new(user_agent: &str, minimum_interval: Duration) -> Self {
        Self {
            client: Client::builder()
                .user_agent(user_agent)
                .timeout(Duration::from_secs(10))
                .redirect(reqwest::redirect::Policy::none())
                .build()
                .expect("resource client"),
            state: Arc::default(),
            minimum_interval,
        }
    }
    pub async fn get(
        &self,
        url: &str,
        now: &str,
        ttl: Duration,
        limit: usize,
    ) -> Result<Resource, &'static str> {
        // Serialize misses so duplicate clients cannot bypass the upstream budget.
        let mut state = self.state.lock().await;
        let cached = state.entries.get(url).cloned();
        if let Some(entry) = cached.as_ref().filter(|e| e.stored_at.elapsed() < ttl) {
            return Ok(entry.clone());
        }
        if state.retry_at.is_some_and(|t| t > Instant::now()) {
            return fallback(cached, "upstream_rate_limited");
        }
        if let Some(last) = state.last_request {
            tokio::time::sleep(self.minimum_interval.saturating_sub(last.elapsed())).await;
        }
        state.last_request = Some(Instant::now());
        let result = async {
            let mut response = self
                .client
                .get(url)
                .send()
                .await
                .map_err(|_| "upstream_unavailable")?;
            if response.status().as_u16() == 429 {
                let delay = response
                    .headers()
                    .get("retry-after")
                    .and_then(|v| v.to_str().ok())
                    .and_then(|v| {
                        v.parse::<u64>().ok().or_else(|| {
                            httpdate::parse_http_date(v)
                                .ok()?
                                .duration_since(std::time::SystemTime::now())
                                .ok()
                                .map(|d| d.as_secs())
                        })
                    })
                    .unwrap_or(60)
                    .clamp(1, 300);
                state.retry_at = Some(Instant::now() + Duration::from_secs(delay));
                return Err("upstream_rate_limited");
            }
            if !response.status().is_success() {
                return Err("upstream_unavailable");
            }
            if response.content_length().is_some_and(|n| n > limit as u64) {
                return Err("upstream_payload_too_large");
            }
            let content_type = response
                .headers()
                .get("content-type")
                .and_then(|v| v.to_str().ok())
                .unwrap_or("application/octet-stream")
                .to_string();
            let mut bytes = Vec::new();
            while let Some(chunk) = response.chunk().await.map_err(|_| "upstream_unavailable")? {
                if bytes.len() + chunk.len() > limit {
                    return Err("upstream_payload_too_large");
                }
                bytes.extend_from_slice(&chunk);
            }
            Ok(Resource {
                bytes,
                content_type,
                fetched_at: now.into(),
                stored_at: Instant::now(),
                stale: false,
            })
        }
        .await;
        match result {
            Ok(resource) => {
                if !ttl.is_zero() {
                    if state.entries.values().map(|e| e.bytes.len()).sum::<usize>()
                        + resource.bytes.len()
                        > 16 * 1024 * 1024
                        || state.entries.len() >= 128
                    {
                        state.entries.clear();
                    }
                    state.entries.insert(url.into(), resource.clone());
                }
                Ok(resource)
            }
            Err(error) => fallback(cached, error),
        }
    }
}
fn fallback(cached: Option<Resource>, error: &'static str) -> Result<Resource, &'static str> {
    match cached {
        Some(mut value) => {
            value.stale = true;
            Ok(value)
        }
        None => Err(error),
    }
}
impl Resource {
    pub fn meta(&self, source: &str) -> Meta {
        Meta::from_cache(
            Some(source.into()),
            Some(self.fetched_at.clone()),
            1,
            self.stale,
        )
    }
    pub fn json(&self) -> Result<serde_json::Value, &'static str> {
        serde_json::from_slice(&self.bytes).map_err(|_| "upstream_invalid_payload")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{Router, extract::State, http::StatusCode, routing::get};
    use std::sync::atomic::{AtomicUsize, Ordering};
    #[tokio::test]
    async fn test_cache_stale_retry_after_bounded_body_and_redirects() {
        let requests = Arc::new(AtomicUsize::new(0));
        let upstream = Router::new()
            .route(
                "/data",
                get(|State(n): State<Arc<AtomicUsize>>| async move {
                    if n.fetch_add(1, Ordering::SeqCst) == 0 {
                        (StatusCode::OK, [("retry-after", "60")], "cached")
                    } else {
                        (
                            StatusCode::TOO_MANY_REQUESTS,
                            [("retry-after", "60")],
                            "limited",
                        )
                    }
                }),
            )
            .route("/large", get(|| async { "too large" }))
            .route(
                "/redirect",
                get(|| async { (StatusCode::FOUND, [("location", "/data")], "") }),
            )
            .with_state(requests.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let server = tokio::spawn(async { axum::serve(listener, upstream).await.unwrap() });
        let cache = ResourceCache::new("test", Duration::ZERO);
        let url = format!("{base}/data");
        assert_eq!(
            cache
                .get(&url, "now", Duration::from_millis(1), 16)
                .await
                .unwrap()
                .bytes,
            b"cached"
        );
        tokio::time::sleep(Duration::from_millis(5)).await;
        assert!(
            cache
                .get(&url, "later", Duration::ZERO, 16)
                .await
                .unwrap()
                .stale
        );
        assert!(
            cache
                .get(&url, "later", Duration::ZERO, 16)
                .await
                .unwrap()
                .stale
        );
        assert_eq!(requests.load(Ordering::SeqCst), 2);
        assert!(matches!(
            cache
                .get(&format!("{base}/other"), "now", Duration::ZERO, 16)
                .await,
            Err("upstream_rate_limited")
        ));
        let fresh = ResourceCache::new("test", Duration::ZERO);
        assert!(matches!(
            fresh
                .get(&format!("{base}/large"), "now", Duration::ZERO, 2)
                .await,
            Err("upstream_payload_too_large")
        ));
        assert!(matches!(
            fresh
                .get(&format!("{base}/redirect"), "now", Duration::ZERO, 16)
                .await,
            Err("upstream_unavailable")
        ));
        assert_eq!(requests.load(Ordering::SeqCst), 2);
        server.abort();
    }
}
