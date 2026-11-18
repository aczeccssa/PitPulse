#!/usr/bin/env python3
"""Collect per-season F1 artwork for the dashboard and record its provenance.

Every file is stored as ``<season>/<kind>/<id>.png`` so the web shell, the
server and the Apple apps can address the same artwork with one identifier.
The manifest this script writes is the single source of truth for what exists,
where it came from and whether the artwork really belongs to the requested
season.

Run from the repository root:

    python3 server/resources/motorsport/collect.py --refresh-roster
    python3 server/resources/motorsport/collect.py --season 2026 --kind driver-photo
    python3 server/resources/motorsport/collect.py --check

Sources are the official Formula 1 media endpoints. Nothing is fetched from a
third party at request time: this script is the only network step, and it runs
offline against ``roster.json`` once that file is present.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from io import BytesIO
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
CATALOG = (
    REPO
    / "Packages/SharedComponents/Sources/SharedComponents/Resources"
    / "PitPulseAssets.xcassets"
)

ROSTER = HERE / "roster.json"
MANIFEST = HERE / "manifest.json"

CDN = "https://media.formula1.com/image/upload"
F1_SITE = "https://www.formula1.com"
FLAG_CDN = "https://flagcdn.com/w80"
COUNTRY_SOURCE = REPO / "server/src/domain/country.rs"
FLAG_DIR = REPO / "server/resources/web/motorsport"

SEASONS = (2021, 2022, 2023, 2024, 2025, 2026)
KINDS = ("driver-photo", "helmet", "car-side", "team-logo")

# Official CDN artwork is season-scoped from 2024 on. Earlier seasons answer
# 404 on every season-scoped path, so they stay an explicit gap instead of
# being filled with another season's portrait.
FIRST_SEASON_WITH_ARTWORK = 2024

# Stable per-driver media codes used by the official CDN: the first three
# letters of the given name, the first three of the family name and a two-digit
# disambiguator. The code does not change between seasons.
DRIVER_CODES = {
    "albon": "alealb01",
    "alonso": "feralo01",
    "antonelli": "andant01",
    "arvid_lindblad": "arvlin01",
    "bearman": "olibea01",
    "bortoleto": "gabbor01",
    "bottas": "valbot01",
    "colapinto": "fracol01",
    "de_vries": "nycdev01",
    "doohan": "jacdoo01",
    "gasly": "piegas01",
    "giovinazzi": "antgio01",
    "hadjar": "isahad01",
    "hamilton": "lewham01",
    "hulkenberg": "nichul01",
    "kevin_magnussen": "kevmag01",
    "kubica": "robkub01",
    "latifi": "niclat01",
    "lawson": "lialaw01",
    "leclerc": "chalec01",
    "mazepin": "nikmaz01",
    "max_verstappen": "maxver01",
    "mick_schumacher": "micsch01",
    "norris": "lannor01",
    "ocon": "estoco01",
    "perez": "serper01",
    "piastri": "oscpia01",
    "rafael_camara": "rafcam01",
    "raikkonen": "kimrai01",
    "ricciardo": "danric01",
    "russell": "georus01",
    "ryo_hirakawa": "ryohir01",
    "sainz": "carsai01",
    "sargeant": "logsar01",
    "stroll": "lanstr01",
    "tsunoda": "yuktsu01",
    "vettel": "sebvet01",
    "zhou": "guazho01",
}

# Constructor id (Jolpica) -> official CDN folder name.
TEAM_SLUGS = {
    "mercedes": "mercedes",
    "red_bull": "redbullracing",
    "ferrari": "ferrari",
    "mclaren": "mclaren",
    "alpine": "alpine",
    "williams": "williams",
    "aston_martin": "astonmartin",
    "haas": "haas",
    "alphatauri": "alphatauri",
    "alfa": "alfaromeo",
    "sauber": "kicksauber",
    "audi": "audi",
    "cadillac": "cadillac",
}

# Logos drawn in near-black need a white cut for the dark theme.
DARK_LOGO_TEAMS = {"aston_martin", "audi", "cadillac", "mercedes"}

DRIVER_PHOTO_SIZE = 320
CAR_WIDTH = 478
LOGO_SIZE = 128
HELMET_HEIGHT = 72

USER_AGENT = "PitPulse/1.0 (+self-hosted dashboard artwork collector)"


# --------------------------------------------------------------------------
# network


def request(url: str, *, tries: int = 3) -> bytes:
    last: Exception | None = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=45) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code in (404, 410):
                raise
            last = error
        except Exception as error:  # transport, timeout, dns
            last = error
        time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed: {last}")


def fetch_json(url: str) -> dict:
    return json.loads(request(url).decode())


def season_calendar(season: int) -> dict:
    return fetch_json(f"https://api.jolpi.ca/ergast/f1/{season}.json?limit=100")


def ergast_page(season: int, offset: int) -> dict:
    url = (
        f"https://api.jolpi.ca/ergast/f1/{season}/results.json"
        f"?limit=100&offset={offset}"
    )
    return fetch_json(url)


# --------------------------------------------------------------------------
# roster


def build_roster(seasons) -> dict:
    """Resolve every driver-season and constructor-season from Jolpica."""
    out = {}
    for season in seasons:
        drivers: dict[str, dict] = {}
        constructors: dict[str, int] = {}
        offset = 0
        total = None
        while total is None or offset < total:
            page = ergast_page(season, offset)
            meta = page["MRData"]
            total = int(meta["total"])
            for race in meta["RaceTable"]["Races"]:
                for result in race["Results"]:
                    driver = result["Driver"]
                    constructor = result["Constructor"]["constructorId"]
                    constructors[constructor] = constructors.get(constructor, 0) + 1
                    entry = drivers.setdefault(
                        driver["driverId"],
                        {
                            "name": f"{driver['givenName']} {driver['familyName']}",
                            "code": driver.get("code"),
                            "constructors": {},
                        },
                    )
                    entry["constructors"][constructor] = (
                        entry["constructors"].get(constructor, 0) + 1
                    )
            offset += 100
            time.sleep(0.2)
        for entry in drivers.values():
            entry["constructors"] = [
                name
                for name, _ in sorted(
                    entry["constructors"].items(), key=lambda kv: -kv[1]
                )
            ]
        calendar = season_calendar(season)["MRData"]["RaceTable"]["Races"]
        countries = sorted({race["Circuit"]["Location"]["country"] for race in calendar})
        out[str(season)] = {
            "drivers": drivers,
            "constructors": sorted(constructors),
            "countries": countries,
            "rounds": len(calendar),
        }
        print(
            f"roster {season}: {len(drivers)} drivers, "
            f"{len(constructors)} constructors, {len(countries)} countries",
            flush=True,
        )
    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": "https://api.jolpi.ca/ergast/f1/{season}/results.json",
        "seasons": out,
    }


def load_roster(refresh: bool) -> dict:
    if refresh or not ROSTER.exists():
        roster = build_roster(SEASONS)
        ROSTER.write_text(json.dumps(roster, indent=1) + "\n")
        return roster
    return json.loads(ROSTER.read_text())


# --------------------------------------------------------------------------
# country codes


def country_table() -> dict[str, str]:
    """Read the alias table the server itself uses.

    Parsing the Rust table keeps the collector and the API from drifting: a
    venue the server cannot code is a venue the dashboard cannot flag.
    """
    source = COUNTRY_SOURCE.read_text()
    block = source[source.index("const COUNTRIES"):source.index("pub const ALPHA2_CODES")]
    table = dict(re.findall(r'\("([^"]+)", "([A-Z]{2})"\)', block))
    if len(table) < 20:
        raise SystemExit(f"could not read the country table from {COUNTRY_SOURCE}")
    return table


def country_code(table: dict[str, str], value: str) -> str | None:
    normalized = (value or "").strip().lower()
    if not normalized:
        return None
    if normalized in table:
        return table[normalized]
    compact = re.sub(r"[ \-_]", "", normalized)
    for alias, code in table.items():
        if alias.replace(" ", "") == compact:
            return code
    return None


def required_flags(roster: dict) -> tuple[dict[str, set[int]], list[dict]]:
    """Every country the six calendars visit, and the seasons that visit it."""
    table = country_table()
    codes: dict[str, set[int]] = {}
    unmapped: list[dict] = []
    for season in SEASONS:
        entry = roster["seasons"][str(season)]
        for country in entry.get("countries", []):
            code = country_code(table, country)
            if not code:
                unmapped.append({"season": season, "country": country})
                continue
            codes.setdefault(code, set()).add(season)
    return codes, unmapped


def collect_flags(codes: dict[str, set[int]]) -> None:
    for code in sorted(codes):
        path = FLAG_DIR / f"flag-{code.lower()}.png"
        if path.exists():
            continue
        raw = request(f"{FLAG_CDN}/{code.lower()}.png")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        print(f"flag {code} {path.stat().st_size}B", flush=True)


# --------------------------------------------------------------------------
# sources


def team_slugs(season: int, constructor: str) -> list[str]:
    if constructor == "rb":
        return ["racingbulls", "rb"] if season >= 2026 else ["rb", "racingbulls"]
    slug = TEAM_SLUGS.get(constructor)
    return [slug] if slug else []


def portrait_url(season: int, slug: str, code: str) -> str:
    return (
        f"{CDN}/c_fill,g_north,w_{DRIVER_PHOTO_SIZE},h_{DRIVER_PHOTO_SIZE}"
        f"/q_auto/v1740000001/common/f1/{season}/{slug}/{code}"
        f"/{season}{slug}{code}right.webp"
    )


def car_url(season: int, slug: str) -> str:
    return (
        f"{CDN}/c_fill,w_{CAR_WIDTH}/q_auto/v1740000001"
        f"/common/f1/{season}/{slug}/{season}{slug}carright.webp"
    )


def logo_url(season: int, slug: str) -> str:
    return f"{CDN}/common/f1/{season}/{slug}/{season}{slug}logo.svg"


def first_available(urls) -> tuple[bytes, str] | None:
    for url in urls:
        try:
            return request(url), url
        except (urllib.error.HTTPError, RuntimeError):
            continue
    return None


# --------------------------------------------------------------------------
# image processing


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def save_png(image: Image.Image, path: Path, *, quantize: bool = False) -> tuple[int, int]:
    """Write a PNG, optionally to an 8-bit palette.

    Photographic artwork is four times smaller as a 255-colour palette with a
    per-entry alpha channel, and the difference is invisible at the sizes the
    dashboard draws. Flat artwork keeps full colour.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    if quantize:
        image = image.quantize(colors=255, method=Image.FASTOCTREE)
    image.save(path, format="PNG", optimize=True)
    return image.size


def trim(image: Image.Image) -> Image.Image:
    box = image.getchannel("A").getbbox()
    return image.crop(box) if box else image


def fit_height(image: Image.Image, height: int) -> Image.Image:
    scale = height / image.height
    size = (max(1, round(image.width * scale)), height)
    return image.resize(size, Image.LANCZOS)


def fit_width(image: Image.Image, width: int) -> Image.Image:
    if image.width <= width:
        return image
    scale = width / image.width
    size = (width, max(1, round(image.height * scale)))
    return image.resize(size, Image.LANCZOS)


def white_cut(image: Image.Image) -> Image.Image:
    """Keep the alpha mask, drop every brand colour."""
    cut = Image.new("RGBA", image.size, (255, 255, 255, 255))
    cut.putalpha(image.getchannel("A"))
    return cut


def fit_box(image: Image.Image, size: int) -> Image.Image:
    """Scale so neither side exceeds ``size``."""
    scale = min(1.0, size / max(image.width, image.height))
    if scale == 1.0:
        return image
    return image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.LANCZOS,
    )


FULL_RECT = re.compile(
    r'<rect[^>]*width="([\d.]+)"[^>]*height="([\d.]+)"[^>]*fill="(#[0-9A-Fa-f]{3,8})"[^>]*/?>'
)


def badge_fill(svg: bytes) -> tuple[bytes, tuple[int, int, int] | None]:
    """Split a badge-style logo into its mark and its background colour.

    The 2024 CDN logos paint a full-canvas colour rectangle behind a white
    mark. The dashboard wants the mark on transparency, so the rectangle is
    removed and its colour is reused for the mark itself.
    """
    text = svg.decode("utf-8", "replace")
    viewbox = re.search(r'viewBox="0 0 ([\d.]+) ([\d.]+)"', text)
    if not viewbox:
        return svg, None
    width, height = viewbox.group(1), viewbox.group(2)
    for match in FULL_RECT.finditer(text):
        if match.group(1) != width or match.group(2) != height:
            continue
        fill = match.group(3)
        if len(fill) == 4:  # #abc
            fill = "#" + "".join(channel * 2 for channel in fill[1:])
        rgb = tuple(int(fill[index : index + 2], 16) for index in (1, 3, 5))
        return (text[: match.start()] + text[match.end() :]).encode(), rgb
    return svg, None


def recolor(image: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    """Paint an alpha mask in one brand colour, darkening very light ones."""
    red, green, blue = rgb
    luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
    if luminance > 0.72:
        scale = 0.55 / luminance
        red, green, blue = (min(255, round(c * scale)) for c in rgb)
    painted = Image.new("RGBA", image.size, (red, green, blue, 255))
    painted.putalpha(image.getchannel("A"))
    return painted


def rasterize_svg(svg: bytes, size: int) -> Image.Image:
    """Render an official logo SVG with ImageMagick."""
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "logo.svg"
        target = Path(tmp) / "logo.png"
        source.write_bytes(svg)
        subprocess.run(
            [
                "magick",
                "-background",
                "none",
                "-density",
                "600",
                str(source),
                "-resize",
                f"{size}x{size}",
                str(target),
            ],
            check=True,
            capture_output=True,
        )
        return Image.open(target).convert("RGBA")


def read_image(raw: bytes) -> Image.Image:
    return Image.open(BytesIO(raw)).convert("RGBA")


# --------------------------------------------------------------------------
# collection


class Collector:
    def __init__(self, roster: dict, *, force: bool):
        self.roster = roster["seasons"]
        self.force = force

    def target(self, kind: str, asset_id: str, season: int) -> Path:
        return HERE / str(season) / kind / f"{asset_id}.png"

    def skip(self, kind: str, asset_id: str, season: int) -> bool:
        return self.target(kind, asset_id, season).exists() and not self.force

    # -- driver photos ----------------------------------------------------

    def collect_driver_photos(self, season: int) -> None:
        drivers = self.roster[str(season)]["drivers"]
        for driver_id, driver in drivers.items():
            if self.skip("driver-photo", driver_id, season):
                continue
            code = DRIVER_CODES.get(driver_id)
            if not code or season < FIRST_SEASON_WITH_ARTWORK:
                continue
            urls = [
                portrait_url(season, slug, code)
                for constructor in driver["constructors"]
                for slug in team_slugs(season, constructor)
            ]
            found = first_available(urls)
            if not found:
                print(f"driver-photo {season} {driver_id} unavailable", flush=True)
                continue
            raw, used = found
            path = self.target("driver-photo", driver_id, season)
            size = save_png(read_image(raw), path, quantize=True)
            print(f"driver-photo {season} {driver_id} {size[0]}x{size[1]}", flush=True)

    # -- car side views ---------------------------------------------------

    def collect_car_sides(self, season: int) -> None:
        for constructor in self.roster[str(season)]["constructors"]:
            if self.skip("car-side", constructor, season):
                continue
            if season < FIRST_SEASON_WITH_ARTWORK:
                continue
            urls = [car_url(season, slug) for slug in team_slugs(season, constructor)]
            found = first_available(urls)
            if not found:
                print(f"car-side {season} {constructor} unavailable", flush=True)
                continue
            raw, _ = found
            path = self.target("car-side", constructor, season)
            size = save_png(fit_width(trim(read_image(raw)), CAR_WIDTH), path, quantize=True)
            print(f"car-side {season} {constructor} {size[0]}x{size[1]}", flush=True)

    # -- team logos -------------------------------------------------------

    def collect_team_logos(self, season: int) -> None:
        for constructor in self.roster[str(season)]["constructors"]:
            if self.skip("team-logo", constructor, season):
                continue
            if season < FIRST_SEASON_WITH_ARTWORK:
                continue
            urls = [logo_url(season, slug) for slug in team_slugs(season, constructor)]
            found = first_available(urls)
            if not found:
                print(f"team-logo {season} {constructor} unavailable", flush=True)
                continue
            raw, _ = found
            svg, badge = badge_fill(raw)
            mark = trim(rasterize_svg(svg, LOGO_SIZE * 2))
            if badge:
                mark = recolor(mark, badge)
            color = fit_box(mark, LOGO_SIZE)
            path = self.target("team-logo", constructor, season)
            size = save_png(color, path)
            cut = white_cut(color)
            save_png(cut, path.with_name(f"{constructor}-contrast.png"))
            if constructor in DARK_LOGO_TEAMS:
                save_png(cut, path.with_name(f"{constructor}-dark.png"))
            print(f"team-logo {season} {constructor} {size[0]}x{size[1]}", flush=True)

    # -- helmets ----------------------------------------------------------

    def collect_helmets(self, season: int) -> None:
        for driver_id in self.roster[str(season)]["drivers"]:
            if self.skip("helmet", driver_id, season):
                continue
            source = CATALOG / f"helmet-{driver_id}-{season}.imageset" / "image.png"
            if not source.exists():
                continue
            image = fit_height(trim(Image.open(source).convert("RGBA")), HELMET_HEIGHT)
            path = self.target("helmet", driver_id, season)
            size = save_png(image, path, quantize=True)
            print(f"helmet {season} {driver_id} {size[0]}x{size[1]}", flush=True)


# --------------------------------------------------------------------------
# manifest


def gap_reason(kind: str, season: int) -> str:
    if season < FIRST_SEASON_WITH_ARTWORK:
        return (
            "official CDN has no season-scoped artwork before "
            f"{FIRST_SEASON_WITH_ARTWORK}; every probed path returns 404"
        )
    if kind == "helmet":
        return (
            "no public season-scoped helmet artwork; only the 2026 app "
            "catalog carries helmets"
        )
    return "no official artwork answered for this entry"


def provenance_for(asset_id: str, kind: str, season: int) -> dict:
    page = {
        "driver-photo": f"{F1_SITE}/en/drivers",
        "car-side": f"{F1_SITE}/en/teams",
        "team-logo": f"{F1_SITE}/en/teams",
        "helmet": "https://turn1visuals.com/f1-2026-assets/ (app catalog import)",
    }[kind]
    return {
        "sourcePageUrl": page,
        "license": "restricted",
        "rightsStatus": "restricted",
        "downloadStatus": "downloaded",
        "applicability": {
            "requestedSeason": season,
            "designSeason": season,
            "status": "seasonExact",
        },
    }


def scan_entries(roster: dict) -> tuple[list[dict], list[dict]]:
    """Describe what is on disk, and what the roster expects but is missing."""
    collected_at = datetime.now(timezone.utc).isoformat(timespec="seconds")
    entries: list[dict] = []
    present: set[tuple[str, str, int]] = set()
    for season in SEASONS:
        season_dir = HERE / str(season)
        if not season_dir.is_dir():
            continue
        for kind in KINDS:
            kind_dir = season_dir / kind
            if not kind_dir.is_dir():
                continue
            for path in sorted(kind_dir.glob("*.png")):
                asset_id = path.stem
                base_id = asset_id.removesuffix("-contrast").removesuffix("-dark")
                image = Image.open(path)
                entry = {
                    "kind": kind,
                    "id": asset_id,
                    "season": season,
                    "file": str(path.relative_to(HERE)),
                    "bytes": path.stat().st_size,
                    "sha256": sha256(path),
                    "width": image.width,
                    "height": image.height,
                    "collectedAt": collected_at,
                    **provenance_for(base_id, kind, season),
                }
                if base_id != asset_id:
                    entry["variant"] = asset_id[len(base_id) + 1 :]
                    entry["baseId"] = base_id
                entries.append(entry)
                present.add((kind, base_id, season))

    gaps: list[dict] = []
    for season in SEASONS:
        season_roster = roster["seasons"][str(season)]
        expected = [
            ("driver-photo", driver_id)
            for driver_id in season_roster["drivers"]
        ] + [
            ("helmet", driver_id) for driver_id in season_roster["drivers"]
        ] + [
            ("car-side", constructor)
            for constructor in season_roster["constructors"]
        ] + [
            ("team-logo", constructor)
            for constructor in season_roster["constructors"]
        ]
        for kind, asset_id in expected:
            if (kind, asset_id, season) in present:
                continue
            gaps.append(
                {
                    "kind": kind,
                    "id": asset_id,
                    "season": season,
                    "status": "missing",
                    "reason": gap_reason(kind, season),
                }
            )
    return entries, gaps


def scan_flags(roster: dict) -> tuple[list[dict], dict]:
    """Record the flag set and prove it covers every calendar country."""
    codes, unmapped = required_flags(roster)
    flags: list[dict] = []
    missing: list[dict] = []
    for code in sorted(codes):
        path = FLAG_DIR / f"flag-{code.lower()}.png"
        if not path.exists():
            missing.append(
                {
                    "code": code,
                    "seasons": sorted(codes[code]),
                    "reason": "no flag file for a country the calendars visit",
                }
            )
            continue
        image = Image.open(path)
        flags.append(
            {
                "code": code,
                "file": str(path.relative_to(REPO)),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
                "width": image.width,
                "height": image.height,
                "seasons": sorted(codes[code]),
                "sourcePageUrl": f"https://flagcdn.com/w80/{code.lower()}.png",
                "license": "public-domain",
                "rightsStatus": "approved",
            }
        )
    coverage = {
        "required": len(codes),
        "present": len(flags),
        "missing": missing,
        "unmappedCountries": unmapped,
    }
    return flags, coverage


def write_manifest(roster: dict) -> None:
    entries, gaps = scan_entries(roster)
    flags, flag_coverage = scan_flags(roster)
    entries.sort(key=lambda e: (e["season"], e["kind"], e["id"]))
    gaps.sort(key=lambda e: (e["season"], e["kind"], e["id"]))
    coverage: dict[str, dict[str, int]] = {}
    for entry in entries:
        if entry.get("variant"):
            continue
        bucket = coverage.setdefault(str(entry["season"]), {})
        bucket[entry["kind"]] = bucket.get(entry["kind"], 0) + 1
    manifest = {
        "schemaVersion": 2,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "identifier": "{kind}/{id}/{season} -> {season}/{kind}/{id}.png",
        "kinds": list(KINDS),
        "seasons": list(SEASONS),
        "sources": [
            {
                "name": "formula1-media",
                "baseUrl": CDN,
                "scope": "season-scoped artwork from 2024 on",
                "rightsStatus": "restricted",
            },
            {
                "name": "pitpulse-app-catalog",
                "path": str(CATALOG.relative_to(REPO)),
                "scope": "2026 helmets",
                "rightsStatus": "restricted",
            },
        ],
        "policy": {
            "runtimeThirdPartyAssetFetchAllowed": False,
            "crossSeasonSubstitutionAllowed": False,
            "publication": "restricted artwork stays private to the self-hosted instance",
        },
        "assets": entries,
        "gaps": gaps,
        "coverage": coverage,
        "flags": flags,
        "flagCoverage": flag_coverage,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"manifest: {len(entries)} assets, {len(gaps)} gaps", flush=True)
    print(
        f"flags: {flag_coverage['present']}/{flag_coverage['required']} countries, "
        f"{len(flag_coverage['unmappedCountries'])} unmapped",
        flush=True,
    )
    for season in sorted(coverage, key=int):
        summary = ", ".join(
            f"{kind}={count}" for kind, count in sorted(coverage[season].items())
        )
        print(f"  {season}: {summary}", flush=True)


# --------------------------------------------------------------------------
# verification


def check() -> int:
    if not MANIFEST.exists():
        print("manifest.json is missing; run the collector first", file=sys.stderr)
        return 1
    manifest = json.loads(MANIFEST.read_text())
    problems: list[str] = []
    seen: set[tuple[str, str, int, str]] = set()
    on_disk = {
        str(path.relative_to(HERE))
        for path in HERE.glob("*/*/*.png")
    }
    for entry in manifest["assets"]:
        key = (entry["kind"], entry["id"], entry["season"], entry.get("variant", ""))
        if key in seen:
            problems.append(f"duplicate asset {key}")
        seen.add(key)
        path = HERE / entry["file"]
        if not path.exists():
            problems.append(f"missing file for {key}: {entry['file']}")
            continue
        on_disk.discard(entry["file"])
        if sha256(path) != entry["sha256"]:
            problems.append(f"hash mismatch for {key}")
        if entry["kind"] not in KINDS:
            problems.append(f"unknown kind in {key}")
        applicability = entry.get("applicability") or {}
        if applicability.get("status") != "seasonExact":
            problems.append(f"asset {key} is not season-exact")
    for leftover in sorted(on_disk):
        problems.append(f"file not recorded in manifest: {leftover}")
    present = {
        (entry["kind"], entry["id"], entry["season"])
        for entry in manifest["assets"]
    }
    for gap in manifest["gaps"]:
        key = (gap["kind"], gap["id"], gap["season"])
        if key in present:
            problems.append(f"gap and asset overlap for {key}")
    flag_coverage = manifest.get("flagCoverage") or {}
    for item in flag_coverage.get("missing") or []:
        problems.append(f"missing flag for {item['code']} (seasons {item['seasons']})")
    for item in flag_coverage.get("unmappedCountries") or []:
        problems.append(
            f"country without an alpha-2 code: {item['country']} ({item['season']})"
        )
    recorded = {flag["file"] for flag in manifest.get("flags") or []}
    for path in sorted(FLAG_DIR.glob("flag-*.png")):
        rel = str(path.relative_to(REPO))
        if rel not in recorded:
            problems.append(f"flag not recorded in manifest: {rel}")
    for flag in manifest.get("flags") or []:
        path = REPO / flag["file"]
        if not path.exists():
            problems.append(f"missing flag file {flag['file']}")
        elif sha256(path) != flag["sha256"]:
            problems.append(f"flag hash mismatch for {flag['file']}")

    if problems:
        for problem in problems:
            print(f"FAIL {problem}")
        return 1
    print(
        f"OK {len(manifest['assets'])} assets, {len(manifest['gaps'])} documented gaps, "
        f"{flag_coverage.get('present')}/{flag_coverage.get('required')} flags"
    )
    return 0


# --------------------------------------------------------------------------
# entry point


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--season", type=int, action="append", choices=SEASONS)
    parser.add_argument("--kind", choices=KINDS, action="append")
    parser.add_argument("--refresh-roster", action="store_true")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if args.check:
        return check()

    roster = load_roster(args.refresh_roster)
    codes, unmapped = required_flags(roster)
    collect_flags(codes)
    for item in unmapped:
        print(
            f"warning: {item['country']} ({item['season']}) has no alpha-2 code "
            "in server/src/domain/country.rs",
            file=sys.stderr,
        )
    collector = Collector(roster, force=args.force)

    seasons = args.season or list(SEASONS)
    kinds = args.kind or list(KINDS)
    for season in seasons:
        if "driver-photo" in kinds:
            collector.collect_driver_photos(season)
        if "car-side" in kinds:
            collector.collect_car_sides(season)
        if "team-logo" in kinds:
            collector.collect_team_logos(season)
        if "helmet" in kinds:
            collector.collect_helmets(season)

    write_manifest(roster)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
