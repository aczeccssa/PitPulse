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


## Historical season import

Run the server executable with the same database configuration as the service. The range is inclusive. The command also accepts a single year.

```sh
pitpulse-server backfill --season 2021..2026 > coverage.jsonl
```

Each JSON line reports the season, round, session, stored row count, quality and any gap reason. A season-level failure produces a diagnostic line and a nonzero exit after the other seasons have run. Add `--resume` to skip stored classifications with at least 20 rows. Omit it to refresh official corrections. The 2021 and 2022 imports use Jolpica alone. Sprint qualifying appears only when the source schedules a separate session.

## 网页首页

服务在 `/` 提供一个只读仪表盘，是自托管 VPS 部署后浏览器直接打开的入口，也支持添加到 iOS 主屏幕。使用哈希路由在五个视图间切换，刷新和直接打开链接都不会请求服务端路由：

| 路由 | 内容 |
| --- | --- |
| `#/overview` | 比赛进行中显示实时计时与圈数、赛道状态；没有比赛时显示下一场会话倒计时与最近一站领奖台。右侧为车手积分榜前八与实时天气 |
| `#/live` | 完整实时计时表，以及“进行中 / 已结束 / 连接中断 / 当前无比赛”阶段横幅；无比赛时显示下一场和最近一站赛果 |
| `#/calendar` | 月历视图：月份条、周一到周日的日期格显示分站日期与状态，点日期筛选右侧当月/当日赛事；`全年` 切换为整季列表。标注已结束、下一站、进行中、已取消，点击进入该站赛果 |
| `#/standings` | 车手 / 车队积分榜切换，含积分条、胜场 |
| `#/results/<meetingId>/<sessionType>` | 分站与排位/正赛/冲刺会话切换，正赛显示成绩、圈数、积分，排位显示 Q1–Q3 |

- 启用 `F1_COMPANION_REQUIRE_TOKEN` 时，仪表盘作为服务的一部分同样受保护：直接访问 `/` 只得到 401 说明页，不会下发页面壳或脚本。运维用 `https://<host>/?token=<F1_COMPANION_TOKEN>` 打开一次，服务端校验后签发 HttpOnly、SameSite=Lax 的 `pitpulse_web` 会话 Cookie 并 303 跳回 `/`（Lax 而非 Strict：从其他应用打开链接时，Strict Cookie 不会随跳转回 `/` 发送）；该 Cookie 由令牌经 HMAC-SHA256 派生，与 Bearer 令牌不同值，只允许 GET/HEAD，即使被复制也无法执行写操作。页面没有令牌输入框，令牌不进入脚本、`localStorage` 或 URL 历史。
- 所有数据仍走受保护的 `/api/v1/*`：浏览器会话可读，Bearer 令牌保持完整权限（包括 `POST /api/v1/refresh`）。轮换 `F1_COMPANION_TOKEN` 会使已签发的会话 Cookie 全部失效，需要重新打开访问链接。
- 图标与 favicon 仍公开：它们不含赛事数据，且浏览器和系统会在不带凭据的情况下请求。manifest、`/app.css`、`/app.js` 与会话一起受保护。
- 访问链接把令牌放在查询串里，反代访问日志必须删除 `token` 查询参数（`server/deploy/caddyfile.global.example` 已包含 `request>uri query { delete token }`，现有 VPS 的 `(access_log)` 片段需同样加上）。部署脚本只在 `127.0.0.1` 上执行一次 `?token=` 交换，公开 HTTPS 检查复用该会话 Cookie，不把原始令牌发到 Caddy。
- 实时更新使用 `/api/v1/live/stream`；`EventSource` 无法附加请求头，因此页面用 `fetch` 读取同一 SSE 流，断线后指数退避重连并回落到 `/api/v1/live/snapshot` 轮询。数据源断开或过期时，计时区域显示对应的中断或过期信息，不伪造实时值。
- 上游在赛后仍可能持续推送最后一场的快照，回放数据也可能是几天前的场次。页面以赛历中该会话的结束时间为准：结束超过 3 小时的快照（无论其状态写的是进行中还是已结束）按“当前没有进行中的比赛”展示，只给出最近赛果，不把旧计时当成实时数据；处于赛历时间窗内的会话正常显示实时计时。
- 反代需保持流式响应不缓冲；仓库内的 Caddy 配置已设置 `flush_interval -1`。
- 桌面端采用可展开图标侧栏、全宽数据工作区；赛果页显示所选会话前三名摘要。深浅主题始终跟随系统并响应系统外观变化，不提供手动主题切换。
- 源文件在 `server/resources/web/`，由 `include_str!`/`include_bytes!` 嵌入二进制，部署仍是单个可执行文件。

## Mapbox、天气、雷达与 Radio

在服务运行环境设置 `F1_COMPANION_MAPBOX_PUBLIC_TOKEN`（公开只读 `pk.` token），然后重启服务。该值仅通过现有鉴权保护的 `/api/v1/maps/config` 提供，不写入 TOML、源码或任务报告；`sk.` token 被拒绝。没有 token 时地点数据、计时、天气与消息仍可使用，地图显示缺失配置状态。

地图渲染资源是客户端直连 Mapbox 官方服务的明确例外；PitPulse Bearer 不进入网页。地图及赛事信息接口、来源、stale 和二进制响应约定见 [数据契约](../docs/data-contract.md)。赛道数据来源、许可证和逐年份校准见 [赛道说明](resources/circuits/README.md)。专项检查与真实验收边界见 [验收记录](../docs/acceptance/live-map.md)。

## Bind address

默认监听 `127.0.0.1:38701`；通过 `Run Server`（Taskdeck/`scripts/run-server.py`）启动时默认监听 `0.0.0.0:38701`，便于 LAN 上的 iOS / 其他设备访问。可用 `F1_COMPANION_BIND=<ip:port>` 或 `~/Library/Application Support/PitPulse/server/environment.json` 覆盖。对外网暴露时请启用 `F1_COMPANION_REQUIRE_TOKEN` 并配置 `F1_COMPANION_TOKEN`。

## VPS release and rollback

The repository contains keyless templates only. Before the first deploy, generate a dedicated Ed25519 key pair outside Git, prepare the non-root account and `restrict,command=...` forced command with `server/deploy/prepare-deploy-credentials.example.sh`, and place `VPS_HOST`, `VPS_USER`, `VPS_KNOWN_HOSTS`, `VPS_SSH_KEY` only in GitHub Environment `production` secrets. Never reuse a general-purpose root SSH key or commit key/token contents. A real end-to-end publish requires a reviewed commit/push to `main`, a successful CI artifact, the `production` environment approval, and public HTTPS/SSE acceptance.

`.github/workflows/ci.yml` builds a fixed-ABI Ubuntu 24.04 x86-64 release archive with `VERSION`, `ldd.txt` and `SHA256SUMS`, and smoke-tests the built binary in the same job: `/` must answer 401 without a session, the `?token=` access link must issue the session cookie, the shell and its assets must answer 200 with that cookie while `POST /api/v1/refresh` stays 401 for it and `/api/v1/health` stays 401 without any credential and answers 200 with the bearer token; `.github/workflows/deploy.yml` verifies and deploys an explicitly selected CI artifact only after the `production` environment is approved. `server/deploy/` contains keyless systemd, TOML, Caddy and environment templates plus `bootstrap-vps.sh`, `deploy-release.sh`, `rollback-release.sh` and `test-deploy-scripts.sh`.

Production state lives outside Git: `/etc/pitpulse/environment` (mode `0600`, high-entropy Bearer token), `/etc/pitpulse/config.toml` (operator-owned feature flags), `/var/lib/pitpulse/pitpulse.sqlite`, `/var/backups/pitpulse/`, and `/opt/pitpulse/releases/<sha>/`. Bootstrap installs the reviewed config template only when the file is absent; an existing config is preserved, and `deploy-release.sh` never writes it. The `config.production.toml` inside a release is provenance, not the active config. Deploy stops the single SQLite writer, takes an online backup and records `user_version`, atomically switches `current`, then checks unauthenticated 401, authenticated 200, the dashboard shell (refused without a session, served with the `?token=` cookie along with `/app.css` and `/app.js`) and the SSE first event locally and over public HTTPS. Failure restores the previous binary and database. Manual rollback uses `rollback-release.sh`; set `PITPULSE_RESTORE_DB=1` and a matching backup only when a forward migration must be undone.

Cold start leaves the VPS database to migrations and the scheduler; the local database is never copied. The VPS service binds `127.0.0.1:38701` behind Caddy TLS; `flush_interval -1` preserves SSE streaming. Run the isolated drill with:

```sh
bash server/deploy/test-deploy-scripts.sh
```

See [deployment acceptance](../docs/acceptance/deployment.md) for the user-added DNS A record, dedicated SSH key/forced-command requirement, unverified items and the authorization checklist. The repository files contain no production secret and do not copy a local database. The first deployment is a cold start and keeps F1 Live disabled until an approved upstream token is installed. VPS Caddy/systemd, the production API token, and release switching are performed only by the approved operator workflow outside these files.
