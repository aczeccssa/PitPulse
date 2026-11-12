#!/usr/bin/env bash
# Local, isolated drill for the deployment helpers. It never touches the
# running Run Server, Run Live Replay, Run App, production VPS, real SQLite,
# real secrets, DNS, Caddy, or systemd.
#
# The harness sandbox may prohibit TCP/Unix socket binding. In that case the
# drill injects a curl-compatible responder through PITPULSE_CURL and clearly
# labels socket-level HTTP/SSE as unverified; the production helpers still run
# against the same request arguments and response bodies.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pitpulse-deploy-drill.XXXXXX")"
AUTH_CONFIG="$WORK_DIR/curl-auth.cfg"
SSE_CONFIG="$WORK_DIR/curl-sse.cfg"
HEALTH_OUTPUT="$WORK_DIR/health-output"
SSE_OUTPUT="$WORK_DIR/sse.txt"
CADDYFILE="$WORK_DIR/etc/caddy/Caddyfile"
FAKE_CURL="$WORK_DIR/fake-curl.py"
FAKE_SYSTEMCTL="$WORK_DIR/fake-systemctl.sh"
FAKE_CADDY="$WORK_DIR/fake-caddy.sh"

export PITPULSE_DEPLOY_ROOT="$WORK_DIR"
export WORK_DIR
export PITPULSE_SYSTEMCTL="$FAKE_SYSTEMCTL"
export PITPULSE_CADDY="$FAKE_CADDY"
export PITPULSE_CURL="$FAKE_CURL"

# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

cleanup() {
    printf '[drill] workspace kept at %s\n' "$WORK_DIR"
}
trap cleanup EXIT

require_commands python3 jq sqlite3 curl caddy sha256sum tar file head sleep openssl base64 ssh-keygen grep zip unzip
mkdir -p "$WORK_DIR/etc/pitpulse" "$WORK_DIR/etc/systemd/system" "$WORK_DIR/etc/caddy" \
    "$WORK_DIR/var/lib/pitpulse" "$WORK_DIR/var/backups/pitpulse" "$WORK_DIR/opt/pitpulse/releases"

TOKEN="$(openssl rand -hex 24)"
cat > "$PITPULSE_ENV_FILE" <<EOF
F1_COMPANION_CONFIG=$PITPULSE_CONFIG_FILE
F1_COMPANION_BIND=$PITPULSE_BIND
F1_COMPANION_DATABASE_PATH=$PITPULSE_DB_PATH
F1_COMPANION_REQUIRE_TOKEN=true
F1_COMPANION_TOKEN=$TOKEN
EOF
chmod 0600 "$PITPULSE_ENV_FILE"
install -m 0644 "$SCRIPT_DIR/config.production.toml" "$PITPULSE_CONFIG_FILE"
printf '\n# operator-owned config sentinel: must survive bootstrap and deploy\n' \
    >> "$PITPULSE_CONFIG_FILE"

cat > "$FAKE_CURL" <<'PY'
#!/usr/bin/env python3
"""Minimal curl-compatible responder for a sandbox without socket binding."""
import os
import sys

TOKEN = os.environ["F1_COMPANION_TOKEN"]
args = sys.argv[1:]
url = args[-1] if args else ""
config = ""
output = ""
header_file = ""
write_out = ""
is_sse = "-N" in args
authorized = False

i = 0
while i < len(args):
    arg = args[i]
    if arg == "--config" and i + 1 < len(args):
        config = args[i + 1]
        i += 1
    elif arg == "-o" and i + 1 < len(args):
        output = args[i + 1]
        i += 1
    elif arg == "--dump-header" and i + 1 < len(args):
        header_file = args[i + 1]
        i += 1
    elif arg == "-w" and i + 1 < len(args):
        write_out = args[i + 1]
        i += 1
    i += 1

if config:
    with open(config, encoding="utf-8") as handle:
        authorized = "Bearer " + TOKEN in handle.read()

if not authorized:
    body = b'{"error":{"code":"unauthorized"}}'
    status = "401"
elif "/api/v1/health" in url:
    if not os.path.exists(os.environ["F1_COMPANION_DATABASE_PATH"]):
        body = b'{"status":"degraded","database":false}'
    else:
        body = b'{"status":"ok","database":true,"live":false,"version":"drill"}'
    status = "200"
elif "/api/v1/live/stream" in url and is_sse:
    body = b"event:snapshot\ndata:{}\n\n"
    status = "200"
else:
    body = b'{"error":{"code":"not_found"}}'
    status = "404"

wrote_output = False
if output and output != os.devnull:
    with open(output, "wb") as handle:
        handle.write(body)
    wrote_output = True
if header_file:
    content_type = "text/event-stream" if is_sse else "application/json"
    with open(header_file, "w", encoding="utf-8") as handle:
        handle.write("HTTP/2 200\r\ncontent-type: " + content_type + "\r\n\r\n")
if write_out == "%{http_code}":
    print(status, end="")
elif not wrote_output:
    sys.stdout.buffer.write(body)
PY
chmod 0700 "$FAKE_CURL"

cat > "$FAKE_SYSTEMCTL" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state="$WORK_DIR/service.state"
case "${1:-}" in
    start) printf '%s\n' "$$" > "$state" ;;
    stop) rm -f "$state" ;;
    is-active) [[ -f "$state" ]] ;;
    reload|daemon-reload) exit 0 ;;
    *) exit 1 ;;
esac
EOF
chmod 0755 "$FAKE_SYSTEMCTL"

cat > "$FAKE_CADDY" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "validate" ]]; then
    [[ -f "${3:-}" ]] || exit 1
    grep -Eq '^\([[:space:]]*access_log[[:space:]]*\)[[:space:]]*\{' "${3:-}" || exit 1
    exit 0
fi
exec caddy "$@"
EOF
chmod 0755 "$FAKE_CADDY"

cat > "$CADDYFILE" <<'EOF'
{
    auto_https disable_redirects
    skip_install_trust
}

(access_log) {
    log {
        format filter {
            request>headers>Authorization delete
        }
    }
}

https://drill.lestere.test {
    import access_log drill
    reverse_proxy 127.0.0.1:38701 {
        flush_interval -1
    }
}
EOF

STAGE="$WORK_DIR/artifact-stage"
mkdir -p "$STAGE"
cp "$FAKE_CURL" "$STAGE/pitpulse-server"
printf '%s\n' "0123456789abcdef0123456789abcdef01234567" > "$STAGE/VERSION"
printf '%s\n' "ELF 64-bit LSB executable, x86-64, dynamically linked (drill placeholder)" > "$STAGE/ldd.txt"
for template in config.production.toml pitpulse-server.service pitpulse.caddyfile; do
    cp "$SCRIPT_DIR/$template" "$STAGE/$template"
done
(
    cd "$STAGE"
    sha256sum pitpulse-server VERSION ldd.txt config.production.toml \
        pitpulse-server.service pitpulse.caddyfile > SHA256SUMS
)
ARCHIVE="$WORK_DIR/pitpulse-server-drill.tar.gz"
tar -czf "$ARCHIVE" -C "$STAGE" \
    pitpulse-server VERSION SHA256SUMS ldd.txt \
    config.production.toml pitpulse-server.service pitpulse.caddyfile

log "1/12 verifying artifact helper and rejecting untrusted archive paths"
DRILL_VERSION="$(verify_artifact "$ARCHIVE" "$WORK_DIR/verify" 1)"
[[ "$DRILL_VERSION" == "0123456789abcdef0123456789abcdef01234567" ]] || fail "artifact VERSION mismatch"
EVIL_STAGE="$WORK_DIR/evil-stage"
mkdir -p "$EVIL_STAGE"
cp "$STAGE/pitpulse-server" "$EVIL_STAGE/pitpulse-server"
cp "$STAGE/VERSION" "$EVIL_STAGE/VERSION"
cp "$STAGE/ldd.txt" "$EVIL_STAGE/ldd.txt"
cp "$STAGE/SHA256SUMS" "$EVIL_STAGE/SHA256SUMS"
printf '%s\n' unsafe > "$EVIL_STAGE/unexpected.txt"
for template in config.production.toml pitpulse-server.service pitpulse.caddyfile; do
    cp "$STAGE/$template" "$EVIL_STAGE/$template"
done
EVIL_ARCHIVE="$WORK_DIR/pitpulse-server-evil.tar.gz"
tar -czf "$EVIL_ARCHIVE" -C "$EVIL_STAGE" \
    pitpulse-server VERSION SHA256SUMS ldd.txt \
    config.production.toml pitpulse-server.service pitpulse.caddyfile unexpected.txt
if verify_artifact "$EVIL_ARCHIVE" "$WORK_DIR/evil-verify" 1 >/dev/null 2>&1; then
    fail "artifact verifier accepted an unexpected archive path"
fi

log "2/12 verifying environment parsing, token policy and secret-safe curl configs"
load_environment "$PITPULSE_ENV_FILE"
export F1_COMPANION_TOKEN F1_COMPANION_DATABASE_PATH
write_curl_config "$AUTH_CONFIG" "application/json"
write_curl_config "$SSE_CONFIG" "text/event-stream"
[[ "$(file_mode "$PITPULSE_ENV_FILE")" =~ 0?600 ]] || fail "environment file mode is not private"
[[ "$(file_mode "$AUTH_CONFIG")" =~ 0?600 ]] || fail "curl auth config mode is not private"
grep -q "Bearer $TOKEN" "$AUTH_CONFIG" || fail "curl auth config did not receive the drill token"
INJECTION_ENV="$WORK_DIR/injection.env"
printf 'INJECTED_VALUE=should-not-run\n' > "$INJECTION_ENV"
printf 'F1_COMPANION_CONFIG=%s\n' "$PITPULSE_CONFIG_FILE" >> "$INJECTION_ENV"
printf 'F1_COMPANION_BIND=%s\n' "$PITPULSE_BIND" >> "$INJECTION_ENV"
printf 'F1_COMPANION_DATABASE_PATH=%s\n' "$PITPULSE_DB_PATH" >> "$INJECTION_ENV"
printf 'F1_COMPANION_REQUIRE_TOKEN=true\n' >> "$INJECTION_ENV"
printf 'F1_COMPANION_TOKEN=%s\n' "$TOKEN" >> "$INJECTION_ENV"
printf 'X=$(touch %s/executed)\n' "$WORK_DIR" >> "$INJECTION_ENV"
chmod 0600 "$INJECTION_ENV"
if (load_environment "$INJECTION_ENV") >/dev/null 2>&1; then
    fail "environment parser accepted a shell-injection line"
fi
[[ ! -f "$WORK_DIR/executed" ]] || fail "environment parser executed shell syntax"
PLACEHOLDER_ENV="$WORK_DIR/placeholder.env"
{
    printf 'F1_COMPANION_CONFIG=%s\n' "$PITPULSE_CONFIG_FILE"
    printf 'F1_COMPANION_BIND=%s\n' "$PITPULSE_BIND"
    printf 'F1_COMPANION_DATABASE_PATH=%s\n' "$PITPULSE_DB_PATH"
    printf 'F1_COMPANION_REQUIRE_TOKEN=true\n'
    printf 'F1_COMPANION_TOKEN=REPLACE_WITH_A_NEW_HIGH_ENTROPY_RANDOM_TOKEN\n'
} > "$PLACEHOLDER_ENV"
chmod 0600 "$PLACEHOLDER_ENV"
if (load_environment "$PLACEHOLDER_ENV") >/dev/null 2>&1; then
    fail "environment parser accepted the example placeholder token"
fi

log "3/12 verifying deploy settings are parsed, not sourced"
printf '# comments and blank lines are allowed\n\nPITPULSE_PUBLIC_BASE_URL=https://pitpulse.example.test/\n\n' > "$PITPULSE_DEPLOY_SETTINGS_FILE"
chmod 0644 "$PITPULSE_DEPLOY_SETTINGS_FILE"
unset PITPULSE_PUBLIC_BASE_URL
load_deploy_settings "$PITPULSE_DEPLOY_SETTINGS_FILE"
[[ "$PITPULSE_PUBLIC_BASE_URL" == "https://pitpulse.example.test" ]] || fail "deploy settings URL was not loaded"
printf 'X=$(touch %s/executed-settings)\n' "$WORK_DIR" > "$PITPULSE_DEPLOY_SETTINGS_FILE"
if (load_deploy_settings "$PITPULSE_DEPLOY_SETTINGS_FILE") >/dev/null 2>&1; then
    fail "deploy settings parser accepted a shell-injection line"
fi
[[ ! -f "$WORK_DIR/executed-settings" ]] || fail "deploy settings parser executed shell syntax"
printf 'PITPULSE_PUBLIC_BASE_URL=https://pitpulse.lestere.bond\n' > "$PITPULSE_DEPLOY_SETTINGS_FILE"
chmod 0644 "$PITPULSE_DEPLOY_SETTINGS_FILE"
unset PITPULSE_PUBLIC_BASE_URL

log "4/12 verifying atomic symlink switching"
atomic_set_symlink "$WORK_DIR/release-one" "$WORK_DIR/current"
[[ "$(resolve_path "$WORK_DIR/current")" == "$(resolve_path "$WORK_DIR/release-one")" ]] || fail "first symlink switch failed"
atomic_set_symlink "$WORK_DIR/release-two" "$WORK_DIR/current"
[[ "$(resolve_path "$WORK_DIR/current")" == "$(resolve_path "$WORK_DIR/release-two")" ]] || fail "second symlink switch failed"

log "5/12 verifying SQLite backup, integrity and cold-start handling"
sqlite3 "$PITPULSE_DB_PATH" 'CREATE TABLE IF NOT EXISTS predeploy (value TEXT); INSERT INTO predeploy VALUES ("before");'
SNAPSHOT="$(sqlite_snapshot "$PITPULSE_DB_PATH" "$WORK_DIR/backup-existing")"
[[ -f "$SNAPSHOT/backup-path" ]] || fail "SQLite backup manifest missing"
[[ "$(cat "$SNAPSHOT/user_version.txt")" =~ ^[0-9]+$ ]] || fail "SQLite user_version was not recorded"
restore_db_from_backup "$SNAPSHOT" "$PITPULSE_DB_PATH" || fail "SQLite restore failed"
[[ "$(sqlite3 "$PITPULSE_DB_PATH" 'SELECT count(*) FROM predeploy;')" == "1" ]] || fail "restored SQLite lost data"
rm -f "$PITPULSE_DB_PATH" "$PITPULSE_DB_PATH-wal" "$PITPULSE_DB_PATH-shm"
COLD_SNAPSHOT="$(sqlite_snapshot "$PITPULSE_DB_PATH" "$WORK_DIR/backup-cold")"
[[ -f "$COLD_SNAPSHOT/cold-start" ]] || fail "cold-start snapshot marker missing"
restore_db_from_backup "$COLD_SNAPSHOT" "$PITPULSE_DB_PATH" || fail "cold-start restore failed"
sqlite3 "$PITPULSE_DB_PATH" 'CREATE TABLE IF NOT EXISTS cold_start (value TEXT);'

log "6/12 exercising deployment helpers through a curl-compatible responder"
systemctl_cmd start "$PITPULSE_SERVICE_NAME"
wait_for_health "http://$PITPULSE_BIND" "$AUTH_CONFIG" "$HEALTH_OUTPUT" || fail "health gate failed"
unauth_status="$(http_status "http://$PITPULSE_BIND/api/v1/health" "")"
[[ "$unauth_status" == "401" ]] || fail "unauthenticated request returned $unauth_status, expected 401"
check_sse_first_event "http://$PITPULSE_BIND/api/v1/live/stream?series=f1" "$SSE_CONFIG" "$SSE_OUTPUT" ||
    fail "SSE first event check failed"
systemctl_cmd stop "$PITPULSE_SERVICE_NAME"

log "7/12 attempting a real loopback listener (may be blocked by the harness sandbox)"
set +e
python3 -c 'import socket, sys; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' \
    > "$WORK_DIR/listener-port.txt" 2> "$WORK_DIR/listener-error.txt"
bind_status=$?
set -e
if (( bind_status == 0 )); then
    log "unexpected: sandbox allowed a loopback bind; real HTTP/SSE host test is not implemented in this drill"
    log "WARNING: real listener test remains unverified"
else
    log "loopback TCP bind is blocked by the sandbox; real socket-level HTTP/SSE remains unverified"
fi

log "8/12 checking Caddy SSE site template and bootstrap without binding a port"
caddy_cmd validate --config "$CADDYFILE" || fail "Caddy drill config is invalid"
BOOTSTRAP_ROOT="$WORK_DIR/bootstrap-root"
mkdir -p "$BOOTSTRAP_ROOT"
(
    export PITPULSE_DEPLOY_ROOT="$BOOTSTRAP_ROOT"
    export PITPULSE_SYSTEMCTL=/usr/bin/true
    bash "$SCRIPT_DIR/bootstrap-vps.sh" >/dev/null
    bash "$SCRIPT_DIR/bootstrap-vps.sh" >/dev/null
)
grep -Fq "import $BOOTSTRAP_ROOT/etc/caddy/pitpulse.caddyfile" "$BOOTSTRAP_ROOT/etc/caddy/Caddyfile" ||
    fail "bootstrap did not import the PitPulse Caddy site template once"
[[ "$(rg -c '^import ' "$BOOTSTRAP_ROOT/etc/caddy/Caddyfile")" == "1" ]] ||
    fail "bootstrap Caddyfile import is not idempotent"
caddy adapt --config "$BOOTSTRAP_ROOT/etc/caddy/Caddyfile" --adapter caddyfile --pretty |
    jq -e '[.. | objects | .match? // empty | .[].host? // empty] | flatten | index("pitpulse.lestere.bond") != null' >/dev/null ||
    fail "bootstrap Caddyfile did not adapt to the expected host"
grep -q 'flush_interval -1' "$SCRIPT_DIR/pitpulse.caddyfile" || fail "Caddy SSE flush setting is missing"
grep -q 'request>headers>Authorization delete' "$SCRIPT_DIR/caddyfile.global.example" ||
    fail "Caddy access-log Authorization redaction is missing"

log "9/12 checking full deploy success, failed-deploy rollback and manual rollback"
PITPULSE_DEPLOY_ROOT="$WORK_DIR" PITPULSE_SYSTEMCTL=/usr/bin/true \
    PITPULSE_CADDY="$FAKE_CADDY" bash "$SCRIPT_DIR/bootstrap-vps.sh" >/dev/null
grep -Fq 'operator-owned config sentinel' "$PITPULSE_CONFIG_FILE" ||
    fail "bootstrap replaced the operator-owned config"
export F1_COMPANION_DATABASE_PATH
export F1_COMPANION_TOKEN

deploy_env=(
    "PITPULSE_DEPLOY_ROOT=$WORK_DIR"
    "PITPULSE_CURL=$FAKE_CURL"
    "PITPULSE_SYSTEMCTL=$FAKE_SYSTEMCTL"
    "PITPULSE_CADDY=$FAKE_CADDY"
    "PITPULSE_SKIP_BINARY_PREFLIGHT=1"
    "WORK_DIR=$WORK_DIR"
)
env "${deploy_env[@]}" bash "$SCRIPT_DIR/deploy-release.sh" "$ARCHIVE" > "$WORK_DIR/deploy-success.log" 2>&1 ||
    { cat "$WORK_DIR/deploy-success.log"; fail "full deploy-release drill failed"; }
[[ "$(resolve_path "$WORK_DIR/opt/pitpulse/current")" == "$(resolve_path "$WORK_DIR/opt/pitpulse/releases/$DRILL_VERSION")" ]] ||
    fail "full deploy did not select the new release"
grep -Fq 'operator-owned config sentinel' "$PITPULSE_CONFIG_FILE" ||
    fail "deploy replaced the operator-owned config"

BROKEN_CURL="$WORK_DIR/fake-curl-broken.py"
cat > "$BROKEN_CURL" <<'PY'
#!/usr/bin/env python3
import sys
if '-w' in sys.argv[1:]:
    print('500', end='')
else:
    print('{"status":"degraded","database":false}', end='')
PY
chmod 0700 "$BROKEN_CURL"
SECOND_VERSION="$(printf '%040d' 2 | tr '0' a)"
SECOND_STAGE="$WORK_DIR/artifact-stage-2"
mkdir -p "$SECOND_STAGE"
cp "$FAKE_CURL" "$SECOND_STAGE/pitpulse-server"
printf '%s\n' "$SECOND_VERSION" > "$SECOND_STAGE/VERSION"
printf '%s\n' placeholder > "$SECOND_STAGE/ldd.txt"
for template in config.production.toml pitpulse-server.service pitpulse.caddyfile; do
    cp "$SCRIPT_DIR/$template" "$SECOND_STAGE/$template"
done
(
    cd "$SECOND_STAGE"
    sha256sum pitpulse-server VERSION ldd.txt config.production.toml \
        pitpulse-server.service pitpulse.caddyfile > SHA256SUMS
)
SECOND_ARCHIVE="$WORK_DIR/pitpulse-server-drill-2.tar.gz"
tar -czf "$SECOND_ARCHIVE" -C "$SECOND_STAGE" \
    pitpulse-server VERSION SHA256SUMS ldd.txt \
    config.production.toml pitpulse-server.service pitpulse.caddyfile

if env "${deploy_env[@]/PITPULSE_CURL=$FAKE_CURL/PITPULSE_CURL=$BROKEN_CURL}" \
    bash "$SCRIPT_DIR/deploy-release.sh" "$SECOND_ARCHIVE" > "$WORK_DIR/deploy-failure.log" 2>&1; then
    fail "failed deploy unexpectedly reported success"
fi
[[ "$(resolve_path "$WORK_DIR/opt/pitpulse/current")" == "$(resolve_path "$WORK_DIR/opt/pitpulse/releases/$DRILL_VERSION")" ]] ||
    fail "failed deploy did not restore the previous release symlink"
# The broken curl remains injected during rollback, so the script intentionally
# stops the service. Restore the healthy responder for the manual rollback check.
env "${deploy_env[@]}" bash "$SCRIPT_DIR/rollback-release.sh" > "$WORK_DIR/rollback.log" 2>&1 ||
    { cat "$WORK_DIR/rollback.log"; fail "manual rollback drill failed"; }

log "10/12 checking secret redaction, forced-command contract and credential template"
if grep -Rqs "$TOKEN" "$SCRIPT_DIR"; then
    fail "a drill token was found in tracked deployment scripts"
fi
forced="$SCRIPT_DIR/pitpulse-deploy.example"
credentials="$SCRIPT_DIR/prepare-deploy-credentials.example.sh"
grep -Fq 'SSH_ORIGINAL_COMMAND' "$forced" || fail "forced-command wrapper does not parse SSH_ORIGINAL_COMMAND"
grep -Fq '^(put|deploy|cleanup)[[:space:]]([0-9a-f]{40})$' "$forced" ||
    fail "forced-command wrapper does not constrain all commands and SHAs"
grep -Fq 'cmp -s "$STAGING/unpacked/$name" "$HELPERS/$name"' "$forced" ||
    fail "forced-command wrapper does not verify helper copies"
grep -Fq 'actions/workflows/ci.yml/runs' "$forced" ||
    fail "forced-command wrapper lacks an independent CI run trust anchor"
grep -Fq 'sha256sum "$temp.payload"' "$forced" ||
    fail "forced-command wrapper does not hash the raw artifact ZIP"
grep -Fq 'unzip -Z1 "$temp.payload"' "$forced" ||
    fail "forced-command wrapper does not verify exact ZIP members"
grep -Fq '.conclusion == "success"' "$forced" ||
    fail "forced-command wrapper does not require a successful CI run"
grep -Fq 'sudo -n "$DEPLOY_LAUNCHER" "$sha"' "$forced" ||
    fail "forced-command wrapper does not use the fixed root launcher"
grep -Eq 'sudo[^|&;]*[[:space:]]+/usr/bin/env' "$forced" &&
    fail "forced-command wrapper still uses sudo env"
grep -Fq 'restrict,command=' "$credentials" || fail "credential template lacks restrict,command"
grep -Fq '^ssh-ed25519[[:space:]]' "$credentials" || fail "credential template lacks dedicated Ed25519 key validation"
grep -Fq 'authorized_keys' "$credentials" || fail "credential template lacks authorized_keys policy"
grep -Fq 'visudo -cf' "$credentials" || fail "credential template does not validate the sudoers policy"
if grep -RqsE '^-----BEGIN (OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----' "$SCRIPT_DIR"; then
    fail "a private key was found in deployment templates"
fi
legacy_key_name="id_$(printf 'ed25519')_103_231_58_220"
if grep -RqsF "$legacy_key_name" "$SCRIPT_DIR"; then
    fail "a general-purpose root key name was found in deployment templates"
fi

# Exercise the wrapper's parser with a fake sudo and the already checked-in
# helper copies. Deny arbitrary commands; accept only the three fixed commands.
FORCED_ROOT="$WORK_DIR/forced-root"
mkdir -p "$FORCED_ROOT/opt/pitpulse/releases.incoming" "$FORCED_ROOT/usr/local/lib/pitpulse" \
    "$FORCED_ROOT/var/tmp/pitpulse-deploy" "$FORCED_ROOT/bin"
cp "$SCRIPT_DIR/lib.sh" "$SCRIPT_DIR/deploy-release.sh" "$SCRIPT_DIR/rollback-release.sh" \
    "$FORCED_ROOT/usr/local/lib/pitpulse/"
cat > "$FORCED_ROOT/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$WORK_DIR/forced-sudo-args"
EOF
chmod 0755 "$FORCED_ROOT/bin/sudo"

# A curl-compatible public-API responder lets the drill exercise put without
# reaching the network. Only the exact successful CI run/artifact digest below
# is accepted; a failed run must be rejected.
cat > "$WORK_DIR/fake-github-api.py" <<'PY'
#!/usr/bin/env python3
import json
import os
import sys

url = sys.argv[-1]
sha = os.environ["DRILL_SHA"]
digest = os.environ["DRILL_ZIP_DIGEST"]
run = "42632042204"
failed_run = "42624865596"
if "/actions/workflows/ci.yml/runs?" in url:
    outcome = {"workflow_runs": [{
        "id": int(run), "name": "CI", "event": "push", "head_branch": "main",
        "head_sha": sha, "status": "completed", "conclusion": "success",
        "created_at": "2026-11-09T15:00:00Z"
    }, {
        "id": int(failed_run), "name": "CI", "event": "push", "head_branch": "main",
        "head_sha": sha, "status": "completed", "conclusion": "failure",
        "created_at": "2026-11-09T14:00:00Z"
    }]}
elif f"/actions/runs/{run}/jobs" in url:
    outcome = {"jobs": [{
        "name": "Server fmt / clippy / test / build",
        "status": "completed", "conclusion": "success"
    }]}
elif f"/actions/runs/{failed_run}/jobs" in url:
    outcome = {"jobs": [{
        "name": "Server fmt / clippy / test / build",
        "status": "completed", "conclusion": "failure"
    }]}
elif f"/actions/runs/{run}/artifacts" in url:
    outcome = {"artifacts": [{
        "name": "pitpulse-server-linux-x86_64-" + sha,
        "expired": False, "digest": "sha256:" + digest,
        "workflow_run": {"head_branch": "main", "head_sha": sha}
    }]}
elif f"/actions/runs/{failed_run}/artifacts" in url:
    outcome = {"artifacts": []}
else:
    sys.exit("unexpected fake GitHub API URL")
print(json.dumps(outcome))
PY
chmod 0755 "$WORK_DIR/fake-github-api.py"
cat > "$FORCED_ROOT/bin/curl" <<EOF
#!/usr/bin/env bash
exec python3 "$WORK_DIR/fake-github-api.py" "\$@"
EOF
chmod 0755 "$FORCED_ROOT/bin/curl"
FORCED_WRAPPER="$WORK_DIR/pitpulse-deploy-drill"
python3 -I - "$SCRIPT_DIR/pitpulse-deploy.example" "$FORCED_WRAPPER" "$FORCED_ROOT" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
root = sys.argv[3]
replacements = {
    "INCOMING=/opt/pitpulse/releases.incoming":
        f"INCOMING={root}/opt/pitpulse/releases.incoming",
    "STAGING=/var/tmp/pitpulse-deploy": f"STAGING={root}/var/tmp/pitpulse-deploy",
    "HELPERS=/usr/local/lib/pitpulse": f"HELPERS={root}/usr/local/lib/pitpulse",
    "DEPLOY_LAUNCHER=/usr/local/sbin/pitpulse-deploy-release":
        f"DEPLOY_LAUNCHER={root}/bin/pitpulse-deploy-release",
}
for old, new in replacements.items():
    assert source.count(old) == 1, old
    source = source.replace(old, new)
source = source.replace(
    "set -Eeuo pipefail\n",
    f"set -Eeuo pipefail\nPATH={root}/bin:$PATH\n",
    1,
)
pathlib.Path(sys.argv[2]).write_text(source)
PY
chmod 0700 "$FORCED_WRAPPER"
if SSH_ORIGINAL_COMMAND='uname -a' "$FORCED_WRAPPER" >/dev/null 2>&1; then
    fail "forced-command wrapper accepted an arbitrary shell command"
fi
if SSH_ORIGINAL_COMMAND='deploy not-a-sha' "$FORCED_WRAPPER" >/dev/null 2>&1; then
    fail "forced-command wrapper accepted an invalid SHA"
fi
CLEAN_SHA=0123456789abcdef0123456789abcdef01234567
SSH_ORIGINAL_COMMAND="cleanup $CLEAN_SHA" "$FORCED_WRAPPER" >/dev/null ||
    fail "SHA-scoped forced-command cleanup failed"
if SSH_ORIGINAL_COMMAND=cleanup "$FORCED_WRAPPER" >/dev/null 2>&1; then
    fail "forced-command wrapper accepted an unscoped cleanup"
fi

log "11/12 checking raw GitHub artifact ZIP trust chain and forced-command denial"
ZIP_SHA=0123456789abcdef0123456789abcdef01234567
ZIP_NAME="pitpulse-server-linux-x86_64-${ZIP_SHA}.tar.gz"
ZIP_STAGE="$WORK_DIR/zip-stage"
ZIP_TAR_STAGE="$WORK_DIR/zip-tar-stage"
ZIP_FILE="$WORK_DIR/github-artifact.zip"
INCOMING="$FORCED_ROOT/opt/pitpulse/releases.incoming"
mkdir -p "$ZIP_STAGE" "$ZIP_TAR_STAGE"
cp -R "$STAGE/." "$ZIP_TAR_STAGE/"
printf '%s\n' "$ZIP_SHA" > "$ZIP_TAR_STAGE/VERSION"
(
    cd "$ZIP_TAR_STAGE"
    sha256sum pitpulse-server VERSION ldd.txt config.production.toml \
        pitpulse-server.service pitpulse.caddyfile > SHA256SUMS
    tar -czf "$ZIP_STAGE/$ZIP_NAME" \
        pitpulse-server VERSION SHA256SUMS ldd.txt \
        config.production.toml pitpulse-server.service pitpulse.caddyfile
)
(
    cd "$ZIP_STAGE"
    sha256sum "$ZIP_NAME" > "$ZIP_NAME.sha256"
    zip -q -X -D "$ZIP_FILE" "$ZIP_NAME" "$ZIP_NAME.sha256"
)
ZIP_DIGEST="$(sha256sum "$ZIP_FILE" | cut -d' ' -f1)"
DRILL_SHA="$ZIP_SHA" DRILL_ZIP_DIGEST="$ZIP_DIGEST" \
SSH_ORIGINAL_COMMAND="put $ZIP_SHA" "$FORCED_WRAPPER" \
    < <(printf '%s %s\n' "$ZIP_SHA" "$ZIP_DIGEST" | openssl base64 -A; printf '\n'; cat "$ZIP_FILE") \
    > "$WORK_DIR/forced-put.log" 2>&1 ||
    { cat "$WORK_DIR/forced-put.log"; fail "valid raw artifact ZIP was rejected"; }
[[ -f "$INCOMING/${ZIP_SHA}.tar.gz" ]] || fail "forced command did not install the approved archive"
cmp -s "$INCOMING/${ZIP_SHA}.tar.gz" "$ZIP_STAGE/$ZIP_NAME" ||
    fail "installed archive differs from the approved ZIP member"
if DRILL_SHA="$ZIP_SHA" DRILL_ZIP_DIGEST="$ZIP_DIGEST" \
    SSH_ORIGINAL_COMMAND="put $ZIP_SHA" "$FORCED_WRAPPER" \
    < <(printf '%s %s\n' "$ZIP_SHA" "$(printf '%064d' 0)" | openssl base64 -A; printf '\n'; cat "$ZIP_FILE") \
    >/dev/null 2>&1; then
    fail "forced command accepted a mismatched ZIP digest request"
fi
if DRILL_SHA="$ZIP_SHA" DRILL_ZIP_DIGEST="$(printf '%064d' 1)" \
    SSH_ORIGINAL_COMMAND="put $ZIP_SHA" "$FORCED_WRAPPER" \
    < <(printf '%s %s\n' "$ZIP_SHA" "$ZIP_DIGEST" | openssl base64 -A; printf '\n'; cat "$ZIP_FILE") \
    >/dev/null 2>&1; then
    fail "forced command accepted a ZIP digest absent from published CI artifacts"
fi

log "12/12 checking repeated same-SHA deploy and root-owned database restore"
env "${deploy_env[@]}" bash "$SCRIPT_DIR/deploy-release.sh" "$ARCHIVE" > "$WORK_DIR/deploy-repeat.log" 2>&1 ||
    { cat "$WORK_DIR/deploy-repeat.log"; fail "same-SHA re-deploy failed"; }
[[ -f "$WORK_DIR/opt/pitpulse/releases/$DRILL_VERSION/ldd.txt" ]] ||
    fail "materialized release is missing all SHA256SUMS inputs"
(
    cd "$WORK_DIR/opt/pitpulse/releases/$DRILL_VERSION"
    sha256sum -c SHA256SUMS
) >/dev/null || fail "materialized release checksums are incomplete"
restore_db_from_backup "$SNAPSHOT" "$PITPULSE_DB_PATH" || fail "hardened database restore failed"
[[ "$(stat -c '%U' "$PITPULSE_DB_PATH" 2>/dev/null || stat -f '%Su' "$PITPULSE_DB_PATH")" == "$(stat -c '%U' "$WORK_DIR" 2>/dev/null || stat -f '%Su' "$WORK_DIR")" ]] ||
    fail "restored database has the wrong owner"
[[ ! -L "$PITPULSE_DB_PATH" ]] || fail "restored database became a symlink"

log "deployment helper drill passed (socket-level listener unverified in sandbox)"
log "drill evidence: $WORK_DIR"
