# F1 Live SignalR spike

**Observed:** 2026-10-10 (Asia/Shanghai), macOS 26.5. **Result:** partial availability.

The probe uses the pinned Rust `signalr-client = 0.3.2` against `https://livetiming.formula1.com/signalrcore`. It ran anonymously (`F1_LIVE_ACCESS_TOKEN` absent); this is separate from the PitPulse API token `F1_COMPANION_TOKEN`. No credentials, cookie values, or raw feed frames were written to the repository.

## Observations

| Capability | Result | Evidence |
|---|---|---|
| Negotiate and WebSocket | available | The negotiate request succeeded and the SignalR Core WebSocket connection opened. An OPTIONS preflight returned 405, but that did not prevent negotiation or connection. |
| Subscribe initial response | available | `Subscribe` returned initial keys for `DriverList`, `Heartbeat`, `RaceControlMessages`, `SessionInfo`, `SessionStatus`, `TimingData`, and `TrackStatus`. This proves topic-key availability, not non-empty timing fields. |
| Feed fields and heartbeat freshness | partial | The 30-second anonymous window delivered no `feed` callback, so no live field changes or periodic heartbeat were observed. The probe stopped itself cleanly at the end of the window. |
| In-session timing freshness | unverified | The observation was outside an active race session. No claim is made about live-session timeliness or authenticated access. |

The fixed `signalr-client` path completed negotiate, WebSocket setup, handshake, and `Subscribe`; there was no observed compatibility gap that would justify switching to `tokio-tungstenite`. `signalr-client` remains pinned. A legal upstream token can be provided later through `F1_LIVE_ACCESS_TOKEN`; it must not be replaced by the independent PitPulse API token.

The selected live topics avoid the high-volume compressed telemetry feeds. Fast-F1's topic list identifies `Position.z` and `CarData.z` as separate `.z` topics; those require a compressed-data decoder and were not subscribed to or verified in this spike. They remain outside the current reducer. See [Fast-F1 live timing client](https://github.com/theOehrly/Fast-F1/blob/main/fastf1/livetiming/client.py) and its [topic mapping](https://github.com/theOehrly/Fast-F1/blob/main/fastf1/_api.py).

## Reproduction

```sh
cargo run --manifest-path server/Cargo.toml --example f1_live_probe
```

The probe prints whether an upstream token is configured, initial topic names, received topic names, and connection termination only. It has a 30-second observation window and does not persist payloads. Authentication failures, a real feed update, and race-session freshness still require a lawful credential/session observation.
