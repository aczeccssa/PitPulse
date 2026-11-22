//! Supplemental public timing transport. Only car data and position patches
//! from the matching official session can reach the main reducer.

use std::time::Duration;

use serde_json::Value;
use tokio::sync::{mpsc, oneshot, watch};
use tokio_websockets::{ClientBuilder, Limits};

use crate::domain::live::{LiveSnapshot, LiveSourceMode, LiveStatus};

use super::{
    client::{F1LiveError, F1LiveUpdate},
    protocol::run_hub,
};

const ENDPOINT: &str = "wss://livetiming.formula1dashboard.com/";
const TOPICS: &[&str] = &["SessionInfo", "CarData.z", "Position.z"];
const CHANNELS: &[&str] = &["CarData.z", "Position.z"];

pub struct TelemetryUpdate {
    pub session_id: String,
    pub data: Value,
}

pub fn matching_session(snapshot: &LiveSnapshot) -> Option<&str> {
    if snapshot.source_mode != LiveSourceMode::Live
        || snapshot.source_status != LiveStatus::Connected
    {
        return None;
    }
    snapshot.session_id.as_deref()
}

pub(super) fn is_active_status(status: &str) -> bool {
    ["Started", "Running", "Green", "InProgress", "Suspended"]
        .iter()
        .any(|active| status.eq_ignore_ascii_case(active))
}

pub async fn supervise(
    mut official: watch::Receiver<LiveSnapshot>,
    out: mpsc::Sender<TelemetryUpdate>,
) {
    loop {
        let next_session = {
            let Ok(snapshot) = official
                .wait_for(|snapshot| matching_session(snapshot).is_some())
                .await
            else {
                return;
            };
            matching_session(&snapshot).map(str::to_owned)
        };
        let Some(session_id) = next_session else {
            continue;
        };
        let result = tokio::select! {
            result = session(&session_id, &out) => result,
            _ = official.wait_for(|snapshot| matching_session(snapshot) != Some(session_id.as_str())) => continue,
            _ = out.closed() => return,
        };
        if let Err(error) = result {
            tracing::debug!(reason = error.reason(), "F1 telemetry relay unavailable");
        }
        tokio::time::sleep(Duration::from_secs(30)).await;
    }
}

async fn session(expected: &str, out: &mpsc::Sender<TelemetryUpdate>) -> Result<(), F1LiveError> {
    let (socket, _) = tokio::time::timeout(
        Duration::from_secs(10),
        ClientBuilder::from_uri(ENDPOINT.parse().map_err(|_| F1LiveError::HandshakeFailed)?)
            .limits(Limits::default().max_payload_len(Some(2 * 1024 * 1024)))
            .connect(),
    )
    .await
    .map_err(|_| F1LiveError::ConnectTimeout)?
    .map_err(|_| F1LiveError::HandshakeFailed)?;

    let (raw_tx, mut raw) = mpsc::channel(32);
    let (_stop, mut stopped) = oneshot::channel();
    let hub = run_hub(socket, TOPICS, raw_tx, &mut stopped);
    tokio::pin!(hub);
    let mut matched = false;
    let idle_deadline = tokio::time::sleep(Duration::from_secs(45));
    tokio::pin!(idle_deadline);
    loop {
        tokio::select! {
            result = &mut hub => return result,
            _ = &mut idle_deadline => return Err(F1LiveError::Disconnected),
            update = raw.recv() => {
                let update = update.ok_or(F1LiveError::ChannelClosed)?;
                let patches = match update {
                    F1LiveUpdate::InitialSnapshot(data) => {
                        if key(data.get("SessionInfo")) != Some(expected.to_owned()) {
                            return Err(F1LiveError::Disconnected);
                        }
                        matched = true;
                        tracing::info!("F1 telemetry relay matched the official session");
                        Value::Object(CHANNELS.iter().filter_map(|topic| {
                            data.get(*topic).map(|patch| ((*topic).to_string(), patch.clone()))
                        }).collect())
                    }
                    F1LiveUpdate::Feed(data) if matched => {
                        match data.get(0).and_then(Value::as_str) {
                            Some("SessionInfo") => {
                                if key(data.get(1)).is_some_and(|id| id != expected) { return Ok(()); }
                                continue;
                            }
                            Some(topic) if CHANNELS.contains(&topic) => data,
                            _ => continue,
                        }
                    }
                    _ => continue,
                };
                idle_deadline.as_mut().reset(tokio::time::Instant::now() + Duration::from_secs(45));
                out.send(TelemetryUpdate { session_id: expected.to_owned(), data: patches })
                    .await.map_err(|_| F1LiveError::ChannelClosed)?;
            }
        }
    }
}

fn key(value: Option<&Value>) -> Option<String> {
    let value = value?;
    let value = value
        .get("Key")
        .or_else(|| value.get("SessionKey"))
        .or_else(|| value.get("SessionId"))?;
    value
        .as_str()
        .map(str::to_owned)
        .or_else(|| value.as_i64().map(|id| id.to_string()))
}
