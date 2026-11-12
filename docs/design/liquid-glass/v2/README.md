# PitPulse macOS · 布局重做 v2

日期：2026-11-11
目标：把当前“480 × 640 单列长滚动”重做为可容纳更多信息、可下钻的 macOS 26 Liquid Glass 界面。
视觉语言沿用 v1（玻璃分层、朱红强调色、等宽数字），**版式与信息架构全部重排**。

## 交付图

| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `race-dashboard-light.png` | 比赛 · 仪表盘 | 下一节、天气格、周末时间线、最新成绩、积分领先 |
| `calendar-light.png` | 赛历 · 主从布局 | 左侧分站列表，右侧选中赛道预览 |
| `race-detail-light.png` | 比赛详情 | 二级标签 + 周末/天气/Race Control 双列 |
| `results-expanded-dark.png` | 成绩 · 行内展开 | 领奖台 + 分类表 + 分段/策略/速度 |
| `driver-detail-dark.png` | 车手详情 | 圈速图、stint、进站、遥测 |
| `standings-light.png` | 积分 · 走势 | 前三概览、积分表、选中车手走势卡 |
| `live-island-dark.png` | Live Island | 双列计时塔 + 车手细节 + mini map |

全部为 1024 × 1536（Live Island 为 1536 × 1024）。图中为示例数据，用于评审信息密度与层级，不代表真实赛季数据。

## 为什么重做

当前界面每条内容都挤在同一条纵向列表里：比赛详情把赛道、天气、赛程、状态串在一起；成绩页只有一张表；积分页只有排名。数据层已经提供天气、Race Control、圈速/分段、进站、轮胎 stint、位置变化、遥测与赛季走势，但界面没有承接这些信息。

v2 的四个变化：

1. **窗口从 480 × 640 扩到 560 × 720**。宽度增加 17%，可以放下双列卡片；高度增加 12.5%，首页首屏能同时看到下一节、天气与周末时间线。
2. **一级导航带文字标签**，下面增加**二级标签**。不再靠四个图标猜内容；每页内部按“概览 / 明细 / 分析”分层。
3. **列表页 → 主从布局**。赛历左侧列表、右侧选中赛道预览；成绩与积分支持行内展开，再进入完整详情页。
4. **详情页独立**。比赛、Session、车手各有自己的下钻页，用返回栈而不是继续往下堆卡片。

## 导航结构

```text
Popover 560 × 720
├─ Header：品牌 / 连接状态 / 刷新 / 设置
├─ Primary tabs：比赛 · 赛历 · 成绩 · 积分
├─ Context strip：赛季 · 分站 · Session · 数据新鲜度
├─ Content
│  ├─ 比赛
│  │  ├─ 概览：下一节倒计时 / 赛道 / 天气 / 周末时间线 / 最新成绩 / 积分领先
│  │  ├─ 周末：按天分组的 Session 列表 → Session 详情
│  │  ├─ 天气：逐节预报 / 空气与赛道温度 / 降雨概率 / 风
│  │  └─ 分析：Race Control / 位置变化 / 圈速
│  ├─ 赛历
│  │  ├─ 列表：已结束 / 前瞻分组，轮次、赛道剪影、日期、状态
│  │  ├─ 地图：赛季地图与分站定位
│  │  └─ 比赛详情：Overview / Weekend / Weather / Analysis
│  ├─ 成绩
│  │  ├─ Session 选择：Race / Qualifying / Sprint / FP
│  │  ├─ 领奖台 + 分类表（行内展开：分段 / 轮胎 / 进站 / 极速）
│  │  ├─ 车手详情：圈速图 / stint / 进站 / 遥测
│  │  └─ Session 分析：圈速 / 赛道 / 策略 / 赛事
│  └─ 积分
│     ├─ 车手 / 车队
│     ├─ 前三名概览 + 积分表 + 近五场状态
│     ├─ 选中车手走势卡 → 车手详情 / 赛季分析
│     └─ 赛季分析：累计积分 / 名次热力 / 车队对比
└─ Live strip（进行中时出现）→ Live Island
```

## 页面规格

### 1. 比赛 · 概览

- 首屏 3 个模块：
  - **Next Session 卡**（520 × 200）：Session 类型、倒计时 44–48 pt、日期时间、赛道名；右侧赛道轮廓。
  - **天气 2 × 2**：空气温度、赛道温度、降雨概率、风速。每格 254 × 76，带趋势箭头。
  - **周末时间线**：5 个 Session 节点横向排列，当前节点用朱红描边；下方显示各节本地时间与状态。
- 第二屏：最新成绩（前三行 + “全部成绩”）、积分领先（P1/P2/P3 + 差距）。
- 进行中时，底部工具条上方浮出 Live strip：P 位、差距、圈数、展开按钮。

### 2. 赛历 · 主从布局

- 顶部：赛季切换、列表/地图切换。
- 左侧 300 pt：按“已结束 / 前瞻”分组；每行 56 pt，包含轮次、国旗、分站名、日期、赛道剪影、状态。
- 右侧 208 pt：选中分站的赛道预览、日期、下一节、打开详情按钮。
- 选中行动画使用玻璃透镜，不做整行蓝色高亮。

### 3. 比赛详情

- 头部 150 pt：返回、国旗、分站名、地点/日期/轮次、打开地图。右侧淡赛道轮廓。
- 二级标签：概览 / 周末 / 天气 / 分析。
- 概览双列：
  - 左 300 pt：周末五个 Session，每行可点进 Session 详情。
  - 右 208 pt：天气摘要、Race Control 最新两条。
- 底部：成绩入口（有结果时显示前三）、赛道信息入口。
- “周末”标签按天分组；“天气”逐节显示温度与降雨；“分析”复用圈速/位置/Race Control 图表。

### 4. 成绩

- Session 选择器 + LIVE 状态。
- 领奖台三卡（P1/P2/P3）：头盔、姓名、车队、成绩/差距、积分。
- 分类表列：POS / 车手 / 差距 / 轮胎 / 积分。
- **行内展开**：选中行展开 140 pt，显示 S1/S2/S3、当前 stint（配方 + 圈数）、最近一次进站耗时、极速、迷你圈速图。
- 底部入口：“打开 Session 分析”进入圈速/策略/遥测。

### 5. 车手详情

- 头部：头盔 56、姓名、车队、P 位、积分、关注按钮。
- 三个指标卡：最快圈、平均圈、极速。
- 圈速图：按 stint 背景分带，进站用垂直标记。
- Stint 时间线：配方色块 + 起止圈。
- 进站列表：圈数、耗时、进站损失。
- 遥测卡：速度 / 油门 / 刹车。
- Race Control 提及与处罚。

### 6. 积分

- 车手/车队切换；赛季与轮次上下文。
- 前三名三列大卡：名次、头盔、姓名、积分、胜场、较上一轮变化。
- 表格列：POS / 车手 / 积分 / 胜场 / 近五场。
- 选中车手后，在表格下方显示该车手的赛季累计积分折线与“车手详情”入口；积分表本身不做行内展开，避免与成绩页的展开行重复。

### 7. Live Island

- 尺寸 860 × 540，双列：
  - 左 540：模式标签（Timing / Gap / Tyres / Race Control / Map）、计时塔、底部 mini map。
  - 右 280：关注车手卡（P 位、差距、轮胎、能量、S1–S3、最近五圈）、Race Control 滚动条。
- 计时塔保留现有固定列宽，避免高频刷新抖动。
- 展开、收起、切换模式均使用一次弹簧；开启减弱动态效果时改交叉淡入。

## 组件清单

`ContextHeader`、`PrimaryTabBar`、`SubTabBar`、`MetricTile`、`SessionRow`、`CircuitMiniMap`、`WeekendTimeline`、`PodiumStrip`、`TimingTable`、`ExpandableTimingRow`、`StintBar`、`LapChart`、`LiveStrip`、`DataFreshnessPill`、`EmptyState`、`StaleBanner`。

## 数据映射与诚实边界

| 模块 | 数据来源 | 备注 |
| --- | --- | --- |
| 下一节倒计时 | `Meeting.sessions` + `CalendarLogic` | 本地时区显示 |
| 天气格 | `/meetings/{id}/weather` | 未开赛且无预报时显示“尚无预报”，不伪造 |
| Session 状态 | `Session.status` | 已结束赛事不显示历史天气 |
| 成绩分类 | `SessionResult` | 未分类名次显示 “—”，不补 0 |
| 行内分段 / 轮胎 | `SessionAnalysis.laps` / `stints` | 缺字段显示“未提供” |
| 进站 | `AnalysisPit` | 区分 pit lane 与停车耗时 |
| 圈速图 / 遥测 | `AnalysisLap` / `AnalysisTelemetry` | 出站圈保留原值，不补零 |
| 位置变化 | `AnalysisPosition` | 只画有采样点 |
| Race Control | `AnalysisEvent` | 保留原文与时间 |
| 积分走势 | `SeasonAnalysis.cumulativePointsByRound` | Sprint 与正赛分开统计 |
| 近五场 | `AnalysisRound.entries` | 缺项显示灰色，不用 DNF 代替未知 |

不在界面中显示后端没有的“赛道长度 / 弯道数 / DRS 区”等静态资料，除非后续接入可信来源。

## 实施顺序

1. 壳与导航：`MenuBarRootView` 改 520 × 700 菜单栏尺度，一级文字标签 + 二级标签容器。
2. 比赛概览：Next Session、天气格、周末时间线。
3. 赛历单列列表，点行进入详情。
4. 比赛详情与 Session 详情。
5. 成绩表行内展开 + 车手详情。
6. 积分概览与走势。
7. 无障碍与性能验收：降低透明度、增强对比度、减弱动态效果、玻璃层数 ≤ 5、列表滚动不掉帧。

## 验收

- 520 × 700 下首屏可见下一节、天气与时间线，不出现三张以上卡片挤压。
- 比赛详情不再需要一条长滚动才能看到周末赛程。
- 分类表展开行后，列宽不跳动；计时数字等宽。
- 所有缺失数据有明确空态，不用 0 或虚构值占位。
- 浅色/深色、三种桌面背景下文字对比度 ≥ 4.5:1。

## 落地记录（2026-11-11）

已在独立 worktree `worktree-macos-liquid-glass` 中完成第一轮实现，未触碰主工作区的 mobile 分支。

| 页面 | 实现文件 | 要点 |
| --- | --- | --- |
| 壳与导航 | `macos/Features/MenuBar/MenuBarRootView.swift` | 540 × 740、`menubar-mark` 品牌标、纯图标 Liquid 切换器（house / calendar / trophy / person.3）、右下角刷新/设置/退出玻璃按钮行；`PitPulseTheme` / `GlassCard` 统一使用 `.glassEffect` |
| 比赛 | `macos/Features/Calendar/NextMeetingCard.swift` | 下一节大倒计时、周末时间线、气温/降雨/风速三格、赛道地图按需展开、积分领跑；天气只读 `/meetings/{id}/weather` |
| 赛历 | `macos/Features/Calendar/CalendarView.swift` | 单列分组列表（待开始 / 已结束）；待开始行加高，显示赛道、Session 数与下一节倒计时；已结束行保持紧凑 |
| 比赛详情 | `macos/Features/Calendar/MeetingDetailView.swift` | 概览 / 周末 / 天气 / 分析四个二级标签；概览双列；Race Control 只显示实时快照 |
| 成绩 | `macos/Features/SessionResults/SessionResultsView.swift` | 金字塔领奖台（P1 大卡居中、P2/P3 下方两卡）、分类表；点行进入独立车手页，页内先显示最终成绩与本场关键数据，再进入 `SessionAnalysisView` |
| 积分 | `macos/Features/Standings/StandingsView.swift` | 与成绩一致的金字塔前三、积分表、选中项赛季累计折线；`SeasonAnalysis` 缺场次时明确标注 |
| Live Island | 未改动 | 按需求回滚，Notch / Live Island 保持原实现，不在本轮范围 |

### 第二轮调整（2026-11-11，按 9 点反馈）

1. 移除页头与页脚的全部“在线 / 连接状态”标记，只在刷新时显示进度。
2. 移除所有“数据详情”折叠区（`MetadataDisclosure` / `DataProvenance`）。
3. 赛历分组改为“待开始 / 已结束”；待开始行加高，增加赛道、Session 数、下一节与倒计时条。
4. 成绩领奖台改为金字塔：P1 头盔大卡居中，P2/P3 在下方左右排列。
5. 成绩行点击改为进入独立车手页（不再行内展开），页内含最终成绩、本场关键数据与完整分析。
6. 积分前三改为同样的金字塔布局。
7. 刷新、设置、退出三个按钮集中到右下角一行，使用更大的 Liquid 玻璃按钮（退出为朱红强调）。
8. 所有卡片、分段控件、返回/关注按钮、Live strip 统一使用 `.glassEffect` / `GlassEffectContainer`。
9. 顶部切换器改为大号纯图标 Liquid 切换器，仅保留 house、calendar、trophy、person.3 四个 SF Symbol，文字只保留在无障碍标签里。

### 第三轮调整（2026-11-11）

- 弹层内车手图像统一使用头盔资产（`f1HelmetImage`），不再回退到官方人像；缺少头盔素材的车手（如 Rafael Câmara）显示中性 `helmet.fill` 图标占位，仍不显示人像。需要补头盔素材才能显示其真实头盔。
- 成绩页与积分页使用同一套金字塔：P1 卡高度、字号与信息层级一致；P2/P3 卡片改为头盔在上、名次/姓名/成绩/积分垂直堆叠。
- 新增 `LiquidSegmented` 共享组件，替换分析页的一级分段、赛道颜色选择器与比赛详情二级标签；`AnalysisCard` 标题改用统一的 `CardHeader` 排版。
- 金字塔改为无底色叠压结构：三张车手卡不使用任何背景色、渐变、描边或 hover 效果；P1 与 P2/P3 行、P2 与 P3 之间使用负间距让框体相互重叠并进一步收紧，下方两张卡整体向内收；P2/P3 放大头盔，只保留名次、姓名、积分（成绩页同样去掉用时行），不再显示胜场与差距。
- 顶部切换器改为单条 Liquid Glass Tab 栏（iOS 样式）：一个连续玻璃胶囊，选中项使用 `matchedGeometryEffect` 的滑动玻璃透镜，图标在选中时切换为 filled 变体。

验证方式与边界：

- 本机 Taskdeck daemon 不可用，`xcodebuild` 在 Claude 会话的嵌套沙箱中无法启动（package manifest 与 DerivedData 均被拒绝）。因此改用 `swiftc -disable-sandbox` 对 `PitPulseShared` / `PitPulseData` / `PitPulseComponents` / Nook 模块与 18 个 App 源文件做全量类型检查，当前通过。
- 第二轮调整后通过 `bash scripts/xcode-task.sh build Debug` 在沙箱外完成真实 Debug 构建（`** BUILD SUCCEEDED **`），并在 worktree 产物上重启 App。
- 构建成功不替代真实运行、截图、VoiceOver 与滚动性能验收；Popup 视觉、`Test App` / `Build App Tests` 仍需在沙箱外完成。
- 未新增后端字段；缺失的赛道长度、弯道数、DRS、历史天气与逐站近五场均保持“未提供”，不用 0 或编造值填充。
