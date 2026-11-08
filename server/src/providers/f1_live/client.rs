use serde_json::Value;
use signalr_client::{CallbackHandler, DisconnectionHandler, ReconnectionHandler, SignalRClient};
use tokio::sync::mpsc;

use crate::providers::f1_live::reducer::{LIVE_TOPICS, is_patch_size_allowed};

const CONNECT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(20);
const SUBSCRIBE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(12);
const MESSAGE_CAPACITY: usize = 256;

#[derive(Debug, Clone)]
pub enum F1LiveUpdate {
    InitialSnapshot(Value),
    Feed(Value),
    TransportHeartbeat,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum F1LiveError {
    ConnectTimeout,
    SubscribeTimeout,
    Unauthorized,
    Forbidden,
    HandshakeFailed,
    SnapshotTooLarge,
    Disconnected,
    ChannelClosed,
}

impl F1LiveError {
    pub const fn reason(self) -> &'static str {
        match self {
            Self::ConnectTimeout | Self::SubscribeTimeout => "upstream_timeout",
            Self::Unauthorized => "upstream_unauthorized",
            Self::Forbidden => "upstream_forbidden",
            Self::HandshakeFailed => "upstream_handshake_failed",
            Self::SnapshotTooLarge => "upstream_snapshot_too_large",
            Self::Disconnected => "upstream_disconnected",
            Self::ChannelClosed => "upstream_consumer_closed",
        }
    }
}

struct DisconnectNotifier(mpsc::Sender<()>);

// The library's registration handle does not unregister on drop.
struct FeedRegistration<H: CallbackHandler>(Option<H>);

impl<H: CallbackHandler> Drop for FeedRegistration<H> {
    fn drop(&mut self) {
        if let Some(handler) = self.0.take() {
            handler.unregister();
        }
    }
}

impl DisconnectionHandler for DisconnectNotifier {
    fn on_disconnected(&self, _reconnection: ReconnectionHandler) {
        let _ = self.0.try_send(());
    }
}

#[derive(Debug, Clone)]
pub struct F1LiveClient {
    pub enabled: bool,
    pub base_url: String,
    pub interface: Option<String>,
}

impl F1LiveClient {
    pub const fn new(enabled: bool, base_url: String) -> Self {
        Self {
            enabled,
            base_url,
            interface: None,
        }
    }

    pub fn with_interface(mut self, interface: Option<String>) -> Self {
        self.interface = interface;
        self
    }

    pub async fn run(
        &self,
        access_token: Option<String>,
        updates: mpsc::Sender<F1LiveUpdate>,
        mut stop: tokio::sync::oneshot::Receiver<()>,
    ) -> Result<(), F1LiveError> {
        if !self.enabled {
            return Err(F1LiveError::Disconnected);
        }
        let endpoint =
            reqwest::Url::parse(&self.base_url).map_err(|_| F1LiveError::HandshakeFailed)?;
        let domain = endpoint
            .host_str()
            .filter(|_| endpoint.scheme() == "https")
            .ok_or(F1LiveError::HandshakeFailed)?
            .to_string();
        let hub = endpoint.path().trim_matches('/').to_string();
        if hub.is_empty() {
            return Err(F1LiveError::HandshakeFailed);
        }
        let port = endpoint.port();
        let (disconnected_tx, mut disconnected_rx) = mpsc::channel(1);
        let overflow_signal = disconnected_tx.clone();
        let token = access_token.filter(|token| !token.trim().is_empty());
        let fallback_token = token.clone();
        if let Some(interface) = self.interface.as_deref() {
            // Binding outbound sockets to a physical interface bypasses a transparent
            // proxy/TUN that would otherwise route the live feed through a blocked egress.
            return super::protocol::run_cookie_transport(
                &self.base_url,
                fallback_token.as_deref(),
                Some(interface),
                updates,
                &mut stop,
            )
            .await;
        }
        let connect = tokio::time::timeout(
            CONNECT_TIMEOUT,
            SignalRClient::connect_with(&domain, &hub, move |config| {
                if let Some(port) = port {
                    config.with_port(i32::from(port));
                }
                if let Some(token) = token.clone() {
                    config.authenticate_bearer(token);
                }
                config.with_disconnection_handler(DisconnectNotifier(disconnected_tx.clone()));
            }),
        )
        .await
        .map_err(|_| F1LiveError::ConnectTimeout)?
        .map_err(classify_error);
        let mut client = match connect {
            Ok(client) => client,
            Err(F1LiveError::HandshakeFailed) => {
                return super::protocol::run_cookie_transport(
                    &self.base_url,
                    fallback_token.as_deref(),
                    self.interface.as_deref(),
                    updates,
                    &mut stop,
                )
                .await;
            }
            Err(error) => return Err(error),
        };

        let (feed_tx, mut feed_rx) = mpsc::channel(MESSAGE_CAPACITY);
        let _feed = FeedRegistration(Some(client.register("feed".to_string(), move |context| {
            let Ok(first) = context.argument::<Value>(0) else {
                return;
            };
            let Some(value) = normalize_feed_arguments(
                first,
                context.argument::<Value>(1).ok(),
                context.argument::<Value>(2).ok(),
            ) else {
                return;
            };
            if !is_patch_size_allowed(&value) {
                tracing::warn!("discarding oversized F1 Live feed message");
                let _ = overflow_signal.try_send(());
                return;
            }
            if let Err(mpsc::error::TrySendError::Full(_)) = feed_tx.try_send(value) {
                tracing::warn!("F1 Live feed queue is full; reconnecting for a fresh snapshot");
                let _ = overflow_signal.try_send(());
            }
        })));

        let topics = LIVE_TOPICS;
        let initial = tokio::time::timeout(
            SUBSCRIBE_TIMEOUT,
            client.invoke_with_args::<Value, _>("Subscribe".to_string(), |arguments| {
                arguments.argument(topics);
            }),
        )
        .await
        .map_err(|_| F1LiveError::SubscribeTimeout)?
        .map_err(classify_error)?;
        if !is_patch_size_allowed(&initial) {
            return Err(F1LiveError::SnapshotTooLarge);
        }
        updates
            .send(F1LiveUpdate::InitialSnapshot(initial))
            .await
            .map_err(|_| F1LiveError::ChannelClosed)?;

        loop {
            tokio::select! {
                _ = &mut stop => {
                    drop(_feed);
                    client.disconnect();
                    return Ok(());
                }
                _ = disconnected_rx.recv() => {
                    drop(_feed);
                    client.disconnect();
                    return Err(F1LiveError::Disconnected);
                }
                value = feed_rx.recv() => {
                    let Some(value) = value else {
                        drop(_feed);
                        client.disconnect();
                        return Err(F1LiveError::ChannelClosed);
                    };
                    if updates.send(F1LiveUpdate::Feed(value)).await.is_err() {
                        drop(_feed);
                        client.disconnect();
                        return Err(F1LiveError::ChannelClosed);
                    }
                }
            }
        }
    }
}

pub(super) fn normalize_feed_arguments(
    first: Value,
    patch: Option<Value>,
    timestamp: Option<Value>,
) -> Option<Value> {
    if first.is_string() {
        let patch = patch?;
        return Some(serde_json::json!([
            first,
            patch,
            timestamp.unwrap_or(Value::Null)
        ]));
    }
    (first.is_array() || first.is_object()).then_some(first)
}

fn classify_error(error: String) -> F1LiveError {
    let error = error.to_ascii_lowercase();
    let status = error
        .split("status code ")
        .nth(1)
        .and_then(|value| value.split_whitespace().next())
        .and_then(|value| value.parse::<u16>().ok());
    let kind = if status.is_some() {
        "websocket_upgrade"
    } else if error.contains("certificate") || error.contains("tls") || error.contains("ssl") {
        "tls"
    } else if error.contains("negotiate") || error.contains("negotiation") {
        "negotiate"
    } else if error.contains("reset") || error.contains("closed") || error.contains("eof") {
        "connection_closed"
    } else {
        "protocol"
    };
    tracing::warn!(kind, status, "F1 Live connection step failed");
    if error.contains("401") || error.contains("unauthorized") {
        F1LiveError::Unauthorized
    } else if error.contains("403") || error.contains("forbidden") {
        F1LiveError::Forbidden
    } else {
        F1LiveError::HandshakeFailed
    }
}

pub fn topic_names(value: &Value) -> Vec<String> {
    if let Some(object) = value.as_object() {
        return LIVE_TOPICS
            .iter()
            .filter(|topic| object.contains_key(**topic))
            .map(|topic| (*topic).to_string())
            .collect();
    }
    let mut names = Vec::new();
    let entries = value.as_array().map_or_else(
        || vec![value],
        |items| {
            if items
                .first()
                .and_then(Value::as_str)
                .is_some_and(|name| LIVE_TOPICS.contains(&name))
            {
                vec![value]
            } else {
                items.iter().collect()
            }
        },
    );
    for entry in entries {
        if let Some(topic) = entry
            .as_array()
            .and_then(|items| items.first())
            .and_then(Value::as_str)
            .filter(|topic| LIVE_TOPICS.contains(topic))
            && !names.iter().any(|current| current == topic)
        {
            names.push(topic.to_string());
        }
    }
    names
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::providers::f1_live::reducer::LiveTopicReducer;
    use serde_json::json;

    #[test]
    fn test_feed_registration_unregisters_on_drop() {
        struct Registration(std::sync::Arc<std::sync::atomic::AtomicUsize>);
        impl CallbackHandler for Registration {
            fn unregister(self) {
                self.0.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            }
        }
        let calls = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
        {
            let _guard = FeedRegistration(Some(Registration(calls.clone())));
        }
        assert_eq!(calls.load(std::sync::atomic::Ordering::SeqCst), 1);
    }

    #[test]
    fn test_three_feed_arguments_reach_reducer_and_refresh_timing() {
        let feed = normalize_feed_arguments(
            json!("LapCount"),
            Some(json!({"CurrentLap": 7})),
            Some(json!("now")),
        )
        .unwrap();
        let update = LiveTopicReducer::default()
            .apply_batch(&feed, "2026-10-10T09:00:00Z")
            .unwrap();
        assert_eq!(update.snapshot.lap_count, Some(7));
        assert!(update.data_updated);
        assert!(normalize_feed_arguments(json!("TimingData"), None, None).is_none());
        assert!(normalize_feed_arguments(json!(true), None, None).is_none());
    }
}
