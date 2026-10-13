# square_smart_lanes ("Smart Lanes")

Plan written 2026-10-08. Mod: `mods/square_smart_lanes/`. Tests: `tests/square_smart_lanes/`.
In-game checklist: `TESTING.md`. Flow results (Lights showcase twins, running ledger): `RESULTS.md`. Background: `plans/square_roundabouts/PHASE6.md` (probe design),
`docs/findings.md` "Junction lane connections (2026-10-08)", probe `mods/square_roundabouts_lanes_probe/`.

## Goal
Assign sensible lane connections ("which lane may go where") at street junctions by writing
`BASE_NODE_CONFIG.laneConnections` from a game script, the same data the vanilla Crossing Tool edits.
1. **Roundabouts, automatic (Phase 1, implemented).** After every player build that adds street
   segments, find the one-way rings among the built nodes and apply the roundabout lane rule to their
   junctions.
2. **Road tool (Phase 2, step 1 implemented).** "Smart Lanes" in Roads -> Tools, right after the
   Crossing Tool: click a junction or a whole roundabout, see its lane connections, choose a layout
   (Matched lanes / Turbo / Game default), Apply or Reset. Roundabouts first; ordinary crossroads
   (turn lanes by angle) later.

3. **Slip-lane junctions (Phase 4, implemented offline).** Diverge / merge nodes of slip lanes,
   splitter legs and ramps: lanes matched one to one without crossings, automatically after a build
   and with the tool ("Phase 4" below).

Separate mod from `square_roundabouts` (which stays construction-only); works for our rings, the
vanilla roundabout and hand-built rings.

## Decisions
| decision | why |
|---|---|
| Game script (`content/smart_lanes/sl_lanes.gs.lua`), no `runScript` | params are read with `api.engine.config.getModParams()` where needed (as the probe); a `runFn` would run in ~50 Lua states for nothing (findings.md) |
| Build event on the engine thread only queues node ids in the game-script state; the GUI thread computes and writes | `sendCommand` inside a build event asserts `!m_betweenChanges` (`square_full_refund` refund.script.tl:345-347); `sendCommand(cmd, callback)` from the engine `update` fails "Callbacks are currently disallowed" (findings.md); undo_tf3_test sends node-config proposals from the GUI thread with a callback (`.cache/subscribed/undo_tf3_test/content/undo/tool_probe.script.lua:118-135`) |
| Ignore builds without `addedSegments` | our own write and Crossing Tool edits are config-only builds (`nodeConfigsToRemove` + `nodeConfigsToAdd`, no streets; findings.md), so no loop and no overwriting of the player's own edits |
| Seeds = `nodeConfigsToAdd` entities + `addedNodes` + both ends of `addedSegments` | the post event carries real entity ids (probe log: `ADDNODE entity=17955` = the later `NODE node=17955`) and a config for every new or changed node |
| One `makeWorldBuildProposalCmd` per ring: `nodeConfigsToRemove = {nodes}`, `nodeConfigsToAdd = {entries}`, `Context{player, cleanupStreetGraph=false}`, args `(false, true, true)` | as the Crossing Tool and undo_tf3_test (`tool_probe.script.lua:124-130`); `api/tealdef/api/cmd.d.tl:961-962`, `type.d.tl:2537-2571` |
| New `LaneConnection` objects from `api.type.LaneConnection.new()` | read objects are read-only and the tealdef has no constructor, but the runtime has one (findings.md 2026-10-08, `HOW strategy=ctor`); `sl_write.lua` keeps the table / owned / subset fallbacks |
| Every other config field (crosswalks, traffic lights, `userModifiedLaneConnections`) is kept as read | the Crossing Tool leaves `userModifiedLaneConnections` nil (findings.md) |
| `severityAdd: None`, `severityRemove: None` | written lane connections are ordinary BaseNodeConfig data, identical to a Crossing Tool edit, and need nothing from the mod; the game-script state is a job list that empties itself (ttl 300 engine updates) and is ignored on load |
| `cosmetic: false` | lane routing changes traffic (wiki `moddefinition.md:69`: anything with an impact on the simulation is not cosmetic). Flip if you decide "same as a vanilla tool" counts as cosmetic |
| Bus lanes (road lane without CAR) skipped | a car exit into a bus lane would strand cars |
| Tram: the engine's `withTram` connections are copied untouched, our road connections merged in (a shared lane pair keeps both flags) | user requirement; the rule only reasons about road lanes |

## Research (verified in files)
| fact | source |
|---|---|
| `BaseNodeConfig { laneConnections, crosswalks, trafficLightPreference, trafficLightConfig, doubleSlipSwitch, userModifiedLaneConnections, userModifiedTrafficLightStates }` | `.cache/game/api/tealdef/api/engine.d.tl:184-196` |
| `LaneConnection { segment0, lane0, segment1, lane1, withRoad, withTram }`, lane index "from left to right when looking from the Node to segment0/1" | `api/tealdef/api/type.d.tl:1200-1213` |
| `BaseEdge { node0, node1, position0/1, tangent0/1, laneConfigs, roadTemplate }` | `engine.d.tl:99-130` |
| tangent0 and tangent1 both point node0 -> node1, length about the segment length | `.cache/game/mods/release/urbangames_campaign_mission_02/content/mission/mission_params_02.tl:265-290` |
| `transportModes : {TransportMode : boolean}`, enum order PERSON, CARGO, CAR, BUS, TRUCK, TRAM, ELECTRIC_TRAM ...; `api.type["enum"].TransportMode.X` | `type.d.tl:2217-2234`, base `base/mod.script.tl:459-464`; probe log `lanes=...:2+3+4` |
| street templates: lane order left to right in edge direction, sidewalks first/last, one-way templates all-forward driving lanes, tram templates add TRAM to a car lane | `.cache/game/base/content/infrastructure/street/town/*.street_template.lua` |
| node -> segments `streetSystem.getNodeStreetSegments(node)` | `api/tealdef/api/engine/system.d.tl:312` |
| engine default at a ring arm node, lane convention, Crossing Tool build shape | findings.md, probe log (`[SQRB-LANES]` in game stdout.txt, builds 1, 2, 4) |
| state subscription pattern `subscribeToNoEvents` + `subscribeToEvent` in `update` | probe `lanes.script.lua` (worked in game), memory "GS gui events need subscribe" |

## Lane model (sl_ring.lua)
- A **road lane** has CAR, BUS or TRUCK in `transportModes`; sidewalks, shoulders and tram-only
  tracks are not road lanes. Nothing is hardcoded about sidewalks: indices come from `laneConfigs`.
- Connection index of laneConfig `k` (0-based, `L` lanes): `k` at node0, `L-1-k` at node1.
  A lane leaves the node when (`node0` end and `forward`) or (`node1` end and not `forward`).
- **One-way** segment: all road lanes share one `forward` value.
- **Ring** through node n: the shortest directed cycle of one-way segments through n (Dijkstra by
  length), accepted when it has 2-32 segments, at most 1200 m, the same road-lane count on every
  segment, no bus lane, and turns smoothly (at most 45 degrees between consecutive segments at a node:
  rejects one-way city blocks). The shortest cycle is the ring itself, never a loop out through a
  splitter leg (that loop replaces one ring segment by two longer legs).
- **Direction** from geometry: signed area of the Hermite-sampled ring (> 0 counterclockwise). Works
  for 2-node rings too.
- **Turn side** = the side the ring turns to (driver's right on a counterclockwise ring). Lanes are
  ordered from the turn side inwards: ring in `o_in`, ring out `o_out` ("outer first"), arm exit lanes
  `x` and entry lanes `e` ("kerb first"). Ascending connection index runs driver-right -> left on an
  incoming segment and left -> right on an outgoing one, so for CCW: `o_in` ascending, `o_out`
  descending, `x` descending, `e` ascending; CW is the mirror. Left-hand traffic is therefore handled
  by geometry alone (a mirrored world gives mirrored connections: test).
- **Node kinds**: `plain` (only the 2 ring segments, never touched), `arm` (exactly one non-ring
  segment with road lanes: a two-way arm, or a one-way splitter leg with only exits or only entries),
  `skip` (two non-ring road segments, e.g. a road through the centre; bus lanes; logged).

## The rule (sl_rules.lua, variant "Matched lanes", key `two_lane`)
Revised 2026-10-08 after the in-game report "4 lanes turning into 1": the first rule fed every
entry lane into `o_min(j, feed)` with `feed` = 1 unless some arm had a 2-lane exit, so a 4-lane
one-way stem into a ring without exits put all 4 entry lanes into the outer ring lane, and a 3-lane
entry on a 4-lane ring put 2 lanes into o2. Exits were capped at 2 ring lanes.

R = ring lanes, E = exit lanes, N = entry lanes at the node (lane 1 = kerb side, o1 = outer).
Ring-level: `turbo` = the ring is fresh (every junction built/changed by this build), has no skipped
node, and every node with exits has min(E, R) >= 2.
1. **Circulate**: `o_in[i] -> o_out[i]` for every ring lane, except `o1` at an exit node in turbo mode
   (exit only). No ring lane moves to another ring lane.
2. **Exit**: `o_i -> x_i` for i <= X = min(E, R); if E > R the innermost ring lane fans out over the
   rest (`o_R -> x_R..x_E`, a split, not a merge).
3. **Enter**: `e_j -> o_min(j, R)`: one to one; only an arm wider than the ring merges, its extra
   far-side lanes into the innermost ring lane (N - R + 1 lanes into o_R, unavoidable).
4. Tram connections are kept as the engine made them; the node is written only when the result differs.
5. **Ramp entry** (2026-10-11, user's hand edit at Roundabout Interchange node 63772; TESTING.md V): at an
   entry-only junction of a ramp (one-way, no sidewalk) with N < R lanes, `e_j -> o_out[j]` and
   `o_in[i] -> o_out[max(i, N + 1)]` (the ramp keeps its own lane, the circulating lanes zip inwards), when the
   next junction downstream has an exit of >= 2 lanes and reachability holds; variants two_lane / turbo only.

The only remaining "merge" at a node is the roundabout's give-way: entry lane j joins ring lane j,
which also carries circulating traffic (inherent to every roundabout).

Tests (`test_rules.lua` "no merges" and "Merges" section): per node, entry lanes feed min(N, R)
distinct ring lanes with at most N - R + 1 lanes into one, every exit lane is fed by exactly one ring
lane, no two ring lanes merge; for every ring/arm/direction, plus a ring without exits (4- and 2-lane
one-way stems) and 3-lane arms on a 4-lane ring.

### Reachability and lane changes
With lanes matched one to one, a vehicle that entered in ring lane 2 can leave at a 1-lane exit only by
changing lanes between junctions. The engine's own default relies on the same thing (on a 4-lane ring
it feeds entry lane 2 into o3/o4, which never exit through node connections: test "engine default ...
dead lanes"), so lane changes on segments are assumed; `Rules.reachability(..., laneChange = true)`
models them and the generated-ring tests check every entry reaches every exit that way. Uniform rings
(every arm as wide as its entries) also pass with node connections only. Verify in game: TESTING.md
traffic step.

Exit-only outer lane: only when every exit has >= 2 lanes, so a vehicle in o1 always has a kerb exit
lane at the next arm; otherwise o1 exits or continues.

### Example sets (CCW, right-hand traffic)
| Ring, arms | o1 (outer) | o2 | o3 | o4 | entries |
|---|---|---|---|---|---|
| 2-lane, medium (E = N = 2), turbo | x1 only | x2 or straight | | | e1->o1, e2->o2 |
| 2-lane, small (E = N = 1) | x1 or straight | straight | | | e1->o1 |
| 4-lane, medium, turbo (probe 22768: 10 -> 7) | x1 only | x2 or straight | straight | straight | e1->o1, e2->o2 |
| 4-lane, large (E = N = 3), turbo | x1 only | x2 or straight | x3 or straight | straight | e1..e3 -> o1..o3 |
| 2-lane, large arms | x1 or x1 only | x2, x3 or straight | | | e1->o1, e2 and e3 -> o2 |
| 4-lane, 4-lane one-way stem in, no exits | straight | straight | straight | straight | e1..e4 -> o1..o4 |

### Only nodes the player just built
- Jobs come only from player builds with added segments; the job's nodes are the seeds.
- A ring is planned when a seed lies on it. Only seed nodes are written; other junctions of the same
  ring keep what they have (engine default or the player's Crossing Tool edits).
- If not every junction of the ring is a seed (an arm added to an existing ring), turbo is off for that
  plan (the safe rule is reachability-safe next to engine-default nodes).
- Junctions elsewhere are never read or written.

## Save safety
- `severityAdd: None`: subscription happens lazily in `update`; nothing runs until the player builds.
- `severityRemove: None`: see Decisions. The state `{seq, jobs}` holds at most 3 jobs of at most 160
  node ids for ~300 engine updates after a build, normally `{seq = n, jobs = {}}`.
- Read-only except the lane writes; no global overrides, no modifiers, no `runFn`.
- Map editor: inactive.

## Logging (`[SQRL]`, stdout.txt)
`APPLY ring node lanes dir exits entries turbo fresh before after` (one per written node),
`SKIP ring node reason` (ring nodes left alone, or a node whose entry could not be built),
`WRITE ring nodes success` (callback), `VERIFY ring same nodes` (re-read 30 GUI frames later),
`ERROR where err` (at most 20 per session).
`SUMMARY job nodes rings ring=applied/same/skipped slip cross drop same skip skips=reason:count,...` (PHASE7.md
step 6): one per processed automatic job that met a ring or a slip / crossing / drop candidate (TESTING.md Q).
`AUDIT node case shape findings=kind:n,... [forced=..] detail src=auto|tool|pick [job | scope | ring]` (sl_audit.lua,
TESTING.md X, 2026-10-11): one per junction with avoidable findings (squeeze, shared, across, ramp_ramp, u_turn,
unfed, dead, bypassed_turn, weave, lights, bad), after the automatic job's / the tool's proposals were sent, or on a
pick (current connections), at most 40 per automatic job; `AUDIT_SUMMARY src=auto job audited flagged findings
forced [failed] [unlogged] skips` after each automatic job's SUMMARY (unlogged: flagged over the line cap); the
tool's PICK lines gain `findings=`. Always on (quiet junctions log nothing; no extra config reads in
the automatic pass), not tied to "Debug: performance log". `make audit` (tools/sqrl_audit.py) reports them.

## Phases
### Phase 1: automatic roundabouts (done offline, needs the in-game test)
Files: `content/smart_lanes/sl_ring.lua`, `sl_rules.lua` (pure), `sl_lanes.script.lua`,
`sl_lanes.gs.lua`; tests `test_rules.lua` (55 checks incl. probe fixtures), `test_script.lua`
(wiring with a fake api). Open questions for the game (TESTING.md): does the write succeed and stick,
does the Crossing Tool show it, do the painted arrows update, do vehicles change lanes between
junctions, does anything get stuck, does the engine regenerate our nodes when a neighbour is rebuilt.

### Phase 2: road tool for roundabouts (and later any junction)
User request 2026-10-08: a tool in the road tools bar, right after the vanilla Crossing Tool. Click a
junction or a whole roundabout, see its lane connections, choose a layout, Apply, Reset to the game
default. Roundabouts (one-way ring junctions) first; ordinary crossroads later.

**Steps**
1. **Skeleton + probes (implemented 2026-10-08, needs the in-game test, TESTING.md "Phase 2 step 1").**
   Tool shell with text buttons, hover / pick with node promotion, NodeViewer overlay, Apply through the
   shared Phase 1 write path, Reset with the remove-only probe and a fallback, status chip, offline tests.
2. **Apply / Reset final**: settle Reset from the probe results (keep remove-only, or always write the
   model / a snapshot), per-node undo story, results in findings.md.
3. **Layouts**: ordinary junctions (turn lanes by angle, below), maybe more ring variants.
4. **Polish**: own icon, hover-only overlay of the hovered junction, gamepad, texts, gallery slides.

**Files (step 1)**
| file | role |
|---|---|
| `content/smart_lanes/sl_tool.res.lua` | `construction_tool` resource -> `sl_tool.script@getDefinition` |
| `content/smart_lanes/sl_tool.script.lua` | definition (toolbar params) + `SmartLanesAction` recipe (world layer) + `SmartLanesStatus` chip; thin UI over the core |
| `content/smart_lanes/sl_toolcore.lua` | controller: resolve / hover / select, apply, reset probe + fallback, frame-timed re-reads, overlay data; takes the api as a parameter (tests: `test_tool.lua`) |
| `content/smart_lanes/sl_write.lua` | the GUI-thread read / write path, extracted from the Phase 1 script and shared by both (live world, current connections, LaneConnection strategies, `sendConfigs`, `sendRemoveOnly`, `verify`) |
| `content/smart_lanes/sl_pick.lua` | pure: edge -> node promotion, colours per outgoing segment, status texts, log rate limit (tests: `test_layouts.lua`) |
| `sl_rules.lua` | + layouts `matched` / `turbo`, `ringPlan` reason, `defaultConns`, `resetDecision` |
| `sl_ring.lua` | + `ringThrough(world, n)` (the Phase 1 ring test, shared) |

**Architecture**
- The menu loads every `construction_tool` generic resource, mods included
  (`.cache/game/base/content/gui/construction/construction_react_util.tl:2813-2840`). The Crossing Tool
  is `base/content/gui/construction/tools/lane_modifier_tool.res.lua` + `.script.tl:4-50`, category
  `roads_tools`, order 1200; the other road tools: tram 100, bus lane 200 (year-gated), crosswalk 300,
  player owned 1000, traffic light 1100 (year-gated). Ours: order **1250**, `yearFrom/yearTo = 0`.
  Caveat (`plans/square_bulk_bulldozer/research.md:18`, `construction.tl:758-760, 427, 315-328`):
  `isActionActive(listIndex)` compares the selected definition index with the visible list position;
  while a year-gated entry before ours is hidden they differ. In mouse mode `abortAction` then does
  nothing; gamepad mode may break. Logged as `TOOL activated=n order=1250`; verify in game.
- `getDefinition` returns `ACTION_CUSTOM` + `customAction = {recipe = SmartLanesAction}`, the shape of
  `mods/square_bulk_bulldozer/content/bulk_bulldozer/bulk_bulldozer.script.tl:1310-1331`. Lua, not
  Teal: a `.script.lua` tool exporting through `data()` is how `.cache/subscribed/parallel_tracks_1/
  content/gui/construction/tools/parallel_tracks_tool.script.lua` does it, and this mod is Lua.
  Toolbar: Layout (Button, 3 values, 1-based indices without `numbers`:
  `base/content/gui/main/script_param_util.tl` `getValueOfIndex1`), [Apply to junction] [Apply to
  roundabout] [Reset] (one `group`, one-value Buttons, labels in a BoxLayout via `makeCompactButtonFn`),
  and a disabled Button whose content is the self-updating status recipe (returns a BoxLayout).
  Values reach the recipe through `onChangeFn` -> `api.gui.fireReactEvent` -> `react.onEvent`, and
  the status chip's `checkEnabledFn(params)` (bulk bulldozer: `getCurrentParams()` returned `{}`).
- World layer (`param.setActionFn`): `builtin.ActionDescriptor{ highlightedEntities, onBack, children }`
  with a `builtin.Selector` (`base/tealdef/scripts/builtin.d.tl:1392-1415`: `onSelect(entity, indices,
  details) -> boolean`, `onHover`, `filter`, `onProcessMouseEvent`, `selectionColor*`), a
  `builtin.NodeViewer` (`builtin.d.tl:1475-1479`), one `builtin.EdgeRenderable` with circle markers
  (one per recipe: the engine asserts on more) and a `builtin.ActionTooltip` (SimpleTooltipRecipe).
- **Picking is move_it's** (`.cache/subscribed/move_it/content/tools/move_it/move_it.script.tl:4513-4560`):
  node hit boxes are tiny, the Selector mostly reports the adjacent street edge; an edge hit with the
  cursor (`api.gui.mouse.getTerrainPosition()`, `api/tealdef/api/gui.d.tl:260-264`) within
  `min(15 m, length / 3)` of an end becomes that end node. Our addition: the middle of a ring segment
  selects the whole roundabout. Node centre / z from `BASE_NODE.position`.
- **Correction to the earlier plan**: bulk bulldozer's Selector only swallows clicks (`onSelect` returns
  true, `bulk_bulldozer.script.tl:1017-1020`); it does not pick nodes. Its useful parts here are the
  tool shell, the right-click handling (`:907-934`: only `PressedOutside` and `Clicked` of button 2
  reach the Selector; a click moved > 16 px is a camera drag) and the status chip.
- **Showing connections**: `builtin.NodeViewer{ nodeConfig = { [node] = {NodeViewerData...} } }` as in
  `base/content/gui/entity_window/double_slip_switch.tl:87-143, 185-199`; `api.type.NodeViewerData`
  (`api/tealdef/api/type.d.tl:4246-4258`: `edgeIdx, colors, order, width`); indices
  `0..#laneConnections-1` are the lane connections in config order, then crosswalks. One colour per
  outgoing segment (`sl_pick.colorIndices`). It shows the applied config only (no preview). Built in a
  pcall, logged once per selection as `PROBE nodeviewer ok=..`. Alternative highlight if needed:
  `api.gui.mission.setZone / setZoneCircle / removeZone` (`api/tealdef/api/gui.d.tl:702-720`; mission
  API, keyed zones).
- **Writes** run on the GUI thread (the menu recipe), through `sl_write.sendConfigs` (the Phase 1
  proposal: `nodeConfigsToRemove` + `nodeConfigsToAdd`, cost 0, one build per click). Our builds have
  no added segments, so the Phase 1 game script ignores them. A re-read 30 frames after the callback
  logs `VERIFY src=tool`.

**Layouts** (`sl_rules`, toolbar values 1..3)
| layout | what | how |
|---|---|---|
| Matched lanes | lanes 1:1 (Phase 1 rule), the outer ring lane may always continue | `planRing(..., "matched")`: turbo forced off |
| Turbo | Matched lanes + exit-only outer lane wherever the ring qualifies: every exit has >= 2 lanes, no skipped junction, >= 2 ring lanes. Applies to a single junction too (freshness ignored); otherwise = Matched lanes, the result says why (`turbo_reason` one_lane_ring / skip_node / no_exit / narrow_exit) | `planRing(..., "turbo")` = `ringPlan(fresh = true)` |
| Game default | the engine's own connections | Apply runs the Reset path |
The automatic Phase 1 rule stays `two_lane` (turbo only on a fresh ring), unchanged.

**Reset** (no API for "regenerate the default"; research: `api.engine.util.proposal.replaceSegment(edge)`,
`api/tealdef/api/engine/util.d.tl:987-991`, would rebuild streets, not tried). Step 1 probes:
1. send a proposal with only `nodeConfigsToRemove = {nodes}` (no add) and log `RESET mode=remove_only_sent`;
2. ~30 frames after the callback, re-read each node: `RESET mode=remove_only node conns_before conns_after
   default_model same decision reason` (`Rules.resetDecision`): regenerated -> keep; left empty or
   unchanged (and not already the default) -> write `Rules.defaultConns` (engine-default model + the
   node's tram connections; model verified for 1-2 entry lanes on 2- and 4-lane rings) =
   `RESET mode=fallback_model`; a node off a ring left empty -> write its old connections back
   (`fallback_restore`). A refused probe is judged at once; closing the tool judges pending resets at
   once, so no junction stays without connections.
Open: whether the engine regenerates (then remove-only is the real reset), and whether an emptied
node blocks traffic for the 30 frames.

**Turn-lane rule by angle** (later step, any junction not on a one-way ring): for each incoming segment,
sort the other segments by the signed turn angle (right turn negative for right-hand traffic); split
the incoming road lanes kerb-first: rightmost lane(s) -> right turns, leftmost -> left turns, middle ->
straight; with fewer lanes than movements, the kerb lane shares right+straight and the median lane
left+straight; each movement maps lanes 1:1 onto the target's lanes kerb-first (fold extras into the
inner lane). U-turns never. Tram connections kept. Pure function of the node view + angles, tested
like Phase 1.

**Other options considered** (2026-10-08): an entity-window button on the node's "Crossing" window
(`gui/entity_window/make_entity_window.tl:644-663`) has no extension hook (monkey-patching only);
mods cannot register new hotkeys; there is no "entity selected" GUI event to hook.

**Log lines (tool)**: `TOOL activated|closed|layout|cleared`, `PROBE hover entity kind=node|edge promoted d r
target` (on a change of target, at most every 0.3 s), `PROBE nodeviewer ok target nodes edges | error`,
`PICK target ring lanes arms node_kind conns`, `APPLY src=tool layout ... turbo turbo_reason before after`,
`SKIP src=tool`, `WRITE src=tool|reset`, `VERIFY src=tool|reset`, `RESET ...` (above), `ERROR where err`.

### Phase 3: polish and publish
In-game round from TESTING.md, findings.md entry for whatever it shows, maybe a "Re-apply to this
roundabout" path through the Phase 2 tool (covers old roundabouts), gallery slides (`make shots`),
Crossing Tool screenshot before/after, upload.

## Phase 2 step 1 in-game results (2026-10-08)
- Tool appears after the Crossing Tool and works; picking nodes, edge promotion and ring picking work
  (PROBE hover lines); NodeViewer draws on arm junctions and whole rings.
- Crash 1: NodeViewer `edgeIdx` out of range on a plain 2-segment ring node (2 connections, 1 network
  edge). Fix: draw a node only when `#TRANSPORT_NETWORK.edges >= #laneConnections`, nothing while a
  write is pending (findings.md).
- Crash 2: the remove-only Reset probe deletes the node config; the simulation crashed 13 s later.
  Reset now = Apply with the engine-default model ("engine" variant in sl_rules.planRing), a full
  config write. Off a ring there is no model, so Reset does nothing there (message). Remove-only code
  is gone from sl_write/sl_toolcore (findings.md).
- Icon: needs its own (in progress).

## Simplified (2026-10-08, user)
- One layout only: the tool's Apply always sets "Smart lanes" (sl_rules variant "turbo": matched
  lanes plus the exit-only outer lane where every exit on the ring has >= 2 lanes, else plain
  matched). The layout row (Matched / Turbo / Game default) is gone; Reset is the game default.
- Mod setting "Roundabout lanes" removed; "Apply automatically" On/Off is the only setting (the
  automatic rule stays "two_lane": exit-only only when the whole ring was just built).
- Toolbar rows: [Apply to junction | Apply to roundabout], [Reset], status chip (three buttons in one
  row clipped their labels).

## Phase 4: slip-lane junctions (2026-10-08, implemented offline, needs the in-game test)
User report: on a Channelized Junction (T, town main road, near-side slip lanes) the node where a
slip lane leaves or joins the main road has the engine default (every incoming lane fans out over
several outgoing lanes, crossing each other). Hand-edited with the Crossing Tool towards "lanes
matched one to one, no crossing". The tool said "Not a roundabout junction: not handled yet" and
the automatic pass ignored it. In-game checks: TESTING.md "G. Slip-lane junctions".

**Files**: `content/smart_lanes/sl_slip.lua` (pure: classification, rule, plan, log fields; header
comment is the spec), wired into `sl_lanes.script.lua` (`processSlips`; since 2026-10-12 `slipStep`) and `sl_toolcore.lua`
(`applySlip`), status texts in `sl_pick.lua`. Tests: `test_slip.lua` (rule tables, invariants for
every lane count 1-4, worlds: Channelized T for 3 main x 3 side x 3 slip templates x 4 slip angles
x both traffic sides, two-way and one-way mains with 1-3 lanes, 1- and 2-lane branches, diverge and
merge, far-side branch, crossroads, Y fork, 5 roads, bus lane, tram), `test_script.lua` (automatic
pass on a placed Channelized T, ring + slip in one build, untouched nodes), `test_tool.lua` (pick,
Apply, Apply to roundabout message, Reset snapshot / unavailable). Fixture `F.channelT` mirrors
`square_roundabouts_channel.lua` `ch.build` (layout T, near-side slips: nodes 1 centre, 2 east
diverge, 3 west merge, 4 north merge + diverge; slip edges as `ch.slipEdge`). The real `ch.build`
cannot be loaded from this mod's tests (the harness's `ug_require` only resolves the mod under test).

### Classification (`Slip.classify`)
Road segments only (CAR / BUS / TRUCK lanes); tram-only tracks ignored. Turn angles from the
tangents at the node (left turn positive, the ring code's convention).
| case | segments | streams |
|---|---|---|
| A | 3 one-way | 1 in + 2 out = diverge, 2 in + 1 out = merge; through = smaller turn (<= 45 deg), branch the other (>= 5 deg apart, else `ambiguous`) |
| B | 2 two-way (the main road, <= 45 deg off straight) + 1 or 2 one-way branches | each branch belongs to the direction it turns least from (< 90 deg); one branch per direction; the other direction is a straight stream |
| none | < 3 road segments, no one-way segment (crossroads, T of two-way roads), one two-way + one-way roads (roundabout splitter's split node) | not logged |
| skip | 5+ roads, bus lane, ambiguous, no through road, main road bends, branch on the far side, mixed driving sides | `SKIP kind=slip reason=..` |
The 4-segment case B is the Channelized T's side-road node (slip from the east joins northbound,
slip to the west leaves southbound): each direction is handled on its own.

**Kerb side**: case B from the two-way lane layout: connection indices run left to right looking
from the node, so right-hand traffic has a two-way segment's incoming lanes on the lower indices
(probe: arm 18164 at node 17955 incoming {1}, outgoing {2}); left-hand traffic the reverse. The base
game decides the same way (`trafficlightutil.lua` `leftHandTraffic`, from lane positions). Both main
segments must agree. A branch on the far side (crossing oncoming traffic) is not a slip lane: skip.
Case A (all one-way, e.g. a highway gore): nothing tells the driving side, so the kerb side is the
branch's side (a left exit gets the mirrored rule, which is what avoids crossings).
**Unverified in game**: that a left-hand-traffic save reports mirrored `laneConfigs` (the tests
assume it, as the ring tests do).

### The rule (lanes kerb first; m main in, t through out, b branch out, p through in, q branch in, o out)
- straight: 1:1 aligned from the far (median) side; extra kerb lanes fan out of / fold into the kerb lane.
- diverge (N in, T through, B branch): f = max(1, N - T + 1), k = min(B, N, f). m_1..m_k -> b_1..b_k,
  extra branch lanes from m_k; m_f..m_N -> through aligned from the far side; N < T: extra kerb
  through lanes from m_1; lanes m_(k+1)..m_(f-1) (only when B < N - T) fold into t_1.
  N <= T: only m_1 feeds the branch and it also goes straight (through keeps every lane).
  N > T: m_1..m_(f-1) are branch-only, m_f is an option lane (branch or straight) when B >= f.
- merge (T through in, B branch in, O out): through 1:1 aligned from the far side (extra kerb
  through lanes fold into o_1); q_i -> o_min(i, c), c = max(1, O - T + 1): T + B <= O nobody shares,
  else the branch shares the kerb lane(s) with through traffic (give-way merge); outgoing lanes
  between are fed by the nearer side.
- No U-turns; every incoming road lane connected, every outgoing road lane fed, no two connections
  of one direction cross (`test_slip.lua` checks all three for every count 1-4 and on every world).
- Deviation from the request: "kerb lanes feed the branch 1:1 (min(B, N))" and "if N <= T the kerb
  lane also continues straight" cannot both hold without a crossing when B >= 2 and N >= 2
  (m_1 -> t_1 crosses m_2 -> b_2). No crossing and no lost through lane win: with N <= T only the
  kerb lane feeds the branch (fanning into all its lanes). The Channelized Junction's 2-lane slip
  lanes on a 2-lane main road are this case.

**2-lane main road (per direction), 1-lane slip**
| diverge 2 -> 2 + 1 | slip b1 | through t1 (kerb) | through t2 |
|---|---|---|---|
| m1 (kerb) | yes | yes | |
| m2 | | | yes |

| merge 2 + 1 -> 2 | out o1 (kerb) | out o2 |
|---|---|---|
| slip q1 | yes (gives way) | |
| through p1 (kerb) | yes | |
| through p2 | | yes |

Other examples: diverge 2 -> 2 + 2 slip (Channelized, medium main): m1 -> b1, b2, t1; m2 -> t2.
Diverge 3 -> 2 + 2 (road narrows): m1 -> b1; m2 -> b2, t1 (option lane); m3 -> t2. Merge 2 + 1 -> 3
(lane gain): q1 -> o1, p1 -> o2, p2 -> o3. Merge 2 + 2 -> 2: q1, q2, p1 -> o1; p2 -> o2.
Exact indices on the Channelized T east node (medium main, xsmall slip):
`12:1>21:2, 12:1>21:1, 12:1>11:4, 12:2>11:3, 11:1>12:4, 11:2>12:3` (`test_slip.lua`).

### Engine default, U-turns, Reset
- The engine default at a slip node is not modelled: the only engine data are ring arm nodes
  (probe log) and the user's description ("fans out, crossing"). No probe line of a slip node exists.
- U-turns: never added. The probe's ring arm nodes have no U-turn connections, so we assume the
  engine adds none at slip nodes either; any road connection the engine had is replaced (tram ones
  kept). Verify with the Crossing Tool (TESTING.md G).
- Tool Reset on a slip node: no model, so it writes back the connections the node had before the
  tool's first Apply on it in this session (snapshot in the tool's Lua state, a full config write,
  never remove-only). No snapshot (fresh session, or a node only the automatic pass changed):
  "Reset not available here (no Apply yet)", nothing written.

### Wiring
- Automatic: `processJob` runs the rings first, then every job node not on a ring through
  `Slip.plan`; all slip nodes of one build go in one proposal (`sendConfigs("slip_job", seq, ...)`).
  (2026-10-12, PERF_REVIEW.md: the job runs in steps over frames, one slip proposal per frame that built
  entries, still one WRITE / VERIFY line per job.)
  Same seed policy (only nodes the build added or changed). Logs: `APPLY kind=slip node shape case
  side lanes before after`, `SKIP kind=slip node reason` (candidates only), `WRITE kind=slip job
  nodes success`, `VERIFY kind=slip job same nodes`.
- Tool: a node off a ring that classifies as slip is selectable: chip "Slip-lane junction: diverge,
  2 lanes" / "2 -> 2 + 2 slip, 8 lane connections". Apply to junction applies the rule (`APPLY
  src=tool kind=slip ...`, `WRITE src=tool kind=slip node=..`, `VERIFY src=tool kind=slip node=..`);
  Apply to roundabout says "Not a roundabout: use Apply to junction"; Reset as above (`RESET
  mode=snapshot|unavailable kind=slip node=..`). NodeViewer guard unchanged.

## Lane status badge (2026-10-08, implemented offline, needs the in-game test)
User request: show at a glance what lanes the selected (or hovered) junction / roundabout has now.
TESTING.md "H. Lane status badge".
- **States** (`sl_pick.badge`, pure; input from `sl_toolcore` `C.badgeInfo`): road connections only
  (`Rules.roadText`: `connsText` of the `withRoad` connections without tram flags, as mergeTram keeps
  tram alone).
  | badge (log key) | when |
  |---|---|
  | Smart lanes (`smart`, green) | every handled junction equals `planRing(..., "turbo")` (what Apply writes); slip node: `Slip.plan` conns. "(= game default)" when it is the engine model too (1-lane ring, one entry lane) |
  | Game default (`default`, neutral) | every handled junction equals `planRing(..., "engine")` (Reset's model); never on slip nodes (no model) |
  | Smart lanes on k of n junctions (`partial`, amber) | whole ring selected, some but not all smart |
  | Custom lanes (`custom`, amber) | anything else on a ring (Crossing Tool, older settings, the automatic rule's matched lanes on a ring that qualifies for exit-only) |
  | Custom (`custom`, neutral) | slip node that differs from the rule (probably the engine default; unknown) |
  | Not handled (`na`) | crossroads / T / plain nodes, ring junctions the rules skip, a ring with only skipped junctions |
  Skipped ring junctions are not counted. "Lane status" with nothing selected.
- **When**: computed in `nodeTarget` / `ringTarget`, so on every resolve: selection, hover (key
  change or every REFRESH_FRAMES), the periodic re-read (REFRESH_FRAMES) and after each VERIFY.
  Cached per ring (`ring:<key>`) / slip node by ring segments + every ring node's `roadText`;
  the two planRing passes run only on a change (`C.badgeStats`). Offline cost on the 4-lane probe
  ring (lupa, Lua 5.4): ~0.5 ms per uncached refresh, ~0.4 ms cached (most of it the ring search).
- **UI**: a second disabled one-value Button (`sqrl_tool_badge`, own `group`, under the status chip),
  content `SmartLanesBadge` (BoxLayout + TextView, `tooltipWhenClipped`, self-updating from `g.badge`
  / `SmartLanes.badge`). Colour via the game's global TextView classes `positive` / `warning`
  (`base/content/gui/main/default.css.lua:12-22`, used as `"font-scale-body, positive"` in
  `line_react_util.tl:630`). Unverified: `builtin.css.lua:268-275` greys TextViews inside disabled
  buttons, which may win over the class (then the badge is grey; fallback: an enabled no-op button
  or a mod stylesheet rule). Also the 3rd cursor tooltip line "Lanes: ..." and `PICK ... badge=..`.

## Free kerb turn at traffic lights (rev 4, 2026-10-12, implemented offline, needs the in-game test: TESTING.md FK)
User request: at signalised junctions Smart Lanes writes, the kerb turn (right in right-hand traffic) goes in every
phase, so kerb turners never wait for their approach's green. Setting `sqrl_free_turn` "Free kerb turn at traffic
lights" (Rules.KEYS.freeTurn; first On / Off, now Off / When safe / Always: see "Revised 2026-10-12" below;
the notes up to there describe FREE, which is "Always" now).

- Pure helpers (sl_lights.lua): `L.kerbIndices(conns, kerb)` (0-based indices of road, non-tram connections whose
  `seg0>seg1` is a kerb pair), `L.kerbPhases(conns, kerbIdx, nCross, lists, mode)`: FREE removes the kerb indices
  from every phase; LOCK (the tool's Reset) adds a kerb index where every other road connection of its approach
  (segment0) is red, which reproduces the game's default (kerb turn red with its approach; unit test: Reset gives
  the original phases back exactly). Refuses input with an index outside `[0, #conns + nCross - 1]` (stale phases)
  and changes nothing else: crosswalks stay, no phase is added or removed, empty phases stay.
- Kerb pairs from the case X view (`X.kerbPairs`, via `S.kerbPairs`): exits of category "kerb" over `ap.allExits`
  (categories are already per driving side, so left-hand traffic needs no extra mirroring). Bypassed turns (TESTING
  R) have no connection in the rule's list, so nothing is freed there; Reset's model has them and locks them.
- Write path (sl_write.lua): items may carry `phase = {mode, kerb}`; `W.remapLights` applies `kerbPhases` to the
  re-pointed lists before building the TrafficLightState objects and checks the read-back range as before. One
  proposal for lanes and phases. `W.kerbLights` is the phases-only path for nodes whose lanes are already right:
  fresh read, a standing light required, `createTrafficLightProposal(node, clone, current preference)` (the base
  phase editor's commit), LIGHTS line with `user_modified=` (probe for the open question below).
- Automatic pass: case X apply items get the FREE phase (setting On); same nodes get `W.kerbLights` unless a slip
  proposal naming the node is unanswered or a pending job lists it (`busyNode`). Nodes whose light state was unknown
  at the read (`Lights.litOf` nil: AUTO, no light yet) are re-checked 60 and 600 frames after the write answered
  (`RECHECK`): lanes still ours and a kerb connection red -> `W.kerbLights` (src=recheck). Covers AUTO lights that
  appear after our read; lights later than ~10 s are a documented gap (TESTING FK 3).
- Tool: Apply (node, street, multi) frees with the setting On; Reset always locks back; same lanes -> phases-only,
  with the tool's buttons held (`C.phaseHold`) until that proposal answered + VERIFY_DELAY frames.
- Never two proposals on one node at once: crossroads keep their lights (no LIGHTS off proposal for them), the
  phases-only proposal only goes to nodes not in a lane proposal (findings.md "pending change" refusal; a light
  proposal built before a lane write lands would carry phases for the old connections).
- No audit finding: the audit is about lane connections; phases are logged on SUMMARY / WRITE / LIGHTS / RECHECK.

### Revised 2026-10-12: Off / When safe / Always (user decision)
Freed turners do not give way (findings.md "A connection unlocked in a phase does not give way"), so FREE in every
phase drove kerb turners into green traffic. The setting now has three values (`Rules.VALUES.freeTurn` =
"off" / "safe" / "always", default "safe" (now "always": see "Revised 2026-10-12: default Always" below); mod.json
values Off / When safe / Always, `defaultIndex` 1 (now 2);
`Lights.modeFor` gives nil / `L.SAFE` / `L.FREE`). Off makes no phase change from this feature at all.

Conflict model of `L.SAFE` (`L.kerbConflict`), per phase p and kerb connection k = A -> E, exit lane l; "green" =
not in p's lockedLanes, including kerb connections freed earlier in the same phase:
- merge: a green connection of another approach (segment0 ~= A), road or tram, ends on E in lane l.
- cross: a green connection of another approach ends on E in a lane nearer the kerb than l. Reason: the game draws
  one lane curve from the approach lane to the exit lane; a kerb turner enters E from the kerb side, so it cuts every
  stream ending kerbward of l and runs beside the streams ending farther out (no conflict, so a far-aligned left turn
  into the far lane does not block it). Lane positions come from sl_cross `ex.o` (exit lanes kerb first), carried as
  the value of `X.kerbPairs` (true when unknown: then every other green lane of E counts). No other paths reach the
  kerb corner between A and E: the other movements stay on the far side of the junction, U-turns (> 135 deg) are no
  exits, and a game-made connection that ends on E falls under the lane rule anyway.
- A's own connections never conflict (A's phase logic; the kerb turn is green with A in the game's default, and
  sl_cross gives each lane of A a contiguous exit range, so they do not cross). Pedestrians are still checked there
  (more conservative than "simply unlock", only differs for hand-edited phases).
- ped: `BaseNodeConfig.crosswalks : {Entity}` (api/tealdef/api/engine.d.tl:190); read as the edges whose end at the
  node has a crosswalk (inferred, not verified: a 3-way game node had 3 crosswalks and a dead end 1, findings.md;
  community mods re-point them by edge id: move_it_probe_overpass `overpass_probe.script.tl:1589-1598`). A green
  crosswalk on A or E keeps k red; on another road of the node it does not; an entity that is none of the node's
  segments (or no list) blocks every kerb turn (conservative). In-game probe: TESTING FK 1e.
Everything else as before: same `stale_phases` refusal, relock-then-free in `W.remapLights`, crosswalk indices
untouched, no phase added or removed, LOCK (Reset) unchanged. Stats per (kerb connection, phase): `free_phases=`
(unlocks), `kept=merge:n,cross:n,ped:n` (first kind found) on SUMMARY, tool WRITE and LIGHTS lines. The re-check
uses the stored mode (When safe re-checks send nothing when the remaining reds are conflicts).
Review 2026-10-12: (a) "cross" is one-sided, so with two kerb turns into one exit (5-way or skewed nodes) the
order of the connections could free both across each other; a kerb connection is now freed only if the ones freed
before it in that phase still pass with it green (unit test "two kerb turns into one exit"). (b) The phases-only path
(`W.kerbLights`, tool Apply on unchanged lanes, auto `same`, re-check) now also locks back first for When safe
(`Lights.kerbDiff` counts the net change), so a turn freed earlier by Always no longer stays green into traffic.
(c) Param values: the released rev 3 has no `sqrl_free_turn`, so no player has a stored value; only a dev save/settings
that stored the unreleased On / Off value 2 (Off) now reads as When safe (index 2). No migration needed.
Expected effect: with the game's two-phase default at a 2x2 crossroads every kerb turn merges with the cross road's
green straight, so When safe frees nothing there; it helps with per-approach phases, a side road's phase at a T
(the main road's kerb turn), and exits where the green stream ends in lanes farther out.

Open (TESTING FK): (1) answered: freed turners do not give way (findings.md 2026-10-12), hence When safe; open:
whether When safe ever frees a turn into conflicting traffic, and what crosswalk entities are (FK 1e); (2) whether the game re-makes phases on its own later (nearby builds, edge
upgrades) and whether `userModifiedTrafficLightStates` protects ours; Smart Lanes keeps the flag as read (setting
it could make the engine keep phases for connections it re-makes, i.e. stale indices); (3) how late AUTO lights can
appear.

### Revised 2026-10-12 (later): When safe allows merges (user decision)
In game (Lights showcase seed 530609, findings roads.md "A connection unlocked in a phase does not give way", "Later
observations") freed kerb turners merged into a green stream entering the same exit lane tolerably, and the user
judged that more efficient than holding the turn red; pedestrians were avoided only mostly. So `L.SAFE` now keeps a
kerb turn red only for **cross** (a green stream of another approach ending kerbward of its exit lane) and **ped**
(a green crosswalk on A or E); a **merge** (a green stream ending in its own exit lane) no longer blocks.
`L.kerbConflict` still classifies (merge before cross before ped, the map agreement test uses it); `kerbPhases` uses
`blockOf` (cross before ped, merges reported apart). Stats: `kept=` never has `merge:` now; `merged` = (kerb
connection, phase) pairs freed while a green stream ends in the same lane, logged as `merge_free=<n>` after `kept=`
on SUMMARY, tool WRITE and LIGHTS lines (named merge_free because SUMMARY already has `merged=<seq>` for merged jobs).
Two kerb turns into one lane (5-way / skewed nodes) are a merge too and may both go; a crossing pair still never.
In-game node 381095 (Lights showcase, PROBE phases 2026-10-12): phase 1 locked the south right turn D1>A4 although
only C2>A4 (a green straight) ends in A4: now freed (unit test in test_lights.lua, both traffic sides).

Planner (Light phases = Smart Lanes, sl_phaseplan.lua) decision: **consistent, kerb turns may merge there too**. Step
4b, after the strict steps 2-4 (seeds, maximal phases, crosswalks): every kerb-class connection joins every phase
where its only conflicts with green entries are merges (`opts.kerbMerge`, default true; fan plans excluded). Done on
top of the strict plan, so no straight or crosswalk loses a phase to a merging kerb turn and the plan's structure is
unchanged (weights come from the seeds; the calibrated T's cycle drops 85 -> 83 s as its turn phase needs less).
The plan lists the kerb turns (`plan.kerb`); `PP.validatePlan` accepts a merge with one of them or with a class
"kerb" connection of `M.cls` (a plan read back from a config), never a crossing or a crosswalk conflict, and refuses a
listed connection whose class is known and not kerb. So "the plan subsumes When safe" holds again, and Light phases'
tooltip says kerb turns also go where they only merge.

### Revised 2026-10-12: default Always (user decision)
"Free kerb turn at traffic lights" now defaults to **Always** (mod.json `defaultIndex` 2, `Rules.DEFAULTS.freeTurn` 3;
an index out of range or not an integer also reads as Always). When safe and Off stay as choices. With Always the
SUMMARY / tool WRITE lines carry no `kept=` / `merge_free=` (those are When safe only) and the MODE line says
`free_turn=always`. Tests: test_rules "mod params" / "mod.json params", the default `{}` runs in the Always tests
(test_script "free turn: a lit crossroads ...", test_tool "free turn (tool): Apply frees ..."). Fallback if Always
jams in game: TESTING.md FK "If it fails".


## Exit-lane fan (sl_exitfan zones, 2026-10-13; a measuring mode, never a default)
Request (2026-10-13): a read-only lane audit of Stress Test session `2026-10-13_0205_top-up-61157` found Smart Lanes
twins ~1.9 km/h slower than game twins at lit 2x2 crossroads (6/6 sets), queues on the arms where turners leave. Smart
Lanes pins each turn to one exit lane (kerb turn into the exit's kerb lane, far turn into its far lane: `ks|sf`, 16
connections); the game lets each turn enter every exit lane (24; PROBE phases_conns node=5921, session
`2026-10-12_0753_sqot-dev-sqrl`). Hypothesis: turners can't pick their downstream lane, so they change lanes after
the junction. The first plan made this the default and let the kerb lane of 3+ lanes go straight too (`ks|s|sf`).

Changed before release (coordinator, fuller evidence from session `2026-10-13_0356_top-up-779299`, 12.5 game min, 15
samples per twin, 12 pairs, not jammed): today's Smart Lanes layout BEATS game, 10/12 pairs faster, +3.2 km/h
(p = 0.039): 3x3 +8.0 km/h (3/3), T 2x2 +2.9 (3/3), 2x2 +0.9 (2/1), 3x2 +0.9 (2/1); the earlier 2x2 loss was likely the
rig's lane joins plus saturation. So **the default is unchanged** (the kerb-lane straight share is dropped entirely)
and the exit-lane fan lives only in a new zone mode, `sl_exitfan`, for a twin to measure (sl vs sl_exitfan).

Default paths unchanged, proven offline: the sl_cross code without the fan (the new blocks stripped, 1144 lines as
before the change) gave byte-identical connections and kerb sets as the new code outside a zone, with
`world.exitFan` false and inside a zone at unlit / unknown nodes, over 2790 world x lit cases (every T / X of 0-4 lanes
in, 0-3 out, one-way roads included, Channelized X centres, both traffic sides; one-off check, 2026-10-13). Permanent
tests: test_cross "exit fan off" (1728 cases) and every pre-existing test unchanged.

Zone contract (sl_zones.lua; for the Stress Test side): ab name `sl_exitfan`; `by_ab` adds `,sl_exitfan:<n>` after
`sl_lock` only when n > 0 (`game:a,sl:b,sl_phases:c[,sl_fan:d][,sl_lock:e][,sl_exitfan:f]`), older lines unchanged.

What the zone does (automatic pass and tool alike):
- Lanes: the rule's lane strings and straights as `sl` (X.allocate untouched); at a **lit** case-X node (X.litOf true)
  whose roads are all two-way and form the game's axis model (X.phaseGroups: a crossroads = two axes, approaches that
  are each other's straight exit; a T = one axis + the side road), every turn fans over the exit lanes its phase group
  leaves it (X.placeExitLit). Unlit, unknown or off the model: today's lanes, `exit_fan=unlit | lit_unknown | one_way |
  x_axes | t_axis | roads` on APPLY.
- Light phases: always the game's (re-pointed by W.remapLights), whatever "Light phases" says (as `sl_lock`; the fan is
  laid out for the game's axis phases). "Free kerb turn" is the setting's.
- Which movements share a phase and an exit (game's axis phases, measured: findings roads.md "Default traffic light
  phases"): in the N-S phase the W exit gets N's kerb turn and S's far turn (right-hand traffic), the E exit S's kerb
  turn and N's far turn, the N / S exits only the opposite straight. A T's main-road phase: one main approach's kerb
  turn and the other's far turn into the side road; the side road's phase: its turns alone. Straights never share a
  phase with a turn into the same exit.
- Layout per exit and phase group (X.placeExitLit): movements ordered kerb turn, straight, far turn; each gets a
  contiguous range, neighbours share exactly one boundary lane (a merge) and never cross (the kerb-side movement never
  ends farther out than the far-side one). Widths: first as many lanes as feeders (no fold where the road has room),
  the spare round robin from the kerb side, so the kerb turn gets the larger share. A lone movement takes every lane.
  Straights keep today's far-aligned lane-to-lane mapping (the exit's kerb lane stays free for a freed kerb turn).
  Why the kerb turn gets the shared lane: it does not cross the opposing straight, so it flows steadily in its green,
  and its kerb lane is the only one a freed kerb turn uses in other phases. The game fans both turns into every lane
  (they cross); a crossing pair in one phase never yields in TF3 (findings "A connection unlocked in a phase does not
  give way"), so the fan allows merges only, which the user judged tolerable (findings "Later observations").
  | shape | lane strings | kerb turn > exit lanes | far turn > exit lanes | connections (sl / fan / game) |
  |---|---|---|---|---|
  | 2x2 X | `ks|sf` | 1-2 | 2 | 16 / 20 / 24 |
  | 3x3 X | `k|s|sf` | 1-2 | 2-3 | 16 / 24 / 36 |
  | 3x2 X | main `k|s|sf`, side `ks|sf` | main into side 1-2, side into main 1-2 | main into side 2, side into main 2-3 | |
  | 2x2 T | main `ks|s` / `s|sf`, side `k|f` | main into side 1-2; side into main 1-2 | main into side 2; side into main 1-2 | |
- Free kerb turn (sl_lights): X.kerbPairs marks the set `kerbLaneOnly`; L.kerbPhases (FREE / SAFE) frees only kerb
  connections into the exit's kerb lane (position 1); the others (L.splitKerb "held") are locked as LOCK does, red
  where every non-kerb road connection of the approach is red, so a freed turn never enters lanes green traffic
  uses and a held one freed earlier is locked back. LOCK (Reset, sl_lock) unchanged. W.kerbLocked counts only the
  freeable ones. SAFE's conflict model (conflictInfo / blockOf) sees the fanned connections of other approaches as
  ever (merge in the same lane, cross kerbward).
- Re-checks: an sl_exitfan node whose light was unknown at its write gets a re-check entry (60 / 600 frames, also with
  Free kerb turn Off); once a light stands and its lanes are still the rule's, the fan goes out in one proposal with
  the kerb phase change (`APPLY src=recheck ... exit_fan=yes`, `WRITE kind=exit_fan`). Lights that appear later than
  600 frames (e.g. a save passing 1950) are not re-evaluated: a rebuild nearby or the tool's Apply does it (same gap as
  FK 3).
- Index safety: every lane write goes through W.remapLights (new fanned connections take their movement's state,
  Rules.remapper; checkStates range check), one proposal per node; test_script "an existing lit junction with today's
  lanes and freed phases re-applied" (16 -> 20 -> 16 connections, every index in range).
- Audit (sl_audit): with view.exitFan, lanes shared across phases and one boundary lane per neighbour pair of one phase
  are `shared_lit`; only shares within one phase beyond those count as `shared` (no false alarms: test_audit).
- Logs: APPLY `exit_fan=..` (+ `zone=sl_exitfan`), AUDIT `zone=sl_exitfan`, SUMMARY `zone_exitfan=<nodes> exit_fan=<fanned>`.
- Zones reach the worlds through `W.zones` (sl_write world.exitFan reads it at the call): the automatic pass sets it
  whenever its zones mirror changes (so a job sees the current zones, not only its start snapshot), the tool on each
  zone read. The tool's badge cache key includes the zone.
- Files: sl_cross.lua (X.exitFanOf, X.phaseGroups, placeExitLit / fanBlocks, roadConns branch, kerbPairs flag),
  sl_zones.lua, sl_write.lua (world.exitFan, W.zones, kerbLocked), sl_lights.lua (L.splitKerb, kerbPhases),
  sl_slip.lua (log field), sl_lanes.script.lua (slipPlan, recheck, tallies), sl_toolcore.lua (zones, phasesAt, labels),
  sl_audit.lua. Tests: test_cross / test_lights / test_audit / test_script / test_tool / test_zones ("exit fan",
  "sl_exitfan", "kerbLaneOnly"). In-game check: TESTING.md "EF". No user-visible change outside the zone, so no
  description / strings change.

## Stress Test bench additions SL-1 .. SL-6 (2026-10-13, offline)
Contract and choices: plans/square_stress_test/BENCH.md "As implemented in Smart Lanes". Summary: zone mode
`sl_keeplights` (lights left as the game made them, `LIGHTS ... to=kept`, SUMMARY `zone_keeplights= lights_kept=`),
`MODE ... lights=on|off`, `zid=` on APPLY / SKIP / LIGHTS / PHASES / AUDIT lines of nodes in a labelled zone, state
`zmodes` / `zerr` (written on zones events only) and `qlen` (our GUI reports `SmartLanes.qlen`, only while zones are
set), and one late lights look 600 frames after a lights-off for zone nodes (`RECHECK kind=lights`). Outside zones
everything is as before (tests "SL-5 / SL-6 off outside zones" and every earlier test unchanged except the MODE line's
appended `lights=` and the extra `SmartLanes.qlen` subscription). Files: sl_zones.lua (mode, zoneAt, idOf, runOf),
sl_lanes.script.lua (keepLights, zid hook, MODE, SUMMARY, zerr / zmodes / qlen, lightsLate), sl_toolcore.lua
(keeplights in toolLights, zid in its out wrapper, write path through it). In-game check: TESTING.md "BN".
