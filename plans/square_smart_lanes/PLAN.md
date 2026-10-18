# square_smart_lanes ("Smart Lanes")

Plan written 2026-10-08. Mod: `mods/square_smart_lanes/`. Tests: `tests/square_smart_lanes/`.
In-game checklist: `TESTING.md`. Flow results (Lights showcase twins, running ledger): `RESULTS.md`. Re-time and
its step B ("Keep timing adjusted"): `RETIME_PLAN.md`. Superseded designs and checks: `HISTORY.md`. Background: `plans/square_roundabouts/PHASE6.md` (probe design),
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
| Seeds = `nodeConfigsToAdd` entities + `addedNodes` + both ends of `addedSegments`; existing seeds the build did not change are quiet (since 2026-10-17: "Nearby junctions stay as they are") | the post event carries real entity ids (probe log: `ADDNODE entity=17955` = the later `NODE node=17955`) and a config for every new or changed node; a replaced arm segment makes its far junction a seed too |
| One `makeWorldBuildProposalCmd` per ring: `nodeConfigsToRemove = {nodes}`, `nodeConfigsToAdd = {entries}`, `Context{player, cleanupStreetGraph=false}`, args `(false, true, true)` | as the Crossing Tool and undo_tf3_test (`tool_probe.script.lua:124-130`); `api/tealdef/api/cmd.d.tl:961-962`, `type.d.tl:2537-2571` |
| New `LaneConnection` objects from `api.type.LaneConnection.new()` | read objects are read-only and the tealdef has no constructor, but the runtime has one (findings.md 2026-10-08, `HOW strategy=ctor`); `sl_write.lua` keeps the table / owned / subset fallbacks |
| Every other config field (crosswalks, traffic lights, `userModifiedLaneConnections`) is kept as read | the Crossing Tool leaves `userModifiedLaneConnections` nil (findings.md) |
| `severityAdd: None`, `severityRemove: None` | written lane connections are ordinary BaseNodeConfig data, identical to a Crossing Tool edit, and need nothing from the mod; the game-script state is a job list that empties itself (ttl 300 engine updates) and is ignored on load |
| `cosmetic: false` | lane routing changes traffic (wiki `moddefinition.md:69`: anything with an impact on the simulation is not cosmetic). Flip if you decide "same as a vanilla tool" counts as cosmetic |
| Bus lanes (road lane without CAR): planned around since rev 6 (2026-10-13, player request), was: junction skipped | the rules plan car lanes only, so no car lane is ever led into a bus lane (that would strand cars); every connection touching a bus-only lane is kept as read; see "Bus lanes" below |
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
  `x` and entry lanes `e` ("curb first"). Ascending connection index runs driver-right -> left on an
  incoming segment and left -> right on an outgoing one, so for CCW: `o_in` ascending, `o_out`
  descending, `x` descending, `e` ascending; CW is the mirror. Left-hand traffic is therefore handled
  by geometry alone (a mirrored world gives mirrored connections: test).
- **Node kinds**: `plain` (only the 2 ring segments, never touched), `arm` (exactly one non-ring
  segment with road lanes: a two-way arm, or a one-way splitter leg with only exits or only entries),
  `skip` (two non-ring road segments, e.g. a road through the centre; logged). An arm's bus-only lanes are in
  no lane list (car lanes only, "Bus lanes" below); an arm with bus-only lanes only is no arm.

## The rule (sl_rules.lua, variant "Matched lanes", key `two_lane`)
Revised 2026-10-08 after the in-game report "4 lanes turning into 1": the first rule fed every
entry lane into `o_min(j, feed)` with `feed` = 1 unless some arm had a 2-lane exit, so a 4-lane
one-way stem into a ring without exits put all 4 entry lanes into the outer ring lane, and a 3-lane
entry on a 4-lane ring put 2 lanes into o2. Exits were capped at 2 ring lanes.

R = ring lanes, E = exit lanes, N = entry lanes at the node (lane 1 = curb side, o1 = outer).
Ring-level: `turbo` = the whole ring is planned (every junction a seed: the automatic pass seeds every arm
junction of a ring a build touched, "Whole rings in the automatic pass"), has no skipped node, and every node
with exits has min(E, R) >= 2, **and the ring has 3 or more lanes** (since 2026-10-15, user decision: a 2-lane ring
that would qualify gets matched lanes, "Default: matched lanes on 2-lane rings with wide exits" below; a 2-lane ring
with one-lane exits gets the mid-node spiral, "Default: the mid-node spiral").

**Ring decision table** (the automatic rule `two_lane` and the tool's Apply `turbo`; zone modes `sl_r*` are unaffected):

| ring | exits | layout | log | evidence |
|---|---|---|---|---|
| 1 lane | any | matched (nothing to change lanes to) | `turbo_reason=one_lane_ring` | |
| 2 lanes | every exit >= 2 lanes | **matched** (since 2026-10-15; was turbo) | `turbo=false turbo_reason=two_lane_ring layout=matched default=two_lane_exits` | bench s5 lu2: matched 89.1 vs turbo 73.8 vs game 58.6 cars/min, 3/0 in every mix; ring lane use ~50/50 vs turbo ~20/80 (RESULTS.md) |
| 2 lanes | every exit 1 lane | `sl_rmid` with mid nodes (Smart Lanes adds them), else `sl_rspiral` | `layout=sl_rmid default=one_lane_exits` | Sheet 4 v3-v5 (heavy-traffic check pending: RESULTS.md `sl_rmid2` row) |
| 2 lanes | mixed (a 1-lane exit beside 2+-lane exits) | matched, ramp own-lane entries (rule 5) | `turbo_reason=narrow_exit` | unchanged (the Roundabout Interchange with a 1-lane ramp) |
| 3 / 4 lanes | every exit >= 2 lanes | turbo | `turbo=true` | micro bench v2; bench s5 lu4: turbo 100.6 cars/min, best of 4 |
| 3 / 4 lanes | any 1-lane exit | matched | `turbo_reason=narrow_exit` | |
| any | a skipped junction / no exit | matched | `skip_node` / `no_exit` | |
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

Exit-only outer lane: only when every exit has >= 2 lanes, so a vehicle in o1 always has a curb exit
lane at the next arm; otherwise o1 exits or continues.

### Example sets (CCW, right-hand traffic)
| Ring, arms | o1 (outer) | o2 | o3 | o4 | entries |
|---|---|---|---|---|---|
| 2-lane, medium (E = N = 2), matched (turbo until 2026-10-15: o1 x1 only) | x1 or straight | x2 or straight | | | e1->o1, e2->o2 |
| 2-lane, small (E = N = 1) | x1 or straight | straight | | | e1->o1 |
| 4-lane, medium, turbo (probe 22768: 10 -> 7) | x1 only | x2 or straight | straight | straight | e1->o1, e2->o2 |
| 4-lane, large (E = N = 3), turbo | x1 only | x2 or straight | x3 or straight | straight | e1..e3 -> o1..o3 |
| 2-lane, large arms (matched since 2026-10-15) | x1 or straight | x2, x3 or straight | | | e1->o1, e2 and e3 -> o2 |
| 4-lane, 4-lane one-way stem in, no exits | straight | straight | straight | straight | e1..e4 -> o1..o4 |

### Only rings the player just built or touched
- Jobs come only from player builds with added segments; the job's nodes are the seeds. A seed the build did not
  change (quiet: "Nearby junctions stay as they are") keeps its lanes off a ring and only leads to its ring.
- A ring is planned when a seed lies on it, whole: see "Whole rings in the automatic pass" (since 2026-10-13;
  before, only seed nodes were written and a ring not seeded whole lost its exit-only lane).
- Junctions elsewhere are never read or written.

## Save safety
- `severityAdd: None`: subscription happens lazily in `update`; nothing writes until the player builds, answers the
  first-load welcome (a window only; its answer is the first write) or has "Automatic light timing" All lights (then
  the listing enrolls lit junctions from the load on: the player chose it in the mod settings).
- `severityRemove: None`: see Decisions. The state `{seq, jobs}` holds at most 3 jobs of at most 160
  node ids for ~300 engine updates after a build, normally `{seq = n, jobs = {}}`.
- Rev 7 / 8 lists in the same state, each written only from its first use: `kept` (<= 2000 entries of 3 numbers,
  sl_kept.lua), step B's `auto` (<= 1000 entries of 3 numbers: node id, position; plus `aseq`, `aall`, `areq` (<= 60
  nodes), `arun`) and the last-measured records of both Re-time modes `rlast` (<= 1000 entries of 8 numbers: node id,
  position, game s, source / outcome, cycle before / after, the signature of the durations we last wrote (since
  2026-10-16; older records have 7); plus `lseq`); both caps reached under 120 kB (110 kB before the signature) in
  test_auto.lua's verbose serialization (sl_auto.lua, RETIME_PLAN.md "Step B v4"). Removing the mod drops them with the
  game script (the enrolled list and the records are gone; TESTING.md "RM" checks it in game); written phase lengths
  stay as ordinary phases. Nothing measures or writes until the player ticks "Keep timing adjusted" or presses
  Re-time (or a test sends an `sl_auto` zone / `SmartLanes.auto`).
- "Automatic light timing" and the first-load welcome (sl_allmode.lua, 2026-10-15): `wel` (one number, written when
  the welcome is answered, Not now and closing included: every save the welcome was shown in gets it, ~20 bytes with
  `aseq`), `amode` ("all" | "pick": Apply with the lights box, the settings panel's Automatic light timing), `aout`
  (<= 1000 entries of 3 numbers, the oldest dropped beyond: junctions unticked while all lights are kept adjusted)
  and `mpass` ({seq, done}: the existing-junctions pass). Under 45 kB with the cap reached (test_allmode.lua); with
  the step B lists above at their caps the state stays under ~155 kB. No answer: nothing but the window. Removing the
  mod drops them with the game script; the lanes the existing-junctions pass wrote stay as ordinary connections.
- The in-game settings panel (sl_settings.lua, 2026-10-15): `sset` (at most 4 small numbers: the light settings
  changed in this save) and `sseq`, written from the first change only. Removing the mod drops them; the mod.json
  values apply again.
- Record traffic (sl_record.lua, 2026-10-16): `trec` (<= 1000 entries of 9 numbers: node id or ring key, position,
  game s, kind, seconds and vehicles of the whole recording and of its last-3-minutes span; plus 3 for the recording
  before it there (game s, seconds, vehicles), 12 in all, when there was one; the oldest dropped beyond)
  and `tseq`, written from the first recording that ran at least 30 game s (its checkpoint every 5 game min or its
  end), never on load. Under 120 kB with the cap reached, every entry with its previous (test_record.lua "save
  safety", the verbose serialization: ~112 kB); with every list above at its cap the state stays under ~270 kB. Removing the mod drops them with the game script;
  a recording changes nothing in the game.
- Read-only except the lane writes; no global overrides, no modifiers, no `runFn`.
- Map editor: inactive.

## Logging (`[SQRL]`, stdout.txt)
`APPLY ring node lanes dir exits entries turbo fresh before after` (one per written node),
`SKIP ring node reason` (ring nodes left alone, or a node whose entry could not be built; `reason=hand_edit`: a
junction the build did not touch, edited by hand, keeps its ring at the build's seeds),
`WAIT kind=ring job ring node` (the job waits for our earlier proposal naming a ring junction it adds),
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
`RETIME op=<op> node=<n> ...` (the tool's Re-time, rev 8, section "Re-time" below; at most 400 per session, ~12 per
run; always on, one run per click; every RETIME line of a node inside a zone with an id carries `zid=`, as APPLY /
SKIP / LIGHTS / PHASES / AUDIT, for the Stress Test's light-plan A/B report): `op=start window_s= every_s=
time=game|wall segs= conns= crosswalks= states= kinds=<veh|all_red|walk per phase, /> durations=<a/b/..>
user_modified= running=`; `op=cancel reason=button|changed:lanes|changed:phases|gone:<lightRead reason>|busy|sampler
elapsed_s= samples= running=` (rev 8 v2: deselecting, another junction and closing the tool no longer cancel); `op=bg
phase= running=` (once per run: the background plugin stepped it with the tool closed, sl_bg.script.lua); `op=refuse
reason=<lightRead reason>|full running=` (full: Core.RETIME_MAX_RUNNING already measure, "Several Re-time runs at
once"); `running=` counts the runs at once before this one ends (rev 9);
`op=measured samples= window_s= time= src=routed|scan cand_max= cand_mean= near_mean= far_skipped= reads= calls=
calls_per_sample= frames= busy_ms= gaps= gap_s= lost= capped= passes=<in>out:n,..> queue=<in>out:mean,..>
q_arm=<seg:mean,..> err= running=` (calls: engine reads of the run; with several runs the shared sampler run's
reads over this run's life, cand_* / near_mean of every run's candidates together; far_skipped: candidates not read because they could not be
near yet; gaps / gap_s: steps missed for longer than 2 samples, the window moved on by them); `op=plan
result=write|fits|small_sample|no_mapped_traffic|no_vehicle_phase total= queued= unmapped= always= kinds= load=<phase:
critical load,..> old= new= cycle=<old>><new> y=<critical flow ratio sum> lost=<s per cycle> sat=<cars per lane per
green hour> sat_src=est|opt cycle_reason=webster|min|max|saturated|queues|floors max_delta=`; `op=write sent=1|0 why=
durations= min=` (plus the proposal's
`LIGHTS src=tool node= to=retime states= cycle= durations= pref= user_modified= action=retime`); the probe after a write
`op=probe at=before|cb|f30|s5|s30 exists= config= light= state= time= state_times= user_modified= durations=
[same_durations= same_locked=] [since_s=] [success=]` (before: just before sending; cb: in the callback; f30: 30 GUI
frames after it; s5 / s30: 5 / 30 game s after sending), `op=reroute at=base5|base30|s5|s30 tracked= same= exit_changed=
dropped= gone=` (base: a snapshot 35 game s before the window ends, re-read 5 and 30 s later, no write in between;
s: the snapshot taken at the write). (`op=probe_cut` is gone with rev 8 v2: the probe goes on with the tool closed.)
`AUTORETIME op=<op> ...` (step B "Keep timing adjusted", RETIME_PLAN.md "Step B"; always on; `zid=` on every line of a
junction inside a zone with an id; at most 2000 per session from the game script, 4000 from the runtime). From the game
script (the event): `op=enroll|unenroll node= pos=<x,y> src=tool|zone|all|stress|prune|build|select total=<entries>`, `op=refuse
reason=cap node= pos= src= total=`, `op=now node= pos= src=`, `op=enroll_all phase=request run= src=`, `op=unenroll
all=1 n= run= src=` (clear), `op=ignored reason=` (bad payload, 20 per session); `update` (re-attach) and `last`
(records) log nothing. From the runtime (step B v4, RETIME_PLAN.md "Step B v4"): `op=snapshot n=<watched> src=routed|scan
cand= read= drivers= near= counted= calls= frames= busy_ms= max_frame_ms= fetch_ms=<list calls> finish_ms=<averages> span_s= gone= capped= enrolled= err= heavy=<refreshes and decisions since the
previous snapshot> backlog=<most carried over at once>` (one per snapshot, every 120 game s; ms in wall time, api.type.Clock, since 2026-10-15); per decision `op=plan node= pos= result=write|fits|quiet|few_snapshots|
no_mapped_traffic|no_vehicle_phase snaps= queued= queue=<seg:mean standing> arrive=<seg:cars per lane per h> load=
load_s=<smoothed, - without a previous decision> share= balanced=0|1 old= new= cycle=<old>><new> cycle_wanted=
stepped=0|1 greens=<old>><new> y= cycle_reason=webster|min|max|saturated|queues|floors|balanced|unconfirmed every=<interval
s before>`; `op=hold node= pos= reason=building|busy` (a wanted write waits); `op=skip node= pos= reason=stale held=
retry_s=120 | reason=read:<why> retry_s=120`; `op=write node= pos= sent=1|0 why= durations= cycle= greens= stepped=
gain= every=<next interval s>` and `op=write node= pos= at=cb success=` (plus the proposal's `LIGHTS src=auto node=
to=retime ... action=auto`); `op=reset node= pos= reason=lanes snaps=`; `op=prune node= pos=
reason=gone|no_light|no_phases|no_config`; `op=reattach node=<new> pos= old= new=`; `op=adopt node= pos=
reason=phases|durations old=<durations> new=<durations>`; `op=config every_factor=<check interval factor>
params=read|unread clock=wall|os` (once per runtime); `op=wake node= pos= reason=quiet_rise|fits_grow|fits_shift queued=<at the
decision>><now> shift= shift_cars= decided_s= due_was_s= due_s=` (early wake, RETIME_PLAN.md "Decisions"); `op=enroll_all phase=done run= src=component|octree nodes=
lit= already= sent= capped=`. At most 4000 lines per session, the write and enroll_all lines 4000 apart. Gone with v4:
`window_start`, `window_end`, `settle`, `member_gone`, `skip reason=building|busy|interval|changed:*`.
`tools/flow_report.py` ignores them (kind AUTORETIME, not RETIME); see "Stress Test
interface: Keep timing adjusted" for what it would need.
All lights (sl_allmode.lua, 2026-10-15): `AUTORETIME op=mode mode=all|pick src= unenrolled= optouts_cleared=`,
`op=optout|optin node= pos= src=tool optouts=`, `op=optout_drop n= max=` (handler); `op=enroll_all phase=done run=allmode
src= nodes= lit= already= optout= hand= sent= capped=` (the listing, only when it sent / capped or once per session),
`op=cap_hit src=allmode|build max= enrolled= capped=` (once per session); `op=config ... lights=pick|all`.
New lights at once (2026-10-16): `AUTORETIME op=new_lights phase=queued src=build nodes=<saved> segs=<added segments>
cfgs=<node configs written> plan=0|1` (handler, per player build in all-lights mode that touched a node not enrolled /
opted out, or a config-only build with the phases look, "New lights get Smart lights"; 200 per session);
`op=plan_new src=build sent= skipped= later=` (runtime, a frame that sent new-light plans), `PHASES src=new_light node=
phases=sl pattern= plan=|plan_fail=` (200 per session) and the proposal's `LIGHTS src=new_light ... to=sl_phases ...
action=new_light plan=`; `op=enroll_new src=build checked= sent= already= optout= hand= wait= gaveup= gone= capped=` (runtime,
when it sent, found a light timed by hand or capped); the enrolls themselves are the handler's `op=enroll ... src=build`
(a build) and `op=enroll ... src=select` (the tool's selection).
`WELCOME op=show` | `op=skip reason=unreadable|no_window_api` (the background plugin), `WELCOME op=answer answer=apply|later
lanes=0|1 lights=0|1 mode=all|- pass=<seq>|-` | `op=ignored reason=answered` (handler).
`TRAFFIC op=<op> kind=node|ring node=<node id | ring key> ...` (the tool's Record traffic, section "Traffic rate at a
junction"; counted with RETIME's 400 lines per session): `op=start nodes=<junctions> cand_ents=<arm segments (a
ring)>|node+segs radius= every_s=5 window_s=1200 bucket_s=30 time=game|wall pos= running=<recordings now>`;
`op=checkpoint elapsed_s= vehicles= rate_all= saved= running=` (every 5 game min of that recording); `op=bg running=`
(once per recording: stepped with the tool closed); `op=done
reason=button|max|gone|error elapsed_s= samples= vehicles= rate_all=<per min> rate_recent=<per min, last 3 min>
recent_s=<its span> saved=0|1 src=routed|scan cand_mean= near_mean= far_skipped= reads= calls= calls_per_sample= frames=
busy_ms= ms_per_sample= gaps= gap_s= lost= capped= arm=<approach (ring: entry) segment:vehicles,..> err= running=<recordings
before it ended> every_max_s=<longest interval between its samples> late=<samples more than 10 s after the one before>`
(the cost fields are the shared sampler run's over that recording's life, shared by all running then); `op=refuse
node= reason=full running=20` (a start beyond Rec.MAX_RUNNING; `reason=another running=<node>` before 2026-10-16, one at
a time). `make logs-grep PAT='TRAFFIC op='`.
`MAPPASS op=start seq= src=config|node|octree|none list= resume=0|1`, `op=progress seq= slices= junctions= scanned= list=
frames=` (every 10 slices), `op=cap seq= what=list|junctions max=`, `op=end seq= reason=done|cap_list|cap_junctions|no_list
slices= junctions= scanned= list= frames=`; the slices' own lines are the automatic pass's (APPLY, SKIP with
`reason=hand_edit|hand_timed`, SUMMARY / AUDIT with `job=m<n>`).
`PHASES src= node= phases=sl pattern=axis|fan|none plan=<PP.planText> | plan_fail=<reason>` (the
automatic pass, the tool's lane writes and Smart lights; `pattern=` added 2026-10-14 so a Stress Test twin's plan can be
confirmed from the log: `PP.patternName`, "none" with plan_fail; "classic" / "generic" until 2026-10-16, below "No
classic fallback": `plan_fail=no_axis_shape|axis_extra|invalid_..` where the game's phases stay).

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
The automatic Phase 1 rule stays `two_lane` (turbo only when every ring junction is a seed); since 2026-10-13 the
automatic pass seeds whole rings ("Whole rings in the automatic pass"), so it gives Turbo's lanes there too.

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
the incoming road lanes curb-first: rightmost lane(s) -> right turns, leftmost -> left turns, middle ->
straight; with fewer lanes than movements, the curb lane shares right+straight and the median lane
left+straight; each movement maps lanes 1:1 onto the target's lanes curb-first (fold extras into the
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
- **Rev 5 toolbar (2026-10-13, current; supersedes the rows above and the badge "UI" note below):**
  [Apply | Reset] in one row (`GROUP_ACTIONS`), then one info param (`sqrl_tool_status`, group
  `sq-tool-info`, shared with Bulk Bulldozer since 2026-10-14) whose content stacks `SmartLanesStatus` (head, detail / result) and
  `SmartLanesBadge` (lane status, empty with nothing selected). Apply is `C.applySelection`: the
  ring when a roundabout is selected (`sel.kind == "ring"`), else the junction / street / multi
  (`C.actions().apply`). The menu draws every toolbar param as a ToggleButton
  (`script_param_util.tl:396-466`), so `sl_tool.css.lua` (the shared "TOOL INFO STYLE" block: 4 rules added by the first active
  tool only, docs/ui-guide.md "Construction toolbar"; the badge colours are inline; scoped under the group class
  `!sq-tool-info`; dashes, see findings gui.md "CSS class names", which `construction.tl:1344-1352` puts on the group's R::Component) removes the
  disabled button's fill and contour, left-aligns the content and sets the text colours (the base
  grey of a disabled button's text, `builtin.css.lua:268-275`, also hid `positive` / `warning`).
  Not yet seen in game: TESTING.md H2.

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
merge, far-side branch, crossroads, Y fork, 5 roads, bus lane (handled since rev 6: test_bus.lua), tram), `test_script.lua` (automatic
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
| skip | 5+ roads, a node of a ring with a bus lane (`bus_lane_ring`), ambiguous, no through road, main road bends, branch on the far side, mixed driving sides | `SKIP kind=slip reason=..` |
The 4-segment case B is the Channelized T's side-road node (slip from the east joins northbound,
slip to the west leaves southbound): each direction is handled on its own.

**Curb side**: case B from the two-way lane layout: connection indices run left to right looking
from the node, so right-hand traffic has a two-way segment's incoming lanes on the lower indices
(probe: arm 18164 at node 17955 incoming {1}, outgoing {2}); left-hand traffic the reverse. The base
game decides the same way (`trafficlightutil.lua` `leftHandTraffic`, from lane positions). Both main
segments must agree. A branch on the far side (crossing oncoming traffic) is not a slip lane: skip.
Case A (all one-way, e.g. a highway gore): nothing tells the driving side, so the curb side is the
branch's side (a left exit gets the mirrored rule, which is what avoids crossings).
**Unverified in game**: that a left-hand-traffic save reports mirrored `laneConfigs` (the tests
assume it, as the ring tests do).

### The rule (lanes curb first; m main in, t through out, b branch out, p through in, q branch in, o out)
- straight: 1:1 aligned from the far (median) side; extra curb lanes fan out of / fold into the curb lane.
- diverge (N in, T through, B branch): f = max(1, N - T + 1), k = min(B, N, f). m_1..m_k -> b_1..b_k,
  extra branch lanes from m_k; m_f..m_N -> through aligned from the far side; N < T: extra curb
  through lanes from m_1; lanes m_(k+1)..m_(f-1) (only when B < N - T) fold into t_1.
  N <= T: only m_1 feeds the branch and it also goes straight (through keeps every lane).
  N > T: m_1..m_(f-1) are branch-only, m_f is an option lane (branch or straight) when B >= f.
- merge (T through in, B branch in, O out): through 1:1 aligned from the far side (extra curb
  through lanes fold into o_1); q_i -> o_min(i, c), c = max(1, O - T + 1): T + B <= O nobody shares,
  else the branch shares the curb lane(s) with through traffic (give-way merge); outgoing lanes
  between are fed by the nearer side.
- No U-turns; every incoming road lane connected, every outgoing road lane fed, no two connections
  of one direction cross (`test_slip.lua` checks all three for every count 1-4 and on every world).
- Deviation from the request: "curb lanes feed the branch 1:1 (min(B, N))" and "if N <= T the curb
  lane also continues straight" cannot both hold without a crossing when B >= 2 and N >= 2
  (m_1 -> t_1 crosses m_2 -> b_2). No crossing and no lost through lane win: with N <= T only the
  curb lane feeds the branch (fanning into all its lanes). The Channelized Junction's 2-lane slip
  lanes on a 2-lane main road are this case.

**2-lane main road (per direction), 1-lane slip**
| diverge 2 -> 2 + 1 | slip b1 | through t1 (curb) | through t2 |
|---|---|---|---|
| m1 (curb) | yes | yes | |
| m2 | | | yes |

| merge 2 + 1 -> 2 | out o1 (curb) | out o2 |
|---|---|---|
| slip q1 | yes (gives way) | |
| through p1 (curb) | yes | |
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
- **Checks (user 2026-10-16: "add a checkmark ... and then a | and Smart lights with check, so you can see you have both
  applied"; offline only, TESTING.md "SO" step 5):** `Pick.badgeChecks(badge, lightsOn)` after `C.canInfo` in
  `addBadge`: `smart` reads "√ Smart lanes" (also "√ Smart lanes (= game default)" and the one-lane variants), and
  any state but `na` / `none` gets " | √ Smart lights" when the light phases are the Smart Lanes plan (`C.lightsStatus`
  same, or timed by our own writes; not when the player re-timed them: "Ours vs the player's"), e.g. "Game default
  | √ Smart lights" after Smart lights on game lanes. Key, class (one colour for the whole line) and the `PICK badge=`
  key stay; the result carries `lights = true`. Names reuse the translated "Smart lanes" / "Smart lights" strings;
  the format has no words ("%s | %s %s"). The mark is `√` (U+221A), not `✓`: the GUI font Lato has no U+2713 / U+2714
  (fontTools on `locale.zip`, docs/findings/gui.md); only Noto CJK has them and window-text fallback to Noto is
  unverified. Lines wrap in the info block (280 px, sl_tool.css.lua). The cursor tooltip's "Lanes: ..." line shows
  the same label.
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

## Free curb turn at traffic lights (rev 4, 2026-10-12, implemented offline, needs the in-game test: TESTING.md FK)
Since rev 8 only a curb turn on a dedicated curb lane is freed: see "Rev 8: dedicated curb lanes, Lights only, main
road green, lane status reason" at the end (the notes below describe rev 4-7).
User request: at signalised junctions Smart Lanes writes, the curb turn (right in right-hand traffic) goes in every
phase, so curb turners never wait for their approach's green. Setting `sqrl_free_turn` "Free curb turn at traffic
lights" (Rules.KEYS.freeTurn; first On / Off, now Off / When safe / Always: see "Revised 2026-10-12" below;
the notes up to there describe FREE, which is "Always" now).

- Pure helpers (sl_lights.lua): `L.kerbIndices(conns, kerb)` (0-based indices of road, non-tram connections whose
  `seg0>seg1` is a curb pair), `L.kerbPhases(conns, kerbIdx, nCross, lists, mode)`: FREE removes the curb indices
  from every phase; LOCK (the tool's Reset) adds a curb index where every other road connection of its approach
  (segment0) is red, which reproduces the game's default (curb turn red with its approach; unit test: Reset gives
  the original phases back exactly). Refuses input with an index outside `[0, #conns + nCross - 1]` (stale phases)
  and changes nothing else: crosswalks stay, no phase is added or removed, empty phases stay.
- Curb pairs from the case X view (`X.kerbPairs`, via `S.kerbPairs`): exits of category "curb" over `ap.allExits`
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
  (`RECHECK`): lanes still ours and a curb connection red -> `W.kerbLights` (src=recheck). Covers AUTO lights that
  appear after our read; lights later than ~10 s are a documented gap (TESTING FK 3).
- Tool: Apply (node, street, multi) frees with the setting On; Reset always locks back; same lanes -> phases-only,
  with the tool's buttons held (`C.phaseHold`) until that proposal answered + VERIFY_DELAY frames.
- Never two proposals on one node at once: crossroads keep their lights (no LIGHTS off proposal for them), the
  phases-only proposal only goes to nodes not in a lane proposal (findings.md "pending change" refusal; a light
  proposal built before a lane write lands would carry phases for the old connections).
- No audit finding: the audit is about lane connections; phases are logged on SUMMARY / WRITE / LIGHTS / RECHECK.

### Revised 2026-10-12: Off / When safe / Always (user decision)
Freed turners do not give way (findings.md "A connection unlocked in a phase does not give way"), so FREE in every
phase drove curb turners into green traffic. The setting now has three values (`Rules.VALUES.freeTurn` =
"off" / "safe" / "always", default "safe" (now "always": see "Revised 2026-10-12: default Always" below); mod.json
values Off / When safe / Always, `defaultIndex` 1 (now 2);
`Lights.modeFor` gives nil / `L.SAFE` / `L.FREE`). Off makes no phase change from this feature at all.

Conflict model of `L.SAFE` (`L.kerbConflict`), per phase p and curb connection k = A -> E, exit lane l; "green" =
not in p's lockedLanes, including curb connections freed earlier in the same phase:
- merge: a green connection of another approach (segment0 ~= A), road or tram, ends on E in lane l.
- cross: a green connection of another approach ends on E in a lane nearer the curb than l. Reason: the game draws
  one lane curve from the approach lane to the exit lane; a curb turner enters E from the curb side, so it cuts every
  stream ending curbward of l and runs beside the streams ending farther out (no conflict, so a far-aligned left turn
  into the far lane does not block it). Lane positions come from sl_cross `ex.o` (exit lanes curb first), carried as
  the value of `X.kerbPairs` (true when unknown: then every other green lane of E counts). No other paths reach the
  curb corner between A and E: the other movements stay on the far side of the junction, U-turns (> 135 deg) are no
  exits, and a game-made connection that ends on E falls under the lane rule anyway.
- A's own connections never conflict (A's phase logic; the curb turn is green with A in the game's default, and
  sl_cross gives each lane of A a contiguous exit range, so they do not cross). Pedestrians are still checked there
  (more conservative than "simply unlock", only differs for hand-edited phases).
- ped: `BaseNodeConfig.crosswalks : {Entity}` (api/tealdef/api/engine.d.tl:190); read as the edges whose end at the
  node has a crosswalk (inferred, not verified: a 3-way game node had 3 crosswalks and a dead end 1, findings.md;
  community mods re-point them by edge id: move_it_probe_overpass `overpass_probe.script.tl:1589-1598`). A green
  crosswalk on A or E keeps k red; on another road of the node it does not; an entity that is none of the node's
  segments (or no list) blocks every curb turn (conservative). In-game probe: TESTING FK 1e.
Everything else as before: same `stale_phases` refusal, relock-then-free in `W.remapLights`, crosswalk indices
untouched, no phase added or removed, LOCK (Reset) unchanged. Stats per (curb connection, phase): `free_phases=`
(unlocks), `kept=merge:n,cross:n,ped:n` (first kind found) on SUMMARY, tool WRITE and LIGHTS lines. The re-check
uses the stored mode (When safe re-checks send nothing when the remaining reds are conflicts).
Review 2026-10-12: (a) "cross" is one-sided, so with two curb turns into one exit (5-way or skewed nodes) the
order of the connections could free both across each other; a curb connection is now freed only if the ones freed
before it in that phase still pass with it green (unit test "two curb turns into one exit"). (b) The phases-only path
(`W.kerbLights`, tool Apply on unchanged lanes, auto `same`, re-check) now also locks back first for When safe
(`Lights.kerbDiff` counts the net change), so a turn freed earlier by Always no longer stays green into traffic.
(c) Param values: the released rev 3 has no `sqrl_free_turn`, so no player has a stored value; only a dev save/settings
that stored the unreleased On / Off value 2 (Off) now reads as When safe (index 2). No migration needed.
Expected effect: with the game's two-phase default at a 2x2 crossroads every curb turn merges with the cross road's
green straight, so When safe frees nothing there; it helps with per-approach phases, a side road's phase at a T
(the main road's curb turn), and exits where the green stream ends in lanes farther out.

Open (TESTING FK): (1) answered: freed turners do not give way (findings.md 2026-10-12), hence When safe; open:
whether When safe ever frees a turn into conflicting traffic, and what crosswalk entities are (FK 1e); (2) whether the game re-makes phases on its own later (nearby builds, edge
upgrades) and whether `userModifiedTrafficLightStates` protects ours; Smart Lanes keeps the flag as read (setting
it could make the engine keep phases for connections it re-makes, i.e. stale indices); (3) how late AUTO lights can
appear.

### Revised 2026-10-12 (later): When safe allows merges (user decision)
In game (Lights showcase seed 530609, findings roads.md "A connection unlocked in a phase does not give way", "Later
observations") freed curb turners merged into a green stream entering the same exit lane tolerably, and the user
judged that more efficient than holding the turn red; pedestrians were avoided only mostly. So `L.SAFE` now keeps a
curb turn red only for **cross** (a green stream of another approach ending curbward of its exit lane) and **ped**
(a green crosswalk on A or E); a **merge** (a green stream ending in its own exit lane) no longer blocks.
`L.kerbConflict` still classifies (merge before cross before ped, the map agreement test uses it); `kerbPhases` uses
`blockOf` (cross before ped, merges reported apart). Stats: `kept=` never has `merge:` now; `merged` = (curb
connection, phase) pairs freed while a green stream ends in the same lane, logged as `merge_free=<n>` after `kept=`
on SUMMARY, tool WRITE and LIGHTS lines (named merge_free because SUMMARY already has `merged=<seq>` for merged jobs).
Two curb turns into one lane (5-way / skewed nodes) are a merge too and may both go; a crossing pair still never.
In-game node 381095 (Lights showcase, PROBE phases 2026-10-12): phase 1 locked the south right turn D1>A4 although
only C2>A4 (a green straight) ends in A4: now freed (unit test in test_lights.lua, both traffic sides).

Planner (Light phases = Smart Lanes, sl_phaseplan.lua) decision: **consistent, curb turns may merge there too**. Step
4b, after the strict steps 2-4 (seeds, maximal phases, crosswalks): every curb-class connection joins every phase
where its only conflicts with green entries are merges (`opts.kerbMerge`, default true; fan plans excluded). Done on
top of the strict plan, so no straight or crosswalk loses a phase to a merging curb turn and the plan's structure is
unchanged (weights come from the seeds; the calibrated T's cycle drops 85 -> 83 s as its turn phase needs less).
The plan lists the curb turns (`plan.kerb`); `PP.validatePlan` accepts a merge with one of them or with a class
"curb" connection of `M.cls` (a plan read back from a config), never a crossing or a crosswalk conflict, and refuses a
listed connection whose class is known and not curb. So "the plan subsumes When safe" holds again, and Light phases'
tooltip says curb turns also go where they only merge.

### Revised 2026-10-12: default Always (user decision)
"Free curb turn at traffic lights" now defaults to **Always** (mod.json `defaultIndex` 2, `Rules.DEFAULTS.freeTurn` 3;
an index out of range or not an integer also reads as Always). When safe and Off stay as choices. With Always the
SUMMARY / tool WRITE lines carry no `kept=` / `merge_free=` (those are When safe only) and the MODE line says
`free_turn=always`. Tests: test_rules "mod params" / "mod.json params", the default `{}` runs in the Always tests
(test_script "free turn: a lit crossroads ...", test_tool "free turn (tool): Apply frees ..."). Fallback if Always
jams in game: TESTING.md FK "If it fails".


## Exit-lane fan (sl_exitfan zones, 2026-10-13; a measuring mode, never a default)
Request (2026-10-13): a read-only lane audit of Stress Test session `2026-10-13_0205_top-up-61157` found Smart Lanes
twins ~1.9 km/h slower than game twins at lit 2x2 crossroads (6/6 sets), queues on the arms where turners leave. Smart
Lanes pins each turn to one exit lane (curb turn into the exit's curb lane, far turn into its far lane: `ks|sf`, 16
connections); the game lets each turn enter every exit lane (24; PROBE phases_conns node=5921, session
`2026-10-12_0753_sqot-dev-sqrl`). Hypothesis: turners can't pick their downstream lane, so they change lanes after
the junction. The first plan made this the default and let the curb lane of 3+ lanes go straight too (`ks|s|sf`).

Changed before release (coordinator, fuller evidence from session `2026-10-13_0356_top-up-779299`, 12.5 game min, 15
samples per twin, 12 pairs, not jammed): today's Smart Lanes layout BEATS game, 10/12 pairs faster, +3.2 km/h
(p = 0.039): 3x3 +8.0 km/h (3/3), T 2x2 +2.9 (3/3), 2x2 +0.9 (2/1), 3x2 +0.9 (2/1); the earlier 2x2 loss was likely the
rig's lane joins plus saturation. So **the default is unchanged** (the curb-lane straight share is dropped entirely)
and the exit-lane fan lives only in a new zone mode, `sl_exitfan`, for a twin to measure (sl vs sl_exitfan).

Default paths unchanged, proven offline: the sl_cross code without the fan (the new blocks stripped, 1144 lines as
before the change) gave byte-identical connections and curb sets as the new code outside a zone, with
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
  laid out for the game's axis phases). "Free curb turn" is the setting's.
- Which movements share a phase and an exit (game's axis phases, measured: findings roads.md "Default traffic light
  phases"): in the N-S phase the W exit gets N's curb turn and S's far turn (right-hand traffic), the E exit S's curb
  turn and N's far turn, the N / S exits only the opposite straight. A T's main-road phase: one main approach's curb
  turn and the other's far turn into the side road; the side road's phase: its turns alone. Straights never share a
  phase with a turn into the same exit.
- Layout per exit and phase group (X.placeExitLit): movements ordered curb turn, straight, far turn; each gets a
  contiguous range, neighbours share exactly one boundary lane (a merge) and never cross (the curb-side movement never
  ends farther out than the far-side one). Widths: first as many lanes as feeders (no fold where the road has room),
  the spare round robin from the curb side, so the curb turn gets the larger share. A lone movement takes every lane.
  Straights keep today's far-aligned lane-to-lane mapping (the exit's curb lane stays free for a freed curb turn).
  Why the curb turn gets the shared lane: it does not cross the opposing straight, so it flows steadily in its green,
  and its curb lane is the only one a freed curb turn uses in other phases. The game fans both turns into every lane
  (they cross); a crossing pair in one phase never yields in TF3 (findings "A connection unlocked in a phase does not
  give way"), so the fan allows merges only, which the user judged tolerable (findings "Later observations").
  | shape | lane strings | curb turn > exit lanes | far turn > exit lanes | connections (sl / fan / game) |
  |---|---|---|---|---|
  | 2x2 X | `ks|sf` | 1-2 | 2 | 16 / 20 / 24 |
  | 3x3 X | `k|s|sf` | 1-2 | 2-3 | 16 / 24 / 36 |
  | 3x2 X | main `k|s|sf`, side `ks|sf` | main into side 1-2, side into main 1-2 | main into side 2, side into main 2-3 | |
  | 2x2 T | main `ks|s` / `s|sf`, side `k|f` | main into side 1-2; side into main 1-2 | main into side 2; side into main 1-2 | |
- Free curb turn (sl_lights): X.kerbPairs marks the set `kerbLaneOnly`; L.kerbPhases (FREE / SAFE) frees only curb
  connections into the exit's curb lane (position 1); the others (L.splitKerb "held") are locked as LOCK does, red
  where every non-curb road connection of the approach is red, so a freed turn never enters lanes green traffic
  uses and a held one freed earlier is locked back. LOCK (Reset, sl_lock) unchanged. W.kerbLocked counts only the
  freeable ones. SAFE's conflict model (conflictInfo / blockOf) sees the fanned connections of other approaches as
  ever (merge in the same lane, cross curbward).
- Re-checks: an sl_exitfan node whose light was unknown at its write gets a re-check entry (60 / 600 frames, also with
  Free curb turn Off); once a light stands and its lanes are still the rule's, the fan goes out in one proposal with
  the curb phase change (`APPLY src=recheck ... exit_fan=yes`, `WRITE kind=exit_fan`). Lights that appear later than
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

## Ring layout variants (bench) (design 2026-10-13; implemented offline 2026-10-13, not run in game yet)

User request 2026-10-13: a bench that tries several "which lane may go where" layouts at roundabouts at once ("in a
4 lane roundabout the centre lane never gets used", "all 3 lanes turning into all 3 lanes is hectic"); one clear
winner is enough, sample size per variant matters less. Interim micro bench (session `2026-10-13_0837_bench-micro-560595`,
busy map, ~50 % standing): 4-lane ring (`town_new_one_way_medium`, 3+3 arms) Smart Lanes +21 cars/min through (6/6)
but +11 pp standing; 3-lane ring (`highway_new_large`, 3+3 arms) -11 cars/min (0/6), +11 pp standing.

### Evidence from the micro bench log (read 2026-10-13)
- **The twins did not end with the same layout.** Each sl ring was written at its build with `turbo=true fresh=true`
  (3-lane: 8 connections per arm junction, the game's 9; 4-lane: 9, the game's 11). The link builds then re-seeded
  the arm junctions one job at a time, which plans a ring that is not "fresh" (not every junction a seed of the job)
  as plain matched lanes (`turbo=false fresh=false`, 3-lane: 9, 4-lane: 10). Later jobs seeded some rings whole again:
  every 4-lane sl twin (microg7a-12a) ended `turbo=true`, every 3-lane twin (microg1a-6a) ended `turbo=false`
  (last APPLY per zone; e.g. ring 404357: turbo at log line 15104, matched from 16908 on; ring 190204: turbo, matched
  at 16908, turbo again at 17627). So the 3-lane loss vs the 4-lane win is confounded with matched vs turbo, not only
  ring size. The automatic pass's freshness rule (then PLAN "Only nodes the player just built") made the final layout
  depend on the build order (fixed: "Whole rings in the automatic pass").
- No AUDIT finding at any micro ring (the audit sees no avoidable squeeze / shared / weave at ring junctions: the
  ring rules' merges are forced, and weave is not looked at on ring segments). The audit cannot rank ring layouts;
  only the traffic log can.
- What "all 3 into all 3" is at our rings: in matched and turbo every ring lane that has an exit lane leaves at every
  arm (o_i -> x_i), and every entry lane joins its ring lane (e_j -> o_j). A vehicle leaving from o3 cuts across o1
  and o2 traffic that continues, at every arm; an entering vehicle bound for o3 cuts across o1 and o2. On a 4-lane
  ring with 3-lane arms nothing enters or leaves o4: it is used only by lane changes on the ring segments (the centre
  lane the user sees empty).

### Variants (zone modes; outside their zones nothing changes, byte for byte)
Notation per arm junction, lanes curb first (o1 = outer ring lane, x1 / e1 = the arm's curb exit / entry lane, as in
"The rule"): R ring lanes, E exit lanes, N entry lanes, X = min(E, R). Driving side: the rules are written in these
curb-first orders, which sl_ring derives from geometry (CW rings and left-hand traffic are the mirror, no extra
rule, as today). Ramp arms (one-way, E or N = 0) use the same rule for the side they have; the ramp-entry rule
(rule 5, a narrow ramp entry takes its own ring lane) applies where it does today, i.e. in the turbo-based variants
sl_rturbo and sl_rspread (as variant "turbo"), not in sl_rmatch (as "matched") and not in the others. Rings of 1 lane: as today
in every variant. Tram connections: kept (Rules.mergeTram).

Common to every variant zone (fixes the confound above): the ring is planned and written **whole** whenever a seed
of the job lies on it, every arm junction inside the zone included, with the variant's rule, no freshness
downgrade; so a twin's layout is the same after any build order. Junctions the rules skip (`skip`) stay as today.

| # | zone mode (ab) | rule at an arm junction (circulate / exit / enter) |
|---|---|---|
| 1 | `sl_rturbo` | today's turbo, fixed: o1 exit-only (-> x1) at junctions with exits when every exit of the ring has >= 2 lanes and R >= 2, else o1 exits and continues; o_i -> x_i and continues for 2 <= i <= X; E > R: o_R also -> x_(R+1)..x_E; o_i (i > X) continue only; e_j -> o_min(j,R) |
| 2 | `sl_rmatch` | today's matched (what the 3-lane twins ended with): as 1 without exit-only (every o_i continues) |
| 3 | `sl_rout1` | only the outer lane exits, fanned: o1 -> x1..x_E and continues; o_i (i >= 2) continue only; e_j -> o_min(j,R) (the game's exits with Smart Lanes' 1:1 entries) |
| 4 | `sl_r2exit` | the two outer lanes exit: E >= 2: o1 -> x1 only, o2 -> x2..x_E and continues; E = 1: o1 -> x1 and continues, o2 continues; o_i (i >= 3) continue only; e_j -> o_min(j,R) |
| 5 | `sl_rspiral` | spiral by destination (turbo-roundabout style): D = min(R, A) (A = ring junctions with exits, the own arm's U-turn included; corrected in the implementation from A - 1, which made U-turns unreachable). At a junction with exits: o1 -> x1..x_E only (exits only); o_i -> o_(i-1) for 2 <= i <= D (shift one lane outwards); o_i (i > D) continue; when D < A, o_D also continues (the farther exits by circling); e_j -> o_min(j, D) (extra entry lanes fold into o_D) and the innermost entry lane e_N also -> o_(N+1)..o_D (the farther exits and the U-turn). At a junction without exits (entry only): every o_i continues, entries as above. Entry lane j = the j-th exit downstream |
| 6 | `sl_rspread` | turbo (1) plus the centre lanes: R > X: o_i -> x_X and continue for X < i <= R (the inner lanes leave into the innermost exit lane: a merge at the exit), e_N -> o_N..o_R (the innermost entry lane splits into the inner lanes); R <= X: as 1 |

Dropped / folded in: "fewer entry lanes" (3 entry lanes into R - 1 ring lanes, the inner lane reserved for
circulating) folds two entry lanes into one ring lane at the give-way (a merge inside the junction for every entry,
the thing "never squeeze" avoids elsewhere); a 7th mode `sl_rfewin` if wanted (e_j -> o_min(j, R - 1) for R >= 3,
exits as 1). The game's own layout is the `game` twin; `sl` twins keep the automatic pass (whole rings since
2026-10-13, "Whole rings in the automatic pass").

Connections per arm junction (A = 4 arms, 3+3 arms unless noted; game = the engine default, findings / probe):

| ring | game | rturbo | rmatch | rout1 | r2exit | rspiral | rspread |
|---|---|---|---|---|---|---|---|
| 2-lane, 2-lane arms | 6 | 5 | 6 | 6 | 5 | 6 (D = 2: o1 -> x1, x2; o2 -> o1 + continues; e1 -> o1, e2 -> o2) | 5 |
| 2-lane, 3-lane arms | 8 | 7 | 8 | 8 | 7 | 8 | 7 |
| 3-lane, 3-lane arms (micro rb3) | 9 | 8 | 9 | 9 | 8 | 9 | 8 |
| 4-lane, 3-lane arms (micro rb4l) | 11 | 9 | 10 | 10 | 9 | 10 | 11 |
(rspiral 2-lane x 3-lane arms: o1 -> x1..x3, o2 -> o1 and continues (D = 2 < 4), e1 -> o1, e2 and e3 -> o2. 4-lane x
3-lane arms: o1 -> x1..x3, o2 -> o1, o3 -> o2, o4 -> o3 (D = 4 = A, no circling), e1 -> o1, e2 -> o2, e3 -> o3 and o4:
the centre lane carries the U-turn. The exact role lists of every variant, size and side are test_ringvar.lua's WANT.)
Equal counts are not equal layouts: on the 3-lane ring `rout1` has the game's 9 connections but not the same ones
(micro v2 logged APPLY there, 2026-10-13_0923_bench-micro-331773); only on the 2-lane ring with 2-lane arms is it
the game's layout (SKIP same).

What each one creates inside the junction and why it might be faster:
1. **rturbo**: every ring lane but the innermost leaves (o2.. exit across the lanes outside them that continue);
   exit-only o1 makes the curb entry lane a "next exit" lane. Destinations use 1 lane each except straight-on and
   far ones, which share the inner lanes; the inner lanes carry only exiting-at-some-point traffic. Baseline (the
   4-lane result).
2. **rmatch**: as 1, the outer lane also circulates: more capacity for passing traffic, more crossing at every exit
   (o1 continuers cut by o2 / o3 exiters). Baseline (the 3-lane result).
3. **rout1**: no exit crossing at all (only o1 leaves, splitting into every exit lane); inner lanes must change
   outwards on the ring segments before their exit (weaving on segments, as the game's default). Entries 1:1 (no
   "3 into 3"). Fewer conflict points per junction, less ring capacity used for exits; tests whether exit crossings
   or segment weaving cost more.
4. **r2exit**: a middle ground: two lanes leave (o1 is exit-only, so o2's exit crosses no continuing stream), the
   inner lanes only circulate. With 3-lane arms the innermost exit lane x3 is fed from o2 too.
   Expected: turbo's exit capacity without the inner-lane exit crossing.
5. **rspiral**: no lane change needed anywhere: the entry lane picks the exit, each junction shifts every spiral lane
   one outwards, the outer lane always leaves. No exit crossing (only o1 leaves), the shift paths are parallel (no
   crossing among themselves); entries merge into their lane with the shifted stream (the give-way, as today).
   Uses o2..o_D for straight / left traffic, so the inner lanes carry the long trips. Risk: one ring lane per
   destination (capacity per destination = 1 lane), and the pathfinder must pick the entry lane by exit (it does: lanes
   are only connected along valid paths). Unreachable exits never happen (D < A - 1: the innermost spiral lane also
   circulates). 4-lane ring, 4 arms: D = 4, o4 carries the U-turns (fed by the innermost entry lane).
6. **rspread**: uses the centre lane of wide rings: the innermost entry lane splits into the inner lanes, the inner
   lanes merge into the innermost exit lane. Creates one merge per exit (R - X + 1 lanes into x_X) and the entry split
   (no conflict). Tests whether the empty centre lane is worth a merge at the exit.

Bench: twins per ring type (rb3 = 3-lane `highway_new_large`, rb4l = 4-lane `town_new_one_way_medium`, both 3+3 arms;
plus rb2 = 2-lane with 2+2 arms for the common case): `game`, `sl`, and the six modes, one set each (8 twins per
set), the user's call on repeats. Report per mode vs game and vs `sl_rturbo`.

Zone contract: ab names `sl_rturbo`, `sl_rmatch`, `sl_rout1`, `sl_r2exit`, `sl_rspiral`, `sl_rspread` (each <= 12
characters of [%w_]), accepted by sl_zones (AB_SET, AB_OPTIONAL, zmodes); `by_ab` appends them after
`,sl_keeplights:<n>` in that order, each only when n > 0 (later modes: sl_rsplit, sl_rmid after them; sl_rmid2,
sl_rturbo_in after `,sl_auto:<n>`, "Ring lane use"). Lights: the setting's ("No lights at roundabouts" On:
switched off after the lane write as in `sl`); with no stress on lights here, `sl_keeplights` stays its own mode
(one mode per zone). Crossroads, slip and drop nodes in such a zone: as `sl`.

Logging: ring `APPLY ring=.. node=.. ... layout=<mode> ... zid=` (layout= added only inside these zones), SUMMARY
`zone_ring=<rings planned with a variant>`; SKIP / same lines as for every zone node. AUDIT stays (the variants'
exit merges in rspread are forced by design: counted as forced shared, never avoidable).

Crash safety: ring junctions are normally unlit (Smart Lanes removes their lights; AUTO lights can stand before the
lights-off lands, and an sl_keeplights-like user may keep them), so every variant write goes through the existing
sendConfigs / W.remapLights path (lockedLanes re-pointed and range-checked when a light has phases; no light: no
phases written). One proposal per ring (all its junctions), remove + add per node (never remove-only), only nodes
with a config (`no_config` skip), never a node with a proposal in flight (busyNode). Rules.reachability per variant in
the tests: every entry reaches every exit with node connections plus lane changes (laneChange = true for rmatch /
rturbo / rout1 / r2exit / rspread, false for rspiral, which needs none); no U-turn connection; no two connections of
one stream crossing except where the table says (rspread's exit merge, the inherent give-way).

Tests (when implemented): per variant the connection lists for R = 2, 3, 4 with E = N = 2, 3, both driving sides
(mirrored worlds), ramp arms (E or N = 0), A = 3 and 4 arms; the counts table above; reachability; a variant zone
writes the whole ring and gives the same connections after builds seeded in different orders (the confound);
outside the zones byte-identical to today (all existing tests, plus the pristine comparison as for sl_exitfan).

### Implemented (2026-10-13)
- sl_rules: `M.RING_VARIANTS`, `M.variantConns(v, variant, ctx)`; `planRing` takes a variant name (ctx: the ring's
  turbo qualification as if fresh, A = junctions with exits; `res.variant`). sl_zones: the six modes (AB, AB_SET,
  AB_OPTIONAL, zmodes; by_ab after `sl_keeplights` in the table's order, each only when > 0). sl_lanes.script: a ring
  with a node in such a zone (`ringVariant`: the first ring node in one) is planned with every ring node as seed and
  that variant; its APPLY lines gain `layout=<mode>` (before `zid=`), SUMMARY `zone_ring=<rings>` (after
  `zone_keeplights=` / `lights_kept=`). sl_toolcore: Apply / the badge on a ring in such a zone use the variant
  (APPLY src=tool layout=<mode>); Reset stays the game's model; the result text shows "Smart lanes" (no new string).
- Tests: test_ringvar.lua (exact roles per variant x R 2/3/4 x arms 2/3 x ccw / cw x both traffic sides, reachability:
  spiral without lane changes, the others with; the counts table; spiral depth on 3 arms; 1-lane rings; seeds alone
  give the whole-ring plan; unknown names skipped), test_script (zone writes layout= / zone_ring=, a later one-arm build
  changes nothing; outside the zones today's rule incl. the flip), test_tool (Apply in a zone), test_zones (by_ab).
  Default unchanged: a one-off comparison against sl_rules with the variant code stripped gave identical planRing
  results for two_lane / matched / turbo / engine / game over 6480 ring plans (1-4 lane rings, 3-5 arms of three
  templates, splitters, both directions and sides, three seed patterns); all earlier tests unchanged.
- Bench contract: ab names as above; `[SQRL] APPLY ring=<key> node=<n> lanes= dir= exits= entries= turbo= fresh=
  before= after= [entry= why=] layout=<mode> [zid=<id>]`; `SUMMARY ... zone_ring=<n>`; a junction already right:
  `SKIP kind=ring ring=<key> node=<n> reason=same [zid=]` (as every zone node).

### Mid-node spiral (sl_rsplit) (2026-10-14; implemented offline, not run in game yet: TESTING.md "RS")
User request 2026-10-14 (screenshot of the Sheet 4 ring `bench_rb2t`): "spiral, but have the outer to inner lane change
happen on a node between the arms, so that traffic entering doesn't overlap as much". In `sl_rspiral` on a 2-lane ring
with 1-lane arms every move happens at the arm junction: o1 -> x1 (exit only), o2 -> o1 (shift out) and o2 -> o2, and the
entry e1 -> o1 **and** e1 -> o2, so an entering car bound for a far exit crosses the shifting o2 -> o1 stream inside the
junction. `sl_rsplit` keeps the spiral and moves the inward lane change off the junction:
- **Arm junction**: as sl_rspiral (o1 exit-only into every exit lane; o_i -> o_(i-1) for 2 <= i <= D = min(R, A); o_D also
  straight on when D < A; o_i straight for i > D; no exits: every lane straight), but entry lane j joins only o_min(j, D):
  the entering traffic merges into the outer lane beside the shifted stream and crosses nothing. Bench ring: 4
  connections (sl_rspiral 5, game 4 with e1 -> o1, o2).
- **Mid node** (the plain ring node half way along each stretch between two ring junctions): every lane straight on, plus
  o_i -> o_(i+1) for i < D (the move inwards). Bench ring: o1 -> o1, o1 -> o2, o2 -> o2 (3; the game's 2). A car that
  entered in o1 stays for the next exit or moves in here for a farther one; the next junction shifts it out again.
- Which way at the mid node: inwards only. Inward and outward there (o1 -> o2 and o2 -> o1) would cross at the node;
  outward only (entries into both lanes at the junction, o2 -> o1 at the mid node) keeps e1 -> o2 at the junction, the
  overlap the user wants gone. Inward-only is the user's wording and crosses nowhere (merges only: the entry with the
  shift at the junction, o1 -> o2 into o2 at the mid node). Reachability holds without lane changes on segments (tested).
- **Mid nodes**: `Rules.splitMids` takes, per stretch, the plain node nearest half way by segment length; a stretch
  without one (square_roundabouts builds them only with its dev override `sqrb_dev_ring_mid`, Stress Test Sheet 4 v3),
  a 1-lane ring or a ring without junctions: the junctions get `sl_rspiral`, no plain node is written (`res.layout`,
  `res.split` = no_mid_nodes | one_lane_ring | no_junction). Other plain nodes of a stretch stay the game's.
- Every other rule and variant plans junctions only, as before (tested on a ring with mid nodes): the game / sl /
  sl_rspiral twins drive the same geometry with their mid nodes straight on, as the game makes them.
- Ring detection with mid nodes: unchanged. `sl_ring` already treats a ring node with only the two ring segments as
  kind "plain" (`nodeView`), `findRing` allows 32 segments and 45 degree kinks (8 segments, 45 degrees between nodes on
  the bench ring: the tangents are continuous), and the slip pass skips ring nodes (`job.onRing`), so a mid node is never
  taken for a lane drop.
- Writes: the mid nodes go into the ring's one proposal (remove + add each, `W.sendConfigs`), never lit (Lights.ringNodes
  takes arm junctions only), VERIFY counts them. Whether the game keeps a lane change written at a 2-edge node of a
  one-way road and whether cars use it: not known (Smart Lanes' lane-drop writes at 2-edge nodes landed, `APPLY
  kind=drop ... before=4 after=6`, e.g. session `2026-10-12_2244_top-up-4951`, but those are fans, not lane changes).
- Logs: APPLY at a mid node `... exits=0 entries=0 ... before=2 after=3 layout=sl_rsplit mid=yes zid=`; per ring one
  `RSPLIT ring=<key> node=<key> mids=<n> nodes=<ids> zid=` or `RSPLIT ... mids=0 fallback=sl_rspiral reason=<why> zid=`
  (APPLY lines then say layout=sl_rspiral). Tool: Apply in an sl_rsplit zone writes the mid nodes too (APPLY src=tool
  layout=sl_rsplit); its badge counts junctions only, and Reset restores the junctions only (the mid nodes keep the
  lane change: bench-only mode, accepted).
- Files: sl_rules.lua (RING_VARIANTS, variantConns, splitMidConns, splitMids, planRing), sl_zones.lua (mode),
  sl_lanes.script.lua (RSPLIT, mid=yes, zid on RSPLIT). Tests: test_rsplit.lua (roles for R = 2/3/4 and both sides,
  reachability, fallbacks, nearest-half-way pick, seeds / same / tram, other rules untouched, the script's lines and
  write), test_tool (Apply in a zone), test_ringvar / test_zones / test_script (the 7th mode).

### Default: the mid-node spiral (rev 6, 2026-10-14, user decision; implemented offline, not run in game yet: TESTING.md "DS")
**Since 2026-10-14 (user decision) the default here is `sl_rmid`, not `sl_rsplit`**: no lane change at the arms (o1 -> x1
only, o2 -> o2 only, e1 -> o1 only; 3 connections), every lane change at the mid nodes (both lanes straight + o1 <-> o2;
4). The split spiral's inner -> outer change at the arm merged where the entries join (the user's screenshot); mid-only
vs split: s4 v4 12.2 vs 12.4 km/h, 87.8 vs 80.3 cars/min; s4 v5 12.4 vs 11.4 km/h, 91.8 vs 84.7 cars/min (RESULTS.md).
Without a mid node on every entry-to-exit stretch (a split refused) the whole ring keeps `sl_rspiral`. Reachable without
lane changes on segments on 3-6 arms, splitter rings, entry-only / exit-only ramps (test_rmid "the default ...").
`ringForm` knows "mid" (and the earlier "split"). Log: `layout=sl_rmid default=one_lane_exits`. The text below describes
the rule as first built with sl_rsplit; read sl_rmid where it says the default writes sl_rsplit.
Results (RESULTS.md "Verdicts so far"): 2-lane ring, 4 one-lane town street arms, Sheet 4 v3 (mid-node ring, 1 set):
sl_rsplit 12.4 km/h / 85.9 cars/min, game 10.2 / 71.4, sl_rspiral 10.0 / 76.0, sl (matched, `narrow_exit`) 8.1 / 62.8;
v2 (no mid nodes): spiral 8.7 / 66.9 > game 8.1 / 62.8 = sl 8.1 / 61.7. User: "make split spiral lane change at mid
nodes default for that situation". The mid nodes: Smart Lanes adds them itself (next section; an R&I menu param for them
did not work, the menu's cleanup joins short ring pieces away, docs/findings/roads.md).
- **Rule** (`Rules.spiralDefault`, planRing for "two_lane" (automatic pass, zone mode `sl`) and "turbo" (the tool's
  Apply)): a 2-lane ring with an exit, no skipped junction, every exit exactly one lane (ringPlan reason `narrow_exit`
  with no 2+-lane exit) gets sl_rsplit's junctions and mid nodes; without a mid node on every entry-to-exit stretch
  sl_rspiral. `res.default = true`, `res.defaultWhy = "one_lane_exits"`, `res.layout`. Everything else as before: rings
  where turbo qualifies (2-lane ones: matched since 2026-10-15, next section), mixed exits (a 1-lane ramp beside 3-lane arms: the Roundabout Interchange keeps its ramp rules),
  3- and 4-lane rings (micro v2: turbo best on 4 lanes, spiral worst), 1-lane rings. Sheet 4 v4 may change that later.
- The automatic pass writes the mid nodes with the ring when every arm junction is a seed (its whole rings); the tool
  with a ring Apply (seeds every ring node), not with one junction. Ramp own-lane entries are off on such rings (the
  spiral plans the entries). The hand-edit guard knows the spiral forms (`Rules.ringForm` "split" / "spiral", ctx A), so
  a later build at one arm re-plans the whole ring, not "hand_edit".
- Logs: ring APPLY lines gain `layout=sl_rsplit|sl_rspiral default=one_lane_exits` (outside zones too), mid nodes
  `mid=yes`; one `RSPLIT ring= node= mids= per_stretch= nodes=` (or `mids=0 fallback=sl_rspiral reason=`) per plan.
- Zone modes: `sl` follows the new default (it is "what Smart Lanes does"); `sl_rmatch` is the old default on these rings
  (matched lanes, written whole) for a comparison; `sl_rspiral` / `sl_rsplit` / `sl_rmid` unchanged.
- Tool (the Crossing Tool can't pick a plain 2-edge node, findings roads.md): the lane view draws a selected ring's mid
  node connections itself (sl_midview: one cubic spline per connection, LEAD 6 m either side of the node, lane positions
  from the laneConfig `offset` (sl_ring lanesFromConfigs), orange; lane changes bright, straight on faint; in the same
  EdgeRenderable as the markers; the NodeViewer can't, it asserts with more connections than network edges); the badge
  counts them (`ringStatuses`: a ring is Smart lanes only when every mid node of the plan holds its connections, Game
  default only when every plain node is straight on); Reset ("engine") gives plain ring nodes with more than straight-on
  connections the game's straight lanes; the ring's detail line reads "Apply or Reset: the roundabout and its lane
  changes between the arms" when it has some (13 languages); the Apply result counts junctions only, and gives no
  "no exit-only outer lane" reason for the spiral. The spline drawing is untested in game (api fields from the tealdef).
- Files: sl_rules.lua (spiralDefault, planRing, ringForm, autoSeeds, splitMids: only entry-to-exit stretches need a node),
  sl_lanes.script.lua (APPLY / RSPLIT fields), sl_toolcore.lua (ringStatuses, fillRing midNodes, highlight lines, Apply
  result), sl_midview.lua (new), sl_ring.lua (lane offset), sl_pick.lua (detail), sl_tool.script.lua (spline edges),
  strings.json. Tests: test_rsplit.lua "default:" / "sl_midview" / splitter, test_tool "default spiral (tool)", and the
  old-default expectations in test_layouts / test_rules / test_wholering updated (2-lane rings with one-lane arms).

### Default: matched lanes on 2-lane rings with wide exits (rev 8, 2026-10-15, user decision; implemented offline, not run in game yet: TESTING.md "MD")
Evidence: bench s5 (`2026-10-15_0602_bench-s5-ring-34019`, RESULTS.md verdict "2-lane ring, 2-lane arms"): on a 2-lane ring
with 2-lane country arms, matched lanes (`sl_rmatch`) beat turbo (`sl_rturbo`, what the default wrote there until now) in all
3 mixes: 89.1 vs 73.8 cars/min (game 58.6), straight mix 91.9 vs 70.7 with 19 vs 33 % standing. Turbo puts 79-85 % of the
ring's cars in the inner lane (o1 after an arm carries only cars for the next exit, so every car going further queues for
e2 -> o2: the user's ring 282381, "Ring lane use" below); matched uses both about evenly. User: matched as the default there.
- **Rule** (`Rules.matchedDefault`, planRing for "two_lane" and "turbo"): a 2-lane ring where turbo would qualify (an exit,
  no skipped junction, every exit >= 2 lanes; fresh or not) gets `twoLaneConns(v, { turbo = false })` on every junction:
  `res.turbo = false`, `turboReason = "two_lane_ring"`, `res.default = true`, `defaultWhy = "two_lane_exits"`,
  `res.layout = "matched"`. Exits of 3+ lanes on a 2-lane ring count as wide (o2 fans out over x2..x_E, as before).
- **Unchanged**: 3- and 4-lane rings keep turbo (bench s5 lu4: turbo best); 2-lane rings with one-lane exits keep the
  mid-node spiral (`sl_rmid`; its heavy-traffic check is prepared separately); mixed exits on a 2-lane ring (a 1-lane
  ramp beside 2+-lane arms) were matched lanes already (`narrow_exit`) and stay so. Zone modes are not affected
  (`sl_rturbo` still builds the turbo twin on 2-lane rings, `sl_rmatch` the matched one); zone mode `sl` follows the
  default, so an `sl` twin on a 2-lane ring with 2-lane arms is now matched.
- **Ramp entries (rule 5)** stay on these rings: an entry-only 1-lane ramp takes o1 and the circulating lanes zip into
  o2, only when the next junction downstream has an exit of >= 2 lanes (always true here) and reachability holds. That
  is the Roundabout Interchange's form (the user's own hand edit), already combined with matched lanes on its mixed
  rings; the zip sits right before an exit both lanes can use. Not measured on its own.
- **No mid nodes**: the matched default writes junctions only (no `RSPLIT`, no split, plain nodes untouched).
- **Existing saves**: Smart Lanes plans only rings a build touches or the player presses Apply on, so 2-lane rings
  written turbo by rev <= 7 keep turbo until then. When a build touches one arm, the hand-edit guard (`Rules.ringForm`)
  reads the other junctions as "turbo" (ours), so the whole ring is re-planned to matched in one proposal, never
  `SKIP reason=hand_edit`. The tool's badge on such a ring reads not Smart lanes (the plan differs) and Apply is
  enabled; after Apply it reads Smart lanes.
- **Tool**: no new text (the layout is still "Smart lanes"); Apply's result gives no "no exit-only outer lane" reason
  for this default (`plan.default`, as for the spiral).
- **Logs**: automatic APPLY lines `turbo=false fresh=true ... layout=matched default=two_lane_exits` (outside zones too);
  tool APPLY `turbo=false turbo_reason=two_lane_ring`. No `RSPLIT` line (the script's RSPLIT is the spiral's only).
- Files: sl_rules.lua (matchedDefault, planRing, ringForm comment), sl_lanes.script.lua (RSPLIT only for the spiral; APPLY
  comment). Tests: test_rules "ring decision table" (4 traffic sides x 3-6 arms: 2-lane/2- and 3-lane exits matched with
  node-only reachability, 3-/4-lane turbo, 2-lane/1-lane exits sl_rmid with mid nodes, mixed matched), test_layouts
  "2-lane ring with 2-lane exits", test_wholering "written turbo by an earlier version", test_tool "matched default
  (tool)", test_rsplit "script: a 2-lane ring with 2-lane exits". Expectations moved from turbo to matched (2-lane rings
  with 2+-lane exits): test_rules probe node 19132 (5 -> 6 connections, `20359:1>19600:2` added), splitter islands,
  two ramps (the 3-lane arm after a ramp gains `i1>o1`); test_layouts "Turbo equals the automatic rule" (now on the
  4-lane probe ring); test_wholering qualifying rings (R = 2 matched) and the Roundabout Interchange with a 2-lane
  off-ramp; test_rsplit "no spiral where it does not apply" (2-lane exits and 2-lane ramps: `two_lane_exits`; a 1-lane
  ramp case added) and the 2 + 2 splitter ring; test_audit turbo_gap (now on a 4-lane ring).

### Smart Lanes adds the mid nodes (rev 6, 2026-10-14, user decision; offline-tested, not run in game yet: TESTING.md "DS")
Placed from the construction menu, a 2-lane ring's plain nodes between the arms are joined away on XS-M rings (16-24 m
pieces; findings roads.md "Menu placements join short ring pieces"; a 4 degree corner did not help), so R&I can't deliver
them. Smart Lanes splits the ring itself (`sl_split.lua`, `W.sendSplit`):
- **When**: the automatic pass's ring step (and an `sl` zone), when the default rule picks the spiral (`plan.default`)
  and `Rules.splitMids` finds a stretch from an entry to the next exit without a plain node (`plan.split ==
  "no_mid_nodes"`); the tool's Apply on the whole roundabout too. Not in ring layout variant zones (the bench builds its
  mid nodes itself), except `sl_rmid2` (since 2026-10-15, "Ring lane use"; the rule is `plan.splitWanted`), and not on
  one junction alone.
- **What**: each such stretch is one edge between two neighbouring junctions (`Split.edges`); it is removed and its two
  exact halves added (a cubic Hermite's sub-curve on [0, .5] / [.5, 1]: the end points and derivatives scaled by .5, so
  the shape is identical; tested at 11 points), with a new node at the middle. Every field of the edge is copied (type,
  typeIndex, laneConfigs, roadType, roadTemplate, roadStyle, edgeDecorations, roadDevelopmentLocked, distance per half,
  street precedence at its old ends, the PLAYER_OWNED component), as parallel_tracks' road pieces. One proposal per ring:
  edgesToRemove, edgesToAdd (temp ids -1..-2n), nodesToAdd (-2n-1..), the old end nodes' configs re-pointed (connections
  and crosswalks in the same order with the halves' ids: the light phases still index them; findings "Removing an edge
  while a remaining node's lane connections still name it throws"), and the new nodes a straight-on config (every node
  of a script proposal gets one: findings "Script link roads without node configs"). Context cleanupStreetGraph = false.
- **Refused** (logged `SPLIT ring= node= len= refused=<why>`, then the spiral without mid nodes as before): an edge object
  on the piece (`edge_objects`: a stop, a signal), a bridge or tunnel (`bridge_tunnel`), tram tracks (`tram`), an edge a
  construction owns (`construction`), a half under 8 m (`short`), a junction with a proposal of ours in flight (`busy`),
  more than 8 edges (`too_many`), the cap (`cap`: Split.MAX_PER_RING = 2 splits per ring and session), no config at an end
  node (`no_config`).
- **Two steps**: the split job writes no lanes on the ring (it returns after `SPLIT ... edges= nodes_added=`); the split's
  answer (`WRITE kind=split ring= success=`) queues the ring's junctions again (`noSplit`: that pass never splits; a
  refused split gets the spiral without mid nodes), and that pass writes the mid-node spiral with the real node ids
  (`RSPLIT ... mids=4`, APPLY, VERIFY). The split's own build event may queue a job too; both merge or the second finds
  everything `same`. The tool re-applies 5 frames after the split answered (`C.reapply`, `C.noSplit`).
- **Reset** gives the mid nodes the game's straight-on lanes; it never merges them back (not needed: a plain node with
  straight-on lanes is what the game itself builds on long rings).
- **Save safety**: as every Smart Lanes write: only rings a build touches or the player presses Apply on; nothing on load.
  The nodes stay when the mod is removed (ordinary streets).
- Open: whether the engine keeps the split pieces (cleanupStreetGraph = false kept 16 m pieces in the bench), and whether
  a later player build next to the ring joins them again (then the next pass splits once more, at most twice a session).
- Tests: test_split.lua (exact halves, Split.edges incl. splitter rings and short rings, the job flow with the fake
  game applying the street proposal: 8 edges on the old curve, re-pointed configs, the spiral written and verified,
  refusals, a refused split and the cap, rings never split), test_tool "splits its edges first".

### Mid-node lane changes (sl_rmid) (2026-10-14; implemented offline, not run in game yet: TESTING.md "RS" step 7)
sl_rsplit ran in game (Sheet 4 v3, 2026-10-14: `mids=4`, 4 `APPLY ... mid=yes before=2 after=3`, `VERIFY same=8 nodes=8`).
User, on the Crossing Tool at its arm junction (the inner lane's o2 -> o1 crossing where the entry joins o1): "try one
where we don't allow the inner to outer merge at an intersection; they would do it mid-node". `sl_rmid`:
- **Arm junction: no lane change at all.** With exits: X exit-only lanes, X = min(E, floor(R / 2), m) (at least 1; m =
  the fewest mid nodes on one stretch): o_i -> x_i for i < X, o_X -> x_X..x_E (a fan), o_i (i > X) straight only;
  without exits every lane straight. Entries lane for lane, e_j -> o_min(j, R): the outer entry lanes join the
  exit-only lanes (no ring stream there), the inner ones their circulating lane (the give-way); nothing crosses.
  Bench rings: 2-lane: o1 -> x1, o2 -> o2, e1 -> o1 (3; sl_rsplit 4, game 4); 3-lane (1 mid node): o1 -> x1..x3, o2, o3
  straight, e_j -> o_j; 4-lane (2 mid nodes): o1 -> x1, o2 -> x2 and x3, o3, o4 straight, e_j -> o_j.
  Why X: the outer half of the ring leaves, the inner half circulates (all lanes carry traffic); and a car that entered in
  o1 for a farther exit must reach o_(X+1) on the stretch's m mid nodes (one lane per node), so X <= m. The outer lane
  straight on too? No: o1 after a junction carries only entering cars; a straight o1 would put through traffic into the
  entry's lane; every trip still reaches its exit without it (tested).
- **Mid node: both ways between every pair of neighbouring lanes.** Every lane straight, o_i -> o_(i+1) and
  o_(i+1) -> o_i for i < R. Bench 2-lane ring: o1 -> o1, o1 -> o2, o2 -> o1, o2 -> o2 (4; the game's 2). The two lane
  changes of a pair cross at the node: whether the engine accepts crossing connections at a 2-edge node (and how cars
  yield there) is open; VERIFY `same=` settles acceptance.
- **Moves per stretch:** one lane per mid node, so m per stretch. With X <= m an outer-lane entrant always reaches the
  circulating lanes before the next arm; the innermost lane reaches an exit lane on one stretch when R - X <= m (2-lane
  ring with 1 node: yes; 4-lane with 2: o4 -> o2 yes; 3-lane with 1: o3 -> o1 no, it leaves one arm later). One node per
  gap was too few for the 4-lane ring (X = 1: one exit lane for three arm lanes), 3 per gap grow the square_roundabouts
  ring from 10 to 35 m inside; 2 (grown to 20 m) give X = 2 and both moves. The 3-lane entry ring takes only 1 (its 30 m
  arms leave ~1 m of free ring beside a second node).
- **Mid nodes = every plain node of a stretch** (Rules.splitMids, also for sl_rsplit: one inward move per node).
- Reachability without lane changes on segments, every entry lane -> every exit (the U-turn included), tested: 2-, 3-
  and 4-lane rings with 1-3 mid nodes per stretch and 1- to 3-lane arms (both directions and traffic sides), 2 and 3
  arms, an exit-only and an entry-only ramp (the entry-only junction keeps o1 straight), one exit only.
- Mid nodes, fallback (`sl_rspiral`, `RSPLIT ... mids=0 fallback=sl_rspiral reason=..`), logs (APPLY `mid=yes`, here
  `after=4`; one `RSPLIT` line per plan, the same kind as sl_rsplit's), tool behaviour: as sl_rsplit
  (`Rules.MID_VARIANTS`). Tests: test_rmid.lua.

### Whole rings in the automatic pass (fixed 2026-10-13, user decision; not run in game yet)
Before, the automatic pass wrote only the junctions a build seeded and turned the exit-only outer lane off when not
every ring junction was a seed (`not_fresh`): links (and town growth, if town builds reach the pass: jobs need
`playerInitiated`, sl_lanes.script.lua handleBuild; unverified, TESTING.md H2) touching one arm at a time left rings matched or
turbo by build order (micro bench session `2026-10-13_0923_bench-micro-331773`: turbo beat matched clearly on 4-lane
rings, ~97-101 vs 82 cars/min, and was never worse on 3- / 2-lane rings; the plain sl twins ended turbo or matched by
build order). The rule now (`Rules.autoSeeds`, sl_lanes.script `ringStep`):
- A ring with a seed on it is planned whole: every **arm** junction of the ring is a seed (skipped and plain ring
  nodes are not added), so `planRing("two_lane")` is fresh and turbo follows the ring's own qualification (>= 2 ring
  lanes, no skip node, an exit, every exit >= 2 lanes; since 2026-10-15 a 2-lane ring then gets matched lanes, "Ring
  decision table"). Every build order ends with the same lanes.
- Hand-edit guard: an arm junction the build did not seed (or seeded quiet, since 2026-10-17: "Nearby junctions stay as
  they are") is added only when its current road connections
  (`Rules.ringForm`, compared order-insensitively, tram ignored) are Smart Lanes' (turbo or matched lanes, the ramp's
  own-lane entry), the engine default model, or none. Otherwise (a Crossing Tool edit, or a form the model does not
  know: an engine default it misses, a bench variant layout) the ring keeps the build's seeds as before (matched
  lanes there, `fresh=false`, `not_fresh`) and that junction is left alone: `SKIP ring= node= reason=hand_edit`
  (SUMMARY `skips=hand_edit:n`). Turbo is a ring-level assumption (every exit junction's outer lane exits only), so
  it is never applied around a junction we may not write. Seeds that are hand-edited are rewritten, as before.
- A junction the job would add that a proposal of ours still names (an earlier ring write or lights-off) is not
  read: the job waits on that node and tries again next frame (`WAIT kind=ring job= ring= node=`, once per job and
  ring; bounded by heldNode's INFLIGHT_TIMEOUT), so the added junctions are always read after our last write
  landed. This closes the job gate's gap (it checks only the job's nodes) for the nodes the job adds.
- Same write path as the ring-variant zones (one proposal per ring, `sendConfigs`: config read in the frame of the
  write, remove + add per node, `no_config` skip, lights re-pointed by W.remapLights).
- Lights ("No lights at roundabouts and ramps"): switched off only at the seeds (not the quiet ones), as before; an added junction keeps
  its light state (a light the player set there stays). Variant zones: the whole ring, unchanged.
- The tool (sl_toolcore: Apply / Reset / the badge) calls `planRing` directly and is unchanged.
- Log: APPLY unchanged (`fresh=true` now also for a ring this way); new `SKIP ... reason=hand_edit` and `WAIT`.
- Tests: test_wholering.lua (2- / 3- / 4-lane rings both directions, every one-arm order ends turbo (2-lane: matched
  since 2026-10-15); narrow exits
  end matched; a mixed old ring; the Roundabout Interchange with its own-lane ramp; ringForm; the hand-edit
  fallback; the wait), test_script "outside the zones the default rule, on the whole ring" (was: the flip).

## Bus lanes (rev 6, 2026-10-13, player request; implemented offline, not run in game yet: TESTING.md H2)
Player: "make the tool ignore bus lanes but set all the other lanes correctly; I'll add the bus lane connections /
bus priority light phases myself." Before, any junction with a bus-only lane was skipped whole (`bus_lane`,
`bus_lane_arm`).
- **Lane model**: `Ring.lanesAt` lists car lanes only (a road lane with CAR); a bus-only lane (BUS / TRUCK without
  CAR) goes to `la.bus` instead. So every rule (slip cases A / B, crossroads / T case X, lane drops case D, ring arms)
  plans the car lanes, never names a bus lane, and its curb lane is the car lane next to the bus lane. Lane counts
  are car lanes: a road where a bus lane starts (2 car lanes -> 1 car + 1 bus) is a lane drop for cars (case D).
- **Kept connections**: `Ring.busLanes(world, n)` / the views' `v.bus` (`{[seg] = {[lane] = true}}`, nil when
  none). `Rules.mergeTram(rule, cur, bus)` keeps every current connection touching a bus-only lane exactly as read
  (both flags), as tram connections are kept; the list carries `bus` (`conns.bus`). Apply, the automatic pass, Reset
  at crossroads (game-default model + kept bus connections) and at rings (`Rules.defaultConns`) all go through it;
  the snapshot Reset (slip nodes, lane drops) restores the snapshot's car connections and keeps today's bus
  connections (`Rules.keepBus`).
- **Status / same checks ignore them**: `Rules.roadText(list, bus)` (badge, button states, cache keys),
  `Rules.carText` (snapshot Reset enabled, VERIFY: `W.addItem` stores `{text, bus}`, the free curb turn's re-check),
  `Cross.isDefault` (car lanes only), `Rules.ringForm` (the whole-ring hand-edit guard), the slip "same" check
  (kept connections are in the planned list), the lane-drop `u_turn` guard (a bus U-turn is no turnaround), the
  audit (not `bad`) and `Rules.reachability` (car travel only). A bus connection the player adds or edits never
  makes a junction Custom lanes or re-enables Apply.
- **Traffic lights**: phases follow the connection list. Game default phases: `W.remapLights` maps a kept bus
  connection to its own old state by key (as tram connections). Smart Lanes phases: `sl_phaseplan` plans every
  connection of the list, kept bus ones included (classes by movement, `Phases.classesFromView`), and validates that
  each is green in some phase. Free curb turn: `Lights.kerbIndices` skips connections touching a bus-only lane
  (`X.kerbPairs` carries `kerb.bus`): the curb turn is the curb car lane's turn, bus connections keep their signal.
  "No lights at roundabouts and ramps": a junction with a bus lane keeps its lights (`Lights.keepsLights(case, bus)`,
  `Lights.ringNodes`): its light may be the player's bus priority.
- **Still skipped**: a ring whose ring segments have a bus-only lane (`Ring.findRing` "bus_lane_ring"); its nodes
  are not slip nodes or crossroads either (`Slip.classify` skips `bus_lane_ring`; status "not handled: the ring has
  a bus lane"). A direction whose road lanes are all bus-only has no car lanes: for the rules the road is one-way
  there (a contraflow bus lane on a one-way street: a crossroads of three two-way roads and a one-way road goes to
  the crossing rule as such), and a road with bus-only lanes only is no road (as a tram-only track). Ring detection
  (`Ring.oneWay`) still counts every road lane, so a one-way ring segment with a contraflow bus lane is no ring.
- **Status line**: a handled junction with a bus lane says "bus lanes kept as they are" (`P.detail`, `t.busKept`).
  Reasons `bus_lane` / `bus_lane_arm` and their texts are gone; `bus_lane_ring` ("the ring has a bus lane") is new.
- **Open (offline unknowns)**: whether the game itself connects car lanes into a bus lane in its defaults (we keep
  whatever it made; our car rule adds the car-to-car moves), whether the engine keeps our re-written bus connections
  byte for byte (VERIFY ignores them, so a change would not show; the TESTING.md H2 check reads them), how TF3 treats
  a car connection into a bus lane (cars should never route over it). Bus lanes carry trucks too (base Bus Lane Tool:
  "exclusive to buses and trucks", `bus_lane_tool.script.tl:10`): a lane without CAR counts as bus-only.
- Tests: `test_bus.lua` (lane model, merge helpers, slip, crossroads incl. default / Reset / curb turn / audit,
  phases remap and plan, all-bus direction, lane drop, ring arm with ringForm / autoSeeds / lights, bus ring skip,
  status line), `test_tool.lua` (crossroads Apply / player edit / Reset, lane drop snapshot Reset), `test_script.lua`
  (automatic pass at a lit crossroads: bus connections and their phases kept, VERIFY, a player's bus edit).

## Reset sticks (rev 7, planned 2026-10-14, user decision; implemented 2026-10-14; TESTING.md RK steps 1-3 passed in game 2026-10-14, 4-5 open)
Problem (user test 2026-10-14, live session 17:29 UTC, `docs/findings/roads.md` "A build on a junction's arm
re-applies..."): the tool's Reset gave T-junction 5237 the game's lanes (17:33:35); moving a bus stop on one arm
rebuilt that arm (edge 6229 -> 8158) and the automatic pass wrote smart lanes again (`APPLY ... node=5237`,
17:38:21) without a word. Players who Reset and then place stops or upgrade a road see Smart Lanes "come back"
(fits a player report: "a sticky setting from your mod"). A config check can't tell: the rebuild leaves the
game's default config, the same as a Reset, so the player's choice must be remembered.

Design:
- **Kept nodes**: a Reset (tool, any selection: junction, street, multi-select, roundabout, slip node, lane drop,
  ring mid node) marks each node it wrote as kept; an Apply on a node clears its mark. The automatic pass leaves
  kept nodes alone exactly like `game` zone nodes (`zoneFilter` / `ringInGame`: a ring with a kept node is left
  whole, as today with a game zone): `SKIP kind=kept job= nodes= reason=reset_kept`.
- **Storage**: a separate list in the saved game-script state, never mixed into `zones` (another mod's `set`
  replaces every zone). `kept = { {n, x, y}, ... }`, `kseq` +1 per change; the GUI mirror re-reads it only when
  `kseq` changed (as `zseq`). Cap 2000 entries, oldest dropped first (log `KEPT op=dropped`). Nothing is written
  until the first Reset, so saves that never use Reset get nothing new (save safety unchanged).
- **Channel**: the tool sends `SmartLanes.kept` `{ op = "add" | "remove", nodes = { {n, x, y} } }` through
  `makeScriptingSendEventCmd`, validated in the engine handler like `SmartLanes.zones` (numbers only, at most 60
  per event = the tool's selection cap). Also handled with Apply automatically Off (the tool reads it) and never
  in the map editor.
- **Matching**: by node id, or by position within 1 m (a rebuild may replace the node; 5237 kept its id in the
  test, other builds unverified). A new junction built on a kept spot inherits the mark (it is the place the
  player reset). Stale entries (no node within 1 m) are pruned when the mirror is read.
- **Tool**: lane status "Game default (locked)" with a tooltip line "Smart Lanes leaves this junction alone when
  you build next to it. Apply gives it smart lanes again." Reset's tooltip gets the same sentence. New strings in
  all 13 languages, tooltips wrapped (`make tooltips`).
- **Not in scope**: Crossing Tool edits (no marker; a rebuild resets them to the game's default anyway), and the
  short-block U-turn question (findings: lane changes need room; compare game vs Smart Lanes at ~25 m first).

Tests (offline): validate the event payload (bad types, too many nodes, op); add / remove / cap / prune; match by
id and by position; the automatic pass skips a kept crossroads, a kept slip node, a ring with one kept junction;
Apply clears the mark; a save without Reset keeps a state without `kept`. In game: TESTING.md "RK".

Docs: description (Features "Smart Lanes tool", "Only what your builds touch is changed" paragraph, Changelog rev 7),
mod.json revision 7.

As implemented (2026-10-14, offline; where it differs from the design above, this wins):
- **sl_kept.lua** (pure, plus `readSaved` for the tool): `validate` (op add|remove, 1..60 nodes `{n, x, y}`, ids
  integers >= 0, coordinates finite within 1e6, optional `src` tool|auto|prune; anything else ignores the whole
  event: `KEPT op=ignored reason=`), `apply` (an add first removes every entry it matches, so one entry per spot and
  the entry moves to the end; cap 2000, oldest dropped), `index` / `match` (by id, else the nearest entry within 1 m
  on a 2 m grid), `payloads` (60 nodes per event), `readSaved(api, lastSeq)` (reads the list only when `kseq` changed).
- **Engine** (sl_lanes.script.lua `handleKept`): subscribed with the zones event (also with Apply automatically Off),
  ignored in the map editor. Logs `KEPT op=add|remove n=<event nodes> total=<entries> src=..` and `KEPT op=dropped n=`.
  A remove that matches nothing writes nothing (no state change, no line), so an Apply on a junction that was never
  reset leaves the state as it was.
- **What a Reset marks**: every node the Reset covers, at the click (C.reset, before the write; written or already the
  game's): a junction, a slip node, the junctions of a street or multi selection, a roundabout's every ring node.
  Apply (C.apply, any scope) sends `remove` only for covered nodes that are kept (the tool's mirror), so an Apply
  elsewhere sends nothing.
- **Pruning** (deviation): the API has no "nodes near a point" query, so "no node within 1 m" can't be read. Instead,
  at load (GUI init, Apply automatically On) entries whose node id is gone (no BASE_NODE) are removed (`src=prune`),
  and when a job matches a kept entry by position under a new id (a rebuild replaced the node), the entry is moved to
  the new id at once (`KEPT op=add ... src=auto`), so a replaced node keeps its mark across reloads. Known gap: a node
  replaced while Apply automatically was Off loses its mark at the next load with it On.
- **Automatic pass**: `keptFilter` after `zoneFilter` (a node in a game zone counts as zone_game, not kept): one
  `SKIP kind=kept job= nodes= reason=reset_kept`, `skips=reset_kept:n` in SUMMARY; `ringKept` in ringStep:
  `SKIP ring= node= reason=reset_kept` for the whole ring. Job snapshot of the mirror (`job.keptIdx`).
- **Tool**: the mirror is re-read at most once per frame and only when `kseq` changed; the tool's own events are
  applied to it at once (the badge shows the change before the engine answers). Badge key `kept` (PICK badge=kept),
  label "Game default (locked)", when the target's handled junctions all have the game's lanes (or, for slip nodes and
  lane drops without a model, none has smart lanes) and all are kept. The badge tooltip is one static text for every
  state, so it gained a "Game default (locked): ..." paragraph; Reset's tooltip the sentence "Smart Lanes leaves a reset
  junction alone when you build next to it. Apply gives it smart lanes again."
- Tests: tests/square_smart_lanes/test_kept.lua (module, event wiring, automatic pass, prune, re-key, save safety),
  test_tool.lua "kept (tool)" (Reset marks, Apply clears, badge).

## Open exit lanes near stops and close junctions (rev 7, user decision 2026-10-14; implemented 2026-10-14; TESTING.md OE steps 1-3 passed in game 2026-10-14, 4-6 open)
Why: a player report (bus lines in new towns with 4-lane roads take U-turns and long detours) and the user's
tests 2026-10-14 (`docs/findings/roads.md` "Vehicles change lanes between junctions..."): which lane may turn where
at a 2-lane crossroads / T is the same in Smart Lanes and the game; the one lane difference is that Smart Lanes
lands each turn in ONE exit lane, the game in every exit lane. A bus that turns into the inner lane then has to
change lanes before a curb stop just after the junction, or before the next junction on a short block.
Rule: at a crossroads or T-junction (sl_cross), per exit road R (a road a turn leads into): if R has a street stop
within 80 m of the junction (along R, either side of the road the turn drives on; a stop on R's road piece that
starts at the junction) or R's far end is a junction within 80 m (`A.WEAVE_M`, the audit's weave test), the turns
into R land in every lane of R the movement can reach without crossing another movement of the same light phase,
as `sl_exitfan` does (`X.phaseGroups` / `placeExitLit`), and as the game does. Straights keep their lanes. The freed
curb turn still lands only in R's curb lane (as sl_exitfan). Unlit junctions: the same fan (no phase constraint
other than not crossing). Which lane may turn where is unchanged (3+ lanes keep the curb turn lane). Other
exit roads of the junction: as today. Roundabouts, slip nodes, lane drops: unchanged.
Order: placing / removing a stop rebuilds its road piece, which sends both end nodes to the automatic pass (jobs
`nodes=2` at 17:35:16-18 in the 2026-10-14 17:29 session), so the rule re-evaluates when stops come and go. Kept
(Reset) junctions stay skipped.
Log: APPLY gets `open=<edge ids>:<stop|near>` (or `open=-`). Tool status: still "Smart lanes".
Tests: stop at 79 m opens, 81 m not; near junction 79 / 81 m; lit and unlit; 2- and 3-lane; no stop and no near
junction = byte-identical connections to today; a freed curb turn still curb lane only.

As implemented (2026-10-14, offline; where it differs from the design above, this wins):
- **Stop detection** (sl_write `world.stops(seg)`, read once per segment and only for the exit roads of a handled
  crossroads / T): the segment's BASE_EDGE `objects` (`{ {entity, EdgeObjectType} }`, `api/engine.d.tl:105`) entries of
  type `STOP_LEFT` / `STOP_RIGHT` (`api/type.d.tl:422`; base `mission_task_build_construction_util.tl:233` tests a stop
  the same way, on a proposal's segment); without the enum, objects with a STATION component (base `name_util.tl:39`).
  The entities' IDs come with the segment read (`stopIds`, at most 32 objects). Each stop's EDGE_OBJECT gives `transf`
  (position) and `param` (0..1 along the edge, `engine.d.tl:133-144`). Read from the tealdefs and base files; **not yet
  verified in game** that a built edge's `objects` lists its street stops (TESTING.md OE step 6 has the console check).
  Either side of the road counts (a stop on the far side of a two-way road opens it too; the side isn't mapped to the
  driving direction).
- **Distance** (sl_cross `stopDist`): the walk's distance to the segment's start, plus the stop's position projected
  onto the segment's chord (direction-free, the curb offset drops out); without a position, `param` from node0 (the
  direction inferred from the tealdef, not checked); with neither, the segment's far end (conservative). The walk out
  (`X.openOf`, `Walk.follow` dir out, at most `X.OPEN_M` = 80 m and 8 segments) passes plain nodes, so a stop on a later
  piece of the road counts at its distance from the junction. `A.WEAVE_M` is now `Cross.OPEN_M` (one value; sl_audit
  requires sl_cross, not the other way).
- **Near** (deviation): the walk must end at a junction within 80 m where traffic arriving on R has 2+ ways on (roads
  with lanes leaving there, at most 135 deg off straight: `X.waysOn`). Without it every Channelized Junction centre opened
  every arm (its slip nodes are 25-40 m out), though a slip lane's merge node offers no lane choice.
- **Which turns change** (deviation): only the far-side turns (the turn across traffic). `placeExitLit` gives the shared
  lanes to the curb turn (the curb turn 1-2, the far turn 2 on a 2-lane road), which leaves the bus turning across
  traffic in the far lane, the case the change is for. Instead (`openExit`, after the rule's placement and its unfed-lane
  fill-in): each far-side turn widens down to the highest lane any movement before it (curb turn, straight) of the same
  group lands in, fill-ins included, and up to the lowest lane of a later one; its curb-most feeder takes the new lower
  lanes, so no approach crosses itself. Curb turns and straights keep every connection, so the freed curb turn stays in
  the curb lane with no `kerbLaneOnly` split (the lights code is untouched). Groups: lit and on the game's axis model
  (`X.phaseGroupMap`, X.phaseGroups without touching the view) the game's phase groups; unlit, unknown or off the model
  one group of every movement into R. Result: 2x2 T, the main road's left turn into the side road 1-2 (was 2), the
  curb turn 1; lit 2x2 / 3x3 crossroads, the far turn into every lane (the opposite straight runs in the other phase);
  unlit 2x2 crossroads nothing changes (the opposite straight already lands in both lanes); unlit 3x3, the far turn 2-3.
- Only exit roads a far-side turn leads into are looked at (the reads and the log): `open=<seg>:<stop|near>,...` on
  case X APPLY lines (after `unshared=`), else `open=-`. A stop wins over near (one reason per road). An sl_exitfan zone
  node keeps its fan where it applies (open is not evaluated there; unlit or off the model, open applies).
- **Audit**: every share of a lane of an open exit road is `shared_open` in `forced=` (by design, never flags);
  tools/sqrl_audit.py lists it under by-design kinds.
- **Budget**: the reads happen inside the node's classify step, so they count in the step's measured cost (stepCost
  "slip") under the existing 8 ms frame budget; per node at most 4 walks of 8 segments, one EDGE_OBJECT read per stop.
- Known gaps: a light that appears after the write (lit unknown at the write) keeps the one-group result (no re-check);
  with Light phases "Smart Lanes" the new merges count as conflicts for the phase planner (it may split the two turns
  into separate phases); a junction built later at the far end of a short block re-evaluates only when the build
  touches this junction's road piece.
- Tests: tests/square_smart_lanes/test_open.lua (detection 79 / 81 m by position, param and unknown; near 79 / 81 m,
  through a plain node, a merge node; lanes at lit / unlit / unknown 2x2 T, 2x2 / 3x3 crossroads; byte-identical
  sweep without open roads; invariant sweep with a stop on every road; openExit; audit; world.stops over the fake api;
  the automatic pass end to end), test_tool.lua "open exits (tool)", tests/tools/test_sqrl_audit.py shared_open.

## Rev 8: dedicated curb lanes, whole lanes and bus lanes, Lights only, lane status reason, axis plan (2026-10-14, a player's report; implemented offline, not run in game yet: TESTING.md "SH", "AX")
Player report (screenshots of a lit crossroads, one car lane each way on both roads, the main road with bus lanes and
a tram, Light phases = Smart Lanes): (a) "Lanes: Smart lanes (= game default)" was puzzling; (b) the free curb turn,
even When safe, stopped phases from skipping; (c) re-applying the tool reset their own lane edits, they wanted the
light phases re-planned for their corrected lanes only; (d) the main road's phases were too short. Follow-up the same
day: (f) every phase must green all lanes of a direction whole; (g) a red curbside bus lane blocks the green right turn
beside it; (h) lane counts do not tell the main road (their busiest road has fewer lanes on purpose).

### Free curb turn: dedicated curb lanes only (b)
Reasoning (inferred from the report, not verified in game): a phase (demand-actuated, `canSkip`) ends early only when
its green lanes are empty. A curb turn freed out of a lane that also carries a straight or far movement is green while
the car at the head of that lane waits for its own red movement: the turners behind it gain nothing, and the lane
is never empty, so the phase where only the freed turn is green runs to its full length every cycle. On a 1-lane
approach every movement shares the lane, on a 2-lane road Smart Lanes' curb lane goes straight too; only 3+ lane
roads (curb lane turns only) or a curb lane the player made turn-only have a dedicated curb lane.
- `L.sharedKerb(conns, kerbIdx, allKerb)` (sl_lights.lua): a curb connection is shared when its entry lane
  (segment0, lane0) also carries a road or tram connection that is no curb connection (a straight, a far turn, a
  U-turn, a tram, a connection into a bus lane). Other curb connections of the same lane (the exit fan's) are no
  mates.
- `L.kerbPhases` SAFE / FREE: shared ones are never freed; they are held with their lane (red in every phase where
  every lane mate is red, so a turn an earlier write freed goes back), as LOCK holds a turn with its approach. LOCK
  (Reset, sl_lock zones, the relock before every write) is unchanged: it still sees every curb connection.
  `stats.shared` = curb connections held so; logged as `shared_held=<n>` after `merge_free=` (SUMMARY, tool WRITE,
  LIGHTS to=free_turn; also for Always).
- `L.freeable` = the exit fan's free ones on a dedicated lane: `W.kerbLocked` (the re-checks) counts only those, so a
  shared turn red with its lane is not taken for "the game re-made its phases".
- Planner (sl_phaseplan.lua): the same rule, applied to every movement, made a hard invariant by (f) below ("Whole
  lanes and bus lanes"). At a 1-lane crossroads every approach phase serves only its own approach.
- Effect: with Smart Lanes' lanes the free curb turn acts only on 3+ lane roads; on 1- and 2-lane roads it frees
  nothing (`free_turn=0 shared_held=<n>`). The rev 4 note "with the game's two-phase default at a 2x2 crossroads every
  curb turn merges ... so When safe frees nothing there" is now true for Always too.
- The audit (sl_audit.lua) checks lanes, not phases: nothing to change there.
- Tests: test_lights.lua ("sharedKerb", "1-lane crossroads", the X / T SAFE tests now with 3-lane / mixed roads),
  test_phaseplan.lua ("shared lanes", lead-lag), test_script.lua ("free turn: 1- and 2-lane crossroads"; the free-turn
  fixtures now 3-lane roads), test_tool.lua (litCross on 3-lane roads).

### Lights only (c)
A toolbar button, "Lights only" (named **Smart lights** since 2026-10-16, user; its status / result lines read
"Smart lights: <reason>"; rev 8 v2, user 2026-10-14: the checkbox could not be unchecked after use in the
user's test, and a mode of Apply was one click too many; first a third button, then a checkbox, now a button again),
in the second row with Re-time (e), shown only at a selected junction with a standing light. For a selected
crossroads / T-junction (sl_cross case X): `C.lightsOnly` = `W.planLights` with the plan input of the junction's
current connections (the player's Crossing Tool edits included) and crosswalks, a phases-only
`createTrafficLightProposal` (preference kept), no lane write, no kept mark change. Whatever "Light phases" says (an
explicit request); the plan is the normal Smart Lanes plan (`W.planFor`), so item (b)'s lane rule applies. Fan zones:
the fan plan (as Apply there). Reset undoes it (below, "Reset after Lights only / Re-time").
- Enabled only when `C.lightsStatus` finds a valid plan whose structure differs from the phases, or whose phases the
  player re-timed by hand (2026-10-16: plan phases re-timed by Smart Lanes still count as Smart lights, "Smart lights stays on after its timing changed" below; cached per node by
  connections, crosswalks and the phases' signature `W.statesSig`, NODE_STATUS_FRAMES at most); else grayed with the reason (the
  table under "Toolbar"; hidden since 2026-10-16 where no axis plan can be made: "No classic fallback"). Held like every phases-only proposal (`lightOnly`, `phaseHold`) and while a write or job is
  pending.
- Status: the selection's detail line also says "Smart lights: no phase plan for these lanes" / "Smart lights: Smart
  Lanes phases already set" / "Smart lights: on, timing adjusted" (since 2026-10-16: nothing when set, the badge's
  "| √ Smart lights" says it; "Smart lights: timing adjusted"; "Smart lights: timing changed by hand"). Results: "Light phases set for the current lanes",
  "Smart lights: <reason>".
- Log: `PHASES src=tool action=lights_only node= phases=sl pattern= plan=<text>` | `plan_fail=<reason>` | `same=1
  timed=0|1 pattern= plan=..`, and the proposal's `LIGHTS src=tool node= to=sl_phases phases=sl ... action=lights_only plan=..`.
- Tests: test_tool.lua "lights only (tool): ..." (2), "toolbar rows: ..." (3), getDefinition / sqperf param counts.

### Smart lights stays on after its timing changed (2026-10-16, user; implemented offline, not run in game yet: TESTING.md "SO"; a hand edit offers it again since the same day: "Ours vs the player's")
User: "after smart lights auto applies new timings, it no longer thinks the smart lights is enabled, so the smart lights
button pops up again. it should know that even if timing is adjusted smart lights was enabled". Re-time, Keep timing
adjusted and the Crossing window's duration slider change only the greens; the exact comparison with a fresh plan
(`W.samePlan`: durations included) then failed and Smart lights was offered again (a click would have thrown the fitted
timing away).
- **Structure, not durations:** `W.samePlan(states, plan, structOnly)`: the same phases in order, the same locked lanes
  (as sets) and canSkip, and a minDuration of the plan's or less (Re-time writes min(minDuration, new duration) and never
  raises it again, sl_retime.lua). Any durations. A changed lane layout gives other phases or locked lanes: offered again.
- **Tool:** `C.lightsStatus` returns `same` (exact) or `timed` (structure only; since the same day only when the
  durations are ours, else `hand`: "Ours vs the player's" below); `can.lights` is off for both. The button
  stayed shown at the lit junction (toolbar v3), grayed "Phases already the Smart Lanes plan" or "Smart lights is on
  (timing adjusted)"; since later the same day it is hidden there and the badge says "| √ Smart lights" (Toolbar
  section), the detail line "Smart lights: timing adjusted" (before: "on, timing adjusted"). A click anyway (a stale toolbar) sends nothing:
  result "Smart lights: on, timing adjusted", `PHASES ... same=1 timed=1`. Reset is unchanged (`C.phasesDefault`, the
  phases are not the game's).
- **The other users of the comparison** (`W.planLights` gets `keepTiming`; with it the plan's structure in other
  durations returns 0, "same" and a 5th result timed = true): the tool's Smart lights and its Smart lanes Apply where the
  lanes stay (`phaseOnly`), the automatic pass at a junction whose lanes are already right (`planSame`, a build nearby
  no longer resets fitted timing), the re-check once a light stands (`recheckFree`, `fanRecheck`): all keep timing. The
  new-light look (`sl_autoretime.lua` planLook) keeps the exact comparison: it acts only on engine-made phases. A build
  that changes a junction's lanes writes its plan with the lanes as before (`item.lightPlan`, not `W.planLights`). No
  Stress Test reader uses it.
- Tests: test_tool.lua "toolbar rows: Smart lights stays on (grayed) after its timing was adjusted ..." and
  "W.samePlan: exact and structure-only", test_script.lua "light phases Smart Lanes: lanes already right: re-timed plan
  phases are kept; another phase structure is written".
- **Ours vs the player's (2026-10-16, user: "if i manually change the timing of a light phase it should know it wasnt
  the re-time doing it, and let me either set smart light phases or reset the light"; offline only, TESTING.md "SO"
  step 2).** The Crossing window's slider keeps the structure too, so "structure only" grayed Smart lights after a
  hand edit. The engine flag can't tell (every phases write sets it, docs/findings/roads.md), so the mod remembers
  what it wrote:
  - **Record:** the last-measured records (`rlast`, sl_auto.lua) get an 8th field `d`, `Auto.durSig` of the
    durations Smart Lanes last wrote at the junction: sum of i x round(2 x d_i) (half seconds; a swap of two greens or
    one changed green changes it, unlike the cycle). A written outcome (Re-time `rtWrite`, Keep timing adjusted
    `writeStep`) stores the written durations' signature; fits / too little traffic / not written carry the previous
    record's (`Auto.carrySig`: the runtime's unsent one, else the saved one), 0 when we never wrote there. Records of
    older builds (7 fields): their written cycle `c1` within 0.5 s counts as ours. Size: 1000 records x 8 numbers,
    test_auto.lua "save safety" 109.6 kB at the signature cap (bound 120 kB). Smart lights, the automatic pass and the
    new-light look write the plan's exact durations: no record needed (`same`).
  - **Status:** `C.lightsStatus` caches the structure match (`struct`) with the read durations; on every call
    `Auto.timingOf(lastEntry(n), durations)` makes it `timed` ("ours": hidden, badge "| √ Smart lights",
    detail "Smart lights: timing adjusted") or `hand` (else: enabled, detail **"Smart lights: timing changed by
    hand"**, 13 languages). Reset is offered there anyway (the phases are not the game's, `C.phasesDefault`).
  - **Click:** at `hand` `C.lightsOnly` passes `keepTiming = false`: the plan is written with its own timing
    (`PHASES src=tool action=lights_only node= phases=sl hand=1 pattern=axis plan=`). At `timed` nothing is sent, as before.
  - **No lag after a Keep timing adjusted write:** a written record goes out at once (not with the 30 s batch), and the
    runtime hands every record to the tool of its Lua state (`opts.lastSent` -> `C.noteLast`, sl_bg.script.lua), so
    the tool never reads its fresh write as a hand edit while the event is in flight. When the tool and the runtime run
    in different Lua states, the tool sees it once the event lands (a second or so: Smart lights may show enabled
    that long).
  - **Keep timing adjusted after a hand edit** (unchanged, documented): at an enrolled junction the runtime adopts the
    player's durations as its base (`AUTORETIME op=adopt reason=durations`), waits `Auto.EVERY_WRITE` (10 game min,
    scaled), and re-times from them; its next write makes them ours again (Smart lights hidden, "| √ Smart lights" in the badge).
    Until then the tool says "timing changed by hand"; a "fits" decision keeps that (it carries the older signature).
    `AllMode.handTimed` (sl_allmode.lua) is a different question, unchanged: whether All lights enrolls a junction
    not enrolled yet; any record of ours there ("measured") still means not timed by hand. Using the signature there
    too would leave a junction we re-timed and then Smart-lighted (whole seconds, flag set) out of All lights, so it
    stays as it was.
  - Edge cases: the player sets exactly the durations we last wrote (reads as ours); a hand edit of a 7-field record's
    junction that keeps the cycle (reads as ours until our next record).
  - Tests: test_tool.lua "toolbar rows: Smart lights after a hand edit of the plan's timing ...", "Auto.durSig /
    timingOf / carrySig ...", the stays-on test with a written record, a fits record and a 7-field one; the runtime's
    write record carries the signature ("keep timing adjusted (runtime): enough snapshots ..."), a never-written one
    0 ("... a quiet junction ..."); test_auto.lua "save safety" with 8 fields.

### Toolbar: rows, hidden when there is nothing to do (rev 8 v3, user 2026-10-16; rev 8 v2 "two rows, grayed with a reason", user 2026-10-14)
User's test of rev 8: buttons that vanish made the bar jump, and the checkbox could not be unchecked (v2: base
Buttons only, a button that can't act grayed with its reason, so the layout stays put). User 2026-10-16 (v3, partly
reverses v2): "Apply" is now **Smart lanes** and "Lights only" **Smart lights**; Smart lanes, Reset and Record traffic
are **hidden** (`checkEnabledFn` "Hidden": no row, gap or separator) where Smart Lanes does not handle the selection
or there is nothing to do, and grayed with a reason only for passing states (a change landing, a recording at another
junction). With both Smart lanes and Reset hidden the first row is gone. The lane status badge ("Smart lanes", "Game
default", "Not handled") and the detail line ("not handled: <reason>", "no junction here", "nothing to change here")
say why; nothing that only the grayed reason said is lost (the v2 reasons "Lanes already set", "No lane rule for this
junction", "Already the game's lanes", "Nothing to reset: no Apply here yet", "Lanes and light phases already the
game's" repeated the badge and are gone). The light row (Smart lights, Re-time) keeps v2: shown at a lit junction,
grayed with its reason, except (user 2026-10-16, "after applying smart lights the button should hide instead of
disable") Smart lights is **hidden** once the phases are the Smart Lanes plan (exact, or re-timed by Re-time / Keep
timing adjusted): the badge says "| √ Smart lights" instead (`lightsOffered` checks `same` / `timed`; the grayed
reasons "Phases already the Smart Lanes plan" and "Smart lights is on (timing adjusted)" and the detail phrase "Smart
lights: Smart Lanes phases already set" are gone; re-timed phases keep a short detail "Smart lights: timing
adjusted"). Re-time, Keep timing adjusted and Reset stay. The player's own re-timing shows it again, enabled. Also 2026-10-16: every action button has the small look of the Keep timing adjusted toggle
(below, "Small buttons"). Nothing selected: no rows, only the message. `C.buttons()` (show, can, enabled, why, tip
per button) drives `C.paramState` (checkEnabledFn: Hidden / Disabled / Enabled) and `C.buttonTip` (the reason).
**Reset hides after a Reset** (user 2026-10-16: Reset stayed at a lit T-junction, four Resets in a row in the log,
node 35512): the phases test `C.phasesDefault` read the game's restored phases as changed (our own states = {}
write sets `userModifiedTrafficLightStates`; a 1-lane T's default may not be the measured 6-phase shape), so Reset
kept offering "light phases". Now the tool remembers the phases its Reset gave back (`C.resetPhases`: marked when
the default write lands, the signature `W.statesSig` of the first read with phases) and counts phases equal to them
as default until they change (Keep timing adjusted, Re-time, the Crossing window) or another write of ours starts
(`C.clearReset` in lightOnly / writeSlip). Session only: after a reload the heuristic decides again (open: whether
the flag stays set after a Reset; then Reset shows again after a reload, harmless).
- **Where the reason goes.** A toolbar param's own `tooltip` can't change at runtime: construction.tl:1064-1079 keeps
  it in a ref set from `param.tooltip` and re-reads it only when the param's ParamForUi (type, name, values, tooltips,
  makeCompactButtonFn, ...) changes; `checkEnabledFn` returns only a state. But `makeCompactButtonFn`'s content is our
  recipe (`SmartLanesButton`): its TextView's `meta.tooltip` is the reason ("Grayed out: A write is still landing") or
  what the click does here, above the button's own text, polled from `C.buttonTip` every step. The base shows tooltips
  on disabled widgets (mod_manager_react_util.tl:5943-5947, `enabled = installed, tooltip = not installed and ...`);
  whether a TextView inside a disabled toolbar button shows its tooltip is unverified (TESTING.md "Toolbar rows").
  Fallback that needs no game check: every static tooltip names when the button is shown or grayed, and the status
  detail says "nothing to change here" when no button can act.
- **Small buttons** (user 2026-10-16, "all buttons the size of Keep timing adjusted"; read from the game files, not
  verified in game). Base widgets only, no stylesheet rule (`make css-rules MODS='square_smart_lanes
  square_better_bus_overlay'` stays 9): each action param gets `numbers = { 1 }`, so the menu draws its one value as a
  base ToggleButtonGroup with one button (script_param_util.tl:440, the Yes / No toggle's widget) instead of a lone
  ToggleButton. The bar's 32 x 32 px minimum is a rule on `ToggleButton!right-parameters` (construction.css.lua:817);
  in a group that class is on the group, so the button is its text's height plus the bar's 4 px padding (814; the
  Yes / No toggle's 0 px padding, 804, needs the param's label wrap, which a hidden label skips). Clicks still reach
  `onChangeFn` (builtin.lua ToggleButtonGroup: every click calls `onValueChange` with the index), the value stays 1,
  the content stays SmartLanesButton (label unclipped, reason tooltip), "Disabled" / "Hidden" work as before.

| Selection | Row 1 | Row 2 | Record traffic |
|---|---|---|---|
| nothing | hidden | hidden | hidden |
| not handled ("Not handled", e.g. 5 roads), smart lanes = game default, nothing to change | Smart lanes hidden; Reset only where there is something to reset; both hidden: no row | as below | as below |
| unlit junction, ring, street, multi | Smart lanes shown when a click would change the lanes, Reset when there is something to reset ("Reset the light phases to the game default" / "Reset lanes and light phases to the game default" tips at a lit crossroads); each grayed "A write is still landing" while one lands | hidden | real junction (3 roads or more, roundabout junction included) or roundabout: shown, Smart Lanes applied or not; grayed "20 recordings running, the most at once" (before 2026-10-16: "Recording traffic at another junction"); a bend, dead end or lane drop (fewer than 3 roads): hidden; street / multi: hidden |
| lit crossroads / T-junction with an axis plan | as above | Smart lights (hidden once the phases are the plan, also re-timed by us, since 2026-10-16; grayed: "Re-time is measuring here", landing) / Re-time | as above |
| lit crossroads / T-junction without one (skewed past 45 deg, no main road, a lane without a road phase; since 2026-10-16, "No classic fallback") | as above | Smart lights hidden, the detail line "Smart lights: not for this junction shape" / "Smart lights: no phase plan for these lanes" / Re-time | as above |
| other lit junction (slip node, 5 arms, ring junction with a light) | as above | Smart lights hidden (grayed "Only at a crossroads or T-junction" until 2026-10-16), the detail line "Smart lights: not for this junction shape" / Re-time | as above |
| the junction Re-time measures | as above | Smart lights grayed; Re-time enabled, its tip "Measuring: click to cancel" (grayed "Waiting for the last change to land" while it waits to write) | as above |
| another lit junction while 5 are measured | as above | Re-time grayed "Re-time is measuring 5 junctions, the most at once" (rev 9; before: "Re-time is measuring another junction" while one was measured) | as above |

Step B (below, "Keep timing adjusted") adds row 3: "Keep timing adjusted [Yes|No]" (twin toggles since 2026-10-15), shown whenever row 2 is, never
grayed, its value the selected junction's own state; at an enrolled junction Re-time is enabled with the tip "Timing
kept adjusted: click to check it now" (also while the manual Re-time measures elsewhere).

Small buttons since 2026-10-16: `numbers = { 1 }` (above, "Small buttons"; docs/ui-guide.md "Construction toolbar"). CSS rules 4 before and
after (`make css-rules MODS='square_smart_lanes'`).

### Reset after Lights only / Re-time (rev 8 v2, user 2026-10-14)
The user expects Reset to undo a phase change too. At a lit crossroads / T-junction Reset restores the game's lanes
(as before) AND the game's default phases (`W.defaultLights`: `states = {}`, the Crossing window's "Reset to Default"),
and is enabled when either the lanes differ from the game model or the phases are not the game's default
(`can.resetPhases`). Lanes already the game's: only the phases (`LIGHTS src=reset to=game_phases`, result "Light phases
reset to the game default"); else the lane write first, the default phases after it answered (as with Light phases =
Smart Lanes before). Street / multi Resets reset a lit crossroads' phases the same way (`resetDefaultFor`), but their
button state counts lanes only.
- **"Not the game default"** (`C.phasesDefault`, a heuristic from the measured defaults, docs/findings/roads.md):
  default = not flagged `userModifiedTrafficLightStates`, exactly 6 phases veh / all-red 6 s / veh / all-red 6 s /
  pedestrians 3 s (all-red without crosswalks) / all-red 9 s, every phase canSkip with minDuration 1.5, and both
  greens **not whole seconds** (the engine's are 18.86 / 21.55 / 23.70 / 27.09 s; the Crossing window's slider, Lights
  only and Re-time all write whole seconds). Failure cases: a default green that happens to be a whole second (none
  seen) reads as changed: Reset stays enabled and rewrites `states = {}` (harmless); a junction type whose engine default
  has another shape (not seen at X / T) reads as changed likewise; a hand edit that keeps the default shape and
  fractional greens and leaves the flag false reads as default (the Crossing window can't make one).

### Pedestrian phases may skip; greens never under the game's (rev 8 v2, user 2026-10-14)
PHASES_PLAN.md "Axis plan": the axis plan's pedestrian phases (and the no-crosswalk all-red) are `canSkip = true` with
`minDuration` = the clearance (`opts.pedClearance` 3 s, 0.5 s steps, at most the phase): the junction is still cleared
every cycle (cars left inside the box drive out, as the user's screenshots show with the game's phases), but an empty
pedestrian phase ends early. `PP.validatePlan` refuses a skippable clearance phase with less than 1 s minDuration
(`clear_min:<state>`). Road phases are never shorter than the game's default green for their lanes (`PP.gameGreen`:
2 lanes 23.7 s, 3 lanes 27.1 s, 1 lane 18.9 s, beyond +3.4 s per lane): a 2x2 X is now 24 / 6 / 24 / 6 s, a 3x3 X
28 / 6 / 28 / 6, a 1-lane X 19 / 6 / 19 / 6.

### Main road: no lane-count factor (d, h)
Rev 8 first gave the main road longer greens from lane counts (`PP.roadFactors`, `mainRoadMax` 1.5: an arm with more
road lanes, bus lanes and tram tracks included, got up to 1.5 times the green). Removed the same day (h): the player's
busiest road has fewer lanes on purpose, so lane counts pick the wrong road. Phase weights are lane counts again (a bus
lane counts as a lane) or explicit `laneDemand`; the answer to (d) is Re-time (e), which measures the traffic.
`info.roadLanes` stays for the crossing length and the all-red clearance. PHASES_PLAN.md "Step 4: calibration".

### Whole lanes and bus lanes (f, g)
Design and reasoning: PHASES_PLAN.md "Whole lanes and bus lanes" (the player's words quoted there; not verified in game).
- (f) An entry lane (segment0 + lane0; road + tram one lane, a bus-only lane its own) is all green or all red in
  every phase: every planner step adds whole lanes (seeds pull in their lane; the T's main phase and lead-lag's axis
  phase seed non-turn lanes only, so a shared straight + left lane runs in its lead phase), and `PP.validatePlan`
  refuses `part_lane:<state>:<seg>:<lane>`. Fan plans pass it too.
- (g) Step 2b: a bus-only lane (`v.bus`, connections kept as read) is green, whole, wherever a car lane of its
  approach is, unless it would conflict with another approach's green movement or a green crosswalk (then red there,
  all of it); its conflicts with its own approach are accepted (`plan.bus` for the validator). A car lane with a curb
  turn joins extra phases beside a bus lane only where that bus lane is green; the free curb turn (Game default phases)
  frees such a turn only where the bus lane is green.
- Tests: test_phaseplan.lua "whole lanes", "bus lanes", "validatePlan whole lanes" (both sides, 1-lane X / T, 2-lane
  X, the player's bus crossroads, a protected axis with a bus lane), test_lights.lua "kerbPhases beside a bus lane".
  Moved expectations: calibrated T 2x2 cycle 83 -> 85 s (whole lead lane), validatePlan's never_green case locks a
  whole lane.

### Axis plan: one long green per road (i) (player report 2026-10-14; implemented offline, not run in game yet: TESTING.md "AX")
Follow-up (i): at the same crossroads "the default runs 100x better; with your smart setting traffic backed up to the
other side of town because the phases are too short". Our x4 plan split shared-lane crossings into 4 approach phases
(~16 s each plus an all-red after each); the game and the player's own 5-phase plan give each road both directions
whole: 2 long greens per cycle. Design, the player's phases and the decisions: PHASES_PLAN.md "Axis plan (default
since rev 8)".
- `sl_phaseplan` `opts.pattern` = "axis" (default) for x4 and t3: per road one phase with every connection of both
  approaches (bus lanes and tram included), a 6 s pedestrian phase after each (every vehicle red; `opts.pedPhase`;
  skippable after its 3 s clearance since rev 8 v2), no all-red phases; the road with more demand first; an optional head start only with measured
  `laneDemand` (ratio >= `headStartRatio` 1.5; no caller passes demand yet). Greens 15 s + 4 s per lane, at least the game's default green
  for the lanes (rev 8 v2): the player's crossroads 24 / 6 / 24 / 6 s = 60 s (theirs 57.3 s without their head
  start); a 2x2 X the same (was 90 s split).
- Conflicts within a road (far turn vs opposite straight) are accepted explicitly: `plan.axis` per state +
  `PP.validatePlan(.., { axis = true })` (sl_write planFor passes it); never across roads or with a crosswalk.
- (Removed 2026-10-16, "No classic fallback" below.) `opts.pattern = "classic"`: the previous patterns (protected / split / lead-lag / t3), also the fallback when an
  axis plan cannot be made. Zone `sl_classic` (sl_zones.lua) plans them in the automatic pass and the tool, for A/B
  twins against `sl_phases` (now the axis plan) and `game`; the Stress Test does not send it yet.
- Setting "Light phases" tooltip rewritten (13 languages): one long green per road, a pedestrian phase between.
- Tests: test_phaseplan.lua "axis plan: ..." (the player's crossroads both lane rules and sides, 2x2 / 3x3 / 3x3 x
  2x2 X, 2x2 / 1-lane T, a 2+1-lane road, head start on / off, options, random fixtures), "validatePlan axis: ..."
  (refused without the flag, cross-road pairs, cross-road conflicts, green crosswalks), test_retime.lua "plan on a
  Smart Lanes axis plan", test_script.lua / test_tool.lua "sl_classic zone", test_zones.lua "sl_classic".
  Moved expectations (deliberate): the classic pattern and calibration tests of test_phaseplan.lua now ask for
  `pattern = "classic"` (LEGACY / CLASSIC) since the default is the axis plan; the write-path checks of test_script.lua
  / test_tool.lua validate the read-back states with the plan's road list and `{ axis = true }`; test_zones.lua's
  ring-variant list is `Zones.AB[8..15]` (sl_classic appended).

### Re-time: phase lengths from measured traffic (e) (player feedback 2026-10-14; step A implemented offline, not run in game yet: TESTING.md "RT"; step B: RETIME_PLAN.md)
Feedback: the phases don't follow how many cars wait in each direction; the main flow gets too little green. Step A:
a fourth tool button, **Re-time**, for one selected junction with a standing light and phases (whatever made them:
the game, Smart Lanes, the player). It measures the junction's traffic for 180 game s, then writes new phase
**durations only**: every phase's `lockedLanes` and `canSkip` stay as read, so hand-made phases and lanes survive.
- **UI.** (Rev 8 v2: see "Toolbar: rows, hidden when there is nothing to do" and "Re-time v2" above; step B adds a third row, "Keep timing adjusted"
  below.) The Lights only button and Re-time form a second row (group `sqrl_tool_lights`, shown only at a lit junction) under Apply / Reset: the construction
  menu's bottom bar is 314 px wide (construction.css.lua:726) and a param group is one horizontal BoxLayout that does
  not wrap, so four buttons would not fit in de / ru ("Anwenden | Zurücksetzen | Nur Ampel | Neu takten"); two rows of
  two do, and the rows say lanes / lights. Base Button params, no new style (CSS rules 4 before and after). Shown at
  a single selected junction whose world light read is lit and whose `W.lightRead` finds phases (cached with the
  selection's status, one extra read only at lit junctions); greyed while something of the tool is pending (job, write
  re-read, phaseHold); while it measures the button stays enabled and cancels. Status line: "Re-time: measuring traffic (%d of
  180 s)" (once per game second), then the result.
- **Measuring** (sl_retimer.lua, GUI thread, from C.step): every 3 game s (GAME_TIME; a paused game takes no samples,
  game speed does not change the spacing) for 180 s = 60 samples, 2-4 cycles of 40-90 s, so every phase is seen
  several times; at 3 s a car within 200 m is seen with the junction ahead before it passes. Candidates per sample:
  `getSimPersonsMovingForTransportNetwork` of the node and of each of its segments (persons ROUTED through them, 240-710
  each in Stress Test probe 11c; 30-360 us per call; far cheaper than the 43-110k SIM_PERSON list) plus the drivers
  ahead at the last sample; should every such call fail, the whole SIM_PERSON list (src=scan). Per candidate as Stress
  Test's sampler: driving (DRIVE, MOVE_PATH, not seated), position within 200 m (else skipped unless ahead last time),
  path (`elem.edgeId.entity`, `pathPos.edgeIndex`, up to 8 elements each way): the node ahead = approaching, movement
  = (element before, element after the node) = approach segment > exit segment; behind after being ahead = one pass.
  Queued: ahead, within 150 m, speed < 0.5 m/s, `timeStanding` >= 5 s. Caps: 1.5 ms of clock per frame (checked
  every 8 candidates; a sample takes more frames rather than more time per frame), 5000 candidates per sample, 2000
  drivers carried, 8 path elements. Lane-level demand is not in the path: the work is per movement.
- **Timing** (sl_retime.lua R.plan, pure, test_retime.lua): phase kinds all_red (every connection and crosswalk
  locked) and walk (only crosswalks green) keep their seconds; veh phases are re-timed. A movement is served in a veh
  phase when any of its road connections is unlocked there (several lanes, or a lane shared with another movement:
  one green connection serves it); served in every veh phase (a curb turn freed all cycle) = sets no length; served
  nowhere = unmapped. Demand = passes + 0.5 x mean queue x (window / cycle) (a standing queue is cars the green did
  not clear, once per cycle; halved because part of every queue is the normal wait through red). Phase load = its
  critical approach: per approach the demand of its served movements (1/k each when served in k phases) / its entry
  lanes. Cycle = the current one clamped to 40..90 s (above only for floors; rev 8 v2: Webster's cycle, "Re-time v2"). Weights 0.75 x load share + 0.25 x
  current share (damping; a phase without measured traffic keeps some green); floors min green 6 s (or the phase's
  own shorter length), pedestrians: a crosswalk green in veh phases keeps its crossing time (lanes x 4.5 m / 1.2 m/s
  + 3 s, less the walk phases' green) over them; whole seconds 1..60; minDuration lowered to the duration if above.
  Keep (no write) when fewer than 20 samples, or fewer than 12 passes and 3 queued cars ("too little traffic
  measured, phases kept"), or no mapped traffic; hysteresis: write only when a veh phase moves by >= max(3 s, 15 %).
- **Guards.** A sample re-reads the node's light (`W.lightRead`): lanes, phases (durations too) or the light changed /
  gone -> stopped ("the junction changed, stopped"). The button cancels (rev 8 v2: picking another junction,
  deselecting and closing the tool no longer do). At the end, a pending proposal of the tool makes it wait (600 frames at most); the write
  (`W.retimeLights`: `createTrafficLightProposal` on a `trafficLightConfig:clone()` with new `TrafficLightState`s,
  the preference as read) re-checks the phases' signature first and is held like every phases-only proposal
  (`lightOnly`, phaseHold). Limit: the automatic pass's own in-flight proposals (sl_lanes.script.lua busyNode) live in
  another Lua state; the signature check catches one that landed, not one in flight (as Lights only).
- **Probe** (the open questions, TESTING.md RT; RETIME lines in "Logging"): whether the node id survives the write and
  the config reads back with our durations and the same lockedLanes (probe cb / f30 `exists`, `same_durations`,
  `same_locked`); whether the running phase restarts (`state`, `time`, `state_times` before vs cb / f30 / s5 / s30);
  whether drivers re-route at the junction (reroute s5 / s30 vs the base5 / base30 baseline without a write);
  `user_modified` before / after.

### Re-time v2: the cycle from the measurement, running in the background (rev 8 v2, user and players 2026-10-14)
Players: "our timing set increased all red and crossing phases, and shorter phases than default; this will harm really
busy intersections". The user's run (node 498446, a 1-lane X under the axis plan 19/6/19/6): `q_arm=498198:28.9,
498258:28.6,498390:23.4,5903:21.7`, `op=plan result=fits total=169 queued=102.6 load=1:89.1,3:91.1 old=19/6/19/6
new=19/6/19/6 cycle=50>50`: balanced, saturated, nothing changed because Re-time kept the cycle. Design: RETIME_PLAN.md
"Step A v2".
- **Cycle** (sl_retime.lua `R.cycleFor`): Webster's C = (1.5 L + 5) / (1 - Y) in 40..120 s; saturated (Y >= 0.9) or a
  standing queue (>= 4 cars per lane on a critical approach) -> 120 s; saturation flow estimated from the queued
  approaches' passes per green second (else 1800 cars / lane / h); the greens split as before (60 s cap each, a capped
  phase leaves its share to the others). The user's junction now: Y = 1.59 (sat 2263 est), L = 16 s, saturated ->
  cycle 50 -> 120 s, greens 19/19 -> 54/54 s (test_retime.lua "a player's saturated 1-lane crossroads"). Since
  cycle rule v3 (Light plans A/B run 2, RETIME_PLAN.md "Cycle rule v3 and damping") a balanced saturated junction (the
  busiest road's load share <= 62.5 % for two roads) stops at max(75 s, the current cycle): this one 50 -> 75 s,
  greens 31/32 s.
- **Background.** Deselecting, another junction or closing the tool no longer cancel; the button at that junction
  does, a lane / phase change or the light gone stop it. Up to 5 runs at once since rev 9 ("Several Re-time runs at
  once" below; before: one at a time, another lit junction's Re-time grayed).
  `C.bgStep` is stepped by an invisible ModEntryPointExtension plugin (`sl_bg.script.lua`, `sl_bg.res.lua`) through the
  shared state module `sl_toolstate.lua`; it does nothing while the tool's own step runs. Whether the plugin and the
  tool share a Lua state is unverified (TESTING.md RT 9; `op=bg` says it ran); if not, the run pauses while the tool is
  closed and the window moves on by the gap (`gaps=`), so it still measures 180 s of traffic.
- **Status** (`C.retimeLines`, under the selection's two lines, translated): while it measures "Re-time: measuring
  traffic (87 of 180 s)"; afterwards the junction's saved last-measured record, read the same way for both modes
  (step B v4, RETIME_PLAN.md "Records and status"): "Last measured 4 min ago (manual): cycle 50 -> 75 s" | "...:
  already fits" | "...: too little traffic" | "...: not written (see log)". (Until step B v4: GUI memory only, lost on
  reload, with "Measured 4 min ago: 18 / 7 cars/min per road" from `R.roadRates`.)
- **Cost** (sl_retimer.lua): candidates not ahead at the last sample are placed first (one call); beyond 200 m they are
  skipped until they could be near at 40 m/s (`farUntil`); only near ones get the driving / path reads. The user's run
  read ~1425 candidates per sample (~315 near): before ~5 engine calls each (~7.1k) + ~1.7k path reads = ~8.9k per
  sample; now ~315 x 5 + 1.7k + at most one position read per far candidate, most skipped (test: 0.10 calls per far
  driver per sample vs >= 4 before) = ~3.4-3.9k, about 55-60 % fewer. `calls=` / `calls_per_sample=` /
  `far_skipped=` in `op=measured` measure it in game.

### Several Re-time runs at once (rev 9, user request 2026-10-17; implemented offline, not run in game yet: TESTING.md "RT5")
The user: allow up to 5 Re-time runs at once, "as long as there's only an impact while the user specifically asks for
it to be re-timed. once timing is done, there should be no impact again." Built on the mechanism of "Several recordings
at once" ("Traffic rate at a junction").
- **Up to `Core.RETIME_MAX_RUNNING` = 5**, each at its own lit junction, started and canceled with the Re-time button
  there ("Measuring: click to cancel"), each with its own 180 game s window, measurement, plan and write. The 6th lit
  junction: Re-time grayed "Re-time is measuring 5 junctions, the most at once" (the button's tooltip and, through
  `C.grayLines`, the status line "Grayed out: ..."; the click gives the same text and `RETIME op=refuse reason=full
  running=5`). `C.grayLines` still leaves out the passing reasons another line already gives ("Re-time is measuring
  here", "A write is still landing", "Waiting for the last change to land"); the cap is no passing reason, so it shows.
- **One shared sampler run** (`C.retimer`, `sl_retimer.lua` `M.startShared` / `addTarget` / `removeTarget`, as
  `C.recorder`): each run is a target (`retime = true`: passes keyed by movement, queued cars counted per target;
  `windowS`: `M.step` returns "done" with `target.over` once its window is over, before the next sample). One
  candidate pass per sample for all runs, one `Retimer.BUDGET_S` (1.5 ms of clock) per frame for all: with more runs a
  sample takes more frames, never more time per frame; each run still measures 180 game s (fewer samples when busy).
  For a single run the measurement is the one before byte for byte (the RT tests' `passes=` / `queue=` / `reroute`
  numbers unchanged). The single-junction `M.start` / `M.result` / `M.progress` were dropped (nothing else used them).
  Re-time and Record traffic keep their own instances (another interval, window and budget), as before.
- **No cost when nothing runs.** The sampler run starts with the first run and is canceled as soon as no run measures
  (a run waiting to write has no target); a finished, canceled or failed run is dropped from `C.rts` / `C.rtList` at
  once (`rtDrop`). `C.retimeStep` and `C.bgStep` return at once with no run, timer or re-route check
  (`rtPending`); the probe after a write (timers at +5 / +30 game s, re-route checks) ends within ~30 game s as before.
  Per frame while runs exist: one walk over at most 5 entries.
- **Writes.** Each run plans when its window ends; its write waits while a proposal of the tool is pending (`rtBusy`:
  job, write re-read, `phaseHold`), so runs ending in the same frame write one after the other (each ~VERIFY_DELAY
  frames after the last landed; the status there "Re-time: waiting for the last change to land"), within
  `RETIME_WAIT_FRAMES` (600) as before.
- **Keep timing adjusted pause:** `opts.manualBusy` (sl_bg.script.lua) calls `C.rtMeasuring()`: true while any run
  measures, computed from the run list each call (no flag that could stick): false once the last one is written, waits
  to write, is canceled, fails (an error drops every run: `rtDropAll`) or with none. `C.autoBusy(node)` still holds the
  automatic writes at a junction with a run (measuring or waiting).
- **Status:** at a measured junction its own progress line as before; anywhere else (another junction, a street,
  nothing selected: below the light timing lines) one line "Re-time measuring junctions: 3" (`C.retimeCountLine`), above
  Record traffic's count line.
- **Save safety:** runs live in the tool's GUI state only (`C.rts`), never in the save; a load starts with none, as
  before with one. Each write and its record (`op=last`) are what a single run sends.
- New strings: "Re-time is measuring %d junctions, the most at once", "Re-time measuring junctions: %d"; dropped:
  "Re-time is measuring another junction", "measuring another junction".
- Tests: test_tool.lua "re-time (tool): several at once ...", "at most Core.RETIME_MAX_RUNNING at once ...", "five at
  once stay within the one per-frame budget ..." (a ticking fake clock), "Keep timing adjusted's pause (C.rtMeasuring)
  ... then bgStep and the sampler do nothing per frame" (step calls counted), "toolbar rows: Re-time while it measures
  ..." (another lit junction starts its own), and the earlier RT tests unchanged in their numbers.

### Keep timing adjusted: automatic re-timing per junction (rev 8 step B, user 2026-10-14; measuring redesigned as queue snapshots 2026-10-15 (step B v4); implemented offline, not run in game yet: TESTING.md "KA v4")
Design and reasoning: RETIME_PLAN.md "Step B" and "Step B v4". In short:
- **UI.** The base Yes / No toggle "Keep timing adjusted" (2026-10-15, replacing a CheckBox that showed unchecked at
  enrolled junctions until its first click) in a **third toolbar row** of its own (group `sqrl_tool_auto`), shown with
  the light row (a lit junction), as twin params `sqrl_tool_auto_on` (default Yes, shown at an enrolled junction) and
  `sqrl_tool_auto_off` (default No, shown otherwise): right from the first frame; after a click both stored values
  follow the selected junction's state (RETIME_PLAN.md "The toggle (UI)"). A click's side is the intent (Yes enrolls,
  No unenrolls). Re-time at an enrolled junction runs the manual 3-minute measurement as anywhere (the automatic writes
  there wait). Status "Keep timing adjusted: counting waiting cars (3 of 8)" | "...: next check in 12 min", then
  the junction's last-measured line (both modes alike): "Last measured 12 min ago (auto): cycle 52 -> 72 s". CSS rules
  4 before and after.
- **Storage.** Game-script state `auto = { {n, x, y} }` (<= 1000), `aseq`, `aall`, `areq`, `arun`, and the records
  `rlast` (<= 1000) / `lseq` (`sl_auto.lua`, event `SmartLanes.auto`); keyed by position (id or within 2 m; re-attached
  at every refresh, pruned when no lit node stands there). See "Save safety".
- **Runtime** (`sl_autoretime.lua`, stepped every frame by the background plugin `sl_bg.script.lua`, so it runs with
  the tool never opened), low importance by design (user 2026-10-15): every 120 game s a **snapshot** counts the cars
  standing on each watched junction's approaches (the inbound half of a 24 m strip, 6-150 m out), one pass over the
  drivers (routed lists for up to 48 approach segments, else the SIM_PERSON list; 1 ms per frame), no route reads;
  per approach an arrival estimate under the timing in force, averaged over ~20 game min. After 8 snapshots a junction
  is **decided** (`R.planQueue`: the v3 cycle rule, damping, hysteresis max(4 s, 20 %); quiet junctions never write),
  then every 10-60 min (setting "Keep timing adjusted: check interval" `sqrl_auto_every`: x0.5 / x1 / x2 / x4 of that,
  default x1), sooner when its queues clearly change after a quiet or fits decision (early wake, `op=wake`). **Writes**: one per 5 game s map-wide, the largest gain first, held while the player builds
  within 300 m or a tool proposal is pending, at most one per junction per 10 game min; the cycle moves at most 20 s
  per write; hand-edited phases adopted as the new base (only lengths are written).
- **v3** (Light plans A/B run 2, 2026-10-15; RETIME_PLAN.md "Cycle rule v3 and damping"): balanced saturated junctions
  stop at max(75 s, current) (manual too); loads smoothed with the junction's previous decision (in memory, not saved);
  a long cycle only after two long decisions in a row (else `cycle_reason=unconfirmed`, next decision in 5 min). The
  v3 settle delay and sampler (incremental path reads, `member_gone`) went with v4's snapshots (HISTORY.md).
- Tests: test_auto.lua (storage, records, event, intervals, size bound), test_retime.lua ("timingOf / arrivalOf",
  "planQueue: ...", "onCorridor / queueIndex / queueHits", "replay run 2 ...", "plan v3 ..."), test_tool.lua "keep timing
  adjusted (tool|tool script|runtime|bulk|cost, v4|budget): ..." (twin toggles, status lines, snapshot counts per inbound corridor
  with routed and scan sources, decision -> write -> record -> status, quiet back-off, the write scheduler's holds,
  stale drop, gain order and gap, re-attach / prune, adopt / lanes reset, removed segment, the manual pause, enroll all /
  zone / clear, cost for 10 / 100 / 500 junctions, the check interval setting read by the runtime, early wake), test_auto.lua
  "check interval setting", test_zones.lua ("sl_auto").

### Stress Test interface: Keep timing adjusted (rev 8 step B; Stress Test side built 2026-10-14: plans/square_stress_test/SHOWCASE.md "Light plans A/B", TESTING.md 6Z1 / 6Z2)
Both go through the channel the zones use (`api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("",
"square_smart_lanes", <event>, <payload>))` from any GUI Lua state; Smart Lanes' game script stores them).
1. **A/B twin: zone mode `sl_auto`** (event `SmartLanes.zones`, `op = "set"`, as every zone; `Zones.AB` gains
   "sl_auto", so an older Smart Lanes refuses the whole set with `ab<i>`, as with `sl_classic` then). Inside: as `sl_phases`
   (Smart Lanes lanes + the axis plan in the automatic pass and the tool, whatever "Light phases" says), and every lit
   junction in the circle (standing light with phases) is enrolled by the runtime (`SmartLanes.auto add src=zone`), at
   the latest ~30 game s after it got its light (a zone is looked at again every 30 s until its junction is enrolled,
   one zone per frame). Twin letter `v` (a-u are taken: `stress_flow` TWIN_LETTER,
   MID_LETTER p-t, `u` sl_classic, dropped 2026-10-16), label "Auto timing", compared with `sl_phases` (axis plan as built) and `game`.
   Clearing or replacing the zones does **not** unenroll: send `op = "clear"` (below) at the end of a run.
   `byAbText`: `,sl_auto:<n>` after the ring layout variants (after `,sl_classic:<n>` until 2026-10-16), only when > 0
   (the Stress Test's `slZonesByAb` must append it the same way).
2. **Whole map: event `SmartLanes.auto`**:
   - `{ op = "all", run = "<id>" }` (src defaults to "stress"): every lit junction on the map is enrolled, at most 1000
     in all (256 before step B v4). Logged `AUTORETIME op=enroll_all phase=request run=<id> src=stress` when stored, then (GUI runtime, within
     a few frames: 64 nodes looked at per frame) `AUTORETIME op=enroll_all phase=done run=<id> src=component|octree
     nodes=<lit list> lit=<with phases> already= sent= capped=`, and one `AUTORETIME op=enroll node= pos= src=all total=`
     per junction. The request is answered once, in the session it was sent (a request already in the save when the
     runtime first reads it is taken as done). Junctions lit after the request are not enrolled (send it again).
   - `{ op = "clear", run = "<id>" }`: every junction unenrolled: `AUTORETIME op=unenroll all=1 n=<count> run=<id>
     src=stress`.
   - `{ op = "add" | "remove", nodes = { {node, x, y}, ... }, src = "stress" }` (at most 60 per event): single
     junctions.
   - Read-back (as `zrun`): the game-script state's `arun` = the run of the last all / clear; `aseq` +1 per change;
     `auto` the list (GAME_SCRIPT component, `state_native:find("arun")`).
3. What a run sees in the log (step B v4): `AUTORETIME op=snapshot` every 120 game s, and per enrolled junction each
   decision `AUTORETIME op=plan ... result=write|fits|quiet ... zid=` and, for a write, `AUTORETIME op=write ... sent=1
   ... zid=` plus `LIGHTS src=auto node= to=retime ... action=auto zid=`. The first decision comes ~16 game min after
   the junction is watched (8 snapshots), later ones 10-60 min apart; the cycle moves by <= 20 s per write and a long
   cycle needs two long decisions, so a saturated unbalanced junction reaches 110-120 s ~45 game min after enrolling.
   A twin run should last ~90 game min or more, compared after the last write (before v4: first write ~3 min after
   enrolling, writes 5 min apart).
4. `tools/flow_report.py`: AUTORETIME lines are not RETIME lines, so they do not split sets (the twin is its own mode).
   What the report has (built in tools/flow_report.py 2026-10-14; settled window = first write + `--auto-settle`, default 900 game s): `sl_auto` in `AB_ORDER` / `COMPARISONS` (sl_auto vs sl_phases, sl_auto vs
   game) / `PLAN_NAMES` ("auto") / `PLAN_ABS`; optionally a per-twin "settled from" game time = its first
   `AUTORETIME op=write sent=1` + N writes, or the last write + `--retime-settle`, to compare the converged timing; for
   the whole-map switch (no twins) a before / after split at `op=enroll_all phase=done`.

### Lane status reason (a)
`Rules.oneLaneEach(conns, bus)`: every approach enters on one car lane (bus-lane connections left out). C.nodeStatusOf
records it (`oneLane`, `bus`) for crossroads / T-junctions; a street / multi selection only when every junction has
it. `Pick.badge`: smart = default and oneLane -> "Smart lanes = game default (one car lane per road)" or "...; bus
lanes kept)" with a bus-only lane; otherwise "Smart lanes (= game default)" as before. Rings keep their label.

## Ring lane use (zone modes 2026-10-15; bench s5 ran 2026-10-15; user request 2026-10-14)

**Result (bench s5, session `2026-10-15_0602_bench-s5-ring-34019`, RESULTS.md verdicts):** `sl_rmid2` rejected (gridlock
under heavy traffic, 3/3 sets: crossing lane changes at the mid nodes); `sl_rturbo_in` and `sl_rspread` rejected for
4-lane rings (no gain over turbo, both jammed in the even mix); matched beat turbo on 2-lane rings with 2-lane arms in
every mix (ring lane use ~50/50 vs turbo ~20/80). **Decided 2026-10-15 (user)**: matched is the default there ("Default:
matched lanes on 2-lane rings with wide exits" above); turbo stays on 3/4-lane rings; a saturation test of the shipped
`sl_rmid` default (2-lane rings, 1-lane exits) is being prepared separately.
Evidence: the user's 2-lane ring 282381 (4 two-lane arms, session 2026-10-14 live log, PICK/CONN lines): turbo layout,
entry e1 -> o1, e2 -> o2; o1 arriving exits only, o2 exits or continues. Every car going past the first exit queues in
the inner entry lane and merges into o2, the only circulating lane: about one lane of through capacity (user screenshot:
"every car lines up for the middle lane before the roundabout"). The bench tests that made turbo the default spread
traffic over all exits. On 4-lane rings with 3-lane arms nothing enters or leaves o4 (see "Ring layouts" above).
Manual "Insert node" tool: deferred (user agreed); add nodes automatically only if a run shows a missing lane-change
point. Nothing here changes a default: two more ring layout variant zone modes (as sl_rturbo .. sl_rmid, outside their
zones byte for byte as before) and the bench interface below.

### Zone modes (sl_rules M.variantConns; lanes curb first, o1 = outer; R ring lanes, E / N exit / entry lanes)
- **`sl_rmid2`** (sl_rmid for wider exits). Junction: X = min(E, floor(R / 2), m) exit-only lanes as sl_rmid (m = the
  fewest mid nodes on an entry-to-exit stretch), o_i -> x_i for i <= X; an exit wider than X is fed by the first
  circulating lane: o_(X+1) -> x_(X+1)..x_E, which also goes straight on (sl_rmid instead fans o_X -> x_X..x_E); inner
  lanes straight; entries e_j -> o_min(j, R). Mid nodes: sl_rmid's (every lane straight, both ways between neighbouring
  lanes). Exits of at most X lanes: exactly sl_rmid (tested). Every exit lane fed by one ring lane, no lane change at a
  junction, reachable without lane changes on segments.
  2-lane ring, 2-lane arms: junction `o1 -> x1` (exit only), `o2 -> x2`, `o2 -> o2`, `e1 -> o1`, `e2 -> o2` (5: the
  turbo junction), mid node `o1 -> o1, o1 -> o2, o2 -> o1, o2 -> o2` (4). The difference to turbo: a car entering in the
  curb lane can move in at the mid node, so both entry lanes reach every exit (turbo: e1 the next exit only; tested,
  test_rmid2 "each entry lane").
  Mid nodes: **Smart Lanes adds them itself** in an sl_rmid2 zone (sl_split, as the default spiral; `Rules.SPLIT_VARIANTS`,
  `plan.splitWanted`; the automatic pass and the tool's ring Apply), so the bench needs no dev mid nodes for these twins.
  A refused split (or a ring where no stretch can be split): the junctions get **`sl_rturbo`** (`Rules.MID_FALLBACK`;
  `RSPLIT ... mids=0 fallback=sl_rturbo reason=`), the same junction without the mid-node lane changes. `sl_rmid` /
  `sl_rsplit` zones still never split (the bench builds their mid nodes: Sheet 4) and fall back to sl_rspiral.
- **Point 1, decided**: a new mode, not `sl_rmid` widened. `sl_rmid` zones already apply regardless of exit width (no
  `spiralDefault` gate inside a variant zone): on a 2-lane ring with 2-lane exits it gives `o1 -> x1, x2` (the fan),
  `o2 -> o2` only, `e1 -> o1`, `e2 -> o2` (4) with the same mid nodes: one ring lane of exit capacity. Changing it would
  change Sheet 4 v4's measured mode; `sl_rmid2` lets both be benched.
- **`sl_rturbo_in`** (turbo with the inner lanes fed). Only on rings where turbo qualifies (every exit >= 2 lanes, no
  skipped junction); otherwise matched lanes as sl_rturbo. At an arm with exits that leaves ring lanes out (R > X =
  min(E, R)): o1 -> x1 only (turbo), o_i -> x_i and straight for 2 <= i < X, **o_X -> x_X only** (exit only), **o_i ->
  o_(i-1) for X < i <= R** (one lane outwards at the junction), o_R also straight (it circles for the far exits and the
  U-turn). Arms with R <= X: sl_rturbo's junction. Entries e_j -> o_min(j, R), and the innermost entry lane also feeds
  every lane inside its own: **e_N -> o_(N+1)..o_R** (a split). Entry-only junctions: every lane straight, entries as
  above (no ramp own-lane entry). No two ring lanes into one lane (each ring-out lane gets at most one ring lane plus the
  entry's give-way), every exit lane fed by exactly one ring lane, every entry lane reaches every exit without a lane
  change on a segment (the innermost lane reaches x_X by its shift: o4 -> o3 at one arm, o3 -> x3 at the next); tested
  3-6 arms, both directions and traffic sides, mixed 2-/3-lane arms, ramps. Why the shift and not o_R -> x_X: that is
  sl_rspread's merge (two ring lanes into one exit lane); without a node connection out of o_R the lane would rely on
  segment lane changes, which the evidence says cars don't plan for. Cost: the entering e_N -> o_R crosses the o_R ->
  o_(R-1) shift inside the junction (like any entry crossing a circulating stream).
  - 4-lane ring, 3-lane arms (rb4l; turbo 9): `o1 -> x1`; `o2 -> x2`, `o2 -> o2`; `o3 -> x3`; `o4 -> o3`, `o4 -> o4`;
    `e1 -> o1`, `e2 -> o2`, `e3 -> o3`, `e3 -> o4` (10). Per entry lane: e1 the next exit, e2 every exit, e3 the next
    exit (o3) or any (o4). Through capacity: o2 and o4 circulate (turbo: o2 and o3, o4 empty).
  - 3-lane ring, 2-lane arms (turbo 6: o3 unused): `o1 -> x1`; `o2 -> x2`; `o3 -> o2`, `o3 -> o3`; `e1 -> o1`,
    `e2 -> o2`, `e2 -> o3` (7). Through traffic still uses e2 only (as turbo), but now on its own ring lane o3.
  - 2-lane rings, 3- and 4-lane rings with arms as wide as the ring: identical to sl_rturbo (R <= X everywhere).
- **Point 3, confirmed**: `sl_rmatch` applies on 2-lane rings with 2-lane exits: `o1 -> o1, x1`, `o2 -> o2, x2`, `e1 -> o1`,
  `e2 -> o2` (6), written whole (test_ringvar WANT "2:2", test_rmid2).
- Counts per arm junction (4 arms; rmid2 without mid nodes = rturbo; test_ringvar TABLE): 2:2 rmid2 5 / rturbo_in 5,
  2:3 7 / 7, 3:2 6 / 7, 3:3 8 / 8, 4:3 9 / 10.
- Zone contract: ab `sl_rmid2`, `sl_rturbo_in` (<= 12 characters); sl_zones `by_ab` appends `,sl_rmid2:<n>,sl_rturbo_in:<n>`
  after `,sl_auto:<n>`, each only when > 0. Logs as the other variants: `APPLY ... layout=sl_rmid2|sl_rturbo_in [mid=yes]
  zid=`, `RSPLIT ring= node= len= mids= per_stretch= nodes= zid=` (sl_rmid2) or `mids=0 fallback=sl_rturbo reason=`,
  `SPLIT ring= node= len= edges= nodes_added= zid=` then `WRITE kind=split ring= success=` (sl_rmid2 twins without mid
  nodes), SUMMARY `zone_ring=`.
- Files: sl_rules.lua (RING_VARIANTS, variantConns, MID_VARIANTS / MID_FALLBACK / SPLIT_VARIANTS, planRing
  `splitWanted`), sl_lanes.script.lua and sl_toolcore.lua (split when `plan.splitWanted`), sl_zones.lua. Tests:
  test_rmid2.lua (new), test_ringvar (WANT, counts), test_zones, test_tool (Apply in an sl_rmid2 zone splits).

### Bench interface for the Stress Test (Smart Lanes side done; Stress Test side built 2026-10-15 as bench Sheet 5, offline-tested, not run yet: plans/square_stress_test/BENCH.md "Sheet 5", its TESTING.md 6Y2)
- Twins (stress_bench AB): `sl_rmid2` = `w` "Ring mid 2", `sl_rturbo_in` = `y` "Ring turbo in" (the suggested p / q are
  Sheet 4 v5's MID_LETTER letters); the Stress Test's own by_ab text (stress_logic slZonesByAb) in Smart Lanes' order,
  tested byte for byte against sl_zones.lua's byAbText.
- As built: tests `lu2` (2-lane ring, country medium arms: game / sl_rturbo / sl_rmid2 / sl_rmatch) and `lu4` (4-lane
  ring, country large arms: game / sl_rturbo / sl_rturbo_in / sl_rspread), 3 sets each, one mix per set (even, straight,
  adjacent); the 3-lane ring with 2-lane arms skipped (the entry roundabout has country large arms only). The RINGMIX line
  is `[SQST] RINGMIX run= s= zone=<n> twin=<zid> pair= ab= gt= arms= dir= n= exit1= .. uturn= none= reads= capped= final=
  [mix=]` (zone= stays the run's zone number as on every FLOW line, the zid is `twin=`), cumulative per sampler run, plus
  `[SQST] RINGLANE ... radii=<m>:<car samples>,...` (ring lane occupancy by distance from the centre; the report clusters
  it into lanes, o1 = outer). Contract: plans/square_stress_test/FLOW.md "RINGMIX / RINGLANE".
- Rings, 3 sets each (the user's call on more):
  - **2-lane ring, 2-lane arms** (`bench_rb4`: square_roundabouts ring lanes 2, country medium arms; no dev mid nodes
    needed): `game`, `sl_rturbo` (what `sl` wrote there until 2026-10-15; now `sl` is matched there), `sl_rmid2` (expect one `SPLIT ... nodes_added=4` per
    twin, then `RSPLIT ... mids=4` and 8 APPLY), `sl_rmatch`; optional `sl_rmid` (the fan; it falls back to sl_rspiral
    without dev mid nodes, so only with `sqrb_dev_ring_mid = 1`, which then every twin of the set should get).
  - **4-lane ring, 3-lane arms** (`bench_rb4l`): `game`, `sl_rturbo`, `sl_rturbo_in`; optional `sl_rspread` (the same idea
    with the merge at the exit instead of the shift).
  - **3-lane ring, 2-lane arms** (new: the entry roundabout `bench_rb3` with 2+2 arms, if stress_entry_streets can take a
    medium arm; square_roundabouts has no 3-lane ring): `game`, `sl_rturbo`, `sl_rturbo_in`. Skip if it needs new geometry.
- Traffic mixes from the Junction test's corner towns (one town per arm, arms A, B, C, D in the ring's travel order;
  town-to-town demand is symmetric):
  - **even**: four equal towns (every exit and the U-turn alike, as the earlier benches);
  - **mostly straight**: A and C large, B and D small (opposite corners): A <-> C trips take the 2nd exit both ways;
  - **mostly first exit**: not possible with symmetric town demand on 4 arms (A -> B is the 1st exit, B -> A the 3rd).
    Nearest: **adjacent** (A and B large, C and D small): mostly 1st + 3rd exits, few straight. A true first-exit mix
    needs one-way demand (a cargo chain, or bus lines that leave at the next arm); say so in the sheet.
  - Every set logs its measured mix (RINGMIX below), so the label is checked, not assumed.
- **Turning-mix log: in the Stress Test, not in Smart Lanes** (decided 2026-10-15). The Stress Test's flow sampler
  already reads each driver's path (`MOVE_PATH.path.edges`, `elem.edgeId.entity`, docs/findings/lines-vehicles.md) and
  knows each twin's arms (stress_junctions reads the arm ends) and zone ids; Smart Lanes reads no driver path at a ring
  (its only sampler is Re-time's, at lit junctions), so a Smart Lanes RINGMIX would be a second sampler doing the same
  reads. Spec: `[SQST] RINGMIX run= s= zone=<twin zid> arms=<A> n= exit1= exit2= exit3= uturn= none=` per twin, at the
  end of each set's window (counts over its samples, each driver once: by its entity id, the first sample that shows
  both its entry and exit). Per driver of the zone: the first inbound arm edge and the next outbound arm edge of that
  twin on its path; k = arms passed from entry to exit in travel order (arms sorted by angle around the twin's centre,
  counterclockwise for right-hand traffic, clockwise for left: the APPLY lines' `dir=` says which), `exit<k>` for
  k < A, `uturn` for k = A (the same arm), `none` = a path that enters and leaves through no arm in the read part (a
  path that ends inside, or the read cap); with more than 4 arms `exit4=` .. `exit<A-1>=`. Budget: no reads beyond
  thru_path's (the bench turns `pathThru` off: ring sets need it on, or a capped subset, e.g. 200 path reads per sample);
  pure Lua on the paths already read. tools/flow_report.py: the mix per twin and set in the ring table, and the
  verdicts grouped by mix.
- The user's own ring (not a bench twin): its mix from the SQRB_TURN console line (session 2026-10-14 conversation;
  counts per arm how many ring junctions each routed driver passes), as before.
- Report per ring: each mode vs game and vs sl_rturbo, per mix (cars/min through, km/h, standing %).


## Automatic timing for all lights + first-load welcome (planned 2026-10-15; implemented offline 2026-10-15, not run in game yet: TESTING.md "AL")
User 2026-10-15 (first plan): "a mod setting so you can opt in (you manually enable one light) or opt out (you manually
disable)", and ask once, the first time a game is loaded with the mod. User 2026-10-15 (build now, no longer waiting for
the funnel-city runs): default opt-in, a setting for opt-out; on the first load of a game that has not seen the question,
a dialog that explains how the mod works and asks whether to apply Smart Lanes and automatic light timing to all
streets, suggesting a save first in case the player changes their mind.
- **Setting "Automatic light timing"** (mod.json, 13 languages): **Junctions I choose** (default, opt-in: today's
  per-junction Keep timing adjusted toggle) / **All lights** (opt-out: every lit junction enrolled, lights built later
  too via the periodic lit-junction listing `op=enroll_all` uses; a junction the player unticks is remembered as opted
  out; junctions whose phases the player timed by hand (`user_modified`) are skipped unless ticked by hand).
- **First-load welcome, once per save** (no change to a save without consent: "Save safety"): the first load of a save
  (not the map editor) whose game-script state has no answer yet, new games included. A small native window (GUI
  script, base `builtin.*` widgets, no new stylesheet rules; `docs/ui-guide.md`): a few short lines on what Smart Lanes
  does (lanes at junctions as you build, the road tool, automatic light timing), then two checkboxes for what is
  already on the map: "Convert all existing junctions to Smart Lanes" (ticked) and "Switch all traffic lights to
  automatic timing" (unticked: the lights stay opt-in; user 2026-10-16), each with a two-line tooltip (the text lines
  broken at 50 columns in code, `AllMode.wrapLine`: a TextView does not wrap, a long line was cut off in game); a tip "Save your game
  first, so you can go back if you change your mind."; buttons [Apply] [Not now]. The answer is kept in the
  game-script state (asked once per save; Not now is an answer too). Apply with the lights box ticked switches this save
  to all-lights mode (a per-save override of the setting). A way back later: the tool offers "Adjust all lights" /
  "Stop for all lights" (since the settings panel: its "Automatic light timing", in the tool with nothing selected
  and in the Crossing Tool; "In-game settings panel" below).
- **Existing junctions pass** (Apply with the lanes box ticked): every street junction on the map planned as the
  automatic pass would after a build (rings whole, slips, crossroads, T-junctions; kept / Reset and hand-edited nodes
  skipped), in time-budgeted slices over game ticks with a hard node cap and a visited set (CLAUDE.md loop rule),
  progress and the end in the log (`[SQRL]` line) and the status of the dialog / tool.
- **Cap:** enrolled max 1000 (`Auto.MAX`), first come; the cap hit is logged. Busiest-first or a raised cap after a
  large-map cost test.

### Implemented (2026-10-15, offline; not run in game yet)
Files: `sl_allmode.lua` (new, pure: resolution, opt-outs, timed by hand, the welcome's decision, the pass's slices),
`sl_auto.lua` (event ops `mode` / `welcome` / `pass`, readSaved extras), `sl_lanes.script.lua` (handler; the
existing-junctions pass in the GUI script), `sl_autoretime.lua` (the all-lights listing), `sl_toolcore.lua` +
`sl_tool.script.lua` (rows 4 / 5, status line), `sl_bg.script.lua` (the welcome window), mod.json `sqrl_auto_lights`.
Tests: test_allmode.lua, test_tool.lua "all lights (runtime | tool | welcome | existing-junctions pass)".
Choices made where the spec was open:
- **Mode** = the save's `amode` when set, else the setting. Apply with the lights box writes `amode = "all"`;
  "Adjust all lights" writes `all` (and clears the opt-outs: an explicit "all"); "Stop for all lights" writes `pick`
  and, coming from All lights, unenrolls every junction (hand-picked ones too; since 2026-10-17 a `pick` after Off
  keeps the list: "Idle runtime and Off" below). Junctions I choose never lists anything.
- **Listing** (`sl_autoretime.lua`): every `AllMode.LIST_EVERY_S` = 300 game s, and at once when the mirror is first
  read or the mode turns all; the same lit-node list as `op=all` (BASE_NODE_TRAFFIC_LIGHT, octree fallback), 64 a
  frame; enrolled and opted-out junctions are matched by position before any light read. Its `enroll_all
  phase=done run=allmode` line only when it sent or capped something (and once per session). Cap: `Auto.MAX`
  first come (list order), `AUTORETIME op=cap_hit src=allmode max= enrolled= capped=` once per session.
- **Opt-outs**: a tool remove (`src=tool`) while all lights are in force adds the junction to `aout` (AUTORETIME
  `op=optout ... optouts=`), a tool add removes it (`op=optin`); the handler also drops `src=all` adds of
  opted-out junctions (a listing that read them before the opt-out landed). A prune (light gone) is not an opt-out.
- **Timed by hand** (`AllMode.handTimed`): the game logs showed that our own phases-only writes set
  `userModifiedTrafficLightStates` (docs/findings/roads.md, 2026-10-15), so the flag alone would skip every junction
  Smart Lanes ever re-timed or curb-freed. Rule: the flag, no `rlast` record of ours there, every vehicle green a whole
  second (the Crossing window's slider; the game's greens are fractional), Light phases not Smart Lanes. Lights only
  at a junction with the Light phases setting Game default reads as hand-timed (the player's own action; Yes there
  includes it).
- **Welcome** (`sl_bg.script.lua`, the background plugin): read 180 GUI frames after the first step, then every 60
  frames up to 10 times while the state is unreadable (then `WELCOME op=skip reason=unreadable`, asked again next
  load); never in the map editor. Closing the window counts as Not now. Lines: three short TextViews, a question
  line, two base CheckBoxes (ticked), the base info hint (`content_card.makeInfoHint`, wraps at ~350 px) for the
  save tip, base `primary` Apply and `secondary` Not now; gaps are inline spacer Components, padding on the content
  Component. 0 new stylesheet rules (`make css-rules`: 4 before and after).
- **Existing-junctions pass** (`sl_lanes.script.lua` guiBody, the job pipeline): the list is
  `getEntitiesWithComponent(BASE_NODE_CONFIG)` (else BASE_NODE, else the octree circle of 20 km around (0, 0)),
  junctions = nodes with >= 3 street segments (lane drops on 2-segment nodes are not included), slices of 160
  (MAX_SEEDS) handed to the automatic pass as jobs `m<n>` one at a time and only while no build job waits; scan budget
  400 entries and 2 ms a frame; hard caps 500000 list entries, 20000 junctions; a visited set, and the slices share
  the rings done (a ring reached from two slices is planned once). Differences from a build's pass: no junction counts
  as touched, so every ring arm goes through the hand-edit guard (`Rules.autoSeeds` with no seeds) and a ring with a
  hand-edited junction is left alone whole (`SKIP ring= node= reason=hand_edit`, no lanes, no split, no lights);
  crossroads / T-junctions whose lanes are neither the game's (`Slip.isDefault`) nor empty are skipped
  (`SKIP kind=cross ... reason=hand_edit`), lit ones that look timed by hand too (`reason=hand_timed`); slip-lane
  junctions and lane drops have no model of the game's lanes and are written as after a build (no way to tell a hand
  edit there: the save-first tip covers it); no lights switched on or off anywhere (the lane writes still carry the
  phases' re-pointing and the curb turn / Smart Lanes phases per the settings, as after a build). It runs whatever
  "Apply automatically to new roads" says (the player asked for it; with Off the GUI script polls the state every
  120 frames). The end goes back as `SmartLanes.auto op=pass` (`mpass.done`); a pass cut short by quitting runs
  again at the next load (`MAPPASS op=start ... resume=1`). Status: the tool's line "Setting smart lanes at all
  junctions..." while it runs (the welcome window closes on Apply).
- **Tool rows** (replaced 2026-10-15 by the settings panel's "Automatic light timing", "In-game settings panel"
  below; the switch itself, C.setAllLights, is the same): "Adjust all lights" and "Stop for all lights" were rows 4 and 5 (groups of their own: side by side
  they would not fit the 314 px bar in German / Russian), shown only with nothing selected and each only where it
  acts (Adjust while not all lights; Stop while all lights or any junction is enrolled). The status with nothing
  selected gains "Light timing: all lights (N junctions)" / "Light timing: junctions you choose (N)".
- Open: the in-game checks (TESTING.md "AL"); whether `getEntitiesWithComponent(BASE_NODE_CONFIG)` lists in game
  (fallbacks logged as `src=node|octree|none`); the welcome window's default position; busiest-first instead of
  first come when the cap is reached; a larger cap after a large-map cost test.

### New lights at once (2026-10-16, user; implemented offline, not run in game yet: TESTING.md "AL" 12-14)
User 2026-10-16: with All lights, a light added at a junction (the Crossing Tool) or a new lit junction showed Keep
timing adjusted "No" in the tool until the next listing (up to 5 game min): "It's confusing to the player if they check
and it says no." Follow-up: a junction placed by hand gets it through the build callback too, also with "Apply
automatically to new roads" Off, and a light the game adds a moment after the build is looked at again soon. No faster
whole-map listing; the periodic listing stays the safety net.
- **Build path** (`sl_lanes.script.lua` handleNewLights, `sl_autoretime.lua` newStep, `sl_allmode.lua` "New lights at
  once"): every player build (`onPostBuildProposal`, `param[4]`) while all lights are in force, whatever Apply
  automatically says (never the map editor), saves the nodes it touched (`nodeConfigsToAdd` / `nodeConfigsToRemove`,
  added nodes, the added segments' ends; at most `NEW_SEEDS_MAX` = 60) minus those enrolled or opted out by id, as
  `alit = { seq, nodes = {{id, seq}} }` (the latest `NEW_SAVED_MAX` = 60; aseq + 1). The runtime's mirror takes the
  ones added since its last read (the first read of a session only takes the seq) into a queue (at most
  `NEW_QUEUE_MAX` = 240) and looks at `NEW_PER_FRAME` = 16 a frame: a standing light with phases there, not enrolled,
  not opted out (by position too), not timed by hand -> `SmartLanes.auto add src=build`; no light yet -> looked at
  again 3, 10 and 30 game s after the first look (`NEW_RETRY_S`), then given up. Cap `Auto.MAX` as the listing.
- **Selection path** (`sl_toolcore.lua` C.allSelect, called from C.select): a lit junction selected in all-lights mode
  that is not enrolled is enrolled at once when `AllMode.decide` allows it (not the map editor, not opted out, not
  timed by hand, under `Auto.MAX`): `add src=select`, applied to the tool's mirror at once, so the twin toggle shows
  Yes at once (no twin pending state needed: the twins follow the mirror). Otherwise the status line under the
  toggle says why: "Not adjusted: you turned it off" / "Not adjusted: timed by hand" / "Keep timing adjusted: at most
  1000 junctions" (13 languages). An untick (setAuto No) in all-lights mode adds the opt-out to the mirror at once.
- **Handler rules**: adds with `src=build` / `select` only while all lights are in force (else dropped silently), and
  never for an opted-out junction (as `src=all`). The timed-by-hand rule is shared (`AllMode.handTimedOf`; the
  listing uses it too).
- **What the Crossing Tool's light toggle fires** (code reading, findings roads.md "The Crossing window's light buttons
  are a player build"): `createTrafficLightProposal` committed with `makeWorldBuildProposalCmd(..., false, true)`, a
  player-initiated build, so `onPostBuildProposal` with `param[4] == true` should fire. Which nodes its proposal lists is
  not seen yet: the `op=new_lights ... segs=0 cfgs=<n>` line answers it (TESTING.md AL 13). If it lists none, the
  selection path still shows Yes at once and the listing enrolls it within 5 game min.
- Our own config writes are player-initiated too (sl_write.lua), so they land in alit as well; enrolled nodes are left
  out in the handler, the rest cost a few reads each (lights-off writes: up to 4 looks, then given up).
- Tests: test_allmode.lua "new lights", test_tool.lua "all lights (new lights at once)", "all lights (tool): selecting".
- **Fixed 2026-10-16:** `onPostBuildProposal` was subscribed only with Apply automatically On (`ensureSubscribed`), so
  after `subscribeToNoEvents` the new-lights path never fired with it Off, although the text above and the test (which
  calls handleEvent directly) said it did. Now always subscribed (handleBuild still returns at once with it Off); test
  test_allmode.lua "onPostBuildProposal is subscribed also with Apply automatically Off".

### New lights get Smart lights (2026-10-16, user; implemented offline, not run in game yet: TESTING.md "NS")
User (coordinator, 2026-10-16): when a junction gets a traffic light and Light phases is Smart Lanes, it should get the
Smart Lanes axis plan as the tool's Smart lights button gives it; Game default: no change.
- **Which builds**: a config-only player build (no added streets): the Crossing Tool's or the node window's light
  switched on, and every other config write (our own, Crossing Tool lane edits, phase edits). Builds that add streets
  are the automatic pass's: with Apply automatically On its lane write carries the plan (`item.lightPlan`) and a light
  the game adds later gets it from the pass's re-check (`RECHECK kind=phases`), so the same junction is never planned
  by both. The game script (`handleNewLights`) saves such a build's nodes in `alit` with a third field 1 when Light
  phases is Smart Lanes (the mod setting, or this save's `sset.phases`, or a saved `sl_phases` / `sl_auto` zone exists)
  and Apply automatically is On; also without all lights, enrolled and opted-out nodes included (`op=new_lights ...
  plan=1`).
- **Apply automatically Off: no plan.** Light phases says "Set when Smart Lanes handles the junction"; with Apply
  automatically Off Smart Lanes does not handle new junctions or new lights (the lanes stay the game's), so the plan
  would come from lanes it never set. Keep timing adjusted's new-light enrollment runs regardless, as before: it
  belongs to Automatic light timing, a setting of its own ("Also lights you build later").
- **The runtime** (`sl_autoretime.lua` newStep / planLook): a queued node with the flag and a standing light gets the
  plan (`W.planLights` with the node's `Slip.classify` view, src `new_light`) only when all hold: Light phases at the
  node is Smart Lanes (the save's setting, or an `sl_phases` / `sl_auto` zone; never in `game`, `sl_lock`,
  `sl_exitfan`, `sl_fan` zones), its phases are still ones the engine made (`Retime.phasesEngineMade`: 2..8 phases,
  all canSkip with minDuration 1.5, every duration fractional or a 3 / 6 / 9 s pause, the flag ignored; so never a
  junction timed by hand, re-timed, Keep-timing-adjusted or planned already, all of which write whole seconds). First
  version used `Retime.phasesDefault` (no flag, the measured 6-phase shape): in game 2026-10-16 every light the user
  switched on was skipped with no log line (1-lane T defaults have 7 phases; the switch may set the flag). Skips now
  log `AUTORETIME op=plan_new ... skipped=<n> why=<reason>:<count>,...`. The tool's `C.phasesDefault` (Reset offering
  "light phases") accepts engine-made phases too. The tool's Reset did not keep it (the saved `kept` list, re-read when `kseq` moves), no tool proposal is pending
  there (`opts.toolBusy`), and it is a crossroads / T-junction (case X). No axis plan: the game's phases stay
  (`PHASES src=new_light ... plan_fail=`). No light yet: looked at again 3, 10, 30 game s later (as the enrollment).
- **Order with Keep timing adjusted**: in all-lights mode a node whose plan was sent goes back into the queue for its
  enrollment look `NEW_RETRY_S[1]` (3) game s later, so the runtime enrolls it with the plan's phases as its base.
- **Caps**: at most `NEW_PLANS_PER_FRAME` = 2 plans a frame (the rest wait for the next frame, no try counted), the
  queue's `NEW_PER_FRAME` = 16 looks and `NEW_QUEUE_MAX` = 240, `NEW_PLAN_LINES_MAX` = 200 PHASES lines per session;
  `alit` stays at `NEW_SAVED_MAX` = 60 entries (3 numbers each now).
- **Cost**: our own phase and lane writes are config-only builds too, so with Light phases = Smart Lanes they are
  looked at once each: one light read (`W.lightRead`) and `phasesDefault` fails on the flag; no plan, no line.
- Light phases in the in-game settings panel: already there since 2026-10-15 ("In-game settings panel"); every reader
  honors the per-save override (`W.phasesMode`, the GUI pass's `G.cfg`, the runtime's `R.slPhases`, and now the game
  script's new-light look). The Light phases tooltip (mod.json and the panel) says a light switched on later gets them too.
- Tests: test_allmode.lua "new lights get Smart lights (game script)", "new lights (alit)", test_tool.lua "new lights
  get Smart lights (runtime)" (two: what is planned and what is left alone; all lights order, the per-frame cap, a
  light that comes later, the in-game setting).

## In-game settings panel (requested 2026-10-15, user; implemented offline 2026-10-15, not run in game yet: TESTING.md "SP")
User: "if possible, show a setting menu in left in game like when in road tool, but also in crossing tool, for the smart
lanes options" (clarified: "the options for lights"). The Smart Lanes light options (No lights at roundabouts and
ramps, Free curb turn, Light phases, Automatic light timing) as toolbar params on the left while the Smart Lanes road tool is open, and
also while the base Crossing Tool is open, changeable in game (per save, overriding the mod.json value, which stays the
default). Open: whether the Crossing Tool's toolbar can be extended by a mod at all, and how a changed value reaches the
game script.

### Implemented (2026-10-15, offline; not run in game yet)
Files: `sl_settings.lua` (new, pure: the per-save overrides, their event, the mirror, the saved-state reader, the one
decode), `sl_settingsui.lua` (new: the toolbar params, shared by both tools; the Crossing Tool insertion and the
`forEachDefinition` wrapper), `sl_settings_replace.res.lua` (new: react-replacement-config -> `sl_tool.script@doReplace`),
`sl_tool.script.lua` (the panel in getDefinition, the wrapper installed at load and in doReplace; rows 4 / 5 gone),
`sl_toolcore.lua` (no button rows with nothing selected), `sl_auto.lua` (op `setting`, src `crossing`),
`sl_lanes.script.lua` (handler; the GUI pass re-derives its settings), `sl_write.lua` (W.modRaw: phases, free turn,
lights), `sl_autoretime.lua` (check interval and Light phases re-derived), mod.json (Automatic light timing tooltip),
strings.json (3 new texts, the old rows' 4 removed). Tests: test_settings.lua, test_tool.lua "settings panel (end to
end)", the getDefinition / all lights tests updated.
- **What**: No lights at roundabouts and ramps (On | Off), Free curb turn at traffic lights (ComboBox), Light phases
  (ComboBox), Automatic light timing (ComboBox), Keep timing adjusted: check interval (x0.5 | x1 | x2 | x4: it fits).
  Apply automatically and the debug log stay mod settings only (the user asked for the light options).
- **Per save**: `sset` / `sseq` in the game-script state (SmartLanes.auto `op=setting key= value= src=tool|crossing`,
  `SETTINGS op=set key= value= param= src= seq=`; nothing written for a value already in force). Automatic light
  timing is the existing `amode` (op=mode, src tool | crossing), so the welcome, the panel and the setting are one
  override. The mod.json value stays the default for new games and other saves; no "back to the mod value" choice
  (choosing the mod's value stores it explicitly).
- **One decode**: every reader goes through `Settings.merged(raw, overrides)` then `Rules.fromModParams` /
  `Auto.everyFactorOf`: `settings()` of the game script (the GUI pass: `G.cfg` re-derived when the overrides change,
  `MODE ... src=save`), `W.phasesMode / W.removeLights / W.freeTurn` (W.modRaw = Settings.effectiveRaw: the mod params
  read each call, the saved overrides polled at most every 0.5 s), the runtime (`R.everyFactor`, `R.slPhases`
  re-derived when `Settings.mirror.version` moves: `AUTORETIME op=config ... src=save`). The engine Lua states keep
  the mod params (they read only Apply automatically and Automatic light timing, the latter with `amode` already, and,
  since 2026-10-16, Light phases for the new-light look, with `sset.phases` read from the state: "New lights get Smart
  lights" below).
- **Mirror** (one per Lua state): the saved values plus values this state sent and the game script has not stored yet
  (shown at once; dropped when stored, when a newer `sseq` / `amode` arrives, or after 5 s: a lost event shows the
  saved value again).
- **The bar** (sl_settingsui.lua): one group `sqrl-settings`, labels above their controls (`displayMode` Vertical;
  labelled params of one group stack vertically, one separator above), `preserveValueInAllCategories` (one stored
  value for both tools, category -1). The shown value: `checkEnabledFn` (every step) sets `param.defaultIndex` to the
  value in force (the menu re-reads the default every step through `getParam`, which returns our table:
  construction.tl:1978-1987, 1044-1051), and after the first click (its `onChangeFn` hands over the params api)
  writes the stored value whenever it differs, as the Keep timing twins do. No twins needed: the default itself
  follows. On | Off is the base toggle with our content (a BoxLayout, so "Désactivé" is not clipped by the bar's
  50 px TextView rule); the long values are ComboBoxes (as the base Town Builder's toolbar params; ui-guide "One of
  many ... or long labels"). Each value carries the param's tooltip: the mod.json tooltip plus "Set here, it applies
  to this game only ..." (Automatic light timing also: choosing Junctions I choose here stops it at every junction).
- **Smart Lanes tool**: shown with nothing selected (`g.core.sel == nil`, or the tool never opened), above the info
  block; it replaces rows 4 / 5 ("Adjust all lights" / "Stop for all lights"): Automatic light timing All lights =
  Adjust all lights, Junctions I choose = Stop for all lights (also unenrolls every junction, as before; the tooltip
  says so), through the controller (`C.setAllLights`: its mirror and result line follow at once). The status line
  "Light timing: ..." stays.
- **Crossing Tool**: `construction_react_util.forEachDefinition` wrapped once per module table (installed at the tool
  script's load, as the verified one-way arrows patch, and by `doReplace` before any recipe runs), the function in
  place kept in the chain (Better Bus Overlay wraps it too, either order); our params go before Underground (after
  BBO's "Line routes"), into a fresh list, never twice (`SETTINGS op=menu where=crossing_tool result=inserted` /
  `present`, once per result and Lua state). Always shown there. The Crossing Tool's action reads only `tramMode` /
  `undergroundMode` (construction_react_util.tl:3323-3330); our params are not `constructionParam`.
- **0 new stylesheet rules** (`make css-rules MODS='square_smart_lanes square_better_bus_overlay'`: 9 before and after).
- Open (in game, TESTING.md "SP"): that the params show and work in the Crossing Tool without disturbing its action;
  that the shown value follows the save before any click (defaultIndex) and after one (stored value); the layout in
  de / ru (labels above, ComboBox widths in the 314 px bar); whether a click in the Smart Lanes tool and the Crossing
  Tool share the stored value as expected.

## Traffic rate at a junction (requested 2026-10-15, user; implemented offline 2026-10-16, not run in game yet: TESTING.md "TR")
User: "show the current traffic rate in any intersection, interchange, node crossing, etc. assuming this isn't too
resource intensive to calculate. clicking a street node should show the traffic rate in the description where smart
lanes is over the past x and y time frames to compare. if it's resource intensive to calculate that for all streets and
save it to have in the smart lanes text, we can also add a manual record button and after recording it will show it".
- Shown in the Smart Lanes tool's info text for the selected junction (node, roundabout, interchange): vehicles per
  minute over two windows (x and y, e.g. the last 2 and the last 20 game minutes) to compare.
- Either measured for all junctions in the background (only if cheap enough), or a "Record" button that measures the
  selected junction and shows the result when done. Open: the counting method and its cost (the Re-time / Keep timing
  adjusted measurement, Stress Test's flow counting), the windows, the save size.
- **Research 2026-10-15 (read-only, no game run):** the engine has no script-readable traffic count per street, lane or
  node (FLOW.md:271; the traffic layer is a native painter only). A true rate needs per-car pass counting, as Re-time's
  measurement (`sl_retimer.lua`, ~10-12 ms per 3 s sample at one junction) and Stress Test's `thru` do; for every
  junction in the background that is a sweep every <= 10 s, too much for the game thread. Queue snapshots (Keep timing
  adjusted, ~0.3 s per 120 game s for 243 junctions, os.clock-timed upper bound) give queues, not a rate.
- **Approach (coordinator, 2026-10-15):** the Record button. "Record traffic" in the Smart Lanes tool measures the
  selected junction with the Re-time pass counting (no light change), going on when the selection changes or the tool
  closes, in 30 s buckets for up to 20 game minutes; the info text shows vehicles per minute over the last 3 minutes and
  over the whole recording (live while it runs, "Recording, 7 of 20 min"). Click again to stop. One recording at a time
  (cap; up to 20 since 2026-10-16, below). Only the last result per junction is saved (like `rlast`, <= 1000 entries, written from first use).

### Implemented (2026-10-16, offline; not run in game yet)
- **Code:** `sl_record.lua` (pure: the bucket ring, rates, the saved records `trec`, their texts), `sl_retimer.lua`
  (options for a second instance: `nodes` (several junctions, `Retime.pathAtMulti`, pass key `<node>@<in>><out>`, no
  queue counting), `candEnts`, `radius`, `budgetS`, `countFn` -> `run.counted`; a Re-time run is unchanged without them),
  `sl_toolcore.lua` (`C.record`, `C.recordStep` / `C.recordTick`, `C.recordLines`, the `trec` mirror, the button state in
  `C.buttons`, the status lines, `C.bgStep`), `sl_tool.script.lua` (the button `sqrl_tool_record`, event
  `SmartLanes.record`), `sl_auto.lua` (event op `traffic`, `M.readTraffic`), `sl_lanes.script.lua` (the handler).
- **Button:** "Record traffic", one base Button in a row of its own (group `sqrl_tool_record`), shown at any selected
  junction (node target: crossroads, T, slip-lane node, lane drop, a roundabout's junction, an interchange's nodes one by
  one) or roundabout (ring target), not on a street or Shift+click selection; listed after the settings panel's params
  (never shown together) and right above the info block. Beside Apply | Reset it would be a row of three, too wide in
  German. Pressed at the recording junction: stops (tooltip "Recording here: click to stop"); elsewhere while one
  records: grayed, "Recording traffic at another junction" (one at a time; since 2026-10-16 up to 20, "Several
  recordings at once" below). No stylesheet rule (css-rules 9 before and
  after with Better Bus Overlay).
- **What is counted:** a junction: every vehicle passing it (all movements, as Re-time). A roundabout: the vehicles
  entering it, i.e. passes at its junctions whose approach is not a ring segment (the candidates come from the routed
  lists of its arm segments only, 1 call per arm; radius 200 m beyond its farthest junction). The log has per approach
  (entry) counts (`arm=`); the text has the totals only (a per-arm list does not fit the status).
- **Sampling:** the same reads and cheaper sampling as Re-time (a far driver placed once and skipped until it could be
  near), a sample every 5 game s (Re-time 3 s: at 40 m/s a driver first seen just beyond 200 m is still ahead at the
  next sample), within 1 ms of clock per frame (Re-time's 1.5 ms is its own). Game time: a paused game takes no samples;
  missed steps move the window on (`gaps=`).
- **Shared sampler with Re-time?** No: a recording at a junction that Re-time measures runs its own instance. Re-time's run is 180 s
  at 3 s, ends in a write and is cancelled by a lane / phase change; the recording is 20 min at 5 s, counts rings too and
  goes on through such changes. Both at once at one junction cost two samplers for at most 3 minutes. Keep timing
  adjusted counts queues, not passes: nothing to share.
- **Buckets and rates:** 30 s buckets (a ring of 40 slots = 20 min); the passes found at a sample go into the bucket of
  its game time. "Last 3 min": the buckets from 6 before the current one, a span of 180 .. 210 s, the rate exact over
  it; "all": the whole recording. Live rates use the time of the last sample.
- **End:** the button (saved when >= 30 game s), 20 game minutes (saved), the junction gone (every junction of a ring
  checked at each sample: `entityExists`; saved when >= 30 s), an error (logged, saved when >= 30 s). A checkpoint every
  5 game min saves the result so far (a quit or load keeps it; a load ends the recording: the GUI state is new).
- **Text:** while it records (selected): "Recording traffic: 7 of 20 min", then "Vehicles per minute: 33 (last 3 min),
  48 (all 7 min)" (a roundabout: "Vehicles entering per minute: ..."; one rate while the recording is 3.5 min or shorter;
  no rates before the first 30 s). Later: "Traffic recorded 12 min ago (20 min)" and the rates line. Below Re-time's
  lines at a lit junction.
- **The previous recording, to compare** (user 2026-10-16: "record traffic should always list the last recorded value,
  ideally in a muted text, so you can compare if the new recording is faster or slower"): where a junction has a saved
  result, a new recording there keeps it (read when it starts) and shows it under its live lines: "Previous recording:
  12 vehicles per minute (20 min, 2 h ago)" (a roundabout: "vehicles entering per minute"; the whole-recording rate).
  The new record keeps it as its previous (`trec` entries of 12 numbers, `Rec.prevOf` / `Rec.record(..., prev)`; a
  checkpoint sends the same previous, never the recording's own earlier checkpoint), so after the recording the status
  shows the new result and, below it, the one it replaced. One saved result only: shown as before. Old 9-number records
  read without a previous; a malformed previous is dropped, the record kept. A recording too short to save leaves the
  record as it was. The line is muted: the base `NeutralMedium` grey (gray50; the info text is `NeutralVeryLight`) set
  inline on its TextView (`meta.styleSheet`, `styleutil.makeStyle`, as the lane status badge colour), no stylesheet
  rule (css-rules 4 before and after, Smart Lanes alone); the base has no muted TextView class. `C.status().muted`
  lists the muted extra lines. Unverified in game that the inline colour wins over the disabled button's text rule
  (TESTING.md "TR" step 8). Results: "Traffic recording stopped" | "finished" | "too short to save (under 30 s)" |
  "stopped: the junction is gone".
- **Cost estimate per sample:** as Re-time's sample at the same junction minus the queue reads: in the user's busy run
  (~1425 candidates, ~315 near) ~3.4-3.9k engine calls, ~10-12 ms of os.clock per sample (an upper bound: os.clock reads
  3-6x the wall time on the Main Thread, docs/findings/gui.md), spread over ~10 frames at 1 ms; every 5 game s that is
  ~2-2.4 ms per game second (at 1x and 60 fps ~0.04 ms per frame on average; at 4x ~4x that). Measured in game
  (session `2026-10-16_1815`, three 20-min recordings): `ms_per_sample` 16-18 ms but only 126-405 `calls_per_sample`
  (the estimate's calls were high, its ms low), and 215 samples in 1200 s (an interval of ~5.6 s already). A roundabout reads the
  routed lists of its arms (4 arms: 4 list calls, 30-360 us each) and tracks drivers at all its junctions: about 1.5-2x a
  crossroads. Offline (test_tool "sampling cost"): 0.16 engine calls per far driver per sample. Measured in game by
  `ms_per_sample=` / `calls_per_sample=` of `TRAFFIC op=done`.
- **Tests:** test_record.lua (buckets, rates, texts, records and the cap, the previous result and old 9-number
  records, the event, save size), test_tool.lua "record traffic (tool)" (a junction with the live and the saved text
  through the game script, the button stops, one at a time, goes on with another selection and with the tool closed,
  the 20-minute end with checkpoints, too short, gone, a roundabout counting only entries, Re-time beside a recording,
  the cost, the previous recording during and after a recording and its muted index) and "status chip: the extra
  lines listed in muted" (the inline grey).

### Several recordings at once (2026-10-16, user: "update to allow multiple recordings"; implemented offline, not run in game yet: TESTING.md "TM")
- **Up to `Rec.MAX_RUNNING` = 20**, each up to 20 game minutes from its own start, each started and stopped with the
  button at its own junction / roundabout. The 21st start: the button grayed "20 recordings running, the most at once"
  (the same as the click's result; `TRAFFIC op=refuse reason=full running=20`). A running one's own junction always
  stops it.
- **One shared sampler run** (`sl_retimer.lua` `M.startShared` / `addTarget` / `removeTarget`, `C.recorder`): the union
  of every recording's candidate entities (each list call once), each driver placed and read once per sample however
  many recordings it passes; near = within any recording's radius (far: skipped until it could reach the nearest);
  `Retime.pathAtMulti` over the union of their junctions; a pass at a node counts for every recording holding it (a
  roundabout's own `countFn`: entries only). Each recording keeps its own start (`t0`, moved on by a gap), samples,
  buckets, checkpoints (`Rec.CHECKPOINT_S` from its own start), previous and saved record. The run starts with the first
  recording and ends with the last.
- **Cost bounded:** one `Rec.BUDGET_S` = 1 ms of clock per frame for all (not per recording), a sample every
  `Rec.EVERY_S` = 5 game s. With many busy junctions a sample needs more frames than 5 s allow; the next one then starts
  when it is done: every recording's interval stretches alike, the frame cost stays. Junction-gone checks: at most
  `Rec.EXIST_MAX` = 32 `entityExists` per sample over all (round robin; one recording: all its junctions each sample).
  Per frame the tool also walks the running list once (20 entries: elapsed and checkpoint, no engine call).
- **Do cars get missed when the interval stretches?** The 5 s interval holds the bound of the single recording: a car
  is seen ahead while it is within 200 m of the junction (and its path has the node within 4 edges), i.e. for 200 / v s:
  14 s at 50 km/h, 9 s at 80 km/h, 5 s at 144 km/h. A pass is lost only when the interval exceeds that for the car's
  speed (then the car may go from "far" to "past" between two samples). Keeping 5 s for 20 busy junctions would need up
  to 20x the frame time, so the frame budget wins (user rule: the same total per-frame budget) and the stretch is
  logged: `TRAFFIC op=done every_max_s= late=` (late: samples more than 10 s apart, the bound for ~72 km/h). Town
  traffic (<= 50 km/h) stays exact up to a 14 s interval.
- **Cost estimate for 20:** in game (session 2026-10-16_1815, three 20-minute recordings at busy town junctions)
  `ms_per_sample` was 16-18 ms (126-405 calls per sample, os.clock: an upper bound, 3-6x the wall time on the Main
  Thread). 20 such junctions without shared drivers: ~320-360 ms of reads per 5 game s pass. At 1x and 60 fps a 5 s
  interval has ~300 frames = 300 ms of budget: the interval stretches to ~5.5-6 s. At 4x (~75 frames per 5 s) ~22-24 s
  (late; fast arterials undercount, town streets mostly not). The frame cost stays at most 1 ms (+ one CHECK_EVERY batch)
  in every case; shared drivers (neighboring junctions) are read once and make it cheaper.
- **The status:** at a recording junction its own lines as before; anywhere else (another junction, a street, nothing
  selected) the line "Traffic recordings running: 3" (below the light timing lines with nothing selected).
- **Save safety:** running recordings live in the tool's GUI state only (`C.recs`), never in the save. A save keeps
  each one's last checkpoint (every 5 game min) or final result in `trec`; a load starts with none running (the GUI
  state is new), as before with one. Up to 20 running send at most 20 checkpoint events per 5 game min (each a
  `trec` change: one record).
- Tests: test_tool.lua "record traffic (tool): two at once ... a reload keeps the checkpoints, never a running
  recording", "at most RecS.MAX_RUNNING at once ..." (the cap lowered to 5 for the fixture's 9 junctions), "many at once
  stay within the one per-frame budget ..." (a ticking fake clock: per-frame time within the budget, samples over
  several frames, each driver once per sample, `every_max_s` / `late` logged), and the earlier tests (one recording,
  the 20-minute end with checkpoints, gone, a roundabout).

## No classic fallback: the game's phases where the axis plan can't be made (user decision 2026-10-16; implemented offline 2026-10-16, not run in game yet: TESTING.md "NC")
User: "is our newer plan better, or is game always better. if game is better we should remove". The axis plan beats the
game's phases (RESULTS.md: +23/+26 % cars/min on 2x2 / 3x3 lit X, 6 of 6 sets; run 2 +14-39 %). The classic patterns
(the default before rev 8) lost to the game in every set (−4.7 km/h, +23-25 pp standing) but are still the planner's
fallback where no axis plan can be made (`axis_extra`, an invalid plan, shapes other than x4 / t3; sl_phaseplan.lua
~1475-1491, "generic" too). Change: where the axis plan can't be made, keep the game's phases (Smart lights hidden /
"nothing to do" there, the Light phases = Smart Lanes setting leaves them alone, logged with a reason); drop the classic
patterns and the `sl_classic` zone (Stress Test twin) unless a test mode still needs them. Open: T-junctions (t3) have
no axis-vs-game bench run yet.

### Implemented (2026-10-16, offline; not run in game yet)
- **Planner** (sl_phaseplan.lua `PP.plan`): the axis plan for x4 / t3, the fan plan for `opts.fan`, nothing else.
  Where no axis plan can be made it returns nil and the reason; every caller keeps the game's phases:
  | reason | when |
  |---|---|
  | `no_axis_shape` | no x4 (4 arms in two pairs within `PP.AXIS_TOL` 45 deg of 180) and no t3 (3 arms with a main road: a straight pair, else a pair within 45 deg of 180): a crossroads skewed past 45 deg, a Y |
  | `axis_extra` | a lane finds no road phase |
  | `invalid_<why>` | the axis plan fails `PP.validatePlan` |
  | `too_many_phases` | more states than `PP.MAX_STATES` |
  Removed: the classic patterns (`axisCandidates` single / plain / protected / split / lead-lag, the t3 pattern), the
  generic colouring (`genericSeeds`), the candidate scoring (`PP.score`, `secPerLane`, `lostTime`), `splitApproach`,
  `opts.pattern`, `PP.patternName` "classic" / "generic". Kept (the axis plan or the fan plan use them): `realise`
  (whole lanes, bus lanes, step 3, step 4b curb merges, the crosswalk step and walk phase for fan plans), the all-red
  clearances (`clearances`, fan plans; `PP.vehClear`, the axis plan's clearance without crosswalks), the skip modes
  (`skip = "turns" | "none"` options, no caller passes them), timing, `PP.validatePlan`, `PP.planText`.
- **The fan plan stays**: zone mode `sl_fan` is still live (sl_zones.lua accepts it, the automatic pass and the tool
  write the full fan with its fan plan there; the Stress Test still accepts and reads it, its Lights showcase no longer
  builds it since 2026-10-13). Its `fanPattern` is the only non-axis plan.
- **Callers** (they already kept the game's phases on a failed plan; now they get one at more junctions): the lane
  write (`W.remapLights`: the game's phases re-pointed onto the new lanes with the free curb turn as set), the phases-only
  write (`W.planLights` -> 0, `plan_fail:<reason>`; the automatic pass then frees the curb turn as with Game default,
  `planSame` / `freeSame`), the re-checks (`planLights` again), Smart lights (`C.lightsOnly`: nothing sent, the result
  "Smart lights: <reason text>"). Re-time and Keep timing adjusted never plan phases (durations only: sl_retime.lua uses
  `PP.gameGreen` alone), nor do the free curb turn paths (sl_lights.lua). Log: `PHASES src=auto|tool|recheck node=
  phases=sl pattern=none plan_fail=no_axis_shape` (the existing `plan_fail=` field; SUMMARY `plan_fail=no_axis_shape:1`,
  WRITE `plan_fail=`); Smart lights: `PHASES src=tool action=lights_only node= phases=sl pattern=none plan_fail=<reason>`.
- **Smart lights** (sl_toolcore `C.buttons`, `lightsOffered`): shown only at a lit crossroads / T-junction (not a ring
  junction) whose axis plan can be made (`C.lightsStatus` ok; grayed "Phases already the Smart Lanes plan" until later 2026-10-16, now hidden, when the
  phases are that plan); elsewhere hidden (user 2026-10-16: "nothing to do"), Re-time and Keep timing adjusted stay in
  the light row. The detail line says why (`Pick.lightsText`): "Smart lights: not for this junction shape" (new string,
  13 languages; `plan_fail:no_axis_shape`, or `{ why = "shape" }` that `C.canInfo` sets at a lit junction that is no
  crossroads / T-junction: 5 arms, a slip node, a ring junction), else "Smart lights: no phase plan for these lanes".
  The grayed reasons "Only at a crossroads or T-junction" and "No phase plan for these lanes" are gone (strings removed);
  the button's tooltip now says "Shown at a crossroads or T-junction with traffic lights (other junctions keep the
  game's phases)" (13 languages).
- **Zone `sl_classic` removed** (sl_zones.lua `AB`, by_ab; sl_lanes.script.lua, sl_toolcore.lua, sl_write.lua). A
  payload with it is refused (`ab<i>`); an `sl_classic` zone saved earlier matches no mode and acts as `sl`. Stress
  Test: `LIGHTS_CLASSIC_AB`, `LIGHTS_PLANS_CLASSIC_*`, `lightsPlansSpec("classic")` / `buildLightPlans(seed, "classic")`
  (console only) and `sl_classic` in `SL_ZONE_AB` / `slZonesByAb` removed; the readers of older saves keep it
  (stress_flow `TWIN_ORDER` / letter `u`, the town word "Classic phases"; tools/flow_report.py reads old logs).
- **The user's junction, node 32350 (session `2026-10-17_0057_sqrl-sqsg`, user: "why did the button to set the smart
  lanes disappear on the node i pressed?")**: arms at 20.1 / 146.2 / 184.0 / 274.0 deg. A / C are 163.9 deg apart
  (16.1 off a road), B / D 127.8 deg (52.2 off, past `PP.AXIS_TOL` 45; the other pairings are worse: A / B 126,
  C / D 90, A / D 106, B / C 38): a crossroads skewed past 45 deg, so no axis plan, by the rule (not a bug). The game
  itself pairs only A / C there (8 phases: A+C, D alone, B alone; docs/findings/roads.md). Arm D's 2+2 lanes play no
  part in the shape test. The log shows the user pressed **Smart lanes** both times (`APPLY src=tool kind=slip` then
  `PHASES src=tool node=32350 phases=sl pattern=none plan_fail=no_axis_shape`, no `action=lights_only`: the lane
  write's phases step, Light phases = Smart Lanes). It wrote the lanes (15 -> 10 connections, the free curb turn on
  arm D) and kept the game's phases re-pointed, so the lights looked unchanged; then the lanes were smart
  (`PICK ... badge=smart`) and Smart lanes hid, as designed (Reset brought it back once, the second Smart lanes hid it
  again). Smart lights was hidden throughout (`C.lightsStatus` plans the same arms: `plan_fail:no_axis_shape`, so
  `lightsOffered` is false; status and click agree). No code change for B; test_tool.lua "Smart lights (tool): node
  32350 ..." pins it with the real angles (and D at 282 deg, 44 deg off: Smart lights offered), test_phaseplan.lua
  "no classic fallback" both angle sets. Whether the axis tolerance should grow past 45 deg stays open: the axis plan
  was benched on regular crossroads only, and the engine does not pair B / D either.
- **Tests**: test_phaseplan.lua rewritten without the classic patterns ("no classic fallback": skewed X within / past
  45 deg, a Y, 5 arms -> `no_axis_shape`, the fan plan still plans them; timing, validation, step 4b, whole lanes, bus
  lanes on the axis plan; fan plans' all-red and unplaceable crosswalk), test_script.lua "no classic fallback
  (automatic pass)" (a lit crossroads skewed past 45 deg: the game's six phases re-pointed, `pattern=none
  plan_fail=no_axis_shape`), test_tool.lua "Smart lights (tool): hidden where no axis plan can be made" (the shape and
  lanes reasons, a lit slip node, the Apply with the game's phases), test_zones.lua "sl_classic refused"; the Stress
  Test's test_showcase.lua (by_ab without sl_classic, every mode it sends accepted by Smart Lanes).

## Idle runtime and Automatic light timing Off (rev 9, user 2026-10-17; implemented offline, not run in game yet: TESTING.md "IO")
A player uninstalled after rev 8 ("a giant stutter fest ... one thing this game doesn't need is more background
scanning"), without having ticked the welcome's lights box and asking for a way to turn the background work off.
Under Junctions I choose with nothing enrolled no traffic was counted (a snapshot needs a member), but the runtime
still ran its per-frame bookkeeping and the game script copied its whole saved state every 5 GUI frames and every 10
engine updates. The user asked for: an Off value, the runtime doing no work until the player enables the feature on a
light (Junctions I choose was already the default and the welcome's lights box already unticked), and cheaper polls.
- **Off** (`sqrl_auto_lights` third value, appended so saved indices 1 / 2 keep their meaning; the panel's Automatic
  light timing gets it too, `amode = "off"`): nothing counted, decided or written; a snapshot or wanted write in
  progress is dropped; the zones, the all-lights listing and `op=all` enroll nothing. The list and the opt-outs are kept
  (`op=mode off` changes only `amode`), so Junctions I choose or All lights takes them up again; `pick` unenrolls only
  when the mode in force was All lights. The new-light look still runs (Smart lights plans are phases, not timing).
  Tool: status "Light timing: off", an enrolled junction "Keep timing adjusted: paused while Automatic light timing is
  Off" (the Yes / No toggle stays: a choice made while Off is kept).
- **Idle** (`sl_autoretime.lua` header "Idle", `R.idle`): Off, or Junctions I choose with no enrolled junction, no sl_auto
  zone and nothing in progress: a frame reads the mirror and the zones every `IDLE_FRAMES` (300) frames instead of
  30 / 120, skips the settings poll, and the background plugin skips the construction cursor read. `R.wake()` (the
  tool's `sendAuto`) keeps the busy cadence for `IDLE_FRAMES` frames so a Yes shows at once.
- **Game script polls** (`sl_lanes.script.lua`): the GUI poll copies the state (`state:get`) only when
  `Auto.readStamp` (state_native finds of seq, zseq, kseq, sseq, aseq on the GAME_SCRIPT component, as the runtime's
  mirror already reads it) moved; unreadable: every poll, as before. The engine's job sweep reads the state every
  100 updates instead of 10 (jobs live 300-400 updates).
- **Not changed**: the build-time automatic pass already runs in steps within an 8 ms frame budget since rev 4
  (PERF_REVIEW.md 2026-10-12).
- Tests: test_tool.lua "keep timing adjusted (idle)", "keep timing adjusted (Off)", "all lights (game script): op=mode
  off ..."; test_script.lua "GUI poll: ..."; test_allmode.lua / test_settings.lua for the third value.

## Nearby junctions stay as they are (rev 9, user decision 2026-10-17; implemented offline, not run in game yet: TESTING.md "NJ")
User report (in game 2026-10-17, session `2026-10-17_2159_sqrl-sqsg`): a road built in one place rewrote the lanes of an
existing lit crossroads nearby (`SUMMARY job=1 nodes=5 ... cross=1`, `APPLY kind=slip node=32350 shape=crossroads ...
before=15 after=10 lit=yes`). The player had not built at 32350: the new road joined an arm road partway along, the game
replaced that stretch (arm 85407 -> 105882), and the replacement's far end, 32350, was a seed (an end of an added
segment). The user: building a road in one section should not change a nearby junction, unless it is a roundabout
(rings stay planned whole).

The rule (sl_lanes.script.lua handleBuild `quietNodes`, slipStep, ringStep):
- A seed is **quiet** when it existed before the build (not in `addedNodes`), the build added as many arm segments as it
  removed there (`addedSegments` vs `removedSegments` end nodes), and each arm has the road it had: the same edge type,
  `typeIndex` and lanes (direction from the node and transport modes per lane, so a replacement drawn the other way
  matches). A segment that cannot be read counts as changed. New nodes, and junctions where an arm was added or removed
  or changed its road (an upgrade), are handled as before. A build that places or removes a street stop (the edge
  objects on its added segments differ in number from those on its removed ones) has no quiet node: the stop rebuilds
  its road piece and may open or close exit lanes at both ends ("Open exit lanes near stops and close junctions"; not
  in the user's decision, kept so that rule still reacts to stops). The job carries the quiet list (`jobs[i].quiet`); a job merged
  with another (enqueue) keeps a node quiet only when no build of the two changed it.
- **Off a ring**, a quiet junction's lanes are not written: where the rule would change them, `SKIP kind=cross|slip|drop
  node= reason=unchanged` (SUMMARY `skips=unchanged:n`), nothing written, lights and phases as they are. Where its lanes
  are already the rule's (status same: Smart Lanes' lanes the engine carried over), the same path as before: no lane
  write, its free curb turn or Smart Lanes phase plan sent again when the rebuild lost them. "No lights at roundabouts
  and ramps" switches no light off at a quiet slip node.
- **On a ring**, a quiet seed still finds its ring and the ring is planned whole (Rules.autoSeeds), so a ring junction
  reached only through a replaced segment gets the whole ring as before; the quiet junction counts as not touched: the
  hand-edit guard applies to it (a ring whose only seeds are quiet and that has a hand-edited junction is left alone
  as a whole, `SKIP ring= node= reason=hand_edit`, no split) and its light stays.
- **The Smart Lanes guard** (the user: a skipped junction that had Smart Lanes' lanes must not be left reset to the
  game's): the engine carries the old config over, re-pointed onto the replacement segment (docs/findings/roads.md "A
  replaced arm keeps the junction's lanes": T 5237 read `same` right after its arm was rebuilt, 2026-10-14), so
  skipping is enough and nothing is re-applied. Its light phases look made again by that rebuild (the curb turns freed
  before were locked back): the same path above frees them again where the lanes still match the rule; where the rule
  would now plan other lanes (e.g. the new road's junction lies within the open-exit distance), the junction keeps its
  old lanes and the phases the game made. In-game check: TESTING.md "NJ".
- Not changed: the existing-junctions pass (jobs "m<n>", no quiet nodes), the new-lights look (handleNewLights), Kept /
  Reset nodes, the hand-edit / hand-timed guards, zones.
- Tests: test_script.lua "nearby junctions: ..." (a road joined partway: the far crossroads alone, both drawing
  directions; a road joined onto the junction, an arm upgrade and a stop placed on an arm: handled; a merged job; Smart Lanes' lanes kept: no lane
  write, curb turns freed again; a ring reached through a replaced arm: whole, its light kept; the same with a hand edit:
  left alone).
