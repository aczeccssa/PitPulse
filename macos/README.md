# PitPulse macOS App

这是 PitPulse 的原生 macOS Menu Bar V1：

- Swift 6 / SwiftUI，`MenuBarExtra(.window)` 单一入口。
- 本机 Rust API：默认 `http://localhost:38701`；远程服务必须使用 HTTPS。
- Token 只存 Keychain；UserDefaults 只保存服务器地址和赛季。
- 赛历按服务器身份与赛季隔离缓存，支持离线读取、损坏缓存恢复和最新 revision 替换。
- 赛历展示举办国 Emoji、本地 Session 时间、下一站和倒计时；预览／测试 fixture 不进入正式运行路径。

## 构建与测试

```sh
xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion   -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

共享 scheme `F1Companion` 包含 App 和单元测试 target。部署目标为 macOS 14；当前运行验收记录以本机 macOS 26.5 / Xcode 26.6 为准。
