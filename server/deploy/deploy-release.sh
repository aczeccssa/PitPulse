#!/usr/bin/env bash
# Versioned, rollback-capable deployment of a CI release artifact.
# Run on the VPS after the manual GitHub Actions deploy approval. The script
# does not fetch source, build Rust, add DNS records, create tokens or secrets,
# or copy any local SQLite database.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_commands python3 jq tar sha256sum file sqlite3 curl grep date sleep base64
if [[ "${PITPULSE_SKIP_BINARY_PREFLIGHT:-0}" != "1" ]]; then
    require_commands ldd
fi
if [[ -z "${PITPULSE_SYSTEMCTL:-}" ]]; then
    require_commands systemctl
fi
require_root

ARCHIVE="${1:-}"
[[ -n "$ARCHIVE" ]] || fail "usage: deploy-release.sh <artifact.tar.gz>"
[[ -f "$ARCHIVE" && ! -L "$ARCHIVE" ]] || fail "artifact not found: $ARCHIVE"
[[ -f "$PITPULSE_CONFIG_FILE" ]] || fail "run bootstrap-vps.sh first; missing $PITPULSE_CONFIG_FILE"
[[ -f "$PITPULSE_SYSTEMD_DIR/$PITPULSE_SERVICE_NAME.service" ]] || fail "systemd unit is not installed"

load_environment "$PITPULSE_ENV_FILE" || fail "$PITPULSE_ENV_FILE is missing, unsafe, or contains an invalid token/config"
load_deploy_settings "${PITPULSE_DEPLOY_SETTINGS_FILE:-$PITPULSE_ETC_DIR/deploy.env}" ||
    fail "production public URL settings are missing or invalid"
[[ "${PITPULSE_PUBLIC_BASE_URL:-}" == "https://pitpulse.lestere.bond" ]] ||
    fail "production public URL must be https://pitpulse.lestere.bond"
require_commands tr stat
CONFIG_DIGEST="$(sha256sum "$PITPULSE_CONFIG_FILE" | cut -d' ' -f1)"
log "using operator-owned config $PITPULSE_CONFIG_FILE; deploy never replaces it"

mkdir -p "$PITPULSE_OPT_DIR/releases" "$PITPULSE_OPT_DIR/releases.incoming" "$PITPULSE_LIB_DIR" "$PITPULSE_BACKUP_DIR"
WORK_DIR="$(mktemp -d "$PITPULSE_BACKUP_DIR/deploy.XXXXXX")"
CURL_AUTH="$WORK_DIR/curl-auth.cfg"
CURL_SSE="$WORK_DIR/curl-sse.cfg"
trap 'rm -rf "$WORK_DIR"' EXIT

log "verifying artifact metadata and Linux x86-64 shared-library preflight"
VERSION="$(verify_artifact "$ARCHIVE" "$WORK_DIR/stage" "${PITPULSE_SKIP_BINARY_PREFLIGHT:-0}")"
if [[ -n "${PITPULSE_DEPLOY_ARTIFACT_SHA:-}" && "$VERSION" != "$PITPULSE_DEPLOY_ARTIFACT_SHA" ]]; then
    fail "artifact VERSION does not match the forced-command SHA"
fi
RELEASE_DIR="$PITPULSE_OPT_DIR/releases/$VERSION"
PREVIOUS_TARGET=""
BACKUP_DIR=""
CURRENT_WAS_ACTIVE=0
SWITCHED=0

write_curl_config "$CURL_AUTH" "application/json"
write_curl_config "$CURL_SSE" "text/event-stream"

rollback() {
    local reason="$1"
    log "deployment failed: $reason; attempting rollback"

    stop_service >/dev/null 2>&1 || true

    if [[ -n "$BACKUP_DIR" ]]; then
        restore_db_from_backup "$BACKUP_DIR" "$PITPULSE_DB_PATH" ||
            log "WARNING: could not restore database from $BACKUP_DIR"
    fi

    if [[ "$SWITCHED" == "1" ]]; then
        if [[ -n "$PREVIOUS_TARGET" && -f "$PREVIOUS_TARGET/pitpulse-server" ]]; then
            atomic_set_symlink "$PREVIOUS_TARGET" "$PITPULSE_OPT_DIR/current" ||
                log "WARNING: could not restore previous release symlink"
            printf '%s\n' "$PREVIOUS_TARGET" > "$PITPULSE_OPT_DIR/previous"
        else
            rm -f "$PITPULSE_OPT_DIR/current"
        fi
    fi

    if (( CURRENT_WAS_ACTIVE )) && [[ -f "$PITPULSE_OPT_DIR/current/pitpulse-server" ]]; then
        if start_service >/dev/null 2>&1 &&
            wait_for_health "http://$PITPULSE_BIND" "$CURL_AUTH" "$WORK_DIR" 15 >/dev/null 2>&1; then
            log "rollback restored the previous release and health check"
        else
            log "WARNING: rollback health check failed; leave the service stopped for inspection"
        fi
    else
        log "no previously active release was restored"
    fi

    fail "$reason"
}

if [[ -L "$PITPULSE_OPT_DIR/current" ]]; then
    PREVIOUS_TARGET="$(resolve_path "$PITPULSE_OPT_DIR/current")"
fi
if service_is_active; then
    CURRENT_WAS_ACTIVE=1
fi

if [[ -e "$RELEASE_DIR" ]]; then
    log "release $VERSION is already materialized; reusing immutable directory"
    (
        cd "$RELEASE_DIR"
        sha256sum -c SHA256SUMS
    ) >/dev/null || rollback "existing release $VERSION failed checksum verification"
else
    install -d -m 0755 "$RELEASE_DIR"
    for name in VERSION SHA256SUMS ldd.txt config.production.toml \
        pitpulse-server.service pitpulse.caddyfile; do
        install -m 0644 "$WORK_DIR/stage/$name" "$RELEASE_DIR/$name"
    done
    install -m 0755 "$WORK_DIR/stage/pitpulse-server" "$RELEASE_DIR/pitpulse-server"
    install -m 0644 "$WORK_DIR/stage/ldd.actual.txt" "$RELEASE_DIR/ldd.actual.txt"
    log "materialized release $VERSION"
fi

log "stopping the single SQLite writer"
stop_service || rollback "could not stop $PITPULSE_SERVICE_NAME"

BACKUP_DIR="$(sqlite_snapshot "$PITPULSE_DB_PATH" "$PITPULSE_BACKUP_DIR/$VERSION-$(date -u +%Y%m%dT%H%M%SZ)")" ||
    rollback "SQLite backup or integrity check failed"
log "SQLite snapshot recorded at $BACKUP_DIR"

atomic_set_symlink "$RELEASE_DIR" "$PITPULSE_OPT_DIR/current" || rollback "could not switch current release symlink"
if [[ -n "$PREVIOUS_TARGET" ]]; then
    printf '%s\n' "$PREVIOUS_TARGET" > "$PITPULSE_OPT_DIR/previous"
fi
SWITCHED=1
log "current release now points to $VERSION"

start_service || rollback "systemd could not start the new release"
wait_for_health "http://$PITPULSE_BIND" "$CURL_AUTH" "$WORK_DIR" ||
    rollback "authenticated health / unauthenticated 401 check failed"

unauth_status="$(http_status "http://$PITPULSE_BIND/api/v1/health" "" || true)"
[[ "$unauth_status" == "401" ]] || rollback "unauthenticated health returned ${unauth_status:-no-response}, expected 401"

check_sse_first_event \
    "http://$PITPULSE_BIND/api/v1/live/stream?series=f1" \
    "$CURL_SSE" "$WORK_DIR/sse.txt" ||
    rollback "SSE first event was not received"

caddy_cmd validate --config "$PITPULSE_CADDY_FILE" >/dev/null 2>&1 ||
    rollback "Caddy config validation failed; existing Caddy routes were not changed"

public_base="${PITPULSE_PUBLIC_BASE_URL%/}"
public_status="$(http_status "$public_base/api/v1/health" "" || true)"
[[ "$public_status" == "401" ]] || rollback "public unauthenticated health returned ${public_status:-no-response}, expected 401"
health_with_token "$public_base/api/v1/health" "$CURL_AUTH" "$WORK_DIR/public-health.json" ||
    rollback "public authenticated health check failed"
check_sse_first_event "$public_base/api/v1/live/stream?series=f1" "$CURL_SSE" "$WORK_DIR/public-sse.txt" ||
    rollback "public SSE first event was not received"
log "public HTTPS health and SSE checks passed"

[[ "$(sha256sum "$PITPULSE_CONFIG_FILE" | cut -d' ' -f1)" == "$CONFIG_DIGEST" ]] ||
    rollback "operator-owned config changed during deployment"
log "operator-owned config remained unchanged across deployment"

log "deployment $VERSION passed local and public health checks"
log "database user_version: $(cat "$BACKUP_DIR/user_version.txt" 2>/dev/null || printf 'unknown')"
