# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render the icons of square_better_minimap ("Better Minimap"): view triangle, size magnifier, map button.

A slim white isosceles triangle, tip up, with a faint dark halo so it still reads on snow and pale
terrain. The minimap turns it with ImageView.rotation around the image centre, so the triangle's
centroid sits near the centre and the tip stays clear of the edge.

The size button's magnifier is a plain white mask (ring + handle), cropped tight so it fills its box.
The base magnifier (gui/line_vehicle_mgmt/icons/inspector@2x.tga) has its glyph in only the middle 40%
of the image and read as a ~9 px dot at 22 UI px in game (2026-10-10).

Output (mods/square_better_minimap/content/minimap/gui/):
  cam_arrow@2x.tga  32x32, loaded as "square_better_minimap::/minimap/gui/cam_arrow.tga" at 16x16 UI px
  zoom@2x.tga       48x48, loaded as "square_better_minimap::/minimap/gui/zoom.tga" at 24x24 UI px
  map@2x.tga        48x48, loaded as "square_better_minimap::/minimap/gui/map.tga" at 24x24 UI px: the
                    top-bar button's "Icon" style, a folded map in the footprint of the base layers
                    icon (gui/layers/icons/symbol_layers@2x.tga: 48x48 white mask, glyph 3..45 x 8..41)
(the game picks the @2x file, as the base icons).

Format: uncompressed 32-bit BGRA TGA (type 2, descriptor 0x08), bottom-left origin, TGA 2.0 footer,
as tools/render_icon_square_smart_lanes.py. Drawn 8x supersampled and downsampled.

Usage: uv run tools/render_icon_square_better_minimap.py [--png DIR]
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR  # noqa: E402

OUT_DIR = MODS_DIR / "square_better_minimap" / "content" / "minimap" / "gui"
SIZE = 32
SS = 8
# Triangle in output pixels: tip, base corners. Centroid y = (2 + 26 + 26) / 3 = 18, close to the centre.
TIP = (16.0, 2.0)
BASE_Y = 26.0
HALF_W = 7.0


def render() -> Image.Image:
    big = SIZE * SS
    pts = [(TIP[0] * SS, TIP[1] * SS), ((16 + HALF_W) * SS, BASE_Y * SS), ((16 - HALF_W) * SS, BASE_Y * SS)]
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    # Halo: the shape grown ~1 px and softened, dark at low alpha.
    halo = mask.filter(ImageFilter.MaxFilter(2 * SS + 1)).filter(ImageFilter.GaussianBlur(SS * 0.6))
    halo = halo.point(lambda v: v * 110 // 255)
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (big, big), (0, 0, 0, 255)), mask=halo)
    img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (big, big), (255, 255, 255)).split(), mask)))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


ZOOM_SIZE = 48
# Magnifier in output pixels: lens centre, outer radius, ring width; handle to the bottom-right corner.
LENS_C = (19.0, 19.0)
LENS_R = 15.0
RING_W = 5.0
HANDLE_END = (44.0, 44.0)
HANDLE_W = 7.0


def render_zoom() -> Image.Image:
    big = ZOOM_SIZE * SS
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    cx, cy, r = LENS_C[0] * SS, LENS_C[1] * SS, LENS_R * SS
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    ri = (LENS_R - RING_W) * SS
    d.ellipse((cx - ri, cy - ri, cx + ri, cy + ri), fill=0)
    # Handle: from the ring's outer edge at 45 degrees to the corner, round caps.
    k = 0.7071 * (LENS_R - 1.0)
    x0, y0 = (LENS_C[0] + k) * SS, (LENS_C[1] + k) * SS
    x1, y1 = HANDLE_END[0] * SS, HANDLE_END[1] * SS
    w = HANDLE_W * SS
    d.line((x0, y0, x1, y1), fill=255, width=int(w))
    for x, y in ((x0, y0), (x1, y1)):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=255)
    img = Image.merge("RGBA", (*Image.new("RGB", (big, big), (255, 255, 255)).split(), mask))
    return img.resize((ZOOM_SIZE, ZOOM_SIZE), Image.LANCZOS)


MAP_SIZE = 48
# Folded map in output pixels: three panels zigzagging between a high and a low edge, a gap between
# panels so the folds read at 24 UI px.
MAP_X = (4.0, 17.5, 30.5, 44.0)
MAP_TOP = (9.0, 13.0)    # panel top edge at the high / low fold
MAP_BOTTOM = (36.0, 40.0)
MAP_GAP = 1.6


def render_map() -> Image.Image:
    big = MAP_SIZE * SS
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    for i in range(3):
        x0, x1 = MAP_X[i] + (MAP_GAP / 2 if i > 0 else 0), MAP_X[i + 1] - (MAP_GAP / 2 if i < 2 else 0)
        # Panels 0 and 2 slope down to the right, panel 1 up: the folds alternate high / low.
        hi_left = i != 1
        t0, t1 = (MAP_TOP[0], MAP_TOP[1]) if hi_left else (MAP_TOP[1], MAP_TOP[0])
        b0, b1 = (MAP_BOTTOM[0], MAP_BOTTOM[1]) if hi_left else (MAP_BOTTOM[1], MAP_BOTTOM[0])
        d.polygon([(x0 * SS, t0 * SS), (x1 * SS, t1 * SS), (x1 * SS, b1 * SS), (x0 * SS, b0 * SS)], fill=255)
    img = Image.merge("RGBA", (*Image.new("RGB", (big, big), (255, 255, 255)).split(), mask))
    return img.resize((MAP_SIZE, MAP_SIZE), Image.LANCZOS)


def write_tga(img: Image.Image, path: Path) -> None:
    """Uncompressed 32-bit BGRA, bottom-left origin, TGA 2.0 footer (as the base icons)."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, img.width, img.height, 32, 8)
    r, g, b, a = img.convert("RGBA").transpose(Image.FLIP_TOP_BOTTOM).split()
    body = Image.merge("RGBA", (b, g, r, a)).tobytes()
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    path.write_bytes(header + body + footer)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--png", type=Path, metavar="DIR", help="also write an enlarged PNG preview on map green to DIR")
    args = ap.parse_args()
    img = render()
    out = OUT_DIR / "cam_arrow@2x.tga"
    write_tga(img, out)
    print(f"wrote {out.relative_to(MODS_DIR.parent)} ({img.width}x{img.height}, 32-bit TGA)")
    zoom = render_zoom()
    zout = OUT_DIR / "zoom@2x.tga"
    write_tga(zoom, zout)
    print(f"wrote {zout.relative_to(MODS_DIR.parent)} ({zoom.width}x{zoom.height}, 32-bit TGA)")
    mp = render_map()
    mout = OUT_DIR / "map@2x.tga"
    write_tga(mp, mout)
    print(f"wrote {mout.relative_to(MODS_DIR.parent)} ({mp.width}x{mp.height}, 32-bit TGA)")
    if args.png:
        args.png.mkdir(parents=True, exist_ok=True)
        for name, im in (("cam_arrow", img), ("zoom", zoom), ("map", mp)):
            bg = Image.new("RGBA", im.size, (96, 120, 72, 255))
            bg.alpha_composite(im)
            bg.resize((im.width * 8, im.height * 8), Image.NEAREST).save(args.png / f"{name}.png")


if __name__ == "__main__":
    main()
