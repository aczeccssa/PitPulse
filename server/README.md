# PitPulse Server

Rust/Tokio/Axum single-process data service. This repository currently contains the Phase 1 infrastructure skeleton:

- Configuration loading from TOML + environment.
- SQLite schema, migrations, WAL, and blocking-task-backed storage.
- Versioned REST endpoints, Bearer token middleware, and health checks.
- Live snapshot state with `tokio::sync::watch` and initial SSE stream.
- Provider adapter boundaries for Jolpica, OpenF1, and F1 Live SignalR.
- systemd deployment example.

Upstream APIs are intentionally not called during this scaffold; Phase 0 recorded fixtures must define their normalization contracts first.

## Development

```sh
cargo fmt --manifest-path server/Cargo.toml -- --check
cargo clippy --manifest-path server/Cargo.toml -- -D warnings
cargo test --manifest-path server/Cargo.toml
cargo build --release --manifest-path server/Cargo.toml
```

## Local run

```sh
F1_COMPANION_DATABASE_PATH=/tmp/pitpulse.sqlite cargo run --manifest-path server/Cargo.toml
curl http://127.0.0.1:38701/api/v1/health
```

To require authentication:

```sh
F1_COMPANION_TOKEN=local-token F1_COMPANION_REQUIRE_TOKEN=true \
F1_COMPANION_DATABASE_PATH=/tmp/pitpulse.sqlite \
  cargo run --manifest-path server/Cargo.toml
```
