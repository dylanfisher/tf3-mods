# /// script
# requires-python = ">=3.11"
# ///
"""Render mod covers in the "square" house style to mods/<id>/_metadata/0.png.

Covers are defined in branding/mods.js and drawn by branding/cover.js; this
script screenshots branding/render.html?mod=<id> with headless Chrome at
exactly 1920x1080 (the wiki's cover size). Mods without an entry in mods.js
are reported and skipped.

Usage: uv run tools/render_covers.py [mods/<id> ...] [--no-text]
Set CHROME=/path/to/chrome if Chrome isn't found automatically.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402

BRANDING = ROOT / "branding"
CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome", "chromium", "chromium-browser",
]


def find_chrome() -> str:
    for c in [os.environ.get("CHROME", ""), *CHROME_CANDIDATES]:
        if c and (Path(c).exists() or shutil.which(c)):
            return c
    sys.exit("Chrome not found; set CHROME=/path/to/chrome")


def registered_ids() -> list[str]:
    return re.findall(r"^\s*id:\s*'([a-z0-9_]+)'", (BRANDING / "mods.js").read_text(), re.M)


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def render(chrome: str, mod_id: str, query: str, out: Path) -> None:
    url = (BRANDING / "render.html").as_uri() + f"?mod={mod_id}{query}"
    out.unlink(missing_ok=True)
    cmd = [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
           "--window-size=1920,1080", "--virtual-time-budget=3000", f"--screenshot={out}", url]
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        # Headless Chrome occasionally writes the screenshot and then fails to exit.
        if not out.exists():
            raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mods", nargs="*", help="mod folders (default: every mod with an entry in branding/mods.js)")
    parser.add_argument("--no-text", action="store_true", help="omit the title and tagline")
    args = parser.parse_args()

    known = registered_ids()
    wanted = [Path(m).name for m in args.mods] or [p.name for p in sorted(MODS_DIR.iterdir()) if p.is_dir()]
    query = "&text=0" if args.no_text else ""
    chrome = find_chrome()

    failed = False
    for mod_id in wanted:
        if mod_id not in known:
            print(f"skip    {mod_id}: no entry in branding/mods.js")
            failed = failed or bool(args.mods)
            continue
        meta = MODS_DIR / mod_id / "_metadata"
        if not meta.is_dir():
            print(f"skip    {mod_id}: {meta} missing")
            failed = True
            continue
        out = meta / "0.png"
        render(chrome, mod_id, query, out)
        size = png_size(out)
        ok = size == (1920, 1080)
        failed = failed or not ok
        print(f"{'wrote' if ok else 'BAD  '}   {out.relative_to(ROOT)} {size[0]}x{size[1]} {out.stat().st_size // 1024} KB")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
