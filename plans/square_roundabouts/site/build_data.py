# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "lupa"]
# ///
"""Data files for the Roundabouts & Interchanges microsite (site/src/mods/square_roundabouts/): data page, gallery, layout wall.

Writes plans/square_roundabouts/site/data/*.json in the generic data-explorer format (tools/site_table.py, version 1):
  probe-*.json   one per probe CSV in plans/square_roundabouts/ (the engine probe's result tables; the CSVs and logs
                 are local and gitignored, so rerun this after a probe run on the machine that has them)
  gallery.json   the facet manifest (in site/, next to data/) of the site's screenshot gallery (generic image-grid kind): the curated
                 captures in plans/square_roundabouts/shots/ (captions below) plus site/shots/shots.json (the screenshots
                 picked for the site, with their own captions)
  shots/settings-panel-*.jpg  the settings panels cropped out of the full-screen captures shots/40-44 (CROPS below)
  layouts/*.svg, layouts.json  plan drawings of every layout sweep, from the mod's own geometry (layouts.py)
  tests.json     one row per offline test of tests/square_roundabouts/ with its last quick-mode time
                 (.cache/test_timings.json, written by `make test`)
Diagnostic columns (row numbers, replay keys, dev overrides, internal flags) are left out; every label lives in the
site's manifest (probe.ts). Data only, never HTML.

Usage: uv run plans/square_roundabouts/site/build_data.py
"""

from __future__ import annotations

import datetime as dt
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from site_table import convert, table  # noqa: E402

import layouts  # noqa: E402  (next to this file)

PLANS = ROOT / "plans/square_roundabouts"
OUT = PLANS / "site/data"
DROP = set(
    "n,total,key,id,mode,upd,err,geomErr,warnings,infos,a,b,rs,fork,forced,setback,edges,nmsg,added,coll,bld,sane,"
    "first,fixed,ncand,cand,acceptedList,rejected,skipped,tried,critical,ctx,dx,dy".split(",")
)


# Captions of the curated captures in plans/square_roundabouts/shots/ (file stem -> subject, view, title).
CURATED = {
    "01-overview": ("showcase", "oblique", "A field of roundabout variants"),
    "02-overview-variants": ("showcase", "oblique", "Ovals, a Magic Roundabout and 4 to 6 arms"),
    "03-magic-closeup": ("magic", "close-up", "Magic Roundabout: five minis on a two-way ring"),
    "04-top-down": ("roundabout", "top-down", "Roundabouts with 4 to 6 arms from above"),
    "05-magic-menu": ("menu", "ui", "Magic Roundabout in the road menu"),
    "06-settings-upper": ("menu", "ui", "Settings, upper half: shape, lanes, radius, arms"),
    "07-settings-lower": ("menu", "ui", "Settings, lower half: through road, arm road, tram, island"),
    "08-menu-strip": ("menu", "ui", "The mod's entries in the road menu"),
    "09-menu-main-hover": ("menu", "ui", "Better Roundabouts hover card"),
    "10-settings-main": ("menu", "ui", "Settings panel while placing"),
    "11-menu-magic-hover": ("menu", "ui", "Magic Roundabout hover card"),
    "12-menu-channel-hover": ("menu", "ui", "Channelized Junction hover card"),
    "13-menu-interchange-hover": ("menu", "ui", "Roundabout Interchange hover card"),
    "14-top-down-variety": ("showcase", "top-down", "Planted islands, a hamburger and a channelized junction"),
    "15-oblique-hamburger": ("roundabout", "oblique", "Hamburger roundabout with a road through the center"),
    "16-oblique-overview": ("showcase", "oblique", "Variety field with the road menu open"),
    "17-interchange-closeup": ("interchange", "oblique", "Two-bridge roundabout interchange"),
    "18-planet-topdown": ("showcase", "top-down", "The whole showcase disc from high above"),
    "19-oblique-mix": ("showcase", "oblique", "Ovals, chains, junctions and interchanges"),
    "20-horizon-mix": ("showcase", "oblique", "Every entry, to the horizon"),
    "21-interchange-oblique": ("interchange", "oblique", "A row of roundabout interchanges"),
    "22-interchange-ring-closeup": ("interchange", "close-up", "Interchange ring bridge in a cutting"),
    "23-dumbbell-magic-chain": ("interchange", "top-down", "Dumbbell interchange beside Magic Roundabout chains"),
    "24-interchange-grid": ("highway", "oblique", "Every highway interchange layout and scale"),
    "25-parclo-diamond": ("highway", "oblique", "Parclo and Diamond interchanges"),
    "26-compact-interchanges": ("highway", "oblique", "Compact highway interchanges"),
    "27-planet-interchanges": ("showcase", "top-down", "A disc of interchanges from high above"),
    "28-magic-field": ("showcase", "top-down", "A field of Magic Roundabouts"),
    "29-magic-islands": ("magic", "top-down", "Magic Roundabout islands: plain, trees, paved"),
    "30-magic-trees": ("magic", "close-up", "Magic Roundabout with a tree island"),
    "31-planet-roundabouts": ("showcase", "top-down", "A radial disc of roundabouts"),
    "32-horizon-roundabouts": ("showcase", "oblique", "Roundabouts to the horizon"),
    "33-ovals-chains": ("roundabout", "top-down", "Ovals and chained rings"),
    "40-settings-roundabouts": ("menu", "ui", "Better Roundabouts settings"),
    "41-settings-magic": ("menu", "ui", "Magic Roundabout settings"),
    "42-settings-channel": ("menu", "ui", "Channelized Junction settings"),
    "43-settings-interchange": ("menu", "ui", "Roundabout Interchange settings"),
    "44-settings-parclo2": ("menu", "ui", "Parclo, two quadrants settings"),
}
SUBJECTS = [
    ("roundabout", "Roundabouts"), ("magic", "Magic Roundabout"), ("channelized", "Channelized Junction"),
    ("interchange", "Roundabout Interchange"), ("highway", "Highway interchanges"), ("traffic", "Traffic"),
    ("showcase", "Showcase fields"), ("menu", "Menu and settings"),
]
VIEWS = [("top-down", "Top-down"), ("oblique", "Oblique"), ("close-up", "Close-up"), ("ui", "Interface")]


# Settings panels cut out of the full-screen revision 6 captures (5120x2880; panel at x 56-934, panel tops as
# in branding/shots.js).
CROPS = {
    "settings-panel-roundabouts.jpg": ("40-settings-roundabouts.jpg", (56, 832, 934, 2624)),
    "settings-panel-magic.jpg": ("41-settings-magic.jpg", (56, 1605, 934, 2624)),
    "settings-panel-parclo-two-quadrants.jpg": ("44-settings-parclo2.jpg", (56, 1336, 934, 2624)),
}


def crops() -> None:
    from PIL import Image

    for name, (src, box) in CROPS.items():
        out = PLANS / "site/shots" / name
        with Image.open(PLANS / "shots" / src) as im:
            im.crop(box).save(out, quality=90)
        print(f"{out.relative_to(ROOT)}: crop of {src}")


def gallery() -> None:
    items, dates = [], set()
    for f in sorted((PLANS / "shots").glob("*.jpg")):
        if f.stem not in CURATED:
            raise SystemExit(f"{f.name}: no caption in CURATED (build_data.py)")
        subject, view, title = CURATED[f.stem]
        date = dt.datetime.fromtimestamp(f.stat().st_mtime).date().isoformat()
        dates.add(date)
        items.append({"file": f"../shots/{f.name}", "title": title, "subject": subject, "view": view, "date": date, "set": "curated"})
    picked = json.loads((PLANS / "site/shots/shots.json").read_text(encoding="utf-8"))["items"]
    for it in picked:
        dates.add(it["date"])
        items.append({"file": f"shots/{it['file']}", "title": it["title"], "subject": it["subject"], "view": it["view"], "date": it["date"], "set": "play"})
    used = {(k, it[k]) for it in items for k in ("subject", "view")}
    manifest = {
        "facets": [
            {"key": "subject", "label": "Subject", "values": [{"value": v, "label": l} for v, l in SUBJECTS if ("subject", v) in used]},
            {"key": "view", "label": "View", "values": [{"value": v, "label": l} for v, l in VIEWS if ("view", v) in used]},
            {"key": "date", "label": "Date", "values": [{"value": d, "label": d} for d in sorted(dates)]},
            {"key": "set", "label": "Set", "values": [{"value": "curated", "label": "Release captures"}, {"value": "play", "label": "Test sessions"}]},
        ],
        "items": items,
    }
    out = PLANS / "site/gallery.json"
    out.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    print(f"{out.relative_to(ROOT)}: {len(items)} images")


def write(name: str, data: dict) -> None:
    out = OUT / name
    out.write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{out.relative_to(ROOT)}: {data['rows']} rows, {len(data['columns'])} columns, {out.stat().st_size // 1024} KB")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    csvs = sorted(PLANS.glob("probe_*.csv"))
    if not csvs:
        print("no probe CSVs in plans/square_roundabouts/ (they are local); keeping the existing data files")
    for p in csvs:
        write(p.stem.replace("_", "-") + ".json", convert(p, DROP, ["dev"], {"cost", "ms", "xm"}, 200))

    crops()
    gallery()
    layouts.main()

    timings_file = ROOT / ".cache/test_timings.json"
    if timings_file.exists():
        timings = json.loads(timings_file.read_text(encoding="utf-8"))
        rows = []
        for key, tests in sorted(timings.items()):
            if not key.startswith("tests/square_roundabouts/") or key.endswith("[full]"):
                continue
            file = key.split("/")[-1].removesuffix(".lua").removeprefix("test_")
            rows += [{"file": file, "test": name, "seconds": f"{secs:.3f}"} for name, secs in tests.items()]
        modified = dt.datetime.fromtimestamp(timings_file.stat().st_mtime).date().isoformat()
        write("tests.json", table(rows, ["file", "test", "seconds"], "test_timings.json", modified, num={"seconds"}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
