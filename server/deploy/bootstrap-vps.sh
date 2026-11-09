#!/usr/bin/env bash
# Idempotent VPS bootstrap. It prepares local files and templates only.
# DNS, production secrets, Caddy reload, systemd enablement and service start
# remain separate, explicitly authorized operations.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

require_commands install cp chmod mkdir id sha256sum sqlite3 caddy
if [[ -z "${PITPULSE_SYSTEMCTL:-}" ]]; then
    require_commands systemctl
fi
require_root

if [[ -z "$PITPULSE_DEPLOY_ROOT" ]]; then
    if ! id -u pitpulse >/dev/null 2>&1; then
        useradd --system --create-home --home-dir "$PITPULSE_LIB_DIR" --shell /usr/sbin/nologin pitpulse
    fi
fi

mkdir -p \
    "$PITPULSE_OPT_DIR/releases" \
    "$PITPULSE_OPT_DIR/releases.incoming" \
    "$PITPULSE_ETC_DIR" \
    "$PITPULSE_LIB_DIR" \
    "$PITPULSE_BACKUP_DIR" \
    "$PITPULSE_SYSTEMD_DIR" \
    "$PITPULSE_CADDY_DIR" \
    "$PITPULSE_DEPLOY_SCRIPT_DIR"

chmod 0755 "$PITPULSE_OPT_DIR" "$PITPULSE_OPT_DIR/releases" "$PITPULSE_OPT_DIR/releases.incoming" "$PITPULSE_ETC_DIR"
chmod 0700 "$PITPULSE_LIB_DIR" "$PITPULSE_BACKUP_DIR"
if [[ -z "$PITPULSE_DEPLOY_ROOT" ]]; then
    chown -R pitpulse:pitpulse "$PITPULSE_LIB_DIR"
fi

if [[ ! -f "$PITPULSE_CONFIG_FILE" ]]; then
    install -m 0644 "$SCRIPT_DIR/config.production.toml" "$PITPULSE_CONFIG_FILE"
else
    cmp -s "$SCRIPT_DIR/config.production.toml" "$PITPULSE_CONFIG_FILE" ||
        fail "existing $PITPULSE_CONFIG_FILE differs from the reviewed template; resolve manually"
fi
if [[ ! -f "$PITPULSE_ENV_FILE" ]]; then
    install -m 0600 "$SCRIPT_DIR/environment.production.example" "$PITPULSE_ENV_FILE"
fi
if [[ ! -f "$PITPULSE_DEPLOY_SETTINGS_FILE" ]]; then
    install -m 0644 "$SCRIPT_DIR/deploy.env.production.example" "$PITPULSE_DEPLOY_SETTINGS_FILE"
fi
install -m 0644 "$SCRIPT_DIR/pitpulse-server.service" "$PITPULSE_SYSTEMD_DIR/$PITPULSE_SERVICE_NAME.service"
install -m 0644 "$SCRIPT_DIR/pitpulse.caddyfile" "$PITPULSE_CADDY_SNIPPET"
install -m 0755 "$SCRIPT_DIR/lib.sh" "$PITPULSE_DEPLOY_SCRIPT_DIR/lib.sh"
install -m 0755 "$SCRIPT_DIR/deploy-release.sh" "$PITPULSE_DEPLOY_SCRIPT_DIR/deploy-release.sh"
install -m 0755 "$SCRIPT_DIR/rollback-release.sh" "$PITPULSE_DEPLOY_SCRIPT_DIR/rollback-release.sh"

if [[ ! -f "$PITPULSE_CADDY_FILE" ]]; then
    install -m 0644 "$SCRIPT_DIR/caddyfile.global.example" "$PITPULSE_CADDY_FILE"
fi

import_line="import $PITPULSE_CADDY_SNIPPET"
if ! grep -Eq "^[[:space:]]*import[[:space:]]+${PITPULSE_CADDY_SNIPPET//\//\\/}[[:space:]]*$" "$PITPULSE_CADDY_FILE"; then
    cat >> "$PITPULSE_CADDY_FILE" <<EOF

# Added by PitPulse bootstrap; reload and certificate issuance require explicit authorization.
$import_line
EOF
fi
[[ "$(grep -Ec "^[[:space:]]*import[[:space:]]+${PITPULSE_CADDY_SNIPPET//\//\\/}[[:space:]]*$" "$PITPULSE_CADDY_FILE")" == "1" ]] ||
    fail "Caddyfile has duplicate PitPulse imports; resolve manually"
grep -Eq '^\([[:space:]]*access_log[[:space:]]*\)[[:space:]]*\{' "$PITPULSE_CADDY_FILE" ||
    fail "main Caddyfile does not define the shared (access_log) snippet"
caddy_cmd validate --config "$PITPULSE_CADDY_FILE" >/dev/null ||
    fail "Caddy validation failed after bootstrap; no Caddy reload was attempted"

if [[ -z "$PITPULSE_DEPLOY_ROOT" ]]; then
    systemctl_cmd daemon-reload >/dev/null
fi

log "prepared PitPulse runtime directories, systemd unit, config and Caddy template"
log "install $PITPULSE_ENV_FILE with mode 0600 and real values before enabling the service"
log "bootstrap intentionally did not reload Caddy, enable/start systemd, add DNS, or inject secrets"
