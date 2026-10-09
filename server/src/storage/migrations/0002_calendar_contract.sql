ALTER TABLE meetings ADD COLUMN country_code TEXT;
ALTER TABLE meetings ADD COLUMN status TEXT NOT NULL DEFAULT 'scheduled';
ALTER TABLE meetings ADD COLUMN jolpica_round_id TEXT;
ALTER TABLE meetings ADD COLUMN openf1_meeting_key INTEGER;

ALTER TABLE sessions ADD COLUMN jolpica_session_id TEXT;
ALTER TABLE sessions ADD COLUMN openf1_session_key INTEGER;

CREATE TABLE IF NOT EXISTS provider_mappings (
    provider TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    meeting_id TEXT,
    session_id TEXT,
    PRIMARY KEY(provider, provider_id)
);

CREATE TABLE IF NOT EXISTS session_results_v2 (
    id INTEGER PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    position INTEGER,
    classification TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    driver_name TEXT NOT NULL,
    constructor_id TEXT NOT NULL DEFAULT '',
    team TEXT NOT NULL,
    time TEXT,
    gap TEXT,
    laps INTEGER,
    points REAL,
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    quality TEXT NOT NULL,
    UNIQUE(session_id, revision, driver_id)
);

INSERT INTO session_results_v2 (
    id, session_id, position, classification, driver_id, driver_name, constructor_id, team,
    time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality
)
SELECT
    id, session_id, position, classification, driver_id, driver_name, '', team,
    time, gap, laps, points, source, source_updated_at, fetched_at, revision, quality
FROM session_results;

DROP TABLE session_results;
ALTER TABLE session_results_v2 RENAME TO session_results;
CREATE INDEX IF NOT EXISTS idx_results_session ON session_results(session_id);
