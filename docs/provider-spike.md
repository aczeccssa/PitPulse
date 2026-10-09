# 2026-10-08 Provider Spike

采样时间：2026-10-08T09:12:29Z 至 2026-10-08T09:16:00Z。未保存 token 或原始实时 feed。

| 来源 | 请求 | 状态 | 结论 |
|---|---|---|---|
| Jolpica 常规 | `/ergast/f1/2026/races.json?limit=100` | 200 | 23 个有效轮次，不含已取消站 |
| Jolpica 分页 | `limit=1` 响应含 `offset/limit/total` | 200 | 可按 offset 跟随下一页 |
| Jolpica Alpha | `/f1/alpha/schedules/2026/` | 200 | 24 个事件：23 个有效轮次 + 1 个无轮次取消站 |
| Jolpica Alpha FP1 | 澳大利亚、中国 results URL | 200 | 两场均有完整名次、车手 ID、时间，判定 `available` |
| OpenF1 | `/v1/meetings?year=2026`、`/v1/sessions?year=2026` | 200 | 含已取消巴林 / 沙特和季前测试；国家码为 alpha-3 |
| OpenF1 FP1 | `session_result?session_key=11227/11235` | 200 | 两场可匿名读取，判定 `available` |
| OpenF1 Race | `session_result?session_key=11234` | 200 | DNF / DNS 的 `position` 为 JSON null |

赛历主源使用 Jolpica Alpha。OpenF1 只补充 session key 和结束时间，不覆盖 Alpha 的赛站身份。常规 Jolpica 仅作对照，因为采样时缺少取消站。
