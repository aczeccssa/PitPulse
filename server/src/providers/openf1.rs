use reqwest::Client;
use serde_json::Value;

use crate::config::ProvidersConfig;

#[derive(Debug, Clone)]
pub struct OpenF1Provider {
    pub client: Client,
    pub enabled: bool,
    pub base_url: String,
}

impl OpenF1Provider {
    pub fn new(config: &ProvidersConfig) -> Result<Self, reqwest::Error> {
        Ok(Self {
            client: Client::builder().user_agent(&config.user_agent).build()?,
            enabled: config.openf1_enabled,
            base_url: "https://api.openf1.org".to_string(),
        })
    }

    /// Phase 0 integration point; results and session keys require fixture validation.
    pub async fn raw(&self, path: &str) -> Result<Value, reqwest::Error> {
        self.client
            .get(format!("{}{}", self.base_url, path))
            .send()
            .await?
            .json()
            .await
    }
}
