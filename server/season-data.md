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

## Automatic reader cache

Central readers keep a shared, process-local cache of canonical query results. Requests populate it automatically. Concurrent callers for an admitted key share its origin load. Least-recently-used idle slots are evicted. If all slots are busy, new distinct keys receive a retryable `503`. No new history rows or cache rows are written to SQLite. The existing Dashboard response and derived archive caches are bypassed in central mode so a second layer cannot conceal an expired or revised canonical value.

| Reader environment variable | Default | Meaning |
| --- | ---: | --- |
| `PITPULSE_SEASON_CACHE_CAPACITY` | 512 | Query entry limit, up to 8192. Zero disables the cache for cold-read comparisons. |
| `PITPULSE_SEASON_CACHE_TTL_SECONDS` | 60 | Fresh age of a key since its last successful read, up to 3600. |
| `PITPULSE_SEASON_CACHE_MAX_STALE_SECONDS` | 21600 | Maximum total age since the last successful read for outage fallback, up to 86400. Zero disables fallback. |
| `PITPULSE_SEASON_CACHE_REVISION_SECONDS` | 5 | Minimum interval between successful shared generation checks on active readers, 1–60 seconds. |

A generation change invalidates the fresh copy on the next check. An unavailable center triggers a coalesced retry after one second. A last successful eligible value is served within the stale window, with existing `meta.stale` and `meta.quality` fields updated where the response has metadata. An uncached key, exhausted stale window or cached negative lookup during an outage returns `503` with `season_data_unavailable` and `Retry-After`. Live recovery, health and SSE use local state.

`GET /api/v1/diagnostics/season-cache` uses the existing API authentication and reports aggregate `hits`, `staleHits`, `originLoads`, `revisionChecks`, `evictions` and `unavailable` counters for the running process. An origin load is one canonical query operation, which can use several SQL statements. Generation probes are tracked separately. A session results request can touch both the session lookup and classification keys. SQLite-only mode returns `data: null`.
