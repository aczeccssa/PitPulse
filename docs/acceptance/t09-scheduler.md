# T09 自动调度与结果修订验收

验收日期：2026-10-09。范围：Tokio 统一调度、Provider 单次请求、SQLite 持久重试状态、稳定 revision 和 Mac REST 刷新。调度验收使用注入时钟和本地 mock，不等待真实六小时。

## 调度与失败恢复

- 启动时不再单独同步 Provider；统一 scheduler 每 30 秒检查持久化截止时间。赛历和 WDC/WCC 默认 6 小时，24 小时内 Session 赛历核对 30 分钟一次。
- 对当前赛季扫描所有应探测 Session，跳过取消场次。无明确结束时间时，FP / 排位 / Sprint 使用 1 小时、Race 使用 2 小时估算，并记 `estimated_end` 探测依据；估算只触发读取，不改 Session 状态或宣布成绩 final。
- Session 结束后立即探测；空结果按 2 / 4 / 5 分钟启动，首次有数据即保存，之后按 30 分钟、24 小时后 60 分钟、72 小时后 6 小时复核。
- 调度入口使用单次 HTTP 请求，保留状态码与 `Retry-After`。429 遵守秒数和 HTTP-date；5xx / timeout 指数退避并加 jitter，普通上限 6 小时，更长的 `Retry-After` 优先。每个目标串行，同一 scheduler cycle 不重叠请求；关闭时取消并 join 后台任务。
- migration `0005_sync_schedule.sql` 增加同步截止状态和身份缓存；重启沿用持久截止时间，不重新触发尚未到期的请求。失败、空数据及低质量结果保留成功快照。
- 成绩与积分的排序业务内容、source 和 quality 形成稳定 hash；`fetchedAt` 等抓取时间不增加 revision。仅内容、来源或质量变化增加业务 revision。REST `meta.syncStatus` 可选，不改变既有 envelope 字段。
- Mac Popup 显示时每 15 分钟重新读取 REST，关闭时取消轮询；唤醒后立即刷新。即使赛历请求失败，也独立尝试当前成绩与积分数据；REST revision 更新由页面观察到，不依赖 Live SSE。

## 可重复验收

| 检查 | 结果 |
|---|---|
| `cargo fmt --manifest-path server/Cargo.toml -- --check` | 通过。 |
| `cargo test --manifest-path server/Cargo.toml` | 50 passed，0 failed：28 unit、6 API、9 calendar sync、1 results sync、6 storage。 |
| `cargo clippy --manifest-path server/Cargo.toml -- -D warnings` | 通过。 |
| `cargo build --release --manifest-path server/Cargo.toml` | 通过。 |
| `xcodebuild -quiet -project PitPulse.xcodeproj -scheme PitPulseDesktop -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test` | 47 passed，0 failed；覆盖 15 分钟轮询、关闭取消、系统唤醒 REST 请求、revision 更新、赛季晚到响应丢弃和失败保留。 |
| `node docs/tasks/validate.mjs` / `node --test docs/tasks/tests/task-data.test.mjs` | 15 tasks / 4 milestones 校验通过；8 passed，0 failed。 |

关键测试位于 [scheduler.rs](../../server/src/scheduler.rs)、[http.rs](../../server/src/providers/http.rs)、[storage.rs](../../server/tests/storage.rs)、[results_sync.rs](../../server/tests/results_sync.rs)、[api.rs](../../server/tests/api.rs) 和 [AppModel tests](../../macos/Tests/CalendarCacheTests.swift)。覆盖注入时钟与 jitter 边界、午夜 / 24 / 72 小时、估算结束时间、取消任务、429 两种 Retry-After、5xx、timeout、单次请求、持久截止重启恢复、mock Session 单飞、空结果 retry deadline、失败回滚、相同内容去重和更正后 revision 增长。

联合契约由两端本地 mock 分别验证：服务存储测试确认相同快照保持 revision、修改结果增加 revision；AppModel 测试确认 REST revision 变化时 Mac 立即采用新结果，重复相同 revision 保持结果不变。未把两套独立 mock 描述成跨进程端到端测试。

## 真实 Provider 时效另记

[T07 真实历史周末记录](t07-results.md)包含 `2026:15:race` 本地 REST 读取时间 `2026-10-09T03:31:47Z`，并在 `03:33:30Z` 单独查询 Jolpica 上游返回 22 条；此前历史读取也记录了 WDC / WCC 状态。它证明历史数据可读，不包含比赛结束时间与 Provider 首次可读时刻的连续观测，不能据此计算真实赛后延迟或声称分钟级达标。下一次实际赛后时效需按 Session 结束时间、首次可读时间和后续修订分别记录；mock 验收不替代该记录。

真实部署、比赛期间分钟级时效和公开发布不在 T09 本地验收范围内。
