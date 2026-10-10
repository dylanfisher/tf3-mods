# /// script
# requires-python = ">=3.11"
# ///
"""Report of the [HITCH] lines that the DEV Hitch Probe (mods/square_hitch_probe) writes to stdout.txt.

Question: does a long game-script update show up as a slow rendered frame? The probe busy-waits once
about every 2 s (40 ticks), either in the game script (levels gs20/gs40/gs100) or in the GUI's onStep (gui40, the
control that must hitch), and logs every frame time with its GAME_TIME.tickCount:

  [HITCH] side=gui level=gs40 gs=40 gui=0 tick=1200 upd=300 vm=..           level change (button)
  [HITCH] side=gui frames level=gs40 tick0=1234 n=240 vm=.. dt=167,166,412/2  frame times, 0.1 ms
  [HITCH] side=gs burn want=40 ms=40.03 tick=1320 upd=330 vm=..             one game-script pause
  [HITCH] side=gui burn want=40 ms=40.01 tick=1440 upd=360 vm=..            one GUI pause

Per level it prints frame-time stats and, for each pause, whether a frame within a few ticks of it was
slow by at least half the pause. The "off" level gets the same test at every 40th tick (where a pause
would have been), which is the false-alarm rate to compare against.

  uv run plans/hitch_probe/hitch_report.py              # the live stdout.txt
  uv run plans/hitch_probe/hitch_report.py copy.txt     # a saved copy
  ... --all       every load in the file, not only the last one with [HITCH] lines
"""

from __future__ import annotations

import argparse
import bisect
import re
import statistics
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

HITCH = re.compile(r"\[HITCH\] (?P<body>.*)$")
KV = re.compile(r"(\w+)=(\S+)")
LOAD_MARK = "Loading config/game from file"
PERIOD = 40
# The GUI sees tickCount move by 4 once per simulation step (~200 ms), so many frames share a tick. A pause
# at tick B is matched with the frames from WINDOW[0] before the first frame showing tick >= B - STEP to
# WINDOW[1] after it (~0.5 s at 90 fps), which covers the GUI lagging the game script by one step.
STEP = 4
WINDOW = (6, 40)  # frames before / after
MIN_LEVEL_S = 45  # a level shorter than this is flagged: too few pauses to judge


@dataclass
class Frame:
    tick: int
    ms: float
    level: str


@dataclass
class Burn:
    side: str
    tick: int
    want: int
    ms: float
    level: str


@dataclass
class Load:
    frames: list[Frame] = field(default_factory=list)
    burns: list[Burn] = field(default_factory=list)
    levels: list[str] = field(default_factory=list)


def default_log() -> Path:
    try:
        from perf_report import default_log as dl  # tools/perf_report.py knows the userdata path

        return dl()
    except Exception:  # noqa: BLE001
        sys.exit("no stdout.txt given and tools/perf_report.py could not locate it")


def parse(path: Path) -> list[Load]:
    loads: list[Load] = [Load()]
    level = "off"
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if LOAD_MARK in line:
            loads.append(Load())
            level = "off"
            continue
        m = HITCH.search(line)
        if not m:
            continue
        body = m.group("body")
        kv = dict(KV.findall(body))
        cur = loads[-1]
        if kv.get("side") == "gui" and "level" in kv and " frames " not in f" {body} " and "burn" not in body.split():
            level = kv["level"]
            cur.levels.append(level)
        elif " frames " in f" {body} ":
            lv = kv.get("level", level)
            tick = int(kv["tick0"])
            for i, item in enumerate(kv["dt"].split(",")):
                dt, _, step = item.partition("/")
                if i > 0:
                    tick += int(step) if step else 1
                cur.frames.append(Frame(tick, int(dt) / 10.0, lv))
        elif "burn" in body.split():
            cur.burns.append(Burn(kv["side"], int(kv["tick"]), int(kv["want"]), float(kv["ms"]), level))
    return [ld for ld in loads if ld.frames or ld.burns]


def pct(values: list[float], p: float) -> float:
    s = sorted(values)
    return s[min(len(s) - 1, int(p / 100 * len(s)))]


def hit_test(frames: list[Frame], ticks: list[int], median: float, want: float):
    """For each pause tick: the slowest frame in the window around it, and whether it beat median + want/2.
    lags counts the slow frame's position in frames after the first frame showing the pause's step."""
    hits, lags = 0, Counter()
    frame_ticks = [f.tick for f in frames]
    for t in ticks:
        i = bisect.bisect_left(frame_ticks, t - STEP)
        if i >= len(frames):
            continue
        lo, hi = max(0, i - WINDOW[0]), min(len(frames), i + WINDOW[1] + 1)
        j = max(range(lo, hi), key=lambda k: frames[k].ms)
        if frames[j].ms > median + want / 2:
            hits += 1
            lags[(j - i) // 10 * 10] += 1
    return hits, lags


def report(load: Load, title: str) -> None:
    print(f"== {title}: {len(load.frames)} frames, {len(load.burns)} pauses, levels {' -> '.join(load.levels) or '(none)'}")
    frames_by_level: dict[str, list[Frame]] = defaultdict(list)
    for f in load.frames:
        frames_by_level[f.level].append(f)
    burns_by_level: dict[str, list[Burn]] = defaultdict(list)
    for b in load.burns:
        burns_by_level[b.level].append(b)

    print(f"{'level':7} {'secs':>5} {'frames':>7} {'fps':>6} {'p50':>6} {'p99':>6} {'max':>6} {'slow/min':>8}"
          f" {'pauses':>6} {'pause ms':>8} {'hit':>9}  lag of the slow frame (frames after the pause's step, by 10: count)")
    for lv in sorted(frames_by_level, key=lambda x: (x != "off", x)):
        fr = frames_by_level[lv][1:]  # the first frame of a level can hold the click
        if len(fr) < 10:
            continue
        ms = [f.ms for f in fr]
        median = statistics.median(ms)
        total_s = sum(ms) / 1000
        slow = sum(1 for x in ms if x > max(2 * median, median + 15))
        burns = burns_by_level.get(lv, [])
        if burns:
            ticks = [b.tick for b in burns]
            want = statistics.mean(b.want for b in burns)
            pause = f"{statistics.mean(b.ms for b in burns):.1f}"
            sides = {b.side for b in burns}
            label = "/".join(sorted(sides))
        else:
            # where a pause would have been: false alarms against a 40 ms pause
            lo, hi = fr[0].tick, fr[-1].tick
            ticks = list(range((lo // PERIOD + 1) * PERIOD, hi - STEP, PERIOD))
            want, pause, label = 40.0, "(none)", "ctl40"
        hits, lags = hit_test(fr, ticks, median, want)
        hit = f"{hits}/{len(ticks)}" if ticks else "-"
        lag_txt = " ".join(f"{k:+d}:{v}" for k, v in sorted(lags.items()))
        short = " (too short)" if total_s < MIN_LEVEL_S else ""
        print(f"{lv:7} {total_s:5.0f} {len(fr):7d} {len(fr) / total_s:6.1f} {median:6.1f} {pct(ms, 99):6.1f} {max(ms):6.1f}"
              f" {slow / total_s * 60:8.1f} {len(burns):6d} {pause:>8} {hit:>9}  {label} {lag_txt}{short}")
    print()
    print("Reading it: 'hit' = pauses followed by a frame slower than median + half the pause. The gui40 control")
    print("should hit (nearly) every pause; off's ctl40 row is the false-alarm rate. If gs40 hits about as often as")
    print("gui40, the renderer waits for the game script and a 40 ms sweep is a 40 ms frame hitch. If it hits about")
    print("as often as off, only the simulation stalls.")
    multi = Counter(b.tick // PERIOD for b in load.burns if b.side == "gs")
    dup = sum(1 for n in multi.values() if n > 1)
    if dup:
        print(f"note: {dup} periods had more than one game-script pause (update ran in parallel Lua states).")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", nargs="?", type=Path, help="stdout.txt (default: the live one)")
    ap.add_argument("--all", action="store_true", help="every load, not only the last with [HITCH] lines")
    args = ap.parse_args()
    path = args.log or default_log()
    loads = parse(path)
    if not loads:
        sys.exit(f"no [HITCH] lines in {path}")
    chosen = loads if args.all else loads[-1:]
    for i, ld in enumerate(chosen, 1):
        report(ld, f"load {i if args.all else len(loads)} of {len(loads)} in {path.name}")


if __name__ == "__main__":
    main()
