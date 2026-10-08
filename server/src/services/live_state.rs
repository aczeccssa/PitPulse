use std::sync::Arc;

use tokio::sync::watch;

use crate::domain::live::{LiveSnapshot, LiveStatus};

#[derive(Clone)]
pub struct LiveState {
    sender: Arc<watch::Sender<LiveSnapshot>>,
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
        }
    }

    pub fn current(&self) -> watch::Ref<'_, LiveSnapshot> {
        self.sender.borrow()
    }

    pub fn subscribe(&self) -> watch::Receiver<LiveSnapshot> {
        self.sender.subscribe()
    }

    pub fn publish(&self, snapshot: LiveSnapshot) {
        self.sender.send_replace(snapshot);
    }

    pub fn mark_status(&self, status: LiveStatus, reason: &str) {
        let mut snapshot = self.sender.borrow().clone();
        snapshot.source_status = status;
        snapshot.status_reason = Some(reason.to_string());
        self.sender.send_replace(snapshot);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_watch_receiver_receives_latest_snapshot() {
        let state = LiveState::new(LiveStatus::Disconnected);
        let mut receiver = state.subscribe();
        let mut snapshot = state.current().clone();
        snapshot.state_version = 1;
        snapshot.session_id = Some("2026-r01-fp1".to_string());
        state.publish(snapshot);

        assert!(receiver.changed().await.is_ok());
        assert_eq!(
            receiver.borrow().session_id.as_deref(),
            Some("2026-r01-fp1")
        );
    }
}
