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
