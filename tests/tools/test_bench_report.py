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
                self.assertEqual({e["sl_lights"] for e in data}, {"on"})
                # rows recorded with the setting Off never pool with an On run
                off = [dict(e, sl_lights="off") for e in data]
                text3 = br.render(b, rows, excluded, {"standing": 20.0, "samples": 2, "capped": 0, "strided": 0, "targets": 0,
                                                       "frame_max": 1.0, "thru_path": 0}, "third", off, False)
                self.assertNotIn("Pooled with the earlier runs", text3)
            finally:
                br.LEDGER, br.RESULTS = old_l, old_r


def sheet5_log(fallback: str | None = None) -> list[str]:
    """Bench sheet 5 (ring lane use): test lu2, sets s5g1 (straight) and s5g2 (even), twins game b / sl_rturbo h /
    sl_rmid2 w / sl_rmatch i. The sl_rmid2 twins: SPLIT (Smart Lanes adds the mid nodes), RSPLIT mids=4, 8 APPLY
    layout=sl_rmid2; `fallback`: that twin's split was refused (RSPLIT mids=0 fallback=sl_rturbo, APPLY layout=sl_rturbo).
    RINGMIX / RINGLANE at samples 6, 12, 18 and the stop. Speeds: game 5, sl_rturbo 5.5, sl_rmatch 6, sl_rmid2 7 m/s."""
    abs_ = ["game", "sl_rturbo", "sl_rmid2", "sl_rmatch"]
    out = ["[SQRL] MODE phases=game free_turn=always lights=on",
           "[SQST] BENCH_START sheet=s5 spec=bench_s5@1 seed=5 map=16000x16000 tests=1 groups=8 towns=32 year=1950 "
           "sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=x warmup_s=180 record_s=1200 interval_s=10 "
           "speed=2 pop=350 pool=no rank=yes",
           "[SQST] BENCH_TEST sheet=s5 id=lu2 title=Roundabout,_2-lane_ring kind=rb variants=RB4_2L twins=game,sl_rturbo,sl_rmid2,sl_rmatch "
           "compare=sl_rturbo:game,sl_rmid2:game,sl_rmatch:game,sl_rmid2:sl_rturbo,sl_rmatch:sl_rturbo sets=2/3 groups=8 towns=32 "
           "towns_per_twin=4 pop=350 lights=game mixes=even,straight,adjacent pops=large:600,small:100,even:350 ring_mix=yes",
           "[SQST] showcase zones sent n=8 run=s5-1-1 by_ab=x smart_lanes=yes"]
    zones = []
    zi = 0
    for s, mix in ((1, "straight"), (2, "even")):
        for ab in abs_:
            zi += 1
            zid = f"s5g{s}{LETTER[ab]}"
            out.append(f"[SQST] showcase zone id={zid} pair=s5g{s} ab={ab} kind=roundabout type=RB4_2L x={zi * 3000} y=0 r=103 "
                       f"r_from=measured towns=4 match=yes test=lu2 variant=RB4_2L approach=518 mix={mix}")
            zones.append((zi, zid, s, ab, mix))
    for zi, zid, s, ab, mix in zones:
        ring = 700000 + 10 * zi
        if ab == "game":
            out.append(f"[SQRL] SKIP kind=zone zone=game job=1 nodes=4 reason=zone_game zid={zid}")
            continue
        layout = ab
        if ab == "sl_rmid2":
            if zid == fallback:
                out.append(f"[SQRL] SPLIT ring={ring} node={ring} len=180 refused=short zid={zid}")
                out.append(f"[SQRL] RSPLIT ring={ring} node={ring} len=180 mids=0 fallback=sl_rturbo reason=no_mid_nodes zid={zid}")
                layout = "sl_rturbo"
            else:
                out.append(f"[SQRL] SPLIT ring={ring} node={ring} len=180 edges=1,2,3,4 nodes_added=4 zid={zid}")
                out.append(f"[SQRL] WRITE kind=split ring={ring} success=true")
                out.append(f"[SQRL] RSPLIT ring={ring} node={ring} len=180 mids=4 per_stretch=1 nodes=5,6,7,8 zid={zid}")
        for n in range(4):
            out.append(f"[SQRL] APPLY ring={ring} node={ring + 2 * n} lanes=2 dir=ccw exits=2 entries=2 turbo=true fresh=true "
                       f"before=6 after=5 layout={layout} zid={zid}")
        out.append(f"[SQRL] WRITE ring={ring} nodes={ring},{ring + 2},{ring + 4},{ring + 6} success=true")
    out.append(f"[SQST] FLOW_START run=1 v=3 interval=10 interval_unit=game_s zones={len(zones)} gt=1000000 gt_per_s=1000 src=placement sc_run=s5-1-1")
    for zi, zid, s, ab, mix in zones:
        out.append(f"[SQST] FLOW_ZONE run=1 zone={zi} kind=rb src=placement label=x x={zi * 3000} y=0 r=103 twin={zid} pair=s5g{s} "
                   f"ab={ab} test=lu2 mix={mix}")
    for k in range(1, 31):
        gt = 1000000 + k * 10000
        for zi, zid, s, ab, mix in zones:
            v = {"game": 5.0, "sl_rturbo": 5.5, "sl_rmatch": 6.0, "sl_rmid2": 7.0}[ab]
            out.append(f"[SQST] FLOW run=1 s={k} zone={zi} twin={zid} pair=s5g{s} ab={ab} gt={gt} cars=10 standing=2 "
                       f"standing_pct=20 queue=1 v_mean={v} v_med={v} v_kmh={v * 3.6:.1f} stand_mean=6 stand_max=9 cars_core=4 "
                       f"q_arm=- thru={({'game': 20, 'sl_rturbo': 22, 'sl_rmatch': 24, 'sl_rmid2': 30}[ab]) if k > 1 else '-'} "
                       f"thru_s={10 if k > 1 else '-'} thru_scale=1 thru_path=-")
            if k % 6 == 0 or k == 30:
                fin = 1 if k == 30 else 0
                out.append(f"[SQST] RINGMIX run=1 s={k} zone={zi} twin={zid} pair=s5g{s} ab={ab} gt={gt} arms=4 dir=ccw n={10 * k} "
                           f"exit1={2 * k} exit2={5 * k} exit3={2 * k} uturn={k} none=0 reads=1 capped=0 final={fin} mix={mix}")
                out.append(f"[SQST] RINGLANE run=1 s={k} zone={zi} twin={zid} pair=s5g{s} ab={ab} gt={gt} cars={20 * k} bin_m=0.5 "
                           f"radii=17.5:{(15 if ab == 'sl_rmid2' else 3) * k},14.0:{(5 if ab == 'sl_rmid2' else 17) * k} final={fin}")
    out.append("[SQST] BENCH_DONE sheet=s5 spec=bench_s5@1 seed=5 ok=yes samples=30 speed=2 minutes=25 problems=0 speed_end=1")
    return [PFX + x for x in out]


class Sheet5RingUseTest(unittest.TestCase):
    """Bench sheet 5: the ring lane use twins' treatment (sl_rmid2 needs its mid nodes: RSPLIT mids > 0), the comparisons
    against game and sl_rturbo, and the Ring lane use section in the draft."""

    def run_it(self, lines):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "s5.log"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            rep = br.fr.parse([p])
            rows, excluded = br.build_rows(b, rep)
            text = br.render(b, rows, excluded, br.map_wide([p]), "sess", [], False, br.extra_lines(b, rep))
            return b, rows, excluded, text

    def test_comparisons_ranking_and_ring_section(self):
        b, rows, excluded, text = self.run_it(sheet5_log())
        self.assertEqual((b.sheet, b.start.get("spec")), ("s5", "bench_s5@1"))
        self.assertEqual(excluded, [])
        got = {r.compare: (r.stats()["n"], r.stats()["w"]) for r in rows}
        self.assertEqual(got, {"sl_rturbo vs game": (2, 2), "sl_rmid2 vs game": (2, 2), "sl_rmatch vs game": (2, 2),
                               "sl_rmid2 vs sl_rturbo": (2, 2), "sl_rmatch vs sl_rturbo": (2, 2)})
        self.assertIn("| 1 | sl_rmid2 | 2 |", text)
        self.assertIn("## Ring lane use", text)
        # the window from sample 24 (the first line after the 180 s cut: first sample + 180 s = sample 19) to the stop (30):
        # 60 drivers; lanes outer first; mixes in set order (even, straight)
        self.assertIn("| lu2 | straight | sl_rmid2 | 1 | 12 | 180.0 | 25.2 | 20 | 1.0 | - | o1 75 % (17.5 m), o2 25 % (14.0 m) | "
                      "1st 20 %, 2nd 50 %, 3rd 20 %, U 10 % (n 60, none 0 %) |", text)
        self.assertIn("| lu2 | straight | game | 1 | 12 | 120.0 | 18.0 | 20 | 1.0 | - | o1 15 % (17.5 m), o2 85 % (14.0 m) |", text)
        self.assertLess(text.index("| lu2 | even |"), text.index("| lu2 | straight |"))
        self.assertIn("- **lu2 straight**: sl_rmid2 best by thru/min (180.0). sl_rmid2: +50 % thru/min, +7.2 km/h, standing +0 pp "
                      "vs game; +36 % thru/min, +5.4 km/h, standing +0 pp vs sl_rturbo.", text)
        self.assertIn("| lu2 | straight | s5g1w | sl_rmid2 | 60 | 12 | 30 | 12 | 6 | 0 |", text)

    def test_rmid2_twin_whose_split_was_refused_is_excluded(self):
        _b, rows, excluded, _text = self.run_it(sheet5_log(fallback="s5g2w"))
        self.assertTrue(any(e[0] == "s5g2" and "no ring APPLY / SKIP same with layout=sl_rmid2" in e[2] for e in excluded), excluded)
        got = {r.compare: r.stats()["n"] for r in rows}
        self.assertEqual((got["sl_rmid2 vs game"], got["sl_rmid2 vs sl_rturbo"], got["sl_rmatch vs game"]), (1, 1, 2))

    def test_rmid2_twin_with_mids_0_is_excluded(self):
        lines = [ln.replace("mids=4 per_stretch=1", "mids=0 fallback=sl_rturbo reason=cap per_stretch=0")
                 if "zid=s5g1w" in ln and "RSPLIT" in ln else ln for ln in sheet5_log()]
        _b, _rows, excluded, _text = self.run_it(lines)
        self.assertTrue(any(e[0] == "s5g1" and "sl_rmid2 twin: no mid nodes on its ring, written as sl_rturbo" in e[2]
                            for e in excluded), excluded)


def sheet6_log(refused: str | None = None, lock: str = "s6g2a") -> list[str]:
    """Bench sheet 6 (the mid-node default under heavy traffic): test hm2, sets s6g1 even / s6g2 straight / s6g3 adjacent,
    twins game b / sl a / sl_rmatch i / sl_rturbo h. The sl twins: Smart Lanes splits the plain ring (SPLIT nodes_added=4),
    RSPLIT mids=4, APPLY layout=sl_rmid default=one_lane_exits; `refused`: that sl twin's split refused (APPLY
    layout=sl_rspiral default=one_lane_exits, RSPLIT mids=0). sl_rturbo: APPLY turbo=false layout=sl_rturbo (matched).
    180 samples at 10 game s (30 game min); `lock` gridlocks from sample 90 on: 9 of 10 cars standing, 1 car through per
    sample (others: 3 standing, 12 through)."""
    abs_ = ["game", "sl", "sl_rmatch", "sl_rturbo"]
    out = ["[SQRL] MODE phases=game free_turn=always lights=on",
           "[SQST] BENCH_START sheet=s6 spec=bench_s6@1 seed=6 map=16000x16000 tests=1 groups=12 towns=48 year=1950 "
           "sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=x warmup_s=180 record_s=1800 interval_s=10 "
           "speed=2 pop=600 pool=no rank=yes",
           "[SQST] BENCH_TEST sheet=s6 id=hm2 title=Roundabout kind=rb variants=RB_2L_town twins=game,sl,sl_rmatch,sl_rturbo "
           "compare=sl:game,sl_rmatch:game,sl_rturbo:game,sl:sl_rmatch,sl_rmatch:sl_rturbo sets=3/3 groups=12 towns=48 "
           "towns_per_twin=4 pop=600 lights=game mixes=even,straight,adjacent pops=large:1000,small:200,even:600 ring_mix=yes",
           "[SQST] showcase zones sent n=12 run=s6-1-1 by_ab=x smart_lanes=yes"]
    zones = []
    zi = 0
    for s, mix in ((1, "even"), (2, "straight"), (3, "adjacent")):
        for ab in abs_:
            zi += 1
            zid = f"s6g{s}{LETTER[ab]}"
            out.append(f"[SQST] showcase zone id={zid} pair=s6g{s} ab={ab} kind=roundabout type=RB_2L_town x={zi * 3000} y=0 r=80 "
                       f"r_from=measured towns=4 match=yes test=hm2 variant=RB_2L_town approach=518 mix={mix}")
            zones.append((zi, zid, s, ab, mix))
    for zi, zid, s, ab, mix in zones:
        ring = 800000 + 10 * zi
        if ab == "game":
            out.append(f"[SQRL] SKIP kind=zone zone=game job=1 nodes=4 reason=zone_game zid={zid}")
            continue
        tail = f"layout={ab}"
        turbo = "false"
        if ab == "sl":
            if zid == refused:
                out.append(f"[SQRL] SPLIT ring={ring} node={ring} len=70 refused=short zid={zid}")
                out.append(f"[SQRL] RSPLIT ring={ring} node={ring} len=70 mids=0 fallback=sl_rspiral reason=no_mid_nodes zid={zid}")
                tail = "layout=sl_rspiral default=one_lane_exits"
            else:
                out.append(f"[SQRL] SPLIT ring={ring} node={ring} len=90 edges=1,2,3,4 nodes_added=4 zid={zid}")
                out.append(f"[SQRL] WRITE kind=split ring={ring} success=true")
                out.append(f"[SQRL] RSPLIT ring={ring} node={ring} len=90 mids=4 per_stretch=1 nodes=5,6,7,8 zid={zid}")
                tail = "layout=sl_rmid default=one_lane_exits"
        for n in range(4):
            out.append(f"[SQRL] APPLY ring={ring} node={ring + 2 * n} lanes=2 dir=ccw exits=1 entries=1 turbo={turbo} fresh=true "
                       f"before=4 after=3 {tail} zid={zid}")
        out.append(f"[SQRL] WRITE ring={ring} nodes={ring},{ring + 2},{ring + 4},{ring + 6} success=true")
    out.append(f"[SQST] FLOW_START run=1 v=3 interval=10 interval_unit=game_s zones={len(zones)} gt=1000000 gt_per_s=1000 src=placement sc_run=s6-1-1")
    for zi, zid, s, ab, mix in zones:
        out.append(f"[SQST] FLOW_ZONE run=1 zone={zi} kind=rb src=placement label=x x={zi * 3000} y=0 r=80 twin={zid} pair=s6g{s} "
                   f"ab={ab} test=hm2 mix={mix}")
    for k in range(1, 181):
        gt = 1000000 + k * 10000
        for zi, zid, s, ab, mix in zones:
            locked = zid == lock and k >= 90
            v = 0.3 if locked else {"game": 4.0, "sl": 5.0, "sl_rmatch": 4.5, "sl_rturbo": 4.5}[ab]
            st, th = (9, 1) if locked else (3, 12)
            out.append(f"[SQST] FLOW run=1 s={k} zone={zi} twin={zid} pair=s6g{s} ab={ab} gt={gt} cars=10 standing={st} "
                       f"queue={st} v_mean={v} thru={th if k > 1 else '-'} thru_s={10 if k > 1 else '-'}")
    out.append("[SQST] BENCH_DONE sheet=s6 spec=bench_s6@1 seed=6 ok=yes samples=180 speed=2 minutes=30 problems=0 speed_end=1")
    return [PFX + x for x in out]


class Sheet6HeavyTest(unittest.TestCase):
    """Bench sheet 6: the sl twin must carry Smart Lanes' shipped default (APPLY layout=sl_rmid default=one_lane_exits on
    mid nodes it added), sl_rmatch vs sl_rturbo is an expected tie (both matched on one-lane exits), gridlock per twin."""

    def run_it(self, lines):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "s6.log"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            rep = br.fr.parse([p])
            rows, excluded = br.build_rows(b, rep)
            text = br.render(b, rows, excluded, br.map_wide([p]), "sess", [], False, br.extra_lines(b, rep))
            return b, rows, excluded, text

    def test_default_check_tie_and_gridlock(self):
        b, rows, excluded, text = self.run_it(sheet6_log())
        self.assertEqual(excluded, [])
        got = {r.compare: r.stats()["n"] for r in rows}
        self.assertEqual(got, {"sl vs game": 3, "sl_rmatch vs game": 3, "sl_rturbo vs game": 3, "sl vs sl_rmatch": 3,
                               "sl_rmatch vs sl_rturbo": 3})
        self.assertIn("| hm2 | sl_rmatch vs sl_rturbo (identical by design: expected tie) |", text)
        self.assertIn("Mode check, hm2: s6g1a layout=sl_rmid default=one_lane_exits split nodes_added=4 mids=4; s6g1h turbo=false "
                      "(matched lanes: every exit one lane);", text)
        # gridlock: s6g2a locked from sample 90 (game min 15 of its record: the 180 s warm-up cut drops samples 1-17)
        self.assertIn("Gridlock per twin", text)
        self.assertIn("| hm2 | straight | s6g2a | sl | 14 | 8 | 90 | 6.0 | 72.0 | GRIDLOCK from game min 12 |", text)
        self.assertIn("| hm2 | straight | s6g2b | game | 14 | 0 | 30 | 72.0 | 72.0 | no |", text)
        self.assertIn("Gridlock: sl (s6g2a) from game min 12.", text)
        self.assertNotIn("GRIDLOCK", text.split("| hm2 | adjacent |")[0].split("| hm2 | even |")[1].split("| hm2 | straight |")[0])

    def test_sl_twin_whose_split_was_refused_is_excluded(self):
        _b, rows, excluded, text = self.run_it(sheet6_log(refused="s6g3a"))
        self.assertTrue(any(e[0] == "s6g3" and "sl twin: no ring APPLY layout=sl_rmid default=one_lane_exits (layout sl_rspiral; "
                            "SPLIT refused=short)" in e[2] for e in excluded), excluded)
        self.assertEqual({r.compare: r.stats()["n"] for r in rows}["sl vs game"], 2)
        self.assertIn("s6g3a layout=sl_rspiral default=one_lane_exits split refused=short mids=0", text)


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


class MicroPoolTest(unittest.TestCase):
    """The micro bench (BENCH_START sheet=micro pool=yes, zone ids microg<k><twin>): per test rows plus a pooled row;
    recorded under its own sheet key."""

    def micro_log(self):
        out = []
        for l in bench_log(seed=7):
            l = l.replace("sheet=s1", "sheet=micro").replace("bench_s1@1", "bench_micro@1").replace(" speed=2", " speed=2 pop=800 pool=yes", 1) \
                if "BENCH_START" in l else l.replace("sheet=s1", "sheet=micro")
            # prefixed ids: microg1a, pair microg1
            l = l.replace("id=g", "id=microg").replace("twin=g", "twin=microg").replace("pair=g", "pair=microg").replace("zid=g", "zid=microg")
            out.append(l)
        return out

    def test_pooled_row(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "m.log"
            p.write_text("\n".join(self.micro_log()) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            self.assertEqual((b.sheet, b.start.get("pool")), ("micro", "yes"))
            rows, excluded = br.build_rows(b, br.fr.parse([p]))
            self.assertEqual(excluded, [])
            text = br.render(b, rows, excluded, br.map_wide([p]), "sess", [], False)
            self.assertIn("| rb4 | sl vs game | 3 |", text)
            self.assertIn("| drop | sl vs game | 2 |", text)
            self.assertIn("| all (pooled) | sl vs game | 5 | +7.2 | 5/0/0 |", text)
            self.assertIn("### Bench sheet micro: sess (seed 7)", text)
            self.assertEqual(text.count("| microg1 |"), 2, "pairs listed under their tests only (sl vs game, sl vs sl_keeplights)")


RING = ["sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread"]
LETTER = {"game": "b", "sl": "a", "sl_rturbo": "h", "sl_rmatch": "i", "sl_rout1": "j", "sl_r2exit": "k", "sl_rspiral": "l",
          "sl_rspread": "m", "sl_rsplit": "n", "sl_rmid": "o", "sl_rmid2": "w", "sl_rturbo_in": "y"}


def ring_log(no_layout: str | None = None, refused: dict | None = None, same_only: str | None = None) -> list[str]:
    """Micro bench v2: tests rb4l (sets 1, 2) and rb3 (set 3), 8 twins each; speeds: game 5, sl 6, the ring modes 6.5 +
    0.5 per position in RING (sl_rspread fastest), rb3's sl_rout1 the slowest twin."""
    abs_ = ["game", "sl"] + RING
    comp = ",".join(["sl:game"] + [f"{m}:sl" for m in RING] + [f"{m}:game" for m in RING])
    out = ["[SQRL] MODE phases=game free_turn=always lights=on",
           "[SQST] BENCH_START sheet=micro spec=bench_micro@2 seed=9 map=16000x16000 tests=2 groups=24 towns=96 year=1950 "
           "sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=x warmup_s=180 record_s=1200 interval_s=10 "
           "speed=2 pop=600 pool=yes rank=yes"]
    for t in ("rb4l", "rb3"):
        out.append(f"[SQST] BENCH_TEST sheet=micro id={t} title={t} kind=rb variants=v twins={','.join(abs_)} compare={comp} "
                   f"sets=1/2 groups=8 towns=32 towns_per_twin=4 pop=600 lights=game")
    out.append("[SQST] showcase zones sent n=24 run=s9-1-1 by_ab=x smart_lanes=yes")
    zones = []
    zi = 0
    for s, test in ((1, "rb4l"), (2, "rb4l"), (3, "rb3")):
        for ab in abs_:
            zi += 1
            zid = f"microg{s}{LETTER[ab]}"
            out.append(f"[SQST] showcase zone id={zid} pair=microg{s} ab={ab} kind=roundabout type=RB x={zi * 3000} y=0 r=120 "
                       f"r_from=measured towns=4 match=yes test={test} variant=RB approach=518")
            zones.append((zi, zid, s, ab, test))
    for zi, zid, s, ab, test in zones:
        if ab == "game":
            out.append(f"[SQRL] SKIP kind=zone zone=game job=1 nodes=4 reason=zone_game zid={zid}")
        else:
            lay = "" if ab == "sl" or zid == no_layout else f" layout={ab}"
            ring = 400000 + zi
            if zid == same_only:
                # Smart Lanes looked and left it: the ring already had the layout (no write)
                out.append(f"[SQRL] SKIP kind=ring ring={ring} node={ring} reason=same{lay} zid={zid}")
                continue
            for n in range(4):
                out.append(f"[SQRL] APPLY ring={ring} node={ring + n} lanes=4 dir=ccw exits=3 entries=3 turbo=true fresh=true "
                           f"before=11 after=9{lay} zid={zid}")
            nodes = ",".join(str(ring + n) for n in range(4))
            for ok in (refused or {}).get(zid, ["true"]):
                out.append(f"[SQRL] WRITE ring={ring} nodes={nodes} success={ok}")
    out.append("[SQST] FLOW_START run=1 v=3 interval=10 interval_unit=game_s zones=24 gt=1000000 gt_per_s=1000 src=placement sc_run=s9-1-1")
    for zi, zid, s, ab, test in zones:
        out.append(f"[SQST] FLOW_ZONE run=1 zone={zi} kind=rb src=placement label=x x={zi * 3000} y=0 r=120 twin={zid} pair=microg{s} ab={ab}")
    for k in range(1, 21):
        gt = 1000000 + k * 30000
        for zi, zid, s, ab, test in zones:
            v = 5.0 if ab == "game" else (6.0 if ab == "sl" else 6.5 + 0.5 * RING.index(ab))
            if test == "rb3" and ab == "sl_rout1":
                v = 3.0
            out.append(f"[SQST] FLOW run=1 s={k} zone={zi} twin={zid} pair=microg{s} ab={ab} gt={gt} cars=10 standing=2 "
                       f"standing_pct=20 queue=1 v_mean={v} v_med={v} v_kmh={v * 3.6:.1f} stand_mean=6 stand_max=9 cars_core=4 "
                       f"q_arm=- thru={30 if k > 1 else '-'} thru_s={30 if k > 1 else '-'} thru_scale=1 thru_path=-")
    out.append("[SQST] BENCH_DONE sheet=micro spec=bench_micro@2 seed=9 ok=yes samples=20 speed=2 minutes=25 problems=0 speed_end=1")
    return [PFX + x for x in out]


class MicroRankTest(unittest.TestCase):
    def run_it(self, lines):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "r.log"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            rep = br.fr.parse([p])
            rows, excluded = br.build_rows(b, rep)
            text = br.render(b, rows, excluded, br.map_wide([p]), "sess", [], False, br.ranking(b, rep))
            return b, rows, excluded, text

    def test_ranking_and_pairwise(self):
        _b, rows, excluded, text = self.run_it(ring_log())
        self.assertEqual(excluded, [])
        self.assertIn("(~600 people each)", text)
        self.assertIn("Ranking, rb4l (by km/h; mean over its sets):", text)
        self.assertIn("| 1 | sl_rspread | 2 | 32.4 | +14.4 | 20 | 60.0 |", text)
        self.assertIn("| 8 | game | 2 | 18.0 | +0.0 |", text)
        self.assertIn("Ranking, rb3", text)
        self.assertIn("| 8 | sl_rout1 | 1 | 10.8 | -7.2 |", text)
        self.assertIn("Ranking, pooled over the ring types", text)
        self.assertIn("| sl_rspread | 2 | +14.4 | 1.0 |", text)
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual(got[("rb4l", "sl_rturbo vs sl")], 2)
        self.assertEqual(got[("rb4l", "sl_rspread vs game")], 2)
        self.assertIn("| all (pooled) | sl_rspiral vs game | 3 |", text)

    def test_mode_without_its_layout_is_excluded(self):
        _b, rows, excluded, text = self.run_it(ring_log(no_layout="microg1h"))
        self.assertTrue(any("no ring APPLY / SKIP same with layout=sl_rturbo" in e[2] for e in excluded), excluded)
        self.assertIn("| sl_rturbo | 1 |", text.split("Ranking, rb4l")[1].split("Ranking, rb3")[0])


class RingWriteTest(unittest.TestCase):
    def run_it(self, lines):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "w.log"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            rep = br.fr.parse([p])
            rows, excluded = br.build_rows(b, rep)
            text = br.render(b, rows, excluded, br.map_wide([p]), "sess", [], False, br.ranking(b, rep))
            return rows, excluded, text

    def test_refused_write_is_untreated(self):
        rows, excluded, text = self.run_it(ring_log(refused={"microg1j": ["false"], "microg2j": ["false", "true"]}))
        why = [e for e in excluded if "ring write refused (WRITE success=false), ring 400005" in e[2]]
        self.assertTrue(why, excluded)
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual(got[("rb4l", "sl_rout1 vs sl")], 1, "set 2's refused-then-landed write counts")
        rank = text.split("Ranking, rb4l")[1].split("Ranking, rb3")[0]
        self.assertIn("| sl_rout1 | 1 |", rank, "left out of the ranking too")

    def test_skip_same_with_layout_is_treated(self):
        rows, excluded, _text = self.run_it(ring_log(same_only="microg1h"))
        self.assertEqual(excluded, [])
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual(got[("rb4l", "sl_rturbo vs sl")], 2)

    def test_expected_tie_marked(self):
        # only the 2-lane ring's sl_rout1 is the game's layout (EXPECTED_TIES); the 3-lane ring's is not (micro v2)
        self.assertEqual(br.tie_note("rb2", "sl_rout1 vs game"), " (identical by design: expected tie)")
        _rows, _excl, text = self.run_it(ring_log())
        self.assertNotIn("| rb3 | sl_rout1 vs game (identical", text)
        self.assertNotIn("| rb4l | sl_rout1 vs game (identical", text)
        self.assertIn("| rb3 | sl_rout1 vs game | 1 |", text)


def sheet4_log(no_layout: str | None = None, node_only: str | None = None, sets: int = 3) -> list[str]:
    """Bench sheet 4 v1 (BENCH.md "Sheet 4"): test rb2t, 3 sets x game / sl / sl_rspiral, ids s4g<k><twin>. The sl
    twins: Smart Lanes' matched lanes equal the ring's (SKIP kind=ring reason=same, no layout=); the spiral twins
    APPLY layout=sl_rspiral. Speeds: game 5, sl 5.5, spiral 6 m/s."""
    abs_ = ["game", "sl", "sl_rspiral"]
    out = ["[SQRL] MODE phases=game free_turn=always lights=on",
           "[SQST] BENCH_START sheet=s4 spec=bench_s4@1 seed=5 map=16000x16000 tests=1 groups=9 towns=36 year=1950 "
           "sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=x warmup_s=180 record_s=1200 interval_s=10 "
           "speed=2 pop=400 pool=no rank=yes",
           "[SQST] BENCH_TEST sheet=s4 id=rb2t title=Roundabout,_2-lane_ring,_4_one-lane_town_street_arms kind=rb "
           "variants=RB_2L_town twins=game,sl,sl_rspiral compare=sl:game,sl_rspiral:sl,sl_rspiral:game sets=3/9 groups=9 "
           "towns=36 towns_per_twin=4 pop=400 lights=game",
           "[SQST] showcase zones sent n=9 run=s5-1-1 by_ab=x smart_lanes=yes"]
    zones = []
    zi = 0
    for s in range(1, sets + 1):
        for ab in abs_:
            zi += 1
            zid = f"s4g{s}{LETTER[ab]}"
            out.append(f"[SQST] showcase zone id={zid} pair=s4g{s} ab={ab} kind=roundabout type=RB_2L_town x={zi * 3000} y=0 "
                       f"r=123 r_from=measured towns=4 match=yes test=rb2t variant=RB_2L_town approach=518")
            zones.append((zi, zid, s, ab))
    for zi, zid, s, ab in zones:
        ring = 500000 + zi
        if ab == "game":
            out.append(f"[SQRL] SKIP kind=zone zone=game job=1 nodes=4 reason=zone_game zid={zid}")
        elif zid == node_only:
            out.append(f"[SQRL] SKIP kind=node node={ring} reason=plain zid={zid}")
        elif ab == "sl":
            for n in range(4):
                out.append(f"[SQRL] SKIP kind=ring ring={ring} node={ring + n} reason=same zid={zid}")
        else:
            lay = "" if zid == no_layout else " layout=sl_rspiral"
            for n in range(4):
                out.append(f"[SQRL] APPLY ring={ring} node={ring + n} lanes=2 dir=ccw exits=1 entries=1 turbo=false fresh=true "
                           f"before=4 after=5{lay} zid={zid}")
            out.append(f"[SQRL] WRITE ring={ring} nodes={ring},{ring + 1},{ring + 2},{ring + 3} success=true")
    out.append("[SQST] FLOW_START run=1 v=3 interval=10 interval_unit=game_s zones=9 gt=1000000 gt_per_s=1000 src=placement sc_run=s5-1-1")
    for zi, zid, s, ab in zones:
        out.append(f"[SQST] FLOW_ZONE run=1 zone={zi} kind=rb src=placement label=x x={zi * 3000} y=0 r=123 twin={zid} pair=s4g{s} ab={ab}")
    for k in range(1, 21):
        gt = 1000000 + k * 30000
        for zi, zid, s, ab in zones:
            v = {"game": 5.0, "sl": 5.5, "sl_rspiral": 6.0}[ab]
            out.append(f"[SQST] FLOW run=1 s={k} zone={zi} twin={zid} pair=s4g{s} ab={ab} gt={gt} cars=10 standing=2 "
                       f"standing_pct=20 queue=1 v_mean={v} v_med={v} v_kmh={v * 3.6:.1f} stand_mean=6 stand_max=9 cars_core=4 "
                       f"q_arm=- thru={30 if k > 1 else '-'} thru_s={30 if k > 1 else '-'} thru_scale=1 thru_path=-")
    out.append("[SQST] BENCH_DONE sheet=s4 spec=bench_s4@1 seed=5 ok=yes samples=20 speed=2 minutes=25 problems=0 speed_end=1")
    return [PFX + x for x in out]


class Sheet4SpiralTest(unittest.TestCase):
    def run_it(self, lines):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "s4.log"
            p.write_text("\n".join(lines) + "\n", encoding="utf-8")
            b = br.read_bench([p])
            rep = br.fr.parse([p])
            rows, excluded = br.build_rows(b, rep)
            text = br.render(b, rows, excluded, br.map_wide([p]), "sess", [], False, br.ranking(b, rep))
            return b, rows, excluded, text

    def test_three_comparisons_and_ranking(self):
        b, rows, excluded, text = self.run_it(sheet4_log())
        self.assertEqual((b.sheet, b.start.get("spec")), ("s4", "bench_s4@1"))
        self.assertEqual(excluded, [])
        got = {(r.test, r.compare): (r.stats()["n"], r.stats()["w"]) for r in rows}
        self.assertEqual(got, {("rb2t", "sl vs game"): (3, 3), ("rb2t", "sl_rspiral vs sl"): (3, 3),
                               ("rb2t", "sl_rspiral vs game"): (3, 3)})
        self.assertIn("### Bench sheet s4: sess (seed 5)", text)
        self.assertIn("| s4g1 |", text)
        self.assertIn("Ranking, rb2t (by km/h; mean over its sets):", text)
        self.assertIn("| 1 | sl_rspiral | 3 | 21.6 | +3.6 |", text)

    def test_spiral_twin_without_its_layout_is_excluded(self):
        _b, rows, excluded, _text = self.run_it(sheet4_log(no_layout="s4g2l"))
        self.assertTrue(any(e[0] == "s4g2" and "no ring APPLY / SKIP same with layout=sl_rspiral" in e[2] for e in excluded), excluded)
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual((got[("rb2t", "sl_rspiral vs sl")], got[("rb2t", "sl vs game")]), (2, 3))

    def test_sl_twin_that_saw_no_ring_is_excluded(self):
        _b, _rows, excluded, _text = self.run_it(sheet4_log(node_only="s4g3a"))
        self.assertTrue(any(e[0] == "s4g3" and "saw no ring junction" in e[2] for e in excluded), excluded)

    def test_one_set(self):
        # sheet 4 v2 runs one set (a quick direction): one pair per comparison, the ranking still drawn
        _b, rows, excluded, text = self.run_it(sheet4_log(sets=1))
        self.assertEqual(excluded, [])
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual(set(got.values()), {1})
        self.assertIn("Ranking, rb2t", text)


def sheet4v3_log(sets: int = 3, fallback: str | None = None, no_rsplit: str | None = None, v4: bool = False) -> list[str]:
    """Bench sheet 4 v3 (BENCH.md "Sheet 4"): test rb2tm (the ring with mid nodes), sets x game / sl / sl_rspiral /
    sl_rsplit, ids s4g<k><twin> (sl_rsplit: n). The sl_rsplit twins APPLY layout=sl_rsplit at the 4 junctions and the 4
    mid nodes (mid=yes) and log one RSPLIT line (mids=4); `fallback`: that twin's ring had no mid nodes (RSPLIT
    fallback=sl_rspiral, APPLY layout=sl_rspiral); `no_rsplit`: that twin logs no RSPLIT line. Speeds: game 5, sl 5.5,
    spiral 6, split 6.5 m/s."""
    abs_ = ["game", "sl", "sl_rspiral", "sl_rsplit"] + (["sl_rmid"] if v4 else [])
    spec = "bench_s4@4" if v4 else "bench_s4@3"
    compare = "sl:game,sl_rspiral:sl,sl_rspiral:game,sl_rsplit:sl_rspiral,sl_rsplit:game"
    if v4:
        compare += ",sl_rmid:sl_rsplit,sl_rmid:sl_rspiral,sl_rmid:game"
    out = ["[SQRL] MODE phases=game free_turn=always lights=on",
           f"[SQST] BENCH_START sheet=s4 spec={spec} seed=7 map=16000x16000 tests=1 groups=5 towns=20 year=1950 "
           "sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=x warmup_s=180 record_s=600 interval_s=5 "
           "speed=2 pop=400 pool=no rank=yes",
           "[SQST] BENCH_TEST sheet=s4 id=rb2tm title=Roundabout,_2-lane_ring_with_mid_nodes,_4_one-lane_town_street_arms kind=rb "
           f"variants=RB_2L_town_mid twins={','.join(abs_)} "
           f"compare={compare} sets=1/1 groups=5 "
           "towns=16 towns_per_twin=4 pop=400 lights=game",
           "[SQST] showcase zones sent n=4 run=s7-1-1 by_ab=x smart_lanes=yes"]
    zones = []
    zi = 0
    for s in range(1, sets + 1):
        for ab in abs_:
            zi += 1
            zid = f"s4g{s}{LETTER[ab]}"
            out.append(f"[SQST] showcase zone id={zid} pair=s4g{s} ab={ab} kind=roundabout type=RB_2L_town_mid x={zi * 3000} y=0 "
                       f"r=123 r_from=measured towns=4 match=yes test=rb2tm variant=RB_2L_town_mid approach=518")
            zones.append((zi, zid, s, ab))
    for zi, zid, s, ab in zones:
        ring = 600000 + 10 * zi
        if ab == "game":
            out.append(f"[SQRL] SKIP kind=zone zone=game job=1 nodes=8 reason=zone_game zid={zid}")
        elif ab == "sl":
            for n in range(4):
                out.append(f"[SQRL] SKIP kind=ring ring={ring} node={ring + 2 * n} reason=same zid={zid}")
        elif ab == "sl_rspiral" or zid == fallback:
            if zid == fallback:
                out.append(f"[SQRL] RSPLIT ring={ring} node={ring} mids=0 fallback=sl_rspiral reason=no_mid_nodes zid={zid}")
            for n in range(4):
                out.append(f"[SQRL] APPLY ring={ring} node={ring + 2 * n} lanes=2 dir=ccw exits=1 entries=1 turbo=false fresh=true "
                           f"before=4 after=5 layout=sl_rspiral zid={zid}")
            out.append(f"[SQRL] WRITE ring={ring} nodes={ring},{ring + 2},{ring + 4},{ring + 6} success=true")
        else:
            if zid != no_rsplit:
                mids = ",".join(str(ring + 2 * n + 1) for n in range(4))
                out.append(f"[SQRL] RSPLIT ring={ring} node={ring} mids=4 nodes={mids} zid={zid}")
            for n in range(4):
                out.append(f"[SQRL] APPLY ring={ring} node={ring + 2 * n} lanes=2 dir=ccw exits=1 entries=1 turbo=false fresh=true "
                           f"before=4 after=4 layout={ab} zid={zid}")
            for n in range(4):
                out.append(f"[SQRL] APPLY ring={ring} node={ring + 2 * n + 1} lanes=2 dir=ccw exits=0 entries=0 turbo=false "
                           f"fresh=true before=2 after=3 layout={ab} mid=yes zid={zid}")
            out.append(f"[SQRL] WRITE ring={ring} nodes={','.join(str(ring + k) for k in range(8))} success=true")
    out.append(f"[SQST] FLOW_START run=1 v=3 interval=10 interval_unit=game_s zones={len(zones)} gt=1000000 gt_per_s=1000 src=placement sc_run=s7-1-1")
    for zi, zid, s, ab in zones:
        out.append(f"[SQST] FLOW_ZONE run=1 zone={zi} kind=rb src=placement label=x x={zi * 3000} y=0 r=123 twin={zid} pair=s4g{s} ab={ab}")
    for k in range(1, 21):
        gt = 1000000 + k * 30000
        for zi, zid, s, ab in zones:
            v = {"game": 5.0, "sl": 5.5, "sl_rspiral": 6.0, "sl_rsplit": 6.5, "sl_rmid": 7.0}[ab]
            out.append(f"[SQST] FLOW run=1 s={k} zone={zi} twin={zid} pair=s4g{s} ab={ab} gt={gt} cars=10 standing=2 "
                       f"standing_pct=20 queue=1 v_mean={v} v_med={v} v_kmh={v * 3.6:.1f} stand_mean=6 stand_max=9 cars_core=4 "
                       f"q_arm=- thru={30 if k > 1 else '-'} thru_s={30 if k > 1 else '-'} thru_scale=1 thru_path=-")
    out.append(f"[SQST] BENCH_DONE sheet=s4 spec={spec} seed=7 ok=yes samples=20 speed=2 minutes=13 problems=0 speed_end=1")
    return [PFX + x for x in out]


class Sheet4SplitTest(unittest.TestCase):
    run_it = Sheet4SpiralTest.run_it

    def test_five_comparisons_and_ranking(self):
        b, rows, excluded, text = self.run_it(sheet4v3_log())
        self.assertEqual((b.sheet, b.start.get("spec")), ("s4", "bench_s4@3"))
        self.assertEqual(excluded, [])
        got = {(r.test, r.compare): (r.stats()["n"], r.stats()["w"]) for r in rows}
        self.assertEqual(got, {("rb2tm", "sl vs game"): (3, 3), ("rb2tm", "sl_rspiral vs sl"): (3, 3),
                               ("rb2tm", "sl_rspiral vs game"): (3, 3), ("rb2tm", "sl_rsplit vs sl_rspiral"): (3, 3),
                               ("rb2tm", "sl_rsplit vs game"): (3, 3)})
        self.assertIn("Ranking, rb2tm (by km/h; mean over its sets):", text)
        self.assertIn("| 1 | sl_rsplit | 3 |", text)
        self.assertEqual(b.rsplit["s4g1n"]["mids"], "4")

    def test_one_set(self):
        _b, rows, excluded, _text = self.run_it(sheet4v3_log(sets=1))
        self.assertEqual(excluded, [])
        self.assertEqual({r.stats()["n"] for r in rows}, {1})

    def test_split_twin_that_fell_back_to_the_spiral_is_excluded(self):
        _b, rows, excluded, _text = self.run_it(sheet4v3_log(fallback="s4g2n"))
        self.assertTrue(any(e[0] == "s4g2" and "no ring APPLY / SKIP same with layout=sl_rsplit" in e[2] for e in excluded), excluded)
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual((got[("rb2tm", "sl_rsplit vs sl_rspiral")], got[("rb2tm", "sl_rsplit vs game")], got[("rb2tm", "sl vs game")]),
                         (2, 2, 3))

    def test_split_twin_without_rsplit_line_is_excluded(self):
        _b, rows, excluded, _text = self.run_it(sheet4v3_log(no_rsplit="s4g3n"))
        self.assertTrue(any(e[0] == "s4g3" and "no RSPLIT line" in e[2] for e in excluded), excluded)
        got = {(r.test, r.compare): r.stats()["n"] for r in rows}
        self.assertEqual(got[("rb2tm", "sl_rsplit vs game")], 2)


class Sheet4MidTest(unittest.TestCase):
    """Bench sheet 4 v4: a 5th twin sl_rmid (letter o) on the mid-node ring; its checks as sl_rsplit's."""
    run_it = Sheet4SpiralTest.run_it

    def test_eight_comparisons_and_ranking(self):
        b, rows, excluded, text = self.run_it(sheet4v3_log(v4=True))
        self.assertEqual(b.start.get("spec"), "bench_s4@4")
        self.assertEqual(excluded, [])
        got = {r.compare: (r.stats()["n"], r.stats()["w"]) for r in rows}
        for c in ("sl_rmid vs sl_rsplit", "sl_rmid vs sl_rspiral", "sl_rmid vs game", "sl_rsplit vs sl_rspiral"):
            self.assertEqual(got[c], (3, 3), c)
        self.assertEqual(len(got), 8)
        self.assertIn("| 1 | sl_rmid | 3 |", text)

    def test_mid_twin_that_fell_back_is_excluded(self):
        _b, rows, excluded, _text = self.run_it(sheet4v3_log(v4=True, fallback="s4g2o"))
        self.assertTrue(any(e[0] == "s4g2" and "no ring APPLY / SKIP same with layout=sl_rmid" in e[2] for e in excluded), excluded)
        got = {r.compare: r.stats()["n"] for r in rows}
        self.assertEqual((got["sl_rmid vs sl_rsplit"], got["sl_rsplit vs game"]), (2, 3))

    def test_mid_twin_with_mids_0_is_excluded(self):
        # an RSPLIT line with mids=0 alone excludes it, whatever the APPLY lines say
        lines = sheet4v3_log(v4=True)
        lines = [ln.replace("mids=4 nodes=", "mids=0 nodes=") if "zid=s4g1o" in ln and "RSPLIT" in ln else ln for ln in lines]
        _b, _rows, excluded, _text = self.run_it(lines)
        self.assertTrue(any(e[0] == "s4g1" and "sl_rmid twin: no mid nodes" in e[2] for e in excluded), excluded)

    def test_mid_twin_without_rsplit_line_is_excluded(self):
        _b, _rows, excluded, _text = self.run_it(sheet4v3_log(v4=True, no_rsplit="s4g3o"))
        self.assertTrue(any(e[0] == "s4g3" and "sl_rmid twin: no RSPLIT line" in e[2] for e in excluded), excluded)


def sheet4v5_log(no_rsplit: str | None = None) -> list[str]:
    """Bench sheet 4 v5: test rb2v (2-lane town ring), one set, twins on the plain ring (game b, sl a) and on the mid-node
    ring (game p, sl_rsplit s, sl_rmid t): zone lines carry geom=plain|mid, the modes read "<ab>@<geom>". Speeds:
    game@plain 5, sl@plain 5.5, game@mid 4, sl_rsplit@mid 6.5, sl_rmid@mid 6 m/s."""
    twins = [("game", "plain", "b"), ("sl", "plain", "a"), ("game", "mid", "p"), ("sl_rsplit", "mid", "s"), ("sl_rmid", "mid", "t")]
    speed = {"game@plain": 5.0, "sl@plain": 5.5, "game@mid": 4.0, "sl_rsplit@mid": 6.5, "sl_rmid@mid": 6.0}
    compare = "sl_rsplit@mid:game@plain,sl_rsplit@mid:sl@plain,game@mid:game@plain,sl@plain:game@plain,sl_rmid@mid:game@plain,sl_rmid@mid:sl_rsplit@mid"
    out = ["[SQRL] MODE phases=game free_turn=always lights=on",
           "[SQST] BENCH_START sheet=s4 spec=bench_s4@5 seed=9 map=16000x16000 tests=1 groups=5 towns=20 year=1950 "
           "sl_auto=on sl_lights=on sl_free_turn=always sl_phases=game sl_modes=x warmup_s=180 record_s=600 interval_s=5 "
           "speed=2 pop=400 pool=no rank=yes",
           "[SQST] BENCH_TEST sheet=s4 id=rb2v title=Roundabout,_2-lane_ring,_plain_and_with_mid_nodes kind=rb "
           f"variants=RB_2L_town,RB_2L_town_mid twins={','.join(a + '@' + g for a, g, _ in twins)} compare={compare} "
           "sets=1/1 groups=5 towns=20 towns_per_twin=4 pop=400 lights=game",
           "[SQST] showcase zones sent n=5 run=s9-1-1 by_ab=x smart_lanes=yes"]
    zones = []
    for zi, (ab, geom, letter) in enumerate(twins, 1):
        zid = f"s4g1{letter}"
        var = "RB_2L_town_mid" if geom == "mid" else "RB_2L_town"
        out.append(f"[SQST] showcase zone id={zid} pair=s4g1 ab={ab} kind=roundabout type={var} x={zi * 3000} y=0 r=123 "
                   f"r_from=measured towns=4 match=yes test=rb2v variant={var} geom={geom} approach=518")
        zones.append((zi, zid, ab, geom))
    for zi, zid, ab, geom in zones:
        ring = 700000 + 10 * zi
        if ab == "game":
            out.append(f"[SQRL] SKIP kind=zone zone=game job=1 nodes=8 reason=zone_game zid={zid}")
        elif ab == "sl":
            for n in range(4):
                out.append(f"[SQRL] APPLY ring={ring} node={ring + n} lanes=2 dir=ccw exits=1 entries=1 turbo=false fresh=true "
                           f"before=4 after=5 layout=sl_rspiral default=one_lane_exits zid={zid}")
            out.append(f"[SQRL] RSPLIT ring={ring} node={ring} mids=0 fallback=sl_rspiral reason=no_mid_nodes zid={zid}")
            out.append(f"[SQRL] WRITE ring={ring} nodes={ring} success=true")
        else:
            if zid != no_rsplit:
                out.append(f"[SQRL] RSPLIT ring={ring} node={ring} mids=4 per_stretch=1 nodes=1,2,3,4 zid={zid}")
            for n in range(4):
                out.append(f"[SQRL] APPLY ring={ring} node={ring + n} lanes=2 dir=ccw exits=1 entries=1 turbo=false fresh=true "
                           f"before=4 after=4 layout={ab} zid={zid}")
            out.append(f"[SQRL] WRITE ring={ring} nodes={ring} success=true")
    out.append(f"[SQST] FLOW_START run=1 v=3 interval=10 interval_unit=game_s zones={len(zones)} gt=1000000 gt_per_s=1000 src=placement sc_run=s9-1-1")
    for zi, zid, ab, geom in zones:
        out.append(f"[SQST] FLOW_ZONE run=1 zone={zi} kind=rb src=placement label=x x={zi * 3000} y=0 r=123 twin={zid} pair=s4g1 ab={ab}")
    for k in range(1, 21):
        gt = 1000000 + k * 30000
        for zi, zid, ab, geom in zones:
            v = speed[ab + "@" + geom]
            out.append(f"[SQST] FLOW run=1 s={k} zone={zi} twin={zid} pair=s4g1 ab={ab} gt={gt} cars=10 standing=2 "
                       f"standing_pct=20 queue=1 v_mean={v} v_med={v} v_kmh={v * 3.6:.1f} stand_mean=6 stand_max=9 cars_core=4 "
                       f"q_arm=- thru={30 if k > 1 else '-'} thru_s={30 if k > 1 else '-'} thru_scale=1 thru_path=-")
    out.append("[SQST] BENCH_DONE sheet=s4 spec=bench_s4@5 seed=9 ok=yes samples=20 speed=2 minutes=13 problems=0 speed_end=1")
    return [PFX + x for x in out]


class Sheet4PlainVsMidTest(unittest.TestCase):
    """Sheet 4 v5: one set's twins on two geometries; comparisons and the ranking name them <ab>@<geom>."""
    run_it = Sheet4SpiralTest.run_it

    def test_comparisons_across_geometries_and_ranking(self):
        b, rows, excluded, text = self.run_it(sheet4v5_log())
        self.assertEqual(excluded, [])
        got = {r.compare: (r.stats()["n"], r.stats()["w"]) for r in rows}
        self.assertEqual(got, {"sl_rsplit@mid vs game@plain": (1, 1), "sl_rsplit@mid vs sl@plain": (1, 1),
                               "game@mid vs game@plain": (1, 0), "sl@plain vs game@plain": (1, 1),
                               "sl_rmid@mid vs game@plain": (1, 1), "sl_rmid@mid vs sl_rsplit@mid": (1, 0)})
        self.assertIn("Ranking, rb2v (by km/h; mean over its sets):", text)
        self.assertIn("| 1 | sl_rsplit@mid | 1 | 23.4 | +5.4 |", text)
        self.assertIn("| 5 | game@mid | 1 | 14.4 | -3.6 |", text)

    def test_mid_twin_without_rsplit_line_is_excluded(self):
        _b, rows, excluded, _text = self.run_it(sheet4v5_log(no_rsplit="s4g1s"))
        self.assertTrue(any("sl_rsplit twin: no RSPLIT line" in e[2] for e in excluded), excluded)
        got = {r.compare: r.stats()["n"] for r in rows}
        self.assertEqual((got["sl_rsplit@mid vs game@plain"], got["game@mid vs game@plain"]), (0, 1))
