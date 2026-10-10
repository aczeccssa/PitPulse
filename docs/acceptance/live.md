# T13 本地 Live 回放验收

**日期：** 2026-10-10。回放只用于验证本地链路，不代表真实 F1 上游字段或赛期时效已通过。

## 回放链路

`server/examples/live_replay.rs` 显式关闭上游 provider，读取仓库 fixture 并标记 `sourceMode=replay`。它只监听本机默认端口，数据库位于系统临时目录，不改写仓库数据。验收时：

- `GET /api/v1/live/snapshot` 返回 `sourceMode=replay`、`sourceStatus=connected`、Session、圈数及合成车手快照。
- `GET /api/v1/live/stream` 首个 SSE 事件立即为 `event: snapshot`，包含完整快照；回放每 5 秒更新圈数。
- 本地 reducer 将 fixture 投影进 REST 和 SSE。服务不在上游失败时自动切换到回放。

可重复启动方式：

```sh
cargo run --manifest-path server/Cargo.toml --example live_replay
curl -sS http://127.0.0.1:38701/api/v1/live/snapshot
curl -N --max-time 2 http://127.0.0.1:38701/api/v1/live/stream
```

## 自动化证据

- Rust：`cargo fmt --manifest-path server/Cargo.toml -- --check`、`cargo test --manifest-path server/Cargo.toml`（60 项通过）及严格 Clippy 通过。覆盖索引 patch、嵌套合并、null、Session 隔离、心跳不刷新数据时间、消息大小限制、stale / disconnected、watch 最新值、SSE 首帧与立即状态事件。
- macOS：`xcodebuild build` 与 `xcodebuild test -parallel-testing-enabled NO` 通过（60 项）。覆盖增量 SSE parser 的 UTF-8 拆包、CRLF、多行 data、注释、坏 UTF-8恢复、连接 generation、乱序版本及 Retry-After 秒数和 HTTP 日期。
- 专用 UI 验收用例位于 `macos/UITests/MenuBarAcceptanceTests.swift`，用 `F1CompanionLiveAcceptance` scheme 运行。当前双屏布局下 macOS 把状态栏项报告在不可命中的坐标；用例因此显式 skip。它没有打开 Popup，也没有产生回放 / 已断开菜单截图。
- 一次默认并行 Xcode 测试运行在既有 `AppModelTests.testTransientFailureBackoffAdvancesBeforeRecovering()` 时序断言失败；该用例单独运行及串行全套运行通过。竞争原因未确认，因此只记录重跑结果，不声称已修复该测试的时序敏感性。

## 未完成边界

T13 仍待验收：需要在状态栏项可点击的桌面上打开实际 Menu Bar Popup，确认回放与断开两种文字并保存截图。上游探测没有收到实时 `feed`，因此也没有真实字段或赛期延迟证据。高流量 `Position.z` / `CarData.z` 压缩遥测未订阅，当前没有压缩解码器；腐坏压缩帧行为仍未验收。不得将这些边界表述为真实 Live 已验证。
