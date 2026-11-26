#!/usr/bin/env bash
# Manual rollback to the release recorded in /opt/pitpulse/previous.
# Set PITPULSE_RESTORE_DB=1 only when the failed deployment changed SQLite's
# schema and the matching backup must be restored.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_commands python3 jq curl sqlite3 date sha256sum stat
if [[ -z "${PITPULSE_SYSTEMCTL:-}" ]]; then
    require_commands systemctl
fi
require_root

lock_release_operation
select_release_mode
load_environment "$PITPULSE_ENV_FILE"

restore_db="${PITPULSE_RESTORE_DB:-0}"
backup_dir="${PITPULSE_BACKUP_DIR_ARG:-}"
previous_file="$PREVIOUS_FILE"
if [[ "$RELEASE_MODE" == central && "$restore_db" == 1 ]]; then
    fail "SQLite restore requires the operator-led data rollback procedure"
fi
[[ -f "$previous_file" && ! -L "$previous_file" ]] || fail "no previous release marker at $previous_file"
marker="$(cat "$previous_file")"
target="$(resolve_path "$marker")"
release_root="$(resolve_path "$PITPULSE_OPT_DIR/releases")"
[[ "$marker" == "$PITPULSE_OPT_DIR/releases/"* || "$marker" == "$release_root/"* ]] ||
    fail "previous release marker points outside releases directory"
[[ "$target" == "$release_root/"* ]] || fail "previous release resolves outside releases directory"
[[ "$RELEASE_MODE" == sqlite || -f "$target/.central-ready" ]] ||
    fail "rollback target has no successful central deployment"
[[ -f "$target/pitpulse-server" && ! -L "$target/pitpulse-server" ]] || fail "previous release binary is missing"
(
    cd "$target"
    sha256sum -c SHA256SUMS
) >/dev/null || fail "previous release failed checksum verification"

WORK_DIR="$(mktemp -d "$PITPULSE_BACKUP_DIR/rollback.XXXXXX")"
CURL_AUTH="$WORK_DIR/curl-auth.cfg"
CURL_SSE="$WORK_DIR/curl-sse.cfg"
trap 'rm -rf "$WORK_DIR"' EXIT
write_curl_config "$CURL_AUTH" "application/json"
write_curl_config "$CURL_SSE" "text/event-stream"

CURRENT_TARGET="$(resolve_path "$PITPULSE_OPT_DIR/current")"
if [[ "$RELEASE_MODE" == central ]]; then
    [[ "$CURRENT_TARGET" == "$release_root/"* && -f "$CURRENT_TARGET/.central-ready" ]] ||
        fail "current release was not verified in central mode"
fi
log "stopping release services ($RELEASE_MODE mode)"
stop_release || fail "could not stop release services"

if [[ "$restore_db" == "1" ]]; then
    [[ -n "$backup_dir" && -d "$backup_dir" ]] ||
        fail "PITPULSE_RESTORE_DB=1 requires an explicit PITPULSE_BACKUP_DIR_ARG"
    [[ -f "$backup_dir/backup-dir" && -f "$backup_dir/user_version.txt" ]] ||
        fail "backup directory has no complete PitPulse manifest"
    (
        cd "$backup_dir"
        sha256sum -c SHA256SUMS
    ) >/dev/null || fail "backup checksum verification failed"
    restore_db_from_backup "$backup_dir" "$PITPULSE_DB_PATH" || fail "database restore failed"
    log "restored SQLite from $backup_dir"
fi

atomic_set_symlink "$target" "$PITPULSE_OPT_DIR/current" || fail "could not switch current symlink"
if ! start_http_and_check "$CURL_AUTH" "$WORK_DIR" ||
   ! check_sse_first_event "http://$PITPULSE_BIND/api/v1/live/stream?series=f1" "$CURL_SSE" "$WORK_DIR/sse.txt" ||
   ! start_publisher_and_check; then
    if [[ "$RELEASE_MODE" == central ]]; then
        stop_release &&
            atomic_set_symlink "$CURRENT_TARGET" "$PITPULSE_OPT_DIR/current" ||
            fail "could not restore the current release pointer"
        recovery_ok=1
        start_http_and_check "$CURL_AUTH" "$WORK_DIR" || recovery_ok=0
        start_publisher_and_check || recovery_ok=0
        (( recovery_ok )) || log "WARNING: current release selected, but readiness failed"
    fi
    fail "previous release did not pass readiness checks"
fi
log "rollback complete: $(basename "$target")"
