"""Unit tests for tools/perf_report.py (the [SQPERF] log report, plans/sqperf/README.md).

Run: make test-tools   (uv run --with lupa python -m unittest discover -s tests/tools)
Input: the synthetic logs tests/tools/data/sqperf_sample.txt (two loads, two mods, every line kind) and
sqperf_last.txt (a load with SQPERF lines, then a finished and a still-starting load without any).
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import perf_report as pr  # noqa: E402

SAMPLE = Path(__file__).resolve().parent / "data" / "sqperf_sample.txt"
LAST = Path(__file__).resolve().parent / "data" / "sqperf_last.txt"


class ParseTest(unittest.TestCase):
    def setUp(self):
        self.rep = pr.parse([SAMPLE])

    def test_loads(self):
        loads = self.rep.loads
        self.assertEqual(len(loads), 2)
        self.assertEqual(loads[0].name, "Big Save")
        self.assertEqual(loads[0].init_s, 22.5)
        self.assertEqual(loads[0].last_step_s(), 16.0)
        self.assertEqual(loads[1].name, "(unnamed)")
        self.assertEqual(loads[1].init_s, 5.0)

    def test_phases(self):
        ph = [(p.load, p.mod, p.ctx, p.phase, p.ms, p.thread) for p in self.rep.phases]
        self.assertIn((1, "square_problem_radar", "gs", "init", 212.4, "Simulation Threa"), ph)
        self.assertIn((1, "square_problem_radar", "gui", "first", 15900.2, "Main Thread"), ph)
        self.assertIn((2, "square_problem_radar", "gs", "init", 180.0, "Main Thread"), ph)
        first = next(p for p in self.rep.phases if p.phase == "first" and p.ctx == "gs")
        self.assertEqual(first.detail, "scan_lines=40.1 scan_stations=7.9")

    def test_slow(self):
        s = self.rep.slow[("square_problem_radar", "gs", "scan_lines")]
        self.assertEqual((s.calls_logged, s.max, s.slow, s.calls), (1, 61.5, 1, 25))
        self.assertEqual(self.rep.slow[("square_problem_radar", "gui", "hud_render")].max, 15900.2)

    def test_windows(self):
        gs = self.rep.windows[("square_problem_radar", "gs")]
        self.assertEqual(gs.windows, 2)
        self.assertAlmostEqual(gs.wall_s(), 60.0041)
        self.assertEqual((gs.secs["scan_lines"].n, gs.secs["scan_lines"].ms, gs.secs["scan_lines"].max), (25, 60.0, 61.5))
        self.assertEqual(dict(gs.counts), {"toasts": 4, "stateSet": 4})
        self.assertEqual((gs.mem_last, gs.mem_max), (5300, 5300))
        gui = self.rep.windows[("square_problem_radar", "gui")]
        self.assertFalse(gui.secs["poll_hud"].timed)
        self.assertTrue(gui.secs["hud_render"].timed)

    def test_skip_and_filters(self):
        rep = pr.parse([SAMPLE], skip=1)
        self.assertEqual(rep.windows[("square_problem_radar", "gs")].windows, 1)
        self.assertNotIn(("square_problem_radar", "gui"), rep.windows)
        self.assertEqual(rep.skipped_windows, 2)
        only = pr.parse([SAMPLE], only_mod="square_other")
        self.assertEqual(only.mods(), ["square_other"])
        last = pr.parse([SAMPLE], last_load=True)
        self.assertEqual(len(last.loads), 1)
        self.assertEqual([p.ms for p in last.phases], [180.0])
        self.assertEqual((last.loads[0].index, last.loads[0].start, last.loads[0].init_s),
                         (2, "2026-10-10 10:01:07Z", 5.0))

    def test_render(self):
        text = pr.render(self.rep)
        self.assertIn("## square_problem_radar", text)
        self.assertIn("## square_other", text)
        self.assertIn("| gui | hud_render | 1 | 15,900 | 1 | 1 | Main Thread |", text)
        self.assertIn("| poll_hud (count only) | 30 |", text)
        self.assertIn("| toasts (counter) | 4 |", text)

    def test_last_skips_newer_loads_without_sqperf(self):
        rep = pr.parse([LAST], last_load=True)
        self.assertEqual([p.load for p in rep.phases], [1, 1])
        self.assertEqual(rep.lines, 3)
        rows = [(ld.index, ld.name, ld.start, ld.init_s, ld.last_step_s(), ld.sqperf) for ld in rep.loads]
        self.assertEqual(rows, [
            (1, "sub-arctic", "2026-10-10 04:00:56Z", 9.5, 3.0, 3),
            (2, "New Game - desert", "2026-10-10 04:16:30Z", 7.9, 2.0, 0),
            (3, "Blank Slate", "2026-10-10 04:20:48Z", None, None, 0),
        ])
        self.assertEqual(len(rep.notes), 1)
        self.assertIn("load 1 of 3", rep.notes[0])
        self.assertIn("2 newer load(s) without [SQPERF] lines", rep.notes[0])
        text = pr.render(rep)
        self.assertTrue(text.startswith("--last: sqperf_last.txt load 1 of 3"))
        self.assertIn("| 2 | sqperf_last.txt | New Game - desert | 2026-10-10 04:16:30Z | 7.9 s | 2 s | 0 |", text)

    def test_last_with_mod_filter_and_full_parse(self):
        # --mod with no lines anywhere: falls back to the last load, rows still complete
        rep = pr.parse([LAST], only_mod="square_other", last_load=True)
        self.assertEqual(rep.lines, 0)
        self.assertEqual([(ld.index, ld.start) for ld in rep.loads], [(3, "2026-10-10 04:20:48Z")])
        self.assertEqual(rep.notes, [])
        # without --last every load is listed with its start, init and gap
        full = pr.parse([LAST])
        self.assertEqual([(ld.start, ld.init_s) for ld in full.loads],
                         [("2026-10-10 04:00:56Z", 9.5), ("2026-10-10 04:16:30Z", 7.9), ("2026-10-10 04:20:48Z", None)])
        # two files: load numbers keep counting across files
        both = pr.parse([SAMPLE, LAST], last_load=True)
        self.assertEqual([ld.index for ld in both.loads], [2, 3, 4, 5])
        self.assertEqual(sorted({p.load for p in both.phases}), [2, 3])

    def test_no_sqperf_lines(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "stdout.txt"
            p.write_text("[2026-10-10 10:00:00Z - MESSAGE  - Main Thread      - Main           ]  Game is ready\n")
            rep = pr.parse([p])
            self.assertEqual(rep.lines, 0)
            self.assertEqual(rep.mods(), [])


if __name__ == "__main__":
    unittest.main()
