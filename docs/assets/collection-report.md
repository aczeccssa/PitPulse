# T03 首轮素材收集报告

> 访问日期：2026-10-08（Asia/Shanghai）；记录时间：`2026-10-08T08:38:15Z`。
> 状态：**研究交付，打包素材待审**。不是“全部素材完成”，不阻塞 V1 / T08 fallback。
> 只写本报告与 `macos/Resources/MotorsportAssets/manifest.json`；未修改任务卡、业务代码或工程；未 commit / push。

## 1. 核验基准与范围

- [F1 官方 2026 当前车手页](https://www.formula1.com/en/drivers)：11 支车队、22 名当前常规车手；[官方车队页](https://www.formula1.com/en/teams)交叉核对归属。正文矩阵以这份**当前阵容**为基准，不沿用 2025 阵容。
- [F1 官方 2026 车手积分](https://www.formula1.com/en/results/2026/drivers)额外包含 Yuki Tsunoda；[官方 Lawson 替补公告](https://www.formula1.com/en/latest/article/tsunoda-to-replace-lawson-at-racing-bulls-for-monaco-grand-prix.3qXjwUiFaZNNOmUhZfk0Rj)解释替补背景。manifest 保留第 23 个头盔记录，但不把他强行列入当前 22 人阵容。
- 实际读取 [Jolpica 2026 drivers](https://api.jolpi.ca/ergast/f1/2026/drivers.json?limit=100)（total=32）、[constructors](https://api.jolpi.ca/ergast/f1/2026/constructors.json?limit=100)（total=11）、[driver standings](https://api.jolpi.ca/ergast/f1/2026/driverStandings.json?limit=100)（round=16，23 人），验证 ID；32 人 registry 不能直接等同“32 名当前正赛车手”。
- 官方 current-grid 与赛季积分是不同时间/口径；Jolpica 中 Lawson 的赛季 constructor IDs 同时有 `rb` / `red_bull`，不能覆盖当前官网阵容归属。
- 尚未全面核验所有 FP / 储备 / 测试参与者的出赛与头盔。额外 9 个 provider registry-only 身份保留于 manifest，明确 `notResearched`，不伪造球队或图片。

## 2. 覆盖与完成度

| 范围 | 记录数 | 有候选页 | 直接图片 URL | 已下载 | 可打包 | 无候选 |
|---|---:|---:|---:|---:|---:|---:|
| 当前 22 人头盔 | 22 | 22 | **0 个确认原始出处**；另有 22 个第三方直接图候选 | 0 | 0 | 0 |
| 赛季额外出赛 Tsunoda | 1 | 0 | 0 | 0 | 0 | 1 |
| 车队 Logo | 11 | 11（官网） | 11（从官网 HTML 确认） | 0 | 0 | 0 |

- **下载总数 0；可发布 bundle 总数 0；34 个研究记录均缺少可打包文件。**
- 头盔 23 项 `needsReview`；官网 Logo 11 项为已知受保护的 `restricted`，并非公开版权许可。
- 5 个当前车手找到官方域名的 2026 头盔专题**搜索候选**：Norris、Piastri、Albon、Bortoleto、Hülkenberg。McLaren 两页直接读取返回 403；Audi / Williams 返回 200 但页面标题通用，未完成专题正文确认。因此 **0 个专题被计作正文与年份都已核验；0 个独立官方头盔原图**，不能声称第三方图与这些候选相同。
- [Turn1Visuals 2026 Assets](https://turn1visuals.com/f1-2026-assets/)逐车手有专门 HELMET 栏及 `img.helmet-img`；已读 HTML 提取 22 个候选地址、浏览页面并对首屏 Colapinto / Gasly 做视觉抽查，确实是独立头盔而非头像。其他 20 项仅按命名行/栏和标记确认候选，不声称已完成视觉/年份核验。
- 聚合页注明资产属于 F1、仅信息展示、非官方关联；**这不是再分发许可**。第三方候选保留在 `candidates[].imageUrl`；`sourceImageUrl` 对所有头盔保留 null，避免把它们当成已确认官方原图。

## 3. 当前阵容与头盔覆盖矩阵

`id` 使用本次 Jolpica 实际返回的稳定 `driverId`，不是 displayName / 数组下标 / 车号。以下全部未下载、未批准打包。

| 车队（constructorId） | 车手 | driverId | 官方域名 2026 专题搜索候选 / 首轮候选 | 原始图 / 赛季 / 权利 |
|---|---|---|---|---|
| alpine | Pierre Gasly | `gasly` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| alpine | Franco Colapinto | `colapinto` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| aston_martin | Fernando Alonso | `alonso` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| aston_martin | Lance Stroll | `stroll` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| audi | Nico Hülkenberg | `hulkenberg` | [官方域名专题候选（未完成正文核验）](https://www.audif1.com/en/news/nico-hulkenberg-helmet-2026)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| audi | Gabriel Bortoleto | `bortoleto` | [官方域名专题候选（未完成正文核验）](https://www.audif1.com/en/news/gabriel-bortoleto-helmet-2026)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| cadillac | Sergio Pérez | `perez` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| cadillac | Valtteri Bottas | `bottas` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| ferrari | Charles Leclerc | `leclerc` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| ferrari | Lewis Hamilton | `hamilton` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| haas | Esteban Ocon | `ocon` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| haas | Oliver Bearman | `bearman` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| mclaren | Lando Norris | `norris` | [官方域名专题候选（未完成正文核验）](https://www.mclaren.com/racing/formula-1/2026/lando-norris-reveals-his-2026-season-helmet/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| mclaren | Oscar Piastri | `piastri` | [官方域名专题候选（未完成正文核验）](https://www.mclaren.com/racing/formula-1/2026/oscar-piastri-reveals-his-2026-season-helmet/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| mercedes | George Russell | `russell` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| mercedes | Andrea Kimi Antonelli | `antonelli` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| rb | Liam Lawson | `lawson` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| rb | Arvid Lindblad | `arvid_lindblad` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| red_bull | Max Verstappen | `max_verstappen` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| red_bull | Isack Hadjar | `hadjar` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| williams | Alexander Albon | `albon` | [官方域名专题候选（未完成正文核验）](https://www.williamsf1.com/articles/f763c154-ed79-4cae-b411-49a1fa3b8a80/alex-albon-2026-helmet)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |
| williams | Carlos Sainz | `sainz` | [第三方 HELMET 栏](https://turn1visuals.com/f1-2026-assets/)；逐项直接候选见 manifest | 未确认原始出处 / 具体设计待审 / needsReview |

**赛季额外记录：** `tsunoda` / Yuki Tsunoda，官方赛季积分和 Jolpica 均有，当前 22 人页无；未找到可靠 2026 独立头盔候选。`teamId=null`；本赛季 constructor `rb` 另存，不误报当前席位。

**registry-only 未研究 9 人：** Paul Aron (`paul_aron`)、Dino Beganovic (`dino_beganovic`)、Luke Browning (`luke_browning`)、Jak Crawford (`jak_crawford`)、Leonardo Fornaroli (`leonardo_fornaroli`)、Colton Herta (`colton_herta`)、Ryo Hirakawa (`ryo_hirakawa`)、Ayumu Iwasa (`ayumu_iwasa`)、Frederik Vesti (`frederik_vesti`)。不包含在上述 23 人头盔候选统计；若产品要展示 FP 临时参与者，后续须单独补名单/出赛依据/素材，不能把 registry 记录当作已确认正赛首发。

## 4. Logo 覆盖矩阵

以下直接图地址逐项写入 manifest，由当前官方车队页 `<img src>` 提取，**不是猜测 CDN 路径，也不是赛车图**。本轮未读取图像字节，因此未验证 MIME / 尺寸 / 透明通道。Logo 是官网使用的明色品牌小标，不保证是完整带赞助商的 2026 字标。

| constructorId | 展示名 | 官方出处 | 当前页面图路径年份 | 许可 / 下载 |
|---|---|---|---|---|
| `alpine` | Alpine | [F1 官方车队页](https://www.formula1.com/en/teams/alpine) | 2025 | proprietary / restricted；未下载 |
| `aston_martin` | Aston Martin | [F1 官方车队页](https://www.formula1.com/en/teams/aston-martin) | 2025 | proprietary / restricted；未下载 |
| `audi` | Audi | [F1 官方车队页](https://www.formula1.com/en/teams/audi) | 2026 | proprietary / restricted；未下载 |
| `cadillac` | Cadillac | [F1 官方车队页](https://www.formula1.com/en/teams/cadillac) | 2026 | proprietary / restricted；未下载 |
| `ferrari` | Ferrari | [F1 官方车队页](https://www.formula1.com/en/teams/ferrari) | 2025 | proprietary / restricted；未下载 |
| `haas` | Haas F1 Team | [F1 官方车队页](https://www.formula1.com/en/teams/haas) | 2025 | proprietary / restricted；未下载 |
| `mclaren` | McLaren | [F1 官方车队页](https://www.formula1.com/en/teams/mclaren) | 2025 | proprietary / restricted；未下载 |
| `mercedes` | Mercedes | [F1 官方车队页](https://www.formula1.com/en/teams/mercedes) | 2025 | proprietary / restricted；未下载 |
| `rb` | Racing Bulls | [F1 官方车队页](https://www.formula1.com/en/teams/racing-bulls) | 2025 | proprietary / restricted；未下载 |
| `red_bull` | Red Bull Racing | [F1 官方车队页](https://www.formula1.com/en/teams/red-bull-racing) | 2025 | proprietary / restricted；未下载 |
| `williams` | Williams | [F1 官方车队页](https://www.formula1.com/en/teams/williams) | 2025 | proprietary / restricted；未下载 |

**重要版本限制：** 9 个官网 Logo URL 仍含 `2025`，只有 Audi / Cadillac 含 `2026`。这说明“当前官网沿用该图”，不证明它覆盖完整 2026 商业品牌。manifest 的 `applicability` 原样标记路径年份及 `needsReview`，没有伪装成 2026 新 Logo。Turn1Visuals 提供的 2026 CDN SVG 候选也单独保留，未代替官网依据。

补充可核验文件页候选（未下载、未批准）：

- [Wikimedia：TGR Haas F1 Team Logo (2026)](https://commons.wikimedia.org/wiki/File:TGR_Haas_F1_Team_Logo_(2026).svg)：文件页含 PD-textlogo / trademark 提醒。页面的低原创性版权说明不消除商标使用限制，不能据此宣布全部品牌素材可发布。
- [Wikimedia：Williams F1 Team (2026 logo)](https://commons.wikimedia.org/wiki/File:Williams_F1_Team_(2026_logo).svg)：仅确认文件页入口；逐文件版权、作者、完整标识适用性仍需审核。
- 搜索曾见其他年份/非自由品牌文件：不直接沿用，不为下载凑数量；未下载任何 SVG，仓库内不存在素材脚本或外链资源。

## 5. 授权边界与后续人工动作

1. [F1 Guidelines](https://www.formula1.com/en/information/guidelines)：品牌、版权、照片及非商业使用规则需要分别核对；[F1 Legal Notices](https://www.formula1.com/en/information/legal-notices)不能视为素材授权。
2. **匿名可访问、官网公开、CDN、personal use、非商业均不自动允许打包再分发。** 没有取得任何媒体包/权利人对 PitPulse 分发的明确授权；没有创建个人参考副本；没有绕过认证、付费墙或访问限制。
3. 头盔须确认：设计年份、通用 / 特殊站版本、摄影/渲染作者、队徽/赞助商版权、可否裁剪与再分发及署名。若只允许本人参考，后续应仓库外存放并记录 `downloadedReference`，不得加入 bundle。
4. Logo 须确认：是否需要 2026 完整 sponsor lockup、F1 页面小标是否足够、copyright grant 与 trademark / 不冒充官方规则。Haas / Williams Wikimedia 候选先复核完整文件页条款，不能把不同页许可混用。
5. 取得许可后才下载到 `helmets/` / `team-logos/`；验证 HTTP/MIME、大小、图片身份和 SVG scripts / 外链；记录真实 SHA-256、具体许可 URL、署名要求、适用赛季，状态改为 `approved + downloadedApproved`。
6. `bundlePath` 非 null **不单独代表可发布**。接入方必须同时检查 rightsStatus、downloadStatus、存在的本地文件、hash 和适用性；任何 `needsReview` / `restricted` 记录都不得自动 copy、热链或在 Mac 运行时请求第三方 CDN。
7. 0 张可发布素材时使用**车手缩写、车队名称 / 已配置颜色**，不伪造头盔、不拿别人图代替。比赛继续国家 Emoji；通用图标继续 SF Symbols；图像缺失不影响 V1。T08 的 Asset Catalog / 明暗变体 / 构建接入未执行。

## 6. manifest 扩展字段与验证

- 最低字段均具备；`providerIds.jolpica.driverId / constructorId` 来自此次实际 API 响应。`openF1` / `f1Live` 保留 null（未核验），不猜 alias。
- `rosterRole` 区分当前阵容/仅本赛季出赛；`providerSeasonConstructorIds` 是赛季内 provider 归属，不保证当前阵容。
- `applicability.designSeason`：头盔图未确认则 null；Logo 只记录 CDN 显式路径年份。`requestedSeason=2026` 不等于许可/设计确认。
- `candidates` 是下一轮研究入口；`imageUrl` 非空不等于下载、原始出处确认或版权授权；`verification` 记录具体核验层级。
- `shippingReady=false`、`bundlePath=null`、`sha256=null` 对全部 34 项成立。`registryOnlyDrivers` 单列尚未研究的 9 人，不能用它宣称赛季所有参与者素材完整覆盖。

本轮命令与观察：

```text
urllib.request.urlopen: 读取官方/候选页面 HTML；读取 Jolpica 2026 drivers、constructors、driverStandings JSON
re.findall(<img ...>): 确认 F1 官网 Logo img src；提取聚合页面 img.helmet-img
Codex in-app browser: 查看 2026 Assets 的 HELMET 栏；首屏截图视觉抽查 2 名车手
python3: JSON parse、kind+id+season 唯一、roster/provider ID 集合及状态门禁检查
python3 -m json.tool macos/Resources/MotorsportAssets/manifest.json
git diff --check -- docs/assets macos/Resources/MotorsportAssets
```

没有执行素材下载命令；素材下载尝试为 0。页面复查时 McLaren 两个候选返回 **HTTP 403 Forbidden**，未尝试绕过；Audi / Williams 返回 200 但仅获得通用标题，专题正文尚未确认。主要未完成项是头盔原图/设计归属和再分发许可；本轮不为页面或下载继续等待。JSON 解析、34 个三元键唯一、22+1 车手 / 11 车队数量、未授权项无 bundlePath/hash 的检查已通过。

**确切交付文件：**

1. `docs/assets/collection-report.md`
2. `macos/Resources/MotorsportAssets/manifest.json`

源代码构建/测试不适用于这两个研究文件；业务、SwiftUI 及图片实际接入未完成，不应报作本任务成果。
