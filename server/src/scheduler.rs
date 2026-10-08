use std::time::Duration;

use crate::app_state::AppState;

pub fn spawn(state: AppState) {
    let live_state = state.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(
            live_state.config.live.snapshot_interval_seconds.max(1),
        ));
        loop {
            interval.tick().await;
            live_state.live.mark_status(
                crate::domain::live::LiveStatus::Disconnected,
                "upstream_not_implemented",
            );
        }
    });
}
