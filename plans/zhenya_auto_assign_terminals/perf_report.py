# /// script
# requires-python = ">=3.11"
# ///
"""Compare the [AATPERF] timing lines of square_aat_perftest's two implementations.

The DEV mod mods/square_aat_perftest logs one line per 30 s window from each Lua state (every simulation
VM, side=gs, and the GUI, side=gui) to <userdata>/crash_dump/stdout.txt:

  [AATPERF] side=gs mode=original vm=3f2a win_ms=30004.1 timer=clock | sweep n=15 ms=120.300 max=22.100 | vehiclesRead c=4500 | stateBytes g=812345

This reads those lines (from the live stdout.txt, or from saved copies given as arguments), groups them by
mode and side, and prints a Markdown table: original vs optimized, with the change.

  uv run plans/zhenya_auto_assign_terminals/perf_report.py                  # live stdout.txt
  uv run plans/zhenya_auto_assign_terminals/perf_report.py run1.txt run2.txt
  ... --skip 1    windows to drop per Lua state after each start (default 1: the first window holds the
                  initial full pass and the loading)

Rates are per real second of the run: "ms/s" is milliseconds of mod work per second summed over all Lua
states of that side, "max ms" the slowest single call seen in any window (a stutter), "avg ms" per call.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

LINE = re.compile(r"\[AATPERF\] side=(\w+) mode=(\w+) vm=(\w+) win_ms=([\d.]+)[^|]*(.*)$")
START = re.compile(r"\[AATPERF\] side=(\w+) start mode=(\w+)")
TIMED = re.compile(r"(\w+) n=(\d+) ms=([\d.]+) max=([\d.]+)")
COUNT = re.compile(r"(\w+) c=(\d+)")
GAUGE = re.compile(r"(\w+) g=(-?\d+)")

MODES = ("original", "optimized")

# Shown first, in this order; the rest follow alphabetically.
HEADLINE = {
    "gs": ["sweep", "update", "lineCargo", "stateGet", "stateSet", "assignStop", "path", "eventBuild"],
    "gui": ["frames", "readState", "guiGameBarWidget", "guiRefreshButton", "guiStationCard", "guiLineCard",
            "guiStopCard", "guiStopRefreshButton"],
}


class Bucket:
    def __init__(self) -> None:
        self.win_ms: dict[str, float] = defaultdict(float)  # per vm
        self.timed: dict[str, list[float]] = defaultdict(lambda: [0, 0.0, 0.0])  # n, ms, max
        self.counts: dict[str, int] = defaultdict(int)
        self.gauges: dict[str, int] = {}
        self.windows = 0

    def seconds(self) -> float:
        # wall time of the run: the longest-running Lua state of this side
        return max(self.win_ms.values(), default=0.0) / 1000


def default_log() -> Path:
    from hubconfig import userdata  # noqa: PLC0415

    return userdata() / "crash_dump" / "stdout.txt"


def parse(paths: list[Path], skip: int) -> dict[tuple[str, str], Bucket]:
    buckets: dict[tuple[str, str], Bucket] = defaultdict(Bucket)
    for path in paths:
        seen: dict[tuple[str, str, str], int] = defaultdict(int)  # windows per (side, mode, vm) since start
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if START.search(raw):
                seen.clear()  # a new session or reload: skip its first windows again
                continue
            m = LINE.search(raw)
            if not m:
                continue
            side, mode, vm, win, rest = m.group(1), m.group(2), m.group(3), float(m.group(4)), m.group(5)
            seen[(side, mode, vm)] += 1
            if seen[(side, mode, vm)] <= skip:
                continue
            b = buckets[(side, mode)]
            b.windows += 1
            b.win_ms[vm] += win
            for name, n, ms, mx in TIMED.findall(rest):
                t = b.timed[name]
                t[0] += int(n)
                t[1] += float(ms)
                t[2] = max(t[2], float(mx))
            for name, c in COUNT.findall(rest):
                b.counts[name] += int(c)
            for name, g in GAUGE.findall(rest):
                b.gauges[name] = int(g)
    return buckets


def fmt(v: float | None, digits: int = 2) -> str:
    if v is None:
        return "–"
    if abs(v) >= 1000:
        return f"{v:,.0f}"
    return f"{v:.{digits}f}"


def change(a: float | None, b: float | None) -> str:
    if a is None or b is None:
        return ""
    if a == 0:
        return "" if b == 0 else "new"
    pct = (b - a) / a * 100
    factor = a / b if b else float("inf")
    if pct <= -50 and b > 0:
        return f"{pct:+.0f}% ({factor:.1f}x less)"
    return f"{pct:+.0f}%"


def rows_for(side: str, buckets: dict[tuple[str, str], Bucket]) -> list[str]:
    bs = {mode: buckets.get((side, mode)) for mode in MODES}
    names_t: set[str] = set()
    names_c: set[str] = set()
    names_g: set[str] = set()
    for b in bs.values():
        if b:
            names_t |= set(b.timed)
            names_c |= set(b.counts)
            names_g |= set(b.gauges)
    order = [n for n in HEADLINE[side] if n in names_t or n in names_c]
    order += sorted((names_t | names_c) - set(order))

    out = [
        f"| {side} | original | optimized | change |",
        "|---|---:|---:|---|",
    ]
    secs = {mode: (b.seconds() if b else 0) for mode, b in bs.items()}
    out.append(f"| measured time (s) | {fmt(secs['original'], 0)} | {fmt(secs['optimized'], 0)} | |")

    def val(mode: str, fn) -> float | None:
        b = bs[mode]
        if not b or secs[mode] == 0:
            return None
        return fn(b, secs[mode])

    frames = {m: val(m, lambda b, s: b.counts.get("frames", 0) / s) for m in MODES}
    for name in order:
        if name in names_t:
            specs = [
                ("ms/s", lambda b, s, n=name: b.timed[n][1] / s if n in b.timed else 0.0),
                ("max ms", lambda b, s, n=name: b.timed[n][2] if n in b.timed else 0.0),
                ("avg ms", lambda b, s, n=name: b.timed[n][1] / b.timed[n][0] if b.timed.get(n, [0])[0] else 0.0),
                ("calls/s", lambda b, s, n=name: b.timed[n][0] / s if n in b.timed else 0.0),
            ]
            for label, fn in specs:
                a, c = val("original", fn), val("optimized", fn)
                out.append(f"| {name} {label} | {fmt(a, 3)} | {fmt(c, 3)} | {change(a, c)} |")
        else:
            fn = lambda b, s, n=name: b.counts.get(n, 0) / s  # noqa: E731
            a, c = val("original", fn), val("optimized", fn)
            out.append(f"| {name} /s | {fmt(a)} | {fmt(c)} | {change(a, c)} |")
    if side == "gui" and all(frames.values()):
        guis = [n for n in names_t if n.startswith("gui")]  # readState runs inside these, not added again
        for m in MODES:
            b = bs[m]
            total = sum(b.timed[n][1] for n in guis if n in b.timed)
            frames[m] = total / b.counts["frames"] if b.counts.get("frames") else None
        out.append(f"| **mod GUI ms per frame** | {fmt(frames['original'], 3)} | {fmt(frames['optimized'], 3)} | "
                   f"{change(frames['original'], frames['optimized'])} |")
    for name in sorted(names_g):
        a = bs["original"].gauges.get(name) if bs["original"] else None
        c = bs["optimized"].gauges.get(name) if bs["optimized"] else None
        out.append(f"| {name} (last) | {fmt(a, 0)} | {fmt(c, 0)} | {change(a, c)} |")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="*", type=Path, help="stdout.txt copies (default: the live one)")
    ap.add_argument("--skip", type=int, default=1, help="windows to drop per Lua state after a start")
    args = ap.parse_args()
    paths = args.logs or [default_log()]
    buckets = parse(paths, args.skip)
    if not buckets:
        raise SystemExit(f"No [AATPERF] lines in {', '.join(map(str, paths))} (after skipping {args.skip} per state)")
    for side in ("gs", "gui"):
        if any(s == side for s, _ in buckets):
            print("\n".join(rows_for(side, buckets)))
            print()
    missing = [m for m in MODES if not any(k[1] == m for k in buckets)]
    if missing:
        print(f"No windows yet for: {', '.join(missing)}. Switch 'Implementation (perf test)' and reload the save.")


if __name__ == "__main__":
    main()
