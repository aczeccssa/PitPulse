//! Transport boundary for the F1 SignalR client.
//!
//! The concrete negotiate/handoff implementation is deliberately deferred until
//! the Phase 0 protocol probe records handshake, subscription, and auth facts.

#[derive(Debug, Clone)]
pub struct F1LiveClient {
    pub enabled: bool,
    pub base_url: String,
}

impl F1LiveClient {
    pub const fn new(enabled: bool, base_url: String) -> Self {
        Self { enabled, base_url }
    }
}
