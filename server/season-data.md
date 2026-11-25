# Season storage ownership (PP-57)

| Tables or data | Owner | Existing call chain |
| --- | --- | --- |
| `meetings`, `sessions`, `calendar_snapshots` | Postgres | Calendar, next meeting, home, season overview, maps/weather/geometry, analysis and result lookup → `Database` → SQLite. Jolpica and OpenF1 calendar sync write through `replace_calendar`. |
| `session_results` | Postgres | Session results, season overview and analysis → `session_results`. `ResultsSync` writes through `replace_session_results`. Preserve all classification revisions and session-specific identities. |
| `driver_standings`, `constructor_standings` | Postgres | Standings, overview/analysis → corresponding `Database` methods. `ResultsSync` updates each ordered season snapshot. Preserve driver numbers and multiple constructor IDs. |
| `provider_mappings`, `driver_mappings`, `constructor_mappings`, `provider_identity_cache` | Postgres | Calendar upserts provider keys. `ResultsSync` writes canonical mappings and loads season identity snapshots. Preserve raw provider keys and identity data. |
| `next_season_schedule` | Postgres | Calendar fallback, season selector and map venue resolution → `next_schedule` → Formula 1 official calendar snapshots. |
| `sync_state`, `live_snapshot_cache` | SQLite | Scheduler/backfill retry and job state. Live supervisor recovery, F1/WEC clocks and SSE broadcasts stay local. |
| `analysis_cache` | SQLite | Compressed OpenF1 analytics and telemetry cache with age-based pruning; no session result authority. Derived archive and Dashboard caches remain derived. |
| Media, FIA engineering data, circuit geometry | Repository assets and configured local media store | Embedded assets/manifests and engineering fixtures. Existing API contract and refresh paths stay in place. |
| Radio, weather/radar and other external live resources | Upstream and existing local cache | Map and live routes keep their existing providers; archived calendar lookup still uses canonical meeting data. |

Postgres uses natural keys from the SQLite uniqueness constraints. SQLite surrogate `id` values on results and standings are internal row IDs. Date strings and JSON text are preserved from the source database. Unsupported archived years are excluded by the product season floor, with explicit counts in the import report. An existing SQLite file remains a rollback artifact until the operator verifies a separate SQLite cutover. The application must never use its old history as a silent fallback in Postgres mode.

## Isolated publisher

Run `pitpulse-server publish-sync` as a separate process with `PITPULSE_SEASON_WRITE_DATABASE_URL`, the shared `PITPULSE_SEASON_SCHEMA`, and a dedicated `PITPULSE_PUBLISH_STATE_PATH`. Provision the write credential to the publisher and migration operator only. HTTP instances use `PITPULSE_SEASON_READ_DATABASE_URL` and never consult the write variable. The publisher reuses the periodic Jolpica/OpenF1 sync and official schedule refresh, without opening an HTTP listener. SQLite holds the restartable retry state. Empty or unavailable upstream responses leave stored classifications and standings intact. Revision and reader generation changes commit with canonical payloads. The previous SQLite-backed server mode remains available by starting HTTP without `PITPULSE_SEASON_READ_DATABASE_URL` against the pre-cutover SQLite snapshot.

The current publisher starts from the existing polling scheduler. The PP-51 archive-sealed replay event and exact actual-end-plus-24h reconciliation still depend on the PP-51 producer. This polling path uses the stored session end or the legacy estimate and retry schedule.
