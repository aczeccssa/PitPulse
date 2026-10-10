use std::{net::SocketAddr, path::PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::ConfigError;

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct AppConfig {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub providers: ProvidersConfig,
    pub live: LiveConfig,
    pub security: SecurityConfig,
    pub scheduler: SchedulerConfig,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ServerConfig {
    pub bind: SocketAddr,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct DatabaseConfig {
    pub path: PathBuf,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ProvidersConfig {
    pub jolpica_enabled: bool,
    pub openf1_enabled: bool,
    pub f1_live_enabled: bool,
    pub user_agent: String,
    #[serde(skip)]
    pub f1_live_access_token: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct LiveConfig {
    pub snapshot_interval_seconds: u64,
    pub stale_after_seconds: u64,
    #[serde(default = "default_live_disconnect_after_seconds")]
    pub disconnect_after_seconds: u64,
}

const fn default_live_disconnect_after_seconds() -> u64 {
    120
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SecurityConfig {
    pub require_token: bool,
    #[serde(skip)]
    pub token: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct SchedulerConfig {
    pub calendar_interval_seconds: u64,
    pub standings_interval_seconds: u64,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            server: ServerConfig {
                bind: "127.0.0.1:38701"
                    .parse()
                    .expect("valid default bind address"),
            },
            database: DatabaseConfig {
                path: PathBuf::from("data/pitpulse.sqlite"),
            },
            providers: ProvidersConfig {
                jolpica_enabled: true,
                openf1_enabled: true,
                f1_live_enabled: true,
                user_agent: "PitPulse/0.1 (+https://github.com/)".to_string(),
                f1_live_access_token: None,
            },
            live: LiveConfig {
                snapshot_interval_seconds: 15,
                stale_after_seconds: 60,
                disconnect_after_seconds: default_live_disconnect_after_seconds(),
            },
            security: SecurityConfig {
                require_token: false,
                token: None,
            },
            scheduler: SchedulerConfig {
                calendar_interval_seconds: 6 * 60 * 60,
                standings_interval_seconds: 6 * 60 * 60,
            },
        }
    }
}

impl AppConfig {
    pub fn load(path: Option<&std::path::Path>) -> Result<Self, ConfigError> {
        let mut config = Self::default();

        if let Some(path) = path {
            let raw = std::fs::read_to_string(path).map_err(|error| ConfigError::Io {
                path: path.to_path_buf(),
                error,
            })?;
            let file = toml::from_str::<Self>(&raw).map_err(|error| ConfigError::Parse {
                path: path.to_path_buf(),
                error,
            })?;
            config.merge(file);
        }

        if let Ok(value) = std::env::var("F1_COMPANION_BIND") {
            config.server.bind =
                value
                    .parse::<SocketAddr>()
                    .map_err(|error| ConfigError::InvalidValue {
                        field: "server.bind".to_string(),
                        error: error.to_string(),
                    })?;
        }

        if let Ok(value) = std::env::var("F1_COMPANION_DATABASE_PATH") {
            config.database.path = PathBuf::from(value);
        }

        if let Ok(value) = std::env::var("F1_COMPANION_TOKEN") {
            if value.trim().is_empty() {
                return Err(ConfigError::EmptyToken);
            }
            config.security.token = Some(value);
        }

        if let Ok(value) = std::env::var("F1_COMPANION_REQUIRE_TOKEN") {
            config.security.require_token = matches!(
                value.trim().to_ascii_lowercase().as_str(),
                "1" | "true" | "yes" | "on"
            );
        }

        if let Ok(value) = std::env::var("F1_LIVE_ACCESS_TOKEN") {
            if value.trim().is_empty() {
                return Err(ConfigError::EmptyToken);
            }
            config.providers.f1_live_access_token = Some(value);
        }

        if config.security.require_token && config.security.token.is_none() {
            return Err(ConfigError::MissingRequiredToken);
        }

        Ok(config)
    }

    fn merge(&mut self, file: Self) {
        self.server = file.server;
        self.database = file.database;
        self.providers = file.providers;
        self.live = file.live;
        self.scheduler = file.scheduler;
        self.security = file.security;
    }
}
