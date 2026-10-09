# T10 提醒、离线与唤醒验收

验收日期：2026-10-09。代码和注入式自动测试已验收；任务按 `implementation-sequence.md` 的两项标准判定完成。真实签名通知授权及物理睡眠／网络切换的运行级证据仍缺，边界见文末复核结论。

## 实现

- Preferences 默认关闭提醒；开启说明用途，只在授权状态为 `notDetermined` 时请求权限。拒绝后保留数据页并提供通知系统设置入口。提醒覆盖所有 Session，可选提前 5、15、30、60 分钟。
- 每个通知 ID 绑定服务器身份、赛季、Session ID 和提前分钟数。计划只收录 scheduled 赛事中的 scheduled Session，UTC 单次触发；重复刷新沿用 ID，时间变化重排，取消／过期／切换服务器或赛季时撤销过期计划。刷新失败不撤销已有通知，安排错误会显示并在后续刷新重试。
- 缓存优先支持赛历、已选成绩、WDC 和 WCC。NWPathMonitor 与睡眠／唤醒监听复用 AppModel；刷新单飞，睡眠取消刷新，唤醒及网络恢复触发刷新。普通失败按 5、15、30、60、300 秒退避，401 等待凭据变化，429 使用 `Retry-After`。关注车手保存稳定 ID。

## 自动验收

| 检查 | 结果 |
|---|---|
| `xcodebuild -quiet -project macos/F1Companion.xcodeproj -scheme F1Companion -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test` | 56 passed，0 failed；覆盖通知授权／拒绝、稳定 ID、重复刷新、并发刷新、改期／取消、服务器／赛季隔离、DST UTC 时刻、过期、安排失败及重试。 |
| `CalendarCacheTests` 离线与生命周期用例 | 断网冷启动读取赛历、成绩、WDC/WCC；网络恢复刷新；401 不循环；429 等待响应头；普通失败推进退避；睡眠取消请求、唤醒与网络恢复合并为一次赛历刷新。 |
| Rust 验证 | `cargo fmt --manifest-path server/Cargo.toml -- --check`、locked strict Clippy、locked tests、release build 和验收 example 编译通过。 |

## 未验收边界

自动化测试使用 `CODE_SIGNING_ALLOWED=NO`。另以本机 Developer ID Application 成功签名隔离 bundle 并通过 `codesign --verify`；但 Computer Use 无法枚举其 MenuBarExtra，也没有可访问窗口。没有调用真实 `UNUserNotificationCenter` 权限弹窗，没有验证系统通知投递或用可交互签名 App 演练睡眠／唤醒和 NWPathMonitor；fake center 测试不等于系统通知实际投递。也未保存 T08 场景截图或完成 VoiceOver 实机操作。运行级系统集成仍未验收；任务标准的完成判定见文末复核结论。

## 本轮复验

2026-10-09 修正 Keychain 错误用例对全局 `URLProtocolStub` 的跨用例误报后，macOS 全套测试 56 passed、0 failed。Computer Use 明确报告本机处于锁定状态；真实通知授权／投递及系统睡眠、唤醒和网络切换仍未执行。

## 按任务验收标准复核

T10-A1 要求上述行为“有测试／本机记录”。56 项通过的 Xcode 测试逐项覆盖 DST 前后 UTC 触发时刻、时刻改动与取消、重复同步、授权拒绝、睡眠取消请求、唤醒刷新和网络恢复；T10-A2 的离线赛历、成绩、WDC、WCC 冷启动和恢复刷新也通过。按 `implementation-sequence.md` 的验收文字，T10 两项标准均通过，任务可标为 `done`。

真实 `UNUserNotificationCenter` 权限弹窗／通知投递和物理睡眠／网络切换没有运行级证据；本机锁定使这些额外系统集成观察无法进行。本轮保留该边界记录，不把测试替身描述成系统通知已实际投递。

## 2026-10-09 最终回归补记

再次运行默认 `F1Companion` scheme 的完整测试命令，56 passed、0 failed（MacBook Pro arm64 / macOS 26.5）。弹窗 UI 测试独立放在 `F1CompanionUITests` scheme 后，默认回归只运行 T10 所需的 XCTest 单元／模型测试；真实系统通知投递和物理睡眠仍是单独的运行级观察边界。
