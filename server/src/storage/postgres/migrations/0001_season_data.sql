-- Applied transactionally by the season-data migration command in a dedicated,
-- non-API-exposed schema. Application roles are granted separately.
CREATE TABLE schema_migrations (
    version BIGINT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Change token for readers. All canonical writes bump it in the same transaction.
CREATE TABLE dataset_generation (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    generation BIGINT NOT NULL DEFAULT 0
);
INSERT INTO dataset_generation DEFAULT VALUES;

CREATE TABLE meetings (
    id TEXT PRIMARY KEY,
    season BIGINT NOT NULL,
    round BIGINT,
    name TEXT NOT NULL,
    country TEXT NOT NULL,
    country_code TEXT,
    location TEXT NOT NULL,
    start_date TEXT NOT NULL,
    end_date TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'scheduled',
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    jolpica_round_id TEXT,
    openf1_meeting_key BIGINT,
    circuit_json TEXT,
    UNIQUE(season, round)
);

CREATE TABLE sessions (
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
    revision BIGINT NOT NULL DEFAULT 1,
    jolpica_session_id TEXT,
    openf1_session_key BIGINT,
    UNIQUE(meeting_id, session_type)
);

CREATE TABLE session_results (
    session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    position BIGINT,
    classification TEXT NOT NULL,
    driver_id TEXT NOT NULL,
    driver_name TEXT NOT NULL,
    constructor_id TEXT NOT NULL DEFAULT '',
    team TEXT NOT NULL,
    time TEXT,
    gap TEXT,
    laps BIGINT,
    points DOUBLE PRECISION,
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    quality TEXT NOT NULL,
    best_lap TEXT,
    q1 TEXT,
    q2 TEXT,
    q3 TEXT,
    race_time TEXT,
    driver_number TEXT,
    PRIMARY KEY (session_id, revision, driver_id)
);

CREATE TABLE driver_standings (
    season BIGINT NOT NULL,
    position BIGINT NOT NULL,
    driver_id TEXT NOT NULL,
    driver_name TEXT NOT NULL,
    constructor TEXT NOT NULL,
    points DOUBLE PRECISION NOT NULL,
    wins BIGINT NOT NULL,
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    quality TEXT NOT NULL,
    constructor_ids TEXT NOT NULL DEFAULT '[]',
    driver_number TEXT,
    PRIMARY KEY (season, driver_id)
);

CREATE TABLE constructor_standings (
    season BIGINT NOT NULL,
    position BIGINT NOT NULL,
    constructor_id TEXT NOT NULL,
    constructor_name TEXT NOT NULL,
    points DOUBLE PRECISION NOT NULL,
    wins BIGINT NOT NULL,
    source TEXT NOT NULL,
    source_updated_at TEXT,
    fetched_at TEXT NOT NULL,
    revision BIGINT NOT NULL DEFAULT 1,
    quality TEXT NOT NULL,
    PRIMARY KEY (season, constructor_id)
);

CREATE TABLE provider_mappings (
    provider TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    meeting_id TEXT,
    session_id TEXT,
    PRIMARY KEY(provider, provider_id)
);

CREATE TABLE driver_mappings (
    provider TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    canonical_id TEXT NOT NULL,
    PRIMARY KEY(provider, provider_id)
);

CREATE TABLE constructor_mappings (
    provider TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    canonical_id TEXT NOT NULL,
    PRIMARY KEY(provider, provider_id)
);

CREATE TABLE provider_identity_cache (
    season BIGINT PRIMARY KEY,
    drivers_json TEXT NOT NULL,
    constructors_json TEXT NOT NULL,
    fetched_at TEXT NOT NULL
);

CREATE TABLE calendar_snapshots (
    season BIGINT PRIMARY KEY,
    content_hash TEXT NOT NULL,
    revision BIGINT NOT NULL
);

CREATE TABLE next_season_schedule (
    season BIGINT PRIMARY KEY,
    events_json TEXT NOT NULL,
    revision BIGINT NOT NULL,
    checked_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE INDEX sessions_meeting_start_idx ON sessions (meeting_id, start_time, id);
CREATE INDEX session_results_latest_idx ON session_results (session_id, revision DESC, position, driver_id);
CREATE INDEX driver_standings_positions_idx ON driver_standings (season, position, driver_id);
CREATE INDEX constructor_standings_positions_idx ON constructor_standings (season, position, constructor_id);

-- Preserve SQLite's NULL behavior for missing or invalid date strings.
CREATE FUNCTION season_timestamp(value TEXT) RETURNS TIMESTAMPTZ
LANGUAGE plpgsql STABLE STRICT SET timezone TO 'UTC' AS $$
BEGIN
    IF value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}($|[T ])' THEN
        RETURN NULL;
    END IF;
    RETURN value::timestamptz;
EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RETURN NULL;
END;
$$;
