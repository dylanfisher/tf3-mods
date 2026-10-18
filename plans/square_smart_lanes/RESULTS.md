Status: current (started 2026-10-13). Running ledger of Smart Lanes traffic-flow results from the Stress Test
Lights showcase. Add every new run at the top of "Runs"; update "Verdicts" when a run changes one.

# Smart Lanes flow results

How a run is made and read: `plans/square_stress_test/SHOWCASE.md` (Lights showcase) and
`plans/square_stress_test/FLOW.md` (traffic log contract). Reproduce any row with
`make flow LOG=<session>` (raw logs in `.cache/logs/`, `make logs-list`).

Twins (zone modes, `mods/square_smart_lanes/content/smart_lanes/sl_zones.lua`):

| twin | lanes | light phases | curb turn |
|---|---|---|---|
| `game` | game default (Smart Lanes leaves it alone) | game | game (waits) |
| `sl` | Smart Lanes | game | the setting (Always in every run here) |
| `sl_lock` | Smart Lanes | game | always locked (waits) |
| `sl_phases` | Smart Lanes | Smart Lanes planner (x4 split) | per the plan |
| `sl_fan` | full fan (every lane to every lane) | Smart Lanes planner | per the plan |
| `sl_phases` (rev 8) | Smart Lanes | axis plan (one phase per road, both directions whole; pedestrian phase between) | per the plan |
| `sl_classic` | Smart Lanes | the pre-rev-8 planner patterns (x4 split / protected / lead-lag) | per the plan |
| `sl_auto` | Smart Lanes | axis plan + automatic re-timing ("Keep timing adjusted") | per the plan |

Columns: km/h = car-weighted mean speed in the zone (junction circle + arm corridors), standing = share of cars
under 0.5 m/s, queue = cars standing >= 5 s. "Δ" = first twin minus second, averaged over pairs; W/L = sets won
/ lost by the first twin (speed); p = two-sided sign test over pairs. With 3 pairs the best possible p is 0.25,
with 6 pairs 0.031.

## Verdicts so far

| question | answer | confidence | evidence |
|---|---|---|---|
| **Automatic timing at city scale** (3 auto grid cities, 243 lit junctions on game phases, vs 3 identical control cities) | **auto cities improved more than their controls in 3 of 3** (km/h change minus control: +4.5, +1.2, +12.7 pp; queues 136 > 68, 173 > 144, 139 > 82 vs controls 110 > 73, 90 > 88, 87 > 95), **despite a timing bug**: every write at the game's 6-phase 3-lane crossroads cut both through phases from 27.1 s to 6-9 s and gave the empty phase 5 26 s (pedestrian floor; fixed offline 2026-10-15, see the run section). Cost mean 0.098 ms/frame at 4x (PASS); frames over 5 ms: person-list snapshot spikes up to 18 ms and a 30 ms burst when 103 junctions decided in the same 30 s (first decisions; needs a per-frame budget). Mostly quiet: 815 of 985 checks "too little traffic", 67 of 243 junctions written | weak (3 pairs; the auto cities' baselines were worse than the controls', so part is regression to the mean). **Run 2 after the fix:** bug gone in game (phase 5 stays 3 s, busy phase 28 s), 21 writes on 16 junctions, auto +12.7 % vs control +11.7 % km/h: no harm, no measurable gain at this load; twin noise as large as the effect; frames max 13.8 ms wall (no burst; the "81 ms person-list spikes" were os.clock CPU time, not wall) | city lights, city lights 2 |
| **Mid-node default (`sl_rmid`) under heavy traffic**, 2-lane ring, 1-lane town street arms, 2400 people per ring | **keep it**: best in all 3 mixes, no gridlock on any twin (30 game min): 88.5 cars/min vs game 65.4 (+23.1, 3/0), 12.2 vs 7.7 km/h, standing 26 vs 46 %, queue ~0.3 vs 9-21; ring lanes used ~55/45 (game / matched: one lane). Matched / turbo = game here (one-lane exits). `sl_rmid2` locked because two entry lanes per arm fill both ring lanes; one entry lane per arm doesn't | trend (3 sets, p = 0.25) but every measure agrees; decision 2026-10-15: default unchanged | bench s6 |
| **2-lane ring, 2-lane arms: matched vs turbo (today's default) vs game** | **matched best in all 3 mixes**: 89.1 cars/min vs turbo 73.8, game 58.6 (+15.3 vs turbo, 3/0; +30.5 vs game, 3/0); straight mix 91.9 vs 70.7, standing 19 vs 33 %. Lane use: turbo puts 79-85 % of ring cars in the inner lane (the user's "everyone in one lane"), matched 45-55 % / 49-55 % | trend (3 sets, one run, p = 0.25). **Decision 2026-10-15 (user): matched is the default on 2-lane rings whose exits have 2+ lanes** (rev 8, PLAN.md "Default: matched lanes on 2-lane rings with wide exits"; turbo stays on 3/4-lane rings) | bench s5 |
| **Mid nodes with crossing lane changes under heavy traffic (`sl_rmid2`)** | **gridlock in all 3 sets**: 30.3 cars/min, 84 % standing, 150-265 queued; screenshots (s5 shot 3, user screenshot "Ring mid 2") show both ring lanes full and nothing leaving. Inferred cause: outward and inward lane changes cross at the same mid node and nobody gives way once both lanes are full. Rejected; the shipped `sl_rmid` default (2-lane rings, 1-lane exits) uses the same crossing changes and needs a saturation test (prepared: bench Sheet 6, plans/square_stress_test/TESTING.md 6Y3) | strong for the rejection (3/3, every measure) | bench s5 |
| 4-lane ring, 3-lane arms: turbo vs turbo with the inner lane fed (`sl_rturbo_in`) vs spread vs game | **turbo stays best** (29.8 km/h, 100.6 cars/min vs game 11.2 / 69.6; 3/0). Feeding o4 works (8-13 % of ring cars) but adds nothing (−4.1 cars/min vs turbo) and both inner-lane variants jammed in the even mix (68-70 % standing, ~180-200 queued vs turbo 52 %, 72) | trend (3 sets); keep turbo | bench s5 |
| **Light plans: axis (rev 8) vs game default vs classic**, lit 2x2 and 3x3 X, busy towns | **axis best**: +23 % / +26 % cars/min vs game (2x2 / 3x3), 6 of 6 sets; 3x3 also halves the queues (61 vs 117) and 17 vs 10 km/h. **Classic worse than game**: −16 % / −11 %, 6 of 6 (the player's "backed up across town", reproduced) | strong (p = 0.031 both) | light plans A/B run 1 |
| ... axis vs game again, balanced + unbalanced towns | axis +14-39 % cars/min per group, speed 6 of 6 sets (p = 0.031) | strong (two runs) | light plans A/B run 2 |
| **Automatic re-timing (`sl_auto`, settled) vs fixed axis** | **better on cars/min in 6 of 6 sets** (+4.2/min mean): balanced +0-2 %, unbalanced +5-7 %; 3x3 unbalanced 46 vs 23 km/h, standing 20 vs 35 %, queue 10 vs 31. But on balanced saturated junctions it stretched the cycle to 112-120 s and the approach queues grew (2x2: 183 vs 144). vs game: +26.1 cars/min, 6 of 6 | strong on throughput (p = 0.031), queues mixed; tune: no cycle stretch when every road is equally saturated, damp flip-flops (g2v 62 > 82 > 62 > 50 s); both built offline 2026-10-15 (RETIME_PLAN.md "Cycle rule v3 and damping"; measuring since redesigned as queue snapshots, "Step B v4"; next run: TESTING.md "KA v4") | light plans A/B run 2 |
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
| Smart Lanes vs game, 4-lane roundabout (busy) | more cars through: +22.7/min, 6 of 6, but +10 pp standing | trend (partial run) | bench micro |
| Smart Lanes vs game, 3-lane highway ring (busy) | **worse**: −13.2 cars/min, 0 of 6, +12 pp standing | trend (partial run); ring layout variants to be benched | bench micro |
| Ring layout on 3+ lane rings: turbo vs matched vs spiral / spread / outer exit / two exits | **turbo best on 4-lane rings** (~98-102 vs game 82, matched 80 cars/min, both sets); spiral worst (57 / 42 cars/min on 4- / 3-lane); outer-exit-only near the bottom; 2-lane: all Smart Lanes layouts ≈ and above game. Explains the micro v1 3-lane loss (those twins were matched). Default: turbo on the whole ring wherever it qualifies | trend (partial run, 1-2 sets per ring) | bench micro v2 |
| 2-lane ring, 1-lane town street arms: Smart Lanes default (matched) vs game | **no gain, maybe worse**: −0.0 km/h (s4 v2), −2.1 km/h and −8.6 cars/min (s4 v3, mid-node ring). Every exit has one lane, so the default falls back to matched lanes (`turbo_reason=narrow_exit`) and the inner lane is never entered or left at a junction | trend (1 pair per run, 2 runs, same sign); don't ship matched as the default here | bench s4 v2, v3 |
| ... spiral (`sl_rspiral`) on that ring | **better than the default** in both runs: +0.7 km/h / +5.1 cars/min (v2), +1.9 km/h / +13.2 cars/min (v3); vs game +0.7 km/h (v2), −0.2 km/h but +4.6 cars/min (v3) | trend (2 pairs, both won vs sl); candidate default for 2-lane rings whose exits all have one lane | bench s4 v2, v3 |
| ... split spiral (`sl_rsplit`: ring with a plain mid node between arms, entry into the outer lane only, outer → inner change at the mid node) | **best of four**: 12.4 km/h vs game 10.2, spiral 10.0, default 8.1; standing 31 % vs 39 / 37 / 45 %; **85.9 cars/min vs 71.4 game** (+20 %), 76.0 spiral. The game accepted the mid-node lane change (`VERIFY same=8 nodes=8`); the Crossing Tool can't pick those nodes (docs/findings/roads.md) | trend (1 pair); needs mid nodes (square_roundabouts dev option only) and tool support before shipping; s4 v4 adds 3- and 4-lane rings and a no-lane-change-at-arms layout | bench s4 v3 |
| Mid-node rings, 2 / 3 / 4 lanes (s4 v4, every twin on the mid-node ring, so **no plain-ring baseline**) | 2-lane: every Smart Lanes layout beat game (split 12.4, mid-only 12.2 and the most cars/min 87.8, sl = split 11.2, spiral 11.0, game 9.3 km/h; sl and split had the same lanes and differ 1.2 km/h: the noise level of one pair). 3-lane: **split 16.2 km/h / 96.7 cars/min vs game 3.8 / 54.0**, spiral 10.7; turbo (sl default) 1.6 and mid-only 2.6 jammed. 4-lane (2 mid nodes per quarter): every twin jammed (spiral best 5.8, game 1.7 km/h): the nodes themselves likely hurt (short ring segments). Mid-only's crossing lane changes were kept by the game (VERIFY 8 / 8 / 12) | trend (1 pair each); baseline missing: s4 v5 adds plain-ring twins | bench s4 v4 |
| **Do mid nodes help? Plain vs mid-node rings, real baseline** (s4 v5) | **2-lane (1-lane town arms): yes.** vs game on the plain ring (8.0 km/h, 62.5 cars/min): mid-only 12.4 / 91.8, split 11.4 / 84.7 (+3.5 km/h, +36 % cars), even game on the mid ring 9.0 / 72.2; Smart Lanes' plain-ring spiral 8.4 / 67.4. **3- and 4-lane: no, they hurt.** game@mid vs game@plain −9.0 km/h (3-lane), −7.4 (4-lane), cars/min −56 / −42; split@mid below game@plain on both. Turbo on the plain ring is the best wide-ring layout: 3-lane 13.2 vs game 11.2, **4-lane 23.3 vs 8.8 km/h, 102.7 vs 74.6 cars/min**. The 130 m shots: the 4-lane mid ring (grown from 10 to 20 m for its 2 nodes per quarter) is packed in its outer lanes with the inner lanes empty, the plain ring flows. Decision: Nodes between arms on 2-lane rings only (as built); split spiral the 2-lane default; turbo stays on 3/4-lane | trend (1 pair each, same direction as v3 / v4 on 2 lanes) | bench s4 v5 |
| ... **decision 2026-10-14: sl_rmid the 2-lane default** (one-lane exits; Smart Lanes adds the mid nodes itself) | user: no lane change at the arms (the split spiral's inner → outer change merged where entries join); mid-only vs split: s4 v4 12.2 vs 12.4 km/h, 87.8 vs 80.3 cars/min; s4 v5 12.4 vs 11.4 km/h, 91.8 vs 84.7 cars/min | trend (2 pairs, cars/min both for mid-only) | bench s4 v4, v5 |
| Free curb turn (Always) vs locked | **no clear effect**: jammed 2x2 −0.1 km/h (2/4, run 4); light traffic lit T +2.7 (5/4) and lit X +5.3 (2/1), pooled 7 of 12, throughput 8 of 12 slightly up. Harmless; keep Always | medium (no test significant) | run 4, bench s3 |
| Smart Lanes phase planner (`sl_phases`) vs game phases | **much worse**: −4.7 to −4.8 km/h, +23-25 pp standing, every set in every run. Cause: x4 split cycle gives each approach ~21 s of 92 s vs the game's ~24 s of 71 s | strong (4 runs) | runs 1-4 |
| Full fan (`sl_fan`) | **worst**: −6.2 km/h vs game, worse than `sl_phases` too | strong (3 runs); dropped from the showcase | runs 1-3 |

Known confound (runs 5-6, found 2026-10-13 by the bench design): inside the Smart Lanes twins' zones, Smart Lanes
also rewrote the 2-lane arm / 3-lane link joint as a lane drop (`APPLY kind=drop`, 26 in run 6, one per 2-lane arm
end), while the game twins kept the rig's own joint. So the 2-lane shapes' sl vs game numbers include that joint;
3x3 X (no such joint) shows the largest gain, so the verdict likely stands. The bench (plans/square_stress_test/
BENCH.md) keeps links at the arm's lane count so no lane change happens inside a zone.

Open questions:
- Per-shape significance: needs 6+ pairs per shape (a single-shape run, or more sets).
- Free curb turn without a jam, and at 3-lane / T junctions (untested; run 4 was 2x2 only and saturated).
- `sl_exitfan` lost in run 6 (5 of 5 pairs); one more run would make it significant. Likely cause: the two turns
  that share one exit lane in the same phase merge without giving way.
- Throughput (cars through per minute): the `thru` count read 0 in run 5 (being fixed); speed / standing are the
  only measures so far. Under saturation they mostly measure queues.

## Runs

### City lights at scale, run 2 (after the Re-time fix): 2026-10-15_1950_city-lights-2-778824 (seed 778824)
Setup as run 1 (bench_city@1, 6 grid cities ~3000 people, 243 enrolled, game phases, Free curb turn Always), new Smart Lanes code (`AUTORETIME op=config every_factor=1 params=read`; Re-time fix, early wake, decision budget, Yes/No toggle). `BENCH_DONE ... ok=yes samples=649 problems=0`. The game clock ran ~16x real time at "4x" (15 game min baseline in ~1 real min; whole run 13 real min).

| city | role | written | km/h before / after | change | standing % before / after | queue before / after |
|---|---|---|---|---|---|---|
| cityg1v | auto | 2 | 27.7 / 29.4 | +6 % | 27 / 24 | 80.0 / 70.7 |
| cityg1b | control | 0 | 22.1 / 27.6 | +25 % | 41 / 29 | 178.2 / 95.8 |
| cityg2v | auto | 6 | 24.0 / 27.4 | +14 % | 36 / 29 | 143.9 / 100.5 |
| cityg2b | control | 0 | 30.6 / 31.4 | +3 % | 21 / 21 | 43.8 / 47.0 |
| cityg3v | auto | 8 | 22.6 / 26.6 | +18 % | 40 / 32 | 176.9 / 119.6 |
| cityg3b | control | 0 | 24.2 / 25.9 | +7 % | 36 / 33 | 152.0 / 135.0 |

- **Bug fixed in game:** every write keeps phase 5 at 3 s and the busy through phase at 28 s (e.g. 27.1/6/27.1/6/3/9 > 8/6/28/6/3/9); the light side road drops to 6-11 s (queue ~0.1). No 6-9 s through greens.
- Auto minus control (km/h %): −19.0, +11.7, +10.8 pp. **Not a measure of automatic timing:** only 16 of 243 junctions were written (2 in cityg1v), and the twins' baselines differ as much as the effect (queues 80 vs 178, 144 vs 44 on identical layouts): the pairs measure demand noise. Mean change auto +12.7 % vs control +11.7 %: no harm, no measurable gain at this load.
- Checks 776: quiet 623, fits 132, write 21 (run 1: 67 writes; the fix makes it keep the game greens at light even traffic). Writes 0.23 per game min.
- Early wakes 51: fits_shift 42, quiet_rise 6, fits_grow 3, against 21 writes: fits_shift is too sensitive at 1-2 standing cars (needs a minimum queue).
- Cost: mean 0.122 ms/frame (PASS); SQPERF window max 13.8 ms (run 1: 30.1 ms, the decision burst is gone); without person-list spikes worst 7.3 ms. Snapshot frames: `max_frame_ms` 49.2 and 81.5 ms in two snapshots, **but timed with os.clock (CPU time over all game threads on macOS, 3-6x too high)**: the same windows' wall-clock SQPERF max was 12.8 / 13.8 ms, and a full 12.5k-person list fetch took ~1.9 ms wall (docs/findings/gui.md; the runtime uses a wall clock since 2026-10-15, `fetch_ms=` on the snapshot line). At ~16x a 243-junction snapshot sometimes took longer (90-138 game s) than its 120 s interval and the due-decision backlog reached 64-225 (drained to 0 at times).
- Follow-ups: minimum queue for fits_shift; find what owns the remaining 11-14 ms wall frames (next run: wall-clock `max_frame_ms` / `fetch_ms`); busier cities, and a longer baseline or swapped roles so twin noise cancels.

### City lights at scale: 2026-10-15_0700_bench-s6-midnode-city-lights-872734 (seed 872734)
Setup: bench_city@1, Blank Slate 16 km, 6 large grid cities (~3000 people each), 81 lit inner crossings each (486; game phases, Light phases = Game default), 3 auto cities (243 junctions enrolled by `SmartLanes.auto op=add` after a 15 game min baseline) + 3 control cities; 90 game min after the enroll at 4x; `BENCH_DONE sheet=city ... ok=yes samples=648 problems=0`; 6 shots. Report: `make flow LOG=last-bench`, section "Auto lights at scale".

| city | role | written | km/h before / after | change | standing % before / after | queue before / after |
|---|---|---|---|---|---|---|
| cityg1v | auto | 18 | 24.8 / 29.4 | +19 % | 34 / 24 | 136.3 / 68.3 |
| cityg1b | control | 0 | 26.0 / 29.6 | +14 % | 31 / 24 | 110.3 / 72.6 |
| cityg2v | auto | 25 | 23.5 / 25.1 | +7 % | 37 / 34 | 173.0 / 144.3 |
| cityg2b | control | 0 | 26.6 / 28.1 | +6 % | 29 / 27 | 90.0 / 88.4 |
| cityg3v | auto | 24 | 25.2 / 28.9 | +15 % | 34 / 25 | 138.7 / 81.9 |
| cityg3b | control | 0 | 28.0 / 28.5 | +2 % | 27 / 28 | 86.9 / 94.6 |

- Auto minus control (km/h %): +4.5, +1.2, +12.7 pp (3 of 3). The auto cities started worse (queues 136-173 vs 87-110 on identical layouts), so part of their gain is regression to the mean.
- Cost (`SQPERF ctx=bg`): before 0.007 ms/frame, after mean 0.098 ms/frame (PASS < 1.5). 15 windows with a frame over 5 ms: 12 person-list snapshot spikes (45 snapshots, longest 18.3 ms, busy 658 ms each spread over frames), 3 others: 30.1 / 29.2 ms at 07:34:03-07:34:33 when the first decisions came due together (103 `op=plan`, 28 writes in that 30 s; frames dropped to ~20/s), 8.2 ms at the end. Criterion "no frame over 5 ms": FAIL.
- Writes 67 (0.75 per game min; 20 / 26 in the first two 10-min windows after the 16 min wait, then 2, 11, 0, 0, 0, 8); 67 of 243 junctions written. Checks 985: quiet 815, fits 90, write 80; "fits by 50 % / 80 %" not reached because quiet junctions never report fits (the metric should count quiet as settled).
- **Bug** (every write): game 6-phase 3-lane crossroads, old greens 27.1/6/27.1/6/3/9 > new 6/6/9/6/26/6 (or 7/6/7/6, 9/6/6/6), whatever the load (e.g. load 1:11, 3:382.5 still gave phase 3 9 s). Phase 5 (no traffic, game 3 s) gets ~26 s, the pedestrian floor of a 3-lane crossing; cycle_reason=min squeezes the through phases to their floors. Cause found 2026-10-15: Free curb turn Always unlocks the curb turns in all six game phases, so the all-red and pedestrian phases counted as vehicle phases and phase 5's crosswalks got the 25.5 s floor of a 6-lane crossing; manual Re-time had it too (node 9594: 16/6/60/6/26/6). Fixed offline in sl_retime.lua (always-green connections ignored for phase kinds and queues, idle phases capped at their current seconds, loaded phases keep the game green when the cycle shrinks); the logged cases now give fits or 6-10/6/28/6/3/9. Not yet run in game.
- Follow-ups: per-frame budget for decisions due together; early wake when a quiet junction gets busy; rerun with busier cities after the fix, and a second run with Light phases = Smart Lanes.

### Bench sheet s6: 2026-10-15_0700_bench-s6-midnode-671214 (seed 671214)
Setup: bench_s6@1, map 16384x16384 m, 12 junctions, 48 towns (~600 people each); Smart Lanes game phases, free kerb turn always, no lights at roundabouts and ramps on; record 30 game min at 2x, every 10 game s; run complete; 4 screenshots.
Build: summary seed=671214 groups=12 built=12 refused=0 hm2=12/12 game=3/3 sl=3/3 sl_rmatch=3/3 sl_rturbo=3/3 links=48 linked=48 unlinked=0 towns_skipped=0 sets_mismatch=0 minutes=2.5
Entries: entries roundabout=48 crossroads=0 broken=0 joins=144/144
Sampler: 179 map-wide samples recorded, map-wide standing 55 % (SATURATED: speed measures queues, use thru); capped 11, strided 11, FLOW_TARGET 3, busiest frame 20.6 ms (phase scan); thru by position.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| hm2 | sl vs game | 3 | +4.5 | 3/0/0 | 0.250 | 1.000 | 0.250 | -20.3 | +23.1 (3/0) |
| hm2 | sl_rmatch vs game | 3 | -0.0 | 2/1/0 | 1.000 | 1.000 | 1.000 | -0.3 | -0.4 (2/1) |
| hm2 | sl_rturbo vs game | 3 | -0.1 | 0/3/0 | 0.250 | 1.000 | 0.250 | +0.1 | -2.1 (1/2) |
| hm2 | sl vs sl_rmatch | 3 | +4.5 | 3/0/0 | 0.250 | 1.000 | 0.250 | -20.0 | +23.5 (3/0) |
| hm2 | sl_rmatch vs sl_rturbo (identical by design: expected tie) | 3 | +0.1 | 2/1/0 | 1.000 | 1.000 | 0.750 | -0.4 | +1.7 (3/0) |

Ranking, hm2 (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl | 3 | 12.2 | +4.5 | 26 | 88.5 |
| 2 | game | 3 | 7.7 | +0.0 | 46 | 65.4 |
| 3 | sl_rmatch | 3 | 7.7 | -0.0 | 46 | 65.0 |
| 4 | sl_rturbo | 3 | 7.6 | -0.1 | 46 | 63.3 |

## Ring lane use

Bench sheets 5 and 6 (BENCH.md "Sheet 5", "Sheet 6"): per ring (test) and traffic mix (`mix=` of the zone lines: even = four equal towns, straight = the N and S towns large, adjacent = the N and E towns large), every mode's matched twins pooled over the recorded window (after the warm-up). thru/min = cars through per game minute; queue per arm = queued cars on the inbound side (`q_in`); lane use = car samples on the ring's edges by lane, outer lane (o1) first (`RINGLANE`, clustered by distance from the centre); turning mix = arms passed from entry to exit per driver, each once (`RINGMIX`: 1st exit .. U-turn; none = no entry and exit read).

| ring | mix | mode | sets | samples | thru/min | km/h | standing % | queue | queue per arm (inbound) | lane use | turning mix |
|---|---|---|---|---|---|---|---|---|---|---|---|
| hm2 | even | game | 1 | 179 | 62.2 | 7.6 | 46 | 9.5 | N 1.5, E 1.7, S 2.4, W 2.4 | o1 100 % (21.0 m) | 1st 34 %, 2nd 31 %, 3rd 35 %, U 0 % (n 1092, none 0 %) |
| hm2 | even | sl | 1 | 179 | 97.9 | 11.0 | 26 | 0.2 | N 0.0, E 0.0, S 0.1, W 0.1 | o1 55 % (21.0 m), o2 45 % (17.0 m) | 1st 36 %, 2nd 33 %, 3rd 31 %, U 0 % (n 1191, none 0 %) |
| hm2 | even | sl_rturbo | 1 | 179 | 62.2 | 7.6 | 46 | 8.7 | N 1.6, E 1.4, S 2.6, W 1.8 | o1 100 % (21.0 m) | 1st 37 %, 2nd 32 %, 3rd 31 %, U 0 % (n 1047, none 0 %) |
| hm2 | even | sl_rmatch | 1 | 179 | 63.5 | 7.7 | 45 | 7.3 | N 1.7, E 1.6, S 1.9, W 1.1 | o1 100 % (21.0 m) | 1st 39 %, 2nd 31 %, 3rd 30 %, U 0 % (n 1076, none 0 %) |
| hm2 | straight | game | 1 | 179 | 70.2 | 7.9 | 46 | 16.5 | N 0.3, E 7.8, S 0.4, W 5.7 | o1 100 % (21.0 m) | 1st 30 %, 2nd 42 %, 3rd 28 %, U 0 % (n 1060, none 3 %) |
| hm2 | straight | sl | 1 | 179 | 86.4 | 14.0 | 24 | 0.2 | N 0.0, E 0.0, S 0.0, W 0.0 | o1 56 % (21.0 m), o2 44 % (17.0 m) | 1st 28 %, 2nd 49 %, 3rd 24 %, U 0 % (n 972, none 0 %) |
| hm2 | straight | sl_rturbo | 1 | 179 | 64.6 | 7.7 | 46 | 14.3 | N 0.6, E 5.5, S 0.2, W 5.9 | o1 100 % (21.0 m) | 1st 29 %, 2nd 45 %, 3rd 25 %, U 0 % (n 932, none 0 %) |
| hm2 | straight | sl_rmatch | 1 | 179 | 66.2 | 7.9 | 46 | 14.2 | N 0.5, E 5.2, S 0.4, W 5.9 | o1 100 % (21.0 m) | 1st 30 %, 2nd 45 %, 3rd 25 %, U 0 % (n 959, none 1 %) |
| hm2 | adjacent | game | 1 | 179 | 63.9 | 7.6 | 47 | 20.9 | N 0.1, E 0.2, S 10.4, W 7.3 | o1 100 % (21.0 m) | 1st 41 %, 2nd 24 %, 3rd 36 %, U 0 % (n 1066, none 0 %) |
| hm2 | adjacent | sl | 1 | 179 | 81.3 | 11.5 | 29 | 0.4 | N 0.2, E 0.0, S 0.0, W 0.1 | o1 55 % (21.0 m), o2 45 % (17.0 m) | 1st 40 %, 2nd 24 %, 3rd 36 %, U 0 % (n 1091, none 0 %) |
| hm2 | adjacent | sl_rturbo | 1 | 179 | 63.0 | 7.6 | 47 | 24.8 | N 0.1, E 0.4, S 11.3, W 9.8 | o1 100 % (21.0 m) | 1st 41 %, 2nd 23 %, 3rd 36 %, U 0 % (n 949, none 0 %) |
| hm2 | adjacent | sl_rmatch | 1 | 179 | 65.3 | 7.5 | 47 | 25.6 | N 0.3, E 0.3, S 11.1, W 10.4 | o1 100 % (21.0 m) | 1st 38 %, 2nd 26 %, 3rd 35 %, U 0 % (n 1112, none 1 %) |

Gridlock per twin (2 game min windows of the recorded samples; locked = standing >= 80 % and thru/min <= 25 % of the best window of any twin of its set; gridlock = the last 3 windows locked):

| ring | mix | twin | mode | windows | locked | last window standing % | last window thru/min | set best thru/min | gridlock |
|---|---|---|---|---|---|---|---|---|---|
| hm2 | even | s6g1b | game | 15 | 0 | 46 | 62.0 | 103.5 | no |
| hm2 | even | s6g1a | sl | 15 | 0 | 24 | 100.5 | 103.5 | no |
| hm2 | even | s6g1h | sl_rturbo | 15 | 0 | 45 | 64.0 | 103.5 | no |
| hm2 | even | s6g1i | sl_rmatch | 15 | 0 | 46 | 60.5 | 103.5 | no |
| hm2 | straight | s6g2b | game | 15 | 0 | 49 | 60.5 | 99.6 | no |
| hm2 | straight | s6g2a | sl | 15 | 0 | 18 | 88.5 | 99.6 | no |
| hm2 | straight | s6g2h | sl_rturbo | 15 | 0 | 43 | 65.0 | 99.6 | no |
| hm2 | straight | s6g2i | sl_rmatch | 15 | 0 | 46 | 64.5 | 99.6 | no |
| hm2 | adjacent | s6g3b | game | 15 | 0 | 44 | 64.5 | 86.9 | no |
| hm2 | adjacent | s6g3a | sl | 15 | 0 | 29 | 86.5 | 86.9 | no |
| hm2 | adjacent | s6g3h | sl_rturbo | 15 | 0 | 48 | 61.0 | 86.9 | no |
| hm2 | adjacent | s6g3i | sl_rmatch | 15 | 0 | 47 | 61.0 | 86.9 | no |

Turning mix per twin (`RINGMIX`, recorded window; drivers counted once):

| ring | mix | twin | mode | n | 1st | 2nd | 3rd | U-turn | none |
|---|---|---|---|---|---|---|---|---|---|
| hm2 | even | s6g1a | sl | 1191 | 428 | 390 | 373 | 0 | 0 |
| hm2 | even | s6g1b | game | 1092 | 370 | 337 | 385 | 0 | 0 |
| hm2 | even | s6g1h | sl_rturbo | 1047 | 385 | 337 | 325 | 0 | 0 |
| hm2 | even | s6g1i | sl_rmatch | 1076 | 417 | 334 | 325 | 0 | 0 |
| hm2 | straight | s6g2a | sl | 972 | 270 | 471 | 230 | 0 | 1 |
| hm2 | straight | s6g2b | game | 1060 | 308 | 437 | 287 | 0 | 28 |
| hm2 | straight | s6g2h | sl_rturbo | 932 | 272 | 421 | 237 | 0 | 2 |
| hm2 | straight | s6g2i | sl_rmatch | 959 | 285 | 425 | 243 | 0 | 6 |
| hm2 | adjacent | s6g3a | sl | 1091 | 433 | 264 | 394 | 0 | 0 |
| hm2 | adjacent | s6g3b | game | 1066 | 431 | 251 | 381 | 0 | 3 |
| hm2 | adjacent | s6g3h | sl_rturbo | 949 | 391 | 216 | 342 | 0 | 0 |
| hm2 | adjacent | s6g3i | sl_rmatch | 1112 | 425 | 292 | 387 | 0 | 8 |

- **hm2 even**: sl best by thru/min (97.9). sl: +57 % thru/min, +3.3 km/h, standing -20 pp vs game; +57 % thru/min, +3.4 km/h, standing -20 pp vs sl_rturbo. sl_rmatch: +2 % thru/min, +0.1 km/h, standing -1 pp vs game; +2 % thru/min, +0.1 km/h, standing -1 pp vs sl_rturbo. sl_rturbo: +0 % thru/min, -0.0 km/h, standing -0 pp vs game.
- **hm2 straight**: sl best by thru/min (86.4). sl: +23 % thru/min, +6.1 km/h, standing -23 pp vs game; +34 % thru/min, +6.3 km/h, standing -23 pp vs sl_rturbo. sl_rmatch: -6 % thru/min, +0.0 km/h, standing -1 pp vs game; +2 % thru/min, +0.2 km/h, standing -0 pp vs sl_rturbo. sl_rturbo: -8 % thru/min, -0.2 km/h, standing -0 pp vs game.
- **hm2 adjacent**: sl best by thru/min (81.3). sl: +27 % thru/min, +3.9 km/h, standing -18 pp vs game; +29 % thru/min, +3.9 km/h, standing -18 pp vs sl_rturbo. sl_rmatch: +2 % thru/min, -0.1 km/h, standing +0 pp vs game; +4 % thru/min, -0.1 km/h, standing -0 pp vs sl_rturbo. sl_rturbo: -1 % thru/min, -0.0 km/h, standing +0 pp vs game.

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| hm2 | sl vs game | s6g1 | RB_2L_town | 11.0 / 7.6 | +3.3 | -20 | -9.3 | 97.9 / 62.2 |
| hm2 | sl vs game | s6g2 | RB_2L_town | 14.0 / 7.9 | +6.1 | -23 | -16.2 | 86.4 / 70.2 |
| hm2 | sl vs game | s6g3 | RB_2L_town | 11.5 / 7.6 | +3.9 | -18 | -20.5 | 81.3 / 63.9 |
| hm2 | sl_rmatch vs game | s6g1 | RB_2L_town | 7.7 / 7.6 | +0.1 | -1 | -2.2 | 63.5 / 62.2 |
| hm2 | sl_rmatch vs game | s6g2 | RB_2L_town | 7.9 / 7.9 | +0.0 | -1 | -2.3 | 66.2 / 70.2 |
| hm2 | sl_rmatch vs game | s6g3 | RB_2L_town | 7.5 / 7.6 | -0.1 | +0 | +4.7 | 65.3 / 63.9 |
| hm2 | sl_rturbo vs game | s6g1 | RB_2L_town | 7.6 / 7.6 | -0.0 | -0 | -0.8 | 62.2 / 62.2 |
| hm2 | sl_rturbo vs game | s6g2 | RB_2L_town | 7.7 / 7.9 | -0.2 | -0 | -2.2 | 64.6 / 70.2 |
| hm2 | sl_rturbo vs game | s6g3 | RB_2L_town | 7.6 / 7.6 | -0.0 | +0 | +3.8 | 63.0 / 63.9 |
| hm2 | sl vs sl_rmatch | s6g1 | RB_2L_town | 11.0 / 7.7 | +3.3 | -19 | -7.1 | 97.9 / 63.5 |
| hm2 | sl vs sl_rmatch | s6g2 | RB_2L_town | 14.0 / 7.9 | +6.1 | -22 | -14.0 | 86.4 / 66.2 |
| hm2 | sl vs sl_rmatch | s6g3 | RB_2L_town | 11.5 / 7.5 | +4.0 | -18 | -25.2 | 81.3 / 65.3 |
| hm2 | sl_rmatch vs sl_rturbo | s6g1 | RB_2L_town | 7.7 / 7.6 | +0.1 | -1 | -1.4 | 63.5 / 62.2 |
| hm2 | sl_rmatch vs sl_rturbo | s6g2 | RB_2L_town | 7.9 / 7.7 | +0.2 | -0 | -0.1 | 66.2 / 64.6 |
| hm2 | sl_rmatch vs sl_rturbo | s6g3 | RB_2L_town | 7.5 / 7.6 | -0.1 | -0 | +0.9 | 65.3 / 63.0 |

Treatment (Smart Lanes lines with zid=): hm2: game 3 (applied 0, unchanged 0, skipped 3, lights off 0, kept 0, lit at read 0), sl 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0), sl_rmatch 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0), sl_rturbo 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0).

Mode check, hm2: s6g1a layout=sl_rmid default=one_lane_exits split nodes_added=4 mids=4; s6g1h turbo=false (matched lanes: every exit one lane); s6g2a layout=sl_rmid default=one_lane_exits split nodes_added=4 mids=4; s6g2h turbo=false (matched lanes: every exit one lane); s6g3a layout=sl_rmid default=one_lane_exits split nodes_added=4 mids=4; s6g3h turbo=false (matched lanes: every exit one lane).

Suggested verdict lines (review before adding to the Verdicts table):
- hm2, sl vs game: sl better by +4.5 km/h, 3/3 pairs, sign p 0.250 (Holm 1.000): trend.
- hm2, sl_rmatch vs game: sl_rmatch worse by -0.0 km/h, 2/3 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- hm2, sl_rturbo vs game: sl_rturbo worse by -0.1 km/h, 0/3 pairs, sign p 0.250 (Holm 1.000): trend.
- hm2, sl vs sl_rmatch: sl better by +4.5 km/h, 3/3 pairs, sign p 0.250 (Holm 1.000): trend.
- hm2, sl_rmatch vs sl_rturbo: identical by design (expected tie); measured +0.1 km/h, 2/1/0.

### Bench sheet s5: 2026-10-15_0602_bench-s5-ring-34019 (seed 34019)
Setup: bench_s5@1, map 16384x16384 m, 24 junctions, 96 towns (~350 people each); Smart Lanes game phases, free kerb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 8 screenshots.
Build: summary seed=34019 groups=24 built=24 refused=0 lu2=12/12 lu4=12/12 shapes RB4_2L=12/12 RB_4-lane=12/12 game=6/6 sl_rturbo=6/6 sl_rmid2=3/3 sl_rmatch=3/3 sl_rturbo_in=3/3 sl_rspread=3/3 links=96 linke
Entries: entries roundabout=96 crossroads=0 broken=0 joins=288/288
Sampler: 120 map-wide samples recorded, map-wide standing 39 %; capped 0, strided 0, FLOW_TARGET 0, busiest frame 18.3 ms (phase scan); thru by position.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| lu2 | sl_rturbo vs game | 3 | +3.5 | 3/0/0 | 0.250 | 1.000 | 0.250 | -4.9 | +15.2 (3/0) |
| lu2 | sl_rmid2 vs game | 3 | -6.3 | 0/3/0 | 0.250 | 1.000 | 0.250 | +40.2 | -28.3 (0/3) |
| lu2 | sl_rmatch vs game | 3 | +6.1 | 3/0/0 | 0.250 | 1.000 | 0.250 | -16.2 | +30.5 (3/0) |
| lu2 | sl_rmid2 vs sl_rturbo | 3 | -9.7 | 0/3/0 | 0.250 | 1.000 | 0.250 | +45.1 | -43.5 (0/3) |
| lu2 | sl_rmatch vs sl_rturbo | 3 | +2.7 | 3/0/0 | 0.250 | 1.000 | 0.250 | -11.2 | +15.3 (3/0) |
| lu4 | sl_rturbo vs game | 3 | +18.6 | 3/0/0 | 0.250 | 1.000 | 0.250 | -11.4 | +31.1 (3/0) |
| lu4 | sl_rturbo_in vs game | 3 | +9.0 | 2/1/0 | 1.000 | 1.000 | 0.500 | +1.2 | +27.0 (2/1) |
| lu4 | sl_rspread vs game | 3 | +6.6 | 1/2/0 | 1.000 | 1.000 | 1.000 | +6.5 | +26.6 (2/1) |
| lu4 | sl_rturbo_in vs sl_rturbo | 3 | -9.6 | 0/3/0 | 0.250 | 1.000 | 0.250 | +12.6 | -4.1 (2/1) |
| lu4 | sl_rspread vs sl_rturbo | 3 | -12.0 | 0/3/0 | 0.250 | 1.000 | 0.250 | +17.9 | -4.5 (1/2) |

Ranking, lu2 (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rmatch | 3 | 15.2 | +6.1 | 28 | 89.1 |
| 2 | sl_rturbo | 3 | 12.6 | +3.5 | 39 | 73.8 |
| 3 | game | 3 | 9.1 | +0.0 | 44 | 58.6 |
| 4 | sl_rmid2 | 3 | 2.8 | -6.3 | 84 | 30.3 |

Ranking, lu4 (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rturbo | 3 | 29.8 | +18.6 | 25 | 100.6 |
| 2 | sl_rturbo_in | 3 | 20.1 | +9.0 | 37 | 96.6 |
| 3 | sl_rspread | 3 | 17.7 | +6.6 | 43 | 96.2 |
| 4 | game | 3 | 11.2 | +0.0 | 36 | 69.6 |

Ranking, pooled over the ring types (mean delta km/h vs game, mean rank):

| mode | tests | mean delta km/h vs game | mean rank |
|---|---|---|---|
| sl_rmatch | 1 | +6.1 | 1.0 |
| sl_rturbo | 2 | +11.0 | 1.5 |
| sl_rturbo_in | 1 | +9.0 | 2.0 |
| sl_rspread | 1 | +6.6 | 3.0 |
| game | 2 | +0.0 | 3.5 |
| sl_rmid2 | 1 | -6.3 | 4.0 |

## Ring lane use

Bench sheet 5 (BENCH.md "Sheet 5"): per ring (test) and traffic mix (`mix=` of the zone lines: even = four equal towns, straight = the N and S towns large, adjacent = the N and E towns large), every mode's matched twins pooled over the recorded window (after the warm-up). thru/min = cars through per game minute; queue per arm = queued cars on the inbound side (`q_in`); lane use = car samples on the ring's edges by lane, outer lane (o1) first (`RINGLANE`, clustered by distance from the centre); turning mix = arms passed from entry to exit per driver, each once (`RINGMIX`: 1st exit .. U-turn; none = no entry and exit read).

| ring | mix | mode | sets | samples | thru/min | km/h | standing % | queue | queue per arm (inbound) | lane use | turning mix |
|---|---|---|---|---|---|---|---|---|---|---|---|
| lu2 | even | game | 1 | 120 | 58.6 | 7.2 | 49 | 15.8 | N 3.2, E 3.9, S 3.2, W 3.7 | o1 100 % (21.0 m) | 1st 33 %, 2nd 33 %, 3rd 34 %, U 0 % (n 609, none 0 %) |
| lu2 | even | sl_rturbo | 1 | 120 | 74.0 | 8.6 | 46 | 21.6 | N 5.1, E 4.4, S 3.9, W 4.7 | o1 17 % (21.0 m), o2 83 % (17.0 m) | 1st 35 %, 2nd 30 %, 3rd 34 %, U 0 % (n 553, none 0 %) |
| lu2 | even | sl_rmatch | 1 | 120 | 85.4 | 9.2 | 42 | 41.6 | N 7.0, E 7.2, S 10.2, W 7.4 | o1 51 % (21.0 m), o2 49 % (17.0 m) | 1st 33 %, 2nd 33 %, 3rd 34 %, U 0 % (n 563, none 0 %) |
| lu2 | even | sl_rmid2 | 1 | 120 | 29.1 | 1.6 | 88 | 264.6 | N 50.8, E 48.4, S 50.9, W 48.8 | o1 39 % (21.0 m), o2 61 % (17.0 m) | 1st 30 %, 2nd 37 %, 3rd 33 %, U 0 % (n 433, none 93 %) |
| lu2 | straight | game | 1 | 120 | 59.0 | 10.4 | 39 | 9.7 | N 0.4, E 3.1, S 0.6, W 2.9 | o1 100 % (21.0 m) | 1st 16 %, 2nd 66 %, 3rd 18 %, U 0 % (n 508, none 0 %) |
| lu2 | straight | sl_rturbo | 1 | 120 | 70.7 | 12.7 | 33 | 5.1 | N 0.6, E 2.3, S 0.8, W 0.1 | o1 15 % (21.0 m), o2 85 % (17.0 m) | 1st 24 %, 2nd 61 %, 3rd 15 %, U 0 % (n 505, none 0 %) |
| lu2 | straight | sl_rmatch | 1 | 120 | 91.9 | 18.8 | 19 | 3.6 | N 0.9, E 0.1, S 0.3, W 0.0 | o1 55 % (21.0 m), o2 45 % (17.0 m) | 1st 15 %, 2nd 66 %, 3rd 19 %, U 0 % (n 518, none 0 %) |
| lu2 | straight | sl_rmid2 | 1 | 120 | 26.0 | 2.7 | 86 | 178.3 | N 49.2, E 9.3, S 47.1, W 14.7 | o1 35 % (21.0 m), o2 65 % (17.0 m) | 1st 49 %, 2nd 7 %, 3rd 44 %, U 0 % (n 276, none 73 %) |
| lu2 | adjacent | game | 1 | 120 | 58.2 | 9.7 | 42 | 17.0 | N 0.4, E 1.1, S 10.7, W 1.4 | o1 100 % (21.0 m) | 1st 42 %, 2nd 19 %, 3rd 39 %, U 0 % (n 563, none 0 %) |
| lu2 | adjacent | sl_rturbo | 1 | 120 | 76.8 | 16.3 | 38 | 10.9 | N 2.2, E 0.0, S 0.0, W 6.9 | o1 21 % (21.0 m), o2 79 % (17.0 m) | 1st 43 %, 2nd 17 %, 3rd 40 %, U 0 % (n 536, none 0 %) |
| lu2 | adjacent | sl_rmatch | 1 | 120 | 90.1 | 17.6 | 21 | 4.5 | N 0.6, E 0.5, S 0.7, W 0.2 | o1 53 % (21.0 m), o2 47 % (17.0 m) | 1st 44 %, 2nd 15 %, 3rd 41 %, U 0 % (n 482, none 0 %) |
| lu2 | adjacent | sl_rmid2 | 1 | 120 | 35.7 | 4.2 | 77 | 152.8 | N 41.2, E 36.9, S 5.6, W 22.7 | o1 37 % (21.0 m), o2 63 % (17.0 m) | 1st 52 %, 2nd 19 %, 3rd 30 %, U 0 % (n 391, none 38 %) |
| lu4 | even | game | 1 | 120 | 76.8 | 8.4 | 43 | 12.4 | N 4.4, E 2.7, S 2.4, W 2.4 | o1 53 % (27.0 m), o2 47 % (23.0 m) | 1st 35 %, 2nd 32 %, 3rd 33 %, U 0 % (n 724, none 2 %) |
| lu4 | even | sl_rturbo | 1 | 120 | 96.2 | 9.9 | 52 | 71.6 | N 9.5, E 13.8, S 16.8, W 16.0 | o1 6 % (27.0 m), o2 50 % (23.0 m), o3 44 % (19.0 m) | 1st 31 %, 2nd 31 %, 3rd 37 %, U 0 % (n 607, none 0 %) |
| lu4 | even | sl_rspread | 1 | 120 | 64.1 | 5.4 | 70 | 202.0 | N 43.8, E 33.8, S 39.9, W 42.0 | o1 2 % (27.0 m), o2 40 % (23.0 m), o3 35 % (19.0 m), o4 23 % (15.0 m) | 1st 38 %, 2nd 31 %, 3rd 31 %, U 0 % (n 712, none 4 %) |
| lu4 | even | sl_rturbo_in | 1 | 120 | 69.5 | 6.1 | 68 | 179.2 | N 34.4, E 33.1, S 38.5, W 36.2 | o1 3 % (27.0 m), o2 50 % (23.0 m), o3 37 % (19.0 m), o4 10 % (15.0 m) | 1st 32 %, 2nd 36 %, 3rd 31 %, U 0 % (n 721, none 10 %) |
| lu4 | straight | game | 1 | 120 | 66.2 | 12.5 | 33 | 2.6 | N 1.3, E 0.0, S 1.1, W 0.1 | o1 58 % (27.0 m), o2 42 % (23.0 m) | 1st 23 %, 2nd 58 %, 3rd 19 %, U 0 % (n 605, none 0 %) |
| lu4 | straight | sl_rturbo | 1 | 120 | 109.3 | 32.9 | 14 | 1.5 | N 0.2, E 0.0, S 0.0, W 0.0 | o1 9 % (27.0 m), o2 58 % (23.0 m), o3 32 % (19.0 m) | 1st 17 %, 2nd 64 %, 3rd 19 %, U 0 % (n 652, none 0 %) |
| lu4 | straight | sl_rspread | 1 | 120 | 106.1 | 12.4 | 41 | 37.2 | N 11.8, E 0.6, S 7.5, W 8.2 | o1 5 % (27.0 m), o2 45 % (23.0 m), o3 28 % (19.0 m), o4 21 % (15.0 m) | 1st 27 %, 2nd 46 %, 3rd 27 %, U 0 % (n 791, none 0 %) |
| lu4 | straight | sl_rturbo_in | 1 | 120 | 109.8 | 25.7 | 22 | 6.2 | N 0.7, E 0.0, S 0.5, W 1.1 | o1 8 % (27.0 m), o2 58 % (23.0 m), o3 20 % (19.0 m), o4 13 % (15.0 m) | 1st 19 %, 2nd 63 %, 3rd 18 %, U 0 % (n 645, none 0 %) |
| lu4 | adjacent | game | 1 | 120 | 65.8 | 12.6 | 33 | 4.0 | N 1.1, E 1.8, S 0.7, W 0.0 | o1 61 % (27.0 m), o2 39 % (23.0 m) | 1st 40 %, 2nd 21 %, 3rd 39 %, U 0 % (n 788, none 0 %) |
| lu4 | adjacent | sl_rturbo | 1 | 120 | 96.4 | 46.5 | 8 | 1.0 | N 0.0, E 0.0, S 0.0, W 0.1 | o1 16 % (27.0 m), o2 61 % (23.0 m), o3 23 % (19.0 m) | 1st 45 %, 2nd 20 %, 3rd 35 %, U 0 % (n 671, none 0 %) |
| lu4 | adjacent | sl_rspread | 1 | 120 | 118.2 | 35.4 | 17 | 5.4 | N 0.2, E 0.0, S 0.4, W 1.4 | o1 12 % (27.0 m), o2 53 % (23.0 m), o3 24 % (19.0 m), o4 11 % (15.0 m) | 1st 41 %, 2nd 19 %, 3rd 40 %, U 0 % (n 799, none 0 %) |
| lu4 | adjacent | sl_rturbo_in | 1 | 120 | 110.4 | 28.6 | 23 | 7.5 | N 1.0, E 0.0, S 0.0, W 3.2 | o1 12 % (27.0 m), o2 58 % (23.0 m), o3 19 % (19.0 m), o4 11 % (15.0 m) | 1st 45 %, 2nd 15 %, 3rd 39 %, U 0 % (n 698, none 0 %) |

Turning mix per twin (`RINGMIX`, recorded window; drivers counted once):

| ring | mix | twin | mode | n | 1st | 2nd | 3rd | U-turn | none |
|---|---|---|---|---|---|---|---|---|---|
| lu2 | even | s5g1b | game | 609 | 202 | 201 | 206 | 0 | 0 |
| lu2 | even | s5g1h | sl_rturbo | 553 | 196 | 168 | 189 | 0 | 0 |
| lu2 | even | s5g1i | sl_rmatch | 563 | 185 | 187 | 191 | 0 | 0 |
| lu2 | even | s5g1w | sl_rmid2 | 433 | 9 | 11 | 10 | 0 | 403 |
| lu2 | straight | s5g2b | game | 508 | 80 | 337 | 91 | 0 | 0 |
| lu2 | straight | s5g2h | sl_rturbo | 505 | 121 | 306 | 78 | 0 | 0 |
| lu2 | straight | s5g2i | sl_rmatch | 518 | 77 | 342 | 99 | 0 | 0 |
| lu2 | straight | s5g2w | sl_rmid2 | 276 | 37 | 5 | 33 | 0 | 201 |
| lu2 | adjacent | s5g3b | game | 563 | 238 | 106 | 219 | 0 | 0 |
| lu2 | adjacent | s5g3h | sl_rturbo | 536 | 232 | 92 | 212 | 0 | 0 |
| lu2 | adjacent | s5g3i | sl_rmatch | 482 | 212 | 70 | 200 | 0 | 0 |
| lu2 | adjacent | s5g3w | sl_rmid2 | 391 | 126 | 45 | 72 | 0 | 148 |
| lu4 | even | s5g4b | game | 724 | 251 | 229 | 233 | 0 | 11 |
| lu4 | even | s5g4h | sl_rturbo | 607 | 191 | 190 | 226 | 0 | 0 |
| lu4 | even | s5g4m | sl_rspread | 712 | 257 | 213 | 215 | 0 | 27 |
| lu4 | even | s5g4y | sl_rturbo_in | 721 | 211 | 237 | 203 | 0 | 70 |
| lu4 | straight | s5g5b | game | 605 | 137 | 353 | 115 | 0 | 0 |
| lu4 | straight | s5g5h | sl_rturbo | 652 | 113 | 415 | 124 | 0 | 0 |
| lu4 | straight | s5g5m | sl_rspread | 791 | 213 | 362 | 216 | 0 | 0 |
| lu4 | straight | s5g5y | sl_rturbo_in | 645 | 124 | 407 | 114 | 0 | 0 |
| lu4 | adjacent | s5g6b | game | 788 | 315 | 163 | 310 | 0 | 0 |
| lu4 | adjacent | s5g6h | sl_rturbo | 671 | 300 | 134 | 237 | 0 | 0 |
| lu4 | adjacent | s5g6m | sl_rspread | 799 | 326 | 151 | 322 | 0 | 0 |
| lu4 | adjacent | s5g6y | sl_rturbo_in | 698 | 316 | 108 | 274 | 0 | 0 |

- **lu2 even**: sl_rmatch best by thru/min (85.4). sl_rmatch: +46 % thru/min, +2.0 km/h, standing -7 pp vs game; +15 % thru/min, +0.6 km/h, standing -3 pp vs sl_rturbo. sl_rturbo: +26 % thru/min, +1.4 km/h, standing -4 pp vs game. sl_rmid2: -50 % thru/min, -5.6 km/h, standing +39 pp vs game; -61 % thru/min, -7.0 km/h, standing +43 pp vs sl_rturbo.
- **lu2 straight**: sl_rmatch best by thru/min (91.9). sl_rmatch: +56 % thru/min, +8.5 km/h, standing -20 pp vs game; +30 % thru/min, +6.1 km/h, standing -14 pp vs sl_rturbo. sl_rturbo: +20 % thru/min, +2.4 km/h, standing -6 pp vs game. sl_rmid2: -56 % thru/min, -7.7 km/h, standing +47 pp vs game; -63 % thru/min, -10.1 km/h, standing +53 pp vs sl_rturbo.
- **lu2 adjacent**: sl_rmatch best by thru/min (90.1). sl_rmatch: +55 % thru/min, +7.9 km/h, standing -21 pp vs game; +17 % thru/min, +1.3 km/h, standing -17 pp vs sl_rturbo. sl_rturbo: +32 % thru/min, +6.6 km/h, standing -5 pp vs game. sl_rmid2: -39 % thru/min, -5.5 km/h, standing +35 pp vs game; -53 % thru/min, -12.1 km/h, standing +39 pp vs sl_rturbo.
- **lu4 even**: sl_rturbo best by thru/min (96.2). sl_rturbo: +25 % thru/min, +1.5 km/h, standing +9 pp vs game. sl_rturbo_in: -9 % thru/min, -2.3 km/h, standing +25 pp vs game; -28 % thru/min, -3.8 km/h, standing +16 pp vs sl_rturbo. sl_rspread: -16 % thru/min, -3.0 km/h, standing +27 pp vs game; -33 % thru/min, -4.5 km/h, standing +18 pp vs sl_rturbo.
- **lu4 straight**: sl_rturbo_in best by thru/min (109.8). sl_rturbo_in: +66 % thru/min, +13.2 km/h, standing -11 pp vs game; +1 % thru/min, -7.2 km/h, standing +8 pp vs sl_rturbo. sl_rturbo: +65 % thru/min, +20.4 km/h, standing -19 pp vs game. sl_rspread: +60 % thru/min, -0.1 km/h, standing +8 pp vs game; -3 % thru/min, -20.4 km/h, standing +27 pp vs sl_rturbo.
- **lu4 adjacent**: sl_rspread best by thru/min (118.2). sl_rspread: +80 % thru/min, +22.7 km/h, standing -16 pp vs game; +23 % thru/min, -11.2 km/h, standing +9 pp vs sl_rturbo. sl_rturbo_in: +68 % thru/min, +16.0 km/h, standing -10 pp vs game; +14 % thru/min, -18.0 km/h, standing +14 pp vs sl_rturbo. sl_rturbo: +47 % thru/min, +33.9 km/h, standing -25 pp vs game.

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| lu2 | sl_rturbo vs game | s5g1 | RB4_2L | 8.6 / 7.2 | +1.4 | -4 | +5.9 | 74.0 / 58.6 |
| lu2 | sl_rturbo vs game | s5g2 | RB4_2L | 12.7 / 10.4 | +2.4 | -6 | -4.5 | 70.7 / 59.0 |
| lu2 | sl_rturbo vs game | s5g3 | RB4_2L | 16.3 / 9.7 | +6.6 | -5 | -6.1 | 76.8 / 58.2 |
| lu2 | sl_rmid2 vs game | s5g1 | RB4_2L | 1.6 / 7.2 | -5.6 | +39 | +248.8 | 29.1 / 58.6 |
| lu2 | sl_rmid2 vs game | s5g2 | RB4_2L | 2.7 / 10.4 | -7.7 | +47 | +168.7 | 26.0 / 59.0 |
| lu2 | sl_rmid2 vs game | s5g3 | RB4_2L | 4.2 / 9.7 | -5.5 | +35 | +135.8 | 35.7 / 58.2 |
| lu2 | sl_rmatch vs game | s5g1 | RB4_2L | 9.2 / 7.2 | +2.0 | -7 | +25.8 | 85.4 / 58.6 |
| lu2 | sl_rmatch vs game | s5g2 | RB4_2L | 18.8 / 10.4 | +8.5 | -20 | -6.0 | 91.9 / 59.0 |
| lu2 | sl_rmatch vs game | s5g3 | RB4_2L | 17.6 / 9.7 | +7.9 | -21 | -12.5 | 90.1 / 58.2 |
| lu2 | sl_rmid2 vs sl_rturbo | s5g1 | RB4_2L | 1.6 / 8.6 | -7.0 | +43 | +242.9 | 29.1 / 74.0 |
| lu2 | sl_rmid2 vs sl_rturbo | s5g2 | RB4_2L | 2.7 / 12.7 | -10.1 | +53 | +173.2 | 26.0 / 70.7 |
| lu2 | sl_rmid2 vs sl_rturbo | s5g3 | RB4_2L | 4.2 / 16.3 | -12.1 | +39 | +141.9 | 35.7 / 76.8 |
| lu2 | sl_rmatch vs sl_rturbo | s5g1 | RB4_2L | 9.2 / 8.6 | +0.6 | -3 | +20.0 | 85.4 / 74.0 |
| lu2 | sl_rmatch vs sl_rturbo | s5g2 | RB4_2L | 18.8 / 12.7 | +6.1 | -14 | -1.5 | 91.9 / 70.7 |
| lu2 | sl_rmatch vs sl_rturbo | s5g3 | RB4_2L | 17.6 / 16.3 | +1.3 | -17 | -6.4 | 90.1 / 76.8 |
| lu4 | sl_rturbo vs game | s5g4 | RB_4-lane | 9.9 / 8.4 | +1.5 | +9 | +59.2 | 96.2 / 76.8 |
| lu4 | sl_rturbo vs game | s5g5 | RB_4-lane | 32.9 / 12.5 | +20.4 | -19 | -1.1 | 109.3 / 66.2 |
| lu4 | sl_rturbo vs game | s5g6 | RB_4-lane | 46.5 / 12.6 | +33.9 | -25 | -3.0 | 96.4 / 65.8 |
| lu4 | sl_rturbo_in vs game | s5g4 | RB_4-lane | 6.1 / 8.4 | -2.3 | +25 | +166.8 | 69.5 / 76.8 |
| lu4 | sl_rturbo_in vs game | s5g5 | RB_4-lane | 25.7 / 12.5 | +13.2 | -11 | +3.6 | 109.8 / 66.2 |
| lu4 | sl_rturbo_in vs game | s5g6 | RB_4-lane | 28.6 / 12.6 | +16.0 | -10 | +3.5 | 110.4 / 65.8 |
| lu4 | sl_rspread vs game | s5g4 | RB_4-lane | 5.4 / 8.4 | -3.0 | +27 | +189.6 | 64.1 / 76.8 |
| lu4 | sl_rspread vs game | s5g5 | RB_4-lane | 12.4 / 12.5 | -0.1 | +8 | +34.5 | 106.1 / 66.2 |
| lu4 | sl_rspread vs game | s5g6 | RB_4-lane | 35.4 / 12.6 | +22.7 | -16 | +1.4 | 118.2 / 65.8 |
| lu4 | sl_rturbo_in vs sl_rturbo | s5g4 | RB_4-lane | 6.1 / 9.9 | -3.8 | +16 | +107.6 | 69.5 / 96.2 |
| lu4 | sl_rturbo_in vs sl_rturbo | s5g5 | RB_4-lane | 25.7 / 32.9 | -7.2 | +8 | +4.7 | 109.8 / 109.3 |
| lu4 | sl_rturbo_in vs sl_rturbo | s5g6 | RB_4-lane | 28.6 / 46.5 | -18.0 | +14 | +6.5 | 110.4 / 96.4 |
| lu4 | sl_rspread vs sl_rturbo | s5g4 | RB_4-lane | 5.4 / 9.9 | -4.5 | +18 | +130.4 | 64.1 / 96.2 |
| lu4 | sl_rspread vs sl_rturbo | s5g5 | RB_4-lane | 12.4 / 32.9 | -20.4 | +27 | +35.7 | 106.1 / 109.3 |
| lu4 | sl_rspread vs sl_rturbo | s5g6 | RB_4-lane | 35.4 / 46.5 | -11.2 | +9 | +4.3 | 118.2 / 96.4 |

Treatment (Smart Lanes lines with zid=): lu2: game 3 (applied 0, unchanged 0, skipped 3, lights off 0, kept 0, lit at read 0), sl_rmatch 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0), sl_rmid2 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0), sl_rturbo 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0); lu4: game 3 (applied 0, unchanged 0, skipped 3, lights off 0, kept 0, lit at read 0), sl_rspread 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0), sl_rturbo 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0), sl_rturbo_in 3 (applied 3, unchanged 0, skipped 0, lights off 12, kept 0, lit at read 0).

Suggested verdict lines (review before adding to the Verdicts table):
- lu2, sl_rturbo vs game: sl_rturbo better by +3.5 km/h, 3/3 pairs, sign p 0.250 (Holm 1.000): trend.
- lu2, sl_rmid2 vs game: sl_rmid2 worse by -6.3 km/h, 0/3 pairs, sign p 0.250 (Holm 1.000): trend.
- lu2, sl_rmatch vs game: sl_rmatch better by +6.1 km/h, 3/3 pairs, sign p 0.250 (Holm 1.000): trend.
- lu2, sl_rmid2 vs sl_rturbo: sl_rmid2 worse by -9.7 km/h, 0/3 pairs, sign p 0.250 (Holm 1.000): trend.
- lu2, sl_rmatch vs sl_rturbo: sl_rmatch better by +2.7 km/h, 3/3 pairs, sign p 0.250 (Holm 1.000): trend.
- lu4, sl_rturbo vs game: sl_rturbo better by +18.6 km/h, 3/3 pairs, sign p 0.250 (Holm 1.000): trend.
- lu4, sl_rturbo_in vs game: sl_rturbo_in better by +9.0 km/h, 2/3 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- lu4, sl_rspread vs game: sl_rspread better by +6.6 km/h, 1/3 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- lu4, sl_rturbo_in vs sl_rturbo: sl_rturbo_in worse by -9.6 km/h, 0/3 pairs, sign p 0.250 (Holm 1.000): trend.
- lu4, sl_rspread vs sl_rturbo: sl_rspread worse by -12.0 km/h, 0/3 pairs, sign p 0.250 (Holm 1.000): trend.

### Light plans A/B run 2: 2026-10-15_0509_light-plans-auto-863105 (seed 863105)
Setup: Stress Test "Build light plans A/B" (rev 8), 16 km Blank Slate, 2x2 X and 3x3 X x 3 sets, twins game / sl_phases
(axis) / sl_auto (axis + automatic re-timing), 3 balanced sets (4 towns ~600) and 3 unbalanced (E/W ~600, N ~150, S ~40;
measured 601 / 150 / 41 at the end), traffic log every 10 s, 61.3 game min, 4x. Auto twins enrolled at build; the first
window ran during the build and was skipped (`changed:lanes`, retried); 24 writes in all; settled window = first write
+ 900 game s. Report: `make flow LOG=2026-10-15_0509_light-plans-auto-863105`.

| shape | demand | game | axis | auto (settled) | note |
|---|---|---|---|---|---|
| 2x2 X | balanced | 94.0 | 125.4 | 127.4 | auto queue 183 vs axis 144 (cycle 112-120 s) |
| 2x2 X | unbalanced | 74.8 | 99.1 | 104.3 | |
| 3x3 X | balanced | 119.1 | 155.5 | 155.7 | auto queue 148 vs 116 |
| 3x3 X | unbalanced | 108.7 | 112.8 | 120.7 | auto 46.5 km/h vs 23.4, standing 20 vs 35 %, queue 9.9 vs 31.1 |

(cars through per game minute.) Paired over 6 sets: sl_auto+settled vs sl_phases thru 6/0 (p = 0.031), speed 5/1;
vs game thru 6/0 (+26.1/min), standing 6/0. Writes kept the node ids (no re-attach: docs/findings/roads.md). g2v
flip-flopped 62 > 82 > 62 > 50 s.

### Light plans A/B run 1: 2026-10-15_0355_top-up-488195 (seed 488195)
Setup: Stress Test "Build light plans A/B", 2x2 X and 3x3 X x 3 sets, twins game / sl_phases (axis) / sl_classic, towns
~600, 19.4 game min (76 samples per zone after warm-up). The mod files were loaded mid-edit (axis greens 24 s, 52 s
cycle; classic x4_split 92 s). Report: `make flow LOG=2026-10-15_0355_top-up-488195`.

| shape | game | axis | classic |
|---|---|---|---|
| 2x2 X | 99.8 (9.9 km/h, queue 82) | **123.1** (10.0, 87) | 84.0 (6.3, 180) |
| 3x3 X | 122.5 (9.9, 117) | **154.1** (17.0, 61) | 108.5 (10.1, 141) |

(cars/min, km/h and queued cars in brackets.) axis vs game thru 6/0, standing 6/0 (p = 0.031); axis vs classic 6/0 on
every measure; classic vs game thru 0/6.

### Bench sheet s4: 2026-10-14_0201_bench-s4-176702 (seed 176702)
Setup: bench_s4@5, map 16384x16384 m, 13 junctions, 52 towns (~400 people each); Smart Lanes game phases, free curb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 13 screenshots.
Build: summary seed=176702 groups=13 built=13 refused=0 rb2v=5/5 rb3v=4/4 rb4v=4/4 shapes RB_2L_town=2/2 RB_2L_town_mid=3/3 RB_3-lane=2/2 RB_3-lane_mid=2/2 RB_4-lane=2/2 RB_4-lane_mid=2/2 game=6/6 sl=3/3 sl_
Entries: entries roundabout=52 crossroads=0 broken=0 joins=156/156
Sampler: 120 map-wide samples recorded, map-wide standing 39 %; capped 0, strided 0, FLOW_TARGET 0, busiest frame 8.2 ms (phase scan); thru by position.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| rb2v | sl_rsplit@mid vs game@plain | 1 | +3.5 | 1/0/0 | 1.000 | 1.000 | 1.000 | -14.7 | +22.1 (1/0) |
| rb2v | sl_rsplit@mid vs sl@plain | 1 | +3.0 | 1/0/0 | 1.000 | 1.000 | 1.000 | -10.3 | +17.3 (1/0) |
| rb2v | game@mid vs game@plain | 1 | +1.0 | 1/0/0 | 1.000 | 1.000 | 1.000 | -6.0 | +9.7 (1/0) |
| rb2v | sl@plain vs game@plain | 1 | +0.5 | 1/0/0 | 1.000 | 1.000 | 1.000 | -4.4 | +4.8 (1/0) |
| rb2v | sl_rmid@mid vs game@plain | 1 | +4.4 | 1/0/0 | 1.000 | 1.000 | 1.000 | -15.9 | +29.2 (1/0) |
| rb2v | sl_rmid@mid vs sl_rsplit@mid | 1 | +0.9 | 1/0/0 | 1.000 | 1.000 | 1.000 | -1.2 | +7.1 (1/0) |
| rb3v | sl_rsplit@mid vs game@plain | 1 | -1.3 | 0/1/0 | 1.000 | 1.000 | 1.000 | +9.3 | -3.2 (0/1) |
| rb3v | sl_rsplit@mid vs sl@plain | 1 | -3.3 | 0/1/0 | 1.000 | 1.000 | 1.000 | +8.4 | -3.0 (0/1) |
| rb3v | game@mid vs game@plain | 1 | -9.0 | 0/1/0 | 1.000 | 1.000 | 1.000 | +41.5 | -55.8 (0/1) |
| rb3v | sl@plain vs game@plain | 1 | +2.0 | 1/0/0 | 1.000 | 1.000 | 1.000 | +0.8 | -0.2 (0/1) |
| rb4v | sl_rsplit@mid vs game@plain | 1 | -5.2 | 0/1/0 | 1.000 | 1.000 | 1.000 | +33.6 | -24.7 (0/1) |
| rb4v | sl_rsplit@mid vs sl@plain | 1 | -19.6 | 0/1/0 | 1.000 | 1.000 | 1.000 | +43.3 | -52.8 (0/1) |
| rb4v | game@mid vs game@plain | 1 | -7.4 | 0/1/0 | 1.000 | 1.000 | 1.000 | +47.7 | -41.8 (0/1) |
| rb4v | sl@plain vs game@plain | 1 | +14.5 | 1/0/0 | 1.000 | 1.000 | 1.000 | -9.7 | +28.1 (1/0) |

Ranking, rb2v (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rmid@mid | 1 | 12.4 | +4.4 | 30 | 91.8 |
| 2 | sl_rsplit@mid | 1 | 11.4 | +3.5 | 31 | 84.7 |
| 3 | game@mid | 1 | 9.0 | +1.0 | 40 | 72.2 |
| 4 | sl@plain | 1 | 8.4 | +0.5 | 41 | 67.4 |
| 5 | game@plain | 1 | 8.0 | +0.0 | 46 | 62.5 |

Ranking, rb3v (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl@plain | 1 | 13.2 | +2.0 | 48 | 92.2 |
| 2 | game@plain | 1 | 11.2 | +0.0 | 47 | 92.3 |
| 3 | sl_rsplit@mid | 1 | 9.9 | -1.3 | 56 | 89.2 |
| 4 | game@mid | 1 | 2.2 | -9.0 | 88 | 36.5 |

Ranking, rb4v (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl@plain | 1 | 23.3 | +14.5 | 33 | 102.7 |
| 2 | game@plain | 1 | 8.8 | +0.0 | 43 | 74.6 |
| 3 | sl_rsplit@mid | 1 | 3.6 | -5.2 | 76 | 50.0 |
| 4 | game@mid | 1 | 1.4 | -7.4 | 90 | 32.8 |

Ranking, pooled over the ring types (mean delta km/h vs game, mean rank):

| mode | tests | mean delta km/h vs game | mean rank |
|---|---|---|---|
| sl_rmid@mid | 1 | +4.4 | 1.0 |
| sl@plain | 3 | +5.6 | 2.0 |
| sl_rsplit@mid | 3 | -1.0 | 2.7 |
| game@plain | 3 | +0.0 | 3.0 |
| game@mid | 3 | -5.1 | 3.7 |

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| rb2v | sl_rsplit@mid vs game@plain | s4g1 | RB_2L_town | 11.4 / 8.0 | +3.5 | -15 | -9.4 | 84.7 / 62.5 |
| rb2v | sl_rsplit@mid vs sl@plain | s4g1 | RB_2L_town | 11.4 / 8.4 | +3.0 | -10 | -7.0 | 84.7 / 67.4 |
| rb2v | game@mid vs game@plain | s4g1 | RB_2L_town | 9.0 / 8.0 | +1.0 | -6 | -1.2 | 72.2 / 62.5 |
| rb2v | sl@plain vs game@plain | s4g1 | RB_2L_town | 8.4 / 8.0 | +0.5 | -4 | -2.3 | 67.4 / 62.5 |
| rb2v | sl_rmid@mid vs game@plain | s4g1 | RB_2L_town | 12.4 / 8.0 | +4.4 | -16 | +6.3 | 91.8 / 62.5 |
| rb2v | sl_rmid@mid vs sl_rsplit@mid | s4g1 | RB_2L_town | 12.4 / 11.4 | +0.9 | -1 | +15.6 | 91.8 / 84.7 |
| rb3v | sl_rsplit@mid vs game@plain | s4g2 | RB_3-lane | 9.9 / 11.2 | -1.3 | +9 | +54.4 | 89.2 / 92.3 |
| rb3v | sl_rsplit@mid vs sl@plain | s4g2 | RB_3-lane | 9.9 / 13.2 | -3.3 | +8 | +49.1 | 89.2 / 92.2 |
| rb3v | game@mid vs game@plain | s4g2 | RB_3-lane | 2.2 / 11.2 | -9.0 | +42 | +296.3 | 36.5 / 92.3 |
| rb3v | sl@plain vs game@plain | s4g2 | RB_3-lane | 13.2 / 11.2 | +2.0 | +1 | +5.3 | 92.2 / 92.3 |
| rb4v | sl_rsplit@mid vs game@plain | s4g3 | RB_4-lane | 3.6 / 8.8 | -5.2 | +34 | +252.5 | 50.0 / 74.6 |
| rb4v | sl_rsplit@mid vs sl@plain | s4g3 | RB_4-lane | 3.6 / 23.3 | -19.6 | +43 | +249.4 | 50.0 / 102.7 |
| rb4v | game@mid vs game@plain | s4g3 | RB_4-lane | 1.4 / 8.8 | -7.4 | +48 | +388.7 | 32.8 / 74.6 |
| rb4v | sl@plain vs game@plain | s4g3 | RB_4-lane | 23.3 / 8.8 | +14.5 | -10 | +3.1 | 102.7 / 74.6 |

Treatment (Smart Lanes lines with zid=): rb2v: game 2 (applied 0, unchanged 0, skipped 2, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rmid 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rsplit 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0); rb3v: game 2 (applied 0, unchanged 0, skipped 2, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rsplit 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0); rb4v: game 2 (applied 0, unchanged 0, skipped 2, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rsplit 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0).

Suggested verdict lines (review before adding to the Verdicts table):
- rb2v, sl_rsplit@mid vs game@plain: sl_rsplit@mid better by +3.5 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2v, sl_rsplit@mid vs sl@plain: sl_rsplit@mid better by +3.0 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2v, game@mid vs game@plain: game@mid better by +1.0 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2v, sl@plain vs game@plain: sl@plain better by +0.5 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2v, sl_rmid@mid vs game@plain: sl_rmid@mid better by +4.4 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2v, sl_rmid@mid vs sl_rsplit@mid: sl_rmid@mid better by +0.9 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3v, sl_rsplit@mid vs game@plain: sl_rsplit@mid worse by -1.3 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3v, sl_rsplit@mid vs sl@plain: sl_rsplit@mid worse by -3.3 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3v, game@mid vs game@plain: game@mid worse by -9.0 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3v, sl@plain vs game@plain: sl@plain better by +2.0 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4v, sl_rsplit@mid vs game@plain: sl_rsplit@mid worse by -5.2 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4v, sl_rsplit@mid vs sl@plain: sl_rsplit@mid worse by -19.6 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4v, game@mid vs game@plain: game@mid worse by -7.4 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4v, sl@plain vs game@plain: sl@plain better by +14.5 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.

### Bench sheet s4: 2026-10-14_0133_session (seed 455860)
Setup: bench_s4@4, map 16384x16384 m, 15 junctions, 60 towns (~400 people each); Smart Lanes game phases, free curb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 15 screenshots.
Build: summary seed=455860 groups=15 built=15 refused=0 rb2tm=5/5 rb3m=5/5 rb4lm=5/5 shapes RB_2L_town_mid=5/5 RB_3-lane_mid=5/5 RB_4-lane_mid=5/5 game=3/3 sl=3/3 sl_rspiral=3/3 sl_rsplit=3/3 sl_rmid=3/3 lin
Entries: entries roundabout=60 crossroads=0 broken=0 joins=180/180
Sampler: 120 map-wide samples recorded, map-wide standing 48 %; capped 0, strided 0, FLOW_TARGET 0, busiest frame 11.4 ms (phase scan); thru by position.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| rb2tm | sl_rmid vs sl_rsplit | 1 | -0.3 | 0/1/0 | 1.000 | 1.000 | 1.000 | +1.3 | +7.4 (1/0) |
| rb2tm | sl_rmid vs sl_rspiral | 1 | +1.2 | 1/0/0 | 1.000 | 1.000 | 1.000 | -1.7 | +9.8 (1/0) |
| rb2tm | sl_rmid vs game | 1 | +2.8 | 1/0/0 | 1.000 | 1.000 | 1.000 | -6.8 | +16.2 (1/0) |
| rb2tm | sl_rsplit vs sl_rspiral | 1 | +1.5 | 1/0/0 | 1.000 | 1.000 | 1.000 | -3.0 | +2.4 (1/0) |
| rb2tm | sl vs game | 1 | +1.9 | 1/0/0 | 1.000 | 1.000 | 1.000 | -7.6 | +13.2 (1/0) |
| rb3m | sl_rmid vs sl_rsplit | 1 | -13.7 | 0/1/0 | 1.000 | 1.000 | 1.000 | +40.4 | -52.1 (0/1) |
| rb3m | sl_rmid vs sl_rspiral | 1 | -8.2 | 0/1/0 | 1.000 | 1.000 | 1.000 | +29.9 | -48.9 (0/1) |
| rb3m | sl_rmid vs game | 1 | -1.3 | 0/1/0 | 1.000 | 1.000 | 1.000 | +6.1 | -9.4 (0/1) |
| rb3m | sl_rsplit vs sl_rspiral | 1 | +5.5 | 1/0/0 | 1.000 | 1.000 | 1.000 | -10.6 | +3.2 (1/0) |
| rb3m | sl vs game | 1 | -2.3 | 0/1/0 | 1.000 | 1.000 | 1.000 | +11.6 | -17.5 (0/1) |
| rb4lm | sl_rmid vs sl_rsplit | 1 | +0.0 | 1/0/0 | 1.000 | 1.000 | 1.000 | +2.9 | +5.7 (1/0) |
| rb4lm | sl_rmid vs sl_rspiral | 1 | -1.8 | 0/1/0 | 1.000 | 1.000 | 1.000 | +12.0 | -7.2 (0/1) |
| rb4lm | sl_rmid vs game | 1 | +2.3 | 1/0/0 | 1.000 | 1.000 | 1.000 | -10.2 | +28.3 (1/0) |
| rb4lm | sl_rsplit vs sl_rspiral | 1 | -1.8 | 0/1/0 | 1.000 | 1.000 | 1.000 | +9.1 | -12.9 (0/1) |
| rb4lm | sl vs game | 1 | +1.8 | 1/0/0 | 1.000 | 1.000 | 1.000 | -6.3 | +12.9 (1/0) |

Ranking, rb2tm (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rsplit | 1 | 12.4 | +3.1 | 31 | 80.3 |
| 2 | sl_rmid | 1 | 12.2 | +2.8 | 32 | 87.8 |
| 3 | sl | 1 | 11.2 | +1.9 | 31 | 84.8 |
| 4 | sl_rspiral | 1 | 11.0 | +1.6 | 34 | 77.9 |
| 5 | game | 1 | 9.3 | +0.0 | 39 | 71.6 |

Ranking, rb3m (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rsplit | 1 | 16.2 | +12.4 | 43 | 96.7 |
| 2 | sl_rspiral | 1 | 10.7 | +6.9 | 54 | 93.5 |
| 3 | game | 1 | 3.8 | +0.0 | 78 | 54.0 |
| 4 | sl_rmid | 1 | 2.6 | -1.3 | 84 | 44.6 |
| 5 | sl | 1 | 1.6 | -2.3 | 89 | 36.5 |

Ranking, rb4lm (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rspiral | 1 | 5.8 | +4.1 | 67 | 65.5 |
| 2 | sl_rmid | 1 | 4.0 | +2.3 | 79 | 58.3 |
| 3 | sl_rsplit | 1 | 4.0 | +2.3 | 76 | 52.6 |
| 4 | sl | 1 | 3.4 | +1.8 | 83 | 42.8 |
| 5 | game | 1 | 1.7 | +0.0 | 89 | 29.9 |

Ranking, pooled over the ring types (mean delta km/h vs game, mean rank):

| mode | tests | mean delta km/h vs game | mean rank |
|---|---|---|---|
| sl_rsplit | 3 | +5.9 | 1.7 |
| sl_rspiral | 3 | +4.2 | 2.3 |
| sl_rmid | 3 | +1.3 | 2.7 |
| sl | 3 | +0.4 | 4.0 |
| game | 3 | +0.0 | 4.3 |

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| rb2tm | sl_rmid vs sl_rsplit | s4g1 | RB_2L_town_mid | 12.2 / 12.4 | -0.3 | +1 | +14.6 | 87.8 / 80.3 |
| rb2tm | sl_rmid vs sl_rspiral | s4g1 | RB_2L_town_mid | 12.2 / 11.0 | +1.2 | -2 | +17.5 | 87.8 / 77.9 |
| rb2tm | sl_rmid vs game | s4g1 | RB_2L_town_mid | 12.2 / 9.3 | +2.8 | -7 | +11.6 | 87.8 / 71.6 |
| rb2tm | sl_rsplit vs sl_rspiral | s4g1 | RB_2L_town_mid | 12.4 / 11.0 | +1.5 | -3 | +2.9 | 80.3 / 77.9 |
| rb2tm | sl vs game | s4g1 | RB_2L_town_mid | 11.2 / 9.3 | +1.9 | -8 | -9.4 | 84.8 / 71.6 |
| rb3m | sl_rmid vs sl_rsplit | s4g2 | RB_3-lane_mid | 2.6 / 16.2 | -13.7 | +40 | +266.7 | 44.6 / 96.7 |
| rb3m | sl_rmid vs sl_rspiral | s4g2 | RB_3-lane_mid | 2.6 / 10.7 | -8.2 | +30 | +237.7 | 44.6 / 93.5 |
| rb3m | sl_rmid vs game | s4g2 | RB_3-lane_mid | 2.6 / 3.8 | -1.3 | +6 | +60.8 | 44.6 / 54.0 |
| rb3m | sl_rsplit vs sl_rspiral | s4g2 | RB_3-lane_mid | 16.2 / 10.7 | +5.5 | -11 | -29.0 | 96.7 / 93.5 |
| rb3m | sl vs game | s4g2 | RB_3-lane_mid | 1.6 / 3.8 | -2.3 | +12 | +111.5 | 36.5 / 54.0 |
| rb4lm | sl_rmid vs sl_rsplit | s4g3 | RB_4-lane_mid | 4.0 / 4.0 | +0.0 | +3 | +53.1 | 58.3 / 52.6 |
| rb4lm | sl_rmid vs sl_rspiral | s4g3 | RB_4-lane_mid | 4.0 / 5.8 | -1.8 | +12 | +124.4 | 58.3 / 65.5 |
| rb4lm | sl_rmid vs game | s4g3 | RB_4-lane_mid | 4.0 / 1.7 | +2.3 | -10 | -101.1 | 58.3 / 29.9 |
| rb4lm | sl_rsplit vs sl_rspiral | s4g3 | RB_4-lane_mid | 4.0 / 5.8 | -1.8 | +9 | +71.3 | 52.6 / 65.5 |
| rb4lm | sl vs game | s4g3 | RB_4-lane_mid | 3.4 / 1.7 | +1.8 | -6 | -118.7 | 42.8 / 29.9 |

Treatment (Smart Lanes lines with zid=): rb2tm: game 1 (applied 0, unchanged 0, skipped 1, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rmid 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rspiral 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rsplit 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0); rb3m: game 1 (applied 0, unchanged 0, skipped 1, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rmid 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rspiral 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rsplit 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0); rb4lm: game 1 (applied 0, unchanged 0, skipped 1, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rmid 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rspiral 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rsplit 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0).

Suggested verdict lines (review before adding to the Verdicts table):
- rb2tm, sl_rmid vs sl_rsplit: sl_rmid worse by -0.3 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl_rmid vs sl_rspiral: sl_rmid better by +1.2 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl_rmid vs game: sl_rmid better by +2.8 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl_rsplit vs sl_rspiral: sl_rsplit better by +1.5 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl vs game: sl better by +1.9 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3m, sl_rmid vs sl_rsplit: sl_rmid worse by -13.7 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3m, sl_rmid vs sl_rspiral: sl_rmid worse by -8.2 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3m, sl_rmid vs game: sl_rmid worse by -1.3 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3m, sl_rsplit vs sl_rspiral: sl_rsplit better by +5.5 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb3m, sl vs game: sl worse by -2.3 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4lm, sl_rmid vs sl_rsplit: sl_rmid better by +0.0 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4lm, sl_rmid vs sl_rspiral: sl_rmid worse by -1.8 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4lm, sl_rmid vs game: sl_rmid better by +2.3 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4lm, sl_rsplit vs sl_rspiral: sl_rsplit worse by -1.8 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb4lm, sl vs game: sl better by +1.8 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.

### Bench sheet s4: 2026-10-14_0027_bench-s4-487199 (seed 487199)
Setup: bench_s4@3, map 16384x16384 m, 4 junctions, 16 towns (~400 people each); Smart Lanes game phases, free curb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 4 screenshots.
Build: summary seed=487199 groups=4 built=4 refused=0 rb2tm=4/4 game=1/1 sl=1/1 sl_rspiral=1/1 sl_rsplit=1/1 links=16 linked=16 unlinked=0 towns_skipped=0 sets_mismatch=0 minutes=1.0
Entries: entries roundabout=16 crossroads=0 broken=0 joins=48/48
Sampler: 120 map-wide samples recorded, map-wide standing 26 %; capped 0, strided 0, FLOW_TARGET 0, busiest frame 6.1 ms (phase scan); thru by position.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| rb2tm | sl vs game | 1 | -2.1 | 0/1/0 | 1.000 | 1.000 | 1.000 | +6.2 | -8.6 (0/1) |
| rb2tm | sl_rspiral vs sl | 1 | +1.9 | 1/0/0 | 1.000 | 1.000 | 1.000 | -8.8 | +13.2 (1/0) |
| rb2tm | sl_rspiral vs game | 1 | -0.2 | 0/1/0 | 1.000 | 1.000 | 1.000 | -2.6 | +4.6 (1/0) |
| rb2tm | sl_rsplit vs sl_rspiral | 1 | +2.4 | 1/0/0 | 1.000 | 1.000 | 1.000 | -5.2 | +9.9 (1/0) |
| rb2tm | sl_rsplit vs game | 1 | +2.2 | 1/0/0 | 1.000 | 1.000 | 1.000 | -7.7 | +14.5 (1/0) |

Ranking, rb2tm (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rsplit | 1 | 12.4 | +2.2 | 31 | 85.9 |
| 2 | game | 1 | 10.2 | +0.0 | 39 | 71.4 |
| 3 | sl_rspiral | 1 | 10.0 | -0.2 | 37 | 76.0 |
| 4 | sl | 1 | 8.1 | -2.1 | 45 | 62.8 |

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| rb2tm | sl vs game | s4g1 | RB_2L_town_mid | 8.1 / 10.2 | -2.1 | +6 | -1.0 | 62.8 / 71.4 |
| rb2tm | sl_rspiral vs sl | s4g1 | RB_2L_town_mid | 10.0 / 8.1 | +1.9 | -9 | -4.5 | 76.0 / 62.8 |
| rb2tm | sl_rspiral vs game | s4g1 | RB_2L_town_mid | 10.0 / 10.2 | -0.2 | -3 | -5.5 | 76.0 / 71.4 |
| rb2tm | sl_rsplit vs sl_rspiral | s4g1 | RB_2L_town_mid | 12.4 / 10.0 | +2.4 | -5 | -4.0 | 85.9 / 76.0 |
| rb2tm | sl_rsplit vs game | s4g1 | RB_2L_town_mid | 12.4 / 10.2 | +2.2 | -8 | -9.5 | 85.9 / 71.4 |

Treatment (Smart Lanes lines with zid=): rb2tm: game 1 (applied 0, unchanged 0, skipped 1, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rspiral 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rsplit 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0).

Suggested verdict lines (review before adding to the Verdicts table):
- rb2tm, sl vs game: sl worse by -2.1 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl_rspiral vs sl: sl_rspiral better by +1.9 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl_rspiral vs game: sl_rspiral worse by -0.2 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl_rsplit vs sl_rspiral: sl_rsplit better by +2.4 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2tm, sl_rsplit vs game: sl_rsplit better by +2.2 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.

### Bench sheet s4: 2026-10-13_2341_bench-s4-774314 (seed 774314)
Setup: bench_s4@2, map 16384x16384 m, 3 junctions, 12 towns (~400 people each); Smart Lanes game phases, free curb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 3 screenshots.
Build: summary seed=774314 groups=3 built=3 refused=0 rb2t=3/3 game=1/1 sl=1/1 sl_rspiral=1/1 links=12 linked=12 unlinked=0 towns_skipped=0 sets_mismatch=0 minutes=0.7
Entries: entries roundabout=12 crossroads=0 broken=0 joins=36/36
Sampler: 119 map-wide samples recorded, map-wide standing 33 %; capped 0, strided 0, FLOW_TARGET 0, busiest frame 5.0 ms (phase scan); thru by position.

| test | compare | pairs | mean delta km/h | W/L/T | sign p | Holm p | Wilcoxon p | standing pp | thru/min (W/L) |
|---|---|---|---|---|---|---|---|---|---|
| rb2t | sl vs game | 1 | -0.0 | 0/1/0 | 1.000 | 1.000 | 1.000 | +0.4 | -1.0 (0/1) |
| rb2t | sl_rspiral vs sl | 1 | +0.7 | 1/0/0 | 1.000 | 1.000 | 1.000 | -4.2 | +5.1 (1/0) |
| rb2t | sl_rspiral vs game | 1 | +0.7 | 1/0/0 | 1.000 | 1.000 | 1.000 | -3.8 | +4.1 (1/0) |

Ranking, rb2t (by km/h; mean over its sets):

| rank | mode | sets | km/h | delta vs game | standing % | cars/min |
|---|---|---|---|---|---|---|
| 1 | sl_rspiral | 1 | 8.7 | +0.7 | 42 | 66.9 |
| 2 | game | 1 | 8.1 | +0.0 | 46 | 62.8 |
| 3 | sl | 1 | 8.1 | -0.0 | 46 | 61.7 |

Per pair (first mode minus second):

| test | compare | pair | variant | km/h | delta km/h | standing pp | queue | thru/min |
|---|---|---|---|---|---|---|---|---|
| rb2t | sl vs game | s4g1 | RB_2L_town | 8.1 / 8.1 | -0.0 | +0 | +1.5 | 61.7 / 62.8 |
| rb2t | sl_rspiral vs sl | s4g1 | RB_2L_town | 8.7 / 8.1 | +0.7 | -4 | -1.1 | 66.9 / 61.7 |
| rb2t | sl_rspiral vs game | s4g1 | RB_2L_town | 8.7 / 8.1 | +0.7 | -4 | +0.3 | 66.9 / 62.8 |

Treatment (Smart Lanes lines with zid=): rb2t: game 1 (applied 0, unchanged 0, skipped 1, lights off 0, kept 0, lit at read 0), sl 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0), sl_rspiral 1 (applied 1, unchanged 0, skipped 0, lights off 4, kept 0, lit at read 0).

Suggested verdict lines (review before adding to the Verdicts table):
- rb2t, sl vs game: sl worse by -0.0 km/h, 0/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2t, sl_rspiral vs sl: sl_rspiral better by +0.7 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.
- rb2t, sl_rspiral vs game: sl_rspiral better by +0.7 km/h, 1/1 pairs, sign p 1.000 (Holm 1.000): no clear effect.

### Bench micro v2, ring layouts (partial): 2026-10-13_0923_bench-micro-331773 (seed 331773)
Setup: bench_micro@2, 16 km, right-hand traffic, 32 junctions (4-lane square_roundabouts ring x2 sets, 3-lane x1,
2-lane x1; 4 country arms), 128 towns of 600 people, 8 twins per set: game, sl, and the six ring layouts
(`sl_rturbo` turbo, `sl_rmatch` matched, `sl_rout1` outer lane exits only, `sl_r2exit` two outer lanes exit,
`sl_rspiral` spiral by destination, `sl_rspread` turbo plus the centre lanes); No lights On. Build clean: 32/32,
0 refused, 128 roundabout entries, 384/384 joins; every variant twin wrote its whole ring before warmup. Stopped by
the user after 76 samples (no BENCH_DONE, not in the ledger). Map saturated (standing 32 → 52 % within the first
third of the record, flat after): speed measures queues, use throughput. `sl` twins: turbo on the 4-lane and 2-lane
rings, matched on the 3-lane ring (the build-order bug, seen flipping turbo → matched → turbo on one ring).
`sl_rout1` on the 2-lane ring = the game's layout (pair excluded, as expected); on the 3-lane ring it rewrote the
connections (9 → 9, different ones), so it is not the game's layout there (the report's "expected tie" label is
wrong for rb3).

Cars per minute through (mean over sets; km/h in brackets):

| layout | 4-lane (2 sets) | 3-lane (1 set) | 2-lane (1 set) |
|---|---|---|---|
| game | 82.1 (9.1) | 88.8 (7.3) | 60.8 (7.4) |
| sl (today) | **102.3** (8.9) | 82.5 (7.4) | 78.6 (9.8) |
| sl_rturbo | **98.3** (9.1) | 88.1 (8.0) | 78.3 (8.9) |
| sl_rmatch | 80.0 (6.1) | 78.9 (6.7) | **87.2** (8.8) |
| sl_rspread | 74.7 (6.7) | **93.8** (7.8) | 77.9 (8.9) |
| sl_r2exit | 85.1 (7.2) | 74.7 (6.8) | 81.6 (9.4) |
| sl_rout1 | 65.5 (6.9) | 63.6 (6.4) | = game |
| sl_rspiral | **56.6** (4.6), 79 % standing | **41.8** (1.4), 91 % standing | 81.1 (9.4) |

Reading: on 4-lane rings turbo (and sl, which ended turbo there) beat game (both sets, +16-20 cars/min) and beat
matched (~98-102 vs 80). Spiral is worst on 3- and 4-lane rings: every arm shifts each ring lane outwards inside the
junction while an entry lane joins the same lane, so every lane leaving the arm has two feeders. Outer exit only is
near the bottom. On the 2-lane ring every Smart Lanes layout beats game (+17-26 cars/min) and they differ little.
3-lane: one set, turbo / spread / game within ±6 cars/min; matched below turbo. Decision taken: fix the build-order
bug so the default writes the whole ring as turbo where it qualifies (PLAN.md).

### Bench micro (partial): 2026-10-13_0837_bench-micro-560595 (seed 560595)
Setup: bench_micro@1, 16 km, 24 junctions (3-lane `highway_new_large` ring = the Stress Test entry ring; 4-lane
square_roundabouts ring `town_new_one_way_medium`; country large 3+3 arms), 96 towns of 800 people, twins game / sl;
No lights On. Stopped by the user after ~13.5 of 20 recorded game minutes (81 samples, no BENCH_DONE, not in the
ledger). Map saturated (~52 % standing): speed measures queues, use throughput.
Confound (found by the Smart Lanes agent): the sl twins did not end with the same layout per ring size: every
4-lane twin ended with the turbo layout (exit-only outer lane), every 3-lane twin with plain matched lanes, because
the link builds re-seeded the arm junctions one job at a time and a non-fresh ring is rewritten as matched. So
"4-lane wins, 3-lane loses" is partly turbo vs matched. The default layout depending on build order is a Smart Lanes
bug to decide on after the ring-layout bench.

| ring | pairs | Δ km/h | W/L | Δ standing | Δ cars/min through | thru W/L |
|---|---|---|---|---|---|---|
| 3-lane | 6 | −1.4 | 1/5 | +12 pp | **−13.2** | **0/6** |
| 4-lane | 6 | −0.2 | 2/4 | +10 pp | **+22.7** (~104 vs ~79) | **6/0** |
| pooled | 12 | −0.8 | 3/9 | +11 pp | +4.7 | 6/6 |

### Bench sheet s3: 2026-10-13_0733_bench-s3-683079 (seed 683079)
Setup: bench_s3@1, map 16384x16384 m, 36 junctions, 117 towns (~400 people each); Smart Lanes game phases, free curb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 6 screenshots.
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
Setup: bench_s2@1, map 16384x16384 m, 39 junctions, 117 towns (~400 people each); Smart Lanes game phases, free curb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 5 screenshots.
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
Setup: bench_s1@1, map 16384x16384 m, 39 junctions, 132 towns (~400 people each); Smart Lanes game phases, free curb turn always, no lights at roundabouts and ramps on; record 20 game min at 2x, every 10 game s; run complete; 5 screenshots.
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
people (398 / 400 / 400); rig lane-fan fix; Light phases = Game default, Free curb turn = Always. Light traffic
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
Light phases = Game default, Free curb turn = Always. Not jammed (map-wide ~40-45 % standing, ~18-20 km/h).
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
