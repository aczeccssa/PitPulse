#!/usr/bin/env python3
"""Build and run the real server with local configuration kept outside Git."""
import json
import os
from pathlib import Path
import subprocess


def main():
    project = Path(__file__).resolve().parent.parent
    local = Path.home() / "Library/Application Support/PitPulse"
    env = dict(os.environ)
    settings = local / "server/environment.json"
    if settings.exists():
        values = json.loads(settings.read_text())
        if not isinstance(values, dict) or not all(
            isinstance(key, str)
            and (key.startswith("F1_COMPANION_") or key == "F1_LIVE_ACCESS_TOKEN")
            and isinstance(value, str)
            for key, value in values.items()
        ):
            raise SystemExit("Local server environment must contain only string F1 configuration values")
        env.update(values)
    env.setdefault("F1_COMPANION_BIND", "127.0.0.1:38701")
    env.setdefault("F1_COMPANION_DATABASE_PATH", str(local / "server/pitpulse.sqlite"))
    token = local / "mapbox-public-token"
    if token.exists():
        env["F1_COMPANION_MAPBOX_PUBLIC_TOKEN"] = token.read_text().strip()
    print("Building the real PitPulse server…", flush=True)
    subprocess.run(
        ["cargo", "build", "--locked", "--manifest-path", "server/Cargo.toml"],
        cwd=project, env=env, check=True,
    )
    executable = project / "server/target/debug/pitpulse-server"
    os.chdir(project)
    print("Starting the real server; replay is disabled by this launch task.", flush=True)
    os.execve(executable, [str(executable)], env)


if __name__ == "__main__":
    main()
