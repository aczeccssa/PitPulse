use std::time::{Duration, SystemTime};

use reqwest::{Client, Url};
use serde::de::DeserializeOwned;
use serde_json::Value;
use tokio::sync::Mutex;

use crate::error::ProviderError;

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(8);
const MAX_ATTEMPTS: u32 = 3;

pub fn shared_client(user_agent: &str) -> Result<Client, reqwest::Error> {
    Client::builder()
        .user_agent(user_agent)
        .connect_timeout(Duration::from_secs(3))
        .timeout(DEFAULT_TIMEOUT)
        .redirect(reqwest::redirect::Policy::limited(4))
        .build()
}

pub async fn get_json(client: &Client, url: &str) -> Result<Value, ProviderError> {
    get_json_typed(client, url, None).await
}

pub async fn get_json_with_min_interval(
    client: &Client,
    url: &str,
    last_request: &Mutex<Option<tokio::time::Instant>>,
    min_interval: Duration,
) -> Result<Value, ProviderError> {
    get_json_typed(client, url, Some((last_request, min_interval))).await
}

async fn get_json_typed<T: DeserializeOwned>(
    client: &Client,
    url: &str,
    limiter: Option<(&Mutex<Option<tokio::time::Instant>>, Duration)>,
) -> Result<T, ProviderError> {
    let mut delay = Duration::from_millis(50);
    let mut last_error = None;
    for attempt in 1..=MAX_ATTEMPTS {
        if let Some((last_request, min_interval)) = limiter {
            let mut last = last_request.lock().await;
            if let Some(previous) = *last {
                let remaining = min_interval.saturating_sub(previous.elapsed());
                if !remaining.is_zero() {
                    tokio::time::sleep(remaining).await;
                }
            }
            *last = Some(tokio::time::Instant::now());
        }
        match request_once(client, url).await {
            Ok(value) => return Ok(value),
            Err(error) if error.is_retryable() && attempt < MAX_ATTEMPTS => {
                let wait = error
                    .retry_after()
                    .unwrap_or_else(|| delay.min(Duration::from_secs(2)));
                tokio::time::sleep(wait).await;
                delay = delay.saturating_mul(2).min(Duration::from_secs(2));
                last_error = Some(error);
            }
            Err(error) => return Err(error),
        }
    }
    Err(last_error.unwrap_or_else(|| ProviderError::Transport {
        url: url.to_string(),
        error: "request failed".to_string(),
    }))
}

async fn request_once<T: DeserializeOwned>(client: &Client, url: &str) -> Result<T, ProviderError> {
    let response = client
        .get(url)
        .send()
        .await
        .map_err(|error| ProviderError::Transport {
            url: url.to_string(),
            error: error.to_string(),
        })?;
    let status = response.status();
    if !status.is_success() {
        let retry_after = response
            .headers()
            .get(reqwest::header::RETRY_AFTER)
            .and_then(|value| value.to_str().ok())
            .and_then(parse_retry_after);
        return Err(ProviderError::Http {
            url: url.to_string(),
            status: status.as_u16(),
            retry_after,
        });
    }
    response
        .json()
        .await
        .map_err(|error| ProviderError::Decode {
            url: url.to_string(),
            error: error.to_string(),
        })
}

pub fn with_query(
    base: &str,
    path: &str,
    query: &[(&str, String)],
) -> Result<String, ProviderError> {
    let mut url =
        Url::parse(&format!("{base}{path}")).map_err(|error| ProviderError::InvalidUrl {
            url: format!("{base}{path}"),
            error: error.to_string(),
        })?;
    {
        let mut pairs = url.query_pairs_mut();
        for (key, value) in query {
            if !value.is_empty() {
                pairs.append_pair(key, value);
            }
        }
    }
    Ok(url.to_string())
}

pub fn next_page(root: &Value) -> Option<String> {
    root.pointer("/MRData")
        .and_then(page_from_mrdata)
        .or_else(|| {
            root.get("metadata")
                .and_then(|metadata| metadata.get("next"))
                .and_then(Value::as_str)
                .map(str::to_string)
        })
}

fn page_from_mrdata(data: &Value) -> Option<String> {
    let total = data.get("total")?.as_str()?.parse::<u64>().ok()?;
    let limit = data.get("limit")?.as_str()?.parse::<u64>().ok()?;
    let offset = data.get("offset")?.as_str()?.parse::<u64>().ok()?;
    if limit == 0 || offset.saturating_add(limit) >= total {
        return None;
    }
    let mut url = Url::parse(data.get("url")?.as_str()?).ok()?;
    let filters = url
        .query_pairs()
        .filter(|(key, _)| key != "limit" && key != "offset")
        .map(|(key, value)| (key.into_owned(), value.into_owned()))
        .collect::<Vec<_>>();
    let mut query = url.query_pairs_mut();
    query.clear();
    for (key, value) in filters {
        query.append_pair(&key, &value);
    }
    query
        .append_pair("limit", &limit.to_string())
        .append_pair("offset", &(offset + limit).to_string());
    drop(query);
    Some(url.to_string())
}

pub async fn get_pages(
    client: &Client,
    first_url: &str,
    mut collect: impl FnMut(&Value) -> Result<(), ProviderError>,
) -> Result<(), ProviderError> {
    let mut url = first_url.to_string();
    for _ in 0..8 {
        let page = get_json(client, &url).await?;
        collect(&page)?;
        match next_page(&page) {
            Some(next) if next != url => url = next,
            _ => return Ok(()),
        }
    }
    Err(ProviderError::Pagination {
        url: first_url.to_string(),
    })
}

fn parse_retry_after(value: &str) -> Option<Duration> {
    if let Ok(seconds) = value.parse::<u64>() {
        return Some(Duration::from_secs(seconds));
    }
    let retry_at = httpdate::parse_http_date(value).ok()?;
    Some(
        retry_at
            .duration_since(SystemTime::now())
            .unwrap_or(Duration::ZERO),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::{
        Json, Router, extract::State, http::StatusCode, response::IntoResponse, routing::get,
    };
    use std::sync::{
        Arc,
        atomic::{AtomicUsize, Ordering},
    };
    use tokio::net::TcpListener;

    #[test]
    fn test_retry_after_accepts_delta_seconds_and_http_date() {
        assert_eq!(parse_retry_after("9"), Some(Duration::from_secs(9)));
        let future = httpdate::fmt_http_date(SystemTime::now() + Duration::from_secs(5));
        let wait = parse_retry_after(&future).unwrap();
        assert!(wait <= Duration::from_secs(5));
        assert!(wait >= Duration::from_secs(3));
        assert_eq!(parse_retry_after("invalid"), None);
    }

    #[tokio::test]
    async fn test_min_interval_applies_between_retries() {
        async fn retry_once(State(calls): State<Arc<AtomicUsize>>) -> axum::response::Response {
            if calls.fetch_add(1, Ordering::SeqCst) == 0 {
                (
                    StatusCode::SERVICE_UNAVAILABLE,
                    [(reqwest::header::RETRY_AFTER, "0")],
                )
                    .into_response()
            } else {
                Json(serde_json::json!({"ok": true})).into_response()
            }
        }

        let calls = Arc::new(AtomicUsize::new(0));
        let app = Router::new()
            .route("/retry", get(retry_once))
            .with_state(calls.clone());
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let server = tokio::spawn(async move {
            axum::serve(listener, app).await.unwrap();
        });
        let last_request = Mutex::new(None);
        let started = tokio::time::Instant::now();
        let result = get_json_with_min_interval(
            &Client::new(),
            &format!("http://{address}/retry"),
            &last_request,
            Duration::from_millis(300),
        )
        .await
        .unwrap();
        assert_eq!(result["ok"], true);
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert!(started.elapsed() >= Duration::from_millis(250));
        server.abort();
    }
}
