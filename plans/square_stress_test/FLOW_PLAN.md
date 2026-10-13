# Traffic flow A/B: Smart Lanes on/off toggle + Stress Test traffic log (plan 2026-10-12)

User request 2026-10-12: see in the logs whether Smart Lanes makes traffic more efficient, on ONE map, with a
toggle that turns Smart Lanes off on all roads and back on (instead of building two maps).

Status 2026-10-12 (later): steps 4-5 built offline as the twins revision needs them (below, "Sampler
requirements"): stress/stress_flow.tl (zones, lookup, aggregation, lines) + gui/stress_flow_log.tl (sampler,
Traffic tab "Traffic log"), keys in FLOW.md v2, tests test_flow.lua + tests/tools SamplerEndToEndTest (the sampler's
own lines through flow_report.py); Smart Lanes' zones payload takes optional id / pair labels (twin ids survive a
reload). Not run in game yet: Stress Test TESTING.md 6R. Deviations from the step text: interval in game seconds
(v=2); zone membership by getPosition within r (no node/edge sets, no stress_zones.tl: the Showcase's zone list and
Smart Lanes' saved zones are the sources); Junction / Crossing test placements are not zones yet; no SQPERF (sweep
cost in FLOW_ALL / FLOW_SUMMARY).

Earlier status: step 0 Stress Test side done 2026-10-12 (log contract FLOW.md, Probe tab 11a-11h, TESTING.md 6M; not run in
game yet); the Smart Lanes channel probes of step 0 are deferred (FLOW.md). Line numbers are approximate (other agents were editing).

## What the code does today
- Reset per kind (square_smart_lanes sl_toolcore.lua): rings = engine-default model (`Rules.planRing(..,"engine")`);
  case X = `Cross.defaultConns` + tram merge; slip (A/B) and drop (D) = `C.snapshots` only, taken at the tool's
  first Apply, tool Lua state only (gone after reload; the automatic pass takes none) -> `RESET mode=unavailable`.
- No record of which nodes Smart Lanes wrote (game-script state is `{seq, jobs}`).
- Automatic pass: game script guiUpdate (Main Thread); tool: construction-menu Lua state (different).
  `doUpdate` subscribes only when active and not hasEventSubscriptions(): new events dropped on old saves.
- Channels: tool -> gs `api.gui.fireGuiScriptEvent` (api/gui.d.tl:57) -> guiHandleEvent (needs
  guiHandleEventScript + subscribe); GUI -> saved state `api.cmd.makeScriptingSendEventCmd` (api/cmd.d.tl:788)
  -> engine handleEvent -> state:set; re-subscribe once per load (square_problem_radar radar.script.tl:1346-1380).
- Stress Test `rt.tick` runs from react.onStep (Main Thread); engine reads must stay there (never onStepTimer).
  Placements are session-only; no game script, no SQPERF yet.

## API
| Need | Call | Citation |
|---|---|---|
| Car speed / standing | MOVE_PATH `.dyn.speed`, `.dyn.timeStanding`, `.dyn.pathPos{edgeIndex(0-based),pos,pos01}`, `.path.edges{{EdgeId,bool}}`, `.blocked`, `.state` | api/engine.d.tl:673-709; api/type.d.tl:2269-2295, :1164-1172 |
| Driver | SIM_PERSON lastMoveMode DRIVE + MOVE_PATH, no SIM_PERSON_AT_VEHICLE | stress_traffic.tl:371-382, stress_probes.tl:735-740 |
| Edge -> node | step[1].entity -> BASE_EDGE node0/node1 | stress_traffic.tl:429-449 |
| Cars per edge/node | simPersonSystem.getSimPersonsMovingForTransportNetwork(tn) (untested on streets) | api/engine/system.d.tl:157 |
| Waiting at light | VehicleOrder.waitingForTrafficLight (no ComponentType: probably unreachable) | engine.d.tl:1565-1574 |
| Town speed | api.engine.util.town.computeTownsTrafficSpeedMap(coef) | api/engine/util.d.tl:670 |
| Bus round trip | TRANSPORT_VEHICLE sectionTimes, lineStopDepartures, lastLineStopDeparture; util.line.getMaxFrequency; getLineVehicles | engine.d.tl:1483-1487; util.d.tl:206 |
| (not a time) | getVehiclesWithRoundTripCount = cargo round-trip counts | system.d.tl:217 |
| Zones | octree.findEntitiesInCircle, streetSystem.getNodeStreetSegments / getNode2StreetEdgeMap | util.d.tl:329; system.d.tl:302,312 |
| Guard | api.engine.entityExists | engine.d.tl:1723 |

## Steps (one subagent each, each followed by a review agent)
0. **Probe + log contract.** FLOW.md with exact line formats. Stress Test Probe tab "11a-11h Flow": MOVE_PATH read
   cost/units; path-edge entity inside a junction; getSimPersonsMovingForTransportNetwork on segments/nodes + cost;
   VehicleOrder reachable?, blocked/state; computeTownsTrafficSpeedMap from onStep + cost; sectionTimes /
   lineStopDepartures units; PLAYER_OWNED + CONSTRUCTION survival of placements; getPosition cost. Smart Lanes PROBE
   lines for the channels (fireGuiScriptEvent return across states; makeScriptingSendEventCmd on an old save after
   re-subscribe; fireReactEvent gs -> tool). Results -> docs/findings.md.
1. **Smart Lanes registry + mode + automatic-pass gate.** New game script sl_reg (own saved state
   `{v=1, mode, modeSeq, nodes={id={pre=connsText, on=connsText}}}`), events SmartLanes.setMode / SmartLanes.reg,
   re-subscribe every load, GUI mirror, one event per job, cap 5000, prune gone nodes; `pre` only for A/B/D;
   `Rules.parseConnsText`; while off the automatic pass plans nothing but registers nodes.
2. **Toggle job (sl_toggle.lua).** Scope registry + optional scan of PLAYER_OWNED nodes; rings batched whole; <= 40
   nodes / 6 ms per frame; fresh world per batch; snapFits; only W.sendConfigs (remapLights); lights after the
   batch callback. Off: ring model / X defaultConns+tram / A,B,D `pre` (missing/stale -> skipped, counted); lights
   AUTO where we had removed them. On: restore `on` if it fits else re-plan. Refused batch -> one node per frame.
   Logs `[SQRL] TOGGLE state=off|on phase=start|end|load nodes= written= same= skipped= kinds= skips= ms= gt=`.
3. **Smart Lanes UI.** Two buttons "All junctions: On" / "All junctions: Off" in the tool toolbar, status chip
   progress, Apply/Reset greyed while toggling; 13 languages; TESTING "AA"; changelog under Rev 4.
4. **Stress Test zones + pure flow logic.** stress_zones.tl (placements registered after the measured build;
   reload fallback: CONSTRUCTION entities if they survive, else node clusters); stress_flow.tl (aggregation,
   standing < 0.5 m/s, queue rule, formatting); test_flow.lua.
5. **Sampler + Traffic tab "Traffic log"** (On/Off, 10/30/60 s): own tick hook; <= 2 ms / 200 queries / 100 MOVE_PATH
   reads per frame, <= 3000 reads per sweep; warns with Keep traffic cleared on; towns every >= 60 s; buses by
   "SQST Bus N" lines. Lines FLOW_START / FLOW_ZONE / FLOW / FLOW_ALL / FLOW_TOWNS / FLOW_BUS / FLOW_SUMMARY.
   SQPERF via `make sqperf-sync`.
6. **tools/flow_report.py + `make flow`.** Split by latest TOGGLE phase=end/load; drop toggling and warm-up
   (default 180 s game); blocks Off#1/On#1..; pooled + paired (each On block vs neighbouring Off blocks); recommend
   ABAB; zones where On is worse. tests/tools/test_flow_report.py.
7. **Docs + in-game run.** findings, Stress Test TESTING 6R (6M = the Flow probes), Smart Lanes TESTING AA, changelogs, PERF_REVIEW.

## Risks
- Stale light phases (VectorMap.h:11): every write via remapLights; repeated toggles may wear phases down (probe
  whether AUTO regenerates them). Stale segment ids: snapFits at write time; stale snapshot = skip.
- Never remove a config without adding one; never touch a node without BASE_NODE_CONFIG.
- Concurrent writers (tool, automatic pass, toggle, Stress Test links): pending-lights proposal refuses later street
  proposals on that node; refuse a toggle during a tool job and vice versa; don't toggle during Stress Test builds.
- Fairness: X / ring models may differ from the true engine default; A/B/D defaults only from `pre` snapshots
  (older junctions are skipped: the report prints skipped= and reasons). Lights change with the lanes: the comparison
  is "Smart Lanes vs game default" as a whole.
- Native crash on dead entities in network queries: entityExists first. MOVE_PATH copies the whole path: caps.

## Open questions (in-game probe)
1. Car inside a junction: node as path-edge entity? getSimPersonsMovingForTransportNetwork on segments/nodes, cost.
2. MOVE_PATH cost, dyn.speed units, timeStanding meaning, blocked/state.
3. VehicleOrder reachable?
4. computeTownsTrafficSpeedMap from GUI onStep, cost.
5. sectionTimes / lineStopDepartures units vs gameTime.
6. Placements stay CONSTRUCTION entities? PLAYER_OWNED on script/construction edges?
7. fireGuiScriptEvent return across Lua states; makeScriptingSendEventCmd on an old save; shared gs GUI Lua state.
8. Does re-setting light preference AUTO regenerate default phases?
9. Engine default at fresh slip / drop nodes (CONN dump with Apply automatically Off) -> a model to replace snapshots.

## Revision 2026-10-12: side-by-side twins instead of toggling (user request)
The Showcase builds every group as twins with identical params: `ab=game` (Smart Lanes leaves it alone), `ab=sl`
(Smart Lanes lanes), and for lit plain intersections `ab=sl_phases` (Smart Lanes lanes + light phases). All variants
run at the same time, so time trends (town growth, time of day) cancel; no toggling or reload needed.
Consequences for the steps:
- Step 1 becomes "zone modes": a channel Stress Test -> Smart Lanes (makeScriptingSendEventCmd into Smart Lanes'
  saved state, re-subscribed every load) carrying the twin zones `{x, y, r, ab}`; Smart Lanes' automatic pass and the
  phase writer look up a node's zone: `game` = skip entirely, `sl` = lanes (light phases per setting), `sl_phases` =
  lanes + Smart Lanes phases regardless of the global setting. Sent BEFORE the Showcase builds anything.
  Done offline 2026-10-12: Smart Lanes sl_zones.lua + sl_lanes.script.lua (event, validation, saved state,
  per-load re-subscribe, auto-pass gate, sl_phases forcing, tool APPLY zone=game), Stress Test gui/stress_slzones.tl
  (send before the towns, ack wait before the first junction, clear on Remove all roads / Remove towns grid+all).
  Lines: FLOW.md "[SQRL] ZONES"; design and race bound: SHOWCASE.md "Twin modes in Smart Lanes"; in-game checks:
  Stress Test TESTING.md 6O, Smart Lanes TESTING.md "ZN".
- Step 2 (global On/Off toggle) is optional and deferred.
- Step 6: `make flow` compares twins pairwise (same pair id) and pooled per kind/type; no blocks, warm-up only at
  the start.

## Sampler requirements from the probes and the make flow review (2026-10-12)
Probe answers (session 2026-10-12_0905 in .cache/logs): MOVE_PATH read ~1 us/car, getPosition ~1 us/car (0 failures
in ~600), SIM_PERSON list of 43k in ~1.2 ms; dyn.speed in m/s, timeStanding in s; 64% of 200 drivers standing on the
congested Showcase map; getSimPersonsMovingForTransportNetwork returns persons ROUTED through an entity (300-700 per
edge/node), not cars on it -> demand, not congestion; lane speedLimit read failed (not needed); probe 11b has a bug
(stress_probes_flow.tl:399 "table index is nil"), not needed: attribute cars to zones by getPosition within zone r.
The sampler must write (so make flow needs no position matching):
1. FLOW_ZONE for a twin: `twin=g3a pair=g3 ab=sl|game|sl_phases sc_run=<showcase zones sent run=>`; non-twin zones
   `twin=-` or no keys.
2. FLOW lines: the same twin=/pair=/ab= keys (self-describing).
3. FLOW_BUS: `pair= ab=` (or twin=) of the twin the line serves.
4. FLOW_START: `gt_per_s=` (gt units per game second) and `v=`; gt monotonic within a load.
5. One FLOW line per zone per sample, including cars=0.
6. After a reload, write the twin ids as logged by the Showcase run they belong to (zones can be rebuilt from Smart
   Lanes' saved zones or the Stress Test's own saved state).
Add these keys to FLOW.md's FLOW_ZONE / FLOW / FLOW_BUS / FLOW_START tables when the sampler is built.

## v3 (2026-10-12, seed 530609 evidence): every driver, measured approaches

The 3000-driver cap read ~5 % of 55k drivers (`capped=1` every sweep, zones 0-35 cars). v3 reads every driver within
the 2 ms frame budget, lowers a per-sweep target only after a skipped sample (`FLOW_TARGET`), and measures each zone
along its arms out to r + 200 m with per-arm queues (`q_arm`). Contract: FLOW.md (v=3); reasons: SHOWCASE.md "Town
entries must not be the bottleneck".
