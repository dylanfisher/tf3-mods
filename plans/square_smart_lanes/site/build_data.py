# /// script
# requires-python = ">=3.11"
# ///
"""Data files for the Smart Lanes microsite (site/src/mods/square_smart_lanes/). Data only, never HTML: every
sentence around the numbers lives in the site's manifest (bench.ts, data.ts, ...).

Reads the archived game logs (.cache/logs/, tools/game_logs.py), the bench ledger and the test timings, and writes:

  bench/<session>_<sheet>/data.json   one page per Stress Test bench run (generic run-compare kind, data version 3):
                                      runs = the twin modes (game lanes, Smart Lanes, the measuring modes), units =
                                      the test sets (one junction per twin), metrics per twin from tools/flow_report.py
                                      and tools/bench_report.py (the same numbers as `make bench`), the treatment check,
                                      and per test and comparison the pair statistics (notes.comparisons)
  bench/<session>_<sheet>/shots/*.jpg the bench's own screenshots (BENCH_SHOT, one per twin of the first set of each
                                      test), from the game's screenshot folder, downscaled to 1920 px JPEG; the local
                                      path is never written anywhere
  data/bench-pairs.json               every A / B pair of those benches (data-explorer, tools/site_table.py format)
  data/bench-twins.json               every twin of those benches
  data/showcase-pairs.json            the Lights showcase runs 3-6 (tools/flow_report.py pairs, today's parser)
  data/audit-junctions.json           every junction audit line ([SQRL] AUDIT) in the archive, latest per session,
                                      source and node
  data/audit-jobs.json                every AUDIT_SUMMARY line (one per automatic job)
  data/perf-slow.json                 every SQPERF slow line of square_smart_lanes (a call over 16 ms)
  data/tests.json                     the offline tests of tests/square_smart_lanes/ with their last quick-mode time
  shots/*.jpg                         the screenshots picked for the site (PICKS below, copied from the Desktop
                                      originals once; a missing original keeps the copy)
  gallery.json                        the facet manifest of the site's screenshot gallery (generic image-grid kind):
                                      plans/square_smart_lanes/shots/ (CURATED), site/shots/ (PICKS) and the bench shots
  twins.json                          the facet manifest of the twins wall (image-grid matrix junction x twin, grouped
                                      by bench run): every bench screenshot with its twin's speed
  showcase.json                       every bench set shot as both game lanes and Smart Lanes: the two screenshots and
                                      both twins' speed and cars per minute (the Showcase page's before / after sliders)

Usage: uv run plans/square_smart_lanes/site/build_data.py [--no-shots]   (--no-shots: keep the copied images)
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import math
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
import bench_report as br  # noqa: E402
import flow_report as fr  # noqa: E402
from site_table import table  # noqa: E402

PLANS = ROOT / "plans/square_smart_lanes"
SITE = PLANS / "site"
LOGS = ROOT / ".cache/logs"

# The bench runs shown on the site: (session, sheet, page title). Partial runs (stopped before BENCH_DONE) are marked.
BENCHES = [
    ("2026-10-13_0610_session", "s1", "Sheet 1: two-lane roundabouts and a lane drop"),
    ("2026-10-13_0610_session", "s2", "Sheet 2: Channelized Junction and diamond interchange"),
    ("2026-10-13_0733_bench-s3-683079", "s3", "Sheet 3: lit T-junctions and crossroads"),
    ("2026-10-13_0837_bench-micro-560595", "micro", "Micro bench: 3- and 4-lane roundabouts (stopped early)"),
    ("2026-10-13_0923_bench-micro-331773", "micro", "Micro bench v2: six ring layouts (stopped early)"),
    ("2026-10-13_2341_bench-s4-774314", "s4", "Sheet 4 v2: town roundabout, spiral"),
    ("2026-10-14_0027_bench-s4-487199", "s4", "Sheet 4 v3: town roundabout with mid nodes"),
    ("2026-10-14_0133_session", "s4", "Sheet 4 v4: mid-node rings of 2, 3 and 4 lanes"),
    ("2026-10-14_0201_bench-s4-176702", "s4", "Sheet 4 v5: plain against mid-node rings"),
]
SHOWCASE = ["2026-10-13_0118_top-up-148916", "2026-10-13_0205_top-up-61157", "2026-10-13_0356_top-up-779299",
            "2026-10-13_0447_top-up-726115"]

MODES = {
    "game": "Game lanes",
    "sl": "Smart Lanes",
    "sl_keeplights": "Smart Lanes, game's lights",
    "sl_lock": "Smart Lanes, curb turn locked",
    "sl_phases": "Smart Lanes phases",
    "sl_fan": "Full fan",
    "sl_exitfan": "Exit-lane fan",
    "sl_rturbo": "Turbo",
    "sl_rmatch": "Matched lanes",
    "sl_rout1": "Outer lane exits only",
    "sl_r2exit": "Two outer lanes exit",
    "sl_rspiral": "Spiral",
    "sl_rspread": "Turbo plus center lanes",
    "sl_rsplit": "Split spiral",
    "sl_rmid": "Mid-node lane changes",
}
GEOM = {"plain": "plain ring", "mid": "mid-node ring"}
TESTS = {
    "rb4": "Roundabout, 2 lanes, 4 arms",
    "drop": "Lane drop, 3 to 2 lanes",
    "cht": "Channelized T-junction (slip lanes)",
    "dia": "Diamond interchange",
    "lt22": "T-junction with traffic lights, 2 x 2 lanes",
    "lx": "Crossroads with traffic lights",
    "rb4l": "Roundabout, 4 lanes",
    "rb3": "Roundabout, 3 lanes (highway ring)",
    "rb2": "Roundabout, 2 lanes",
    "rb2t": "Roundabout, 2 lanes, town street arms",
    "rb2tm": "Roundabout, 2 lanes, town street arms, mid nodes",
    "rb3m": "Roundabout, 3 lanes, mid nodes",
    "rb4lm": "Roundabout, 4 lanes, mid nodes",
    "rb2v": "Roundabout, 2 lanes, town street arms: plain and mid-node ring",
    "rb3v": "Roundabout, 3 lanes: plain and mid-node ring",
    "rb4v": "Roundabout, 4 lanes: plain and mid-node ring",
}
VARIANTS = {
    "RB4_2L": "2-lane ring", "Lane_drop_3-2": "3 to 2 lanes", "Channel_T": "Channelized T", "Diamond_S": "Diamond, small",
    "T_2x2": "T 2x2", "2x2_X": "2x2 crossroads", "3x3_X": "3x3 crossroads", "3x2_X": "3x2 crossroads",
    "RB_4-lane": "4-lane ring", "RB_3-lane": "3-lane ring", "RB_2-lane": "2-lane ring", "RB_2L_town": "2-lane ring, town arms",
    "RB_2L_town_mid": "2-lane ring, town arms, mid nodes", "RB_3-lane_mid": "3-lane ring, mid nodes",
    "RB_4-lane_mid": "4-lane ring, mid nodes",
}

# Captions of the curated captures in plans/square_smart_lanes/shots/ (file stem -> subject, view, title).
CURATED = {
    "01-ring-lanes": ("tool", "oblique", "Chained roundabouts with the Smart Lanes tool's lane view"),
    "02-ring-select": ("tool", "oblique", "A whole roundabout selected: the tool's hover card"),
    "03-junction-hover": ("tool", "oblique", "One roundabout junction hovered: each entry lane its own ring lane"),
    "04-busy-road": ("traffic", "street", "Rush hour on a test map's link road"),
    "05-showcase-map": ("bench", "aerial", "A Lights showcase map: twin junctions between test towns"),
    "06-roundabout-queue": ("roundabout", "oblique", "A roundabout with smart lanes under load"),
    "07-crossing-phases": ("lights", "top-down", "A lit crossroads and the game's Crossing window"),
    "08-bench-group": ("bench", "top-down", "One bench group: a junction fed by its own towns"),
    "09-roundabout-top": ("roundabout", "top-down", "A two-lane roundabout from above during a bench run"),
    "10-bench-map": ("bench", "aerial", "A whole bench map of twin junctions"),
    "11-grid-town": ("bench", "aerial", "A 2,400-people grid town of a test map"),
    "12-multi-select": ("tool", "aerial", "Shift+click: many junctions of a city selected at once"),
    "15-micro-rings": ("bench", "aerial", "Micro bench: test towns linked by roundabouts"),
    "16-district-select": ("tool", "aerial", "A district's junctions selected, their lanes drawn"),
    "17-district-panel": ("tool", "interface", "The tool panel: 50 junctions selected, smart lanes on 38"),
    "18-ring-mid-nodes": ("roundabout", "top-down", "Mid-node lane changes (orange) between a roundabout's arms"),
}

# Screenshots picked for the site from the Desktop captures of the test sessions (date and time of the capture,
# local time, as in the file name) -> (site file name, subject, view, title). Copied once into site/shots/.
PICKS = {
    "2026-10-11 at 1.15.48 PM": ("2026-10-11-roundabout-interchange-tool", "tool", "oblique", "A Roundabout Interchange ring selected in the tool"),
    "2026-10-11 at 2.07.28 PM": ("2026-10-11-busy-roundabout-tool", "roundabout", "oblique", "A busy two-lane roundabout, one junction selected"),
    "2026-10-11 at 6.40.49 PM": ("2026-10-11-street-hover", "tool", "top-down", "Hovering a street: the junctions at both ends of the stretch"),
    "2026-10-11 at 7.11.27 PM": ("2026-10-11-channelized-x-lanes", "slip", "oblique", "A Channelized Junction (X) with its lane view"),
    "2026-10-11 at 8.06.41 PM": ("2026-10-11-splitter-ring-lanes", "roundabout", "oblique", "A roundabout with splitter islands: 12 junctions selected"),
    "2026-10-11 at 8.08.10 PM": ("2026-10-11-roundabout-interchange-lanes", "interchange", "oblique", "Roundabout Interchange: ring and ramp junctions selected"),
    "2026-10-11 at 8.16.59 PM": ("2026-10-11-channelized-x-closeup", "slip", "top-down", "Lane view of a Channelized Junction's center and slip nodes"),
    "2026-10-11 at 8.44.50 PM": ("2026-10-11-parclo-lanes", "interchange", "oblique", "A parclo interchange's ramp junctions selected"),
    "2026-10-11 at 11.57.48 PM": ("2026-10-11-hamburger-ring-lanes", "roundabout", "oblique", "A hamburger roundabout's lane view"),
    "2026-10-11 at 11.58.45 PM": ("2026-10-11-oval-ring-lanes", "roundabout", "oblique", "An oval roundabout with splitter islands"),
    "2026-10-11 at 11.59.46 PM": ("2026-10-11-ramp-junction-lanes", "crossroads", "oblique", "A ramp meeting a divided road: no turn across the median"),
    "2026-10-12 at 1.43.00 AM": ("2026-10-12-crossing-phases", "lights", "top-down", "The light-phase probe: a lit crossroads in the Crossing window"),
    "2026-10-12 at 12.11.43 AM": ("2026-10-12-slip-junction-lights", "lights", "oblique", "A slip-lane junction with the game's traffic light"),
    "2026-10-12 at 12.17.23 AM": ("2026-10-12-three-arm-ring-tool", "roundabout", "oblique", "A three-arm roundabout with splitter islands selected"),
    "2026-10-12 at 12.21.01 AM": ("2026-10-12-ring-arm-lanes", "roundabout", "close-up", "Ring arm junctions: entries (teal) and exits (orange) lane by lane"),
    "2026-10-12 at 12.21.04 AM": ("2026-10-12-ring-arm-lanes-2", "roundabout", "close-up", "The same arm from the other side"),
    "2026-10-12 at 2.52.03 PM": ("2026-10-12-lit-crossroads-queue", "lights", "top-down", "Queues at a lit 2x2 crossroads of the first Lights showcase"),
    "2026-10-12 at 4.05.27 PM": ("2026-10-12-phase-arrows", "lights", "top-down", "One light phase: red and green turn arrows at a busy crossroads"),
    "2026-10-13 at 1.38.10 PM": ("2026-10-13-panel-t-junction", "tool", "interface", "Tool panel before rev 5: a T-junction, smart lanes applied"),
    "2026-10-13 at 1.43.07 PM": ("2026-10-13-panel-slip-lane", "tool", "interface", "Rev 5 panel: a slip lane leaving the road, lanes in words"),
    "2026-10-13 at 1.43.17 PM": ("2026-10-13-panel-custom-lanes", "tool", "interface", "Rev 5 panel: a roundabout with custom lanes"),
    "2026-10-13 at 1.43.21 PM": ("2026-10-13-panel-smart-lanes", "tool", "interface", "Rev 5 panel: the same roundabout after Apply"),
    "2026-10-13 at 4.50.44 PM": ("2026-10-13-mid-node-request", "roundabout", "top-down", "The request: lane changes on nodes between the arms (red)"),
    "2026-10-13 at 5.40.45 PM": ("2026-10-13-bench-ring-hover", "bench", "oblique", "A Sheet 4 ring hovered in the tool during a bench run"),
    "2026-10-14 at 11.17.33 AM": ("2026-10-14-t-junction-bus-turn", "crossroads", "close-up", "A T-junction's lanes during the bus-turn test (rev 7)"),
}
SUBJECTS = [
    ("roundabout", "Roundabouts"), ("slip", "Slip lanes"), ("crossroads", "Crossroads and T-junctions"),
    ("lights", "Traffic lights"), ("interchange", "Interchanges"), ("tool", "The tool"), ("traffic", "Traffic"),
    ("bench", "Test maps and benches"),
]
VIEWS = [("top-down", "Top-down"), ("oblique", "Oblique"), ("close-up", "Close-up"), ("aerial", "Aerial"),
         ("street", "Street level"), ("interface", "Interface")]

SHOT_RE = re.compile(r"Screenshot: wrote (.+\.png)\s*$")
DESKTOP = Path.home() / "Desktop"


def log_path(session: str) -> Path:
    out = subprocess.check_output(["uv", "run", "-q", str(ROOT / "tools/game_logs.py"), "path", session], text=True, cwd=ROOT)
    return Path(out.strip().splitlines()[-1])


def mode_label(ab: str) -> str:
    mode, _, geom = ab.partition("@")
    base = MODES.get(mode, mode)
    return f"{base} ({GEOM.get(geom, geom)})" if geom else base


def run_id(ab: str) -> str:
    return ab.replace("@", "-").replace("_", "-")


def r(v, d=2):
    return None if v is None or (isinstance(v, float) and math.isnan(v)) else round(v, d)


def quart(vals: list[float]) -> list[float] | None:
    v = sorted(x for x in vals if x is not None)
    if not v:
        return None

    def q(p):
        k = (len(v) - 1) * p
        lo, hi = math.floor(k), math.ceil(k)
        return v[lo] + (v[hi] - v[lo]) * (k - lo)

    return [round(q(0.25), 2), round(q(0.5), 2), round(q(0.75), 2), round(v[0], 2), round(v[-1], 2)]


def sign_p(w: int, l: int) -> float | None:
    n = w + l
    if not n:
        return None
    k = min(w, l)
    p = sum(math.comb(n, i) for i in range(k + 1)) / 2**n * 2
    return round(min(1.0, p), 3)


def bench_shots(path: Path, sheet: str) -> dict[str, Path]:
    """zone id -> the PNG the game wrote right before its BENCH_SHOT line (this sheet only)."""
    last: Path | None = None
    out: dict[str, Path] = {}
    for line in fr.read_lines(path)[0]:
        m = SHOT_RE.search(line)
        if m:
            last = Path(m[1])
            continue
        if "[SQST] BENCH_SHOT " in line and f" sheet={sheet} " in line and " ok=true" in line and last is not None:
            zid = br.kv_of(line.split("BENCH_SHOT", 1)[1]).get("id", "").split(":")[-1]
            if zid:
                out[zid] = last
            last = None
    return out


# Sheets 1-3 took their bench shots from high above (the junction a few percent of the frame): those are cut to the
# center, 1 / ZOOM of the frame each way, at the capture's own resolution (no upscaling).
ZOOM = {"s1": 2.5, "s2": 2.5, "s3": 2.5}


def to_jpeg(src: Path, dest: Path, width: int = 1920, zoom: float = 1.0) -> bool:
    if not src.is_file():
        return dest.is_file()
    dest.parent.mkdir(parents=True, exist_ok=True)
    if zoom > 1:
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(src)], check=True, capture_output=True, text=True).stdout
        w, h = (int(re.search(rf"{k}: (\d+)", out)[1]) for k in ("pixelWidth", "pixelHeight"))
        cmd = ["sips", "-c", str(round(h / zoom)), str(round(w / zoom))]
    else:
        cmd = ["sips", "-Z", str(width)]
    subprocess.run([*cmd, "-s", "format", "jpeg", "-s", "formatOptions", "82", str(src), "--out", str(dest)], check=True, capture_output=True)
    return True


def build_bench(session: str, sheet: str, title: str, copy: bool, pairs_out: list, twins_out: list) -> dict:
    path = log_path(session)
    b = br.read_bench([path], sheet)
    if not b.sheet:
        raise SystemExit(f"{session}: no BENCH_START of sheet {sheet}")
    rep = fr.parse([path])
    gen = br.run_gen(b, rep)
    rows, excluded = br.build_rows(b, rep)
    page = f"{session.split('_')[0]}_{session.split('_')[1]}_{sheet}"
    out_dir = SITE / "bench" / page
    out_dir.mkdir(parents=True, exist_ok=True)
    shots = bench_shots(path, sheet)
    built = f"{session[:10]} {session[11:13]}:{session[13:15]}"

    # twins of this run, per test and pair
    zones = [st for st in rep.zones.values() if st.key[0] == "sc" and st.gen == gen and st.kind.startswith("test:")]
    order: list[str] = []
    for t in b.tests.values():
        for ab in t.twins:
            if ab not in order:
                order.append(ab)
    for st in zones:
        if st.ab not in order:
            order.append(st.ab)
    first = list(order)
    order.sort(key=lambda a: (0 if a.split("@")[0] == "game" else 1 if a.split("@")[0] == "sl" else 2, first.index(a)))
    runs = []
    for ab in order:
        runs.append({"id": run_id(ab), "label": mode_label(ab), "kind": "game" if ab.split("@")[0] == "game" else "smart",
                     "mode": ab, "session": session})
    units_by: dict[tuple[str, str], dict] = {}
    for st in sorted(zones, key=lambda z: (list(b.tests).index(z.kind[5:]) if z.kind[5:] in b.tests else 99, z.pair, z.key[2])):
        test = st.kind.split(":", 1)[1]
        key = (test, st.pair)
        u = units_by.setdefault(key, {"test": test, "pair": st.pair, "variant": st.type, "m": {}, "ids": {}})
        zid = st.key[2]
        shot = None
        if zid in shots and copy:
            dest = out_dir / "shots" / f"{zid}.jpg"
            if to_jpeg(shots[zid], dest, zoom=ZOOM.get(sheet, 1.0)):
                shot = f"shots/{zid}.jpg"
        elif (out_dir / "shots" / f"{zid}.jpg").is_file():
            shot = f"shots/{zid}.jpg"
        bad = br.treatment(b, zid, st.ab, b.tests.get(test))
        m = {"name": f"{TESTS.get(test, test)} · set {re.sub(r'^(s4|micro)?g', '', st.pair.split('#')[0])}",
             "kmh": r(st.speed_kmh()), "standing": r(st.standing_pct(), 1), "queue": r(st.queue_mean(), 1),
             "thru": r(st.thru_per_min(), 1), "samples": st.n(), "variant": VARIANTS.get(st.type, st.type), "zone": zid,
             "applied": b.applied.get(zid, 0), "skipped": b.skipped.get(zid, 0), "lightsOff": b.lights_off.get(zid, 0),
             "lightsKept": b.lights_kept.get(zid, 0), "treatment": bad, "match": st.match}
        if shot:
            m["shot"] = shot
        u["m"][run_id(st.ab)] = m
        u["ids"][run_id(st.ab)] = zid
        twins_out.append({"bench": title.split(":")[0], "date": session[:10], "test": test, "mode": st.ab,
                          "variant": st.type, "kmh": r(st.speed_kmh()), "standing": r(st.standing_pct(), 1),
                          "queue": r(st.queue_mean(), 1), "thru": r(st.thru_per_min(), 1), "samples": st.n(),
                          "check": "ok" if not bad else "failed"})
    units = []
    for i, ((test, pair), u) in enumerate(units_by.items(), 1):
        smart = next((run_id(a) for a in ("sl", "sl@plain") if run_id(a) in u["m"]), None)
        base = next((run_id(a) for a in ("game", "game@plain") if run_id(a) in u["m"]), None)
        unit = {"nn": f"{i:02d}", "ids": u["ids"], "m": u["m"], "x": {k: {"test": test, "pair": pair} for k in u["m"]}}
        if smart and base and u["m"][smart]["kmh"] is not None and u["m"][base]["kmh"] is not None:
            d = u["m"][smart]["kmh"] - u["m"][base]["kmh"]
            unit["category"] = "faster" if d > 0 else "slower"
            unit["verdict"] = f"{d:+.1f} km/h"
        units.append(unit)

    summary: dict[str, dict] = {}
    for key in ("kmh", "standing", "queue", "thru"):
        summary[key] = {}
        for run in runs:
            vals = [u["m"][run["id"]][key] for u in units if run["id"] in u["m"]]
            summary[key][run["id"]] = {"q": quart(vals), "sum": None}

    comparisons = []
    for row in rows:
        ps = row.pairs
        if not ps:
            continue
        w = sum(1 for p in ps if p["d_kmh"] > 0)
        l = sum(1 for p in ps if p["d_kmh"] < 0)
        th = [p["d_thru"] for p in ps if p["d_thru"] is not None]
        a, bb = row.compare.split(" vs ")
        comparisons.append({"test": row.test, "title": TESTS.get(row.test, row.test), "a": mode_label(a), "b": mode_label(bb),
                            "pairs": len(ps), "wins": w, "losses": l, "dKmh": r(sum(p["d_kmh"] for p in ps) / len(ps)),
                            "dStanding": r(sum(p["d_standing"] for p in ps) / len(ps), 1),
                            "dThru": r(sum(th) / len(th), 1) if th else None,
                            "thruWins": sum(1 for x in th if x > 0), "p": sign_p(w, l)})
        for p in ps:
            pairs_out.append({"bench": title.split(":")[0], "date": session[:10], "test": row.test, "compare": f"{mode_label(a)} vs {mode_label(bb)}",
                              "variant": p["variant"], "pair": p["pair"], "kmh_a": r(p["kmh_a"]), "kmh_b": r(p["kmh_b"]),
                              "d_kmh": r(p["d_kmh"]), "d_standing": r(p["d_standing"], 1), "d_queue": r(p["d_queue"], 1),
                              "thru_a": r(p["thru_a"], 1), "thru_b": r(p["thru_b"], 1), "d_thru": r(p["d_thru"], 1),
                              "samples": p["n"], "faster": "yes" if p["d_kmh"] > 0 else "no"})

    count = lambda f: [str(sum(f(u["m"][run["id"]]) for u in units if run["id"] in u["m"])) for run in runs]
    run_rows = [
        ["Twins (junctions)", *count(lambda m: 1)],
        ["Junctions written by Smart Lanes (APPLY lines)", *count(lambda m: m["applied"])],
        ["Left as the game built them (SKIP lines)", *count(lambda m: m["skipped"])],
        ["Traffic lights switched off", *count(lambda m: m["lightsOff"])],
        ["Traffic lights kept", *count(lambda m: m["lightsKept"])],
        ["Twins failing the treatment check", *count(lambda m: 1 if m["treatment"] else 0)],
    ]
    mw = br.map_wide([path], sheet)
    data = {
        "version": 3,
        "single": False,
        "seed": b.seed,
        "built": built,
        "pairing": "id",
        "header": {"title": title},
        "runs": runs,
        "units": units,
        "summary": summary,
        "notes": {
            "comparisons": comparisons,
            "excluded": [{"pair": p, "compare": c, "why": w} for p, c, w in excluded],
            "spec": b.spec,
            "complete": bool(b.done and b.done.get("ok") == "yes"),
            "towns": b.start.get("towns"),
            "pop": b.start.get("pop") or "400",
            "recordS": b.start.get("record_s"),
            "freeTurn": b.start.get("sl_free_turn"),
            "lights": b.start.get("sl_lights"),
            "phases": b.start.get("sl_phases"),
            "mapStanding": r(mw.get("standing"), 1),
        },
        "runRows": run_rows,
    }
    (out_dir / "data.json").write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    print(f"{(out_dir / 'data.json').relative_to(ROOT)}: {len(runs)} twins modes, {len(units)} sets, "
          f"{sum(1 for u in units for m in u['m'].values() if m.get('shot'))} shots, {len(comparisons)} comparisons")
    return data


def showcase_pairs() -> list[dict]:
    out = []
    for i, session in enumerate(SHOWCASE, 3):
        rep = fr.parse([log_path(session)], ignore=["entry"] if session.startswith("2026-10-13_0118") else None)
        for p in rep.pairs:
            out.append({"run": f"Run {i}", "date": session[:10], "shape": p.type, "compare": f"{mode_label(p.a)} vs {mode_label(p.b)}",
                        "pair": p.pair, "kmh_a": r(p.za.speed_kmh()), "kmh_b": r(p.zb.speed_kmh()), "d_kmh": r(p.d_speed()),
                        "d_standing": r(p.d_standing(), 1), "samples": min(p.za.n(), p.zb.n()),
                        "faster": "yes" if p.d_speed() > 0 else "no"})
    return out


def archive_lines():
    """(session, line) of every archived log, oldest first."""
    for f in sorted(LOGS.glob("*.log.gz")):
        session = f.name.removesuffix(".log.gz")
        with gzip.open(f, "rt", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                yield session, line


def scan_archive() -> tuple[list[dict], list[dict], list[dict]]:
    audit: dict[tuple, dict] = {}
    jobs, slow = [], []
    for session, line in archive_lines():
        if "[SQRL] AUDIT" in line:
            kind = "AUDIT_SUMMARY" if "[SQRL] AUDIT_SUMMARY " in line else "AUDIT" if "[SQRL] AUDIT " in line else None
            if not kind:
                continue
            kv = br.kv_of(line.split(kind, 1)[1])
            if kind == "AUDIT":
                finds = br_counts(kv.get("findings"))
                forced = br_counts(kv.get("forced"))
                main = max(finds, key=finds.get) if finds else "-"
                audit[(session, kv.get("src"), kv.get("node"))] = {
                    "date": session[:10], "session": session, "src": kv.get("src", "-"), "case": kv.get("case", "-"),
                    "shape": kv.get("shape", "-"), "finding": main, "findings": str(sum(finds.values())),
                    "kinds": ",".join(sorted(finds)) or "-", "forced": ",".join(sorted(forced)) or "-",
                    "zone": "yes" if kv.get("zid") or kv.get("zone") else "no"}
            elif kv.get("src") == "auto":
                finds = br_counts(kv.get("findings"))
                jobs.append({"date": session[:10], "session": session, "audited": kv.get("audited"), "flagged": kv.get("flagged"),
                             "findings": str(sum(finds.values())), "kinds": ",".join(sorted(finds)) or "-",
                             "clean": "yes" if kv.get("flagged") in ("0", None) else "no"})
        elif "mod=square_smart_lanes" in line and " slow=" in line and "[SQPERF]" in line:
            kv = br.kv_of(line.split("[SQPERF]", 1)[1])
            over, _, calls = (kv.get("over") or "").partition("/")
            slow.append({"date": session[:10], "session": session, "section": kv.get("slow"), "max_ms": kv.get("max"),
                         "over": over, "calls": calls})
    # sessions whose Smart Lanes had the frame budget (its job_step instrument exists)
    budget = {s["session"] for s in slow if s["section"] == "job_step"}
    for s in slow:
        s["budget"] = "yes" if s["session"] in budget else "no"
    return list(audit.values()), jobs, slow


def br_counts(text: str | None) -> dict[str, int]:
    out: dict[str, int] = {}
    for part in (text or "").split(","):
        k, _, v = part.partition(":")
        if k and k != "-" and not k.startswith("+") and v.isdigit():
            out[k] = out.get(k, 0) + int(v)
    return out


def picks(copy: bool) -> list[dict]:
    items = []
    by_stamp = {}
    if copy and DESKTOP.is_dir():
        for f in DESKTOP.glob("Screenshot *"):
            stamp = f.stem.removeprefix("Screenshot ").replace(" ", " ")
            by_stamp[stamp] = f
    for stamp, (name, subject, view, title) in PICKS.items():
        dest = SITE / "shots" / f"{name}.jpg"
        src = by_stamp.get(stamp)
        if src and copy:
            to_jpeg(src, dest, 2560)
        if not dest.is_file():
            raise SystemExit(f"{dest.relative_to(ROOT)}: missing and no original 'Screenshot {stamp}' on the Desktop")
        items.append({"file": f"shots/{dest.name}", "title": title, "subject": subject, "view": view, "date": name[:10], "set": "play"})
    return items


def gallery(play: list[dict]) -> None:
    items, dates = [], set()
    for f in sorted((PLANS / "shots").glob("*.jpg")):
        if f.stem not in CURATED:
            raise SystemExit(f"{f.name}: no caption in CURATED (build_data.py)")
        subject, view, title = CURATED[f.stem]
        date = dt.datetime.fromtimestamp(f.stat().st_mtime).date().isoformat()
        items.append({"file": f"../shots/{f.name}", "title": title, "subject": subject, "view": view, "date": date, "set": "curated"})
    items += play
    for page in sorted((SITE / "bench").glob("*/data.json")):
        d = json.loads(page.read_text(encoding="utf-8"))
        for u in d["units"]:
            for run in d["runs"]:
                m = u["m"].get(run["id"])
                if m and m.get("shot"):
                    items.append({"file": f"bench/{page.parent.name}/{m['shot']}", "title": f"{d['header']['title'].split(':')[0]}: {m['name']}, {run['label']}",
                                  "subject": "bench", "view": "top-down", "date": d["built"][:10], "set": "bench"})
    for it in items:
        dates.add(it["date"])
    used = {(k, it[k]) for it in items for k in ("subject", "view")}
    manifest = {
        "facets": [
            {"key": "subject", "label": "Subject", "values": [{"value": v, "label": l} for v, l in SUBJECTS if ("subject", v) in used]},
            {"key": "view", "label": "View", "values": [{"value": v, "label": l} for v, l in VIEWS if ("view", v) in used]},
            {"key": "date", "label": "Date", "values": [{"value": d, "label": d} for d in sorted(dates)]},
            {"key": "set", "label": "Set", "values": [{"value": "curated", "label": "Release captures"},
                                                      {"value": "play", "label": "Test sessions"},
                                                      {"value": "bench", "label": "Bench twins"}]},
        ],
        "items": items,
    }
    out = SITE / "gallery.json"
    out.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    print(f"{out.relative_to(ROOT)}: {len(items)} images")


def kind_of(mode: str) -> str:
    base = mode.split("@")[0]
    return "game" if base == "game" else "smart" if base == "sl" else "variant"


def twins_and_showcase() -> None:
    """twins.json (image-grid manifest) and showcase.json (before / after pairs) from the bench pages' data.json."""
    items, pairs = [], []
    benches, tests, modes = [], [], []
    for page in sorted((SITE / "bench").glob("*/data.json")):
        d = json.loads(page.read_text(encoding="utf-8"))
        bench = d["header"]["title"]
        short = bench.split(":")[0]
        for u in d["units"]:
            shots = {rid: m for rid, m in u["m"].items() if m.get("shot")}
            if not shots:
                continue
            test = next(iter(u["x"].values()))["test"]
            for run in d["runs"]:
                m = shots.get(run["id"])
                if not m:
                    continue
                kmh = m.get("kmh")
                items.append({"file": f"bench/{page.parent.name}/{m['shot']}", "title": f"{TESTS.get(test, test)}, {run['label']}: {kmh} km/h",
                              "bench": page.parent.name, "test": test, "mode": run["mode"], "kind": kind_of(run["mode"])})
                if page.parent.name not in [b for b, _ in benches]:
                    benches.append((page.parent.name, bench))
                if test not in [t for t, _ in tests]:
                    tests.append((test, TESTS.get(test, test)))
                if run["mode"] not in [x for x, _ in modes]:
                    modes.append((run["mode"], mode_label(run["mode"])))
            game = next((r for r in d["runs"] if r["mode"] in ("game", "game@plain") and r["id"] in shots), None)
            smart = next((r for r in d["runs"] if r["mode"] in ("sl", "sl@plain") and r["id"] in shots), None)
            if game and smart:
                g, s_ = shots[game["id"]], shots[smart["id"]]
                pairs.append({"bench": short, "page": page.parent.name, "test": test, "title": TESTS.get(test, test),
                              "before": f"plans/square_smart_lanes/site/bench/{page.parent.name}/{g['shot']}",
                              "after": f"plans/square_smart_lanes/site/bench/{page.parent.name}/{s_['shot']}",
                              "kmhGame": g.get("kmh"), "kmhSmart": s_.get("kmh"), "thruGame": g.get("thru"), "thruSmart": s_.get("thru")})
    modes.sort(key=lambda m: ({"game": 0, "smart": 1}.get(kind_of(m[0]), 2), m[0]))
    manifest = {
        "facets": [
            {"key": "bench", "label": "Bench run", "values": [{"value": v, "label": l} for v, l in benches]},
            {"key": "test", "label": "Junction", "values": [{"value": v, "label": l} for v, l in tests]},
            {"key": "mode", "label": "Twin", "values": [{"value": v, "label": l} for v, l in modes]},
            {"key": "kind", "label": "Lanes", "values": [{"value": "game", "label": "Game lanes"}, {"value": "smart", "label": "Smart Lanes"},
                                                          {"value": "variant", "label": "Test layouts"}]},
        ],
        "items": items,
    }
    (SITE / "twins.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    (SITE / "showcase.json").write_text(json.dumps({"version": 1, "pairs": pairs}, indent=1) + "\n", encoding="utf-8")
    print(f"plans/square_smart_lanes/site/twins.json: {len(items)} twins; showcase.json: {len(pairs)} pairs")


def write(name: str, rows: list[dict], keys: list[str], source: str, num: set[str]) -> None:
    out = SITE / "data" / name
    out.parent.mkdir(parents=True, exist_ok=True)
    stringify = [{k: "" if v is None else str(v) for k, v in row.items()} for row in rows]
    modified = max((row.get("date", "") for row in rows), default=dt.date.today().isoformat()) or dt.date.today().isoformat()
    data = table(stringify, keys, source, modified, num=num)
    out.write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"{out.relative_to(ROOT)}: {data['rows']} rows, {len(data['columns'])} columns, {out.stat().st_size // 1024} KB")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--no-shots", action="store_true", help="keep the copied images (no screenshot folder needed)")
    a = ap.parse_args()
    copy = not a.no_shots
    pairs, twins = [], []
    for session, sheet, title in BENCHES:
        build_bench(session, sheet, title, copy, pairs, twins)
    write("bench-pairs.json", pairs, ["bench", "date", "test", "compare", "variant", "pair", "faster", "kmh_a", "kmh_b", "d_kmh",
                                      "d_standing", "d_queue", "thru_a", "thru_b", "d_thru", "samples"],
          "bench logs (tools/bench_report.py)", {"kmh_a", "kmh_b", "d_kmh", "d_standing", "d_queue", "thru_a", "thru_b", "d_thru", "samples"})
    write("bench-twins.json", twins, ["bench", "date", "test", "mode", "variant", "check", "kmh", "standing", "queue", "thru", "samples"],
          "bench logs (tools/flow_report.py)", {"kmh", "standing", "queue", "thru", "samples"})
    write("showcase-pairs.json", showcase_pairs(), ["run", "date", "shape", "compare", "pair", "faster", "kmh_a", "kmh_b", "d_kmh",
                                                    "d_standing", "samples"],
          "Lights showcase logs (tools/flow_report.py)", {"kmh_a", "kmh_b", "d_kmh", "d_standing", "samples"})
    audit, jobs, slow = scan_archive()
    write("audit-junctions.json", audit, ["date", "session", "src", "case", "shape", "finding", "kinds", "findings", "forced", "zone"],
          "[SQRL] AUDIT lines", {"findings"})
    write("audit-jobs.json", jobs, ["date", "session", "clean", "audited", "flagged", "findings", "kinds"],
          "[SQRL] AUDIT_SUMMARY lines", {"audited", "flagged", "findings"})
    write("perf-slow.json", slow, ["date", "session", "budget", "section", "max_ms", "over", "calls"],
          "[SQPERF] slow lines", {"max_ms", "over", "calls"})
    timings_file = ROOT / ".cache/test_timings.json"
    if timings_file.exists():
        timings = json.loads(timings_file.read_text(encoding="utf-8"))
        rows = []
        for key, tests in sorted(timings.items()):
            if not key.startswith("tests/square_smart_lanes/") or key.endswith("[full]"):
                continue
            file = key.split("/")[-1].removesuffix(".lua").removeprefix("test_")
            rows += [{"file": file, "test": name, "seconds": f"{secs:.3f}"} for name, secs in tests.items()]
        modified = dt.datetime.fromtimestamp(timings_file.stat().st_mtime).date().isoformat()
        for row in rows:
            row["date"] = modified
        write("tests.json", rows, ["file", "test", "seconds"], "test_timings.json", {"seconds"})
    gallery(picks(copy))
    twins_and_showcase()
    return 0


if __name__ == "__main__":
    sys.exit(main())
