# /// script
# requires-python = ">=3.11"
# ///
"""Stress Test bench report (plans/square_stress_test/BENCH.md): one bench sheet's run -> a draft RESULTS.md entry.

Reads the log of a bench session (default: the last one, `make bench`; `LOG=<session>` for another):

  [SQST] BENCH_START sheet= spec= seed= ... sl_lights= sl_free_turn= sl_phases= sl_modes=   (one per press)
  [SQST] BENCH_TEST sheet= id= title= ... twins= compare=sl:game,sl:sl_keeplights sets=placed/wanted ...
  [SQST] BENCH_PHASE / BENCH_TWIN / BENCH_SHOT / BENCH_DONE / BENCH_ABORT
  [SQST] showcase zone id= pair= ab= ... test= variant= approach=     (the twins; tools/flow_report.py joins FLOW lines)
  [SQRL] APPLY / SKIP / LIGHTS ... zid=<zone id>                      (Smart Lanes: which twin got what)

and writes, per test and comparison: the pairs (delta km/h, standing, queue, thru/min), wins / losses, the sign test,
Wilcoxon signed-rank and a Holm-adjusted p over the sheet's comparisons; a treatment check per twin (every Smart Lanes
twin written by Smart Lanes, every game twin skipped, the lights twins' lights kept / switched off: a pair whose twins
did not get their modes is left out); the sampler's health and the saturation; pooled results of every earlier run of
the same spec from the ledger (`plans/square_smart_lanes/bench_ledger.json`).

  uv run tools/bench_report.py LOG            # draft to stdout and .cache/bench/<session>.md
  ... --record                                # also: append the pairs to the ledger, the entry to RESULTS.md "Runs"
  ... --warmup 180 --min-samples 5
"""

from __future__ import annotations

import argparse
import itertools
import json
import math
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import flow_report as fr  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / "plans" / "square_smart_lanes" / "bench_ledger.json"
RESULTS = ROOT / "plans" / "square_smart_lanes" / "RESULTS.md"
OUT_DIR = ROOT / ".cache" / "bench"

KV = re.compile(r"([A-Za-z_]\w*)=(\S*)")
SQ = re.compile(r"\[(SQST|SQRL)\] (\S+)(.*)$")
SL_TWINS = {"sl", "sl_keeplights", "sl_lock", "sl_phases", "sl_exitfan", "sl_fan"}
LIGHT_TESTS_KIND = {"rb"}  # tests whose sl twins lose lights (rings, slip nodes) with the setting On


def kv_of(text: str) -> dict[str, str]:
    return {k: v for k, v in KV.findall(text)}


@dataclass
class BenchTest:
    id: str
    title: str
    kind: str
    twins: list[str]
    compare: list[tuple[str, str]]
    sets: str
    towns: int


@dataclass
class Bench:
    sheet: str = ""
    spec: str = ""
    seed: str = ""
    start: dict = field(default_factory=dict)
    tests: dict[str, BenchTest] = field(default_factory=dict)
    phases: list[str] = field(default_factory=list)
    done: dict | None = None
    abort: dict | None = None
    shots: int = 0
    record_speed: str = ""
    zones_run: str = ""  # its "showcase zones sent run=" (the Showcase generation flow_report keys its zones by)
    tests_derived: bool = False  # no BENCH_TEST lines: the tests come from the zone lines
    zones: dict[str, dict] = field(default_factory=dict)          # zone id -> its showcase zone line
    applied: dict[str, int] = field(default_factory=lambda: defaultdict(int))   # zid -> APPLY lines
    skipped: dict[str, int] = field(default_factory=lambda: defaultdict(int))   # zid -> SKIP zone_game mentions
    unchanged: dict[str, int] = field(default_factory=lambda: defaultdict(int))  # zid -> SKIP reason=same|plain (looked at, left)
    skip_kinds: dict[str, set] = field(default_factory=lambda: defaultdict(set))  # zid -> kinds of its APPLY / same|plain SKIP lines
    geometry_bad: dict[str, str] = field(default_factory=dict)  # zone id -> BENCH_TWIN geometry=bad text
    layouts: dict[str, set] = field(default_factory=lambda: defaultdict(set))  # zid -> layout= of its APPLY / SKIP same lines
    rsplit: dict[str, dict] = field(default_factory=dict)  # zid -> its last [SQRL] RSPLIT line (sl_rsplit: mids= or fallback=)
    defaults: dict[str, set] = field(default_factory=lambda: defaultdict(set))  # zid -> default= of its ring APPLY lines
    turbo: dict[str, set] = field(default_factory=lambda: defaultdict(set))  # zid -> turbo= of its ring APPLY lines
    splits: dict[str, dict] = field(default_factory=dict)  # zid -> its last [SQRL] SPLIT line (Smart Lanes splitting the ring)
    rings_of: dict[str, set] = field(default_factory=lambda: defaultdict(set))  # zid -> ring keys of its APPLY / SKIP lines
    ring_pending: dict[str, bool] = field(default_factory=dict)  # ring key -> an APPLY not yet followed by a WRITE success=true
    ring_refused: dict[str, bool] = field(default_factory=dict)  # ring key -> a WRITE success=false seen
    lights_off: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    lights_kept: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    lit: dict[str, int] = field(default_factory=dict)            # zone id -> lit junction nodes at the read
    mode: dict = field(default_factory=dict)                     # the [SQRL] MODE line
    summary: str = ""
    entries: str = ""
    idle: list[str] = field(default_factory=list)


def read_bench(paths: list[Path], sheet: str | None = None, seed: str | None = None) -> Bench:
    """The last BENCH_START in the logs (of that sheet / seed when given) and everything after it up to the next one."""
    lines: list[str] = []
    for p in paths:
        lines += fr.read_lines(p)[0]
    start_i, end_i = None, None
    for i, line in enumerate(lines):
        if "[SQST] BENCH_START " in line:
            kv = kv_of(line.split("BENCH_START", 1)[1])
            if (sheet is None or kv.get("sheet") == sheet) and (seed is None or kv.get("seed") == str(seed)):
                start_i, end_i = i, None
            elif start_i is not None and end_i is None:
                end_i = i
    b = Bench()
    if start_i is None:
        return b
    # the MODE line comes at the load, before the press
    for line in lines[:start_i]:
        if "[SQRL] MODE " in line:
            b.mode = kv_of(line.split("[SQRL] MODE", 1)[1])
    # zid= lines count only while this run's zones are the ones Smart Lanes holds: from its "showcase zones sent run=R"
    # (or Smart Lanes' "ZONES op=set run=R") to the next zones set / clear of another run. Zone ids repeat across sheets
    # (g10a in sheet 1 and in sheet 2), so a line of another sheet's zones must never count here.
    our_run: str | None = None
    active = False
    for line in lines[start_i:end_i]:
        m = SQ.search(line)
        if not m:
            continue
        mod, kind, rest = m[1], m[2], m[3]
        kv = kv_of(rest)
        if mod == "SQST":
            if kind == "BENCH_START":
                b.start, b.sheet, b.spec, b.seed = kv, kv.get("sheet", ""), kv.get("spec", ""), kv.get("seed", "")
            elif kind == "BENCH_TEST":
                comp = [tuple(c.split(":", 1)) for c in kv.get("compare", "").split(",") if ":" in c]
                b.tests[kv["id"]] = BenchTest(kv["id"], kv.get("title", "").replace("_", " "), kv.get("kind", ""),
                                              kv.get("twins", "").split(","), comp, kv.get("sets", "?"),
                                              int(kv.get("towns", "0") or 0))
            elif kind == "BENCH_PHASE":
                b.phases.append(kv.get("phase", "?"))
                if kv.get("phase") == "record":
                    b.record_speed = kv.get("speed", "")
            elif kind == "BENCH_DONE":
                b.done = kv
            elif kind == "BENCH_ABORT":
                b.abort = kv
            elif kind == "BENCH_SHOT":
                b.shots += 1
            elif kind == "BENCH_TWIN":
                b.lit[kv.get("id", "?")] = int(kv.get("lit_nodes", "0") or 0)
                if kv.get("geometry") == "bad":
                    b.geometry_bad[kv.get("id", "?")] = kv.get("what", "?") + " " + kv.get("lanes", kv.get("n", ""))
            elif kind == "showcase" and rest.startswith(" zone ") and "test" in kv:
                b.zones[kv["id"]] = kv
            elif rest.startswith(" summary seed=") and kind.startswith("bench_"):
                # the run's own summary ("bench_s1 summary seed=..."), not its lock pass's ("bench_s1_lock summary pass=...")
                b.summary = rest.strip()
            elif rest.startswith(" entries ") and kind.startswith("bench_"):
                b.entries = rest.strip()
            elif "smart_lanes idle=" in rest:
                b.idle.append(kv.get("idle", "?"))
            elif kind == "showcase" and rest.startswith(" zones sent "):
                if our_run is None:
                    our_run, active = kv.get("run"), True
                    b.zones_run = our_run or ""
                else:
                    active = kv.get("run") == our_run
            elif kind == "showcase" and rest.startswith(" zones cleared ") and our_run is not None:
                active = False
        else:
            # a ring's proposal answered (no zid: matched to the twin by its ring key, BENCH.md "Micro bench")
            if kind == "WRITE" and kv.get("ring") and active:
                if kv.get("success") == "true":
                    b.ring_pending[kv["ring"]] = False
                elif kv.get("success") == "false":
                    b.ring_refused[kv["ring"]] = True
                continue
            if kind == "ZONES" and kv.get("op") in ("set", "clear") and our_run is not None:
                active = kv.get("op") == "set" and kv.get("run") == our_run
                continue
            zid = kv.get("zid")
            if not zid or not active:
                continue
            ids = zid.split(",")
            if kind == "APPLY":
                for z in ids:
                    b.applied[z] += 1
                    b.skip_kinds[z].add(kv.get("kind") or ("ring" if "ring" in kv else "?"))
                    if kv.get("layout"):
                        b.layouts[z].add(kv["layout"])
                    if kv.get("ring"):
                        b.rings_of[z].add(kv["ring"])
                        if kv.get("default"):
                            b.defaults[z].add(kv["default"])
                        if kv.get("turbo"):
                            b.turbo[z].add(kv["turbo"])
                if kv.get("ring"):
                    b.ring_pending[kv["ring"]] = True
            elif kind == "SKIP" and kv.get("reason") == "zone_game":
                for z in ids:
                    b.skipped[z] += 1
            elif kind == "SKIP" and kv.get("reason") in ("same", "plain"):
                # Smart Lanes looked at the node in the zone and left it (lanes already right, or nothing to do)
                for z in ids:
                    b.unchanged[z] += 1
                    b.skip_kinds[z].add(kv.get("kind") or ("ring" if "ring" in kv else "?"))
                    if kv.get("layout"):
                        b.layouts[z].add(kv["layout"])
                    if kv.get("ring"):
                        b.rings_of[z].add(kv["ring"])
            elif kind == "RSPLIT":
                for z in ids:
                    b.rsplit[z] = kv
            elif kind == "SPLIT":
                for z in ids:
                    b.splits[z] = kv
            elif kind == "LIGHTS":
                for z in ids:
                    if kv.get("to") == "off":
                        b.lights_off[z] += 1
                    elif kv.get("to") == "kept":
                        b.lights_kept[z] += 1
    if not b.tests and b.zones:
        derive_tests(b)
    return b


# sl-type twin modes compared with sl (sl minus it), in this order; sl vs game first
FALLBACK_VS_SL = ["sl_keeplights", "sl_lock", "sl_exitfan", "sl_phases"]


def derive_tests(b: Bench) -> None:
    """The tests from the zone lines (test=, ab=) when the log has no BENCH_TEST lines (session
    2026-10-13_0610_session: the run logged none): sl vs game, then sl vs each other Smart Lanes mode present."""
    abs_of: dict[str, list[str]] = defaultdict(list)
    kind_of: dict[str, str] = {}
    pairs_of: dict[str, set[str]] = defaultdict(set)
    for z in b.zones.values():
        t = z["test"]
        if z.get("ab") and z["ab"] not in abs_of[t]:
            abs_of[t].append(z["ab"])
        kind_of.setdefault(t, z.get("kind", ""))
        pairs_of[t].add(z.get("pair", ""))
    for t, abs_ in abs_of.items():
        comp = [("sl", "game")] if "sl" in abs_ and "game" in abs_ else []
        comp += [("sl", m) for m in FALLBACK_VS_SL if m in abs_ and "sl" in abs_]
        b.tests[t] = BenchTest(t, t, kind_of[t], abs_, comp, f"{len(pairs_of[t])}/?", 0)
    b.tests_derived = True


# --------------------------------------------------------------------------------------------- statistics


def wilcoxon(ds: list[float]) -> float | None:
    """Two-sided exact Wilcoxon signed-rank p (zeros dropped, ties by mean rank); None without data or above 20 pairs."""
    xs = [d for d in ds if d != 0]
    n = len(xs)
    if n == 0 or n > 20:
        return None
    order = sorted(range(n), key=lambda i: abs(xs[i]))
    ranks = [0.0] * n
    i = 0
    while i < n:
        j = i
        while j + 1 < n and abs(xs[order[j + 1]]) == abs(xs[order[i]]):
            j += 1
        for k in range(i, j + 1):
            ranks[order[k]] = (i + j) / 2 + 1
        i = j + 1
    w = sum(r for r, x in zip(ranks, xs) if x > 0)
    mean = sum(ranks) / 2
    obs = abs(w - mean)
    hits = 0
    for signs in itertools.product((0, 1), repeat=n):
        s = sum(r for r, sg in zip(ranks, signs) if sg)
        if abs(s - mean) >= obs - 1e-9:
            hits += 1
    return min(1.0, hits / 2 ** n)


def holm(ps: list[float | None]) -> list[float | None]:
    idx = [i for i, p in enumerate(ps) if p is not None]
    idx.sort(key=lambda i: ps[i])  # type: ignore[arg-type,return-value]
    out: list[float | None] = [None] * len(ps)
    m, run = len(idx), 0.0
    for k, i in enumerate(idx):
        run = max(run, min(1.0, (m - k) * ps[i]))  # type: ignore[operator]
        out[i] = run
    return out


@dataclass
class Row:
    test: str
    compare: str
    pairs: list[dict]

    def stats(self) -> dict:
        ds = [p["d_kmh"] for p in self.pairs]
        w, l = sum(d > 0 for d in ds), sum(d < 0 for d in ds)
        st = [p["d_standing"] for p in self.pairs if p["d_standing"] is not None]
        th = [p["d_thru"] for p in self.pairs if p["d_thru"] is not None]
        return {"n": len(ds), "mean": sum(ds) / len(ds) if ds else None, "w": w, "l": l, "t": len(ds) - w - l,
                "p": fr.sign_test(w, l), "wil": wilcoxon(ds), "standing": sum(st) / len(st) if st else None,
                "thru": sum(th) / len(th) if th else None,
                "thru_wl": (sum(d > 0 for d in th), sum(d < 0 for d in th))}


# comparisons that are equal by design (Smart Lanes PLAN.md "Ring layout variants": sl_rout1 writes the game's own
# connections on the 2-lane ring with 2 + 2 arms); shown as expected ties, never as a verdict. Not on the 3-lane
# ring with 3 + 3 arms: the same count (9), but different connections (micro v2, 2026-10-13_0923_bench-micro-331773:
# its sl_rout1 twin logged APPLY, and lost 24 cars/min to game)
EXPECTED_TIES = {("rb2", "sl_rout1 vs game"),
                 # Sheet 6: on a ring whose exits all have one lane turbo does not qualify (narrow_exit): sl_rturbo writes
                 # matched lanes (APPLY turbo=false), the same as sl_rmatch: an A/A pair, the noise of identical twins
                 ("hm2", "sl_rmatch vs sl_rturbo")}


def tie_note(test: str, compare: str) -> str:
    return " (identical by design: expected tie)" if (test, compare) in EXPECTED_TIES else ""


def f(v, d=1, sign=True) -> str:
    return fr.f(v, d, sign)


def pv(p) -> str:
    return "-" if p is None else (f"{p:.3f}" if p >= 0.001 else "<0.001")


# --------------------------------------------------------------------------------------------- build


# the Smart Lanes line kinds a test's junction must show in its Smart Lanes twins (kind=node only: Smart Lanes saw no
# junction of that kind, e.g. a lane drop whose two roads have the same lanes)
EXPECTED_KINDS = {"drop": {"drop"}, "rb4": {"ring"}, "cht": {"slip", "cross"}, "dia": {"slip", "cross"},
                  "rb2": {"ring"}, "rb3": {"ring"}, "rb4l": {"ring"}, "rb2t": {"ring"}, "rb2tm": {"ring"}, "rb3m": {"ring"}, "rb4lm": {"ring"},
                  "lu2": {"ring"}, "lu4": {"ring"}, "hm2": {"ring"}}
RING_LAYOUTS = set(fr.RING_MODES)  # zone modes whose ring APPLY lines carry layout=<mode> (Smart Lanes)
# ring layouts that write the ring's mid nodes: their last RSPLIT line must say mids > 0 (sl_rmid2, Sheet 5: Smart Lanes splits
# the ring itself first, SPLIT ... nodes_added=; a refused split falls back to sl_rturbo, RSPLIT ... fallback=sl_rturbo)
MID_LAYOUTS = {"sl_rsplit", "sl_rmid", "sl_rmid2"}
# tests whose sl twin must get Smart Lanes' shipped ring default (Sheet 6, BENCH.md "Sheet 6"): the layout and the why of its
# ring APPLY lines (`layout=sl_rmid default=one_lane_exits`), and a last RSPLIT with mids > 0 (Smart Lanes split the plain
# ring itself: SPLIT ... nodes_added=; a refused split writes sl_rspiral: the twin is excluded)
DEFAULT_RING = {"hm2": ("sl_rmid", "one_lane_exits")}


def mode_notes(b: Bench) -> list[str]:
    """The ring mode check per twin for the tests in DEFAULT_RING: the sl twin's layout, default= and mid nodes (SPLIT,
    RSPLIT), and what sl_rturbo wrote (turbo=false: matched lanes, turbo needs 2+ lane exits)."""
    out = []
    for t in b.tests.values():
        if t.id not in DEFAULT_RING:
            continue
        parts = []
        for zid, z in sorted(b.zones.items()):
            if z.get("test") != t.id:
                continue
            ab = z.get("ab", "?")
            if ab == "sl":
                rs, sp = b.rsplit.get(zid, {}), b.splits.get(zid, {})
                split = (f"refused={sp['refused']}" if sp.get("refused") else f"nodes_added={sp.get('nodes_added', '?')}") if sp else "-"
                parts.append(f"{zid} layout={','.join(sorted(b.layouts.get(zid, set()))) or '-'} "
                             f"default={','.join(sorted(b.defaults.get(zid, set()))) or '-'} split {split} mids={rs.get('mids', '-')}")
            elif ab == "sl_rturbo":
                tv = b.turbo.get(zid, set())
                parts.append(f"{zid} turbo={','.join(sorted(tv)) or '-'}"
                             + (" (matched lanes: every exit one lane)" if tv == {"false"} else ""))
        if parts:
            out.append(f"Mode check, {t.id}: " + "; ".join(parts) + ".")
    return out


def apply_tagged(b: Bench, test: str) -> bool:
    """Whether Smart Lanes tagged any APPLY line of this test's zones with zid= (session 2026-10-13_0610_session: its
    `APPLY kind=drop` lines carry no zid, so the lane-drop twins can't be checked that way)."""
    return any(b.applied.get(i) or b.unchanged.get(i) for i, z in b.zones.items() if z.get("test") == test)


def treatment(b: Bench, zid: str, ab: str, test: BenchTest | None) -> str | None:
    """Why a twin did not get its mode (None: it did, or nothing can tell). ab may carry a ring geometry ("sl_rsplit@mid",
    Sheet 4 v5): the checks use the Smart Lanes mode before the @."""
    ab = ab.split("@")[0]
    if not (b.applied or b.skipped):
        return None  # a Smart Lanes without zid= lines: no check possible
    if zid in b.geometry_bad:
        return f"geometry: the twin does not present its test ({b.geometry_bad[zid]})"
    if ab == "game":
        return "game twin written by Smart Lanes" if b.applied.get(zid) else None
    treated = b.applied.get(zid) or b.unchanged.get(zid)
    if ab in SL_TWINS and not treated and test is not None and not apply_tagged(b, test.id):
        return None  # no APPLY / SKIP line of this test carries zid=: unchecked (said under Treatment)
    if ab in SL_TWINS and not treated:
        return f"{ab} twin: Smart Lanes neither applied nor looked at it"
    if ab in RING_LAYOUTS and treated and ab not in b.layouts.get(zid, set()):
        return f"{ab} twin: no ring APPLY / SKIP same with layout={ab}"
    if ab in RING_LAYOUTS:
        # every ring the twin's lines name must have its last APPLY answered by a successful WRITE
        stuck = sorted(k for k in b.rings_of.get(zid, set()) if b.ring_pending.get(k))
        if stuck:
            why = "refused (WRITE success=false)" if any(b.ring_refused.get(k) for k in stuck) else "never answered with success"
            return f"{ab} twin: ring write {why}, ring {','.join(stuck)}"
    if ab in MID_LAYOUTS:
        # Smart Lanes logs one RSPLIT line per plan of the twin's ring: its mid nodes, or why it fell back to sl_rspiral
        rs = b.rsplit.get(zid)
        if rs is None:
            return f"{ab} twin: no RSPLIT line (a Smart Lanes without the mid-node layout?)"
        if rs.get("fallback") or (rs.get("mids") or "0") == "0":
            return f"{ab} twin: no mid nodes on its ring, written as {rs.get('fallback') or '?'} (reason={rs.get('reason') or '?'})"
    default = DEFAULT_RING.get(test.id if test else "")
    if ab == "sl" and default is not None and treated:
        # the shipped default under test (Sheet 6): the sl twin's ring written with it, on mid nodes Smart Lanes added
        layout, why = default
        if layout not in b.layouts.get(zid, set()) or why not in b.defaults.get(zid, set()):
            got = ",".join(sorted(b.layouts.get(zid, set()))) or "none"
            sp = b.splits.get(zid)
            refused = f"; SPLIT refused={sp['refused']}" if sp and sp.get("refused") else ""
            return f"sl twin: no ring APPLY layout={layout} default={why} (layout {got}{refused})"
        rs = b.rsplit.get(zid)
        if rs is None or rs.get("fallback") or (rs.get("mids") or "0") == "0":
            return f"sl twin: the default's ring has no mid nodes (RSPLIT {'missing' if rs is None else 'mids=0'})"
    want = EXPECTED_KINDS.get(test.id if test else "")
    if ab in SL_TWINS and want and b.skip_kinds.get(zid) and not (b.skip_kinds[zid] & want):
        return f"{ab} twin: Smart Lanes saw no {'/'.join(sorted(want))} junction (only {','.join(sorted(b.skip_kinds[zid]))})"
    if ab == "sl_keeplights" and not b.lights_kept.get(zid) and b.lit.get(zid, 0) == 0:
        return "sl_keeplights twin: no lit node (nothing to keep)"
    return None


def run_gen(b: Bench, rep: fr.Report) -> int | None:
    """This run's Showcase generation in flow_report's terms: by its zones run id, else the one holding its zones at
    their positions, else the last bench one."""
    gen = next((sc.gen for sc in rep.showcases if b.zones_run and sc.run == b.zones_run), None)
    for sc in ([] if gen is not None else rep.showcases):
        hit = [i for i, z in b.zones.items() if i in sc.zones and sc.zones[i].x == fr.num(z.get("x"))]
        if hit and len(hit) == len(b.zones):
            gen = sc.gen
    if gen is None:
        gens = [p.gen for p in rep.pairs if p.kind.startswith("test:")]
        gen = max(gens) if gens else None
    return gen


def ranking(b: Bench, rep: fr.Report) -> list[str]:
    """BENCH_START rank=yes (the micro bench's ring layouts): per test every twin mode's mean km/h, standing and cars
    through per minute over its sets, ranked by km/h (1 = fastest), its km/h delta to the game twin; then every mode
    pooled over the tests (mean delta to game, mean rank). Twins failing the treatment check are left out."""
    gen = run_gen(b, rep)
    if gen is None:
        return []
    per: dict[str, dict[str, list]] = defaultdict(lambda: defaultdict(list))  # test -> ab -> [ZoneStat]
    for st in rep.zones.values():
        if st.key[0] != "sc" or st.gen != gen or not st.kind.startswith("test:"):
            continue
        test = st.kind.split(":", 1)[1]
        zid = st.key[2]
        if treatment(b, zid, st.ab, b.tests.get(test)) or not st.match or st.speed_kmh() is None:
            continue
        per[test][st.ab].append(st)
    out: list[str] = []
    pooled_d: dict[str, list[float]] = defaultdict(list)
    pooled_rank: dict[str, list[int]] = defaultdict(list)

    def mean(v):
        v = [x for x in v if x is not None]
        return sum(v) / len(v) if v else None

    for test in [t for t in b.tests if t in per]:
        rows = []
        for ab, sts in per[test].items():
            rows.append((ab, len(sts), mean([z.speed_kmh() for z in sts]), mean([z.standing_pct() for z in sts]),
                         mean([z.thru_per_min() for z in sts])))
        rows.sort(key=lambda r: -(r[2] or -1e9))
        # the baseline: the game's lanes (on the plain ring when the test has twins on two geometries, Sheet 4 v5)
        game = next((r[2] for r in rows if r[0] in ("game", "game@plain")), None)
        out.append(f"Ranking, {test} (by km/h; mean over its sets):")
        out.append("")
        out.append("| rank | mode | sets | km/h | delta vs game | standing % | cars/min |")
        out.append("|---|---|---|---|---|---|---|")
        for k, (ab, n, kmh, stp, th) in enumerate(rows, 1):
            d = kmh - game if kmh is not None and game is not None else None
            out.append(f"| {k} | {ab} | {n} | {f(kmh, 1, False)} | {f(d)} | {f(stp, 0, False)} | {f(th, 1, False)} |")
            if d is not None:
                pooled_d[ab].append(d)
            pooled_rank[ab].append(k)
        out.append("")
    if len([t for t in b.tests if t in per]) >= 2:
        out.append("Ranking, pooled over the ring types (mean delta km/h vs game, mean rank):")
        out.append("")
        out.append("| mode | tests | mean delta km/h vs game | mean rank |")
        out.append("|---|---|---|---|")
        for ab in sorted(pooled_rank, key=lambda a: (mean(pooled_rank[a]), a)):
            out.append(f"| {ab} | {len(pooled_rank[ab])} | {f(mean(pooled_d[ab]))} | {mean(pooled_rank[ab]):.1f} |")
        out.append("")
    return out


def extra_lines(b: Bench, rep: fr.Report) -> list[str] | None:
    """The ranking (BENCH_START rank=yes), then this run's ring lane use section (bench Sheet 5: zone lines with mix=;
    flow_report.ring_use_lines)."""
    out = (ranking(b, rep) if b.start.get("rank") == "yes" else []) + fr.ring_use_lines(rep, run_gen(b, rep))
    # the city run (BENCH.md "City lights at scale"): no junction twins, its own section
    if b.start.get("city") == "yes":
        out += fr.render_city(rep)
    return out or None


def build_rows(b: Bench, rep: fr.Report) -> tuple[list[Row], list[tuple[str, str, str]]]:
    rows: dict[tuple[str, str], Row] = {}
    excluded: list[tuple[str, str, str]] = []
    gen = run_gen(b, rep)
    for t in b.tests.values():
        for a, bb in t.compare:
            rows[(t.id, f"{a} vs {bb}")] = Row(t.id, f"{a} vs {bb}", [])
    for p in rep.pairs:
        if gen is None or p.gen != gen or not p.kind.startswith("test:"):
            continue
        test = p.kind.split(":", 1)[1]
        key = (test, f"{p.a} vs {p.b}")
        if key not in rows:
            continue
        ida, idb = p.za.key[2], p.zb.key[2]
        bad = treatment(b, ida, p.a, b.tests.get(test)) or treatment(b, idb, p.b, b.tests.get(test))
        if bad:
            excluded.append((p.pair, key[1], f"treatment: {bad}"))
            continue
        rows[key].pairs.append({"pair": p.pair, "variant": p.type, "a": ida, "b": idb, "d_kmh": p.d_speed(),
                                "kmh_a": p.za.speed_kmh(), "kmh_b": p.zb.speed_kmh(), "d_standing": p.d_standing(),
                                "d_queue": p.d_queue(), "d_thru": p.d_thru(), "thru_a": p.za.thru_per_min(),
                                "thru_b": p.zb.thru_per_min(), "n": min(p.za.n(), p.zb.n())})
    for pair, kind, typ, why in rep.excluded:
        if kind.startswith("test:"):
            excluded.append((pair, kind.split(":", 1)[1], why))
    return list(rows.values()), excluded


def load_ledger() -> list[dict]:
    if LEDGER.is_file():
        return json.loads(LEDGER.read_text())
    return []


def map_wide(paths: list[Path], sheet: str | None = None, seed: str | None = None) -> dict:
    """FLOW_ALL means after the run's record phase began (that run: its BENCH_START to the next): standing %, capped /
    stride samples, FLOW_TARGET lines, the busiest frame and its phase."""
    lines: list[str] = []
    for p in paths:
        lines += fr.read_lines(p)[0]
    starts = [i for i, l in enumerate(lines) if "[SQST] BENCH_START " in l]
    pick = [i for i in starts if (sheet is None or f" sheet={sheet} " in lines[i]) and (seed is None or f" seed={seed} " in lines[i])]
    s0 = pick[-1] if pick else 0
    nxt = [i for i in starts if i > s0]
    end = nxt[0] if nxt else len(lines)
    rec = [i for i in range(s0, end) if "[SQST] BENCH_PHASE " in lines[i] and "phase=record" in lines[i]]
    start = rec[-1] if rec else s0
    lines = lines[:end]
    st, n, capped, strided, targets, frame_max, thru_path = 0.0, 0, 0, 0, 0, 0.0, 0
    phases_max = "-"
    for l in lines[start:]:
        if "[SQST] FLOW_ALL " in l:
            kv = kv_of(l)
            if kv.get("standing_pct") not in (None, "-"):
                st += float(kv["standing_pct"])
                n += 1
            capped += kv.get("capped") == "1"
            strided += kv.get("stride", "1") != "1"
            fm = kv.get("frame_ms_max")
            if fm not in (None, "-") and float(fm) > frame_max:
                frame_max = float(fm)
                phases_max = kv.get("frame_phase", "-")
        elif "[SQST] FLOW_TARGET " in l:
            targets += 1
        elif "[SQST] FLOW_PATHOFF" in l:
            thru_path = -1
        elif "[SQST] FLOW " in l and " thru_path=" in l and not l.rstrip().endswith("thru_path=-") and thru_path == 0:
            thru_path = 1
    return {"standing": st / n if n else None, "samples": n, "capped": capped, "strided": strided, "targets": targets,
            "frame_max": frame_max, "frame_phase": phases_max, "thru_path": thru_path}


def render(b: Bench, rows: list[Row], excluded, mw: dict, session: str, ledger: list[dict], recorded: bool,
           rank_lines: list[str] | None = None) -> str:
    out: list[str] = []
    title = entry_title(b, session)
    out.append(title)
    s = b.start
    status = "complete" if b.done and b.done.get("ok") == "yes" else (f"ABORTED in {b.abort.get('phase')}: {b.abort.get('reason')}"
                                                                       if b.abort else "incomplete (no BENCH_DONE)")
    out.append(f"Setup: {b.spec}, map {s.get('map', '?')} m, {s.get('groups', '?')} junctions, {s.get('towns', '?')} towns "
               f"(~{s.get('pop', '400')} people each); Smart Lanes {b.mode.get('phases', s.get('sl_phases', '?'))} phases, free kerb turn "
               f"{b.mode.get('free_turn', s.get('sl_free_turn', '?'))}, no lights at roundabouts and ramps "
               f"{b.mode.get('lights', s.get('sl_lights', '?'))}; record {int(s.get('record_s', '0')) // 60} game min at "
               f"{b.record_speed or s.get('speed', '?')}x, every 10 game s; run {status}; {b.shots} screenshots.")
    if b.summary:
        out.append(f"Build: {b.summary[:200]}")
    if b.entries:
        out.append(f"Entries: {b.entries}")
    if b.tests_derived:
        out.append("Tests: from the zone lines (the log has no BENCH_TEST lines): sl vs game and sl vs each other Smart Lanes "
                   "mode per test.")
    st = mw.get("standing")
    sat = st is not None and st > 50
    out.append(f"Sampler: {mw['samples']} map-wide samples recorded, map-wide standing {f(st, 0, False)} %"
               f"{' (SATURATED: speed measures queues, use thru)' if sat else ''}; capped {mw['capped']}, strided "
               f"{mw['strided']}, FLOW_TARGET {mw['targets']}, busiest frame {mw['frame_max']:.1f} ms (phase {mw.get('frame_phase', '-')}); thru by position"
               f"{', path thru off (no path element read)' if mw['thru_path'] < 0 else (', path thru read too' if mw['thru_path'] > 0 else '')}.")
    out.append("")
    # a sheet whose tests ask one question (BENCH_START pool=yes: the micro bench): a row pooling every test's pairs of
    # each comparison found in two or more tests
    if s.get("pool") == "yes":
        by_cmp: dict[str, list[Row]] = defaultdict(list)
        for r in rows:
            by_cmp[r.compare].append(r)
        rows = rows + [Row("all (pooled)", c, [p for r in rs for p in r.pairs]) for c, rs in by_cmp.items() if len(rs) >= 2]
    stats = [r.stats() for r in rows]
    adj = holm([x["p"] for x in stats])
    out.append("| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |")
    out.append("|---|---|---|---|---|---|---|---|---|---|")
    for r, x, h in zip(rows, stats, adj):
        out.append(f"| {r.test} | {r.compare}{tie_note(r.test, r.compare)} | {x['n']} | {f(x['mean'])} | {x['w']}/{x['l']}/{x['t']} | {pv(x['p'])} | {pv(h)} | "
                   f"{pv(x['wil'])} | {f(x['standing'])} | {f(x['thru'])} ({x['thru_wl'][0]}/{x['thru_wl'][1]}) |")
    out.append("")
    # pooled with earlier recorded runs of the same spec
    if ledger:
        pooled = []
        for r in rows:
            # never pool runs with another "No lights at roundabouts and ramps" setting (rows without it: unknown, kept apart)
            old = [e for e in ledger if e["spec"] == b.spec and e["test"] == r.test and e["compare"] == r.compare
                   and e.get("sl_lights") == sl_lights_of(b) and not same_run(e, session, b)]
            if not old:
                continue
            ds = [e["d_kmh"] for e in old] + [p["d_kmh"] for p in r.pairs]
            w, l = sum(d > 0 for d in ds), sum(d < 0 for d in ds)
            pooled.append(f"| {r.test} | {r.compare} | {len({(e['session'], e.get('sheet'), str(e.get('seed'))) for e in old}) + 1} | {len(ds)} | {f(sum(ds) / len(ds))} | "
                          f"{w}/{l} | {pv(fr.sign_test(w, l))} |")
        if pooled:
            out.append("Pooled with the earlier runs of this spec (ledger):")
            out.append("")
            out.append("| test | compare | runs | pairs | mean delta km/h | W/L | sign p |")
            out.append("|---|---|---|---|---|---|---|")
            out += pooled
            out.append("")
    if rank_lines:
        out += rank_lines
    out.append("Per pair (first mode minus second):")
    out.append("")
    out.append("| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |")
    out.append("|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        if r.test.startswith("all"):
            continue  # the pooled row's pairs are listed under their tests
        for p in r.pairs:
            out.append(f"| {r.test} | {r.compare} | {p['pair']} | {p['variant']} | {f(p['kmh_a'], 1, False)} / {f(p['kmh_b'], 1, False)} | "
                       f"{f(p['d_kmh'])} | {f(p['d_standing'], 0)} | {f(p['d_queue'])} | {f(p['thru_a'], 1, False)} / {f(p['thru_b'], 1, False)} |")
    out.append("")
    if excluded:
        out.append("Excluded pairs: " + "; ".join(f"{p} {c} ({w})" for p, c, w in excluded) + ".")
        out.append("")
    # treatment summary per test
    tlines = []
    for t in b.tests.values():
        ids = [i for i, z in b.zones.items() if z.get("test") == t.id]
        by_ab: dict[str, list[str]] = defaultdict(list)
        for i in ids:
            by_ab[b.zones[i].get("ab", "?")].append(i)
        parts = []
        for ab, lst in sorted(by_ab.items()):
            ap = sum(1 for i in lst if b.applied.get(i))
            un = sum(1 for i in lst if b.unchanged.get(i) and not b.applied.get(i))
            bad = sum(1 for i in lst if i in b.geometry_bad)
            sk = sum(1 for i in lst if b.skipped.get(i))
            off = sum(b.lights_off.get(i, 0) for i in lst)
            kept = sum(b.lights_kept.get(i, 0) for i in lst)
            lit = sum(1 for i in lst if b.lit.get(i, 0) > 0)
            parts.append(f"{ab} {len(lst)} (applied {ap}, unchanged {un}, skipped {sk}, lights off {off}, kept {kept}, lit at read {lit}"
                         f"{f', GEOMETRY BAD {bad}' if bad else ''})")
        tlines.append(f"{t.id}: " + ", ".join(parts) + ("" if apply_tagged(b, t.id) or not (b.applied or b.skipped) else
                      " [its Smart Lanes APPLY lines carry no zid=: the sl twins were not checked]"))
    if tlines:
        out.append("Treatment (Smart Lanes lines with zid=): " + "; ".join(tlines) + ".")
        if not (b.applied or b.skipped):
            out.append("No zid= lines: this Smart Lanes predates BENCH.md SL-3, so the twins' modes were not checked.")
        out.append("")
    notes = mode_notes(b)
    if notes:
        out += notes
        out.append("")
    out.append("Suggested verdict lines (review before adding to the Verdicts table):")
    for r, x, h in zip(rows, stats, adj):
        if x["n"] == 0:
            continue
        if tie_note(r.test, r.compare):
            out.append(f"- {r.test}, {r.compare}: identical by design (expected tie); measured {f(x['mean'])} km/h, {x['w']}/{x['l']}/{x['t']}.")
            continue
        word = "better" if (x["mean"] or 0) > 0 else "worse"
        a = r.compare.split(" vs ")[0]
        strength = "significant" if (h is not None and h <= 0.05) else ("trend" if x["p"] is not None and x["p"] <= 0.25 else "no clear effect")
        out.append(f"- {r.test}, {r.compare}: {a} {word} by {f(x['mean'])} km/h, {x['w']}/{x['n']} pairs, sign p {pv(x['p'])} "
                   f"(Holm {pv(h)}): {strength}.")
    if not recorded:
        out.append("")
        out.append("(Draft: `make bench ARGS=--record` appends these pairs to the ledger and this entry to RESULTS.md \"Runs\".)")
    return "\n".join(out) + "\n"


def sl_lights_of(b: Bench) -> str:
    """Smart Lanes' "No lights at roundabouts and ramps" in this run: its MODE line, else BENCH_START's sl_lights=."""
    return b.mode.get("lights") or b.start.get("sl_lights") or "?"


def same_run(e: dict, session: str, b: Bench) -> bool:
    """A ledger row of this run: one session can hold several sheets (or the same sheet twice): session + sheet + seed."""
    return e.get("session") == session and e.get("sheet") == b.sheet and str(e.get("seed")) == str(b.seed)


def entry_title(b: Bench, session: str) -> str:
    return f"### Bench sheet {b.sheet}: {session} (seed {b.seed})"


def record(b: Bench, rows: list[Row], session: str, text: str, ledger: list[dict]) -> None:
    keep = [e for e in ledger if not same_run(e, session, b)]
    for r in rows:
        for p in r.pairs:
            keep.append({"session": session, "sheet": b.sheet, "spec": b.spec, "seed": b.seed, "sl_lights": sl_lights_of(b), "test": r.test,
                         "compare": r.compare, "pair": p["pair"], "variant": p["variant"], "d_kmh": round(p["d_kmh"], 3),
                         "d_standing": None if p["d_standing"] is None else round(p["d_standing"], 3),
                         "d_thru": None if p["d_thru"] is None else round(p["d_thru"], 3)})
    LEDGER.write_text(json.dumps(keep, indent=1) + "\n")
    res = RESULTS.read_text()
    marker = "## Runs\n"
    if entry_title(b, session) in res:
        print(f"RESULTS.md already has {entry_title(b, session)}: entry not added again", file=sys.stderr)
        return
    if marker in res:
        res = res.replace(marker, marker + "\n" + text, 1)
    else:
        res += "\n" + marker + "\n" + text
    RESULTS.write_text(res)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="*", type=Path, help="the bench session's log (default: the live stdout.txt)")
    ap.add_argument("--warmup", type=float, default=180.0, help="game seconds dropped per zone (default 180)")
    ap.add_argument("--min-samples", type=int, default=5)
    ap.add_argument("--record", action="store_true", help="append the pairs to the ledger and the entry to RESULTS.md")
    ap.add_argument("--out", type=Path, default=OUT_DIR, help="where the draft goes (default .cache/bench)")
    ap.add_argument("--sheet", help="the run of this sheet (s1, s2, ...) when the log holds several (default: the last run)")
    ap.add_argument("--seed", help="the run with this seed")
    args = ap.parse_args()
    paths = args.logs or [fr.default_log()]
    for p in paths:
        if not p.is_file():
            raise SystemExit(f"No such log: {p}")
    b = read_bench(paths, args.sheet, args.seed)
    if not b.sheet:
        raise SystemExit("No [SQST] BENCH_START in these logs: run a bench sheet (Stress Test > Towns > Bench) first.")
    rep = fr.parse(paths, warmup=args.warmup, min_samples=args.min_samples)
    rows, excluded = build_rows(b, rep)
    session = paths[-1].name.removesuffix(".gz").removesuffix(".log")
    ledger = load_ledger()
    text = render(b, rows, excluded, map_wide(paths, args.sheet, args.seed), session, ledger, args.record, extra_lines(b, rep))
    args.out.mkdir(parents=True, exist_ok=True)
    # one session can hold several sheets (and the same sheet twice): sheet and seed in the name
    dest = args.out / f"{session}_{b.sheet}-{b.seed}.md"
    dest.write_text(text)
    print(text, end="")
    print(f"\n(draft written to {dest})")
    if args.record:
        if not (b.done and b.done.get("ok") == "yes"):
            raise SystemExit("The run did not finish (no BENCH_DONE ok=yes): not recorded.")
        record(b, rows, session, text, ledger)
        print(f"recorded: {LEDGER} and {RESULTS}")


if __name__ == "__main__":
    main()
