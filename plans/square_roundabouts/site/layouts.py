# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Plan drawings of every layout Roundabouts & Interchanges builds, for the site's layout wall (generic image-grid kind).

Runs the mod's own pure geometry modules (mods/square_roundabouts/content/infrastructure/street_construction/*.lua,
no api.*) in Lua 5.4 (lupa) with the menu params of each sweep below, samples every edge's Hermite curve and draws the
roads as plan bands (band width = the road's width, bridges drawn above with a casing), the islands as faces and the
island trees / fountain as dots. Data only: each SVG is an image, and the facet manifest layouts.json says what it shows
(entry, sweep, row / column values for the image-grid matrix). Nothing here reaches the game.

Writes plans/square_roundabouts/site/layouts/<sweep>-<row>-<col>.svg and plans/square_roundabouts/site/layouts.json.

Usage: uv run plans/square_roundabouts/site/layouts.py      (build_data.py runs it too)
"""

from __future__ import annotations

import json
import math
import shutil
from pathlib import Path

import lupa.lua54 as lupa

ROOT = Path(__file__).resolve().parents[3]
CONTENT = ROOT / "mods/square_roundabouts/content"
SITE = ROOT / "plans/square_roundabouts/site"
OUT = SITE / "layouts"

LUA = r"""
local CONTENT = ...
local cache = {}
function ug_require(p)
  local rel = p:gsub("^square_roundabouts::", "")
  if cache[rel] == nil then
    local f = assert(loadfile(CONTENT .. rel, "t", _ENV))
    cache[rel] = f()
  end
  return cache[rel]
end
function _(s) return s end
local quiet = function() end
log = { verbose = quiet, message = quiet, warning = quiet, error = quiet }

local D = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(D .. "square_roundabouts_geometry.lua")
local mods = {
  roundabout = { m = geom },
  magic = { m = ug_require(D .. "square_roundabouts_magic.lua") },
  channel = { m = ug_require(D .. "square_roundabouts_channel.lua") },
  interchange = { m = ug_require(D .. "square_roundabouts_interchange.lua") },
  highway = { m = ug_require(D .. "square_roundabouts_highway.lua") },
}

local function hermite(e, s)
  local s2, s3 = s * s, s * s * s
  local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
  local p = {}
  for i = 1, 3 do p[i] = h00 * e.p0[i] + h10 * e.t0[i] + h01 * e.p1[i] + h11 * e.t1[i] end
  return p
end

local function enc(v)
  local t = type(v)
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    return string.format("%.2f", v)
  elseif t == "string" then return string.format("%q", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    if #v > 0 or next(v) == nil then
      local out = {}
      for i = 1, #v do out[i] = enc(v[i]) end
      return "[" .. table.concat(out, ",") .. "]"
    end
    local out = {}
    for k, x in pairs(v) do out[#out + 1] = string.format("%q", tostring(k)) .. ":" .. enc(x) end
    return "{" .. table.concat(out, ",") .. "}"
  end
  return "null"
end

--- Builds one layout and returns it as JSON: lists (role, half width, bridge, polylines) and island faces / models.
function dump(entry, params)
  local m = mods[entry].m
  local spec
  if entry == "roundabout" then spec = geom.readParams(params)
  elseif entry == "highway" then spec = m.specFor(nil, params)
  else spec = m.readParams(params) end
  local ok, built = pcall(m.build, spec)
  if not ok or not built then return enc({ error = tostring(built) }) end
  local lists = {}
  for _, l in ipairs(built.lists or {}) do
    local lines = {}
    for _, e in ipairs(l.edges) do
      local pts = {}
      local n = 10
      for k = 0, n do
        local p = hermite(e, k / n)
        pts[#pts + 1] = { p[1], p[2], p[3] or 0 }
      end
      lines[#lines + 1] = pts
    end
    lists[#lists + 1] = { role = l.role or "road", hw = l.halfWidth or 4, bridge = l.edgeType == "BRIDGE", lines = lines,
      template = l.template or "" }
  end
  local faces, models = {}, {}
  if built.island then
    for _, f in ipairs(built.island.faces or {}) do
      local pts = {}
      for _, p in ipairs(f.outline) do pts[#pts + 1] = { p[1], p[2] } end
      faces[#faces + 1] = { fill = f.fill or "", pts = pts }
    end
    for _, md in ipairs(built.island.models or {}) do models[#models + 1] = { id = md.id or "", x = md.x, y = md.y } end
  end
  return enc({ lists = lists, faces = faces, models = models, radius = built.radius })
end
"""

# --- sweeps: (sweep id, entry, title, row facet values, col facet values, params(row, col)) -------------------------
# Param values are the menus' 1-based option indices (the .con.lua button rows).
RB = {"shape": "sqrb_shape", "lanes": "sqrb_lanes", "scale": "sqrb_radius_size", "arms": "sqrb_arms",
      "splitter": "sqrb_splitter", "centre": "sqrb_centre", "island": "sqrb_island", "armType": "sqrb_arm_type"}
SCALES5 = [("xs", "XS"), ("s", "S"), ("m", "M"), ("l", "L"), ("xl", "XL")]
SHAPES = [("round", "Round"), ("oval-125", "Oval 1.25:1"), ("oval-15", "Oval 1.5:1"), ("oval-175", "Oval 1.75:1"), ("oval-2", "Oval 2:1")]
LANES = [("lanes-1", "1 ring lane"), ("lanes-2", "2 ring lanes"), ("lanes-4", "4 ring lanes")]
ARMS = [("arms-3t", "3 arms (T)"), ("arms-3y", "3 arms (Y)"), ("arms-4", "4 arms"), ("arms-5", "5 arms"), ("arms-6", "6 arms"), ("arms-0", "No arms")]
CENTRE = [("centre-none", "Nothing through"), ("centre-road", "Road through"), ("centre-tram", "Tram line through"), ("centre-lights", "Road + lights")]
SPLIT = [("split-off", "No splitters"), ("split-on", "Splitter islands")]
ISLANDS = [("island-none", "No island"), ("island-grass", "Grass"), ("island-trees", "Grass and trees"), ("island-fountain", "Fountain"), ("island-paved", "Paved")]
ARMROADS = [("road-town-s", "Small town road"), ("road-town-m", "Medium town road"), ("road-town-l", "Large town road"),
            ("road-country-s", "Small country road"), ("road-country-m", "Medium country road"), ("road-country-l", "Large country road")]
MAGIC_LANES = [("mini-1", "1-lane minis"), ("mini-2", "2-lane minis")]
CH_LAYOUT = [("t", "T junction"), ("x", "X junction")]
CH_SLIPS = [("slips-near", "Slips on every corner"), ("slips-main", "Slips from the main road"), ("slips-none", "No slips")]
IX_LAYOUT = [("two-bridge", "Two-bridge ring"), ("dumbbell", "Dumbbell"), ("peanut", "Peanut")]
IX_SIZE = [("s", "S"), ("m", "M"), ("l", "L"), ("xl", "XL")]
IX_LEVEL = [("ring-over", "Ring over the highway"), ("highway-over", "Highway over the ring")]
HX_TYPES = [("a4", "Parclo A4"), ("b4", "Parclo B4"), ("a2", "Parclo A2"), ("b2", "Parclo B2"), ("ab2", "Parclo AB2"), ("diamond", "Diamond")]
HX_SCALE = [("scale-1", "Scale S"), ("scale-2", "Scale M"), ("scale-3", "Scale L")]
HX_RAMP = [("ramp-1", "Short ramps"), ("ramp-2", "Medium ramps"), ("ramp-3", "Long ramps")]
HX_LEVEL = [("road-over", "Road over the highway"), ("hx-highway-over", "Highway over the road")]


def idx(values, v):
    return [k for k, _ in values].index(v) + 1


GRASSY = {RB["island"]: 3}  # grass and trees: the island shows in the drawing
SWEEPS = [
    ("shape-scale", "roundabout", "Shape × scale", SHAPES, SCALES5,
     lambda r, c: {**GRASSY, RB["shape"]: idx(SHAPES, r), RB["scale"]: idx(SCALES5, c), RB["arms"]: 3}),
    ("lanes-arms", "roundabout", "Ring lanes × arms", LANES, ARMS,
     lambda r, c: {**GRASSY, RB["lanes"]: idx(LANES, r), RB["arms"]: idx(ARMS, c), RB["scale"]: 3}),
    ("centre-splitter", "roundabout", "Through the center × splitter islands", CENTRE, SPLIT,
     lambda r, c: {**GRASSY, RB["centre"]: idx(CENTRE, r), RB["splitter"]: idx(SPLIT, c), RB["scale"]: 4, RB["arms"]: 3}),
    ("island-shape", "roundabout", "Center island × shape", ISLANDS, [SHAPES[0], SHAPES[2], SHAPES[4]],
     lambda r, c: {RB["island"]: idx(ISLANDS, r), RB["shape"]: idx(SHAPES, c), RB["scale"]: 4, RB["arms"]: 3}),
    ("arm-road-arms", "roundabout", "Arm road × arms", ARMROADS, [ARMS[0], ARMS[2], ARMS[4]],
     lambda r, c: {**GRASSY, RB["armType"]: idx(ARMROADS, r), RB["arms"]: idx(ARMS, c), RB["scale"]: 3}),
    ("magic", "magic", "Magic Roundabout: minis × size", MAGIC_LANES, SCALES5,
     lambda r, c: {"sqrb_magic_lanes": idx(MAGIC_LANES, r), "sqrb_magic_size": idx(SCALES5, c), "sqrb_island": 3}),
    ("channel", "channel", "Channelized Junction: layout × scale", CH_LAYOUT, SCALES5,
     lambda r, c: {"sqrb_ch_layout": idx(CH_LAYOUT, r), "sqrb_ch_scale": idx(SCALES5, c), "sqrb_ch_island": 2}),
    ("channel-slips", "channel", "Channelized Junction: slip lanes × layout", CH_SLIPS, CH_LAYOUT,
     lambda r, c: {"sqrb_ch_slips": idx(CH_SLIPS, r), "sqrb_ch_layout": idx(CH_LAYOUT, c), "sqrb_ch_scale": 3, "sqrb_ch_island": 2}),
    ("interchange", "interchange", "Roundabout Interchange: layout × size", IX_LAYOUT, IX_SIZE,
     lambda r, c: {"sqrb_ix_layout": idx(IX_LAYOUT, r), "sqrb_ix_radius_size": idx(IX_SIZE, c), "sqrb_island": 3}),
    ("interchange-level", "interchange", "Roundabout Interchange: layout × level", IX_LAYOUT, IX_LEVEL,
     lambda r, c: {"sqrb_ix_layout": idx(IX_LAYOUT, r), "sqrb_ix_level": idx(IX_LEVEL, c), "sqrb_ix_radius_size": 2, "sqrb_island": 3}),
    ("highway", "highway", "Highway interchanges: type × scale", HX_TYPES, HX_SCALE,
     lambda r, c: {"sqrb_hx_type": idx(HX_TYPES, r), "sqrb_hx_scale": idx(HX_SCALE, c)}),
    ("highway-ramps", "highway", "Highway interchanges: type × ramp length", HX_TYPES, HX_RAMP,
     lambda r, c: {"sqrb_hx_type": idx(HX_TYPES, r), "sqrb_hx_ramp": idx(HX_RAMP, c)}),
    ("highway-level", "highway", "Highway interchanges: type × level", HX_TYPES, HX_LEVEL,
     lambda r, c: {"sqrb_hx_type": idx(HX_TYPES, r), "sqrb_hx_level": idx(HX_LEVEL, c)}),
]
ENTRIES = [("roundabout", "Better Roundabouts"), ("magic", "Magic Roundabout"), ("channel", "Channelized Junction"),
           ("interchange", "Roundabout Interchange"), ("highway", "Highway interchanges")]

# --- drawing ---------------------------------------------------------------------------------------------------------
GROUND = "#e6e1d3"
CASING = {"highway": "#4a4f57", "ramps": "#4a4f57"}
FILL = {"highway": "#9aa1ab", "ramps": "#b4b9c0", "ring": "#c9a24a", "legs": "#c9a24a", "through": "#8f969f"}
ROAD_FILL = "#a7adb5"
ROAD_CASING = "#5a5f66"
FACE = {"grass": "#9cc27a", "paving": "#cfc6b4"}
TREE = "#4f7d3a"
WATER = "#5b9bd5"
MARGIN = 10.0
SIZE = 640  # SVG viewBox width / height in px


def face_color(fill: str) -> str:
    f = fill.lower()
    if "grass" in f or "green" in f or "lawn" in f:
        return FACE["grass"]
    return FACE["paving"]


def model_color(mid: str) -> str:
    m = mid.lower()
    return WATER if "fountain" in m else TREE


def svg(layout: dict, title: str, span: float) -> str:
    """One plan drawing. span = metres shown across (the same for every drawing of a sweep, so sizes compare)."""
    lists = layout["lists"]
    xs = [p[0] for l in lists for line in l["lines"] for p in line]
    ys = [p[1] for l in lists for line in l["lines"] for p in line]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k = SIZE / span

    def pt(p):
        return f"{(p[0] - cx) * k + SIZE / 2:.1f},{SIZE / 2 - (p[1] - cy) * k:.1f}"

    def band(l, color, extra):
        w = max(0.8, (2 * l["hw"] + extra) * k)
        d = " ".join("M" + " L".join(pt(p) for p in line) for line in l["lines"])
        return f'<path d="{d}" stroke="{color}" stroke-width="{w:.1f}"/>'

    def z(l):
        zs = [p[2] for line in l["lines"] for p in line]
        return (sum(zs) / len(zs) if zs else 0) + (100 if l["bridge"] else 0)

    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">',
           f"<title>{title}</title>", f'<rect width="{SIZE}" height="{SIZE}" fill="{GROUND}"/>',
           '<g fill="none" stroke-linecap="butt" stroke-linejoin="round">']
    order = sorted(lists, key=z)
    ground = [l for l in order if z(l) < 50 and max((p[2] for line in l["lines"] for p in line), default=0) < 3]
    raised = [l for l in order if l not in ground]
    for group in (ground, raised):
        # casings of the whole level first, then the fills: junctions of one level merge cleanly
        for l in group:
            out.append(band(l, CASING.get(l["role"], ROAD_CASING), 1.6))
        for l in group:
            out.append(band(l, FILL.get(l["role"], ROAD_FILL), 0))
    out.append("</g>")
    for f in layout["faces"]:
        if len(f["pts"]) >= 3:
            out.append(f'<polygon points="{" ".join(pt(p) for p in f["pts"])}" fill="{face_color(f["fill"])}"/>')
    for m in layout["models"]:
        if m.get("x") is None:
            continue
        r = max(1.5, (4.0 if "fountain" in m["id"].lower() else 2.2) * k)
        out.append(f'<circle cx="{(m["x"] - cx) * k + SIZE / 2:.1f}" cy="{SIZE / 2 - (m["y"] - cy) * k:.1f}" r="{r:.1f}" fill="{model_color(m["id"])}"/>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def extent(layout: dict) -> float:
    lists = layout["lists"]
    xs = [p[0] for l in lists for line in l["lines"] for p in line]
    ys = [p[1] for l in lists for line in l["lines"] for p in line]
    pad = max((l["hw"] for l in lists), default=4) + MARGIN
    return max(max(xs) - min(xs), max(ys) - min(ys)) + 2 * pad


def main() -> int:
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(LUA, str(CONTENT))
    dump = lua.globals().dump
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    items, failed = [], []
    rows_seen, cols_seen = {}, {}
    for sweep, entry, title, rows, cols, params in SWEEPS:
        built = {}
        for r, rl in rows:
            for c, cl in cols:
                p = lua.table_from(params(r, c))
                data = json.loads(dump(entry, p))
                if "error" in data or not data.get("lists"):
                    failed.append(f"{sweep} {r} {c}: {data.get('error', 'no roads')}")
                    continue
                built[(r, c)] = (data, rl, cl)
        if not built:
            continue
        # one scale per sweep, so the drawings of a sweep compare in size
        span = max(extent(d) for d, _, _ in built.values())
        for (r, c), (data, rl, cl) in built.items():
            name = f"{sweep}-{r}-{c}.svg"
            cap = f"{dict(ENTRIES)[entry]}: {rl}, {cl}"
            (OUT / name).write_text(svg(data, cap, span), encoding="utf-8")
            items.append({"file": f"layouts/{name}", "title": cap, "entry": entry, "sweep": sweep, "row": r, "col": c,
                          "span": str(round(span))})
            rows_seen.setdefault(r, rl)
            cols_seen.setdefault(c, cl)
    manifest = {
        "facets": [
            {"key": "entry", "label": "Menu entry", "values": [{"value": v, "label": l} for v, l in ENTRIES if any(i["entry"] == v for i in items)]},
            {"key": "sweep", "label": "Sweep", "values": [{"value": s[0], "label": s[2]} for s in SWEEPS if any(i["sweep"] == s[0] for i in items)]},
            {"key": "row", "label": "Variant", "values": [{"value": v, "label": l} for v, l in rows_seen.items()]},
            {"key": "col", "label": "Setting", "values": [{"value": v, "label": l} for v, l in cols_seen.items()]},
        ],
        "items": items,
    }
    (SITE / "layouts.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    size = sum(f.stat().st_size for f in OUT.glob("*.svg"))
    print(f"{(SITE / 'layouts.json').relative_to(ROOT)}: {len(items)} layouts in {len(SWEEPS)} sweeps, {size // 1024} KB of SVG")
    for f in failed:
        print("  not built:", f)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
