# Smart Lanes: designed traffic light phases (queued 2026-10-12)

User request 2026-10-12 (screenshot: game phase at a lit T, north straight + north left together): better default
light patterns, e.g. protected left-turn arrows and other common patterns, taking crosswalk time into account.

Status: steps 0-4 done offline 2026-10-12 (rev 4, unreleased); step 0 ran in game (TESTING.md "LP"), step 4 waits for TESTING.md "LS".
- Step 0: `W.probePhases` (sl_write.lua), called from the automatic pass and the tool's picks, debug setting only.
  Offline answers in findings.md "Traffic light phase records, units and defaults" (4 phase fields, seconds, no
  cycle / offset / yellow field, all-red = an ordinary all-locked phase, defaults made by the engine).
- Step 1: `sl_phases.lua` (P.build: rim-order model, see its header), tests/square_smart_lanes/test_phases.lua.
  Agrees with L.kerbConflict pair by pair on every sl_cross fixture (rule and game-default connections, both
  sides); stricter only for an in-only arm inside a kerb corner. The game's modelled default (one phase per road,
  parallel crosswalks green) is conflict-free except the permissive movements: far turn vs the opposite straight
  (cross), far turn vs the opposite kerb turn into the same road (merge / cross), turns vs the green parallel
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
"A connection unlocked in a phase does not give way"). Every phase must be conflict-free; protected turns only.

## Plan
0. **Probe** (Smart Lanes PROBE lines, gated by probeOn): dump default phases at a few lit T / X junctions:
   states, lockedLanes, per-state duration fields and units, trafficLightType, crosswalk records (segment mapping),
   whether the game inserts yellow / all-red itself, userModifiedTrafficLightStates. Results -> findings.md.
1. **Conflict map** (pure): per pair of connections cross / merge-same-exit-lane / crosswalk crossing; extends the
   "When safe" conflict model.
2. **Phase plans** (pure), by shape:
   - Crossroads with left-turn lanes: opposing lefts -> both straights + kerb turns + parallel crosswalks -> same for
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

## Phase plans: design (steps 2-3, sl_phaseplan.lua)

Input: the conflict map M (P.build) and info = conns (the list M was built from), arms {seg, angle}, classes
(kerb / straight / far / u_turn per connection; from the sl_cross view, else from the arm angles and the driving
side), road lanes or crossing length per arm, optional lane demand ("seg:lane" -> weight). Output: states
{locked (0-based), green, duration, minDuration, canSkip, tag, weight}, kind, why, cycle, warnings, score; or nil +
reason (caller keeps the game's phases). Every plan passes PP.validatePlan (indices in range and unique, every
connection and crosswalk green somewhere, no conflicting green pair, durations 1..60 whole s, minDuration 0..30 in
0.5 s steps and <= duration, >= 1 phase that never skips).

Patterns ("turn" = far or U-turn; an approach "shares" when one entry lane has a turn and a non-turn connection):
- **x4** (4 arms in two opposite pairs, 180 +- 45 deg), per axis: `single` (one approach: one phase), `plain` (no
  turns: one phase), `protected` (turns, no shared lane: opposing turns first, then straights + kerb turns),
  `split` (a shared lane: one phase per approach), `leadlag` (exactly one approach shares: its approach -> both
  non-turn -> the other's turns; a candidate next to split). The axis with more entry lanes first. kind
  `x4_<mode>` or `x4_mixed` (plan.axes).
- **t3**: main road = the arm pair with straights between them: main non-turn (straights both ways + kerb turns)
  -> per main approach with turns: its turns + its straight (lead) -> the side road.
- **generic** (other shapes, or a pattern that fails): approaches (split where their own movements conflict)
  coloured greedily in arm order.
- Then: seeds placed only where conflict-free (else the first phase they fit / a new phase); every connection added
  to every phase it fits (maximal: the free kerb turn "When safe" falls out of it); crosswalks added to every phase
  they fit. A crosswalk that fits nowhere takes a phase from connections green elsewhere too, never leaving part of
  a lane green (a red movement at the head of a shared lane would block it): fewest straights, fewest connections,
  earliest phase. Else one pedestrian phase with every vehicle red (`unknownCrosswalk = "ped_phase"`; "refuse" =
  no plan). An unmapped crosswalk entity conflicts with every connection, so it always lands there.
  Last (step 4b, 2026-10-12): every kerb turn also joins every phase where its only conflicts with green are merges
  (as "When safe" since merges are allowed; `opts.kerbMerge`, not in fan plans; PLAN.md "When safe allows merges").
- Candidate choice (x4 axes split vs lead-lag): PP.score = greedy lane cover (a lane is served in a phase when all
  its connections are green there) x secPerLane, at least the phase floors, + lostTime (4 s) per phase. With lane
  counts as demand split always wins (one phase change less); lead-lag needs real demand (traffic log): with busy
  straights and light turns it wins (tested).

canSkip: a phase may skip when every non-turn entry green in it (straight, kerb turn, crosswalk) is also green in a
phase that never skips: protected arrows, the T's lead phase, a side-road phase whose kerb turn runs elsewhere.
minDuration = 5 s (or the pedestrian need, below), 0.5 s steps. Option `skip = "none"`.

Timing: weight = per approach the demand of its (lane, class) units first seeded in the phase (lane counts; a lane
with k classes counts 1/k each; a unit a crosswalk displaced is shared by its green phases), largest approach. Floors: minGreen 6 s; pedestrians: from the start of any phase
a crosswalk is green in to the end of that run of green phases, guaranteed time >= crossing length / 1.2 m/s + 3 s
(skippable phases count their minDuration for themselves, nothing as later phases). Crossing length = the crossed
road's width (info.crossLen; else driving lanes x 4.5 m (town lanes are 4 m, kerb lanes 5 m); else 14 m; unmapped
crosswalk: widest arm). Durations max(floor, s x weight) with the sum = clamp(sum of max(floor, weight x 10 s),
40, 90) (over 90 only for floors: warning `cycle_over_max`), whole seconds.

All-red: none at first (findings: amber is the light model's change animation, all-red an ordinary locked
phase); since step 4 "auto" clearances after every phase (below, "Step 4: calibration"). The timing numbers in
this section and the examples below are the pre-calibration ones (the LEGACY options of test_phaseplan.lua).

Example plans (test_phaseplan.lua prints them; RHT, crosswalk on every arm unless noted):
- 2x2 X (Smart Lanes rule, far lane = straight + far): `x4_split`, 4 x 18 s approach phases (each approach's kerb,
  straight and far + compatible kerb turns of others) + 18 s pedestrian phase (every crosswalk conflicts with a turn
  of every approach phase and moving it would leave part of a lane green). With `pedYield`: 4 x 20 s, crosswalks
  beside their traffic.
- 3x3 X with dedicated far lanes (lanes R / S / L): `x4_protected`, 10 s arrows (skip >= 5 s) / 20 s straights +
  kerb turns per axis, 60 s cycle without crosswalks. With crosswalks the parallel crosswalks take the straight
  phases (26 s for a 6-lane road), the kerb turns move to the arrow phases (one arrow phase then never skips):
  15 / 26 / 15 (skip) / 26 s = 82 s.
- 3x3 X from sl_cross (far lane goes straight too): `x4_split`, ped floors 26 s x 4 = 104 s: `cycle_over_max`.
- 2x2 T: `t3`, main 20 s / lead 10 s / side 10 s (skip) / pedestrian 18 s = 58 s; with `pedYield` 20 / 6 / 20 s.

Open (LP probe and later):
- **Do turning vehicles wait for pedestrians on a green crosswalk?** The game's own default greens kerb and far
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
- **Greens**: target = 15 s + 4 s x weight (lanes): 19 / 23 / 27 s for 1 / 2 / 3 lanes, the game's measured
  18.9 / 21.6 / 23.7 / 27.1 s. The demand weighting stays; one factor scales every green so the cycle (all-red
  included) lies in 40..90 s (the game's 71-78 s plus room for 4-phase plans). 4-phase split plans therefore get
  16 s greens at a 2x2 X (75 s cycle without pedestrians, 90 s with).
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
  read back (checkStates). The free kerb turn is not applied on top. No plan or an invalid one: the free kerb turn
  and the plain re-pointing as before, `plan_fail=<reason>` logged (PHASES line per node).
- Lanes already right: W.planLights, a phases-only `createTrafficLightProposal` (clone, current preference), only
  with a standing light, only when the phases differ from the plan, never while a write or light proposal on the
  node is pending (automatic pass: busyNode / inflight, released on the callback or after INFLIGHT_TIMEOUT = 600
  frames without one, and on a send that throws; tool: phaseHold, bounded by CALLBACK_TIMEOUT). A failed plan falls back to W.kerbLights.
- Unknown light at the write (AUTO, no light yet): the 60 / 600-frame re-checks re-classify the node and write the
  plan once a light stands and the lanes are still ours (RECHECK kind=phases).
- Reset (tool, Smart Lanes mode): the lane write as before (game model, kerb turns locked in the re-pointed phases),
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
- Then the usual pipeline: maximal phases (another approach's movement joins a phase when it conflicts with nothing
  green there: in practice only turns into the active approach's own arm, as the active fan uses every other exit
  lane), crosswalks (every crosswalk conflicts with a full fan, so they get the pedestrian phase), all-red after
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

User request 2026-10-12: measure the free kerb turn on its own. The `sl` twin runs the global settings (the user has
"Free kerb turn" = Always), so `sl` vs `game` mixes the lane layout and the freed kerb turn. An `sl_lock` twin is
`sl` with the kerb turn never freed: `sl_lock` vs `game` = the lane layout alone, `sl` vs `sl_lock` = the free kerb
turn alone (valid while Light phases = Game default; the `MODE` line tells).

- Zone mode `sl_lock` (sl_zones.lua `M.AB`, `AB_SET`); `by_ab` gains `,sl_lock:<n>` after `sl_fan` only when n > 0
  (`game:a,sl:b,sl_phases:c[,sl_fan:d][,sl_lock:e]`), so older lines stay the same.
- Automatic pass (sl_lanes.script.lua `slipPlan`): a crossroads / T-junction in the zone gets the Smart Lanes rule's
  lanes as in an `sl` zone, `phase = { mode = Lights.LOCK, kerb }` in its lane write whatever "Free kerb turn" says,
  and no Smart Lanes plan whatever "Light phases" says (the game's phases, re-pointed). Lights.LOCK is the tool's
  Reset path (W.remapLights): kerb turns freed earlier are locked back with their approach before the re-pointing,
  then locked in the new phases (red where every other road connection of the approach is red, the game's default),
  indices range-checked by `checkStates` as every write. So a junction freed by an earlier write ends locked.
- Lanes already right: `freeSame` with LOCK = a phases-only `W.kerbLights(.., LOCK)` (`LIGHTS src=auto
  to=lock_turn lock_turn=<n> ... lock_phases=<n>`), sent only when a kerb turn is green somewhere.
- No re-check after an sl_lock write (unknown light at the read: the game's later phases lock the kerb turn
  anyway); a node busy at its "same" read gets a LOCK re-check entry (`recheckFree`: `W.kerbLights(.., LOCK)`).
- Log lines: the node's `APPLY` and `AUDIT` lines end in `zone=sl_lock free_turn=off`; `SUMMARY ... zone_lock=<nodes>
  lock_turn=<kerb connections locked back> lock_phases=<(connection, phase) locks> free_turn=..` (free_turn= and
  free_phases= never count sl_lock nodes; `zone_lock` and its two fields only when the job had such a node).
- Tool: Apply inside an `sl_lock` zone locks the kerb turns too (`phaseFor` LOCK; `WRITE ... lock_turn=..
  phases=game`, `APPLY src=tool ... zone=sl_lock free_turn=off`) and plans no phases there (`phasesAt` = game).
- `sl_fan` stays a valid mode (the Lights showcase no longer gives it a twin).
- Not covered: a node that carries a Smart Lanes plan from an earlier write (Light phases = Smart Lanes, or an
  sl_phases zone before) keeps that plan's phases in an sl_lock zone, kerb turns locked in them; the game's default
  phases come back only with the tool's Reset outside the zone.
- Tests: test_zones.lua (validate, by_ab), test_script.lua "zones: sl_lock zone: ..." (5), test_tool.lua "zones
  (tool): Apply in an sl_lock zone ...". In-game check: TESTING.md "FL".
