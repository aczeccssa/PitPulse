# Infrastructure Status

## Implemented

- Rust 2024 / Tokio / Axum service boundary.
- TOML plus environment configuration; secret token is never written to repository config.
- SQLite WAL schema for meetings, sessions, results, standings, and sync state.
- Blocking-task storage access and read-only REST endpoints for empty/cached data.
- Bearer-token middleware and health endpoint.
- Live snapshot shared with `tokio::sync::watch`; SSE emits the latest snapshot and keep-alives.
- Jolpica, OpenF1, and F1 Live adapter boundaries. F1 Live patch merging has isolated tests.
- systemd, environment, and optional Docker deployment assets.
- CI gates: rustfmt, Clippy, tests, release build.

## Deliberately Not Implemented Yet

- Real upstream calls: Phase 0 fixtures must first prove Jolpica Alpha, OpenF1 result payloads, and SignalR transport.
- macOS app: Phase 2. Only architectural directory boundaries exist.
- Production scheduler behavior, source reconciliation, and notification/revision rollout.

## Verification

```sh
cargo fmt --manifest-path server/Cargo.toml -- --check
cargo clippy --manifest-path server/Cargo.toml -- -D warnings
cargo test --manifest-path server/Cargo.toml
cargo build --release --manifest-path server/Cargo.toml
```
