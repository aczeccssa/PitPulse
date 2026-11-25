CREATE TABLE IF NOT EXISTS next_season_schedule (
    season INTEGER PRIMARY KEY,
    events_json TEXT NOT NULL,
    revision INTEGER NOT NULL,
    checked_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
PRAGMA user_version = 11;
