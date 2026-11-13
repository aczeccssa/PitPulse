BEGIN;
ALTER TABLE driver_standings ADD COLUMN driver_number TEXT;
ALTER TABLE session_results ADD COLUMN driver_number TEXT;
PRAGMA user_version = 8;
COMMIT;
