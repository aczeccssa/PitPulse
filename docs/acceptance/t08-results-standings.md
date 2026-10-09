# T08 成绩、积分与素材验收

验收日期：2026-10-09。范围：macOS 成绩 / WDC / WCC 页面、REST 缓存、本地素材 Catalog。本文件按时间记录证据；早先“找不到普通窗口／机器锁定”的判断由文末 MenuBarExtra 实测补记更正。

## 实现与契约

- [成绩页](../../macos/Features/SessionResults/SessionResultsView.swift)按 Session 类型展示最佳圈、Q1/Q2/Q3，或 classification、time/gap、laps、points；空字段显示 `—`，未分类文字保留。赛事 / Session 选项来自已结束 Session，并按最近结束时间排序。
- [积分页](../../macos/Features/Standings/StandingsView.swift)支持车手 / 车队榜和赛季选择；显示官方名次、积分、胜场。两页显示 source、sourceUpdatedAt、fetchedAt、revision、quality、stale 和独立刷新错误。
- [API 模型与客户端](../../macos/Core/APIClient/APIModels.swift)解码七类 Session、WDC/WCC 与可选值；按服务器 / 赛季 / Session key 隔离缓存。刷新失败保留上次成功内容，服务器或赛季变化时忽略晚到响应。成绩、积分 REST 错误独立于赛历状态。
- 素材按 provider 稳定 ID 和 season 查找；未知 ID、非当前 season、缺图和加载失败使用车手缩写 / 车队名称，不请求第三方图片 URL。图片使用本地 `NSImage(named:)`，视图按图像尺寸缩放并向辅助技术隐藏装饰性图片；选择器、成绩行和 provenance 有 VoiceOver label / 合并语义。

## 素材与授权边界

- [manifest](../../macos/Resources/MotorsportAssets/manifest.json)记录 22 张单盔和 11 个车队标志的原始来源、原图 SHA-256、项目输出路径 / SHA-256、逐项 `projectUseAuthorization` 和 `projectBundleReady`。本机 SHA-256 对照无缺文件或不匹配；构建后的 `Assets.car` 中 33 个名称全部存在。
- 用户授权仅限 PitPulse 项目本地使用和打包。六份专题照片未作为单盔。原第三方 `license`、`rightsStatus`、设计年份核验事实未被改写；manifest 的公开发布仍为 `notReady`，`shippingReadyCount` 仍为 0。项目授权不等同权利方许可。
- 研究清单未加入 App bundle；运行时图片路径只调用本地 Asset Catalog，没有素材域名请求。

## 自动验收

| 检查 | 结果 |
|---|---|
| `xcodebuild -quiet -project macos/F1Companion.xcodeproj -scheme F1Companion -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO test` | 47 passed，0 failed；MacBook Pro arm64 / macOS 26.5。 |
| `APIClientTests` | 成绩、WDC、WCC envelope，空阶段字段、鉴权、限流与错误解码通过。 |
| `CalendarCacheTests` / `AppModelTests` | 服务器 / 赛季 / Session 缓存隔离；服务器及赛季切换的晚到响应丢弃；刷新失败保留最后成功成绩；REST revision 从 1 更新至 2，同 revision 再抓取不改变当前成绩。 |
| `MotorsportAssetTests` | 稳定 ID / season 命名及车手缩写 fallback 通过。 |
| bundle 对照 | 22 helmets + 11 team logos；33 项源 / 输出 hash 相符，33/33 位于构建后的 `Assets.car`。 |

七类 Provider fixture、未分类 / DNF / DNS / DSQ、空结果、处罚修正、业务 revision 和低质量覆盖保护另由 [T07 Rust 验收](t07-results.md)覆盖；这属于服务契约验证，不代替 Mac UI 场景截图。

## 未验收项

T08-A1 仍为 `false`。本轮以独立 bundle ID 完成 Developer ID Application 签名构建并通过 `codesign --verify`；Computer Use 的 `getApp` 多次超时，尽管隔离 App 进程已启动，MenuBarExtra 仍未出现在可访问应用列表或 AX 窗口中。没有提交正常、缺图、旧赛季、未分类、缺圈速、处罚后更正或明暗外观的截图，也没有手工验证选择、滚动、刷新和 VoiceOver。没有用静态 mock 图冒充运行界面证据。需在可捕获的本机 Popup 会话中补齐这些证据后，才可将 T08 标为 `done`。

## 本轮复验

2026-10-09 再次运行 macOS 全套测试，56 passed、0 failed；重新核对 manifest 中 33 项 bundle 文件 SHA-256 全部匹配，构建后的 `Assets.car` 含 33/33 项资源名，结果／积分图片加载路径没有第三方 URL。Computer Use 明确报告本机处于锁定状态；因此本轮仍无法打开 MenuBarExtra Popup，T08-A1 的界面场景截图、交互和 VoiceOver 继续待本机解锁后实测。

## 2026-10-09 MenuBarExtra 验收路径与更正

PitPulse 的 `Info.plist` 设置 `LSUIElement=true`，入口是 SwiftUI `MenuBarExtra(.window)`。它没有常规 Dock 图标和主窗口；Computer Use 的普通窗口枚举／`getApp` 找不到窗口，不能推出 App 或 Popup 不可用。早先把锁屏和“no matching windows”写成 T08 blocker 是验收工具路径判断错误，不是产品缺陷。

正确的 Xcode 调试入口是选 `F1Companion` scheme 执行 Run；进程会以菜单栏 agent 运行，断点仍可附着在 AppModel、APIClient 和视图代码中。要自动化 Popup，用 `XCUIApplication(bundleIdentifier:)`、`app.statusItems` 和 `app.dialogs`，不要等待普通 `app.windows`。本轮 UI acceptance test 曾通过真实状态栏项打开 Popup，结果／积分／赛季切换与辅助功能控件均由 XCTest 访问；它导出五张实际弹窗截图，清单记录测试标识及附件：

UI scheme 使用的 fixture 端口和可直接复跑命令见 [T11 本地验收步骤](v1.md)。

- [正常成绩、缺素材 fallback、未分类、无圈数](assets/t08-menu-bar-20261009-ui/73634126-4C5E-4A70-BC36-D446708F77BF.png)
- [2026 车手积分](assets/t08-menu-bar-20261009-ui/972239B5-2350-497D-95E9-612819BDA803.png)
- [2025 赛季缺素材 fallback](assets/t08-menu-bar-20261009-ui/7E4D62B5-CFE1-4B58-9474-2A8C2FA34099.png)
- [revision 2 更新后的成绩](assets/t08-menu-bar-20261009-ui/080AC56F-96F1-479B-9A50-68A015391647.png)
- [处罚更正后的成绩](assets/t08-menu-bar-20261009-ui/AEA3D950-8C6E-440D-8708-5844904083E1.png)
- [附件与 UI 测试映射](assets/t08-menu-bar-20261009-ui/manifest.json)

后续重跑查明当前自动化环境的具体限制：XCUITest / System Events 都枚举到 `PitPulse` 状态栏项，但辅助功能坐标为 `x=-3948`，当前内建屏幕范围从 `x=0` 开始；Popup 因而未展开。当前无外接屏在线，重启 `SystemUIServer` 和重启 App 后坐标仍为负值。失败发生在弹窗出现前，不是成绩断言失败。标准 `F1Companion` scheme 保留 56 项单元测试；状态栏 UI 测试放入独立 `F1CompanionUITests` scheme，避免无可见状态栏坐标时把单元测试误报失败。UI 场景成功证据以本节实际通过运行及附件为准，当前坐标异常作为复跑环境限制单独记录。

UI 测试通过了成绩／积分导航和赛季选择器的 Accessibility 查询；本轮未验证 VoiceOver 实际语音播报。验收准则中的 UI 场景与截图已通过，语音播报不作为本任务 blocker。
