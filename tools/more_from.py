# /// script
# requires-python = ">=3.11"
# ///
"""Write the "More from square" section into mods' _metadata/description.html.

The groups live in branding/more_from.json. The order, mod.io page names and logo files come from our mod.io
profile page, saved to branding/modio_profiles.json by --refresh (headless Chrome renders the page; no token
needed). Logo tiles use mod.io's own CDN copy of each mod's logo (docs/findings/publishing.md
"mod.io description HTML"), so nothing is uploaded.

The section sits right before the Changelog's <hr>, from "<hr>\\n<h4>More from" up to there; running again
replaces it. A mod's own entry is left out of its section.

Usage: uv run tools/more_from.py [--refresh] [--check] [--published] mods/<id> ...
  --published  every mod on the mod.io profile (modio_profiles.json) instead of listing them
  --refresh  re-read the profile page (order, logos) before writing
  --check    only report which descriptions are out of date (exit 1 if any)
Set CHROME=/path/to/chrome if Chrome isn't found automatically.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import html
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402
from render_covers import find_chrome  # noqa: E402

BRANDING = ROOT / "branding"
CONFIG = BRANDING / "more_from.json"
PROFILES = BRANDING / "modio_profiles.json"
STATE = BRANDING / "modio_state.json"
MOD_URL = "https://mod.io/g/transportfever3/m/{slug}"
TILE_WIDTH = 200
SECTION_START = "<hr>\n<h4>More from"
CHANGELOG = "<hr>\n<h2>Changelog</h2>"


def slugify(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def mod_name(mod_id: str) -> str:
    return json.loads((MODS_DIR / mod_id / "_metadata" / "modinfo.json").read_text(encoding="utf-8"))["name"]


def parse_profile(dom: str) -> list[dict]:
    """Mods in page order: slug, modioId and logo filename from each card's thumbnail."""
    out, seen = [], set()
    for m in re.finditer(r'href="/g/transportfever3/m/([a-z0-9-]+)"', dom):
        slug = m.group(1)
        if slug in seen:
            continue
        img = re.search(r"modcdn\.io/mods/[0-9a-f]+/(\d+)/[^/\"]+/([^\"&)]+)", dom[m.start():m.start() + 3000])
        if not img:
            continue
        seen.add(slug)
        out.append({"slug": slug, "modioId": int(img.group(1)), "logo": img.group(2)})
    return out


def map_mod_ids(entries: list[dict]) -> list[str]:
    """Fill each entry's modId: by modioId from modio_state.json, else by the slug of a local mod's name."""
    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {}
    by_modio = {v.get("modioId"): k for k, v in state.items()}
    by_slug = {}
    for info in sorted(MODS_DIR.glob("square_*/_metadata/modinfo.json")):
        by_slug.setdefault(slugify(json.loads(info.read_text(encoding="utf-8"))["name"]), info.parent.parent.name)
    missing = []
    for e in entries:
        e["modId"] = by_modio.get(e["modioId"]) or by_slug.get(e["slug"])
        if not e["modId"]:
            missing.append(e["slug"])
    return missing


def refresh(url: str) -> list[dict]:
    cmd = [find_chrome(), "--headless=new", "--disable-gpu", "--window-size=1400,8000",
           "--virtual-time-budget=20000", "--dump-dom", url]
    dom = subprocess.run(cmd, check=True, capture_output=True, text=True, timeout=120).stdout
    entries = parse_profile(dom)
    if not entries:
        sys.exit(f"no mods found on {url} (page layout changed?)")
    missing = map_mod_ids(entries)
    if missing:
        sys.exit(f"can't match these mod.io mods to a local mod: {', '.join(missing)}")
    PROFILES.write_text(json.dumps({"source": url, "refreshed": date.today().isoformat(), "mods": entries},
                                   indent=2) + "\n", encoding="utf-8")
    print(f"{PROFILES.relative_to(ROOT)}: {len(entries)} mods from {url}")
    return entries


def resolve_groups(config: dict, entries: list[dict]) -> list[dict]:
    """Each group's entries in display order; error when a published mod is in no group."""
    rank = {e["modId"]: i for i, e in enumerate(entries)}
    by_id = {e["modId"]: e for e in entries}
    placed = set(config.get("exclude", []))
    groups = []
    for g in config["groups"]:
        ids = []
        for pat in g["mods"]:
            hits = [pat] if pat in by_id else sorted(fnmatch.filter(by_id, pat), key=rank.get)
            ids += [i for i in hits if i not in ids]
        placed.update(ids)
        if not g.get("fixedOrder"):
            ids.sort(key=rank.get)
        groups.append({**g, "entries": [by_id[i] for i in ids]})
    unplaced = [e["modId"] for e in entries if e["modId"] not in placed]
    if unplaced:
        sys.exit(f"published but in no group of {CONFIG.relative_to(ROOT)}: {', '.join(unplaced)}")
    return groups


def tile(e: dict, name: str, style: str = "") -> str:
    h = hashlib.md5(str(e["modioId"]).encode()).hexdigest()[:4]
    img = f"https://thumb.modcdn.io/mods/{h}/{e['modioId']}/crop_640x360/{e['logo']}"
    return (f'<a href="{MOD_URL.format(slug=e["slug"])}"><img src="{img}" alt="{html.escape(name)}" '
            f'width="{TILE_WIDTH}"' + (f' style="{html.escape(style)}"' if style else "") + "></a>")


def render_section(config: dict, groups: list[dict], host: str, names=mod_name) -> str:
    out = ["<hr>", f"<h4>{config['heading']}</h4>"]
    for g in groups:
        entries = [e for e in g["entries"] if e["modId"] != host]
        if not entries:
            continue
        title = html.escape(g["title"])
        if g["style"] == "line":
            strip = g.get("labelStrip", "")
            links = [f'<a href="{MOD_URL.format(slug=e["slug"])}">{html.escape(names(e["modId"]).removesuffix(strip))}</a>'
                     for e in entries]
            out.append(f"<p><strong>{title}</strong>: {' · '.join(links)}</p>")
        else:
            out.append(f"<p><strong>{title}</strong></p>")
            out.append("<p>" + " ".join(tile(e, names(e["modId"]), config.get("tileStyle", "")) for e in entries) + "</p>")
    return "\n".join(out) + "\n"


def apply_section(desc: str, section: str) -> str:
    end = desc.find(CHANGELOG)
    if end < 0:
        raise ValueError("no '<hr>\\n<h2>Changelog</h2>' to put the section before")
    start = desc.find(SECTION_START)
    if start < 0 or start > end:
        start = end
    return desc[:start] + section + desc[end:]


def with_section(desc: str, mod_id: str) -> str:
    """desc with the current section for mod_id (generators call this; unchanged when there is no profile yet)."""
    if not PROFILES.exists():
        return desc
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    groups = resolve_groups(config, json.loads(PROFILES.read_text(encoding="utf-8"))["mods"])
    return apply_section(desc, render_section(config, groups, mod_id))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mods", nargs="*", help="mods/<id> to write the section into")
    ap.add_argument("--refresh", action="store_true", help="re-read the mod.io profile page first")
    ap.add_argument("--check", action="store_true", help="only report out-of-date descriptions")
    ap.add_argument("--published", action="store_true", help="every mod on the mod.io profile")
    args = ap.parse_args()
    config = json.loads(CONFIG.read_text(encoding="utf-8"))
    if args.refresh or not PROFILES.exists():
        entries = refresh(config["profile"])
    else:
        entries = json.loads(PROFILES.read_text(encoding="utf-8"))["mods"]
    groups = resolve_groups(config, entries)
    if args.published:
        args.mods += [str(MODS_DIR / e["modId"]) for e in entries]
    if not args.mods:
        if not args.refresh:
            print("no mods given (MOD=mods/<id>)")
        return 0
    stale = 0
    for arg in args.mods:
        mod = Path(arg).resolve()
        path = mod / "_metadata" / "description.html"
        desc = path.read_text(encoding="utf-8")
        new = apply_section(desc, render_section(config, groups, mod.name))
        rel = path.relative_to(ROOT)
        if new == desc:
            print(f"ok       {rel}")
        elif args.check:
            stale += 1
            print(f"stale    {rel}")
        else:
            path.write_text(new, encoding="utf-8")
            print(f"written  {rel}")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
