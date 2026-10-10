use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use tokio::sync::watch;

use crate::domain::live::{LiveSnapshot, LiveSourceMode, LiveStatus};

#[derive(Clone)]
pub struct LiveState {
    sender: Arc<watch::Sender<LiveSnapshot>>,
    version: Arc<AtomicU64>,
    last_transport: Arc<Mutex<Option<Instant>>>,
    last_data: Arc<Mutex<Option<Instant>>>,
}

impl LiveState {
    pub fn new(initial_status: LiveStatus) -> Self {
        let snapshot = LiveSnapshot {
            source_status: initial_status,
            status_reason: Some("not_connected".to_string()),
            ..LiveSnapshot::default()
        };
        let (sender, _) = watch::channel(snapshot);
        Self {
            sender: Arc::new(sender),
            version: Arc::new(AtomicU64::new(0)),
            last_transport: Arc::new(Mutex::new(None)),
            last_data: Arc::new(Mutex::new(None)),
        }
    }

    pub fn current(&self) -> watch::Ref<'_, LiveSnapshot> {
        self.sender.borrow()
    }

    pub fn subscribe(&self) -> watch::Receiver<LiveSnapshot> {
        self.sender.subscribe()
    }

    pub fn subscriber_count(&self) -> usize {
        self.sender.receiver_count()
    }

    pub fn publish(&self, mut snapshot: LiveSnapshot, data_updated: bool) {
        let now = Instant::now();
        *self
            .last_transport
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = Some(now);
        if data_updated {
            *self
                .last_data
                .lock()
                .unwrap_or_else(|error| error.into_inner()) = Some(now);
        }
        snapshot.state_version = self.next_version();
        self.sender.send_replace(snapshot);
    }

    pub fn mark_status(&self, status: LiveStatus, reason: &str) {
        let mut snapshot = self.sender.borrow().clone();
        if snapshot.source_status == status && snapshot.status_reason.as_deref() == Some(reason) {
            return;
        }
        snapshot.source_status = status;
        snapshot.status_reason = Some(reason.to_string());
        snapshot.state_version = self.next_version();
        self.sender.send_replace(snapshot);
    }

    pub fn reset(&self, status: LiveStatus, mode: LiveSourceMode, reason: &str) {
        *self
            .last_transport
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = None;
        *self
            .last_data
            .lock()
            .unwrap_or_else(|error| error.into_inner()) = None;
        let snapshot = LiveSnapshot {
            source_status: status,
            source_mode: mode,
            status_reason: Some(reason.to_string()),
            state_version: self.next_version(),
            ..LiveSnapshot::default()
        };
        self.sender.send_replace(snapshot);
    }

    pub fn check_freshness(&self, stale_after: Duration, disconnect_after: Duration) -> bool {
        let now = Instant::now();
        let last_transport = *self
            .last_transport
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let transport_age = last_transport.map(|at| now.saturating_duration_since(at));
        if transport_age.is_some_and(|age| age >= disconnect_after) {
            self.mark_status(LiveStatus::Disconnected, "upstream_silent");
            return true;
        }
        let last_data = *self
            .last_data
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        let freshness_age = last_data
            .or(last_transport)
            .map(|at| now.saturating_duration_since(at));
        if freshness_age.is_some_and(|age| age >= stale_after) {
            self.mark_status(LiveStatus::Stale, "data_stale");
        }
        false
    }

    fn next_version(&self) -> u64 {
        self.version
            .fetch_add(1, Ordering::Relaxed)
            .saturating_add(1)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_slow_watch_consumer_gets_latest_snapshot_without_backlog() {
        let state = LiveState::new(LiveStatus::Disconnected);
        let mut receiver = state.subscribe();
        let mut snapshot = state.current().clone();
        for session_id in ["older-session", "middle-session", "latest-session"] {
            snapshot.session_id = Some(session_id.to_string());
            state.publish(snapshot.clone(), true);
        }

        assert!(receiver.changed().await.is_ok());
        assert_eq!(
            receiver.borrow_and_update().session_id.as_deref(),
            Some("latest-session")
        );
        assert_eq!(receiver.borrow().state_version, 3);
    }

    #[test]
    fn test_subscriber_count_tracks_live_stream_receivers() {
        let state = LiveState::new(LiveStatus::Disconnected);
        assert_eq!(state.subscriber_count(), 0);
        let _receiver = state.subscribe();
        assert_eq!(state.subscriber_count(), 1);
    }

    #[test]
    fn test_status_updates_increment_version_without_refreshing_data() {
        let state = LiveState::new(LiveStatus::Disconnected);
        let mut snapshot = state.current().clone();
        snapshot.updated_at = Some("2026-10-10T01:00:00Z".to_string());
        state.publish(snapshot, true);
        state.mark_status(LiveStatus::Stale, "data_stale");
        let snapshot = state.current();
        assert_eq!(snapshot.state_version, 2);
        assert_eq!(snapshot.updated_at.as_deref(), Some("2026-10-10T01:00:00Z"));
        assert_eq!(snapshot.status_reason.as_deref(), Some("data_stale"));
    }

    #[test]
    fn test_reset_clears_session_and_freshness() {
        let state = LiveState::new(LiveStatus::Disconnected);
        let mut snapshot = state.current().clone();
        snapshot.session_id = Some("old-session".to_string());
        snapshot.updated_at = Some("2026-10-10T01:00:00Z".to_string());
        state.publish(snapshot, true);
        state.reset(
            LiveStatus::Disconnected,
            LiveSourceMode::Live,
            "reconnecting",
        );
        assert!(state.current().session_id.is_none());
        assert!(state.current().updated_at.is_none());
    }

    #[test]
    fn test_transport_heartbeat_prevents_disconnect_without_refreshing_stale_timing() {
        let state = LiveState::new(LiveStatus::Connected);
        let mut snapshot = state.current().clone();
        snapshot.updated_at = Some("2026-10-10T13:00:00Z".into());
        state.publish(snapshot, true);
        *state.last_data.lock().unwrap() = Some(Instant::now() - Duration::from_secs(60));
        *state.last_transport.lock().unwrap() = Some(Instant::now() - Duration::from_secs(180));
        let mut heartbeat = state.current().clone();
        heartbeat.last_transport_at = Some("2026-10-10T13:01:00Z".into());
        state.publish(heartbeat, false);
        assert!(!state.check_freshness(Duration::from_secs(30), Duration::from_secs(120)));
        assert_eq!(state.current().source_status, LiveStatus::Stale);
        assert_eq!(
            state.current().updated_at.as_deref(),
            Some("2026-10-10T13:00:00Z")
        );
        assert_eq!(
            state.current().last_transport_at.as_deref(),
            Some("2026-10-10T13:01:00Z")
        );
    }

    #[test]
    fn test_live_stream_becomes_stale_then_disconnected() {
        let state = LiveState::new(LiveStatus::Disconnected);
        state.publish(LiveSnapshot::default(), true);
        assert!(!state.check_freshness(Duration::ZERO, Duration::from_secs(1)));
        assert_eq!(state.current().source_status, LiveStatus::Stale);
        assert!(state.check_freshness(Duration::ZERO, Duration::ZERO));
        assert_eq!(state.current().source_status, LiveStatus::Disconnected);
    }
}
