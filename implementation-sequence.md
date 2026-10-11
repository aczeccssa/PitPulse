# PitPulse 快速实现任务计划

> 制定日期：2026-10-08（Asia/Shanghai）
> 架构依据：[`F1-Companion-Architecture.md`](F1-Companion-Architecture.md)
> 策略：优先交付可用的 Menu Bar V1；Live / Notch 独立推进，不阻塞 V1。
> 当前状态唯一数据源：[`docs/tasks/tasks.json`](docs/tasks/tasks.json)，通过 [`静态任务看板`](docs/tasks/index.html) 查看；本文件保留任务定义与依赖，不再重复维护当前状态。完成必须有验收证据。

## 1. 已核对的起点

| 模块 | 2026-10-08 仓库实际情况 | 后续处理 |
|---|---|---|
| Rust 服务 | Tokio / Axum、配置、Bearer 鉴权、SQLite WAL、REST 读取、watch / SSE 已有基础代码 | 复用，不重新搭架子 |
| 上游 Provider | Jolpica / OpenF1 仅有 raw 请求边界；没有业务映射、真实采集闭环 | 先核验历史样本，再实现 adapter |
| 数据与调度 | 已有 domain 与 migration；sync / reconcile 是枚举边界；scheduler 只标记 Live 未接入 | 不算生产同步已完成 |
| Live | 通用 JSON merge 有测试；SignalR client / protocol 仍是接入边界 | 真实 Topic reducer 与协议另做 Spike |
| macOS | 只有目录、README 和 `.gitkeep`，没有 Xcode 工程 | 创建一个 SwiftUI App 入口与 test target |
| 素材 | 没有头盔 / Logo 映射 | T03 独立 Agent 在线收集，不挡业务主线 |

本次起点验证：`cargo test --locked --manifest-path server/Cargo.toml` 通过 **7 项测试**（unit 3、API 3、storage 1）；fmt、严格 Clippy、locked release build 均通过。本机可用 Xcode 26.6、Swift 6.3.3；没有 App 工程，因此还不能声称 macOS build / test 通过。

## 2. 已确定的界面规则

### 2.1 比赛用举办国旗帜 Emoji

- 赛历、下一站卡片、比赛详情和 Notch 的比赛标识使用**比赛举办国家 / 地区的旗帜 Emoji**；不下载国旗图片，不用车手国籍代替举办国。
- 后端保留 `country` 可读名称，增加可空 `countryCode`（ISO 3166-1 alpha-2，大写）；在 Provider adapter 内归一化别名。新增字段走增量 migration，不改写已经使用的 `0001_init.sql`。
- Mac 的 `CountryFlag` 从经过映射校验的国家代码生成区域指示符 Emoji；不依赖比赛名称关键字或系统当前语言猜国旗。
- 测试样例：Australia → `AU` → 🇦🇺；UK / United Kingdom → `GB` → 🇬🇧；USA / United States → `US` → 🇺🇸；UAE → `AE` → 🇦🇪；Japan → `JP` → 🇯🇵。
- 同国多站共享国旗，但按 `meetingId` / `round` 区分，不以国家为唯一键。Sprint 周末仍使用该站举办国旗。
- 国家映射缺失 / 非法 / 无对应代码时显示 `globe` SF Symbol 和原始国家名称；不构造看似正确的假旗帜。
- 旗帜配可访问性国家名称，不能作为唯一辨识文本。

### 2.2 通用 icon 用 SF Symbols

集中在 `macos/Core/Models/AppSymbol.swift` 管理语义到 Symbol 的映射，不在视图中散落字符串，不引入第三方通用 icon 库：

| 语义 | 首选候选 SF Symbol |
|---|---|
| Menu Bar / 比赛 | `flag.checkered` |
| 赛历 | `calendar` |
| Session 时间 / 倒计时 | `clock` / `timer` |
| 成绩 / 积分榜 | `list.number` / `trophy` |
| 提醒 | `bell` |
| 设置 | `gearshape` |
| 刷新 / 重连 | `arrow.clockwise` |
| 缓存 / 断网 | `externaldrive` / `wifi.slash` |
| 数据过期 / 故障 | `exclamationmark.triangle` |
| 关注 | `star` / `star.fill` |
| 国家未知 / Live 无连接 | `globe` / `antenna.radiowaves.left.and.right.slash` |

这些是实现候选；T04 必须在实际最低 macOS 版本检查 `NSImage(systemSymbolName:accessibilityDescription:)`，缺失时回退到已验证的基础 Symbol。使用 `Image(systemName:)`，Menu Bar 保持 template rendering；选中与异常状态不能仅靠颜色表达。

**范围说明**：SF Symbols 用于 App 内功能图标和状态栏图标，不能直接当作应用品牌 / App Store App Icon。发行 App Icon 留给后续原创图标，不为此阻塞本地 V1。车手头盔和车队 Logo 是单独的真实素材，不用 SF Symbols 冒充。Apple 的 SF Symbols HIG（2026-10-08 核对）：`https://developer.apple.com/design/human-interface-guidelines/sf-symbols`。

### 2.3 车手头盔与车队 Logo

- 单独任务 **T03**，完整 Agent brief 位于 [`docs/tasks/T03-motorsport-assets.md`](docs/tasks/T03-motorsport-assets.md)。Agent 必须实际联网检索，不把“以后找图”当交付。
- 头盔不等于头像；车队 Logo 不等于赛车照片。用稳定 `driverId` / `constructorId` + `season` 映射，不能用数组序号、当前车号或显示名称作为唯一键。
- 素材随 App 本地打包；macOS 不运行时直连 F1 / 第三方图源，素材元数据研究文件不作为客户端联网入口。
- 来源、授权、赛季、下载与打包状态逐项记录。研究完成、下载完成、可发布和 App 已接入是四种不同状态。
- 无可用素材时用车手缩写 + 车队名 / 颜色占位，通用辅助图标仍用 SF Symbols；不展示其他车手或其他赛季图却不标注。
- 不等待所有图齐全才实现 V1。未知授权图不自动进入对外发布 bundle。
- **2026-10-09 用户范围澄清：** 仓库仅供用户本人本机私人版本控制，用户授权将 T03 素材纳入本地 commit；不 push 到 GitHub、不公开发布或分发。素材放在 `MotorsportAssets/private-local/`，manifest 用 `useScope=privateLocalOnly` / `privateLocalPath` 标识；本地 commit 不改变 `rightsStatus`，也不代表获得通用再分发许可。若未来要 push、公开发布或分发，须先重新核验相应权利。

## 3. 快速交付路线

```text
T01 契约与 V1 数据 Spike → T02 赛历采集 ───────────────┐
                      └→ T07 成绩 / 积分采集 → T09 调度与修订 ─┤
T04 macOS 工程 → T05 API / 缓存 → T06 赛历 ─────────────┤→ T11 V1 验收
                          └→ T08 成绩 / 积分 UI → T10 提醒 ─┘
T03 素材 Agent ───────────→ T08 可用素材接入（不是阻塞依赖）

T12 SignalR Spike → T13 Live 链路 → T14 Notch → T15 部署与最终验收
                     若 Live blocked：保留降级，继续交付 V1
```

- **M1：第一条可用链路** — T01、T02、T04、T05、T06：真实赛历 → SQLite → REST → Menu Bar；可选赛季、显示国旗和本地时间、离线可读。
- **M2：完整 V1** — T07～T11：各 Session 成绩、WDC/WCC、修订刷新、提醒、故障恢复；T03 的可用素材逐步接入。
- **M3：尽力提供 Live V2** — T12～T14：协议事实明确后再接实时链路和 Notch；协议或授权受阻不影响 M2。
- **M4：个人部署** — T15：本地部署演练先行；真实 VPS / 比赛时段验证独立记录，不用模拟验收代替。

以可运行的纵向闭环推进，不先造完整设计系统、复杂主题、全量遥测存储、素材后台、账户系统或通用工作流平台。没有日期 / 工期承诺；外部 API 与真实赛期按证据推进。

## 4. 任务定义索引（当前状态读取 JSON）

| ID | 任务 | 优先级 | 硬依赖 |
|---|---|---|---|
| T01 | V1 数据 Spike、统一契约与 fixture | P0 | 无 |
| T02 | 赛历采集、国家代码与持久化 | P0 | T01 |
| T03 | **独立 Agent 在线收集头盔 / 车队 Logo** | P1 / 并行 | 无 |
| T04 | macOS 工程、Menu Bar 壳与 Symbol 映射 | P0 | 无；模型绑定前对齐 T01 |
| T05 | APIClient、Keychain、缓存与设置 | P0 | T01、T04 |
| T06 | 赛历 / 下一站 / Session 详情与国旗 | P0 | T02、T05 |
| T07 | Session Results、WDC/WCC Provider 与存储 | P0 | T01、T02 |
| T08 | 成绩 / 积分 UI 与素材映射 | P0 | T05、T07；T03 非阻塞 |
| T09 | 自动调度、结果修订与失败退避 | P0 | T02、T07 |
| T10 | 本地提醒、离线与睡眠 / 唤醒恢复 | P1 | T06、T08、T09 |
| T11 | V1 本地端到端验收 | P0 | T06、T08、T09、T10 |
| T12 | SignalR 与 OpenNook 集成可行性 Spike | P1 / 并行 | 无；本地 App Spike 需 T04 |
| T13 | Live Topic Reducer、SSE、LiveStore | P1 | T01、T05、T12 协议结论 |
| T14 | Notch 紧凑 / 展开态与降级 | P1 | T13、T12 OpenNook 结论 |
| T15 | 部署、运行证据与最终验收 | P1 | T11；V2 验收另需 T14 |

素材研究记录见 [`docs/assets/collection-report.md`](docs/assets/collection-report.md)，来源与映射见 [`manifest.json`](macos/Resources/MotorsportAssets/manifest.json)。当前任务进度、授权／下载待审项统一读取 [`tasks.json`](docs/tasks/tasks.json)。

## 5. 可直接执行的任务卡

### T01 — V1 数据 Spike 与统一契约

**实现范围**：`server/src/providers/`、`server/src/domain/`、`server/src/api/dto.rs`、`server/tests/fixtures/`、`docs/data-contract.md`、`docs/provider-spike.md`。

- 查询一个已经结束的常规周末和一个 Sprint 周末，核验 Jolpica 常规 / Alpha、OpenF1 sessions / session_result；FP1 尤其验证字段、匿名可读性、分页和延迟边界。
- 记录请求路径、采集时间、HTTP 状态、来源、字段缺失；只提交脱敏、精简、可用于测试的历史 fixture，不提交 token、原始实时 feed 日志或庞大全量抓取。
- 冻结稳定 meeting / session / driver / constructor ID、来源映射、Session 枚举、UTC 时间、国家代码、质量状态与可空字段。成绩 `position` 当前必填，应核验未分类 / DSQ 等情况是否需要可空；不可用数字 0 假装真实名次。
- 明确 `schemaVersion` / `revision` / `source` / `fetchedAt` / `stale`；区分数据抓取时间、上游修正时间和业务 revision。统一空数据、尚未发布成绩、404、401、错误 envelope 的语义。
- API 不因上游暂无成绩而整接口报系统故障；Mac 能区分 pending / partial / provisional / final（仅有源证据时）/ stale。不凭“首次抓到”判定 final。

**验收**：fixture 解码 / 分页 / 缺字段 / UTC 测试通过；契约有 JSON 示例；两源 FP1 对照写出 `available / partial / blocked` 和证据。某上游受阻时，可用历史主源继续 V1，不凭预期宣称接入成功。

### T02 — 赛历采集与持久化

**实现范围**：Jolpica / OpenF1 adapters、`domain/calendar.rs`、`storage/sqlite.rs`、新增 migrations、`services/sync.rs`、对应 API 测试。

- 实现赛季赛历、常规 / Sprint 周末各 Session，映射国家别名到 `countryCode`。
- 共享 Reqwest 连接、设置 timeout、检查 HTTP 状态、限制重试；Provider 不直接耦合 Swift 字段或 UI 文案。
- SQLite 用事务 upsert，避免重复同步多出 Session；真实时间更新形成可观察 revision，取消 / 延期不丢失语义。
- 增加启动同步入口（完整调度留 T09）；已缓存内容先可读，上游失败不抹掉缓存。

**验收**：从空 DB 经 fixture 上游取到赛历 → API 非空；与该赛季官方赛历对照完整站数和 Session 类型（不写死数量）；重复同步幂等；分页 / 取消 / Sprint / 未知国家 / 旧库升级 / 请求超时有测试；真实数据手工 smoke 与离线测试分开记录。

### T03 — 独立素材 Agent

**执行方式**：使用独立 Agent，按 [`docs/tasks/T03-motorsport-assets.md`](docs/tasks/T03-motorsport-assets.md) 在线查找、核验并收集。只写素材专属目录，避免与 App 实现产生冲突。

**交付**：当前赛季名单证据、逐车手头盔 / 逐车队 Logo 覆盖矩阵、可审计 manifest、可打包图片（若许可明确）、缺失与授权待审清单。**不能只写一份网址列表就声称图片已下载。**

**验收**：manifest 可解析；每项 ID / season / 来源 / license / 状态明确；已下载文件 hash、格式与路径有效；区分候选、已下载参考、可发布；缺失有替代 UI 建议。详细要求见独立任务卡。

### T04 — macOS 原生工程与壳

**实现范围**：`macos/F1Companion.xcodeproj`、共享 scheme、`macos/App/`、`Features/MenuBar/`、`Core/Models/AppSymbol.swift`、测试 target、macOS CI job。

- Swift 6；一个 `@main App`；`MenuBarExtra(.window)` + Settings；无第二 App 入口、无主窗口抢焦点。
- 先完成连接状态、loading / empty / error、页签导航；预览样本与真实运行明确隔离，禁止正式版默认展示编造赛事。
- SF Symbols 集中映射、Menu Bar template 图标、可访问性 labels；测试候选 Symbol 是否可用。
- 最低部署目标为 macOS 26.0；App 与 Test 构建配置已统一为 26.0，Info.plist 从该值派生。直接使用 macOS 26 SwiftUI API，不宣称支持更早版本。

**验收**：共享 scheme 支持 build / test；App 实际启动后只有一个状态栏入口；Popup、Settings、退出可操作；附截图及实际最低版本 / Symbol 兼容结论。CI 编译不能代替运行验收；最低版本为 macOS 26.0，当前主机运行环境为 macOS 26.5。

### T05 — APIClient、缓存与 Preferences

**实现范围**：`macos/Core/APIClient/`、`Models/`、`Cache/`、`Features/Preferences/`；Settings 场景的尺寸、原生窗口材质与激活生命周期。菜单栏设置入口仅负责收起 Popup、激活并打开设置，不重做 Menu Bar 或 Nook 界面。

- URLSession 只访问自托管 Rust API；base URL 可配置。Bearer 从 Keychain 读取，日志脱敏。
- 解码统一 envelope；超时 / 401 / 429 / 5xx / 契约不兼容可识别，不无限自动重试错误凭据。
- Codable 磁盘缓存按服务器身份、赛季和资源键隔离；原子写入、旧 schema 失效 / 迁移、损坏缓存恢复。
- 缓存优先显示，后台刷新；切换服务器时不把旧服务器数据混到新连接。HTTPS 优先，仅为明确的本地开发 / 私网配置开放必要 HTTP 范围，不做全局 ATS 豁免。

**验收**：URLProtocol fixture 测试、损坏缓存、离线冷启动、缓存 revision、切换服务器和 Keychain 错误路径覆盖；不把 token 写 UserDefaults / JSON / 日志。Preferences 以「连接、本地提醒、Live Island、关注车手」四类侧栏呈现，保留原有设置行为。

### T06 — 赛历、Session 与国家 Emoji

**实现范围**：`Features/Calendar/`、`Features/MenuBar/`、`Core/Models/CountryFlag.swift`；允许 `/meetings/next` 的最小后端修复及质量时间元数据纠正。

- 下一站、全赛季列表、比赛详情、各 Session 本地时间和倒计时；旗帜按 2.1 执行。
- `/meetings/next` 可选 season；按不早于当前时间的 scheduled Session 排序，排除取消/延期，稳定 ID 打破同时间平局；无候选 data 为 null。在线接口与离线选择同规则、时钟可注入测试。
- fetchedAt 表示真实服务端抓取时间，未知 sourceUpdatedAt 保持为空，不互相冒充。
- 时间只从 RFC 3339 UTC 转当前 Mac 时区；常规 / Sprint 周末不硬编码固定 Session 数量。
- 清楚呈现暂无赛程、延期 / 取消、数据来源、最近成功同步和缓存过期；不将计划起止时间当实时比赛状态。

**验收**：AU / GB / US / AE / JP、未知代码与同国多站测试；Asia/Shanghai、跨日和 DST 时区测试；实际 Popup 截图和详情点击证据。

### T07 — 成绩与积分的 Provider / 存储闭环

**实现范围**：`providers/`、`domain/results.rs`、`domain/standings.rs`、`services/sync.rs`、`storage/`、`api/routes.rs` 和 fixture 测试。

- FP1 / FP2 / FP3、Sprint Qualifying / Sprint / Qualifying / Race；练习赛两源并行探测，谁先有可用完整成绩先使用。Sprint 在 Alpha 返回空榜或失败时回退至已有 OpenF1 session_result，保留来源及 partial / provisional 标识；Alpha 后续可读时恢复主源，不从 Live 排名生成正式成绩。
- 将练习赛最佳圈、Q1 / Q2 / Q3、Race time / gap / laps / classification 分开建模；禁止将多阶段排位挤进一个含糊 `time` 而丢字段。
- DSQ / DNF / DNS / 无有效圈 / 缺 position 不伪造；部分数据以 partial 展示，完整判据不得固定“永远 20 名”。
- 分析接口按已存Session与稳定身份查询OpenF1详细历史数据，轨迹/遥测限制到单车单圈时间区间；季节明细通过Jolpica实际Race/Sprint结果获得。鉴权、限流、缓存、失败保留及字段缺项可验证。
- WDC / WCC 接官方积分快照，不自行算积分。写入事务、稳定 ID 和来源一致性；Mac 所需车队 ID 须在契约提供，不从显示名称猜素材。

**验收**：每种 Session 至少一个 fixture；两源分歧、先 partial 后完整、处罚修正、空榜与可空字段测试；两种 standings API 有实际非空及鉴权测试。

### T08 — 成绩 / 积分 UI 与素材

**实现范围**：`Features/SessionResults/`、`Features/Standings/`、`Core/Models/MotorsportAsset.swift`、App asset catalog 接入。

- 结果页按 Session 类型显示适配列；积分页支持 WDC / WCC 和赛季。
- 成绩与车手 / 车队积分详情在同一菜单栏内以二级页面打开，与赛历一致；左上角图标返回原列表，不使用 sheet 弹出层。
- 详情增加真实逐圈/赛段、名次、轮胎/进站、天气/赛事事件图表，以及单圈轨迹速度/油门/刹车热力图；积分含逐站/累计走势、名次分布与对比。采样由服务器按需获取并限流/缓存，Mac不直连Provider。缺项/身份不明/上游不可读明确降级，不绘制假赛道或假数据。
- 显示 driver / constructor 稳定 ID 对应头盔 / Logo；T03 交付的可发布文件由此任务转入 App build resources / `.xcassets`，素材研究 manifest 不自动加入 bundle。
- 允许没有素材照常运行；缺图、过季图、加载失败有明确 fallback。支持 Retina、明暗背景与 VoiceOver。
- 源时间戳、revision、partial / provisional / stale 可见；刷新不是仅重画旧缓存。

**验收**：正常 / 缺图 / 旧赛季 / 未分类 / 缺圈速 / 处罚后更正 UI 测试和截图；无第三方素材联网请求；研究清单与实际 bundle 对照。

### T09 — 自动调度、重试与结果修订

**实现范围**：`scheduler.rs`、`services/sync.rs`、`services/reconcile.rs`、`sync_state` 持久化和 API meta。

- 常态赛历 / 积分每 6 小时；Session 前 24 小时每 30 分钟核对赛程；赛后每 2～5 分钟尝试结果；首次可读立即入库，随后每 30～60 分钟复核、逐步降频。
- Session 结束时间不确定时记录估算 / source 状态依据；探测可以提前，但不得因此宣布比赛已结束 / 成绩 final。
- 处理 429 / Retry-After、5xx、网络 timeout、指数退避与 jitter；同一目标不重叠抓取；同步任务可取消并随服务正常退出。
- 同源内容 hash 去重；仅实际内容 / 来源 / 质量变化形成业务 revision；不要每次 fetchedAt 改变都通知“成绩更新”。跨源冲突遵守架构优先级并保留来源事实。
- 保存 next_retry / last_success / 错误摘要；重启恢复，不把失败写入替代上次成功数据。Mac 在打开 Popup、周期刷新、唤醒时识别 REST revision 更新；静态结果不依赖 Live SSE。

**验收**：可注入时钟 + 本地 mock Provider 测试调度、限流、重启续跑、并发单飞、失败回滚和结果修订；不等待真实 6 小时跑测试；真实 Provider 时效另外记账。

### T10 — 提醒、离线与唤醒

**实现范围**：`Core/Notifications/`、缓存 / 生命周期协调、Preferences。

- 默认可配置 Session 提前提醒（例如 15 分钟）；解释用途后请求 UserNotifications 权限；可关闭 / 调整，不反复弹权限。
- sessionId + reminder 规则去重；赛程更改重排，取消撤回；UTC 转本地通知时间，过期 Session 不补发一串通知。
- 断网和唤醒立即标识缓存状态，再按退避刷新；通知权限拒绝不影响所有数据页。
- 关注车手按稳定 ID 保存；为 V2 使用，但不假设某车手永远属于同一车队。

**验收**：时间变更、跨时区、重复刷新、权限拒绝、睡眠 / 唤醒与网络切换有测试 / 本机记录；离线可查看赛历、成绩和积分。

### T11 — V1 端到端验收

**交付**：`docs/acceptance/v1.md`、可重复的本地 fixture/mock 驱动流程、App 截图与必要测试补缺。

- 从空 DB 启动 Rust → 同步 fixture → Mac 配置私有 API → 赛历 / 成绩 / 积分显示；结果第二版注入后自动显示新 revision。
- 演练错误 token、上游限流、停止服务、Mac 断网、数据库恢复、缓存重启和 App 睡眠 / 唤醒；UI 不虚构“实时”。
- 另记录一次真实已完成历史周末的数据读取；**至少一次真实练习赛赛后自动获取**保留待真实赛期验证，不拿 mock 代替。

**验收**：本地 fixture 验收与真实数据证据分别列状态。M2 本地实现可以先通过；全架构的真实赛后时效条目仍 pending，不能提前宣称整体完成。

### T12 — SignalR 与 OpenNook Spike

**交付**：`docs/live-spike.md`、`docs/opennook-spike.md`、最小纯 Rust / Swift 原型（不引入第二服务运行时）。

- 核实 negotiate / websocket / subscribe 的**实际协议版本**、cookie / auth、压缩 Topic、心跳与初始状态。不要因为名字叫 SignalR 就预设与某 Core crate 兼容。
- 先验证 `signalr-client`，不兼容再选择最小 `tokio-tungstenite` 层；不绕过认证或付费限制。
- 验证 OpenNook NookKit / NookSurface 实际包产品、最低系统、单 App 生命周期、MenuBarExtra 共存、多显示器 / 无刘海 fallback；不先引入整个示例 App。
- Live 分 `available / partial / blocked`，同时区分协议能握手与真实赛期 Timing 字段可读；离线阶段不等同于无访问权。

**验收**：记录访问日期、依赖 revision、实际成功 / 失败步骤和字段证据；不能只靠库文档宣告可用。Live blocked 则暂停实际连接部分，继续实现 fixture 降级和 V1。

### T13 — Live Topic Reducer → SSE → LiveStore

**实现范围**：`providers/f1_live/`、`domain/live.rs`、`services/live_state.rs`、`api/sse.rs`、`macos/Core/LiveStore/`。

- 优先 SessionInfo / SessionStatus / DriverList / TimingData / LapCount / TrackStatus / RaceControlMessages；轮胎字段按真实证据补齐，不订阅高体量物理遥测。
- 顺序 reducer 处理嵌套 key patch、索引、可空值和实际压缩消息；Session 切换 / reconnect 清理旧状态。现有通用 merge 不能直接视为完整 Topic reducer。
- watch 最新 Snapshot、版本、UTC 时间、stale / disconnected 阈值，10～30 秒聚合 SSE；首次连入完整 snapshot，断线后重新取快照，不虚构完整事件审计。
- Swift 增量 SSE parser 处理拆包、多行 data、keep-alive、取消、后台与唤醒；断开立即不再标 live，重连有退避。

**验收**：记录 / 精简 fixture 回放、多 Session 隔离、乱序版本、SSE 拆包、慢消费者、超时、断线 / 重连测试；没有真实上游时 UI 明示 replay / disconnected，不宣称 Live 已证实。

### T14 — Notch 界面与降级

**实现范围**：`Features/LiveIsland/`、AppKit 面板 / OpenNook 接入、Preferences。

- 紧凑态：举办国 Emoji、Session / 比赛状态、圈数、关注车手头盔 / 姓名 / 名次 / gap；展开态：加宽 Timing、头盔、Gap / Interval、上一圈 / 最佳圈、S1 / S2 / S3 时间与分段状态、可用进站状态、TrackStatus / RaceControl。只投影现有 Topic 字段；新增 API 字段可选并兼容旧客户端，未提供的轮胎 / 进站次数 / 遥测明确标缺。
- Session 自动激活 / 收起，关注车手切换；赛道绿旗 / 黄旗 / SC / VSC / 红旗及结束状态以图标与对应颜色显示，展开顶部持续可见，悬停提示与辅助功能保留完整说明。关注、取消与收起操作使用图标，关注入口置顶，车手行直接关注 / 取消，紧凑态可点击进入选择。Live 不可用只展示已知 Session / 计划信息与降级标签，不推进假圈数或保留过期旗色。
- 无刘海、外接显示器、分辨率变更和多屏策略明确；Panel 不抢焦点、不遮关键菜单区域；保留 Menu Bar 独立可用。
- 消息详情默认折叠，按需展开并保留选择；设置提供鼠标移出自动收起或点击外部收起，菜单/天气详情保持展开。

**验收**：紧凑 / 展开 / 无刘海 / 缺字段 / stale / disconnected 实际截图和交互；OpenNook 受阻时记录边界，不临时另起一个 App。

用户实际验收反馈涉及共享界面时，同步修正 T04 / T06 / T08 的入口与展示：比赛首页展示当周或最近赛事的完整周末，菜单图标固定，显式隐藏立即执行；赛历、成绩、积分统一原生滚动与行间距，成绩及积分行提供已有字段的详情。相关运行验收重新关联证据，既有历史保留。

### T15 — 部署与最终验收

**实现范围**：现有 `server/deploy/`、必要的可选 Docker 改进、README、`docs/acceptance/deployment.md` / `live.md`。

- Release binary + systemd 为默认；token / TOML / SQLite 放仓库外。演练 HTTPS 或私网、正常 shutdown、DB 备份恢复、重启与 provider 断网。
- 本地开发使用 `taskdeck init` 注册 PitPulse，配置 `Run Server` / `Run App`：启动前分别构建 Rust/Swift，前台进程由 Taskdeck 管理；Server 读取仓库外配置与数据库，App 默认连接真实本机服务38701。停止和重启只操作本会话任务，回放始终独立。
- 常用本地开发检查由Taskdeck具名任务统一入口：Rust debug/release、test/fmt/clippy，Swift debug/release、测试目标编译/单测，以及地图和任务报告检查；遵循AGENTS.md的Taskdeck优先、具名启动和桌面测试隔离规范。
- 有 VPS 访问授权再部署；没有则本地先验收，不捏造远程上线结果。除非用户另行授权，不 commit / push / 创建 PR / 发布 release。
- 真实练习赛后 5 / 15 / 30 / 45 / 60 分钟记录 Provider 可读性；真实 Session 记录 Live 字段、分钟级时效及降级。
- 闲置 / 赛事 RSS / CPU 实测，无硬编码低内存承诺；区分 Linux 服务指标和本机 App 指标。

**验收**：架构 Phase 4 每项关联证据；真实赛事、VPS、最低系统兼容未测的项目标 pending；Live blocked 时明确交付 V1 + V2 不可用说明，不把全部功能勾完。

## 6. 执行与验证约束

### 分工与变更边界

- 默认主线按依赖逐任务推进，每次交付一条可验证路径。当前只授权并启动 T03 素材 Agent；其他任务若要多 Agent 并行再明确分配。
- 未来后端与 macOS 可在 T01 契约完成后分开写；共同契约、migration、工程文件、任务状态由主 Agent 集成，避免抢写。
- 每次任务开始、实质进展、验收或完成后更新 `docs/tasks/tasks.json` 的状态、步骤、验收项、证据、阻塞、更新时间和追加历史；本文件仅在任务定义 / 依赖变更时同步。未经证据不得把架构原 checklist 批量勾选。
- 不覆盖无关 dirty / staged / untracked 改动；不抓取或提交敏感实时日志；fixture 测试不依赖 live network。

### 验证命令

```sh
# Rust（现有目录可执行）
cargo fmt --manifest-path server/Cargo.toml -- --check
cargo clippy --locked --manifest-path server/Cargo.toml -- -D warnings
cargo test --locked --manifest-path server/Cargo.toml
cargo build --release --locked --manifest-path server/Cargo.toml

# macOS（T04 建好项目、共享 scheme 与 test target 后执行）
xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

真实通知 / Keychain / App 生命周期还需使用恰当签名运行测试，不能把无签名 build 等同于系统集成通过。运行数据、Xcode 派生文件、token 与 SQLite 文件不得进 Git。

## 7. 计划交付记录

- 2026-10-08：核对架构与实际骨架；建立本计划及 T03 独立任务卡；启动素材 Agent；Rust 起点 7 项测试、fmt、严格 Clippy 与 locked release build 通过；任务卡唯一性及本次新增文档的本地链接检查通过。
- 本记录不代表 T01～T15 的业务实现已完成；实际状态以 `docs/tasks/tasks.json` 和各验收证据为准。

- 2026-10-08：素材 Agent 首轮研究已交付（报告 + 34 项 manifest），JSON 必填字段、唯一键、UTC 时间及权利 / 打包状态隔离检查通过；尚无已下载或可发布图片。

- 2026-10-08：初始化静态任务状态看板和独立 JSON；任务当前状态统一迁移至 `docs/tasks/tasks.json`，后续 Agent 更新按 `AGENTS.md` 必须维护 JSON。

### T07/T08 分析加载修正约束

分析由服务器在启动和结果可用后后台预加载，缓存持久化。详情 API 立即返回缓存或准备状态，不能等待上游或被其他分析的网络读取阻塞；客户端先显示既有缓存，后台进度有边界与失败提示。用真实响应延迟、离线单次刷新/重启恢复测试验收，UI 操作仍由用户执行。


## 地图与赛事信息扩展（M5）

T16 Live 数据扩展 → T17 Notch 3D 地图与校准 → T18 赛历地图、天气与雷达；T19 消息与音频依赖 T16；T20 综合验收依赖 T17–T19。当前进度只记录在 tasks.json。

- T16：Position.z / CarData.z 有界解码、逐字段更新与时间、WeatherData / TeamRadio、最多 10 Hz SSE（100ms 合并），保持慢消费者只取最新状态、连接状态立即发送；实际遥测频率受上游采样限制。
- T17：WKWebView + 固定版本 Mapbox GL JS Standard 夜间 3D，赛道几何与版本化校准；整圈居中、车队颜色/车号、位置插值、地点标签隐藏、收起/隐藏后恢复展示选项与相机。至少三个控制点拟合、独立点误差 ≤20m；首批为新加坡当前布局及下一站。未校准不得产生车位。Mapbox 渲染资源直连为第三方网络规则的明确例外，其余数据经 Rust adapter。
- T18：Jolpica 赛道经纬度持久化，比赛首页和赛历列表/地图切换；Open-Meteo 近期预报、RainViewer 历史两小时雷达与覆盖状态。
- T19：固定可见的 Race Control / Team Radio 分页及消息条数，详情默认折叠、按需展开；明确的全部/指定车手过滤和空态，手动单条音频播放；鉴权下载、固定上游路径和隐藏/折叠清理。
- T20：Rust/Xcode/任务校验、真实 Notch/floating/键盘/VoiceOver；回放与真实 Mapbox、赛事 feed 分开验收。不新增独立 Live 窗口，不做未来雷达、转写、追车镜头或全季一次性校准。

### T16 — Live 数据扩展

范围与验收遵循上方 M5 定义；任务数据记录当前进度与证据。

### T17 — Notch 3D 地图与校准

范围与验收遵循上方 M5 定义；任务数据记录当前进度与证据。

### T18 — 赛历地图、天气与雷达

范围与验收遵循上方 M5 定义；任务数据记录当前进度与证据。

### T19 — 消息与音频

范围与验收遵循上方 M5 定义；任务数据记录当前进度与证据。

### T20 — 综合验收

范围与验收遵循上方 M5 定义；任务数据记录当前进度与证据。
