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
