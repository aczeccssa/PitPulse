/// Oldest season the archive and every seasonal endpoint still carry.
pub const FIRST_SEASON: i64 = 2024;

pub mod analysis;
pub mod live_state;
pub mod next_schedule;
pub mod reconcile;
pub mod results_sync;
pub mod sync;

pub mod circuits;
pub mod season_results;

pub mod backfill;
pub mod engineering;
