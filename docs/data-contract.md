# PitPulse V1 数据契约

`schemaVersion` 固定为 `1`。所有时间使用 RFC 3339 UTC，JSON 字段使用 lowerCamelCase。

```json
{
  "data": [],
  "meta": {
    "schemaVersion": 1,
    "revision": 1,
    "stale": false,
    "quality": "provisional",
    "source": "jolpica-alpha",
    "fetchedAt": "2026-10-08T00:00:00Z",
    "sourceUpdatedAt": "2026-10-08T00:00:00Z"
  }
}
```

- `fetchedAt` 是 PitPulse 抓取时间；`sourceUpdatedAt` 是上游给出的修正时间，可空。
- 赛历 `revision` 只在赛站时间或取消 / 延期状态变化时递增；成绩和积分 `revision` 只在内容、来源或质量变化时递增。仅抓取时间更新不产生新 revision。
- `quality` 为 `pending`、`partial`、`provisional`、`final`、`stale`。没有来源证据不得标 `final`。
- 上游暂无成绩时返回空 `data` 和 `quality=pending`，HTTP 200；未知资源仍返回 404，鉴权失败返回 401。

Meeting ID 为 `season:round`；没有轮次的取消站为 `season:cancelled:providerRoundId`。Session ID 为 `meetingId:sessionType`。Session 类型只有 `fp1`、`fp2`、`fp3`、`sprintQualifying`、`sprint`、`qualifying`、`race`。季前测试不进入 V1 赛历。

成绩 `position` 可空。未分类、DNS、DNF、DSQ 不使用 `0` 填充，分类放在 `classification`。

`GET /api/v1/sessions/{sessionId}/results` 返回单一最新 revision。已知 Session 暂无结果时返回 `200`、空 `data` 和 `quality=pending`；未知 Session 返回 `404`。成绩保留兼容字段 `time`，并可提供 `bestLap`、`q1`、`q2`、`q3`、`raceTime`、`gap`、`laps` 和 `points`；缺失值不填 `0`。排位被淘汰阶段没有时间属于有效空值。练习赛不拼接不同 Provider 的行；完整快照优先，partial 按已映射参与者覆盖选择，平局优先 Jolpica Alpha。未知 Provider 身份使用带来源前缀的原始 ID，并使快照保持 `partial`。`final` 只在 Provider 提供明确终结证据时使用。

`GET /api/v1/standings/drivers` 和 `/api/v1/standings/constructors` 返回 Jolpica Ergast 官方积分快照，不由 PitPulse 重算。省略 `season` 时使用 UTC 当前年份；仅接受 1950–9999。WDC 保留旧字段 `constructor`，并提供稳定 ID 列表 `constructorIds`；车手当季服务过多个车队时，旧字段列出相应名称，客户端应以 ID 列表表达多车队关系，不把其中一队当作当前归属。成绩和积分 meta 提供 `source`、真实 `fetchedAt`、`revision`、`quality` 和六小时过期状态；未知 `sourceUpdatedAt` 保持空值。

赛历缓存以抓取时间判断过期：任一赛事距最近抓取超过 6 小时，calendar 和 meetings/next 的 meta.stale 为 true、quality 为 stale；成功刷新后恢复。离线缓存仍可读取，不伪造新鲜度。
