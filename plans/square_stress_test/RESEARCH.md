# Stress generator mod: feasibility research

Paths: `API` = `.cache/game/api/tealdef/api`, `BC` = `.cache/game/base/content`, `REL` = `.cache/game/mods/release`.
Tags: [C] confirmed by game files/findings, [I] inferred, [?] needs an in-game probe.

Note: `docs/wiki/` is TF2-era on these topics (baseconfig.md is marked Wip). `docs/findings.md` has nothing on towns,
vehicles, costs or sandbox, so everything below comes from game files.

## 1. Towns

- [C] `api.cmd.makeTownCreateCmd(towns : {TownInfo})` (API/cmd.d.tl:831; data record 345-351 has `towns` +
  `updateInitialLandUseCapacities`). `TownInfo` (API/type.d.tl:3175-3190): `name`, `position : Vec2f`,
  `initialLandUseCapacities : {integer}` (res/com/ind), `landUse2CargoNeedsCategories : {LandUseType:{string}}`,
  `majorStreetAngle`, `initialMajorStreetAngle`, `capacityScalingFactor`. Docs call it "extended town information for map generation".
- [C] The only base caller builds TownInfo through the engine: `api.engine.mapgen.createTowns(seed, {GameMap.Town})` returns
  `TownResult{toRemove,toAdd}` (API/engine.d.tl:1782-1800), then `makeTownCreateCmd(townResult.toAdd)`
  (BC/gui/map_editor/map_editor.tl:1621-1636). `GameMap.Town` (API/type.d.tl:231-247): `pos, name, sizeFactors{3},
  landUse2CargoNeeds, existing`. Built via `api.type.Map.Town.new()` (map_editor.tl:1743-1750, sizeFactors default {1,1,1}).
  `getMinMaxValidNumTowns()` gives the legal count range (map_editor.tl:2074; values [?]).
- [?] Whether `createTowns` / `makeTownCreateCmd` work outside the map editor (in a running game). Both are plain API, no editor
  guard seen, but the only call site is map editor code.
- [C] The in-game player tool "Town Builder" is a C++ `ConstructionAction.TownBuilder` (not a script command):
  `BC/gui/construction/construction_react_util.tl:3500-3550`. It sets `initialLandUseCapacity`, `landUse2CargoNeeds`,
  `initialMajorStreetAngleRange` (`getBaseConfig().townInitialMajorStreetAngleRange`) and `capacityScalingFactor`
  (`getBaseConfig().townCapacityScalingFactor`, type.d.tl:3721).
  There is also an "Experimental Town Builder" (`ACTION_TOWN_BUILDER_EXPERIMENTAL`, tools/town_builder_tool.script.tl:78-200,
  `town_builder_experimental_tool.res.lua`): per-district capacities `{50..450,600,800,1000,1200,1400,1600}`
  (tool.script.tl:80), capacity scaling 0.25-2.0. So 1600 per district x scale 2.0 is the biggest the stock tool offers [C].
  How the menu gates it (sandbox or not) is not visible in scripts [?].
- [C] Growth: `makeTownUpdateSizeCmd(townEntity, sizeFactors{res,com,ind}, updateAllBuildings)` (API/cmd.d.tl:876,
  data 403-410: `landUseSizeFactors`, "update all buildings to their target capacity"). Base growth script sends it with
  `updateAllBuildings=false` (BC/game_mechanics/towns/town_growth.script.tl:550,557). Current land use = `initialLandUseCapacities[i] * sizeFactors[i]` (town_growth.script.tl:370).
  `makeTownSetInitialLandUseCapacitiesCmd(entity, {res,com,ind})` (cmd.d.tl:862) is what the town editor uses.
- [C] Size limits found: the editor spin boxes allow 10..5000 per district (BC/gui/entity_window/town/town_eow.script.tl:1062-1066);
  the editor shows target = initialCapacity * sizeFactor and writes `target / sizeFactor` back (town_eow.script.tl:1002-1022).
  No hard limit appears in the commands' docs [?]. Natural growth is capped by district fraction rules (max 0.5 of a town, 0.4 of the map: town_growth.script.tl:14-17) and
  only ever increases when `floor(newSum) > floor(current)` (town_growth.script.tl:~395), so a scripted size set will not be shrunk by growth [I].
- [C] `makeTownSetDevelopmentActiveCmd(entity, bool)` (cmd.d.tl:856): growth script only touches towns with `developmentActive` (town_growth.script.tl:~340).
  Growth runs every `townDevelopInterval` (baseConfig, default 60 half-days, API/type.d.tl:3692; base/mod.script.tl:104; the script hardcodes `UpdateIntervalTownCount=30`, towns.script.tl:10).
- [C] `makeTownDevelopAtCmd(position : Vec2f, developStreets, upgradeBuildings)` (cmd.d.tl:844): "triggers development of towns at the given position; adds new buildings or street segments". No base caller found (grep over base + mods: only the d.tl). So YES the town can generate its own streets (`developStreets=true`) [C by doc, effect/speed unverified [?]].
  Whether one call develops one lot or a whole area [?]. A loop of calls is the fallback.
- [C] `makeTownConnectWithIndustriesCmd(townEntities, connections{{i,j}}, keep)` (cmd.d.tl:819, data 329-336) builds road connections between towns/industries (map editor: map_editor.tl:2626-2632, defaults from `api.engine.mapgen.getDefaultTownConnections`, API/engine.d.tl:1790). `makeTownAutoDetectConnectionsCmd` (cmd.d.tl:825). `baseConfig.townConnectionMaxBridgeLength` limits bridges (base/mod.script.tl:113).
- [C] Sandbox town editor: three plugins on `TownEowEditorExtensionPoint` (town_eow.script.tl:1151-1215): cargo demand (`makeTownUpdateCargoNeedsCmd`, :576), initial capacity (:1020) + development checkbox (:1035), district weights (`makeTownCustomDistributionWeightsCmd`, :731). The initial-capacity plugin has `condition = ...@isSandboxMode` (`town_eow_editor_initial_capacity.res.lua`), reading `params.state.isSandboxMode`. All sent through `useStepState` commit (GUI side).
- [C] `baseConfig.locations.town.populationDensity / townFrequency / maxNumberPerArea`, `economy.townDevelopment.cargoNeedsPerTown` (API/type.d.tl:3534-3547, 3573) control map-generation towns (preRunFn time, base/mod.script.tl:199-205). Alternative: a "dense map" preset via preRunFn only for new games; does not help for an existing save.
- [I] Fastest path to a huge dense town: makeTownCreateCmd with large `initialLandUseCapacities`, then `makeTownUpdateSizeCmd(town, {f,f,f}, true)` with big factors, then repeated `makeTownDevelopAtCmd(pos, true, true)`. All unprobed [?]. Watch building count vs. engine cost.

## 2. Roads by script

- [C] Streets/tracks: `api.type.SimpleProposal.new()`, fill `proposal.streetProposal` (`SimpleStreetProposal`, API/type.d.tl:2764-2790: `nodesToAdd, edgesToAdd, nodesToRemove, edgesToRemove, edgeObjectsToAdd, nodeConfigsToAdd...`), send `api.cmd.makeWorldBuildProposalCmd(proposal, context, ignoreErrors, playerInitiated, doDust?)` (API/cmd.d.tl:961). Assign whole Lua tables (no append after assigning; mods/square_bulk_bulldozer/content/bulk_bulldozer/bb_commit.tl header).
- [C] Working from-scratch example (rail): `BC/mission/tasks/auto_builder/track_builder.tl:7-77`: `NodeAndEntity` with negative ids (-3,-4) and `comp.position`; `SegmentAndEntity` `entity=-1`, `comp.node0/node1/tangent0/tangent1/position0/position1`, `comp.type = BaseEdgeType.NORMAL`, `typeIndex=1`, `type = 1` (rail), `laneConfigs`/`roadTemplate`/`roadStyle` from `api.res.streetTemplateRep.get(find(name))`, `roadType`. Reuse an existing node by passing its entity id and `BASE_NODE` component. Result nodes come from `res.proposal.proposal.addedSegments[1].comp.node0/1` (track_builder.tl:63).
- [C] Streets: `seg.type = 0` and `seg.streetEdge = BaseEdgeStreet` (API/type.d.tl:2519-2527, subscribed move_it `move_it.script.tl:3719-3728`, which copies an existing edge); `RoadType.STREET` (type.d.tl:1955). Street templates: `BC/infrastructure/street/town/town_new_{small,medium,large}.street_template.lua`, `country/country_new_*.street_template.lua`. Template fields: `laneConfigs, streetStyle, simBuildable (type.d.tl:5481)`.
- [?] A from-scratch road edge (no source edge to copy): whether `streetEdge` may be left default; what `Context.player` / `playerOwned` must be; terrain alignment (`Context.checkTerrainAlignment`, type.d.tl:2481). No local code builds a brand-new street edge from nothing; only rail (track_builder) and copy-and-modify (move_it, parallel_tracks_1 `parallel_tracks.script.lua:50-80, 372-380`).
- [C] Crossings in a grid: edge endpoints on the same new node id make the junction; intersecting existing edges needs splitting by the engine/proposal (not shown) [?]. A grid made of separate rows/cols that share node ids at crossings avoids that [I].
- [C] Alternative: let towns build streets (`makeTownDevelopAtCmd developStreets=true`), or `makeTownCreateCmd` which lays out the initial town street network itself (major street angle fields, base/mod.script.tl:110-111). `baseConfig.locations.makeInitialStreets` (type.d.tl:3554) is for industries.
- [C] Station stops on streets: edge objects, `SimpleStreetProposal.EdgeObject{edgeEntity (neg id of new edge), param 0..1, oneWay, left, model : ResName, playerEntity, name}` (type.d.tl:2767-2784); `model` is an edge-object construction resource (signals: subscribed undo `signals.script.lua:411-417`). Stops: `BC/stations/street/small_stops/small_new.con.lua` has `edgeObject={snapToStreet=true,...}` (lines 55-62), `streetTerminal` in `small_stops.script.lua`. Stop category 0, STOP_LEFT/RIGHT (mission_task_build_construction_util.tl:154-263). [?] exact call to place a stop on an existing/new street edge from script; needs a probe.
- [C] Depots/stations as constructions: `SimpleProposal.ConstructionEntity{fileName, params, transf(Mat4f), name, playerEntity, autoFillSlots}` into `proposal.constructionsToAdd` (type.d.tl:2832-2848; usage mission_05 `send_vehicle.tl:27-54`, BC/mission/tasks/utility/industry_activity.tl:12-25). Road depot: `::/depots/road/road_depot/road_depot.con` (tutorial_story.tl:782; DYNAMIC template; `road_depot.script.lua:189-199` `capacity=10`, `filterTags={"default"}`). It must connect to a street via snap/street connector [?]; `result.snapPoint` is defined in the script (road_depot.script.lua:~215).

## 3. Vehicles and traffic

- [C] Private cars are sim persons: residents are "car owners" and "if they decide not to use public transportation... might use a car" (docs/wiki/modding/vehicles/basics.md:104; car models need `car = {}` metadata). Pathing uses `MoveMode WALK/DRIVE/LINES` (API/type.d.tl:2364-2368; `SimPerson.destinations/moveModes/lastMoveMode` API/engine.d.tl:1086-1112). Person counts come from building `personCapacity` (wiki constructions/types.md:436-452; `PersonCapacity` engine.d.tl:827-840) so traffic scales with population [I].
- [C] Knobs: `baseConfig.simPersonDestinationRecomputationProbability` (type.d.tl:3696, default 1.0, base/mod.script.tl:108; wiki: "smaller values reduce performance load"). Raising above 1 is [?]. `advancedOptions.trafficSpeedSensitivityScale` (type.d.tl:3476), `simPersonHappinessDecay*` (3483-3484). No baseConfig knob for "car ownership share" found [C: none]. More people + more destinations + a congested road net = more drive trips [I]. `api.engine.system.simPersonSystem` can count persons (API/engine/system.d.tl:133-160).
- [C] Buying: `makeVehicleBuyCmd(playerEntity, depotEntity, TransportVehicleConfig)` (cmd.d.tl:892; data 424-433 returns `resultVehicleEntity`). A depot entity is a required argument: no depot-less purchase [C]. Config build: `api.type.TransportVehicleConfig.new()`, `.vehicles={TransportVehiclePart}`, `.vehicleGroups={n}`, `.muFileNames={}` with parts from `vehicle_util.makePart(modelId, forward, color)` (BC/gui/line_vehicle_mgmt/vehicle_util.tl:9-28; usage BC/mission/tasks/vehicle_util/replace_vehicles.tl:36-55). Model ids via `api.res.modelRep`, metadata `transportVehicle`; depot lists only models whose `filterTags` match (default `"default"`, wiki vehicles/basics.md:98). Base buy flow: vehicle_react_util.tl:344-382 (buy, callback, then SetLine).
- [C] Lines: `Line = api.type.Line.new(); line.stops = {Stop{stationGroup, station=0, terminal=0, ...}}` and `makeLineCreateCmd(name, Vec3f color, playerEntity, line)` (cmd.d.tl:767; example BC/mission/tasks/vehicle_util/mission_vehicle_util.tl:5-37, which reads `resultEntities[1][1]` in the callback). `makeLineUpdateCmd(entity, line)` (cmd.d.tl; example mission_04 everything.tl:73-98). Station group of a stop: `api.engine.system.stationGroupSystem.getStationGroup(construction.stations[1])` (send_vehicle.tl:58).
- [C] `makeVehicleSetLineCmd(vehicle, line, stopIndex)` (cmd.d.tl:922, send_vehicle.tl:60 uses stopIndex 0; vehicle_react_util.tl:376). `makeVehicleSendToDepotCmd(v, sell, jumpToDepot?)` can teleport (cmd.d.tl, doc). `maxVehicleCloneAmount` (type.d.tl, "console only").
- [?] Cost/time of mass buying: vehicle purchase needs money; inject money (see 9). `Line` mod example in repo: `mods/square_line_revert/content/line_revert/line_revert.script.lua:321`.
- [I] Fastest traffic generator: N depots + 2 stops on a long road + one line, buy hundreds of buses/trucks and `SetLine` them. Needs a probe for whether buys succeed in batches.

## 4. Industries

- [C] Engine API for creating industries (map-editor flow, BC/gui/map_editor/map_editor.tl:1554-1584): `api.engine.mapgen.createIndustries(seed, {GameMap.Industry})` -> `IndustryResult.toAdd : {IndustryInfo}`; per entry `api.engine.util.proposal.createIndustryProposal(seed, industryInfo, context)` (API/engine/util.d.tl:946-951), then `makeWorldBuildProposalCmd(proposal, context, true, false)`. `GameMap.Industry{pos, angle, onWater, fileName, tag}` (type.d.tl:249-260). Industry cons: `BC/industries/<name>/<name>.con.lua`.
- [C] Direct placement via construction proposal also works for the sandbox construction menu: category `industries` is "only in sandbox mode" (wiki modding/constructions/menu.md:62-63) [C wiki; gating code is C++].
- [C] Extension: `makeCreateIndustryExtendProposalCmd(constructionEntity, numTrySlots, numKeepSlots)` returns a `resultProposal` (cmd.d.tl:738, data 212-222; GUI use BC/gui/entity_window/industry/industry.tl:95). Apply that proposal with makeWorldBuildProposalCmd [I].
- [C] Cargo flow is automatic once the industry exists and a station/line serves it. Knobs: `locations.industry.industryProductivity/industryDensity/absoluteMinimum` (type.d.tl:3518-3531), `economy.industryDevelopment.*` (3566+; `spawnIndustries`, `closureProbability`, `extendTimeSpan`). Closure: `makeIndustrySetDespawnTimeCmd(entity, 0)` keeps an industry alive (industries.script.tl:96-102, subvention_util.tl:481). `makeIndustrySetManualDevelopmentCmd` exists (cmd.d.tl ~205). Debug: `api.cmd.debug.makeStockSetCargoAmountCmd(entity, stockId, amount, cargoType)` (cmd.d.tl:1015) sets stock amounts [C; availability in release build [?]].

## 5. Game controls

- [C] `makeGameSetSpeedCmd(speedup : integer)` "a positive number: the speed that the simulation will run at" (cmd.d.tl:708). UI speeds are `{0,1,2,4}` (BC/gui/game_bar/game_bar_widgets.tl:203). The UI helper clamps with `api.gui.game.getEstimatedMaximumGameSpeed()` (GUI thread only, API/gui.d.tl:783-786; game.tl:632-638) and re-commits when speed 2..4 exceeds it (game.tl:679-690). Sending the command directly (e.g. 8) skips that clamp [C by code reading]; whether the engine accepts >4 and keeps it [?]. Treat as probe. Speed 3 is a special "throttled" case (game.tl:622-628).
- [C] `makeGameSetDateCmd(Date)` (cmd.d.tl:703; `Date.new(y,m,d)`, API/type.d.tl:959-970). Used by `BC/mission/calendar.lua:7-25` (syncDate: `startDate:addOffsetDays`). `makeGameSetCalendarSpeedCmd(millisPerDay)` (cmd.d.tl:698; mission_04 sets 8000 then 0 to freeze the calendar: everything.tl:45,67). `makeGameSetTimeOfDayCmd`, `makeGameSetCloudCoverageCmd` (cmd.d.tl:712-716).
- [C] Debug: `api.cmd.debug.makeGamePerformSimulationStepsCmd(amount)` (cmd.d.tl:1019) advances the simulation by steps; also `makeSimPersonSetStateCmd` etc. Used only by `BC/gui/debug_panel/make_entity_debug_panel.tl` (panel with cargo/simperson tools; how it's enabled is not visible in scripts [?]).
- [C] `noCosts`/`sandboxMode` are `BaseConfig` booleans (API/type.d.tl:3723-3724), defaults false (base/mod.script.tl:81-82). Official mods set them in `preRunFn`: `REL/urbangames_no_costs/content/mod.script.tl:4-6` (`baseConfig.noCosts = true`), `REL/urbangames_sandbox/content/mod.script.tl:4-6` (`baseConfig.sandboxMode = true`), with `mod.json` `preRunScript`. The wiki's `sandboxButton` / `industryButton` (baseconfig.md:175-176) are TF2 names; not in the TF3 `BaseConfig` typedef [C: absent]. TF3 equivalent is `sandboxMode`.
- [C] `sandboxMode` is read once by the GUI: `isSandboxModeRef = react.useRefLazy(function() return api.res.getBaseConfig().sandboxMode end)` (BC/gui/main/game.tl:732, used :880), which feeds entity windows (town editor tabs etc.). A runtime flip after the HUD mounted likely will not be seen [I]; `getBaseConfig()` at runtime being writable is [?].
- [C] A mod can therefore enable sandbox (town editor with 10..5000 capacities, industry menus) only at load time through `preRunFn`. A mod.json param can feed it: `allModParams[modId].key` (1-based index, findings.md:19-21; preRunFn signature `preRunFn(captureParams, configDict, allModParams, baseConfig)` findings.md:18). Param numbers must be doubles (memory note).

## 6. Where commands may be sent from

- [C] `sendCommand` is used from GUI scripts (react callbacks; bulk_bulldozer: "GUI thread only", bb_commit.tl header; town editor, map editor) and from game scripts (town_growth.script.tl:550 `update`, emissions.script.tl:130, mission tasks).
- [C] findings.md:116-118: `sendCommand(cmd, callback)` from a game script's engine `update` fails with "Callbacks are currently disallowed"; send without callback and check later. Conflict [?]: base mission tasks call `sendCommand(cmd, callback)` from `onUpdate` (track_builder.tl:60-74, called from `mission_sim.script.tl` update at ~655) and read the result synchronously. Not reconciled; probe before relying on callbacks in `update`.
- [C] Memory notes: no `sendCommand` inside onPre/PostBuildProposal events (asserts `!m_betweenChanges`); `react.onStepTimer`/HUD icon scripts run on worker threads (GUI calls crash), `react.onStep` runs on the Main Thread (findings.md:349-366). So a stress window should drive a queue from `react.onStep` (or a game script `update`) and send a bounded batch per tick [I].
- [C] `getEstimatedMaximumGameSpeed`, `api.gui.*` are GUI-thread only. `api.engine.mapgen.*` availability in game scripts [?].
- [C] Existing repo GUI patterns to copy: `mods/square_industry_flows/content/industry_flows/gui/flows_window.script.tl`, `mods/square_bulk_bulldozer/content/bulk_bulldozer/` (batched proposals with split retries). Recipe/layout crash rules in memory notes.

## 7. Load-time only vs runtime

Load-time (preRunFn/mod.json, `baseConfig`): `sandboxMode`, `noCosts`, `townDevelopInterval`, `simPersonDestinationRecomputationProbability`, `townCapacityScalingFactor`, `townInitialMajorStreetAngleRange`, `locations.*`, `economy.*`, `advancedOptions.*`, `emission.*` (base/mod.script.tl:81-211; baseconfig.md:12-17 says getBaseConfig() in game scripts is for reading). Wiki says writes in `postRunFn` via `api.res.getBaseConfig()` [C wiki, TF2-era]; writing from game/GUI scripts at runtime [?], and the effect on already-built engine state is unknown. Games already running keep what was set at load; settings are applied when the mod set loads (a save with the mod enabled must be reloaded).

Runtime (commands): town create/size/develop/dev-active/initial capacity/cargo needs/weights; roads/constructions/stops via proposals; lines and vehicles; speed, date, calendar speed, time of day, clouds; journal money; entity emissions; industry despawn/extend/manual development.

## 8. Existing mods for patterns

- `REL/urbangames_sandbox`, `REL/urbangames_no_costs`, `REL/urbangames_vehicles_no_end_year` (runFn `addModifier("loadModel")` setting `availability.yearTo = 0`, `content/mod.script.lua:4-9`): best minimal examples of cheat toggles.
- `.cache/subscribed/move_it`, `parallel_tracks_1`, `move_it_probe_overpass`: build streets/tracks from Lua proposals (street edge copy-and-modify; `seg.type = 0` + `streetEdge`).
- `.cache/subscribed/zhenya_auto_assign_terminals`, `auto_line_namer_1`, `ui_overhaul_1/gui/terminals.lua`: LINE read/update commands (`makeLineUpdateCmd`).
- `.cache/subscribed/undo_tf3_test/content/undo/cost_probe.script.lua:50`, `house_history.script.lua`: money booking and a TownBuilding command user (it matches `makeTown`).
- Nothing local creates towns or grows them by script (`grep makeTown` over subscribed + mods: only undo house_history). Town creation/growth by script is untested in this repo.
- Repo mods: `mods/square_full_refund` (journal book), `mods/square_line_revert` (line create/update), `mods/square_bulk_bulldozer` (batched proposals), `mods/square_aat_perftest` (perf harness pattern).

## 9. Infinite money

- [C] `baseConfig.noCosts = true` in `preRunFn`: `REL/urbangames_no_costs/content/mod.script.tl:4-6` (mod.json `preRunScript "urbangames_no_costs_1::/mod.script@preRunFn"`, no params). Load-time only [I]; no runtime toggle command exists in cmd.d.tl [C: grep found none]. Wiki: "noCosts disables all costs" (baseconfig.md:177). Cost scales also exist in `costs.*` (base/mod.script.tl:221-229) [C].
- [C] Runtime money: `makeJournalBookAssetCmd(player, JournalEntry, position?)` (cmd.d.tl:744-749). Entry: `entry.amount`, `entry.time = -1`, `entry.category.type = JournalEntry.Type.OTHER` (mods/square_full_refund/content/refund/refund.script.tl:118-129; campaign mission_04 books 30,000,000 in onStart: everything.tl:50-55). Player: `api.engine.util.getPlayer()`. Sent from handleEvent (proven there). Balance read: `ACCOUNT` component `balance`, `loan` (API/engine.d.tl:22-29; `api.engine.getComponent(player, ComponentType.ACCOUNT)`, bb_commit.tl balance()). Periodic top-up: read balance from update, book the difference when below a threshold [I]. Integer overflow limit of `amount` [?].
- [C] `makeGameAddPlayerCmd(name, color)` (cmd.d.tl, GameAddPlayerCommandData) creates another player (used to spawn AI players for line ownership: mission_vehicle_util / transfer_ownership_util) [C]; not needed for money.
- Recommendation: use the journal top-up at runtime and optionally also ship a variant with preRunFn `noCosts` [I].

## 10. No pollution / noise

- [C] `makeEntitySetEmissionsCmd(entity, noisePower, pollutionPower, radius, pollutionRadius)` (cmd.d.tl:671-672; data record 113-122 lacks pollutionRadius). Sets an entity's emitter values. Base use: `BC/game_mechanics/emission/emissions.script.tl:129-130` which recomputes per entity from model `emissions` metadata x `ecoFactor` x `advancedOptions.missionEmissionsScriptFactor`, re-sending when changed. So setting to 0 per entity will be overwritten by that script unless `missionEmissionsScriptFactor == 0`, which makes `update` return early (emissions.script.tl:27-29) [C]. Effect of factor 0 on emissions overall (zero vs. unmanaged) [?].
- [C] Config: `baseConfig.emission.noiseLowerBoundDB/noiseUpperBoundDB/pollutionLowerBoundDB/pollutionUpperBoundDB`, `townNoise{Residential,Commercial,Industrial}Affected` (API/type.d.tl:3649-3659; base/mod.script.tl:177-180). Setting the `*Affected` booleans false removes noise from town ratings [I] (read at town_util.tl:1726-1732, town_building.tl:363). Pollution: `advancedOptions` has `emissionSensitivityScale` in the wiki (baseconfig.md Advanced options) but not in the TF3 typedef [C: absent]; town ratings use `SensitivityNoise`/`SensitivityPollution` (default 4; `BC/game_mechanics/towns/town_ratings_sensitivity.res.lua:9-10`, town_util.tl:29-31,82-85), editable per town in the editor plugin (`TownEditorRatingsSensitivity`, town_eow.script.tl:929-960; saved through the towns game script, towns.script.tl:346-364).
- [C] Model-level: the `loadModel` modifier can edit `data.metadata` (precedent: no_end_year). Zeroing model `metadata.emissions` at load time is plausible [I]; precedent for per-vehicle noise fields in type.d.tl:1135-1139,1438.
- [C] Global kill switch for the emission simulation: none found. Per entity: `makeEntitySetEmissionsCmd` or `debug.makeComponentExchangeCmd` (EmissionEmitter, cmd.d.tl:1008). Wind: `makeWorldChangeWindCmd` (cmd.d.tl:968). [?] what actually dominates town growth penalty; probe.
- [C] Phase 4 follow-up (2026-10-10, after probe 8 failed): vehicle emissions come from `metadata.emissions.{noise,pollution}.{score,idle,speed,power}`; the base runFn fills idle/speed/power from the score (`base/base_mod.lua:84-85` -> `base/model_metadata_util.lua:312-376`), so a later `loadModel` modifier can zero them. The emissions script only manages industries, stations, depots and warehouses (`emissions.script.tl:197-251`); factor 0 stops it but leaves their last values. Town ratings: a sensitivity <= 0 gives rating 1.0 (`town_util.tl:412-439`); the default index is a script config the base postRunFn writes (`base/mod.script.tl:676-692`, scale table `base/difficulty_util.tl:48-49`, index 1 = 0). Implemented as the "No noise and pollution" param and the Game tab's town ratings action (stress_logic.tl).

## 11. Instant year change

- [C] `makeGameSetDateCmd(Date.new(year[,month,day]))` (cmd.d.tl:703-707): "the calendar date (for vehicle availability, etc.) is set". `calendar.syncDate` (BC/mission/calendar.lua:7-25) shows the base pattern: compute offset days from `GAME_TIME.gameTime` and `GAME_SPEED.millisPerDay` and set the date; mission_04 also sets the calendar speed first (everything.tl:44-45). `api.engine.util.getCalendarDate(gameTime)` reads the current date (util.d.tl:1030).
- [I] Side effects: vehicle/street/station availability use year (`availability.yearFrom/yearTo`, `busLaneYearFrom` etc. type.d.tl:3687-3689), new buildings appear per era, vehicles age (purchaseTime, lifespan, vehicle_util.lua), fines or yearly charge events fire; jumping many years at once might trigger lots of catch-up work [?]. Existing vehicles keep their `purchaseTime`.
- [C] `makeGameSetCalendarSpeedCmd(millisPerDay)`: day length only, not simulation speed; 0 freezes the calendar (everything.tl:67). A very short `millisPerDay` makes time fly while the sim runs at 1x (side effects as above) [I].

## 12. Other cheat-style toggles

- [C] `urbangames_vehicles_no_end_year`: `addModifier("loadModel", ...)` sets `metadata.availability.yearTo = 0` for vehicles (`content/mod.script.lua:4-9`), load-time. Counterpart for year-from needs `yearFrom = 0` [I].
- [C] `makeTownBuildingSetBlockedDevelopmentCmd` (historic), `makeTownSetDevelopmentActiveCmd`, `makeIndustrySetManualDevelopmentCmd`, `makeIndustrySetDespawnTimeCmd`, `makeVehicleSetModifiersCmd(entity, TransportVehicle.Modifiers)` (cmd.d.tl:~890-960; modifiers record in engine.d.tl [?] fields), `makeVehicleTryToDepartCmd`, `makeVehicleSetManualDepartureCmd`, `makeVehicleSendToDepotCmd(…, jump)`.
- [C] Time/weather: `makeGameSetTimeOfDayCmd(seconds)`, `makeGameSetCloudCoverageCmd`, `makeWorldChangeWindCmd`. Used for time of day in mission tasks (BC/mission/tasks/utility/time_of_day.tl:43).
- [C] Debug set (`api.cmd.debug.*`, cmd.d.tl:985-1025): maintenance cost update, sim person state/happiness, component exchange, stock cargo amount, perform N simulation steps, clear logbooks. Release-build availability [?].
- [C] baseConfig toggles worth listing (type.d.tl:3470-3724): `advancedOptions.subventionFinancialRewardMultiplier`, `vehicleMaintenance*Effect`, `missionDisableTunnelBuilding`, `isReforestationActive`, `maxVehicleCloneAmount`, `trainAccelerationFactor`, `terrainTool*` limits, `economy.industryDevelopment.spawnIndustries`.
- "Instant build": no explicit command found; proposals through `makeWorldBuildProposalCmd` finish immediately when sent from script (the mission track_builder reads results right after sending) [I]; the construction scaffold animation is separate [?].

## Open probes (priority)

1. makeTownCreateCmd with hand-made TownInfo (and via `mapgen.createTowns`) in a running, non-editor game; what max `initialLandUseCapacities` is accepted.
2. makeTownUpdateSizeCmd large factors with updateAllBuildings=true: building count/time, any clamping.
3. makeTownDevelopAtCmd(developStreets=true): how much it builds per call.
4. From-scratch street edge proposal (street template, `streetEdge`, junction handling), then stop edge-object and road depot placement on it.
5. makeVehicleBuyCmd batch + makeLineCreateCmd + SetLine from `update` vs GUI `onStep`; callback availability (conflict in section 6).
6. makeGameSetSpeedCmd above 4 and journal top-up with large amounts.
7. Whether runtime writes to `api.res.getBaseConfig()` (noCosts/sandboxMode) have any effect.
8. Emission zeroing: factor 0 vs per-entity SetEmissions.
