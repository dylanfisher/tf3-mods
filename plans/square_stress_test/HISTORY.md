# Stress Test: history

Superseded designs and finished notes, moved verbatim (newest first). See plans/README.md.

## TESTING.md 6Y, bench sheet 4 v4 (moved 2026-10-14: ran 2026-10-14, `BENCH_DONE spec=bench_s4@4 seed=455860 ok=yes`; every write landed, live samples in BENCH.md "Sheet 4" v5; superseded by v5)

Background: BENCH.md "Sheet 4" (v4: the v3 ring `bench_rb2tm` with a plain node half way between the arms for every
twin; a 5th twin `sl_rmid`; the same five twins on a 3-lane ring `bench_rb3m` and a 4-lane ring `bench_rb4lm`). v3 ran 2026-10-14 (its checks: HISTORY.md). Mods: Stress Test, Smart Lanes with the ring
layout modes `sl_rspiral`, `sl_rsplit` and `sl_rmid` (Apply automatically On, No lights at roundabouts and ramps On: the
preflight refuses otherwise, and names `sl_rmid` for an older Smart Lanes), Roundabouts & Interchanges with the dev
override `sqrb_dev_ring_mid` (this repo's staging copy). A free game, 16 km Blank Slate, right-hand traffic (the v3 map
can be reused: the bench clears it).
1. Debug window > Towns tab > Bench > **Sheet 4**. **Pass:** the dialog says "15 junctions, 60 towns (~24k people), about
   N min to build; 16.0 x 16.0 km map: everything fits". Press "Run bench".
2. Leave the game running, unpaused, in front, until the Bench status says `Bench s4 done (seed N)` (about 20 min).
3. Say "done". Claude runs `make bench`.
What Claude checks: `BENCH_START sheet=s4 spec=bench_s4@4`; three `BENCH_TEST` lines (`id=rb2tm`, `id=rb3m`, `id=rb4lm`, each
`sets=1/1 groups=5 towns=20`); 15 `BENCH_TWIN ... geometry=ok what=one_way_streets n=.. mids=..` (rb2tm `n=8 mids=4`, rb3m
`mids=4`, rb4lm `n=12 mids=8`; `geometry=bad`: the 3-lane entry ring or the 4-lane ring was built without its nodes, or the
game refused the bigger ring: then a `refused=` count); `bench_s4 summary ... built=15 refused=0 ... linked=60 unlinked=0 ...
sets_mismatch=0`. Per test (zone ids per pair `s4g<k>`): zones `s4g1b` (game), `s4g1a` (sl), `s4g1l` (`layout=sl_rspiral`, no `mid=yes`),
`s4g1n` (sl_rsplit: `RSPLIT ... mids=4`, mid nodes `after=3`, `VERIFY ... same=8 nodes=8`), and **`s4g1o`** (sl_rmid:
`RSPLIT ... mids=4 nodes=<4 ids> zid=s4g1o`, 8 `APPLY ... layout=sl_rmid`: junctions `after=3`, mid nodes `exits=0
entries=0 ... before=2 after=4 ... mid=yes`, its `WRITE ring=.. success=true` and **`VERIFY ring=.. same=8 nodes=8`**: the
engine keeps two crossing lane changes at a 2-edge node; square_smart_lanes TESTING.md "RS" step 7); `BENCH_DONE
ok=yes`. On the wide rings the same lines with more mid nodes: rb3m `RSPLIT ... mids=4 per_stretch=1`, sl_rmid
junctions `after=8` (3-lane: o1 -> 3 exit lanes, o2, o3 straight, 3 entries) and mid nodes `after=7`, `VERIFY ... same=8 nodes=8`; rb4lm `mids=8
per_stretch=2`, sl_rmid junctions `after=8`, mid nodes `after=10`, `VERIFY ... same=12 nodes=12`. The report per test: rows
`sl_rmid vs sl_rsplit`, `sl_rmid vs sl_rspiral`, `sl_rmid vs game`, `sl_rsplit vs sl_rspiral`, `sl vs game` (one pair
each: a direction) and the ranking of the five modes; a `treatment: sl_rmid twin: ...` exclusion says why the twin did not count.
4. With the shots (or live at 2x): on `s4g1o`, nobody changes lanes at an arm; cars bound for the next exit move out at
   the mid node, cars going further move in there; nobody stops at a mid node (the two lane changes cross there). The
   Crossing Tool can't pick a mid node: the APPLY `mid=yes` / VERIFY lines prove the lanes; at an arm junction of `s4g1o`
   it shows 3 curves (outer lane into the exit, inner lane straight, the entry into the outer lane).

## TESTING.md 6Y, bench sheet 4 v3 (moved 2026-10-14: ran 2026-10-14, every twin `mids=4`, sl_rsplit mid nodes written, `VERIFY same=8 nodes=8`; superseded by v4)

Background: BENCH.md "Sheet 4" (v3: the ring with a plain node half way between the arms, `bench_rb2tm`, for every
twin; a 4th twin `sl_rsplit`). v2 ran in session `2026-10-13_2341_bench-s4-774314` (`BENCH_DONE ok=yes`; its checks:
HISTORY.md). Mods: Stress Test, Smart Lanes with the ring layout modes `sl_rspiral` and `sl_rsplit` (Apply automatically
On, No lights at roundabouts and ramps On: the preflight refuses otherwise, and names `sl_rsplit` for an older Smart
Lanes), Roundabouts & Interchanges with the dev override `sqrb_dev_ring_mid` (this repo's staging copy). A free game,
16 km Blank Slate, right-hand traffic (the v2 map can be reused: the bench clears it).
1. Debug window > Towns tab > Bench > **Sheet 4**. **Pass:** the dialog says "4 junctions, 16 towns (~6k people), about
   N min to build; 16.0 x 16.0 km map: everything fits". Press "Run bench".
2. Leave the game running, unpaused, in front, until the Bench status says `Bench s4 done (seed N)` (about 15 min).
3. Say "done". Claude runs `make bench`.
What Claude checks: `BENCH_START sheet=s4 spec=bench_s4@3`; `BENCH_TEST id=rb2tm ... sets=1/1 groups=4 towns=16`; 4
`BENCH_TWIN ... geometry=ok what=one_way_streets n=8 mids=4` (the mid nodes stand in every twin; `geometry=bad ...
mids=` under 4: the staging square_roundabouts lacks the override); `bench_s4 summary ... built=4 refused=0 ... linked=16
unlinked=0 ... sets_mismatch=0`; zones `s4g1b` (game, `SKIP ... reason=zone_game`), `s4g1a` (sl, matched), `s4g1l`
(`APPLY ... layout=sl_rspiral` at the 4 junctions, no `mid=yes`), `s4g1n`: `RSPLIT ... mids=4 nodes=<4 ids>
zid=s4g1n`, 8 `APPLY ... layout=sl_rsplit` (4 of them `exits=0 entries=0 ... before=2 after=3 ... mid=yes`), `WRITE ring=..
success=true`, `VERIFY ring=.. same=8 nodes=8` (the game kept the lane change at the 2-edge nodes: the open question,
square_smart_lanes TESTING.md "RS"); `BENCH_DONE ok=yes`. The report: rows `sl_rsplit vs sl_rspiral` and `sl_rsplit vs
game` (one pair each: a direction), the ranking of the four modes; a `treatment: sl_rsplit twin: ...` exclusion says why
the twin did not count.
4. With the shots (or live at 2x): on `s4g1n`, cars that enter stay in the outer lane to the next exit or move to the
   inner lane at the mid node (the Crossing Tool can't pick a mid node: the APPLY `mid=yes` / VERIFY lines prove the lanes; TESTING.md
   "RS" in square_smart_lanes).

## TESTING.md 6Y, bench sheet 4 v2 (moved 2026-10-14: ran 2026-10-13, session `2026-10-13_2341_bench-s4-774314`, `BENCH_DONE ok=yes`; superseded by v3)

Background: BENCH.md "Sheet 4" (v1 run: every link refused; v2: 1 set, 2 + 2 country links with fallbacks). Mods:
Stress Test, Smart Lanes with the ring layout mode `sl_rspiral` (Apply automatically On, No lights at roundabouts and
ramps On: the preflight refuses otherwise), Roundabouts & Interchanges. A free game, 16 km Blank Slate, right-hand
traffic (the v1 map can be reused: the bench clears it).
1. Debug window > Towns tab > Bench > **Sheet 4**. **Pass:** the dialog says "3 junctions, 12 towns (~5k people), about
   N min to build; 16.0 x 16.0 km map: everything fits". Press "Run bench".
2. Leave the game running, unpaused, in front, until the Bench status says `Bench s4 done (seed N)` (about 15 min:
   a short build, 3 game min warm-up and 20 game min recorded at 2x).
3. Say "done". Claude runs `make bench`.
What Claude checks: `BENCH_START sheet=s4 spec=bench_s4@2`; `BENCH_TEST ... sets=1/1 groups=3 towns=12`; 3
`BENCH_TWIN ... geometry=ok`; `bench_s4 summary ... built=3 refused=0 ... linked=12 unlinked=0 ... sets_mismatch=0`
(which link variant took: a link line with "(copies of the arm's street)" or "(the country road of the arm's lanes)"
means the 2 + 2 link was refused: note it in BENCH.md); the spiral twin's ring `APPLY ... layout=sl_rspiral zid=s4g1l`,
the sl twin matched (`turbo_reason=narrow_exit`), `SKIP ... reason=zone_game zid=s4g1b`; `BENCH_DONE ok=yes`.

## Lights showcase growth x25 (SHOWCASE.md, 2026-10-12; superseded 2026-10-12 by x10, then 2026-10-13 by x3 for ~1000 people per town)

- **Density instead of area** (Lights showcase): `LIGHTS_GROW_FACTOR` x25 (GROW_FACTORS[4]; was x10 = the Showcase's
  DENSE_GROW_FACTOR), still one size command (`LIGHTS_GROW_PASSES` 1), DENSE_WEIGHTS {0, 0.1, 0.5, 1} (tall
  buildings), every street locked (the town can only build up, never out). Why x25: the engine keeps size factors
  unclamped (x100 on Tacoma read back 100, docs/findings/lines-vehicles.md "Big growth factors"); where the streets
  are full the building count plateaus while the people per building keep rising; our cap MAX_SIZE_FACTOR 1000.
  Not x100: ~100 Medium towns at once on one map, unmeasured sim load; raise after TESTING.md 6U step 3 if the game
  keeps up. The Showcase keeps x10 in 3 passes. More people per building without any growth: the load setting
  "Town building capacity" x2 / x4 (experimental; TESTING.md 6U).
