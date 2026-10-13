# Findings: Towns and town growth

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## A save whose name set is gone crashes on the next new name (2026-10-10)

- A save stores its name set as a resource path in the config dict (`nameList: square_names_us_washington::/names/...`).
  If the mod that ships it is turned off, **the save still loads without any warning**, but the first time the game
  needs a new name it hits `ResTypeRep.h:233 Get: Assertion '(iindex)>(-1)'` ("Actual: -1 <= -1"), a fatal error, and
  writes a crash save. The game looks the set up by path and uses the "not found" index -1 without falling back to a default.
- Evidence: "Blank Slate" (made with `square_names_us_washington`) loaded with only `square_roundabouts` crashed twice
  (20:11:15Z, 20:12:29Z), each about 2 s after opening construction menu → Roads (UI path `action-constructionbuilder`,
  `tool-construction-menu-roads`), i.e. on the first preview that creates streets. The same mod set on "Test Area"
  (`::/names/europe/europe.names`) worked. Earlier loads of Blank Slate had the Washington mod active and worked.
  The roundabout construction itself was not the cause: every template, bridge and model it names resolves.
- No mod code can prevent it (the mod is absent when it fires). Every mod that ships a `.names.lua` set needs
  `severityRemove: "Critical"` and a "never remove it from a game started with this set" note. Turning the mod back on
  fixes the save. The state names generator sets both from revision 6.
- When debugging a `ResTypeRep` `Get` assert, compare the save's config dict (`Loading config from file`, `nameList`,
  `climate`, `economy`) with the active mods first.

## Town development needs its small street templates (crash 2026-10-11)

square_stress_test's "Town streets: Wide" set `simBuildable = false` on every town street template except
`town_{new,old}_large` (a `loadStreetTemplate` modifier; the country templates stayed sim-buildable). Pressing the
Stress Test's Grow (with Car traffic = Drive: destinations, capacity x2) crashed: assert
`!sizeDiffAndTemplate.empty()`, "Did not find any street template usable for town road development",
`train_fever/src/Game/UrbanSim/simulation_util.cpp:116 GetStreetForTownDevelopment` (crash json
d915b116-..._5.json, town_streets = 2). Inferred: town development looks for a template within some size
difference of the street it wants (new or upgraded), so the large one alone does not cover small streets. Never
take the smaller town templates away from town development; the setting was removed. Wide streets for test towns:
build them yourself (Stress Test "Wide grid").

## Organic Towns probe, first run (2026-10-11)

`square_organic_towns_probe` (plans/square_organic_towns/PROBE.md), free game, temperate, name set `europe`, build
40420, `[SQOT_PROBE]` lines in stdout.txt.

- **Config dict at runtime (G):** `api.engine.config.getConfigDict()` works in game-script `update` ("Sim Pool N"),
  `guiUpdate` and a GUI plugin's onStep/onClick, but has **no `climate`, `nameList` or `economy`** there. `preRunFn`'s
  configDict lacks them too. Only `runFn(captureParams, configDict, …)` gets them (it runs in ~15 Lua states at load,
  "Load Game Pool"/"Sim Pool"/"Main Pool"). A global set in `runFn` **is visible in game-script `update` and
  `guiUpdate`** (same states), **not** in the GUI plugin/HUD state. So: read region and climate in a game script.
  - **Correction (2026-10-11, late, from base code): preRunFn does get them, as a list of pairs.** preRunFn's
    `configDict` is `{ {key, value}, ... }` (type `{{string, string}}`): base `base/content/base/mod.script.tl:184-191`
    reads it with `for _, v in ipairs(configDict) do settings[v[1]] = v[2] end` and copies `nameList` / `climate` /
    `economy` into `baseConfig.nameId` / `climate` / `economyId`. The probe read `configDict.nameList` (a dict
    lookup) and so logged nil. runFn's configDict is a real dict. So a mod can set baseConfig per region in
    preRunFn (Organic Towns' "Vanilla town street angles", `ot_angles.settings` accepts both forms); its
    `[SQOT] ANGLE` line will confirm it in game.
- **baseConfig set in preRunFn is readable at runtime:** param 45 → `townMajorStreetAngleRange` and
  `townInitialMajorStreetAngleRange` 0 → 45, read back 45 from the HUD later (`api.res.getBaseConfig()`).
- **Lua states (I):** the GUI plugin's `react.onStep` and the game script's `guiUpdate` (Main Thread, ~110 Hz) are
  **different Lua states** (a shared module table written by one was never seen by the other, 3/3 rounds). A harmless
  `makeTownSetDevelopmentActiveCmd` from onStep got its callback after ~390 ms.
- **Script streets on slopes (E):** a single 80 m `town_new_small` edge whose node z follows the terrain built at every
  tried grade (4–16 % terrain, resulting slopes up to 11 %), ~285 ms from send to callback; the engine cut/filled the
  ground itself. A forced 20 % slope also built but cost ~10× (338k vs 26–39k). Forcing flat z on 12 %+ terrain was
  refused with `Collision`.
- **Water (E):** streets 30 m and 10 m from the shore built; a street at the shoreline and one reaching 20 m into the
  water were refused **with no message** (`success=false`, `msgs=[]`, even though the pre-check said ok). Keep script
  streets off water yourself.
- **Build time:** one- and two-edge proposals took 270–290 ms each from send to callback, roughly constant, so a
  proposal costs at least that much latency (H not run yet).
- **`parcelSystem.getParcelData(edge)` crashed the game natively (inferred, 2026-10-11).** Probe J's first call on a
  town street edge (valid id from `BASE_EDGE`) was followed 13 s later by a hard crash: no Lua error, main thread
  `EXC_BAD_ACCESS` at address 0 (`ldp x21, x8, [x1]`, a vector read through a null pointer), dump
  `88e6bc07-…_1006.dmp`; no `[SQOT_PROBE] J` line was logged (they come after the call). No base or official mod code
  calls `parcelSystem` at all. `pcall` can't catch it. Don't call `getParcelData`; the probe now reads
  `getSegment2ParcelData()` (no argument) and looks edges up in Lua (untested yet).
- **Joining a script street to a town dead end (D, 2026-10-11, script readings; visual check pending):**
  D1 plain join → the node's `BASE_NODE_CONFIG` kept 0 lane connections (deg 1→2), i.e. blocked as before.
  D2 replace the node with a new one → the new node had **no** config component (engine default, effect unknown).
  **D3 plain join + `nodeConfigsToRemove`/`nodeConfigsToAdd` with a full config for all its edges → 0→4 lane
  connections**, success, ~280 ms. D4 (remove the dead-end edge, rebuild it longer) built but cost 776k vs ~20k for the
  others (likely demolished the town buildings along the removed edge): don't remove town edges. D6 (coincident new
  node, `cleanupStreetGraph`) was refused, Construction Not Possible (its target was D4's new end).
- **Removing a node config that doesn't exist crashes the game (verified 2026-10-11).** D3 on a dead end that a
  script had just built (D1's new end: a new node gets **no** `BASE_NODE_CONFIG`) sent `nodeConfigsToRemove = {node}` +
  `nodeConfigsToAdd`: the simulation thread asserted `Engine.cpp:693 PostRemoveComponent 'it != components.end()'`
  and the game crashed (dump `6E6C71D0-….dmp`, crash save `crash_town-growth-dev_2026-10-11_16-12-20`). The same D3 on
  an engine-made dead end (has a config, 0 lanes) worked the run before. Rule: put a node in `nodeConfigsToRemove` only
  if `getComponent(node, BASE_NODE_CONFIG)` is non-nil; otherwise only add. Probably the same family as the Stress Test
  crash above (component type 27 = BaseNodeConfig "not known").
- **Parcels (J, verified):** `parcelSystem.getSegment2ParcelData()` works from a GUI script: a table of 610 segments
  → `ParcelData` userdata; `#pd.leftEntities + #pd.rightParcels` gave 7–22 parcels per town edge. Town Beccles: 29
  edges, 599 parcels, 223 built (via `townBuildingSystem.getParcel2BuildingMap()` + the `PARCEL` component's
  `streetSegment`), scan 2 ms. The town entity's bounding box held only 28 % of its 98 buildings: use the buildings,
  not the town's box, for the town extent. Town capacities were exactly at target (sizeFactors 1, all level 1, 2020).
- **Town street templates (E):** every base `town_*` street has `maxSlopeBuild` 0.2, `maxSlope` 0.4,
  `minCurveRadiusBuild` 60 m (44 m existing); only the plain variants (`town_{new,old}_{xsmall,small,medium,large}`)
  are `simBuildable`; `new` from 1940, `old` from 0; none `initiallyLocked`.
- **`isOnWater`:** a 400 m grid at 10 m over the coast: 1415/1681 points water, 154 disagree with "terrain height < 1 m"
  (shore band); over land 0 hits (31 low points that aren't water). Use `isOnWater`, not the height.
- **Big script patches (B):** an 18-edge `town_new_small` grid patch joined to a town dead end built in one proposal
  (cost 306k–520k, ~200–380 ms); the placement search found a passing candidate after 1–9 pre-checks (~1 ms each).
  Right after the build the new edges had 0 parcels (parcels appear later or need growth; pending).
- **The engine's lane connections at a town junction (verified 2026-10-11, probe Node dump):** a game-made 3-way node of
  `town_new_small` (4 lanes incl. sidewalks) had exactly 6 entries, one per ordered pair of different segments:
  `A.1>B.2` (withRoad), whatever each edge's direction (in or out at the node). No sidewalk entries, 3 crosswalks.
  So a connection is one-way, from the incoming road lane (1) to the outgoing one (2); a straight joint needs `A.1>B.2`
  **and** `B.1>A.2`. Probe D3's first pattern (`i -> n-1-i` for all 4 indices, i.e. `A.1>B.2`, `A.2>B.1` and two
  sidewalk entries) left the junction with the HUD's red dead-end sign. A game-made dead end has a config with 0
  connections and 1 crosswalk (no sign). The red sign in the screenshot was on a plain-joined node (2 edges, 0
  connections). **Script-made nodes get no `BASE_NODE_CONFIG` at all** (a 4-way and a 3-way patch node, `config=false`)
  and showed no sign; whether vehicles route through them is open.
- **Forced growth ignores script patches so far (verified 2026-10-11, probe Grow here + user screenshot).** Beccles,
  sizeFactors 1 → 2, 4 × `makeTownUpdateSizeCmd(…, true)` 8 s apart: buildings 98 → 174 → 183 → 195 → 196, town
  streets 29 → 51 (**the engine built 22 streets of its own**: loops and cul-de-sacs at its edge), capacities
  {128,92,83} → {258,197,170}, label 128 → 261. Both 18-edge script patches next to it stayed **completely empty**:
  one joined plainly (red dead-end sign at the joint), one player-owned with a plain joint. Cause open (no parcels on
  script edges? the blocked joint? ownership? distance from the centre?); probe Street read checks the parcels.
- B1 at a dead end on a slope near water: all 40 pre-checks refused (`Collision` 40, `Too Much Incline` 39); a 1x1
  patch whose pre-check passed was then refused at build with **no message** (as streets touching water, E).
- **Script streets have no parcels or node configs at first (verified 2026-10-11, probe Street read).** All 18 edges
  of each script patch (owned and unowned): `inMap=false` in `getSegment2ParcelData`, 0 parcels, and no
  `BASE_NODE_CONFIG` on any patch node (`cfg=nn`). Every game-built town street nearby: in the map, 7–32 parcels,
  configs at both ends.
- **…but the town does fill them once it grows into them (verified 2026-10-11, user screenshots).** At sizeFactors 4
  (Beccles 98 → 361 buildings, label 518, streets 29 → 65, dead ends → 0) the engine linked its own new streets into
  the bottom-right script patch (player-owned, 18 edges) and **filled it with houses**. The upper-left patch, whose
  only joint is the plain join with the red dead-end sign, stayed empty. So script streets can become town streets;
  a working joint matters. When the parcels appear (on the town's next growth pass that touches the patch?) is open.
- **Both patches adopted at larger growth (2026-10-11, user screenshot):** Beccles at label 988: the engine built
  streets around the upper-left patch too (the blocked joint's red sign is still there) and filled it with houses.
  Both script grids kept their exact geometry, and the engine's new streets beside them continued along the grid
  lines. So: script streets are adopted once the town's network reaches them through a working connection; growth
  did not reshape them (first answer to probe F).
- **Patch `Collision` near Morecambe was geometry, not the join (2026-10-11):** the first candidate pre-checked with
  no join, plain join and plain + config gave the same 29 collisions, all existing street edges/nodes (no buildings,
  terrain flat). Morecambe's curved dead ends sit close to its other streets, so a 240 m wide 3x2 patch overlaps them;
  the 40-pre-check cap ran out before smaller layouts were tried. Pre-checks cost ~1–3 ms, so try them all.
- **Corrected D3 joint works (verified 2026-10-11, user screenshot):** an 18-edge patch joined to a Morecambe dead end
  with plain join + the engine lane pattern (`A.1>B.2` and `B.1>A.2`, no sidewalks; config removed first only if it
  exists) built (cost 331k, cand 74/220 after 74 pre-checks, 3x2 at 120 m) and shows **no red dead-end sign**.
- **Adoption of script streets spreads gradually (verified 2026-10-11, Morecambe, probe Street read twice ~minutes
  apart at speed 4–8 after Grow ×2 and ×4):** the D3-joined edge got 30 parcels / 25 built first; later patch edges
  gained parcels one by one (14–20 each) **without node configs** (`cfg=nn`), while the far edges still had none.
  Parcels appear on a script edge some time after the town's network/development reaches it, then fill with demand.
  For the mod: build the next styled increment just ahead of the town's frontier, joined with the D3 pattern.

- **Street proposal crash: Engine.h:323 GetComponentDataIndex, BaseNodeConfig on a new entity** (2026-10-11, Organic
  Towns DEV "Grow now", stdout + crash_dump 2eea61dd). An 11-edge/10-node script street proposal with 4 D3 joints
  (configs removed and re-added on the existing dead ends) but **no** BASE_NODE_CONFIG on the new nodes, sent with
  `ctx.player` unset, asserted on the Simulation Thread right after the send ("component type is
  ecs::component::BaseNodeConfig … entity is not known, it was probably being added") and crashed the game. Every
  probe build that worked had `ctx.player` set, and the D3 ones also configs on all new nodes. Fix applied: both
  (configs in the engine pattern on every new node, an empty one on a 1-edge node; player set). Which of the two
  was the cause is still open.

## Organic Towns showcase, first run (verified from the game log 2026-10-11)

Blank Slate map, start 2020, dev mod `square_organic_towns_dev` "Showcase: build all" (plans/square_organic_towns/
PLAN.md 6.2 "Showcase v2"). From stdout.txt (`[SQOT_DEV] SHOWCASE …`):

- **Towns can be created from a game script's `guiUpdate`:** `api.engine.mapgen.createTowns` + `makeTownCreateCmd`
  made 16 towns one at a time, callback after 0.86-1.21 s each; the new town is found by diffing the town list
  (resultEntities empty). `createTowns` handed back `majorStreetAngle = initialMajorStreetAngle = 0` and
  `initialLandUseCapacities` 100/100/100; setting our own values on the TownInfo before the command worked.
  `makeEntitySetNameCmd` renamed them.
- **`api.gui.camera.setCameraData(Vec5f{x, y, distance, angle, pitch})`** from a HUD button moves the camera; read
  back 1.5 s later it matched exactly once settled (pitch 1.45 kept: near top-down), or was still easing toward
  the target (x 3027 of 3750).
- **A lane connection naming a lane past a segment's lanes doesn't crash a pre-check:** `makeProposalData` logs
  `lane_config_util.cpp:364: GetLaneOffset: Assertion '(i)<((int)laneConfigs.size())' failed`, `Actual: 6 >= 4`
  (index 6 on a 4-lane street) as a WARNING "Fatal error" on the Main Thread and Main Pool workers, and returns an
  errorState with one message, Construction Not Possible, and 0 collisions (105 such assertions in 9 min). Cause in
  our code: one lane count for every street at a node (an 8-lane street's road lanes 1..6 on a 4-lane one).
- **The pre-check message is not the literal `Construction_Not_Possible`:** a check for that exact text never matched
  while the log (whose formatter turns spaces into `_`) showed it, so the text has spaces (inferred). Match it
  normalised (lower case, spaces and `_` removed), or don't depend on it.
- **`makeTownUpdateSizeCmd(town, factors, true)` answers within about a second** (passes 2 s apart with a 2 s
  pause after each callback) and raises the capacity at once (e.g. 731 -> 889 of 938 between two passes), so
  forced growth needs no pauses.

- **Probe C answered: `TownInfo.initialMajorStreetAngle`/`majorStreetAngle` change the game's own town layout**
  (2026-10-11, Organic Towns showcase v2, Blank Slate, towns created with makeTownCreateCmd, grown 10 rounds by
  forced UpdateSize only, no script streets; screenshots .cache/ot_shots/2026-10-12_05-09-46/15–17). Angle 0: a
  strict rectilinear grid (like the default-angle controls). Angle 45: visibly irregular, diagonal streets at
  varied angles, lobes along arms. Metrics (spread / elongation): 0 → 1.84 / 1.19, 15 → 1.34 / 1.33,
  45 → 2.31 / 1.09, 90 → 1.78 / 1.33. So a mod can make vanilla towns (incl. starting towns, if the new-game
  generator reads the baseConfig `townInitialMajorStreetAngleRange` — still unverified) less grid-like per region.
- **Forced growth makes vanilla towns build long empty arms too** (same run): the control towns' outer streets
  include long dead-end arms with no houses, so not every empty stub in a mod town is a script street.
- **Update (same day, later): the cause is the missing configs, not the player.** "Roundabout here" (dev tools,
  two-way town-street ring, 8 edges / 7 new nodes, D3 joint at one town dead end, **no** configs on the new
  nodes, `ctx.player` **set**) built twice fine and crashed on the third with the same Engine.h:323
  GetComponentDataIndex assert, "component type is ecs::component::BaseNodeConfig" on a new entity (crash_dump
  9f5e3f38). So script-made nodes without BASE_NODE_CONFIG can crash the simulation at random even with a player;
  always give every new node a config. Whether `ctx.player` can be dropped (no charge) is still untested.

## Organic Towns Showcase v4 (from the game log and screenshots, 2026-10-12)

Blank Slate, 30 showcase towns, 10 forced increments each (`stdout.txt` 2026-10-12 01:10, screenshots
`.cache/ot_shots/2026-10-12_08-02-54/`).

- **Why the shape row read round (inferred from the log, reproduced offline):** the driver's street snapshot held
  only the edges within the building extent (90 % radius) + 300 m (`SNAP_MARGIN`). The shape towns' building extent
  stayed ~250-400 m (houses fill near the core), so arm streets beyond ~550-700 m from the centre were not in the
  graph: their tips were never reached or joined and each increment spent its 18 edges near the houses. The
  showcase TOWN metrics were cut the same way (`elong` 1.02-1.19 for every shape). Offline, the same cut on a round
  core gives linear `elong` 2.1-2.3, without it 5.6 (`tests/square_organic_towns/test_envelope.lua`). Fixed by
  following the town's connected streets beyond the circle (`ot_driver.townNetwork`, SNAPSHOT `net=`); unverified
  in game.
- **Houses stay near the core:** the linear town ended with 648 buildings, 231 of them on our 177 edges (66 with
  parcels); far arm streets had no parcels after 10 rounds. Forced growth (UpdateSize) fills by demand from the
  core outward, so a 600-building town looks round from above however the streets run, unless the streets near the
  core are only on the shape's side.
- **Starting angle:** `createTowns` handed back `majorStreetAngle = initialMajorStreetAngle = 35` for every town
  (in v2: 0). The main mod's "Vanilla town street angles" (Auto, EU) had set baseConfig
  `townMajorStreetAngleRange` 0 -> 35 in preRunFn ([SQOT] ANGLE line), and createTowns takes the range from it.
  Setting the TownInfo angles 0/15/45/90 before `makeTownCreateCmd` then gave towns that look the same (organic;
  v2 with range 0: clearly different). Whether the per-town angle is ignored when the baseConfig range is set, or
  the read-back only shows the range, is open. The showcase's Probe C row is off (`otd_layout.PROBE_C`); a repeat
  needs the main mod's angle setting off. The new-map (preRunFn) angle is still to be tested on a new map.
- **`makeTownDevelopAtCmd(centre, false, true)` once is a growth trigger, not an in-place upgrade:** no change in the
  same round (306 -> 306 buildings, capacity 1302 -> 1308), the next round 306 -> 670 buildings and 127 -> 250
  street edges (the game built ~120 streets of its own), at the end 1244 buildings vs the control town's 613.
- **Settle without transport barely grows towns:** 5 game months at speed 4 (6 real minutes) added 22 buildings to
  30 towns (17999 -> 18021); the dev settle now runs forced growth passes by default.
- **Street lock field:** `BaseEdge.roadDevelopmentLocked` ("prevent towns from updating or extending this road",
  `api/engine.d.tl:109`) is on the edge component a street proposal carries (`SegmentAndEntity.comp`; the move_it
  mod copies it). Our proposals set it false; the dev lock probe (Showcase v5) sets it true on new edges.
- **Locked town streets still get houses; the town stops branching off them (Showcase v5, game log 2026-10-12):**
  new edges built with `roadDevelopmentLocked = true` stayed locked (157/157 after 10 steps in each locked town).
  After 10 steps: linear locked 170 houses on our streets, 1 vanilla street attached to them, vs its plain twin 183
  houses / 33 attached; fingers locked 426 houses / 0 attached vs plain 162 / 33. Freezing the town instead
  (`makeTownSetDevelopmentActiveCmd` false) changed neither the vanilla street count nor the houses noticeably.
  Not yet seen: the town later widening a locked street, or unlocking one.

## `makeTownDevelopAtCmd` resets the town's initial capacities to its current size (Showcase v5, 2026-10-12)

Evidence: session `2026-10-12_0905_top-up-488838` (Blank Slate, Organic Towns Showcase v5): the "linear (fill)"
twin got `makeTownDevelopAtCmd(point, false, false)` (developStreets = false, upgradeBuildings = false) at 12 points
20 m beside its new streets after every round's two forced growth passes; its plain twin got none. Both had the
same forced `makeTownUpdateSizeCmd` schedule (sizeFactors 1 + 0.25 x step).

- **DevelopAt rebases the town.** The dev GROW lines log `cap=actual/target` (target = Σ initialLandUseCapacities x
  sizeFactors) before each pass. In the fill twin, after each round's DevelopAt calls the initial capacity sum
  equals the person capacity the town had at that moment: round 3 target 4562 at sf 1.75 = 2607 x 1.75 with actual
  2607; round 5 9728 / 2 = 4864 = actual 4864; round 7 29878 / 2.5 = 11951 = actual 11951; round 8 48953 / 2.75 =
  17801 = actual 17801. Initial sum: 750 -> 982 -> 1502 -> 2607 -> 4864 -> 7611 -> 11951 -> 17801 -> 20905 -> 26849
  -> 30066. So a town at size factor s wants s x its current size afterwards: it grew x1.5-1.9 per round. The
  plain twin stayed at 750 x 3.5 = 2625 (2618 actual). This matches the engine's "automatic update" of
  `makeTownSetInitialLandUseCapacitiesCmd(town)` without a list ("capacities are automatically updated",
  `api/cmd.d.tl`), and v4's single DevelopAt upgrade (306 -> 670 buildings the round after, at sf ~2).
- **It keeps growing after the calls stop.** In the 2-year settle (forced UpdateSize passes at the same size
  factors, no more DevelopAt) only the fill twin grew: +80..+357 buildings per pass, 4972 -> 7196 buildings;
  every other town +0 (they were at their target).
- **developStreets = false still means the town builds streets.** The fill twin added 45-206 vanilla street edges
  per round (plain twin -16..+17) and ended with 2093 edges vs 341: the street growth follows the raised target.
- **The arms filled, and so did everything else.** At the end 142 of its 150 mod edges had parcels and 1242 houses
  stood on them (plain twin: 42 / 177, 183 houses), but the town also grew round (street elongation 1.14 vs 3.35,
  `r` 1347 m vs 411 m). Whether a call builds right at its point (the undo_tf3 mod uses `(pos, false, false)` to
  rebuild one house at its old spot) is not measured yet; Organic Towns logs `FILL effect near= far=` per fill now.
  What developStreets = true / upgradeBuildings = true add: not tested.
- Consequence for mods: one DevelopAt multiplies a grown town's target by its size factor. To use it locally, put
  the initial capacities back afterwards with `makeTownSetInitialLandUseCapacitiesCmd(town, list)` (the town
  editor's command; untested from a script so far).

## Organic Towns Showcase v6 (game log 2026-10-12)

Evidence: session `2026-10-12_1732_sqrl-sqsg` (Blank Slate, 34 showcase towns, 10 forced increments each, three forced
growth passes after; `FILL`, `FILL restore`, `FILL effect`, `SHOWCASE LOCK` lines).

- **The DevelopAt reset is immediate, and the script restore works.** After a town's two `makeTownDevelopAtCmd(point,
  false, false)` calls, its initial land use capacities read right after the callbacks were already its current
  capacities (e.g. 250,250,250 -> 734,752,675 with 713 persons), so the reset happens at the call, not a round later.
  `makeTownSetInitialLandUseCapacitiesCmd(town, {r, c, i})` sent from the game script then set them (282,283,261), and
  the town's next check read an initial sum near its base again (FILL effect `initial=750->718`, not the ~2160 of the
  reset; why it read below the 826 sent is not known): the script path of the town editor's command works.
- **DevelopAt builds little at its point.** Over 55 fills of 2 points each, the buildings within 60 m of the points
  grew by 6.6 on average by the town's next check (within 200 m by more, the whole town by its forced growth), so a
  DevelopAt call is mainly a growth-target change, not a "build here".
- **developStreets / upgradeBuildings showed no clear effect** in a single-dose setting: three otherwise equal towns
  (fill only / streets / upgrade) ended with 1137 / 1040 / 965 buildings and 482 / 442 / 442 street edges.
- **Locked town streets keep their houses, unlocked ones far ahead of demand stay empty too.** Locked twins: locked =
  alive on every edge, 2-4 side streets attached vs 24 / 47 in the unlocked twins. With 18 new edges per round and the
  town growing ~40-60 buildings per round, only 31 % of a linear town's new edges had parcels after 8 rounds, the
  unlocked plain twin 18 % after 10: houses come by demand from the core outward, so streets built ahead of demand
  stay empty whatever their lock (Organic Towns now limits arm streets to ~2 blocks beyond the last housed street).


## Organic Towns Showcase v7 (game log 2026-10-12)

Evidence: session `2026-10-12_1900_sqot-dev` (Blank Slate, 35 showcase towns, 10 forced increments each, 18 script
edges per increment, three forced growth passes after; `SHOWCASE STEP`, `SHAPE`, `FILL effect`, `GROW`, `RB` lines;
shots `.cache/ot_shots/2026-10-12_19-16-20/`).

- **A town whose target runs far ahead of its streets builds its own streets everywhere, in its own organic pattern.**
  The five metropolis towns got `makeTownDevelopAtCmd` at 12 points after every build with no restore of the initial
  capacities, so each build reset the target to size factor x the current size (radial: target 57658 vs 22136 persons
  after 9 builds). They ended with 1425-1852 street edges each, of which only 145-180 were script-built: the game added
  86-205 street edges per round (its own layout, branching off every unlocked street, ours included), and all five
  looked like the same organic blob from above although their first rounds differed. Script streets steer a town's
  shape only while they supply the lots its target needs.
- **Houses fill by network distance from the core, not where free lots are.** In a shaped town whose arm streets
  (locked, with parcels) ran 300-550 m out, the farthest housed street along the arm stayed at 337 m for five rounds
  while the town grew from 212 to 449 buildings: the growth went into side streets nearer the core. Free lots far out
  along an arm stay empty until the nearer ones are taken.
- **A one-way town street ring with the derived lane pattern builds** (traffic on it not checked from the log) (`RB SEND ... ring=oneway
  newNodeConfigs=7/7`, `RB BUILT ok=true ring=4 arms=4`, no crash, no fallback). The ring and its four arm stubs had
  no parcels after 7 more rounds (`RB ADOPT ring=0/4 arms=0/4`): the town did not line them with houses.
- `makeProposalData` refusals: 3 `REFUSED` pre-checks (all `Collision` against the town's own new edges in one
  metropolis), `notPossibleNoCollision=6` over 329 builds; no lane-config assertion.


## Organic Towns Showcase v8 (game log 2026-10-12)

Evidence: session `2026-10-12_2129_top-up-530609` (Blank Slate, 32 showcase towns, 10 forced increments each, 12 town
jobs at once, three forced growth passes after; `SHAPE`, `SHOWCASE SETTLE town`, `SHOT`, `METRO step` lines; shots
`.cache/ot_shots/2026-10-12_22-10-37/`).

- **Forced growth without new script streets rounds a shaped town with the game's own streets.** The forced-linear
  town's houses read elong 1.62 (668 buildings, 259 street edges, 120 of them script-built and locked) at its last
  build; round 10's growth and three forced growth passes (`makeTownUpdateSizeCmd`, no script increment) added 350
  buildings and 113 game-made street edges around the round core, and the houses' elongation fell to 1.12 (streets
  1.60 -> 1.22). The game branches its own streets off the unlocked core streets wherever the target needs lots.
- **Locked script streets with 36-edge increments still leave ~70 % of a big town's streets to the game.** The four
  large metropolis towns (every new script street `roadDevelopmentLocked`, initial capacities restored to <= +25 % per
  fill) ended with 905-1335 street edges, 270-311 script-built (own 0.23-0.31; v7 without lock / brake 0.10). From
  above the locked frames kept their layout: the grid variant shows straight locked streets with single rows of houses
  along them and open block interiors (10 green gaps, 37 ha), the game's organic streets only around its own core.
- **A screenshot requested during or right after a long Main Thread stall, and one 0.3 s after it, both wrote no file**
  (inferred from the log): `api.gui.camera.takeScreenshot(1)` at the end of a ~3 s stall (the dev script wrote 32 long
  report lines; the shot's camera wait logged 2661 ms) and again 0.3 s later produced no "Screenshot: wrote" line;
  every later request, 3 s apart with steady frames, wrote one (30 of 32). Consistent with the game dropping requests
  while busy (findings 2026-10-11). Dev tours now wait for steady frames and keep shots >= 2.5 s apart.

## Natural town growth: how the game sizes a town (read from the game scripts 2026-10-12, not verified in game)

Source: build 40420's `base/content/game_mechanics/towns/` (paths under `.cache/game/base/content/`). Read from the
scripts only; the engine side (what the town developer does with the size) is not visible there. Used by the dev
tool "Simulate natural growth" (`mods/square_organic_towns_dev/content/organic_towns_dev/otd_simgrow.lua`).

- **No transport, no growth.** `town_cargo_util.tl:6` `growthPerTick = 0` (the only time-based experience source,
  used at `town_growth.script.tl:197`). Experience comes only from deliveries: `OnCalcTicketPrice` cargo into a town
  building (`town_growth.script.tl:620-647`, 10 per item, `town_growth_config.res.lua`) and passengers arriving by
  line (`:649-701`, 5 each); both x `2^tier` (tier 0 same town, 1 neighbour, 2 other town; cargo: the category tier)
  x the town's rating factor (`town_util.getXpFactor`, `town_util.tl:941-949`: 0-1 by its growth rating level,
  `authority2xpFactor`, x construction bonuses; `town_growth.script.tl:60-63`). Inactive towns (`developmentActive`
  false) get none (`:28`).
- **Level curve.** Level n costs `1000 x 1.5^(n-1)` (`town_cargo_util.tl:81-97` getLevelAndFraction,
  `expBaseTownLevel` 1000, `townExpScaling` 1.5). A town's start level comes from its residential initial capacity:
  > 100 -> 2, > 150 -> 3, > 200 -> 4 (`town_cargo_util.tl:43-55`). `levelUpSizeFactor` 1.25 (`:8`) is defined but
  unused in the scripts.
- **Growth factor.** `town_cargo_util.getGrowthFactor` (`:100-110`) = `town_growth_function.getGrowthFactor(level + 1
  - initialLevel + fraction)`, a cubic with F(1) = 1, F(18) = 40 (`scripts/util/town_growth_function.tl`), rising
  everywhere. So growth counts levels gained since the start: +1 level 1.46x, +4 2.75x, +9 8x, +17 40x; no cap.
- **Target and trigger.** Each town is handled once per 120 updates (`town_growth.script.tl:11-12, 344`):
  target = Σ initialLandUseCapacities x factor (`:365-374`); only if `floor(target) > floor(Σ initial x
  sizeFactors)` (`:376`). The script never lowers a size.
- **District split.** Usage weights from transport (`:377-412`): residential = line usage x 2 (clamped), averaged
  with residential cargo supply / demand; commercial and industrial = their cargo supply / demand. **If all three
  are 0 (no transport) nothing happens even with experience** (`:415`). The extra capacity is split by the
  normalised weights, then `rebalance2` (`:423-491`) pins each weight to at least
  `baseConfig.economy.townDevelopment.townGrowthMinDistrictFraction` (`:136`, engine default not in the scripts;
  the campaign mission 04 sets 1/3) and a maximum that is dampened from 1 toward 0.5 as the district passes 40 % of
  the town and toward 0.4 as it passes 32 % of the map (`:14-17, 509-520`).
- **Apply.** `sizeFactors[i] = (current land use + added) / initialLandUseCapacities[i]` and
  `api.cmd.makeTownUpdateSizeCmd(town, sizeFactors, false)` (`:536-550`): `updateAllBuildings = false`, so the town
  developer builds toward the new size at its own pace (the dev tools' forced growth passes `true`). When nothing
  changed, the script still sends `makeTownUpdateSizeCmd(town, town.sizeFactors, false)` "in case
  initialLandUseCapacities changed" (`:555-557`), so sizes set by a mod stay (the game re-sends them, never lower).
- Debug hooks in the same script: script events `Towns` / `_debugAddExperience` `{ entity, amount }` and
  `addExperiencePercentage` (`:9, 577-610`); adding experience alone doesn't grow an unconnected town (the
  usage test above).

## At the game's natural pace the town developer keeps open frontage ahead of the houses (real map + simulated growth, 2026-10-12)

Evidence: session `2026-10-12_2306_sqot-dev` (real map + simgrow, 2026-10-12, live session): a new generated European
map, 16 towns, `square_organic_towns` (Act on New towns: `INIT actOn=new`, `RUN knownTowns=0 fresh=true`, lock=shape,
fill=dose2) with the dev tool Simulate natural growth (`makeTownUpdateSizeCmd(town, sizeFactors, false)` in quarter-year
steps along the game's curve, 32 simulated years in ~19 real minutes, `SIMGROW` lines; buildings 2313 -> 4544, 0
fails). The main mod checked each town every ~48 s (16 towns x `CHECK_S` 3 s round-robin): 388 `[SQOT] CHECK` lines,
**every one `why=open needsRoom=false`, 0 SEND / BUILT**.

- **The game adds its own streets as the target rises, whatever frontage is free.** Over the run the 16 towns gained
  682 street edges and 2326 buildings (0.29 edges per new building), all game-made; the three towns without growth
  (Crewe, Uttoxeter, Sandiacre) gained 0-1. Aldershot: edges 58 -> 144, buildings 190 -> 570, free lots 711 -> ~1380,
  open frontage (free lots on edges filled below 25 %) 426 -> 650-850 while the mod's need (20 % of the built lots)
  rose 83 -> ~320; capacity / target fell 0.98 -> 0.54 (the developer's pace lags a fast target). Mitcham, Tidworth,
  Southgate, Greater Willington the same shape (+86..+113 edges each). Lowest open / need of all 388 checks: 2.03.
- **Gaps stay empty, new streets come anyway:** free lots on fuller edges grew too (Aldershot 251 -> 571) while the
  built lots doubled; the developer neither fills its gaps first nor waits for its open frontage to fill.
- Consequence for Organic Towns: a trigger on scarce room never fires in normal play; the mod now triggers on growth
  demand (the target's rise since its last build, `ot_assess.demand`, PLAN.md 6.3 "Growth-demand trigger"). Replaying
  the 388 checks with that rule: 13 growing towns would have triggered (<= ~100 builds before the own-frontage gate),
  the 3 static towns none.
- **No per-town switch for street growth exists in the API** (build 40420 tealdefs): `Town.developmentActive` /
  `makeTownSetDevelopmentActiveCmd` turns the town's growth off as a whole (houses too; Showcase v5: no visible effect
  under forced growth); `BaseEdge.roadDevelopmentLocked` ("prevent towns from updating or extending this road") is per
  edge, set on our new edges (existing edges only by rebuilding them; the game's own Player-owned tool sets it through
  a `StreetEdgeNodeModifier`, a GUI build action); `baseConfig.townDevelopInterval` (60, every town) and
  `townMajorStreetAngleRange` are global; `makeTownDevelopAtCmd(pos, developStreets, upgradeBuildings)` has a streets
  flag but showed no clear effect (Showcase v6); `makeTownBuildingSetBlockedDevelopmentCmd` is per building;
  `economy.townDevelopment` has only `cargoNeedsPerTown` and `townGrowthMinDistrictFraction`.

## Town population = residential person capacity; forced growth fills most of the target within seconds (code reading + probe log, 2026-10-13)

- **Population is the residential person capacity.** The game counts world population as the sum of
  `api.engine.system.townBuildingSystem.getTown2personCapacitiesMap()[town][1]` (`base/content/game_mechanics/company/
  company_util.tl:365-370` computeWorldPopulation; the map is `{RESIDENTIAL, COMMERCIAL, INDUSTRIAL}` per town,
  `api/tealdef/api/engine/system.d.tl:123-125`), and the town window's `TownPopulationWidget` shows
  `town_util.getTownCapacityUsages(town).residential.capacity` (`game_mechanics/towns/town_react_util.tl:859-870`).
  There is no separate "population" field on the TOWN component (`initialLandUseCapacities`, `sizeFactors`, ...;
  `api/tealdef/api/engine.d.tl:1285-1302`). Cheap to read (one map for all towns).
- **A forced size command fills about 85 % of the residential target within 5 s** (one reading, log session
  `2026-10-10_0544_grow-x100-crash`: a fresh town of initial capacities 100 on a free map, sizeFactors 1 -> 10 with
  `makeTownUpdateSizeCmd(town, f, true)`: residential 97 -> 836 at +5 s and +30 s; an older town on a crowded map,
  Tacoma 233 x10 -> 1347 = 58 %). So target ≈ initialLandUseCapacities[1] x sizeFactor, and the fill depends on
  room. A town right after creation is often below its target too: Lights showcase towns (initCaps 400, sizeFactors
  1, 96 per run) had 43-399 residents at creation over sessions `2026-10-12_2244_top-up-4951`,
  `2026-10-12_2343_top-up-563524` and `2026-10-13_0018_top-up-598153` (the `createTowns ... personCaps=` lines;
  quartiles 245 / 279 / 397 in `0018`, minimum 147 there, 43 and 60 in the other two). The Stress Test sizes the Lights showcase towns with this (x3 for ~1000 people) and logs `pop=` per town;
  that run's numbers will refine the fill for locked, level-shifted grids.

## Listing industries with their type and position (read from tealdefs and base / mod code, 2026-10-12; not verified in a game-script state)

- **List:** `api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)` (`api/tealdef/api/engine.d.tl:1713`,
  `ComponentType.INDUSTRY` at `:1654`) returns every industry entity; the base statistics window does the same
  (`base/content/gui/statistics/statistic_industries.tl:392`). `Engine.Component.Industry` itself carries only
  `stockList`, `level`, `closureTimeStamp`, `upgradeProgress`, `manualDevelopment` (`engine.d.tl:441-453`): no type.
- **Type:** the industry entity is a subconstruction; its construction comes from
  `api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(e)` (as square_industry_flows
  `flows_gather.tl:19` and the base HUD `gui/main/hud_icon_toolbox.tl:242-245`) or `getConstructionEntityForIndustry(e)`
  (`api/tealdef/api/engine/system.d.tl:240-249`); its `CONSTRUCTION.fileName` (`engine.d.tl:307`) names the industry
  (base files `base/content/industries/<name>/<name>.con.lua`, e.g. `steel_mill`, `food_factory`, `coal_mine`).
- **Position:** the industry entity's `BOUNDING_VOLUME` bbox centre (square_industry_flows `positionOf`).
- These calls work in Industry Flows' GUI state in game; Organic Towns calls them from the game script's `guiUpdate`
  (Main Thread), which is unverified until a run logs `[SQOT] IND industries=<n> ok=true` on a map with industries.
  `api.type.ConstructionType.INDUSTRY` (`api/tealdef/api/type.d.tl:2203`) is the construction-type route, not needed for
  the listing.

## Towns build on unlocked script / construction streets within a minute (log session 2026-10-13_0045_top-up-158690, inferred)

Lights showcase, 96 entry roundabouts (our construction, every node free, edges not `roadDevelopmentLocked`) built
right after town creation; their arms read after the junction builds and a settle (about a minute later).

- **The town hung its own streets on the arm ends and split arms.** 12 entries had an arm end that was no longer a
  dead end at the read (`arms not read (ends=3)`), 10 had joins fail, 3 a stale arm edge id (`can't be cast` copying
  it: the edge was gone). The towns with failures had 4-7 streets outside their grid at the next lock pass
  (`lock pass=links ... outside_streets=4..7`), the others 2 (the entry's own outward pieces). No side / axis pattern
  (all four sides, every twin mode): timing, not geometry (the construction's geometry is tested for every
  direction / inward axis / reach). User screenshot: ring arms ending in town-built stubs bent outwards.
- **A town street (`town_new_one_way_small`) ring got houses** on both sides and a tower on its island; the
  `country_new_large` arms stayed clear (as `country = true` roads do, roads.md).
- Rule: lock script and construction streets in town reach as soon as they exist (the grid lock waits 1 s after the
  build; do the same), and use `country` templates where no houses are wanted (`highway_new_small` / `_medium` are
  the base game's country one-ways; verified in game: no houses on the 2- / 3-lane `highway_new_medium` / `_large` rings or their islands after the
  towns filled in, user check in session `2026-10-13_0447_top-up-726115`).
- **The fix works (log sessions `2026-10-13_0118_top-up-148916`, `2026-10-13_0205_top-up-61157`,
  `2026-10-13_0356_top-up-779299`):** locking each entry's streets in a serial step about 2 s after its build (after
  Smart Lanes' ring write) gave 96 of 96, 96 of 96 and 90 of 90 entries read and joined 3/3. In
  `2026-10-13_0447_top-up-726115` 3 of 69 entries (one twin's E / N / W, 3 town streets outside the grids at the links
  lock, one per failing town) still lost an arm end: they were the last set, locked at 3.4 / 3.8 / 4.2 s after their
  build; all 64 entries locked at 2.0-2.6 s were fine. So a town can hang a street on a free dead end within ~3-4 s:
  lock in the build's own callback where possible.
- **Script-built highway streets arrive locked:** the `highway_new_*` templates have `initiallyLocked = true`, and a
  script proposal's edges of them already read `roadDevelopmentLocked` (session `2026-10-13_0118_top-up-148916`: 4 of
  every entry's 8 streets, the ring quarters, needed no lock; the links lock pass found 0 unlocked). Count them as
  locked; a lock proposal that skips locked edges would otherwise under-count.



## The first screenshot request of a game session writes no file; `makeInitialStreets` lays the industry-edge streets (2026-10-13)

- **The first `api.gui.camera.takeScreenshot(1)` of a session seems to be dropped** (inferred from three runs, not a
  controlled test). Session `2026-10-13_0018_top-up-598153`: the tour's shot 1 waited 2.5 s after the camera settled
  with steady frames (`SHOT n=1 ... settleMs=2499 steady=true`) and the game logged no "Screenshot: wrote"; each of the
  15 later requests (2.5-3 s apart) wrote one. In Showcase v8 (shots 1-2) and v9 (shot 1) the dropped shots were also the
  session's first requests (there after a ~3 s stall, so the stall was taken as the cause then). The Organic Towns dev
  tour now sends a throwaway primer request first (`SHOT primer=true`); the next run confirms or refutes this.
- **`baseConfig.locations.makeInitialStreets`** ("Add small streets at the edge of industries",
  `api/tealdef/api/type.d.tl:3554`; `base/content/base/mod.script.tl:135` sets it true with the comment "default true,
  false experimental"; the new-game page sets it true too, `base/content/gui/menu/new_game_or_map_settings_page.tl:407`):
  read from the game files only. In the same session's screenshots a town (Barnard Castle) had a small separate cluster
  of houses ~1.2 km out next to a farm, linked by its country road: consistent with those generator streets being town
  streets that the town later filled with houses (inferred from the picture, not traced in the log).


## A town's development reads off after a script dose fill (makeTownDevelopAtCmd + initial-capacity restore) (2026-10-13, inferred from a log)

- Session `2026-10-13_0137_sqot-dev` (Organic Towns real map run, dev simulation): Thornaby-on-Tees read
  `developmentActive` true before the mod's first dose fill (two `makeTownDevelopAtCmd(pos, false, false)` calls, then
  `makeTownSetInitialLandUseCapacitiesCmd(town, {137, 143, 128})`) and false at the next check 6 s later (`FILL effect ...
  active=true->false`); a `makeTownSetDevelopmentActiveCmd(town, true)` was sent (`FILL reactivate`), but every later
  fill's effect read `active=false->false` and the simulation saw the town off from year 29 to 40 (`SIMGROW stall ...
  why=off`); Market Drayton and Cheadle the same. Which of the two commands switches it off is not known (the town
  editor sends both; nothing in the base scripts says either touches the flag). Organic Towns now logs the flag after the
  DevelopAt calls and after the restore (`FILL ... active=before->develop:x->restore:y`) and switches it back on after
  every fill of a town that was on before its first fill (next run tells which command and whether the reactivate
  holds).

## The map's bounds and script street bridges (research 2026-10-13, not verified in a game-script state)

- **Map bounds:** `api.engine.terrain.getBoundingBox()` (`api/tealdef/api/engine.d.tl:1754`, `Box2f` with `min` /
  `max`) gives the terrain's extent; square_better_minimap reads it in a GUI script. Organic Towns reads it from its game
  script's guiUpdate (pcall-guarded; `[SQOT] MAP bounds=` logs it once) to keep its streets 400 m from the edge.
- **A street bridge in a proposal:** a street `SegmentAndEntity` becomes a bridge with `comp.type =
  api.type.enum.BaseEdgeType.BRIDGE` and `comp.typeIndex` = an `api.res.bridgeTypeRep` id (`type.d.tl:463-467`,
  `transformator.d.tl:468-469`: 0 normal, 1 bridge, 2 tunnel; `SegmentAndEntity.type` stays 0 = street). Move It
  (subscribed) converts ground edges to bridges that way in one SimpleProposal; creating a NEW bridge edge from a script
  is not shown anywhere. Base road bridges: `stone` (always), `steel` (from 1940), `concrete` (from 1970), `trestle_s`
  (road only, until 1970) in `base/content/infrastructure/bridge/*.bridge.lua`; resource names
  `::/infrastructure/bridge/<name>.bridge` (format unverified for `find`). No documented span, clearance or end-node
  rules. Organic Towns' river bridge (ot_bridge) is pre-checked, all or nothing, one try per town and session, and logs
  `BRIDGE` lines; the next real map run decides.

## Starting town size: where a new map's town population factor is set (read from the game files 2026-10-13, not verified in game)

Research for Organic Towns' "Starting town size" test setting (plans/square_organic_towns/PLAN.md 6.3).

- `BaseConfig.Locations.TownParamList` has `maxNumberPerArea`, `allowInRoughTerrain`, `townFrequency` and
  `populationDensity` ("Population will be scaled by this factor", `api/tealdef/api/type.d.tl:3534-3547`). Base's
  preRunFn creates `baseConfig.locations` with only the first two (`base/content/base/mod.script.tl:121-125`), then sets
  `baseConfig.locations.town.townFrequency` and `.populationDensity` from its params `locations.towns.frequency` /
  `locations.towns.populationDensity` (`mod.script.tl:199-200`, `difficulty_util.getScale`).
- `locations.towns.populationDensity` is the base game's **"Population"** setting (`base/mod.json:127-158`, Slider 50 % /
  75 % / 100 % / 150 % / 200 %, default 100 %, scale `{0.5, 0.75, 1.0, 1.5, 2.0}`, `difficulty_util.tl:80`). It is in the
  advanced settings and is shown for savegames too (`gui/menu/advanced_settings.tl:416-420`, outside the
  `if not isSavegame` block), which hints that it acts at runtime (residents), not only at map generation.
- **The new-game map preview generates the towns in the menu from its own locations config**:
  `makeMapPreviewCompInputs` builds a fresh `Locations` with `populationDensity` from the base params only
  (`gui/menu/new_game_or_map_settings_page.tl:402-421`), the `MapPreviewComp` makes the `GameMap` (towns with
  `sizeFactors`, `api/type.d.tl:229-247`), and "Start Game" passes that map to `app.startGame2` (`:613-636`). So a mod's
  preRunFn change to `populationDensity` may not reach the starting towns' size at all; Organic Towns' `[SQOT] START`
  lines (Game size vs Small on the same seed) will tell.
- A mod's preRunFn runs after base's (Organic Towns' angle setting was read back by `createTowns`, "Starting angle"
  above), so it can multiply base's value and keep the other fields.

## Locking the mod's arm streets doesn't keep a big town's form: the game fills the wedges from its own core (2026-10-13, inferred from a log + screenshots)

Real map run `2026-10-13_0232_sqot-dev` (Organic Towns, 16 towns grown ~9x by the dev growth simulation + Testing grow;
shots `.cache/ot_shots/2026-10-13_02-40-43/`).

- With the mod's arm / rim streets locked (`roadDevelopmentLocked`) and 41 % of the new street edges the mod's, the
  game still built the other ~59 %, and at 1000-3500 buildings the linear, fingers and radiating towns read as one
  round organic blob: the game's streets spread from its own unlocked core streets into every wedge between the arms
  (and kept extending its core's dead ends facing them).
- Unhoused town streets of the mod stayed empty for long: PLAN `emptyLen` 4-17 km per town at the end; houses came first
  to the streets nearest the core (as in Showcase v7).
- The dev growth simulation's "years" don't move the game calendar: 40 simulated years in 357 s at 8x left the game
  year at ~1900 (every STYLE line `gridBias=e=0.33`), so an era change needs a map started in that era.
- Consequence (Organic Towns real map round 4): wedge frames, locked streets joining the game's own dead ends in the
  wedges, with the arms' gates left open; whether the game crosses / attaches to them is still to be seen in game.

## A forced size command fills its residential capacity target at once (log sessions 2026-10-13_0356_top-up-779299, 2026-10-13_0118_top-up-148916, 2026-10-13_0205_top-up-61157)

- **x1-x1.55, 90 Medium towns** (session `2026-10-13_0356_top-up-779299`: initCaps 400, each town x(400 / its
  residents) from 261-398 residents, level weights {0, 0.1, 0.5, 1}, `makeTownUpdateSizeCmd(town, f, true)`): every
  town ended at its initialLandUseCapacities[1] x f (final / (400 x f): median 0.998, quartiles 0.997 / 1.0, 0.76-1.0),
  whatever its residents before; 89 of 90 the same at the command's answer as at the final check minutes later.
  The 17 towns at x1 ended at 398-400; pop min / mean / max 398 / 569 / 1020 for 400 wanted. The buildings dropped
  (33517 -> 21623 over the 90 towns: the level weights rebuild them taller and fewer).
- **Confirmed by sizing from capacity** (session `2026-10-13_0447_top-up-726115`: 69 Medium towns, initCaps 400,
  factor = target / (initial capacity x current size factor) = x1 for 400, level weights {0, 0.1, 0.5, 1}): pop min / mean
  / max **398 / 400 / 400** (69 of 69 read). A target at the initial capacity lands exactly; aim by capacity.
- **x3, 96 towns** (the two earlier sessions): mean 939 of 1200 = 0.78, 20 towns at 1150-1200: at larger factors
  the locked 8 x 8 grid runs out of room.
- So: a forced command fills its capacity target (initial capacity x size factor) at once, up to the room there
  is. The earlier reading "x the town's population" (x3: after / before 3.1) matched only because created towns
  averaged about 3/4 of their capacity. Size a town by its capacity target (the Stress Test's `growFactorForCap`;
  Medium towns for 400 people: x1, the level weights only).

## (superseded 2026-10-13, see above) A forced size command multiplies the town's population, at x3 (log sessions 2026-10-13_0118_top-up-148916, 2026-10-13_0205_top-up-61157)

96 Medium Lights showcase towns each (initial capacities 400, sizeFactors 1 -> 3, `makeTownUpdateSizeCmd(town, f, true)`,
locked grids, level weights {0, 0.1, 0.5, 1}): residents before 122-399 (mean 301), after 326-1198 (mean 939; 20 towns
at or near 1150-1200, the initial capacity x 3). Per town after / before = 3.1 (median; quartiles 3.0 / 3.2; range
2.7-4.2), and the population read at the command's answer equalled the one minutes later. Caveats: "before" is the
`personCaps` logged at `createTowns`, about 3.5 minutes before the size command (the towns may have grown a little in
between: the ratio is then slightly high); only x3 is measured. The cap: 20 of the 96 towns ended at 1150-1200,
the initial capacity x 3; at x10 (probe 2026-10-10, session `2026-10-10_0544_grow-x100-crash`) a fresh town of
initCaps 100 reached 836 of 1000 and Tacoma (233) 1347 of 2330, so with more room per factor the town stops short
of the cap. Inferred: the result is about the town's own population x factor, up to the initial capacity x factor.
To land towns at one size the Stress Test gives each its own factor from its population (`growFactorForPop`,
x1-x3.3 for 400 people): that outcome is not yet measured (TESTING.md 6V step 2).

## `makeInitialStreets` is applied when the game builds the map; industries don't need those streets (read from the game files 2026-10-13, not verified in game)

- The new-game page's map preview (`builtin.MapPreviewComp`, `base/content/gui/menu/new_game_or_map_settings_page.tl:815-850`)
  produces a `GameMap` that `app.startGame2` receives (`:628`). A `GameMap` (`api/tealdef/api/type.d.tl:229-315`) holds the
  heightmap, town entries (position, name, `sizeFactors`), industry entries (position, angle, file name), town connections,
  trees and assets: **no streets**. So the industry-edge streets of `baseConfig.locations.makeInitialStreets` ("Add small
  streets at the edge of industries", `type.d.tl:3554`) can only be laid when the game builds the world from that map at
  start, after the mods' `preRunFn` has set the running baseConfig (inferred). The preview's own locations config sets
  `makeInitialStreets = true` (`:407`), but it makes no streets. The same reading explains the "Starting town size"
  doubt: the town `sizeFactors` are already in the preview's map, before `preRunFn`.
- Industries: cargo is collected by stations in their catchment; their workplaces count as a production **booster**
  (`base/content/gui/entity_window/industry/industry.tl:176-180`: a `PERSON_CAPACITY` > 0 adds a booster row next to the
  stock list's booster rules). So an industry without generator streets still produces; whether its worker boost is lower
  until a street reaches it is unknown. Base comment on the field: "default true, false experimental"
  (`base/content/base/mod.script.tl:135`).
- Existing saves: `preRunFn` runs on every load, so the field is written again on load; it cannot remove streets. Whether
  the game reads it for industries founded later in a running game is unknown.
- Organic Towns (round 5) sets it false by default ("Streets at industries": Off; log `[SQOT] INDSTREETS choice=
  makeInitialStreets=from->to`). Check in game: a new map with Off has no small street clusters at its industries, and
  the industries produce.

## Satellite seeds refused by collisions outside the town's snapshot (2026-10-13, inferred from a log)

- Session `2026-10-13_0342_sqot`: three of four Organic Towns satellite seeds 1-1.5 km out were refused by the
  `makeProposalData` pre-check with `Collision` (2-18 collisions; partners with consecutive entity ids such as
  `ent90849..90852`, none of them in the town's street snapshot; `buildings=0`). Farms sit in that ring (satellites may be
  near light industry) and farm `FIELD` entities, tracks and country roads were not checked. The kind of the partners is
  now logged (`partners=ent<id>:field|track|street|con|node`) and the site search reads every `BASE_EDGE`, `CONSTRUCTION`
  and `FIELD` around the town (ot_engine.obstacles); the next run confirms what they were.

- **Joining a script street to a country-road node: not attempted (research 2026-10-13, read from game files and the
  mod's own findings; not verified in game).** Country street templates (`base/content/infrastructure/street/country/
  country_new_small.street_template.lua`) have 4 lane configs like the town streets: two `PERSON`/`CARGO` edge lanes and
  two road lanes, so ot_proposal's lane indexing (road lanes = count - 2) would fit them. But every verified join is a D3
  on a town **dead end** (a config with 0 connections); a country-road node is a degree-2 (mid-road) or 3-4 (junction)
  node whose config already carries the through connections, so joining it means removing and rewriting a working
  config for 3-5 segments, which nothing has tried (the config-removal crash class is in this file above). A new edge
  crossing a road without a node is a `Collision`. Organic Towns therefore never joins or crosses a country road: its
  M2 motifs run beside them (PLAN.md 6.3 "Motifs M2"). Open: a dev probe of a D3 on a degree-2 country-road node.

## Listing rail stations with their position and forecourt (read from tealdefs and base files 2026-10-13, not verified in a game-script state)

- **List:** `api.engine.system.stationSystem.getTown2StationsMap()` (every station, keyed by town; also `getStations(town)`,
  `getStation2TownMap()`; `.cache/game/api/tealdef/api/engine/system.d.tl:57-85`). Whether
  `getEntitiesWithComponent(ComponentType.STATION)` may be enumerated is unknown (some component types throw "Cannot loop
  over this component type", findings/gui.md): Organic Towns uses it only as a pcall fallback.
- **Station -> construction:** `api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)`
  (`system.d.tl:252`; base `mission/name_util.tl:11`); a kerbside bus stop has no construction (nil / < 0). A rail station
  is one CONSTRUCTION whose `stations` list holds its STATION entities; `Engine.Component.Station` has no position and no
  cargo flag (`type.d.tl:1319-1336`: tag, terminals, catchmentAreas, pool).
- **Rail:** `CONSTRUCTION.fileName` under `stations/rail/` (base `stations/rail/modular_station/modular_station.con.lua`;
  the exact string of a built station unconfirmed), or `stationGroupSystem.getCarriers(getStationGroup(st), -1, -1)[1]`
  holding `api.type.enum.Carrier.RAIL` (base `gui/line_vehicle_mgmt/line_util.tl:480-484`). `ConstructionType.RAIL_STATION`
  exists (`type.d.tl:2192-2212`) but no read of it was found.
- **Passenger:** `api.engine.util.station.isStationOfType(station, false)` (`engine/util.d.tl:555-558`); terminals carry
  `passengersLoad` / `cargoLoad` (`type.d.tl:1271-1296`).
- **Position / forecourt:** the construction's `transf` (Mat4f: `getTransl()`, `transformDirection(v)`,
  `type.d.tl:747-830`), BOUNDING_VOLUME as the fallback. The modular station's main building faces local -Y: its linkable
  person lanes lie at y = -17 and its street furniture at y = -16 (`stations/rail/modular_station/
  main_building_1_era_a.module.lua:7-18`), so the forecourt is `transf` origin + 17 m along local -Y. Unverified for side
  buildings and terminus layouts. A rail station has no street nodes of its own (only track edges,
  `modular_station.script.lua:459-474`): its access street is the player's / town's.
- Organic Towns (M3 station quarter, `ot_engine.railStations`) reads stations this way every 120 s; `STATIONS stations=
  dirs= ok=` in the log tells whether it works (TESTING.md "Motif checks" 50).

## The earliest start year is 1900 (user-reported 2026-10-13, not checked against the game files)

- The user reports that a new Transport Fever 3 game can start in 1900 at the earliest (the start-year choice in the new
  game menu). Not looked up in the game files or seen in a log here; the base default start (1960 fallback in
  `ot_engine.year`) is a separate assumption.
- Consequence for mods: any era curve, era gate or style band that changes before 1900 is dead weight, and a curve that is
  already half way at 1900 (e.g. Organic Towns' grid trend that ran from 1870) makes the earliest start look like a later
  one. Organic Towns recalibrated every era curve to 1900+ (plans/square_organic_towns/PLAN.md 6.3 "Era range 1900+").

## Reading trees near a town; the game has no "keep the forest" rule (read from tealdefs and base / mod code 2026-10-13, NOT verified in a game script)

- **Trees are asset groups.** `api/tealdef/api/engine.d.tl:77-87`: `AssetGroup` is "data attached to assets, in particular
  trees. Assets are grouped together when built together ... Usually comes together with a ModelInstanceList";
  `AssetGroupAutoRemove` is "attached to assets entities to enable automatic removal when it collides with newly built
  objects". Component types `ASSET_GROUP` and `MODEL_INSTANCE_LIST` exist (`engine.d.tl:1624,1634`).
- **Positions:** `ModelInstanceList` (`engine.d.tl:615-627`) holds `fatInstances` (`ModelInstance`: `modelId`, `transf`
  Mat4f) and `thinInstances` (`ThinModelInstance`: `modelId`, `pos` Vec3f, `rot`, `scale`; `type.d.tl:2237-2258`), with
  `_native` vectors (`:size()`, 1-based `:at(i)`, `type.d.tl:29-37`) "for more performant access", and a `dynamic` flag.
- **Which models are trees:** `api.res.modelRep.get(id).metadata.tree` (record `Tree { reputationFactor }`,
  `type.d.tl:4048`); the base construction menu tests it (`base/content/gui/construction/construction.tl:3695`,
  `construction_react_util.tl:2766`, with `metadata.rock`).
- **Search by position:** `api.engine.util.octree.findEntitiesInCircle(Vec2f, r, ComponentType)` (`engine/util.d.tl:323`)
  with `ASSET_GROUP` (the subscribed `undo_tf3_test` does it within 500 m, `player_assets.script.lua:88`) or
  `MODEL_INSTANCE_LIST` (the subscribed `schbrongx_minimap` lists every model list of the map in a GUI script and plots
  thin instances whose model has `metadata.tree`, sliced over frames: `minimap.script.tl:192-209, 242-290`). Neither mod
  logs group counts or timings; how many groups a map-generated forest makes and how many trees one holds is unknown.
- **No cheaper source found:** `UtilTerrain` (`engine.d.tl:1725-1780`) has height, water, bounds and
  `makeMapFromGame(..., withAssets)` (the whole map's assets in one GameMap: too big for a per-town read) but no
  ground-material or forest sampler; the `Terrain` component has `dataMaps : {string, HeightmapNew}` (`engine.d.tl:1221-1234`,
  keys unknown: possibly material layers, untested). The map generator's forests come from a node graph (Worley noise
  distance bands, `base/content/climates/*/*_gen.tree.lua`, comment at the top) with a seed scripts can't read: not
  reproducible.
- **The game removes trees, it never avoids them:** new streets and constructions remove the trees in the way (and, by
  the auto-remove component, presumably the town developer's houses and streets too: inferred, not seen in a log); a proposal's `collisionInfo.autoRemovalEntity2models` lists them
  (`type.d.tl:2714`) and `api.engine.util.getAutoRemovalEntityImpact(proposalData)` gives the reputation impact of removed
  trees and rocks per town (`engine/util.d.tl:654-657`). No baseConfig field or API makes a town keep or prefer forest.
  Trees regrow: base `terrain/reforestation.script.tl` sends `makeReforestationProposal` every step (0.6 of the map's
  tiles a month, at most 8 trees per tile) while `advancedOptions.isReforestationActive`.
- **Used by:** Organic Towns phase F (`ot_engine.forestReader`: octree `ASSET_GROUP` within ~2.1 km, model instance
  lists read with a per-group stride under a ~24k read budget, sliced 3 ms per tick; `ot_forest` grid of 50 m cells; FOREST
  debug line with `groups reads trees stride capped dense share p50 p90 listUs us slices err`). The in-game run
  (plans/square_organic_towns/TESTING.md 59) shows whether the read works, what it costs and how dense TF3 forests are.
