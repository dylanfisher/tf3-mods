# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render the road-menu icons of square_one_way_roads: each two-way road's base icon with the
base game's one-way arrow on it.

The arrow is not drawn by hand. It is unmixed from the base pair town_new_small@2x.tga /
town_new_one_way_small@2x.tga (the one-way icon is the two-way icon plus a white arrow, so
alpha = (one_way - two_way) / (255 - two_way)), then laid on each source icon at the same offset
from the road tile's centre. All base road icons share one camera, so the arrow's perspective fits.

Sources come straight from the game's base/content/infrastructure/street.zip.
Outputs: mods/square_one_way_roads/content/infrastructure/street/square_one_way/<slug>@2x.tga,
referenced as `icon = "<slug>.tga"` (the game picks the @2x file). Format as the base icons:
240x150 px, uncompressed 32-bit BGRA TGA, bottom-left origin.

Usage: uv run tools/render_icon_square_one_way_roads.py [--png sheet.png]
"""

from __future__ import annotations

import argparse
import io
import struct
import sys
import zipfile
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hubconfig import MODS_DIR, _STEAM  # noqa: E402

STREET_ZIP = _STEAM / "steamapps/common/Transport Fever 3/base/content/infrastructure/street.zip"
OUT_DIR = MODS_DIR / "square_one_way_roads/content/infrastructure/street/square_one_way"

SOURCES = [
    "town/town_old_xsmall", "town/town_old_small", "town/town_old_medium", "town/town_old_large",
    "town/town_new_large",
    "country/country_old_small", "country/country_old_medium", "country/country_old_large",
    "country/country_new_small", "country/country_new_medium", "country/country_new_large",
]


def load(zf: zipfile.ZipFile, name: str) -> Image.Image:
    return Image.open(io.BytesIO(zf.read(f"street/{name}@2x.tga"))).convert("RGBA")


def tile_centre(img: Image.Image) -> tuple[float, float]:
    """Centroid of the solid road tile (ignores thin, half-transparent lamp posts)."""
    a = img.getchannel("A").load()
    sx = sy = n = 0
    for y in range(img.height):
        for x in range(img.width):
            if a[x, y] > 200:
                sx += x
                sy += y
                n += 1
    return sx / n, sy / n


def extract_arrow(zf: zipfile.ZipFile) -> tuple[Image.Image, tuple[float, float]]:
    """The base arrow as a white sprite with alpha, and its offset from the tile centre."""
    two, one = load(zf, "town/town_new_small"), load(zf, "town/town_new_one_way_small")
    p2, p1 = two.load(), one.load()
    arrow = Image.new("RGBA", two.size, (0, 0, 0, 0))
    pa = arrow.load()
    for y in range(two.height):
        for x in range(two.width):
            c2, c1 = p2[x, y], p1[x, y]
            if c1[3] < 250 or min(c1[:3]) < 120:
                continue  # the arrow is opaque and light
            k = [(c1[i] - c2[i]) / max(1, 255 - c2[i]) for i in range(3)]
            alpha = max(0.0, min(1.0, sum(k) / 3))
            if alpha > 0.15:
                pa[x, y] = (244, 244, 244, round(alpha * 255))
    box = arrow.getbbox()
    assert box and box[2] - box[0] < 120, f"arrow extraction picked up too much: {box}"
    sprite = arrow.crop(box)
    cx, cy = tile_centre(one)
    return sprite, (box[0] - cx, box[1] - cy)


def stamp(img: Image.Image, sprite: Image.Image, offset: tuple[float, float]) -> Image.Image:
    cx, cy = tile_centre(img)
    out = img.copy()
    out.alpha_composite(sprite, (round(cx + offset[0]), round(cy + offset[1])))
    return out


def write_tga(img: Image.Image, path: Path) -> None:
    """Uncompressed 32-bit BGRA, bottom-left origin, TGA 2.0 footer (as the base icons)."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, img.width, img.height, 32, 8)
    r, g, b, a = img.transpose(Image.Transpose.FLIP_TOP_BOTTOM).split()
    body = Image.merge("RGBA", (b, g, r, a)).tobytes()
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    path.write_bytes(header + body + footer)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--png", type=Path, help="also write a contact sheet (two-way above one-way)")
    args = ap.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(STREET_ZIP) as zf:
        sprite, offset = extract_arrow(zf)
        pairs = []
        for src in SOURCES:
            base = load(zf, src)
            icon = stamp(base, sprite, offset)
            out = OUT_DIR / f"one_way_{src.split('/')[1]}@2x.tga"
            write_tga(icon, out)
            print(f"wrote {out.relative_to(MODS_DIR.parent)}")
            pairs.append((base, icon))
    if args.png:
        w, h = 240, 150
        sheet = Image.new("RGBA", (w * len(pairs), h * 2), (60, 64, 70, 255))
        for i, (base, icon) in enumerate(pairs):
            sheet.alpha_composite(base, (i * w, 0))
            sheet.alpha_composite(icon, (i * w, h))
        sheet.save(args.png)
        print(f"wrote {args.png}")


if __name__ == "__main__":
    main()
