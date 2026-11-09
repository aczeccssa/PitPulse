# PitPulse Server

Rust/Tokio/Axum single-process data service. This repository currently contains the Phase 1 infrastructure skeleton:

- Configuration loading from TOML + environment.
- SQLite schema, migrations, WAL, and blocking-task-backed storage.
- Versioned REST endpoints, Bearer token middleware, and health checks.
- Live snapshot state with `tokio::sync::watch` and initial SSE stream.
- Provider adapter boundaries for Jolpica, OpenF1, and F1 Live SignalR.
- systemd deployment example.

Upstream APIs are intentionally not called during this scaffold; Phase 0 recorded fixtures must define their normalization contracts first.

## Development

```sh
cargo fmt --manifest-path server/Cargo.toml -- --check
cargo clippy --manifest-path server/Cargo.toml -- -D warnings
cargo test --manifest-path server/Cargo.toml
cargo build --release --manifest-path server/Cargo.toml
```

## Local run

```sh
F1_COMPANION_DATABASE_PATH=/tmp/pitpulse.sqlite cargo run --manifest-path server/Cargo.toml
curl http://127.0.0.1:38701/api/v1/health
```

To require authentication:

```sh
F1_COMPANION_TOKEN=local-token F1_COMPANION_REQUIRE_TOKEN=true \
F1_COMPANION_DATABASE_PATH=/tmp/pitpulse.sqlite \
  cargo run --manifest-path server/Cargo.toml
```


## Mapbox、天气、雷达与 Radio

在服务运行环境设置 `F1_COMPANION_MAPBOX_PUBLIC_TOKEN`（公开只读 `pk.` token），然后重启服务。该值仅通过现有鉴权保护的 `/api/v1/maps/config` 提供，不写入 TOML、源码或任务报告；`sk.` token 被拒绝。没有 token 时地点数据、计时、天气与消息仍可使用，地图显示缺失配置状态。

地图渲染资源是客户端直连 Mapbox 官方服务的明确例外；PitPulse Bearer 不进入网页。地图及赛事信息接口、来源、stale 和二进制响应约定见 [数据契约](../docs/data-contract.md)。赛道数据来源、许可证和逐年份校准见 [赛道说明](resources/circuits/README.md)。专项检查与真实验收边界见 [验收记录](../docs/acceptance/live-map.md)。

## Bind address

默认监听 `127.0.0.1:38701`；通过 `Run Server`（Taskdeck/`scripts/run-server.py`）启动时默认监听 `0.0.0.0:38701`，便于 LAN 上的 iOS / 其他设备访问。可用 `F1_COMPANION_BIND=<ip:port>` 或 `~/Library/Application Support/PitPulse/server/environment.json` 覆盖。对外网暴露时请启用 `F1_COMPANION_REQUIRE_TOKEN` 并配置 `F1_COMPANION_TOKEN`。

## VPS release and rollback

The repository contains keyless templates only. Before the first deploy, generate a dedicated Ed25519 key pair outside Git, prepare the non-root account and `restrict,command=...` forced command with `server/deploy/prepare-deploy-credentials.example.sh`, and place `VPS_HOST`, `VPS_USER`, `VPS_KNOWN_HOSTS`, `VPS_SSH_KEY` only in GitHub Environment `production` secrets. Never reuse a general-purpose root SSH key or commit key/token contents. A real end-to-end publish requires a reviewed commit/push to `main`, a successful CI artifact, the `production` environment approval, and public HTTPS/SSE acceptance.

`.github/workflows/ci.yml` builds a fixed-ABI Ubuntu 24.04 x86-64 release archive with `VERSION`, `ldd.txt` and `SHA256SUMS`; `.github/workflows/deploy.yml` verifies and deploys an explicitly selected CI artifact only after the `production` environment is approved. `server/deploy/` contains keyless systemd, TOML, Caddy and environment templates plus `bootstrap-vps.sh`, `deploy-release.sh`, `rollback-release.sh` and `test-deploy-scripts.sh`.

Production state lives outside Git: `/etc/pitpulse/environment` (mode `0600`, high-entropy Bearer token), `/var/lib/pitpulse/pitpulse.sqlite`, `/var/backups/pitpulse/`, and `/opt/pitpulse/releases/<sha>/`. Deploy stops the single SQLite writer, takes an online backup and records `user_version`, atomically switches `current`, then checks unauthenticated 401, authenticated 200 and SSE first event locally and (when configured) over public HTTPS. Failure restores the previous binary and database. Manual rollback uses `rollback-release.sh`; set `PITPULSE_RESTORE_DB=1` and a matching backup only when a forward migration must be undone.

Cold start leaves the VPS database to migrations and the scheduler; the local database is never copied. The VPS service binds `127.0.0.1:38701` behind Caddy TLS; `flush_interval -1` preserves SSE streaming. Run the isolated drill with:

```sh
bash server/deploy/test-deploy-scripts.sh
```

See [deployment acceptance](../docs/acceptance/deployment.md) for the user-added DNS A record, dedicated SSH key/forced-command requirement, unverified items and the authorization checklist. No DNS, VPS Caddy/systemd, production secret or production deployment has been changed by these repository files.
