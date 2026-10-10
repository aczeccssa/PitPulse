# T07 成绩与积分闭环验收

验收日期：2026-10-09。范围：Provider 解码、SQLite 快照、启动同步与 REST。T08 素材打包、T09 周期同步未执行。

## 实现

- Jolpica Alpha 提供七种 Session 成绩；练习赛同时探测 Alpha 与 OpenF1，选先返回的完整快照。若都不完整，按稳定 ID 已映射的参与者覆盖选择，平局优先 Alpha。不会拼接不同来源的成绩行。
- Jolpica Ergast 常规分页端点提供 WDC / WCC 官方积分快照；PitPulse 不计算积分。WDC `constructorIds` 保留赛季内多车队 ID，旧 `constructor` 字段仍在。
- 新增 migration 0004，保留旧成绩并增加可空阶段时间和来源身份映射。结果／积分用事务替换最新快照；内容、来源或质量变化才升 revision。失败、空结果、较差 partial 和写入回滚均保留上一份可读缓存。
- 已知但尚无成绩的 Session 返回 `200 + pending`；未知 Session 返回 `404`。省略 standings season 使用 UTC 当前年份；限制输入年份为 1950–9999。成绩与积分 meta 提供 source、fetchedAt、revision、quality、过期状态；未知 sourceUpdatedAt 为空。
- 无授权图片仍由 T03 阻塞，和 T07 / V1 无依赖关系。

## 可重复验证

| 验证 | 结果 |
|---|---|
| 七种 Session fixture | 通过；FP1、FP2、FP3、Sprint Qualifying、Sprint、Qualifying、Race 均有 Alpha fixture。 |
| 两源选择、partial 升级、处罚修正、DNF / DNS / DSQ、无有效圈与未知身份 | 通过；未知身份保留来源 ID 并标 partial，可空时间不填 0。 |
| OpenF1 限流与 Retry-After | 本地 mock 返回 503 + `Retry-After: 0`；逐次重试仍遵守 350 ms 最小请求间隔。 |
| SQLite 快照、revision、回滚、空响应保留、v3 旧库升级 | 通过；旧成绩与旧 revision 保留，新增字段读取为空。 |
| 本地 Provider mock 启动同步 | 通过；results、WDC、WCC REST 均非空；随后上游断开，缓存行与 revision 未变。 |
| REST 状态与授权 | 通过；两种 standings API 有非空数据测试及 Bearer 401/200 测试；未知 Session 为 404；非法 season 为 400；无结果 Session 为 `200 + pending`。 |
| `cargo test --locked --manifest-path server/Cargo.toml` | 通过，37 passed。 |
| `cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings` | 通过。 |
| `cargo build --release --locked --manifest-path server/Cargo.toml` | 通过。 |

测试代码：[`results_sync.rs`](../../server/tests/results_sync.rs)、[`storage.rs`](../../server/tests/storage.rs)、[`api.rs`](../../server/tests/api.rs)；七种 fixture 解码见 [`results.rs`](../../server/src/providers/results.rs)。

## 真实历史周末 smoke

2026-10-09T03:31:47Z，以本地 release server 启动并读取真实 Provider 缓存；只记录本地 REST 的状态和数量，不保存原始上游响应。

| REST 路径 | HTTP | 数量 | meta |
|---|---:|---:|---|
| `/api/v1/calendar?season=2026` | 200 | 24 meetings | — |
| `/api/v1/sessions/2026:15:race/results` | 200 | 22 rows | source=`jolpica-alpha`，quality=`provisional`，revision=1，sourceUpdatedAt=`2026-10-09T03:31:44.811318Z` |
| `/api/v1/standings/drivers?season=2026` | 200 | 23 rows | source=`jolpica-ergast`，revision=1 |
| `/api/v1/standings/constructors?season=2026` | 200 | 11 rows | source=`jolpica-ergast`，revision=1 |

对应调用源包括 [Jolpica Alpha](https://api.jolpi.ca/f1/alpha/schedules/2026/) 赛历 / Session 结果、Jolpica Ergast drivers / constructors / driverStandings / constructorStandings 分页端点，以及 [OpenF1 drivers](https://api.openf1.org/v1/drivers?session_key=11377) Session 名单。OpenF1 历史 `session_result` 字段以[官方文档](https://openf1.org/docs/)为准；本次 Race 返回来源为 Alpha。

2026-10-09T03:33:30Z 单独直连上游复核状态和数量：

| 上游 GET 路径 | HTTP | 数量 |
|---|---:|---:|
| `https://api.jolpi.ca/f1/alpha/schedules/2026/` | 200 | 24 events |
| `https://api.jolpi.ca/f1/alpha/results/round_St4SXfGd/R/` | 200 | 22 results |
| `https://api.jolpi.ca/ergast/f1/2026/driverStandings.json?limit=100` | 200 | 23 drivers |
| `https://api.jolpi.ca/ergast/f1/2026/constructorStandings.json?limit=100` | 200 | 11 constructors |
| `https://api.openf1.org/v1/drivers?session_key=11377` | 200 | 22 session drivers |

## 未完成边界

- 本次证明一个已结束历史周末可启动同步、持久化并由 REST 读取；未证明真实赛后分钟级延迟。该项需真实比赛期间继续观察。
- 没有周期轮询；T09 保持未实现。T08 资源目录 / Asset Catalog 接入保持未实现。
- Provider 未提供终结证据时结果保持 `provisional`，本次 smoke 未将其标成 `final`。

## 本地提交前最终质量门禁（2026-10-09T06:08:46Z）

| 命令 | 结果 |
|---|---|
| `cargo fmt --manifest-path server/Cargo.toml -- --check` | 通过 |
| `cargo test --locked --manifest-path server/Cargo.toml` | 37 passed，0 failed |
| `cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings` | 通过 |
| `cargo build --locked --release --manifest-path server/Cargo.toml` | 通过 |

真实历史周末 smoke 结果仍见上文；本次质量门禁未重新发起外部网络 smoke。

## 2026-10-10 新加坡 Sprint 实际空榜修正

用户报告 Sprint 结束后仍无成绩。2026-10-10T11:08:31Z 实际检查主源 [Jolpica Alpha SR](https://api.jolpi.ca/f1/alpha/results/round_nxOKfUxB/SR/) 返回 HTTP 200 / 0 行，但已有补源 [OpenF1 session_result](https://api.openf1.org/v1/session_result?session_key=11383) 返回 HTTP 200 / 22 行。SQLite 和 REST 当时均为 0 行、pending；同步每 5 分钟尝试，故障并非 App 没有刷新，而是 `sync_session_once` 在非练习赛分支只读 Alpha。

修正仅在 Sprint 的 Alpha 为空或失败且 OpenF1 已启用、Session 有可靠 key 时调用既有补源。主源非空仍优先，后续主源可读可形成正常修订；补源实际字段直接经过现有解码/身份映射/事务写入，不从 Live 末圈排行生成成绩或计算积分。空榜和失败不覆盖缓存，Alpha 限流的 Retry-After 保留。候选选择优先非空，避免无稳定 ID 的 partial 补源与空榜打平时丢失实际结果。

重建并重启现有唯一服务器后，2026-10-10T11:14:32Z 的正常调度将 `2026:17:sprint` 写入 revision 1：REST 返回 22 行，source=openf1、quality=partial、stale=false；领先车手 Max Verstappen，20 圈、8 分，来自结果接口字段。nextRetryAt=11:44:32Z，遵守已有成功后复核周期。没有手动写入成绩或修改同步状态，没有额外回放/服务进程。partial 仍保留缺项和身份映射边界，不宣布 final；此证据证明这次赛后接口可读/持久化，不能推出所有赛事的分钟级开放保证。

新增 loopback 集成测试覆盖主源空榜补源可读、主源恢复不请求补源、两源空榜保留缓存、Alpha 429 的 120 秒 Retry-After、补源失败保留缓存、补源禁用及缺 Session key；缺 points 不推算。新增候选测试覆盖两个顺序下 partial 未映射结果均胜过空榜。`cargo test --locked --manifest-path server/Cargo.toml` 共 68 passed / 0 failed；fmt 和严格 all-targets clippy 通过。

最终检查：`cargo fmt --manifest-path server/Cargo.toml -- --check`、`cargo test --locked --manifest-path server/Cargo.toml`（68/68）、`cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings`、`cargo build --locked --release --manifest-path server/Cargo.toml` 全部通过。当前运行的正常服务使用新的 debug binary；release build 仅用于质量门禁，没有启动第二个服务器。任务数据校验、8 项 task-data 测试与 diff 检查通过。

## 2026-10-10 详细分析扩展

按用户新需求扩展服务器按需分析与原窗口二级页面；真实 Sprint 圈速/赛段/赛道遥测及逐站积分已读通。实现、数据含义、实际缺项、命令结果与人工验收边界见 [详细分析验收](analysis.md)。这份追加记录不改写此前验收历史。
