# Motifs and landscape phases: brief (2026-10-13)

Queued after the current round (industry streets off, satellites, frames, character towns, spread across the
landscape, coast hugging, hill road; NEXT_PHASE_BRIEF §24). One subagent per phase. Read first: PLAN.md design
principles (incl. "character from the site, not the region" and "towns follow the landscape, no default disc"),
§3.1, §6.3; TESTING.md "Real map test"; docs/findings.md index + docs/findings/towns.md.

## Why (user, 2026-10-12/13)
- Towns should look unique and respond to terrain and surroundings; regional style labels matter less.
- Spread across the landscape, not radiating from the centre; hug coastlines more often.
- Liked: Middlewich's single street climbing into the hills with house rows and small terrace neighbourhoods
  (session `2026-10-13_0342_sqot`), Acton's gaps, EU organic crescents around meadows, the density control
  town's green gaps, vanilla house clusters at industries (Barnard Castle / Ilkeston), metropolis variants,
  polycentric.
- "If there are any other motifs you can think of, add those in, too."
- Forest: some towns should work around dense forest (smaller fingering towns), big suburbs may clear it.

## Motif framework (phase M0, before the motifs): DONE 2026-10-13 (PLAN.md 6.3 "Motifs: the framework", NEXT_PHASE_BRIEF 25)
- A motif = a small, recognisable street pattern placed where the land or the game calls for it, built through
  the normal planner (increments, housed-front, own-empty budget, lead limit, map edge, crash rule).
- Each town gets 0-2 motifs, chosen from site + surroundings + era + a per-town seed (deterministic, saved
  compatibly on the frame; old saves get none). Neighbour diversity applies to motifs too.
- Log `MOTIF town= kind= why= edges= houses=` and a per-town summary; ALLTOWN gets `motifs=`.
- Offline: synthetic terrain fixtures per motif; each motif test checks the pattern's metric and the rules.
- Dev: a Showcase/Town-tab option to force a motif on the picked town (dev only) for screenshots.

### Notes for M1 (from M0)
- Add a kind with `MO.register{ id, eligible, style?, plan?, measure? }` in `ot_motif.lua` (or a new `ot_motif_<name>.lua`
  required from it); append its id to `MO.IDS` (append only: saved frames hold indices) and to the dev picker
  `otd_shared S.MOTIFS` (the dev test checks they match). Drawn kinds (not `derived`) are picked 0-2 per town, seeded,
  saved on the frame (`mo`), diversified against neighbours; `eligible` returns 0..1 (the site's call: slope, valley,
  bay, shore, roads, era, size) plus a short `why` for the logs.
- Hooks: `plan(mp, style, m, env)` adds / cuts master-plan pieces (crescent: `ot_crescent.apply`; pieces need `key`,
  `a`, `b` junction keys present in `mp.junctions`, `pts`, `class`); `style(p, m, env)` steers (style fields such as
  `contour`, `lobeDirs`, `waterPremium`, `maxSlope`, extra `greens` reservations); `measure(env, m)` gives the MOTIF build
  line numbers (env: g, inc, style, mp, pts, sampler, MT, SH). A motif needing its own small plan outside the master plan
  (like frames / satellites) needs a new driver stage: not built in M0.
- The hill road is a derived kind today (the hillside contour-linear shape). M1's deliberate climb can either make
  `hill_road` drawn (it then needs `derived = nil` and the old shape-based look stays via the shape) or add a new drawn
  kind (e.g. `hill_climb`) whose plan hook lays the climbing street and terraces; keep `hill_road`'s id / index.
- Each drawn kind's eligibility should be exercised on the synthetic fixtures (`F.plane`, `F.valley`, `F.coast`, `F.river`)
  with a pattern metric; the green-relax fallback (ot_core) and the map-edge / lead / housed rules apply unchanged.

## Motifs (phases M1-M4, in order of expected visual impact)
M1 (terrain/water, most wanted): DONE 2026-10-13 (ot_motif_land.lua; PLAN.md 6.3 "Motifs M1", NEXT_PHASE_BRIEF 26,
TESTING.md 38-42)
1. Hill road: one main street takes the easiest climb up a slope or valley, houses along it (single-loaded where
   steep), small terrace loops on flatter shelves, steep/rocky ground left green. (May already be started in §24.)
2. Valley fishbone: main street along the valley floor, short lanes up both slopes.
3. Harbour crescent: curved waterfront street around a bay, dense row facing the water.
4. Fishing village: a few narrow streets running straight down to the shore, a waterfront street linking them.

### Notes for M2 (from M1)
- Put new kinds in a module like `ot_motif_land.lua` with a `registerAll(MO)` called from ot_motif (append ids to `MO.IDS`
  and `otd_shared S.MOTIFS` in the same order). Give kinds a `group` when two would lay the same main street.
- Reuse the line tools: `L.overlay(mp, line, o)` (cut into the plan, `band`, `drop(x, y, tee)`, `stops`, `startKey` /
  `endKey`, `every`, `dense`, `branch`, `deadEnd`, `teeK`), `L.layMain(mp, line, o, L.anchors(g, style, ix, sMid, dirs,
  sampler))` for a main line that must join the town (env.g is the snapshot graph the plan is built from),
  `L.approach(style)`, `L.dense(style)`, `L.band(style)`, `L.builtAlong(g, ix, tol)` for measures, `L.arc` for kink-free
  links. A ribbon village's road is an existing country road (not in the town snapshot): its lanes must start from town
  dead ends or plan junctions, never from the road's nodes (not joinable; engine.obstacles knows the road's edges).
- Branch rule: any street that must leave a main line at a junction needs `branch = "start" | "end"` on its overlay
  (ot_select.withBranches takes it with the main-line piece there and runs the line one piece past it); a junction
  passed by a built street can never get a new street (dead ends only).
- Offline sims must use `join = "deadEnd"` (core.simulate defaults to "any", which hid the branch problem).
- Motif pieces skip the envelope / front / wedge / arm limits (ot_select `MOTIF_FREE`): keep each motif's own extent
  bounded (trace length, zone), the housed front and the lead limit do the rest in game.
- A village green / hamlet at a road fork outside the town needs its own small plan (like satellites / frames): a new
  driver stage (not built yet), or a plan hook that only adds pieces within the town's plan extent.

M2 (roads/villages): DONE 2026-10-13 (ot_roads.lua, ot_motif_road.lua; PLAN.md 6.3 "Motifs M2", NEXT_PHASE_BRIEF 27,
TESTING.md 43-47)
5. Ribbon village: houses along a country road out of town, a few short side lanes (Strassendorf).
6. Village green: triangular/oval green at a road fork, houses around it, green left unbuilt.
7. Crossroads hamlet: a small cluster where two country roads meet.
Also done: satellite sites prefer crossroads and farms / light industry (heavy / medium still avoided).

### Notes for M3 (from M2)
- Country roads: `style.roads` (ot_roads.trace: `roads` polylines with heading / out, `junctions` with `own`, `segs`)
  on every resolved style in game (offline: pass `roads` to I.build, or `RDS.fromGraph`). A station quarter can find the
  road toward a station the same way; ot_select already blocks plan pieces across / onto any traced road.
- Geometry must stay put across plans: the master plan is rebuilt whenever an anchor's dead end is built on, the extent
  grows or (dev) the decade changes, and every rebuild runs the plan hook again. Derive the motif's line from stable data
  only (centre, terrain, roads, seed) and never stop it at the town's own streets (the planner refuses a piece that hits
  one); if a choice needs the graph (the green's free place), keep it on the motif record (`m.greenPick`) for the session
  and recognise an earlier session's by the mod's locked streets (`e.locked`; kinds with `lock = true` and
  `MO.LOCK_PREFIX` get their build edges locked by D.lockKeys). A ring road (M3) needs exactly this.
- A closed ring of new streets: lead line to a new junction, the other sides as `branch = "start"` overlays from that
  junction (taken with the lead's last piece, ot_select withBranches end rule), the closing piece ending on the other
  side's dead end (`endKey`). Keep a line's pieces >= ~40 m (a 10 m stub piece is refused as `short`) and avoid kinks
  inside one overlay with curved pieces (`curve`): put a stop at every corner, or split into overlays.
- `clearAround(mp, {ix...}, r)` (ot_motif_road) drops the plan's pieces running near a motif's streets but keeps T's onto
  them: useful for cul-de-sac pods and the ring road. Debugging selection: `ot_select` honours `opts.why` (call
  ot_grow_organic.grow with `why = {}`), and planIncrement's `inc.dropped` reasons (short / curve / nearExisting).
- Fixture `F.*` style for roads lives in test_motif_road (`roadTown`, `roadA` / `roadB`, `crossroadsTown`): reuse it for
  a station quarter (a station = a point plus a road toward it).
- Satellite records (`s.sat`) carry `at` / `junction`; MO.measure env has `sat`. Industry kinds via `IND.forTown` need
  `file =` named fields (`{ x, y, file = ... }`, as ot_engine.industries gives them; a positional name is classified
  medium: test_satellite's steel mill was, fixed in M2).

M3 (town structure, era): DONE 2026-10-13 (ot_motif_town.lua; PLAN.md 6.3 "Motifs M3", NEXT_PHASE_BRIEF 28,
TESTING.md 48-52)
8. Ring road around the old core: a curved street around the organic core (old walls), grid districts outside;
   ties into the grid trend (later years).
9. Station quarter: when the player builds a train station near a town, a small straight grid grows toward it
   (detect stations via the API; gameplay hook).
10. Workers' terraces (pre-~1920): short parallel terrace rows next to LIGHT industry only; heavy industry keeps
    the away preference.
11. Cul-de-sac pods (post-1950): suburban closes off a collector.

### Notes for M4 (from M3)
- New kinds go in a module like `ot_motif_town.lua` (`registerAll(MO)` from ot_motif; append ids to `MO.IDS` and
  `otd_shared S.MOTIFS`); gate their eligibility and plan hooks on the module's `ON` and switch it off in
  tests/fixtures.lua (`TW.ON = false` / `F.withTownMotifs`), else the new kinds take slots in the other tests' towns and
  their baselines move (M3's first run broke 5 tests that way).
- Junctions where several new streets meet: the game joins only dead ends, so they must come in one increment. Flag the
  pieces `motifBranch` + `motifJoin` (ot_select withBranches takes the others along also at a town node that is still a
  dead end); a dead-end branch off a main line (`branch = "start"`, culDeSac) should carry `motifWait` (ot_select
  `branchOk`: it waits while the line's built tip is its junction and the line goes on, else it takes the tip and the line
  stalls). Both are off for M1 / M2 pieces (their numbers were measured without them).
- Keep a line's geometry independent of the plan extent and the graph: no `L.smooth` over a line whose length grows
  (smoothing / simplifying moves earlier points when the end moves; the pods' collector is a circular-arc trace for that),
  and ignore the motif's own built edges when testing a geometry against the graph (`crossesGraph` treats edges lying
  along the segment's line within 10 m as its own; ot_plan snaps junctions a few metres).
- A dead-end branch must not cross the main line's link arc from the town (`crossesMotif`): the overlay would cut the link
  there and the close stops being a dead end. Drop the plan's T parts onto a dead-end branch (`drop = tee or ...`).
- Derived kinds get a fresh motif record per plan: keep their geometry on the master plan (`mp.stationGeo`) for the
  measure. A derived kind counts as a slot at a fresh town's pick (a town with a station draws one motif less). (M4: no
  longer for `extra` kinds: the station / bridgehead quarters take no slot.)
- The ring's radius is saved on the frame (`rr`, ot_saved): a kind whose geometry depends on the town's size at the pick
  can do the same (a frame field read in the style hook via `env.frame`). Switchbacks / ridge street can reuse the hill
  climb's tracer (L.traceClimb) with a hairpin rule; a bridgehead quarter can take the station quarter's grid (`stationGeo`
  with the bridge's far end as the forecourt) and ot_bridge's `br` frame flag.
- Station API facts are read from files only (docs/findings/towns.md "Listing rail stations"); the in-game run checks them
  (TESTING.md 50). If `transf` / -Y fail, `front=unknown` and the quarter faces the town (`side=guess`).

M4 (more terrain): DONE 2026-10-13 (ot_motif_relief.lua; PLAN.md 6.3 "Motifs M4", NEXT_PHASE_BRIEF 29, TESTING.md
53-58; also the M3 fixes (extra kinds take no slot, motifWait give-up) and the era range 1900+)
12. Switchbacks: hairpin climbing street on steep slopes, houses at the bends.
13. Ridge street: along a crest, houses both sides, steep green flanks.
14. Headland street: along a cliff/headland edge facing the sea.
15. Bridgehead quarter: a small cluster at the far end of a mod-built bridge (ot_bridge).

### Notes for F (from M4)
- Motif kinds are done (MO.IDS 1-17). A forest motif (fingers along clearings, houses facing the trees) would be a new
  module like ot_motif_relief.lua with an `ON` switch off in tests/fixtures.lua (`RL.ON` / `F.withReliefMotifs` pattern);
  append ids to `MO.IDS` and `otd_shared S.MOTIFS`. A "forest-hugging" town is a style / steering choice more than a
  motif: probably a style hook (soft barrier = drop / cost plan pieces in dense forest cells) plus an eligibility from
  the forest map; the own-empty budget, lead limit and map edge apply as everywhere.
- Per-town terrain extras belong on `ot_terrain.stats` (once per town and session, like `cliff`, ~180 samples): a
  coarse forest grid could sit there too if the forest read is cheap enough; eligibility hooks only see the stats
  (`ctx.terrain`), not the sampler.
- Era: the game starts in 1900 at the earliest (findings towns.md); any forest-era weighting (forest-hugging early,
  clearing later) should span 1900 to the latest years (PLAN 6.3 "Era range 1900+").
- Lines that bend hard (hairpins) need a stop at every bend start / apex / end (two pieces per bend) and a radius >= 80 m
  (ot_plan MIN_RADIUS 70 + margin); the bend's ground must stay within maxSlope over every 10 m (ot_select's per-piece
  grade test) or the piece is dropped as steep.
- A `motifWait` branch now gives up after 6 plans with its line's next piece refused (SEL.WAIT_GIVEUP).
- The bridge is found in the snapshot as a street edge over water with both ends on land (the engine snapshot carries no
  bridge flag); the in-game run checks it (TESTING.md 57).

## Forest (phase F, research first): DONE 2026-10-13 (ot_forest.lua, ot_engine.forestReader; PLAN.md 6.3 "Forest-aware
towns", NEXT_PHASE_BRIEF 30, TESTING.md 59-62; findings towns.md "Reading trees near a town")
Result: feasible from the files (trees = ASSET_GROUP model instances with `metadata.tree`, octree by position; not
verified in a game script); built as a per-plan town mode (hug / clear / none) steering ot_select, no motif kind.
- Research: can a game script find trees/forest density near a point cheaply (tealdefs: engine.d.tl ~77 "data
  attached to assets, in particular trees"; entity searches by position; terrain material/ground texture
  sampling; how the game removes trees under new streets)? Write findings (read from files vs verified).
- If feasible: a forest map per town (cached, coarse grid). Forest-hugging towns (seeded; more likely early,
  small, organic styles, character towns) treat dense forest as a soft barrier: fingers along clearings and the
  forest edge, houses facing the trees, forest kept. Clearing towns (late, big suburbs, metropolis, grids) build
  through as now. Log `forest=` share around the town and `forestCut=` share of new street length in forest.
- If not feasible: report the cost of the fallback (ground texture, terrain sampler proxy) and stop.

### Notes for the later-ideas phase (from F)
- The tree grid sits on `stats.forest` (ot_forest grid: `cover(fg, x, y)`, `share`) and `style.forest` (`{ grid, mode,
  share }`, per plan). A motif or style hook can read it: e.g. a `forest_edge` motif (a street traced along the cover 0.5
  contour with houses on the open side) would follow the MO.register pattern (own module, `ON` off in tests/fixtures.lua);
  not built because the hug mode's edge premium already lays streets along the edge.
- The in-game run decides the thresholds (FOREST `p50` / `p90`, `share`) and the read's cost (`listUs`, `us`); if the
  octree list is slow on big forested maps, read a smaller radius (`FO.R`) or once per load only.
- A build's real cut could be measured from the precheck's `collisionInfo.autoRemovalEntity2models` (trees the proposal
  removes) instead of the grid: a `trees=` field on BUILD lines, no extra call.
- "Tree-lined entries" (country road character, below) could plant trees with an asset proposal; the reforestation
  script's `makeReforestationProposal` shows the command path.

## Other ideas for later phases: later-ideas phase DONE 2026-10-13 (PLAN.md 6.3 "Later ideas", NEXT_PHASE_BRIEF 31,
TESTING.md "Final test: all phases" G 22-25)
- Upward density in big towns: DONE (`ot_upward`: from 1500 buildings or under pressure, the demand increment cut by
  0.25-0.5 and DevelopAt(upgradeBuildings) at 3 core points along main streets, initial capacities restored exactly;
  UPWARD / UPWARD effect lines; the in-game effect of upgradeBuildings is the open question).
- Gaps for sprawling and character towns: DONE (`ot_meadow`: meadow sectors between the lobes, reserve + locked meadow
  frames; MEADOW, FRAME kind=meadow).
- Head start / reshape starting towns: NOT DONE, waits on the Starting town size test (does populationDensity shrink
  the generator's cores?).
- Country road character: the roads themselves NOT DONE (not safe: the mod never rebuilds a country-road node,
  findings towns.md); town side DONE as tree-lined entries (`ot_entry`: the base `town_*_trees` templates on the mod's
  streets along a road's first 320 m out of town; ENTRY lines). Curvier approaches: the M2 ribbon village covers it.
- Polycentric next steps: DONE (centres at country-road junctions, a third centre from 30000 persons, seeded grid cores
  per centre: ot_metro / `ot_poly`; METRO at= / cores=). Suburb patterns between the centres: not done.
- Satellite villages next to light industry / farms as deliberate clusters: done in M2 (satellites prefer crossroads,
  farms and light works).

## Status (2026-10-13): every phase of this brief is done (M0-M4, F, the later ideas) and was run in game (final
all-phases test, session `2026-10-13_0856_sqot-dev`, results in HISTORY.md): the drawn motifs almost never picked
(eligibility calibrated on steep fixtures; no country roads on that map, and missed ones on earlier maps). The final-test round recalibrated them,
added virtual roads and a new kind, the **peninsula tip** (a street out along a spit with a cluster of houses at its tip,
the user's favourite from Southborough; `ot_motif_point`). Next: TESTING.md "Final-test round test".

## Rules (every phase)
Crash rule (every new node needs a BASE_NODE_CONFIG; valid lane indices); don't impact saves (saved frames load;
old towns keep their look); new user-visible strings in all 13 languages, tooltips wrapped; run only the two
mods' tests/check, i18n, tooltips, `make link`; never commit, never `make modio`/`op`. Each phase updates PLAN.md,
NEXT_PHASE_BRIEF (new section), TESTING.md "Real map test" (what to look for per motif), HISTORY.md.
