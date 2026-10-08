CREATE TABLE IF NOT EXISTS meetings (
    id TEXT PRIMARY KEY,
    season INTEGER NOT NULL,
    round INTEGER NOT NULL,
    name TEXT NOT NULL,
    country TEXT NOT NULL,
    location TEXT NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    UNIQUE(season, round)
);

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
    session_type TEXT NOT NULL,
    start_time TEXT NOT NULL,
    end_time TEXT,
    status TEXT NOT NULL,
    source TEXT NOT NULL,
    provider_session_id TEXT,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    UNIQUE(meeting_id, session_type)
);

CREATE TABLE IF NOT EXISTS session_results (
    id INTEGER PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    classification TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    driver_name TEXT NOT NULL,
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

CREATE TABLE IF NOT EXISTS driver_standings (
    id INTEGER PRIMARY KEY,
    season INTEGER NOT NULL,
    position INTEGER NOT NULL,
    driver_id TEXT NOT NULL,
    driver_name TEXT NOT NULL,
    constructor TEXT NOT NULL,
    points REAL NOT NULL,
    wins INTEGER NOT NULL,
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    quality TEXT NOT NULL,
    UNIQUE(season, driver_id)
);

CREATE TABLE IF NOT EXISTS constructor_standings (
    id INTEGER PRIMARY KEY,
    season INTEGER NOT NULL,
    position INTEGER NOT NULL,
    constructor_id TEXT NOT NULL,
    constructor_name TEXT NOT NULL,
    points REAL NOT NULL,
    wins INTEGER NOT NULL,
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1,
    quality TEXT NOT NULL,
    UNIQUE(season, constructor_id)
);

CREATE TABLE IF NOT EXISTS sync_state (
    provider TEXT NOT NULL,
    endpoint TEXT NOT NULL,
    last_success_at TEXT,
    last_attempt_at TEXT NOT NULL,
    next_retry_at TEXT,
    last_error TEXT,
    retry_count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(provider, endpoint)
);

CREATE INDEX IF NOT EXISTS idx_sessions_meeting ON sessions(meeting_id);
CREATE INDEX IF NOT EXISTS idx_results_session ON session_results(session_id);
CREATE INDEX IF NOT EXISTS idx_driver_standings_season ON driver_standings(season);
CREATE INDEX IF NOT EXISTS idx_constructor_standings_season ON constructor_standings(season);
