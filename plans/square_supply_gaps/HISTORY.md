# Supply Gap Overview: history

Finished phases, superseded designs and resolved risks, moved verbatim out of `PLAN.md`
(newest first). Read only to learn why something is the way it is. Current design: `PLAN.md`.

## 2026-10-09: Open risks resolved in game (moved from PLAN.md on 2026-10-12)
From "Open risks (in-game)". Markers render in free play, marker types are in `docs/findings.md`
("Mission marker types"), catchables are the building entity (MATCH building=1033 stocklist=0), track B was dropped.

- `api.gui.mission` markers may not exist / render outside missions (free play) or may be hidden in some
  tools or at far zoom. Fallback zones (A2); last resort: markers only in the window list + camera jump.
- Unknown marker `type` strings besides `"arrow"`; a bad type may throw (pcall) or draw nothing.
- Catchable identity: `getStationCatchables` may return the building entity or `TownBuilding.stockList`
  (`cargo_util.tl:565-571` suggests separate entities, `hud_icon_toolbox.tl:189-198` the same one). The
  index maps both; `MATCH` log decides.
- B3 wrapping `builtin.ActionDescriptor` (a userdata-declared builtin, `react.DeclareBuiltinWithUserdata`)
  may break identity checks in react and crash; DEV flag, off by default; `highlightedEntities` may not
  affect town buildings at all.

## 2026-10-09: Phases 3, 4, 5 as planned (moved from PLAN.md on 2026-10-12)
Phase 3 was superseded by "Release cleanup"; the Phase 4 review and Phase 5 release are done (rev 1 published 2026-10-09).

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

## 2026-10-09: Release cleanup, removed material and the default-on step (moved from PLAN.md on 2026-10-12)
From PLAN "Release cleanup".

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

**On by default** (superseded by "Per-save state" below: off by default, on when the save says so). `overlay.DEFAULT_ON = true`: the overlay ticks from game load without opening the
window. Safe for saves: GUI-only and read-only (mission markers, HUD rows; no game script, no commands,
nothing saved). `shutdown` (plugin unmount = game unload) forgets the markers without engine calls and
restores every session default, so each game starts on. Cost when nobody looks: the scoped tick (towns in
view only; first tick = one catchment call per delivering station plus one box read per building). The
map editor stays off: the onStep paused fallback is now gated by `isMapEditor` like the timer.

Tests: 136 (`test_patch` deleted; markers, labels and overlay tests rewritten for the removed probes; new:
default-on, no log lines in a normal tick, paused fallback without logs, forget).

## 2026-10-09: Phase 2d logs and tests (moved from PLAN.md on 2026-10-12)
The VIEW / VIEWCAM / SCOPE logs were removed in "Release cleanup".

- Logs: `VIEW towns= scope=view|map +added -removed names=` on change (max 10 names), `VIEWCAM cx= cy= dist=
  hits=n/4 fallback= poly=` (first tick after each switch-on), `SCOPE view|map`; TICK and PERF add
  `scope=view:n|map:n pending=`.
- Tests: 156 (`test_scope` 12 new; `test_model` +2 scopeOrder / scoped compute; `test_cache` +1 due/maxUrgent;
  `test_gather` +1 box / name; `test_overlay` +5 scoped). The Phase 1-2c overlay tests run with scoping off.

## 2026-10-09: Phase 2c research: options for area labels, logs, tests (moved from PLAN.md on 2026-10-12)
From PLAN "Phase 2c". Option (a) shipped; the probe of (a') was removed in "Release cleanup", as were the LABEL logs.

**Options, ranked.**
1. **(a) Wrap the base HUD recipes through their module tables** (chosen). `HudIconMasterGame` (free-play
   HUD, TOWN in the default pre-filter, `gui/main/selector_react_util.tl:14-23`) calls
   `town_hud_react_util.TownHudIcon(params, true, true)` through the module table at render
   (`gui/main/hud_icon_toolbox.tl:343-346`; also `HudIconMasterBase` `:41` for the other layers), and the Cargo
   Flow layer reads `layer_cargo_flow.HudIconMaster` at render (`layer_cargo_flow.tl:338`). Module-table
   wrapping from a mod is proven (findings "Native construction tools can be patched from a mod"); HUD
   recipes share the GUI Lua state's modules (`plans/square_industry_production_label/PLAN.md:93`). Engine
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

- Logs: `LABEL install town= cargoflow= thresholds=`, `LABEL tick n= areas= shown= cap= ms= selection= probe=`
  (TICK cadence), `LABEL hud mode=town|district|cargoflow town= landUse= rows=` (first 3 per mode),
  `LABEL thresholds districts=on n=` (first 5), `LABEL on|off`, `LABEL probe on|off`, `LABEL ERR where msg`.
- Tests: 136 (`test_areas` 19, `test_labels` 12, `test_overlay` +5).

## 2026-10-09: Phase 2b logs and tests (moved from PLAN.md on 2026-10-12)
The STARVED logs were removed in "Release cleanup".

- Logs: `STARVED cargo=c(name) n= was=` on change (max 10 a tick); TICK adds `split=` (ms
  lines/catch/buildings/model/markers), `read=`, `unreached=`, `starved=`, `starvedNeeds=`, `~retyped`;
  PERF adds `read=`, `unreached=`, `starved=`; `STARVEDMODE` on the checkbox.
- Tests: 100 (model starved/zeroStreak/order, gather stock reads + streaks + flatten, cache buildingStep,
  overlay starved markers/log/hide/retype/round robin, markers kinds).

## 2026-10-09: Phase 2, spike in game (moved from PLAN.md on 2026-10-12)

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

## 2026-10-09: Phase 1, scaffold + model + gather (moved from PLAN.md on 2026-10-12)

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

## 2026-10-09: Decisions rows for dropped rendering tracks (moved from PLAN.md on 2026-10-12)
Rows of the PLAN "Decisions" table; track A2 (zone circles) and track B (native tool patches) were removed in
"Release cleanup". Table header kept for context.

| topic | decision | why |
|---|---|---|
| Track A2 (fallback) | `api.gui.mission.setZoneCircle(key, center, radius, draw=true, color, prohibitBuilding=false, playAnimation=false)` (`gui.d.tl:704-713`) at the building position | if markers don't render in free play or look wrong; same keyed lifecycle |
| Rendering, track B (probe) | while the overlay is on, patch the **native construction tools**: wrap `construction_react_util.getActionParams` (proven: `docs/findings.md` "Native construction tools can be patched from a mod"; `mods/square_smart_lanes/content/smart_lanes/sl_tool.script.lua:147-180`) and add to `res.layerConfig` (B1) cargo catchment circles `catchmentAreaRenderableConfig` (`type.d.tl:4911`, record `:4704-4730`, base use `entity_window/maintenance_station/maintenance_station.tl:130-135`) and (B2) the Cargo Flow `CargoColor` painter (`includePassengers=false`, 5 levels, as `layer_cargo_flow.tl:185-194`). (B3) per-entity highlight via `ActionDescriptorParam.highlightedEntities` (`base/tealdef/scripts/builtin.d.tl:1337-1346`; base use `line_vehicle_mgmt/line_util.tl:1182` for vehicles) needs a wrap of `builtin.ActionDescriptor` (`gui/main/builtin.lua:176`), because construction.tl builds the descriptor itself (`gui/construction/construction.tl:4438-4485`): DEV flag, off unless the probe enables it | no LayerConfig painter can colour single town buildings: `townBuildingPainter` takes BaseColor / CargoColor / DestinationColor / EmissionImpactColor / LandUseColor only (`type.d.tl:4606-4607`); per-entity highlight exists only on the ActionDescriptor |
| Track B scope | definitions with `action == "ACTION_STREET_TERMINAL_BUILDER"` (street stops, `construction_react_util.tl:971-993`), `"ACTION_MODULE_BUILDER"`, or `hudIcons.showDistricts == true` (every station: `construction_desc_react_util.tl:1040-1055`) | the tools the user edits stops with; stations already get the district `CargoColor` painter there (`construction_react_util.tl:595-631`) |
| Player-picked layer | wins, as in base (`mergeLayerConfig`, `construction_react_util.tl:3985-3990`); we never fire `preferredLayerConfig` | firing it would fight the layer ridge, which resets it to nil (`gui/layers/layers_button_ridge.tl:99, 135, 277, 510`) |

## 2026-10-09: Plan header (moved from PLAN.md on 2026-10-12)

Plan written 2026-10-09. Mod: `mods/square_supply_gaps/`. Tests: `tests/square_supply_gaps/`.
In-game checklist: `TESTING.md` (written in Phase 2). Log prefix `[SQSG]` in `<userdata>/crash_dump/stdout.txt`.
