# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Export Organic Towns' name data for the Name lab on the mod site (site/, section "name-lab": the React island in
site/src/mods/square_organic_towns/namelab/, which fetches this file).

Runs the mod's own Lua (lupa, Lua 5.2 like tools/ot_preview.py; ug_require maps to mods/square_organic_towns/content)
and writes names/data.json (gitignored: it holds the game's own town lists; the site build publishes it), plus the
same data as names/data.js (window.NAMEDATA) for the old lab page (names/index.html) until it is retired:

    lang      ot_placename_lang.lua per generator language, as the raw tables (the lab parses the spec / gen / affix
              lines with its JS port of ot_placename's parser, so edited lines parse the same way)
    parsed    Lua's parse of every entry (text, kind / form, tags, flags), for the lab's port check (check_port.mjs)
    pn        ot_placename: TAGS, SPECIES, PARENT, SPEC, CONTRA, LANGS, GEN_OF_CLS, CLS_OF_GEN and every numeric constant
    nw        ot_namewords (2026-10-14, "Names from the map's shape"): the word budget's lexicons (WORDS, WORDS_OF, SOFT),
              its constants and RARE_EXEMPT, for the port's budget and rarity
    block     the blocklists (BLOCK_SUB / BLOCK_WORD / BLOCK_CJK)
    towns     the game's town lists per generator language (.cache/game/base/content/names/<path>/<dir>/towns.lua,
              the folders ot_names.LISTS classifies as that language): the Remix mode's training set and `real`
    stop      ot_stopname.LANG (stop-name parts per list language) and THEMES
    presets   the lab's site presets (weights per tag; lab content, not mod data)
    golden    ot_placename.assign run in Lua on synthetic maps (every preset, per language; golden53 the same with the
              s53 rules, NEXT_PHASE_BRIEF 60): the lab re-runs them with
              its TypeScript port (namelab/gen.ts) and shows whether the port gives the same names
    map       the NAME lines of one map load of a game log: old -> new, parts, tags, river / lake, dialect, read

Usage (from the repo root):
    uv run plans/square_organic_towns/names/export_names.py                    # map from the live stdout.txt
    uv run plans/square_organic_towns/names/export_names.py --session last-sqot   # an archived session (make logs-list)
    uv run plans/square_organic_towns/names/export_names.py --log /path/to/stdout.txt [--seed-text a] [--no-map]

--session takes what `make logs` takes (a session name or prefix, live, last, last-<tag>); --log a file path. The
map load is the last one with NAME lines (--seed-text X: the load that starts at "Map seed text: X"). Rerun after
every change to the inventories or the scorer (then `node plans/square_organic_towns/names/check_port.mjs`); the
page never holds hand-copied data.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from hubconfig import CACHE_DIR, MODS_DIR  # noqa: E402

LuaRuntime = importlib.import_module("lupa.lua" + os.environ.get("TEALRT_LUA", "52")).LuaRuntime

MOD_ID = "square_organic_towns"
CONTENT = MODS_DIR / MOD_ID / "content"
NAMES_DIR = CACHE_DIR / "game" / "base" / "content" / "names"
OUT = HERE / "data.json"
SRC = ["ot_placename.lua", "ot_placename_lang.lua", "ot_stopname.lua", "ot_names.lua", "ot_rng.lua", "ot_namewords.lua",
       "ot_mapshape.lua", "ot_climate.lua"]

# Site presets (lab content): weights as ot_placename.siteTags would give them for such a site.
PRESETS = {
    "lakeside": {"lake": 1, "mere": 0.9, "edge": 0.7, "forest": 0.5, "alder": 0.6, "meadow": 0.6, "plain": 0.5},
    "wooded valley": {"valley": 1, "vale": 0.8, "forest": 0.8, "clearing": 0.9, "oak": 0.8, "beech": 0.5,
                      "river": 1, "brook": 0.9, "ford": 0.9, "bridge": 0.6},
    "clifftop": {"coast": 1, "cliff": 1, "rocky": 0.8, "headland": 0.9, "hilltop": 0.8, "hill": 0.6, "heath": 0.5},
    "plain market town": {"plain": 1, "field": 0.8, "market": 0.8, "big": 0.8, "church": 0.4},
    "island": {"island": 1, "coast": 1, "sandy": 0.8, "bay": 0.8, "spit": 1, "headland": 0.7},
    "confluence": {"river": 1, "confluence": 1, "ford": 0.6, "bridge": 0.9, "meadow": 0.8, "plain": 0.6},
    "river mouth port": {"river": 1, "mouth": 1, "coast": 0.8, "bay": 0.8, "bridge": 0.9, "market": 0.8, "big": 0.8},
    "moorland": {"moor": 0.8, "heath": 0.6, "hill": 0.6, "mountain": 0.6, "spring": 0.8, "small": 0.6},
    "fenland": {"marsh": 0.8, "fen": 0.9, "river": 1, "plain": 0.9, "meadow": 0.8, "willow": 0.7},
    "mountain pass": {"pass": 1, "mountain": 0.9, "hill": 0.8, "rock": 0.7, "pine": 0.6, "forest": 0.4, "edge": 0.7},
    "tarn hamlet": {"lake": 1, "tarn": 1, "mountain": 0.7, "hill": 0.6, "small": 0.6, "rock": 0.6},
    "gorge": {"valley": 1, "gorge": 1, "river": 1, "brook": 0.9, "rock": 0.7, "slope": 0.8, "ash": 0.6},
    "birch forest clearing": {"forest": 1, "clearing": 0.9, "birch": 0.9, "pine": 0.5, "lake": 0.0, "small": 0.6},
    "sandy bay": {"coast": 1, "sandy": 0.8, "bay": 0.8, "plain": 0.6, "field": 0.5},
    # the map survey's cue tags (ot_mapshape.townCues, 2026-10-14): what a town gets from the shape of the whole map
    "river fork": {"river": 1, "confluence": 1, "ford": 0.6, "bridge": 0.6, "plain": 0.5, "meadow": 0.5},
    "falls": {"river": 1, "falls": 1, "gorge": 0.5, "rock": 0.4, "forest": 0.4},
    "upper course": {"river": 1, "upper": 1, "slope": 0.5, "forest": 0.5, "brook": 0.6},
    "lower course": {"river": 1, "lower": 0.9, "meadow": 0.6, "plain": 0.6, "bridge": 0.7},
    "north edge": {"plain": 0.8, "field": 0.6, "north": 0.9, "dir": 0.9},
    "big lake shore": {"lake": 1, "biglake": 1, "sandy": 0.5, "edge": 0.5},
    "mountain gap": {"pass": 1, "range": 0.8, "mountain": 0.6, "rock": 0.5},
    "summit": {"summit": 0.9, "hilltop": 0.8, "peak": 1, "mountain": 0.8},
    "big bay": {"coast": 1, "bay": 1, "bigbay": 1, "sandy": 0.6},
    "narrows": {"coast": 1, "narrows": 1, "headland": 0.5},
}
# the survey's other cue facts for the golden runs of the cue presets: the river component, the compass side, the side
# of the big lake, the big bay
CUE_OF = {"river fork": {"river": 1}, "falls": {"river": 1}, "upper course": {"river": 1}, "lower course": {"river": 1},
          "north edge": {"dir": "north"}, "big lake shore": {"lake": True, "ldir": "west"}, "big bay": {"bigbay": True},
          "mountain gap": {}, "summit": {}, "narrows": {}}


def make_runtime():
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


def req(lua, name):
    return lua.globals().ug_require(f"{MOD_ID}::/organic_towns/{name}")


def py(v, depth=0):
    """A Lua value as JSON-able Python (sequences -> lists, functions dropped)."""
    if depth > 12:
        return None
    t = type(v).__name__
    if t in ("str", "int", "float", "bool") or v is None:
        return v
    if t == "bytes":
        return v.decode("utf-8", "replace")
    if t == "_LuaFunction" or callable(v) and not hasattr(v, "items"):
        return None
    try:
        items = list(v.items())
    except Exception:  # noqa: BLE001
        return None
    keys = [k for k, _ in items]
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [py(v[i], depth + 1) for i in range(1, len(keys) + 1)]
    out = {}
    for k, val in items:
        pv = py(val, depth + 1)
        if pv is not None:
            out[str(k)] = pv
    return out


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


# ------------------------------------------------------------------------------------------------ the map's NAME lines

KV = re.compile(r"(\w+)=(\S*)")


def resolve_log(o) -> Path | None:
    if o.no_map:
        return None
    if o.log:
        return Path(o.log).expanduser()
    import game_logs  # noqa: PLC0415
    store = game_logs.default_store()
    e = game_logs.resolve(store, o.session or "live")
    return e if isinstance(e, Path) else game_logs.readable_path(store, e)


def pairs_of(text: str | None) -> list:
    out = []
    for p in (text or "").split(","):
        if ":" in p:
            k, v = p.rsplit(":", 1)
            try:
                out.append([k, float(v)])
            except ValueError:
                pass
    return out


def num_or_none(v: str | None) -> float | None:
    try:
        return float(v) if v not in (None, "-") else None
    except ValueError:
        return None


def read_map(path: Path, seed_text: str | None) -> dict | None:
    import gzip  # noqa: PLC0415
    op = gzip.open if str(path).endswith(".gz") else open
    with op(path, "rt", encoding="utf-8", errors="replace") as f:
        lines = f.read().split("\n")
    loads = []  # (line index, seed text)
    for i, l in enumerate(lines):
        m = re.search(r"Map seed text: (.*)$", l)
        if m:
            loads.append((i, m.group(1).strip()))
    if not loads:
        loads = [(0, None)]
    spans = [(s, loads[k + 1][0] if k + 1 < len(loads) else len(lines), st) for k, (s, st) in enumerate(loads)]
    pick = None
    for s, e, st in spans:
        has = any("[SQOT] NAME town=" in l for l in lines[s:e])
        if seed_text is not None:
            if st == seed_text:
                pick = (s, e, st)  # the last load with that seed text
        elif has:
            pick = (s, e, st)
    if pick is None:
        return None
    s, e, st = pick
    towns, summary, industries, climate = [], None, 0, None
    for l in lines[s:e]:
        i = l.find("[SQOT] NAME town=")
        if i >= 0:
            f = dict(KV.findall(l[i + len("[SQOT] NAME "):]))
            tags = []
            for p in (f.get("tags") or "").split(","):
                if ":" in p:
                    k, v = p.split(":", 1)
                    try:
                        tags.append([k, float(v)])
                    except ValueError:
                        pass
            und = lambda v: (v or "").replace("_", " ")  # noqa: E731
            parts = (f.get("parts") or "-+-+-").split("+")
            towns.append({
                "id": f.get("town"), "old": und(f.get("old")), "new": und(f.get("new")), "src": f.get("src"),
                "parts": [und(p) if p != "-" else None for p in (parts + ["-", "-", "-"])[:3]],
                "feature": f.get("feature"), "tags": tags, "river": None if f.get("river") in (None, "-") else und(f.get("river")),
                "lake": None if f.get("lake") in (None, "-") else und(f.get("lake")), "dialect": f.get("dialect"),
                "read": f.get("read"), "score": float(f.get("score") or 0), "character": f.get("character") == "true",
                "cap": int(float(f.get("cap") or 0)),
                # (NEXT_PHASE_BRIEF 53 Part B: the survey's cues, the position and height, the shape, layer and character
                # kind: the lab's map mode reruns the real sites with the plan)
                "cue": pairs_of(f.get("cue")), "x": num_or_none(f.get("x")), "y": num_or_none(f.get("y")),
                "alt": num_or_none(f.get("alt")), "shape": f.get("shape"), "layer": f.get("layer"),
                "char": None if f.get("char") in (None, "-") else f.get("char"),
            })
        elif "[SQOT] NAME industry=" in l:
            industries += 1
        w = l.find("[SQOT] NAMES words ")
        if w >= 0:
            c = dict(KV.findall(l[w:])).get("climate")
            climate = c if c not in (None, "-") else climate
        j = l.find("[SQOT] NAMES ")
        if j >= 0 and not re.match(r"\[SQOT\] NAMES (words|shapes|survey|offshoot) ", l[j:]):
            summary = dict(KV.findall(l[j + len("[SQOT] NAMES "):]))
    return {"log": os.path.basename(str(path)), "seedText": st, "towns": towns, "industries": industries, "climate": climate,
            "summary": {k: summary.get(k) for k in ("mode", "gen", "list", "lang", "rivers", "lakes", "towns", "renamed")
                        if summary and k in summary} if summary else None}


# ------------------------------------------------------------------------------------------------ town lists

def town_lists(lua, NM, gen_of_cls) -> dict:
    out: dict[str, dict] = {}
    lists = py(NM.LISTS)
    load = lua.eval("function(src, name) local f = assert(load(src, '@' .. name)); return f() end")
    for path, L in sorted(lists.items()):
        for d, cls in sorted((L.get("cls") or {}).items()):
            g = gen_of_cls.get(cls)
            f = NAMES_DIR / path / d / "towns.lua"
            if not g or not f.is_file():
                continue
            names = [n for n in py(load(f.read_text(encoding="utf-8"), str(f))) or [] if isinstance(n, str)]
            o = out.setdefault(g, {"sources": [], "names": []})
            o["sources"].append(f"{path}/{d}")
            seen = set(o["names"])
            o["names"] += [n for n in names if n not in seen]
    return out


# ------------------------------------------------------------------------------------------------ golden runs

GOLDEN_LUA = r"""
local PN, towns_by_lang, seed, climate, year, rules = ...
local CL = ug_require("square_organic_towns::/organic_towns/ot_climate.lua")
local out = {}
for li = 1, #PN.LANGS do
  local lang = PN.LANGS[li]
  local towns = towns_by_lang[lang]
  if towns then
    local real = {}
    for i = 1, #(towns.real or {}) do real[PN.lowerAll(towns.real[i])] = true end
    local list = {}
    for i = 1, #towns.list do
      local t = towns.list[i]
      local w = {}
      for k, v in pairs(t.w) do w[k] = v end
      -- (a climate run: the climate's site tags in, the tags it never takes out, as siteTags does)
      if climate then
        for ct, cv in pairs(CL.SITE[climate] or {}) do if (w[ct] or 0) < cv then w[ct] = cv end end
        for k in pairs(w) do if CL.vetoTag(climate, k) then w[k] = nil end end
      end
      -- ranked as siteTags returns it (weights >= 0.2, x specificity)
      local ranked = {}
      for _, tag in ipairs(PN.TAGS) do
        if (w[tag] or 0) >= 0.2 then ranked[#ranked + 1] = { tag, w[tag] * (PN.SPEC[tag] or 1) } else w[tag] = nil end
      end
      table.sort(ranked, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return PN.TAG_INDEX[a[1]] < PN.TAG_INDEX[b[1]] end)
      list[i] = { id = t.id, name = t.name, x = t.x, y = t.y, w = w, ranked = ranked, character = t.character,
        cap = t.cap, river = t.river, axis = t.axis, lake = t.lake, cue = t.cue, keep = t.keep, alt = t.alt,
        ind = t.ind, facts = t.facts }
    end
    local res, st = PN.assign(list, { lang = lang, seed = seed, real = real, climate = climate, year = year, rules = rules })
    local rows = {}
    for i = 1, #res do
      local r = res[i]
      local inf = r.info
      rows[i] = { id = r.id, new = r.new, river = r.river, lake = r.lake,
        spec = inf and inf.spec or nil, gen = inf and inf.gen or nil, affix = inf and inf.affix or nil,
        score = inf and inf.score or nil, dialect = inf and inf.dialect or nil, shape = inf and inf.shape or nil }
    end
    local sf = {}
    for _, e in ipairs(PN.shapeFields(st)) do sf[#sf + 1] = e[1] .. "=" .. tostring(e[2]) end
    out[lang] = { rows = rows, rivers = st.rivers, lakes = st.lakes, satellite = st.satellite, shapes = table.concat(sf, " ") }
  end
end
return out
"""


IND_FAMS = ["fish", "oil", "clay", "coal", "stone", "timber", "farm", "iron", "chem"]


def golden(lua, PN, towns: dict, seed: int, rules: str | None = None) -> dict:
    """Synthetic maps per language (every preset twice, some character towns, a river chain and a lake pair); rules = None
    (the mod's default, NEXT_PHASE_BRIEF 61 "s61"), "s60" or "s53" (the earlier rules, the lab's comparison)."""
    names = list(PRESETS)
    base = []
    tid = 1000
    for k, pname in enumerate(names * 2):
        w = dict(PRESETS[pname])
        ch = k % 7 == 3
        if ch:
            w["character"], w["church"] = 1, max(w.get("church", 0), 0.4)
        if k % 5 == 4:
            w["small"] = 0.6
        tid += 7
        river = w.get("river", 0) > 0
        x, y = (k % 6) * 5200.0, (k // 6) * 4700.0
        if river:  # river towns in a row along x: one river system per row
            y = 30000.0 + (k % 3) * 9000.0
            x = (k // 3) * 3000.0
        if pname == "lakeside" or pname == "tarn hamlet":
            x, y = 50000.0 + k * 900.0, 50000.0
        # (NEXT_PHASE_BRIEF 53 Part B: one character town of a kind, the strong-characters hook; NEXT_PHASE_BRIEF 61: the
        # s61 kinds, deep forest, secluded, coastal, and a waterfront)
        kind = {10: "market", 2: "forest", 8: "secluded", 12: "coastal", 15: "harbour"}.get(k)
        base.append({"id": tid, "name": f"T{tid}", "x": x, "y": y, "w": w, "character": kind if kind else ch,
                     "cap": 300 + (k * 137) % 1900, "river": river, "axis": 0.0 if river else None,
                     "lake": any(w.get(t, 0) > 0 for t in ("lake", "pool", "mere", "tarn")),
                     # (NEXT_PHASE_BRIEF 53: heights for Upper / Lower twins and the dialect areas' high edge)
                     "alt": float(20 + (k * 53) % 400),
                     # (NEXT_PHASE_BRIEF 61: an industry near every third town, some beyond IND_R; two lakes by the lakes)
                     "ind": {"fam": IND_FAMS[k % len(IND_FAMS)], "d": float(200 + (k * 211) % 1700)} if k % 3 == 1 else None,
                     "facts": {"lakes": 2} if pname in ("lakeside", "tarn hamlet") else None})
    # small towns 900 m from a bigger one (satellites, seeded SAT_P)
    for k, t in enumerate([t for t in base if not t["river"] and not t["lake"]][:10]):
        tid += 7
        base.append({"id": tid, "name": f"T{tid}", "x": t["x"] + 900.0, "y": t["y"], "w": {"plain": 0.8, "field": 0.6, "small": 0.6},
                     "character": False, "cap": 80 + k * 5, "river": False, "axis": None, "lake": False})
    # the map survey's cues: towns with a cue's facts (river component, compass side, lake side, the big bay), two of
    # each, plus a kept (player-renamed) town
    for k, pname in enumerate([p for p in PRESETS if p in CUE_OF] * 2):
        tid += 7
        facts = CUE_OF[pname]
        w = dict(PRESETS[pname])
        cue = {"w": {t: v for t, v in w.items() if t in ("confluence", "falls", "upper", "lower", "north", "dir", "biglake",
                                                          "summit", "peak", "range", "bigbay", "narrows")}}
        for f, v in facts.items():
            cue[f] = v
        base.append({"id": tid, "name": f"T{tid}", "x": 70000.0 + (k % 5) * 5200.0, "y": 70000.0 + (k // 5) * 5200.0,
                     "w": w, "character": False, "cap": 400 + k * 61, "river": w.get("river", 0) > 0, "axis": None,
                     "lake": w.get("lake", 0) > 0, "cue": cue})
    tid += 7
    base.append({"id": tid, "name": "Lake Forest", "x": 71000.0, "y": 71000.0, "w": {"lake": 1, "forest": 0.6},
                 "character": False, "cap": 500, "river": False, "axis": None, "lake": True, "keep": True})
    tbl = {}
    for lang in lua_list(PN.LANGS):
        tbl[lang] = {"list": base, "real": (towns.get(lang) or {}).get("names", [])}
    run = lua.eval(f"function(...) {GOLDEN_LUA} end")
    def lt_of(v):
        if isinstance(v, dict):
            return lua.table_from({kk: lt_of(vv) for kk, vv in v.items() if vv is not None})
        if isinstance(v, list):
            return lua.table_from([lt_of(x) for x in v])
        return v
    lt = lua.table_from({k: lua.table_from({"list": lua.table_from([lt_of(t) for t in v["list"]]),
                                            "real": lua.table_from(v["real"])}) for k, v in tbl.items()})
    # (NEXT_PHASE_BRIEF 53 Part B: a map from 1905, the later layer shares)
    year = 1905
    res = py(run(PN, lt, seed, None, year, rules))
    # (climate runs, NEXT_PHASE_BRIEF 49: the same maps on a tropical, a dry and a subarctic map)
    by_climate = {c: py(run(PN, lt, seed, c, year, rules)) for c in ("tropical", "dry", "subarctic")}
    return {"seed": seed, "year": year, "towns": base, "byLang": res, "byClimate": by_climate, "rules": rules or PN.RULES}


# ------------------------------------------------------------------------------------------------ main

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--session", help="archived session for the map's NAME lines (as `make logs`: name, live, last-...)")
    ap.add_argument("--log", help="a log file path instead of --session")
    ap.add_argument("--seed-text", help='the load that starts at "Map seed text: X" (default: the last with NAME lines)')
    ap.add_argument("--no-map", action="store_true", help="no map section")
    ap.add_argument("--out", default=str(OUT))
    o = ap.parse_args()

    lua = make_runtime()
    LD = req(lua, "ot_placename_lang.lua")
    PN = req(lua, "ot_placename.lua")
    SN = req(lua, "ot_stopname.lua")
    NM = req(lua, "ot_names.lua")

    langs = lua_list(PN.LANGS)
    lang = {}
    parsed = {}
    for k in sorted(py(LD).keys()):
        v = py(LD[k])
        if isinstance(v, dict) and "spec" in v:
            lang[k] = v
    for lid in langs:
        L = PN.lang(lid)
        if L is None:
            continue
        def ent(e):
            d = {"text": e.text, "kind": e.kind, "form": e.form, "k": e.k, "r": e.r, "rd": e.rd, "grp": e.grp,
                 "rare": bool(e.rare), "cls": e.cls, "gender": e.gender, "main": e.main,
                 "tl": [[p[1], p[2]] for p in lua_list(e.tl)], "flags": sorted(py(e.flags) or {})}
            return {k: v for k, v in d.items() if v not in (None, False, [], "")}
        parsed[lid] = {"spec": [ent(e) for e in lua_list(L.specs)], "gen": [ent(e) for e in lua_list(L.gens)],
                       "affix": [ent(e) for e in lua_list(L.affixes)]}
    consts = {}
    for k, v in py(PN).items():
        if re.fullmatch(r"[A-Z][A-Z0-9_]*", k) and isinstance(v, (int, float)) and not isinstance(v, bool):
            consts[k] = v
    pn = {"TAGS": py(PN.TAGS), "SPECIES": py(PN.SPECIES), "PARENT": py(PN.PARENT), "SPEC": py(PN.SPEC),
          "CONTRA": py(PN.CONTRA), "LANGS": langs, "GEN_OF_CLS": py(PN.GEN_OF_CLS), "CLS_OF_GEN": py(PN.CLS_OF_GEN),
          "consts": consts, "BAD": py(PN.BAD) or [],
          # (NEXT_PHASE_BRIEF 53: the shape plan's tables)
          "SHAPES": py(PN.SHAPES), "NON_IDEA": py(PN.NON_IDEA), "FUNC_WORDS": py(PN.FUNC_WORDS), "CLAIM_MIN": py(PN.CLAIM_MIN),
          "FEAT_TAGS": py(PN.FEAT_TAGS),
          # (NEXT_PHASE_BRIEF 53 Part B: the settlement layers and the dry map's water parts)
          "LAYERS": py(PN.LAYERS), "LAYER_SITE": py(PN.LAYER_SITE), "WATER_TAG": py(PN.WATER_TAG),
          # (NEXT_PHASE_BRIEF 60: the descriptive rules' tables)
          "RULES": PN.RULES, "CUE_K": py(PN.CUE_K), "SHAPE_K60": py(PN.SHAPE_K60), "SEP60": py(PN.SEP60),
          "WORDS60": py(PN.WORDS60), "READ_SKIP": py(PN.READ_SKIP),
          # (NEXT_PHASE_BRIEF 61: the s61 kinds, words and the industry families' weights)
          "KINDS61": py(PN.KINDS61), "WORDS61": py(PN.WORDS61), "IND_FAM_K": py(PN.IND_FAM_K)}
    NWm = req(lua, "ot_namewords.lua")
    nwc = {}
    for k, v in py(NWm).items():
        if re.fullmatch(r"[A-Z][A-Z0-9_]*", k) and isinstance(v, (int, float)) and not isinstance(v, bool):
            nwc[k] = v
    nw = {"WORDS": py(NWm.WORDS), "WORDS_OF": py(NWm.WORDS_OF), "SOFT": py(NWm.SOFT), "RARE_EXEMPT": py(NWm.RARE_EXEMPT),
          "STOP": py(NWm.STOP), "consts": nwc}
    if pn["BAD"]:
        print("warning: unknown tags in the inventories:", pn["BAD"], file=sys.stderr)
    block = {"sub": py(LD.BLOCK_SUB), "word": py(LD.BLOCK_WORD), "cjk": py(LD.BLOCK_CJK)}
    towns = town_lists(lua, NM, pn["GEN_OF_CLS"])
    stop = {"LANG": py(SN.LANG), "THEMES": py(SN.THEMES)}
    gold = golden(lua, PN, towns, 12345)
    # (NEXT_PHASE_BRIEF 60: the review's rules too, for the lab's "Rules" select and its port check)
    gold53 = golden(lua, PN, towns, 12345, "s53")
    # (NEXT_PHASE_BRIEF 61: the §60 rules too)
    gold60 = golden(lua, PN, towns, 12345, "s60")

    mp = None
    logp = resolve_log(o)
    if logp is not None:
        if not Path(logp).is_file():
            print(f"warning: no log at {logp}; no map section", file=sys.stderr)
        else:
            mp = read_map(Path(logp), o.seed_text)
            if mp is None:
                print(f"warning: no NAME lines in {logp}" + (f" for seed text {o.seed_text!r}" if o.seed_text else ""),
                      file=sys.stderr)
            elif o.session:
                mp["session"] = o.session

    src = {}
    for f in SRC:
        p = CONTENT / "organic_towns" / f
        src[f] = {"sha": hashlib.sha256(p.read_bytes()).hexdigest()[:12],
                  "mtime": datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M")}
    CLm = req(lua, "ot_climate.lua")
    climate = {"VETO_TAGS": py(CLm.VETO_TAGS), "SITE": py(CLm.SITE), "WORDS": py(CLm.WORDS), "LANG_OF": py(CLm.LANG_OF),
               "EXTRA": CLm.EXTRA, "VETO_MIN": CLm.VETO_MIN, "MAX_WORDS": CLm.MAX_WORDS, "CLIMATES": py(CLm.CLIMATES),
               "NOT_WORDS": py(CLm.NOT_WORDS)}
    data = {"built": datetime.now().strftime("%Y-%m-%d %H:%M"), "src": src, "pn": pn, "nw": nw, "lang": lang, "parsed": parsed,
            "climate": climate,
            "block": block, "towns": towns, "stop": stop, "presets": PRESETS, "golden": gold, "golden53": gold53, "golden60": gold60,
            "map": mp}
    js = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    Path(o.out).write_text(js, encoding="utf-8")
    # The old lab page (names/index.html, check_port.js) still loads data.js: the same data as a script, until that page
    # is retired (plans/site/PLAN.md Open).
    Path(o.out).with_suffix(".js").write_text(
        "// Generated by plans/square_organic_towns/names/export_names.py from the mod's Lua. Do not edit.\n"
        f"window.NAMEDATA = {js};\n", encoding="utf-8")
    nt =sum(len(v["names"]) for v in towns.values())
    print(f"{o.out}: {len(js) / 1024:.0f} KB · {len(lang)} languages · {nt} game town names · "
          f"golden {sum(len(v['rows']) for v in gold['byLang'].values())} names · "
          f"map {'-' if mp is None else str(len(mp['towns'])) + ' towns (seed text ' + str(mp['seedText']) + ')'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
