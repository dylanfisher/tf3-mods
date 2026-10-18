#!/usr/bin/env python3
"""Build the data of an Organic Towns comparison (two or more runs on the same seed) from the game log.

Reads map loads of the archived game log(s) (a session can hold several, like 2026-10-14_0119_sqot), pairs the towns
by entity id with the first run's (the same seed gives the same ids; else by position), and writes a folder with:

    data.json           version 3: the runs list, every per-town metric per run (`units`), the towns a run created
                        (`extraUnits`), medians / quartiles / sums, run rows; plain data, no HTML (the site's
                        compare.ts words the page: description, generated key points, footer)
    <dir>/NN-<town>.jpg each run's tour shots (sips -Z 1400, JPEG); extra towns (districts, Works) <dir>/x-<town>.jpg

Each run needs the dev mod's measure after the simulation: SIMGROW start / town / year=40 / stop, the ALLTOWN lines
and the tour's SHOT lines (OT Dev, Simulate, Tour on, screenshots on).

Usage (from the repo root):
    # a new two-run page
    uv run plans/square_organic_towns/compare/build_compare.py --a 2026-10-14_0119_sqot:1 --b 2026-10-14_0119_sqot:2 \
        [--out plans/square_organic_towns/compare/<date>_<seed>] [--label-a 'Organic Towns'] [--label-b 'Vanilla'] \
        [--dir-a mod --dir-b vanilla] [--verdicts verdicts.json] [--no-shots]
    # add a run to an existing page (v1 / v2 data.json is converted to v3; verdicts and notes are kept)
    uv run plans/square_organic_towns/compare/build_compare.py --out plans/square_organic_towns/compare/2026-10-14_U8Qxgisp4I \
        --add 2026-10-14_0302:2 --label 'Mod 0302 (density round)' --dir mod-0302 [--relabel mod='Mod 0119 ...']
    # re-read every run of a page from its log (after a script change)
    uv run plans/square_organic_towns/compare/build_compare.py --out <page folder> --rebuild [--notes notes.json]
    # a single-run page (a gallery of every town with its metrics; no pairing), e.g. a run on a new seed
    uv run plans/square_organic_towns/compare/build_compare.py --single 2026-10-14_0502_sqot:1 --label 'Mod 0502' \
        --dir mod --out plans/square_organic_towns/compare/2026-10-14_Z2tNDhy0Ht --shot-px 1600 --shot-q 50

A run is `<session name or prefix | path to a .log/.log.gz>[:<load>]`; <load> is the 1-based map load inside the log
(split at "Init game took"); without it the first load with a SIMGROW stop (the next one for a second run of the same
log). --verdicts: a JSON file { "<NN or town id>": { "category": "clear" | "similar", "verdict": "text" } } (the page's
filters and notes); towns without one are "unrated". --notes: { "keyNotes": ["text", ...] } for the key-points box:
plain text with **bold** and `code` (the site renders only these two; no HTML).
The site renders it (site/, section "Map comparisons", kind run-compare, labels and metric rows in
site/src/mods/square_organic_towns/compare.ts): `make site-media` then `make site-dev`. The shots are read from the paths the log's "Screenshot: wrote" lines name; a shot already in the folder is kept.
--shot-px / --shot-q: the shots' longest side (default 1400) and JPEG quality (default: sips' own).
--single: a one-run page; --rebuild on it keeps it single (data.json `single: true`).
"""
import argparse
import glob
import gzip
import json
import math
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LOGS = os.path.join(ROOT, ".cache", "logs")

KV = re.compile(r"(\w+)=(\S*)")
TS = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)Z")


def fields(line, tag):
    """key=value pairs after `tag` in a log line (dict of strings)."""
    i = line.find(tag)
    return dict(KV.findall(line[i + len(tag):])) if i >= 0 else {}


def num(v, default=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def open_log(spec):
    path = spec
    if not os.path.exists(path):
        # (an exact session name first: "2026-10-14_0640_sqrl-sqsg" also prefixes its "-2" archive, which sorts first)
        exact = [p for p in (os.path.join(LOGS, spec + ".log.gz"), os.path.join(LOGS, spec + ".log")) if os.path.exists(p)]
        cands = exact or sorted(glob.glob(os.path.join(LOGS, spec + "*.log.gz")) + glob.glob(os.path.join(LOGS, spec + "*.log")))
        if not cands:
            sys.exit(f"no log for {spec!r} (a path, or a session name in {LOGS})")
        path = cands[0]
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt", encoding="utf-8", errors="replace") as f:
        return path, f.read().split("\n")


def loads(lines):
    """[(pre_start, start, end)] per map load: `Init game took` at start; pre = the loading lines before it."""
    marks = [i for i, l in enumerate(lines) if "Init game took" in l]
    out = []
    for k, m in enumerate(marks):
        pre = marks[k - 1] + 1 if k > 0 else 0
        end = marks[k + 1] if k + 1 < len(marks) else len(lines)
        out.append((pre, m, end))
    return out


def pick_load(lines, want, skip=None):
    ls = loads(lines)
    if not ls:
        sys.exit("no map load (Init game took) in the log")
    if want is not None:
        if not 1 <= want <= len(ls):
            sys.exit(f"load {want} of {len(ls)}")
        return want, ls[want - 1]
    for k, (p, s, e) in enumerate(ls, 1):
        if k == skip:
            continue
        if any("SIMGROW stop" in l for l in lines[s:e]):
            return k, (p, s, e)
    sys.exit("no load with a SIMGROW stop")


def quant(vals):
    v = sorted(x for x in vals if x is not None)
    if not v:
        return None
    def q(p):
        pos = (len(v) - 1) * p
        lo = math.floor(pos)
        hi = min(lo + 1, len(v) - 1)
        return v[lo] + (v[hi] - v[lo]) * (pos - lo)
    return [round(q(0.25), 4), round(q(0.5), 4), round(q(0.75), 4), v[0], v[-1]]


def parse_run(lines, rng):
    pre, start, end = rng
    body = lines[start:end]
    run = {"pre": [], "towns": {}, "years": [], "shots": [], "extras": {}, "counts": new_counts()}
    for l in lines[pre:start]:
        if "Seed text:" in l and "Map seed" not in l:
            run["seed"] = l.split("Seed text:", 1)[1].strip()
        if "[SQOT] PRERUN" in l or "[SQOT] ANGLE" in l:
            run["pre"].append(l[l.find("[SQOT]"):].strip())
    m = TS.match(lines[start])
    run["loadAt"] = m.group(1)[11:] if m else "-"
    run["initS"] = num(lines[start].rsplit(":", 1)[-1].replace("s", "").strip())
    last_wrote = None
    allt = {}
    for l in body:
        if "[SQOT] INIT " in l:
            run["init"] = l[l.find("INIT"):].strip()
        elif "SIMGROW start" in l:
            run["startLine"] = l[l.find("[SQOT_DEV]"):].strip()
            run["simStart"] = TS.match(l).group(1)[11:] if TS.match(l) else "-"
        elif "SIMGROW stop" in l:
            run["stopLine"] = l[l.find("[SQOT_DEV]"):].strip()
            run["simStop"] = TS.match(l).group(1)[11:] if TS.match(l) else "-"
        elif "SIMGROW town " in l and " year=" not in l:
            f = fields(l, "SIMGROW town ")
            t = run["towns"].setdefault(f.get("town"), {})
            t.update(startName=f.get("name", "").replace("_", " "), personsStart=num(f.get("persons")),
                     buildingsStart=num(f.get("buildings")), rate=num(f.get("rate")), cls=f.get("class"))
        elif "SIMGROW town year=" in l:
            f = fields(l, "SIMGROW town ")
            t = run["towns"].setdefault(f.get("town"), {})
            t.update(lastYear=num(f.get("year")), personsEnd=num(f.get("persons")), targetEnd=num(f.get("target")),
                     factorEnd=f.get("factor"))
        elif "SIMGROW final" in l:
            f = fields(l, "SIMGROW final ")
            t = run["towns"].setdefault(f.get("town"), {})
            t.update(factor=f.get("factor"), cls=t.get("cls") or f.get("class"))
        elif "SIMGROW year year=" in l:
            f = fields(l, "SIMGROW year ")
            run["years"].append({"year": num(f.get("year")), "s": num(f.get("s")), "buildings": f.get("buildings"),
                                 "cap": f.get("cap"), "filled": f.get("filled"), "round": f.get("round")})
        elif "] ALLTOWN n=" in l:
            f = fields(l, "ALLTOWN ")
            allt[f.get("town")] = f   # (the last tour's measure wins)
        elif "Screenshot: wrote " in l:
            last_wrote = l.split("Screenshot: wrote ", 1)[1].strip()
        elif "[SQOT_DEV] SHOT n=" in l:
            f = fields(l, "SHOT ")
            key = f.get("key", "")
            run["shots"].append({"n": num(f.get("n")), "key": key, "ok": f.get("ok") == "true", "file": last_wrote,
                                 "town": key[4:] if key.startswith("ALL_") else None})
            last_wrote = None
        elif "[SQOT] " in l:
            extra_line(run["extras"], l)
            count_line(run["counts"], l)
    run["alltown"] = allt
    return run


def new_counts():
    return {"checkWhy": {}, "builds": {}, "builtEdges": {}, "satBuilt": 0, "satWhy": {}, "districts": 0,
            "districtsLinked": 0, "districtNone": {}, "works": 0, "worksLinked": 0, "worksNone": {}, "levelsSet": 0,
            "levelsClear": 0, "bridgesBuilt": 0, "bridgesRefused": 0, "coastal": 0, "straightCut": 0, "upwardDoses": 0}


def bump(d, k, by=1):
    d[k] = d.get(k, 0) + by


def count_line(c, l):
    """Run-level counts of a run's [SQOT] lines (the page's run rows; data.json runs[].counts)."""
    if "] CHECK town=" in l:
        bump(c["checkWhy"], fields(l, "CHECK ").get("why", "?"))
    elif "] BUILT town=" in l and "ok=true" in l:
        f = fields(l, "BUILT ")
        bump(c["builds"], f.get("trigger", "?"))
        bump(c["builtEdges"], f.get("trigger", "?"), int(num(f.get("edges"), 0)))
    elif "] SATELLITE built " in l:
        if fields(l, "SATELLITE built ").get("kind") == "seed":
            c["satBuilt"] += 1
    elif "] SATELLITE town=" in l and " why=" in l:
        bump(c["satWhy"], fields(l, "SATELLITE ").get("why", "?"))
    elif "] DISTRICT " in l:
        f = fields(l, "DISTRICT ")
        ev = f.get("event")
        if ev == "created":
            c["districts"] += 1
        elif ev == "linked":
            c["districtsLinked"] += 1
        elif ev == "none" or f.get("on") == "false":
            bump(c["districtNone"], f.get("why", "?"))
    elif "] WORKS " in l:
        f = fields(l, "WORKS ")
        ev = f.get("event")
        if ev == "created":
            c["works"] += 1
        elif ev == "linked":
            c["worksLinked"] += 1
        elif ev == "none" or f.get("on") == "false":
            bump(c["worksNone"], f.get("why", "?"))
    elif "] LEVELS town=" in l and " action=" in l:
        a = fields(l, "LEVELS ").get("action")
        if a == "set":
            c["levelsSet"] += 1
        elif a == "clear":
            c["levelsClear"] += 1
    elif "] BRIDGE " in l and "outcome=" in l:
        o = fields(l, "BRIDGE ").get("outcome")
        if o == "built":
            c["bridgesBuilt"] += 1
        elif o in ("refused", "failed"):
            c["bridgesRefused"] += 1
    elif "] COASTAL town=" in l and "applied=true" in l:
        c["coastal"] += 1
    elif "] PLAN town=" in l and " straight=" in l:
        cut = fields(l, "PLAN ").get("straight", "0/0").split("/")
        if len(cut) == 2:
            c["straightCut"] += int(num(cut[1], 0))
    elif "] UPWARD effect " in l:
        c["upwardDoses"] += 1


def extra_line(ex, l):
    """The main mod's per-town extras (run A only matters)."""
    def town(f):
        return ex.setdefault(f.get("town"), {"satelliteBuilt": False, "districts": [], "works": [], "worksLinked": False,
                                             "districtLinked": False, "bridges": [], "coastal": False, "character": False,
                                             "forest": [], "builtEdges": 0, "builds": 0, "failed": 0, "straight": 0,
                                             "levels": None, "checkWhy": {}, "matLast": None, "demKLast": None,
                                             "matHalfAt": None, "levelsSkip": None, "satellites": 0})
    if "] CHECK town=" in l:
        f = fields(l, "CHECK ")
        e = town(f)
        bump(e["checkWhy"], f.get("why", "?"))
        mat, dk = num(f.get("mat")), num(f.get("demK"))
        e["matLast"], e["demKLast"] = mat, dk
        if mat is not None and mat >= 0.5 and e["matHalfAt"] is None:
            e["matHalfAt"] = (f.get("cap") or "-").split("/")[0]
    elif "] LEVELS town=" in l and " skip=" in l:
        town(fields(l, "LEVELS "))["levelsSkip"] = fields(l, "LEVELS ").get("skip")
    elif "] SATELLITE built " in l:
        f = fields(l, "SATELLITE built ")
        if f.get("kind") == "seed":
            town(f)["satelliteBuilt"] = True
            town(f)["satellites"] += 1
    elif "] DISTRICT " in l and "event=created" in l:
        f = fields(l, "DISTRICT ")
        town(f)["districts"].append(f.get("name", "").replace("_", " ") + (f" ({f['kind']})" if f.get("kind") else ""))
    elif "] DISTRICT " in l and "event=linked" in l:
        town(fields(l, "DISTRICT "))["districtLinked"] = True
    elif "] WORKS " in l and "event=created" in l:
        f = fields(l, "WORKS ")
        town(f)["works"].append(f.get("name", "").replace("_", " "))
    elif "] WORKS " in l and "event=linked" in l:
        town(fields(l, "WORKS "))["worksLinked"] = True
    elif "] BRIDGE " in l and "outcome=built" in l:
        f = fields(l, "BRIDGE ")
        town(f)["bridges"].append(f"built span {f.get('span', '?')} m")
    elif "] COASTAL town=" in l and "applied=true" in l:
        town(fields(l, "COASTAL "))["coastal"] = True
    elif "] STYLE town=" in l and "character=true" in l:
        town(fields(l, "STYLE "))["character"] = True
    elif "] FOREST town=" in l and " share=" in l:
        f = fields(l, "FOREST ")
        town(f)["forest"].append(num(f.get("share")))
    elif "] BUILT town=" in l and "ok=true" in l:
        f = fields(l, "BUILT ")
        e = town(f)
        e["builds"] += 1
        e["builtEdges"] += int(num(f.get("edges"), 0))
    elif "] FAILED town=" in l:
        town(fields(l, "FAILED "))["failed"] += 1
    elif "] PLAN town=" in l and " straight=" in l:
        f = fields(l, "PLAN ")
        cut = f.get("straight", "0/0").split("/")
        if len(cut) == 2:
            town(f)["straight"] += int(num(cut[1], 0))
    elif "] LEVELS town=" in l and " action=" in l:
        f = fields(l, "LEVELS ")
        town(f)["levels"] = f"{f.get('action')} k={f.get('k')} pb={f.get('pb')}"


def town_metrics(run, tid, shot_rel):
    a = run["alltown"].get(tid)
    s = run["towns"].get(tid, {})
    if a is None:
        return None
    b = num(a.get("buildings"), 0)
    r = num(a.get("r"), 0)
    edges = num(a.get("edges"), 0)
    sl = num(a.get("streetLen"))
    el = num(a.get("emptyLen"))
    ee = num(a.get("emptyEdges"))
    de = num(a.get("deadEnds"))
    pe = s.get("personsEnd")
    free = a.get("freeLots", "-").split("/")
    sp = a.get("spread", "-").split("/")
    lvl = a.get("lvl", "-")
    lvl_a = lvl.split(",")[0][2:] if lvl.startswith("a:") else None
    lv = [num(x) for x in lvl_a.split("/")] if lvl_a else []
    orient = [num(x) for x in a.get("orient", "").split("/")]
    out = {
        "name": a.get("name", "").replace("_", " "), "startName": s.get("startName"),
        "buildingsStart": s.get("buildingsStart"), "buildingsEnd": b,
        "personsStart": s.get("personsStart"), "personsEnd": pe, "targetEnd": s.get("targetEnd"),
        "targetShare": round(pe / s["targetEnd"], 3) if pe and s.get("targetEnd") else None,
        "growthBuildings": round(b / s["buildingsStart"], 2) if s.get("buildingsStart") else None,
        "growthPersons": round(pe / s["personsStart"], 2) if pe and s.get("personsStart") else None,
        "factor": s.get("factor"), "rate": s.get("rate"), "class": s.get("cls"),
        "r": round(r), "rPerSqrtB": round(r / math.sqrt(b), 1) if b > 0 else None, "dens": num(a.get("dens")),
        "spread": num(sp[0]) if sp else None, "beyondPct": num(sp[1]) if len(sp) > 1 else None,
        "lobes": num(sp[2]) if len(sp) > 2 else None, "orient": a.get("orient"),
        "capacity": num(a.get("capacity")), "edges": edges, "streetLen": sl, "emptyLen": el, "emptyEdges": ee,
        "emptyEdgePct": round(100 * ee / edges, 1) if ee is not None and edges else None,
        "emptyLenPct": round(100 * el / sl, 1) if el is not None and sl else None,
        "deadEnds": de, "pb": num(a.get("pb")),
        "freeLotsPct": round(100 * num(free[0], 0) / num(free[1], 1), 1) if len(free) == 2 and num(free[1]) else None,
        "streetPerBuilding": round(sl / b, 1) if sl and b else None,
        "edgesPer100B": round(100 * edges / b, 1) if b else None,
        "style": a.get("style"), "form": a.get("form"), "shape": a.get("shape"), "motifs": a.get("motifs"),
        "forest": a.get("forest"), "ind": a.get("ind"), "lvl": lvl, "lvlActual": lvl_a,
        "orth": orient[0] if len(orient) == 3 else None,
        "lvl2Pct": lv[1] if len(lv) == 4 else None, "lvl34Pct": (lv[2] or 0) + (lv[3] or 0) if len(lv) == 4 else None,
        "x": num(a.get("x")), "y": num(a.get("y")), "shot": shot_rel,
        "personsPerHa": round(pe / (math.pi * r * r / 1e4), 1) if pe and r else None,
        "streetPerPerson": round(sl / pe, 2) if sl and pe else None,
        "deadEndsPerKm": round(de / (sl / 1000), 2) if de is not None and sl else None,
    }
    return out


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", (s or "town").lower()).strip("-") or "town"


SHOT = {"px": 1400, "q": None}


def copy_shot(src, dst, enabled):
    if not enabled or not src or not os.path.exists(src):
        return False
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if shutil.which("sips"):
        q = ["-s", "formatOptions", str(SHOT["q"])] if SHOT["q"] else []
        r = subprocess.run(["sips", "-Z", str(SHOT["px"]), "-s", "format", "jpeg"] + q + [src, "--out", dst],
                           capture_output=True)
        return r.returncode == 0
    shutil.copyfile(src, dst)
    return True


EXTRA_KEYS = (("satelliteBuilt", False), ("districts", []), ("works", []), ("worksLinked", False),
              ("districtLinked", False), ("bridges", []), ("coastal", False), ("character", False), ("builtEdges", 0),
              ("builds", 0), ("failed", 0), ("straight", 0), ("levels", None), ("checkWhy", {}), ("matLast", None),
              ("demKLast", None), ("matHalfAt", None), ("levelsSkip", None), ("satellites", 0))
SUM_KEYS = ["buildingsStart", "buildingsEnd", "personsStart", "personsEnd", "growthBuildings", "growthPersons",
            "targetShare", "r", "rPerSqrtB", "dens", "spread", "beyondPct", "lobes", "edges", "streetLen", "emptyLen",
            "emptyEdgePct", "emptyLenPct", "deadEnds", "pb", "freeLotsPct", "streetPerBuilding", "edgesPer100B",
            "capacity", "personsPerHa", "streetPerPerson", "deadEndsPerKm", "orth", "lvl2Pct", "lvl34Pct", "modShare"]
RUN_KEYS = ("loadAt", "initS", "simStart", "simStop", "init", "pre", "startLine", "stopLine", "years", "seed", "counts")


def split_spec(spec):
    m = re.match(r"^(.*?)(?::(\d+))?$", spec)
    return m.group(1), int(m.group(2)) if m.group(2) else None


def rid_of(label, used):
    base = slug(label)[:24] or "run"
    rid, k = base, 2
    while rid in used:
        rid, k = f"{base}-{k}", k + 1
    return rid


def specs_from_data(d):
    """The run specs of an existing data.json: v2 (runs list) or v1 (the two-run page: runs.mod / runs.vanilla)."""
    if isinstance(d.get("runs"), list):
        return [{k: r.get(k) for k in ("id", "label", "dir", "session", "load")} for r in d["runs"]]
    H = d.get("header") or {}
    loads = d.get("loads") or [1, 2]
    sess = d.get("session")
    return [{"id": "mod", "label": H.get("labelA", "Organic Towns"), "dir": "mod", "session": sess, "load": loads[0]},
            {"id": "vanilla", "label": H.get("labelB", "Vanilla"), "dir": "vanilla", "session": sess, "load": loads[1]}]


def existing_shot(out, rel):
    if rel and os.path.exists(os.path.join(out, rel)):
        return rel
    return None


def find_extra_shot(out, d, nm):
    """An extra town's shot already in the folder (x-<slug>.jpg, or the v1 page's NN-<slug>.jpg)."""
    hits = sorted(glob.glob(os.path.join(out, d, f"*-{slug(nm)}.jpg")))
    return f"{d}/{os.path.basename(hits[0])}" if hits else None


def legacy_note(html):
    """A v2 key note (HTML with <b> / <code>) as v3 text: **bold**, `code`, other tags dropped."""
    t = re.sub(r"<b>(.*?)</b>", r"**\1**", html, flags=re.S)
    t = re.sub(r"<code>(.*?)</code>", r"`\1`", t, flags=re.S)
    t = re.sub(r"<[^>]*>", "", t)
    return t.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&#39;", "'").replace("&amp;", "&")


def site_slug(s):
    """The site's URL rule (site/src/lib/slug.ts slugify): lowercase, dashes, never underscores."""
    s = re.sub(r"[^a-z0-9.]+", "-", s.lower())
    return re.sub(r"^[-.]+|[-.]+$", "", re.sub(r"-*\.-*", ".", s))


def build(specs, out, verdicts, notes_in, no_shots, title=None, single=False):
    used, runs, parsed = set(), [], []
    cache = {}
    for i, sp in enumerate(specs):
        sess, want = sp["session"], sp.get("load")
        if sess not in cache:
            cache[sess] = open_log(sess)
        path, lines = cache[sess]
        skip = None
        if want is None and i > 0 and parsed and parsed[-1][1] == path:
            skip = parsed[-1][2]
        k, rng = pick_load(lines, want, skip=skip)
        R = parse_run(lines, rng)
        rid = sp.get("id") or rid_of(sp["label"], used)
        used.add(rid)
        R["kind"] = "mod" if "on=true" in (R.get("init") or "") else "vanilla"
        parsed.append((R, path, k))
        runs.append({"id": rid, "label": sp["label"], "dir": sp.get("dir") or rid, "session":
                     os.path.basename(path).split(".log")[0], "load": k, "kind": R["kind"]}
                    | {kk: R.get(kk) for kk in RUN_KEYS})
    A = parsed[0][0]
    base_ids = sorted((t for t in A["towns"] if t in A["alltown"]), key=lambda x: int(x))

    def match(R, t):
        if t in R["alltown"]:
            return t
        ax, ay = num(A["alltown"][t].get("x")), num(A["alltown"][t].get("y"))
        best = None
        for u, f in R["alltown"].items():
            dd = math.hypot(num(f.get("x"), 1e9) - ax, num(f.get("y"), 1e9) - ay)
            if dd < 100 and (best is None or dd < best[0]):
                best = (dd, u)
        return best[1] if best else None

    towns, matched = [], {r["id"]: set() for r in runs}
    for i, t in enumerate(base_ids, 1):
        nn = f"{i:02d}"
        T = {"nn": nn, "ids": {}, "m": {}, "x": {}, "samePos": {}}
        for (R, _, _), run in zip(parsed, runs):
            rid, u = run["id"], match(R, t)
            if u is None:
                T["ids"][rid] = None; T["m"][rid] = None; T["x"][rid] = None
                continue
            matched[rid].add(u)
            nm = R["alltown"][u].get("name", "").replace("_", " ")
            rel = f"{run['dir']}/{nn}-{slug(nm)}.jpg"
            shots = {s["town"]: s for s in R["shots"] if s["town"]}
            ok = copy_shot(shots.get(u, {}).get("file"), os.path.join(out, rel), not no_shots)
            m = town_metrics(R, u, rel if ok else existing_shot(out, rel))
            ex = R["extras"].get(u, {})
            fo = [v for v in ex.get("forest", []) if v is not None]
            xx = None
            if run["kind"] == "mod":
                xx = {k: ex.get(k, dflt) for k, dflt in EXTRA_KEYS} | {
                    "forestShareFirst": fo[0] if fo else None, "forestShareLast": fo[-1] if fo else None,
                    "forestReads": len(fo)}
                m["modShare"] = round(100 * xx["builtEdges"] / m["edges"], 1) if m["edges"] else None
            T["ids"][rid] = int(u); T["m"][rid] = m; T["x"][rid] = xx; T["samePos"][rid] = u == t
        v = verdicts.get(nn) or verdicts.get(t) or {}
        T["category"], T["verdict"] = v.get("category", "unrated"), v.get("verdict", "")
        towns.append(T)

    extra = {}
    for (R, _, _), run in zip(parsed, runs):
        rows = []
        shots = {s["town"]: s for s in R["shots"] if s["town"]}
        for u, f in R["alltown"].items():
            if u in matched[run["id"]]:
                continue
            nm = f.get("name", "").replace("_", " ")
            have = find_extra_shot(out, run["dir"], nm)
            rel = have or f"{run['dir']}/x-{slug(nm)}.jpg"
            ok = have is not None or copy_shot(shots.get(u, {}).get("file"), os.path.join(out, rel), not no_shots)
            rows.append({"id": int(u), "name": nm, "buildings": num(f.get("buildings")), "edges": num(f.get("edges")),
                         "r": round(num(f.get("r"), 0)), "pb": num(f.get("pb")), "emptyEdges": num(f.get("emptyEdges")),
                         "ind": f.get("ind"), "shot": rel if ok else None})
        extra[run["id"]] = rows

    summary = {}
    for k in SUM_KEYS:
        summary[k] = {}
        for run in runs:
            vals = [t["m"][run["id"]][k] for t in towns if t["m"].get(run["id"]) and t["m"][run["id"]].get(k) is not None]
            summary[k][run["id"]] = {"q": quant(vals), "sum": round(sum(vals), 2) if vals else None}

    def med(rid, k):
        q = summary[k][rid]["q"]
        return q[1] if q else None

    def tot(rid, k):
        return summary[k][rid]["sum"] or 0

    def orient_med(rid):
        parts = [[num(x) for x in (t["m"][rid] or {}).get("orient", "").split("/")] for t in towns if t["m"].get(rid)]
        parts = [p for p in parts if len(p) == 3 and None not in p]
        return " / ".join(f"{quant([p[i] for p in parts])[1]:.2f}" for i in range(3)) if parts else "-"

    def last_cap(run):
        for y in reversed(run.get("years") or []):
            if y.get("cap"):
                return y["cap"]
        return "-"

    def wtxt(d):
        return ", ".join(f"{k} {v}" for k, v in sorted(d.items(), key=lambda kv: -kv[1])) or "-"

    run_rows = [["Street orientation orth / radial / ring (median)"] + [orient_med(r["id"]) for r in runs],
                ["Sim time (s) / per year"] + [f"{fields(r.get('stopLine') or '', 'SIMGROW stop ').get('s', '-')} / "
                                               f"{fields(r.get('stopLine') or '', 'SIMGROW stop ').get('sPerYear', '-')}" for r in runs],
                ["Persons vs target at the end (SIMGROW cap)"] + [last_cap(r) for r in runs]]
    mods = [r for r in runs if r["kind"] == "mod"]
    if mods:
        def mrow(label, f):
            return [label] + [f(r["counts"], r) if r["kind"] == "mod" else "-" for r in runs]
        run_rows += [
            mrow("Mod-built street edges: head start / demand (builds)", lambda c, r: f"{c['builtEdges'].get('head', 0)} / "
                 f"{c['builtEdges'].get('demand', 0)} ({c['builds'].get('head', 0)} / {c['builds'].get('demand', 0)})"),
            mrow("Mod-built share of the 16 towns' edges", lambda c, r: f"{100 * sum(c['builtEdges'].values()) / max(1, tot(r['id'], 'edges')):.0f} %"),
            mrow("SIMGROW build rounds / round builds", lambda c, r: f"{fields(r.get('stopLine') or '', 'SIMGROW stop ').get('rounds', '-')} / "
                 f"{fields(r.get('stopLine') or '', 'SIMGROW stop ').get('roundBuilds', '-')}"),
            mrow("CHECK outcomes", lambda c, r: wtxt(c["checkWhy"])),
            mrow("Satellites built (decisions)", lambda c, r: f"{c['satBuilt']} ({wtxt(c['satWhy'])})"),
            mrow("Districts / Works created (linked)", lambda c, r: f"{c['districts']} ({c['districtsLinked']}) / {c['works']} ({c['worksLinked']})"),
            mrow("District / Works not founded (why)", lambda c, r: f"{wtxt(c['districtNone'])} / {wtxt(c['worksNone'])}"),
            mrow("Bridges built / refused, coastal picks", lambda c, r: f"{c['bridgesBuilt']} / {c['bridgesRefused']}, {c['coastal']}"),
            mrow("Level weights set / cleared, upward doses", lambda c, r: f"{c['levelsSet']} / {c['levelsClear']}, {c['upwardDoses']}"),
            mrow("Straight-run edges cut", lambda c, r: str(c["straightCut"])),
        ]
    seed = A.get("seed") or "noseed"
    labels = [r["label"] for r in runs]
    header = {
        "title": title or (f"{labels[0]}, seed {seed}" if len(runs) == 1 else f"{labels[0]} vs {labels[1]}" if len(runs) == 2
                           else f"Organic Towns: {len(runs)} runs, seed {seed}"),
        "h1": title or f"{' · '.join(labels)}",
    }
    notes = {k: v for k, v in (notes_in or {}).items() if k != "auto"}
    pairing = "id" if all(all(t["samePos"].values()) for t in towns) else "id-or-position"
    data = {"version": 3, "single": single or len(runs) == 1, "seed": seed, "built": datetime.now().strftime("%Y-%m-%d %H:%M"),
            "pairing": pairing, "header": header, "runs": runs, "units": towns, "extraUnits": extra, "summary": summary,
            "notes": notes, "runRows": run_rows}
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "data.json"), "w") as f:
        json.dump(data, f, indent=1)
    for r in runs:
        rid = r["id"]
        n_shot = sum(1 for t in towns if t["m"].get(rid) and t["m"][rid].get("shot"))
        n_town = sum(1 for t in towns if t["m"].get(rid))
        print(f"  {rid:28s} {r['session']}:{r['load']}  towns {n_town}  shots {n_shot}  extra {len(extra[rid])}  "
              f"buildings {tot(rid, 'buildingsStart'):,.0f}->{tot(rid, 'buildingsEnd'):,.0f}  pb {med(rid, 'pb')}")
    print(f"{out}: {len(towns)} towns, {len(runs)} runs")
    print(f"view it on the site: make site-media && make site-dev  ->  "
          f"http://localhost:4321/square-organic-towns/comparisons/{site_slug(os.path.basename(os.path.normpath(out)))}/")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--a", help="new page, run A (Organic Towns): session[:load] or log path[:load]")
    ap.add_argument("--b", help="new page, run B (reference): session[:load] or log path[:load]")
    ap.add_argument("--add", help="add this run (session[:load]) to the existing page in --out")
    ap.add_argument("--single", help="a one-run page (session[:load]): every town's shot and metrics, no pairing")
    ap.add_argument("--shot-px", type=int, default=1400, help="shots: longest side in px (default 1400)")
    ap.add_argument("--shot-q", type=int, default=None, help="shots: JPEG quality 1-100 (default: sips' own)")
    ap.add_argument("--label", help="--add / --single: the run's label")
    ap.add_argument("--dir", help="--add / --single: the run's shot folder (default: a slug of the label; --single: mod)")
    ap.add_argument("--rebuild", action="store_true", help="re-read every run of the page in --out from its log")
    ap.add_argument("--relabel", action="append", default=[], help="<run id>=<label> (repeatable)")
    ap.add_argument("--out", help="output folder (default compare/<date>_<seed>; required for --add / --rebuild)")
    ap.add_argument("--label-a", default="Organic Towns")
    ap.add_argument("--label-b", default="Vanilla")
    ap.add_argument("--dir-a", default="mod")
    ap.add_argument("--dir-b", default="vanilla")
    ap.add_argument("--title", help="page title (default: from the labels)")
    ap.add_argument("--verdicts")
    ap.add_argument("--notes", help='JSON file {"keyNotes": ["text", ...]} for the key-points box (**bold**, `code`; kept on later rebuilds)')
    ap.add_argument("--no-shots", action="store_true")
    o = ap.parse_args()
    SHOT["px"], SHOT["q"] = o.shot_px, o.shot_q
    verdicts, notes, title = {}, {}, o.title
    single = False
    if o.single:
        sess, load = split_spec(o.single)
        lab = o.label or "Organic Towns"
        specs = [{"id": slug(o.dir or "mod"), "label": lab, "dir": o.dir or "mod", "session": sess, "load": load}]
        out, single = o.out, True
        if out and os.path.exists(os.path.join(out, "data.json")):
            old = json.load(open(os.path.join(out, "data.json")))
            notes = {k: v for k, v in (old.get("notes") or {}).items() if k != "auto"}
            if (old.get("version") or 1) == 2 and notes.get("keyNotes"):
                notes["keyNotes"] = [legacy_note(n) for n in notes["keyNotes"]]
    elif o.add or o.rebuild:
        if not o.out:
            sys.exit("--add / --rebuild need --out <existing page folder>")
        old = json.load(open(os.path.join(o.out, "data.json")))
        specs = specs_from_data(old)
        for t in old.get("units") or old.get("towns") or []:
            if t.get("category") or t.get("verdict"):
                verdicts[t["nn"]] = {"category": t.get("category", "unrated"), "verdict": t.get("verdict", "")}
        version = old.get("version") or 1
        notes = {k: v for k, v in (old.get("notes") or {}).items() if k != "auto"}
        if version < 2 and notes and "keyNotes" not in notes:
            notes = {"keyNotes": [f"**{specs[0]['label']} vs {specs[1]['label']}:** {legacy_note(v)}" for v in notes.values()
                                  if isinstance(v, str)]}
        elif version == 2 and notes.get("keyNotes"):
            notes["keyNotes"] = [legacy_note(n) for n in notes["keyNotes"]]
        title = title or ((old.get("header") or {}).get("title") if version >= 2 else None)
        single = bool(old.get("single")) and not o.add
        if o.add:
            if not o.label:
                sys.exit("--add needs --label")
            sess, load = split_spec(o.add)
            specs.append({"id": slug(o.dir or o.label), "label": o.label, "dir": o.dir or slug(o.label), "session": sess, "load": load})
        out = o.out
    else:
        if not (o.a and o.b):
            sys.exit("a new page needs --a and --b (or --add / --rebuild with --out)")
        (sa, la), (sb, lb) = split_spec(o.a), split_spec(o.b)
        specs = [{"id": "mod", "label": o.label_a, "dir": o.dir_a, "session": sa, "load": la},
                 {"id": "vanilla", "label": o.label_b, "dir": o.dir_b, "session": sb, "load": lb}]
        out = o.out
    for rl in o.relabel:
        k, _, v = rl.partition("=")
        for sp in specs:
            if sp["id"] == k:
                sp["label"] = v
    if o.verdicts:
        verdicts.update(json.load(open(o.verdicts)))
    if o.notes:
        notes.update(json.load(open(o.notes)))
    if out is None:
        path, lines = open_log(specs[0]["session"])
        _, rng = pick_load(lines, specs[0]["load"])
        seed = parse_run(lines, rng).get("seed") or "noseed"
        out = os.path.join(HERE, f"{os.path.basename(path)[:10]}_{seed}")
    build(specs, out, verdicts, notes, o.no_shots, title, single)


if __name__ == "__main__":
    main()
