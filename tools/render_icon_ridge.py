# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render the top-bar ("ridge") button icons of the square mods that put a button there.

Every icon is a plain white 48x48 mask, shown at 24x24 UI px on the base's dark button tile and tinted by
the ImageView `color`, like the base data layers icon (gui/layers/icons/symbol_layers@2x.tga: glyph in
about 3..45 x 8..41) and Better Minimap's map icon (tools/render_icon_square_better_minimap.py, which
draws that one).

Output (the game picks the @2x file, as the base icons):
  square_industry_flows  content/industry_flows/gui/flows@2x.tga  factory with an arrow out to the right
  square_supply_gaps     content/supply_gaps/gui/gaps@2x.tga      house with a "missing" (minus) badge
  square_stress_test     content/stress/gui/gauge@2x.tga          gauge with the needle in the high range
  square_photo_mode      content/photo_mode/gui/camera@2x.tga     camera: body, viewfinder hump, lens ring

Format: uncompressed 32-bit BGRA TGA (type 2, descriptor 0x08), bottom-left origin, TGA 2.0 footer, as
tools/render_icon_square_better_minimap.py. Drawn 8x supersampled and downsampled.

Usage: uv run tools/render_icon_ridge.py [--png DIR]
"""

from __future__ import annotations

import argparse
import math
import sys
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR  # noqa: E402
from render_icon_square_better_minimap import write_tga  # noqa: E402

SIZE = 48
SS = 8


def _s(*xy: float) -> list[float]:
    return [v * SS for v in xy]


def _canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    mask = Image.new("L", (SIZE * SS, SIZE * SS), 0)
    return mask, ImageDraw.Draw(mask)


def _finish(mask: Image.Image) -> Image.Image:
    big = SIZE * SS
    img = Image.merge("RGBA", (*Image.new("RGB", (big, big), (255, 255, 255)).split(), mask))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def _circle(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill: int) -> None:
    d.ellipse(_s(cx - r, cy - r, cx + r, cy + r), fill=fill)


def _ring(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, w: float) -> None:
    """Ring of stroke w centred on radius r."""
    _circle(d, cx, cy, r + w / 2, 255)
    _circle(d, cx, cy, r - w / 2, 0)


def _line(d: ImageDraw.ImageDraw, x0: float, y0: float, x1: float, y1: float, w: float) -> None:
    """Line with round caps."""
    d.line(_s(x0, y0, x1, y1), fill=255, width=round(w * SS))
    _circle(d, x0, y0, w / 2, 255)
    _circle(d, x1, y1, w / 2, 255)


def render_flows() -> Image.Image:
    """Factory (sawtooth roof, chimney) on the left, a bold arrow leaving it to the right."""
    mask, d = _canvas()
    # Factory body with a two-tooth sawtooth roof and a chimney on the left.
    d.polygon(_s(3, 41, 3, 22, 10, 17, 10, 22, 17, 17, 17, 22, 24, 22, 24, 41), fill=255)
    d.rectangle(_s(4, 9, 8, 20), fill=255)
    # Arrow: shaft from the factory wall, head reaching the right edge.
    d.rectangle(_s(26, 28, 36, 34), fill=255)
    d.polygon(_s(34, 21, 45, 31, 34, 41), fill=255)
    return _finish(mask)


def render_gaps() -> Image.Image:
    """House silhouette with a round badge at the bottom right holding a minus (a missing supply)."""
    mask, d = _canvas()
    d.polygon(_s(3, 21, 17, 8, 31, 21, 28, 21, 28, 40, 6, 40, 6, 21), fill=255)
    cx, cy = 34.5, 31.5
    _circle(d, cx, cy, 12.5, 0)    # gap around the badge
    _circle(d, cx, cy, 9.5, 255)
    d.rectangle(_s(cx - 5.5, cy - 1.6, cx + 5.5, cy + 1.6), fill=0)
    return _finish(mask)


def render_gauge() -> Image.Image:
    """Gauge: an open arc (upper three quarters), ticks, and the needle pointing into the high range."""
    mask, d = _canvas()
    cx, cy, r, w = 24.0, 26.5, 18.0, 3.6
    box = _s(cx - r - w / 2, cy - r - w / 2, cx + r + w / 2, cy + r + w / 2)
    # PIL angles: 0 = east, clockwise. Arc from 135 (lower left) through the top to 45 (lower right).
    d.arc(box, start=135, end=405, fill=255, width=round(w * SS))
    for ang in (135, 405):
        t = math.radians(ang)
        _circle(d, cx + r * math.cos(t), cy + r * math.sin(t), w / 2, 255)
    # Ticks inside the arc.
    for ang in (180, 225, 270, 315, 360):
        t = math.radians(ang)
        _line(d, cx + (r - 5.5) * math.cos(t), cy + (r - 5.5) * math.sin(t),
              cx + (r - 8.5) * math.cos(t), cy + (r - 8.5) * math.sin(t), 2.4)
    # Needle to the upper right (high range), hub on top.
    t = math.radians(-35)
    _line(d, cx, cy, cx + 14 * math.cos(t), cy + 14 * math.sin(t), 3.4)
    _circle(d, cx, cy, 4.2, 255)
    return _finish(mask)


def render_camera() -> Image.Image:
    """Camera: rounded body with a viewfinder hump on top, a lens ring in the middle, a small flash window."""
    mask, d = _canvas()
    d.rounded_rectangle(_s(3, 15, 45, 41), radius=5 * SS, fill=255)
    d.polygon(_s(15, 16, 18.5, 9, 29.5, 9, 33, 16), fill=255)
    cx, cy = 24.0, 28.0
    _circle(d, cx, cy, 10.5, 0)    # gap around the lens
    _circle(d, cx, cy, 7.0, 255)   # lens
    _circle(d, cx, cy, 3.0, 0)     # glass highlight hole
    d.rounded_rectangle(_s(36, 19, 41, 22.5), radius=1.2 * SS, fill=0)  # flash window
    return _finish(mask)


ICONS: list[tuple[str, Path, Callable[[], Image.Image]]] = [
    ("flows", MODS_DIR / "square_industry_flows" / "content" / "industry_flows" / "gui" / "flows@2x.tga", render_flows),
    ("gaps", MODS_DIR / "square_supply_gaps" / "content" / "supply_gaps" / "gui" / "gaps@2x.tga", render_gaps),
    ("gauge", MODS_DIR / "square_stress_test" / "content" / "stress" / "gui" / "gauge@2x.tga", render_gauge),
    ("camera", MODS_DIR / "square_photo_mode" / "content" / "photo_mode" / "gui" / "camera@2x.tga", render_camera),
]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--png", type=Path, metavar="DIR",
                    help="also write enlarged PNG previews on the dark button tile to DIR")
    args = ap.parse_args()
    for name, out, fn in ICONS:
        img = fn()
        write_tga(img, out)
        print(f"wrote {out.relative_to(MODS_DIR.parent)} ({img.width}x{img.height}, 32-bit TGA)")
        if args.png:
            args.png.mkdir(parents=True, exist_ok=True)
            bg = Image.new("RGBA", img.size, (52, 56, 64, 255))
            bg.alpha_composite(img)
            bg.resize((img.width * 6, img.height * 6), Image.NEAREST).save(args.png / f"{name}.png")
            small = Image.new("RGBA", (40, 40), (52, 56, 64, 255))
            small.alpha_composite(img.resize((24, 24), Image.LANCZOS), (8, 8))
            small.resize((160, 160), Image.NEAREST).save(args.png / f"{name}_24.png")


if __name__ == "__main__":
    main()
