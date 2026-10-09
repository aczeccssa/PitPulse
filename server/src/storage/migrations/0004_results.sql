ALTER TABLE session_results ADD COLUMN best_lap TEXT;
ALTER TABLE session_results ADD COLUMN q1 TEXT;
ALTER TABLE session_results ADD COLUMN q2 TEXT;
ALTER TABLE session_results ADD COLUMN q3 TEXT;
ALTER TABLE session_results ADD COLUMN race_time TEXT;
ALTER TABLE driver_standings ADD COLUMN constructor_ids TEXT NOT NULL DEFAULT '[]';

CREATE TABLE IF NOT EXISTS driver_mappings (
    provider TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    canonical_id TEXT NOT NULL,
    PRIMARY KEY(provider, provider_id)
);

CREATE TABLE IF NOT EXISTS constructor_mappings (
    provider TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    canonical_id TEXT NOT NULL,
    PRIMARY KEY(provider, provider_id)
);
