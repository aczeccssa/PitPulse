# PitPulse App Logo

简约的「赛道形 P」：前倾的粗线条表达速度，上方回转与内部斜切口呼应赛道和实时计时。朱红主体搭配石墨黑底；不使用赛事官方标识、车队标识或 SF Symbols。

## 文件

| 文件 | 用途 |
| --- | --- |
| `logo-foreground.png` | 独立 Logo 主体，RGBA，真实透明背景和透明镂空 |
| `background.png` | 独立石墨黑背景，RGB，全画布不透明 |
| `app-icon-preview.png` | 正视的合成图标预览，无设备或样机场景 |
| `pitpulse-layered.svg` | 同画布叠放的背景、主体两个命名组；内嵌原始 PNG，可分别隐藏或替换 |
| `menubar-mark.png` | 菜单栏专用紧凑主体：按 alpha 可见边界裁掉空画布，743 × 625 RGBA |
| `prompts.json` | 最终采用的完整生成提示词与透明背景设置 |
| `asset-checks.json` | 实际图片尺寸、颜色模式与透明通道检查结果 |

三个 PNG 均为 **1254 × 1254 px**。背景和前景按画布原点 `(0, 0)`、100% 尺寸叠放，不要单独裁切前景的透明留白。主体没有烘焙底板或投影，可独立放在其他背景上。

`pitpulse-layered.svg` 是包含两个位图图层的 SVG 容器，**不是纯矢量路径稿**。它直接引用内嵌的原始像素，是准确的分层组合；`app-icon-preview.png` 是 imagegen 的合成预览，像素不保证与直接叠图完全一致。

这些设计源保留完整方形画布。用户确认后，App 接入使用 `Packages/SharedComponents/Resources/AppIcon.icon/`，由 Xcode 处理系统图标轮廓；server 的 favicon 来自同一原生图标导出。接入说明见 `docs/acceptance/branding.md`。

## 菜单栏紧凑版

- `menubar-mark.png` 只裁切、不重绘：从 `logo-foreground.png` 取 alpha ≥ 8 的可见边界并外扩 1 px 抗锯齿边（原画布 `1254 × 1254` → `743 × 625`），透明背景与主体内部镂空保持不变。
- 菜单栏只有 24 pt 高，外层间距由系统添加，不能沿用 App 图标的方形画布留白。本次导出把主体内容定高 16 pt、宽 19.02 pt，居中放进 20 × 18 pt 画布：左右各 0.5 pt（2.5%）、上下各 1 pt（5.6%），可见内容约占画布高度的 89%。
- `macos/Resources/PitPulseAssets.xcassets/MenuBarIcon.imageset` 按 1x/2x/3x 导出 20 × 18 / 40 × 36 / 60 × 54 px，并设置 `template-rendering-intent: template`，菜单栏按 alpha 单色渲染，自动适配浅色、深色与菜单栏着色。
- 参照值：macOS 菜单栏高 24 pt；系统模板图标按 18 pt 绘制，可见内容通常 16–18 pt；相邻状态项之间由系统再补约 4–6 pt。素材内部留白超过可见内容的 15% 就会显得图标偏小。

## 生成与检查

使用内置 **imagegen** 工具生成主体、背景与合成预览，保留原始输出，不通过脚本抠图或修改生成像素。SVG 只包装两个原图层。

- 主体 alpha 范围为 0–255，四角全透明，透明像素共 1,344,988 个；背景与预览均不透明。
- 三个 PNG 可完整解码，画布尺寸一致；SVG 可解析。
- 已目视检查主体和合成预览，轮廓与内部斜切清晰，无文案或第三方标志；不将设计文件检查视为真实 Dock、菜单栏或 App 运行验收。
- 当前 `taskdeck.yaml` 仅提供 `Run App` / `Run Server`，未提供 `Check Task Report`，因此任务记录使用直接命令 `node docs/tasks/validate.mjs` 和 `node --test docs/tasks/tests/task-data.test.mjs` 校验。
