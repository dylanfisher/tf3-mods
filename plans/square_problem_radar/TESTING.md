# Problem Radar: in-game test checklist

One ordered checklist for the finished mod (phases 1-5, the phase 6 review fixes and the phase 7 Economy tab, §11). This file is not shipped (it lives in `plans/`). Work top to bottom; later sections assume the earlier ones passed. Use a **copy** of a save for anything that isn't a new free game.

**Already verified in game (2026-10-05):** the phase 1 UI (the ridge button renders, the window opens, tabs and the HUD-mode toggle work and persist) and adding the mod to an existing save. Everything else below is still open.

Report back every `[ProblemRadar]` log line, especially `… failed (further failures not logged)` and `… failed N times in a row; its alerts were removed`.

## 1. Setup and log tail

1. Run `make link`, then tick **Problem Radar** in the mod list.
2. Turn on debug mode for the console and **Simulation options** up to 32× (`docs/wiki/modding/tools/ingame.md`, "Console", line 68). At 32×, 5 game-minutes take about 10 s.
3. Keep the log open in a terminal:
   ```sh
   tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered -i "ProblemRadar\|square_problem_radar\|error"
   ```

Console helpers used below (debug console):

```lua
-- the radar state
local e = api.engine.system.gameScriptSystem.getEntityForGameScript("square_problem_radar::/radar/radar.gs")
local s = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT).state
print(s.version, s.total, #s.alerts) for k, n in pairs(s.kindCounts) do print(k, n) end
for k, v in pairs(s.settings) do print(k, v) end for k, l in pairs(s.settings.notify) do print("level", k, l) end
local n = 0 for _ in pairs(s.memory.stoppedSince) do n = n + 1 end print("standing timers", n)
for b, t in pairs(s.memory.blockedSince) do print("blocked", b, "by", s.memory.blockedBy[b], "since", t) end
for _, k in ipairs({ "overloadSince", "underusedSince", "bunchingSince" }) do for l, t in pairs(s.memory[k]) do print(k, l, t) end end
for id, t in pairs(s.notified) do print("notified", id, t) end for id, t in pairs(s.notifyCleared) do print("cooldown", id, t) end
-- phase 7: utilisation averages (line, basis points, tracking start, last sample) and tier counts
for l, u in pairs(s.memory.useAvg or {}) do print("useAvg", l, u[1], u[2], u[3]) end print("tiers", table.concat(s.tierCounts or {}, " "))

-- what the game itself reports (compare with the radar)
print(#api.engine.util.line.getLineProblems(), #api.engine.util.vehicle.getVehicleProblems(), #api.engine.system.transportVehicleSystem.getNoPathVehicles())
for l, issues in pairs(api.engine.util.line.getLinesIssues(api.engine.util.getPlayer(), false)) do print(l, #issues) end
print(#api.engine.util.line.getLineStationProblems())

-- shrink thresholds for testing (integers only)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.setSetting",
  { stuckMinRoad = 1, stuckMinTram = 1, stuckMinRail = 1, stuckMinWater = 1, stuckMinAir = 1, idleDepotDays = 1,
    lineSustainMin = 1, lineOverloadFactor = 1, lineUnderusedPct = 30, lineClumpPct = 40, lineGapPct = 150 }))
-- everything back to the defaults (HUD mode included)
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.resetSettings", {}))
-- notify levels / pause from the console
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.setSetting", { notify = { fleet_worn = "notify" } }))
api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.setSetting", { notifyPaused = true }))
```

## 2. Smoke test

- [ ] **New free game:** the log shows `[ProblemRadar] state initialised (initNewGame)` (or `(update)`) **once**. A `Radar ● 0` button with a **green** dot sits in the top-left ridge. Report if the `●` glyph renders as a box.
- [ ] Nothing in the ridge is clipped. Other mods' ridge buttons sit beside it unchanged.
- [ ] The window opens **centred** (slightly above the middle, like Finances), can be moved and closed, and clicking the button again never opens a second one. All 7 row columns fit at 1080p.
- [ ] Tabs read `All (0) · Vehicles (0) · Lines (0) · Stations (0) · Fleet (0) · Economy (0) · Settings`. Each alert tab says "No problems detected". The selected tab stays selected while the window refreshes.
- [ ] **Compact panel:** Settings → HUD mode **Compact panel** logs `settings: hudMode=compact`; the ridge shows `Radar ● 0 crit · 0 warn · 0 info [Open]` within about 1 s. Back to **Badge** works.
- [ ] **Map editor:** no radar button and no `[ProblemRadar]` lines.
- [ ] Console validation: both are ignored with `ignored unknown setting keys/values: …` and no change:
  ```lua
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.setSetting", { hudMode = "huge", foo = 1 }))
  api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "ProblemRadar", "ProblemRadar.setSetting", "compact"))
  ```

## 3. Alert kinds and how to provoke them

Each row should appear about **30 game seconds** after the game's own verdict (or its threshold): the default smoothing window (`smoothSec`, see "Smoothing" at the end of this section). Game seconds pass faster at higher sim speeds. To check a kind quickly, set **Smoothing** to 0 in Settings first; then rows appear within about 3 s, as before. Row format: tier · kind · type · entity · context · detail · metric; hovering shows detail + metric as a tooltip.

**Vehicles**
- [ ] `veh_blocked` (Critical): two trains facing each other on a single track without a passing loop. Once the game says "Trains Are Blocking Each Other", **one** row `Blocked · Train · <A> · <line> · Blocking each other with <B>`, with a `→` button that jumps to B. No `Waiting` row for them.
- [ ] `veh_nopath` (Critical): an electric train on track without catenary → `No path · Train · … No Electrified Path…` (+ `: Missing electric tracks.` when the game gives a reason). A ship between unconnected waters → `No path · Ship …` and/or a `Line broken` row; report which. Click: camera to the failure position (if a reason is shown), else to the vehicle.
- [ ] `veh_stuck` (Critical): `stuckMinRoad = 1`, gridlock trucks on a tiny roundabout (or block a road ahead of a bus). `Stuck · Bus/Truck · <vehicle> · <line> · Standing 1m, next stop <stop>`; the minutes count up, and the row is there before the base "Vehicle Stuck" (5 min).
  - Must **not** show: buses queueing in front of a full stop (`approachingStation`), a bus stopped with its stop button (user-stopped), a vehicle already in `veh_nopath`.
  - Ships: `stuckMinWater = 1`, block a ship mid-water → `Stuck · Ship`. Ships queueing outside a single-berth harbour must **not** show (run the MOVE_PATH helper in §10 on a waiting ship). Same for aircraft at a runway if you can provoke it.
- [ ] `train_blocked_by` (Warning): a train waiting behind another train for longer than the rail threshold. `Waiting · Train · <A> · <line> · Waiting behind <B> · 1m`; `→` jumps to B. **Chain:** three trains behind a user-stopped front train give **one** row with metric `Nm +2`. A train "Waiting for Free Path" with no blocker pair shows `Waiting for Free Path, next stop <stop>` with no `→`. Normal signal waits never show at the default 5 min.

**Lines**
- [ ] `line_broken` (Critical): bulldoze a segment of a running line → `Line broken · Line · <line> · Could Not Connect Stations`. Click: camera to the **break position**. Missing catenary → `: Missing catenaries`. A one-stop line → `Line Contains Too Few Stations` (no `No vehicles` row).
- [ ] `line_no_vehicles` (Critical): a valid 2+ stop line without vehicles → `No vehicles on this line (2 stops)`. Assigning a vehicle removes it.
- [ ] `line_cargo_issue` (Warning): a truck line with nowhere to unload, or a passenger bus on a cargo line → `Cargo issue …`, `+N` when there are several. **Phase 6:** a cargo line with **no vehicles** shows only `No vehicles`, not also "No vehicle can transport the configured cargo".
- [ ] `line_cargo_not_unloaded` (Warning, passive): a truck line carrying a cargo that no stop on the line accepts (e.g. a two-stop line where the drop-off has no consumer for it but the line still loads it), run until a truck completes a full round trip still loaded → **one** `Not unloaded · Line · <line> · N cargo of K vehicles rode a full round trip without being unloaded · K veh · N` row per line, even with several affected trucks; N and K match the base "Cargo Unload Problem" HUD icons / the line manager's problem vehicles. Click opens the line. Fixing the destination clears it once the vehicles unload. With the level set to Notify in Settings a toast appears. Loading an older save made with this mod shows the kind in Settings at `Passive`.
- [ ] `line_overloaded` (Warning): one small bus between two dense towns. With `lineSustainMin = 1, lineOverloadFactor = 1`: `Over capacity · … Stop N '<stop>': W waiting, ~F× capacity per trip`. W should match the station window's waiting count for that line, N the stop number in the line window.
- [ ] `line_underused` (Info): 10 buses on a tiny village line → `10 vehicles running mostly empty (N% used)`; N ≈ the line window's Utilization. A single empty vehicle never shows.
- [ ] `line_bunching` (Warning): buy 4 vehicles at once from one depot onto a line → after one round trip `K of N within m:ss · target m:ss` (target = the line window's Frequency). Stopping two adjacent vehicles of a 5-vehicle line → `Gap m:ss vs target m:ss`. Lines with < 3 running vehicles or a **full-load** stop never show it. Report how long a fresh clump takes to dissolve on its own.

**Stations**
- [ ] `station_overcrowded` (Warning): one slow bus on a long line through a dense centre, until the game says "Station Overcrowded" → `Overcrowded … <used>/<capacity>`.
- [ ] `station_useless` (Info): a truck line stopping at a passenger-only stop → `Stop unusable · Station · <station> · <line> · …`.

**Fleet**
- [ ] `fleet_worn` (Info): condition ≤ 20 % → `Worn · … · 18%`; it clears above 30 %.
- [ ] `fleet_old` (Info): a vehicle past its model lifespan → `Age 23/20 y, past its lifespan · 115%`, within about 20 s. Renewing it removes the row within about 20 s. Report if the years differ from the vehicle window (non-default calendar speed).
- [ ] `fleet_idle_depot` (Info): `idleDepotDays = 1`, leave a bought vehicle in its depot → `In depot for N days · Nd`. Assigning it removes the row.

**Window with data**
- [ ] **All** is sorted Critical → Warning → Info, oldest first; long-standing rows don't move when others appear. Tab counts and the compact panel counts match.
- [ ] **Pause** the game and break a line: with Smoothing = 0 the row appears while paused within about 12 s (phase 6: paused slots are 45 frames apart). With the default 30 s it appears only after you unpause, about 30 game seconds later, because game time stands still while paused (expected).

**Smoothing (`smoothSec`, default 30 game seconds)**
- [ ] **No flicker:** an overcrowded station whose waiting count hovers at its capacity (the game's overflow flag toggles). Before smoothing, `Overcrowded` came and went several times within seconds. Now it shows once, about 30 game seconds after it first overflows, stays while the flag toggles, and leaves only after about 30 game seconds of not overflowing. The ridge count and the tab counts don't jump either.
- [ ] A one-off blip (e.g. a bus briefly blocked at a junction that clears within a few seconds, at Smoothing 30 and `stuckMinRoad = 1`) never shows a row and never toasts.
- [ ] A toast (e.g. `veh_stuck` at Notify) never comes before its row: when the toast pops, the row is already in the list.
- [ ] **Off is instant:** Settings → **Smoothing** = 0 (logs `settings: smoothSec=0`): new problems are listed within about 3 s and cleared rows go on the next scan, as before smoothing. Set it back to 30 and check the overcrowded station again.
- [ ] Setting a kind to **Off** still removes its rows at once (no 30 s linger).
- [ ] **Existing save:** load a save that already had this mod (made before smoothing). Its listed rows are still there right after loading (they don't vanish for 30 s). Settings shows Smoothing = 30.
- [ ] **Adding the mod** to a save that never had it: the problems already there are listed on the first scan cycle (about 2.4 s), not after 30 s, and don't toast.

## 4. Row and toast clicks

- [ ] Every row click moves the camera to the entity (or to the break / failure position) and opens the game's own window for it.
- [ ] Clicking a row of an entity deleted since does nothing and logs no error.
- [ ] **Reused id (phase 6):** with the window open, sell a vehicle that has a row, buy a new vehicle right away (it may get the same id), and click the old row before the next scan removes it: the new vehicle's window must **not** open.
- [ ] Toast click (popup or log entry) does the same as the row click. A toast for a vehicle sold since: nothing happens, no error. The summary toast isn't clickable.

## 5. Settings and persistence

- [ ] Layout: left column General (HUD mode, Pause) + the alerts table (15 rows: label, coloured severity, Off / List / Notify); right column a **General** group with "Smoothing: problems must persist / linger (game seconds)" (`0-600 s (default 30)`), then the thresholds with spin boxes, ranges, the mute hint and **Reset to defaults**. Nothing clipped; the tab scrolls. Phase 6 narrowed the window's spacing rule to our own layouts: check the spin boxes' −/+ buttons and the Off/List/Notify buttons look like the base game's.
- [ ] Each control logs one `[ProblemRadar] settings: <key>=<value>` with only that key.
- [ ] Setting a kind to **Off** removes its rows within about 2.4 s; turning it back on starts its timers fresh.
- [ ] `Worn: condition at or below` = 40 → more Worn rows; a worn row stays until above 50 %.
- [ ] **Persistence:** change the HUD mode, pause, three notify levels and three thresholds; save, quit to menu, load: all kept. Timers survive too: let a vehicle stand half its threshold, save, reload; it alerts after the **remaining** time.
- [ ] **Reset to defaults** logs `settings reset: …`; pressing it again logs nothing.

## 6. Notifications and the budget

Defaults: **Notify** for Stuck and No vehicles (No vehicles waits 2 game-minutes); **List** for the rest.

- [ ] A stuck vehicle gives **one** toast `Stuck: <vehicle>` / `Standing Nm, next stop <stop> (<line>)` with the stuck icon; the log shows `notified 1`. No second toast while it stays stuck. Stuck again within 10 game-minutes of clearing: no toast; after more than 10: a new toast.
- [ ] **Budget (phase 6):** make 10+ vehicles stuck at once (block a busy road). Within any 2 game-minutes you get at most **3** toasts plus **one** `Problem Radar: +N more new problems` summary; further new problems in the same 2 minutes arrive as the **next** summary after the window ends. The base game's own notifications in the log are not pushed out (the base keeps 100 history entries).
- [ ] **No burst on switch (phase 6):** on a save with many worn vehicles, set **Worn** to Notify: no toasts for the vehicles already listed; only vehicles that become worn afterwards toast. Same when switching a kind from Off to Notify.
- [ ] **Pause** all radar notifications: no toasts; untick: only problems that appear afterwards toast.
- [ ] **Game filter:** notification log → settings → untick **Problem Radar** (under Problem): radar toasts stop, base ones don't.

## 7. Performance on a large save

Use your biggest save (note vehicle, line and station counts in the report).

- [ ] At 1× and at max speed: no stutter every ~0.6 s (one scan group runs every 3 sim updates) or every 2.4 s (a full cycle). If there is, report which: the vehicles and fleet groups are the heavy ones.
- [ ] **Window closed vs open:** watch the frame rate (debug FPS overlay) with the window closed, then open on **All**, then on **Settings**. Phase 6 renders only the selected tab and at most 100 rows; there should be no visible drop when it refreshes once per second. Report the FPS of each case.
- [ ] With 100+ problems, the list ends with `+N more (not listed)` and the tab count still includes them.
- [ ] The badge/compact panel alone (window closed) should cost nothing noticeable (phase 6: it reads only the per-kind counts).
- [ ] **Window idle:** with the window open on a tab with rows and nothing changing (game paused, smoothing holding), the rows must not flicker or lose hover/scroll position every second (perf review: an unchanged poll no longer re-renders).
- [ ] **Save churn:** stuck timers in `memory.stoppedSince` are only those ≥ 30 s (`for v, t in pairs(s.memory.stoppedSince) do ... end` all older than 30 s of game time); the younger ones are in `s.rt.young.stopped` (PERF_VMS fix: shared by every simulation Lua state, so the state is rewritten on vehicles passes where young timers come or go; quietly, the window does not re-read). Save, reload: a vehicle standing ~1-2 min still gets its `veh_stuck` row on time.
- [ ] **Economy scans (Phase 7):** in a save ≥ 1 game year old, compare the 2.4 s stutter check with *Losing money* and *Low use* on (List) and both **Off**: no visible difference. Expected cost: one `calculateBalance` per profitable line and game month, 7 per losing line, at most 4 lines per 2.4 s pass.
- [ ] Standing timers stay ≤ 500; the save grows by a few KB at most. Pending (smoothing) entries stay ≤ 200: `print(s.pending and #s.pending or 0)` in the console.

## 8. Existing save: add and remove (on a copy)

- [x] Adding to an existing save works (verified 2026-10-05).
- [ ] **No toast burst on first add (phase 6):** add the mod to a copy of a save with existing stuck vehicles / lines without vehicles. After loading, no toasts for the problems already there; only new ones toast later.
- [ ] Play a few minutes: money, vehicles and lines behave as without the mod.
- [x] Save the copy, **remove** Problem Radar, reload (2026-10-07): the save loads (`Removing entity … radar.gs`, info only), but opening the notification log throws "Resource not found … radar_notification.script@useDataState" (`notification_log.tl:31`, `util.useFn` has no fallback). Old radar entries stay in the base notification history (≤ 100) until they roll off, so `severityRemove` must stay `Warning`.

## 9. Achievements

- [ ] With only Problem Radar (plus base) active, the new-game / load screen still says achievements can be earned (`cosmetic: true`). If it warns, report it.

## 10. Only verifiable in game: API questions

Each item has a helper to paste into the console. A failure in the radar shows as a `[ProblemRadar] … failed` warning; phase 6 keeps the previous rows for that part and drops them after 10 failures in a row.

- [ ] **Sim-thread availability.** No `scan '…' failed`, `stuck scan failed`, `line-quality scan failed` or `getVehiclesWithState unavailable` warnings during a 10-minute session. The console runs on the GUI thread, so it proves the shapes, not sim availability:
  ```lua
  print(#api.engine.system.landVehicleMoveSystem.getBlockedTrains())
  for _, p in ipairs(api.engine.system.landVehicleMoveSystem.getBlockedTrains()) do print(p[1], "blocked by", p[2]) end
  print(#api.engine.system.transportVehicleSystem.getVehiclesWithState(api.type.enum.TransportVehicleState.EN_ROUTE))
  local v = <trainId> print(api.engine.util.vehicle.getSpeed(v), api.engine.system.landVehicleMoveSystem.isTrainWaitingForFreePath(v))
  local line = <lineId> print(api.engine.util.line.getMaxFrequency(line))
  for idx, u in pairs(api.engine.util.line.getLineCapacityUsages(line, false)) do print("cargo", idx - 1, u.used, u.capacity) end
  print(api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntitiesCount(line, 0, 0))
  local f = api.engine.util.line.getFailedPathReason(<noPathVehicleId>, <itsLineId>) print(f and f.reason, f and f.pos)
  print(api.type.Line.LoadMode.FULL_LOAD_ANY, api.type.Line.LoadMode.FULL_LOAD_ALL) -- expect 1 2
  ```
- [ ] **Empty tables after save/load.** Save and reload a game where `notified`, `notifyCleared` and some timer maps are empty. The log must show `state initialised` at most **once** after the load, not on every scan. If it repeats, empty tables don't round-trip:
  ```lua
  print(type(s.notified), type(s.notifyCleared), type(s.alerts), type(s.memory), type(s.memory and s.memory.stoppedSince))
  ```
- [ ] **Field-level state reads (phase 6 GUI).** The HUD and window read single fields through `state_native`; check it works (the badge count matches `s.total`):
  ```lua
  local gs = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
  print(gs.state_native ~= nil, gs.state_native:find("total"), type(gs.state_native:find("kindCounts")))
  ```
- [ ] **Notification history after removal:** see §8 (remove on a copy that has radar toasts in its log).
- [ ] **Cargo waiting counts:** on a truck line from a busy industry, does `getLineStopSimEntitiesCount(line, stop, cargoTypeId)` count waiting cargo (the doc says SimPersons)? Compare with the station window:
  ```lua
  local comp = api.engine.getComponent(line, api.type.ComponentType.LINE)
  for i, stop in ipairs(comp.stops) do print("stop", i, api.engine.util.getEntityName(stop.stationGroup), "loadMode", stop.loadMode,
    "waiting", api.engine.system.simEntityAtTerminalSystem.getLineStopSimEntitiesCount(line, i - 1, <cargoTypeId>)) end
  ```
- [ ] **`lineStopDepartures` units:** values should be game-time **ms** close to `now` (within interval × vehicles × 1000), one entry per stop; `1 / maxFrequency` should match the line window's Frequency in seconds:
  ```lua
  local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
  local f = api.engine.util.line.getMaxFrequency(line) print("now", now, "interval s", f > 0 and 1 / f or 0)
  for _, v in ipairs(api.engine.system.transportVehicleSystem.getLineVehicles(line)) do
    local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
    local d = {} for i, t in ipairs(tv.lineStopDepartures) do d[i] = t end
    print(v, "state", tv.state, "autoDeparture", tv.autoDeparture, "loadState", tv.loadState, "departures", table.concat(d, ","))
  end
  ```
- [ ] **Harbour / runway queue fields** (stuck exclusions), on a ship waiting outside a harbour and a plane waiting at a runway:
  ```lua
  local v = <vehicleId>
  local mp = api.engine.getComponent(v, api.type.ComponentType.MOVE_PATH) if mp then print("approaching", mp.dyn.approachingStation) end
  local mpa = api.engine.getComponent(v, api.type.ComponentType.MOVE_PATH_AIRCRAFT)
  if mpa then print("ship approaching", mpa.shipState.dyn.approachingStation, "waitingDist", mpa.shipState.waitingDist,
    "clearToLand", mpa.shipState.clearToLand, "air waitingDistance", mpa.aircraftState.waitingDistance) end
  local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) print("daysInDepot", tv.daysInDepot)
  ```
- [ ] **DoubleSpinBox typing:** −/+ step by 1; typing a value works and clamps to the range; values show as integers (report `3.0`-style decimals); typing isn't interrupted by the once-per-second refresh.
- [ ] **Module-locals shared by update and handleEvent:** switching a kind to Notify should not toast the alerts already listed (§6). If it does, the engine's `update` and `handleEvent` don't share one Lua module instance; report it.

## 11. Phase 7: Economy tab (`line_unprofitable`, `line_low_use`)

Defaults: both **List**; Losing money = Info when the 12-month balance is negative with ≥ 3 of 4 quarters negative, tier by points: coverage (income ÷ the line's vehicle costs) < 75 % = 1, < 50 % = 2; loss ≥ 2 % of all lines' vehicle costs = 1, ≥ 6 % = 2; 0 Info, 1-2 Warning, ≥ 3 Critical; Low use = yearly average utilisation < 20 % (Warning < 10 %, Critical < 5 %), judged once a line has been tracked for half a game year. Use a copy of an established save (≥ 1 game year old, some weak lines) and 32× speed.

- [x] **`calculateBalance` on the sim thread** (only base GUI code calls it): play 10 minutes; no `[ProblemRadar] line money scan failed (calculateBalance): …` warning. If it appears, report the full line: the money part then stays empty (its previous rows are kept for 10 failures, then dropped) while `line_low_use` and every other alert keep working. *(2026-10-07: passed: Losing-money rows listed in a Dec 1992 save, `shots/04-economy.jpg`.)*
- [ ] **Balance matches the base line window:** for a line listed as *Losing money*, the row's money (metric column) matches the line window's 12-month **Balance** to two significant digits. Console (GUI thread; the same call the engine makes):
  ```lua
  local line = <lineId>
  local now = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
  local Y = api.util.getDefaultYearDuration() local from = now - Y local B = api.engine.util.finance.calculateBalance
  print("year", B({line}, from, now, true))
  for i = 1, 4 do print("quarter", i, B({line}, from + (i - 1) * (Y // 4), i == 4 and now or from + i * (Y // 4), true)) end
  local M = api.type.JournalEntry.Maintenance print("enum", M.VEHICLE, M.VEHICLE_MAINTENANCE)
  print("running", B({line}, from, now, true, M.VEHICLE), "maintenance", B({line}, from, now, true, M.VEHICLE_MAINTENANCE))
  print("via vehicles", B(api.engine.system.transportVehicleSystem.getLineVehicles(line), from, now, true))
  ```
- [x] **The cost split gives a sane coverage:** `running` and `maintenance` above are ≤ 0, and `year - running - maintenance` (= income) is ≥ 0 and close to the line's yearly revenue. If the maintenance-type calls return the whole balance (income included) or 0, the split doesn't work as assumed: every losing line then shows as Warning with no "income covers" text (code `LossNoSplit`). Report the printed numbers either way. Also report whether the line entity's balance includes costs at all (if `year` is never negative for an obviously losing line, the line account holds income only and the vehicles' balance, "via vehicles", is the one to use). *(2026-10-07: rows come out Critical and Warning by coverage, so the split works; console numbers still to report.)*
- [ ] **A deliberately losing line shows up:** build a bus line with several expensive vehicles between two tiny villages and run it for a bit over a game year (32×). It must appear in **Economy** as *Losing money* once a full year of history exists (not before: the oldest quarter must have journal entries; each line's money is re-checked once per game month, so allow up to a month plus the smoothing time), with `Lost … in 12 months, 4/4 quarters negative, income covers about N% of vehicle costs`, Critical when N < 50. A brand-new line in an old save must **not** appear until it is a year old.
- [ ] **Combined severity (coverage + size):** in a save with several losing lines, a small loss that earns back < 50 % of its costs is a **Warning** (not Critical), a line with poor coverage whose loss is ≥ 6 % of all lines' vehicle costs is **Critical**, and within each severity the bigger losses come first. Hover a row: the tooltip is the full sentence (loss, quarters, coverage, share of all line costs); the detail cell ("Earns N% of costs · M% of all line costs") is not cut off. Console check of the reference: `B(<all your line ids>, from, now, true, M.VEHICLE) + B(…, M.VEHICLE_MAINTENANCE)` is negative and its size matches the finance window's vehicle costs for the year (roughly; only lines with vehicles count).
- [ ] **Severity tracks the size:** raise `econLossCritPct` to 99 and lower `econLossSharePct` to 1 in Settings → Economy: a losing line whose loss is at least 1 % of all lines' costs turns Critical on its next re-check, at most a game month later (with more than about 200 lines with vehicles: L / 4 lines passes of 2.4 s). Save and reload to force an immediate re-check of every line (at 4 lines per pass). Reset.
- [ ] **Utilisation average starts after half a year:** on the same near-empty line, `s.memory.useAvg[line]` appears within a minute (tracking start = first sample); after about half a game year it shows as *Low use* (`N% used on average over 6 months`), tier by the thresholds. A line half full must not show. The basis points `u[1]` should match the line window's Utilization over time (roughly; the window shows the instant value).
- [ ] **Save/load keeps the averages:** note `useAvg` for two lines, save, reload: same tracking start and the same basis points (the saved copy, at most a game month old), the *Low use* rows still listed after the load (no restart of the half-year wait). The log shows `state initialised` at most once.
- [ ] **Save churn:** with the window closed and nothing changing, `useAvg` must not be rewritten on every pass: its `u[3]` (last sample) values change together about once per game month (also with 300+ lines), or when a line starts / stops being tracked. Print `useAvg` a few times a game week apart: the basis points do not change between the monthly writes.
- [ ] **Off drops the memory:** set *Low use* to **Off**: within one pass `s.memory.useAvg` is empty and its rows go; back to List: tracking restarts from scratch (half a year again).
- [ ] **Adding the mod to an existing save (≥ 1 year old):** money rows appear within a minute or two (the money check needs no history of ours); *Low use* rows only after half a game year. No error, no toast burst.
- [x] **Ridge / tier counts:** with a Critical economy row and no other Critical alert, the badge dot is **red** (the HUD reads `s.tierCounts`, since the economy kinds' tier varies per row). *(2026-10-07: passed: the badge dot is red with only economy rows Critical, `shots/05-all-economy.jpg`.)*
- [ ] **Icons:** a *Losing money* row set to Notify shows the base coin-stack icon (`::/game_mechanics/finance/icons/symbol_coin_stack.tga`) in the toast; report if it renders badly (wrong size / blank) at notification size, and whether `api.util.formatMoney` text fits the metric column.

## 12. Simulation Lua states (PERF_VMS fix, 2026-10-10)

The game script runs in ~14 Lua states; ticks hop between them. Offline proof: `tests/square_problem_radar/test_multistate.lua`.
Turn on **DEV SQPERF: all mods** (or the mod's *Debug: performance log*) for the `win_ms=` lines.

- [ ] **No burst when added:** copy a save that never had the radar (or one saved after removing it: removal drops the `radar.gs` entity, §8), with lines without vehicles. Enable, load, play 5 game-minutes. `grep "\[ProblemRadar\]" stdout.txt`: `state initialised (…)` exactly once, **no** `notified` line. Console right after load: `print(s.rt and s.rt.prime and s.rt.prime.all)` → `true`, a few seconds later `nil`.
- [ ] **No burst on switch:** with 3+ rows of a List kind (e.g. Overcrowded or Worn), set it to Notify in the window: no `notified` line; a new problem of that kind toasts later.
- [ ] **Stuck delay:** `stuckMinRoad = 1` (console, §1). Make one road vehicle stand en route (e.g. block its road) and note the game time. Its row must appear **90-95 game s** later (1 min + 30 s smoothing + ≤ 2 passes); at 1× game seconds are real seconds. Console every few seconds: `s.rt.young.stopped[<id>]` (first 30 s) then `s.memory.stoppedSince[<id>]` must keep the **same** start value (it never restarts).
- [ ] **Budget:** 10+ vehicles stuck at once: per 2 game-minutes at most 3 `notified 1`-style toasts plus one `+N more` summary (timestamps of the `notified` lines).
- [ ] **Rotation:** with > 8 lines, `print(s.rt.lineCursor)` every few seconds walks up through the line ids and wraps (not stuck near the lowest ids).
- [ ] **Write cost:** in the `ctx=gs` window lines compare `state_get n= ms=` with `state_set n= ms=`; `stateSet c=` all writes, `stateSetQuiet c=` the ones only bookkeeping changed (mostly lines and vehicles passes). Report both on the big save; `make perf` sums them.

## Report back

- Which checks passed, which failed, with screenshots of layout issues.
- The API answers from §10 and §11 (numbers, not just "works").
- FPS numbers from §7 and the save's size (vehicles, lines, stations).
- Thresholds that felt wrong (false positives matter most: the radar should stay quiet on a healthy network).
- Every `[ProblemRadar]` log line.
