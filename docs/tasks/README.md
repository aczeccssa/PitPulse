# PitPulse 任务状态看板

零依赖的静态任务报告，无构建步骤、无后端写入、无第三方 CDN。页面通过 `fetch` 读取同目录的 `tasks.json`；**该 JSON 是任务当前状态的唯一数据源**。

## 打开页面

在仓库根目录运行：

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

然后打开 `http://127.0.0.1:8765/docs/tasks/`。不要双击使用 `file://` 打开：浏览器通常不允许这样读取 JSON。服务只绑定本机；这里只是文档预览，不是 PitPulse 业务服务，也没有引入新的生产后端。

页面支持任务搜索、状态与里程碑筛选、任务详情／验收展开、手动刷新与数据错误提示。统计和进度由 JSON 计算，完成率 = `done` 任务数 / 全部任务数；未开始或部分研究不算完成。每次刷新忽略缓存，无轮询，任务数据不落任何本地副本。

页面支持浅色与深色两套配色，顶栏提供「自动 / 浅色 / 深色」三态切换：默认跟随系统外观，也可手动固定。该偏好以 `localStorage` 的单一键 `pitpulse.board.theme` 持久化——它只保存界面外观偏好，与任务数据无关（任务状态仍然只来自 `tasks.json`）。主题在首帧渲染前由 `index.html` 的 `<head>` 内联脚本落地，避免深色用户看到一瞬间的白闪。

## 文件分工

- `index.html`：语义化静态页面骨架，`<head>` 内含在建首帧前落地主题的内联脚本。
- `favicon.svg`：站点图标。形态对齐顶栏 `.brand-mark`（圆角块 + 八角辐条星），配色随系统浅色／深色自动切换。
- `board.css`：设计令牌与组件样式。浅色令牌定义在 `:root`，深色令牌在 `:root[data-theme="dark"]` 覆盖；组件规则只引用令牌（`var(--*)`），不写裸色值——否则深色下会露白。新增主题相关样式时需同时补齐两套令牌。
- `board.js`：样式与展示逻辑，不保存业务任务副本；另含主题三态状态机。
- `tasks.json`：完整任务卡、当前状态、依赖、验收、证据与历史。
- `task-schema.mjs`：浏览器与 CLI 共用校验规则。
- `validate.mjs`：本地校验，包括已记录文档路径是否存在。
- `tests/task-data.test.mjs`：状态、完整性、依赖、证据、时间与路径回归测试。

HTML 不编辑 JSON，也不会写回文件。开始、继续、验收或完成任务，直接修改 JSON 并刷新页面即可。

## 状态与更新规则

| status | 展示 | 用途 |
|---|---|---|
| `pending` | 待开始 | 尚未实施 |
| `inProgress` | 进行中 | 正在推进或部分交付；局部待审不等于整个任务 blocked |
| `inReview` | 待验收 | 实现已交付，验收尚未完成 |
| `done` | 完成 | 全部验收通过，有证据且无未解决阻塞 |
| `blocked` | 受阻 | 无法继续，必须填写具体 blockers 与所需下一步 |

修改相关任务时，至少维护：

1. `status`、`summary`、`nextAction`、任务 `updatedAt`。
2. `acceptanceCriteria[].done`：只勾实际通过的项。
3. `deliverables`、`evidence`：记录真实交付与命令／观察结果；`path` 仅填写实际存在的仓库相对路径。
4. `blockers`：解释未解决事项；研究完成但授权、下载或接入未完成，不得标 `done`。
5. `history`：末尾追加一条 `{ "at": "...Z", "status": "...", "note": "..." }`；同状态下的实质进展也要记。不要改写旧历史。
6. 顶层 `updatedAt`：同步为此次更新时间。全部时间是 RFC 3339 UTC，以 `Z` 结尾；展示按 `project.timezone`（Asia/Shanghai）。

任务 ID 稳定。新增／删除／调整依赖时，同时维护 `milestones[].taskIds`；任务不能引用自身或形成硬依赖环。`relatedTasks` 表示非硬阻塞关联，T03 素材缺失不阻塞 V1。JSON 中的 `steps`、`scope`、验收文本按纯文本显示，避免把用户输入作为 HTML 执行。

`implementation-sequence.md` 保留架构、任务定义和实施顺序，不再维护重复的当前状态表。需求变更时同步修改计划与 JSON 的任务定义；日常进度只需更新 JSON。`AGENTS.md` 规定所有 Agent 必须遵守此约定。

## 检查

```sh
node docs/tasks/validate.mjs
node --test docs/tasks/tests/task-data.test.mjs
node --check docs/tasks/board.js
```

初始化快照包含 T01～T15：T03 处于 `inProgress`（首轮素材研究已交付、0 下载／0 可打包），其余 `pending`。该描述仅解释初始化；后续当前状态始终读取 JSON，不需要修改这段历史说明。
