# Organic Towns: history

Finished phases, past run logs and result tables, superseded designs, moved verbatim from the other plan docs
(newest first, dated). Read it only to learn why something is the way it is.

## 2026-10-16: seed `a` with §71 small woods + hooks (session `2026-10-16_1846_sqot`, load 2; page `compare/2026-10-15_a-lock`, run mod-71)

Same setup as 0405 (EU, 1900, Quick 40, calendar moved, `lock=steer`). Load 1 of the session was another map
(`fFcqAYSZqB`). 0 mod errors (base GUI `selector_react_util` traces only), 0 STALL lines.

| | 0405 (§70) | 1846 (§71) |
|---|---|---|
| Game-built share of non-core edges | 0.32 | **0.34** (699 game / 1381 mod) |
| forestLot sum | 35.8 ha | **31.1 ha** (the lowest of the series) |
| Buildings / capacity at year 40 | 9079 / 97 % | 9384 / 97 % |
| knotHeld / hookHeld / smallWood | 38 / - / - | 50 / 75 / 647 |
| Refunds | 159 paid | 164 paid, 10 not charged, 4 mismatch |
| Offshoot towns | 4 | 4: Merehythe Forge (y20), Brantmerehall (y24), Wheatden Timber Yard (y32), New Seven Oaks (y36) |

- Game share by town: Hornholt Isle 0.75, Merehythe 0.65, Seven Oaks 0.54, Two Waters 0.46, Far Ashworth / Wheatden
  0.43, Lower Arunmouth 0.36, Shaw **0.28** (0.07 in 0405), Norfield 0.29, Dovemouth 0.28; still low: Dalemere 0.02,
  Little Dalemere 0.05, Ashgrove 0.11.
- Shots (main session review): Shaw now a compact organic town (no bare spokes, the game's fill around the core);
  Merehythe a dense organic shore town, no knots or hooks; Dalemere dense and organic between the lake and the woods,
  a few long straight streets and a rectangular loop on its south edge.
- The series' best result: forest loss down from 50.3 ha (0629) to 31.1 ha with the same capacity, no stalls.

## 2026-10-16: §71 built offline (small woods, hooks)

From run `2026-10-16_0405_sqot` (game share 0.32; Shaw 0.07, Dalemere 0.12, Little Dalemere 0.15 with their rims locked
against small woods; a few curled "P" dead ends in Merehythe and Shaw): the steer lock's face rules (mod and game
streets, valves, tips) count only woods of at least 1.75 ha (a patch of dense cells in the town's forest grid; BUILT /
CHECK `smallWood=`), and a steer town's chosen piece that would leave a dead-end street curling over 120 deg or back by
its own street is left out of the increment (kept only when that would empty it; PLAN / STREETS `hookHeld=`). Details:
NEXT_PHASE_BRIEF 71, PLAN.md 6.2 "Steering lock policy (§69)", "§71"; next in game: TESTING.md "Real play (first)"
(the seed `a` check, Combined test iteration step 20, is optional).

## 2026-10-16: seed `a` with §70 maturity + knots (session `2026-10-16_0405_sqot`; page `compare/2026-10-15_a-lock`, run mod-70)

Same setup as 2031 (EU, 1900, Quick 40, calendar moved, `lock=steer`). 0 mod errors.

| | 2031 (§69) | 0405 (§70) |
|---|---|---|
| Game-built share of non-core edges | 0.24 | **0.32** (675 game / 1456 mod) |
| forestLot sum | 32.2 ha | 35.8 ha |
| Buildings / capacity at year 40 | 9215 / 98 % | 9079 / 97 % |
| STALL | 0 | 1 (Watersmeet, level 1, year ~early, 159 buildings) |
| knotHeld | - | 38 |
| Refunds | 160 paid | 159 paid, 9 not charged, 5 mismatch |

- lockMat now 0.74-1.0 for every town over ~400 buildings (Holtbottom 0.44 at 283). Game share by town: Seven Oaks
  0.67, Far Ashworth 0.54, Two Waters 0.51, Merehythe / Wheatden 0.47, Hornholt Isle 0.38, Ashgrove 0.33; still low at
  full maturity: Shaw 0.07, Dalemere 0.12, Seachurch Cove 0.15, Little Dalemere 0.15, Norfield / Watersmeet 0.19 (the
  face rules: woods / water / lean near the rim).
- Shots (main session review): Two Waters the best of the series (compact, organic, the game's fill inside, no west
  bank sprawl, a short south tongue); Seven Oaks organic along the lake shore with the game's fill to the north;
  Merehythe's knots gone (a few small curled hook dead ends left); Shaw still mostly our locked radial spokes with two
  bare-ish arms west / south-west and a hook north-east.

## 2026-10-15: §70 built offline (steering lock tuning)

From run `2026-10-15_2031_sqot` (game share 0.24, the mid-size towns read young at year 40, Merehythe's south
knotted, Two Waters' south into clearings) and the user's "yes tune it": the lock maturity is the larger of the
persons measure, the town's size and its age since the first frame (frame `fy`); a knot look rule on the curves
(crossings off a shared node, long near-parallel runs, small loops; steer towns, relaxed only when the increment would
be empty); a narrow clearing between woods faces forest and takes no tip. Details: NEXT_PHASE_BRIEF 70, PLAN.md 6.2
"Steering lock policy (§69)", "§70"; in-game test: TESTING.md "Combined test iteration" step 19.

## 2026-10-15: seed `a` with §69 steering lock (session `2026-10-15_2031_sqot`; page `compare/2026-10-15_a-lock`, run mod-69)

EU, EU_ORGANIC, 1900, Quick 40, calendar moved, `lock=steer`. 0 mod errors (two base GUI `selector_react_util` traces),
0 STALL lines.

| | 1936 (lock all, §67) | 2031 (steer, §69) |
|---|---|---|
| Game-built share of non-core edges | 0.22 | 0.24 (468 game / 1460 mod) |
| forestLot sum | 34.7 ha | **32.2 ha** |
| Mean forestCut per plan | 0.124 | 0.171 |
| Buildings / capacity at year 40 | 9709 / 98 % | 9215 / 98 % (44478 / 45228) |
| GLOCK | 1080 ok / 8 refused | 801 ok / 9 refused |
| Refunds | 34 paid, 162 mismatch | **160 paid**, 16 notCharged (the REFUND_TOL fix works) |
| Tips (valves) | - | 31 open / 25 close |
| PLAN holds | - | spikeTrim 344, wiggleHeld 226, rakeJoin 7, rakeHeld 1 |

- Game share per town follows maturity: the mature towns (lockMat 0.96-1.0: Two Waters 0.63, Dovemouth 0.68,
  Merehythe 0.57) let the game fill; the towns read as young at year 40 (lockMat 0-0.16: Holtbottom, Dalemere, Shaw,
  Little Dalemere, Norfield) stayed 0.00-0.34. The 0.35-0.5 map target is missed because most towns never read as
  mature.
- Shots (main session review): no bare spikes (Shaw's V spike, Seven Oaks' 600 m roads and Merehythe's 1 km bridge road
  are gone), no rakes; Seven Oaks a compact town along the lake meadow; Shaw a compact core with the game's organic lobe
  to the north-west at a tip; Two Waters' interior filled by the game. Left: Merehythe's south has tangled crossing
  curved locked streets (knots); Two Waters' south still grows into the clearings between woods.

## 2026-10-15: §69 built offline (the steering lock)

From run `2026-10-15_1936_sqot-glprobe` load 2 (every street locked: game share 0.22, forestLot 34.7 ha, but bare
locked spikes, rakes, a zig-zag arm and less organic texture) and the user's "not lock all roads, just many of them,
especially early ... a locked branch out into an open space, then unlocking at the end": towns framed from now on get
the "steer" lock (frame `lm = 2`; ot_lockpol: lock what steers, the inside left to the game's fill as the town
matures, game streets locked only at the rim toward forest / water / neighbours / against the land), locked branches
with an open tip (a tip valve), the lead beyond housed streets capped at 150-250 m with a continuous arm front, bridges
with a target or short, rake and wiggle rules. Old saves' towns keep their lock. Details: NEXT_PHASE_BRIEF 69, PLAN.md
6.2 "Steering lock policy (§69)"; in-game test: TESTING.md "Combined test iteration" step 18.

## 2026-10-15: seed `a` with §66-§68 and housed game streets locked (session `2026-10-15_1936_sqot-glprobe`, load 2)

EU, EU_ORGANIC, start 1900, Quick 40 years, **calendar moved** (first run with the new default), `lock=mod`,
`townGrowth=deliveries` (the Simulate makes no deliveries, so no RCI writes), `WITH_HOUSES` on. 0 mod errors (two base
GUI `selector_react_util` traces at quit).

| | 0759 (§65 only) | 1936 (§67 + housed lock) |
|---|---|---|
| Game-built share of non-core edges | 0.58 (1704 / 1231) | **0.22** (504 game / 1743 mod) |
| forestLot sum | 46.9 ha | **34.7 ha** |
| Mean forestCut per plan | 0.172 | 0.124 |
| forestHeld | 181 / 289 | 139 / 285 |
| Buildings at year 40 | 10480 | 9709 |
| Capacity at year 40 | 44385 / 45183 (98 %) | 44183 / 45246 (98 %) |
| Offshoot towns | 3 | 4: Merehythe Clayworks (Works, y16), Brantmerehall (district, y20), Arunmouth Mill (y28), New Seven Oaks (y32) |

- GLOCK: 1080 edges locked (737 game, 343 core), 8 refused, 1 backoff; 199 lock builds. VALVE: 86 open, 61 close,
  27 want (stubs). No STALL line.
- The same capacity with 7 % fewer buildings: the moving calendar (later eras, bigger buildings), not missing growth.
- Dovemouth-in-the-Forest (deep) 753 buildings, no longer the biggest (Two Waters 1037, Merehythe 940).
- Refunds: 198 refund lines, 34 `paid` (0.40 M of 1.66 M), 162 `mismatch` with the balance change far above the cost
  (the Quick sim's months pass between send and callback). Fixed after the run: REFUND_TOL has no upper bound now,
  so the cost itself is booked back whenever at least half of it left the balance.

## 2026-10-15: §67 lock probe found a bug: every edge was refused (session live 2026-10-15 ~19:30Z, a base-game save)

The TESTING step 16a probe on a base-game save ("Act on: New towns only", towns `SKIP reason=existingTown`) printed
`preOk=false` with no messages. A diagnostic probe showed `E.lockProposal` skipped the edge as `read`, and a field probe
(`GLPROBE3`) showed every field it reads was fine (type 0 = NORMAL, objects 0, unlocked, nodes 127136/101057). Cause:
`why = okF and w or "read"` in `ot_engine.lockProposal`: for a lockable edge `w` is nil, so the expression gave "read"
and every edge was refused; §67's game-street locking could never have locked anything. Fixed (`if okF then why = w
else why = "read" end`) with a regression test on a fake api in `test_glock.lua`. Gate: 901 passed, 0 failed. The
houses-survive question is still open: the probe must be run again after a game restart (the console's `ug_require`
keeps the old module).

## 2026-10-15: §68 built offline (small follow-ups)

The dev Quick now moves the calendar by default (every Quick run had logged `moveDate=false`); the coupled seeded
decisions (equal-length labels were one draw shifted: forestMode / forestDeep / entryTrees, shape / arms3 / metro,
satellite / shoreForm / siteStyle, ...) draw with `rng.decide`, old frames keep `rng.unit` (frame `dv`); company towns
reach ~1.7 km (0 -> 5 of 16 archived maps); the game-street lock's rebuild charge is booked back. Details:
NEXT_PHASE_BRIEF 68, PLAN.md 6.2 "Small follow-ups (§68)"; in-game test: TESTING.md "Combined test iteration" step 17.

## 2026-10-15: §67 built offline (lock the game's own streets, valves)

From run `2026-10-15_0759_rci-sqrl` load 2 (the game still built 58 % of the non-core edges off its own unlocked
streets): the game's houseless new streets (and the core's) are rebuilt locked soon after they appear (no in-place
setter exists), a few valves per town stay open toward open land and rotate, the stall guard opens extra valves; frame
`gk`, saved ids `gx`. Details: NEXT_PHASE_BRIEF 67, PLAN.md 6.2 "Game-street locking and valves"; in-game test and the
console probe: TESTING.md "Combined test iteration" step 16.

## 2026-10-15: §65 built offline (lock every mod-built street)

From run `2026-10-15_0629_sqot` (the game built ~2/3 of the new streets): every street the mod builds is now locked
in towns framed from this build on (frame `lm`), old towns keep the shape lock; a capped stall guard keeps the supply
up; CHECK / STREETS log mod vs game edges. Details: NEXT_PHASE_BRIEF 65, PLAN.md 6.2 "Lock every mod-built street,
the stall guard"; in-game test: TESTING.md "Combined test iteration" step 14.

## 2026-10-15: seed `a` with §65 "lock every mod-built street" (session `2026-10-15_0759_rci-sqrl`, load 2)

Same setup as 0629 (EU, EU_ORGANIC, 1900, Quick 40 years, calendar not moved), `lock=mod`. 0 errors, 0 STALL lines
(the stall guard never fired), no STREETS line (the session was shorter than its 600 s period).

| | 0629 (legacy lock) | 0759 (lock=mod) |
|---|---|---|
| Buildings at year 40 | 11107 | 10480 |
| Game-built share of the non-core edges | about 2/3 (from `ownEdges`) | 0.58 (1704 game / 1231 mod) |
| forestLot sum | 50.3 ha | 46.9 ha |
| Mean forestCut per plan | 0.216 | 0.172 |
| forestHeld | 238 / 278 plans | 181 / 289 plans |
| Offshoot towns | 2 | 3: Arunmouth Mill (district, y16, quota), Watersmeet Ironworks (Works, y24), New Merehythe (Works, y32) |

- Per town the game's share ranged 0.35 (Seachurch Cove) to 0.81 (Seven Oaks); Two Waters 0.70, Merehythe 0.72,
  Lower Arunmouth 0.69. The game branches off the unlocked starting core and then off its own new (unlocked) streets,
  as §65 expected. LOCKCHK in game: 31 of 142 street edges locked within 600 m of (-4707, -5425) (Merehythe).
- Locking our streets moved the share a little and the wooded lots a little (-7 %); the game's own streets remain the
  main source of forest loss.

## 2026-10-15: seed `a` after §61-§64 (session `2026-10-15_0629_sqot`)

Same setup as `2026-10-15_0539_sqot`: EU names, EU_ORGANIC, start 1900, Quick 40 years, calendar not moved. 0 errors.

| | 0539 (before §62-§64) | 0629 |
|---|---|---|
| Buildings at year 40 | 10661 | 11107 |
| Forest modes | 11 hug / 4 clear / 1 deep | the same |
| forestHeld (sum over plans) | 153 / 262 plans | 238 / 278 plans |
| Mean forestCut per plan | 0.198 | 0.216 |
| forestLot sum | 46.1 ha | 50.3 ha |
| Offshoot towns | none (5 bare street satellites) | Wheatden Timber Yard (Works, y12, 34 buildings), Blackmerehall (district, open site, y24, 70) |

- Names are the same as 0539 (deterministic per map). Character towns: Seachurch Cove (harbour cove), Hornholt Isle
  (island town), Dovemouth-in-the-Forest (deep forest, again the biggest town: 1122), Far Ashworth (secluded). Other
  towns scored for harbour cove / garden city / waterfront but hit the map quota (`applied=no:quota`).
- SKEL: 8 shaped towns got a skeleton. Most arms came out `short` (200-800 m, clearance 70-90 m) on this heavily wooded
  map; Norfield was boxed on both arms, Wheatden and Little Dalemere on one, 5 arms dropped for wood. Compact towns
  (Watersmeet, Dalemere) only moved a hotspot.
- The wooded-lot numbers did not fall: the holds fired more often (forestHeld 153 -> 238), but the lots placed in woods
  per building stayed about the same. Offline the skeleton cut wooded lots sharply; in game the unlocked demand growth
  still fills into the woods.

## 2026-10-15: seed `a` after the landscape pull (session `2026-10-15_0539_sqot`)

Seed `a`, EU names, EU_ORGANIC, start 1900, Quick 40 years, calendar not moved; the first run with §62's landscape
pull. Every town got a LAND line (k 0.09-0.35). Against the same map before §62 (`2026-10-14_1927_sqot`, 1900): hug
mode 11/16 towns vs 8/16, mean `forestCut` per plan 0.20 vs 0.23, buildings at year 40 10,661 vs 13,192. A small
effect only: §62 reorders the planned pieces and moves the hotspots, but the shaped towns' arms (their cheapest
corridors, locked as "arm" streets) still went out at their seeded headings, e.g. Far Ashworth's W arm into
`forest:W`. The head start was cut after 1 job by the Quick run (`HEAD done ... cut=simgrow left=79`), so the early
arms came from the sim's demand increments. Seachurch Cove's LAND line read `cues=open:N,forest:N` (a cue naming
bug). The user:

> "it still seems like the towns take over forest too quickly. the initial locked streets play an important part of
> the early growth, and they aren't drawn aggressively enough in some situations. remember that roads built houses on
> them, which then take over the forest. so ideally we take that into account when considering spacing"

Next phase: §63 "landscape-aware skeleton" (NEXT_PHASE_BRIEF 63).

Offshoots in the same run (read 2026-10-15 for §64): no Works or district town at all. SATPACE founded 5 (simulated
years 12 / 20 / 24 / 32 / 40, `minGap=4.0`), all streets-only satellite seeds: Far Ashworth (1916:7517, 1000 m out),
Two Waters (-873:917, 1200 m, link 667 m), Dovemouth-in-the-Forest (682:-5989), Merehythe (-4817:-5736, hamlet
fallback), Wheatden (1293:2030, a crossroads hamlet); Lower Arunmouth's seed was refused (`ok=false`, refund). Every
`SATELLITE built` read `near=0`; on the tour they were bare X / T crossings. WORKS `why=rare`: Wheatden, Lower
Arunmouth, Merehythe, Seven Oaks, Shaw, Norfield, Dalemere, Watersmeet, Holtbottom; DISTRICT `why=rare`: Wheatden,
Lower Arunmouth, Seven Oaks, Shaw, Little Dalemere, Ashgrove; Two Waters' Works (k=1) and Dalemere's district (k=0)
passed but waited (`spacing` / `sameRound` / `deferred`) to the end; character towns (Seachurch Cove, Hornholt Isle,
Far Ashworth, Dovemouth-in-the-Forest) `why=character`. The user: "I don't see any satellite towns" (the separately
named towns). Analysis and changes: NEXT_PHASE_BRIEF 64.

## 2026-10-15: US names, European build style, start 1900 (user run, about 04:35-04:40Z; log lost)

The user's own run: US name list, a European build style, start 1900, Quick to about 1940. Five screenshots (Desktop,
`Screenshot 2026-10-14 at 9.40.*`): Oakport (lake shore), Twin Rivers (both banks of a river, bridge), Lake Stone
(long strip along a river), Lower Deer Forks (round, river to the north), Buffalo Prairie (round, open prairie to the
south). The log is lost: the last archive of the session (`2026-10-15_0429_sqot-sqrl`) was taken at 04:34Z, and the game
was restarted at 04:41Z, which rewrote `stdout.txt`. Run `make logs` before restarting the game.

- Names: all five are descriptive US names that fit the place (lake, two rivers, river forks, prairie), with no opaque
  coinages. They follow §60.
- Shapes: the towns read as organic (curving streets, closes, irregular blocks), not as US grids. That is what the
  European build style should give.
- Growth direction (the user's notes, red / green arrows): several towns pushed streets into or along woods on one side
  (Lower Deer Forks north and east, Twin Rivers' south-east fringe, Buffalo Prairie's north rim) while wide open land on
  the other side stayed empty (Oakport's south, Lower Deer Forks' south, Buffalo Prairie's south). Forest only acts per
  piece (ot_forest hug cost within 1.5 km, and only in hug / deep mode). The town's overall direction (ot_select
  `preference`: seeded sectors, coast lean, away from industry) never reads the woods. Next phase: §62 "open land
  pull".

## 2026-10-14: combined test iteration (session `2026-10-14_2237_sqot-dev`, loads 1-4)

TESTING.md "Combined test iteration". Load 1 is a Blank Slate showcase (2020). Loads 2-4 are seed `a`, Quick 40 years
with the tour, 0 errors on every map.

| Load | Map | Buildings 40 y | Characters | Page |
|---|---|---|---|---|
| 1 | Blank Slate showcase, 2020 | - | roundabout town (forced) | - |
| 2 | europe, temperate, 1900, Move date on (calendar 1900 -> 1940 only) | 1,992 -> 12,919 | **none picked** (`picked=0`, all `applied=no:low`); deep forest Milton-under-Edge | `compare/2026-10-14_a` (mod-2237) |
| 3 | usa, temperate, 1960 | 1,495 -> 9,266 | garden_city (Prairiewood Garden City), roundabout_town (Fletcherville Center, **0 rings**) | `compare/2026-10-14_a-usa` (mod-2237-usa) |
| 4 | usa names, **dry (first desert map)**, Town style European organic | 1,878 -> 10,496 | hilltop (Otterford Heights, rise 89 m), harbour_cove (Mirrorton Cove) | `compare/2026-10-14_a-dry` (new) |

- **Showcase (load 1):**
  - one-way rings in every size built with no refusals: l R49, m R34, s, mini;
  - EU organic's equal circles gone;
  - the roundabout town had only 3 rings in 18 increments (6 candidate crossings);
  - no pairs formed (7 tried, all `draw` at 0.14);
  - empty winding leads in the roundabout town and Shape cross;
  - a grid block left at EU organic's east edge.
- **Names:**
  - load 2: Brynhaven, Mytham, Aberdart, Lower Aberarun, Shaw, Padfield, Oakport, Ashworth, Hornness, Abercoed, Kelington, Edton, Winmere, Trefach, Wemmead, Milton-under-Edge (13 plain);
  - load 3: Walkerport, Three Rivers, Port Big Sandy, Shady Fork, Hayes Junction, Deer Forks, Prairiewood Garden City …;
  - load 4: Las Lomas, San Felipe, Los Cerritos (the Spanish area), Lyman Flats, Lower Pine Forks, Alkaliboro, Mesa Butte, Middle Fork, Mirrorton Cove, Otterford Heights. "Mesa Butte" stacks two landforms.
- **Bridge stops (load 2):** Arun Bridge (`bridge=1 bridgeRead=edge`), Bridge End and Bridgefoot (`bridge=end`), and an Arun Bridge East section variant.
- **Satellite pacing:**
  - load 2: 8 found (simulated years 8-40), one per 4-year round, 3 refunded on forest;
  - load 3: 6 found (12-36, one round skipped);
  - load 4 (desert): only 3 (20, 24, 36).
- **Densify:** drew on for only 1 of 16 towns (load 2) and 2 of 7 (load 3), not a third. Load 4 had 0 on of 4 draws.
- **Town style setting (load 4):** `regionSource=setting`, EU weights with the dry bias (9 EU_ORGANIC, 5 MED_HILL), US names kept.
- **Roundabouts in ordinary US towns:** rate 0.00 in 1960-2000.
- Open: NEXT_PHASE_BRIEF 57 (hubs for the roundabout town in organic and grid growers, pairs, empty leads, character calibration on load 2's sites, densify rate, the US ring rate).

## 2026-10-14: 203 simulated years on seed `a` (session `2026-10-14_1927_sqot`; page `compare/2026-10-14_a-203y`)

After the 40-year Quick (page `compare/2026-10-14_a`, run `mod-1927`), the user kept Simulate going for the 6 towns near
the camera (`scope=near r4000`), Move the game date off, to 203 simulated years, then toured every town (44 shots).
The calendar stayed at 1900 throughout. The user: "after a certain point towns should start building up their downtowns.
maybe it's just because the actual game year wasn't progressing while the simulation ran. some sprawling towns are good,
but some others should get dense at some point." Kept as a finding for later builds (NEXT_PHASE_BRIEF 52).

| Town | Buildings (start -> 203 y) | Capacity | Persons / building | r (m) | Style, form |
|---|---|---|---|---|---|
| Twywath-under-Dun | 287 -> 7,049 | 21,557 | 3.06 | 1,496 | EU_ORGANIC, linear |
| Swainby | 126 -> 3,601 | 10,282 | 2.86 | 1,045 | MED_HILL, linear |
| East Hornness | 165 -> 3,583 | 15,402 | 4.30 | 1,226 | NORDIC, shore |
| Little Merthorpe | 73 -> 1,980 | 5,630 | 2.84 | 961 | MED_HILL, shore |

Findings:
1. **No downtown.** Persons per building stayed at 2.8-4.3, against about 6.4 for true vanilla at 40 years
   (BASELINE_VANILLA.md). The towns only grew outward, to 1-1.5 km radius. Cause, mostly: with the calendar at 1900,
   level 3 / 4 town buildings don't exist yet (docs/findings/towns.md "Town buildings of levels 3-4 exist only from
   1950 / 1990"), and the level weights read `x/x/0/0` for every town (LEVELS lines). So no simulated length can make a
   1900 town tall. The mod also has no per-town "densify" phase beyond the mature hold.
2. **Huge empty street networks in the created Works towns.** They get no simulated growth (`rate=0 class=none`):
   - East Hornness Engine Works: 40 buildings, 456 edges, 33.0 km of street, 31.9 km of it empty;
   - Ashworthville: 37 buildings, 352 edges, 24.8 km, 24.8 km empty;
   - Aberdart Grange (district): 78 buildings, 175 edges, 10.7 of 12.9 km empty.

   Something keeps adding streets to towns that don't grow. It may be the mod, despite OFFSHOOT_HOLD_B, or the game's
   own industry streets. To check.
3. The mature hold worked as meant (MATURE lines, e.g. Little Merthorpe `mat=1.00 free=0.52`), but on its own it only
   slows the sprawl; it doesn't build up a core.

## 2026-10-14: seed `a` on five maps (session `2026-10-14_0814_sqot`, loads 1-6; Quick 40 years, tour)

First runs with the map-shape names (§45) and Quick cutting the head start. Pages: `compare/2026-10-14_a` (European,
run `mod-0814`), `compare/2026-10-14_a-usa` (`mod-0814-usa`), `compare/2026-10-14_a-asia` (new).

| Load | List, climate | Buildings 40 y | Time | Errors | Names |
|---|---|---|---|---|---|
| 1 | europe, temperate | 2,006 -> 14,006 | 142 s | 9x `ot_satellite.lua:240` (bridge, fixed §46) | 16 renamed, budget held (no word over 2) |
| 2 | usa, temperate | 1,472 -> 9,692 | 105 s | 0 | 16 renamed; Lake 1 (0710: 6); Spanish Fork / Grand Forks on forks |
| 3 | asia, tropical | 1,716 -> 11,002 | 138 s | 0 | **none renamed**: `NAMES why=noTags list=asia pool=0` |
| 4 | usa, tropical (island map) | 1,583 -> 9,974 | 107 s | 0 | 16 renamed (Key West, Staten Island, Cutler Bay …); misfits below |
| 6 | europe, tropical (same island map; load 5 an abandoned Asian reload) | 1,978 -> 12,249 | 129 s | 0 | 15 renamed + 1 kept: real English towns on tropical islands |

- Head start: `HEAD done ... cut=simgrow left=77 / 80 / 79` on all three (Quick at once).
- Survey (loads 1-2, same terrain): rivers 4, forks 11, mouths 11, falls 3, lakes 7, peaks 8, bays 11, 0.5 s.
- Load 3 findings (asia, tropical):
  1. Landscape names did nothing: the base Asian list is ~100 world megacities with no landscape words (docs/findings/towns.md),
     so nothing scores and nothing is renamed; the NAMES line still says `on=true`. Generated names fall back to Landscape
     for asia, so neither mode names an Asian map. The map survey never ran (it is part of the naming step).
  2. Satellite / Works names put English generics on Asian names: High Wuhan, Wenzhou Works.
  3. Styles: 14 of 16 towns JP_DENSE, 1 NORDIC, 1 EU_ORGANIC (`asia` maps to EAST_ASIA, JP_DENSE weight 3-4 x; tropical
     has no style bias), on a list that runs from Karachi to Seoul.
  4. CHARACTER quota counted a created town: `towns=16 count=2` then `towns=17 count=3` (Shanghai added after a satellite
     appeared). Satellites should not count toward the quota.
  5. 10 satellites built, 2 shown on the tour (High Wuhan, Wenzhou Works); coastal picks Xi'an 0.91, Nagoya 0.88.
- Load 4 findings (usa, tropical; survey `lakes=0 sea=true bays=37 capes=33 peaks=8`; page `compare/2026-10-14_a-asia`):
  1. Two towns tagged `lake:1.00` on a map with no lakes became "Lake in the Hills" and "Canyon Lake" (sea inlets read as
     lakes). The user: "make sure names don't sound silly - like lake in the hills on a tropical map where its all islands".
  2. Temperate words on tropical islands: Cottonwood Heights, West Hollywood; Marlborough fell to `match=plain`.
  3. Good fits: Key West, Staten Island, Fleming Island, Cutler Bay, Bayonet Point, Portsmouth (mouth), Mount Pleasant (peak).
- Load 6 (europe, tropical): Darley Dale, Penkridge, Ellesmere and Haslemere (lake tags on a map with no lakes), Chipping
  Campden, Swanscombe and Greenhithe, Northleach with Eastington, Queenborough-in-Sheppey, Harrogate kept. The user: "our
  names should all be heavily influenced from the region (tropical, subarctic, etc.) otherwise the naming falls apart. in
  landscape name mode i'd prefer not to use real existing city names, and instead all generated names from region and
  geography cues". Decision: Landscape mode composes every name (no real list names), with the climate as a first-class input.
- Open work: NEXT_PHASE_BRIEF 48 and 49 (plausible names: tags against the survey, climate fit, whole-name check).

## 2026-10-14: TESTING.md "Generated names test" (run 2026-10-14, session `2026-10-14_0613_sqot`, seed `a`)

Run with Generated names on seed `a` (Quick 40 years, tour): `NAMES mode=generated gen=en rivers=1 lakes=6 renamed=16 ok=31`,
15 industries renamed, no failures; no stops on the map (no STOPNAME line). Per-town verdicts and the misfiring tags
(edge everywhere, ash everywhere, vale on flat towns, spit / island / tarn / Upper): BASELINE_VANILLA.md "Seed a run
2026-10-14 0613" finding 6; fixed in NEXT_PHASE_BRIEF 44. Stop names with Generated names were never queued (the game
script gate, fixed 2026-10-14). The section, verbatim:

## Generated names test (2026-10-14; NEXT_PHASE_BRIEF 42; PLAN.md 6.3 "Generated names")

### Setup
- Main mod only (plus the dev mod if you want Simulate afterwards), Debug log On.
- New map, same seed as the comparison runs: **U8Qxgisp4I**, Europe (England list) or the list you play.
- Settings: "Town and stop names" = **Generated names**; the rest as in the last run.

After the run: `uv run plans/square_organic_towns/names/export_names.py --session <session>` loads the map's names into the
Name lab (`names/index.html`, tab "This map") to try alternatives for each town's site.

### Steps
1. Start the map and wait until the `NAMES on=true` line (the head start waits for it; at most 4 minutes).
2. Look at the town labels across the map: do the names read as real place names of that language? Do neighbours
   share a flavour (a run of -by / -thorpe towns in one area, -ton / -ham in another)? Do river towns carry the river
   ("-upon-<River>", "<River>mouth"), coast towns a sea name, hill towns a hill name, forest towns their trees?
3. Note any name that is clumsy, too long for its label, or (rarely) offensive; and any industry still named after a
   town's old name.
4. Build two or three bus stops by a river or a lake in a town on it: does the stop name use the river / lake name
   ("Avon Street")?
5. Play on until a district or Works is founded (or use the dev tool): its name in the DISTRICT / WORKS line
   (`src=generated` about 60 % of the time).
6. Optional: a second new map with the German or French list (game language German / French, or a map whose names
   are from that folder) and one with the Russia list (expect `mode=landscape fallback=noGenerator`).

### Lines to send
- `[SQOT] NAMES` (the summary: `mode=generated gen= fallback= rivers= lakes= renamed= sent= ok= failed=`).
- All `[SQOT] NAME town=` lines (`parts= feature= tags= river= lake= dialect= read=`) and the `NAME industry=` lines.
- `[SQOT] STOPNAME` lines of the stops from step 4; `[SQOT] DISTRICT` / `WORKS` lines with `event=create`.
- Two or three screenshots of the map with the labels.

## 2026-10-14: TESTING.md "Retune run after the 0302 run" (runs 2026-10-14, sessions `2026-10-14_0502_sqot` on seed
`Z2tNDhy0Ht` and `2026-10-14_0613_sqot` on seed `a`; never on `U8Qxgisp4I`)

Results: BASELINE_VANILLA.md "Retune run 2026-10-14 0502" and "Seed a run 2026-10-14 0613" (young towns branch out:
worked; grown towns build up: did not (LEVELS `skip=player`, no `why=free`); offshoots back, links regressed in 0613).
Follow-up: NEXT_PHASE_BRIEF 44, TESTING.md "Seed a run". The section, verbatim:

## Retune run after the 0302 run (2026-10-14; NEXT_PHASE_BRIEF 40; PLAN.md 6.3 "Round after the 0302 run")

One mod run on the **comparison seed** (`U8Qxgisp4I`, the 0119 / 0302 map settings), the new build. It checks that young
towns branch out again (the 0119 look), grown towns build up (the 0302 density), and satellites, districts and Works come
back. Then add it to the three-run page. The previous section's run A was done as `2026-10-14_0302_sqot-sqrl` load 2
(BASELINE_VANILLA.md "Density-round run"); its run B (the angle split) is still open.

### Setup

- Quit TF3 fully (old Lua modules stay loaded), `make link` (done). Main mod + dev mod. Organic Towns settings: Act on
  **New towns only**, Town and stop names **Landscape names**, Debug log **On**, Satellite towns **On**, Vanilla town
  street angles **Automatic**, the rest default (as 0119 / 0302).

### Steps

1. New map, seed text `U8Qxgisp4I`, European, the 0119 run's map settings, 1900. Wait for `HEAD done` (~1 min).
2. First lines: `[SQOT] ANGLE choice=auto ... angle=0/0->35`, `INIT ... capsBoost=0 ... levels=pbAim4.5`.
3. OT Dev, Simulate: Seed 1, Every town grows on, Tour on, screenshots on, Move the game date off, **Quick: 40 years**
   (since 2026-10-14 as fast as possible, ~95-110 s; section above). Wait for `SIMGROW stop`,
   then (a district or Works being created) `SIMGROW tour wait=create` -> `wait=done`, then the tour.
4. Save ("sqot retune"), quit. Tell Claude the session; it runs the compare below. (Build out, section above: after
   the save, on the same map.)

### Checklist (log lines)

1. No crash, no freeze; `grep -cE 'SQOT[_A-Z]*\] (ERROR|WARN)'` = 0.
2. **Young towns branch out:** CHECK `mat=0.00 demK=1.00` while a town is under ~1800 persons (`cap=<actual>/<target>`),
   `why=demand` / `ahead` again instead of `free` (0302: free 235 of 279). BUILT `trigger=demand` in the first ~20
   simulated years: 0119 had 170 demand builds, 0302 had 20; expect 100 or more. SIMGROW stop `roundBuilds=` well over
   17 (0119: 160).
3. **Grown towns build up:** CHECK `mat=` rising past 0.5 on the biggest towns in the second half (Stratford-upon-Avon,
   Penkridge, Telscombe, Ringwood, Windermere reach 3400-4000 persons), their `demK=` falling, `why=free` appearing only
   on them. `LEVELS ... action=set ... mat=0.5..1 k=` only on those (no `set` under `mat=0.5`; `skip=young` debug lines
   on the others). ALLTOWN `pb=`: small towns near 0119 (~3), the grown ones higher than 0119's (target ~4-5); the median
   between 0119's 2.9 and 0302's 6.3. `lvl=a:` levels 3-4 stay 0 (era A before 1950: expected).
4. **Offshoots back:** `OFFSHOOT event=turn for=satellite|works|district|link` lines; SATELLITE `built kind=seed`
   **>= 8** (0119: 8, 0302: 3), DISTRICT `event=created` and WORKS `event=created` (0119: 9 / 3, 0302: 0 / 0); some BUILT
   `trigger=offshoot` (a satellite seed or a link on a turn). `why=` of the WORKS / DISTRICT `event=none` / `on=false`
   lines: `rare`, `character`, `forest`, `noSite` are fine; `small` should be rare now (the size reads persons / 4).
5. **Form:** spread median back near 1.19 (0302: 1.13), 3-4 towns >= 1.3 (0302: 1), towns visibly different from the
   0302 shots on the page (arms, fingers, shore wraps), still no long straight empty lanes (PLAN `straight=`).

### Compare

```
uv run plans/square_organic_towns/compare/build_compare.py --out plans/square_organic_towns/compare/2026-10-14_U8Qxgisp4I \
    --add <session>:<load> --label 'Mod <hhmm> (maturity retune)' --dir mod-<hhmm>
```

`<load>` is the map load with the SIMGROW stop (`:N` = the N-th `Init game took`). Open `index.html` (works from disk),
pick A = the new run and B = each of the others; "All runs" shows the four in a row. Then a new dated section in
BASELINE_VANILLA.md (the four-way metrics as in "Density-round run").

## 2026-10-14: TESTING.md "Round after the 2240 run" (run 2026-10-13, session `2026-10-13_2355_sqot`)

New European map (`fresh=true`, 16 towns, Landscape names), stops built by hand, SIMGROW 40 years with tour shots, then a
vanilla load of another map (Act on Off) for BASELINE_VANILLA.md. Analysed in the round after the 2355 run (PLAN.md 6.3
"Round after the 2355 run", NEXT_PHASE_BRIEF 38). User: "I like the industrial offshoots like Haslemere Works ... push
offshoot towns more"; "Hills continue to be very interesting"; "more extreme coastal city hugging in at least 1-2 cities
per map. I like when bridges get created"; Works "closer to factories, like 2/3 distance"; High Wycombe "looked good in
the long narrow shape between forests"; Kirkby Lonsdale "finally ended up using one of the long arms"; stops: "more stop
names ... Bay Quay North, Old Bay Quay etc.".
Results per checklist item:
1. No crash or freeze, 0 ERROR, 0 WARN.
2. Stop names: 40 STOPNAME renames (kind theme 23, toward 8, tree 6, high 1, ind 1), 0 duplicates, 0 `why=noUnique`.
   Oddities: "Old Henley-in-Arden Road" (too long), "Bay Quay" (clumsy). Fixed: 28-character cap, town words, clumsy
   pairs, street-section variants.
3. Industry stops: one `kind=ind`.
4. Station beside an industry: Lower Ellesmere Station -> "Ellesmere Works" (`indDist=225 dist=2643 form=works`); two
   town-centre stations `why=noIndustry`.
5. Works: 2 created, Haslemere Works and Chorleywood Works (`kind=plain d=800`), neither linked: `event=link
   outcome=dropped why=notJoined` (Haslemere, joined=1), then `none why=crossing` x2 (Chorleywood) and `why=obstacle`
   (Haslemere). Fixed: ot_link (pairs, detours, back-check, all routes planned in turn), Works by a factory.
6. Keep-clear zones: active (`zones=1:422` ...), `zoneHeld=2` twice, 0 `REFUSED why=industryZone`.
7. Arms: `armWait=3` on 5 PLAN lines (271 with 0).
8. Lanes ahead: 4 built (Ampthill ribbon 9 lane edges, Skegness hamlet, Haslemere hamlet, Darley Dale hamlet), 3 FILL
   `why=leadEnd`. The vanilla comparison: long straight empty lanes ending in a T are the mod's most visible flaw.
9. Bridges: 14 towns `noRiver`, Bexhill `noSite`; Windermere (span 156 m, stone, deck 4.1) refused `Construction Not
   Possible` (0 collisions), Haslemere (span 116 m) refused `Collision` x8 with street entities beyond the snapshot
   (the lane ahead built a second earlier, or a country road); 0 built.
Also: 14 satellites built; shapes linear-dominated (152 of 276 SHAPE lines).

Section verbatim (TESTING.md, moved 2026-10-14):

### Round after the 2240 run (2026-10-13; NEXT_PHASE_BRIEF 37; PLAN.md 6.3 "Round after the 2240 run")

The previous run's results: HISTORY.md (2026-10-13, "Round after names run", session `2026-10-13_2240_sqot-dev`).
**Prefixes changed:** the dev SIMGROW's build round now logs under the main driver's `[SQOT]` (it is the main mod's own
turn); dev tasks (Forest lane test, Place test stops, showcase) stay `[SQOT_DEV]`. Grep both (`\[SQOT(_DEV)?\]`).

### Setup

- Quit TF3 fully, `make link` (done). Load **the save from the last run** (the 40-year European map: it already has
  stops named "The Grove" twice and many game-named stops, a good test for unique names; its saved new-map flag lets
  the Works start there). Same mods and settings as last time (Debug log On).
- Optional part B needs a **new map** (European, Large, hilly, many towns, 1900): lanes ahead and new arms.

### Steps (part A, the old save)

1. Load; wait ~1 min (`RUN`, a few CHECK lines).
2. **Stops:** build 10-15 bus stops by hand: next to the crop farm in Budleigh Salterton and next to 2-3 other
   industries (within ~300 m), in a wood, by a river / the shore / a lake, on a hill, in the centre, on the outskirts.
   Then OT Dev, Main mod tab -> **Place test stops: all towns** (dozens of stops at once).
3. **Station beside an industry:** build one passenger rail station next to an industry (within ~300 m of it, farther
   from the town centre than from the industry), and one in a town centre for comparison.
4. OT Dev, Simulate: Seed 1, Every town grows on, Tour on, screenshots on; **Quick: 10 years**. Leave it until
   `SIMGROW stop` and the tour shots. Save.

### Steps (part B, optional new map)

5. New map as above; load, wait for `NAMES` and `HEAD done`; Simulate Quick: 20 years with the tour. Save.

### Checklist (crashes first)

1. No crash, no freeze; `grep -c 'SQOT[_A-Z]*\] ERROR'` = 0; send any `WARN`.
2. **Stop names unique:** `STOPNAME ... kind= gen= uniq=`: kinds mostly `theme / tree / field / mark / compass / ind /
   toward`, `real` / `solo` rare. **No two stops on the map with the same name** (the game's included: look at the
   line manager's stop list or hover a few). `why=noUnique` (the game's name kept): how many? Debug `STOPNAME ...
   why=same` should be gone.
3. **Industry stops:** a stop beside an industry: `theme=industry kind=indName|ind ind=<kind> indName=<name>` ->
   "Crop Farm Gate", "Works Road", "Quarry Lane", "Farm Lane", "Brewery Lane", "Foundry Street".
4. **Station beside an industry:** `STOPNAME ... kind=station:rail indDist= dist= new=<Town> Quarry|Works|Farm ... form=`
   (or `<Industry> Halt`); the town-centre station: debug `why=nearerTown` or `noIndustry`, the game's name kept.
5. **Works on the old save:** `WORKS ... event=create works=<name> kind= site= d=` -> `event=created` -> `event=link
   outcome=plan ... joined=2` -> `event=linked` (at most 2 on this 16-town map). Or `event=none why=` / `refused`. No
   `why=notNewMap` lines any more. Fly there.
6. **Keep-clear zones:** PLAN `zones=n:r1/r2 zoneHeld= zoneLock=` on towns with industries near (Budleigh Salterton:
   `zones=` > 0 now, CHECK `ind=` not 0). No new mod street inside ~400 m of a farm's centre (~150 m of a factory);
   `REFUSED ... why=industryZone` lines (a satellite / lane / Works link refused for a zone), debug `FILL ...
   zoneDropped=`. The game's own streets may still go in (its growth has no such rule); the mod's streets beside the
   zone are locked (`zoneLock=`), so fewer of the game's branch in from them.
7. **Arms:** PLAN `armWait=` > 0 on towns with 3+ arms (cross / fingers): a new arm waits while another runs ahead.
8. (Part B) **Lanes ahead:** `LEADLANE ... outcome=plan ... endJoined=n/n` then `outcome=built`, then `FILL town= kind=dose
   why=leadEnd points=2`: after the 20 years, **houses at the lane's far end** (the hamlet T / the short ribbon, at most
   ~120 m). `outcome=dropped why=endLoose` if an end street came out loose.
9. Forest edge (keep): Verwood-like towns still keep their woods (shots).

### Log lines to send

`grep -E '\[SQOT(_DEV)?\] (INIT|STOPNAME|TESTSTOP|LEADLANE|WORKS|REFUSED|ERROR|WARN)' stdout.txt`, a few PLAN lines with
`zones=` (Budleigh Salterton), the FILL `why=leadEnd` lines. Or just "done" + the save names: the session is archived
(`make logs`).


## 2026-10-13: TESTING.md "Round after names run" (run 2026-10-13, session `2026-10-13_2240_sqot-dev`)

New European map (`SAVE event=init fresh=true`), 16 towns renamed (`NAMES ... renamed=16 fit=16`), 12 road stops built
by hand (no "Place test stops"), Forest lane test, SIMGROW 40 years with tour shots (s0 Budleigh Salterton, s9 Verwood,
s15 Tickhill); no reload. Analysed in the round after the 2240 run (PLAN.md 6.3 "Round after the 2240 run",
NEXT_PHASE_BRIEF 37). User: "still too many duplicate bus names. a lot of them are The Grove"; "stations next to a
factory should use the factory naming as a cue"; "long offshoot roads don't actually get houses on them (lanes
ahead?)"; "did any work towns get set up?"; Salterton "built completely around the crop farm"; forest edge "hard to
tell ... Verwood seemed very successful in that regard".
Results per checklist item:
1. No crash or freeze, 0 ERROR, 0 WARN. 49 of 605 CHECK lines over 15 ms in one slice; `parts=` says the street read:
   Darley Dale 90 ms (`str:84449`), Skegness 57 ms (`str:52749`), Budleigh Salterton 56 ms (`bld:21731,str:26051`).
2. Stop names: all 12 STOPNAME `kind=real gen=-` (the list's real names came first, the composer never ran). Group
   110136 kept the game's "The Grove" (`why=same`), 38 s later group 107957 was renamed "The Grove" too: the map-wide
   names were cached for 60 s and the game had named 110136 after the read. A stop 2.9 km out with `ind=works` got
   "Meadow Way". Fixed: live used set, composed names first, industry theme, richer composer.
3. Henley-like stray lanes: none. FORESTLANE keys `rg` / `ln` only, 91 `check=true` lines.
4. Forest lanes in hug towns: Skegness `why=hug:...,freed` built (3 edges, 84 m); dev Chorleywood built 3 edges; 3
   skipped by the draw. LANETEST `why=noForestCrossing tried=8` (dry runs empty / no lane in the 8 forest towns).
5. Lanes ahead: 2 built (dev prefix: the build round's drivers): Tickhill ribbon (8 lane edges, 437 m, 5 end edges, far
   end 800 m out), Verwood hamlet (7 lane edges, 596 m through forest); 14 towns `why=rare`. Shots: Verwood's far T has
   no house after 40 years, Tickhill's far streets few (findings towns.md "Town streets at the far end of a long
   country lane"). Fixed: far-end dose, ribbon at most 120 m, ends must hang on the lane; new arms wait (3+ arm towns).
6. Forest towns: FOREST `lock=1..8 side=1..2` on 38 towns' reads; `forestBudget=...:growth` 158, `:first` 40 (the
   budget windows work). The user: "there are definitely some preserved areas. Verwood seemed very successful".
7. Works: none. Every `[SQOT_DEV] WORKS ... on=false why=notNewMap` (the build round's drivers had no new-map flag) and
   they marked the shared town state done, so the main driver's own 27 demand builds skipped the Works silently. Fixed:
   the pool drivers inherit newMap / listDir and log under the main prefix.
8. Station facing away: not built; every station_quarter `side=town`.
9. Names: no reload this run (open).
Also: Budleigh Salterton grew 206 -> 2856 buildings round its crop farm, the mod built 195 of 919 edges, every CHECK
`ind=0` (the farm beyond the fixed 1500 m industry read): findings towns.md; keep-clear zones added.

### Round after names run (verbatim from TESTING.md)

The previous run's results: HISTORY.md (2026-10-13, "Forest / gaps / bridges round test", session
`2026-10-13_2113_sqot-dev`). Every line is `[SQOT] ...` unless `[SQOT_DEV]`. **The dev SIMGROW's plans log under
`[SQOT_DEV]`** (they run on the dev runner's drivers): grep both prefixes (`\[SQOT(_DEV)?\]`).

### Setup

- Quit TF3 fully, `make link` (done). **New game**, map **European**, size **Large**, relief **hilly**, forests more (or
  default), a coast, lakes and rivers, many towns, start **1900**, game language English, throwaway save.
- Mods: `square_organic_towns` + `square_organic_towns_dev`. Main mod defaults (New towns only, Street style Automatic,
  Starting town size Game size, Town and stop names = Landscape names, Streets at industries Game default), **Debug log
  On**, Testing: grow towns faster Off.

### Steps

1. Load; wait for `NAMES ...` and `HEAD done`.
2. **Stops:** build 10-15 bus stops across 3-4 towns: some on the outskirts on the road toward a neighbouring town,
   some in a wood, by a river or the shore, on a hill, by a station, by an industry, in the centre. Optional: OT Dev,
   Main mod tab -> "Place test stops: all towns".
3. **Station facing away** (still open from the last round): one passenger station 300-800 m from a town with its
   building facing away from the town.
4. OT Dev, Town tab -> **Forest lane test** with **no town picked** (it finds one); wait for the last `LANETEST` line.
5. OT Dev, Simulate: Seed 1, Only towns near the camera off, Every town grows on, Tour all towns when stopped on,
   screenshots on; **Quick: 40 years**. Leave it until `SIMGROW stop` and the tour's shots. Save.
6. Save, quit, reload the save once (names / lead / Works flags).

### Checklist (crashes first)

1. No crash, no freeze; `grep -c 'SQOT[_A-Z]*\] ERROR'` = 0; send any `WARN`. **CHECK `sliceUs=` and the new `parts=caps:..,
   map:..,bld:..,str:..,fin:..`**: send the 10 slowest CHECK lines (77 of 786 were 15-62 ms in one slice last run; the
   parts say which read is slow).
2. **Stop names:** `STOPNAME ... new= theme= kind=real|solo|toward|tree|theme|ind|compass|high|own gen= uniq=left/total
   toward= ind= trees= compass= high=`. **No two stops on the map with the same name.** Do they fit? A stop on the road
   toward Ferryhill: "Ferryhill Road" (`kind=toward`); in a wood: a tree of the town's forest ("Beech Copse", `trees=`);
   by a river: Mill / Bridge / Ford / Weir; on the shore: Harbour / Anchor / "<Town> Quay"; on a hill: Rise / View /
   Heights, "Upper ..."; by works / a quarry: "Works Road" / "Quarry Lane"; centre: High Street / Market Place / Church /
   King Street. A stop the game named after an industry keeps that name (`why=industry`). FOREST `species=oak:..,pine:..`
   (the tree species read: the stop names' trees come from it). Rename one right after building: `why=renamed`.
3. **Henley-like stray country roads:** none. FORESTLANE `edge=` keys never start with `bk` / `sr` / `q` / `conn`; every
   lane is one stretch with town streets at both ends (`edges=` >= 2, `len=` 60-400). Debug `FORESTLANE ... check=true
   wooded= joined= line= lineKey= tip= short= long= runs= freed=`: send a few (why wooded edges made no lane).
4. **Forest lanes in hug towns:** `FORESTLANE ... why=hug:...,freed` (a held crossing let through as a lane), `outcome=
   built`. Fly to one: a dirt / asphalt lane through a strip of forest between two parts of a town, no houses on it.
5. **Lanes ahead:** `LEADLANE ... outcome=plan target=neighbour|satellite|axis|frame heading= len= laneEdges= laneLen=
   endKind=hamlet|ribbon endEdges=` then `outcome=built far=x:y`; `outcome=none why=` / `refused` lines too. About a
   quarter of the towns at most. Fly to one: a country road out of town toward the next town (or along its axis), a
   T or a short street at its end. Later shots: do houses / streets grow at its far end? (the game builds there itself;
   the mod doesn't dose it). Never past the halfway line to the next town, no houses along the lane.
6. **Brentwood-like forest towns:** debug `FOREST town= lock= side= tip=` (streets facing the forest locked); PLAN
   `forestBudget=left/total:first|decade|growth` (a new window as the town grows). Shots of a hug town by a forested
   slope: does the game still push its own streets deep into the forest? Compare with Brentwood (shot s3 last run).
7. **Works:** `WORKS ... event=create works=<name> kind=harbour|rail|across|plain site= d=` -> `event=created works=<id>`
   -> `event=link outcome=plan ... laneEdges= joined=2` -> `event=linked`; or `event=none why=` / `refused`. At most one
   per 8 towns (1-3). Fly there: a small industrial town 0.8-1.5 km out, linked by a road (country middle), named after
   its parent ("<Town> Works" / "Docks" / "Junction"). After the 40 years: industrial mostly? After the reload: no
   second Works (`wk` saved), no WORKS create lines.
8. **Station facing away:** MOTIF station_quarter `side=back`, `sides=` rising, `link=` > 0.
9. **Names (still open):** after the reload `NAMES on=false why=done`, no rename. Optional: a second new map with
   "Game names" (`why=setting`), a map in German or French (stop names in the list's language: "Eichenweg", "Rue des
   Chênes").

### Log lines to send

`grep -E '\[SQOT(_DEV)?\] (INIT|NAMES|STOPNAME|TESTSTOP|FOREST |FORESTLANE|LANETEST|LEADLANE|WORKS|SATELLITE|ERROR|WARN)' stdout.txt`,
the 10 slowest CHECK lines (`sliceUs=` / `parts=`), and a few PLAN lines of a forest town (`forestBudget` / `lanes`).
Or just "done" + the save name: the session is archived (`make logs`).


## 2026-10-13: TESTING.md "Forest / gaps / bridges round test", "Landscape names test", "Landscape stop names" (run 2026-10-13, session `2026-10-13_2113_sqot-dev`)

New European map, 16 towns, SIMGROW 40 years with tour shots (s3 Brentwood, s8 Henley-in-Arden); analysed in the round
after the names run (PLAN.md 6.3 "Round after the names run", NEXT_PHASE_BRIEF 36). User: satellites "create really
interesting dynamics", Haslemere circling its mountain "fantastic", Skegness's long arms "cool", Ellesmere Port with its
Works "looks awesome together", names "look appropriate"; Brentwood "could have maybe saved more forest"; Henley-in-Arden
"has some random country roads mixed in"; stop names: "only a pool of a few, so there's tons of duplicates".
Results per checklist item (forest round test):
1. No crash or freeze, 0 ERROR, 0 WARN; `hangGuard=off`. PLAN at most ~14.5 ms per slice. CHECK split over two ticks, but
   77 of 786 CHECK lines still took 15-62 ms in one slice (Ferryhill Works 62 ms, Brentwood 60 ms): `parts=` added.
2. FOREST shares 0.24-0.40 on the wooded towns (no more `none` at stride 5); `renew=first` 21, `renew=builds` 46.
   Brentwood's 2 ha clearing budget was spent in the head start (1.6 -> 0.4) and never came back (budget windows added).
3. Forest lanes: 0 `[SQOT]` but 11 `[SQOT_DEV] FORESTLANE` lines (the SIMGROW plans' prefix): 3 built (Sandhurst 2 edges
   after a Collision re-send, Whitehill 6, Henley-in-Arden 6 = the stray back-row grid in shot s8), 4 skipped by the
   draw. Every LANETEST `ok=false why=noLane` (Ferryhill Works, Sandhurst, Brentwood picked). Lane rules and the test's
   auto-pick changed.
4. Gaps: PLAN `gapHeld=` > 0 in 20 lines; no complaint about towns growing together.
5. Empty streets: `retired=` > 0 in 169 PLAN lines, `emptyLoopHeld=` > 0 in 5.
6. Motifs: 6 `event=fallback` (Ferryhill switchbacks -> ribbon_village ok, Ampthill ribbon_village -> hill_climb ok,
   Skegness hill_climb -> peninsula_tip ok; two without a fit), 3 `hamletFallback`, the wide spit pass found one
   (`spit=950/300/317,wide=328`).
7. Ships: `SHIPS lines=1 read=1 stops=3 vehicles=1 waterLevel=0.0 source=default` (the line read works, the water level
   read doesn't). No bridge built: Skegness `shipPath:highNoFit=3`, Darley Dale's 11 m deck `outcome=failed` (game log
   "ProposalData error: Place on Land"); the ship kept its route. Findings roads.md.
8. Industry: SIMGROW `mix=era` (716 lines); SATIND Ferryhill Works `landUse=17/17/395 indShare=0.92`, Ellesmere Port
   Works `17/14/398 0.93`, `onlyIndustry=true` both (findings towns.md); the main mod's Works added.
9. Station facing away: only `side=town` station quarters (22 lines); not tested.
10. Landscape names: `NAMES on=true why=ok list=europe lang=en langSource=lang apiLang=en apiRaw=mod:table:...,code:en
    pool=929 tagged=333 towns=16 renamed=16 fit=16 ... ok=30 failed=0 ... industries=14 indPrefixed=14 indEngine=0
    indSent=14 loadErr=- s=6.6` (findings towns.md). Reload / Game names / other lists not done. Stop names: 32 dev test
    stops all named, but from 3-7 names per theme (The Grove / Highfield Road / High Street x6, Green Lane / Esplanade
    x4); one renamed from its industry name "Whitehill Clay Pit". Replaced by ot_stopname.
The three sections verbatim:

### Forest / gaps / bridges round test (2026-10-13; ROUND_FOREST_BRIEF.md R1-R7; NEXT_PHASE_BRIEF 35; PLAN.md 6.3 "Forest / gaps / bridges round")

One run for this round together with "Landscape names test" and "Landscape stop names" below (both still open: they
landed after session `2026-10-13_1945_sqot-dev`). Every line is `[SQOT] ...` unless `[SQOT_DEV]`; most are debug lines
(Debug log On). The previous run's results: HISTORY.md (2026-10-13, "Final-test round test").

#### Setup

- Quit TF3 fully, `make link` (done). **New game**, map **European**, size **Large**, relief **hilly**, **forests: more**
  (or default), a **coast**, **lakes** and **rivers** (at least one river through a town stretch), many towns, start
  **1900**, game language English, throwaway save.
- Mods: `square_organic_towns` + `square_organic_towns_dev`. Main mod defaults (New towns only, Street style Automatic,
  Starting town size Game size, Town and stop names = Landscape names, Streets at industries Game default), **Debug log
  On**, Testing: grow towns faster Off.

#### Steps

1. Load; wait for `NAMES ...` and the head start until `HEAD done` (Landscape names test items 1-3 read these lines).
2. **Ship line:** build two harbours on the river on either side of a river town's stretch (or on a lake / the sea a
   river town touches) and a ship line between them with one ship running. Note the town's name.
3. **Station facing away:** one passenger station 300-800 m from a town with its building facing away from the town
   (tracks between the station and the houses).
4. **Stops:** Landscape stop names items 1-2 (6 bus stops in one town).
5. OT Dev, Town tab: pick a town next to a forest ("Pick town nearest the camera") -> **Forest lane test**; wait for the
   last `LANETEST` line (~1 min). Then pick a town by a river or lake -> **Industrial satellite probe**; wait for
   `SATIND ... event=result`.
6. OT Dev, Simulate: Seed 1, Only towns near the camera off, Every town grows on, Tour all towns when stopped on,
   screenshots on; **Quick: 40 years**. Leave it until `SIMGROW stop` and the tour's shots. Save.

#### Checklist (crashes first)

1. No crash, no freeze; `grep -c 'SQOT\] ERROR'` = 0; send any `WARN`. INIT `hangGuard=off` is known (the game's Lua has
   no `debug.sethook`: only the loop caps and slices protect). PLAN `us / slices` under ~50 ms; **CHECK `sliceUs=`** under
   ~15 ms (was up to 54 ms in one frame; `slices=2` = split over two ticks).
2. **Forest by plot depth (R1):** FOREST `share=` on the wooded towns (Redruth- / Southminster-like towns that read `none`
   at stride 5 should now read 0.1+), `renew=first|builds:n/edges:n|age` (re-reads after building). PLAN `forestLot=`
   (ha of forest under the increment's lots) and, for hug towns, `forestBudget=left/total` falling within a decade and
   resetting the next; no `forestCut=1.00` on small increments of hug towns unless `forestBudget` is above 0. Shots: hug
   towns' streets one lot depth off the trees, houses not reaching into the forest on the forest side.
3. **Forest lanes (R2):** `FORESTLANE town= edge= edges= len= why=hug|clear:p=..,u=.. template=country_old_small|
   country_new_small` then `FORESTLANE ... outcome=built`; PLAN `lanes=`. Not every town: about 1 in 3 crossings, at most
   4 per town. `outcome=refused` / `off=true` means the game refused the country lane: send the line. Fly to one: a dirt
   (old) / asphalt (new) country road through the trees, no houses along it, town streets with houses beyond it.
   Dev **LANETEST**: `increment=1 outcome=built lanes=n`, `increment=2 outcome=built`, then `lanes= laneLen= housesOnLane=
   housesOnTownEdges= edges2= beyond= ok=true|false` (want `housesOnLane=0`, `beyond` > 0: the town builds on past it);
   leaf markers show the lane for 30 s. `ok=false why=noLane` = the plan crossed no forest wooded on both sides (pick
   another town).
4. **Gaps (R3):** PLAN `gapHeld=` > 0 on towns growing toward a neighbour, `gaps=n:<half>-<gap>[t]` (`t` = twin). Shots:
   open land between neighbouring towns (150-300 m short of halfway); twins meet along one main road only.
5. **Empty streets (R4):** SNAPSHOT `noJoin=retired:n`, PLAN `retired=` and `emptyLoopHeld=`; shots: fewer bare stubs and
   no empty rectangular loops in organic towns (Kirkham / Fleetwood / Syston / Ormskirk-like).
6. **Motifs (R5):** `MOTIF event=fallback from= why= to= ok=`: a hill climb / switchbacks that couldn't be laid hands its
   slot on (`ok=true` and a MOTIF build line of the new kind with `edges=` > 0 later). SATELLITE `why=...:hamletFallback`
   for a crossroads hamlet. TERRAIN `spit=...w` on a town on a wide peninsula (`w` = the wide pass).
7. **Bridges and ships (R6):** `SHIPS lines= read= stops= vehicles= waterLevel= source=terrain|default` (lines >= 1 after
   step 2: the ship-line read works; `source=terrain` = the water level read works). BRIDGE `outcome=plan ... ship=none|
   navigable|path shipWhy=stop:<line>|cap:<m>|span:<m>|noShips deck= clearance=`: on the ship line's water `ship=path`
   with `clearance=` >= 11, or `outcome=none why=shipPath:highNoFit=n` (no bridge). Then: **does the ship still pass under
   the bridge?** (the ship line keeps running, no "no path" warning on the line). A low bridge (`clearance` < 11) over
   water with no ships: fine. Note which river stretches got bridges (narrow ones preferred).
8. **Industry (R7):** SIMGROW town lines `mix=era`; SATIND `event=create ... across=true|false` then `event=result
   initial=10/10/200 landUse=r/c/i indShare= buildings= onlyIndustry=`: **does the satellite build only industry?** Fly
   there and say what stands. Shots: towns like Alsager less mixed with industry everywhere.
9. **Station facing away:** MOTIF station_quarter `side=back`, `sides=` rising, `link=` > 0.
10. Landscape names test and Landscape stop names (sections below): their checklists as written.

#### Log lines to send

`grep -E '\[SQOT(_DEV)?\] (INIT|NAMES|NAME |STOPNAME|TESTSTOP|FOREST |FORESTLANE|LANETEST|SATIND|SHIPS|BRIDGE|SATELLITE|ERROR|WARN)' stdout.txt`,
plus `grep -E 'MOTIF .*event=(fallback|elig)|TERRAIN .*spit='`, a few PLAN lines of a hug town and of two neighbouring
towns (`forestLot` / `forestBudget` / `lanes` / `gapHeld` / `retired` / `emptyLoopHeld`), and the slowest CHECK lines
(`sliceUs=`). Or just "done" + the save name: the session is archived (`make logs`).

### Landscape names test (2026-10-13; NEXT_PHASE_BRIEF 34; PLAN.md 6.3 "Landscape names and stop names")

New: on a new map every town gets a real name from the game's own list that fits its site, before the head start.
Setup: a NEW map, European name list (game language English first; then one map in German or French if you can), hilly
with a coast, lakes and rivers; Organic Towns defaults ("Town and stop names" = Landscape names), Debug log On. Quit the
game fully first.

1. Right after load: `[SQOT] NAMES on=true why=ok list=europe lang=en langSource=lang|match apiLang= apiRaw= cls=en
   pool= tagged= tags=... towns= renamed= fit= plain= random= satellite= kept= ... indPrefixed= indEngine= indSent=`.
   Send the whole line. `apiLang` / `apiRaw` answer what `api.util.getLanguage()` returns; `langSource=match` means the
   language read failed but the town names found the folder. `why=listLoad` / `loadErr=` means `ug_require
   "::/names/..."` failed in the game script (then nothing was renamed).
2. One `[SQOT] NAME town= old= new= tags= match= score= nameTags=` line per town (debug): look at 5-10 towns on the map
   (coast, river, lake, hill, valley, forest towns) and say whether the new names fit (a river town -ford / -bridge /
   -on-X, a coast town -haven / -mouth / -on-Sea, a lake town -mere, a hill town -don / -hill, a valley town -dale /
   -combe, a wooded town -ley / -hurst / -wood). Names must be unique on the map.
3. The town labels on the map and in the town windows show the new names a few seconds after load; the head start
   (`HEAD start` / `HEAD` lines) begins only after the NAMES line.
4. Industries: find one named after a renamed town ("<new town> Crop Farm" etc.). `indEngine=` > 0 means the engine renamed
   industries with their town by itself (a finding), `indSent=` the ones the mod renamed. Any industry still carrying an
   old town name: send its name.
5. Save, quit, reload: `NAMES on=false why=done`, no rename. A second new map with "Game names": `why=setting`.
6. Another name mod (a square_names_us_* state mod): `NAMES on=false why=notBase`, names untouched. An existing save
   (game time past 10 minutes): `why=notNewMap`.
7. Optional: a US map (`list=usa`: Falls, Springs, Heights, Lake X, X Beach) and a Japanese one (`list=japan`).
8. "Little X" / "Klein X": `match=satellite parent=<id>` lines, if any: does the village sit right next to its parent?

### Landscape stop names (2026-10-13; NEXT_PHASE_BRIEF 34)

New Road Stops you build in a town get a street name that fits their spot. Same map as above (any map with a base name
list works, also an existing save).

1. Build a bus stop on a town street (the Road Stop tool) on a hill above the centre, one by the shore, one by a river,
   one next to a rail station, one in the centre, one at the edge of town. About a second later each gets a new name:
   `[SQOT] STOPNAME group= station= town= old= new= dev=false tags= theme= dz= ring= wet= forest= rail= dist=`. Send the
   lines and say whether the names fit (en: Hill Road / The Heights, Esplanade / The Quay, Bridge Street / Mill Lane,
   Station Road, High Street / Market Street, Green Lane). A stop with no theme keeps the game's name (debug line
   `why=noTheme`).
2. Rename a stop yourself right after building it (within a second): it keeps your name (`why=renamed`). A stop added to an
   existing stop group: `why=joined`, untouched. Upgrading a road with stops on it must not rename them.
3. Several stops on one hill: each gets a different name until the theme's names run out (then the game's name stays:
   `why=allUsed`). Two towns may both have a "High Street".
4. With a square_names_us_* mod: `STOPNAME on=false why=notBase` once, and that mod renames its stops as before (never both).
5. Passenger stations keep the game's names.

Dev test (square_organic_towns_dev, OT Dev window): Town tab -> "Pick town nearest the camera" -> "Place test stops
(named)" (or Main mod tab -> "Place test stops: all towns", 6 towns, at most 24 stops). It builds one curbside stop per
theme the town offers on its streets and has the main mod name it:

6. `[SQOT_DEV] TESTSTOP start=true towns= main=true`, `TESTSTOP planned=n`, then per stop `TESTSTOP town= edge= tag=
   tags= stop=<group> station= name= named=main` followed by the main mod's `[SQOT] STOPNAME group=<same> ... dev=true`.
   A failed build: `TESTSTOP ... ok=false msgs=` (send it; `why=noConfig|lights` are edges the tool skips on purpose).
7. Fly to a few test stops (no line serves them): does the stop sit on the street, and does its label show the
   STOPNAME `new=` name? Is the theme right for the spot (hill / shore / river / station / centre / outskirts)?
8. No crash or red sign at the stops' street ends after a minute of game time (the stop replaces the edge and re-sends
   its two end nodes' configs). Remove them with the bulldozer afterwards.

## 2026-10-13: TESTING.md "Hang fix check" and "Final-test round test" (run 2026-10-13, session `2026-10-13_1945_sqot-dev`)

Quick 40 years, 21 towns, tour shots; analysed read-only in the main session (summary: ROUND_FOREST_BRIEF.md), the fixes
in NEXT_PHASE_BRIEF 35. Hang fix check: `INIT ... hangGuard=off` (the game's Lua has no `debug.sethook`: the loop caps
and slice budgets are the only protection), no freeze, no `planHang`, 0 `[SQOT] ERROR`; PLAN at most ~28 ms per slice
(`us / slices`), CHECK up to 54 ms in one frame (Redruth, Okehampton; split since R1). Final-test round test: building
around forests liked ("let's keep pushing this"); forest read only at stride <= 4 (stride bias, R1); drawn motifs mostly
none (hill_climb 5 of 6 flat / short, switchbacks noBend, crossroads hamlet always waiting, ribbon noRoom: R5); empty
stubs / loops in Kirkham, Fleetwood, Syston, Ormskirk (R4); towns growing into each other (R3); Alsager's industry mixed
everywhere (R7). The two sections verbatim:

### Hang fix check (2026-10-13; NEXT_PHASE_BRIEF 33)

Session `2026-10-13_1848_sqot` froze in Henley-on-Thames' head-start round 2 (after `SNAPSHOT town=66049`, no PLAN). The
loop wasn't reproduced offline; the fix caps every planning loop, keeps bad coordinates from the terrain API and adds a
hang guard that ends a stuck plan with the loop's location. Run the same setup as "Final-test round test" below (a new
European hilly map with lakes, Streets at industries Game default); the head start is enough, then the 40-year simulate.

1. `INIT ... hangGuard=on`. `off` means the game's Lua has no `debug.sethook`: the guard can't stop a stuck plan (send
   the line; the loop caps still apply).
2. No freeze through `HEAD done`. Any `WARN stage=plan msg=planHang ... err=<file:line<fn|...>>` or
   `ERROR ... err=planHang:` names the loop: send the line plus the town's STYLE / MOTIF / SNAPSHOT lines before it.
3. If the game still freezes (watchdog `Possible hang detected` with no planHang line): while it hangs, run
   `sample $(pgrep -x "Transport Fever 3" || pgrep -f TransportFever3) 5 -file /tmp/tf3_hang.txt` in a terminal and send
   the file (shows whether it spins in the Lua VM or in the engine's terrain code).
4. Frame time: PLAN `us= slices=` should now be mostly under ~50 ms per slice (`us / slices`); Henley-like towns with a
   fishing village were ~70 ms per slice (round 1: `us=360284 slices=5`).
5. `START summary ... skipped=0 us=` (skipped > 0: the START rows ran out of their 250 ms budget; fine, send the line).

### Final-test round test (2026-10-13; after the final all-phases test)

The final all-phases test (session `2026-10-13_0856_sqot-dev`) ran clean (no crash, no mod error) and its results are in
HISTORY.md (2026-10-13, "Final test: all phases", with the checklist verbatim). This round fixed what it showed
(PLAN.md 6.3 "Final-test round", NEXT_PHASE_BRIEF 32): real country-road detection (wide read, exits at the outer
nodes) and virtual roads where a town has none (that map had none: makeInitialStreets false), drawn motifs
recalibrated to real terrain + a `MOTIF event=elig` line, the peninsula tip motif, forest densities, the station quarter
on a station facing away, coast-hugging shore towns, the hillside contour shape more often, the master plan sliced.
One run, the same setup as the final test; every line `[SQOT] ...` unless `[SQOT_DEV]`.

#### Setup

- Quit TF3 fully, `make link` (done). **New game**, map **European**, size **Large**, relief **hilly / mountainous**, a
  **coast**, **lakes**, **rivers**, **forests** (default or more), **many towns**, start **1900**, throwaway save.
- Mods: `square_organic_towns` + `square_organic_towns_dev`. Main mod settings as the final test (New towns only, Street
  style Automatic, Starting town size Game size, Town layout default, **Debug log On**, Testing: grow towns faster Off)
  but **Streets at industries: Game default** (the final test's Off apparently removed the roads between towns too:
  this run checks the real road detection and keeps the country roads).

#### Steps

1. Load; wait for `[SQOT_DEV] LOAD ok=true` and the head start until `HEAD done`.
2. Build one passenger station 300-800 m from a town **with its building facing away from the town** (tracks between
   the station and the houses), and one facing the town. Wait 2-3 minutes.
3. OT Dev, Simulate: Seed 1, Only towns near the camera off, Every town grows on, Tour all towns when stopped on,
   screenshots on; **Quick: 40 years**. Leave it until `SIMGROW stop` and the tour's shots. Save.

#### Checklist (crashes first)

1. No crash; `grep -c 'SQOT\] ERROR'` = 0; send any `WARN` (`stage=virtualRoads|roads|plan|motif` matter); no
   `lane_config_util` / `Engine.h:323`. Tree-lined streets now really go out (virtual roads): `SEND ... trees=n` with
   `ENTRY outcome=built`; an `ENTRY outcome=refused` once is tolerated, `off=true` = the game refuses them (send the lines).
2. Frame time: PLAN `us=` / `slices=` below ~50 ms per slice (was up to ~144: the master plan yields now); `TERRAIN us=`
   (now with the spit search) under ~30 ms.
3. **Roads:** per town `ROADS town= roads=n text=n:<out>@<deg>/.. nonTown= wide=edges/streets/noStreetComp/tracks:
   country=,town=,other=;country_old_small:n,..`: towns with a country road in the shots should have `roads=` >= 1 and
   STYLE `exits=` >= 1 (was 0 everywhere), `virtual=-`. `nonTown=0` with `wide=..country=n` > 0 means the snapshot misses
   the roads and only the wide read finds them (send a few lines either way). Towns without any road: `virtual=nbr/..`.
   Optional second map with Streets at industries Off: does it have roads between towns (shots, `wide=country=0`)?
4. **Motif eligibility:** `grep 'event=elig'`: one line per town with `terrain=grade=..,range=..,dr=..,water=..,cliff=..,
   spit=..,wide=..` and every drawn kind's `kind:score:why`. Send them all (the next calibration). Good: drawn picks
   (`MOTIF event=pick ... src=drawn`) on ~60-80 % of the towns, at most 2 each, neighbours mostly different; hill climbs
   / switchbacks / fishbones / ridge streets on hilly towns, harbour / fishing village / headland / peninsula tip on the
   coast, ribbon villages and village greens (`why=virtual:..`) elsewhere; crescents no longer take a slot.
5. Built motifs: MOTIF build `info=` rising: hill_climb `len=a/b` with a near b and `grade` <= ~0.08 (Wirksworth was
   0.135), ribbon_village `ribbon=..,off=0,..,virtual`, village_green `cover=` toward 0.8, peninsula_tip `spine=a/b,
   reach=,lanes=,atTip=` (houses at the tip), station_quarter `side=back` for the station facing away with `sides=`
   rising and `link=` > 0.
6. **Forest:** FOREST `share=` 0.1-0.4 on wooded towns (was 0.01-0.08), STYLE `forest=x:hug|clear`, a few `hug` towns with
   PLAN `forestHeld=` > 0 and low `forestCut=`. Shots: hug towns finger between forest patches.
7. **Shore towns:** STYLE `form=shore` on most sea / lake towns (water within 600 m); SHAPE `shore=a/b_cov=_depth=` and
   `ownShore=..depth=` well under ~350 m (was 665-896), FRAME lines for shore towns (`shape=shore`); shots: strips along
   the water, little inland.
8. **Hillside:** `shapeWhy=hillside: along the contour` on more towns than the one in the final test; SHAPE `hillRoad=`
   with len 300+ m.
9. `TERRAIN ... spit=tip/neck/width@deg` on towns by a peninsula; a `peninsula_tip` pick where `beyond=` is 120-1300 m.

#### What to send

"done" + the save name; impressions of the shots (coast strips visible? peninsula tips? the forests hugged? mountain
roads more common?).

## 2026-10-13: TESTING.md "Final test: all phases" (run 2026-10-13, session `2026-10-13_0856_sqot-dev`)

New European map (Large, hilly, coast / lakes / rivers / forests, 16 towns, 1900), main + dev mod, head start, two
passenger stations built by the user, Quick 40 years, tour (16 overview shots: `uv run tools/ot_shots.py` ->
`.cache/ot_shots/2026-10-13_09-04-47/`). The game generated a first map and returned to the main menu before the run's
map (two INIT / START blocks; the first map's towns, e.g. Grimsby, never grew). Results per checklist item:

- **A1 crashes / errors:** no crash, 0 `[SQOT] ERROR`, 0 `WARN`. The one Lua traceback (08:57:30, `Ignoring Set() on
  expired ReactRefWrap`, `::/gui/main/selector_react_util.tl(103)`) is the base game's GUI on the way back to the main
  menu (no mod frame in it); a Better Minimap `Invalid entity` traceback (09:03) is that mod's, caught.
- **A2:** no `lane_config_util` / `Engine.h:323` / BaseNodeConfig lines; 47 REFUSED, 5 FAILED (3 `Collision`, 2 empty
  msgs) over 304 BUILT.
- **A3 frame time:** PLAN up to 432 ms in 3 slices (~144 ms per slice, Tetbury), several over 100 ms per slice: the master
  plan with its motifs was built in one tick (fixed: it yields between its parts now). FOREST reads 11-32 ms per town in
  5-12 slices (~3 ms each).
- **B4:** `INDSTREETS choice=off makeInitialStreets=true->false applied=true`; no house clusters at industries in the shots.
- **B5:** INIT `upward=from1500 meadows=on trees=on params=...test_grow=1`; `MAP bounds=-8192:-8192:8192:8192`;
  `TOWNSIZE populationDensity=1->1 applied=false`.
- **B6:** `CHARACTER count=2 picks=Wirksworth:1.28:nnd3525:edge1324,Southborough:1.30:nnd3858:edge1644` (both edge >= 1300).
- **B7 FAILED:** `ROADS roads=0 segs=0 fetched=0` for all 16 towns, `exits=0` on every STYLE line: the map had no
  country roads (shots). The earlier EU maps (makeInitialStreets at its default true) do have dirt country roads in their
  shots, yet logged `exits=0` too: the exit test missed roads joining at the town's outer street node beyond the houses'
  extent. This map was started with Streets at industries Off (makeInitialStreets false), which apparently drops the
  roads between towns as well (findings towns.md "`makeInitialStreets = false` also drops the roads between towns"). So
  no ribbon village, village green, crossroads hamlet or tree-lined entry could trigger (`ENTRY ... roads=-`, 8 on /
  8 off, none built).
- **C8:** CHECK why: demand 404, ahead 96, open 17.
- **C9:** BUILT ok=true 304 in all 16 growing towns; mod share of new street edges 39 % overall (2070 of 5375; per town
  15-60 %: Southborough 15, Wirksworth 20, Sevenoaks 22 % lowest; Hitchin 60, Brandon 59, Stone 58 % highest).
- **C10:** ownEmpty within its cap (41 of 386 plans at room 0, max 4248 m); FILL restore after every upward dose exact
  (A->B->A); the dose fills' restores ended above A (e.g. 275,236,199 -> 1549,.. -> 316,271,229: the town grew between);
  FILL reactivate 44 (Madeley 10, Nelson 7).
- **D11:** 7 satellites seeded and built (Madeley, South Molton, Burton, Stone, Woodstock, Nelson, Tetbury) + 4 grow
  builds; none `dropped=disconnected` (more than the expected 1-3).
- **D12:** FRAME 25 plan -> 24 built, 1 pruned (Stratford, kept 10), 5 none; no plan refused twice. No frames in the three
  shore towns (the wedge rule didn't cover the shore shape: fixed).
- **D13:** forms clustered 4, linear 4, radiating 3, shore 3, fingers 1, sprawling 1 (clustered + wide 4 of 16: ok); SHAPE
  spread > 1.2 on only 5 of 16 at the end (1.03-1.56). Coast towns did not read as strips: the three shore towns' streets
  reached 665-896 m inland (SHAPE `shore=` / `ownShore=` depth), near-water share 0.32-0.51 (the user: "it wasn't
  obvious to me if any of these towns were doing the spread across coastline").
- **D14:** one hillside town: Stratford-upon-Avon `shapeWhy=hillside: along the contour`, `hillRoad=761/+1/111` at the end
  (the user's favourite "mountain roads": the linear arms along the contour of the mountain's foothills).
- **E15 FAILED:** every STYLE line has `motifs=`; drawn picks only 2 (Wirksworth hill_climb 0.46 `slope:grade=0.048,
  range=103`, saved later); derived crescent 13 towns (took one of the 2 slots), hill_road 1, station 2, bridgehead 2.
  Cause: the eligibility was calibrated on the steep synthetic fixtures (grade 0.06-0.09); the real towns read grade
  0.01-0.05, water 250-575 m out, the strict valley / ridge flags never held; the pick chance was 0.6 x the best score.
- **E16:** hill_climb (Wirksworth) only `len=124/833`, `grade=0.135` (the 120 m smoothing cut across the contours: the
  planner refused the steep pieces; fixed); crescents 194 build lines; hill_road `761/+1/123`; bridgehead quarters
  `sides=4/25` (Sevenoaks), `3/21` (Nelson).
- **E17:** STATIONS `stations=2 dirs=2 ok=true`; Tetbury `station=566@79,side=town,grid=4x4,sides=13/26,link=31/477`;
  South Molton `station=724@66,side=away,grid=3x3,sides=0/23 -> 1/23,link=0/0(away)`: nothing toward the town (fixed:
  the quarter goes on the station's back).
- **E18:** 2 bridges built (Nelson span 132 m, Sevenoaks 144 m, stone bridge), then their bridgehead quarters; the other
  towns `BRIDGE outcome=none why=noRiver|noCrossing|noSite|rare`.
- **E19:** 0 `waitGiveUp`.
- **F20:** FOREST per town: groups 1154-1913, trees 12-21k, stride 2-3, `capped=true` (= sampled), p50 24-28, p90 60
  trees/ha, us 11-32 ms, `err=-`.
- **F21 WEAK:** forest share 0.01-0.08 for every town (one `hug`, Thaxted 0.08) on a heavily wooded map: DENSE_HA 90 /
  LIGHT_HA 25 were far above the read's densities (recalibrated).
- **G22:** UPWARD in South Molton (big, after=empty), Burton (big, built), Thaxted and Nelson (pressure, built); `UPWARD
  effect perBuilding=2.74->2.73, 2.64->2.65, 2.87->2.86`, `initial` and `target` unchanged (no runaway); one effect
  sample each: whether upgradeBuildings raises the core is still open.
- **G23:** Thaxted only (sprawling lens): `MEADOW lobes=33/158/267 meadows=3:56/56/49@220`, meadow frames 3 built.
- **G24:** ENTRY 8 on / 8 off, nothing built (no roads, B7).
- **G25:** no polycentric metropolis (METRO on=false why=small|site; expected on a 1900 run).
- **H26:** 16 ALLTOWN lines + SHOT (shot 1 the primer). User: loved Stratford-upon-Avon's mountain roads, Southborough's
  small group of houses at the tip of a coastal peninsula ("like expensive real estate"; the town's linear river-bank arm
  ran out along the spit until the water stopped it), Sevenoaks' varied layout with the bridge and the quarter across the
  river; "in general the offshoots are interesting, and the more we can push cities that build with the environment,
  the better results."

The fixes are the final-test round (PLAN.md 6.3 "Final-test round", NEXT_PHASE_BRIEF 32). The checklist as it was:

### Final test: all phases (2026-10-13; one run after the later-ideas phase)

One run that exercises everything built since the last in-game test (session `2026-10-13_0342_sqot`): real map round 5
(industry streets off, satellites, frames, character towns, spread, coast), motifs M0-M4, phase F (forest) and the
later-ideas phase (upward density, meadows, tree-lined entries, polycentric). The older sections below stay as the
reference for each feature (item numbers in brackets). Every line is `[SQOT] ...` unless it says `[SQOT_DEV]`. The game
log is archived by itself (`.cache/logs/`, `make logs`): you don't need to copy anything unless asked.

#### Setup

- Quit TF3 fully, then `make link` (done by this phase; the staging links must point at `mods/square_organic_towns` and
  `mods/square_organic_towns_dev`).
- **New game**, map **European**, size **Large**, relief **hilly / mountainous**, with a **coast**, **lakes**, **rivers**
  (water settings high enough for all three) and **forests** (default or more), **many towns**, industries on (default),
  **start year 1900**. Throwaway save.
- Mods: **`square_organic_towns` + `square_organic_towns_dev`** (no other town / street mods).
- Main mod settings: Act on **New towns only**, Street style **Automatic**, Vanilla town street angles **Automatic**,
  **Starting town size: Game size**, **Streets at industries: Off** (default), **Town layout: default** (Organic),
  Growth lookahead default, **Debug log: On**, **Testing: grow towns faster: Off**.

#### Steps

1. Load the map; build nothing yet. Wait for `[SQOT_DEV] LOAD ok=true`, then the head start: `START summary`, `HEAD start
   towns= rounds=`, `HEAD town= ... outcome=built` every few seconds, until **`HEAD done`** (~2-4 minutes).
2. **Station quarter:** pick 1-2 towns with open land beside them and build one **passenger train station** each,
   200-800 m from the town's houses (a short track to a second station is enough; no line needed). Leave the game
   running ~2-3 real minutes afterwards (the station list is read every 120 s).
3. OT Dev window, **Simulate** tab: Seed 1, **Only towns near the camera: off**, **Every town grows: on**, Big towns
   better connected: on, Tour all towns when stopped: on; **Camera & tour** tab: Screenshots during the tour on, s per
   view 3. Back in Simulate: press **Quick: 40 years**. Check `[SQOT_DEV] SIMGROW start ... towns= fastFill=true
   buildRound=true`.
4. Leave it ~5-8 real minutes until `SIMGROW stop`; the tour then flies to the biggest towns and shoots each (`ALLTOWN`,
   `SHOT`). Save at the end (note the save name).
5. Optional second run (era effects: cul-de-sac pods, polycentric, new templates, grid trend): the same setup with
   **start year 1950** (a new map; Every town grows on). Polycentric needs a metropolis of 9000+ persons: only the
   biggest flat towns get there, if at all.

#### Checklist (crashes and errors first; each line: what to grep, what good looks like)

**A. Crashes and errors**
1. No crash. `grep -c 'SQOT\] ERROR' stdout.txt` = 0; `WARN` lines: send any (`stage=plan|motif|metro` ones matter).
2. No lane / config assertions: no `lane_config_util` or `Engine.h:323` / `BaseNodeConfig` in the log; `[SQOT] REFUSED`
   lines are fine in small numbers, `FAILED` rare.
3. Frame time smooth while big towns plan: PLAN `us=` / `slices=` (no slice > 50 ms), `FOREST us=` (the tree read).

**B. Start of the game** (round 5, F, M2)
4. `INDSTREETS choice=off makeInitialStreets=true->false applied=true`; in the shots no house clusters glued to
   industries away from towns [28].
5. `INIT ... upward=from1500 meadows=on trees=on params=...test_grow=1`; `MAP bounds=` four numbers; `TOWNSIZE`
   `populationDensity=1->1`.
6. `CHARACTER count= picks=name:score:nnd:edge`: 2-3 towns, every pick's edge >= 1300 m [19, 33].
7. `ROADS town= roads=n:<out>@<deg>/...` for most towns (towns with country roads have n >= 1) [43].

**C. Growth and the mod's share** (rounds 2-4)
8. `grep -o 'CHECK.* why=[a-z]*' | grep -o 'why=[a-z]*' | sort | uniq -c`: `demand` and `ahead` dominate, `open` in
   static towns [0].
9. `BUILT ok=true` in every growing town; mod share of new street edges >= 40 % overall (BUILT `edges=` per town vs
   CHECK `edges=` first -> last) [0].
10. PLAN `ownEmpty=m/cap` stays under its cap, no long empty loops in the shots [25]. `FILL restore` after every dose,
    no town with `FILL reactivate` repeating every fill [23].

**D. Round 5: the landscape**
11. Satellites: `SATELLITE ... kind=seed`, then `SATELLITE built`: **1-3 built** on the map, no `dropped=disconnected`;
    a refusal line has `partners=ent<id>:<kind>` (send those) [29].
12. Frames: every `FRAME outcome=plan` followed by `outcome=built` or `outcome=pruned kept= dropped=` (never the same plan
    refused twice) [30].
13. STYLE `form=`: clustered + wide at most ~4 of 16 towns; several `linear` / `fingers` / `sprawling` / `shore`; SHAPE
    `spread=` ratio above ~1.2 on most towns; coast towns as strips along the water [31, 11].
14. Hill road: hillside towns `shapeWhy=hillside: along the contour`, SHAPE `hillRoad=len/climb/houses` with len 300+ m
    [32].

**E. Motifs (M0-M4)** — `grep 'SQOT\] MOTIF' stdout.txt`
15. Every STYLE line has `motifs=`; `MOTIF ... event=pick kind= src=drawn why=` on about half the towns, at most 2 per
    town, neighbours mostly different kinds [34, 38].
16. Built motifs: MOTIF build lines `kind=<id> ... info=` with `<built>/<planned>` rising over the run. Per kind:
    hill_climb `len=` 300+ m and `grade` <= ~6 % [39]; valley_fishbone ribs both sides [40]; harbour_crescent `cover=`
    toward 0.7 [41]; fishing_village 3-4 streets [42]; ribbon_village `ribbon=` built along the road [45];
    village_green `cover=` toward 0.8, nothing inside [46]; crossroads_hamlet: `SATELLITE ... why=hamlet` [47];
    ring_road `R=` and arcs [49]; workers_terraces (1900 start, light factories) rows [51]; switchbacks `bends=` [54];
    ridge_street `crest=` near 1 [55]; headland_street `seaward=0` [56].
17. **Station quarter** (step 2): `STATIONS stations=n` > 0 after you built the stations, then `MOTIF ... kind=station_quarter`
    with `info=station=d@deg,side=town|away|guess,grid=nxn,sides=<built>/<planned>,link=`; sides rising; in the shot a small
    straight grid toward the station [50].
18. Bridgehead: only after `BRIDGE outcome=built` (a river town with a crossing): `kind=bridgehead_quarter` [57].
    `BRIDGE outcome=none why=` once per river town otherwise [26].
19. `MOTIF event=waitGiveUp` rare (a few per run) [58].

**F. Forest (phase F)**
20. One `FOREST town= groups= reads= trees= share= p50= p90= us=` per town (debug); `err=` empty; `trees` > 0 on wooded
    towns; `us` (read time) a few ms per slice [59].
21. STYLE `forest=<share>:hug|clear|none`; early small organic towns in forest mostly `hug`; PLAN `forestCut=` low in hug
    towns (< ~0.3), `forestHeld=` > 0 [61]. In the shots: hug towns finger along clearings, clear towns cut through [62].

**G. Later ideas (this phase)**
22. **Upward density:** `grep 'SQOT\] UPWARD' stdout.txt`. Towns past ~1500 buildings (or 700+ with held plans,
    `why=pressure`): `UPWARD why=big|pressure after=built|empty points=3 main= near= cut=0.25-0.50`, every few minutes per
    town; each followed by `FILL restore ... initials=A->B->A` (**back exactly to A**) and, at the town's next check,
    `UPWARD effect ... perBuilding=a->b initial=X->X target=T->T`. Good: `initial` and `target` unchanged (no runaway),
    `perBuilding` rising over the run in upward towns (the core getting taller: **the open question**; flat or falling
    = upgradeBuildings does nothing, send the lines). PLAN `upCut=big:0.xx:<asked>` with `edges=` below the ask. Shots:
    taller buildings in the big towns' centres.
23. **Meadows:** `grep 'SQOT\] MEADOW\|FRAME.*kind=meadow' stdout.txt`. Each sprawling town (and character towns
    without arms) logs `MEADOW form=sprawling lobes=<deg>/... meadows=n:<widths>@<coreR>` once; PLAN `meadowHeld=n@R`
    > 0 in those towns; `FRAME kind=meadow outcome=plan` -> `built`. Shots: green wedges between the clusters that stay
    green at the end (compare a sprawling town with a clustered one).
24. **Tree-lined entries:** `grep 'SQOT\] ENTRY' stdout.txt`. One `ENTRY town= on=true|false p=` per town (about half
    `on=true`); `ENTRY outcome=built edges=n fallback=0` in towns with country roads; SEND `spec=... trees=n`. Good: no
    `ENTRY outcome=refused` (one is tolerated: the build goes out again without trees; `off=true` after 2 = the game
    refuses tree-lined script streets: send the lines). `fallback=` > 0 = the decoration ids weren't found (plain streets
    were built). Shots: rows of trees along the town's new streets beside a country road where it leaves town.
25. **Polycentric** (only if a town becomes `METRO ... variant=polycentric`, most likely in the 1950 run): METRO
    `at=x:y@D:junction|ring:grid|plan` (junction = a centre at a country-road crossroads), `METRO event=centreAdded`
    when it grows past 18000 / 30000 persons, METRO step `cores=c1:grid@junction:<built>/<planned>`: the grid core's sides
    built only once the houses reach it. None on the map: say so (expected on a 1900 run).

**H. Tour and look**
26. `ALLTOWN ... spread= motifs= forest= later=ups=n,pb=x.xx,meadow=on|-,frames=n,trees=n` for the biggest towns, and a
    `SHOT` per town (shot 1 a primer). Look across the shots: few round blobs, strips along coasts, lobes with meadows,
    hill streets climbing, motif patterns recognisable.

#### If it crashes

- Note the time and what was on screen (head start, Quick, a station build, the tour). Restart the game once (the
  session log is archived at the next start; crash logs too) and tell me "crashed"; I read `make logs-list ARGS=--crash`
  and the last `[SQOT] SEND` line before the crash (the proposal that was in flight: `spec=... trees=` tells whether it had
  tree-lined edges).
- If the game won't start or the archive misses it: send `stdout.txt` (or its last 300 lines) and any crash dump from the
  game folder.
- To retry without the new features, nothing is needed from you: tell me which one and I switch it off (`UP.ON`,
  `MD.ON`, `EN.ON`, `PO.ON` in their modules).

#### What to send

Nothing beyond "done" (and the save name) if the session archived; otherwise `stdout.txt`. Plus your impressions of the
shots: which towns look good / wrong, and whether the big towns' centres look taller.

## 2026-10-13: Later-ideas phase (upward density, meadows, tree-lined entries, polycentric; offline only)

- Four of MOTIFS_BRIEF's "Other ideas" approved by the user; "reshape starting towns" left for after the Starting town
  size test. Details: PLAN.md 6.3 "Later ideas", NEXT_PHASE_BRIEF 31.
- Upward density: the lever is the known DevelopAt (findings towns.md) with `upgradeBuildings`, restored exactly
  (`UP.EXTRA` 0) so it can't run away like v5's fill twin; the town-wide `makeTownCustomDistributionWeightsCmd` (found in
  the town editor) was rejected: whole town, saved after removal. The first driver test found that the fake town's
  trigger is `low`, not `demand`: the dose now follows any trigger but the head start (the cut stays demand-only).
- Meadows: the first bigform run picked town ids whose seeded sprawling style had an armed shape (wedges apply there,
  `MD.applies` false): the test now picks unarmed sprawling towns (and a sprawling character town) by scanning ids.
  10x results: meadow share 0.30 -> 0.17, 0.44 -> 0.35, 0.30 -> 0.13, character 0.13 -> 0.07, all housed.
- Country roads: restyling / curving them is not safe (the mod never rebuilds a road node); the town side uses the base
  `town_*_trees` templates found in the game files (findings towns.md "Tree-lined town street templates").
- Polycentric: junction centres, a third centre at 30000 persons, seeded grid cores (ot_poly). The first plan test's
  junction lay off the town's (seeded) axis and was skipped by the 75 deg rule: the test now places it on the axis.
- Doc fixes: PLAN.md 7 "Commands ≤ 24 edges each" (the code sends up to 36 per demand / metropolis increment, 48 per
  frame, 60 per satellite seed); PLAN.md 8 "use only simBuildable town templates" (the tree-lined entries are the one
  exception, by design).

## 2026-10-13: Phase F, forest-aware towns (offline only)

- Research first (MOTIFS_BRIEF "Forest"): trees found in the files as `ASSET_GROUP` entities with model instance lists
  (`metadata.tree` on the model), searchable by the octree; no ground-material sampler; the map generator's forest noise
  not reproducible; nothing in the game keeps forest. Built as a town mode rather than a motif.
- Tuning runs (test_forest, the 160 m clearing cross): the first hold (industry-style, relaxed to "no hold") let a Nordic
  town fill whole 18-edge increments in forest once its reachable clearing pieces were used (cut 0.69 vs 0.71 clear);
  long loop pieces with a short wooded stretch passed the mean-cover test. Fixes: pen = max(mean cover, wooded length /
  120 m); the relaxed hold stops at just over 1 instead of switching off, and wooded pieces fill at most half an
  increment (`FO.CUT_FILL`): Nordic 0.63 vs 0.71 on 160 m clearings (its cluster cells are wider than the clearings),
  0.21 vs 0.40 on 440 m ones; NA grid growth 0.51 -> 0.56 of the clear town's. Nordic's hug odds 0.9 -> 0.75.
- The reader's first budget gave every group at least 600 reads (1.2M reads with 2000 groups); now the budget is spread
  evenly (at least 4 per group) with a hard stop at 2 x READ_MAX.

## 2026-10-13: Motifs M4 (more terrain motifs, M3 fixes, era range 1900+; offline only)

- Fixes from M3: the station quarter took a motif slot at a fresh town's pick (ring picks 3 -> 0 of 120 with a station):
  derived kinds from events in the town's life (station quarter, the new bridgehead quarter) are `extra` and take no slot
  (`MO.slotsTaken`); the site / style looks (crescent, hill_road) still do. A close / terrace row / spur whose main line's
  next piece is refused waited forever: counted per plan (only plans where that piece is excluded / refused / blocked,
  never a lead-limit hold), dropped after `SEL.WAIT_GIVEUP` 6 (`style._motifGaveUp`, MOTIF `event=waitGiveUp`).
- Era range 1900+ (user: TF3's earliest start is 1900): ot_grid trend 1870/1960/1990 -> 1910/1970/2000; industry
  away-preference ramp 1890-1920 -> 1910-1945; ensanche gate 1860 -> 1920 (style pick too), extension gate 1850 -> 1900;
  the EU organic town's extension ring from 1915 (was era band 2: always); ring road era 0.45 before 1850 -> 1 from 1900
  became 1 to 1940 -> 0.45 at 1975; workers' terraces 1900/1930 -> 1935/1950. Tests moved to 1900+ years (grid shares
  1900 0.18 / 1920 0.24 / 1940 0.29 / 1960 0.44 / 1990 0.51 grid-ish).
- `ot_motif_relief.lua`: switchbacks, ridge_street, headland_street (drawn) and bridgehead_quarter (derived, extra),
  `MO.IDS` 14-17. Switchbacks first traced legs at 6 % on a ~9 % plane: legs 45 deg off the contour, a wave rather
  than a zigzag (5 % and longer legs now); on a slope with shelves no bend fitted at the leg's end and moving the end
  back 120 m never reached a shelf: the leg is traced 1.5 x long and the bend goes at the end nearest the leg's length
  whose ground fits. Ridge crest test at 60 m / 3 m ended the trace at once on a 0.04 %/m^2 crest (80 m / 2 m now).
  The cliff's brink found a beach (the sea bed 20 m out is 5 m below the last land): the water's surface counts and the
  brink must stand 8 m+ above it. Station grid laying refactored into `TW.layGrid` (station numbers unchanged: 37/40).

## 2026-10-13: Motifs M3 (town structure / era motifs; offline only)

- `ot_motif_town.lua`: ring_road, station_quarter (derived), workers_terraces, culdesac_pods (`MO.IDS` 10-13); engine
  `railStations` + driver `stationsFor` / `stationRefresh` (stations re-read every 120 s, the plan rebuilt when they
  change); frame field `rr` (the ring's radius). First run: the new drawn kinds took slots in the other tests' towns (5
  failures: arms, form, industry, metro, M1 picks): eligibility gated on `TW.ON`, off in the fixtures. The pods' collector
  on NA grid stalled where the grid's T parts near the town took its junctions (the green zone now starts half a block
  beyond the houses and drops T's too); later collectors stalled at their second close, built alone at the line's tip
  (`motifWait` / `branchOk`; tried for every branch first: the M1 fishbone fell from 18 to 14 ribs, so M3 pieces only); the
  collector moved as the plan extent grew (smoothing over a longer trace: now an unsmoothed arc, no extent cut); closes
  vanished from later plans because the built close, snapped a few metres, "crossed" the planned one (own edges along the
  line ignored now), and one close crossed the collector's link arc and was joined by it (`crossesMotif`). Terrace rows
  first 34 m apart (too tight for back-to-back lots): 40-52 m.

## 2026-10-13: Motifs M2 (road / village motifs; offline only)

- `ot_roads.lua` (country roads traced from the snapshot, beyond it through the engine's node / edge reads; junctions,
  forks, segments) and `ot_motif_road.lua`: ribbon_village, village_green, crossroads_hamlet (drawn, `MO.IDS` 7-9, groups
  road / hamlet). Offline the first ribbon built one piece and stopped: its line stopped at the town's own new streets, so
  every replan moved it (or flipped it to the road's other side); now only country roads stop it. The first green wandered
  around the town (its free-place test saw the town's growth, and "our streets along the ring" matched random town
  streets), its stub-to-apex piece came out too short or kinked: the green now keeps its place for the session, finds an
  earlier session's green by its locked streets, anchors on the stub's town 70 %, and both sides leave the stub's end
  together (ot_select withBranches: a main line ending at a new junction takes its branches; first try broke M1's
  fishbone, whose anchor sat on a rib junction at a town node: limited to new junctions). The rules check found plan
  streets crossing a country road beyond the snapshot (all towns): ot_select now blocks pieces across / onto traced roads.
- Satellites: crossroads and farms / light works score better, only heavy / medium works keep them away; the crossroads
  hamlet motif seeds its satellite at a junction from 120 buildings. Country-road nodes are not joined (research in
  PLAN.md 6.3 "Motifs M2").
- Offline: ribbon 365 / 503 m beside the road, lanes 2 / 2; green lens cover 0.91, triangle 1.00, nothing inside; hamlet
  8 / 8 beside the junction; farm sites 12 / 12. Main 361 / dev 113 tests green. Details PLAN.md 6.3 "Motifs M2".

## 2026-10-13: Motifs M1 (terrain / water motifs; offline only)

- `ot_motif_land.lua`: hill_climb, valley_fishbone, harbour_crescent, fishing_village (drawn, `MO.IDS` 3-6, groups land /
  shore). The first offline runs built almost nothing of the motifs: lines traced from the centre passed too near the
  core's streets (planner `nearExisting`), the next piece was then disconnected, every increment again; crossings with
  dropped plan pieces left 30-60 m pieces; the plan's own streets ran alongside the line and blocked it; a contour-drawn
  shape's distance priced the climb out. Fixes in order: pending crossings, a band beside the line, plain distance and
  `costK` for motif pieces, dense junctions, anchors to the town's dead ends (circular link arcs, clear of streets, not
  steep) with plan rebuilds, tee / approach discounts. Under join "deadEnd" (as in game) ribs / lanes never came once the
  main line passed their junction: branches are now chosen with the main-line piece and the line runs one piece past.
- Offline (12 increments, join deadEnd): climb 555 m (+40 m, 6.8 %, 2 terraces), fishbone 18 / 20 ribs, harbour cover
  0.96, village 3 / 3 streets. Main 352 / dev 113 tests green. Details PLAN.md 6.3 "Motifs M1".

## 2026-10-13: Motifs M0 (framework; offline only)

- Two dev tests failed after real map round 5 (108/110): the runner's own-dead-ends test counted on one build, but the
  NA_SUBURB form weights now draw the fake town radiating / cross (test rewritten to its intent); the showcase's
  K-refusals test never reached a refusal because EU organic drew wide with green reserves over both dead ends (main-mod
  fix: green relax on an empty increment, PLAN `greenRelax=`).
- `ot_motif` registry, seeded 0-2 motifs per town saved on the frame (`mo`), neighbour diversity, crescents and the
  hillside hill road migrated as derived kinds, STYLE / MOTIF / ALLTOWN logs, dev Town-tab motif picker. Main 342 /
  dev 113 tests green. Details PLAN.md 6.3 "Motifs: the framework".

## 2026-10-13: TESTING.md "Real map test", fifth run (session `2026-10-13_0342_sqot`) and real map round 5

Setup: new generated European (UK names) map, 16 towns, main mod Act on New towns, debug on, Testing grow **Off**, the
dev sim Quick (264 s, 208 build-round builds): 1992 -> 15517 buildings. Shots `.cache/ot_shots/2026-10-13_03-50-26/`.

- Mod share of new street edges 34 % overall (12-69 % per town; Bodmin 12 %, Aylsham 16 %, Barnes 21 %, Bicester 22 %).
  Builds per town 5-27 (Bodmin 10 builds / 53 edges, Rawtenstall 27 / 176).
- Forms (ALLTOWN): clustered 5, linear 3, wide 3, radiating 2, sprawling 1, shore 1; shapes compact 6, linear 3, lens 3,
  cross 2, shore 1 (one more compact via sprawling). Character towns Barrow-in-Furness (sprawling, 853 buildings, r 497 m)
  and Bodmin (linear, 1693 buildings): both 920 m from the map edge, both read as blobs.
- FRAME: 15 plans, 12 built (Bodmin 3, Middlewich 3, Crowle 3, Romford 2, Aylsham 1), Aylsham refused twice with the
  same plan (re-send after the prune), Romford once `fewLinks`. PLAN `wedgeHeld=-` on the 11 unarmed towns, 0-6 on the
  armed ones.
- SATELLITE: seeded Middlewich, Barrow-in-Furness, Hingham (`refused=precheck`, Collision with 2-18 entities outside the
  snapshot), Romford and Hessle built; Bodmin `seed=none why=noSite`; 9 `on=false why=rare`.
- User: Middlewich (hillside, contour-axis linear, ~1261 buildings) with its long street up into the hills "very cool";
  more spread across the landscape, not radiating from the centre; hug coastlines more; small house clusters next to
  industries 1-2 km out (Barnes, Ilkeston, earlier Barnard Castle): the generator's industry-edge streets.
- Done (PLAN.md 6.3 "Real map round 5"): "Streets at industries" (default Off), satellites 55 % / map quota / obstacle-aware
  sites / retries, frame prune fix, towns across the landscape (forms, shapes, shore share, hillside gain, lobes along the
  roads), character towns away from the map edge, dose fill for sprawling lobes, `spread=` / `hillRoad=` metrics.

## 2026-10-13: TESTING.md "Real map test", fourth run (session `2026-10-13_0232_sqot-dev`) and real map round 4

Setup: new generated European (UK names) map, 16 towns, main mod Act on New towns, debug on, **Testing grow On**
(`test_grow=2`, 11 GROW lines) plus the dev sim (Quick 40 years, every town grows: 2468 -> 22228 buildings, 357 s, 10 build
rounds, 320 round builds, 0 SIMGROW stall). Shots `.cache/ot_shots/2026-10-13_02-40-43/`.

- Main mod: 355 BUILT ok (33 head start, 322 demand), 5 FAILED; CHECK why demand 379 / ahead 123 / open 19 / over 3; mod
  share of new street edges 41 % overall (25-62 % per town, fast towns 28-39 %); 45 `FILL reactivate`.
- Styles: 9 EU organic, 3 EU extension, 2 MED ensanche, 1 MED hill, 1 Nordic; forms clustered 7, sprawling 3, fingers 2,
  radiating 2, linear 1, wide 1; character towns Holsworthy (fingers) and Grays (ensanche sprawling). Map edge respected.
- Look: at 1000-3500 buildings Harwich (linear), Holsworthy (fingers), Bingley and Bootle (radiating, shape cross) read as
  one organic blob; Grays' south long empty rectangular loops, Harwich's west empty strips. PLAN `emptyLen` at the end
  4-17 km per town (Grays 6.7 km of mod streets, 87 edges, laid 2-15 edges at a time while `ownOpen` < `lead` ~ 0.5 x
  the built lots).
- Satellites: Holsworthy, Jarrow, Bingley, Whitnash built (13 edges each); Harwich `dropped=disconnected:13/nearExisting:2`
  and Workington `crossesExisting:1/disconnected:12` (the link crossed / ran along a street). Bridges: 0 lines, no town
  read `river` (Bootle's river ~1 km out flows into its lake).
- Grid trend: every STYLE line `gridBias=e=0.33` (the game calendar stayed ~1900 in the 40 simulated years); the framed
  re-resolutions read `gridLook=-` (the look dropped after the head start saved the frame: a bug).
- Done (PLAN.md 6.3 "Real map round 4"): green wedges + wedge frames (ot_wedge), own empty budget / OWN_CAP 0.35 / lead
  400 m, bridges toward narrow water (ot_bridge narrowWater, CHANCE 0.75, BRIDGE none lines), satellite links clear of
  streets, grid look saved with the frame.

## 2026-10-13: TESTING.md "Real map test", third run (session `2026-10-13_0137_sqot-dev`) and real map round 3

Setup: new generated European (UK names) map, 16 towns, main mod Act on New towns, debug on, Testing grow Off
(`test_grow=1`); dev Simulate natural growth (Quick 40 years). Shots `.cache/ot_shots/2026-10-13_01-47-31/`.

- Head start: `HEAD start towns=16 rounds=2 edges=12`, 28 of 32 jobs built (256 edges; 4 `buildFailed`). Axbridge's round 2
  (EU extension, lens, `BUILT trigger=head mix=0/39/61`, PLAN `emptyLen=1899/27`) laid an ~800 m straight empty medium
  street from the town to the map edge with a T at its end: the head start ignored the housed-front / arm-fill rules
  (EU styles have no housed front, a lens no arm fill) and nothing kept plans from the map boundary.
- Main mod: 59 BUILT ok, 4 FAILED; CHECK why demand 56 / open 17 / ahead 2; 1 satellite; 6 `FILL reactivate`, 3 `SIMGROW
  stall` (Thornaby-on-Tees, Market Drayton, Cheadle stayed with development off after later fills: the reactivate only
  fired when the fill found the town on). Final factors up to 10.7 (Market Drayton 238 -> 2063 buildings).
- Styles: 11 EU organic, 3 EU extension, 1 Nordic, 1 MED ensanche (Amble), 1 MED hill. Forms: wide / lens 7 (every coast
  town drew the site's fan, and a fan decided "wide"), linear 3, clustered 2, sprawling 2, radiating 1. From above most
  towns looked alike (round organic blobs), none had any grid.
- User: towns should start with more character (long, skinny, sprawling) within sane limits; no streets near the map
  edge; a few drastically different secluded towns per map (Acton "has some nice gaps in it"); towns that jump across a
  river; more gridded towns in later years and a setting for organic vs gridded (default organic, especially early).
- Done (PLAN.md 6.3 "Real map round 3"): head start per form with a lead limit (280 m beyond the houses) and 2-5 rounds by
  size / form; a lead limit for all growth (550 m); map edge margin (400 m) and edge-aware shape axes; character towns
  (ot_map, ot_form CHARACTER); fan no longer forces "wide"; stronger forms; river bridges (ot_bridge, unverified in game);
  era trend + "Town layout" setting (ot_grid); FILL reactivate after every fill of a town that was on before (and which
  command turns it off is logged); demand bank up to 2 x 5 increments.

## 2026-10-13: TESTING.md "Real map test", second run (session `2026-10-13_0018_top-up-598153`)

Setup: new generated European (English names) map, hilly, lakes, a sea channel; 16 towns; main mod Act on New towns
(`RUN fresh=true`), debug on, **Testing: grow towns faster On** (`params=...test_grow=2`, 10 `GROW` lines, x1.25 forced
steps); dev Simulate natural growth, Quick 40 years (pace 1, fill every 4, wait main, speed 8). The main mod build had no
industry code yet (no IND / ind= / indPen= fields). Shots `.cache/ot_shots/2026-10-13_00-31-06/`.

- Simulation: 40 years in 194 s (sPerYear 4.8), steps 178, fills 42, fails 0, buildings 2473 -> 5990. Fill years took
  17.8-23.8 s (fill 1.9-7.7 s + the 15 s wait, which timed out in every fill year: `main=0-4/3-13`); the years after a
  wait came at once (`s=0.0`, the clock ran during the wait). Final factors: Bexley 13.53, Braintree 5.37, Burnley 2.94,
  Bilston 2.71, Reepham 2.47, Yarmouth 1.98; 3 towns none.
- Every town stopped getting simulated growth right after the main mod's first dose-fill restore in it (Market Weighton
  year 3 -> 4 steps, Bilston year 4, Yarmouth 6, Braintree 12, Reepham 13; Bexley never had a dose fill: 29 steps), with
  no command timeout and no failure (cause unknown; the sim's early returns are busy / off / gone; offline the sim keeps
  growing a town whose initial capacities rise 15 %).
- Main mod: 89 CHECK (demand 59, open 30, no ahead), 50 BUILT ok, 3 FAILED (Reepham 14 edges 7.5 s, Bexley twice), 4-6
  checks per town over the whole run. PLAN us up to 262 ms in 5 slices. Every fast-town demand check read `demand=36.0`
  (2 x 18, the bank cap).
- Mod share of new street edges (BUILT edges / CHECK edges first -> last): Reepham 26/50, Harwich 21/29, Market Weighton
  48/62, Bilston 72/166, Barnard Castle 27/55, Leyburn 10/10, Yarmouth 20/62, **Bexley 38/415**, **Burnley 4/51**, North
  Petherton 4/18, Clay Cross 9/13, Buckfastleigh 15/26, **Southsea 2/28**, Middlewich 20/21, Sutton 20/50, **Braintree
  20/201**; overall 356/1257 = 28 %.
- Styles: 6 Nordic of 16 (hills / valleys / lakes everywhere: every town rough 1.00 from the 2 km height spread),
  EU organic 8, MED hill 2. Forms: shore 7 (4 drawn p 0.23-0.66, 3 from the site shape candidate), linear 4, wide 3.
  Bilston (lake, shore) read as a shore strip; SHAPE `shore=` 0.39-0.84 near-water share, depth 328-725 m (over every
  street incl. the starting core). METRO: Bexley `on=false why=site cap=4164` (rough 1.00 although its floor slope is
  0.02), Braintree `why=style` (MED hill).
- Tour: 16 shots, 15 files; shot 1 (Bexley, settleMs=2499 steady=true) wrote none, as in v8 / v9: the first screenshot
  request of each session.
- User: liked the Barnard Castle satellite cluster (vanilla: houses on the generator's streets at a farm ~1.2 km out).
- Follow-up: PLAN.md 6.3 "Real map round 2", NEXT_PHASE_BRIEF 20.

## 2026-10-12: TESTING.md "Showcase v8" (run 2026-10-12, session `2026-10-12_2129_top-up-530609`)

Result (game log, shots `.cache/ot_shots/2026-10-12_22-10-37/`, shots 1-2 NA grid / NA suburb dropped by the game
again): 32 towns, 310 built, 0 refused (32 PRUNE, 1 DIAGJOINT), notPossibleNoCollision=11, modEdges 4216, modHouses
23744, roundS 27.7 (rounds 17.7-36.8 s: build 2.5-4.7 s, grow 12.9-32.7 s, inflight 12, peak 12), settle 3 passes
72.5 s (+7402 buildings). Targets:

| target | v8 | verdict |
| --- | --- | --- |
| 1. linear elongation | TOWN linear streets / houses elong 1.22 / 1.12, ridge 1.43 / 1.21 (aim >= 2.5 / 1.8). During the rounds the SHAPE lines read linear streets 1.60-2.06, houses 1.62-2.08 (last build 1.60 / 1.62); the last round's growth and the settle added 350 buildings and 113 game-made edges around the core. `armGap` max 494 m (NA grid's linear arm), shape row <= 326 m; fingers 3 arms | **missed** (gaps met) |
| 2. metropolis variants | own grid 0.31 / radial 0.23 / corridor 0.23 / oldcore 0.23 / polycentric 0.56 (aim >= 0.35); buildings 3373 / 5006 / 4096 / 4780 / 1207; r 1227 / 1282 / 1071 / 1177 / 594 m (aim <= 1100); grid orth 0.50 (aim 0.6), radial arms 2, radial + ring 0.46, corridor elong 1.21 (aim 2.0), polycentric c1 0.5 / ha, between 0.88 (aim c1 >= 3, between < c1); FILL restore on 4 metropolis towns (8-9 each, polycentric restores under POLY_CAP); shots 28-32: five distinct towns, not touching | distinct in the shots (user: "the metropolis ideas are best so far"); the numbers mostly **missed** |
| 3. form row | linear elong 1.15 vs clustered 1.02 (+0.13, aim +0.4); sprawling dens 11.0 vs clustered 12.3 (0.89, aim <= 0.75), green 0 (aim >= 2); radiating arms 1 (aim >= 3) | **missed** |
| 4. superblock lattice | own 0.48, last townMix 2/38/60 (large + medium 40 %), orient orth 0.58 | met but orth (0.58 vs 0.6) |
| 5. NA grid reads as a grid | NA grid orth 0.43 / own 0.32, NA grid 1900 0.39 / 0.29 (aim 0.6 / 0.4); NA grid drew `shape=linear` toward its neighbour (form linear), increments 4-14 edges; shot 01 dropped | **missed** |
| 6. round time | avg 27.7 s, build 2.5-4.7 s, peak 12, metropolis FILL `concurrent=true timeouts=0` | met |
| 7. fills spread | dose FILL lines per round 20 / 2 / 1 / 0 x 6 / 3 (round 1: every shaped town's first dose) | round 1 missed, rest met |
| 8. regression | 0 REFUSED, 1 DIAGJOINT, notPossibleNoCollision 11 (v7 6); RB one-way as v7 (`fallback=false`, 7/7 configs, ring 0/4 parcels); Density: control green 0 gaps (v7 3 / 13 %); settle 72.5 s | refusals and control green **worse** |

User (2026-10-12): "Metropolis polycentric ends up with too many empty streets built out before town growth"; "NA grid
takes a while to start building out grid patterns"; "Nordic isn't clear, what makes this Nordic?"; keep Control A,
superblock after a while, the fingers town's edge row of houses facing open land, form radiating, all form and
metropolis options; "The metropolis ideas are best so far. Metropolis grid starts to feel almost like it could be the
American grid or suburbs"; "I like EU organic ... the empty green space and big curve is interesting".

Causes found (log + offline, NEXT_PHASE_BRIEF 16):

- *Linear round in the TOWN line:* the shape held during the rounds (SHAPE houses elong up to 2.08); the rounding came
  after the last build: round 10's growth and the settle's three forced passes ran with no script increment at all
  (+350 buildings, +113 game-made edges branching off the round core). The showcase settle now runs the main mod's
  normal check after each pass.
- *Polycentric empty grid:* 36-edge increments (~2.4 km of street each) with only ~70 new buildings a round, the twin
  shape's distance field cheap around the secondary centre, the NA grid lattice leading by cells: ~3-4 km of large
  arterials with no houses. The arm fill rule only covered arm shapes, not the twin.
- *NA grid organic early:* a `linear` shape toward the neighbour (2.4 km) with arm fill gates, 4-14 edge increments,
  unlocked streets the game branched its organic side streets off; the metropolis grid (compact, every street locked,
  36-edge increments, the fill) read as the American grid.
- *Nordic:* the profile was a plain 90 x 70 m grid grower (gridness 0.8): nothing Nordic in it.
- *First two shots:* the tour started while the game script wrote the 32 TOWN lines (~3 s Main Thread stall); shot 1
  fired at the end of it (`settleMs=2661`), shot 2 0.3 s later; the game wrote neither (findings towns.md).

The section as it stood (verbatim):

### Showcase v8 (2026-10-12, arm towns extend again, town forms, metropolis keeps its layout, lattice-first grids)

What changed (offline, unverified in game; NEXT_PHASE_BRIEF 15, PLAN.md 6.3 "Showcase v8 round"):

- **Arm towns extend again (main mod):** a strong-reach arm shape (linear / ridge / fingers from the site or forced,
  a linear / radiating / fingers form) no longer widens its envelope when the arm fill rule holds pieces back (v7: the
  increment went beside the core, `inc=out80..100`, houses filled those first and the town grew round); instead the
  fill limit gives up to 1.5 blocks or the increment stays small. Only an increment with nothing at all inside the
  envelope widens it (young cores), and one under 3 edges is planned once more with the envelope free.
- **Town forms (main mod):** every town gets a form on top of its street style: clustered, radiating, sprawling,
  linear, wide, fingers. A site-picked shape decides (valley -> linear, coast fan -> wide, ...), else a seeded draw
  from the style's weights x the site (open plains favour sprawling, rough / coast / valley clustered). Sprawling =
  1.3 x blocks, far front, hotspots, 3+ meadows; clustered = 0.9 x blocks, tight front, no meadows. Saved with the
  plan frame (`f`); older frames: no form. STYLE `form= formWhy=`, SHAPE `form=`, showcase TOWN `form=`.
- **Metropolis keeps its layout (main mod):** every new street of a metropolis is locked, increments are 36 edges
  (`PLAN maxEdges=36`), and the metro fill restores the initial capacities to at most +25 % per fill (`FILL restore`
  on metropolis towns too; v7: none, the target ran to 2.6 x the town). A radial metropolis with a radiating /
  fingers / linear form grows fingers along its 8 spokes; a grid metropolis with a linear / wide form keeps that
  outline. `METRO ... between=` per ha fixed (v7 printed raw counts when the town was smaller than its discs).
- **Lattice first (main mod):** superblock (from 1950) and NA grid (from 1950) on a game-made core or saved frame lay
  out their arterial / collector cell lines first (lead up to a cell beyond the front, 8 pieces deep, 0.6 / 0.7 x
  cost), so the 350 x 250 m superblocks and the 400 m NA grid frame show early.
- **Fills faster (main mod):** a build's DevelopAt calls go out back to back (the restore after all); the dose's surge
  window is spread 225-375 s by town id, so doses don't all come back in the same round.
- **Dev showcase rows:** gone: Control B, the density levers weights / upgrade / medium (control stays), the
  locked+fill twins and the fingers plain twin (the linear plain twin stays as the lock control). New: form row
  `Form: clustered / radiating / sprawling / linear` (all JP dense). The metropolis towns sit in a 5 km band at the
  bottom, staggered ~3.6 km apart (v7 2.5 km: they touched), each with a forced form (grid clustered, radial
  radiating, corridor linear, oldcore clustered, polycentric sprawling). 32 towns (31 without Roundabouts &
  Interchanges). TOWN lines add `orient=orth/radial/ring` (street length shares: grid-aligned, toward the centre,
  along rings), `own=` (our share of the town's street edges) and `dens=` (buildings per ha in the 90 % radius).
- **Dev "Tour all towns"** (OT Dev window, beside Auto tour): on any map, measures every town (`ALLTOWN n= town=
  name= buildings= edges= r= orient= dens= style= form= shape= metro=`) and flies to the 40 biggest with screenshots.

Setup: as v7 (NEW Blank Slate game, Large; mods `square_organic_towns` + `square_organic_towns_dev` + Blank Slate +
Sandbox + Roundabouts & Interchanges; quit TF3 fully first; `make link` is done; main mod settings: Debug log On).
**Autosave off** in the game settings (v6 / v7: ~10-12 s inside a round).

Run:

1. OT Dev window: "Settle after the rounds" **3 grow passes**, Tour after settle ON, Screenshots ON, dwell **3 s**,
   Camera distance **1800**, Shape row top-down ON (also the form and metropolis rows).
2. **Showcase: build all**, N = **10**. Don't press Auto tour; it starts after the settle.
3. When the tour has finished: `grep 'SQOT' stdout.txt` (or the whole file) and `uv run tools/ot_shots.py`.

Targets (measurable from the TOWN lines unless said otherwise; v7 in brackets):

1. **Linear elongation back:** Shape: linear and Shape: ridge TOWN `metrics=...elong=` >= 2.5 and `houses=` (first
   number) >= 1.8 [1.26 / 1.06 streets, 1.30 / 1.26 houses]; offline 2.62 / 2.19. No empty ladders: every SHAPE
   `armGap=` gap <= ~490 m (fill lead 2 + relax 1.5 blocks + one edge) [282]. Shape: fingers keeps >= 3 arms.
2. **Metropolis variants distinct at the end** (shots: five different towns that don't touch), measured:
   - every metropolis `own=` >= 0.35 [~0.10: 145-180 of 1425-1852 edges], buildings 2500-5500 [4901-6061], r <= 1100 m
     [1213-1264];
   - grid: `orient` orth >= 0.6; radial (radiating: fingers on the spokes): `metrics` arms >= 4 or `orient`
     radial + ring >= 0.75; corridor: elong >= 2.0; oldcore: shot with an organic centre and gridded districts;
     polycentric: last `METRO step` `dens=core:a/c1:b` with b >= 3 per ha and `between` < b [c1 0.2];
   - `FILL restore` lines on metropolis towns (initials back to <= +25 % per fill).
3. **Form row distinct:** Form: linear elong >= Form: clustered elong + 0.4; Form: sprawling `dens` <= 0.75 x
   Form: clustered `dens` and `green` gaps >= 2; Form: radiating `metrics` arms >= 3. STYLE `form=` on every
   showcase style town (seeded draws: note which forms the style towns got).
4. **Superblock lattice:** Superblock `own=` >= 0.4 [0.30], the last BUILT `townMix=` large + medium >= 35 % [21 %],
   `orient` orth >= 0.6; shot 10: rectangular 350 x 250 m frames around the core, not loops at its edge.
5. **NA grid reads as a grid** (Chicago: long straight streets, regular blocks): NA grid and NA grid 1900 `orient` orth
   >= 0.6, `own=` >= 0.4 [0.30, 0.36]; shots 01 / 13 (01 was dropped in v7: if the first shot drops again, Auto
   tour by hand from NA grid).
6. **Round time:** `SHOWCASE ROUND ... s=` average <= 55 s [74.1, one town at a time], `build=` <= 25 s per round;
   `inflight=12 peak=` > 1; metropolis FILL debug lines `concurrent=true` with `timeouts=0`.
7. **Fills spread across rounds:** `FILL town=... kind=dose` lines per round (between two ROUND lines) at most 10 in
   every round [v6 round 9: 23].
8. Regression: refused / DIAGJOINT / notPossibleNoCollision no worse than v7 (3 / 1 / 6); RB one-way as v7; green
   gaps of the Density: control town >= 2 gaps / >= 10 % [3 / 13 %]; settle `s=` (3 passes) <= ~90 s [84.7].

Send back: `grep 'SQOT' stdout.txt`, the screenshots, and what you see.

## 2026-10-12: TESTING.md "Showcase v7" (run 2026-10-12, session `2026-10-12_1900_sqot-dev`)

Result (game log, shots `.cache/ot_shots/2026-10-12_19-16-20/`, shots 1-2 NA grid / NA suburb dropped by the game):
35 towns, 329 built, 0 refused (3 REFUSED pre-check lines, all one metropolis's own edges colliding; 33 PRUNE, 1
DIAGJOINT, 1 JOINTRULE), notPossibleNoCollision=6, modEdges 4223, modHouses 24132, 14.7 min, roundS 74.1 (rounds
56.7-98.4 s; still one town at a time: the concurrent builds came after this run started). Targets:

| target | v7 | verdict |
| --- | --- | --- |
| 1. no empty arms in non-arm towns | style towns all `reach=mild`; last `armGap` max 223 m (NA grid 1900), JP dense 62 m; shot 08 compact | met |
| 2. arm towns fill before they extend | `armGap` max over all steps 161-282 m (<= 340); LOCK withParcels/alive linear 115/146 = 79 %, fingers 136/142 = 96 % (plain 58 %, 80 %); houses elong linear 1.30, ridge 1.26 (aim >= 1.6; v6 1.19 / 1.53); `armFill=` 5-22 on the linear PLAN lines | gaps met, elongation **missed: linear / ridge grew round** |
| 3. straight wide streets | `wideDefl` max large 6, medium 24 deg; 2 pieces narrowed (`bent1`) | met |
| 4. one-way ring | `RB SEND ring=oneway fallback=false newNodeConfigs=7/7`, `RB BUILT ok=true ring=4 arms=4`, no RB FALLBACK, no crash; ring / arms 0 parcels after 7 rounds | met (not adopted) |
| 5. metropolis row distinct | 5 x `METRO on=true`; 4901-6061 buildings, r 1213-1264 m, but 1425-1852 edges of which 145-180 ours (`own` ~0.10); shots 31-35: the same organic blob, towns touching; polycentric c1 density 0.0-0.2 / ha (the second centre never filled) | **missed** |
| 6. green gaps | Density control 3 gaps / 13 %; shape row 0-1 gaps; metropolis 1-4 gaps, share 1-2 % | control met, others low |
| 7. buildings vs the plain twin <= 1.4x | linear 1027 / 702 = 1.46, fingers 1217 / 687 = 1.77, locked+fill 1.69 / 1.60 | over |
| 8. refusals | 3 REFUSED / 1 DIAGJOINT (v6 3 / 4), notPossibleNoCollision 6 (v6 10) | better |
| 9. settle 3 passes | 84.7 s (v6 67 s; the metropolis towns grew 300-900 per pass) | longer |
| 10. normal play | not run | open |

Causes found (log + offline reproduction, NEXT_PHASE_BRIEF 15):

- *Linear / ridge round:* the arm fill gate held the arm pieces back (`armFill=` 5-22 per PLAN line, `armBuilt=` housed
  337 m for five rounds while the town grew 212 -> 449 buildings), and the selector's envelope relaxation (an
  under-filled increment widens the envelope x 1.2 up to 8 times) then spent the increment beside the core (`SHAPE
  inc=out80..out100`). Those side streets lay nearer the core in network terms, so the houses filled them first and
  the arm stretch behind the gate never got housed: a loop that kept the town round. Reproduced offline with houses
  filled by network distance (F.markBuilt): linear streets elong 1.11-1.32 (game 1.26).
- *Metropolis convergence:* the unbraked metro fill reset the target every build (radial 57658 vs 22136 persons); our
  18 edges per round housed a tenth of the growth, the game built 86-205 edges a round of its own (organic, branching
  off our unlocked streets too). By round 5 the variant's skeleton was ~10 % of the town.
- *Superblock:* 6-12 edges per increment (85 mod edges vs 197 game-made after 10 rounds), 0 % large, mix 0/16/84: the
  late hierarchy's wide lead cap (1.25 x the 87 m interior block) kept the 350 x 250 m arterial cells from forming;
  only interior locals grew, as small loops at the edge of the game core. NA grid alike (107 mod edges, mostly
  medium / small, 5-15 edges per increment).

The section as it stood (verbatim):

### Showcase v7 (2026-10-12, arms fill before they extend, straight wide streets, one-way rings, automatic metropolis)

What changed (offline, unverified in game; NEXT_PHASE_BRIEF 14, PLAN.md 6.3 "Showcase v7 round"):

- **Long arms only where the shape wants them (main mod):** strong reach only for linear / ridge / fingers picked from
  the site (valley, coast, river, hillside, ridge) and for the dev's forced shapes; every other shape grows mostly
  around (arm reach 1 + (ka - 1) x 0.4, one block of arm front). "Toward the neighbour town" pulls much less (0.12 x the
  context gain instead of 0.6; in v6 most showcase style towns turned linear from it, 2.5 km apart). STYLE
  `shapeGeom=... reach=strong|mild`, SHAPE `reach=`.
- **Arms fill before they extend (main mod):** no piece reaches farther along an arm than the farthest street with
  houses on that arm + 2 blocks (1.25 for mild arms, at least 120 m); deep arms' back streets and rungs only beside the
  housed stretch (+ half a block). Uses the parcels with a building per street (snapshot `built`). PLAN `armFill=`
  (pieces held back), `armBuilt=` per arm `housedAlong:limit`; SHAPE `armGap=` per arm `gap/street` (m the streets run
  beyond the farthest housed street / the farthest street along the arm).
- **Straight wide streets (main mod):** a large piece keeps its template only with <= 10 deg deflection per edge and
  <= 12 deg at joints along its line, else medium (<= 25 / 30 deg) or small. PLAN `hier=wide/stub/bare/bent`,
  `wideDefl=L/M` (largest deflection of the kept large / medium pieces, deg).
- **One-way roundabout ring (dev):** "Roundabout here" and the showcase roundabout build a counterclockwise one-way town
  street ring (`town_new_one_way_small`) with the engine's one-way ring lane pattern; the two-way ring only as a logged
  fallback (`RB FALLBACK`). The "experimental" toggle is gone. TOWN `roundabout=built_step_3_ring_oneway`.
- **Metropolis is a city style (main mod):** the setting is gone; big towns (>= 4000 persons) on big flat open land
  become a metropolis by themselves (a seeded ~35 % of those), variant by region / site: grid, radial, corridor,
  oldcore, polycentric (secondary centres from 9000 persons, LA-like). Large arterials (straight-wide rule), the
  variant's shape and lock, the strong fill on the variant's streets, parks (green reserves). `METRO town= on=true
  variant= why= centres= at= templates= outer=` once, `METRO step town= variant= centres= dens=core:a/c1:b between=
  buildings= lock= green=` per planned increment (debug).
- **Green gaps (both):** EU organic / extension, MED hill, Nordic and NA suburb leave 2-3 seeded meadows the plan
  grows around (`excluded=green` pieces), a metropolis 4 parks. Measured as `green=gaps/gapHa/maxHa/enclosedHa/share%`
  (enclosed open land without buildings, patches >= 1 ha) on SHAPE, METRO step and the showcase TOWN lines.
- **Dev showcase:** the metropolis twin and the three DevelopAt flag twins are gone; a metropolis row: `Metropolis:
  grid` (NA grid), `radial` (EU extension), `corridor` (EU extension), `oldcore` (EU organic), `polycentric` (NA grid,
  its secondary centre 0.8-1.0 km out from the first build). Top-down like the shape row. 35 towns (34 without
  Roundabouts & Interchanges). TOWN lines carry `metro=` and `green=`.

Note (added after the v7 run started): from the next game start the showcase builds each round's towns concurrently
(up to 12 jobs at once, PLAN.md 6.3 "Dev showcase speed"); ROUND lines add `build= grow= other=` seconds, `builds=`,
`inflight=` (cap) and `peak=` (most jobs at once); a growth batch's late callback logs `LATE` (timeout 120 s). The
v7 run (session `2026-10-12_1900_sqot-dev`) still built one town at a time. Autosave
off in the game settings keeps a ~10 s save out of the timings.

Setup: a NEW Blank Slate game (Large if possible), mods `square_organic_towns` + `square_organic_towns_dev` + Blank
Slate + Sandbox + Roundabouts & Interchanges. Quit TF3 fully first; `make link` is done. Main mod settings: Debug log
On, the rest default (there is no Metropolis setting any more).

Run:

1. OT Dev window: "Settle after the rounds" **3 grow passes**, Tour after settle ON, Screenshots ON, dwell **3 s**,
   Camera distance **1800**, Shape row top-down ON. Ring: one-way (default).
2. **Showcase: build all**, N = **10**. Don't press Auto tour; it starts after the settle.
3. Optional: in an EU extension town with a free dead end, point the camera at it and press "Roundabout here"; watch
   cars drive round the ring (counterclockwise) and out of every arm.
4. When the tour has finished: `grep 'SQOT' stdout.txt` (or the whole file) and `uv run tools/ot_shots.py`.

Targets:

1. **No empty arms in non-arm towns:** for the style towns (JP dense, NA suburb, Nordic, superblock, EU extension,
   EU ext roundabout, EU 1900), STYLE `reach=mild` unless the shape came from the site; the last SHAPE line's
   `armGap=` <= ~250 m on every arm (v6: ladders 400-900 m past the last house); screenshot 08 (JP dense) without
   the two empty straight arms.
2. **Arm towns fill before they extend:** shape-row linear / ridge / fingers and the locked+fill twins: `armGap=` <= 2
   blocks + 120 m (~340 m in EU extension) at every step; `withParcels` / `alive` on the LOCK report >= 60 % (v6:
   linear 47 %, fingers 65 %); TOWN `houses=` elongation for linear / ridge higher than v6 (1.19 / 1.53), aim >= 1.6.
   `armFill=` > 0 on some PLAN lines means the rule held pieces back.
3. **Straight wide streets:** every PLAN line `wideDefl=` large <= 12, medium <= 30; `bent` counts how many wide
   pieces were narrowed. Screenshots: large avenues straight, no wide curves (NA suburb, superblock, metropolis row).
4. **One-way ring:** `SHOWCASE RB SEND ... ring=oneway fallback=false newNodeConfigs=7/7`, `RB BUILT ring=4 arms=4`, no
   `RB FALLBACK`, no crash; in the roundabout town's screenshot / close-up a one-way ring with arrows, cars driving
   round and exiting. If `RB FALLBACK` appears, send its `why=` and the RB PLAN lines.
5. **Metropolis row:** one `METRO town=... on=true variant=<v>` per row town; the five shots visibly different (grid
   blocks with straight avenues; radial spokes with rings; a dense spine without empty ladders beyond the built edge;
   an organic centre with gridded outer districts; two dense centres with lower-density land between).
   Polycentric: `METRO step ... centres=1 dens=core:a/c1:b between=c` with b rising over the steps and c < b.
   Buildings: dense (v6 metropolis twin 5804) but not exploding (polycentric restores: `FILL restore` lines).
6. **Green gaps:** TOWN `green=` for the density control twin (the look the user liked) vs the shape row and the
   metropolis row: gaps >= 2 and share >= ~10 % in the EU extension / organic towns; the metropolis row keeps some
   (parks). Note towns with `0/...`.
7. **Plain twins vs locked+fill vs shape row** (LOCK report): buildings within ~1.4 x the plain twin's (v6: 1.55-1.57).
8. Refusals: `REFUSED` / `DIAGJOINT` vs v6 (3 / 4), `notPossibleNoCollision=` (v6 10).
9. Settle: `SETTLE end reason=passes s=` ~60-70 s (v6: 67 s).
10. Normal play (optional, short): a new map with only the main mod, Debug log On, Testing: grow towns faster On; INIT
    `metropolis=auto_from_4000`; after an hour `grep 'SQOT\] METRO'`: big flat towns only, `on=false why=small|site|rare`
    for the others.

Send back: `grep 'SQOT' stdout.txt`, the screenshots, and what you see.

## 2026-10-12: Showcase v6 timing analysis (session `2026-10-12_1732_sqrl-sqsg`)

Rounds 2-8: 33-41 s each, build stage ~18 s (32 towns one by one: CHECK -> BUILT ~0.56 s each, BUILT `ms=` 220-340,
CHECK `us=` 9-34 ms) + two growth batches 13 + 6 s. Round 9 (92.1 s): build 53 s (23 FILL doses vs 1-2: the
`FILL_SURGE_S` 300 s window of round 1's doses lapsed for most towns at once; 2 DevelopAt + restore each, sequential;
autosave at 17:50:00 took 10.3 s, Superblock's DevelopAt counted as `timeouts=1`), growth batches 26 + 13 s. Round 10
(56.8 s): the remaining 9 doses, batches 20 + 9 s. The metropolis twin's 12-point fill took ~5 s per round. Led to
concurrent town jobs in the dev showcase (PLAN.md 6.3 "Dev showcase speed").

## 2026-10-12: TESTING.md "Showcase v6" (run 2026-10-12, session `2026-10-12_1732_sqrl-sqsg`)

Result (game log, shots `.cache/ot_shots/2026-10-12_17-53-32/`): 34 towns, 320 built, 0 refused (3 REFUSED lines, 29
PRUNE, 4 DIAGJOINT, 1 JOINTRULE), notPossibleNoCollision=10, modEdges 4992, modHouses 17462, 9.7 min. Targets:

| target | v6 | verdict |
| --- | --- | --- |
| houses elongation >= 2 (linear / ridge) | 1.19 / 1.53 (TOWN `houses=`) | missed |
| >= 50 % mod edges with parcels | linear 85/180 = 47 %, fingers 117/180 = 65 % (plain twins 32/175, 69/173) | about |
| locked+fill <= ~1.4 x plain buildings | linear 1076 / 685 = 1.57, fingers 1046 / 673 = 1.55 (shape row 1.49 / 1.54) | over |
| FILL restore | DevelopAt reset the initials at once (250 -> ~730 = current capacity), restore put them back (~285, +15 %) | works |
| FILL effect near growth | 6.6 buildings within 60 m per fill (55 fills); 178 x `skip=surge`, 7 x `skip=cap` | DevelopAt doesn't build at its point |
| DevelopAt flags | fill only 1137 buildings / streets 1040 / upgrade 965 | no clear effect |
| lock | locked = alive in locked towns; attached 2-4 (shape row, lockfill) vs 24 / 47 (plain) | works |
| metropolis twin | 5804 buildings, 1757 edges, r 1252 m | dense, liked |
| settle 3 passes | 67 s, 32534 -> 38726 buildings | works |
| deep arms | 2-row ladder strips 400-900 m past the built edge, nearly empty (shots 08, 12, 16, 18, 28, 31) | failed |

Diagnosis of the empty arms (SHAPE_LINEAR, LOCK step lines): withParcels stayed 18 while its mod edges went 18 -> 54
(steps 1-3), 44 of 144 at step 8 (31 %), houses on our streets came only at steps 9-10 (the town's demand); every
increment was 89-100 % arm (`inc=arm100`). The showcase builds every step (`force=true`, `needsRoom=false`), 18 edges
of arm frontage per round against ~40-60 new buildings per round, and the planner's arm reach counted junctions, not
houses (the strips make their own junctions, so the front ran out every increment). Lock is not the cause (the
unlocked plain twin had the fewest parcels, 18 %); the dose barely ran (178 x `skip=surge`). Style towns turned linear
from "toward the neighbour town" (towns 2.5 km apart): JP dense, NA suburb, Nordic, superblock, EU ext roundabout, EU
1900. The roundabout town built its roundabout as a two-way town street (`ring=town`: the one-way ring was behind the
experimental toggle). User feedback and the follow-up: NEXT_PHASE_BRIEF 14, TESTING.md "Showcase v7".

The section as it stood (verbatim):

### Showcase v6 (2026-10-12, houses onto the arms: lock + dosed fill, deep arms, metropolis, short settle)

What changed (offline, unverified in game; NEXT_PHASE_BRIEF 13, PLAN.md 6.3 "Houses onto the arms", "Deep arms"):

- **Lock by default (main mod, normal play too):** in shaped towns (not compact) every new street in an arm corridor
  or near the envelope rim goes out `roadDevelopmentLocked`. BUILT lines: `locked=<n>`.
- **Dosed fill (main mod, normal play too):** after a build of a shaped town, `makeTownDevelopAtCmd(point, false,
  false)` at 2 points 20 m beside its new arm / rim streets (`FILL town= kind=dose points=2 initial=now/base
  near= far=`), then the town's initial capacities are put back to at most +15 % (`FILL restore initials=
  before->afterDevelopAt->restored`), never above 1.3 x their sum at the town's first build. `FILL effect` at the
  town's next check: buildings within 60 m (`near`) / 200 m (`far`) of the points, the town's buildings, capacity,
  initial capacities and size factors before -> now. Why the restore: v5's fill twin showed that DevelopAt resets
  the initial capacities to the town's current size (findings towns.md), which made it grow 12x.
- **Metropolis growth (new mod setting, default Off):** towns from ~4000 persons (~1000 buildings) get v5's strong
  fill (12 points per build, no restore) up to 50000: `FILL kind=metro why=big`. INIT logs `lock=shape fill=dose2
  metropolis=off|on_from_4000`.
- **Deep arms:** arms grow as strips with back streets (see PLAN.md 6.3 "Deep arms").
- **Dev showcase:** the shape row runs the main mod's defaults. Probe row (all EU extension, twins of the shape
  row): `Shape: linear (plain)` / `Shape: fingers (plain)` (no lock, no fill: v5's shape row), `Shape: linear
  (locked+fill)` / `Shape: fingers (locked+fill)` (every new street locked + dose), `Metropolis (linear)` (the
  metropolis fill forced from step 1, no lock: v5's fill twin), and three DevelopAt flag twins with the dose and
  no lock: `Shape: linear (fill only)` (false, false), `(fill streets)` (developStreets = true), `(fill upgrade)`
  (upgradeBuildings = true). Freeze twins gone. LOCK lines now carry `lockMode= fill=` and come for every probe
  town and its shape-row twin. 34 towns (6 x 6 grid).
- **Settle:** default "3 grow passes": three forced growth batches back to back, each one step further (sizeFactors
  1 + (10 + k) x 0.25), 6 s after each, no game time (v5: 2 game years = 16 real minutes). `SETTLE pass n= extra=`,
  `SETTLE end reason=passes s=`. The game-time modes are still in the picker. Tour dwell 3 s (default).

Setup: Blank Slate (Large if possible), mods `square_organic_towns` + `square_organic_towns_dev` + Blank Slate +
Sandbox + Roundabouts & Interchanges, a NEW game. Quit TF3 fully first; `make link` is done. Main mod settings: Debug
log On, Metropolis growth Off (the showcase's metropolis twin forces it), the rest default.

Run:

1. OT Dev window: "Settle after the rounds" **3 grow passes** (default), Tour after settle ON, Screenshots ON, dwell
   **3 s** (default), Camera distance 1800, Shape row top-down ON. Leave "Fill mod streets" and "Freeze style towns"
   OFF.
2. **Showcase: build all**, N = **10**. Don't press Auto tour; it starts after the settle (should be ~1-2 minutes
   after the last round, not 16).
3. When the tour has finished: `grep 'SQOT' stdout.txt` (or the whole file) and `uv run tools/ot_shots.py`.

What to look for (targets from NEXT_PHASE_BRIEF 13):

1. **Houses on the arms (shape row, defaults):** the last `SHAPE` line per shape town: `houses=` elongation >= 2 for
   linear and ridge (v5: 1.38 / ~1.4). `SHOWCASE LOCK key=SHAPE_LINEAR ... when=report`: `withParcels` / `alive` >=
   50 % (v5: 42/177). Total `buildings=` within ~1.4 x the plain twin's (`SHAPE_LINEAR_PLAIN`; v5 plain ~597).
2. **Lock:** BUILT `locked=` > 0 for linear / cross / fingers / ridge towns, 0 for compact; LOCK `attached=` low in the
   shape row and the locked+fill twins, ~30 in the plain twins (v5: 33).
3. **Fill and restore:** `FILL` lines (`kind=dose points=2`), then `FILL restore initials=a->b->c`: if b is about
   the town's current capacity, DevelopAt reset the initial capacities at once and the restore caught it; `FILL
   effect` a round later: `initial=` should stay at the restored value (if it jumped again, the reset came late:
   note it), `near=` growth vs `far=` growth says whether DevelopAt builds at its point. Note towns with
   `FILL ... skip=cap` (the 1.3 x brake reached) and `skip=surge`.
4. **DevelopAt flags:** compare `Shape: linear (fill only)` / `(fill streets)` / `(fill upgrade)`: FILL effect
   near / far / buildings, the TOWN line `edges=` (vanilla streets), capacity.
5. **Locked+fill vs plain vs shape row:** LOCK `houses=` / `withParcels=`, TOWN `houses=` elongation, buildings.
6. **Metropolis twin:** `FILL kind=metro why=forced points=12`, buildings at the end (v5's fill twin 7196); from
   above a dense big town (it may round out: that is the metropolis look the user liked).
7. **Deep arms (shots of the shape row):** arms as strips 2-3 blocks deep with back streets parallel to the main
   street and closed blocks, not a spine with stubs; no zig-zags / balloons; no wide streets far into the fields.
8. **Settle:** `SETTLE pass n=1..3 extra=1..3`, `SETTLE end reason=passes` with `s=` in seconds; `SETTLE sample`
   buildings grow after each pass.
9. Refusals: `REFUSED` / `DIAGJOINT` counts vs v5 (2 / 1). Locked dead ends must still take our joints.
10. Normal play (optional, a short second run): a new map with only the main mod, Debug log On, Testing: grow towns
    faster On: INIT `lock=shape fill=dose2 metropolis=off`; shaped towns log `locked=` and `FILL` / `FILL restore`;
    no town explodes (buildings per town over an hour similar to before).

Send back: `grep 'SQOT' stdout.txt`, the screenshots, and what you see.

## 2026-10-12: TESTING.md "Showcase v5" (run 2026-10-12, session `2026-10-12_0905_top-up-488838`)

Result (game log 2026-10-12, labelled shots `.cache/ot_shots/2026-10-12_09-29-35/`): 31 towns, 290 built, 0
refused, 4 notPossibleNoCollision, no errors. Street shapes read (linear streets elong 3.35, ridge 2.91, fingers
3 arms, cross 4 arms; fan / twin / lens unclear), but houses did not follow: ~25 % of mod edges had parcels
(linear 42/177, 183 houses), houses elong 1.07-1.48; arms looked like ladders (spine + stubs). Lock probe: the
flag stuck (157/157), houses still built, side streets attached 0-1 vs 33; fingers locked 426 houses on our
streets vs 168. Freeze did nothing useful. The fill twin exploded to 7196 buildings and grew round (DevelopAt
resets the town's initial capacities: docs/findings/towns.md). Settle 2 game years took ~16 real minutes.
Follow-up: NEXT_PHASE_BRIEF 13, TESTING.md "Showcase v6".

The section as it stood (verbatim):

### Showcase v5 (2026-10-12, street mix + shapes round: wide-street mix, superblock interiors, joint kinks, shape envelope, lock / freeze probes)

What changed (offline, unverified in game; PLAN.md 6.2 "Street mix", "Joint kinks"):

- **Late styles (from 1950) mix street sizes**: NA grid arterials (large) every 1.2 km plus collectors (medium) every
  400 m; NA suburb arterials every 8 blocks, collectors every 2, curvy local streets and some cul-de-sacs; the town's
  cross axis is a collector, the main street along the axis the arterial. **Superblock**: wide arterial / collector
  grid around each 350 x 250 m block, small local streets inside (two along the block, short staggered cross
  streets).
- **Wide streets don't run far ahead**: arterials at most ~1.25 blocks beyond the outermost junctions (collectors a
  bit more); shaped towns' arms may still lead, at local width.
- **Log**: PLAN lines `mix=L/M/S` (% of the increment's new street length large / medium / small) and
  `kinks=<n> jointRule=on|off`; BUILT lines `mix=` and `townMix=` (all builds of that town this session);
  `JOINTRULE town= kinks= edges=` when a refused increment with sharp joints is planned again without them.

**Shapes round (same run; PLAN.md 6.3 "Shapes round", NEXT_PHASE_BRIEF 12):**

- The driver now sees a town's whole connected street network (it only saw streets within the houses' extent +
  300 m, so v4's shape arms stopped ~600 m out): SNAPSHOT lines `net=<streets followed beyond the circle>`.
- Shaped towns keep new streets inside a shape envelope (no more filling all round the core), arms grow as ribbons
  (cross streets close behind the tip), a cross is an X of 4 arms. One `SHAPE town= shape= axis= net= env= envScale=
  streets=elong/arms/side/waist houses=elong/arms/side/waist buildings= inc=armNN/outNN edges=` line per planned
  increment of a shaped town.
- Showcase TOWN / FOCUS lines: `metrics=` on the whole network (with `arms_side_waist`), `houses=` from the buildings,
  `net=`. The Probe C row (vanilla angles) is gone (findings 2026-10-12: with the main mod's angle setting the
  per-town angles did nothing). A probe row of twins: "Shape: linear (locked)" and "Shape: fingers (locked)" (every
  new street sent with `roadDevelopmentLocked`), "Shape: linear (frozen)" and "Shape: fingers (frozen)" (town
  development off), "Shape: linear (fill)" (DevelopAt beside its new streets each round). Lines: `SHOWCASE LOCK key=
  role=lock|twin … alive= locked= withParcels= lots= houses= attached= vanilla= buildings=` (attached = vanilla streets
  added at our streets' nodes), `SHOWCASE FREEZE effect key= role=freeze|twin … vanilla= edges= buildings= modHouses=`.
- Settle: forced growth passes are ON by default; pressing Auto tour during the settle waits for it (`TOUR deferred`,
  then `TOUR start after=settle`). Density upgrade: `DENSITY effect … when=same` and `when=next` (v4: the effect came a
  round later, 306 -> 670 buildings).

Setup: Blank Slate (Large if possible), mods `square_organic_towns` + `square_organic_towns_dev` + Blank Slate +
Sandbox + Roundabouts & Interchanges, a NEW game (31 towns, 6 x 6 grid). Quit TF3 fully first; `make link` is done.
Main mod settings as v4 (Debug log On).

Run:

1. OT Dev window: Settle **2 years**, "Settle at most, real minutes" **20**, "Settle: forced growth passes" **ON**
   (default), Tour after settle ON, Screenshots ON, dwell 3 or 5 s, Camera distance 1800, Shape row top-down ON.
   Leave "Fill mod streets" and "Freeze style towns" OFF (the probe twins set theirs themselves).
2. **Showcase: build all**, N = **10**. Don't press Auto tour yourself; the tour starts after the settle.
3. When the tour has finished: `grep 'SQOT' stdout.txt` (or the whole file) and `uv run tools/ot_shots.py`.

What to look for:

1. `grep 'SQOT_DEV\] BUILT' stdout.txt`: the last `townMix=` per Superblock / NA grid / NA suburb / ensanche town.
   Target: large <= ~20, medium ~20-30, small >= ~50. Superblock's first increment should no longer be nearly all
   wide (`hier=` and `mix=` on its first PLAN line).
2. Screenshots: superblock towns should show small streets inside the big blocks; NA suburb a wide axis with
   medium collectors and small curvy streets / cul-de-sacs between them; no wide street running hundreds of metres
   into empty fields (narrow arm streets may).
3. Refusals: count `REFUSED` and `DIAGJOINT` lines vs v4 (16 DIAGJOINT). Compare `kinks=` on PLAN lines with the
   DIAGJOINT `turn=` values: if most planned kinks end in a DIAGJOINT refusal, the rule should go on by default.
   Note any `JOINTRULE` lines and whether the replanned increment built.
4. Saved towns from earlier runs (if you load a v4 save): they must load and keep growing; old superblock towns keep
   their open blocks (interiors only in new blocks).
5. **Shape row (top-down shots):** linear / ridge clearly long (streets elong >= 3 on the last SHAPE line, houses
   above ~1.5), cross an X of 4 arms, fingers 4-6 arms with empty wedges, fan one-sided, twin a lobe toward its
   second core, lens an oval; no streets on the "wrong" sides of the core; no bare main street running far ahead of
   its cross streets. SNAPSHOT `net=` should rise above 0 once arms leave the houses. The last `SHAPE` line per town
   tells the story without screenshots (`inc=arm..` high for linear / cross / fingers, `out0` normally).
6. **Lock probe:** compare each locked twin with its plain twin (SHOWCASE LOCK lines): `locked=` should equal `alive=`
   if the flag sticks; `houses=` on the locked streets > 0 means the town still builds along them (needed);
   `attached=` lower than the twin's means the game stopped hanging side streets off them. Note any refusals of the
   locked town's later builds (our own joints at locked dead ends).
7. **Freeze probe:** frozen twins vs plain twins (SHOWCASE FREEZE effect): `vanilla=` near 0 means forced UpdateSize no
   longer adds the game's own streets; `modHouses=` shows whether houses still fill our streets.
8. **Fill twin:** its `houses=` (TOWN line) vs the plain linear town: whether DevelopAt beside our streets pulls houses
   out along the arms.
9. Settle: `SETTLE sample` lines should now show growth every month (forced passes), `SETTLE end reason=target`.
   Density: the `when=next` line for DENS_UPGRADE.
10. Valley / ridge lock case (user idea): Blank Slate is flat, so not in this run; note for a terrain map test.

Send back: `grep 'SQOT' stdout.txt`, the screenshots, and what you see.

