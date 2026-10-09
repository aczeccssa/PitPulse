ALTER TABLE sync_state ADD COLUMN schedule_note TEXT;

CREATE TABLE provider_identity_cache (
    season INTEGER PRIMARY KEY,
    drivers_json TEXT NOT NULL,
    constructors_json TEXT NOT NULL,
    fetched_at TEXT NOT NULL
);

CREATE TABLE calendar_snapshots (
    season INTEGER PRIMARY KEY,
    content_hash TEXT NOT NULL,
    revision INTEGER NOT NULL
);
