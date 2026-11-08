# FIA WEC Live PoC（Griiip 公开接口）

日期：2026-11-08（UTC）  
范围：仅 Live 快照与 Notch 数据源切换；不含 WEC 赛历、成绩、积分或数据库多系列迁移。

## 结论

FIA WEC 官方免费 Live Timing（`livetiming.fiawec.com`）由 Griiip 的 “Second Screen” 前端提供数据，其服务端为 `https://insights.griiip.com`。公开 REST 接口无需登录即可返回会话 bootstrap，足以构建排名、组别、圈速、分段、天气、赛会消息与计时赛剩余时间。当前实现以默认关闭的 opt-in 适配器接入，F1 行为不变。

该接口没有公开文档或 SLA，只作为个人自托管 PoC 使用；不绕过登录、付费墙或访问控制，也不提交原始抓取载荷。使用前应确认 WEC / Griiip 的服务条款。

## 上游观察

- `GET /api/v2/public/live/session/{sid}/bootstrap`
- `GET /meta/series/10/active-season-calendar`（发现当前 Live 会话）
- 需要时可用 `GET /live/session-clock/{sid}`、`/live/race-flags/{sid}`、`/live/cars-locations-on-track/{sid}`。
- 官方前端另有 SignalR `/live-session-stream`；PoC 未使用，改为低频率 REST 轮询，降低实现与运维复杂度。
- bootstrap 的关键字段：`sessionInfo`、`sessionClock`、`sessionLengthLimit`、`participants`、`ranks`、`gaps`、`laps`、`bestLaps`、`sectors`、`currentLapSectors`、`runningStatuses`、`carLocations`、`weather`、`raceFlags`、`raceLogFirstPage`、`trackDetails`。

## 实现

- `server/src/providers/wec_live.rs`：公开接口客户端、当前会话发现、bootstrap → `LiveSnapshot` 映射。
- `server/src/scheduler.rs`：独立的 WEC live supervisor，轮询失败时保留旧快照并按时效标记 `stale` / `disconnected`。
- `server/src/app_state.rs`、`server/src/api/routes.rs`、`server/src/api/sse.rs`：独立 `live_wec` 状态；`/api/v1/live/snapshot?series=wec` 与 `/api/v1/live/stream?series=wec`。
- `macos/Core/LiveStore/LiveModels.swift`、`LiveStore.swift`、`macos/App/AppModel.swift`、`macos/Features/Preferences/PreferencesView.swift`、`macos/Features/LiveIsland/LiveIsland.swift`：数据源切换、组别标签、FCY 与计时赛剩余时间。
- 默认配置：`wec_live_enabled = false`；轮询间隔默认 5 秒，限制在 2–60 秒。

### 启用方式

```bash
F1_COMPANION_WEC_LIVE_ENABLED=1
F1_COMPANION_WEC_LIVE_SESSION_ID=18162   # 可选；缺省时自动发现当前 Live 会话
F1_COMPANION_WEC_LIVE_POLL_SECONDS=5
```

`scripts/run-server.py` 会从 `~/Library/Application Support/PitPulse/server/environment.json` 读取以 `F1_COMPANION_` 开头的字符串配置。

## 验证证据

### 真实 Live 会话

2026-11-08 10:24 UTC，Monza 6 小时赛（session 18162）进行中。以独立端口启动启用 WEC 的服务端，读取 `/api/v1/live/snapshot?series=wec`：

- `series = wec`，`sessionId = wec:18162`，`meetingName = FIA WEC - 6 Hours of Monza`
- `countryCode = IT`，`circuitName = Monza Circuit`
- `sourceStatus = connected`，`sessionStatus = started`，`trackStatus = Green`
- 35 辆车；`HYPERCAR` 与 `LMGT3` 组别、总排名与组别排名均可用
- 领跑车 `#38 Jack Aitken (CADILLAC HERTZ TEAM JOTA)`，`LEADER`，上一圈 `1:36.185`
- `lapCount = 14`，`timeRemainingSeconds = 20112`（约 5 小时 35 分）
- 天气：气温 11.6°C、赛道 12.5°C、湿度 72%
- 赛会日志 40 条，含 `RCMessage` 文本消息
- 未记录原始 bootstrap 载荷或任何凭证。

10:30 UTC 修正国家代码映射后再次复核同一会话：`countryCode = IT`，`lapCount = 18`，`timeRemainingSeconds = 19775`，`elapsedSeconds = 1825`，`isTimeBased = true`，35 辆车与 40 条赛会日志保持一致；`series=wec` 的 SSE 首帧同样返回 WEC 快照。

### 自动化测试

- `cargo test --lib wec_live`：4 项通过（映射、组别/计时、会话发现、RFC 3339）。
- `cargo test --test live`：7 项通过（默认 F1、`series=wec`、未知 series 返回 400、WEC SSE）。
- `cargo test`：全量 109 项测试通过，无回归。
- `cargo fmt --check` 与 `cargo clippy --all-targets -- -D warnings`：通过。
- macOS：`xcodebuild ... build-for-testing` 编译 App 与 XCTest 目标；`LiveStoreTests` 新增 WEC 解码、FCY 与剩余时间用例。
- Swift 模型运行时检查：以 `swiftc` 编译 `APIModels.swift`、`LiveModels.swift` 并解码 WEC 快照，确认 `series`、`isWec`、`remainingLabel`、FCY 映射与组别标签均符合预期。

## Live Island 展示增强（2026-11-08）

- **保持原 F1 布局**：计时表的列宽、字号、行高与焦点信息恢复为改动前的设计；新增信息不占用独立列，避免拥挤。
- **Gap**：F1 与 WEC 都使用原有 `Gap` 列，默认显示。
- **轮胎**：F1 从 `Stints` topic 的最后一个 stint 取 `Compound` 与 `StartLaps + TotalLaps`；WEC 从 bootstrap `tires` 取左前轮胎与圈龄。以 `S/M/H/I/W + 圈数` 显示在车手信息第二行，可在“显示”菜单中关闭。
- **虚拟能量**：WEC 从 `carsEnergyTanks.items[].e` 映射为 0–100% 剩余量，以细进度条与百分比显示在车手信息第二行；F1 不提供该项，菜单中也不显示该开关。
- **WEC 视觉资产**：从 FIA WEC 官方 Grid 与车辆页下载 2026 赛季 23 个车队/制造商 logo、35 张赛车右侧视图与 102 位车手肖像，压缩后放入 `PitPulseAssets.xcassets`；数据来源与哈希记录在 `Resources/MotorsportAssets/wec-assets-2026.json`。深色 logo 在本地处理为浅色以保证深色界面对比度，不做运行时联网抓取。
- **车手肖像补全**：按 `fiawec.com/en/car/2026/33` 补入 TF SPORT #33 的 Jonny Edgar 官方肖像（`driver-photo-jonny-edgar-2026`）；2026 车辆页仍把 Alex Lynn 标为 unknown 时，改从 `fiawec.com/en/car/2025/12` 取官方肖像（`driver-photo-alex-lynn-2026`）。当前 Live 名单 35 人全部有本地肖像；官方仍标记为 unknown 的车手继续回退为姓名缩写。
- **关注与选择分离**：关注按车手身份（姓名）匹配并持久化；同一车号换人后不会继承关注，关注车手不在本次会话时折叠区与详情条显示 `No selected`。点击列表行只改变顶部车组详情，点击星标只改变关注，互不重置。
- **轮胎文字**：不再使用官方轮胎贴图；WEC 与 F1 一致回到 `S/M/H/I/W + 圈龄` 的文字显示，按配方着色，避免小尺寸圆形贴图难以辨认。
- **WEC 区段与轮胎能量**：WEC 不提供分段颜色数据，S1–S3 列由 88pt 收窄到 50pt 并去掉无信息的灰色分段条；空出的宽度改为独立的轮胎/能量单元，轮胎以 11pt 文字显示，能量用更大的进度条与百分比，字号由 9pt 提升到 11pt。
- **折叠角标**：黄旗、红旗改用 `YF` / `RF` 短代码，与 `SC` / `FCY` / `VSC` 一致，折叠 Nook 不再出现中文赛道状态。
- **制造商标识**：WEC 计时行显示制造商 logo（由 `manufacturer` 匹配官方品牌素材），不再显示车手肖像；车手肖像只保留在关注车手折叠区与详情条，缺失时回退为姓名缩写。品牌素材统一使用标志本身：BMW 仅圆标（不含 ///M）、Mercedes 仅三叉星、Toyota 仅椭圆标、Lexus 仅 L、Cadillac 仅盾徽、Corvette 仅交叉旗、Ford 仅椭圆、Aston Martin/Genesis 仅翼徽、McLaren 仅 Speedmark，不再使用“标志 + 文字”组合或纯文字字标；列表内保留 32pt 行位但按 80% 尺寸绘制，避免挤压车手姓名。
- **车辆详情条**：WEC 选中车手时显示官方赛车侧面图、车队 logo、组别/组内名次与轮胎/能量，替代原本的“车辆遥测未提供”占位。F1 详情条同样显示 2026 各队官方赛车侧视图、头盔、车队 logo、车号/名次/差距与实时速度、RPM、挡位；11 支车队侧视图来自 formula1.com 官方车队页，仅本地打包。
- **系列标识**：折叠 Nook 与展开头部不再显示赛事所在国家的旗帜 emoji，改为官方 F1 / WEC 系列 logo（`series-f1` / `series-wec`），只显示标识本身；关注与选中逻辑不变。
- **组别区分**：WEC 计时表上方提供“全部 / HYPERCAR / LMP2 / LMGT3”标签页，按 `classId` 过滤并按组别优先级排序，每个标签显示车辆数；切换系列时重置为“全部”。F1 不显示该行。
- **关注车组**：WEC 车手按车号关注（`wec:<number>`），与 F1 关注车手分开持久化；列表星标与详情条星标均可操作。折叠后的 Notch 只显示关注车手的肖像、车号与名次（不显示差距）。选中车辆的详情条同时显示肖像、赛车侧面图、总名次、差距、组别名次与车队。
- **折叠信息**：圈数移到左侧；WEC 显示关注车组自身的圈数，没有关注车组时回退为全场圈数。会话类型按显示名规范化（`race` → `Race`），旗帜、会话与 WEC 标签保持同一水平线居中。
- **折叠警示**：绿旗状态默认不显示。只有黄旗、FCY、SC、VSC、红旗时，左侧整组信息才包裹为胶囊，使用对应旗帜颜色背景与 `SC` / `VSC` / `FCY` / `黄旗` / `红旗` 小角标。
- **赛道状态**：`raceFlags` 是整场历史，改为取最后一条记录判断当前状态，不再按全场最高严重度取值（修复比赛恢复绿旗后仍显示 SC 的问题）。SC / FCY / VSC 使用“旗标 + 文字”胶囊标识，取代原先的黄色小车图标。
- **双系列切换**：Live Island 不新增独立控件，点击赛事标题弹出 F1/WEC 菜单即可切换。Menu Bar 菜单不承担实时数据源切换；切换会重连 SSE 并清空上一系列快照。
- **真实 WEC 复核**：session 18162 返回 `SOFT 31`、虚拟能量 `91%`、`Cadillac V-Series.R` 制造商与各组别排名；F1 replay fixture 验证 `SOFT 4` / `HARD 12` 映射。

## 验收

2026-11-08，用户在运行中的 Release App 上确认 WEC 制造商标志（含 BMW 单一圆标）与 Live Island 列表显示正常；T23 全部验收标准通过并关闭。

## 未覆盖 / 后续

- 未实现 SignalR 增量流；目前每 5 秒拉取约 25–35 KB bootstrap。
- bootstrap 的 `carLocations` 只有 `Track` / `Pit` 状态，没有逐车 x/y；地图与遥测仍为后续工作。
- WEC 官方素材按所有者本地授权打包：车队/制造商 logo、赛车侧面图与车手肖像来自 `fiawec.com`，仅本地自托管使用，不对外分发；运行时仍不抓取第三方图片。WEC 官方未发布头盔素材，因此 WEC 行显示制造商 logo，详情条显示车手肖像而非头盔。
- F1 2026 赛车侧视图与 F1/WEC 系列标识同样按所有者本地授权打包（`Resources/MotorsportAssets/f1-assets-2026.json` 记录来源与哈希），仅用于本地自托管，不对外分发，运行时不联网抓取。
- 未接入 WEC 赛历、成绩、积分或 SQLite 多系列维度。
- 未完成正式 ToS 确认；接口可能随时变化，必须保持 feature flag 与优雅降级。
- WEC 关注按车号记录，车手更替后同一车号会继承关注；如需按车手身份跨赛季追踪，还需接入 WEC 车手名册。
