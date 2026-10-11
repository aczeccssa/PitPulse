# Repository Guidelines

## Project Structure & Module Organization

PitPulse (F1 Companion) is a self-hosted F1 timing system with two deliverables. The design lives in `F1-Companion-Architecture.md`.

- `server/` — single Rust process (Tokio/Axum/Reqwest/SQLite). Modules: `providers/` (Jolpica, OpenF1, `f1_live/`), `domain/`, `services/`, `storage/migrations/`, `scheduler.rs`, `api/`, `tests/`, `deploy/`.
- `macos/` — Swift 6 / SwiftUI Menu Bar + Notch app. `App/`, `Core/` (APIClient, Models, LiveStore, Cache, Notifications), `Features/` (MenuBar, Calendar, SessionResults, Standings, LiveIsland, Preferences), `Resources/`.
- Keep each provider behind its own adapter; never call third-party APIs from the macOS client.

## Build, Test, and Development Commands

**Prefer Taskdeck for routine development, builds, tests, lint, and runtime control.** `taskdeck.yaml` is the command source of truth for the `PitPulse` session. Before acting, inspect `taskdeck status --session PitPulse --json`; register the existing config on a new machine with `taskdeck register --session PitPulse`, and use `taskdeck update --session PitPulse` after changing it. `taskdeck init` is only for the first initialization and refuses to overwrite an existing file.

Start one named task with `taskdeck start --session PitPulse --task "<label>"`; inspect its status and logs until it exits, and verify its exit code. A start response or `running` state is not a passing build/check. For the development services, use targeted `restart` / `stop` for `Run Server` or `Run App`; do not launch a second unmanaged instance.

| Task | Purpose |
| --- | --- |
| `Run Server`, `Run App` | Build then run the real local server and the Release native App under Taskdeck |
| `Build Server`, `Build Server Release` | Locked Rust debug/release build |
| `Test Server` | Locked Rust unit/integration tests with fixtures |
| `Check Server Format`, `Lint Server` | rustfmt check and strict Clippy across all targets |
| `Build App`, `Build App Release` | Swift debug/release build, separate from the running App bundle |
| `Build App Tests` | Compile App and XCTest targets without starting a test host |
| `Test App` | Run the unit XCTest scheme; launches a native App test host |
| `Check Map Page`, `Check Live Models` | Map JavaScript checks and production Swift CLI model/store checks |
| `Check Task Report` | Validate task JSON, run task-data tests, and check board JavaScript syntax |

All tasks are manual (`auto_start: false`). Always select a task explicitly: a start/restart of the entire session would also run builds and the App-host tests. Serialize Rust build/test/lint tasks that share Cargo artifacts, and Xcode tasks that share their development DerivedData. `Test App` refuses to run while F1Companion is running; coordinate with the user before stopping their App or running desktop-affecting tests. Prefer `Build App Tests` when desktop interaction is out of scope. UI acceptance schemes remain a separate, explicitly authorized workflow.

Use direct `cargo`, `xcodebuild`, or `node` only when Taskdeck is unavailable or a focused diagnostic is not represented by a task; explain the fallback. Keep standard task commands in YAML aligned with required repository gates. Tokens, config, SQLite and Xcode products stay outside Git. Build/test success does not replace real UI or upstream acceptance.

## Coding Style & Naming Conventions

- Rust: 2024 edition, `rustfmt` defaults (4 spaces), snake_case modules/functions, `CamelCase` types. Run `cargo fmt` and `cargo clippy` before committing.
- Swift: 4 spaces, `UpperCamelCase` types, `lowerCamelCase` members, one primary `App` lifecycle entry.
- JSON/API fields are `lowerCamelCase`; all timestamps are RFC 3339 UTC.

## Testing Guidelines

- Rust tests live beside modules and in `server/tests/`; name them `test_<behavior>` or `<unit>_<condition>_<expected>`.
- Cover patch/reducer merging, provider adapters, and cache/retry paths with recorded fixtures. Never assert on live network output in CI.
- macOS tests go in the Xcode test target; use `xcodebuild test`.

## Commit & Pull Request Guidelines

- Use Conventional Commits: `feat(server): add jolpica adapter`, `fix(macos): correct notch stale state`, `docs: update architecture notes`.
- PRs state motivation, scope, linked issues, and test evidence (commands run + observed results). Include screenshots for Menu Bar/Notch UI changes.
- Never commit tokens, `.env` files, SQLite data, or captured live-feed logs.

## Security & Configuration

- Secrets come from `F1_COMPANION_TOKEN` or Keychain; config lives outside the repo. Prefer HTTPS + Bearer auth or a Tailscale private network.
- Degrade gracefully: mark `stale`/`disconnected` instead of showing fabricated realtime data.

## Task Status Report — Required Agent Workflow

- The task status source of truth is `docs/tasks/tasks.json`. The read-only static board is `docs/tasks/index.html`; it reads the JSON directly. Do not hardcode task cards, counts, progress, or current statuses in HTML/JavaScript, and do not create a second state store.
- **Every task start, substantive progress update, blocker, review, acceptance, or completion MUST update the corresponding JSON task in the same change.** Maintain `status`, `summary`, `nextAction`, `acceptanceCriteria[].done`, real `deliverables`/`evidence`, `blockers`, task `updatedAt`, and top-level `updatedAt`. Append a chronological `history` entry; never rewrite previous evidence/history.
- Allowed states are `pending`, `inProgress`, `inReview`, `done`, and `blocked`. Use RFC 3339 UTC timestamps ending in `Z`; the board displays them in `project.timezone`. Mark `done` only when all acceptance criteria passed, supporting evidence is present, and unresolved blockers are empty. Partial research, a passing build, or a downloaded candidate is not full acceptance.
- Preserve stable task IDs and unrelated task updates. When adding tasks or changing scope/dependencies, also update milestone membership and relevant definitions in `implementation-sequence.md`. The Markdown plan defines scope/order; **current progress belongs only in JSON**, not a duplicated Markdown status table.
- Never put tokens, secrets, SQLite data, raw captured live-feed logs, or machine-specific private paths into the report. Recorded document paths are repository-relative and must exist. Asset licensing/download/bundle readiness must remain distinct; missing T03 assets must not block V1 by default.
- After updating task data, run `node docs/tasks/validate.mjs` and `node --test docs/tasks/tests/task-data.test.mjs`. For board UI changes also run `node --check docs/tasks/board.js` and verify the page via local HTTP, including filters and error states. See `docs/tasks/README.md` for the data contract and preview command.
