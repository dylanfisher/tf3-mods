# Findings: Roads, junctions and constructions

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

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
- **A street joined onto an existing dead-end node by script keeps that node blocked** (2026-10-11,
  `square_stress_test` Junction test, user's screenshots). Link roads built with a `SimpleProposal`
  (`makeWorldBuildProposalCmd`, `streetProposal.edgesToAdd` only, no node configs) from the free arm ends
  of a `square_roundabouts` junction to town dead-end nodes: every **existing** node they joined (each arm
  end, both carriageway ends of a highway arm, each town node) showed the HUD's red dead-end sign
  (`BaseNodeItem` `dead-end-icon`, base `gui/main/internal_hud.css.lua:132`, BASE_NODE HUD entry
  `renderDistances.DeadEndPath`, `gui/hud/hud_react_util.tl:111`); the links' own **new** nodes (merge
  node, intermediate nodes) showed none. Inferred: the engine keeps an existing node's
  `BASE_NODE_CONFIG` (a dead end's has no lane connections) when a proposal adds an edge to it, and only
  sets up new nodes. Fix in use (not yet verified in game): replace the existing node by a new node at the
  same spot, its edges by copies, and re-point the far nodes' configs (remove + add).
- **Crash while a script link road replaced a node with more than one edge (2026-10-11, inferred)**
  (`square_stress_test` Junction test on wide-grid towns, crash save `crash_Empty 2_2026-10-11_13-45-40`,
  dump 0B4128F6). Simulation thread `Engine.h:323 GetComponentDataIndex` "it != components.end()",
  component type 27 = `BaseNodeConfig`, entity 49041 "not known, probably being added". In the same
  second, the previous link (to a town dead end, `deg=1`) had succeeded; the next was a Channelized T arm to
  a wide-grid town whose nearest node was a grid corner (2 edges). Every one of ~25 earlier links joined a
  dead end and worked. The link proposal removes the joined node, replaces all its edges with copies at a new
  node and re-points the far nodes' configs (remove + add with `LaneConnection.new`). Not proven which part
  fails with 2+ edges; the Stress Test now links only to dead ends (and its grids got corner stubs), and logs
  each link before sending.
  Update 2026-10-12: entity 49041 was a new node, and the link's new nodes had no `BASE_NODE_CONFIG` at all: see
  "Script link roads without node configs" below.
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
- **Removing an edge while a remaining node's lane connections still name it throws** (2026-10-11, `square_stress_test`
  Remove all roads, `stdout.txt`): a removal proposal (`edgesToRemove` + orphan `nodesToRemove`) for a batch of 100
  of 348 street edges logged `StreetShapeFactory.cpp:195 GetOrMakeLanes: Assertion 'false && "lc.segment1 not
  found"'` (entity 8123) and `makeWorldBuildProposalCmd`/`sendCommand` raised `std::exception` in Lua, for all
  four batches; no callback came. The map had Junction test link roads and Smart Lanes writes, i.e. nodes whose
  `BASE_NODE_CONFIG` was written by a script; such a node that stays (its other edges in a later batch) keeps
  pointing at the removed edge. Fix in the same proposal: `nodeConfigsToRemove` + `nodeConfigsToAdd` for each
  remaining node with the connections and crosswalks through the removed edges dropped (`stress_roads.tl`
  prunedConfig). Whether engine-generated configs alone also trigger it: unknown (earlier Remove all roads runs,
  without script-written configs, worked). Fix not yet run in game.
- **A street proposal touching a node whose traffic light change is still pending is refused** (2026-10-11,
  `square_stress_test` Junction test with `square_smart_lanes` rev 4, `stdout.txt`): three in-line links failed with
  `cmd failed` (`critical=false messages={}`) right after the Simulation thread logged `Apply: invalid entity: N`.
  Each N was a ring node Smart Lanes had sent `createTrafficLightProposal(node, cfg, NO)` for moments before
  (`[SQRL] LIGHTS node=N`), and the link's proposal re-pointed that node's config. Links into junctions Smart Lanes
  leaves alone (1-lane rings) never failed. Inferred: the light proposal replaces or re-creates the node (or its
  config) when applied, so a proposal built from reads made before it names a dead entity. Smart Lanes' lights
  VERIFY now reports `gone=` (nodes without a config any more) to confirm. Workaround: wait ~3 s after a junction
  build before linking to it, retry a refused link with fresh reads.

### The game's default crossroads connections vary per approach (log evidence 2026-10-12)

Untouched 3x3 crossroads have 36 road connections, but not always "one lane per turn, fanned into every exit lane".
Seed 488838, Stress Test Showcase twin g3b (`ab=game`, never written; node 331872, a 60/120 degree skewed crossing)
and a right-angle 3x3 (node 66527, log 2026-10-11_2312): at three approaches one turn (or both) came from **two**
lanes instead: kerb turn = kerb lane into the exit's two kerb lanes + the next lane into its far lane; far turn =
the lane next to the far lane into the exit's kerb lane + the far lane into the other two. Per arm in 331872: one
arm split both turns, one only the kerb turn, one only the far turn, one neither, and the 180-degree-symmetric arms
differed, so geometry alone does not decide it. Movements (approach > exit), their connection counts and the exit
lanes they reach always matched the one-lane model. Smart Lanes compares the "Game default" badge per movement
(sl_cross `X.isDefault`) for this reason. Open: picked nodes with `conns=0` (334396, a one-way road's
continuation; 333819, where a two-way 3x3 splits into two one-way roads) read no lane connections. The log
cannot tell whether their `BASE_NODE_CONFIG` was absent or its read threw (both read as "no config" then); the
pick audit now logs which (`skipped=no_config` / `skipped=config_error`).

### Traffic light component at build time (log evidence 2026-10-11)
A node's `BASE_NODE_TRAFFIC_LIGHT` component can already exist when Smart Lanes' automatic pass runs ~10 GUI frames
after the build: in a Junction test session (crash_dump `a01dd455-..._1004.txt`) freshly built Channelized X slip
nodes logged `LIGHTS src=auto ... light=true` (43 of 315 AUTO nodes), while other new AUTO nodes (Magic Roundabout
junctions) had none at that moment. So "AUTO without a light component" right after a build is unknown, not unlit
(square_smart_lanes `L.litOf`). The game adds AUTO lights only from 1950 (`traffic_light_config.res.lua`).

### Traffic light phases index the lane connections (2026-10-11)
`BaseNodeConfig.trafficLightConfig.states[i].lockedLanes` are 0-based indices into the node's `laneConnections`,
followed by its `crosswalks` (index `#laneConnections + k - 1` for crosswalk k; base
`gui/entity_window/double_slip_switch.tl:115-131`). A node-config write that changes the connection list but keeps the
read config's `trafficLightConfig` leaves phases pointing past the new list: in game, Smart Lanes cut a lit 3x3
crossroads from 36 to 16 connections, the proposal was accepted (`success=true`), and the simulation thread asserted
in the same second (`VectorMap.h:11 Add: key >= 0`, "Exception during simulation loop", entity = that node, which had
`BaseNodeTrafficLight`). The same write on another 3x3 crossroads a minute earlier was fine (whether it had lights is not logged; inferred: none, or phases that stayed in range). Any lane write must re-point
the phases: `cfg.trafficLightConfig:clone()`, new `api.type.TrafficLightState.new()` per state (duration,
minDuration, canSkip copied, lockedLanes remapped), assign `.states`, set it on the entry (square_smart_lanes
`sl_write.lua` W.remapLights, `sl_rules.lua` remapLocked).

### Traffic light phases: what the game files show about regeneration (code reading 2026-10-12, in-game checks pending)
From `base/content/gui/entity_window/double_slip_switch.tl` and a search of all base Lua/Teal and the mods in
`.cache/`; no in-game evidence yet (square_smart_lanes TESTING.md FK 2-3 will answer the open points).
- The Crossing window's phase editor commits every edit with `createTrafficLightProposal(node, config, preference)`
  on a `trafficLightConfig:clone()` whose `states` it replaced (`:46-57`, edits `:147-170`, Add Phase `:566-584`), the
  node's preference passed as read. Its **Reset to Default** button commits `trafficLightConfig.states = {}` (`:604-612`):
  an empty list stands for the game's default phases (inferred: the engine then makes them; the window shows
  phases only when `#states > 0`, `:66-68`).
- `userModifiedTrafficLightStates` (`api/tealdef/api/engine.d.tl:196`) is never set or read by any base script; only
  the engine handles it, so what it protects is unknown. The community mod undo_tf3_test refuses nodes that have it
  (or `userModifiedLaneConnections`) set (`signals.script.lua:128`). square_smart_lanes copies the read config and
  leaves the flag as it was (it logs it as `user_modified=` on its phases-only LIGHTS lines).
- A node-config write (`nodeConfigsToRemove` + `nodeConfigsToAdd`) that changes the connection list does **not**
  make the engine re-make the phases: it used the written stale `lockedLanes` and crashed (section "Traffic light
  phases index the lane connections"). Phases written with the lanes therefore stay as written at that moment.
- Open: whether a later build next to the node, an edge upgrade, or AUTO lights appearing after a script's read
  re-make the phases (and drop a script's edits).

### Crosswalk entries of a node config (code reading 2026-10-12, mapping not verified in game)
`BaseNodeConfig.crosswalks : {Entity}` (`api/tealdef/api/engine.d.tl:190`); the record has no other crosswalk field
(no lanes, no side). The base Crossing window uses only their count and order (phase index `#laneConnections + k - 1`,
`gui/entity_window/double_slip_switch.tl:128-131`). That each entry is the id of an edge at the node whose end has a
crosswalk is inferred: a game-made 3-way town node had 3 crosswalks and a dead end 1 (section "The engine's lane
connections at a town junction" below), and community mods re-point them with edge ids
(`.cache/subscribed/move_it_probe_overpass/.../overpass_probe.script.tl:1589-1598`). square_smart_lanes "When safe"
treats an entry that is none of the node's segments as a conflict (TESTING.md FK 1e checks the mapping in game).

### A connection unlocked in a phase does not give way (2026-10-12)
The game has no "turn on red" rule; a lane connection either has red (in the phase's `lockedLanes`) or may go. The
base Crossing window (click a junction: Phase #N boxes, click a lane curve to toggle red / green) can unlock a right
turn in every phase. In game on a lit T-junction, the unlocked right turners did NOT give way to conflicting traffic
that had green: an unlocked connection drives as if it had green, with no yielding. The default phases lock the kerb
turn together with its approach.

Later observations (user, in game 2026-10-12, Lights showcase seed 530609, Smart Lanes "When safe"):
- **Merging is tolerable:** a freed kerb turn whose exit lane also takes another approach's green straight stream
  (Smart Lanes `kept=merge`) merges into it; the user judged that overall more efficient than holding the turn red.
- **Pedestrians: mostly avoided, not reliably.** With a crosswalk green at all times, turning cars sometimes slowed
  for pedestrians and sometimes drove through them; mostly they seemed to avoid them. So a turn released across a
  green crosswalk is not safe.
- **Country roads get no houses:** after x10 growth no buildings stood along the `country_*` link roads or the
  grid's country perimeter ring (agrees with the wiki, `tracksstreets.md:170`).
- **109.5k sim persons ran smoothly at 4x** (64 Medium towns, all level-4 buildings); 8x stuttered.

### Traffic light phase records, units and defaults (code reading 2026-10-12; in-game values: "Default traffic light phases, measured in game")
From the tealdefs and the base Crossing window; square_smart_lanes TESTING.md "LP" (`PROBE phases` lines) answers
the open points in game.
- **A phase has four fields**: `TrafficLightState` = `lockedLanes {integer}`, `duration number`, `minDuration number`,
  `canSkip boolean` (`api/tealdef/api/engine.d.tl:166-174`). No yellow, clearance, offset or per-lane timing field.
- **The config has no cycle field**: `TrafficLightConfig` = `states` + `trafficLightType integer`
  (`engine.d.tl:177-183`); no cycle length, offset or coordination between nodes. `trafficLightType` is a key of
  `api.res.trafficLightTypeRep` (the `.trl.lua` look: Type A / C and the dry variants): the window's type buttons set it
  together with preference YES (`gui/entity_window/double_slip_switch.tl:501-523`).
- **Units are seconds**: the window labels `duration` and `minDuration` with " s" (`double_slip_switch.tl:378`, `:452`).
  Its duration slider runs 1..60 whole seconds (`:357-372`, the value shown floored). The min-duration slider runs 0..60
  half steps, i.e. 0..30 s by 0.5 s (`:427-441`), enabled only with `canSkip` (`:444-446`). `canSkip` = "Allows this phase to end
  early or be skipped entirely when these lanes are empty and traffic is waiting on another phase" (`:387`): the phases
  are demand-actuated, `minDuration` the least green before an early end. A script may set other values; whether the
  engine clamps them is unknown.
- **The running phase**: `BaseNodeTrafficLight.state` is the 0-based index of the running phase (the window reads
  `states[state + 1].duration`, `:28`), `.time` the seconds spent in it (progress = time / duration, `:29`). The
  component also has `stateTimes {integer}` and `trafficLightData : TrafficLightData` = `state2lockedLanes`,
  `state2redLightModelIndices`, `state2duration`, `animatedModels` (`engine.d.tl:200-207`, `api/tealdef/api/type.d.tl:1216-1221`);
  no base script reads them (inferred: the engine's copy of the phases and which light models show red per phase).
- **All-red is an ordinary phase**: the window calls a phase with every connection and crosswalk locked a "pause
  phase" (`isPausePhase`, `:230`; its "Set All to Red" button is disabled then, `:284-322`), and **Add Phase**
  appends such an all-red phase made with `api.type.TrafficLightState.new()` (`:572-578`, duration left at the
  constructor's default, unknown). Whether the game's default phases contain all-red phases: probe.
- **Yellow is no phase**: the light models have only `green` and `red` animations, each animating the red, yellow and
  green lamp meshes (`infrastructure/traffic_light/traffic_light_a/traffic_light_1.mdl:19-83`); the pedestrian light has
  red and green lamps (`traffic_light_a/pedestrian_light.mdl:19-60`). Inferred: amber is part of the model's change
  animation, not a state in `states`.
- **The default phases are made by the engine**: no Lua or Teal file of the base game, the official mods or the
  subscribed mods builds phases (search for `lockedLanes`, `state2duration`, `minDuration`, `canSkip`: only
  `double_slip_switch.tl` and the community probe `undo_tf3_test/content/undo/tool_probe.script.lua:33-35`, which only
  prints them). The only light setting in the game files is `trafficLightYearFrom = 1950`
  (`infrastructure/traffic_light/traffic_light_config.res.lua:5`). The default phase structure and durations are
  therefore known only from game reads (probe).
- The phase editor appears only at nodes with more than two street segments (`gui/entity_window/view_manager_util.tl:34-41`).
- Light models are placed per street end, one per lane that `needsLight`, sidewalks included
  (`infrastructure/traffic_light/trafficlightutil.lua:152-170`, `:262-281`; wiki `modding/infrastructure/trafficlights.md`
  "Model Script"): pedestrian lights stand per edge end, which fits crosswalks being per edge (section "Crosswalk
  entries of a node config").

### Default traffic light phases, measured in game (2026-10-12)
Smart Lanes probe (`[SQRL] PROBE phases`, session `2026-10-12_0753` in `.cache/logs`, build 40420, 5 fresh lit
junctions: 2x2, 3x3, 3x3 x 2x2 crossroads and two T-junctions; user screenshots of the Crossing window agree):
- **Every default plan has 6 phases**: axis 1 green -> all-red 6 s -> axis 2 green -> all-red 6 s -> pedestrians
  only (every crosswalk green, every vehicle red) 3 s -> all-red 9 s. T-junctions use the same 6-phase shape.
- **Green durations scale with the junction**: 18.86 / 21.55 / 23.70 / 27.09 s seen (larger roads longer). Every
  phase has `canSkip = true`, `minDuration = 1.5`. Fully locked phases are the all-red pauses (the Crossing window
  greys their X icon). `trafficLightType = -1`, `userModifiedTrafficLightStates = false`.
- **A cycle is ~71-78 s, of which 21 s all-red and 3 s pedestrian-only** (2x2: 23.7+6+23.7+6+3+9 = 71.4 s).
- **An axis phase greens every movement of both opposing approaches, left turns included** (node 5921, 2x2: phase 1
  unlocks the A and C straights, right turns and left turns together), so far turns run against the opposing
  straight; with no yielding ("A connection unlocked in a phase does not give way") they conflict by design.
- **Crosswalks are the node's edge ids** (`cw_is_edge=y` on all 18 crosswalks probed), one per arm.
- **Phases survive a Smart Lanes lane write** as durations; lockedLanes are re-pointed (node 5921 read again after
  24 -> 16 connections: same 6 durations).

## Script link roads without node configs (game logs 2026-10-11/12; fix not run in game yet)

`square_stress_test` Junction test and Showcase link roads (`stress_junctions.tl` linkProposal / linkPairProposal)
replaced each joined node by a new node and added pieces, a highway merge node and copies, and gave **none** of
those new nodes a `BASE_NODE_CONFIG` (only the far nodes of the copied edges got re-pointed configs). Evidence from
the archived logs (`make logs-grep PAT='Engine.h:323'`):

- **The link nodes really had no config.** Showcase seed 204313 (`2026-10-12_0525_showcase-204313-crash`): Smart
  Lanes' drop pass, run right after each link, logged `[SQRL] SKIP slip_job=N node=X reason=no_config` for 37 link
  nodes (`APPLY kind=drop ... before=0`), one per town link it looked at, e.g. `Group 1 Roundabout -> Grid S7 linked`
  then `node=21674 reason=no_config` (the node where the link's copied street meets the town street).
- **Every Engine.h:323 assert on `BaseNodeConfig` in the archive followed a script proposal that added config-less
  nodes**, with the entity "not known, it was probably being added on the crash site":
  - `2026-10-11_1947_junction-grid-crash`: entity 49041, component 27, in the same second as `Cell A3 Channelized X ->
    Grid A4 linked ... node=49035` (the next link was being sent; see "Crash while a script link road replaced a node"
    above).
  - `2026-10-12_0227_sqot-sqperf-crash` and `2026-10-12_0504_sqot-dev-sqperf-crash` (Organic Towns DEV): within the
    second after `[SQOT_DEV] SEND` / `RB SEND ... newNodeConfigs=none` (towns.md "Street proposal crash").
  - `2026-10-12_0525_showcase-204313-crash`: entity 21742, component 27, 16 s after the last Showcase link, while
    Showcase bus lines worked on the Grid S6 -> Grid S7 route (a depot connect refused 1 s before; its proposal's
    split node -4 had no config either). Grid S6 and S7 are the two towns whose link nodes 19850 and 21674 Smart
    Lanes had just reported without config. No `[SQST]` line names 21742, and entity ids are reused, so this one is a
    correlation only; the earlier "Car traffic" suspicion (lines-vehicles.md) is not ruled out.
  - The other two Engine.h:323 sessions (`2026-10-05_0518`, `2026-10-10_0544_grow-x100`) name `TransportVehicle`,
    not `BaseNodeConfig`: unrelated.
- **Correlation, not proof**: no crash pinned a specific script node, and the Showcase crash came between proposals.
  Organic Towns' later run (towns.md, "Update: the cause is the missing configs") is the strongest evidence: the same
  proposal shape with configs never crashed.

Fix (square_stress_test rev 2, `gui/stress_nodecfg.tl`, offline-tested only): every street proposal of the mod gives
every node it adds a config, and an existing node that gains an edge a full one: the engine pattern per segment
(arriving road lanes into leaving ones, outer with outer: `a.1 > b.2` on two-way town streets, `i > m + 1 - i` on a
one-way continuation, read from each segment's `laneConfigs` `forward` and `transportModes`), nothing between two
segments that leave the node within 30 degrees (the highway merge node's U-turn), an empty config on a 1-edge node.
A replaced node's new node takes the old node's config re-pointed at the copies plus the link piece's pairs; an
existing node keeps its connections, is removed first only if it has a config. Check in game: `[SQRL] ...
reason=no_config` should no longer appear after Showcase links, and the link nodes should read a config.

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

## Terrain-shaping constructions (verified in game 2026-10-11)

Probe `square_terraform_probe` (DEV, since deleted; plans/square_terraform/FEASIBILITY.md): a construction whose only content is one `terrainAlignmentLists` entry
(EQUAL, flat 32/64 m pad or 8 m strip, +5/+10 m, slopes 0.3/0.6), `cost = 0`, a barrel marker model. Flat test map.

- A construction can go in the terrain tools' tab (`menuCategory` `landscaping_terrain`); it shows after the
  native tools.
- The builder shows the usual **"Costs: $… / Reputation: -x% (n towns impacted)"** tooltip before the click, so a
  construction is a real preview-and-confirm terraform step. Builds are one `onPreBuildProposal` each with
  `proposal.terrain` untouched; the volume arrives as `data.terrainPreviewHeightModCutFill` (x = volume).
- **Cost = cutFill volume × `costs.terrainLower`** (6.5625/m³ here, base 5.25 × purchaseCostScale), even for a
  raise. The slopes dominate: a 32 m +5 m pad (5,120 m³ nominal) moved 13,038 m³ for $85,561.
- Reputation goes through `getTerrainAlignmentImpact` (logged as alignment volume removed, about volume / 3), not the
  brush path; about 0.2% per 13k m³ near a town.
- **The change is an alignment, not a base-height edit:** `getHeightAt` reads the new height a few seconds after the
  build (not yet in `onPostBuildProposal`), `getBaseHeightAt` stays at the old height. So the shape belongs to the
  construction (it would most likely revert on removal).
- The placed pad (barrel marker) could **not be selected with the bulldozer**. Not yet known why (marker model,
  missing collider/lot, or the landscaping category).

## Octree edge search matches the edge's position, not its extent (in-game run 2026-10-12, inferred)

- `api.engine.util.octree.findEntitiesInCircle(pos, r, BASE_EDGE)` with a small `r` centred on a street node does
  **not** return that node's streets when they are long: Lights showcase seed 4951 (log
  `.cache/logs/tmp/2026-10-12_2244_top-up-4951.log`) searched 15 m around each town grid's side-middle node (75 m and
  300 m streets) and found nothing for 96 of 96 towns (`kind=crossroads (no grid node at the side's middle) at
  -6324,6908`, exactly the side's middle of the town at -6024,6908 with its 600 m grid), while a 750 m search around
  the town centre found every one of those nodes at the same point (96/96 links). So an edge is matched by a point
  (most likely its midpoint), not by its bounding box. Not probed directly.
- To find a node or the edges at a point, query with a radius that covers half the longest edge there (or around a
  wider centre, e.g. the town's), then filter by distance; or test `BASE_NODE` (unverified).

## A construction's street end inside a neighbouring junction collides with its node (in-game run 2026-10-12, inferred)

Log session `2026-10-12_2343_top-up-563524` (`.cache/logs/`; Lights showcase; plans/square_stress_test/SHOWCASE.md
"In-game refusal"). One proposal per town removed the grid's side-middle node and its three 75 m streets and added a
square_roundabouts Roundabout centred there (2-lane ring at 24 m, `country_new_large` arms ending 62 m out, rotation 0).
`makeProposalData` refused all 96 with `Collision (hits 12 other BASE_NODE e.g. #N)`: no street, no town building.

- **The arm ends lay inside the junction areas of the next grid nodes** (75 m out; crossroads / T-junctions of the
  32 m large town street, so their areas start about 75 - 16 = 59 m out). The named ids are the strongest evidence
  (their `[SQRL] APPLY` lines in the same log): 24 of the 96 were crossroads (every S town's entry), and the only
  crossroads within reach of an entry is its inward far node (the side-middle node and the ring far nodes are
  T-junctions); the other 72 were T-junctions. The hit is listed as the **node** (`BASE_NODE`), not as its streets. Inferred: only one id per refusal was
  logged; the split of the 12 (3 far nodes x 4?) is not known. The Stress Test now logs every hit's role.
- **Streets the same proposal removes are not collided with**: the three removed edges lay under the arms for 38 m
  each and no street was hit (other refusals do list streets, towns.md "makeProposalData refusals"). So a construction
  can replace a crossroads in one proposal (`edgesToRemove` / `nodesToRemove` + `constructionsToAdd`); splitting it
  into two proposals would not have helped. Inferred from the missing street hits, not probed directly.
- Rule: keep a construction's free street ends (and any edge) out of a neighbouring node's junction area: about half
  the widest street at that node, measured from the node. A short join piece from the end to the node is fine.
- First fix, `square_stress_test_entry.con` with every arm ending 46 m out: ran in session
  `2026-10-13_0018_top-up-598153` and was still refused at all 96 entries, now only by the inward crossroads (next
  bullet). Current fix (ran from session `2026-10-13_0045_top-up-158690` on, accepted: next bullets): the inward arm alone shortened (46 / 42 / 38 / 36 m, the first the
  pre-check passes); the ring runs clockwise for left-hand traffic.
- **Second run (log session `2026-10-13_0018_top-up-598153`): a town crossroads' area reaches farther than half the
  street width.** With arms ending 46 m out, all 96 entries were still refused, now `Collision (hits 2 other BASE_NODE
  (1 distinct) ...; known: #id in far node)`: every hit was the inward far node (a lit crossroads of four 32 m
  `town_new_large` legs, 75 m from the centre, so 29 m from the arm end), while the left / right far nodes (lit
  T-junctions whose approached leg was the 30 m country ring street) at the same 29 m were clear. So that crossroads'
  area reaches more than 29 m along a leg (16 m half width + about 13 m or more). Inferred, not measured: likely the
  town street's sidewalk crosswalks and kerb corners of two 32 m streets (country roads have no crosswalks), and it
  is evaluated with the leg the same proposal removes still there. Both nodes were lit, so the lights don't separate
  them. Keep construction street ends more than ~30 m from a wide town crossroads; the Stress Test now tries the
  inward arm at 46, 42, 38, 36 m with makeProposalData and takes the first that passes.
- **What fits (log sessions `2026-10-13_0045_top-up-158690` (2-lane ring), `2026-10-13_0205_top-up-61157`,
  `2026-10-13_0356_top-up-779299`, `2026-10-13_0447_top-up-726115` (3-lane ring)):** in a Medium town grid (75 m
  blocks, 32 m `town_new_large` streets) replacing the side-middle T with a 4-arm roundabout of `country_new_large`
  arms: a 2-lane `highway_new_medium` ring (centreline 24 m) or a 3-lane `highway_new_large` ring (centreline 22 m,
  outer edge 33.5 m) with the left / right arms ending 46 m out and the inward arm 42 m out was accepted every time
  (inward 46 m always refused by the crossroads 75 m in). So a wide town crossroads needs about 33 m of clear leg
  from a construction's street end; a T of the same street about 29 m or less.


## A lit T that loses a leg loses its light; Smart Lanes re-plans a lit node after a removal (log session 2026-10-13_0045_top-up-158690)

Lights showcase entries (removal of the side-middle node and its 3 streets, then joins to the far nodes):
- The ring far nodes (lit T-junctions that became 2-street corners) had **0 traffic light phases** at the join
  (`unmapped (phases 0, were 6)`, every one of 74 joined entries): the engine dropped the light of a node left with
  two streets. Inferred from the phase count; the preference was not logged.
- The inward far node (a lit crossroads that became a T) had **a connection the pre-removal config lacked**
  (`connection -3:1>-2:6 is new`, every one): its lanes were rewritten between the removal and the join (Smart Lanes'
  automatic pass on the changed node is the likely writer; the game-default twins showed the same, so the engine
  regenerating the T's connections is possible too). So a ghost of the old config can't be carried over after any
  delay; the Stress Test now switches such nodes' lights off after the join (the game's createTrafficLightProposal,
  preference NO).
