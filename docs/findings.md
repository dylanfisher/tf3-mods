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
