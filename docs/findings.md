# In-game findings

Facts verified by running mods in the installed game, where the wiki is wrong, silent or misleading.
Hand-written (unlike `docs/wiki/` and `docs/game/`). These override the wiki. Add an entry whenever a
game test contradicts or fills a gap in the docs, with the date and the evidence (log line, error).

## Mod params, script functions and stylesheets

Found 2026-10-08 while trying to give `square_bigger_line_dots` a "Dot size" setting (game build 40420).
**Result: a mod.json param cannot change a stylesheet (`.css.lua`).** For size or style options, ship
separate variant mods instead.

### Script function signatures

- The script functions get a `captureParams` argument **first**. The wiki
  (`docs/wiki/modding/general/modscripts.md`) leaves it out:
  - `runFn(captureParams, settings, allModParams)`: base `base/base_mod.lua:8`
  - `preRunFn(captureParams, configDict, allModParams, baseConfig)`: base `base/mod.script.tl:16`
  - `postRunFn(captureParams, configDict, allModParams)`: base `base/mod.script.tl:257`
- With the wiki's two-argument `runFn(configDict, allModParams)`, the second argument is really the
  config dict (keys `climate`, `economy`, `nameList`), so `allModParams[modId]` is nil and every option
  silently falls back to its default.
- `allModParams[modId].<key>` is the **1-based index** of the chosen value, even when the param has
  `numbers` (the game log showed `dotSize = 4` for the 4th of `[12.0, 16.0, 20.0, 24.0]`).
- `runFn` runs in about 50 Lua states per game load (every worker thread: "Load Game Pool", "Sim Pool",
  "Main Thread", …). Globals it sets stay in each of those states.
- `postRunFn` runs once ("Load Game Pool 1"), about 2 s before the GUI resources and stylesheets are built.

### Stylesheets (`*.css.lua`)

- Stylesheets are rebuilt on **every game load**, on the Main Thread, after `runFn` and `postRunFn`.
  So timing is not the problem; access is.
- The stylesheet's `api` has **only `gui` and `type`**. `api.engine` and `api.res` are nil, so
  `api.engine.config.getModParams()` fails there.
- Its sandbox is minimal: `rawget` is nil. `pcall`, `type`, `tostring`, `ipairs`, `pairs`, `table.concat`,
  `require` and `log.message` work.
- Any Lua error in `data()` makes the game drop **the whole stylesheet** ("Failed to load style sheet",
  `StyleSheetRep.cpp`, in `crash_dump/error.json`) and the base styles come back. Keep risky reads in `pcall`.
- Globals set by `runFn` are not visible (`nil`): the stylesheet is built in a separate Lua state.
- `addModifier("loadStyleSheet", fn)` registers without error (the category exists in base
  `base/mod.lua:128`), but the modifier is **never called**, not even for base stylesheets.

### GUI resources (`*.gres.lua`, `gui_res_overwrite`)

- A stylesheet can read a mod's own `gui_res` resource:
  `api.gui.genericRep.get(api.gui.genericRep.find("<modId>::/path/file.gres")).data` works (the name
  has no `.lua`).
- The mod's `.gres.lua` `data()` and a `gui_res_overwrite` script (`docs/wiki/modding/misc/soundeffects.md`)
  run on the Main Thread just before the stylesheets, in the same GUI-only state: no `api.engine`, no
  `runFn` globals. So they can't read mod params either.
- In `postRunFn`, `api.res.genericRep.add(name, res, true)` works (it returns an id), but `api.res.genericRep`
  is a **separate repository** from `api.gui.genericRep`. The stylesheet can't see it, and `api.res.genericRep.find`
  doesn't find `gui_res` resources.

### Channels tried, all failed

| Channel | Why it fails |
|---|---|
| `getModParams()` inside the `.css.lua` | `api.engine` is nil there |
| `loadStyleSheet` modifier in `runFn` | never called |
| global from `runFn`, read in the `.css.lua` | separate Lua state, `nil` |
| global from `runFn`, read in a `.gres.lua`, then the `.css.lua` reads the gres | `.gres.lua` is in the GUI state too, `nil` |
| `gui_res_overwrite` script calls `getModParams()`, then `setData` | no `api.engine` |
| `postRunFn` writes or adds a generic resource | `api.res` repository, not visible to `api.gui` |

Not tried: writing a file from `runFn` and reading it in the stylesheet (needs `io` in both sandboxes),
and patching base GUI modules from a GUI script (the dots are built by a local function in
`gui/line_vehicle_mgmt/manager_hud_util.tl`).

### Debugging tips

- `log.message` from any of these contexts lands in `<userdata>/crash_dump/stdout.txt`. Prefix messages
  with the modId and `grep` for them. The thread column shows which Lua state ran the code.
- The engine logs each load's mod params ("mod params: … dotSize = 4") after "Loading config from file".
- `crash_dump/error.json` holds the most recent caught Lua error with file, line and stack trace.
- **Removing a staging mod while a save is loaded crashes the game** (2026-10-09): deleting
  `square_quota_run` (its staging symlink went with it) while in game, even though the save didn't use
  it, crashed on the next staging rescan (`LocalModHubBackend::UpdateLocalInstallations`, "Mod got
  locally deleted in restricted mod management mode", then Assertion `inAddMods && "cannot remove mods
  in game"`). Edits to files in existing mods are fine. Quit to the main menu (or close the game) before
  `make unlink`, deleting a mod folder, or switching to a git branch that lacks a mod.
- **Adding a staging mod while the game runs is fine** (2026-10-09): `make link` added
  `square_opt_zhenya_auto_assign_terminals` with the game open; stdout showed "new ModHubMod was installed and
  will be added to filesystem …" and no assertion. Whether a save was loaded at the time isn't known.

### Game-script event subscriptions are saved (2026-10-08)

- `GameScriptState` subscriptions (`subscribeToEvent`) persist in the savegame. A script that subscribes
  only `if not state:hasEventSubscriptions()` never picks up an event added in a later mod revision when
  an existing save is loaded: the new GUI events are silently dropped (no error, the handler never runs).
  Evidence: square_problem_radar rev 3 added `ProblemRadar.snooze`; on a rev 2 save the click did
  nothing and stdout.txt had no handler log line. Fix: re-run the full subscribe (`subscribeToNoEvents`
  + every `subscribeToEvent`) once per load, tracked by a module-local flag.

## Street names and Road Stops (2026-10-08)

Source: `square_town_street_names_probe` run, new game with its "DEV TSN Probe" name set (streets
"Probe Street 01..80" in fixed order), 7 Road Stops built in one town. Log: `[SQTSN_PROBE]` lines in
stdout.txt. Plan: `plans/square_town_street_names/`.

- The name set's `streetNamesScript` is only ever called with `num = -1` (262 calls in one session,
  bursts during load), so the engine takes the whole list and picks from it itself.
- Each new Road Stop got the **next unused name in list order** (01, 02, … 07), regardless of which
  street edge it was on. Seven stops on different edges: no East/#2 suffixes, no shared names. So the
  "street name" is not tied to the actual street. With the base script the list is shuffled, which
  hides this.
- The name is on the **station group** (and the station's NAME shows the same value). The carrying
  edge has no NAME.
- `onPostBuildProposal` lists the stop in `proposal.proposal.edgeObjectsToAdd` with category 0 and,
  after the build, the **real station entity id** as the result (not a placeholder). `onPreBuildProposal`
  shows result -1. `playerInitiated` is true for player builds.
- `stationSystem.getTown(station)` returns the right town immediately after the build, matching
  `util.town.getClosestTown`.
- A flag set in the build event was mostly **not visible** in the next `update` poll ("lastBuild=none"),
  so treat build events and `update` as separate Lua states; pass data via `state` or detect in update.
- `api.cmd.sendCommand(cmd, callback)` from a game script's engine `update` fails with "Callbacks are
  currently disallowed". Send without a callback (as Auto Line Namer does) and check the result on a
  later update.
- Rename test (2026-10-08, same probe, mode "station group"): `makeEntitySetNameCmd(stationGroup, name)`
  sent from the engine `update` works. The station group **and** its station both show the new name
  within one update. Duplicate names are accepted as-is: two groups both became "Pike Street", no suffix.
- A new stop gets the **first unused** pool name: after "Probe Street 10" was renamed to "Pike Street",
  the next stop got "Probe Street 10" again.
- Name set scripts and the climate (Probe 3, 2026-10-08, `square_town_street_names_probe`, new games on several
  climates):
  - In the town/person name scripts **`api.engine` is nil**, so `api.engine.config.getConfigDict()` and
    `getModParams()` fail there.
  - A global set by the mod's `runFn` **is** visible in the name scripts: both run in the same Lua state
    ("Load Game Pool 1"). Log: `runFnGlobal climate=::/climates/tropical/tropical.clima`. So the climate reaches a
    name script via `runFn(captureParams, configDict, …)` → `configDict.climate` → global.
  - But a plain global assignment from `runFn` goes through base `base/content/base/init.lua:235-260`
    (`_G.__newindex`), which logs ERROR "Global variable in mod" (`key = …`) in **every** Lua state (67 errors per
    load). The value is still set (it `rawset`s first). Use `rawset(_G, KEY, value)` (in `pcall`) to bypass the
    guard, or a table in a module both scripts `require` (same Lua state, same require cache). Reading with
    `rawget(_G, KEY)` or `_G[KEY]` doesn't trigger anything. (`square_names_us_*`: `mod.script.lua`,
    `names.script.lua`.)
  - Town sizes don't follow the name order: the 1st name (Seattle) got `initialCap` 94, the 9th (Vancouver) 335.
    Putting big-city names first does not make them the big towns on the map.

## Junction lane connections (2026-10-08)

Found with the probe `square_roundabouts_lanes_probe` (log lines `[SQRB-LANES]`, game stdout.txt), on
`square_roundabouts` builds and the vanilla Crossing Tool. Details: `plans/square_roundabouts/PHASE6.md`.

- Lane routing at a junction is `BASE_NODE_CONFIG.laneConnections` (`api/tealdef/api/engine.d.tl:184`).
  The engine fills it when streets are built: `onPostBuildProposal` carries `nodeConfigsToAdd` for every
  new node (8 for a 4-arm roundabout; arm end nodes get 0 connections).
- **Lane indices count the sidewalks**: index 0 and the last index are sidewalks, so a 2-lane one-way
  road uses lanes 1-2 and a 4-lane two-way road 1-4. Indices run left to right looking from the node
  along the segment, so an incoming segment's lane 1 is on the driver's right and an outgoing
  segment's lane 1 on the driver's left. On a counterclockwise (right-hand) ring: incoming lane 1 =
  outermost, outgoing lane 1 = innermost; going straight is `i -> n + 1 - i`.
- Engine defaults on a one-way ring at an arm node: only the outermost ring lane may exit (into every
  exit lane of the arm); the other ring lanes only continue in their own lane; arm entry lanes fan out
  (right entry lane -> outer ring lanes, left -> inner). Same for 2 and 4-lane rings.
- The Crossing Tool applies each click as one build: `nodeConfigsToRemove = {node}` +
  `nodeConfigsToAdd = {full new config}` (no added/removed streets, cost 0).
  `userModifiedLaneConnections` stays nil after a Crossing Tool edit, so it is not the "edited" marker.
- **LaneConnection objects read from a node are read-only** (2026-10-08, `square_smart_lanes` rev 1,
  GUI thread): `lc.segment0, lc.lane0, ... = ...` on an element of
  `getComponent(node, BASE_NODE_CONFIG).laneConnections` raised `cannot write to re[adonly ...]`
  (`[SQRL] SKIP ... reason=error:...sl_lanes.script.lua:233`). move_it's `lc.segment0 = ...`
  pattern therefore does not work as written. The tealdef has no `api.type.LaneConnection`
  constructor, **but the runtime has one**: `api.type.LaneConnection.new()` works (2026-10-08,
  `[SQRL] HOW strategy=ctor`). Set its six fields, put the objects in a list, assign the list to
  `entry.comp.laneConnections` of a `BaseNodeLaneConnectionAndEntity.new()` whose `comp` is the
  read config, and send `nodeConfigsToRemove = {node}` + `nodeConfigsToAdd = {entry}` from the GUI
  thread: `WRITE success=true`, and a re-read about 30 frames later matches (`VERIFY same=4 nodes=4`,
  4-lane ring).
- **`builtin.NodeViewer` crashes the game on an out-of-range `edgeIdx`** (2026-10-08,
  `square_smart_lanes` tool): `NodeViewer.cpp:76 Render: Assertion '0 <= edgeConfig.edgeIdx &&
  edgeConfig.edgeIdx < (int)transportNetwork.edges.size()' failed`, "Actual: 1 not in range [0, 1)",
  a fatal error that pcall cannot catch (it fires in the native render, later). It happened on a
  plain 2-segment ring node with 2 lane connections: `edgeIdx` = lane connection index (as base
  `double_slip_switch.tl:113-118` uses it) is not always valid, because the node's transport network
  can have fewer edges. Guard: only pass indices below `#getComponent(node, TRANSPORT_NETWORK).edges`,
  and draw nothing while a node config write is pending.
- **Never send `nodeConfigsToRemove` without a matching `nodeConfigsToAdd`** (2026-10-08,
  `square_smart_lanes` tool Reset probe on 3 ring junctions). The build succeeds, but the engine does
  not regenerate default connections: it deletes the node's `BASE_NODE_CONFIG` (re-read: 0
  connections, and a later config write finds no component to edit). About 13 s later the
  simulation thread died with `Engine.cpp:693 PostRemoveComponent: Assertion 'it !=
  components.end()' failed` (fatal, crash save written). move_it's and the overpass probe's
  remove-only use is only for nodes that are rebuilt in the same proposal. To "reset" a junction,
  write a full config (the engine-default model) with remove + add, as the Crossing Tool does.
- **Text colour classes don't show inside a disabled toolbar Button** (2026-10-08, `square_smart_lanes`
  lane badge): a TextView with `meta.class = "font-scale-body, positive"` (or `warning`) inside a
  `checkEnabledFn -> "Disabled"` one-value Button param renders grey like the rest of the disabled
  button (base `builtin.css.lua:268-275` wins). Use text (a prefix) for state instead of colour.
- **One-way arrows in any tool: `LayerConfig.showOneWay`** (2026-10-08, `square_smart_lanes`): the
  street builder's white one-way arrows are `LayerConfig.showOneWay = true` (api/type.d.tl:4924), set
  only for `ACTION_STREET_BUILDER_UPGRADER` in the local `getLayerConfig` of
  `gui/construction/construction_react_util.tl`. A custom tool gets them by adding
  `builtin.LayerConfig{ config = cfg }` to its `ActionDescriptor` children.
- **Native construction tools can be patched from a mod** (2026-10-08, `square_smart_lanes`):
  `ug_require "::/gui/construction/construction_react_util.tl"` returns the same module table the
  construction menu uses, and `construction.tl` calls `construction_react_util.getActionParams(...)`
  through it at render time. Wrapping it and setting `res.layerConfig.showOneWay` for
  `ACTION_LANE_MODIFIER_TOOL` showed the arrows in the native Crossing Tool. A mod tool's `.script.lua`
  loads with the game (before any tool is opened), so the wrapper is in place at load. Evidence: stdout
  `[SQRL] PROBE oneway=patched` at load, `oneway=crossing_tool` on opening the Crossing Tool, arrows in game.
- **Upload validation rejects references to mods that don't exist** (2026-10-08, `square_smart_lanes`):
  Mod Hub's validator checks the `<modId>::` paths a script loads and fails with "Lua Content ERROR …
  Exists: The Mod is not enabled, mod = '<id>'" when the ID isn't a known mod, even inside a `pcall` and even when the path is built at runtime (`id .. "::/..."`), so it probably runs the script.
  Trigger: a probe calling `ug_require("square_no_such_mod::/…")`. `make validate` doesn't catch this.
  Remove probes that name made-up mods before uploading.
- **`VisibilityThresholds.OfComponent.scale` doesn't shrink HUD icons** (2026-10-09, `square_better_bus_overlay`):
  documented as "Scale multiplier for hud icon" (`base/tealdef/scripts/builtin.d.tl:484`), and base fills it
  from `hud_gui_config.gres.lua` `renderDistances` (all 1.0). Setting the STATION_GROUP entry to 0.7 in the
  stop tool's `HudIconManagerConfig` (log `scale station 1 -> 0.7`) left the stop icons and their tags the same
  size in game. Probably a render-distance factor. To make a HUD tag smaller, build a smaller tag instead.

## Camera zoom limit (2026-10-09)

Found with the probe `square_zoom_probe` (log lines `[ZPROBE]`, game stdout.txt). `BaseConfig` has no camera
distance field, so the GUI camera API is the only route past the zoom-out limit.

- **`api.gui.camera.setCameraData` accepts a distance past the limit, but the camera eases back.** Vanilla max
  distance about 4137 m (pitch 0.95). Setting 20000 read back 20000 immediately, then 18834 (frame 1), 17793 (2),
  16301 (5), 8210 (30), and the vanilla max after about a second. x1.5 and x3 behaved the same.
- **`setManualCamera(center, distance)` and `focusPosition(pos, distance)` don't change the distance** (read-back
  ratio 1.00, both calls from a button `onClick`).
- **The far plane follows the camera distance automatically**: `getNearFar()` went 7200 → 17549 at 18.8 km and
  back to 7200 near the limit. A pushed camera doesn't need a larger `viewNearFar` in `baseConfig.settings`.
- **Construction template entries reach `getActionParams` without `menuCategory`** (2026-10-09,
  `square_better_bus_overlay`): `construction_react_util.tl:1074-1097` builds template definitions with
  `menuCategory = template.menuCategory`, but the definition passed to the `getActionParams` wrapper had
  `menuCategory == nil` for the street station (log `menu=nil … modular_terminal.con template=0`). Read it from the
  resource instead: `api.res.constructionRep.findAndGet(definition.resName).constructionTemplates_native:at(
  definition.constructionTemplate + 1).menuCategory` (template index is zero based). Its `categories` /
  `filterCategories` are native vectors: `ipairs` sees nothing, use `:size()` / `:at(i)`.
- **Recolouring a stop's HUD pin** (2026-10-09, `square_better_bus_overlay`): `builtin.UseDefaultHudIcon` is engine-drawn,
  takes no colour, and no stylesheet reaches it. Wrapping the `builtin.UseDefaultHudIcon` module field (checked by
  `react.getCurrentRecipeName() == "HudStationWithLineStops"`) and returning a copy works: the mask
  `::/gui/hud/icons/hud_background.tga` in an ImageView (Stretch) tinted by CSS `color` at **29x38 UI px**, with
  `::/gui/hud/icons/vehicle_bus_front_32.tga` at 20x20 stacked on top (two full-size FloatingLayoutChild layers,
  padding 5/4/13/5), matches the vanilla pin in the Lines window. As a nine-patch background at the mask's natural
  40x52 it came out ~40 % too big. Line dots and terminal numbers stay the base ones.
- **Station HUD icons switch from group to per-terminal when zoomed in** (2026-10-09, `square_better_bus_overlay`):
  a hud icon master is called with `param.index == -1` (one icon per station group) from afar, but close to the camera
  with `index >= 0`, one icon per terminal (in the Lines window these carry the terminal number,
  `manager_hud_util.tl:546-557`). A replacement that checked only `index == -1` showed when zoomed out and vanished
  zoomed in; handle both.
- **A HUD tag next to the stop icon gets stretched** (2026-10-09): `!hud-icon-main > BoxLayout` (gravity {-1, 0},
  `gui_react_util.css.lua:54-57`) stretches a tag placed beside `UseDefaultHudIcon` in a horizontal BoxLayout to the
  icon's height. Replace the icon with the tag inside `BoxLayout{ class = "station-icon-layout" }` instead, as
  free play does (`hud_icon_toolbox.tl:112-142`).
- **The camera controller eases toward its own hidden target distance, which mods can't set.** After a push, the
  camera eased back to the last scroll-wheel distance (2771 m, below the 4137 m max), not to the limit. Re-applying
  the distance every `react.onStep` (via `react.enqueueJoin`) held it on average, but the controller had already
  pulled it back 4–16% before each reset, so the view visibly jittered. "Continuous Zoom" (`zoomPrecise`) was
  tried and didn't stop the ease-back. No camera limit exists in the API, `BaseConfig` or `settings.lua`.
  **Result: a "zoom out further" mod isn't feasible with the current API; idea scrapped.**

## Highway street templates and interchange placement (2026-10-09)

Found with the probe `square_roundabouts_probe` (runs p7_hx_all / p7_hx_search, logs in
`plans/square_roundabouts/probe_p7_hx_*.log`; read via `api.res.streetTemplateRep`, GUI thread). Details:
`plans/square_roundabouts/INTERCHANGES.md` "Phase 7e notes".

- **Base highway templates** (`highway_new_small` / `_medium` / `_large`, ids 37 / 35 / 33 in this build):
  `maxSlope = maxSlopeShape = 0.4`, `maxSlopeBuild = 0.2`, `minCurveRadius = 44`, `minCurveRadiusBuild = 60`,
  `speedCoeffs` empty (curve speed for streets is engine-internal), lane speeds 27.78 m/s (small) and
  33.33 m/s (medium, large), `country = true`.
- **Those radius limits apply to the player's drag tool, not to constructions**: a construction's 25 m loops
  of `highway_new_small` placed (every highway, both levels), as do the base cloverleaf's 24-31 m loops.
- **A junction node on a large highway needs more than 10.5 m of plain edge to the next bridge end.**
  Highway over road (highway on a bridge over the cross road), a slip road joining `highway_new_large`
  10.5 m from the bridge's end: "Construction Not Possible" (65 of 65 combos); 17.5 m and 32.5 m placed.
  On `highway_new_medium` / `_small` 10 m placed. The limit between 10.5 and 17.5 m is not measured. Inferred:
  every refused layout had that 10.5 m piece, every placed large-highway one 17.5 m or more, and none of the
  searched tunables (clearance, gore run, terminal gap, loop radius 20-30 m) changed it; p7_verify confirms.
- **A construction whose edges reach about 485 m from its origin is refused** (2026-10-09, probe `p7_hx_scale`,
  `plans/square_roundabouts/probe_p7_hx_scale.log`, flat test map, origin 0 / 0, rotation 0). Of 1080 parclo
  builds every one with an edge end at |x| <= 481.25 m placed ("Highway over road", highway on an 8 m
  embankment: up to 462.5 m) and every one at |x| >= 486.25 m was refused (190 of 190), with mixed messages:
  "Construction Not Possible", "Too Much Incline" + "Construction Not Possible", or "Collision" (coll = 1,
  no buildings). Edge length (557 m single edges placed), gradient and |y| (<= 325 m tested) did not separate
  them. Inferred, not measured: whether the limit is per construction (radius or box around the origin) or
  the test map's buildable area (only one position was used); the exact value lies in 481.25-486.25 m
  (462.5-486.25 m for an elevated end). `square_roundabouts` keeps every highway build within the measured
  maxima (`hx.MAX_REACH`); p7_hx_scale_verify checks it.

## Negative zero in construction geometry (2026-10-09)

Found while fixing "Highway Interchange" in `square_roundabouts` (Phase 7e fix-up; logs
`plans/square_roundabouts/probe_p7_*.log`, notes in `plans/square_roundabouts/INTERCHANGES.md`).
Confirmed in game by the user on 2026-10-09: with the fix the layout is green at 0°, and the old build is red.

- **A `-0` in an edge's position or tangent can make a construction "Construction Not Possible" at exactly 0°
  rotation, with no other reason, no collision and no Lua error.** Symptom: red at Rotation 0°, green after
  rotating a few degrees, on any flat spot. In our case exactly one ramp had tangents `(+x, -0, -0)`; its point
  mirror with `+0` placed fine.
- **Why only at 0°:** the construction builder's placement transform at 0° is `1/-0/0/0/0/1/…` (sin = `-0`), so
  `(-0)(+x) + (-0)` stays `-0` in world space. Any other rotation, and a transform built from
  `Mat4f.new(Vec4f…)` with `+0`, turns it into `+0`.
- **A script probe can't reproduce it:** `api.engine.util.proposal.makeProposalData` with a
  `+0` identity transform placed every combination (thousands of calls, every context) while the UI refused
  the same file, params and position. Copy the builder's exact transform (it carries the `-0`) to reproduce,
  or test in the UI.
- **Fix:** before returning from `updateFn`, normalise every zero coordinate in `edgeLists` (positions and
  tangents) to `+0` (`if v == 0 then v = 0 end` turns `-0` into `+0`). Mirroring code (`-x`, `x * -1`, `-0`
  literals) is where `-0` comes from. `square_roundabouts_highway.lua` `hx.positiveZeros` is the reference, and
  `tests/square_roundabouts` forbids `-0` in the highway output. Print with `%a` or `%.17g` to spot it:
  `%.2f` hides the sign only sometimes (`-0.00`).
- **A world `-0` in a tangent's x placed** (2026-10-09, probe `p7_presets`, `plans/square_roundabouts/probe_p7_presets.log`,
  88 / 88 placed at the builder's exact 0° transform): the Channelized Junction's X layout, left-hand traffic,
  has side-road tangents `(-0, -y)`, world `(-0, …)` at 0°, and all 6 combos placed. The refused highway case
  had the `-0` in the tangent's **y** (`(+x, -0, -0)`). Which components (or which edges) matter is unclear, so
  normalise every zero anyway.
- **Fastest diagnosis when the probe and the UI disagree:** add temporary DEV params to the `.con.lua` that
  drop or swap parts of the layout (all, no ramps, only one ramp, …) and toggle them in the UI at a red spot.
  This found the cause in three rounds after many probe rounds didn't.
- **Probe artifact to avoid:** a `makeProposalData` for a `.con` called from inside the builder's own
  `guiHandleEvent` callback (`builder.proposalCreate`) for that same file is refused anywhere on the map. Don't
  use replays made there as evidence.

## Drawing arrows from an entity-window plugin (2026-10-09)

Found with `square_passenger_destinations` rev 1 (user's game test, 2026-10-09). Notes: `plans/square_passenger_destinations/PLAN.md`.

- **An entity-window plugin can draw map layers by stacking its own tool.** EOW plugins get `gameCtx.toolStack`. Pushing a
  window-less `react.RegisterTool{ push = function(ctx, p) ctx.setActionFn(actionFn, key) end, … }` with
  `allowStacking = true` makes its `ActionDescriptor` (e.g. `selector_react_util.makeDefaultSelectorAction(gameCtx,
  layerConfig, true)` with a `cargoFlowRenderableConfig`) the active one, and the arrows draw while the window is open.
- **Pushing shelves the entity window, which hides it** unless it is pinned (`EntityDetailsTool.shelve`,
  `gui/entity_window/view_manager.tl` ~404-415). The push handler runs after the shelve (`builtin.lua` push:
  `shelveNonTop`, then `pushHandler`), so `api.gui.byId.setVisible("temp.view.entity_<keyEntity>", true)` there brings
  it back. In game the station window stayed open with the arrows drawn. Popping the tool un-shelves the window tool.

## Mod terrain generators for base climates (2026-10-09)

Found with `square_blank_slate` rev 1 (user's game test, 2026-10-09; screenshots in `plans/square_blank_slate/shots/`).

- **A mod `.gen.lua` joins a base climate's generator list** with an absolute climate id:
  `climate = "::/climates/temperate/temperate.clima"` (the base files' relative `"temperate.clima"` would resolve inside
  the mod). Its tree's `climate` field uses the same form. No `_content.json` or other registration is needed: the file
  sits in `content/<dir>/` and `nodeTree` names the tree without folder or extension. It showed up as a "Generator"
  option in New Game, with an empty Terrain section because `params = { }`.
- **A heightmap PNG works as the whole terrain.** A `texture_map` node with `minHeight`/`maxHeight` `constant_number`
  inputs and `tex = "<modId>::/<dir>/<file>.png"` (16-bit grayscale, 1024 px) feeding `height_map_output` gave the exact
  shape, stretched over the map. Sea level is 0 m, so anything below 0 is water.
- **No trees or rocks:** an `assets_output` whose `assets` and `forest` inputs are a constant 0 `constant_map`, with
  mappings that only use other values, placed nothing. A minimal tree (`biome0` = 1, `biome1..4` and `forest_mask` = 0,
  a `Biomes` `output_biomes` of 0) ran fine on temperate with green grass ground and a sandy shore.
- **Towns and industries still appear** in New Game (25 towns, 9 industries on Medium): the menu's own sampler places
  them after the generator, whatever the tree outputs. The Map Editor's Generate heightmap turns them off.

## Timers and threads in GUI contexts (2026-10-10)

Probe `square_sqperf_probe` (log lines `[SQPERF-PROBE]`, game stdout.txt), "New Game - desert", build 40420.
`api.type.Clock.new()` and `:getTime()` worked in every GUI context, with no crash or error:

| Context | Thread column in stdout.txt |
|---|---|
| recipe render (GUI script) | Main Thread |
| `react.onStep` | Main Thread |
| `react.onStepTimer` | Main Pool N (worker threads, a different one per tick) |
| `hudIconScript` function and its recipe render | Main Pool N |

- Cost on the Main Thread (20 000 calls): `getTime` 0.07 µs, `os.clock` 1.0 µs. SQPERF's `wrap` adds 0.28 µs per
  call and `hit` 0.03 µs. Use Clock, not `os.clock` (which is also process CPU time over all threads on macOS).
- So the onStep/onStepTimer split matters: in this probe `react.onStep` ran on the Main Thread, while
  `onStepTimer` and HUD icon scripts ran on worker threads. GUI-thread-only calls (`api.gui.*`,
  `getApplicationTime`) belong in onStep or render, or behind `react.enqueueJoin` from onStepTimer.
  The earlier square_supply_gaps crash ("Main Pool 10") is consistent with a worker-thread callback.

## Stress Test probes (2026-10-10)

First in-game run of `square_stress_test`'s Probe tab (plans/square_stress_test/TESTING.md), a running free game
(not the map editor), build 40420. Evidence: `[SQST]` / `[SQST-PROBE]` lines in stdout.txt. All commands were sent
from the GUI state's `react.onStep` (Main Thread) through `api.cmd.sendCommand`.

- **Create a town in a running game (`town_create`): works.** `api.engine.mapgen.createTowns(seed, { one Map.Town })`
  then `api.cmd.makeTownCreateCmd` on its `toAdd`. `toRemove` came back as **all existing towns** (3 of 3): createTowns
  treats its input as the whole town list. The probe ignored it and no town was lost. Callback after 655 ms; the new
  town had `initialLandUseCapacities` {100,100,100}, `sizeFactors` {1,1,1}, 58 buildings, person capacities {97,93,93}.
- **Bigger towns (`town_create_big`): accepted.** Overwriting the TownInfo's `initialLandUseCapacities` with
  {1600,1600,1600} before `makeTownCreateCmd` was kept as given. Callback after 3962 ms; 580 buildings, person
  capacities {1537,1561,1416}.
- **Grow a town (`town_grow_x10`): works, almost at once.** `makeTownUpdateSizeCmd` with `sizeFactors` {10,10,10} and
  `updateAllBuildings = true`: callback after 2700 ms, `sizeFactors` read back {10,10,10} (not clamped), buildings
  58 → 343 within 5 s and 345 at 30 s; person capacities {97,93,93} → {836,878,974}.
- **Year jump:** `makeGameSetDateCmd(Date.new(2100, 1, 1))` → `success=true`, `getYear()` 2100 at once.
- **Money top-up:** the keep-balance loop (`makeJournalBookAssetCmd`, player `ACCOUNT` balance read) worked; the balance
  showed 204M on screen.
- **`api.engine.getEntitiesWithComponent(BASE_EDGE_STREET)` throws "Cannot loop over this component type".** `BASE_EDGE`
  throws the same (square_better_minimap, 2026-10-09). To list every edge, use
  `api.engine.system.streetSystem.getNode2StreetEdgeMap()` / `getNode2TrackEdgeMap()` (each edge appears under both of
  its nodes, so de-duplicate). Not every
  component type can be listed this way; `TOWN` works. Base GUI code only lists `TOWN`, `INDUSTRY`, `VEHICLE_DEPOT`,
  `TRANSPORT_VEHICLE`, `WAREHOUSE` and `STATION_GROUP` with it. Count street edges with
  `api.engine.util.octree.findEntitiesInCircle(pos, r, BASE_EDGE)` filtered by a `BASE_EDGE_STREET` component instead
  (that made probes 3a/3b fail; fixed, not re-run yet).

Second run (2026-10-10, build 40420, same setup):

- **Big growth factors (`town_grow` with {100,100,100}, `updateAllBuildings = true`) on Tacoma** (initCaps {233,314,244}):
  callback 3956 ms; buildings 499 → 816 within 5 s (818–821 at 30 s); person capacities {1347,2033,1742} →
  {4415,6958,7522}, about 19k capacity. The factor is **not clamped**, but the **building count plateaus** (probably
  street space) while the person capacity per building keeps rising.
- **`makeTownDevelopAtCmd(pos, true, true)` is not a useful generator.** 9 calls on a 150 m grid all returned success,
  but street edges +0 and buildings +0 (Tacoma 155 → 155, Vancouver 23 → 23 edges). The single-call run showed
  buildings +344, but a ×10 growth of the same town ran at the same time, so that number is not DevelopAt's. It adds no
  streets; the Stress Test has no "Develop now" button.
- **Town creation must be serialized.** `town_create_big` clicked several times quickly: all succeeded, but the
  callbacks slowed to 10–12 s and the before/after town-set diff reported the same "new" town for two creations (a race
  in the probe). One `makeTownCreateCmd` in flight at a time, the next after the callback.
- **Speed 8 sticks:** `makeGameSetSpeedCmd(8)` → `GAME_SPEED.speedup` 8 after 15 s, while
  `getEstimatedMaximumGameSpeed()` said 23. Speed 16 not tested yet.
- **Journal booking of 1e9 works** (balance 204M → 1.204B). 3e9 (32-bit overflow) not tested yet.
- **Emissions (`emissions_zero`) unresolved:** `makeEntitySetEmissionsCmd(e, 0, 0, r, r)` on 10 of 5180
  `EMISSION_EMITTER` entities (that type *is* iterable with `getEntitiesWithComponent`): read-back zero = 0/10 after 2 s
  and 0/9 after 30 s, with `missionEmissionsScriptFactor` = 1; the restore command reported failure. Either the command
  doesn't take effect or the read-back reads a different field.
- **Not run yet:** probes 4 (street from scratch), 5 (buy vehicles: the test save had no line), 6b (speed 16),
  6d (3e9 booking), 7 (runtime `baseConfig.noCosts`).

Third run (2026-10-10 06:15–06:26Z, build 40420, Towns and Traffic tabs; user: "it looks like it's working well"):

- **Spawn spread over the map** (bounds -4096..4096): 5 + 8 medium towns created serially, 1.3–2.0 s each,
  `initialLandUseCapacities` 400 kept, 175–250 buildings each. `makeTownCreateCmd`'s `resultEntities` came back
  **empty** (results=0); the new town is found by diffing the town list.
- **Placement was too strict:** Huge (3200, spacing 2500 m) near the camera placed 0 of 1 (16 candidates: near=12,
  edge=4), so Huge is still untested; after ~16 towns the coarse spread grid had 0 valid spots for Small (near=16).
  Fixed afterwards by relaxation steps (wider ring, 70 %, 50 % of the spacing, finer grid; never below 800 m).
- **`makeTownConnectWithIndustriesCmd`** with `getDefaultTownConnections`' `{{0,1}}` (0-based) and `keep = true`:
  success, ~0.8 s each.
- **Grow: one `makeTownUpdateSizeCmd` builds only ~250–350 buildings, and re-sending it keeps building.** Callbacks
  0.4–8 s per town, longer for bigger towns. With the SAME factor (1000, already capped) and
  `updateAllBuildings = true`, Town 10 went 889 → 1193 → 1494 → 1732 → 2065 → 2314 over 5 calls (~4 s each). The
  factor isn't the limit (this replaces the second run's "plateau" reading); hence the Grow form's build-out passes.
- **Freeze/unfreeze** 19 towns (`makeTownSetDevelopmentActiveCmd`): ~100 ms.
- **Hide notifications:** success with 29 type names from `getNotificationType2Label`, so `notification_util`
  resolves from a mod GUI script.
- **Add vehicles:** 25 buses on one line from depot 11332 (`findBestLineAndDepotForVehicle`), `makeVehicleSetLineCmd`
  true for all 25, ~0.6 s per vehicle, 0 failures; balance 193.1M → 104.4M (price check fine). Lines with no vehicle
  were skipped correctly.
- **Speed 16** was sent; no read-back logged (still unconfirmed).

Fourth run (2026-10-10 06:42–06:44Z, build 40420, Probe tab probes 4 and 9, Towns tab):

- **Street from scratch (`street_from_scratch`, probe 4 variant A): works.** A `SimpleProposal` street edge (`type` 0,
  `typeIndex` -1, `streetEdge` copied from a reference edge, template `country_new_small.street_template`) sent with
  `makeWorldBuildProposalCmd`: `success=true`, `critical=false`, no messages, cost ~36.6k, street edges +1. Worked 3 of 3
  times. Auto bus lines can build their own streets; stops and depot are still open (probe 10).
- **`SIM_PERSON` is iterable** with `getEntitiesWithComponent` (9a census: 693 persons, `scanMs=1`). By `lastMoveMode`:
  DRIVE=79, WALK=614. Persons driving right now (DRIVE + `MOVE_PATH`, no `SIM_PERSON_AT_VEHICLE`) = 63, and **all 63 have
  a `LAND_VEHICLE` component**: a private car is a `SIM_PERSON` with `LAND_VEHICLE` + `MOVE_PATH`, not an entity of its
  own. `LAND_VEHICLE` itself is **not** iterable. `lastMoveMode` 1 = DRIVE. `SIM_PERSON` fields: cargoType,
  destinations{3}, moveModes{3}, travelTimes, targetOrAtEntity, lastNonResType, lastMoveMode, walkSpeed, modelIdPerson,
  colorConfigPerson, modelIdCar, colorConfigCar, lastDestinationUpdate, landUse2ReachableWalkDrive,
  landUse2ReachableLines, pickupTime, happiness.
- **`api.cmd.debug.makeSimPersonSetStateCmd` works from a GUI script in a normal (release) game.**
  - State **2 (jump home)**: all 5 picked drivers were at their home building with no `MOVE_PATH` after 2 s; the car
    disappears from the road. Repeated 4×5 with the same result. By +15 s, 1–4 of the 5 were driving again (they start
    their next trip), so clearing traffic for good means repeating it.
  - State 1 (new path): no visible effect (still driving).
  - State 0: the command failed (callback `success=false`).
- **`PERSON_CAPACITY.pathfindingPreference`** on town buildings (9d): `destinationWeight=1`, `disallowedMoveModes={}`.
  Read-only: no command writes it.
- **Spawn Huge (3200)**: `initialLandUseCapacities` {3200,3200,3200} kept, 716 buildings, person capacities
  {1972,2605,2688}, 5.5 s.

Fifth run (2026-10-10 07:05–07:07Z, build 40420, Traffic tab Clear traffic, Probe tab probes 10a–10d):

- **Clear traffic works at scale.** One click scanned 11,096 `SIM_PERSON`s and found 285 drivers: 285 sent, 285 ok,
  333 ms wall (spread over frames). A second click right after found 64 drivers, 54 ok (the other 10 had changed state
  in between). **Keep cleared every 5 s** finds 205–349 drivers again each cycle (traffic regenerates within 5 s),
  382–394 ms per cycle, ok ≈ sent.
- **Bus stops by script work (10a/10b).** Variant A (the replacement edge's `comp.objects` holds the stop with the temp id
  `-400000000 + index`, `STOP_RIGHT`) succeeded on all 6 stops, cost ~39–42k each, one new `STATION_GROUP` per stop
  (found by diffing the list). Stops on edges 31–88 m long worked. Variant B was never needed.
- **Road depot (10c): placement often collides.** With the depot's free entrance node 22 m off the street centre
  (construction origin ~57 m from the edge middle), the build often came back `messages={Collision}` on both sides,
  once `critical` "Construction Not Possible" (the transform has no `-0` entries: every one goes through `z0`;
  cause unknown, maybe terrain). It succeeded 2 of 5 times.
- **A construction build's `resultEntities[1][1]` is not the construction.** The log said
  "construction=10438 has no CONSTRUCTION component" while `VEHICLE_DEPOT` went 0→2 (new 11468, 11587). Find a new
  depot by diffing the `VEHICLE_DEPOT` list and map it to its construction with
  `streetConnectorSystem.getConstructionEntityForDepot`. The probe stopped there, so the entrance connection is
  still untested. `cmd road_depot_here:build failed` lines next to a success are the refused tries of the other side.
- **10d found no depot**: "depot=nil (none)" although 11468/11587 existed. The fallback (nearest road depot within
  1500 m of the camera) filtered on `VehicleDepot.carrier == ROAD` and read the position through
  `construction.transf:getTransl()`; one of the two failed. Base code derives a depot's carrier from its
  `transportModes` (`gui/line_vehicle_mgmt/vehicle_util.tl:54-75`). The lookup now accepts either and falls back to the
  depot's `BOUNDING_VOLUME`, and logs per depot what it saw (not re-run yet).
- Fixed afterwards (not run yet): 10c walks candidate spots (along the edge at 0.5/0.25/0.75, both sides, entrance
  30/45/60 m off) over the 3 nearest edges, pre-checks each with `api.engine.util.proposal.makeProposalData` (depot and a
  stand-in stub street) and sends only clean spots; the new depot comes from the `VEHICLE_DEPOT` diff.

Sixth run (2026-10-10 07:40–07:45Z, build 40420, a 53k-person map, Traffic tab):

- **Auto bus lines in a dense town (SQST Town 6): the depot search failed every time**:
  `depot: edges=4 spots=72 tried=72 pre={Collision=72} sent=0 | no spot left` (the 4 outermost town edges, 3 gaps x
  3 params x 2 sides each, all refused by the `makeProposalData` pre-check). The stops and the line had been built
  **before** the depot step, so each failed try left an empty line with 2 stops behind (SQST Bus 3, 6, 9, 12) and
  spent the stop money. Fixed afterwards: the depot comes first (nothing is built without one), searched in rings
  outward from the centre with more gaps, any player road depot within 2 km counts, and a line left with no bus is
  destroyed again (not re-run yet).
- **Once a depot existed (151591, built by the user), 2 runs of 4 lines x 10 buses all worked**:
  `findBestDepotForLine` found 151591, 40 buses each run, ~6 s per line (11–14 s while Keep traffic cleared ran),
  2 stops 301–440 m apart on built-up edges.
- **Line names skipped by 3** (SQST Bus 3, 6, 9, 12, 15, 18): one counter was shared by the 2 stop names and the line
  name. Fixed: a counter of its own, continuing after the highest existing "SQST Bus N".
- **Three quick clicks queued 3 batches** (3 "bus_lines: 1 towns x 4 lines" plans). The buttons now refuse while the
  same kind of job is queued or running (bus lines / their removal; add / sell vehicles).
- **Remove added bus lines works**: 40 sold, 8 lines deleted, 0 failures (`makeLineDestroyCmd` after the buses are
  sold). **Ignore town emissions** (Game tab town ratings): 13 towns, 26 events ok. **Add vehicles 10**: 10/10
  bought. **Keep traffic cleared on 53.8k persons**: 2.4k–12k drivers per 5 s cycle, 1.1–3.8 s wall per cycle,
  0 skipped cycles.
- **Crash at 07:45:22Z, unexplained.** In the same second as the 3rd batch's "bus_lines 4/4 ... ok" and its summary
  (12 lines and 120 buses this session; 40 buses sold and 8 lines destroyed at 07:41:59), the Simulation Thread hit
  `Engine.h:323 GetComponentDataIndex` "Assertion it != components.end()" for entity 152444, component type 73 =
  TransportVehicle. 152444 then had TpNetLink, BoundingVolume, LotList and TerrainAlignmentList, which looks like
  a street stop / edge object, near the ids of the stops just built (station groups ~1525xx–1530xx). Suspected:
  something still referenced a sold bus's id after the id was reused, or a vehicle on an edge our stop proposal
  replaced; not proven, and no `[SQST]` line named 152444. Guards added afterwards: every vehicle or line id is
  re-checked (TRANSPORT_VEHICLE / LINE component, PLAYER_OWNED) right before its command, removal waits until the
  sold buses are gone and never deletes a line that still lists vehicles, stop edges with moving sim persons
  (`getSimPersonsMovingForTransportNetwork`, untested on street edges) and edges near our stops or depot gates
  come last, and every bought bus id and every stop's station group and result entities are logged (`rt.detail`)
  so a future crash entity can be matched against stdout.txt.
- **Unrelated(?)**: at 06:32:24Z, during a save load (no `[SQST]` line nearby), the Simulation Thread hit
  `gamescript_util.cpp:385` "Assertion 'false' failed", logged as a fatal-error exception, but the game kept
  running. Later traced to `state:get_native()` in the SQ Opt AAT fork; see "Game-script `get_native` asserts".

## ImageView raw pixel data (2026-10-09)

`builtin.ImageView{ data = {...}, size = api.type.Vec2i.new(w, h) }` draws a raw image. Verified in game (square_better_minimap network layer, calibration squares + road layer vs town markers):

- One Lua integer per **byte**. The data length must be exactly `w*h*3` or `w*h*4`. The binary checks `bytes / (w*h)` and accepts only 3 or 4 ("only 3 or 4 is supported"). Otherwise it logs an error and shows a default image; it doesn't crash.
- Channel order **RGBA**, and alpha works: alpha 0 is fully transparent over whatever is underneath.
- Rows are **bottom-up**: the first row of the data is drawn at the bottom of the image. Write rows in reverse for a top-down raster.
- Related (same mod): `api.engine.getEntitiesWithComponent(BASE_EDGE)` throws "Cannot loop over this component type". List
  every edge with `api.engine.system.streetSystem.getNode2StreetEdgeMap()` / `getNode2TrackEdgeMap()` (each edge appears
  under both of its nodes, so de-duplicate).

## Window `header` slot (2026-10-10)

`builtin.Window{ header = <node> }` (builtin.d.tl:1209) puts the node at the **left** of the title bar, before the
title, in the dark title tab (square_better_minimap size button). An empty title plus
`Window#<id> Window::Title { visibility = "none" }` removes the title text cleanly. In game, two attempts to
right-align the header next to the pin both left it at the left: `gravity = { -1, 0 }` on the header recipe's root, and
an explicit root `size` (picture width - 56 UI px) with the button at `gravity = { 1, 0 }`. The header container has no
stylesheet name in the base CSS (only `Window::TitleBar`, `TitleLayout`, `Title`, `Icon`, `Content`, `Close`, `Locate`).
The pin sits in its own notch outside the title tab.

## Game-script pauses don't stall rendering (2026-10-10)

Probe `square_hitch_probe` (`[HITCH]` lines, report `plans/hitch_probe/hitch_report.py`, steps in its README), a big
save at 1x, camera panning, ~60 fps.

- **A long game-script `update` does not delay rendered frames.** Busy-waiting 40 ms in `update` gave 0 of 13 pauses
  a slow frame, 100 ms gave 0 of 8 (worst frame of that level 50 ms). The control, a 40 ms busy-wait in the GUI's
  `react.onStep`, hit 6 of 6. The tester felt no difference either. `update` runs on `Sim Pool N` / `Simulation Thread`
  threads beside the `Main Thread`. So a slow sweep costs simulation time, not frames; per-frame GUI work is what
  players feel.
- **`GAME_TIME.tickCount` is not per frame**, despite its doc comment ("once per frame"): read from the GUI, it moved by
  4 once per simulation step, about every 200 ms (~20/s), with ~12-18 frames sharing a value.
- Game-script `update` ran in more than one simulation Lua state within the same 40-tick period (10 periods paused
  twice although the period was stored in the shared state), so a "once per interval" guard in a module local or even
  in the state can fire more than once.

## Game-script `get_native` asserts (2026-10-10)

- **`state:get_native():findPath({...})` in a game script's `handleEvent` throws a fatal assertion in game**:
  `gamescript_util.cpp:385` "Assertion 'false' failed" on the Simulation Thread (exception type "Fatal error"). The
  game keeps running when the call is wrapped in `pcall`, but every call logs the fatal error, and the first one wrote
  a crash dump (`crash_dump/*.dmp`, same second). The binary places that file in `GameScriptTableHelper` /
  `SyncTableBack`, the native state accessors (`get_native`, `set_native`; `gamescript.d.tl:42`).
- Evidence: `square_opt_zhenya_auto_assign_terminals` rev 1 called it per new station group in
  `onPostBuildProposal`. It was the only script among 21 active mods that used `get_native`. A save with it active
  logged 10 asserts 2–7 s apart (16:55:32Z–16:56:40Z) during a construction session; earlier unexplained cases
  (02:55Z, 06:32Z) all date from after the fork was linked. Not yet confirmed by a game run without the fork. Which
  call asserts (`get_native` or `findPath`, and whether only for missing paths) isn't isolated.
- Use `state:get()` in game scripts. The GUI-side `gameScript.state_native:find(key)` / `findPath(...):asTable()`
  (used by the base game, `industry_productivity_util.tl:11`) runs on the Main Thread, and no assert came from it in
  the same log.

## Wrapping rows in a GUI plugin: `builtin.FlowLayout` (2026-10-10)

- **`builtin.FlowLayout{ children = {...} }` wraps its children onto new rows to fit the available width**, also inside
  an entity-window plugin's `ContentCard` (`extraChildrenPermanent`). Its only field is `children`
  (`base/tealdef/scripts/builtin.d.tl:683`); the base game uses it for sparse construction-menu toggle buttons
  (`construction_desc_react_util.tl:970`, `builtin.lua:817`).
- Use it instead of splitting a horizontal `BoxLayout` into rows after a fixed item count: the window width varies (a
  port's station window is narrower than the counts assumed), and wider labels (two-digit numbers) overflow sooner.
  Items past the edge of a `BoxLayout` are silently cut off.
- Spacing: keep each item's gap inside the item (`BoxLayout{ item, gap }` with a fixed-width styled `Component` as the
  gap), so a wrapped row never starts with a bare spacer.
- Evidence: `square_passenger_destinations` rev 3. The station card's "Destinations: [] All [] 1 … [] Next stop" row
  (fixed 6 + 10 per row) was cut off in a port window; as one FlowLayout it wrapped correctly in game.

## 200 locals per function, also in a `.tl` file's main chunk (2026-10-10)

- A `.tl` script whose top level declares more than 200 `local`s fails to load in game with "too many local variables
  (limit is 200) in main function", and a GUI plugin in it takes the whole UI down ("Script component root failed",
  crash dump). Teal's type check passes such a file; `make check` now also compiles the generated Lua and reports it
  (`generated Lua: too many local variables ...`).
- Evidence: `square_better_minimap` `minimap_hud.script.tl` with 213 top-level locals crashed on load at 17:33:15Z
  (`MinimapHudPlugin`). Fix: group constants and helpers into tables.

## Translations: `strings.json` and `_()` (research 2026-10-10, in-game checks pending)

From game files and published mods, not yet tested in game. Replace each "pending" line with the in-game result.

**Verified in game (2026-10-10, square_better_minimap rev 6 from the staging area, game language Russian):**
`_()` in a GUI react script (HUD plugin recipes, a Window's content, CheckBox labels, a TextInputField
placeholder, Button text) shows the mod's `strings.json` `ru` text: "Пром / Фильтр / Сеть / Ярко", "Карта",
"Фильтр предприятий", "Показаны все типы". Cyrillic renders in all of them. Industry names from the game arrive
in Russian (and are longer: "Лесозаготовительное предприятие", so rows sized for English names clip; cut them
to fit). The Mod Hub "My Mods" page for that staging mod still showed the English name "Better Minimap" with the
`localization.ru` block present. Pending: whether the mod browser / mod list for subscribed mods uses it.

- `_` is a global (`api/tealdef/main.d.tl:9`, `global _ : function(string) : string`), implemented in
  `base/content/base/mod.lua:154-184`. It translates immediately only where the engine sets `_getTextNow`;
  everywhere else it returns the key unchanged and the engine translates the string when it displays it
  (resource files: `.con.lua` name/description/params, road and street `.lua`, `.names.lua`). So in resource
  files `_()` must wrap the whole displayed string: never `string.format`, concatenate or compare its result.
  GUI scripts translate immediately: the base game does `string.format(_("%.0f%%"), v)`
  (`base/content/gui/menu/settings_page.tl:88`), and community GUI scripts with a `ru` strings.json use `_()`
  the same way (zhenya_auto_assign_terminals `aat_eow.script.lua:73-80`).
- Used in published mods in: GUI `.script.lua/.tl` and the plain `.lua` modules they load, `.css.lua`
  (move_it `move_it.css.lua:20`), `.con.lua` (incl. param name/tooltip/values), `.names.lua`, `.clima.lua`,
  `.eco.lua`, `.mu.lua`, `.module.lua`, base-game HUD scripts. **Never seen** in a game script (`.gs.lua`)
  or in mod.script `runFn`. Pending: does `_()` translate there, and in `hudIconScript`?
- `strings.json` language keys are the short codes `en ru de fr es it nl pl pt_BR ja ko zh_CN zh_TW`
  (exactly the game's 13 locales in `base/content/locale/*.lang.lua`; community mods use the same keys).
  Fallback (wiki): language, then `en`, then the key itself. Pending: whether `pt_BR`/`zh_TW` fall back to
  `pt`/`zh` (irrelevant as long as every mod ships all 13 keys).
- mod.json param `name`, `tooltip` and each `values` entry are looked up in strings.json
  (zhenya_doubleclick_to_edit uses id keys, the wiki's param-filter example plain English text).
- `modinfo.json` `localization.<lang>.{name,summary,description}`: name ≤ 32 chars, summary ≤ 100, no line
  breaks. The wiki warns the Hub concatenates the languages into the uploaded mod.io description; we
  localize only `name` and `summary` (description.html stays English). `tools/modio_sync.py` ignores
  `localization`. A Hub upload with a `localization` block (name + summary only) did not concatenate anything:
  Blank Slate rev 3's mod.io description matched `description.html` exactly (2026-10-10, see "Mod Hub uploads
  and the mod.io gallery").
- Fonts: every locale has a Noto Sans CJK `unicodeFontMap` fallback, so Cyrillic and CJK should render in GUI
  text. Pending: CJK and Cyrillic in HUD (`hudIconScript`) text, whose font lacks some glyphs (▲).
- Named placeholders: the game's own convention is `{name}` plus `lang_util.format(s, {name = v})`
  (`base/tealdef/scripts/lang_util.d.tl:5`); plurals exist (`nGetText`) but no strings.json plural form is
  documented, so we avoid them.
- Pending: whether `strings.json` changes in the staging area apply live or need a game restart.

## Mod Hub uploads and the mod.io gallery (2026-10-10)

- A Hub update uploads every slide in `_metadata/`, whatever its name: `N.png` and `N-<hash>.png` both show up
  on the upload screen and on mod.io.
- With slides named `N.png`, a Hub update left the mod.io gallery wrong: it added new numbers next to old ones
  (Problem Radar rev 2 showed the settings slide twice) and the stored files were not byte-identical to the local
  slides. `make modio ARGS=--apply` fixed it by replacing the gallery as `N-<hash>.png` (`tools/modio_sync.py`).
- With local slides named `N-<hash>.png`, the name `make modio` uploads them under, a Hub update left the gallery
  exactly as it was: Blank Slate rev 3 (renamed slides, Hub upload) then gave "in sync" in
  `make modio ARGS='--diff --verify'`, which downloads mod.io's originals and compares bytes. So `make shots` now
  writes `N-<hash>.png` (first 8 hex digits of the sha256 of the file), and `modio_sync.py` reads both forms.
- The same Hub upload sent the new `description.html` (rev 3 changelog entry) to mod.io. Earlier Hub updates
  seemed to leave the description old; the cause is unknown (maybe a description edited while the game was
  running, or mod.io's scan delay). Check with `make modio ARGS=--diff` after an upload.
