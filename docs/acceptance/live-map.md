# Notch Live Map、天气和赛事消息验收

2026-10-11（Asia/Shanghai）。本记录区分实现、离线检查、真实网络和实屏验收；当前任务状态以 `docs/tasks/tasks.json` 为准。

## 已交付

- 原展开态尺寸内提供 Telemetry / Live Map、共享车手选择和独立收藏按钮；遥测与天气按各自 UTC 判断过期。
- 固定 Mapbox GL JS 3.32.0，Standard 夜间、55°、建筑/地标/地形；地图复用、隐藏暂停、服务器切换释放。浏览器只收到公开 token 与地图数据，雷达由鉴权原生 scheme handler 转发。
- 比赛首页、详情地点地图和近期 Session 预报；赛历列表/地图切换，标记打开比赛详情。旧 SQLite/客户端缓存允许缺失 circuit。
- 压缩多帧 Position/CarData、WeatherData、TeamRadio；snapshot schemaVersion 1 可选扩展，最多 4 Hz 合并快照，连接状态立即发送。
- Race Control 稳定 ID、排序、车手过滤和完整元数据；Team Radio 手动单条播放、暂停/进度、下载取消与临时文件清理。
- Open-Meteo 预报窗口与历史赛事降级；RainViewer 历史帧播放/暂停、时间选择、覆盖遮罩、缓存与限流。雷达每五分钟刷新，失败清除旧叠加。

## 自动和无界面检查

| 检查 | 观察结果 | 范围 |
| --- | --- | --- |
| `cargo test --manifest-path server/Cargo.toml` | 95 passed，0 failed，0 ignored | 压缩损坏/截断/尾部垃圾/超限、多帧/稀疏/乱序/null、UTC、跨 Session、旧契约、4 Hz 合并/慢消费者、SQLite 迁移、校准门槛、预报缺失/窗口、缓存/stale/429/重定向、鉴权/音频路径 |
| `cargo fmt --manifest-path server/Cargo.toml -- --check` | 通过 | Rust 格式 |
| `cargo clippy --manifest-path server/Cargo.toml --all-targets -- -D warnings` | 通过 | 严格静态检查 |
| `xcodebuild -project PitPulse.xcodeproj -scheme PitPulseDesktop -destination 'platform=macOS' -parallel-testing-enabled NO build-for-testing` | TEST BUILD SUCCEEDED | 主 App、XCTest 与 UI test target 编译；没有执行测试宿主 |
| `sh macos/Tests/run-live-map-check.sh` | 通过 | 实际 Swift 模型旧字段解码、独立过期、RC 元数据/过滤；实际 RadioPlayer 下载切换/取消没有复活旧请求；实际 MapStore 的旧比赛响应不能覆盖新状态，释放后晚到的配置不能恢复 token |
| `node --test macos/Tests/map-page.test.mjs` | 2 passed | Mapbox stub：缺失 token、镜头复用、待加载雷达、暂停/释放、失败状态保持 |
| `node docs/tasks/validate.mjs` / `node --test docs/tasks/tests/task-data.test.mjs` | 通过，8 passed | 任务来源、依赖、证据路径及历史 |

Mapbox stub 不加载真实地图，也不证明 WKWebView 自定义 scheme 的 WebGL 瓦片渲染。新增 XCTest 旧快照、鉴权、stale 雷达和 MapStore 释放用例已编译；没有将编译当执行结果。

## 真实网络与归档证据

在隔离、要求 Bearer 的临时服务上检查，新旧用户服务未被替换，未启用 fixture 或把失败转为 replay：

- Jolpica 返回 2026 赛历 24 站，保留赛道 ID/名称/经纬度。当前新加坡 `2026:17`，下一站 Austin `2026:18`。
- 新加坡及 Austin 的 Open-Meteo 请求成功，分别取回 40 和 55 个覆盖赛事窗口的小时预报（UTC 2026-10-10 18:36 的观察）。这是地点预报，不是 F1 赛道实况。
- 新版 RainViewer 接口取回 13 个历史帧，UTC 16:40–18:40；真实帧路径是哈希。服务使用上游给出的受限路径，固定主机获取雷达 PNG 3539 bytes、覆盖 PNG 914 bytes，来源 rainviewer、stale=false。无鉴权请求返回 401。
- 新加坡 2026 归档校准 held-out 误差 0.90/5.36/1.55 米。Austin 2025 归档为 3.72/7.68/5.95 米；**2026 Austin 没有启用车辆叠加**。数据、控制点来源和方法见 [赛道资源说明](../../server/resources/circuits/README.md)。归档几何匹配不能代替实时位置/GPS验收。

RainViewer 使用 [历史雷达/覆盖 API](https://www.rainviewer.com/api/weather-maps-api.html)、[Universal Blue 色表 2](https://www.rainviewer.com/api/color-schemes.html)，最大 zoom 7、串行最短请求间隔 650 ms；不请求未来 nowcast。限制依据 [官方变更说明](https://www.rainviewer.com/api/transition-faq.html)。天气窗口依据 [Open-Meteo 文档](https://open-meteo.com/en/docs)。本次没有在仓库保存 token、数据库或原始 feed。

## 2026-10-11 账号、配置与真实地图复核

- 用户确认账号后，完成 Mapbox 注册、邮箱验证和个人 F1 应用用途问卷。未绑定银行卡；使用自动生成的公开 token。专用 token 的创建界面要求添加付款方式，本次没有继续该步骤。控制台显示当前公开 token 的 Map Loads for Web 上限为 5K loads。
- 账号凭据、token、服务启动环境与启动脚本保存在仓库外的受限文件（凭据/token/config 0600、启动脚本 0700）。本机现有服务保留绑定地址和数据库设置后重启；健康检查成功，地图配置接口确认 token 为公开 pk 类型、GL JS 版本 3.32.0。直接请求 Standard 样式返回 HTTP 200。
- 真实浏览器发现 Mapbox 的 WebAssembly 解码器被 CSP 拦截；`script-src` 增加 `wasm-unsafe-eval` 后正常加载，没有开放 JavaScript 的 `unsafe-eval`。
- Ego Lite 加载实际地图 HTML、官方 Standard 夜间资源，检查到 styleLoaded=true、俯仰 55°、terrain source 可用、无地图错误。截图中确认建筑、地标和 Mapbox/OpenStreetMap 归属标注。通过真实按钮验证 2D/3D、缩放、复位；赛道接口返回当前新加坡轮廓，地图查询到渲染中的 track-line 特征。
- [真实 3D 底图截图](assets/t17-mapbox-browser/singapore-3d.png)、[赛道数据接入截图](assets/t17-mapbox-browser/singapore-3d-track.png)。这是独立浏览器验收：测试桥只接收页面回调，车手列表为空，没有虚构车辆位置。没有验证原生 WKWebView 的自定义雷达 scheme。
- 已有缓存没有 circuit 字段，将无错误冷却的 Jolpica 赛历成功状态标为待刷新后，由现有调度器完成回填；24 站均保留真实地点坐标，没有替换结果数据或忽略 Retry-After 错误冷却。
- 重启后的真实服务 sourceMode=live/sourceStatus=connected，22 位车手，收到 WeatherData 和 12 条 TeamRadio；当前 Session 状态 Ends，属于真实源返回的已结束场次状态，不是正在比赛的位置流。当前没有 Position/CarData 数据。
- 按已接收 Radio 条目 ID 下载真实音频成功：HTTP 200、audio/mpeg、206976 bytes、MP3 签名有效、source=f1-live、stale=false。没有在原生播放器中播放音频。
- CSP 变更后的地图 Node 检查 2/2 和 Xcode `build` 通过。原生 App、XCTest 宿主和 UI 自动化仍没有启动。

## 未完成与复核入口

- Austin 2026 当前年原点和布局未核验；其余赛道没有校准。缺失时显示地点与“车辆定位未校准”。
- 新增四个 Topic 的持续真实 Live feed、当前赛事位置叠加、正在比赛的 F1 天气和真实 Radio 原生播放没有通过独立验收；真实源已结束场次的 WeatherData/Radio 状态及音频下载已单独记录。
- 内置 Notch、外接屏 floating、地图拖拽/缩放、赛历点击、雷达播放/覆盖、音频暂停/进度、键盘和 VoiceOver 没有新的实屏操作或截图证据。
- 沿用此前停止桌面自动化和 App-host/UI 测试的限制（见 [Notch 验收记录](notch.md)）；本次没有启动主 App、测试宿主或操纵原生桌面。浏览器注册授权不扩展为原生 UI 自动化授权。

有效 token 与浏览器底图已验证；下一步检查原生 WKWebView 401/403、弱网重试、雷达跨域和实际覆盖，再用正在比赛的 Session 验证 Position/CarData/WeatherData/TeamRadio、切换 Session/服务器和隐藏时清理。记录截图和具体 UTC，仍需把离线回放、真实地图与真实 feed 分开；全部通过前不得标记任务 done。

## 2026-10-11 Mapbox GL JS 额度与实例生命周期方案

- 官方 [GL JS 计费说明](https://docs.mapbox.com/mapbox-gl-js/guides/pricing/)确认：每次初始化 `Map` 对象计一个 Map Load；地图交互和切换图层不额外计数；单次会话最多 12 小时。当前公开[价格页](https://www.mapbox.com/pricing)列出 Map Loads for Web 每月前 50,000 次免费，但本机账号验收记录中的控制台额度是 5K，两个数字不一致；实施前应以该账号控制台显示的产品项/上限为准。
- 官方 [GL JS API](https://docs.mapbox.com/mapbox-gl-js/api/properties/#prewarm)说明 `prewarm()` 预先创建可在后续地图之间复用的 worker，主要减少频繁创建/销毁实例时的等待。结合“每个 `Map` 初始化计费”的规则，`prewarm()` 本身不是额度优化。
- 官方[成本管理指南](https://docs.mapbox.com/help/troubleshooting/manage-web-map-costs/)建议对非交互小地图采用静态图；需要交互的地图采用延迟初始化，并在用户需要时再创建。静态图属于独立 API 计量项，替换前需按账号实际额度核算。
- 当前 `map.html` 只在 `window.updateMap` 且 `map == null` 时执行 `new mapboxgl.Map(...)`；同一实例上的相机、图层、车辆更新不会再次初始化。Swift `MapStore.release()` 会调用 `disposeMap()`/`map.remove()` 并丢弃 `WKWebView`，再次显示会新建实例。赛历切图、Notch 隐藏、详情页离开和服务器地址变化都可能触发释放。
- 推荐实现：进程内保留每个可同时显示的交互地图实例；临时隐藏只暂停并复用 `MapStore`/`WKWebView`，应用退出、内存回收或 Mapbox token 真正改变时才释放。主窗口与 Notch 可以同时显示，需各自保留一个实例；单实例不能同时绘制到两个容器。赛事详情的小地图改为静态预览，或在明确的“打开交互地图”操作后再初始化。只切换 PitPulse 数据服务器且 token 未变化时刷新数据，不销毁 Mapbox 实例。
- Map 对象包含页面容器、WebGL 与 worker 运行时，按磁盘持久化实例不可行；持久化的目标应是当前进程内保留实例，而不是落盘缓存 Map 对象或自行缓存 Mapbox 瓦片。尚未实施，也未验证实际账户额度变化。

## 2026-10-12 Mapbox 保活、Live 位置与手动刷新实施

- 菜单栏首页、赛历和赛事详情共用 `AppModel.mapStore`；Live Island 保留独立实例。详情地图只有点击“打开赛道地图”才创建 Mapbox 地图。隐藏/切页暂停雷达请求与动画并保留 `WKWebView`，重现后复用；切换数据服务器时取消旧请求并重读配置，同公开 token 保留实例，token 改变、Web 内容进程终止或隐藏实例遇到内存压力时释放。Session/相机键变化清除旧车辆和选择状态；无赛道地点时以有效车辆坐标作为相机中心候选。
- `LiveLocation` / `LiveTelemetry` 新增可选 `receivedAt`，契约仍为 schemaVersion 1。仅有效且上游 UTC 前进的新 Position/CarData 样本记录收样时间；初始化快照、重复帧、Heartbeat 和其他主题不续期。Swift 对位置和遥测分别按 10 秒接收时效清除实时内容，保留并展示上游 UTC 延迟；旧服务器缺少字段时回退到 UTC。地图展示等待、解码失败、缺校准、停更和比赛结束状态，并记录收到、解码、校准、客户端接受、最终绘制数量。
- 新加坡 Replay mock 现在合成压缩后的原始 `Position.z` / `CarData.z`，走生产解码、reducer 和赛道校准后推送，继续明确标为 Replay/MOCK；它不能证明真实赛事 feed 已恢复。
- 新增鉴权 `POST /api/v1/refresh`，校验赛季、目标及 Session；同目标合并、手动刷新优先，并用现有 `sync_state` 保存失败与 `Retry-After`。当前菜单页先重新读取缓存并等待上游刷新完成后再读；其他目标排入后台，完成状态通过独立 `dataRefresh` SSE 事件发送。切页、换赛季/服务器的旧响应由客户端请求代次和上下文校验拦截。

### 检查结果

- Taskdeck `Test Server`：退出码 0；服务器测试套件通过，新增 `manual_refresh` mock 实际返回上游 HTTP 429、客户端事件 `rateLimited`，并验证 SQLite 保存重试截止时间。此前直接 `cargo test --example live_replay` 通过 1 项生产解码/校准 mock。
- Taskdeck `Check Server Format` 和 `Lint Server`：退出码均为 0。
- Taskdeck `Check Map Page`：退出码 0，Mapbox stub 验证同实例暂停/恢复、雷达暂停与恢复和车辆清理。
- Taskdeck `Check Live Models`：退出码 0；无 App 宿主的脚本通过独立接收时效、旧响应隔离，并以 mock URLProtocol 调用生产 `APIClient.refresh`，检查 POST、Bearer、赛季/目标/Session 与响应解码。
- Taskdeck `Build App Tests`：`TEST BUILD SUCCEEDED`，主 App 和测试目标编译通过；新增的手动刷新旧 Session 失败隔离用例已编译。测试宿主没有运行；App 当前保持运行。
- Taskdeck `Check Task Report`：最终任务状态更新后退出码 0；`validate.mjs`、任务数据测试 8/8 与 board.js 语法检查通过。真实当前赛事 feed、原生 App UI 和 Mapbox 账号额度效果不由这些 mock/编译检查代替。

### 未完成的真实验收

- 当前可观测的真实 F1 Session 已结束，没有新的 Position/CarData feed；因此真实比赛期间车辆位置缺失的上游断点尚未复现。新诊断计数可在下一场进行中 Session 区分接收、解码、校准、客户端接受与绘制阶段。
- 未在真实原生 WKWebView 中重复开关菜单、切页、切 Session、换服务器/token 或制造内存压力；mock 通过不证明设备上 Mapbox `Map` 初始化次数或账号用量实际下降。
- `Test App` 未运行，因为 F1Companion 当前由用户保持运行；测试目标仅完成编译。真实比赛位置、外接屏/VoiceOver、Mapbox 账号计费以及失败/弱网原生 UI 仍需独立验收。
