use std::{collections::HashMap, convert::Infallible, time::Duration};

use axum::{
    extract::{Query, State},
    response::sse::{Event, KeepAlive, Sse},
};
use futures_util::stream;

use crate::{
    api::refresh::DataRefreshEvent, app_state::AppState, domain::live::LiveSnapshot,
    error::ApiError,
};

pub async fn live_stream(
    State(state): State<AppState>,
    Query(params): Query<HashMap<String, String>>,
) -> Result<Sse<impl futures_util::Stream<Item = Result<Event, Infallible>>>, ApiError> {
    let series = params.get("series").map(String::as_str).unwrap_or("f1");
    let live = state
        .live_for(series)
        .ok_or_else(|| ApiError::InvalidQuery {
            field: "series".to_string(),
            error: "expected f1 or wec".to_string(),
        })?;
    let receiver = live.subscribe();
    let refresh_events = state.refresh_events.subscribe();
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
        (
            receiver,
            refresh_events,
            interval,
            updates,
            current,
            0,
            true,
        ),
        |(
            mut receiver,
            mut refresh_events,
            mut interval,
            mut updates,
            mut current,
            mut sent_version,
            initial,
        )| async move {
            if initial {
                sent_version = current.state_version;
                let event = snapshot_event(&current);
                return Some((
                    Ok(event),
                    (
                        receiver,
                        refresh_events,
                        interval,
                        updates,
                        current,
                        sent_version,
                        false,
                    ),
                ));
            }
            loop {
                tokio::select! {
                    refresh = refresh_events.recv() => match refresh {
                        Ok(event) => {
                            let event = data_refresh_event(&event);
                            return Some((Ok(event), (receiver, refresh_events, interval, updates, current, sent_version, false)));
                        }
                        Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                        Err(tokio::sync::broadcast::error::RecvError::Closed) => {}
                    },
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
                            return Some((Ok(event), (receiver, refresh_events, interval, updates, current, sent_version, false)));
                        }
                    }
                    _ = updates.tick() => {
                        current = receiver.borrow_and_update().clone();
                        if current.state_version != sent_version {
                            sent_version = current.state_version;
                            let event = snapshot_event(&current);
                            return Some((Ok(event), (receiver, refresh_events, interval, updates, current, sent_version, false)));
                        }
                    }
                    _ = interval.tick() => {
                        current = receiver.borrow_and_update().clone();
                        sent_version = current.state_version;
                        let event = snapshot_event(&current);
                        return Some((Ok(event), (receiver, refresh_events, interval, updates, current, sent_version, false)));
                    }
                }
            }
        },
    );

    Ok(Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("keep-alive"),
    ))
}

fn data_refresh_event(event: &DataRefreshEvent) -> Event {
    Event::default()
        .event("dataRefresh")
        .data(serde_json::to_string(event).expect("refresh event serializes"))
}

fn snapshot_event(snapshot: &LiveSnapshot) -> Event {
    Event::default()
        .event("snapshot")
        .data(serde_json::to_string(snapshot).expect("snapshot serializes"))
}
