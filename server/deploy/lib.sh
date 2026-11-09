#!/usr/bin/env bash
# Shared, secret-safe helpers for the PitPulse release pipeline.
# This file is sourced by the bootstrap, deploy, rollback, and local drill scripts.

set -Eeuo pipefail

PITPULSE_DEPLOY_ROOT="${PITPULSE_DEPLOY_ROOT:-}"
PITPULSE_OPT_DIR="${PITPULSE_DEPLOY_ROOT}/opt/pitpulse"
PITPULSE_LIB_DIR="${PITPULSE_ROOT_LIB_DIR:-${PITPULSE_DEPLOY_ROOT}/var/lib/pitpulse}"
PITPULSE_ETC_DIR="${PITPULSE_DEPLOY_ROOT}/etc/pitpulse"
PITPULSE_BACKUP_DIR="${PITPULSE_DEPLOY_ROOT}/var/backups/pitpulse"
PITPULSE_SYSTEMD_DIR="${PITPULSE_DEPLOY_ROOT}/etc/systemd/system"
PITPULSE_CADDY_DIR="${PITPULSE_DEPLOY_ROOT}/etc/caddy"
PITPULSE_ENV_FILE="${PITPULSE_ETC_DIR}/environment"
PITPULSE_CONFIG_FILE="${PITPULSE_ETC_DIR}/config.toml"
PITPULSE_DEPLOY_SETTINGS_FILE="${PITPULSE_ETC_DIR}/deploy.env"
PITPULSE_CADDY_FILE="${PITPULSE_CADDY_DIR}/Caddyfile"
PITPULSE_CADDY_SNIPPET="${PITPULSE_CADDY_DIR}/pitpulse.caddyfile"
PITPULSE_DEPLOY_SCRIPT_DIR="${PITPULSE_DEPLOY_ROOT}/usr/local/lib/pitpulse"
PITPULSE_SERVICE_NAME="pitpulse-server"
PITPULSE_BIND="127.0.0.1:38701"
PITPULSE_DB_PATH="${PITPULSE_LIB_DIR}/pitpulse.sqlite"

log() {
    printf '[pitpulse] %s\n' "$*"
}

fail() {
    printf '[pitpulse] ERROR: %s\n' "$*" >&2
    exit 1
}

require_commands() {
    local name
    for name in "$@"; do
        command -v "$name" >/dev/null 2>&1 || fail "required command is unavailable: $name"
    done
}

require_root() {
    if [[ -n "$PITPULSE_DEPLOY_ROOT" ]]; then
        return 0
    fi
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "this action must run as root on the VPS"
}

systemctl_cmd() {
    if [[ -n "${PITPULSE_SYSTEMCTL:-}" ]]; then
        "${PITPULSE_SYSTEMCTL}" "$@"
    else
        systemctl "$@"
    fi
}

caddy_cmd() {
    if [[ -n "${PITPULSE_CADDY:-}" ]]; then
        "${PITPULSE_CADDY}" "$@"
    else
        caddy "$@"
    fi
}

resolve_path() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null
}

# Parse a simple KEY=VALUE file without sourcing it. Environment files are
# root-owned on the VPS; refusing to execute their contents keeps the deploy
# helper safe even if an operator accidentally pastes shell syntax into one.
load_environment() {
    local env_file="$1" mode require_token line name value
    [[ -f "$env_file" && ! -L "$env_file" ]] || return 1
    mode="$(file_mode "$env_file" 2>/dev/null || true)"
    [[ -n "$mode" ]] || return 1
    if (( (8#$mode & 8#077) != 0 )); then
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            return 1
        fi
        name="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        case "$name" in
            F1_COMPANION_*|F1_LIVE_ACCESS_TOKEN|F1_COMPANION_MAPBOX_PUBLIC_TOKEN) ;;
            *) return 1 ;;
        esac
        if [[ ! "$value" =~ ^[A-Za-z0-9._~+/:=-]*$ ]]; then
            return 1
        fi
        printf -v "$name" '%s' "$value"
        export "$name"
    done < "$env_file"

    [[ -n "${F1_COMPANION_TOKEN:-}" ]] || return 1
    [[ "$F1_COMPANION_TOKEN" != "REPLACE_WITH_A_NEW_HIGH_ENTROPY_RANDOM_TOKEN" ]] || return 1
    (( ${#F1_COMPANION_TOKEN} >= 32 )) || return 1
    [[ "$F1_COMPANION_TOKEN" =~ ^[A-Za-z0-9._~+/=-]+$ ]] || return 1
    require_token="$(printf '%s' "${F1_COMPANION_REQUIRE_TOKEN:-}" | tr '[:upper:]' '[:lower:]')"
    [[ "$require_token" =~ ^(1|true|yes|on)$ ]] || return 1
    [[ "${F1_COMPANION_BIND:-}" == "$PITPULSE_BIND" ]] || return 1
    [[ "${F1_COMPANION_DATABASE_PATH:-}" == "$PITPULSE_DB_PATH" ]] || return 1
    [[ "${F1_COMPANION_CONFIG:-}" == "$PITPULSE_CONFIG_FILE" ]] || return 1
    [[ -f "$PITPULSE_CONFIG_FILE" ]] || return 1
}

# Deployment settings are root-owned and contain no secrets. The only accepted
# key is a bare https origin for optional external health checks.
load_deploy_settings() {
    local settings="$1" mode line url=""
    [[ -f "$settings" && ! -L "$settings" ]] || return 0
    mode="$(file_mode "$settings" 2>/dev/null || true)"
    [[ -n "$mode" ]] || return 1
    if (( (8#$mode & 8#022) != 0 )); then
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" =~ ^PITPULSE_PUBLIC_BASE_URL=https://([A-Za-z0-9.-]+)/?$ ]] || return 1
        [[ -z "$url" ]] || return 1
        url="https://${BASH_REMATCH[1]}"
    done < "$settings"

    [[ -n "$url" ]] || return 1
    export PITPULSE_PUBLIC_BASE_URL="$url"
}

write_curl_config() {
    local path="$1" accept="$2" token="${F1_COMPANION_TOKEN:-}"
    [[ -n "$token" ]] || fail "cannot create curl config without a token"
    [[ "$token" =~ ^[A-Za-z0-9._~+/=-]+$ ]] || fail "token must be URL-safe before writing curl config"
    rm -f "$path"
    (
        umask 077
        printf 'header = "Authorization: Bearer %s"\nheader = "Accept: %s"\n' \
            "$token" "$accept" > "$path"
    )
    chmod 0600 "$path"
}

curl_cmd() {
    if [[ -n "${PITPULSE_CURL:-}" ]]; then
        "${PITPULSE_CURL}" "$@"
    else
        curl "$@"
    fi
}

http_status() {
    local url="$1" auth_config="${2:-}"
    local -a args=(-sS --max-time 10 -o /dev/null -w '%{http_code}')
    if [[ -n "$auth_config" ]]; then
        args+=(--config "$auth_config")
    fi
    curl_cmd "${args[@]}" "$url" || printf '000'
}

health_with_token() {
    local url="$1" auth_config="$2" output="$3"
    curl_cmd -sS --max-time 10 --config "$auth_config" -o "$output" "$url" >/dev/null || return 1
    jq -e '.database == true and .status == "ok"' "$output" >/dev/null
}

check_sse_first_event() {
    local url="$1" auth_config="$2" output="$3" headers="$3.headers"
    : > "$output"
    curl_cmd -N -sS --max-time 20 --dump-header "$headers" \
        --config "$auth_config" -o "$output" "$url" >/dev/null 2>&1 || true
    grep -qi '^content-type:[[:space:]]*text/event-stream' "$headers" || return 1
    grep -q '^event:' "$output"
}

wait_for_health() {
    local base_url="$1" auth_config="$2" work_dir="$3" attempts="${4:-30}" output
    local i health_code
    mkdir -p "$work_dir"
    output="$work_dir/health.json"
    base_url="${base_url%/}"
    for ((i = 1; i <= attempts; i++)); do
        health_code="$(http_status "$base_url/api/v1/health" "" 2>/dev/null || true)"
        if [[ "$health_code" == "401" ]] &&
            health_with_token "$base_url/api/v1/health" "$auth_config" "$output" 2>/dev/null; then
            return 0
        fi
        log "health attempt $i/$attempts pending"
        sleep 1
    done
    return 1
}

service_is_active() {
    systemctl_cmd is-active --quiet "$PITPULSE_SERVICE_NAME"
}

stop_service() {
    if service_is_active; then
        systemctl_cmd stop "$PITPULSE_SERVICE_NAME" >/dev/null
    fi
    local i
    for ((i = 1; i <= 10; i++)); do
        service_is_active || return 0
        sleep 1
    done
    service_is_active && return 1
    return 0
}

start_service() {
    systemctl_cmd start "$PITPULSE_SERVICE_NAME" >/dev/null
    service_is_active
}

sqlite_snapshot() {
    local db_path="$1" backup_dir="$2" stamp backup_path integrity
    mkdir -p "$backup_dir"
    chmod 0700 "$backup_dir" 2>/dev/null || true
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"

    if [[ -f "$db_path" ]]; then
        backup_path="$backup_dir/pitpulse-$stamp.sqlite"
        sqlite3 "$db_path" ".backup '$backup_path'" || return 1
        integrity="$(sqlite3 "$backup_path" 'PRAGMA integrity_check;' 2>/dev/null || true)"
        [[ "$integrity" == "ok" ]] || return 1
        (
            cd "$backup_dir"
            sha256sum "$(basename "$backup_path")" > SHA256SUMS
        )
        sqlite3 "$backup_path" 'PRAGMA user_version;' > "$backup_dir/user_version.txt"
        printf '%s\n' "$backup_path" > "$backup_dir/backup-path"
        printf '%s\n' "$backup_dir" > "$backup_dir/backup-dir"
    else
        printf 'absent\n' > "$backup_dir/user_version.txt"
        printf '%s\n' "$backup_dir" > "$backup_dir/backup-dir"
        : > "$backup_dir/SHA256SUMS"
        : > "$backup_dir/cold-start"
    fi
    printf '%s\n' "$backup_dir"
}

restore_db_from_backup() {
    local backup_dir="$1" db_path="$2" backup_path temp_path owner_group
    [[ -d "$backup_dir" && ! -L "$db_path" ]] || return 1
    backup_path="$(cat "$backup_dir/backup-path" 2>/dev/null || true)"

    if [[ -n "$backup_path" && -f "$backup_path" && ! -L "$backup_path" ]]; then
        temp_path="$(mktemp "$db_path.restore.XXXXXX")" || return 1
        cp -f "$backup_path" "$temp_path" || { rm -f "$temp_path"; return 1; }
        rm -f "$db_path-wal" "$db_path-shm"
        mv -fT "$temp_path" "$db_path" 2>/dev/null || mv -f "$temp_path" "$db_path" || return 1
        owner_group="$(stat -c '%U:%G' "$(dirname "$db_path")" 2>/dev/null || true)"
        [[ -n "$owner_group" ]] && chown "$owner_group" "$db_path"
        chmod 0600 "$db_path"
        [[ "$(sqlite3 "$db_path" 'PRAGMA integrity_check;' 2>/dev/null || true)" == "ok" ]] || return 1
        return 0
    fi

    if [[ -f "$backup_dir/cold-start" ]]; then
        rm -f "$db_path" "$db_path-wal" "$db_path-shm"
        return 0
    fi

    return 1
}

atomic_set_symlink() {
    local target="$1" link_path="$2" tmp_path
    tmp_path="${link_path}.tmp.$$"
    rm -f "$tmp_path"
    ln -s "$target" "$tmp_path" || return 1
    if mv --help 2>&1 | grep -q -- '--no-target-directory'; then
        mv -Tf "$tmp_path" "$link_path"
    else
        # macOS fallback: rename(2) replaces an existing symlink atomically.
        mv -f "$tmp_path" "$link_path"
    fi
}

verify_artifact() {
    local archive="$1" stage_dir="$2" skip_binary_preflight="${3:-0}" version
    local unexpected name
    [[ -f "$archive" && ! -L "$archive" ]] || fail "missing or linked artifact: $archive"
    unexpected="$(tar -tzf "$archive" | grep -Ev '^(pitpulse-server|VERSION|SHA256SUMS|ldd\.txt|config\.production\.toml|pitpulse-server\.service|pitpulse\.caddyfile)$' || true)"
    if [[ -n "$unexpected" ]]; then
        return 1
    fi
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir"
    chmod 0700 "$stage_dir"
    tar -xzf "$archive" -C "$stage_dir" || fail "cannot unpack artifact"

    for name in pitpulse-server VERSION SHA256SUMS ldd.txt \
        config.production.toml pitpulse-server.service pitpulse.caddyfile; do
        [[ -f "$stage_dir/$name" && ! -L "$stage_dir/$name" ]] || fail "artifact is missing $name"
    done

    local sum_line sum_hash sum_name
    while IFS= read -r sum_line || [[ -n "$sum_line" ]]; do
        [[ -z "$sum_line" ]] && continue
        [[ "$sum_line" =~ ^([0-9a-fA-F]{64})[[:space:]]+(pitpulse-server|VERSION|ldd\.txt|config\.production\.toml|pitpulse-server\.service|pitpulse\.caddyfile)$ ]] ||
            fail "SHA256SUMS contains an unexpected entry"
        sum_hash="${BASH_REMATCH[1]}"
        sum_name="${BASH_REMATCH[2]}"
        [[ -f "$stage_dir/$sum_name" ]] || fail "SHA256SUMS references missing $sum_name"
    done < "$stage_dir/SHA256SUMS"

    (
        cd "$stage_dir"
        sha256sum -c SHA256SUMS
    ) >/dev/null || fail "artifact SHA256 verification failed"

    version="$(tr -d '[:space:]' < "$stage_dir/VERSION")"
    [[ "$version" =~ ^[0-9a-fA-F]{7,40}$ ]] || fail "artifact VERSION is not a Git commit SHA"

    if [[ "$skip_binary_preflight" != "1" ]]; then
        file "$stage_dir/pitpulse-server" | grep -q 'ELF 64-bit.*x86-64' ||
            fail "artifact binary is not an x86-64 Linux ELF executable"
        ldd "$stage_dir/pitpulse-server" > "$stage_dir/ldd.actual.txt" ||
            fail "ldd could not inspect the artifact binary"
        ! grep -q 'not found' "$stage_dir/ldd.actual.txt" ||
            fail "artifact binary has unresolved shared libraries"
    else
        cp "$stage_dir/ldd.txt" "$stage_dir/ldd.actual.txt"
    fi

    chmod 0755 "$stage_dir/pitpulse-server"
    printf '%s\n' "$version"
}
