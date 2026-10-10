# Supply Gap Overview (`square_supply_gaps`): plan

Plan written 2026-10-09. Mod: `mods/square_supply_gaps/`. Tests: `tests/square_supply_gaps/`.
In-game checklist: `TESTING.md` (written in Phase 2). Log prefix `[SQSG]` in `<userdata>/crash_dump/stdout.txt`.

## Goal
A toggle that marks every **town building that needs a cargo but is not reached by any station
delivering that cargo**. Example: a town needs fish, so its commercial buildings have a fish input
stock; those outside the catchment of every stop of a fish-carrying line get a marker. Pick the cargo
in a small window ("All needed" or one cargo). The markers stay up while the player places or edits
bus/truck stops and stations, so gaps can be closed on the spot.

Related vanilla views: the Cargo Flow layer (`base/content/gui/layers/layer_cargo_flow.tl:185-226`
`getConfig`: `CargoColor` townBuildingPainter = supply rating per land use, no per-cargo filter) and the
town window's supplies layer (`gui/entity_window/town/town.tl:39-70`). Neither can say "this building
gets no fish".

## Decisions
| topic | decision | why |
|---|---|---|
| "Needs cargo c" | the building's STOCK_LIST has an `InputStock` with `cargoType == c` (passengers skipped) | town buildings get one INPUT_STOCK per needed cargo (`base/content/buildings/townbuildingutil.lua:222-249`); this covers commercial, industrial **and** residential (when `Town.cargoNeeds[1]` is non-empty) with no land-use logic. `Town.cargoNeeds : {{{CargoTypeId, number}}}` indexed by `LandUseType + 1` (`api/tealdef/api/engine.d.tl:1295`; residential = `[1]`, `layer_cargo_flow.tl:322-325`; `town_util.tl:13-15`) is only used to build the cargo picker and to log a mismatch |
| Land use (picker filter / summary) | `PERSON_CAPACITY.type` of `TownBuilding.personCapacity` (`engine.d.tl:837-838`, `+1` index as `town_util.tl:1167`) | per-building, documented |
| "Reached" | building B is reached for c when B (or `TownBuilding.stockList` of B) is in `catchmentAreaSystem.getStationCatchables(station, true)` (`api/tealdef/api/engine/system.d.tl:445-448`, "entities holding a StockList") for some station of a **station group that delivers c** | same catchment test the engine's auto load config uses (`gui/line_vehicle_mgmt/line_util.tl:540-560` → `cargo_util.getInputOutputStocksForStation`, `cargo_util.tl:543-563`: union of every station of the group) |
| "Delivers c" | a station group G delivers c when a LINE has a stop at G whose terminal unloads cargo (`Terminal.cargoUnload ~= false`, `api/tealdef/api/type.d.tl:1286-1291`; `line_util.tl:556-558` uses it the same way) and the line **carries c**: some stop of the line has `stopConfig.load[c + 1] == true` (`engine.d.tl:505-509`, read as in `cargo_util.getConfiguredStopCargoTypes`, `cargo_util.tl:818-835`), c not passengers | the line's load config is the only per-line cargo list the API keeps; a line that loads fish anywhere unloads it at any stop whose catchment has a fish input stock (`StopConfig.forceUnload` comment, `engine.d.tl:511-513`). Line → stops from one bulk call `lineSystem.getStationGroup2LineStopsMap()` (`system.d.tl:45`), stop = `LINE.stops[stopIndex0 + 1]`, exactly as `production_label_pickup.tl:220-340` (verified in game for pickup). Optional cross-check logged in Phase 2: `transportVehicleSystem.getLineCargoInfo(line, c).totalCapacity > 0` (`system.d.tl:393-396`, `type.d.tl:4185-4199`) |
| Fallback semantics | window checkbox **"Count stops without a line"** (off by default): every station group with a cargo-unloading terminal counts as delivering every cargo | needed while placing: a freshly placed stop is on no line yet. Also the fallback if the line rule proves wrong in game |
| Town-level numbers | `townBuildingSystem.getCargoSupplyAndLimit(town, landUse?)` → `{cargo: {supply, limit, ?}}` (`system.d.tl:113`; rounding as `town_util.tl:91-108`) for the window's "supply 12 / 40" per town | display only; it is town-wide, not per building |
| Where it runs | GUI only: the ridge plugin's script on the GUI thread (`react.onStepTimer`, `base/tealdef/scripts/react.d.tl:304`). No `runFn`. Exception ("Per-save state"): a tiny game script keeps the on/off flag per save | memory "Don't impact existing saves"; GUI-thread APIs (`api.gui.mission`, `api.gui.camera`) are allowed there, unlike HUD recipes (memory "HUD recipes not on GUI thread") |
| Entry point | ridge button in `::MainModButtonAreaExtension` (`gui/main/main_mod_button_area.tl:7`, mounted always in `gui/main/game.tl:554`): `react-plugin` res + plugin recipe, the proven pattern of `mods/square_industry_flows/content/industry_flows/gui/flows_window.res.lua` and `square_problem_radar` `radar_hud.script.tl:855` | |
| Window | a **plain singleton window**, not a tool: `game_react_globals.getDefaultWindowApi().addSingletonWindow / removeAllWindows` (`radar_hud.script.tl:778-810`) | a tool on the stack is closed by the construction menu, and a LayerConfig from it only renders while it is on top (`plans/square_industry_flows/PLAN.md` "How a mod panel makes a LayerConfig take effect"). The overlay must survive tool changes, so it is driven by module state, not by a tool |
| Overlay switch | "Show supply gaps" checkbox in the window; the ridge button opens/closes the window; closing the window keeps the overlay; the button shows an "on" state | player closes the window and keeps the markers while building |
| Rendering, track A (reliable) | **mission markers**: `api.gui.mission.setMarkerAtEntity(key, entity, type, scaling, isSelectable, fireSelectEntity)` / `removeMarker(key)` (`api/tealdef/api/gui.d.tl:719-739`), keys `sqsg:<entity>`, diffed per tick, cap `MAX_MARKERS = 300` nearest to `api.gui.camera.getCameraData()` centre (`gui.d.tl:431-433`, Vec5f `{x, y, distance, angle, pitch}`) | GUI-level world markers independent of the active tool. Base: `mission/mission_sim.script.tl:1072-1084, 1137-1139` (only removes **its own** known keys), type `"arrow"` (`mission/tasks/create_line/create_line_for_towns.tl:98-103`); marker models `base/content/assets/markers/marker_{arrow,exclamation,exclamation_red,question,question_red,locate}.mdl` (other type strings unverified) |
| Why not hudIconScript (the production-label route) | rejected | HUD icons exist only for entities in the HUD manager's preFilter; the default filter has no TOWN_BUILDING (`gui/main/selector_react_util.tl:14-23`), `HudIconMasterGame` deliberately skips town-building stocks (`gui/main/hud_icon_toolbox.tl:196-198`), and the custom script is only taken for `con.subconstructions[1]` of constructions it visits (`:242-251`). Thousands of town buildings would also mean thousands of recipes on the HUD worker thread |
| Track A2 (fallback) | `api.gui.mission.setZoneCircle(key, center, radius, draw=true, color, prohibitBuilding=false, playAnimation=false)` (`gui.d.tl:704-713`) at the building position | if markers don't render in free play or look wrong; same keyed lifecycle |
| Rendering, track B (probe) | while the overlay is on, patch the **native construction tools**: wrap `construction_react_util.getActionParams` (proven: `docs/findings.md` "Native construction tools can be patched from a mod"; `mods/square_smart_lanes/content/smart_lanes/sl_tool.script.lua:147-180`) and add to `res.layerConfig` (B1) cargo catchment circles `catchmentAreaRenderableConfig` (`type.d.tl:4911`, record `:4704-4730`, base use `entity_window/maintenance_station/maintenance_station.tl:130-135`) and (B2) the Cargo Flow `CargoColor` painter (`includePassengers=false`, 5 levels, as `layer_cargo_flow.tl:185-194`). (B3) per-entity highlight via `ActionDescriptorParam.highlightedEntities` (`base/tealdef/scripts/builtin.d.tl:1337-1346`; base use `line_vehicle_mgmt/line_util.tl:1182` for vehicles) needs a wrap of `builtin.ActionDescriptor` (`gui/main/builtin.lua:176`), because construction.tl builds the descriptor itself (`gui/construction/construction.tl:4438-4485`): DEV flag, off unless the probe enables it | no LayerConfig painter can colour single town buildings: `townBuildingPainter` takes BaseColor / CargoColor / DestinationColor / EmissionImpactColor / LandUseColor only (`type.d.tl:4606-4607`); per-entity highlight exists only on the ActionDescriptor |
| Track B scope | definitions with `action == "ACTION_STREET_TERMINAL_BUILDER"` (street stops, `construction_react_util.tl:971-993`), `"ACTION_MODULE_BUILDER"`, or `hudIcons.showDistricts == true` (every station: `construction_desc_react_util.tl:1040-1055`) | the tools the user edits stops with; stations already get the district `CargoColor` painter there (`construction_react_util.tl:595-631`) |
| Player-picked layer | wins, as in base (`mergeLayerConfig`, `construction_react_util.tl:3985-3990`); we never fire `preferredLayerConfig` | firing it would fight the layer ridge, which resets it to nil (`gui/layers/layers_button_ridge.tl:99, 135, 277, 510`) |
| Own layer in the left menu | not possible | the ridge's layer list is a hard-coded table inside a recipe (`layers_button_ridge.tl:300-430`), no extension point, no `getPlugins` call |
| Refresh | tick every `TICK = 1.0` s while the overlay is on, nothing while off; bounded work per tick (see Cache) | never per frame |
| Save safety | `severityAdd: None`, `severityRemove: Warning` (since "Per-save state"; was None), `cosmetic: true`; read-only; markers are GUI-only and removed when the overlay is switched off; no global overrides other than the two guarded GUI wraps (B), which are pass-through while the overlay is off | memory "Don't impact existing saves" |
| Map editor | inactive (`api.gui.game.isMapEditor()`, as `flows_window.script.tl:673-674`) | |
| Language | Teal for model / gather / window (like industry_flows); **Lua** for the patch module `sg_patch.lua` (dynamic wrapping, as smart_lanes) | |

## Data flow
```
tick (GUI, 1 s, overlay on)
  gather.lines()      getStationGroup2LineStopsMap + LINE reads  -> group -> {cargo}   (every tick, cheap)
  gather.buildings()  getTown2BuildingMap + TOWN_BUILDING + STOCK_LIST + PERSON_CAPACITY (every 10 s or on count change)
  cache.step()        catchables for new stations now, STATIONS_PER_TICK others round robin
  model.compute()     pure: needs x delivering groups x catchables -> gaps per cargo, per town
  markers.apply()     diff vs last set: setMarkerAtEntity / removeMarker (cap, nearest camera)
  probe patch reads   module state (on, gap entity list, flags) at render time
```

### Model (`sg_model.tl`, pure, tested)
- Input `SupplyGapsWorld`: `buildings[b] = {town, landUse, needs = {cargo}, stockList, pos}`,
  `groupCargo[g] = {cargo: true}` (or `ANY` when "Count stops without a line"), `groupStations[g] = {station}`,
  `catchables[station] = {entity}`, `towns[t] = {name, needs per landUse}`.
- `index(buildings)`: catchable entity -> building (both `b` and `stockList`; logs which one matched).
- `compute(world, selection)` -> `SupplyGapsView{ cargos = {c: {needed, reached, towns = {t: {needed, reached}}}},
  gaps = {b: {missing cargos}}, total }`. "All needed": a building is a gap when any of its needs is
  unreached; one cargo: when that cargo is unreached.
- `pickerRows(view, townsNeeds)`: "All needed" + every cargo some town needs, sorted by unreached desc,
  then name; counts `unreached / needed`.
- `markerPlan(gaps, positions, camera, cap)`: nearest `cap`, deterministic tie order (entity id);
  `diff(prev, next)` -> `{add, remove}`.
- All iteration in sorted entity order so results never depend on `pairs` order.

### Gather (`sg_gather.tl`, engine adapter, stubbed in tests)
- Lines: `lineSystem.getStationGroup2LineStopsMap()`; per line one `LINE` read (memoised per tick),
  carried cargos = union of `stopConfig.load` (copy the userdata vector into a plain table first, as
  `production_label_pickup.tl` does); stop terminal via `STATION.terminals[terminal + 1].cargoUnload`
  (0-based, `production_label_pickup.tl:324-338`). `LEGACY_UNLOAD_ONLY` stops still unload: no skip.
- Buildings: `townBuildingSystem.getTown2BuildingMap()` (`system.d.tl:122`); `TOWN_BUILDING`
  (`engine.d.tl:1305-1325`: `personCapacity, stockList, town`); `STOCK_LIST.stocks[i]` with
  `type == api.type.enum.StockListType.InputStock` (`town_building.tl:84-88`) and `cargoType`;
  position `entity_util.getPosition(b)` (`base/content/scripts/entity_util.tl:48`) once per new building.
- Station groups: `STATION_GROUP.stations`; catchables per station from the cache.
- Every read in `pcall`; a failing entity is skipped and counted (`ERR` log, max 20).

### Cache (`sg_cache.tl`, pure scheduler + adapter)
- `catchables[station] = {list, tick}`. New station (not cached) -> fetched this tick (a stop just added
  to a line shows within 1 s). Others refreshed round robin, `STATIONS_PER_TICK = 25`, so a 500-station
  map cycles in 20 s (town growth, rebuilt buildings). Stations no longer in any delivering group are
  dropped.
- Only stations of **delivering** groups are queried (passenger-only lines never cost a catchment call).
- Buildings re-read every `BUILDING_EVERY = 10` ticks, or at once when the town -> building count
  changes. New building ids may show as a gap until their stations' next refresh (documented).
- Per-tick time measured with `os.clock()`; `PERF` log every 30 ticks (ms max/avg, stations queried,
  catchables total, buildings, gaps, markers set/removed). If a tick exceeds `BUDGET_MS = 8`, halve
  `STATIONS_PER_TICK` (min 5) and log once.
- Paused game: `onStepTimer` may not fire while paused (unverified); Phase 2 logs it. If it doesn't,
  fall back to `react.onStep` with our own 1 s `os.clock` gate.

## UI (`gui/sg_window.script.tl`, `sg_window.css.lua`)
- Ridge button (icon + "on" class while the overlay is on) -> toggles the window.
- Window ~320 px: checkbox **Show supply gaps**; cargo list (`builtin.CheckBox`-style single-select rows:
  cargo icon via `cargo_react_util.makeCargoIcon`, name, `unreached / needed`), first row "All needed";
  checkbox **Count stops without a line**; summary "Fish: 14 of 52 buildings unreached in 3 towns" and
  "Showing 300 nearest of 912" when capped; per-town rows (name, unreached, `supply / limit` from
  `getCargoSupplyAndLimit`), click = `api.gui.camera.setManualCamera(townPos, 800)` (`gui.d.tl:429`).
- Session state (selection, flags) in a module table; only "Show supply gaps" is persisted per save ("Per-save state").
- GUI rules from memory: recipes return layouts, never `Component{layout = Recipe{}}`, ScrollArea content
  is a `Component` with a builtin layout, no unknown fields in builtin calls (check `*Param` records in
  `builtin.d.tl`).

## Phases
Every phase: `make check MOD=mods/square_supply_gaps`, `make test MOD=mods/square_supply_gaps`,
`make validate MOD=mods/square_supply_gaps` pass; brief includes the save-safety and GUI rules above.

### Phase 1: scaffold + model + gather (offline)
`make new-mod ID=square_supply_gaps NAME='Supply Gaps' ARGS='--tag "Script Mod"'` (no runScript), then
set `cosmetic: true`, severities None/None, authors square.
Files: `mod.json`, `_metadata/modinfo.json`, `_metadata/description.html` (Changelog rev 1),
`content/supply_gaps/sg_types.d.tl` (+ byte-identical `tealdef/supply_gaps/sg_types.d.tl`,
`tealdef/square_supply_gaps_def.d.tl`, as industry_flows), `sg_model.tl`, `sg_gather.tl`, `sg_cache.tl`.
Tests: `tests/square_supply_gaps/test_model.lua` (needs per stock list, residential needs, "All needed"
vs single cargo, catchable = building or stockList, ANY mode, passengers ignored, cargoUnload=false
ignored, deterministic order, cap + nearest + diff), `test_cache.lua` (new station immediate, round robin
coverage, budget halving, dropped stations), `test_gather.lua` (fake api: userdata-like load vectors,
0-based stop/terminal indices, pcall skips).
Done: all three make targets pass; ≥ 30 tests.

Phase 1 as built (2026-10-09), deviations from the text above:
- Scaffolded with `ARGS='--tag "Script Mod" --cosmetic --summary ...'`; description uses `<h4>` sections.
- `gather.lines()` reads the map only for the **set of lines**, then uses every stop of each LINE
  (a per-line union needs no `stopIndex0` matching). Unknown station/terminal (-1, out of range) = unloads.
- Pure "delivers" rule lives in the model: `model.deliveringGroups(lines, passenger)` and
  `model.addUnlinedGroups(groupCargo, gather.unloadGroups())` (unloadGroups = groups with a terminal
  `cargoUnload == true`). `ANY` is the cargo key `model.ANY = -1`; `compute(world, selection)` takes
  `selection = nil` for "All needed". `view.match` counts building / stockList catchable hits (MATCH log).
- Cache API: `cache.new/step(c, stations, fetch)/catchables/buildingsDue(c, count)/noteTime(c, ms)/perf/
  engineFetch`. **All** uncached stations are fetched in the tick they appear (not capped by perTick), so
  the first tick or switching "Count stops without a line" on costs one call per station; Phase 2 must
  watch that tick's time (PERF/BUDGET). `noteTime` logs `[SQSG] BUDGET ...` once.
- Gather: `passengerCargo, lines, unloadGroups, groupStations, buildingMap (count, map), buildings(map,
  prev, passenger)` (buildings without needs are dropped; `pos` reused from `prev`), `towns`. No
  `getCargoSupplyAndLimit` / `pickerRows` yet (Phase 3).
- Tests: 52 (`test_model` 25, `test_cache` 14, `test_gather` 13).

### Phase 2: spike in game (rendering + probe, needs the in-game test)
Files: `content/supply_gaps/gui/sg_window.res.lua` (react-plugin, order 30), `gui/sg_window.script.tl`
(plugin + minimal window: overlay checkbox, cargo rows, summary; tick wiring), `gui/sg_window.css.lua`,
`content/supply_gaps/sg_markers.tl` (marker lifecycle: set / diff / clear-all on overlay off and on
plugin unmount), `content/supply_gaps/sg_patch.lua` (track B, installed once at script load in `pcall`,
guarded by a module flag like `__sqrlOneWayPatched`), `plans/square_supply_gaps/TESTING.md`.
Probe switches (constants in `sg_patch.lua` / `sg_markers.tl`, DEV build): `MARKER_MODE = "marker" |
"zone"`, `MARKER_TYPE = "arrow"` (also tries `"exclamation_red"`, `"question"` once each, logs `pcall`
result), `B1_CATCHMENT`, `B2_CARGOCOLOR`, `B3_HIGHLIGHT` (ActionDescriptor wrap, only for
`tool` starting `construction-menu-`, only when the overlay is on, appends gap entities, max 300).
Log lines: `INIT plugin`, `TICK n ms stations catch buildings gaps markers+/-`, `MATCH catchable=building|stocklist`,
`NEEDS town mismatch`, `LINECHK line cargo loads capacity` (first 20), `MARKER type ok err`,
`ZONE ok err`, `PATCH getActionParams=ok actionDescriptor=ok|off`, `PROBE layer action res b1 b2`
(once per resName), `PROBE highlight tool n`, `PAUSE tick_fired=yes|no`, `ERR where msg`.
Done: make targets pass; TESTING.md lists: markers visible in free play, in the bus-stop tool, in station
placement, in the road tool, in an open layer; markers clickable (open building window); B1/B2/B3 visible
or not; add/remove on an existing save; paused refresh; perf on the largest save.
**User runs the in-game test; results go to `docs/findings.md` (mission markers in free play, marker
types, highlightedEntities on town buildings, catchable entity identity).**

Phase 2 as built (2026-10-09), deviations from the text above:
- New module `content/supply_gaps/sg_overlay.tl`: session, the tick pipeline and every probe (TICK, PERF,
  MATCH, NEEDS, LINECHK, PAUSE, OVERLAY, SELECT, UNLINED, UNMOUNT), so the window script only wires
  hooks. The ridge plugin drives it: `onStepTimer(overlay.timerTick, 1.0)`, `onStep(overlay.stepCheck)`
  (once per wall second: GAME_SPEED pause probe; after 3 s paused without a timer tick it logs
  `PAUSE tick_fired=no` and ticks from onStep), `onUnmount(overlay.shutdown)`.
- The probe switches are **runtime checkboxes** in the window's DEV section (`sg_patch.DEV = true`), not
  constants: zone mode (A2), B1, B2, B3. All off by default. The `ActionDescriptor` wrap is installed
  only when B3 is first ticked. `getActionParams` is wrapped at script load (pass-through unless on + B1/B2).
- Marker type probe: on the first apply, the 2nd to 4th nearest gaps get `exclamation`, `question_red`, `locate`
  (all used by official mission code); `exclamation_red` is left out (model exists, no code uses it).
  `ZONE_PROBE`: one zone circle on the nearest gap.
- Plugin unmount **forgets** the markers without engine calls (`markers.forget`): on a game unload the
  world may be gone. A remount during play would leave stale markers (logged as `UNMOUNT`).
- `LINECHK` checks each carried non-passenger cargo of the lines, one pass (max 20) per switch-on.
- Tests: 82 (`test_markers` 10, `test_overlay` 13, `test_patch` 7 added).

### Phase 2b: "starved" gaps (in range but empty), 2026-10-09
In game (Phase 2 spike): an Industrial building showing Input Stocks "fuel 0/2" got no marker with Fuel
selected; it sits in the catchment of a stop on a fuel line, so the "reached" rule passed. The user's
model: a building that needs a cargo and isn't getting it is a gap.
- Stock read: `api.engine.system.simEntityAtStockSystem.getStockCount(stockList, stockId0)`
  (`api/tealdef/api/engine/system.d.tl:161-168`), one call per input stock of a needed cargo, inside the
  existing building read (`sg_gather.readBuilding`). It is the per-stock read of
  `cargo_util.calculateStockConfigs` (`base/content/gui/main/cargo_util.tl:65`) whose `stored` the building
  window prints as "{count}/{capacity}" (`gui/entity_window/entity_window_util.tl:699-703`; the
  town-building window passes the stockList entity, `town_building.tl:253-264`). One InputStock per
  needed cargo, so stock count = cargo count (same cargo in several stocks: summed). Rejected:
  `getStockCountForCargoType` (same result here, one more argument), `forEachCargoInStock` /
  `getNumberOfCargoInStock` (`cargo_util.tl:788-815`, an extra `getStockCargoTypes` per stock and a total
  over all cargos), `getCargoTypesForStockList` (types only, no counts).
- Rule: need c is **unreached** (no delivering stop in range, the old rule; marker `arrow`) or **starved**
  (reached, but stock of c was 0 on the last `model.STARVED_READS = 3` reads; marker `exclamation`). Kind
  unreached wins when a building has both. The streak (`SupplyGapsBuilding.zeroReads`, `model.zeroStreak`:
  0 -> +1, >0 -> reset, failed read -> unchanged) keeps buildings that just consumed their last unit
  between two deliveries from flickering: with the 10 s re-read cadence a stock must stay empty ~20 s.
  Known limit: a line with a very long interval can still leave a supplied building empty for longer;
  `api.engine.util.stock.getCargoTypeDeliveredPerYear(stockList, c)` (`cargo_util.tl:~107`, the window's
  tendency) is the fallback signal if the in-game test shows false positives.
- Window: checkbox **Include in-range but empty** (default on, `session.starved`); rows show
  `unreached · starved / needed`, "All needed" sums per building; summary "U not reached, S in range but
  empty (of N buildings with needs)"; two legend lines; cargo icons in rows (`cargo_react_util.makeIcon`
  with `CargoType.icon`, as `makeCargoIcon`, `cargo_react_util.tl:26-33`); tooltips on every checkbox
  (meta.tooltip on a CheckBox as `line_vehicle_mgmt/cargofilter_window.tl:755-758`) and every cargo row.
- Markers: `markers.apply(plan, buildings, view.kind)`; a kind change removes and re-sets the marker.
  The type probe is off (all 4 types rendered in game).
- Perf: building reads are now **round robin** (`cache.buildingStep`): new ids at once, plus
  ceil(n / BUILDING_EVERY) known ones per tick, so each building is re-read every 10 ticks and the stock
  calls are spread evenly instead of all buildings every 10th tick (the old max-ms spike). The sorted
  building order and the catchable index are rebuilt only when the set of buildings with needs changes
  (`world.order`, `world.index`), not every tick. Demolished buildings are dropped in an O(n) pass that
  runs only when the count changed or a new id appeared.
- Logs: `STARVED cargo=c(name) n= was=` on change (max 10 a tick); TICK adds `split=` (ms
  lines/catch/buildings/model/markers), `read=`, `unreached=`, `starved=`, `starvedNeeds=`, `~retyped`;
  PERF adds `read=`, `unreached=`, `starved=`; `STARVEDMODE` on the checkbox.
- Tests: 100 (model starved/zeroStreak/order, gather stock reads + streaks + flatten, cache buildingStep,
  overlay starved markers/log/hide/retype/round robin, markers kinds).

### Phase 2c: area labels ("[fuel icon] 73%" per district), 2026-10-09
Request: besides the per-building arrows, one floating label per area with the cargo icon and how much
of that need is covered, like the Cargo Flow layer's district label.

**How the vanilla district label works.** It is a HUD icon of the **TOWN** entity, not of a district
entity (there is none). The HUD manager calls the master recipe once for the town and once per district
"sub-entity", with `param.details.data = Gui.SelectionDetails.Town {townEntity, districtType, districtCenter}`
(`api/tealdef/api/gui.d.tl:213-219`); `layer_cargo_flow.HudIconMaster` renders the chips when
`districtType ~= nil` (`base/content/gui/layers/layer_cargo_flow.tl:66-95, 129-150`), the station tools'
`ConstructionMenuHudIconMaster` likewise (`gui/construction/constructionHudIconMaster.tl:144-200`). Sub-icons
exist only when the HudIconManagerConfig's `visibilityThresholds` enable them: the default has
`Town detailsThreshold = -1` "by default, we do not want to see the districts" (`gui/hud/hud_react_util.tl:146`);
the layer and `showDistricts` tools call `resetSubEntityThresholds(..., Town)` (`hud_react_util.tl:200-230`,
`layer_cargo_flow.tl:322-325`, `construction_react_util.tl:1267-1272`). District position: engine-placed
(`api.engine.util.town.getTownDistrictCenter`, `api/tealdef/api/engine/util.d.tl:703-707`).

**Options, ranked.**
1. **(a) Wrap the base HUD recipes through their module tables** (chosen). `HudIconMasterGame` (free-play
   HUD, TOWN in the default pre-filter, `gui/main/selector_react_util.tl:14-23`) calls
   `town_hud_react_util.TownHudIcon(params, true, true)` through the module table at render
   (`gui/main/hud_icon_toolbox.tl:343-346`; also `HudIconMasterBase` `:41` for the other layers), and the Cargo
   Flow layer reads `layer_cargo_flow.HudIconMaster` at render (`layer_cargo_flow.tl:338`). Module-table
   wrapping from a mod is proven (findings "Native construction tools can be patched from a mod"); HUD
   recipes share the GUI Lua state's modules (`plans/square_industry_production_label/PLAN.md:82`). Engine
   does the anchoring, culling, LOD and stacking; cost = one 1 s state read per visible town icon.
2. **(a') + district anchors in free play** (DEV probe, off): also wrap
   `hud_react_util.makeDefaultVisibilityThresholds` (read at render, `selector_react_util.tl:223, 344`) to
   `resetSubEntityThresholds(Town)`, so the free-play HUD gets district sub-icons and our TownHudIcon wrapper
   draws one label per district at the engine's anchor. Risky: global HUD change; only takes effect when a
   HUD config is next built; `HudIconMasterGame` also adds the town's notification icons to each district
   sub-icon (`hud_icon_toolbox.tl:340-365`).
3. **(c) world2Screen + own overlay** (`api.gui.camera.world2Screen`, `gui.d.tl:483-484`, GUI thread only):
   needs a full-screen layer our ridge plugin doesn't own, padded-layer pixel placement (memory "GUI pixel
   placement", 4 rounds to get right on the minimap), per-frame repositioning on the GUI thread, and lags
   the camera. Rejected.
4. **(b) A mod HUD icon on the town / district**: no such entity hook. `hudIconScript` is only taken for
   `con.subconstructions[1]` of constructions (`hud_icon_toolbox.tl:242-251`, `api/tealdef/api/type.d.tl:1693`);
   a second `HudIconManagerConfig` only lives inside the active tool's ActionDescriptor. Not possible.
5. **(d) Mission markers at the district centre** (`setMarkerAtPosition`, `gui.d.tl:719-725`): models only,
   no text. Not a label.

**Area** = town x land use (residential / commercial / industrial), the engine's district. Buildings already
carry `town` and `landUse` (`PERSON_CAPACITY.type + 1`); land use 0 (unknown) has no area.
Per area and cargo c: `needed` = buildings with an input stock of c, `covered` = reached and (while
"Include in-range but empty" is on, the default) not starved; % = `floor(covered * 100 / needed)` (floor, so one
gap left never reads 100 %). Tone: >= 90 Normal, >= 50 Inferior, else Poor (`LabelFontColor`). One cargo
selected: that cargo's chip. "All needed": the worst `WORST = 3` cargos below 100 % (lowest %, then more
buildings, then id); a fully covered area gets one 100 % chip. Labels only for the `MAX_LABELS = 30` areas
whose building centroid is nearest the camera centre.

**As built.**
- `sg_model.compute` fills `view.areas` (key `town * 4 + landUse`, per-cargo needed / covered, running-mean
  centroid) in the existing building loop; `model.areaKey`.
- `sg_areas.tl` (pure): `pct`, `tone`, `chips`, `labels` (nearest + cap, ties by key).
- `sg_overlay`: after the markers, in its own pcall, `areas.labels` -> `overlay.makeLabelStore` (rows per town,
  icon path from `CargoType.icon` read on the GUI thread, text "73%") -> `overlay.labelStore`, replaced as a
  whole. Session `labels` (default on), `labelProbe` (default off); `setLabels`, `setLabelProbe`; store cleared
  on overlay off / labels off / shutdown; snapshot `labels`, `labelProbe`, `labelsShown`.
- `sg_labels.lua` (plain Lua, installed once at window-script load, guards `__sqsgLabelPatched` on each base
  module): wraps `TownHudIcon` (base icon, then our `SupplyGapsAreaLabel` below it: one row per labelled
  district = district colour bar + stock HUD pills via `gui_react_util.makeContentLabelIndictator`,
  labelMode "HudIconMain"; nothing when `showCargo == false`, the Cargo Flow town icon), `layer_cargo_flow.HudIconMaster`
  (district sub-icons: our row under the vanilla chips) and `makeDefaultVisibilityThresholds` (probe).
  What a label shows is decided in its own `useStepStateTimer` (1 s) from `overlay.labelStore`, never at the
  wrapper's render (base parents re-render rarely). HUD side reads only plain Lua data; no engine / res /
  GUI-thread-only call (memory "HUD recipes not on GUI thread"); the tick runs in `react.enqueueJoin`.
  Every wrapper falls back to the base recipe alone on error.
- Window: checkbox **Area labels** (tooltip), DEV checkbox **District anchors for area labels (probe)**;
  summary adds "N district labels."; CSS `R::SupplyGapsAreaLabel` (spacing, district bar colours from
  `district_colors.gres`).
- Logs: `LABEL install town= cargoflow= thresholds=`, `LABEL tick n= areas= shown= cap= ms= selection= probe=`
  (TICK cadence), `LABEL hud mode=town|district|cargoflow town= landUse= rows=` (first 3 per mode),
  `LABEL thresholds districts=on n=` (first 5), `LABEL on|off`, `LABEL probe on|off`, `LABEL ERR where msg`.
- Known limits: town icons built before the script loaded keep the base recipe until the HUD rebuilds them
  (pan away and back); rows also show under town names in other layers that use `HudIconMasterBase`.
- Tests: 136 (`test_areas` 19, `test_labels` 12, `test_overlay` +5).

### Phase 2d: only towns in view, 2026-10-09
Request: counts in the window were map-wide and the arrows the 300 nearest the camera; scope everything
to the towns on screen.

**In-view rule** (`sg_scope.tl`, pure).
- View footprint: the four screen corners' rays (`api.gui.camera.screen2World` at depth 0 and 1,
  `api/tealdef/api/gui.d.tl:483-487`; `getSize`, `getEye`) meet the horizontal plane at the terrain height
  under the camera centre (`api.engine.terrain.getHeightAt`, `api/tealdef/api/engine.d.tl:1734`), each corner
  capped at `CAP_FACTOR = 4` x camera distance (at or above the horizon). Same projection as the shipped
  `square_better_minimap` camera box (`minimap_hud.script.tl` `cameraFootprint`, `minimap_geom.tl`
  `groundPoint`, ported). Fallback on any error: a square of +- distance around `getCameraData()` centre.
- Rejected: `world2Screen` of town points (no base or verified mod use; points behind the camera have no
  defined result; a town box larger than the screen has every corner off screen) and a radius from
  `getCameraData()` alone (ignores tilt and aspect).
- Town extent: the TOWN record has no position or size (`engine.d.tl:1285-1302`), so a town's box is the
  union of its buildings' 2D `BOUNDING_VOLUME` boxes (`gather.buildingBox`, read once per building id for
  every building of the map, cheap; rebuilt only when an id appears or one is demolished). A town whose
  centre is off screen but whose buildings are visible counts; zoomed into the middle of a big town counts.
- Enter: town box overlaps the footprint (separating-axis test, convex polygon vs box). Leave: only when
  it has not overlapped for `HOLD_TICKS = 3` ticks AND is farther than `max(0.25 x distance, 100 m)`
  (hysteresis, no flicker at the edge while panning / zooming).
- Recomputed every tick on the GUI thread (the tick is already `react.enqueueJoin`ed).

**Scoped work** (`sg_overlay.tl`).
- Checkbox **Only towns in view** (default on, `session.scoped`, `overlay.setScoped`); off = every town with
  buildings is "in scope" (same code path).
- Building reads only for towns in scope (`cache.buildingStep(c, ids, known, due, maxUrgent)`): never-read
  ids and `due` ids first, at most `overlay.PRIORITY_PER_TICK = 800` a tick, plus the round robin over the
  scoped ids. A town that comes into scope has its known buildings marked `due` (re-read at once).
  Buildings of out-of-scope towns keep their last record (shown at once when the town comes back, then
  refreshed). Catchment cache and lines stay global (unchanged).
- No partial flash: a town is **counted** only once every building of it has been read (`overlay.ready`,
  sticky for the session, so a new building in a counted town doesn't hide it). Until then the header says
  "(reading N buildings)".
- Counted towns -> `model.scopeOrder(buildings, towns)` is the order passed to `model.compute`, so picker
  counts, the summary, gaps / markers and area labels all cover only those towns. The catchable index stays
  map-wide. Order rebuilt only when the building set or the counted towns change.
- Window: header line "In view: Rockledge, Columbus, Avon +2" (nearest first, `NAMES_SHOWN = 3`), "In view:
  no towns..." or "Whole map: N towns"; the selected cargo keeps its row (0 / 0) when no town in view needs it.
- Logs: `VIEW towns= scope=view|map +added -removed names=` on change (max 10 names), `VIEWCAM cx= cy= dist=
  hits=n/4 fallback= poly=` (first tick after each switch-on), `SCOPE view|map`; TICK and PERF add
  `scope=view:n|map:n pending=`.
- Tests: 156 (`test_scope` 12 new; `test_model` +2 scopeOrder / scoped compute; `test_cache` +1 due/maxUrgent;
  `test_gather` +1 box / name; `test_overlay` +5 scoped). The Phase 1-2c overlay tests run with scoping off.
- Known limits: towns past 4x the camera distance at a horizon tilt are out of view even if their
  silhouette is visible; footprint unverified at extreme pitch until VIEWCAM lines come back.

### Release cleanup, 2026-10-09
User direction: "clean up the UI in the tool to get ready for release. Most options should be on by
default, and we should not have too many options. Keep it simple with the mod enabled and showing most
information." This replaces Phase 3; town rows with a camera jump and track B were dropped.

**Removed** (spike / DEV material):
- `sg_patch.lua` and `test_patch.lua` (track B: `getActionParams` / `ActionDescriptor` wraps, B1 catchment
  circles, B2 cargo painter, B3 highlight) and the window's DEV section with its checkboxes.
- Zone mode (A2) and the marker TYPE / ZONE probes in `sg_markers.tl` (marker-only now; `apply(next, kinds)`).
- The district-anchor probe (`makeDefaultVisibilityThresholds` wrap, `labelProbe`, district mode) in
  `sg_labels.lua`. A district sub-icon reaching the `TownHudIcon` wrapper (base never sends one) now gets
  the base recipe alone.
- Catchable index by `TownBuilding.stockList` (in game `MATCH` was building=1033 stocklist=0): `model.index`,
  `world.index`, `view.match` are gone; a catchable reaches a building only as the building entity.
- One-off probes and logs: MATCH, LINECHK, NEEDS (`needsMismatch`, `gather.towns`), PAUSE (the onStep
  fallback stays, silent), VIEWCAM, VIEW, SCOPE, SELECT, UNLINED, STARVED(MODE), OVERLAY, UNMOUNT, TICK,
  LABEL install/hud/tick, MARKER, ZONE, BUDGET; the unused `gather.buildings` batch read; the window's
  "last tick ms, ticks n" line.
- Log now: one `[SQSG] INIT mapEditor= on= labels town=ok cargoflow=ok` line, rate-limited `ERR` lines
  (20 per module), and a `PERF` line every 30 ticks only with `local DEBUG = true` in `sg_overlay.tl`.

**On by default** (superseded by "Per-save state" below: off by default, on when the save says so). `overlay.DEFAULT_ON = true`: the overlay ticks from game load without opening the
window. Safe for saves: GUI-only and read-only (mission markers, HUD rows; no game script, no commands,
nothing saved). `shutdown` (plugin unmount = game unload) forgets the markers without engine calls and
restores every session default, so each game starts on. Cost when nobody looks: the scoped tick (towns in
view only; first tick = one catchment call per delivering station plus one box read per building). The
map editor stays off: the onStep paused fallback is now gated by `isMapEditor` like the timer.

**Options (final), all with short tooltips:** Show supply gaps (On) at the top; under an "Options"
heading: Only towns in view (On), Include in-range but empty (On), Area labels (On), Count stops without a
line (Off). Not folded further: "Only towns in view" is also the perf guard on big maps; "Include in-range
but empty" is the one way to see only coverage gaps (the false-positive escape hatch if starved buildings
misfire); "Area labels" adds HUD rows players may not want; "Count stops without a line" is the only way to
preview a stop before it is on a line and must stay off by default (it marks every unloading stop as
delivering everything).

**Window:** title "Supply Gaps"; checkbox; while on: in-view header ("In view: A, B, C +2" / "Whole map:
N towns" / "(reading N buildings)"), cargo list (icon, name, `unreached · empty / needed`, or `unreached /
needed` with empty buildings excluded; tooltips explain the count), summary, legend (arrow; exclamation only
while empty buildings are marked); while off: one hint line. Then the options. Content is far above the
~92 px window minimum in both states (memory "Window frame min height"). Strings in `_()`.

Tests: 136 (`test_patch` deleted; markers, labels and overlay tests rewritten for the removed probes; new:
default-on, no log lines in a normal tick, paused fallback without logs, forget).

### Per-save state, 2026-10-09
User direction: the overlay is **off by default**, and on at load only if the game was saved with it on.

**Mechanism** (copied from `square_problem_radar`, `plans/square_problem_radar/PLAN.md`):
- `content/supply_gaps/sg.gs.lua`: `data()` with `updateScript` / `handleEventScript` →
  `sg_state.script.tl` (as `radar/radar.gs.lua`). Game-script name `square_supply_gaps::/supply_gaps/sg.gs`.
- `sg_state.script.tl` (engine): `update` only re-subscribes to `SupplyGaps.setOn` once per load
  (`subscribeToNoEvents` + `subscribeToEvent`; findings "Game-script event subscriptions are saved");
  `handleEvent` validates `{ on = boolean }` with `sg_saved.apply` and calls `state:set` **only when the flag
  changes**. Never writes in `update`, no lifecycle init. Map editor: inert. Both entry points in pcall.
- `sg_saved.tl`: pure rules (`isOn`, `apply`, load decision `newLoad` / `loadStep`) + GUI adapter
  (`readOn`: `gameScriptSystem.getEntityForGameScript` → `GAME_SCRIPT` component → `state_native:find("on")`,
  falling back to the `state` copy, as `radar_hud.script.tl` readFields; `sendOn`:
  `api.cmd.makeScriptingSendEventCmd("", "SupplyGaps", "SupplyGaps.setOn", { on })`, as radar sendEvent).
- GUI (`gui/sg_window.script.tl`): `overlay.DEFAULT_ON = false`. The ridge plugin's `react.onStep` joins
  `loadCheck` onto the main thread (memory "react.onStep runs on worker threads") until decided, at most once
  per wall second: saved on → `overlay.setOn(true)`; saved off / no state → stay off; state not readable →
  retry, give up as off after `LOAD_TRIES = 10` reads. onStep (not onStepTimer) so a game loaded paused
  decides at once. Off → on only, so nothing flashes. One log line `[SQSG] LOAD saved=on|off tries=N`. The
  window checkbox calls `setShown`: marks the load decided (the player wins over a pending read), switches
  the overlay and sends `setOn`. Unmount resets the decision for the next game.

**State:** `{ v = 1, on = boolean }`. Absent = off, so adding the mod to an old save writes nothing until
the player ticks the box (only the event subscription is stored, as for every game script). Not saved: the
cargo selection (cargo ids depend on the loaded mod set) and the options (rarely changed, and each would add
an event key and validation for little gain); they stay session-only with their defaults.

**Severity:** `severityAdd: None` (nothing happens until the player toggles), `severityRemove: Warning`
(the save then holds our game-script entity state; same choice as `square_problem_radar`, whose state also
lives in the save), `cosmetic: true` (the flag only drives GUI markers; achievements stay allowed).

**Perf:** `update` is one boolean test per sim update after the first; the load read is one component read
per second for at most 10 s; a write happens only on a checkbox change.

Tests: `test_saved.lua` (13: isOn, apply validation / no-change, load decision incl. retry limit and player
wins, readOn / sendOn on a fake API, engine subscribe-once, write-only-on-change, ignored events, map
editor, pcall); `test_overlay.lua` now asserts off by default.

### Phase 3: full UI + chosen rendering
(Superseded by "Release cleanup" above.)
Keep what Phase 2 proved; delete failed probe paths (smallest code). Full window (picker counts, town
rows with camera jump, "Count stops without a line", cap notice), button state, legend line explaining
the marker, perf constants tuned from Phase 2 PERF lines. If B3 works: highlight follows the selected
cargo inside stop/station tools; else B1/B2 only or none.
Files: `gui/sg_window.script.tl`, `sg_window.css.lua`, `sg_model.tl` (+ `pickerRows`, `summary`),
`sg_markers.tl`, `sg_patch.lua`; tests `test_model.lua` (+ picker/summary), `test_window.lua` (session
state helpers).
Done: make targets pass; TESTING.md updated to the final feature list.

### Phase 4: review
`tf3-mod-validator` agent + code review of the diff + perf review (as `plans/*/PERF_REVIEW.md`). Fix findings.
Done: all make targets pass, no open review items.
Perf review done 2026-10-09: `PERF_REVIEW.md` (line cache, dirty-flag model skip, budgeted box pass and
building reads, wall clock, DEBUG split timings; TESTING.md step 9 is the in-game confirmation).

### Phase 5: in-game test, cover, publish (user + main session)
TESTING.md round, findings.md entry, `branding/mods.js` entry (accent distinct, pictogram: house with
a broken supply arc), `make covers`, gallery shots (`make shots`), description, upload.

## Open risks (in-game)
- `api.gui.mission` markers may not exist / render outside missions (free play) or may be hidden in some
  tools or at far zoom. Fallback zones (A2); last resort: markers only in the window list + camera jump.
- Unknown marker `type` strings besides `"arrow"`; a bad type may throw (pcall) or draw nothing.
- Catchable identity: `getStationCatchables` may return the building entity or `TownBuilding.stockList`
  (`cargo_util.tl:565-571` suggests separate entities, `hud_icon_toolbox.tl:189-198` the same one). The
  index maps both; `MATCH` log decides.
- "Delivers" rule: a line that loads c at stop A unloads at every stop whose catchment needs c; confirm
  with a fish line that has a stop in town (gap disappears) and a passenger-only line there (gap stays).
  `stopConfig.load` may include cargos the vehicles can't carry (compare `LINECHK` capacity).
- `onStepTimer` while paused (players build while paused).
- B3 wrapping `builtin.ActionDescriptor` (a userdata-declared builtin, `react.DeclareBuiltinWithUserdata`)
  may break identity checks in react and crash; DEV flag, off by default; `highlightedEntities` may not
  affect town buildings at all.
- Cost on big maps: catchment calls are bounded per tick, but `getStation2edgesMap`-sized maps are never
  used; watch `PERF` lines on the largest save. 300 markers: frame cost of the marker renderer unknown.
- Rebuilt town buildings get new ids: a stale gap/missing marker for up to one round-robin cycle.
- Removing the mod while markers are on: markers are GUI-only and gone after reload; quitting to menu
  first is required anyway (findings: no mod removal in game).
