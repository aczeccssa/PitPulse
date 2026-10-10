# T04 / T05 / T06 实施与自动化验收续记

## T05 Settings 重做验收（2026-10-11）

- `PreferencesView` 改用 macOS 26 原生 `NavigationSplitView` 侧栏、透明可滚动详情和 `GlassEffectContainer` / `.glassEffect` / `.glassProminent` 操作层；保留连接、本地提醒、Live Island、关注车手四类设置及原有 `AppModel` 行为。
- 设置场景使用 800×640 默认尺寸、760×560 内容最小尺寸和统一紧凑工具栏；设置入口先收起菜单栏 Popup，避免 Popup 覆盖设置窗口。
- 最终 `xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`：82 项单测通过，0 失败。
- 最终 `F1CompanionLiveAcceptance` scheme 仅运行 `MenuBarAcceptanceTests/testSettingsWindowPromotesAppAndRestoresAccessoryPolicy` 和 `MenuBarAcceptanceTests/testSettingsWindowLightAppearance`：2 项通过，0 失败、未跳过。覆盖齿轮打开、四类侧栏切换、关闭后重开、regular/accessory 往返、已打开设置时 Cmd+, 不增加第二个设置窗口。该 Cmd+, 断言不证明从关闭状态独立打开设置。
- 浅色测试同时传入 `-AppleInterfaceStyle Light -NSRequiresAquaSystemAppearance YES`；仅前一参数在本机未生效。最终八张截图已逐张检查：800×640 窗口的浅深色四类页面均无遮挡，文字和控件未裁切，空 Token 操作正确显示禁用态。截图均为 2× 像素导出，未裁切、未合成。
- 最小尺寸尝试两次失败：角落和直边拖拽后 XCTest 仍报告 800×640，760×560 断言失败。未确定是拖拽工具还是窗口缩放行为所致，因此移除不稳定拖拽断言，保留真实缩放与滚动为未验收项，不把最终两项交互测试通过扩大为缩放通过。
- Computer Use Helper 缺少辅助功能授权；实际 Dock/Cmd+Tab 切换返回、最小化恢复、独立 Cmd+, 打开路径及最小尺寸检查尚无完整证据。T05 保留 `inReview`，A4/A5 不勾选。

最终截图：

| 页面 | 浅色 | 深色 |
|---|---|---|
| 连接 | [浅色连接](assets/t05-settings/light-connection.png) | [深色连接](assets/t05-settings/dark-connection.png) |
| 本地提醒 | [浅色提醒](assets/t05-settings/light-reminders.png) | [深色提醒](assets/t05-settings/dark-reminders.png) |
| Live Island | [浅色 Live Island](assets/t05-settings/light-liveIsland.png) | [深色 Live Island](assets/t05-settings/dark-liveIsland.png) |
| 关注车手 | [浅色车手](assets/t05-settings/light-favoriteDriver.png) | [深色车手](assets/t05-settings/dark-favoriteDriver.png) |

以下为历史记录；其中 macOS 14 最低目标描述已由当前 macOS 26.0 配置取代，历史测试数量不代表当前回归数量。


日期：2026-10-09。运行环境：macOS 26.5 / Xcode 26.6；最低部署目标 macOS 14.0。当前验证覆盖最低目标编译设置与本机 macOS 26.5 运行环境；未在 macOS 14 设备上实测，Symbol 回退结果仅能确认在当前环境全部可解析。

## 实现与回归

- 原生单一 `MenuBarExtra(.window)`、Settings scene、Accessory App、template 状态栏 Symbol；共享 Scheme 同时含 App 与 XCTest target。
- APIClient 仅请求配置的 PitPulse API；URLSession fixture 覆盖小数 UTC、可空字段、401 不重试、429 Retry-After、5xx、超时和 schema 错误。
- 缓存覆盖服务器与赛季隔离、损坏删除恢复、原子写入失败、旧 cache/schema 失效、revision 同值刷新。
- 新增 AppModel 回归：失败不更新成功请求节流时钟、缓存冷启动照常刷新、离线保留可读数据、401 明示需 Token、Keychain 错误可见、服务器切换后晚到旧请求不能覆盖、stale 同 revision 更新 metadata。
- 修复服务器身份规范化：host 不区分大小写、路径大小写保留、默认端口和尾部斜杠归一。抓取时间改为 SQLite UTC 实时值；未知 Provider 更新时间不再伪装为抓取时间。
- T06 测试含 AU/GB/US/AE/JP、无效国家 globe、同国赛事独立 ID、Asia/Shanghai 跨日、America/New_York DST、Sprint 非固定 Session 数、取消/延期、未来 Session 与倒计时边界。

## 门禁结果

- `xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`：39 项通过、0 失败（最终重跑）；含身份归一、Keychain 错误和 Season boundary 回归。
- `cargo fmt --manifest-path server/Cargo.toml -- --check`、`cargo test --locked --manifest-path server/Cargo.toml`、严格 Clippy `-D warnings`：通过；其中真实同步时间/未知 provider 时间分离有固定断言。
- `node docs/tasks/validate.mjs` 与任务 JSON 数据测试：8 项通过。
- 本地 API 曾返回 2026 赛季 24 站，`/meetings/next?season=2026` 返回 Singapore Grand Prix；复启后 fetchedAt 为当前 UTC，不是固定旧日期。该联调数据库来自本地 provider 尝试/缓存；不将其描述为上游实时成功证明。

## 运行证据边界

仓库保留 `assets/t04-t06/popup-next-meeting.png`（可读的旧 Popup）与 `calendar-list.png`。**实际打开发现后者全黑，是无效截图，不能作为列表/详情的验收证据。** 原文件保留用于追溯，不纳入有效交付。当前桌面 Computer Use 未枚举到 F1Companion 窗口，截图工具无法匹配该窗口，故本轮没有重新保存 popup、详情点击、设置与离线状态证据。不能据此宣称本机交互验收全部通过；T04 Popup/Settings/退出逐项操作及 T06 详情点击仍待可操作 UI session 复核。离线逻辑已有 URLProtocol/缓存自动测试，但停止正在使用的服务器并手动重启 App 的完整交互演练也未重采集。

## 用户补交截图与赛历样式反馈（2026-10-09）

用户提供五张本机运行截图，已保存到 `assets/t04-t06/user-*.png`：

- `user-next-meeting.png`：Singapore 下一站、未来 FP1、本地时间、当前抓取与读取时间及在线状态可读。
- `user-meeting-detail.png`：从赛历打开 Australian Grand Prix 详情，显示举办国、状态及各 Session。本图替代旧全黑图作为详情证据。
- `user-results-placeholder.png`、`user-standings-placeholder.png`：明确提示未接入，不伪造成绩/积分；不代表 T07/T08 完成。
- `user-settings.png`：设置窗口、服务器地址、空 SecureField、Keychain 状态和连接/缓存操作入口可见，无 Token 泄露。

这些截图证明上述界面已打开，不证明退出、唯一状态栏入口、Token 增删或真实断网重启流程全部通过。此前 UI 自动化取不到窗口的限制已由用户手动截图补足一部分；历史记录不删除。

用户反馈不喜欢赛历实色填充和粗、有底色的滚动条。本次仅调整赛历模块：以透明列表/轻量返回标题替代原生 List/NavigationStack 的实色区域；列表及详情的原生滚动容器局部设为小尺寸、自动隐藏的 overlay scroller，不修改 macOS 全局滚动设置。修改前的五张图不能作为修改后的视觉通过证据，仍待用户复核。

## 续接验证与预览恢复（2026-10-09）

- 对中断前已写入的赛历透明列表、轻量返回标题与局部覆盖式滚动条执行完整 `xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`，结果 **40 tests / 0 failures / TEST SUCCEEDED**。新增的一项检查覆盖 NSScrollView 配置；该检查不证明 SwiftUI 实际视图中的锚点已找到滚动容器，也不代替视觉验收。
- 停止旧 App 进程后，通过 Computer Use 的 App 入口启动当前构建，确认新版进程存在；这不等于通过「退出」按钮验收。没有修改用户 Token、服务器偏好或系统滚动设置。
- 恢复既有本地联调数据库对应的 loopback 服务；`/api/v1/calendar?season=2026` 为 HTTP 200 / 24 站，`/api/v1/meetings/next?season=2026` 为 HTTP 200 / Singapore Grand Prix。这是本地预览可用性证明，不作为第三方实时 feed 证明。
- Computer Use 两次绑定目标 App 均报告 timeoutReached；Finder 能返回 AX desktop，但截图是纯白，不足以判断状态栏图标与 Popup 外观。因此未采纳该截图，也未勾选单一入口、退出或真实离线冷启动的未通过项。
- 可从运行中的状态栏 App 打开「赛历」及比赛详情，复核透明标题区、细自动隐藏滚动条和返回操作。修改前用户截图仍保留，仅证明修改前的可见状态。

## 用户验收与提交前审查（2026-10-09）

用户确认下一站、赛历两个 Tab 的数据与展示正常，接受本轮交付并授权本地 commit。成绩、积分空页是明确的未接入占位，属于 T07/T08。

最终审查修复共享 calendar_meta 的 stale 固定为 false：超过 6 小时的抓取标记 stale，calendar 和 next 共用；数据继续可读。新增「过期缓存 → 成功刷新」测试先复现失败，再通过修复；同时更新固定旧 fixture 的 stale 断言。Rust 全套 22 项、fmt 和严格 Clippy 通过；Swift 沿用上一轮当前代码的 40 项通过结果，本轮无 Swift 修改。任务状态和用户验收写入唯一 tasks.json。

用户的 Tab 验收不扩大为退出按钮或入口数量证明。T04 这两项实际操作仍待补；真实断网后的完整运行演练未做，已有 fixture 冷启动回归是 T05 的验收证据。最低 macOS 14 实机运行仍未覆盖。本地提交不含临时看板备份、Token、SQLite 数据及实时 feed 日志。
