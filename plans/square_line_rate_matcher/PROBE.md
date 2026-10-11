# Line Rate Matcher probe (mods/square_line_rate_matcher_probe)

DEV ONLY, never upload. **It changes the game:** "+1" buys a vehicle and "-1" sells one, so use a test save.
Phase 0 of `PLAN.md`. The answers go into `docs/findings.md`.

## What it does

An **RM** button left of A+ in the Line Manager line toolbar. It is mounted the same way Line Revert mounts its
buttons (wrapped `button_react_util.makeIconToggleButton` + `line_util.makeLineActionDescriptor`, doReplace
order 250, after Line Revert's 200, so Line Revert's buttons stay). Click RM to show or hide the action buttons and
a short status text:

| Button | Action | Log lines |
|---|---|---|
| **Rep** | Report: line, name, Rate, vehicle count, Capacity/Utilization/Frequency (as `stli_core.lua`), each vehicle (state, line, depot, sellOnArrival, purchaseTime, model ids, per-cargo capacity, protected), game time. Then the supply walk: each stop's loaded cargo, other lines at the same station group (with their Rate), each reachable producer's output cargo with `getCargoProducedPerYear`, `getCargoMaxProductionPerYear`, `STOCK_LIST.cargoData[c].produceFrequency` and `industry_util.getIndustryProductionData` | `==== report` ... `==== end report` |
| **+1** | Clones the first line vehicle like vanilla's Clone (config copy, purchaseTime/maintenance reset, autoLoad all, mission hooks), depot from `findBestLineAndDepotForVehicle` (fallbacks `line_util.getBestDepotForLine`, a line vehicle's depot), `makeVehicleBuyCmd`, then in the callback `makeVehicleSetLineCmd(new, selectedLine, 0)` | `clone: ...` |
| **-1** | `makeVehicleSendToDepotCmd(v, true)` for the line vehicle with the latest purchaseTime (skips protected and already-selling vehicles) | `sell: ...` |
| **Smp** | Only starts the sampler | `sample ...` |

Every button also starts the **sampler**: for 2 minutes of real time it reads Rate and the vehicle states once a
second and logs a `sample` line every 5 s and whenever Rate, vehicle count or states change (marked `CHANGED`).
It runs in the button row's step callback, so **keep the Line Manager open on that line** while it samples
(closing it or picking another line stops the samples; the next click restarts them).

## Run

1. `make link` (done; the mod is linked). Start the game, load a **test save** with a cargo line that has 2+
   vehicles (ideally the logging camp ship line from PLAN.md, or a truck line from a raw producer).
   Enable **DEV Line Rate Matcher Probe** (Line Editor Undo on as well, to test coexistence).
2. In a terminal, follow the log:
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered RMPROBE`
   Expect `loaded` and `installed (order 250)` at GUI start.
3. Open the Line Manager, select the cargo line. Expect `captured commonParams` and `mounted row left of A+`.
   **Look:** is RM left of A+, and are Line Editor Undo's undo/redo buttons still there (order: RM, undo, redo, A+)?
   Click **RM**: Rep/+1/-1/Smp and a status text appear. Does the toolbar overflow or squash anything? Screenshot.
4. Game speed 1x, unpaused. Click **Rep**. Wait for the samples (2 min, or click again to restart).
   Note the Rate shown in the Line Manager footer and compare it with `rate=` in the log.
5. Click **+1**. Watch `clone:` lines: `findBestLineAndDepotForVehicle -> line X depot Y | selected line Z`,
   `buy callback success=...`, `setLine callback ... vehicle.line=... (selected ...)`. Check the vehicle list in the
   game: did the new vehicle land on this line? Let the sampler run the full 2 minutes; note when `n=` and `rate=`
   change (the `t=+...s` of the first `CHANGED` line with the higher Rate).
6. Click **+1** once or twice more (wait for each sampler to show the new Rate), so we have Rate at n, n+1, n+2.
7. Click **-1**. Watch `sell:` lines and the samples: does Rate drop as soon as the vehicle heads to the depot
   (`GOING_TO_DEPOT(sell)` in states), or only when it is sold (n drops)?
8. Optional: in the game, send one line vehicle to the depot by hand **without selling**, then click **Smp**:
   does an `IN_DEPOT` vehicle still count in `n=` and in Rate? Also try a line whose vehicles are stopped.
9. Optional: a line where `findBestLineAndDepotForVehicle` returns another line (`(DIFFERENT)` in step 5), if one
   exists: does SetLine still move the clone onto the selected line?

Pause or quit afterwards; the bought vehicles stay in the save.

## What to paste back

All `[RMPROBE]` lines of the run (one file is easiest):

`grep RMPROBE ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt > plans/square_line_rate_matcher/probe_run1.log`

(`plans/**/*.log` is gitignored.) Plus: the Rate the
footer showed at each step, a screenshot of the toolbar, and any `ERROR` lines, Lua errors or crashes.

## Questions each step answers

| Question | Where in the log |
|---|---|
| Is Rate linear in the vehicle count? (`perVehicle = Rate / n` in PLAN.md) | `sample` lines: settled `rate=` at n, n+1, n+2, n+1 (steps 4-7) |
| Do vehicles in the depot or on their way to it count? | `states=[...]` vs `n=` vs `rate=` in steps 7-8 (`GOING_TO_DEPOT(sell)`, `IN_DEPOT`) |
| How long before a clone shows up in Rate? | `t=+...s` of the first `CHANGED` sample after `clone: setLine callback` (step 5); `gameTime=` gives the game-time delay |
| Does buy + SetLine put the clone on the selected line? | `setLine callback success=true ... vehicle.line=<selected>`, and the vanilla line list |
| What does vanilla's depot search return? | `findBestLineAndDepotForVehicle -> line ... depot ...` and `(same)` / `(DIFFERENT)` |
| Is the button visible next to A+ and does it work with Line Revert? | step 3 look + screenshot; Line Revert's undo/redo still work |
| Does Rate match the footer? Does it react to Capacity/Frequency? | `report` line `rate= capacity= utilization= frequencySec=` vs the footer |
| Which production number is the target? | `producer ...` lines: `producedPerYear`, `maxPerYear`, `produceFrequency`, `industryUtil(...)={actual total}` vs the industry window |
| Do the per-vehicle capacities read correctly? | `vehicle ... capacities(index-1=cargo)=[...]` vs the vehicle window |
| Other lines at the producer's station | `other line stops at group:` lists them with their Rate |

## Results

(none yet)
