/// Reconciliation compares source revisions before replacing persisted results.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReconcileDecision {
    KeepExisting,
    ReplaceWithHigherRevision,
    ConflictRequiresReview,
}
