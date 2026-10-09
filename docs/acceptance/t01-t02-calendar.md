# T01 / T02 验收记录

离线测试使用 `server/tests/fixtures/`，不访问网络。真实上游采样单独记录在 `docs/provider-spike.md`，采样时间为 2026-10-08T09:12:29Z。

手工 smoke 与 CI 分开：CI 只运行 fixture。2026-10-08T09:44:40Z 对 `https://api.jolpi.ca/f1/alpha/schedules/2026/` 的只读 smoke 返回 HTTP 200、24 个事件、23 个有效轮次和 1 个取消站。上游失败保留缓存由离线超时测试覆盖。
