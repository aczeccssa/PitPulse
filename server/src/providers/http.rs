use std::time::Duration;

use reqwest::{Client, Url};
use serde::de::DeserializeOwned;
use serde_json::Value;

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
    get_json_typed(client, url).await
}

async fn get_json_typed<T: DeserializeOwned>(
    client: &Client,
    url: &str,
) -> Result<T, ProviderError> {
    let mut delay = Duration::from_millis(50);
    let mut last_error = None;
    for attempt in 1..=MAX_ATTEMPTS {
        match request_once(client, url).await {
            Ok(value) => return Ok(value),
            Err(error) if error.is_retryable() && attempt < MAX_ATTEMPTS => {
                let wait = error.retry_after().unwrap_or(delay);
                tokio::time::sleep(wait.min(Duration::from_secs(2))).await;
                delay = delay.saturating_mul(2);
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
    url.query_pairs_mut()
        .clear()
        .append_pair("limit", &limit.to_string())
        .append_pair("offset", &(offset + limit).to_string());
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
    None
}
