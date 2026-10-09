# T03 — 独立 Agent：车手头盔与车队 Logo 在线收集

> 日期：2026-10-08（Asia/Shanghai）
> 总计划：[`../../implementation-sequence.md`](../../implementation-sequence.md)
> 执行角色：独立素材研究 / 收集 Agent
> 优先级：P1，和 V1 开发并行；任何素材缺失不得阻塞 V1。
> 目标赛季：2026；不凭旧赛季记忆列出“当前完整阵容”。

## 1. 明确的任务

**自行上网查、搜索、核验并收集**：

1. 2026 赛季车队与车手名单的可靠来源及核对日期。
2. 每名已确认车手的**头盔图**（不是头像 / 半身照）。
3. 每支已确认车队的**Logo**（不是赛车 / 车库照片）。
4. 可用下载文件、出处、授权信息和缺失矩阵，供 SwiftUI 本地资源使用。

“已找到页面”“已找到直接图片”“已下载本机私用文件”“允许对外再分发”“已接入 App”必须分别记录。不能拿候选搜索结果当已下载图片，也不能把用户的本机私用范围写成通用开放版权。

**范围澄清（2026-10-09）：** 用户明确仓库只用于本人本机私人版本控制，允许将 T03 素材纳入本地 commit，不 push 到 GitHub、不公开发布或分发。按此范围收集本地文件，不再以取得对外发布许可作为前置条件；仍逐项记录来源和已知条款，`rightsStatus` 不得因用户用途说明或本地 commit 而伪改为 `approved`。如未来要 push、公开发布或分发，必须重新核验权利。

## 2. 允许写入的范围

```text
docs/assets/
  collection-report.md           # 名单、来源、覆盖统计、缺失与结论
macos/Resources/MotorsportAssets/
  manifest.json                  # 逐项来源 / 授权 / season / ID 映射
  private-local/                 # 仅供用户本机使用；不可视作发布素材或通用授权
  helmets/                       # 许可已确认的头盔本地文件（若有）
  team-logos/                    # 许可已确认的 Logo 本地文件（若有）
```

- 不修改业务代码、Xcode 工程、根任务计划、架构原文和已有无关文件。
- 用户已授权本地 commit；不 push、创建 PR 或公开发布；不是唯一在仓库工作的 Agent，不回滚其他人的改动。
- 私人本机文件放 `private-local/`，不自动进入对外发布 bundle；转换 `.xcassets`、明暗变体和构建设置由 T08 负责。
- 用户明确限定为本机私人使用时，实际下载的权利未明素材可放入 `private-local/` 并纳入本地版本控制，逐项记录来源、已知条款与权利状态；不进入对外 bundle。仅临时核验、无需保存在本机的候选放仓库外，不记为本地交付。

## 3. 检索与核验方法

1. 用当前官方名单建立覆盖表。优先 Formula 1、官方车队 / 车手站；交叉核对官方更新，记录日期。无法核对当前更换 / 替补时注明范围，不伪造最终阵容。
2. 头盔优先找官方车手 / 车队公开媒体页面、明确允许使用的媒体包、能核验作者与授权的 Wikimedia 文件页。
3. Logo 优先官方品牌 / 媒体包，其次明确授权文件页。品牌素材经常带 trademark / 使用规则，**版权与商标说明都要记录**；`personal use` 不等于可再分发。
4. 禁用付费墙绕过、认证绕过、盗链来源替代出处、搜索缩略图冒充原图；不将头像重新裁剪后称为头盔。
5. 2026 特殊站设计、旧赛季设计、通用头盔分别记录 applicability。找不到当前设计时可记旧图候选，但不能无标签替代。
6. 2026 车队名称 / 品牌可能变化，按稳定内部 ID 与 Provider alias 映射；名字、车号、数组顺序不是稳定键。
7. 下载前检查真实 MIME / 内容、文件尺寸、透明通道与背景；SVG 避免 scripts / 外链。PNG / WebP 可作为收集原文件，App 最终格式与 Asset Catalog 转换由 T08 决定。

## 4. manifest 最低字段

顶层包含 `schemaVersion`、`season`、`collectedAt`（RFC 3339 UTC）、`rosterSources`、`assets`。逐素材至少包含：

| 字段 | 含义 |
|---|---|
| `id` | 稳定内部车手 / 车队 ID；配合 `kind` 与 `season` 唯一 |
| `providerIds` | Jolpica / OpenF1 等已核实 alias；未核实则 null / pending，不猜 |
| `name` | 可读车手 / 车队名 |
| `kind` | `helmet` 或 `teamLogo` |
| `season` / `applicability` | 图的适用赛季、特殊站 / 通用 / 旧图限制 |
| `sourcePageUrl` | 能确认出处的页面，不只是图片 CDN |
| `sourceImageUrl` | 确认的原图 URL；只有候选则 null |
| `license` / `licenseUrl` | 许可名称 / 条款页；不明确为 `unknown`，不能写 assumed free |
| `rightsStatus` | `approved` / `needsReview` / `restricted` |
| `downloadStatus` | `notDownloaded` / `downloadedReference` / `downloadedApproved` / `missing` |
| `bundlePath` | 已确认许可本地文件的相对路径；待审 / 未下载为 null |
| `useScope` / `privateLocalPath` | 私人本机文件标 `privateLocalOnly` 并记录相对路径；它与 `bundlePath` / `shippingReady` 分离 |
| `sha256` | 已下载文件的真实 hash；未下载为 null |
| `notes` | attribution、商标、设计年份、格式、缺失原因与下一步 |

自定扩展字段允许，但必须在报告解释；不要只用一个 `completed: true` 混淆授权、下载和 App 接入。

## 5. collection-report 必须回答

- 哪份官方名单作为基准、何时访问、核验范围；名单未全面确认时明确说明。
- 车手 / 车队总数分别多少；头盔 / Logo 的候选、已下载、可打包、缺失数分别多少。
- 逐项来源与图片类型；任一未满足项都可追溯至 manifest。
- 缺图或授权待审的推荐 fallback：车手缩写、车队名 / 颜色；**不得用他人头盔或别队 Logo 顶替**。
- 可发布资产所需 attribution 与商标提醒；记录个人研究和对外分发边界，不做“全部素材无版权风险”承诺。
- 下载 / 验证命令、遇到的失败、仍需人工确认项，以及实际修改的路径。

## 6. 验收清单

- [ ] 实际联网检索并引用能核验的出处，访问日期明确。
- [ ] 当前赛季覆盖矩阵与名单基准可追溯；缺失保留，不虚构完整覆盖。
- [ ] manifest JSON 可解析；kind + id + season 无重复；已确认 Provider ID 对应正确。
- [ ] 头盔与头像、Logo 与照片分类正确；特殊版 / 旧赛季不冒充当前通用设计。
- [ ] 私人本机文件的 `privateLocalPath` 指向存在文件；sha256 与本地文件一致；`bundlePath` 仅用于对外已获准素材。
- [ ] 未知 / restricted 素材仅按用户指定的本机范围保存，不进入对外发布包；来源、条款、署名和限制已记录。
- [ ] App 无需运行时访问第三方素材 API / CDN。
- [ ] 完成研究与未完成下载 / 权利审批分别汇报；T08 接入不在本任务完成范围。

对外可发布数可以为 0；在当前用户指定的私人本机范围内，这不单独阻止 T03 完成。必须实际收集并校验本机素材、如实列出缺失项，并将私用与再分发状态分开；若没有实际本机素材或缺失矩阵未完成，不可标记任务完成。

## 7. 可直接发给 Agent 的执行 prompt

> 阅读仓库 AGENTS.md 与 F1-Companion-Architecture.md，执行 docs/tasks/T03-motorsport-assets.md。只写 docs/assets/ 和 macos/Resources/MotorsportAssets/，你不是唯一在仓库工作的 Agent，不回滚其他人修改。基于 2026-10-08 当前日期自行联网检索和核验 2026 F1 名单，逐车手收集头盔、逐车队收集 Logo；记录稳定 ID / Provider alias、赛季、来源页面与原图 URL、许可、下载 / 打包状态。只把许可明确的图片放可打包路径，未知权利保留候选与待审项，不绕过访问限制。提交 collection-report.md、manifest.json、允许打包的素材（若有）和覆盖 / 缺失统计。不要把头像当头盔、不猜当前阵容、不把搜索结果或候选 URL 当已下载图片，不因素材缺失阻塞 V1。最后列变更文件、验证结果与待确认项，不 commit / push。

## 8. 首轮交付状态

2026-10-08 已由独立 Agent 实际联网研究并交付：

- 报告：[`../assets/collection-report.md`](../assets/collection-report.md)。
- 映射与来源：[`../../macos/Resources/MotorsportAssets/manifest.json`](../../macos/Resources/MotorsportAssets/manifest.json)。
- 34 项记录：23 个头盔研究条目（22 个候选、1 个缺失）和 11 个车队 Logo 条目。
- 已下载 0、可发布 0；当前为**研究交付，打包素材待审**，不得当作素材任务全完成。
- 主 Agent 已验证 JSON、必填字段、kind + id + season 唯一键、时间格式与未授权素材隔离；下载文件 / hash 验证和 T08 接入仍待执行。
