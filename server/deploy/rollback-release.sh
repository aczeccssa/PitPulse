#!/usr/bin/env bash
# Manual rollback to the release recorded in /opt/pitpulse/previous.
# Set PITPULSE_RESTORE_DB=1 only when the failed deployment changed SQLite's
# schema and the matching backup must be restored.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_commands python3 jq curl sqlite3 date sha256sum
if [[ -z "${PITPULSE_SYSTEMCTL:-}" ]]; then
    require_commands systemctl
fi
require_root

load_environment "$PITPULSE_ENV_FILE"

restore_db="${PITPULSE_RESTORE_DB:-0}"
backup_dir="${PITPULSE_BACKUP_DIR_ARG:-}"
previous_file="$PITPULSE_OPT_DIR/previous"
[[ -f "$previous_file" && ! -L "$previous_file" ]] || fail "no previous release marker at $previous_file"
marker="$(cat "$previous_file")"
target="$(resolve_path "$marker")"
release_root="$(resolve_path "$PITPULSE_OPT_DIR/releases")"
[[ "$marker" == "$PITPULSE_OPT_DIR/releases/"* || "$marker" == "$release_root/"* ]] ||
    fail "previous release marker points outside releases directory"
[[ "$target" == "$release_root/"* ]] || fail "previous release resolves outside releases directory"
[[ -f "$target/pitpulse-server" && ! -L "$target/pitpulse-server" ]] || fail "previous release binary is missing"
(
    cd "$target"
    sha256sum -c SHA256SUMS
) >/dev/null || fail "previous release failed checksum verification"

WORK_DIR="$(mktemp -d "$PITPULSE_BACKUP_DIR/rollback.XXXXXX")"
CURL_AUTH="$WORK_DIR/curl-auth.cfg"
trap 'rm -rf "$WORK_DIR"' EXIT
write_curl_config "$CURL_AUTH" "application/json"

log "stopping the current single SQLite writer"
stop_service || fail "could not stop $PITPULSE_SERVICE_NAME"

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
start_service || fail "systemd could not start the previous release"
wait_for_health "http://$PITPULSE_BIND" "$CURL_AUTH" "$WORK_DIR" ||
    fail "previous release did not pass authenticated health / unauthenticated 401 checks"
log "rollback complete: $(basename "$target")"
