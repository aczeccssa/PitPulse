# Local real-source runtime under Taskdeck

2026-10-11: the user requested switching back from the isolated Singapore replay, rebuilding/running the current workspace, and using `taskdeck init` to configure `Run Server` and `Run App`.

## Configuration

- `taskdeck init --session PitPulse --json` created and registered the project; `taskdeck update --session PitPulse --json` loaded the final two-task configuration. The installed CLI supports init/update/register and has no schema subcommand; successful update is the configuration loading proof.
- `taskdeck.yaml` orders `Run Server` before `Run App`. Both are manual tasks (`auto_start: false`) and directly supervise their foreground process using exec. No detached `open` launcher is used for the managed App.
- Server builds the locked current Rust workspace, reads optional local F1 environment configuration and the Mapbox public token from user Application Support, and preserves the existing database. No credentials or database contents enter the YAML or repository.
- App builds the current Swift workspace into the user cache and runs the actual App executable with `-serverAddress http://127.0.0.1:38701`. Demo overrides for season, reminders and auto-show are absent, so normal preferences apply. Server availability is handled by the existing retry path.
- The old standalone server, replay and App were stopped after checking their exact executable identities. The replay listener on 38974 is gone.

## Lifecycle observations

- Initial task start produced one server and one main App, both children of the Taskdeck daemon. Server health returned `status=ok`, `database=true` and `live=true`; the map configuration retained a public token (token value omitted).
- First server restart exposed an older ephemeral launchctl `com.pitpulse.local-acceptance-server` KeepAlive registration: it repeatedly attempted to acquire port 38701 and won during shutdown, making the replacement task fail with address-in-use. The old launchctl registration was booted out; its configuration, database and logs were preserved. No unrelated Taskdeck session or daemon was stopped.
- After removing that competing owner, a second Server start/restart succeeded and the old supervised Server exited with code 0. App stop/start/restart also succeeded. Final task generations were Server 4 / App 3, each running; their actual process IDs match Taskdeck's IDs.
- Latest App unified logs accept `mode=live`, `status=stale`, 22 drivers. Real source session 11384 reports `Ends`, with WeatherData and 12 Radio entries; no current Position/CarData is provided. This is an ended real-source state and does not prove active-race telemetry, vehicle motion, Radio playback or UI acceptance. No fallback to replay is used.

## Checks and boundaries

- `cargo build --locked --manifest-path server/Cargo.toml`: passed.
- `xcodebuild -quiet -project PitPulse.xcodeproj -scheme PitPulseDesktop -destination 'platform=macOS' -derivedDataPath <user-cache> build`: passed; the expected multiple-architecture destination warning was non-fatal.
- Python launcher AST parse and `bash -n scripts/run-app.sh`: passed.
- Task data validation and eight task-data tests: passed; `git diff --check`: passed.
- Process ownership, listener uniqueness, actual Taskdeck stop/restart and App `snapshotAccepted` logs were checked. No native UI automation or full XCTest suite was run for this operational switch. Existing real-race, external-display, VoiceOver, radar and audio acceptance gaps stay open. No commit or push was made.

Repeat using the commands in the root README. Keep configuration and tokens in the user directory; do not paste them into Taskdeck task environment fields. Starting `Run Server` and `Run App` manually leaves them managed until stopped, independent of this chat.

## Standard development tasks and Taskdeck-first guidance

2026-10-11: expanded the existing session to 14 explicitly named, manual tasks. The original Run Server and Run App remain running with the same process IDs throughout this configuration work.

| Group | Task labels |
| --- | --- |
| Runtime | Run Server; Run App |
| Rust build | Build Server; Build Server Release |
| Rust checks | Test Server; Check Server Format; Lint Server |
| Swift build | Build App; Build App Release; Build App Tests |
| Swift tests | Test App |
| Focused checks | Check Map Page; Check Live Models; Check Task Report |

The repository's existing `AGENTS.md` now requires Taskdeck as the preferred entry for standard commands, named-task control, serialized Cargo/Xcode operations sharing artifacts, and inspection of the terminal task status plus exit code. Direct commands are reserved for an unavailable Taskdeck or focused diagnostics absent from the configuration. README usage and the T15 scope in implementation-sequence.md describe the same entry points.

The reusable `scripts/xcode-task.sh` selects the host architecture and builds into a separate development DerivedData directory. It accepts only supported actions/configurations. Test App refuses to start an XCTest host when a main F1Companion process exists. A focused direct invocation verified the guard exits 1 with the explanatory message, before invoking xcodebuild; this diagnostic does not execute XCTest. UI acceptance remains a separate workflow.

Actual execution through Taskdeck returned exit code 0 for:

- Test Server (locked Rust test suite).
- Check Server Format.
- Lint Server (all-target Clippy with warnings denied).
- Build App Tests (TEST BUILD SUCCEEDED; test targets compiled without an App host).
- Check Map Page (five tests).
- Check Live Models (compatibility, freshness, RC filtering, Radio cancellation, stale-response/release checks).
- Check Task Report (data validation, eight task-data tests, board JavaScript syntax).

All 14 commands were accepted by `taskdeck update`. The standalone debug/release build labels and Test App are configured but were not all executed in this extension; runtime builds were verified in the preceding section. Neither the full XCTest suite nor native UI tests are claimed. Shell syntax and Git whitespace checks passed. A final Check Task Report run was performed after writing these deliverables and the task-board history.

## Release app launch

2026-10-11: the user asked for the running app to be Release. `Run App` now builds `-configuration Release` and executes `Build/Products/Release/F1Companion.app` against the real server on port 38701. Debug and test builds remain separate Taskdeck tasks and use a different DerivedData directory. Restarting only `Run App` replaces the previous Debug process; `Run Server` is left running.
