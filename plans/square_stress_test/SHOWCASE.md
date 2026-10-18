# Stress Test: Showcase (user request 2026-10-11)

A new Towns-tab test, "Showcase", for watching Smart Lanes / Roundabouts & Interchanges under traffic. Three bands
across the map, top to bottom (or whatever fits the map best), all using the existing Junction test machinery
(gui/stress_junctions.tl: construction placement, linkProposal / linkPairProposal, settle + retry, lights, Traffic,
summary, warnings, busy guards) wherever possible:

1. **Interchange line.** One town at the far left, one at the far right, joined by a highway (a pair of one-way
   carriageways, as the Junction test's highway links). Between them, in a line, as many of the collection's
   interchanges as fit (square_roundabouts: Parclo, Parclo two quadrants, Diamond, Roundabout Interchange, ...),
   cycling through every type and repeating until the line is full. Each placement uses random variation of the
   construction's size / settings (sizes, lane counts, splitters, slip angles... whatever params the type has),
   seeded so a run can be reproduced (log the seed and each placement's params).
2. **Roundabout line.** The same left-to-right layout with a large country road between two towns, with every
   roundabout type of the collection (round/oval, 1/2/4 ring lanes, splitters, hamburger, Magic Roundabout,
   Channelized Junctions, ...) cycling and repeating, random params per placement.
3. **Roundabout groups.** In the remaining space: for each roundabout type (cycling, random params), one roundabout
   with one town per arm placed in a ring around it (4 arms -> 4 towns, 3 arms -> 3 towns, ...), each town linked
   to its arm. Groups are NOT connected to each other (or to bands 1-2). As many groups as fit.

Requirements: map-edge margins and spacing rules of the Junction test (fitJunctionGrid / inlineStops / MAP_MARGIN);
a precheck that warns (rt.warn dialog) when nothing fits; English only (Stress Test); Traffic option (Off / Bus
lines) like the other tests; summary line; Remove all roads / Remove towns clean it up; tests in
tests/square_stress_test/; TESTING.md section; description changelog under the current unreleased revision.
Smart Lanes applies itself to every placement (Apply automatically), so after the build `make audit` reports on all
of them.

Status: implemented 2026-10-11 (rev 2, unreleased); in-game runs 2026-10-12 (seeds 204313 and 747943, below); the second run's fixes not run in game yet: TESTING.md 6L (6K for the first run's). **Superseded by Showcase v2 (2026-10-12, implemented, not run in game yet: TESTING.md 6N; see the last sections).** The text up to "Showcase v2" describes v1 (lines + groups) and stays as the record.

Implementation notes:
- Pure layout in stress_logic.tl (`showcaseLayout`, `showcaseDraw`, `showcaseArms`, `showcaseReach`, `showcaseRoutes`,
  PRNG `newRng` / `rngInt`: Park-Miller minimal standard, exact in Lua 5.1 doubles); GUI glue `jn.buildShowcase` in
  gui/stress_junctions.tl (reuses its precheck, junctionProposal, linkProposal / linkPairProposal, newEnds, lightsOff,
  busy guard TEST_JOBS); form in gui/stress_hud.script.tl; tests in tests/square_stress_test/test_showcase.lua.
- Types: interchanges Roundabout / Dumbbell / Peanut Interchange, Parclo, Parclo two quadrants, Diamond; roundabouts
  Roundabout (round), Magic Roundabout, Channelized T, Oval roundabout, Channelized X, Hamburger (road / road + lights
  through the centre). Every range is the construction's own value list except Direction / Traffic side (right-hand
  only), Arms None, and Through the centre outside the Hamburger type (its arms are drawn from 3 (T), 4, 6 so no
  extra arm appears and the group towns stay on the known arm directions, at least 60 deg apart).
- Spacing: interchanges reach 485 m, roundabouts an estimate per draw (at most 300 m), 100 m between reaches; towns
  keep 0.35 x their size's spacing + 100 m; the roundabout line sits max(town spacing, 485 + 300 + 300) below the
  interchange line; group towns a ring radius max(town spacing, 300 + town clearance) out, groups 2 x ring + town
  spacing apart. On a taller-than-wide map the layout runs along y.
- Review 2026-10-11: the build step's counters and lists live in one table (`ShowState`), so the step closes over
  43 upvalues in Lua 5.1 (limit 60; the test keeps 10 spare); a line ended by a refused link logs and counts the
  links it skips; the tall-map rotation writes `0.0 - y` (never `-0`; junctionTransf normalises too).
- Faster builds (2026-10-11): every placement is built back to back (each waits only for its own build
  callback), then one settle (INLINE_SETTLE_MS, 3 s, after the last build: docs/findings.md "invalid entity"),
  then every placement's arms are read fresh (node diff against its own pre-build snapshot) and the links follow
  in line order as before. Review 2026-10-11: scan circles CAN overlap (Junction test In line: a stop shifted
  -160 m along its route sits 266 m from the previous one at 4 km, inside its 190 m scan circle; Showcase:
  reach estimates are not measured, 60 m margin), so a read also drops new nodes that a LATER build added:
  every build's circle and snapshot is kept in send order (`Scan`, `JunctionState.scans` / `ShowState.scans`),
  and a node inside a later build's circle but missing from that build's snapshot is that build's (serial
  builds: build j's snapshot is taken after build j-1's callback). Tests: test_junctions "keeps its own
  arms", test_showcase "neighbours closer". Each read logs `res_nodes=N`: how many of its new nodes the
  build callback's resultEntities named (evidence whether they could attribute nodes; not used yet).
  Was 3 s per placement: ~60 placements (Small, 16 km) saved ~3 minutes of waiting; bus lines now start 3 s after
  the last link (was 5 s). Job names unchanged (`showcase`, `showcase:settle`, `showcase:relink`), so the busy
  guards still cover every phase. The build step closes over 44 upvalues in Lua 5.1 (45 in the test; the
  Junction test step 46 / 47).
- Highway town links (2026-10-11 screenshot: the interchange line entered its town on a small street): the merge
  piece copies a large two-way street (stress_junctions `mergeEdge`) and town nodes on large streets rank first
  (stress_logic `rankTownNodes`, `LARGE_PREFER` 400 m); the showcase's Wide grid towns offer large corner stubs.
- ~~Open: reach estimates are not measured; oval arm directions are assumed to be the round layout's.~~ Done
  2026-10-12, below.

## In-game run 2026-10-12 (seed 204313, Small, 16 km Blank Slate) and the fixes

Log: crash_dump/ca9a2f49-..._1.txt (`[SQST] showcase`, `bus_lines_showcase`). 59 of 60 built, 85 of 99 links, then
the sim crashed during the bus lines (docs/findings.md "Sim crash while bus lines were added with Car traffic on";
not addressed here).

| Seen | Cause (offline evidence) | Fix |
|---|---|---|
| A. Interchange line: link 1/13 Roundabout Interchange -> 2/13 Parclo refused 3x {Collision}; the line ended (11 junctions + Grid S2 unlinked, 12 links) | ix 1 had a medium highway (half width 9 m), the Parclo a small one (carriageway centres +-6.5 m, ramps.HIGHWAYS); linkPairProposal copied ix 1's 18 m carriageways into ends 13 m apart: the two copies overlapped | `linkPairProposal` copies the carriageways of the arm whose ends lie closer together; a refused link **splits** the line (only that link unlinked, the rest linked to town B, no bus route on a split line); after a Collision an arm-to-arm link tries `SHOW_BENDS` (one point 50 / 90 m to either side halfway; `(bent +50m)` in the log) |
| B. Roundabout line 13/35 refused by the check "Construction Not Possible" after 12/35 Hamburger (est 94 m) | Offline geometry: the Hamburger's real footprint is 112 m (est 94) and 13/35's 113 m (est 129), 326 m apart: still ~100 m clear, so spacing alone does not explain it (check that type + settings alone in game) | Reach estimates replaced by tables measured offline on square_roundabouts' updateFn (below); placements measured after the build |
| C. Group 4 Oval (arms 2 = 90/210/330, shape 5, radius 5, angle 120) -> Grid S16 refused 3x {Collision} | An oval's arms leave the ring up to 33 deg off their nominal direction (offline: ends at -39 / -141 deg, headings -63 / -117 for nominal -30 / -150); S16's arm itself was straight, so the town node choice (large streets preferred up to 400 m further) is the other suspect | Arms matched by their measured heading (`assignArms` with `cl.hx/hy`), a town without an arm within 60 deg gets the nearest free arm (`assignLeftovers`, logged); after a Collision a town link takes the nearest node (no large preference) through a point 60 m along the arm |
| D. Bus lines: route 2 reused depot "ours, 1177m" of the roundabout line for a group (another network) -> findBestDepotForLine=-1, setLine failed, bus stuck; route 3's depot spot at x=-7898 (294 m from the edge) -> connect "Construction Not Possible", depot left unconnected; route 1 (15.5 km roundabout line) findBestDepotForLine=-1 with its own new depot | Depot reuse ignored road networks; no map margin; a refused connect kept the depot; buses were bought before any depot was confirmed | Routes carry their network (`line N` / `group N`); depots reused only within it (`bl.depotNet`) and built only on the run's own town's streets; buses only from a depot findBestDepotForLine confirms, else a new depot near stop 1 (0-400, 400-900 m) and ask again, else the line is destroyed with no bus bought; a bus whose SetLine fails is sold; depot spots keep `MAP_MARGIN` 400 m; an unconnected depot is removed and the next spot tried |

Reach tables (stress_logic `showcaseReach`): worst case over every param that is not a table key, of the farthest
edge point (9 Hermite samples) + its road's half width, + 12 m. Ring / oval / Hamburger by splitter x shape x
radius size (a road through the centre its own table), Magic by size x lanes, Channelized by layout x scale x arm
length, interchanges by arm length, Parclo / Diamond by scale x arm length. `SHOWCASE_IX_R` 505 m (Parclo scale 3;
the old 485 m was 8 m short), `SHOWCASE_RB_MAX` 315 m (Channelized T scale 5, arm length 4). The roundabout
interchanges are ~300 m, so the interchange line now holds 17-19 on 16 km (was 13), the roundabout line 29-32 (was 32-38). Test: test_showcase "showcaseReach
covers the real footprint" runs every type's updateFn on 30 draws each.

Footprint measurement (stress_junctions `measurePlace`): right after each build callback, the farthest new street
node within reach + `SHOW_MEASURE` (90 m) + `SHOW_HALF_W` (12 m); logged on the placement line as
`reach est=..m measured=..m` (+ `bbox=..m` when the construction's BOUNDING_VOLUME is readable), one
`[SQST] showcase reach:` line per run (per type: measured, over the estimate, worst difference). The next line
placement keeps `SHOW_MIN_GAP` (40 m) from it: moved along the line (`moved Nm along the line`) or left out (`left
out: ...`, counted as refused). Arm ends count only within the measured reach + `SHOW_ARM_MARGIN` (25 m): town streets
grown between the build and the read are not arms. Unverified: whether the new nodes are visible at the build callback (the other tests
read 0.5-1 s later). If not, the measurement happens at the read instead (`measured=..m (at the read)`, later builds'
nodes left out by laterOwns): no shifts then, but the arm-end guard still works. Watch for `(at the read)` and
`measured=?` in game.

Build step upvalues: 32 in the test's Lua 5.4 (was 45): the placement, link and split code moved to module
functions taking the run's `ShowState`.

## In-game run 2026-10-12 #2 (seed 747943, Small, 16 km Blank Slate desert) and the fixes

57 of 61 built, 95 of 95 links, 0 splits; every reach measurement under its estimate. Log lines (stdout.txt,
`[SQST] showcase`; prefix trimmed):

```
showcase: seed=747943 map=16384x16384m towns=54 (Small) lines ix=17 rb=32 groups=12 ring=1200m lights=Game decides traffic=Bus lines
showcase Interchange line 11/17 Peanut Interchange at 1898,7287 angle=0 reach=288m [sqrb_island=1 sqrb_ix_arm_length=1 sqrb_ix_cross=6 sqrb_ix_highway=2 sqrb_ix_layout=3 sqrb_ix_level=1 sqrb_ix_radius_size=1 sqrb_ix_slip_length=4 sqrb_lanes=1] refused by the check: Collision (hits 12 other)
showcase Roundabout line 4/32 Oval roundabout at -5680,6087 angle=0 reach=107m [sqrb_arm_type=6 sqrb_arms=3 sqrb_centre=1 sqrb_island=3 sqrb_lanes=1 sqrb_radius_size=1 sqrb_shape=2 sqrb_signals=1 sqrb_splitter=1 sqrb_tram=2] refused by the check: Construction Not Possible
showcase Roundabout line 30/32 Hamburger roundabout at 6332,6087 angle=0 reach=171m [sqrb_arm_type=6 sqrb_arms=1 sqrb_centre=4 sqrb_island=3 sqrb_lanes=1 sqrb_radius_size=2 sqrb_shape=5 sqrb_signals=1 sqrb_splitter=1 sqrb_through_road=5 sqrb_tram=1] refused by the check: Construction Not Possible
showcase Group 7 Roundabout at 2197,-1460 angle=180 reach=167m [sqrb_arm_type=5 sqrb_arms=2 sqrb_centre=1 sqrb_island=2 sqrb_lanes=1 sqrb_radius_size=3 sqrb_shape=1 sqrb_signals=1 sqrb_splitter=2 sqrb_tram=1] refused by the check: Construction Not Possible
showcase Interchange line 10/17 Parclo, two quadrants at 1020,7287 angle=0 reach=443m [... sqrb_hx_scale=2 sqrb_ix_cross=3 sqrb_ix_highway=1] built ... reach est=443m measured=394m
showcase Interchange line 12/17 Diamond at 2762,7287 angle=0 reach=429m [... sqrb_hx_scale=3 sqrb_ix_cross=2 sqrb_ix_highway=3] built ... reach est=429m measured=417m
showcase summary seed=747943 placements=61 built=57 refused=4 links=95 linked=95 unlinked=0 splits=0
bus_lines_showcase: 28 bus lines between Showcase towns x 5 buses
bus_lines_showcase stopped: balance -92.1M below 1M; tick Keep balance or add money
bus_lines_showcase summary towns=28 ok=0 failed=0 lines=0 (complete 0) buses=0 ... balance -92.1M->-92.1M stopped: ...
```
The run before (seed 204313): `Roundabout line 13/35 Roundabout at -2058,6107 angle=0 reach=129m [sqrb_arm_type=6
sqrb_arms=2 sqrb_centre=1 sqrb_island=5 sqrb_lanes=3 sqrb_radius_size=5 sqrb_shape=1 sqrb_signals=2 sqrb_splitter=1
sqrb_tram=2] refused by the check: Construction Not Possible`.

| Seen | Cause (offline evidence) | Fix |
|---|---|---|
| E. Roundabout line 4/32 Oval (shape 2, radius size 1 = Scale XS 10 m, grown to 15 m by rev 6; 1 ring lane, 4 arms of country large, no splitter) "Construction Not Possible" | **square_roundabouts geometry, by its engine-fitted model**: `checks.engineModel` (tests/square_roundabouts/checks.lua, fitted to the probe verdicts) flags `arms#1 / arms#3: a junction corner 1.4 m behind its node (> 1.0)`. Sweep of the ring con (shape x radius size x lanes x arms x arm road x splitter x centre x tram, 36 000 builds, 2026-10-12, anticlockwise only): 84 flagged, every one an oval (shape 2-4), 1 ring lane, radius 10-20 m (sizes 1-3), splitter off, and nearly all with large arm roads (town / country large; a few town medium). square_roundabouts rev 6 is released (mod.io), so nothing was changed there: **reported** (fix in square_roundabouts: grow such ovals like the round ring's arm-room floor, plus a test over that sweep). **Fixed in square_roundabouts rev 7** (2026-10-12): `geom.plan` keeps a plain arm's curb corner within `geom.ARM_BEHIND_PLAN` (1 m) of its node outside the engine-searched patterns (`geom.radiusSearched`: round and 2:1), so the 168 flagged builds of 1.25-1.75:1 ovals (the 84 above in both directions; rev 6 geometry re-swept 2026-10-14 with direction: 84 anticlockwise + 84 clockwise) grow 1-3 radius steps; this one 15 -> 20 m; `tests/square_roundabouts/test_oval_arm_room.lua`. Showcase reach tables still cover them (offline) | Showcase: a CNP placement is redrawn once (below) |
| F. 30/32 Hamburger (T arms, road + lights through the centre, oval 5), Group 7 Round (Y arms, splitter, country medium, angle 180), 13/35 Round (Y arms, 4 lanes, radius 5, tram) "Construction Not Possible" | **Not found offline.** updateFn (repo, Lua 5.2 doubles): no error, no NaN / inf, no edge under 1 m, no nodes within 0.5 m (`checks.shortEdges`), no world `-0` under the builder's 0 deg transf (`checks.negativeZeros`; raw `-0` only in tangent x of ring entry 1 and in the island collider / model transf entry 5, both also in placements that built: 19/32, 1/32, 16/32), no overlaps, island clear, engine model clean (13/35 is even "judged": a probe verdict accepted that pattern). `junctionTransf` at 180 deg: (c, s) = (-1, 1.22e-16), rows (-1, 1.2e-16) / (-1.2e-16, -1): no `-0`, and `makeProposalData` with a script transf ignores `-0` anyway (docs/findings.md "Negative zero"). No assertion / Fatal line in stdout.txt near them. Common to 3 of 4: T or Y arms (built Y: only 22/32 and Group 1; no T built in this run) | **Retry**: showPlace gives a refused placement one more check: after "Construction Not Possible" `logic.showcaseRedraw` (same type, same `sqrb_arms` and arm road, reach within the planned one, a draw that differs; 40 tries) logs `refused by the check: Construction Not Possible; redrawn` with the refused params, then the new line `... [params] (redrawn)`; the dialog lists `<tag>: Construction Not Possible, then redrawn (the refused params are in the log)`. **To try in game**: each refused param set alone with the construction menu at 0 deg on a flat spot (Oval 4/32, Hamburger 30/32, Round Y 13/35 and G7 at 180 deg); if red there too, it is square_roundabouts' |
| G. Interchange line 11/17 Peanut (est 288 m) "Collision (hits 12 other)" | Not the neighbours: offline footprints 11/17 x +-230 m (1668-2128), y +-98 m; 10/17 Parclo two quadrants +-382 m (to 1402, measured 394 m); 12/17 Diamond was built after 11 (send order = line order), +-405 m from 2762 (from 2357). Ground faces / colliders lie inside the edges (the interchanges have no terrainAlignmentLists). 266 m clear on the west, 229 m on the east. The 12 entities are none of town building / street / track / construction (`collisionText`), so something at the spot itself, unknown (desert Blank Slate: asset groups? nodes?) | `collisionText` names an "other" entity by its first component of BASE_NODE, SUBCONSTRUCTION, ASSET_GROUP, FIELD, MODEL_INSTANCE_LIST, EDGE_OBJECT, BRIDGE, INDUSTRY, TOWN, ANIMAL, TERRAIN (`hits 12 other ASSET_GROUP e.g. #1234`; only the first 20 unknown entities of a list are probed, the rest count as plain `other`). **Retry**: a line placement refused with a Collision moves into the larger of its two gaps (`logic.showcaseNudge`: prev = the last built one's measured reach or town A's clearance, next = the next planned one's reach or town B's), at most `SHOW_NUDGE_MAX` 150 m, keeping `SHOW_MIN_GAP`, not under `SHOW_NUDGE_MIN` 20 m: `refused by the check: Collision (...); moved Nm along the line towards the previous one`; its links and the next placement's shift use the moved spot. Groups are not moved (their towns surround them) |
| H. Bus lines silently skipped: the build left -92.1M, `bus_lines_showcase stopped: balance -92.1M below 1M ...`, the dialog said nothing | runBatch (stress_buslines, shared by Auto bus lines and every test's Traffic) only logged its stop reason | runBatch's summary step shows a dialog when it stopped early: `Bus lines not added: the balance -92.1M is below 1M. Tick Keep balance (Game tab) or add money, then build the Showcase again: its bus lines cannot be added on their own later (Auto bus lines on the Traffic tab adds lines in the towns around the camera).` (title "<test> bus lines"; Auto bus lines: "... then press the button again."). Build with Traffic = Bus lines, costs on and Keep balance off: a dialog up front (`buslines.moneyWarning`), the build goes on |

Build step upvalues: +1 (`placeRetry`); still within the test's limit of 50.

## Showcase v2: groups only (user request 2026-10-12; implemented 2026-10-12)

User: the roundabout groups (one junction, a small town on every arm, groups not connected) work well. Do the same
for the highway interchanges and remove the long lines: on the 16 km lines the towns at the two ends are too far
apart, so residents don't drive across the map (user observation in game 2026-10-12; line traffic stayed local).
Goal: a small or medium town between every junction arm, many diverse configurations, including plain game
intersections (crossroads / T-junctions of ordinary streets, lights on and off, varied lane counts), to test
Roundabouts & Interchanges and Smart Lanes.

Plan: replace the interchange line and the roundabout line by groups; group types cycle through every interchange,
every roundabout and plain game crossroads / T-junctions; random params per placement (seeded); towns Small or Medium
(random, seeded) on every arm, close to the junction (ring radius from the measured reach + town clearance);
highway arms reach their town by a highway with the large-street merge piece; groups not connected; as many groups
as fit; bus lines across each group; zones for the traffic log at each group centre.
No options (user 2026-10-12): the Showcase section is one button. Bus lines always added; a fresh random seed per
press (logged, so a run can still be reproduced from the log); the build turns Keep balance on itself (logged) so the
bus lines are never skipped for money; everything else drawn from the seed.

### Why the lines went (record)

In game 2026-10-12 the lines' towns sat 16 km apart at the map's two ends: residents don't drive across the map, so
line traffic stayed local and the long lines tested little; the groups (a small town on every arm) did. v2 removes
the interchange line, the roundabout line and their code paths: line packing (`packLine`), line splits, moves along
a line (`showcaseShift`, `showcaseNudge`, `SHOW_NUDGE_*`, `SHOW_MIN_GAP`), arm-to-arm pair links between placements
and their bent routes (`showToArm`, `SHOW_BENDS`, `logic.bendPoint`, linkPairProposal's bend), the Size / Seed /
Lights / Traffic options (`jn.showUi`, `SHOWCASE_SEEDS`) and the Showcase's up-front money dialog. Kept:
linkPairProposal (straight, the Junction test's in-line stops), measured footprints, redraw after "Construction Not
Possible", the collision text, the busy guards and job names (`showcase`, `showcase_towns`, `showcase:settle`,
`showcase:relink`, `bus_lines_showcase`).

### Implementation (2026-10-12)

- One button (stress_hud showcaseItems): a description + Build showcase. `jn.buildShowcase(seed?)`: a fresh seed per
  press (`os.time` x 1000 + the session clock, 1..999999, logged in the first line); the argument (tests, reproducing a
  logged run) uses that seed. It sets `rt.keepBalance = true` (`[SQST] showcase keep_balance=on (was off|on)`), so the
  bus lines (always queued after the build, `TRAFFIC_DELAY_MS` later) are never skipped for money.
- Kinds in turn (`SHOWCASE_KINDS` ix, rb, plain), each cycling its own types: interchanges (Roundabout / Dumbbell /
  Peanut Interchange, Parclo, Parclo two quadrants, Diamond; cross road fixed Country large = `armKey sqrb_ix_cross`
  6, so the cross-road arms reach their towns on a large country road; highway arms as carriageway pairs + mergeEdge
  as the Junction test), roundabouts (as v1), plain game crossings: the Crossing test's construction
  (`square_stress_test_crossing.con`) as "Crossroads" (X) and "T-junction" with new params `sqst_x_angle` (side road
  at 90 / 60 / 75 / 105 / 120 deg: arms >= 60 deg apart), `sqst_x_main2` / `sqst_x_side2` (the second main / side
  arm's own road: lanes differ per arm; 1 = the same road). Roads 1-6 (town / country small / medium / large); the X
  side road one-way (7, 8) 1 time in 7 (both side arms one way through; its two towns then get no bus line,
  `showcaseOneWay`); a T's side arm is never one-way (its town would be a dead end one way). Lights per plain
  placement drawn: game AUTO or off (the game's NO proposal at its centre node after the read). Rotation 0-345 deg in
  15 deg steps. A kind stops after `SHOWCASE_MISSES` (3) draws in a row that fit nowhere.
- Towns: Small or Medium per town (`SHOWCASE_SIZES`, `SquareStressGridPoint.size`; towns.createGrid uses a point's own
  size for its capacity and wide grid). Superseded 2026-10-12: one fixed size per spec, Medium (section "One town size
  per Showcase"). Distance from the junction: reach estimate + 0.35 x its size's spacing + 100 m
  (`showcaseTownDists`), all of a group pushed out by one factor when two towns would come closer than their
  clearances together (arms 60 deg apart). A group keeps a circle R = farthest town + its clearance from the others,
  so towns of different groups keep the same distance as towns of one group. Placement: first fit, rows top to
  bottom (100 m steps), left to right, every twin of a set side by side 2 R apart (`fitSet`).
- Order: sets in kind turn, the twins of a set next in the list and built back to back; one settle; reads (zone
  line, built line, lights); one town link per arm (NODE_TRIES nodes; after a Collision the nearest node along the
  arm). Construction seed and redraw seed per set (`seed + set`), so the twins stay identical after a redraw. A
  set whose twins no longer match (only one redrawn, a redraw refused again, or a town skipped for want of land:
  createGrid `skipNoLand`, Showcase only) logs `match=no reason=redrawn|town` on every twin's zone line (FLOW.md
  "Showcase zones"); its siblings are not rebuilt. The layout adds a set only while its twins keep the groups
  within `SHOWCASE_MAX_GROUPS`.
- Summary: `[SQST] showcase summary ... interchanges=a/b roundabouts=a/b plain=a/b sl=a/b game=a/b sl_phases=a/b
  links= linked= unlinked=` and `logic.showcaseSummary` (window line, and the dialog's first line when something
  was refused).
- Bus routes (`showcaseRoutes`): across each ring (k with k + n/2), only arm pairs linked in every twin of the set,
  every set's first route first; a set's twins are added together or not at all under TEST_ROUTES_MAX (40).
- Layout numbers (Small / Medium, before "One town size per Showcase"; offline, 16 km map, 400 m margin): seed 1: 21 groups in 10 sets (8 ix, 8 rb, 5 plain; 10 sl, 10
  game, 1 sl_phases), 80 towns, 80 links; seed 777: 20 groups / 9 sets (6 / 6 / 8), 81 towns; seed 4242: 22 / 10
  (6 / 8 / 8), 87 towns. 12 x 9 km: 7-11 groups; 8 x 16 km: 10-12.
- Build step: 18 upvalues in the test's Lua 5.4 (limit 60; the test keeps it <= 50): the read, the arm matching
  and the summary moved to module functions taking the run's `ShowState`.

### Twins for A/B (user request 2026-10-12, coordinator; implemented 2026-10-12)

Every group is built once per A/B mode, side by side, with identical draws (type, params, rotation, lights, town
sizes; every town has the same GRID_SEED), not connected to each other: `logic.SHOWCASE_AB` (one table, easy to
change): `sl` (a, Smart Lanes lanes + current light behaviour), `game` (b, game default lanes and lights: Smart
Lanes must leave it alone), `sl_phases` (c, Smart Lanes lanes + Smart Lanes light phases; `litPlainOnly`: only a
plain crossing with lights). Groups are named "Group 3a", "3b", "3c" (set 3). Twins halve the distinct groups. The
zone lines carry `id=g3a pair=g3 ab=sl` (FLOW.md "Showcase zones"); `logic.showcaseZones(layout, cx, cy)` returns
the zone list with modes for the Stress Test -> Smart Lanes channel. ~~Not done here~~: done 2026-10-12, see
"Twin modes in Smart Lanes" below.

## In-game run 2026-10-12 #3 (seed 488838, Showcase v2) and the bus-line fixes

Archived as `2026-10-12_0905_top-up-488838` (`make logs-grep PAT='bus_lines_showcase'`). The Showcase built 21/21
groups and 80/80 links (zones acked); its bus lines then failed on the first 3 of 40 routes and the batch stopped
("3 failed towns in a row", ok=0, wastedStops=6). Per route (Grid S1 -> S3, S5 -> S7, S9 -> S10):

| Finding | Evidence | Fix |
|---|---|---|
| Every depot stub into the town grid refused "Construction Not Possible" (6 sends per ring, 12-18 per route), although the same split + stub to a new stand-in node pre-checked `ok` | `connect: success=false critical=true messages={Construction Not Possible} ... streetEdges at node 1->1`; the Simulation thread's proposal dump: segments `-1 9054 -4`, `-2 -4 9063`, `-3 -4 334946` (the depot's free node), no config for 334946. The stub was a copy of the split edge, the 8-lane `town_new_large` grid street, joined to the depot's 4-lane entrance street (`entrance_new`, lanes 3/5/5/3 m) at the entrance's existing node. Seed 204313 (Showcase v1, same grid) refused the same way; no script-built depot has ever connected on a town street | The stub is the small town street of the year (`town_new_small` / `town_old_small`: exactly the entrance street's lanes and style), and the gate node gets its full two-way config in the same proposal (D3, docs/findings/towns.md). Cause inferred (lane layout at an existing node), not proven: 6P item 1 records it |
| The one depot per route that connected (ring 700-1200 m, e.g. 83499 at -7113,7020) stood beside a Roundabout Interchange next to its highway ramp, with the red no-entry sign at its gate (user screenshot); `findBestDepotForLine=-1` | `getClosestTown` still named the town, so `townOnly` let the junction's arm / link road through. The gate joined (`streetEdges 1->2`) but a plain join keeps the node's old config: 0 lane connections (towns.md D1), the HUD's dead-end sign; buses can't leave the depot | Route lines build stops and depots only on their own town's grid (`logic.busEdgeReject`: no highway, no one-way, a `town_*` template, both ends within the grid half-size + 15 m, nothing within a junction zone's reach + 100 m); rejected counts logged per ring. A gate with 0 lane connections counts as not connected (depot removed); a failed line logs its depot's `gate node=.. streetEdges=.. laneConns=..` |
| The new depot near stop 1 (0-400, 400-900 m) failed the same way, so each route's line was destroyed with 2 stops wasted | as above | as above |
| 3 failed routes stopped all 40 | `stopped after 3 failed towns in a row` | Route batches go on and stop only after `MAX_ROUTE_FAILS` = 10 failed routes; Auto bus lines keep the 3-in-a-row stop |

Not changed: the depot still comes before the stops (it already did); the route through the junction is assumed
drivable for buses (highway templates carry BUS lanes; `findBestDepotForLine=-1` is explained by the dead-end gate).
If a route still fails with a gate showing `laneConns` > 0, check the group's type and twin (6P item 3).

### Node configs on the link roads (2026-10-12; not run in game yet)

Seed 204313's log (`2026-10-12_0525_showcase-204313-crash`) shows the links left their new nodes without
`BASE_NODE_CONFIG`: Smart Lanes skipped 37 link nodes `reason=no_config`, and the run crashed 16 s after the last link
with `Engine.h:323 GetComponentDataIndex` on a new entity's `BaseNodeConfig` while the bus lines worked on Grid S6 ->
S7, two towns with such nodes (correlation; docs/findings/roads.md "Script link roads without node configs"). Fix:
`gui/stress_nodecfg.tl` (shared with the bus-line stops / depot gates, the locked wide grid and probe 4): every node
a link adds gets the engine pattern from its segments' lanes and directions (a replaced node keeps its old config
re-pointed at the copies, plus the link piece), an empty one with one edge; offline tests check every link's
proposal shape (`test_nodecfg.lua`, `cfgProblems` in test_junctions / test_showcase). Test: TESTING.md 6Q.

### Twin modes in Smart Lanes (zones channel, 2026-10-12; not run in game yet)

- Stress Test `gui/stress_slzones.tl`: `buildShowcase` sends `logic.slZonesPayload(showcaseZones(...))` (r = reach
  estimate + `SL_ZONE_PAD` 20 m, at most 400 zones, run id `s<seed>-<os.time>-<n>`) with
  `api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones", payload))`
  right after the layout, before `towns.createGrid`. The build job's first task (`zones`) waits for the
  acknowledgement: Smart Lanes' saved `zrun` read through its GAME_SCRIPT component (`getEntityForGameScript
  "square_smart_lanes::/smart_lanes/sl_lanes.gs"`, `state_native:find("zrun")`, the radar HUD's pattern), polled every
  250 ms, at most 5 s; only tried when `getModParams()` lists square_smart_lanes (so an unknown script name is never
  asked for). Without Smart Lanes: no wait (`ack=absent`), the event has no subscriber.
- Why this channel: the only cross-Lua-state path into Smart Lanes' engine state with an existing pattern in the repo
  (square_problem_radar's GUI events; base `subventions_gui.tl:135`); `fireGuiScriptEvent` reaches only GUI-side
  handlers and its result across states is unprobed (FLOW_PLAN open question 7); a shared module or `ug_require`
  between the mods is ruled out (either may be absent). Saved subscriptions are the known trap (findings
  "Game-script event subscriptions are saved"): Smart Lanes now re-subscribes once per load.
- Race bound: the zones event is queued before any build command, the engine runs commands in order, and Smart
  Lanes' GUI reads the zones from the same `state:get()` that hands it the build's job. The ack wait adds a hard
  guarantee independent of the command order (the towns take minutes, so it normally costs nothing). After a
  timeout (an older Smart Lanes, a paused game) the build goes on and the log says `ack=timeout`.
- Clear: Remove all roads, Remove towns > Grid towns / All towns send `op=clear` (the Showcase's junctions or towns
  are gone; a later Showcase sends its own set anyway). Remove the nearest town keeps the zones.
- Test: TESTING.md 6O.

## Lights showcase (user request 2026-10-12, queued after the traffic log sampler)
A second one-button test, "Lights showcase": only LIT plain intersections (crossroads and T-junctions; varied lane
counts per arm 1-3 each way, angles, turn-lane layouts; lights forced on), each built as 4 side-by-side twins with
identical draws: ab = game | sl | sl_phases | sl_fan (sl_fan: Smart Lanes full-fan lanes + split phases, user's
hand-made pattern, measured not default). Denser towns for heavy traffic: Medium or Large, then grown several passes
after creation (Towns > Grow's build-out passes). Bus lines through every twin; zones sent to Smart Lanes before
building (same channel); zone lines for the traffic log; summary per mode. Reuses Showcase v2 code (twins, zones,
towns, links, node configs, bus lines) with a different group-type table and town sizes.

Status: implemented 2026-10-12 (rev 2, unreleased), not run in game yet: TESTING.md 6S. One shape per press, one
size command (x3 since 2026-10-13, about 1000 people per town: "Growth for ~1000 people per town" below), no bus lines
and batched building since: section "Faster, simpler Lights showcase + batched building" (TESTING.md 6U).

### Implementation (2026-10-12)

- **One shared code path, two specs** (stress_logic `SquareStressShowcaseSpec`): `SHOWCASE_SPEC` (v2, its nil fields
  read SHOWCASE_KINDS / showcaseTypes / SHOWCASE_AB / SHOWCASE_SIZES / SHOWCASE_TOWN_R at call time, so v2 is
  unchanged: same layouts for the same seed, tested) and `LIGHTS_SPEC` (kind slots `x`, `t`; types
  `LIGHTS_X_TYPES` / `LIGHTS_T_TYPES`; modes `LIGHTS_AB`; sizes `LIGHTS_SIZES` = Medium, Large (since replaced by
  `size` = `LIGHTS_SIZE`, Medium: section "One town size per Showcase"); `litOnly`;
  `growFactor` / `growPasses`; misses 6). `showcaseLayout`, `showcaseModes`, `showcaseCounts`, `showcaseRedraw`,
  `showcaseSummary` take the spec (optional, default v2); groups carry `slot` (their kind slot; `kind` stays "plain"
  so zone lines, gaps and the traffic log treat them as plain crossings). stress_junctions `buildRun(spec, seed)` is
  the old buildShowcase (ShowState.spec; job / log names from `spec.id`: `lights_showcase`, `lights_showcase_towns`,
  `lights_showcase:settle|relink|traffic`, `lights_showcase_grow`, `bus_lines_lights_showcase`, all in rt.TEST_JOBS).
  The zone lines and the zones-sent line keep their `[SQST] showcase zone` / `showcase zones sent` text, so
  tools/flow_report.py reads both variants.
- **Types**: crossroads (`lit_crossroads`, shape 1) and T-junctions (`lit_t_junction`, shape 2) in turn; angle 1-5
  (90 / 60 / 75 / 105 / 120 deg), main / side road 1-6 (two-way town / country small, medium, large = 1-3 lanes each
  way), main2 / side2 1-7 (same road, or ROADS 1-6: lanes differ per arm). Since run #4 (section "In-game run
  2026-10-12 #4"): 90 deg only, country roads 4-6 only, the square layout. No one-way arms, so every arm pair gets
  its bus line. Not done: turn-lane layouts (our crossing has none; Smart Lanes' modes are the lane variants).
- **Lights**: new crossing param `sqst_x_lights` (Traffic light: Game decides / Yes); Yes lists the centre node's
  entries in `trafficLightYes` and `trafficLightNodePreference` {{i, "YES"}} of every edge list (the fields
  square_roundabouts' signals use; its Showcase v1 log `2026-10-12_0525_showcase-204313-crash` has 20 `[SQRL] LIGHTS
  ... before=yes light=true` lines after placements with `sqrb_signals=2`, so inferred: one of the fields sets the
  preference; which one is still open). The game's AUTO lights start in 1950 (`trafficLightYearFrom`); whether Yes
  lights a node before 1950 is unknown, so before 1950 a dialog warns up front (`lights_showcase year=Y before 1950`)
  and the build goes on. At each read the junction node is checked (`lit=<node>:pref=..,light=..`: lit = preference
  YES or a BASE_NODE_TRAFFIC_LIGHT component, Smart Lanes' rule); a node without a light gets Yes then
  (`createTrafficLightProposal(node, config:clone(), YES)`, the clone read at that moment so its phases match the
  node's lane connections, as the Showcase's lights-off proposal; `lights forced on at N`, listed in the dialog). In
  every twin alike, the game twin b included: intended (a lit game default is the baseline; from 1950 the game's AUTO would light such a crossing too, so b stays the game's own lanes and default phases, not an unlit junction). A refused light proposal (e.g. a Smart Lanes change still pending on the node) is not retried; it is logged `<name>: lights on at node N refused` and that twin may stay dark (the log shows it; the dialog only lists the forced placement). Open (TESTING.md 6S step 4): whether Smart Lanes re-plans c / d after such a late light.
- **Twins**: `LIGHTS_AB` sl a, game b, sl_phases c, **sl_lock d** since 2026-10-13 (user: replaces sl_fan; Smart
  Lanes' `sl_lock`: its lanes, the game's phases, the curb turn always locked; sl_lock vs game = the lane layout
  alone, sl vs sl_lock = the free curb turn alone; litPlainOnly c / d: always met), built in letter order
  (stress_flow's fallback twin ids follow it: TWIN_ORDER sl_lock 5, letter d); `SL_ZONE_AB` and `slZonesByAb` know
  sl_fan and sl_lock (`,sl_fan:N`, then `,sl_lock:N`, each only when N > 0, as Smart Lanes' `byAbText`); the payload
  passes Smart Lanes' `sl_zones.lua` validator (test). sl_fan (the fourth twin until 2026-10-13) stays accepted
  everywhere (old saves, Smart Lanes, flow_report).
- **Towns** (superseded: all Medium, section "One town size per Showcase"): Medium or Large per arm (seeded), clearance 0.35 x spacing + 100 m as v2 (Large: 800 m). After the
  links (`showSummary`, only when something was built) every live town of the run grows with the Grow machinery:
  `towns.grow(5, 3, list, "lights_showcase_grow")` (the Grow UI's x5 and 3 passes, `LIGHTS_GROW_FACTOR` /
  `LIGHTS_GROW_PASSES`; towns.grow now takes an optional town list and job name), logged `lights_showcase grow queued
  towns=N factor=x5 passes=3`. Serial job, queued before the bus lines (which come TRAFFIC_DELAY_MS later and wait
  for it), so their stops go onto the grown grid. Growth beyond the clearance is not bounded: watch in game.
  Superseded the same day: both Showcases lock their towns' streets and grow x10 with shifted building levels
  through `towns.densify` (section "Town growth locked into the grid").
- **Layout numbers** (Medium / Large, superseded by "One town size per Showcase"; offline, 16 km map, 400 m margin): every seed tried (1, 12, 99, 777, 4242, 31337) gives 4 sets
  = 16 twins (4 per mode), 56-60 towns (seed 4242: 12 crossroads + 4 T, 60 towns; seed 1: 8 + 8, 56 towns, 40
  Large); one set per row (a set of 4 needs ~13-15 km of width). 20 km: 5 sets; 16 x 8 km: 2; 14 km: 0-4 by seed;
  12 x 9 km or taller-than-wide maps: none ("Nothing fits" dialog). Bus routes: 2 per twin (crossroads: both
  through pairs; T: 1-2 and 2-3), 32 for 4 sets (cap 40).
- **Traffic log**: no change needed: it restarts when slzones.current changes and no test job runs (now including the
  growth and the Lights showcase's bus lines). tools/flow_report.py compares sl_fan with game and with sl_phases.
- Build step upvalues: 16 in the test's Lua 5.4 (the run's values moved into ShowState: `s.name`, `s.seed`,
  `s.layout`, `s.spec`).
- Tests: test_showcase.lua (lights types / construction fields / layout / zones / redraw / summary; the build with
  the fake api: lit-only constructions, identical twins, sl_fan zones validated, links, growth after the links and
  before the bus lines, forced lights, the pre-1950 dialog, busy guards, upvalues), test_towns.lua (grow a given
  list), test_flow.lua (restart on a Lights showcase, sl_fan sampled), test_hud.lua (one-button form),
  tests/tools/test_flow_report.py (sl_fan pairs).

## Town growth locked into the grid (user request 2026-10-12; implemented 2026-10-12)

Request (screenshot): a Showcase town's wide grid had a dense core, but the town also grew streets and houses
outside the grid, which changes how traffic reaches the junction's cells. Wanted: growth locked into the grid, very
dense in the centre, nothing outside. Both specs (`SHOWCASE_SPEC`, `LIGHTS_SPEC`) now set `lockStreets = true`,
`denseWeights = DENSE_WEIGHTS`, `growFactor = 10`, `growPasses = 3`.

Status: offline-tested only (test_towns_lock.lua, test_towns_logic.lua, test_showcase.lua); TESTING.md 6T.

### Basis (docs/findings/towns.md)

- `BaseEdge.roadDevelopmentLocked` ("prevent towns from updating or extending this road") on the edge a street
  proposal carries. Showcase v5 (Organic Towns): locked edges stayed locked; the town still built houses on them but
  attached 0-1 vanilla streets in 10 steps vs 33 on unlocked twins. Freezing the town changed nothing, so the lock,
  not development off, is the tool.
- Never take town street templates away (crash); `makeTownDevelopAtCmd` rebases the town's capacities (not used).

### Which streets get locked, when

| When | What | How |
| --- | --- | --- |
| Grid build (per town, before the town) | the wide grid's streets incl. its 4 corner stubs | `createGrid` streets = 3 ("Wide grid, locked"): `lockGrid` -> `lockEdges` |
| After all towns exist, before any junction | the town's own seed streets (makeTownCreateCmd) and anything else unlocked | `towns.lockTowns("<id>_lock", areas, {pass = "towns"})`, serial, queued before the build job |
| Link roads | every edge the link proposal adds (link pieces, the arm-end copies, the town node's copies) | `linkProposal(..., lock)`: `Builder.lock` -> `roadDevelopmentLocked = true` in `assemble`; the Junction test's links stay unlocked |
| After the links | anything unlocked again (town growth meanwhile) + the corner stubs no link uses removed | `towns.lockTowns(.., {pass = "links", stubs = true})` |
| After each growth pass, and a final check | every unlocked street of the town (leak check) | `towns.densify` -> `leakCheck` |

A town's streets: street edges within half x sqrt 2 + `LOCK_REACH` (300 m) of the grid centre whose closest town
(`api.engine.util.town.getClosestTown`, edge midpoint) is it, not in a construction (junctions); positions from the
nodes. Edges with edge objects (stops) are never swapped (their object would not follow the copy). At most
`LOCK_MAX_PASS` (400) per town and pass, in batches of `LOCK_BATCH` (100), one proposal in flight, each batch built
from fresh reads when it is sent (the previous batch swapped its neighbours), a refused batch rebuilt and sent once
more `LOCK_RETRY_MS` (3 s) later (pending-light refusal, roads.md), refused twice: counted `failed`, left unlocked.

Node configs (roads.md "Script link roads without node configs"): the lock swaps edges, the nodes stay: every node
with a config gets it re-pointed at the copies (`rt.nodeConfigEntry`, remove + add; nothing dropped, so the light
phases' indices stay as they were), a node without one gets a fresh one (`nc.complete`), never a remove on a node
without a config. Tested with `nc.problems` on every proposal.

### Corner stubs

The grid construction leaves a 60 m diagonal dead-end stub at each corner (for the Junction test's links). A link
joins a stub's end (its node then has two edges); the others lead nowhere and would carry houses outside the grid.
`logic.stubOuterEnd` finds them (one end on a grid corner within 3 m, the other diagonally outside); the second lock
pass removes those whose outer node still has one edge and belongs to no construction: one proposal per town, the
stubs in `edgesToRemove`, their dead ends in `nodesToRemove`, the corner nodes' configs without the stub (remove +
add) only where the corner has a config. Same shape as Remove all roads (stress_roads.tl, in game). They are locked
already (pass 1), so a refused removal only leaves a locked stub (`stubs_kept=` on the summary).

### Density

- `makeTownCustomDistributionWeightsCmd(town, weights)` (cmd.d.tl:845-850, data record cmd.d.tl:369-374: three
  rows of four numbers): the town editor's custom distribution weights (base town_eow.script.tl:660-812: per land
  use (residential, commercial, industrial) one slider 0..100 % per level 1-4, never all 0; its default comes from
  `computeWeightedTargetTownBuildingCapacityPerType`, normalised to max 1). We send `{0, 0.1, 0.5, 1}` for all three
  (`DENSE_WEIGHTS`, `logic.denseWeights`): no level 1, mostly level 4. Read back on `Town.levelToCapacityDistributionWeights`
  (`read_back=` on the detail line).
- Then `makeTownUpdateSizeCmd` x10 (pass 1 multiplies the size factors, passes 2-3 re-send them; a pass adding fewer
  than `MIN_PASS_GAIN` buildings ends that town's build-out), the Grow tab's own machinery (`logic.growPlan`).
- The densest part is the grid's centre by itself (the town centre is the grid centre); the log shows it:
  `levels 1:a 2:b 3:c 4:d centre 1:.. 4:..` (centre = the grid's central half).

### Log lines (stdout.txt)

- `[SQST] <id>_lock town <name> lock pass=towns|links edges=N unlocked=U inside=I outside_streets=O locked=L refused=R
  failed=F batches=B objects=X left=Y stubs=S removed=Z`, then `[SQST] <id>_lock summary pass=.. towns=.. locked=..
  failed=.. stubs_removed=.. stubs_kept=.. outside_streets=..`.
- `[SQST] <id> grow queued towns=N factor=x10 passes=3 weights={0,0.1,0.5,1} locked=true`, `[SQST] <id>_grow queued
  ...`, per pass a detail line `town <name> pass p/3 ... buildings a->b`, then the leak line `[SQST] <id>_grow town
  <name> outside_streets=N houses_outside=M pass=p/3 buildings=B inside_new=I locked=L failed=F locked_outside=K`
  (outside = beyond the grid + `LOCK_MARGIN` 20 m for streets, + `HOUSE_MARGIN` 45 m for houses; `outside_streets`
  counts unlocked ones: streets grown since the last lock; `locked_outside` ours: links, kept stubs), the final
  `... final buildings=B ...` and `town <name> levels ... centre ... buildings=B`, and `[SQST] <id>_grow dense summary
  towns=N factor=x10 passes=3 weights=.. sent=.. stoppedEarly=.. buildings a->b outside_streets=.. houses_outside=..
  locked=.. levels ..`.

### Test grid "Wide grid, locked"

Unchanged in what it locks and when (the grid right after its build, before the town). Changed only in how: via
`lockEdges` (batches of 100, each retried once) instead of one proposal of every grid edge; a Large grid (~224 edges)
is now 3 proposals. A strict improvement (smaller proposals, a pending-light refusal retried), so the Test grid uses
it too. The Test grid does not lock the town's own streets or grow densely (no request for it).

### Open in game

- Does `makeTownCustomDistributionWeightsCmd` from a GUI script take (read back) and shift the levels (the `levels`
  lines vs a Showcase before this change)? Era: are level 4 buildings available in the save's year?
- Do the towns stay inside: `outside_streets=0` on every final leak line, `houses_outside` small (houses on the
  outer streets' outward side are counted only beyond 45 m)? Does a town fill its grid at x10 or stall
  (`stoppedEarly`)?
- Does `getClosestTown` assign a link road between a town and its junction to the right town (only matters for
  `locked_outside`)? Does any lock batch get refused (`refused=`), and are the junction approaches still fine after
  the second lock pass re-points the link nodes' configs (Smart Lanes `no_config` must not appear)?
- Stub removal: accepted (`removed=`), and no red dead-end sign left at the corners.

## In-game run 2026-10-12 #4 (Lights showcase seed 718344) and the fixes: square layout, country links, zone lock

Log: `.cache/logs/2026-10-12_1847_top-up-718344.log.gz` (`uv run tools/game_logs.py path 718344`), user screenshots.
Status: implemented 2026-10-12 (rev 2, unreleased), offline-tested; not run in game yet (TESTING.md 6S, 6T).

### What the log shows

- **Wrong town.** Group 1a at -6661,6661: towns S1 west (-7792,6661, Large), S2 south, S3 east (-5752,6661, Medium,
  600 m grid), S4 north (-6661,7792, Large). The log only says `Group 1a Crossroads -> Grid S4 linked` (link lines named
  the arm's town, never the node). Cause in our code: the town's candidates were every free street node within
  `townR` = spacing x 0.5 (Large: 1000 m) of its centre, any town's, dead ends first (the corner stub tips). S3's NW
  stub tip (about -6094,7003) lies ~970 m from S4's centre (inside that circle) and ~630 m from the north arm's end
  (-6661,6733), S4's own nearest stub tips (its south corners, about -6661+-442,7350) ~760 m, so the north link went
  to the EAST town's corner and S4 got nothing of its own (the screenshot). No
  `not linked` line: the link succeeded, to the wrong town.
- **Collisions** (`Group 1b -> Grid S7` and `Group 1d -> Grid S15`, twins a / c of the same arm linked fine): no
  entity kinds were logged (link refusals logged only the messages). The refused proposal (log lines after
  18:52:42 `Data error: Collision`) replaced node 56871, the tip of a corner stub (its corner 56796 had two grid
  edges + the stub), with 7 new pieces of at most 200 m: a 1.2-1.4 km link, though S7's near corner stubs lie
  ~0.5 km from the east arm's end. Inferred: the north link (S8) had taken S7's near corner as in 1a (wrong town),
  and the avoid list pushed S7's link to a far stub of its own grid, a long diagonal across its own grid / the other
  link; the retry ("nearest town node, 60 m along the arm first") collided too, then "no town street node left,
  candidates=2". So our own geometry, not terrain or buildings. Gone with the square layout (straight axis links
  to the own side's middle). Refused links now log what they hit (`(hits N streets, ...)`, collisionText on the
  result's proposal data).
- **Houses along the links and outside the ring.** Link pieces were copies of the arm's edge, i.e. town streets
  (`town_new_*`); locked town streets still get houses (docs/findings/towns.md), so x10 growth lined the links with
  high-rises, and the grid's perimeter street got houses on its outer side.
- **Streets around a crossing** (screenshot near Grid S7, twin 1b): the town built a block of vanilla streets between
  its grid and the crossing, hung on the crossing's arms. The crossing construction dissolves into free, unlocked
  streets after the build (probe 11g); the arm whose link failed (S7) was never locked (linked arms were: the link
  copies the arm edge locked), and no lock pass looked that far from a town (corners + 300 m) or at edges whose
  closest town was another.

### Fixes

- **Square layout** (`LIGHTS_SPEC.square`, user decision): crossings at 90 deg only (`sqst_x_angle` fixed 1, no longer
  drawn; lane variety kept), never turned (rotation 0); every town exactly on its arm's axis (`logic.axisUnit`: no
  6e-17 from cos 90), all towns of a group at one distance (the farthest one `showcaseTownDists` asked for, rounded
  up, so two Large towns at 90 deg still clear each other); twins in rows of 4, 2 R apart as before (no town of one
  twin near the next). Showcase v2 unchanged (its layouts for a seed are the same, tested).
- **Links to the middle of the facing side.** The street grid now always has an even number of blocks
  (stress_grid_streets `grid.lines`: Medium 8 x 75 m and Large 10 x 80 m as before; Small 6 x 66.7 m instead of
  5 x 80 m), so a central street runs both ways and every side has a node at its middle (3 edges). A square-layout
  link is one straight road along the arm's axis to that node (`logic.sideCentre`, `logic.nodeAt` within 15 m); no
  other target, no bend, no "nearest node" fallback: a refused link is sent again as is (3 tries), then the arm
  stays unlinked.
- **A link always ends on its own town** (both Showcases): candidates are only nodes inside the arm's town's grid
  square + `OWN_TOWN_MARGIN` 50 m (its corner stubs reach 42 m out; `logic.ownTownNodes`), and the chosen node is
  checked again (`notOwnTown`: in the square, and `getClosestTown` of its spot is the arm's town when the game names
  one). Otherwise the arm stays unlinked with the reason in `not linked (...)`. Never another town's node.
- **Unlinked arm -> match=no reason=link**: the set's zone lines were written at the read, so after the links every
  built twin of a set with an unlinked arm gets `[SQST] showcase zone_match id=g1b pair=g1 match=no reason=link`
  (FLOW.md; tools/flow_report.py applies it to that zone), and `sets_mismatch=` counts it.
- **Link roads are country roads.** Every new piece between the arm and the town node is the base country road of
  the arm's lanes (`logic.countryTemplate`: 2 / 4 / 6 road lanes -> `country_{new,old}_{small,medium,large}`, new
  from 1940; a highway pair's merge piece `country_*_large`), locked. Only the copies of the existing edges at the
  two joined nodes keep their own type. Evidence that country roads get no houses: the wiki (modding/infrastructure/
  tracksstreets.md:170) "`country` ... If set to `true`, no houses will spawn along streets of this type", and every
  base `country_*.street_template.lua` has `country = true` (town_* have no such field); same lane layout as the town
  templates (2 sidewalk lanes + 2 / 4 / 6 CAR lanes, `simBuildable = true`). Not yet seen in game: TESTING.md 6T.
- **Lights showcase crossings are country roads too** (main / side 4-6 = country small / medium / large, main2 / side2
  1 or 5-7): lanes per arm still 1-3 each way, but the town never lines the junction's own 60 m arms. Smart Lanes and
  the lights treat them like any street (country_new_medium has the same lanes as town_new_medium).
- **Country ring** (decided): the locked grids of both Showcases (and the Test grid's "Wide grid, locked") get their
  outer ring (perimeter streets + corner stubs) as `country_{new,old}_large` (construction param `sqst_grid_ring` 2:
  a second edge list), the inner streets stay `town_*_large`. Why: the outward parcels of the perimeter were the
  houses outside the grid; the town is created at the grid centre and develops along the inner town streets (Organic
  Towns: houses come from the core outwards), the outermost blocks keep houses on their inner streets' sides, and no
  finding says a town needs its outer street (the template crash was about removing small templates from town
  development, not about street types in place). Leak lines count houses just outside the perimeter separately
  (`houses_perimeter=`, between the outer street and HOUSE_MARGIN 45 m; `houses_outside=` stays beyond 45 m): with
  the country ring both should be ~0. If the town visibly stalls at the edge in game, set `sqst_grid_ring` back to 1.
- **Zone lock.** Every town's lock area carries its junction's zone (centre, measured reach) and is scanned out to
  its junction: every street within the zone + `ZONE_LOCK_MARGIN` 150 m is locked in the "links" lock pass and in
  every leak check, whatever its closest town (`zone_streets=` on the lock and leak lines: unlocked ones found). The
  crossing's own arms (an unlinked one included) and anything a town hung on them are locked each pass.
- Node configs: every new node of a link still gets one (stress_nodecfg via `assemble`); the lock passes re-point
  configs as before; lock flags are copied on every link edge.

## Faster, simpler Lights showcase + batched building (user approved 2026-10-12, queued after the link fix)
Evidence (Lights showcase seed 718344): towns 247.5 s for 60 (~4 s each: createTowns ~1.1 s, grid ~0.5 s, lock
~0.6 s + waits), links 46 s, locks 27 s, growth x10 3 passes ~3-4 min adding only +0..+12 buildings per town per
pass (towns densify later while the game runs), bus lines: all 10 routes failed (every depot spot collided with
buildings in the built-up grids).
1. Lights showcase: ONE junction shape per press repeated in all sets (cycle per press: 2x2 X, 3x3 X, 3x2 X, T);
   drop the build-out passes (keep x10 size + tall-building weights); drop bus lines; keep 4 modes x 4 sets.
2. Batch in both Showcases: one makeTownCreateCmd with all towns (cmd.d.tl:831 takes a list); grid constructions
   several per proposal; lock batches of 100 edges across towns; non-touching links grouped per proposal; every
   batch falls back to one-by-one on refusal and logs the failing piece.
3. Main Showcase bus lines: build depots before towns grow (or reserve a depot lot per town).
Target: ~2 min per Lights showcase build (was 10-15).

Status: implemented 2026-10-12 (rev 2, unreleased), offline-tested; not run in game yet (TESTING.md 6U).

### Implementation (2026-10-12)

- **One shape per press** (`logic.LIGHTS_SHAPES`, `logic.lightsSpec(k)`): each spec has ONE slot (`x` crossroads or
  `t` T-junctions) with ONE type and no drawn ranges, so every set is the same junction. Shapes (lanes per direction ->
  stress_crossing.ROADS; 2 = Country medium (5), 3 = Country large (6); main2 / side2 1 = the same road on both arms;
  angle 1 = 90 deg; lights 2 = Yes):

  | Shape | sqst_x_shape | main | side |
  | --- | --- | --- | --- |
  | 2x2 X | 1 (X) | 5 | 5 |
  | 3x3 X | 1 | 6 | 6 |
  | 3x2 X (main 3 each way, side 2) | 1 | 6 | 5 |
  | T 2x2 | 2 (T) | 5 | 5 |

  `jn.lightsShape` (session counter, starts at 1) picks the shape and advances only when a run starts (a busy or
  "nothing fits" press keeps it); the button reads "Build lights showcase (<next shape>)"; the run's first log line
  ends in `shape=k/4 (<label>) bus_lines=no`. `jn.buildLightsShowcase(seed, shape)` builds a given shape (tests,
  reproduction) without moving the counter. `LIGHTS_SPEC` = `lightsSpec(1)`. A refused crossing gets no redraw (nothing
  to vary).
- **Growth**: `LIGHTS_GROW_PASSES = 1`: weights (DENSE_WEIGHTS) and one size command per town after the links
  (`LIGHTS_GROW_FACTOR`, x3 since 2026-10-13; was x10);
  `towns.densify` with one pass skips the per-pass leak check (the final check does it). The Showcase keeps 3 passes.
- **No bus lines** (`spec.noBusLines`): no routes, no depots, no `bus_lines_lights_showcase` job; the summary says
  "no bus lines (the towns' own traffic)".
- **Batched building** (`towns.createGrid` opts.batch; both Showcases, the Junction test and the Crossing test; the
  Test grid stays one town at a time): steps setup, grid batches, lock, towns.
  - Grids: `GRID_BATCH` (10) street grid constructions per proposal; a refused proposal is sent again one grid per
    proposal (`street grids batch c/n (N grids) refused ...; sent again one by one`, then the refused grid's own
    `street grid refused` line).
  - Grid locks: 1 s after the last grid batch, every built grid's new street edges (minus each grid's `before` set,
    read when its batch was sent) in ONE `lockEdges` run: LOCK_BATCH (100) per proposal across towns
    (`street grids locked grids= edges= locked= batches= refused= failed=`).
  - Towns: ONE `createTowns` call with every point and ONE `makeTownCreateCmd` with all TownInfos (cmd.d.tl:831).
    TownInfos are matched to their points by position (`logic.matchNearest`, list order when they can't be); the new
    towns (town list diff, a second look 1 s later) are mapped back to the points by their real positions (nearest
    within `TOWN_MATCH_MAX` 600 m, leftovers to leftover points only when that point is the town's nearest: `far=`;
    else the town is a stray, logged `is not in <point>'s grid`, and its point counts as missing: `stray=`). A town
    found is used even when the command reported failure (never created twice). Per town the old detail line (with
    `batch=N (position|list order)`), then `towns batch: one command for N towns success= ms= new= matched= missing=
    far= stray=`. Missing towns (or createTowns giving fewer than asked, or a refused command) are created one by one with
    the old per-town code (`createOne`). The job's serial wait is `BATCH_TIMEOUT_MS` (10 min) per step.
  - `onDone` gets a fourth argument: `{towns, grids, locks}` ms (batch; one by one: everything under towns), also on
    the summary line (`batched towns_ms= grids_ms= locks_ms=`).
- **Lock passes across towns** (`towns.lockTowns`, one serial step): every town scanned, every town's unlocked
  streets (LOCK_MAX_PASS each) locked together in LOCK_BATCH proposals (`lockEdges` with an owner map: per-town
  locked / failed / refused / batches), then every town's unused stubs in ONE removal (refused: one per town). The
  per-town lines and the summary keep their format (summary adds `edges= batches= ms=`); `opts.onDone(ms)`.
- **Link groups** (both Showcases): at the first link step, `planLinkGroups` groups every link task
  (`logic.groupLinks`: footprints = arm end -> town centre, widened by the town's grid half x 1.42 + 60 m; groups of up
  to `LINK_GROUP_MAX` 8 whose footprints stay `LINK_GROUP_GAP` 200 m apart; greedy in task order). A group's first
  task sends ONE proposal: each member's first try (`showToTown` now returns a `Builder`; `linkBuilder` /
  `mergeBuilders` renumber the new nodes and pieces after each other, refuse two links touching one existing node or
  edge) assembled once, so node configs come from the same `assemble` / `nc.complete` path as a single link.
  Accepted: every member logs `linked ms=.. (one proposal of N links)`, its own step only finishes. Refused (or a
  member not made / merged): `link group of N refused (<error> (hits ...)); one by one: <tags>`, every member's
  `tried` reset and each sent alone in its own step with the old retries (its own refusal logs its hits). Settle
  rule unchanged: the links still come after the one settle and the reads.
- **Main Showcase depots before growth** (`buslines.prebuildDepots`, job `showcase_depots`, queued after the links'
  lock pass and before the growth): per distinct route town (`r.a`, its network) the line's own `findDepot` (our
  depots of that network, else DEPOT_RINGS on its own town's streets, out of the junction zones); each depot marked
  with the route's network, so the line built after the growth reuses it (`ourDepotNear`). Chosen over reserving a lot
  per town (empty blocks would need the lock and the growth to keep them free; this reuses tested code). Lines
  `showcase_depots <route> depot=D (how)` / `: no depot (...)`, summary `towns= depots= failed= ms=`.
- **Timing**: `[SQST] <id> timing towns= grids= locks= junctions= links= depots= density= total=..ms (X.X min)` once the
  summary is out and every timed job (lock passes, depots, growth: their `onDone(ms)`) is through, then `[SQST] <id>
  finished in X.X min (seed N)`. junctions = from the zones wait to the first link; links = to the summary. The
  summary line gets `minutes=` and its sentence " Built in X.X min (the growth follows)."
- Upvalues: the Lights showcase build step 21 (Lua 5.4 test count, +1 for _ENV).
- Tests: test_showcase.lua (shapes, layouts per shape, no redraw, summary, batch helpers, Lights build with link groups
  / no bus lines / timing, shape cycling, a refused link group falling back, depots before growth), test_towns.lua
  (batched createGrid: grid batches, one create mapped back by position, fallbacks, cross-town grid lock),
  test_towns_lock.lua (lock passes across towns, shared stub removal and its fallback, one-pass densify),
  test_towns_logic.lua, test_hud.lua.

## One town size per Showcase (user decision 2026-10-12)
Town size must be consistent in every Showcase that spawns towns around junctions: no per-town random size. First
decided Lights showcase all Large (10 x 10 blocks) and the main Showcase all Medium; changed the same day to **Medium
(8 x 8 blocks, 600 m grid) in both**, the Lights showcase getting more people from **density** instead of a bigger
grid.

Status: implemented 2026-10-12 (rev 2, unreleased), offline-tested; not run in game yet (TESTING.md 6U steps 3, 6).

- **One size per spec** (stress_logic): `SquareStressShowcaseSpec.size` (one TOWN_SIZES index, nil = `SHOWCASE_SIZE`)
  replaces `sizes`; `SHOWCASE_SIZE = 2` and `LIGHTS_SIZE = 2` (Medium) replace `SHOWCASE_SIZES` {Small, Medium} and
  `LIGHTS_SIZES` {Medium, Large}; `logic.specSize` / `logic.specSizeText` ("Medium", on the first log line:
  `towns=N (Medium)`) replace `specSizes` / `specSizesText`. `drawGroup` gives every town the spec's size.
- **RNG stream changed**: the size draws are gone (one `rngInt` per town no longer spent), so every later draw of a
  seed (params, rotation, lights) differs from earlier runs: a seed logged before this change no longer rebuilds the
  same layout. Layouts stay reproducible for a given seed from now on (tested: same seed, same layout).
- **Square layout distances**: unchanged code; with one size every town of a group asks the same distance
  (`showcaseTownDists`: reach + 1500 x 0.35 + 100 m; a lit crossing: 88 + 525 + 100 = 713 m), R = 713 + 625 = 1338 m.
- **Density instead of area** (Lights showcase): one size command, DENSE_WEIGHTS {0, 0.1, 0.5, 1} (tall buildings),
  every street locked (the town can only build up, never out); the factor is x3 for about 1000 people per town
  ("Growth for ~1000 people per town" below). The x25 plan of 2026-10-12 is superseded (HISTORY.md). The Showcase
  keeps x10 in 3 passes. More people per building without any growth: the load setting "Town building capacity"
  x2 / x4 (experimental; TESTING.md 6U).
- **Layout numbers** (offline, 400 m margin, seeds 1, 12, 777, 4242, 31337):

  | Map | Showcase sets / towns | Lights showcase sets (X towns / T towns) |
  | --- | --- | --- |
  | 16 x 16 km | 9-10 / 71-86 | 6 (96 / 72) |
  | 20 x 20 km | 14-17 / 120-143 | 7 (112 / 84) |
  | 14 x 14 km | 7-9 / 55-74 | 5 (80 / 60) |
  | 16 x 8 km | 3-6 / 26-46 | 3 (48 / 36) |
  | 12 x 9 km | 3-5 / 30-40 | 3 (48 / 36) |
  | 8 x 16 km | 5 / 38-46 | 0 ("Nothing fits") |

  Lights showcase: one set of 4 per row (a set needs 3 x 2R + 2 x 713 m = 9.5 km of width, two need 20.2 km), rows
  2R = 2.7 km apart; the same for every seed (nothing drawn but the fixed shape). Was 4 sets on 16 km, 5 on 20 km
  with Medium / Large.
- Junction test and Crossing test: unchanged, their town size is the UI choice (`jn.ui.size`, `jn.crossUi.size`).
- Tests: test_showcase.lua (every town of every layout the spec's size via `checkLayout`, sets per 16 / 20 km map,
  spec size and text, the Lights build's `towns=N (Medium)` and its growth: x3 now), test_towns_logic.lua (both specs Medium,
  Lights x3 once), test_hud.lua (the button's hint).

## Town names say their test (user request 2026-10-12)
Showcase towns were all "Grid S<n>": nothing told which test, set, side or twin a town belonged to.

Status: implemented 2026-10-12 (rev 2, unreleased), offline-tested; not seen in game yet (TESTING.md 6U step 3).

- **Names** (`logic.showcaseTownName`, set in `showcaseLayout`): Lights showcase (`spec.modeNames`) "<mode> <set>
  <side>": "Smart lanes 1 N", "Game default 1 E", "Smart phases 1 S", "Kerb locked 1 W" (mode = the twin's
  `SquareStressShowcaseAb.label`: a sl, b game, c sl_phases, d sl_lock, "Full fan" before 2026-10-13 and still a test
  town name; a T has E, N, W). Showcase "<type> <set> <side>
  (<mode>)": "Parclo 3 N (Smart lanes)", type = `SquareStressShowcaseType.short` (Ring IX, Parclo, Dumbbell, Parclo 2Q,
  Peanut, Diamond, Roundabout, Magic RB, Channel T, Oval RB, Channel X, Hamburger, Crossroads, T-junction; <= 10
  characters). Side = `logic.compassOf(rotation + arm direction)`: 8 compass points (map +y north, +x east, as the
  Crossing test's rows); arms are >= 60 deg apart, so no two towns of a group share one. Longest name 31 characters
  ("Roundabout 17 NW (Game default)"), tested <= 31 and unique per layout. The log keeps the name (`Group 1a
  Crossroads -> Crossroads 1 N (Smart lanes)`); no separate S<n> id was needed (log tags and lock areas use the name,
  nothing parses it).
- **Remove towns > Grid towns** no longer relies on the "Grid " prefix alone: `towns.testTowns` holds every town
  entity `createGrid` made this session (Test grid, Junction test, Crossing test, both Showcases; filled in its
  summary, with the name it got; taken only while the town still has that name, since a destroyed town's id may be
  reused by a real town; an id dropped when its town is removed or no longer exists), and `logic.isTestTownName`
  matches the test grid's "Grid A1", the Crossing test's "Grid N/E/S/W", older Showcases' "Grid S35" (earlier saves)
  and both new patterns (mode word from `TEST_TOWN_MODES` and a compass
  point required, so "Parclo 3 N" or "Full fan city" are not taken). Nothing else matched town names (bus lines,
  zones, flow log and tools/flow_report.py use entity ids, zone ids and positions).
- Tests: test_showcase.lua (names per mode / side / set, the side where the town really lies, short and unique, every
  Showcase town a test town), test_towns_logic.lua (`isTestTownName` yes / no lists), test_towns.lua (Grid towns
  removes old- and new-named towns and this session's towns by id, never real towns; createGrid records its towns).

## Town entries must not be the bottleneck (user screenshot 2026-10-12, queued after the town-size/names change)
Screenshot (Lights showcase seed 530609): the link's inbound lanes queue solid back from the grid's side-middle
crossroads (link x ring x central street): the whole town arm funnels through one at-grade crossroads, so the
measurement would test the town entry, not the junction. Rule: the town end must have clearly more capacity than
the junction under test, identical in every twin. Plan: (1) links = large country road (3 lanes each way);
(2) at the grid side middle a 2-lane square_roundabouts Roundabout (4 arms: link, ring both ways, central street) when
Roundabouts & Interchanges is enabled, else a Smart-Lanes-handled crossroads with the link's straight-in movement on
its own lanes; (3) optional second entry per side (link splits to two side nodes) if one roundabout still queues;
(4) entries are outside the twin zones but identical in all twins; log entry builds; tests.

Status: (1) and (4) implemented 2026-10-12 (rev 2, unreleased), offline-tested. First in-game run (log
`2026-10-12_2343_top-up-563524`): every one of 96 entries refused by the pre-check, `Collision (hits 12 other BASE_NODE
e.g. #..)`; fixed the same day with our own entry construction (below, "In-game refusal"). Second run
(`2026-10-13_0018_top-up-598153`): refused by the inward crossroads only; inward arm shortened. Third run
(`2026-10-13_0045_top-up-158690`): all 96 built (in_reach=42m), but the town built on the unlocked entry streets
(below, "Third run"); fixed, not run in game since (TESTING.md 6U step 4b). (3) not done (only if one roundabout still queues).

### Implementation (2026-10-12)

- **Lights showcase only.** The main Showcase links through `rankTownNodes` to the nearest dead end of the town's
  own grid (corner stubs), a different code path with no side-middle node to replace; its towns keep that.
  `spec.entries` / `spec.linkLanes` are set by `logic.lightsSpec` only.
- **Links**: every new link piece is `country_{new,old}_large` (`logic.ENTRY_LINK_LANES` 6 via `linkBuilder`'s
  `lanes`), whatever the junction arm's lanes (2x2: 2 each way into 3 each way at the replaced arm end; stress_nodecfg
  pairs the lanes). Crossroads fallback links too.
- **Design chosen: the roundabout replaces the side-middle crossroads itself.** Rejected: a roundabout just outside
  the ring with its inner arm to the side-middle node, the ring left as it is: every car would still pass the same
  at-grade crossroads (link x ring x central street), which is what queued. The chosen variant, per town entry:
  1. **ebuild** (first build step, right after the zones wait, while the towns are still small: fewest houses in the
     way): the grid node at `logic.sideCentre` (within 15 m) must have exactly 3 street edges whose far ends are
     `in` / `left` / `right` of the outward axis (`logic.entryRoles`), each far enough for the arm, the far node's
     junction area and a join (`ENTRY_REACH` 46 + `ENTRY_FAR_CLEAR` 16 + `ENTRY_MIN_JOIN` 5 = 67 m; a Medium block is
     75 m). The roundabout is centred on that node (`e.x, e.y` = the node's position from here on: proposal, scan,
     read, log lines; sideNode accepts it up to 15 m off the side's middle). The driving side is read once per run
     at the first entry with its streets (`logic.drivingSide` over a grid street's lane `forward` flags; logged
     `entries: driving side right|left, ring anticlockwise|clockwise`, or `not read (...), right assumed`) and sent
     as `sqst_entry_dir` (1 anticlockwise, 2 clockwise: every ring quarter reversed), the same for every twin.
     The inward arm (towards the central street, `sqst_entry_in_axis`) ends at `logic.ENTRY_IN_REACHES` 46 / 42 / 38 /
     36 m (`sqst_entry_in_reach`), the first that passes the pre-check, starting from the reach the run's entries
     needed so far (`s.entryInK`); a lower start is logged once (`entries: inward arm 46m refused by the check (46m),
     42m from now on`). Chosen over "one reach for all from the first entry" because it needs no extra pass and
     still keeps every entry after the first identical; a set whose entries ended with different reaches is
     `match=no reason=entry` (`entriesMixed` compares kind and reach). All refused: the crossroads,
     `(roundabout refused by the check: <why> (inward arm 46m, 42m, 38m, 36m))`. The shortest arm, 36 m, ends 3 m beyond
     the ring's outer edge (33 m with the highway ring); whether the engine takes so short an arm is not known (the pre-check decides).
     Then ONE proposal: `constructionsToAdd` = our entry roundabout
     (`square_stress_test_entry.con`, geometry `stress/stress_entry_streets.lua`, `logic.ENTRY_CASE`): **3-lane ring
     first** (user 2026-10-13, "3/4 lanes, whatever is biggest"): `highway_new_large`, the widest country one-way of
     the base game (3 lanes, 23 m; no 4-lane one-way exists, country or town), centreline 22 m (island curb 10.5 m,
     outer edge 33.5 m: the 2-lane ring's footprint +0.5 m, so the block and far-node clearances measured in game
     still hold: ring arms to 46 m clear of the T-junctions, inward 42 m clear of the crossroads; square_roundabouts'
     3-lane ring with large country arms placed at a 19 m centreline in its engine probe,
     plans/square_roundabouts/probe_results.csv), `sqst_entry_ring` 2. **Pre-check ladder**: the 3-lane ring at
     every inward reach (46 / 42 / 38 / 36 m), then the 2-lane ring the same way, then the crossroads; the step the
     entries need so far is the start for the later ones (`s.entryStep`), logged once when it moves (`entries: 3 lanes
     46m refused by the check (...), 3 lanes 42m from now on`); a set whose entries end on different steps is
     `match=no reason=entry`; all refused: `(roundabout refused by the check: <why> (tried 3 lanes 46m, ..., 2 lanes
     36m))`. Built line: `... in_reach=Nm ring_lanes=3|2`. The 2-lane ring (fallback):
     `highway_new_medium` (a country one-way: no houses on the ring or its island; was `town_new_one_way_small`; it
     has no footpath, so pedestrians detour round the entry, e.g. over the grid's other streets) at
     24 m centreline radius, as square_roundabouts' Roundabout with 2 lanes and radius S,
     direction by `sqst_entry_dir`; four straight `country_new_large` arms on the axes ending 46 m out; availability
     from 1940) centred exactly on the node,
     **rotation exactly 0** (`junctionTransf` writes every zero +0; the output has no -0, tests/square_stress_test/
     test_entry_streets), plus `edgesToRemove` = the 3 edges, `nodesToRemove` = the node, and the far nodes' configs
     without them (`rt.nodeConfigEntry` remove + add). Pre-checked with makeProposalData; refused (check or send) leaves
     the crossroads untouched (atomic); a collision names the entry's own nodes and edges it hits
     (`; known: #id in far node, ...`) and how many distinct entities (`12 other BASE_NODE (3 distinct)`).
     Before 1940 (no one-way ring street) every entry stays the crossroads (`before 1940: ...`).
     **Locked early, in the serial job**: each ebuild step first locks every built entry that is at least
     `ENTRY_LOCK_AGE_MS` 2 s old (`lockDue`: past Smart Lanes' ring write, WRITE -> LIGHTS -> VERIFY within ~1 s in
     session `2026-10-13_0045_top-up-158690`, so every entry gets build, SL write, lock in that order; SL re-plans the
     swapped streets afterwards, covered by the settle), and an `elock` step after the last ebuild waits for the
     youngest to reach 2 s, then locks the rest. Its own streets (both ends new nodes within `ENTRY_REACH +
     ENTRY_SCAN`: ring and arms) are swapped for `roadDevelopmentLocked` copies (`towns.lockEdgeList`, one proposal,
     retried once). Logged `kind=roundabout locked=N of M streets age=..s` (detail; a shortfall or fewer than 8 at log
     level; edges already locked count, `(N already)`: the highway ring is `initiallyLocked`, and session
     `2026-10-13_0118_top-up-148916` logged a false "locked=4 of 8" plus `its streets not all locked` at every entry,
     every set `reason=entry`, while the links lock pass found `unlocked=0` in all 96 towns; for that map use
     `make flow ARGS='--ignore-reason entry'`). Window: about 2-3 s from build to lock (the town hung streets on the arms within 12-51 s in that run).
     A 1 s `rt.later` lock (first version) was dropped: it landed in the middle of Smart Lanes' ring write. An entry
     not all locked is said at its read (`its streets not all locked (...)`), listed, and its set is `match=no
     reason=entry`; it is still read and joined (the joins read each arm end fresh).
  2. **eread** (after the one settle, before the junction reads): the 4 new arm ends near the centre (`newEnds`,
     `ENTRY_REACH + ENTRY_SCAN`), roles by `entryRoles`; the outward one is the town link's target (`arm.entryNode`,
     no own-town check: it lies 46 m outside the grid square).
  3. **elink**: the three inner arm ends joined to the three far grid nodes (`linkBuilder`, copies of the arm's
     country large road, every new node configured), ONE proposal (`mergeBuilders` now merges two links re-pointing
     the same far node for different edges: the grid corners shared by a ring join and the central join); refused:
     each join alone with the usual retries. `joined=k/3`.
     **Lights at a lit far node** (review 2026-10-12): step 1 drops the side-middle leg's connections and
     crosswalk from the far node's config (phases re-pointed), and the join adds a leg in the same direction;
     `nc.remapLocked` alone would leave that leg's connections unlocked in every phase (no history: "drives as
     if green") and without a crosswalk. So step 1 reads the far node's config first (`nc.ghost`: connections,
     crosswalks, per-phase lockedLanes, the removed edge), the join's builder carries it to its replacement
     node's seed, and `nc.configs` maps the removed leg onto the joined piece: each new connection takes the
     removed leg's state for its movement (else its approach) per phase, exits into it likewise, and the
     removed leg's crosswalk comes back as the piece's edge id with its per-phase locks. Applied only when the
     node still matches (same phase count, no connection the ghost lacked) and the piece is the one added
     edge; otherwise the old rule stays (the leg unlocked: a permanent red would deadlock the entry instead,
     and `states = {}` inside a node-config write is unverified, docs/findings/roads.md) and the run lists it
     as a problem. Log: the joined line ends `lights=in:carried` per lit far node (`unmapped (why)`,
     `not joined`; before a final ` (broken)`); unlit far nodes are not listed. **In game (third run) never
     carried**: the ring corners had lost their light (0 phases) and the inward T had new connections (findings
     roads.md). Now a lit far node not carried gets its light switched off after the join (`lightsOff`, the game's
     own proposal; logged `in:off (unmapped (...))`), not listed as a problem; only a node not found at its spot
     is. The joins read each arm end fresh (`entryJoin`: its one street now; an end with another street is not
     joined, "arm end N has k streets now, not 1"); a read that misses an arm says which roles it found.
  4. glink: the junction's arm straight into the roundabout's outer arm end.
- **Third run (2026-10-13, log `2026-10-13_0045_top-up-158690`, seed 158690).** All 96 built at in_reach 42 m, but 12
  arms not read (ends=3/2), 10 broken joins (3 of them a stale arm edge: "can't be cast" in the segment copy), every
  joined far node's lights unmapped, 15 towns unlinked (12 without an outer end, 3 links refused CNP 3 times),
  sets_mismatch=6; user screenshots: houses and a tower on the town-street ring; in some towns the ring arms ended in
  town-built stubs bent outwards, the outer arm a dead stub. No pattern by side or twin mode; offline the geometry is
  right for every direction / axis / reach (test_entry_streets). Cause (inferred, docs/findings/towns.md): the entry
  streets were unlocked town-reach streets for about a minute before the read, and the town hung streets on the
  free arm ends and split arms; the towns with failures had 4-7 streets outside the grid at the links lock pass,
  the others 2. Fixes: the lock right after the build, the country ring, the fresh arm reads, the lights switched
  off (above). The 3 refused links probably met town streets at the outer end (not verified).
- **Order (user asked to see the roads sooner)**: towns -> grids/locks -> entries -> junctions -> settle -> reads
  (entries, junctions) -> entry joins -> links -> summary line and problems dialog (`Built in N min (the growth
  follows)`) -> the links lock pass -> growth (both queued at the summary, serial). So every road is built before the
  dialog and the growth; the dialog appears only when there are problems (otherwise the summary is only in the
  log). Unchanged.
- **Fallback = the crossroads as before**: our entry construction not found (`entries=crossroads (entry construction
  not found)` on the first line, one `kind=crossroads (...)` line per town), a year before 1940, a town's node not as
  expected, or the proposal refused (`kind=crossroads (roundabout refused...: why)`, listed in the dialog).
- **In-game refusal (2026-10-12, log `2026-10-12_2343_top-up-563524`) and the fix.** With square_roundabouts'
  Roundabout every one of the 96 entries came back from the pre-check `Collision (hits 12 other BASE_NODE e.g. #N)`,
  no streets, no town buildings. Its arms end 62 m out (ring centreline 24 m + its 8 m half width + its fixed 30 m
  ARM_LENGTH; no param shortens them; XS 57 m is still too far), and the far grid nodes lie 75 m out: the central
  street's next node is a crossroads of 32 m large town streets, the ring's next nodes T-junctions whose inward leg
  is a column (or row) street of the grid, the same 32 m street, so their junction areas reach to about 75 - 16 = 59 m,
  and every arm end lay inside one. The "e.g." ids fit that (their SQRL APPLY lines in the same log): 24 of the 96
  were crossroads, all of them the S towns' entries, and the only crossroads within reach is the `in` far node (the
  side-middle node and the ring far nodes are T-junctions); the other 72 (E, N, W) were T-junctions. Not the removal: the three removed edges lie under the arms for 38 m
  each and the check named no street, so makeProposalData does not collide a construction with the streets the same
  proposal removes (a two-step removal would not have helped). Not proven which 12 (the log printed one id; 3 far
  nodes x 4 is the inferred split): the next run's refusals list them with roles. Fix: our own construction with
  the same ring and arms ending at 46 m (joins 29 m, about 13 m of it clear of the far junction), so the old flow
  (removal + construction in one proposal, read, joins, lights carried) stays. **Second run** (log session
  `2026-10-13_0018_top-up-598153`): all 96 still refused, `hits 2 other BASE_NODE (1 distinct) ... in far node`, every
  hit the inward crossroads (the ring T-junctions at the same 29 m were clear; docs/findings/roads.md). Fix: the
  inward arm alone is shortened by pre-check (step 1); the far-node labels now also give its street count. Rejected: a roundabout out on the
  link (the side-middle crossroads would stay, the bottleneck); a sparser grid for the Lights showcase (fewer
  streets and houses: a different town).
- **Identical in all twins**: the same construction, params and offset from every twin's junction. A set whose twins
  got different entry kinds is `match=no reason=entry` at the read (`entriesMixed` after the entry builds); a
  roundabout not read or not fully joined marks its set the same after the links (`showcase zone_match`).
- **Outside the twin zones**: an entry sits at side middle = town distance - grid half (713 - 300 = 413 m from its
  junction), its outer arm 46 m closer: ~367 m, beyond the traffic log's measured area (r + 200 m, ~290 m; tested).
- **Smart Lanes**: no zone for the entries (its normal ring rules, the same in every twin).
- **Logs**: `[SQST] lights_showcase entry <town> kind=roundabout at x,y node=N removed=3 from_junction=..m ms=..
  reach=46m`, `... kind=roundabout read ends=4 outer=N` (detail), `... kind=roundabout joined=3/3`,
  `... kind=crossroads (why) at x,y`, and after the summary `[SQST] lights_showcase entries roundabout= crossroads=
  broken= joins=a/b` (FLOW.md; tools/flow_report.py counts the kinds per load). Timing: the entries and their joins
  count in the `junctions` phase.
- **Growth for ~1000 people per town** (user 2026-10-13, "grow to ~1000 population is good"; was x10, which targets
  4000 residents per Medium town; seed 530609 stuttered at 8x with x10). `LIGHTS_GROW_FACTOR` =
  `logic.growFactorFor(LIGHTS_TARGET_POP 1000, Medium initial capacity 400)` = 1000 / (`GROW_FILL` 0.85 x 400) = 2.94,
  rounded to 0.5 steps: **x3**, one size command per town as before, the same for every town (twins comparable).
  Population = the residential person capacity (`getTown2personCapacitiesMap()[town][1]`, the game's own: world
  population sums it, the town window shows it; docs/findings/towns.md). `GROW_FILL` from the only post-growth
  reading in the log archive (session `2026-10-10_0544_grow-x100-crash`: initCaps 100 x10 -> 836 residents within 5 s,
  the same at 30 s). Chosen over grow-read-stop: a second size command per town would be another serial pass (the
  passes were dropped for taking 3-4 min), and towns keep building after the answer anyway. Logs: each grow line
  ends `pop=N` (read at the size command's answer, detail log; usually still the old value), each final line
  `pop=N` (read at the final check, after every town's command), the dense summary
  ` pop min/mean/max=a/b/c (n of N towns read)`. **To check in game**: the summary's mean near 1000; if it is far off,
  adjust `GROW_FILL` from it. One constant: the first log line, the summary, the HUD hint (now "to about 1000 people
  each") follow it.
- **houses_outside** (coordinator 2026-10-12): seed 530609's final leak lines summed 1842 houses outside (2-97 per
  town) while the user saw none outside any grid; `houses_perimeter=0` in every town (no house in the 45 m band just
  beyond the ring) and the one town whose grid holds the map origin (S43) had 0. Inferred, not proven: buildings
  whose BOUNDING_VOLUME was not filled yet (a point at 0,0: under construction right after the growth) were placed at
  the map origin, outside every other town. Fix (`logic.housePos`, stress_towns `townHouses`): the box centre only
  when the box is real (finite, with extent, not a point), else the building's construction origin
  (`TOWN_BUILDING.construction` -> CONSTRUCTION transf), else not counted (`houses_unread=`); a box over 150 m from its
  construction's origin uses the origin (`odd`). Leak lines now end in `houses_unread=N houses_pos=bbox:a,con:b,odd:c`
  (evidence for the next run, TESTING.md 6U step 3).
- **Traffic log** (FLOW.md v3): every driver read; zones measured along their arms (`arms` from the read's clusters
  on `SquareStressShowcaseZone.arms`). See FLOW.md "Measured area" and FLOW_TARGET.
- Tests: test_showcase.lua (entry helpers; entries built, rotation 0 with no -0, node + 3 edges removed and far configs
  paired, identical per set, joined in one proposal each with complete configs, every link to an outer arm end and
  large; the inward arm shortened by the pre-check (46/42 refused -> 38 m for all, logged once; one later entry
  needing 42 m -> its earlier sets reason=entry; all refused -> crossroads listing the reaches); ring direction by the driving side read from the grid streets (right / left / unread); the roundabout
  centred on a side-middle node 10 m off the side's middle; construction missing; before 1940 (the 1920 Lights test); one refused entry -> reason=entry; a refusal's
  collision text (12 hits on the 3 far nodes: `(3 distinct)`, roles under `known:`); a lit far node: the joined leg's connections and crosswalk
  locked exactly where the removed leg's were, unlit far nodes unchanged (test_nodecfg: ghost, carry, unmapped);
  the settle waits when only entries were built; the older Lights tests run with `entryRing = false` for the
  crossroads path), test_entry_streets.lua (the entry construction: ring and arms, reach = ENTRY_REACH, no -0,
  arm ends clear of a Medium grid's far junction areas with a join, the old 62 m refused by the block check, the
  clockwise ring = every quarter reversed with no -0, availability 1940, the direction param, drivingSide, the
  inward arm per axis and reach with nothing else changed and no -0, axisIndex),
  test_flow.lua (60k persons all read within budget, target lowering, measured area / q_arm),
  test_towns_lock.lua (housePos, unfilled boxes not outside), tests/tools/test_flow_report.py (v3 fields, v2 lines).

## Mixed shapes, smaller towns, throughput (user 2026-10-13: "A, but lets keep towns smaller, maybe around 400 people")

Status: implemented 2026-10-13 (rev 2, unreleased), offline-tested; not run in game yet (TESTING.md 6V).

- **One press, every shape** (`logic.lightsMixedSpec` = `LIGHTS_SPEC`): kinds x / t alternating, the crossroads'
  types in turn, `perType` 3 (`LIGHTS_PER_TYPE`): 3 sets each of 2x2 X, 3x3 X, 3x2 X and T 2x2 = 12 sets, two twins
  each (`LIGHTS_MIXED_AB`: sl a, game b; sl_phases / sl_lock / sl_fan stay modes of LIGHTS_AB and Smart Lanes, not
  built here) = 24 junctions; X sets 4 towns per twin, T sets 3: 90 towns (today's load: 96). The shape cycling is
  gone (the button: "Build lights showcase"); `jn.buildLightsShowcase(seed, k)` still builds one shape with four
  twins (`lightsSpec(k)`, earlier runs and tests). First log line: `... twins sl=12 game=12 towns=90 (Medium) ...
  shapes=2x2_X,3x3_X,3x2_X,T_2x2 per_shape=3`. Zones keep the shape as their type label (`2x2_X`, ...), so
  tools/flow_report.py groups per shape and pools them (`all`).
- **Layout with two twins (superseded the same day by three twins: "Exit-fan twin" below has the current layout)**
  (offline, 16 km map, margin 400 m, seed 12; 16 and 20 km, seeds 12 / 777 / 4242 all give 12 sets, 24
  junctions, 90 towns, tested): every set's two twins side by side, R = 1509 m.

  | set | shape | sl at (m) | game at (m) |
  |---|---|---|---|
  | 1 | 2x2 X | -6908, 6908 | -3890, 6908 |
  | 2 | 3x3 X | -871, 6908 | 2147, 6908 |
  | 3 | 3x2 X | 3839, 4408 | 6857, 4408 |
  | 4 | T 2x2 | -5559, 4208 | -2541, 4208 |
  | 5 | 2x2 X | 2169, 1708 | -849, 1708 |
  | 6 | 3x3 X | -3890, 1508 | -6908, 1508 |
  | 7 | 3x2 X | 6879, -792 | 3861, -792 |
  | 8 | T 2x2 | 820, -992 | -2198, -992 |
  | 9 | 2x2 X | -6908, -3492 | -3890, -3492 |
  | 10 | 3x3 X | 2511, -3492 | 5529, -3492 |
  | 11 | 3x2 X | -2198, -5992 | 820, -5992 |
  | 12 | T 2x2 | 3861, -6192 | 6879, -6192 |

  Kinds in turn x, x, x, t (`kinds = { "x", "x", "x", "t" }`; the layout loop ends when every distinct kind is full),
  so every fourth set is a T and the T sets spread from the north to the south of the map; `alternateTwins`: per shape,
  its second set has the sl twin east of the game twin (its first and third west: every shape has sl on both sides;
  the zone ids stay a = sl, b = game). Guards (tested): a kind without types is full at once; a set with no twin
  (every mode lit-plain only for an unlit kind) is a miss, never an empty set (the loop ended only at the cap before).
  T sets: three towns (E, N, W of the junction), the same entries, links and locks (tested end to end: 90 entries,
  90 links, joins 270/270).
- **Towns about 400 people: corrected 2026-10-13 after session `2026-10-13_0356_top-up-779299`** (the factor from the
  population overshot: pop 398 / 569 / 1020 for 400; every town ended at its initial capacity x its factor, median
  0.998, docs/findings/towns.md): each town's factor is now `growFactorForCap(400, initialLandUseCapacities[1] x
  sizeFactor)`, i.e. x1 for every Medium town (the level weights only; the x1 towns there ended at 398-400), logged
  `(x1 for 400 from capacity=400 pop=..)`; fallback `LIGHTS_GROW_FACTOR` x1. The earlier design below is superseded.
- **(superseded) Towns about 400 people** (`LIGHTS_TARGET_POP` 400, `spec.growTarget`): the growth multiplies what a town has.
  Evidence (sessions `2026-10-13_0118_top-up-148916` and `2026-10-13_0205_top-up-61157`, x3 for all, 96 Medium towns):
  population after = population before x 3.1 (median; quartiles 3.0 / 3.2, 2.7-4.2), before 122-399 (mean 301), after
  326-1198 (mean 939), the same at the size command's answer and minutes later. So each town gets its own factor
  `growFactorForPop(400, pop)` = 400 / pop (0.05 steps, at least 1: a town already that big only gets the level
  weights), read at its grow step; `LIGHTS_GROW_FACTOR` (x1.25, `growFactorFor(400, 400)` with `GROW_FILL` 0.78 =
  939 / 1200) only when a population can't be read. Same 8 x 8 Medium grid for every town. Expected: about 400 each
  (the smallest town x3.3, the mean x1.35). Logs: `grow queued ... target=400 (each town: target / its population)`,
  each pass line `(x1.35 for 400 from pop=296)`, the final `pop=` per town and the summary's `pop min/mean/max`.
- **Lanes fan where the lane count changes** (lane audit of session `2026-10-13_0205_top-up-61157`, stress_nodecfg
  `nc.pattern`): at a two-street joint of different widths (junction arm 2 lanes -> large country link 3, link ->
  entry roundabout arm) the narrower side's far lane feeds every extra lane of the wider side and they all lead back
  into it, curb lanes aligned, nothing crossing; before, the link's third lane was never fed and led nowhere. Junction
  nodes (3+ streets) keep one-to-one for the smaller count. The same in every twin; these joints are unlit.
- **Throughput and queue sides in the traffic log**: FLOW lines carry `thru` / `thru_s` (cars through the junction
  between samples, from each driver's path) and `q_in` / `q_out` (an arm's queue by side of the road). FLOW.md
  "FLOW" has the method; tools/flow_report.py shows `thru/min` per zone and pair and in the sign tests, and the
  queue sides under Approaches.

## Exit-fan twin: three twins per set (user 2026-10-13)

Status: implemented 2026-10-13 (rev 2, unreleased), offline-tested; not run in game yet (TESTING.md 6V).

- `LIGHTS_MIXED_AB` = sl (a), game (b), **sl_exitfan (e)** (`LIGHTS_EXITFAN_AB`: Smart Lanes lanes, every turn fanned
  into the exit lanes at a lit junction, game phases; towns "Exit fan <set> <side>"; letter e keeps d for sl_lock /
  sl_fan). Zones `g<k>e`; `by_ab=game:12,sl:12,sl_phases:0,sl_exitfan:12`, the same text Smart Lanes' `byAbText` writes
  (tested). tools/flow_report.py compares `sl_exitfan vs sl` (the fan alone) and `sl_exitfan vs game`, both pooled in `all`.
- **Map size**: a set of three twins is 9 km wide (each twin 2 x R = 3018 m), so a 16 km map holds one set per row:
  6 sets (18 junctions, 69 towns; seeds 12 / 777 / 4242 tested). **All 12 sets need a 20 km map**: 36 junctions,
  135 towns (about 400 people each without growth: x1, the level weights only). No shape cycling or perType change:
  smaller maps get the first sets of the cycle (2x2, 3x3, 3x2, T, 2x2, 3x3), positions not balanced per shape.
  **A compact layout can't fit 12 three-twin sets on 16 km**: every twin needs its own square of 2 x R = 3018 m (its
  junction, its four towns at 713 m and their 600 m grids, the gap; R is fixed by the town spacing), so a 16 km map
  (15.4 km inside the 400 m margin) holds at most 5 x 5 = 25 such squares however a set's twins are arranged (row, L
  or triangle), and 12 x 3 = 36 are needed. Only a smaller R (closer or smaller towns) would, which changes the test.
- **Positions rotate per shape** (`alternateTwins`): a shape's k-th set puts twin t at position (t - 1 + k - 1) mod 3
  + 1, so over its three sets every twin sits once west, once in the middle, once east (tested per shape). Layout,
  20 km map, seed 12 (x, y in m):

  | set | shape | sl (a) | game (b) | exit fan (e) |
  |---|---|---|---|---|
  | 1 | 2x2 X | -8956, 8956 | -5938, 8956 | -2920, 8956 |
  | 2 | 3x3 X | 99, 8956 | 3117, 8956 | 6135, 8956 |
  | 3 | 3x2 X | -7607, 6256 | -4589, 6256 | -1571, 6256 |
  | 4 | T 2x2 | 1448, 6256 | 4466, 6256 | 7484, 6256 |
  | 5 | 2x2 X | -5938, 3556 | -2920, 3556 | -8956, 3556 |
  | 6 | 3x3 X | 3117, 3556 | 6135, 3556 | 99, 3556 |
  | 7 | 3x2 X | -4589, 856 | -1571, 856 | -7607, 856 |
  | 8 | T 2x2 | 4466, 856 | 7484, 856 | 1448, 856 |
  | 9 | 2x2 X | -2920, -1844 | -8956, -1844 | -5938, -1844 |
  | 10 | 3x3 X | 6135, -1844 | 99, -1844 | 3117, -1844 |
  | 11 | 3x2 X | -1571, -4544 | -7607, -4544 | -4589, -4544 |
  | 12 | T 2x2 | 7484, -4544 | 1448, -4544 | 4466, -4544 |

## Run 6 (2026-10-13, seed 726115, session `2026-10-13_0447_top-up-726115`): three arms lost to town streets, fixed

- All 69 entries `ring_lanes=3`, 66 joined; Exit fan 6 E / N / W `arms not read (ends=3)`, one town street outside
  each of those grids (`outside_streets=1`). They were the last four entries, locked one after another in the closing
  lock step at 3.4-4.2 s; the 64 locked at 2.0-2.6 s were all fine (docs/findings/towns.md, unlocked streets).
- Fixes: (1) every entry's streets are locked in its own build callback (before Smart Lanes' pass ~10 frames later;
  when not all lock there, e.g. still the construction's, the later lock at >= 2 s tries again: logged as detail
  `(at the build: the later lock tries again)`); (2) the later lock locks every due entry in ONE `lockEdgeList`
  call (`locked=N of M streets age=..s (one lock for K entries)`, counted per entry from fresh reads); (3) an arm read
  that misses an end looks for a stray town street on it: exactly two streets at a node at an arm's reach, one the
  entry's own, the other unlocked, without objects, ending in a dead end: that stub and its end node are removed in
  one proposal (the arm end's config re-pointed), logged `kind=roundabout stray street <edge> (arm end <node>)
  removed` (or `not removed: <why>`), and the arms are read once more; anything else stays `arms not read`;
  (4) the summary counts each kind once and then per shape (`crossroads=15/15 t_junctions=3/3 shapes 2x2_X=..`).
- Review fixes (2026-10-13): the entry's own streets and arm ends come from its geometry (`entryPoints` /
  `entryNodes`: ring nodes at the ring's radius, arm ends at their reach, within 2.5 m), not from "new node near the
  centre", so a short town stub (sideways or outward, both ends inside 66 m) is neither locked as its own nor read as
  an arm; a dead end at each arm-end point is the arm end. A stub is removed only at an arm-end point of a role the
  read missed, unlocked, without objects or town buildings on its parcels (getSegment2ParcelData), ending in a dead
  end, no construction's or later build's node; otherwise `stray street not removed: <role> arm end <node>: <why>`.
  The closing lock step waits (every 0.5 s, up to 20 s) while a build-time lock is still in flight, so a late or
  refused one is retried; the read says `its build-time lock never answered` when one never came. The final read
  after the stray check is guarded (an error marks the entry broken) and the step finishes once.


## Light plans A/B (user 2026-10-14: "a small simulation for testing these light updates on 2- and 3-lane intersections")

Status: implemented 2026-10-14 (rev 3, unreleased); run once in game 2026-10-15 (session
`2026-10-15_0355_top-up-488195`, TESTING.md 6Z). The third twin is now the auto timing one (below: "Auto twin and
unbalanced demand"); the table here describes the classic build (the variant `light_plans_classic` until 2026-10-16,
removed with Smart Lanes' classic patterns: its PLAN.md "No classic fallback"; Smart Lanes now refuses `sl_classic`).

Smart Lanes now has three light plans for a lit crossroads: the game's default (zone `game`), its new **axis plan**
(zone `sl_phases`, since Smart Lanes rev 8) and its old **classic patterns** (protected / split / lead-lag, new zone
mode `sl_classic`, `square_smart_lanes` `sl_zones.lua`). All three use the same lanes except `game`, so `sl_phases` vs
`sl_classic` is the light plan alone.

What a press of the **Lights showcase** button builds (unchanged): `LIGHTS_SPEC` (= `lightsMixedSpec`): every shape
(2x2 X, 3x3 X, 3x2 X, T 2x2), 3 sets of each, every set as three twins sl (a) / game (b) / sl_exitfan (e); 16 km map:
6 sets (18 junctions, 69 towns), 20 km: all 12 (36 junctions, 135 towns); towns about 400 people.

New second button in the same section, **"Build light plans A/B"** (`jn.buildLightPlans`, `logic.LIGHTS_PLANS_SPEC` =
`lightsPlansSpec()`): the same build code and budget (`buildRun`: batched towns / grids / locks / links, entries, square
layout, no bus lines), only:

| | Lights showcase | Light plans A/B |
|---|---|---|
| shapes | 2x2 X, 3x3 X, 3x2 X, T 2x2 | **2x2 X** (2 lanes each way) and **3x3 X** (3 each way), in turn |
| sets | 3 per shape | 3 per shape (6 sets, 18 junctions, 72 towns: fits a **16 km** map; seeds 12 / 777 / 4242 tested) |
| twins | sl a, game b, sl_exitfan e | **game b, sl_phases c (axis plan), sl_classic u (classic patterns)** (`LIGHTS_PLANS_AB`), each once in every position per shape (`alternateTwins`) |
| towns | ~400 people | **~600 people** (`LIGHTS_PLANS_TARGET_POP`, x1.5 by capacity: busier junctions; 400 left the 3x3 Smart Lanes twins at ~20 % standing in session `2026-10-13_0447_top-up-726115`; the micro bench's 800 neared a jam) |
| first log line | `... shapes=2x2_X,3x3_X,3x2_X,T_2x2 per_shape=3` | `... twins game=6 sl_phases=6 sl_classic=6 towns=72 (Medium) ... shapes=2x2_X,3x3_X per_shape=3 variant=light_plans bus_lines=no` |
| summary | `Lights showcase done: ...` | `Light plans A/B done: 18 of 18 lit crossroads built (game 6/6, sl_phases 6/6, sl_classic 6/6) ...` |

Job and log names stay `lights_showcase` (busy guards, `make logs` tags, the entry lines). Town names "Game default
<set> <side>", "Smart phases <set> <side>" (the axis twins), "Classic phases <set> <side>" (Remove towns > Grid towns
knows them). Zones `g<k>b` / `g<k>c` / `g<k>u`; the zones line `by_ab=game:6,sl:0,sl_phases:6,sl_classic:6` matches
Smart Lanes' `byAbText` byte for byte (tested against its `sl_zones.lua`). Letter **u** for sl_classic (a-t are taken:
stress_flow `TWIN_LETTER`, the bench's mid letters p-t); `stress_flow` `TWIN_ORDER` sl_classic = 16, so a reload's
fallback set split works. Built in that order (game, sl_phases, sl_classic). Needs Smart Lanes with the `sl_classic`
zone mode (an older Smart Lanes refuses the whole zone set: `ab<i>`).

**Re-time** (Smart Lanes' tool button: measures 3 game min at the selected lit junction, then changes only its phase
lengths): pressed by hand on an axis twin. `tools/flow_report.py` finds the write (`[SQRL] RETIME op=write sent=1`),
joins it to its twin by the node's `zid=` (Smart Lanes appends `zid=` to the write's `LIGHTS ... to=retime` line; a
`zid=` on the RETIME line itself is read too) and splits that set at the write: before = the plans as built, after =
from `--retime-settle` (60) game s after it (set `g<k>+rt`). FLOW.md "Light plans and Re-time in the report".

Tests: test_showcase.lua (layout on 16 km for three seeds: 18 groups / 72 towns, modes and letters, every twin once in
every position per shape, town names, zones validated by Smart Lanes' `sl_zones.lua`, the reload fallback letters;
the build end to end: shapes, 72 entries and links, zones, growth target 600, summary), test_hud.lua (the second
button and its hint), tests/tools/test_flow_report.py (light plans section, verdicts, Re-time split).

### Auto twin and unbalanced demand (user 2026-10-14 (2); Smart Lanes rev 8 step B "Keep timing adjusted")

Status: implemented 2026-10-14, offline-tested; not run in game yet (TESTING.md 6Z1, 6Z2). The first run of the build
above (session `2026-10-15_0355_top-up-488195`, seed 488195: axis +23-26 % thru/min vs game, classic worse than game
on 6/6 sets) settled the classic patterns, so the third twin is now Smart Lanes' automatic re-timing.

What a press of **Build light plans A/B** builds now (`LIGHTS_PLANS_SPEC` = `lightsPlansSpec()`):

| | |
|---|---|
| shapes, sets | as above: 2x2 X and 3x3 X in turn, 3 sets each (6 sets, 18 junctions, 72 towns on a 16 km map) |
| twins | **game b, sl_phases c (axis plan), sl_auto v (axis plan + "Keep timing adjusted")** (`LIGHTS_PLANS_AB`; `LIGHTS_AUTO_AB`: label "Auto timing", letter **v**: a-u are taken, u = sl_classic), each once in every position per shape |
| demand | **balanced and unbalanced sets in turn** (`demandMix`, `lightsPlansDemand(shape, k)`): 2x2 X balanced / unbalanced / balanced, 3x3 X unbalanced / balanced / unbalanced: 3 sets of each on a 16 km map; the twins of a set share it, so every twin mode sees both |
| towns | balanced: every town ~600 (`LIGHTS_PLANS_TARGET_POP`). Unbalanced (`LIGHTS_PLANS_UNBALANCED`, `LIGHTS_PLANS_POPS`): the two towns on the E-W road ~600 ("busy"), the north town ~150 ("small"), the south town ~40 ("tiny") |
| town names | balanced as before ("Auto timing 2 N"); unbalanced with the word: "Auto timing 2 S tiny", "Game default 3 E busy" (Remove towns > Grid towns knows them: `TEST_TOWN_WORDS`) |
| first log line | `... twins game=6 sl_phases=6 sl_auto=6 towns=72 (Medium) ... shapes=2x2_X,3x3_X per_shape=3 variant=light_plans demand=balanced:3,unbalanced:3 pops=busy:600,small:150,tiny:40 unbalanced_sides=E,W:busy,N:small,S:tiny bus_lines=no ...` |
| zone lines | `showcase zone ... demand=balanced\|unbalanced` (last key), `FLOW_ZONE ... demand=`; zones line `by_ab=game:6,sl:0,sl_phases:6,sl_auto:6` (Smart Lanes' `byAbText`: `,sl_auto:n` after `,sl_classic:n`, tested against its `sl_zones.lua`) |
| summary | `Light plans A/B done: 18 of 18 lit crossroads built (game 6/6, sl_phases 6/6, sl_auto 6/6) ...; every town then grows to about 600 people ..., but in the unbalanced sets the north town to about 150 and the south town to about 40` |

**How a town's size is set** (unchanged mechanism): every town is created with the spec's size (Medium: initial land
use capacities 400 on an 8 x 8 grid, locked: country ring and links, so it can only build up, never out), then ONE
forced size command after the links sizes it from its capacity target (`growFactorForCap(target, capacity)`, at least
x1; a forced command fills initial capacity x factor at once, docs/findings/towns.md). A factor never goes below x1,
so a town wanted below 400 is **created with that capacity** (`SquareStressGridPoint.townCaps`: 150 / 40 on all three
land uses; its street grid stays Medium, so every set has the same geometry), and its own growth target is its pop
(`SquareStressLockArea.target`: factor x1). Logged: the grow lines' `(x1 for 40 from capacity=40 pop=...)`, every
town's final line `... pop=<n> target=<t>`, the dense summary's `pop_by_target=40:min/mean/max/n,150:...,600:...`; with
the Traffic log on, every FLOW_TOWNS town line's `pop=` (one engine call per FLOW_TOWNS, at most once per 60 s wall)
and `make flow`'s town populations per class (busy / small / tiny / other). **Open (TESTING.md 6Z1):** whether the game
accepts a 40-capacity town and whether it holds ~40 over a 60-minute run (towns grow with transport over years, not
minutes; a town's start level comes from its residential capacity: > 100 level 2, so the tiny towns start at level 1).

**Classic variant** (removed 2026-10-16 with Smart Lanes' classic patterns and its `sl_classic` zone mode): the console
`jn.buildLightPlans(seed, "classic")` built the earlier set (twins game / sl_phases / sl_classic, every town balanced,
`variant=light_plans_classic`). Gone: `LIGHTS_CLASSIC_AB`, `LIGHTS_PLANS_CLASSIC_AB`, `LIGHTS_PLANS_CLASSIC_SPEC`,
`sl_classic` in `SL_ZONE_AB` / `slZonesByAb`. Kept for older saves and logs: stress_flow `TWIN_ORDER` sl_classic = 16
(letter u), the town word "Classic phases", tools/flow_report.py's `sl_classic` comparisons.

**Smart Lanes side** (its PLAN.md "Stress Test interface: Keep timing adjusted"): `sl_auto` zones get the axis plan,
and their lit junction is enrolled (`AUTORETIME op=enroll ... src=zone`) within ~30 game s of its light; since Smart
Lanes' step B v4 (2026-10-15, its RETIME_PLAN.md "Step B v4") the first write comes after 8 queue snapshots (~16 game
min), later ones >= 10 game min apart, the cycle moving <= 20 s per write and a long cycle only after two long
decisions: ~45 game min to settle (before v4: first write after a 180 game s window, >= 5 min apart, ~15-20 min). Clearing the zones does not unenroll: press **Auto re-time > Clear** at the end of a run.
So a light plans A/B run with the auto twin now lasts **~90 game min** after the build (the window's hint says so), and
`make flow` compares the settled window from the first write + `--auto-settle` (default **2700** game s since v4, was 900).

### Auto re-time buttons (whole map)

Towns tab > Lights showcase section, a row **Auto re-time** under the light plans: **All lit junctions** sends
`SmartLanes.auto { op = "all", run }` (Smart Lanes enrolls every lit junction on the map, at most 1000 since its step B
v4, 256 before; junctions lit
later are not included: press again), **Clear** sends `{ op = "clear", run }` (every junction unenrolled; written
timing stays). Logged `[SQST] AUTO_ALL op=all|clear run=<s0-wall-n> by=button smart_lanes=yes|no` (`stress_slzones`
`sendAuto`; run ids as the zones'). Below the row, once pressed: "Last auto re-time: every lit junction enrolled (run
...), acknowledged by Smart Lanes" (read back from Smart Lanes' saved `arun`, as the zones' `zrun`) or "not
acknowledged yet". Here rather than the Traffic tab: the light builds and the before / after run are in this section,
and the buttons act on Smart Lanes' lights, not on the traffic log; refused during a bench run (`notDuringBench`).
`make flow` splits a whole-map run at Smart Lanes' `AUTORETIME op=enroll_all phase=done` (FLOW.md "Auto timing in the
report"). A before / after run on any lit map: 15 game min, press, **90** more (was 30 before Smart Lanes' step B v4).

**City lights at scale** (a row under Auto re-time, user 2026-10-15: "make every light in the big grid cities be auto
timer lights so we can see what happens with many at once"): one press runs the bench's city run (big grid towns, every
inner crossing lit, half of them kept re-timed): BENCH.md "City lights at scale", TESTING.md 6Z3.

Tests: test_showcase.lua (twins and letters, demand per set and shape for three seeds, town pops / caps / names, zone
lines, the classic variant gone, `pop_by_target`, the build end to end with per-town targets 600 / 150 / 40), test_towns.lua
(`townCaps` at creation, batched and one by one), test_flow.lua (FLOW_ZONE `demand=`, FLOW_TOWNS `pop=`), test_roads.lua
(`sendAuto`: payloads accepted by Smart Lanes' `sl_auto.lua` validator, AUTO_ALL lines, status), test_hud.lua (the
buttons and hints), tests/tools/test_flow_report.py (auto settled split, demand, whole map, town classes).
