Status: current (2026-10-14). Step A implemented offline (rev 8, unreleased); step A v2 (the cycle from the
measurement, the background run, the last result in the status, cheaper sampling) implemented offline after the
user's first in-game run; neither run in game in this form yet (TESTING.md "RT"). Step B ("Keep timing adjusted")
implemented offline the same day (rev 8); run in game in the Light plans A/B run 2 (2026-10-15, RESULTS.md); cycle rule
v3 and damping built offline after it (2026-10-15, below); its measuring redesigned the same day as occasional queue
snapshots ("Step B v4", user decisions 2026-10-15; the shared sampler, settle delay and sampler cost v3 moved to
HISTORY.md), run in game at scale in the city runs 1-2 (RESULTS.md "City lights at scale"); after run 2 the early
wake's minimum queue and the wall-clock budgets (2026-10-15, below), not run in game yet (TESTING.md "KA v4" 13-14).

# Re-time: light phase lengths from measured traffic

Player feedback (2026-10-14): the phases don't reflect how many cars wait in each direction; the main flow gets too
little green. Two steps, agreed with the user:
- **Step A** (built): a "Re-time" button in the Smart Lanes tool for one selected lit junction: measure, then write
  new phase durations only.
- **Step B** (built, below): an optional per-junction "Keep timing adjusted" that re-times the junction now and then,
  without the tool open. Since step B v4 it measures with occasional queue snapshots, not Re-time's 3-minute windows.

## Step A summary (details: PLAN.md "Re-time: phase lengths from measured traffic", log format: PLAN.md "Logging")
- Code: `sl_retime.lua` (pure: path state, phase kinds, movements per phase, `R.plan` timing; `test_retime.lua`),
  `sl_retimer.lua` (measuring runtime: candidates, per-frame budget, re-route checks, light reads), `sl_toolcore.lua`
  (`C.retime` button, `C.retimeStep` per frame, `C.retimeClose`; guards, write, probe timers), `sl_write.lua`
  (`W.retimeLights`: durations only, phases signature re-checked), `sl_tool.script.lua` (the button, second row with
  Lights only). Tool tests: `test_tool.lua` "re-time (tool): ..." (a fake traffic simulator: drivers with paths through
  node 500, routed lists, game clock).
- Measure: every 3 game s for 180 game s, drivers routed through the node and its segments (plus last sample's
  ahead set), position within 200 m, path read 8 elements each way; passes per movement (ahead, then behind) and
  queued cars per movement (ahead, within 150 m, standing >= 5 s). 1.5 ms per frame.
- Plan: only veh phases change; all-red and walk phases keep their seconds; the cycle stayed (clamped 40..90 s; v2: chosen from the measurement, below);
  greens weighted 0.75 by the critical approach's demand per entry lane, 0.25 by the current split; floors (6 s,
  pedestrians); hysteresis max(3 s, 15 %); too small a sample keeps the phases.
- Write: one phases-only `createTrafficLightProposal` (clone, new `TrafficLightState`s with the read `lockedLanes` /
  `canSkip`), preference as read; never while a tool proposal is pending; the phases' signature re-checked.

## Step A v2 (user's run and players' feedback, 2026-10-14)
Evidence: the user's run at node 498446 (a 1-lane X, axis plan 19/6/19/6): `q_arm=498198:28.9,498258:28.6,
498390:23.4,5903:21.7`, `op=plan result=fits total=169 queued=102.6 load=1:89.1,3:91.1 old=19/6/19/6 new=19/6/19/6
cycle=50>50`, `op=measured cand_mean=1425 near_mean=314.6 reads=104429 frames=6993 busy_ms=7229.1`, and the run ended
`reason=tool_closed` when the menu closed. Players: shorter phases than the default harm busy junctions.

### The cycle (sl_retime.lua R.cycleFor, pure, test_retime.lua)
Webster's optimum cycle C = (1.5 L + 5) / (1 - Y), clamped to cycleMin..cycleMax = 40..120 s:
- q per veh phase = its load (the critical approach's demand per entry lane over the window; demand = passes + 0.5 x
  mean queue x window / cycle, as step A) per hour.
- s, the saturation flow (cars per entry lane per hour of green): estimated where a phase's critical approach queued
  at every sample on average (>= queueSat = 4 cars per lane): that green ran full, so its served passes per lane over
  its green seconds in the window (duration / cycle x window) are what a green clears; the mean of such estimates,
  clamped to 1200..3600; else satFlow = 1800 (the textbook value; an option).
- Y = sum q / s; L = every non-veh phase's duration (all-reds and pedestrian phases counted whole: a skippable one may
  end earlier, so L is an upper bound) + startLost 2 s per veh phase.
- Y >= yMax 0.9 (saturated, where C runs away) or a standing queue -> cycleMax. Logged `y= lost= sat= sat_src=
  cycle_reason=webster|min|max|saturated|queues|floors`.
- Then the greens split as in step A (load share 0.75 + current share 0.25, floors, pedestrians), each at most 60 s
  (the Crossing window's slider; a capped phase leaves its share to the others); hysteresis unchanged (max(3 s,
  15 %)).
- The user's junction (reconstructed from its log: straights only, passes 37 / 37 / 49 / 46 with those queues, which
  gives back load 89.0 / 91.1): Y = 1.59 with s = 2263 (est), L = 16 s -> saturated: cycle 50 -> 120 s, greens 19 / 19
  -> 54 / 54 s, pedestrian phases 6 s kept. **Since v3** (below) it is balanced (share 0.51): cycle 50 -> 75 s, greens
  31 / 32 s.
- "Never shorter than the game" applies to a fresh axis plan (PHASES_PLAN.md "Green floor"); Re-time may shorten a
  cycle where Webster says the traffic is light (40 s at least), which is what a quiet junction wants.

### Background run, up to 5 at once
- Selecting something else or closing the tool no longer cancels; the Re-time button at the measured junction does,
  a lane / phase change or the light gone stop it, a load ends it (the GUI state is new). Up to 5 runs at once since
  rev 9 (PLAN.md "Several Re-time runs at once"; before: one at a time, another lit junction's Re-time grayed).
- The run lives in the tool's controller (sl_toolcore, kept in the shared module `sl_toolstate.lua` across tool opens).
  `C.step` steps it while the tool is open; an invisible `::ModEntryPointExtension` plugin (`sl_bg.script.lua`,
  `sl_bg.res.lua`, the pattern of Passenger Destinations' PaxDestEntry) calls `C.bgStep` every frame, which counts the
  frame and steps it only while the tool's own step does not run. The write at the end has the same guards (the
  phases' signature, nothing of the tool pending); `op=bg` logs the first background step of a run.
- Unverified: that the plugin and the construction tool's recipe share a Lua state (both live under GameUIRoot; the
  game script's guiUpdate is another state, docs/findings/towns.md). If they don't, nothing steps the run while the
  tool is closed; the retimer then moves its window on by the gap at the next step (`gaps=`, `gap_s=`), so the run
  still measures 180 s of traffic once the tool is open again.

### The last result in the status
Since step B v4 the saved "last measured" record both modes share (below, "Records and status"): "Last measured 4 min
ago (manual): cycle 50 -> 75 s". (Before: `C.rtLast[node]`, GUI memory only, lost on reload, with "Measured 4 min ago:
18 / 7 cars/min per road".) While it measures: "Re-time: measuring traffic (87 of 180 s)".

### Cheaper sampling (sl_retimer.lua)
A candidate not ahead at the last sample is placed first (one `vehicle.getPosition`); beyond 200 m it is skipped and
not read again until it could have come within 200 m at 40 m/s (`farUntil`, at most 20000 entries); only near ones get
the driving / path reads (SIM_PERSON, MOVE_PATH, two at-vehicle checks, path elements). The user's run: ~1425
candidates per sample, ~315 near -> before ~8.9k engine calls per sample (5 per candidate + ~1.7k path reads), after
~3.4-3.9k (near ones as before, far ones at most one call, mostly skipped: 0.10 calls per far driver per sample in
test_tool.lua "measuring cost"). The log's `calls=`, `calls_per_sample=`, `far_skipped=` measure it in game.

## Open in-game questions (answered by the step A probe, TESTING.md RT)
1. **Does the node id survive a phases-only write?** `op=probe at=cb|f30 exists= config=`. Earlier evidence: a street
   proposal touching a node right after `createTrafficLightProposal` with preference NO failed with "invalid entity"
   (docs/findings/roads.md, "A street proposal touching a node whose traffic light change is still pending is refused"):
   either the node is re-created by a light proposal, or only its pending state blocks. If ids change, step B keys
   junctions by position.
2. **Does the config read back with our durations and the same lockedLanes?** `same_durations`, `same_locked`. If
   not, the engine clamps or re-makes phases and step B must re-read before deciding anything.
3. **Does the running phase restart at phase 0?** `state`, `time`, `state_times` before vs after. A restart costs up to
   one cycle of disorder per write; step B then writes at most every few minutes and only on a clear gain.
4. **Do drivers re-route because of a write?** `op=reroute` s5 / s30 against the base5 / base30 baseline. Re-routing
   after a write would make frequent writes move traffic around (and could feed back into the measurement).
5. **Does a script write set `userModifiedTrafficLightStates`?** `user_modified` before / after. If it does, step B
   can't use the flag to tell the player's edits from its own.
   **Answered 2026-10-15 from the logs: yes** (false before our first write, true after; docs/findings/roads.md
   "Phases-only writes set userModifiedTrafficLightStates"). Adopt already works from the durations, not the flag;
   "Automatic light timing" (sl_allmode.lua handTimed) needs more than the flag to tell a hand edit.
6. Cost and coverage: `src=routed` works at junction nodes, `cand_max`, `busy_ms`, `frames`, passes plausible.

## Step B: "Keep timing adjusted" per junction (built offline 2026-10-14, rev 8; not run in game yet: TESTING.md "KA")
User decisions (2026-10-14): per-junction opt-in, a checkbox in the toolbar, stored in the save keyed by position, one
shared sampler for every enrolled junction, gradual cycle steps, a bulk switch for the Stress Test. The A/B evidence
before it: the axis plan beat the game by ~25 % throughput on 2- and 3-lane crossroads in 6/6 sets (`make flow
ARGS='--last'`); Re-time had not written in game yet (the user's one run: `fits`).

### Files
- `sl_auto.lua` (pure + `readSaved` / `readLast`): the saved list, the last-measured records, the `SmartLanes.auto`
  event (validate / apply / applyLast / match / payloads), the decision interval rule (`nextEvery`). Tests: test_auto.lua.
- `sl_autoretime.lua` (GUI runtime): mirror, zones, "enroll all", refreshes, queue snapshots, decisions, the write
  scheduler, records. Tests: test_tool.lua "keep timing adjusted (runtime|bulk|cost, v4): ...".
- `sl_retime.lua`: `R.planQueue` (the plan from averaged queues), `R.timingOf` / `R.arrivalOf`, the corridors
  (`R.onCorridor`, `R.queueIndex`, `R.queueHits`) and `R.plan`'s `maxCycleStep` option (test_retime.lua).
- `sl_lanes.script.lua`: `handleAuto` (the event stored in the game-script state; subscription `SmartLanes.auto`);
  zone mode `sl_auto` planned as `sl_phases` (`sl_zones.lua`).
- `sl_bg.script.lua`: makes the runtime (`g.auto`) on its first frame and steps it every frame (SQPERF section `auto`,
  ctx `bg`), tells it when the player builds (below).
- `sl_toolcore.lua` / `sl_tool.script.lua`: the Yes / No toggle (`C.setAuto`, `C.autoChecked`, `autoTwin`,
  `syncAutoToggles`), the status
  lines (`C.autoLine`, `C.lastLine`), the manual run's records (`sendRecord`), `C.autoBusy`.

### The toggle (UI)
2026-10-15 (user): the CheckBox below was replaced by the base Yes / No toggle as twin params, so the state is right
from the first frame (the CheckBox showed unchecked at an enrolled junction until its first click). Now:
- **Twin params** `sqrl_tool_auto_on` (default Yes) and `sqrl_tool_auto_off` (default No): a two-value `Button`
  param each (`script_param_util.tl:396-450` draws a ToggleButtonGroup with `selected` from the stored value, as the
  street builder's "Underground"), label "Keep timing adjusted" shown, values Yes / No (1 / 2), same group, row and
  tooltip. `autoTwin`: the on twin shows (`checkEnabledFn`) at an enrolled junction, the off twin at one that is not,
  the other "Hidden"; both hidden where the row is (unlit, nothing selected). Before any click each shows its
  default: the truth by construction. A click: `C.setAuto(value == 1)` (the side in force changes nothing); its
  `onChangeFn` keeps the params api, and from then on `syncAutoToggles` writes both stored values from
  `C.autoChecked()` every step, so a twin clicked earlier never shows a stale side. Hidden params' values leave the
  current values: the tool's action never reads these keys. Unverified in game: TESTING.md KA v4 steps 1-2.
- Superseded (kept for the record): a base `CheckBox` param ("Keep timing adjusted", values No / Yes = 1 / 2,
  `hideLabel` so the CheckBox carries its name) in a **third row of its own** (group `sqrl_tool_auto`), shown exactly when the light row is (a single selected
  junction with a standing light and phases, or the one the manual Re-time measures), enabled always (the cap is
  answered by the click). Not in the light row: a group is one horizontal BoxLayout (construction.tl:2050-2072), and
  "Nur Ampel | Neu takten" plus a checkbox labeled "Takt laufend anpassen" / "Подбирать время автоматически" (~150-220
  px) does not fit the 314 px bar; its own group is a new row with the base separator above it, as between the others.
  CSS rules 4 before and after (no style of its own).
- **The box shows the selected junction's state, not a menu mode.** The base CheckBox draws
  `getStoredValues(category)[key]`, re-read by ConstructionParam every step (construction.tl:1044-1051, 1081-1084).
  The params api (`getStoredValues`, `getCategory`: construction.tl:1945-1990) reaches the mod as `onChangeFn`'s second
  argument (1885); the tool keeps it (`g.paramsApi`) and its `checkEnabledFn` writes the stored value from
  `C.autoChecked()` every step (`syncAutoBox`). Until the first click in a game session (a fresh menu) the box shows its
  default, unchecked, even at an enrolled junction (the status line says "Timing kept adjusted ..." there).
- **It unchecks reliably:** a click's new value is the player's intent (`C.setAuto(value == 2)`): checked enrolls,
  unchecked unenrolls, whatever the box showed before. A stale box is corrected by the click itself (enroll an
  enrolled junction or unenroll one that is not: no event, the box then shows the truth). The rev 8 "Lights only"
  checkbox was a menu mode whose stored value stuck across selections and hidden rows; this one has no mode.
- Clicked: `SmartLanes.auto add|remove src=tool`, the mirror changed at once, result "Timing kept adjusted at this
  junction" / "Timing no longer adjusted at this junction"; at the cap "Keep timing adjusted: at most 1000 junctions".
- Re-time at an enrolled junction (v4): the manual 3-minute measurement, as anywhere (a deliberate player action); the
  automatic writes there wait meanwhile (`C.autoBusy`) and no snapshot starts while it measures. (Before v4 the click
  sent `op=now` instead: one sampler at a time.)
- Status: "Step B v4", "Records and status".

### Storage and save safety
- Game-script state (`sl_lanes.script.lua` `handleAuto`, the engine thread): `auto = { {n, x, y} }` (node id last
  seen, position rounded to 0.1 m; v4 dropped the bookkeeping fields t, e, c of earlier rev 8 builds, cleaned on read),
  `aseq` (+1 per change), `aall = { seq, run }`, `areq = { seq, nodes }`, `arun`; and `rlast` / `lseq`, the last-measured
  records ("Step B v4"). Each written from its first use only: a save that never used them gets none of these keys.
- **Keyed by position**: an entry matches a node by id or within 2 m (`Auto.match`, a 4 m grid). At every refresh the
  runtime resolves the spot: the stored id if that node still stands within 2 m, else the nearest node within 2 m
  (octree `BASE_NODE`), re-attached (`AUTORETIME op=reattach old= new=`, the saved id updated with an `update` event).
  No node, or no light / phases there: pruned (`op=prune reason=gone|no_light|no_phases|no_config`, `remove
  src=prune`); a passing read failure (`stale_conns`, `crosswalks`: a write landing) only retries. A rebuilt junction at
  the same spot keeps its entry (it is the place the player enrolled).
- **Bounded**: at most `Auto.MAX` = 1000 entries (256 before v4); an add beyond is refused (`op=refuse reason=cap`),
  never an old entry dropped (each is an opt-in). At most `Auto.LAST_MAX` = 1000 records, the oldest dropped. Both caps
  reached: under 120 kB (with the 8th record field, the durations signature, 2026-10-16) in test_auto.lua's serialization, which writes every index key (`auto` ~1/3, `rlast` ~2/3).
- **Ignored without the mod** (severity None stays): the lists live only in our game script's state, which the game
  drops with the mod (removing the mod drops the enrolled list and the records; TESTING.md "RM"); what remains are
  written phase lengths, ordinary phases the game runs like hand-edited ones. A load runs nothing until the runtime
  reads the list (lazy; the plugin's first frame); the map editor ignores the event.
- Not saved (v4): the queue averages, the decision schedule and the adopt base: after a load each junction collects
  MIN_SNAPS snapshots again before its first decision, and the first refresh takes the current phases as the base.

### Gradual changes (the Webster caution)
The user's junction got cycle 50 -> 120 s at once (Y = 1.59, saturated). A long cycle can spill queues into the
neighbors, and every write may restart the running phase (probe Q3, open). Automatic writes therefore move the cycle by
at most `MAX_CYCLE_STEP` = 20 s (`R.plan` `maxCycleStep`, `cycle_wanted=` and `stepped=1` in the plan line): the same
junction walks 50 -> 70 -> 90 -> 110 s over three writes (10 game min apart since v4) and stops there (the last 10 s fall under the
hysteresis; test_retime.lua "plan with maxCycleStep"), so each step is measured before the next. The manual Re-time
keeps its one-step behavior (the player asked for it at that moment and watches it; nothing found against it yet).
Since v3 both stop balanced saturated junctions at max(75 s, current); only the automatic one smooths and confirms
(the manual run has one window and no history).

### Cycle rule v3 and damping (Light plans A/B run 2, 2026-10-15; built offline, not run in game yet)
Evidence: RESULTS.md "Light plans A/B run 2" (session `2026-10-15_0509_light-plans-auto-863105`, 6 sl_auto twins, 34
`op=plan` lines, extracted verbatim into `tests/square_smart_lanes/retime_run2.lua`). Auto beat the axis plan on
throughput in 6 of 6 sets, but:
- **Balanced saturated junctions** (g1v, g5v 2x2; g4v 3x3; load shares 0.50-0.62, y 1.11-1.28) walked 52/62 -> 112-120 s
  and stayed there: throughput +0-2 % (2x2 127.4 vs axis 125.4, 3x3 155.7 vs 155.5) for longer queues (2x2 183 vs 144,
  3x3 148 vs 116). Every road waits alike there; a longer cycle only lengthens every red. The lost time is what a long
  cycle buys back: 2x2 L = 8 s is 15 % of 52 s, 11 % of 75 s, 7 % of 120 s, so 52 -> 75 s gains about 5 % capacity
  and the further 75 -> 120 s about 4 % more for 60 % longer reds (run 2 measured +1.6 % throughput, +27 % queue for
  it). The game's own default cycles are 71-78 s.
- **Unbalanced junctions** gained clearly (3x3 unbalanced 46.5 vs 23.4 km/h, queue 10 vs 31; shares 0.65-0.90).
- **Flip-flop**: g2v 62 > 82 > 62 > 82 > 62 > 50 > 63 s and g6v 53 > 73 > 53 s. The loads hardly moved (g2v 55.9 /
  14.7 vs 41.8 / 11.7); y jumped 0.6 <-> 1.17 because the saturation flow came from the estimate (clamped to 1200, one
  queued approach) in one window and from the 1800 default in the next: a one-window "saturated".

The rule (`R.plan`, test_retime.lua "replay run 2 ..."):
1. **Balanced cap** (manual and automatic): when the cycle wanted is long (cycle_reason saturated, queues or max) and the
   busiest veh phase's share of the loads is at most `balanceRatio` 1.25 x an equal share (62.5 % for two roads, 41.7 %
   for three; run 2: balanced 0.50-0.62, unbalanced 0.65-0.90), the cycle goes at most to max(`balancedCycle` 75 s, the
   current cycle) (`cycle_reason=balanced`; the greens still follow the loads). The current cycle is never shortened by
   it (a player's long cycle stays). Unbalanced junctions keep Webster.
2. **Damping** (automatic only; since v4 "window" reads "decision": the previous decision's loads from the averages):
   (a) the loads are smoothed with the junction's previous window (0.5 / 0.5, `load_s=`
   in the plan line); (b) a long cycle is only lengthened toward when the previous window was long too, otherwise the
   cycle holds and only the greens move (`cycle_reason=unconfirmed`), and that junction is checked again in 5 min, not
   after a back-off. The previous window (loads per phase, long or not, game time, phase structure) lives in the
   runtime's record (`rec.hist`, a few numbers), **not in the save**: after a reload one window is unsmoothed and
   unconfirmed, which only holds the cycle once more (the safe side); a new phase structure (adopt) or a window older
   than 30 min (v4: a decision older than 60 min) is not used.
3. Not built: the throughput feedback ("step back when a longer cycle did not raise passes per minute"): run 2's window
   to window passes moved -10..+24 % at one junction with the same timing (g5v 311 -> 385, towns growing), more than the
   0-2 % such a test would have to see; it would act on noise.

Replayed (the logged loads, each window starting from the previous decision; cycle old -> new, greens of phases 1 / 3):

| junction | logged (run 2) | v3 |
|---|---|---|
| g1v 2x2 balanced | 52 > 72 > 92 > 112 > 120 (fits), greens 56/60 | 52 (unconfirmed) > 72 (balanced) then fits at 72, greens 31/37 |
| g5v 2x2 balanced | 52 > 72 > 92 > 112 > 120 (fits), 58/58 | 52 (unconfirmed) > 72 (balanced), 34/34 |
| g4v 3x3 balanced | 62 > 82 > 102 > 120, 60/54 | 62 (unconfirmed) > 75 (balanced), 34/35 |
| g3v 2x2 unbalanced | 52 > 72 > 92 > 112 > 120, 60/56 | 52 (unconfirmed) > 72 > 92 > 112 > 120, 60/56 (one window later) |
| g6v 3x3 unbalanced | 62 > 42 > 53 > 73 > 53 > 49 > 50 | 62 > 42 > 45, then 45 (the y 1.06 window unconfirmed), 30/9 |
| g2v 3x3 unbalanced | 62 > 62 > 82 > 62 > 82 > 62 > 50 > 63 (4 reversals) | 62 > 61, then 61 in every window (two windows unconfirmed), 44/11 |

(g1v / g5v stop at 72 s: the last 3 s to 75 move each green by 1.5 s, under the hysteresis.)

### The Stress Test interface (PLAN.md "Stress Test interface: Keep timing adjusted" has the exact spec)
- Zone mode `sl_auto` (SmartLanes.zones): Smart Lanes lanes + the axis plan, and the junction is enrolled
  (`src=zone`) once lit: an A/B twin against `sl_phases` measures the automatic re-timing alone.
- `SmartLanes.auto { op = "all", run }`: every lit junction on the map enrolled (`src=all`), answered by
  `AUTORETIME op=enroll_all phase=done ...`; `{ op = "clear", run }` unenrolls all.

### Open
- In game: everything (TESTING.md "KA v4"). Most important: that the plugin runs the runtime with the tool never opened
  (`op=snapshot` lines), that `constructionMenuActive` reaches it, the cost (`op=snapshot busy_ms= max_frame_ms=`,
  SQPERF `auto`), the queue corridors on real roads (curved approaches, close junctions), and whether repeated writes
  restart the cycle or re-route drivers (step A probe Q3 / Q4; the auto write has no probe).
- The head start (the earlier open point): still never added by a re-time; a re-plan with measured `laneDemand` would be
  a step C.
- Not built (left out on purpose, add when the in-game runs ask for it): widening the hysteresis for a junction whose
  last two results alternate (v3's confirmation and smoothing answer run 2's alternation; v4's averages more so), "stop
  after a hand edit of durations only" (replaced by adopt, user decision 2026-10-14), saving the averages (a reload
  waits MIN_SNAPS snapshots: the timing is low importance, user 2026-10-15).

### What the probe results decide (step B as built already keys by position and resolves the spot at every check)
- Q1 ids change -> position keys mandatory, re-attach on every check (not only when missing): built that way.
- Q2 config differs -> re-read after every write; if the engine re-makes phases, step B is not possible as designed.
- Q3 cycle restarts -> minimum interval 10 min and no write while the junction's queues are long in the green
  direction (writing mid-flow costs most).
- Q4 re-routing above the baseline -> writes only when the gain is large (hysteresis 25 %) and at most every 20 min;
  log the re-routed share per write and stop for that junction if it stays high.
- Q5 the flag is set by script writes -> step B cannot read the player's intent from it; rely on its own signature.
- Q6 routed lists empty at junction nodes -> step B's cheap check uses the segments' lists only (or the scan, which
  is too slow to run in the background for more than a few junctions).

## Step B v4: queue snapshots (user decisions 2026-10-15; built offline, not run in game yet: TESTING.md "KA v4")
User decisions: automatic timing is low importance in the overall game; it should keep lights reasonable over a long
game, occasionally. No sampling every few seconds, no continuous windows. The manual Re-time keeps its detailed
3-minute measurement (pass counting with route reads: a deliberate player action). One "last measured" record per
junction for both modes, saved. The enrolled cap ~1000, compact entries; the Stress Test interface unchanged.

### Snapshots (`sl_autoretime.lua` `startSnap` / `snapStep` / `finishSnap`)
- Every `SNAP_EVERY_S` = 120 game s (a snapshot that takes longer delays the next; none while the manual Re-time
  measures): the cars standing (`dyn.speed` < 0.5 m/s, `timeStanding` >= 5 s, the Stress Test's queue) on each approach
  of every watched junction, counted in **one pass over the drivers**, no route reads.
- **Corridors** (`T.armsOf`, `R.onCorridor`; the Stress Test's arm corridors, plans/square_stress_test/FLOW.md "Measured
  area"): per approach segment with incoming car lanes, a strip 12 m to each side of the arm's axis (the segment's
  tangent at the node), 6 m (the junction box) to 150 m out and no further than the segment's other end, its
  **inbound half** only (right-hand traffic: left of the outward heading, from the lanes as sl_slip `S.sideOf`;
  left-hand mirrored; a one-way approach or an unclear layout: both halves). So a car queued for the next junction
  down the road (the other half) is not counted here; a queue reaching back beyond the next node is not counted
  (it is saturated anyway). Curved approaches: the strip is straight (approximation).
- **Drivers**: the routed lists (`getSimPersonsMovingForTransportNetwork`, persons routed through) of the watched
  junctions' approach segments when there are at most `ROUTED_ENTS_MAX` = 48 of them (~12 junctions; each segment
  checked first: a removed one is not asked, `gone=`), else the whole `SIM_PERSON` list (one engine call, then one
  `SIM_PERSON` read per person, drivers placed with `vehicle.getPosition`). A grid of 200 m cells finds the junctions
  near a car, so 500 junctions cost about what 10 do (test "cost, v4": 40015 / 40143 / 40645 engine calls for 10 / 100
  / 500 junctions over 30k persons). Only a car on a corridor gets the driving / standing reads (MOVE_PATH, at-vehicle).
- **Budget**: 1 ms of **wall** clock per frame (`BUDGET_S`, checked every 8 engine calls: a frame ends within ~8 calls
  past it; test: 1.01-1.03 ms max at 3 us per call). The `SIM_PERSON` list itself is one engine call in one frame (8.8k
  persons in 0.5-0.9 ms in game, docs/findings: ~4 ms for 43k, ~10 ms for 110k): the only spike, once per snapshot, and
  none with routed lists. The reads start in the list's frame only when it left budget.
- **Wall clock, not os.clock** (2026-10-15, city run 2): the runtime timed its budgets and `max_frame_ms` with
  `os.clock`, the process CPU time of all threads on macOS (docs/findings/gui.md "Timers and threads"). Run 2 logged
  `max_frame_ms=81.52` and `49.20` (2 of 45 snapshots; the others 3.3-11.0) where SQPERF's wall clock saw at most 12.8 and
  13.8 ms in those 30 s windows, and the snapshot that fetched 12 518 persons at 20:03:05 lay in a window whose worst
  frame was 1.9 ms wall (`ctx=bg ... auto ... max=1.886`): the list call is not the spike, os.clock inflated every reading
  ~3-6x (and stopped every budget early by as much: busy_ms 650-960 "ms" per snapshot vs SQPERF 600-875 ms per 30 s
  for everything). Now `T.wallClock` (`api.type.Clock`, `os.clock` only without one; `op=config clock=wall|os`) drives
  the snapshot, heavy-step and Retimer budgets of the runtime, and the snapshot line adds `fetch_ms=` (the list calls
  alone: the one `SIM_PERSON` call, or the routed lists' frames) and `finish_ms=` (the averages and wake checks of every
  member, in the frame the reads end). The windows' 11-14 ms wall worst frames (several, also without a snapshot spike)
  are not attributed yet: the next run's wall `max_frame_ms` / `fetch_ms` tells whether a snapshot frame owns them or a
  heavy step / write does (TESTING.md "KA v4" step 14). Cheaper per-area person queries (octree by circle) are
  unverified: console one-liner in TESTING.md step 14. The manual Re-time (sl_toolcore, `os.clock` from
  sl_tool.script.lua) still times with `os.clock`: its 1.5 ms is really ~0.3-0.5 ms (left as it was measured in game).
- **Averages** (per junction and approach, memory only): each snapshot's count q becomes an arrival estimate under the
  timing in force (`R.arrivalOf`: a fixed-time queue holds lambda' r_e^2 / (2 C) cars on average, lambda' = lambda /
  (1 - lambda / s), r_e = the approach's red less the 5 s stand time; timing-normalized, so snapshots before and after a
  write average together), averaged exponentially with `TAU_S` = 1200 s (a running mean for the first snapshots); the
  standing count is averaged alike (the quiet check and the log).

### Per-frame cost (estimates)
Game per-call costs: ~2-3 us per component read / position (Stress Test sampler), ~35 us per routed list call
(docs/findings/lines-vehicles.md), the `SIM_PERSON` list ~0.1 us per person; a snapshot every 120 game s = 7200 frames
at 1x, 1800 at 4x (60 fps).

| watched | source | work per snapshot | busy frames (<= 1 ms) | mean per frame 1x | mean per frame 4x |
|---|---|---|---|---|---|
| 10 | routed (40 segments) | ~1.4 ms calls + ~5-15k candidates x 3 us = 20-50 ms | 20-50 | 0.003-0.007 ms | 0.01-0.03 ms |
| 100 | person list | town map (43k persons, 2.4k drivers): ~100 ms; Stress Test map (110k persons, 55k drivers): ~400 ms | 100-400 + the list frame (4-10 ms) | 0.014-0.06 ms | 0.06-0.22 ms |
| 500 | person list | as 100, plus ~5k more cars on corridors x 12 us: ~105-460 ms | 105-460 + the list frame | 0.015-0.064 ms | 0.06-0.26 ms |

Plus refreshes (one light read, the node's segments and the corridors, ~0.3 ms, each junction every 300 game s: 500
junctions at 4x ~1 in 9 frames, ~0.03 ms mean) and decisions (as rare). **Heavy-step budget** (2026-10-15, after the
city run's 30.1 / 29.2 ms bg frames when 243 junctions' first decisions came due together, RESULTS.md "City lights at
scale"): refreshes and decisions found due wait in `R.dueSet` and run oldest due first within `HEAVY_BUDGET_S` = 1 ms of
clock per frame (at least one, at most `HEAVY_MAX` = 4), none in a frame that wrote and none while a snapshot reads;
the rest carry to the next frames. A junction's first decision waits `T.firstDelay` (0 .. one snapshot interval, from
its position), so junctions enrolled together come due spread over 120 game s. The snapshot line reports `heavy=`
(steps since the previous snapshot) and `backlog=` (the most due steps carried over at once). One step is never split:
a single slow refresh or write still costs what it costs (SQPERF `auto` max).
A Stress Test map's 400 ms snapshot spans 400 frames (~7 s wall, ~27 game s at 4x): within its 120 s.

### Decisions (`decide`, `R.planQueue`)
- A junction is decided once it has `MIN_SNAPS` = 8 snapshots (~16 game min after it is watched), then at its interval
  (`Auto.nextEvery`: after a write 10 game min; fits / too little traffic 10, 20, 40, 60 min; a long cycle not confirmed
  yet 5 min). A refresh (light read, adopt) comes first.
- **Check interval setting** (mod.json `sqrl_auto_every`, "Keep timing adjusted: check interval", x0.5 / x1 / x2 / x4,
  default x1; user 2026-10-15): a factor on `EVERY_SOON`, `EVERY_WRITE`, `EVERY_BACKOFF` and `EVERY_MAX`
  (`Auto.every`, `Auto.setEveryFactor`, clamped to [0.5, 4]): x0.5 writes 5 min apart and backs off 5, 10, 20, 30 min;
  x2 20 .. 120 min; x4 40 .. 240 min. Not scaled: `EVERY_FIRST`, `RETRY_S`, the snapshots (120 s), the averages
  (~20 min), the map-wide write gap (5 s), the manual Re-time. Read once per runtime in `T.new` from `getModParams()`
  of the background plugin's Lua state (as SQPERF's gate there), x1 when that fails; logged `AUTORETIME op=config
  every_factor= params=read|unread`.
- **Early wake** (user 2026-10-15: "next check in 34 min" too long at a junction that was quiet): after each snapshot,
  a junction whose last decision was `quiet` or `fits` is due at once when its averaged standing cars clearly changed:
  quiet -> all approaches together at least 1.5 x `quietQueue` (1.5 cars; the decision said below 1: the gap is the
  hysteresis); fits -> the total grew by half and by at least 1.5 cars to at least 3 (`fits_grow`), or an approach's
  share of the standing cars moved by more than 0.2 (the write hysteresis' 20 %) **and** by at least 1.5 cars (the share
  moved x the standing cars now), with at least 3 cars standing at the decision and now (`fits_shift`). Never
  before the write gap after the junction's last write (or adopt) ends (`EVERY_WRITE` x the factor), at most once per
  decision (the interval after the woken decision follows `Auto.nextEvery` as usual); other keeps (few snapshots, no
  mapped traffic) and pending writes never wake. Only the averages the snapshot just updated are compared (no game
  reads). Logged `AUTORETIME op=wake node= pos= reason=quiet_rise|fits_grow|fits_shift queued=<at decision>><now>
  shift= shift_cars= decided_s= due_was_s= due_s=` (`T.WAKE_QUIET_X`, `WAKE_GROW_REL`, `WAKE_GROW_ABS` 1.5,
  `WAKE_SHIFT`, `WAKE_MIN_CARS` 3, `WAKE_SHIFT_CARS` 1.5).
- **Wake minimums** (2026-10-15, city run 2, RESULTS.md "City lights at scale, run 2"): 51 wakes against 21 writes over
  243 junctions in 90 game min: fits_shift 42, quiet_rise 6, fits_grow 3. The woken decisions: fits_shift -> fits 40,
  quiet 1, write 1 (at 1.3 > 1.7 cars); fits_grow -> fits 3; quiet_rise -> write 5, fits 1. The fits wakes stood at
  1.0-6.6 cars (all but 7 under 2.5), their share moves 0.20-0.35 = 0.2-1.4 cars: noise. Replayed under the minimums
  (3 cars standing, a share move of 1.5 cars, growth of 1.5 cars to 3): **6 kept** (the 6 quiet_rise, 5 of which wrote),
  **45 dropped** (all fits_shift and fits_grow; the largest: 6.6 > 5.7 cars, shift 0.24 = 1.37 cars; 4.2 > 4.8, 1.2 cars;
  fits_grow 1.8 > 3.0, +1.2 cars). The one write lost to it (1.7 cars) comes at that junction's regular decision.
  Tests: test_tool.lua "wake rules" (noise at 1-2 cars and run 2's largest cases don't wake; a 2.5-car shift at 6 cars
  does).
- `R.planQueue`: per approach lambda' per entry lane back to lambda = lambda' s / (s + lambda') (s = 1800 cars / lane /
  h: a queue that grows without end reads as lambda -> s, saturated), its flow the approach's load **in every veh phase
  it has green in** (`R.approachPhases`; movements freed all cycle give no phase). The axis plan: one phase per road,
  so a road's load is its busier approach. A classic or hand-made plan that splits an approach's movements over phases
  (a lead turn phase): the approach's whole flow counts in each of them (approach-level queues can't tell which
  movement waits; documented approximation, test "an approach split over phases"). Then as `R.plan`: critical approach
  per phase, Webster's cycle with s = 1800, the v3 balanced cap (75 s), `maxCycleStep` 20 s, damping (smoothing with
  the previous decision, a long cycle only after two long decisions), floors, pedestrians.
- **Freed turns and light traffic** (city run 2026-10-15 bug, both modes): `R.kinds` ignores connections green in
  more than half of the phases (`R.alwaysGreen`: curb turns freed by Free curb turn Always / When safe, green in the
  pauses and the pedestrian phase too). Before, they made the game's all-red and pedestrian phases "veh": phase 5
  (pedestrians, 3 s) got the crosswalks' 25.5 s need as its floor and the min cycle squeezed the through phases,
  27.1/6/27.1/6/3/9 -> 6/6/9/6/26/6 at every write whatever the load. Also: a phase without traffic is never lengthened
  for a crosswalk (`idleCrosswalkCap`), and a cycle that shrinks for light traffic (not a long one being capped) never
  cuts a phase with at least half an equal share of the loads below min(its current, the game's green for its critical
  approach's lanes, `PP.gameGreen`) (`keepLoadedOnShrink`, applied after the split: it only raises such a phase). A
  phase without traffic also never takes the time a loaded phase can't (60 s slider cap): at most its current seconds
  (`idleCrosswalkCap`). A movement green all cycle adds no queue to its approach for the cycle rule's `queues`
  (`freedQueueOut`; manual run node 9594: the freed 12085>7448 turn's 20-car queue gave `queues` -> 120 s and the
  empty side road 16-36 s). The auto cases now give 10/6/28/6/3/9, 6/6/28/6/3/9 and fits (logged 6/6/9/6/26/6), the
  manual one 6/6/28/6/3/9 (logged 16/6/60/6/26/6) (test_retime.lua "live city run 2026-10-15"). The manual Re-time had
  the same bug (same `R.kinds` / `finishPlan`; its log line said `kinds=veh/veh/veh/veh/veh/veh always=30`).
- **Thresholds**: keep when fewer than 8 snapshots (`few_snapshots`), when the mean standing cars on all approaches
  together are below 1 (`quiet`: quiet junctions never write; recorded "too little traffic"), when no approach maps to
  a phase; write only when a veh phase moves by at least max(4 s, 20 %) (`HYST_ABS` / `HYST_REL`, wider than the
  manual run's max(3 s, 15 %): "clearly off").

### Write scheduler (`writeStep`)
- A decision that wants a write waits in `R.pending` with its expected gain (the cars standing x the green seconds
  moved / the cycle). At most one write per `WRITE_GAP_S` = 5 game s map-wide, the largest gain first.
- Held while the player builds within 300 m (construction menu open, 30 s after) or a tool proposal is pending there /
  the manual Re-time is at that junction (`op=hold reason=building|busy`, once per wait); dropped after `PENDING_MAX_S`
  = 120 s (`op=skip reason=stale held=`), decided again 2 min later.
- Per junction at most one write per `Auto.EVERY_WRITE` = 10 game min x the check interval factor (ours, or a hand
  edit: an adopt counts as one).
- The write is `W.retimeLights(..., "auto")` (durations only, the phases' signature re-checked: a change since the
  decision gives `sent=0 why=changed`, refreshed and retried). After a write the junction's timing for the snapshots is
  the written one.

### Records and status (both modes)
- Saved `rlast = { {n, x, y, t, k, c0, c1, d} }` (node id, position, game s, k = source x 10 + outcome: source 1 manual /
  2 auto; outcome 1 written, 2 fits, 3 too little traffic, 4 not written; cycle before and after; d since 2026-10-16:
  the signature of the durations Smart Lanes last wrote there, `Auto.durSig`, 0 = none, carried by a not-written
  outcome; PLAN.md "Smart lights stays on after its timing changed"), one per junction ever
  measured (matched by id or within 2 m), at most 1000 (oldest dropped), `lseq` +1 per change; event `SmartLanes.auto
  op=last` (src tool / auto, 60 per event). The runtime batches its records every 30 game s (`LAST_FLUSH_S`; a written
  one goes out at once since 2026-10-16, and each record reaches the tool's mirror at once through `opts.lastSent`
  when they share a Lua state); the tool sends the manual run's at once and shows it before the event lands.
- Status at a selected lit junction (translated, 13 languages): enrolled first "Keep timing adjusted: counting waiting
  cars (3 of 8)" | "Keep timing adjusted: next check in 12 min" (plain wording, user 2026-10-16; before: "Timing kept
  adjusted: watching queues (3 of 8 snapshots)") | "Timing kept adjusted at this junction" (the
  runtime in another Lua state), then the manual run's progress "Re-time: measuring traffic (87 of 180 s)" or the
  record: "Last measured 12 min ago (manual): cycle 50 -> 75 s" | "Last measured 2 h ago (auto): already fits" |
  "... too little traffic" | "... not written (see log)" | "... greens adjusted (cycle 72 s)" (ago: just now, N min,
  N h from 120 min).

### Log (`AUTORETIME`, PLAN.md "Logging")
`op=config every_factor= params= clock=wall|os`; `op=snapshot n= src=routed|scan cand= read= drivers= near= counted=
calls= frames= busy_ms= max_frame_ms= fetch_ms= finish_ms= span_s= gone= capped= enrolled= err= heavy= backlog=` (the ms
in wall time since 2026-10-15); `op=wake node= pos= reason= queued= shift= shift_cars= decided_s= due_was_s= due_s=`; per decision `op=plan node= pos= result=write|fits|quiet|few_snapshots|no_mapped_traffic|
no_vehicle_phase snaps= queued= queue=<seg:mean> arrive=<seg:cars per lane per h> load= load_s= share= balanced= old=
new= cycle= cycle_wanted= stepped= greens= y= cycle_reason= every=`; `op=hold reason=`, `op=skip reason=stale|read:<why>`,
`op=write ... sent= why= durations= cycle= greens= stepped= gain= every=` and `op=write at=cb success=` (the fields
tools/flow_report.py reads kept), `op=reset reason=lanes snaps=`, `op=adopt`, `op=reattach`, `op=prune`,
`op=enroll_all`. Gone with v4: `window_start`, `window_end`, `settle`, `member_gone`. The write and enroll_all lines
have their own cap (4000), so many junctions' plan lines never hide them.

### Stress Test timeline (what a twin run sees)
First decision ~16 game min after the junction is watched (8 snapshots), first write then; with damping a saturated
unbalanced junction confirms its long cycle at the next decision (10 min later) and steps 20 s per write, 10 min apart:
52 -> 112 s takes ~3 writes after confirmation, ~45 game min after enrolling. A twin run should last ~90 game min or
more, the comparison window after the last write.
