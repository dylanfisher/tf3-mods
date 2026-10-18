Status: built 2026-10-13 (rev 2, unreleased), offline-tested; sheets 1-3 and micro v1 / v2 run in game; sheet 4 (spiral
2-lane roundabouts on town streets, section "Sheet 4") v1 run: links refused; v2 (1 set) run 2026-10-13 (session
`2026-10-13_2341_bench-s4-774314`, ok=yes); v3 (mid nodes, 4th twin sl_rsplit) run 2026-10-14 (mid nodes built and
written, VERIFY same=8); v4 (5th twin sl_rmid, 3 ring sizes) run 2026-10-14 (writes all landed; live samples: below); v5 (plain vs mid-node
rings) run 2026-10-14 (RESULTS.md "bench s4 v5"); sheet 5 (ring lane use: traffic mixes, RINGMIX / RINGLANE, section "Sheet 5") run
2026-10-15 (session `2026-10-15_0602_bench-s5-ring-34019`); sheet 6 (the mid-node default under heavy traffic, section
"Sheet 6") and the city run (section "City lights at scale") built 2026-10-15, offline-tested, not run yet (TESTING.md
6Y3, 6Z3). Redesigned for
16 km maps the same day (user: "9.9mi x 9.9 is very large size": 16 km is the largest map): three sheets, one press
each. Builds on the Lights showcase (SHOWCASE.md "Town entries", "Mixed shapes", "Exit-fan twin"), the traffic log
contract (FLOW.md v3) and the run ledger (`plans/square_smart_lanes/RESULTS.md`). Section "As built" lists the files.

# Stress Test: the test bench

User (2026-10-13): "the lights showcase is much more accurate now with the town fixes, roundabouts, etc. can we use
that as a foundational tool to build the other tests? making sure to only have as many towns as necessary for that
test. and ideally we have as many tests as possible in one map so its faster to record and audit. the more you can
automate the better".

Tests wanted, in order: (1) Smart Lanes vs game at roundabouts, interchanges, slip-lane junctions, ramps, lane drops;
(2) the "No lights at roundabouts and ramps" setting alone; (3) free curb turn without a jam on mixed shapes (sl vs
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
Mixed (a variant list cycling over the sets) only when the question is about a family ("the free curb turn on lit
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
| Roundabout `square_roundabouts.con` | round, 2 ring lanes, scale XS (`sqrb_radius_size` 1: 10 m inside the ring, grown to fit the roads), 4 arms, no splitter, no tram, signals Off (the game's AUTO decides), arm road country medium | 4 two-way | 4 | AUTO (from 1950) may light the ring's arm junctions; the bench logs `lit_nodes=` per twin after the settle | reach 103 + 20 | test 2 needs lit ring nodes: if AUTO lights none at this variant, phase 2 switches the arm road to country large (gate) |
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
| 1 | `rb4` | Roundabout, 2-lane ring, scale XS, 4 country medium arms, signals Off (the game's AUTO lights) | game, sl, sl_keeplights | 9 | 27 | 108 | test 1 (rings, 9 pairs), test 2 (rings, 9 pairs) |
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

**Towns tab > Bench: one button per sheet** ("Sheet 1" to "Sheet 5", "Micro"). A press first checks what it can
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
| shots | a primer `takeScreenshot(1)` (the first of a session writes no file), then per test every twin of its first set: `setCameraData` 130 m over the junction (450 m until 2026-10-14: queues only, no lanes) (the camera's angle and pitch kept), 2.5 s, `takeScreenshot(1)`, one `[SQST] BENCH_SHOT n= id=<test>:<zone> x= y=` each, 4 s apart | the last shot |
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
| SL-1 | zone mode **`sl_keeplights`**: as `sl` (lanes, free curb turn and light phases as the settings), but no light is switched off in the zone (ring arm junctions, slip / ramp nodes), in the automatic pass and the tool; one `LIGHTS src=auto node= to=kept zone=sl_keeplights` line per node it would have switched off; `SUMMARY ... zone_keeplights= lights_kept=`; `by_ab ...,sl_keeplights:<n>`; accepted by `sl_zones.lua` (AB_SET, AB_OPTIONAL) | test 2: the setting is load-time and acts at build time, so neither a reload A/B nor a second map isolates it; twins on one map do |
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
  `stress_logic.slZonesByAb` must add the same, last). Lanes, free curb turn and light phases as `sl`. A node there
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

## Micro bench (2026-10-13)

A fourth button, **Micro**, runs a small one-off sheet with the same one-press automation (preflight, map clear, year,
build, Smart Lanes idle, warm-up, record, screenshots, `BENCH_DONE`) and `make bench` support. Sheet key `micro`, id
`bench_micro`, zone ids `microg<k><twin>` (pair `microg<k>`), so it never collides with sheets 1-3 in the ledger,
RESULTS.md (`### Bench sheet micro: ...`) or one session's log.

**Swapping a test in:** edit the block `bench.MICRO` in `mods/square_stress_test/content/stress/stress_bench.tl`
(marked "MICRO BENCH: SWAP TESTS HERE"): its `tests` (a variant from `bench.VARIANTS` or a new `variant(...)`, the arms
that get a town, the twins, the comparisons, the sets), `pop` (people per town) and `pool`; bump `version` (pairs of
different versions never pool in the ledger). Then `make test MOD=mods/square_stress_test` (the "sheets on a 16 km map"
test lists what each sheet places: update its `micro` line, or read the window's plan line) and `make link`. A new
construction file needs its arms on the axes (the packer refuses others) and, for the build-time geometry check, a kind
it knows (`rb`: 3+ one-way streets; `ix`: 4+; a crossing shape 4: a lane change; else any junction).

**Version 1 (run, session `2026-10-13_0837_bench-micro-560595`, RESULTS.md):** 3- and 4-lane rings, game vs sl, 6 sets each,
800 people a town (~52 % standing map-wide). The 3-lane ring is the Stress Test's own entry roundabout
(`square_stress_test_entry.con`, ring 2 = `highway_new_large`; square_roundabouts' rings come in 1, 2 or 4 lanes only), the
4-lane ring square_roundabouts' Roundabout with ring lanes "4" (`town_new_one_way_medium`), scale XS, country large arms.

**Version 2 (current): ring layouts.** Per ring type one set of 8 twins: `game`, `sl` and Smart Lanes' six ring layout
zone modes `sl_rturbo`, `sl_rmatch`, `sl_rout1`, `sl_r2exit`, `sl_rspiral`, `sl_rspread` (square_smart_lanes PLAN.md
"Ring layout variants (bench)"; twin letters h-m, town names "Ring turbo 1 N" ...). Ring types in this order: `rb4l`
(4-lane), `rb3` (3-lane), `rb2` (2-lane ring, 2 + 2 country medium arms: sheet 1's variant). The sheet places sets round
robin (`roundRobin`: one set of every ring type before any second), so every type gets one and the second goes to the
4-lane ring: **16 km: 4 sets, 32 junctions, 128 towns (~77k people), ~11 min build** plus growth, ~27 min in all.
- Comparisons per test: sl vs game, every mode vs sl, every mode vs game (13); `pool`: each also pooled over the ring
  types; `rank` (BENCH_START `rank=yes`): the report ranks every mode per ring type by mean km/h (with its delta to game,
  standing, cars/min) and pooled over the types (mean delta to game, mean rank). The user accepts few sets: one clear
  winner is the aim, not significance.
- Towns 600 people (x1.5 by capacity, still a full fill): v1's 800 ran at ~52 % standing map-wide.
- Treatment: a ring mode twin needs a ring `APPLY ... layout=<its mode> zid=` line (Smart Lanes writes the ring whole in
  these zones), else it is excluded and left out of the ranking; the preflight requires the six modes in Smart Lanes'
  `zmodes`; `by_ab` ends `...,sl_rturbo:4,sl_rmatch:4,sl_rout1:4,sl_r2exit:4,sl_rspiral:4,sl_rspread:4` (tested byte for
  byte against sl_zones.lua's byAbText).

## Sheet 4: roundabouts with and without nodes between the arms (2026-10-13; versions 3-5 2026-10-14)

**Version 5 (2026-10-14):** v4 ran (session of 2026-10-14 ~01:30-01:52 UTC, `BENCH_DONE spec=bench_s4@4 seed=455860 ok=yes`).
Every write landed: sl_rmid `VERIFY same=8` (2-lane), 8 (3-lane), 12 (4-lane), so the engine keeps crossing lane changes
at a 2-edge node; the tool drew the mid nodes (sl_midview), no `ERROR where=mid_lines`. But the **live samples** (traffic
log during the record phase from 01:40:31 UTC, read by the coordinator before the report; not `make bench` output) say the
mid-node geometry itself may hurt:
- 4-lane ring, 2 mid nodes per stretch: every twin jammed, the game's too (s4g3b game 1.4 km/h, 88 % standing; a sl 2.2 /
  85; l sl_rspiral 1.8 / 90; n sl_rsplit 3.1 / 78; o sl_rmid 0.4 / 98).
- 3-lane ring, 1 per quarter: sl (turbo) 0.2 / 97, sl_rmid 1.4 / 86, game 6.0 / 62, sl_rspiral 8.6 / 50, sl_rsplit 14.2 / 42.
- 2-lane ring: all moving, 30-42 % standing.
Hypothesis (unverified): the game's cars change lanes along segments, and mid nodes cut the ring into short segments, so
the game's own lanes (and every layout) lose room for that. Nothing in the docs, findings or game files documents lane
changes along a segment in TF3 either way (square_smart_lanes PLAN.md "Reachability and lane changes" assumes them; the
in-game question in its TESTING.md 3 was ticked without a recorded observation). And without twins on the plain ring the
sheet had no baseline. User: "game default might get totally buggy on the 2-node lane change", "we're missing the default
baseline. next is the short sheet for baseline without mid rings". So v5, per ring size (one set each):
- **Twins on two geometries in one set**: `<ab>@plain` on the ring as players have it today (R&I Nodes between arms Off,
  `bench_rb2t` / `bench_rb4l`; the entry ring without nodes, `bench_rb3`), `<ab>@mid` on v4's mid-node ring (`bench_rb2tm`,
  `bench_rb3m`, `bench_rb4lm`). The test lists both variants and `geoms = { plain = 1, mid = 2 }`; each twin takes its
  geometry's variant (stress_bench `twinMode`, `placeSet`). The zone's mode stays the Smart Lanes mode (ab), mid twins get
  their own letters (`MID_LETTER`: game p, sl q, sl_rspiral r, sl_rsplit s, sl_rmid t; plain twins keep a / b), town names
  "<mode> mid". The zone line and BENCH_TWIN gain `geom=plain|mid`; tools/flow_report.py reads such a twin's mode as
  `<ab>@<geom>`, so comparisons and the ranking name them unambiguously ("sl_rsplit@mid vs game@plain").
- Twins: `game@plain`, `sl@plain` (Smart Lanes' shipped default: 2-lane: since 2026-10-14 Smart Lanes splits the plain
  ring's edges itself and writes its 2-lane default, since 2026-10-14 `sl_rmid` (before: the mid-node spiral), so this twin
  is nearly `sl_rmid@mid` with its nodes made by Smart Lanes; before that change the spiral without mid nodes; 3- and 4-lane: turbo), `game@mid` (what the nodes alone do), `sl_rsplit@mid`; on the 2-lane ring also `sl_rmid@mid`.
- Comparisons: `sl_rsplit@mid vs game@plain` (the decision question), `sl_rsplit@mid vs sl@plain`, `game@mid vs game@plain`
  (node harm), `sl@plain vs game@plain`; 2-lane also `sl_rmid@mid vs game@plain`, `sl_rmid@mid vs sl_rsplit@mid`.
- Tests `rb2v` (links on the 2 + 2 country road), `rb3v`, `rb4v` (links at the arms' lanes). Plan: "13 junctions, 52 towns
  (~21k people), about 4.3 min to build; 16.0 x 16.0 km map: everything fits". Spec `bench_s4@5`. Needs Smart Lanes with
  `sl_rsplit` and `sl_rmid` in `zmodes` (preflight).
- Report: the ranking per test shows `<ab>@<geom>`, its "delta vs game" against `game@plain`; treatment checks use the
  mode before the @ (`sl_rsplit@mid` needs its `layout=sl_rsplit` APPLY lines and an `RSPLIT ... mids=` > 0 line).

**Version 4 (2026-10-14):** v3 ran in game (every twin `mids=4`; sl_rsplit's mid nodes written, `VERIFY same=8 nodes=8`).
User, on the Crossing Tool at the sl_rsplit twin's arm junction (the inner lane's inner -> outer curve crossing where
the entry joins the outer lane): "try one where we don't allow the inner to outer merge at an intersection; they would do
it mid-node". A **5th twin `sl_rmid`** (letter o, town names "Ring mid 1 N"; square_smart_lanes PLAN.md "Mid-node lane
changes (sl_rmid)") on the same ring `bench_rb2tm`: at the arms no lane change (o1 -> exit only, o2 -> o2, e1 -> o1); at
the mid nodes o1 -> o1 and o2, o2 -> o2 and o1 (both ways, crossing at the node). Comparisons added: `sl_rmid vs
sl_rsplit` (where the outward move happens), `sl_rmid vs sl_rspiral`, `sl_rmid vs game`, plus `sl_rsplit vs sl_rspiral` and
`sl vs game` (the five per test). The user then: "also for 3 lane roundabouts, so we use all 4 lanes effectively and allow
mid-roundabout switching, in the same test" (both the 3- and the 4-lane ring): **three tests, one set each, the same five
twins**: `rb2tm` (v3's ring), `rb3m` (variant `bench_rb3m`: the micro bench's 3-lane entry ring rb3 with `sqst_entry_mid
= 2`, one plain node per quarter: a second leaves ~1 m of free ring beside the 30 m country large arms), `rb4lm`
(`bench_rb4lm`: the micro bench's 4-lane ring rb4l with `sqrb_dev_ring_mid = 2`, two per gap: square_roundabouts grows it
from 10 to 20 m inside so the junctions keep their room). Links: rb2tm on the 2 + 2 country road (`linkLanes = 4`), the
wide rings at their arms' own lanes (as the micro bench). Plan: "15 junctions, 60 towns (~24k people), about 5 min to
build; 16.0 x 16.0 km map: everything fits". Geometry check: `mids=` at least 4 per gap (rb3m 4, rb4lm 8).
Since Smart Lanes rev 5's default spiral (2026-10-14, square_smart_lanes PLAN.md "Default: the mid-node spiral"), the `sl`
twin of rb2tm writes sl_rsplit's lanes (a 2-lane ring with one-lane exits): there `sl vs game` measures the same layout as
`sl_rsplit vs game` (a second pair of it); on rb3m / rb4lm `sl` keeps its default (matched / turbo).
Treatment check as sl_rsplit's (`APPLY ... layout=sl_rmid` and the last `RSPLIT ... mids=` > 0 with its zid). Needs a
Smart Lanes with `sl_rmid` in `zmodes`. Spec `bench_s4@4`.

**Version 3 (2026-10-14):** the user, on a screenshot of a v2 ring: "can we build a roundabout with an extra node where
the red circles are (half way between the arms), so that we could do spiral, but have the outer to inner lane change
happen on that node, so that traffic entering doesn't overlap as much?" So:
- **Ring with mid nodes** for every twin: variant `bench_rb2tm` ("RB 2L town mid") = `bench_rb2t` plus square_roundabouts'
  dev override `sqrb_dev_ring_mid = 1` (a plain ring node half way between neighbouring arms: 8 ring nodes 45 degrees
  apart, same radius 10 m, same arms; plans/square_roundabouts/PLAN.md "Ring mid nodes (dev)"). Test id `rb2tm` (other
  geometry than v2's `rb2t`: results never pool, `bench_s4@3` either way). Same geometry in all twins is the better A/B
  and costs nothing: the game makes a plain one-way node straight on, and `sl` / `sl_rspiral` plan junctions only, so
  their mid nodes stay as the game made them (tested in square_smart_lanes test_rsplit "other twins").
- **4th twin `sl_rsplit`** (letter n, town names "Ring split 1 N"; square_smart_lanes PLAN.md "Mid-node spiral
  (sl_rsplit)"): at the arms o1 -> exit only, o2 -> o1 and o2, e1 -> o1 only; at the mid nodes o1 -> o1 and o2, o2 -> o2.
  Comparisons `sl vs game`, `sl_rspiral vs sl`, `sl_rspiral vs game`, `sl_rsplit vs sl_rspiral` (the mid-node lane change
  alone), `sl_rsplit vs game`; `rank = yes` ranks all four. Still 1 set: 4 junctions, 16 towns.
- **Geometry check** (`benchGeometry`): a ring asked for mid nodes also needs 4+ new nodes joining two one-way streets
  only: `BENCH_TWIN ... geometry=ok what=one_way_streets n=8 mids=4` (`geometry=bad` with fewer: the set is no match).
- **Treatment check** (`make bench`): the sl_rsplit twin needs `APPLY ... layout=sl_rsplit` (as every ring layout twin)
  and its last `[SQRL] RSPLIT ... mids=<n > 0>` line; a ring without mid nodes logs `RSPLIT ... mids=0
  fallback=sl_rspiral reason=..` and writes `layout=sl_rspiral`: excluded ("sl_rsplit twin: no mid nodes on its ring").
  tools/flow_report.py COMPARISONS gained `sl_rsplit vs sl_rspiral`, RING_MODES `sl_rsplit`; bench_report
  EXPECTED_KINDS `rb2tm`: ring.
- Needs: Smart Lanes with `sl_rsplit` in `zmodes` (the preflight names it) and this repo's square_roundabouts (the dev
  override; an older one ignores the key and builds no mid nodes: geometry=bad on every twin).

The v2 design below is kept for the record (v3 above it).

**Version 2 (2026-10-13, after the first run):** the v1 run (session of 2026-10-13 23:02, seed 397256) built all 27
rings and Smart Lanes set every twin as planned (9 x `APPLY layout=sl_rspiral`, 9 sl twins matched, game twins
`zone_game`), but **all 108 links were refused** (Construction Not Possible, 3 tries each: `linked=0 unlinked=108`),
so no traffic reached a ring. Sheets 1-3 linked fine; the new part was the 1 + 1 country link from a `town_new_small`
arm to the 3-lane entry (which joint the game refuses is not known). And user: "why does this run need so many tests?
it takes a long time to build. can we keep it simpler, sample size of 1". So v2:
- **1 set: 3 junctions, 12 towns** (~1-2 min build). One pair per comparison: a direction, no significance; the
  report's ranking and the cars/min say which layout to look at. A clear winner gets a larger run later.
- **Links on the 2 + 2 country road** (test `linkLanes = 4`; sheet 1 joined that road to the 3-lane entries). A
  refused link tries again with copies of the arm's town street (try 2), then the 1 + 1 country road (try 3)
  (`showToTown`, only for a bench test with `linkLanes > 0`); the link line names the variant that was used.

The v1 design below is kept for the record.

**Question (one):** a player's 2-lane one-way roundabout with 1-lane town streets (1 + 1 lanes) as arms runs best with
their hand-made "spiral": the outer ring lane always leaves at the next exit (exit-only), the inner lane either stays
inner or moves into the outer lane (and so leaves at the next exit), the entry lane joins both ring lanes. That is
Smart Lanes' ring layout `sl_rspiral` (square_smart_lanes `sl_rules.lua` `M.variantConns`; on this ring D = 2, A = 4:
o1 -> exit only, o2 -> o1 and o2, e1 -> o1 and o2). Smart Lanes' default (`sl`) gives this ring plain matched lanes
(the exit-only outer lane needs 2+ exit lanes at every arm: `turbo_reason=narrow_exit`), so its inner lane is never
entered or left at a junction. Micro v2 had this ring only with 2 + 2 country arms, one set, saturated (spiral 81.1
cars/min, matched 87.2, game 60.8).

**Design** (`bench.SHEETS` entry `bench_s4`, key `s4`, button **Sheet 4**):
- Junction `rb2t` (variant `bench_rb2t`, label "RB 2L town"): sheet 1's ring (square_roundabouts Roundabout, ring lanes
  "2", scale XS, 4 arms, no splitter, signals Off) with arm road `sqrb_arm_type` 1 = Town, small (`town_new_small`:
  1 + 1 lanes, sidewalks). Links at the arm's own lanes: a 1 + 1 country road (`country_*_small`) from the arm end to
  the town's entry roundabout, so no lane changes inside the zone. A town on all four arms. No forced lights;
  "No lights at roundabouts and ramps" On (as sheet 1; the game AUTO-lit sheet 1's rings, Smart Lanes removes them
  in every sl-type twin).
- Twins `game`, `sl`, `sl_rspiral` (letters b, a, l); comparisons `sl vs game` (what Smart Lanes gives this ring today),
  `sl_rspiral vs sl` (the question: does spiral beat today's matched default), `sl_rspiral vs game` (spiral against the
  game's own lanes). `rank = yes`: the report also ranks the three modes by km/h with cars/min.
- **9 sets, 27 junctions, 108 towns of 400 people (~43k), ~9 min build, ~25 min in all** (warm-up 180 + record 1200
  game s at 2x, 3 shots). 9 pairs per comparison: significant at 8 of 9 (power 0.77 at q = 0.9). A 16 km map holds 11
  sets of 3 twins, but 11 pairs need 10 of 11 (power 0.70): 9 is the efficient count and leaves load off the map.
- `sl_rspread` (turbo plus centre lanes; here: matched + o2 -> exit + e1 -> o2) left out: a 4th twin fits only 8 sets
  (32 junctions), so every comparison would need 8 of 8 (power 0.43). If spiral wins, a version 2 could run spiral vs
  spread on its own.
- Load: 400 people is the least a Medium bench town takes (a Medium town is created with capacity 400 and `growFactorForCap` clamps at x1; a smaller
  town would need another town size, which changes grids, entries and the packer). Sheet 3 ran at 18 % map-wide standing,
  sheet 1 (same ring, 2 + 2 arms, 132 towns) at 31 %, micro v2 (600 people) at 52 %. Each arm here carries one town's
  traffic like sheet 1's, through one entry lane instead of two, so the junctions are busier: if the draft says
  "SATURATED" (over 50 %), read throughput, not speed, and say so in the result.
- Ids: zones `s4g<k><a|b|l>`, pairs `s4g<k>` (k = 1-9), spec `bench_s4@1`: none of these occur in the ledger
  (sheets s1-s3: `g<k>`; micro: `microg<k>`). Town names "Ring spiral 3 N", "Smart lanes 3 N", "Game default 3 N".
- Treatment check (`make bench`): every spiral twin needs a ring `APPLY ... layout=sl_rspiral zid=` (or `SKIP ... reason=same
  layout=sl_rspiral`) answered by `WRITE success=true`; sl twins a ring `APPLY` / `SKIP same` (EXPECTED_KINDS `rb2t`:
  ring); game twins no APPLY. Failing twins are excluded from the pairs and the ranking.

**Run:** a fresh 16 km Blank Slate (right-hand traffic) with Stress Test, Smart Lanes (Apply automatically On, No lights
at roundabouts and ramps On, a version that has `sl_rspiral` in its `zmodes`) and Roundabouts & Interchanges; Debug
window > Towns tab > Bench > **Sheet 4** > "Run bench"; leave it ~25 min; then `make bench` (TESTING.md 6Y). Recording
into the ledger: `make bench ARGS=--record` after `BENCH_DONE ok=yes`.

## Sheet 5: ring lane use (2026-10-15; run 2026-10-15: session `2026-10-15_0602_bench-s5-ring-34019`, results in plans/square_smart_lanes/RESULTS.md)

Smart Lanes PLAN.md "Ring lane use (in progress)" / "Bench interface": the user's 2-lane ring with 2-lane arms (ring 282381)
queues every car bound past the first exit in the inner entry lane (turbo: o1 exits only, so one circulating lane); on
4-lane rings with 3-lane arms nothing enters or leaves o4. Two new Smart Lanes zone modes answer it: `sl_rmid2` (sl_rmid for
wide exits; Smart Lanes adds the mid nodes itself, `SPLIT` then `RSPLIT ... mids=4`) and `sl_rturbo_in` (turbo with the inner
lanes fed). The bench measures them, per traffic mix, with the turning mix and the lane use logged per twin.

**What a press builds** (`bench.SHEETS` entry `bench_s5`, key `s5`, button **Sheet 5**, spec `bench_s5@1`):

| test | ring | twins (letters) | sets |
|---|---|---|---|
| `lu2` | `bench_rb4` (sheet 1's ring): square_roundabouts Roundabout, ring lanes 2, scale XS, 4 country medium arms (2 + 2), signals Off | game (b), sl_rturbo (h), sl_rmid2 (w), sl_rmatch (i) | 3 |
| `lu4` | `bench_rb4l` (the micro bench's): ring lanes 4, scale XS, 4 country large arms (3 + 3) | game (b), sl_rturbo (h), sl_rturbo_in (y), sl_rspread (m) | 3 |

- **Traffic mixes** (`bench.LU_MIXES`, one per set, in turn: set 1 even, 2 straight, 3 adjacent; every twin of a set sees its
  mix, so every mode sees each): **even** four towns of 350 people; **straight** N and S large (600), E and W small (100):
  N <-> S trips take the 2nd exit both ways; **adjacent** N and E large, S and W small: mostly 1st + 3rd exits (a true
  first-exit mix needs one-way demand: town-to-town demand is symmetric, so A -> B (1st exit) comes with B -> A (3rd)).
  Equal people per ring (1400). A town below a Medium town's 400 is created with that capacity (`townCaps`, as the light
  plans A/B's small towns); names end in the word: "Ring mid 2 2 N large", "Ring turbo in 6 W small". The label is checked,
  not assumed: every ring twin logs its measured mix (RINGMIX), and the report says when a set's mix does not bear it out.
- **Comparisons** (per test): every layout vs game and vs `sl_rturbo` (what `sl` wrote on these rings when Sheet 5 ran; since 2026-10-15 Smart Lanes writes matched lanes by default on 2-lane rings whose exits all have 2+ lanes, so `sl` = `sl_rmatch` on lu2, turbo stays on the 4-lane ring: square_smart_lanes PLAN.md "Default: matched lanes on 2-lane rings with wide exits"):
  lu2 `sl_rturbo vs game`, `sl_rmid2 vs game`, `sl_rmatch vs game`, `sl_rmid2 vs sl_rturbo`, `sl_rmatch vs sl_rturbo`; lu4 the
  same with `sl_rturbo_in` and `sl_rspread`. 3 sets = 3 pairs per comparison, one per mix (a direction, no significance:
  the per-mix verdicts are the point). `rank = yes`.
- **Letters**: `sl_rmid2` w, `sl_rturbo_in` y. The suggested p / q are taken (Sheet 4 v5's `MID_LETTER` p-t), a-v by the other
  modes (stress_flow TWIN_LETTER: u sl_classic (dropped 2026-10-16, older saves), v sl_auto), g marks the set in a zone id (`s5g3w`) and x is the fallback
  letter of a recomputed id. Zone ids `s5g<k><letter>`, pairs `s5g<k>` (k = 1-6: lu2 sets 1-3, lu4 4-6).
- **Fit**: 16 km: **24 junctions, 96 towns (~34k people), ~8 min build**; the most this layout holds is 32 junctions (8 sets
  of 4 twins: a 4th set per ring would repeat a mix). The 3-lane ring with 2-lane arms is left out: the Stress Test's entry
  roundabout (the only 3-lane ring) has country large arms only, so it needs new geometry (PLAN.md: skip then).
- **Mid nodes**: none built by the bench. Smart Lanes splits the `sl_rmid2` twins' ring edges itself; on this XS ring with
  country medium arms the halves should clear its 8 m minimum (`SPLIT ... refused=short` would make that twin
  `fallback=sl_rturbo`: excluded by the treatment check). No twin uses `sl_rmid` (it would need `sqrb_dev_ring_mid` on every
  twin of the set).
- **Turning mix and lane use** (traffic log, FLOW.md "RINGMIX / RINGLANE"): the bench's tests set `ringMix`, so the sampler
  reads, for each driver in a ring twin's measured area, its path window once (entry and exit arm: `exit1..3`, `uturn`,
  `none`; at most 400 drivers a sweep) and, for cars in the ring on a ring edge, their distance from the centre (lane use,
  clustered into lanes by the report: o1 = outer). This runs while the bench's `path_thru` is off. Lines every 6 samples
  and at the stop, cumulative.
- **Report**: `make bench` (the ranking, the pairs, the treatment check) plus the section **"Ring lane use"** of
  tools/flow_report.py for this run: per ring x mix every mode's thru/min, km/h, standing %, queue, queue per arm (inbound),
  lane use and measured mix, the RINGMIX table per twin, a verdict line per ring and mix (best mode; each mode vs game and vs
  sl_rturbo). `make flow` shows the same section for the whole log.
- **Treatment check** (`make bench`): `sl_rturbo` / `sl_rmatch` / `sl_rturbo_in` / `sl_rspread` twins need ring `APPLY ...
  layout=<mode> zid=` lines answered by `WRITE success=true`; `sl_rmid2` twins also their last `RSPLIT ... mids=` > 0 (a refused
  split: `RSPLIT ... mids=0 fallback=sl_rturbo`, excluded as "no mid nodes on its ring, written as sl_rturbo"); game twins
  no APPLY. EXPECTED_KINDS `lu2`, `lu4`: ring.
- **Needs**: Smart Lanes with `sl_rmid2` and `sl_rturbo_in` in its `zmodes` (the preflight names a missing one), Apply
  automatically On, No lights at roundabouts and ramps On; Roundabouts & Interchanges. Files: stress_bench.tl (AB, LU_MIXES /
  LU_POPS / LU_SIDES, mixPop, setMix, the sheet, plan: per-town pop, group mix / ringMix), stress_logic.tl (SL_ZONE_AB,
  slZonesByAb, town modes / words, zone lines' mix=), stress_flow.tl (ring*: newRing, ringClass, ringMove, ringSteps,
  ringCount, ringMiss, ringEdge, ringLane, ringMixLine, ringLaneLine; FLOW_ZONE mix=; letters w / y), gui/stress_flow_log.tl
  (ringRead, node / ring edge caches, the lines), gui/stress_hud.script.tl (hint), tools/flow_report.py, tools/bench_report.py.
  Tests: test_bench "sheet 5", test_showcase "bench sheet 5 (16 km)", test_flow "ring mix", tests/tools RingUseTest and
  Sheet5RingUseTest.

## Sheet 6: the mid-node default under heavy traffic (2026-10-15; offline-tested, not run in game yet: TESTING.md 6Y3)

Evidence: bench s5 (session `2026-10-15_0602_bench-s5-ring-34019`, RESULTS.md verdict "Mid nodes with crossing lane changes
under heavy traffic"): `sl_rmid2` gridlocked in all 3 sets (both ring lanes full, nothing leaving). The default Smart Lanes
**ships** for a 2-lane ring whose exits all have one lane is `sl_rmid` with mid nodes it adds itself (square_smart_lanes
PLAN.md "Default: the mid-node spiral", "Smart Lanes adds the mid nodes"): the same crossing lane changes at the mid nodes.
Its wins (Sheet 4 v3-v5) were on this ring shape at lighter traffic (1600 people a ring, 30-42 % standing). And the
plain-ring `sl` twin of s4 v5 never had mid nodes (session `2026-10-14_0201_bench-s4-176702`: `RSPLIT ... mids=0
fallback=sl_rspiral reason=no_mid_nodes`, `APPLY ... layout=sl_rspiral default=one_lane_exits`: before Smart Lanes split
rings itself), so the shipped default with its own mid nodes has **not been benched at all**.

**What a press builds** (`bench.SHEETS` entry `bench_s6`, key `s6`, button **Sheet 6**, spec `bench_s6@1`):

| test | ring | twins (letters) | sets |
|---|---|---|---|
| `hm2` | `bench_rb2t` (Sheet 4's town ring, **plain**: no dev mid nodes): ring lanes 2, scale XS, 4 one-lane town street arms (`town_new_small`), signals Off; links on the 2 + 2 country road (`linkLanes = 4`, as rb2v) | game (b), sl (a), sl_rmatch (i), sl_rturbo (h) | 3 |

- **sl = the automatic default.** In an `sl` zone Smart Lanes splits the ring (`SPLIT ... nodes_added=4`), then writes
  `sl_rmid` (`RSPLIT ... mids=4`, `APPLY ... layout=sl_rmid default=one_lane_exits`). The report's treatment check wants
  exactly that (`tools/bench_report.py` `DEFAULT_RING`), and prints a "Mode check, hm2:" line per twin (layout, default,
  split, mids). A refused split (`SPLIT ... refused=short`: halves under 8 m on the XS ring) writes `sl_rspiral`: that
  twin is excluded ("sl twin: no ring APPLY layout=sl_rmid ...").
- **sl_rturbo falls back to matched here** (checked in square_smart_lanes `sl_rules.lua`: `variantConns("sl_rturbo")` =
  `twoLaneConns(v, {turbo = ctx.turbo})`, and `ringPlan` gives `turbo=false, reason=narrow_exit` when any exit has one lane).
  Its APPLY lines say `turbo=false layout=sl_rturbo`; the mode check notes "(matched lanes: every exit one lane)". So
  `sl_rmatch vs sl_rturbo` compares identical layouts: an expected tie (`EXPECTED_TIES`) whose spread is the noise of
  identical twins (an A/A pair, useful with 3 sets). Kept as asked rather than replaced by another layout.
- **Load: 2400 people a ring** (`bench.HM_POPS`: even 600 each; straight / adjacent 1000 large + 200 small), the
  Sheet 5 mixes (`bench.LU_MIXES`, one per set). Why 2400: s5 gridlocked sl_rmid2 at 1400 a ring, but with 2 + 2 arms (two
  entry lanes per arm); here every arm feeds one entry lane, and s4 v5 ran this ring at 1600 with 30-42 % standing (moving).
  1.5 x s4 v5's load (and 1.7 x s5's) should take every twin to saturation without the town entries being the limit (each
  town still has its 3-lane entry roundabout and a 2 + 2 link). A large town is a Medium town sized x2.5 (fill ~0.8-0.9 at
  that factor: 800-900 people likely; FLOW_TOWNS `pop=` shows it); a small town is created with capacity 200.
- **Record 30 game min** (`recordS = 1800`, sheet field; others keep 20): a lock needs time to form and to be told from
  a slow spell. 2x as the other sheets; 12 junctions, 48 towns (~29k people), ~5 min build: ~25 min hands off.
- **Gridlock per twin** (tools/flow_report.py, FLOW.md "Gridlock per twin"): 2 game min windows of each ring twin's
  recorded samples; locked = >= 80 % standing and thru/min <= 25 % of the best window of any twin of its set; gridlock =
  the last 3 windows locked ("GRIDLOCK from game min n"). In the "Ring lane use" section (table + the verdict lines), for
  Sheets 5 and 6 alike. Verdict per mix: the ring use verdict line (best mode, each vs game / sl_rturbo) plus the gridlocked
  twins.
- Comparisons: `sl vs game`, `sl_rmatch vs game`, `sl_rturbo vs game`, `sl vs sl_rmatch` (the shipped default against the
  old matched default: the question), `sl_rmatch vs sl_rturbo` (A/A). `rank = yes`.
- Files: stress_bench.tl (`HM_POPS`, `mixPop(mix, side, pops)`, test `pops`, sheet `recordS`, `bench.recordS` / `speed`),
  gui/stress_bench_run.tl (per-sheet record length), tools/flow_report.py (gridlock, `sl vs sl_rmatch`), tools/bench_report.py
  (`DEFAULT_RING`, `mode_notes`, SPLIT / turbo / default tracking, `EXPECTED_KINDS` hm2, the tie). Tests: test_bench "sheet 6",
  tests/tools Sheet6HeavyTest.

**What Smart Lanes may need** (not edited here): nothing to run it. If the sl twins' splits are refused (`refused=short`)
on this XS ring, the sheet cannot judge sl_rmid: Smart Lanes would then need a lower `short` limit, or the bench a larger
ring scale (an `sqrb_radius_size` S variant of rb2t, a new test id).

## City lights at scale (2026-10-15; run in game twice: TESTING.md 6Z3; v2 options: "Funnel layouts" below)

User: "make every light in the big grid cities be auto timer lights so we can see what happens with many at once". Smart
Lanes' automatic timing (step B v4, its RETIME_PLAN.md: one queue snapshot of every enrolled junction every 120 game s, a
junction's first decision after 8 snapshots ~16 game min, then every 10-60 min, writes at most 1 per 5 game s map-wide, a
saturated junction settled ~45 game min after enrolling, cap 1000 junctions) on hundreds of lights at once.

**What a press builds** (`bench.CITY`, key `city`, button **City lights** in the Towns tab's Lights showcase section, spec
`bench_city@1`, `@2` since the options (below; the defaults build this run); not in `bench.SHEETS`: no junction tests, the bench run's phases with a city build):
- **6 cities in 3 pairs** (`bench.cityPlan`): Large towns (capacity 1600) on the Stress Test's wide street grid, locked, its
  outer ring a country road (the Lights showcase's town recipe: `towns.createGrid` streets 3, `lockTowns`, one size
  command to **3000 people**, `densify`), 4 km apart (columns x -4000 / 0 / 4000, rows y -2000 / 2000), **never linked**:
  each city its own network (the bench's "never share" rule). In each column one **auto** city and one **control** city,
  the auto one on the first row in odd columns and on the second in even ones.
- **Every inner crossing lit**: the 800 m grid has 9 x 9 = 81 inner crossings (80 m blocks; the ring's T-junctions are
  left at the game's AUTO), found among the street nodes (4+ streets within 4 m of an inner grid point,
  `bench.cityInterior`), a light set to Yes where the game's AUTO lit none (the Lights showcase's way, one command at a
  time). 486 lit crossings, **243 enrolled** (the auto cities; within the 150-400 asked and Smart Lanes' 1000).
- **One traffic log zone per city** (r = 400: the measured circle reaches 600 m, past the ring's corners), ab
  `city_auto` / `city_control`, ids `cityg<k>v` / `cityg<k>b`, **not sent to Smart Lanes** (`slzones.setLocal`): Smart
  Lanes treats every city alike with its global settings (lanes, its Light phases setting) until the enroll.
- **Timeline** (one press, the bench run's phases): clear the map, year 1950, build, Smart Lanes idle, traffic log on (10
  game s, path thru off), **4x**, 3 min warm-up, **15 game min baseline**, then the enroll (`SmartLanes.auto` op=add events
  of <= 60 junctions, src=stress, the auto cities' crossings only; `[SQST] CITY_ENROLL`), **90 game min** more (105 in all,
  `recordS = 6300`: first decisions ~16 min after the enroll, settled ~45 min after it, so the report's "after" window,
  from `--auto-settle` 2700 s, has 45 game min), then op=clear (every junction unenrolled; written timing stays), 1x,
  one shot over each city from 700 m, `BENCH_DONE`. A skipped sample in the warm-up steps 4x down to 2x (2x -> 1x for the
  junction sheets, as before). ~40 min hands off.
- **Preflight**: Smart Lanes present with `sl_auto` in its zone modes (rev 8+), and its **Debug: performance log On**
  (`sqperf_log` 2) or the DEV `square_sqperf_all` active: the frame-time criteria need its SQPERF window lines.
- **Control**: a variant without control cities (`city.control = false`) enrolls with `SmartLanes.auto op=all` (the user's
  "All lit junctions" button) instead; the pairs need `op=add` so the controls stay out.
- **Report**: tools/flow_report.py section "Auto lights at scale" (FLOW.md "Auto lights at scale in the report"):
  Smart Lanes' cost (SQPERF ctx=bg: mean ms/frame, max, windows over 5 ms, slow lines), the v4 snapshots and their
  person-list spikes (src=scan, one long frame per snapshot, counted apart), writes per game minute and per 10 min, junctions
  written at least once, the game min by which 50 % / 80 % of the enrolled had a first `fits`, each city's km/h /
  standing / queue before vs after, map-wide, auto minus control, and the pass criteria: no Smart Lanes frame over 5 ms
  (also printed without the person-list spikes), mean cost < 1.5 ms/frame at 4x, no auto city's km/h more than 10 % below
  its baseline. `make bench` shows the same section for a city run.
- Log lines (keys only added): `[SQST] bench_city cities= auto= control= size= pop= spacing= half= crossings= enrolled= run=`,
  `[SQST] bench_city_lights: <n> inner crossings found, <d> dark: lights on`, one `[SQST] CITY id= pair= role= town= name= x=
  y= half= crossings= found= lit_before= forced= refused=` per city, `showcase zone` lines, `[SQST] showcase zones local n=
  run=`, `BENCH_PHASE ... phase=record ... enroll=<n>`, `[SQST] CITY_ENROLL run= op=add|all cities= nodes= events= baseline_s=
  by=bench smart_lanes=`; BENCH_START gains `city=yes cities= auto= control= crossings= enrolled= baseline_s= sl_perf=`.
- Files: stress_bench.tl (`CITY`, `cityLines`, `cityPlan`, `cityInterior`, `cityPayloads`, `cityZone`, the lines,
  `needs` / `problems` / `startLine` for it), gui/stress_citylights.tl (new: the build, the enroll, the unenroll),
  gui/stress_bench_run.tl (the city path: build, 4x, enroll after the baseline, unenroll, shots, the 4x -> 2x step-down),
  gui/stress_slzones.tl (`sendAutoNodes`, `setLocal`), gui/stress_hud.script.tl (button, hint, confirm text),
  tools/flow_report.py (`render_city`, SQPERF / snapshot / plan / enroll parsing), tools/bench_report.py (the section for a
  city run). Tests: test_bench "city lights", "run: the city run ...", test_citylights.lua (the build against a fake game),
  test_hud, tests/tools CityLightsTest.
- **Risks**: the town may grow its own streets over the grid (crossings `found` < 81; the lock pass should prevent it);
  ~240 light commands one per queue step (~10 s); the sampler with 6 big cities at 4x (FLOW_TARGET then strides; the
  report's speeds are still per city); a person-list spike every snapshot (src=scan above ~12 junctions: ~4-10 ms) fails
  the strict 5 ms criterion by design: the report shows it apart.

### Funnel layouts and fairer pairs (v2, `bench_city@2`, 2026-10-15; offline-tested, not run in game yet: TESTING.md 6Z4)

Runs 1 and 2 (plans/square_smart_lanes/RESULTS.md "City lights at scale") could not judge the automatic timing: the
cities were too quiet (623 of 776 checks "too little traffic") and the identical pairs differed at baseline as much as
any effect (queues 80 vs 178, km/h +25 % / -22 %). User: force the streets into narrow sections "like an hour glass, or
with holes in the grid" (they had bulldozed a city by hand into two grid halves joined by a 2-3 street neck). The City
lights section got options (rows under its button; the confirm dialog repeats them in one line):

| option | values (default first) | what changes |
|---|---|---|
| Layout | Plain grid / Hourglass / Holes | the grid's streets (below) |
| Baseline | 15 min / 30 min | game min before the enroll; 90 after it either way (`recordS = baseline + 5400`) |
| Busy (checkbox) | off / on | 7500 people wanted per city (v1: 3000), size command x4.7 from the Large capacity, level weights {0, 0, 0.25, 1} (`bench.CITY_BUSY`); the locked grid's lots cap it (v1 run 2: x1.9 gave ~2070 of 3000), the real number is the CITY line's `pop=` and the dense summary |
| Swap roles (checkbox) | off / on | the other city of each pair is auto (`role_swap=1`) |
| Same seed as the last city run (checkbox, after a run) | off / on | the last city run's seed again (the same holes); kept for this game session only |

The defaults build v1's run (the same cities, crossings, record); only the spec version (`bench_city@2`) and the added
log keys differ. `bench.citySheet(ui)` makes the sheet from the options (`gui/stress_bench_run.tl` `br.cityUi`,
`br.sheetFor`).

**Layouts** (stress_grid_streets.lua `grid.layout`; the 800 m grid, 10 x 10 blocks of 80 m, lines 0..10, center line 5):

```
 Hourglass (band 2 blocks tall, neck 3 streets)        Holes (an example: 4 holes of 2 x 2 blocks)
 +--+--+--+--+--+--+--+--+--+--+                        +--+--+--+--+--+--+--+--+--+--+
 |  |  |  |  |  |  |  |  |  |  |                        |  |  |  |  |  |  |  |  |  |  |
 +--+--+--+--+--+--+--+--+--+--+                        +--+--+--+--+--+--+--+--+--+--+
 |  |  |  |  |  |  |  |  |  |  |                        |  |     |  |  |  |  |  |  |  |
 +--+--+--+--+--+--+--+--+--+--+                        +--+     +--+--+--+--+--+--+--+
 |  |  |  |  |  |  |  |  |  |  |                        |  |     |  |  |  |     |  |  |
 +--+--+--+--+--+--+--+--+--+--+                        +--+--+--+--+--+--+     +--+--+
 |  |  |  |  |  |  |  |  |  |  |                        |  |  |  |  |  |  |     |  |  |
 +--+--+--+--+--+--+--+--+--+--+                        +--+--+--+--+--+--+--+--+--+--+
             |  |  |                                     |  |  |  |  |  |  |  |  |  |  |
             +--+--+       (no streets left              +--+--+--+--+--+--+--+--+--+--+
             |  |  |        and right: gaps)             |  |  |     |  |  |  |  |  |  |
 +--+--+--+--+--+--+--+--+--+--+                        +--+--+     +--+--+--+     +--+
 |  |  |  |  |  |  |  |  |  |  |                        |  |  |     |  |  |  |     |  |
 +--+--+--+--+--+--+--+--+--+--+                        +--+--+--+--+--+--+--+--+--+--+
 ...  (the south half as the north)                      ...
```

- **Hourglass**: a band `BAND_HALF` = 1 block above and below the center line where only the `2 x NECK_HALF + 1` = 3
  central north-south streets (x = -80, 0, 80) and the east-west streets between them are built; the ring's sides, every
  other north-south street and the center line's east-west streets outside the neck are left out (24 of 224 pieces). All
  traffic between the two halves (4 block rows each) goes through the neck. 75 inner crossings: 61 4-way, 14 T (the band's
  edges and the neck's sides), 6 grid points gone; `neck_streets=3`.
- **Holes**: `HOLE_COUNT` = 4 holes of 2 x 2 blocks whose inner cross (the 4 streets meeting at the hole's center) is left
  out (16 pieces); centers on lines 2..8 both ways, never the center (the town's center), at least 3 lines apart (no two
  holes share a street); placed by a pattern (`HOLE_PATTERNS` = 12, Park-Miller shuffle, greedy pick; pattern =
  `(seed - 1) % 12 + 1`): the same in every city of a run and for the same seed. 77 inner crossings: 61 4-way, 16 T.
- Both keep the grid one network with the town's center (0, 0) on a 4-way crossing (tests: test_grid_layouts, a BFS over
  the kept streets, every layout, size and pattern).

**How the gaps stay free.** The streets are never built (not bulldozed later: a town that grew along them would keep
its houses and lots, and the lock pass would have locked them): the grid construction takes two more params,
`sqst_grid_layout` (1 plain / 2 hourglass / 3 holes) and `sqst_grid_holes` (the pattern), sent only by the city run
(`towns.createGrid` opts `gridLayout` / `gridHoles`; every other build sends the same params as before). The town then
lines the remaining streets with houses; run 2's log shows a town created on our locked grid builds no street of its
own (lock pass `unlocked=0`) and none during the size command (`outside_streets=0 inside_new=0`), and locked streets are
never branched from (towns.md). As a guard, after the lock pass every street whose middle lies `GAP_MARGIN` = 12 m inside
a gap (hourglass gaps reach 20 m past the ring line) is removed, one proposal per city, before the size command (the same
removal also covers a game that dropped the params: the full grid's gap pieces go): `[SQST] CITY_GAPS ... at=build
gap_streets= removed=`. At the record's end the gaps are counted again (no removal): `CITY_GAPS ... at=end`; a non-zero
count means the town grew into a gap during the run (note it; the lock should prevent it).

**Lights**: every inner crossing with 4 streets, and in a funnel layout with 3 (`cityInterior` minDeg 3), lit as before;
the CITY line counts `found4= found3= lit4= lit3=`.

**Log keys added (v2)**: `BENCH_START ... layout= busy= role_swap=` (baseline_s= was there); `bench_city ... layout= busy=
baseline_s= role_swap= neck_streets= holes= holes_pattern= holes_at=i:j,... x4= t3= weights=`; `bench_city_lights: ...
lights on (layout= found4= found3=)`; `CITY ... layout= neck_streets= holes= found4= found3= lit4= lit3= pop= gap_streets=
gap_removed=`; `CITY_GAPS id= pair= role= at=build|end layout= gap_streets= removed=`; `CITY_ENROLL ... layout= busy=
role_swap=`. The report (FLOW.md "Auto lights at scale in the report"): one part per run, the options, each pair's
baseline gap with a warning over 10 %, and with runs of both roles their swapped-roles mean.

Files: stress_grid_streets.lua (`LAYOUTS`, `layout`, `holeCenters`, `layoutEdges`, `inGap`, `edgeKey`), the grid
construction (two params), stress_bench.tl (`citySheet`, `CITY_*` options, `cityLayout`, `cityHolesPattern`,
`cityOptionKeys`, `cityOptionsText`, `cityGapLine`, the swap in `cityPlan`, minDeg in `cityInterior`), gui/stress_towns.tl
(`gridEntity` params), gui/stress_citylights.tl (gap clear and check, kinds, pop, weights), gui/stress_bench_run.tl
(`cityUi`, `sheetFor`, Same seed, `gapCheck` at the end), gui/stress_hud.script.tl (rows, dialog), tools/flow_report.py.
Tests: test_grid_layouts, test_bench "city lights options" / "run: the city run with options", test_citylights
"Hourglass", test_towns "batched grids with a layout", tests/tools CityLightsTest.

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
