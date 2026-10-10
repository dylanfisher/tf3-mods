"""Which build feature splits placed from refused in a highway probe sweep (Phase 7e2 analysis as a tool).

Reads a probe CSV (or the .log next to it), dumps every unrotated highway combo with
tools/dump_square_roundabouts_highway.lua (in process, ~1.5 s per 1000 keys), measures each build and
prints, per feature, the placed max, the refused min and the best single threshold ("refused if > t")
with its error count, overall and per highway level. A feature with 0 errors explains the refusals.

  make probe-split LOG=plans/square_roundabouts/probe_p7_hx_scale.log [ARGS='--uncap --near xmax']

--uncap  lifts hx.MAX_REACH (needed for runs made before the 7e2 cap, or every refused combo is capped)
--near F also lists the 8 placed and 8 refused combos closest to feature F's threshold
"""
import argparse, csv, math, os, sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))


def dump(keys, uncap):
    import run_tests as r
    os.environ["SQRB_HX_KEY"] = " ".join(keys)
    os.environ["SQRB_HX_DEV"] = ""
    os.environ["SQRB_HX_UNCAP"] = "1" if uncap else ""
    o = r.ModRunner(ROOT / "mods/square_roundabouts").run_file(ROOT / "tools/dump_square_roundabouts_highway.lua", None)
    bad = [x["err"] for x in o["results"] if not x["ok"]]
    if o["load_error"] or bad:
        sys.exit(f"hx-dump failed: {o['load_error'] or bad[0]}")
    return "".join(x["printed"] for x in o["results"])


def parse(text):
    D, cur = {}, None
    for line in text.splitlines():
        if line.startswith("== "):
            cur = line.split()[1]
            D[cur] = []
        elif cur:
            p = line.split()
            if len(p) >= 11 and p[0] in ("highway", "cross", "arms", "ramps"):
                try:
                    D[cur].append((p[0], float(p[3]), list(map(float, p[5:11]))))
                except ValueError:
                    pass
    return D


def feats(edges):
    pts = [(c[i], c[i + 1], c[i + 2]) for _, _, c in edges for i in (0, 3)]
    def mx(role):
        v = [pl for r, pl, _ in edges if r == role]
        return max(v) if v else 0.0
    return {
        "xmax": max(abs(x) for x, _, _ in pts),
        "ymax": max(abs(y) for _, y, _ in pts),
        "radial": max(math.hypot(x, y) for x, y, _ in pts),
        "longest_edge": max(pl for _, pl, _ in edges),
        "longest_hw": mx("highway"),
        "longest_ramp": mx("ramps"),
        "max_grade": max((abs(c[5] - c[2]) / pl for _, pl, c in edges if pl > 0), default=0.0),
        "n_edges": float(len(edges)),
    }


def split(pairs):
    """pairs: (value, placed). Best t for 'refused iff v > t' -> (errors, t)."""
    pairs = sorted(pairs)
    nplaced = sum(1 for _, ok in pairs if ok)
    best = (nplaced, pairs[0][0] - 1)  # t below every value: each placed combo counts as an error
    placed_le = ref_le = 0
    for i, (v, ok) in enumerate(pairs):
        placed_le += ok
        ref_le += not ok
        if i + 1 < len(pairs) and pairs[i + 1][0] == v:
            continue
        err = ref_le + (nplaced - placed_le)
        nxt = pairs[i + 1][0] if i + 1 < len(pairs) else v
        if err < best[0]:
            best = (err, (v + nxt) / 2)
    return best


def table(title, rows):
    print(f"-- {title}: {sum(ok for _, ok, _ in rows)} placed, {sum(not ok for _, ok, _ in rows)} refused")
    if not rows or all(ok for _, ok, _ in rows) or not any(ok for _, ok, _ in rows):
        return
    print(f"   {'feature':<13} {'placed max':>10} {'refused min':>11} {'best t':>8} {'errors':>6}")
    out = []
    for name in rows[0][2]:
        pairs = [(f[name], ok) for _, ok, f in rows]
        pm = max(v for v, ok in pairs if ok)
        rm = min(v for v, ok in pairs if not ok)
        err, t = split(pairs)
        out.append((err, name, pm, rm, t))
    for err, name, pm, rm, t in sorted(out):
        print(f"   {name:<13} {pm:10.2f} {rm:11.2f} {t:8.2f} {err:6d}{'  SEPARATES' if pm < rm else ''}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", type=Path, help="probe .csv, or the .log whose .csv parse_probe wrote")
    ap.add_argument("--uncap", action="store_true", help="lift hx.MAX_REACH while dumping")
    ap.add_argument("--near", help="list the combos closest to this feature's overall threshold")
    ap.add_argument("--all-types", action="store_true", help="include diamonds (default: parclos only)")
    a = ap.parse_args()
    path = a.path.with_suffix(".csv")
    if not path.exists():
        sys.exit(f"{path} missing: run `make probe-report LOGS={a.path.with_suffix('.log')}` first")
    rows = [r for r in csv.DictReader(open(path)) if r.get("entry") == "highway" and not r.get("rot") and r.get("key")]
    if not a.all_types:
        rows = [r for r in rows if r["type"] != "diamond"]
    if not rows:
        sys.exit("no unrotated highway rows")
    D = parse(dump([r["key"] for r in rows], a.uncap))
    data = [(r, r["ok"] == "true", feats(D[r["key"]])) for r in rows if D.get(r["key"])]
    print(f"{path.name}: {len(data)} highway combos{' (uncapped)' if a.uncap else ''}")
    table("all", data)
    by = defaultdict(list)
    for d in data:
        by[d[0]["level"]].append(d)
    for lv, ds in sorted(by.items()):
        table(f"level {lv}", ds)
    if a.near:
        _, t = split([(f[a.near], ok) for _, ok, f in data])
        print(f"-- near {a.near} t={t:.2f}")
        close = sorted(data, key=lambda d: abs(d[2][a.near] - t))
        pick = [d for d in close if d[1]][:8] + [d for d in close if not d[1]][:8]
        for r, ok, f in sorted(pick, key=lambda d: d[2][a.near]):
            print(f"   {'ok ' if ok else 'REF'} {f[a.near]:8.2f} {r['key']} {r['type']} {r['level']} {r['cross']} "
                  f"size={r['size']} ramp={r['ramp']} arm={r['armlen']} {r['msgs'][:40]}")


if __name__ == "__main__":
    main()
