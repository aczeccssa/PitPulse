#!/usr/bin/env python3
"""Fetch and normalize the two recorded Live sessions used by the replay server.

The generated replay files are deliberately written below ``server/target/`` so
raw upstream payloads and derived timing data stay outside Git. Sources:

* F1 São Paulo 2026 race: the public OpenF1 historical API.
* FIA WEC 6 Hours of Monza 2026: the public Griiip endpoints used by the
  official WEC Live Timing page.

WEC only exposes the last five completed laps per car anonymously after the
session; the full final classification, race log and race flags are public.
The WEC replay therefore covers the real final five laps of each car, not the
entire six-hour race. This is recorded in docs/acceptance/live-replay.md.
"""

from __future__ import annotations

import argparse
import gzip
import http.client
import json
import re
import sys
import time
import urllib.error
import urllib.request
from bisect import bisect_right
from datetime import datetime, timezone
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
DEFAULT_DATA_DIR = PROJECT / "server/target/replay-data"
DEFAULT_CACHE_DIR = PROJECT / "server/target/replay-cache"
USER_AGENT = "PitPulse/0.1 (+https://github.com/)"

OPENF1 = "https://api.openf1.org/v1"
GRIIIP = "https://insights.griiip.com"
F1_SESSION_KEY = 11412  # 2026 São Paulo Grand Prix, Race
WEC_SESSION_ID = 18162  # 2026 6 Hours of Monza, Race
FRAME_SECONDS = 1.0

COUNTRY_CODES = {
    "BRA": "BR",
    "ITA": "IT",
    "GBR": "GB",
    "USA": "US",
    "FRA": "FR",
    "DEU": "DE",
    "ESP": "ES",
    "JPN": "JP",
    "AUS": "AU",
    "CAN": "CA",
    "MEX": "MX",
    "SGP": "SG",
    "NLD": "NL",
    "BEL": "BE",
    "AUT": "AT",
    "HUN": "HU",
    "AZE": "AZ",
    "QAT": "QA",
    "ARE": "AE",
    "SAU": "SA",
    "BHR": "BH",
    "CHN": "CN",
    "KOR": "KR",
    "MON": "MC",
}


def log(message: str) -> None:
    print(message, flush=True)


def fetch_json(url: str, cache: Path, *, refresh: bool = False, retries: int = 6) -> object:
    if cache.exists() and not refresh:
        with cache.open("rb") as handle:
            return json.load(handle)
    cache.parent.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = response.read()
            parsed = json.loads(payload)
            cache.write_bytes(payload)
            time.sleep(0.35)
            return parsed
        except (
            urllib.error.URLError,
            TimeoutError,
            json.JSONDecodeError,
            OSError,
            http.client.HTTPException,
        ) as error:
            last_error = error
            delay = min(12.0, 1.5 * (attempt + 1))
            log(f"  retry {attempt + 1}/{retries} for {url}: {error}")
            time.sleep(delay)
    raise RuntimeError(f"could not fetch {url}: {last_error}")


def parse_utc(value: str) -> float:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()


def format_lap(seconds: float | None) -> str | None:
    if seconds is None or seconds <= 0:
        return None
    minutes = int(seconds // 60)
    remainder = seconds - minutes * 60
    return f"{minutes}:{remainder:06.3f}" if minutes else f"{remainder:.3f}"


def format_gap(seconds: float) -> str:
    return f"+{max(0.0, seconds):.3f}"


def normalize_gap(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return format_gap(float(value))
    text = str(value).strip()
    if not text:
        return None
    match = re.match(r"^\+?(\d+)\s*laps?$", text, re.IGNORECASE)
    if match:
        laps = int(match.group(1))
        return "+1 Lap" if laps == 1 else f"+{laps} Laps"
    if text.upper() == "LEADER":
        return "LEADER"
    try:
        return format_gap(float(text))
    except ValueError:
        return text


def class_name(class_id: str | None) -> str | None:
    if not class_id:
        return None
    return {
        "HYPERCAR": "HYPERCAR",
        "LMP2": "LMP2",
        "LMGT3": "LMGT3",
    }.get(class_id.upper(), class_id)


def title_name(first: str | None, last: str | None, fallback: str | None) -> str | None:
    if first and last:
        return f"{first} {last.title()}"
    return fallback


# ---------------------------------------------------------------------------
# F1 São Paulo (OpenF1)
# ---------------------------------------------------------------------------


def prepare_f1(cache: Path, data: Path, *, refresh: bool, telemetry: bool) -> Path:
    log("Preparing F1 São Paulo 2026 replay (OpenF1)")
    sessions = fetch_json(
        f"{OPENF1}/sessions?session_key={F1_SESSION_KEY}",
        cache / "openf1/sessions.json",
        refresh=refresh,
    )
    if not sessions:
        raise RuntimeError("OpenF1 returned no session metadata")
    session = sessions[0]
    meeting_key = session["meeting_key"]
    meetings = fetch_json(
        f"{OPENF1}/meetings?meeting_key={meeting_key}",
        cache / "openf1/meetings.json",
        refresh=refresh,
    )
    meeting = meetings[0]
    drivers = fetch_json(
        f"{OPENF1}/drivers?session_key={F1_SESSION_KEY}",
        cache / "openf1/drivers.json",
        refresh=refresh,
    )
    position = fetch_json(
        f"{OPENF1}/position?session_key={F1_SESSION_KEY}",
        cache / "openf1/position.json",
        refresh=refresh,
    )
    intervals = fetch_json(
        f"{OPENF1}/intervals?session_key={F1_SESSION_KEY}",
        cache / "openf1/intervals.json",
        refresh=refresh,
    )
    laps = fetch_json(
        f"{OPENF1}/laps?session_key={F1_SESSION_KEY}",
        cache / "openf1/laps.json",
        refresh=refresh,
    )
    weather = fetch_json(
        f"{OPENF1}/weather?session_key={F1_SESSION_KEY}",
        cache / "openf1/weather.json",
        refresh=refresh,
    )
    race_control = fetch_json(
        f"{OPENF1}/race_control?session_key={F1_SESSION_KEY}",
        cache / "openf1/race_control.json",
        refresh=refresh,
    )
    stints = fetch_json(
        f"{OPENF1}/stints?session_key={F1_SESSION_KEY}",
        cache / "openf1/stints.json",
        refresh=refresh,
    )
    pit = fetch_json(
        f"{OPENF1}/pit?session_key={F1_SESSION_KEY}",
        cache / "openf1/pit.json",
        refresh=refresh,
    )
    results = fetch_json(
        f"{OPENF1}/session_result?session_key={F1_SESSION_KEY}",
        cache / "openf1/session_result.json",
        refresh=refresh,
    )

    driver_numbers = [str(item["driver_number"]) for item in sorted(drivers, key=lambda item: item["driver_number"])]
    car_data: dict[str, list[dict]] = {}
    if telemetry:
        dns = {str(item["driver_number"]) for item in results if item.get("dns")}
        for index, number in enumerate(driver_numbers, start=1):
            if number in dns:
                car_data[number] = []
                continue
            log(f"  telemetry {index}/{len(driver_numbers)}: car {number}")
            samples = fetch_json(
                f"{OPENF1}/car_data?session_key={F1_SESSION_KEY}&driver_number={number}",
                cache / f"openf1/car_data-{number}.json",
                refresh=refresh,
            )
            car_data[number] = sorted(samples, key=lambda item: item["date"])

    drivers_by_number = {str(item["driver_number"]): item for item in drivers}
    result_by_number = {str(item["driver_number"]): item for item in results}
    total_laps = max(
        (int(item.get("number_of_laps") or 0) for item in results),
        default=0,
    )

    def group_by_driver(rows: list[dict], key: str = "date") -> dict[str, list[dict]]:
        grouped: dict[str, list[dict]] = {}
        for row in rows:
            grouped.setdefault(str(row["driver_number"]), []).append(row)
        for values in grouped.values():
            values.sort(key=lambda item: item[key])
        return grouped

    positions = group_by_driver(position)
    interval_rows = group_by_driver(intervals)
    lap_rows = group_by_driver(laps, "date_start")
    pit_rows = group_by_driver(pit)

    stint_by_driver: dict[str, list[dict]] = {}
    for row in stints:
        stint_by_driver.setdefault(str(row["driver_number"]), []).append(row)
    for values in stint_by_driver.values():
        values.sort(key=lambda item: item["lap_start"])

    weather = sorted(weather, key=lambda item: item["date"])
    weather_times = [parse_utc(item["date"]) for item in weather]
    race_control = sorted(race_control, key=lambda item: item["date"])

    completed = [
        lap
        for driver_laps in lap_rows.values()
        for lap in driver_laps
        if lap.get("lap_duration") is not None
    ]
    if not completed:
        raise RuntimeError("OpenF1 returned no completed laps")
    race_start = min(parse_utc(lap["date_start"]) for lap in completed) - 5.0
    race_end = max(
        parse_utc(lap["date_start"]) + float(lap["lap_duration"])
        for lap in completed
    ) + 5.0

    lap_completions: list[tuple[float, str, dict]] = sorted(
        (
            parse_utc(lap["date_start"]) + float(lap["lap_duration"]),
            str(lap["driver_number"]),
            lap,
        )
        for lap in completed
    )

    best_sector: dict[str, list[float | None]] = {number: [None, None, None] for number in driver_numbers}
    global_best: list[float | None] = [None, None, None]
    completion_index = 0

    record_time = {number: [parse_utc(item["date"]) for item in values] for number, values in positions.items()}
    interval_time = {number: [parse_utc(item["date"]) for item in values] for number, values in interval_rows.items()}
    lap_start_time = {
        number: [parse_utc(item["date_start"]) for item in values]
        for number, values in lap_rows.items()
    }
    lap_end_time = {
        number: [
            parse_utc(item["date_start"]) + float(item["lap_duration"])
            if item.get("lap_duration") is not None
            else None
            for item in values
        ]
        for number, values in lap_rows.items()
    }
    telemetry_time = {
        number: [parse_utc(item["date"]) for item in values]
        for number, values in car_data.items()
    }

    def latest(rows: list[dict], times: list[float], timestamp: float) -> dict | None:
        index = bisect_right(times, timestamp) - 1
        return rows[index] if index >= 0 else None

    def current_lap(driver_number: str, timestamp: float) -> tuple[int, dict | None]:
        values = lap_rows.get(driver_number, [])
        if not values:
            return 0, None
        ends = lap_end_time[driver_number]
        completed_count = sum(1 for end in ends if end is not None and end <= timestamp)
        last_completed = None
        for index, end in enumerate(ends):
            if end is not None and end <= timestamp:
                last_completed = values[index]
        return completed_count, last_completed

    def last_activity(driver_number: str) -> float:
        times: list[float] = []
        if interval_time.get(driver_number):
            times.append(interval_time[driver_number][-1])
        if record_time.get(driver_number):
            times.append(record_time[driver_number][-1])
        if lap_rows.get(driver_number):
            end = lap_end_time[driver_number][-1]
            times.append(end if end is not None else lap_start_time[driver_number][-1])
        if telemetry_time.get(driver_number):
            times.append(telemetry_time[driver_number][-1])
        return max(times) if times else race_start

    last_seen = {number: last_activity(number) for number in driver_numbers}

    def track_status(timestamp: float) -> str:
        relevant = [
            item
            for item in race_control
            if parse_utc(item["date"]) <= timestamp
            and item.get("flag") in {"GREEN", "YELLOW", "DOUBLE YELLOW", "RED", "CHEQUERED", "CLEAR", "SC", "VSC"}
        ]
        if not relevant:
            return "All clear"
        flag = relevant[-1]["flag"]
        return {
            "GREEN": "All clear",
            "CLEAR": "All clear",
            "YELLOW": "Yellow flag",
            "DOUBLE YELLOW": "Yellow flag",
            "SC": "Safety car",
            "VSC": "Virtual safety car",
            "RED": "Red flag",
            "CHEQUERED": "Chequered",
        }.get(flag, "All clear")

    def weather_frame(timestamp: float) -> dict | None:
        item = latest(weather, weather_times, timestamp)
        if not item:
            return None
        return {
            "utc": item["date"],
            "airTemp": item.get("air_temperature"),
            "trackTemp": item.get("track_temperature"),
            "humidity": item.get("humidity"),
            "pressure": item.get("pressure"),
            "windSpeed": item.get("wind_speed"),
            "windDirection": item.get("wind_direction"),
            "rainfall": bool(item.get("rainfall")),
        }

    def race_control_frame(timestamp: float) -> list[dict]:
        messages: list[dict] = []
        for index, item in enumerate(race_control):
            if parse_utc(item["date"]) > timestamp:
                break
            driver_number = item.get("driver_number")
            messages.append(
                {
                    "id": str(index),
                    "utc": item["date"],
                    "lap": item.get("lap_number"),
                    "driverNumber": str(driver_number) if driver_number is not None else None,
                    "sector": item.get("sector"),
                    "scope": item.get("scope"),
                    "message": item.get("message"),
                    "category": item.get("category"),
                    "flag": item.get("flag"),
                    "Message": item.get("message"),
                    "Category": item.get("category"),
                    "Flag": item.get("flag"),
                    "Lap": item.get("lap_number"),
                    "RacingNumber": str(driver_number) if driver_number is not None else None,
                    "Utc": item["date"],
                    "Id": str(index),
                }
            )
        return messages[-20:][::-1]

    def driver_frame(driver_number: str, timestamp: float) -> dict:
        meta = drivers_by_number[driver_number]
        result = result_by_number.get(driver_number, {})
        row = latest(positions.get(driver_number, []), record_time.get(driver_number, []), timestamp)
        interval_row = latest(interval_rows.get(driver_number, []), interval_time.get(driver_number, []), timestamp)
        completed_count, last_completed = current_lap(driver_number, timestamp)
        best = None
        for lap in lap_rows.get(driver_number, []):
            duration = lap.get("lap_duration")
            if duration is not None and parse_utc(lap["date_start"]) + float(duration) <= timestamp:
                best = float(duration) if best is None else min(best, float(duration))
        sectors = None
        if last_completed is not None:
            sectors = []
            for sector in range(3):
                value = last_completed.get(f"duration_sector_{sector + 1}")
                segments = last_completed.get(f"segments_sector_{sector + 1}")
                numeric = float(value) if value is not None else None
                sectors.append(
                    {
                        "value": format_lap(numeric),
                        "personalFastest": numeric is not None and best_sector[driver_number][sector] is not None and numeric == best_sector[driver_number][sector],
                        "overallFastest": numeric is not None and global_best[sector] is not None and numeric == global_best[sector],
                        "segments": segments,
                    }
                )
        stint = None
        current_lap_number = completed_count + 1
        for candidate in stint_by_driver.get(driver_number, []):
            if candidate["lap_start"] <= current_lap_number:
                stint = candidate
            if candidate["lap_start"] <= current_lap_number and (
                candidate.get("lap_end") is None or candidate["lap_end"] >= current_lap_number
            ):
                stint = candidate
                break
        in_pit = False
        for entry in pit_rows.get(driver_number, []):
            moment = parse_utc(entry["date"])
            if moment <= timestamp and timestamp - moment <= 40:
                in_pit = True
                break
        sample = latest(car_data.get(driver_number, []), telemetry_time.get(driver_number, []), timestamp) if telemetry else None
        retired = False
        if result.get("dns"):
            retired = True
        elif result.get("dnf") or result.get("dsq"):
            retired = timestamp > last_seen[driver_number] + 90
        gap = normalize_gap(interval_row.get("gap_to_leader")) if interval_row else None
        position = int(row["position"]) if row and row.get("position") is not None else None
        if position == 1:
            gap = "LEADER"
        interval = normalize_gap(interval_row.get("interval")) if interval_row else None
        if position == 1:
            interval = "LEADER"
        payload = {
            "number": driver_number,
            "name": title_name(meta.get("first_name"), meta.get("last_name"), meta.get("full_name")),
            "team": meta.get("team_name"),
            "position": position,
            "gap": gap,
            "interval": interval,
            "lapCount": completed_count if completed_count else None,
            "lastLap": format_lap(float(last_completed["lap_duration"])) if last_completed and last_completed.get("lap_duration") else None,
            "bestLap": format_lap(best),
            "sectors": sectors,
            "inPit": in_pit,
            "retired": retired,
        }
        if stint:
            payload["tireCompound"] = stint.get("compound")
            payload["tireAgeLaps"] = int(stint.get("tyre_age_at_start") or 0) + max(
                1, current_lap_number - int(stint["lap_start"])
            )
        if sample:
            payload["telemetry"] = {
                "utc": sample["date"],
                "receivedAt": sample["date"],
                "rpm": sample.get("rpm"),
                "speed": sample.get("speed"),
                "gear": sample.get("n_gear"),
                "throttle": sample.get("throttle"),
                "brake": sample.get("brake"),
                "drs": sample.get("drs"),
            }
        return payload

    def frames():
        nonlocal completion_index
        timestamp = race_start
        while timestamp <= race_end:
            while completion_index < len(lap_completions) and lap_completions[completion_index][0] <= timestamp:
                _, driver_number, lap = lap_completions[completion_index]
                for sector in range(3):
                    value = lap.get(f"duration_sector_{sector + 1}")
                    if value is None:
                        continue
                    numeric = float(value)
                    if best_sector[driver_number][sector] is None or numeric < best_sector[driver_number][sector]:
                        best_sector[driver_number][sector] = numeric
                    if global_best[sector] is None or numeric < global_best[sector]:
                        global_best[sector] = numeric
                completion_index += 1
            finished = timestamp >= race_end - 2.0
            driver_frames = [
                driver_frame(number, timestamp)
                for number in driver_numbers
            ]
            driver_frames.sort(
                key=lambda item: (
                    item["position"] is None,
                    item["position"] if item["position"] is not None else 999,
                    int(item["number"]),
                )
            )
            leader_laps = max((item["lapCount"] or 0) for item in driver_frames) if driver_frames else 0
            snapshot = {
                "schemaVersion": 1,
                "stateVersion": 0,
                "series": "f1",
                "circuitKey": str(session.get("circuit_key") or meeting.get("circuit_key") or ""),
                "circuitName": meeting.get("circuit_short_name"),
                "sessionId": f"replay:f1:{F1_SESSION_KEY}",
                "sessionName": session.get("session_name") or "Race",
                "meetingName": meeting.get("meeting_name") or "São Paulo Grand Prix",
                "countryCode": COUNTRY_CODES.get((meeting.get("country_code") or "").upper(), meeting.get("country_code")),
                "sourceStatus": "connected",
                "sourceMode": "replay",
                "statusReason": "recorded_replay:openf1",
                "sessionType": session.get("session_type") or "Race",
                "sessionStatus": "finished" if finished else "started",
                "trackStatus": track_status(timestamp),
                "lapCount": leader_laps,
                "totalLaps": total_laps or None,
                "updatedAt": None,
                "lastTransportAt": None,
                "drivers": driver_frames,
                "raceControl": race_control_frame(timestamp),
                "positionStatus": "waiting",
                "elapsedSeconds": int(max(0.0, timestamp - race_start)),
                "isTimeBased": False,
                "weather": weather_frame(timestamp),
            }
            yield {"t": round(timestamp - race_start, 3), "snapshot": snapshot}
            timestamp += FRAME_SECONDS

    meta = {
        "series": "f1",
        "event": "2026 São Paulo Grand Prix · Race",
        "source": "OpenF1 (public historical API)",
        "sessionKey": F1_SESSION_KEY,
        "frameSeconds": FRAME_SECONDS,
        "windowStartUtc": datetime.fromtimestamp(race_start, tz=timezone.utc).isoformat(),
        "windowEndUtc": datetime.fromtimestamp(race_end, tz=timezone.utc).isoformat(),
        "driverCount": len(driver_numbers),
        "totalLaps": total_laps,
        "telemetry": telemetry,
        "generatedAt": datetime.now().astimezone().isoformat(),
    }
    output = data / "f1-sao-paulo-2026.json.gz"
    write_replay(output, meta, frames())
    return output


# ---------------------------------------------------------------------------
# FIA WEC Monza (Griiip public endpoints)
# ---------------------------------------------------------------------------


def prepare_wec(cache: Path, data: Path, *, refresh: bool) -> Path:
    log("Preparing WEC Monza 2026 replay (Griiip public endpoints)")
    bootstrap = fetch_json(
        f"{GRIIIP}/api/v2/public/live/session/{WEC_SESSION_ID}/bootstrap",
        cache / "wec/bootstrap.json",
        refresh=refresh,
    )
    results_payload = fetch_json(
        f"{GRIIIP}/meta/sessions/{WEC_SESSION_ID}/results",
        cache / "wec/results.json",
        refresh=refresh,
    )

    racelog_cache = cache / "wec/racelog.json"
    if racelog_cache.exists() and not refresh:
        racelog = json.loads(racelog_cache.read_text())
    else:
        items: list[dict] = []
        start_after: int | None = None
        seen: set[str] = set()
        while True:
            url = f"{GRIIIP}/live/racelog-items/{WEC_SESSION_ID}/paged"
            if start_after is not None:
                url += f"?startAfter={start_after}"
            page = fetch_json(
                url,
                cache / "wec/racelog-page.json",
                refresh=True,
            )
            page_items = page.get("items") or []
            if not page_items:
                break
            for item in page_items:
                item_id = str(item.get("raceLogItemId"))
                if item_id not in seen:
                    seen.add(item_id)
                    items.append(item)
            next_start = page.get("startAfter")
            if next_start is None or next_start == start_after:
                break
            start_after = int(next_start)
        racelog = sorted(items, key=lambda item: item.get("ts") or "")
        racelog_cache.parent.mkdir(parents=True, exist_ok=True)
        racelog_cache.write_text(json.dumps(racelog))

    participants = bootstrap.get("participants") or []
    if not participants:
        raise RuntimeError("WEC bootstrap returned no participants")
    participants_by_pid = {int(item["pid"]): item for item in participants if item.get("pid") is not None}
    ranks = {int(item["pid"]): item for item in bootstrap.get("ranks") or [] if item.get("pid") is not None}
    gaps = {int(item["pid"]): item for item in bootstrap.get("gaps") or [] if item.get("pid") is not None}
    best_laps = {int(item["pid"]): item for item in bootstrap.get("bestLaps") or [] if item.get("pid") is not None}
    statuses = {
        int(item["pid"]): item
        for item in bootstrap.get("runningStatuses") or []
        if item.get("pid") is not None
    }
    laps_by_pid: dict[int, list[dict]] = {}
    for lap in bootstrap.get("laps") or []:
        if lap.get("pid") is None or lap.get("lapTimeMillis") is None:
            continue
        laps_by_pid.setdefault(int(lap["pid"]), []).append(lap)
    for values in laps_by_pid.values():
        values.sort(key=lambda item: item["lapNumber"])

    race_flags = sorted(
        (item for item in bootstrap.get("raceFlags") or [] if item.get("ts")),
        key=lambda item: (item.get("elapsedTimeMillis") or 0, item.get("ts")),
    )
    chequered = sorted(
        (item for item in bootstrap.get("chequeredFlags") or [] if item.get("ts")),
        key=lambda item: item.get("ts"),
    )
    pit_ins: dict[int, list[float]] = {}
    for item in bootstrap.get("pitIns") or []:
        if item.get("pid") is None or not item.get("ts"):
            continue
        pit_ins.setdefault(int(item["pid"]), []).append(parse_utc(item["ts"]))
    for values in pit_ins.values():
        values.sort()

    car_laps: dict[int, list[tuple[float, float, dict]]] = {}
    for pid, values in laps_by_pid.items():
        records = []
        for lap in values:
            duration = float(lap["lapTimeMillis"]) / 1000.0
            end = parse_utc(lap["ts"])
            records.append((end - duration, end, lap))
        records.sort(key=lambda item: item[1])
        car_laps[pid] = records

    starts = [records[0][0] for records in car_laps.values() if records]
    ends = [records[-1][1] for records in car_laps.values() if records]
    if not starts or not ends:
        raise RuntimeError("WEC bootstrap returned no recent lap history")
    window_start = max(starts)
    window_end = max(ends) + 3.0

    final_position = {
        pid: int(rank["overallPosition"])
        for pid, rank in ranks.items()
        if rank.get("overallPosition") is not None
    }
    final_lap_number = {
        pid: int(records[-1][2]["lapNumber"])
        for pid, records in car_laps.items()
    }

    def current_driver_name(participant: dict) -> str | None:
        current = participant.get("currentDriverId")
        drivers = participant.get("drivers") or []
        selected = None
        if current is not None:
            for driver in drivers:
                if str(driver.get("externalDriverID")) == str(current) or str(driver.get("driverId")) == str(current):
                    selected = driver
                    break
        selected = selected or (drivers[0] if drivers else None)
        if selected:
            return selected.get("displayName") or title_name(
                selected.get("firstname"), selected.get("lastname"), None
            )
        return participant.get("displayName")

    def progress_at(pid: int, timestamp: float) -> tuple[float, float | None]:
        records = car_laps.get(pid, [])
        current = None
        completed = 0
        for start, end, lap in records:
            if end <= timestamp:
                completed = int(lap["lapNumber"])
                continue
            if start <= timestamp < end:
                current = (start, end, lap)
            break
        if current is None:
            if records and timestamp >= records[-1][1]:
                return float(final_lap_number.get(pid, completed)), None
            if records and timestamp < records[0][0]:
                return float(records[0][2]["lapNumber"] - 1), None
            return float(completed), None
        start, end, lap = current
        duration = max(0.001, end - start)
        fraction = min(1.0, max(0.0, (timestamp - start) / duration))
        return (int(lap["lapNumber"]) - 1) + fraction, duration

    def track_status(timestamp: float) -> str:
        active = [item for item in race_flags if parse_utc(item["ts"]) <= timestamp]
        if [item for item in chequered if parse_utc(item["ts"]) <= timestamp]:
            return "Chequered"
        if not active:
            return "Green"
        flag = (active[-1].get("flag") or "").upper()
        return {
            "GREEN": "Green",
            "YELLOW": "Yellow",
            "DOUBLEYELLOW": "Yellow",
            "DOUBLE YELLOW": "Yellow",
            "VIRTUALSAFETYCAR": "VSC",
            "SAFETYCAR": "SC",
            "FULLCOURSEYELLOW": "FCY",
            "CODE60": "FCY",
            "RED": "Red",
            "CHEQUERED": "Chequered",
        }.get(flag.replace(" ", ""), flag or "Green")

    def race_log_item(item: dict) -> dict:
        kind = item.get("type") or ""
        car = item.get("carNumber") or ""
        text = item.get("text") or {
            "RaceFlag": f"Flag: {item.get('flag') or ''}",
            "PitIn": f"Car {car} in pit",
            "PitOut": f"Car {car} pit out",
            "ParticipantRetired": f"Car {car} retired",
            "DriverSwap": f"Car {car} driver change",
            "FastestLap": f"Fastest lap car {car}",
            "Overtake": f"Car {car} overtake",
            "Battle": f"Car {car} battle",
            "SignificantTimeLoss": f"Car {car} significant time loss",
            "AttackMode": f"Car {car} attack mode",
            "WeatherUpdate": "Weather update",
        }.get(kind, kind)
        return {
            "id": str(item.get("raceLogItemId") or ""),
            "utc": item.get("ts"),
            "lap": item.get("lapNumber"),
            "driverNumber": str(car) if car else None,
            "sector": item.get("sectorNumber"),
            "scope": None,
            "message": text,
            "category": kind,
            "flag": item.get("flag"),
            "Message": text,
            "Category": kind,
            "Flag": item.get("flag"),
            "Lap": item.get("lapNumber"),
            "RacingNumber": str(car) if car else None,
            "Utc": item.get("ts"),
            "Id": str(item.get("raceLogItemId") or ""),
        }

    race_log_times = [parse_utc(item["ts"]) for item in racelog if item.get("ts")]

    def race_log_frame(timestamp: float) -> list[dict]:
        limit = bisect_right(race_log_times, timestamp)
        return [race_log_item(item) for item in racelog[:limit][-20:]][::-1]

    def final_gap(pid: int, *, ahead: bool) -> str | None:
        gap = gaps.get(pid)
        if not gap:
            return None
        laps = int(gap.get("gapToAheadLaps" if ahead else "gapToFirstLaps") or 0)
        if laps > 0:
            return "+1 Lap" if laps == 1 else f"+{laps} Laps"
        millis = gap.get("gapToAheadMillis" if ahead else "gapToFirstMillis")
        if millis is None:
            return None
        return format_gap(float(millis) / 1000.0)

    def driver_frame(pid: int, participant: dict, timestamp: float) -> dict:
        progress, _ = progress_at(pid, timestamp)
        completed = int(progress)
        records = car_laps.get(pid, [])
        last_completed = None
        for start, end, lap in records:
            if end <= timestamp:
                last_completed = lap
        status = (statuses.get(pid) or {}).get("status") or "Running"
        retired = not status.lower().startswith("running")
        in_pit = any(0 <= timestamp - moment <= 60 for moment in pit_ins.get(pid, []))
        return {
            "number": participant.get("carNumber") or "",
            "name": current_driver_name(participant),
            "team": participant.get("teamName") or participant.get("displayName"),
            "position": None,
            "gap": None,
            "interval": None,
            "lapCount": completed if completed else None,
            "lastLap": format_lap(float(last_completed["lapTimeMillis"]) / 1000.0)
            if last_completed
            else None,
            "bestLap": format_lap(
                float(best_laps[pid]["lapTimeMillis"]) / 1000.0
                if pid in best_laps and best_laps[pid].get("lapTimeMillis")
                else None
            ),
            "inPit": in_pit,
            "retired": retired,
            "classId": participant.get("classId"),
            "className": class_name(participant.get("classId")),
            "manufacturer": participant.get("manufacturer"),
            "_pid": pid,
            "_progress": progress,
        }

    def frames():
        timestamp = window_start
        while timestamp <= window_end:
            finished = timestamp >= window_end - 3.0
            driver_frames = [
                driver_frame(pid, participant, timestamp)
                for pid, participant in participants_by_pid.items()
            ]
            if finished:
                driver_frames.sort(
                    key=lambda item: (
                        final_position.get(item["_pid"], 999),
                        item["number"],
                    )
                )
            else:
                driver_frames.sort(
                    key=lambda item: (
                        -item["_progress"],
                        final_position.get(item["_pid"], 999),
                        item["number"],
                    )
                )
            leader = driver_frames[0] if driver_frames else None
            leader_progress = leader["_progress"] if leader else 0.0
            leader_duration = None
            if leader:
                _, leader_duration = progress_at(leader["_pid"], timestamp)
            leader_duration = leader_duration or 90.0
            previous = None
            for index, item in enumerate(driver_frames):
                item["position"] = index + 1
                if index == 0:
                    item["gap"] = "LEADER"
                    item["interval"] = "LEADER"
                elif finished:
                    item["gap"] = final_gap(item["_pid"], ahead=False)
                    item["interval"] = final_gap(item["_pid"], ahead=True)
                else:
                    laps_behind = int(leader_progress) - int(item["_progress"])
                    if laps_behind >= 1:
                        item["gap"] = "+1 Lap" if laps_behind == 1 else f"+{laps_behind} Laps"
                    else:
                        item["gap"] = format_gap((leader_progress - item["_progress"]) * leader_duration)
                    if previous is not None:
                        ahead_laps = int(previous["_progress"]) - int(item["_progress"])
                        if ahead_laps >= 1:
                            item["interval"] = "+1 Lap" if ahead_laps == 1 else f"+{ahead_laps} Laps"
                        else:
                            item["interval"] = format_gap(
                                (previous["_progress"] - item["_progress"]) * leader_duration
                            )
                previous = item
            class_counters: dict[str, int] = {}
            for item in driver_frames:
                class_id = item.get("classId") or ""
                class_counters[class_id] = class_counters.get(class_id, 0) + 1
                item["classPosition"] = class_counters[class_id]
            for item in driver_frames:
                item.pop("_pid", None)
                item.pop("_progress", None)
            leader_laps = max((item["lapCount"] or 0) for item in driver_frames) if driver_frames else 0
            snapshot = {
                "schemaVersion": 1,
                "stateVersion": 0,
                "series": "wec",
                "circuitKey": (
                    f"wec:{bootstrap.get('sessionInfo', {}).get('trackId')}:"
                    f"{bootstrap.get('trackDetails', {}).get('trackConfigId')}"
                ),
                "circuitName": bootstrap.get("sessionInfo", {}).get("trackName"),
                "sessionId": f"replay:wec:{WEC_SESSION_ID}",
                "sessionName": bootstrap.get("sessionInfo", {}).get("sessionName") or "Race",
                "meetingName": bootstrap.get("sessionInfo", {}).get("eventName"),
                "countryCode": "IT",
                "sourceStatus": "connected",
                "sourceMode": "replay",
                "statusReason": "recorded_replay:griiip",
                "sessionType": bootstrap.get("sessionInfo", {}).get("sessionType") or "Race",
                "sessionStatus": "finished" if finished else "started",
                "trackStatus": track_status(timestamp),
                "lapCount": leader_laps,
                "totalLaps": None,
                "updatedAt": None,
                "lastTransportAt": None,
                "drivers": driver_frames,
                "raceControl": race_log_frame(timestamp),
                "positionStatus": None,
                "elapsedSeconds": int(parse_utc(bootstrap["sessionClock"]["startTime"]) * -1 + timestamp),
                "isTimeBased": True,
                "timeRemainingSeconds": 0,
            }
            yield {"t": round(timestamp - window_start, 3), "snapshot": snapshot}
            timestamp += FRAME_SECONDS

    meta = {
        "series": "wec",
        "event": "2026 FIA WEC 6 Hours of Monza · Race (final five laps)",
        "source": "Griiip public Live Timing bootstrap/results/race log",
        "sessionId": WEC_SESSION_ID,
        "frameSeconds": FRAME_SECONDS,
        "windowStartUtc": datetime.fromtimestamp(window_start).astimezone().isoformat(),
        "windowEndUtc": datetime.fromtimestamp(window_end).astimezone().isoformat(),
        "driverCount": len(participants_by_pid),
        "bestLapMillis": results_payload.get("bestLapTime"),
        "raceDurationMillis": results_payload.get("raceDurationMiilliseconds"),
        "lapHistory": "last five completed laps per car (public anonymous limit)",
        "generatedAt": datetime.now().astimezone().isoformat(),
    }
    output = data / "wec-monza-2026.json.gz"
    write_replay(output, meta, frames())
    return output


def write_replay(output: Path, meta: dict, frames) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with gzip.open(output, "wt", encoding="utf-8", compresslevel=6) as handle:
        handle.write('{"meta":')
        json.dump(meta, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write(',"frames":[')
        for frame in frames:
            if count:
                handle.write(",")
            json.dump(frame, handle, ensure_ascii=False, separators=(",", ":"))
            count += 1
        handle.write("]}")
    log(f"Wrote {output} ({count} frames, {output.stat().st_size / 1024 / 1024:.1f} MiB)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE_DIR)
    parser.add_argument("--refresh", action="store_true", help="ignore cached upstream responses")
    parser.add_argument("--skip-telemetry", action="store_true", help="do not download OpenF1 car data")
    args = parser.parse_args()
    prepare_f1(args.cache_dir, args.data_dir, refresh=args.refresh, telemetry=not args.skip_telemetry)
    prepare_wec(args.cache_dir, args.data_dir, refresh=args.refresh)
    log("Replay data ready.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
