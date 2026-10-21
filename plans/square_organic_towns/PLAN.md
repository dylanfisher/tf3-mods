Status: rev 3 published (2026-10-17: free builds without a player, unowned streets, testing growth removed); rev 4 (the town window's Organic Towns card and the new-town notification; checked in game 2026-10-17, TESTING.md "Rev 4: town window card and new-town notification") ready for upload. Offline work done through NEXT_PHASE_BRIEF 32 (the final-test round, 2026-10-13: virtual
roads on maps without country roads, drawn motifs recalibrated to real terrain + the peninsula tip motif, forest
densities, the station quarter on a station's back, coast-hugging shore towns, mountain contour roads more often; 6.3
"Final-test round"), after the final all-phases test (session `2026-10-13_0856_sqot-dev`, results in HISTORY.md), the
later-ideas phase, phase F, the motif phases M0-M4 and real map round 5. "Reshape starting towns" waits on the Starting
town size test. Then the hang fix (NEXT_PHASE_BRIEF 33, 2026-10-13: session `2026-10-13_1848_sqot` froze in a head-start
plan; loop caps, a plan hang guard, finer plan slices). Then landscape names (NEXT_PHASE_BRIEF 34, 2026-10-13: real town names from
the game's list fitted to each town's site on a new map, industries follow, landscape stop names for new Road Stops, a dev
"Place test stops (named)" button; 6.3 "Landscape names"). Then the forest / gaps / bridges round (ROUND_FOREST_BRIEF.md R1-R7, NEXT_PHASE_BRIEF 35, 2026-10-13: forest by plot depth +
clearing budget, forest lanes, gaps between towns, empty dead ends retired, motif fallback, ship-aware bridges, SIMGROW's
realistic split + a dev industrial satellite probe; 6.3 "Forest / gaps / bridges round"), tested in run
`2026-10-13_2113_sqot-dev` (results HISTORY.md). Then the round after the names run (NEXT_PHASE_BRIEF 36, 2026-10-13: unique
composed stop names, country lanes laid ahead, forest lanes on through streets only + the hug release, forest-facing
streets locked and clearing-budget windows, industrial "Works" towns; 6.3 "Round after the names run"). Then the round
after the 2240 run (NEXT_PHASE_BRIEF 37) and the round after the 2355 run (NEXT_PHASE_BRIEF 38, 2026-10-14: district
towns, Works by a factory with a robust link, coastal huggers, more bridges, squeezed towns, street-aware stop names,
Act on Off does nothing, denser growth, shorter curved lanes ahead; 6.3 "Round after the 2355 run"; the vanilla
comparison BASELINE_VANILLA.md), with its addendum after run `2026-10-14_0119_sqot` (one town creation in flight, created
towns claimed by name + site, the saved claims checked on load, no forest districts, the "Satellite towns" setting,
varied Works / district names; 6.3 "Round after the 2355 run" addendum). Then the round after the same-seed vanilla
comparison (NEXT_PHASE_BRIEF 39, 2026-10-14: no fill raises a town's capacities any more (`capsBoost=0`), a frontage brake
on free lots and persons per building, town-wide level weights toward bigger buildings (`LEVELS`, new maps), upward doses
without the surge hold, satellite links as shorter winding country lanes with a dosed core, a straight-run guard,
ALLTOWN `ind=` / `lvl=`, the tour waits for town creations, `compare/build_compare.py`; 6.3 "Round after the same-seed
comparison"), tested on the comparison seed in run `2026-10-14_0302_sqot-sqrl` (BASELINE_VANILLA.md "Density-round
run"). Then the round after the 0302 run (NEXT_PHASE_BRIEF 40, 2026-10-14: the brake and the level weights phase in with
the town's maturity in persons, pbK per building, FREE_AIM 0.55, offshoot turns and offshoot size in persons, the
three-run comparison page; 6.3 "Round after the 0302 run"). Then deep forest towns (NEXT_PHASE_BRIEF 43, 2026-10-14: 1-3
towns per map in dense forest, saved on the frame, winding, locked around the trees, groves kept; 6.3 "Deep forest
towns"), generated names (NEXT_PHASE_BRIEF 42), the dev Simulate speed-up (41), tested in runs `2026-10-14_0502_sqot` and
`2026-10-14_0613_sqot` (BASELINE_VANILLA.md). Then the round after those runs (NEXT_PHASE_BRIEF 44, 2026-10-14: LEVELS
reads the engine's own weights as a baseline, a mature hold, small satellite cores with redoses and retirement, bridges
without a far cross street, name-tag fixes, lead-out links, the deep pick recalibrated; 6.3 "Round after the 0502
run"). Then names from the map's shape (NEXT_PHASE_BRIEF 45, 2026-10-14, after run `2026-10-14_0710_sqot`: a once-per-map
survey of rivers / compass / big features, the map's word budget and tag rarity, cue words per language, clean list
names; 6.3 "Names from the map's shape"). Then bridge stops and the one-line bridge fix (NEXT_PHASE_BRIEF 46,
2026-10-14, run `2026-10-14_0814_sqot`; 6.3 "Bridge stops"). Then satellite and Works name variety (NEXT_PHASE_BRIEF 47;
6.3 "Satellite and Works name variety"), untagged lists keep the game's names with the survey run (48 items 1, 2, 5) and
plausible, climate-led names: Landscape names generated from region, climate and map, no real list names (49; 6.3
"Plausible, climate-led names"), then the stop names' climate fit, the Asian list's style spread, the tropical style
bias and the character quota (48 items 3-4, 49; 6.3 "Style spread on the Asian list, tropical bias, character quota").
Then staggered offshoots (NEXT_PHASE_BRIEF 51, 2026-10-14, after run `2026-10-14_1927_sqot`: satellites, Works and
districts paced map-wide by the map's growth, per-town readiness, a seeded draw; 6.3 "Staggered satellites"). Since
NEXT_PHASE_BRIEF 64 (2026-10-15, after run `2026-10-15_0539_sqot`) every satellite is a named town (Works / district),
2-4 per 16 towns with a quota fallback, the streets-only seeds retired, a non-linear draw for the offshoot decisions
(6.2 "Named offshoot towns instead of street satellites").
Then strong characters, the roundabout town and densify (NEXT_PHASE_BRIEF 54, 2026-10-14: 1-3 towns per map with a
strong kind picked once per map, one-way rings in roundabout towns, a densify trait; the "Strong town characters"
setting, On by default (release default decided by the user 2026-10-15: ships On); 6.3 "Strong characters, roundabout town, densify").
Then roundabout variety and organic ring roads (NEXT_PHASE_BRIEF 56, 2026-10-14, after the showcase run
`2026-10-14_2150_sqot-dev`: four ring sizes, rings in every town by era and region, paired rings, rings only among
houses, the roundabout town's empty leads stopped, wobbling organic rings that wait for the houses; 6.3 "Roundabout
variety and organic ring roads"). Then LEVELS by maturity (NEXT_PHASE_BRIEF 58, 2026-10-15, after run
`2026-10-14_2347_sqot-dev`: the engine's own weights written after the mod's FILL restores replaced by the town's phase
(young / blend / mature / densify) up to the era's top level, a refill after each restore, densify drawn from half grown
in the dev Simulate too; 6.3 "LEVELS by maturity").
Then the supply-driven district weighting (NEXT_PHASE_BRIEF 66, 2026-10-15: "Town growth: By deliveries", each
town's R/C/I mix follows its deliveries through the initial capacities, the sum kept; 6.2 "Supply-driven district
weighting"), the game-street lock with valves (67) and small follow-ups (68, 2026-10-15: the dev Quick moves the
calendar by default, the coupled seeded decisions drawn independently, company towns reach ~1.7 km, the game-street
lock's rebuild cost booked back; 6.2 "Small follow-ups (§68)"). Then the steering lock (NEXT_PHASE_BRIEF 69,
2026-10-15, after run `2026-10-15_1936_sqot-glprobe`: many streets locked, chiefly early and where direction matters,
the inside left to the game's own fill as the town matures, locked branches with open tips, no bare spikes, bridges
with a target, no rakes or wiggles; 6.2 "Steering lock policy (§69)").
Rev 2 (2026-10-17, player report on rev 1: streets built while the game was paused, and a new game at $0 went into the
red): the driver's clock stops while the game is paused and nothing new starts then, and every mod build's charge is
booked back (6.2 "Pause and refunds (rev 2)").

**Open decisions for the user** (each also under its section):
- **Deep forest towns can be the biggest town on the map** (§68 note, no change): Dovemouth-in-the-Forest reached
  1122-1260 buildings on seed `a` (runs `2026-10-15_0629_sqot`, `0759`; its site's game growth about x10). Deep mode
  shapes the streets (winding, groves kept, forest edges locked) but does not hold the size. Options: leave it (a big
  forest town is plausible), cap its growth (a lower target or a stronger forest hold once it is the map's biggest), or
  pick deep towns only among the smaller half of the map's towns. 6.3 "Deep forest towns".
- **New towns' starting mix is not evened out** (§66): the brief's "less random variation for new towns" would need
  lowering a district below what is built (untested in game: could it demolish?). Left as the game makes it. 6.2
  "Supply-driven district weighting", "Starting sizes".
- **Every mod build is free: no player in the context** (rev 3, 2026-10-17; findings towns.md "A script street
  build without `ctx.player` is free and unowned"). The refund (§68, rev 2) stays for a build that is charged anyway (the dev
  toggle "Build as player" on). Seen in game: 35 builds in a $0 new game, no charge, no crash, the new streets
  not `PLAYER_OWNED`. 6.2 "Small follow-ups (§68)", "Pause and refunds (rev 2)".
Next: TESTING.md "Climate-led names", "Bridge stops", "Names from the map's
shape" and "Seed a run" (seed text `a`
from now on), then one true-vanilla run on `a`; "Angle split run" and "Addendum after the 0119 run" / "Round after the
2355 run" stay open.

# Organic Towns (`square_organic_towns`): plan

**Working pages:** the mod's microsite (`site/`, `make site-media && make site-dev`, then
http://localhost:4321/square_organic_towns/; plans/site/PLAN.md): map comparisons (from `compare/<dir>/data.json` and the
shots, written by `compare/build_compare.py`), the Name lab, street-plan previews. The builders write data only. Name lab data: `uv run plans/square_organic_towns/names/export_names.py
[--session <name> | --log <path>] [--seed-text X]` (the mod's inventories and constants, the game's town lists, Lua
golden names for the port check, a map's NAME lines) into `names/data.json` (gitignored). The site's Name lab
(`site/src/mods/square_organic_towns/namelab/`: the TypeScript port `gen.ts` of ot_placename, the five generator ideas,
lists, constants, ratings, export) is checked against Lua by `node plans/square_organic_towns/names/check_port.mjs`.
The old disk page (`names/index.html`, `lab.js`, `gen.js`, `check_port.js`, `data.js`) still exists while its
"Whole map (plan)" mode is in work; once that settles, port it to the site and delete the old page (since
NEXT_PHASE_BRIEF 60, 2026-10-15, gen.ts is the port and `node plans/square_organic_towns/names/gen_js.mjs` writes
gen.js from it; check_port.mjs also runs the s53 rules' golden runs, `golden53`). Street-plan previews: `tools/ot_preview.py` also writes
`svg/previews.json` (style, terrain, variant, shape, region per SVG) for the site's filters and style x terrain matrix.

Towns keep growing in a street pattern that fits the map's region, climate, terrain, era, size and transport:
a sprawling axis-aligned grid in the US, an irregular radial core with rings in Europe, contour-hugging lanes on
Mediterranean hills, fine-grained dense blocks in Japan. **Ongoing styled growth is the core**; a styled start is a
side effect. Facts and citations: RESEARCH.md. Open questions: PROBE.md (Phase 1).

## 1. Principles

1. **Lead, don't fight the engine.** The C++ town developer stays responsible for buildings and parcels. The mod adds
   street increments in style just before a town runs out of room, so the developer fills our streets instead of
   inventing its own. How much engine street growth is left on is a mode (section 5).
2. **Plain base streets only.** Every edge uses a base town template (`town_{old,new}_*`), no mod resource is ever
   referenced by the world (no mod `.con`, no mod street template). Removing the mod leaves ordinary streets.
3. **Stateless where possible.** Style, axis and seed are derived from data the save already has (town entity,
   position, name, config dict, existing streets). Saved state is only optional per-town overrides.
4. **Pure geometry, thin engine layer.** All planning is pure Lua modules testable offline; the engine layer only
   reads snapshots and sends proposals.
5. **One command in flight**, small increments, hard per-frame budget.
6. **Character from the site, not the region (2026-10-13, user).** "It's less important to break towns up by JP,
   Nordic, American, old Europe etc., and more important to just have character variation of towns and have them
   respond to their terrain and surroundings ... unique-looking towns that follow terrain and factory influence." So
   variation lives in a town's form / shape / density and gaps, decided first by its terrain and surroundings (slope,
   valley, ridge, coast, lake, river, industries, neighbours, map edge); where the land is neutral, the seeded draw plus
   neighbour diversity (ot_diverse) varies it. Regional style ids change only lightly; never push a town into a foreign
   regional style just to differ.
7. **Towns follow the landscape; no default disc (2026-10-13, user).** "I still wish cities were more spread out around
   the landscape, not just radiating from the centre. Hugging coastlines more often is probably not a bad idea." A town
   grows along what its land offers: the shore, the valley floor, the hillside's contour (Middlewich's one long street up
   the hill: "very cool"), ridges, river banks and the country roads out of town (ribbons), and in lobes with meadow
   between; a round clustered town is one outcome among many, not the default. Realism stays: houses keep up with the
   streets (housed front, own empty budget, lead limits), the map edge is respected, no empty spurs. Measured per town:
   SHAPE / ALLTOWN `spread=` (ot_metrics.landSpread).

## 2. Architecture

```
inputs (per town, cached) ──► style resolver ──► StyleParams
   nameList, climate, year,         (ot_style)        │
   terrain stats, size, stations                       ▼
scheduler (GUI Main Thread) ─► assess town ─► snapshot graph ─► planner ─► terrain fit ─► precheck ─► send
   round-robin, budget         (needs room?)  (octree in bbox)  (ot_grow_*) (ot_terrain)  makeProposalData   1 in flight
```

### 2.1 Modules (`mods/square_organic_towns/content/organic_towns/`)

| Module | Pure? | Job |
|---|---|---|
| `ot_rng.lua` | yes | Hash RNG: `seed(townId, posX, posY, edgeCountBucket)`; no saved RNG state; `unit` is affine in its inputs (equal-length labels give one draw shifted, §64), `draw` (2026-10-15) the non-linear one for the offshoot decisions |
| `ot_style.lua` | yes | Style profiles (data) + `resolve(inputs) -> StyleParams` |
| `ot_inputs.lua` | yes | Region from `nameList`, climate id → enum; era band from year; size tier from capacities |
| `ot_graph.lua` | yes | Snapshot model: nodes, edges, degree, dead ends, frontier, dominant axis (orientation histogram mod 90°), centre, radius |
| `ot_terrain.lua` | yes (sampler injected) | slope along a path, gradient/contour heading, water clearance, coast/river direction from water samples, shoreline trace (lake / pond / island / open); the 2 km wide survey (since §62 with its 16 rays' points for ot_land) |
| `ot_grow_grid.lua` | yes | Next ring/strip of blocks on the town axis; arterial every N blocks; suburban loops/cul-de-sacs |
| `ot_grow_organic.lua` | yes | Radial spokes, ring roads, irregular infill (jittered, curved, T-junction bias) |
| (contour) | yes | Contour-following streets: no module of their own (planned `ot_grow_contour.lua` never built; 2026-10-13 M3 doc fix): the organic grower's `contour` weight (ot_grow_organic) and the shapes' hillside contour (ot_shape); switchbacks are motif phase M4 |
| `ot_form.lua` | yes | Town form (2026-10-12, Showcase v8 round): clustered / radiating / sprawling / linear / wide / fingers per town on top of the style (character); pick from dev / saved frame / site-picked shape / seeded draw; shape, block, front, sector, meadows |
| `ot_shore.lua` | yes | Waterfront streets (2026-10-12, shore towns): promenade along the traced shoreline at the setback, a row of small blocks behind it (shore towns), the plan cut at it |
| `ot_crescent.lua` | yes | Crescents around a green (2026-10-12, Showcase v9 round): the master plan cut at a crescent meadow, arcs around it between the crossings, one side open |
| `ot_industry.lua` | yes | Away from industries (2026-10-12): the industries near a town from the map's list, heavy / medium / light by file name, era weight; penalty field, buffers, arm exposure for the shape axis, `ind=` / `indPen=` texts; (2026-10-18) player facilities (harbors, airports, heliports, depots / maintenance stations, freight-only stations: `FAC_KINDS`, `classifyFacility`) as a soft list `info.soft` in the cost penalty only (`pen`), never a zone or hold (`penHold`), `fac=` text |
| `ot_indstreets.lua` | yes | "Streets at industries" (2026-10-13): preRunFn writes `baseConfig.locations.makeInitialStreets` (Off: false, Game default: untouched), INDSTREETS line |
| `ot_satpace.lua` | yes | Staggered offshoots (2026-10-14, 6.3 "Staggered satellites"): per-town readiness milestones, map-wide slots by the map's growth (and game years; SPACE_B 850 since §64), a seeded draw among the ready towns (`rng.draw` since §64), refunds, pod growth cadence, the saved `sp` record; SATPACE lines |
| `ot_satellite.lua` | yes | Satellite villages (2026-10-13; since §64, 2026-10-15, no new seeds (ot_driver `STREET_SAT` false): only a save's existing satellites grow, and the dev tools' forced hamlet): who gets one (seeded, grown towns), the site 0.65-1.2 km out (dry, gentle, away from heavy industry, nearer this town, by a road; 0.8-1.5 km until 2026-10-14 late), one link (since 2026-10-14 late a winding locked country lane, `curvedLink`, at most MAX_LINK 900 m, no straight run over 150 m) + a compact core (dosed at the seed build), growth by a block from its own dead ends, meadow discs along the link |
| `ot_roads.lua` | yes | Country roads around a town (M2, 2026-10-13): traced from the snapshot outward (engine reads beyond it), junctions with their owner town, forks, road segments (style.roads); the road edges also read wide around the town (template `country` flag; the snapshot missed them), virtual roads toward the neighbours when there is none (final-test round) |
| `ot_motif.lua`, `ot_motif_land.lua`, `ot_motif_road.lua`, `ot_motif_town.lua`, `ot_motif_relief.lua`, `ot_motif_point.lua` | yes | Town motifs (M0-M4, 2026-10-13): the registry and pick (0-2 per town, saved on the frame), the terrain / water kinds (hill climb, valley fishbone, harbour crescent, fishing village), the road / village kinds (ribbon village, village green, crossroads hamlet), the town-structure / era kinds (ring road, station quarter (derived, extra), workers' terraces, cul-de-sac pods), more terrain (switchbacks, ridge street, headland street, bridgehead quarter (derived, extra)), the peninsula tip (final-test round: the spit search, a street out along it with a cluster at its tip) |
| `ot_upward.lua` | yes | Upward density (later-ideas phase, 2026-10-13): who is an upward town (>= 1500 buildings, or >= 700 with 3 held demand plans, or 250+ under 4.5 persons per building; no metropolis), the demand increment's cut (0.2-0.5), the core points along main streets where houses stand (DevelopAt with upgradeBuildings, restored exactly after); since 2026-10-14 late the town-wide level weights (`levelDecide` / `levelWeights`: strength from persons per building, a player's own weights never touched; driver LEVELS); since 2026-10-15 by maturity (`levelMat` / `levelPhase` young / blend / mature / densify, a signed tilt, `eraTop`, owner `fill` via `editorLike`, `share1`: a hold never lowers a town) |
| `ot_meadow.lua` | yes | Protected meadows (later-ideas phase): lobe headings of sprawling / unarmed character towns, meadow sectors between them beyond the core zone (no mod pieces; ot_select `meadowHeld`), the meadow frame's tip filter (ot_wedge.frameStreets `accept`, no tails) |
| `ot_entry.lua` | yes | Tree-lined town entries (later-ideas phase; off since 2026-10-18, `M.ON = false`: plain streets only): the `_trees` variants of the town templates, which new streets are entry streets (along a country road's first 320 m out of town, or wide at its entry), seeded per town |
| `ot_poly.lua` | yes | Polycentric next steps (later-ideas phase): the grid cores of a polycentric metropolis's secondary centres laid into the master plan (ot_motif_town.layGrid), METRO `cores=` text; centre placement at junctions / third centre / core kinds live in ot_metro |
| `ot_forest.lua` | yes | (deep forest round, 2026-10-14: mode deep, `deepPick` / `ringShare` / `deepStyle` / `groveCells` / `inGrove` / `lotSpend` / `windStats`, `M.k` deep values, saved `fd`; 6.3 "Deep forest towns") (§71: `woodSizes` / `bigWoodAt` / `bigWoodNear` / `bigWoodBy`, woods of at least `WOOD_MIN_HA` for the steer lock's face rules) (round after the names run: `facesForest`, a hug town's new streets facing the forest locked; the clearing budget's windows per decade or 1.5x growth, the tier's total, spent at the build) Forest-aware towns (phase F, 2026-10-13): the tree grid per town (50 m cells within 1.5 km, from ot_engine.forestReader), the mode per town (hug / clear / none: seeded, era, size, style, character), the planner's forest cost / hold / edge premium, `forestCut=` / `forest=` texts; R1 (2026-10-13): the corridor (centreline + both sides' lots to 36 m + the band beyond), the clearing budget per town and decade, `forestLot=` / `forestBudget=` |
| `ot_land.lua` | yes | The landscape pull (§62, 2026-10-15; 6.2 "Landscape pull"): one angular field per town from the tree grid, the wide survey's rays and the disc's water (forest / steep push, open land pulls hardest, along the water, never across), style factors, the lean at a heading, lobe order, LAND / `land=` texts |
| `ot_skeleton.lua` | yes | The landscape-aware skeleton (§63, 2026-10-15; 6.2 "Landscape-aware skeleton"): per arm of a shaped town a clearance survey against dense forest (both sides' lots, ahead), bend / shorten / drop / boxed, longer reach for open arms, the saved `sk` text; hotspot moves for unshaped towns and the satellite sites' forest clearance; SKEL texts |
| `ot_lockpol.lua` | yes | The steering lock (§69, 2026-10-15; 6.2 "Steering lock policy (§69)"): the town's built outline, the lock maturity (§70: persons, size, age) and its inner zone, per street lock or open (facing forest / water / neighbour / lean, arms while young, out / rim / fill; §71: only big woods face forest, `smallWood`), the game-street rule, the lead cap and the continuous arm front, policy texts |
| `ot_knot.lua` | yes | Knot look rules (§70, 2026-10-15; 6.2 "Steering lock policy (§69)", "§70"): on the curves, a new piece crossing a street off a shared node, running beside one for long, or closing a loop under half a block (ot_select M.KNOT, steer towns); §71 hooks: a dead-end street curling over 120 deg or back by its own street (`hook`, ot_select M.HOOK); §75 (6.2 "Side streets and parallel streets (§75)"): the parallel run over the whole street through a piece (`chainBehind`, `streetLine`, `graphAt`, `parallelRun` options), `text` with `side`; one empty row at a time (§75 follow-up, 2026-10-19: `ROW`, `rowM`, `rowNeed`, `emptyOurs`, knot reason `row`); the empty-row measure (2026-10-20: `emptyRows`, `rowsText`, SNAPSHOT `emptyRows=`) |
| `ot_prov.lua` | yes (console part: engine reads) | Street provenance (§75 follow-up, 2026-10-19; 6.2 "Side streets and parallel streets (§75)" "Follow-ups built"): the source of each built edge (`source`), the saved record (`entry` / `parse` / `append` / `add`, ot_saved `pv`), lookups (`find`, `nearest`, `describe`) and the console helper `who()` |
| `ot_nearmiss.lua` | yes | Close the gap (§74, 2026-10-17; 6.2 "Close the gap (§74)"): near-miss dead ends (a street within 80 m ahead) joined to a node ahead (a bend to another dead end, a T / crossroads at a street node the driver allows), shapes (line, arcs, Hermite; §75 a pair's `corner`), place / planner / curve checks (§75 `parallelKnot` over the whole street), the seeded chance by gap, woods kept (§75 `woodRun`: only through a big wood), the cap, `merge`, the near-miss share (tests) |
| `ot_rci.lua` | yes | Supply-driven district weighting (§66, 2026-10-15; 6.2 "Supply-driven district weighting"): the base game's usage weights (`usage`), smoothing, the aim with floors, the step (initial sum kept, built floor, ceiling, total cap, no overshoot), the lean and its draw multipliers, the RCI texts |
| `ot_lane.lua` | yes | (deep forest towns, 2026-10-14: DEEP_P 0.67, DEEP_MAX_PER_TOWN 8, `maxFor`) Forest lanes (R2, 2026-10-13): stretches of an increment wooded on both sides to lot depth go out as locked `country_{old,new}_small` (no houses), seeded ~1 in 3 (hug more, clear fewer, later eras fewer), MAX_PER_TOWN; FORESTLANE lines. Round after the names run: one stretch of ONE plan line (no block-interior lines `bk` / `sr` / `q` / `conn`, no side streets inside, town streets at both ends, 2+ edges, 60-400 m), hug towns' held crossings freed as a bundle (`free`, ot_select laneBundle) |
| `ot_lead.lua` | yes | Country lanes laid ahead (round after the names run): who (seeded 30 % of towns of 60-1500 buildings, map quota 25 %), where (toward a neighbour / the satellite / the shape axis / the frame axis, 250-600 m beyond a dead end at the edge (400-1000 m and straight until 2026-10-14; now curved, none for a town with a district), short of the gap line, dry, gentle, not along a road), the streets (the locked country lane + a town-street T or ribbon at the far end), the marking; LEADLANE lines |
| `ot_works.lua` | yes | Industrial satellite towns "Works" (round after the names run; 2026-10-14: 2/3 of the way to an industry within 3 km when there is one, named by its kind, the link through ot_link): who (new maps only, >= 300 buildings, seeded 35 % (`rng.draw` since §64), quota one per 8 towns, max 3, with the districts at most 4 per 16 towns (ot_driver OFF_PER16), never a character or Works town), where (0.8-1.5 km, harbour / rail / across water best, dry, gentle, gap / character / neighbour rules, room, a reachable link line; §64 `landScore`: wooded surroundings / link worse, the §62 lean's heading better), the name per list language (through ot_offname since NEXT_PHASE_BRIEF 47), the link road (country middle between two joined town-street ends); WORKS lines |
| `ot_stopname.lua` | yes | Unique stop names (round after the names run; 2026-10-14: street sections and their variants, 28 characters at most): per list language (en, usa, de, nl, sv, nb, fr, it, es, pt, ja, ja_r, ru, ru_r) a generic per theme x a specific part from the spot (toward a neighbour town, trees by species, works / quarry / farm, the theme's features, compass, height, the own town; Russian size / age pairs), real list names first, a seeded jitter per stop, unique map-wide (`uniq=`); 2026-10-14: bridge stops first (`SN.BRIDGE`, `bridge=` on STOPNAME) |
| `ot_district.lua` | yes | District towns (round after the 2355 run, 2026-10-14): who (new maps, >= 300 buildings, seeded 60 % (`rng.draw` since §64), 1-2 per town, quota one per 4 towns), where (a site feature 0.6-1.5 km out: hilltop / terrace, shore, across water, the lane ahead's end, valley head, since §64 a country crossroads ("cross") and plain open land ("open", the lowest kind); the forest clearing kind dropped after run 0119; the landscape terms of ot_works.landScore; the Works' site rules incl. the forest test), the name (through ot_offname since NEXT_PHASE_BRIEF 47: composed per language from the site, its water and the compass, never a real list name), caps 200 / 30 / 10, `orphanOf` (the load check's lost creates); DISTRICT lines |
| `ot_link.lua` | yes | The robust link road between two towns' dead ends (2026-10-14): many pairs, detours round streets / fields / zones, never doubling back at a dead end, best routes first (the driver plans them in turn until both ends join); Works and district links |
| `ot_gap.lua` | yes | Gaps between towns (R3, 2026-10-13): new streets stop 150-300 m (seeded per pair) short of the halfway line to a neighbour's centre; twins' main roads go on to the line; never past it or on land the engine gives another town; PLAN `gapHeld=` / `gaps=` |
| `ot_metro.lua` | yes | Metropolis city style (2026-10-12): who becomes one, variants (grid / radial / corridor / oldcore / polycentric), style copy, lock / fill per variant, density per centre |
| `ot_names.lua` | yes | Landscape names (2026-10-13): the 18 base name lists (languages, classifier per folder), name tag rules per language (en, usa, de, fr, it, es, pt, nl, sv / nb, ja, ja_r, ru, ru_r), the pool (sliced classification, tag buckets), town site tags (`townTags`), the assignment (rarest tags first, unique, seeded per map, plain / kept / random, satellite "Little X"), industry prefix renames; stop themes and the real list names per theme (`stopThemes`, `stopCandidates`; the names themselves: ot_stopname since the round after the names run) |
| `ot_placename.lua` + `ot_placename_lang.lua` | yes | Generated names (2026-10-14; 6.3 "Generated names"): fine site tags with specificity (`siteTags`, the cheap `read`), per-language inventories (stems / generics / affixes, dialects, rare forms, classes), scoring and joining rules, the blocklist, river / lake systems and their names, the map assignment (unique, seeded, satellites), related district names and industrial Works names; `langOf` (nil: the game's names, NEXT_PHASE_BRIEF 49); since NEXT_PHASE_BRIEF 49 also the Landscape names, with the climate (`ot_climate`) and `agreeSurvey` |
| `ot_mapshape.lua` | yes | The map survey for names (2026-10-14; 6.3 "Names from the map's shape"): the whole map on a coarse grid (<= 128 x 128 cells, height + water each), sliced and capped per phase: rivers as a network (forks, mouths, bends, falls, upper / lower course), the big lake, peaks and the range, the main valley, bays, capes, narrows, isthmus; `townCues` (cue tags per town, its river component, compass side, lake side) |
| `ot_offname.lua` | yes | Offshoot names (2026-10-14; 6.3 "Satellite and Works name variety"): Works by the industry's type (`indType`), the site and the survey's cues in parent / company / cue / generic patterns, districts by the site kind, height, compass and water (`readWater`: sea, sandy, lake, river), suffix keys counted map-wide (each once per map while others fit, no sibling twice), seeded class shares, `listName` for lists without a classifier, `usedText` (the NAMES offshoot line), `parentForms` (orphanOf); 14 classifiers |
| `ot_climate.lua` | yes | The climate fit of names (2026-10-14; 6.3 "Plausible, climate-led names"): `key` (tropical / dry / subarctic / temperate), generator tag vetoes and site tags per climate, `wordMisfit` (a finished name's words a climate rules out, per language), `lakeMisfit` (lake words of stop names, 2026-10-14) |
| `ot_namewords.lua` | yes | The map's word budget (2026-10-14): generic landscape words per list language (`WORDS`, keys such as lake / forest / woods / -see / -wald / 湖 and the compass), at most one per 8 towns, never twice within 5 km (SOFT words twice / half), Landscape names also whole repeated words; tag rarity; landscape cue words (`CUES`: North / Upper / Forks / Falls / Mount ...); `clean` (list disambiguators) |
| `ot_card.lua` | yes | The town window's Organic Towns card and the new-town notification (rev 4, 2026-10-17; 6.2 "Town window card and new-town notification (rev 4)"): the display model from a polled input (`view`: five sections), the driver's per-town summary (`summary` / `summaryMoved`), name origin codes (`originCode` / `originOf`), the notification's dedupe, params and texts; the ID lists mirrored from ot_character / ot_form / ot_motif / ot_upward (test_card checks them) |
| `gui/ot_card.res.lua` + `gui/ot_card.script.tl`, `notify/ot_new_town.res.lua` + `.script.tl` | no | The card plugin (`::TownEowExtensionPoint`, order 45; state_native reads, the town's components) and the notification type (rev 4) |
| `ot_plan.lua` | yes | Polylines → node/edge specs: split to ≤ maxSeg, snap to existing nodes, min angle/length, the §75 side-street angle (`sideAngle`, off by default; steer organic towns' plans and the near-miss joins pass 60), no crossings, z and tangents, every `-0` → `+0` |
| `ot_engine.lua` | no | Reads (octree, components, parcels, terrain sampler adapter), builds `SimpleProposal`, precheck, send, verify; (2026-10-18) `facilities()`: player depots and station constructions with cargo / passenger flags (reads verified by console 2026-10-18, docs/findings/lines-vehicles.md; airports not yet); `sentN` (events sent, 2026-10-20: the state reader's watch) |
| `ot_driver.lua` | no | Scheduler, budget, cooldowns, SQPERF lines, log `[SQOT]` |
| `organic_towns.gs.lua` + `.script.lua` | no | Game script: `guiUpdate` drives (GUI Main Thread), engine `update` only for optional per-town state |
| `mod.script.lua` | no | `runFn`: `rawset(_G, "SQOT_CONFIG", configDict)`; `preRunFn`: global angle knobs by detected region |

Offline tests: `tests/square_organic_towns/test_*.lua` for every pure module (graph fixtures, terrain samplers as
functions: plane, slope, ridge, river trench, coastline).

### 2.2 Input layer → StyleParams

| Input | Source | Effect |
|---|---|---|
| Region | the "Town style" setting when it names a region (2026-10-14, NEXT_PHASE_BRIEF 55; `regionSource=setting`), else the `nameList` path: `square_names_us_*`, `::/names/usa` → US; germany/france/england/netherlands/poland/europe → EU central; italy/spain/portugal → MED; norway/sweden → NORDIC; russia → RU; japan → JP; korea/china → EAST_ASIA; asia → ASIA (the pan-Asian list, its own mixed bias, 2026-10-14); oceania → US-like grid with wider lots | base profile |
| Climate | style bias x the region's (`ot_site.CLIMATE`): `dry` → MED hill towns / ensanche up, Nordic down; `subarctic` → NORDIC up, MED down, blocks x1.2; `tropical` (2026-10-14) → suburbs / extension / organic up, the dense compact styles down, blocks x1.15, spreading forms (`ot_form.CLIMATE`) and the shore form more often | modifiers |
| Terrain stats | sampled once per town in a 600 m disc, 24×24 grid: mean/95th slope, water fraction, water side (coast/river normal), relief direction | contour bias, axis rotation, setbacks |
| Era | year bands: <1850, 1850-1920, 1920-1950, 1950-1980, ≥1980 (TF3 starts in 1900 at the earliest: the first band never applies; 6.3 "Era range 1900+") | template old/new, block size, suburban loops, superblocks |
| Size | total person capacity: <500, <2000, <6000, ≥6000 | hierarchy depth (arterials), ring count |
| Stations | `getTown2StationsMap` + station position | main street toward the station, denser weights near it |
| Existing streets | dominant axis + its strength | grid axis = existing axis (never rotate an existing town); organic styles keep existing radials |

Region detection falls back to climate only, then to "EU central" (the base default name set is europe).
A mod param can force a style for all towns. Later: per-town override from the town window.

**"Town style" setting** (mod param `style`, was "Street style"; 13 languages; values appended, saved indices keep
their meaning; `ot_params.STYLE_REGION`):

| Index | Value | Effect |
|---|---|---|
| 1 | Automatic (default) | region from the name list, else the climate (`regionSource=nameList` or `climate`) |
| 2 | North American grid | every town NA_GRID (`forceGrid`, `forceStyle`); the region still from the name list, as before |
| 3 | European organic | region EU |
| 4 | Mediterranean | region MED |
| 5 | Nordic | region NORDIC |
| 6 | North American suburbs and grid | region US (the regional mix, not the forced grid) |
| 7 | East Asian | region EAST_ASIA |
| 8 | Japanese | region JP |
| 9 | Mixed | region MIXED (setting only): every style weight 1 (`ot_site.REGION`), metro variants alike, core grid 0.45, angle 25 |

A setting region (`regionSource=setting`) drives every region-dependent bias: the site's style weights (`ot_site`),
metro variants and core grids (`ot_metro`), `pickProfile`, and the vanilla street angle when "Vanilla town street
angles" is Automatic (`ot_angles.region(s, styleRegion)` in preRunFn). The site still decides within the region's
bias, the climate bias still multiplies. Names follow the name list (`inputs.nameRegion`, the driver's `nameRegion`
for `nameCls`). The name list's country rides along only when it is the chosen region's own (a Spanish map set to
Mediterranean keeps the Spanish ensanche rule). Towns with a saved frame keep their style.

### 2.3 Growth loop

1. **Scheduler** (`guiUpdate` or HUD `onStep`, whichever probe I picks): every ~2 s real time take the next town
   (round-robin over `getEntitiesWithComponent(TOWN)`), at most one assessment per tick, ≤ 0.5 ms Main Thread per
   frame (slice longer work over frames with a coroutine and Clock checks).
2. **Assess "needs room"**: target = Σ `initialLandUseCapacities[i]*sizeFactors[i]`; actual =
   `getLandUsePersonCapacities`; free frontage = parcels without building on town edges (probe J decides the cheap
   way). Needs room when actual/target < 0.9 **and** free parcels < X % (both on two consecutive checks), or when
   the planned "ahead" margin (style param `leadBlocks`) isn't reached. Cooldown per town: ≥ half a
   `townDevelopInterval` of game time between increments. *(Original design. Now: growth demand, the target's rise
   since the town's last build, held back while our own streets wait for houses; room only below that: 6.3
   "Growth-demand trigger".)*
3. **Snapshot**: octree `BASE_EDGE` in the town bbox + 250 m, street edges only, with templates, nodes, degrees.
4. **Plan one increment** (≤ 24 edges, ~1-3 blocks or one ring segment): pick frontier sides by cost (slope, water,
   distance to centre, station pull, existing arterial), generate per style, clip against water and steep cells,
   reject crossings with any edge/track (later: make T-junctions only on our own fresh edges).
5. **Join**: connect to the existing network only by the safe variant probe D finds (dead-end extension or T on a
   segment). Until then: only at dead ends, never at nodes with 2+ edges.
6. **Fit terrain**: z from `getHeightAt` per node, pieces ≤ 40 m on slopes, tangents from neighbours; drop pieces
   above the template's `maxSlope` (read from `streetTemplateRep`) or the style's own limit.
7. **Pre-check** with `makeProposalData` (`checkTerrainAlignment = true`): on collision drop the offending edges
   (and what hangs off them) and retry once; else skip the side for this cycle.
8. **Send** `makeWorldBuildProposalCmd(p, ctx, false, false)` (`playerInitiated = false` → no reputation effect),
   one in flight, verify by edge diff, log one `[SQOT]` line.
9. **Density**: when a town's style or size tier changes, send `makeTownCustomDistributionWeightsCmd` once (only if
   the "density by style" param is on; it overrides a player's custom weights, so off by default for existing towns).

## 3. Styles (data, `ot_style.lua`)

Shared parameter schema (lengths in m, angles in degrees):

| Param | Meaning |
|---|---|
| `block = {len, depth, sd}` | block size between street centres, Gaussian spread `sd` (fraction) |
| `gridness` | 0..1, chance a new street continues straight / meets at 90° |
| `jitter` | heading noise per street |
| `curve` | max tangent change per edge (curvature) |
| `radial = {spokes, ringEvery}` | radial streets and ring spacing, or nil |
| `arterialEvery` | blocks between arterials (large template), collectors at half |
| `templates = {local, collector, arterial}` | base template names per era (`old` before ~1925, `new` after; the engine's own `availability` applies) |
| `deadEnds` | share of cul-de-sacs (post-1950 suburbs) |
| `maxSlope`, `contour` | street grade limit; 0..1 bias to follow contours instead of the axis |
| `waterSetback`, `waterfront` | min distance from water; build a street parallel to the shore |
| `stationPull` | 0..1, priority for growth toward a station, main street to it |
| `lead` | blocks of empty street kept ahead of demand (sprawl vs compact) |
| `ribbon` | 0..1, growth along arterials vs compact rings |
| `angleRange` | value for `townMajorStreetAngleRange` (preRunFn) when this style dominates the map |
| `weights` | 3x4 level weights (res/com/ind x level 1-4) for `makeTownCustomDistributionWeightsCmd` |

| Style | block len×depth (sd) | gridness / jitter / curve | radial | arterial | slope / contour | lead / ribbon | angleRange | weights (res L1-4) |
|---|---|---|---|---|---|---|---|---|
| **NA grid** (US, oceania) | 200×100 (0.05) | 0.98 / 0 / 0 | – | every 8 blocks (≈1 mile) | 0.12 / 0.1 (grid climbs hills, SF style) | 2 / 0.6 | 0 | 1, 0.6, 0.3, 0.1 (core 0.3,0.6,1,0.8) |
| NA suburb (≥1950 band, outer ring of NA grid towns) | 150×90 (0.25) | 0.4 / 10 / 25 | – | collectors only, loops | 0.10 / 0.5 | 2 / 0.3 | – | 1, 0.3, 0, 0 |
| **EU organic** (DE/FR/UK/NL/PL) core | 60×45 (0.4) | 0.3 / 15 / 20 | 6 spokes, ring 300 | spokes + rings | 0.10 / 0.5 | 1 / 0.2 | 30 | 0.3, 0.8, 1, 0.5 |
| EU 19th-c. extension (EU organic towns' outer ring from 1915, outside first ring) | 110×80 (0.15) | 0.8 / 4 / 5 (axis per spoke sector) | rings continue | every 5 | 0.10 / 0.3 | 1 / 0.3 | – | 0.2, 0.6, 1, 0.8 |
| **MED hill town** (IT/ES/PT, or dry+EU, slopes > 8 %) | 40×30 (0.4) | 0.2 / 20 / 30 | 3-4 spokes uphill to a centre | spokes | 0.10 hard / 0.9 | 0 / 0.1 (compact) | 45 | 0.1, 0.4, 1, 0.6 |
| MED ensanche (ES flat, ≥1920) | 113×113 (0.02) | 1.0 / 0 / 0 | – | every 6 | 0.06 / 0 | 1 / 0.2 | 0 | 0, 0.2, 0.8, 1 |
| **JP dense** | 50×35 (0.3) | 0.6 / 5 / 8 | – | every 6; main street to station | 0.12 / 0.6 | 1 / 0.5 (along rail) | 10 | 1, 0.9, 0.3, 0.2 (station core 0.2,0.5,1,1) |
| NORDIC (NO/SE, subarctic; v9) | cells 190×150 (0.12): cluster loops, cul-de-sacs 0.42 deep, 30 % green cells | 0.6 / 6 / 20 (loops bowed 0.12 x cell) | – | every 3 cells | 0.10 / 0.8 (fjords) | 1 / 0.6 (valley ribbons) | 10 | 1, 0.7, 0.2, 0 |
| RU/EAST ASIA superblock (≥1950) | 350×250 (0.1) inside: free-form | 0.9 / 2 / 0 | – | every block | 0.08 / 0.2 | 1 / 0.3 | 0 | 0, 0.2, 0.6, 1 |

Since the Showcase v9 round (2026-10-12) the profiles also carry: `mech` (metropolis mechanics at a smaller scale: lock
every new street, `maxEdges` per increment, dosed fill beside any new street; NA grid / NA suburb / ensanche 28 edges,
superblock 30 without the fill), `housedLead` (housed front, blocks: NA grid 1.5, NA suburb / ensanche 2, superblock /
Nordic 1, polycentric 1.5), `emptyBudget` (polycentric 2000 m), `crescents` (EU organic 2, EU extension / MED hill /
Nordic 1, metropolis 1 park) and `cluster` (Nordic). NA grid shapes: compact 3, lens 1, cross / linear 0.75; Nordic:
fingers 2, linear / compact 1.5, fan 0.5.

### 3.1 What you should see (per style, v9; the user judges the shots against these lines)

- **Across the landscape (2026-10-13, round 5):** few round blobs; coast and lake towns as long strips along the water
  (about two in five, most on islands), valley towns along the floor, towns on a road out of town ribboning along it,
  sprawling towns in lobes along their roads with meadow between; two to four separately named offshoot towns per 16
  towns (Works and districts) about a kilometre out, founded over the years (§64, 2026-10-15; the streets-only satellite
  villages before that).
- **Hill road (2026-10-13, round 5; Middlewich, session `2026-10-13_0342_sqot`):** a hillside town drawn linear along
  its contour (SH.HILLSIDE_GAIN 1.2) grows its arm along the slope, climbing where the contour bends (Middlewich's arm
  reached 829 m). SHAPE `hillRoad=len/climb/houses`; MOTIF `kind=hill_road src=derived`.
- **Motifs (M1, 2026-10-13; drawn: 0-2 per town, seeded, saved on the frame; MOTIF lines, PLAN.md 6.3 "Motifs M1"):**
  - *Hill climb* (towns on a slope or in a valley, the user's Middlewich favourite made deliberate): one street leaves
    the town up the easiest climb (about 5.5 % or less, bending along the contour where the slope is steeper, never a
    hairpin), built a few pieces per round as the houses follow it; 1-3 small loops (two short lanes and a street along
    the shelf) on flatter shelves beside it; no other streets in a ~70-100 m corridor along it beyond the town, so the
    steep ground between the terraces stays green and the street reads as one road up the hill with houses along it.
  - *Valley fishbone* (towns on a valley floor): a main street along the floor through the town, both ways, and short
    straight lanes up both slopes every ~80-140 m, each stopping where the slope gets steep (dead ends); nothing else on
    the valley sides near it.
  - *Harbour crescent* (towns at a bay, a concave sea or lake shore): a curved waterfront street ~37 m from the water
    around the bay, short dead-end streets inland off it every ~55-90 m, a dense row of houses facing the water (the
    build's DevelopAt dose on the land side of the new crescent streets), only the plan's through streets reaching it
    from the town; no promenade elsewhere (it replaces ot_shore's).
  - *Fishing village* (small towns, < 2000 people, on a shore sloping down to the water; more before 1950): beside the
    core along the shore a waterfront street and 3-4 narrow parallel streets straight up the slope (~45-80 m apart,
    120-260 m long, stopping where it gets steep), nothing else in that block.
  - At most one of hill climb / fishbone and one of harbour / village per town; none on flat land; old saves none.
- **Motifs (M2, 2026-10-13; roads / villages, on the country roads traced around each town; PLAN.md 6.3 "Motifs M2"):**
  - *Ribbon village* (small / medium towns on a country road, more before 1950): a street beside the road out of town
    ~32-45 m from it, 450-750 m long, a row of houses between it and the road facing the road side, 2-4 short dead-end
    lanes off its far side, meadow behind; its streets locked (no game side streets on them).
  - *Village green* (small / medium towns on gentle land, more before 1950): 240-400 m from the centre a lens-shaped
    green (the street splits around it and joins again) or, where two roads fork out of town, a triangle along them;
    houses around it, the middle left as meadow (no mod street inside, the town's streets meet it head on), locked.
  - *Crossroads hamlet* (a crossroads of country roads 0.45-1.6 km out, nearer this town; any era): the satellite
    village seeded beside it (90-170 m from the junction, in the quadrant facing the town), with its own link street
    from the town beside the road (the road can't be joined); from 120 buildings, no seeded draw. Since §64
    (2026-10-15) no street satellite is seeded (only the dev tools' forced hamlet); a crossroads within 250 m of a
    district site makes it a "cross" district instead (named like a lane's end).
  - At most one of ribbon / green per town; none without a country road; none in cities (tier 4) or metropolises.
- **Motifs (M3, 2026-10-13; town structure / era; PLAN.md 6.3 "Motifs M3"):**
  - *Ring road* (old organic cores: EU organic / extension / MED hill towns of 500+ people with houses 140+ m out, on
    gentle land; an early-game motif: full to ~1940, about half as likely by 1975): a curved street around the core where its walls would have stood,
    just beyond the core's dead-end streets (radius picked once, saved on the frame), each radial street running straight
    on into it (a short stub, head on), medium where gentle; outside it the 19th-c. extension districts, straighter
    (the grid look) than the core. Where the town's streets cross the circle, or water, steep ground, a country road or
    the map edge lie on it, only the arcs between two radial streets are built (no full ring, no street split mid-edge).
  - *Station quarter* (any town except a metropolis, from the moment the player builds a rail passenger station within
    ~800 m of its houses; it appears in later sessions too, the stations are re-read every 2 minutes): a small straight
    grid of 3 x 3 or 4 x 4 blocks on the station's forecourt side (its front, local -Y), squared to the station, a station
    square street along its front, a straight Bahnhofstrasse from the town to the grid; nothing across the tracks; a
    forecourt facing away from the town gets its grid there without the Bahnhofstrasse (the tracks lie between).
  - *Workers' terraces* (to ~1935, fading to none by 1950; a light works, i.e. a factory such as a food plant,
    textile mill or brewery, never a farm, 120-900 m beyond the houses with no heavy / medium works within 450 m): a
    short straight street from the town toward the works and 3-5 short parallel rows (narrow streets ~40-50 m apart,
    ~140-200 m long) square to it near the works, dense houses in single rows; the away-from-industry preference doesn't
    apply to them (it still does to every other street).
  - *Cul-de-sac pods* (from ~1950, EU extension / NA suburb / Nordic / EU organic / NA grid and other later towns on
    gentle land): a gently curving collector out of town 380-560 m, 3-6 short dead-end closes (60-110 m) off alternate
    sides, plain dead ends (no turning heads), meadow behind them, streets locked.
  - Ring / terraces / pods share the towns' two motif slots with the M1 / M2 kinds (one per group); the station quarter
    comes on top (since M4 it takes no slot: a town with a station draws the same motifs as without).
  - Satellites (all): a site beside a crossroads or beside a farm / light works scores better; heavy / medium works
    still keep them away. No mod street crosses a country road beyond the town (the traced roads block plan pieces).

- **Motifs (M4, 2026-10-13; more terrain; PLAN.md 6.3 "Motifs M4"):**
  - *Switchbacks* (towns on slopes of ~6.5-10 %+, too steep for the hill climb's gentle street, with ground somewhere
    gentle enough for a bend): beside the town a street climbing in long legs along the slope (~5 %), joined by 2-4
    tight hairpin bends (80 m radius), houses clustered at the bends, the slope between the legs left green.
  - *Ridge street* (towns on a crest): one street along the top of the ridge through the town, houses on both sides, a
    few short dead-end lanes down the flank only where it is gentle, the steep flanks green.
  - *Headland street* (towns above a cliff coast, 8 m+ high, within ~550 m): a street along the cliff top ~40 m inland
    of the edge, a row of houses on its inland side facing the sea, short lanes inland, nothing between it and the
    cliff, no promenade below.
  - *Bridgehead quarter* (river towns once their bridge stands): a small square grid on the far bank, squared to the
    bridge, its first row the bridge's cross street continued straight on; takes no motif slot (like the station quarter).
  - At most one of hill climb / fishbone / switchbacks / ridge street and one of harbour / village / headland per town.
- **Neighbours (2026-10-13, ot_diverse):** towns within ~5 km of each other mostly differ in form / shape (one clustered,
  the next long, sprawling or radiating); the same regional style next door is fine. Valley, ridge, river and coast
  towns still follow their site even beside a town of the same form.

- **NA grid:** straight streets on one axis, rectangular 200 x 100 m blocks laid out as whole blocks from the first
  rounds along the game core's edges, a wide arterial every ~6 blocks and collectors every 2 (from 1950); houses in
  rows along every street, no organic side streets off ours (locked); a compact or rectangular town, not arms.
- **NA suburb:** the grid's frame with gently curving local streets, cul-de-sacs on every other cross street, larger
  blocks and 3 meadows; low density (mostly level-1 houses); grows in whole blocks (locked, 28 edges).
- **EU organic:** an irregular radial core, 6 spokes and rings, small 60 x 45 m blocks with bent lanes, T-junctions;
  2 crescents (a long curved street wrapped around an open meadow, short streets meeting it, denser blocks outside)
  and another meadow; from 1900 an extension zone beyond ~300 m.
- **EU extension:** the 19th-c. extension: straighter, larger 110 x 80 m blocks between the spokes and rings, an
  arterial every 5 blocks; one crescent; arms as deep strips in shaped towns.
- **MED hill:** tight 40 x 30 m blocks on contour-hugging lanes, 4 spokes uphill to the centre, xsmall streets,
  compact (ridge on crests); one crescent along a contour.
- **MED ensanche:** a strict square 113 m grid (Barcelona), wide arterials every 6 blocks from 1950, dense (level
  3-4); grows in whole blocks, locked.
- **JP dense:** fine 50 x 35 m near-grid blocks, xsmall / small streets, a main street toward the station, every block
  filled (no meadows), clustered / radiating / sprawling / linear forms differ in outline.
- **Nordic:** curving collector loops around ~190 x 150 m cells, each with short dead-end streets reaching into it
  (small clusters of houses), about a third of the cells left as open green inside their loop, 4 meadows (one with a
  crescent), low density (level 1-2), fingers / strips along valleys and coasts (Scandinavian post-war suburbs,
  Copenhagen's Finger Plan, Stockholm's green wedges). Not a plain grid, not an organic core.
- **Superblock:** 350 x 250 m arterial cells (alternating arterial / collector lines) laid out early, each cell filled
  with local streets (two along the axis, staggered short cross streets), dense level 3-4; locked, 30 edges.
- **Shore towns** (any style, a seeded share of the towns on a sea or lake shore; more on islands and right at the
  water): a long, shallow strip along the water that follows the shore's curve (bays, lake shores, around an island)
  both ways from the town, a waterfront street ~37 m from the water (medium on gentle shores, small where it bends),
  behind it a row of small blocks (a parallel back street one short block inland, cross streets every ~50-120 m), the
  style's own streets only 2-4 blocks inland; it stops at headlands / cliffs and never goes onto the water. River towns
  still grow along their banks; ponds do nothing. Other new coast / lake towns get the waterfront street and build near
  the water first; a coastal metropolis keeps its corridor along the shore.
- **Metropolis** (any style, big flat towns): grid = the American grid look (straight locked frames with house rows
  and open block interiors), radial = spokes / fingers, corridor = a long band, oldcore = organic centre with gridded
  districts, polycentric = a main town growing toward a second centre with no empty arterials ahead of the houses.

- **From day one** (any style, 2026-10-13): on a new map each town's first streets draw its form: long towns two arms
  along the axis, finger / radiating towns their spokes, shore towns their strip, sprawling towns loose patches,
  clustered towns tight blocks; never more than ~280 m beyond the houses (no empty spurs), 2-5 small rounds by size and
  form. No street within 400 m of the map edge; arms point away from a near edge.
- **Character towns** (any style, 2026-10-13): on every map the most secluded ~15 % of the towns (at least 1-2; far from
  other towns, near the map edge, sometimes island towns) look drastically different: sprawling in loose clusters with
  fields and meadows between them (much larger blocks, leapfrog patches), or very long and narrow, spidery fingers, or a
  long shore strip. STYLE `character=yes:...`.
- **River towns** (2026-10-13): a seeded ~75 % of the river towns (also towns with narrow water within 1.5 km), once
  grown (~150 buildings), build one street bridge across the river at a narrow point (<= 160 m of water) with a T on the
  far bank, and a quarter grows there (since M4 the bridgehead quarter's small grid).
- **Organic vs gridded** (2026-10-13; era range 1900+ since M4): a 1900-1910 start is organic (no grid trend yet, no
  ensanche before 1920, the EU organic town's straighter extension ring only from 1915); from ~1910 planned / gridded
  towns (ensanche, NA grid, later suburbs and superblocks) and straighter extensions become more common, more after
  1950; an old town's outer districts turn straighter and start closer as the decades pass while the core keeps its
  lanes. Default (Organic) on a UK map: ~18 % grid-ish towns in 1900 (mostly the semi-organic extension style, true grids
  3 %), ~29 % in 1940, ~44 % in 1960, ~51 % from 1990 (offline mean of the 16 run sites); the "Town layout" setting moves
  it (1930: 14 % very organic -> 53 % very gridded).

- **Away from industries** (any style, 2026-10-12): new streets prefer the side of the town away from the industries
  within ~1.5 km; heavy works (steel mill, chemical plant, refinery, mines, quarry, saw mill ...) push harder and
  farther (500 m buffer) than medium (400 m) and light ones (food factory, farms: 320 m); a seeded shape axis turns its
  arms away; before ~1920 the pull is weaker. A preference only: a town with works on every side still grows (6.3
  "Away from industries"). Grid towns respond least (their housed front leaves few pieces to reorder).
- **Away from player facilities** (any style, 2026-10-18): the same lean, lighter, away from the harbors, airports /
  airfields, heliports, vehicle depots / maintenance stations and freight-only stations the player builds near a town
  (6.3 "Away from player facilities"). Never a keep-clear zone or a hold; passenger rail stations and stops keep pulling.
- **Around the forest** (phase F, 2026-10-13; in-game tree read unverified): towns with dense forest around them (8 %+
  within 1 km) split into forest-hugging and clearing towns. Hugging (seeded; ~80 % of small EU organic / MED hill towns
  in 1900-1920, ~20 % by 1990, fewer big towns, grids ~10 %, character towns more, a metropolis never): new streets keep
  to the open land, run out along clearings and meadows between the woods as fingers and follow the forest edge, the
  houses on the open side facing the trees; only when no open land is left do they cut into the forest, a few streets
  per build. Clearing towns (later, bigger, grids, metropolis) build straight through as before. STYLE / SHAPE /
  ALLTOWN `forest=<share>:hug|clear|none`, PLAN `forestCut=` (6.3 "Forest").

- **Big towns grow taller, not only wider** (later-ideas phase, 2026-10-13; the in-game effect of upgradeBuildings is
  unverified): from ~1500 buildings (or a 700+ town whose plans keep coming out held) the mod's demand streets shrink by
  a quarter to a half and every ~3-5 minutes three points in the core along its main streets, where houses already
  stand, get DevelopAt with upgradeBuildings; the town's growth target stays exactly where it was (no v5 runaway). Look
  for taller buildings in the core and a town that spreads less than before at the same population. UPWARD /
  UPWARD effect `perBuilding=`.
- **Meadows in sprawling and character towns** (later-ideas phase): a sprawling town (or a character town without arms,
  e.g. a shore character town) keeps one to four wedge-shaped meadows between its lobes (the roads out of town / its
  shore) beyond its core: the mod plans nothing there and locks short frame streets across the game's tips that face
  them. Look for green gaps between the clusters that stay green as the town grows. MEADOW, FRAME `kind=meadow`, PLAN
  `meadowHeld=`.
- **Plain streets only** (2026-10-18, user; first seen in game the same day, seed `a`: 0 ENTRY lines, PLAN `trees=-`
  everywhere, no `specialJoin`, plain grey streets in the shots): the mod's new streets never take a special variant (tram tracks, bus
  lanes, barriers, tree rows): tree-lined entries are off (`ot_entry.ON = false`), a joint at a dead end the player
  built as a variant takes the plain template with the dead end's lanes (`ot_proposal.plainPath`; another mod's street:
  the edge's own template, else refused `specialJoin`), and every new edge drops its copy source's decorations
  (ot_engine.proposal). The §67 lock rebuild still copies existing edges as they are. test_later "plain streets only".
- **Tree-lined entries** (off since 2026-10-18, see above; was: a seeded ~55 % of EU organic towns, fewer JP / Nordic, most metropolises):
  the mod's new streets along a country road's first ~300 m out of town (frontage streets, ribbon streets) and wide
  streets right where the road enters get the base game's tree-lined town street (`town_*_trees`: same lanes, a tree row
  on both sides, houses still built). The country roads themselves are never touched. ENTRY lines, PLAN `trees=`.
- **Polycentric conurbations** (later-ideas phase): a secondary centre sits at a crossroads of country roads 0.9-2 km out
  when one is in its direction, a third centre appears at ~30000 persons, and about half the secondary centres (US / JP
  more) grow their own small 3x3 / 4x4 grid downtown (off the crossing's roads, in the quadrant facing the town) instead
  of the plan's pattern, once the houses reach it. METRO `at=x:y@D:junction|ring:grid|plan`, METRO step `cores=`.

Terrain modifiers (applied on top of any style):

- **River**: water samples on one side in the snapshot disc → a street parallel to the bank at `waterSetback`
  (25 m); grid axis rotated toward the bank direction for new towns only; no bridges in v1 (later: arterials may
  bridge if `townConnectionMaxBridgeLength` style allows).
- **Coast / lake** (2026-10-12): the shoreline is traced (`ot_terrain.shoreline`); new towns with a form get a
  promenade along it at waterSetback + 12 m (`ot_shore`) and streets near the water first (`waterPremium`); a share of
  them become shore towns (above). Growth leans toward the water side (`irregular.coast`); grids align to the shore.
- **Hills**: `contour` weight blends the style heading with the contour heading (perpendicular to the gradient);
  above `maxSlope` switchbacks (≤ 2 per street) or stop. Hilltops in MED become the centre.
- **Valley**: relief direction from terrain stats → linear growth along the valley floor.

## 4. Engine interplay modes (mod param "Town streets")

| Mode | Engine | Our streets | Pros / cons |
|---|---|---|---|
| **Guide** (default) | development on | plain, unlocked; built ahead of demand | Safest; engine may still add its own streets at other dead ends and later widen ours (fine) |
| **Lead** | development on | our edges `roadDevelopmentLocked` | Engine can't extend/alter ours (probe F); it may still extend its own edges |
| **Own** | development on | additionally lock the town's existing edges at their dead ends only | Engine has nowhere to add streets, base growth script keeps sizing the town; costs: no auto-widening; needs "Release towns" before removal |
| Freeze (probe-only) | `SetDevelopmentActive(false)` + our own `UpdateSize` | – | Loses base growth/experience logic (`town_growth.script.tl:28,345`); only if probes show no other way |

Probes A, B, F decide which modes ship. Start with Guide, add Lead/Own only if probe F shows locking works as hoped.

## 5. Save safety (this mod changes the world, so `cosmetic: false`)

Reviewed 2026-10-14 before the first real-play test (TESTING.md "Real play (first)"); the old plan text here (a "Release
all locks" button, an Act on value "Paused", "no other saved state") described ideas that were never built.

- `severityAdd: "None"`, `severityRemove: "Warning"`. Nothing in the world references mod resources: every street,
  ring and bridge is a base-game town street template (the one-way rings `town_new_one_way_small`; square_roundabouts
  only lends its geometry math through its presence file), so removing Organic Towns or Roundabouts & Interchanges
  can't break a save's streets.
- **Saved state** (the game script's, `ot_saved`): one table, `v = 1`. `M.normalize` copies every known field through
  `tonumber` / type and length checks and drops the rest, so a missing field is nil and old saves load as "none yet":
  `known`, `fresh`, `nm` / `nd` / `rv` (names done, list folder, river and lake names), `sq` / `sb` (stop queue and
  street sections), `frames[town]` (axis, shape, style, form, motifs, `b0`, `ck`, `dz`, `og`, `lw` / `ls`, the pair
  `px py ph pr pn pk`, ...), `cm` (strong characters), `sp` (satellite pacing), `lb` / `lbs` (level baseline), `wk` /
  `wm` / `dk` (Works and district towns), `rev` (the change number handleEvent bumps with every set, 2026-10-20: the
  per-frame read copies the state only when it moved, 6.2 §75 "The saved state off the frame path"). All additive: an older save without `sp` counts from the towns' starting
  sizes, without `b0` from the frame's initial capacity, without `cm` gets no strong characters (`why=oldMap`), a frame
  without `og` keeps the even rings, without `pk` an older outward-only twin. Every apply in `handleEvent` is idempotent
  and capped (MAX_FRAMES 4000, MAX_KNOWN 20000, LEVELBASE_MAX 4000, WORKS_CAP 64, STOP_CAP 64, STOPBASE_CAP 300,
  WATER_CAP 32, CHARS_CAP 16, PACE_HIST 64). A mod `revision` bump doesn't touch it; only a change of `ot_saved.VERSION`
  would reset it (never do that: add fields instead).
- **Opt-in scope:** param "Act on": *New towns only* (default: towns that weren't there when the mod first saw this
  save; on a fresh map every town) / *All towns* / *Off* (the mod changes nothing, preRunFn included). Names,
  strong characters, Works / districts, the head start and level weights only on a new map (`newMap`).
- **Removal** (the game warns: severityRemove Warning): the mod's streets stay as plain town streets, the locked ones
  (arms, edges, grid / metropolis blocks, forest edges) stay `roadDevelopmentLocked` (the player's lock tool can edit
  them), the renamed towns, rivers, stops and industries keep their names, Works and district towns stay ordinary
  towns, and the level weights the mod set stay with their town (the town editor's custom weights: a lasting effect,
  the description says so). The saved table stays in the save, unread. Never remove a mod with a save loaded.
- **Left-hand traffic** (2026-10-20, user report with Left Hand Traffic `left_hand_traffic_1`): the driver reads the
  driving side once per session from the loaded base town templates (`ot_engine.driveSide`, `ot_proposal.leftHandFrom`;
  log `DRIVE side=`) and mirrors every node config it writes (`junctionConns` leftHand); the counter-clockwise one-way
  rings stay off (`rbGeo` "leftHand", `PR.build` refuses one-way edges `leftHandOneway`). Junctions built before the fix
  stay as they are unless a new street joins them (that node's config is rewritten in full); no repair pass. Open:
  clockwise rings for left-hand traffic. In game: `2026-10-20_2051_lht-seed-a` (findings roads.md "Left-hand traffic").
- Never touches player-owned edges, stations, tracks, constructions, or nodes with 2+ edges. Never bulldozes
  buildings: precheck `collisionInfo.buildingEntities` must be empty.
- Money: builds go out with the player in the context and are charged (2026-10-11); since rev 2 (2026-10-17) the
  driver books every charge back (min(balance drop, cost), street construction income; no setting). 6.2 "Pause and
  refunds (rev 2)".
- Pause: nothing is built while the game is paused (rev 2): the driver's clock is running time (GAME_SPEED.speedup 0
  stops it), so its pacing and timeouts stand still too.

## 6. Phases

1. **Phase 1: DEV probe mod `square_organic_towns_probe`** (never uploaded, English only): PROBE.md. Output: findings.md
   entries, mode decision, driver context, join variant, cost numbers.
2. **Phase 2: pure core + tests**: `ot_rng`, `ot_inputs`, `ot_style` (profiles above), `ot_graph`, `ot_terrain`,
   `ot_plan`, `ot_grow_grid`. Tests with fixtures; a dev script renders planned increments to SVG for eyeballing
   (`plans/square_organic_towns/svg/`, not shipped). **Done 2026-10-11**, see 6.1.
3. **Phase 3: MVP mod, NA grid only, Guide mode**: driver, assess, snapshot, plan, fit, precheck, send; "Act on" param;
   SQPERF; `[SQOT]` log. In-game test on a US-names map and a flat test map. Translations for params (13 languages).
   **Built offline 2026-10-11, in-game test pending** (TESTING.md), see 6.2.
4. **Phase 4: EU organic + MED + JP + terrain modifiers** (`ot_grow_organic`, `ot_grow_contour`), station pull,
   preRunFn angle knob by region.
5. **Phase 5: Lead/Own modes and density weights** (if probe F/K allow), "Release all locks".
6. **Phase 6: polish**: NORDIC/RU/EAST ASIA profiles, era transitions inside one town (old core → new rings), town
   window plugin for per-town style, cover + slides, description, release.

### 6.1 Phase 2 status (2026-10-11)

Pure modules in `mods/square_organic_towns/content/organic_towns/` (plain Lua, pre-5.3, no `api.*`, loaded with
`ug_require "square_organic_towns::/organic_towns/<file>.lua"`). Mod scaffold only: `mod.json` severity None/Warning,
no params, `strings.json` skeleton, modinfo name/summary in 13 languages, no cover; not linked or released.

| Module | Public functions |
|---|---|
| `ot_geom` | `z0`, `round`, `clamp`, `lerp`, `dist`, `len`, `wrap`, `angleDiff`, `lineAngleDiff`, `heading`, `rot`, `pointSegDist`, `segIntersect`, `polyLen`, `polyAt`, `polySplit`, `resample`, `simplify`, `smoothNoise`, `atan2` |
| `ot_rng` | `hash(...)`, `seed(townId, x, y[, bucket])`, `unit(...)`, `new(seed)` → `:next/:range/:int/:chance/:normal/:pick/:fork` |
| `ot_inputs` | `region(nameList)` → region, country; `climate`, `era`, `newTemplates`, `sizeTier`, `regionFromClimate`, `build(raw)` |
| `ot_style` | `PROFILES`, `IDS`, `profile(id)`, `pickProfile(inputs)`, `pickOuter`, `templatePath`, `resolve(inputs)` → StyleParams, `zone(style, d)` |
| `ot_graph` | `new`, `addNode`, `addEdge`, `fromSnapshot`, `degree`, `deadEnds`, `other`, `headingFrom`, `edgeLength`, `centre`, `radius`, `dominantAxis`, `bbox`, `nearestNode`, `edgesNear`, `distToEdges`, `crossing`, `connected`, `frontier`, `apply` |
| `ot_terrain` | `sampler(heightFn, waterFn, waterLevel)`, `height`, `isWater`, `gradient`, `slope`, `contourHeading`, `downhill`, `grade`, `pathMaxGrade`, `wetAlong`, `clearance`, `stats(s, cx, cy, r, n)` |
| `ot_plan` | `plan(graph, streets, opts)` → increment, `shape`, `edgeCount`, `noNegativeZero` |
| `ot_select` (new) | `select(graph, masterPlan, style, opts)` → streets, report; `classify`, `matchJunctions`, `junctionIndex`, `alongGraph` |
| `ot_grow_grid` | `masterPlan(style, opts)`, `planFor`, `extentFor`, `matchShare`, `grow` |
| `ot_grow_organic` (done early) | `masterPlan(style, opts)`, `planFor`, `extentFor`, `grow` |
| `ot_core` (new) | `planIncrement(graph, style, opts)` → increment, report, plan; `masterPlan` (cached), `grower`, `simulate` |

Increment (what Phase 3 turns into a `SimpleProposal`): `nodes = {{entity, x, y, z}}` (new nodes only),
`edges = {{entity, node0, node1, p0, p1, t0, t1, class = main|medium|small, template = base template path, length}}`,
`joins = {{node = existing id, edge = entity}}`, `dropped = {{street, reason}}`. Entity ids follow the Stress Test
convention (edges -1..-E, then nodes); node0/node1 are new entity ids or positive existing node ids; tangents have
chord length with z; every number rounded to mm and `-0` → `+0`.

How it works: each grower builds a deterministic **master plan** for the town (junction points shared exactly by
plan pieces): a jittered lattice on the town axis (grid styles; NA suburb outer zone with cul-de-sacs and bent
cross streets; a lattice line on the shore setback for new waterside towns), or spokes + an inner ring at 0.45 R +
rings every R + infill lanes with T-offsets (organic; spokes turn to keep within the grade cap on hills).
`ot_select` matches the plan against the snapshot (built: an edge chain runs along the piece; blocked: an
existing street near/through it; excluded: water/setback or too steep), then grows greedily from the reached
junctions, cheapest piece first (distance, class x ribbon, station pull, slope, waterfront, loop closing), up to
24 edges. `ot_plan` turns the pieces into nodes/edges (snap, split ≤ 100 m flat / 40 m on slopes, refuse
crossings, steep, wet, angles < 25 deg, short pieces, unconnected parts) and `ot_core` reruns the selection
without refused pieces (up to 4 rounds).

Tests: `make test MOD=mods/square_organic_towns`, 73 tests in 5 files (+ `fixtures.lua`: terrain samplers, network
invariants: one component, no crossings, min angle, edge lengths, on land, grade); also pass on Lua 5.2
(`TEALRT_LUA=52`). `make check` clean.

SVG preview: `uv run tools/ot_preview.py [-n 16] [--style ID] [--terrain ID] [--town N]` (driver
`tools/ot_preview.lua`, Lua 5.2 via lupa) writes `plans/square_organic_towns/svg/<style>_<terrain>.svg` for
NA_GRID, EU_ORGANIC, MED_HILL, JP_DENSE, NORDIC, MED_ENSANCHE x flat, hillside, river, coast, plus `previews.json`
(the site's street-plan section; `--manifest` rewrites only that).
Colour = increment (dark first), width = class, red dots = dead ends, purple = station.

Changes from the plan above:

- Template eras switch at **1940** (base `availability` of `town_new_*`/`town_old_*`), not ~1925.
- The rng seed for the master plan is `seed(townId, x, y)` without the edge-count bucket (the plan must not move
  as the town grows); the bucket only feeds per-increment tie-breaking (`incSeed`).
- New modules `ot_geom`, `ot_select`, `ot_core`; `ot_grow_organic` written in this phase; `ot_grow_contour` not
  written: MED hill uses organic growth with grade-capped spokes and rings around the hilltop, no switchbacks yet.
- Existing axis: the street axis is turned by a multiple of 90 deg toward the fresh axis (water/station/seed), so a
  grid we grew keeps its long blocks in the same direction.
- `ot_plan` takes `join = deadEnd | any | none`; `ot_core.planIncrement` defaults to `deadEnd` (in game until
  probe D), `simulate` and the previews use `any` (a grid without dead ends can't grow otherwise).
- `lead` is not used by the planner (increment size is fixed at 24 edges); it is for the Phase 3 driver's
  "needs room" test; in the planner it only widens the plan extent.
- Engine (non-plan) towns: the grid plan anchors a lattice node on the node nearest the centre when < 50 % of the
  town's junction nodes match the fresh plan; unmatched dead ends get a connector piece to a free junction within
  0.75 block. Untested against real snapshots (Phase 3).
- Not yet: superblock interior lanes, suburban loops, organic waterfront streets, bridges, the `weights` usage
  (only stored), river/valley ribbon bias.
- Planning time offline (Lua 5.4): 2-7 ms per increment for a 700-edge town; building a master plan 3-6 ms, cached
  per style table (weak keys) with a margin of max(400 m, 50 %) and rebuilt when the town outgrows it. Phase 3
  should keep the StyleParams table per town so the cache works, and slice if a frame needs it.

### 6.2 Phase 3 status (2026-10-11, offline; in-game test: TESTING.md)

Phase 2 preview fixes (HANDOFF): strict grids (`gridness` >= `ot_style.STRICT_GRID` 0.9) get no junction jitter and
no bent suburb pieces; NA suburb cul-de-sacs only on even cross lines (share 0.35 -> 0.2); grid line spacing and
organic infill (`ot_grow_organic.stripCount/laneCount`) never below `ot_style.MIN_BLOCK` = 40 m (two 2-cell lots of
8 m back to back + street; 44 m since 2026-10-18, 6.2 "Wider minimum block"); grid selections drop dangling small streets (`ot_select.prune`, not for organic
styles, kept when it would empty the increment). NA grid preview: 23 -> 7 dead ends after 16 increments. SVGs
regenerated. EU outer rings still look ragged mid-growth (Phase 4).

New planner rules found with the fake engine town (test_driver): new nodes keep `clear` = 6 m off existing
streets and new edges 6 m off existing nodes they don't connect to (`blockedNode` / `nearExisting`); an engine
dead end missing a plan junction by < 2 x snapR (16 m) stands in for it (`report.adopted`), else gets a connector.
`ot_plan.joinable` honours `node.noJoin`; `ot_select` excludes pieces ending at non-joinable nodes (`nojoin`);
edges carry their plan piece `key`; `ot_core.planIncrement` takes `opts.exclude`.

New modules (all in `content/organic_towns/`):

| Module | Pure? | Job |
|---|---|---|
| `ot_params` | yes | mod params -> options (runtime values are 1-based indices) |
| `ot_saved` | yes | per-save state: known towns (New towns only), plan frame per town; idempotent event apply; the change number `rev` (`bumpRev` / `revOf`) and the per-frame `Reader` (2026-10-20, 6.2 §75 "The saved state off the frame path") |
| `ot_assess` | yes | extent from building positions, free / virtual lots, needs room, round-robin scheduler + cooldowns; the main body of the houses (`body` / `bodyFields`, 2026-10-20, 6.2 §75 "Far-out streets after an extent jump": CHECK `rBody=` / `r50=` / `out=` / `outFar=`; the frame tip cap's reach) |
| `ot_proposal` | yes | increment -> proposal spec: copy sources, D3 joint, config-remove rule, -0 |
| `ot_driver` | logic (engine injected) | state machine, one stage per tick, `[SQOT]` log |
| `ot_engine` | no | api reads, SimpleProposal, pre-check, send, events, grow |
| `organic_towns.gs.lua` + `ot_gs.script.lua` | no | game script: update subscribes, handleEvent writes state (and bumps `rev`), guiUpdate ticks the driver with the Reader's copy (a full copy only when `rev` moved, read through the GAME_SCRIPT component's `state_native`; fallback to a copy every frame) |
| `mod.script.lua` | no | runFn: `SQOT_CONFIG = {nameList, climate}` (replaces the Teal stub) |

Decisions:

- **Driver context: game-script `guiUpdate`** (Main Thread). Only there do both proven facts hold: runFn's
  region global is visible (not in GUI plugin states) and commands get callbacks (not in engine `update`). **No
  stylesheet**; since rev 4 one read-only GUI plugin, the town window's card (6.2 "Town window card and new-town
  notification (rev 4)"), which reads the saved state and never drives anything. One stage per tick (assess, terrain once per town, snapshot, plan, send, wait), one
  town check every 3 s, 6 s pause after a build, one command in flight, 30 s callback timeout. guiUpdate also runs
  while the game is paused: since rev 2 every one of these times is running time (real time with the paused stretches
  left out, `Driver:gameClock`) and a paused tick starts nothing (6.2 "Pause and refunds (rev 2)").
- **Gate:** the map's profile (from runFn's nameList/climate) must be `NA_GRID` (US, Canada rules added, Oceania)
  or the "Street style" param (now "Town style") forces it; otherwise one `INIT on=false` line and nothing else.
- **Needs room (trigger, revised 2026-10-11 after the first in-game run):** see "Trigger" below. Cooldowns: built
  90 s, room 30 s, empty 240 s, skip 600 s, fail 120 s doubling to 30 min.
- **Snapshot:** street edges within building extent (90th percentile) + 300 m. Dead ends are joinable only with a
  true degree of 1 (`getNodeStreetSegments`), a plain town edge (not owned, no stops, no construction, even lanes
  >= 4, no one-way), a BASE_NODE_CONFIG, and the closest town = this town. Own config-less dead ends are never
  joined (`ot_driver.ALLOW_NO_CONFIG = false`).
- **Plan centre / seed:** the town's bounding-box centre (fixed, unlike its extent). **Saved plan frame** (axis +
  lattice origin) per town after its first build, so later increments and reloads keep the same grid (the only
  saved data besides the known-town list).
- **Proposal:** edges copy a town edge with the era's template (town_old_* < 1940 <= town_new_*) or a small town
  edge with the template overridden; edges at a joint copy the dead end's own edge (one lane layout at the node).
  Context **without player** (town streets; the BUILT line logs the balance to confirm), `playerInitiated = false`,
  not player owned, unlocked. Pre-check refused -> re-plan with half the edges down to 3, then the first piece is
  excluded (session memory); a build refused by the engine excludes all its pieces.
- **Testing param** "Testing: grow towns faster" (makeTownUpdateSizeCmd x1.25 every 40 s, cap 8): removed in rev 3
  (2026-10-17, player report "towns develop without any player input"); growth for tests comes from the dev tools
  (Simulate natural growth, Grow now / Grow town only).
- SQPERF not added; timings are in the debug `CHECK`/`SNAPSHOT`/`PLAN` lines (`us=`).

**Trigger (revised 2026-10-11, first in-game run).** The first rule (free lots + virtual lots, inner half x 0.5,
below max(min, built x share), halved at the capacity target) never fired: all 16 fresh towns of a US map logged
`needsRoom=false`, e.g. Dickinson `buildings=162 edges=52 free=527 virtual=14 room=499.50 built=457 need=91.40
cap=856/870`. A fresh town meets 98 % of its capacity target with about half of its 984 lots empty, and those gaps
stay empty: the developer doesn't fill them when its target rises, it extends streets (probe Grow here: Beccles at
sizeFactors 1 -> 2 doubled its buildings with +76 % streets; its lots were 37 % built at target). So the free-lot
count measures the engine's lot slicing, not room. The developer does use **open frontage**: lots on our own
streets before adoption (virtual, 1 per 12 m) and free lots on edges that are still mostly empty (built below
`OPEN_FILL` = 25 % of their lots; inner half x 0.5). Free lots on fuller edges count as `gaps` (weight
`GAP_WEIGHT` = 0). New rule (`ot_assess.needsRoom`): build when open frontage < max(min, built lots x share), the
unchanged lookahead thresholds (12/24/40 lots, 10/20/35 %; increments 12/18/24 edges); a hungry town (capacity <
`CAP_HUNGRY` 0.9 of target: its target just rose) wants x1.5 of it; a town over `CAP_OVER` 1.1 of its target
(shrinking) gets none. Dickinson-like towns now fire once (test_assess "fresh town at its target"), and an
unadopted 18-edge increment (~150 virtual lots) holds the next one off until the town fills it. The CHECK line
shows `free open openEdges gaps virtual built need cap capRatio why`. `OPEN_FILL`/`GAP_WEIGHT`/`CAP_*` are
first guesses: tune them from the next run's CHECK lines (the share of edges under 25 % is not known yet).

**Dev window layout (2026-10-12).** The OT Dev window follows the Stress Test window: status, queue (Stop, Pause)
and progress at the top, tabs Simulate / Showcase / Town / Main mod / Camera & tour (remembered per session), green
"go" buttons (`colorDefault.Ok`; the old `Positive` was blue), check boxes for options (`otd_hudview.lua`,
TESTING.md "Dev tools").

**Dev hooks (2026-10-11).** For the DEV mod `square_organic_towns_dev` (never uploaded; TESTING.md "Dev tools"):
`ot_hooks` (one table per Lua state, never saved: `paused`, `devBusy`, `debug`, `main`) holds the driver (no new
checks, no testing growth; a running job finishes) and overrides the debug log; without the dev mod the fields keep
their defaults. `ot_driver` was split for reuse: `loadConfig`, `measure` (one town's numbers without scheduling),
`startJob(t, now, {force, styleMode, dry, maxEdges, onDone})` + `advance` (the stages, one per tick; `tick` uses
them too), style modes (`main` as before, `region`, or a profile id with its era's outer zone: `ot_inputs`
`keepOuter`), a dry run that stops after the pre-check (`DRY` line), per-instance `prefix`, `verbose` and
`allowNoConfig`, and a per-town `history` of built increments (edge ids found by matching both ends of each spec
edge after the callback; `BUILT … found=N`). Tests: 117 in 8 files.

Tests: 110 in 8 files (+37: test_fixes, test_assess, test_proposal, test_driver with a fake engine town).
`make check`, `make i18n --check --lint-modinfo` (19 keys, 13 languages) and `make validate` (only the missing
cover) pass. `make link` done.

Deviations from the plan: no density weights, no station pull in game (stations not read), no two-consecutive-
checks rule (cooldowns + virtual lots instead), no frame-sliced planning (one stage per frame; planning measured
offline at 2-7 ms), Lead/Own modes and "Release locks" still Phase 5.

**Curves (2026-10-11, after EU organic was refused in game every time).** In game the NA grid built, but every EU
organic increment (18 down to 3 edges, ~25 m edges) was refused by the pre-check with `Construction_Not_Possible`,
no collisions. New pure checker `ot_check` (Hermite curve radius, tangent vs chord, angles between actual
tangents at nodes, kinks where one plan line continues) over `ot_core` simulations of every profile x 4 terrains
(10 increments): before the fix EU organic had 43/60/50/32 edges under 70 m (flat/river/coast/hill; worst 6.3 m),
EU extension 9-32 (worst 2.9 m), MED hill 43-69 (worst 3.7 m); grids none. Cause: ot_plan gave a curved
street's end edges the chord as tangent at the piece end but a Catmull-Rom direction at the inner node, both of
chord length; on the short pieces the organic plan cuts at its many junctions this made a cusp-like curve (a 19 m
ring piece with 21.6 deg at one end: R = 13 m). The templates allow 44 m (`minCurveRadius`, "final proposal") /
60 m (`minCurveRadiusBuild`). Also: 3-point bent lanes (a 30 m lane with a 13 deg bend: R 33 m), a 67 m inner ring
on MED hill, unsmoothed spoke vertices (contour turns on slopes), and breaks of up to 26-45 deg at degree-2 nodes.
Fix: plan lines are smooth curves of >= 80 m that carry their exact unit tangent per point (`ot_geom.smoothLine`
= relax corners + widest fillets, `polyDirs`, `frameAt`, `hermitePts`, `polySplit` keeps directions); spokes steer
at most 10 m / 90 m per 10 m step (and keep their side of the gradient on slopes); ring arcs are polar curves
(smoothstep radius blend + sin^2-weighted noise, halved until >= 80 m) that leave and reach the spokes square to
the centre, so neighbouring arcs share one tangent; inner ring >= 100 m. `ot_plan.streetPoints` cuts curved
streets evenly by arc length (<= maxSeg, a node every 40 deg of turn, tries 3 counts for the widest result),
tangent = curve direction x arc length, angles measured with tangents, and drops an edge still under
`MIN_RADIUS` 70 m (reason `curve`). Jittered grids: a lattice node gets one tangent (chord bisector) when the half
kink fits L / (6 x 80 m), else it stays a corner. After: every profile x terrain passes (minR 70-125 m, min angle
>= 25 deg, no kinks; test_check), ~same edge counts, organic planning 5-9 ms per increment in Lua 5.2 (was 2-7).
Unverified in game: whether the engine really applies 44 or 60 m to script proposals, and whether kinks/corners at
degree-2 nodes matter (the NA grid with corners builds).

Dev diagnosis (`ot_hooks.diagnose`, on while the dev mod is loaded): a pre-check refused with
`Construction_Not_Possible`, and every dry run, is followed by a `diag` stage that pre-checks each new edge alone
(`ot_proposal.single`: the edge with its new nodes, a join edge with its D3 joint), 6 per tick, and logs the first
6 failures (`DIAG`, with the checker's numbers) and `DIAGSUM`; PLAN lines carry the checker summary. Player:
`ot_hooks.player` (nil/true = context with the player, the known crash-free setting, which charged the player
537k in game; false = without, dev toggle "Build as player" for the crash bisect); SEND/DRY log `player=on|off`.
Tests: 136 + 18 (test_check: checker, smoothing, every profile; test_driver: player, diagnosis, organic styles on
the fake engine town).

**Irregular growth (2026-10-11, SHOWCASE_BRIEF).** Towns grew as even rings: `ot_select` picked frontier
pieces by distance from the centre (plus class / station / slope / waterfront terms). Now each profile has an
`irregular` table (`ot_style`: `sector`, `lobes`, `ribbon`, `hotspots`, `pull`, `coast`) and the cost
(`ot_select.cost`, resolved once per style by `ot_select.irregularity`) is: distance / (block x s(theta)) with a
seeded angular preference s = 1 + sector x f(theta) (1-3 cosine harmonics, phases from the town seed; coast towns
blend in cos(theta - waterDir), `ot_style` sets `waterDir` for coasts), times (1 - R x corridor) with corridors
along the master plan's main (1) / medium (0.5) pieces (spatial hash, Gaussian of width 0.75 block, R = ribbon x
gain <= 0.6: ribbons along arterials and spokes), times (1 - pull x Gaussian) around seeded hotspots 3-6.5 blocks
out, the first in the favoured direction (leapfrog patches reached along a main street; NA suburb 2, JP dense 1).
`style.irregular = false` restores the old cost (baseline for the tests and `ot_preview.py --even`).
New pure module `ot_metrics` (also logged for real towns by the showcase): drift (centroid offset / mean radius),
spread (max / min of the 8 sectors' 90th-percentile radius), cv (street length per sector), elong (principal
moments). Flat land, 12 increments, mean of 4 towns, even -> irregular (test_shape):

| Style | drift | spread | cv | elong |
|---|---|---|---|---|
| NA grid | 0.03 -> 0.08 | 1.19 -> 1.32 | 0.20 -> 0.23 | 1.06 -> 1.22 |
| NA suburb | 0.05 -> 0.30 | 1.12 -> 1.64 | 0.15 -> 0.35 | 1.06 -> 1.24 |
| EU organic | 0.01 -> 0.13 | 1.05 -> 1.54 | 0.05 -> 0.30 | 1.02 -> 1.49 |
| EU extension | 0.02 -> 0.12 | 1.08 -> 1.55 | 0.07 -> 0.24 | 1.02 -> 1.42 |
| MED hill | 0.05 -> 0.24 | 1.11 -> 1.40 | 0.08 -> 0.25 | 1.04 -> 1.12 |
| MED ensanche | 0.03 -> 0.05 | 1.16 -> 1.23 | 0.15 -> 0.18 | 1.03 -> 1.18 |
| JP dense | 0.04 -> 0.39 | 1.21 -> 1.95 | 0.13 -> 0.42 | 1.13 -> 1.18 |
| Nordic | 0.04 -> 0.32 | 1.17 -> 1.44 | 0.11 -> 0.36 | 1.10 -> 1.13 |
| Superblock | 0.06 -> 0.09 | 1.18 -> 1.33 | 0.22 -> 0.26 | 1.05 -> 1.28 |

Tests assert: uneven styles spread >= even + 0.2 and cv >= 1.4 x even; grids spread above even but < 1.7, drift <
0.25; one connected network; a Nordic coast town leans toward the sea. The geometry checker (test_check) still
passes for every profile; planning time unchanged (~same edge counts). SVGs regenerated for all 9 styles x 4
terrains (`svg/`, plus `*_flat_even.svg` baselines; dashed circles = hotspots, metrics in the header). Known,
older than this change: Superblock grows nothing on the river and hillside previews (350 m pieces cross the river /
exceed its 8 % grade from the start junction); Blank Slate is flat, so the showcase is not affected.

**Landscape pull (2026-10-15, §62; NEXT_PHASE_BRIEF 62; in game: TESTING.md "Combined test iteration" step 11).**
The seeded preference above never read the land beyond the town (the forest acted per piece only, in hug / deep
mode), so towns pushed streets into the woods on one side while open land on the other stayed empty (HISTORY.md
2026-10-15 US names run). `ot_land` builds one smooth angular field per town (16 sectors) from readings the driver
already has, no new engine reads: the tree grid (`stats.forest`, mean cover of the ring r0..1450 m, r0 = max(300,
1.1 x the town's extent) <= 1000 m, so the trees its own streets cleared don't count), the wide survey's rays
(`ot_terrain.wide` now keeps them: 16 rays x 500 / 1000 / 1500 / 2000 m; mean grade along each ray up to its first
wet point, uphill full, downhill x 0.6, no push under 2.5 %, full at 9 %; wet points; points within 100 m of the map
edge count as wet) and the disc's water (`stats.water`: a river or shore the 500 m ray steps miss; its side wet
cos^3 x 0.6, its bank / shore axis pulls cos^2 x 0.8 both ways; none for a pond, no wet side for a river within 60 m
of the centre). Per sector F = 1.0 open - 0.8 forest - 0.9 steep + 0.6 shore, with open = (1 - forest) (1 - steep)
(1 - wet) and shore = the dry sector's pull from wet neighbours 1 / 2 / 3 sectors away (1 / 0.75 / 0.4), smoothed
(1, 2, 1), centred; lean = F / max|F| in [-1, 1], strength k = 0.35 x the asymmetry (range of F from 0.2 to 1.0):
uniform land gives no lean. So woods and steep ground push away, a hillside favours its contour, a valley its floor
axis both ways, the dry land along a shore / river bank pulls, the water itself never (no growth across), open flat
dry land (prairie) pulls hardest. Style factors (`LAND.forStyle`): the forest cue x 0.5 for clear-mode towns
(metropolis too), x 0.3 for deep forest towns; character towns k x 0.5, a hilltop ignores the steep cue and a
waterfront / clifftop / harbour cove / island town the water cue (and those cues then don't close the open land
either); with the coast lean (`style.waterDir`) the water cue x 0.5. `ot_select.irregularity` blends it next to the
seeded preference: amplitudes ampSeed = sector, ampLand = k, scaled down together when their sum passes `TOTAL_MAX`
0.55 (EU organic 0.35 + 0.35 -> 0.275 + 0.275: the seeded variety keeps ~80 %); `preference` is the weighted blend
(the hotspots' favoured heading follows it), the cost's reach `SEL.reach` = 1 + ampSeed x seeded + ampLand x lean
(shaped towns: seeded x SH.SECTOR_DAMP, lean x `LAND.SHAPE_F` 0.5), at least 0.3. The lobe headings (`style.lobeDirs`,
road exits / contour) are re-ordered favoured-first from k 0.08 (hotspots sit on the first ones). The driver
(`Driver:landRefresh`, each snapshot after the forest mode) caches the raw reading per tree grid, wide survey, disc
stats and r0 step; a new forest read or a bigger town recomputes it, and a changed field redoes the cached
preference. Nothing saved (old saves load and grow; a town without a reading plans exactly as before). Log: LAND
(always on, once per town and change) `cues=open:W,forest:E k= kRaw= A= to=<deg> away=<deg> r0= forest= why=
shape= lobes=`; PLAN `land=<cues>/k<k>/to<deg>`. Offline (test_land): east woods -> west lean, k 0.35; 8 increments
of EU organic from a round core: west share of new street length 0.60 -> 0.74, the east still grows. Constants
`ot_land.lua` head.

**Landscape-aware skeleton (2026-10-15, §63; NEXT_PHASE_BRIEF 63; in game: TESTING.md "Combined test iteration"
step 12).** Run `2026-10-15_0539_sqot` (seed `a`, 1900, Quick 40 years) still lost woods fast (HISTORY.md): §62 only
reordered pieces, while a shaped town's arms (ot_shape linear / ridge / cross / fingers: the cheapest corridors in
`SH.distance`, the arm fronts' lead, and locked as "arm" streets, `D.lockKeys` lock=shape) went out at their seeded
headings into or along the trees, and houses fill any street to lot depth (~36-40 m a side) with the game clearing the
trees under them (Far Ashworth's W arm into `forest:W`, Norfield's into `forest:S`, Shaw's cross into `forest:NW`).
`ot_skeleton.plan` surveys each arm from 0.8 x the houses' extent (at least 100 m / one block) 900 m out every 25 m:
the clearance to the nearest dense cell (cover >= 0.5) along the normal on both sides, straight ahead and on the two
forward diagonals, scanned to 100 m every 10 m; the open run ends where it first drops under `CLEAR_M` 65 m (lot
depth + ~25-30 m for the 50 m smoothed cells: the measured edge sits up to ~25 m off the real one; a wood met head-on
stops the arm 65 m short). Per arm: `keep` (open all the way), `bend` (another heading scores 150 m more: open run +
150 m x the §62 lean; organic plans only onto an unused master-plan spoke within 75 deg, so the deep arms stay on
spokes; other plans 20 / 40 / 60 deg turns; linear / ridge at most 65 deg; two arms never within 35 deg), `short`
(run >= 200 m: `shape.armMax` caps it there: past the cap the distance along runs at the core's rate, so the corridor
costs like the core field, `SH.inArm` / `armAt` see no arm and nothing there is locked as one), `drop` (run under
200 m while another arm runs 200 m+ and the shape keeps 1 / 1 / 2 / 3 arms for linear / ridge / cross / fingers),
`boxed` (no alternative: every arm wooded; kept as it was, `why=noAlternative`, the hug / deep per-piece logic does
the rest). Open arms reach and lead further (`shape.armK`: SH.distance's ka, `armFronts`' reach, `armBuiltFronts`'
lead): 1 + 0.4 x (0.6 + 0.4 x lean, 0.2..1) for an open run over 0.6 x 900 m, + 0.15 per cut / dropped arm, at most
1.6. Exempt: deep forest towns (`mode=deep`, unchanged), metropolis variants, dev jobs (forced shape / form / pure).
Character towns keep their headings and arms (shortened / lengthened only; a too-short arm `boxed why=intent`); site
arms (valley / ridge / coast / river / hillside, `shape.site`) don't bend; strict grids don't bend. The driver
(`Driver:skeletonRefresh`, each snapshot after landRefresh): a town without a frame plans it from its tree grid
(again on a re-read grid until its first build's frame goes out), the frame saves it (`sk` = "<deg x 10>:<k x
100>:<cap m>" per arm, ot_saved), a framed town decodes it (headings snap onto the plan's spokes within 1 deg), a
frame without `sk` (older saves) keeps the arms exactly as the shape draws them (`src=old`). The master plan is
rebuilt when the arms change (`mp.skelKey`). Unshaped towns: their hotspots / lobes (ot_select.irregularity) that
sit in or within 120 + 32 m of dense forest turn 20 / 40 / 60 deg either way or move in to 0.75 / 0.55 of their
radius to the first clear spot (`SK.movePoint`; deep towns keep theirs; none clear: as before). Satellites
(`SAT.pickSite`, o.forest): score + 1.2 x how wooded the site's surroundings are (`SK.pointClear` over 185 m) + 0.5 x
the link's mean cover (deep towns none). Clear-mode towns (ot_forest `clearFactor`, the select cost): a wooded piece
costs x (1 + 0.6 x p x corridor pen), p = the town's hug odds (style x era x size x character): no hold, no budget.
Log SKEL (always on, once per town and change): `town= name= shape= src=new|saved|old|noGrid mode=forest|deep|saved
arms=<deg>:<act>:<run m>:<least clearance m>:k<x>[:from<deg>][:max<m>]/... dropped=<deg>:<why>:<run>/... minClear=
boxed= why=open|wood|boxed hot=<moved>/<hotspots> clearM=65 r0=`. Offline (test_skeleton): an EU organic linear town
(arms E / W) with woods from x = 330 m, 10 increments: street metres with lots in the woods 1693 of 5239 -> 95 of
5427 (clear mode alone, the light cost: 1301; hug mode 68 -> 30), west / east 2397 / 2801 -> 2968 / 1838. Not
replayable on seed `a`: the archived logs have no per-direction tree data. §62 fix: the LAND cue names come from each
cue's own top run of sectors (`LAND.peakHeading`), open land only among sectors with at most mean forest
(Seachurch Cove's `cues=open:N,forest:N`: the old resultant of the open sectors fell on the gap between two forest
lobes). Constants: `ot_skeleton.lua` head, `ot_forest.CLEAR_COST_K`, `ot_satellite.FOREST_W` / `LINK_WOOD_W`.

**Named offshoot towns instead of street satellites (2026-10-15, §64; NEXT_PHASE_BRIEF 64; in game: TESTING.md
"Combined test iteration" step 13).** Run `2026-10-15_0539_sqot` (seed `a`, 1900, Quick 40 years) showed no satellite
town: the five foundings (years 12, 20, 24, 32, 40) were all streets-only seeds (Far Ashworth, Two Waters at
-873:917, Dovemouth-in-the-Forest, Merehythe, Wheatden), each one dose, `near=0`, bare X / T crossings; no Works or
district was founded. Why: (1) `satelliteDecide` runs first in every job and its `paceGate` verdict is cached on the
job, so a satellite-eligible town's Works / district never got a turn of its own, and its seed took the slot and
raised its readiness (k + 1: Two Waters' Works waited at k=1, Merehythe's district at k=1); (2) the seeded draws were
broken: `ot_rng.hash` is affine mod 2^31 - 1, so `rng.unit(seed, a)` and `rng.unit(seed, b)` for labels of the same
length are one draw shifted by a constant mod 1: `district` = `leadLane` + 0.649 (every lane-ahead town, u < 0.3, had
u_district in [0.649, 0.949): always "rare"; Seven Oaks and Wheatden in 0539), `works` = `shape` + 0.430 = `metro` +
0.708 (Works only for one band of shape draws), `satellite` = `siteStyle` / `shoreForm` shifted; nearby numbers
(seed, seed + 2) correlate -0.31. The same map keeps the same towns' seeds, so the same towns read "rare" in every run
on seed `a`. Changes:
- `rng.draw(...)` (ot_rng): M.hash, then three rounds of x -> (x + c)^5 mod p (a bijection, 5 does not divide p - 1):
  labels and nearby numbers independent (chi-square over 10 x 10 bins under the 0.1 % line on 20000 seeds). Used for
  `WK.eligible` ("works"), `DT.eligible` ("district"), `SP.key` and `SP.need`; `rng.unit` is unchanged, every other
  seeded outcome stays as it was. Share over 20000 seeds: Works 0.353 (CHANCE 0.35), districts 0.602 (0.6), districts
  of lane-ahead towns 0.600 (0 before).
- No new streets-only satellites (`D.STREET_SAT` false): `satelliteDecide` logs `SATELLITE on=false why=retired` once
  (debug) and returns; the offshoot turn has no "satellite" kind. A satellite on a save's frame (`sx sy`) is restored
  and grows as before (pod cadence, meadow discs); the dev tools' forced crossroads hamlet still seeds one.
- Quotas (ot_driver, `D.offshootQuota`): Works and districts together at most OFF_PER16[2] 4 per 16 towns (rounded,
  the map's own towns: `paceMap.n`, the mod's offshoots left out; Works' own quota 1 per 8 / max 3 and districts' 1
  per 4 / max 6 still apply on top), at least OFF_PER16[1] 2 (at least 1). While the map is under the minimum, a town
  the draw passed over ("rare") founds one anyway once its size (`D.offshootSize`) reaches OFF_QUOTA_BUILDINGS 400
  (`why=quota`), of the kind the map has fewer of (`D.offshootFallbackKind`: a district first, Works when the map has
  fewer Works and room for one); a smaller one keeps its tries (`quotaWait=true`) and stays a candidate. The pacing
  still decides when (`paceGate`).
- Stagger: `SP.SPACE_B` 520 -> 850 (the slots now go to at most ~4 towns instead of 6-10 foundings).
- Sites (`WK.landScore`, both pickers' ring sites; the Works' industry site unchanged): + WOOD_W 1.2 x how wooded the
  surroundings are (1 - `SK.pointClear` / (POINT_R + CLEAR_M) = 185 m), + LINK_WOOD_W 0.5 x the link line's cover
  (`FO.pen`), - LEAN_W 0.35 x the §62 lean at the site's heading (`style.land`); no forest terms for a deep town (it
  founds none anyway). The forest share test (FOREST_MAX 0.2 within 450 m) and the edge bonus stay. Districts: two
  more kinds, "cross" (a country-road crossroads of `s.roads.junctions` within CROSS_R 250 m, bonus 0.75, the lane
  end's names) and "open" (no feature: plain open land, bonus 0.45, generic / size / compass names; `DT.OPEN`).
  Existing rules kept: character / deep towns found none, the gap / neighbour / character-core rules, links via
  ot_link, names via ot_offname (§61).
- Logs: WORKS / DISTRICT `event=create ... land=wood<x>:clear<m>:lean<x> why=seeded|quota simYear=`; the not-eligible
  debug lines `quota=<known>/<min>-<max> quotaWait=`; OFFSHOOTS (always on, every 300 real s and once per dev Simulate
  round while the map has offshoots): `n= quota= towns=<id>:<name>:works|district:<parent>:y<founded>:b<buildings>/...
  simYear= year=`, so the houses filling each offshoot town can be followed (CHECK lines carry them too).
- Saves: nothing new saved; Works / district towns of a save stay claimed (`wk` / `dk`) and count toward the quota.
Offline (test_offshoots, 9): the old shift (district = leadLane + 0.649, works = shape + 0.430), the draw's
independence and shares; the quota table and fallback; a 40-year model of 300 maps (16 towns, 3-5 character towns,
the driver's order, pacing, 15 % failed sites): every map 2-4 offshoot towns (2: 25, 3: 25, 4: 250; via the quota
129 of 1125), one per round, the first at simulated year 4-16 (median 8), the last 12-40 (median 28); without the
fallback 0 of 300 maps end with none (random seeds; a fixed map like seed `a` can); the landscape terms; the driver
glue (a rare town's quota district, the map's max, no seed, `why=retired`), an old save's satellite growing, the
OFFSHOOTS line, the loop caps. Constants: ot_driver `OFF_PER16`, `OFF_QUOTA_BUILDINGS`, `OFFSHOOT_LOG_S`, `STREET_SAT`; ot_works
`WOOD_W`, `LINK_WOOD_W`, `LEAN_W`; ot_district `OPEN`, `CROSS_R`, `KIND_BONUS`; ot_satpace `SPACE_B`.

**Lock every mod-built street, the stall guard (2026-10-15, §65; NEXT_PHASE_BRIEF 65; in game: TESTING.md
"Combined test iteration" step 14). (§69: "mod" is no longer the default; towns framed from now on get the steering
lock, below "Steering lock policy (§69)"; "mod" towns of a save keep this lock. The stall guard serves both.)** Run `2026-10-15_0629_sqot` (seed `a`, 1900, Quick 40 years): the 16 towns went
from ~706 to ~3880 street edges, CHECK `ownEdges` (the town's lot edges that are locked or built by the mod this
session, ot_assess.lots `own`: in that one-session run the mod's live streets) summed to ~1100, so the game's town
developer built about 2/3 of the new streets. It branches off every unlocked street (findings towns.md "Locked town
streets"), and its streets follow none of our rules (forest holds §62 / §63, open land, shapes): forestLot did not
fall. The user chose the middle option:
- **Lock lever (ot_driver).** `D.LOCK_DEFAULT = "mod"`: every street the mod builds goes out `roadDevelopmentLocked`
  (PR.build `info.lock`, `D.locksAll`): demand and room increments, the head start, rings / roundabout quarters, forest
  lanes, lanes ahead with their far-end streets (legacy left those open), Works links, bridges, wedge frames, satellite
  streets. All builds go through `Driver:send` -> `buildInfo`, so no kind is missed. The town's own starting streets,
  the game's and the player's stay unlocked: the game branches only off its own streets. `"legacy"` is the old lock
  (`LOCK_SHAPE`: arm / rim keys, forest-facing, motif, zone, metro / mech keys; D.lockKeys unchanged). A job's own
  `lock` still wins (dev: "shape" / "off" / "all" / "mod"); `ot_hooks.lockDefault` sets the default for towns framed
  this session (dev).
- **Per town, saved.** `Driver:townLockMode(t)`: the frame decides (`lm = 1`: "mod"; a frame without it, from before
  §65: "legacy", so old saves' towns keep their lock); a town without a frame gets the default, cached on the town
  state and written with its first frame. The frame also saves `e0`, its edges that were not the mod's at the first
  build (its core). Additive fields; nothing else in the save changes.
- **Supply.** A "mod" town's lead floor (own open lots allowed ahead of demand, ot_assess.demand) is x `LOCK_LEAD_K`
  1.5, phased out with the maturity (a grown town's mature brake holds as before). The **stall guard**
  (ot_assess.stall, "mod" towns, not forced / dry): capacity under `STALL_RATIO` 0.85 of the target, buildings up less
  than `STALL_GROW` 3 % since the streak began and open frontage under `STALL_OPEN_K` 2 x the need, `STALL_N` 3 checks
  in a row: it fires (STALL line, always on) at 3, 6, 9 ... checks of the streak, its level rising to 3; at most
  `STALL_MAX` 12 fires per town and session (`event=capped`). A fire makes a waiting check build (`why=stall`) unless
  the town is held (created towns) or over its target. Level 1: the increment x `STALL_INC_MUL` 1.5 (at most
  `STALL_MAX_EDGES` 36) and `STALL_OWN_EMPTY_M` 600 m more own empty budget (never the tight base); level 2: also the
  shape's envelope `STALL_ENV_SCALE` 1.3 wider (ot_core `envScale0`); level 3: also the forest hold
  `STALL_FOREST_STEP` 1 step looser (ot_select `limits.forestStep`, CUT_FILL still caps it): open land first, the
  woods last. A town whose lots stay free has no street shortage: no fire (the stalled-town test).
- **Measurement.** CHECK `lockMode= modEdges= gameEdges= coreEdges= gameShare= stallStreak= stallFires=`
  (ot_assess.edgeSplit: game = edges - mod - core; core = the frame's `e0`, else this session's first check); PLAN
  `stall= forestStep=`; BUILT `lockMode=`; STREETS every `STREETS_EVERY_S` 600 real s (always on): the map's towns,
  edges, mod / game / core edges, the game's share, stalled towns, fires, towns per lock.
- **Dev A/B (otd_layout PROBES, Showcase).** "EU organic (old lock)" and "Shape: linear (old lock)" (lock "shape")
  beside EU organic and Shape: linear (the new default) and Shape: linear (plain) (lock off). Their LOCK lines log
  `lockUsed= edges= gameEdges= gameShare= cap= capRatio=` with the buildings. A "rebuild and lock the core" variant was
  left out: it would rebuild the town's live starting streets (never rebuild live junctions).
- Open: whether the game's own unlocked streets keep branching (children of the core are unlocked, so the game can
  still grow a large share from them); whether the game ever widens or unlocks a locked street (findings: not seen);
  the stall guard's thresholds are offline guesses (the demand model never stalls: its game branches only off its own
  streets already).

**Supply-driven district weighting, "Town growth: By deliveries" (2026-10-15, §66; NEXT_PHASE_BRIEF 66; in game:
TESTING.md "Combined test iteration" step 15).** Phase 0 (session `2026-10-15_0759_rci-sqrl`, a played base-game save,
findings towns.md "District split" -> "Measured spread"): 15 towns at residential 25-47 %, commercial 20-50 %,
industrial 13-41 %, none above 50 %. The base game splits each growth increase by usage (line use, cargo supply /
demand) and then evens it out (rebalance2: a minimum weight per district, the maximum shrinking toward 0.5 past 40 % of
the town), so towns vary but never turn lopsided. The setting (mod.json `town_growth`, ot_params `townGrowth`): By
deliveries (default) / Game default.
- **Inputs (ot_engine.townSupply).** The base helpers, not a recomputation: `town_util.getCargoSupplyDemands(town)`
  (sums of supply / demand per land use; it wraps `townBuildingSystem.getCargoSupplyAndLimit`) and
  `api.engine.util.town.getTownLineUsage`, `town_util.LineUsageRatingMultiplier` (2). `RCI.usage` is the base
  game's own usage formula (town_growth.script.tl:377-412): residential = clamp(line use x 2) averaged with residential
  cargo supply / demand when there is any demand; commercial / industrial = clamp(supply / demand) (0 without
  demand). Reachability is not an input (the base growth doesn't use it).
- **Formula (ot_rci, pure).** Smoothed usage e += (u - e) x (1 - exp(-dt / `TAU_YEARS` 0.5)) (dt in game years, first
  sight e = u). Aim w = `FLOORS` (residential 0.25, commercial / industrial 0.12; §75, 2026-10-18: was 0.12 each) + 0.51 x e / Σe, so residential aims at 0.25-0.76, commercial / industrial at 0.12-0.63 (none when Σe = 0: a town without deliveries is left alone, as the
  game grows nothing there). Target shares s = init x sf / Σ. Budget b = min(`STEP_MAX` 0.03, `MOVE_K` 1 x the total
  target's growth since the last step / the target). Goal q = s + (w - s) x min(1, b / Σ max(w - s, 0)): never past
  w. New initial capacities λ q / sf with λ = Σ init / Σ(q / sf): **the initial sum is kept**, so the game's next total
  target (Σ init x its growth factor) is the base game's; the mix changes, not the speed. Floors: a losing district's
  target never below its built capacity (nothing to tear down); the units a floor keeps come back from the gainers,
  except up to `CEIL` 5 % above `n0` (the town's initial sum at its first write, saved): the only way the total grows.
  The current total target moves by `TOTAL_DEV` 4 % at most (the move halved until it fits, `HALVINGS` 6). Moves under
  `MIN_MOVE` 0.002 are not sent; towns under `MIN_TARGET` 60 persons are left alone. Too little growth for a step
  ("noGrowth") adds up until it can move; any other skip uses the growth up.
- **Wiring (ot_driver, "Supply-driven district weighting").** `Driver:rciTick` beside the jobs (in `tick`, at the
  check slots (`CHECK_S`) after the head start, before the slot's check), never while a job runs (its fill could restore stale values) or a command
  is in flight; `RCI_TICK_S` 1, `RCI_PER_TICK` 4 towns, `RCI_BUDGET_US` 2000, one command per tick (`self.inflight`),
  `RCI_MAX_TOWNS` 4000. A town is stepped at most once per game month (`STEP_YEARS`; `STEP_S` 60 real s without a
  date). Act on: Off nothing (the driver is off), New towns only skips the known towns, the mod's Works / district
  towns are never weighted. **One writer:** `E.setInitialCaps` (makeTownSetInitialLandUseCapacitiesCmd), the FILL
  restore's command. **The restore keeps the weighting:** a town the weighting has written (`rciManaged`: this
  session or saved `k > 0`) gets its pre-dose values back exactly (`D.restoreExact`; FILL restore `rci=keep`), the
  districts DevelopAt lowered too (the old `restoreCaps` only lowered the ones above, so a dose would undo the
  weighting). **Level weights (§58):** the engine may rewrite them with the capacities (findings "Restoring a town's
  initial capacities writes its custom level weights", changed values still unverified): after each write a town
  whose weights the mod manages gets its own back (`levelsAfterRestore`), any other town whose weights changed gets
  its old ones back (none: the game's default; `RCI levels=putBack`).
- **Visual tie-in.** The lean (`RCI.lean`: residential >= 55 %, commercial >= 52 %, industrial >= 45 % of the
  target, above the base game's measured maxima) multiplies the seeded draws (`CHANCE_MUL`): industrial: Works x2,
  district x0.6, lane ahead x0.8; residential: district x1.5, lane ahead (ribbon along a road) x1.5, Works x0.6;
  commercial: Works x0.8 and the core's upward dose as a densify town's (ot_upward.decide `densify`: from fewer
  buildings, a denser centre). The draws stay one-shot per town (a "rare" verdict before the town leans is final).
- **Saves.** Additive: `rc = { ["<town>"] = { e = {3} x 1000, s, y = year x 100, n0, k } }` (EV_RCI, ot_saved
  `normRci` / `applyRci` / `rci`, at most `RCI_CAP` 4000), written with every step that sends; n0 stays the first.
  Old saves: no `rc`, a town starts at its current mix and turns only with its growth, `STEP_MAX` per month at most.
  Removing the mod leaves the capacities where they are (the game never lowers them; description). Game default
  stops all writes; restores go back to the old rule.
- **Starting sizes: not changed.** The brief's "less random variation for new towns": an evening of the starting mix
  is a no-op under the built floor (a generated town stands at its target, so no district can lose), and lowering a
  district below its built capacity is untested. Left for the user's decision (open).
- **Logs.** `RCI town= name= r/c/i=a->b aim= supply= smoothed= caps=a,b,c->x,y,z built= target= sum= n0= move=
  budget= lean= n=` per write (always); debug `RCI skip=` once per reason change (noSupply / noCaps / zero / small /
  noAim / noGrowth / atMix / built / total / tiny / known / offshoot); `RCI summary towns= weighted= writes= lean=
  skips=` every `RCI_LOG_S` 600 real s; INIT `townGrowth=`; FILL restore `rci=keep`.
- **Dev.** ALLTOWN `rci=<shares>:use=:aim=:lean=|main:<state>` (`D.rciReadout`: from the engine's reads, also with
  the setting off or no main driver) and the inspector's "R/C/I by deliveries" line. The dev Simulate makes no
  deliveries (no supply: the weighting leaves its towns alone), so the check is real play (TESTING.md step 15).
- Tests: test_rci (usage, smoothing, aim, the step's guards / budget / floors / ceiling / total cap, a 20-year
  lopsided town vs the base split: industrial >= 60 % without overshoot, the total within CEIL; a passenger town >= 60 %
  residential; a town that never grows unchanged; the full-mode sweep; the lean draws; the driver: writes, Act on Off /
  Game default / New towns only / offshoots, the per-tick cap, the exact restore, the level weights put back, the
  saved state).
- Open: whether a lowered initial capacity (target still >= built) ever demolishes buildings; whether the changed-
  value write rewrites level weights (the put-back handles it either way); the constants (STEP_MAX, TAU, FLOOR) are
  offline guesses; the starting-size evening (above).

**Game-street locking and valves (2026-10-15, §67; NEXT_PHASE_BRIEF 67; in game: TESTING.md "Combined test
iteration" step 16). (§69: in steer towns only rim streets facing something unwanted are locked, and the valves are
the branches' tips, below "Steering lock policy (§69)"; "mod" towns keep this section's rules.)** Run `2026-10-15_0759_rci-sqrl` load 2 (§65): the game still built 58 % of the non-core edges
(1704 game / 1231 mod; per town 0.35-0.81), branching off the unlocked core and then off its own new unlocked streets.
The user: "lets try locking the games streets after it builds them. then we try to steer early building with locked
streets, and intentionally build unlocked streets at the opportune places." The lock lever now has three parts: every
mod street locked (§65), the game's own new streets locked soon after they appear, and a few **valves** (unlocked
places the mod chooses) where the game may still branch.
- **No in-place setter (findings towns.md "No script can set the lock on an existing edge in place").** So a game
  street is rebuilt between its SAME two nodes (ot_engine `lockProposal`, move_it's pattern): its own BASE_EDGE /
  BASE_EDGE_STREET (template, lanes, style, decorations, geometry, -0 normalized), `roadDevelopmentLocked = true`,
  `edgesToRemove` = the old edge, no node added or removed; each end node with a BASE_NODE_CONFIG gets it back (remove +
  add, only when it exists) with lane connections and crosswalks re-pointed to the new edge, in their order (traffic
  light phases index them). Each edge is re-checked live (exists, street, unlocked, not PLAYER_OWNED, no edge objects,
  NORMAL type, not a loop, neither it nor its nodes owned by a construction). Pre-check with the mod's context; refused
  when it lists buildings or costs over `GL.COST_MAX` 250k per edge. The new edge ids (found between the same nodes,
  `E.edgeBetween`) are saved (`gx`, EV_GLOCK) so a reload still tells them from the mod's own locked streets.
- **Which edges (ot_glock.classify / queue).** The town's lot edges (CHECK) that are unlocked town templates, not the
  player's, not the mod's (built this session); `core` when present at the town's first sight before its first frame
  (else `game`). Housed edges are locked too (`WITH_HOUSES` true since the console probe of 2026-10-15,
  session `2026-10-15_1936_sqot-glprobe`: 6 houses and 22 lots kept, cost 1650). Skipped: edge objects (stops, signals), constructions, bridges / tunnels, loops, edges under `MIN_LEN` 8 m, edges known for less
  than `SETTLE_S` 3 s (one check stamps, a later one locks), edges refused `EDGE_FAILS` 2 times, another town's street
  (`E.closestTown`), and the open valves' zones. Order: dead-end tips first, game before core, outer first. `CORE` true:
  the core's edges (its tips, where the game branches first) are locked too, housed ones included.
- **Budget.** Queued at the CHECK (`job.glockQ`, at most `BATCH` 8), locked when the job ends (Driver:finish defers to
  stages `glock` / `glockWait`, then finishes with the job's outcome): one proposal per job, never beside another
  command; a refused batch is pre-checked edge by edge (one per tick), the passing ones sent together. Caps:
  `TOWN_MAX` 600 per town and `MAP_MAX` 6000 per session; a refusal backs the town off `BACKOFF_S` 60 s doubling to
  `BACKOFF_MAX_S` 1800, `TOWN_FAILS` 8 in a row: off for the session; a callback that never comes ends after
  `WAIT_S` 20. Never in dry / forced / head-start jobs, and not before the town's first plan of the session (`noCtx`:
  no valves known).
- **Valves (ot_glock.pickValves, Driver:glockValves).** Wanted: `VALVES` organic 2 / grid 1, + 1 from `VALVE_BIG_R` 450
  m extent, at most `VALVE_MAX` 3, + the stall guard's extra ones. An anchor is an unlocked town street at least
  `VALVE_OUT_MIN` 0.5 x the extent out (the outermost `VALVE_CANDS` 120 scored): score = §62 land lean toward its
  heading + 0.6 x a §63 skeleton arm's alignment (cos^4) + 0.5 x outwardness + 0.3 for a dead-end tip, - 1.2 when within
  `VALVE_REST` 45° of one of the last 3 closed valves; rejected when the probe point `VALVE_AHEAD_M` 150 m out is in
  dense forest or the skeleton's clearance there is under `SK.CLEAR_M` 65 m, is water (the town's sampler), or is held
  by a neighbour's gap (ot_gap). Valves keep `VALVE_SEP` 60° apart. The game's new streets within `VALVE_R` 300 m of
  the anchor stay unlocked while it is open; it closes after `VALVE_EDGES` (organic 14 / grid 8) new game streets
  there, after `VALVE_CHECKS` 24 checks, or when its anchor is gone; its houseless streets are then locked like any
  other, and the next valve opens elsewhere. No anchor good enough: the best rim heading (`stubHeading`, 16 headings)
  becomes `stubWant`, and the town's next locked build leaves one outward tip toward it unlocked (`pickStub`,
  `STUB_TURN` 40°, PR.build `unlockKeys`), which becomes the valve (`kind=stub`). Early building is steered by the
  locked mod streets (§63 skeleton / arms) as before.
- **Supply.** Locked game streets still get houses; the game still adds streets as its target rises (it just can't
  chain off fresh ones), so frontage keeps coming. The §65 stall guard stays as it was; each applied fire also opens one
  more valve (`VALVE_STALL_MAX` 2), so a starving town gets more of the game's own fill before level 3 relaxes the
  forest hold.
- **Saves.** Frame `gk = 1` (the town gets this lock, written with its first frame); a frame without it (towns framed
  before §67) keeps the §65 lock only; `gx` the rebuilt ids (at most `GX_TOWN_CAP` 800 per town, oldest dropped).
  Additive; `ot_hooks.glockDefault` sets the default for towns framed this session (dev). Valves are session state.
- **The rest of the mod reads our locked game streets as the game's** (`Driver:glockMark` after each street read:
  `locked = false, glocked = true`), so `ownEdges`, the own empty budget, retiring, wedge frames and motifs see them as
  before.
- **Logs (always on).** `GLOCK event=send town= edges= preCost=` before each proposal, then per edge `GLOCK town= name=
  edge= len= ok= why=<kind> kind= tip= new= locked= batch= cost=` (refused: `why=precheck|buildings|cost|failed|
  timeout|skip:<why>` with `msgs= fails=`), `GLOCK event=backoff pause= off=`; `VALVE event=open|close|want town= name=
  heading= dir= kind=game|core|stub why=land|arm|open|quota|age|gone score= at= quota= n= checks= valves= want= extra=
  rejected=`; CHECK `valves=<n>:<deg><kind>/... glocked= gameOpen= glock=<queued|none|noCtx|backoff|...>`; STREETS
  `gameLock= valves= glocked= gameOpen= glockedSession=`; STALL `valveExtra=`.
- Tests: test_glock (20: classification, the fresh-edge rule, skip rules, queue order, loop caps, backoff, valve
  placement / separation / rest, wanted counts, rotation, stubs and `unlockKeys`, saves, old saves, the driver's lock
  stages (batch, edge by edge, build refusal, timeout), caps, valves in the driver, the stall guard's extra valve).
- Answered: houses survive a locked rebuild (console probe 2026-10-15; `WITH_HOUSES` on; the first probe also found
  `lockProposal` refusing every edge as `read`, fixed, HISTORY.md). Open: what a rebuild costs the player (it runs with the player, as every mod build; booked back since §68, 6.2 "Small
  follow-ups (§68)"); the game may still branch off its
  housed unlocked streets and off a fresh street before the next check locks it; a game edit at a node between the
  pre-check and the build could leave the re-added config stale; after a reload the edge ids the game split since are
  unknown (they count as the mod's).

**Small follow-ups (2026-10-15, §68; NEXT_PHASE_BRIEF 68; in game: TESTING.md "Combined test iteration" step 17).**
- **Dev Quick moves the calendar by default.** Every Quick run so far logged `moveDate=false`: a 1900 map stayed in
  1900 for 40 simulated years, so the era rules (forest hug odds, deep, era styles, upward levels, levels 3-4 from
  1950 / 1990) never moved. "Move the game date with the simulated years" is now on by default (HUD store
  `simMoveDate`, otd_hudview `simStartParams`, otd_runner `simStart`: nil = on; SG.new keeps its explicit default off
  for direct callers). `Sim:moveDateNow` is forward only (never sets a year at or below the current one, nor below one
  it already asked for). With the calendar moving, ot_satpace's slots count game years too (`years / YEARS` adds to
  the growth term): a Quick run now paces offshoots as normal play does (both terms), still capped by the quota and the
  per-town readiness; a 1950 map reaches 1990 (level 4) in a Quick run.
- **Coupled seeded decisions drawn independently (ot_rng.decide).** `ot_rng.hash` is affine mod 2^31 - 1, so every
  pair of `rng.unit(seed, label)` with labels of the same length is one draw shifted (20000 seeds: resultant 1.000 for
  every same-length pair, < 0.02 across lengths; test_draws). Groups found: 10 letters forestMode / forestDeep /
  entryTrees (a deep candidate turned down by share or quota with u in [0.14, 0.3) always hugged); 5 shape / metro /
  arms3 / works (arms3 = shape + 0.028: a cross town's 3-arm chance hung on where cross sat in the weights); 9
  satellite / shoreForm / siteStyle; 7 densify / leadEnd / fingers; 13 characterForm / satpace:ready / every / phase;
  8 leadLane / district (§64 fixed district); and the motif slots (slot 2's gate = slot 1's + a constant: same label,
  the slot number mixed in linearly). Switched to `rng.decide` (rng.draw): forestMode, forestDeep, entryTrees,
  leadLane, leadEnd, bridge, metro, metroVariant, polyCore, satellite, shoreForm, arms3, fingers, densify, motif /
  motifPick, satpace ready / min / step / every / phase; charPick's jitter (map-wide, once per new map) uses rng.draw.
  Kept on rng.unit as each group's one anchor (a draw is independent of every unit): shape, form, siteStyle,
  characterForm, characterIsland, so the towns' shapes, forms and styles do not move. Geometry jitter (angles, radii,
  phases, motif lengths and counts) stays on rng.unit; the remaining same-length pairs among geometry (e.g. form / axis,
  4 letters) are left as they are.
- **Existing saves.** The frame carries `dv = 2` from §68 (SV.frameParam when style.drawV is 2); ot_style sets
  `p.drawV = 1` for a town whose frame lacks it, and every switched draw passes that version (`rng.decide(v, ...)`:
  v 1 = rng.unit). So a town framed before §68 keeps its re-derived picks (forest mode and entries per plan, metro,
  the cross's arms, the finger count, lead lane, bridge, densify, readiness, pod cadence); towns without a frame yet
  (new towns, also on old saves) draw with rng.decide. Saved decisions are read back, never drawn again: deep `fd`,
  character `ck`, densify `dz`, skeleton `sk`, shape `s`, style `st`, form `f`, motifs `mo`, the map's characters `cm`.
- **Company towns reach farther.** §62 found 0 company towns on the archived maps (starting towns' nearest heavy works
  1236-1577 m; the score 1.25 - d / 1500 needed a heavy works within ~1275 m). Now `CH.companyDist`: full within
  `COMPANY_FULL` 1000 m, `MIN_SCORE` 0.4 at `COMPANY_AT` 1700 m for a heavy works (a medium one x 0.75: ~1545 m), 0 at
  ~2170 m, read within `COMPANY_R` 2200 m; the slope rule stays `COMPANY_SLOPE` 0.05 (near-misses 0.08-0.11, e.g.
  81939 heavy at 1277 m, slope 0.09; 0.06 adds no map, 0.07 one medium site). Archived maps 2026-10-13..15 (16
  distinct maps, reloads counted once; CHECK `ind=` nearest + heavy count, kinds from the industries named after the
  town): 0 -> 5 maps with an eligible starting town (66044 heavy 1346 m, 61035 heavy 1516 m, 60343 heavy 1559 m,
  58806 medium 1436 m, 58864 1236 m kind unknown); the seed `a` map still has only light industries near its towns. A
  lower bound: the CHECK read reaches 1500 m for small towns, so works at 1.5-2.2 km were not logged. One per map at
  most (one kind per map), within the quota (1-3 per map), so it takes at most one of the strong-character slots.
- **The game-street lock's rebuild is booked back.** Every mod build runs with `ctx.player` (charged, like the
  player's own); the lock rebuilds the game's streets on top, about doubling the town's street costs. Building
  without a player was never tried (findings towns.md: the 2026-10-11 crash bisect left it open), so the driver
  refunds instead: the balance at the send minus the balance in the callback, at most the build's cost
  (result `costs`, else the pre-check's), only when it is at least `REFUND_TOL` 0.5 x the cost (no upper bound since
  the seed `a` run: other spending in the same frames still gets the cost back, never more), booked as street
  construction income (`E.bookStreetRefund`, makeJournalBookAssetCmd as
  Full Refund / Stress Test book from a GUI script). Infinite money (no balance): none. `GL.REFUND` off: none. Logs
  `GLOCK event=refund amount= why=paid|mismatch|notCharged|noBalance|noCost paid= cost= session=`, STREETS
  `glockRefund=`. Since rev 2 every other mod build is refunded the same way (6.2 "Pause and refunds (rev 2)").
- Tests: test_draws (6: before / after on 20000 seeds, joint gates, versions, frames, legacy picks, saved decisions),
  test_character (company distance), test_glock (+2: refund rule, the driver's booking), test_hud (Quick moves the
  date by default). Re-baselined: test_character harbour cove (compared without motifs: its motif draw swapped),
  test_shapes NA_GRID fingers (the drawn finger count; the bar is the drawn shape's), test_demand maturity (the street
  pods' cadence held at the measured draw, withLegacyPods).
- Open: the refund in game (does the callback's balance already show the charge; one GLOCK refund line per send);
  how often the Quick runs' moving calendar changes the offshoots' pacing; company towns on new maps.

**Steering lock policy (2026-10-15, §69; NEXT_PHASE_BRIEF 69; in game: TESTING.md "Combined test iteration" step
18). Supersedes the lock-everything parts of §65 ("mod" as the default) and §67 (GLOCK of every game street, valves
on game anchors and stubs) for towns framed from now on.** Run `2026-10-15_1936_sqot-glprobe` load 2 (seed `a`, 1900,
Quick 40, calendar moving; HISTORY.md): the game-built share of the non-core edges fell to 0.22 (0759: 0.58), forestLot
34.7 ha (46.9), capacity 98 %; the towns read tidier, but (1) bare locked spikes (Shaw's V south-west, two ~600 m roads
south of Seven Oaks, Merehythe's ~1 km road over a bridge to an empty peninsula), (2) rakes of parallel dead ends and a
zig-zag arm (Seven Oaks), (3) less organic texture (our regular pattern everywhere), (4) Two Waters' south still into
clearings by the woods. The user: "i think we should not lock all roads, just many of them, especially early when
trying to stear direction. but building a locked branch out into an open space, then unlocking at the end seems
good."
- **Lock modes.** `D.LOCK_DEFAULT = "steer"` (frame `lm = 2`, gk as before); `"mod"` (lm 1: every mod street, §65)
  and `"legacy"` (no lm) stay selectable (`ot_hooks.lockDefault`, a job's `lock`) and a town keeps the lock its frame
  saved: old saves' towns keep theirs (decision: new frames get the new policy, old ones keep their lock). The §65
  machinery (stall guard, lead floor `STEER_LEAD_K` 1.2, edge split) and §67's (the rebuild, refunds, caps, backoff)
  serve both (`D.lockFamily`). Metropolis and mech styles keep their own lock-all rule in steer towns.
- **The town's outline (ot_lockpol.outline, at each CHECK, Driver:steerNote).** 16 heading sectors around the extent
  centre, per sector the `OUTLINE_Q` 0.85 quantile of the housed streets' midpoint distances (at least `OUTLINE_MIN`
  120 m; a sector without houses `OUTLINE_EMPTY_K` 0.6 x the town's own quantile), smoothed 1/4-1/2-1/4; without
  housed streets a round outline of 0.8 x the extent. The maturity is ot_assess's (persons, MAT_LO..MAT_HI).
- **Mod streets (ot_lockpol.decide, D.steerKeys at the plan's end).** In order: **face** (locked): the street's outer
  end, probed `AHEAD_M` 120 m outward, meets dense forest (or the skeleton's clearance there is under `CLEAR_M` 65 m;
  a hug / deep town's `facesForest` too), water, a neighbour's gap, or, at or beyond `GK_RIM_K` 0.85 x the outline,
  the §62 lean under `LEAN_BAD` -0.15 ("lean"); **arm**: in a §63 skeleton arm (`SH.inArm`) while the maturity is under
  `ARM_FREE_MAT` 0.6; **out**: beyond the outline; **rim**: beyond the inner zone, `innerK(mat)` x the outline
  (smoothstep from `INNER_K` 0 at maturity `MAT[1]` 0.15 to 0.85 at `MAT[2]` 0.8); else **fill**: unlocked, the game's
  own side streets fill the blocks. So a young town locks every street it builds; a grown one leaves its inside open.
  Motif lock prefixes, industry zones, ring quarters and forest lanes stay locked as before. BUILT `steer=<why>:<n>/...`.
- **Game streets (ot_lockpol.gameLock, the GLOCK classify's `c.steer`).** A game / core street is a lock candidate
  only at or beyond `GK_RIM_K` x the outline and only when it faces something unwanted (as above, the lean included),
  or, while the maturity is under `YOUNG_MAT` 0.35, when it lies beyond the outline at all (the early steering).
  Inside (`steerIn`) and on the rim toward open land in a grown town (`steerOk`) the game keeps building. CHECK
  `gameKept=<steerIn>/<steerOk>`. Steer towns pick no game-anchor valve and no stub (their rim toward open land is
  open anyway): their valves are tips.
- **Locked branch, open tip (ot_glock.pickTips, Driver:steerPrep / glockStubBuilt).** Of a build's new dead ends
  whose street the policy locked as out / rim / arm, `TIP_OUT` 0.7 x the extent or farther out: the best by
  `valveScore` (forest / water / neighbour ahead rejected), at least `SK.CLEAR_M` 65 m from dense forest
  (`SK.pointClear`: the game's fill from it would eat the woods), `VALVE_SEP` from the open valves, at most the valves
  wanted (`wantValves`) less the open ones. The tip edge goes out unlocked (PR.build `unlockKeys`; the rest of the
  branch locked) and opens a tip valve (`kind=tip`): the game's new streets within `VALVE_R` 300 m stay open until its
  quota / age (§67 rotation); then the steer rule applies to them. BUILT `tips= tipRej=`, CHECK `tips=`.
- **No bare spikes (ot_select limits, Driver:plan).** Steer towns' plans (and the head start; not the dev tools'
  forced increments) get `leadCap` = `LEAD_BLOCKS` 2 blocks within `LEAD_CAP` 150-250 m on the lead limit (was
  `MAX_LEAD_M` 400; the head start's 280 too), measured from streets with `HOUSED_MIN_B` 2+ buildings (a lone house is
  no front; none such yet: the plain index). The arm fill rule's front is **continuous** (`armCont`, `LP.contFront`):
  it runs out from the town's housed radius only across gaps of at most `ARM_GAP_BLOCKS` 1 block (at least 100 m), so
  one far house (a bridge end's dose, a farm) no longer lets an arm run out to it bare (1936: Merehythe's arm 1 housed
  front 204 -> 904 m); the arm's lead after the §63 reach (`armK` up to 1.6) is capped at `leadCap` too. PLAN
  `leadCap= spikeTrim=<lead held>/<arms trimmed>`.
- **Bridges need a target (ot_bridge.target, Driver:bridgeTargets).** A steer town's crossing needs, on the far bank
  within `TARGET_R` 300 m of its end (not back across the water) or ahead within `TARGET_FAR` 1500 m and `TARGET_DEG`
  35 deg: a neighbour town, an industry or the town's own housed streets; else it must be short (approach + span + far
  street at most `EMPTY_MAX_M` 220 m; Merehythe's was 270). BRIDGE `target= len=`, `why=noTarget noTarget=`. Lead lanes
  (ot_lead, unhoused country lanes by design) unchanged.
- **No rakes, no wiggles (ot_select RAKE / WIGGLE, `limits.steer`).** Rake: a new spur off an existing node whose far
  end lies within `RAKE_R` 1.6 blocks of `RAKE_N` 2+ parallel (`RAKE_DEG` 25 deg) dead-end spurs (at most
  `RAKE_SPUR_M` 260 m back to their junction) waits; a piece joining the tips of two parallel spurs (`RAKE_JOIN_R` 2.4
  blocks apart) costs x `RAKE_JOIN_K` 0.3 and is free of the lead / lasso / empty-loop holds (it closes the block,
  adds no reach). Wiggle: a main / medium / arm-line piece extending an existing dead end turns at most `TURN_MAX` 40
  deg off the street it continues, and not back against that street's last corner (`WIGGLE_MIN` 10 deg, within
  `WIGGLE_BACK_M` 260 m along the straightest continuation) when both sum over `WIGGLE_DEG` 55 deg. Why the zig-zag
  rule missed Seven Oaks' east arm (from the code; the run's geometry is not in the log): it counts corners only at
  two-street nodes one edge back, so a piece split into several edges (`maxSeg` 100 m) puts a straight split node
  there, an arm spine with a lane at every node has no two-street nodes at all, and alternating turns under 35 deg
  never count. Both rules give way when the increment would be empty (`lookRelax`). PLAN `rakeHeld= rakeJoin=
  wiggleHeld= lookRelax=`.
- **Logs.** CHECK `lockShare=` (the town's lot edges locked by us or the game-street lock) `tips= gameKept= outline=
  lockMat=`; PLAN `lockMode= spikeTrim= leadCap= rakeHeld= rakeJoin= wiggleHeld= lookRelax=`; BUILT `steer= tips=
  tipRej=`; BRIDGE `target= len= noTarget=`; VALVE `kind=tip`; STREETS `lockSteer= lockShare= tips= spikeTrim=
  rakeJoin= wiggleHeld=`; INIT `lock=steer`.
- **Dev.** The showcase's EU organic twin runs "mod" now (`EU_ORGANIC_LOCKALL`, "EU organic (lock all)") beside the
  default steer row; the linear twins keep the old shape lock and the plain control.
- Tests: test_steer (19: outline, innerK, the policy young / grown / inside / rim / out, facing forest / water /
  neighbour / lean, arms, the share falling with maturity, game streets, tips and their rejects, steerKeys + PR.build,
  the driver's CHECK (grown / young), tips as valves, buildInfo, Works links, old saves and frames, the lead cap with
  housedMin and its fallback, the continuous arm front, the bridge target, rake hold / join / relax, wiggle, loop
  caps); test_driver (+1 steer default build and frame; the §65 tests run under "mod"); test_glock (the §67 driver
  tests pin "mod"); test_demand (head start lead within the steer cap); dev test_layout / test_showcase (the lock-all
  twin).
- **§70 (2026-10-15, NEXT_PHASE_BRIEF 70; in game: TESTING.md "Combined test iteration" step 19).** Run
  `2026-10-15_2031_sqot` (seed `a`, Quick 40): game share 0.24, following the maturity: the grown towns (lockMat
  0.96-1) 0.57-0.68, the mid-size ones (300-550 buildings, lockMat 0-0.16) 0.00-0.34; Merehythe's south knotted.
  - **Lock maturity (ot_lockpol.maturity, Driver:steerNote, `s.lockMat`).** The persons measure (ot_assess.maturity,
    1800..3600 persons) read the era's small houses (3.8-4.6 persons per building) as young for ever: 1233-2089 persons
    at 311-534 buildings. Now the larger of base (that measure), **size** (buildings `SIZE_B` 150..600 x the scale:
    grid styles x `SIZE_GRID_K` 1.2, eras after `ERA_Y` 1930 down to x `ERA_K` 0.75 by 1990) and **age** (the years
    since the town's first frame, `AGE_Y` 5..35, at most `AGE_W` 0.8, times the size gate min(1, buildings / `AGE_GATE_B`
    450 x the scale): an old hamlet stays young). The frame saves its game year (`fy` = year x 100; frames from before
    §70 have none: no age part). It feeds innerK, ARM_FREE_MAT, YOUNG_MAT and the game-street rule as before. `s.mat`
    is the densify draw's level maturity again (§69's steerNote overwrote it with the persons measure). CHECK
    `lockMat=<v>:size<a>:age<b>:base<c>`.
  - **Knots (ot_knot, ot_select M.KNOT, steer towns' plans).** Why Merehythe's south knotted (from the code; the log
    has no per-edge geometry): classifyPiece blocks a piece only when its middle lies within occR (8-30 m) of a street
    or its chords cross a street's chord, leaving out every street at its end nodes; ot_plan's crossesExisting /
    nearExisting compare chords too. A 100 m curved edge bulges up to ~20 m off its chord, so curves crossed while their
    chords did not, a curve leaving a node crossed that node's other street, and pieces ran 20-35 m beside a street.
    Now, on the curves (graph edges as Hermite curves from the snapshot tangents): **cross** (a street or a piece chosen
    in this increment, other than at a shared node, `TRIM_M` 6 m of a shared end left out), **parallel** (at least
    `PAR_RUN` max(60 m, a block length) within `PAR_M` 0.65 x block depth, 20-35 m, at most `PAR_DEG` 25 deg off; the
    other street's own ends and `END_SKIP` 30 m of the piece's ends don't count; **§75 changed it**: the whole street,
    `PAR_K` 0.9, `PAR_MAX` 50 m, the run 60-200 m, `END_SKIP` only at a junction end, never relaxed, connectors too:
    "Side streets and parallel streets (§75)" below) and **loop** (the piece closes a loop
    enclosing under `LOOP_K` 0.5 x len x depth; the way back by a capped Dijkstra, `WALK_MAX` 400 nodes, within 3 x
    (len + depth)). Motif, ring and connector pieces exempt; relaxed only when the increment would be empty (after the
    rake / wiggle relax). PLAN `knotHeld=<n>:<cross>/<parallel>/<loop> knotRelax=`, STREETS `knotHeld=`.
  - **Clearings (ot_skeleton.corridorAt).** A narrow clearing ahead (woods on both sides within `CORRIDOR_W` 220 m in
    all) faces forest (LP.facing: mod and game streets; `LP.CORRIDOR`), and no tip sits in one (`GL.TIP_CORRIDOR`, BUILT
    `tipRej=corridor:n`): Two Waters' south.
  - Tests: test_knot (8: maturity parts, gates and the 2031 towns, scale, the frame year and old frames, the driver's
    CHECK, knot geometry and caps, the select holds / relax / off switch, two crossing pieces of one increment, the
    clearing corridor and tips).
- **§71 (2026-10-16, NEXT_PHASE_BRIEF 71; in game: TESTING.md "Real play (first)").** Run `2026-10-16_0405_sqot`
  (seed `a`, Quick 40; HISTORY.md): game share 0.32, forestLot 35.8 ha; every town over ~400 buildings mature (lockMat
  0.74-1), but some still let the game build little because the face rules locked their rims: Shaw 0.07 (a patchwork
  of small woods), Dalemere 0.12, Seachurch Cove / Little Dalemere 0.15, Norfield / Watersmeet 0.19; a few small
  curled "P" dead ends (ours, locked) in Merehythe and Shaw.
  - **Small woods don't count (ot_forest.woodSizes / bigWoodAt, LP.SMALL_WOOD, GL.SMALL_WOOD).** A wood is a
    4-connected patch of dense cells (cover >= 0.5) in the town's forest grid (one capped flood fill per grid, cached;
    a patch touching the grid's border counts as big); the lock policy's face rules count only patches of at least
    `WOOD_MIN_HA` 1.75 ha (7 cells of 50 m). Applies to LP.facing's probe ahead, clearAhead and the §70 corridor (mod
    streets and the game-street rule), a hug town's `facesForest` (it needs a big wood within `SMALL_WOOD_R` 60 m of
    the street or its tip probe; deep towns as before), and ot_glock's valve score and tip checks (pointClear,
    corridor). The §63 skeleton clearance, the hug / forest costs and the clearing budget read the plain cover as
    before (ot_skeleton's clearAt / clearAhead / corridorAt / pointClear take an optional `isWood` predicate; default the
    dense test). Faces skipped: BUILT `smallWood=` (mod streets and tips of the build), CHECK `smallWood=` (rim game
    streets this check).
  - **No curled hooks (ot_knot.hook, ot_select M.HOOK, steer towns' plans).** Source (likely, from the shots and the
    code; the log has no per-edge geometry): the hooks are our locked small streets, and Merehythe's MOTIF lines show
    no motif building there (crossroads hamlet waiting, crescent / village green 0-4 edges), so plain organic pieces: a dead-end
    chain growing a piece at a time, each piece within the wiggle rule (main / medium only) and none closing a loop (the
    knot rule only sees loops), curls round over several increments. Now, once the increment is chosen, a chosen piece
    whose far end is a new dead end (no other chosen piece, no town street there) is left out when the dead-end street
    it makes (the piece plus the chain behind it back to its junction through two-street
    nodes, `HOOK_WALK` 8 edges / `HOOK_BACK_M` 400 m at most, existing streets and this increment's pieces) **turns**
    more than `HOOK_DEG` 120 deg over its last `hookTurnM` (2.5 x block length, 150-250 m: a curl, not a long sweeping
    street; signed, so an S is fine; points under 2 m apart make no turn) or its end comes **back** within `hookR` (1 x
    block depth, 30-50 m) of its own chain, or, heading toward it (within `HOOK_TOWARD_DEG` 60 deg; a lane beside a
    parallel back street is the knot rule's), of the other streets at its junction, after at least `HOOK_ARC_K` 3 x
    hookR of chain; again until none is left (the piece before it may become one). Tested at the end, not during the
    greedy choice, so a U on its way to closing a block within one increment is fine (the grid towns build blocks that
    way; holding the U's third side stopped them). The select then runs once more without the pruned pieces
    (`opts.hookPass`, its budget to other pieces; used when it chooses at least as many); kept when pruning would empty
    the increment (`hookRelax`). Connector and ring pieces, the climbing motifs (`HOOK_FREE`: switchbacks, hill_climb)
    and grid growers (`SEL.HOOK_GRID` false: NA grid and the strict grids) exempt. Why grids: in test_demand's NA grid
    simulation the rule pruned acute V spurs (a diagonal meeting a grid line, which later blocks close); seed 1 then
    took another course: its game streets outgrew the master plan and every remaining piece was blocked / excluded
    after 3 builds (was 11). The hooks seen in game were organic towns' curls. In the organic simulations it catches
    hairpins and "?" spirals. PLAN `hookHeld=<n>:<turn>/<back> hookRelax=`, STREETS `hookHeld=`.
  - Tests: test_tune71 (8: wood sizes, copse / wood / border, near / by; the face rule with smallWood and its off
    switch, decide's third value, the game rule's count and cache; tips and valves by a copse vs a wood; steerKeys'
    count; hook geometry (curl, S, straight, back toward the junction's street, beside it is no hook, the joint of two
    pieces, caps); the select prunes / runs again / relax / other towns / motif exemption / off switch; a chain of
    existing streets and of this increment's pieces; a U closing a block within the increment). test_knot's off-switch case turns M.HOOK off too (its lasso piece
    is a curled dead end); test_tune71 checks the NA grid exemption.
  - Open: `WOOD_MIN_HA` is a guess (the grid's woods per town are not in the log); the game's own streets may now grow into
    the gaps between small woods (forestLot should stay within ~36 ha); hooks built by the game itself are not ours to
    hold.
- Open: every constant is an offline guess (the in-game run decides: game share 0.35-0.5, forestLot <= 34.7 ha);
  whether the outline's 0.85 quantile and the inner zone read "established" right on long arm towns; tips may sit on
  arms the lean dislikes when nothing better scores; lead lanes still run up to 600 m into open land with a hamlet at
  the end (the user's earlier ask), `axis` targets included.

**Showcase (2026-10-11, dev mod).** "Showcase: build all" (TESTING.md "Showcase"; `otd_showcase.lua`,
`otd_layout.lua`): island measured with isOnWater from the terrain box centre, 16 towns on a grid (2.5 km when
there is room, never under 1.3 km; Probe C, controls, era town dropped first on small maps; NORDIC moved 420 m
from the shore), created one at a time with createTowns + makeTownCreateCmd, renamed to their labels, grown
round-robin (forced increment in the town's pure style + two growth passes to 1 + step x 0.25), K = 3 refused
builds / 4 empty plans in a row stop a town, `[SQOT_DEV] SHOWCASE …` log lines, Next / Previous town camera
(`api.gui.camera.setCameraData`, fixed 1800 m, first jump's angle/pitch, optional top-down pitch). Main-mod
changes for it: `ot_driver.startJob` takes `pure` (a profile without its outer zone) and `newTemplates` (force the
template era: the era town), and every ended job carries `job.why` (why it didn't build) and `job.cost`. Tests:
test_layout, test_showcase (fake multi-town engine), 31 dev tests; main mod 149.

**Showcase v2 (2026-10-11, after the first showcase run; TESTING.md "Showcase v2").** First run (Blank Slate,
2020, 16 towns, N=10, ended after ~7 rounds in 9 min): SUMMARY turns=107 built=45 refused=19 empty=1 stopped=2,
105 x `lane_config_util.cpp:364 GetLaneOffset` (Actual 6>=4, 4>=4, 6>=6), no DIAG lines, many `Collision`
refusals, wide empty stubs and kinked leftovers in the screenshots, mod streets mostly unadopted. Root causes and
changes:

- *Lane assertion.* Junction configs used one lane count for every street at a node; a new node where a large
  main piece (8 lanes, road lanes 1..6) met a small one (4 lanes) got index 6 on the 4-lane edge ("6 >= 4"),
  medium vs small "4 >= 4", large vs medium "6 >= 6". The pre-check catches the assertion and answers
  "Construction Not Possible" with 0 collisions. JP dense (main medium 6 lanes, small xsmall 4) stopped on three of
  them. The per-street fix (already in) is completed: `ot_proposal` takes each segment's own count (existing edges
  from the join info, new edges from their copy source / override template, else from the template path; unknown =
  4, valid on every street) and `checkLanes` refuses a spec with any out-of-range index (`laneIndex:` instead of
  an engine assertion). test_proposal checks > 1000 lane references over eras x 4 sizes x joins x overrides.
- *No DIAG.* `ot_driver.notPossible` matched "Construction_Not_Possible", the engine's text has spaces (the log's
  `_` comes from our field formatter); now normalised. With the dev hooks on, DIAG lines name collision partners
  (`partners=edge<id>:<size>@<m from our edge>`, `node<id>`), also on REFUSED.
- *Collisions -> drop, not halve.* A refused pre-check now pre-checks each edge alone (stage `diag`, 6 per tick,
  main driver too), excludes the pieces of the edges that fail and plans again at the same size (`PRUNE_ROUNDS` 2);
  halving only when no single edge fails (combination problems). A leftover under `MIN_USEFUL` 3 edges that closes
  no loop is not built (`TINY`, its first piece excluded). Planner: `ot_plan` refuses a new edge running within
  `clearEdge` 16 m (main / medium class 20 m) of an existing street centre line it doesn't meet (two small town
  streets are 16 m wide together; the old checks only kept nodes 6 m off).
- *Wide streets* (screenshots: our streets wider than the town's). Classes map to `main = medium`, `medium = small`,
  `small = small` (was large / medium / small); MED hill and JP dense small / small / xsmall. Joint edges still copy
  the dead end's own street.
- *Long empty leads.* `ot_select.LEAD_DEPTH`: a piece may end at most 1 piece (main / medium) or 2 pieces (small)
  beyond the network the town has; loop-closing pieces always may (report `maxDepth`; test_grow). Shapes stay
  irregular (test_shape unchanged within noise).
- *Kinked chains* came from the halving retries (budget 4-9 picks scattered cheapest pieces); dropping instead of
  halving, the lead cap and `TINY` remove most. No explicit direction-reversal rule yet: judge from the next
  screenshots.
- *Adoption / vanilla dominance.* The first run showed our streets mostly empty while vanilla growth filled its
  own streets. Now measured: STEP lines split each round's new edges into `mod` / `vanilla`, TOWN lines give
  `modEdges` and `adoption` (edges with lots, lots, houses), the window's Results table compares with the vanilla
  towns. Probes (showcase toggles): **Fill mod streets** (makeTownDevelopAtCmd(point, false, false) beside each new
  mod street: the undo_tf3 mod rebuilds a house with it) and **Freeze style towns** (makeTownSetDevelopmentActiveCmd
  false: does forced UpdateSize still add vanilla streets?). **Locking vanilla street growth:** no command sets
  `roadDevelopmentLocked` on an existing edge (cmd.d.tl has none; the player tool's StreetEdgeNodeModifier is a
  construction action); a proposal can only set it by removing and re-adding the edge, which demolishes its houses
  (HANDOFF D4). So no safe lock; the freeze probe answers whether development-off is one.
- *Speed.* One round = all style-town jobs one after the other, then 2 growth batches (every town's UpdateSize sent
  back to back, one in flight per town), extras, STEP + ROUND lines. Expected ~6-10 s per round for 18 towns (v1:
  ~80 s with pauses; callbacks ~0.3-0.4 s each).
- *Era.* `startJob{ year }` resolves a style as of another year; the showcase era row has NA grid 1900 and EU
  extension 1900 (old templates) beside the map-era towns, logged `era=<year>:<old|new>`. Only the plain town
  templates differ by era (old / new from 1940), so 1960 = 2020: no 1960 column.
- *Results / reset / tour.* Results table in the window; SUMMARY adds modEdges, adopted, modHouses, prunes, tiny,
  roundS, `notPossibleNoCollision` (the lane assertion's signature; grep `lane_config_util` to be sure).
  Reset showcase destroys the towns (makeTownDestroyCmd) and logs streets left per town; if any stay, the next
  layout moves by 1250 m. Auto tour flies to each town (5/10/20 s per view, optional top-down pass) and can take
  screenshots: `api.gui.camera.takeScreenshot(scale)` exists (gui.d.tl, used by the base free-camera menu); the
  game names and stores the files (userdata), we log the order (`SHOT`).

**Roundabouts (NEXT_PHASE_BRIEF 2, probe only).** square_roundabouts' geometry module
(`square_roundabouts_geometry.lua`, pure, plus its shapes/tuning modules) loads by `ug_require` across mods
(presence file `square_roundabouts_presence.lua`); `geom.build(geom.readParams{ sqrb_arms = 3, sqrb_radius_size =
1..3 })` gives a 4-arm ring (4 Hermite edges, counter-clockwise, `town_new_one_way_small`) and 4 straight
`town_new_small` arms in local coordinates (arms at 0/90/180/270 deg, 30 m beyond the curb). The mod itself builds
it as a construction (edge lists, no node configs). `otd_roundabout` rotates/moves it so arm 0 ends on a town dead
end (D3 joint there), the ring ahead in empty land (no live junction rebuilt: removing town edges demolishes houses;
replacing nodes with 2+ edges crashed), tries XS / S / M until the pre-check passes, sends one proposal (player
context, new nodes without configs as in the probe's adopted patches), records ring and arm edges and logs their
adoption (`RB ADOPT`). Ring mode toggle: one-way (not sim-buildable: will the town line it?) or the dead end's two-way
street. Showcase: "EU ext roundabout" gets one at step 3 at its farthest dead end (main / medium streets first).
Decision notes for the rules (after the probe answers): only EU extension, Nordic, NA suburb, Superblock; era gate
~1960+; at main x main crossings planned at the frontier (reserve the spot while empty: the plan's junction keys of
two main pieces, ring placed instead of the 4-way node, arms = the first edges of the four pieces); occasional mini
(XS) on minor crossings; seeded per town (`rng.unit(seed, "rb", junction key) < share`); main mod detects the mod by
the presence file (no hard dependency); any new user-visible string in all 13 languages. (2026-10-14: the main mod's
roundabout town builds one-way rings at its own new crossings, 6.3 "Strong characters, roundabout town, densify"; since
§56 every town may get them at its era / region rate, in four sizes, 6.3 "Roundabout variety and organic ring roads".)

Tests: main 154 (+4: lane matrix, checkLanes, prune at full size, leads), dev 40 (+9: roundabout geometry, showcase
roundabout / Roundabout here, options, reset, layout offset). `make check`, i18n (19 keys), validate, link pass.

**After the settled showcase (2026-10-11, late; NEXT_PHASE_BRIEF 5; in game: TESTING.md "Showcase v3").**

- *Roundabout crash.* "Roundabout here" with the two-way ring and no configs on the 7 new nodes crashed on the
  3rd build (Engine.h:323 BaseNodeConfig, player on): config-less script nodes crash at random. `otd_roundabout.spec`
  now gives every new node a config (`spec.newConfigs`, `RB SEND newNodeConfigs=7/7`): two-way ring nodes the
  engine pattern over ring in / ring out / arm with each segment's lanes (`ot_proposal.junctionConns`), free arm
  ends an empty config. One-way ring: `ot_proposal.junctionConnsDir(segs, info)` with per-segment in / out lane
  lists in node-relative indices (type.d.tl: lanes count "from left to right when looking from the node to the
  segment"; two-way m road lanes: in 1..m/2, out m..m/2+1; one-way arriving: in 1..m; one-way leaving: out m..1;
  pair in_a[k] -> out_b[k]); on two-way-only nodes it equals `junctionConns` (tested). At a one-way ring node:
  ring in -> ring out (both lanes), ring in -> arm, arm -> ring out. Derived, **unverified**: builds only with the
  dev toggle "One-way ring: experimental"; the showcase defaults to the two-way ring. Dev "Node dump" button
  (`otd_nodedump`, `NODEDUMP` / `NODECONN` / `NODEOURS`) logs a node's lane connections with their meaning and
  compares our pattern, for a Roundabouts & Interchanges one-way ring node. Invariant tests: no proposal path
  (main `ot_proposal.build` over planner increments of 7 styles, dev roundabout both modes x 3 sizes x 8 headings x
  lane counts) sends a new node without a config, and every lane index exists.
- *Planner self-collisions* (showcase v2: `REFUSED … msgs=Collision partners=ent-20`, a new edge against one of the
  plan's own new nodes). `ot_plan` checks every new edge against the edges already accepted for the increment
  (`ot_check.pairConflict` on sampled Hermite curves): no crossing (`crossesNew`), no end node within 12 m of
  another new street, bodies apart by half widths (small 8 m, medium/main 12 m: 16 / 20 / 24 m) outside 12 m caps
  at the ends, two edges from one node at least 0.6 x that beyond 30 m (`nearNew`). `ot_check.selfClearance(inc)`
  re-checks a finished increment (tests over every profile x terrain and in dead-end mode; the PLAN line logs
  `self=`). Found on the way: `math.min(..., G.pointSegDist(...))` took pointSegDist's second return value (t) as
  a candidate (Lua multiple returns): wrap such calls in parentheses.
- *Combination refusals* (46 x "Construction Not Possible" with no collision while every edge passed alone).
  Cause unknown (junction geometry, lane configs at new nodes, ...). The driver's diagnosis now pre-checks each
  junction star (a node with its new edges, `D.stars` / `D.subIncrement`) when no single edge fails, logs
  `DIAGNODE`, drops the newest edge of each failing star and plans again at the same size (`PRUNE … by=star`).
  The DIAGNODE lines of the next run should show what the engine refuses.
- *Look rules* (`ot_select`, `ot_core.lookIssues`, `ot_metrics.zigzags` / `lassos`). Zig-zag chain: three corners
  (> 35 deg at nodes left with two streets) alternating left / right along one street; the selector doesn't take
  the piece that would make the third corner (a single S stays: forbidding it stalled towns whose frontier node
  never got a third street). Lasso: a loop hanging off the town on a stem. `ot_graph.structure` (Tarjan bridges,
  2-edge-connected parts, the core, each node's gateway to the core) gives every reached junction a root; a loop
  may close only in a part that reaches the town through two gateways or that hugs the town (closing piece within
  1.5 blocks of a non-bridge street: only dead ends can be joined, so a block beside the town hangs off one stub
  too). Allowing every loop that starts right at a network junction let cheap loop closures near the dead ends
  outbid the shape's arms (tested, dropped). After planning, `ot_core.lookIssues` builds the result
  (`ot_graph.overlay`), finds chains and lassos, leaves out the newest offending piece and re-plans (the cleanest
  round wins). Offline (7 styles x 3 towns x 12 increments from a vanilla core, dead-end joins): 0 chains and
  1 lasso in 21 towns, with the rules off up to 6 chains and 2 lassos per style; growth equal or larger. Not
  caused by the rules but seen on the way: a town whose joinable dead ends run out stalls (dead-end-only joins).
- *Vanilla town street angles* (main mod, new setting `start_angle`, default Automatic; `ot_angles`). preRunFn's
  config dict is a list of {key, value} pairs (base mod.script.tl:184-191), so preRunFn does know the map's
  nameList and climate (the probe read it as a dict and logged nil). It sets `townInitialMajorStreetAngleRange`
  and `townMajorStreetAngleRange` by region: US / Oceania 0, JP / East Asia 15, Nordic 25, RU 30, EU 35, MED 45
  (Probe C: 0 = strict grid, 15 mild, 45 irregular); Grid 0 / Mixed 15 / Organic 40 / Game default. Logs
  `[SQOT] ANGLE`. Skipped with "Act on: Off" since 2026-10-14 (PRERUN line; Off means the mod does nothing). Unverified: whether the new-map generator reads it, and what the
  growth range does to towns already in a save.
- *Showcase v3* (dev): shape row (8 EU extension towns, one per archetype), density row (weights / upgrade at the
  centre / medium streets / control), Settle phase (game speed 4 via `makeGameSetSpeedCmd`, waits N calendar
  months, logs sizes before / after and adoption, then the Auto tour), tour shots after the camera settled.
  TESTING.md "Showcase v3".

Tests: main 187 (test_look, test_shapes, test_angles new; check / driver / proposal extended), dev 50. Planning
time on a 700-edge town (Lua 5.2): EU organic 9 ms -> 17 ms per increment with the look rules (structure and
overlay graphs, zig-zag lookups), NA grid 5 -> 8 ms: over the 5 ms budget (section 7), as the organic planner
already was; slicing the plan stage over ticks is the next step if frames hitch.

**Site styles, hierarchy, stronger shapes, refusals (2026-10-12, NEXT_PHASE_BRIEF 8-10; in game: TESTING.md
"Showcase v4").**

- *Style per town from its site* (new pure module `ot_site`; user: "one map should have various styles"). Features
  0..1 from the 600 m terrain stats and a new 2 km survey (`ot_terrain.wide`: 16 rays x 4 radii, water share, height
  sd / range; once per town and session, `TERRAIN wideWater= wideSd= wideRange=`): `open` (flat, low 2 km height
  spread, dry), `rough`, `coast`, `river`, `valley` (valley or crest axis on sloped ground). weight(style) = region
  bias x era gate x exp(sum affinity x feature) (tables `ot_site.REGION`, `AFFINITY`; gates: superblock and NA
  suburb from 1950, ensanche 1920, extension 1900 (era range 1900+, M4; was 1860 / 1850); dry / subarctic climate bias), seeded draw per town. Saved with
  the plan frame at the first build (`ot_saved` frame field `st`, only for site styles). STYLE line:
  `styleSource=site|saved|forced|region styleWhy=<kind>:open=…,rough=…,coast=…,river=…,valley=…|<region>|<top 3
  weights> hierarchy=late|plain`. Main mod, setting Street style: **Automatic** now acts on every map and uses
  the site style (was: NA maps only, grid only; tooltip and description changed, 13 languages); "North American
  grid" forces the grid as before. The INIT gate `reason=style` is gone. Offline picks over 80 towns (test_site):
  EU flat 68 % sprawl (EU extension 22, EU organic 19, NA suburb 15, superblock 12, ensanche 7), EU valley 89 %
  dense (EU organic 33, MED hill 23, Nordic 15), EU coast mostly EU organic / extension / MED hill / Nordic, US flat
  NA grid 33 / NA suburb 35; an EU map with the four synthetic sites uses >= 4 styles. Previews:
  `uv run tools/ot_preview.py --site EU --site US` -> `svg/site/<region>_<terrain>_t<N>.svg` (header: style and
  why).
- *Street hierarchy by era* (user: more wide streets later where they fit). Profiles may carry `lateTemplates`,
  used from era band 4 (1950) with new templates: NA grid, NA suburb, superblock, MED ensanche get arterial =
  large, collector = medium, local = small; EU styles, MED hill, JP, Nordic keep theirs (main medium or small).
  Wide only on through routes (`ot_select.through`: a main / medium plan piece continuing at both junctions into
  a piece of at least its class; tips, cul-de-sacs and connectors are local width) and only when the piece meets
  another street in the built result (`ot_core.hierarchy`: a node with 3+ streets; a bare spur, also one
  continuing a wide street, stays local). PLAN line `hier=wide<n>/stub<n>/bare<n>/bent<n>/short<n>` (`short`: the
  §73 run rule, 6.2 "Continuous thoroughfares"). A wide edge starting at a
  narrower dead end is marked `wideJoin`: `ot_proposal` gives the joint edge the wide template (copy of the dead
  end's town street with the template overridden; the node config pairs each street's own lanes, checkLanes
  valid; test_hierarchy). Half widths by template (`ot_check.halfWidth(class, template)`: 7 / 8 / 12 / 16 m) feed
  the clearances. Offline: no wide dead-end spur longer than 1.3 blocks; NA grid / superblock 1930 none large.
  Unverified: how the game treats an 8-lane street ending at a 4-lane dead end (mixed widths at a 2-street node).
- *Street mix (2026-10-12, NEXT_PHASE_BRIEF 11; user: "for higher density roads we build it's important they
  still mix in some smaller roads").* Showcase v4: the Superblock town's first increment logged
  `hier=wide14/stub0/bare0` of 16 edges (SUPERBLOCK had `arterialEvery = 1`: every lattice line an arterial; NA
  grid / suburb had only the two origin axes wide and no collectors). Now, from 1950 (profile field `late`, applied
  with `lateTemplates`, before the small-town doubling): NA grid arterials every 6 blocks (1.2 km), collectors every
  2 (`collectorEvery`, 400 m); NA suburb arterials every 8, collectors every 2; the **cross axis** (lattice line
  through the centre across the town axis) is a collector (`crossAxis = "medium"`), the main street along the axis
  stays the arterial. NA suburb (`curvyLocal`) curves its small streets and plans cul-de-sacs in the town itself,
  not only as NA grid's outer zone (cul-de-sacs move to the odd cross lines when collectors take the even ones,
  `mp.culParity`). **Superblock interior** (`sub = { u = 4, v = 3, cross = {{2}, {1, 3}, {2}}, art = 3 }`): the
  350 x 250 lattice stays the arterial grid (cell lines every 3rd main, the others collectors; their positions are
  unchanged, so saved superblock towns keep their lattice), and each cell gets two local streets along the axis
  plus short staggered cross streets (one in the outer strips, two in the middle), so no interior street runs
  straight through a cell; row pieces split only where a cross street meets them (no two-street split points the
  dead-end joins could not use). Interior junctions on an arterial already built as one edge can't be joined later
  (dead-end joins only): old superblock towns keep their open cells, new cells get interiors. Arm leads
  (`ARM_LEAD`) no longer apply to the collector lines (they run across the arms and widened them).
  *Wide lead cap*: in late styles main pieces may reach at most `ot_select.WIDE_REACH` (1.25) fine blocks beyond the
  town's front of junctions (`FRONT_Q`), collectors one more (`WIDE_REACH_MEDIUM`); in an arm corridor of a shaped
  town they may still lead, at local width (`through = false`). Showcase v4 screenshots: arterials ran 300-600 m
  into empty fields. *Log*: `ot_core.mix(inc)` = new length by template size; PLAN line `mix=L/M/S` (% of length),
  BUILT lines `mix=` and `townMix=` (all builds in that town this session). Town mix over 10 increments, flat
  (test_hierarchy "street mix", before -> after, L/M/S %):

  | Style | empty town | vanilla core (dead-end joins; before: core at 0 deg, after: 0.4 deg as in the test) |
  |---|---|---|
  | NA grid | 21/3/76 -> 19/11/70 | 22/0/78 (stalls after 2) -> 13/13/75 (10 increments) |
  | NA suburb | 13/0/87 -> 11/17/72 | 32/0/68 -> 15/33/52 |
  | Superblock | 92/0/8 -> 17/10/73 | 78/0/22 -> 12/20/69 |
  | MED ensanche | 15/20/65 (unchanged) | 17/24/59 -> 8/27/65 |

  Target (large <= ~20 %, medium ~20-30 %, small >= ~50 %) met for large and small everywhere; medium is lower than
  aimed from an empty town (10-17 %). The superblock plan itself is 8/28/63. The asserted bounds: large <= 22 %,
  medium >= 8 %, small >= 50 %. Previews: `uv run tools/ot_preview.py -n 10 --style SUPERBLOCK --terrain flat
  [--core]` (header line `mix large/medium/small %`).
- *Joint kinks (2026-10-12, Showcase v4 DIAGJOINT).* 15 of 16 DIAGJOINT lines: an edge leaving an existing dead end
  at 82-95 deg refused (Construction Not Possible), the same edge continued straight built. `ot_core.jointIssues`
  finds such kinks (a dead end left with one new street turning more than `ot_select.JOINT_TURN` = 60 deg);
  `opts.jointRule` keeps them out (the selector chooses a sharp piece at a dead end only next to a chosen piece that
  continues straight there, a T; the planned result is re-checked and offending pieces excluded for the next
  round). **Off by default**: on in every round it cut growth a lot offline (EU organic shape tests, NA grid / MED
  ensanche from a vanilla core stalled after 1 increment), and such joints built many times in game (DIAG logs only
  failures). The existing per-edge diagnosis already drops a joint edge that fails alone; on top, the driver now
  replans a refused increment that has kinks once with the rule (`JOINTRULE town= kinks= edges=`) before halving.
  PLAN lines log `kinks=<n> jointRule=on|off`, so the next run shows how often kinked joints are planned against the
  DIAGJOINT refusals; if they nearly always fail, turn `JOINT_RULE` on.
- *Stronger shapes, fewer teeth.* `ot_shape.GEOM` longer / narrower arms (linear ka 2.5 kb 0.42, ridge 2.3 / 0.48,
  cross 2.4 / 0.36, fingers wedge 2.4, fan back 0.15, smaller core share); main / medium pieces in an arm corridor
  (`ot_shape.inArm`) may lead one more piece (`ot_select.ARM_LEAD`; small pieces not: longer stems made lassos);
  shaped towns' ribbons follow main pieces only (the organic rings' ribbons filled the wedges). A growth front stops
  spurs: no piece beyond the 90th percentile of the junctions' effective distance + 2.5 blocks (shaped) / 4 blocks
  (compact; hotspots leapfrog) (`FRONT_Q`, `FRONT_REACH*`; the NA preview grew a 2 km arterial into the field
  without it). Saw-tooth: a piece turning a corner (> 60 deg) at a node with one street costs x1.5
  (`CORNER_PEN`); a straight bonus and dropping dangling L legs were tried and left off (lassos, less growth).
  New metric `ot_metrics.teeth` (corners + dead ends per km of new street). Mean of 4 towns, 14 increments from a
  vanilla core, flat (before -> after):

  | Style / shape | elong | arms | side | teeth/km |
  |---|---|---|---|---|
  | EU extension compact | 1.36 -> 1.39 | 1.8 | 0.59 | 4.7 -> 3.2 |
  | EU extension linear | 2.74 -> 5.97 | 1.8 -> 2.0 | | 5.1 -> 3.9 |
  | EU extension cross | 1.56 -> 1.86 | 2.8 | 0.68 -> 0.73 | 5.6 -> 4.0 |
  | EU extension fingers | 1.40 -> 1.12 | 3.5 -> 5.8 | | 5.9 -> 4.1 |
  | EU extension fan | 2.03 -> 1.93 | | 0.78 -> 0.83 | 4.7 -> 3.5 |
  | EU extension twin (drift) | 0.50 -> 0.66 | | 0.70 -> 0.77 | 4.9 -> 3.5 |
  | EU organic linear | 2.90 -> 3.60 | | | 9.8 -> 6.6 |
  | EU organic fan | | | 0.78 -> 0.81 | 8.8 -> 6.6 |
  | NA grid (vanilla core) linear | 1.58 -> 5.60 | | | 2.2 -> 2.0 (edges 69 -> 170) |

  test_shapes asserts linear / ridge >= compact + 1.8 / 1.5, fan side >= 0.78, >= 15 % fewer teeth with the corner
  rule at equal growth (measured 28 %), no edge beyond the front. Planning time rose ~20 % (EU 380-edge towns
  ~17-28 ms per increment in Lua 5.4), so the plan stage is now **sliced over ticks**: `ot_core.planIncrement`
  yields between its rounds through a coroutine once `ot_driver.PLAN_SLICE_US` (4 ms) passed in a tick (falls back
  to one go if coroutines fail, `WARN stage=plan`); PLAN lines log `slices=`. Known, unchanged: NA grid from a 90 m
  vanilla core aligned to its axis stalls after 2-3 increments in the preview (dead-end-only joins run out).
- *Remaining refusals (98 notPossibleNoCollision).* From the v3 log: 18 of 20 single-edge failures with
  "Construction Not Possible" and no collision were `conn:` joint edges (17-31 m), and 24 of 26 failing junction
  stars contained one (shortest 20-38 m, angles 45-55 deg). Hypothesis: the junction footprints (street bodies
  overlapping by max(half widths) / tan(theta / 2) at each node: 19 m at 46 deg for small streets) don't fit on so
  short an edge. Planner fixes: `ot_plan` refuses an edge shorter than its two footprints + 4 m (`footprint`
  reason, also re-checking accepted edges and the existing street at a joint: `ot_check.footprint`); connectors
  leave a dead end at most 60 deg off its street and are >= 24 m (`ot_select.CONN_TURN`, `CONN_MIN`; near misses
  <= 16 m still stand in for the junction). PLAN lines log `footprint=<dropped>`. Dev diagnosis pins it if
  unresolved: a joint edge refused alone with no collision gets `DIAGJOINT … len= turn= deadEndDeg= edgeDeg=
  footprint= existingLen= nearNode= plain= straight= long=` (variant pre-checks: no config change at the joint;
  re-aimed along the dead end's street; same heading, max(40 m, 2 x) long); DIAGSUM `joints=`. Unverified in game.
- *Dev (Showcase v4):* settle by game years / plateau with a real-time cap and optional forced growth passes,
  wider / top-down tour camera for the shape row, density "upgrade" once per town (TESTING.md "Showcase v4").

Tests: main 206 (test_site, test_hierarchy new; plan / grow / driver / shapes extended), dev 57. Street mix and
joint kinks (2026-10-12): main 214. Shapes round (2026-10-12, 6.3): main 223, dev 60.

**Pause and refunds (rev 2, 2026-10-17; player report on rev 1).** "Roads are built in towns while the game is paused"
and "a new game at $0 plunges into the red" (repro: new game, pause at once, wait).
- **Cause.** The driver runs from the game script's `guiUpdate`, which ticks while paused, and paced itself by the
  engine's real-time clock (`api.type.Clock`); only the dev hook `ot_hooks.paused` held it. So the whole head start
  (`HEAD_GAP_S` 3 real s, game time stays 0) ran in a paused new game. Every build has `ctx.player` (the crash-free
  setting) and was charged; only the §68 lock rebuild was booked back.
- **Pause.** `ot_engine.gameSpeed()`: the world's `GAME_SPEED` component, field `speedup` (api/tealdef engine.d.tl
  `GameSpeed`, 0 = paused; nil when unreadable: running). `Driver:gameClock` turns the tick's real-time stamp into
  running time (the time since the last tick is added to `pausedUs` when the game is paused now); `Driver:nowUs()` /
  `clockFn()` are that clock for every stamp and hang guard in the driver (no more `E.nowUs()` there), so cooldowns,
  `CHECK_S`, `AFTER_BUILD_S`, `HEAD_GAP_S`, the callback timeouts (`WAIT_TIMEOUT_S`, `GL.WAIT_S`, fills, names, Works)
  stand still while paused and nothing fires at once on unpause. A paused tick (`Driver:pausedTick`) starts nothing:
  no init, check, head-start job, fill, satellite / Works, rename, stop name, level or RCI command; a build or lock
  build whose callback already came is handled (BUILT / FAILED, its refund), its next stage waits for the game to run.
  `[SQOT] PAUSE state=on|off pausedS= pauses= at=` once per change. `D.PAUSE_GATE` (true). Not scaled by the speed:
  x2 / x4 build at the real-time pace, as before at every speed (scaling would shorten the callback timeouts in real
  time and multiply the per-second work at x4). The dev runner's own drivers never tick, so they keep real time.
- **Refunds.** `Driver:refundBuild(kind, bal0, cost, now)`: the §68 rule (`GL.refund`: the balance drop since the send,
  at most the cost, at least 0.5 x the cost) for every build. The growth send (`Driver:afterPrecheck`, the one path of
  growth increments, the head start, frames, satellites, leads, Works links, bridges, forest lanes) records
  `job.refundBal0`, `Driver:done` books it after BUILT (`REFUND kind=build town= name= amount= why= paid= cost= session=
  n=`); the lock send (`glockFire` / `glockWait`) keeps its `GLOCK event=refund` line. One command in flight, one
  balance window per build: none is refunded twice (a job's `refundBal0` is cleared once used). A booking sent but not
  landed yet counts into the next send's balance (`Driver:balanceAtSend`, `refundsPending`, `REFUND_PENDING_S` 10 s),
  so a lock rebuild right after a growth build gets its whole charge back. No player set (dev toggle) or infinite money
  (no balance): none. STREETS `refund=` (the session total, the lock's included) beside `glockRefund=`. Always on, no
  setting. DevelopAt fills, town creations and level / RCI commands are no build proposals and get no refund
  (whether any of them is charged is unverified).
- Tests: test_driver (+6: a paused game starts nothing and resumes, the head start waits while paused and keeps its gap
  after, a callback handled while paused without a timeout, min(drop, cost) per build incl. the head start / no player /
  infinite money, every `sendBuild` records the balance, pending bookings and a single refund per job), test_glock (+1:
  a lock rebuild after a growth build's refund: each once, the booking in flight counted).
- **No growth without transport** (2026-10-17, player report "towns develop without any player input"; checked in game:
  a new map at $0, nothing built, 16 towns, 19:57-20:10Z): every town's growth target (`cap=x/target`) stayed exactly
  the same; buildings rose by 24 in all (0-6 a town) as towns filled their unbuilt ~5 % on the head start's streets;
  RCI skipped every town (`skip=noAim`, supply 0), no satellite / Works / district founded. The removed testing setting
  was the one lever that grew towns by itself.
- **No player in the build context** (2026-10-17, player report on rev 1: "money is deducted and re-added: it flashes
  on the bottom bar, messes with the graphs"; "new roads are player-owned"). `ot_engine.context(asPlayer)` sets
  `ctx.player` only when `asPlayer == true`; `ot_hooks.player` nil / false = no player (the default), true = with the
  player (the dev toggle "Build as player", now off by default). In game: 37 player-less builds left the balance
  unchanged, no crash, the new streets carry no `PLAYER_OWNED` (findings towns.md). The refund path is unchanged and books only a charged build (`refundBal0` /
  `bal0` only with the player), so a default build logs no REFUND line. Tests: test_driver (the toggle's default,
  charged-path tests set hooks.player = true), test_glock (+ the same), dev test_runner / test_hud (default off).
- **"Testing: grow towns faster" removed** (2026-10-17, player report: towns develop without player input, tycoon
  ranks rise on their own). The param (`test_grow`), `Driver:testGrow`, `D.GROW_*` and its strings are gone; a save that
  had it On simply stops the forced growth. `E.growTown` stays (Works towns' one fill, the dev tools).
- Open (in game): the pause read (`GAME_SPEED.speedup` 0 while paused, from guiUpdate); PAUSE lines on pause / resume;
  no SEND between them; REFUND lines with `why=paid` and the balance back where it was after each build (does the
  callback's balance already show the charge: the §68 open point).

**Town window card and new-town notification (rev 4, 2026-10-17; user request; in game: TESTING.md "Rev 4: town
window card and new-town notification").** An "Organic Towns" card in the base town window and a notification in the
game's feed when the mod founds a Works or district town.
- **Card** (`gui/ot_card.res.lua`: `react-plugin ::TownEowExtensionPoint`, order 45 after District Sizes (40), before
  Statistics (60), condition `notMapEditor`; `gui/ot_card.script.tl`): the base `content_card.ContentCard` (title
  "Organic Towns", a one-line summary as the permanent part, the five sections collapsible, collapsed by default),
  base pieces (native-UI pass 2026-10-17; round 2 after the user's screenshots the same day: thin bars, gaps, visible
  descriptions, no repeats of the header): the header and the values as the base key / value
  row (line_eow "Transported": body text, horizontal spacer, value; character left, phase right, so the collapse
  triangle sits under the value as in the base cards), descriptions visibly under their rows (font-scale-annotation)
  and as the rows' tooltips, bars as a thin `builtin.ProgressBar` (inline 10 px, district colors / TownGrowth, the
  aim as the base threshold mark; ProgressDisplay was 25 px tall), fixed inline gap spacers (`ot_card.gapBefore`;
  only these two inline sheets, docs/ui-guide.md "A card in a base entity window"), explanations and empty
  states as `content_card.makeInfoHint`, the base `card-children-separator` between sections, town links as plain
  Buttons (town icon + name, `selectEntity`); text wraps by the base entity-window card rule; **0 stylesheet rules**
  (`make css-rules`: 0 before and after). Polls
  every 2 s (`useStepStateTimer`): the saved state through `state_native` `findPath` / `find` on the town's keys (never
  the whole copy), the TOWN component, built capacities and, until the town's first weighting step, its live supply;
  the settings once. Hidden in the map editor and for a town without data of ours. `ot_card.view` builds the sections:
  1. *Growth by deliveries*: a legend line, then per district a row ("Residential" / "x% → y%", "x%, on its aim")
     and a thin bar with the built share and the aim as its mark (from `rc` e, else the live usage), the pull (the
     district whose aim is at least 3 points above its target share), the lean (`ot_rci.lean`); a plain line when the
     setting is Game default / Act on Off, or nothing is delivered (an info hint).
  2. *Character*: strong kind (`ck`), deep forest (`fd`), secluded (`ch`), coastal hugger (`cs`), form (`f`), street
     style (`st`, only when saved: a style from the setting isn't), motifs (`mo`): key / value rows (Town type, Form,
     Streets, Features), each description under its row and as its tooltip; no Form row when the header shows the
     form (a town without a kind): its description opens the section.
  3. *Growth phase*: from the new `ui` summary (below): the phase's description (its name is in the header) and,
     toward the next phase (young -> blend / densify / early, blend -> mature), a row "Next: <phase>" / "x%" with a
     thin bar (the tooltip as the base Town Level bar's); a final phase shows the description only; new maps only
     (`fresh`): an older save's towns show none.
  4. *Family*: the parent and the offshoots (`dk`, `wm`) as buttons that open the town's window (`react.fireEvent`
     `selectEntity`, as the base entity links; existing towns only), the offshoot readiness from the summary, or why
     there is none (setting off, a kind that founds none: an info hint).
  5. *Name origin*: one "Named for ..." sentence from the new `no` key (generated names only).
- **Saved state** (`ot_saved`): `no` (name origins "<genTag>,<specTag>,<shape>" from `ot_placename.nameTown` info,
  `ot_card.originCode`; sent once with the names event, `EV_NAMES` param `no`; at most 4000) and `ui` (per town
  "<phase>:<maturity x 20>:<readiness x 20 | ->", `EV_UI`, at most 4000 towns, 64 per event). Both normalised in
  `normalize`; a save without them shows what it can (no phase line on older maps, no name origin).
- **Summary writes** (`Driver:uiNote` at each town check on a new map: `ot_upward.levelPhase` of the check's level
  maturity, `low` for a kind without level weights / deep forest; the readiness ratio from the last `paceGate`;
  `Driver:uiTick` every `UI_FLUSH_S` 30 s: one EV_UI event with the towns whose summary moved two twentieths or
  changed phase / ready state (`ot_card.summaryMoved`), nothing else). `[SQOT] CARD event=summary` once per session,
  then debug.
- **Notification** (`notify/ot_new_town.res.lua` guiType Info, label "Organic Towns: new towns" in the log filter;
  `.script.tl` `useDataState`: title / text with the towns' current names, district or Works icon, click focuses the
  new town and opens its window, unless gone or its id reused (creation revision)). `Driver:noteNewTown` at the claim
  in `offshootCreated` (after EV_WORKS), once per town (`ot_card.shouldNotify`: this session's set and the saved
  `dk` / `wm` / `wk`, so a reload never re-posts; an adopted orphan is never announced); `autoDismissDuration` 60 s.
  `[SQOT] CARD event=notify town= name= kind= parent= parentName= rev=`. Notification entries persist in the base
  save (as Problem Radar's).
- **Logs:** `[SQOT] CARD event=read town= sections= frame= rc= ui= origin= parent= offshoots= rciOn=` the first time a
  town's card finds data in a session (GUI state, at most 200 towns), `CARD event=origins towns= of=` with the names.
- Not shown: the name origin of Works / district towns (named by `ot_offname` at the creation, no origin saved); the
  offshoot readiness of towns that never reached a founding decision (no ratio yet); the phase of towns on an older
  save; a strong kind shown from the frame even when "Strong town characters" was turned Off later.
- Tests: test_card (+14: the mirrored lists, every text, summary round trip / bounds / hysteresis, phase progress, name
  origins, the five sections from plain inputs incl. garbage and old saves, family buttons and readiness, the
  notification's dedupe and texts, `no` / `ui` normalised, capped and idempotent, the driver's batches and reload),
  test_demand (created towns: one notification per claimed town, never twice).

**Name lists from other mods (§72) (2026-10-17; player question; NEXT_PHASE_BRIEF 72; in game: TESTING.md "Name
lists from other mods").** A German list from another mod ("Deutsche Städte und Gemeinden") was not recognized and its
satellite towns got English names.
- **Region by the path's words** (`ot_inputs.region`, also `ot_angles.region` for "Vanilla town street angles"): the
  nameList path (`<modId>::/names/<dir>/<file>.names`) split at every non-letter, matched against country and
  language words in English and native forms (`NAME_WORDS`: german / deutsch / deutschland, francais, nederland,
  polska, italia, espana, norge, sverige, ...; a few long stems for glued names); our state mods' prefixes first, a
  country over a continent, the later of two countries. Words, not substrings: "uk" never hits "duke". Base lists
  and square_names_us_ / ca_ keep their region and country. Unknown lists: the climate, as before.
- **Satellite names in the list's language** (`Driver:listLang`, `nameCls`, `offshootCls`, `offshootListName`,
  `offshootName`): another mod's list keeps its towns' and stops' names (no landscape / stop names, `basePath`
  "notBase"); the Works / districts the mod founds take the country's classifier (`ot_names.COUNTRY_CLS`), else a
  confident guess from the map's town names (`ot_names.guessCls`: script, then site-tag shares; en / de / fr / nl /
  sv / ru / ja only), else unused names of the list's own towns.lua (`ot_names.moddedTownPaths`,
  `ot_engine.townListAt`: the base names.script layout `<modId>::/names/<dir>/<lang>/towns.lua`, at most 12 pcall'd
  requires once per session), else the old composed English / US names. With a German classifier the generator
  candidate (GEN_OFFSHOOT_P) and the word budget run in German too; nothing renames the list's towns.
- **Log:** `[SQOT] NAMELIST list= base= region= country= regionSource= nameRegion= word= cls= clsSource= guess=
  listPath= listN= tries= why=` once after INIT (mod on); `NAMELIST event=listUsedUp` when the list's names run out.
- **Tooltips:** "Town style" (lists from other mods are recognized by their file names, else the climate) and "Town
  and stop names" (their towns keep their names, new satellite towns are named in the list's language), 13 languages.
- Not verified in game: that a missing towns.lua only raises a Lua error under pcall (no log spam, no assert); that
  other mods' lists follow the base folder layout (arizonaranger_washington_names does; our state mods use their own
  script and are recognized by prefix anyway).
- Tests: test_namelist72 (12: detection table incl. base / state-mod parity with the old rules and false-positive
  guards, the dry-map German list's EU region and angle, classifier per country / script, the guess (and its accuracy
  on the real base lists), the list fallback and its paths / caps, base lists unchanged, the NAMELIST line, offshoot
  names on a German list and a used-up list).

**Continuous thoroughfares (§73) (2026-10-17; user: "early on (~1909) medium streets get built in weird
configurations (like just a single track in-between small streets) and causes the car path finding to go in weird
roundabouts"; NEXT_PHASE_BRIEF 73; in game: TESTING.md "Continuous thoroughfares").** Medium / large streets only as
deliberate through routes; everything else at the style's narrower template.
- **Cause (offline, reproduced):** `ot_core.hierarchy` judged each wide piece alone: a main / medium piece whose plan
  line goes on at both ends (`ot_select.through`) and that meets a street kept its wide template, whether or not the
  rest of the line was ever built. EU organic spokes (`sp<i>:<ring>#<n>`, class main, 25-56 m pieces between rings)
  were built one or two pieces per increment, scattered: EU organic 1905 from a vanilla core, 6 increments: 4 medium
  runs of 7 edges, the longest 92 m, one a single edge. Second leak: `ot_proposal.build` gave every edge joining a
  dead end the dead end's own template, so a small street continuing a medium dead end became one medium edge.
- **The run rule** (`ot_core.continuity`, in `hierarchy` after the straight-wide rule, and again in
  `Driver:plan` after the straight guard / forest lanes cut the increment): the connected set of medium / large edges
  (existing + the increment's) a new wide edge belongs to must be >= `RUN_MIN_M` 300 m (three of our <= 100 m
  edges, five EU-organic blocks, 1.5 NA blocks) and reach an anchor: an existing medium / large street (an extension
  or a crossing), a country road at one of its nodes (the exit), the town centre or a rail station within
  `RUN_ANCHOR_M` 150 m; the late hierarchy (`style.hierarchy == "late"`: the sprawling styles from 1950 and the
  metropolis, whose arterial lattice is planned as such) also counts a start on any existing street. Otherwise its
  new edges get `ot_core.narrowTemplate` (the collector template when it isn't wide, else the local one; a JP metro
  main street small, not xsmall) and lose `wideJoin`. A build is one proposal (all or nothing) and a refused one is
  replanned smaller (the rule runs again), so no partial run is left; a run only grows on from an existing one.
- **Early era** (old templates, before 1940): a town of 1900 had one high street, the road through it, and narrow
  lanes; so a new run that doesn't continue an existing one starts only while the town has fewer than `RUN_OLD_MAX`
  (1) runs of 300 m; extensions of the high street (the game core's or ours) go on. From 1940 no count cap.
- **Joins** (`ot_proposal.narrowJoin`): a narrower town street joining a medium / large dead end keeps its own
  template (override; the node config pairs each street's lanes, as for `wideJoin`). A small dead end is still
  copied (no xsmall joints for JP / MED hill).
- **The game's own growth** (unverified whether it carries a wide street on): the §69 open tips and the §67 valve stub
  are never a medium / large edge (`ot_glock.NO_WIDE_TIPS`; BUILT `tipRej=wide:n`). Nothing is removed from the
  sim templates (findings towns.md "Town development needs its small street templates").
- **Logs:** PLAN `hier=.../short<n>` (edges narrowed by the rule) and `runs=<kept>/<cut>/<longest m>`; SNAPSHOT
  `wideRuns=<runs>/<edges>/<m>:short<n>,lone<n>,max<m>;mod<n>,game<n>,other<n>` (the town's medium / large runs
  before the build: shorter than 300 m, single-edge, the longest, the wide edges by builder: ours / the game's
  locked by us / the core and the game's open streets; "0" without one); STREETS `wideRuns=` the same summed over
  the towns' last snapshots.
- Not changed: medium edges already built (saves keep them; a short one becomes part of a run only when a build
  makes it 300 m with an anchor). Offline effect (test_hierarchy, 10 increments, vanilla core 1970): NA grid
  L/M/S 2/46/52 -> 0/24/76, NA suburb 5/33/61 -> 0/23/77, superblock 5/28/67 -> 1/22/77; EU organic 1905: no
  medium (no anchor reaches a 300 m run), from nothing: one 430 m run.
- Tests: test_runs (new, 11: lone edge, long run kept / unanchored cut / station / exit, extensions and stubs, the
  old era's one run, the second pass after a cut and a forest lane, the narrower template, joins, the audit and its
  text, the capped walk, no tips on wide edges, growth over 8 styles x 4 years x vanilla / empty: no short run, the
  old era at most one), test_hierarchy (unit run 300 m from the centre), test_proposal (join lanes), three
  geometry thresholds relaxed (test_head spokes +1 -> +0.75, test_shore bay 1.3 -> 1.25, test_skeleton hug within
  2 %: the narrower streets shift the footprints).

**Close the gap (§74) (2026-10-17; user: "Is it feasible to have our roads connect to each other slightly more
logically when they are so close?"; NEXT_PHASE_BRIEF 74; in game: TESTING.md "Close the gap").** Near-miss dead ends
are joined to the street ahead now and then, more often the closer they are.
- **Cause (from the code):** the planner joins only existing dead ends (`join = "deadEnd"`), and the lattice pieces
  stop short of a street they would meet off a node (ot_select occR block, ot_plan `nearExisting` 16 m centre line /
  `blockedNode` 6 m), so fronts end a piece short of a street (a T never comes) or pass each other; the game's growth
  adds cul-de-sacs. The logs can't say which builder made a given stub (no per-edge geometry).
- **The pass** (`ot_nearmiss.joins`, `ot_core.nearMissPass` after each increment's plan, also when the own empty
  budget holds the town; the driver passes `opts.nearMiss`): dead ends with a street within `JOIN_MAX` 80 m,
  `AHEAD_DEG` 60 ahead, smallest gap first; targets within `NODE_MAX` 100 m: another dead end (`pair`), a street node
  (`tee`), a small 3-way junction (`cross`) that `Driver:midJoinOk` allows (node config, plain town streets of the
  snapshot, no track, no construction, this town). Shapes: line, single arc (>= 74 m), arc-and-straight (100 / 150 /
  240 m), Hermite (up to 8 on the place checks, 4 planned); kink <= 45 deg at a dead end, >= 60 deg to every street at
  a street node (values since "Less cautious" below; 60 since §75, was 50); §75 adds a pair's corner. Checks: buildings (12 m), gap lines, zones,
  greens, country roads on the shape; ot_plan on the street (`joinExtra`); slope / water / crossings / 16 m clearance /
  parallel run (§75: over the whole street the join makes) / loops under 0.25 block / junction spacing 20 m on the
  planned curve. Chance 0.97 to 25 m -> 0.4 at 80 m, fixed per pair; joins through the woods of hug / deep towns keep
  0.5 / 0.75 (§75: through, i.e. 16 m of the join in big-wood cells; was any big wood within 40 m); cap 2 per
  increment; time budget 8 ms per plan.
  Joins are small streets (`nm:<D>:<N>` keys), locked by the policy like any piece; the street node's config is
  rewritten over all its segments (ot_proposal, as at a dead end).
- **Logs:** PLAN `nearMiss=<found>/<joined>/<kept> nmKept= nmJoins= nmErr=`, STREETS `nearMiss=<built>`; `nmKept`
  reasons as in NEXT_PHASE_BRIEF 74 plus `cut` (2026-10-18). `nmJoins=<kind>:<gap>` and since §75 a `c` (a pair's
  corner) / `r` (closing a retired dead end) suffix. Two kept reasons in words (from the code): `curve` no shape of
  the dead end's targets bends gently enough (an arc under ARC_MIN 74 m, a Hermite under 0.9 x 70 m, or the planner's
  own `curve` / `short`); `target` every node ahead failed the target test (a dead end the snapshot marks noJoin:
  retired, a country lane / bridge (`edge`), no config, another town; a 4-way node; a 3-way node with a medium street;
  the driver's midOk; a country road's node).
- **Offline effect:** 36 % of near misses joinable at all (the rest: no node of the street in reach, too sharp, 4-way
  nodes); growth sweep (10 increments): dead ends with a street within 40 m ahead 0.160 -> 0.130 of all dead ends.
- **In game (run 2026-10-18, session `2026-10-18_2222_sqot`, seed `a`, Quick 40; TESTING.md "Close the gap"):** 20
  joins (19 `tee`, 1 `cross`, gaps 19-68 m) in 17 builds, all `ok=true`, 0 REFUSED, no assert / crash in the ~3 min of
  simulated growth after the first one: the config rewrite at a street node builds (docs/findings/towns.md). No `pair`
  join at all; the joins are rare (20 over 271 plans; `nmKept` mostly `curve` 454, `building` 268, `target` 228,
  `noJoin` 200, `noNode` 183). Dead ends on the 16 towns 353 -> 305 against the §71 run.
- **Less cautious (2026-10-18; user: "in game it joins too rarely to notice"):**
  - `KINK_DEG` 35 -> 45 (the join's corner at a dead end, both ends of a pair; still under ot_select `JOINT_TURN` 60),
    `ARC_MIN` 78 -> 74 (ot_plan still holds every cut edge to `MIN_RADIUS` 70); `MAX_TURN_DEG` 120 kept (150 gained
    nothing offline).
  - `NODE_MAX` 100 (was `JOIN_MAX` 80): target nodes up to 100 m away while the street ahead stays within 80 m (the
    next node of a long street ahead often lies just past 80 m: offline `noNode` 63 -> 20).
  - `GEN_SHAPES` 8: up to 8 shapes per target on the place checks (houses, water, gap lines: no plan), still at most
    `MAX_SHAPES` 4 planned (the per-plan cost unchanged): a shape over a house gives way to one beside it.
  - Chance: `SURE_M` 15 -> 25 m, `P_FAR` 0.15 -> 0.4 (in game `chance` kept 86 against 20 joined). `MAX_PER_INC` 2
    kept (`cap` never kept a join in the seed `a` run), the 8 ms budget kept.
  - Retired dead ends (the mod's own empty stubs, R4; snapshot `retired` 298 in the seed `a` run): still never
    extended, but a near-miss join may now close one, as its start or as a pair's partner, when retirement is its only
    noJoin reason (`nmRetired`, its join info in `g.nmRetiredInfo`; `Driver:retiredJoinOk` -> `job.nmInfo`;
    ot_plan `joinExtra[n] = "retired"`; `D.NEAR_MISS_RETIRED`). Likely the main reason no `pair` joined in game: the
    stubs "curling past each other" are mostly lattice fronts that stayed empty, so both were noJoin (`noJoin` 200 /
    `target` 228). The geometry is the other reason: two parallel stubs a lattice row apart (offset 50 m, overlapping
    30 m) or side by side pointing the same way need a Z-jog / hairpin, and stay.
  - New kept reason `cut`: a snapshot dead end that the game sees more streets at (snapshot `degree`, 600 in the run:
    the snapshot's edge, no dead end) was counted as `noJoin`. Country roads' nodes are no targets now (a pair's partner
    or a street node; before only midOk caught them in game).
  - Tried and dropped: a corner shape (two straight legs meeting at a new node, corner <= 45 deg, legs >= 20 m) for
    joins no curve can make: 0 extra joins in the census (the 45 deg kinks already cover what it could reach).
  - Side T (edge split, `noNode`): deferred. Splitting a town edge removes it (findings towns.md D4: removing a dead-end
    edge and rebuilding it longer cost 776k, likely the houses along it; only a same-geometry rebuild is known to keep
    its houses), and no build of ours has split an edge; it needs a console probe first (a split of a housed town
    edge: buildings before / after, the collision list, the two halves' parcels).
  - Offline (`test_nearmiss_census`, full: 18 towns grown 10 increments without the pass, houses 15 m off every street,
    every chance 1, no cap): joinable near misses 87 -> 116 of 267 (pair 7 -> 6, tee 67 -> 93, cross 6 -> 11); kept
    `noNode` 63 -> 20, `curve` 47 -> 35, `building` 26 -> 37, `target` 37 -> 46 (more targets tried per dead end);
    expected joins under the chance 36.8 -> 67.2 (+83 %). Growth sweep (full, 40 m share): organic 0.114 -> 0.090,
    others 0.198 -> 0.130. Slowest uncapped pass 9.3 -> 13.6 ms offline (in game MAX_TESTS / MAX_PLANS and the 8 ms
    budget hold it).
- **In game, less cautious (run 2026-10-19, session `2026-10-19_0024_sqot`, seed `a`, Quick 40; TESTING.md "Close
  the gap"):** 34 joins (23 `tee`, 10 `cross`, 1 `pair`; gaps 26-95 m, 4 past 80 m) in 32 builds, all `ok=true`,
  0 REFUSED, no assert / crash: 1.7x the last run (offline 1.8x). `nmKept` `noNode` 183 -> 36, `noJoin` 200 -> 93,
  `building` 268 -> 461, `target` 228 -> 170, but `curve` 455 and `chance` 86 unchanged; `cut` 6. Plan time median /
  p90 / max 42 / 193 / 398 ms; `nmKept=budget` on 7 plans (late, big towns). No house loss beyond the other builds'.
  Still rare to the eye: joins can't be picked out in the tour shots, and dead ends on the 16 towns 331 vs 305
  (run-to-run spread of the game's growth). Retired joins aren't logged (no token), so whether `D.NEAR_MISS_RETIRED`
  ever closed one is unknown (at most 1). (§75, 2026-10-19: none could: ot_core.nearMissPass did not pass the driver's
  `retiredOk` on to the pass, so every retired dead end stayed `noJoin` / `target`; fixed, and `r` marks such a join.)
- **Open:** a T on an edge's side (edge split, deferred above; only `noNode` 36 left, so it would add little now);
  `curve` (455) is the biggest kept reason left, then `building` (461); pair joins still about none (1); cars routing
  through a rewritten street node (no vehicles in either seed `a` run); a close-up look at a few joins (dev showcase or
  zoomed shots). (The retired-join token: done in §75, `r`.)
- Tests: test_nearmiss (22), test_nearmiss_census (new: old rules against new), test_driver (+1, R4 retire +
  retiredJoinOk).

**Wider minimum block (2026-10-18; user: "several examples of a square of road where only one large building
fits in between ... two roads very close where you can only fit the smallest size building ... it's too frequent";
the light touch; in game: TESTING.md "Wider minimum block").** Two parallel streets' centerlines at least 44 m apart
(`ot_style.MIN_BLOCK`, was 40: it counted the street as 8 m, but a small town street is 16 m with its sidewalks, so 40 m
left 24 m of land and 1-cell slivers; 44 m leaves 28 m, a row of 3-cell lots; 48 m would fit two 2-cell lots back to
back but thins the towns more). Copies in `ot_character.MIN_BLOCK` and `ot_forest.deepStyle` (require cycle).
- **The jitter no longer undercuts it** (`ot_grow_organic.masterPlan`): stripCount / laneCount / armLaneCount capped only
  the mean spacing; the offsets, wobble and tilt put a cross lane ~0.55 block off the ring it runs along (5 m at worst
  in the sweep) and secondary radials closer than a block. Now each cross lane is shifted into [previous kept lane + 44 m,
  strip end - 44 m x (lanes left + 1)] on both its strips (the shorter strip and the ring gap set the fraction; its tilt
  dropped when both don't fit; a lane with no room even then is left out, ~1 %), each secondary radial into [previous +
  44 m, arc end - 44 m x (radials left + 1)] on the shorter arc: the shift itself keeps the counts (the MIN_BLOCK caps in laneCount / stripCount do not: see
  the growth-front bullet below), the positions get more even (most lanes
  sit at a cap, so ~80 % are shifted). Deep arms' back rows at least 44 m apart, within the band of BACK_ROWS x the
  style's depth (MED hill: one row at 44 m instead of two at 30 / 60: the band does not cut wider into the woods).
- **Data:** MED hill `block.len` 40 -> 44 (blocks never under the minimum); the hilltop kind's rings 110 -> 118 m (the
  narrowest wobbled gap, 0.75 x ringEvery, keeps two blocks and its lane; at 110 those cells lost the lane and hilltop
  towns stalled in the test model).
- **Offline effect** (probe: 5 styles x 4 towns x 10 increments on the round test core; spacing of each street to its
  nearest parallel neighbour): below 40 m 18 % -> 0.7 % of streets, below 44 m 25 % -> 10 %; EU organic median 54 -> 52 m,
  n 465 -> 502; MED hill below 40 m 41 % -> 0 %, median 47 -> 54 m, n 334 -> 281; JP dense (grid grower, lines >= 44 m,
  node jitter +-5 m) below 40 m 18.5 % -> 1.2 %. Master plan length within 500 m: MED hill / EU organic -10 % / -8 %.
- **Growth model side effects:** fewer pieces in reach of the growth front: in the test models MED hill towns stall a
  little more often (3 of 36 vs 2 in the probe's model); the hug / deep MED towns cut more woods (cross of clearings
  0.19 -> 0.35 of the clear town's cut). The test suite's seeded single-town checks moved with the plan (any plan change
  reshuffles ~8-14 of them): those re-seeded or re-calibrated name the change and the pass rate over other towns.
- **The growth front after the wider block (same day; the full tier's 4 failures).** The plan is sparser than "the
  counts stay" suggested: laneCount / stripCount cap at MIN_BLOCK, so EU organic (45 m deep blocks) lost one lane per
  ring cell (8358 lanes vs 9575 over 30 towns, ~1 % from the shift itself) and ~20 % of its pieces within 450 m. The
  growth front (`ot_select` FRONT_Q of the junctions + FRONT_REACH blocks) moves only with junctions, i.e. the mod's own
  streets (the test models' game extends its dead ends), so fewer pieces in reach fed back: in test_demand's EU organic
  models increments came out half full and towns stopped for good (no brake, 36 towns: grown-phase mod share 0.39 ->
  0.24, young 0.47 -> 0.44; a fast grower's allowance gained + 0.010 over the old cap instead of + 0.063). Two driver
  limits fix it, not a global lever (an under-filled-increment relaxation in the select restored it too but broke 5
  shape tests: shore, linear head start, hilltop, street village): `limits.frontRelax` (a demand build of a town whose
  last plan came out empty, `s.emptyRun`: up to `ot_select.FRONT_RELAX` = 2 blocks, one per step, only when the front
  alone would leave this increment empty, last of the relaxations) and `limits.frontExtra` (a fast grower's demand build:
  `ot_driver.FAST_FRONT` = 1 block per unit of its fast factor above 1, up to + 2). The lead limit, housed front and depth
  caps hold. Now (same models): grown share 0.56, young 0.46; fast allowance + 0.058 (scarce checks + 0.046, was + 0.042);
  EU organic / frontage runs that never build 7 of 40 (10 at 40 m, 14 at 44 m without it), share 0.27 (0.21 at 40 m).
  In game (seed `a`, Quick 40, run 2026-10-18 `2026-10-18_2222_sqot`, against the §71 run `2026-10-16_1846_sqot`):
  0 STALL, 2 STUCK (as before), persons 44155 vs 44159, buildings 9212 vs 9384, mod street 100 vs 108 km, median
  radius 457 vs 495 m, persons / ha +13 %; the game's own streets fill more (game share of the towns' street length 0.51
  vs 0.48). `frontRelax` / `frontExtra` are not logged, so their in-game effect is unseen; narrow blocks can't be
  judged in the 1800 m overview shots (TESTING.md "Wider minimum block"). Two seeded checks were luck, re-set
  with the pass rates in their comments: test_demand EU organic / frontage "at most one of 5 runs builds nothing"
  (was every run builds; old plan 10 of 40 towns never built, so 24 % luck), test_arms "at most one more lasso" (over 40
  towns the deep arms make ~2x the lassos of the plain arms in both plans; fingers 15 / 7 at 40 m, 17 / 7 at 44 m).
- Tests: test_fixes (+2: the trace `ot_grow_organic.TRACE` over 3 organic styles x deep / not, every lane, radial and
  back row >= MIN_BLOCK; the MIN_BLOCK pin 44; the growth front's frontRelax / frontExtra), the re-seeds / calibrations
  listed in each test's comment. `make gate-full` green.

**Side streets and parallel streets (§75) (2026-10-19; user shots: (A) a side street leaving a curving street at
~20-30 deg and running back beside it ~20-30 m away to a hairpin dead end; (B) a street running 200 m+ beside a
diagonal main street ~40-50 m center to center, one row of houses between, then turning to join it; (C) a forest town
by the water: two dead ends ~60-80 m apart at right angles, the corner closing the block never made; in game: TESTING.md
"Side streets and parallel streets").**
- **Why (from the code; the logs hold no per-edge geometry, and the game's own streets can look the same):** (A) the
  planner's only junction angle was `minAngle` 25 deg (ot_plan DEFAULTS, ot_check LIMITS) for any two streets at a
  node; (B) ot_knot's parallel rule could practically never fire: it left out `END_SKIP` 30 m at both ends of each
  piece and needed a 60 m run, and pieces are cut at maxSeg 100 m (40 m left at most); it saw one piece, never the
  street it extends; `PAR_MAX` 35 m was under the 40-50 m seen; motif / ring / connector pieces were exempt and the
  rule gave way when the increment would be empty. (C) below, "close the gap review".
- **Side-street rule** (`ot_check.sideBad` / `isFork`, `LIMITS.sideAngle` 60): at a junction (a node with 3+ streets)
  a new street meets every other street there at least 60 deg off (a side street at 60-120 deg); the one exception is
  a fork, two arms splitting a third street's straight continuation between them, each 12-50 deg off it
  (`FORK_DEV` / `FORK_MAX`); a bend (two streets) keeps `minAngle` 25. Pairs of existing streets stand. Held by the
  planner (`ot_plan` `sideAngle`, off by default; ot_core passes 60 for steer towns of organic growers) and by the
  selector (`ot_select` `SIDE`: a fourth knot reason `side`, from the actual node position and the graph's tangents,
  so pieces don't spend the budget only to be refused; never relaxed). ot_check reports `side` (PLAN `geoSide=`), not
  in `geoBad` / `passes` (other towns' plans keep it). Exempt: the climbing motifs (`SIDE_FREE` switchbacks /
  hill_climb: their streets follow the slope and branch where the shelf is; the piece's `sideFree` goes on to the
  planner's edges) and grid growers (`SIDE_GRID` false: their lattice meets at right angles; the acute joins are where
  it meets the old core's stubs, and holding them cost NA grid / JP dense 14-26 % of their street length offline).
  The near-miss T: `TEE_MIN_DEG` 50 -> 60 and its planner runs with `sideAngle` 60.
- **Parallel streets** (`ot_knot`): the run over the whole street through the piece: `chainBehind` walks back from
  each end through nodes with exactly one other street (graph streets and this increment's chosen pieces; `CHAIN_WALK`
  8 edges, `CHAIN_BACK_M` 300 m, each node once), `streetLine` joins chain + piece + chain, and `parallelRun` leaves
  `END_SKIP` 30 m out only at a junction end (its approach), counts a street bent back beside itself (`SELF_ARC_K` 3 x
  parM of arc apart) and only runs reaching `PIECE_RUN_M` 30 m (or half the piece) into the piece (a piece turning away
  from an old parallel street is no knot). `PAR_K` 0.65 -> **0.9**, `PAR_MAX` 35 -> **50 m**, the run
  clamp(1 x block length, 60, **200** m). Why 50: two 16 m streets and one row of the deepest (4-cell, 32 m) lots are
  48 m apart; closer, both streets share one row of houses. Why 0.9 and not 1.0: the organic lattice lays lanes and
  back rows a block depth apart, at least MIN_BLOCK 44 m (EU organic 45 m blocks): at 1.0 its own lanes at 44-45 m
  counted whenever two lane pieces were built before the radial crossing them; 0.9 keeps the limit just under them (EU organic 40.5 m, MED hill 27 m, EU
  extension and larger 50 m). Never relaxed; connector pieces too (motif and ring pieces still exempt); the near-miss
  joins through `parallelKnot` (the streets behind both ends of a pair).
- **Offline effect** (6 seeds x 10 increments, steer towns on the round test core, before / after): street length EU
  organic 42.6 -> 41.8 km, EU extension 64.6 -> 59.2 km, MED hill 35.0 -> 38.8 km (seed spread), grids unchanged;
  side junctions under 60 deg in what was built 11 / 4 / 23 -> 0; holds `side` 22 / 14 / 38, `parallel` 21 / 2 / 7.
  test_demand's fast grower (EU organic model): pooled mod share 0.44 -> 0.40 with the side rule (both arms of the
  comparison), its margin re-set (comment there).
- **Close the gap review (case C; §74 joins):**
  - **Retired dead ends never joined (bug):** `ot_core.nearMissPass` passed `midOk` but not the driver's `retiredOk`
    to `ot_nearmiss.joins`, so `D.NEAR_MISS_RETIRED` (2026-10-18) never worked: a retired dead end (the mod's own
    street empty for more than `RETIRE_CHECKS` 4 snapshots; SNAPSHOT `noJoin=retired:` 631 in the 2 h real-play
    session `2026-10-19_0531_sqot-sqrl`) stayed `noJoin` as a start and `target` as a partner. That session joined 1
    of 962 near misses (`noJoin` 338, `target` 265, `building` 192, `curve` 78, `chance` 38). A forest town's own stubs
    stay empty longest, so case C's pair was likely two retired stubs. Fixed; `r` marks such a join.
  - **Woods:** the forest keep (0.5 hug / 0.75 deep, fixed per pair) applied when a big wood lay within 40 m (+ half a
    50 m cell) of the join's middle or the dead end: in a forest town nearly every join, also one closing a block on
    the town's cleared land. Now only a join running `WOOD_RUN_M` 16 m through big-wood cells (`woodRun`).
  - **The corner:** two dead ends at right angles 60-80 m apart can't join in one arc of 74 m+ (a quarter turn needs
    ~105 m) and the arcs / line with 45 deg kinks at both ends make a chamfer; the corner (`M.corner`, `CORNER` on:
    both streets straight on to where they meet, a 45-100 deg turn at a new node, legs at least 20 m, within DETOUR)
    is the shape the eye expects, scored ahead of the kinked arcs. (2026-10-18 tried a corner of at most 45 deg: no
    gain; a block corner is what case C lacks.) ot_check passes it: a break of `cornerFrom` 45 deg or more at a
    two-street node is a deliberate corner, not a kink (the NA grid's corners build in game).
  - **The 2026-10-19_1745 session** (Long Fork Beach: EU extension, coast, forest share 0.46, not deep): 2 near misses,
    `curve:1,target:1`, both plans (`nearMiss=2/0/2`): one dead end whose arcs were all too tight (the corner case
    above, likely), one whose node ahead failed the target test (a noJoin dead end: there `edge:2` / `degree:2`).
  - Checked and kept: `AHEAD_DEG` 60 (a right-angle pair is found from the dead end whose line points at the other's
    street; the corner then needs no kink at either end), `JOIN_MAX` 80 / `NODE_MAX` 100, `KINK_DEG` 45, `MAX_PER_INC`
    2 (`cap` never kept a join in game), the fixed per-pair chance (recommendation: a draw per decade instead, so a pair
    left by chance may close later).
  - Offline census (full, 18 towns): joinable near misses 115 of 267 (§74: 116; TEE 60 costs one).
- Tests: test_side75 (new, 12: the side rule and forks; case A in the planner / checker and the selector; case B's
  geometry, chain and caps, the selector holding it (never relaxed, connectors too), 70 m off free, a chain through
  pieces chosen earlier in the same increment; the lattice's own
  lanes free; a near-miss join extending a parallel street; case C joined by a corner in a hug / deep town on cleared
  land, still kept through the woods; retiredOk reaching the pass; the T at 60 deg; the knot text), test_knot (parM;
  the sliver from dead end 1, the lasso's relax with SIDE off), test_tune71 (a junction piece at 73 deg), test_nearmiss
  (case 2 at 40 m, the 28 m stub stays; the old-rules check without the corner), test_demand (fast grower margin).
- **In game (run 2026-10-19, session `2026-10-19_1949_sqot`, seed `a`, Quick 40; TESTING.md "Side streets and
  parallel streets"):** holds 92 pieces (`side` 40, `parallel` 22, `cross` 28, `loop` 2); mod street 95.9 km on the 16
  towns vs 106.1 (§74 run) and 97.3 (§73 run), buildings the same, 3 STUCK as before; 39 near-miss joins incl. 4 pairs,
  2 corners and the first 5 closing retired stubs, all built; `nmKept=noJoin` 10 (0531 baseline 338), `target` 139
  (265). Two fixes from it (2026-10-19): `ot_check.SIDE_TOL` 0.1 deg (the 6 `geoSide=1` plans were near-miss Ts clamped
  to exactly 60 deg, read back at 59.99x), and `knotHeld` / `knotRelax` on the empty PLAN line and `knotHeld` on STUCK
  (`ot_driver.knotText`: whether the never-relaxed holds empty a town's plans was unreadable). Tests: test_side75 (+1),
  test_forced (+3 checks).
- **Follow-ups after the 2026-10-19_1949 run (shot 4 (a) and shot 5 (a) built 2026-10-19, the rest open; user shots
  4 and 5, taken mid-run; the log couldn't name the town or the builder: no per-edge geometry, no camera line outside
  the tour; since 2026-10-19 the PROV lines and the console lookup can):**
  - **Shot 4, a triangle island at a 90 deg bend** (a chord leaves the bend's start and meets the far arm at ~30 deg,
    ~40 x 60 m, three houses). A grower piece can't make it now: at the far node the chord is ~30 deg off the street
    going on straight there (side rule; no fork, the through street is 0 deg off its own continuation). At the near
    node it could pass as a fork (12-50 deg each off the continuation), and the loop rule would not hold it: the
    triangle's ~2000-2500 m2 is over `LOOP_K` 0.5 x 60 x 45 = 1350 m2 in EU organic (MED hill 660, EU extension 4400),
    and loop gives way in a relaxed plan. Left: the game's own growth (about half the towns' street length; no side
    rule), a starting-town street, a climbing motif's piece (`SIDE_FREE`), or a pair of streets that were both there.
    Proposals: (a) **first, provenance** (no design risk; **built 2026-10-19**, "Follow-ups built" below): a SQOT_DEV
    line per built edge (entity, town, key / origin, end points) and a console line that names the builder of the edge
    nearest a point, so a screenshot can be traced;
    (b) if it is ours: a floor on the loop area for 3-street loops (`LOOP_MIN` ~2500 m2, never relaxed for
    triangles; costs: small greens the village-green motif makes on purpose are motif pieces, exempt); (c) no fork at
    a bend: the fork's third street straight for ~40 m (or `FORK_MAX` 50 -> 40); costs some natural Y splits; (d) if
    it is the game's: only the lock policy reaches it.
  - **Shot 5, three long empty parallel dead ends ~45 m apart on open grass, a comb of two short streets off the
    middle one** (straight, right angles, rounded ends: the game's dead-end caps). Most likely the organic lattice's
    lanes / back rows (MIN_BLOCK 44 m apart) built by demand plans ahead of the houses. Why the rules let them: PAR_K
    0.9 keeps the parallel limit under the lattice's own spacing on purpose (EU organic 40.5 m; EU extension 50 m
    would hold 45 m when the run reaches its 110 m block length); the lead limit lets empty streets go to `leadCap`
    150 m from any housed street (the housed plaza beside them); the own empty budget allows several hundred metres of
    the mod's empty street; the sparse rule (§57) runs only on forced plans (`sparseHeld` 0 in this run and the last);
    the near-miss pass joins only a dead end with a street ahead (60 deg cone), and parallel fingers have none.
    Proposals: (a) **one empty row at a time** (**built 2026-10-19**, "Follow-ups built" below): hold a lane piece
    running within ~1.2 block depths beside a mod street that is still empty (no houses) over its run; the houses come
    on the first row before the next is laid; (b)
    **closed blocks before combs:** a lane piece parallel to an empty dead end waits until the cross piece tying the two
    ends exists or is chosen in the same plan (the comb becomes a block); (c) a shorter lead for parallel lanes (150 ->
    ~90 m, one block depth past a housed street); (d) the sparse rule on demand plans of organic towns at a lower
    threshold. Costs: (a)-(c) slow the growth front, the same feedback as "the growth front after the wider block"
    (fewer pieces in reach, more STUCK; `frontRelax` / `frontExtra` may need to cover them); (b) needs the selector to
    pair pieces. Needs a decision; (a) is the smallest change.
  - **Follow-ups built (2026-10-19; user approved shot 4 (a) and shot 5 (a); offline only, in game: TESTING.md "Side
    streets and parallel streets" 5.-6.):**
    - **Street provenance** (`ot_prov`): after every successful build the driver logs (debug log on) one line per built
      edge, `PROV town= name= edge=<entity> n=<node0>,<node1> a=<x>,<y> b=<x>,<y> len= src= key=<plan piece key>
      trig=<demand|head|force|...> seq=<the town's build number this session> year= lock=0|1` (at most `LINES_MAX` 24
      per build, then `PROV ... more=<n>`), and always sends the record to the game script (event
      `square_organic_towns.prov`, ot_saved `pv`; layout and caps: "Provenance record: bounded" below). `src` = `nm:<tee|cross|pair>[c]` for a near-miss join (c: a pair's corner;
      ot_nearmiss now marks `nearMissCorner`), the job kind (`sat` / `lead` / `works` / `bridge` / `frame`), else the
      plan piece's origin (`plain`, `arm`, `ring`, `crescent`, `link`, `m:<motif>`), then `/<key head>` (organic
      lattice `sp` spoke, `sr` secondary radial, `bk` back row, `ln` cross lane, `tip`, `rg` ring; `conn` connector;
      left out when it repeats the kind: `frame`, `lead`, not `frame/frame`).
      The console lookup `ug_require("square_organic_towns::/organic_towns/ot_prov.lua").who()` (the street under the
      cursor; or `who(<edge id>)`, `who(<x>, <y>)`) reads the saved record through `state_native` (the console's own
      `ug_require` can't see the driver's memory, docs/console.md) and prints `[SQOT] WHO edge= a= b= locked= ours=yes
      | likely | probably | no ...`: `yes` (the edge is in the record), `likely` (a record within 12 m along it: the
      game split or rebuilt the street since, a new entity), a §67 game lock (`gx`), `probably` (locked, no record:
      built before the records began or dropped past the cap), `no` (no record, not locked: the game's own growth or
      the original layout; or an open tip the mod built before 2026-10-19). Records exist only from this version on;
      the session's `own` set is not restored from them (left as is: the retire / own-empty logic keeps its meaning).
      Tests: test_prov (10).
    - **Provenance record: bounded (2026-10-20, before release; user: "make sure we do that cap, or otherwise don't
      impact performance").** Cost: the game script's `guiUpdate` copies the whole saved state with `state:get()`
      every frame (Main Thread, TICKCOST `getMaxUs` 180-330 us in the 1949 / 0001 runs, before any `pv`); event
      applies run on the simulation threads only when an event comes. The first layout (one string per town, 12,000
      chars each, 1,000 towns) grew ~66 chars an edge: 994 edges = ~65 KB in the 4-minute 0205 run (16 towns), and
      up to 12 MB on a big map in a long game, all copied every frame. Now: **one string for the map** (one Lua
      object to copy, not one per town), entries `<town>,<edge>,<src>,<trig>,<year>,<x0>,<y0>,<dx>,<dy>,<mx>,<my>` in
      build order (plain pieces stored `/<piece>`, trig one letter `d`/`h`/`f`/`o`, the far end and the Hermite
      middle as offsets, whole metres, no session `seq`): ~40-46 chars an edge. Caps: **`TOTAL_MAX` 32768 chars**
      (~700-800 edges, ~40 km of street: a per-frame copy of at most 32 KB, a memcpy of a few us, beside the existing
      state's 180-330 us) with the map's oldest dropped first, and **`TOWN_N` 120 entries a town** (its oldest first,
      so one busy town can't push the others out). An append is a few plain string finds over the record, one rebuild
      of the string and a cut at the front: no parse of the record, nothing per tick; a 1,000-town x 12-round worst
      case (36,000 events, test_prov) stays under the cap in about a second offline. A save from before has no `pv`
      (nil: no work); the per-town tables of the 2026-10-19 dev build convert once (at most `CONVERT_MAX` 2000
      entries, by year). Kept with the debug log off too (32 KB is cheap, and players' bug reports can use `who()`).
      TICKCOST now ends `getAvgUs= ... pvB=<chars> pvN=<entries>`.
      (The whole-state copy each frame itself: taken off the frame path 2026-10-20, "The saved state off the frame
      path" below.)
    - **`who()` fixes (2026-10-20, session `2026-10-20_0228_sqot-sqrl` + the live log):** the first try was a bare
      `who()` (console history: "attempt to call global 'who' (a nil value)", shown only in the console window);
      the full line then printed `[SQOT] WHO no street within 40 m of -408,-4743` with the cursor on a street: the
      octree matches an edge by its middle (findings roads.md "Octree edge search"), so a 40 m circle missed a long
      street. Now the circle is `SEARCH_R` 300 m (PICK_R + half the longest street edge), the nearest street by its
      curve within `PICK_R` 40 m wins (at most `EDGES_MAX` 3000 read), and a miss names the nearest street's
      distance and how many edges the circle held. The whole lookup runs in pcall: an error prints `[SQOT] WHO error
      <reason>`; no game-script state or no record says so.
    - **The saved state off the frame path (2026-10-20; user: "no regressions in behavior or performance"; offline
      only, in game: TESTING.md "Side streets and parallel streets" 5. (d), 7.).** `guiUpdate` copied the whole saved
      state (`state:get()`, `pv` included) every frame on the Main Thread for the driver, which needs every key but
      `pv`. Options checked against the API (`base/tealdef/scripts/gamescript.d.tl`, `api/tealdef/api/engine.d.tl`,
      `api/type.d.tl`; findings game-scripts.md / gui.md): (a) per-key reads through `state_native:find(key)`: the
      driver reads every key but `pv`, so each frame would still convert nearly the whole state (`asTable()` per key);
      (c) a second state the driver never reads: a game script has one state, guiUpdate's is a
      `GameScriptStateReadOnly` with `get` only, and a second game script would need its own `.gs.lua`, a split of
      the record's events and a migration: no. **(b) built: copy only when the state changed.** handleEvent bumps a
      change number `rev` with every `state:set` (`ot_saved.bumpRev`; `normalize` keeps it, a foreign layout too);
      guiUpdate reads it through the GAME_SCRIPT component's `state_native:find("rev")` (the town window card's read,
      verified on the Main Thread 2026-10-17, findings gui.md; never the game script's own `get_native`, which asserts
      on the simulation thread) and passes the last copy again while the number inside that copy matches
      (`ot_saved.Reader`). A full copy (the old `state:get()`) still runs: with no copy yet; when the native number
      and the copy's differ (either view may lag: every frame until they agree, as the old path); at least every
      `READ_REFRESH_S` 2 s (a save loaded into the same Lua state, a change without a bump); and after the driver sent
      an event (`ot_engine.sentN` moved; `Reader:expect`) every frame until the copy's number moved, at most
      `READ_WATCH_S` 2 s, so the driver sees its own changes the frame the old path did even if the native number lags
      (only a player's new Road Stop, written from `onPostBuildProposal`, relies on the native number alone; the stop
      queue is drained at `STOP_CHECK_S` pace anyway). **Never worse than before:** any error of the number read (no
      entity, no component, no `state_native`, not a number) or of the reader puts the session back on a copy every
      frame (`mode` get) with one `[SQOT] STATEREAD mode=get reason=...` warning; so does a cost check every
      `READ_CHECK_N` 2000 frames when the number reads plus that window's copies cost as much as a copy every frame
      (the session's mean copy; e.g. if `getComponent` itself copied the whole state); `READ_REV = false` is the old
      path. A failed copy gives nil as before. The driver never writes into the copy (twin-driver test). Expected
      saving: from a copy every frame (~110 Hz) to one per change / 2 s plus a few after each sent event: TICKCOST
      `getAvgUs` from about the copy's cost to a few us, `getN` from the tick count to a few hundred per 5-minute
      window; `getMaxUs` stays a copy's cost (copies still happen on changes). TICKCOST adds `getN=<full copies>
      stateMode=rev|get revMiss=<copies that disagreed with the number read just before, session total>` (revMiss >
      0: the two views lag each other, the watch covers the driver's own events). Tests: test_stateread (8: the
      number; the same data as the old path with every key; lag either way and the watch; an old save, a nil state, a
      failed copy; fallback on every error kind, reason once; the cost check; handleEvent's bump; guiUpdate with a fake
      engine, cached / fallback), test_driver (+3: two drivers on two fake engines, one fed a copy every frame and one
      through the reader with the native number lagging 0 / 3 / 25 frames, send the same events and log the same
      lines, the copy never written; the TICKCOST fields; SNAPSHOT `emptyRows`).
    - **Empty-row measure (2026-10-20; open decision (1) of the 0205 run, approved):** SNAPSHOT (debug, one per
      check) carries `emptyRows=<m>/<dead-end m>/<edges>` (`ot_knot.emptyRows` / `rowsText`): the town's own empty
      edges (`emptyOurs`: locked or built this session, no house) of at least `ROWS_RUN_M` 40 m running 40 m or more
      within the row distance `rowM` of another such edge (not one sharing a node), at most `PAR_DEG` 25 deg off; an
      edge at a dead end counts in the second figure too (the offline metric of the row rule's table below). Computed
      only when the debug line is written, at most `ROWS_EDGES_MAX` 400 edges (`+<n>` the rest), `SCAN_MAX`
      neighbours each (offline worst case 400 edges in a 30-lane comb: 6 ms); `rowsUs=` its time, `us=` stays the
      snapshot's own. "-" without house counts. Tests: test_row75 (+2), test_driver (+1).
    - **One empty row at a time** (`ot_knot` `ROW`, ot_select `ROW`, a fifth knot reason `row`): a steer organic
      town's piece that leaves a new dead end (an end at no town street and no piece chosen in the increment) waits
      while it runs beside one of the mod's own streets without a house (`emptyOurs`: locked, or built this session,
      ot_driver's snapshot now carries `own`; fewer than `ROW_HOUSED` 1 buildings; unknown house counts never count)
      or beside a piece chosen in the same increment, within `rowM` = `ROW_K` 1.2 x max(`ROW_DEPTH_MIN` 44 m = the
      lattice's least row spacing, block depth), at most `ROW_MAX` 80 m (EU organic 54 m, MED hill 52.8 m), for
      `rowNeed` = max(20, min(40 m, 0.6 x the piece)), at most `PAR_DEG` 25 deg off. Decisions: never gives way (as
      `parallel`: offline it did not stall towns, below); a piece closing a block (both ends at streets or chosen
      pieces) passes, so a connector or the far street tying a comb's ends lets the lanes come as a block ("closed
      blocks before combs" for free within one increment); exempt: grid growers (as `SIDE_GRID`), motif / ring /
      crescent / connector pieces, forced plans (ot_driver sets `rowHold = false` where it skips the lead cap), plans
      without house data. `knotHeld=<n>:<cross>/<parallel>/<loop>/<side>/<row>` on PLAN, the empty PLAN and STUCK
      lines (`ot_knot.text`).
    - **Offline effect** (6 seeds x 10 increments of 12 edges, steer limits, the round test core, F.markBuilt houses
      after each increment, +15 / +40 / +80 lots per increment; "empty rows" = our unhoused edges running >= 40 m
      within 1.2 x max(44, depth) of another, in brackets the dead-end ones; before -> after):

      | houses / inc | style | street km | empty km | empty rows km (dead-end) | empty plans | `row` holds |
      |---|---|---|---|---|---|---|
      | +15 | EU organic | 13.3 -> 11.7 | 9.5 -> 7.9 | 1.54 (0.69) -> 0.31 (0.00) | 8 -> 8 | 70 |
      | +15 | EU extension | 13.3 -> 13.4 | 8.6 -> 8.5 | 1.68 (0.74) -> 1.11 (0.42) | 20 -> 18 | 21 |
      | +15 | MED hill | 12.9 -> 13.0 | 9.0 -> 8.9 | 1.28 (0.50) -> 0.22 (0.10) | 5 -> 6 | 48 |
      | +40 | EU organic | 21.6 -> 20.4 | 2.3 -> 1.9 | 0.15 (0.08) -> 0.00 | 2 -> 1 | 49 |
      | +40 | EU extension | 25.2 -> 24.7 | 2.8 -> 2.7 | 0.72 (0.00) -> 0.64 (0.00) | 2 -> 0 | 20 |
      | +40 | MED hill | 18.4 -> 19.2 | 1.9 -> 1.5 | 0.24 (0.00) -> 0.00 | 0 -> 0 | 32 |
      | +80 | all three | 79.4 -> 77.9 | 1.9 -> 2.0 | 0 -> 0 | 3 -> 3 | 47 |

      The driver against the fake growing town (test_demand, EU organic, 5 seeds each): independent model builds 105 ->
      108, mod edges 1076 -> 983 (share 71 -> 69 %), houses on mod streets 2547 -> 2452 of 5025, max own open lots
      (sum) 1528 -> 1315; frontage model builds 67 -> 81, mod edges 404 -> 497 (29 -> 34 %); the fast grower's
      pooled share 0.40 -> 0.45 became 0.38 -> 0.43 (test margin + 0.05 -> + 0.04, comment there), scarce checks
      0.19 -> 0.22 became 0.18 -> 0.20. No stall: empty plans flat or down, builds up. The EU extension's remaining
      empty rows (0.42 km dead-end at +15) are the model's (F.markBuilt re-ranks every lot by network distance after
      each increment, so a street housed when its neighbour was laid can lose its houses) or block-closing pieces.
    - Tests: test_row75 (5: limits; shot 5 held beside our empty lane (locked or own), passing beside a housed lane or
      a game street; a block-closing lane passes; grid / forced / no house data / ROW off exempt; one increment's comb
      comes one row at a time, all of it as a closed block with the far street; the snapshot's `own`), test_forced /
      test_side75 (the fifth count), test_demand (fast grower margin).
    - **In game (run 2026-10-20, session `2026-10-20_0205_sqot`, seed `a`, Quick 40, same map as 1949; TESTING.md
      "Side streets and parallel streets" run 2026-10-20):** the row rule held 53 pieces in 44 plans (9 of 16 towns),
      never stalled a town (0 STUCK vs 3; the longest empty run with a `row` hold 3 plans, always beside wedge / env /
      lead holds); buildings 9340 vs 8915, plans with edges 194 vs 172. Its gain is not visible at the town level: mod
      street 106.2 vs 95.9 km, the mod's own empty street (`ownEmpty`) 16.6 vs 14.1 km (within the run-to-run spread;
      the logs held no empty-row measure: SNAPSHOT `emptyRows` since 2026-10-20). `geoSide=0` on every plan; 47 joins, all built; PLAN `us=` +5-10 %.
      Provenance: one PROV line per built edge (994 of 994), but `src` read `plain/<key>` for every plan piece and
      near-miss join: `ot_proposal.build` dropped the plan edge's `origin` / `nearMiss*` fields. **Fixed 2026-10-20**
      (the spec edge carries them; test_prov +1 through the proposal). Not seen yet: `who()` from the console, the
      record after a reload (`2026-10-20_0001_sqot-sqrl` ran the code from before ot_prov).
    - **Status (2026-10-20):** provenance built, `src` fixed, the console lookup unverified; row rule kept (no give-way
      needed: it stalled nothing); the state read off the frame path and the empty-row measure built (above; in game
      next run). Open decisions: (1) done (SNAPSHOT `emptyRows`); (2) rebuilding `own` from the saved record on load (small: 898 of 994 built edges are locked
      and count as ours without it; the 96 unlocked, plan pieces and 17 lead lanes the steer policy left open, drop out of `emptyOurs` after a reload); (3) shot 4's triangle
      fixes (b) / (c) wait for a `who()` on a real triangle; (4) the record's size: `PV_MAX` 12000 chars x up to
      `PV_TOWNS` 1000 towns can reach megabytes on a big map in a long game (this run: ~55 KB for 16 towns over 40
      years); a lower town cap or a total cap is cheap (done 2026-10-20: "Provenance record: bounded").
  - Also open from this run: a close look at a corner (`c`) join in game; the forest keep and the fixed per-pair chance
    unchanged (`chance` 133 kept).
  - **Far-out streets after an extent jump (investigated 2026-10-20 from the logs; frame tip cap and log fields built
    2026-10-20, below; the main-body decision pending the next run's numbers):**
    Wheatden (1949: CHECK `r` 478 -> 1070 m at 452 -> 495 buildings, simulated years 28-32, the mod sending nothing for
    it then; game edges 34 -> 59) and Seachurch Cove (0205: `r` 682 -> 998 m at 424 -> 481, game edges 27 -> 53,
    `foreignLen=0`). **Not a Works / satellite / other-town mix-up:** `r` is the 90 % quantile of the distances of the
    town's own houses (the game's town-to-building map, keyed by town id: an offshoot's houses never count; `A.extent`,
    ot_assess `EXTENT_QUANTILE` 0.9) from their mean; the game's own growth put an outlying group of the town's houses
    0.7-1.2 km out, and once it held over 10 % of them the quantile jumped from the main body's edge to that group.
    Wheatden Foundry came after the jump (`WORKS event=create ... d=1500 ... simYear=32`, its site pushed out by the
    inflated r + `GAP_EXTENT`; its link `outcome=none why=crossing`: no access road). **Which jobs:** plain plan pieces
    (`sr` / `rg` / `conn`, every PLAN `@far=` <= 190 m: each within the lead limit of a street carrying the town's far
    houses, joining dead ends the game built in the simulated years) and frames (Merehythe 925-1003 m, Dovemouth
    935-996 m out, env 749 / 284 m: `ot_wedge.frameStreets` has a floor (0.6 x coreR) and the 250 m housed-street test
    but no outer limit). Verdict: the measure is fragile (one radius from the mean for a body plus an outlying group)
    and the mod then treats the outlying houses as the town's front: a design gap, not misattribution. The empty-street
    / dead-end jumps of the tour are partly the dev ALLTOWN circle (r + 300) growing with r. Also scaled by the
    inflated r: Works sites, the industry reach (r + 900), the snapshot and the lot set. **Proposals (decision open):**
    (1) a main-body extent: houses on ~100 m cells flood-filled from the town's cell across gaps up to ~200 m, `r` from
    that body (pro: one fix for all the users of r; con: a gappy ribbon, a lead hamlet or a bridgehead cut off unless
    groups joined by the mod's own streets stay in the body); (2) an outer cap on frame tips (~1.3 x env, or the
    sector outline): cheap; (3) the lead / housed-street tests on the main body only (outlying groups left to the game);
    (4) fallback: a growth cap on r per CHECK (x 1.25; lags real growth). Log fields to confirm first: CHECK
    `rBody=` / `r50=` / `out=<n>@<m>/<heading>` and the template under the outlying houses (country road or town
    street), PROV `d=` from the town, FRAME `maxTipR=`.
    - **Built 2026-10-20 (proposal (2) as a frame tip cap, plus the log fields; in game next run):**
      - **Frame tip cap** (`ot_wedge.tipCap`, `TIP_CAP`, `TIP_LEAD_M` 300; ot_core.frameIncrement, wedge and meadow
        frames): a tip farther from the frame centre than **the main body's reach + 300 m** is dropped before linking
        (the main body: `ot_assess.body` over the snapshot's housed streets, midpoints weighted by `e.built`; its reach
        the farthest body house from the centre; at most `TIP_EDGES_MAX` 4000 edges). Base decided against the two
        proposed: a multiple of a radius cannot separate the cases, because the game's tips legitimately run up to
        `LEAD_M` 250 m ahead of the houses. Offline (test_bigform growth 1x -> 10x, 13 armed towns over EU organic /
        extension, MED hill, Nordic + 4 meadow twins; 272 frame calls, 145 frames) the farthest tip of a call reached
        up to 2.2 x env, median 1.7 / max 2.5 x the 75 % house radius (from the frame centre), median 1.4 / max 2.1 x
        the 90 %; so ~1.3 x env cuts normal frames (env is an effective distance, low in the wedges where frame tips
        live; Dovemouth's in-game frame, by the earlier reading 935-996 m out, ran ~3.3 x its env 284 m beside
        fingers arms housed to 835 m (`armBuilt`): likely a legitimate arm-end frame), q75 x 1.6 cut 56 of 272 calls
        (151 tips), q90 x 1.3 62 calls (186 tips), and a cap loose enough for all of them (q75 x 2.5) sat inside or
        past the synthetic outlying group below, letting part or all of it through. The body's reach + `LEAD_M` + 50 m lies beyond
        every tip a one-body town can have (a tip needs a housed street within `LEAD_M`), so it is a no-op there by
        construction, and cuts only tips past the body, i.e. at an outlying group (gap over 200 m).
      - **Offline before / after** (cap off vs on, same graphs; `make test` scratch runs, not kept):

        | towns | frame calls | frames | frame edges off -> on | tips cut | least margin cap - farthest tip |
        |---|---|---|---|---|---|
        | test_bigform armed: EU organic linear x3 / fingers x3 / cross x3, EU extension linear / fingers, MED hill linear, Nordic linear | 208 | 116 | 671 -> 671 | 0 | 56 m (MED hill) |
        | test_bigform meadow (sprawling twins x4) | 64 | 29 | 107 -> 107 | 0 | 177 m |
        | test_spread sites x 6 towns, to 10x (28 with frames): flat, flat + roads (cross), coast (shore x3, linear, fingers), valley (linear x6), hillside MED (linear x6) | 168 | 144 | 1088 -> 1088 | 0 | 96 m |
        | + an outlying comb (12-20 % of the houses, 350 m past the farthest house, mid-wedge; 6 towns x steps 6 / 10 / 14 x 2 shares) | 36 | 36 | its 2-8 frame edges -> 0 | 5 (all the comb's) in every case | - |

        Growth metrics (elong / arms / wedge share / housed at 5x, 10x) identical with the cap on. A twin or bridgehead
        across a gap over 200 m with fewer houses than the main part would lose its far tips: none offline; CHECK
        `out=` in game says whether such towns exist.
      - **FRAME** plan / none lines: `tipCap=<m>` ("-" without house data), `tipCut=<n>[@<m> the farthest cut]`,
        `maxTipR=<m>` (the farthest tip kept, from the frame centre), `bodyOut=<houses outside the body>`.
      - **CHECK** (debug; computed only when the line is written; logging only): `rBody=` (the main body's 90 % radius
        from its own mean, as `r`), `r50=` (median radius of all houses), `out=<houses outside the body>/<other groups>`,
        `outFar=<houses>@<m>/<deg>` (the largest other group: houses, distance of its mean from the body's mean,
        heading 0 = +x counter-clockwise), `bodyUs=`. The body: houses on `BODY_CELL_M` 100 m cells flood-filled across
        gaps up to `BODY_GAP_M` 200 m (cells within 2 of an occupied cell join), the group with the most houses (not
        the group at the town centre: a ring / crescent / twin town's mean can sit in an empty cell; the outlying groups
        seen held 10-20 %), at most `BODY_PTS_MAX` 4000 points, one visit per cell.
      - **PROV**: `d=<m>` the edge middle's distance from the town centre (the style's, as plans and frames use).
      - Tests: test_far75 (5: body with an outlying group / gappy ribbon / largest group / weights / caps; the cap cuts an
        outlying comb's tips and keeps the town's frame; normal towns cap on = off over growth), test_prov (`d=`),
        test_driver (CHECK fields).
      - **Decisions left (after the next run's numbers):** (a) the main body for `r` itself (proposal (1): every user
        of `r`: Works sites, industry reach, snapshot, lot set, plain pieces' lead) or (3) the lead / housed-street
        tests on the body only (the plain `sr` / `rg` / `conn` pieces of 1949 / 0205 are not capped by this change);
        read CHECK `rBody` / `out` / `outFar` against `r` on the jumping towns and PROV `d=` of far builds; (b) whether
        `TIP_LEAD_M` 300 holds in game (FRAME `maxTipR` vs `tipCap`; `tipCut` on towns with `out=0` would mean a
        tip beyond the houses' lead, not expected).

### 6.3 Town shapes (2026-10-11, offline; `ot_shape`)

The user's main wish: "more interesting town shapes, not just radiating from the center: long and skinny, wide,
spidery". A shape archetype per town steers where increments go (the selector's cost), independent of the street
style (which decides what the streets look like).

**Real-world basis.** Urban morphology classifies town outlines by site and roads (Conzen's town-plan analysis;
the German village forms Strassendorf, Angerdorf, Haufendorf; ribbon development along roads; the finger plans
of post-war planning):

| Shape | Real pattern | Steering (`SH.distance`, effective distance from the centre) |
|---|---|---|
| compact | Haufendorf / nucleated town around its core | plain distance (the old behaviour) |
| linear | street village, ribbon along a road, valley or coastal strip | two arms along the axis: ellipse reach 2.0, half width 0.55, core circle x 1.7 |
| cross | crossroads town: 3-4 corridors along the roads meeting in it | 3-4 arms (reach 2.0, width 0.4), core x 1.9 |
| fingers | finger / spider plan: corridors along radial roads, green wedges between | 4-6 arms (width 0.32), core of 1.5 blocks, wedges beyond it x 1.5 |
| fan | coast, river bank or cliff: a half-circle opening away from the barrier | ellipse wide across (1.25), forward 0.95, behind 0.25 |
| twin | two cores growing together: old town + station quarter, twin villages, a satellite toward a neighbour | second core 500-900 m out (0.45 x the distance to a neighbour), link corridor, old core x 1.6 |
| lens | Angerdorf: an oval around a green | ellipse 1.35 / 0.75, the green (0.9 x 0.45 blocks) + 3 blocks |
| ridge | hill towns along a crest (Italy, southern France) | as linear (1.8 / 0.6), x (1 + metres below the centre / 40) |

The cost uses that distance instead of the plain one; a shaped town keeps 40 % of the seeded sector preference
(`SH.SECTOR_DAMP`) and no seeded hotspots (the shape is the outline); main-street ribbons stay. A fresh plan (axis
from the seed) turns its axis to the shape's, so spokes / lines run along the corridors (strict grids keep their
survey axis; their arms snap to it); seeded cross / fingers arms of the organic growers sit on master-plan spokes
(arms off the spokes grew unevenly: only arms on a spoke get its main-street ribbon).

**Selection** (`SH.candidates` / `SH.pick`, weighted draw from the town seed). Site (x 12, `ot_terrain.dirRelief`:
heights on 16 rays at 0.25 / 0.5 / 0.75 of 600 m give the most level axis and its two sides): valley -> linear
along it; crest -> ridge; coast within 500 m -> fan opening inland or a strip along the shore (Nordic prefers the
strip); river -> along the banks (twin x 0.3); hillside -> along the contour or a fan downhill. Context (x 7):
country roads (non-town templates) crossing the building extent (`SH.exits`: 2 opposite -> linear, 3-4 -> cross
with arms along them, 5+ -> fingers), the nearest town (under 1.8 km -> twin toward it; under 4 km -> linear toward
it), a station 250-1200 m out (linear toward it). Style weights on flat land: EU organic compact 3 / twin 1.5 /
linear 1.5 / lens 1 / cross 0.5; EU extension compact 2 / cross 1.5 / fingers, linear, twin 1 / lens 0.5; NA grid
cross 2 / linear 2 / compact 1.5 / fan 0.5; NA suburb fingers 2 / compact 1.5 / fan, linear 1; MED hill compact 2 /
ridge 2 / lens 0.5; MED ensanche compact 3 / cross 1; JP dense linear 2 / compact 2 / cross 1; Nordic linear 3 /
fan 1.5 / compact 1; Superblock compact 2 / cross 1.5 / linear 1. Forced (dev `startJob{ shape }`) and saved shapes
win: the frame saved at a town's first build now carries the shape index and axis (`ot_saved` frames `s`, `sa`;
older frames load without). The STYLE line logs `shape= shapeWhy= shapeGeom= exits= neighbour=`, PLAN lines
`shape=`.

**Metrics** (`ot_metrics`, new): `arms` (prominent peaks of the 24-sector 90th-percentile radius, each 25 % above
the lowest sector toward its neighbour), `side` (largest share of street length on one side of a line through the
centre), `waist` (thinnest length density along the principal axis between the densest tenths of both ends, over
the weaker one; low = two lobes). Mean of 4 towns, flat land (test_shapes; EU styles: 14 increments from a vanilla
core with dead-end joins as in game; NA grid: 14 increments from an empty town joining anywhere, because its 200 m
blocks hardly grow from the 90 m test core):

| Shape | EU extension elong / arms / side / drift | EU organic elong / arms / side / drift | NA grid elong / arms / side / waist |
|---|---|---|---|
| compact | 1.36 / 1.8 / 0.59 / 0.20 | 1.62 / 2.0 / 0.56 / 0.12 | 1.28 / 2.5 / 0.53 / 0.99 |
| linear | 2.56 / 1.8 / 0.61 / 0.31 | 2.79 / 2.0 / 0.61 / 0.29 | 4.90 / 2.2 / 0.53 / 1.00 |
| cross | 1.53 / 2.8 / 0.67 / 0.23 | 1.61 / 2.8 / 0.71 / 0.27 | 1.15 / 4.0 / 0.55 / 0.85 |
| fingers | 1.31 / 3.0 / 0.64 / 0.31 | 1.35 / 3.8 / 0.59 / 0.16 | 1.27 / 4.0 / 0.58 / 0.99 |
| fan | 1.93 / 1.8 / 0.77 / 0.49 | 1.75 / 1.2 / 0.78 / 0.45 | 1.96 / 2.5 / 0.73 / 0.99 |
| twin | 1.39 / 1.2 / 0.72 / 0.53 | 1.64 / 1.0 / 0.77 / 0.66 | 2.38 / 2.0 / 0.75 / 0.58 |
| lens | 1.62 / 2.0 / 0.58 / 0.16 | 1.80 / 2.0 / 0.55 / 0.06 | 2.19 / 2.0 / 0.52 / 1.00 |
| ridge | 2.34 / 2.0 / 0.58 / 0.19 | 2.30 / 1.8 / 0.62 / 0.28 | 3.94 / 2.0 / 0.52 / 1.00 |

(EU styles have 6 spokes: a cross is a Y of 3 arms, fingers one per spoke.) Tests assert per shape against
compact (linear / ridge longer, cross / fingers more arms, fan one-sided, twin leaning toward its second core,
lens an oval), the selection (valley, crest, coast, river, roads, neighbour, seeded variety, forced / saved) and
the distance field. Previews: `uv run tools/ot_preview.py --shape all --style … --terrain flat` writes
`svg/shapes/<style>_<shape>_<terrain>.svg` (grown from a vanilla core, dead-end joins; core grey, the twin's
second core a blue circle); `--core` does the same for the seeded shape (`*_core.svg`: hillside / river / coast
show the site-driven picks); every header shows the shape, its reason and the zig-zag / lasso counts. Looked at:
the eight shapes read distinctly in EU extension, EU organic and NA grid; twin is a lobe toward the second core
more than two separate towns (the old core keeps growing); lens shows as an oval (its green sits where the
vanilla core already is).

Open: whether the shapes survive the game's own growth (vanilla streets fill the wedges / lens green), twin's
look in game, valley / ridge detection on real maps (offline only on synthetic terrain), the planning time.

**Stronger shapes (2026-10-12):** the geometry above was strengthened after the v3 shape row read round at 1000 m
(linear ka 2.5 / kb 0.42, ridge 2.3 / 0.48, cross 2.4 / 0.36, fingers wedge 2.4, fan back 0.15, lens 1.45),
arm leads, main-only ribbons, the growth front and the corner rule: 6.2 "Site styles, hierarchy, stronger shapes"
(new metrics table there).

**Shapes round (2026-10-12, SHAPES_BRIEF; in game: TESTING.md "Showcase v5", NEXT_PHASE_BRIEF 12).** Showcase v4's
shape row read as round blobs from above. Causes, measured (whole town = game core + ours, offline from a round
vanilla-like core `F.roundCore` as in game: ~70 edges, 14 dead ends; 10 increments of 18 edges, EU extension 2020
as the showcase; a house proxy `F.houses`: lots every 25 m, filled in network distance from the core, 180 + 45 x
step houses):

1. *The snapshot cut (the main cause in game).* The driver's street graph held only edges within the building
   extent + 300 m. Houses stay near the core, so arm streets beyond ~600 m were invisible: never reached or joined.
   `F.snapshotCut` reproduces v4 (linear 2.1 instead of 5.6). Fix: `ot_driver.townNetwork` follows the town's
   connected town streets beyond the circle node by node (true node degree, `E.edge`), up to `NET_RADIUS` 2500 m /
   `NET_MAX` 1200 edges; a street whose far node is closer to another town ends the walk. SNAPSHOT `net=`.
2. *Fill all round the core.* The growth front is a quantile of the effective distance, which a round core widens.
   New **shape envelope** (`ot_select.envelopeCap`): no piece beyond the level whose region holds `ENV_AREA` (1.3) x
   the area of a round town with the same street length (area = length x block / 2) + 0.5 block; the level per
   metre is measured once per town by a grid count of `SH.distance` (`shape._envK`). Area-preserving: the shape
   spreads the town's area along its arms, a spur can't stretch it. When it would starve an increment (< 60 % of
   the edges) the selector widens it x 1.2 up to 8 times (`ENV_RELAX`), and `ot_core` replans a still under-filled
   increment with it x 1.2^2k (`ENV_RETRY` 3; PLAN report `envScale`). Compact towns have none.
3. *Bare spines.* With the envelope, cross / fingers grew 1.2 km main-street spines with sparse combs. **Arm fronts**
   (`ot_select.armFronts`, organic growers only): a piece in an arm corridor (`SH.armAt`) reaches at most
   `ARM_REACH` 2 blocks beyond the arm's outermost junction (3+ streets), so arms grow as ribbons. (Grids: off; their
   cross pieces are pruned until they close a block, so the front never moved and NA grid stalled.)
4. *Cross read as a Y.* EU styles have 6 spokes; a cross took 3. Now an X of two straight lines (4 arms at 60 / 120
   deg, `SH.CROSS_X`). Twin geometry unchanged (stronger core weights made one lobe, not two).

Before -> after, mean of 4 towns, streets `elong / arms / side / waist / drift`, houses `elong / side` ("before" =
the old snapshot cut + old selection, which matches v4's look):

| Shape | 10 steps before | 10 steps after | houses before -> after | 20 steps before | 20 steps after | houses 20 |
|---|---|---|---|---|---|---|
| compact | 1.31 / 2.2 / 0.58 / 0.96 / 0.15 | 1.36 / 2.8 / 0.58 / 0.90 / 0.14 | 1.15 / 0.57 -> 1.15 / 0.57 | 1.35 / 1.5 | 1.45 / 2.2 | 1.37 -> 1.32 |
| linear | 2.11 / 2.0 / 0.57 / 0.93 / 0.14 | 5.73 / 2.0 / 0.54 / 1.00 / 0.07 | 1.13 / 0.55 -> 1.83 / 0.56 | 1.96 | 5.43 | 1.44 -> 2.08 |
| cross | 1.22 / 3.0 / 0.62 / 1.00 / 0.09 | 1.85 / 3.5 / 0.63 / 0.96 / 0.34 | 1.07 -> 1.39 | arms 3.0 | arms 3.5 | 1.14 -> 1.50 |
| fingers | 1.10 / 5.5 / 0.55 / 1.00 / 0.06 | 1.29 / 5.0 / 0.58 / 1.00 / 0.15 | 1.11 -> 1.17 | arms 5.8 | arms 5.5 | 1.11 -> 1.16 |
| fan | 1.44 / 1.5 / 0.77 / 1.00 / 0.49 | 1.78 / 1.8 / 0.80 / 1.00 / 0.47 | side 0.62 -> 0.65 | side 0.80 | side 0.83 | side 0.73 -> 0.76 |
| twin | 1.15 / 1.0 / 0.72 / 0.91 / 0.49 | 1.56 / 1.5 / 0.82 / 0.75 / 0.75 | side 0.57 -> 0.64 | drift 0.46 | drift 0.74 | side 0.62 -> 0.69 |
| lens | 1.42 / 1.8 / 0.57 / 0.99 / 0.10 | 2.12 / 2.0 / 0.58 / 1.00 / 0.16 | 1.10 -> 1.12 | 1.53 | 1.95 | 1.09 -> 1.66 |
| ridge | 1.89 / 1.8 / 0.58 / 1.00 / 0.18 | 4.91 / 2.0 / 0.54 / 1.00 / 0.07 | 1.11 -> 1.62 | 1.82 | 4.46 | 1.50 -> 1.72 |

All grow 242-246 edges at 10 steps (the old 246). Zig-zags / lassos 0 in the previews (`uv run tools/ot_preview.py -n
10 --style EU_EXTENSION --terrain flat --shape all --round --max-edges 18 --run-year 2020 --town 7` ->
`svg/shapes/*_round.svg`). The streets read; the houses only partly: the game core holds ~60 % of the houses after
10 steps (in v4 the linear town had 231 of 648 buildings on our streets), so from above a 600-building town keeps a
round centre with arms; the long shapes show (linear / ridge houses 1.6-1.8, 2.1 at 20 steps). Twin is a lobe toward
its second core, not two separate towns. Tests: `test_envelope.lua` (goals per shape, the cut reproduced, envelope
respected, X arms, `MT.points`), test_driver (network walk, SHAPE line, lock).

*Log*: `SHAPE town= shape= axis= net= env= envScale= streets=elong/arms/side/waist houses=… buildings= inc=armNN/outNN
edges=` per planned increment of a shaped town (houses from the town's building positions, `ot_metrics.points`;
`inc` = share of the increment's new length in the arm corridors / beyond the envelope).

*Locking streets (probe, user 2026-10-12).* `BaseEdge.roadDevelopmentLocked` ("prevent towns from updating or
extending this road") can be set on our own NEW edges in the proposal (no rebuild; existing streets can't be locked
without removing them, HANDOFF D4). Dev lock probe: `startJob{ lock = true }` sends every new edge locked (spec
`locked`, BUILT `locked=`); Showcase v5 has locked twins of the linear and fingers towns (SHOWCASE LOCK lines: alive,
read-back locked, houses on them, `attached` = vanilla streets at our nodes). Open: houses along locked streets,
whether the town still attaches side streets, whether the flag survives edge splits. **Design if it works (user
idea 2026-10-12):** locking follows the site, not only the showcase envelope: in valley / ridge / coast towns lock
our streets on the valley sides and slope edges (edges whose outer side faces ground steeper than the town
templates' build slope, or water / a cliff within a block), so the game does not branch side streets up the slopes
or across the valley and the town stays a winding ribbon; shaped towns could lock the envelope-edge streets of the
wedges. A per-town record of locked edges (saved with the frame) lets the mod unlock them later (a proposal that
re-adds the edge unlocked would demolish its houses, so unlocking must be tested first, or done only on edges
without houses) when the town should grow that way (envelope reached, a new road built). Blank Slate is flat: the
valley / ridge case needs a terrain map test.

**Deep arms (2026-10-12, Showcase v5: arms read as ladders / fishbones; in game: TESTING.md "Showcase v6").** Arms now
grow as strips: the spine plus back streets parallel to it, joined into blocks. The organic master plan gives every
spoke an arm sits on up to two back rows per side (offsets of the spoke at 1 and 2 x block depth, from ring 2, where
the cell is wide enough; secondary radials there are dropped), with lanes about 0.85 block lengths apart, lined up
across the rows (`ot_grow_organic` `DEEP_ARMS`, pieces carry `armLine` / `armPiece`). Arms sit exactly on spokes
(`SH.spokeHeadings`; a seeded axis snaps to a spoke, `SPOKE_SNAP`). Organic arm corridors are at least 2 blocks wide
each side (`STRIP_BAND`; this widens `SH.inArm`, so the driver's lock / dose and the SHAPE line's `inc=arm` cover the
whole strip). Inside them the selector uses `SH.stripDistance` (along the arm + 0.35 across, + 1.5 beyond 1.25
depths, so the second row comes later), and the whole strip shares the spine's ribbon. As the game joins only dead
ends, a corner or a street through an arm line's junction stopped that line for good (the U-combs): at an arm-line
junction with 2+ streets the line's pieces on both sides are chosen with the piece (`ARM_TIPS`, `ARM_LANE_TS`: lanes
meet rows in T's). From their own tips, rows and spine extend only with lanes (lead cap 0, `SPINE_TIPS`); arm pieces
are exempt from the lasso guard (`ARM_LOOPS`); arm fronts reach one piece further. New metric `MT.ladder` (rungs,
depth in rows, closed blocks), test `test_arms.lua`. Round core, EU extension 2020, 10 steps: blocks in arms linear
21 -> 41, ridge 19 -> 37, cross 16 -> 38, fingers 12 -> 34; depth 1.4-2.6 -> 1.8-2.3 (2.0-2.9 at 20 steps); rungs
0.03-0.08 -> 0.00 (the old arms were mostly one-block U-combs, so depth / blocks show the change better); linear
elong 4.65 -> 7.30 (the old version stalled at 20 steps), houses proxy 1.69 -> 1.93 (2.49 at 20); cross keeps 4
arms; NA grid byte-identical; zig-zags 0, lassos not more. Planning time per increment ~1.5x mean (21-28 ms), worst
~2x (240 ms, cross; sliced over ticks). *Young towns:* a small core with two dead ends and no plan junction within
reach of them planned nothing (also before deep arms: 4-10 of 30 EU towns, ~20 of 30 MED hill): an empty selection
now retries once with longer / sharper connectors (`CONN_RELAX_*`), and an increment still empty after every round
plans once with straight connectors from the dead ends (`ot_core`, report `connRelax`); offline 0 of 30 empty for
the EU cases, MED hill 2 of 30. Open in game: several new edges at one existing dead end (row tip T's), refused row
pieces leaving bare lanes, arms off spokes (road exits, terrain) get only the strip cost, saved seeded towns get no
back rows, planning time, MED hill on tiny grid cores.

**Houses onto the arms (2026-10-12, NEXT_PHASE_BRIEF 13; in game: TESTING.md "Showcase v6").** Showcase v5: the
streets read (linear elong 3.35) but houses stayed a round blob on the game core (~25 % of our edges with parcels,
houses elong 1.07-1.48). Two levers in `ot_driver`, on by default for shaped towns (compact / unshaped: neither),
logged on the INIT line (`lock=shape fill=dose2 metropolis=off`):

- *Lock* (`D.LOCK_SHAPE`, `D.lockKeys`; since §65 2026-10-15 the "legacy" lock: new towns lock every mod street,
  6.2 "Lock every mod-built street, the stall guard"): new edges whose midpoint is in an arm corridor (`SH.inArm`) or beyond
  `LOCK_RIM` 0.75 x the envelope level go out `roadDevelopmentLocked` (`ot_proposal` `info.lockKeys`; BUILT
  `locked=`). v5's lock probe: flag sticks, houses still build, the town attaches 0-1 side streets instead of 33.
  Interior streets stay unlocked so the game can densify near the core. Removing the mod leaves them locked
  (description "Adding and removing" says so).
  (§63, 2026-10-15: the arm corridors themselves now come from `ot_skeleton`: headings bent off the woods, capped
  65 m short of dense forest (past `shape.armMax` no arm, so not locked as one), open arms longer; 6.2
  "Landscape-aware skeleton".)
- *Dosed fill* (`D.fillKind` / `D.fillPoints` / stage `fill`): after a build, `makeTownDevelopAtCmd(point, false,
  false)` at `FILL_POINTS` 2 points 20 m beside new arm / rim streets (spread inner -> outer, sides alternating),
  one command at a time; then `FILL restore`: DevelopAt resets the town's initial land use capacities to its
  current capacities (v5 log, findings towns.md: that is why the fill twin grew 12x), so the driver sets them back
  (`makeTownSetInitialLandUseCapacitiesCmd`) to at most `FILL_EXTRA` +15 % above the value before and never above
  `FILL_CAP` 1.3 x their sum at the town's first build (saved with the plan frame as `ic`, older frames load
  without; else the first value seen this session). A dose is skipped at that cap (`skip=cap`) and while a fill
  less than 5 min ago was followed by > 25 % more buildings (`skip=surge`). `FILL effect` at the town's next check
  logs buildings within 60 / 200 m of the points before -> now, buildings, capacity, initial capacities and size
  factors: where DevelopAt's growth goes, and whether the restore holds.
- *Metropolis* (mod setting `metropolis`, default Off, 13 languages): towns from `METRO_MIN_CAP` 4000 persons get
  v5's strong fill (12 points beside every new street of each build, no restore) up to `METRO_MAX_CAP` 50000:
  each fill multiplies the town's target by its size factor, the dense fast-growing look the user liked
  (`FILL kind=metro why=big`).
- startJob options for the dev tools: `lock` = true / "all" / "shape" / "off", `fill` = "dose" / "metro" / "off",
  `fillStreets` / `fillUpgrade` (DevelopAt's flags). Tests: test_driver (lock keys, fill kinds and points, the
  stage with one command in flight, the restore, FILL effect, metropolis param, INIT fields).

Expected (unverified): houses elong >= 2 for linear / ridge, >= 50 % of our edges with parcels, buildings within ~1.4x
of the plain twin. Open: whether DevelopAt builds at its point at all (if `near=` doesn't move, the dose is a +15 %
size bump and the lock does the work), whether the initial-capacity reset is immediate (the restore reads it right
after the callbacks), DevelopAt's two flags (probe twins).

#### Showcase v7 round (2026-10-12; NEXT_PHASE_BRIEF 14)

Showcase v6 (HISTORY.md): the deep arms ran 400-900 m past the built edge as empty ladder strips; style towns turned
linear toward their neighbours; the roundabout was two-way. Changes:

- **Arm reach** (`ot_shape`): `shape.reach` = 1 (strong) for linear / ridge / fingers picked from the site (terrain
  candidates carry `site = true`) and for forced shapes; else `MILD_REACH` 0.4: arm ka -> 1 + (ka - 1) x 0.4 in
  `SH.distance`, one block of arm front (`ot_select.armFronts`). `NEIGHBOUR_GAIN` 0.12 (was 0.6); style weights: JP
  dense linear 0.75, NA suburb 0.5, EU organic 1.
- **Arms fill first** (`ot_select.armBuiltFronts`, `ARM_FILL`): snapshot edges carry `built` (parcels with a building,
  `ot_engine.townBuildings`; `g.hasBuilt`); per arm the farthest housed edge midpoint along it (else the town's housed
  radius, 80 % quantile) + `ARM_FILL_LEAD` 2 blocks (mild 1.25, >= `ARM_FILL_MIN_M` 120 m) is the limit for any piece
  (its farthest point on the arm it reaches farthest along); deep arms' back streets / rungs `ARM_FILL_BACK` 0.5 block.
  No data (no housed street, tests, preview): not applied. `armGaps` / `armGapText` for the log.
- **Straight wide streets** (`ot_core.straightWide`, called from `hierarchy` on the kept wide pieces):
  `STRAIGHT_LIMITS` large { edge = 10, joint = 12 }, medium { 25, 30 } (deg; edge = angle between its end tangents,
  joint = between two wide edges of one piece or plan line through a node, <= 90 deg); over the large limits ->
  medium if it fits, else small; medium over -> small. `hier.bent`, `hier.maxDefl`, `hierText`.
- **One-way ring** (`ot_proposal.junctionConnsDir`): ring -> ring lane by lane, ring -> arm only the outermost ring lane
  into every arm exit lane, arm -> ring a fan (right entry lane -> outer ring lanes); dev `otd_runner.roundabout`
  tries one-way first, then the two-way ring (`RB FALLBACK`).
- **Metropolis** (`ot_metro`, new; `ot_driver.metroStyle`): decided per session from size, site features
  (`ot_site.features`), region, era and seed (nothing saved); applied to a copy of the town's style (large arterials,
  hierarchy late, variant shape / plan / outer zone, parks); the frame keeps the town's own style
  (`job.baseStyle`). Lock: `MET.lockKeys` (radial arterials, corridor off-band, polycentric between centres); fill
  "metro" on `MET.fillEdges`; polycentric restores with `POLY_EXTRA` / `POLY_CAP`. Setting "Metropolis growth"
  removed (`ot_params` no longer reads it).
- **Green gaps**: `ot_metrics.greenGaps` / `greenGapsSegs` / `greenText`; green reserves `ot_style.greenReserves`
  (`style.greens`; `ot_select.inGreen`, pieces `excluded = "green"`), off in the other tests (fixtures) and covered in
  test_metro.
- Tests: `test_reach.lua`, `test_metro.lua`, the one-way patterns in test_proposal / test_roundabout, the dev layout /
  showcase counts (35 towns).

#### Dev showcase speed (2026-10-12, after v7 started; applies from the next game start)

- **Concurrent town jobs** (`otd_runner.buildBatch` / `poolStep`): a round's style-town jobs run on a pool of driver
  instances (`R.BUILD_INFLIGHT` 12 at once) sharing the dev driver's `towns` / `counts` / `sched` / config, so each
  job keeps its own stages, callback and refusal handling (prune / halve / joint-rule replan / fill) and reports via
  its own onDone; CPU stages run within `R.TICK_BUDGET_US` 12 ms per tick (at least one), waiting jobs are checked
  every tick. Metropolis towns start first (12 DevelopAt one after another per build). Stop: no new jobs, the running
  ones finish; resume builds the round's towns without an outcome. Main mod untouched. ROUND line adds `build= grow=
  other= builds= inflight= peak=`. Tests: test_showcase "concurrent builds" (deferred out-of-order callbacks, equal
  per-town results vs one job at a time, refusal / build failure mid-batch, Stop mid-batch + resume, the RB step).
- **v6 round 9 (92 s)** (session `2026-10-12_1732_sqrl-sqsg`): the fill surge brake (`FILL_SURGE_S` 300 s) lapsed
  for most shaped towns at once (round 1's doses + ~317 s): 23 doses (2 DevelopAt + restore each, one by one) vs 1-2
  in rounds 2-8 -> build 53 s vs 18; the game's autosave froze 10.3 s inside it (one DevelopAt counted as a timeout);
  the doses' raised capacities doubled the two growth batches (26 + 13 s vs 13 + 6, engine). Round 10: the other 9
  doses. v7's metropolis row fills 12 points per build every round (no surge brake): ~5 s per metro town serially.
  Concurrency hides the fill chains; the growth-batch cost (engine) and the autosave stay.
- **v7 (session `2026-10-12_1900_sqot-dev`, 35 towns, avg round 74 s, 14.7 min):** build stage 32-64 s per round
  (the 5 metropolis towns ~5-6 s each = ~27 s, mostly their 12 DevelopAt one after another; logged CPU per round
  (CHECK + SNAPSHOT + PLAN + pre-check us) only 1.2-5 s, metro PLAN up to ~360 ms in 3 slices), growth batches 14-30 s
  + 6-15 s (engine, growing with the metro towns), rest ~1 s. Round 6: one growth batch hit the runner's 30 s
  timeout and its late callbacks could count for the next batch: batches now time out after `R.BATCH_TIMEOUT_S`
  120 s and carry an id (late callbacks log `LATE` and are ignored). Round 8: autosave 11.8 s (one metro DevelopAt
  `timeouts=1`, build `ms=` 848 average).

#### Showcase v8 round (2026-10-12; NEXT_PHASE_BRIEF 15; in game: TESTING.md "Showcase v8", "Real map test")

Showcase v7 (session `2026-10-12_1900_sqot-dev`, HISTORY.md): empty arms gone in the style towns (armGap <= 223 m),
but the forced linear / ridge towns grew round (elong 1.26 / 1.06), the five metropolis towns converged on one
organic blob (~90 % game-made edges), superblock read as an organic core with a few loops. Changes:

- **Strong arms hold their envelope** (`ot_select` `ARM_STRONG_HOLD`, `ARM_FILL_RELAX` 1.5 blocks; `ot_core`
  `ENV_WIDE_MIN` 3). Cause (log + offline repro with houses filled by network distance, `F.markBuilt`): when the arm fill
  rule held arm pieces back, the envelope relaxation (x 1.2 up to 8 times) spent the increment beside the core
  (`inc=out80..100`); the houses filled those nearer streets first, so the arm stretch never got housed and the gate
  never opened. Now for strong-reach shapes (reach >= 1) the relaxation widens the fill limit instead (0.5 block per
  step, at most 1.5 blocks); the envelope widens only while nothing at all is chosen, and an increment under 3 edges is
  planned once more with the envelope free (young cores whose dead ends sit at the rim). Offline (4 towns, 10 steps,
  houses 150 + 75 x step): linear streets / houses elong 1.21 -> 2.62 / 2.19, ridge -> 2.62 / 2.18, worst arm gap 91 m;
  `test_form.lua`.
- **Town forms** (`ot_form`, new): CHARACTER = the style's street pattern, FORM = how the town spreads: clustered
  (compact shape, 0.9 x blocks, front x 0.6, sector x 0.5, no meadows), radiating (cross, strong, ribbon x 1.6),
  sprawling (the style's mild shape, 1.3 x blocks, front x 1.6, sector x 1.5, +2 hotspots, >= 3 meadows), linear,
  wide (lens), fingers (strong). Pick: dev `startJob{ form }`, the saved frame (`f`, ot_saved; older frames: no form, so
  existing towns grow exactly as before), a site / roads / neighbour shape (`FM.FROM_SHAPE`: valley linear -> linear,
  coast fan -> wide, cross -> radiating ...), else a seeded draw from `FM.STYLE_WEIGHTS` x `FM.siteFactors` (open
  plains favour sprawling, rough / coast / valley clustered, a neighbour under 2 km halves sprawling). Applied in
  `ot_style.resolve` after the first shape pick (block scale first, then the form's shape via `SH.pick(inputs, p,
  formShape)` with reason `form:`, then the growth modifiers; meadows via `FM.greens`). The selector's front cap uses
  `style.form.front`. Logs STYLE `form= formWhy=`, SHAPE `form=`. Offline JP dense (2 towns): elong clustered 1.19,
  radiating 1.33, sprawling 1.48 (block 65 m), linear 1.95; 40 seeded JP towns: clustered 12 / radiating 15 /
  sprawling 8 / linear 5. Forms are off in the other offline tests (`F.withForms`), as the green reserves.
- **Metropolis keeps its layout** (`ot_metro` `LOCK_ALL`, `FILL_EXTRA` 0.25; `ot_driver` `METRO_MAX_EDGES` 36). Cause
  (v7 log): the unbraked metro fill reset the target to size factor x the town each build (radial 57658 vs 22136
  persons), 18 edges of ours housed a tenth of the growth, and the game built 86-205 edges per round of its own,
  branching off our unlocked streets too (findings towns.md "Showcase v7"). Now every new metropolis street is locked
  (the variant rules stay behind `LOCK_ALL = false`), increments are 36 edges, and the fill restores the initial
  capacities to at most +25 % per fill with no base cap (polycentric: its POLY_EXTRA / POLY_CAP). A radial metropolis
  with a radiating / fingers / linear form grows fingers on its spokes (8 arms, strong); a grid metropolis with a linear
  / wide form keeps that outline (`MET.apply` reads `style.form`). `MET.density` between-centre area fixed.
  Unverified: whether 36 locked edges per build plus the brake keep the game's own street share low (target own >= 35 %).
- **Lattice first** (`style.lattice`; SUPERBLOCK late `{ lead = 0.5, depth = 8, discount = 0.6 }`, NA_GRID late
  `{ lead = 1, depth = 6, discount = 0.7 }`): on a plan anchored to the town's streets (a game-made core or a saved
  frame) the main / medium cell lines may lead `lead` x block beyond the junction front (instead of the late
  hierarchy's 1.25 fine blocks, 109 m for superblock), up to `depth` new pieces, at `discount` x cost. Cause (v7):
  superblock planned 6-12 edges per increment, 0 % large, only interior locals near the core. Offline from a round core
  (town 5, 10 steps): superblock wide share 30 -> 37 %, length 8.6 -> 14.7 km; NA grid 29 -> 35 %, 7.5 -> 11.1 km;
  previews show 350 x 250 m frames around the core (`svg/superblock_flat_core.svg`). A fresh plan in an empty town is
  unchanged (it grows as a regular grid anyway; with the lattice it made more stubs).
- **Fills faster** (`ot_driver` `FILL_CONCURRENT`, `FILL_SURGE_JITTER` 0.5): a build's DevelopAt calls go out back to
  back and the job waits for all callbacks (10 s timeout), the restore after all; normal play too (the engine runs
  queued commands in order; 2 calls for a dose, 12 for a metropolis). The surge window is `FILL_SURGE_S` x 0.75-1.25 by
  town id (`D.surgeWindowS`).
- **Metrics:** `ot_metrics.orientation` / `orientationSegs`: orth (length within 10 deg of the grid axes), radial,
  ring (within 15 deg of the direction to the centre / the tangent), `orientText`.
- **Dev:** rows (L.FORMS JP dense x 4; metropolis band 5 km at the bottom, 5 staggered slots ~3.6 km apart, forced
  forms; one density control, one probe twin, no Control B; the v7 rows stay as `L.DENSITY_V7` / `L.PROBES_V7` /
  `L.CONTROL_B` for the mechanics tests), TOWN `orient= own= dens= form=`, "Tour all towns" (runner `allTowns`, ALLTOWN
  lines, HUD tour source "all", 40 biggest towns).
- Not done: polycentric next steps (centres at arterial junctions, per-centre core style, a third centre); v7's
  secondary centre never filled (c1 0.2 / ha), likely too far for 10 steps; site-following locks on terrain.

#### Showcase v9 round (2026-10-12; NEXT_PHASE_BRIEF 16; in game: TESTING.md "Showcase v9")

Showcase v8 (HISTORY.md): fast (roundS 27.7), metropolis variants distinct in the shots (the user's favourite), but
linear read round at the end, polycentric laid ~3-4 km of empty arterials, NA grid looked organic early, Nordic had
nothing Nordic, the first two tour shots dropped. Changes:

- **Housed front** (`ot_select` `HOUSED`, `housedIndex` / `housedDist`, `style.housedLead`): no point of a new piece
  farther than housedLead x block (>= 120 m) from the midpoint of a housed street (snapshot `built`); an under-filled
  increment gets up to 1 block more (`HOUSED_RELAX`). No data (tests, preview, a fresh core): off. PLAN `housedHeld=`.
- **Empty budget** (`ot_core`, `style.emptyBudget`, polycentric 2000 m): maxEdges = (budget - unhoused length) / 70 m,
  at least 6. PLAN `emptyLen=` (ot_metrics.emptyLen) and `emptyCap=`. Offline polycentric (2 towns, 10 steps, houses
  150 + 75 x step): mean unhoused length per step 9567 -> 958 m, worst 14294 -> 2585 m (`test_v9.lua`). The secondary
  centre now fills only when the town's houses reach it (not within 10 showcase steps); seeding it as its own compact
  core was not done: DevelopAt builds little at its point (findings) and streets there would stand empty.
- **Metropolis mechanics for the grid styles** (`style.mech`, `ot_driver` `MECH`): what made the metropolis grid read
  as the American grid (shot 28: long straight locked frames, house rows along them, open block interiors, compact):
  NA grid, NA suburb, ensanche: lock every new street, 28 edges, dose the fill beside any new street (FILL `why=mech`);
  superblock: lock, 30 edges. A metropolis drops the style's copy (`MET.apply`: `mech`, `housedLead`, `emptyBudget`
  cleared; its own lock / 36 edges / metro fill unchanged). NA grid shape weights compact 3 / lens 1 / cross 0.75 /
  linear 0.75 (v8's NA grid drew linear toward its neighbour). PLAN `gridShare=` (ot_metrics.axisShare on the town
  axis). Offline from a round core (4 towns): steps 1-3 gridShare 0.89 (v8 settings 0.83), 27 edges at step 1.
- **Nordic** (`ot_style` NORDIC, `style.cluster`, `ot_grow_grid` cluster mode): research (RESEARCH.md "Nordic towns";
  Vallingby / Farsta, Oslo drabantbyer, Tapiola, Copenhagen Finger Plan, Stockholm green wedges): post-war
  Nordic suburbs are curving collector loops with houses in small clusters on short dead-end streets, green between
  the clusters, low density. The superblock subdivision (`sub` u = 3, v = 1) gives cells whose sides are the loops
  (rows bowed by a seeded sine of 0.12 x cell length, cross sides through a bowed midpoint, no junction jitter); the
  interior gets only cul-de-sacs (0.42 of the cell deep) from the rows, staggered (bottom row odd offsets, top row
  even); 30 % of the cells (never the 4 at the centre) none. Arterial every 3 cells, weights res 1 / 0.7 / 0.2 / 0,
  housedLead 1, 4 meadows (1 crescent). Offline plan (900 m): 101 of 292 pieces cul-de-sacs, 143 curved; 10 steps from
  a core: 246 edges, 63 dead ends. Preview `svg` not regenerated (scratch only).
- **Crescents** (`ot_crescent`, `style.crescents`, `ot_style.greenReserves` entry [4], `CRESCENT_R` 85-130 m): applied to
  the master plan in `ot_core.masterPlan` (with `SEL.GREEN`): pieces inside the circle (meadow + 10 m) dropped, crossing
  pieces cut at the circle (new junctions), arc pieces (small, smooth, 5 deg points with tangents) between neighbouring
  crossings except the widest gap and gaps over 150 deg. Reserves no longer overlap (v8: a crescent's arc could lie in
  another meadow). Offline EU organic (25 steps from empty): 2 of 2 crescents planned, 12 arc edges built. PLAN
  `crescents=made/planned`.
- **Kept / borrowed from what the user liked:** metropolis variants untouched but one park now a crescent; Control A
  (vanilla) for comparison: 626 buildings on 170 edges (3.7 per edge vs ~3.0 in the mod towns), dens 9.3 (mod towns
  10-12.5), houses elong 1.41 with waist 0.54 (an irregular two-lobed outline), orient 0.27 / 0.21 / 0.17 (no grid, no
  rings): fewer, longer streets carrying more houses; the housed front and the empty budget push the mod towns that
  way. Not done: single-loaded edge rows facing open land as a deliberate feature (the fingers town's left side); the
  form row's metrics (v8 missed them all) were not reworked this round.
- **Dev:** settle with the main mod's checks after each pass (`SC.SETTLE_MOD`, `showOpts.settleMod`); tour shots wait
  for steady frames, a warm-up and a gap (otd_hud `TOUR_WARMUP_US` / `STEADY_US` / `SHOT_GAP_US`); TOWN `emptyLen=
  modGrid= crescents=`; the preview draws the meadows.
- Tests: `test_v9.lua` (metrics, housed front, polycentric empty length, NA grid gridShare, Nordic plan, crescents,
  driver mech); test_shapes / test_shape / test_terrain_style updated (NA grid weights, Nordic cells and coast lean);
  dev test_showcase counts the settle builds.

#### Simulate natural growth (2026-10-12, dev mod; in game: TESTING.md "Real map test")

The base game grows a town only from transport experience (`growthPerTick = 0`; docs/findings/towns.md "Natural town
growth"), so a real-map test without a network shows no growth. Dev `otd_simgrow.lua` (runner `simStart` / `simStop` /
`simTick`, HUD top section) reproduces it: a seeded connectedness per town (exp per person per simulated year; 25 %
none, ~45 % slow, ~12 % fast, ~4 % metropolis candidates, optional size bias), experience along the game's level
curve, the game's target (Σ initial x F(levels gained)) and district split (`rebalance2` ported, the town's current
mix as usage weights since transport usage is 0), applied with `makeTownUpdateSizeCmd(town, sizeFactors, false)` in
quarter-year steps (1 simulated year per 10 / 30 / 60 real s while the game runs; faster paces below). It is not a task: the main
driver keeps running with its normal trigger (growth demand since 2026-10-12, below). Session state only (a new Start derives experience from the
current size). SIMGROW start / town / year / final / stop lines; optional Tour all towns when stopped. Tests:
`tests/square_organic_towns_dev/test_simgrow.lua`.

**Faster simulation (2026-10-12, after the first real map run `2026-10-12_2306_sqot-dev`).** That run (pace 30 s,
speed 4x, 16 towns) took 30 s per year: 52 size steps a year all applied, buildings +65-90 a year (2313 -> 4544 in
32 years / 16 min). The town developer kept slow towns at 92-100 % of their target capacity but fast ones at ~55 %
(Aldershot: ~3.6 capacity per real s at 4x), 84 % over the map; the main mod ran 320 checks, all `why=open`, no
build (its trigger: other work). So the pace was the limit, and at a few s per year the developer would be (no API
knob for its pace). Now: paces 1 / 2 / 5 s (one size command per town per year; experience still integrated in
quarter years, so the curve matches) besides 10 / 30 / 60; **Fast fill** every 1 / 2 / 4 years (the year's command
with `updateAllBuildings = true` for towns under 95 % of their target capacity, at their current size if it didn't
change; the year ends after those callbacks); **wait for the main mod** after a fill (until its driver has checked
the grown towns, by its scheduler's cooldown stamps, and has no job running; at most 15 s), with the main driver's
check pace raised for the run (`D.CHECK_S` 0.25 s, `ot_assess COOLDOWN_S` x 0.1, restored at Stop); game speed 8x
during the run (the previous speed back at Stop if still 8x). HUD: **Quick: 40 years** (1 s, fill every 4,
wait, 8x; expected ~3-5 min for 16 towns), check boxes Fast fill / Wait / Game speed 8x, Fill every picker; SIMGROW
year logs `s= cap= filled= fillS= waitS= main= mainChecks= mainBuilds= timeout=`. Trade-off: fills put a fill
period's houses in at once (less like natural pacing; the engine may add its own streets when a town has no room).

**Build round (2026-10-13, offline; in game: TESTING.md "Real map test").** The run `2026-10-13_0137_sqot-dev`
(Quick 40 years, every town grows, 16 towns, 358 s, buildings 2134 -> 12067, 0 fails) gave the main mod ~3 checks per
town in the whole run (75 CHECK, 63 SEND, 59 BUILT: 28 head start + 31 demand); 10 of 16 towns got no demand build
(North_Hykeham, Huntingdon, Minehead, Bolton: 3 checks, last `why=demand demand=78-108 fast=2-3`), mod share of new
street edges 16 % (21-53 % where it built). The compressed run outran the driver (one job at a time, ~3-4 s a build,
waits capped at 15 s for 6 towns; in normal play 40 years take hours, hundreds of checks per town). Also 3 towns
(Thornaby-on-Tees, Market_Drayton, Cheadle) stayed development-off to the end (`res=off`): the main mod's FILL
reactivate came once each, their later dose fills read `active=false->false`, so it never retried; the sim re-reads
`active` every step, so it never marked them stalled for good, but the game kept them off.
- Now the run goes in chunks of Fill every years; at a chunk's end (after the sizes' callbacks, before the fill) a
  **build round** (`otd_simgrow` startRound / roundTick, runner `simRoundStart` / `simRoundTick`): the main driver held
  (H.devBusy, after its running job ends, at most `ROUND_START_S` 10), every town that grew since the last round (most
  growth first) gets the main mod's normal job (force = false: its trigger decides) on the `simPool` drivers (separate
  from the showcase `pool`) that share the **main** driver's towns (demand ledger, own streets), sched, counts, config,
  prefix and engine, so the ledger / served / cooldowns move as in normal checks and the lines are `[SQOT] CHECK /
  PLAN / BUILT`. `ROUND_INFLIGHT` 12 at once (24 since 2026-10-14), one job per town, no two jobs in towns within
  `ROUND_NEAR_M` 2 km (since 2026-10-14 the plan-extent rule, "Speed-up and Build out" below); after
  a build the town is checked again until a check doesn't build or `ROUND_BUILDS` 6, no new job after `ROUND_MAX_S`
  20 (running ones finish), the sim's guard 90 s. `SIMGROW round` (towns, checks, builds, edges, served, capped,
  demandLeft, s, peak, why, per town builds/checks/last why/demand). Rounds also without Fast fill (every Fill every
  years); no wait after the fill in round mode. HUD check box "Build round" (default on; off: the old wait). Stop
  during a round: no new jobs, the running ones finish (Runner:tick drains), then the main driver is free.
- The sim switches development back on (`X.setDevelopmentActive`) for a town found off that was active at Start,
  after `STALL_STEPS` off steps, at most `REACTIVATE_MAX` 3 times (`SIMGROW reactivate`); `SIMGROW resume` when it
  gets steps again. (Main-mod side, not changed here: its FILL reactivate only fires when the fill found the town
  active, so a fill on an already-off town never retries.)
- Expected Quick: 40 s of years + 10 fills x ~12 s + 10 rounds x ~10-20 s (job ~1.5-3 s wall: check ~7 ms, plan ~44 ms
  median in slices, build callback ~0.3 s median) ~ 4-5 min, at most ~6; share >= 40 % in growing towns (up to 6 builds
  per town per round vs ~0-10 per town in the whole run before). Tests: test_simgrow "build round ...", "stall ...",
  "runner round ..." (fake main driver: served / capped / per-town tally / shared ledger, concurrency cap and the
  neighbour rule, time cap, hold and release, full run, Stop drain).

**Speed-up and Build out (2026-10-14, dev only; NEXT_PHASE_BRIEF 41; in game: TESTING.md "Simulate speed-up and Build
out").** Run `2026-10-14_0302_sqot-sqrl` load 2: Quick 40 years took 175 s (`SIMGROW stop s=175`): 30 quiet years x the
1 s pace, 10 fill years with `sizesS` 0.4-1.3 (7 s), `roundS` 0-9.4 (29 s) and `fillS` 3.9-20.7 (94 s). The long fills
(years 24 / 28 / 32: 14.7 / 20.7 / 16.4 s) were the ones where the main driver, free again after the round, sent its own
build (BUILT `ms=8717` / `16859` instead of ~300-800): its proposal queued with the 16 forced updates and the fill waited
for it. Alone a fill took 4-10 s, ~100 buildings per s (engine-bound). `WAIT_MAX_S` / `WAIT_FILL_S` never applied (round
mode) and no round waited on `ROUND_START_S`, so those stay.
- **Pace 0** (`SG.PACES` 0 / 1 / 2 / 5 / 10 / 30 / 60, "As fast as possible"): no minimum real time per year; the year
  waits for its size callbacks (no step finds a town busy) and steps only while the game runs. Same size targets as a
  paced run (test). Quick = pace 0, Fill every 4.
- **Main driver held through the fill** after a round (runner `simHolds`, H.devBusy right after the sim's tick).
- **Early fill:** during a fill year's round, a town whose round part ended (served / capped / cut; runner
  `simRoundReady`) and that no running job's town can reach is filled at once (`Sim:earlyFill`), still after the main
  mod's turn on that town; no job starts beside a filling neighbour (`simRoundFilling`). SIMGROW year `fillEarly=`;
  `fillS` counts from the first early fill.
- **More jobs, extent neighbour rule:** `ROUND_INFLIGHT` 24 (runner `R.POOL_MAX` 24; 0302 peaked at 12 every round).
  Two towns' jobs run side by side unless their centres are closer than rA + rB + 2 x `ROUND_REACH_M` 700 (r: the main
  driver's last `extR`, else 400 m): a plan stays within the extent + ~700 m (300 m snapshot margin, an increment's
  ~400 m, a satellite seed ~1 km from the centre). Two 300 m towns pair from 1.9 km, 150 m towns from 1.6 km; the gain
  is small on that map: the round's tail is one town's serial builds (Stratford-upon-Avon 5 builds, 9.4 s).
- **Fill every 1 / 2 / 4 / 8** (8: about twice as fast as 4, the main mod reacts half as often).
- Expected Quick, 16 towns: quiet years ~6-9 s + sizes ~7 s + rounds ~29 s + fills ~62 s alone, minus the overlap of
  early fills with the round tails (~10-15 s), plus the houses the developer no longer adds between fills (~5-8 s):
  **~95-110 s** (was 175).
- **Build out** (`SG.BUILDOUT`: 100 years in 10 chunks): a fresh run (no resume) from the towns' current size, every
  town grows, pace 0, one size step per chunk with 10 years of experience (quarter-year integration: the sizes match a
  yearly run within 1 %, test), a build round of up to 8 builds per town (25 s) and the fill per chunk, the tour at the
  end. ot_upward `GAP_S` 240 / `LV_GAP_S` 300 lowered to 8 s for the run (restored at Stop), so upward doses and level
  weights can come about once per chunk from the round's checks. `SIMGROW start mode=buildout chunks=10 years=100`,
  one `SIMGROW chunk chunk=k of=10 years=10 ...` per chunk (the year line's fields). Expected ~3.5-4 min on a fresh
  0302-like map (the fills alone: ~15,000 forced buildings at ~100 per s); 2-3 min would need fewer years.
- **Game date** (check box "Move the game date with the simulated years", default on since §68, off before): unticked, the calendar stands
  still (towns.md), so a 1900 map never unlocks level 3-4 town buildings (era limits 1950 / 1990) and the main mod's
  LEVELS can only shift level 1 against 2. On: at each round year (and the last year) `makeGameSetDateCmd(Date.new(start
  year + simulated years, 1, 1))`, forward only (`SIMGROW date year= was= ok=`); the base calendar editor and the Stress
  Test's year jump use the same command (findings lines-vehicles "Year jump"). Vehicles and eras follow: a throwaway save.
- Tests: test_simgrow "pace 0", "early fill", "runner: the main driver stays held through the fill", "the extent
  rule", "simRoundReady", "Fill every 8", "Build out", "move the game date", "runner: Build out"; test_hud "Build out is
  green ...", "hudview: fill every tips ...".

#### Growth-demand trigger (2026-10-12, offline; in game: TESTING.md "Real map test" item 0)

*Why.* The first real-map run (session `2026-10-12_2306_sqot-dev`, natural pace, 16 towns, 32 simulated years) built
nothing: 388 CHECK lines, all `why=open`. The room trigger (6.2 "Trigger": build when open frontage < max(min, 20 %
of the built lots)) assumed the developer fills its open frontage before adding streets. It doesn't: as the target
rises it adds its own streets whatever is free (682 edges, 0.29 per new building), so open frontage stayed >= 2x the
need in every check (Aldershot open 426 -> ~770 vs need 83 -> ~320, free lots 711 -> ~1380; findings "At the game's
natural pace ..."). In normal play the mod did nothing; the showcases built only because their jobs were forced.

*No API switch.* Nothing stops a town's street growth alone (findings, same section): `developmentActive` stops all
growth, `roadDevelopmentLocked` is per edge (our new edges; existing ones only by rebuilding), `townDevelopInterval`
is global. So the mod has to out-build the developer rather than switch it off.

*Design (a + d of the options).* `ot_assess.demand` keeps a per-town session ledger of the size factors the town has
been served up to (first sight: the current ones, so a loaded save's past growth is no demand). Demand = Σ initial x
(sizeFactor - served), so the dose fill's initial-capacity changes don't count, converted to street length at the
town's own persons per metre (`PER_M_MIN/MAX`) and to edges of its mean length (`demand=`, `perEdge=` in CHECK).
- `why=demand` (build) when demand >= `DEMAND_MIN_EDGES` (4) and the open frontage on the town's **own** streets
  (`ownOpen`: locked edges, which only our proposals make, plus this session's built edge ids `townState.own`) is
  under the lead; `why=ahead` (wait) when it isn't. Lead = max(1.25 x the lookahead threshold, min(2 x the game's own
  open frontage, 0.5 x the built lots)): our streets get at least as good a chance at the houses as the game's, never
  a long empty ladder. Own streets count wherever they are (arms beyond the extent), so their empty frontage always
  holds the trigger.
- The increment is sized to the demand in the styles without `mech` / metropolis (`maxEdges` = clamp(demand, 6, the
  lookahead's maxEdges)); grid / superblock / metropolis keep their whole frames. A build serves its length x perM of
  capacity (`ot_assess.served`); demand beyond `DEMAND_BANK` (2) increments is dropped (no burst after a hold or a
  forced fill). The planner's housed-front / arm-fill / empty-budget rules are unchanged.
- Room still triggers below the demand threshold (`why=low`), `over` still blocks. `ot_assess.DEMAND = false` is the
  old behaviour. BUILT logs `trigger=`.
- Replay of the run's 388 checks (persons per edge from the CHECK numbers, no own-frontage gate): the 13 growing towns
  would have triggered (<= ~100 builds), the 3 static towns none.

*Offline (tests/square_organic_towns/test_demand.lua).* A fake ~Aldershot-sized town (5 x 5 blocks, 45 % of the lots
built, 8 empty stubs, 98 % of its target) grows 8 % a check for 24 checks; houses go to free lots at random (gap lots
0.3x), the game adds 60-100 m streets at its own dead ends, either one per 25 persons of target growth whatever is free
("independent") or only while its open frontage is under 0.75 x the built lots ("frontage", which reproduces the run:
the room rule fires 0-1 times in 24 checks). Pooled over 5 seeds:

| Scenario | builds / run | mod share of new edges |
|---|---|---|
| room rule only, frontage | 0-1 | 1 % |
| NA grid (mech, 28-edge frames), independent | 4-11 | 59 % |
| EU organic (demand-sized 8-18), independent | 9-12 | 60 % |
| NA grid, frontage | 4-11 | 39 % (the game builds ~25 % fewer streets than with the room rule) |
| EU organic, frontage | 12-13 | 48 % |
| stalled town (no houses at all) | 1 | then `why=ahead` |

The share is capped by where the game puts its houses: the lead only lets our open frontage match the game's (x2,
<= half the built lots), so if the game fills its own streets first our streets wait (`ahead`) instead of laying
empty ladders. Levers if the real-map share stays low: `OWN_MATCH` / `OWN_CAP` (more lead), `DEMAND_MIN_EDGES`,
the "empty" cooldown (240 s) after a planner with nothing to build, and locking more of our streets so the game's
growth can only come from its own dead ends.

#### Shore towns (2026-10-12, offline; in game: TESTING.md "Real map test" item 11)

*Why.* User: "If it isn't already taken into account, I want to emphasise being able to have some coastal towns prefer
spreading across the coastline, similar to how high real estate can be on the coast. This might be more prevalent on
island maps, but lakes also act like this in real life." Before: a coast picked the style (ot_site coast feature), a
fan or a *straight* strip along `water.axis` (the disc's water centroid direction + 90 deg), a slight lean toward the
water (`irregular.coast`), a lattice line at the setback for grids, a metropolis corridor on a straight axis. Nothing
followed a curved shore, and a lake fully inside the 600 m disc was classified as a **river** (land on both sides of
its principal line).

*Water detection* (`ot_terrain`): `isOnWater` can't tell sea from lake (one water level), so the shape of the water
decides. `M.shoreline` walks the land / water boundary from the nearest water point both ways (40 m steps, the
boundary found by bisection across each step to 3 m, sharper turns tried at up to 110 deg; stops at 3 km each way,
3.5 km from the town, an inland grade > 0.2 at 60 m twice (cliffs, headland rock), or when the loop closes; ~10
samples a step, once per town and session). A closed loop with water inside is a lake (< 1500 m perimeter: a
**pond**), with land inside an **island**. In-disc water is a river only when also elongated (variance ratio >= 6),
so a round lake isn't one. `water.body` = river / lake / pond / open; ot_site turns open into sea (wide survey >= 30 %
wet) or lake. Island flag: a closed loop around land, or water on >= 11 of the wide survey's 16 rays with >= 35 %
wet (`wide.waterDirs`). A pond is no coast (features.coast 0, no fan / strip, no lean).

*Shape* (`ot_shape` "shore", index 9): effective distance = min(core r x 2, link (distance off the centre -> foot
segment) / 0.35, sqrt((along / 3.0)^2 + (pd / 0.45)^2)), along = arc length on the traced shore from the town's foot
point (the shorter way round a closed loop), pd = distance from the shore + 4 x the part beyond the depth cap (3.5 x
block depth, 140-350 m, x 0.75 on islands); points on the water side beyond 30 m only get the core / link. Two arms
(ahead / behind the foot along the shore) for the arm rules (`SH.armAt` / `inArm` return the arc along; `SH.ARMED`
replaces the id lists in ot_select); envelope area x 1.3 (`GEOM.shore.env`: the promenade is single-loaded). The site
candidate "coast: a strip along the shore" is the shore shape when a shoreline is traced (else the old straight
linear); `FM.FROM_SHAPE.shore = shore`.

*Form* (`ot_form` "shore", index 7): drawn first (after forced / saved / legacy / dev shape) with p = 0.3 (+0.3 island,
+0.2 water within 150 m) x style (superblock 0.5, ensanche 0.6, NA grid 0.8, Nordic 1.2, JP / MED hill 1.1) x 0.7 when
features.shore < 0.5, at most 0.85; needs features.shore > 0 (sea / lake, >= 600 m traced, water within 450 m). With
the shore-strip shape candidate on top, ~55 % of EU organic coast / lake towns, ~80 % on a small island (offline).

*Waterfront* (`ot_style` `waterPremium` / `shoreFront`, new towns with a form only, water within 400 m): selector cost
x (1 - gain x exp(-(d / 250)^2)), d = distance to the traced shore (shore towns gain 0.35, other forms 0.2). `ot_shore`
(applied in `ot_core.masterPlan` after the crescents): the shore within the plan extent offset inland by waterSetback +
12 m, simplified, smoothed to R >= 180 m, sampled every 10 m, split where it comes within setback + 5 m of the shore or
onto water (tight bays, headlands); shore towns also get the back street (0.9 x block depth, 40-75 m behind) and cross
streets every 0.8 x block length (50-120 m). The style's plan is cut at the back street (or the promenade): crossing
pieces end in a T (snapped to a cross street within 15 m), pieces between it and the water dropped (also the grid's
own setback line). Promenade class main (built medium; small where the straight-wide rule finds it bends; medium class
in late hierarchies, where main is large), back street / cross streets small. Promenade and back street are arm lines
(`armLine`, `mp.hasArmLines`): the line-tips rule keeps their tips dead ends one piece ahead (without it a cross
street at the tip made a corner and the line stopped for good: the north arm stalled in the first offline run).

*Others:* a shore metropolis keeps the shore shape (grid / radial / corridor); a coast corridor metropolis turns into
the shore shape when a shoreline is traced; its band = distance from the shore (`corridorDist`). The dose fill of a
shore town goes beside the build's streets within 300 m of the shore, spread along it (`D.FILL_SHORE_M`), never on the
water side's last 10 m.

*Logs:* TERRAIN `waterDirs= waterKind=`; STYLE `water=kind:body:distance island= shore=length/stops`, styleWhy
`water= island=`, `formWhy=shore:p=0.55,sea[,island]`, `shapeGeom=shore ... shoreLen= depth= [closed] [island]`;
SHAPE `shore=streets/houses cov=m depth=m` (share of street length / buildings within 300 m of the shore, shoreline
covered by a street within 150 m in 50 m bins, 90th percentile inland depth; `ot_metrics.shore`), `shoreFront=row|
promenade|-`.

*Offline* (`tests/square_organic_towns/test_shore.lua`; synthetic coast, bay (curved), lake (3.1 km), small island,
river, pond; a small round core 300 m from the water, 10 increments of 18 edges, houses 80 + 60 x step): classification
right for all six (lake not river, pond pond, island closed); bay shore points within 5 m of the circle; promenade
32-42 m from the shore, no plan point on water. EU organic shore vs clustered: near-water share 1.00 vs 0.49 (coast),
shoreline covered 1700 vs 850 m (coast), 1350 vs 600 (bay), 1050 vs 650 (lake), depth90 106-109 m vs 556-585 m;
island share 0.95 vs 0.66, depth 145 vs 548 m. NA grid coast share 0.89 / covered 1750 m / depth 304 (clustered 0.43 /
950 / 701), Nordic bay 0.58 / 950 / 510 (0.37 / 700 / 759: its 190 m cells), JP dense lake 0.90 / 600 / 133 (0.35 /
350 / 564). No street in the water in any run. Plan cost: shore apply ~40 ms on a 1400-piece organic plan (lupa).

*Save safety:* old frames without a form get no waterfront (no premium, no promenade); forms / shapes append to the
index lists (saved indices unchanged). Changed for every town: a round lake inside the disc is no longer "river" (its
waterfront axis / lean), and no lean toward a pond.

*Not done / open:* the dev showcase has no coast town (Blank Slate's sea is at the map edge; the real-map test covers
it); whether `isOnWater` traces cleanly on real coasts (shallows, rivers mouths: a river mouth may end a coast trace
"lost" or carry it upriver a little); sea vs large lake beyond the trace is a guess from the wide survey (only the
log label); trace cost in game (`TERRAIN us=`).

#### Away from industries (2026-10-12, offline; in game: TESTING.md "Real map test" item 12)

*Why.* User: "Is it also possible to make it so cities build away from factories?" -> "At least have a preference
away." A soft preference for the mod's own street growth, never a ban.

*Industries* (`ot_engine.industries`, `ot_driver:industryFor`): `getEntitiesWithComponent(INDUSTRY)` (as the base
statistics window, `statistic_industries.tl:392`), the construction by `getConstructionEntityForSubconstruction` (as
square_industry_flows; `getConstructionEntityForIndustry` as a fallback), its `CONSTRUCTION.fileName`, the industry
entity's `BOUNDING_VOLUME` centre. Driver thread: the game script's guiUpdate (Main Thread), like every other read.
The map's list is read once per `D.IND_REFRESH_S` (300 s, one listing for all towns; IND line with `us=`), each town's
share (`ot_industry.forTown`: within `SEARCH_R` 1500 m of the town centre) when the list was re-read. Nothing saved.

*Classes* (`ot_industry.PATTERNS`, substrings of the lower-case file name, first match): heavy (w 1.0, r 500 m): steel,
chemical, refinery, coal / iron ore mines, quarry, cement, brick, glass works, saw mill, paper mill, sand excavator, oil
well, dump, sewage, smelter, power plant, any "mine"; medium (0.75, 400 m): machine / vehicle / tire / tool factories,
sand / clay pits; light (0.5, 320 m): food, brewery, farms, forest, fishing, textile, weaving, furniture, printing,
pharma ...; ignore: oil platform, resort (campaign oddities). Unknown names: medium, logged once (`IND unknown file=`).
Era (`strength`, `IND.ERA`): 0.4 up to 1910, rising to 1.0 in 1945 (era range 1900+, M4; was 1890 / 1920).

*Penalty* pen(x, y) = era x min(1.25, sum w x exp(-1.5 (d / r)^2)) (0.22 w at the buffer radius, 0.69 w at half).
Where it applies:
- `ot_select` cost x (1 + 1.6 pen) (`COST_K`): next to a heavy works a piece costs like one 2.6x farther.
- hold (`HOLD_PEN` 0.45): pieces with pen >= 0.45 (heavy works within ~0.7 r; light never; before ~1900 none) wait;
  when the increment would stay under `HOLD_FILL` (34 %) of its edges after the other relaxations, the threshold rises
  by 0.25 a step (least exposed first) until none is held. With 60 % (the envelope's fill share) or before the other
  relaxations (`HOLD_FIRST`) the grids showed no effect / Nordic less.
- envelope check: the effective distance x (1 + 0.5 pen) (`ENV_K`; the relaxation still widens it).
- unshaped towns' sector preference / hotspots lean along the away direction (weight up to 0.5 x the works' pull at the
  centre x era, `IRR_K`), like the coast lean with the opposite sign.
- `ot_shape`: a seeded shape axis (no site, context or saved axis) picks among 12 turns (4 for strict grids) the one
  whose arms' mean exposure (pen sampled every 100 m to 700 m) is lowest, if it gains >= 0.03 (`AXIS_GAIN`); SHAPE
  `indTurned=`, shapeWhy "(turned away from industry)". Shore towns' arms follow the shore; the cost steers them
  toward the arm away from the works.
- dose / metropolis DevelopAt points: the ones outside the buffers (all of them when none is outside, `D.outsideBuffers`).
- Not done: a deliberate green buffer strip (the hold and cost leave fields toward heavy works in the offline runs,
  nothing reserves them).

*Logs:* CHECK / STYLE / SHAPE `ind=count/nearest m/heavy count` (`0`: none), PLAN `indPen=` (share of the increment's
street length inside the buffers, `-` without industries), `IND industries= ok= us=` (debug), `IND unknown file=`.

*Offline* (`tests/square_organic_towns/test_industry.lua`; round ~260 m core, 8 increments of 18 edges, a works 550 m
east, 8 town seeds per style; share of new street length within 500 m of the works, none -> heavy / light / heavy in
1880; total length change):

| Style | none | heavy | light | heavy 1880 | length |
|---|---|---|---|---|---|
| EU organic | 0.30 | 0.03 | 0.18 | 0.16 | +1 % |
| EU extension | 0.30 | 0.10 | 0.23 | 0.23 | 0 % |
| JP dense | 0.40 | 0.17 | 0.24 | 0.23 | -9 % |
| MED hill | 0.33 | 0.08 | 0.19 | 0.15 | +1 % |
| Nordic | 0.35 | 0.24 | 0.30 | 0.31 | -2 % |
| NA grid | 0.26 | 0.22 | 0.25 | 0.24 | +4 % (frames go round the buffer NE / SE) |

Boxed in (heavy works 430 m N / E / S / W): EU organic 98 edges (94 without), NA grid 51 (72). No industries (or only
beyond 1500 m): edge for edge the same plan as before. A seeded linear town turns its arms off the works (8 of 12
turned, every arm >= 40 deg off). Single seeds are chaotic (one reordered piece changes every later increment: JP town
13 went 0.21 -> 0.68 in one variant), hence the pooled seeds.

*Save safety:* no saved field; existing towns get the cost from the next load on, their saved frames keep their axis
(only towns without a frame can turn). Crash rule unchanged (read-only API calls, each pcall-guarded).

*Open:* the industry read in the game script's guiUpdate state is unverified (the same calls work in Industry Flows'
GUI state); the file names on real maps (IND unknown lines); whether grid towns need more (their housed front); a green
strip toward heavy works.

#### Away from player facilities (2026-10-18, offline; in game: TESTING.md "Away from player facilities")

*Why.* User: "Is it easy to try to encourage our residents to move away from shipping ports that we build? Same for
things like vehicle depots, etc. It doesn't have to be a hard rule, maybe just a small suggestion." Scope (confirmed):
harbors, vehicle depots (road, tram, rail, water) and maintenance stations, airports and heliports, freight stations;
not passenger rail stations (the M3 station quarter pulls toward them) and not kerbside bus stops.

*Read* (`ot_engine.facilities`, `ot_driver:facilitiesRead`; the depot and station reads verified by console 2026-10-18, docs/findings/lines-vehicles.md: depots, cargo rail / truck stations, harbors as expected, industry stations report cargo + passenger and are excluded by path; airports not yet seen):
`getEntitiesWithComponent(VEHICLE_DEPOT)` (base GUI lists it; maintenance stations are VehicleDepot entities with a
catchment area) -> `streetConnectorSystem.getConstructionEntityForDepot` -> `CONSTRUCTION.fileName`, the construction's
`BOUNDING_VOLUME` centre (the depot's as fallback); the stations from the module's `stationList()` (as railStations /
harbours) -> `getConstructionEntityForStation` (kerbside stops have none) -> fileName, and
`util.station.isStationOfType(st, true / false)` for cargo / passenger, merged per construction (an unreadable
passenger flag counts as passenger). Re-read every `D.FAC_REFRESH_S` (120 s); the classified list's signature (kind and
rounded position) decides whether `facVer` moves, so the towns' info (and the planner's cached sector preference) is
redone only when the player built or removed one. Debug line `FAC facilities= port= airport= heliport= depot= freight=
read= ok= us=` when the list changed.

*Classes* (`ot_industry.classifyFacility`, `FAC_KINDS`; w at the site, r buffer): depot (any VEHICLE_DEPOT or
`depots/` file: road, tram, rail, water depots and maintenance stations) w 0.25 r 180 m; heliport (`heli`) 0.25 / 200;
airport (`stations/air/`, airport, airfield) 0.45 / 400 (noise); port (`stations/water/`, harbor / harbour; passenger
harbors too) 0.4 / 300; freight (a station construction with cargo and no passenger support: cargo rail / truck
stations) 0.3 / 220. Everything else (passenger rail, bus / small stops, underground, mixed stations): none. All lighter
than a light works (0.5 / 320). Era weight (`strength`) kept: dockside and depot-side housing was normal before ~1920.

*Where it applies:* `IND.forTown(all, cx, cy, year, reach, facs)` puts them in `info.soft` (within the same reach) and
into the away direction; `IND.pen` sums industries + facilities (same cap), so the select cost, the envelope lean, the
M3 path pick, the shape axis turn (`rayExposure` / `bestAxis`) and the sector lean see them. Not: the hold
(`ot_select` now reads `IND.penHold`, industries only), keep-clear zones, zone locks / refusals, dose-fill avoidance,
`indPen=`, satellites (`penHeavy`, `nearestLight`), Works, `enclosure`: all read `info.list` / `info.zones`, which stay
industries only. With no facility near, every industry number and plan is unchanged (tests). `IND.FAC_ON = false`
switches it off.

*Logs:* PLAN and SHAPE `fac=count:port/airport/heliport/depot/freight` (`0` none); `ind=` stays industries only (`0`
for a town with facilities only); `FAC` debug line as above.

*Offline* (`tests/square_organic_towns/test_facilities.lua`; round ~260 m core, 8 increments of 18 edges, the facility
450 m east, 3 seeds in quick mode (6 full); share of new street length within 400 m of it):

| Style | none | depot | harbor | airport | steel mill | length (harbor) | held |
|---|---|---|---|---|---|---|---|
| EU organic | 0.35 | 0.29 | 0.25 | 0.23 | 0.10 | +2 % | 0 |
| MED hill | 0.41 | 0.40 | 0.25 | 0.24 | 0.15 | -5 % | 0 |
| Nordic | 0.26 | 0.25 | 0.22 | 0.23 | 0.09 | +8 % | 0 |

Full mode (6 seeds): EU organic none 0.35 / depot 0.31 / harbor 0.25 / airport 0.19 / steel 0.10; MED hill 0.31 / 0.28
/ 0.18 / 0.17 / 0.08; Nordic 0.29 / 0.28 / 0.28 / 0.27 / 0.11 (Nordic responds least, as with industries). A small
suggestion: a harbor or airport cuts the share near it by up to ~45 % (Nordic barely), a depot by 0-15 %, a heavy works
by 60-75 %; no piece is ever held. Penalty at the site (1990): airport 0.45, port 0.40, freight 0.30, depot 0.25 (light works 0.50).

*Save safety:* nothing saved; read-only calls, each pcall-guarded, capped at `MAX_FAC` (20000) entries. Existing towns
lean from the next load on (saved frames keep their axis).

*Open:* the reads are verified by console (2026-10-18); inside the mod's own script state the reader has run only on a
fresh map without player facilities (seed `a`, `2026-10-18_2222_sqot`: `FAC facilities=0 ... read=15 ok=true us=53-102`,
every PLAN `fac=0`, no error), so the classification there and the `fac=` lean are unseen; no airport was on the map;
the strength on real maps. DEV only: the dev simulation's pool drivers (otd_runner.poolDriver) each read the facilities
(and industries) on their own, hence one FAC / IND line per pool driver in that run (17 / 16); a pool driver can briefly
hold an older list than the main driver (the shared town state's `facVer` / `indVer` then flips). Harmless in normal
play (one driver).

#### Real map round 2 (2026-10-13; NEXT_PHASE_BRIEF 20; in game: TESTING.md "Real map test")

Evidence: session `2026-10-13_0018_top-up-598153` (HISTORY.md 2026-10-13): Quick 40 years in 194 s, 16 towns, buildings
2473 -> 5990; 50 BUILT ok / 3 FAILED, CHECK why demand 59 / open 30 (no ahead); mod share of new street edges 28 %
overall, small / medium towns 32-95 %, fast towns 8-10 % (Bexley 47 -> 462 edges, 38 ours; Braintree 74 -> 275, 20;
Burnley 4 of 51). The run's main mod had no industry code yet (no IND / ind= / indPen= fields: the game was started
before that build), and **Testing: grow towns faster was On** (`params=...test_grow=2`, 10 GROW lines: x1.25 forced
size steps, e.g. Bilston 2.71 -> 3.39), so the towns grew partly by the testing param.

*Causes (from the log).* (1) The main mod's attention: only 4-6 checks per town in 40 simulated years (89 checks in 194
s; a check + plan + build + fill takes ~2-4 s of the driver; plans up to 262 ms over 5 slices), and the fill-year wait
timed out every time (`main=0-4/3-13`, 15 s). (2) The fill came first: the forced houses landed before the mod's turn,
on whatever streets the game had. (3) The bank: every demand-trigger check of a fast town read `demand=36.0` = 2 x 18,
the cap; increments <= 18 edges. (4) Island shore town Braintree (MED hill, depth cap 105 m on an island): both shore
arms built out (armBuilt 2964/3084 m), plans of 3-6 edges. (5) Unexplained: every town stopped getting simulated growth
right after the main mod's first dose-fill restore in it (Bilston from year 4, Braintree from year 12, Yarmouth 6, Market
Weighton 3; Bexley never had a fill and grew 13.5x); no command timeout, no failure; the sim's early returns are
"busy" / "off" (developmentActive false) / "gone". Now logged (SIMGROW stall, FILL effect active=), and the main mod
switches development back on if its own fill switched it off (FILL reactivate).

*Changes.*
- **Simulation order (dev, otd_simgrow):** a fill year applies the sizes (waits for their callbacks), then waits for the
  main mod's checks / builds of the `WAIT_TOWNS` (6) towns that grew most since the last wait (`WAIT_MAX_S` 15), then
  fills (each lagging town's current size again with updateAllBuildings, `Sim:townFill`), then waits briefly
  (`WAIT_FILL_S` 4) for the filled towns. The simulated clock stands still while a fill year waits or fills (the run's
  next year came instantly after every wait). Year line: `res=` (step results), `sizesS=`, `waitS= main= mainChecks=
  mainBuilds= timeout=` (before the fill), `filled= fillS= waitFillS= mainFill= mainFillBuilds=`. `SIMGROW stall`
  (once per town: why, active, initials, sizeFactors, pendingS). Quick stays 40 years at 1 s, fill every 4: ~10 fill
  years x (<= 15 + 4 s) + ~30 s, expected ~3-4 min.
- **Fast growers (main, ot_assess):** the raw backlog over the normal bank gives `fast` (1-3, decays x0.8 a check); the
  bank holds 2 x fast increments, a demand increment may plan up to maxEdges x (1 + (fast - 1) x 0.5) = 18 -> 36 edges
  (grid / mech styles too); housed front / arm fill / ahead unchanged. A demand build that left >= 8 edges of demand puts
  the town on a 30 s "more" cooldown and the scheduler picks it first when due (`hot`). CHECK `raw= fast=`. Offline
  (test_demand, EU organic, +20 % target per check for 14 checks, 5 seeds): mod share 53 -> 60 %; with the driver only
  every 3rd check window (the run's scarce attention) 27 -> 34 % (one build per window: the next check waits for houses).
- **Fewer shore / Nordic towns (main):** shore form p = 0.10 (+0.15 island, +0.06 within 150 m, x0.6 weak, max 0.4),
  site shape candidate "shore" x0.25 (Nordic x0.4) of TERRAIN_GAIN (was x0.75 / 1.25): offline coast 0.20, lake 0.20,
  island 0.40 (was ~0.55 / 0.8). Nordic: EU region bias 0.7 -> 0.25 (US / Oceania 0.3 -> 0.2), affinities rough 0.6,
  coast 0.6, valley 0.4, plus a pair term 0.9 x rough x coast (`ot_site.PAIRS`): on the run's sites (rough 1, lakes,
  valleys) Nordic 0.04-0.10 of the weight, EU organic 0.53-0.58, MED hill 0.19-0.31; Nordic names still Nordic (>= 0.6).
  `rough` now damps the 2 km height spread on a flat town floor (x (0.5 + 0.5 x slope term)): Bexley (slope 0.02, spread
  82 m) 1.00 -> 0.5; new feature `floor` (local flatness).
- **Metropolis on a valley floor:** Bexley (river, 4164 persons) was `why=site` because every town of the hilly map read
  rough 1.00. A river / coast / valley town with floor >= 0.7 may become a **corridor** metropolis (chance as from open
  0.55: ~24 % of the eligible); why `river:floor=0.92,rough=...`. Steep towns stay `site`.
- **Shore depth:** the run's SHAPE `depth=` 410-676 m was measured over every street including the starting core (the
  first SHAPE line of Bilston, 400 buildings, already read depth 478 with ~18 of our edges): inconclusive. SHAPE now
  also logs `ownShore=` (the same metrics for the mod's own streets: locked or built this session). The depth cap is
  applied in the shape distance; if `ownShore depth=` stays <= ~350 m, the deep part is the game's / the start core's.
- **Tour shot 1 (dev):** shot 1 was dropped again although it waited 2.5 s with steady frames (`settleMs=2499
  steady=true`); every later request wrote a file; in v8 and v9 too it was always the first screenshot request of the
  game session (inferred: three runs). A tour with shots now sends a primer request at its start when the session has
  none yet (`TOUR start primer=true`, `SHOT primer=true sessionShot=1`; tools/ot_shots.py ignores it) and the first real
  shot waits SHOT_GAP after it; every SHOT line carries `sessionShot=`.
- **Satellite villages (main, ot_satellite):** at a demand build of a town with >= 300 buildings, a seeded 30 % of the
  towns (not metropolis, superblock, ensanche; at most 2 seed tries a session, 600 s apart) look for a site: 24
  directions x 0.8 / 1.0 / 1.2 / 1.5 km, at least 450 m beyond the houses, link from the nearest joinable dead end >=
  550 m; dry within 120 m, mean slope <= 0.08, industry penalty <= 0.15 (heavy works push it away; a farm beside it is
  fine), >= 1.3 km from other town centres and nearer this town, link dry and <= 10 % grade, closestTown = this town;
  score: flat, short link, a road (non-town street) within 150 m (-0.35), lower than the centre (-0.2), seeded jitter.
  First increment: ONE link street (a gentle seeded bend, small town template, no side streets) + a compact core (a
  main street on through the site, a cross street at the site and one a block on: ~5 edges); everything locked, no fill.
  Growth: every 3rd demand build of the town while the satellite has >= 1.5 buildings per core edge within 220 m and < 30
  core edges: its dead ends one block on (+ a side street), within 220 m; when nothing fits it is done (`full`) and the
  build goes to the town. Meadow discs along the link (30-75 %, r 60-110 m, clear of both ends) go into the town's
  style.greens, so its own plan leaves the gap. The site is saved on the town's frame (EV_SAT `sx, sy`): a reload keeps
  the meadow and seeds no second one. Logs: `SATELLITE ... kind=seed|grow site= dist= link= road= low= slope= score=
  cands= edges= linkEdges= coreEdges= near= dropped= ok=`, `SATELLITE built`, `SATELLITE seed=none why=`, CHECK
  `sat=near/coreEdges@dist`. Offline (test_satellite, test_demand): sites 0.8-1.5 km, dry, away from a steel mill, off a
  neighbour, 7+/10 beside a road; link 687 m = 8 edges + core 5 edges, one join; in the growth sim one seed, growth to
  17 core edges, then `full`.
  Since 2026-10-14 (6.3 "Staggered satellites") seeds, Works and districts are paced map-wide (ot_satpace) and a pod
  grows on its own seeded cadence instead of every 3rd demand build.
  Not done: the link is a town street, so the town can put parcels along it (locked: no side streets, but houses may
  come along its first stretch); a country-road link would need a mixed town / country node config (untested lanes).
- **`makeInitialStreets` (research):** `baseConfig.locations.makeInitialStreets` ("Add small streets at the edge of
  industries", api type.d.tl:3554; base mod.script.tl:135 default true, "false experimental"; the new-game page sets it
  true, gui/menu/new_game_or_map_settings_page.tl:407). The Barnard Castle cluster is such a set of streets at a farm that
  the town later filled. Organic Towns leaves it at the default (its satellites are a deliberate version of that).
- **Head start (main, automatic):** on a fresh map (Act on New towns: the saved fresh flag; All towns: any) whose game
  clock is under 600 000 ms at load, every town without a saved frame gets 2 rounds of 12-edge increments (round 1 for
  every town, then round 2; one job every 3 s of running time when the driver is idle, none while the game is paused
  (rev 2: it used to run through a paused start); forced past the needs-room test, fill off, no size
  change). Its streets count as the town's own, so the demand trigger waits (`ahead`) until they are housed. Logs `HEAD
  start towns= rounds= edges= gapS= gameTime=`, `HEAD town= round= outcome= edges=`, `HEAD done`, BUILT `trigger=head`.
  No setting (harmless, one-time, new maps only). Offline: 2 builds of 12 edges, no FILL, size factors unchanged; a load
  past the window: none.

#### Real map round 3 (2026-10-13; NEXT_PHASE_BRIEF 21; in game: TESTING.md "Real map test")

Evidence: session `2026-10-13_0137_sqot-dev` (HISTORY.md 2026-10-13, third run): 16 towns, UK names; most towns read as
round organic blobs from above, forms dominated by wide / lens (7 of 16: every coast town drew the site's fan, which
decided "wide"); Axbridge's head start round 2 laid ~800 m of empty medium street to the map edge; no town had a grid.

*Lead limit* (`ot_select` MAX_LEAD_M 550, `opts.limits.leadM`): with house data (`g.hasBuilt`) no point of a new piece
lies farther than the limit from the midpoint of a street with houses, in every style (a hard cap, never relaxed; PLAN
`leadHeld=`). The head start passes 280 m (`D.HEAD_LEAD_M`) and the same as the arms' fill lead (`armFillM`). Offline
(test_head, EU extension lens, 4 head rounds): worst lead 466 m without the limit, 272 m with it.

*Head start per form* (`ot_driver` headStart / headTick / `D.headLimits`): rounds `D.headRounds` = 2 + buildings / 120 +
1 for linear / fingers / radiating / shore / sprawling + 1 for character towns, 2-5 (rounds beyond a town's count are
skipped without a job); 12 edges (clustered 10). In an armed shape (linear, ridge, cross, fingers, shore) only pieces in
the arm corridors (and connectors) qualify during the head start (`limits.headForm`, PLAN `headHeld`), the envelope x1.6
and the arm fronts 2 blocks further; sprawling / clustered / wide use their form's own parameters. Logs: `HEAD start
rounds=2-5 leadM=`, `HEAD ... round= of= form= character= shape= buildings= leadM= leadHeld= armFill= edge=`, `HEAD done
forms=<form>:<towns>/<edges>e/<character>ch`. Offline (test_head, EU organic 1900 on a round core with 250 houses, 4
rounds, the head start's own streets): clustered 45 edges elong 1.49 / arms 3.5, linear 16 edges elong 1.85 (57 % of the
length in the arms, 28 % without the steering), fingers 24 edges arms 4.5, radiating 16 edges, sprawling 46 edges elong
2.5, wide 44 edges elong 4.1; worst lead 191-280 m. Within 280 m of the houses a linear town's arms stop at ~500 m from
the centre, so its head start is short; it reads along its axis rather than as long arms.

*Forms* (`ot_form`): a coast fan no longer decides "wide" (it adds 1 to wide in the seeded draw: 40 EU organic coast towns
offline clustered 13 / shore 8 / radiating 7 / sprawling 5 / wide 4 / linear 3); radiating ribbon 1.8, sprawling block
1.35 / front 1.9 / 3 hotspots, linear arms x1.15 longer and x0.9 narrower (`shape.kaMul / kbMul`, ot_shape), fingers
narrower. Clustered keeps block 0.9 / front 0.6 (tighter values left a young dev-test core without a joinable plan).

*Character towns* (`ot_map.characters`, `ot_form` CHARACTER): seclusion score = nearest other town / the map's median +
0.6 x (1 - edge distance / 2500 m); the top 15 % (at least 1 from 3 towns, 2 from 8) are character towns; island towns
not among them by a seeded 30 %. Form by a seeded draw (sprawling 3, linear 1.5 (+2 valley, +1 river), fingers 1.5,
shore 2 (+1 island) where a shore is usable). Sprawling character: compact field (no shape: the seeded hotspots pull
patches out), block x1.5, front x2.4, sector x2, 5 hotspots (pull 0.85), meadows style + 4 (at least 6); linear / fingers
arms x1.35-1.45 longer, x0.75 narrower. Saved on the frame (`ch`); a later town doesn't change the pick. The quota
counts the map's own towns only (2026-10-14, NEXT_PHASE_BRIEF 48 item 4): towns the mod created (Works, districts) are
left out of the ranking; a framed town keeps its saved pick (`ch` yes or no) and the rest of the quota goes to unframed
towns by rank. Logs: STYLE `character=yes|no:rank=r/n,score=`, `CHARACTER towns=<own> created= fixed= count= picks=`
(debug; `:saved` on a kept pick). Offline: 40 character towns on flat land:
sprawling 21, linear 12, fingers 7; a character sprawl reaches 768 m with 210 edges (clustered 632 m with 205).

*Map edge* (`ot_map`, `ot_engine.mapBounds` = `api.engine.terrain.getBoundingBox`, re-read every 600 s, `MAP bounds=`
line): pieces with a point within 400 m of the boundary are excluded (`ot_select` classify `edge`, PLAN `edgeHeld=`);
satellite sites keep 400 + 220 m; a seeded shape axis turns (12 / 4 steps) to the least arm exposure within 1.5 km, the
industry turn choosing among the equally good ones (SHAPE reason "turned away from the map edge"); STYLE `edgeDist=`.
Offline: 3 towns 600 m from the edge, 10 increments: nearest node 409 m; 12 linear towns 700 m from it: 9 turned,
exposure 0.29 -> 0.03.

*River bridges* (`ot_bridge`, research: docs/findings/towns.md "The map's bounds and script street bridges"): at a demand
build of a river town (ot_site river) with >= 150 buildings, a seeded 40 %, not yet bridged (frame `br`), one try per
session: from a joinable dead end within 450 m of the river, straight across on the river's normal (+-20 / 40 deg), the
first narrow crossing (12-160 m of water, approach >= 30 m, grades <= 8 %, far bank dry, no existing street crossed, far
streets 30 m clear of others, inside the map margin): approach D -> A, bridge edge A -> B (BANK 12 m of land each side,
deck = higher bank + 4 m, `BaseEdgeType.BRIDGE` + the bridge type: stone, else steel / concrete by year,
`ot_engine.bridgeType`), far street B -> C (70-160 m, down to the ground), a cross street at C (2 x 55 m; since 2026-10-14 not built, CROSS_LATER: 6.3 "Round after the 0502 run"). Every new
node gets its config (ot_proposal), the joined dead end a full one; approach + bridge locked; the dead end's template.
All or nothing: pre-checked, no pruning or halving, no retry this session; built: frame `br` (EV_BRIDGE). Logs: `BRIDGE
outcome=plan span= approach= far= deck= type= typeIndex= edges= cands=`, `outcome=none why=noRiver|noCrossing|far|
noSite|otherTown|noBridgeType`, `outcome=refused why= ...precheck fields`, `outcome=failed`, `outcome=built`. Offline
(test_map): a 60 m river: span 60 m, 5 edges, 5 nodes, one bridge edge, every new node on land with a config, no -0;
none over a 300 m river or without water. Unverified in game: whether a new edge with type BRIDGE builds, the clearance
the game wants, houses on the far street.

*Organic <-> gridded* (`ot_grid`, mod param `town_layout`, 13 languages): era trend e = 0 until 1910, 1 at 1970, 1.3 at
2000 (era range 1900+, M4; was 1870 / 1960 / 1990); setting x {0.25, 0.7, 1.3, 2.4, 4.5} (very organic .. very gridded, default 2 = Organic). Site weights (ot_site):
gridded styles (NA grid, NA suburb, ensanche, superblock) x setting x exp(1.3 e), the extension x setting^0.7 x (0.65 +
0.55 e); boosts above 1 damped by 0.8 x max(rough, coast, valley) (grids stay a thing of open land); on a map whose
region's home style is a grid (US / Oceania) no grid boost, the organic styles / sqrt(boost) instead. EU region:
ensanche 0.3 -> 0.6, NA grid 0.4 -> 0.5. Grid look (organic growers: gridness up, jitter / curve / block spread down;
0.45 e + {-0.25, 0, 0.12, 0.3, 0.5}, at most 0.85) on fresh towns (a saved frame keeps its core plan: its spokes come
from the jitter); the outer zone gets +0.25 more and starts up to 120 m closer (EU organic's extension ring; EU extension
towns get their own straighter ring beyond 450 m from look 0.2); styles are re-resolved per decade (`styleFor` key).
STYLE `gridBias=e=,set=,look=,x=gridded/semi gridLook=`. Offline (test_grid, the 16 run sites, UK names; since M4): grid-ish
share 1900 0.18, 1920 0.24, 1940 0.29, 1960 0.44, 1990 0.51 (true grids 0.03 -> 0.35); 1930 by setting 0.14 / 0.26 / 0.35 /
0.43 / 0.53; US 1930 0.57 -> 0.89. Saved styles stay. The offline tests of the other rules run with it off (fixtures,
`F.withGrid`).

*FILL reactivate* (coordinator, session `2026-10-13_0137_sqot-dev`): a town whose development was on before the mod's
first fill this session (`s.devBefore`) is switched back on whenever it reads off after one of our fills (at the fill's end
and at the next check), every time; FILL logs `active=before->develop:x->restore:y` so the next run shows which command
turns it off (findings towns.md). *Demand bank* (coordinator: 4-year chunks): the bank's fast factor runs to
`BANK_FAST_MAX` 5 (2 x 5 x 18 = 180 edges), increments still up to 36.

*Dev showcase* (other agent's files, not changed here): a character / bridge row would need a river terrain and a
remote town; the Blank Slate showcase has neither. Suggested: a "river town" job with `startJob{ force = true }` cannot
trigger the bridge (demand only); a dev `bridge = true` startJob option could call `bridgeDecide` on a forced job.

#### Neighbour diversity, terrain first, Starting town size (2026-10-13; NEXT_PHASE_BRIEF 22; in game: TESTING.md "Real map test", "Starting town size test")

*Neighbour diversity* (`ot_diverse`, user: "Can we make sure we try not to have the same town style near another town?",
then principle 6): when a town's style (ot_site), shape (ot_shape) and form (ot_form) are drawn, the ids the towns within
`RADIUS` 5 km use weigh less: factor = prod (1 - (1 - MIN) x closeness), closeness = 1 - (d / R)^2, forms MIN 0.25,
shapes 0.35, both floored at 0.15; styles only 0.85 (floor 0.7). Neighbours: a saved frame (always), else this session's
pick of a lower town id (the head start goes in id order, so a fresh map's picks are reproducible). Not touched: a town
with a saved frame (no diversity at all), dev-forced styles / shapes / forms, character towns, the shore form, a form
decided by a site / road shape (FROM_SHAPE); in the shape draw only the style / road / neighbour part of a shape's
weight is scaled, never its terrain evidence (`siteW`). STYLE (debug) `nbr=<count>/<style:form@dist,...>`
`divPen=style:..;shape:..;form:..`. Offline (test_diverse, 5 clusters of 16 EU towns on flat land, 2.5 km apart): pairs
within 3 km with the same form 0.28 -> 0.16, same shape 0.32 -> 0.19, same style 0.35 -> 0.33; distinct forms near a town
2.69 -> 3.06; valley towns beside a linear neighbour stay linear 10/12.
*Terrain first:* a hillside town's "along the contour" candidate x0.8 TERRAIN_GAIN (`SH.HILLSIDE_GAIN`, was 0.5: below a
style's own weights, so most slope towns drew a style shape). Valley / ridge / river (x1) and industry (cost, hold, axis
turn) unchanged here: no in-game evidence that they read weak; the rerun's screenshots decide.

*Starting town size* (`ot_townsize`, mod param `starting_town_size`, 13 languages; a TEST): Game size (default: baseConfig
untouched) / Smaller x0.6 / Small x0.35 on `baseConfig.locations.town.populationDensity` in preRunFn, after base's own
"Population" setting set it (so it multiplies the player's choice; other TownParamList fields kept). Logs `TOWNSIZE
where=preRunFn choice= factor= populationDensity=from->to applied= capture=`; INIT `townSize= popDensity=` (read back at
runtime via api.res.getBaseConfig). Head start: Smaller +1 round (max too) and x1.25 edges, Small +2 and x1.5 (18 edges);
lead limit 280 m and map-edge margin unchanged. First load of a fresh map (the head start's window): `START town= name=
buildings= edges= length= cap= actual= townSize=` per town before the head start (edges / length: the town streets
`measure` counts), then `START summary towns= townSize= buildings=meanX/medianY edges= length= cap=`. Doubts from the
game files (docs/findings/towns.md "Starting town size"): the new-game page builds the map preview (towns included) from
its own locations config and hands that map to startGame2, and base's "Population" can also be changed on a savegame,
so the factor may only scale residents at runtime, and (if it is a runtime factor) would also act on an existing save
whose setting is changed there (the tooltip says: pick it for a new map, keep Game size on existing saves). preRunFn
can't tell a new map from a load (`capture=` logs its argument's type to look for a signal).

#### Real map round 4: form survives growth (2026-10-13; NEXT_PHASE_BRIEF 23; in game: TESTING.md "Real map test")

Evidence: session `2026-10-13_0232_sqot-dev` (HISTORY.md 2026-10-13, fourth run; Testing grow was On, `test_grow=2`): the
towns grew ~9x (2468 -> 22228 buildings), 355 BUILT (33 head, 322 demand), mod share of new street edges 41 %. At
1000-3500 buildings the linear (Harwich), fingers (Holsworthy, character) and radiating (Bingley, Bootle: shape cross)
towns read as one organic blob; Grays' south (MED ensanche, sprawling character) had long empty rectangular loops; 0
BRIDGE lines; satellites: 4 built, 2 dropped (Harwich `dropped=disconnected:13/nearExisting:2`, Workington
`crossesExisting:1/disconnected:12`).

*Causes.* (1) Blob: the game kept building ~60 % of the new streets "nearest the centre where they fit", from its own
unlocked streets; its core's dead ends face the wedges, and the mod's own planner filled the wedges too once the
area-preserving envelope (ot_select) grew past them. Offline model (test_bigform: a round game core, 10x the houses in 16
steps x 4 sub-steps; the game adds streets for the new houses' whole need at its unlocked dead ends / mid-street nodes
nearest the centre, jittered, closing blocks within 35 m; the mod one demand-sized increment per sub-step with the
driver's lock; houses by network distance) reproduces it: linear houses elong 1.11 at 10x, wedge share 0.59-0.73.
(2) Empty loops: the demand trigger's lead was up to 0.5 x the built lots (Harwich 3220 lots, Grays 1326) and nothing
capped the mod's own unhoused length: PLAN `emptyLen` 4-17 km per town at the end (Grays 6.7 km in 87 edges, most of it
built 2-15 edges at a time while `ownOpen` stayed under `lead`); the 550 m lead cap let loop pieces end 400-500 m out.
(3) No bridge: no town read `river` (TERRAIN `waterKind` only coast:lake / coast:sea; the river test looks at the 600 m
disc only), while Bootle's river runs ~1 km out into its lake. (4) Satellite links: `pickSite` checked water and grade
but not the town's streets; the planner then dropped the piece that crossed / ran along a street and the rest of the link
and core as disconnected. (5) Grid trend: the dev sim's 40 years are simulated years; the game calendar stayed ~1900
(every STYLE `gridBias=e=0.33`), so no era change can show in such a run. And a bug: the grid look was applied only to
towns without a saved frame, so it dropped right after the head start saved the frame (later STYLE lines `gridLook=-`):
later increments followed another (rougher) plan than the head start's.

*Changes.*
- **Green wedges** (`ot_wedge`, ot_select; `style.wedges`, set by the driver for armed shapes: linear, ridge, cross,
  fingers; not metropolis or mech grids; `D.WEDGES`): beyond the core zone (`WG.coreR`: the shape's core circle at the
  unrelaxed envelope level x 1.15, at least 180 m; fingers: its core blocks + the wedge factor) and outside every arm
  corridor (`SH.inArm`) the mod plans nothing, never relaxed (PLAN `wedgeHeld=n@coreR`). The core zone grows with the
  envelope, so the wedges keep their proportion.
- **Wedge frames** (`ot_core.frameIncrement`, driver `frameDecide` / `framePlanStage` / `frameBuilt`): at a demand build of
  an armed town, at most every `D.FRAME_GAP_S` 90 s, the unlocked dead ends beyond 0.6 x the core zone that are not yet
  inside a frame (no locked street within 350 m on the ray outward) are linked wedge by wedge in angular order by locked
  small streets (25-280 m, at most 48 edges), the chain ends get a locked tail toward the arm axis (stopping 45 m short);
  tips within 70 m of an arm's axis stay free (the arm's seed: without that gate the linear town's second arm was shut).
  The game's tips there are consumed and a new game street would have to cross the locked frame, so the game's growth
  stays inside / along the arms. No fill; the town's normal build follows (finish "more"); a refusal is not halved (keys
  excluded, retry after 90 s). Logs `FRAME outcome=plan shape= cands= links= edges= coreR= env= us=`, `FRAME outcome=built
  frames=`, `outcome=refused`, debug `outcome=none why=fewTips|fewLinks|planEmpty`. Nothing saved (after a reload the
  locked streets of the snapshot mark the frame: OG.fromSnapshot carries `locked`).
- **Own empty budget** (ot_core `OWN_EMPTY_BASE` 1500 m + `OWN_EMPTY_SHARE` 0.08 x the town's street length, `OWN_EMPTY_MIN`
  4; driver `opts.ownEmpty` = locked or built this session; not forced / head-start builds): the mod's own unhoused length
  plus the increment stays within it, else the increment is empty (`why=ownEmpty:<m>`; PLAN `ownEmpty=m/cap`). Demand lead
  `OWN_CAP` 0.5 -> 0.35 x the built lots; `MAX_LEAD_M` 550 -> 400 (every style).
- **Bridges** (ot_bridge): `narrowWater` (24 rays from the centre to 1.5 km, 12 m steps: water 12-160 m wide with 40 m dry
  beyond) makes a town a candidate too (once per town and session, `s.narrow`); `plan` searches each dead end's crossing
  toward the nearest narrow point (and the river normal for river towns); `CHANCE` 0.4 -> 0.75; the crossing march stops
  beyond SEARCH_R without water. `BRIDGE outcome=none why=noRiver|rare|done river= narrow= us=` once per town and session
  (info, not debug).
- **Satellites** (ot_satellite): the link from one of the 3 nearest dead ends whose link crosses no street and keeps 18 m
  from every street not at its dead end (`linkClear`, `pickSite{ g }`); `D.SAT_RETRY_S` 600 -> 300.
- **Grid look saved** (ot_saved frame `gl`, ot_style): the frame keeps the look its plan was made with; a framed town
  applies it (old frames without `gl`: none, as before).

*Offline* (test_bigform, EU organic 1920, H0 250 houses on F.roundCore, 10x in 16 x 4 steps; houses metrics):

| Form (shape) | before 5x elong / wedge | before 10x | wedges 5x | wedges 10x | frames | game edges before -> after |
|---|---|---|---|---|---|---|
| linear | 1.12 / 0.73 | 1.11 / 0.66 | 3.60 / 0.19 | 4.12 / 0.24, arms 2 | 11 (72 e) | 320 -> 320 |
| fingers | 1.09 / 0.32 | 1.10 / 0.35, arms 2 | 1.55 / 0.26 | 1.25 / 0.25, arms 3 | 12 (57 e) | 322 -> 317 |
| radiating (cross) | 1.06 / 0.65 | 1.11 / 0.59 | 1.52 / 0.34 | 1.57 / 0.34, arms 3 | 13 (65 e) | 326 -> 322 |

(wedge = share of the houses beyond the 330 m start core more than 25 deg / 0.3 x the arm gap off every arm.) Every town
houses its whole target (100 %); the game still builds its streets, mostly along the arm gates and inside. Tighter
containment (no gates) starved the towns (36-61 % housed: the mod's arm fronts can't carry 10x alone), hence the gates.
test_demand shares with the new budget / lead: NA grid independent 60 %, EU organic independent 71 %, NA frontage 40 %, EU
frontage 52 %, fast grower 53 -> 60 %; mean max own open lots -17 % (EU 400 -> 331, NA 352 -> 293). Bridges: a 60 m river
700 m out found by the rays, crossing planned toward it (span 60 m); satellite links clear of a road ring / a road.

*Not done / open:* sprawling / character towns' gaps between clusters (no frames: their shape is compact); "upward
density" in a framed core (the game's own densification is all there is); whether the game really can't cross or attach
to the locked frame (v5: 0-1 side streets on locked streets), whether it branches from mid-street nodes (the model does)
and how much leaks through the gates; frame links joining two existing dead ends (2 new edges at one dead end) build
without refusals; how housed the frame's outer side gets; the empty loops' second possible cause: a housed index fed by
single far houses (any edge with a building counts).

#### Real map round 5: industry streets, satellites built, frames built, towns across the landscape (2026-10-13; NEXT_PHASE_BRIEF 24; in game: TESTING.md "Real map test" 28-33)

Evidence: session `2026-10-13_0342_sqot` (HISTORY.md 2026-10-13, fifth run; Testing grow Off, Quick, 264 s): 16 towns,
1992 -> 15517 buildings, 208 build-round builds, mod share 34 % (12-69 %: Bodmin 12 %, Aylsham 16 %, Barnes 21 %,
Bicester 22 %), screenshots `.cache/ot_shots/2026-10-13_03-50-26/`.

*Causes (from the log).*
- **Frames:** 15 `FRAME outcome=plan`, 12 `outcome=built` (Bodmin 3, Middlewich 3, Crowle 3, Romford 2, Aylsham 1; the
  `built` lines carry no `name=`, which made it look like 1 of 4). Aylsham was refused twice (`Collision` with a medium
  town street crossing a link, `edge149350:medium@0`; later 25 edges `Construction_Not_Possible`): the per-edge diagnosis
  pruned the failing links and set the job to plan again, but `framePlanStage` re-sent the stored increment unchanged, so
  the identical plan was refused again and the whole frame excluded. Romford once `none why=fewLinks`.
- **Wedges:** `wedgeHeld=-` on every unarmed town (compact / lens / shore shapes: 11 of 16), 0-6 on the 5 armed ones: wedges
  only apply to linear / ridge / cross / fingers, and most towns drew round forms (clustered 5, wide 3).
- **Satellites:** 5 seeded (Middlewich, Barrow, Hingham, Romford, Hessle), 2 built (Romford, Hessle), 3 refused by the
  pre-check: `Collision` with 2-18 entities outside the town's snapshot (`ent91138` x2 along Middlewich's link,
  `ent90849..90852` around Hingham's site: consecutive ids, likely farm fields, tracks or country roads; the snapshot
  holds only the town's streets). The prune dropped `sat:link`, but `satellitePlan` planned the same streets again (no
  exclusion there) and a refusal ended the town's tries (`SAT_TRIES` 2, retry 300 s). Others: `why=rare` (30 %) or
  `noSite`.
- **Character towns:** both picks (Barrow-in-Furness sprawling, Bodmin linear) sat 920 m from the map edge: the seclusion
  score gives an edge bonus, the 400 m margin then cut their room. Bodmin (coastal, linear): 10 builds, 53 edges over the
  run, late plans `edges=0 blocked=29 excluded=37` and `edgeHeld=1-11`: the game built 88 %. Barrow (sprawling, compact
  shape with 5 hotspots): plans of 5-12 edges, its own unhoused streets reached the empty budget (`ownEmpty=2841/0`,
  `emptyLen` 7 km): the far patches stayed empty (houses fill by network distance) while the game filled the core.
- **Middlewich (liked):** STYLE `shapeWhy=hillside: along the contour`, linear axis 111 deg, form linear (from the shape);
  the long street up the hill is the mod's arm (`armGap` second arm 829 m), built by 21 demand / arm-fill builds (all
  locked), with 3 frames; the satellite was refused.
- **Clusters at industries:** no mod build there (SATELLITE on=false, no BUILT near them): the generator's
  `makeInitialStreets` streets, filled by the nearest town (docs/findings/towns.md).

*Changes.*
- **"Streets at industries"** (`ot_indstreets`, mod param `industry_streets`, Off / Game default (the default since the final test, 2026-10-13: Off apparently drops the roads between towns too), 13 languages,
  tooltip wrapped): preRunFn sets `baseConfig.locations.makeInitialStreets = false` (Off) or leaves it untouched;
  `[SQOT] INDSTREETS where=preRunFn choice= makeInitialStreets=from->to applied= err= note=newMapsOnly`. Research
  (docs/findings/towns.md "`makeInitialStreets` is applied when the game builds the map"): the preview's GameMap has no
  streets, so the field acts at game start (inferred); industries produce without those streets (workplaces are a
  booster); on a load it is written again and can remove nothing. Risk: "false experimental" in base's comment; the
  worker boost may be lower until a street reaches an industry; whether later-founded industries read it is unknown.
- **Satellites:** `CHANCE` 0.3 -> 0.55, `MIN_BUILDINGS` 300 -> 250; map quota (`D.SAT_MAP_MIN` 2: a town >= 400 buildings
  the draw passed over seeds one while fewer are known this session, saved frames counted; `why=quota`); obstacle-aware
  site search (`ot_engine.obstacles`: every BASE_EDGE incl. tracks and country roads, CONSTRUCTION and FIELD boxes within
  1.9 km, grid-indexed; the link keeps 18 m from edges / 22 m from tracks / 15 m from boxes beyond its first 30 m, the core
  streets too); a refused or empty seed marks its site bad (300 m), the next try comes after 90 s (`SAT_TRIES` 4);
  `partners=ent<id>:<kind>` (street / track / node / field / building / con) in REFUSED and the SATELLITE refusal line
  (`msgs= collisions= partners= tries=`), SATELLITE `why= obst= tries=`. Rules kept (one link, meadow, away from heavy
  industry; near a farm / light industry allowed).
- **Frames:** after a prune `framePlanStage` sends the frame without the links (whole streets) that hold an excluded key
  (`D.frameWithout`, `FRAME outcome=pruned kept= dropped=`); later frame plans leave excluded links out
  (`core.frameIncrement{ exclude }`, why `excluded`).
- **Towns across the landscape** (principle 7): forms (ot_form STYLE_WEIGHTS: clustered / wide down, linear / fingers /
  sprawling up; site factors `FM.SITE_K`: rough land favours linear / fingers, clustered only +0.3 x tight), shapes
  (SH.STYLE_WEIGHTS: compact / lens down in EU / MED / JP / Nordic), `SH.HILLSIDE_GAIN` 0.8 -> 1.2, one road out of town
  -> linear `SH.ONE_EXIT_GAIN` 0.5 -> 0.8; shore form back up (`SHORE_P` base 0.24, island +0.25, near +0.08 within 200 m,
  max 0.7; `SH.SHORE_GAIN` 0.45, Nordic 0.6: offline coast / lake 0.45, island 0.65) and longer, shallower strips (shore
  GEOM ka 3.6, kb 0.38, depth cap 130-280 m); lobes: an unshaped town's hotspots sit on `style.lobeDirs` (driver
  `D.lobeDirs`: the road exits, else the valley / ridge axis or the contour both ways) 300-700 m out (`SEL.LOBE_R`);
  clustered 1 lobe (pull 0.3), sprawling 4 (0.65).
- **Character towns** (ot_map): a town less than `EDGE_ROOM` 1300 m from the map edge loses `EDGE_CRAMP` 0.8 of its
  seclusion score. Sprawling towns (form sprawling, unshaped) get the dose fill after their builds beside the outer half
  of the new streets (`D.LOBE_FILL`, FILL `why=lobes`), so their lobes are housed instead of reaching the empty budget.
- **Metrics:** `MT.landSpread` (ratio of the radius of gyration to an equal-area disc's, share beyond 1.5 x its radius,
  lobes = 8-connected 60 m cell groups with >= 3 % of the buildings) on SHAPE `spread=` and the dev ALLTOWN `spread=`;
  `MT.hillRoad` (the armed shape's arm with the largest climb: length / climb / houses beyond 150 m) on SHAPE `hillRoad=`.

*Offline.* test_spread (5 sites x 6 towns, EU organic / MED hill, a 150-house core grown 6x, the game's streets nearest
its centre, houses by network distance plus the dose fill, round-4 values swapped in for "before"): mean spread ratio
1.26 -> 1.28, clustered / wide 6 -> 1 of 30, coast towns 1.18 -> 1.22 (3 of 6 shore strips), flat / roads / valley /
hillside about unchanged (the model's houses fill nearest the centre, so the outline moves little: the in-game test
decides). test_satellite: an obstacle field moves the site, a track ring blocks links across it, refused sites skipped;
eligible share 0.55. test_demand: a frame link refused by the pre-check is pruned and the other links built (no frame
refusal). test_map: a cramped rim town ranks below a secluded one. Shore form share coast 0.45 / lake 0.45 / island 0.65.

*Not done / open:* separate lobes don't form offline (lead limits and the housed front keep every new piece near
houses; only satellites make real gaps); whether the obstacle list explains the satellite collisions (partner kinds
logged); the in-game effect of `makeInitialStreets = false` (no streets at industries; industries working); the hill
road as a deliberate climb (today: the contour-axis linear arm, which only climbs where the contour bends).

#### Motifs: the framework (phase M0, 2026-10-13; MOTIFS_BRIEF.md; NEXT_PHASE_BRIEF 25; in game: TESTING.md "Real map test" "Motif checks")

*Step 1: two dev-test regressions after round 5 (fixed first).*
- test_runner "own dead ends" (expected 1 build, got 2): round 5's NA_SUBURB form weight (`clustered` 0.5 -> 0.4) moved the
  fake town's seeded form draw to radiating -> cross shape, whose first increment extends one of the two game dead ends,
  so the second increment legitimately used the other one (verified: with 0.5 the old assertion passes). Intended
  behaviour; the test now checks its intent independent of the draw: at most one build per game dead end, the run stops
  `stopped:empty` with `joinable=0 ... noConfig:n`, and the toggle joins our own dead ends.
- test_showcase "K consecutive refusals" (no refusal ever reached the engine): the EU organic twin now drew form wide
  (lens) with 3 green reserves; ot_style places reserves beyond the houses' radius, so two of them covered both of the
  fake town's dead ends (which stick out beyond the houses): every increment came out empty (`planEmpty:
  blockedNode/curve/disconnected`, the frontier `green:4 nojoin:6`). A real main-mod flaw (a town whose growth points
  are all inside reserves never grows by the mod). Fix in ot_core.planIncrement: an empty increment plans once more
  without the reserves within radius + one block of a dead end (`core.greensClearOfDeadEnds`, `core.GREEN_RELAX`; the
  others stay; PLAN `greenRelax=n`). test_fixes covers it; the normal showcase test now also checks EU organic builds.

*Framework (`ot_motif.lua`, pure).* A motif = a small recognisable street pattern placed where the land, the
surroundings or the era call for it, built through the normal planner (increments, housed front, own-empty budget, lead
limit, map-edge margin, crash rule unchanged: a motif only changes what the planner is offered or how it is steered).
- Registry `MO.register(kind)`: `id` ([a-z_], save index in the append-only `MO.IDS`), `derived` (a look the town gets
  from its style / shape anyway: present whenever eligible, recomputed each session, never drawn / saved / diversified),
  `eligible(ctx) -> score 0..1, why` (ctx: resolved style with shape / form, inputs, site features, terrain, year / era,
  tier, capacity, character), hooks `inputs(inputs, m)` (a forced kind before the shape / form pick), `style(p, m, env)`
  (steering and reservations: style fields, `style.greens`), `plan(mp, style, m, env)` (candidate pieces: the master
  plan in place, ot_core.masterPlan; a derived kind's hook runs for every style and checks its own condition), and
  `measure(env, m) -> { edges, total, houses, text }` (MOTIF build lines). An `eligible` error counts as score 0.
- Pick (`MO.pick`, end of ot_style.resolve -> `style.motifs`): a dev-forced kind alone; a saved frame keeps its saved
  motifs (frames without `mo`, i.e. every pre-M0 save, get none); a fresh town draws from the eligible non-derived kinds
  into the slots left after its derived ones (`MO.MAX` 2 in all): slot k taken with `MO.SLOT_P[k]` (0.6 / 0.3) x the best
  score, the kind by weight, seeded per town (`rng.unit(seed, "motif"|"motifPick", k)`); neighbour diversity
  (ot_diverse key `motif`, `DV.MOTIF_MIN` 0.3, neighbours' drawn / saved motifs only; STYLE `divPen=...;motif:`).
  `MO.list(style)` = style.motifs + the derived ones not among them.
- Saved: frame field `mo` = i1 + 64 x i2 (indices into `MO.IDS`), only drawn / saved motifs (forced and derived never),
  no field when none was drawn; `SV.frame(...).motifs` (nil = none); the neighbour reads (`DV.gather`, driver
  `nbrPicks`, this session's `s.pick.motifs`) carry them.
- Migrated (derived, behaviour unchanged): `crescent` (eligible when `style.crescents` > 0 and a crescent meadow exists;
  plan hook = the old `if SEL.GREEN and crescents > 0 then CR.apply` in masterPlan, now `MO.applyPlan`; forced on a style
  without crescents: one crescent meadow) and `hill_road` (eligible when the shape is linear "hillside: along the
  contour"; no plan hook (the shape is the behaviour); measure = `MT.hillRoad`, which now also returns the arm and its
  street count; forced: the shape linear, its strongest candidate = the contour on a slope). test_motif checks the
  master plan through the registry equals the old direct call.
- Logs: STYLE `motifs=id:score:source,...` (source drawn / saved / forced / derived); `MOTIF town= name= event=pick kind=
  src= why= score= edges=- houses=-` per motif when the town's style is resolved (once per style key and session);
  after a BUILT `MOTIF ... event=build ... edges=<this build>/<in town> houses= info=` where the kind measured something;
  dev ALLTOWN `motifs=`; PLAN `greenRelax=` (step 1).
- Dev: Town tab "Motif for Grow now / Plan only (dev)" (Main mod (auto) / Crescent / Hill road; otd_shared `S.MOTIFS`,
  ids checked against `MO.IDS`), sent with every command, runner `motif` -> task -> `startJob opts.motif` -> driver
  `job.motif` (style cache key `:m<id>`, no diversity / no `s.pick` for a forced town); QUEUE `motif=`, inspector line
  "Motifs: ...".
- Offline: test_motif (registry, encode / decode, both migrated kinds, deterministic 0-2 pick, derived slots, save /
  load and old saves, diversity, forced kinds, eligible errors), test_fixes (green relax), dev test_runner (picker ids,
  forced motif in STYLE / MOTIF / QUEUE / inspector, ALLTOWN `motifs=`), test_hud (the picker sends `motif`).
- In game (M0 alone) nothing changed: no drawn kind was registered; M1 adds the first four (below).

#### Motifs M1: terrain / water (2026-10-13; MOTIFS_BRIEF.md; NEXT_PHASE_BRIEF 26; in game: TESTING.md "Real map test" "Motif checks" 38-42)

Four drawn kinds in `ot_motif_land.lua` (registered from ot_motif: `MO.IDS` 3-6 = `hill_climb`, `valley_fishbone`,
`harbour_crescent`, `fishing_village`; `hill_road` stays the derived contour-arm look, index 2). Each: `eligible` from
the terrain stats (`ctx.terrain`: relief plane, `dirRelief`, `shore` trace, water), size / era / style; a `plan` hook
that lays its streets into the master plan; a `measure` for the MOTIF build line. Kinds carry a `group` (`land`: climb
and fishbone, `shore`: harbour and village): MO.pick draws at most one per group.

*Eligibility (score 0..1, x 0.35 for the gridded styles NA grid / NA suburb / ensanche / superblock, 0 for a metropolis).*
- hill_climb: relief plane grade 2.5-7.5 % -> 0..1, or a valley (`dirRelief.valley`, contrast 8-38 m), x height range
  20-60 m, x 0.3 when the mean slope > 18 % (switchbacks are M4), x 0.6 for tier 4. Ridges: 0 (M4's ridge street).
- valley_fishbone: `dirRelief.valley` on sloped ground (mean slope > 2 %), contrast 8-33 m -> 0..1, x a level floor
  (`level` < 10-30 m); river towns 0 (their banks).
- harbour_crescent: a usable shore (ot_shape.shoreUsable, water <= 400 m) whose bay (`L.bay`: chord 250-1400 m between
  two points of the traced shore around the town, the shore's deepest point inland of it) has depth / chord 0.12 ->
  0..1 at 0.33; shore-shaped towns 0 (they have their strip and row).
- fishing_village: a usable shore within 350 m, the relief falling toward the water (within 60 deg), grade 2.5-6.5 % ->
  0..1, tier <= 2 (tier 3 x 0.4, tier 4 0), x 0.6 from 1950.

*Laying a motif's streets (L.overlay / L.layMain).* The motif's line is cut into the master plan like the crescents /
the promenade: plan pieces crossing it end there in a T (a shared junction); crossings whose parts are all dropped leave
no junction; the plan's pieces in a band of 20-40 m beside the line, and parts meeting it at a shallow angle, are
dropped (no street running alongside); pieces in the motif's corridor / zone are dropped (`drop`); motif pieces carry
`motif`, `costK` (main line 0.4, lanes 0.7), `motifLead` (main line), `motifBranch` (a lane's piece at the main line),
`culDeSac` (rib / lane ends). The plan's streets meeting the line cost 0.7 x, the plan within 2 blocks of it near the
town 0.75 x (they lead the town to it). Lines traced from the town centre (stable across sessions: centre, terrain,
seed) carry dense junctions (every 30 m) where they leave the houses.
- **Anchors** (`L.anchors`): the planner refuses streets passing too near the town's streets and the game joins only
  dead ends, so per direction the line looks for the town's dead end that reaches it just beyond its exit (the last
  point within 25 m of a town street): one lying on it (within 7 m: the line continues from it, e.g. the climb's built
  tip) or a circular link arc from it (leaving along the dead end's street, radius >= 95 m, 24 m .. 3.5 blocks, meeting
  the line at >= 35 deg, clear of other streets by 16 m, not steep, not near water); the line's pieces inward of the
  anchor are left out. ot_core.masterPlan plans again when a line has no anchor yet (after `REANCHOR_EDGES` 12 more
  streets) or an anchor's dead end was built on (`mp.motifAnchorIds`).
- **ot_select** (pieces with `motif`, `M.MOTIF_FREE`): no envelope / front / wedge / arm-fill / arm-front / head-start
  limit and no lasso guard (the motif bounds them; terrace loops are no balloons), plain distance in the cost (a climb
  runs across a contour-drawn shape), `costK` applied; the housed front, the lead limit (`MAX_LEAD_M`), the lead depth
  (+`MOTIF_LEAD` 2 for the main line), the own empty budget, the map edge and the water / grade checks unchanged.
  **Branches** (`withBranches`): a rib / lane / terrace street at a main-line junction is chosen with the main-line
  piece reaching that junction, and the main line then goes one piece beyond it (its tip stays a dead end): the game
  can't add a street at a junction later (dead ends only).
- Classes small / medium only (ot_core.hierarchy and straightWide narrow them further; no large motif street).

*The kinds.*
- **hill_climb:** uphill bearing = the dry direction with the most rise on a 250 m ring (seeded ties); trace in 40 m
  steps: each the heading within 25 deg of the last (the first step anywhere within 80 deg of the bearing), within 80
  deg of the bearing (no hairpins), rising nearest the target grade min(5.5 %, 0.6 x maxSlope), never over 0.9 x
  maxSlope, not near water / the map edge, up to 900 m or the plan extent; stops at a plateau (three steps < 1.2 %) or
  where nothing fits. Smoothed (R 120). Terraces: spans of ~1.1 blocks along the climb beyond the corridor start whose
  ground at 0.5 / 1 x the offset (0.9 x block depth, 45-80 m) beside it is <= 0.65 x maxSlope; 1-3 (seeded) of the
  flattest, 130 m apart; each a loop: lane, a street along the shelf, lane. Corridor: offset + 25 m either side, beyond
  the town radius + 1.5 blocks (`L.dropFrom`): no plan streets there. Measure `len=built/planned,climb=,grade=,terraces=
  built/planned,stop=,anchors=n/links`.
- **valley_fishbone:** floor trace both ways along the `dirRelief` axis (40 m steps, the lowest heading within 20 deg of
  the last and 45 deg of the axis, up to 650 m each way, stops where the floor rises over 0.8 x maxSlope), smoothed
  (R 150); ribs both sides every 1.3 x block length (70-140 m) beyond the town radius + 1.5 blocks, each up to 2.2 x
  block depth (70-170 m), stopping before 10 m steeper than 0.75 x maxSlope (>= 35 m); zone: rib length + 20 m beside the
  spine beyond that radius cleared. Measure `spine=,ribs=,sides=l+r,spacing=` (median gap of built ribs).
- **harbour_crescent:** the bay's shore run offset inland by waterSetback + 12 m (points on water or within setback +
  5 m of the shore left out), smoothed (R 90); lanes inland every 1.0 x block length (55-90 m), 1.2 x block depth
  (50-100 m), stopping at water / steep ground; zone: lane + 15 m inland cleared (water side always) except the plan's
  streets meeting the crescent in a T. Style hook: `shoreFront` off (the record's `replaced`), `waterPremium` on. Dose hook
  (`MO.dose`, driver `D.MOTIF_FILL`): a build with crescent streets gets the dose fill (FILL `why=motif`, also in
  unshaped towns) at FILL_OFFSET on their land side. Measure `front=,cover=built/planned share of the bay's shore,lanes=,
  bay=ratio`.
- **fishing_village:** the side along the shore with more room (seeded when close) from the shore foot: a waterfront
  street (offset waterSetback + 12 m, smoothed R 100) from the foot to past the village; 3-4 (seeded) streets from it
  every 0.9 x block length (45-80 m), starting 0.8 x the town radius (>= 60 m) along, one heading for all (uphill within
  35 deg of the inland normal), 3 x block depth long (120-260 m) or until steeper than 0.9 x maxSlope (>= 50 m); the block
  between them cleared. Style hook as the harbour's. Measure `front=,streets=built down to the water/planned,len=,heading=`.

*Offline (test_motif_land, 10 tests; EU organic, a 4 x 4 vanilla core, 12 increments, join "deadEnd" as in game).*
Fixtures: `F.terraces` (6 % with shelves, grade 2-10 %), `F.bay` (a round bay, shore 300 m east), `F.shoreSlope`
(sea 250 m east, land rising 6 %), plus F.plane / F.valley / F.coast / F.river / F.flat.
- Eligibility only where the land fits: flat / coast / river / ridge none; plane / terraces climb; valley climb 0.30 +
  fishbone 1.00; bay harbour 1.00; sloped shore village 0.74 (+ climb 0.42). Picks (auto style, 120 valley towns): 69
  draw a land motif (one at most), flat towns none; same town, same motifs; the frame keeps them, old frames none.
- hill_climb on F.terraces: 555 of 871 m built, climbs 40 m, steepest 6.8 %, 2 of 2 terrace loops, no plan street in
  its corridor; F.plane 9 %: 568 m at 5.4 %, no terrace (no shelf); F.valley: 583 m (up one side, then along the
  contour); flat: none (`planWhy=flat`).
- valley_fishbone: spine 823 of 1280 m, 18 of 20 ribs (9 + 9), median spacing 78 m (planned 78), spine on the floor
  (|y| < 30 m), every rib stops at its maximum or before steep ground.
- harbour_crescent: 0.96 of the bay's shore covered by the built crescent (planned 1.00), 15 of 17 lanes, lanes lead away
  from the water, the dose fill on the land side (FILL why=motif).
- fishing_village (400 people): 3 of 3 parallel streets built down to the waterfront, uphill, evenly spaced; waterfront
  255 of 280 m.
- Rules on every run: no crossing edges, min angle >= 15 deg, no edge on water, none steeper than maxSlope, no large
  motif street; the map edge (east edge 650 m out: nothing within 400 m); with house data every new street within the
  400 m lead limit of a housed street and the motif still builds; every new node of 24 motif increments gets a config
  and valid lane indices (crash rule).
- Not offline: whether the game's own street growth fills the climb's corridor (it may; only our plan stays out of it),
  how often real towns anchor (the fixtures' cores have few dead ends; F.hill's short climb to its 300 m top never left
  the core's streets), the dose's effect on the harbour row.

#### Motifs M2: roads / villages (2026-10-13; MOTIFS_BRIEF.md; NEXT_PHASE_BRIEF 27; in game: TESTING.md "Real map test" "Motif checks" 43-47)

Three drawn kinds in `ot_motif_road.lua` (registered from ot_motif after the land kinds: `MO.IDS` 7-9 = `ribbon_village`,
`village_green`, `crossroads_hamlet`; groups `road` (ribbon, green: both lay the town's street beside / out along its
road) and `hamlet`), on the country roads from the new `ot_roads.lua`.

*Country roads (`ot_roads.trace`, pure; driver `countryRoads`).* A country road = a street edge whose template isn't
`town_*`. From the snapshot's edges (houses' extent + 300 m), every road edge crossing the extent circle or meeting a town
street is followed outward edge by edge (always the edge turning least, <= 70 deg, not back toward the town), the edges at
nodes near / beyond the snapshot's rim read through `E.nodeStreetEdges` + `E.edge` (<= 250 reads), up to 1.7 km from the
centre. Result: `roads` (polylines with the heading 150 m beyond the houses, `out` = far end's distance), `junctions`
(nodes where 3+ road edges meet; `own` = nearer this town by `getClosestTown`), `segs` (every road segment seen, side roads
included). Once per town and session (`D.ROADS_RENEW_S` 30 min), `ROADS` debug line, STYLE `roads=`; inputs.roads ->
style.roads (MO.pick's ctx.inputs.roads). `R.forks`: road pairs leaving 35-120 deg apart. Offline the graph's own road
edges are the fallback (`R.fromGraph`).
- **ot_select (all towns):** a plan piece crossing a traced road segment, or passing within 12 m of one away from its
  ends, is blocked (`M.ROAD_BLOCK`, `M.nearRoads`; the graph only holds the roads' first stretch, so before M2 the
  planner could send streets across a country road beyond the snapshot: pre-check refusals).
- **withBranches:** a motif main line that ends at a new junction (no continuation, no other main line, not a town
  node) takes its branches with its last piece (the green's two sides leave the stub's end together).

*Joining country roads (research, not attempted).* The mod joins only plain town dead ends (D3: plain join + a full
node config; docs/findings/towns.md): ot_driver.snapshotGraph marks every other node `noJoin` (`degree` / `edge`). A
country-road node is a degree-2 (mid-road) or 3-4 (junction) node with a working config: joining it means rewriting its
config with every pair of 3-5 segments (ot_proposal.junctionConns can write that; country templates have 4 lane configs
incl. 2 pedestrian lanes like town streets, `country_new_small.street_template.lua`), i.e. a D3 on a node that already
has connections, never tried; a mistake there is a crash class (Engine.cpp asserts) or a road cut for through traffic.
A proposal crossing a road without a node is a Collision. So M2 never touches a road: the ribbon runs beside it, the
green and the hamlet link to the town's dead ends. A future probe (dev): D3 on a degree-2 country-road node beside a town
(verify the config, traffic through it, then a 4-way).

*Eligibility (0 without a traced road; 0 for tier 4 and metropolises; x 0.35 for the gridded styles; ribbon / green x 0.55
from 1950).*
- ribbon_village: a road reaching >= the houses' extent + 300 m: 0.75 (x 0.85 with 3+ roads, x 0.5 tier 3). `road:n=,out=`.
- village_green: mean slope <= 10 %, relief grade 3-8 % -> 1..0; a fork 0.8, else 0.45 (x 0.5 tier 3). `fork:angle=` /
  `edge:grade=`.
- crossroads_hamlet: an own junction of 3+ roads 0.45-1.6 km out and >= the extent + 220 m, not near the map edge: 0.7
  (deg 4: 0.85; x 0.6 tier 3); not superblock / ensanche. `crossroads:d=,deg=`. Style hook: `style.hamlet` = that junction.

*The kinds.*
- **ribbon_village:** for every road reaching far enough and both sides of it: a line offset 0.6 x block depth (32-45 m)
  from the road from where it is a block inside the houses, 450-750 m (seeded) beyond them, in 20 m steps, stopping at
  water (setback), the map edge, the plan extent, a step steeper than 0.8 x maxSlope, or (beyond the houses) within 22 m
  of / across another country road (`segs`); never at the town's own streets (they come and go; the planner refuses a
  hit), so the line stays put across plans. The longest side (+ 40 m seeded jitter; a side already carrying the mod's
  locked streets wins) is smoothed (R 100) and laid with L.layMain (anchors from the town's dead ends, class small, costK
  0.4, lead, pieces ~90 m, dense junctions where it leaves the houses). Lanes: 2-4 (seeded) every 140-190 m (seeded)
  beyond the town radius + 1.5 blocks, off the far side, 1.4 x block depth (60-110 m), stopping at water / steep / a road
  (>= 40 m), dead ends with `branch = "start"`. Zone beyond radius + 1.5 blocks: the plan's pieces between the ribbon and
  the road dropped, those on the far side within lane length + 20 m too (but T's onto the ribbon). Dose hook: DevelopAt
  on the road side (FILL `why=motif`). `lock`: the build's `mrb*` edges locked (D.lockKeys via MO.lockPrefixes). Measure
  `ribbon=built/planned,lanes=,off=,roadSide=<houses between it and the road>,stop=,anchors=`.
- **village_green:** distance 240-360 m (seeded), pushed out in 60 m steps (up to 4 beyond the houses' extent + half a
  block); direction the fork's bisector (+-20 deg) or 16 seeded directions; the first place (lowest slope, then nearest,
  seeded) whose ring is dry, inside the map / extent, gentle (<= 0.7 x maxSlope inside, ring grade <= 0.9 x), clear of
  the roads (20 m) and with no older street inside wins; a place whose ring already carries the mod's locked streets wins
  outright (a green from an earlier session never moves); the motif record keeps the place for the session
  (`m.greenPick`). Shapes: lens 220-280 m long, half width 0.3 x length (both sides leave P at ~43 deg), or triangle
  (sides 220-270 m, half angle = half the fork, 25-40 deg). A 150 m stub from the town to the apex P (anchors on its town
  70 %), then both sides as branches from the stub's end (built with its last piece) meeting at the far end (the last
  piece joins the other side's dead end). Plan pieces inside the green dropped; every plan piece within 26 m of the green's
  streets dropped but at a T (`clearAround`); locked (`mvg*`). Measure `shape=,ring=built/planned,cover=,onGreen=<houses
  > 35 m inside>,ring=<houses within 45 m outside>,d=,ours=,anchors=`.
- **crossroads_hamlet:** no plan hook: the satellite stage (driver `satelliteDecide`) sees `style.hamlet`:
  SAT.eligible(`hamlet`) from 120 buildings without the seeded draw (`why=hamlet`); SAT.pickSite only around the
  junctions (the motif's first, `HAMLET_PICK` 1.0): sites 90 / 130 / 170 m into every quadrant of >= 50 deg between its
  roads, at least the extent + 220 m from the centre, the link >= 250 m, and the satellite's usual checks (dry, slope, map
  edge, neighbours, link clear of streets and obstacles: the road's segments are BASE_EDGE obstacles, so link and core keep
  18 m from them). Dev: a forced hamlet (Grow now) runs the satellite stage at once. Measure `site=,junction=,at=,near=,
  coreEdges=` (`none:waiting` / `none:noJunction`).
- **Satellites (MOTIFS_BRIEF later idea, all towns):** `SAT.pickSite` scores sites beside a crossroads (`HAMLET_BONUS`
  0.3, `junctions` from countryRoads, own only) and within 100-450 m of a farm / light works (`LIGHT_BONUS` 0.3,
  `IND.nearestLight`); only heavy / medium works keep the site away (`IND.penHeavy` <= 0.15; before M2 a light works
  within ~290 m excluded a site). SATELLITE `at=crossroads|light|ring junction= light=`.

*Offline (test_motif_road, 9 tests; EU organic, a 4 x 4 vanilla core, country roads as graph edges within 500 m (their
nodes noJoin, as the driver marks them) and the rest through the trace's fetch; join "deadEnd").*
- Trace: road A followed 1758 m through a 4-way crossroads at 1040 m (deg 4, 4 headings) beyond the 500 m snapshot (31
  reads); fork A / B 60 deg found; deterministic; the driver traces once per session, marks a junction nearer another
  town `own=false`, logs ROADS.
- Eligibility: none without roads; ribbon 0.75, green 0.45 (one road) / higher at a fork, hamlet 0.85; tier 4 none; later
  ribbon lower; NA grid lower; steep: no green; hamlet none for a junction inside the town, too far or another town's.
  Picks of 120 fork + crossroads towns: ribbon 19, green 12, hamlet 24, never ribbon + green together; towns without roads
  draw none.
- Ribbon (14 increments): 365 of 503 m built, 2 of 2 lanes, every ribbon edge beyond 260 m within off +- 14 m of the
  road, lanes away from the road, no plan street between ribbon and road, dose points on the road side, its edges locked;
  the dry side taken when water lies on the other; no road: `planWhy=noRoad`.
- Green (16 increments): lens ring 599 of 657 m (cover 0.91), triangle at the fork 808 of 808 m (1.00), along the fork's
  bisector; no street and no plan piece inside the green; a new session (bigger radius, the motif record gone) finds the
  built green by its locked streets at the same place.
- Hamlet: 8 of 8 seeds 85-175 m from the junction, link and core clear of the roads; without the motif a crossroads site
  wins 10 of 10 (flat land); `none:waiting`, then the satellite's numbers.
- Satellites and industry: beside a farm 12 of 12 (100-450 m from it), within 500 m of a steel mill 0 of 12.
- Rules: no crossing streets, min angle >= 15 deg, no street across or onto a country road (beyond the snapshot too), no
  water / steep edge / large motif street, map edge (900 m east edge: nothing within 400 m), lead limit with house data
  (the motifs still build), every new node of 12+ increments a config and valid lanes, never a join at a road node.
- Main 361 / dev 113 tests green; M1's numbers unchanged (withBranches' end rule only at new junctions).
- Not offline: real road networks (bends, bridges, road-side constructions: the segs know only streets / roads followed),
  how often the town anchors the ribbon / green, whether the game's growth fills the green's middle, hamlet refusals.

#### Motifs M3: town structure / era (2026-10-13; MOTIFS_BRIEF.md; NEXT_PHASE_BRIEF 28; in game: TESTING.md "Real map test" "Motif checks" 48-52)

Four kinds in `ot_motif_town.lua` (registered from ot_motif after the road kinds: `MO.IDS` 10-13 = `ring_road`,
`station_quarter`, `workers_terraces`, `culdesac_pods`; groups `ring`, `works`, `pods`; the station quarter is a derived
kind). `TW.ON` (fixtures: off in the other offline tests, eligibility 0, so their draws stay as measured; test_motif_town
turns it on with `F.withTownMotifs`).

*Joining (research in the code, no new engine behaviour).* The planner joins only plain town dead ends (`join =
"deadEnd"`, ot_plan.joinable) and never splits an existing edge: a new street crossing a town street is refused
(`crossesExisting`), one passing within 16 m `nearExisting`. So the ring never splits a radial street: it joins radial dead
ends (a stub straight on out of them, or through a dead end lying on the circle) and is cut where streets cross it. Two
`ot_select` additions for junctions where several new streets must meet (the game joins only dead ends): pieces flagged
`motifJoin` (with `motifBranch`) take the pieces at their ends along also when that junction is a town node that is still a
dead end (withBranches; before only new junctions), and `motifWait` branches (closes, terrace rows) wait while their
junction is the main line's built tip with the line going on unbuilt (`branchOk`; built alone they would take the tip and
stop the line: the first pod collectors stalled at their second close). Both only on M3 pieces: M1 / M2 numbers unchanged.

*Eligibility (score 0..1; 0 for a metropolis).*
- ring_road: style EU organic 1 / EU extension 0.7 / MED hill 0.45 (others 0) x `RR.SCORE` 0.5 x flatness (mean slope
  0.06-0.12 -> 1..0) x era (1 to 1940 -> 0.45 from 1975; before M4 0.45 before 1850 -> 1 from 1900) x 0.3 for a linear / shore shape; tier >= 2 and houses' extent
  >= 140 m. `core:r=,era=,slope=`.
- station_quarter (derived, `extra`: present whenever eligible, also on framed / old towns; never saved, no diversity;
  takes no motif slot since M4, before it counted as one at a fresh town's pick): the nearest rail passenger station within the houses' extent + 800 m and no deeper inside
  than 1.5 blocks. `station:d=,n=`.
- workers_terraces: a light works that is a factory (not farm / forest / orchard / fishing) 120-900 m beyond the houses'
  extent with no heavy / medium works within 450 m of it; `WT.SCORE` 0.7 x era (1 to 1935 -> 0 at 1950; before M4 1900 -> 1930) x 0.35 for the
  gridded styles, x 0.5 tier 4. `light:file=,d=`.
- culdesac_pods: EU extension 1, NA suburb 1, NA grid 0.6, Nordic / EU organic 0.5, MED hill 0.3, superblock / ensanche 0.2
  (JP dense 0) x `CP.SCORE` 0.55 x era (0 before 1945 -> 1 from 1970) x flatness (mean slope 0.08-0.15 -> 1..0).
  `suburb:era=,slope=`.

*The kinds.*
- **ring_road:** radius R: the frame's `rr` (saved with the frame at the first build: `SV.frameParam` from the motif record,
  `SV.frame(...).ringR`; old frames none), else an earlier session's ring found by the mod's locked streets on a circle
  (`TW.ringFromLocked`), else the best of R0 .. R0 + 120 m (R0 = houses' extent + 0.45 block, 160-650 m; score: blocked
  length + 150 per awkward dead end - 40 per stub). `TW.ringScan`: the circle in 10 m samples; bad: water (setback), the map
  edge, grade > 0.9 x maxSlope, country road segments within 16 m, town streets crossing / running within 16 m of it, nodes
  on it that are not joints. Joints: the town's dead ends within 5 m of the circle (snap), built ring nodes (on it with an
  edge along it), and radial dead ends 22 m .. 1.3 blocks inside it whose street points outward within 45 deg (a straight
  stub to the circle, clear of other streets, not steep / wet; >= 40 m along the ring apart). Arcs: runs of good samples, each
  from its first joint to its last (>= 120 m); the full circle when nothing blocks it. Laid with L.overlay per arc (class
  medium where its grade <= 0.5 x maxSlope, else small; the straight-wide rule narrows bent edges), stubs as their own lead
  lines, the plan's pieces crossing the ring cut into T parts (flagged `motifJoin`, they come with the ring piece there),
  the plan kept 26 m off it (`clearAround`); locked (`mrr`). Style hook: organic growers' outer zone = EU extension from R
  with grid look >= 0.35 (era look + OUTER_EXTRA). A ring with arcs missing plans again as the town grows
  (`motifReanchor`). Measure `R=(src),arcs=,closedPlan=,planned=/circumference,built=,cover=,radials=,joints=,stubs=,tees=,
  blocked=,awkward=,class=,outer=`.
- **station_quarter:** stations from `E.railStations` (ot_engine, read from files, unverified: docs/findings/towns.md
  "Listing rail stations"): every station of `stationSystem.getTown2StationsMap()`, its construction
  (`getConstructionEntityForStation`), `stations/rail/` in the file name (or the group's RAIL carrier), passenger
  (`util.station.isStationOfType(st, false)`), the transform's origin and local -Y (the forecourt: the modular station's
  main building faces -Y, its person lanes at y = -17), the bounding box. Driver `stationsFor`: the list re-read every
  `STATION_REFRESH_S` 120 s, per town the stations within 1.5 km with their tracks (`E.obstacles` 350 m, kind track), debug
  `STATIONS stations=,dirs=` per listing and `STATIONS town=,n=,nearest=,front=,tracks=,file=` when a town's set changes;
  `stationRefresh` puts them on the planner's style each snapshot (`style.railStations`, `style.stationKey`), the master
  plan is rebuilt when the key changes (ot_core), and the quarter's MOTIF pick line is logged when it becomes eligible.
  Geometry: the forecourt point (front, or origin + 17 m toward the town without a direction: `side=guess`), the station
  square street 22 m beyond it, an n x n grid (3 or 4, seeded per station) of blocks 0.9 x block length (60-100 m) along the
  station x 1.0 x block depth (45-80 m) away from it; a block side is left out where it is wet, steep (> 0.8 x maxSlope),
  off the map / plan extent, inside the station's box + 8 m, within 20 m of / across a track, near / across a country
  road or across a town street; the lines laid as runs of good sides, every crossing keyed and flagged `motifJoin`; plan
  pieces inside the quarter (and the forecourt) dropped; the Bahnhofstrasse (medium, layMain with anchors) from the centre
  to the grid junction nearest it, unless the forecourt faces away from the town (`side=away`: no link across the tracks)
  or tracks / a road / water cross it beyond the houses (`link=...(blocked)`); locked (`msq`, MO.lockPrefixes now covers
  derived kinds). Geometry lives on the master plan (`mp.stationGeo`: a derived kind's record is new per plan). Measure
  `station=d@deg,side=,grid=nxn,sides=built/planned,link=built/planned,anchors=`.
- **workers_terraces:** the spine straight from the centre toward the works, ending 110 m short of it (layMain, anchors,
  small); rows at the spine's last 3-5 (seeded) stops, spaced 0.8 x block depth (40-52 m), both sides, square to the spine,
  each up to 1.0 x block length (70-100 m) per side, stopping at water / steep / a road / within 90 m of any works / a town
  street (>= 40 m), dead ends (branch, `motifWait`); plan pieces in the terrace block dropped (also T's onto a row); every
  piece `indFree` (ot_select: no away-from-industry cost or hold). Dose hook: DevelopAt beside the build's rows, both sides
  in turn (FILL why=motif). Measure `works=file@d,rows=built/planned,spine=,sp=,half=,anchors=`.
- **culdesac_pods:** 12 directions (seeded turn), each a circular-arc trace from the centre (curvature +-1/700 per m,
  seeded), 20 m steps to the houses' extent + 380-560 m (seeded; not cut at the plan extent and not smoothed, so it stays
  put as the plan and the town grow), stopping at water / the map edge, beyond the houses at a country road (22 m) or a
  step steeper than 0.7 x maxSlope; the best by length beyond the houses - 300 x industry penalty - 150 x grade ratio +
  seeded jitter, a direction carrying the mod's locked streets wins (an earlier session's pods), kept for the session
  (`m.podPick`). Closes on a fixed comb along it (seeded phase / gap 85-120 m, from half a block beyond the houses, 3-6,
  alternate sides), each 1.5 x block depth (60-110 m) or until water / steep / a road / a town street (>= 45 m), skipped
  where it would cross the collector's link arc; plain dead ends (no turning head: the town templates have none and a loop
  head needs ot_plan's 70 m radius), `motifWait`. Green behind: plan pieces within close length + 80 m of the collector
  beyond half a block out of town dropped (T's too), and a reserve disc behind each close (style.greens, once). Collector
  medium where its grade <= 0.5 x maxSlope, else small; locked (`mcp`). Measure `collector=built/planned beyond the houses,
  closes=,heads=plain,dir=,class=,inGreen=<other streets in the green>,stop=,anchors=`.

*Offline (test_motif_town, 11 tests; EU organic unless named, join "deadEnd").* Fixtures: F.roundCore (an organic core,
14 radial dead ends ~320 m out), a station east of the town with tracks behind it (`stationEast`), a food works 523 m NE.
- Eligibility: only where the site fits (ring 0.50 on a flat EU core, less before 1870, none in grids / villages / small
  cores / steep land; quarter 1 with a station within reach, none 2 km out; terraces 0.70 at a food works in 1890, less in
  1920, none in 1935, at a farm, at a steel mill or beside one, in the town; pods 0.44 in 1970, none in 1930 / JP / steep).
  Picks of 120 auto-style towns: 1890 ring 13, terraces 30, pods 0; 1975 ring 3, terraces 0, pods 23; with a station
  every town has the quarter (and ring 0, pods 13: it takes a slot); deterministic, one per group, the quarter never saved.
  (M4: years moved to 1905 / 1975 with the era range 1900+: 1905 ring 15, terraces 33; 1975 ring 1, pods 24; with a
  station the same drawn motifs as without.)
- Ring (16 increments): R 367 m (beyond the core's dead ends), the full ring planned and built (cover 0.99), 36 junctions
  with the town's streets on it, ring edges on the circle +-9 m, stubs head on, no plan street alongside; outer zone EU
  extension from R0 with a grid look; `rr` round trip through the frame (a bigger town later keeps R), the locked-street
  fallback, deterministic. Blocked by a street across the circle and a lake: arcs only (cover 0.57, blocked 529 m), each
  between two joints, nothing on the shore, the street across untouched.
- Station quarter (16 increments): 4 x 4 grid, 37 of 40 block sides built, all west of the station's front, squared to
  it (< 2 deg), >= 19 m from the tracks, a Bahnhofstrasse (245 of 431 m built; the town's arm reached the grid first),
  locked; no station: no quarter and the plan rebuilt without it; forecourt facing away: the grid beyond the station, no
  link; no direction: `side=guess`.
- Terraces (16 increments): 10 rows planned (5 x 2 sides), 3 built, square to the spine (< 1 deg), spaced 40 m, >= 80 m
  from the works, 4+ of their streets inside the works' 320 m buffer (not held), dose points; a chemical plant beside the
  works: none (`noWorks`).
- Pods (24 increments, four styles): collector 417-437 of 520-540 m beyond the houses, closes 2-3 of 3 per town (9 of 12),
  every built close a dead end, no plan street in the pods' zone, reserves behind the closes, locked, the line identical
  at plan extents 900 / 3000 m.
- Rules: no crossings, min angle, no water / steep edge / large motif street; map edge (an east edge 700 m out cuts the
  ring: nothing within 400 m); with house data every new street within the 400 m lead limit and each motif builds (ring 60,
  quarter 29, terraces 9+, pods 17+ edges); every new node of 40 increments a config and valid lanes, never a join at a
  noJoin node. Driver: stations read once per 120 s, per town within reach, tracks once per station, STATIONS lines, the
  style follows (key, MOTIF pick line). Engine (fake api): one rail passenger station per construction (street stops, cargo
  stations, duplicates out), transform origin / -Y, the 16-number transform fallback, the box.
- Main 372 / dev 113 tests green; M1 / M2 numbers unchanged.
- Not offline: whether `E.railStations` works in the game-script state (listing, file names, transform, -Y = forecourt for
  every layout; terminus stations), stations near a town's core (the grid then mostly blocked by the town's streets),
  how often a real core has radial dead ends near the ring radius (else arcs only), whether the game's own growth fills the
  pods' green and the terrace rows' backs, the dose on terrace rows.

#### Motifs M4: more terrain; M3 fixes; era range 1900+ (2026-10-13; MOTIFS_BRIEF.md; NEXT_PHASE_BRIEF 29; in game: TESTING.md "Real map test" "Motif checks" 53-58)

Four kinds in `ot_motif_relief.lua` (registered from ot_motif after the town kinds: `MO.IDS` 14-17 = `switchbacks`,
`ridge_street`, `headland_street`, `bridgehead_quarter`; groups land / land / shore; the bridgehead quarter derived and
extra, locked `mbh`). `RL.ON` (fixtures: off in the other offline tests; test_motif_relief turns it on with
`F.withReliefMotifs`).

*Slots (fix).* A derived kind may be `extra`: a quarter from an event in the town's life (the player's rail station, the
town's river bridge) takes no motif slot (`MO.slotsTaken` counts the others): a town's drawn motifs never depend on it.
Before, a station near a fresh town took a slot (ring picks 3 -> 0 of 120). The derived site / style looks (crescent,
hill_road) still take a slot: they are the town's own character (at most `MO.MAX` 2 of those and the drawn kinds).

*Give-up (fix).* A `motifWait` branch (close, terrace row, ridge spur, headland lane) whose main line's next piece is left
out (excluded: refused in game or by the planner this plan, blocked, water / steep / edge / nojoin) is counted once per
plan (ot_select `opts.waitRefused`, ot_core per style `_motifWaitN`); at `SEL.WAIT_GIVEUP` 6 the branch is dropped
(`style._motifGaveUp`, excluded like a refusal for the session; MOTIF `event=waitGiveUp piece= line= plans=`). A next piece
only held by the lead limit / housed front never counts (the houses come). The line's tip stays a dead end.

*Era range 1900+ (user, 2026-10-13: TF3's earliest start year is 1900; docs/findings/towns.md).* Every era curve now
spans 1900 to the latest years: ot_grid trend 0 until 1910, 1 at 1970, 1.3 at 2000 (was 1870 / 1960 / 1990: a 1900 start
already had a third of it); ot_industry away preference 0.4 to 1910 -> 1 at 1945 (was 1890 -> 1920); ot_site gates
ensanche 1920 (was 1860), extension 1900 (1850; the style weights follow the grid trend), ot_style's Spanish ensanche
pick 1920, the EU organic town's extension ring from `EXT_OUTER_YEAR` 1915 (was era band 2, i.e. always); ring road era
1 up to 1940 -> 0.45 at 1975 (an old-town motif of the early game; was 0.45 before 1850 -> 1 from 1900); workers'
terraces 1 to 1935 -> 0 at 1950 (was 1900 -> 1930). Unchanged: superblock / NA suburb from 1950, pods 1945 -> 1970,
polycentric metropolis from 1950, ribbon / green / fishing village x less from 1950, templates new from 1940. The era
bands (ot_inputs) keep their bounds; their first band (< 1850) never applies. The showcase's era rows use the map's year
or 1900 / 2020 (none before 1900).

*Eligibility (score 0..1; 0 for a metropolis).*
- switchbacks: relief grade 0.065 -> 0.10 (0..1), x 0 above 1.35 x maxSlope (no legal bend anywhere), x relief range
  30-70 m (0..1), x 0 on a crest (the ridge street), x 0.5 tier 4, x 0.35 grid styles. `steep:grade=,range=,max=`. Shares
  group land with hill_climb (both full on a ~7.5-10 % slope: the draw decides), valley_fishbone, ridge_street.
- ridge_street: a crest (ot_terrain.dirRelief ridge) on sloped ground: (contrast - 8) / 25 x (1.5 - level / 20), x 0.35
  grid styles. `ridge:contrast=,level=`.
- headland_street: coast water (not a river), not a shore-shaped town, a cliff on the stats (`ot_terrain.cliff`, new:
  from the centre toward the water, the brink = the first point whose ground falls 0.25 per m over the next 20 m (the
  water's surface over water) and stands 8 m+ above the water, within 550 m): (h - 10) / 20 x (1 - (d - 250) / 300), x 0.35
  grid styles. `cliff:h=,d=`.
- bridgehead_quarter (derived, extra): `style.bridge` set (the frame's `br`: ot_style; this session's bridge build:
  `Driver:bridgeRefresh`, which also logs the pick and sets `style.bridgeKey`, so ot_core rebuilds the plan). `bridge:frame
  |session`.

*The kinds.*
- **switchbacks:** uphill bearing (L.uphill); leg 0 from the centre along the contour (seeded side) for the houses'
  extent + LEG (2.8 x block length, 180-280 m), later legs LEG long; each traced with L.traceClimb (M4 overrides: within
  60 deg of the leg's contour heading, 15 deg per 30 m step, the first step after a bend 8 deg, no "top" stop) at 5 %
  (0.6 maxSlope at most), traced 1.5 x long. The bend at the leg's end nearest its length (not before 0.4 x it; leg 0 never
  inside the town) whose arc (radius 80 m >= ot_plan.MIN_RADIUS, turning through the uphill bearing to the mirrored
  heading, 60-200 deg) keeps its steepest 10 m within 0.97 x maxSlope, clear of water, the map edge, the extent and the
  legs below (0.9 R). 2-4 bends (seeded); a climb ending right after a bend drops it. Laid with layMain (anchors, small),
  stops at each bend's start, apex and end (two pieces per bend), plan pieces within 1.15 R of the line beyond the core
  dropped (green slopes). Dose hook: DevelopAt beside new bend edges, inside / outside the curve in turn. Measure `len=,
  bends=<built>/<planned>(want n),R=,climb=,grade=,legs=,leg=,stop=,atBends=,anchors=`.
- **ridge_street:** crest trace both ways from the centre (40 m steps, the highest of 9 headings within 20 deg of the
  last and 40 deg of the axis; stops at water, the edge, the extent, 650 m, a step steeper than 0.8 maxSlope, or where
  either side 80 m out is no longer 2 m lower: `crestEnd`), smoothed (R 150). Spurs every 1.4 x block length (80-140 m)
  beyond the core, both sides, down the flank until it is steeper than 0.7 maxSlope (1.6 x block depth, 50-110 m;
  >= 40 m), dead ends with `motifWait`; the flank zone (longest spur + 40 m) beyond the core has no other plan pieces.
  Medium, layMain with anchors both ways. Measure `spine=,crest=<share of the built spine with both sides lower>,spurs=,
  sides=l+r,stop=,anchors=`.
- **headland_street:** the brink traced both ways along the coast from the cliff point (40 m steps; each step's brink
  searched on the seaward normal 90 m inland .. 140 m out; <= 40 deg turn per step, 110 deg from the start, 650 m), the
  street the brink offset inland by waterSetback (>= 25) + 15 m (points on steep / wet ground end a run; the run through
  the town's point kept), smoothed (R 120). Lanes inland every 1.0 x block length (55-90 m), 50-100 m, dead ends with
  `motifWait`. Plan pieces between the street and the cliff (and up to 70 m beyond the street's line seaward) dropped, the
  lanes' block inland too (T's onto the street kept). Style hook: no ot_shore promenade (its shore lies at the cliff's
  foot). Dose hook: DevelopAt on the inland side (RM.doseSide). Measure `front=,setback=<min>..<mean>(plan),seaward=,
  lanes=,houses=<inland>/<sea side>,cliff=<h>m@<d>,stop=,anchors=`.
- **bridgehead_quarter:** the bridge: this session's plan (`style.bridge.C` / `heading`: the far T junction and the
  crossing's heading, Driver:bridgeBuilt) when a node lies there, else the snapshot's longest street edge over water with
  both ends on land (far end = farther from the centre), followed straight on through 2-street nodes (<= 220 m) to the
  cross street's junction C. Grid: origin C, f = the bridge's heading (away from the river), 4 columns of 55 m (ot_bridge
  CROSS: the cross street's dead ends are junctions of row 0, which continues straight on from them), 3-4 rows (seeded) of
  1.0 x block depth (45-80 m); a side is left out where wet, steep (> 0.8 maxSlope), off the map / extent, near / across
  a country road, across a town street, or leaving C along f (C already has three streets). Laid with `TW.layGrid` (the
  station quarter's runs, refactored out of stationPlan), every piece `motifJoin`, plan pieces inside the quarter dropped,
  locked. Geometry on the master plan (`mp.bridgeGeo`). Measure `bridge=plan|graph,grid=4xN,sides=<built>/<planned>,
  linked=<built sides off the cross street's dead ends>,heading=`.

*Offline (test_motif_relief, 9 tests; EU organic, join "deadEnd").* Fixtures `F.steep(grade, swing)` (a slope with shelves
every 200 m), `F.ridgeVar` (a crest with steep east flanks), `F.cliff(bend)` (a 30 m plateau, a 60 m cliff, the sea;
bend > 0 a headland), a river town with its ot_bridge increment applied.
- Eligibility: switchbacks 0.57 on an 8.5 % plane, 1.00 on the shelved 10 % slope, none flat / 4 % / 20 % / valley /
  crest; ridge 1.00 on both crests only; headland 0.79 on the straight cliff and the headland only (none on a beach, a bay,
  a river); bridgehead only with a bridge record (frame `br` -> style.bridge). Picks of 120 towns: steep hill_climb 10 /
  switchbacks 11, crest ridge_street 70, cliff headland_street 41; one per group; a bridged town draws the same motifs;
  a saved ridge street reloads as saved.
- Switchbacks (16 increments): 8.5 % plane 3/3 bends built, 1024 of 1332 m, climb 77 m, grade 0.085; shelved 10 % slope
  2 bends built of 2 (3 wanted), 934 m; every bend radius >= 70 m, its ground within maxSlope, turning >= 100 deg; no plan
  street between the legs; dose points at the bends; none on a uniform 16 % slope (`noBend:bend:steep`).
- Ridge (16 increments): spine 823 of 1280 m, all on the crest (1.00), 10 of 16 spurs built, both sides; houses both sides;
  no plan street on the flanks; uneven crest: every spur on the gentle west half (6/8 built).
- Headland (16 increments): straight 640 of 1360 m, headland 907 of 1303 m, 38-41 m from the brink (plan 40), nothing
  seaward, lanes 10 / 14 built, every lane inland, dose inland; none on a beach (`noCliff`).
- Bridgehead (14 increments): 29 of 30 sides built (4 x 3), all beyond C away from the river, squared (< 3 deg), 6 sides off
  the cross street's dead ends, identical with the graph-found and the plan-given bridge; the plan rebuilt when the record
  appears; locked; no bridge edge: `noBridgeEdge`.
- Rules: map edge, lead limit with house data (switchbacks 37, ridge 54, headland 20 motif edges), configs for every new
  node of 6 increments of each kind (bridgehead too), never a noJoin join. Driver: `bridgeRefresh` from a frame's `br`
  (one MOTIF pick line) and from this session's build (C, heading, key).
- M3 give-up (test_motif_town): a close waiting on a refused collector piece dropped after 6 plans, never built.
- Main 382 / dev 113 tests green.
- Not offline: real slopes (how often a hairpin finds legal ground; the game's embankments on the bends), real crests
  (the crest trace on noisy terrain), real cliffs (the brink search on map coasts; the cliff stat's cost ~180 samples per
  town and session), the snapshot showing the bridge edge over water (`none:noBridgeEdge` otherwise), whether the game's
  own growth fills the switchbacks' green.

#### Forest-aware towns (phase F, 2026-10-13; MOTIFS_BRIEF.md "Forest"; NEXT_PHASE_BRIEF 30; in game: TESTING.md "Forest checks" 59-62)

User: "If the game doesn't already do this, working around dense forest for some cities could be cool, e.g. smaller
fingering cities around forests, vs big suburbs that just bulldoze them." The game doesn't: streets and constructions
auto-remove trees, nothing makes a town keep forest (docs/findings/towns.md "Reading trees near a town").

*(§63, 2026-10-15: on top of the per-piece modes below, a shaped town's locked arms keep 65 m off dense forest, bend /
shorten / drop where they would run into or along it and reach further into open land (`ot_skeleton`, saved `sk`);
unshaped towns' hotspots and satellite sites move off the woods; clear-mode towns' wooded pieces cost x (1 + 0.6 x p x
pen). 6.2 "Landscape-aware skeleton".)*

*Research (read from files, not verified in a game script).* Trees are `ASSET_GROUP` entities with a
`MODEL_INSTANCE_LIST` (fat instances: `transf`; thin: `pos`); a tree model has `modelRep.get(id).metadata.tree`; the octree
finds groups by position. No ground-material / forest sampler; the generator's forest (Worley-noise node graph, seeded)
can't be reproduced. Fallbacks not built: probing with proposals (`collisionInfo.autoRemovalEntity2models` lists the
trees a proposal would remove: one precheck per probe, far too slow for a grid; usable later to measure a build's real
cut), the `Terrain.dataMaps` layers (keys unknown).

*The read (`ot_engine.forestReader`, driver stage "forest").* After the terrain stats, once per town and session
(renewed after `FO.RENEW_S` 1200 s: reforestation, clearing): one octree call (`ASSET_GROUP` within 1.415 x 1.5 km), then
the groups' model instance lists a slice at a time (`FO.SLICE_US` 3 ms per tick), at most ~`FO.READ_MAX` 24k instance
reads per town spread evenly over the groups (a stride per group: each read tree counts `stride` trees; a hard stop at
2x: `capped`), non-tree models (rocks) skipped, dynamic lists skipped. Into `ot_forest` grid: 50 m cells over 3 x 3 km,
density -> cover (0 at <= 25 trees / ha, 1 at >= 90 / ha: UNVERIFIED thresholds, the FOREST line logs p50 / p90 to
calibrate), smoothed once; `share` = forest cells (cover >= 0.5) within 1 km. Kept on the town state and on
`stats.forest` (eligibility hooks see the stats). A reader error with no groups: no grid for the session (no effect).
Cost unknown until the run (FOREST `listUs`, `us`, `slices`).

*The mode (`FO.forStyle`, every plan; nothing saved).* share < 0.08: `none`. A metropolis: `clear`. Else `hug` when a seeded
draw (`rng.unit(seed, "forestMode")`) < p = style (EU organic 0.8, MED hill 0.75, Nordic 0.75, JP 0.55, EU extension 0.45,
NA suburb 0.12, NA grid 0.1, ensanche 0.08, superblock 0.05) x era (`FO.eraF`, 2026-10-15 §59: x1.12 to 1910, back to 1
by 1930, 1 to 1950 -> 0.5 at 1990; was 1 to 1920 -> 0.25 at 1980; era range 1900+) x size
tier (1, 1, 0.6, 0.3) x character town 1.4, at most 0.95; else `clear`. The draw is fixed and p only falls with years and
size: a town may turn from hug to clear, never back. (Forest lanes use the factor without the early boost.)

*Hug in the planner (ot_select; clear / none: unchanged, identical plans).* pen of a piece = its mean cover, or the
cover-weighted wooded length / 120 m when more (long loops). Cost x (1 + 2.2 pen); an open piece (pen < 0.15) with forest
in the next cell x (1 - 0.2 edge) (streets along the edge). Pieces with pen >= 0.45 wait (`forestHeld`) while the increment
fills elsewhere (the envelope / housed / arm relaxations come first: the town reaches out along clearings); when it would
starve (< 34 % filled) they come back 0.2 at a time (`forestRelax`), and once relaxed wooded pieces fill at most
`FO.CUT_FILL` 50 % of the increment (a hug town boxed in by forest grows, about half as fast per increment). Motif pieces
are costed, never held. Dose points (dose and metro fill) on the open side of a street when the other side is forest.

*Logs.* `FOREST town= name= groups= reads= trees= nonTree= stride= capped= cells= dense= share= p50= p90= listUs= us=
slices= err=`; STYLE / SHAPE / ALLTOWN `forest=<share>:<mode>`; PLAN `forestMode= forestCut=<share of the increment's
length in forest, the grid as read before the build> forestHeld= forestRelax=`.

*Offline (test_forest, 14 tests).* Mode shares of 200 towns: EU organic tier 2 1900 0.80, 1990 0.20, tier 4 1900 0.23;
NA grid 0.10; Nordic 1950 0.46; tier 3 1960 0.23, character 0.34; metropolis 0; never clear -> hug with the years. A cross of
160 m clearings in forest beyond a 260 m core (6 seeds x 8 increments; hug vs clear): forestCut EU organic 0.17 vs 0.53
(length 4103 vs 5709 m, reach 567 vs 533 m), MED hill 0.23 vs 0.53, JP 0.10 vs 0.49, NA grid 0.19 vs 0.61 (length 0.56x);
Nordic only with 440 m clearings 0.21 vs 0.40 (its ~230 m cluster cells can't thread 160 m ones: 0.63 vs 0.71). Forest on
one side: cut 0.02 vs 0.31. Boxed in by forest beyond 300 m: EU organic 51 of 94 edges, NA grid 44 / 72, Nordic 56 / 74 in
6 increments. Clear / none: identical plans. Dose points on the open side. Driver stage slicing; engine reader with a fake
api (stride, weights, rocks skipped, no ASSET_GROUP type).

*Not offline / risks.* Whether the octree finds the forest groups and how big they are; the read's cost on a forested map
(one octree list + up to ~48k instance reads per town and session); TF3's real tree density (the cover thresholds);
the town developer's own streets and houses still clear forest (the hug only steers the mod's streets; houses on the
forest side of an edge street remove trees); a grid read after building shows the streets' clearings, which can open
"clearings" a later plan prefers; reforestation slowly refills open land (the grid renews every 20 min).

#### Later ideas: upward density, protected meadows, tree-lined entries, polycentric next steps (later-ideas phase, 2026-10-13; MOTIFS_BRIEF.md "Other ideas"; NEXT_PHASE_BRIEF 31; in game: TESTING.md "Final test: all phases" G 22-25)

The user approved four of the "Other ideas" (MOTIFS_BRIEF.md); "reshape starting towns" waits on the Starting town size
test (does `populationDensity` shrink the generator's cores?). Every change is offline only: the run after this phase is
the first in-game test of everything since session `2026-10-13_0342_sqot`.

*1. Upward density in big towns (`ot_upward`, driver `upwardDecide` / `upwardStart` / `upwardEffect`).* Real map round 4
(9x growth): at 1000-3500 buildings every new resident needed a new lot, so towns spread out (blobs). Lever:
`makeTownDevelopAtCmd(point, false, true)` (upgradeBuildings) at `UP.POINTS` 3 points in the core (within 0.45 x the
town's building radius, 200-900 m), beside the midpoints of its streets (main 1.6 / medium 1.3 / small 1 x the buildings
within 60 m; at least 3 buildings there; 150 m apart and from the last 12 points; outside industry buffers), on the side
away from the centre. Known side effect (findings towns.md): DevelopAt resets the initial capacities to the town's size
(v5's fill twin grew 12x), so the fill stage restores them right after with **no allowance** (`UP.EXTRA` 0; the dose's
+15 % does not apply): the growth target stays where it was, so whatever the upgrades add to the core's capacity houses
residents who would otherwise need new lots at the edge. Who: `UP.decide` - at least `MIN_BUILDINGS` 1500, or
`PRESSURE_BUILDINGS` 700 with `PRESSURE_PLANS` 3 demand plans in a row held (`UP.held`: empty, or < half the ask with
housed / wedge / lead / meadow holds or the own empty budget spent); never a metropolis (its fill is its own), forced /
dev / head-start jobs; at most every `GAP_S` 240 s x 0.75-1.25 per town; not during a fill's surge window; not above
`CAP_K` 1.6 x the town's base initial capacity. The cut: an upward town's demand build gets `UP.cut` 0.25 (1500 buildings
or pressure) .. 0.5 (4000+) fewer edges (never below DEMAND_MIN_INC), so the mod's own streets stop leading the sprawl.
The dose follows the build, or an empty plan (the case the form can't absorb). Logs: `UPWARD town= why=big|pressure
after=built|empty buildings= cut= asked= edges= coreR= points= main= medium= near= at= cap= perBuilding= initial=
pressure= n=`, `FILL restore` (exact), `UPWARD effect s= near= buildings= cap= perBuilding=a->b initial= target= active=` at
the next check, debug `UPWARD skip=gap|surge|cap|noPoint`, PLAN `upCut=why:cut:asked`, dev ALLTOWN `later=ups=..,pb=..`.
Not used: `makeTownCustomDistributionWeightsCmd` (the town editor's level-to-capacity weights, findings towns.md "Town
level weights"): it would shift a whole town's building levels, persists in the save after the mod is removed and is not
local to the core.

*2. Protected meadows (`ot_meadow`; ot_select reserve, ot_core.frameIncrement meadow frame).* Wedges only covered the
armed shapes; sprawling towns (form sprawling: no arms unless the style's seeded shape has them, in which case its wedges
apply) and the unarmed character towns (sprawling, shore) filled into discs (Barrow-in-Furness, run 5). Lobes = the
hotspots' headings (ot_select.irregularity: the roads out of town first, else the contour / valley axis; a shore shape:
its axis both ways), deduplicated within 35 deg; between neighbouring lobes >= 70 deg apart the middle 45 % of the gap is
a meadow sector (at most 4). Beyond the core zone (0.9 x the radius of a disc holding the town's street length x block,
at least 220 m) the mod plans no piece in a meadow sector (never relaxed; motif pieces exempt), and the wedge frame
machinery (`D.FRAME_GAP_S`, prune, exclusions) links the game's unlocked tips in a meadow sector by locked small streets
(`frameStreets{ accept = inSector, noTails = true }`: the lobes stay open). Logs: `MEADOW town= form= character= shape=
lobes=deg/.. meadows=n:widths@coreR` (once per town and session), `FRAME kind=meadow`, PLAN `meadowHeld=n@coreR`.
Nothing saved (lobes from the seed, the roads and the shore each session).

*3. Country road character (`ot_entry`; ot_proposal `decor`, ot_engine edge decorations).* Research (findings towns.md
"Tree-lined town street templates"): curving or restyling the country roads would mean removing / re-adding the game's
road edges and rewriting their junction configs: the mod never joins, crosses or rebuilds a country-road node (round 5 /
M2 research), so that part is **skipped**. Town side: the base game ships `town_{old,new}_{small,medium,large}_trees`
templates, identical to the plain ones (lanes, street style, speeds) except `defaultEdgeDecorations` (`alley.edge` both
sides; `preventParcels = false`) and not `simBuildable` (towns never build them, players and scripts can). A seeded share
of towns (`EN.P` by style: EU extension 0.65, NA suburb 0.6, EU organic 0.55, ensanche / superblock 0.5, default 0.4, MED
hill 0.35, NA grid 0.35, Nordic 0.3, JP 0.2; metropolis 0.8) builds its entry streets tree-lined: new edges (>= 25 m) along
a traced country road's first 320 m out of town (within 70 m of it and within 30 deg of its direction) or main / medium
edges within 110 m of where it leaves the town. ot_proposal gives such an edge the `_trees` template (override, the plain
lanes) and `decor = "template"`; ot_engine sets `edgeDecorations` from the template's defaults (`edgeDecorationRep.find`,
as the base track builder does; a decoration that can't be resolved leaves the plain template: `treesFallback`). An edge
continuing from a tree-lined dead end without the flag gets the plain template and `decor = "none"` (its copy source
carries the tree row); tree-lined streets are never copy sources. A pre-check refused with tree-lined edges is re-sent
once without them; after 2 such refusals the trees are off for the session. Logs: `ENTRY town= on= p= roads=` once per
town, `ENTRY outcome=built edges= town_total= fallback=`, `ENTRY outcome=refused edges= msgs= refusals= off=`, SEND
`spec=... trees=n`, PLAN `trees=`. "Curvier approaches" (a curving town street beside the road) are not built: the
ribbon village (M2) already lays a street beside the road out of town.

*4. Polycentric next steps (`ot_metro`, `ot_poly`).* Centres at junctions: `MET.junctionCentre` takes the traced
country-road junction (3+ roads) nearest the centre's planned heading (within 75 deg) at 0.75-1.2 x its distance range,
on flat dry land, 800 m from the other centres; else the ring search as before (`src=junction|ring`). Centres added over
time: a third centre from `POLY_THIRD_CAP` 30000 persons (across the axis); the cap grows the count (1 at 9000, 2 at
18000), the style is rebuilt with the new centre, `METRO event=centreAdded centres= was= cap=`. Per-centre core style:
`MET.coreKind` (seeded; grid share by region: US 0.75, OCEANIA 0.7, JP / East Asia 0.6, RU 0.5, MED 0.45, EU 0.35,
Nordic 0.3; halved for grid styles) - a grid core is a 3x3 / 4x4 straight grid (blocks 70-110 x 55-90 m, rows on its rim
medium) centred on a ring centre, or in a junction's quadrant facing the main centre 30 m off the roads, squared to the
first road (else the town axis), keeping 18 m from country roads, the town's streets, water, steep ground and the map edge;
the plan's own pieces inside dropped, the grid's crossings paired (ot_motif_town.layGrid / pair). Grid pieces are motif
pieces: the housed front, the lead limit and the polycentric empty budget (POLY_HOUSED, POLY_EMPTY 2000 m) apply, so the
grid is built as the houses reach it (no empty downtown ahead of the town). Logs: METRO `at=x:y@D:src:core`, METRO step
`cores=c1:grid@junction:built/planned,c2:plan@ring`.

*Offline.* test_driver (upward decide / cut / held / points; the driver flow: cut PLAN `upCut=`, DevelopAt(false, true)
at the core points, the initial capacities restored exactly; tree-lined pre-check refusal re-sent without trees, ENTRY
lines), test_bigform (upward model, meadows), test_later (entry geometry and the proposal's `_trees` / decor rules, lanes;
junction centres, third centre, core kinds, grid core plan and growth).
- Upward model (bigform model, 10x from 250 houses, wedges on; from ~4x the cut and one dose per step, each dose upgrading
  the houses near its points by 0.35 house each: the in-game effect is unmeasured): clustered r90 654 -> 642 m, mod edges
  690 -> 537, 57 houses' worth upgraded; radiating r90 1062 -> 987 m, mod edges 632 -> 510, 101 upgraded; every town
  housed. The cut is the sure part (fewer mod streets ahead); how much taller the core gets is the in-game question.
- Meadows (bigform model, 10x, the meadow share = houses beyond the 330 m start core inside a meadow sector): sprawling
  towns 0.30 -> 0.17, 0.44 -> 0.35, 0.30 -> 0.13, a sprawling character town 0.13 -> 0.07; every town housed 100 %;
  frames 3-8 (12-43 edges), 76-464 pieces held.
- Entry: EU organic share of towns lining their entries 0.56 (P 0.55); only parallel streets beside the road's first
  320 m or wide ones at the entry; the trees variant keeps the joint's lane rules.
- Polycentric: a junction 1.15 km out on the axis becomes the first centre (the opposite one stays a ring centre, the
  third takes a junction across the axis); grid cores US 0.76 / EU 0.36 of centres; a grid core of 43 pieces / 2.5 km off the
  junction's roads in the quadrant facing the town; a forced near centre's grid built 30 of 40 sides in 14 increments with
  the housed front and the empty budget on.

*Not offline / risks.* Whether `upgradeBuildings` raises buildings near the point at all (Showcase v6: no clear effect
from a single dose; UPWARD effect `perBuilding` decides), and whether the exact restore holds (a FILL restore line after
every UPWARD, `initial` back to before); whether the game builds tree-lined templates and decorations from a script
proposal (first ENTRY built / refused lines; a decoration that can't be found falls back to plain); whether the game's
own growth enters the meadows through the lobes (FRAME kind=meadow built, the shots); junction centres only on maps
where polycentric metropolises appear (9000+ persons, 1950+, open land: rare on a 40-year 1900 run).

#### Final-test round: virtual roads, motifs on real terrain, peninsula tip, forest, station back, coast strips (2026-10-13; NEXT_PHASE_BRIEF 32; in game: run 2026-10-13 `2026-10-13_1945_sqot-dev`, results HISTORY.md)

*Why.* The final all-phases test (session `2026-10-13_0856_sqot-dev`, results HISTORY.md) ran clean and showed the
satellites, frames, river bridges, station and tree reads working, but: no town had a country road (`ROADS roads=0`,
that map was started with `makeInitialStreets = false`, which apparently drops the generator's roads between towns too:
the three earlier maps (default true) have dirt country roads in their shots; findings towns.md), so the road motifs and tree-lined entries
could never trigger; 2 drawn motifs in 16 towns (eligibility calibrated on 6-9 % synthetic slopes; real towns read grade
0.01-0.05, water 250-575 m out; the crescent took one of the two slots; chance 0.6 x score); forest share 0.01-0.08 on a
wooded map (the read's cells: p50 24, p90 60 trees/ha); the station facing away built nothing; the shore towns' streets
reached 665-896 m inland; master-plan rebuilds of up to ~144 ms in one tick. The user loved Stratford-upon-Avon's
mountain roads (the linear shape along the contour of the foothills: `shapeWhy=hillside: along the contour`, the derived
hill road), Southborough's houses at a peninsula's tip (its linear river-bank arm ran out along the spit by chance) and
Sevenoaks' bridge quarter: "the more we can push cities that build with the environment, the better".

*Changes.*
- **Real country roads found** (after a coordinator check of the earlier tour shots: dirt `country_old_*` roads leave
  the towns on the three maps started with `makeInitialStreets` true, yet those runs logged `exits=0` everywhere):
  `SH.exits` only counted road edges crossing the houses' extent, but the roads join the town at its outermost street
  node beyond it: an edge whose inner end lies within `SH.EXIT_PAD` 150 m beyond the extent counts now. And the driver
  reads every non-track BASE_EDGE within the snapshot radius + `D.ROADS_WIDE_M` 400 m (`ot_engine.roadEdges`), classified
  by the street template's `country` flag (`ot_roads.isRoad`; by name when unread), merged with the snapshot for the trace
  and the exits; ROADS `wide=edges/streets/noStreetComp/tracks:country=,town=,other=;<non-town templates>` tells the next
  run exactly what lies around each town. Whether the snapshot itself ever held the roads is open (no earlier ROADS
  lines on a map with roads).
- **Virtual roads** (`ot_roads.virtual`, `D.VIRTUAL_ROADS`): when neither the snapshot nor the wide read holds a road edge, 2-3
  lines from the centre toward the nearest neighbour towns (within 6 km; else the land's directions `D.lobeDirs`, else
  seeded), each traced over the terrain (40 m steps, the gentlest heading within 12 deg per step / 40 deg of the bearing,
  30 m off water, the map edge margin, 1.6 km, at least 420 m). No segments, no junctions. The ribbon village runs on the
  line itself (`off=0`, lanes alternating sides, no road-side drop; `virtual` on MOTIF build), its and the village
  green's eligibility x 0.8 (`why=virtual:`); the hamlet needs a real crossroads (`why=virtualRoads`); tree-lined
  entries (`ot_entry.isEntry`) along a virtual road count from 60 m inside the houses' extent, never in the core.
  ROADS line: `name snapEdges nonTown templates traced virtual=nbr/land/seed`.
- **Motif pick**: the crescent is `free` (no slot, like the `extra` quarters); SLOT_P 0.6/0.3 -> 0.9/0.4, chance x
  min(1, best / P_FULL 0.4); drawn kinds under MIN_SCORE 0.1 are not eligible (`low:`). Every eligibility returns its why
  with the numbers it read; `MOTIF event=elig town= free= terrain=grade,range,slope,dr,water,cliff,spit,wide kinds=
  id:score:why,...` (debug) once per resolved style.
- **Eligibility on real terrain**: hill climb grade 0.012-0.035 (was 0.025-0.075), range 15-45 m, or a soft valley side;
  switchbacks grade 0.04-0.07 (was 0.065-0.10); soft valley / ridge (`L.valleyScore` / `L.ridgeScore`: both sides of the
  most level axis 4+ m higher / lower, full at 20 m, at least 1.3 x the axis' change; ot_terrain's flags asked 8 m and
  2 x) for the fishbone, the ridge street, the climb and their geometry; harbour crescent water within 650 m (was 400),
  bay ratio 0.08-0.25; fishing village water within 550 m (was 350), grade 0.022-0.05, slope toward the water within 75
  deg; headland cliff 6-20 m (was 10-30) within 700 m (full to 300 m). The hill climb's line: smoothing 120 / 70 / none,
  the first within the climb's max grade.
- **Peninsula tip** (`ot_motif_point`, drawn, group `point`, MO.IDS 18, locked `mpt`): the spit (`PT.findSpit`, the
  driver's terrain stage for towns with water in the disc or > 2 % in the wide survey; TERRAIN `spit=tip/neck/width@deg`):
  16 rays from 150 m out in 50 m steps until water ahead, the width across every other step (water both sides within
  300 m, together <= 450 m), the longest neck (>= 200 m) wins. Eligible when the tip lies 120-1300 m beyond the houses
  (score 0.9 x neck / 350, >= 0.45); the plan: a spine from the centre along the spit, re-centred between its shores each
  30 m step, stopping 25 m + setback short of the water, smoothed 100 / 60 / none within the grade; 2-4 dead-end lanes
  (35-90 m) along its last 240 m, alternating sides; the plan's other pieces within 140 m of the spine beyond the core
  dropped (one street of houses on the neck); dose beside the spine and lanes. MOTIF build `spine=,reach=,lanes=,atTip=`.
- **Forest**: LIGHT_HA 25 -> 12, DENSE_HA 90 -> 36, light at least 1.5 x one sampled tree's density (the grid keeps the
  read's stride) and dense at least 2 x light.
- **Station quarter on a station facing away** (`SQ.FLIP_AWAY`): the quarter goes on the station's back, the town side,
  its first row beyond the station's box + TRACK 20 + GAP 22 m, linked to the town (`side=back`).
- **Coast strips**: ot_site SHORE_DIST 450 -> 600, ot_shape coast candidates within 620 m (was 500), ot_style
  WATERFRONT_DIST 400 -> 600; FM.SHORE_P base 0.24 -> 0.34, near 0.08 -> 0.16 within 400 m (was 200), max 0.85;
  SHORE_GAIN 0.45 -> 0.7 (Nordic 0.85); shore geometry ka 3.6 -> 4.2, kb 0.38 -> 0.32, cf 2.0 -> 2.6 (a smaller core
  around an inland centre), depth cap 280 -> 240 m. The wedge rule covers shore towns (`ot_wedge` IDS.shore): beyond the
  core zone, the land farther from the shore than the depth cap and off the link corridor (1 block either side of the
  centre -> foot line) is a wedge, and the frames chain the inland tips (the game's inland growth stays in).
- **Mountain roads more often**: the hillside candidate (linear along the contour + fan) from grade 0.028 (`SH.HILLSIDE_GRADE`,
  was 0.04; also `D.lobeDirs`), HILLSIDE_GAIN 1.2 -> 1.4; soft valley / ridge shape candidates (`SH.SOFT_VALLEY` 6 m,
  1.5 x) so more valley towns grow linear along the floor.
- **Plan slicing**: `core.masterPlan` yields after the grower's plan, before each drawn motif's plan hook and before the
  promenade (`opts.yield`, the driver's coroutine).
- Debug lines: TERRAIN `grade= spit=`.

*Offline.* Main 420 / dev 113 tests green. New: test_motif_point (the spit on a peninsula fixture: tip 1250 m, neck
1000 m; none on a straight coast, dry land or a 800 m-wide headland; 50 of 60 peninsula towns draw it; the spine built out
to 1200 m with 3 of 4 tip lanes in 30 increments, nothing else built on the neck; configs, locks, dose), test_motif_env
(seven sites modelled on the logged values: 90 % of the towns draw a terrain-fitting motif; hill climbs on the hillside,
tips on the spit, fishbones / climbs in the soft valley; the master plan yields 3+ times and resumes to the same plan),
virtual roads (toward neighbours, off water, the driver's ROADS line, the ribbon on the line: 301 of 500 m built in 14
increments, lanes 2/2; entries from the town edge), forest calibration (a 40 trees/ha wood read at stride 3: share 0.41
with 12 / 36, 0.04 with 25 / 90), shore wedge (rules; the fixture town is already shallow, so no change there), the
station's back (pieces on the town side, built, linked; FLIP_AWAY off keeps the old layout). Updated expectations: the
pick share (SLOT_P), the valley land-motif share, shore shares (coast / lake 0.55-0.8, islands 0.7-0.95), the shore
growth comparisons now run without motifs (a clustered bay town drew a harbour crescent along the bay).

*Not offline / risks.* The tree-lined entries go out for the first time (the template / decoration path is unverified;
re-send without trees, off after 2 refusals); a virtual-road ribbon can't get houses ahead of the housed front (fine:
it waits) but may leave a long locked street if houses stall; the shore wedge holds a shore town's mod growth to its
strip (never relaxed); the real eligibility numbers are still unknown: the `MOTIF event=elig` lines of the next run
are the calibration data; the spit search's cost (TERRAIN `us=`).

#### Landscape names and stop names (2026-10-13; NEXT_PHASE_BRIEF 34; tested in run `2026-10-13_2113_sqot-dev`, results HISTORY.md; stop names replaced by ot_stopname, 6.3 "Round after the names run")

User-approved design (the "middle option"): on a NEW map each town gets a REAL name from the game's own active list that
fits its site; no invented words except the satellite composition. Setting "Town and stop names" (Landscape names
default / Game names), one param for both parts (simpler for players).

- **Why it works:** base `names/names.script.lua` townsNameScriptFn draws `num` names at random (reservoir sampling)
  from `::/names/<path>/<lang>/towns.lua`; the engine gets strings only. 18 base lists (`*.names.lua`); the
  `languages` table picks the folder by the game language (fallback en). ot_names.LISTS copies those tables (verified
  2026-10-13) with a classifier id per folder (france/en = French names, germany/en = German, japan/en = romanised).
- **When (ot_driver names phase):** once per new map, before the head start (which waits; NAMES_MAX_S 240 s cap):
  Act on New towns + the saved fresh flag + game time < 600 s, or Act on All towns + game time < SV.FRESH_GAME_TIME;
  never with the saved done flag `nm` (sent with the list folder `nd` right after the assignment, before any rename);
  never in the map editor (driver off). Only a base nameList (`::/names/<path>/<path>.names`); any other set (the
  square_names_us_* mods) or unknown path: `NAMES on=false why=notBase|unknownList`.
- **List and language:** E.townList = `ug_require "::/names/<path>/<dir>/towns.lua"` (the same require the base script
  does; a plain `return {...}`), every folder of the list, one per tick. The folder in use: the game language's
  (`api.util.getLanguage()`, fields unknown: E.language tries .code / .lang / .language / [1] and logs `apiRaw=`) when
  at least half of the map's town names are in it, else the folder holding most of them (`langSource=match`), else
  `why=noListMatch`. Matching the town names makes the language read optional.
- **Classifier:** word-level rules per language (end / start / word / first / last / seq / has + veto), ASCII-only lower
  case (string.lower in a UTF-8 C locale folds bytes of "ü": broke German offline). Tags: estuary, ford, bridge, river,
  coast, lake, valley, hill, cliff, headland, island, forest, marsh, market, plain. A list is usable with >= 20 and
  >= 5 % tagged names. Offline counts on the real lists (tagged / pool): europe/en 333/929, england 365/1033, de
  668/1890, europe/fr 114/931, france 302/2033, italy 173/1922, spain 125/1827, europe/es 20/194, europe/it 38/456,
  europe/nl 26/98, netherlands 67/341, sv 240/704-713, europe/nb 55/122, norway 120/355, usa 393/1970, japan 84 (en) /
  95 (ja) of 262, europe/ru 104/1515; no classifier or under the bar (`why=noTags`): china, korea, asia, oceania,
  poland, europe/ko, portugal (15/196), russia (14-16/259).
- **Town tags (`townTags`):** from the survey the head start does anyway (Driver:terrain / forest run early for every
  town, cached in townState, so the head start skips them): river in the disc -> river / ford / bridge (+ estuary and
  coast with wide water), coast / lake by the water body, shore towns, island, spit -> headland, cliff >= 6 m within
  700 m, rough / ridge / grade -> hill, valley, forest share >= 0.08, flat wet low land -> marsh, open -> plain; big
  towns (>= 2500 target or the biggest tenth at 1.5 x the median) also market / plain.
- **Assignment (`assign`):** every name on the map is reserved; character towns first, then the rarest best tag; per
  town tag a seeded walk of up to 300 candidates of that bucket, score = matched strength x weight (x 1.5 on a rare tag,
  <= 30 names) minus CONTRA x strength for each name tag the site lacks (water names cost most). Rename when the best
  scores >= 0.3 and beats the game name by 0.1; a game name that contradicts the site by less than 0.25 stays (`kept`);
  a contradicting one gets a plain non-contradicting name (`plain`), else any unused one (`random`). Plain / market are
  never searched for: plain towns keep their game names. Deterministic per map (seed from town ids + positions).
- **Satellites:** the mod's satellite villages are streets of their parent town (no town entity, no name), so the
  composition applies to real neighbour pairs: a town within 1.8 km of one 2.5 x its size, without a landscape fit,
  seeded 60 %, gets "Little X" / "Klein X" / "Petit-X" / "Lilla X" / "East X" / "新X" ... (ot_names.SAT) when the parent's
  name is one word of <= 16 bytes and the result is unique; one per parent.
- **Industries:** the industry names (getEntityName of the INDUSTRY entities) are read at the assignment; 2 s after
  the town renames, read again: those already "<new> <type>" count as `indEngine=` (the engine renamed them: unknown),
  the rest that still start with "<old town> " (longest town-name prefix wins) are renamed.
- **Renames:** makeEntitySetNameCmd from guiUpdate with a callback, 2 per tick, 4 waiting, 10 s timeout; skipped when the
  name changed meanwhile (`changed=`). Every step under the stage hang guard; any error / timeout ends the phase and the
  rest keep the game's names. Save-safe: plain strings; no `.names.lua` shipped.
- **Stop names:** streets have no names in TF3; a new Road Stop's group gets the next unused name of the list's
  streets.lua (findings roads.md). The game script's handleEvent queues new player Road Stops (onPostBuildProposal,
  playerInitiated, not carried over by a road upgrade; the state names mods' pattern) in the saved state (`sq`, <= 64);
  the driver (guiUpdate) names one per 0.5 s, >= 1 s after the build: the group must still have its build-time name and
  only queued stops, then the spot (height vs the town centre and a 200 m ring, water within 130 m with the town's water
  kind, tree cover, the nearest rail station, distance from the centre) -> themes station / shore / river / hill /
  valley / forest / centre / outskirts -> the first name of the best theme unused in that town: real names of the list's
  streets.lua with the theme's keys first, then the theme's own names (ot_names.STOP: en, usa, de, fr, nl, sv, nb, it,
  es, pt, ja, ja_r, ru). No theme / all used: the game's name stays. Folder from the names phase (`nd`) or, on saves
  without it, from matching the town names. Passenger stations keep the game's names (since the 2240 round, 6.3 "Round after the 2240 run": new ones beside an industry are named after it). Dev-built stops come through
  `Driver:addDevStops` (same Lua state, H.main), not the saved queue.
- **Open questions (in game, not findings yet):** what `api.util.getLanguage()` returns in a game script; whether
  `ug_require "::/names/..."` works from the game-script state (else `loadErr=`); whether the engine renames industries
  with their town (`indEngine=`); whether makeEntitySetNameCmd from guiUpdate with a callback renames a station group
  as reliably as the state mods' callback-free send from `update`; whether onPostBuildProposal's playerInitiated is set
  for proposals the dev tool sends with the player in the context; the stop position from `eo.modelInstance.transf`.

#### Forest / gaps / bridges round (2026-10-13; ROUND_FOREST_BRIEF.md R1-R7; NEXT_PHASE_BRIEF 35; tested in run `2026-10-13_2113_sqot-dev`, results HISTORY.md)

Evidence: run `2026-10-13_1945_sqot-dev` (Quick 40 years, 21 towns, tour shots), the user's notes and the user's bridge
test (docs/findings/roads.md "A low road bridge cuts a ship lane").

- **R1 forest by plot depth** (ot_forest, ot_select, ot_driver): each piece is measured over a corridor (`FO.corridor`:
  centreline + lots at 20 / 36 m each side + the band at 52 / 72 m beyond), cached per piece (`SEL.corridorOf`). Hold /
  cost pen = max(centreline, mean of the 5 lines): one side wooded to lot depth ~0.4 (dearer, not held), both sides ~0.8
  (held). `EDGE_GAIN` only for an edge street: centreline and both lots open (< 0.3) with forest just beyond one side.
  Dose points read each side to lot depth (`FO.sideCover`). The relaxed wooded pieces are capped in metres: with clearing
  budget left up to CUT_FILL of maxEdges (as before), else wooded length <= CUT_FILL x the chosen street length
  (CUT_MIN_M 60 at least; offline boxed town: 448 -> 96 wooded m per increment). Clearing budget per town and decade of
  game time (`BUDGET_HA` 2/3/5/8 ha by tier, session memory), spent by the increment's forest under lots. The grid is read
  again after RENEW_BUILDS 6 builds or RENEW_EDGES 80 edges (FOREST `renew=`). Stride bias fixed: LIGHT / DENSE stay 12 /
  36 trees/ha on the stride-corrected density, only a cell with one sampled tree reads open (was: light = max(12, 1.5 x
  max stride / 0.25 ha), 30 / 60 at stride 5). PLAN `forestLot= forestBudget=`; the empty PLAN line now has `slices=`,
  `forestHeld=`, `gapHeld=`. CHECK: the reads (caps, map reads, buildings, streets) end the tick when they took
  CHECK_SPLIT_US 12 ms, the network / lots / demand run the next tick, the check's town network gets NET_CHECK_US 15 ms
  (was 50); CHECK `slices= sliceUs=` (Redruth / Okehampton were 49-54 ms in one frame).
- **R2 forest lanes** (ot_lane, ot_proposal, ot_driver): edges of an increment wooded on the centreline and both sides
  (cover >= 0.5) whose nodes are both new and each meet another new edge (never a tip, never a joined edge, never a
  bridge), in connected runs >= 60 m, become the era's `country_old_small` / `country_new_small` (4 lanes like the small
  town street), locked, no decorations, no dose beside them; the street's other edges stay town streets (the town builds
  past). Chance 0.34 x (hug 1.5 / clear 0.5 / none 0) x the forest era factor, never a metropolis, MAX_PER_TOWN 4;
  offline: hug ~0.55, clear ~0.19 of the eligible crossings. A refused pre-check re-sends without lanes, 2 refusals turn
  them off. A country lane never counts toward the own empty budget. One-sided variant (barrier decorations): not built
  (`ONE_SIDED` false; R1's edge placement does it). Logs `FORESTLANE town= edge= edges= len= why= template=`,
  `outcome=built|refused`, PLAN `lanes=`. Dev: "Forest lane test" (LANETEST).
- **R3 gaps between towns** (ot_gap, ot_select `gapOk`, also for the tip pieces withTips adds): Voronoi half planes
  toward every town within 6 km (driver `neighbours`), gap 150-300 m seeded per pair (symmetric, at most 0.4 x half the
  distance); twins (<= 1800 m) let main / medium pieces on to the halfway line, small streets keep the gap; nothing past
  the line; within 250 m of the gap line E.closestTown must answer this town (cached per 50 m cell). No relaxation.
  PLAN `gapHeld= gaps=n:<half>-<gap>[t]`. Offline: a neighbour 900 m east: EU organic grows as much (elsewhere), NA grid
  ~half.
- **R4 empty streets**: the mod's own dead ends (locked or built this session, not country lanes) without a house for
  more than RETIRE_CHECKS 4 snapshots in a row are retired (noJoin `retired`, SNAPSHOT `noJoin=retired:n`, PLAN
  `retired=`) until a house stands on them; a town with retired dead ends plans with the tighter own empty base
  (OWN_EMPTY_TIGHT 900 m instead of 1500). Organic styles: a piece closing a loop among the increment's new streets needs a
  housed street within EMPTY_LOOP_M 90 m of its middle (arm / motif pieces exempt; PLAN `emptyLoopHeld=`). Tisbury /
  Stotfold (STYLE `form=linear`, round in the shots): the mod built only the head start; in the SIMGROW years their dev
  plans came out empty (`blocked=10-17 excluded=27-33`: the game's own streets took the plan's pieces) or held by the own
  empty budget (Stotfold `ownEmpty=1368-3440 m`) while the towns grew 6-7x, so the game's round growth won. Hitchin
  (shore strip, dens 2.5) and Rushden's bridgehead (houses=2): no change beyond the retirement.
- **R5 motifs that build** (ot_motif): a drawn or saved kind whose plan hook lays no geometry (`m.geo` nil with a
  planWhy: hill_climb flat / short, switchbacks noBend, ribbon noRoom ...) gives its slot to the next eligible kind (best
  score first, not in use, no group clash; its style hook runs first), FALLBACK_MAX 3 tries; the frame saves the new id.
  `MOTIF event=fallback from= why= to= ok= toWhy=`. MO.pick now records the eligible kinds for framed towns too (their
  `event=elig` line appears as well). The crossroads hamlet (always `waiting`: Towcester `noHamletSite`) falls back to the
  normal satellite search with its junction among the crossroads (SATELLITE `why=...:hamletFallback`). Peninsula read: a
  second, wide pass (probe 500 m, neck <= 850 m, >= 250 m long) when the narrow one finds nothing (TERRAIN `spit=...w`);
  the spine re-centres within width / 2 + 100 m.
- **R6 bridges and ships** (ot_bridge `shipCheck`, ot_engine `shipLines` / `waterLevel`, driver `shipStops`). Research
  (tealdefs, 2026-10-13; not verified in game): no navigability query (only terrain.isOnWater, the water mesh
  riverSystem.getWaterMeshEntities with depths, the line manager's engine-drawn layer), no readable ship path (a SHIP
  component has pathIndex / reserved edges, no edge list); lines: lineSystem.getLines, util.line.getLineTransportModesUnion
  (SHIP / SMALL_SHIP), LINE.stops -> station group -> station -> construction box. So the conservative test: a ship line
  stop within 200 m of the water body the crossing spans (a capped flood fill, 2500 cells of 40 m; capped with a ship
  stop within 6 km also counts) = `ship=path`: deck >= waterLevel + CLEARANCE 11 m, far street up to 240 m, approaches
  at MAX_GRADE 0.08, else no crossing (`why=shipPath:highNoFit=n`); water >= NAV_SPAN 45 m wide without ships =
  `navigable` (proxy): high deck when it fits, else low; narrower = `none`, low deck. Score penalties NAV_PEN 40 / PATH_PEN
  25 prefer narrow non-navigable stretches. BRIDGE plan `ship= shipWhy= deck= clearance=`; SHIPS debug line (lines,
  stops, vehicles, waterLevel, source=terrain|default) once per 60 s when a bridge is planned.
- **R7 industry mix**: SIMGROW (dev) grows with a per-era split (1900s 0.62 / 0.14 / 0.24 ... 1980+ 0.68 / 0.24 / 0.08)
  instead of the town's current mix (SIMGROW town `mix=era`); the game's own rebalance still caps a district past 40-50 %
  of the town (docs/findings/towns.md "District split"), so residential can't run away: an Alsager-like town (34 %
  industrial) grows 82 / 59 / 63 instead of 82 / 42 / 80. Dev "Industrial satellite probe": a separate town 0.9-1.5 km
  out (across water when it can) created with initial capacities 10 / 10 / 200, 3 growth passes, SATIND `landUse=
  indShare= onlyIndustry=`. Main mod: nothing until the probe answers. Not done (optional): dose fills kept off the
  industrial district centre.
- Nothing saved (budgets, lanes, retirements, ship reads are session memory; the frame keeps a fallback motif's id), no
  new strings, no new node kinds (lanes are new edges between new nodes with their configs as before).
- Tests: test_forest (+6 R1), test_lane (5), test_gap (5, incl. R4 empty loops), test_ships (5), test_driver (+2: CHECK
  split, retire), test_motif (+1 fallback), test_motif_point (wide spit); dev: test_runner (+3: forest lane, noLane,
  industrial satellite), test_simgrow (+1). Main 471 / dev 118 green. Expectations eased: test_forest boxed 0.45 -> 0.42
  (the open town grows ~10 % more with the empty-loop rule), test_bigform upward r90 within 2 %.
- Risks: the country-lane edge copies a town street's BASE_EDGE_STREET (a first; fallback strip + off); the CHECK split
  adds a tick of latency; ship reads (`getLineTransportModesUnion`, LINE.stops, the TERRAIN `waterLevel`) unverified;
  NAV_SPAN / CLEARANCE unmeasured; gaps may hold twin towns' small streets that grew together before.

#### Round after the names run: unique stop names, lanes ahead, forest lanes, Brentwood, Works (2026-10-13; NEXT_PHASE_BRIEF 36; tested in run `2026-10-13_2240_sqot-dev`, results HISTORY.md; follow-up 6.3 "Round after the 2240 run")

Evidence: run `2026-10-13_2113_sqot-dev` (new European map, 16 towns, SIMGROW 40 years, tour shots; s3 = Brentwood,
s8 = Henley-in-Arden), the user's notes (satellites, Haslemere around its mountain, Skegness's arms, Ellesmere Port and
its Works liked; names fit; "Brentwood could have maybe saved more forest"; Henley's "random country roads"; stop names
duplicated). Findings recorded: docs/findings/towns.md (renames / getLanguage / indEngine=0, the 10 / 10 / 200 town,
country lanes in town proposals, the game's own growth into forest) and roads.md (ship read, water level read, a high
bridge's "Place on Land").

- **Unique stop names (ot_stopname).** The 32 test stops drew from 3-7 names per theme, unique per town only: The Grove /
  Highfield Road / High Street x6. Now a stop's candidates are the list's real street names holding the theme's keys,
  the theme's stand-alone names, then generic x specific compositions ranked by relevance with a seeded jitter (rank
  groups: works / quarry / farm within 350 m, trees, the theme's features, compass, height, the own town; "toward" first
  on the outskirts: a stop past the inner part (>= 250 m, 0.35 x radius) whose bearing from the centre points within 32°
  at a town within 8 km gets "<Town> Road"), per list language (compounds de / nl / sv / nb, Romance phrases with
  gendered height adjectives, ja / ja_r concatenation, ru / ru_r gendered adjectives with Большая / Малая / Новая /
  Старая pairs, en / usa Old / New). Trees: the town's forest read now tallies species from the tree model file names
  (`shgl_oak` oak, `hzl` hazel, `brleaf_0N` / `confr_0N` spread over oak / ash / beech / elm / birch and pine / fir /
  spruce / larch, palms, ...; FOREST `species=`), else the climate's defaults; willow / alder / poplar first by the water.
  Unique against every station group name on the map (E.mapStopNames, re-read every 60 s) plus this session's; the
  outskirts / centre themes as the last resort, then the game's name. A stop the game named after its industry keeps it
  (`why=industry`); a stop without a theme now gets an outskirts name. STOPNAME `kind= gen= uniq=left/total toward= ind=
  trees= compass= high=`. Offline: 500 stops per language, 0 duplicates, 0 left with the game's name, on theme (fallback
  0-21 of 500); the run's 32 spots: 32 different names.
- **Henley-in-Arden's stray country roads: the forest lane.** `[SQOT_DEV] FORESTLANE town=68564 name=Henley-in-Arden
  edge=bk1:2:L1#3 edges=6 len=474 why=clear:p=0.17,u=0.01 template=country_old_small` then `outcome=built`, in a dev SIMGROW
  plan (gridShare 0.81): six edges of a back-row grid at the north edge, connected through the junctions (the old rule
  only asked each node to meet another new edge). Not a template, an entry, a satellite (`why=rare`) or industry streets
  (those are town templates). Now (ot_lane): one stretch of one plan line (`lineOf`: the piece key before "#", a grid
  lattice piece's row), never on block-interior lines (back rows `bk`, secondary radials `sr`, grid blocks `q`, connectors
  `conn`), chained only through nodes without a side street, a dead-end edge at either end trimmed off (it stays a town
  street), at least 2 edges and 60-400 m; FORESTLANE `check=true wooded= joined= line= lineKey= tip= short= long= runs=
  freed=` (debug) says why wooded edges made none.
- **Country lanes laid ahead (ot_lead; the user's idea).** At a demand build, a seeded 30 % of the towns with 60-1500
  buildings (map quota: a quarter of the towns, at least one; never a metropolis, superblock / ensanche, a Works town)
  lay one lane: targets toward a neighbour 1.2-6 km away, the satellite's site, the shape axis both ways, else the plan
  frame's axis; from a joinable dead end at the edge (>= 0.6 x the houses' extent, within 40° of the target) 400-1000 m
  (seeded) shortened in 50 m steps until the far end is on this town's side of every gap line, the engine's owner is this
  town, inside the map margin, dry, <= 8 %, clear of the town's streets and of fields / tracks / constructions beyond the
  snapshot, and no road runs along its far half. The proposal: the joined first edge a town street, the lane edges the
  era's country template (locked: ot_proposal's forestLane path), at the far end a hamlet T (two 60 m arms and a 50 m stub
  on, 60 %) or a ribbon (the last 30 % as a town street), unlocked so the game grows there; all or nothing (no prune,
  no halving), `fill=off`; LEADLANE `outcome=none|plan|dropped|built|refused`; the frame keeps `ld` (EV_LEAD). Offline
  driver test: `laneEdges=7 laneLen=457 endKind=hamlet endEdges=3`, BUILT `locked=7` of 11.
- **Brentwood went into the forest because the game built it.** FOREST share 0.39-0.40, hug. The mod built 105 of
  the town's 446 edges (116 -> 1917 buildings in SIMGROW's 40 years, x9.6); its later plans came out tiny or empty with
  `forestHeld=0` mostly: the game's own streets had taken the plan's pieces (`edges=0 blocked=20 excluded=15`), its own
  unhoused streets held it (`ownEmpty=600-1600 m`, 14 `why=ahead` checks), its 2 ha clearing budget went in the head start
  (1.6 -> 0.4 in four plans) and never came back (the sim's years don't move the game calendar, and the tier stayed 1),
  the open meadow east lay within the 400 m map margin (`edgeDist=960`, `edgeHeld` up to 6), the linear axis ran along its
  one road (221° / 31°). The game's development has no forest rule and took the mountain foot. Tuning (ot_forest,
  ot_driver): (1) a hug town locks its new streets that face the forest (a side's lots or the band beyond >= 0.5 cover,
  or a dead end whose street probed 80 m on runs into it): the game hangs no streets of its own off them (FOREST `lock=
  side= tip=` debug); (2) the clearing budget opens a new window per decade or at 1.5 x the buildings since the window
  opened, its total follows the current tier, and it is spent when the increment is built (a refused plan spent it twice
  before): `forestBudget=left/total:first|decade|growth`; Brentwood's run would have had 7 windows instead of 1. Relax
  spends the budget as before (the held pieces come back a step at a time, CUT_FILL). The user still wants towns to
  cover some trees: the mod's own relaxed pieces and lanes still do.
- **Forest lanes "never triggered": they did, under the dev tag.** 0 `[SQOT] FORESTLANE` lines, but 11 `[SQOT_DEV]
  FORESTLANE`: the SIMGROW plans run on the dev runner's drivers (prefix `[SQOT_DEV]`): Sandhurst (refused once for a
  Collision, then built, 2 edges), Whitehill (6), Henley-in-Arden (6, the stray grid), 4 skipped by the draw. Rare
  because hug towns (226 of 285 plans) held exactly the pieces a lane needs, and clear towns draw at 0.17. Every
  LANETEST said noLane because the test used the picked town: Ferryhill Works (no forest), Sandhurst (empty plans),
  Brentwood (no crossing). Fixes: hug towns release a held crossing as a bundle (ot_select laneBundle: a held piece next
  to the town whose line has a wooded stretch of 60-400 m followed by open land comes with the whole stretch and the
  first open piece, seeded per line through ot_lane.free, the town's quota); offline 6-7 lanes in ~150 plans of 16
  forest-band towns (before: 1). Dev "Forest lane test" dry-runs the picked town, then up to 8 towns by forest share
  (LANETEST `pick= dry= lanes= tried=`), and builds where a plan has a lane; no town needs to be picked; its forced mode
  allows single-edge lanes.
- **Works (ot_works).** The dev probe answered (SATIND indShare 0.92 / 0.93). Main mod: only on a new map (Act on New
  towns: the saved fresh flag; All towns: the game clock at load), at a demand build of a town with >= 300 buildings,
  seeded 35 %, quota one per 8 towns (1-3), one per town, never a character town or a Works town. Site: 0.8-1.5 km out,
  harbour within 350 m (E.harbours: stations under `stations/water/`) > rail station within 400 m > across water from the
  centre > open land; dry within 100 m, <= 8 %, map margin + 220 m, on this town's side of the gap lines, the engine's
  owner, >= 1300 m from other towns and nearer this one, >= 1500 m from a character town's centre, 150 m clear of streets
  / tracks / constructions / fields, a dry gentle link line from a dead end to 150 m short of it. Name in the list's
  language, unique among the town names (en "<Town> Works / Docks / Junction", usa "Port <Town> / <Town> Mills", de
  "<Town>-Werk / -Hafen", fr "<Town>-les-Forges / Port-<Town>", sv "<Town> bruk", it "<Town> Scalo", ja "<Town>港" ...).
  E.createTown (the probe's path: createTowns + initial capacities 10 / 10 / 200 + makeTownCreateCmd), the new town found
  by diffing the town list (worksTick), saved (`wk`, the parent frame's `wp`, EV_WORKS), filled once (makeTownUpdateSizeCmd
  x1); 20 s later, at the parent's next demand build, the link road: the Works town's streets (450 m) added to the job's
  network, its dead ends joinable (job.otherTownOk), the nearest dry / gentle / clear pair of dead ends joined at both
  ends, the middle the era's country template (locked); all or nothing, 3 tries. WORKS `event=none|create|created|
  refused|link|linked`. **Save-safe:** the created town is a normal town; removing the mod leaves it (and its link road:
  plain base templates). No new setting, no new strings.
- CHECK `parts=caps:..,map:..,bld:..,str:..,fin:..`: 77 of the run's 786 CHECK lines still took 15-62 ms in one slice
  (Ferryhill Works 62 ms, Brentwood 60 ms) although split over two ticks: the parts show which read is slow (next run).
- Bridges: no bridge was built in the run (Darley Dale's high deck failed with "Place on Land", findings roads.md;
  Skegness `shipPath:highNoFit=3`), so the ship line was never cut. SHIPS read the line (1 line, 3 stops, 1 ship); the
  water level read fell back to 0 (`source=default`). Not changed this round.
- Tests: test_stopname (5: 500 stops x 14 languages, specific parts, grammar, species, the run's 32 spots), test_lead (5),
  test_works (5), test_lane (+4: Henley, freed pieces, the planner's bundle, single edges), test_forest (+2: budget
  windows, forest-facing locks; the budget text), test_names (+1: map-wide unique, industry names), test_demand (+2: the
  lane ahead and the Works in the driver); dev test_runner (+1: the forest-lane auto-pick). Main 494 / dev 119.
- Risks: the bundle release lets a hug town cut through forest strips it held before (the lane has no lots; the open
  piece beyond is a town street); the lead lane's far T may stay empty for a long time (the game fills by network
  distance; the mod doesn't dose it); the Works link joins another town's dead end (a D3 join like any other, untested
  across towns); createTowns may refuse a site near fields the obstacle read missed (`WORKS event=refused`); forest
  locks reduce the game's side streets on the open side of an edge street too.

#### Round after the 2240 run: unique stop names map-wide, industry cues, housed lane ends, Works in the sim, keep-clear zones (2026-10-13; NEXT_PHASE_BRIEF 37; in game: TESTING.md "Round after the 2240 run")

Evidence: run `2026-10-13_2240_sqot-dev` (new European map, 16 towns, 12 hand-built stops, SIMGROW 40 years, shots s0
Budleigh Salterton / s9 Verwood / s15 Tickhill; results HISTORY.md) and the user's notes. Findings recorded:
docs/findings/towns.md (a lane's far town streets stay unhoused; the game's growth surrounds a farm; the industry
listing works in a game script).

- **Stop names (ot_stopname, ot_driver stopUsed / stopName).** Cause: (1) the real names of the list's streets.lua
  came first and the game hands those same names to new stops, so all 12 stops took `kind=real`; (2) the map-wide used
  set was cached for 60 s: group 110136 got "The Grove" from the game after the read and group 107957 was renamed "The
  Grove" 38 s later. Now: `used` = every station group's name read live (E.stationGroups: the names kept per group, only
  new groups, the stop's own and the queued ones read afresh, everything again every 60 s; plus the names sent and not
  applied, and the cache updated on a rename); composed names of every theme first, the stand-alone and real names only
  after them (each once, while unused on the map); no fallback themes: nothing unique and fitting -> the game's name
  stays (`why=noUnique`, debug). Richer composer, per list language (14): old field / farm names (`fields`, ~15-22),
  landmarks (`marks`, ~11-15), lake words for a lake shore (`site.lake` from the town's water body), the industry
  theme, the town's own name on every theme (later), Old / New / Little / Great (en), Old / New / Little (usa).
  Offline: 500 stops per language 0 duplicates, real / solo 0; 300 stops on one map mixed with game-named streets.lua
  stops (en, de, fr, ja, ru): 0 duplicates, 0 left with the game's name, ~1.6 ms per stop (plain Lua).
- **Industry cue.** A stop within IND_R 350 m of an industry gets the `industry` theme first (SN.themesFor): the
  industry's own short name (its game name minus the longest town-name prefix, SN.indShort: "Crop Farm Gate", en / usa
  / ja / ja_r only, the other grammars can't take an unknown name's gender) then its kind's words (SN.indKind, now works
  / quarry / mine / farm / mill / brewery / timber; steel mills are works) with the theme's generics ("Works Road",
  "Quarry Lane", "Farm Lane", "Brewery Lane", "Foundry Street", "Werkstrasse", "Rue de l'Usine", "Заводская улица"),
  then compass and own-town names. New **player stations** (rail / harbour / bus-truck station constructions, collected
  like the state names mods do: brand-new constructions only, no removal in the proposal; ot_saved `sq` entries carry
  `k`): renamed only when an industry lies within STATION_IND_R 400 m and nearer than the town centre: "<Town> <Works /
  Quarry / Colliery / Farm / Mills / Brewery / Sawmills>" by kind, a harbour station "<Town> Docks" first, else
  "<Industry> Halt" (SN.STATION, 14 languages), unique like the stops; else debug `why=noIndustry|nearerTown`. Same
  rules as stops: new player builds, never a renamed group, the setting "Town and stop names". Station positions are
  the construction's bounding box centre (unverified for stations).
- **Long empty offshoots.** Which builds: only 2 lanes ahead were built (Tickhill ribbon end 800 m out, Verwood hamlet
  680 m out, both through the dev build round); the shots show their far town streets without houses after 40 years
  (findings towns.md: houses fill by network distance; a street past a lots-less country lane waits behind every nearer
  lot). The other 16 towns' LEADLANE said `why=rare`; hill_road / ribbon_village / entries / arms were not the cause
  in the logs (their streets are within the housed front / lead limits). Now (ot_lead, ot_driver): the ribbon end at
  most RIBBON_MAX_M 120 m (was 30 % of the lane, ~130-300 m); every end street must hang on the lane (LD.endJoined:
  one network with the joined first edge, else `outcome=dropped why=endLoose`; LEADLANE `endJoined=`); the far end gets
  a dose at the build (LD.endFillPoints: one DevelopAt point beside each end street, FILL_POINTS at most; job.fillPts,
  fillKind `why=leadEnd` whatever the town's shape) so its first houses start there. The end streets stay plain unlocked
  town streets of the town's template. **Arms** (ot_select ARM_WAIT): in towns of 3+ arms (cross, fingers) an arm not
  yet housed beyond the town's housed radius (+ ARM_WAIT_M) starts out only ARM_WAIT_F 0.5 x the lead while another arm
  runs more than max(ARM_WAIT_M 150 m, lead + half a block) of unhoused town street ahead (country roads and lanes
  don't count); linear / ridge / shore towns' two arms are exempt (their elongation test failed with the rule).
  PLAN `armWait=`.
- **Works never started: the dev build round's drivers.** The SIMGROW build round runs the main mod's jobs on pool
  drivers (otd_runner poolDriver) that share the main driver's town state but were made without `newMap` (and logged
  under `[SQOT_DEV]`: `owner.prefix or R.PREFIX` fell through for the main driver's nil prefix). Every WORKS said
  `notNewMap` and set `worksTries` in the shared state, so the main driver's own 27 demand builds skipped the Works
  without a line. Now poolDriver copies `newMap` / `listDir` from the owner or the main driver (ensureConfig for the dev
  driver too) and uses the owner's prefix: the build round logs `[SQOT]`. Normal play (no dev mod) was not affected.
- **Industries hemmed in: keep-clear zones (ot_industry ZONE).** Research (game files, not verified in game; the
  tf3-docs-researcher's report): processing industries never grow (one layout, `currentLevel = 1`); field industries
  (farms, livestock / cotton / rubber, forestry, mines, pits, quarries, oil wells) grow one field / pit stage at a
  time into fixed slots around the construction origin (`fieldConfig.fields`, maxLevel by "Industry Size"), tried every
  half game year (staggered), only while the rating (production x shipped share) is >= 0.25 (growth chance
  invLerp(rating, 0.25, 0.75)), via makeIndustryExtendProposal; a slot whose field collides (houses, streets,
  constructions; also slope) is skipped silently (`industryFailedExtensions`, a red area in the industry window
  only), retried later. Max footprints (rotation free, farthest corner from the origin): farm ~382 m (level 1 ~108),
  livestock 366, cotton 362, rubber 359, forestry 331, iron ore 295, clay pit 278, coal mine 275, oil well ~272, sand pit
  250, quarry 220; plants 85-141 m (half diagonals). Budleigh Salterton: `ind=0` on all 46 checks (the farm lay beyond
  SEARCH_R 1500 m from the centre; the town reached r = 1854 m), the mod built 195 of its 919 edges, the game the rest
  and the enclosure. Now: the industry read reaches max(1500, the town's radius + ZONE_REACH 900) (re-done when the
  radius moves 250 m); every industry gets a zone = max footprint + ZONE_MARGIN 40 m, shrunk to at least ZONE_CORE_M
  150 m short of the town centre (never below level 1 + margin); ot_select holds every piece whose street or lots
  (ZONE_LOT 30 m) enter a zone, motif pieces too, no relaxation (PLAN `zoneHeld= zones=`); Driver:send refuses any
  other plan that would (satellite, lane ahead, Works link, bridge, frame: `REFUSED why=industryZone`, its pieces
  excluded); dose points in a zone are dropped (`FILL zoneDropped=`); new streets within ZONE_LOCK_M 80 m of a zone are
  locked (D.zoneLock, also for a metropolis; PLAN `zoneLock=`). The game's own streets can still enter (no API keeps
  them out; the locks stop it branching from ours). Offline: four steel works boxing a town in: EU organic 75 / 107
  edges, NA grid 25 / 72 (the soft buffer alone: 96 / 51), 0 streets in a zone. Not done: reading the industry's real
  level / maxLevel (INDUSTRY component `level`, `maxLevel`) to drop zones of industries at their max, the real
  placement transform (zones are discs around the bounding-box centre).
- **Kept:** forest edges ("Verwood seemed very successful").
- Nothing new saved except the stop queue's `k`; no new settings or translatable strings (stop / station names are
  per-list-language data like before). Description Features / Changelog updated.
- Tests: test_stopname (+3: 300 mixed stops, the industry theme in 14 languages, stations), test_names (+2: the live
  used set, the station rename in the driver), test_industry (+1 zones; the boxed-in test split into soft buffer /
  zones), test_lead (+1 far end), test_demand (lane ahead: endJoined, the leadEnd dose), test_reach (+1 arm wait); dev
  test_simgrow (+1 pool driver gate / prefix). Main 502 / dev 120.
- Risks: a town that started right beside a farm gets less room (the zone shrinks only to 150 m short of its centre);
  the station rename reads stations from the proposal's result entities (unverified in this mod; the state names mods
  do it); lake detection depends on the town's water read; the far-end dose resets initial capacities like any dose
  (restored as before).

#### Round after the 2355 run: districts, Works by a factory, coastal huggers, bridges, squeezed towns, street-aware stop names, density (2026-10-14; NEXT_PHASE_BRIEF 38; in game: TESTING.md "Round after the 2355 run")

Evidence: run `2026-10-13_2355_sqot` (HISTORY.md), the vanilla comparison BASELINE_VANILLA.md, the user's notes.
- **District towns** (`ot_district`, driver `districtDecide` / `devDistrict`): a grown town on a new map founds 1-2
  residential towns (`makeTownCreateCmd`, caps 200 / 30 / 10) on a site feature 0.6-1.5 km out (upper, shore, across,
  lead, valley, clearing; a plain site is none), named per list language (sometimes an unused real name the names phase
  reserved, `ot_names.reserve`). The Works state machine is shared (`offshootCreated`, `worksLinkDecide`,
  `worksPlanStage`: records in `s.works` and `s.districts`). Saved `dk` = { {t, p} }, the parent frame's `dp` (EV_WORKS
  kind=district). The parent's arms reach `DISTRICT_KA` 0.75 (style key `:dist`, STYLE `districtKa=`), it lays no lane
  ahead, and the R3 gap between parent and offshoot is waived within `ot_gap.WAIVE_W` 160 m of the line between their
  centres (PLAN `gaps=... waive=n`; the engine's ownership still holds). Never by a character town's core, outside
  industry zones, never for a character or mod-made town. Dev: OT Dev "Found a district" (DISTRICTDEV line).
- **Joining mid-edge** is not supported by `ot_plan` / `ot_proposal` (only dead ends with a node config are joined:
  the crash rule), so the linker tries many dead-end pairs instead.
- **Robust link** (`ot_link`): up to 24 pairs x 5 routes (the seeded bend, waypoint detours +-0.22 / 0.42 x the
  length, at most 420 m off), cheapest tests first (back-check `BACK_DEG` 60: the planner's min angle at the joint was
  the likely `notJoined`; crossings / clearance; obstacles beyond the snapshot with 35 m untested at each end; zones;
  wet; grade), up to 4 routes planned in turn. WORKS / DISTRICT link lines: `tries= pair= route= detour= pairs=
  routes= fails=`.
- **Works by a factory** (`ot_works.industrySite`): an industry 500-3000 m from the centre -> the site on the line
  to it at 2/3 (0.55-0.73 tried), nudged sideways up to 360 m, outside its zone and 250 m of it; a ring harbour /
  station site only when nearer. Named by the industry's kind ("<Town> Quarry / Colliery / Mills / Maltings /
  Sawmills / Grange", de "-Steinbruch / -Zeche / -Mühle ...", 14 classifiers). WORKS `industry=<kind>:<m> at= nudge=
  industries=`.
- **Coastal huggers** (`ot_map.coastal`, `ot_form.COASTAL`, driver `coastalOf`): the 1-2 towns (2 from 10 towns) with
  the most coastline on 300 / 600 / 900 m rings (score >= 0.45; characters and mod-made towns left out) take the strong
  shore form (kaMul 1.6, kbMul 0.75, depth cap 150-230 m, the waterfront street always); the frame saves `cs`.
  COASTAL lines (`pick=` once, per town `applied=`).
- **Bridges** (`ot_bridge`): rays also from 4 origins 450 m round the centre (narrow lake arms, river bends); the far
  street and cross street dry all along (one guess for Darley Dale's "Place on Land": a high deck's far street ran
  beyond the checked dry margin); up to 6 candidates best first, each tested in the driver against the obstacles
  beyond the snapshot (`skipped=`); a refused key is skipped and the next tried at a later build (BRIDGE_TRIES 3,
  `try=`), a "Construction not possible" without collisions tries the next bridge type (ot_engine.bridgeType skip).
  Research: the only bridge rule the scripting API exposes is `townConnectionMaxBridgeLength` (250 m,
  base/content/base/mod.script.tl:113: map-generator connections between towns); nothing on how the game's own town
  growth lays a bridge (Gainsborough's vanilla bridge: generator or growth unknown).
- **Squeezed towns** (`ot_site` `squeeze`, `ot_form.SQUEEZE_K`): steep 95th-percentile slope, water and forest share
  (two constraints at least, else half), above SQUEEZE_MIN 0.3 the form weights lean to clustered (x2 at 1) and away
  from sprawling / wide. STYLE `squeeze=`. No block scaling (the plan must stay the same after a reload).
- **Stop names** (`ot_stopname`): street sections (`M.section`: the chain through the stop's edge, < 35 deg at each
  node, up to 1.2 km each way, on the streets read 700 m round the stop); the first named stop on a section is its
  base (saved `sb`, EV_STOPBASE, at most 300), later stops within 1.2 km on it take variants (`M.variants`: compass,
  Upper / Lower >= 8 m, Old / New >= 100 m nearer / farther from the centre, far end >= 400 m, landmark, combinations;
  per classifier); 28-character cap (UTF-8), town names over 12 characters give their first word, clumsy pairs (water
  edge / hill / valley words twice) left out, more parts per theme in 10 classifiers. STOPNAME `section= base=`,
  `kind=variant:<how>`.
- **Act on: Off** (mod.script.lua): no preRunFn write (PRERUN line); the driver was already off (`INIT on=false`, no
  names phase). The "Vanilla town street angles" tooltip now says "not when Act on is Off" (13 languages).
- **Density** (BASELINE_VANILLA.md: 3.0 vs 4.6 persons per building, 92 vs 63 edges per 1000 persons, 54 % lots free):
  `ot_assess.DENSIFY` 1.2 (demand counted at 1.2 x the town's persons per metre), the free-lot brake (FREE_SHARE 0.4 ->
  FREE_MIN 0.35 at FREE_FULL 0.65; CHECK `freeK= pb=`), the upward dose for sparse towns (`ot_upward` SPARSE: 400+
  buildings under 4.0 persons per building, cut 0.2; UPWARD `why=sparse`). The offline growth model hands the left-out
  frontage to the game's own streets (test_demand: EU mod share 0.29 vs 0.35 before); the real run's mod frontage came
  on top of the game's, so the in-game effect has to be measured (ALLTOWN `pb=`).
- **Lanes ahead** (`ot_lead`): 250-600 m (was 400-1000), curved through a seeded waypoint 8-16 % off the line, 40 %
  hamlet ends (was 60 %), none for a town with a district.
- **Measurement** (dev): ALLTOWN `streetLen= emptyLen= emptyEdges= deadEnds= pb= freeLots=` (also with the main mod
  off: the dev driver measures); SIMGROW year `frames= gapHeld=` (the main driver's counts).
- Tests: main 517 / dev 120 (test_district new; test_ships, test_stopname, test_demand extended).
- Risks: creating several towns per map (Works + districts, quota 1 per 4 towns, max 6) is unverified for the game's
  town ownership between parent and district; the variant names assume streets carry no readable names (no cross-street
  names); the coastal ranking reads ~72 water samples per town once per town count (COASTAL `us=`).

##### Addendum after run `2026-10-14_0119_sqot` (2026-10-14; NEXT_PHASE_BRIEF 38 addendum; in game: TESTING.md "Addendum after the 0119 run")

- **Created-town race** (cause): every parent took "a town not in my list when I sent" as its new town, picking the last
  such id. Six creates went out within ~2 s from different parents (no map-wide limit, only one per build), all
  built, and the ids came in no particular order, so Penkridge Sands (128852) was claimed by Penkridge and Winchcombe,
  Heywood Works (147514) by Heywood, Ringwood, Tickhill and Windermere. Winchcombe Heath, Ringwood Bay, Tickhill-on-Sea
  and Windermere Sands were built but claimed by nobody (ordinary towns). Winchcombe's and the three districts' links
  then ran to the wrong town (`why=far fails=far:24`). The save kept the first event per town (applyWorks is
  idempotent): `dk` 147514 -> Ringwood (wrong, Ringwood `dp` 1), Heywood Works missing from `wk` (Heywood without `wp`).
- **Fix:** one town creation in flight map-wide (`createInFlight`, Works and districts together, let go after 2x
  WORKS_CREATE_TIMEOUT_S); the created town is the one named as we named it within `ot_works.IDENT_R` 600 m of the site
  (`ot_works.identify`: name with spaces / underscores ignored, nearest when two, position optional), never one another
  parent claimed; none within WORKS_CREATE_TIMEOUT_S -> `created ... why=unidentified` (once; never claimed, no new
  try this session). DISTRICT / WORKS `created ... how=name+pos cands=`. Saved claims now carry the site (`dk` x / y,
  new `wm` = { t, p, x, y } for Works).
- **Load check** (`Driver:offshootCheck`, once per session; `ot_saved.offshootCheck`): a `dk` / `wk` entry whose town
  is gone, more than OFFSHOOT_SITE_R 900 m from its saved site, or (older entries) more than OFFSHOOT_MAX_D 2.6 km from
  its parent's centre is dropped (EV_WORKS kind=drop: out of `dk` / `wk` / `wm`, the parent's `dp` lowered / `wp`
  cleared; a filtered view until it lands). Then towns named like a district / Works of another town (`DT.orphanOf`)
  and claimed by none are adopted by that town on a new map when within 2.6 km and it has room (no Works yet / fewer
  than 2 districts), else logged as orphans. OFFSHOOT `event=drop|adopt|orphan` lines. On the 0119 save: drop 147514
  from Ringwood, adopt it as Heywood's Works, adopt Winchcombe Heath / Ringwood Bay / Tickhill-on-Sea / Windermere
  Sands as their parents' districts (test_demand "load check in the driver").
- **Forest:** the clearing kind is gone (a new town's houses and streets come from the game's own growth, which ignores
  forest: Winchcombe Heath ate the forest the user liked). Every Works / district site needs open land: mean cover
  (the parent's tree grid, `FO.coverAt`, unknown outside it) within `ot_works.FOREST_R` 450 m (centre + rings 150 /
  300 / 450 m) at most FOREST_MAX 0.2, else rejected (`rejects=forest:n`, `why=forest` when no site was left); open land
  with forest just beyond (ring at 600 m >= 0.35) scores FOREST_EDGE_BONUS better. A Works / district town hugs the
  forest from its first build (`ot_forest.forStyle` `style.offshoot`: facing streets locked, the corridor cost, the
  clearing budget). DISTRICT / WORKS create `forest=<share>[+edge] rejects=`.
- **Penkridge Sands' empty streets** (coordinator's question): not ours. The driver never ran a job for 128852 (no
  SNAPSHOT / PLAN / SEND), and the dev SIMGROW grew only the 16 starting towns. Its CHECK `edges` 41 -> 78 counted the
  parent's streets inside its 550 m snapshot circle: Penkridge (600 m away, gap waived along the link) grew from 109
  to 868 buildings and r 227 -> 587 m in the sim, mostly by the game's own growth; `ownEdges` 14 = locked edges there
  (the link and Penkridge's lanes). Still, a Works / district town below OFFSHOOT_HOLD_B 120 buildings now gets no mod
  streets of its own (assess; OFFSHOOT `event=hold`, once per verdict and street count since 6.3 "Held towns"): it
  grows when served by transport.
- **"Satellite towns" setting** (`satellite_towns`: On / Residential only / Industrial only / Off; 13 languages): Off
  founds no district or Works (the dev "Found a district" neither: `why=setting`); towns founded already stay. The
  satellite villages (streets of the parent, ot_satellite) are not part of it: they are the parent's own streets.
- **Names:** every kind has more forms (en Works: Works, Ironworks, Foundry, Mills, Forge, Brickworks, Gasworks, Yard,
  Depot, Tannery, Sawmill; Trading / Industrial Estate from 1950, Business Park from 1980; harbour Docks, Wharf, Quay,
  Port X, Harbour; rail Junction, Sidings, Yard, Depot; a plain site HILL_DZ 25 m above the centre: "hill" = Pit,
  Colliery, Quarry; the same per list language), and a name takes its kind's form used least among the map's town
  names (`ot_works.formCount`, stateless), ties by list order (districts: the seeded rotation). No water word twice
  (`ot_works.hasWater`: Port, Sea, Bay, Mouth, Haven, Quay, Sands, Mere, Water ... per language, ASCII endings, CJK
  characters): "Ellesmere Port-on-Sea" and "Port Ellesmere Port" are out; a water-named parent's shore district takes
  the lane-end forms ("X End") first.
- Tests: main 523 / dev 120 (test_district forest / names / saved check; test_demand created towns, load check,
  setting; test_works names).

##### Round after the same-seed comparison (2026-10-14; NEXT_PHASE_BRIEF 39; in game: TESTING.md "Angle split run", "Fresh run after the comparison round")

Evidence: BASELINE_VANILLA.md "Same-seed comparison 2026-10-14" (session `2026-10-14_0119_sqot`): the same people as
vanilla in 2.4x the buildings (2.9 vs 6.4 persons per building), 2x the street per person, 58 vs 52 % of lots free, long
straight empty lanes; the mod's +15 % people came from the dose fill's capacity boost.
- **Phase 1, no capacity boost** (`ot_driver` FILL_EXTRA 0.15 -> 0, `ot_metro` FILL_EXTRA 0.25 -> 0, POLY_EXTRA 0.4 -> 0;
  `D.capsBoost()`): every fill (dose, metropolis, polycentric, upward) puts the initial capacities back exactly to their
  pre-fill values; FILL_CAP only applies while a boost is allowed (an old save's raised town doses again, its raised
  capacities stay, never lowered). INIT and FILL restore `capsBoost=0`. Other capacity writers checked: the dev SIMGROW
  (the test driver's own target), the "Starting town size" setting (explicit, default Game size), the testing GROW
  param (off by default), Works / district creation (200 / 30 / 10 per new town: more towns, not more per town).
- **Phase 2, density.** (a) The demand brake (`ot_assess`): freeK from the town's free-lot share around FREE_AIM 0.5
  (1 up to 0.45, FREE_MIN 0.12 at 0.6) x pbK = persons per built lot / PB_AIM 4.5 (at least 0.5), at least K_MIN 0.06;
  no room build (`why=free`) above 55 % free. The run's typical town (58 % free, 2.9 pb) now asks 0.15 of its demand
  (0.53 before). CHECK `pbK= demK=`. (b) UPWARD: of its 25 logged skips 22 were `surge` (SIMGROW's Fast fill), and its
  3 doses changed nothing (findings towns.md "A new map's starting towns at a 35° street angle"): no surge rule for
  upward (UP.SURGE_BLOCKS false), sparse from 250 buildings under 4.5. (c) **Level weights** (`LEVELS`, the lever that
  did change building size in the Stress Test, findings towns.md): on a new map, a town of 150+ buildings under UP.PB_AIM
  gets `makeTownCustomDistributionWeightsCmd` weights r^(level-1) / r^3, r = 1 + 0.6 k, k = (4.5 - pb) / 2 in quarter
  steps (k 1 at 2.5 or less: 0.244 / 0.391 / 0.625 / 1, all three land uses); re-sent when k changes (at most every
  300 s per town), cleared to the game's default at 5.5; a town whose weights the mod did not set (a player's) is never
  touched; saved `lw` (EV_LEVELS) so a reload knows its own. Town-wide and saved with the town: they stay when the mod is
  removed (description "Adding and removing"). LEVELS line `action=set|clear why= pb= k= was= weights=
  lvl=a:<actual shares>,u:<unweighted>,w:<weighted>,c:<custom>`. Target: ALLTOWN `pb=` >= ~4.5 after 40 years.
  Note: the start gap is partly the angle: at 35° the generator's own towns had 29 % more buildings for the same people
  before any script street (findings towns.md).
- **Phase 3, straight empty lanes.** The four in the shots (Ellesmere S, Winchcombe W, Windermere SW, Henley-in-Arden
  S) were satellite links (`SATELLITE kind=seed link=567-1233`; no lane ahead ran: every LEADLANE `why=rare`, and those
  towns' district links failed). The link is now `SAT.curvedLink`: a seeded bow plus a wiggle every 150 m, 4 variants,
  the gentlest grade along the terrain, no straight run over 150 m (`G.maxStraightRun`, 4 deg; 30 seeds x 250-1250 m:
  135 m at most); planned `curved` and marked a locked country lane (`ot_lead.mark`: no lots, so no empty town street),
  its first edge at the town's dead end a town street; the core's streets dosed at the seed build (`why=leadEnd`);
  RING_D 650-1200 (was 800-1500), SAT_GAP 350, MIN_LINK 400, MAX_LINK 900. SATELLITE `laneEdges= laneLen= straight=`.
  Lanes ahead and Works / district links are planned `curved` too. A **straight-run guard** in every normal plan
  (`CK.straightRuns` + `PL.dropEdges`): a chain of new straight town-street edges (no country lane, no bridge), straight
  on at each new node (< 6 deg, also across a junction), every midpoint more than 60 m from a building, loses its part
  beyond 250 m from its town end, with whatever hung only on it; PLAN `straight=<longest m>/<edges dropped>`.
- **Phase 4, the two levers.** "Vanilla town street angles: Game default" writes nothing (`ot_angles.angleFor` nil;
  the driver never reads the angle), so mod growth at 0° is that setting alone; TESTING.md "Angle split run".
- **Phase 5, measurement.** Dev ALLTOWN `ind=<in town>/<enclosed>[:files]` (`IND.enclosure`: houses or town streets
  on 3+ of 4 sides within the industry's keep-clear radius) and `lvl=` (actual / unweighted / weighted residential level
  shares, custom weights), both also with the main mod off; the Simulate tour waits for the main driver's town creation
  (`SIMGROW tour wait=create`, then `wait=done why=created|timeout`: 10 s after it came back, 150 s at most);
  `compare/build_compare.py` + `compare/template.html` rebuild a comparison folder for any two loads (TESTING.md).
- Tests: main 529 / dev 120. Loosened (each noted in its test): test_demand "old room trigger" open >= 30 -> open + free;
  "growth demand (frontage)" EU minBuilds 3 -> 1, share 0.25 -> 0.10; "stalled town" ahead >= 10 -> ahead + free; the
  growth model runs with PB_AIM = its 2 persons per lot (pbK 1; pbK tested alone); test_satellite distance 0.8-1.5 ->
  0.65-1.2 km, link edges 6 -> 4; test_driver fill cap / restore re-based on the exact restore.
- Risks: the level weights are unverified in game (whether natural growth follows them, era limits on level 3-4
  buildings, how `levelToCapacityDistributionWeights` reads when unset: a read error means no weights, `noRead`); the
  brake may leave shaped towns' arms short where lots stay free (form); the straight-run guard drops pieces the master
  plan keeps proposing (logged per plan, not excluded).

##### Round after the 0302 run (2026-10-14; NEXT_PHASE_BRIEF 40; in game: TESTING.md "Retune run after the 0302 run")

Evidence: BASELINE_VANILLA.md "Density-round run 2026-10-14 0302" (session `2026-10-14_0302_sqot-sqrl` load 2, the
comparison seed; page `compare/2026-10-14_U8Qxgisp4I/`, three runs). The brake held 235 of 279 CHECKs (`why=free`): the
mod built 122 demand edges in 20 builds (0119: 1032 in 170), 11 % of the edges (24 %); the towns came out vanilla-dense
(pb 6.33 vs 6.37, the same 41963 people) but round and alike (spread 1.13, one town >= 1.3); 3 satellites, 0 districts,
0 Works (8 / 9 / 3); LEVELS on all 16 towns in their first years, no level 3-4 building anywhere (era A, findings
towns.md). The user: "towns branch out a lot early on, and in later years start building up, but not before"; "I
didn't see any satellite villages".
- **Maturity** (`ot_assess.maturity`, MAT_LO 1800 / MAT_HI 3600 persons, `caps.actual`): 0 young .. 1 grown, linear.
  The brake is `demK = 1 - mat x (1 - max(K_MIN, freeK x pbK))`: a young town asks its whole demand (as before the
  density round), a grown one the full brake; the free-lot hold (`why=free`) starts at FREE_AIM + FREE_ROOM +
  (1 - mat) x YOUNG_ROOM (0.5), i.e. never for a young town. CHECK `mat=`. Why persons and not buildings or years: the
  brake itself changes the building count (the 0119 towns had 2.4x the buildings of 0302's for the same people), so a
  building gate would feed back (braked town, fewer buildings, younger, unbraked ...); the game's target sets the
  persons, which the mod can't move since `capsBoost=0`; all of a map's starting towns are the same age, so age can't
  tell them apart, and the dev sim's years don't move the calendar. 1800 persons ~ 600 of a young town's small houses
  (0119: 3 persons per building), the user's "under ~600 buildings"; at 3600 a town is past the 0302 run's biggest. In
  the 40 simulated years the five biggest towns (3400-4000 persons in 0302) mature fully, the middle ones half.
- **pbK per building** (`A.demand(..., buildings)`): it took persons per built lot (Heywood 162 buildings on 387 lots:
  pbK 0.67 at 7.2 persons per building), so even a vanilla-dense town asked x0.6. Without `buildings` (old callers,
  tests) per lot as before.
- **FREE_AIM 0.5 -> 0.55, band 0.5-0.7** (FREE_BAND_HI 0.1 -> 0.15): the game's own towns at the 35° angle keep ~60 %
  free (findings towns.md); the old aim held every town at FREE_MIN. At 60 % freeK is now 0.56.
- **LEVELS for grown towns only** (`ot_upward` LV_MAT 0.5): no weights below half maturity (`skip=young`), the strength
  `k = levelK(pb) x mat` (quarter steps), so a town gets them late and gradually; the clear rule first (an old save's
  weights still clear at pb 5.5). Town-wide only: the API has no core-local weights, the centre-first part stays the
  upward dose's. Before 1950 the weights can only tilt level 1 -> 2 (era A, findings towns.md); from 1950 they reach
  level 3, from 1990 level 4. LEVELS `mat=`.
- **Offshoot turns and size** (`ot_driver` OFFSHOOT_TURN / OFFSHOOT_TURN_S 240 / OFFSHOOT_PB 4): the satellite, Works
  and district gates read `D.offshootSize` = max(buildings, persons / 4) (300 buildings ~ 1200 persons: a vanilla-dense
  town of 1200 persons has ~190 buildings), and a town that needs no streets gets an **offshoot turn** while one of them
  is open (`Driver:offshootTurnDue`: new map, not itself an offshoot, the satellite not yet decided or a quota case, a
  Works / district under its quota and tries, or a link waiting; at most every 240 s per town): the snapshot, the three
  decisions and a waiting link, nothing else (no lead lane, no bridge, no town streets; `offshoot:noPlan` finishes as
  room). Satellites still grow only with demand builds. OFFSHOOT `event=turn for=satellite|works|district|link`;
  BUILT `trigger=offshoot` for a satellite seed or a link.
- **Measurement, offline** (test_demand "maturity", the frontage model with the real PB_AIM and an upgrade model: under
  62 % free lots the developer puts half the missing capacity into the built lots): mod share of new edges, young phase
  (< 1800 persons) / grown (> 3600), 3 seeds: no brake (0119) 48 % / 32 %, pb at the end 4.31; brake from the start
  (0302) 30 % / 56 %, 4.29; maturity 48 % / 25 %, **4.38**. The young phase is exact (demK 1); the grown phase of this
  model is path-dependent (the sign flips at other open levels), so it is directional only; the in-game check is
  TESTING.md "Retune run after the 0302 run". Offshoot turns: test_demand "offshoot turns" (a room-only town of 260
  buildings seeds its satellite on a turn, `trigger=offshoot`).
- **Comparison page**: `compare/build_compare.py` keeps a runs list in data.json (`version: 2`): `--add <session>:<load>
  --label ... --dir ...` adds a run to an existing page, `--rebuild` re-reads every run from its log, `--relabel id=...`;
  the template picks any two runs as A / B (side by side, slider, the ratio column) or shows all runs in a row
  (`#view=all&town=08&a=<run id>` links); run rows: mod-built edges by trigger, CHECK outcomes, offshoots, LEVELS.
- Tests: main 532 / dev 120. Changed (each noted in its test): test_demand "demand ledger" runs its brake checks with
  the town made mature (MAT_LO = MAT_HI = 0) and checks the young case; freeK(0.58) < 0.3 -> < 0.7 (the new aim; the
  formula check follows the constants); the `why=free` check at 65 % free (was 60 %, now the boundary); "level weights in
  the driver" made mature, plus a young case. Not loosened: "growth demand (frontage)" (EU share back at 0.51; its
  round-39 thresholds stay).
- Risks: the young phase brings the 0119 frontage back for towns under 1800 persons (more street per person early, as
  the user asked); a town that never reaches 1800 persons never brakes; the offshoot turns add a snapshot per open town
  every 240 s at most (the satellite / Works / district searches as before); the four-biggest-towns weight values are
  unexplained (findings towns.md).

##### Deep forest towns (2026-10-14; NEXT_PHASE_BRIEF 43; in game: TESTING.md "Deep forest towns")

User: "push some towns that are in particularly dense forested areas to lock more often around trees, to really try to
make them winding, wooded, secluded towns." Liked before: Verwood and Dewsbury (fingers between forest patches, woods
kept). A fourth forest mode, **deep**, beside hug / clear / none (ot_forest, ot_select, ot_grow_organic, ot_style,
ot_lane, ot_saved, ot_driver; ot_upward / ot_works / ot_district gates).

- **Who** (`FO.deepPick`): the forest share of the growth ring 150-900 m (`ringShare`: the town's own cleared core left
  out) at least DEEP_SHARE 0.45; a seeded draw (`rng.unit(seed, "forestDeep")`) against DEEP_P 0.75 x style (EU organic
  1, MED hill 0.9, Nordic 0.9, EU extension 0.5, every other style 0) x tier (1 / 0.85 / 0.35 / 0: never tier 4) x era
  (1 up to 1960, 0.45 from 2010; §59, was 1930 / 1990 / 0.35; `FO.deepChance`) x character 1.3; never a metropolis or a Works / district town; at most DEEP_MAX 3 per
  map (the saved frames' `fd` + this session's picks). Offline on a deep-forest fixture (ring share 0.75): EU organic
  1900 tier 1 0.76, tier 2 0.64, tier 3 0.27, 1995 0.23, 1960 0.44 / character 0.56, Nordic 0.57. A half-wooded town
  (ring 0.41) stays a hug candidate. Picked in `Driver:styleFor` (main style mode, before the town's first frame): a
  deep town's style is resolved again with `inputs.deep`. **Saved:** the frame's `fd = 1` (SV.frameParam / applyFrame /
  normalize / frame().deep); a framed town keeps what its frame says (`fd`: deep whatever the draw, the quota or the
  tree share say later; a frame without `fd`, every town built before this round included: never deep). FOREST
  `mode=deep why=ring=..,p=..,u=..|saved|force share= ring= dense= count=` (always logged; a not-deep reason is debug).
- **Winding geometry** (`FO.deepStyle`, in ot_style.resolve before shape / form / greens / motifs read the blocks; only
  the existing knobs, each inside the grower's own radius checks): curve >= 35 deg, jitter >= 20, contour >= 0.8, blocks
  x 0.8 / x 0.85 (never under MIN_BLOCK, 44 m since 2026-10-18), sd >= 0.35, no outer zone (organic all the way out). Organic grower:
  gridness <= 0.15, spoke wobble wavelength `curveWave` 110 m (200), `spokeRadius` 80 m (90; = LINE_RADIUS, the planner's
  edge check is 70 m), ring spacing x 0.8 (>= 150 m), and `wiggle` { amp 7, wave 90 }: secondary radials and cross lanes
  of 50 m or more become bows (ot_grow_organic.wiggle: A sin(pi m s / L), m = round(L / 90) half waves, A <= 0.9 (L / m
  pi)^2 / LINE_RADIUS, discrete radius checked, else the old line). Nordic: cluster green >= 0.45, bow >= 0.18. Radius
  not lowered below LINE_RADIUS (the town templates' 44 m and the planner's 70 m stay the limit; ot_check unchanged).
- **Planner** (`FO.k`: the deep value of a constant, else the hug one): COST_K 3.2 (2.2), EDGE_GAIN 0.35 (0.2), HOLD_PEN
  0.38 (0.45: one side wooded to lot depth already waits), HOLD_STEP 0.12, CUT_FILL 0.25 (0.5), CUT_MIN_M 120 (60: about
  one wooded piece per increment, so a town deep in the woods creeps on; offline driver town wholly in forest: 1 edge /
  91 m per plan, with 80 m it planned nothing). **Groves** (`FO.groveCells`: 4-connected forest patches of at most
  GROVE_CELLS 16 cells = 4 ha, not touching the grid border; `inGrove`): a piece crossing one inside the frame
  (max(150, FRAME_F 1.25 x the houses' extent), `fo.frameR` from the driver) never comes, whatever the relaxation (a lane
  through it still may): green islands the streets wrap around (PLAN `groveHeld=`). The surrounding forest is no grove: a
  frame-wide ban boxed the offline driver town in (no plan at all).
- **Clearing budget**: a quarter of the hug total per window (BUDGET_F 0.25: 0.5 / 0.75 / 1.25 / 2 ha by tier), and a
  held (wooded) piece's lots spend 1.5 x their hectares (`FO.lotSpend`, also ot_select's budget check).
- **Locks** (`FO.facesForest`, deep): besides the hug rule (a side's lots or the band beyond >= 0.5) any forest on the
  centreline or within lot depth on either side (>= 0.2) -> `side`, the band just beyond (52 / 72 m) >= 0.1 -> `near`
  (with the grid's smoothing: trees within ~90 m of the street), a dead end probed 120 m on into forest (>= 0.3) -> `tip`.
  FOREST lock line `near=`, PLAN `deepLocks=<locked>/<edges>`. The game's own streets can't be locked by the mod (that
  would mean rebuilding existing edges: the crash rule); its development hangs no side streets off the locked ones.
- **Lanes**: LN.DEEP_P 0.67 per eligible crossing whatever the era (offline 0.66 vs hug 0.26 at 1960), DEEP_MAX_PER_TOWN 8.
  Single-sided lanes on edge streets: not built (a country street has no houses on either side, the barrier decorations
  stay unverified; ONE_SIDED stays false): a deep town's edge streets are locked instead.
- **Secluded feel**: smaller blocks, dead ends into clearings (the holds stop pieces at the trees, the tip lock keeps the
  game from carrying on), ribbons one lot off the forest edge (EDGE_GAIN), clusters in the clearings joined by the
  lanes. culdesac_pods / satellites not reused (pods is a post-1950 suburban motif drawn in resolve; satellites run as
  before). **Density**: no level weights (UP.levelDecide `deep`; weights of ours sent before are cleared), the demand
  brake unchanged.
- **Districts / Works**: a deep town founds none (`why=deep` in DT.eligible / WK.eligible, tries spent); the 0.2 forest
  gate on their sites stays.
- **Logs**: STYLE `forest=<share>:deep deep=<why>`; PLAN `forestMode=deep deepLocks= bends=<edges bending >= 8 deg>/<edges>
  maxStraight=<m> groveHeld= lanes=`; ALLTOWN `forest=<share>:deep` (D.forestText); FOREST `mode=deep why=`.
- **Dev**: OT Dev Town tab "Forest (main mod)" -> "Force deep forest" (action `deepForest`, `Driver:devDeep`: session
  only, the dev and the main driver's town state; DEEPDEV line); the first build after it saves `fd`.
- **Offline** (test_deep, 7 tests; groves of 50-55 m in an open ring 260-420 m, forest beyond with three clearings; 4
  seeds x 8 increments of 18 edges): EU organic deep / hug / clear: grove cells kept 0.91 / 0.84 / 0.52, forest-adjacent
  edges locked 1.00 / 0.55 / 0, length 3514 / 4753 / 5579 m, maxStraight 72 / 171 / 143 m, bends 191/321 / 108/443 /
  130/517; MED hill: kept 0.95 / 0.91 / 0.68, locked 1.00 / 0.67 / 0, 3832 / 4955 / 5311 m, maxStraight 70 / 137 / 143 m;
  geoBad none everywhere. The driver with a fake tree reader: pick at the first plan, `fd` on the frame, deep again after a
  reload with the odds off, a frame without `fd` not deep. Hug / clear / none unchanged (test_forest's numbers
  identical, its "identical plan" test passes). Main 532 -> 539 / dev 131 -> 132 green.
- **Risks**: a deep town grows ~25-35 % less street per increment than a hug town (offline) and in game the game's own
  development, which carries most growth, gets far fewer streets to branch from (every street near the trees locked):
  the town may stay under its target size (watch CHECK `why=` and the town's buildings against its target); many locked
  streets also stop the game's side streets on the open side; the wiggles turn the junctions 10-15 deg off square (inside
  the planner's minAngle 25); groves are read from the grid at the time (a grove the game itself cleared is gone).

##### Generated names (2026-10-14; NEXT_PHASE_BRIEF 42; in game: TESTING.md "Generated names test")

User: "do we have an option for custom names? skip the european name set and use our own more interesting and very
procedural and reactive to environment names?" and "the more specific to the terrain the better".

- **Setting:** "Town and stop names" gets a third value, **Generated names**, appended as index 3 (params are 1-based
  indices: 1 Landscape names and 2 Game names keep their meaning in existing saves; ot_params `town_names = {
  "landscape", "game", "generated" }`). Default stays Landscape names: real names are the safer first impression,
  generated names are new and untested in game. Tooltip re-wrapped in 13 languages.
- **Generator** `ot_placename.lua` (pure) + `ot_placename_lang.lua` (data; entry syntax in its header): per name-list
  language (en, usa, de, fr, it, es, pt, nl, sv, nb, ja kanji, ja romaji) stems, generics and affixes, each tagged with
  fine site tags and weights, a regional dialect group, rare flags and a class.
- **Fine site tags** (`PN.siteTags`): river / mouth / ford / bridge / bend / confluence / spring / brook; lake / mere /
  pool / tarn; coast / sandy / rocky / cliff / bay / headland / spit / island; hill / hilltop / slope / ridge / pass /
  foot / mountain / valley / vale / gorge / combe / rock; marsh / fen / moor / heath; forest / edge / clearing and 21
  tree species; plain / field / meadow; market, church, big, small, character, district, works, old, new. From what
  the driver already has (ot_terrain stats and wide survey, ot_site features, spit, cliff, the forest share and the
  tree species of the forest read) plus one cheap read per town (`PN.read`, 81 samples in the names survey: water arms
  on a 450 m ring -> confluence (3+), mouth / spring (1), bend (2 at < 125 deg), river width -> brook / ford / bridge;
  the 1100 m ring's water share -> bay / headland and its dry heights -> hilltop (+18 m), foot (-25 m with a 120 m
  range), pass (two opposite heights up 15 m, the other two down 10 m); the altitude above the water level -> tarn
  (250 m), moor (200 m), mountain (450 m)). Specificity weights (`PN.SPEC`): confluence 1.6 > river 0.9, tarn 1.6 >
  lake 1.0, gorge 1.6 > valley 1.0.
- **Scoring:** a part's fit = best match (site x part weight x specificity) + 0.3 x the second, minus `PN.CONTRA` for
  each feature it claims that the site lacks (no "-mouth" inland; softer when a broader tag is present). Name = stem +
  generic (generic 1.0, stem 0.8), + 0.25 when they name two different features ("Alderbrook"), dialect multiplier
  (seeded anchors over the map, 2-6, each town takes the nearest (since NEXT_PHASE_BRIEF 53: 2-3 dialect areas, see
  "Name shapes chosen per map"): en saxon / norse / celtic / mixed, de nord / mitte /
  sued, usa east / mid / west, fr nord / sud / centre, nl, sv, nb), rare parts +0.35 on character towns and -0.35
  elsewhere, -0.45 / -0.7 per use of the generic / stem on the map, seeded jitter 0.2. Personal-name stems count 0.7
  (terrain first); the dialect acts on stems by its square root only (no rows of Norse personal names). Then an affix
  ("-on-Sea", "-upon-<River>", "Bad ...", "... an der <River>", "-sur-<River>", "Saint-...", "Upper ...") when it
  fits by more than 0.55 (character towns 0.15), never repeating a word of the base or a second phrase, -0.35 per use.
- **Rivers and lakes:** `PN.riverSystems` links river towns within 7 km whose line runs along both towns' river axes
  (40 deg), `PN.lakeSystems` lake towns within 7 km; each system gets a name from the language's list, then a syllable
  generator; the river stem joins the stems of its towns ("Avonmouth", "Lahnstein", "Aberavon"). Saved with the done
  flag as ot_saved `rv` = { n, s, x, y, k } (<= 32 entries); stop names read the nearest one of the stop's kind of water
  within 2.5 km (`site.waterName`, ot_stopname group "water": "Avon Street", "Lahnweg").
- **Rules:** suffix joins drop a final -e before a vowel, reject doubled junction letters a language doesn't double
  (en "Ashham"), vowel clashes, clusters over 3-4 consonants and triple letters; romance prefix joins elide (Villa +
  alta = Villalta) and agree in gender and number ("Casas Blancas"); two parts of one class or sharing a word never
  meet ("Bridgeford", "Isla de la Isla"); base <= 16 characters, name <= 30; a blocklist of offensive words and brands
  (substrings and whole words, case-insensitive, `ot_placename_lang.BLOCK_*`); never a name of any folder of the game's
  list (`n.real`) or one already on the map.
- **Driver:** the names phase as before (load -> survey -> assign -> rename -> industries) without the classify step;
  the survey adds `PN.read`; `Driver:namesAssignGen` names every town whose current name is from the game's list (a
  player-renamed one keeps it: `drawn=false`); satellites (a small town within 1.8 km of one 2.5 x its size, 40 %) take
  "Little X" / "Klein X" / "新X"; industries follow as before. NAME `src=generated parts= feature= tags= river= lake=
  dialect= read=`; NAMES `mode=generated gen= fallback= rivers= lakes=`.
- **Districts / Works** (60 % each, `D.GEN_OFFSHOOT_P`): `PN.related` (the parent's stem with a generic that fits the
  district's site kind: Ashford -> Ashdon / Ashdown on the hill; romance names have no stem -> composed forms) and
  `PN.works` (an industrial stem of the industry's kind with a site generic: "Leadbury"; romance: "Usine-Beauville");
  else the composed forms of ot_district / ot_works. DISTRICT / WORKS `src=generated`.
- **Fallback lists** (`PN.langOf` nil -> landscape names, `fallback=noGenerator`): Russian (europe ru, russia: Cyrillic
  and romanised forms need gendered adjective agreement and case endings, a small generator would read as fake
  Russian), Polish (no classifier either; adjective agreement, -ów / -owo / -ice morphology), Chinese, Korean, Asian
  (character names whose readings and meanings we can't compose reliably), Oceanian (Pacific and Indonesian names; an
  invented Maori, Samoan or Indonesian name would be appropriation and wrong). Those keep Landscape names (which for
  the lists without a classifier means the game's names).
- **Offline numbers** (test_placename, printed): stems / generics / affixes / stem+generic names: en 147 / 87 / 27 /
  9927, usa 129 / 64 / 12 / 8139, de 122 / 70 / 18 / 7704, fr 131 / 32 / 19 / 907, it 75 / 28 / 16 / 1502, es 79 / 36 /
  15 / 2078, pt 55 / 22 / 12 / 963, nl 62 / 40 / 10 / 1918, sv 74 / 43 / 7 / 2990, nb 71 / 37 / 6 / 2457, ja 65 / 39 / 3
  / 2521; 1000 towns per language all named, unique, none blocked; a one-feature site gets a part of that feature's
  family in 42-49 of 49 tags (fr lowest); a 16-town map uses 14-15 distinct generics, a 50-town one 23-42 (the most
  used generic 3-4 times).
- **Open (in game):** whether the extra read's thresholds (arms, ring, relH, altitude) tag real TF3 sites as intended;
  how often towns sit on a river axis the system linking catches; whether 30-character names fit the town labels.
  Tests: test_placename.lua (15), test_names.lua generated-mode driver tests (3).

##### Round after the 0502 run (2026-10-14; NEXT_PHASE_BRIEF 44; in game: TESTING.md "Seed a run")

Evidence: runs `2026-10-14_0502_sqot` (seed `Z2tNDhy0Ht`) and `2026-10-14_0613_sqot` (seed `a`, Generated names);
BASELINE_VANILLA.md "Retune run 2026-10-14 0502" and "Seed a run 2026-10-14 0613". From now on the user plays seed `a`.

- **LEVELS vs the engine's own weights.** Generated towns carry per-town custom level weights the mod never sent (level 1
  0.08-0.33, level 2 0-0.26, levels 3-4 0; findings towns.md), so `levelDecide` read them as the player's (`skip=player`
  on every grown town). Now `Driver:levelBaseStart` (run start): on a new map whose save has no baseline and whose clock
  is under `SV.FRESH_GAME_TIME`, every town's weights (`UP.levelSig`: 12 numbers, 3 decimals, or "-") are the engine's
  baseline, kept in `self.lvBase` and saved (EV_LEVELBASE, ot_saved `lb` / `lbs`, first event wins). `UP.levelOwner`:
  none / engine (= baseline) / ours (= `levelWeights(ours)`) / player (anything else; no baseline: every custom weight).
  `levelDecide` takes `owner`; a clear sends the baseline back (`weights=...:base`), else the default. LEVELS `owner=`,
  `LEVELS event=base from=firstSight|save|none`. Probe `Driver:levelsProbe(at, all)`: `LEVELS read town= custom= base=
  was= at=` for every town at load and for changed towns after every SIMGROW round (`at=simgrow:year=N`, otd_runner
  simRoundEnd), and a summary `LEVELS read at= towns= custom= changed=`. Open: whether the engine changes a town's
  weights later (era 1950 / 1990?); such a change would now count as the player's (the probe will show it).
- **Mature hold (ot_assess MATURE_*).** `why=free` never fired in 0502 / 0613 (its hold applies only below
  DEMAND_MIN_EDGES of demand; grown towns always had demand) and demK at maturity 1 stayed 0.4-0.7. Now (a) `A.demand`
  caps demK at 1 - mat x capK x (1 - MATURE_DEMK 0.18), capK 0..1 over FREE_AIM - FREE_BAND_LO .. FREE_AIM (50-55 %
  free; dem.matureCap); (b) `A.needsRoom` returns `why=mature` (no build, the demand stays in the bank) while free lots
  exceed `A.matureHoldLine(mat)` = 0.60 + (1 - mat) x YOUNG_ROOM from maturity 0.5. Young towns (mat 0) untouched.
  `MATURE town= event=hold|cap|off mat= free= line= demK= demand= pb=` once per change. A held town is due for offshoot
  turns again. Before 1950 a grown town densifies by filling its lots (levels 1-2 only). Offline (test_demand
  "maturity"): grown share 41 % -> 34 %, pb 4.24 -> 4.32 (the model's lots hold a fixed capacity, so pb barely moves).
- **Satellites that stay empty.** The seed's dose came 1-2 s after the build, before the new streets had lots (FILL
  effect near=0->0 on every dosed seed), and five seeds got no dose (`skip=surge`). Now: `SAT.CORE_SMALL` (3 core
  edges: the main street's first block and the cross street at the site; the second cross street comes with the growth
  once housed); `D.fillKind` returns the `job.fillPts` dose (satellite core, lane end, bridge far bank) before the surge
  rule; `Driver:satWatch` at each check of the town: `SAT.watch` -> a core dose of its own (`Driver:coreDose`, FILL
  `why=satCore dose=n of=2`) REDOSE_S 45 s after the build and after the last dose, up to REDOSES 2, then `SATELLITE
  retire` after RETIRE_CHECKS 10 empty checks (st.retired / full: no more streets; its gap meadow removed from the style).
- **Bridges to empty stubs.** `BR.CROSS_LATER`: the far street ends at C (no cross street; the town's planner grows the
  quarter from C once houses stand); the far bank gets a dose at the build (`BR.farPoints`, FILL `why=bridgeEnd`) and a
  redose by `Driver:bridgeWatch` (SAT.watch timing, no retire). `BR.APPROACH_MAX` 260 m (Budleigh Salterton's 384 m
  straight approach); an approach over APPROACH_BOW_M 120 m bends once through a seeded waypoint (BOW 0.07 x its length;
  node -11, edge -12, both approach pieces locked; same template, so no lane count change next to the bridge). BRIDGE
  built `approach= bowed= crossLater=`.
- **District names from the reserve.** `DT.name` read `self.nameReserve`, which nothing set: now `Driver:namesAssign`
  sets it from `NM.reserve(pool, used, seed)` (Landscape names, this session only; after a reload districts compose).
- **Dev Simulate speed.** `H.simNoFills` (ot_hooks) while a build round runs: `D.fillKind` returns `sim` and
  `upwardStart` skips (the Fast fill covers them); SG.ROUND_BUILDS 3 (was 6; Build out keeps 8 per 10-year chunk);
  Quick / Build out greyed (`sqotd-wait`) and refused by the runner until the main driver's `HEAD done` (status
  `mainHead`); SIMGROW year / chunk `added= perS=`. Expected Quick time ~0.7 s x quiet years + buildings added / 90 (0613:
  172 s estimated, 182 s measured).
- **Generated name tags** (ot_placename.siteTags / read): `edge` only with `info.forestEdge` (`FO.isEdge`: the town disc
  under 250 m <= 0.25 wooded, an eighth of the 250-900 m ring >= 0.45, another <= 0.12); species by lift over the map's
  mix (`info.speciesMap`, SPECIES_LIFT 1.15; the common species never tags every town); hill and vale need the disc's own
  dry height range OWN_RANGE 12 m (the wide survey's spread made flat towns dales); `island` only with a closed shore
  (else headland); `spit` only with the tip within SPIT_M 800 m and water at the town; slope near the water level
  (alt < 20 m, not above the ring) weighs 0.3 ("Upper" at altitude 2); no "tarn" lake generic unless a town of the lake
  has the `tarn` tag; `PN.read` adds RIV_N 16 rays to 700 m: a first wet run <= 160 m wide with 30 m dry beyond is a
  crossing, RIV_RAYS 3 crossings make a river town (`PN.nearRiver`, `read=...,riv:n/width@dist`). Risk: a lake arm
  crossed by three rays reads as a river too.
- **Offshoot links.** 1 of 7 linked in 0613 (`why=back` x4: every route left the dead end on the line to the target;
  one try each). `LK.LEAD`: after the seeded bend, three lead-out routes (a cubic curve leaving along the dead end's own
  street, straight or swung to either side by LEAD_SIDE, arriving along the other end's street) that must keep CLEAR of
  both ends' own streets; their detour cost is the farthest point off the line. Tries D.WORKS_LINK_TRIES 5, D.WORKS_LINK_RETRY_S 60 s,
  each with another route seed. Not done: starting from the town's nearest edge (no mid-street joins: the crash rule).
- **Works caps checked:** 0613's WORKS create lines show `caps=10/10/200` for both (the generated path changes the name
  only); CHECK now logs `uses=` (person capacity per land use) and `initials=` to see whether the 200 are built as
  industry.
- **Deep forest pick recalibrated:** the ring at DEEP_COVER 0.25 (~18 trees / ha, FOREST_COVER 0.5 ~24 elsewhere
  unchanged), DEEP_SHARE 0.40, and DEEP_SECTORS 5 of 8 ring sectors >= 0.25 (woods around, not on one side). Not
  rank-based: each town is picked before its first build, before most other towns' grids are read.
- **Tour aim (dev):** a fallback shot with the camera more than REAIM_M 60 m off the target aims again (at most 2, `SHOT
  reaim`); 0613's shot 1 was 925 m off.
- Tests: test_round0502.lua (new, 13); test_demand (level driver: engine baseline / later change; maturity: a fourth
  variant without the mature hold), test_satellite (core >= 3), test_ships (no cross street), test_deep (half-wooded
  town: the sector rule), test_district (doubling back only without LEAD), dev test_simgrow (round cap 3, simNoFills).
  Main 569, dev 133.

##### Names from the map's shape (2026-10-14; NEXT_PHASE_BRIEF 45; in game: TESTING.md "Names from the map's shape")

Evidence: run `2026-10-14_0710_sqot` (seed `a`, USA list, Landscape names): 9 of 16 starting towns carried Lake / Forest
(Forest Lake, Canyon Lake, Lake Forest, Kendale Lakes, Lake in the Hills, Lauderdale Lakes, Wake Forest, Park Forest, Forest
Hills; `lake:1.00` on 6 towns, `forest` on 15) and `Milford_city_` kept the list's "Milford city " (the usa list's only
such entry). User: "too many repeat words in city names ... take into account the shape of the map. e.g. middle fork,
directionality, big geographical cues". Names are still given once per new map, at first sight; nothing renames a named
town on load (the done flag `nm` is unchanged).

- **Map survey (`ot_mapshape`, phase `shape` of the names phase, after the per-town survey).** The map's bounds on a
  coarse grid (cell `max(CELL_M 120, extent / MAX_N 128)`; a 16 km map: 128 x 128 cells of 128 m, one height and one
  `isOnWater` read each, a fresh sampler). Phases, each in units (one cell / ring / BFS pop), `more()` checked every 32
  units against `NAMES_SLICE_US` (2 ms), capped at `PHASE_K` 40 units per cell (`capped=<phase>`, the phase's features
  skipped) and the whole survey at `D.NAMES_SHAPE_MAX_S` 45 s (`capped=<phase>:timeout`, the rest skipped); an error in
  a phase skips it (`<phase>:error`). sample -> width (the shortest run through each water cell over four axes:
  `RIVER_MAX_M` 400 m and narrower is river, wider a body) -> label (bodies first, 8-neighbours; a body under
  `SMALL_BODY` 12 cells off the map edge, such as the wide water where two rivers meet, becomes river; then rivers,
  8-neighbours and one-cell gaps; bodies at the edge are the sea; a river of `RIVER_MIN_M` 1.5 km or more counts) ->
  rivers (mouths: a river cell beside a body; forks: 3+ river arms on a round ring of 3 cells, away from bodies; bends:
  two arms under `BEND_DEG` 100; falls: the water's edge (the highest wet height of the 3 x 3) `FALL_DH` 12 m higher within
  two cells; greedy clusters of 4 cells, `MAX_FEAT` 48 per kind) -> flow (upper / lower course of rivers of 3 km+: BFS
  distance from the mouth, else the water's edge heights with a 12 m fall) -> relief (the dry median; peaks
  `PEAK_MIN` 120 m above it and the highest within 4 cells; the range: the largest patch of ground `max(150 m, half the
  way to the top)` above the median, 12 cells+; the main valley: the longest river of 4 km+) -> coast (bays: water with
  60 % land on a 6-cell ring in a body of 200+ cells; capes: land beside a body with 60 % body water on it; narrows: water
  under 450 m reaching 1 km wide water both ways; isthmus: land with body water on both sides within 4 cells and land 5
  cells along the neck). Offline: the synthetic map in test_nameshape (a river forking at (0, 0), two mouths, a lake, a
  peak on a ridge, a bay) 117,748 units, ~120 ms in Lua 5.2 with the sampler (in game the 32k API reads dominate: the
  terrain stats read ~12 us per sample, so ~0.4-0.6 s of reads over a few hundred ticks). Log: `NAMES survey rivers=
  forks= mouths= bends= falls= lakes= sea= peaks= ranges= valley= bays= capes= narrows= isthmus= grid= cell= wet= units=
  capped= ms= s=` (or `NAMES survey on=false why=noBounds|small|off`).
- **Town cues (`MS.townCues`).** Per town: its long river (the nearest river cell within 900 m: towns along one river share
  its name, `PN.assign` groups them by the component instead of the axis rule), `twin` (two rivers within 1.2 km),
  `confluence` (a fork within 1.5 km), `mouth` (1.5 km), `bend` (800 m), `falls` (1.5 km), `upper` / `lower` (the outer
  thirds of the river's course), the compass (`north` / `south` / `east` / `west` beyond 30 % of the half extent toward
  that edge, weight 0.4-1; `central` within 25 %; `dir` = the strongest side), `biglake` (within 1.5 km of the largest
  lake; `ldir` = its side of the lake), `peak` (3 km of the highest peak), `summit` (on the range), `range` (within
  2.5 km of it), `divide` (on the range with two long rivers on opposite sides within 4 km), `mainvalley` (1.5 km of the
  longest river), `bay` / `bigbay` (1.5 km; the largest bay), `headland` (a cape within 1 km), `narrows`, `isthmus`
  (1.2 km). NAME lines: `cue=confluence:1.00,north:0.70,...`, `words=` (the name's budget keys).
- **Word budget (`ot_namewords`).** `WORDS` per list language (en, usa, de, fr, it, es, pt, nl, sv, nb, ja, ja_r, ru,
  ru_r): whole words ("Lake", "Woods"), endings ("-wood", "-see", "-wald", "-berg", "-sjön") and starts ("Mont-", "Lake-"),
  under family keys, plus the compass and Upper / Lower. Each key at most `max(1, ceil(towns / PER_TOWNS 8))` times on the
  map and never within `NEAR_M` 5 km; `SOFT` keys (-ford, -bridge, -bach, -berg, -dal, 山 ...) twice the count, half the
  distance. Landscape names also count every other word of a multi-word list name (`=plainfield`, 4+ letters, not a stop
  word): at most once on the map (the 0710 replay put North Plainfield and South Plainfield on one map before it).
  Derived names (district, Works, satellite) don't pay for their parent's words. Generated names: a part whose own word the
  budget holds here ranks `BUDGET_PEN` 2.0 lower (100 towns: 90 ms, as before; without it 750 ms), the built name is
  checked again, and when nothing fits the best name over the budget is taken (`over=`). Districts / Works: the budget over
  the map's current town names and positions (`Driver:offshootBudget`), generated (`PN.related` / `PN.works`, strict) and
  composed forms (`DT.name` / `WK.name` `o.ok`); with no name left, a repeat rather than no district. Stops are not in the
  budget; their picks vary the last word (`SN.VARY_N` 6 candidates, each earlier use of the word on the map 2 places
  down). Log once per map: `NAMES words used=lake:2,forest:1,... held=lake:5,=plainfield:1 cap= near= over= rare= mode=`
  (+ `clean=` / `mount=` `bay=`).
- **Rarity (`NW.rarity`).** A tag on more than 20 % of the towns (weight >= 0.3) weighs `1 - (share - 0.2) / 0.8 x 0.7`,
  down to 0.3 on every town; town meta tags and the compass are exempt; 4+ towns. Both modes (`rare=` on the words line).
- **Landscape names.** `townTags` adds the survey's cues as coarse tags (confluence / falls / bend -> river, mouth ->
  estuary, biglake -> lake, peak / summit / range / divide -> hill, mainvalley -> valley, bay / narrows -> coast, cape /
  isthmus -> headland); every pool name gets its cue words (`NW.CUES`: "North ...", "Upper ...", "... Forks", "...
  Falls", "... Bend", "... Gap", "Summit", "Mount ...", "-mouth", "Nord-" / "Ober-" / "Unter-", "Haut" / "Bas", "-fors",
  北 / 上 ...) and cue buckets; a town walks its tag buckets and its cue buckets; score += 0.8 x CUE_W x name cue x town cue
  (fork / falls / divide / narrows 1.6, mouth / bend / gap / peak / twin 1.4, compass 0.45, central 0.3), minus CUE_CONTRA
  (compass 0.8, fork / falls ... 0.6) for a name cue the survey didn't find (no survey: no cue terms). A compass word is
  a preference among fitting names, not a reason of its own to rename. A kept game name must fit the budget too (else
  renamed). `NW.clean` drops list disambiguators ("Milford city " -> "Milford", "(city)", "(CDP)"; match `clean`), in the
  industries' renames (a town name with a trailing blank matches "<town> <type>" either way) and the reserve; stop
  candidates from streets.lua are trimmed.
- **Generated names.** The cue tags join each town's site weights (`PN.withCues`), then rarity, then the order (most
  distinctive after rarity first). New tags: north / south / east / west / central / dir, upper / lower (parents slope /
  foot: the existing "Upper" / "Ober-" / "-le-Haut" forms serve the upper course), falls, twin, summit, divide, peak, range,
  mainvalley, biglake, bigbay, narrows, isthmus (SPEC 0.7-1.6, CONTRA 0.5-1.0: no "North ..." in the south, no "Falls"
  without falls). Affix fields `%t` (the river's stem), `%m` / `%M` (the map's mountain: `peaks`, `peakForm`), `%b` / `%B`
  (the big bay: `bays` / `bayForm`), `%D` (the compass side), `%E` (the side of the big lake). An affix without `%s` is the
  whole name, taken from fit >= `FULL_MIN` 0.4 ("Cedar Falls", "Three Rivers", "Middle Fork", "Condé-sur-Risle",
  "Divide"; NAME `parts=whole:<affix>`). Features named once per map (`featName`: usa "Eagle Mountain" / "Heron Bay", en
  "Brant Fell" / "Whit Bay"; other languages none). Per language: usa East / West / North / South, `%E %k` ("West Crystal
  Lake"), `%D Bend`, `%t Forks`, Three Rivers, Twin Rivers, Middle Fork, `%t Falls` / Bend / Junction, Upper / Lower `%t`,
  Port `%t`, `%m Gap` / Summit, Summit, Divide, Mount `%m`, `%m` / `%t Valley`, `%B`, Narrows, `%s Neck`; _Falls / _Rapids
  now need falls; en North / South / East / West, Lower, `%s-under-%m`, `%s Fell`, `%s-by-the-Narrows`, `%t Head`, `%s
  Water Foot`, stems Myt (OE gemythe, "Myton") and Twy; de Norder- / Süder- / Oster- / Wester-, -münden, `%s am Fall` /
  `am Pass`, -münde no longer rare; fr Haut- / Bas-, Condé-sur-`%r`, -les-Cascades, -du-Col, -Nord / -Sud; it Bocca di
  `%t`, Alta / Bassa, delle Cascate, al Passo; es Juntas de `%t`, Las Juntas, del Salto, del Puerto, del Norte / del Sur; pt
  Foz do `%t`, Entre-os-Rios, da Cascata, do Norte / do Sul; nl Noord- / Zuid- / Oost- / West-, `%t`mond, Boven-, stem
  Twee; sv Norra / Södra / Östra / Västra, `%t`fors, -mot; nb Nordre / Søndre / Østre / Vestre, `%t`foss, `%t`os, -mot; ja
  北 / 南 / 東 / 西, 落合, -川合. Big-lake towns are one lake system; towns kept (player-renamed) count first (`keep`).
- **Name lab** (`names/`): gen.js ports the cue tags, rarity, the budget (`M.NW`), whole-name affixes, the new fields,
  featName and the ranking penalty; export_names.py exports `nw` and 10 cue presets (river fork, falls, upper / lower
  course, north edge, big lake shore, mountain gap, summit, big bay, narrows) and golden towns with the survey's facts +
  a kept town; check_port 948 / 948. The page has a "Word budget" checkbox (one map of n towns).
- **Offline** (test_nameshape, 16 tests): the survey of the synthetic map (rivers 1, forks 1, mouths 2, lakes 1, sea,
  peaks 1, ranges 1, bays 2, capes 2; no caps); cues (fork, upper, mouth + lower, north, central, lake side, peak, bay);
  caps (PHASE_K 0.5: capped, sliced = whole, stop -> timeout, no bounds); 16 lake towns: lake words 1-2 in usa / en / de /
  sv, none twice within 5 km; the real usa list, 16 lake towns: 2 lake words (14 without the budget); rarity; clean names
  + industries + stops; a fork town: usa "Middle Fork", en "Twywath", de "Fährmünden", fr "Condé-sur-Risle", landscape
  "Grand Forks"; compass words only on their side (usa / sv / nb / nl; landscape "North Platte" / "South Gate", no North
  name in the south); one river shared (usa Upper Spring / Lower Spring / Spring Valley); determinism; derived names; the
  driver (survey once, `cue=`, the lines, nothing on a reload, no bounds, the time cap); cost; the replay of 0710's 16
  towns: Cottonwood Heights, Milford, Canyon Lake, Lake in the Hills, Oakdale, American Canyon, West Hollywood, North
  Plainfield, Bay Point, Chicago (kept), Southfield, Saratoga Springs, Eastern Goleta Valley, East Ridge, Desert Hot
  Springs, Crown Point (lake 2, forest 0, woods 2; compass words only toward their edge, at most 2 each). test_names: two order tests run without the
  budget (it would allow one "-haven" / one lake name per 8 towns).
- **Risks / open (in game):** the grid misses rivers under ~100 m wide on a 16 km map (cells of 128 m; a broken river
  splits into two names); the falls read assumes per-tile river water levels (no falls on a flat-level map); a long lake
  arm reads as river; bays / capes on a ragged coast may cluster oddly; the compass and the big features only name a few
  towns per map (by design: the budget, CONTRA); the whole-word rule can turn down real pairs a player might like ("North
  / South Salt Lake"); the survey adds ~1-3 s of game time before the head start (NAMES_MAX_S unchanged).

##### Bridge stops (2026-10-14; NEXT_PHASE_BRIEF 46; in game: TESTING.md "Bridge stops")

User: "if a bus stop is on a bridge, we could use that as a big cue." Also the fix of run `2026-10-14_0814_sqot`'s 9x
`ERROR stage=snapshot ... ot_satellite.lua:240` (a bridge plan without a far cross street has one line, `BR.lines(c)[2]`
nil; the driver now skips it, `SAT.clearOfObstacles` is clear for nil / under 2 points; test_ships "bridgeDecide (run
0814)", test_satellite).

- **The read (`ot_engine.stopBridge(st, x, y)`, pcall-guarded, read-only):** the BASE_EDGEs within 80 m (at most 200);
  the stop's own edge is the one whose `objects` hold the stop's station entity (64 objects at most per edge); bridge
  edges (`type == api.type.enum.BaseEdgeType.BRIDGE`, or 1) as two chords through the Hermite midpoint, with their end
  points. Returns `{ read, on, edge, bridges, n }`. Streets only for Road Stops (`e.k == nil`), never for stations.
- **The cue (`SN.bridgeCue`):** `on` when the stop's edge is a bridge (`how=edge`), or, with no edge found, within
  `BRIDGE_ON_M` 6 m of a bridge chord (`near`); `end` for a stop off the bridge within `BRIDGE_END_M` 60 m of a bridge
  edge's end. A read edge that is not a bridge is never `on` (a street beside or under the bridge). The read throwing:
  no cue (`bridgeRead=fail`), the normal name.
- **The names (`SN.BRIDGE`, `SN.bridgeNames`, theme `bridge` first in `themesFor`):** on: river (`%r`: the generated
  river name within 2.5 km, `D.waterNameAt` kind `r`; first word when long), town (`%t`: `townWord`), Old / New (Old first
  before `BRIDGE_OLD_YEAR` 1900, game year), street forms; end: the end forms, then the street forms. Per classifier: en
  Avon Bridge / Haslemere Bridge / Old Bridge / Bridge Street / Bridge End / Bridgefoot; usa + River Bridge / Bridge St /
  Bridge Plaza; de Lahnbrücke / Haslemerer Brücke / Alte / Neue Brücke / Brückenstrasse / An der Brücke / Am
  Brückenkopf; nl Avonbrug / Oude / Nieuwe Brug / Brugstraat / Bij de Brug; sv Avonbron / Gamla bron / Brogatan / Vid
  bron; nb Avonbrua / Gamlebrua / Nybrua / Brugata / Ved brua; fr Pont d'Avon / Vieux Pont / Pont Neuf / Rue du Pont /
  Tête de Pont; it Ponte Avon / Ponte Vecchio / Via del Ponte / Capo di Ponte; es Puente de Avon / Puente Viejo / Calle
  del Puente / Cabeza del Puente; pt Ponte de Avon / Ponte Velha / Rua da Ponte / Cabeça da Ponte; ja 多摩橋 / 大橋 / 旧橋
  / 新橋 / 橋通り / 橋詰 / 橋本; ja_r -bashi / Ōhashi / Hashizume; ru Мост через Волгу / Старый мост / Мостовая улица / У
  моста / Предмостная площадь; ru_r likewise. Like the other stop parts these are list-language names (not mod.json
  strings). Unique map-wide (`used`); in `SN.pick` the variety window holds only bridge names while one is unused (the
  bridge stays the cue; the last-word rule picks among them); none left: the stop's other themes. A bridge stop is
  named before a section variant (`stopName`); it can be a section base.
- **Log:** STOPNAME `theme=bridge kind=bridge:river|town|old|new|street|end ... bridge=1|end|0
  bridgeRead=edge|near|end|noEdge|fail river=<name>|-` (`river=` only with a cue).
- **Offline** (test_stopname, 5 tests): the cue (edge, near, end, none, NaN / garbage), every classifier's forms and
  era order, 20 bridge stops per classifier all distinct, 40 non-bridge stops per classifier unchanged, the driver's
  stopName with a fake engine (Avon Bridge + `bridge=1 bridgeRead=edge river=Avon`, Bridge End, `near`, a throwing read
  -> the normal name with `bridge=0 bridgeRead=fail`).
- **Open (in game):** whether the stop's station entity is the one in its edge's `objects` (else every bridge stop goes
  by the 6 m fallback, `bridgeRead=near`); the Russian town form "Мост на <town>" uses the accusative helper only.

##### Satellite and Works name variety (2026-10-14; NEXT_PHASE_BRIEF 47; in game: TESTING.md "Climate-led names", step "Created towns")

User: "industrial satellites seem like they always say 'works' or very often. make sure our satellites have lots of
variety too." Evidence: "Works" on 7 of 11 Works towns, every one "<Parent> <suffix>"; districts Sands x4, Beach x3,
-on-Sea x3 (a "shore" site was any water within 170 m, a river bank too, and the first form of each kind won every tie
on a fresh map).

- `ot_offname` (new) names both. Works: the family of the industry's file (`indType`: steel / iron ore / coal / quarry
  / clay & bricks / sand / cement / chemicals / glass / oil / machines & tools & vehicles & tyres / textiles / paper &
  printing / timber & furniture / food / brewing / farms / fishing, else works) and the site (harbour, rail, across ->
  river, hill), the survey's cues (falls, bend, confluence, mouth, bay) and a local water read. Patterns: parent (the
  family's and the site's forms), company (founder names with the language's company-town forms: "%Fville", "Port %F",
  "Kolonie %F", "Zeche %F", "%Fsberg", "Colonia %F", "Villaggio %F", "Cité %F"; "New %s"), cue (a family root glued to a
  site word where the site has it: "%rbridge" river, "%r Vale" valley, "%rport" water, "%rberg" hill), generic (Works,
  Depot, the era's estates: low weight). A seeded draw picks the pattern (parent 0.5, company 0.25, cue 0.25) among those
  whose best candidate is as rare on the map as the overall best.
- Districts: the site kind's forms, Upper / Lower from the height against the parent (+18 / -10 m), the compass from the
  parent, river forms on a river bank (Ford, Holme, Ings, Ferry), Little / New, the language's generics, beach words
  (Sands, -on-Sea, Strand, Beach) only on a sandy sea shore, rocky-shore words (Head, Ness, Point) on a rocky one, lake
  words by a lake; inland or by a river no water word. Never a real list name.
- Suffix keys: the literal text around a form's placeholder ("works", "port+", "*ville" for a glued ending). A map name
  carries a key when it ends (starts) with it as a word, or as a glued part. Candidates: lowest map count, then no
  sibling of the same parent with the key, then weight + seeded jitter (ot_rng's hash rehashed: consecutive seeds stepped
  evenly). Counted over the map's names each time (no state; a reload counts the same). The word budget (ot_namewords)
  and the climate (ot_climate) filter every candidate.
- Driver: `offshootCls` (false on a list without a classifier: `offshootListName`, an unused name of the list),
  `offshootSite` (compass, height difference, `readWater`, the session's survey `mapShape`: falls / bend / confluence /
  mouth / bay, the big lake or `waterNear` telling sea from lake), WORKS / DISTRICT lines `pattern= suffix= fam=`,
  `NAMES offshoot used= n= new= pattern= suffix=`.
- Samples (test_offname, seed 42): en Works "Haslemere Rolling Mills", "Coalville", "Ringwood Glassworks", "Tickhill
  Sawmills", "Lime Hill", "Radcliffe Garden Village", "Settle Locomotive Works", "Yarm Maltings", "Chesham Kilns",
  "Cottonfield"; usa Works "Haslemere Steel", "Harlan Mines", "Ringwood Wharf", "Lime Hill", "Prenticeville", "Mill City"
  ...; en districts "Upper Haslemere", "East Heywood", "Ringwood Dale", "Tickhill Ford", "North Winchcombe", "High
  Settle", "Yarm Grange", "Chesham Vale", "Telscombe Fields"; de "Haslemere-Höhe", "Heywood-Ost", "Tickhill-Au",
  "Winchcombe-Nord", "Settle-Berg", "Chesham-Feld".

##### Plausible, climate-led names (2026-10-14; NEXT_PHASE_BRIEF 49; in game: TESTING.md "Climate-led names")

Run `2026-10-14_0814_sqot` loads 4 and 6 (tropical island map, survey `lakes=0 sea=true`): "Lake in the Hills",
"Canyon Lake", "Cottonwood Heights", "West Hollywood", and real English towns on tropical islands. User: "our names
should all be heavily influenced from the region (tropical, subarctic, etc.) ... in landscape name mode i'd prefer not
to use real existing city names, and instead all generated names from region and geography cues".

- Landscape names = the generator. Both name values run ot_placename (`n.glang`); the list matcher in the driver
  (`namesAssign`, phase classify, the district name reserve) is gone. ot_names stays for the stop names (pool, classifier,
  street lists) and its own tests. The setting kept three values with "Generated names" as an alias until 2026-10-15; then the user removed it ("remove it"): the setting is Landscape names / Game names, and a saved 3 reads as Landscape names (`ot_params`).
- Climate (`ot_climate`): the climate key from the map's climate path; `VETO_TAGS` (an inventory entry claiming a vetoed
  tag at >= 0.3 is never ranked; affixes alike); `SITE` (tags every town of the climate reads: tropic / arid / boreal and
  palm, birch, pine; siteTags adds reef / lagoon / mangrove on the right coast, dune / mesa / wadi on dry ground, snow /
  moor on high subarctic ground, and drops the vetoed tags); `wordMisfit` on every finished, river and lake name and on
  the offshoot names. New tags: tropic, arid, boreal (CONTRA 3.0: another climate's words never fit), reef, lagoon,
  mangrove, dune, mesa, wadi, snow. Climate words in all 11 generator languages.
- Survey agreement: `PN.agreeSurvey(w, MS.waterNear(...))`: no lake word without a lake (not the sea) within 1.5 km; the
  weight moves to coast / bay on a sea map. `NAMES words ... climate= misfit=` lists the vetoes and corrections.
- Lists: oceania -> the English generator; asia / china / korea / poland -> the game's names (`untaggedList`), russia ->
  `noGenerator`; the survey runs for all of them.
- Samples (test_climate, the load 4 replay, usa): "South Banyanville", "West Hayes Key", "North Dalton Harbor", "Coralboro",
  "East Turner Keys", "Ward Island", "Bradley Lagoon", "Barnes Reef"; en: "North Hunt Key", "Reefdon", "East Glen Lagoon",
  "Lud Reef", "Market Chip Cay", "Coralton"; de tropical "Korallenriff", "Palmenmünden".
- Stop names (2026-10-14, done offline): `ot_stopname.climateKey` = `ot_climate.key` (subarctic too); `treesFor` drops
  the species the climate rules out (tag veto or word: no oak / birch / pine on a tropical map, no willow / alder on a
  dry one, no palm / lemon in the subarctic; subarctic defaults spruce / pine / birch / larch / fir); every candidate
  runs `SN.fits`: `CL.wordMisfit` on the name with its proper names (town, neighbour, river / lake, industry) blanked,
  and with the survey's `MS.waterNear` (1.5 km) showing no lake, `CL.lakeMisfit` (no Lake / Lakeside / Mere / See / Lac
  ...; a town-stats "lake" the survey doesn't know becomes `lakeFix=noLake|sea`). Bridge names are never checked.
  STOPNAME adds `climate= noLake= lakeFix= misfit=climate:n,lake:n`. `ot_climate.lower` folds ASCII only now (a locale
  `%u` folded UTF-8 lead bytes: "Sjö" never matched); "First" / "Alderman" are no fir / alder (`NOT_WORDS`, ported to the
  Name lab).
- Open: Russian and Polish generators; the survey runs on a fresh map only, so after a reload the stop names have no
  lake read (stats only, as before).

##### Style spread on the Asian list, tropical bias, character quota (2026-10-14; NEXT_PHASE_BRIEF 48 items 3-4; in game: TESTING.md "Climate-led names" step 9)

Run `2026-10-14_0814_sqot` load 3 (asia list, tropical): 14 of 16 towns JP_DENSE (asia -> EAST_ASIA; in 1900 the
superblock is gated, so JP_DENSE x3 stood alone), and `CHARACTER towns=16 count=2` -> `towns=17 count=3` once a created
town appeared (Shanghai added).

- Region ASIA (`ot_inputs`: the "asia" list only; china / korea stay EAST_ASIA, japan JP): `ot_site.REGION.ASIA` EU_ORGANIC
  2, JP_DENSE 1.6, SUPERBLOCK 1.6 (from 1950), MED_HILL 1.4, NA_GRID 1.1, EU_EXTENSION 1.1, MED_ENSANCHE 0.9, NA_SUBURB 0.6;
  `ot_metro` grid 1.5 / oldcore 1.5 / polycentric 1.2 / radial 1 / corridor 1, core grid 0.45; `ot_angles` 25 deg;
  `pickProfile` (no auto style) EU_ORGANIC (dry: MED_HILL), SUPERBLOCK from era 4.
- Tropical (`ot_site.CLIMATE.tropical`): NA_SUBURB 1.8, EU_EXTENSION 1.5, EU_ORGANIC 1.2, NA_GRID 1.1, SUPERBLOCK 0.7,
  JP_DENSE / MED_HILL 0.6, NORDIC 0.3; forms (`ot_form.CLIMATE`): sprawling 1.5, linear 1.3, radiating 1.25, clustered 0.6,
  shore chance x1.3 (still capped at `SHORE_P.max`); blocks x1.15 as before (`ot_style.BLOCK_TROPICAL`, under the
  subarctic's 1.2). Dry adds NORDIC 0.3, subarctic MED_HILL 0.5 / MED_ENSANCHE 0.7.
- Offline (test_site, 16 varied synthetic sites, one town each): asia tropical 1900 EU_ORGANIC 6, JP_DENSE 4,
  EU_EXTENSION 4, NA_GRID 1, MED_HILL 1; asia tropical 1960 eight styles, none over 4; 160 towns per case: no style over
  42 %. Japan list on a tropical map: JP_DENSE 124 of 160. Tropical vs temperate (EU, 1960): NA_SUBURB 0.16 / 0.11,
  EU_EXTENSION 0.29 / 0.24, MED_HILL 0.02 / 0.05; forms on flat land (120 towns): clustered 9 / 16, sprawling 50 / 41.
- Character quota: `Driver:characterOf` ranks the map's own towns (Works and district towns, saved or this session, are
  left out and never picked; the ranking is redone when the town count or the created towns change); `ot_map.characters`
  `fixed`: a frame's saved `ch` stays a pick, a frame without it never becomes one, the free slots go to unframed towns.

- (2026-10-14, NEXT_PHASE_BRIEF 50 item 4) Under the dev Simulate the builds run on pool drivers (otd_runner
  `poolDriver`) that share `towns` but not `saved`, the created-town sets or the cache: run 1729 logged `created=0
  fixed=0` and the picks changed at 22 towns. Now `Driver:root()` (the game script's driver, `ot_hooks.main`, when this
  one shares its `towns`) owns the cache, the session picks (`charSticky`: a pick stays a pick, also before its frame
  is saved) and the one creation in flight (`createInFlight`); `Driver:createdTowns` reads every record (saved `wk` /
  `dk`, the claimed sets of both drivers, the parents' `works.town` / `districts[].town`); a town that appeared while a
  creation is in flight and isn't identified yet counts as created (pending).

##### Name fixes after the 1729 run (2026-10-14; NEXT_PHASE_BRIEF 50; in game: TESTING.md "Climate-led names")

Run `2026-10-14_1729_add-money-100m` loads 3 (europe) and 4 (usa), seed a, temperate.

- One path for every created town's name (`Driver:offshootName`): the generator's name (`PN.related` / `PN.works`, drawn
  GEN_OFFSHOOT_P in Landscape / Generated names) is only a candidate of `ot_offname` (`o.extra`, pattern `generated`,
  suffix key from its generic: "*sands"), ranked with the composed forms by the map-wide suffix count, the siblings, the
  climate and the site's water. `OFF.shoreOk`: beach words (Sands, Beach, Strand, -on-Sea, Plage, Lido, Playa, Praia,
  浜 ...) only on a sandy sea shore, Sea / Mer / Mar only by the sea, lake words (Lake, Mere, Tarn, See, Meer, Lac ...)
  only by a lake, for composed and generated names. `PN.related` reads the site: a lake shore takes lake words, a
  rocky sea shore `shoreRock`, only a sandy sea shore the beach weights. A long parent name's stem skips modifiers
  ("Great Mytbridge" -> "Mytbridge Ings", not "Great Holme").
- Roots and affix patterns in the word budget (`PN.attachExtra`, `PN.extraKeys`, from the finished name, so a reload
  counts the same): the root of each word from the inventory ("^myt", plural folded: Fork / Forks one word), the
  affix family (the template's first literal word: "%under", "%on", "%north") and, for a rare template, the template
  itself ("%!%s-under-%m": once per map; the most literal match wins, "X-under-Edge" is not "%s-under-%m"). The budget's
  neighbourhood rule (`NW.setTowns`, `NW.HOOD` 7): a non-SOFT key is never used again among a town's 7 nearest towns
  nor within 5 km, besides the cap of one per 8 towns. A composed offshoot form skips its parent's keys; a generated
  one pays for every root ("Mytsands" next to Mytmere is refused).
- Feature qualifiers (`featureOk`): a river / lake / mountain / bay stem appears in at most two names, the second only as
  a qualifier after a qualifier, one whole-name form per feature ("Port Big Sandy" then no "Big Sandy Valley"; "Mount
  Spruce" then no "South Spruce Valley"). A bare one-word whole name (usa Narrows, Divide, Summit) takes the town's
  name in front ("Ashford Narrows").
- Dialects: `compat` per language (en saxon:norse, celtic:gaelic, celtic:welsh; usa east:mid, mid:west; de nord:mitte,
  mitte:sued; fr nord / sud with centre; nl / sv / nb none): two grouped parts of one name come from one group or a listed
  pair. en's celtic split into gaelic (Burn, Glen, Strath, Ard, Ros, Inver-, Kil-), welsh (Pol, Pen, Bryn, Nant, Tre-,
  Llan-, coed, more, wyn, garth, glas, maen) and celtic (Aber-, Dun, Tor), with gaelic / welsh anchors. Registers: `+f`
  marks a stem fragment (Ac, Myt, Twy, Wel ...), `+w` a generic that wants a whole word before it (-bottom, -edge, -side,
  -water, -grove, -hill, -head, -hall, -marsh, -heath, -moor, -sands, -ness, -naze, -port, -haven, -wood); a fragment or
  a personal name never takes one ("Acbottom" -> "Wheatbottom").
- Tests: test_namefix.lua (7). Ported to the name lab (gen.js) with NEXT_PHASE_BRIEF 53 (check_port 2844 / 2844).

##### Name shapes chosen per map (2026-10-14; NEXT_PHASE_BRIEF 53 Part A; review names/review/REVIEW_ANSWERS.md; in game: TESTING.md "Climate-led names" step 11)

Run 1729 framed 11 of 16 names: each town scored stem, generic and affix together. `ot_placename.assign` now plans the
map first, then fills each town's shape.

- Shapes (`planShapes`): per language `shapes` (ot_placename_lang; the review's Q1 table: en single .05, separate .05,
  qualifier .06, frame .03, saint .02, whole .02, civic .02; usa separate .35, personal .15, qualifier .05, saint .02,
  whole .08, civic .05; de / nl / sv / nb mostly plain with joined qualifiers; fr frame .15, saint .15, article .10;
  it / es / pt frame .10, saint .20, article .10; ja qualifier .06, whole .02); count = floor(towns x share + seeded u),
  never above (share + 0.05) x towns nor the forms the language has. Handed out by claim (the affix's raw fit): whole
  names first (the big cues), then qualifiers, frames (one per river, each template once per 32 towns), saints, civic
  names, articles, single elements; the rest plain, and the 40 % with the weakest site claim quiet (parts naming a
  feature rank QUIET_PEN lower). A shape that finds no name in 200 candidates goes plain (`miss=`).
- Qualifiers (`+q`): twins (two towns within 6 km, the smaller takes the other's base: Upper / Lower by the river's
  course or 25 m of height, Little by a 1.6x size, else its compass side of the other), one Upper / Lower on the town's
  granted river stem ("Lower Glavenmouth"), site ones (Kings / New / Long X, joined Ober- / Unter-). Map-side compass
  forms (%D) never. The satellite pass ("Little X" beside a big town) is folded into the twins.
- Frames on a common base (`common`: Newton, Sutton, Kirkby ...; de Neustadt ...; nl Bergen ...) or a base already on
  the map ("Ashford" and "Ashford-on-Dart", which skips the original's words), one-word bases only, never the base's own
  river; fr / it / es / pt frame any base. Articles: `articles` by the generic's gender ("La Hoya", "Le Val", "L'Isola").
  Single: `+o` generics alone ("Holt", "Hagen", "Torre").
- Named-feature budget (`featureGrants`): each river, lake, peak, bay in one name per 6 towns along it (2 at most), the
  claim cue x uniqueness x size; the strongest gets its stem first (FEAT_FIRST), the others may not use it (`left=`).
- Words: at most 3 per name, at most 2 features (`ideas`); en at most 1.35 per name on average, usa 1.65 (`words`,
  pro rata while naming). Roots once per 12 towns (`NW.ROOT_PER`).
- Dialect areas (`regions` / `dialectAt`, replacing the anchors): a border along the main valley's towns (else the
  range's, else across the longer extent; moved to the median when one side is empty), the coast / east side Norse, the
  core Saxon, with three areas (10+ towns, seeded 60 %) the core side's far quarter Gaelic or Welsh; own group x1.9,
  Celtic with its partners x1.7, others x0.3 and -1.5; 20 % of towns borrow the neighbouring area; hybrids (Saxon +
  Norse) only within 1.5 km of a border. Lakes -water / tarn in the Norse area, -mere in the Saxon; the peak a Fell or a
  Down. New Gaelic / Welsh +c stems and Bal-.
- Logs: `NAMES shapes quota= used= frames= whole= twins= quiet= towns= miss= left=`, `shape=` on NAME lines.
- Lab: gen.js carries §50 and §53; check_port 2844 / 2844 then, 3792 / 3792 with Part B (golden rows compare the shape too).
- Tests: test_shapegates.lua (Q7 gates over 4-24 seeds x 4 presets x 4 climates for en / usa, 2 climates for the other
  languages; dialect areas; twins; the feature budget; the plan's counts; the twin cap); test_nameshape (the compass
  test rewritten: never by the map's side), test_placename (per language, 300 / 1000 towns), test_namefix (samples
  print the shapes).

##### Name shapes chosen per map, Part B: layers, climate tables, created towns, the name lab (2026-10-14; NEXT_PHASE_BRIEF 53 Part B; review names/review/REVIEW_ANSWERS.md Q3, Q6, Q8; in game: TESTING.md "Climate-led names" step 12)

- Settlement layers (`layers` / `oldness` / `yearLayer`, review Q3): each town at map start is old (LAYER_OLD 35 %), late
  (LAYER_LATE 25 %, 30 % from 1900) or middle by its oldness: size share x LAYER_CAP_K + its best LAYER_SITE claim (ford,
  confluence, mouth 1; bridge, twin .8; market .9; big .6; church .5), +0.1 for a character town; ties by id. Per
  language `layers` lists the raw gens / affixes each layer prefers (en old: Saxon -ham / -ton / -ley, Norse -by / -thorpe,
  the Celtic prefixes; middle: Market / Kings / Bishops X, Magna, St X, -field / -hurst; late: -side / -haven / New X /
  -on-Sea / X Junction; usa old: -ton / -ford / Mount / Fort / Ferry / Landing, middle: -ville / -burg / City / Springs
  and the personal stems (+p), late: Junction / Center / Heights / Park / -view); a part of the town's layer LAYER_ON
  higher, of other layers only LAYER_OFF lower (`layerAdj`, rankParts and the plan's affix claims). Rivers and peaks keep
  the oldest names (the river / peak lists). A created town is middle before YEAR_LATE (1945), late after. Logs: `layers=`
  on `NAMES shapes`, `layer=` on NAME lines.
- Civic names (Junction / Station / Center, +v): only on a late town that is no natural confluence (confluence or twin
  claim CIVIC_CONFLUENCE, `q.noCivic`); usa `_Junction` / `%t_Junction` lost their confluence tag; en got `%s_Junction`.
- Climate shape tables (`climateOf`, review Q6): per language and climate `climate = { shapes, words, boost, veto,
  shared, saints, areas, three, group }`. en tropical: separate .35 (Port X, X Bay / Point / Cay / Key, X Estate / Pen /
  Hall, Mount X, Xtown of the @colonial given names: Carolinetown), saint .05 with Caribbean saints, words 1.5, the
  areas core Saxon / coast colonial / edge Gaelic (no Norse), veto -thorpe / -by / -ham / -toft / -thwaite ...; en dry:
  Downs, Crossing, Creek, Mount X, Wells; en subarctic: Fort X (@post surnames: Fort Fraser), X Landing / Portage /
  Rapids / Narrows, Glen- / Strath- / Kyle- (Gaelic), always three areas with the Gaelic edge. usa tropical Port / Bay /
  Point / Key; usa dry: Springs / Wells / Tank / Mesa / Butte first, rock colours (Painted, Vermilion, Ochre) and the
  Spanish settler group (`group = "spanish:.3"`: the 30 % of towns farthest along a seeded direction take @spanish parts
  GLAYER_K higher, every other town DIALECT_PEN lower: Agua Dulce, Arroyo Seco, Los Alamos, Las Lomas, San Felipe, Santa
  Rita; +x parts meet only their own group, the generic's gender agrees); usa subarctic Fort / Landing / Portage /
  Rapids / Narrows; fr / it / es / pt tropical saint .25-.30; sv / nb subarctic -vik / -fjärd / -fjord / -fjäll / -fjell
  first. A boost form ranks CLIMATE_BOOST higher; on a dry map a water part the site has DRY_WATER higher. No invented
  Native-derived words: English, Spanish and French forms only.
- Created towns by the game year (ot_offname `ERAS`, `eraMul`, `worksShares`, cond `b1920` = before): Works before 1920
  weigh "-Works" / Ironworks / Foundry / Forge / Colliery forms ERA_K higher and the Ironbridge-style cue class x ERA_CUE;
  1840-1945 Junction / Station / Sidings / Yard / Depot / New X; districts from 1945 Heights / Park / Estate(s) / Acres /
  Gardens / Village (en got "%s Estate@y1945", "%s Gardens@y1945", "%s Junction@y1840+b1945"; usa "%s Estates@y1945").
  The generated candidates (related / works / claimName) take the year's layer.
- Districts' compass words relate to the parent: "North X" only on the parent's north side (ot_offname.compass), never on
  a parent with a compass or size word already ("South Ashby"); no triple letters in composed names ("Abbottton").
- Leftover feature claims (Part A item 2): `featureGrants` also returns the list; stateless `leftClaim(waters, names, x,
  y, { own, cap, maxD })`: the nearest saved water entry (ot_saved `rv`) of the town whose stem its name doesn't carry and
  that fewer than `cap` names carry (FEAT_CAP + 1 for districts, 1 for stops). Districts: `claimName` (the stem with a
  generic for the site kind: "Uskford", "Glavenside") joins ot_offname as `first`, pattern `feature`, taken before any
  other form while its key is unused (driver offshootName, src `claim`). Stops: driver stopName sets `site.claimName`
  (only away from the water and off bridges); ot_stopname puts it before the theme's words (rank 0.4, `claim=` on STOPNAME).
- The naming hook for strong characters (interface for the characters work): a town of `PN.assign` may carry
  `character = "<kind>"` (a string) instead of `true`. Kinds with forms (per language `charForms`, raw affixes; en, usa):
  hilltop ("-on-the-Hill", High X; usa X Heights), harbour / cove (X Cove, Port X), street (Long X, Market X; usa Grand
  X), company (New X, Port X), garden (X Garden City), island (X Isle; usa X Island), market (Market X, Kings X, X Magna;
  usa X Center), church (X St Y, Bishops X). Such a town gets the shape `character` before the whole names (one of its
  kind's forms on a one-word base; +k affixes go nowhere else); an unknown kind or a language without forms: an ordinary
  character town. The driver reads it in namesAssignGen from `characterOf(t).nameKind` (the characters work sets that
  field); NAME lines log `char=<kind>`, info `charKind`.
- Lab (names/index.html, opens from disk): mode **Whole map (plan)**: assign on a synthetic map (test_shapegates' maps:
  valley / coast / lakes / upland, the lab seed, n = Count) or an imported game log (file picker, .txt / .log / .gz: the
  last load's NAME lines with x / y, cues, river / lake by name; also in the "This map" tab, whose "Lab now" column runs
  the plan). Panels: the region rating 1-5 ("sounds like one region", stored with the shape counts), the names at their
  positions (dots by shape, a named feature's names in colour, the dialect border), the shape mix (the review's table,
  the editable target, the plan's count, what the names got), the Q7 numbers, the shape A/B test (the same base in two
  shapes where it can: "Chipton" / "Kings Chipton"). Every rating keeps its shape and layer; the Export JSON adds
  `mapRatings`, `abTests`, `byShape` (ratings, A/B wins, map scores per shape) and `shapeTargets`. gen.js ports Part B;
  check_port 3792 / 3792 (golden runs from 1905, a subarctic run, a "market" character town).
- Tests: test_shapegates.lua Part B (layers by size and site, the layers' forms, the climate tables, civic names, created
  towns by year, district compass words, leftover claims, the character hook, NAME_SAMPLES=1 samples); the Q7 gates use
  the climate's shares and words (en tropical words 1.5 + 0.05).

##### Staggered satellites (2026-10-14; NEXT_PHASE_BRIEF 51; in game: TESTING.md "Staggered satellites")

Run `2026-10-14_1927_sqot` (seed a, Quick 40 years) founded 3 satellites before year 1 and the rest in bursts (18
offshoots, 12 of them seeds). `ot_satpace` (pure) paces every founding; the driver's glue is `Driver:paceGate` (called by
satelliteDecide / worksDecide / districtDecide after their own gates, before the site search), `paceRefund`, `paceMap`,
`paceGrowDue`, `paceTurnOk` (offshoot turns only for a ready town with the slot open) and `satPaceSummary`.

- Readiness (`SP.readiness`): size >= max(start x READY 1.3-2.3, READY_MIN 260-480), seeded per town, x READY_STEP
  1.35-1.9 per offshoot the town already has (satellite, Works, districts). Start = the frame's `b0` (new: the town's
  offshoot size at its first build), else its initial capacity / 4, else its size at the first sight this session.
- Spacing (`SP.need`, `SP.slot`): growth of the map's size (sum of persons / OFFSHOOT_PB over the towns, not the mod's own;
  cached 2 s) since the mark >= SPACE_B 520 x (towns / 16)^0.5 x JITTER 0.6-1.7 (seeded per slot), or game years / 10.
  Before the first founding the mark is the towns' summed starting sizes (initial capacities / 4).
- Draw (`SP.decide`): candidates = ready towns seen within CAND_TTL_S 900 s; the highest key u^(1/w) wins (w = min(2.5,
  readiness) x 1 / (1 + the town's failed foundings)); the others `deferred`. A Simulate round (`H.simRound`): one
  founding per round (`sameRound`), the draw over the towns still to decide in it, the mark settles at the round's last
  check (`SP.observe` from `paceSeen`).
- Refund (`SP.refund`): no site, no name, not sent, refused / timed out create, seed refused or empty: the mark and count
  go back, the town is out of that slot.
- Grows (`SP.growDue`): every EVERY_K 3-5 demand builds per pod (seeded, with a phase), GROW_TOWN_F 8 % town growth
  since the pod's last growth (`s.sat.podMark`), GROW_MAP_F 0.12 x need map growth since the last pod growth anywhere.
- Saved: `sp` (EV_PACE, ot_saved `applyPace` / `normPace`), frame `b0`; old saves: no `sp` (the starting sizes), no
  `b0` (initial capacity / 4).
- Model (test_satpace): the run's 16 towns (start / end buildings), growth landing at the rounds (years 1, 4, ..., 40),
  most growth first, 15 % failed foundings: 6-9 foundings (median 7-8), the first at year 8-12, gaps 4-8 years; seed
  a's salt: 12, 16, 20, 24, 28, 32, 36, 40 (the in-game town seeds differ).
- Tests: test_satpace.lua (10); test_demand's offshoot mechanism tests run with the pacing off.

##### Held towns: no streets in created towns that don't grow (2026-10-14; NEXT_PHASE_BRIEF 52 item 3; in game: TESTING.md "Held towns")

Run `2026-10-14_1927_sqot` (203 simulated years) showed 25-33 km of "empty" street in East Hornness Engine Works and
Ashworthville, and 10.7 km in Aberdart Grange. Not built by the mod and not by Simulate (evidence in NEXT_PHASE_BRIEF 52
item 3). It was the parents' engine-built streets, read from the created town's centre: ALLTOWN's `emptyLen` counted only
the town's own houses.
- `ot_assess.growthEmpty(caps)`: size factors all <= 1 (+0.001) and actual >= GROWTH_FULL 0.95 x target, i.e. the town
  never grew and its initial capacity is built. Bad / missing caps: false.
- `Driver:holdWhy`: `below` for a Works / district town under OFFSHOOT_HOLD_B 120 buildings, `noGrowth` for any town
  with empty growth (`D.HOLD_EMPTY_GROWTH`; an original town's head start excepted). Assess computes it on every
  unforced check and stores it as `s.hold`. A held town that needs streets ends as `room`. A held town gets no offshoot
  turn either. `OFFSHOOT event=hold town= why= edges= buildings= until=` is logged once per verdict and street count.
- Send guard (`D.HOLD_GUARD`, `Driver:heldHits`): new edges within HOLD_GUARD_R 1500 m of a held created town are
  checked with E.closestTown. The guard reads at most HOLD_GUARD_MAX 64 towns, and a created town not checked yet
  counts as held. Edges in such a town's land are excluded for the planning town. A town plan is planned again
  without them (HOLD_REPLANS 2), then refused. Satellite pods, lanes ahead, lead-outs, bridges and frames take their
  own refusal path. The founding link to its own target is exempt. Log: `OFFSHOOT event=hold why=guard:<why> by=`.
  The demand planner already keeps to the engine's ownership (ot_gap `owner`); the guard is for the plans made
  without gaps.
- Simulate: its build rounds start unforced jobs, so the hold applies there. Rounds and fills only take towns that
  grew (`rate > 0`). Dev Grow now / forest-lane tests stay forced (explicit dev commands).
- Dev ALLTOWN: `bareLen=` (no house of any measured town), `foreignLen=` (only other towns' houses) and `modLen=`
  (locked, or built by the main driver this session; locked marks only part of the mod's streets). `emptyLen` keeps
  its meaning, so it stays comparable with earlier runs.
- Tests: test_hold.lua (9), test_runner "streetMeasures".

##### Strong characters, roundabout town, densify (2026-10-14; NEXT_PHASE_BRIEF 54; CHARACTERS_BRIEF.md; in game: TESTING.md "Strong characters")

User: "identifying more characters with strong preference, like deep forest ... 1 or 2 on a map depending on how many
cities ... very distinct and really push the parameters"; "one character could push roundabouts more"; "some others
should get dense at some point" (§52 item 2); "lets also build strong characters and roundabout town".

- **Framework** (`ot_character.lua`, pure): a registry like `ot_motif` (`CH.register`, `CH.IDS` append-only: frame `ck`,
  map record `cm`). Each kind: `eligible(site)` 0..1 + why, `style` (its street style, before the site draw and the
  diversity penalty), `form` (an `ot_form` def, forced through `inputs.charForm` ahead of every other form), `apply` /
  `post` (planner knobs; blocks never below `ot_style.MIN_BLOCK`, the planner's own radius / grade checks untouched),
  `motifs` (`prefer` x4 and the first slot, `forbid` never drawn: `ot_motif.pick`), `offshoots` (false: no district /
  Works), `levels` ("early" / "off"), `names` (the naming hook). The site record: terrain stats + wide survey + `ot_site`
  features + a cheap probe (`CH.probe`: 4 rings x 16 heights / water, the valley axis' floor and sides), the nearest
  heavy / medium industry, the era, the region.
- **Kinds built** (site test -> what it pushes):

  | Kind | Site test | Pushes |
  |---|---|---|
  | deep_forest | its own pick (`ot_forest deepPick`, frame `fd`, 3 per map), unchanged | listed for the index, logs and names |
  | hilltop | the 600 m disc's summit within 380 m, 25 m+ over the 1000 / 1500 m rings, lower in 11+ of 16 directions | MED hill, the summit as centre, clustered compact (front 0.35), blocks x0.85 (40 x 30), curve 35, contour 1, grade limit 0.14, 5 spokes / rings every 110 m, small templates, hill climb / switchbacks preferred, early levels, no offshoots |
  | clifftop | `ot_terrain` cliff toward a sea / lake: brink 18 m+ above the water within 420 m | a shore strip (kaMul 1.8, kbMul 0.6, depth cap 100-160 m), the promenade, blocks 0.75 deep, grade limit 0.07 (nothing down the cliff), headland street preferred |
  | harbour_cove | sea / lake within 350 m, the 300 m ring 15-50 % wet in one arc, the 600 m ring opening out, steep sides | MED hill (Nordic / JP by region), clustered (front 0.85), blocks x0.75 / 0.8, small templates, water premium 0.6 over 300 m, harbour crescent / fishing village preferred, early levels |
  | waterfront | a river through the disc, within 220 m | EU extension (NA grid / JP), linear along the river (ribbon 1.6), gridness 0.85, water premium 0.45, the river bridge always tried, from half the size |
  | street_village | a valley (`dirRelief`), its floor along the axis 60 %+ within 20 m of the centre, the sides 12 m+ up | EU organic (NA grid in the US), linear kaMul 2.4 / kbMul 0.4, 2 spokes, rings every 900 m, plots x1.3 long, no fishbone / green / ring road / pods, no offshoots |
  | company_town | a heavy / medium industry within ~1.7 / ~1.5 km (full within 1 km, §68), mean slope <= 0.05; full chance to 1940, half by 1970 | strict NA grid of terraced rows (110 x 44 m), the axis to the works, arterials every 4, collectors every 2, all locked, workers' terraces preferred, early levels, no offshoots |
  | garden_city | open >= 0.65, the probe 70 %+ flat, no coast, from 1900 (full from 1915) | EU extension: 8 radial boulevards, rings every 220 m, blocks x1.35 / 1.3 (low density), 3 crescents, 7+ greens (a green belt), ring road / village green preferred, no level weights |
  | island_town | `ot_site` island with a closed traced coast of 1.2-9 km | a shore form wrapping the island (front 2.4, kaMul 2.0, kbMul 1.2), the ring road along the shore, blocks x0.85, harbour / tip motifs preferred, early levels, no offshoots |
  | roundabout_town | flat open (open 0.6+, flat 0.65+), the one-way ring geometry loaded, from 1950 (France 1940, outside Europe 1955) | EU extension (NA grid in the US), cross form, 6 spokes / rings every 240 m (grid: arterials every 3, the lattice ahead), one-way rings at its new crossings (below) |

  Skipped: moorland hamlets (a "high and flat" test needs the height above the water relative to the map, unreliable
  across maps), spa / crescent town (gentle slope + water or park: no reliable park read; the crescent motif already
  covers the look), mountain pass (a saddle between peaks is not reliable from the 600 m disc and the 2 km survey).
- **Selection** (`CH.select`; driver phase "chars"): once per new map, before the names and the head start: every own
  town's terrain read (the names survey reuses it), the probe, the scores; quota 1 per ~8 own towns (rounded; 1 below 10
  towns, at most 3); the highest score wins (x up to 1.3 for a kind few of the map's towns qualify for; a seeded
  jitter breaks ties); never one kind twice, never within 3 km of another pick, never a town of 6000+ persons at the
  start (a metropolis), never a created town, never a town framed as secluded. Saved at once (`EV_CHARS` -> `cm`), and
  each town's kind on its frame at its first build (`ck`; the frame keeps the kind's style too). A reload reads `cm`
  (`CHARACTER pick src=saved`); a save from before has no `cm` and never gets kinds (`why=oldMap`).
- **Secluded towns** (`ot_map.characters`): stay a separate mechanism (an extreme form for the most remote towns). The
  kinds are picked first; a picked town is never a secluded one and the secluded quota passes to the next most remote
  town (`characterOf` treats it as `fixed = false`); a town framed as secluded gets no kind. A kind town is never deep
  forest (`FOREST why=character`) and never a coastal hugger (left out of the ranking). It gets one more head-start
  round, like a secluded town.
- **Roundabout town** (`ot_ring.lua`, pure): after the plan, before the pre-check, a new node of the increment where 3
  or 4 of its new streets meet (arms 55 deg+ apart; never an existing node) becomes a one-way ring when the spot is
  empty (no existing node / street, no other new street within the ring + 18 m: reserved while empty land at the
  frontier) and the arms keep 22 m+ beyond it: each arm's Hermite curve cut where it meets the ring, the arcs
  counter-clockwise between the arm points (ring nodes between when an arc would exceed 110 deg), template
  `town_new_one_way_small` (square_roundabouts' own ring template and sizes: XS 19 m for a crossing of minor streets,
  S 24 m main x main, M 29 m with large arms; `RG.load` via the presence file). Every new node gets a config in
  `ot_proposal.build`: a node with a one-way segment the engine's one-way ring pattern (`junctionConnsDir`: ring in ->
  ring out, ring in -> arm (outer lane), arm -> ring out), "in" where the edge's node1 is the node. Seeded share: 0.9 of
  the main x main crossings, 0.35 of the minor ones, 2 per increment at most. Locked (the ring keys). All or nothing: a
  refused pre-check sends the plain crossing again (`RG.strip`, `RB event=refused`); after 3 refusals no more rings in
  that town this session. Before 1940 (no one-way town street) or without square_roundabouts: `RB event=off why=era |
  noRoundabouts...`, and the kind is not picked without the mod. Offline: 4 rings in 10 increments of a flat EU town.
  On by default (`RG.ON`, `D.RINGS`): a one-way town street ring with this lane pattern built without a crash in
  Showcase v7 (findings towns.md); whether traffic drives it one way is the showcase step's question. (Since §56,
  2026-10-14: four sizes mini / s / m / l by the crossing's class instead of XS / S / M, the shares 0.95 / 0.5 plus
  gateways and pairs, up to 4 a plan, a housed front, and every other town at its era / region rate: 6.3 "Roundabout
  variety and organic ring roads".)
- **Densify** (non-exclusive trait): drawn once per town when it first reads mature (`ot_assess.maturity` >= 0.5) on a
  map with strong characters: p = 0.33 x form (linear 0.3, sprawling 0.55, fingers 0.7, shore 0.5, clustered 1.3,
  radiating 1.2) x size rank (0.7-1.4) x centrality (0.75-1.25) x rail station near (1.4), 0.05-0.85; never a kind,
  deep, secluded, coastal-hug, created or metropolis town. Saved on the frame (`dz` 1 / 2, `EV_DENSE`). Once active: the
  mature hold at 42 % free lots (60 %) and its cap at 0.06 of the demand (0.18), level weights aiming at 8 persons per
  building with strength 0.75+ (cleared only from 11; levels 3 / 4 only exist from 1950 / 1990, the API is town-wide),
  new pieces' blocks x0.75 and denser arterials / collectors / rings, no new meadows, upward doses (DevelopAt in the
  core) from 300 buildings with half the demand build cut. Sprawl towns unchanged. Offline (700 draws): 30 %, linear 16
  % vs clustered 37 %; a yearly model: persons per building 5.7 -> 7.7 after maturity vs 5.7 -> 6.3 for a sprawl town.
- **Setting** "Strong town characters" On / Off (mod.json `strong_characters`, 13 languages, default On for the next
  test iteration; the release default is On, decided by the user 2026-10-15). Off: no picks (`CHARACTER pick on=false why=setting`),
  saved kinds ignored, no densify; deep forest towns stay as they were (their own pick, unaffected by the setting).
- **Logs**: `CHARACTER pick on= map= towns= count= picked= kinds= src= rings= read= s=`, per town `CHARACTER town= name=
  event=pick kind= score= why= applied=pending|no:<skip> best= top=` (picked towns logged, the rest debug), `CHARACTER
  ... event=apply kind= applied=yes|partial:<what> style= form= shape= block= motifs= rings=` when the style resolves,
  deep forest picks `CHARACTER ... kind=deep_forest` (debug); STYLE / PLAN `char=`, PLAN `roundabouts=` (built so far);
  `RB event=ring|skip|refused|built|off`; `DENSIFY event=draw|apply on= why= core= levels= pb=`; dev ALLTOWN `char=
  roundabouts=`.
- **Naming hook** (not wired: the naming phase owns it): `Driver:characterNameCue(t)` -> `{ kind, tag, words }`
  (`CH.nameCue`: hilltop hill / "-on-the-Hill", "Mount" ...; clifftop cliff; harbour_cove cove / "Cove", "Harbour",
  "Haven"; waterfront river / "Wharf", "Bridge"; street_village valley / "Street", "-in-the-Vale"; company_town works /
  "Works", "Colliery"; garden_city garden / "Garden City", "Green"; island_town island / "Isle", "Holm"; roundabout_town
  newtown / "New", "Park"; deep_forest forest / "Wood", "Holt"). The chars phase now runs before the names phase, so the
  picks exist at name assignment. Wired 2026-10-14 with the names Part B: `characterOf(t).nameKind` (`CH.NAME_KIND`:
  hilltop / clifftop -> hilltop, harbour_cove -> cove, waterfront -> harbour, street_village -> street, company_town ->
  company, garden_city -> garden, island_town -> island, roundabout_town -> market; `character` stays false), read by
  `namesAssignGen`.
- **Dev**: Town tab "Character (main mod)": "Force character" with a kind picker (`-`, the kinds, `densify`;
  `CHARDEV`); showcase item "Roundabout town" (`RB_TOWN`, EU extension, startJob `charKind`) beside the probe's "EU ext
  roundabout" when square_roundabouts is installed.
- Two single-town tests in test_demand (head start rounds, level weights) run with the setting Off: their one town
  would be picked (a garden city: one more head-start round, no level weights), which test_character covers.
- Tests: `test_character.lua` (21: site tests, eight signatures, rings, selection, save, apply, unchanged, densify,
  driver phase), dev `test_runner` (+1), `test_layout` / `test_showcase` counts +1 town.
- Not done: moorland / spa / mountain pass; several bridges per waterfront town
  (one bridge, always tried); a central green for the garden city (the greens are its belt); densify's core-only level
  weights (the API is town-wide).

##### Roundabout variety and organic ring roads (2026-10-14; NEXT_PHASE_BRIEF 56; in game: TESTING.md "Combined test iteration" step 1)

User on the showcase run `2026-10-14_2150_sqot-dev`: "eu organic looks strange with the big equal circles on the
outside"; "roundabout town - it would be nice if there were different sized roundabouts used. also, roundabouts
shouldnt be limited to just that roundabout town. roundabout town just should use more of them. e.g. perhaps a pair of
round abouts added at same time on opposite parts of a city, or street, for a unique intentional effect."

What the run showed: EU organic (town 5561, twin / sprawling) had 18 ring_road and 18 crescent picks over 16 forced
increments, the ring road at R 436 (`tees=57`) plus the grower's own rings every ~300 m: long equal-radius arcs west
and south far ahead of the houses with evenly spaced stubs (a ladder ring), and a cut-off grid patch east (the
EU_EXTENSION outer zone switching on at one radius). The roundabout town (7477) built 5 rings, all XS / S (R 19 / 24),
many `draw:x>=0.35` skips, rings at the frontier with arms into empty land, 1 refused (Construction Not Possible,
collisions 0; the plain crossing went out instead), and `emptyLen` 2 -> 7 km: the strong cross arms (reach 1, blocks
121 x 88, arm fill lead 2 blocks + the 400 m lead limit) ran ~1 km out, deep-arm back rows closed empty rectangles
(west) and the spine with its lanes made the zig-zag leads (south-west).

Done (ot_ring, ot_driver ringMark, ot_character, ot_grow_organic, ot_motif_town, ot_crescent, ot_select, ot_style,
ot_saved):

- **Sizes** (`RG.CLASSES`): square_roundabouts' own radius list (`geom.RADII`, island radius, `sqrb_radius`) through
  `RG.load`; the ring's centreline radius `a` = island + 9 m (the one-way small street, lanes 2 offset): mini R 17
  (island 8: the smallest the geometry gives; the brief's R 12-15 is below it), s R 19 / 24, m R 34 / 39, l R 49 / 59.
  `RG.classOf`: l at a gateway with two main arms, main x main with wide (large template) arms, or 3 main arms; m
  main x main, or a main arm at a gateway / with a medium one / of 4 arms; s one main arm or two medium; mini a
  crossing of minor streets. The radius within the class is seeded; smaller sizes are tried when the room is short
  (`armShort`, `nearNew`, ...). A gateway: a crossing with a main arm 0.8 x the houses' radius out (at least 140 m).
  **Longer arms** (`RG.extendArms`, follow-up): before the sizes are tried, an arm shorter than the largest size + 28
  m whose far end is a new node with exactly one more new edge going on within 35 deg (the plan's split / tap point,
  no junction) is merged with it into one Hermite edge (the node dropped; up to 3 merges per arm), and the arms are
  checked against the houses again; no size fits: the plain arms are put back. Never an existing node.
- **Rates** (`RG.rate`, every town): the major-crossing share by region at full era: France 0.16, EU 0.09, MED 0.08,
  Nordic 0.06, Oceania 0.08, RU 0.04, East Asia / Asia 0.03, US 0.02, JP 0.015, Mixed 0.06; none before 1940 (no one-way
  town street), x 0.15 until 1960, rising to the full rate by 1975; minor crossings x 0.15; gateways x 1.6; none in JP
  dense towns. At most 2 rings a plan and 4 per town (counted in the graph: `RG.existing`, one-way small street
  clusters), 260 m apart. Not on satellite / bridge / lead / Works / frame plans. A town's reason for none is a debug
  `RB event=off why=` line (the roundabout town's a normal line).
- **Roundabout town** (`RG.TOWN` via `RG.townShare`): major 0.95, minor 0.5, gateways 1, pairs 0.7 (0.6 since §57, with its hubs; any crossings), up
  to 4 a plan, 110 m apart. Its empty leads: a housed front of 1.25 blocks (`housedLead`, no street farther from a
  street with houses), no deep-arm back rows (`noDeepArms`), blocks x1.35 / x1.3 (room for m / l rings), the NA grid
  variant's lattice 3 deep (was 6). A mild arm reach starved the plan offline, so the reach stays strong.
- **Pairs** (`RG.pairOf`): in one increment, two crossings 120 m+ apart, "street" (a major arm of each points at the
  other within 22 deg: the two ends of one street) before "opposite" (120 deg+ apart round the centre, both beyond half
  the houses' radius); seeded draw `share.pair` (ordinary towns 1.5 x the rate, at most 0.4; major crossings only);
  the same size for both (the smaller class, the first ring's radius first). Both or neither: the second refused puts
  the increment back as before the first. A refused pre-check strips all rings of the increment (both of a pair).
  `RB event=pair kind= ok= size= R= d= why=` (not placed: debug). **Deferred pairs** (follow-up: a pair within one
  increment was rare, the increments are local): a ring placed alone at a major crossing may reserve its partner
  (the same pair draw): its centre, the heading of its most outward major arm, its radius and 4 plans
  (`RG.PAIR_WAIT`), saved on the frame (`px py ph pr pn`, additive; event `square_organic_towns.pair`). A later plan
  of the town places the partner first, without a draw, at a crossing 120-700 m on along that heading (within 30 deg)
  with an arm pointing back, the same radius first; each plan without one counts down, at 0 it lapses (`RB event=pair
  deferred=true ok= why=none|expired:...`, `RB event=pairWait` when reserved). A refused pre-check of the reserving
  ring drops the reservation.
- **No arms into empty land** (`RG.armsOk`): the crossing and every arm's far end within `RG.ARM_LEAD` 200 m of a
  street with houses (the snapshot's housed edges, `ot_select.housedIndexM`); `skip why=emptyArm`.
- **Organic ring geometry** (`ot_style.ORGANIC_RINGS`, `style.ringWobble`): only for towns without a frame and towns
  framed with it (frame field `og = 1`, additive); a town framed before keeps its even rings. The grower: ring gaps
  0.75-1.3 x ringEvery, two consecutive gaps 0.15 x apart at least; each ring's own radius per spoke (x 1 +- 0.14, less
  for gridded styles; the old wall line stays round); arcs wobbling 0.12 x ringEvery; the ring nearest the ring road
  motif's radius left out (one ring there, not two side by side); secondary radials jittered 0.35+ and 15 % left out
  (no evenly spaced stubs). The ring road: its radius R x (1 + harmonics 2 / 3 / 5, ~5 / 3.5 / 1.2 %) round the town
  (`ot_motif_town.ringRad`; the scan, stubs, joints and measure follow the profile; `rr` stays the mean). Crescents: on
  a seeded curve up to 10 % outward of the circle (`ot_crescent.radiusFn`), the plan cut where it meets the curve.
  **Ring lead** (`ot_select.RING_LEAD_M` 160 m): an organic ring arc beyond the wall line, the ring road motif's pieces
  and crescent arcs only within 160 m of a street with houses (PLAN `ringHeld=`). **Zone blend** (`ot_style.zone`):
  the outer zone blends in over 1.5 x ringEvery beyond its `from` in 3 steps (gridness, jitter, curve, blocks).
- **Other styles**: MED hill (rings every 150 m), EU extension / garden city / roundabout town (220-300 m, gridness 0.8:
  half the wobble) and metropolis radial variants (a copy of the style) get the same geometry; grid growers have no
  rings. At most one outer ring: the ring road replaces the grower's ring beside it, and every ring waits for the
  houses.
- **Logs**: `RB event=ring size=<mini|s|m|l> R= ring= wanted= gate= pair= roundaboutTown= rate=`, `RB event=pair`,
  `RB event=skip why= class=` (debug), PLAN `roundabouts=` (built this session) and `ringHeld=`, ALLTOWN `roundabouts=`.
- **Size mix offline** (`test_rings` "size mix", 8 fixture towns x 10 plans, houses keeping up): roundabout towns 69
  rings, mini 12 / s 24 / m 25 / l 8; of the 37 at main x main crossings or gateways m 25 (68 %), l 8 (22 %), s 4; 9
  pairs (4 deferred); 41 arms extended. Ordinary EU towns (every eligible crossing drawn): 38 rings, mini 24 / s 7 /
  m 3 / l 4. Before the follow-up: no m at all, wanted l fell back to s.
- Tests: `test_rings.lua` (18: sizes and their order, size by class and room, every size one-way / CCW / configured /
  no live junction / no -0, rates by era and region, the roundabout town's higher count with several sizes, ordinary
  towns spaced, pairs street / opposite, both or neither, no empty arms, the organic flag and frame, wobble and uneven
  spacing, the ring road's profile and no grower ring beside it, ring lead, zone blend, crescent curve; the size mix,
  longer arms (merged through plain nodes, never through a junction), deferred pairs and their saved field).
- Not done: rings smaller than R 17 (below square_roundabouts' geometry); a ring reserved in the master plan (the
  plan's parallel streets kept off its footprint: the longer arms were enough offline, `nearNew` stays the main
  reason an l falls back); the cause of the one refused ring (no SEND / DIAG lines in the log for it).

##### Roundabout town hubs (2026-10-14; NEXT_PHASE_BRIEF 57; in game: TESTING.md "Combined test iteration" step 1)

Showcase run `2026-10-14_2237_sqot-dev` (load 1) and the seed-a loads 2-4. Causes and numbers: NEXT_PHASE_BRIEF 57.

- **Ring hubs** (`ot_ring`, the roundabout town only: `RG.TOWN.hubs`): `RG.hubSites(inc)` lists the plan's new
  streets' continuation nodes (exactly two new edges, a turn of 35 deg at most) and the middles of new edges of 92 m+;
  `RG.addHub` adds 1-2 new straight arms across the street (`HUB_STUB` 55 / 62 / 78 / 95 m by class), each clear of
  every other street (16 m) and node (26 m), its end within `ARM_LEAD` of a housed street and at most a 9 % grade, the
  long edge split first; then `RG.mark`'s `try` places the ring (its sizes downward, the arms extended through plain
  nodes as before). A site keeps `HUB_GAP_MIN..MAX` 250-450 m (seeded per site) from every ring of the town and lies
  within `HUB_HOUSED` 170 m of a housed street; roomy gateways (`RG.room` 80 m+) first, then main / medium / small
  streets, continuation nodes before splits; up to `HUB_PER_INC` 2 a plan, `HUB_TRIES` 6 sites. Class (`RG.hubClass`):
  l at a gateway on a main / medium street, m on a main street (a medium one at `HUB_MEDIUM_M` 0.5), s on a medium one,
  mini / s on a small one (`HUB_MINI` 0.5). No size fits: the plan as before the hub (the arms out again). The hub arms
  are plain new streets (class one below the street's, the town's own templates), not locked; the ring's arcs locked as
  before; the ring's `ringUndo` is the plan before the hub (a refused pre-check sends the plain plan).
- **Twins**: a hub reserves its twin at `share.pair` (0.6 in the roundabout town): along its street outward (`k` 1) or
  across the town toward and past the centre (`k` 2, `PAIR_REACH_OPP` 1600 m, saved as frame field `pk`, additive),
  `PAIR_WAIT_HUB` 6 plans. A later plan takes a candidate crossing in the window (a street twin's arm pointing back) or
  plants a hub there (`hub=true`), the first ring's radius first.
- **Ordinary towns**: no hubs; pair share `PAIR_K` 2 (max 0.3), still drawn per pair; the US late rate (`RATE_LATE`
  0.05 by 1995, Oceania 0.1).
- **Forced increments** (`D.FORCED_EMPTY`, driver plan stage): the own empty budget with `ownEmptyFloor` =
  `core.OWN_EMPTY_MIN` edges, and `limits.sparse`: `ot_select.SPARSE` holds a piece whose ends or middle lie among
  streets (150 m round, 300 m+ of street) with under 1.5 houses per 100 m, in a town with 1.2 km+ and 10 %+ unhoused
  street and 3+ houses per 100 m overall (PLAN `sparseHeld=`). Demand plans: unchanged. (§59: when the hold would leave
  the increment under `SPARSE_RELAX_EDGES` 4 edges, the held pieces come, the cheapest first, up to 4 edges; PLAN
  `sparseRelax=true`.)
- **Look zone** (`ot_style.LOOK_ZONE`): an organic town with `ringWobble` and a grid look above `LOOK_CORE` 0.35: its
  core look 0.35 (saved `gl` as before), the look (at most `LOOK_ZONE_MAX` 0.5) as an outer zone of its own style from
  `LOOK_FROM` 320 m (`outer.lookZone`), blended by `ZONE_BLEND`; a town with an outer zone of its own gives it the look.
- **Strong characters calibrated on seed a** (load 2: 0 picks of 16): harbour cove from the coast reading
  (`COVE_D` 380, `COVE_COAST` 0.45, steepness from p95 slope / wide relief / rough share, the probe's bay pattern
  `COVE_BAY_K` 1.15, wet > `COVE_OPEN` 0.6 on the 300 m ring: no), garden city `GARDEN_YEAR` 1895-1905 and
  (0.25 + 0.75 open x flat) x era, `GARDEN_OPEN` 0.55, waterfront `RIVER_D` 320, an unclosed island from 12+ wet rays
  (score up to 0.7), hilltop `HILL_RISE` 20 / `HILL_DIRS` 10, the roundabout town (0.3 + 0.7 open x flat) x era and
  `KIND_W` 1.5 in the ranking. Every kind's score and why in the CHARACTER town lines (`top=`, `whys=`). Densify
  `DZ_P` 0.45, `DZ_FORM` shore 0.85 / fingers 0.8 / sprawling 0.7 / linear 0.3 / clustered 1.25 / radiating 1.15.
- **Logs**: `RB event=hub`, `RB event=ring ... hub= fell=`, `RB event=pairWait ... kind=`, `RB event=pair deferred=true
  kind= hub=`, rates `%.3f`; PLAN `sparseHeld=`; CHARACTER `whys=`.
- Tests: `test_hubs.lua`, `test_forced.lua`, `test_character.lua` replays (NEXT_PHASE_BRIEF 57).
- Not done: l rings stay rare offline (crowded gateways; `fell=` shows why); no graph dump of the 2237 run, so the look
  zone as the cause of EU organic's east block is the best reading of its STYLE / PLAN lines, not proven.
- **Round 2** (in-game run `2026-10-14_2347_sqot-dev`, NEXT_PHASE_BRIEF 57b): dead-end hubs (`RG.deadEndSites`,
  `RG.addDeadEndHub`: a dead end near houses carried on by a stem to a new crossing, arm on + 1-2 across, the hub
  sliding out by `HUB_SLIDE` R + 32 / 52 / 76 / 104 m until its ring has room, `HUB_DE_MAX` 40 dead ends a plan); hubs
  try only their class's sizes (`try(..., exact)`), the wanted class drawn from `HUB_MIX` (l 0.2 / m 0.35 / s 0.3 / mini
  0.15) and stepped down only when no spot has room; street sites need the class's `RG.room`; farther-out sites
  first; gap 220-400 m; `HUB_TRIES_ALL` 14. `canDefer` always (the twin in memory, on the frame when there is one).
  `RG.clear` checks existing streets' Hermite curves too (`nearCurve`); `RB event=refused ... near=` (`RG.nearText`);
  PLAN `origins=` (`ot_select.origin` on each street, carried by ot_plan's edges; `D.originsText`).
- **Round 3** (in-game run `2026-10-15_0234_sqot-dev`, NEXT_PHASE_BRIEF 57c): dead-end hubs only at dead ends within
  `HUB_DE_HOUSED` 80 m of houses with `HUB_DE_HOUSES` 6 buildings within `HUB_DE_NEAR` 120 m; every hub centre within
  `HUB_CENTRE_LEAD` 140 m; wedge / meadow frame links held to `RING_LEAD_M` 160 m (`ot_wedge.frameStreets ringLead`;
  §59: a link up to `FAR_LINK_M` 160 m long still comes when no point of it lies farther from the houses than its farther
  tip + `FAR_SLACK_M` 15 m);
  hub twins both ways along their street, `PAIR_HUB_ALIGN` 40 deg, `PAIR_WAIT_HUB` 8, frame `pk` 1 / 2; `RG.existing`
  groups one-way edges by shared nodes (an l ring counted once).

##### LEVELS by maturity (2026-10-15; NEXT_PHASE_BRIEF 58; in game: TESTING.md "Combined test iteration" step 7)

Run `2026-10-14_2347_sqot-dev` load 3: the grown towns' 100/0/0/0 weights were never LEVELS': they came with the FILL
restores (findings towns.md), were read as the player's, and LEVELS never ran. Numbers: NEXT_PHASE_BRIEF 58.

- **Owner** (`UP.levelOwner(cur, base, ours, rows, sent)`): none / ours (the sig sent, frame `ls`, or the old `lw`
  formula) / engine (the baseline) / player (`UP.editorLike`: a row normalised to 1 or with a slider step of 0.01) /
  fill (anything else: the engine's write after a restore). Rows unknown: the old rule (custom = the player's).
- **Level maturity** `UP.levelMat(mat, buildings)`: the persons maturity (ot_assess, 1800-3600) or buildings
  `LV_B_LO`..`LV_B_HI` 200-800, the larger (a town held at level 1 houses few persons and read young for ever).
- **Phases** (`UP.levelPhase(matL, pb, densify, early, top)`):
  - young under `LV_BLEND_MAT` 0.5: nothing (no weights of ours; the fill weights stay);
  - blend 0.5-`LV_MATURE_MAT` 0.9: tilt -(1 - f) in `LV_Q` steps, raised until its level-1 share (`UP.share1`) is no
    more than the current weighted target's, so a town at the engine's weights gets none;
  - mature: `min(levelK(pb), LV_MATURE_K)`, which is 0 from 1950 (the engine's own: fill weights and blend rows
    cleared, ours above them kept until LV_CLEAR_PB) and `LV_MATURE_K_TOP2` 1 before 1950;
  - densify (drawn): `max(levelK(pb, DZ_PB_AIM), DZ_K_MIN)` x the ramp from 0.5 to `DZ_RAMP_MAT` 0.75;
  - the dense strong kinds (`early`) and the garden city / deep forest rules as before.
- **Weights** `UP.levelWeights(k, top)`: k > 0 `r^(min(l, top) - 1) / r^(top - 1)`, r = 1 + 0.6 k (top 4: the old
  rows); k < 0 `1 / r^(l - 1)`, r = 1 + `LV_HOLD_STEP` 1.5 |k|; `UP.eraTop(year)` 2 / 3 / 4 from 1950 / 1990.
- **Driver**: `levelsCheck` passes `top`, `u` / `w` (levelInfo unweighted / weighted residential rows), the densify draw
  (`densifyDrawn`, not the old "mature" gate); `levelBaseOf` / `levelOurs` read the root driver's baseline and the
  saved frame (pool drivers have none); `levelsAfterRestore` after each FILL restore (`LEVELS event=refill`).
  Saved: EV_LEVELS `{ town, k4 (-4..4), sig }`, frame `lw` / `ls`.
- **Densify**: drawn at `CH.DZ_MAT` 0.5 of the level maturity; `densifyCheck` reads `savedNow` (the dev Simulate's
  pool drivers drew none before); `densifyDemand` ramps the hold line / cap from the plain mature hold's (`CH.dzRamp`).
- Tests: test_levels58.lua; level tests in test_demand / test_round0502 (`top = 2`), test_character.
- Not done: `DZ_P` unchanged. On the 2347 map only ~16 % of the ordinary towns are expected on by year 28 and ~22 %
  by year 40, against "a third by year 20-30". The refill and the level-3 persons per building are unverified.

##### Forest era, stall fix (2026-10-15; NEXT_PHASE_BRIEF 59; in game: TESTING.md "Combined test iteration" step 8)

- **Forest era** (`ot_forest`): the hug odds' era factor `eraF` is x`EARLY_F` 1.12 up to `EARLY` 1910, back to 1 by
  1930, 1 up to `ERA` 1950, `ERA_LATE` 0.5 from 1990 (was 1 to 1920, 0.25 from 1980); the deep pick's `DEEP_ERA`
  1960 / 2010, `DEEP_ERA_LATE` 0.45 (was 1930 / 1990 / 0.35), its chance in `FO.deepChance`. P_MAX 0.95, the style /
  tier / character factors and the planner's hug rules unchanged. Forest lanes (`ot_lane.chance`) take `min(1, eraF)`.
  STYLE lines log `forestWhy=` (the draw: `p=..(s,e,t,c),u=..`).
- **Stall fix** (`ot_select`): the sparse-street hold (forced plans only) has a last relaxation, `SPARSE_RELAX_EDGES` 4
  (above, "Forced increments"). Every empty PLAN line logs `held=` (each hold's count: lead, sparse, ring, housed,
  wedge, meadow, head, edge, ind, forest, gap, zone, grove, emptyLoop, and the shape's limits env / armFill / armFront /
  wide / front, now counted in ot_select (`envHeld`, `armFrontHeld`, `wideHeld`, `frontHeld`); `D.heldText`), `emptyRun=` (empty plans in a
  row, reset by a build) and `forced=`; its job why ends `held:<top>`. After `D.STUCK_AT` 6 empty plans in a row, then
  every `D.STUCK_EVERY` 10, a `STUCK town= name= emptyRun= held= reached= blocked= excluded= ownEmpty= forced= trigger=`
  line (also without debug).
- **Frames** (`ot_wedge`): `FAR_LINK_M` / `FAR_SLACK_M` (Round 3 above).

##### Literal, context-aware names first, a little national flavor (2026-10-15; NEXT_PHASE_BRIEF 60; in game: TESTING.md "Combined test iteration" step 9)

User after run `2026-10-15_0341_sqot` (Mytham, Shaw, Padfield, Kelington, Edton, Wemmead, Trefach, Abercoed): "maybe we
just really push the simple context aware naming and then just a little nationality mixed in", then "descriptive names
and multi word names that help make it clear its context-aware". The §53 rules stay selectable (`o.rules = "s53"`, the
lab's comparison; `ot_placename.RULES` "s60" was the default until NEXT_PHASE_BRIEF 61 ("s61"), with the same Lua s53
reproduces the §53 golden names 3792 / 3792).
- **Inventory flags** (`ot_placename_lang`): `+u` opaque stems (en Ac, Myt, Twy, Wel, Sal, Lin, Chip, Stan, Bur, Wes,
  Eas ... and the Celtic fach / fawr / wyn / garth / mory ...); `+p` personal names count as opaque too; `+n` flavor
  parts (en Aber- / Inver- / Pen- / Tre- / Llan- / Kil- / Bal- / Dun- / Glen- / Strath- / Kyle-, -by / -thorpe /
  -thwaite / -toft / -wath / -gill / -holme / -caster / -beck / -burn / -kirk, Kirk, Beck, Pen, Tor, Bryn, Glen,
  Nant, the feature-carrying Celtic stems; usa -kill; de -reuth / -rode / -rath / -zell / -büttel / -leben / -siel /
  -wörth / -egg / -leiten / -halde / -stedt / -weiler / -beck / -born / -brunn; nl -drecht / -donk / -loo / -um / -werd
  / -wolde / -rade / -lo / -waard / -weerd; sv -tuna / -köping / -ryd / -red / -hult / -boda / -sta / -träsk; nb -rud /
  -seter / -vang / -tjern; fr -court / -mesnil / -ières); `+a` adjective stems and `+e` front generics that refuse
  them (usa: no "Lake Shady"); `+60` the entries this phase added (left out under s53). New readable parts: en New,
  Middle, Kings, Moor, Fen, Marsh, Reed, Rush, Sedge, Heron, Gull, Bridge, Cross, Market, Spring, Well, Mere, Stony,
  Heath, Combe, Dale, Twin and the multi-word generics `_Hill _Heath _Moor _Green _Common _End _Cross _Bridge _Wood _Dale
  _Vale _Water _Brook _Mill _Cliff _Fen _Marsh _Edge _Fell _Head _Ford _Sands`, the whole name Two Waters; usa Middle,
  Center, Union, Liberty, Stony, Mill, Ash, Beech, Alder, Rose, Orchard, `-kill`, `_Run`.
- **Rules** (`ot_placename`, s60): `OPAQUE_PEN` 2.0 and at most `max(1, towns / OPAQUE_PER 16)` opaque names per map
  (then blocked); flavor parts only on the planned flavor towns (`planShapes` step 6: `FLAVOR_SHARE` 0.125 of the
  towns, at most `FLAVOR_MAX` 3 per 16, the best `+n` claim, a river or a coast / edge dialect area first, never a twin
  anchor; `FLAVOR_ON` 0.6) and the climate's settler group (the Spanish of a dry US map, share at most 0.155) counts as
  flavor; `QUIET_SHARE` 0.1 (s53 0.4); a pair naming no feature on a non-quiet town `LITERAL_PEN` 0.5 lower; the shape
  shares through `quota60` (whole x3, qualifier x2, frame x2.5, each at most 0.12 or its old share, together at most
  0.34; personal, single and saint x0.25 / 0.4 / 0.4; en / usa multi-word `separate` at least `SEP60` 0.32 / 0.36,
  words `WORDS60` 1.6 / 1.7) with `SEP_BONUS` 0.35 for a multi-word candidate while the map's count lasts; a frame tries
  the town's named feature on a descriptive base first ("Oakhaven-on-Blackmere"), then the common bases (no reused
  bases); a whole name that drops the town's granted river ranks 0.5 lower. Twins never copy an opaque or flavor
  anchor. `M.siteWord(info, w)`: a readable site word (a non-opaque, non-flavor part whose main tag is on the site, a
  named feature); `NAMES shapes ... desc= opaque= flavor= multi= rules=`.
- **Created towns:** `PN.related` builds no district on an opaque parent stem or the first word of a multi-word parent
  (the composed forms take the whole name); ot_offname's en forms read plainly (Riverside, Meadows, Bottom, Croft, Falls,
  Watersmeet, Stone Works, Landing for Ings, Holme, Clough, Leys, Force, Meeting, Delph, Staithes).
- **Name lab:** gen.ts ports all of it, a "Rules" select (descriptive (§60) / review (§53)) in the site lab's toolbar
  and the old page's Whole map card; export_names.py writes `golden53` beside `golden`; check_port.mjs 7584 / 7584
  (both rule sets), check_port.js 3792 / 3792; gen.js is generated from gen.ts (`names/gen_js.mjs`).
- Tests: test_names60.lua (new, 22: the gates per language and climate, the s53 comparison, the flags, the 0341 and
  1729 replays with districts and Works, de / fr maps); test_shapegates (the shares of the map's rules, words
  WORDS60 + 0.1, quiet at most QUIET_SHARE + 8 points, saints not quiet; synthetic maps moved to
  `tests/square_organic_towns/namemaps.lua`), test_namefix (twins share their base).
- Offline numbers (full mode, 16-24 towns): en site word 84-87 % per climate, multi-word 42-46 %, quiet 10 %, opaque
  0, flavor 1.3 per 16; usa site word 78-89 % (dry 78 %: the Spanish names), multi-word 57-62 %, quiet 9 %, opaque 0;
  de 90 %, fr 86 %, it 91 %, es 90 %, pt 89 %, nl 90 %, sv 91 %, nb 91 %, ja 88 % site words, quiet 10-15 %, opaque 0.

##### Evocative names, every character town's kind, the industry as a cue (2026-10-15; NEXT_PHASE_BRIEF 61; in game: TESTING.md "Combined test iteration" step 10)

User after run `2026-10-15_0429_sqot-sqrl`: "i like two waters name a lot. anything that is kind of obviously part of
the environment is neat", "if character names don't already factor into city name that would be cool, too" and "city
name could potentially take into account what type of industry they are". `ot_placename.RULES` is "s61" (default);
`o.rules = "s60"` / `"s53"` give the earlier names exactly (the s61 lines are left out, the root index too).
- **Inventory** (`ot_placename_lang`, per language `affix61`, every line +61, and `charForms61`): evocative whole names
  `+g` with gates `?tag[:min]` (`?a|b` either; `?lakes2` two lakes within 1.5 km, the survey's `waterNear().lakes`):
  en Two Waters / Three Rivers / Watersmeet (confluence), Broadwater / Lakeside, Seven Oaks / Ashgrove / Birchwood / The
  Willows / Pinewood (the species tags), Long Meadow, Wide Fen, Saltmarsh, Windy Ridge, Fell Foot, Dale Head, High Moor,
  High Force, Wellspring, Sandy Point, Rocky Bay, Cliff End, Shingle Street, Bridgend (a wide river's bridge), Stepping
  Stones (a brook's ford), Ferryside, Palm Bay / Coral Point / Mangrove Bay (tropical); usa Two Rivers, Three Forks,
  Twin Lakes, Lakeview, Seven Pines, Oak Grove, Cedar / Pine Bluff, Walnut Bottom, Big Meadows, Prairie View, Windy
  Ridge / Gap, High Ridge, Rocky / Stony Point, Sandy Hook, Bayside, Big Spring, Cold Springs, Rock Falls, Cypress
  Swamp, Palm Point, Coral Bay; de Zweiwasser, Dreiflüssen, Seeufer, Eichenhain, Birkenhain, Lindenhain, Tannenhöhe,
  Langenwiese, Breitenbruch, Windeck, Bergfuss, Talende, Kaltenbrunn, Sandhaken, Steinbucht, Klippenende, An der
  Brücke, Zur Furt; fr Les Deux-Eaux, Trois-Rivières, Bellevue-sur-Mer, Bord-du-Lac, La Chênaie, La Frênaie, La
  Saulaie, La Pinède, Grand-Pré, La Crête, Pied-du-Mont, Bout-du-Val, Bellefontaine, Pointe-de-Sable, Baie-des-Rochers,
  Les Falaises, Les Ponts, Le Gué; it / es / pt / nl / sv / nb / ja likewise (Dueacque, Dos Aguas, Duas Águas,
  Tweewater, Tvåvatten, Tovann, 川合 ...; 17-29 per language). Industry forms `+i !family` (fish, oil, clay, coal,
  stone, timber, farm, iron; two or more each: en Fisherhaven / X Harbour, Oil Springs / X Wells, Brickfield /
  Claygate, Coalbrook / Pithead, Stonegate / Quarry Bank, Timberley / Sawyers End, Barnfield / X Grange, Ironbridge /
  Furnace End; usa X Harbor, Oil City, Coaldale, Quarryville, Sawmill Creek, Lumberton, Hayfield, Ironton ...). The
  kinds' forms: en waterfront X Quay / Port X, street Long X / X Street, company Xville / New X, deep forest
  X-in-the-Forest / X Woods, secluded Far X / X End, coastal X Sands / X-on-Sea / X-by-the-Sea (the others as before);
  every other language got forms for all 11 kinds (de Hohen-, -hafen, an der Bucht, Langen-, -Siedlung, Gartenstadt,
  -werder, Markt, im Wald, Hinter-, an der See / -Strand; fr Mont-, Port-, -la-Crique, -la-Rue, Cité-, -Cité-Jardin,
  -en-l'Île, -le-Marché, -en-Forêt, -du-Bout, -Plage; sv -höjden, -hamn, -viken, Lång-, -bruk, -ön, köping, -skogen,
  Bortre, -strand; ja 台 / 港 / 浦 / 宿 / 新 / 園 / 島 / 本 / 森 / 奥 / 浜 ...).
- **Plan** (`planShapes`, s61): 0b industry towns (`IND_SHARE` 0.09, at most `IND_PER16` 2 per 16, at least one per map
  of 6+ towns with a candidate; claim `IND_FAM_K[family]` x nearness, one per family, `IND_R` 1500 m); 2b evocative
  towns after the whole names and the twins (`EVOC_SHARE` 0.21 + draw, at most `EVOC_MAX` 0.25; the gate on the
  town's reading before rarity, the fit at least `EVOC_CLAIM` 0.5, `EVOC_RIVER` 0.3 lower on a river-granted town and
  none on the river's first grant, each name once in the plan; each multi-word one takes a `separate` name off the
  count). The evocative and industry towns are named right after the character towns. Character towns: the s61 kinds
  (`KINDS61` forest, secluded, coastal) take the character shape; a romance base of two words may take the form, one
  idea more allowed, the word budget waived before a plain name (`over`). Evocative, industry and character names are
  never quiet. `WORDS61` en 1.75 (usa keeps 1.7); the quiet share counts the towns left plain. `NAMES shapes ...
  evoc= charCue=<carry>/<kinds> indCue=`; NAME `evoc=` (the gate's reading), `ind=<family>:<m>`, `char=`.
- **Driver** (`namesAssignGen`): `Driver:namesKinds`: a town without a strong kind is "forest" when its forest read
  passes `FO.deepSite` (the ring share and wooded sectors of deepPick) and a seeded draw (`DEEP_P` x the era), at most
  `DEEP_MAX` on the map with the saved deep towns, else "secluded" (an ordinary character town), else "coastal"
  (`coastalOf`); `s.nameDeep` (true / false) then decides the plan's deep pick (`FO.deepPick o.named`: the draw
  skipped, or never deep: `why=names:`). `namesIndustryCue`: the nearest industry of a cue family within `IND_R`
  (`OFF.indType`; ore mines read as coal, `/forest/` as timber). `CH.NAME_KIND.deep_forest = "forest"`,
  `CH.NAME_SECLUDED`, `CH.NAME_COASTAL`.
- **Name lab:** gen.ts ports all of it; Rules "evocative (§61)" / "descriptive (§60)" / "review (§53)" (site lab and the
  old page); the site lab's single-site runs try an evocative name on every 5th town; export_names.py writes
  `golden60` too and the golden towns carry s61 kinds, industries and lake facts; check_port.mjs 11376 / 11376,
  check_port.js 3792 / 3792.
- Tests: test_names61.lua (new: inventories, gates, the maps per language, shares, the industry rules, the older rules,
  the 0429 / 1729 replays, de / fr maps, the driver's kinds); test_nameshape (ind= / evoc= on the NAME lines, the NAMES
  shapes fields); test_shapegates and test_namefix adjusted to the s61 forms (a waterfront's Quay, twins' roots).
- Offline numbers (full mode): evocative 15-20 % of the towns on maps with two character towns (en 20, usa 16, de 15,
  fr 16, it 19, es 19, pt 18, nl 16, sv 16, nb 15, ja 16-17 %), 10-17 % on maps with four character towns and
  industries; industry names 1.4-1.6 per 16; every character town of a kind carries its kind (100 / 100 per language).
- Open: in game, does the names-time forest read predict the deep forest towns (a town whose forest read was not done
  at naming keeps the old draw, and its name may lack the cue)? `Driver:charIndustry` read `it.x` / `it.y` of
  `E.industries()` entries, which are `{ x, y }` arrays: no town was ever picked as a company town (`noIndustry` on
  every CHARACTER line of the last 8 runs). Fixed in §62 (both forms read); the archived runs' industries sit
  1200-1800 m from the town centres, so the company kind still scores under `MIN_SCORE` almost everywhere
  (NEXT_PHASE_BRIEF 62 "Not done").

## 7. Performance budget

| Item | Budget |
|---|---|
| Main Thread per frame (driver) | ≤ 0.5 ms average, ≤ 2 ms worst (sliced) |
| Assessment of one town | ≤ 3 ms total, sliced; once per town per ~60 s at 100 towns |
| Snapshot (octree + components) | ≤ 5 ms for 500 edges, sliced |
| Planning one increment | ≤ 5 ms per tick: sliced over ticks since 2026-10-12 (`PLAN_SLICE_US` 4 ms + one round) |
| `makeProposalData` precheck | measure in probe H; ≤ 20 ms or move to fewer prechecks |
| Commands | 1 in flight; ≥ 2 s between increments map-wide; ≤ 36 edges per demand / metropolis increment, 48 per frame, 60 per satellite seed (2026-10-13 doc fix: was "≤ 24 edges each") |
| Upward dose (later ideas) | 3 DevelopAt + 1 restore per upward town, at most every 180-300 s per town; points from the snapshot graph (no extra reads) |
| Level weights (2026-10-14 late) | at a check, only when a send is due: one TOWN component read + 3 capacity-per-level reads, one command; at most every 300 s per town; since 2026-10-15 also one read after each FILL restore of a managed town (+ one command when the restore rewrote the weights) |
| Straight-run guard (2026-10-14 late) | per plan: one pass over the increment's edges with a 60 m cell index of the buildings |
| Terrain stats | once per town per load, 576 height samples (cached by town id) |
| Forest read (phase F) | once per town per 20 min: one octree list + <= ~24k (hard 48k) instance reads, 3 ms slices (measured 2026-10-13: 11-32 ms per town in 5-12 slices) |
| Spit search (peninsula tip) | once per town per load in the terrain stage, towns with water only: 16 rays, <= ~4k water samples (memoised sampler) |
| Stop names (round after the names run) | one stop per 0.5 s at most, only after a player builds one; the map's station group names re-read at most every 60 s (one name read per group), up to 1,500 composed candidates per stop |
| Names assign (2026-10-14) | once per new map, in ONE tick (`namesAssignGen`: site tags + ot_placename.assign): offline 0.04-0.1 s at 30-60 towns, 0.1-0.3 s at 120, 0.3-1.2 s at 250 (Lua 5.4, quick model towns); past STAGE_HANG_US 4 s the guard ends the names phase (towns keep the game's names). NAMES words `towns= assignMs=`. Slice it if a real map shows > 100 ms |
| Strong characters pick (2026-10-14) | once per new map: `CHARS_SLICE_US` 6 ms per tick (at least one town), `CHARS_MAX_S` 90 s, then the towns read so far are scored |
| Map survey (names, 2026-10-14) | once per new map: `NAMES_SLICE_US` 2 ms per tick, `NAMES_SHAPE_MAX_S` 45 s (`capped=timeout`), every phase capped at `cells x PHASE_K` units |
| Satellite pacing (2026-10-14) | the map's size re-read at most every 2 s, only when a founding is asked (one `townCaps` per town, `PACE_MAX_TOWNS` 4000) |
| Frame cost line (2026-10-14) | `TICKCOST` every 300 s (always on): ticks, `avgUs`, `maxUs` and its stage (`at=` chars / names:<phase> / job:<stage> / idle), `getMaxUs` / `getAvgUs` (the GUI `state:get()` copy of the saved table, every frame; avg from 2026-10-20), ticks over 4 / 16 / 50 ms, `pvB` / `pvN` (the provenance record's chars / entries, 2026-10-20, cap 32768) |
| Master plan rebuild | sliced since the final-test round (yields between grower, motif hooks, promenade; the final test had up to ~144 ms in one tick) |

Heavy work could move to the GS `update` (no frame cost, findings.md:585-589) only if probe I shows a safe pattern for
sending (no callback; duplicate sends across sim states must be ruled out by an idempotency check).

## 8. Risks

| Risk | Mitigation |
|---|---|
| Engine street growth collides with or duplicates ours | Build ahead (`lead`), precheck, Lead/Own modes; skip a side after 2 refusals |
| Crash when touching nodes with 2+ edges (findings.md:198-207) | Join only dead ends until probe D clears a variant; log every proposal before sending |
| Joined dead ends stay "blocked" (findings.md:186-197) | Probe D variants (replace-node, config rebuild) |
| Terrain refusals / ugly embankments | Slope limits from templates, short pieces, contour styles, precheck |
| Town no longer lines our streets with houses (wrong owner/template) | Probe B; plain town templates, no `playerOwned`; the one exception: the `town_*_trees` entry streets (not simBuildable, players build them in towns; preventParcels false; ENTRY lines; off after 2 refusals) |
| An upward dose (DevelopAt) raises a big town's target (v5 runaway) | Exact restore (UP.EXTRA 0) right after, CAP_K 1.6 x base, 240 s gap (the surge rule dropped for upward 2026-10-14 late: the exact restore is the brake); UPWARD effect logs initial / target |
| Player pays for/maintains town streets | Probe B; every mod build refunded (rev 2, 2026-10-17) |
| Frame hitches on big maps | Budget + slicing + the stage hang guard; one town per tick; TICKCOST lines (the mod has no SQPERF) |
| Proposal reroutes lines/stops (proposal "updates lines, stops", type.d.tl:2826) | Never remove existing edges except in the chosen join variant; never edges with objects |
| Other mods (Town Street Names, Roundabouts, Bulk Bulldozer) | Read-only interplay; skip edges/nodes owned by constructions |
| GS `update` fires in several states | Driver on the GUI thread; GS state writes idempotent |
| Level weights (2026-10-14 late) stay with the town after removal and fix its level mix | New maps only, never a player's own weights, re-sent as persons per building change, cleared at 5.5; LEVELS lines. Since 2026-10-15: a grown plain town ends at the engine's own weights (none of ours), the blend rows are never lower than the town's current weighted target, and the engine's fill weights (written by the mod's own restores, which hold a town at level 1 for good) are replaced from half grown |
| Global angle knob changes all towns, not just ours | Written in preRunFn by the "Vanilla town street angles" setting (default Automatic; Game default leaves it; never with Act on: Off); it can't be per town |
