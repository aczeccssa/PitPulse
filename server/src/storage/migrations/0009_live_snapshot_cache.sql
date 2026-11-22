BEGIN IMMEDIATE;
CREATE TABLE IF NOT EXISTS live_snapshot_cache (
    series TEXT PRIMARY KEY,
    snapshot_json TEXT NOT NULL
);
PRAGMA user_version = 9;
COMMIT;
