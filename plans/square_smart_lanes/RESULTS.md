Status: current (started 2026-10-13). Running ledger of Smart Lanes traffic-flow results from the Stress Test
Lights showcase. Add every new run at the top of "Runs"; update "Verdicts" when a run changes one.

# Smart Lanes flow results

How a run is made and read: `plans/square_stress_test/SHOWCASE.md` (Lights showcase) and
`plans/square_stress_test/FLOW.md` (traffic log contract). Reproduce any row with
`make flow LOG=<session>` (raw logs in `.cache/logs/`, `make logs-list`).

Twins (zone modes, `mods/square_smart_lanes/content/smart_lanes/sl_zones.lua`):

| twin | lanes | light phases | kerb turn |
|---|---|---|---|
| `game` | game default (Smart Lanes leaves it alone) | game | game (waits) |
| `sl` | Smart Lanes | game | the setting (Always in every run here) |
| `sl_lock` | Smart Lanes | game | always locked (waits) |
| `sl_phases` | Smart Lanes | Smart Lanes planner (x4 split) | per the plan |
| `sl_fan` | full fan (every lane to every lane) | Smart Lanes planner | per the plan |

Columns: km/h = car-weighted mean speed in the zone (junction circle + arm corridors), standing = share of cars
under 0.5 m/s, queue = cars standing >= 5 s. "Δ" = first twin minus second, averaged over pairs; W/L = sets won
/ lost by the first twin (speed); p = two-sided sign test over pairs. With 3 pairs the best possible p is 0.25,
with 6 pairs 0.031.

## Verdicts so far

| question | answer | confidence | evidence |
|---|---|---|---|
| Smart Lanes lanes vs game lanes, lit crossroads / T, game phases | **Smart Lanes faster**: +3.5 km/h, 11 of 12 pairs, all four shapes (run 5); +6.9 km/h, 4 of 5 (run 6) | strong overall (p = 0.006 in run 5); per shape only a trend | runs 5, 6 |
| ... per shape | 3x3 X +8.2 km/h (3/3), T 2x2 +3.4 (3/3), 3x2 X +1.3 (2/1), 2x2 X +1.0 (3/0) | trend | run 5 |
| Earlier 2x2 losses (runs 1-4) | an artefact of the test, not of Smart Lanes: the rig joined the 2-lane arms to the 3-lane links lane to lane only (forced lane changes, which hurt a layout that pins turns to one exit lane), and the maps were jammed (towns x3/x10) | likely; run 5 fixed both and the sign flipped | runs 3-5, lane audit 2026-10-13 |
| Turns fanned into every reachable exit lane (`sl_exitfan`) vs today's pinned exit lanes | **worse**: −2.9 km/h, lost all 5 pairs, every shape | medium (p = 0.062, one run); keep today's pinning | run 6 |
| Smart Lanes lanes vs game lanes, 2-lane 4-arm roundabout (unlit after Smart Lanes) | **Smart Lanes better**: +1.5 km/h, 9 of 9 sets, **+16 cars/min through** (9 of 9) | strong (p = 0.004, Holm 0.012) | bench s1 |
| "No lights at roundabouts and ramps" at roundabouts (sl vs sl_keeplights) | **no measurable effect at 2-lane roundabouts** (unlike slip lanes, bench s2): −0.2 km/h, 4/5; throughput equal (game had lit 108 ring junctions) | medium (9 pairs, light traffic) | bench s1 |
| ~~Smart Lanes lane drop 3→2 vs game~~ | **nothing to measure**: at a 3+3 → 2+2 country road the game's own connections already equal Smart Lanes' drop rule (its sl twins logged `same=1`, no change), so both twins had the same lanes and the 5/6 was noise | n/a | bench s1 |
| Smart Lanes vs game, channelized T (slip lanes) | **Smart Lanes much better**: +28.5 km/h, 9 of 9, standing −31 pp, **+17.5 cars/min** (9 of 9) | strong (p = 0.004, Holm 0.012) | bench s2 |
| "No lights at roundabouts and ramps" at slip-lane junctions (sl vs sl_keeplights) | **the lights are the whole difference**: sl +29.0 km/h vs keep-lights, 9 of 9, +16.9 cars/min; keep-lights ≈ game (~12-15 km/h). The game lights the slip-lane junctions (81 kept) and that throttles them | strong (p = 0.004) | bench s2 |
| Smart Lanes vs game, diamond interchange | faster: +19.4 km/h, 5 of 6, standing −19 pp; throughput equal (−1.9/min, 3/3) | trend (p = 0.22); pool with a second run | bench s2 |
| Smart Lanes vs game, lit T 2x2 (light traffic, game phases) | **Smart Lanes better**: +9.2 km/h, 9 of 9, +4.7 cars/min (9 of 9) | strong (p = 0.004, Holm 0.016); settles the run 5/6 T split | bench s3 |
| Smart Lanes vs game, lit X (2x2/3x3/3x2, light traffic) | +12.7 km/h, 3 of 3, +8.2 cars/min | trend (3 pairs); agrees with run 5 (11/12) | bench s3 |
| Free kerb turn (Always) vs locked | **no clear effect**: jammed 2x2 −0.1 km/h (2/4, run 4); light traffic lit T +2.7 (5/4) and lit X +5.3 (2/1), pooled 7 of 12, throughput 8 of 12 slightly up. Harmless; keep Always | medium (no test significant) | run 4, bench s3 |
| Smart Lanes phase planner (`sl_phases`) vs game phases | **much worse**: −4.7 to −4.8 km/h, +23-25 pp standing, every set in every run. Cause: x4 split cycle gives each approach ~21 s of 92 s vs the game's ~24 s of 71 s | strong (4 runs) | runs 1-4 |
| Full fan (`sl_fan`) | **worst**: −6.2 km/h vs game, worse than `sl_phases` too | strong (3 runs); dropped from the showcase | runs 1-3 |

Known confound (runs 5-6, found 2026-10-13 by the bench design): inside the Smart Lanes twins' zones, Smart Lanes
also rewrote the 2-lane arm / 3-lane link joint as a lane drop (`APPLY kind=drop`, 26 in run 6, one per 2-lane arm
end), while the game twins kept the rig's own joint. So the 2-lane shapes' sl vs game numbers include that joint;
3x3 X (no such joint) shows the largest gain, so the verdict likely stands. The bench (plans/square_stress_test/
BENCH.md) keeps links at the arm's lane count so no lane change happens inside a zone.

Open questions:
- Per-shape significance: needs 6+ pairs per shape (a single-shape run, or more sets).
- Free kerb turn without a jam, and at 3-lane / T junctions (untested; run 4 was 2x2 only and saturated).
- `sl_exitfan` lost in run 6 (5 of 5 pairs); one more run would make it significant. Likely cause: the two turns
  that share one exit lane in the same phase merge without giving way.
- Throughput (cars through per minute): the `thru` count read 0 in run 5 (being fixed); speed / standing are the
  only measures so far. Under saturation they mostly measure queues.

## Runs

### Bench sheet s3: 2026-10-13_0733_bench-s3-683079 (seed 683079)
Setup: bench_s3@1, map 16384x16384 m, 36 junctions, 117 towns (~400 people each); Smart Lanes game phases, free kerb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 6 screenshots.
Build: summary seed=683079 groups=36 built=36 refused=0 lt22=27/27 lx=9/9 shapes T_2x2=27/27 2x2_X=3/3 3x3_X=3/3 3x2_X=3/3 sl=12/12 game=12/12 sl_lock=12/12 links=117 linked=117 unlinked=0 towns_skipped=0 se
Entries: entries roundabout=117 crossroads=0 broken=0 joins=351/351
Sampler: 120 map-wide samples recorded, map-wide standing 18 %; capped 0, strided 0, FLOW_TARGET 0, busiest frame 8.5 ms (phase list); thru by position.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| lt22 | sl vs game | 9 | +9.2 | 9/0/0 | 0.004 | 0.016 | 0.004 | -11.1 | +4.7 (9/0) |
| lt22 | sl vs sl_lock | 9 | +2.7 | 5/4/0 | 1.000 | 1.000 | 0.570 | -6.8 | +1.1 (6/3) |
| lx | sl vs game | 3 | +12.7 | 3/0/0 | 0.250 | 0.750 | 0.250 | -14.8 | +8.2 (3/0) |
| lx | sl vs sl_lock | 3 | +5.3 | 2/1/0 | 1.000 | 1.000 | 0.500 | -8.4 | +9.2 (2/1) |

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| lt22 | sl vs game | g1 | T_2x2 | 39.1 / 18.9 | +20.2 | -18 | -25.0 | 78.2 / 74.8 |
| lt22 | sl vs game | g2 | T_2x2 | 20.3 / 18.4 | +1.9 | -4 | -8.5 | 76.7 / 75.1 |
| lt22 | sl vs game | g3 | T_2x2 | 22.6 / 17.6 | +5.0 | -11 | -18.4 | 82.6 / 76.2 |
| lt22 | sl vs game | g4 | T_2x2 | 21.5 / 15.1 | +6.4 | -10 | -21.0 | 82.2 / 72.0 |
| lt22 | sl vs game | g5 | T_2x2 | 31.0 / 24.1 | +7.0 | -9 | -10.3 | 82.4 / 76.6 |
| lt22 | sl vs game | g6 | T_2x2 | 21.9 / 16.0 | +6.0 | -11 | -24.9 | 74.5 / 73.7 |
| lt22 | sl vs game | g7 | T_2x2 | 26.0 / 20.6 | +5.4 | -9 | -13.3 | 84.7 / 75.2 |
| lt22 | sl vs game | g8 | T_2x2 | 47.1 / 21.9 | +25.1 | -21 | -20.5 | 75.5 / 74.9 |
| lt22 | sl vs game | g9 | T_2x2 | 27.0 / 21.2 | +5.9 | -8 | -12.3 | 85.7 / 81.7 |
| lt22 | sl vs sl_lock | g1 | T_2x2 | 39.1 / 20.9 | +18.1 | -23 | -26.8 | 78.2 / 69.8 |
| lt22 | sl vs sl_lock | g2 | T_2x2 | 20.3 / 29.7 | -9.5 | +6 | +8.9 | 76.7 / 80.9 |
| lt22 | sl vs sl_lock | g3 | T_2x2 | 22.6 / 39.8 | -17.2 | +9 | +12.7 | 82.6 / 74.5 |
| lt22 | sl vs sl_lock | g4 | T_2x2 | 21.5 / 22.1 | -0.6 | -4 | -5.5 | 82.2 / 80.5 |
| lt22 | sl vs sl_lock | g5 | T_2x2 | 31.0 / 24.3 | +6.7 | -10 | -12.9 | 82.4 / 81.7 |
| lt22 | sl vs sl_lock | g6 | T_2x2 | 21.9 / 24.5 | -2.6 | -3 | -6.6 | 74.5 / 82.5 |
| lt22 | sl vs sl_lock | g7 | T_2x2 | 26.0 / 25.4 | +0.6 | -5 | -5.6 | 84.7 / 78.5 |
| lt22 | sl vs sl_lock | g8 | T_2x2 | 47.1 / 24.5 | +22.6 | -23 | -22.9 | 75.5 / 81.0 |
| lt22 | sl vs sl_lock | g9 | T_2x2 | 27.0 / 21.2 | +5.8 | -8 | -14.7 | 85.7 / 82.8 |
| lx | sl vs game | g10 | 2x2_X | 18.7 / 12.7 | +5.9 | -7 | -37.0 | 113.2 / 103.5 |
| lx | sl vs game | g11 | 3x3_X | 49.8 / 21.7 | +28.1 | -29 | -47.8 | 126.2 / 114.3 |
| lx | sl vs game | g12 | 3x2_X | 28.1 / 24.2 | +3.9 | -8 | -14.3 | 109.0 / 106.1 |
| lx | sl vs sl_lock | g10 | 2x2_X | 18.7 / 14.2 | +4.5 | -8 | -21.7 | 113.2 / 96.7 |
| lx | sl vs sl_lock | g11 | 3x3_X | 49.8 / 36.9 | +12.9 | -14 | -10.1 | 126.2 / 108.2 |
| lx | sl vs sl_lock | g12 | 3x2_X | 28.1 / 29.5 | -1.4 | -3 | -5.2 | 109.0 / 116.0 |

Treatment (Smart Lanes lines with zid=): lt22: game 9 (applied 0, unchanged 0, skipped 9, lights off 0, kept 0, lit at read 9), sl 9 (applied 9, unchanged 0, skipped 0, lights off 0, kept 0, lit at read 9), sl_lock 9 (applied 9, unchanged 0, skipped 0, lights off 0, kept 0, lit at read 9); lx: game 3 (applied 0, unchanged 0, skipped 3, lights off 0, kept 0, lit at read 3), sl 3 (applied 3, unchanged 0, skipped 0, lights off 0, kept 0, lit at read 3), sl_lock 3 (applied 3, unchanged 0, skipped 0, lights off 0, kept 0, lit at read 3).

Suggested verdict lines (review before adding to the Verdicts table):
- lt22, sl vs game: sl better by +9.2 km/h, 9/9 pairs, sign p 0.004 (Holm 0.016): significant.
- lt22, sl vs sl_lock: sl better by +2.7 km/h, 5/9 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- lx, sl vs game: sl better by +12.7 km/h, 3/3 pairs, sign p 0.250 (Holm 0.750): trend.
- lx, sl vs sl_lock: sl better by +5.3 km/h, 2/3 pairs, sign p 1.000 (Holm 1.000): no clear effect.

### Bench sheet s2: 2026-10-13_0610_session (seed 571569)
Setup: bench_s2@1, map 16384x16384 m, 39 junctions, 117 towns (~400 people each); Smart Lanes game phases, free kerb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 5 screenshots.
Build: summary seed=571569 groups=39 built=39 refused=0 cht=27/27 dia=12/12 shapes Channel_T=27/27 Diamond_S=12/12 game=15/15 sl=15/15 sl_keeplights=9/9 links=117 linked=117 unlinked=0 towns_skipped=0 sets_m
Entries: entries roundabout=117 crossroads=0 broken=0 joins=351/351
Tests: from the zone lines (the log has no BENCH_TEST lines): sl vs game and sl vs each other Smart Lanes mode per test.
Sampler: 119 map-wide samples recorded, map-wide standing 19 %; capped 2, strided 2, FLOW_TARGET 3, busiest frame 23.8 ms; thru by position, path thru read too.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| cht | sl vs game | 9 | +28.5 | 9/0/0 | 0.004 | 0.012 | 0.004 | -31.0 | +17.5 (9/0) |
| cht | sl vs sl_keeplights | 9 | +29.0 | 9/0/0 | 0.004 | 0.012 | 0.004 | -32.5 | +16.9 (9/0) |
| dia | sl vs game | 6 | +19.4 | 5/1/0 | 0.219 | 0.219 | 0.062 | -18.8 | -1.9 (3/3) |

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| cht | sl vs game | g1#2 | Channel_T | 42.9 / 13.4 | +29.5 | -31 | -47.1 | 85.4 / 67.0 |
| cht | sl vs game | g2#2 | Channel_T | 43.1 / 12.3 | +30.9 | -33 | -50.1 | 84.1 / 63.4 |
| cht | sl vs game | g3#2 | Channel_T | 34.1 / 16.1 | +17.9 | -22 | -27.6 | 85.5 / 68.1 |
| cht | sl vs game | g4#2 | Channel_T | 42.5 / 10.3 | +32.2 | -34 | -63.6 | 83.1 / 64.6 |
| cht | sl vs game | g5#2 | Channel_T | 45.0 / 16.0 | +28.9 | -31 | -37.1 | 80.8 / 67.3 |
| cht | sl vs game | g6#2 | Channel_T | 45.6 / 13.2 | +32.5 | -35 | -48.1 | 83.1 / 64.2 |
| cht | sl vs game | g7#2 | Channel_T | 51.0 / 12.8 | +38.2 | -38 | -51.3 | 83.0 / 66.7 |
| cht | sl vs game | g8#2 | Channel_T | 27.6 / 12.9 | +14.7 | -22 | -40.5 | 74.2 / 65.0 |
| cht | sl vs game | g9#2 | Channel_T | 43.7 / 12.1 | +31.7 | -34 | -52.2 | 88.4 / 63.9 |
| cht | sl vs sl_keeplights | g1#2 | Channel_T | 42.9 / 15.0 | +27.9 | -30 | -34.8 | 85.4 / 68.0 |
| cht | sl vs sl_keeplights | g2#2 | Channel_T | 43.1 / 12.0 | +31.2 | -34 | -48.1 | 84.1 / 65.2 |
| cht | sl vs sl_keeplights | g3#2 | Channel_T | 34.1 / 9.3 | +24.7 | -38 | -73.3 | 85.5 / 56.1 |
| cht | sl vs sl_keeplights | g4#2 | Channel_T | 42.5 / 12.3 | +30.2 | -32 | -48.0 | 83.1 / 71.2 |
| cht | sl vs sl_keeplights | g5#2 | Channel_T | 45.0 / 11.1 | +33.9 | -37 | -52.8 | 80.8 / 63.0 |
| cht | sl vs sl_keeplights | g6#2 | Channel_T | 45.6 / 13.7 | +31.9 | -33 | -39.8 | 83.1 / 70.9 |
| cht | sl vs sl_keeplights | g7#2 | Channel_T | 51.0 / 16.9 | +34.1 | -33 | -31.9 | 83.0 / 68.7 |
| cht | sl vs sl_keeplights | g8#2 | Channel_T | 27.6 / 12.6 | +15.0 | -22 | -41.0 | 74.2 / 65.9 |
| cht | sl vs sl_keeplights | g9#2 | Channel_T | 43.7 / 11.5 | +32.2 | -34 | -50.3 | 88.4 / 66.0 |
| dia | sl vs game | g10#2 | Diamond_S | 59.1 / 32.1 | +27.0 | -26 | -15.6 | 87.7 / 78.3 |
| dia | sl vs game | g11#2 | Diamond_S | 40.9 / 46.2 | -5.3 | +3 | +1.0 | 67.2 / 82.6 |
| dia | sl vs game | g12#2 | Diamond_S | 60.6 / 37.4 | +23.2 | -22 | -12.1 | 70.8 / 83.4 |
| dia | sl vs game | g13#2 | Diamond_S | 62.6 / 29.4 | +33.2 | -26 | -17.9 | 73.5 / 80.8 |
| dia | sl vs game | g14#2 | Diamond_S | 62.0 / 35.9 | +26.1 | -24 | -14.2 | 84.1 / 81.8 |
| dia | sl vs game | g15#2 | Diamond_S | 43.1 / 30.7 | +12.4 | -18 | -15.2 | 97.8 / 85.7 |

Treatment (Smart Lanes lines with zid=): cht: game 9 (applied 0, skipped 9, lights off 0, kept 0, lit at read 9), sl 9 (applied 9, skipped 0, lights off 27, kept 0, lit at read 9), sl_keeplights 9 (applied 9, skipped 0, lights off 0, kept 81, lit at read 9); dia: game 6 (applied 0, skipped 6, lights off 0, kept 0, lit at read 6), sl 6 (applied 6, skipped 0, lights off 24, kept 0, lit at read 6).

Suggested verdict lines (review before adding to the Verdicts table):
- cht, sl vs game: sl better by +28.5 km/h, 9/9 pairs, sign p 0.004 (Holm 0.012): significant.
- cht, sl vs sl_keeplights: sl better by +29.0 km/h, 9/9 pairs, sign p 0.004 (Holm 0.012): significant.
- dia, sl vs game: sl better by +19.4 km/h, 5/6 pairs, sign p 0.219 (Holm 0.219): trend.

### Bench sheet s1: 2026-10-13_0610_session (seed 954486)
Setup: bench_s1@1, map 16384x16384 m, 39 junctions, 132 towns (~400 people each); Smart Lanes game phases, free kerb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 5 screenshots.
Build: summary seed=954486 groups=39 built=39 refused=0 rb4=27/27 drop=12/12 shapes RB4_2L=27/27 Lane_drop_3-2=12/12 game=15/15 sl=15/15 sl_keeplights=9/9 links=132 linked=132 unlinked=0 towns_skipped=0 sets
Entries: entries roundabout=132 crossroads=0 broken=0 joins=396/396
Tests: from the zone lines (the log has no BENCH_TEST lines): sl vs game and sl vs each other Smart Lanes mode per test.
Sampler: 118 map-wide samples recorded, map-wide standing 31 %; capped 8, strided 8, FLOW_TARGET 10, busiest frame 76.4 ms; thru by position, path thru read too.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| rb4 | sl vs game | 9 | +1.5 | 9/0/0 | 0.004 | 0.012 | 0.004 | -4.1 | +16.0 (9/0) |
| rb4 | sl vs sl_keeplights | 9 | -0.2 | 4/5/0 | 1.000 | 1.000 | 0.652 | +0.5 | -0.3 (4/5) |
| drop | sl vs game | 6 | +0.8 | 5/1/0 | 0.219 | 0.438 | 0.312 | -0.1 | +0.4 (3/3) |

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| rb4 | sl vs game | g1 | RB4_2L | 8.8 / 7.3 | +1.5 | -5 | +3.8 | 75.2 / 59.8 |
| rb4 | sl vs game | g2 | RB4_2L | 8.7 / 7.5 | +1.3 | -4 | +6.7 | 75.6 / 59.2 |
| rb4 | sl vs game | g3 | RB4_2L | 8.9 / 7.3 | +1.7 | -6 | +3.0 | 76.7 / 59.6 |
| rb4 | sl vs game | g4 | RB4_2L | 8.6 / 7.3 | +1.3 | -3 | +1.1 | 77.1 / 59.8 |
| rb4 | sl vs game | g5 | RB4_2L | 8.8 / 7.3 | +1.5 | -5 | +2.2 | 75.5 / 59.3 |
| rb4 | sl vs game | g6 | RB4_2L | 9.2 / 7.4 | +1.8 | -5 | +2.4 | 79.0 / 60.0 |
| rb4 | sl vs game | g7 | RB4_2L | 9.1 / 7.4 | +1.7 | -4 | +4.1 | 76.3 / 60.3 |
| rb4 | sl vs game | g8 | RB4_2L | 8.8 / 7.3 | +1.5 | -4 | +4.4 | 76.1 / 63.1 |
| rb4 | sl vs game | g9 | RB4_2L | 8.7 / 7.5 | +1.3 | -3 | +3.1 | 75.4 / 61.9 |
| rb4 | sl vs sl_keeplights | g1 | RB4_2L | 8.8 / 8.5 | +0.3 | -1 | +0.3 | 75.2 / 72.7 |
| rb4 | sl vs sl_keeplights | g2 | RB4_2L | 8.7 / 8.9 | -0.1 | +1 | +4.7 | 75.6 / 76.9 |
| rb4 | sl vs sl_keeplights | g3 | RB4_2L | 8.9 / 10.8 | -1.9 | +2 | +5.2 | 76.7 / 77.7 |
| rb4 | sl vs sl_keeplights | g4 | RB4_2L | 8.6 / 8.9 | -0.3 | -0 | -0.4 | 77.1 / 74.0 |
| rb4 | sl vs sl_keeplights | g5 | RB4_2L | 8.8 / 8.9 | -0.1 | +1 | +0.3 | 75.5 / 83.5 |
| rb4 | sl vs sl_keeplights | g6 | RB4_2L | 9.2 / 8.6 | +0.7 | -2 | -4.4 | 79.0 / 74.2 |
| rb4 | sl vs sl_keeplights | g7 | RB4_2L | 9.1 / 9.0 | +0.1 | +1 | +1.9 | 76.3 / 78.6 |
| rb4 | sl vs sl_keeplights | g8 | RB4_2L | 8.8 / 8.7 | +0.1 | +1 | +2.2 | 76.1 / 75.4 |
| rb4 | sl vs sl_keeplights | g9 | RB4_2L | 8.7 / 8.9 | -0.1 | +1 | +1.2 | 75.4 / 76.8 |
| drop | sl vs game | g10 | Lane_drop_3-2 | 74.1 / 73.8 | +0.3 | +0 | +0.0 | 50.2 / 45.5 |
| drop | sl vs game | g11 | Lane_drop_3-2 | 73.7 / 69.9 | +3.7 | -0 | +0.0 | 45.6 / 51.9 |
| drop | sl vs game | g12 | Lane_drop_3-2 | 74.0 / 72.9 | +1.1 | -0 | +0.0 | 51.5 / 50.6 |
| drop | sl vs game | g13 | Lane_drop_3-2 | 71.7 / 73.4 | -1.7 | -0 | +0.0 | 45.2 / 48.0 |
| drop | sl vs game | g14 | Lane_drop_3-2 | 74.4 / 73.8 | +0.5 | -0 | +0.0 | 49.0 / 42.8 |
| drop | sl vs game | g15 | Lane_drop_3-2 | 74.3 / 73.1 | +1.2 | -0 | +0.0 | 49.1 / 49.2 |

Treatment (Smart Lanes lines with zid=): rb4: game 9 (applied 0, skipped 9, lights off 0, kept 0, lit at read 0), sl 9 (applied 9, skipped 0, lights off 36, kept 0, lit at read 0), sl_keeplights 9 (applied 9, skipped 0, lights off 0, kept 108, lit at read 0); drop: game 6 (applied 0, skipped 6, lights off 0, kept 0, lit at read 0), sl 6 (applied 0, skipped 0, lights off 0, kept 0, lit at read 0) [its Smart Lanes APPLY lines carry no zid=: the sl twins were not checked].

Suggested verdict lines (review before adding to the Verdicts table):
- rb4, sl vs game: sl better by +1.5 km/h, 9/9 pairs, sign p 0.004 (Holm 0.012): significant.
- rb4, sl vs sl_keeplights: sl worse by -0.2 km/h, 4/9 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- drop, sl vs game: sl better by +0.8 km/h, 5/6 pairs, sign p 0.219 (Holm 0.438): trend.

### Run 6: 2026-10-13_0447_top-up-726115 (seed 726115)
Setup: mixed shapes on a 16 km map, 6 sets (2x2 X x2, 3x3 X x2, 3x2 X, T 2x2), three twins `sl` / `game` /
`sl_exitfan`; 69 x 3-lane entry roundabouts (3 lost in set 6: its pair excluded, 5 pairs left); towns exactly 400
people (398 / 400 / 400); rig lane-fan fix; Light phases = Game default, Free kerb turn = Always. Light traffic
(map-wide ~23 % standing, ~30 km/h). 18 game min, 30 samples per twin. `thru` still broken (path elements are
userdata; read 0). Twin positions not balanced (16 km map). No stutter at 4x (user); no houses on the highway rings (user).

| compare | pairs | Δ km/h | W/L | p | Δ standing |
|---|---|---|---|---|---|
| sl vs game | 5 | +6.9 | 4/1 | 0.375 | −9.2 pp |
| sl_exitfan vs sl (the exit fan alone) | 5 | **−2.9** | **0/5** | 0.062 | +3.9 pp |
| sl_exitfan vs game | 5 | +4.0 | 2/3 | 1.0 | −5.3 pp |

Per shape, sl vs game: 2x2 +1.4 (2/0), 3x2 +7.8 (1/0), 3x3 +28.8 (1/0), T 2x2 −5.0 (0/1). Exit fan lost to `sl`
in every pair (2x2 −3.3, 3x2 −5.5, 3x3 −1.0, T −1.5).

### Run 5: 2026-10-13_0356_top-up-779299 (seed 779299)
Setup: mixed shapes, 12 sets (3 each of 2x2 X, 3x3 X, 3x2 X, T 2x2), twins `sl` vs `game`; town entries 90 x
3-lane roundabouts; towns per-town growth to ~400 (got 398/569/1020 min/mean/max); rig lane-fan fix at arm/link
joints; Smart Lanes code of rev 4 before any exit-fan change (`k|s|sf` on 3-lane approaches, `ks|sf` on 2-lane);
Light phases = Game default, Free kerb turn = Always. Not jammed (map-wide ~40-45 % standing, ~18-20 km/h).
17.5 game min, 23 samples per twin after warm-up. Sampler flapped between full and partial sweeps (fixed after
this run started); `thru` read 0 (broken).

| shape | game km/h | sl km/h | Δ km/h | W/L | game standing | sl standing | game queue | sl queue |
|---|---|---|---|---|---|---|---|---|
| 2x2 X | 9.6 | 10.5 | +1.0 | 3/0 | 55 % | 54 % | 76 | 58 |
| 3x2 X | 10.8 | 12.1 | +1.3 | 2/1 | 58 % | 55 % | 70 | 69 |
| 3x3 X | 11.1 | 18.6 | +8.2 | 3/0 | 57 % | 46 % | 83 | 40 |
| T 2x2 | 11.2 | 14.6 | +3.4 | 3/0 | 47 % | 39 % | 36 | 15 |
| all 12 pairs | 10.6 | 13.5 | **+3.5** | **11/1, p = 0.006** | 55 % | 50 % | 66 | 45 |

Smart Lanes zones also held fewer cars (143 vs 177 on average).

### Run 4: 2026-10-13_0205_top-up-61157 (seed 61157)
Setup: 2x2 X only, 6 sets, twins `sl` / `game` / `sl_phases` / `sl_lock`; entries 96 x 3-lane roundabouts; towns
x3 (~940 people); old rig joints (lane to lane). Jammed (map-wide ~62 % standing). 6.5 game min, 8 samples.

| compare | Δ km/h | W/L | p | Δ standing |
|---|---|---|---|---|
| sl vs game | −1.9 | 0/6 | 0.031 | +6.2 pp |
| sl_lock vs game | −1.8 | 1/5 | 0.219 | +7.7 pp (0/6, p = 0.031) |
| sl vs sl_lock (free turn alone) | −0.1 | 2/4 | 0.688 | −1.5 pp |
| sl_phases vs game | −4.8 | 0/6 | 0.031 | +25.2 pp |

Lane audit of this run: `sl` and `game` allow the same movements per lane at a 2x2; Smart Lanes pins each turn to
one exit lane (16 connections vs the game's 24). Queues sat on the arms where turners leave.

### Run 3: 2026-10-13_0118_top-up-148916 (seed 148916)
Setup: 2x2 X only, 6 sets, twins `sl` / `game` / `sl_phases` / `sl_fan`; entries 96 x 2-lane roundabouts; towns x3
(mean 939 people); old rig joints. Jammed after ~5 game min (~65 % standing). 8.5 game min, 12 samples. Report
needs `ARGS='--ignore-reason entry'` (a false "not locked" flag, fixed later).

| compare | Δ km/h | W/L | p | Δ standing |
|---|---|---|---|---|
| sl vs game | −1.6 | 1/5 | 0.219 | +3.4 pp |
| sl_phases vs game | −4.7 | 0/6 | 0.031 | +23.1 pp |
| sl_fan vs game | −6.2 | 0/6 | 0.031 | +25.6 pp |

### Run 2: 2026-10-12_2343_top-up-563524 (seed 563524)
Setup: 2x2 X only, 6 sets, four twins incl. `sl_fan`; town entries crossroads (roundabouts refused); towns x10.
4 game min, 3 samples per twin: pooled only (no per-pair verdict).

| twin | km/h | standing | stand s | queue |
|---|---|---|---|---|
| game | 13.2 | 49 % | 11.6 | 92 |
| sl | 10.7 | 50 % | 7.4 | 87 |
| sl_phases | 6.8 | 73 % | 28.4 | 231 |
| sl_fan | 5.2 | 76 % | 29.8 | 298 |

### Run 1: 2026-10-12_2244_top-up-4951 (seed 4951)
Setup: first Lights showcase, 2x2 X, crossroads entries. 1.5 game min: warm-up only, no comparison. Early look:
`sl_phases` and `sl_fan` about 7-8 km/h and ~72 % standing vs ~15-16 km/h and ~45-48 % for `game` and `sl`.
