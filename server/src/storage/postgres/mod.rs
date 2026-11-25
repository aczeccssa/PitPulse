mod cache;
mod import;
mod read;
mod write;
pub use cache::{SeasonCacheConfig, SeasonCacheStats};
pub use import::ImportCount;

use std::{path::Path, sync::Arc, time::Duration};

use deadpool_postgres::{Client, Hook, HookError, Manager, Pool, Runtime};
use native_tls::{Certificate, TlsConnector};
use postgres_native_tls::MakeTlsConnector;
use tokio_postgres::config::{Host, SslMode};
use url::Url;

use crate::error::StorageError;

const MIGRATION: &str = include_str!("migrations/0001_season_data.sql");
const TIMEOUT: Duration = Duration::from_secs(3);
pub const DEFAULT_SCHEMA: &str = "pitpulse_season";

/// Lazy pool so a central outage cannot keep the local server or Live offline.
#[derive(Clone)]
pub struct Postgres {
    pool: Pool,
    schema: String,
    cache: Arc<cache::Cache>,
}

impl Postgres {
    pub fn new(dsn: &str, schema: &str, read_only: bool) -> Result<Self, StorageError> {
        if !valid_identifier(schema) || !schema.starts_with("pitpulse_") {
            return Err(StorageError::SeasonConfig(
                "schema must be a pitpulse_ identifier",
            ));
        }
        let (mut config, tls) = connection_options(dsn)?;
        let mut settings = format!(
            "SET search_path TO {schema}, pg_catalog; SET timezone TO 'UTC'; \
             SET statement_timeout TO 3000; SET lock_timeout TO 2000; \
             SET idle_in_transaction_session_timeout TO 5000;"
        );
        if read_only {
            settings.push_str(" SET default_transaction_read_only TO on;");
        }
        config.connect_timeout(TIMEOUT);
        let pool = Pool::builder(Manager::new(config, tls))
            .post_create(Hook::async_fn(move |client, _| {
                let settings = settings.clone();
                Box::pin(async move {
                    client
                        .batch_execute(&settings)
                        .await
                        .map_err(HookError::Backend)
                })
            }))
            .runtime(Runtime::Tokio1)
            .max_size(8)
            .wait_timeout(Some(TIMEOUT))
            .create_timeout(Some(TIMEOUT))
            .recycle_timeout(Some(TIMEOUT))
            .build()
            .map_err(|_| StorageError::SeasonConfig("could not configure Postgres pool"))?;
        Ok(Self {
            pool,
            schema: schema.to_owned(),
            cache: Arc::new(cache::Cache::new(if read_only {
                SeasonCacheConfig::default()
            } else {
                SeasonCacheConfig {
                    capacity: 0,
                    ..SeasonCacheConfig::default()
                }
            })),
        })
    }

    pub fn with_cache(mut self, config: SeasonCacheConfig) -> Self {
        self.cache = Arc::new(cache::Cache::new(config));
        self
    }

    pub fn cache_stats(&self) -> SeasonCacheStats {
        self.cache.stats()
    }

    async fn dataset_generation(&self) -> Result<i64, StorageError> {
        Ok(self
            .client()
            .await?
            .query_one(
                "SELECT generation FROM dataset_generation WHERE singleton",
                &[],
            )
            .await?
            .try_get(0)?)
    }

    pub(super) async fn client(&self) -> Result<Client, StorageError> {
        self.pool
            .get()
            .await
            .map_err(|_| StorageError::SeasonUnavailable)
    }

    async fn lock_writes(
        &self,
        tx: &deadpool_postgres::Transaction<'_>,
    ) -> Result<(), StorageError> {
        tx.query_one(
            "SELECT pg_advisory_xact_lock(hashtextextended($1, 57))",
            &[&self.schema],
        )
        .await?;
        Ok(())
    }

    pub async fn migrate(&self, reader_role: Option<&str>) -> Result<(), StorageError> {
        if reader_role.is_some_and(|role| !valid_identifier(role)) {
            return Err(StorageError::SeasonConfig("invalid reader role identifier"));
        }
        let mut client = self.client().await?;
        let tx = client.transaction().await?;
        self.lock_writes(&tx).await?;
        tx.batch_execute(&format!(
            "CREATE SCHEMA IF NOT EXISTS {}; REVOKE ALL ON SCHEMA {} FROM PUBLIC",
            self.schema, self.schema
        ))
        .await?;
        let installed: bool = tx
            .query_one(
                "SELECT to_regclass(format('%I.schema_migrations', $1::text)) IS NOT NULL",
                &[&self.schema],
            )
            .await?
            .get(0);
        if !installed {
            tx.batch_execute(MIGRATION).await?;
            tx.execute("INSERT INTO schema_migrations (version) VALUES (1)", &[])
                .await?;
        } else {
            let version: Option<i64> = tx
                .query_one("SELECT max(version) FROM schema_migrations", &[])
                .await?
                .get(0);
            if version != Some(1) {
                return Err(StorageError::SeasonConfig(
                    "unsupported Postgres schema version",
                ));
            }
        }
        if let Some(role) = reader_role {
            tx.batch_execute(&format!(
                "GRANT USAGE ON SCHEMA {schema} TO {role}; \
                 GRANT SELECT ON ALL TABLES IN SCHEMA {schema} TO {role}",
                schema = self.schema,
            ))
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

fn valid_identifier(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 63
        && s.as_bytes()[0].is_ascii_lowercase()
        && s.bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_')
}

fn connection_options(
    dsn: &str,
) -> Result<(tokio_postgres::Config, MakeTlsConnector), StorageError> {
    let mut url =
        Url::parse(dsn).map_err(|_| StorageError::SeasonConfig("invalid Postgres URL"))?;
    if !matches!(url.scheme(), "postgres" | "postgresql") || url.fragment().is_some() {
        return Err(StorageError::SeasonConfig("expected a Postgres URL"));
    }
    let params: Vec<_> = url.query_pairs().into_owned().collect();
    url.set_query(None);
    let mut config: tokio_postgres::Config = url
        .as_str()
        .parse()
        .map_err(|_| StorageError::SeasonConfig("invalid Postgres URL options"))?;
    let loopback = matches!(config.get_hosts(), [Host::Tcp(host)] if matches!(host.as_str(), "127.0.0.1" | "::1"));
    let mut mode = None;
    let mut ca = None;
    for (key, value) in &params {
        match key.as_str() {
            "sslmode" if mode.is_none() => mode = Some(value.as_str()),
            "sslrootcert" if ca.is_none() => ca = Some(value.as_str()),
            _ => {
                return Err(StorageError::SeasonConfig(
                    "unsupported or repeated Postgres URL option",
                ));
            }
        }
    }
    config.ssl_mode(match mode {
        Some("disable") if loopback && ca.is_none() => SslMode::Disable,
        None | Some("verify-full") => SslMode::Require,
        _ => {
            return Err(StorageError::SeasonConfig(
                "Postgres requires sslmode=verify-full except loopback tests",
            ));
        }
    });
    let mut builder = TlsConnector::builder();
    if let Some(path) = ca {
        let data = std::fs::read(Path::new(path))
            .map_err(|_| StorageError::SeasonConfig("could not read Postgres CA certificate"))?;
        let certificate = Certificate::from_pem(&data)
            .map_err(|_| StorageError::SeasonConfig("invalid Postgres CA certificate"))?;
        builder.add_root_certificate(certificate);
    }
    let tls = builder
        .build()
        .map_err(|_| StorageError::SeasonConfig("could not configure Postgres TLS"))?;
    Ok((config, MakeTlsConnector::new(tls)))
}
