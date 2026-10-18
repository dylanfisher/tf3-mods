#!/usr/bin/env python3
"""Copy the Organic Towns dev "Auto tour" screenshots under their town names.

The game names screenshots by time (api.gui.camera.takeScreenshot takes no file name), so this pairs the
`[SQOT_DEV] SHOT n= town= view=` lines of the latest tour in stdout.txt with the screenshot files written after
that tour started, in order, and copies them to .cache/ot_shots/<tour start> (gitignored: ~7 MB PNGs)/NN-<town>-<view>.png.

Usage: uv run tools/ot_shots.py [--log PATH] [--shots DIR] [--out DIR] [--dry-run]
"""
import argparse
import glob
import os
import re
import shutil
from datetime import datetime, timezone

USERDATA = glob.glob(os.path.expanduser("~/Library/Application Support/Steam/userdata/*/3493540/local"))
LOCAL = USERDATA[0] if USERDATA else ""
LINE_TS = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)Z")
SHOT = re.compile(r"\[SQOT_DEV\] SHOT n=(\d+) town=(.*?)(?: key=\S+)? view=(\S+) .*?\bok=(\S+)")
TOUR = re.compile(r"\[SQOT_DEV\] TOUR start")


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower()).strip("_") or "town"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", default=os.path.join(LOCAL, "crash_dump", "stdout.txt"))
    ap.add_argument("--shots", default=os.path.join(LOCAL, "screenshots"))
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", ".cache", "ot_shots"))
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    start, shots = None, []
    with open(a.log, encoding="utf-8", errors="replace") as f:
        for line in f:
            if TOUR.search(line):
                m = LINE_TS.match(line)
                start = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc) if m else None
                shots = []
            m = SHOT.search(line)
            if m and m.group(4) == "true":
                t = LINE_TS.match(line)
                ts = datetime.strptime(t.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp() if t else None
                shots.append((int(m.group(1)), m.group(2), m.group(3), ts))
    if start is None or not shots:
        raise SystemExit("no tour with screenshots in " + a.log)

    files = sorted(
        (p for p in glob.glob(os.path.join(a.shots, "*.png"))
         if os.path.getmtime(p) >= start.timestamp() - 1),
        key=os.path.getmtime)
    # Pair by time, not order. The game writes a file about 2 s per screenshot and drops requests while it is
    # busy, so shots get lost; the file's mtime (whole seconds) equals its SHOT line's second (tours 2026-10-11).
    # Each file takes the earliest unused shot in the same second, else the nearest within MATCH_S.
    MATCH_S = 1.5
    used, pairs, taken = set(), [], set()
    for p in files:
        mt = int(os.path.getmtime(p))
        cands = [x for x in shots if x[3] is not None and x[0] not in taken and abs(x[3] - mt) <= MATCH_S]
        cands.sort(key=lambda x: (abs(x[3] - mt), x[0]))
        if not cands:
            continue
        n, town, view, _ = cands[0]
        taken.add(n)
        used.add(p)
        pairs.append((n, town, view, p))
    for n, town, view, _ in shots:
        if n not in taken:
            print(f"shot {n} ({town}, {view}): no file (dropped by the game)")
    for p in files:
        if p not in used:
            print(f"unmatched file: {os.path.basename(p)}")
    out = os.path.join(a.out, start.strftime("%Y-%m-%d_%H-%M-%S"))
    if not a.dry_run:
        os.makedirs(out, exist_ok=True)
    for n, town, view, src in pairs:
        dst = os.path.join(out, f"{n:02d}-{slug(town)}-{view}.png")
        print(f"{os.path.basename(src)} -> {os.path.relpath(dst)}")
        if not a.dry_run:
            shutil.copy2(src, dst)


if __name__ == "__main__":
    main()
