# /// script
# requires-python = ">=3.11"
# ///
"""Turn square_roundabouts_probe's [SQRB_PROBE] lines from stdout.txt into a report.

The DEV-ONLY mod mods/square_roundabouts_probe asks the engine which Better Roundabouts param
combinations cannot be placed and logs one line per combination (plans/square_roundabouts/PROBE.md).
This reads the last (or a chosen) probe run from the game log and writes

  plans/square_roundabouts/probe_results.md   summary: totals, failure reasons, failure rate per
                                               axis value, conditions that always fail, failing
                                               combos grouped by reason
  plans/square_roundabouts/probe_results.csv  one row per combination (every logged field)

and, for the Phase 4 search subsets (T and S lines; PROBE.md "Search runs"):

  plans/square_roundabouts/probe_search.md          minimal accepted values per pattern
  plans/square_roundabouts/probe_search.csv         one row per search job (S lines)
  plans/square_roundabouts/probe_search_trials.csv  one row per engine call (T lines)

The search CSVs accumulate over runs: rows of the parsed run replace rows with the same job id
(and candidate), others are kept, so search_splitter and a later search_radius_split end up in
one file (--fresh starts over). tools/gen_roundabouts_tuning.py turns them into the tuning table.
A run without R lines leaves probe_results.* alone, and one without S lines leaves probe_search.*.

Output names by subset (the --out-*/--search-*/--trials-csv flags override them): the Phase 3-4
sweeps (splitter6, magic, main_cw, main, all) write probe_results.*, the Phase 4 searches
(search*) probe_search.*; every other subset (smoke, the Phase 5e p5_* subsets) writes its own
files, so it never overwrites the data the tuning generator and test_engine_verdicts read:
  sweeps    plans/square_roundabouts/probe_<subset>.md / .csv
  searches  plans/square_roundabouts/probe_<subset>.md, probe_<subset>_jobs.csv, probe_<subset>_trials.csv
Entries: main (m:), magic (g:), channel (c:, Channelized Junction), interchange (x:, Roundabout
Interchange); every row carries its `entry` and `key`.

Usage:
  uv run tools/parse_probe.py [--stdout PATH] [--run N] [--out-md PATH] [--out-csv PATH] [--fresh]

--stdout defaults to <TF3 userdata>/crash_dump/stdout.txt (tools/hubconfig.py). --run picks a
run by number (1 = first in the file, -1 = last, the default); --list shows the runs.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import ROOT, userdata  # noqa: E402

PLANS = ROOT / "plans" / "square_roundabouts"
TAG = "[SQRB_PROBE] "
FIELD_RE = re.compile(r'(\w+)=(?:"([^"]*)"|(\S*))')

# axis keys per entry, in log order (mods/square_roundabouts_probe/content/probe/probe_grid.lua)
AXES = {
    # through: appended later (Phase 5c); an 11-value key = Same as arms (canon_key)
    "main": ["shape", "lanes", "radius", "arms", "splitter", "centre", "arm", "tram", "dir", "island", "signals", "through"],
    "magic": ["size", "arm", "dir", "island", "lanes"],  # lanes: appended later (see magic_lanes)
    "channel": ["layout", "main", "side", "slips", "splitter", "armlen", "dir", "island"],
    "interchange": ["layout", "highway", "level", "lanes", "radius", "cross", "slip", "armlen", "dir", "island", "year"],
}
ENTRIES = list(AXES)
GEOM = {"main": ["effR", "fork", "forced"], "magic": ["effSize", "rs"], "channel": ["setback", "cost"],
        "interchange": ["effR", "forced", "bridge", "cost"]}
# subsets whose output goes to the historic file names (see the module doc)
LEGACY_SWEEPS = {"splitter6", "magic", "main_cw", "main", "all"}
MAX_ROWS_PER_GROUP = 60


@dataclass
class Run:
    start: dict[str, str]
    notes: list[str] = field(default_factory=list)
    rows: list[dict[str, str]] = field(default_factory=list)
    progress: list[dict[str, str]] = field(default_factory=list)
    end: dict[str, str] | None = None
    trials: list[dict[str, str]] = field(default_factory=list)
    searches: list[dict[str, str]] = field(default_factory=list)


def parse_fields(body: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for m in FIELD_RE.finditer(body):
        out[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    return out


def read_runs(path: Path) -> list[Run]:
    runs: list[Run] = []
    pending: list[str] = []
    current: Run | None = None
    with path.open(encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            i = raw.find(TAG)
            if i < 0:
                continue
            rest = raw[i + len(TAG):].rstrip("\n")
            kind, _, body = rest.partition(" ")
            if kind == "START":
                current = Run(start=parse_fields(body), notes=pending)
                pending = []
                runs.append(current)
            elif kind in ("INFO", "ERROR"):
                note = f"{kind} {body}"
                if current is not None and current.end is None:
                    current.notes.append(note)
                else:
                    pending.append(note)
            elif current is None:
                continue
            elif kind == "R":
                current.rows.append(parse_fields(body))
            elif kind == "T":
                current.trials.append(parse_fields(body))
            elif kind == "S":
                current.searches.append(parse_fields(body))
            elif kind == "PROGRESS":
                current.progress.append(parse_fields(body))
            elif kind == "END":
                current.end = parse_fields(body)
                current = None
    if pending and runs and runs[-1].end is not None:
        runs[-1].notes.extend(pending)  # e.g. "probe stopped" after END
    elif pending and not runs:
        runs.append(Run(start={}, notes=pending))
    return runs


def reason(row: dict[str, str]) -> str:
    if row.get("err"):
        return "error: " + row["err"]
    msgs = row.get("msgs", "")
    if msgs:
        return msgs
    if row.get("critical") == "true":
        return "(critical, no message)"
    if row.get("mode") == "result_only":
        return "(updateFn: " + row.get("upd", "?") + ")"
    return "(not ok, no message)"


def failed(row: dict[str, str]) -> bool:
    return row.get("ok") != "true"


def md_table(header: list[str], rows: list[list[str]]) -> list[str]:
    esc = lambda s: str(s).replace("|", "\\|")  # noqa: E731
    lines = ["| " + " | ".join(header) + " |", "|" + "|".join("---" for _ in header) + "|"]
    lines += ["| " + " | ".join(esc(c) for c in r) + " |" for r in rows]
    return lines


def pct(n: int, d: int) -> str:
    return f"{100 * n / d:.0f}%" if d else "-"


def axis_rates(rows: list[dict[str, str]], axes: list[str]) -> list[str]:
    out: list[str] = []
    table: list[list[str]] = []
    for axis in axes:
        values: dict[str, list[int]] = {}
        for r in rows:
            v = r.get(axis, "-")
            values.setdefault(v, [0, 0])
            values[v][0] += 1
            values[v][1] += failed(r)
        if len(values) < 2:
            continue
        table.append([axis, ", ".join(f"{v} {pct(f, n)} ({f}/{n})" for v, (n, f) in values.items())])
    if table:
        out += md_table(["axis", "fail rate per value (fails/combos)"], table)
    return out


def always_fail(rows: list[dict[str, str]], axes: list[str], min_support: int = 3, max_len: int = 3) -> list[list[str]]:
    """Conditions (1 to max_len axis values) under which every combo fails: the minimal ones only
    (a condition is left out if a shorter part of it already always fails). Only axes that vary."""
    varying = [a for a in axes if len({r.get(a) for r in rows}) > 1]
    stats: dict[tuple, list[int]] = defaultdict(lambda: [0, 0])
    for r in rows:
        items = [(a, r.get(a, "-")) for a in varying]
        f = failed(r)
        for k in range(1, max_len + 1):
            for cond in itertools.combinations(items, k):
                s = stats[cond]
                s[0] += 1
                s[1] += f
    always = {k for k, (n, f) in stats.items() if n >= min_support and f == n}
    found = []
    for cond in always:
        if any(sub in always for k in range(1, len(cond)) for sub in itertools.combinations(cond, k)):
            continue
        n = stats[cond][0]
        found.append((len(cond), -n, " and ".join(f"{a}={v}" for a, v in cond), n))
    found.sort()
    return [[cond, str(n)] for _, _, cond, n in found]


def pivot(rows: list[dict[str, str]], row_axis: str, col_axis: str) -> list[str]:
    cols = list(dict.fromkeys(r.get(col_axis, "-") for r in rows))
    rws = list(dict.fromkeys(r.get(row_axis, "-") for r in rows))
    cell: dict[tuple[str, str], list[int]] = defaultdict(lambda: [0, 0])
    for r in rows:
        c = cell[(r.get(row_axis, "-"), r.get(col_axis, "-"))]
        c[0] += 1
        c[1] += failed(r)
    body = [[rv] + [f"{cell[(rv, cv)][1]}/{cell[(rv, cv)][0]}" if cell[(rv, cv)][0] else "" for cv in cols] for rv in rws]
    return md_table([f"{row_axis} \\ {col_axis}"] + cols, body)


def report(run: Run, run_no: int, n_runs: int, source: Path) -> str:
    rows = run.rows
    s, e = run.start, run.end
    out = [
        "# Roundabouts probe results",
        "",
        f"Generated by `tools/parse_probe.py` from `{source}` (run {run_no} of {n_runs}). "
        "Do not edit by hand; rerun the parser. How the probe works: `PROBE.md`.",
        "",
        "## Run",
        "",
    ]
    info = [
        ["subset", s.get("subset", "?")],
        ["combos logged / planned", f"{len(rows)} / {s.get('total', '?')}"],
        ["finished", "yes" if e else "no (no END line: stopped early or still running)"],
        ["position", f"x={s.get('x')} y={s.get('y')} z={s.get('z')}"],
        ["context", s.get("context", "?")],
        ["constructions", " ".join(f"{e}={s[e]}" for e in ENTRIES if e in s) or "?"],
        ["geometry module", s.get("geometry", "?")],
    ]
    if e:
        info.append(["END", f"ok={e.get('ok')} fail={e.get('fail')} errors={e.get('errors')} seconds={e.get('seconds')} steps={e.get('steps')}"])
        if e.get("seconds") and e.get("done"):
            try:
                info.append(["rate", f"{int(e['done']) / max(1.0, float(e['seconds'])):.1f} combos/s"])
            except ValueError:
                pass
    out += md_table(["", ""], info)
    if run.notes:
        out += ["", "Notes from the log:", ""] + [f"- `{n}`" for n in run.notes]

    n_ok = sum(1 for r in rows if not failed(r))
    n_fail = len(rows) - n_ok
    out += ["", "## Totals", "", f"{len(rows)} combos: {n_ok} placeable, {n_fail} not placeable."]
    modes = Counter(r.get("mode", "?") for r in rows)
    if set(modes) - {"proposal"}:
        out += ["", f"Modes: {dict(modes)} (`result_only` = makeProposalData was unusable; only the updateFn was checked)."]
    if rows and n_ok == 0 and all(r.get("ok") == "false" for r in rows) and s.get("total") and int(s["total"]) > len(rows):
        out += ["", "Only failures were logged (mod setting 'Log placeable combos' Off): rates below are meaningless."]

    fails = [r for r in rows if failed(r)]
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for r in fails:
        groups[reason(r)].append(r)
    out += ["", "## Failure reasons", ""]
    if groups:
        out += md_table(["reason (errorState.messages, joined by \\|)", "combos", "entries", "updateFn"], [
            [g, str(len(rs)), ", ".join(sorted({r.get('entry', '?') for r in rs})),
             ", ".join(f"{k} {v}" for k, v in Counter(r.get("upd") or "-" for r in rs).most_common(3))]
            for g, rs in sorted(groups.items(), key=lambda kv: -len(kv[1]))
        ])
    else:
        out.append("None.")

    for r in rows:
        if r.get("entry") == "magic" and not r.get("lanes"):
            r["lanes"] = magic_lanes(r)
        if r.get("entry") == "main" and not r.get("through"):
            r["through"] = "same"
    for entry in ENTRIES:
        er = [r for r in rows if r.get("entry") == entry]
        if not er:
            continue
        axes = AXES[entry]
        ef = [r for r in er if failed(r)]
        out += ["", f"## {entry}: {len(ef)} of {len(er)} fail", ""]
        rates = axis_rates(er, axes)
        if rates:
            out += ["### Fail rate per axis value", ""] + rates
        conds = always_fail(er, axes)
        if conds:
            out += ["", "### Conditions under which every combo fails", "",
                    "Minimal conditions of up to three axis values (none of their parts fails alone; at least 3 combos), shortest first.", ""]
            out += md_table(["condition", "combos"], conds[:80])
            if len(conds) > 80:
                out.append(f"\n... {len(conds) - 80} more.")
        if entry == "main" and ef:
            for sp in sorted({r.get("splitter", "-") for r in er}):
                sub = [r for r in er if r.get("splitter") == sp]
                out += ["", f"### Fails per arm road x arm layout (splitter {sp}; fails/combos)", ""] + pivot(sub, "arm", "arms")
        if entry == "magic" and ef:
            out += ["", "### Fails per arm road x size (fails/combos)", ""] + pivot(er, "arm", "size")
        if entry == "main" and any(r.get("through") not in (None, "", "same") for r in er):
            out += ["", "### Through road x arm layout (fails/combos)", ""] + pivot(er, "through", "arms")
            out += ["", "### Through road x centre (fails/combos; lights = Road + traffic lights)", ""] + pivot(er, "through", "centre")
        if entry == "channel":
            for sp in sorted({r.get("splitter", "-") for r in er}):
                sub = [r for r in er if r.get("splitter") == sp]
                out += ["", f"### Main road x side road (splitter {sp}; fails/combos)", ""] + pivot(sub, "main", "side")
            out += ["", "### Slip lanes x traffic side (fails/combos)", ""] + pivot(er, "slips", "dir")
        if entry == "interchange":
            out += ["", "### Layout x highway (fails/combos)", ""] + pivot(er, "layout", "highway")
            out += ["", "### Layout x level (fails/combos)", ""] + pivot(er, "layout", "level")
            out += year_check(er)

    out += ["", "## Failing combos by reason", "",
            f"Up to {MAX_ROWS_PER_GROUP} rows per reason; every row is in `probe_results.csv`. "
            "`key` replays a combo: entry tag then the param indices in .con.lua order.", ""]
    for g, rs in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        out += [f"### {g} ({len(rs)})", ""]
        for entry in ENTRIES:
            er = [r for r in rs if r.get("entry") == entry]
            if not er:
                continue
            cols = AXES[entry] + GEOM[entry] + ["upd", "key"]
            out += md_table(["entry"] + cols, [[entry] + [r.get(c, "") for c in cols] for r in er[:MAX_ROWS_PER_GROUP]])
            if len(er) > MAX_ROWS_PER_GROUP:
                out.append(f"\n... {len(er) - MAX_ROWS_PER_GROUP} more {entry} rows in the CSV.")
            out.append("")
    return "\n".join(out).rstrip() + "\n"


def year_check(rows: list[dict[str, str]]) -> list[str]:
    """Interchange: does params.year reach the updateFn? Pairs of combos that differ only in the
    year (1969 = steel bridges, 2020 = concrete) should cost differently; equal costs on every pair
    mean the engine replaced the year (TESTING.md 11.3 / 14)."""
    by_base: dict[str, dict[str, dict[str, str]]] = defaultdict(dict)
    for r in rows:
        base = r.get("key", "").rsplit(",", 1)[0]
        by_base[base][r.get("year", "?")] = r
    pairs = [(v["1969"], v["2020"]) for v in by_base.values() if "1969" in v and "2020" in v]
    if not pairs:
        return []
    priced = [(a, b) for a, b in pairs if num(a.get("cost")) is not None and num(b.get("cost")) is not None]
    same = sum(1 for a, b in priced if num(a.get("cost")) == num(b.get("cost")))
    verdict = Counter((a.get("ok"), b.get("ok")) for a, b in pairs)
    out = ["", "### Bridge type by year (steel 1969 / concrete 2020)", "",
           f"{len(pairs)} pairs differing only in the year; {len(priced)} with both costs, {same} of them at the same cost"
           + (" (every pair: the engine replaced params.year, so both builds used one bridge type)" if priced and same == len(priced) else "") + ".", ""]
    out += md_table(["ok 1969 / ok 2020", "pairs"], [[f"{k[0]} / {k[1]}", str(v)] for k, v in verdict.most_common()])
    return out


# Search runs (Phase 4) ---------------------------------------------------------------------------

SEARCH_KINDS = ["radius", "magic_size", "magic_spacing", "splitter", "tram_stub", "grid"]
DEV_FIELDS = ["devRadius", "devMagicSize", "devMagicRadius", "devMagicDistance", "devSplit", "devFork",
              "devSpread", "devLeg", "devNeck", "devNeckType", "devTramStub",
              # Phase 5e (grid searches of the Channelized Junction / Roundabout Interchange)
              "devChSlipAngle", "devChCornerGap", "devChSlipFree", "devIxClear", "devIxGamma", "devIxGoreRun", "devIxWaistGap",
              "devChSlip", "devIxAlphaMax"]


def canon_key(key: str) -> str:
    """Replay key with Magic's lanes value: 4-value Magic keys (logged before the lanes axis) = 1
    lane, so a rerun of a 1-lane search replaces their rows instead of adding duplicates."""
    if key.startswith("g:") and len(key[2:].split(",")) == 4:
        return key + ",1"
    # main keys logged before the through road axis (Phase 5c) have 11 values: Same as arms
    if key.startswith("m:") and len(key[2:].split(",")) == 11:
        return key + ",1"
    return key


def trial_id(row: dict[str, str]) -> str:
    return canon_key(row.get("key", "")) + "#" + row.get("kind", "") + "#" + row.get("fixed", "") + "#" + row.get("cand", "")


def job_id(row: dict[str, str]) -> str:
    ident = row.get("id") or (row.get("key", "") + "#" + row.get("kind", "") + "#" + row.get("fixed", ""))
    key, sep, rest = ident.partition("#")
    return canon_key(key) + sep + rest


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def merge(old: list[dict[str, str]], new: list[dict[str, str]], ident) -> list[dict[str, str]]:
    """Rows of old whose id is not in new, then new (in its order)."""
    ids = {ident(r) for r in new}
    return [r for r in old if ident(r) not in ids] + list(new)


def num(v: str | None) -> float | None:
    try:
        return float(v) if v not in (None, "", "-") else None
    except ValueError:
        return None


def fmt_num(v: float | None) -> str:
    if v is None:
        return "-"
    return str(int(v)) if v == int(v) else f"{v:g}"


def split_list(v: str | None) -> list[str]:
    return [x for x in (v or "").split("|") if x]


def magic_lanes(row: dict[str, str]) -> str:
    """Satellite lanes of a Magic row: the 5th replay key value; keys logged before the lanes axis
    existed have 4 values (= 1 lane). The CSV's `lanes` column is shared with the main entry."""
    idx = row.get("key", "").partition(":")[2].split(",")
    return idx[4] if len(idx) > 4 and idx[4] else "1"


def search_report(jobs: list[dict[str, str]], trials: list[dict[str, str]], sources: str) -> str:
    out = [
        "# Roundabouts probe search results",
        "",
        f"Generated by `tools/parse_probe.py` ({sources}). Do not edit by hand; rerun the parser. "
        "Rows accumulate over search runs (`--fresh` starts over). How to run: `PROBE.md` \"Search runs\". "
        "Next step: `uv run tools/gen_roundabouts_tuning.py` writes the tuning table from `probe_search.csv`.",
        "",
        "## Jobs",
        "",
    ]
    by_kind: dict[str, list[dict[str, str]]] = defaultdict(list)
    for j in jobs:
        by_kind[j.get("kind", "?")].append(j)
    out += md_table(["kind", "jobs", "found", "none", "skipped", "engine calls"], [
        [k, str(len(by_kind[k])),
         str(sum(1 for j in by_kind[k] if j.get("found") == "true")),
         str(sum(1 for j in by_kind[k] if j.get("found") != "true" and not j.get("skipped"))),
         str(sum(1 for j in by_kind[k] if j.get("skipped"))),
         str(sum(int(j.get("tried") or 0) for j in by_kind[k]))]
        for k in SEARCH_KINDS if by_kind.get(k)
    ])
    msgs = Counter(t.get("msgs") or "-" for t in trials if t.get("ok") != "true")
    if msgs:
        out += ["", "Rejection messages (engine calls): " + ", ".join(f"`{m}` {n}" for m, n in msgs.most_common(6))]
    offline = Counter((t.get("offline", "-"), t.get("ok")) for t in trials if t.get("offline") not in (None, "", "-"))
    if offline:
        rows = [[o, str(offline.get((o, "true"), 0)), str(offline.get((o, "false"), 0))] for o in ("true", "false")]
        out += ["", "Offline model vs engine (calls with an exact dev layout; offline = the geometry's own plan accepted it):", ""]
        out += md_table(["offline accepts", "engine accepts", "engine rejects"], rows)

    # radius ------------------------------------------------------------------------------------
    rad = [j for j in by_kind.get("radius", []) if not j.get("skipped")]
    if rad:
        out += ["", "## Radius: smallest ring radius the engine accepts", "",
                "Per base combo: from the slider value up in 5 m steps (first accepted). `shipR` = what the shipped "
                "geometry builds today (offline growth rule). Cells: largest minimal radius over the other axes "
                "(arms, arm road, tram tracks) / jobs with none up to 120 m.", ""]
        cmp = Counter()
        rejected_ship = []
        for j in rad:
            best, ship = num(j.get("devRadius")), num(j.get("shipR"))
            rej = {num(x.split("=", 1)[1]) for x in split_list(j.get("rejected")) if "=" in x}
            if ship is not None and ship in rej:
                rejected_ship.append(j)
            if best is None:
                cmp["none found"] += 1
            elif ship is None:
                cmp["?"] += 1
            elif best < ship:
                cmp["engine accepts smaller than shipped"] += 1
            elif best == ship:
                cmp["equal"] += 1
            else:
                cmp["engine needs more than shipped"] += 1
        out += md_table(["engine minimum vs shipped radius", "jobs"], [[k, str(v)] for k, v in cmp.most_common()])
        out += ["", f"Shipped radius among the engine's rejected radii: {len(rejected_ship)} jobs (these fail in game today)."]
        groups: dict[tuple, dict[str, list]] = defaultdict(lambda: defaultdict(list))
        r0s: list[str] = []
        for j in rad:
            g = (j.get("centre"), j.get("splitter"), j.get("dir"), j.get("lanes"), j.get("shape"), j.get("through") or "same")
            r0 = j.get("radius", "?")
            if r0 not in r0s:
                r0s.append(r0)
            groups[g][r0].append(num(j.get("devRadius")))
        r0s.sort(key=lambda x: num(x) or 0)
        body = []
        for g in sorted(groups, key=lambda t: tuple(str(x) for x in t)):
            cells = []
            for r0 in r0s:
                vals = groups[g].get(r0, [])
                if not vals:
                    cells.append("")
                    continue
                found = [v for v in vals if v is not None]
                none = len(vals) - len(found)
                cells.append(f"{fmt_num(max(found)) if found else '-'}" + (f" / {none}" if none else ""))
            body.append(list(g) + cells)
        out += ["", "### Largest minimal radius per group (m; / = jobs with none)", ""]
        out += md_table(["centre", "splitter", "dir", "lanes", "shape", "through"] + [f"from {r}" for r in r0s], body)
        cols = AXES["main"][:9] + ["through", "devRadius", "shipR", "tried"]
        nones = [j for j in rad if j.get("found") != "true"]
        if nones:
            out += ["", f"### No accepted radius up to 120 m ({len(nones)})", ""]
            out += md_table(cols + ["key"], [[j.get(c, "") for c in cols] + [j.get("key", "")] for j in nones[:MAX_ROWS_PER_GROUP]])
        if rejected_ship:
            out += ["", f"### Shipped radius rejected by the engine ({len(rejected_ship)})", ""]
            out += md_table(cols + ["key"], [[j.get(c, "") for c in cols] + [j.get("key", "")] for j in rejected_ship[:MAX_ROWS_PER_GROUP]])

    # magic -------------------------------------------------------------------------------------
    ms = by_kind.get("magic_size", [])
    if ms:
        out += ["", "## Magic: sizes the engine accepts (exact size, no growth)", ""]
        out += md_table(["arm", "dir", "lanes", "accepted sizes", "shipped size from Compact"], [
            [j.get("arm", ""), j.get("dir", ""), magic_lanes(j),
             ", ".join(x.split("=", 1)[1] for x in split_list(j.get("acceptedList"))) or "none", j.get("shipSize", "")]
            for j in ms])
    sp = by_kind.get("magic_spacing", [])
    if sp:
        out += ["", "## Magic: smallest accepted spacing (centre to satellite centre, m) per satellite radius", ""]
        radii = sorted({j.get("fixed", "") for j in sp}, key=lambda f: num(f.split("=", 1)[-1]) or 0)
        arms = list(dict.fromkeys(j.get("arm", "") for j in sp))
        cell = {(j.get("arm"), j.get("fixed")): (j.get("devMagicDistance") if j.get("found") == "true" else "none") for j in sp}
        out += md_table(["arm \\ satellite"] + [f.replace("magicRadius=", "r=") for f in radii],
                        [[a] + [cell.get((a, f), "") for f in radii] for a in arms])

    # splitter ----------------------------------------------------------------------------------
    st = [t for t in trials if t.get("kind") == "splitter"]
    if st:
        out += ["", "## Splitter: accepted parameter sets per arm road", "",
                "Rate = accepted base combos / base combos tried (layouts x lanes x radii). Candidates are in compactness "
                "order (shortest split + neck, then narrowest fork, narrowest leg, least spread); the tuning generator "
                "takes the most compact one with the best rate.", ""]
        per: dict[str, dict[str, list[int]]] = defaultdict(lambda: defaultdict(lambda: [0, 0, 0]))
        for t in st:
            c = per[t.get("arm", "?")][t.get("label", "?")]
            c[0] += 1
            c[1] += t.get("ok") == "true"
            c[2] = int(t.get("cand") or 0)
        for arm, cands in per.items():
            ranked = sorted(cands.items(), key=lambda kv: (-kv[1][1] / max(1, kv[1][0]), kv[1][2]))
            out += [f"### {arm}", ""]
            out += md_table(["candidate", "accepted", "rate"], [
                [lab, f"{c[1]}/{c[0]}", pct(c[1], c[0])] for lab, c in ranked[:12]])
            out.append("")
        sj = by_kind.get("splitter", [])
        cols = ["arm", "arms", "lanes", "shape", "fixed", "accepted", "ncand", "best"]
        out += ["### Most compact accepted set per base combo", ""]
        out += md_table(cols, [[j.get(c, "") for c in cols] for j in sj])

    # tram stub ---------------------------------------------------------------------------------
    ts = by_kind.get("tram_stub", [])
    if ts:
        out += ["", "## Tram line: accepted stub lengths (m beyond the ring half width)", ""]
        out += md_table(["lanes", "dir", "fixed", "accepted stubs"], [
            [j.get("lanes", ""), j.get("dir", ""), j.get("fixed", ""),
             ", ".join(x.split("=", 1)[1] for x in split_list(j.get("acceptedList"))) or "none"] for j in ts])
    # grid (Phase 5e) -----------------------------------------------------------------------------
    gt = [t for t in trials if t.get("kind") == "grid"]
    if gt:
        out += ["", "## Grid searches (Phase 5e): tunables per entry", "",
                "Every candidate is tried (shipped values first). Rate = accepted base combos / base combos tried. "
                "A candidate that the engine accepts as often as the shipped one gives a more compact layout.", ""]
        per: dict[str, dict[str, list[int]]] = defaultdict(lambda: defaultdict(lambda: [0, 0, 0]))
        for t in gt:
            c = per[t.get("entry", "?")][t.get("label", "?")]
            c[0] += 1
            c[1] += t.get("ok") == "true"
            c[2] = int(t.get("cand") or 0)
        for entry, cands in per.items():
            out += [f"### {entry}", ""]
            out += md_table(["candidate (in search order)", "accepted", "rate"], [
                [lab, f"{c[1]}/{c[0]}", pct(c[1], c[0])] for lab, c in sorted(cands.items(), key=lambda kv: kv[1][2])])
            out.append("")
            ej = [j for j in by_kind.get("grid", []) if j.get("entry") == entry]
            axes = [a for a in AXES.get(entry, []) if len({j.get(a) for j in ej}) > 1]
            cols = axes + ["accepted", "ncand"]
            out += [f"#### {entry}: accepted candidates per base combo", ""]
            out += md_table(cols + ["accepted list"], [[j.get(c, "") for c in cols] + [
                ", ".join(split_list(j.get("acceptedList"))) or "none"] for j in ej[:MAX_ROWS_PER_GROUP * 3]])
            out.append("")
    return "\n".join(out).rstrip() + "\n"


def write_csv(rows: list[dict[str, str]], path: Path) -> None:
    cols: list[str] = []
    for r in rows:
        for k in r:
            if k not in cols:
                cols.append(k)
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow(r)


def default_outputs(subset: str) -> dict[str, Path]:
    """Output files of a run by its subset (module doc: "Output names by subset")."""
    if subset in LEGACY_SWEEPS or subset.startswith("search"):
        return {"out_md": PLANS / "probe_results.md", "out_csv": PLANS / "probe_results.csv",
                "search_md": PLANS / "probe_search.md", "search_csv": PLANS / "probe_search.csv",
                "trials_csv": PLANS / "probe_search_trials.csv"}
    name = re.sub(r"[^a-z0-9_]", "_", subset.lower()) or "unknown"
    return {"out_md": PLANS / f"probe_{name}.md", "out_csv": PLANS / f"probe_{name}.csv",
            "search_md": PLANS / f"probe_{name}.md", "search_csv": PLANS / f"probe_{name}_jobs.csv",
            "trials_csv": PLANS / f"probe_{name}_trials.csv"}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--stdout", type=Path, help="game log (default: <userdata>/crash_dump/stdout.txt)")
    ap.add_argument("--run", type=int, default=-1, help="run number (1 = first, -1 = last)")
    ap.add_argument("--list", action="store_true", help="list the runs in the log and exit")
    ap.add_argument("--out-md", type=Path, help="sweep report (default by subset, see above)")
    ap.add_argument("--out-csv", type=Path, help="sweep rows (default by subset)")
    ap.add_argument("--search-md", type=Path, help="search report (default by subset)")
    ap.add_argument("--search-csv", type=Path, help="search jobs (default by subset)")
    ap.add_argument("--trials-csv", type=Path, help="search engine calls (default by subset)")
    ap.add_argument("--fresh", action="store_true", help="search CSVs: drop rows from earlier runs")
    args = ap.parse_args()

    source = args.stdout or userdata() / "crash_dump" / "stdout.txt"
    if not source.is_file():
        raise SystemExit(f"{source}: not found (pass --stdout)")
    runs = read_runs(source)
    if not runs:
        raise SystemExit(f"{source}: no [SQRB_PROBE] lines (did the probe run? see PROBE.md)")
    if args.list:
        for i, r in enumerate(runs, 1):
            state = "finished" if r.end else "unfinished"
            print(f"{i}: subset={r.start.get('subset', '?')} rows={len(r.rows)} jobs={len(r.searches)} "
                  f"calls={len(r.trials)} of {r.start.get('total', '?')} {state}")
            for n in r.notes:
                if n.startswith("ERROR"):
                    print(f"     {n}")
        return
    idx = args.run - 1 if args.run > 0 else len(runs) + args.run
    if not 0 <= idx < len(runs):
        raise SystemExit(f"run {args.run}: the log has {len(runs)} run(s)")
    run = runs[idx]
    for name, path in default_outputs(run.start.get("subset", "")).items():
        if getattr(args, name) is None:
            setattr(args, name, path)
    rel = lambda p: p.relative_to(ROOT) if p.is_relative_to(ROOT) else p  # noqa: E731
    if not run.rows and not run.searches:
        notes = "\n".join(run.notes) or "(none)"
        print(f"run {idx + 1} has no result rows. Notes:\n{notes}")
    if run.rows or not run.searches:
        args.out_md.parent.mkdir(parents=True, exist_ok=True)
        args.out_md.write_text(report(run, idx + 1, len(runs), source), encoding="utf-8")
        write_csv(run.rows, args.out_csv)
        n_fail = sum(1 for r in run.rows if failed(r))
        print(f"run {idx + 1}/{len(runs)}: {len(run.rows)} combos, {n_fail} not placeable"
              f"{'' if run.end else ' (unfinished)'}")
        print(f"wrote {rel(args.out_md)}")
        print(f"wrote {rel(args.out_csv)}")
    if run.searches or run.trials:
        old_jobs = [] if args.fresh else read_csv(args.search_csv)
        old_trials = [] if args.fresh else read_csv(args.trials_csv)
        jobs = merge(old_jobs, run.searches, job_id)
        trials = merge(old_trials, run.trials, trial_id)
        write_csv(jobs, args.search_csv)
        write_csv(trials, args.trials_csv)
        subset = run.start.get("subset", "?")
        sources = f"last parsed: run {idx + 1} of {len(runs)} in `{source}`, subset {subset}"
        args.search_md.write_text(search_report(jobs, trials, sources), encoding="utf-8")
        print(f"run {idx + 1}/{len(runs)}: subset {subset}, {len(run.searches)} search jobs, {len(run.trials)} engine calls"
              f"{'' if run.end else ' (unfinished)'}; files now hold {len(jobs)} jobs, {len(trials)} calls")
        for p in (args.search_md, args.search_csv, args.trials_csv):
            print(f"wrote {rel(p)}")


if __name__ == "__main__":
    main()
