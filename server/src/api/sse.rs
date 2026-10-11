use std::{convert::Infallible, time::Duration};

use axum::{
    extract::State,
    response::sse::{Event, KeepAlive, Sse},
};
use futures_util::stream;

use crate::{app_state::AppState, domain::live::LiveSnapshot};

pub async fn live_stream(
    State(state): State<AppState>,
) -> Sse<impl futures_util::Stream<Item = Result<Event, Infallible>>> {
    let receiver = state.live.subscribe();
    let current = receiver.borrow().clone();
    let interval = tokio::time::interval(Duration::from_secs(
        state.config.live.snapshot_interval_seconds.clamp(10, 30),
    ));
    let mut updates = tokio::time::interval(Duration::from_millis(100));
    updates.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    updates.tick().await;
    let mut interval = interval;
    interval.tick().await;
    let stream = stream::unfold(
        (receiver, interval, updates, current, 0, true),
        |(mut receiver, mut interval, mut updates, mut current, mut sent_version, initial)| async move {
            if initial {
                sent_version = current.state_version;
                let event = snapshot_event(&current);
                return Some((
                    Ok(event),
                    (receiver, interval, updates, current, sent_version, false),
                ));
            }
            loop {
                tokio::select! {
                    changed = receiver.changed() => {
                        if changed.is_err() {
                            return None;
                        }
                        let next = receiver.borrow_and_update().clone();
                        let status_changed = next.source_status != current.source_status
                            || next.source_mode != current.source_mode
                            || next.status_reason != current.status_reason;
                        current = next;
                        if status_changed {
                            sent_version = current.state_version;
                            let event = snapshot_event(&current);
                            return Some((Ok(event), (receiver, interval, updates, current, sent_version, false)));
                        }
                    }
                    _ = updates.tick() => {
                        current = receiver.borrow_and_update().clone();
                        if current.state_version != sent_version {
                            sent_version = current.state_version;
                            let event = snapshot_event(&current);
                            return Some((Ok(event), (receiver, interval, updates, current, sent_version, false)));
                        }
                    }
                    _ = interval.tick() => {
                        current = receiver.borrow_and_update().clone();
                        sent_version = current.state_version;
                        let event = snapshot_event(&current);
                        return Some((Ok(event), (receiver, interval, updates, current, sent_version, false)));
                    }
                }
            }
        },
    );

    Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("keep-alive"),
    )
}

fn snapshot_event(snapshot: &LiveSnapshot) -> Event {
    Event::default()
        .event("snapshot")
        .data(serde_json::to_string(snapshot).expect("snapshot serializes"))
}
