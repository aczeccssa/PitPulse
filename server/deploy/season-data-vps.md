# PP-57 VPS deployment

The [season data runbook](../season-data.md#migrate-switch-and-roll-back) describes the data model and import invariants. This procedure uses the existing CI Linux x86-64 archive and the existing **Deploy PitPulse Server** workflow. Use a disposable VPS or Linux VM for rehearsal. Production provisioning, the first production cutover, and any later data rollback require the operator to initiate them.

## Provision before the first cutover

Use the same reviewed revision for the VPS helpers and the release workflow. Deploy downloads a successful `main` CI artifact and the VPS verifies its provenance again. The forced command compares the three uploaded helpers byte for byte against the root-installed copies. Install `lib.sh`, `deploy-release.sh`, and `rollback-release.sh` from the reviewed checkout under `/usr/local/lib/pitpulse` as root with mode `0755`. Retain the prior copies with the rollback inventory. Keep the existing Caddy site, deploy account, and forced command. The server needs `flock` and `runuser` from util-linux, plus the existing deploy dependencies.

Install the service files from the checkout as root. The reader keeps the existing service account and HTTP listener. Its supplementary group permits connecting to the publisher socket. The publisher's systemd-managed runtime directory belongs to `pitpulse-publisher:pitpulse-socket`; only the publisher can create or remove entries. The publisher database lives in a separately owned `0700` state directory.

```sh
getent group pitpulse-socket >/dev/null || groupadd --system pitpulse-socket
id pitpulse-publisher >/dev/null 2>&1 ||
  useradd --system --gid pitpulse-socket --no-create-home --shell /usr/sbin/nologin pitpulse-publisher
install -d -m 0755 /etc/systemd/system/pitpulse-server.service.d
install -m 0644 pitpulse-server.service.d/season-data.conf /etc/systemd/system/pitpulse-server.service.d/
install -m 0644 pitpulse-publisher.service /etc/systemd/system/
systemctl daemon-reload
```

Place the following root-owned files outside Git. Use mode `0600` for the environment files. Provision separate Postgres logins. The publisher and migration operator use the schema owner. Rehearse with separately generated test credentials. The reader gets only `USAGE` on the application schema and `SELECT` on its tables. Supabase uses the session pooler with `sslmode=verify-full` and the provisioned CA readable by both services. Handle the DSNs with shell tracing off.

| File | Contents |
| --- | --- |
| `/etc/pitpulse/season.env` | `PITPULSE_SEASON_SCHEMA` for both services |
| `/etc/pitpulse/publisher.env` | `PITPULSE_SEASON_WRITE_DATABASE_URL` and any needed publisher-specific provider settings |
| Pending reader file | `PITPULSE_SEASON_READ_DATABASE_URL` and `F1_COMPANION_DATABASE_PATH=/var/lib/pitpulse/reader.sqlite`. The pending file can also set `PITPULSE_SEASON_QUERY_DEADLINE_SECONDS` if the verified hosted latency requires it. |

The live `/etc/pitpulse/reader.env` file selects central mode. Keep the pending file under a different name in the same directory until cutover. The regular `environment` file keeps the legacy SQLite path and the API token. Keep the shared TOML readable by both service users.

## First cutover

1. Verify and stage the selected CI archive on the isolated host with `deploy-release.sh /trusted/path/artifact.tar.gz --stage-only`. Record its SHA, the current release and operator configuration, and a baseline for calendar, standings, results, Live snapshot and the first SSE event. Keep the prior release and its configuration.
2. Reserve the maintenance window and keep manual CI dispatches idle. Stop the legacy HTTP service and confirm the publisher is stopped. Create and integrity-check a SQLite `.backup` in a private backup directory. Retain it as an immutable rollback source. The import accepts SQLite schema v11 or v12. Use a recent SQLite-mode binary against a separate copy to upgrade an older snapshot.
3. As migration operator, use the staged binary with the private writer, schema and reader-role settings. Run `season-data migrate`, `season-data import <snapshot>`, then `season-data verify <snapshot>`. Keep private reports. Confirm all supported counts match, excluded counts are expected, and a retry with the same snapshot inserts zero rows. If any values conflict, resolve the conflict before proceeding. Keep the publisher stopped throughout this phase.
4. Start a read-only canary with the staged binary, a different loopback port and a fresh SQLite file. Use a separate environment with only the reader credentials. Compare the reference season endpoints and Live/SSE, and check cache diagnostics. Stop the canary. If carrying local state, copy `sync_state` and `live_snapshot_cache` from the frozen snapshot to the initialized reader SQLite in a transaction. Seed publisher retry state separately if needed. Give each SQLite file and its parent the matching service ownership. Keep the legacy snapshot and working SQLite separate from both central files.
5. Atomically rename the pending reader file to `/etc/pitpulse/reader.env`. Run the verified deploy helper with the same archive, or dispatch the approved CI artifact once it is eligible for the existing manual workflow. The helper starts the reader, checks canonical reads, local/public auth, SSE and web assets, then starts and checks the publisher. Confirm both services are healthy before enabling the publisher at boot with `systemctl enable pitpulse-publisher`. A failed first activation restores the old release pointer. Follow the data rollback steps to restore service in SQLite mode.
6. Compare the baseline again. In rehearsal, issue an authenticated refresh against a controlled provider fixture. Confirm the queued result and observed generation/revision, and that the reader and publisher SQLite files have no canonical rows. Record the generation at traffic acceptance.

## Routine upgrade or binary rollback

Dispatch **Deploy PitPulse Server** with the successful `main` CI run ID and matching full SHA. The same root lock covers deploy and rollback. Both units resolve one release pointer. The helper verifies and materializes the artifact before stopping services, then stops the publisher and reader, starts the candidate reader, and starts the publisher after HTTP checks pass. It probes the publisher from the reader's Unix identity. Publisher readiness checks the socket, Postgres generation access, and update permission on the generation table using the writer login. An unsuccessful candidate restores the previous pointer and attempts to restart and verify its services. If a shared dependency is still down, the log reports that readiness did not recover.

For an operator-led binary rollback in central mode, run `/usr/local/lib/pitpulse/rollback-release.sh` as root. Its target must be a previously successful central release. Postgres and both SQLite state files continue in place. Keep subsequent schema changes backward-compatible with the rollback candidate. Use a separate reviewed data migration for incompatible changes.

## Check a running central deployment

Check both units and the publisher from the same Unix identity used by the HTTP reader.

```sh
systemctl is-active pitpulse-server pitpulse-publisher
runuser -u pitpulse -g pitpulse -G pitpulse-socket -- \
  curl --fail --silent --show-error --noproxy '*' --max-time 20 \
    --unix-socket /run/pitpulse-publisher/sync.sock http://publisher/ready
```

Both units should report `active`. The socket probe returns HTTP 204 with an empty body. Check a known season with the existing protected HTTP API and inspect its data and cache diagnostics. Inspect `journalctl -u pitpulse-server -u pitpulse-publisher` for startup errors. Retest Live/SSE through Caddy during the acceptance window.

## Roll back the first data cutover

1. Reserve a maintenance window and suspend routine dispatches. Disable and stop the publisher. Record the final Postgres generation and relevant revisions after writes stop. Stop the reader.
2. Move `reader.env` out of its active name. Restore the saved legacy configuration and release pointer. Move the stopped legacy database and any of its WAL/SHM files together into the private backup inventory. Restore a working copy of the preserved SQLite snapshot to the configured legacy path with ownership for `pitpulse`. If Live recovery moved forward, copy the newer `live_snapshot_cache` from a consistent reader snapshot into the rollback copy before starting HTTP.
3. Start the legacy service. Recheck local/public auth, representative season reads, Live snapshot and SSE. Keep the untouched migration snapshot, Postgres data, and both reports. Reconcile post-cutover Postgres revisions with the SQLite rollback state before any later cutover.

In rehearsal, also check denial for a user outside the socket group, restart the publisher after a forced process exit, and exercise a failed candidate before running manual rollback. Use identical artifact structure and the same helper commands. Keep sanitized evidence under `temp/docs/`.

### Instance season cache

In central mode the API uses a disposable `reader.season-cache.sqlite` alongside
`reader.sqlite`. `warm()` primes the current calendar, standings, Home and Results
on startup. When the Postgres generation matches, a populated cache can serve
these reads after restart without reloading the season from Postgres. The first
fill of a new generation queries Postgres, including one batch for season results.
Keep the sidecar with its instance and originating database. After restoring or
replacing the origin under the same database name, stop the API and remove the
sidecar before restarting. The sidecar can be removed with the API stopped and
is safe to exclude from backups.

| Setting | Default | Purpose |
| --- | --- | --- |
| `PITPULSE_SEASON_CACHE_DISK_BYTES` | `67108864` | SQLite file budget (64 MiB). `0` disables persistence. |
| `PITPULSE_SEASON_CACHE_MEMORY_BYTES` | `33554432` | Estimated heap budget for retained season entries (32 MiB). |
| `PITPULSE_SEASON_CACHE_MAX_STALE_SECONDS` | `21600` | Outage window from the last successful load or confirmation of its generation. |
| `PITPULSE_SEASON_CACHE_REVISION_SECONDS` | `5` | Interval between shared generation probes on reads. |
| `PITPULSE_SEASON_CACHE_TTL_SECONDS` | `60` | Refresh interval for derived dashboard views. Canonical disk snapshots follow the dataset generation. |

Cache diagnostics expose `diskBytes`, `memoryBytes`, `diskHits`, `originLoads`,
`hits`, `staleHits` and `revisionChecks`. Measure process RSS independently. The
legacy analysis archive in `reader.sqlite` has its own retention policy and is
separate from the season-cache budget. During origin outages a valid snapshot
can be served with stale metadata. A missing or expired snapshot returns the
existing retryable `season_data_unavailable` response.
