# /// script
# requires-python = ">=3.11"
# ///
"""Render mod gallery slides in the "square" house style to mods/<id>/_metadata/<n>-<hash>.png.

Slides are defined in branding/shots.js (captures in plans/<id>/shots/) and drawn by
branding/slide.js; this script screenshots branding/slide.html?mod=<id>&n=<n> with headless
Chrome at 1920x1080. The file is named after its content hash, the same name modio_sync.py
uploads it under, so a Mod Hub upload leaves mod.io's gallery as it is (docs/findings.md). Older
copies of a slide and stale slides (beyond the defined count) are removed; 0.png (the cover, see
render_covers.py) is never touched.

Usage: uv run tools/render_shots.py [mods/<id> ...]
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402
from render_covers import find_chrome, png_size  # noqa: E402

BRANDING = ROOT / "branding"
MAX_SLIDES = 9  # 19 and 22 failed the Mod Hub upload with mod.io error 13003 FILE_TOO_MANY; 10 uploaded, but a Hub
# upload left 10-slide galleries out of order on mod.io (slide 10 second); single-digit names stay in order (docs/findings.md)
SLIDE_RE = re.compile(r"^(\d+)(?:-[0-9a-f]{8})?$")  # N.png or N-<hash>.png, as modio_sync.py reads them


def slide_number(path: Path) -> int | None:
    m = SLIDE_RE.match(path.stem)
    return int(m.group(1)) if m and path.suffix == ".png" else None


def hashed_name(n: int, data: bytes, count: int) -> str:
    """N-<first 8 hex of sha256>.png: modio_sync.py's upload name for this slide. N is zero-padded to the width of
    the slide count (02 of 22): the Mod Hub sorts gallery files as text, so 10-19 showed before 2."""
    return f"{n:0{len(str(count))}d}-{hashlib.sha256(data).hexdigest()[:8]}.png"


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
        if counts[mod_id] > MAX_SLIDES:
            print(f"skip    {mod_id}: {counts[mod_id]} slides in branding/shots.js, at most {MAX_SLIDES} (more fail or mix up the Hub upload, docs/findings/publishing.md)")
            failed = True
            continue
        for old in meta.glob("*.png"):
            n = slide_number(old)
            if n is not None and n > counts[mod_id]:
                old.unlink()
                print(f"removed {old.relative_to(ROOT)}")
        for n in range(1, counts[mod_id] + 1):
            tmp = meta / f".render-{n}.png"
            render(chrome, mod_id, n, tmp)
            out = meta / hashed_name(n, tmp.read_bytes(), counts[mod_id])
            for old in meta.glob("*.png"):
                if slide_number(old) == n and old != out:
                    old.unlink()
            tmp.replace(out)
            size = png_size(out)
            ok = size == (1920, 1080)
            failed = failed or not ok
            print(f"{'wrote' if ok else 'BAD  '}   {out.relative_to(ROOT)} {size[0]}x{size[1]} {out.stat().st_size // 1024} KB")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
