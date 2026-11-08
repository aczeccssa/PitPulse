use std::{
    collections::{HashMap, VecDeque},
    sync::Arc,
};

use axum::{Json, extract::State};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, Notify, oneshot};

use crate::{app_state::AppState, error::ApiError};

pub async fn refresh(
    State(state): State<AppState>,
    Json(request): Json<RefreshRequest>,
) -> Result<Json<DataRefreshEvent>, ApiError> {
    if !(1950..=9999).contains(&request.season) {
        return Err(ApiError::InvalidQuery {
            field: "season".to_string(),
            error: "season must be between 1950 and 9999".to_string(),
        });
    }
    match request.target {
        RefreshTarget::Results => {
            let Some(session_id) = request.session_id.as_deref() else {
                return Err(ApiError::InvalidQuery {
                    field: "sessionId".to_string(),
                    error: "sessionId is required for results refresh".to_string(),
                });
            };
            let sessions = state.database.calendar(Some(request.season)).await?.0;
            if !sessions.iter().any(|meeting| {
                meeting
                    .sessions
                    .iter()
                    .any(|session| session.id == session_id)
            }) {
                return Err(ApiError::NotFound);
            }
        }
        _ if request.session_id.is_some() => {
            return Err(ApiError::InvalidQuery {
                field: "sessionId".to_string(),
                error: "sessionId is only valid for results refresh".to_string(),
            });
        }
        _ => {}
    }
    let completion = state
        .refresh_queue
        .enqueue_manual(request)
        .await
        .map_err(|_| ApiError::RefreshQueueFull)?;
    completion
        .await
        .map(Json)
        .map_err(|_| ApiError::RefreshUnavailable)
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq, Hash)]
#[serde(rename_all = "camelCase")]
pub enum RefreshTarget {
    Calendar,
    Results,
    Standings,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RefreshRequest {
    pub season: i64,
    pub target: RefreshTarget,
    #[serde(default)]
    pub session_id: Option<String>,
}

#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum RefreshStatus {
    InProgress,
    Completed,
    Partial,
    Failed,
    RateLimited,
}

#[derive(Debug, Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DataRefreshEvent {
    pub target: RefreshTarget,
    pub season: i64,
    pub session_id: Option<String>,
    pub status: RefreshStatus,
    pub updated_at: String,
    pub retry_after: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct RefreshKey(i64, RefreshTarget, Option<String>);

impl RefreshRequest {
    fn key(&self) -> RefreshKey {
        RefreshKey(
            self.season,
            self.target,
            (self.target == RefreshTarget::Results)
                .then(|| self.session_id.clone())
                .flatten(),
        )
    }
}

struct PendingRefresh {
    request: RefreshRequest,
    waiters: Vec<oneshot::Sender<DataRefreshEvent>>,
    manual: bool,
}

#[derive(Default)]
struct QueueState {
    manual: VecDeque<PendingRefresh>,
    background: VecDeque<PendingRefresh>,
    running: HashMap<RefreshKey, RunningRefresh>,
}

struct RunningRefresh {
    waiters: Vec<oneshot::Sender<DataRefreshEvent>>,
    manual: bool,
}

#[derive(Clone, Default)]
pub struct RefreshQueue {
    state: Arc<Mutex<QueueState>>,
    notify: Arc<Notify>,
}

pub struct RefreshJob {
    pub request: RefreshRequest,
    pub manual: bool,
    key: RefreshKey,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct QueueFull;

impl RefreshQueue {
    pub async fn enqueue_manual(
        &self,
        request: RefreshRequest,
    ) -> Result<oneshot::Receiver<DataRefreshEvent>, QueueFull> {
        let (sender, receiver) = oneshot::channel();
        let key = request.key();
        let mut state = self.state.lock().await;
        if let Some(running) = state.running.get_mut(&key) {
            running.waiters.push(sender);
            running.manual = true;
        } else if let Some(pending) = state.manual.iter_mut().find(|job| job.request.key() == key) {
            pending.waiters.push(sender);
        } else if let Some(index) = state
            .background
            .iter()
            .position(|job| job.request.key() == key)
        {
            let mut pending = state.background.remove(index).expect("queued job exists");
            pending.manual = true;
            pending.waiters.push(sender);
            state.manual.push_back(pending);
        } else {
            if state.manual.len() + state.background.len() >= 32 {
                return Err(QueueFull);
            }
            state.manual.push_back(PendingRefresh {
                request,
                waiters: vec![sender],
                manual: true,
            });
        }
        drop(state);
        self.notify.notify_one();
        Ok(receiver)
    }

    pub async fn enqueue_background(&self, request: RefreshRequest) {
        let key = request.key();
        let mut state = self.state.lock().await;
        if state.running.contains_key(&key)
            || state.manual.iter().any(|job| job.request.key() == key)
            || state.background.iter().any(|job| job.request.key() == key)
            || state.manual.len() + state.background.len() >= 32
        {
            return;
        }
        state.background.push_back(PendingRefresh {
            request,
            waiters: Vec::new(),
            manual: false,
        });
        drop(state);
        self.notify.notify_one();
    }

    pub async fn next(&self) -> RefreshJob {
        loop {
            let notified = self.notify.notified();
            let mut state = self.state.lock().await;
            let pending = state
                .manual
                .pop_front()
                .or_else(|| state.background.pop_front());
            if let Some(pending) = pending {
                let key = pending.request.key();
                state.running.insert(
                    key.clone(),
                    RunningRefresh {
                        waiters: pending.waiters,
                        manual: pending.manual,
                    },
                );
                return RefreshJob {
                    request: pending.request,
                    manual: pending.manual,
                    key,
                };
            }
            drop(state);
            notified.await;
        }
    }

    pub async fn finish(&self, job: RefreshJob, event: DataRefreshEvent) -> bool {
        if let Some(running) = self.state.lock().await.running.remove(&job.key) {
            for waiter in running.waiters {
                let _ = waiter.send(event.clone());
            }
            running.manual
        } else {
            job.manual
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(target: RefreshTarget) -> RefreshRequest {
        RefreshRequest {
            season: 2026,
            target,
            session_id: None,
        }
    }

    fn event(target: RefreshTarget) -> DataRefreshEvent {
        DataRefreshEvent {
            target,
            season: 2026,
            session_id: None,
            status: RefreshStatus::Completed,
            updated_at: "2026-10-12T00:00:00Z".into(),
            retry_after: None,
        }
    }

    #[tokio::test]
    async fn test_refresh_queue_prioritizes_manual_and_merges_same_target() {
        let queue = RefreshQueue::default();
        queue
            .enqueue_background(request(RefreshTarget::Standings))
            .await;
        let first = queue
            .enqueue_manual(request(RefreshTarget::Calendar))
            .await
            .unwrap();
        let second = queue
            .enqueue_manual(request(RefreshTarget::Calendar))
            .await
            .unwrap();

        let job = queue.next().await;
        assert!(job.manual);
        assert_eq!(job.request.target, RefreshTarget::Calendar);
        queue.finish(job, event(RefreshTarget::Calendar)).await;
        assert_eq!(first.await.unwrap().status, RefreshStatus::Completed);
        assert_eq!(second.await.unwrap().status, RefreshStatus::Completed);

        let background = queue.next().await;
        assert!(!background.manual);
        assert_eq!(background.request.target, RefreshTarget::Standings);
    }

    #[tokio::test]
    async fn test_refresh_queue_merges_requests_while_job_is_running() {
        let queue = RefreshQueue::default();
        let first = queue
            .enqueue_manual(request(RefreshTarget::Calendar))
            .await
            .unwrap();
        let job = queue.next().await;
        let second = queue
            .enqueue_manual(request(RefreshTarget::Calendar))
            .await
            .unwrap();
        assert!(queue.finish(job, event(RefreshTarget::Calendar)).await);
        assert_eq!(first.await.unwrap(), second.await.unwrap());
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(10), queue.next())
                .await
                .is_err()
        );
    }
}
