# Smart Lanes: designed traffic light phases (queued 2026-10-12)

User request 2026-10-12 (screenshot: game phase at a lit T, north straight + north left together): better default
light patterns, e.g. protected left-turn arrows and other common patterns, taking crosswalk time into account.

Status: steps 0-4 done offline 2026-10-12 (rev 4, released); step 0 ran in game (TESTING.md "LP"), step 4 waits for TESTING.md "LS".
Rev 8 (2026-10-14, offline): whole lanes in every step and in PP.validatePlan, bus lanes with their approach, the tool's
"Lights only" (PLAN.md "Rev 8"; TESTING.md "SH"; below "Whole lanes and bus lanes"). The main road factor rev 8 first
added is removed again (same section).
Rev 8 (later 2026-10-14, offline): the **axis plan** is the default for crossroads and T-junctions (below, "Axis plan
(default since rev 8)"); the patterns of "Phase plans: design" stayed as `opts.pattern = "classic"` (zone `sl_classic`)
until 2026-10-16.
2026-10-16 (user decision, offline): **no classic fallback** (PLAN.md "No classic fallback"): the classic patterns, the
generic colouring and zone `sl_classic` are removed; where no axis plan can be made the planner returns no plan with a
reason (`no_axis_shape`, `axis_extra`, `invalid_..`) and the junction keeps the game's phases. "Phase plans: design"
below is history apart from the pipeline steps the axis and fan plans share.
- Step 0: `W.probePhases` (sl_write.lua), called from the automatic pass and the tool's picks, debug setting only.
  Offline answers in findings.md "Traffic light phase records, units and defaults" (4 phase fields, seconds, no
  cycle / offset / yellow field, all-red = an ordinary all-locked phase, defaults made by the engine).
- Step 1: `sl_phases.lua` (P.build: rim-order model, see its header), tests/square_smart_lanes/test_phases.lua.
  Agrees with L.kerbConflict pair by pair on every sl_cross fixture (rule and game-default connections, both
  sides); stricter only for an in-only arm inside a curb corner. The game's modelled default (one phase per road,
  parallel crosswalks green) is conflict-free except the permissive movements: far turn vs the opposite straight
  (cross), far turn vs the opposite curb turn into the same road (merge / cross), turns vs the green parallel
  crosswalk (ped), and at a 3-lane T side road its own lanes 2..N all turning into every lane (X.defaultConns
  model). Never two straights, never straight vs crosswalk: the map is not too strict.
- Steps 2 and 3 done offline 2026-10-12 as pure logic: `sl_phaseplan.lua` (PP.plan, PP.validatePlan, PP.planText,
  PP.infoFromView), tests/square_smart_lanes/test_phaseplan.lua. Design below ("Phase plans: design").
- Step 4 done offline 2026-10-12 (user decision "let's measure first": default **Game default**, Smart Lanes
  phases only when chosen; the traffic log compares them). Setting `sqrl_light_phases` "Light phases" (Game
  default / Smart Lanes, 13 languages). Calibrated from the LP probe (findings.md "Default traffic light phases,
  measured in game"), see "Step 4: calibration and write path" below. In-game check: TESTING.md "LS".

## Constraint
TF3 has no permissive turn: a connection unlocked in a phase drives as if green and never yields (docs/findings.md
"A connection unlocked in a phase does not give way"). The classic patterns keep every phase conflict-free (protected
turns only). The axis plan (rev 8 default, below) deliberately accepts the conflicts within one road, as the game's own
default phases and a player's hand-made plan do; never between roads, never with a green crosswalk.

## Plan
0. **Probe** (Smart Lanes PROBE lines, gated by probeOn): dump default phases at a few lit T / X junctions:
   states, lockedLanes, per-state duration fields and units, trafficLightType, crosswalk records (segment mapping),
   whether the game inserts yellow / all-red itself, userModifiedTrafficLightStates. Results -> findings.md.
1. **Conflict map** (pure): per pair of connections cross / merge-same-exit-lane / crosswalk crossing; extends the
   "When safe" conflict model.
2. **Phase plans** (pure), by shape:
   - Crossroads with left-turn lanes: opposing lefts -> both straights + curb turns + parallel crosswalks -> same for
     the cross road (4 phases).
   - Crossroads without separate left lanes: split phasing per approach, or lead-lag (protected left + straight).
   - T: main straight both ways (+ side-road crosswalk) -> main left arrow + its straight -> side road.
   - Every connection and crosswalk green in >= 1 phase; non-conflicting movements added to every compatible phase.
3. **Timing**: green by demand (lane counts until the traffic log gives real numbers); pedestrian minimum =
   crossing length / ~1.2 m/s + clearance; keep cycles short (fewer phases).
4. **Setting** "Light phases: Game default / Smart Lanes" (13 languages); Reset restores game default; log
   `phases=<plan>`; compare with the traffic log (FLOW_PLAN.md) per setting.
5. Index safety as everywhere: lockedLanes within the final connections + crosswalks of the same proposal
   (VectorMap.h:11 crash), one proposal per node, Reset path, tests both traffic sides.

## Axis plan (default since rev 8; 2026-10-14, offline, not run in game yet: TESTING.md "AX")

Evidence: a player's report 2026-10-14 (not verified in game by us), a lit city crossroads of 1-car-lane roads with
curbside bus lanes and tram, comparing Smart Lanes' phases, the game's default and their own: "the default runs 100x
better; with your smart setting traffic backed up to the other side of town because the phases are too short". Our
x4 plan split the shared-lane crossroads into 4 approach phases (~16 s greens, an all-red after each); the game's
default and the player's plan give each ROAD both of its directions whole (left turns included, against the opposite
straight, which the game tolerates): 2 long greens per cycle. The player's phases (screenshots, ~70 s cycle; every
lane 1-2 destinations; car lanes never lead into bus lanes), **the reference**:

| # | phase | duration | skip | min |
|---|---|---|---|---|
| 1 | head start: one direction of the main road alone, all its movements | 12.6 s | yes | 1.5 s |
| 2 | main road, both directions whole, every movement, crosswalks red | 23.7 s | yes | 1.5 s |
| 3 | pedestrians only (every crosswalk green, every vehicle red) | 6 s | no | - |
| 4 | cross road, both directions whole, every movement, crosswalks red | 21.6 s | yes | 1.5 s |
| 5 | pedestrians only | 6 s | no | - |

No all-red phases: the pedestrian phases are the clearance between the roads.

What it replaces and why: the classic x4 patterns (split for shared lanes, protected / lead-lag) made 4 short phases
plus 4 all-reds (and a 15 + 3 s pedestrian phase) at the common 1- and 2-lane crossroads: each approach got ~16 s of
a 90 s cycle, so a road's direction was green ~18 % of the time instead of ~40 %. Protected turns cost more green
than the conflicts they avoid save. The classic patterns stayed reachable (`opts.pattern = "classic"`, zone
`sl_classic`) for A/B measuring until 2026-10-16; they lost to the game's phases in every set (RESULTS.md) and are gone.

The plan (sl_phaseplan.lua, header "Axis plan"; x4 and t3; other shapes no plan since 2026-10-16, the game's phases stay):
- **Roads**: x4 the two axes, the one with more demand first (lane counts without `laneDemand`: equal lanes, then
  the lower segment id); t3 the main road (the arm pair with straights between them), then the side road.
- **One phase per road**, every connection of both approaches (bus-lane, tram, U-turn connections included): each
  approach whole, the whole-lane invariant holds. Lanes of the other road join only conflict-free, or (a dedicated
  curb lane, step 4b) where they only merge.
- **Conflict acceptance, explicit and narrow** (like the fan mode's same-approach flag): `fits` accepts a conflict
  between two connections whose approaches both lie in the phase's road (its axis set: the two opposite approaches,
  and within one approach); the plan lists per state the road (`plan.axis[state] = { segA, segB }` or `{ seg }`);
  `PP.validatePlan(M, plan, n, nCross, { axis = true })` accepts exactly those, and only when the pair is one road
  (`PP.roadPair`: opposite arms within 180 +- 45 deg by `M.armAngle`, or a straight between them, the T's main
  road). Never a conflict with another road's connection, never with a crosswalk (`:ped`). Without the flag, or for
  a state the list does not name, the same plan fails `conflict:..`. sl_write planFor validates with the flag unless
  the plan is a fan one.
- **Pedestrian phase** after each road (tag `ped`): every crosswalk green, every vehicle red, `opts.pedPhase` = 6 s
  (the player's). Rev 8 v2 (user 2026-10-14): `canSkip = true` with `minDuration` = `opts.pedClearance` (3 s, 0.5 s
  steps, at most the phase), as every phase of the game's default skips: the junction is still cleared every cycle
  (the user's screenshots: cars stuck mid-junction "cycle out eventually, like with regular lights"), but an empty
  pedestrian phase ends early instead of holding both roads red for 6 s. The no-crosswalk all-red clearance the same
  (minDuration = min(3 s, its 2..4 s)). `PP.validatePlan` refuses a skippable phase with every vehicle red and less than
  `PP.MIN_CLEAR` = 1 s minDuration (`clear_min:<state>`); skip "all" needs no fixed phase. The game runs a 3 s walk + 9 s all-red (findings "Default traffic light
  phases, measured in game"); the classic patterns' walk floor was crossing length / 1.2 m/s + 3 s (15 + 3 s at a 2x2). Crosswalks
  are red in the road phases (the player's choice: turners do not yield to pedestrians, findings "A connection
  unlocked in a phase does not give way"). No other all-red phases (`allRed` applies to fan plans); a
  junction without crosswalks gets an all-red clearance (2..4 s, `PP.vehClear`) in place of each pedestrian phase.
- **Head start** (tag `head`, before its road's phase, skip yes, min 1.5 s): one approach alone, all its movements,
  only when measured demand says it clearly dominates its opposite: `laneDemand` ratio >= `opts.headStartRatio`
  (1.5; `false` = never). Lane counts never trigger it. Its weight is the excess (dominant - opposite) with a green
  base of 0 (4 s per unit, at least minGreen 6 s); the road's phase then weighs the opposite's demand. **No caller
  passes `laneDemand` yet**: Re-time changes lengths only (it cannot add a phase); a later step that feeds measured
  demand into the planner (RETIME_PLAN.md step B or the traffic log) turns it on.
- **Timing**: road weight = its larger approach's demand (a lane = 1, bus-only and tram-only lanes included),
  green = 15 s + 4 s x weight scaled into the 40..90 s cycle (the calibration below); road and head-start phases
  `canSkip = true`, `minDuration = 1.5`.
- **Green floor** (rev 8 v2, `opts.gameGreenFloor`, players: "shorter phases than default harm busy junctions"): a
  road phase is at least the game's default green for its lanes, `PP.gameGreen(lanes of its larger approach)`:
  1 -> 18.9 s, 2 -> 23.7 s, 3 -> 27.1 s, then +3.4 s per lane (whole seconds round up: 19 / 24 / 28 s). From the probe
  (session `2026-10-12_0753`): a 2x2 crossroads' greens are 23.70 s, a 3x3's 27.09 s (two approaches each); the
  18.86 / 21.55 s greens are the single-approach phases of a 2-lane / 3-lane T; no 1-lane default was measured, so
  1 lane takes the shortest seen. (The calibration note "the game's measured 18.9 / 21.6 / 23.7 / 27.1 s" for 1-4
  lanes read them as one lane-count series; they are not: corrected below and in docs/findings/roads.md.) The head
  start has no floor.
- **No fallback** (since 2026-10-16; before: the classic candidates, then generic): a lane that fits no road phase
  (`axis_extra`), an invalid plan (`invalid_<why>`) or another shape (`no_axis_shape`: a crossroads skewed past 45 deg,
  a Y without a main road, 5+ arms) is no plan: every caller keeps the game's phases and logs `PHASES ... pattern=none
  plan_fail=<reason>`; Smart lights is hidden there (PLAN.md "No classic fallback").
- **Free curb turn**: Light phases = Smart Lanes never applies the free curb turn on top (as before). Inside the plan,
  step 4b lets a dedicated curb lane (curb turns only; beside a bus lane only while that bus lane is green: the rev 8
  rules) also go in the other road's phase where it only merges: there it merges into that road's straight towards
  the same exit (the other road's far turns end in other arms), and it meets no pedestrians since crosswalks are red
  in every road phase. A curb turn on a shared lane goes only with its road. With Light phases = Game default the
  free curb turn works on the game's phases as before (sl_lights, unchanged).
- **Re-time** (sl_retime.lua) works on axis plans unchanged: pedestrian phases are `walk` (their duration and
  minDuration kept, counted whole in the lost time L), road and head-start phases `veh` (test_retime.lua "plan on a
  Smart Lanes axis plan"). Since rev 8 v2 it also picks the cycle (RETIME_PLAN.md).

Examples (calibrated defaults with the green floor, right-hand traffic, a crosswalk on every arm; test_phaseplan.lua
prints them; the pedestrian phases `6s/skip3`):
- The player's crossroads (1 car lane + curbside bus lane each way, tram on the main road): `x4_axis cycle=60`
  24 s main road / 6 s pedestrians / 24 s cross road / 6 s pedestrians (the player's 23.7 / 6 / 21.6 / 6 s = 57.3 s
  without their head start).
- 2x2 X: `x4_axis cycle=60` 24 / 6 / 24 / 6 s (classic: `x4_split cycle=90`, 4 x 16 s + 4 x 2 s all-red + 15 + 3 s).
- 3x3 X: 28 / 6 / 28 / 6 s = 68 s; 3x3 x 2x2 X: 28 / 6 / 24 / 6 s = 64 s.
- 2x2 T: `t3_axis cycle=60` main 24 s / 6 / side 24 s / 6; 1-lane T and X 19 / 6 / 19 / 6 = 50 s.
- A 2+1-lane road x a 1-lane street: 24 / 6 / 19 / 6 = 55 s; with measured demand 3 : 1 on the 1-lane direction:
  head start 8 s, road 24 s (the floor; its weight alone gives 19 s), pedestrians 6 s, street 19 s, pedestrians 6 s.

Zone `sl_classic` (2026-10-14 to 2026-10-16; sl_zones.lua): as `sl_phases` but the classic patterns; the Stress
Test's Light plans A/B compared game / sl_phases (axis) / sl_classic twins (RESULTS.md: the axis plan +23-26 %
cars/min, classic worse than the game in every set). Removed with the patterns.

Open (TESTING.md "AX", "NC"): queues and throughput at lit T-junctions under game default vs axis (no bench run yet); whether a
6 s pedestrian phase is enough for wide roads (pedestrians still on the crosswalk when the next road goes green);
whether the turners in a road phase really get through the opposite straight without jamming the box (the player says
yes); the head start once measured demand reaches the planner.

## Phase plans: design (steps 2-3, sl_phaseplan.lua; the classic patterns since rev 8, removed 2026-10-16: history)

Input: the conflict map M (P.build) and info = conns (the list M was built from), arms {seg, angle}, classes
(curb / straight / far / u_turn per connection; from the sl_cross view, else from the arm angles and the driving
side), road lanes or crossing length per arm, optional lane demand ("seg:lane" -> weight). Output: states
{locked (0-based), green, duration, minDuration, canSkip, tag, weight}, kind, why, cycle, warnings, score; or nil +
reason (caller keeps the game's phases). Every plan passes PP.validatePlan (indices in range and unique, every
connection and crosswalk green somewhere, no conflicting green pair, durations 1..60 whole s, minDuration 0..30 in
0.5 s steps and <= duration, >= 1 phase that never skips).

Patterns ("turn" = far or U-turn; an approach "shares" when one entry lane has a turn and a non-turn connection):
- **x4** (4 arms in two opposite pairs, 180 +- 45 deg), per axis: `single` (one approach: one phase), `plain` (no
  turns: one phase), `protected` (turns, no shared lane: opposing turns first, then straights + curb turns),
  `split` (a shared lane: one phase per approach), `leadlag` (exactly one approach shares: its approach -> both
  non-turn -> the other's turns; a candidate next to split). The axis with more entry lanes first. kind
  `x4_<mode>` or `x4_mixed` (plan.axes).
- **t3**: main road = the arm pair with straights between them: main non-turn (straights both ways + curb turns)
  -> per main approach with turns: its turns + its straight (lead) -> the side road.
- **generic** (other shapes, or a pattern that fails): approaches (split where their own movements conflict)
  coloured greedily in arm order.
- Then: seeds placed only where conflict-free (else the first phase they fit / a new phase); every connection added
  to every phase it fits (maximal: the free curb turn "When safe" falls out of it); crosswalks added to every phase
  they fit. Since rev 8 every step works on whole entry lanes (below, "Whole lanes and bus lanes"). A crosswalk that fits nowhere takes a phase from connections green elsewhere too, never leaving part of
  a lane green (a red movement at the head of a shared lane would block it): fewest straights, fewest connections,
  earliest phase. Else one pedestrian phase with every vehicle red (`unknownCrosswalk = "ped_phase"`; "refuse" =
  no plan). An unmapped crosswalk entity conflicts with every connection, so it always lands there.
  Last (step 4b, 2026-10-12): every curb turn also joins every phase where its only conflicts with green are merges
  (as "When safe" since merges are allowed; `opts.kerbMerge`, not in fan plans; PLAN.md "When safe allows merges"),
  since rev 8 only a lane of curb turns only, whole.
- Candidate choice (x4 axes split vs lead-lag): PP.score = greedy lane cover (a lane is served in a phase when all
  its connections are green there) x secPerLane, at least the phase floors, + lostTime (4 s) per phase. With lane
  counts as demand split always wins (one phase change less); lead-lag needs real demand (traffic log): with busy
  straights and light turns it wins (tested).

canSkip: a phase may skip when every non-turn entry green in it (straight, curb turn, crosswalk) is also green in a
phase that never skips: protected arrows, the T's lead phase, a side-road phase whose curb turn runs elsewhere.
minDuration = 5 s (or the pedestrian need, below), 0.5 s steps. Option `skip = "none"`.

Timing: weight = per approach the demand of its (lane, class) units first seeded in the phase (lane counts; a lane
with k classes counts 1/k each; a unit a crosswalk displaced is shared by its green phases), largest approach. Floors: minGreen 6 s; pedestrians: from the start of any phase
a crosswalk is green in to the end of that run of green phases, guaranteed time >= crossing length / 1.2 m/s + 3 s
(skippable phases count their minDuration for themselves, nothing as later phases). Crossing length = the crossed
road's width (info.crossLen; else driving lanes x 4.5 m (town lanes are 4 m, curb lanes 5 m); else 14 m; unmapped
crosswalk: widest arm). Durations max(floor, s x weight) with the sum = clamp(sum of max(floor, weight x 10 s),
40, 90) (over 90 only for floors: warning `cycle_over_max`), whole seconds.

All-red: none at first (findings: amber is the light model's change animation, all-red an ordinary locked
phase); since step 4 "auto" clearances after every phase (below, "Step 4: calibration"). The timing numbers in
this section and the examples below are the pre-calibration ones (the LEGACY options of test_phaseplan.lua).

Example plans (test_phaseplan.lua prints them; RHT, crosswalk on every arm unless noted):
- 2x2 X (Smart Lanes rule, far lane = straight + far): `x4_split`, 4 x 18 s approach phases (each approach's curb,
  straight and far + compatible curb turns of others) + 18 s pedestrian phase (every crosswalk conflicts with a turn
  of every approach phase and moving it would leave part of a lane green). With `pedYield`: 4 x 20 s, crosswalks
  beside their traffic.
- 3x3 X with dedicated far lanes (lanes R / S / L): `x4_protected`, 10 s arrows (skip >= 5 s) / 20 s straights +
  curb turns per axis, 60 s cycle without crosswalks. With crosswalks the parallel crosswalks take the straight
  phases (26 s for a 6-lane road), the curb turns move to the arrow phases (one arrow phase then never skips):
  15 / 26 / 15 (skip) / 26 s = 82 s.
- 3x3 X from sl_cross (far lane goes straight too): `x4_split`, ped floors 26 s x 4 = 104 s: `cycle_over_max`.
- 2x2 T: `t3`, main 20 s / lead 10 s / side 10 s (skip) / pedestrian 18 s = 58 s; with `pedYield` 20 / 6 / 20 s.

Open (LP probe and later):
- **Do turning vehicles wait for pedestrians on a green crosswalk?** The game's own default greens curb and far
  turns with the parallel crosswalk. If they wait, `pedYield = true` drops every pedestrian phase (2x2 X: 4 phases
  instead of 5; T: 3 instead of 4). Default false (no yielding at all is the verified vehicle behaviour).
- canSkip: which "lanes" count (the phase's green connections? pedestrians?); whether a skipped phase strands
  pedestrians. The planner keeps every crosswalk in a phase that never skips.
- The game's default durations (cycle length, min green) to calibrate secPerLane / cycle range; whether the engine
  clamps durations outside the sliders.
- Whether the engine clears the junction between phases (amber time) or `allRed` is needed against vehicles still
  in the junction.
- Crosswalk entity = edge id (`cw_is_edge`): if not, every crosswalk is unmapped -> one pedestrian phase per plan;
  step 4 should then refuse (`unknownCrosswalk = "refuse"`) rather than add Barnes-dance phases everywhere.
- Lane allocation vs phases: sl_cross lets the far lane of a 3+ lane approach also go straight at lit nodes, which
  makes every 3x3 X a split plan (4 approach phases, 104 s with crosswalks). Making the far lane far-only where the
  plan is protected would give 4 short phases with leading arrows; decide with the traffic log (FLOW_PLAN.md).
- Step 4: done (below).

## Step 4: calibration and write path (2026-10-12)

Calibration (PP.DEFAULTS; the pattern tests keep the pre-calibration options as LEGACY):
- **Greens**: target = 15 s + 4 s x weight (lanes): 19 / 23 / 27 s for 1 / 2 / 3 lanes. The game's measured greens
  are 23.7 s (2x2 X) and 27.1 s (3x3 X) for two-approach phases, 18.9 / 21.6 s for the single-approach phase of a 2- /
  3-lane T (corrected 2026-10-14: earlier read as one 1-4 lane series); the axis plan's green floor (above) keeps road
  phases at or above them. The demand weighting stays; one factor scales every green so the cycle (all-red
  included) lies in 40..90 s (the game's 71-78 s plus room for 4-phase plans). 4-phase split plans therefore get
  16 s greens at a 2x2 X (75 s cycle without pedestrians, 90 s with).
- **No main road factor** (rev 8 first added one, removed the same day): lane counts guess the main road wrong. A
  player's busiest road has fewer lanes on purpose (a deliberate bottleneck), so a factor from the arms' lane counts
  gave the quieter, wider road the longer greens. Measured traffic is the real answer: the tool's Re-time
  (RETIME_PLAN.md) sets the lengths from counted cars. Weights stay lane counts (a bus-only lane counts as a lane:
  the player's crossroads gets 18 s for the main road with its bus lanes vs 14 s for the 1-lane street at 90 s) or
  explicit `laneDemand`.
- **All-red clearance** (allRed "auto"): after every vehicle phase clamp(round(junction width / 8 m/s), 2, 4) s, the
  width = the widest arm's road (driving lanes x 4.5 m; 3 s unknown): 2 s at a 2x2, 3 s at a 3x3. After the
  pedestrian phase max(that, 3 s). Fully locked, `canSkip = false` (choice: a fully locked phase has no lanes to hold
  it, so with canSkip it could end at once and the clearance would be lost; the game marks its all-reds skippable,
  which TESTING.md LS 4 watches).
- **canSkip** (skip "all", the game's way): every other phase `canSkip = true`, `minDuration = 1.5` (the game's).
  No starvation rule: canSkip only ends a phase whose lanes are empty while traffic waits elsewhere, so a phase with
  demand runs; validatePlan accepts a plan without a fixed phase in this mode ("turns" / "none" keep the old rules).
- **Pedestrians**: concurrent with conflict-free parallel traffic where the map allows (realise step 4), else the
  pedestrian phase. The floor crossing length / 1.2 m/s + 3 s is split as walk green (length / 1.2, e.g. 15 s at a
  2x2) + the 3 s all-red after it (the game: 3 s + 9 s; a long walk green runs only when somebody waits, a long
  all-red every cycle). The crossing time goes into the green, never into minDuration (inferred: pedestrians on a
  crosswalk keep its "lane" busy, so the phase does not end under them; LS 4 checks it).

Write path (sl_write.lua, sl_lanes.script.lua, sl_toolcore.lua):
- Lane write with a lit case-X node (X.litOf true) and Smart Lanes: the item carries `lightPlan = {view, world}`;
  W.remapLights builds the plan from the FINAL connections and the config's crosswalks of the same proposal
  (W.planFor: infoFromView, P.build, PP.plan, PP.validatePlan, index range [0, #conns + #cws - 1] again), new
  `TrafficLightState.new()` per state with duration / minDuration / canSkip set, on a clone of the read config,
  read back (checkStates). The free curb turn is not applied on top. No plan or an invalid one: the free curb turn
  and the plain re-pointing as before, `plan_fail=<reason>` logged (PHASES line per node).
- Tool "Lights only" (rev 8, PLAN.md "Rev 8"): W.planLights for the junction's current connections (the player's
  own lanes included) whatever "Light phases" says, no lane write, same guards (phaseHold, standing light, a plan
  that differs from the phases); logs `PHASES src=tool action=lights_only` and `LIGHTS ... action=lights_only`.
- Lanes already right: W.planLights, a phases-only `createTrafficLightProposal` (clone, current preference), only
  with a standing light, only when the phases differ from the plan, never while a write or light proposal on the
  node is pending (automatic pass: busyNode / inflight, released on the callback or after INFLIGHT_TIMEOUT = 600
  frames without one, and on a send that throws; tool: phaseHold, bounded by CALLBACK_TIMEOUT). A failed plan falls back to W.kerbLights.
- Unknown light at the write (AUTO, no light yet): the 60 / 600-frame re-checks re-classify the node and write the
  plan once a light stands and the lanes are still ours (RECHECK kind=phases).
- Reset (tool, Smart Lanes mode): the lane write as before (game model, curb turns locked in the re-pointed phases),
  then after it answered W.defaultLights: `states = {}` with createTrafficLightProposal, exactly the Crossing window's
  "Reset to Default" (double_slip_switch.tl:604-612, verified in the file; that the engine then makes its default
  phases is inferred from the window, LS 6 checks it). Game default mode: Reset as before (LOCK in the lane write).
- Zones (2026-10-12, sl_zones.lua, FLOW.md "[SQRL] ZONES"): a node in an `sl_phases` zone (Stress Test Showcase
  twin c) takes the Smart Lanes write path above whatever the setting (SUMMARY `zone_phases=`); a node in a `game`
  zone is skipped by the automatic pass entirely. The tool is unchanged (APPLY lines say `zone=game`).
- Game default mode: no change to any proposal (test "byte-for-byte"); logs gain `phases=game` (SUMMARY, WRITE of
  slip / street / multi writes, LIGHTS free_turn) and the load line `MODE phases= free_turn=`.
- Open: whether the game re-makes phases after nearby builds or road upgrades (LS 5); whether a phases-only
  proposal sets `userModifiedTrafficLightStates` (logged as user_modified=); whether a phase ends early under
  pedestrians; whether the all-red phases need canSkip = false.

## Whole lanes and bus lanes (rev 8, 2026-10-14; offline, not verified in game: TESTING.md "SH" 3, 7-9)

Evidence: a player's report 2026-10-14 (a lit city crossroads, 1-car-lane roads, curbside bus lanes and a tram,
Light phases = Smart Lanes), not verified in game by us:
- "Every phase needs to allow all connected lanes of a direction to go at the same time, or the one car in the line
  that wants to turn left while everybody else goes straight blocks the flow and prevents the phase skip."
- "A curbside bus lane: if the bus lane has red but the traffic lane to its left has green for a right turn, the cars
  don't drive. The collision check of the (stopped) player vehicles stretches ahead to let them cut into traffic, and
  that blocks the right turn in front of them. So a bus lane needs green at the same time as the traffic next to it
  (same approach), ideally for all its directions."
- "It's not easy to figure out the main road": their busiest road has fewer lanes on purpose (the main road factor
  is removed, "Step 4: calibration").

**Whole lanes** (a hard invariant of sl_phaseplan): an entry lane is all green or all red in every phase.
- Lane key: the connection's entry `segment0` + `lane0` (P.build now records `M.lane0` beside `M.seg0`), road and
  tram connections alike: a car lane with tram tracks is one lane (its tram connection green exactly with its road
  twin, as before); a tram-only track and a bus-only lane each have their own lane index, so each is a lane of its own.
- Every step adds whole lanes (`joinLane`, all-or-nothing): the pattern seeds (a seed movement pulls in its whole
  lane; a seed lane that conflicts with what its phase has green already is placed later, whole, in the first phase it
  fits, else in a new phase: the old per-movement rule. Dropping such a candidate instead was tried: it turned the
  game's 3-lane T, whose side-road lanes cross each other, into a generic plan), the lanes no seed placed, the maximal
  phases, the pedestrian phase's fill, step 4b (only lanes of curb turns only). The crosswalk step already took
  phases from whole lanes only.
- Patterns seed whole lanes by design, so no seed lane fights its own phase: the T's main phase seeds only the main
  approaches' non-turn lanes (a shared straight + left lane runs in its lead phase only); lead-lag's axis phase seeds
  the lead's non-turn lanes (its shared lane runs in the lead phase); the generic colouring works on lanes.
- `PP.validatePlan` refuses a part-green lane: `part_lane:<state>:<seg>:<lane>` (after the state's conflict check).
  Fan plans pass it too (their seeds are whole approaches; other lanes join only whole, as everywhere).
- Effect: the 2x2 T's main phase greens one main approach's straight lane only, the other's straight + far lane waits
  for its lead phase (calibrated T 2x2: 85 s cycle, was 83 s); 1- and 2-lane crossroads stay split (one approach per
  phase). Lead-lag still wins on demand.

**Bus lanes go with their approach** (step 2b): a bus-only entry lane (`info.bus` = the view's `v.bus`, Ring.busLanes;
its connections are kept as read: Rules.mergeTram) is green, whole, in every phase where a car connection of its
approach (same `segment0`) is green, unless one of its connections conflicts with another approach's green movement or
a green crosswalk: then all of it stays red in that phase (e.g. a bus left turn while the opposite straight is green).
- Conflicts between a bus-lane connection and another connection of its own approach (the bus lane's straight crosses
  the car lane's right turn beside it, or merges with it) are accepted: `fits` / `fitsMerging` while planning,
  `PP.validatePlan` with `plan.bus` (the bus-lane connections, 0-based; a plan read back without it is checked
  strictly). The player's point: the two go side by side.
- Bus lanes take no part in the pattern choice (an approach's shared / turn classes, seeds); a bus lane no car phase
  takes goes into the first phase it fits whole, else a new one, so every bus connection is still green somewhere.
- Step 3 tries an approach's bus lanes before its car lanes, and a car lane carrying a curb turn joins a phase beside
  a bus lane only where a bus lane of its approach is green (also step 4b). Seeds are not held back: in a protected
  axis whose bus lane also turns left, the curb car lane is green in the straight phase while the bus lane is red
  (TESTING.md SH 8 watches it; classic patterns only since the axis plan: there the bus lane is green with its whole road).
- Free curb turn (Game default phases, sl_lights `L.kerbPhases` When safe / Always): a dedicated curb turn of an
  approach with a bus-only lane is freed only in phases where a connection out of that bus lane is green (the same
  rule; LOCK / Reset unchanged).
- Demand: a bus lane counts as a lane in the weights (as before rev 8).
- Tests: test_phaseplan.lua "whole lanes", "bus lanes", "validatePlan whole lanes", the defect test's `part_lane`;
  test_lights.lua "kerbPhases beside a bus lane".

## Fan mode (2026-10-12, zone `sl_fan`; a measuring mode, never a default)

User request 2026-10-12 (screenshot of a hand-made lit crossroads): "every lane connects to every other lane, and then
the light schedule does the appropriate". Built so it can be **measured** against `game`, `sl` and `sl_phases` twins,
not as a new default.

Lanes (sl_cross `X.fanConns`): at a case-X node (crossroads, T) every entry lane of an approach (`ap.m`) goes to
every exit lane (`ex.o`) of every exit of that approach (`ap.allExits`: the game model's exits, so also turns a slip
lane serves and shallow moves; turns sharper than 135 deg and ramp to ramp stay out as X.classify leaves them).
- Decision: **all lane x lane pairs**, not a lane-ordered fan (the screenshot shows each entry lane fanning to all
  exits). 2x2 X = 48 connections (game 24, Smart Lanes 16), 3x3 X = 108, 3x3 x 2x2 X = 74, 2x2 T = 24.
- Road lanes only (`Ring.lanesAt`: no sidewalk, no tram-only track, bus-lane roads are skipped by X.classify);
  tram connections stay as the engine made them (Rules.mergeTram); never a U-turn; indices are the view's own.
- The fan's lanes of one approach cross and merge inside the junction **by design**: the conflict map (sl_phases)
  shows them as `cross` / `merge` pairs within one approach. Only a plan that keeps a whole approach in one phase
  makes that safe, so the fan is only ever written together with its plan.

Plan (sl_phaseplan `opts.fan`, kinds `x4_fan` / `t3_fan` / `fan`):
- Seeds: one phase per approach (all its connections), approaches in arm order (counter-clockwise).
- Then the usual pipeline: maximal phases (another approach's lane joins a phase, whole, when it conflicts with nothing
  green there: since rev 8 only whole lanes, so rarely any, as another approach's fan lane also goes to exits the
  active fan uses; before, a lone turn into the active approach's own arm could join), crosswalks (every crosswalk conflicts with a full fan, so they get the pedestrian phase), all-red after
  every phase, calibrated timing, skip "all".
- Conflicts between two connections of the **same approach** (`M.seg0`, new in P.build) are accepted in fan plans
  only: `fits(..., fanSeg)` while planning, `PP.validatePlan(M, plan, n, nCross, { fan = true })` when checking. The
  flag is explicit: the same plan without it fails `conflict:..`. A conflict between approaches, or with a
  crosswalk, is never accepted. No generic fallback.
- Examples (calibrated defaults, right-hand traffic; test_fan.lua prints them):
  - 2x2 X: `x4_fan cycle=90`: 4 x (16 s approach + 2 s all-red), walk 15 s + 3 s.
  - 3x3 X: `x4_fan cycle=90`: 4 x (13 s + 3 s), walk 23 s + 3 s (the 27 m crossing floor, 25.5 s, squeezes the
    approach greens; the targets would be 27 s each).
  - 3x3 x 2x2 X: 14 s (main) / 12 s (side) approaches, 3 s all-reds, walk 23 s + 3 s.
  - 2x2 T: `t3_fan cycle=90`: 3 x (22 s + 2 s), walk 15 s + 3 s.
  - Compare the same 2x2 X: Smart Lanes lanes `x4_split` (16 connections) and game lanes (24) give the same timing:
    split phasing is what the 2x2's shared lanes need anyway; the fan differs only in the lanes (any entry lane
    to any exit lane).

Write path (one proposal, the crash rules of step 4):
- Automatic pass: a node in an `sl_fan` zone plans with `Slip.plan(world, n, cur, { fan = true })`. Lit (X.litOf
  true): the fan + `lightPlan = { view, world, fan = true }` in the slip proposal; W.planFor plans and validates
  with the fan flag, indices checked against the final list + crosswalks, `TrafficLightState.new()` per state.
  `APPLY ... lit=yes mode=fan`, `PHASES ... plan=x4_fan ...`, SUMMARY `zone_fan=<nodes>`.
- **No plan, no fan**: W.remapLights raises `fan_<reason>` (or `fan_no_phases` with no phases to replace), so
  buildEntry refuses the node (`SKIP ... reason=lights:fan_<reason>`): fan lanes are never re-pointed onto the game's
  phases (the game's main-road phase would run two opposing fans at once).
- Decision for unlit / unknown nodes in the zone: the rule's lanes (as an `sl_phases` zone), `APPLY ... fan=unlit` /
  `fan=lit_unknown`; no fan without a light. Unknown at the read: the re-checks (60 / 600 frames) write the fan and
  its plan in one proposal once a light stands and the lanes are still the rule's (`APPLY src=recheck ... mode=fan`,
  `PHASES src=recheck ... plan=x4_fan`, RECHECK kind=phases sent=1). The Lights showcase builds lit junctions, so
  this is the fallback.
- Lanes already the fan: W.planLights with the fan flag (phases-only, as step 4).
- Not audited (sl_audit): the fan's crossings are by design, they would drown the AUDIT_SUMMARY.
- Tool: Apply inside an `sl_fan` zone does the same (lit: fan + plan in one proposal); the badge counts the fan as
  "Smart lanes" there (no new UI string), "Custom" elsewhere. Reset: the game model and default phases as anywhere.
- Other junction kinds in the zone (rings, slip nodes, lane drops): as `sl`.
- Open (to measure, TESTING.md FN): throughput and queue lengths of fan twins vs game / sl / sl_phases; whether the
  game's vehicles use the inner lanes for far turns (lane choice is the pathfinder's); whether merges of two entry
  lanes into one exit lane stall inside the junction.

## Lock mode (2026-10-12, zone `sl_lock`; a measuring mode, never a default)

User request 2026-10-12: measure the free curb turn on its own. The `sl` twin runs the global settings (the user has
"Free curb turn" = Always), so `sl` vs `game` mixes the lane layout and the freed curb turn. An `sl_lock` twin is
`sl` with the curb turn never freed: `sl_lock` vs `game` = the lane layout alone, `sl` vs `sl_lock` = the free curb
turn alone (valid while Light phases = Game default; the `MODE` line tells).

- Zone mode `sl_lock` (sl_zones.lua `M.AB`, `AB_SET`); `by_ab` gains `,sl_lock:<n>` after `sl_fan` only when n > 0
  (`game:a,sl:b,sl_phases:c[,sl_fan:d][,sl_lock:e]`), so older lines stay the same.
- Automatic pass (sl_lanes.script.lua `slipPlan`): a crossroads / T-junction in the zone gets the Smart Lanes rule's
  lanes as in an `sl` zone, `phase = { mode = Lights.LOCK, kerb }` in its lane write whatever "Free curb turn" says,
  and no Smart Lanes plan whatever "Light phases" says (the game's phases, re-pointed). Lights.LOCK is the tool's
  Reset path (W.remapLights): curb turns freed earlier are locked back with their approach before the re-pointing,
  then locked in the new phases (red where every other road connection of the approach is red, the game's default),
  indices range-checked by `checkStates` as every write. So a junction freed by an earlier write ends locked.
- Lanes already right: `freeSame` with LOCK = a phases-only `W.kerbLights(.., LOCK)` (`LIGHTS src=auto
  to=lock_turn lock_turn=<n> ... lock_phases=<n>`), sent only when a curb turn is green somewhere.
- No re-check after an sl_lock write (unknown light at the read: the game's later phases lock the curb turn
  anyway); a node busy at its "same" read gets a LOCK re-check entry (`recheckFree`: `W.kerbLights(.., LOCK)`).
- Log lines: the node's `APPLY` and `AUDIT` lines end in `zone=sl_lock free_turn=off`; `SUMMARY ... zone_lock=<nodes>
  lock_turn=<curb connections locked back> lock_phases=<(connection, phase) locks> free_turn=..` (free_turn= and
  free_phases= never count sl_lock nodes; `zone_lock` and its two fields only when the job had such a node).
- Tool: Apply inside an `sl_lock` zone locks the curb turns too (`phaseFor` LOCK; `WRITE ... lock_turn=..
  phases=game`, `APPLY src=tool ... zone=sl_lock free_turn=off`) and plans no phases there (`phasesAt` = game).
- `sl_fan` stays a valid mode (the Lights showcase no longer gives it a twin).
- Not covered: a node that carries a Smart Lanes plan from an earlier write (Light phases = Smart Lanes, or an
  sl_phases zone before) keeps that plan's phases in an sl_lock zone, curb turns locked in them; the game's default
  phases come back only with the tool's Reset outside the zone.
- Tests: test_zones.lua (validate, by_ab), test_script.lua "zones: sl_lock zone: ..." (5), test_tool.lua "zones
  (tool): Apply in an sl_lock zone ...". In-game check: TESTING.md "FL".
