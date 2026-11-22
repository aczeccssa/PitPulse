#!/usr/bin/env python3
"""Collect original FIA reports into PitPulse's SQLite archive.

Requires Poppler's pdftotext on the server. Run with --help for selecting a
season/manifest. Unknown PDF layouts fail closed and retain existing records.
No requests are made to a third-party dashboard, and no repair costs or PU
penalties are inferred from usage counts.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import unicodedata
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

PROJECT = Path(__file__).resolve().parent.parent
DEFAULT_MANIFEST = PROJECT / "server/resources/engineering/fia-reports.json"
GZIP_PREFIX = b"\x00PULSEGZ\x01"
ELEMENTS = [("ice", "Internal Combustion Engine"), ("tc", "Turbo Charger"),
            ("ex", "Exhaust Set"), ("mgu-k", "Motor Generator Unit - Kinetic"),
            ("es", "Energy Store"), ("ce", "Power Unit Control Electronics"),
            ("anc", "Power Unit Ancillary Components")]
ELEMENT_NAMES = dict(ELEMENTS + [("mgu-h", "Motor Generator Unit - Heat")])

TEAMS = ["McLaren", "Mercedes", "Red Bull Racing", "Ferrari", "Williams",
         "Racing Bulls", "Aston Martin", "Haas", "Audi", "Alpine", "Cadillac"]


def normalize(text):
    return unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()


def team_name(text):
    compact = normalize(text).replace(" ", "")
    if "redbullracing" in compact or compact.startswith("rbr"):
        return "Red Bull Racing"
    for historical in ["AlphaTauri", "Alfa Romeo", "Sauber"]:
        if normalize(historical).replace(" ", "") in compact:
            return historical
    # Car descriptions include their engine supplier (e.g. Haas Ferrari).
    # Match the constructor prefix before considering any supplier name.
    for name in TEAMS:
        if compact.startswith(normalize(name).replace(" ", "")):
            return name
    if "racingbulls" in compact:
        return "Racing Bulls"
    if "astonmartin" in compact:
        return "Aston Martin"
    for name in TEAMS:
        if normalize(name).replace(" ", "") in compact:
            return name
    raise ValueError("Unrecognized team in FIA report")


def team_header(words):
    # FIA puts the constructor's name centered below the document heading.
    # Limiting the box prevents car/team names in prose from assigning a page.
    header = " ".join(w[3] for w in sorted(
        (w for w in words if 110 <= w[2] <= 140 and w[0] >= 240),
        key=lambda w: (round(w[2] / 4), w[0])))
    return team_name(header)


def source_url(url):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "www.fia.com" or not parsed.path.endswith(".pdf") or not (parsed.path.startswith("/system/files/") or parsed.path.startswith("/sites/default/files/")):
        raise ValueError("Report URLs must be original HTTPS FIA PDF documents")
    return url


def download(url):
    source_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (PitPulse FIA report collector)"})
    with urllib.request.urlopen(request, timeout=30) as response:
        source_url(response.url)
        data = response.read(25 * 1024 * 1024 + 1)
    if len(data) > 25 * 1024 * 1024 or not data.startswith(b"%PDF"):
        raise ValueError("FIA response was not a supported PDF")
    return data


def pdf_text(data, bbox=False):
    with tempfile.TemporaryDirectory(prefix="pitpulse-fia-") as folder:
        path = Path(folder) / "report.pdf"
        path.write_bytes(data)
        args = ["pdftotext", "-bbox-layout" if bbox else "-layout", str(path), "-"]
        result = subprocess.run(args, check=True, capture_output=True, timeout=30)
        return result.stdout.decode("utf-8")


def document_info(text, spec, digest):
    number = re.search(r"\bDocument\s+(\d+)", text)
    if not number or str(spec["season"]) not in text[:500]:
        raise ValueError("Missing document number or season mismatch")
    return {"url": source_url(spec["url"]), "number": int(number[1]),
            "kind": spec["kind"], "sha256": digest}


def parse_usage(text, spec, source):
    header = next((line for line in text.splitlines() if re.search(r"\bICE\s+TC\s+", line)), "")
    codes = [code.lower() for code in re.findall(r"\b(?:ICE|TC|MGU-H|MGU-K|ES|CE|EX|ANC)\b", header)]
    if "pu elements" not in text.lower() or not codes or "mgu-k" not in codes:
        raise ValueError("Unsupported PU usage report")
    rows = []
    for line in text.splitlines():
        match = re.match(r"^\s*(\d{1,2})\s{2,}(.+?)\s{2,}(.+?)\s{2,}(\d+(?:\s+\d+){" + str(len(codes) - 1) + r"})\s*$", line)
        if not match:
            continue
        number, car, driver, counts = match.groups()
        counts = [int(n) for n in counts.split()]
        if any(n > 30 for n in counts):
            raise ValueError("Unexpected PU count")
        team = team_name(car)
        engine = next((name for name in ["RB Ford", "Mercedes", "Ferrari", "Honda", "Renault", "Audi", "RBPT"] if name in car), None)
        if not engine:
            raise ValueError("Unknown engine manufacturer")
        rows.append({"driverNumber": int(number), "driverCode": normalize(driver.split()[-1])[:3].upper(),
                     "driverName": driver, "team": team, "engineManufacturer": engine,
                     "used": dict(zip(codes, counts)), "total": sum(counts),
                     "round": spec["round"], "sourceDocuments": [source]})
    # A truncated/scanned document must not silently replace the complete table.
    if not 20 <= len(rows) <= 30 or len({r["driverNumber"] for r in rows}) != len(rows):
        raise ValueError("Incomplete or duplicate PU usage rows")
    return rows


def parse_tech(xml, spec, source):
    ns = {"p": "http://www.w3.org/1999/xhtml"}
    pages = ET.fromstring(xml).findall(".//p:page", ns)
    result, seen = [], set()
    for page in pages:
        words = [(float(w.attrib["xMin"]), float(w.attrib["xMax"]),
                  (float(w.attrib["yMin"]) + float(w.attrib["yMax"])) / 2, w.text or "")
                 for w in page.findall(".//p:word", ns)]
        text = " ".join(w[3] for w in sorted(words, key=lambda w: (round(w[2] / 4), w[0])))
        if "Car Presentation" not in text:
            continue
        # Team header is above the table, so references to other cars in a
        # description cannot change ownership of the update.
        try:
            team = team_header(words)
        except ValueError:
            # The first PDF page is document metadata, not a team table.
            if not any(w[3].lower() in {"mclaren", "mercedes", "ferrari", "williams", "audi", "alpine", "cadillac", "aston", "bull", "haas"} for w in words if 75 <= w[2] <= 140):
                continue
            raise
        seen.add(team)
        if re.search(r"no updates?\b", text, re.I):
            continue
        # Row numbers are a separate left column. Column headers define the
        # component and primary-reason regions; never parse description words.
        component = [w for w in words if w[3].lower() == "component" and w[2] < 190]
        primary = [w for w in words if w[3].lower() == "primary" and w[2] < 190]
        geometric = [w for w in words if w[3].lower() == "geometric" and w[2] < 190]
        if not component or not primary or not geometric:
            raise ValueError(f"Unsupported car presentation table for {team}")
        cx, px, gx = component[0][0], primary[0][0], geometric[0][0]
        if not cx < px < gx:
            raise ValueError("Unsupported car presentation column order")
        indices = sorted([w for w in words if w[0] < cx and re.fullmatch(r"\d{1,2}", w[3]) and w[2] > component[0][2]], key=lambda w: w[2])
        if not indices:
            raise ValueError(f"No recognized update rows for {team}")
        if [int(w[3]) for w in indices] != list(range(1, len(indices) + 1)):
            raise ValueError("Unexpected update numbering")
        for index, row in enumerate(indices):
            lo = (indices[index - 1][2] + row[2]) / 2 if index else component[0][2] + 10
            hi = (row[2] + indices[index + 1][2]) / 2 if index + 1 < len(indices) else row[2] + 30
            def cell(left, right):
                selected = [w for w in words if left <= w[0] < right and lo < w[2] < hi]
                return " ".join(w[3] for w in sorted(selected, key=lambda w: (round(w[2] / 4), w[0])))
            comp = cell(row[1] + 1, (component[0][1] + px) / 2)
            reason = cell((component[0][1] + px) / 2, gx - (gx - px) / 4)
            parts = re.split(r"\s*[-–—]\s*", reason, maxsplit=1)
            if not comp or len(parts) != 2 or parts[0] not in ("Performance", "Circuit specific", "Reliability"):
                raise ValueError(f"Unrecognized component/reason in {team} row {index + 1}")
            result.append({"id": f"fia:{spec['season']}:{spec['round']}:{team}:{index+1}",
                           "team": team, "round": spec["round"], "country": spec["country"],
                           "component": comp, "type": parts[0], "reason": parts[1],
                           "major": False, "sourceDocuments": [source]})
    if len(seen) != spec.get("expectedTeams", 11):
        raise ValueError(f"Incomplete car presentation: {len(seen)} teams")
    return result


def encode(envelope):
    import gzip
    raw = envelope.encode()
    if len(raw) > 16 * 1024 * 1024:
        return envelope
    compressed = gzip.compress(raw, compresslevel=1)
    if len(GZIP_PREFIX) + len(compressed) < len(raw):
        return GZIP_PREFIX + compressed
    return envelope


def decode(value):
    import gzip
    raw = value.encode() if isinstance(value, str) else bytes(value)
    if raw.startswith(GZIP_PREFIX):
        return gzip.decompress(raw[len(GZIP_PREFIX):]).decode()
    return raw.decode()


def save(connection, key, data, meta):
    envelope = json.dumps({"data": data, "meta": meta}, ensure_ascii=False)
    connection.execute("INSERT INTO analysis_cache(cache_key,value_json,fetched_at) VALUES(?,?,?) "
                       "ON CONFLICT(cache_key) DO UPDATE SET value_json=excluded.value_json,fetched_at=excluded.fetched_at",
                       (key, encode(envelope), meta["fetchedAt"]))


def rebuild(connection, season, now):
    reports = [json.loads(decode(row[0])) for row in connection.execute(
        "SELECT value_json FROM analysis_cache WHERE cache_key LIKE ?", (f"pitpulse:fia:document:{season}:%",))]
    for kind, resource in [("tech", "tech-updates"), ("usage", "used-elements")]:
        selected = [r for r in reports if r["data"]["kind"] == kind]
        if not selected:
            continue
        selected.sort(key=lambda r: (r["data"]["round"], r["meta"].get("publishedAt") or ""))
        # Keep the latest successfully parsed document for each round.
        per_round = {r["data"]["round"]: r for r in selected}
        rows = ([row for report in per_round.values() for row in report["data"]["rows"]]
                if kind == "tech" else selected[-1]["data"]["rows"])
        expected = [row[0] for row in connection.execute(
            "SELECT round FROM meetings WHERE season=? AND round IS NOT NULL AND status!='cancelled' AND end_date < ? ORDER BY round",
            (season, now))]
        complete = kind == "tech" and set(expected).issubset(per_round)
        coverage = {"rounds": sorted(per_round), "expectedRounds": expected,
                    "complete": complete,
                    "asOfRound": selected[-1]["data"]["round"]}
        meta = {"source": "FIA · PitPulse collector", "fetchedAt": now,
                "publishedAt": selected[-1]["meta"]["publishedAt"], "stale": False,
                "unavailable": False, "coverage": coverage}
        save(connection, f"pitpulse:fia:{resource}:{season}", rows, meta)
        summary = {"total": len(rows) if kind == "tech" else sum(r["total"] for r in rows)}
        save(connection, f"pitpulse:fia:home-{'tech' if kind == 'tech' else 'pu'}:{season}", summary, meta)
        if kind == "usage":
            # Usage reports define columns, not sporting allocations. Until a
            # regulation is imported, display counts without invented limits.
            codes = list(rows[0]["used"]) if rows else []
            elements = [{"code": code, "name": ELEMENT_NAMES[code], "quota": None} for code in codes]
            save(connection, f"pitpulse:fia:elements:{season}", elements, {**meta, "allocationsAvailable": False})


def sync(connection, manifest, season):
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    failures = 0
    for spec in manifest:
        if spec["season"] != season:
            continue
        try:
            raw = download(spec["url"])
            text = pdf_text(raw)
            source = document_info(text, spec, hashlib.sha256(raw).hexdigest())
            if spec["kind"] == "usage":
                rows = parse_usage(text, spec, source)
            elif spec["kind"] == "tech":
                rows = parse_tech(pdf_text(raw, bbox=True), spec, source)
            else:
                raise ValueError("Unsupported report kind")
            with connection:
                save(connection, f"pitpulse:fia:document:{season}:{spec['round']}:{spec['kind']}",
                     {"kind": spec["kind"], "round": spec["round"], "rows": rows, "source": source},
                     {"source": "FIA", "fetchedAt": now, "publishedAt": spec["publishedAt"]})
                rebuild(connection, season, now)
            print(f"FIA {season} R{spec['round']} {spec['kind']}: {len(rows)} records imported", flush=True)
        except (ValueError, OSError, ET.ParseError, subprocess.SubprocessError) as error:
            failures += 1
            print(f"FIA {season} R{spec['round']} {spec['kind']}: retained prior archive ({type(error).__name__}: {error})", flush=True)
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, default=dt.datetime.now().year)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--database", type=Path)
    args = parser.parse_args()
    database = args.database or Path(os.environ.get("F1_COMPANION_DATABASE_PATH", Path.home() / "Library/Application Support/PitPulse/server/pitpulse.sqlite"))
    if not database.is_file():
        parser.error("Start PitPulse once to initialize the database, or pass --database")
    if not 1950 <= args.season <= 2100:
        parser.error("Invalid season")
    with sqlite3.connect(database, timeout=30) as connection:
        raise SystemExit(1 if sync(connection, json.loads(args.manifest.read_text()), args.season) else 0)


if __name__ == "__main__":
    main()
