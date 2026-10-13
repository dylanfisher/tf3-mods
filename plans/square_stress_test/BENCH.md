Status: built 2026-10-13 (rev 2, unreleased), offline-tested; not run in game yet (TESTING.md 6W). Redesigned for
16 km maps the same day (user: "9.9mi x 9.9 is very large size": 16 km is the largest map): three sheets, one press
each. Builds on the Lights showcase (SHOWCASE.md "Town entries", "Mixed shapes", "Exit-fan twin"), the traffic log
contract (FLOW.md v3) and the run ledger (`plans/square_smart_lanes/RESULTS.md`). Section "As built" lists the files.

# Stress Test: the test bench

User (2026-10-13): "the lights showcase is much more accurate now with the town fixes, roundabouts, etc. can we use
that as a foundational tool to build the other tests? making sure to only have as many towns as necessary for that
test. and ideally we have as many tests as possible in one map so its faster to record and audit. the more you can
automate the better".

Tests wanted, in order: (1) Smart Lanes vs game at roundabouts, interchanges, slip-lane junctions, ramps, lane drops;
(2) the "No lights at roundabouts and ramps" setting alone; (3) free kerb turn without a jam on mixed shapes (sl vs
sl_lock); (4) T-junctions with 6+ pairs; (5) throughput, once `thru` reads.

## Key decisions (summary)

1. **A bench is a list of tests; one press builds a whole "sheet" (one map) and runs it end to end.** Every test is
   a junction type (one variant or a short variant list), its twins, its sets and its towns-per-arm rule. The bench
   compiles to the existing `SquareStressShowcaseSpec` + a precomputed layout and reuses `buildRun` (towns, grids,
   locks, entries, junctions, settle, reads, joins, links, growth, zones, match flags) unchanged in spirit.
2. **No town is shared between twins or tests.** Every twin keeps its own isolated road network. Sharing couples the
   A/B in three ways (below); "fewest towns" is met instead by a town only on arms whose movements the test needs.
3. **Point-clearance packing instead of circles.** Today every twin reserves a 2R = 3018 m square. The groups are plus
   shapes (towns on the axes, empty corners), so checking town-to-town, junction-to-town and link clearances point by
   point lets them interlock: 4-arm groups 35 per 16 km map (was 25), 54 per 20 km (was 36); T-shapes 40 / 73.
4. **Three 16 km sheets for tests 1-4** (16 km is the largest map; a 16 km map holds about 40 groups of these
   shapes). Sheet 1 roundabouts (9 sets) + lane drops (6), sheet 2 channelized T (9) + diamonds (6), sheet 3 lit T (9) +
   lit X (3); 36-39 groups and 117-132 towns each (table in "The first bench"). The diamond and the lane drop get 6
   pairs (the most that fit beside 9 roundabout / channelized sets); a second run of the sheet pools to 12 through the
   ledger. Test 5 is not a sheet: `thru` is logged in every run (by position, below), and throughput needs a saturated
   load level (statistics section).
5. **Three-twin sets** where one twin answers two questions: rings and slip-lane junctions run game / sl /
   sl_keeplights (test 1 = sl vs game, test 2 = sl vs sl_keeplights); lit T and X run sl / game / sl_lock (test 4 = sl
   vs game, test 3 = sl vs sl_lock). 3 squares for 2 comparisons instead of 4.
6. **9 pairs per primary question where it fits, 6 at least.** A sign test with 6 pairs is significant only at 6/6
   (power 53 % if Smart Lanes wins 90 % of pairs); 9 pairs allow 8/9 (power 77 %).
7. **Automation, one press to "done":** preflight (map, mods, Smart Lanes settings and zone modes) -> clear the map ->
   year to 1950 (automatic, user decision) -> build -> Smart Lanes idle -> traffic log on (10 game s) + 2x -> warm-up
   -> record 20 game minutes (game time, so a pause is safe) -> stop, 1x -> screenshot tour -> `[SQST] BENCH_DONE`. Then `make bench` writes
   the draft RESULTS.md entry (per-test tables, treatment checks, verdict deltas, cross-run pooling).
8. **Smart Lanes must add one zone mode (`sl_keeplights`) and four log / state fields** (section "What Smart Lanes
   must add"); everything else is Stress Test and tools.
9. **Rig nodes never change lanes inside a zone.** Found while writing this: in run 6 Smart Lanes rewrote every 2-lane
   arm end of the SL twins (where the arm meets the 3-lane link) with its lane-drop rule, the game twins kept the
   rig's fan (section "A confound in runs 5 and 6"). The bench keeps link lanes = arm lanes and moves every lane
   change to the town entry, outside all zones.

## What carries over from the Lights showcase, and what changes

| part | today (Lights showcase) | bench |
|---|---|---|
| Square layout | lit X / T at 90 deg, rotation 0, towns on the axes at one distance (`drawGroup` square, `axisUnit`) | same for every bench type; a type qualifies only if its arms are multiples of 90 deg (ring with 3 (T) or 4 arms, channelized T / X, diamond / parclo / ring interchanges, lit X / T, lane drop). Magic Roundabout (72 deg) and Y / 5 / 6-arm rings are not bench types yet |
| Town size | Medium (8 x 8 blocks, 600 m), x1 by capacity for 400 people (`growFactorForCap`) | same; a test may set its own `pop` (the saturated load level of test 5), identical in its twins |
| Town entries | 3-lane `highway_new_large` roundabout replacing the side-middle node, inward arm by pre-check ladder, locked ~2 s after the build | unchanged for every town (the lock timing fix of the other agent included); highway arms reach the entry through a merge piece (below) |
| Links | country large (`ENTRY_LINK_LANES` 6) from the arm end to the entry's outer arm | **the arm's own lanes** (`linkLanes = "arm"`): no lane change at the arm end, so no rig node with a lane change inside a zone; the 2 -> 3 change happens at the entry's outer arm, ~540 m out, where Smart Lanes' global rules treat every twin alike |
| Rig lane fan (`nc.pattern`) | at two-street joints of different widths | unchanged; with links at arm lanes it only acts at the entries (outside zones) |
| Zones and modes | `showcaseZones` -> `slzones.sendSet` -> ack (`zrun`) | unchanged, plus per-test modes (a test lists its own twins), the `test=` label on zone lines, and a preflight that knows which modes the installed Smart Lanes accepts |
| Twin matching | `match=no reason=redrawn|town|link|entry` per set (`showcaseMatch`, `lostEntries`, `zone_match`) | unchanged; adds `reason=lights` (a test-2 set whose sl_keeplights twin ended with no lit node: nothing to compare) |
| Positions | `alternateTwins` rotates twin order per set | unchanged (the packer places a set's twins next to each other in the rotated order) |
| Timing / summary | `timing ... total=`, `finished in X min` | unchanged; the orchestrator hooks the "finished" point |
| Traffic log | user turns it on | the orchestrator turns it on, sets the interval and the speed, stops it |

## Towns: the fewest a test needs, and why twins never share them

**Rule: one town per arm whose movements the test needs; every other arm stays a dead-end stub (or is absent).**

| type | arms | towns | why |
|---|---|---|---|
| Roundabout, 4 arms | N E S W | 4 | every entry / exit of the ring carries traffic |
| Channelized T | E N W | 3 | all three arms |
| Diamond | E W (highway), N (cross road) | **3** | with towns W, E, N every ramp and both ramp terminals carry traffic: W->N takes the eastbound off-ramp and both terminals, N->E the eastbound on-ramp, E->N and N->W the westbound pair; a south town would add only N<->S through trips. The S arm stays a stub |
| Parclo / ring interchanges (later sheets) | per layout | 3 or 4 | the arm set that uses every ramp (worked out per layout in phase 2) |
| Lane drop (new crossing shape) | E W | 2 | one road: 3+3 lanes on one side, 2+2 on the other |
| Lit crossroads | N E S W | 4 | as today |
| Lit T | E N W | 3 | as today |

**Can twins or tests share towns without coupling the A/B?** Considered: a town between two twins, linked to both
(each twin's facing arm into the town's two facing entries), "feeding both symmetrically". It saves about a quarter of
the towns of a row of twins, but it couples the twins three ways:

1. **One network.** A shared town joins the two twins' road networks. A resident of twin A's far town can now drive
   to twin B's far town through both junctions: traffic in series, so B's queue changes A's flow and A's measured
   cars include B's traffic. With every town shared in a chain, the whole map is one network.
2. **Demand follows performance.** The shared town's residents pick destinations among every reachable building;
   whether TF3 weighs that by travel time is not verified, but if it does, the faster twin attracts more trips and
   loses part of its advantage (the bias is towards "no difference"). With route choice, cars would also route around
   a slow junction through the other twin.
3. **A shared bottleneck.** Both twins' traffic uses one town grid and its entries; a backlog from one twin's arm
   (the twins were jammed in runs 2-4) blocks the other twin's cars in the shared grid.

None of these is symmetric in a way that cancels: each pushes the two twins' numbers towards each other or mixes
them. Sharing between *tests* has the same problems and also mixes two questions. **Recommendation: never share.**
The only coupling left between isolated twins is global (one simulation, one CPU budget, one sampler), which every
twin gets alike at the same moment, the reason the twins run together at all.

## Layout: point-clearance packing

Today (`fitSet`) every group keeps a circle R = farthest town + its clearance (R = 1509 m for a lit X: the four
towns at 713 m are pushed out to 884 m so two neighbours keep 1250 m; 884 + 625 = 1509). Circles waste the plus
shape's empty corners. The bench packer checks what actually matters, with the clearances the current code already
uses:

| rule | value (Medium towns) | source |
|---|---|---|
| town centre to town centre (any two towns) | 1250 m (2 x 0.35 x 1500 + 2 x 100) | `showcaseTownDists` |
| junction centre to another group's town | reach + 625 m | town clearance |
| a link (junction -> own town) to another group's town centre | >= 625 m | grid half 300 + entry 80 + gap |
| a link to another group's junction | >= reach + 400 m | keeps foreign roads out of `r_measure` (r + 200) and the 30 m corridors |
| two links | do not cross, >= 100 m apart | |
| map margin | town centres and junctions >= 400 m inside (`MAP_MARGIN`) | |

Placement: first fit, rows top to bottom and left to right on a 100 m grid, sets in spec order, a set's twins
placed one after another (each at the first spot that clears everything placed); an occupied-cell grid (1250 m
buckets of placed towns and links) keeps each candidate check to its neighbours, so a 20 km map is about 37k
candidates x a few dozen distance checks (target < 0.5 s in game Lua; measured in phase 1). Deterministic: the same
map size and spec always give the same layout (no random draw; the seed only names the run).

**Capacity** (offline estimate: a throwaway Python first fit with exactly the rules above, 100-200 m steps, not
committed; phase 1 pins the real numbers in tests):

| footprint | towns | town distance | 16 km map | 20 km map | today's circles (16 / 20 km) |
|---|---|---|---|---|---|
| 4 arms, reach <= 259 m (lit X, ring, channelized X) | 4 | 884 m | 35 | 54 | 25 / 36 |
| 3 arms (lit T, channelized T, diamond with 3 towns) | 3 | 884 m | 40 | 73 | 25 / 36 |
| 4 arms, reach ~320 m (ring interchange, parclo S) | 4 | 945 m | 32 | 50 | |
| 2 arms (lane drop) | 2 | 713 m | 71 | | |
| the two sheets below | | | sheet 2: 38 of 45 | sheet 1: 66 of 66; sheet 2: 45 of 45 | |

Interchanges at the largest params (parclo scale 3, reach 505 m) need ~1130 m town distances: give such variants
their own sheet. **Twin positions:** a set's twins sit next to each other (same terrain, same part of the map) in
the order `alternateTwins` rotates per set, so over a test every twin mode is placed first, second and third equally
often. On a flat Blank Slate with isolated networks position should not matter; the rotation makes sure of it.

## Statistics

**Pairs per question.** The verdict stays the two-sided sign test over pairs (robust, no distribution assumed).
Critical counts and power (q = the chance one pair favours the better mode):

| pairs | significant at (p <= 0.05) | power q = 0.7 | q = 0.8 | q = 0.9 |
|---|---|---|---|---|
| 6 | 6/6 (p 0.031) | 0.12 | 0.26 | 0.53 |
| 8 | 8/8 (0.008) | 0.06 | 0.17 | 0.43 |
| 9 | 8/9 (0.039) | 0.20 | 0.44 | 0.77 |
| 12 | 10/12 (0.039) | 0.25 | 0.56 | 0.89 |
| 15 | 12/15 (0.035) | 0.30 | 0.65 | 0.94 |

So 9, 12 and 15 are the efficient counts (7, 8, 10, 11 add towns but no power). Primary questions get 9 sets where
the map allows, 6 at least. Run 5's 11/12 at +3.5 km/h corresponds to q around 0.9.

**One shape per test vs mixed.** A test answers one question. Homogeneous (one variant in every set) when the
question is about a junction ("does Smart Lanes beat the game at a 2-lane roundabout"): 9 pairs give a verdict for it.
Mixed (a variant list cycling over the sets) only when the question is about a family ("the free kerb turn on lit
junctions in general"); the report then shows per-variant rows as trends, never verdicts. Never pool across tests.

**Correlated comparisons.** In a three-twin set both comparisons use the same sl twin: each is a valid paired test on
its own, but they are not independent (don't combine their p values).

**Many questions per sheet.** About 8 comparisons per sheet at 0.05 means one false positive every two sheets.
The report adds a Holm-adjusted p column per sheet; a default changes only on p_Holm <= 0.05 or a replication in a
second run.

**Pooling across runs.** Pairs of the same test with the same spec version (logged `spec=<id>@<n>`) on different
maps are independent, so the report keeps a ledger (`plans/square_smart_lanes/bench_ledger.json`, one row per pair:
session, test, compare, deltas) and shows "this run" and "all runs of this spec" side by side. Two 6-pair runs give
the power of 12.

**Secondary statistics** (shown, not verdicts): Wilcoxon signed-rank p (uses the size of each delta; with 6 pairs
also 0.031 at best, but 5/6 with one small loss can reach 0.06), and a bootstrap 90 % interval of the mean delta.

**Metric by load.** Unsaturated, both twins pass the same demand, so `thru/min` is equal by construction and speed /
standing / queue measure the junction's delay. Saturated, speed mostly measures queues (runs 2-4) and `thru` is the
right measure. So test 5 is a **load level**, not a junction set: once `thru` reads, a later sheet repeats a test's
sets at `pop = 1000` (x2.5 by capacity) next to the 400-people sets, and the report judges thru there. A run whose
map-wide standing exceeds 50 % is flagged "saturated" in the draft.

## Junction types: what each needs

| type (construction) | params (bench variant) | arms / roads | towns | lights | zone r | special |
|---|---|---|---|---|---|---|
| Roundabout `square_roundabouts.con` | round, 2 ring lanes, radius S, 4 arms, no splitter, no tram, signals Off (the game's AUTO decides), arm road country medium | 4 two-way | 4 | AUTO (from 1950) may light the ring's arm junctions; the bench logs `lit_nodes=` per twin after the settle | reach 103 + 20 | test 2 needs lit ring nodes: if AUTO lights none at this variant, phase 2 switches the arm road to country large (gate) |
| Channelized T `square_roundabouts_channel.con` | layout T, scale 1, slips "near-side corners", no splitter, arm length 1, main and side country medium | 3 two-way | 3 | centre: AUTO; slip nodes: Smart Lanes removes (setting On) | 149 + 20 | |
| Diamond `square_roundabouts_highway_diamond.con` | scale S, ramps short, arm length 1, highway 2 lanes per carriageway, cross road country large (`SHOWCASE_IX_CROSS`) | E / W: highway carriageway pairs (one-way each), N / S: two-way | 3 (W, E, N) | terminals: AUTO (Smart Lanes keeps crossroads / T lights); gores: none | 234 + 20 | **new link path**: each highway arm's carriageway pair runs on as a pair to a merge node near the town entry (>= r + 200 m from the junction, outside the zone and the measured corridors), then one two-way country medium (2+2: the highway's lanes) into the entry's outer arm. The FLOW corridor of a highway arm is 60 m wide (both carriageways), not 30 |
| Lane drop (new `square_stress_test_crossing.con` shape 4 "Lane drop") | main country large (3+3) on the W arm, main2 country medium (2+2) on the E arm | 2 two-way | 2 | none | 88 + 20 | eastbound 3 -> 2 drop, westbound 2 -> 3 gain at the one node (Smart Lanes case D); links keep each arm's lanes |
| Lit crossroads (shape 1) | 2x2, 3x3, 3x2 as `LIGHTS_SHAPES` | 4 two-way | 4 | Yes (forced, as today) | 88 + 20 | links at arm lanes (was country large) |
| Lit T (shape 2) | T 2x2 | 3 two-way | 3 | Yes | 88 + 20 | |

Every construction param index is resolved in phase 1 from the construction's own value list (the test asserts the
label, e.g. `sqrb_arms` index 3 = "4").

## A confound in runs 5 and 6 (found while writing this; not in RESULTS.md yet)

Session `2026-10-13_0447_top-up-726115` has exactly 26 `[SQRL] APPLY kind=drop ... case=D` lines
(`lanes=3_->_2;_2_->_3 before=6 after=6`): that is the number of 2-lane arm ends in that run's Smart Lanes twins
(2x2 X: 2 sets x 2 SL twins x 4 arms = 16; 3x2 X: 1 x 2 x 2 = 4; T 2x2: 1 x 2 x 3 = 6). The arm end (2 lanes) meets
the 3-lane link at a construction node inside the zone (zone r = 108 m, arm end at 60 m): in sl / sl_exitfan zones
Smart Lanes wrote its lane-drop rule there, in game zones it left the rig's fan. Whether the two layouts differ is not
known (both 6 connections). So the sl vs game deltas of the 2-lane shapes include that joint; the 3x3 X (no lane
change at its arm ends) had the biggest Smart Lanes gain, so the main verdict does not hinge on it. To check:
compare those nodes' connections (a node-config dump of one sl and one game arm end). The bench removes the joint.

## The spec format

Pure data in a new module `stress/stress_bench.tl` (types in `stress_types.d.tl`), compiled to a
`SquareStressShowcaseSpec` plus a layout:

```lua
-- one test = one question (or two, with a three-twin set)
{ id = "rb4",                         -- [%w_], short: the `test=` key (zone ids stay g<set><letter>)
  title = "Roundabout, 2-lane, 4 arms",
  kind = "rb",                        -- zone kind (rb / ix / plain)
  variants = { { file = "square_roundabouts.con", label = "RB4 2L",
                 params = { sqrb_shape = 1, sqrb_lanes = 2, sqrb_radius_size = 1, sqrb_arms = 3, sqrb_splitter = 1,
                            sqrb_tram = 1, sqrb_signals = 1, sqrb_island = 1, sqrb_arm_type = 5 } } },
  towns = { "N", "E", "S", "W" },     -- the arms that get a town (compass points of the arms, rotation 0)
  twins = { "game", "sl", "sl_keeplights" },
  compare = { { "sl", "game" }, { "sl", "sl_keeplights" } },   -- logged; drives the report's tables
  sets = 6,                           -- wanted; the planner may place fewer (logged, the report says so)
  priority = 1,                       -- lower first when the map runs out
  pop = 400,                          -- people per town (growFactorForCap), the same in every twin
  linkLanes = "arm",                  -- or a lane count
  lights = "game",                    -- "yes" (forced, lit crossings), "game" (AUTO), "off"
  needs = { year = 1950, sl = { lights = "on" }, modes = { "sl_keeplights" } } }
```

A **sheet** = `{ id, title, version, map = { minKm }, record = { warmupS, recordS, interval, speed }, shots, tests }`.
`bench.plan(w, h, sheet)` returns the layout (sets per test placed / wanted, towns, groups, estimated persons /
drivers / build minutes, the cut tests) without building; the Bench window shows it before the press, and a unit
test prints it for 16 and 20 km. `bench.compile(sheet, layout)` gives buildRun its spec: kinds = test ids, types =
the variants, per-kind modes (new `SquareStressShowcaseType.modes`, read by `showcaseModes`), per-type link lanes,
town arms and pop.

**Presets** (same module): `sheet1` and `sheet2` below, and `lights_mixed`, the current Lights showcase as one test
(variants 2x2 X, 3x3 X, 3x2 X, T 2x2; 3 sets each; sl / game / sl_exitfan), which must reproduce its counts (zones,
towns, by_ab) before the old button may go. The main Showcase (random draws, bus lines, non-square, no entries)
stays on its own path; it is not a bench.

## The first bench: three sheets for tests 1-4 (16 km Blank Slate, every one)

Placed by the real packer (`stress_bench.plan`, tests/square_stress_test/test_bench.lua pins the numbers):

| sheet | test | junction | twins | sets | groups | towns | answers |
|---|---|---|---|---|---|---|---|
| 1 | `rb4` | Roundabout, 2-lane ring, radius S, 4 country medium arms, signals Off (the game's AUTO lights) | game, sl, sl_keeplights | 9 | 27 | 108 | test 1 (rings, 9 pairs), test 2 (rings, 9 pairs) |
| 1 | `drop` | Lane drop: country large (3 + 3) W arm, country medium (2 + 2) E arm, one node | game, sl | 6 (8 at most) | 12 | 24 | test 1 (lane drops, 6 pairs) |
| | | | | | **39** | **132** | ~53k people, ~11 min build |
| 2 | `cht` | Channelized T, scale 1, near-side slips, country medium | game, sl, sl_keeplights | 9 | 27 | 81 | test 1 (slip lanes, 9), test 2 (slip nodes, 9) |
| 2 | `dia` | Diamond S, highway M (2 lanes a carriageway), country large cross road; towns W, E, N | game, sl | 6 (the most) | 12 | 36 | test 1 (interchange + ramps, 6) |
| | | | | | **39** | **117** | ~47k people, ~10 min |
| 3 | `lt22` | lit T 2x2 | sl, game, sl_lock | 9 | 27 | 81 | test 4 (T sl vs game, 9), test 3 (T part) |
| 3 | `lx` | lit X 2x2 / 3x3 / 3x2, one each | sl, game, sl_lock | 3 (the most) | 9 | 36 | test 3 (with lt22: 12 sl vs sl_lock pairs on mixed shapes); X sl vs game 3 pairs (trend only) |
| | | | | | **36** | **117** | ~47k people, ~10 min |

Each sheet: ~10-12 min build, Smart Lanes idle ~15-60 s, warm-up 180 game s + record 1200 game s at 2x (~11 wall
min), screenshots ~1 min: about 25 minutes hands off. Sheet 1 needs the Smart Lanes with `sl_keeplights` (SL-1) and
"No lights at roundabouts and ramps" On; sheets 1 and 2 need Roundabouts & Interchanges; sheet 3 only Smart Lanes.
"Without a jam" (test 3): 400-people towns ran at ~23-45 % map-wide standing in runs 5-6; the draft flags over 50 %.

## Automation, end to end (as built)

**Towns tab > Bench: one button per sheet** ("Sheet 1", "Sheet 2", "Sheet 3"). A press first checks what it can
(another test running, nothing fits the map, Roundabouts & Interchanges missing, Smart Lanes absent, Smart Lanes'
"Apply automatically" Off, sheets 1-2: "No lights at roundabouts and ramps" Off): any of it is one dialog and nothing
happens. Else a confirm dialog with the plan for this map ("39 junctions, 132 towns (~53k people), about 11 min to
build; 16.0 x 16.0 km map: everything fits") and what the run does; "Run bench" starts it. Module
`gui/stress_bench_run.tl`, a state machine on the rt tick hook (Main Thread, polled every 250 ms, every step pcall'd),
every transition one `[SQST] BENCH_PHASE sheet= phase= gt= ms=` line:

| phase | what | next when |
|---|---|---|
| ack | Keep balance on; `slzones.sendClear("bench_preflight")` (a clear with our run id, valid for every Smart Lanes). A paused game is refused before this (dialog: unpause) | Smart Lanes stored that run id (`zrun`): then its `zmodes` are read; a sheet mode it lacks (or no `zmodes`: an older Smart Lanes) ends the run (`BENCH_ABORT`, dialog) before anything is removed. No answer in 5 s: abort ("game paused? an older Smart Lanes?"). Else `[SQST] BENCH_START ...` |
| clear | Remove towns > All towns (existing code), then Remove all roads (existing code; only when streets are left) | no `remove_*` job queued (10 min at most) |
| year | before 1950: `makeGameSetDateCmd(1950-01-01)` (user decision: automatic), logged `bench year 1950 success= year now Y` | its answer, the year re-read: still before 1950, or no answer in 30 s: abort |
| build | `jn.buildBench(sheet, seed)` = buildRun with `bench.spec(sheet)` (the zones ack refused or timed out: the build stops at once and the run aborts, `jn.onRunAborted`): towns, grids, locks, entries, junctions, settle, **Smart Lanes idle** (qlen 0 twice 2 s apart, 30 s at most: `bench_s1 smart_lanes idle=`), the reads (zone lines with `test=`, `BENCH_TWIN` lit counts), joins, links, lock pass, growth to 400 | `jn.onRunFinished` (after the run's `finished in X min`). Watchdog: no log line for 10 min, or 90 min in all: abort |
| sl_idle | Smart Lanes idle again (its late looks after the links, SL-6), 60 s at most | idle |
| warmup | Keep traffic cleared off; traffic log restarted at 10 game s (`bench.INTERVAL`); speed 2 | 180 game s; a skipped sample (a sweep missed its interval) at 2x: speed 1, the sampler restarted, the warm-up again (once) |
| record | nothing: game time counts, a paused game waits | 1200 game s |
| stop | traffic log off (`FLOW_SUMMARY final=1`), speed 1 | at once |
| shots | a primer `takeScreenshot(1)` (the first of a session writes no file), then per test every twin of its first set: `setCameraData` 450 m over the junction (the camera's angle and pitch kept), 2.5 s, `takeScreenshot(1)`, one `[SQST] BENCH_SHOT n= id=<test>:<zone> x= y=` each, 4 s apart | the last shot |
| done | `[SQST] BENCH_DONE sheet= spec= seed= ok=yes samples= speed= minutes= problems=`; the window says `Bench s1 done (seed N): tell Claude "done" (make bench).` | |

Abort: Clear queue, an error in a step, a build that did not start, a timeout: `[SQST] BENCH_ABORT sheet= phase=
reason=` and a dialog; the traffic log goes off and the speed back to 1x. While a run is active every other build and
removal button (Test grid, Spawn, Grow, Crossing / Junction test, both Showcases, Remove towns, Remove all roads) says
so in a dialog and does nothing, and buildRun refuses anything but the bench's own build. A reload ends the run silently (the orchestrator is GUI state). Not built: `app.saveGame`
after the build (open question), copying the screenshot files (the game logs `Screenshot: wrote <path>`; the report
counts the BENCH_SHOT lines).

**Thru by position** (FLOW.md "thru"): the path elements still read nothing in game, so `thru` now counts by
position: a car seen on an inbound approach (the inbound side of an arm's corridor, out to the zone's `approach` =
the straight link up to just before the town entry: 518 m at 884 m town distance, 347 m for the lane drop) or in the
junction at one sample, and not there at the next, has passed (it is out an exit, beyond, or no longer driving: no
car on an approach arrives anywhere before the junction). At 10 game s per sample every car spends more than one
interval on its approach, so each is seen whatever the twin's speed (no bias towards the slower twin). The path count
stays as `thru_path` and stops for the run after 2000 unreadable path elements (`FLOW_PATHOFF`). Interchange
corridors are 25 m to each side (both carriageways).

**`make bench [LOG=...]`** (default `LOG=last-bench`): `game_logs.py save`, then `tools/bench_report.py`:
- the last `BENCH_START` in the log and everything after it; the run's state (complete / aborted in phase X /
  incomplete);
- per test and comparison (`BENCH_TEST compare=`): pairs, mean delta km/h, W/L/T, sign p, Holm p over the sheet,
  Wilcoxon p, standing pp, thru/min with its W/L; per pair km/h, standing, queue, thru; excluded pairs with reasons
  (flow_report's `match=no` / missing twin, plus **treatment**: an sl-type twin without a Smart Lanes `APPLY ...
  zid=`, a game twin with one, an sl_keeplights twin with neither a `LIGHTS ... to=kept` nor a lit node);
- per test and twin mode: applied / skipped / lights off / kept / lit at the read;
- sampler health after the record started: map-wide standing (over 50 %: "SATURATED"), capped / strided samples,
  FLOW_TARGET lines, the busiest frame, whether the path thru was off;
- pooled with every earlier recorded run of the same spec (`plans/square_smart_lanes/bench_ledger.json`);
- suggested verdict lines; writes `.cache/bench/<session>.md` and prints it. `ARGS=--record` (only for a run with
  `BENCH_DONE ok=yes`) appends the pairs to the ledger and the entry under RESULTS.md "## Runs".
- `game_logs.py`: a session with a `BENCH_START` is named `..._bench-s1-<seed>` and matches `last-bench`. Caveat: a
  session archived before its bench started (the SessionStart hook ran mid-session) keeps its first name; it still
  matches `last-bench` once re-archived (its entry carries `bench`), else pass `LOG=<session name>` (`make logs-list`).
  Several sheets in one session: the report reads the last `BENCH_START`; the ledger and RESULTS.md key a run by
  session + sheet + seed.
- flow_report: a zone line with `test=` makes its test the kind (`test:rb4`), so every table groups per test, and the
  `all` row (pooled across tests) is left out for a bench.

**What the user does:** a fresh 16 km Blank Slate with Stress Test, Smart Lanes and (sheets 1-2) Roundabouts &
Interchanges on; Towns tab > Bench > Sheet N; "Run bench"; leave the game running (unpaused, in front) ~25 min; when
the Bench status says done, say "done" (TESTING.md 6W).

## Log contract additions (FLOW v3: keys and line kinds only added; as built)

- `[SQST] BENCH_START sheet=s1 spec=bench_s1@1 seed= map=WxH tests= groups= towns= year= sl_auto=on|off sl_lights=on|off
  sl_free_turn= sl_phases= sl_modes=<Smart Lanes' zmodes> warmup_s= record_s= interval_s= speed=`, then one
  `[SQST] BENCH_TEST sheet= id= title= kind= variants= twins= compare=sl:game,sl:sl_keeplights sets=placed/wanted groups=
  towns= towns_per_twin= pop= lights=game|yes` per test (logged by the build's first line too: `bench_s1: seed= ...`).
- `[SQST] BENCH_PHASE sheet= phase=ack|clear|year|build|sl_idle|warmup|record|stop|shots gt= ms= [extra]`,
  `[SQST] BENCH_TWIN id= test= ab= nodes= lit_nodes= phase=read` (each twin's junction nodes and the lit ones at the
  read), `[SQST] BENCH_SHOT sheet= n= id=<test>:<zone> x= y= ok=`, `[SQST] BENCH_DONE ...`, `[SQST] BENCH_ABORT sheet=
  phase= reason=`, `[SQST] bench_s1 smart_lanes idle=yes|timeout|absent|unread ms=`.
- `showcase zone`: `test= variant= approach=` appended (approach also on Lights showcase zones: square layout);
  `FLOW_ZONE`: `approach= test=` appended; `FLOW`: `thru_path=` appended (`thru` now by position); `FLOW_START`:
  `thru_m=pos ix_corridor_m=50`; new `FLOW_PATHOFF run= tries=`.
- Zone ids: `g<set><letter>` as today (sets numbered across the sheet; pair `g<set>`), letter `f` for
  `sl_keeplights`; `by_ab` ends `,sl_keeplights:<n>` (only when > 0, after `,sl_exitfan:<n>`).

## What Smart Lanes must add

| # | what | why |
|---|---|---|
| SL-1 | zone mode **`sl_keeplights`**: as `sl` (lanes, free kerb turn and light phases as the settings), but no light is switched off in the zone (ring arm junctions, slip / ramp nodes), in the automatic pass and the tool; one `LIGHTS src=auto node= to=kept zone=sl_keeplights` line per node it would have switched off; `SUMMARY ... zone_keeplights= lights_kept=`; `by_ab ...,sl_keeplights:<n>`; accepted by `sl_zones.lua` (AB_SET, AB_OPTIONAL) | test 2: the setting is load-time and acts at build time, so neither a reload A/B nor a second map isolates it; twins on one map do |
| SL-2 | `[SQRL] MODE ... lights=on|off` (the "No lights at roundabouts and ramps" setting) | the report must know what the sl twins ran with |
| SL-3 | `zid=<zone id>` on APPLY, SKIP (kind=zone), LIGHTS, PHASES and AUDIT lines of nodes in a zone (the stored label) | treatment check per twin without matching node ids by position |
| SL-4 | in the game-script state next to `zrun`: `zerr` (the last refused payload's run and reason) and `zmodes` (the ab names it accepts) | preflight fails fast with "Smart Lanes does not know sl_keeplights" instead of `ack=timeout` and a silently untreated sheet |
| SL-5 | `qlen` in the same state: jobs + light queue + pending verifies | the bench waits for Smart Lanes to finish 60+ junctions instead of a fixed settle; links into nodes with a pending light change are refused (findings roads.md "pending traffic light change") |
| SL-6 (check) | a ring or slip node whose AUTO light appears after Smart Lanes' pass: is it switched off later (a re-check like the free-turn one)? If not, add one for sl zones | otherwise late AUTO lights stay in the sl twins and test 2 compares lit with lit |

Smart Lanes needs nothing new for tests 1, 3 and 4 (`game`, `sl`, `sl_lock` exist; the lane drop is its case D).

### As implemented in Smart Lanes (2026-10-13, rev 4, offline tests only; tests/square_smart_lanes "SL-")

Choices where the table above left room are marked (choice).
- **SL-1** `sl_keeplights`: accepted (sl_zones `M.AB` = game, sl, sl_phases, sl_fan, sl_lock, sl_exitfan,
  sl_keeplights); `by_ab` appends `,sl_keeplights:<n>` after `,sl_exitfan:<n>`, only when n > 0 (Stress Test
  `stress_logic.slZonesByAb` must add the same, last). Lanes, free kerb turn and light phases as `sl`. A node there
  that "No lights at roundabouts and ramps" would switch off (ring arm junction, slip / ramp node, Lights.needs:
  preference not NO or a light standing) logs `[SQRL] LIGHTS src=auto node=<n> to=kept zone=sl_keeplights [zid=<id>]`
  (tool: `src=tool`) and is not sent. With the setting Off nothing is logged (nothing would be switched off).
  `SUMMARY ... zone_keeplights=<job nodes in such zones, any kind> lights_kept=<to=kept lines>` only when the first
  is > 0, after `zone_exitfan=` / `exit_fan=` and before `free_turn=`. The tool's Reset still gives AUTO back there.
- **SL-2** `[SQRL] MODE phases=<game|sl> free_turn=<off|safe|always> lights=<on|off>` (lights= appended last).
- **SL-3** `zid=<id>` appended last to APPLY, SKIP, LIGHTS, PHASES and AUDIT lines that carry a numeric `node=` lying
  in a zone with a valid id label (the zone found as everywhere: nearest centre relative to its radius), in the
  automatic pass and the tool (also the write path's LIGHTS / PHASES lines). Lines without `node=` (WRITE, VERIFY,
  SUMMARY) get none. (choice) `SKIP kind=zone zone=game job= nodes= reason=zone_game zid=<ids>`: the sorted,
  comma-separated distinct ids of the game zones its nodes lie in (one line per job covers many nodes); none without ids.
- **Unchanged nodes (2026-10-13, inside zones only):** every node a job looked at and left as it was logs once per
  job and node `[SQRL] SKIP kind=<ring|cross|slip|drop|node> [ring=<ring key>] node=<n> reason=same|plain [zid=<id>]`:
  `same` = its lanes already are the rule's (ring junctions `kind=ring ring=<key>`, crossroads / T `kind=cross`,
  slip nodes `kind=slip`, lane drops `kind=drop`); `plain` = nothing to do there (`kind=node`: a plain road node, a
  dead end, a junction kind the rules do not handle; plain ring nodes `kind=ring ring=<key>`). A node in a zone
  appears on exactly one of APPLY / SKIP (incl. these) per job it was seeded in; game-zone nodes keep their
  `SKIP kind=zone ... zid=<ids>`. Outside every zone no such line (the default logs are unchanged).
- **SL-4** state fields next to `zrun`: `zmodes` = the list of accepted ab names (`M.AB`, in that order); `zerr` =
  `{ run = <the refused payload's run id, or "-" when it had none or an invalid one>, reason = <validate reason,
  e.g. "ab1", "run", "too_many"> }`. (choice) Both are written only when a zones event arrives (accepted or refused),
  never at load: an ordinary save's state stays as before. Preflight: send `{ op = "clear", run = <id> }` (valid
  for every Smart Lanes), wait for `zrun == <id>`, then read `zmodes` (absent: a Smart Lanes without SL-4). After a
  `set`, `zrun == run` means accepted; `zerr.run == run` means refused (`zerr` stays until the next refusal).
- **SL-5** `qlen` in the same state = our GUI's last report (`qgui`: job in progress + waiting jobs + lights-off
  entries + verifies and re-checks + refused parts to retry + proposals awaiting their answer + nodes held by one)
  + the jobs in the state the GUI had not taken at that report (`qseen` = the last job seq it took). The GUI
  reports through our own script event `SmartLanes.qlen` (`{ qlen, seen }`) when the value changes, at most once
  per 30 GUI frames, so a reading lags by up to ~0.5 s plus the event round trip; a build sets `qlen` at once
  (its job counted). (choice) Only while zones are set (plus one last report after a clear until it said 0): outside
  the bench nothing is sent or stored. Re-checks (60 / 600 frames after a write) and SL-6's late look (600 frames
  after a lights-off) count, so idle comes ~10-12 s after the last build. The tool's own writes (another Lua state)
  are not counted. The bench's "qlen = 0 twice 2 s apart" therefore works; keep the 30 s fallback.
- **SL-6** answer: a node Smart Lanes switched off gets preference NO, and the game adds AUTO lights only at AUTO nodes,
  so a late AUTO light cannot appear there; the existing `VERIFY kind=lights off= nodes= gone=` checks it 30 frames
  later. Missed cases: a refused or timed-out light proposal, or a node whose config another proposal replaced. So
  (added, zones only): 600 GUI frames after each lights-off entry, one late look at its nodes that lie in a zone:
  every node the setting still switches off (not busy, not in an sl_keeplights zone) gets one more lights-off,
  logged `RECHECK kind=lights job=<key> nodes=<looked at> lit=<still lit> queued=<switched off again>`. The late
  entry has no late look of its own (bounded, no loop). Outside zones: unchanged (no late look).

## As built (2026-10-13; files)

- `stress/stress_bench.tl` (new, pure): sheets and variants, the point-clearance packer (`plan`, memoised per map and
  sheet; ~0.8-1.2 s for a 16 km sheet in the offline Lua 5.4), `spec` (the Showcase spec with `layoutFn`), the
  preflight (`slSettings`, `problems`), `testLine`, `startLine`, `planText`.
- `gui/stress_bench_run.tl` (new): the run state machine above; `gui/stress_hud.script.tl`: the Bench section.
- `gui/stress_junctions.tl`: `buildRun` takes `spec.layoutFn`; per-group link lanes (`linkLanes` 0 = the arm's own,
  `pairLanes` for a highway arm's merge piece); per-group forced lights (`litYes`); bench `BENCH_TWIN` lines and lit
  counts at the read; the settle waits for Smart Lanes idle (bench); `jn.buildBench`, `jn.onRunFinished` (called after
  the timing line); job prefix `bench_` in `rt.TEST_JOBS`.
- `gui/stress_slzones.tl`: `sendClear` returns its run id; `modes()`, `refused()`, `qlen()`, `waitIdle()`; `waitAck`
  answers `refused:<reason>` when Smart Lanes' `zerr.run` is our run.
- `stress/stress_logic.tl`: `sl_keeplights` in `SL_ZONE_AB` and `slZonesByAb` (last); `TEST_TOWN_MODES` "Keep lights";
  crossing shape 4 arms; `groupApproach`; zone lines' `test= variant= approach=`; layouts carry `square`.
- `stress/stress_crossing.lua`: shape 4 "Straight" (no side road; main2 on the east arm: the lane drop).
- `stress/stress_flow.tl`, `gui/stress_flow_log.tl`: thru by position (`approachOf`, `posCount`), `thru_path`,
  `FLOW_PATHOFF`, `FLOW_START thru_m=pos ix_corridor_m=50`, `FLOW_ZONE approach= test=`, wider ix corridors,
  `fl.counts()`; twin letter `f` for sl_keeplights.
- `tools/bench_report.py` (new), `tools/flow_report.py` (sl_keeplights, `test:` grouping), `tools/game_logs.py`
  (bench slug, `last-bench`), Makefile `bench`.
- Tests: tests/square_stress_test/test_bench.lua (plan, clearances, rotation, spec, zones, lines, preflight, the run
  with stubs: every phase, pause, step-down, aborts), test_showcase.lua (sheets 1 and 2 built end to end on the fake
  api: entries, links at arm lanes, diamond pair merges into country medium, configs complete, no -0, BENCH_TWIN,
  the finished hook; variant params against the construction files' labels), test_flow.lua (thru by position, the
  path give-up), tests/tools/test_bench_report.py.

## After sheets 1 and 2 (2026-10-13, session `2026-10-13_0610_session`)

- **Thru:** the path elements read in game (`elem.edgeId.entity`, docs/findings/lines-vehicles.md); the positional
  count matched the path count within 1 % (52117 vs 51709, 62503 vs 62431). A bench record now runs without path reads
  (`fl.pathThru = false`, `FLOW_START ... path_thru=off`; back on after the run or an abort); other traffic logs keep
  `thru_path`. The street re-read for the path count is skipped then, else at most 2 zones a frame.
- **Sampler cost (sheet 1):** ~22k drivers, 370 ms busy in 171 frames per sweep (~16 us per driver with path reads),
  2.0 s wall median of the 5 s a 10 game s sample has at 2x: 10 s / 2x stays. Frame spikes (busiest frame median 14 ms,
  max 76 ms; sheet 2: 23.8 ms) are now attributed: `FLOW_ALL ... frame_phase=<phase of the sweep's busiest frame>`;
  the scan now checks the clock after every driver near a zone, whatever it read.
- **Log fixes:** `BENCH_TEST` lines after `BENCH_START` (the first runs had none: bench_report derives the tests from the
  zone lines then, and still does as a fallback); `BENCH_DONE speed=` is the record's speed (`speed_end=` after the
  stop; the first runs logged 1, the post-stop speed).
- **Geometry check:** each twin's read checks that the junction presents its test: a lane drop has a 2-street node
  whose streets differ in road lanes (`lanes=6>4`), a roundabout / channelized junction at least 3 one-way streets, an
  interchange 4. `BENCH_TWIN ... geometry=ok|bad what= ...`; a bad twin puts its set at `match=no reason=geometry`
  (zone_match lines) and in the problems dialog. The lane drop variant was right in sheet 1 (`sqst_x_main2` 6 is
  ROADS[5], Country medium: main2 / side2 are offset by one, 1 = the same road; test "bench lane drop variant"); but
  Smart Lanes logged no lane-drop write at the 6 sl twins' centres (all 120 `APPLY kind=drop` lines of the run are the
  entries' joints: 27 x 4 + 12), so sheet 1's drop result stays void until a run shows `geometry=ok` and Smart Lanes'
  line for those nodes (`APPLY kind=drop` or `SKIP kind=drop reason=same`).
- **Treatment check (bench_report):** an sl-type twin counts as treated with an `APPLY ... zid=` or a `SKIP kind=..
  reason=same|plain zid=` (Smart Lanes looked and left it); neither: excluded. Its kinds must include the test's
  junction kind (drop: `drop`; rb4: ring applies; cht / dia: `slip` or `cross`), else excluded ("saw no drop junction
  (only node)"); a `geometry=bad` twin is excluded. A test whose lines carry no `zid=` at all stays unchecked (said).
  Caveat seen in session 0610: Smart Lanes tagged `APPLY kind=slip` lines of town grid nodes far outside a zone with
  that zone's id (`zid=g10a`), so a zid alone can over-count; the kind check above narrows it.
- **Report files:** the draft is `.cache/bench/<session>_<sheet>-<seed>.md`; `--sheet s1` / `--seed N` pick a run when
  one log holds several (default: the last); the zone generation and the sampler lines are taken from that run only.

## After sheet 3 (2026-10-13)

- **Sheet 1 version 2: roundabouts only, 11 sets** (the most a 16 km map holds: 33 junctions, 132 towns). The lane drop
  test is gone: Smart Lanes logged `same` at every drop centre of session `2026-10-13_0610_session` (the game's default
  at a 3+3 -> 2+2 node already equals its rule), and no other lane drop is known to differ (no game-default dump for
  other lane counts / one-way; a probe would have to show one first). The lane drop variant and its geometry check stay
  (tests build it in a test-only sheet).
- **Zone ids carry the sheet key:** `s1g10a`, pair `s1g10` (layout `idPrefix`), so ids no longer repeat across sheets
  run in one session. flow_report's twin-id and pair sorting accept the prefix; bench_report reads ids as given.

## Compatibility

- Lights showcase and Showcase buttons, specs, job names and log lines stay as they are. The bench calls buildRun
  through a new entry point with a precomputed layout; the per-type `modes` field defaults to the spec's.
- `lights_mixed` preset: once it reproduces the Lights showcase's counts in game (phase 5 gate), the Lights showcase
  button may become that preset (the user decides).
- FLOW v3 stays v3 (keys and line kinds only added); flow_report reads old logs as before (tests with run 5 / 6
  archives).
- Zone payloads stay valid for an older Smart Lanes except with `sl_keeplights` (refused as a whole: SL-4 makes the
  preflight say so; sheets 1 and 2 need the new Smart Lanes (both have sl_keeplights twins), sheet 3 does not).

## Risks

| risk | evidence | mitigation |
|---|---|---|
| `Engine.h:323` BaseNodeConfig on config-less script nodes | roads.md "Script link roads without node configs" | every new node (the diamond's pair merge pieces included) through `stress_nodecfg`; offline `cfgProblems` on every new proposal shape |
| `VectorMap.h:11` stale `lockedLanes` | roads.md "Traffic light phases index the lane connections" | the rig never writes a lit node's config without the remap (entries: lights switched off after the join, as today); ring / channel nodes are written only by Smart Lanes |
| stale ids / "invalid entity" | entries third run; pending light change | fresh reads before every proposal (as today); links only after `sl_idle`; the other agent's entry lock timing |
| towns hanging streets on free ends | towns.md "Towns build on unlocked script streets within a minute" | entry lock in the build callback (other agent); diamond stub arms and the merge pieces locked at once (highway templates arrive locked) |
| sampler cost | run 6: 1004 ms busy in 465 frames, frame max 6.3 ms, stride 2 at ~10k drivers; run 5: 2317 ms for 22.5k with path reads | sheets sized ~200 towns (~29k drivers) until the fixed `thru` cost is measured; automatic speed step-down on a skipped sample; the draft reports stride / thru_scale |
| build time | 5.2 min for 69 towns, 7.9 for 90 | ~15-18 min per sheet, unattended; batched steps as today |
| AUTO lights absent at the chosen ring variant | 43 `light=true` vs 200 `light=false` ring LIGHTS lines in the archive | `lit_nodes=` per twin; phase 2 gate picks a variant that gets lit |
| bigger proposals (66 junctions) | none yet | link groups and batches as today; a mini sheet (1 set per test) runs first (phase 2 gate) |
| a crash late in a 30 min run | | `BENCH_PHASE` lines show how far it got; optional save after the build |

## Implementation plan (each phase in its own subagent; gates: `make check`, `make test MOD=mods/square_stress_test`, `make validate MOD=mods/square_stress_test`)

Status 2026-10-13: phases 1, 2, 4 and 5 built (one pass, offline gates green: check, 547 Stress Test tests, test-tools,
validate); phase 3 (Smart Lanes) done by its agent; phase 6 partly (the tour, no file copy); phase 0's confound check
and every in-game gate open: the first in-game run is sheet 1 itself (TESTING.md 6W).

0. **Prerequisites (other agents, now).** `thru` fix and entry lock timing land; one Lights showcase run shows
   `thru` > 0 at busy junctions and the per-driver sweep cost with path reads. Also settle the confound: dump one sl
   and one game 2-lane arm end of run 6's map, or accept and note it in RESULTS.md. **Gate:** both in a session.
1. **Spec + planner (pure, offline).** `stress/stress_bench.tl`: records, presets (sheet1, sheet2, lights_mixed),
   point-clearance packer, `plan` / `compile`, plan text. Tests (`tests/square_stress_test/test_bench.lua`): every
   clearance rule over every placed pair; capacities for 16 / 20 km at least the table's; deterministic; twins
   identical and adjacent, order rotated per set; no -0, axes exact; param labels per variant; `lights_mixed`
   counts; packer time < 0.5 s for 20 km; locals / upvalues limits. **Gate:** plan tables equal this file's (update
   the file if the real packer differs).
2. **Build path.** After phase 0's edits: buildRun takes a layout and per-type modes / link lanes / town arms /
   pop; square layout for rb / ix kinds; highway pair arms to a merge near the entry; lane-drop shape 4 in
   `stress_crossing.lua` (+ con param, geometry test with no -0); stub arms locked; `test=` / `variant=` on zone
   lines; `BENCH_TEST` / `BENCH_TWIN` lines; `lit_nodes`. Tests: fake-api builds of each new type (proposal shapes,
   `cfgProblems`, entries, links at arm lanes, the merge outside the zone, match flags incl. `lights`). **Gate:** a
   mini sheet in game (16 km, one set per test, all twins): everything built / linked / joined, zones acked, the
   treatment check by hand from the log, ring lit nodes > 0 (else change the variant), no crash. TESTING.md 6W.
3. **Smart Lanes SL-1 to SL-6** (Smart Lanes agent, in parallel with phase 2): tests in tests/square_smart_lanes,
   the payload validator, by_ab text byte for byte with the Stress Test's. **Gate:** the mini sheet shows
   `to=kept` in f zones and none in a zones.
4. **Orchestrator.** `gui/stress_bench_run.tl` + the Bench section in the HUD (plan line, one button per sheet).
   Tests with a fake clock and fake api: phase order, game-time counting with pauses, speed commands, sampler on /
   off, step-down on a skipped sample, aborts, preflight failures, the marker line. Probe `app.saveGame`.
   **Gate:** the mini sheet runs from one press to `BENCH_DONE` unattended (short record, 3 game min).
5. **Report.** `tools/bench_report.py` + `make bench` + ledger + game_logs slug; flow_report gains `--test`
   grouping. Tests (`tests/tools/test_bench_report.py`): synthetic bench logs (all tables, treatment exclusions,
   Holm, ledger pooling), runs 5 and 6 archives reproduce their RESULTS.md rows. **Gate:** the mini sheet's draft
   reads right to the user.
6. **Screenshots.** Tour + copy to `plans/square_smart_lanes/shots/`. **Gate:** one tour in game, files matched.
7. **Production.** Sheet 1, then sheet 2, each a RESULTS.md run; `lights_mixed` once to cross-check against run 6.
   Later sheets: parclo / ring interchanges, channelized X, ovals; test 5's 1000-people load level.

## Open questions

1. ~~Map size~~: 16 km is the largest (user 2026-10-13): three 16 km sheets.
2. Does the game's AUTO light the 2-lane ring's arm junctions with country medium arms (test 2's premise)? Sheet 1's
   `BENCH_TWIN lit_nodes=` and the report's "lit at read" / "kept" counts answer it; if none is lit, sheet 1's
   `sl vs sl_keeplights` compares identical twins: switch `rb4`'s arm road to country large (6) or its signals to On.
3. Does TF3 weigh destination choice by travel time (would matter only if towns were ever shared; the bench avoids
   it)?
4. ~~Year~~: the run jumps to 1950 by itself (user 2026-10-13).
5. Is `app.saveGame` callable from a mod's GUI script (resume after a crash)? Not built.
6. Sweep cost at 10 game s and 2x with ~19k drivers (sheet 1): the step-down to 1x covers a miss; the draft shows it.
7. Does the town entry's outward arm stay clear of the diamond's highway pair merge (60 m before the entry, after a
   120 m taper)? Offline yes; the first sheet 2 run shows it (links `linked=117`).
