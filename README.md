# PitPulse — F1 Companion

Self-hosted F1 companion consisting of a Rust API/data service and a native macOS Menu Bar + Notch app.

- Architecture: `F1-Companion-Architecture.md`
- Task status board: [`docs/tasks/index.html`](docs/tasks/index.html) · [JSON data](docs/tasks/tasks.json) · [preview/update guide](docs/tasks/README.md)
- Implementation plan: [`implementation-sequence.md`](implementation-sequence.md)
- Independent helmet / team-logo collection task: [`docs/tasks/T03-motorsport-assets.md`](docs/tasks/T03-motorsport-assets.md)
- Server: `server/`
- macOS: `macos/`

## Current scope

The repository currently contains the Phase 1 Rust infrastructure foundation. The macOS app is still Phase 2; no placeholder UI has been generated.

See `server/README.md` for build, test, run, and deployment guidance.

## Local development with Taskdeck

The `PitPulse` session contains `Run Server` and `Run App`. Both tasks build the current workspace before running and stay attached to Taskdeck, so its stop/restart controls own the actual processes.

```sh
# taskdeck init --session PitPulse creates and registers the initial config.
# Once taskdeck.yaml exists, use register on a new machine or update after edits.
taskdeck register --session PitPulse
taskdeck start --session PitPulse --task "Run Server"
taskdeck start --session PitPulse --task "Run App"
taskdeck status --session PitPulse
taskdeck restart --session PitPulse --task "Run Server"
taskdeck restart --session PitPulse --task "Run App"
taskdeck stop --session PitPulse
```

`Run Server` uses `scripts/run-server.py` and the real F1 provider. Local configuration is read from `~/Library/Application Support/PitPulse/server/environment.json` when present (string `F1_COMPANION_*` / `F1_LIVE_ACCESS_TOKEN` values only); Mapbox's public token is read from `~/Library/Application Support/PitPulse/mapbox-public-token`. Keep these local files private and outside Git. The default database also lives in that user directory.

`Run App` uses `scripts/run-app.sh`, builds the Release app into `~/Library/Caches/PitPulse/Xcode`, and connects to `http://127.0.0.1:38701` without replay arguments. Starting the App does not require the server to be ready; the existing retry path reconnects. Tasks start manually (`auto_start: false`). If the upstream has ended or stopped updating, the App continues to show its real stale/disconnected state.

Taskdeck also provides `Build Server`, `Build Server Release`, `Test Server`, `Check Server Format`, `Lint Server`, `Build App`, `Build App Release`, `Build App Tests`, `Test App`, `Check Map Page`, `Check Live Models`, and `Check Task Report`. Use `taskdeck start --session PitPulse --task "<label>"`, then check the final status/exit code. Build and test tasks are manual; always name the task so a session-wide start does not also launch tests.

App build/test tasks use a separate development DerivedData directory. `Test App` starts an XCTest host and refuses to run while a main F1Companion process exists; coordinate stopping the App before running it. `Build App Tests` compiles tests without a host. Run Cargo tasks sequentially, and serialize Xcode development tasks. Routine agent work should follow the Taskdeck-first rules in `AGENTS.md`.
