CREATE TABLE analysis_cache (
    cache_key TEXT PRIMARY KEY,
    value_json TEXT NOT NULL,
    fetched_at TEXT NOT NULL
);
CREATE INDEX analysis_cache_age ON analysis_cache(fetched_at);
