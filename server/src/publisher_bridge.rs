//! Private, same-host IPC. The public server remains a read-only Postgres client.
use std::{
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    time::Duration,
};

use anyhow::Context;
use axum::{
    Json, Router,
    body::Body,
    extract::{Path as RoutePath, State},
    http::StatusCode,
    response::Response,
    routing::{get, post},
};
use futures_util::StreamExt;
use tokio::{net::UnixListener, sync::broadcast, task::JoinHandle};
use tokio_stream::wrappers::BroadcastStream;

use crate::{
    api::{
        dto::SyncStatus,
        refresh::{DataRefreshEvent, RefreshRequest, run_manual_refresh},
    },
    app_state::AppState,
    error::{ApiError, StorageError},
};

const ORIGIN: &str = "http://publisher";
const REFRESH_TIMEOUT: Duration = Duration::from_secs(85);
const STATUS_TIMEOUT: Duration = Duration::from_millis(250);
const EVENT_LIMIT: usize = 16 * 1024;
const EVENT_HEARTBEAT: Duration = Duration::from_secs(5);

#[derive(Clone)]
pub(crate) struct PublisherClient(reqwest::Client);

impl PublisherClient {
    pub(crate) fn new(path: &Path) -> anyhow::Result<Self> {
        anyhow::ensure!(
            path.is_absolute(),
            "PITPULSE_PUBLISH_SOCKET must be absolute"
        );
        Ok(Self(
            reqwest::Client::builder()
                .unix_socket(path.to_path_buf())
                .no_proxy()
                .redirect(reqwest::redirect::Policy::none())
                .connect_timeout(STATUS_TIMEOUT)
                .build()?,
        ))
    }

    pub(crate) async fn refresh(
        &self,
        request: &RefreshRequest,
    ) -> Result<DataRefreshEvent, ApiError> {
        let response = self
            .0
            .post(format!("{ORIGIN}/refresh"))
            .json(request)
            .timeout(REFRESH_TIMEOUT)
            .send()
            .await
            .map_err(|_| ApiError::RefreshUnavailable)?;
        if response.status() == StatusCode::SERVICE_UNAVAILABLE {
            let error = response.json::<serde_json::Value>().await.ok();
            if error
                .as_ref()
                .is_some_and(|value| value["error"]["code"] == "refresh_queue_full")
            {
                return Err(ApiError::RefreshQueueFull);
            }
        } else if response.status() == StatusCode::OK {
            return response
                .json()
                .await
                .map_err(|_| ApiError::RefreshUnavailable);
        }
        Err(ApiError::RefreshUnavailable)
    }

    pub(crate) async fn sync_status(&self, endpoint: &str) -> Option<SyncStatus> {
        let mut url = reqwest::Url::parse(ORIGIN).expect("static publisher origin");
        url.path_segments_mut()
            .expect("publisher base URL")
            .extend(["status", endpoint]);
        // Sync metadata is optional. An absent publisher must not hide cached
        // canonical data or convert a good response into a storage failure.
        self.0
            .get(url)
            .timeout(STATUS_TIMEOUT)
            .send()
            .await
            .ok()?
            .error_for_status()
            .ok()?
            .json()
            .await
            .ok()
            .flatten()
    }

    pub(crate) async fn relay_events(self, sender: broadcast::Sender<DataRefreshEvent>) {
        loop {
            self.forward_events(&sender).await;
            tokio::time::sleep(Duration::from_secs(1)).await;
        }
    }

    async fn forward_events(&self, sender: &broadcast::Sender<DataRefreshEvent>) {
        let Ok(Ok(mut response)) = tokio::time::timeout(
            Duration::from_secs(1),
            self.0.get(format!("{ORIGIN}/events")).send(),
        )
        .await
        else {
            return;
        };
        if response.status() != StatusCode::OK {
            return;
        }
        let mut line = Vec::new();
        while let Ok(Ok(Some(chunk))) =
            tokio::time::timeout(EVENT_HEARTBEAT * 3, response.chunk()).await
        {
            for part in chunk.split_inclusive(|byte| *byte == b'\n') {
                if line.len() + part.len() > EVENT_LIMIT {
                    return;
                }
                line.extend_from_slice(part);
                if part.ends_with(b"\n") {
                    if let Ok(event) = serde_json::from_slice::<DataRefreshEvent>(&line) {
                        let _ = sender.send(event);
                    }
                    line.clear();
                }
            }
        }
    }
}

pub(crate) struct PublisherListener {
    task: JoinHandle<()>,
    path: PathBuf,
}

impl Drop for PublisherListener {
    fn drop(&mut self) {
        self.task.abort();
        let _ = std::fs::remove_file(&self.path);
    }
}

pub(crate) fn serve(path: &Path, state: AppState) -> anyhow::Result<PublisherListener> {
    anyhow::ensure!(
        path.is_absolute(),
        "PITPULSE_PUBLISH_SOCKET must be absolute"
    );
    let parent = path
        .parent()
        .context("publisher socket needs a private directory")?;
    let metadata = parent
        .metadata()
        .context("publisher socket directory unavailable")?;
    anyhow::ensure!(
        metadata.is_dir() && metadata.permissions().mode() & 0o027 == 0,
        "publisher socket directory must be private and not group-writable"
    );
    // Never unlink an existing listener on startup. After an unclean shutdown
    // the operator can remove the stale socket after confirming its owner exited.
    let listener = UnixListener::bind(path).context("could not bind publisher socket")?;
    if let Err(error) = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o660)) {
        let _ = std::fs::remove_file(path);
        return Err(error).context("could not restrict publisher socket permissions");
    }
    let router = Router::new()
        .route("/ready", get(ready))
        .route("/refresh", post(refresh))
        .route("/status/{endpoint}", get(status))
        .route("/events", get(events))
        .with_state(state);
    let task = tokio::spawn(async move {
        if let Err(error) = axum::serve(listener, router).await {
            tracing::warn!(%error, "publisher socket stopped");
        }
    });
    Ok(PublisherListener {
        task,
        path: path.to_owned(),
    })
}

async fn ready(State(state): State<AppState>) -> StatusCode {
    match state.database.publisher_ready().await {
        Ok(()) => StatusCode::NO_CONTENT,
        Err(_) => StatusCode::SERVICE_UNAVAILABLE,
    }
}

async fn refresh(
    State(state): State<AppState>,
    Json(request): Json<RefreshRequest>,
) -> Result<Json<DataRefreshEvent>, ApiError> {
    run_manual_refresh(&state.refresh_queue, request).await
}

async fn status(
    State(state): State<AppState>,
    RoutePath(endpoint): RoutePath<String>,
) -> Result<Json<Option<SyncStatus>>, StorageError> {
    state
        .database
        .sync_status("jolpica-alpha", &endpoint)
        .await
        .map(Json)
}

async fn events(State(state): State<AppState>) -> Response {
    let events = BroadcastStream::new(state.refresh_events.subscribe()).filter_map(|event| async {
        let mut json = serde_json::to_vec(&event.ok()?).ok()?;
        json.push(b'\n');
        Some(Ok::<_, std::convert::Infallible>(json))
    });
    let heartbeat =
        tokio_stream::wrappers::IntervalStream::new(tokio::time::interval(EVENT_HEARTBEAT))
            .map(|_| Ok(vec![b'\n']));
    Response::new(Body::from_stream(tokio_stream::StreamExt::merge(
        events, heartbeat,
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        api::refresh::RefreshStatus,
        config::AppConfig,
        scheduler,
        storage::{postgres::Postgres, sqlite::Database},
    };
    use axum::{body::to_bytes, http::Request};
    use serde_json::{Value, json};
    use tower::ServiceExt;

    async fn request(router: &Router, request: Request<Body>) -> (StatusCode, Value) {
        let response = router.clone().oneshot(request).await.unwrap();
        let status = response.status();
        let bytes = to_bytes(response.into_body(), 1024 * 1024).await.unwrap();
        (status, serde_json::from_slice(&bytes).unwrap())
    }

    fn calendar_refresh() -> Request<Body> {
        Request::post("/api/v1/refresh")
            .header("content-type", "application/json")
            .body(Body::from(r#"{"season":2024,"target":"calendar"}"#))
            .unwrap()
    }

    #[tokio::test]
    async fn central_refresh_uses_publisher_queue_and_relays_events() {
        async fn database() -> Database {
            let db = Database::open(Path::new(":memory:")).await.unwrap();
            db.migrate().await.unwrap();
            db
        }
        let work = tempfile::tempdir().unwrap();
        std::fs::set_permissions(work.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        let mut config = AppConfig::default();
        config.providers.jolpica_enabled = false;
        let legacy = AppState::new(config.clone(), database().await);
        let publisher = AppState::new(config.clone(), database().await);
        // Calendar refresh requires no canonical query when the provider is off.
        // The only preceding Postgres call is the scheduler's identity probe.
        let central = AppState::new(
            config,
            database().await.with_season_reader(
                Postgres::new(
                    "postgres://fixture@127.0.0.1:1/fixture?sslmode=disable",
                    "pitpulse_fixture",
                    true,
                )
                .unwrap(),
            ),
        );
        let socket = work.path().join("sync.sock");
        let bridge = serve(&socket, publisher.clone()).unwrap();
        assert!(serve(&socket, publisher.clone()).is_err());
        let central = central.with_publisher_socket(&socket).unwrap();
        let legacy_loop = tokio::spawn(scheduler::run_season_scheduler(legacy.clone()));
        let publisher_loop = tokio::spawn(scheduler::run_season_scheduler(publisher.clone()));
        let client = central.publisher.clone().unwrap();
        let mut events = central.refresh_events.subscribe();
        let event_relay = tokio::spawn(client.clone().relay_events(central.refresh_events.clone()));
        tokio::time::timeout(Duration::from_secs(3), async {
            while publisher.refresh_events.receiver_count() == 0 {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await
        .unwrap();
        let central_router = crate::server::router(central);
        let legacy_router = crate::server::router(legacy);
        let (old_status, mut old_event) = request(&legacy_router, calendar_refresh()).await;
        let (new_status, mut new_event) = request(&central_router, calendar_refresh()).await;
        assert_eq!(old_status, StatusCode::OK);
        assert_eq!(new_status, old_status);
        for event in [&mut old_event, &mut new_event] {
            assert!(
                crate::scheduler::parse_utc_seconds(event["updatedAt"].as_str().unwrap()).is_some()
            );
            event.as_object_mut().unwrap().remove("updatedAt");
        }
        assert_eq!(old_event, new_event);
        assert_eq!(
            new_event,
            json!({"target":"calendar", "season":2024, "sessionId":null, "status":"failed", "retryAfter":null})
        );
        for status in [RefreshStatus::InProgress, RefreshStatus::Failed] {
            let event = tokio::time::timeout(Duration::from_secs(3), events.recv())
                .await
                .unwrap()
                .unwrap();
            assert_eq!(event.status, status);
            assert_eq!(event.target, crate::api::refresh::RefreshTarget::Calendar);
        }
        let attempted = "2024-03-04T12:00:00Z";
        publisher
            .database
            .sync_begin("jolpica-alpha", "calendar-2024", attempted)
            .await
            .unwrap();
        assert_eq!(
            client
                .sync_status("calendar-2024")
                .await
                .unwrap()
                .last_attempt_at,
            attempted
        );
        assert!(client.sync_status("calendar-2025").await.is_none());
        event_relay.abort();
        legacy_loop.abort();
        publisher_loop.abort();
        drop(bridge);
        assert!(!socket.exists());
        assert_eq!(
            request(&central_router, calendar_refresh()).await.0,
            StatusCode::SERVICE_UNAVAILABLE
        );
    }
}
