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

## Migrate, switch, and roll back

For the CI release bundle, systemd service setup, and VPS acceptance gates, use the [VPS deployment runbook](deploy/season-data-vps.md).

Rehearse on an isolated copy first. Keep the previous binary, configuration and database backup together. Use private service environment files with shell tracing disabled. Keep the writer URL out of HTTP process environments and use TLS hostname verification for non-loopback connections.

1. Stop legacy season writers and keep `publish-sync` stopped. Make a consistent backup of the current SQLite database with SQLite's backup API or CLI `.backup`. A raw copy of an active WAL database is insufficient. Save the source file, manifest of supported seasons and representative API responses. The import expects SQLite schema v11. Upgrade a copy with the legacy schema v11 binary before import if necessary.
2. Use a dedicated `pitpulse_…` Postgres schema owned by the migration role. Ask the database administrator to preprovision the schema if the role cannot create schemas. The reader must be a separate login without DDL, mutation privileges or writer-role membership. With the schema, writer DSN and reader role set in the operator's private environment, run:

   ```sh
   pitpulse-server season-data migrate
   pitpulse-server season-data import "$LEGACY_SQLITE_SNAPSHOT" > import-report.json
   pitpulse-server season-data verify "$LEGACY_SQLITE_SNAPSHOT" > verify-report.json
   ```

   Check every table's `source == verified`, intended `excluded` counts and Postgres counts against the manifest. On a fresh target `inserted == source` for the first import. Re-importing the same snapshot must insert zero rows. Each import is atomic across the canonical tables. If a run is interrupted, repeat `migrate`, `import`, and `verify` from the same immutable snapshot before starting any publisher. A conflict fails the whole import. Inspect the affected keys or retry in a separate staging schema rather than changing authoritative rows to force a match. Once a publisher has advanced the data, the historical snapshot is no longer a suitable verify-only reference for revised keys.
3. Start a canary reader with `PITPULSE_SEASON_READ_DATABASE_URL`, `PITPULSE_SEASON_SCHEMA` and `F1_COMPANION_DATABASE_PATH` pointing at a separate, new SQLite path. The binary initializes the v11 schema. To carry local state forward, stop the canary and copy `sync_state` and `live_snapshot_cache` from a consistent v11 backup to the new file in one transaction. Keep `analysis_cache` only when needed and apply its normal retention. Keep the existing TOML, token, and local media paths. Give the publisher a different SQLite path. If moving publisher retry state, seed its `sync_state` from the same snapshot before starting it.
4. Compare status/body on captured season endpoints and verify `/api/v1/health`, `/api/v1/live/snapshot` and the SSE first event. Check that canonical SQLite tables are empty and `/api/v1/diagnostics/season-cache` reports origin loads on first read and hits on repeat. The central reader disables legacy season writes and backfill. Configure `PITPULSE_PUBLISH_SOCKET` on the reader and the local `publish-sync` process as described below. Before switching traffic, confirm a legal `POST /api/v1/refresh` follows the publisher queue, `meta.syncStatus` reflects publisher state, and the intended revision appears on the reader. Verify the HTTP and publisher SQLite files still hold no canonical rows. Keep the old SQLite backup for rollback.

**Rollback.** Stop the publisher before promoting the SQLite path, and record the final Postgres generation and recent publication revisions. Stop the central reader and start the prior release with its previous configuration and a working copy of the preserved v11 SQLite snapshot. Remove `PITPULSE_SEASON_READ_DATABASE_URL` from that service environment and restore `F1_COMPANION_DATABASE_PATH` to the rollback copy. If the central reader ran long enough to hold newer live recovery data, snapshot its SQLite and copy `live_snapshot_cache` into the rollback copy before it starts. Check health, representative season endpoints, and Live/SSE before switching traffic. The restored history is current through the SQLite snapshot. Post-cutover Postgres revisions remain in Postgres and require reconciliation before any later cutover. Keep both stores and the import reports intact during rollback.

The Local VM rollback drill used the same 2024–2026 fixture as the load comparison. It switched the actual release processes from the baseline binary to the Postgres reader and back to the baseline binary on a copy of the SQLite backup. The first import verified and inserted 15,318 rows. Re-import and verify each matched all 15,318 rows and inserted none. Calendar, driver standings, and session results returned identical status and bodies across all three phases. Health, Live snapshot, and the first SSE event passed at each phase. The central SQLite retained zero canonical rows. The drill did not run any production services.

## Isolated publisher

Run `pitpulse-server publish-sync` as a separate process with `PITPULSE_SEASON_WRITE_DATABASE_URL`, the shared `PITPULSE_SEASON_SCHEMA`, and a dedicated `PITPULSE_PUBLISH_STATE_PATH`. Provision the write credential to the publisher and migration operator only. HTTP instances use `PITPULSE_SEASON_READ_DATABASE_URL` and never consult the write variable. The publisher reuses the periodic Jolpica/OpenF1 sync and official schedule refresh. SQLite holds the restartable retry state.

To enable manual refresh and publisher metadata, set `PITPULSE_PUBLISH_SOCKET` to the same absolute path on the publisher and public HTTP process. Run both processes on the same Unix host. Put the socket in a publisher-owned `0700` directory for a common service account, or in a publisher-owned `2750` directory with a dedicated group when the reader has a separate service account. In the latter case add the reader to that group. The socket is mode `0660` and the publisher opens no TCP listener. Treat socket access as permission to queue refresh jobs. Keep the publisher's SQLite file private. If a crash leaves a socket file, confirm the publisher stopped before removing the file and restarting.

The public refresh API keeps its validation, queue limits, and `DataRefreshEvent` response. The publisher provides `meta.syncStatus` where the legacy API reads sync status, and its `dataRefresh` events are forwarded on the existing Live SSE stream. If the publisher socket is missing or unavailable, valid refresh requests return `503 refresh_unavailable`, and season reads omit publisher sync metadata while continuing to use the usual season cache. This is a service configuration change and requires no client migration. Empty or unavailable upstream responses leave stored classifications and standings intact. Revision and reader generation changes commit with canonical payloads. The previous SQLite-backed server mode remains available by starting HTTP without `PITPULSE_SEASON_READ_DATABASE_URL` against the pre-cutover SQLite snapshot.

The current publisher starts from the existing polling scheduler. The PP-51 archive-sealed replay event and exact actual-end-plus-24h reconciliation still depend on the PP-51 producer. This polling path uses the stored session end or the legacy estimate and retry schedule.

## Automatic reader cache

Central readers keep a shared, process-local cache of canonical query results. Requests populate it automatically. Concurrent callers for an admitted key share its origin load. Least-recently-used idle slots are evicted. If all slots are busy, new distinct keys receive a retryable `503`. No new history rows or cache rows are written to SQLite. The existing Dashboard response and derived archive caches are bypassed in central mode so a second layer cannot conceal an expired or revised canonical value.

| Reader environment variable | Default | Meaning |
| --- | ---: | --- |
| `PITPULSE_SEASON_CACHE_CAPACITY` | 512 | Query entry limit, up to 8192. Zero disables the cache for cold-read comparisons. |
| `PITPULSE_SEASON_CACHE_TTL_SECONDS` | 60 | Fresh age of a key since its last successful read, up to 3600. |
| `PITPULSE_SEASON_CACHE_MAX_STALE_SECONDS` | 21600 | Maximum total age since the last successful read for outage fallback, up to 86400. Zero disables fallback. |
| `PITPULSE_SEASON_CACHE_REVISION_SECONDS` | 5 | Minimum interval between successful shared generation checks on active readers, 1–60 seconds. |
| `PITPULSE_SEASON_QUERY_DEADLINE_SECONDS` | 4 | End-to-end deadline for each reader query operation or generation probe, 1–30 seconds. |

A generation change invalidates the fresh copy on the next check. A temporarily unavailable center, including a PostgreSQL lock timeout (`55P03`), triggers a coalesced retry after one second. A last successful eligible value is served within the stale window, with existing `meta.stale` and `meta.quality` fields updated where the response has metadata. An uncached key, exhausted stale window or cached negative lookup during an outage returns `503` with `season_data_unavailable` and `Retry-After`. Live recovery, health and SSE use local state.

`GET /api/v1/diagnostics/season-cache` uses the existing API authentication and reports aggregate `hits`, `staleHits`, `originLoads`, `revisionChecks`, `evictions` and `unavailable` counters for the running process. An origin load is one canonical query operation, which can use several SQL statements. Generation probes are tracked separately. A session results request can touch both the session lookup and classification keys. SQLite-only mode returns `data: null`.

## Reproduce the local load comparison

Build the original SQLite baseline and the candidate with the same toolchain and release profile. Use a fresh local Postgres database or a dedicated disposable database. `PITPULSE_BENCH_LOCAL_URL` names its loopback connection. Optionally set `PITPULSE_BENCH_LOCAL_READ_URL` and `PITPULSE_BENCH_LOCAL_READER_ROLE` to a separate login already created on that database. The script creates a uniquely named fixture schema and leaves it for inspection. SQLite files are temporary and the JSON report includes the name of the fixture schema.

```sh
base=39f7c759
bench=$(mktemp -d)
git worktree add --detach "$bench/baseline" "$base"
export CARGO_TARGET_DIR="$bench/target"
cargo +1.94.1 build --manifest-path "$bench/baseline/server/Cargo.toml" --locked --release --bin pitpulse-server
cp "$CARGO_TARGET_DIR/release/pitpulse-server" "$bench/sqlite-server"
cargo +1.94.1 build --manifest-path server/Cargo.toml --locked --release --bin pitpulse-server
python3 scripts/bench-season-storage.py \
  --legacy "$bench/sqlite-server" --central "$CARGO_TARGET_DIR/release/pitpulse-server" \
  --out "$bench/results" --requests 2400 --repeats 3
```

The script sends a four-way mix of calendar, driver standings, constructor standings and session results over loopback HTTP/1.1 keep-alive at concurrency 1, 16 and 64. It checks all 81 distinct URLs against the baseline response. Cold means application caching is disabled and Postgres may already have data and connections in memory. Warm uses the default cache and primes the same URLs before measuring. The separate 64-request burst targets one previously unrequested calendar key. Both modes use the same generated 2024–2026 fixture, disable the live and racing providers in config, and point environment-aware outbound HTTP through an unavailable loopback proxy. They run sequentially with eight Tokio worker threads. Cache counters are per canonical query, so one HTTP request can account for several hits or origin loads. Percentiles in `results.json` use nearest rank and exclude fixture setup, connection setup, priming and correctness checks.

### Local VM measurements (2026-11-25 UTC)

Rust 1.94.1 release builds (`39f7c759` and `31f8999`), PostgreSQL 15.20 on loopback, AMD Ryzen 7 H 255, 16 logical CPUs. The fixture contains 72 meetings, 360 sessions and 14,400 classification rows (two revisions for each 20-driver field), plus standings and identity/mapping data. The import verified all 15,318 canonical rows. No remote load was generated.

Each row is the median of three 2,400-request runs for each displayed metric. All 64,800 requests returned HTTP 200. The [raw measurement JSON](evidence/pp-57-local-benchmark.json) contains each run, including status counts and error rates.

| Concurrency | Mode | p50 ms | p95 ms | p99 ms | Requests/s | Query hits / origin loads per run |
|---:|---|---:|---:|---:|---:|---:|
| 1 | SQLite baseline | 0.841 | 1.135 | 1.325 | 1,191 | — |
| 1 | Postgres cold | 1.308 | 2.775 | 3.160 | 692 | 0 / 3,000 |
| 1 | Postgres warm | 0.490 | 0.688 | 0.820 | 2,022 | 3,000 / 0 |
| 16 | SQLite baseline | 4.810 | 6.493 | 7.032 | 3,149 | — |
| 16 | Postgres cold | 1.876 | 4.059 | 5.073 | 4,606 | 0 / 3,000 |
| 16 | Postgres warm | 1.240 | 1.705 | 1.979 | 12,070 | 3,000 / 0 |
| 64 | SQLite baseline | 20.500 | 28.716 | 30.996 | 2,924 | — |
| 64 | Postgres cold | 8.992 | 17.586 | 18.698 | 5,459 | 0 / 3,000 |
| 64 | Postgres warm | 4.952 | 6.595 | 8.050 | 12,118 | 3,000 / 0 |

The one-key cold burst returned 64/64 HTTP 200 with 63 hits and one origin load. Its p50/p95/p99 were 7.941/31.540/31.687 ms at 1,963 requests/s. Warm p95 was 61%, 26%, and 23% of the SQLite baseline at concurrency 1, 16, and 64. Single-client cold p95 was 2.44× the SQLite baseline. These loopback results measure application and database work on one VM. Hosted latency depends on the instance-to-Supabase network path.

After checkpoint and vacuum, the seeded SQLite was 2,772,992 bytes and the clean cutover SQLite was 143,360 bytes (−94.8%). After HTTP runs and checkpoint, those files were 2,785,280 and 155,648 bytes respectively. Each central-mode copy retained zero rows across the 11 canonical tables. This comparison uses a clean SQLite database with seeded local sync state. Existing full SQLite files retain their original size and contents until a separate cutover.

## Supabase development smoke test (2026-11-25 UTC)

From the Local VM, both development roles established TLS 1.3 to the Supabase session pooler with `sslmode=verify-full` and the provisioned CA. `psql -XAt -c '\conninfo'` confirmed TLS on the client-to-pooler connection for each role. Supply the connection settings via the environment and redact the `\conninfo` destination before sharing the output.

The migration role owns the preprovisioned `pitpulse_dev` schema and does not need database-level `CREATE`. Inspect the schema before running this test. Use only a dedicated, empty fixture schema or the exact fixture from an interrupted import at revision 2. The test publishes a new revision and leaves the fixture in place.

```sh
# Source the private development env file outside the repository with shell tracing off.
export PITPULSE_TEST_DATABASE_URL="$PITPULSE_DEV_DATABASE_URL"
export PITPULSE_TEST_READ_DATABASE_URL="$PITPULSE_DEV_READ_DATABASE_URL"
export PITPULSE_TEST_PREPROVISIONED_SCHEMA=pitpulse_dev
# Set PITPULSE_TEST_READER_ROLE privately to the read login's SELECT current_user result.
export PITPULSE_SEASON_QUERY_DEADLINE_SECONDS=20
# For an interrupted run, first check that only the expected fixture is present at revision 2.
# Then set PITPULSE_TEST_RESUME_IMPORT=1 to require zero inserted rows on the first import.
cargo +1.94.1 test --manifest-path server/Cargo.toml --locked --test season_postgres \
  imported_history_matches_http_contract_with_clean_sqlite -- --ignored --exact
```

The first run installed v1 and imported eight fixture rows, then exceeded the default reader deadline. The resumed run reapplied the migration twice and checked all eight source rows. Re-import inserted zero rows and verify-only checked the same values. Through Axum's router with a clean SQLite, six status/body comparisons matched the baseline. The reader saw result revision 2 then 3 (26 points). Duplicate and late older submissions stayed at revision 3. The publisher and reader SQLite files each held zero rows in all 11 canonical tables. The full resumed test passed in 87.42 seconds. The read login could `SELECT` all 13 tables and had no table mutation or schema creation privilege. A direct no-op `UPDATE` in a transaction returned `ERROR: permission denied for table session_results`.

The development network intermittently returned `SSL SYSCALL error: EOF detected`, `server closed the connection unexpectedly`, and `SeasonUnavailable` at the default four-second reader deadline. An earlier run reported a transient HTTP 500 on next meeting. The successful run used a 20-second reader deadline. Hosted availability and production latency still need separate validation.
