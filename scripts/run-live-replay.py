#!/usr/bin/env python3
"""Run the recorded F1 + WEC Live replay server on its own port.

The replay timelines are produced by scripts/prepare-live-replay.py; this task
only builds and serves them so the normal server keeps its own port.
"""
import json
import os
from pathlib import Path
import subprocess

PROJECT = Path(__file__).resolve().parent.parent
LOCAL = Path.home() / "Library/Application Support/PitPulse"
SKIPPED_LOCAL_KEYS = {"F1_COMPANION_BIND", "F1_COMPANION_DATABASE_PATH"}
REPLAY_FILES = ("f1-sao-paulo-2026.json.gz", "wec-monza-2026.json.gz")


def main():
    env = dict(os.environ)
    settings = LOCAL / "server/environment.json"
    if settings.exists():
        values = json.loads(settings.read_text())
        if not isinstance(values, dict) or not all(
            isinstance(key, str)
            and (key.startswith("F1_COMPANION_") or key == "F1_LIVE_ACCESS_TOKEN")
            and isinstance(value, str)
            for key, value in values.items()
        ):
            raise SystemExit("Local server environment must contain only string F1 configuration values")
        # Local file supplies defaults only: explicit Taskdeck / shell env wins.
        # The replay server owns its bind address and never touches the live DB.
        for key, value in values.items():
            if key not in SKIPPED_LOCAL_KEYS:
                env.setdefault(key, value)
    env.setdefault("F1_COMPANION_BIND", "0.0.0.0:38702")
    replay_dir = Path(env.setdefault("F1_COMPANION_REPLAY_DIR", str(PROJECT / "server/target/replay-data")))
    missing = [name for name in REPLAY_FILES if not (replay_dir / name).is_file()]
    if missing:
        raise SystemExit(
            f"Missing replay data in {replay_dir}: {', '.join(missing)}; "
            "run python3 scripts/prepare-live-replay.py first"
        )
    print(f"Building the recorded Live replay server…", flush=True)
    subprocess.run(
        [
            "cargo",
            "build",
            "--locked",
            "--release",
            "--manifest-path",
            "server/Cargo.toml",
            "--example",
            "live_events_replay",
        ],
        cwd=PROJECT,
        env=env,
        check=True,
    )
    executable = PROJECT / "server/target/release/examples/live_events_replay"
    os.chdir(PROJECT)
    print(
        f"Starting recorded replay on {env['F1_COMPANION_BIND']} from {replay_dir}; "
        "both series loop independently.",
        flush=True,
    )
    os.execve(executable, [str(executable)], env)


if __name__ == "__main__":
    main()
