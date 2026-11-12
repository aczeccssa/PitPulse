# Repository Guidelines

## Project Structure & Module Organization

PitPulse (F1 Companion) is a self-hosted F1 timing system with two deliverables. The design lives in `F1-Companion-Architecture.md`.

- `server/` — single Rust process (Tokio/Axum/Reqwest/SQLite). Modules: `providers/` (Jolpica, OpenF1, `f1_live/`), `domain/`, `services/`, `storage/migrations/`, `scheduler.rs`, `api/`, `tests/`, `deploy/`.
- `PitPulse.xcworkspace` — Xcode entry point containing two independent projects and two shared packages.
- `macos/PitPulseDesktop.xcodeproj` — Swift 6 / SwiftUI Menu Bar + Notch app, WidgetKit extension and tests. Sources: `App/`, `Core/` (APIClient, Models, LiveStore, Cache, Notifications), `Features/`, `PitPulseWidgets/`, `Tests/`, `UITests/`, generated from `macos/project.yml`.
- `ios/PitPulseMobile.xcodeproj` — iOS app, Live Activity extension and tests, generated from `ios/project.yml`.
- `Packages/SharedData` — contracts, API/storage/live services, widget snapshot publishing. `Packages/SharedComponents` — shared SwiftUI components and image assets; depends on `SharedData`. Both app projects link both packages.
- Keep each provider behind its own adapter; never call third-party APIs from the macOS or iOS client.

## Build, Test, and Development Commands

**Prefer Taskdeck for routine development, builds, tests, lint, and runtime control.** `taskdeck.yaml` is the command source of truth for the `PitPulse` session. Before acting, inspect `taskdeck status --session PitPulse --json`; register the existing config on a new machine with `taskdeck register --session PitPulse`, and use `taskdeck update --session PitPulse` after changing it. `taskdeck init` is only for the first initialization and refuses to overwrite an existing file.

Start one named task with `taskdeck start --session PitPulse --task "<label>"`; inspect its status and logs until it exits, and verify its exit code. A start response or `running` state is not a passing build/check. For the development services, use targeted `restart` / `stop` for `Run Live Replay` or `Run App`; do not launch a second unmanaged instance.

| Task | Purpose |
| --- | --- |
| `Run Live Replay`, `Run App` | Run the live replay server workflow and the Release native App under Taskdeck |
| `Build App`, `Build App Release` | Swift debug/release build of the Desktop project, separate from the running App bundle |
| `Build App Tests` | Compile Desktop App and XCTest targets without starting a test host |
| `Build iOS`, `Test iOS` | Build or test the Mobile project for the iOS Simulator |
| `Connect Simulator Replay` | Point the simulator build at the live replay workflow |
| `Check Widget Publisher` | Run the `SharedData` widget snapshot publisher tests |
| `Check App Launcher` | Verify the built Release bundle and embedded WidgetKit extension |

All tasks are manual (`auto_start: false`). Always select a task explicitly: a start/restart of the entire session would also run builds and the App-host tests. Serialize Rust build/test/lint commands that share Cargo artifacts, and Xcode tasks that share their development DerivedData. `Test iOS` and desktop App-host tests must not overlap with a running App; coordinate with the user before stopping their App or running desktop-affecting tests. Prefer `Build App Tests` when desktop interaction is out of scope. UI acceptance schemes remain a separate, explicitly authorized workflow.

Use direct `cargo`, `xcodebuild`, `swift test`, or `node` only when Taskdeck is unavailable or a focused diagnostic is not represented by a task; explain the fallback. Keep standard task commands in YAML aligned with required repository gates. Tokens, config, SQLite and Xcode products stay outside Git. Build/test success does not replace real UI or upstream acceptance.

## Coding Style & Naming Conventions

- Rust: 2024 edition, `rustfmt` defaults (4 spaces), snake_case modules/functions, `CamelCase` types. Run `cargo fmt` and `cargo clippy` before committing.
- Swift: 4 spaces, `UpperCamelCase` types, `lowerCamelCase` members, one primary `App` lifecycle entry.
- JSON/API fields are `lowerCamelCase`; all timestamps are RFC 3339 UTC.

## Testing Guidelines

- Rust tests live beside modules and in `server/tests/`; name them `test_<behavior>` or `<unit>_<condition>_<expected>`.
- Cover patch/reducer merging, provider adapters, and cache/retry paths with recorded fixtures. Never assert on live network output in CI.
- macOS and iOS tests go in their project test targets; shared package tests go in `Packages/<Name>/Tests/` and run with `swift test --package-path Packages/<Name>`.

## Commit & Pull Request Guidelines

- Use Conventional Commits: `feat(server): add jolpica adapter`, `fix(macos): correct notch stale state`, `docs: update architecture notes`.
- PRs state motivation, scope, linked issues, and test evidence (commands run + observed results). Include screenshots for Menu Bar/Notch UI changes.
- Never commit tokens, `.env` files, SQLite data, or captured live-feed logs.

## Security & Configuration

- Secrets come from `F1_COMPANION_TOKEN` or Keychain; config lives outside the repo. Prefer HTTPS + Bearer auth or a Tailscale private network.
- Degrade gracefully: mark `stale`/`disconnected` instead of showing fabricated realtime data.

## Task Tracking & Docs Policy — Required Agent Workflow

- Task status lives in YouTrack project `PP` (`https://lestere-dev.youtrack.cloud`). After each commit, add an issue comment with the hash, branch, scope, verification commands and results, and anything still unverified. Keep an issue `In Progress` until its acceptance criteria are actually verified; never report a build or preview as full acceptance.
- `docs/` holds only documents the user explicitly authorized. Do not add acceptance records, research notes, reviews, screenshots, asset dumps or generated evidence there, and do not recreate the removed `docs/tasks` board.
- Without that authorization, write every such file under `temp/docs/` instead. `temp/` is git-ignored and never committed.
- Never put tokens, secrets, SQLite data, raw captured live-feed logs or machine-specific private paths into a report, an issue comment or an ignored file's path list.
