# Repository Guidelines

## Project Structure & Module Organization

PitPulse (F1 Companion) is a self-hosted F1 timing system with two deliverables. The design lives in `F1-Companion-Architecture.md`.

- `server/` — single Rust process (Tokio/Axum/Reqwest/SQLite). Modules: `providers/` (Jolpica, OpenF1, `f1_live/`), `domain/`, `services/`, `storage/migrations/`, `scheduler.rs`, `api/`, `tests/`, `deploy/`.
- `macos/` — Swift 6 / SwiftUI Menu Bar + Notch app. `App/`, `Core/` (APIClient, Models, LiveStore, Cache, Notifications), `Features/` (MenuBar, Calendar, SessionResults, Standings, LiveIsland, Preferences), `Resources/`.
- Keep each provider behind its own adapter; never call third-party APIs from the macOS client.

## Build, Test, and Development Commands

- `cargo build --release --manifest-path server/Cargo.toml` — production server binary.
- `cargo run --manifest-path server/Cargo.toml` — run the server locally (config via env/TOML).
- `cargo test --manifest-path server/Cargo.toml` — unit and integration tests.
- `cargo fmt --manifest-path server/Cargo.toml -- --check` and `cargo clippy --manifest-path server/Cargo.toml -- -D warnings` — formatting and lint gates.
- `xcodebuild -project macos/F1Companion.xcodeproj -scheme F1Companion build` — build the macOS app.

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
