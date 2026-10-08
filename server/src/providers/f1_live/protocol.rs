//! SignalR protocol adapter decision point.
//!
//! Phase 0 must decide whether `signalr-client` supports F1's negotiation and
//! subscription flow or whether a `tokio-tungstenite` protocol layer is needed.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportDecision {
    SignalrClientAvailable,
    WebsocketFallbackRequired,
}
