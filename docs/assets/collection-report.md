# T03 素材收集报告

> 首轮记录：2026-10-08；最近复核：`2026-10-09T06:01:35Z`（UTC）。
> 最新状态：T03 本机私用素材收集与文件核验已完成。累计 39 个 private-local 文件：22 张单车手头盔 PNG、6 张 2026 英国站官方编辑照片拼图、11 个车队 Logo。2026 设计年份与再分发权仍未独立核验；这是发布范围的后续限制，不阻止本机私用交付。未进入 bundle，shipping-ready 为 0。
> 早期轮次中的下载数量、素材目录为空等结论均为对应时间的历史快照；仓库外 6 个既有参考文件仍单独记录，不计入本轮 private-local 39 个文件。素材 Agent 未修改任务 JSON、业务代码或工程资源；主 Agent 按仓库要求更新任务状态，并依用户授权将本次 T03/T07 工作纳入本地版本控制 commit；未 push 或公开发布。

## 第五轮追加：本机私用素材收集（2026-10-09T06:01:35Z）

### 收集结果和范围

按用户限定的本机私用范围，新增 38 个公开 URL 文件，并从既有仓库外研究参考复制 1 个 Haas SVG 到 private-local；共 39 个本地素材文件。文件路径、实际 MIME、格式、像素尺寸／SVG viewBox、字节数、SHA-256、来源 URL、使用范围和权利状态均记在 manifest 的 `privateLocalDownloads`。素材纳入用户本机仓库版本控制，但未加入 Xcode bundle；所有记录 `useScope=privateLocalOnly`、`bundlePath=null`、`shippingReady=false`。

| 类别 | 数量 | 本轮核验 |
|---|---:|---|
| T1V 2026 页面单车手头盔图 | 22 | 22/22 直接 URL HTTP 200；实际 GET 均为 PNG，685×597 RGBA；视觉确认一图一顶具名车手头盔 |
| F1 2026 英国站编辑照片 | 6 | 均为 WebP、3200×1800；全部为人物照片、双图/多图拼接或多个头盔的拼图，不计为单盔覆盖 |
| 当前车队 Logo | 11 | 9 个 F1 官网 Profile 图、1 个 Williams 官网 SVG、1 个复用既有 Haas Commons SVG；11/11 当前车队映射 |
| 合计 | 39 | 38 个公开网络下载 + 1 个先前已下载 Haas 参考副本；每文件 hash 已入 manifest |

### 单车手头盔覆盖矩阵

[Turn1Visuals 2026 Assets 页面](https://turn1visuals.com/f1-2026-assets/)在 22 个当前车手行中均列出独立 `HELMET` 图。逐项 HEAD 和 GET 均返回 HTTP 200；GET 响应 MIME 为 `image/png`，实测文件签名也是 PNG。逐图视觉检查均为透明背景上的单顶侧视头盔；画面中车队与赞助商标志及页面行名与目标车手相符，未见拼图或多人错配。全部图像为 685×597 RGBA；实际字节数、SHA-256、provider driver ID 映射见 manifest。

| driverId | 车手 | 本地文件 | 赛季依据 |
|---|---|---|---|
| `gasly` | Pierre Gasly | `2026-t1v-gasly-helmet.png` | T1V 页标题标 2026；具体设计年份未独立确认 |
| `colapinto` | Franco Colapinto | `2026-t1v-colapinto-helmet.png` | 同上 |
| `alonso` | Fernando Alonso | `2026-t1v-alonso-helmet.png` | 同上 |
| `stroll` | Lance Stroll | `2026-t1v-stroll-helmet.png` | 同上 |
| `hulkenberg` | Nico Hülkenberg | `2026-t1v-hulkenberg-helmet.png` | 同上 |
| `bortoleto` | Gabriel Bortoleto | `2026-t1v-bortoleto-helmet.png` | 同上 |
| `perez` | Sergio Pérez | `2026-t1v-perez-helmet.png` | 同上 |
| `bottas` | Valtteri Bottas | `2026-t1v-bottas-helmet.png` | 同上 |
| `leclerc` | Charles Leclerc | `2026-t1v-leclerc-helmet.png` | 同上 |
| `hamilton` | Lewis Hamilton | `2026-t1v-hamilton-helmet.png` | 同上 |
| `ocon` | Esteban Ocon | `2026-t1v-ocon-helmet.png` | 同上 |
| `bearman` | Oliver Bearman | `2026-t1v-bearman-helmet.png` | 同上 |
| `norris` | Lando Norris | `2026-t1v-norris-helmet.png` | 同上 |
| `piastri` | Oscar Piastri | `2026-t1v-piastri-helmet.png` | 同上 |
| `russell` | George Russell | `2026-t1v-russell-helmet.png` | 同上 |
| `antonelli` | Andrea Kimi Antonelli | `2026-t1v-antonelli-helmet.png` | 同上 |
| `lawson` | Liam Lawson | `2026-t1v-lawson-helmet.png` | 同上 |
| `arvid_lindblad` | Arvid Lindblad | `2026-t1v-arvid_lindblad-helmet.png` | 同上 |
| `max_verstappen` | Max Verstappen | `2026-t1v-max_verstappen-helmet.png` | 同上 |
| `hadjar` | Isack Hadjar | `2026-t1v-hadjar-helmet.png` | 同上 |
| `albon` | Alexander Albon | `2026-t1v-albon-helmet.png` | 同上 |
| `sainz` | Carlos Sainz | `2026-t1v-sainz-helmet.png` | 同上 |

T1V 页只证明其把这些行放在 “2026 Assets” 表格，不证明每顶头盔的设计年份、摄影/制作者、图案授权或来源链。manifest 中保留 `designYear=null`、`rightsStatus=needsReview`，并记 `claimedDesignYear=2026` 与来源页主张；不能把页面标题当作独立赛季鉴定。[T1V 服务条款 §2](https://turn1visuals.com/tos/)（2026-03-13 更新）原文为：“You may not copy, redistribute, or use the content for commercial purposes without prior written permission.” 本次仅按用户限定留在本机私用目录；未取得 T1V 书面授权，不主张获得转载或分发许可，图像不进入 bundle。权利状态仍按原事实记录，不因私用下载而改成 approved。

**头盔覆盖结论：** 当前 22 名正赛车手各有一张视觉上匹配的单盔候选；图像缺失 `0/22`。T1V 页面标注 2026 的候选 `22/22`，但逐图可独立证实设计年份的数量为 `0/22`；若未来需要官方出处或明确可再分发素材，仍缺 22 项权利/来源证据。Yuki Tsunoda 是额外赛季出赛/替补身份，当前素材不适用；本轮没有他的头盔图，使用姓名缩写及车队文字 fallback。此项不影响 22 名当前正赛车手覆盖。Yuki Tsunoda 是赛季出赛但非当前 22 人阵容的额外记录，不计当前覆盖；其素材在本轮未新增。

### F1 官方英国站拼图参考

[F1 2026 英国站专题](https://www.formula1.com/en/latest/article/lego-racing-chaos-football-trolling-and-a-british-boyband-8-moments-you-might-have-missed-at-the-2026-british-grand-prix.7KueGnWFUFv0R7yuApUisr)确认这些为 2026 英国站特殊头盔或车手造型。直接下载的六张官方媒体文件均保留为编辑照片参考，不裁图、不从拼图派生单盔：Hamilton 图含历史与活动头盔视图；Lindblad、Bearman、Sainz 图含车手和头盔多面板；Bottas/Pérez 图有两顶头盔；Piastri 图代表他当周末三款设计中的至少两款。它们不计入 22 人的单盔覆盖，也不等于基础赛季头盔。逐文件 hash、MIME、字节与图像大小见 manifest。官方页面与 CDN 来源没有赋予本项目分发权，全部保持 private-local。

### 车队 Logo 覆盖和版本

| constructorId | 本地文件 | 来源／版本说明 | 权利状态 |
|---|---|---|---|
| `alpine` | `2026-alpine-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2025 | `restricted` |
| `aston_martin` | `2026-aston-martin-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2025 | `restricted` |
| `audi` | `2026-audi-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2026 | `restricted` |
| `cadillac` | `2026-cadillac-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2026 | `restricted` |
| `ferrari` | `2026-ferrari-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2025 | `restricted` |
| `haas` | `2026-tgr-haas-previously-downloaded.svg` | 既有 Haas 来源 Commons SVG；2026、PD-textlogo 且标 trademarked | `needsReview` |
| `mclaren` | `2026-mclaren-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2025 | `restricted` |
| `mercedes` | `2026-mercedes-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2025 | `restricted` |
| `rb` | `2026-racing-bulls-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2025 | `restricted` |
| `red_bull` | `2026-red-bull-racing-current-page-logo.webp` | F1 当前 Profile；CDN 路径版本 2025 | `restricted` |
| `williams` | `2026-atlassian-williams-official-site.svg` | Williams 官方 2026 新品牌页面提供的水平 SVG，78×17 | `needsReview` |

11 个当前车队均有本地参考图。9 个 F1 Profile 小标中只有 Audi / Cadillac 路径明确为 2026；其余 7 个仍是 2025 路径，即使展示在当前页面也不能冒称为 2026 新设计。Haas / Williams 两个 Logo 可确认是 2026 名称/品牌，但版权与商标权分开记录；Williams SVG 来自其公开官网页面，Haas 文件复用先前已有的外部参考，未尝试绕过本轮 Commons 403。

### 校验与剩余边界

- 每个栅格文件用 `file --mime-type` 核 MIME，用 Pillow 解码并验证图像格式、像素尺寸及颜色模式；逐文件记录真实字节数和 SHA-256。22 张 T1V PNG 已逐张目视确认单盔；六张 F1 拼图已按目标人物/头盔关系分类；九张 64×64 F1 车队标志已目视确认内容。
- 两张 SVG 均成功解析 XML。Haas `viewBox=0 0 199.3864487 182.5550803`；Williams `viewBox=0 0 78 17`。脚本、`foreignObject`、外部 href、事件处理属性、CSS `url()` 外链数均为 0。
- 2026 来源适用性：头盔 22 张为第三方页面标 2026、实际图片与车手行匹配，但未有逐图日期/作者证明；F1 六张只证实 2026 英国站特别设计；Logo 11/11 当前车队可映射，版本按上表标注。
- 对 bundle 而言目前 `shipping-ready=0`。仅用户授权的本机私用，不代表车手头盔图案、队徽、赞助商、F1 IP 的公开发布授权；未授权文件不得进入 bundle。无法使用图像时 fallback 为车手缩写、车队名和配置色。
- manifest 校验保留 34 条既有素材唯一键与 6 个仓库外参考历史；新增 39 条 `privateLocalDownloads` 和独立私用摘要。用户限定的本机私用收集范围已完成；未宣称再分发授权或 bundle readiness。任务 JSON 由主 Agent 更新，本报告不写状态副本。

## 第四轮追加：官方媒资包、设计师授权与商业图库复核（2026-10-09T05:03:02Z）

### 结果

本轮换查 FIA / F1 官方媒体包、运动员或设计师公开授权、商业图库许可，以及 Unsplash 明确版权许可照片。没有发现同时满足目标设计适用性和队徽、赞助商、车手相关权利清理的可发布素材。新增 1 个仓库外个人参考照片，0 个新增 bundle 文件，0 个 shipping-ready；第四轮开始时的 34 条 manifest 记录与 5 个参考文件均保留，本轮结束累计 6 个参考文件。

### Unsplash Max Verstappen 头盔照片

[Unsplash 照片页](https://unsplash.com/photos/white-racing-helmet-with-red-accents-and-sponsor-logos-jAGMc5EwpZ4)由 Todd Jiang (`@toddjiang`) 上传，页面标题为 “White racing helmet with red accents and sponsor logos”，标签包含 Max Verstappen 和 Red Bull Racing，发布时间为 2026-02-06；页面提供官方 [Unsplash License](https://unsplash.com/license) 下载。许可证向照片版权授予全球、不可撤销、非独占的下载、复制、修改、分发和使用许可，包含商业用途，且无需署名。该版权许可不涵盖图中第三方标志、物品设计、赛事权利或个人形象等独立权利。[Unsplash 官方 Releases and Trademarks 指引](https://help.unsplash.com/en/articles/2612329-releases-and-trademarks)说明版权许可不代表任何用途都已获准；图中人物、物件、商标等可能需要额外批准，且 Unsplash 不保证每张照片的 release 范围。

通过 Unsplash 页面公开下载入口实际下载一张，仅存仓库外作个人参考，未放进素材目录。记录文件名 `max-verstappen-2026-unsplash.jpg`；响应 MIME `image/jpeg`，文件签名识别为 JPEG，4032×3024 RGB，707,669 bytes；视觉确认是单顶实体头盔摆放照，无车手本人，能见 Red Bull、Oracle、Mobil 1、Heineken、TAG Heuer、viaplay、Gate.io 等标志。SHA-256：`173cfd8ee40861ebe49899c799ff94e97b7ea0af197c33b9401d8add83cb8681`。来源页发表日期仅证明上传时间，不证明头盔设计年；故 `designYear=null`，候选适用性仍未确认，`rightsStatus=needsReview`、`downloadStatus=downloadedReference`、`shippingReady=false`。此图作为个人参考也不是发布候选。

用 [Red Bull 官方 2026 头盔图集](https://www.redbull.com/us-en/galleries/max-verstappen-2026-f1-helmet-photos)交叉核验。图集标注日期 2026-01-23；照片说明指出该季头盔有 Ford 标志，后部有四颗冠军星，摄影署名为 Verstappen.com / David Klopman。Unsplash 照片可见区域未见 Ford 标志或四星，外观也与官方主图的红、蓝、白设计不同；页面的 Max 标签与 2026 上传日期不足以证明图中就是该季常规设计。其是否为其他站次变体、旧赛季或展示复制品无法确认，故保留 `designYear=null`。Red Bull 图集仅作年份比对；其官方照片亦未获 PitPulse 分发授权。

主 Agent 同时报告了 6 个 Unsplash 车手定向搜索结果：Oscar Piastri 0 张、Charles Leclerc 1 张（整人照片，不是单盔）、George Russell 0 张、Lando Norris 2 张（均标注 2025-10-29）、Fernando Alonso 0 张、Isack Hadjar 0 张。该批搜索未产生新的 2026 单头盔发布候选；搜索结果没有用于下载或替代原始来源证明。

### FIA、车手／设计师授权和媒体包

- [FIA 2026 官方媒体包](https://www.fia.com/sites/default/files/final_2026_media_kit.pdf)包含赛事信息；文件版权行标为 ©2026 Formula One World Championship Limited，并写明 “All rights reserved”。媒体包没有授予 PitPulse 自托管 App 复制／分发文件的许可，因此只作为新闻资料，不提取图片或标志。
- [FIA 媒体认证规则](https://www.fia.com/accreditation)将网络认证限制为专业编辑／新闻报道，并要求尊重 FIA、Formula One Group 和第三方权利；规则明列对商标、title、logos 的限制。认证或媒体包访问不是通用 App 授权。
- [Esteban Ocon 头盔设计比赛条款](https://fr.esteban-ocon.com/legal/fan-helmet-design-competition-terms-and-conditions)是 2025 年比赛授权：参赛者向 Ocon / EO31 SARL 授予与比赛、头盔制作、宣传和公开展示相关的设计使用权；设计不得包含第三方标志（指定模板提供的官方标志例外）。没有授予第三方应用的使用权，且不是 2026 车手素材授权。
- [Matteo Macchiavelli Art Helmet 页面](https://www.matteomacchiavelli.com/art-helmet)列有 Kimi Antonelli 的 2025 致敬作品及其他历史主题，并注明 “Artistic Interpretation NOT sold under a commercial license”。它不是 2026 赛季正式头盔原图，也没有商业 App 分发授权。

### 商业图库边界

- [Shutterstock 2026 George Russell 日本站照片](https://www.shutterstock.com/editorial/image-editorial/suzuka-japan---march-29-george-russell-16807142el)是 4000×2667 JPEG 的整场赛事编辑照片，不是独立头盔图。其现行 [Standard Image License](https://www.shutterstock.com/license)明确准许标准图片作为数字复制用于 mobile apps / software；但该文件标为 Editorial，适用另一种 Editorial License，只可在单一新闻编辑语境中使用，并要求保留上下文、署名；不得把该标准商用授权套到此编辑照片，也不能因此获得车队或赞助商标志许可。没有购买或下载图库文件。
- [Getty Images EULA](https://www.gettyimages.co.uk/eula)禁止让他人下载、提取或单独再分发素材文件；编辑内容没有人物／物件 release，商业或推广用途须另外获明确授权并另清相关第三方权利。未取得 Getty 逐图 license。
- [Adobe Stock 2026 附加条款](https://www.adobe.com/cc-shared/assets/pdf/legal/servicetou/stock-product-specific-terms-en-us-20260116.pdf)要求编辑作品保持新闻语境、禁止商业用途；违规用途须向版权人另取许可并取得必要附加许可。没有发现能满足目标设计及车队标志权利的可下载商业图库资产。

**本轮计数：** 新增下载 1 个仓库外个人参考；累计 6 个外部参考；仓库素材 0；shipping-ready 0。个人参考的版权许可、嵌入标志权限和设计年份适配性分开记录；不以已下载或 Unsplash 的宽版权许可替代商标 / 设计许可。所有候选仍不得自动进入 bundle。最小 blocker 仍为逐项确认适用设计并取得涵盖应用内复制／分发与嵌入商标／赞助元素的权利许可。

### 本轮文件与 manifest 验证（2026-10-09T05:08:10Z）

`file` 和 `sips` 检查外部 Unsplash 副本为 JPEG/JFIF、4032×3024；`wc -c` 得到 707,669 bytes；`shasum -a 256` 得到 `173cfd8ee40861ebe49899c799ff94e97b7ea0af197c33b9401d8add83cb8681`，与 manifest 一致。`python3 -m json.tool macos/Resources/MotorsportAssets/manifest.json` 与本地结构校验通过：34 个唯一 `(kind,id,season)` 记录、6 个带 SHA-256 的外部参考、0 个 `bundlePath`、0 个 shipping-ready；全部参考均为 `needsReview` / `downloadedReference`。`git diff --check -- docs/assets/collection-report.md macos/Resources/MotorsportAssets/manifest.json` 通过。F1 [官方 Guidelines](https://www.formula1.com/en/information/guidelines.4EOKE9RRqevL4niTK9kWyt)再次核对记录于 manifest `rightsSources`：F1 Logo 需明确书面许可，静态图需相关权利人同意，其他 F1 IP 不得用于 App；车队和车手权利需分别确认。没有联系权利人。

## 本轮追加：2026 开放许可来源与标志权利复核（2026-10-09T04:20:08Z）

### 结果与权利边界

本轮覆盖 manifest 全部 34 条目标（23 个车手头盔记录、11 个车队 Logo）。对每条记录运行 Openverse CC0 / CC BY / CC BY-SA 筛选，34 条均返回 `result_count=0`。Commons 另按目标名检索 34 次：12 次返回、22 次被 HTTP 429 限流；429 记录为“未核实”，不当作无结果。没有找到同时满足“2026 赛季适配、素材类型吻合、版权可再分发、嵌入车队／F1／赞助商商标及车手相关权利明确”的文件，因此第二轮新增下载 0、shipping-ready 仍为 0。上一轮四份仓库外参考及其许可、hash、状态均保留不动。

[F1 2026 年 3 月官方文章](https://www.formula1.com/en/latest/article/meeting-carlos-alcaraz-and-final-days-off-what-f1-drivers-have-been-up-to-in.4Yqc3HtvSEcBGkRNXcxOYp.4Yqc3HtvSEcBGkRNXcxOYp)确认车手通过社交媒体展示了多款新头盔，并点名 Bottas、Albon、Piastri、Bearman、Ocon、Alonso、Hülkenberg、Norris 等。页面 DOM 核验只见一张页面 hero 图，没有独立头盔文件 URL；这是“官方可见参考”，不是素材授权或可下载单盔。

[F1 官方 IP 指引](https://www.formula1.com/en/information/guidelines.4EOKE9RRqevL4niTK9kWyt)要求使用 F1 Logos 须有明确书面许可，照片须获相关权利人同意，并明确其他 F1 IP 不得用于 apps；车队及车手权利须另向相应权利人确认。故照片许可只覆盖摄影作品的版权时，仍不足以证明可在应用内分发头盔图案、F1 标志、车队／赞助商商标或车手相关形象。未联系或提交授权申请。

### Simple Icons 与 Coloracci 车队标志候选

[Coloracci McLaren 页面](https://coloracci.ai/brands/mclaren)将 Simple Icons 的 McLaren 单色 glyph 标为 CC0 1.0，同时说明 McLaren 名称和 Logo 仍是权利人商标，并限制不得暗示背书、改动标志或用于周边。该页面是第三方聚合来源，不是 McLaren 的许可。

已直接读取 [Simple Icons 官方逐图数据](https://raw.githubusercontent.com/simple-icons/simple-icons/develop/data/simple-icons.json)：共 3,465 条。Aston Martin、Audi、Cadillac、Ferrari、McLaren 五项有品牌条目，但各项均没有 `license` 字段；Alpine、Haas、Mercedes、Racing Bulls、Red Bull Racing、Williams 没有对应 F1 车队图标条目（Alpine.js/Linux 和 Red Bull 饮料品牌不是目标车队 lockup）。[Simple Icons 官方免责声明](https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md)特别说明项目 CC0 不代表每个图标都 CC0，并要求核对单项许可、取得所需权限。缺少字段不证明图标无许可，但本轮没有取得可核验的逐项授权；Coloracci 的汇总标签不能替代许可字段或权利方授权。[CC0 条款](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md)也明确不授予 Affirmer 的商标权，且不负责清理第三方权利。此路径不能令任何车队 Logo shipping-ready。

Commons 另发现 [Williams 2026 Logo PNG](https://commons.wikimedia.org/wiki/File:Williams_F1_logo_2026.png) 与[另一同名更正候选](https://commons.wikimedia.org/wiki/File:Williams_F1_logo_2026_(Corrigindo).png)，文件页分别标 CC0，但前者由 Gufactor 上传为 own work，后者作者未知且来源指向 Williams 官方发布；均无证据表明上传者持有 Williams Logo 权利或获商标许可。[Williams 官方发布页](https://www.williamsf1.com/articles/f8e0db58-3b85-4c23-b5e2-887160812e54/williams-unveils-new-name-and-logo-for-2026)只确认 2026 新 Logo，并未授予再分发权。两个候选都未下载。

### 逐条开放来源检索矩阵

每条 Openverse 查询均使用 `2026 + 名称 + F1 helmet`（车手）或 `2026 + 名称 + Formula 1 team logo`（车队），过滤 `CC0, CC BY, CC BY-SA`；逐条精确查询 URL 和 Commons 状态同时写入 manifest 的 `secondRoundResearch.perAssetSearches`。

**车手头盔**

| ID | 目标 | Openverse 匹配 | Commons 结果 / 限制 | 判定 |
|---|---|---:|---|---|
| `gasly` | Pierre Gasly | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `colapinto` | Franco Colapinto | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `alonso` | Fernando Alonso | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `stroll` | Lance Stroll | 0 | 仅有无关 PDF 命中 | 不下载 / 不入 bundle |
| `hulkenberg` | Nico Hülkenberg | 0 | 仅找到 2018 头盔插画（CC BY-SA 4.0） | 不下载 / 不入 bundle |
| `bortoleto` | Gabriel Bortoleto | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `perez` | Sergio Pérez | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `bottas` | Valtteri Bottas | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `leclerc` | Charles Leclerc | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `hamilton` | Lewis Hamilton | 0 | 仅找到 2025 展陈头盔照片（CC BY-SA 4.0） | 不下载 / 不入 bundle |
| `ocon` | Esteban Ocon | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `bearman` | Oliver Bearman | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `norris` | Lando Norris | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `piastri` | Oscar Piastri | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `russell` | George Russell | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `antonelli` | Andrea Kimi Antonelli | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `lawson` | Liam Lawson | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `arvid_lindblad` | Arvid Lindblad | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `max_verstappen` | Max Verstappen | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `hadjar` | Isack Hadjar | 0 | Commons API 返回 HTTP 429，未能核实；另有 2026 CC BY 4.0 整车/车手照，非单盔 | 不下载 / 不入 bundle |
| `albon` | Alexander Albon | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `sainz` | Carlos Sainz | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `tsunoda` | Yuki Tsunoda | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |

**车队 Logo**

| ID | 目标 | Openverse 匹配 | Commons 结果 / 限制 | 判定 |
|---|---|---:|---|---|
| `alpine` | Alpine | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `aston_martin` | Aston Martin | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `audi` | Audi | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `cadillac` | Cadillac | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `ferrari` | Ferrari | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `haas` | Haas F1 Team | 0 | Commons API 返回 HTTP 429，未能核实；已知 TGR Haas PD-textlogo 页面明示 trademarked | 不下载 / 不入 bundle |
| `mclaren` | McLaren | 0 | Commons API 返回 HTTP 429，未能核实；Coloracci 标 CC0，官方 Simple Icons 单项 license 缺失 | 不下载 / 不入 bundle |
| `mercedes` | Mercedes | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `rb` | Racing Bulls | 0 | Commons API 返回 HTTP 429，未能核实 | 不下载 / 不入 bundle |
| `red_bull` | Red Bull Racing | 0 | 目标式 Commons 查询无相关文件命中 | 不下载 / 不入 bundle |
| `williams` | Williams | 0 | 找到 2026 Williams CC0 上传候选，上传者权属及商标未核实 | 不下载 / 不入 bundle |

补充候选核验：Commons 的 Hülkenberg 命中为 2018 CC BY-SA 头盔插画；Hamilton 命中为 2025 CC BY-SA 展馆照片；均不是 2026 设计，嵌入标记也没有独立授权。Isack Hadjar 的 2026 比利时站 Flickr / Commons 命中为摄影者 Der Alf 的 CC BY 4.0、6000×3376 整车与车手比赛照片，非单顶头盔；车队／赞助商标记和车手相关权利未单独许可。TGR Haas 2026 Commons 文件是 PD-textlogo，同时明示 `trademarked`。上述均不下载、不进入 bundle。

### 本轮核验

- 新增下载：0；累计仓库外参考副本：4；bundle 文件：0；shipping-ready：0。
- Openverse 逐条筛选：34/34 查询成功，0 条许可候选。Commons 逐条 API：34 次尝试，12 次有响应、22 次 HTTP 429；限流结果保留为未知。
- Simple Icons 逐图 metadata、Coloracci 的 McLaren 聚合标签、官方商标／应用限制均已记录于 manifest `rightsSources` 与 `secondRoundResearch`。
- `helmets/` 与 `team-logos/` 没有新增文件；T03 保持素材待审，不标 `done`。fallback 仍用车手缩写、车队名称及配置色。


## 第三轮追加：权利方媒资、逐项许可与 Commons/Flickr 复核（2026-10-09T04:54:45Z）

### 结果与新增参考

本轮改查权利方媒体中心/使用条款、Flickr 原作者文件页、Commons 文件页，并低频重试上一轮被限流的 22 条 Commons 查询。没有找到可确认允许在 PitPulse App bundle 再分发、且包含车队/赞助商标志及车手形象权许可的素材；本轮新增 **1 个仓库外个人参考文件**，并非发布候选。**截至第三轮结束（2026-10-09T04:54:45Z）**累计 5 个外部参考文件；当时仓库内仍无素材文件，34 个目标均 `shippingReady=false`、`bundlePath=null`，可发布数为 0。第四轮新增一份后，当前累计数为 6。

新参考为 [Atlassian Williams F1 Team horizontal logo.svg](https://commons.wikimedia.org/wiki/File:Atlassian_Williams_F1_Team_horizontal_logo.svg)：Commons 页标注 source=`williamsf1.com`、author=`Atlassian Williams F1 Team`、上传者 `Eloir`，文件历史为 2026-03-08，归入 2026 SVG logos；MIME `image/svg+xml`，SVG 500×80、`viewBox=0 0 500 80`、6,746 bytes。已在本地渲染确认是独立横版队标；XML 可解析，0 个 `<script>`、0 个外链引用。SHA-256：`56af776014a1216fad897ef7b097e66912bc50070e265e675983a67b06bac877`。Commons 将简单文字/几何图标列为 `PD-textlogo`，同时明确 `trademarked` 并要求使用者自行确保拥有合法权利；这不是 Williams、Atlassian 或 F1 对 App 分发该标志的商标许可。故 manifest 仅记作 `downloadedReference` / `needsReview`，无 `bundlePath`，不计可发布素材。

### 权利方媒体包与官方条款

- [F1 官方 IP 指引](https://www.formula1.com/en/information/guidelines.4EOKE9RRqevL4niTK9kWyt)：F1 Logo 需明确书面许可；静态图片须获相应权利人同意；指引还写明其他 F1 IP 不能用于 Apps，车队和车手许可需另向相应权利人确认。官方头盔揭示文章仅是公开展示，不是可下载文件或素材授权。
- [Audi Revolut F1 Content Hub 条款](https://contenthub.audif1.com/en/terms-of-service)：下载素材严格限编辑用途、不得商业使用；内容仍属其权利人，访问/下载不转让使用权。具体 [2026 Audi F1 照片页](https://www.audi-mediacenter.com/en/photos/detail/audi-revolut-f1-team-monaco-grand-prix-132376)只标“editorial purposes free of charge”，不是允许将照片或车标作为应用资源包分发的许可。
- [McLaren Racing Website & App 条款 §2](https://www.mclaren.com/racing/terms-of-use/)仅允许个人、非商业下载页面摘录；图形不得脱离配套文字；McLaren 和赞助商标志是专有标志，未经许可不得使用；条款还限制把内容另存进公共或私有电子检索服务。不能据此打包分发。
- [Williams Racing 条款 §§2、4](https://www.williamsf1.com/policies/terms-and-conditions)同样仅授予个人、非商业页面摘录使用，禁止单独使用图形；队标为专有标志，网站内容不得储存到电子检索服务，Williams 商标须有明确书面许可。Commons 的 PD-textlogo 版权状态不能覆盖该独立商标问题。
- [Haas 官方 Media Portal](https://media.haasf1team.com/)须先获准访问；可访问或获准使用门户内容不等同公开、可再分发的应用授权。本轮未申请账号或联系权利人。
- [Turn1Visuals 服务条款 §2](https://turn1visuals.com/tos/)规定内容限个人/信息用途，未经书面许可不得复制或再分发；因此该站标注的 22 个 2026 `HELMET` 候选不能当成“已获准个人下载”，也不能用于 bundle。

这些条款分开处理素材版权与内嵌商标/形象权。即使照片作者授予 CC 或权利方媒体页允许编辑用途，也不自动授予头盔图案、车队/赞助商标志、F1 权利或车手形象在自托管 App 资源包中的使用权。

### Commons 低频重试及 Flickr 检索

上一轮 HTTP 429 的 22 个精确 Commons 查询已按每次间隔约 3.5 秒重试；21 条重试请求返回 HTTP 200，Liam Lawson 查询再次触发 HTTP 429 并带 `Retry-After: 6`，等待后复查返回 HTTP 200、空页。重试阶段 17 条返回空页；4 条返回文件，但其中 3 组是无关内容（Audi e-tron 2019/法规 PDF、版权手册 PDF、Mercedes-Benz EQC 2019 照片），另 1 组是已记录的 Russell 九顶头盔展陈照。后者是摄影照片的 CC BY 4.0 参考，但不是单顶头盔，设计年份不明，也没有清理图案/商标；没有新增合格发布素材。

此外，Chrome DevTools 的 Commons MediaSearch 搜索 `2026 Formula One driver helmet` 返回 6 个 1965–1992 历史头盔结果；`2026 Formula 1 team logo` 返回 3 个不属于 2026 F1 当前车队的结果（Citroën Formula E 标志、2019 电动方程式照片、Hesketh 1977 标志）。Flickr 的 4 条车手头盔定向搜索只发现 Jim Clark 1963/1965 历史展陈头盔和 LEGO 复制品相关页面；没有得到许可明确、素材类型吻合的 2026 单顶实物头盔。以上均不下载入 bundle。

| 检索路线 | 覆盖/响应 | 合格的 2026 发布素材 | 结论 |
|---|---:|---:|---|
| Commons 先前 429 的逐项低频重试 | 22 个目标；最终均得到 HTTP 200（Lawson 在 `Retry-After: 6` 后复查） | 0 | 仅发现已存的 Russell 展陈照，其余空页或无关页 |
| Commons MediaSearch | 头盔 6 项；车队 Logo 3 项 | 0 | 头盔全为历史物件，Logo 命中不属于当前 F1 车队 |
| Flickr 定向检索 | 4 个查询 | 0 | 历史头盔/玩具复制品不符合类型或赛季 |
| 权利方官方媒资条款 | F1、Audi、McLaren、Williams、Haas | 0 | 没有开放可自托管 App bundle 的明确授权 |

**第三轮结束快照（2026-10-09T04:54:45Z）：1 个仅供个人参考的新下载；当时累计 5 个外部参考，0 个仓库素材，0 个 shipping-ready。** 第四轮新增 1 个外部参考后，当前累计 6 个；最小剩余 blocker 是取得能覆盖嵌入商标/赞助标志、头盔设计与车手形象（如适用）以及应用内复制/分发的权利方授权；未联系权利人。T03 保持“研究交付，打包素材待审”，不标 `done`。

## 本次追加：开放许可复查与下载（2026-10-09T04:04Z）

重新查了 Wikimedia Commons 文件页/API 与 Openverse 许可筛选结果。Commons 按每个文件页给出来源、作者、文件许可和限制；CC BY 4.0 / CC BY-SA 4.0 允许复制、再分发（含商业用途），但分别要求署名与 ShareAlike，且许可页提醒其他权利仍可能限制实际用途。许可覆盖文件贡献者的版权，不自动清理图中车队、赞助商和商标权。[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)；[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)。

| 类别 | 检索/实际数量 | 最新判定 |
|---|---:|---|
| 头盔历史参考 | 2 个已下载 | Verstappen 2024 插画、Piastri 2024 实物照片；均有清晰 CC BY-SA 4.0 文件页，设计年份明确但只适用历史版本；因嵌入商标/图案未另获许可，仅仓库外参考 |
| 2026 头盔展示照片 | 1 个已下载 | Russell 展陈照获 CC BY 4.0；实图有 9 顶头盔，非单一车手资产，且各头盔设计年份未证实；不计有效单头盔候选 |
| 2026 车队标志 | 1 个已下载参考 | Haas 官方来源 SVG；Commons 标 `PD-textlogo`，同时明确提醒商标；版权允许不等于商标许可，仓库外参考 |
| 全部 34 项（第二轮结束快照，2026-10-09T04:04Z） | 4 个下载、4 个参考、0 个可发布 | 当时仓库素材目录无文件；34 项 `shippingReady=false`、`bundlePath=null`。24 项 `needsReview`、10 项 `restricted` |

实际下载文件均存于仓库外临时研究目录，完整路径只在本地交付说明提供；报告与 manifest 不写机器私有路径。

1. **Max Verstappen / 2024 历史头盔插画**：[Commons 文件页](https://commons.wikimedia.org/wiki/File:Max_Verstappen_Integralhelm_2024.png)，Auge=mit，CC BY-SA 4.0；[原图](https://upload.wikimedia.org/wikipedia/commons/a/ab/Max_Verstappen_Integralhelm_2024.png)。文件名 `max-verstappen-2024.png`；MIME `image/png`，PNG，2500×2300，RGBA，透明像素 2,532,612，3,236,782 bytes；视觉确认单顶侧视插画，含 Red Bull、Heineken、TAG Heuer 等标记。SHA-256：`fefa5bbbeca47dc0204798585bb221bb2f58c45e06f884a0b1f9a05e0464a67b`。`designYear=2024`，仅 historical；`rightsStatus=needsReview`、`downloadStatus=downloadedReference`。
2. **Oscar Piastri / 2024 历史头盔照片**：[Commons 文件页](https://commons.wikimedia.org/wiki/File:Oscar_Piastri_Helmet_2024.jpg)，Liauzh，CC BY-SA 4.0；[原图](https://upload.wikimedia.org/wikipedia/commons/b/b0/Oscar_Piastri_Helmet_2024.jpg)。文件名 `oscar-piastri-helmet-2024.jpg`；MIME `image/jpeg`，JPEG，3257×3257，RGB，无 alpha，1,893,060 bytes；视觉确认单顶实物头盔置于人台，无车手肖像；含赞助商/车队标志。SHA-256：`3c2d150f68409c2396e2e8cdade486930142b6315e5eef27d45d4394f844fc08`。`designYear=2024`，仅 historical；`rightsStatus=needsReview`、`downloadStatus=downloadedReference`。
3. **George Russell / 头盔展陈照片**：[Commons 文件页](https://commons.wikimedia.org/wiki/File:Kart_Silverstone_20260423_Russell_Helmets.jpg)，Mb2437，CC BY 4.0；[原图](https://upload.wikimedia.org/wikipedia/commons/3/34/Kart_Silverstone_20260423_Russell_Helmets.jpg)。文件名 `russell-helmet-display-2026.jpg`；MIME `image/jpeg`，JPEG，5712×4284，RGB，无 alpha，1,922,202 bytes；视觉确认展墙上的 9 顶头盔和展馆周边，不是单人头盔图。拍摄日为 2026-04-23，不等于设计年份；`designYear=null`。SHA-256：`9fdff31bc79e6565e5bed0a6f38908f71909bf7ed07b34a9f145a99518981f04`。`rightsStatus=needsReview`、`downloadStatus=downloadedReference`。
4. **TGR Haas F1 Team / 2026 Logo**：[Commons 文件页](https://commons.wikimedia.org/wiki/File:TGR_Haas_F1_Team_Logo_(2026).svg)，作者/来源为 Haas F1 Team，页面标注 2026-01-01 和 `PD-textlogo`，并明确 `trademarked`；[原图](https://upload.wikimedia.org/wikipedia/commons/1/18/TGR_Haas_F1_Team_Logo_%282026%29.svg)。文件名 `haas-tgr-logo-2026.svg`；MIME `image/svg+xml`，SVG，Commons 标称 512×469，实际 `viewBox=0 0 199.3864487 182.5550803`，10,855 bytes。XML 可解析；0 个 `<script>`、0 个 `href`、0 个外链 URL；Quick Look 预览确认内容为 TGR/Haas 标志。SHA-256：`37edb3462957d443c661f3e6e3a57d4897a6d2d0596dd38057a775169977a8ac`。`designYear=2026`；版权层为 `PD-textlogo`，商标未授权；`rightsStatus=needsReview`、`downloadStatus=downloadedReference`。

开放来源未提供可直接批准入 bundle 的 2026 当前阵容头像式头盔：Commons/Openverse 的可核验个人头盔项落在 2024 或更早；Openverse 对 `2026 formula one helmet` 许可筛选只返回一张 Senna 1989 头盔展览照，属于旧设计；Russell 当前年候选则是多顶展陈照。未把旧图冒充 2026，也未下载 Turn1Visuals 受限文件。Haas Commons 图版权层虽清楚，但商标警告尚未解除；其余 10 个 F1 官方 CDN Logo 仍无再分发许可。故没有任何文件写入 `helmets/` / `team-logos/`。

另复核旧候选：[Williams F1 Team (2026 logo).svg](https://commons.wikimedia.org/wiki/File:Williams_F1_Team_(2026_logo).svg) 的精确标题在 Commons API 返回 missing；不把失效文件页当许可证据，原候选保留并标失败。已有 34 个稳定记录未删改；本节记录第二轮的四份参考快照，第三轮最新累计数和 Williams 外部参考见本报告第三轮章节及 manifest `referenceDownloads`；后续首轮段落中的 0 下载数字仅描述 `2026-10-09T03:16:21Z` 的首轮快照。

## 0. 2026-10-09 名单、ID 与权利复核（首轮截至 03:16Z）

- [F1 当前车手页](https://www.formula1.com/en/drivers)和[当前车队页](https://www.formula1.com/en/teams)仍列出 22 名正赛车手、11 支车队。逐一对照后，manifest 的 22 个 `currentGrid` 车手及车队映射仍一致。
- 当日重新请求 [Jolpica 2026 drivers](https://api.jolpi.ca/ergast/f1/2026/drivers.json?limit=100)（32 条 registry）和 [constructors](https://api.jolpi.ca/ergast/f1/2026/constructors.json?limit=100)（11 条）；逐项比对 manifest 中 23 个头盔记录的 provider `driverId` / 姓名，以及 11 个 `constructorId`。再查 [Jolpica driver standings](https://api.jolpi.ca/ergast/f1/2026/driverStandings.json?limit=100)，round 16 共 23 人，额外的 Yuki Tsunoda 是赛季出赛者，不属于当前 22 人阵容；9 个 registry-only 身份仍不纳入正赛车手覆盖。
- [F1 官方 2026 阵容页](https://www.formula1.com/en/latest/article/who-are-the-2026-formula-1-drivers.3mVj9UTWK7Puz2QuScnzuz)说明 Tsunoda 转为测试／后备车手；本轮未发现当前名单变化。上轮报告中的当前阵容和 provider ID 无需改写。
- F1 后续确认[荷兰站替补安排](https://www.formula1.com/en/latest/article/red-bull-confirm-hadjar-to-miss-dutch-grand-prix-as-lawson-steps-up-and-tsunoda-returns.3D3k7oc9dUwwEBZC7upjR1)、[意大利站再次替补](https://www.formula1.com/en/latest/article/lawson-details-biggest-challenge-as-he-explains-preparation-for-next-outing-in-monza.3dlFi54JDP75xJn7R5roav.3dlFi54JDP75xJn7R5roav)和[西班牙站第三次替补](https://www.formula1.com/en/latest/article/lawson-to-stay-at-red-bull-for-third-race-weekend-in-madrid-as-hadjars-recovery-continues.Bxrk9FOVDChcWCo5vxY8v)：Liam Lawson（`lawson`）临时代 Isack Hadjar（`hadjar`）出战 Red Bull（`red_bull`），Yuki Tsunoda（`tsunoda`）填补 Lawson 的 Racing Bulls（`rb`）席位。manifest 已按站次记录，不将赛季内车队变动误写成固定 `teamId`。
- [Turn1Visuals 2026 素材页](https://turn1visuals.com/f1-2026-assets/)仍提供 22 个标为 `HELMET` 的图像候选，但页面未证明逐项实际设计年份、作者或再分发许可。其[服务条款](https://turn1visuals.com/tos/)（2026-03-13）要求未经书面许可不得复制、再分发或商业使用页面内容；因此即使已获准收集个人参考，本轮也未下载这些文件。
- [F1 IP 指引](https://www.formula1.com/en/information/guidelines)要求 F1 公司 Logo 有明确书面许可，并说明静态图片不得在未获权利人同意时重制；App 中使用其他 F1 IP 也受限制。车队／车手权利还须向相应权利人另行确认。**首轮截至 03:16Z** 尚无许可文件，因此当时未下载 Logo 或参考图；当前追加下载见本报告首节，仍只在仓库外。

| 类型 | 当前／赛季记录 | 候选页面或图片 | 已下载参考 | 许可确认、可打包 | 缺失／限制 |
|---|---:|---:|---:|---:|---|
| 当前阵容头盔 | 22 | 22 个 `HELMET` 图片候选 | 0 | 0 | 逐图年份、来源作者和许可未确认 |
| 赛季额外出赛头盔（Tsunoda） | 1 | 0 | 0 | 0 | 三站替补记录已核验；无已核验的 2026 头盔候选 |
| 当前车队 Logo | 11 | 11 个官网图片 URL | 0 | 0 | 无再分发授权；9 个官网小标 URL 路径仍标 2025，Audi / Cadillac 标 2026 |

**首轮截至 `2026-10-09T03:16:21Z` 实际下载 0 个、仓库外参考副本 0 个、可发布素材 0 个；文件级检查当时不适用。** 第二轮结束记录 4 个外部参考；第三轮新增 1 个 Williams 横版 Logo 个人参考，截至第三轮结束共 5 个；第四轮再新增 1 个后，当前累计 6 个。仓库内可发布素材仍为 0，T03 仍有商标/授权 blocker。

## 1. 核验基准与范围

- [F1 官方 2026 当前车手页](https://www.formula1.com/en/drivers)：11 支车队、22 名当前常规车手；[官方车队页](https://www.formula1.com/en/teams)交叉核对归属。正文矩阵以这份**当前阵容**为基准，不沿用 2025 阵容。
- [F1 官方 2026 车手积分](https://www.formula1.com/en/results/2026/drivers)额外包含 Yuki Tsunoda；官方报道确认他在荷兰、意大利、西班牙三站代 Liam Lawson 出赛。manifest 保留第 23 个头盔记录，但不把他强行列入当前 22 人阵容。
- 实际读取 [Jolpica 2026 drivers](https://api.jolpi.ca/ergast/f1/2026/drivers.json?limit=100)（total=32）、[constructors](https://api.jolpi.ca/ergast/f1/2026/constructors.json?limit=100)（total=11）、[driver standings](https://api.jolpi.ca/ergast/f1/2026/driverStandings.json?limit=100)（round=16，23 人），验证 ID；32 人 registry 不能直接等同“32 名当前正赛车手”。
- 官方 current-grid 与赛季积分是不同时间/口径；Jolpica 中 Lawson 的赛季 constructor IDs 同时有 `rb` / `red_bull`，不能覆盖当前官网阵容归属。
- 尚未全面核验所有 FP / 储备 / 测试参与者的出赛与头盔。额外 9 个 provider registry-only 身份保留于 manifest，明确 `notResearched`，不伪造球队或图片。

## 2. 覆盖与完成度（首轮截至 03:16Z）

| 范围 | 记录数 | 有候选页 | 直接图片 URL | 已下载 | 可打包 | 无候选 |
|---|---:|---:|---:|---:|---:|---:|
| 当前 22 人头盔 | 22 | 22 | **0 个确认原始出处**；另有 22 个第三方直接图候选 | 0 | 0 | 0 |
| 赛季额外出赛 Tsunoda | 1 | 0 | 0 | 0 | 0 | 1 |
| 车队 Logo | 11 | 11（官网） | 11（从官网 HTML 确认） | 0 | 0 | 0 |

- **首轮快照下载总数 0；可发布 bundle 总数 0；34 个研究记录均缺少可打包文件。** 截至第三轮结束已有 5 个文件且均仅为仓库外参考；第四轮新增 1 个。截至当前累计 6 个，最新计数见报告首节和 manifest `referenceDownloads`。
- 头盔 23 项 `needsReview`；官网 Logo 11 项为已知受保护的 `restricted`，并非公开版权许可。
- 5 个当前车手找到官方域名的 2026 头盔专题**搜索候选**：Norris、Piastri、Albon、Bortoleto、Hülkenberg。McLaren 两页直接读取返回 403；Audi / Williams 返回 200 但页面标题通用，未完成专题正文确认。因此 **0 个专题被计作正文与年份都已核验；0 个独立官方头盔原图**，不能声称第三方图与这些候选相同。
- [Turn1Visuals 2026 Assets](https://turn1visuals.com/f1-2026-assets/)逐车手有专门 HELMET 栏及 `img.helmet-img`；已读 HTML 提取 22 个候选地址、浏览页面并对首屏 Colapinto / Gasly 做视觉抽查，确实是独立头盔而非头像。其他 20 项仅按命名行/栏和标记确认候选，不声称已完成视觉/年份核验。
- 聚合页注明资产属于 F1、仅信息展示、非官方关联；**这不是再分发许可**。第三方候选保留在 `candidates[].imageUrl`；`sourceImageUrl` 对所有头盔保留 null，避免把它们当成已确认官方原图。

## 3. 当前阵容与头盔覆盖矩阵

`id` 使用本次 Jolpica 实际返回的稳定 `driverId`，不是 displayName / 数组下标 / 车号。以下 2026 头盔候选均未下载、未批准打包；历史参考下载单列于本报告首节和 manifest。

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

**赛季额外记录：** `tsunoda` / Yuki Tsunoda，官方赛季积分和 Jolpica 均有，当前 22 人页无。2026 荷兰、意大利、西班牙三站代 Liam Lawson 驾驶 Racing Bulls；Lawson 同三站代 Isack Hadjar 驾驶 Red Bull。对应 provider IDs 与站次见 manifest `seasonSubstitutions`；Tsunoda 的静态 `teamId=null`，不误报当前席位。未找到可靠 2026 独立头盔候选。

**registry-only 未研究 9 人：** Paul Aron (`paul_aron`)、Dino Beganovic (`dino_beganovic`)、Luke Browning (`luke_browning`)、Jak Crawford (`jak_crawford`)、Leonardo Fornaroli (`leonardo_fornaroli`)、Colton Herta (`colton_herta`)、Ryo Hirakawa (`ryo_hirakawa`)、Ayumu Iwasa (`ayumu_iwasa`)、Frederik Vesti (`frederik_vesti`)。不包含在上述 23 人头盔候选统计；若产品要展示 FP 临时参与者，后续须单独补名单/出赛依据/素材，不能把 registry 记录当作已确认正赛首发。

## 4. Logo 覆盖矩阵（首轮官方 F1 页面核验）

以下直接图地址逐项写入 manifest，由当前官方车队页 `<img src>` 提取，**不是猜测 CDN 路径，也不是赛车图**。首轮未读取这 11 个官方 F1 页面图 URL 的字节，因此当时未验证 MIME / 尺寸 / 透明通道。Logo 是官网使用的明色品牌小标，不保证是完整带赞助商的 2026 字标。

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

补充可核验文件页候选（首轮截至 03:16Z 尚未下载）：

- [Wikimedia：TGR Haas F1 Team Logo (2026)](https://commons.wikimedia.org/wiki/File:TGR_Haas_F1_Team_Logo_(2026).svg)：首轮只发现页面；追加轮已下载到仓库外并检查。文件页标 `PD-textlogo`，也标 `trademarked`；页面的版权说明不消除商标使用限制。
- [Wikimedia：Williams F1 Team (2026 logo)](https://commons.wikimedia.org/wiki/File:Williams_F1_Team_(2026_logo).svg)：追加轮对精确标题的 Commons API 查询返回 missing，文件版权、作者及适用性未能验证。
- 首轮未下载 SVG；追加轮仅下载 1 个外部 SVG 参考，仓库素材目录仍无 SVG，也无脚本或外链资源。

## 5. 授权边界与后续人工动作

1. [F1 Guidelines](https://www.formula1.com/en/information/guidelines)：品牌、版权、照片及非商业使用规则需要分别核对；[F1 Legal Notices](https://www.formula1.com/en/information/legal-notices)不能视为素材授权。
2. **匿名可访问、官网公开、CDN、personal use、非商业均不自动允许打包再分发。** 首轮没有取得媒体包/权利人对 PitPulse 分发的明确授权，也没有个人参考副本。第二轮下载 4 个 Commons 参考；第三轮新增 1 个个人参考（Williams 横版 SVG，PD-textlogo 版权状态并带商标警示），截至第三轮结束累计 5 个。第四轮新增 1 个 Unsplash 个人参考，当前累计 6 个，全部在仓库外。没有绕过认证、付费墙或访问限制。
3. 头盔须确认：设计年份、通用 / 特殊站版本、摄影/渲染作者、队徽/赞助商版权、可否裁剪与再分发及署名。若只允许本人参考，后续应仓库外存放并记录 `downloadedReference`，不得加入 bundle。
4. Logo 须确认：是否需要 2026 完整 sponsor lockup、F1 页面小标是否足够、copyright grant 与 trademark / 不冒充官方规则。Haas Commons 文件已确认 PD-textlogo 与独立 trademark 警示，仍需商标授权；Williams 精确文件标题查询缺失，未核实许可。不能把不同页面许可混用。
5. 取得许可后才下载到 `helmets/` / `team-logos/`；验证 HTTP/MIME、大小、图片身份和 SVG scripts / 外链；记录真实 SHA-256、具体许可 URL、署名要求、适用赛季，状态改为 `approved + downloadedApproved`。
6. `bundlePath` 非 null **不单独代表可发布**。接入方必须同时检查 rightsStatus、downloadStatus、存在的本地文件、hash 和适用性；任何 `needsReview` / `restricted` 记录都不得自动 copy、热链或在 Mac 运行时请求第三方 CDN。
7. 0 张可发布素材时使用**车手缩写、车队名称 / 已配置颜色**，不伪造头盔、不拿别人图代替。比赛继续国家 Emoji；通用图标继续 SF Symbols；图像缺失不影响 V1。T08 的 Asset Catalog / 明暗变体 / 构建接入未执行。

## 6. manifest 扩展字段与验证

- 最低字段均具备；`providerIds.jolpica.driverId / constructorId` 来自此次实际 API 响应。`openF1` / `f1Live` 保留 null（未核验），不猜 alias。
- `rosterRole` 区分当前阵容/仅本赛季出赛；`providerSeasonConstructorIds` 是赛季内 provider 归属，不保证当前阵容。
- `seasonSubstitutions` 记录有官方报道的替补站次、稳定 provider IDs 和来源；没有将测试／储备名单等同于参赛记录。
- `applicability.designSeason`：头盔图未确认则 null；Logo 只记录 CDN 显式路径年份。`requestedSeason=2026` 不等于许可/设计确认。
- `candidates` 是下一轮研究入口；`imageUrl` 非空不等于下载、原始出处确认或版权授权；`verification` 记录具体核验层级。
- `rightsSources` 汇总候选页服务条款和 F1 权利指引；全部 34 项均为 `shippingReady=false`、`bundlePath=null`。当前 6 个外部参考有真实 SHA-256 并列于 `referenceDownloads` 及对应资产项；其余 28 项 hash 为空。第三轮结束快照曾为 5 个参考、29 项无 hash。`registryOnlyDrivers` 单列尚未研究的 9 人，不能用它宣称赛季所有参与者素材完整覆盖。

本轮命令与观察：

```text
urllib.request.urlopen: 读取官方/候选页面 HTML；读取 Jolpica 2026 drivers、constructors、driverStandings JSON
re.findall(<img ...>): 确认 F1 官网 Logo img src；提取聚合页面 img.helmet-img
Codex in-app browser: 查看 2026 Assets 的 HELMET 栏；首屏截图视觉抽查 2 名车手
python3: JSON parse、kind+id+season 唯一、roster/provider ID 集合及状态门禁检查
python3 -m json.tool macos/Resources/MotorsportAssets/manifest.json
git diff --check -- docs/assets macos/Resources/MotorsportAssets
```

首轮截至 `2026-10-09T03:16:21Z` 未执行素材下载命令；McLaren 两个候选返回 **HTTP 403 Forbidden**，未尝试绕过；Audi / Williams 返回 200 但仅获得通用标题，专题正文尚未确认。第二轮实际用 `curl -fL` 下载 4 个 Commons 原文件并完成字节级 MIME、尺寸、图像内容、SHA-256 检查；Haas SVG 另通过 XML / script / 外链检查。第三轮通过 Commons API 下载另 1 个 Williams 横版 SVG 个人参考，完成 MIME/尺寸/hash、XML 与 SVG 脚本/外链检查并渲染预览。第四轮再增加 1 个 Unsplash 个人参考；**当前六个外部参考**的 hash 均已记录，不可当作打包素材。主要未完成项仍是 2026 头盔来源、商标/使用许可及适用性。JSON 解析、34 个三元键唯一、22+1 车手 / 11 车队数量、未授权项无 `bundlePath` 的检查已通过。

**确切交付文件：**

1. `docs/assets/collection-report.md`
2. `macos/Resources/MotorsportAssets/manifest.json`

源代码构建/测试不适用于这两个研究文件；业务、SwiftUI 及图片实际接入未完成，不应报作本任务成果。


## T08 项目内图集授权记录（2026-10-09）

用户授权将当前 33 个 2026 单盔与车队 Logo 参考文件用于 PitPulse 项目并打包进 macOS App。源文件仍保留于私用素材目录；另生成 33 个本地 PNG asset catalog 项，并在 manifest 记录项目使用范围、输出路径及 SHA-256。六份专题照片未作为默认单盔。该项目授权不改变各素材项原有的 `rightsStatus`、`license`、`shippingReady`、商标状态或其第三方来源核验结论；它不代表权利人授予公开再分发权。`shippingReadyFiles` 保持 0，项目内 bundle readiness 与公开发布许可分别记录。
