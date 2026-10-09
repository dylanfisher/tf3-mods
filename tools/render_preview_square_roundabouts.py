# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render the construction-menu hover previews of square_roundabouts from in-game captures.

Outputs (mods/square_roundabouts/content/infrastructure/street_construction/):
  square_roundabouts_preview@2x.tga        `previewIcon = "square_roundabouts_preview.tga"`
  square_roundabouts_magic_preview@2x.tga  `previewIcon = "square_roundabouts_magic_preview.tga"`
  square_roundabouts_channel_preview@2x.tga      `previewIcon = "square_roundabouts_channel_preview.tga"`
  square_roundabouts_interchange_preview@2x.tga  `previewIcon = "square_roundabouts_interchange_preview.tga"`
(the game picks the @2x file, like the base `roundabout_preview.tga` -> `roundabout_preview@2x.tga`
in base infrastructure/street_construction.zip).

Format (matches the base roundabout_preview@2x.tga header): 720x405 px, uncompressed 24-bit BGR
TGA (image type 2), bottom-left origin, TGA 2.0 footer (docs/wiki/modding/constructions/basics.md:
"`previewIcon` ... has a resolution of 720x405 pixels").

Sources: 16:9 crops of the captures in plans/square_roundabouts/shots/ (5120x2880, UI-free areas),
downscaled with Lanczos. Same inputs give the same bytes.

Usage: uv run tools/render_preview_square_roundabouts.py [--png DIR]   (--png also writes PNG copies)
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402

SHOTS = ROOT / "plans/square_roundabouts/shots"
OUT_DIR = MODS_DIR / "square_roundabouts/content/infrastructure/street_construction"
W, H = 720, 405

# name -> (capture, crop [x, y, w, h] in capture pixels, 16:9)
PREVIEWS = {
    # hamburger roundabout: oval ring, road through the centre, splitter islands, tree island
    "square_roundabouts_preview@2x.tga": ("15-oblique-hamburger.jpg", [2000, 400, 2208, 1242]),
    # close-up of a paved Magic Roundabout with fountain and hedge ring
    "square_roundabouts_magic_preview@2x.tga": ("03-magic-closeup.jpg", [360, 120, 4448, 2502]),
    # top-down T channelized junction with slip lanes and triangle islands (the only capture of
    # it; the top-down view is a little soft at this zoom)
    "square_roundabouts_channel_preview@2x.tga": ("14-top-down-variety.jpg", [1788, 733, 1120, 630]),
    # two-bridge ring over a medium highway with its four slip roads
    "square_roundabouts_interchange_preview@2x.tga": ("17-interchange-closeup.jpg", [1300, 160, 2560, 1440]),
}


def render(src: str, crop: list[int]) -> Image.Image:
    x, y, w, h = crop
    if abs(w / h - W / H) > 0.01:
        raise SystemExit(f"{src}: crop {crop} is not 16:9")
    with Image.open(SHOTS / src) as img:
        return img.convert("RGB").crop((x, y, x + w, y + h)).resize((W, H), Image.LANCZOS)


def write_tga(img: Image.Image, path: Path) -> None:
    """Uncompressed 24-bit BGR TGA, bottom-left origin (descriptor 0), TGA 2.0 footer."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, img.width, img.height, 24, 0)
    r, g, b = img.split()
    bgr = Image.merge("RGB", (b, g, r)).transpose(Image.FLIP_TOP_BOTTOM)
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    path.write_bytes(header + bgr.tobytes() + footer)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--png", type=Path, help="also write PNG copies into this directory")
    args = ap.parse_args()
    for name, (src, crop) in PREVIEWS.items():
        img = render(src, crop)
        out = OUT_DIR / name
        write_tga(img, out)
        print(f"wrote   {out.relative_to(ROOT)} {img.width}x{img.height} 24-bit")
        if args.png:
            args.png.mkdir(parents=True, exist_ok=True)
            img.save(args.png / (Path(name).stem.replace("@2x", "") + ".png"))


if __name__ == "__main__":
    main()
