use std::convert::Infallible;

use axum::{
    extract::State,
    response::sse::{Event, KeepAlive, Sse},
};
use futures_util::{StreamExt, stream::Stream};
use tokio_stream::wrappers::WatchStream;

use crate::app_state::AppState;

pub async fn live_stream(
    State(state): State<AppState>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let receiver = state.live.subscribe();
    let stream = WatchStream::new(receiver).map(|snapshot| {
        Ok(Event::default()
            .event("snapshot")
            .data(serde_json::to_string(&snapshot).expect("snapshot serializes")))
    });

    Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(std::time::Duration::from_secs(15))
            .text("keep-alive"),
    )
}
