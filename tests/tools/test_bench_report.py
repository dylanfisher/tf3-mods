"""Unit tests for tools/bench_report.py (the Stress Test bench report, plans/square_stress_test/BENCH.md).

Run: make test-tools. A synthetic bench log: BENCH_START / BENCH_TEST / zone lines of two tests (rb4: 3 sets of game /
sl / sl_keeplights; drop: 2 sets of game / sl), 20 samples per zone (the first 6 in the warm-up), Smart Lanes zid=
lines, one sl twin without its APPLY (excluded: treatment), BENCH_DONE.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import bench_report as br  # noqa: E402

PFX = "[2026-10-13 12:00:00Z - MESSAGE  - Main Thread      - Main           ]  "


def bench_log(no_apply: str | None = None, done: bool = True, seed: int = 42) -> list[str]:
    out = ["[SQRL] MODE phases=game free_turn=always lights=on",
           f"[SQST] BENCH_START sheet=s1 spec=bench_s1@1 seed={seed} map=16000x16000 tests=2 groups=13 towns=44 year=1950 "
           "sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=game,sl,sl_keeplights warmup_s=180 record_s=1200 "
           "interval_s=10 speed=2",
           "[SQST] BENCH_TEST sheet=s1 id=rb4 title=Roundabout kind=rb variants=RB4_2L twins=game,sl,sl_keeplights "
           "compare=sl:game,sl:sl_keeplights sets=3/9 groups=9 towns=36 towns_per_twin=4 pop=400 lights=game",
           "[SQST] BENCH_TEST sheet=s1 id=drop title=Lane_drop kind=plain variants=Lane_drop_3-2 twins=game,sl compare=sl:game "
           "sets=2/6 groups=4 towns=8 towns_per_twin=2 pop=400 lights=game",
           "[SQST] showcase zones sent n=13 run=s42-1-1 by_ab=game:5,sl:5,sl_phases:0,sl_keeplights:3 smart_lanes=yes"]
    zones = []
    zi = 0
    for s in range(1, 6):
        test = "rb4" if s <= 3 else "drop"
        twins = [("b", "game"), ("a", "sl"), ("f", "sl_keeplights")] if test == "rb4" else [("b", "game"), ("a", "sl")]
        for letter, ab in twins:
            zi += 1
            zid = f"g{s}{letter}"
            kind = "roundabout" if test == "rb4" else "plain"
            label = "RB4_2L" if test == "rb4" else "Lane_drop_3-2"
            x = zi * 3000
            out.append(f"[SQST] showcase zone id={zid} pair=g{s} ab={ab} kind={kind} type={label} x={x} y=0 r=120 r_from=measured "
                       f"towns=4 match=yes test={test} variant={label} approach=518")
            zones.append((zi, zid, s, ab, x, test))
    # Smart Lanes: every sl / keeplights twin applied, every game twin skipped; keeplights twins kept lights
    for zi, zid, s, ab, x, test in zones:
        if ab == "game":
            out.append(f"[SQRL] SKIP kind=zone zone=game job=1 nodes=4 reason=zone_game zid={zid}")
        elif zid != no_apply:
            if test == "rb4":
                out.append(f"[SQRL] APPLY ring={zi} node={zi} lanes=2 dir=ccw zid={zid}")
            else:
                out.append(f"[SQRL] APPLY kind=drop node={zi} shape=lane_drop+gain case=D zid={zid}")
        if ab == "sl" and test == "rb4":
            out.append(f"[SQRL] LIGHTS src=auto node={zi} before=auto light=true to=off zid={zid}")
        if ab == "sl_keeplights":
            out.append(f"[SQRL] LIGHTS src=auto node={zi} to=kept zone=sl_keeplights zid={zid}")
    out.append("[SQST] BENCH_PHASE sheet=s1 phase=warmup gt=1000000 ms=1 speed=2")
    out.append("[SQST] FLOW_START run=1 v=3 interval=10 interval_unit=game_s zones=13 gt=1000000 gt_per_s=1000 src=placement sc_run=s42-1-1")
    for zi, zid, s, ab, x, test in zones:
        out.append(f"[SQST] FLOW_ZONE run=1 zone={zi} kind=x src=placement label=x x={x} y=0 r=120 twin={zid} pair=g{s} ab={ab}")
    for k in range(1, 21):
        gt = 1000000 + k * 30000
        if k == 19:
            out.append(f"[SQST] BENCH_PHASE sheet=s1 phase=record gt={gt} ms=2 speed=2 samples_so_far=18")
        for zi, zid, s, ab, x, test in zones:
            # sl faster than game by 2 m/s; sl_keeplights 1 m/s slower than sl in sets 1-2, faster in set 3
            v = 5.0 + (2.0 if ab == "sl" else 0.0) + ((1.0 if s == 3 else 1.0) if ab == "sl_keeplights" else 0.0)
            if ab == "sl_keeplights" and s == 3:
                v = 7.5
            thru = 30 + (5 if ab == "sl" else 0)
            out.append(f"[SQST] FLOW run=1 s={k} zone={zi} twin={zid} pair=g{s} ab={ab} gt={gt} cars=10 standing=2 standing_pct=20 "
                       f"queue=1 v_mean={v} v_med={v} v_kmh={v * 3.6:.1f} stand_mean=6 stand_max=9 cars_core=4 q_arm=- thru={thru if k > 1 else '-'} "
                       f"thru_s={30 if k > 1 else '-'} thru_scale=1 thru_path=-")
        out.append(f"[SQST] FLOW_ALL run=1 s={k} gt={gt} drivers=100 sampled=100 in_zones=50 standing=20 standing_pct=20 queue=5 "
                   f"v_mean=6 capped=0 stride=1 frame_ms_max=1.5")
    if done:
        out.append("[SQST] BENCH_DONE sheet=s1 spec=bench_s1@1 seed=42 ok=yes samples=20 speed=1 minutes=25.0 problems=0")
    return [PFX + x for x in out]


class StatsTest(unittest.TestCase):
    def test_wilcoxon(self):
        self.assertAlmostEqual(br.wilcoxon([1, 2, 3, 4, 5, 6]), 2 / 64)
        self.assertIsNone(br.wilcoxon([]))
        self.assertAlmostEqual(br.wilcoxon([1, -1]), 1.0)
        p = br.wilcoxon([3, 4, 5, 6, 7, -1])
        self.assertTrue(0.03 < p < 0.07, p)

    def test_holm(self):
        self.assertEqual(br.holm([0.01, 0.04, None]), [0.02, 0.04, None])
        self.assertEqual(br.holm([0.03, 0.03]), [0.06, 0.06])


class ReportTest(unittest.TestCase):
    def run_report(self, lines, *extra):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "2026-10-13_1200_bench-s1-42.log"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            rep = br.fr.parse([p])
            rows, excluded = br.build_rows(b, rep)
            text = br.render(b, rows, excluded, br.map_wide([p]), "2026-10-13_1200_bench-s1-42", [], False)
            return b, rows, excluded, text

    def test_tables(self):
        b, rows, excluded, text = self.run_report(bench_log())
        self.assertEqual(b.sheet, "s1")
        self.assertEqual(set(b.tests), {"rb4", "drop"})
        self.assertEqual(b.record_speed, "2")
        got = {(r.test, r.compare): r.stats() for r in rows}
        self.assertEqual(got[("rb4", "sl vs game")]["n"], 3)
        self.assertEqual(got[("rb4", "sl vs game")]["w"], 3)
        self.assertAlmostEqual(got[("rb4", "sl vs game")]["mean"], 7.2)
        self.assertEqual(got[("drop", "sl vs game")]["n"], 2)
        kl = got[("rb4", "sl vs sl_keeplights")]
        self.assertEqual((kl["w"], kl["l"]), (2, 1))
        self.assertAlmostEqual(got[("rb4", "sl vs game")]["thru"], 10.0, msg="5 per 30 s more")
        self.assertEqual(excluded, [])
        self.assertIn("### Bench sheet s1: 2026-10-13_1200_bench-s1-42 (seed 42)", text)
        self.assertIn("| rb4 | sl vs game | 3 | +7.2 | 3/0/0 |", text)
        self.assertIn("run complete", text)
        self.assertIn("no lights at roundabouts and ramps on", text)
        self.assertIn("rb4: game 3 (applied 0, unchanged 0, skipped 3, lights off 0, kept 0, lit at read 0), sl 3 (applied 3, unchanged 0, skipped 0, lights off 3", text)
        self.assertIn("- rb4, sl vs game: sl better by +7.2 km/h, 3/3 pairs", text)
        self.assertNotIn("| all |", text)

    def test_treatment_excludes_a_twin_without_its_mode(self):
        _b, rows, excluded, _text = self.run_report(bench_log(no_apply="g2a"))
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual(got[("rb4", "sl vs game")], 2)
        self.assertEqual(got[("rb4", "sl vs sl_keeplights")], 2)
        self.assertTrue(any("treatment: sl twin: Smart Lanes neither applied nor looked at it" in e[2] for e in excluded), excluded)

    def test_incomplete_and_record(self):
        _b, _rows, _excl, text = self.run_report(bench_log(done=False))
        self.assertIn("incomplete (no BENCH_DONE)", text)
        with tempfile.TemporaryDirectory() as d:
            ledger, results = Path(d) / "ledger.json", Path(d) / "RESULTS.md"
            results.write_text("# R\n\n## Runs\n\n### Run 6: old\n", encoding="utf-8")
            old_l, old_r = br.LEDGER, br.RESULTS
            br.LEDGER, br.RESULTS = ledger, results
            try:
                b, rows, excluded, text = self.run_report(bench_log())
                br.record(b, rows, "2026-10-13_1200_bench-s1-42", text, [])
                data = json.loads(ledger.read_text())
                self.assertEqual(len(data), 3 + 3 + 2)
                self.assertTrue(results.read_text().index("### Bench sheet s1") < results.read_text().index("### Run 6"))
                # a second run of the same spec pools with the first
                text2 = br.render(b, rows, excluded, {"standing": 20.0, "samples": 2, "capped": 0, "strided": 0, "targets": 0,
                                                       "frame_max": 1.0, "thru_path": 0}, "second", data, False)
                self.assertIn("Pooled with the earlier runs of this spec", text2)
                self.assertIn("| rb4 | sl vs game | 2 | 6 | +7.2 | 6/0 |", text2)
            finally:
                br.LEDGER, br.RESULTS = old_l, old_r


if __name__ == "__main__":
    unittest.main()


class TwoRunsOneSessionTest(unittest.TestCase):
    def test_two_runs_in_one_session_both_recorded(self):
        with tempfile.TemporaryDirectory() as d:
            ledger, results = Path(d) / "ledger.json", Path(d) / "RESULTS.md"
            results.write_text("# R\n\n## Runs\n", encoding="utf-8")
            old_l, old_r = br.LEDGER, br.RESULTS
            br.LEDGER, br.RESULTS = ledger, results
            try:
                session = "2026-10-13_1200_bench-s1-42"
                for seed in (42, 43):
                    p = Path(d) / f"{seed}.log"
                    p.write_text("\n".join(bench_log(seed=seed)) + "\n", encoding="utf-8")
                    b = br.read_bench([p])
                    rows, excluded = br.build_rows(b, br.fr.parse([p]))
                    led = br.load_ledger()
                    text = br.render(b, rows, excluded, br.map_wide([p]), session, led, True)
                    br.record(b, rows, session, text, led)
                    # recording the same run again replaces its rows, adds no second entry
                    br.record(b, rows, session, text, br.load_ledger())
                data = json.loads(ledger.read_text())
                self.assertEqual(len(data), 2 * 8)
                self.assertEqual({e["seed"] for e in data}, {"42", "43"})
                res = results.read_text()
                self.assertEqual(res.count("### Bench sheet s1:"), 2)
            finally:
                br.LEDGER, br.RESULTS = old_l, old_r


REAL = Path(__file__).resolve().parent / "data" / "bench_0610_sample.txt"


class RealSheet1Test(unittest.TestCase):
    """Real lines of session 2026-10-13_0610_session (sheet 1, seed 954486; pairs g1 rb4 and g10 drop kept): the log has
    no BENCH_TEST lines and Smart Lanes' `APPLY kind=drop` lines carry no zid=. The first `make bench` printed empty
    tables (no tests) and would have excluded every lane drop pair (treatment)."""

    def test_tables_from_the_zone_lines(self):
        b = br.read_bench([REAL])
        self.assertEqual(b.sheet, "s1")
        self.assertTrue(b.tests_derived)
        self.assertEqual(b.tests["rb4"].compare, [("sl", "game"), ("sl", "sl_keeplights")])
        self.assertEqual(b.tests["drop"].compare, [("sl", "game")])
        self.assertTrue(b.summary.startswith("summary seed=954486 "), b.summary)
        rows, excluded = br.build_rows(b, br.fr.parse([REAL]))
        got = {(r.test, r.compare): r.stats() for r in rows}
        self.assertEqual(got[("rb4", "sl vs game")]["n"], 1)
        self.assertEqual(got[("rb4", "sl vs game")]["w"], 1)
        self.assertEqual(got[("rb4", "sl vs sl_keeplights")]["n"], 1)
        self.assertEqual(got[("drop", "sl vs game")]["n"], 1, "the lane drop pair is kept (its sl twin unchecked, not excluded)")
        self.assertEqual(excluded, [])
        text = br.render(b, rows, excluded, br.map_wide([REAL]), "2026-10-13_0610_session", [], False)
        self.assertIn("| rb4 | sl vs game | 1 | +1.5 |", text)
        self.assertIn("[its Smart Lanes APPLY lines carry no zid=: the sl twins were not checked]", text)
        self.assertIn("Tests: from the zone lines", text)
        self.assertIn("- rb4, sl vs game: sl better by +1.5 km/h", text)


class TreatmentKindsTest(unittest.TestCase):
    def report(self, extra, geometry_bad=False):
        lines = bench_log(no_apply="g4a")
        lines = [l for l in lines if "zid=g4a" not in l]
        lines += [PFX + x for x in extra]
        if geometry_bad:
            lines.append(PFX + "[SQST] BENCH_TWIN id=g5a test=drop ab=sl nodes=0 lit_nodes=0 phase=read geometry=bad what=lane_drop "
                         "two_street_nodes=1 lanes=same")
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "x.log"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            rows, excluded = br.build_rows(b, br.fr.parse([p]))
            return b, {(r.test, r.compare): r.stats()["n"] for r in rows}, excluded

    def test_same_or_plain_counts_as_treated(self):
        _b, n, excl = self.report(["[SQRL] SKIP kind=drop node=7 reason=same zid=g4a"])
        self.assertEqual(n[("drop", "sl vs game")], 2, excl)

    def test_only_plain_nodes_where_a_drop_is_expected(self):
        _b, n, excl = self.report(["[SQRL] SKIP kind=node node=7 reason=plain zid=g4a"])
        self.assertEqual(n[("drop", "sl vs game")], 1)
        self.assertTrue(any("saw no drop junction (only node)" in e[2] for e in excl), excl)

    def test_geometry_bad_twin_excluded(self):
        _b, n, excl = self.report(["[SQRL] SKIP kind=drop node=7 reason=same zid=g4a"], geometry_bad=True)
        self.assertEqual(n[("drop", "sl vs game")], 1)
        self.assertTrue(any("geometry: the twin does not present its test" in e[2] for e in excl), excl)


class DraftNameTest(unittest.TestCase):
    def test_draft_name_has_sheet_and_seed(self):
        import subprocess
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "sess.log"
            p.write_text("\n".join(bench_log()) + "\n", encoding="utf-8")
            subprocess.run([sys.executable, str(Path(br.__file__)), str(p), "--out", d], check=True, capture_output=True)
            self.assertTrue((Path(d) / "sess_s1-42.md").is_file(), list(Path(d).iterdir()))


class ZidScopeTest(unittest.TestCase):
    """Session 2026-10-13_0610_session ran sheets 1 and 2: zone ids repeat (g1a, g10a ...), so a zid= line belongs to the
    run whose zones Smart Lanes held then (its zones set to the next set / clear), never to the other sheet's."""

    def test_two_sheets_in_one_log(self):
        s1 = bench_log(seed=42)
        s2 = [l.replace("sheet=s1", "sheet=s2").replace("bench_s1", "bench_s2").replace("run=s42-1-1", "run=s43-1-1")
              .replace("seed=42", "seed=43") for l in bench_log(seed=43)]
        # sheet 2's Smart Lanes lines: its g4a twin (a drop sl twin in sheet 1's terms) written; sheet 1's g4a was not
        s1 = [l for l in s1 if "zid=g4a" not in l]
        s1.insert(5, PFX + "[SQRL] ZONES op=set n=13 run=s42-1-1 by_ab=game:5,sl:5,sl_phases:0,sl_keeplights:3")
        s2.insert(5, PFX + "[SQRL] ZONES op=set n=13 run=s43-1-1 by_ab=game:5,sl:5,sl_phases:0,sl_keeplights:3")
        # a late line of sheet 1's zones after sheet 2's zones were set, inside sheet 2's slice: not sheet 2's
        late = PFX + "[SQRL] APPLY kind=drop node=9 zid=g4a"
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "both.log"
            p.write_text("\n".join(s1 + s2) + "\n", encoding="utf-8")
            b1 = br.read_bench([p], "s1")
            b2 = br.read_bench([p], "s2")
            self.assertEqual((b1.sheet, b1.seed, b2.sheet, b2.seed), ("s1", "42", "s2", "43"))
            self.assertEqual(b1.applied.get("g4a", 0), 0, "sheet 2's g4a lines are not sheet 1's")
            self.assertEqual(b2.applied.get("g4a", 0), 1)
            rows1, excl1 = br.build_rows(b1, br.fr.parse([p]))
            self.assertTrue(any(e[0].split("#")[0] == "g4" and "neither applied nor looked" in e[2] for e in excl1), excl1)
            # a zid line before a run's own zones were set (the preflight's clear, the build of the run before) is ignored
            pre = s2[:]
            pre.insert(2, late)
            p.write_text("\n".join(s1 + pre) + "\n", encoding="utf-8")
            self.assertEqual(br.read_bench([p], "s2").applied.get("g4a", 0), 1)
