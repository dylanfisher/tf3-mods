# /// script
# requires-python = ">=3.11"
# ///
"""Per-mod report of the [SQPERF] lines that square_* mods write to the game log.

SQPERF (tools/sqperf/sqperf.lua, plans/sqperf/README.md) logs three kinds of lines to
<userdata>/crash_dump/stdout.txt, each from one Lua state (vm=) of one context (ctx=):

  [SQPERF] mod=square_x ctx=gs vm=3f2a phase=init ms=212.4 timer=clock            level 1, always
  [SQPERF] mod=square_x ctx=gs vm=3f2a phase=first ms=48.0 scan_a=40.1 scan_b=7.9  level 1, always
  [SQPERF] mod=square_x ctx=gui vm=3f2a slow=window_render max=41.2 over=3/1200    level 2, always (rare)
  [SQPERF] mod=square_x ctx=gs vm=3f2a win_ms=30004.1 timer=clock mem_kb=5120 | scan_a n=12 ms=4.210 max=1.020 | toasts c=3
                                                                                    level 3, opt-in mod setting

The game log also marks each load (the "mod params:" dump, "Loading config/game from file …",
"push() default tool", "Game is ready", "Init game took: … s"); the report lists the loads with their
total init time and the last step (default tool -> ready), so a stall can be matched with the init
lines logged in it.

  uv run tools/perf_report.py                   # the live stdout.txt (TF3_USERDATA / .hub.env / auto)
  uv run tools/perf_report.py run1.txt run2.txt # saved copies
  ... --mod square_problem_radar   only this mod
  ... --last                       per file, only the most recent load with [SQPERF] lines (of --mod
                                   if given); newer loads without any are listed in Loads and named
  ... --skip 1                     window lines to drop per Lua state (the first holds the loading)
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

LOG_LINE = re.compile(r"^\[(?P<ts>[^\]]*?) - (?P<level>\w+)\s*- (?P<thread>.*?)\s*- (?P<cat>[^\]]*?)\s*\]\s?(?P<msg>.*)$")
SQ = re.compile(r"\[SQPERF\] mod=(?P<mod>\S+) ctx=(?P<ctx>\S+) vm=(?P<vm>\S+) (?P<rest>.*)$")
PHASE = re.compile(r"^phase=(?P<phase>\S+) ms=(?P<ms>[\d.]+)(?P<rest>.*)$")
SLOW = re.compile(r"^slow=(?P<sec>\S+) max=(?P<max>[\d.]+) over=(?P<slow>\d+)/(?P<calls>\d+)")
WIN = re.compile(r"^win_ms=(?P<win>[\d.]+)(?P<head>[^|]*)(?P<rest>.*)$")
TIMED = re.compile(r"^(\S+) n=(\d+) ms=([\d.]+) max=([\d.]+)$")
HITS = re.compile(r"^(\S+) n=(\d+)$")
COUNT = re.compile(r"^(\S+) c=(\d+)$")
KV = re.compile(r"(\w+)=(\S+)")
LOAD_CONFIG = re.compile(r"Loading (?:config|game) from file (?P<name>.*)$")
INIT_TOOK = re.compile(r"Init game took: (?P<s>[\d.]+) s")
TS_FMT = "%Y-%m-%d %H:%M:%SZ"


def default_log() -> Path:
    from hubconfig import userdata  # noqa: PLC0415

    return userdata() / "crash_dump" / "stdout.txt"


def parse_ts(ts: str) -> datetime | None:
    try:
        return datetime.strptime(ts.strip(), TS_FMT)
    except ValueError:
        return None


@dataclass
class Load:
    file: str
    index: int
    name: str
    start: str
    init_s: float | None = None
    default_tool: datetime | None = None
    ready: datetime | None = None
    sqperf: int = 0  # [SQPERF] lines in this load (of --mod if given)

    def last_step_s(self) -> float | None:
        """Seconds from "push() default tool" to "Game is ready" (where the 16 s stall was seen)."""
        if self.default_tool and self.ready:
            return (self.ready - self.default_tool).total_seconds()
        return None


@dataclass
class Phase:
    load: int
    mod: str
    ctx: str
    vm: str
    thread: str
    phase: str
    ms: float
    detail: str
    ts: str


@dataclass
class Slow:
    calls_logged: int = 0  # lines
    max: float = 0.0
    slow: int = 0
    calls: int = 0
    threads: set[str] = field(default_factory=set)


@dataclass
class Sec:
    n: int = 0
    ms: float = 0.0
    max: float = 0.0
    timed: bool = True


@dataclass
class Ctx:
    seconds: dict[str, float] = field(default_factory=lambda: defaultdict(float))  # per vm
    windows: int = 0
    secs: dict[str, Sec] = field(default_factory=lambda: defaultdict(Sec))
    counts: dict[str, int] = field(default_factory=lambda: defaultdict(int))
    mem_last: int | None = None
    mem_max: int | None = None
    timers: set[str] = field(default_factory=set)

    def wall_s(self) -> float:
        return max(self.seconds.values(), default=0.0) / 1000


@dataclass
class Report:
    loads: list[Load] = field(default_factory=list)
    phases: list[Phase] = field(default_factory=list)
    slow: dict[tuple[str, str, str], Slow] = field(default_factory=lambda: defaultdict(Slow))  # mod, ctx, section
    windows: dict[tuple[str, str], Ctx] = field(default_factory=lambda: defaultdict(Ctx))  # mod, ctx
    lines: int = 0
    skipped_windows: int = 0
    notes: list[str] = field(default_factory=list)  # which load --last picked, per file

    def mods(self) -> list[str]:
        names = {p.mod for p in self.phases} | {k[0] for k in self.slow} | {k[0] for k in self.windows}
        return sorted(names)


def sqperf_load(text: list[str], only_mod: str | None) -> tuple[int | None, int]:
    """(1-based load in this file with the last [SQPERF] line (of only_mod), or None; loads in the file).

    Load 0 = lines before the first "mod params:" dump."""
    cur, found = 0, None
    for raw in text:
        if "mod params:" in raw:
            cur += 1
        elif (sm := SQ.search(raw)) and (not only_mod or sm["mod"] == only_mod):
            found = cur
    return found, cur


def parse(paths: list[Path], skip: int = 0, only_mod: str | None = None, last_load: bool = False) -> Report:
    """Parse the logs. last_load: per file, keep only the most recent load that has [SQPERF] lines
    (all loads are still parsed, so start / init / gap are right) plus the newer loads without any."""
    rep = Report()
    numbered = 0  # loads numbered across all files (the report's load #)
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace").splitlines()
        pick: int | None = None  # load number in this file whose [SQPERF] lines are kept (--last)
        n_loads = 0
        if last_load:
            pick, n_loads = sqperf_load(text, only_mod)
            if pick is None:
                pick = n_loads  # nothing anywhere: show the last load (the "No [SQPERF] lines" case)
        file_loads: list[Load] = []
        load: Load | None = None
        pending_name: str | None = None
        last_ts = ""
        seen: dict[tuple[str, str, str], int] = defaultdict(int)  # windows per (mod, ctx, vm) in this load
        for raw in text:
            m = LOG_LINE.match(raw)
            ts, thread, msg = (m["ts"], m["thread"].strip(), m["msg"]) if m else ("", "", raw)
            # One "mod params:" dump per load (new game, savegame or map); "Loading config" comes just
            # before it, "Loading game from file" just after.
            if "mod params:" in raw:
                numbered += 1
                load = Load(path.name, numbered, pending_name or "(unnamed)", ts or last_ts)
                file_loads.append(load)
                pending_name = None
                seen.clear()
                continue
            if ts:
                last_ts = ts
            if lm := LOAD_CONFIG.search(msg):
                if load is not None and load.name == "(unnamed)" and load.default_tool is None:
                    load.name = lm["name"].strip()
                elif msg.find("Loading config") >= 0:
                    pending_name = lm["name"].strip()
                continue
            if load is not None and (im := INIT_TOOK.search(msg)):
                load.init_s = float(im["s"])
            if load is not None and "push() default tool" in msg:
                load.default_tool = parse_ts(ts)
                load.ready = None
            elif load is not None and msg.strip() == "Game is ready" and load.ready is None:
                load.ready = parse_ts(ts)
            sm = SQ.search(msg)
            if not sm:
                continue
            mod, ctx, vm, rest = sm["mod"], sm["ctx"], sm["vm"], sm["rest"].strip()
            if only_mod and mod != only_mod:
                continue
            load_no = load.index if load else 0
            if load is not None:
                load.sqperf += 1
            if last_load and len(file_loads) != pick:
                continue
            rep.lines += 1
            if pm := PHASE.match(rest):
                rep.phases.append(Phase(load_no, mod, ctx, vm, thread, pm["phase"], float(pm["ms"]),
                                        pm["rest"].strip(), ts))
            elif wm := SLOW.match(rest):
                s = rep.slow[(mod, ctx, wm["sec"])]
                s.calls_logged += 1
                s.max = max(s.max, float(wm["max"]))
                s.slow += int(wm["slow"])
                s.calls += int(wm["calls"])
                if thread:
                    s.threads.add(thread)
            elif wn := WIN.match(rest):
                seen[(mod, ctx, vm)] += 1
                if seen[(mod, ctx, vm)] <= skip:
                    rep.skipped_windows += 1
                    continue
                c = rep.windows[(mod, ctx)]
                c.windows += 1
                c.seconds[f"{load_no}:{vm}"] += float(wn["win"])
                head = dict(KV.findall(wn["head"]))
                if "timer" in head:
                    c.timers.add(head["timer"])
                if "mem_kb" in head:
                    kb = int(head["mem_kb"])
                    c.mem_last = kb
                    c.mem_max = kb if c.mem_max is None else max(c.mem_max, kb)
                for part in (p.strip() for p in wn["rest"].split("|")):
                    if not part:
                        continue
                    if tm := TIMED.match(part):
                        sec = c.secs[tm[1]]
                        sec.n += int(tm[2])
                        sec.ms += float(tm[3])
                        sec.max = max(sec.max, float(tm[4]))
                    elif hm := HITS.match(part):
                        sec = c.secs[hm[1]]
                        sec.n += int(hm[2])
                        sec.timed = False
                    elif cm := COUNT.match(part):
                        c.counts[cm[1]] += int(cm[2])
        if last_load:
            kept = file_loads[max(pick, 1) - 1:]  # pick 0: SQPERF lines before any load dump
            chosen = file_loads[pick - 1] if pick >= 1 else None
            if chosen is not None and chosen.sqperf:
                newer = kept[1:]
                note = (f"--last: {path.name} load {pick} of {n_loads} (#{chosen.index}, {chosen.name}, "
                        f"started {chosen.start or '?'}), "
                        f"the most recent with [SQPERF] lines{' for ' + only_mod if only_mod else ''}.")
                if newer:
                    note += (f" {len(newer)} newer load(s) without [SQPERF] lines (still starting, or no SQPERF mod "
                             f"enabled): " + ", ".join(f"#{ld.index} {ld.name}" for ld in newer) + ".")
                rep.notes.append(note)
            file_loads = kept
        rep.loads.extend(file_loads)
    return rep


def fmt(v: float | None, digits: int = 1) -> str:
    if v is None:
        return "–"
    if abs(v) >= 10000:
        return f"{v:,.0f}"
    return f"{v:.{digits}f}"


def render(rep: Report) -> str:
    out: list[str] = [*rep.notes, ""] if rep.notes else []
    if rep.loads:
        out.append("## Loads")
        out.append("")
        out.append("| # | file | config / save | started | Init game took | push() default tool -> Game is ready | SQPERF lines |")
        out.append("|---:|---|---|---|---:|---:|---:|")
        for ld in rep.loads:
            step = ld.last_step_s()
            init = f"{ld.init_s:.1f} s" if ld.init_s is not None else "–"
            out.append(f"| {ld.index} | {ld.file} | {ld.name} | {ld.start or '?'} | {init} | "
                       f"{fmt(step, 0) + ' s' if step is not None else '–'} | {ld.sqperf} |")
        out.append("")
    for mod in rep.mods():
        out.append(f"## {mod}")
        out.append("")
        phases = [p for p in rep.phases if p.mod == mod]
        if phases:
            out.append("Init (level 1): one line per Lua state and load")
            out.append("")
            out.append("| load | ctx | thread | vm | phase | ms | detail |")
            out.append("|---:|---|---|---|---|---:|---|")
            for p in phases:
                out.append(f"| {p.load or '–'} | {p.ctx} | {p.thread or '?'} | {p.vm} | {p.phase} | {fmt(p.ms)} | {p.detail} |")
            out.append("")
        slows = {k[1:]: v for k, v in rep.slow.items() if k[0] == mod}
        if slows:
            out.append("Slow calls (level 2): over the threshold (16 ms GUI, 50 ms simulation)")
            out.append("")
            out.append("| ctx | section | lines | max ms | slow calls | of calls | threads |")
            out.append("|---|---|---:|---:|---:|---:|---|")
            for (ctx, sec), s in sorted(slows.items(), key=lambda kv: -kv[1].max):
                out.append(f"| {ctx} | {sec} | {s.calls_logged} | {fmt(s.max)} | {s.slow} | {s.calls} | {', '.join(sorted(s.threads))} |")
            out.append("")
        else:
            out.append("Slow calls (level 2): none")
            out.append("")
        ctxs = {k[1]: v for k, v in rep.windows.items() if k[0] == mod}
        for ctx, c in sorted(ctxs.items()):
            secs = c.wall_s()
            mem = f", Lua memory {fmt(c.mem_last, 0)} KB last / {fmt(c.mem_max, 0)} KB max" if c.mem_last is not None else ""
            out.append(f"Windows (level 3), ctx={ctx}: {c.windows} window(s), {fmt(secs, 0)} s, timer {'/'.join(sorted(c.timers)) or '?'}{mem}")
            out.append("")
            out.append("| section | calls | calls/s | total ms | ms/s | avg ms | max ms |")
            out.append("|---|---:|---:|---:|---:|---:|---:|")
            for name, s in sorted(c.secs.items(), key=lambda kv: (-kv[1].ms, kv[0])):
                rate = s.n / secs if secs else None
                if s.timed:
                    out.append(f"| {name} | {s.n} | {fmt(rate, 2)} | {fmt(s.ms, 1)} | {fmt(s.ms / secs if secs else None, 3)} | "
                               f"{fmt(s.ms / s.n if s.n else None, 3)} | {fmt(s.max, 1)} |")
                else:
                    out.append(f"| {name} (count only) | {s.n} | {fmt(rate, 2)} | – | – | – | – |")
            for name, n in sorted(c.counts.items()):
                out.append(f"| {name} (counter) | {n} | {fmt(n / secs if secs else None, 2)} | | | | |")
            out.append("")
    return "\n".join(out).rstrip() + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="*", type=Path, help="stdout.txt copies (default: the live one)")
    ap.add_argument("--mod", help="only this modId")
    ap.add_argument("--last", action="store_true", help="only the last load of each file")
    ap.add_argument("--skip", type=int, default=0, help="window lines to drop per Lua state and load")
    args = ap.parse_args()
    paths = args.logs or [default_log()]
    for p in paths:
        if not p.is_file():
            raise SystemExit(f"No such log: {p}")
    rep = parse(paths, args.skip, args.mod, args.last)
    if rep.lines == 0:
        where = ", ".join(map(str, paths))
        print(f"No [SQPERF] lines{' for ' + args.mod if args.mod else ''} in {where} ({len(rep.loads)} load(s) in the log).")
        print("Enable a mod that ships SQPERF (e.g. square_problem_radar) and load a game; set its "
              "'Debug: performance log' to On for the 30 s summaries.")
        if rep.loads:
            print()
            print(render(Report(loads=rep.loads)), end="")
        return
    print(render(rep), end="")


if __name__ == "__main__":
    main()
