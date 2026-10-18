# Supply Gap Overview (`square_supply_gaps`): plan

Status: rev 4, released on mod.io (id 6438590), last change 2026-10-10. Open: the in-game release checklist
(`TESTING.md`, nothing ticked off) and the DEBUG perf run (`TESTING.md` step 9). Next step: run `TESTING.md`.

Mod: `mods/square_supply_gaps/`. Tests: `tests/square_supply_gaps/`. In-game checklist: `TESTING.md`. Log prefix
`[SQSG]` in `<userdata>/crash_dump/stdout.txt`. Finished phases, research and resolved risks: `HISTORY.md`.
Perf review (2026-10-09): `PERF_REVIEW.md`.

## Current state
Shipped (see `_metadata/description.html` Changelog): rev 1 (2026-10-09) the overlay as designed below and in
"Phases"; rev 2 the optional `sqperf_log` mod param (`[SQPERF]` lines); rev 3 translations into the 12 other
game languages; rev 4 (2026-10-10) starved buildings get a red `question_red` marker instead of the yellow
`exclamation` (the engine has no `exclamation_red` type, `docs/findings.md`), the options sit above the cargo
list, option clicks update at once, stylesheet rules 26 to 18.

Open work: `TESTING.md` (release checklist never ticked off here; step 9 DEBUG perf run). Known limits are
listed under "Open risks" and in the phase notes below.

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

Phase 1 (scaffold, model, gather, offline) and Phase 2 (in-game spike with rendering probes), 2026-10-09:
done; detail in `HISTORY.md`.

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

**Options, ranked** (wrap the base HUD recipes, chosen; rejected: world2Screen overlay, a mod HUD icon,
markers at the district centre): in `HISTORY.md`.

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
- Known limits: town icons built before the script loaded keep the base recipe until the HUD rebuilds them
  (pan away and back); rows also show under town names in other layers that use `HudIconMasterBase`.

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
- Known limits: towns past 4x the camera distance at a horizon tilt are out of view even if their
  silhouette is visible; footprint unverified at extreme pitch until VIEWCAM lines come back.

### Release cleanup, 2026-10-09
User direction: "clean up the UI in the tool to get ready for release. Most options should be on by
default, and we should not have too many options. Keep it simple with the mod enabled and showing most
information." This replaces Phase 3; town rows with a camera jump and track B were dropped.

**Removed** (spike / DEV material: track B, zone mode, probes, the stockList catchable index, one-off logs):
the list is in `HISTORY.md`.
- Log now: one `[SQSG] INIT mapEditor= on= labels town=ok cargoflow=ok` line, rate-limited `ERR` lines
  (20 per module), and a `PERF` line every 30 ticks only with `local DEBUG = true` in `sg_overlay.tl`.

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

Phase 3 (superseded by "Release cleanup"), Phase 4 (review; perf review in `PERF_REVIEW.md`) and Phase 5
(in-game test, cover, publish), 2026-10-09: done; the plan text is in `HISTORY.md`.

## Open risks (in-game)
- "Delivers" rule: a line that loads c at stop A unloads at every stop whose catchment needs c; confirm
  with a fish line that has a stop in town (gap disappears) and a passenger-only line there (gap stays).
  `stopConfig.load` may include cargos the vehicles can't carry (compare `LINECHK` capacity).
- `onStepTimer` while paused (players build while paused).
- Cost on big maps: catchment calls are bounded per tick, but `getStation2edgesMap`-sized maps are never
  used; watch `PERF` lines on the largest save. 300 markers: frame cost of the marker renderer unknown.
- Rebuilt town buildings get new ids: a stale gap/missing marker for up to one round-robin cycle.
- Removing the mod while markers are on: markers are GUI-only and gone after reload; quitting to menu
  first is required anyway (findings: no mod removal in game).
