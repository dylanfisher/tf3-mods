# Traffic flow A/B: log contract (FLOW_PLAN.md step 0, 2026-10-12)

Results of every run so far: `plans/square_smart_lanes/RESULTS.md` (add new runs there).

The lines Smart Lanes (`[SQRL] TOGGLE`) and the Stress Test traffic log (`[SQST] FLOW_*`) write to stdout.txt, so
`tools/flow_report.py` (step 6) can be written while steps 1-5 are built. Values marked **(P)** are provisional
until the in-game Flow probes (Stress Test Probe tab 11a-11h, TESTING.md 6M) answer them; the probe that answers
each is named. Step 0 is Stress Test side only: the Smart Lanes channel probes (FLOW_PLAN.md open questions 7-9:
fireGuiScriptEvent across Lua states, makeScriptingSendEventCmd on an old save after re-subscribe, fireReactEvent
gs -> tool, light phases after AUTO, engine default at fresh slip / drop nodes) are **deferred** to the Smart Lanes
agent (square_smart_lanes was being edited by another agent); step 1 must not start before they ran.

## Grammar (all lines)

```
<prefix> <KIND> key=value key=value ...
```

- `<prefix>` is `[SQRL]` (Smart Lanes, `Rules.line`, sl_rules.lua) or `[SQST]` (Stress Test). One line per event.
- Values never contain whitespace (written with `_` instead). Unknown keys must be ignored by the parser (keys may be
  added later, never renamed); key order is fixed as below but the parser must not depend on it.
- `-` = no value (unreadable, or nothing to average). Numbers: integers as `%d`, others `%.3g` (so `0.719`, `13.9`,
  `1.2e+03`).
- Lists `a,b,c`; count maps `key:count,...` most frequent first, `+N` = N more keys cut off (line cap 200 chars per
  value).
- `gt` = `GAME_TIME.gameTime` of the world entity (api/engine.d.tl:425-433), the time axis for the report: both mods
  write it, so lines of the two mods are ordered by it, not by stdout order. Unit: game milliseconds (verified,
  docs/findings/lines-vehicles.md "Units": 10 000 per 10 s at 1x; FLOW_START writes `gt_per_s=1000`). `gt` is only monotonic within one game
  load: loading a save (an older one, or the same one again) restarts it from the save's time. The parser first
  splits stdout.txt into loads (at each `[SQRL] TOGGLE phase=load` line, and at the game's own load messages when
  Smart Lanes is absent) in stdout order, then orders by `gt` within a load only.
- The stdout.txt time stamp in front of each line (wall clock) is kept by the parser as `wall` for warnings only.

## `[SQRL] TOGGLE` (Smart Lanes step 2, sl_toggle.lua)

```
[SQRL] TOGGLE state=off phase=start seq=7 nodes=412 written=0 same=0 skipped=0 kinds=- skips=- ms=0 gt=81234000
[SQRL] TOGGLE state=off phase=end seq=7 nodes=412 written=380 same=20 skipped=12 kinds=X:210,ring:120,A:30,B:12,D:8 skips=no_pre:9,stale:3 ms=5400 gt=81301000
[SQRL] TOGGLE state=on phase=load seq=7 nodes=412 written=0 same=0 skipped=0 kinds=- skips=- ms=0 gt=90000000
```

| key | meaning |
|---|---|
| `state` | `off` = game default lanes, `on` = Smart Lanes lanes. At `start`/`end`: the target mode; at `load`: the mode in force |
| `phase` | `start`: a toggle job begins (old layout still in force, partly from here); `end`: every batch done, the new layout is in force from this `gt`; `load`: once per game load after the registry is read (no job) |
| `seq` | the registry's `modeSeq` (+1 per toggle); `start` and `end` of one job share it |
| `nodes` | registry nodes in the job's scope (plus scanned PLAYER_OWNED nodes when that option is on) |
| `written` / `same` / `skipped` | nodes whose configs were sent / already in the target layout / left unchanged (0 at `start` and `load`) |
| `kinds` | written nodes by Smart Lanes case: `ring`, `X`, `A`, `B`, `D` |
| `skips` | skipped nodes by reason: `no_pre` (A/B/D without a pre snapshot), `stale` (snapshot no longer fits), `gone`, `no_config`, `refused` |
| `ms` | wall ms of the job (0 at `start` / `load`) |
| `gt` | game time at the line |

Report rule: a block starts at a `phase=end` or `phase=load` line and runs to the next `phase=start` (or the end of
the log / of a `FLOW_SUMMARY` run); time between `start` and `end` is dropped. A `load` with the same `state` as the
block before it continues the mode but starts a new block (the sampler restarts after a load anyway).

## `[SQRL] MODE` (Smart Lanes rev 4, sl_lanes.script.lua; PHASES_PLAN.md step 4, 2026-10-12)

```
[SQRL] MODE phases=sl free_turn=safe
```

Once per game load, when the Smart Lanes game script's GUI state starts (before any job; also with Apply
automatically Off). Mod settings cannot change during a load, so the line holds for the whole load.

| key | meaning |
|---|---|
| `phases` | setting "Light phases": `game` = the game's own traffic light phases (re-pointed to the lanes), `sl` = Smart Lanes planned phases at lit crossroads / T-junctions it writes (sl_phaseplan.lua) |
| `free_turn` | setting "Free kerb turn at traffic lights": `off` / `safe` / `always` (with `phases=sl` only where no plan could be made) |

Report rule: split runs by `phases` (the A/B of Smart Lanes phases vs the game's); a load without a MODE line (Smart
Lanes absent or older) is `phases=game`. Per junction, `[SQRL] PHASES node= phases=sl plan=|plan_fail=` (and
`LIGHTS ... to=sl_phases`, `LIGHTS ... to=game_phases` for a Reset) say which lit nodes actually run a plan; Smart
Lanes' `SUMMARY` lines carry `phases=` too. No `gt` on these lines: order them by stdout within the load.

## `[SQRL] ZONES` (Smart Lanes rev 4, sl_zones.lua / sl_lanes.script.lua; twins channel, 2026-10-12)

```
[SQRL] ZONES op=set n=24 run=s747943-1760280000-1 by_ab=game:10,sl:10,sl_phases:4
[SQRL] ZONES op=clear n=0 run=s0-1760281234-2 by_ab=game:0,sl:0,sl_phases:0
[SQRL] ZONES op=ignored reason=r3
[SQRL] ZONES op=loaded n=24 run=s747943-1760280000-1
[SQRL] SKIP kind=zone zone=game job=12 nodes=9 reason=zone_game
[SQRL] ZONES op=set n=25 run=fan1 by_ab=game:10,sl:10,sl_phases:4,sl_fan:1
[SQRL] APPLY kind=slip node=331872 shape=crossroads case=X side=right lanes=.. split=node before=24 after=48 lit=yes mode=fan
[SQRL] PHASES src=auto node=331872 phases=sl plan=x4_fan cycle=90 1:16s/skip1.5[12-23,36-39] 2:red2 ..
[SQRL] SUMMARY job=13 nodes=5 .. phases=game sl_plans=1 plan_fail=- zone_fan=1 free_turn=..
[SQRL] ZONES op=set n=24 run=s747943-1760290000-2 by_ab=game:6,sl:6,sl_phases:6,sl_lock:6
[SQRL] APPLY kind=slip node=331880 shape=crossroads case=X .. lit=yes zone=sl_lock free_turn=off
[SQRL] SUMMARY job=14 nodes=5 .. phases=game zone_lock=1 lock_turn=0 lock_phases=0 free_turn=0 free_phases=0
```

`set` / `clear` / `ignored`: on receipt of a `SmartLanes.zones` event (engine thread, handleEvent); `loaded`: once
per game load when the GUI state starts (after `MODE`), from the saved state, so a reload keeps the zones (also
with Apply automatically Off; not in the map editor).

| key | meaning |
|---|---|
| `op` | `set` (every zone replaced), `clear` (all removed), `ignored` (payload refused as a whole: nothing changed), `loaded` |
| `n` | zones now stored (`set` / `loaded`) |
| `run` | the sender's run id (`-` none); Stress Test reads it back as the acknowledgement |
| `by_ab` | zones per mode, fixed order `game,sl,sl_phases`, then `,sl_fan:<n>` only when the set has fan zones, then `,sl_lock:<n>` only when it has lock zones, then `,sl_exitfan:<n>` only when it has exit-fan zones (older lines unchanged) |
| `reason` | `ignored` only: `not_table`, `op`, `run`, `zones`, `too_many` (> 400), `zone<i>` / `xy<i>` / `r<i>` / `ab<i>` (the first bad zone; r must be in (0, 2000] m, \|x\|,\|y\| <= 1e6, ab one of game / sl / sl_phases / sl_fan / sl_lock) |

Effect (automatic pass only; nothing written before the zones arrived is changed): a node in a `game` zone is left
alone (no lanes, lights or phases): one `SKIP kind=zone zone=game job= nodes= reason=zone_game` per job (a ring with
any node in a game zone: `SKIP ring= node= reason=zone_game`, the whole ring), `SUMMARY ... skips=zone_game:<n>`.
`sl`: as everywhere (the global settings). `sl_phases`: lit crossroads / T-junctions get the Smart Lanes phase plan
as with Light phases = Smart Lanes (`PHASES ... phases=sl plan=`); with the setting at Game default `SUMMARY` then
carries `sl_plans= plan_fail= zone_phases=<nodes planned for the zone>`. A node in several zones takes the one whose
centre is nearest relative to its radius. The tool's Apply works in a game zone (manual override): its `APPLY
src=tool` lines end in `zone=game`.
`sl_fan` (added 2026-10-12, a measuring mode: square_smart_lanes PHASES_PLAN.md "Fan mode"): a lit crossroads /
T-junction gets the full fan (every entry lane to every exit lane of every other arm) and a split plan, one approach
per phase, in one proposal: `APPLY ... lit=yes mode=fan`, `PHASES ... plan=x4_fan|t3_fan|fan ...`, `SUMMARY ...
zone_fan=<nodes>` (with `sl_plans= plan_fail=`). Unlit / unknown nodes there keep the rule (`APPLY ... fan=unlit` /
`fan=lit_unknown`; a light that comes later: `APPLY src=recheck ... mode=fan`); a fan whose plan fails is not written
(`SKIP ... reason=lights:fan_<reason>`). Fan nodes log no `AUDIT` lines. Report rule: a twin whose junction logged
`mode=fan` is a fan twin (ab `sl_fan`); compare it with the game / sl / sl_phases twins of the same pair. The Stress
Test sends `sl_fan` zones from its Lights showcase (2026-10-12, SHOWCASE.md "Lights showcase": twin `d` of every
lit crossing set; `SL_ZONE_AB` has it; its `by_ab` then ends in `,sl_fan:<n>` as Smart Lanes' own). Since 2026-10-12 the Lights
showcase builds no bus lines (SHOWCASE.md "Faster, simpler Lights showcase"): no `FLOW_BUS` lines for it.
`sl_lock` (added 2026-10-12, a measuring mode: square_smart_lanes PHASES_PLAN.md "Lock mode"): as `sl` (Smart Lanes
lanes), but the kerb turn at crossroads / T-junctions is never freed, as with "Free kerb turn" Off, and the light
phases stay the game's, whatever the global settings; a kerb turn freed by an earlier write is locked back with its
approach. Lines: `APPLY ... zone=sl_lock free_turn=off` (and on its `AUDIT` line), `SUMMARY ... zone_lock=<nodes>
lock_turn=<kerb connections locked back> lock_phases=<n>` (free_turn= never counts them), `LIGHTS src=auto ...
to=lock_turn` when only the phases had to change. Report rule: `sl_lock` vs `game` = the lane layout alone, `sl` vs
`sl_lock` = the free kerb turn alone (with `MODE phases=game`; `MODE free_turn=` says what the sl twin ran).
tools/flow_report.py compares both (`COMPARISONS`). Stress Test side, **done 2026-10-13** (offline-tested, not run
in game yet): the Lights showcase sends an `sl_lock` twin (letter d, towns "Kerb locked <set> <side>") instead of
`sl_fan` (`LIGHTS_AB`, `SL_ZONE_AB`, its own `by_ab` text ending in `,sl_lock:<n>` after `,sl_fan:<n>`, and
`stress_flow` TWIN_ORDER sl_lock = 5 after sl_fan, letter d); `sl_fan` stays valid in Smart Lanes and is still read
(older saves, `isTestTownName` "Full fan ...").

`sl_exitfan` (added 2026-10-13, Smart Lanes sl_zones.lua; PLAN.md "Exit-lane fan (sl_exitfan zones)"): as `sl`, but at
a lit crossroads / T-junction every turn fans into every exit lane it can reach without crossing a movement green in
the same phase of the game's axis phases; the phases stay the game's. Lines: `APPLY ... zone=sl_exitfan exit_fan=yes`.
Report rule: `sl_exitfan` vs `sl` = the exit fan alone, `sl_exitfan` vs `game` = lanes + fan (tools/flow_report.py
`COMPARISONS`). Stress Test side, done 2026-10-13 (offline-tested): the mixed Lights showcase's third twin, letter e
(`LIGHTS_EXITFAN_AB`, zone ids `g<k>e`, towns "Exit fan <set> <side>"), `SL_ZONE_AB`, its `by_ab` ending in
`,sl_exitfan:<n>` (tested byte for byte against Smart Lanes' `byAbText`), `stress_flow` TWIN_ORDER sl_exitfan = 6,
letter e.

Payload zones are `{x, y, r, ab, id?, pair?}`: `id` / `pair` (added 2026-10-12, optional) are the sender's labels,
1..12 characters of `[%w_]` (the Stress Test sends its twin ids `g3a` / `g3`); Smart Lanes stores them with the zone
and never uses them; a malformed label is dropped, never the zone, so older payloads stay valid (also with
`sl_fan` added: a payload of game / sl / sl_phases zones is valid and logs the same `by_ab` as before). The Stress Test
traffic log reads them back after a reload (FLOW_ZONE `id_from=sl`).

Stress Test side: `[SQST] showcase zones sent n= run= by_ab= smart_lanes=yes|no [dropped=] [failed=yes]` before the
towns, `[SQST] showcase zones ack=yes|timeout|absent|unsent run= ms=` before the first junction, `[SQST] showcase
zones cleared by=remove_roads|remove_grid|remove_all run= smart_lanes=` (Remove all roads, Remove towns > Grid / All
towns). Report rule: a load whose stored zones came from another run than the zone lines' Showcase (`run` differs,
or `ack=timeout|absent`) cannot trust `ab` for the junctions built before the ack.

## `[SQST] FLOW_*` (Stress Test traffic log, built 2026-10-12: stress/stress_flow.tl, gui/stress_flow_log.tl)

Traffic tab > Traffic log (On / Off, every 10 / 30 / 60 game s, default 30). Every line carries `run=` (sampler
run, +1 per start in the session: On, an interval change, a new Showcase) and every per-sample line `s=` (sample
number in the run, from 1) and `gt=`. A sample (sweep) is one pass over the SIM_PERSON list, spread over frames;
its lines are written when the sweep ends, `gt` = game time at the sweep's start. Sampled on the Main Thread only
(an rt tick hook, react.onStep); per frame at most 2 ms (`budget_us`; 2000 driver reads per frame are only a safety
stop) and 100 written lines. **v3 (2026-10-12): every driver is read** (v2 read the first 3000 only: seed 530609 had
~55k drivers, `capped=1` every sweep, and the zones saw 0-35 cars). A sample that comes due while the previous sweep
still runs is skipped (`FLOW_SUMMARY skipped=`) and lowers the run's per-sweep target once per sweep to the drivers
read so far x 0.75 (never below `target_min` 3000; one `FLOW_TARGET` line); later sweeps then read every `stride`-th
driver, spread over the whole list. The target is never raised again within a run (a new run starts with every
driver). The time axis is game time: a paused game takes no sample.

**Sweep cost at 55k drivers** (estimate from seed 530609's v2 lines: 109k persons checked + 3000 read = ~95 ms busy in
~75 frames): every driver read adds ~2-4 us (MOVE_PATH dyn, entityExists, getPosition, zone lookup), ~0.2 s, so a
sweep is ~0.3 s busy in ~150 frames of <= 2 ms: ~2.5 s wall at 60 fps, inside the 30 game s interval at 4x (7.5 s
wall, ~450 frames). The fake-clock test (60k persons, 48k drivers) reads all of them in < 450 frames, no frame over
2.1 ms. `FLOW_ALL frames= sweep_ms= frame_ms_max=` record the real cost.

Units (verified, docs/findings/lines-vehicles.md "Units" and the probe session 2026-10-12_0905): `gt` and bus
departures game ms (`gt_per_s=1000`), `dyn.speed` m/s, `timeStanding` s, `sectionTimes` s.

### FLOW_START (once per run)

```
[SQST] FLOW_START run=2 v=3 interval=30 interval_unit=game_s zones=46 towns=50 buses=12 speed=4 keep_cleared=0 cap=0 gt=81400000 gt_per_s=1000 src=placement sc_run=s747943-1760280000-1 budget_us=2000 target_min=3000 measure_pad=200 corridor_m=30
```

`v` contract version: **2** = `interval` in game seconds (`interval_unit=game_s`; v1 planned wall seconds) and
zone membership by position; **3** = every driver read (`cap=0`; v2 logged `cap=3000`), zones measured out along
their arms (`r_measure`, `cars_core`, `q_arm`), `target_min` / `measure_pad` (m beyond r) / `corridor_m` (corridor
width); `zones` / `towns` (TOWN entities) / `buses` (SQST Bus lines) at the start; `speed`
GAME_SPEED.speedup; `keep_cleared` 1 when Keep traffic cleared is on (the run is then invalid for A/B: the report
warns; the Traffic tab also opens a warning); `cap` driver reads per sweep at the run's start (0 = every driver); `gt_per_s` gt units per game second;
`src` where the zones come from: `placement` (the session's Showcase), `sl_zones` (Smart Lanes' saved zones, after
a reload), `none`; `sc_run` the Showcase zones run id (the `showcase zones sent run=` / Smart Lanes `zrun`);
`budget_us` the per-frame budget. Added 2026-10-13 (still v3: keys only added): `drive_side` (`right` / `left`, the
side `q_in` / `q_out` assume: the Lights showcase's read of a grid street, else right), `thru_r` / `thru_track` /
`thru_window` (the `thru` count's parameters, below).

### FLOW_ZONE (once per zone after FLOW_START)

```
[SQST] FLOW_ZONE run=2 zone=14 kind=rb src=placement label=Magic_Roundabout x=1200 y=-3400 r=167 twin=g3a pair=g3 ab=sl sc_run=s747943-1760280000-1 id_from=showcase match=yes r_measure=367 measure=corridor arms=N,E,S,W
[SQST] FLOW_ZONE run=3 zone=2 kind=other src=sl_zones label=g1b x=1000 y=0 r=120 twin=g1b pair=g1 ab=game sc_run=s5-6-7 id_from=sl r_measure=320 measure=circle arms=-
```

**Measured area (v3)**: `r` stays the junction's circle (the v2 zone); `r_measure` = r + 200 m. `measure=corridor`
(the session's Showcase: the read's measured arm headings, `arms` their compass points in N, NE, E, ... order): a
car counts when it is within `r`, or on an arm's corridor (30 m wide, 15 m each side of the arm's axis, from the
centre out to `r_measure`), so the approach roads where the queues stand are measured. `measure=circle` (after a
reload: Smart Lanes stores no headings): the whole circle `r_measure`. Chosen over a plain r + 200 m circle because
the corridors give per-approach queues (`q_arm`) and leave out anything between the arms; the Lights showcase's town
entries lie ~400 m out, beyond `r_measure` (tested).

`zone` number within the run (zones in the Showcase's group order); `kind` `rb` | `ix` | `x` (plain crossing / T)
| `other` (after a reload: Smart Lanes stores no kind); `src` as FLOW_START; `label` the construction type
(spaces `_`), the twin id after a reload; `x`,`y`,`r` metres: a car whose `getPosition` lies within `r` of the
centre is in the zone (overlapping zones each count it). Session: the twins whose `showcase zone` line was
written (built and read; a refused twin has none), `r` the measured reach. After a reload: Smart Lanes' stored
zones, `r` = the reach estimate + 20 m pad (`SL_ZONE_PAD`). `twin` / `pair` / `ab` as the `showcase zone` line
(`twin=-` for a zone without one); `id_from` `showcase` (session), `sl` (the id / pair labels Smart Lanes stored
with the zone, Smart Lanes rev 4 from 2026-10-12), `order` (an older Smart Lanes without labels: recomputed from
the stored order, the Showcase's group order: a new set whenever a twin does not follow the previous one in
sl, game, sl_phases, sl_fan (then sl_lock, once the Stress Test sends it) order); `match` / `reason` (session only) as the `showcase zone` line. Not written (dropped
from the v1 plan): `nodes` / `edges` (membership is by position, FLOW_PLAN.md "Sampler requirements").

### FLOW (one per zone per sample, also for zones with no car)

```
[SQST] FLOW run=2 s=5 zone=14 twin=g3a pair=g3 ab=sl gt=81520000 cars=9 standing=3 standing_pct=33.3 queue=2 v_mean=6.1 v_med=7.4 v_kmh=22 stand_mean=8.2 stand_max=21 cars_core=4 q_arm=N:1,E:0,S:1,W:0
[SQST] FLOW run=2 s=5 zone=15 twin=g3b pair=g3 ab=game gt=81520000 cars=0 standing=0 standing_pct=- queue=0 v_mean=- v_med=- v_kmh=- stand_mean=- stand_max=- cars_core=0 q_arm=N:0,E:0,S:0,W:0
```

| key | meaning |
|---|---|
| `twin` / `pair` / `ab` | the zone's twin (self-describing; the same as its FLOW_ZONE) |
| `cars` | sampled drivers (SIM_PERSON lastMoveMode DRIVE + MOVE_PATH, not seated in a vehicle) whose `api.engine.util.vehicle.getPosition` lies in the zone's measured area (v2: within `r`) |
| `cars_core` | v3: of `cars`, those within `r` (the junction itself; v2's `cars`) |
| `q_arm` | v3: queued cars (`timeStanding >= 5` s) per arm corridor, `<arm>:<n>` in the FLOW_ZONE `arms` order; both directions of the arm (`-` without arms) |
| `q_in` / `q_out` | 2026-10-13: of `q_arm`, those on the inbound side (lanes towards the junction) / the outbound side, same format. The side is the car's position across the arm's centreline (the corridor runs straight out from the centre): inbound = right of the way in for `drive_side=right`, left for `left`; no heading read. Missing in older logs (the report shows `-`) |
| `thru` / `thru_s` / `thru_scale` | 2026-10-13: cars through the junction since the previous sample (already x `thru_scale`), that interval in game seconds, and the stride it was counted on (1: every driver; k: the drivers whose entity id is a multiple of k, x k). `-` all three in the first sample, when the two samples used different strides, or at stride 1 when a target cut drivers off. Method below |
| `standing` | of `cars`, `dyn.speed < 0.5` m/s; `standing_pct` = standing / cars x 100 |
| `queue` | of `standing`, `dyn.timeStanding >= 5` s (stopped for a while, not just braking) |
| `v_mean` / `v_med` | `|dyn.speed|` over `cars`, m/s (car-weighted mean, median); `v_kmh` = v_mean x 3.6 |
| `stand_mean` / `stand_max` | mean / max `timeStanding` of the standing cars, s |

Not written: `v_rel` (the lane speedLimit read failed in probe 11a; the report treats it as missing).

**`thru` by position (2026-10-13, the primary count since then; plans/square_stress_test/BENCH.md "Thru by
position").** The path elements read nothing in game, so `thru` counts by position: a driver seen on an inbound
approach (the inbound side of an arm's corridor, 15 m to each side, 25 m at an interchange, out to the zone's
`approach`: square layouts, the straight link up to just before the town entry, `FLOW_ZONE approach=`; else
r_measure) or within r at one sample, and not there at the next, has passed. Same completeness rule and stride
scaling as below. At 10 game s per sample every car is seen on its approach (no bias towards the slower twin); at 30 s
cars faster than approach / 30 s can be missed. The path count below is written as `thru_path=` (appended), and stops
for the run after `PATH_GIVE_UP` (2000) path elements no reader could read (`[SQST] FLOW_PATHOFF run= tries=`, once).
`FLOW_START` appends `thru_m=pos ix_corridor_m=50`; `FLOW_ZONE` appends `approach=<m|-> [test=<bench test>]`. Added 2026-10-13 (after the bench's
sheets 1-2): `FLOW_START ... path_thru=on|off` (off: the bench's record, no path reads, `thru_path=-`), `FLOW_ALL ...
frame_phase=<list|sets|scan|buslist|bus|towns>` (the phase of the sweep's busiest frame, `-` when none). The path
elements read in game as `elem.edgeId.entity` (docs/findings/lines-vehicles.md), and the two counts agreed within 1 %.

**Path count, now `thru_path` (2026-10-13; not run in game yet).** The engine exposes no traffic count per street, lane or node
(api/tealdef: no counter in BaseEdge, the street / transport systems or util; FLOW_TOWNS' town speed map is per town).
A sample snapshot can't count passes either: a car crosses a junction in a few seconds, samples are 10-60 s apart.
So the sampler reads each driver's own path (`MOVE_PATH.path.edges`, the EdgeIds it will drive, `dyn.pathPos.edgeIndex`
where it is): a zone's junction is its street edges whose middle lies within `thru_r` (40 m) of the centre, plus
their nodes within 45 m (`octree.findEntitiesInCircle`, once per run). A driver within `thru_track` (600 m) of a zone
(or one that had it ahead last time) is checked over at most `thru_window` (32) path edges ahead and behind its
position: a junction edge ahead -> "ahead"; none ahead but one behind (looked at only for drivers that had it ahead
last time) -> "passed". `thru` = the drivers the previous sample had ahead that this one finds passed (each car
counted once per pass). The track radius is `thru_track` = 20 m/s x the interval, 600-1200 m (10 / 30 s: 600, 60 s:
1200). Missed (an undercount, the same rule in every twin): (1) a car that starts its trip and passes between two
samples (trips here last minutes); (2) a car farther than the track radius or the path window from the junction
at one sample that passes before the next (a fast car with a long interval; the radius grows with the interval
for it); (3) a car that changes its route off the junction, or that is more than `thru_window` edges past it, or
gone, by the next sample. Under a lowered target (stride k > 1) the sampler reads the drivers whose entity id is a
multiple of k (the same subset every sweep at that stride), path reads included, and thru counts passes among them
x k (`thru_scale=k`; an estimate, the same rule in every twin); a stride change gives one `thru=-` sample. The target
comes back up only when the last sweep (that ran through, its path reads included) projects the raised one within
half the interval: its game time x drivers it would read / drivers it read (FLOW_TARGET `reason=recovered`,
`target=all` once every driver fits); review 2026-10-13: judged on time alone, the raise to every driver flapped
(the stride sweeps had skipped the path reads). The path window (32 edges each way) covers about 1200 m of town
streets (~37 m per path entry: an edge per lane segment plus the junction connections; link pieces are longer), so
the widest track radius, 1200 m at a 60 s interval, is about what it reaches. Assumes EdgeId.entity names the street
edge / node entity (unverified). **In game 2026-10-13 (session `2026-10-13_0356_top-up-779299`): every complete
sample wrote `thru=0`** (96 of them) while cars crossed: either the path element's pair layout (only `elem[1].entity`
was read) or the EdgeId entity is not the street edge / node id, or the junction's streets had new ids since the run
started (a lock pass). Now (2026-10-13 review): the junction's streets are re-read every sweep in their own phase
(`sets`, a few zones per frame within the budget, after the person list's frame), and include every street with an
end node within `thru_r` of the centre (the octree is asked 250 m farther out: arms that are single long edges have
their middle outside 40 m); with a stride only every stride-th person by id is read at all (`FLOW_ALL drivers=` is
then that subset's drivers x stride, `drivers_est=1`). And: the element is read as `elem[1].entity`, `elem.first.entity` or `elem.entity` (the one
that works is kept), the junction's streets are re-read every sweep, and the first 4 drivers near a zone per run
write one `[SQST] FLOW_PATHDBG run= driver= zone= n= cur= elems=<i>:<lua type>/<reader>/<entity>/<its components>,...
set=<the zone's ids>` line, so the next run shows what a path element is. Run 6 (session `2026-10-13_0447_top-up-726115`):
every element read as `userdata` and none of the three readers gave an entity (`elems=4:userdata/?/nil/-`), thru=0 in all
594 complete samples. Now seven readers (`[1].entity` first, the base game's documented way for `{EdgeId, boolean}`
lists from findPath; then `.first`, `.entity`, `.edgeId`, `.edge`, `[0]`, `.id`), `elems=<i>:<type>/r<k>/...` names the
reader that worked, and the line ends `elem0=` with a dump of the first element: `tostring=`, its metatable's
`__name` / `__index` type (and up to 16 `__index` keys when a table), and for keys 0, 1, 2, first, second, edgeId, edge,
entity, id, index, dir what each reads (type, and `.entity` / `.index` of a userdata or table). Cost in that session: a full sweep with
the path reads took 1105 frames / 2317 ms busy for 22.5k drivers (~100 us per driver; the stride-2 sweeps without
them 51 frames, ~9 us), so it overran its 30 s interval; the reads now stop at the first junction edge, look
behind only for drivers that had it ahead, and use one pcall per element once the reader is known. Cost: up to 32
path-edge reads per driver near a zone (64 for one that had it ahead), counted against the frame budget (the clock
after every such driver): offline with every one of 48k drivers near a junction, 218 frames instead of 57 per
sweep, no frame over 2 ms (test_flow.lua). `FLOW_TARGET reason=` is `skipped` (lowered) or `recovered` (raised).
tools/flow_report.py: `thru/min` per zone (sum thru / sum thru_s x 60), per pair (delta), and in the paired
comparison (W/L/T + sign test, every group including `all`).

### FLOW_ALL (one per sample, map-wide)

```
[SQST] FLOW_ALL run=2 s=5 gt=81520000 drivers=2410 sampled=2410 in_zones=310 standing=640 standing_pct=26.6 queue=301 v_mean=7.9 v_med=9.1 v_kmh=28.4 stand_mean=6.4 stand_max=95 persons=43120 pos_fail=0 frames=41 sweep_ms=48.3 elapsed_ms=690 capped=0 target=all stride=1 frame_ms_max=2
```

v3 adds `target` (the sweep's per-sweep target: `all`, or a number after a `FLOW_TARGET`), `stride` (every
stride-th driver read) and `frame_ms_max` (the sweep's busiest frame).

`drivers` found in the sweep (all of them, also past the target); `sampled` drivers read (v3: all, or every
`stride`-th up to `target`; v2: the first `cap` found);
`in_zones` sampled cars in at least one zone (a car counts once here, in each zone's FLOW); `standing` ...
`stand_max` as FLOW over every sampled car with a speed; `persons` the SIM_PERSON list length; `pos_fail` sampled
cars without a position (map-wide only); `frames` / `sweep_ms` frames and busy wall time of the sweep up to the
formatting (list, scan, bus lines, towns; not the writes); `elapsed_ms` wall time from the sweep's start to the
formatting; `capped` 1 when `sampled < drivers`.

### FLOW_TOWNS (at most every 60 s wall, in a sample)

```
[SQST] FLOW_TOWNS run=2 s=5 gt=81520000 scope=all towns=50 speed_mean=0.71 speed_min=0.32 levels=812,140,22,3 coef=1 ms=4.2
[SQST] FLOW_TOWNS run=2 s=5 gt=81520000 scope=town town=152233 name=Grid_S3 speed=0.64 levels=31,8,2,0
```

From `api.engine.util.town.computeTownsTrafficSpeedMap(1)` in its own frame (api/engine/util.d.tl:670; base
town_util.tl:345,459). `speed` its first value per town (**(P) 11e**: a 0..1 rating), `levels` its second value,
streets per congestion level (**(P) 11e**: order); `scope=all` sums `levels` and averages `speed`; then one
`scope=town` line per town, slowest first, at most 100. `ms` the call's cost: above 50 ms the next call waits
300 s instead of 60 s.

### FLOW_BUS (one per SQST Bus line per sample)

```
[SQST] FLOW_BUS run=2 s=5 gt=81520000 line=153001 name=SQST_Bus_3 twin=g3a pair=g3 ab=sl twin_from=session vehicles=4 stops=2 rt_n=3 rt_mean=212 rt_min=190 rt_max=240 lap_n=1 lap_mean=236 lap_min=236 lap_max=236 dep_age_max=95 freq=0.019 raw_last=81424000 raw_deps=81424000,81306000 raw_sections=104,108
```

Per vehicle of the line (TRANSPORT_VEHICLE, api/engine.d.tl:1482-1487). **(P)** lap rule and units: probe 11f was
not run in game; the units come from the Line Manager Plus probe (findings "Units": departures ms, sectionTimes s
without dwell), the raw values of the line's first vehicle are logged (`raw_last`, `raw_deps`, `raw_sections`) to
check them.
- `twin` / `pair` / `ab`: the twin the line serves: `twin_from=session` (the Showcase's route -> line map,
  stress_buslines `lineTwins`), `stops` (after a reload: the zone nearest the midpoint of the line's two stops, if
  closer than half their distance: the route's towns sit on opposite arms of its junction), `twin=-` none.
- `rt_*`: round trip = sum of `sectionTimes` (s, without dwell) when it has one entry per stop, all > 0 (`rt_n`
  such vehicles in this sample; the same trip is counted again in later samples until the next one replaces it).
- `lap_*`: completed laps since the previous sample: a vehicle's `lineStopDepartures[1]` (its last departure from
  the first stop) moved on; lap = new - old in game s (dwell included). Each lap is counted once. A departure that
  went back to 0 (history wiped, e.g. re-sent to its line) restarts the vehicle. One lap per sample at most (laps
  are minutes, samples <= 60 s).
- `dep_age_max` = max over vehicles of `gt - lastLineStopDeparture`, game s (a stuck bus grows it).
- `freq` = `util.line.getMaxFrequency(line)` (util.d.tl:206, unit **(P)**).

### FLOW_SUMMARY (every 10 samples, and when the run stops)

```
[SQST] FLOW_SUMMARY run=2 samples=40 gt0=81400000 gt1=82570000 wall_s=1210 zones=46 drivers_mean=2380 standing_frac=0.27 v_mean=7.8 v_kmh=28.1 capped=0 skipped=1 sweep_ms_mean=48.1 sweep_ms_max=61.2 frames_mean=40.5 warn=- final=1
```

`final` 1 when the run stopped (Off, an interval change, Clear queue, a new Showcase), else 0 (the periodic one;
the report keeps the last line of a run). `samples` sweeps logged; `gt0` / `gt1` first / last sample;
`wall_s` since the start; `drivers_mean` mean of FLOW_ALL `drivers`; `standing_frac` / `v_mean` pooled over every
sampled car of the run (sum of standing / sum of sampled cars, not a mean of per-sample means); `capped` samples
that hit the cap; `skipped` samples not started because a sweep was still running; `sweep_ms_*` / `frames_mean`
the sweeps' busy cost (no SQPERF in this mod: this is its perf record); `warn` count map: `keep_cleared` (samples
taken with Keep traffic cleared on), `unfinished` (stopped mid-sweep), `towns_failed`, `no_person_list`, `sweep_error` (a sweep dropped after
an error in one of its phases). v3 adds `frame_ms_max` (the run's busiest sweep frame) and `target` (the last
sample's target, `all` when never lowered).

### FLOW_TARGET (v3: when a sweep could not finish within its interval)

```
[SQST] FLOW_TARGET run=2 s=6 target=41250 was=all read=55000 drivers_prev=55000 reason=skipped
```

A sample came due while sweep `s` was still running (that sample is skipped): the run's target drops to `read`
(drivers this sweep had read by then) x 0.75, at least 3000; `was` the target before; `drivers_prev` the drivers of
the last finished sweep (the next stride). tools/flow_report.py lists it as a warning per load.

## `[SQST] <id> entry` (Lights showcase town entries, 2026-10-12; SHOWCASE.md "Town entries")

```
[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout at -6661,7361 node=55012 removed=3 from_junction=413m ms=120 [sqrb_arm_type=6 sqrb_arms=3 sqrb_lanes=2 sqrb_radius_size=2]
[SQST] lights_showcase entry Smart lanes 1 N kind=roundabout joined=3/3
[SQST] lights_showcase entry Game default 1 N kind=crossroads (roundabout refused by the check: Collision (hits 2 town buildings)) at -2796,7361
[SQST] lights_showcase entries roundabout=95 crossroads=1 broken=0 joins=285/285
```

One build line per town (`kind=roundabout` with the side-middle node it replaced, or `kind=crossroads (why)`: Roundabouts
& Interchanges not enabled, the grid node not as expected, the check or the build refused); a join line per built
roundabout (`joined=k/3`; fewer: broken, its set match=no reason=entry); one summary line after the run's summary.
tools/flow_report.py counts the kinds per load (Loads notes).

## `[SQST] showcase zone` (Showcase v2, stress_junctions readPlace; 2026-10-12)

One line per built Showcase placement, after its arms are read (after the build's settle), before its `built` line:

```
[SQST] showcase zone id=g3a pair=g3 ab=sl kind=roundabout type=Magic_Roundabout x=1200 y=-3400 r=167 r_from=measured towns=5 match=yes
[SQST] showcase zone id=g4b pair=g4 ab=game kind=plain type=Crossroads x=2900 y=-3400 r=95 r_from=measured towns=4 match=no reason=redrawn
```

| key | meaning |
|---|---|
| `id` | `g<set><twin>`: the group set (one draw) and its twin letter (`a`, `b`, `c`; Lights showcase also `d`), unique within the run |
| `pair` | `g<set>`: the twins of one set have identical junction, params, rotation and town sizes (compare them) |
| `ab` | the twin's A/B mode (stress_logic `SHOWCASE_AB`, one table): `sl` Smart Lanes lanes + current light behaviour, `game` game default lanes and lights (Smart Lanes leaves it alone: `[SQRL] ZONES` above), `sl_phases` Smart Lanes lanes + Smart Lanes light phases whatever the setting (only lit plain crossings), `sl_fan` (Lights showcase, `LIGHTS_AB`) Smart Lanes' full fan + split phases, `sl_lock` Smart Lanes lanes with the kerb turn never freed and the game's phases (Smart Lanes accepts it since 2026-10-12; the Lights showcase's twin once the Stress Test sends it). The Lights showcase writes the same `showcase zone` lines (kind `plain`) |
| `kind` | `interchange` / `roundabout` / `plain` (FLOW_ZONE `ix` / `rb` / `x`) |
| `type` | the construction type label, spaces as `_` |
| `x`,`y` | map position of the junction centre (m) |
| `r` | its measured reach (farthest new street node + 12 m), else the estimate (`r_from=est`) |
| `towns` | towns on its arms (a town skipped for want of land not counted) |
| `match` | `yes`: the twins of its set are still identical as built (compare them pairwise); `no`: leave the whole set out of pairwise A/B comparisons (each twin can still be read on its own). Set at the read, when every twin's build is known (stress_logic `showcaseMatch`) |
| `reason` | only with `match=no`, comma-separated: `redrawn` (the check refused a twin with "Construction Not Possible" and it was redrawn while a sibling kept the original draw, the redraws differ, or a redrawn twin was not built; every twin redrawn the same way and built still matches), `town` (a town of one of its twins failed the land check and was skipped: that arm is unlinked and its arm pair's bus line is dropped in every twin, but the twin's traffic still differs), `link` (an arm of one of its twins was left unlinked: its link refused every try, or no node of its own town to end on; known only after the links, so it comes on a `showcase zone_match` line), `entry` (Lights showcase: its twins' town entries differ: a roundabout in one twin, the crossroads in another, at the read; or a roundabout whose arms could not be read or not all three joined to its grid, after the links on a `zone_match` line) |

After the links, every built twin of a set with an unlinked arm (or a broken town entry) gets a late verdict (its zone line was written
before the links; `stress_logic.showcaseZoneMatchLine`):

```
[SQST] showcase zone_match id=g1b pair=g1 match=no reason=link
```

tools/flow_report.py applies it to the zone of that id in the current run (also when FLOW lines joined it already);
it never starts a new run. `reason` here is the set's full list (e.g. `town,link`).

The same list (from the layout, before the build; `r` the estimate) comes from `stress_logic.showcaseZones(layout,
cx, cy)`: the input for the Stress Test -> Smart Lanes channel and for step 4's `src=placement` zones. Not written
for a placement the check refused. That list has no `match` (the build decides it).

The `showcase summary` line counts `towns_skipped=` (towns left out for want of land) and `sets_mismatch=` (sets
logged `match=no`).
`tools/flow_report.py --ignore-reason REASON[,REASON]` (repeatable; `make flow ARGS='--ignore-reason entry'`) counts a
zone whose `match=no` reasons are all among those as matched, and the report's notes say so with the count. For a
known false alarm only: session `2026-10-13_0118_top-up-148916` (seed 148916) marked every set `reason=entry`
because an entry's lock miscounted its already-locked highway ring ("locked=4 of 8", fixed); its entries were all
built, read and joined.
A twin that was refused for another reason or whose build failed has no zone line at all: the report
must treat a `pair=` with fewer zone lines than its set's modes as unmatched and leave it out of pairwise
comparisons (pooled per-type numbers may still use the twins that exist).

## What the probes answer (TESTING.md 6M; results go to docs/findings.md)

| probe | lines (`[SQST] probe 11x ...`, then `[SQST-PROBE] flow_11x_<name> ok\|fail`) | decides |
|---|---|---|
| 11a MOVE_PATH | `movepath_read_us`, `path_edges`, `dyn_speed` + `standing(<0.5)`, `time_standing_of_standing`, `get_speed_us` + `getSpeed/dyn.speed`, `lane tn_read_us`, `lane speedLimit` + `curSpeed`, `speed/speedLimit`, 12 `sample` lines | read cost -> per-frame / per-sweep caps; dyn.speed unit (vs speedLimit, getSpeed); timeStanding meaning; whether lane `curSpeed` is a usable flow signal |
| 11b path entity | `current_kind`, `current_kind#lane`, `whole_path_kinds`, `transitions`, `sample` (non-street steps) | whether junction nodes are path steps (zone membership by node entity) |
| 11c moving query | per group `camera_edge` / `camera_node` / `driver_edge` / `driver_node`: shape, returned counts, drivers among them, `expectedFound`, `cost_us`, `no_tn` (entities without a TRANSPORT_NETWORK component, never queried: a missed native component lookup can assert) | per-zone query instead of the full driver sweep |
| 11d order | `component_types` (VEHICLE_ORDER?), `state`, `blocked`, `speed_x_blocked`, `land_vehicle` | waiting-at-light signal; meaning of `blocked` |
| 11e towns | per town `town=.. speed=.. levels=..`, per coef `us towns speed levelsLen` | FLOW_TOWNS cost, `levels` shape |
| 11f bus | `game_time` (+ maxFrequency), `t0` / `t1` per vehicle, final `gameTime delta per wall s` | gt unit; sectionTimes / departure units; FLOW_BUS fields |
| 11g placements | per construction `file owner frozenNodes frozenEdges`, `street_edges` / `street_nodes` owner+construction | zone fallback after reload (`src=construction` vs `cluster`); PLAYER_OWNED scan scope for the toggle |
| 11h position | `octree` cost, `getPosition_us` (+ zero, `notDriving`: sampled persons no longer driving, skipped), `calcPathPosData_us`, `path_node_fallback_us`, distance, line vehicles | position-based zone membership vs path-entity membership |
