use reqwest::Client;
use serde_json::Value;

use crate::config::ProvidersConfig;

#[derive(Debug, Clone)]
pub struct JolpicaProvider {
    pub client: Client,
    pub enabled: bool,
    pub base_url: String,
}

impl JolpicaProvider {
    pub fn new(config: &ProvidersConfig) -> Result<Self, reqwest::Error> {
        Ok(Self {
            client: Client::builder().user_agent(&config.user_agent).build()?,
            enabled: config.jolpica_enabled,
            base_url: "https://api.jolpi.ca".to_string(),
        })
    }

    /// Phase 0 integration point; paths will be finalized against recorded fixtures.
    pub async fn raw(&self, path: &str) -> Result<Value, reqwest::Error> {
        self.client
            .get(format!("{}{}", self.base_url, path))
            .send()
            .await?
            .json()
            .await
    }
}
