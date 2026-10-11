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
- 赛历 `revision` 在赛站内容（含地点坐标）、时间、来源或取消 / 延期状态变化时递增；成绩和积分 `revision` 只在内容、来源或质量变化时递增。仅抓取时间更新不产生新 revision。
- `quality` 为 `pending`、`partial`、`provisional`、`final`、`stale`。没有来源证据不得标 `final`。
- 上游暂无成绩时返回空 `data` 和 `quality=pending`，HTTP 200；未知资源仍返回 404，鉴权失败返回 401。

Meeting ID 为 `season:round`；没有轮次的取消站为 `season:cancelled:providerRoundId`。Session ID 为 `meetingId:sessionType`。Session 类型只有 `fp1`、`fp2`、`fp3`、`sprintQualifying`、`sprint`、`qualifying`、`race`。季前测试不进入 V1 赛历。

成绩 `position` 可空。未分类、DNS、DNF、DSQ 不使用 `0` 填充，分类放在 `classification`。

`GET /api/v1/sessions/{sessionId}/results` 返回单一最新 revision。已知 Session 暂无结果时返回 `200`、空 `data` 和 `quality=pending`；未知 Session 返回 `404`。成绩保留兼容字段 `time`，并可提供 `bestLap`、`q1`、`q2`、`q3`、`raceTime`、`gap`、`laps` 和 `points`；缺失值不填 `0`。排位被淘汰阶段没有时间属于有效空值。练习赛不拼接不同 Provider 的行；完整快照优先，partial 按已映射参与者覆盖选择，平局优先 Jolpica Alpha。未知 Provider 身份使用带来源前缀的原始 ID，并使快照保持 `partial`。`final` 只在 Provider 提供明确终结证据时使用。

`GET /api/v1/standings/drivers` 和 `/api/v1/standings/constructors` 返回 Jolpica Ergast 官方积分快照，不由 PitPulse 重算。省略 `season` 时使用 UTC 当前年份；仅接受 1950–9999。WDC 保留旧字段 `constructor`，并提供稳定 ID 列表 `constructorIds`；车手当季服务过多个车队时，旧字段列出相应名称，客户端应以 ID 列表表达多车队关系，不把其中一队当作当前归属。成绩和积分 meta 提供 `source`、真实 `fetchedAt`、`revision`、`quality` 和六小时过期状态；未知 `sourceUpdatedAt` 保持空值。

赛历缓存以抓取时间判断过期：任一赛事距最近抓取超过 6 小时，calendar 和 meetings/next 的 meta.stale 为 true、quality 为 stale；成功刷新后恢复。离线缓存仍可读取，不伪造新鲜度。


## 地图、天气和 Live 扩展

所有新接口遵循现有 Bearer 配置与 error envelope；远程部署应启用 `require_token`。地图页面不会获得 PitPulse Bearer，只获得公开只读 Mapbox token、地点/赛道几何及必要车手标记。Mapbox GL JS 固定 `3.32.0`，默认 `mapbox://styles/mapbox/standard` 夜间风格；官方脚本、地图瓦片、字体、地形和模型直连是客户端第三方网络规则的唯一地图渲染例外。F1、Open-Meteo、RainViewer 及 Radio 仍由 Rust 获取。

Meeting 可缺省 `circuit: { id?, name?, latitude, longitude }`。SQLite migration 7 增加可空地点 JSON；旧数据库和客户端缓存没有地点时保持未知，不用中心猜测车位。地点修正纳入赛历 revision。

| 接口 | 返回内容 |
| --- | --- |
| `GET /api/v1/maps/config` | `data.publicToken`（缺失为 null）、style、version；no-store |
| `GET /api/v1/meetings/{meetingId}/geometry` | GeoJSON Feature、source、status、layoutVerified、calibrated、layout；没有已核验布局时明确标记 |
| `GET /api/v1/meetings/{meetingId}/weather` | status 与 hours；每小时 `utc`、airTemp、precipitationProbability、precipitation、weatherCode、windSpeed；缺值为 null |
| `GET /api/v1/weather/radar` | 过去约两小时的 frames：固定资源 `id` 与 RFC 3339 `utc`，maxZoom=7；不投影 nowcast |
| `GET /api/v1/weather/tiles/{kind}/{frame}/{z}/{x}/{y}` | PNG；kind 仅 radar/coverage，radar 必须是已知帧，z<=7 且 x/y 在范围内 |
| `GET /api/v1/live/radio/{session}/{id}` | 已收到条目的音频；session 必须匹配当前 Session；客户端不得传入 URL |

天气预报使用 Open-Meteo UTC 当天起 16 天窗口。过去的赛事返回 past_event，窗口外返回 outside_forecast_window；Session 未给结束时间时沿用 start+2h 的估计边界，只用于窗口判断。实况只来自 F1 WeatherData，预报不会填入 Live 实况。雷达为历史观察；无覆盖用官方 coverage mask 的黑色区域表示，不能据透明瓦片推断无雨。RainViewer 请求共享限速（间隔至少 650ms）、缓存和 429 Retry-After 冷却；仅使用 Universal Blue（color=2），coverage 使用 color=0。失败时缓存返回 stale；Swift 不渲染新收到的 stale 瓦片。

二进制响应通过 `X-PitPulse-Source`、`X-PitPulse-Fetched-At`、`X-PitPulse-Stale` 提供来源/时效，使用 private/no-store。音频 URL 只能由已接收 SessionInfo.Path 和 TeamRadio capture 组合固定 `https://livetiming.formula1.com/static/` 主机；禁止绝对路径、`.`/`..`、百分号编码、查询串和重定向，响应限制 16MiB。默认手动播放；下载取消、切条目、切服务器/Session、收起/隐藏和消息页切换停止单播放器，并删除临时文件。

SSE 仍为 `snapshot`、`schemaVersion:1`。新字段可缺省：`circuitKey`、`circuitName`、`weather`、`teamRadio`；driver 可缺省 `location` 和 `telemetry`。location 包含原始 XY、独立 utc、status、校准后可空 longitude/latitude；原始 Z 不当作地理海拔。telemetry 包含 utc、rpm、speed（km/h）、gear、throttle、brake、drs（保留上游状态码）。WeatherData 使用独立 utc，其他 Topic 不刷新它的时效。位置和遥测在 Live 超过 10 秒、天气超过 120 秒时不继续显示为新鲜；显式 replay 保留来源标记。

Position.z/CarData.z Base64 + raw-deflate 的编码及解压内容各限制 2MiB；损坏、未完整结束、尾部垃圾、超限帧不更新状态。多帧、稀疏通道及乱序按每车 UTC 合并；Session 切换清理位置、遥测、天气、Radio 与旧 Session 路径。Race Control 保留旧 Message/Category/Flag 等字段兼容已有客户端，新投影增加 lowerCamelCase 的 id、utc、lap、driverNumber、category、flag、scope、sector；按 UTC 倒序并使用稳定索引 ID。Radio 路径与 Session 静态路径永不序列化给客户端。

有变化的快照每 100ms 至多发送一次（最多 10 Hz）；连接状态/模式/原因变化立即发送，保留 10–30 秒定期完整快照。watch 通道只保留最新状态，慢消费者不会积累帧队列。实际遥测按上游采样更新，不插值或伪造车速/RPM 等值。赛道校准的来源、年份、控制点和独立误差门槛见 `server/resources/circuits/README.md`。
