Status: done 2026-10-11 (run 1 analysed in PROBE_RESULTS.md; Balance dropped, PLAN.md D8). Log: ../probe_run1.log.

# Balance probe (mods/square_lmp_probe)

DEV ONLY, never upload. Phase 6 of `PLAN.md`: answers the three probe questions of "5. Balance vehicles" before
Option A is built. The answers go into `docs/findings.md`.

**Snap only reads. The Send buttons change the game** (one `makeVehicleSetLineCmd` per click, vanilla vehicle state
only, nothing from the mod persists), so use a throwaway save.

## What it does

An **LMPP** button left of A+ in the Line Manager line toolbar (mounted like the RM probe: wrapped
`makeIconToggleButton` + `makeLineActionDescriptor`, doReplace order 260, after Line Manager Plus at 250). Click LMPP
to show or hide the actions and a short status text. Everything logs `[LMPProbe] ...` lines to stdout.txt.

| Button | Changes the game? | What it does | Log lines |
|---|---|---|---|
| **Snap** | no | Starts a 60 s sampler on the selected line. Every 10 s a full snapshot: game time, stop count, line-average `sectionTimes`, round trip T, headway H = T/n, vehicles ordered by progress, and per vehicle: state, loadState, stopIndex, last departed stop (from `lineStopDepartures` and from `stopIndex`), time since that departure, progress, gap ahead (and gap/H), `timeUntilDeparture`, `timeUntilNextScheduledDeparture`, `autoDeparture`, raw `lineStopDepartures` / departure differences / `sectionTimes` / `visitedStops`, cargo on board per cargo type, position, speed. Then the Option A plan preview (most bunched vehicle, target stop). Every 1 s in between: each vehicle whose state/loadState/stopIndex changed (`CHANGED from ...`) and every vehicle in `WaitForScheduledDeparture` (`WAIT`) | `==== snapshot` ... `==== end snapshot`, `t=+Ns CHANGED`, `t=+Ns WAIT` |
| **Send:plan** | **yes** | Snapshot, then re-sends the **most bunched vehicle** (smallest gap ahead) to the stop in the middle of the largest gap (Option A's choice), same line | `SEND plan`, `track ...`, `after-send` snapshot |
| **Send:back** | **yes** | Same vehicle, sent to the stop **before** its current stop index: does it turn around? | `SEND back`, `track ...` |
| **Send:same** | **yes** | Same vehicle, sent to its **current** stop index: no-op, or does it reset/unload? | `SEND same`, `track ...` |

After a Send: the command callback (`success=`), then the vehicle every 2 s for 60 s (line, state, loadState,
stopIndex, cargo on board, position, speed, distance moved, distance from its start and to the target station), then a
full `after-send` snapshot of the line.

The samplers run in the button row's step callback, so **keep the Line Manager open on that line** while they run
(closing it pauses them; the next click restarts them). Game speed 1x, **unpaused** (game time must advance).

## Run

1. `make link` (done). Start the game, enable **DEV Line Manager Plus Probe** (and Line Manager Plus, to check that
   both rows mount). Load a **throwaway save**.
2. In a terminal, follow the log:
   `tail -f ~/Library/Application\ Support/Steam/userdata/65263351/3493540/local/crash_dump/stdout.txt | grep --line-buffered LMPProbe`
   Expect `loaded` and `installed (order 260)`.
3. Open the Line Manager. Expect `captured commonParams` and `mounted row left of A+`. Click **LMPP**.
4. **Line A, a bunched bus line** (3+ buses, two or more driving nose to tail):
   - Click **Snap**, wait the full 60 s (`snap end`).
   - Click **Send:plan**, wait 60 s (`track end`, then the `after-send` snapshot). Watch the bus in game: does it
     turn around, drive on, skip stops? Do its passengers stay on board (vehicle window)?
   - Click **Send:back**, wait 60 s. Then **Send:same**, wait 60 s.
5. **Line B, a train line** (2+ trains): **Snap** (60 s), then **Send:plan** (60 s). Note whether the train turns
   (reversible trains) or drives the whole loop.
6. **Line C, a cargo line with loaded vehicles** (trucks or a train carrying goods between stations): click **Snap**
   while at least one vehicle is driving loaded (60 s), then **Send:plan** on it (60 s). Check in the vehicle window
   whether the cargo is still on board after the command.
7. Optional: a line where you have seen "Ensuring safe distance" in a vehicle window: **Snap** and wait for `WAIT`
   lines.

Quit or reload afterwards; the save is throwaway.

## What to paste back

All `[LMPProbe]` lines of the run (one file is easiest; `plans/**/*.log` is gitignored):

`grep LMPProbe ~/Library/Application\ Support/Steam/userdata/65263351/3493540/local/crash_dump/stdout.txt > plans/square_line_manager_plus/probe_run1.log`

(That is the live log `tools/perf_report.py` reads: `<TF3_USERDATA>/crash_dump/stdout.txt`.) Plus, per Send: what
you saw in game (turned around? skipped stops? cargo kept?), the line types used, and any `ERROR` lines, Lua errors
or crashes.

## What each answer decides for Option A

| Question | Log evidence | Decision |
|---|---|---|
| **Q1** re-send to the same line accepted? | `SEND ... callback success=` | `false` or `line=-1` afterwards: Option A is dropped (feature 5 not built) |
| Q1 cargo kept? | `cargo[...]` in `SEND` vs `track callback` / later `track` lines | Dropped: only re-send **empty** vehicles (or those at a terminal after unloading), and the tooltip warns. Kept: any vehicle |
| Q1 route? | `Send:back` `fromStart`/`toTargetStation` and `stopIndex` over time; your observation | Turns around or takes a shortcut: allowed targets limited to stops **ahead**. Drives the whole loop: Option A only picks stops ahead anyway, but a "back" target is never used |
| Q1 `Send:same` | `track` lines | Unload/reset on a no-op: never re-send a vehicle to its current stop |
| **Q2** engine's own spacing | `WAIT` lines: `tUntilSched`, gap/H of that vehicle | If the engine already holds vehicles closer than some gap: Balance targets must respect it (and Balance may be less needed). `tUntilSched` counting down from a value near H: the engine spaces by line frequency |
| **Q3** consistency | `lastDep(byDep/byIdx)` agree; `depDiffs(s)` ≈ `sectionTimes` (+ dwell) and which index they line up with; `since` grows 10 s per 10 s snapshot at 1x (confirms the ms unit); `order by progress` stable between snapshots; `T(s)` ≈ the line's frequency × n | All yes: the planner uses line-average sectionTimes + departures as in PLAN. Index off by one: fix the section mapping in `balance_core`. Units differ: fix `DEP_UNITS_PER_SEC`. `sectionTimes` empty/zero on new lines: Balance needs every section measured (`sectionsComplete=true`) and is disabled otherwise |
