#!/usr/bin/env python3
"""Remove a season's archived rows from the PitPulse database.

Destructive by design: the product no longer carries 2021-2023, so their rows
are deleted rather than hidden. Dry-run unless --apply is passed.

    python3 scripts/purge-season.py --season 2021..2023
    python3 scripts/purge-season.py --season 2021..2023 --apply
"""
from __future__ import annotations

import argparse
import shutil
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_DB = Path.home() / "Library/Application Support/PitPulse/server/pitpulse.sqlite"


def seasons(text: str) -> list[int]:
    start, _, end = text.partition("..")
    first, last = int(start), int(end or start)
    if first > last:
        raise SystemExit("season range must ascend")
    return list(range(first, last + 1))


def counts(connection: sqlite3.Connection, year: int) -> dict[str, int]:
    prefix = f"{year}:"
    queries = {
        "session_results": ("SELECT count(*) FROM session_results WHERE session_id LIKE ?", f"{prefix}%"),
        "sessions": ("SELECT count(*) FROM sessions WHERE id LIKE ?", f"{prefix}%"),
        "meetings": ("SELECT count(*) FROM meetings WHERE season = ?", year),
        "driver_standings": ("SELECT count(*) FROM driver_standings WHERE season = ?", year),
        "constructor_standings": ("SELECT count(*) FROM constructor_standings WHERE season = ?", year),
        "calendar_snapshots": ("SELECT count(*) FROM calendar_snapshots WHERE season = ?", year),
        "provider_identity_cache": ("SELECT count(*) FROM provider_identity_cache WHERE season = ?", year),
        "analysis_cache": (
            "SELECT count(*) FROM analysis_cache WHERE cache_key LIKE ? OR cache_key LIKE ? OR cache_key LIKE ?",
            (f"%:{year}:%", f"%:{year}", f"identity-{year}"),
        ),
        "sync_state": (
            "SELECT count(*) FROM sync_state WHERE endpoint LIKE ? OR endpoint LIKE ?",
            (f"%-{year}", f"%-{year}-%"),
        ),
    }
    result = {}
    for name, (sql, argument) in queries.items():
        if isinstance(argument, tuple):
            result[name] = connection.execute(sql, argument).fetchone()[0]
        else:
            result[name] = connection.execute(sql, (argument,)).fetchone()[0]
    return result


def purge(connection: sqlite3.Connection, year: int) -> None:
    prefix = f"{year}:"
    connection.execute("DELETE FROM session_results WHERE session_id LIKE ?", (f"{prefix}%",))
    connection.execute("DELETE FROM sessions WHERE id LIKE ?", (f"{prefix}%",))
    connection.execute("DELETE FROM meetings WHERE season = ?", (year,))
    connection.execute("DELETE FROM driver_standings WHERE season = ?", (year,))
    connection.execute("DELETE FROM constructor_standings WHERE season = ?", (year,))
    connection.execute("DELETE FROM calendar_snapshots WHERE season = ?", (year,))
    connection.execute("DELETE FROM provider_identity_cache WHERE season = ?", (year,))
    connection.execute(
        "DELETE FROM analysis_cache WHERE cache_key LIKE ? OR cache_key LIKE ? OR cache_key LIKE ?",
        (f"%:{year}:%", f"%:{year}", f"identity-{year}"),
    )
    connection.execute(
        "DELETE FROM sync_state WHERE endpoint LIKE ? OR endpoint LIKE ?",
        (f"%-{year}", f"%-{year}-%"),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", required=True, help="year or inclusive range, e.g. 2021..2023")
    parser.add_argument("--database", type=Path, default=DEFAULT_DB)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    target = args.database.expanduser().resolve()
    if not target.is_file():
        raise SystemExit(f"database not found: {target}")
    years = seasons(args.season)
    with sqlite3.connect(target, timeout=30) as connection:
        total = {year: counts(connection, year) for year in years}
        for year, rows in total.items():
            print(year, rows)
        if not args.apply:
            print("dry run; pass --apply to delete")
            return 0
        backup = target.with_name(
            f"{target.name}.{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}.bak"
        )
        shutil.copyfile(target, backup)
        print(f"backup: {backup}")
        for year in years:
            purge(connection, year)
        connection.commit()
        remaining = {year: counts(connection, year) for year in years}
        for year, rows in remaining.items():
            print("remaining", year, rows)
        if any(any(rows.values()) for rows in remaining.values()):
            raise SystemExit("purge left rows behind")
    print("purged", ", ".join(str(year) for year in years))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
