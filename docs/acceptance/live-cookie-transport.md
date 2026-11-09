# Sprint Live connection correction — 2026-10-10

This is observed runtime evidence from the normal server and sole main App, not a replay or UI automation pass. The existing server binds loopback and uses its existing database outside the repository. No mouse, keyboard, display setting or VoiceOver operation was performed.

## Root causes and changes

- F1's `feed` callback carries topic, patch and timestamp as three arguments. Reading argument zero alone discarded updates. The pinned SignalR client's callback now normalizes all three; its registration is explicitly released on every exit because its handle does not unregister on drop.
- WebSocket upgrade returned HTTP 404 after negotiation. The negotiation supplied affinity cookies that `signalr-client = 0.3.2` did not forward. After a handshake failure, a small SignalR Core adapter uses the already installed `tokio-websockets = 0.13.3`, forwards negotiation cookies and optional bearer authentication, subscribes to the same eight Topics, validates sizes, decodes record-separated frames and closes on cancellation. Unauthorized/forbidden responses remain failures. Production never switches into replay.
- `SessionInfo.Name = Sprint` now takes precedence over broad `Type = Race`. `Position` takes precedence over the line index. Non-driver metadata entries are ignored.
- TimingData's three sectors expose optional time, personal/overall fastest flags and sparse segment statuses. Array snapshots merge numeric object deltas without losing unchanged sectors/segments. LapCount also supplies optional total laps. Session meeting name and country are matched uniquely to the calendar before using a flag.
- The main App shares its existing LiveStore. Expanded timing is 860 wide, vertically scrollable, with helmets from the existing bundle, position, full name/team, gap/interval, last/best lap and three sector columns. Compact content includes Session state and favorite helmet/name/position/gap. Helmets require a unique normalized full-name roster match; missing or ambiguous identity uses an abbreviation. No team, position or fuzzy-name guess is introduced.
- Sector colors use raw feed status codes, with unknown values neutral. The supporting [producer schema notes](https://github.com/matteocelani/f1-telemetry/blob/main/docs/live-timing-types.md#timingdata--timingdataf1) distinguish 2048/2049/2051/2064 and explain sparse array updates. Accessibility announces sector value and personal/overall fastest without relying only on color. Tyres, pit counts and vehicle telemetry remain explicitly unavailable; no new Topic is subscribed.
- Default tracing suppresses dependency payload logs. Diagnostics record fixed failure classes/status, affinity-cookie presence, source mode, counts and state versions; credentials, cookies and raw feed are not recorded here.

## Observed real upstream

Times below are UTC. GET `/api/v1/live/snapshot` returned its normal `data` envelope:

| Observed | State version | Source | Session status | Laps | Drivers |
| --- | --- | --- | --- | --- | --- |
| 09:36:12 | 7 | live / connected | Inactive | 1 / 20 | 22 |
| 09:36:41 | 47 | live / connected | Started | 1 / 20 | 22 |
| 09:36:51 | 167 | live / connected | Started | 1 / 20 | 22 |
| 09:37:01 | 265 | live / connected | Started | 1 / 20 | 22 |
| 09:38:27 | 1074 | live / connected | Started | 2 / 20 | 22 |
| 09:39:45 | 1746 | live / connected | Started | 2 / 20 | 22 |

All 22 timing rows projected exactly three sector columns. At 09:38:27, 25 sector times were nonempty; at 09:39:45, 21 were nonempty. The changes and empty values are actual upstream data, not filled from a fixture. SessionInfo identified Singapore Grand Prix / SG. The observed Started event arrived after the calendar's scheduled start; the client does not fabricate Started from a schedule.

The sole rebuilt main App launched at 09:38:48. Its controller logged `automaticStarted` and `compact`, automatic=true, panelKey=false and appActive=false. At 09:39:49, the main App's actual LiveStore logged `snapshotAccepted generation=1 connection=1 version=1767 status=connected mode=live drivers=22`, and its controller logged the matching content update with panelKey=false/appActive=false. Comparing the normal server roster against current Live full names found 21 unique matches and 21 existing helmet assets out of 22 drivers; the remaining identity uses an abbreviation rather than a guessed helmet. These are launch and automatic-focus diagnostics; they do not replace the user's visual/interaction or VoiceOver acceptance.

## Verification

- `cargo test --locked --manifest-path server/Cargo.toml --all-targets`: 66 passed, no skips. Includes a loopback negotiate/WebSocket peer asserting affinity cookie, bearer header, subscription Topics, split handshake, combined completion/feed records and shutdown; also callback argument/lifecycle, sparse sectors, Sprint identity and missing metadata regression tests.
- `cargo clippy --locked --manifest-path server/Cargo.toml --all-targets -- -D warnings`: passed.
- `cargo fmt --manifest-path server/Cargo.toml -- --check`: passed.
- `xcodebuild -project PitPulse.xcodeproj -scheme PitPulseDesktop build`: passed.
- `xcodebuild -project PitPulse.xcodeproj -scheme PitPulseDesktop build-for-testing`: passed; test hosts were not launched.
- Terminal `swiftc` compiling the actual APIModels, CalendarLogic, LiveModels and LiveIslandLogic: 14 assertions passed for optional sector decoding, missing values, helmet/favorite unique identity, duplicate rejection, Session label, total-lap label and replay/stale labels.

New XCTest cases compiled but were not run under the user's prohibition on desktop test automation. The local replay fixture includes synthetic sector times/statuses and missing-sector coverage; it was not substituted for the live server. New UI screenshots, actual hide click, favorite selection, menu coexistence, external-display changes and VoiceOver still require user-operated acceptance. No commit or push was made.
