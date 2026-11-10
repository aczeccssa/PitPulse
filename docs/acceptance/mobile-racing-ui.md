# Mobile UI — PP-40

实现分支 `codex/mobile-racing-ui`，YouTrack [PP-40](https://lestere-dev.youtrack.cloud/issue/PP-40)。本轮交付与提交记录 [PP-41](https://lestere-dev.youtrack.cloud/issue/PP-41)。当前进度仅维护于 `docs/tasks/tasks.json` 的 T27。以下说明最终设计；旧截图保留用于追踪，不能作为新设计验收依据。

## 当前实现

- 四个纯图标 tab：下一场总览、赛历、车手积分（奖杯）、车队积分（团队）。P logo 打开原生设置 sheet。
- 总览显示下一场真实赛事、对应赛道 GeoJSON 轮廓、倒计时、周末场次、收藏车手。移除 Las Vegas 的 McLaren 与周末页无关 Ferrari 赛车图。
- 赛历对照用户 HEIC：大分站编号、国旗地点、赛事/日期、真实赛道轮廓、分隔线，回顾/前瞻标识；自动定位下一站。
- 收藏从服务器 F1 车手名单选择，保存在本地；Live、成绩、车手积分用现有头盔，姓名下方为车队标识。资产缺失使用占位，未扩充图片。
- App 与普通 Widget 使用系统语义颜色；App 可跟随系统或选择浅色/深色。
- 自动同时监听 F1/WEC。只将未结束且新鲜、含车手的活动场次作为候选；单场无切换入口，多场提示并提供切换。保持当前已选场次，结束/过期时自动选择其他活动赛事。
- Live 条放在 tab 上方，原生 zoom 动画展开全屏，可收起；计时差距、圈速、轮胎、赛会消息以及车手详情。车手详情展示实际采样速度/油门/刹车/分段。历史分析采用圈速曲线、分段堆叠、遥测、轮胎区间图，并轮询服务端异步分析状态。
- 积分榜分成两个 tab，选中对象展示真实赛季累计曲线；同分站冲刺与正赛先合并，缺失分数处不伪造累计。
- 灵动岛支持赛事总览、前排对比、喜欢车手三种内容；收藏车手不在当前赛事时明确说明。
- 三类 Widget：下一场、周末赛程、Live 计时。小尺寸聚焦摘要，中尺寸横向信息，大尺寸完整周末/差距图；支持锁屏附件尺寸。DEBUG 预览画廊编译同一套渲染器与 App Group 数据，便于在模拟器无法添加组件时检查布局。

## 固定资产与数据

Resource build phase 直接引用 `macos/Resources/PitPulseAssets.xcassets` 和现有品牌 PNG。没有生成、下载或扩充图像。赛道线来自已有自托管 geometry API。

客户端只访问自托管服务。F1 正常数据地址有 24 场、25 位车手、11 支车队；此前误恢复回放地址导致三类数据为空，已经修正。Widget 只读 App Group 的无凭证摘要；App 同步主动刷新，Live 缓存按 90 秒判断过期。

Live 验证使用实际比赛记录回放，界面明确标记“回放”，不证明当前上游正在比赛。ActivityKit 当前通过 App 进程更新，90 秒 staleDate；未增加 APNs，后台持续更新与签名真机仍须独立验收。

## 验证与证据

通过 Taskdeck `Build iOS`、`Test iOS`（12 项 XCTest：活动兼容/缓存/积分/时间戳/自动赛事选择/头盔映射）。最后检查结果见 T27 history。模拟器安装/启动用 simctl（配置未提供 Run iOS），原生交互与截图使用 Computer Use。

本轮原生操作已确认：P 设置 sheet；收藏菜单列出真实车手并选择 Norris，首页显示头盔/P6/246PTS；Live mini bar 展开 WEC 全屏并切换 F1；灵动岛选择喜欢车手；四个 tab 的对应页面通过启动诊断入口核对。最后一项不等价于点击 tab 的动效验收。测试收藏已恢复未选择，灵动岛恢复赛事总览。

新设计证据目录为 `assets/t27/navigation-rework/`：

- `calendar-light.png`：参考图列表、真实轮廓、回顾/前瞻、四个图标与 Live 条。
- `drivers-dark.png`：深色积分趋势，头盔及姓名下方车队。
- `teams-light.png`：浅色独立车队积分页。
- `settings-sheet.png`：收藏与灵动岛选项，无比赛系列设置。
- `live-light.png`：F1 回放全屏与实际差距图。
- `widget-next-large-light.png` / `widget-next-large-dark.png`：最终五场周末列表。
- `widget-schedule-large-dark.png` / `widget-schedule-medium-dark.png`：大小尺寸不同信息结构。
- `widget-live-large-light.png` / `widget-live-large-dark.png`：差距图主题对照（后续行头像修正以最终构建为准）。

组件预览截图仅证明共享渲染器在 App 内的结果。历史 `assets/t27/widget-small.png` 是实际桌面小组件；桌面全部类型/尺寸还未验收。模拟器原生坐标操作持续报 noWindowsAvailable / windowNotFoundAtPosition，Widget 系统选择行缺少可用无障碍目标，用户也无法操作；没有把预览冒充桌面验收。

旧 `calendar.png`、`standings.png`、Live Activity 演示图属于上轮设计；演示活动仅证明布局。签名真机、后台冻结、多设备显示和全部锁屏尺寸均未完成验收。

最终补充：普通 Live Widget 行改为头盔，车队标识在姓名下方，最后一次 Test iOS 仍为 12/0。`navigation-rework/live-expand-collapse.mp4` 是最终代码的 38 秒实际录屏，已抽帧核对展开/收起两端状态；`home-dark.png`、`live-dark.png` 记录深色页面。
