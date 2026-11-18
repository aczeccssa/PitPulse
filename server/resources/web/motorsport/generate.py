#!/usr/bin/env python3
"""Derive the dashboard's motorsport artwork from the app's bundled assets.

The macOS/iOS apps ship full-resolution artwork in
`Packages/SharedComponents/Sources/SharedComponents/Resources/PitPulseAssets.xcassets`.
The web shell embeds its own copies so the dashboard stays self-contained; they
are downscaled to the sizes the tables actually draw and stay transparent.
Run from the repository root:

    python3 server/resources/web/motorsport/generate.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
CATALOG = (
    ROOT
    / "Packages/SharedComponents/Sources/SharedComponents/Resources"
    / "PitPulseAssets.xcassets"
)
OUT = Path(__file__).resolve().parent

# 2026 Formula 1 grid: one logo per team, one helmet per driver.
TEAMS = [
    "alpine",
    "aston_martin",
    "audi",
    "cadillac",
    "ferrari",
    "haas",
    "mclaren",
    "mercedes",
    "rb",
    "red_bull",
    "williams",
]

HELMET_HEIGHT = 72
TEAM_SIZE = 128


def trimmed(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    box = image.getchannel("A").getbbox()
    return image.crop(box) if box else image


def fit(image: Image.Image, *, height: int | None = None, width: int | None = None) -> Image.Image:
    scale = (height / image.height) if height else (width / image.width)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.LANCZOS)


def save_team(source: Path, name: str) -> None:
    image = trimmed(source)
    if image.width > TEAM_SIZE:
        image = fit(image, width=TEAM_SIZE)
    image.save(OUT / name, optimize=True)
    print(f"{name} {image.width}x{image.height}")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for team in TEAMS:
        imageset = CATALOG / f"team-logo-{team}-2026.imageset"
        save_team(imageset / "image.png", f"team-{team}.png")
        # A few logos are drawn in near-black and disappear on the dark card;
        # the catalog carries an appearance variant for exactly those teams.
        dark = imageset / "image-dark.png"
        if dark.exists():
            save_team(dark, f"team-{team}-dark.png")

    # A white silhouette preserves the existing alpha mask on McLaren orange.
    mclaren = Image.open(OUT / "team-mclaren.png").convert("RGBA")
    contrast = Image.new("RGBA", mclaren.size, (255, 255, 255, 0))
    contrast.putalpha(mclaren.getchannel("A"))
    contrast.save(OUT / "team-mclaren-dark.png", optimize=True)

    for source in sorted(CATALOG.glob("helmet-*-2026.imageset/image.png")):
        slug = source.parent.name[len("helmet-") : -len("-2026.imageset")]
        image = fit(trimmed(source), height=HELMET_HEIGHT)
        image.save(OUT / f"helmet-{slug}.png", optimize=True)
        print(f"helmet-{slug}.png {image.width}x{image.height}")


if __name__ == "__main__":
    main()
