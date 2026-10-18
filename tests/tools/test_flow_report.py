"""Unit tests for tools/flow_report.py (the Stress Test traffic flow A/B report, plans/square_stress_test/FLOW.md).

Run: make test-tools   (uv run --with lupa python -m unittest discover -s tests/tools)
Input: the synthetic log tests/tools/data/flow_sample.txt: one Showcase (pairs g1 and g5 Magic_Roundabout sl/game,
g2 Crossroads sl/game/sl_phases with sl worse than game, g3 match=no reason=town, g4 without its game twin), a
town cluster zone without a twin, two loads of the same save (gt restarts lower; 12 and 10 samples, the first 6 of
each in the 180 s warm-up with junk values), FLOW_BUS lines paired by pair=/ab=, FLOW_TOWNS, a FLOW line without
cars and a cut-off last line.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import flow_report as fr  # noqa: E402

SAMPLE = Path(__file__).resolve().parent / "data" / "flow_sample.txt"
PFX = "[2026-10-12 12:00:00Z - MESSAGE  - Main Thread      - Main           ]  "


def write_log(d: str, lines: list[str], end: str = "\n") -> Path:
    p = Path(d) / "stdout.txt"
    p.write_text("\n".join(PFX + x if x.startswith("[SQ") else x for x in lines) + end, encoding="utf-8")
    return p


class HelpersTest(unittest.TestCase):
    def test_num(self):
        self.assertEqual(fr.num("13.9"), 13.9)
        self.assertEqual(fr.num("1.2e+03"), 1200.0)
        self.assertIsNone(fr.num("-"))
        self.assertIsNone(fr.num(None))
        self.assertIsNone(fr.num("x1"))
        self.assertIsNone(fr.num("nan"))

    def test_sign_test(self):
        self.assertEqual(fr.sign_test(2, 0), 0.5)
        self.assertEqual(fr.sign_test(0, 0), None)
        self.assertAlmostEqual(fr.sign_test(9, 1), 22 / 1024)
        self.assertEqual(fr.sign_test(3, 3), 1.0)

    def test_pctl(self):
        self.assertEqual(fr.pctl(list(range(1, 11)), 90), 9)
        self.assertIsNone(fr.pctl([], 90))


class ParseTest(unittest.TestCase):
    def setUp(self):
        self.rep = fr.parse([SAMPLE])

    def test_loads_split_at_reload(self):
        self.assertEqual(len(self.rep.loads), 2)
        self.assertEqual([ld.name for ld in self.rep.loads], ["Showcase Test", "Showcase Test"])
        self.assertEqual(self.rep.loads[0].first_gt, 1000000)
        self.assertEqual(self.rep.loads[1].first_gt, 1100000, "gt restarts with the load")
        self.assertEqual(self.rep.partial, 2, "the FLOW line without cars and the cut-off last line")

    def test_zones_join_showcase_and_pool_loads(self):
        g1a = self.rep.zones[("sc", 1, "g1a")]
        self.assertEqual((g1a.pair, g1a.ab, g1a.kind, g1a.type), ("g1", "sl", "roundabout", "Magic_Roundabout"))
        self.assertEqual(g1a.n(), 10, "6 kept in load 1 + 4 in load 2")
        self.assertEqual(g1a.dropped, 12, "6 warm-up samples per load")
        self.assertAlmostEqual(g1a.speed_kmh(), 8.0 * 3.6)
        self.assertAlmostEqual(g1a.standing_pct(), 20)
        self.assertAlmostEqual(g1a.queue_mean(), 1.0)
        self.assertAlmostEqual(g1a.stand_mean(), 6.0)
        self.assertIsNone(self.rep.zones[("sc", 1, "g4a")].stand_mean(), "no car standing")
        raw = [z for z in self.rep.zones.values() if z.key[0] == "raw"]
        self.assertEqual([z.label for z in raw], ["Grid_S1"])
        self.assertEqual(raw[0].n(), 10)

    def test_pairs_and_exclusions(self):
        got = {(p.pair, p.a, p.b) for p in self.rep.pairs}
        self.assertEqual(got, {("g1", "sl", "game"), ("g5", "sl", "game"), ("g2", "sl", "game"),
                               ("g2", "sl_phases", "game"), ("g2", "sl_phases", "sl")})
        excl = {e[0]: e[3] for e in self.rep.excluded}
        self.assertIn("match=no (town)", excl["g3"])
        self.assertIn("missing twin: game", excl["g4"])
        g2 = next(p for p in self.rep.pairs if (p.pair, p.a) == ("g2", "sl"))
        self.assertAlmostEqual(g2.d_speed(), -3.6)
        self.assertAlmostEqual(g2.d_speed_pct(), -100 / 6)
        self.assertEqual(g2.worse(10), ["speed -17%"])
        self.assertEqual(next(p for p in self.rep.pairs if p.pair == "g1").worse(10), [])

    def test_last_and_options(self):
        last = fr.parse([SAMPLE], last=True)
        self.assertEqual(len(last.loads), 1)
        self.assertEqual(last.zones[("sc", 1, "g1a")].n(), 4)
        self.assertEqual(last.pairs, [], "4 samples < --min-samples 5")
        self.assertTrue(any("under 5 samples" in e[3] for e in last.excluded))
        nowarm = fr.parse([SAMPLE], warmup=0, min_samples=3)
        self.assertEqual(nowarm.zones[("sc", 1, "g1a")].n(), 22)
        self.assertEqual(len(nowarm.pairs), 5)


class RenderTest(unittest.TestCase):
    def test_render(self):
        text = fr.render(fr.parse([SAMPLE]))
        self.assertIn("| 1 | flow_sample.txt | Showcase Test | game | 1 | 132 | 66 | 6.0 |", text)
        self.assertIn("| g1a | roundabout | Magic_Roundabout | sl | 10 | 10.0 | 28.8 | 20 | 6.0 / 6.0 / 6.0 | 1.0 |", text)
        self.assertIn("| g3a (match=no) |", text)
        self.assertIn("| g2 | plain | Crossroads | sl vs game | 10 / 10 | 18.0 / 21.6 | -3.6 | -17 | +10 | +1.0 | +1.0 |",
                      text)
        self.assertIn("| roundabout/Magic_Roundabout | sl vs game | 2 | +4.5 | 2/0/0 | 0.500 |", text)
        self.assertIn("| all | sl vs game | 3 | +1.8 | 2/1/0 | 1.000 |", text)
        self.assertIn("| g4 | plain | T_junction | missing twin: game", text)
        self.assertIn("| g2 | plain | Crossroads | sl | g2a | 18.0 (21.6) | 30 (20) | speed -17% |", text)
        self.assertIn("| roundabout | Magic_Roundabout | sl | 2 | 20 | 11.0 | 26.8 | 23 |", text)
        self.assertIn("| Grid_S1 | town | - | - | 10 |", text)
        self.assertIn("(warm-up)", text)
        self.assertIn("| g1 | sl vs game | 200 / 240 | -40 |", text)
        self.assertIn("| Grid_S1 | 11 | 0.40 |", text)
        self.assertIn("| 2 | 2 | 30 | 4 | 11 | (no summary) |", text)
        self.assertNotIn("Toggle blocks", text)
        self.assertLess(text.index("## Twins: per pair"), text.index("## Pooled per kind / type"))


class RobustTest(unittest.TestCase):
    def test_no_showcase_garbled_and_warnings(self):
        lines = [
            "    | mod params:",
            "[SQST] showcase zones sent n=2 run=r9 by_ab=game:1,sl:1 smart_lanes=no",
            "[SQST] showcase zones ack=timeout run=r9 ms=5000",
            "[SQRL] ZONES op=loaded n=2 run=r8",
            "[SQST] FLOW_START run=1 keep_cleared=1 gt=0",
            "[SQST] FLOW_ZONE run=1 zone=1 kind=rb label=Foo x=1 y=2",
            "[SQST] FLOW run=1 s=1 zone=1 gt=0 cars=4 standing=- v_mean=- stand_mean=-",
            "[SQST] FLOW run=1 s=2 zone=2 gt=1000 cars=2 standing=2 v_mean=0.1",  # zone without FLOW_ZONE
            "[SQST] FLOW run=1 s=2 zon",
        ]
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
            text = fr.render(rep)
        self.assertEqual(len(rep.zones), 2)
        foo = rep.zones[("raw", "Foo", 0, 0, 1)]
        self.assertIsNone(foo.speed_kmh())
        self.assertEqual(foo.standing_pct(), 0)
        self.assertIn("Keep traffic cleared was on", text)
        self.assertIn("ack=timeout", text)
        self.assertIn("smart_lanes=no", text)
        self.assertIn("Smart Lanes holds zones of run r8", text)
        self.assertIn("No FLOW zone matched", text)
        self.assertIn("| load 1 run 1 zone 2 |", text)

    def test_new_showcase_reusing_ids_not_pooled(self):
        def showcase(run, dx):
            return [f"[SQST] showcase zones sent n=2 run={run} smart_lanes=yes",
                    f"[SQST] showcase zone id=g1a pair=g1 ab=sl kind=plain type=X x={dx} y=0 r=90 match=yes",
                    f"[SQST] showcase zone id=g1b pair=g1 ab=game kind=plain type=X x={dx + 400} y=0 r=90 match=yes"]
        lines = ["    | mod params:", *showcase("r1", 0), "[SQST] FLOW_START run=1 gt=0",
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=x x=0 y=0 r=90",
                 "[SQST] FLOW run=1 s=1 zone=1 gt=0 cars=1 standing=0 v_mean=5",
                 *showcase("r2", 0), "[SQST] FLOW_START run=2 gt=600000",
                 "[SQST] FLOW_ZONE run=2 zone=1 kind=x x=0 y=0 r=90",
                 "[SQST] FLOW run=2 s=1 zone=1 gt=600000 cars=1 standing=0 v_mean=7",
                 "[SQST] FLOW run=2 s=2 zone=1 gt=900000 cars=1 standing=0 v_mean=9"]
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)])
        g1 = rep.zones[("sc", 1, "g1a")]
        self.assertEqual((g1.n(), g1.dropped), (0, 1), "first Showcase: own samples only (in its warm-up)")
        g2 = rep.zones[("sc", 2, "g1a")]
        self.assertEqual((g2.n(), g2.dropped), (1, 1), "second Showcase warms up from its own first sample")

    def test_join_explicit_ids_and_one_zone_per_twin(self):
        lines = ["    | mod params:", "[SQST] showcase zones sent n=2 run=r1 smart_lanes=yes",
                 "[SQST] showcase zone id=g1a pair=g1 ab=sl kind=plain type=X x=0 y=0 r=90 match=yes",
                 "[SQST] showcase zone id=g1b pair=g1 ab=game kind=plain type=X x=180 y=0 r=90 match=yes",
                 "[SQST] FLOW_START run=1 gt=0 gt_per_s=1",
                 # explicit ids win over position (both centres sit nearer the other twin)
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=x twin=g1b pair=g1 ab=game x=10 y=0 r=90",
                 "[SQST] FLOW_ZONE run=1 zone=2 kind=x pair=g1 ab=sl x=170 y=0 r=90",
                 # an unknown explicit id is never guessed by position; a town never joins a junction twin
                 "[SQST] FLOW_ZONE run=1 zone=3 kind=x twin=g9a x=0 y=0 r=90",
                 "[SQST] FLOW_ZONE run=1 zone=4 kind=town label=T x=0 y=0 r=300"]
        for z in (1, 2, 3, 4):
            lines.append(f"[SQST] FLOW run=1 s=1 zone={z} gt=0 cars=1 standing=0 v_mean={z}")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
        self.assertEqual(rep.loads[0].gps, 1, "FLOW_START gt_per_s=")
        self.assertEqual(rep.zones[("sc", 1, "g1b")].samples[0].v_mean, 1)
        self.assertEqual(rep.zones[("sc", 1, "g1a")].samples[0].v_mean, 2)
        self.assertEqual(sorted(z.key[0] for z in rep.zones.values()), ["raw", "raw", "sc", "sc"])

    def test_lights_showcase_four_twins_pair_sl_fan(self):
        """Lights showcase: a, b, c, d = sl, game, sl_phases, sl_fan; sl_fan pairs with game and sl_phases."""
        abs_ = [("a", "sl"), ("b", "game"), ("c", "sl_phases"), ("d", "sl_fan")]
        lines = ["    | mod params:", "[SQST] showcase zones sent n=4 run=r1 by_ab=game:1,sl:1,sl_phases:1,sl_fan:1 smart_lanes=yes"]
        for k, (t, ab) in enumerate(abs_):
            lines.append(f"[SQST] showcase zone id=g1{t} pair=g1 ab={ab} kind=plain type=Crossroads x={k * 4000} y=0 r=108 match=yes")
        lines.append("[SQST] FLOW_START run=1 gt=0 gt_per_s=1000")
        for k, (t, ab) in enumerate(abs_):
            lines.append(f"[SQST] FLOW_ZONE run=1 zone={k + 1} kind=x twin=g1{t} pair=g1 ab={ab} x={k * 4000} y=0 r=108")
        for s in range(1, 7):  # at least 5 samples with cars per twin
            for k in range(4):
                lines.append(f"[SQST] FLOW run=1 s={s} zone={k + 1} gt={s * 30000} cars=2 standing=0 v_mean={5 + k}")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
        got = {(p.pair, p.a, p.b) for p in rep.pairs}
        self.assertEqual(got, {("g1", "sl", "game"), ("g1", "sl_phases", "game"), ("g1", "sl_phases", "sl"),
                               ("g1", "sl_fan", "game"), ("g1", "sl_fan", "sl_phases")})
        fan = next(p for p in rep.pairs if (p.a, p.b) == ("sl_fan", "game"))
        self.assertAlmostEqual(fan.d_speed(), 2 * 3.6)  # sl_fan 8 m/s, game 6 m/s

    def test_lights_showcase_sl_lock_twin_pairs_with_game_and_sl(self):
        """Lights showcase with an sl_lock twin (kerb turn never freed) instead of sl_fan: sl_lock vs game (the lane
        layout alone) and sl vs sl_lock (the free kerb turn alone); no sl_fan comparisons."""
        abs_ = [("a", "sl"), ("b", "game"), ("c", "sl_phases"), ("e", "sl_lock")]
        lines = ["    | mod params:", "[SQRL] MODE phases=game free_turn=always",
                 "[SQST] showcase zones sent n=4 run=r1 by_ab=game:1,sl:1,sl_phases:1,sl_lock:1 smart_lanes=yes"]
        for k, (t, ab) in enumerate(abs_):
            lines.append(f"[SQST] showcase zone id=g1{t} pair=g1 ab={ab} kind=plain type=Crossroads x={k * 4000} y=0 r=108 match=yes")
        lines.append("[SQST] FLOW_START run=1 gt=0 gt_per_s=1000")
        for k, (t, ab) in enumerate(abs_):
            lines.append(f"[SQST] FLOW_ZONE run=1 zone={k + 1} kind=x twin=g1{t} pair=g1 ab={ab} x={k * 4000} y=0 r=108")
        for s in range(1, 7):
            for k in range(4):
                lines.append(f"[SQST] FLOW run=1 s={s} zone={k + 1} gt={s * 30000} cars=2 standing=0 v_mean={5 + k}")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
        got = {(p.pair, p.a, p.b) for p in rep.pairs}
        self.assertEqual(got, {("g1", "sl", "game"), ("g1", "sl_phases", "game"), ("g1", "sl_phases", "sl"),
                               ("g1", "sl_lock", "game"), ("g1", "sl", "sl_lock")})
        free = next(p for p in rep.pairs if (p.a, p.b) == ("sl", "sl_lock"))
        self.assertAlmostEqual(free.d_speed(), -3 * 3.6)  # sl 5 m/s, sl_lock 8 m/s
        self.assertIn("sl vs sl_lock", fr.render(rep))

    def test_zone_match_line_marks_the_set_after_the_links(self):
        """`showcase zone_match` (an arm left unlinked) turns the zone's match off with its reason, also after
        FLOW lines joined it; it never starts a new Showcase run."""
        lines = ["    | mod params:", "[SQST] showcase zones sent n=2 run=r1 smart_lanes=yes",
                 "[SQST] showcase zone id=g1a pair=g1 ab=sl kind=plain type=X x=0 y=0 r=90 match=yes",
                 "[SQST] showcase zone id=g1b pair=g1 ab=game kind=plain type=X x=4000 y=0 r=90 match=yes",
                 "[SQST] FLOW_START run=1 gt=0 gt_per_s=1",
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=x twin=g1a pair=g1 ab=sl x=0 y=0 r=90",
                 "[SQST] FLOW run=1 s=1 zone=1 gt=0 cars=1 standing=0 v_mean=1",
                 "[SQST] showcase zone_match id=g1a pair=g1 match=no reason=link",
                 "[SQST] showcase zone_match id=g1b pair=g1 match=no reason=town,link",
                 "[SQST] FLOW_ZONE run=1 zone=2 kind=x twin=g1b pair=g1 ab=game x=4000 y=0 r=90",
                 "[SQST] FLOW run=1 s=2 zone=2 gt=1 cars=1 standing=0 v_mean=1"]
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
        self.assertEqual(len(rep.showcases), 1)
        a, b = rep.zones[("sc", 1, "g1a")], rep.zones[("sc", 1, "g1b")]
        self.assertEqual((a.match, a.reason), (False, "link"))
        self.assertEqual((b.match, b.reason), (False, "town,link"))

    def test_ignore_reason_counts_those_zones_as_matched(self):
        """--ignore-reason: a zone whose match=no reasons are all ignored counts as matched (noted), others stay."""
        lines = ["    | mod params:", "[SQST] showcase zones sent n=2 run=r1 smart_lanes=yes",
                 "[SQST] showcase zone id=g1a pair=g1 ab=sl kind=plain type=X x=0 y=0 r=90 match=no reason=entry",
                 "[SQST] showcase zone id=g1b pair=g1 ab=game kind=plain type=X x=4000 y=0 r=90 match=no reason=entry",
                 "[SQST] showcase zone id=g2a pair=g2 ab=sl kind=plain type=X x=0 y=4000 r=90 match=no reason=entry,link",
                 "[SQST] showcase zone id=g2b pair=g2 ab=game kind=plain type=X x=4000 y=4000 r=90 match=yes",
                 "[SQST] FLOW_START run=1 gt=0 gt_per_s=1",
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=x twin=g1a pair=g1 ab=sl x=0 y=0 r=90",
                 "[SQST] FLOW run=1 s=1 zone=1 gt=0 cars=1 standing=0 v_mean=1",
                 "[SQST] showcase zone_match id=g1a pair=g1 match=no reason=entry"]
        with tempfile.TemporaryDirectory() as d:
            path = write_log(d, lines)
            plain = fr.parse([path], warmup=0)
            ign = fr.parse([path], warmup=0, ignore=["entry"])
        self.assertTrue([x for x in plain.excluded if x[0] == "g1" and x[3] == "match=no (entry)"], plain.excluded)
        self.assertFalse([x for x in ign.excluded if x[0] == "g1" and x[3].startswith("match=no")], ign.excluded)
        self.assertIn("g2", [x[0] for x in ign.excluded], "entry,link: link not ignored")
        self.assertTrue(ign.zones[("sc", 1, "g1a")].match)
        self.assertTrue(any(n.startswith("--ignore-reason entry: 2 zones") for n in ign.notes), ign.notes)
        self.assertIn("--ignore-reason entry", fr.render(ign))

    def test_thru_and_queue_sides(self):
        """thru / thru_s per FLOW line: cars per game minute per zone, per pair (delta) and in the paired comparison
        (W/L/T + sign test, the `all` group across shapes); q_in / q_out in Approaches."""
        lines = ["    | mod params:", "[SQST] showcase zones sent n=4 run=r1 smart_lanes=yes"]
        zones = [("g1a", "g1", "sl", "2x2_X", 0), ("g1b", "g1", "game", "2x2_X", 4000),
                 ("g2a", "g2", "sl", "T_2x2", 8000), ("g2b", "g2", "game", "T_2x2", 12000)]
        for zid, pair, ab, typ, x in zones:
            lines.append(f"[SQST] showcase zone id={zid} pair={pair} ab={ab} kind=plain type={typ} x={x} y=0 r=90 match=yes")
        lines.append("[SQST] FLOW_START run=1 gt=0 gt_per_s=1")
        for k, (zid, pair, ab, typ, x) in enumerate(zones, 1):
            lines.append(f"[SQST] FLOW_ZONE run=1 zone={k} kind=x twin={zid} pair={pair} ab={ab} x={x} y=0 r=90 r_measure=290 "
                         "measure=corridor arms=N,S")
        for smp in range(1, 7):
            for k, (zid, pair, ab, typ, x) in enumerate(zones, 1):
                thru = (30 if ab == "sl" else 20) if smp > 1 else "-"
                ts = 30 if smp > 1 else "-"
                lines.append(f"[SQST] FLOW run=1 s={smp} zone={k} twin={zid} pair={pair} ab={ab} gt={smp * 30} cars=10 standing=2 "
                             f"queue=1 v_mean=5 cars_core=2 q_arm=N:2,S:1 q_in=N:2,S:0 q_out=N:0,S:1 thru={thru} thru_s={ts}")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0, min_samples=3)
            text = fr.render(rep)
        a, b = rep.zones[("sc", 1, "g1a")], rep.zones[("sc", 1, "g1b")]
        self.assertAlmostEqual(a.thru_per_min(), 60.0)
        self.assertAlmostEqual(b.thru_per_min(), 40.0)
        self.assertEqual(a.q_arm_means("q_in"), {"N": 2, "S": 0})
        self.assertIn("| N 2.0, S 1.0 | N 2.0, S 0.0 | N 0.0, S 1.0 | 60.0 |", text)
        self.assertIn("| 60.0 / 40.0 | +20.0 |", text)
        row = next(l for l in text.splitlines() if l.startswith("| all | sl vs game |"))
        self.assertFalse([l for l in text.splitlines() if l.startswith("| plain | sl vs game |")],
                         "no kind row that pools the same pairs as all")
        self.assertIn("| 2 |", row)
        self.assertTrue(row.rstrip().endswith("| +20.0 | 2/0/0 | 0.500 |"), row)

    @staticmethod
    def light_plans_log(retime: bool = True, zid_on_write: bool = False, refused: bool = False) -> list[str]:
        """Light plans A/B: two sets (2x2_X, 3x3_X) x twins game b / sl_phases c / sl_classic u, 12 samples at 30 game s
        (gt_per_s=1). Before sample 7 the axis twin g1c passes 20 cars a sample, after it 32; game 24, classic 22
        throughout. Re-time writes node 501 (g1c) between samples 6 and 7; a LIGHTS line names its zid."""
        lines = ["    | mod params:", "[SQST] showcase zones sent n=6 run=r1 by_ab=game:2,sl:0,sl_phases:2,sl_classic:2 smart_lanes=yes"]
        zones = []
        for k, typ in ((1, "2x2_X"), (2, "3x3_X")):
            for j, (ab, letter) in enumerate((("game", "b"), ("sl_phases", "c"), ("sl_classic", "u"))):
                zones.append((f"g{k}{letter}", f"g{k}", ab, typ, j * 3000, k * 3000))
        for zid, pair, ab, typ, x, y in zones:
            lines.append(f"[SQST] showcase zone id={zid} pair={pair} ab={ab} kind=plain type={typ} x={x} y={y} r=90 match=yes")
        lines.append("[SQST] FLOW_START run=1 gt=0 gt_per_s=1")
        for k, (zid, pair, ab, typ, x, y) in enumerate(zones, 1):
            lines.append(f"[SQST] FLOW_ZONE run=1 zone={k} kind=x twin={zid} pair={pair} ab={ab} x={x} y={y} r=90 r_measure=290 "
                         "measure=corridor arms=N,E,S,W")
        lines.append("[SQRL] APPLY node=777 kind=crossroads zid=g2c")
        for smp in range(1, 13):
            if retime and smp == 7:
                lines.append("[SQRL] RETIME op=start node=501 window_s=180")
                lines.append("[SQRL] LIGHTS src=tool node=501 to=retime action=retime" + ("" if zid_on_write else " zid=g1c"))
                lines.append("[SQRL] RETIME op=write node=501 sent=1 why=- durations=30/20" + (" zid=g1c" if zid_on_write else ""))
                lines.append(f"[SQRL] RETIME op=probe node=501 at=cb success={'false' if refused else 'true'}")
            for k, (zid, pair, ab, typ, x, y) in enumerate(zones, 1):
                base = {"game": 24, "sl_phases": 20, "sl_classic": 22}[ab]
                if zid == "g1c" and smp >= 7 and retime and not refused:
                    base = 32
                stand = {"game": 5, "sl_phases": 6, "sl_classic": 4}[ab]
                lines.append(f"[SQST] FLOW run=1 s={smp} zone={k} twin={zid} pair={pair} ab={ab} gt={smp * 30} cars=10 "
                             f"standing={stand} queue=2 v_mean={base / 4} q_arm=N:2,E:1,S:0,W:1 q_in=N:2,E:1,S:0,W:0 "
                             f"q_out=N:0,E:0,S:0,W:1 thru={base} thru_s=30")
        return lines

    def test_light_plans_section_and_verdicts(self):
        """game vs axis vs classic per shape, verdict per shape; sl_classic vs game and sl_phases vs sl_classic pairs;
        a set without an sl twin is not 'missing sl' (the light plans A/B builds none)."""
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, self.light_plans_log(retime=False))], warmup=0, min_samples=3)
            text = fr.render(rep)
        self.assertEqual(rep.excluded, [])
        got = {(p.pair, p.a, p.b) for p in rep.pairs}
        self.assertEqual(got, {(g, a, b) for g in ("g1", "g2") for a, b in
                               (("sl_phases", "game"), ("sl_classic", "game"), ("sl_phases", "sl_classic"))})
        self.assertIn("## Light plans: game vs axis vs classic", text)
        self.assertIn("| 2x2_X | - | game | 1 | 12 | 48.0 | 21.6 | 50 | 2.0 | N 2.0, E 1.0, S 0.0, W 0.0 |", text)
        self.assertIn("| 2x2_X | - | axis | 1 | 12 | 40.0 | 18.0 | 60 | 2.0 |", text)
        self.assertIn("| 3x3_X | - | classic | 1 | 12 | 44.0 | 19.8 | 40 | 2.0 |", text)
        self.assertIn("- **2x2_X**: game best: +9 % thru/min vs classic (standing +10 pp, 1/1 sets); "
                      "+20 % thru/min vs axis (standing -10 pp, 1/1 sets).", text)
        self.assertNotIn("## Re-time", text)
        self.assertIn("| all | sl_classic vs game | 2 |", text)

    def test_retime_split(self):
        """A Re-time write on g1c (zid from the LIGHTS line of that node) splits set g1: before (6 samples each) in the
        tables, after (from 60 game s after the write: samples 9-12) as set g1+rt with mode sl_phases+rt; the Re-time
        section's difference of differences against game; g2 untouched."""
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, self.light_plans_log())], warmup=0, min_samples=3)
            text = fr.render(rep)
        g1c, g1b, g2c = rep.zones[("sc", 1, "g1c")], rep.zones[("sc", 1, "g1b")], rep.zones[("sc", 1, "g2c")]
        self.assertEqual((g1c.n(), g1b.n(), g2c.n()), (6, 6, 12))
        aft = rep.zones[("sc", 1, "g1c+rt")]
        self.assertEqual((aft.ab, aft.pair, aft.n()), ("sl_phases+rt", "g1+rt", 4))
        self.assertAlmostEqual(aft.thru_per_min(), 64.0)
        self.assertEqual(rep.zones[("sc", 1, "g1b+rt")].ab, "game")
        got = {(p.pair, p.a, p.b) for p in rep.pairs if p.pair == "g1+rt"}
        self.assertEqual(got, {("g1+rt", "sl_phases+rt", "game"), ("g1+rt", "sl_phases+rt", "sl_classic")},
                         "the after window pairs only the written twin (its siblings count once, before the write)")
        self.assertIn("## Re-time: before / after", text)
        self.assertIn("| g1 | g1c (re-timed) | axis | 6 / 4 | 40.0 / 64.0 | 18.0 / 28.8 | 60 / 60 | 2.0 / 2.0 | "
                      "-3.6 / +7.2 | -8.0 / +16.0 |", text)
        self.assertIn("- **g1 g1c** (axis, 2x2_X): re-timed better by +24.0 thru/min relative to game (-8.0 before, "
                      "+16.0 after; 6 / 4 samples).", text)
        self.assertIn("g1: 6 sample(s) between the writes / in the 60 s settle dropped; node(s) 501, 1 write(s).", text)
        # the light plans section keeps the plans as built (g1 before the write only)
        self.assertIn("| 2x2_X | - | axis | 1 | 6 | 40.0 |", text)
        self.assertIn("| 2x2_X | - | game | 1 | 6 | 48.0 |", text)
        self.assertIn("| all | sl_classic vs game | 2 |", text)
        self.assertIn("| plain/2x2_X | sl_phases+rt vs game | 1 | +7.2 |", text)

    def test_retime_zid_on_write_line_and_refused(self):
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, self.light_plans_log(zid_on_write=True))], warmup=0, min_samples=3)
            self.assertIn(("sc", 1, "g1c+rt"), rep.zones)
            rep = fr.parse([write_log(d, self.light_plans_log(refused=True))], warmup=0, min_samples=3)
            self.assertNotIn(("sc", 1, "g1c+rt"), rep.zones)
            self.assertTrue(any("refused the write" in n for n in rep.notes), rep.notes)
            # a write whose node no line names with a zid: noted, not split
            lines = [ln.replace(" zid=g1c", "") for ln in self.light_plans_log()]
            rep = fr.parse([write_log(d, lines)], warmup=0, min_samples=3)
            text = fr.render(rep)
        self.assertEqual(rep.rt_sets, [])
        self.assertIn("Re-time at node 501: its twin is unknown", text)
        self.assertIn("No Re-time write could be joined to a twin", text)

    @staticmethod
    def auto_plans_log(writes: bool = True) -> list[str]:
        """Light plans A/B with the auto twin: four sets g1 (2x2_X balanced), g2 (2x2_X unbalanced), g3 (3x3_X unbalanced),
        g4 (3x3_X balanced), twins game b / sl_phases c / sl_auto v, 40 samples at 30 game s (gt_per_s=1). Thru per
        sample: balanced game 24 / axis 30 / auto 30, unbalanced game 20 / axis 22 / auto 22; an auto twin that wrote
        passes 36 (balanced) / 30 (unbalanced) from sample 11 on. Auto writes (node 70<k>) after sample 10 (zid on the
        write for g1, on a LIGHTS line for g2 and g3) and again after sample 20; g4's auto twin never writes. Towns with
        pop=, an unbalanced set's small / tiny towns."""
        lines = ["    | mod params:", "[SQST] showcase zones sent n=12 run=r2 by_ab=game:4,sl:0,sl_phases:4,sl_auto:4 smart_lanes=yes"]
        sets = ((1, "2x2_X", "balanced"), (2, "2x2_X", "unbalanced"), (3, "3x3_X", "unbalanced"), (4, "3x3_X", "balanced"))
        zones = []
        for k, typ, dem in sets:
            for j, (ab, letter) in enumerate((("game", "b"), ("sl_phases", "c"), ("sl_auto", "v"))):
                zones.append((f"g{k}{letter}", f"g{k}", ab, typ, j * 3000, k * 3000, dem))
        for zid, pair, ab, typ, x, y, dem in zones:
            lines.append(f"[SQST] showcase zone id={zid} pair={pair} ab={ab} kind=plain type={typ} x={x} y={y} r=90 "
                         f"r_from=measured towns=4 match=yes approach=600 demand={dem}")
        lines.append("[SQST] FLOW_START run=1 gt=0 gt_per_s=1")
        for n, (zid, pair, ab, typ, x, y, dem) in enumerate(zones, 1):
            lines.append(f"[SQST] FLOW_ZONE run=1 zone={n} kind=x twin={zid} pair={pair} ab={ab} x={x} y={y} r=90 r_measure=290 "
                         f"measure=corridor arms=N,E,S,W demand={dem}")
        lines.append("[SQRL] LIGHTS src=auto node=702 to=retime action=auto zid=g2v")
        lines.append("[SQRL] AUTORETIME op=plan node=703 pos=6000,9000 result=fits zid=g3v")
        for smp in range(1, 41):
            if writes and smp in (11, 21):
                for k in (1, 2, 3):
                    lines.append(f"[SQRL] AUTORETIME op=write node=70{k} pos=6000,{k * 3000} sent=1 why=- durations=40/20 "
                                 f"cycle=60>80" + (" zid=g1v" if k == 1 else ""))
                    lines.append(f"[SQRL] AUTORETIME op=write node=70{k} pos=6000,{k * 3000} at=cb success=true")
            for n, (zid, pair, ab, typ, x, y, dem) in enumerate(zones, 1):
                bal = dem == "balanced"
                base = {"game": 24 if bal else 20, "sl_phases": 30 if bal else 22, "sl_auto": 30 if bal else 22}[ab]
                if writes and ab == "sl_auto" and pair != "g4" and smp >= 11:
                    base = 36 if bal else 30
                lines.append(f"[SQST] FLOW run=1 s={smp} zone={n} twin={zid} pair={pair} ab={ab} gt={smp * 30} cars=10 "
                             f"standing=4 queue=2 v_mean={base / 4} q_arm=N:2,E:1,S:0,W:1 q_in=N:2,E:1,S:0,W:0 "
                             f"q_out=N:0,E:0,S:0,W:1 thru={base} thru_s=30")
            if smp in (1, 40):
                for name, pop in (("Auto timing 2 N small", 148 + smp // 40 * 4), ("Auto timing 2 S tiny", 40),
                                  ("Auto timing 2 E busy", 600), ("Game default 1 N", 598)):
                    lines.append(f"[SQST] FLOW_TOWNS run=1 s={smp} gt={smp * 30} scope=town town=1 name={name.replace(' ', '_')} "
                                 f"speed=0.9 levels=1 pop={pop}")
        return lines

    def test_auto_twin_settled_split_and_demand(self):
        """sl_auto pairs (vs axis, vs game); a set whose auto twin wrote is split at its first write: before (10 samples)
        in the tables, settled from the first write + --auto-settle (300 s: samples 21-40) as set <pair>+as with mode
        sl_auto+as; the light plans section per shape and demand compares every plan in that settled window; the auto
        section shows settled-from, writes, before / settled; towns per class."""
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, self.auto_plans_log())], warmup=0, min_samples=3, auto_settle=300)
            text = fr.render(rep)
        self.assertEqual(rep.excluded, [])
        self.assertEqual(rep.zones[("sc", 1, "g1v")].demand, "balanced")
        self.assertEqual(rep.zones[("sc", 1, "g2v")].demand, "unbalanced")
        g1v, g1b, g4v = rep.zones[("sc", 1, "g1v")], rep.zones[("sc", 1, "g1b")], rep.zones[("sc", 1, "g4v")]
        self.assertEqual((g1v.n(), g1b.n(), g4v.n()), (10, 10, 40))
        aft = rep.zones[("sc", 1, "g1v+as")]
        self.assertEqual((aft.ab, aft.pair, aft.n()), ("sl_auto+as", "g1+as", 20))
        self.assertAlmostEqual(aft.thru_per_min(), 72.0)
        self.assertEqual(rep.zones[("sc", 1, "g1c+as")].ab, "sl_phases")
        self.assertEqual({(p.pair, p.a, p.b) for p in rep.pairs if p.pair == "g1+as"},
                         {("g1+as", "sl_auto+as", "sl_phases"), ("g1+as", "sl_auto+as", "game")})
        self.assertIn(("g4", "sl_auto", "sl_phases"), {(p.pair, p.a, p.b) for p in rep.pairs})
        self.assertIn("## Light plans: game vs axis vs auto", text)
        # settled window for g1-g3 (every twin), g4 whole
        self.assertIn("| 2x2_X | balanced | auto | 1 | 20 | 72.0 |", text)
        self.assertIn("| 2x2_X | balanced | game | 1 | 20 | 48.0 |", text)
        self.assertIn("| 2x2_X | unbalanced | auto | 1 | 20 | 60.0 |", text)
        self.assertIn("| 3x3_X | balanced | auto | 1 | 40 | 60.0 |", text)
        self.assertIn("| 3x3_X | unbalanced | axis | 1 | 20 | 44.0 |", text)
        self.assertIn("- **2x2_X balanced**: auto best: +20 % thru/min vs axis (standing +0 pp, 1/1 sets); "
                      "+50 % thru/min vs game (standing +0 pp, 1/1 sets).", text)
        self.assertIn("- **3x3_X balanced**: no clear best (thru/min tied).", text)
        self.assertIn("3 sets), any other set whole", text)
        self.assertIn("## Auto timing: as built / settled", text)
        self.assertIn("| g1 | balanced | g1v | 10.0 | 2 (0) | 10 / 20 | 60.0 / 72.0 | 27.0 / 32.4 | 40 / 40 | +12.0 / +24.0 | "
                      "+0.0 / +12.0 |", text)
        self.assertIn("- **g2 g2v** (unbalanced, 2x2_X): auto vs axis gained +16.0 thru/min from as built to settled (+0.0 -> "
                      "+16.0; 10 / 20 samples).", text)
        self.assertIn("g1: 30 sample(s) between the first write and the settled-from time dropped; node(s) 701.", text)
        self.assertIn("| all | sl_auto+as vs sl_phases | 3 |", text)
        self.assertNotIn("## Whole-map auto re-time", text)
        # towns per class
        self.assertIn("| small | 1 | 148 | 152 | 152 / 152 |", text)
        self.assertIn("| tiny | 1 | 40 | 40 | 40 / 40 |", text)
        self.assertIn("| other | 1 | 598 | 598 | 598 / 598 |", text)

    def test_auto_twin_without_writes_and_short_settle(self):
        """No auto write: no split, no auto section, sl_auto vs sl_phases over the whole run; a write without any zid
        is noted, not used."""
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, self.auto_plans_log(writes=False))], warmup=0, min_samples=3)
            text = fr.render(rep)
            self.assertEqual(rep.as_sets, [])
            self.assertNotIn("## Auto timing", text)
            self.assertIn("| 2x2_X | unbalanced | auto | 1 | 40 | 44.0 |", text)
            lines = [ln.replace(" zid=g1v", "").replace(" zid=g2v", "").replace(" zid=g3v", "") for ln in self.auto_plans_log()]
            rep = fr.parse([write_log(d, lines)], warmup=0, min_samples=3)
        self.assertEqual(rep.as_sets, [])
        self.assertTrue(any("Auto timing: 6 write(s)" in n for n in rep.notes), rep.notes)

    def test_whole_map_auto_retime(self):
        """Stress Test Auto re-time > All lit junctions: AUTO_ALL, enroll lines (twin g1a by zid, a raw zone by pos), then
        enroll_all phase=done after sample 10: the enrolled zones before (samples 1-10) and from --auto-settle (120 s)
        after it (samples 15-20); the map-wide FLOW_ALL split; a zone not enrolled is left out."""
        lines = ["    | mod params:",
                 "[SQST] showcase zone id=g1a pair=g1 ab=sl kind=plain type=2x2_X x=0 y=0 r=90 match=yes",
                 "[SQST] showcase zone id=g1b pair=g1 ab=game kind=plain type=2x2_X x=3000 y=0 r=90 match=yes",
                 "[SQST] FLOW_START run=1 gt=0 gt_per_s=1",
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=x twin=g1a pair=g1 ab=sl x=0 y=0 r=90",
                 "[SQST] FLOW_ZONE run=1 zone=2 kind=x twin=g1b pair=g1 ab=game x=3000 y=0 r=90",
                 "[SQST] FLOW_ZONE run=1 zone=3 kind=x src=lights label=Elm_St x=9000 y=500 r=50"]
        for smp in range(1, 21):
            if smp == 11:
                lines += ["[SQST] AUTO_ALL op=all run=s0-5-1 by=button smart_lanes=yes",
                          "[SQRL] AUTORETIME op=enroll_all phase=request run=s0-5-1 src=stress",
                          "[SQRL] AUTORETIME op=enroll node=11 pos=2,3 src=all total=1 zid=g1a",
                          "[SQRL] AUTORETIME op=enroll node=12 pos=9010,520 src=all total=2",
                          "[SQRL] AUTORETIME op=enroll_all phase=done run=s0-5-1 src=component nodes=11,12 lit=2 already=0 "
                          "sent=2 capped=0"]
            after = smp >= 11
            for zone, twin in ((1, "g1a"), (2, "g1b"), (3, None)):
                th = 40 if after and zone != 2 else 30
                tw = f" twin={twin} pair=g1 ab={'sl' if zone == 1 else 'game'}" if twin else ""
                lines.append(f"[SQST] FLOW run=1 s={smp} zone={zone}{tw} gt={smp * 30} cars=10 standing=2 queue=1 v_mean=5 "
                             f"thru={th} thru_s=30")
            lines.append(f"[SQST] FLOW_ALL run=1 s={smp} gt={smp * 30} drivers=100 sampled=100 standing={30 if after else 50} "
                         f"v_mean={6 if after else 4}")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0, min_samples=3, auto_settle=120)
            text = fr.render(rep)
        self.assertIsNotNone(rep.wm)
        got = {st.name: (len(b), len(a)) for st, b, a in rep.wm["zones"]}
        self.assertEqual(got, {"g1a": (10, 6), "Elm_St": (10, 6)})
        self.assertIn("## Whole-map auto re-time: before / after", text)
        self.assertIn("Run s0-5-1 (`AUTORETIME op=enroll_all phase=done`: lit=2 sent=2 capped=0) at game min 5.0 of load 1; "
                      "2 junction(s) named by", text)
        self.assertIn("| plain | 2x2_X | sl | 1 | 10 / 6 | 60.0 / 80.0 |", text)
        self.assertIn("Map-wide (FLOW_ALL): 10 / 6 samples, km/h 14.4 / 21.6, standing % 50 / 30 (before / after).", text)

    def test_exitfan_twin(self):
        """sl_exitfan (twin e): ids g<k>e parse, compared vs sl (the fan alone) and vs game, pooled in `all`."""
        lines = ["    | mod params:", "[SQST] showcase zones sent n=6 run=r1 smart_lanes=yes"]
        zones = []
        for k, typ in ((1, "2x2_X"), (2, "T_2x2")):
            for ab, t, dx in (("sl", "a", 0), ("game", "b", 3000), ("sl_exitfan", "e", 6000)):
                zones.append((f"g{k}{t}", f"g{k}", ab, typ, dx + 10000 * k))
        for zid, pair, ab, typ, x in zones:
            lines.append(f"[SQST] showcase zone id={zid} pair={pair} ab={ab} kind=plain type={typ} x={x} y=0 r=90 match=yes")
        lines.append("[SQST] FLOW_START run=1 gt=0 gt_per_s=1")
        for k, (zid, pair, ab, typ, x) in enumerate(zones, 1):
            lines.append(f"[SQST] FLOW_ZONE run=1 zone={k} kind=x twin={zid} pair={pair} ab={ab} x={x} y=0 r=90")
        speed = {"sl": 6, "game": 5, "sl_exitfan": 7}
        for smp in range(1, 7):
            for k, (zid, pair, ab, typ, x) in enumerate(zones, 1):
                lines.append(f"[SQST] FLOW run=1 s={smp} zone={k} twin={zid} pair={pair} ab={ab} gt={smp * 30} cars=10 standing=2 "
                             f"queue=1 v_mean={speed[ab]}")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0, min_samples=3)
            text = fr.render(rep)
        cmps = {(p.pair, p.a, p.b) for p in rep.pairs}
        for pair in ("g1", "g2"):
            self.assertIn((pair, "sl_exitfan", "sl"), cmps)
            self.assertIn((pair, "sl_exitfan", "game"), cmps)
            self.assertIn((pair, "sl", "game"), cmps)
        row = next(l for l in text.splitlines() if l.startswith("| all | sl_exitfan vs sl |"))
        self.assertIn("| 2 | +3.6 | 2/0/0 |", row)
        self.assertIn("| g1e |", text)

    def test_position_join_closest_takes_the_twin(self):
        lines = ["    | mod params:", "[SQST] showcase zones sent n=1 run=r1 smart_lanes=yes",
                 "[SQST] showcase zone id=g1a pair=g1 ab=sl kind=roundabout type=X x=0 y=0 r=150 match=yes",
                 "[SQST] FLOW_START run=1 gt=0",
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=rb x=100 y=0 r=150",
                 "[SQST] FLOW_ZONE run=1 zone=2 kind=rb x=5 y=0 r=150",
                 "[SQST] FLOW run=1 s=1 zone=1 gt=0 cars=1 standing=0 v_mean=1",
                 "[SQST] FLOW run=1 s=1 zone=2 gt=0 cars=1 standing=0 v_mean=2",
                 "[SQST] showcase zones cleared by=remove_roads run=r1 smart_lanes=yes",
                 "[SQST] FLOW_START run=2 gt=1000",
                 "[SQST] FLOW_ZONE run=2 zone=1 kind=rb x=5 y=0 r=150",
                 "[SQST] FLOW run=2 s=1 zone=1 gt=1000 cars=1 standing=0 v_mean=3"]
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
        self.assertEqual([s.v_mean for s in rep.zones[("sc", 1, "g1a")].samples], [2],
                         "one FLOW zone per twin; after a clear nothing joins the old twins")

    def test_gt_reset_without_load_marker(self):
        lines = [
            "[SQST] FLOW_START run=1 gt=5000000",
            "[SQST] FLOW run=1 s=1 zone=1 gt=5000000 cars=1 standing=0 v_mean=5",
            "[SQST] FLOW_START run=2 gt=100",
            "[SQST] FLOW run=2 s=1 zone=1 gt=100 cars=1 standing=0 v_mean=5",
        ]
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
        self.assertEqual(len(rep.loads), 2)
        self.assertTrue(rep.loads[1].gt_reset)

    def test_empty(self):
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, ["nothing here", "[SQRL] AUDIT node=1"])])
        self.assertEqual(rep.loads, [])


class RingUseTest(unittest.TestCase):
    """Bench sheet 5 (ring lane use): zone lines with test= and mix=, RINGMIX / RINGLANE cumulative per run, the recorded
    window = the last line minus the first line after the warm-up cut."""

    MODES = (("game", "b", 24), ("sl_rturbo", "h", 20), ("sl_rmid2", "w", 30), ("sl_rmatch", "i", 22))

    @classmethod
    def ring_log(cls, adjacent_wrong: bool = False) -> list[str]:
        """Two sets of test lu2: s5g1 straight, s5g2 adjacent (its game twin's turning mix mostly 2nd exits when
        adjacent_wrong); 18 samples at 10 game s (gt_per_s=1); RINGMIX / RINGLANE at samples 6, 12 and the stop (18)."""
        lines = ["    | mod params:", "[SQST] showcase zones sent n=8 run=r5 by_ab=game:2,sl:0,sl_phases:0,sl_rturbo:2,sl_rmatch:2,"
                 "sl_rmid2:2 smart_lanes=yes"]
        zones = []
        for k, mix in ((1, "straight"), (2, "adjacent")):
            for j, (ab, letter, _) in enumerate(cls.MODES):
                zones.append((f"s5g{k}{letter}", f"s5g{k}", ab, mix, j * 3000, k * 3000))
        for zid, pair, ab, mix, x, y in zones:
            lines.append(f"[SQST] showcase zone id={zid} pair={pair} ab={ab} kind=roundabout type=RB4_2L x={x} y={y} r=60 r_from=measured "
                         f"towns=4 match=yes test=lu2 variant=RB4_2L approach=518 mix={mix}")
        lines.append("[SQST] FLOW_START run=1 gt=0 gt_per_s=1")
        for z, (zid, pair, ab, mix, x, y) in enumerate(zones, 1):
            lines.append(f"[SQST] FLOW_ZONE run=1 zone={z} kind=rb twin={zid} pair={pair} ab={ab} x={x} y={y} r=60 r_measure=260 "
                         f"measure=corridor arms=N,E,S,W approach=518 test=lu2 mix={mix}")
        # cumulative counts at samples 6 / 12 / 18 (game twin of set 1; the others scaled)
        mix_at = {6: (40, 8, 20, 10, 2, 0), 12: (100, 20, 50, 25, 5, 0), 18: (250, 50, 125, 60, 10, 5)}
        lanes_at = {6: "32.0:4,28.0:40", 12: "32.0:10,28.0:90", 18: "32.0:30,31.5:5,28.5:20,28.0:265"}
        for smp in range(1, 19):
            for z, (zid, pair, ab, mix, x, y) in enumerate(zones, 1):
                base = dict((m, t) for m, _, t in cls.MODES)[ab]
                lines.append(f"[SQST] FLOW run=1 s={smp} zone={z} twin={zid} pair={pair} ab={ab} gt={smp * 10} cars=10 "
                             f"standing=3 queue=1 v_mean={base / 4} q_arm=N:1,E:1,S:0,W:0 q_in=N:1,E:0,S:0,W:0 "
                             f"q_out=N:0,E:1,S:0,W:0 thru={base} thru_s=10")
            if smp in mix_at:
                for z, (zid, pair, ab, mix, x, y) in enumerate(zones, 1):
                    n, e1, e2, e3, u, none = mix_at[smp]
                    if mix == "adjacent" and not adjacent_wrong:
                        e1, e2 = e2, e1   # mostly 1st (and 3rd) exits
                    fin = 1 if smp == 18 else 0
                    lines.append(f"[SQST] RINGMIX run=1 s={smp} zone={z} twin={zid} pair={pair} ab={ab} gt={smp * 10} arms=4 dir=ccw "
                                 f"n={n} exit1={e1} exit2={e2} exit3={e3} uturn={u} none={none} reads=999 capped=0 final={fin} mix={mix}")
                    lines.append(f"[SQST] RINGLANE run=1 s={smp} zone={z} twin={zid} pair={pair} ab={ab} gt={smp * 10} cars=0 "
                                 f"bin_m=0.5 radii={lanes_at[smp]} final={fin}")
        lines.append("[SQST] FLOW_SUMMARY run=1 samples=18 final=1")
        return lines

    def test_windows_lanes_and_section(self):
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, self.ring_log())], warmup=60, min_samples=3)
            text = fr.render(rep)
        g = rep.zones[("sc", 1, "s5g1b")]
        self.assertEqual(g.mix, "straight")
        # cut = gt 10 + 60: the window from sample 12 (the first line after the cut) to the stop
        self.assertEqual(dict(g.ringmix), {"n": 150, "exit1": 30, "exit2": 75, "exit3": 35, "uturn": 5, "none": 5})
        self.assertEqual(dict(g.ringlanes), {32.0: 20, 31.5: 5, 28.5: 20, 28.0: 175})
        lanes = fr.ring_lanes(g.ringlanes)
        self.assertEqual([c for _, c in lanes], [25, 195])
        self.assertAlmostEqual(lanes[0][0], 31.9)
        self.assertEqual(fr.lane_text(g.ringlanes), "o1 11 % (31.9 m), o2 89 % (28.1 m)")
        # the new twins pair with game and with sl_rturbo
        got = {(p.pair, p.a, p.b) for p in rep.pairs if p.pair == "s5g1"}
        self.assertEqual(got, {("s5g1", "sl_rturbo", "game"), ("s5g1", "sl_rmid2", "game"), ("s5g1", "sl_rmatch", "game"),
                               ("s5g1", "sl_rmid2", "sl_rturbo"), ("s5g1", "sl_rmatch", "sl_rturbo")})
        self.assertEqual(rep.excluded, [])
        self.assertIn("## Ring lane use", text)
        self.assertIn("| lu2 | straight | game | 1 | 12 | 144.0 | 21.6 | 30 | 1.0 | N 1.0, E 0.0, S 0.0, W 0.0 | "
                      "o1 11 % (31.9 m), o2 89 % (28.1 m) | 1st 21 %, 2nd 52 %, 3rd 24 %, U 3 % (n 150, none 3 %) |", text)
        self.assertIn("| lu2 | straight | sl_rmid2 | 1 | 12 | 180.0 | 27.0 |", text)
        self.assertLess(text.index("| lu2 | straight |"), text.index("| lu2 | adjacent |"), "mixes in set order")
        self.assertIn("| lu2 | adjacent | s5g2w | sl_rmid2 | 150 | 75 | 30 | 35 | 5 | 5 |", text)
        # every mode, best first, against game and against sl_rturbo
        self.assertIn("- **lu2 straight**: sl_rmid2 best by thru/min (180.0). sl_rmid2: +25 % thru/min, +5.4 km/h, standing +0 pp "
                      "vs game; +50 % thru/min, +9.0 km/h, standing +0 pp vs sl_rturbo. sl_rmatch: -8 % thru/min, -1.8 km/h, "
                      "standing +0 pp vs game; +10 % thru/min, +1.8 km/h, standing +0 pp vs sl_rturbo. sl_rturbo: -17 % thru/min, "
                      "-3.6 km/h, standing +0 pp vs game.", text)
        self.assertIn("- **lu2 adjacent**: sl_rmid2 best", text)
        self.assertNotIn("label not borne out", text)

    def test_mix_label_check_and_no_section_without_mix(self):
        with tempfile.TemporaryDirectory() as d:
            text = fr.render(fr.parse([write_log(d, self.ring_log(adjacent_wrong=True))], warmup=60, min_samples=3))
            self.assertIn("(label not borne out: 1st + 3rd exits not above the 2nd)", text)
            # without mix= (any other run): no section
            lines = [ln.replace(" mix=straight", "").replace(" mix=adjacent", "") for ln in self.ring_log()]
            text = fr.render(fr.parse([write_log(d, lines)], warmup=60, min_samples=3))
        self.assertNotIn("## Ring lane use", text)

    def test_run_restarted_after_the_cut_counts_whole(self):
        """A second sampler run (the bench restarts the log) after the cut: its lines count from its start."""
        lines = self.ring_log()
        extra = ["[SQST] FLOW_START run=2 gt=200 gt_per_s=1"]
        extra.append("[SQST] FLOW_ZONE run=2 zone=1 kind=rb twin=s5g1b pair=s5g1 ab=game x=0 y=3000 r=60 test=lu2 mix=straight")
        extra.append("[SQST] FLOW run=2 s=1 zone=1 twin=s5g1b pair=s5g1 ab=game gt=210 cars=10 standing=3 queue=1 v_mean=6 thru=24 thru_s=10")
        extra.append("[SQST] RINGMIX run=2 s=1 zone=1 twin=s5g1b pair=s5g1 ab=game gt=210 arms=4 dir=ccw n=10 exit1=10 exit2=0 "
                     "exit3=0 uturn=0 none=0 reads=1 capped=0 final=1 mix=straight")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines + extra)], warmup=60, min_samples=3)
        self.assertEqual(rep.zones[("sc", 1, "s5g1b")].ringmix["exit1"], 40)
        self.assertEqual(rep.zones[("sc", 1, "s5g1b")].ringmix["n"], 160)


def city_log(slow_auto: bool = False, no_perf: bool = False, old_clock: bool = False, run: str = "city-9", swap: str | None = None,
             control_v: float = 4.8, control_b: float = 5.0, header: bool = True, gt0: int = 0) -> list[str]:
    """The bench's city run (BENCH.md "City lights at scale"): two cities (cityg1v auto, cityg1b control), 40 samples at
    30 game s, the enroll after sample 10 (3 junctions of the auto city), 2 writes and 2 first fits after it, Smart Lanes'
    SQPERF ctx=bg windows (one window over 5 ms right after a src=scan snapshot whose person-list fetch took 8.2 ms; `slow_auto`:
    also one over 5 ms without a snapshot), FLOW_ALL. Speeds: auto city 5 then 6 m/s, control `control_b` then `control_v`.
    Smart Lanes with the wall clock (`op=config clock=wall`, fetch_ms); `old_clock`: an older one (os.clock max_frame_ms, no
    fetch_ms). `swap`: a v2 run (CITY_ENROLL layout= busy= role_swap=); `header`: the load's start (off: a second run in the
    same load, its game time from `gt0`)."""
    lines = ["    | mod params:",
             "[SQST] BENCH_START sheet=city spec=bench_city@1 seed=9 map=16000x16000 tests=0 groups=0 towns=2 year=1950 city=yes",
             "[SQRL] AUTORETIME op=config every_factor=1 params=read" + ("" if old_clock else " clock=wall")] if header else []
    lines += [
             "[SQST] CITY id=cityg1v pair=cityg1 role=auto town=501 name=City_auto_1 x=-4000 y=-2000 half=400 crossings=81 found=81 "
             "lit_before=41 forced=40 refused=0",
             "[SQST] CITY id=cityg1b pair=cityg1 role=control town=502 name=City_control_1 x=-4000 y=2000 half=400 crossings=81 "
             "found=81 lit_before=40 forced=41 refused=0",
             "[SQST] showcase zone id=cityg1v pair=cityg1 ab=city_auto kind=other type=City_auto_1 x=-4000 y=-2000 r=400 r_from=est towns=1 match=yes",
             "[SQST] showcase zone id=cityg1b pair=cityg1 ab=city_control kind=other type=City_control_1 x=-4000 y=2000 r=400 r_from=est towns=1 match=yes",
             f"[SQST] showcase zones local n=2 run={run} (traffic log only, not sent to Smart Lanes)",
             "[SQST] BENCH_PHASE sheet=city phase=warmup gt=0 ms=1 speed=4"]
    if header:
        lines += ["[SQST] FLOW_START run=1 gt=0 gt_per_s=1",
                  "[SQST] FLOW_ZONE run=1 zone=1 kind=other twin=cityg1v pair=cityg1 ab=city_auto x=-4000 y=-2000 r=400",
                  "[SQST] FLOW_ZONE run=1 zone=2 kind=other twin=cityg1b pair=cityg1 ab=city_control x=-4000 y=2000 r=400"]
    v2 = "" if swap is None else f" layout=hourglass busy=1 role_swap={swap}"
    perf = "" if no_perf else "[SQPERF] mod=square_smart_lanes ctx=bg vm=ab12 win_ms=30000.0 timer=clock mem_kb=900 | auto n=1800 ms={ms} max={mx}"
    for smp in range(1, 41):
        if smp == 11:
            lines += [f"[SQST] CITY_ENROLL run={run} op=add cities=1 nodes=3 events=1 baseline_s=300 by=bench smart_lanes=yes{v2}",
                      "[SQRL] AUTORETIME op=enroll node=11 pos=-3920.0,-1920.0 src=stress total=1",
                      "[SQRL] AUTORETIME op=enroll node=12 pos=-3840.0,-1920.0 src=stress total=2",
                      "[SQRL] AUTORETIME op=enroll node=13 pos=-3760.0,-1920.0 src=stress total=3"]
        if smp == 14:
            lines.append("[SQRL] AUTORETIME op=snapshot n=3 src=scan cand=0 read=9000 drivers=800 near=40 counted=12 calls=9100 "
                         "frames=20 busy_ms=21.0 max_frame_ms=8.20 " + ("" if old_clock else "fetch_ms=8.20 finish_ms=0.40 ")
                         + "span_s=4 gone=0 capped=0 enrolled=3 err=-")
        if smp == 16:
            lines += ["[SQRL] AUTORETIME op=plan node=11 pos=-3920.0,-1920.0 result=write snaps=8",
                      "[SQRL] AUTORETIME op=write node=11 pos=-3920.0,-1920.0 sent=1 why=- durations=30/3/30/3"]
        if smp in (20, 30):
            lines += [f"[SQRL] AUTORETIME op=plan node={11 if smp == 30 else 12} pos=-3840.0,-1920.0 result=fits snaps=9",
                      "[SQRL] AUTORETIME op=plan node=13 pos=-3760.0,-1920.0 result=few_snapshots snaps=3"]
        if smp == 26:
            lines.append("[SQRL] AUTORETIME op=write node=11 pos=-3920.0,-1920.0 sent=1 why=- durations=35/3/30/3")
        if perf and smp % 5 == 0:
            if smp <= 10:
                lines.append(perf.format(ms="9.0", mx="0.2"))
            elif smp == 15:
                lines.append(perf.format(ms="540.0", mx="8.4"))
            elif smp == 35 and slow_auto:
                lines.append(perf.format(ms="540.0", mx="6.1"))
            else:
                lines.append(perf.format(ms="360.0", mx="0.9"))
        after = smp > 10
        for zone, twin, ab in ((1, "cityg1v", "city_auto"), (2, "cityg1b", "city_control")):
            v = (6 if ab == "city_auto" else control_v) if after else (5 if ab == "city_auto" else control_b)
            lines.append(f"[SQST] FLOW run=1 s={smp} zone={zone} twin={twin} pair=cityg1 ab={ab} gt={gt0 + smp * 30} cars=100 "
                         f"standing={20 if after and ab == 'city_auto' else 30} queue=10 v_mean={v} thru=50 thru_s=30")
        lines.append(f"[SQST] FLOW_ALL run=1 s={smp} gt={gt0 + smp * 30} drivers=200 sampled=200 standing={50 if after else 60} v_mean=5.4")
    return lines


class CityLightsTest(unittest.TestCase):
    """The bench's city run: section "Auto lights at scale" (Smart Lanes' cost, snapshot spikes, writes, fits, cities before
    / after, the control, the pass criteria); the city zones never pair with a game twin."""

    def test_section(self):
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, city_log())], warmup=0, min_samples=3, auto_settle=300)
            text = fr.render(rep)
        self.assertEqual(rep.excluded, [], "no 'missing twin: game' for the city pairs")
        self.assertNotIn("could be joined", text)
        self.assertIn("## Auto lights at scale", text)
        self.assertIn("City run city-9 (`[SQST] CITY_ENROLL op=add`: 1 auto cities, 3 junctions asked for in 1 event(s)) at game min "
                      "5.0 of load 1; 14.5 game min recorded after it.", text)
        self.assertIn("before 2 window(s), mean 0.005 ms/frame, max 0.2 ms; after 6 window(s), mean 0.217 ms/frame, max 8.4 ms, "
                      "1 window(s) with a frame over 5 ms; 0 slow line(s) after the enroll; recorded at 4x.", text)
        self.assertIn("Snapshots (`AUTORETIME op=snapshot`) after the enroll: 1 (src=scan 1), watched up to 3, busy 21.0 ms each on "
                      "average, longest frame 8.20 ms; person-list fetch (fetch_ms) mean 8.20 ms, max 8.20 ms over 1 snapshot(s); "
                      "person-list spikes (src=scan, fetch_ms over 5 ms, once per snapshot): 1 (max 8.2 ms).", text)
        self.assertIn("Options: layout plain, baseline 5 game min, roles as usual", text)
        self.assertIn("| cityg1 | cityg1v / cityg1b | 18.0 / 18.0 | +0 % | 10.0 / 10.0 | +24.0 |", text)
        self.assertNotIn("pairs too unequal", text)
        self.assertIn("Writes: 2 (refused 0) after the enroll, 0.14 per game minute; 1 of 3 enrolled junctions written at least "
                      "once (3 `AUTORETIME op=enroll` lines).", text)
        self.assertIn("Checks (`AUTORETIME op=plan`): 5 after the enroll (few_snapshots 2, fits 2, write 1); 2 of 3 junctions reported "
                      "fits at least once; first fits reached by 50 %: game min 9.5; 80 %: not reached (game min after the enroll).",
                      text)
        self.assertIn("| cityg1v | auto | 81 / 41 / 40 | 3 | 1 | 10 / 20 | 18.0 / 21.6 | +20 % | 30 / 20 | 10.0 / 10.0 |", text)
        self.assertIn("| cityg1b | control | 81 / 40 / 41 | 0 | 0 | 10 / 20 | 18.0 / 17.3 | -4 % | 30 / 30 | 10.0 / 10.0 |", text)
        self.assertIn("Auto city change minus its control's (km/h %, the drift cancels): cityg1v +24.0 pp vs cityg1b.", text)
        self.assertIn("- No Smart Lanes frame over 5 ms: FAIL (worst 8.4 ms; 1 window(s) over: 1 with a person-list snapshot spike, "
                      "0 other; 0 slow line(s)).", text)
        self.assertIn("  - Without the person-list spikes (once per snapshot, every 120 game s): PASS (worst other window 0.9 ms).", text)
        self.assertIn("- Mean cost under 1.5 ms/frame at 4x: PASS (0.217 ms/frame).", text)
        self.assertIn("- No city worse than its baseline by more than 10 % (km/h): PASS (worst cityg1v +20 %).", text)

    def test_other_spikes_and_no_perf(self):
        with tempfile.TemporaryDirectory() as d:
            text = fr.render(fr.parse([write_log(d, city_log(slow_auto=True))], warmup=0, min_samples=3, auto_settle=300))
            self.assertIn("1 with a person-list snapshot spike, 1 other", text)
            self.assertIn("  - Without the person-list spikes (once per snapshot, every 120 game s): FAIL (worst other window 6.1 ms).", text)
            text = fr.render(fr.parse([write_log(d, city_log(no_perf=True))], warmup=0, min_samples=3, auto_settle=300))
        self.assertIn("- No Smart Lanes frame over 5 ms: UNKNOWN (no SQPERF ctx=bg window lines after the enroll", text)
        self.assertIn("- Mean cost under 1.5 ms/frame at 4x: UNKNOWN (no window lines).", text)

    def test_old_clock(self):
        """An older Smart Lanes (no clock=wall, no fetch_ms): its os.clock max_frame_ms is labeled inflated and never a spike."""
        with tempfile.TemporaryDirectory() as d:
            text = fr.render(fr.parse([write_log(d, city_log(old_clock=True))], warmup=0, min_samples=3, auto_settle=300))
        self.assertIn("longest frame 8.20 ms (os.clock: CPU time over all threads, inflated 3-6x on macOS; not counted as frame "
                      "spikes); fetch_ms not logged (an older Smart Lanes); person-list spikes (src=scan, a frame over 5 ms, once "
                      "per snapshot): 0.", text)
        self.assertIn("1 window(s) over: 0 with a person-list snapshot spike, 1 other", text)

    def test_swapped_runs_and_unequal_pairs(self):
        """Two v2 runs in one load (roles as usual, then swapped): a part per run, each pair's baseline gap with the warning
        over 10 %, and the swapped-roles mean of auto minus control."""
        first = city_log(run="city-9", swap="0", control_b=4.0)
        second = city_log(run="city-10", swap="1", control_v=5.4, header=False, gt0=2000)
        with tempfile.TemporaryDirectory() as d:
            text = fr.render(fr.parse([write_log(d, first + second)], warmup=0, min_samples=3, auto_settle=300))
        self.assertIn("### City run city-9 (layout hourglass, Busy, baseline 5 game min, roles as usual)", text)
        self.assertIn("### City run city-10 (layout hourglass, Busy, baseline 5 game min, roles swapped)", text)
        # run 1: control 14.4 km/h at baseline vs auto 18.0: +25 %
        self.assertIn("| cityg1 | cityg1v / cityg1b | 18.0 / 14.4 | +25 % | 10.0 / 10.0 |", text)
        self.assertIn("WARNING: pairs too unequal at baseline (km/h differs by more than 10 %): cityg1 (+25 %).", text)
        self.assertIn("### Swapped roles: runs city-9 and city-10", text)
        # run 1: auto +20 %, control 4.0 -> 4.8 = +20 %: 0 pp; run 2: auto +20 %, control +8 %: +12 pp; mean +6
        self.assertIn("| cityg1 | +0.0 | +12.0 | +6.0 | +25 % / +0 % |", text)
        self.assertIn("Swapped-roles effect of the automatic timing (km/h, auto minus control, mean over 1 pair(s)): +6.0 pp", text)

    def test_archived_old_clock_session(self):
        """The archived run 2 (2026-10-15_1950_city-lights-2-778824, os.clock): renders, labels its snapshot frames inflated."""
        import gzip
        src = Path(__file__).resolve().parents[2] / ".cache/logs/2026-10-15_1950_city-lights-2-778824.log.gz"
        if not src.exists():
            self.skipTest("archived session not here")
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "stdout.txt"
            p.write_bytes(gzip.decompress(src.read_bytes()))
            text = fr.render(fr.parse([p]))
        self.assertIn("## Auto lights at scale", text)
        self.assertIn("os.clock: CPU time over all threads, inflated", text)
        self.assertIn("Pairs at baseline", text)

    def test_no_section_without_a_city_run(self):
        with tempfile.TemporaryDirectory() as d:
            text = fr.render(fr.parse([write_log(d, [ln for ln in city_log() if "CITY_ENROLL" not in ln])], warmup=0))
        self.assertNotIn("## Auto lights at scale", text)


class V3Test(unittest.TestCase):
    """Traffic log v3 (SHOWCASE.md "Town entries", FLOW.md "Measured area"): r_measure / measure / arms on FLOW_ZONE,
    cars_core / q_arm on FLOW, target / frames on FLOW_ALL, FLOW_TARGET, the Lights showcase's entry lines."""

    def test_v3_fields(self):
        lines = ["    | mod params:", "[SQST] showcase zones sent n=2 run=r1 smart_lanes=yes",
                 "[SQST] showcase zone id=g1a pair=g1 ab=sl kind=plain type=2x2_X x=0 y=0 r=72 match=yes",
                 "[SQST] showcase zone id=g1b pair=g1 ab=game kind=plain type=2x2_X x=4000 y=0 r=72 match=yes",
                 "[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout at 0,713 node=55 removed=3",
                 "[SQST] lights_showcase entry Smart lanes 1 E kind=roundabout at 713,0 node=56 removed=3",
                 "[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout read ends=4 outer=60",
                 "[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout joined=3/3",
                 "[SQST] lights_showcase entry Smart lanes 1 E kind=roundabout joined=2/3 (broken)",
                 "[SQST] lights_showcase entry Game default 1 N kind=crossroads (roundabout refused: Collision)",
                 "[SQST] FLOW_START run=1 v=3 gt=0 gt_per_s=1000 cap=0 target_min=3000 measure_pad=200 corridor_m=30",
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=x twin=g1a pair=g1 ab=sl x=0 y=0 r=72 r_measure=272 measure=corridor arms=N,E,S,W",
                 "[SQST] FLOW_ZONE run=1 zone=2 kind=x twin=g1b pair=g1 ab=game x=4000 y=0 r=72 r_measure=272 measure=corridor arms=N,E,S,W"]
        for s in range(1, 7):
            lines.append(f"[SQST] FLOW run=1 s={s} zone=1 gt={s * 30000} cars=40 standing=20 queue=10 v_mean=3 "
                         f"cars_core=8 q_arm=N:4,E:2,S:{s},W:0")
            lines.append(f"[SQST] FLOW run=1 s={s} zone=2 gt={s * 30000} cars=30 standing=5 queue=1 v_mean=6 "
                         "cars_core=6 q_arm=N:1,E:0,S:0,W:0")
            lines.append(f"[SQST] FLOW_ALL run=1 s={s} gt={s * 30000} drivers=55000 sampled={55000 if s < 4 else 40000} "
                         f"standing=40000 v_mean=2 frames=150 sweep_ms=300 capped={0 if s < 4 else 1} "
                         f"target={'all' if s < 4 else 41250} stride={1 if s < 4 else 2} frame_ms_max=2.1")
        lines.append("[SQST] FLOW_TARGET run=1 s=4 target=41250 was=all read=55000 drivers_prev=55000 reason=skipped")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
            text = fr.render(rep)
        a = rep.zones[("sc", 1, "g1a")]
        self.assertEqual((a.measure, a.r, a.r_measure, a.arms), ("corridor", 72, 272, "N,E,S,W"))
        self.assertEqual(a.core_mean(), 8)
        self.assertEqual(a.q_arm_means(), {"N": 4, "E": 2, "S": 3.5, "W": 0})
        self.assertIn("## Approaches (v3 measured area)", text)
        self.assertIn("| g1a | sl | 72 / 272 | 40.0 | 8.0 | N 4.0, E 2.0, S 3.5, W 0.0 |", text)
        self.assertIn("target all -> 41250", text)
        self.assertIn("lights_showcase town entries: 1 broken, 1 crossroads, 2 roundabout (first crossroads: "
                      "(roundabout refused: Collision))", text)
        self.assertIn("| frames | capped | target |", text)
        self.assertIn("| 300 | 150 | 1 | 41250 |", text)

    def test_v2_lines_still_parse(self):
        lines = ["[SQST] FLOW_START run=1 v=2 gt=0 cap=3000",
                 "[SQST] FLOW_ZONE run=1 zone=1 kind=x label=X x=0 y=0 r=72",
                 "[SQST] FLOW run=1 s=1 zone=1 gt=0 cars=3 standing=1 v_mean=2",
                 "[SQST] FLOW_ALL run=1 s=1 gt=0 drivers=55000 sampled=3000 capped=1"]
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)], warmup=0)
            text = fr.render(rep)
        st = next(iter(rep.zones.values()))
        self.assertEqual((st.measure, st.q_arm_means(), st.core_mean()), ("-", {}, None))
        self.assertNotIn("## Approaches", text)
        self.assertIn("| 1 | - |", text)


class ToggleTest(unittest.TestCase):
    def test_blocks(self):
        lines = ["    | mod params:", "[SQRL] TOGGLE state=on phase=load seq=1 gt=0"]
        for gt, v in ((0, 9), (200000, 9), (300000, 9)):  # On#1 (0 dropped: warm-up)
            lines.append(f"[SQST] FLOW_ALL run=1 s=1 gt={gt} sampled=100 standing=10 v_mean={v}")
        lines.append("[SQRL] TOGGLE state=off phase=start seq=2 gt=400000")
        lines.append("[SQST] FLOW_ALL run=1 s=5 gt=410000 sampled=100 standing=10 v_mean=1")  # toggling
        lines.append("[SQRL] TOGGLE state=off phase=end seq=2 gt=420000")
        for gt in (500000, 620000, 700000):  # Off#1 (500000 in its warm-up)
            lines.append(f"[SQST] FLOW_ALL run=1 s=6 gt={gt} sampled=100 standing=30 v_mean=5")
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, lines)])
            blocks, toggling = fr.toggle_blocks(rep)
            text = fr.render(rep)
        self.assertEqual(toggling, 1)
        self.assertEqual([(b.state, len(b.alls), b.dropped) for b in blocks], [("on", 2, 1), ("off", 2, 1)])
        self.assertAlmostEqual(blocks[0].map_speed(), 9 * 3.6)
        self.assertIn("## Toggle blocks", text)
        self.assertIn("| On#1 | 1 | 1 | on |", text)
        self.assertIn("On#1 +14.4", text)
        self.assertIn("ABAB", text)


class SamplerEndToEndTest(unittest.TestCase):
    """The Stress Test traffic log's own lines (gui/stress_flow_log.tl on the fake api of
    tests/square_stress_test/flow_fake.lua, run by tests/square_stress_test/flow_e2e.lua through run_tests.ModRunner)
    parse into twins, pairs, buses and runs."""

    @classmethod
    def setUpClass(cls):
        root = Path(__file__).resolve().parents[2]
        sys.path.insert(0, str(root / "tests"))
        import run_tests  # noqa: PLC0415

        out = run_tests.ModRunner(root / "mods" / "square_stress_test").run_file(
            root / "tests" / "square_stress_test" / "flow_e2e.lua", None)
        res = out["results"]
        if not res or not res[0]["ok"]:
            raise AssertionError(f"flow_e2e.lua failed: {out.get('load_error') or (res and res[0]['err'])}")
        cls.lines = [ln for ln in res[0]["printed"].splitlines() if ln.startswith("[SQ")]

    def test_lines_parse_into_twins_and_pairs(self):
        self.assertTrue(any(ln.startswith("[SQST] FLOW_START ") for ln in self.lines))
        with tempfile.TemporaryDirectory() as d:
            rep = fr.parse([write_log(d, self.lines)])
            text = fr.render(rep)
        self.assertEqual(len(rep.loads), 1)
        self.assertEqual(rep.loads[0].gt_per_s, 1000)
        self.assertEqual(rep.partial, 0, "every FLOW line has zone, gt and cars")
        names = sorted(st.name for st in rep.zones.values() if st.key[0] == "sc")
        self.assertEqual(names, ["g1a", "g1b", "g2a", "g3a"], "every FLOW zone joined its showcase twin by twin=")
        g3a = next(st for st in rep.zones.values() if st.name == "g3a")
        self.assertGreater(g3a.n(), 15, "cars=0 lines are samples too")
        self.assertEqual(g3a.cars_mean(), 0)
        pairs = {(p.pair, p.a, p.b): p for p in rep.pairs}
        self.assertIn(("g1", "sl", "game"), pairs)
        p = pairs[("g1", "sl", "game")]
        self.assertGreater(p.d_speed(), 0, "the sl twin drives faster in the scenario")
        self.assertIn("g2", [x[0] for x in rep.excluded], "g2: match=no and no game twin")
        self.assertIn("## Bus lines (FLOW_BUS)", text)
        self.assertIn("| SQST_Bus_1 | g1 sl |", text)
        self.assertIn("## Sampler runs (FLOW_START / FLOW_SUMMARY)", text)
        self.assertIn("## Towns (FLOW_TOWNS)", text)
        self.assertIn("## Map-wide trend (FLOW_ALL)", text)
        # v3: g1a measured along its arms (q_arm), the rest as circles; every driver read
        self.assertIn("## Approaches (v3 measured area)", text)
        g1a = next(st for st in rep.zones.values() if st.name == "g1a")
        self.assertEqual((g1a.measure, g1a.arms), ("corridor", "N,E,S,W"))
        self.assertTrue(any(" target=all " in ln for ln in self.lines if ln.startswith("[SQST] FLOW_ALL ")))


if __name__ == "__main__":
    unittest.main()
