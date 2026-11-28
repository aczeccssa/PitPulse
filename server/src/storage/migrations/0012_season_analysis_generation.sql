BEGIN;
CREATE TABLE IF NOT EXISTS season_analysis_generation (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    generation INTEGER NOT NULL DEFAULT 0
);
INSERT OR IGNORE INTO season_analysis_generation (id) VALUES (1);
CREATE TRIGGER IF NOT EXISTS season_analysis_insert AFTER INSERT ON analysis_cache
WHEN NEW.cache_key GLOB 'session:*:bundle' OR NEW.cache_key GLOB 'session:*:shared:*'
  OR NEW.cache_key GLOB 'season:*:bundle' OR NEW.cache_key GLOB 'pitpulse:fia:*'
  OR NEW.cache_key GLOB 'engineering:*'
BEGIN
    UPDATE season_analysis_generation SET generation = generation + 1 WHERE id = 1;
END;
CREATE TRIGGER IF NOT EXISTS season_analysis_update AFTER UPDATE ON analysis_cache
WHEN NEW.cache_key GLOB 'session:*:bundle' OR NEW.cache_key GLOB 'session:*:shared:*'
  OR NEW.cache_key GLOB 'season:*:bundle' OR NEW.cache_key GLOB 'pitpulse:fia:*'
  OR NEW.cache_key GLOB 'engineering:*'
BEGIN
    UPDATE season_analysis_generation SET generation = generation + 1 WHERE id = 1;
END;
CREATE TRIGGER IF NOT EXISTS season_analysis_delete AFTER DELETE ON analysis_cache
WHEN OLD.cache_key GLOB 'session:*:bundle' OR OLD.cache_key GLOB 'session:*:shared:*'
  OR OLD.cache_key GLOB 'season:*:bundle' OR OLD.cache_key GLOB 'pitpulse:fia:*'
  OR OLD.cache_key GLOB 'engineering:*'
BEGIN
    UPDATE season_analysis_generation SET generation = generation + 1 WHERE id = 1;
END;
PRAGMA user_version = 12;
COMMIT;
