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
- `revision` 只在赛站时间或取消 / 延期状态实际变化时递增。
- `quality` 为 `pending`、`partial`、`provisional`、`final`、`stale`。没有来源证据不得标 `final`。
- 上游暂无成绩时返回空 `data` 和 `quality=pending`，HTTP 200；未知资源仍返回 404，鉴权失败返回 401。

Meeting ID 为 `season:round`；没有轮次的取消站为 `season:cancelled:providerRoundId`。Session ID 为 `meetingId:sessionType`。Session 类型只有 `fp1`、`fp2`、`fp3`、`sprintQualifying`、`sprint`、`qualifying`、`race`。季前测试不进入 V1 赛历。

成绩 `position` 可空。未分类、DNS、DNF、DSQ 不使用 `0` 填充，分类放在 `classification`。

赛历缓存以抓取时间判断过期：任一赛事距最近抓取超过 6 小时，calendar 和 meetings/next 的 meta.stale 为 true、quality 为 stale；成功刷新后恢复。离线缓存仍可读取，不伪造新鲜度。
