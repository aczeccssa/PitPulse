/// Scheduled synchronization boundary; provider fetches are intentionally absent
/// until Phase 0 fixtures define normalization contracts.
#[derive(Debug, Clone, Copy)]
pub enum SyncTarget {
    Calendar,
    Results,
    Standings,
}
