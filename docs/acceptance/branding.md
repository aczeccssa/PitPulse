# PitPulse 应用图标与 favicon

## 接入范围

- 设计源保留在 `design/brand/pitpulse-v1/`，主体和背景仍为两份独立 PNG。
- `macos/Resources/AppIcon.icon/` 是可由 Icon Composer 读取的原生分层图标文件。两张图片以 `sips` 等比导出为 1024 × 1024，分别保存在 `Assets/`；`icon.json` 中 Logo 在前、Background 在后，关闭图层玻璃、折射与投影，保留既定配色。
- Xcode 主 App 的 Debug/Release 均设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`，并把 `.icon` 加入资源编译。图标的系统轮廓和兼容产物由 Xcode 生成。
- `server/resources/branding/favicon.png` 为 64 × 64；`favicon.ico` 包含 16/32/48 三个尺寸。它们来自同一原生图标的默认外观导出。
- 首页保留原有运行提示，新增标题及两种 favicon 的 HTML 引用。两条静态图标路由在 Bearer 中间件之外，首页和所有 API 保持原鉴权范围；图标字节通过 `include_bytes!` 编译进服务，不依赖运行目录。
- 应用的菜单栏功能符号沿用原有逻辑，本次修改应用品牌图标。

## 原生导出依据

本机 Icon Composer 自带 `ictool --help` 列出的导出接口用于验证并生成默认 macOS 外观。图标配置遵循 [Apple 的 Icon Composer 接入方式](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)。

```sh
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" \
  macos/Resources/AppIcon.icon --export-image \
  --output-file /tmp/pitpulse-app-icon.png \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

`favicon.ico` 只是三个已导出的 PNG 帧的 ICO 容器，不包含新的绘制内容。原生导出预览见 `docs/acceptance/assets/t24/app-icon.png`。

## 验证边界

现有 `taskdeck.yaml` 已补齐本次需要的 Build App Release、Test Server、Check Server Format、Lint Server、Check Task Report，均为手动具名任务。构建与校验的观测结果记录在 `docs/tasks/tasks.json`；当前进度只以该 JSON 为准。

新增 API 回归验证启用 Bearer 后图标仍可被浏览器读取、图标类型和文件签名正确，首页/健康/赛历/Live API 无凭证仍返回 401，凭证正确时首页包含图标声明。真实本机 HTTP 检查与 fixture/router 测试分别记录。

Icon Composer 的桌面自动控制遇到图像捕获错误，未用 UI 操作结果作为验收。原生渲染图片、构建产物检查和已有 Taskdeck 服务更新各自留证；未执行 App-host 或 UI 自动化测试。

## 本机验证证据（2026-11-09，UTC+8）

- Taskdeck `Build App Release`、`Test Server`、`Check Server Format`、`Lint Server` 均实际结束并返回退出码 0。格式检查首次指出新增测试的换行问题，修正后复跑通过。
- Release bundle 的 `CFBundleIconFile` / `CFBundleIconName` 均为 `AppIcon`，包含可解码的 `AppIcon.icns`。从构建产物提取的图片为 `docs/acceptance/assets/t24/bundled-app-icon.png`，已目视核对 Logo。
- 通过 Taskdeck 仅重启 `Run App` 和 `Run Server`，实际进程已分别进入新版 App 和 Rust server。运行中的 App bundle 同样引用 `AppIcon`。
- 真实本机服务的 PNG/ICO 均返回 HTTP 200、正确 MIME，返回字节与仓库资源逐字节一致；首页包含两个图标声明，健康接口数据库状态正常。脱敏检查结果为 `docs/acceptance/assets/t24/http-checks.json`。
- 启用 token 的鉴权边界由隔离 router 测试验证；本机服务没有为本次验收更改鉴权配置。未把浏览器标签页或 Finder 的视觉表现标为人工验收。
