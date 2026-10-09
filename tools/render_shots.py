# /// script
# requires-python = ">=3.11"
# ///
"""Render mod gallery slides in the "square" house style to mods/<id>/_metadata/<n>.png.

Slides are defined in branding/shots.js (captures in plans/<id>/shots/) and drawn by
branding/slide.js; this script screenshots branding/slide.html?mod=<id>&n=<n> with headless
Chrome at 1920x1080. Stale numbered slides (beyond the defined count) are removed; 0.png
(the cover, see render_covers.py) is never touched.

Usage: uv run tools/render_shots.py [mods/<id> ...]
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402
from render_covers import find_chrome, png_size  # noqa: E402

BRANDING = ROOT / "branding"


def slide_counts() -> dict[str, int]:
    """Slide count per mod, read from the Square.slides('<id>', [...]) blocks in shots.js."""
    text = (BRANDING / "shots.js").read_text()
    counts = {}
    for m in re.finditer(r"Square\.slides\('([a-z0-9_]+)', \[(.*?)\n\]\);", text, re.S):
        counts[m.group(1)] = len(re.findall(r"^\s*\{ title:", m.group(2), re.M))
    return counts


def render(chrome: str, mod_id: str, n: int, out: Path) -> None:
    url = (BRANDING / "slide.html").as_uri() + f"?mod={mod_id}&n={n}"
    out.unlink(missing_ok=True)
    cmd = [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
           "--allow-file-access-from-files", "--window-size=1920,1080", "--virtual-time-budget=5000",
           f"--screenshot={out}", url]
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=90)
    except subprocess.TimeoutExpired:
        if not out.exists():
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mods", nargs="*", help="mod folders (default: every mod with slides in branding/shots.js)")
    args = parser.parse_args()

    counts = slide_counts()
    wanted = [Path(m).name for m in args.mods] or sorted(counts)
    chrome = find_chrome()
    failed = False
    for mod_id in wanted:
        meta = MODS_DIR / mod_id / "_metadata"
        if mod_id not in counts or not meta.is_dir():
            print(f"skip    {mod_id}: no slides in branding/shots.js or no _metadata/")
            failed = failed or bool(args.mods)
            continue
        for old in meta.glob("*.png"):
            if old.stem.isdigit() and int(old.stem) > counts[mod_id]:
                old.unlink()
                print(f"removed {old.relative_to(ROOT)}")
        for n in range(1, counts[mod_id] + 1):
            out = meta / f"{n}.png"
            render(chrome, mod_id, n, out)
            size = png_size(out)
            ok = size == (1920, 1080)
            failed = failed or not ok
            print(f"{'wrote' if ok else 'BAD  '}   {out.relative_to(ROOT)} {size[0]}x{size[1]} {out.stat().st_size // 1024} KB")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
