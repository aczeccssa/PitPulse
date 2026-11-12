# PitPulse · macOS 26 Liquid Glass 界面概念

日期：2026-11-11
范围：macOS 菜单栏 App 的视觉重设计概念，不含 SwiftUI 实现。

> 本目录是第一轮“同一版式的材质重绘”，保留为色彩、玻璃与字体基线。
> 整体布局重做（560 × 720、文字导航、二级标签、主从列表与详情下钻）见 [`v2/README.md`](v2/README.md)。
参考：用户提供的当前比赛详情截图（`MeetingDetailView`）、`MenuBarRootView`、`NextMeetingCard`、`SessionResultsView`、`LiveIsland.swift`，以及 `design/brand/pitpulse-v1/`。

概念图使用 Magpie（`routin/gpt-image-2.6-flare`）生成，以当前截图作为布局参考、以品牌图标作为 Logo 参考。图中的英文文案仅用于保证生成字形的可读性；正式界面继续使用现有中文文案，布局需按 CJK 字宽重新核对。

## 交付图

| 文件 | 页面 | 对应代码 |
| --- | --- | --- |
| `calendar-detail-light.png` | 赛历 → 比赛详情（浅色） | `CalendarView.detailHeader` + `MeetingDetailView` |
| `calendar-detail-dark.png` | 赛历 → 比赛详情（深色） | 同上 |
| `next-race-light.png` | 比赛 → 下一站倒计时（浅色） | `NextMeetingCard` |
| `results-dark.png` | 成绩 → 正赛结果（深色） | `SessionResultsView` |
| `standings-light.png` | 积分 → 车手积分榜（浅色） | `StandingsView` |
| `live-island-dark.png` | Live Island 展开态（深色，860 × 490） | `LiveIsland.swift` |

六张图均为 1024 × 1536（Live Island 为 1536 × 1024），可直接作为设计评审稿；它们不是 App 资源，也不应打包进 Target。

## 设计方向

1. **玻璃只负责“浮起来的层”**：窗口、选中标签的透镜、底部工具条、Live Island 使用 Liquid Glass；长列表和正文放在稳定的内容层上。这样 11–13 pt 中文在赛道照片背景上仍然可读，也符合 Apple 对玻璃“导航与控制层”的定位。
2. **单一强调色**：PitPulse 朱红 `#D6202A`（深色态 `#E0242C`）。车队色只保留 2 px 发丝线；紫/绿/黄只用于计时段与轮胎语义，不做大面积填充。
3. **同心圆角**：窗口 28 pt，卡片 20 pt，控件 14 pt，胶囊全圆。所有内嵌卡片与父容器同圆心。
4. **用亮度与描边分层，而不是堆阴影**：每层玻璃一条 1 px 内侧高光（顶部偏左最亮）、一层大范围低透明度环境阴影；避免多层重阴影把界面压灰。
5. **数字优先**：计时、差距、倒计时全部使用等宽数字并右对齐；数值变化用 `contentTransition(.numericText())`，不整行跳动。
6. **动效克制**：标签切换时选中透镜在容器内移动（约 0.28 s 弹簧）；Live Island 展开用一次弹簧；开启“减弱动态效果”时改为交叉淡入。

## 设计 Token

### 颜色

| 用途 | 浅色 | 深色 |
| --- | --- | --- |
| 强调色 | `#D6202A` | `#E0242C` |
| 窗口玻璃 | 白 62%（叠系统 vibrancy） | 石墨 `#18181B` 66% |
| 内容卡片 | 白 38% + 白 55% 内描边 | 白 4.5% + 白 10% 内描边 |
| 主文字 | `#1C1C1E` | `#F5F5F7` |
| 次文字 | 主文字 60% | 主文字 60% |
| 分隔线 | 黑 8% | 白 10% |

语义色沿用系统色：绿 `#34C759`、黄 `#FF9F0A`、紫 `#BF5AF2`、红 `#FF453A`。玻璃上的文字不要依赖模糊后的背景取色，正文对比度按 4.5:1 复核。

### 字体

- 页面标题：SF Pro Display Semibold 30–32 pt，字距 −0.4。
- 卡片标题：SF Pro Text Semibold 15–17 pt。
- 正文/列表：13 pt；说明文字 11 pt。
- 计时与倒计时：SF Pro Rounded / SF Mono 等宽数字；倒计时 30–36 pt，差距 12–13 pt。
- 分区标题：11 pt Semibold，全大写，字距 +1.2。

### 间距与尺寸

- 4 pt 网格；窗口左右内边距 16 pt，卡片内边距 14–16 pt。
- 列表行高 38–44 pt；比赛周末行 44 pt。
- 菜单栏弹窗维持 480 × 640 pt；Live Island 展开 860 × 490 pt。
- 图标按钮 30 × 30 pt；标签项高度 36 pt。

## SwiftUI 落地建议

工程 `MACOSX_DEPLOYMENT_TARGET = 26.0`，无需 `#available` 分支。API 名称以当前 Xcode 26 SDK 为准，下面是结构建议而非已验证代码。

```swift
@Namespace private var glass

GlassEffectContainer(spacing: 10) {
    HStack(spacing: 4) {
        ForEach(MenuBarRootView.Section.allCases) { item in
            tabButton(item)
                .glassEffect(
                    section == item ? .regular.interactive() : .clear,
                    in: .rect(cornerRadius: 11)
                )
                .glassEffectID(item, in: glass)
        }
    }
}
```

- 顶部刷新/设置、底部信息/更多：`.buttonStyle(.glass)` + `.buttonBorderShape(.circle)`，保留现有 `accessibilityLabel` 与 `help`。
- 标签栏保留“仅图标 + tooltip”的现方案；选中态不要再用 `Color.accentColor` 实心填充，改为玻璃透镜。
- 滚动内容从玻璃头部下方穿过时使用 `backgroundExtensionEffect()` 与顶部 scroll edge effect；不要给每个 `ForEach` 行单独加玻璃。
- 当前 `MenuBarRootView` 的 `Color(nsColor: .windowBackgroundColor)` 是不透明底，会杀死透视。改造时让弹窗背景透明，交给系统 popover material；Live Island 的 `NSPanel` 需要 `isOpaque = false` 且 `backgroundColor = .clear`，再用 `NSGlassEffectView` 作为底层。
- 菜单栏弹窗本身已有一层系统材质，再叠 `glassEffect` 容易发灰；先做一层玻璃，只有浮在内容之上的控件再加第二层。
- `Circle().fill(.quaternary)` 的占位头像可以保留；车队色只画 2 pt 左边线，不染整行。
- Live Island 表格列宽已固定（Gap/Interval 58、上一圈/最佳圈 76、扇区自适应）。玻璃化不要改变这些列宽，否则高频刷新时会抖动。

## 验收清单

- 浅色/深色、降低透明度、增强对比度、减弱动态效果四种系统设置下均可用。
- 在 480 × 640 内确认 5 行周末赛程不截断；中文 GP 名称与英文长名都能尾部省略。
- 外接显示器与缩放分辨率下检查 1 px 描边不消失、圆角不发毛。
- 玻璃上 11 pt 次要文字对比度 ≥ 4.5:1；不能只靠颜色区分完赛/进行中状态。
- 真实照片、纯色桌面、浅色桌面三种背景下都能看清窗口边界。
- Live Island 展开/收起时命中区域正确，点击不穿透到下层窗口。

## 未完成 / 边界

- 仅视觉概念，没有修改任何 SwiftUI 视图，也没有替换图标或字体资源。
- 图中的赛道轮廓是生成示意，正式界面继续使用现有地图/赛道数据与素材。
- 图中英文文案不代表最终本地化；中文文案、日期格式与时区显示仍以现有代码为准。
- 生成图只用于评审，不作为可切图的 UI 资源；落地时需要按上述 Token 在 SwiftUI 中重建。
