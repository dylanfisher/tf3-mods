"""Unit tests for tools/sqrl_audit.py (the Smart Lanes junction audit report, plans/square_smart_lanes/TESTING.md X).

Run: make test-tools   (uv run --with lupa python -m unittest discover -s tests/tools)
Input: the synthetic log tests/tools/data/sqrl_audit_sample.txt (two loads; AUDIT lines of the automatic pass,
a pick and a ring pick, AUDIT_SUMMARY, SKIP and SUMMARY lines; node 9 audited by two jobs).
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import sqrl_audit as sa  # noqa: E402

SAMPLE = Path(__file__).resolve().parent / "data" / "sqrl_audit_sample.txt"


class CountsTest(unittest.TestCase):
    def test_counts(self):
        self.assertEqual(sa.counts("shared:2,weave:1"), {"shared": 2, "weave": 1})
        self.assertEqual(sa.counts("-"), {})
        self.assertEqual(sa.counts(None), {})
        self.assertEqual(sa.counts("a:1,+3"), {"a": 1})


class ParseTest(unittest.TestCase):
    def setUp(self):
        self.rep = sa.parse([SAMPLE])

    def test_latest_line_per_junction(self):
        self.assertEqual(self.rep.lines, 8)
        self.assertEqual(len(self.rep.audits), 7)
        n9 = self.rep.audits[("auto", "9")]
        self.assertEqual(n9.findings, {"shared": 2}, "job 2's line replaced job 1's")
        self.assertEqual(n9.forced, {"shared": 4})
        self.assertEqual(self.rep.audits[("pick", "2")].findings, {"squeeze": 2, "bypassed_turn": 1})

    def test_by_kind(self):
        by = self.rep.by_kind()
        self.assertEqual(sorted(a.node for a in by["shared"]), ["1", "7", "9"])
        self.assertEqual(sorted(a.node for a in by["squeeze"]), ["2", "500"])
        self.assertNotIn("weave", by)

    def test_summaries_and_skips(self):
        t = self.rep.summaries["auto"]
        self.assertEqual((t["jobs"], t["audited"], t["flagged"]), (3, 14, 6))
        self.assertEqual(self.rep.summary_findings["auto"]["shared"], 9)
        self.assertEqual(self.rep.summary_forced["auto"]["squeeze"], 3)
        self.assertEqual(self.rep.summary_skips, {"ambiguous": 2, "u_turn": 1, "multi_arm": 1})
        self.assertEqual(self.rep.skip_lines[("slip", "ambiguous")], 1)
        self.assertEqual(self.rep.skip_lines[("street (tool)", "no_config")], 1)

    def test_filters(self):
        last = sa.parse([SAMPLE], last=True)
        self.assertNotIn(("auto", "500"), last.audits, "the old load is dropped")
        self.assertEqual(last.summaries["auto"]["jobs"], 2)
        auto = sa.parse([SAMPLE], only_src="auto")
        self.assertEqual({s for s, _ in auto.audits}, {"auto"})
        self.assertNotIn("pick", auto.summaries)


class RobustTest(unittest.TestCase):
    def test_unlogged_and_garbled(self):
        log = "\n".join([
            "  [SQRL] AUDIT node=5 case=X shape=crossroads findings=shared:1 src=auto job=1",
            "  [SQRL] AUDIT node=6 case=X sha",  # truncated mid-line
            "  [SQRL] AUDIT node=7 findings=shared:x,squeeze:,:3,weave:2 forced=",  # garbled values
            "  [SQRL] AUDIT_SUMMARY src=auto job=1 audited=90 flagged=50 findings=shared:60 forced=- unlogged=10",
            "  [SQRL] AUDIT_SUMMARY src=auto job=2 audited=x flagged= findi",
            "\udcff junk [SQRL] lowercase=1",
        ])
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "stdout.txt"
            p.write_text(log + "\n", encoding="utf-8", errors="surrogateescape")
            rep = sa.parse([p])
            text = sa.render(rep)
        self.assertEqual(rep.lines, 3)
        self.assertEqual(rep.audits[("auto", "6")].findings, {})
        self.assertEqual(rep.audits[("auto", "7")].findings, {"weave": 2})
        t = rep.summaries["auto"]
        self.assertEqual((t["jobs"], t["audited"], t["flagged"], t["unlogged"]), (2, 90, 50, 10))
        self.assertIn("50 flagged, 10 flagged without an AUDIT line", text)


class SharedLitTest(unittest.TestCase):
    def test_shared_lit_is_by_design(self):
        # sl_audit.lua: sharing the rule keeps at lit crossroads goes to forced= as shared_lit (never flags)
        log = "\n".join([
            "  [SQRL] AUDIT node=5 case=X shape=crossroads findings=shared:1 forced=shared_lit:4 detail=shared:12:fs src=tool",
            "  [SQRL] AUDIT_SUMMARY src=auto job=1 audited=3 flagged=0 findings=- forced=shared_lit:6,shared:2 skips=-",
        ])
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "stdout.txt"
            p.write_text(log + "\n", encoding="utf-8")
            rep = sa.parse([p])
            text = sa.render(rep)
        self.assertEqual(rep.audits[("tool", "5")].forced, {"shared_lit": 4})
        self.assertNotIn("shared_lit", rep.by_kind(), "never an avoidable finding")
        self.assertEqual(rep.summary_forced["auto"]["shared_lit"], 6)
        self.assertIn("| auto | shared_lit | by design | 6 |", text)
        self.assertLess(text.index("| auto | shared |"), text.index("| auto | shared_lit |"), "sl_audit's order")
        self.assertIn("shared_lit: an exit lane a straight movement shares", text)
        self.assertLess(sa.kind_order("shared_lit"), sa.kind_order("across"))

    def test_shared_open_is_by_design(self):
        # sl_audit.lua (rev 7): merges into an open exit road (a stop or the next junction close by) go to forced=
        log = "  [SQRL] AUDIT_SUMMARY src=auto job=1 audited=1 flagged=0 findings=- forced=shared_lit:2,shared_open:1 skips=-"
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "stdout.txt"
            p.write_text(log + "\n", encoding="utf-8")
            rep = sa.parse([p])
            text = sa.render(rep)
        self.assertEqual(rep.summary_forced["auto"]["shared_open"], 1)
        self.assertIn("| auto | shared_open | by design | 1 |", text)
        self.assertIn("shared_open: an exit lane of an open exit road", text)


class ForcedKindsTest(unittest.TestCase):
    def test_turbo_gap_and_forced_weave(self):
        # sl_audit.lua (showcase 2026-10-12): the turbo ring's empty outer lane is by design, the weave the
        # other movements' lanes force goes to forced= (neither flags a junction)
        log = "\n".join([
            "  [SQRL] AUDIT node=5 case=X shape=crossroads findings=weave:1 forced=weave:15,shared_lit:4 "
            "detail=weave:14>12@2 src=auto job=1",
            "  [SQRL] AUDIT_SUMMARY src=auto job=1 audited=8 flagged=1 findings=weave:1 "
            "forced=weave:60,turbo_gap:6,shared:4 skips=-",
        ])
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "stdout.txt"
            p.write_text(log + "\n", encoding="utf-8")
            rep = sa.parse([p])
            text = sa.render(rep)
        self.assertEqual(rep.audits[("auto", "5")].findings, {"weave": 1})
        self.assertIn("| weave | 1 | 1 | 15 | X:1 | auto:1 |", text)
        self.assertIn("| auto | weave | 1 | 60 |", text)
        self.assertIn("| auto | turbo_gap | by design | 6 |", text)
        self.assertIn("turbo_gap: the ring-out outer lane", text)
        self.assertLess(sa.kind_order("unfed"), sa.kind_order("turbo_gap"))


class RenderTest(unittest.TestCase):
    def test_render(self):
        text = sa.render(sa.parse([SAMPLE]), top=2)
        self.assertIn("AUDIT lines: 8 (7 junction(s)", text)
        self.assertIn("AUDIT_SUMMARY src=auto: 3 job(s), 14 junction(s) audited, 6 flagged.", text)
        self.assertIn("| shared | 3 | 7 | 7 | X:3 | auto:3 |", text)
        self.assertIn("| 7 | 4 | X | crossroads | auto | shared:4 |", text)
        self.assertIn("| ... 1 more |", text)
        self.assertIn("| ambiguous | 2 | slip: 1 |", text)
        # finding sections in sl_audit's order
        self.assertLess(text.index("### squeeze"), text.index("### shared"))
        self.assertLess(text.index("### shared"), text.index("### lights"))

    def test_no_lines(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "stdout.txt"
            p.write_text("[2026-10-11 12:00:00Z - MESSAGE  - Main Thread - Main ]  Game is ready\n")
            out = io.StringIO()
            argv = sys.argv
            sys.argv = ["sqrl_audit.py", str(p)]
            try:
                with contextlib.redirect_stdout(out):
                    sa.main()
            finally:
                sys.argv = argv
            self.assertIn("No [SQRL] AUDIT / SUMMARY / SKIP lines", out.getvalue())


if __name__ == "__main__":
    unittest.main()
