# square_roundabouts Phase 6: lane connections at ring junctions

Status: superseded 2026-10-08. Lane routing became the separate mod `square_smart_lanes` (`plans/square_smart_lanes/PLAN.md`); the Phase 6a probe ran (results: `docs/findings.md` "Junction lane connections (2026-10-08)"), 6b/6c were never done in this mod.

Plan written 2026-10-08. Background: `PLAN.md` (Phases 1-4b), `PHASE5.md` (channel, interchange,
hamburger). Phase 6a (this file's probe) changes nothing in `mods/square_roundabouts`.

## Goal
After one of our roundabouts is placed, assign the lane connections at its junction nodes so that
multi-lane rings drive with lane discipline (turbo-like, without a custom template): on a 2-lane
ring only the outer lane may exit, the inner lane keeps circulating and spirals out; a 2-lane arm's
right lane enters the outer ring lane and its left lane the inner one. Today the engine generates
the connections itself, and (to be confirmed by the probe) lets every ring lane exit and every arm
lane enter every ring lane.

## Research summary (verified in files)
| fact | source |
|---|---|
| Junction routing is component `ComponentType.BASE_NODE_CONFIG` → `Engine.Component.BaseNodeConfig`: `laneConnections : {LaneConnection}`, `crosswalks`, `trafficLightPreference`, `trafficLightConfig`, `doubleSlipSwitch`, `userModifiedLaneConnections`, `userModifiedTrafficLightStates` | `.cache/game/api/tealdef/api/engine.d.tl:184-196`, `ComponentType.BASE_NODE_CONFIG` at `engine.d.tl:1677` |
| `LaneConnection`: `segment0`/`lane0` incoming, `segment1`/`lane1` outgoing, lane indices "zero-based, from left to right when looking from the Node to segment0/1", `withRoad`, `withTram` | `api/tealdef/api/type.d.tl:1197-1213` |
| Write path: `SimpleProposal.streetProposal.nodeConfigsToRemove = {node}` + `nodeConfigsToAdd = {BaseNodeLaneConnectionAndEntity}` ("node itself cannot be removed at the same time"); `api.type.BaseNodeLaneConnectionAndEntity` is exposed | `type.d.tl:2537-2541, 2566-2571, 2798-2802, 3838` |
| Command: `api.cmd.makeWorldBuildProposalCmd(proposal, context, ignoreErrors, playerInitiated, doDust?)` | `api/tealdef/api/cmd.d.tl:953-962` |
| Community mod writing node configs (undo of Crossing Tool edits): entry built from a fresh read, segments validated against the node, `Context{player, cleanupStreetGraph=false}`, `makeWorldBuildProposalCmd(p, ctx, false, true, true)`, sent with a callback **from the GUI thread** (guiUpdate / guiHandleEvent) | `.cache/subscribed/undo_tf3_test/content/undo/tool_probe.script.lua:27-44, 118-140`; called from `undo_gs.script.lua:60-77` (guiUpdate) |
| Second community example: `cfgAE.comp = cfg` (read component) then edit `laneConnections` / `crosswalks` | `.cache/subscribed/move_it/content/tools/move_it/move_it.script.tl:2466-2498` |
| Node → segments: `api.engine.system.streetSystem.getNodeStreetSegments(node)` / `getNodeSegments(node)`; nodes in an area: `api.engine.util.octree.findEntitiesInCircle(Vec2f, r, ComponentType.BASE_NODE)` | `api/tealdef/api/engine/system.d.tl:299-315`, `engine/util.d.tl:329, 1054`; octree use in `undo_tf3_test/.../tool_probe.script.lua:83` |
| `BaseEdge` carries `roadTemplate`, `roadStyle`, `node0`/`node1`, `laneConfigs` (TF3 has no `streetType` field) | `engine.d.tl:99-130` |
| Build events: `handleEvent(..., id = "apply_command", name = "onPostBuildProposal", param = {Proposal, ProposalData, {Entity}, playerInitiated})`; `Proposal.toAdd[i]` = `ConstructionEntity {fileName, transf, construction.params, construction.frozenNodes, ...}`; `ProposalData.toAddData[i].boundingVolume.bbox` | `mods/square_full_refund/content/refund/refund.script.tl:438-447`; `type.d.tl:2600-2660, 2694-2750`; `engine.d.tl:225-230` |
| The GUI event `builder.proposalApply` (param `{Proposal, ProposalData, result}`) reaches guiHandleEvent once the game script subscribed to it | base `game_mechanics/company/company.script.tl:387-389, 559-584`; `mission/mission_sim.script.tl:244-276` |
| Constructions cannot set lane connections: the construction result has no node-config field; our roundabouts dissolve into plain streets (all nodes `freeNodes`) | PLAN.md "Decisions"; main session check of `edgeLists` fields |
| The vanilla Crossing Tool (`base/content/gui/construction/tools/lane_modifier_tool.script.tl`) is native: no Lua command besides the proposal | main session |
| Engine-thread gotchas: `sendCommand` inside a build event asserts `!m_betweenChanges`; `sendCommand(cmd, callback)` from the engine `update` fails "Callbacks are currently disallowed" | `refund.script.tl:345-347`; `docs/findings.md` "Street names and Road Stops" |

Lane layouts of the templates we use (`.cache/game/base/content/infrastructure/street/**.street_template.lua`,
`laneConfigs` in file order; S = sidewalk PERSON+CARGO, V = vehicle lane CAR+BUS+TRUCK, `-` = shoulder
without modes, B/F = `forward`):

| template | used for | laneConfigs |
|---|---|---|
| `highway_new_small` | 1-lane ring, Magic satellites, interchange slip roads | B- F V F- (1 vehicle lane) |
| `town_new_one_way_small` | 2-lane ring, medium-arm splitter legs | B S, F V, F V, F S |
| `town_new_one_way_medium` | 4-lane ring, large-arm splitter legs | B S, F V x4, F S |
| `town_new_one_way_xsmall` | small-arm splitter legs, channel slip lanes | B S, F V, F V, F S |
| `town_new_small` / `country_new_small` | arms | S, B V, F V, S (1 per direction) |
| `town_new_medium` / `country_new_medium` | arms | S, B V x2, F V x2, S |
| `town_new_large` / `country_new_large` | arms | S, B V x3, F V x3, S |

Whether `LaneConnection.lane0/lane1` count sidewalks and shoulders (template index) or only vehicle
lanes, and which side index 0 is on a one-way ring, is **not documented**: probe question Q1.

## Lane rules we intend (right-hand traffic; left-hand traffic is the mirror image)
Notation at one node: `Rin` = ring segment arriving, `Rout` = ring segment leaving, `A` = arm
(two-way). Ring lanes are numbered from the outside, `o1` (outer, curb side) .. `on` (inner). Arm
lanes per direction are numbered from the curb: `in1..ink` arriving at the node, `out1..outk`
leaving it. `(seg, lane) → (seg, lane)` is one connection, withRoad true; tram connections
(`withTram` only) are never touched. Once Q1 is answered, `o1/in1/out1` map to concrete indices
(guess: on a one-way ring seen from the node, `o1` = lowest vehicle index, inner = highest).

### Better Roundabouts (main entry)
Ring node with an arm (n ring lanes, k arm lanes per direction):
- **Exit only from the outer lane.** `(Rin, o1) → (A, out1)`; if k >= 2 also `(Rin, o2) → (A, out2)`
  (a 4-lane ring with a medium/large arm exits two lanes side by side). No other `Rin → A`.
- **Circulate and spiral out.** `(Rin, oi) → (Rout, oi)` for every i, plus `(Rin, oi) → (Rout, o(i-1))`
  for i >= 2 (move one lane outwards at each node). Never inwards (`oi → o(i+1)`): a vehicle that
  must exit is never pushed away from the exit.
- **Enter by lane.** k = 1: `(A, in1) → (Rout, o1)` and `(A, in1) → (Rout, o2)` (2/4-lane ring:
  the single arm lane may choose; it then spirals out). k >= 2: `(A, inj) → (Rout, oj)` for j <= min(k, n)
  (right lane → outer, left lane → inner; a 3-lane large arm on a 2-lane ring: in3 → o2 as well).
- **No U-turn** `A → A` (expected to be absent already).
- 1-lane ring (`highway_new_small`): nothing to choose; leave the engine's set alone (only drop a
  U-turn if one exists).
Ring node without an arm (2 ring segments): `(Rin, oi) → (Rout, oi)` and `→ (Rout, o(i-1))`.

Splitter legs (`Splitter islands` On): exit node X (`Rin`, `Rout`, leg `Lx` leaving, one-way 2-lane
`xsmall`/`small` or 4-lane `medium`): only the outer ring lanes exit, lane for lane from the curb:
`(Rin, o1) → (Lx, right lane)`, and `(Rin, o2) → (Lx, left lane)` when the leg and the ring both have
>= 2 vehicle lanes. No other `Rin → Lx`.
Entry node E (`Rin`, `Rout`, leg `Le` arriving): `(Le, right lane) → (Rout, o1)`, `(Le, left lane) → (Rout, o2)`.
Ring connections as above. The split node S (arm, two legs) is a plain fork/merge: leave it.

Through the centre (Road / Road + traffic lights; hamburger): axis ring node has `Rin`, `Rout`,
arm `A`, through road `T`. Through traffic only goes straight: `(A, inj) → (T, outj)` and
`(T, inj) → (A, outj)`; no `Rin → T`, no `T → Rout` (the through road is not a shortcut onto the
ring); arm entry and ring exit as above. Tram line through the centre: tram-only connections,
untouched.

### Magic Roundabout
Satellites are 1-lane rings (`highway_new_small`): no lane choice. The two-way link ring
(`town_new_small`, 1 lane per direction) meets each satellite at two nodes (`Rin`, `Rout`, link `K`):
keep the engine's set; only drop U-turns `K → K` if present. Result: no change expected unless the
probe shows U-turns. Low priority.

### Channelized Junction
Central node (main E/W, side N, + S for X), slip lanes on the arms:
- At the central node remove the turns a slip lane serves, so those turns must use the slip lane:
  near-side slips (T): `E → N` and `N → W` (X adds `W → S`, `S → E`); "All turns off the main road":
  `E → N`, `W → N` (X adds `W → S`, `E → S`).
- Diverge node on the approach arm (arm in, arm continuing to the centre, slip leaving): only the
  curb lane enters the slip: `(arm, in1) → (slip, all lanes)`; `(arm, inj) → (arm-continue, inj)` for all j
  (the curb lane may still go straight).
- Merge node on the target arm (slip arriving, arm from the centre, arm continuing out):
  `(slip, lanes) → (arm-out, out1)` only.
- Splitter legs on the side road: as the roundabout's X/E nodes, against the main road's lanes.

### Roundabout Interchange
- Ring nodes with cross-road arms (two-bridge ring, dumbbell, peanut lobes): as the main entry.
- Slip roads (`highway_new_small`, 1 lane) at ring nodes: off-ramp arriving = an arm with k = 1;
  on-ramp leaving = `(Rin, o1) → (ramp, 0)` only.
- Highway gore nodes (carriageway in, carriageway out, ramp): off-ramp diverge `(hw in, kerb lane) → ramp`
  only; on-ramp merge `ramp → (hw out, kerb lane)` only. Probably already the engine default; probe.
- Dumbbell link (two-way cross road between the rings): an arm at both rings.
- Peanut waist (one-way edges continuing the lobes): `(in, oi) → (out, oi)` lane for lane, no spiral
  (a lane change in the pinch is what the waist must avoid).

## Design options
1. **Automatic on placement (game script).** Subscribe to `onPostBuildProposal`; when a
   `square_roundabouts*.con` is placed (the probe shows what the event carries: Q2), queue a job in
   the game-script state, find the nodes on a later `update`/`guiUpdate`, compute the connection
   sets and send one proposal with every node's config. Must not run inside the build event
   (`!m_betweenChanges`). Pros: zero clicks, matches "the roundabout just works". Cons: the mod gains
   a game script with saved state and event subscriptions on every build; it has to recognise its
   own nodes after the construction dissolved (position + template matching).
2. **A "button" on a selected node or roundabout (GUI tool).** The player selects a node (or clicks
   inside a ring) and presses "Apply roundabout lanes". The script walks the ring from that node
   (follow one-way ring templates until it closes) and writes every ring node. Pros: also works for
   the **vanilla roundabout**, for roundabouts placed **before** the mod update, for hand-built rings
   and after the player rebuilt an arm (if the engine regenerates connections, Q3); no build-event
   handling; nothing runs unless pressed. Cons: one click per roundabout; needs a GUI mount point
   (window plugin or toolbar button; see `mods/square_line_revert` for mounting patterns).
3. **Both:** automatic for new placements, button for everything else. Same pure "rules" module.
Recommendation pending the probe: if writes stick (Q3) and the event identifies our construction
cheaply (Q2), option 3; if the engine regenerates connections on nearby edits, option 2 alone
(re-apply on demand) is the honest design.

## Save safety
Today: construction only, no game script, `severityAdd: None`, `severityRemove: Warning` (islands),
description.html line 73: "Adds nothing to the game but four construction menu entries, and runs no
scripts while you play."
With Phase 6:
- **Written lane connections are ordinary BaseNodeConfig data** in the savegame (the same as a
  Crossing Tool edit). They survive removing the mod and need nothing from it. Removal stays
  `Warning` only because of the islands.
- **Option 1 adds a game script.** Its state (pending jobs, at most a few entries, cleared when done)
  is saved under the mod's game-script name. Precedent: `square_full_refund` keeps a small state with
  `severityRemove: None`. What the game does with a removed mod's saved game-script state is
  **unverified** (expect it to be dropped); keep the state empty between placements so nothing
  meaningful is ever left behind. Lazy subscription in `update` (no lifecycle event for a mod added to
  an existing save), `severityAdd` stays `None`, no change to existing roundabouts unless the player
  asks (button).
- **Option 2** adds a GUI script only (no saved state).
- description.html must change: "runs no scripts while you play" → e.g. "After you place a
  roundabout, a small game script assigns its lane connections once; it changes nothing else.
  Lane connections stay if you remove the mod." Changelog entry with the revision bump.
- Never touch nodes the mod did not build (option 1: only nodes whose segments all came from the
  placement; option 2: only the ring the player chose). Never overwrite a node with
  `userModifiedLaneConnections = true` unless the player pressed the button on it.

## Phases
- **6a (this phase): probe.** `mods/square_roundabouts_lanes_probe` (DEV ONLY, never upload), offline
  tests `tests/square_roundabouts_lanes_probe/`, TESTING.md "Phase 6a lane probe". No change to
  `mods/square_roundabouts`.
- **6b: implement** the chosen option: pure rules module (node topology → connection set, unit-tested
  for every entry/lanes/arm road/splitter/through combination using the geometry modules' output as
  topology), the game script and/or GUI button, description.html + changelog, `revision` bump.
- **6c: in-game test**: traffic on 2- and 4-lane rings (inner lane never exits, no deadlocks at the
  spiral), Crossing Tool shows our sets, removal of the mod from a save keeps the connections.

## Open questions the probe answers (one in-game round)
- **Q1 index convention.** `CONN` lines vs `SEG ... lanes=` (template order with sidewalks) and
  `endAt` (0 = segment starts at the node): do lane indices count sidewalks/shoulders? Which index is
  the ring's outer lane? What does the engine generate by default at a ring/arm node (every ring lane
  to the arm? arm lane to every ring lane?), and is `userModifiedLaneConnections` false by default?
  Does a plain 2-segment ring node have a BaseNodeConfig at all (`...d2` tag)?
- **Q2 detection.** `BUILD`/`CON`/`ADDNODE`/`ADDSEG` lines: is our construction in `proposal.toAdd`
  with its `fileName`, transf, bbox and `sqrb_*` params in the post event, or only as streets (then the
  probe's `streets` fallback job fires)? Are `result` ids real entities? Does the `GUIEV` line
  (`builder.proposalApply`) carry the same?
- **Q3 write.** `WRITE` / `WRITE_RESULT success=` / `PERSIST same=`: is a node-config proposal from the
  GUI thread accepted, does the change show in the Crossing Tool, does it survive 2/15/60 s and later
  nearby builds, does it need `userModifiedLaneConnections = true` (write 1 sets it, write 2 keeps the
  read value), and what does the vanilla Crossing Tool itself send (`NCFG` lines of its build)?

## Probe log format (`[SQRB-LANES]`, one fact per line, `key=value` without spaces)
| kind | thread | fields |
|---|---|---|
| `INFO` | both | `msg`, `write` (setting) |
| `BUILD` | engine | `build` (counter), `shape` (param types), `toAdd`, `toRemove`, `addedNodes`, `addedSegs`, `removedNodes`, `removedSegs`, `ncfgAdd`, `ncfgRemove`, `result` (ids), `costs`, `toAddData` |
| `ADDNODE` / `ADDSEG` | engine | first 4 added nodes (`entity`, `x y z`) / segments (`entity`, `type`, `node0`, `node1`, `tpl`) |
| `CON` | engine | `build`, `i`, `file`, `entry` (main/magic/channel/interchange/vanilla/-), `tx ty tz` (transf), `cx cy r src` (scan circle from bbox or transf), `frozenNodes`, `frozenEdges`, `params` (`sqrb_*`) |
| `NCFG_REMOVE` / `NCFG` / `NCFG_CONN` | engine | node configs in the build (e.g. the Crossing Tool's): `node`, `nConns`, `userModLanes`, `userModLights`, `lightPref`, `crosswalks`; each connection `s0 l0 s1 l1 road tram` |
| `JOB` | engine | `seq`, `entry` (or `streets` fallback with `ringSegs`), `build` |
| `GUIEV` | GUI | `builder.proposalApply`: `shape`, `files`, `result`, `addedNodes`, `ncfgAdd` |
| `SCAN` | GUI | `job`, `entry`, `x y r`, `nodes`, `junctions` (>= 3 segments), `deg2` |
| `NODE` | GUI | `tag` (`j<seq>`, `j<seq>d2` = one plain ring node, `w<k>diff`), `node`, `x y z`, `nSegs`, `segsHow`, `hasConfig`, `nConns` |
| `SEG` | GUI | `node`, `seg`, `tpl`, `ring`, `type`, `node0`, `node1`, `endAt` (0/1: which end is at the node), `nLanes` (laneConfigs), `nLaneConfig`, `lanes` (`F|B:width:offset:modes`), `style` |
| `CFG` | GUI | `userModLanes`, `userModLights`, `lightPref`, `crosswalks`, `doubleSlip`, `conns` (sorted `s0:l0>s1:l1:RT`) |
| `CONN` | GUI | `node`, `s0 l0 s1 l1 road tram` |
| `WRITE` | GUI | `k`, `job`, `node`, `ringIn`, `arm`, `lane0` (removed incoming lane), `removed`, `kept`, `mode` (`set_true`/`keep`), `userModBefore`, `removedConns`; or `status=no_candidate/skipped_max_writes/no_config_component` |
| `WRITE_RESULT` / `WRITE_SEND` | GUI | callback `success`; send fallback without callback |
| `PERSIST` | GUI | `k`, `node`, `reason` (`time2s/15s/60s`, `build<N>`), `dt`, `same`, `nConns`, `hasConfig`, `userModLanes`, `mode` |
| `ERROR` | both | `where`, `err` (at most 20 per session) |

Write experiment (param "Write experiment" On, at most 4 per session): at the lowest-id node with
two ring-template segments, an arm, and ring→arm road connections from 2+ incoming lanes, remove the
ring→arm connections of the **highest** incoming lane index (the guessed inner lane,
`lanes_logic.chooseExperiment`). Odd writes set `userModifiedLaneConnections = true`, even writes keep
the read value. A 1-lane ring gives `status=no_candidate`.
