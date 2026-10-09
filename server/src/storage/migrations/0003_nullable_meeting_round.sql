PRAGMA foreign_keys = OFF;
BEGIN IMMEDIATE;

CREATE TABLE meetings_v3 (
    id TEXT PRIMARY KEY,
    season INTEGER NOT NULL,
    round INTEGER,
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
    revision INTEGER NOT NULL DEFAULT 1,
    jolpica_round_id TEXT,
    openf1_meeting_key INTEGER,
    UNIQUE(season, round)
);

INSERT INTO meetings_v3 (
    id, season, round, name, country, country_code, location, start_date, end_date,
    status, source, source_updated_at, fetched_at, revision, jolpica_round_id,
    openf1_meeting_key
)
SELECT
    id, season, round, name, country, country_code, location, start_date, end_date,
    status, source, source_updated_at, fetched_at, revision, jolpica_round_id,
    openf1_meeting_key
FROM meetings;

DROP TABLE meetings;
ALTER TABLE meetings_v3 RENAME TO meetings;

COMMIT;
PRAGMA foreign_keys = ON;
