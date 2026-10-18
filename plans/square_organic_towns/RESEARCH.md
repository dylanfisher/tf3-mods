# Organic Towns: research (2026-10-11)

Build 40420 sources. Paths are relative to the repo; `C=.cache/game`, `A=$C/api/tealdef/api`.
Tags: **[F]** confirmed in files, **[G]** confirmed in game (docs/findings.md), **[I]** inferred, needs a probe
(see PROBE.md).

## 1. Who grows towns, and the knobs

- **[F] Town size growth is a base Lua game script, street/building layout is C++.**
  `$C/base/content/game_mechanics/towns/town_growth.script.tl` decides new `sizeFactors` per town and sends
  `makeTownUpdateSizeCmd(town, sizeFactors, false)` (:550), or re-sends the old factors "to call the town developer
  anyway" (:556-557). It only picks towns with `town.developmentActive` (:345) and gives no experience to frozen
  towns (:28). The developer that places streets and buildings is engine code with no Lua hooks.
- **[F] So `makeTownSetDevelopmentActiveCmd(false)`** (`A/cmd.d.tl:851-856`) at least stops the base script's growth
  and experience for that town. Whether the C++ developer also stops building streets/buildings, and whether a
  manual `makeTownUpdateSizeCmd` on a frozen town still runs it, is **[I]** → probe A.
- **[F] baseConfig knobs** (set in `preRunFn(captureParams, configDict, allModParams, baseConfig)`, pattern
  `$C/mods/release/urbangames_sandbox/content/mod.script.tl:3-5`; signature [G] findings.md:13-24):
  - `townMajorStreetAngleRange` (`A/type.d.tl:3698`), base 0 with the comment "angle within town major street
    directions are randomized (in degrees)" (`$C/base/content/base/mod.script.tl:110`). Wiki: "0 results in parallel
    streets without curves" (docs/wiki/modding/scripting/baseconfig.md:183).
  - `townInitialMajorStreetAngleRange` (`A/type.d.tl:3720`, base :111). The map editor's experimental town builder
    exposes it as "Initial Road Angle Range" 0-90° in 3° steps (`$C/base/content/gui/construction/tools/town_builder_tool.script.tl:94-96,139-148`,
    applied in `construction_react_util.tl:3546`). So 0 = strict grid, larger = more organic. **[I]** how it looks
    at 15/45/90 → probe C.
  - `townDevelopInterval` 60 half days (`A/type.d.tl:3692`, base :104). The base growth script still hardcodes 30
    steps (`towns.script.tl:10`, `TODO: read value from base_config`), so this knob may do little. **[I]**
  - `locations.makeInitialStreets` (`A/type.d.tl:3555`) is about **industry** edge streets ("Add small streets at the
    edge of industries"), not town streets, despite the wiki's wording (baseconfig.md:137).
- **[F] Per-town angle only at creation.** `TownInfo.majorStreetAngle` / `initialMajorStreetAngle`
  (`A/type.d.tl:3185-3187`) exist only on the creation record. The `Town` component (`A/engine.d.tl:1285-1302`) has no
  angle, and no command sets one (no "angle" in cmd.d.tl). Existing towns can't be re-angled except by destroy +
  recreate. Stress Test sets both to 0 on creation (`mods/square_stress_test/content/stress/gui/stress_towns.tl:581`).
- **[F] Density lever:** `makeTownCustomDistributionWeightsCmd(town, weights)` (`A/cmd.d.tl:845-850`), weights are
  3 land uses x 4 levels (`A/cmd.d.tl:374`). Base town window builds defaults from
  `api.engine.util.town.computeWeightedTargetTownBuildingCapacityPerType`, normalised to max 1
  (`$C/base/content/gui/entity_window/town/town_eow.script.tl:682-694`) and `nil` resets (:747).
- **[F] Building lock:** `makeTownBuildingSetBlockedDevelopmentCmd` (`A/cmd.d.tl:878-883`), "Historic" buildings.
  Useful for keeping an old core.

## 2. Street locking: `aiLock` is gone, `roadDevelopmentLocked` replaces it

- **[F] `aiLock` exists only in the wiki** (docs/wiki/modding/infrastructure/tracksstreets.md:156,168, a TF2-era
  text): no TF3 street template, no tealdef, no base code uses it (rg over `$C`).
- **[F] TF3 has a per-edge lock:** `BaseEdge.roadDevelopmentLocked` "prevent towns from updating or extending this
  road" (`A/engine.d.tl:108-109`). The template field `initiallyLocked` is only the initial value "when built by the
  player" (`A/type.d.tl:5483`; set on highways and construction entrances, e.g.
  `$C/base/content/infrastructure/street/highway/highway_new_small.street_template.lua:26`).
  The player tool `ACTION_PLAYER_OWNED_TOOL` sets it via `StreetEdgeNodeModifier.roadDevelopmentLocked = true` and
  makes the edge player-owned (`construction_react_util.tl:3302-3310`, `$C/base/tealdef/scripts/builtin.d.tl:169-172`).
  Map layer `hideNonLocked` shows locked edges (`A/type.d.tl:4572`).
- **[I]** A script can set `seg.comp.roadDevelopmentLocked = true` on edges in a `SimpleProposal`. Whether the town
  then never extends from that edge's free nodes, still lines it with houses, and never upgrades it → probe F.
- **[F]** `simBuildable` = template may be used by the town developer (`A/type.d.tl:5481`; wiki :169: target type
  for upgrades). `country = true` → no houses along it (wiki :170, `A/type.d.tl:5485`). Our streets must use town
  templates (`$C/base/content/infrastructure/street/town/town_{old,new}_{xsmall,small,medium,large}.street_template.lua`).

## 3. Building streets by script

- **[G] Street from scratch works:** `SimpleProposal.streetProposal.edgesToAdd` with `type` 0, `typeIndex` -1,
  `streetEdge` copied from a reference edge, `makeWorldBuildProposalCmd`: success, ~36.6k cost, 3/3
  (findings.md:474-477).
- **[F] Proposal shape:** `SimpleStreetProposal` (`A/type.d.tl:2764-2805`): `nodesToAdd`, `edgesToAdd`,
  `nodesToRemove`, `edgesToRemove`, `nodeConfigsToAdd/Remove`. New ids count down from -1 (edges first, then nodes in
  the Stress Test's convention, `stress_junctions.tl:484-490`). `SegmentAndEntity` (`A/type.d.tl:2520-2533`) has
  an **optional `playerOwned`**: leaving it nil probably makes a town (unowned) street **[I]** → probe B logs the
  `PLAYER_OWNED` component and the money charged.
- **[F] Working code to copy:** straight segment builder `segment()` (`stress_junctions.tl:247-269`), node replace +
  far-node config re-point `linkProposal()` (:379-521, `repointedConfig` :331), `-0` → `+0` helper `z0` (:55,
  `stress_grid_streets.lua:31-34`), `Context` with `checkTerrainAlignment = true` and pre-check via
  `api.engine.util.proposal.makeProposalData` (:183-212; `A/engine/util.d.tl:925`), batch remove with split-and-retry
  (`stress_roads.tl`).
- **[G] Joining an existing dead end keeps it "dead end"** (red sign) because the node's `BASE_NODE_CONFIG` is kept
  (findings.md:186-197). **[G/I] Crash** when a link replaced a node with 2+ edges (findings.md:198-207). → probe D.
- **[F] Town reputation:** `town_util.getProposalStats` returns empty stats when `playerInitiated` is false
  (`$C/base/content/game_mechanics/towns/town_util.tl:1062-1064`), so `makeWorldBuildProposalCmd(p, ctx, false,
  false)` costs no town authority (`towns.script.tl:266-287`).
- **[I] Construction route:** the Stress Test's "Wide grid" is a `.con.lua` with all nodes free
  (`stress_grid_streets.lua`, `square_stress_test_town_grid.con.lua`), built before the town. The caller reports the
  town filled it with houses; findings.md does not record this (TESTING.md 6F was "not run in game yet"). Whether the
  edges stay owned by a construction (`getConstructionEntityForEdge >= 0`) matters for save safety: a construction
  that names a mod `.con` would break when the mod is removed (same failure class as findings.md:678-693). Prefer plain
  street proposals with base templates.

## 4. Terrain and water

- **[F]** `api.engine.terrain` (`A/engine.d.tl:1725-1781`): `getHeightAt(Vec2f)` (with alignments),
  `getBaseHeightAt` (4 m resolution, no alignments), `isOnWater(Vec2f)` ("below the water level"),
  `isValidCoordinate`, `getBoundingBox`. `Terrain.waterLevel` component (:1232). No slope or river API: slope = finite
  differences of heights; rivers only via `isOnWater` **[I]** (rivers may or may not count) → probe E.
- **[F] Street slope limits are per template:** `maxSlope`, `maxSlopeShape`, `maxSlopeBuild`, `minCurveRadius`
  (`A/type.d.tl:5512-5531`). Town templates don't set them, so engine defaults apply; read at runtime with
  `api.res.streetTemplateRep` (`A/res.d.tl:147`).
- **[F]** Stress Test sets each node's z from `getHeightAt` and splits long links into pieces (`stress_junctions.tl:70-74,
  422-423`, `logic.linePoints`). With `checkTerrainAlignment` the engine cuts/fills. **[I]** whether a too-steep piece is
  refused or reshaped → probe E.
- **[G] mod terrain**: sea level is 0 m in mod heightmaps (findings.md:373).

## 5. Reading towns

- **[G]** `getEntitiesWithComponent(TOWN)` works; `BASE_EDGE(_STREET)` can't be listed: use
  `streetSystem.getNode2StreetEdgeMap()` or `util.octree.findEntitiesInCircle(pos, r, BASE_EDGE)` filtered by
  `BASE_EDGE_STREET` (findings.md:418-425).
- **[F] Town centre/extent:** base takes a town's position from its `BOUNDING_VOLUME` centre
  (`$C/base/content/scripts/entity_util.tl:48-55`, `town_util.tl:978-984`). **[I]** the bbox spans its buildings →
  probe J.
- **[F] Fill level:** `townBuildingSystem.getLandUsePersonCapacities(town)` (actual, `A/engine/system.d.tl:116`),
  `Town.initialLandUseCapacities * sizeFactors` (target, as `town_growth.script.tl:368-371`),
  `util.town.getTownCapacityUsage` (used vs capacity, `A/engine/util.d.tl:629`),
  `computeActualTownBuildingCapacityPerType` (per level, :607-610).
- **[F] Parcels:** `parcelSystem.getParcelData(segment)` returns `any` (`A/engine/system.d.tl:562`, shape unknown →
  probe J), `Parcel` component (`A/engine.d.tl:803-822`: `streetSegment`, `left`, `curveParam`, `offset`, faces),
  `townBuildingSystem.hasBuilding(parcel)` / `getParcel2BuildingMap` / `getTown2BuildingMap` (system.d.tl:107-129),
  `TownBuilding.level/depth/parcels/town/timeBuilt` (`A/engine.d.tl:1305-1326`).
- **[F] Graph:** `streetSystem.getNodeStreetSegments(node)` (dead end = 1 segment), `isTownCrossingNode`,
  `BaseEdge.node0/1, position0/1, tangent0/1, roadTemplate` (`A/engine.d.tl:98-129`, system.d.tl:293-320).
- **[F] Stations:** `stationSystem.getTown2StationsMap()` (`A/engine/system.d.tl:75`), `getTown(station)` (:78).
- **[F] Era:** `api.engine.util.getYear()` (`A/engine/util.d.tl:1033`).

## 6. Region signal

- **[G]** The config dict holds `climate`, `economy`, `nameList` (findings.md:21; nameList is a resource path like
  `square_names_us_washington::/names/...` or `::/names/europe/europe.names`, findings.md:680,687).
- **[F]** Base name sets (`$C/base/content/names/`): asia, china, england, europe, france, germany, italy, japan,
  korea, netherlands, norway, oceania, poland, portugal, russia, spain, sweden, usa. Repo: 13 `square_names_us_*`.
  Climates (`$C/base/content/climates/`): dry, subarctic, temperate, tropical.
- **[G]** `runFn`'s second argument is the config dict (findings.md:20-22) and runFn runs in ~50 Lua states
  (:23-24), so `rawset(_G, KEY, configDict)` from runFn reaches every state (`rawset` avoids the global guard,
  findings.md:130-136). Name scripts have `api.engine == nil` (:126).
- **[F/I]** Game scripts can call `api.engine.config.getConfigDict()` (`A/engine.d.tl:1803-1807`; the state names
  rename script does, `mods/square_names_us_texas/content/square_names_us_texas/rename.script.lua:288-290`), but that
  call's result was never checked in game (its `isActive` returns true on nil, `sn_logic.lua:424-428`) → probe G.

## 7. Where code can run and send commands

- **[G]** GUI `react.onStep` runs on the Main Thread; `onStepTimer` and HUD icon scripts on worker threads (no GUI
  calls there) (findings.md:380-398). The Stress Test sends all commands from a HUD element's `onStep` with callbacks
  (`stress_runtime.tl:1-8,82-90`); GUI-state commands run next sim step, callback a frame later (`A/cmd.d.tl:2-10`).
- **[G]** Game-script `update`: `sendCommand` with a callback fails ("Callbacks are currently disallowed"), send
  without and verify later (findings.md:116-118); never send inside build events (memory note, `!m_betweenChanges`).
  `update` runs in several sim Lua states, so a once-per-interval guard can fire twice (findings.md:592-594); it does
  not stall frames (:585-589). `state:get_native()` asserts (findings.md:596-610).
- **[F]** A `.gs.lua` can add `guiUpdate(userParams, state, guiState)` on the GUI state (`$C/base/tealdef/scripts/gamescript.d.tl:66`);
  it must be registered for the script to load on the Main Thread at all (memory "GS gui events need subscribe").
- **[G]** One proposal / town command in flight at a time; parallel ones slow down and race (findings.md:437-439).

## 8. Measured costs to plan with

- [G] Town create 0.7-5.5 s; `makeTownUpdateSizeCmd` 0.4-8 s, ~250-350 buildings per call, repeatable
  (findings.md:405-414,460-463); freeze/unfreeze 19 towns ~100 ms (:464).
- [G] A 40 ms stall in GUI `onStep` drops frames; the same in GS `update` doesn't (findings.md:585-589).
- [I] Proposal build time for ~20 edges: unknown → probe H.

## Open questions (all in PROBE.md)

A freeze scope · B fill along script streets, ownership, cost · C angle knobs · D joining existing nodes safely ·
E slope / water · F engine vs script streets, `roadDevelopmentLocked` · G configDict at runtime · H proposal cost ·
I driver context (`guiUpdate` vs HUD `onStep`) · J parcel data, town bbox · K density weights.

## Nordic towns (2026-10-12, Showcase v9 round: "what makes this Nordic?")

What the NORDIC profile now draws on (web search 2026-10-12; the street-level details partly from general planning
history, not from a plan drawing):

- Post-war Nordic new towns and suburbs (Vallingby 1954, Tapiola ~1950s, alongside Stevenage) were planned around 1950
  with neighbourhood units, the Radburn concept and community centres
  ([Hall, Post-war new town models](https://journal.urbanform.org/index.php/jum/article/view/3923);
  [ABC city](https://www.wikipedia.org/wiki/ABC_city)). Radburn groups houses in small clusters on cul-de-sacs off a
  collector road, with footpaths and green between the clusters.
- Tapiola: four neighbourhood units, each surrounded by a green belt, linked by large park zones; buildings set among
  pine and birch ([Docomomo Finland](https://en.docomomo.fi/projects/tapiola-garden-city/)).
- Vallingby: flats within ~450 m of the centre, small houses within ~900 m, everything compact around the metro
  station centre ([Watching the Swedes](https://watchingtheswedes.com/2024/08/04/the-abc-of-swedish-town-planning/)).
- Regional scale (general knowledge): Copenhagen's 1947 Finger Plan (growth along rail fingers, green wedges between)
  and Stockholm's green wedges; old cores small, often a regular grid after fire regulations (Norwegian wooden towns).

Translated to the profile: cells bounded by curving collector loops (the neighbourhood units), cul-de-sacs from the
loops into each cell (the house clusters), a third of the cells left green (the green belts), 4 meadows, low density
weights, fingers / linear shapes favoured. The game makes the old core itself.
