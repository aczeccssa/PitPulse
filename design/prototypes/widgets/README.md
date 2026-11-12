# PitPulse 小组件概念 · App 视觉体系版

日期：2026-11-12
范围：16 个 iOS 主屏组件概念，**不含实时计时 / Live 组件**，不与灵动岛 Live Activity 抢职责。
本版按 PitPulse iOS App 与 macOS Liquid Glass 规范重做；上一版 `set16-*.png` 保留为探索稿。

## 为什么重做

上一版用了黑卡、全大写粗标题、整条车队色和紫色高亮。这些元素不在 App 的视觉系统里，放在主屏上会像另一个产品。

App 实际的样子（`app-style/reference/`，模拟器实拍：总览 / 赛历 / 积分）：

- 背景 `systemBackground`，内容卡 `secondarySystemGroupedBackground`，20 pt 连续圆角，8% 发丝描边，16 pt 内边距（`PulseCard`）。
- 红色只做三件事：9 pt `PITPULSE` 字标、`F1 · R21` eyebrow、选中行 / 数据强调；不做大面积填充。
- 标题用 sentence case 的 SF Pro，不使用全大写展示字体；计时、积分、差距全部等宽数字。
- 车队色只出现在头盔与队徽素材里，不画整行色条；紫色只属于计时 / 轮胎语义。
- 层次靠发丝线、留白和轻微环境阴影，不靠重阴影或黑底反白。

新 16 个概念全部复用这套 token，并把 App 已有的头盔、队徽、赛道轮廓、红色面积图直接放进组件。

## 视觉 Token（以代码为准）

| 项目 | 取值 | 来源 |
| --- | --- | --- |
| 强调色 | `PulseStyle.red`：浅色 ≈ `#C71412`，深色 ≈ `#FA403B` | `PitPulseMobileApp.swift` |
| 卡片底 | `secondarySystemGroupedBackground` | `PulseCard` |
| 画布底 | `systemBackground` | `PulseStyle.background` |
| 描边 / 分隔 | `primary` 8% / 4–8% | `PulseStyle.border`、现有组件 |
| 选中底 | 品牌红 10% | 积分榜选中行 |
| 圆角 | 卡片 20 pt，控件 14 pt，胶囊全圆 | `PulseCard`、Liquid Glass 规范 |
| 字标 | 9 pt heavy，字距 1.6，品牌红 | `WidgetHeading` |
| 标题 | SF Pro 15–18 pt semibold / bold，sentence case | App 页面 |
| 数据 | `monospacedDigit`；倒计时 / 大数字用 SF Rounded bold | `RaceCountdown`、赛历轮次 |
| 素材 | SF Symbols、头盔、队徽、2.5 pt 赛道轮廓 | App 现有组件 |
| 玻璃 | 仅用于浮动层（标签栏、胶囊、Dock），内容卡保持实底 | iOS 26 / Liquid Glass 规范 |

**不要**：黑卡、全大写展示标题、车队色整条、紫色装饰、霓虹、厚重投影。

## 交付图

| 文件 | 概念 |
| --- | --- |
| `app-style/set-a.png` / `set-a-dark.png` | 01–04 下一场（2 小 + 2 中），浅色 / 深色 |
| `app-style/set-b.png` / `set-b-dark.png` | 05–08 周末与单节，浅色 / 深色 |
| `app-style/set-c.png` / `set-c-dark.png` | 09–12 积分榜，浅色 / 深色 |
| `app-style/set-d.png` / `set-d-dark.png` | 13–16 赛后与赛季，浅色 / 深色 |
| `app-style/overview.png` | 16 个概念浅 / 深对照总览（1680 × 2620） |
| `app-style/contexts.png` | 三个主屏情境：赛前 / 积分 / 赛后（1800 × 1280） |
| `app-style/home-screen-light.png` | 周末主屏情境 · 浅色（大 + 中） |
| `app-style/home-screen-dark.png` | 周末主屏情境 · 深色（大 + 中） |
| `app-style/home-next-race.png` | 赛前主屏：双时区 + 倒计时 + 赛道 |
| `app-style/home-standings.png` | 积分主屏：赛季走势 + 车手前五 |
| `app-style/home-post-race-dark.png` | 赛后主屏 · 深色：领奖台 + 比赛数字 |
| `app-style/reference/tab0.png` 等 | App 真实界面参考（总览 / 赛历 / 积分，浅色） |

深色版不是简单反相：卡片为 graphite `#1C1C1E`，描边为白色 10%，强调色 `#E0242C`，赛道轮廓与时间轴改用白色；选中行仍是暗红 20% 底 + 红色引导线。所有主屏情境都保留 App 的实底卡片，玻璃只出现在 Dock / 浮动层。

概念图用 Magpie 生成，仅用于评审，不是可切图资源；英文文案用于保证字形可读，正式界面继续使用现有中文文案。

## 16 个概念

### 01–04 下一场

| # | 尺寸 | 名称 | 内容 | 数据 |
| --- | --- | --- | --- | --- |
| 01 | small | 倒计时 | 赛事名、`8` 天倒计时、FP1 时间，淡赛道线稿水印 | 现有 |
| 02 | small | 赛道线稿 | 赛道轮廓 + 站名 + 日期 | 现有 + 轮廓缓存 |
| 03 | medium | 周末时间线 | 赛事信息 + 五节点横轴，当前节点红环，RACE 红标 | 现有 |
| 04 | medium | 双时区 | 你的时间 / 赛道当地时间并排，中间发丝线 | 需新增赛道时区 |

### 05–08 周末与单节

| # | 尺寸 | 名称 | 内容 | 数据 |
| --- | --- | --- | --- | --- |
| 05 | medium | 三日分栏 | FRI / SAT / SUN 三栏，正赛红色强调 | 现有 |
| 06 | large | 周末总表 | 三个日期胶囊 + 五节列表，RACE 行红底红杠 | 现有 |
| 07 | small | 下一节 | 节次、时间、浅红胶囊倒计时、细进度线 | 现有 |
| 08 | medium | 排位结果 | Q3 前三、头盔、杆位时间红色 | 需新增单节结果快照 |

### 09–12 积分榜

| # | 尺寸 | 名称 | 内容 | 数据 |
| --- | --- | --- | --- | --- |
| 09 | small | 车手榜首 | 头盔、姓名、积分、红色面积走势 | 需新增积分榜快照 |
| 10 | medium | 车手前五 | 名次 / 头盔 / 车队 / 积分 / 与榜首差，P1 红底 | 需新增积分榜快照 |
| 11 | medium | 车队前三 | 队徽、积分、细红进度条 | 需新增积分榜快照 |
| 12 | large | 赛季走势 | 两人积分与头盔、红 / 石墨双折线、胜场与台数 | 需新增赛季分析快照 |

### 13–16 赛后与赛季

| # | 尺寸 | 名称 | 内容 | 数据 |
| --- | --- | --- | --- | --- |
| 13 | large | 上站领奖台 | P1–P3 头盔与成绩、最快圈 / 圈数 / 安全车 | 需新增比赛结果快照 |
| 14 | medium | 比赛数字 | 圈数 / 进站 / 安全车 / 最快圈，2×2 发丝网格 | 需新增比赛结果快照 |
| 15 | medium | 未来三站 | 轮次、国旗、站名、日期、浅红倒计时胶囊 | 现有 |
| 16 | small | 赛道信息 | 赛道轮廓、长度 / 圈数 / 弯数 | 需新增可信静态数据 |

## 落地建议

首发 5 个：**03、06、10、13、15**。

- 覆盖赛前时间线、完整周末、积分、赛后结果、未来赛程五种场景。
- 03、06、15 只用现有 `RaceWidgetSnapshot`，可以先做。
- 10、13 需要给 `WidgetSnapshotPublisher` 增加 standings / lastResult 快照，沿用 6 小时 stale 语义。
- 16 的赛道长度 / 弯数目前后端没有可信来源，未接入前不要显示，避免伪造数据。
- 08、11、12、14 作为第二批；02、04、07 作为尺寸补齐。

## 已落地（2026-11-12）

iOS 组件包最终保留 6 种、15 个尺寸组合：

| 组件 | 尺寸 | 概念 |
| --- | --- | --- |
| 比赛周末 | small / medium / large | 小尺寸最近场次，中尺寸按场次分栏（恢复原样），大尺寸三日胶囊 + 五节总表（06） |
| 车手积分 | small / medium | 09 车手榜首 / 10 车手前五 |
| 我的车手 | small / medium / large | 收藏车手的排名与积分 / 上站明细与近三场 / 近三场明细与赛季数据 |
| 上站结果 | medium / large | 中尺寸领奖台 + 比赛数字 / 13 大尺寸完整领奖台 |
| 未来三站 | small / medium | 下一站倒计时 / 15 未来三站 |
| 下一场 | small / medium / large | 原有组件，未改动 |

- 移除 iOS 的 `实时计时` 组件（small / medium / large）；实时计时继续由 Live Activity 承担，macOS 组件包保持不变。
- `Shared/Widgets/RaceWidgets.swift`：比赛周末中尺寸回滚为原来的场次分栏；大尺寸保留 06 总表；新增车手积分小尺寸、上站结果中尺寸、未来三站小尺寸，以及对应的 Provider 空态和过期状态。
- `Shared/Widgets/WidgetSnapshotPublisher.swift`：新增 `publishStandings`、`publishFavoriteDriver`、`publishLastRace`，并在 `publishCalendar` 内发布未来三站；清空与 6 小时 stale 语义保持一致。我的车手读取收藏车手的积分排名，以及最近三场正赛的个人成绩（名次、积分、最快圈、差距/成绩）。
- `Packages/PitPulseShared/Sources/PitPulseShared/Shared.swift`：新增 `StandingsWidgetSnapshot`、`LastRaceWidgetSnapshot`、`UpcomingWidgetSnapshot` 及各自缓存键/kind。
- `ios/PitPulseMobile/MobileModel.swift`：车手积分加载后发布 standings；赛历加载后读取最近三场已结束正赛的结果，发布领奖台与我的车手数据；收藏车手变化时用已有缓存重新发布，不重复请求。
- `ios/PitPulseLiveActivity/PitPulseLiveActivityBundle.swift`：注册 `StandingsWidget`、`FavoriteDriverWidget`、`LastRaceWidget`、`UpcomingWidget`，不再注册 `LiveTimingWidget`。
- 组件扩展仍然不联网；所有内容来自 App Group 缓存。

实现截图（模拟器、真实缓存、浅色 / 深色）：`docs/acceptance/assets/widget-impl-20261112/`。

上站组件的最快圈与领奖台来自比赛结果；安全车数量需要较重的 analysis 包，当前实现不额外下载，缺失时改显示冠军积分，避免为了一个数字拉取全场遥测。

## 落地约束

- Widget Extension 不做网络请求；所有数据沿用 App Group 缓存与 `savedAt` / stale 标记。
- 赛道轮廓必须在扩展内可离线绘制：缓存简化后的 path points 或打包静态 SVG，不在时间线里请求服务器。
- 卡片一律 `containerBackground` 适配浅 / 深色；不要自带壁纸或固定白底。
- 缺失数据显示明确空态，不用 0 或虚构值；回放与过期继续显示状态标签。
- 中文站名与车手名比英文长，落地时按 CJK 字宽重新检查换行与截断；概念图中的英文仅用于评审。
- 不使用官方 F1 / 车队 Logo 新素材；头盔与队徽继续使用仓库已有资产。

## 未完成 / 边界

- 08、11、12、14、02、04、07、16 尚未实现；09 已作为车手积分小尺寸落地，14 的信息已并入上站结果中尺寸；12 需要赛季走势数据，16 仍缺可信的赛道长度 / 弯数来源。
- 概念图中的赛道形状为近似示意，正式实现使用服务器 geometry。
- 图中数据为示例：Las Vegas R21 使用预览 fixture，积分与 São Paulo 结果用于验证信息密度，不代表真实赛季。
- 上站组件的安全车数字暂不显示；等后端提供轻量比赛摘要后再接入。
