# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Render Organic Towns planner previews as SVG (dev tool, nothing shipped).

Runs the pure planner modules of mods/square_organic_towns (content/organic_towns/*.lua) in Lua 5.2 (doubles
only, like the game) through tools/ot_preview.lua: synthetic terrains (flat, hillside, river, coast) x style
cases (NA grid, EU organic, MED hill, JP dense, Nordic, MED ensanche), each grown for N increments from an
empty town at (0, 0). Writes plans/square_organic_towns/svg/<style>_<terrain>.svg and svg/previews.json, the
manifest the mod site's street-plan section reads (site/, generic "image-grid" kind: filters, groups and a
style x terrain matrix from these facets).

Edges are coloured by increment (dark = first, light = last) and sized by street class; curved edges are drawn
from their Hermite tangents. Background: terrain height (grey) and water (blue).

Env OT_PREVIEW_OUT=<dir> writes there instead of plans/square_organic_towns/svg (scratch comparisons).

Usage: uv run tools/ot_preview.py [-n INCREMENTS] [--style ID ...] [--terrain ID ...] [--town N] [--even]
       [--shape ID|all ...] [--core] [--round] [--max-edges N] [--run-year Y]
--shape grows each style in that town shape (ot_shape) from a vanilla core with dead-end joins, as in game, and
writes svg/shapes/<style>_<shape>_<terrain>.svg; --core does the same for the seeded shape.
Every run rewrites previews.json from all the SVGs in the folder (--manifest: only that, no rendering).
"""

from __future__ import annotations

import argparse
import html
import importlib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT  # noqa: E402

LuaRuntime = importlib.import_module("lupa.lua" + os.environ.get("TEALRT_LUA", "52")).LuaRuntime

MOD_ID = "square_organic_towns"
CONTENT = MODS_DIR / MOD_ID / "content"
OUT_DIR = Path(os.environ["OT_PREVIEW_OUT"]) if os.environ.get("OT_PREVIEW_OUT") else ROOT / "plans" / MOD_ID / "svg"
DRIVER = Path(__file__).with_name("ot_preview.lua")
SIZE = 900  # px

WIDTH = {"main": 7.0, "large": 8.5, "medium": 4.5, "small": 2.6, "xsmall": 2.1}


def make_runtime() -> object:
    lua = LuaRuntime(unpack_returned_tuples=True)
    loader = lua.eval(
        """
        function(read)
          local loaded = {}
          return function(path)
            if loaded[path] == nil then
              local src, name = read(path)
              local chunk, err = load(src, "@" .. name)
              if not chunk then error(err) end
              loaded[path] = chunk()
            end
            return loaded[path]
          end
        end
        """
    )

    def read(path: str):
        prefix = MOD_ID + "::/"
        if not path.startswith(prefix):
            raise RuntimeError(f"ug_require outside {MOD_ID}: {path}")
        file = CONTENT / path[len(prefix):]
        return file.read_text(encoding="utf-8"), str(file.relative_to(ROOT))

    lua.globals().ug_require = loader(read)
    return lua


def colour(k: int, n: int) -> str:
    if k <= 0:
        return "#8a8f94"  # the vanilla core (--core / --shape runs)
    t = 0.0 if n <= 1 else (k - 1) / (n - 1)
    # dark teal -> orange
    a, b = (20, 90, 110), (240, 150, 40)
    r, g, bl = (round(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return f"#{r:02x}{g:02x}{bl:02x}"


def lua_list(t) -> list:
    return [t[i] for i in range(1, len(t) + 1)]


def render(d) -> str:
    raster = d["raster"]
    half, n = raster["half"], raster["n"]
    scale = SIZE / (2 * half)

    def px(x: float, y: float) -> tuple[float, float]:
        return (x + half) * scale, (half - y) * scale  # north up

    cells = lua_list(raster["cells"])
    heights = [c[1] for c in cells if c[2] == 0]
    lo, hi = (min(heights), max(heights)) if heights else (0, 1)
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">']
    cw = SIZE / n
    for idx, c in enumerate(cells):
        i, j = idx % n, idx // n
        x, y = i * cw, SIZE - (j + 1) * cw
        if c[2] == 1:
            fill = "#7fb3d5"
        else:
            t = 0.0 if hi <= lo else (c[1] - lo) / (hi - lo)
            v = round(238 - 70 * t)
            fill = f"rgb({v},{v - 4},{v - 14})"
        out.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{cw + 0.6:.1f}" height="{cw + 0.6:.1f}" fill="{fill}"/>')
    # 100 m grid ticks
    for k in range(-int(half) // 100 * 100, int(half) + 1, 100):
        a = px(k, 0)[0]
        out.append(f'<line x1="{a:.1f}" y1="0" x2="{a:.1f}" y2="{SIZE}" stroke="#000" stroke-opacity="0.04"/>')
        b = px(0, k)[1]
        out.append(f'<line x1="0" y1="{b:.1f}" x2="{SIZE}" y2="{b:.1f}" stroke="#000" stroke-opacity="0.04"/>')
    edges = lua_list(d["edges"])
    ninc = int(d["increments"])
    order = sorted(edges, key=lambda e: -WIDTH.get(e[9], 2))
    for e in order:
        x0, y0, x1, y1, t0x, t0y, t1x, t1y, cls, inc = (e[i] for i in range(1, 11))
        p0, p3 = px(x0, y0), px(x1, y1)
        p1 = px(x0 + t0x / 3, y0 + t0y / 3)
        p2 = px(x1 - t1x / 3, y1 - t1y / 3)
        w = WIDTH.get(cls, 2.0) * scale * 1.6
        out.append(
            f'<path d="M{p0[0]:.1f},{p0[1]:.1f} C{p1[0]:.1f},{p1[1]:.1f} {p2[0]:.1f},{p2[1]:.1f} {p3[0]:.1f},{p3[1]:.1f}" '
            f'fill="none" stroke="{colour(int(inc), ninc)}" stroke-width="{max(w, 1.0):.2f}" stroke-linecap="round"/>'
        )
    for nd in lua_list(d["nodes"]):
        if nd[4] == 1:
            x, y = px(nd[2], nd[3])
            out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="2.2" fill="#c0392b"/>')
    c = px(d["centre"][1], d["centre"][2])
    out.append(f'<circle cx="{c[0]:.1f}" cy="{c[1]:.1f}" r="5" fill="none" stroke="#000" stroke-width="1.5"/>')
    for gr in lua_list(d["greens"] or {}):
        x, y = px(gr[1], gr[2])
        rr = abs(px(gr[1] + gr[3], gr[2])[0] - x)
        stroke = "#1e8449" if gr[4] == 1 else "#7dcea0"
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{rr:.1f}" fill="#abebc6" fill-opacity="0.35" stroke="{stroke}" '
                   f'stroke-dasharray="4,3"/>')
    for h in lua_list(d["hotspots"]):
        x, y = px(h[1], h[2])
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="9" fill="none" stroke="#c0392b" stroke-dasharray="3,2"/>')
    for s in lua_list(d["stations"]):
        x, y = px(s[1], s[2])
        out.append(f'<rect x="{x - 7:.1f}" y="{y - 4:.1f}" width="14" height="8" fill="#8e44ad"/>')
    lines = [
        f'{d["label"]} ({d["style"]}){" / outer " + d["outer"] if d["outer"] else ""}',
        f'region {d["region"]}, era {d["era"]}, axis {d["axis"]:.1f} deg ({d["axisSource"]})',
        f'{len(edges)} edges in {ninc} increments; terrain slope {d["meanSlope"] * 100:.1f} %, '
        f'water {d["waterFraction"] * 100:.0f} % {d["water"]}',
        f'{"EVEN (irregular growth off): " if d["even"] else "metrics: "}{d["metrics"]}',
        f'town shape {d["shape"]} ({d["shapeWhy"]}); {d["look"]}',
        f'style why: {d["styleWhy"]}; streets {d["hierarchy"]}; mix large/medium/small % {d["mix"]}',
    ]
    if d["second"]:
        x, y = px(d["second"][1], d["second"][2])
        out.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="7" fill="none" stroke="#2e86c1" stroke-width="2"/>')
    out.append(f'<rect x="8" y="8" width="{SIZE - 16}" height="116" fill="#fff" fill-opacity="0.85" rx="4"/>')
    for i, t in enumerate(lines):
        out.append(
            f'<text x="16" y="{28 + i * 18}" font-family="Helvetica, Arial, sans-serif" font-size="14">{html.escape(t)}</text>'
        )
    out.append(
        f'<text x="{SIZE - 12}" y="{SIZE - 12}" text-anchor="end" font-family="Helvetica, Arial, sans-serif" '
        f'font-size="12" fill="#333">grid 100 m; red dots = dead ends; dashed circles = hotspots; green = meadows (dark rim: crescent)</text>'
    )
    out.append("</svg>")
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("-n", type=int, default=16, help="increments per town (default 16)")
    ap.add_argument("--style", action="append", help="style case id (repeatable; default all)")
    ap.add_argument("--terrain", action="append", help="terrain id (repeatable; default all)")
    ap.add_argument("--town", type=int, default=1, help="town id (seed), default 1")
    ap.add_argument("--even", action="store_true", help="irregular growth off (writes <style>_<terrain>_even.svg)")
    ap.add_argument("--shape", action="append", help="town shape id (repeatable; 'all' = every shape; writes "
                    "shapes/<style>_<shape>_<terrain>.svg); default: the seeded pick")
    ap.add_argument("--core", action="store_true", help="start from a vanilla town core and join at dead ends only "
                    "(as in game); default with --shape")
    ap.add_argument("--site", action="append", help="Automatic style from the site (ot_site) for this region (EU, US, "
                    "MED, JP, NORDIC; repeatable): every terrain, towns --town..--town+--towns-1, writes "
                    "site/<region>_<terrain>_t<N>.svg")
    ap.add_argument("--round", action="store_true", help="with --shape / --core: start from a round core as the game "
                    "makes it (~70 edges) instead of the small grid; writes *_round.svg")
    ap.add_argument("--max-edges", type=int, default=None, help="edges per increment (default the planner's 24; in game 18)")
    ap.add_argument("--run-year", type=int, default=None, help="year for the style cases (e.g. 2020 as the showcase)")
    ap.add_argument("--towns", type=int, default=3, help="towns per terrain with --site (default 3)")
    ap.add_argument("--year", type=int, default=1970, help="year with --site (default 1970)")
    ap.add_argument("--manifest", action="store_true", help="only rewrite previews.json from the SVGs in the folder")
    args = ap.parse_args()
    lua = make_runtime()
    drv = lua.execute(DRIVER.read_text(encoding="utf-8"))
    if args.manifest:
        write_manifest(drv)
        return
    styles = args.style or lua_list(drv["STYLE_IDS"])
    terrains = args.terrain or lua_list(drv["TERRAIN_IDS"])
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    names = []
    shapes = args.shape or [None]
    if "all" in shapes:
        shapes = lua_list(drv["SHAPE_IDS"])
    for region in args.site or []:
        (OUT_DIR / "site").mkdir(exist_ok=True)
        for t in terrains:
            for town in range(args.town, args.town + args.towns):
                d = drv["run"](None, t, args.n, town, False, None, True, region, args.year)
                name = f"site/{region.lower()}_{t}_t{town}.svg"
                (OUT_DIR / name).write_text(render(d), encoding="utf-8")
                print(f"wrote {name}  {d['style']} ({d['styleWhy']}) {len(d['edges'])} edges")
    if args.site:
        write_manifest(drv)
        return
    for s in styles:
        for t in terrains:
            for sh in shapes:
                core = args.core or sh is not None
                d = drv["run"](s, t, args.n, args.town, args.even, sh, core, None, None, args.round, args.max_edges,
                               args.run_year)
                if sh is not None:
                    (OUT_DIR / "shapes").mkdir(exist_ok=True)
                    name = f"shapes/{s.lower()}_{sh}_{t}{'_round' if args.round else ''}.svg"
                else:
                    name = f"{s.lower()}_{t}{'_even' if args.even else ''}{'_core' if core else ''}.svg"
                (OUT_DIR / name).write_text(render(d), encoding="utf-8")
                names.append((s, t, name))
                print(f"wrote {name}  {len(d['edges'])} edges, {d['increments']} increments, mix={d['mix']}, "
                      f"{d['metrics']}; {d['shape']}; {d['look']}")
    write_manifest(drv)


# ---- previews.json: what each SVG shows, parsed from the file names with the driver's ids (so files of earlier runs
# are described too). The site's image-grid kind turns the facets into filters, groups and a matrix.
SETS = [("styles", "Style cases"), ("shapes", "Town shapes"), ("site", "Automatic style (site)")]
VARIANTS = [("plain", "irregular growth"), ("even", "even (irregular growth off)"), ("core", "from a town core"),
            ("even_core", "even, from a town core"), ("round", "round core"), ("grid", "small grid core")]
STYLE_LABEL = {"NA": "NA", "EU": "EU", "MED": "MED", "JP": "JP"}


def _style_label(sid: str) -> str:
    return " ".join(STYLE_LABEL.get(w, w.capitalize() if i == 0 else w.lower()) for i, w in enumerate(sid.split("_")))


def write_manifest(drv) -> Path:
    styles = sorted(lua_list(drv["STYLE_IDS"]), key=len, reverse=True)  # longest first: na_grid before na
    terrains = lua_list(drv["TERRAIN_IDS"])
    shapes = lua_list(drv["SHAPE_IDS"])
    items = []
    for p in sorted(OUT_DIR.rglob("*.svg")):
        rel = p.relative_to(OUT_DIR).as_posix()
        folder, stem = (rel.split("/")[0] if "/" in rel else ""), p.stem
        it: dict = {"file": rel, "set": folder or "styles"}
        if folder == "site":
            region, terrain, town = (stem.rsplit("_", 2) + ["", "", ""])[:3]
            it.update(region=region.upper(), terrain=terrain, town=town.lstrip("t"),
                      title=f"{region.upper()} · {terrain} · town {town.lstrip('t')}")
        else:
            sid = next((x for x in styles if stem.upper().startswith(x + "_")), None)
            if sid is None:
                continue  # not a preview of this tool
            rest = stem[len(sid) + 1:].split("_")
            it["style"] = sid
            if folder == "shapes":
                sh = rest[0] if rest and rest[0] in shapes else None
                if sh is None:
                    continue
                it["shape"], rest = sh, rest[1:]
            it["terrain"] = rest[0] if rest and rest[0] in terrains else "?"
            var = "_".join(rest[1:])
            it["variant"] = var or ("grid" if folder == "shapes" else "plain")
            bits = [_style_label(sid)] + ([it["shape"]] if folder == "shapes" else []) + [it["terrain"]]
            label = dict(VARIANTS).get(it["variant"], it["variant"])
            it["title"] = " · ".join(bits) + (f" ({label})" if it["variant"] != "plain" else "")
        items.append(it)
    used = lambda k: {it.get(k) for it in items if k in it}  # noqa: E731
    facets = [
        {"key": "set", "label": "Set", "values": [{"value": v, "label": lab} for v, lab in SETS if v in used("set")]},
        {"key": "style", "label": "Style",
         "values": [{"value": x, "label": _style_label(x)} for x in lua_list(drv["STYLE_IDS"]) if x in used("style")]},
        {"key": "terrain", "label": "Terrain", "values": [{"value": x, "label": x} for x in terrains if x in used("terrain")]},
        {"key": "variant", "label": "Variant", "values": [{"value": v, "label": lab} for v, lab in VARIANTS if v in used("variant")]},
        {"key": "shape", "label": "Town shape", "values": [{"value": x, "label": x} for x in shapes if x in used("shape")]},
        {"key": "region", "label": "Region", "values": [{"value": x, "label": x} for x in sorted(used("region"))]},
    ]
    out = OUT_DIR / "previews.json"
    out.write_text(json.dumps({"generator": "tools/ot_preview.py", "facets": [f for f in facets if f["values"]],
                               "items": items}, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {out} ({len(items)} previews)")
    return out


if __name__ == "__main__":
    main()
