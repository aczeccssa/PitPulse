# PitPulse macOS App

这是 PitPulse 的原生 macOS Menu Bar V1：

- Swift 6 / SwiftUI，`MenuBarExtra(.window)` 单一入口。
- Rust API：默认 `http://localhost:38701`；允许任意主机/IP 与 http/https（无 scheme 时默认 http），公网部署建议 HTTPS。
- Token 只存 Keychain；UserDefaults 保存服务器地址、赛季、关注车手稳定 ID 和自动展示偏好。
- 赛历按服务器身份与赛季隔离缓存，支持离线读取、损坏缓存恢复和最新 revision 替换。
- 赛历展示举办国 Emoji、本地 Session 时间、下一站和倒计时；预览／测试 fixture 不进入正式运行路径。

## 构建与测试

```sh
xcodebuild -project PitPulse.xcodeproj -scheme PitPulseDesktop   -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

共享 scheme `PitPulseDesktop` 包含 App 和单元测试 target。部署目标为 macOS 26.0；当前运行验收记录以本机 macOS 26.5 / Xcode 26.6 为准。

## Live Island 诊断

App 使用系统统一日志，subsystem 为 `com.pitpulse.F1Companion`。`LiveStore` 记录连接 generation、接受或丢弃的 stateVersion、连接状态及重试延迟；`LiveIsland` 记录自动／手动展示、Session 切换、30 秒收起计时器、窗口几何、屏幕候选、缩放比例及面板是否获取键盘焦点。不记录 Token、服务器 URL、原始赛事消息或车手名单；前台应用标识按私有数据处理。

在启动 App 前采集：

```sh
log stream --style compact --level debug --predicate 'subsystem == "com.pitpulse.F1Companion"'
```

回看最近五分钟：

```sh
log show --last 5m --style compact --info --debug --predicate 'subsystem == "com.pitpulse.F1Companion"'
```

先确认 `snapshotAccepted`，再检查 `automaticStarted`、`compact`／`expanded` 和 `panelKey`。自动展示和悬停应保持 `panelKey=false`；显式展开支持键盘焦点。窗口 `panelFrame`、`screenFrame` 使用 AppKit 坐标，XCTest 的 AX frame 使用不同坐标系，不能直接互相替代。若 status item 不可点击，保存测试的 AX frame、`isHittable` 和 App 日志，先诊断自动化；不要调整用户的显示器设置来迁就测试。

UI 自动化会移动鼠标、发送键盘输入并切换焦点，只能在不干扰用户的专用桌面时段运行。用户正在使用桌面或已要求停止交互时，只执行 `xcodebuild build` 和日志／结果文件检查，不运行 `test`、启动 App 或操作系统设置。

运行 UI 验收前应确认没有手动启动的主 App。`xcodebuild test` 自行启动和退出被测 App；手动验收和自动化验收串行执行，避免两个进程各自创建 Nook。可用 `pgrep -x F1Companion` 只读核查进程，不应按模糊名称批量终止用户进程。

Debug 版可用 `PITPULSE_ACCEPTANCE_SCREEN=external` 将唯一 Live Island 面板放在现有无刘海外接屏，以复现 OpenNook floating 布局；无符合条件的屏幕则沿用默认选择。该参数不进入 Release，不改变系统屏幕配置，也不建立新 SSE 连接。默认策略始终优先内建刘海屏。
