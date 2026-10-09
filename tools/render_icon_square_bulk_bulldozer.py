# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render the construction-menu icons of square_bulk_bulldozer ("Bulk Bulldozer").

A side-view bulldozer inside the dashed red brush circle.

Outputs (mods/square_bulk_bulldozer/content/bulk_bulldozer/):
  bulk_bulldozer@2x.tga          240x150, `icon = resolve("bulk_bulldozer.tga")`
  bulk_bulldozer_preview@2x.tga  1368x770, `previewIcon = resolve("bulk_bulldozer_preview.tga")`
(the game picks the @2x file; sizes as the Overpass Builder mod's tool icons).

Format: uncompressed 32-bit BGRA TGA, bottom-left origin, transparent background (same writer as
tools/render_icon_square_roundabouts.py).

Usage: uv run tools/render_icon_square_bulk_bulldozer.py [--png preview.png]
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR  # noqa: E402

OUT_DIR = MODS_DIR / "square_bulk_bulldozer/content/bulk_bulldozer"
S = 4  # supersampling factor

RING = (235, 92, 60, 255)
BODY = (242, 178, 36, 255)      # construction-machine amber
BODY_DARK = (196, 132, 18, 255)
TRACK = (52, 50, 48, 255)
WHEEL = (128, 124, 118, 255)
GLASS = (168, 206, 228, 255)
STEEL = (150, 146, 140, 255)


def render(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = h * S / 150  # design units: the 150 px icon height
    ox = (w * S - 240 * u) / 2  # centre a 240x150 design on wider canvases

    def P(x: float, y: float) -> tuple[float, float]:
        return (ox + x * u, y * u)

    def rect(x0, y0, x1, y1, fill, r=0.0):
        d.rounded_rectangle([P(x0, y0), P(x1, y1)], radius=r * u, fill=fill)

    # dashed brush ring behind the machine
    cx, cy, r = 114, 79, 64
    dashes = 28
    for i in range(dashes):
        a0 = 360 / dashes * i
        d.arc([P(cx - r, cy - r), P(cx + r, cy + r)], a0, a0 + 360 / dashes * 0.6, fill=RING, width=int(6 * u))

    # bulldozer, side view, facing left (blade on the left)
    rect(86, 92, 170, 116, TRACK, r=12)                     # track
    for x in (98, 115, 132, 149, 158):
        d.ellipse([P(x - 6, 98), P(x + 6, 110)], fill=WHEEL)  # road wheels
    rect(94, 70, 166, 93, BODY, r=3)                        # engine deck
    rect(94, 86, 166, 93, BODY_DARK)                        # deck shadow line
    rect(128, 40, 162, 72, BODY, r=3)                       # cab
    rect(133, 45, 157, 62, GLASS, r=2)                      # cab window
    rect(104, 52, 109, 71, TRACK, r=1)                      # exhaust stack
    # push arm and blade
    d.line([P(96, 84), P(70, 92)], fill=BODY_DARK, width=int(6 * u))
    d.polygon([P(58, 66), P(70, 64), P(74, 118), P(56, 120), P(62, 94)], fill=STEEL)
    d.line([P(58, 120), P(74, 118)], fill=TRACK, width=int(3 * u))  # cutting edge
    return img.resize((w, h), Image.LANCZOS)


def write_tga(img: Image.Image, path: Path) -> None:
    """Uncompressed 32-bit BGRA, bottom-left origin, TGA 2.0 footer (as the base icons)."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, img.width, img.height, 32, 8)
    rows = []
    px = img.load()
    for y in range(img.height - 1, -1, -1):
        row = bytearray()
        for x in range(img.width):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    path.write_bytes(header + b"".join(rows) + footer)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--png", type=Path, help="also write a PNG preview of the icon (on the menu tile grey)")
    args = ap.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for (w, h), name in (((240, 150), "bulk_bulldozer@2x.tga"), ((1368, 770), "bulk_bulldozer_preview@2x.tga")):
        img = render(w, h)
        out = OUT_DIR / name
        write_tga(img, out)
        print(f"wrote {out.relative_to(MODS_DIR.parent)} ({img.width}x{img.height}, 32-bit TGA)")
        if args.png and w == 240:
            bg = Image.new("RGBA", img.size, (178, 182, 186, 255))  # menu tile grey
            bg.alpha_composite(img)
            bg.save(args.png)
            print(f"wrote {args.png}")


if __name__ == "__main__":
    main()
