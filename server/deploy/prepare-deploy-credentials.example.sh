#!/usr/bin/env bash
# EXAMPLE only: prepare the dedicated CI deploy account, forced-command wrapper,
# least-privilege sudo policy and root-owned helper copies on the VPS.
#
# This is a command checklist/template, not an installer. Run it only after the
# user explicitly authorizes production credential generation/installation and
# VPS authorized_keys/sudoers changes. It never reads, copies, or reuses an
# existing general-purpose SSH key. Generate the new key pair outside Git and
# supply its PUBLIC key via PITPULSE_DEPLOY_PUBLIC_KEY_FILE. Keep the private
# key only in the GitHub Environment `production` secret VPS_SSH_KEY.
#
# Required environment:
#   PITPULSE_DEPLOY_PUBLIC_KEY_FILE=/absolute/path/to/new-key.pub
# Optional environment:
#   PITPULSE_DEPLOY_USER=pitpulse-deploy
#   PITPULSE_REPO_DEPLOY_DIR=/absolute/path/to/PitPulse/server/deploy
#
# Run on the VPS as root with the reviewed repository checked out outside this
# script's directory. Then store these four values in the GitHub Environment
# `production` secrets (never in Git, artifacts, logs or task reports):
#   VPS_HOST, VPS_USER, VPS_KNOWN_HOSTS, VPS_SSH_KEY
#
# Obtain VPS_KNOWN_HOSTS with `ssh-keyscan -t ed25519 <host>` from a trusted
# network and verify its fingerprint out of band. VPS_USER is the dedicated
# non-root account created below, never root.

set -Eeuo pipefail

fail() {
    printf '[pitpulse] ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || fail "run as root on the VPS"
}

require_commands() {
    local name
    for name in "$@"; do
        command -v "$name" >/dev/null 2>&1 || fail "missing $name"
    done
}

require_root
require_commands install useradd usermod ssh-keygen grep sha256sum cmp visudo chown chmod

deploy_user="${PITPULSE_DEPLOY_USER:-pitpulse-deploy}"
public_key_file="${PITPULSE_DEPLOY_PUBLIC_KEY_FILE:-}"
deploy_dir="${PITPULSE_REPO_DEPLOY_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)}"
wrapper_src="$deploy_dir/pitpulse-deploy.example"
launcher_src="$deploy_dir/pitpulse-deploy-release.example"
helpers_src=("$deploy_dir/lib.sh" "$deploy_dir/deploy-release.sh" "$deploy_dir/rollback-release.sh")
wrapper_dst=/usr/local/sbin/pitpulse-deploy
launcher_dst=/usr/local/sbin/pitpulse-deploy-release
helpers_dir=/usr/local/lib/pitpulse
incoming_dir=/opt/pitpulse/releases.incoming
staging_dir=/var/tmp/pitpulse-deploy
sudoers_file=/etc/sudoers.d/pitpulse-deploy
sudoers_tmp="$(mktemp /etc/sudoers.d/.pitpulse-deploy.XXXXXX)"
authorized_keys_dir="/home/$deploy_user/.ssh"
trap 'rm -f "$sudoers_tmp"' EXIT

[[ -n "$public_key_file" && -f "$public_key_file" && ! -L "$public_key_file" ]] ||
    fail "set PITPULSE_DEPLOY_PUBLIC_KEY_FILE to the NEW public key file"
[[ "$deploy_user" =~ ^[a-z_][a-z0-9_-]*$ ]] || fail "invalid deploy account name"
[[ "$deploy_user" != root && "$deploy_user" != pitpulse ]] || fail "deploy account must be dedicated and non-root"
for src in "$wrapper_src" "$launcher_src" "${helpers_src[@]}"; do
    [[ -f "$src" && ! -L "$src" ]] || fail "missing reviewed template: $src"
done

# Validate that this is a single, new Ed25519 public key. No private key or
# general-purpose root key is read, installed, or copied.
public_key="$(ssh-keygen -l -f "$public_key_file" >/dev/null 2>&1 &&
    grep -Ev '^[[:space:]]*(#|$)' "$public_key_file")" || fail "public key is not a valid SSH key file"
[[ "$(printf '%s\n' "$public_key" | wc -l | tr -d ' ')" == "1" ]] || fail "supply exactly one public key"
[[ "$public_key" =~ ^ssh-ed25519[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] ||
    fail "supply a dedicated ssh-ed25519 public key"

if ! id -u "$deploy_user" >/dev/null 2>&1; then
    useradd --create-home --shell /usr/sbin/nologin "$deploy_user"
fi
usermod --lock "$deploy_user" >/dev/null 2>&1 || true

install -d -m 0700 "$authorized_keys_dir"
install -d -m 0755 "$incoming_dir"
install -d -m 0700 "$staging_dir"
install -d -m 0755 "$helpers_dir"
install -m 0755 "$wrapper_src" "$wrapper_dst"
install -m 0755 "$launcher_src" "$launcher_dst"
for src in "${helpers_src[@]}"; do
    install -m 0755 "$src" "$helpers_dir/$(basename "$src")"
done
chown -R "$deploy_user:$deploy_user" "$incoming_dir" "$staging_dir"

# Root owns the home/.ssh/authorized_keys path so the deploy account cannot
# replace its own forced command even if an archive path check regresses.
# `restrict` disables forwarding, PTY allocation and user rc.
authorized_keys_line="restrict,command=\"$wrapper_dst\" $public_key"
install -m 0600 /dev/null "$authorized_keys_dir/authorized_keys"
printf '%s\n' "$authorized_keys_line" > "$authorized_keys_dir/authorized_keys"
chown -R root:root "/home/$deploy_user" "$authorized_keys_dir" "$authorized_keys_dir/authorized_keys"
chmod 0700 "/home/$deploy_user" "$authorized_keys_dir"
chmod 0600 "$authorized_keys_dir/authorized_keys"

# One fixed root-owned launcher is allowed through sudo. No `/usr/bin/env`,
# shell wildcards, CI-controlled environment variables, or helper paths are in
# the rule. Validate the temporary file BEFORE installing it so a bad policy
# cannot disable sudo on the VPS.
cat > "$sudoers_tmp" <<EOF
$deploy_user ALL=(root) NOPASSWD: $launcher_dst
EOF
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp" >/dev/null || fail "sudoers policy failed validation"
install -m 0440 "$sudoers_tmp" "$sudoers_file"

printf '[pitpulse] prepared dedicated account %s and forced command %s\n' "$deploy_user" "$wrapper_dst"
printf '[pitpulse] private key stays OUTSIDE the VPS and repository; add it only to GitHub Environment production secret VPS_SSH_KEY\n'
printf '[pitpulse] verify host key fingerprint out of band, then set VPS_HOST/VPS_USER/VPS_KNOWN_HOSTS/VPS_SSH_KEY\n'
printf '[pitpulse] test denials before any deploy: ssh <alias> "uname -a" must be rejected; ssh <alias> "cleanup <sha>" must succeed\n'
