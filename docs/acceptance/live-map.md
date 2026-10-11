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
| `xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion -destination 'platform=macOS' -parallel-testing-enabled NO build-for-testing` | TEST BUILD SUCCEEDED | 主 App、XCTest 与 UI test target 编译；没有执行测试宿主 |
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
