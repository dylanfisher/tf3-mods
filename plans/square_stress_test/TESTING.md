# square_stress_test: pre-release checklist

Display name: **Stress Test Debug Tool** (modId `square_stress_test`), revision 1, not uploaded yet. Run sections 0-7
in a throwaway free game before the first upload. Sections marked **Verified in game** were already seen working in
the probe runs of 2026-10-10 (docs/findings.md "Stress Test probes") and only need a quick re-check. The Probe tab
experiments are in Appendix A. **Use a throwaway save: this mod changes the save** (towns, vehicles, money, date,
speed, town rating sensitivity, the notification ignore list).

Log: `~/Library/Application Support/Steam/userdata/<id>/3493540/local/crash_dump/stdout.txt`.

```sh
LOG=~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt
grep -h "\[SQST" $LOG                 # every action line
grep -h "Failed to parse mod.json\|square_stress_test" $LOG | head   # mod didn't show up?
```

Every action writes `[SQST] action=<name> count=<n> ms=<wall ms> busyMs=<ms inside the steps>`. Errors show as
`[SQST] button error`, `[SQST] tick error`, `[SQST] callback <name> error` or `cmd <name> failed`. The last 8 lines
also show at the bottom of the window.

## Release gate

- [ ] Section 0 (setup, look) with all settings at their defaults: no error, no `[SQST] config` line, **no Probe tab**.
- [ ] Section 1 (Game tab) and section 2 (town ratings).
- [ ] Section 3: at least **No noise and pollution** = On once, and Show probe tab = On once (the tab appears).
- [ ] Sections 4, 5, 5B: quick re-check of the verified actions.
- [ ] Section 5C (Auto bus lines): the user's in-game test of the bus-line code (fixes go separately).
- [ ] Section 6 (notifications) and section 7 (save, reload, remove).
- [ ] `make check MOD=mods/square_stress_test`, `make test MOD=mods/square_stress_test`, `make validate MOD=mods/square_stress_test`.
- [ ] Cover rendered (`make covers MOD=mods/square_stress_test`), description.html reads well in the Mod Hub.

## 0. Setup and look

1. `make link`, start the game, Mod Hub: enable **Stress Test Debug Tool**, leave all its settings at their defaults.
2. Start a new free game (medium map, a few towns), or load a copy of a save. Section 5 needs a bus line with at
   least one bus and a road depot.
3. The top-left mod button row shows **Debug**. Click it: a window "Stress Test Debug Tool" opens with tabs
   **Game / Towns / Traffic** (no Probe tab), a status line (Year, Speed, Balance), "Queue: Idle" and a Log section.
   Click Debug again: the window closes. Look for: no error popup, no `[SQST] tick error` in stdout.txt, and no
   `[SQST] config` line (defaults change nothing).
4. Every tab section is a form: its heading row has the section's action button at the right edge, the options
   (toggle groups) below. Action buttons have a solid **green** fill; other buttons (Freeze all, Clear queue, speed
   buttons, Restore defaults, Sell added vehicles) a neutral fill with a blue outline on hover; none renders as bare
   text. The window fits on a 1080 px screen; the Log shows about 6 lines (scrolls). No hint text mentions phases,
   probes or "untested". If the green or the fills are missing, the stylesheet failed: check stdout.txt.

## 1. Game tab

Money, top-up and the year jump are **verified in game** (first run); speed 8 sticks (second run); speed 16 was sent
but never read back.

| Step | Expect on screen | Expect in stdout.txt |
|---|---|---|
| Click **Add 10M** | Balance in the status line goes up by 10M within a second | `[SQST] action=add_money_10M count=1 ...` |
| Click **Add 100M** | +100M | `action=add_money_100M count=1` |
| Tick **Keep balance above 50M**, then spend money until below 50M (or start with less) | Within ~2 s the balance jumps back to about 60M; the box stays ticked | `[SQST] keep_balance on`, then `action=top_up count=1` per top-up (at most one per balance; while paused it retries every 20 s) |
| Untick it | No more top-ups | `[SQST] keep_balance off` |
| Type `2000` in the year field, click **Jump to year** | Status shows Year 2000; the game's date shows 1 Jan 2000; newer vehicles appear in the depot | `action=set_year_2000 count=1`, then `[SQST] set_year 2000 success=true year now 2000` |
| Type `abc`, click **Jump to year** | Nothing changes | `[SQST] set_year: "abc" is not a year (not a number)` |
| Click **1x 2x 4x** | Status speed and the game bar speed follow | `action=set_speed_N count=1` |
| Click **8x**, then **16x** | Status speed shows 8, then **16 or less** (note what it shows after 15 s at 16x: the read-back for 16 is still missing) | `action=set_speed_16` |
| Click **Clear queue** | "Queue: Idle" | `[SQST] queue cleared (0 jobs)` |

## 2. Town ratings (Game tab, not verified in game yet)

"Ignore noise and pollution" sends the base Towns game script's `setTownRatingSensitivity` event (rating `noise`,
then `pollution`, sensitivity 0) for every town, one event at a time, as the town editor's rating sensitivity
control does (town_eow.script.tl:896-903, towns.script.tl:351-368). A sensitivity of 0 makes the noise and
pollution ratings 1.0 (town_util.tl:412-439). "Restore defaults" sends `resetTownRatingSensitivity` per town (like
the editor's reset button: it clears all six custom sensitivities). Both are stored in the save.

| Step | Expect on screen | Expect in stdout.txt |
|---|---|---|
| Open the window of a town next to a busy road or an industry, note its noise and pollution ratings | | |
| Game tab, **Ignore noise and pollution** | Queue `Ignoring noise and pollution i/2N`; within a few seconds the town's noise and pollution ratings show full (no penalty) | `[SQST] ignore_town_emissions summary towns=N events=2N ok=2N`, `action=ignore_town_emissions count=2N` |
| With Sandbox mode on: the town window's editor tab, rating sensitivity | Noise and pollution show the lowest option | |
| **Restore defaults** | The ratings drop back to what they were | `restore_town_ratings summary towns=N events=N ok=N` |
| Spawn a town, then check it | The new town still has the default sensitivity (press again to include it) | |

## 3. Load-time settings (each needs a reload)

Mod Hub > Stress Test Debug Tool settings, then start a new game (or reload) and check stdout.txt for one line
`[SQST] config ...` listing exactly what was changed. With all defaults there must be **no** such line. None of
these has been checked in game yet.

| Setting | Check in game |
|---|---|
| No costs = On | Building a road costs nothing (`[SQST] config noCosts=true`) |
| Sandbox mode = On | Town window has the sandbox editor tabs; industries in the construction menu |
| Vehicles never expire = On | Old vehicle models stay in the depot list after jumping to 2100 |
| No noise and pollution = On | See below |
| Sim person trip recalculation x2 / x5 | `config simPersonDestinationRecomputationProbability=2` (or 5) |
| Town development interval Fast / Very fast | `config townDevelopInterval=15` (or 5); towns grow visibly faster |
| Show probe tab (developers) = On | The window has a fourth tab, **Probe** (Appendix A); Off again: the tab is gone |

**No noise and pollution** (replaces the earlier "Town noise ignored"; three parts, each cited in stress_logic.tl):

1. stdout.txt: `[SQST] config missionEmissionsScriptFactor=0 townNoise*Affected=false` and
   `[SQST] config town_ratings_sensitivity SensitivityNoise=1 SensitivityPollution=1`; no `preRunFn failed` /
   `postRunFn failed`.
2. Depot or vehicle purchase window: every vehicle's noise and pollution bars are empty (score 0).
3. Emissions layer (map layers): roads with traffic show no noise; **new** industries and stations show none.
   Existing industries, stations and depots keep the value they had when the game loaded (the emissions script stops
   updating them; it never resets them). Note how they look.
4. Town window: noise and pollution ratings at full (no penalty) for towns without their own sensitivity.
5. Off again + reload: vehicles show their usual bars, the emissions layer comes back within a few seconds.
6. Side effect to look for: "make green" industry upgrades (pollution cleanup) do nothing while it is on (the base
   script returns before subscribing to that event, emissions.script.tl:27-32).

## 4. Towns tab

**Verified in game** (docs/findings.md "Stress Test probes", third and fourth runs): spawn near the camera and spread
over the map (Small to Huge), grow with passes, connect (`{{0,1}}`, 0-based, success), freeze/unfreeze. Not yet seen:
Reset to x1 (do buildings shrink?), the relaxed placement after the map fills up, double-click spawn.

Open the **Towns** tab. Changing Target, Factor, Passes, Count or Size changes the green button's label at once
(e.g. "Grow all towns x10, 3 passes", "Spawn 5 large towns"); nothing happens until it is clicked. The top line is the readout, refreshed every 4 s while the window is open:
`Towns N (k frozen)   Capacity X   Buildings Y` (capacity = sum of all towns' person capacities).
Every action ends with `[SQST] action=<name> count=<n> ms=...`; per-town details go to stdout.txt only
(`grep -h "\[SQST\] \(grow\|spawn\|connect\)" $LOG`). Town commands run one at a time: the queue line shows
e.g. `Growing x10 3/12`, and the next town starts only after the previous command's callback.

Third run (docs/findings.md): one grow command builds ~250-350 buildings and re-sending it keeps building, so the
Grow form has **Passes** (1/3/5/10): each town gets the command N times in a row (pass 1 multiplies the factors,
later passes re-send them), and a town stops early when a pass adds fewer than 20 buildings. Spawn placement now
relaxes when the strict pass finds too few spots: `strict` → `wider` (more rings, finer grid over the map) →
`70%` → `50%` of the size's spacing, never closer than 800 m; water and map-edge checks never relax. The placement
line names the step used (`relaxation=none|wider|70%|50%`) and lists each step's candidates and skips.

| Step | Expect on screen | Expect in stdout.txt |
|---|---|---|
| Target **Nearest to camera**, Factor **x10**, Passes **1** (the button now reads "Grow nearest town x10"), camera on a small town, click it | Queue `Growing x10 1/1`; the town fills up within ~5 s; readout capacity rises | `[SQST] grow_x10 1/1 pass 1/1 town=... success=true ms=... sizeFactors {1,1,1}->{10,10,10} buildings A->B (+n)`, `grow_x10 summary towns=1 passes=1 sent=1 stoppedEarly=0 buildings A->B`, then `action=grow_x10 count=1` |
| Same town, Passes **5** ("Grow nearest town x10, 5 passes") | Queue `Growing x10, 5 passes 1/5` ... `5/5`; the town keeps getting denser, ~300 buildings per pass | `pass 2/5 ... (build-out pass) buildings A->B (+n)` per pass; a pass under +20 ends it early (`build-out done after pass k`); the summary line has the total `buildings A->B` |
| On a town already at 1000 (two x100 clicks), Passes **3** | Still builds | first pass `(at cap, build-out pass)`, then `(build-out pass)` |
| Target **All towns**, Factor **x2**, click **Grow all towns x2** | `Growing x2 1/N` ... `N/N`, one town after another (each takes 0.5-4 s) | one `grow_x2 i/N` line per town, then `action=grow_x2 count=N` |
| Factor **x100**, click **Grow nearest town x100** twice on one town | Second time the factors stop at 1000 | `... (capped at 1000)` |
| Factor **Reset to x1** (button: "Reset nearest town to x1"), click it | Unknown: do buildings shrink or stay? Please note it | `grow_reset 1/1 ... ->{1,1,1} buildings A->B` |
| Count **1**, Size **Medium (400)**, Where **Near camera**, camera on open land, **Spawn 1 medium town** | A town "SQST Town N" appears near the camera within a few seconds | `[SQST] spawn_medium placement: 1 of 1 positions, near camera X,Y relaxation=none | strict 1500m cands=16 placed=1 (...)`, `spawn_medium 1/1 SQST Town N pos=... success=true ms=... createTowns caps={...} sent caps=400 results=R town=... initCaps={400,400,400} ... buildings=... personCaps={...}`, `spawn_medium summary requested=1 placed=1 created=1 failed=0`, `action=spawn_medium count=1` |
| Count **5**, Size **Large (1600)**, **Spawn 5 large towns** | `Spawning large towns 1/5` ... `5/5`, towns appear one by one in a ring ~2 km apart around the camera, none on water or on top of another town | five `spawn_large i/5` lines, callbacks ~4 s each (not 10-12 s as when several ran at once) |
| Count **1**, Size **Huge (3200)**, **Spawn 1 huge town** | One very big town (fourth run: caps kept, 716 buildings, 5.5 s) | the placement line's `relaxation=`, then `spawn_huge 1/1 ... initCaps={3200,3200,3200}` |
| Where **Spread over map**, Count **10**, Size **Small**, **Spawn 10 small towns** | Ten small towns spread across the whole map, none in water or within 1.2 km of a town | `placement: 10 of 10 positions, spread map=... coarse grid=...m relaxation=... | strict ...m cands=C placed=P (near=.. water=.. edge=..) | ...` |
| Keep spawning spread over the map until the map is full (the third run's coarse grid ran out after ~16 towns) | More towns still fit, closer together (never under 800 m) | later batches log `relaxation=wider`, `70%` or `50%`; when even 50% has no spot, `0 of N positions` |
| Tick **Connect new towns by road**, Count **1**, click the Spawn button | After the town: `Connecting towns 1/1`; a road from the new town to its nearest town | `connect_towns 1/1 <new> - <nearest> connections={{0,1}} success=true ms=...`, `action=connect_towns count=1`. Note whether it built roads to industries too |
| **Freeze all** | Readout shows `(N frozen)` within ~4 s; towns stop growing | `action=freeze_towns count=N` |
| **Unfreeze all** | `(frozen)` disappears | `action=unfreeze_towns count=N` |
| Click the Spawn button twice quickly | The second batch waits until the first one is done | Names keep counting up (no duplicate "SQST Town N"), each `summary` line has its own `created` count |
| **Clear queue** during a spawn | Queue `Idle`; the town already being created still appears | no error lines |

Look for: no `[SQST] tick error`, no `callback ... error`, and the frame rate while a Large/Huge town is created
(the callback ms is the stall).

## 5. Traffic tab: add vehicles

**Needs a save with at least one line of yours that has a vehicle** (a bus line with one bus and a road depot is
enough), and money (Add 100M first, or tick Keep balance). **Verified in game** (third run): 25 buses on one line,
`setLine` true for all, ~0.6 s each, 0 failures, lines without a vehicle skipped. Not yet seen: Sell added vehicles,
non-bus lines (tram, train, ship, plane), the 3-failures stop.

The top line is the readout, refreshed every 4 s while the window is open: `Lines L   Vehicles V   Sim persons P`,
plus `Driving now D` after the first Clear traffic scan (section 5B) and `Added A` once vehicles were bought here.
Lines = your lines; Vehicles = every transport vehicle (all companies); Sim persons = `simPersonSystem.getCount()`.
Per-vehicle details go to stdout.txt only: `grep -h "\[SQST\] \(add_vehicles\|remove_vehicles\)" $LOG`.

| Step | Expect on screen | Expect in stdout.txt |
|---|---|---|
| Per line **1**, click **Add 1 vehicle per line** | Queue `Buying 1/N` ... `N/N` (N = lines with a vehicle); a copy of each line's first vehicle (same model, same wagons) leaves a depot and joins the line; Lines window vehicle count +1 per line; readout `Added N` | `add_vehicles_1: L lines x 1 = N vehicles (S skipped: no vehicle)`, per line once `add_vehicles_1 line=... depot=... (best)`, per vehicle `add_vehicles_1 i/N line=... vehicle=... depot=... setLine=true ms=...`, then `add_vehicles_1 summary planned=N bought=N setLine=N failed=0 lineSkips=0 balance A->B` and `action=add_vehicles_1 count=N` |
| A line without vehicles exists | It gets nothing | `add_vehicles_1: line X (name) has no vehicle to copy; skipped` |
| Per line **5** | Purchases go round robin (one per line, then the second per line, ...), one at a time | `Buying 1/5N` ...; **please paste** the `ms=` of a few lines (time per purchase) |
| Untick Keep balance, spend down to less than one vehicle's price, **Add** | Nothing is bought | `add_vehicles_N stopped: balance X can't pay the next vehicle (Y); tick Keep balance or add money`, summary `bought=0 ... stopped: ...` |
| Keep balance on, Per line **25** on a few lines | Many buses; balance kept above 50M | no `failures in a row` lines; frame rate while buying? |
| Something refuses the buys (e.g. delete the depot, then Add) | Queue stops after 3 tries | three `add_vehicles_N i/M buy failed line=... depot=... (k/3 failures in a row)` lines (or `no depot (...); line skipped` when no depot is found at all), then `stopped after 3 failures in a row` |
| **Sell added vehicles (A)** | Queue `Selling 1/A` ...; the added vehicles disappear; the button count drops to 0 | per vehicle `remove_vehicles i/A vehicle=... success=true`, `remove_vehicles summary requested=A sold=A gone=0 failed=0 left=0`, `action=remove_vehicles count=A` |
| Sell with nothing added | Nothing | `remove_vehicles: no vehicles added in this session` |
| Save + reload, then Sell | Nothing (the list is in memory only) | `no vehicles added in this session` |

Look for: no `[SQST] tick error`, no `callback ... error`, no `error:` in the add/remove lines. Unknowns to report:
does `findBestLineAndDepotForVehicle` find a depot for each line type (bus, tram, train, ship, plane)? Do the new
vehicles start at stop 1 (stopIndex 0) and run normally? Is the wagon order of trains kept?

Auto bus lines: section 5C.

## 5B. Clear traffic

**Verified in game** (fifth run): one click scanned 11,096 persons, 285 drivers sent home, 285 ok, 333 ms; Keep cleared
every 5 s finds 205-349 drivers per cycle, ~390 ms per cycle. Not yet seen: the 50k+ person map, Clear queue unticking it.

Built on probe 9 (docs/findings.md "Stress Test probes", fourth run): `makeSimPersonSetStateCmd(e, 2)` ("jump home")
takes a driver off the road within 2 s, and drivers start their next trip within ~15 s. A driver = `SIM_PERSON` with
`lastMoveMode` DRIVE, a `MOVE_PATH`, no `SIM_PERSON_AT_VEHICLE` / `SIM_ENTITY_AT_VEHICLE`; transport vehicles are never
sent anything. One clear reads 5,000 persons per frame over a snapshot of the person list, then sends 200 commands
per frame (queue label `Clearing traffic i/n`).

**Needs a town with visible car traffic** (as for probe 9: grow a town x10, run a few months at speed 4). Unpause at
speed 1 (the commands run in the next simulation step). Have a bus line of yours running on the same roads to check
it is left alone.

| Step | Expect on screen | Expect in stdout.txt |
|---|---|---|
| Centre the camera on a busy road, Traffic tab, click **Clear traffic** (green, Car traffic row) | Within ~2 s the cars vanish from the road; your buses keep driving. The readout shows `Driving now D` (about the number of cars you saw, before the clear); after a few seconds cars come back | `[SQST] clear_traffic scanned=N drivers=D sent=D ok=D ms=...` (N = sim persons; `answered=A` appears only if callbacks were missing after 10 s) |
| Click **Clear traffic** twice quickly | Second click is refused while the first runs | `clear_traffic: a clear is still running; try again in a moment` (on a small map the first may already be done: then two clear lines) |
| Tick **Keep traffic cleared**, Every **5 s** (default) | The road stays (nearly) empty: cars that start a trip vanish again within ~5 s | `[SQST] keep_traffic_cleared on (every 5 s)`, then in the window at most one `[SQST] keep_traffic_cleared cycles=C skipped=K drivers=D sent=S ok=K (last: scanned=N drivers=D ms=...)` per 30 s; per cycle in stdout.txt only: `[SQST] keep_traffic_cleared scanned=N drivers=D sent=S ok=K ms=...` |
| Switch Every to **2 s**, then **10 s** | Cars stay away longer with 2 s, come back more with 10 s | The cycle lines follow the new interval |
| Untick **Keep traffic cleared** | Traffic comes back within ~15 s | `[SQST] keep_traffic_cleared off` |
| Tick it again, then click **Clear queue** | The box unticks itself | `[SQST] queue cleared (N jobs)`, `[SQST] keep_traffic_cleared off (queue cleared)` |
| Big map (Towns tab: grow several towns x100 with passes, 50k+ sim persons), Keep cleared on | Frame rate while it runs? (one 5,000-person chunk per frame) | Please paste a few cycle lines (`scanned`, `ms`) and any `cycle skipped` lines |

Look for: no `[SQST] tick hook error`, no `error:` in the clear lines, `ok` equal to `sent` (a failed command
would mean the state was refused for some persons). Unknowns to report: does a jumped driver ever reappear mid-road
(not at home)? Do the cleared persons still count toward town growth and happiness as usual?

## 5C. Auto bus lines (sixth run: works with a depot in place; the fixes below are not re-run yet)

Built on probe 10 (PROBES_BUSLINES.md): stops work (fifth run), the depot spot search, the depot lookup and the
entrance connection are new. **Run 10c and 10d first** (PROBES_BUSLINES.md steps 6-7; needs the setting "Show probe tab (developers)" = On): if 10c cannot build and
connect a depot, Auto bus lines can only use depots that `findBestDepotForLine` already finds (your own).

Sixth run (docs/findings.md): with a depot in town, 2 x 4 lines x 10 buses worked (~6 s per line); in a dense town
the depot search failed and left empty lines behind, names skipped by 3, quick clicks stacked batches, and the game
crashed right after a batch (unexplained; guards added). Fixed since, **re-test these**:

Per town, **the depot comes first**: a depot built by Auto bus lines within 2 km of the town, else any road depot
of yours within 2 km, else a new one: street edges in rings outward from the centre (300-700 m, 700-1200 m,
1200-2000 m, then 0-300 m), up to 15 per ring with the fewest town buildings within 80 m first (own town before
other towns), each tried at 30/45/60/80 m from the street on both sides and pre-checked (`makeProposalData`); else
the nearest road depot anywhere, used only if `findBestDepotForLine` confirms a depot once the line exists. **No
depot = the town is skipped with nothing built.** Then per line: two of the town's street edges (within 900 m,
at least 30 m, no stop or signal, not part of a construction) 300-800 m apart, built-up and without moving sim
persons first, never within 100 m of any stop or depot gate of ours from this session; a stop on each, the line
"SQST Bus N" (N counts 1, 2, 3 ... after the highest existing SQST Bus N), then N buses from
`findBestDepotForLine`'s depot only (2026-10-12; none: a new depot near stop 1, asked again, else the line is
destroyed before any bus is bought; a bus whose SetLine fails is sold again). **A line that ends up with no bus is destroyed again** and its
stops are counted as `wastedStops` in the summary. Every bus id and stop (station group, result entities) is logged
with `rt.detail`. Every vehicle or line id is re-checked right before its command. One command at a time; a town
stops at its first failure, the batch after 3 failed towns in a row, and without Keep balance it stops when the
balance is below 1M before a line or a bus can't be paid. **The button refuses** (logged) while a batch or a
removal is queued or running. Lines and buses are remembered for this session only (forgotten on reload).

Setup: a free game in a year with buses (1950+), a few towns with streets, money (Add 100M or Keep balance), speed 1
unpaused. Traffic tab, section **Auto bus lines**. The green button names the batch ("Add 1 bus line each to 5
towns"); Towns / Lines / Buses change it.

| Step | Expect on screen | Expect in stdout.txt |
|---|---|---|
| Camera on a town, Towns **Nearest to camera**, Lines **1**, Buses **2**, click **Add 1 bus line to the nearest town** | Queue `Bus lines 1/1`; two stops appear in the town a few blocks apart, then a line in the line manager, maybe a depot at the edge of town with a short street to its gate, then 2 buses leave the depot | `[SQST] bus_lines: 1 towns x 1 lines x 2 buses (1 lines)`, `bus_lines bus: year=... pick=...`, per line `bus_lines 1/1 <town> ok ms=... line 1: edges A,B (builtUp,quiet) Nm apart depot=D (existing, Nm / built in ring 300-700m / ours, Nm) groups=G1,G2 line=L (SQST Bus N) success=true buses from depot=D2 (findBestDepotForLine=D2) buses=2/2`; `stop built: SQST Stop k edge=E stationGroup=G ...` and `bought bus=V depot=D for line=L` per item, `bus_lines town <town> (id): 1 lines ok`, `bus_lines summary towns=1 ok=1 failed=0 lines=1 (complete 1) buses=2 ...`, `action=bus_lines count=1` |
| Watch the buses for a minute | They drive to both stops and back; passengers board after a while | none |
| Same town again, Lines **2** | Two more lines on other streets of the same town (no stop next to an earlier one of this session) | two `bus_lines i/2` lines, line names continue (SQST Bus N+1, N+2), no new depot |
| Click the green button 3 times quickly | One batch only | one `bus_lines: ... plan` line and `bus_lines: refused, bus_lines is still queued or running` for the other clicks |
| Towns **5 nearest**, Lines **1**, Buses **5** | `Bus lines 1/5` ... `5/5`, one town after another | one `town ... lines ok` or `town ... failed after k lines: <reason> (n/3 failed towns in a row)` per town; **please paste** the failed ones |
| Towns **All towns** on a map with many towns | At most 25 towns, nearest to the camera first | summary `towns=25` (or fewer) |
| A dense town with no depot of yours within 2 km | A depot appears on a quiet street 300-2000 m from the centre, **before** any stop; if none fits, the town fails with **no** stop or line built | `bus_lines <town> depot 300-700m: ...` per ring, `depot rings: 300-700m inRing=N edges=15 spots=... pre={...} sent=... ; 700-1200m ...`; on failure `depot failed, nothing built (...)`; summary `wastedStops=0` |
| Untick Keep balance, spend down below 1M, click the button | Nothing is built | `bus_lines stopped: balance ... below 1M; tick Keep balance or add money` |
| **Remove added bus lines (L)** | Queue `Selling buses`, `Waiting for sold buses`, `Removing bus lines`; the buses disappear, then the lines; **stops and depots stay** | `remove_bus_lines summary vehicles=V sold=V lines=L deleted=L kept=0 gone=0 failed=0 wait: 0 still listed after N ms left: 0 lines, 0 buses (stops and depots stay)` |
| Remove with nothing added (or after a reload) | Nothing | `remove_bus_lines: no bus lines added in this session` |
| **Clear queue** during a batch | Queue `Idle`; a line in progress may still finish its current command | no `error:` lines |

Unknowns to report: does the crash of the sixth run come back (paste the `Engine.h` assertion's entity id; grep
stdout.txt for it among `bought bus=` / `stop built:`)? Does the pre-check (`pre={...}`) agree with the engine (a spot pre-checked `ok` but refused is a
miss)? Do the stops get passengers (built-up edges)? How long does one line take (`ms=`)? Is the frame rate hit when
a town's edges are read (up to 300 edges, one closest-town and one building query each)? Does `findBestDepotForLine`
find the depot we built (`built; findBestDepotForLine=<id> after`)?

## 6. Hide all notifications

The event itself is **verified** (third run: `success=true` with 29 type names); whether every popup really stays away
is not.

Uses the base Notifications game script's own ignore set (`updateIgnoredTypes` event with `ignoreFully=true`,
as the missions do). The set is **stored in the save**: uncheck the box before removing the mod, or the
notifications stay hidden in that save.

1. Load a save with the mod: the Game tab box **Hide all notifications** is ticked; stdout.txt has
   `[SQST] notifications hidden success=true ...`. Please paste the line (the `type names` count).
2. Make notifications happen: grow a town x10 (Towns tab), let a vehicle get old (jump the year forward 30 years),
   leave an industry unserved, run out of money. Look for: no notification popups at the top and no new entries
   in the notification log. Note any that still appear: achievement toasts and money popups (floating +/- amounts)
   may not be covered.
3. Untick the box: `[SQST] notifications shown success=true`. New notifications appear again (old ones that were
   ignored while it was on don't come back). Note: this also clears your own notification-log filter.
4. Tick it again: `hidden` again. Save, reload: still hidden, and the mod sends it again on load (one `hidden` line).

## 6B. Test grid (rev 2, not run in game yet)

Setup: Map Editor → new temperate map → Generate heightmap → **Blank Slate (flat island)** → Generate → save → Play Map
(no towns, no industries). Enable Stress Test, open Debug → Towns.

1. Test grid: 2 x 2, 2 km, Medium, Map centre, Roads = Neighbours → press "Create 2 x 2 grid, 2 km".
   Expect 4 towns "Grid A1/A2/B1/B2", then 4 road links (A1-A2, A1-B1, A2-B2, B1-B2).
2. stdout.txt: `[SQST] grid_2x2 summary towns=4 created=4 failed=0 ... maxOffset=` should be ~0 m. If not, the
   engine moves the centre: note the per-town `asked=... real=...` lines. Also note `angle0=` (true = the street-angle
   fields were writable) and whether the four towns look the same (same seed, same angle): docs/findings.md.
3. Look at the road links: straight on a flat map, or winding? Do they join the town streets at the edges?
4. Roads = Neighbours + diagonals on a 3 x 3, 3 km: 9 towns, 20 links (checks connect on a bigger batch).
5. Centre = Camera with the camera over the sea edge: expect `grid_... cancelled: Grid X at ... is water`, nothing built.

## 6C. Remove towns (rev 2, not run in game yet)

Save first. `makeTownDestroyCmd` has only been used by the base map editor, never from a mod in a running game.

1. Target Nearest to camera → "Remove the nearest town". Expect `[SQST] remove_nearest 1/1 ... success=true gone=true`
   and the town's streets and buildings gone. Note what happens to your own roads/stations/stops that touch the town.
2. Target Grid towns after a Test grid run: only "Grid ..." towns go. Road links between them (built by the town
   connect command): removed with the towns, or left behind?
3. Target All towns on a New Game Blank Slate map: an empty map without the Map Editor? Industries stay.
4. Save, reload: no errors, town count as before the reload.

## 6D. Remove all roads + confirm dialogs (rev 2, not run in game yet)

The confirm dialog is the base `dialog_react_util.DialogWindow` (pause menu's Quit Game) opened in the default
window container from a mod: never tried in game before.

1. Remove towns (any target) and Remove all roads: a centred dialog with the count, Remove and Cancel (Cancel
   focused). Cancel, Esc and a click outside do nothing; check stdout has no `remove_` line. Does it look right
   (opaque, readable)?
2. Remove all roads on a map with towns removed (step 6C.3): `[SQST] remove_roads: N street edges in K batches (M in
   constructions kept)`, then `remove_roads summary ... failed=0 ... streets left=0`. Note `splits`/`failed` and the
   error text of any refused batch (detail lines). Are leftover nodes or dead-end stubs visible?
3. With towns still there (not frozen): do the towns rebuild streets? Are town streets refused (failed > 0)?
4. A station with its access road: the station's own street pieces stay, the rest goes.

## 6E. Junction test (rev 2, needs Roundabouts & Interchanges, not run in game yet)

New from a mod: a square_roundabouts construction built from the Stress Test's GUI state (`react.onStep`, the
showcase did it from a game script's guiUpdate), its arm ends read by a node diff, and long street proposals from
those ends to town nodes. Setup as 6B (empty Blank Slate map), plus Roundabouts & Interchanges enabled.

1. Without Roundabouts & Interchanges: the Towns tab shows only the hint line "Junction test: enable ...".
2. Junctions Roundabouts (4), 2 km, Medium, Map centre → "Build 4 junctions, 2 km". Expect 9 towns (3 x 3, no town
   links), then per cell `[SQST] junction_test Cell A1 Roundabout built ms=... nodes=N ends=4 arms=4 [1->Grid A1
   1->Grid A2 ...]`, then 16 link lines (detail, stdout.txt) and `junction_test summary junctions=4 built=4
   refused=0 arms linked=16 unlinked=0`. Look: is each junction turned 45 deg with its arms towards the four
   corner towns, and does each link road join a town street at the town's edge?
   **No red dead-end sign** (the HUD's "no entry" icon) at either end of a link road: first run
   (2026-10-11) had one at every arm end and town node a link joined, so no traffic could pass; the links
   now replace those nodes with new ones (docs/findings.md "Junction lane connections"). A sign there
   now means the fix did not work: note which end (junction or town) and paste the link's detail line.
3. If `ends=0`: the build's streets were not found by the diff (maybe they need longer than 1 s to appear, or the
   construction keeps its nodes): note `nodes=`. If arms go to `none`: an arm more than 60 deg off a corner.
4. Interchanges (6), 3 km: 4 x 3 towns, 6 junctions. Each highway arm should show `2->Grid ..`: both carriageways
   run on as a highway side by side to the town, close in over the last ~180 m and meet in one node 60 m before
   the town node, then a short town street joins it. Do the parallel carriageways keep their gap (no overlap)? Drive check: do cars use both carriageways in the right
   direction (no wrong-way one-way piece; the merge node's lane connections look sane)?
5. All types (10), 2 km: 6 x 3 towns. Note any `refused by the check: <reason>` (junction too big for 2 km? try
   3 km) and any `link refused at N node(s)` with its error text.
6. Run the game at speed 4-8 for a few minutes with towns grown (Grow, 2-3 passes): traffic between towns drives
   through the junctions. Note jams or cars turning back at a junction (lane connections on the merge node).
7. Clean up: Remove towns > Grid towns, then Remove all roads (the junctions are plain streets once built).

### 6E2. Road types and In line (2026-10-11, not run in game yet)
1. **Road types:** every roundabout's arms and every road link are "Country large" (main junctions too:
   `sqrb_arm_type` / `sqrb_ch_main` / `sqrb_ch_side` / `sqrb_ix_cross` = 6). Highway arms stay the
   interchange's highway and their links two carriageways. A "Construction Not Possible" that did not happen with
   town-road arms: note the junction (country large arms may need a bigger ring).
2. **In line**, Roundabouts (4), 4 km, Medium, In line = As many as fit: per road arm 3 extra junctions
   (`[SQST] junction_test Cell A1 Roundabout -> Grid A1 in line 1/3 <layout> built ... through=yes`), each turned
   along the route, then the chain links (`in line k/3 ... linked`) and the town link. Summary `in_line built=48
   refused=0 arms linked=64`. Look: are the stops on the straight line, their through arms on it, and the spare
   arms (side roads) dead ends? Do cars drive town to town through every stop?
3. Layouts cycle through `INLINE_ROAD` (1 lane, 2 lanes, Magic, splitters, Channelized X, 4 lanes, oval 2:1,
   Channelized T, T roundabout, Channelized X all slips, hamburger). Note every `refused by the check` with its
   layout: that layout needs another size with country large arms (stress_logic.tl INLINE_ROAD).
4. **Highways**, Interchanges (6), 8 km: highway arms get interchanges in a row (`INLINE_HIGHWAY`: Parclo A,
   Diamond, Roundabout Interchange, Parclo B, Dumbbell, Parclo 2 AB, Peanut), linked carriageway to carriageway
   (`sending link: ends=2->2`). Check both carriageways keep their direction through each one, and no red
   dead-end sign at a link end. Their cross roads are dead ends (no traffic on the ramps there).
5. `through=no`: the stop's arms were not found along the route (note the layout); the rest of that route is not
   linked (`the rest of this route is not linked`), its town gets no link from that arm.
6. With Smart Lanes (rev 4) on: every stop's ring and slip junctions get `[SQRL] APPLY` and `LIGHTS` lines.
7. (2026-10-11 run: links into stops refused while Smart Lanes' light commands were pending.) Now (faster builds,
   2026-10-11): the cell junctions are built back to back, then one wait (`[SQST] junction_test: 4 junctions built;
   reading their arms in 3 s`, detail line in stdout.txt), their arms read, then all in-line stops back to back,
   one more wait (`48 in-line junctions built; reading their arms in 3 s`), their `built ... through=` lines, then
   the links route by route. Before, every stop waited 3 s (and every cell junction 1 s): In line with 4 roundabouts
   and 48 stops waited about 148 s, now 6 s. A refused link still retries twice 3 s apart (`trying again in 3 s
   (2/3)`). Note any `link refused 3 times`, especially into the last stops built (they had only the 3 s): if
   those appear, raise INLINE_SETTLE_MS (gui/stress_junctions.tl). In Smart Lanes' `VERIFY kind=lights ...
   gone=N`, N > 0 means the light change replaced the node (record it in docs/findings.md).
   Every `built ... nodes=N ends=M ...` line now ends with `res_nodes=K`: K of the N new nodes were named by the
   build callback's resultEntities. Record K vs N in docs/findings.md (K = N: resultEntities name a freed
   construction's street nodes and could attribute them; K = 0: they don't). A stop placed `-160m along the
   route` (or -300 m on a highway) sits inside the previous stop's scan circle: its `built` line and the
   previous one's must still show only their own arms (same nodes/ends as other stops of that layout).
8. A stop refused at its spot tries 80 m (highway 150 m) back and forth along the route; the refused line now
   says what it hits (`(hits 3 town buildings, 1 streets)`). 10 junctions now use a 5 x 4 town grid.
9. The grid is fitted to the map: a spacing that does not fit is lowered (dialog "... do not fit this map (16 x 16
   km). Using 3.8 km ..."). On the 16 km Blank Slate map: All types at 3 km, any size, In line = As many as fit:
   about 3 stops per road route (road stop reach 150 m, gap 100 m, town reach 0.35 x the size's spacing).
10. **Highway town links** (2026-10-11 Showcase screenshot: the highway entered its town through a small street):
    the two carriageways now meet a large 4-lane street piece (the town node's own street if large, else the
    nearest large town / country street within 600 m, else as before the town node's own street), and links
    prefer town dead ends on large streets (up to 400 m further than the nearest; Wide grid towns: the corner
    stubs). Check at an interchange line's end town and a Junction test Interchanges town: the last ~60 m before
    the town node is a large road, not a small one. Road links copy the arm's country large road up to the town
    node as before.

## 6F. Wide streets and Clear traffic Where (rev 2, not run in game yet)

1. **Wide grid** (new: a Stress Test construction built from the GUI, then a town created on top of it). Test grid
   2 x 2, 2 km, Medium, Streets = Wide grid. Expect per town `[SQST] grid_2x2 Grid A1 street grid 600m era=1
   success=true` (stdout.txt), then the town. Look: a 600 m square grid of large 4-lane streets, no red dead-end
   signs, and the town's own streets/buildings on and around it. Does the town create fail or overlap the grid?
   Grow x5, 3 passes: do houses line the grid streets? If `street grid refused`, paste the line.
2. **Junction test** with Streets = Wide grid (the default): links should end at grid corners (the corners face the
   junctions).
2b. **Wide grid, locked** (2026-10-11): same as 1 with Streets = Wide grid, locked. Expect after each grid line
   `street grid locked edges=N success=true` (N about 250 for 600 m), then the town. Check with the game's Player owned
   road tool view (or a street's window) that the grid streets are locked, no red dead-end signs, and cars still
   drive the grid. Grow x5, 3 passes, unfrozen for a few game months: does the town still add streets off the grid
   (stubs from grid nodes, streets beside it)? The flag says "prevent towns from updating or extending this road";
   whether "extending" covers new side streets is the open question. Record the answer in docs/findings.md.
   Link roads joined later (Junction test) replace the stub ends: are those still locked? (they copy the edge)
3. ~~**Town streets = Wide**~~ REMOVED 2026-10-11: with only the large town street sim-buildable, Grow crashed the game (`simulation_util.cpp:116 GetStreetForTownDevelopment`, "Did not find any street template usable for town road development"; docs/findings.md). Skip this step. Was: (mod setting, reload): `[SQST] config` has no line for it; check in game whether
   unfrozen towns widen streets to the large 4-lane street (watch a busy town for a few game months). Unknown:
   whether new towns start with wide streets.
4. **Clear traffic Where = In towns** on the junction test with traffic: `[SQST] clear_traffic ... where=In towns
   towns=N kept=K unknown=U`. Cars on link roads and junctions keep driving, town streets empty. `unknown` should
   be 0: if it equals the number of drivers, neither position read works (paste the line). Then Keep traffic
   cleared every 5 s with In towns, and once Outside towns.

## 6G. Warning dialogs (2026-10-11)
1. Test grid at 6 km on a small map (or a point on water): a "Not enough space" dialog with the grid point and the
   reason, OK closes it. Nothing is built.
2. Press Build junctions twice quickly: a "Junction test" dialog says one is running.
3. A junction test with refused junctions (e.g. All types at 2 km, Large towns): after the summary a "Junction test"
   dialog lists them (at most 10) and suggests a larger spacing.
4. Remove all roads on a map without streets, Remove towns without towns: a dialog each.
5. Two warnings at once (press Build junctions twice while the first is still checking): shown together under
   "Stress Test", one OK.

## 6H. Crossing test (2026-10-11): input for Smart Lanes' crossroads rule
Towns tab > Crossing test (no Roundabouts & Interchanges needed), Size Medium, Lights Off, empty Blank Slate map.
Layout (stress_logic.crossingLayout, ~9 km across): rows west -> east at y = +1.5, 0, -1.5 km with 3, 2, 1 lanes each
way; columns south -> north at x = -1.5, 0, +1.5 km with 3, 2, 1 lanes; collector roads (2 lanes) 1 km beyond on each
side, T junctions where rows / columns end, a crossing in the middle whose outer arm goes 1.5 km to the town ("Grid
W/E/N/S"). Every junction is our crossing construction (stress_crossing.lua).
1. Expect `[SQST] crossing_test x12 Crossing 3x2 built nodes=5 arms=ENSW lights off at 1` for 21 junctions, then
   `crossing_test summary crossings=21 built=21 refused=0 links=36 linked=36 failed=0`. No traffic lights anywhere.
2. Unfreeze / grow the towns; at speed 4 watch W <-> E traffic straight along the rows and N/S <-> W/E traffic turning.
3. For the rule: pick a crossing with the Smart Lanes tool (`[SQRL] CONNS` / `CONN` = the game's default), set the lanes
   with the Crossing Tool (right turns only from the kerb lane, ...), pick it again; note its id (x12 = row 1 col 2:
   3 x 2 lanes). Most useful: x11 (3x3), x12 (3x2), x13 (3x1), x22 (2x2), a collector T (w1 = T 2 / 3).
4. Lights = Game decides: the same with the game's automatic lights.

## 6I. More car traffic (Phase 7, not run in game yet)
Load-time settings **Car traffic** (Default / Drive: destinations / Drive: all town buildings) and **Town building
capacity** (x1 / x2 / x4): a `loadScript` modifier wraps the town building scripts' `updateFn` and patches each
result's `personCapacity` (`disallowedMoveModes` += WALK, LINES; `capacity` x factor). Plan and unknowns U1-U6:
`MORE_TRAFFIC.md`. Use a **copy** of a save with 2-3 grown towns connected by road, game speed 4. Every reload
below = quit to the main menu, change the setting in the mod's settings, load the save again.

Log lines (stdout.txt, one set per Lua state that loads scripts, so they repeat a few dozen times per load):
- `[SQST] config car_traffic=<default|drive_destinations|drive_all> town_capacity=x<1|2|4> wrapped=N first=...`
  from runFn. `wrapped` is what that Lua state wrapped before this runFn: 0 is normal (scripts load after runFn).
- `[SQST] town_building_wrap wrapped=3 seen=S first=<file>,<file>,<file>` once 3 town building scripts are
  wrapped (U1: the modifier gets them, and this is what their file names look like).
- `[SQST] town_building_skip first=<file> (has updateFn, not a town building script)`: the first other script
  with an `updateFn` (stations etc.). If this shows town building files, the name filter is wrong: paste it.
- `[SQST] town_building_patch first=<file> type=<land use> modes=<list> capacity=<a>-><b> wrapped=N seen=S` for
  the first patched result (U2: the wrapper runs when a building is built or updated).
- Warnings: `[SQST] loadScript modifier failed` / `[SQST] town_building_patch failed` (one per state at most).

Traffic tab: **Scan** (new button on the Car traffic row) counts without clearing; the readout then shows a second
line `Last trip mode: DRIVE n (x%) / WALK n (x%) / LINES n (x%)` (every person's `lastMoveMode`) under
"Driving now", and the window log gets `[SQST] traffic_scan scanned=... drivers=... sent=0 ... modes=DRIVE:a,WALK:b,LINES:c`.
Clear traffic and Keep cleared lines now carry `modes=` too. Check the second readout line shows as its own line
(not cut off or joined).

1. **Baseline**: both settings Default. No `[SQST] config car_traffic` line and no `town_building_*` line. Traffic
   tab: Scan; note Driving now and the DRIVE / WALK / LINES split.
2. **Car traffic = Drive: destinations**, reload. stdout.txt: the `config` line, then `town_building_wrap` (U1) and
   `town_building_patch ... type=COMMERCIAL or INDUSTRIAL modes=WALK,LINES` (U2). Does the save load and do town
   buildings still build (no "Expected table", no load error)? Scan right after load and again after 2 game
   minutes (U4: do existing buildings already act on it?). Then rebuild one town: Towns tab Grow, Target Nearest
   to camera, Factor Reset to x1 (a town still at size factor 1 keeps its size; Grow always sends
   updateAllBuildings), Passes 1; then Scan again (U4). Optional (Show probe tab = On): Probe tab "9d Person
   capacity dump" reads the `pathfindingPreference` and capacity of the 3 town buildings nearest the camera; a
   commercial building should now list WALK and LINES.
3. **Car traffic = Drive: all town buildings**, reload, the same scans (U3: does the split move further towards
   DRIVE once homes also disallow WALK and LINES? i.e. does the setting act on trips to a building, from it, or both).
4. Watch 5 game minutes at speed 4: town ratings, cars stuck or circling, persons who never leave home, population
   trend, the game's own warnings (U5).
5. **Town building capacity = x4** (Car traffic Default), reload. `town_building_patch ... capacity=a->b` with
   b = 4a. Open one building's window: capacity before (step 1 save) and after; Scan. After a town develops for a
   few game minutes (or the rebuild of step 2), is the building still at x4 (U6)?
6. Back to both Default, reload: buildings keep the changed values until they are rebuilt (expected, the tooltips
   say so); rebuild a town as in step 2 and check a rebuilt building is back to normal.

Report: the `[SQST]` lines (one of each kind), the Scan numbers per step, and screenshots of busy roads.

## 6J. Traffic through the Junction / Crossing test (Smart Lanes PHASE7.md step 6, not run in game yet)
New row **Traffic** (Off / Bus lines) on both forms. Bus lines: when the test's last link is done, the summary line
`[SQST] Junction test done: 4 of 4 junctions built, 16 of 16 links; 8 bus lines queued.` (or `Crossing test done:
21 of 21 crossings built, 36 of 36 links; 4 bus lines queued.`) goes to the window log, and 5 s later a bus-lines
job (`bus_lines_junction_test` / `bus_lines_crossing_test`) builds one line per route: a stop on a free street of
each town, the first town's depot (found or built as in Auto bus lines), the Traffic tab's Auto bus lines **Buses**
count per line. Since 2026-10-12 (Showcase run): buses are bought only at a depot `findBestDepotForLine` confirms
for the line; without one a depot is built near stop 1 and asked again, else the line is destroyed before any bus
is bought; a bus whose SetLine fails is sold again; depot spots keep 400 m from the map edge and an unconnected depot
is removed again (6K item 5). Routes: Junction test, both diagonals of every cell whose two arms reached their towns (SW-NE and
SE-NW: both lines drive straight through the cell's junction and cross there), at most 40 lines; Crossing test,
W-E and S-N straight across the grid, then W-N and E-S turning. With Traffic Off the summary line is written
without the bus clause. Lines and buses count as Auto bus lines ("Remove added bus lines" removes them).
1. Junction test, Roundabouts (4 junctions, 3 x 3 towns), Traffic Bus lines, Buses 2: the summary, then
   `[SQST] bus_lines_junction_test: 8 bus lines between Junction test towns x 2 buses`, per line
   `bus_lines_junction_test town Cell A1 Grid A1 -> Grid B2 (id): 1 lines ok`, and the job's summary
   `towns=8 ok=8 ...`. In game: each line's two stops in two different towns, its buses driving through the
   cell's junction (the line window's route map), and both lines of a cell crossing each other there.
2. Crossing test, Traffic Bus lines: 4 lines Grid W -> Grid E, Grid N -> Grid S, Grid W -> Grid N, Grid E -> Grid S;
   the buses run along the rows / columns and turn at the collectors and crossings.
3. A busy bus-lines job when the test ends (start Auto bus lines with All towns just before the test's last link):
   `Busy: bus_lines_junction_test: bus_lines is still queued or running; wait for it to finish.` in a dialog, no
   test lines built. Pressing either test's button while the test's bus lines are queued or running: "A ... test
   is already running (bus_lines_...)".
4. A route whose stops cannot be placed (a town without free street edges): that line fails (`no free street edge
   in one of the towns`), the others go on; the batch stops after 10 failed routes in all (since 2026-10-12;
   Auto bus lines still stop after 3 failed towns in a row).
5. With Smart Lanes enabled: one `[SQRL] SUMMARY` per junction job in stdout.txt (Smart Lanes TESTING.md Q); compare
   the `ring=` / `slip=` / `cross=` counts with the junctions built.
6. Remove added bus lines: the test lines are sold / deleted; Remove towns > Grid towns and Remove all roads clear
   the rest (bulldoze leftover stops and depots by hand if needed).

## 6K. Showcase (rev 2, needs Roundabouts & Interchanges; first run 2026-10-12, its fixes not run in game yet)
Towns tab, section **Showcase** below the Junction test (only with Roundabouts & Interchanges enabled), options
Size (town size, default Small), Seed (New seed / Same as last (N)), Lights, Traffic. Layout (stress_logic
`showcaseLayout`, plans/square_stress_test/SHOWCASE.md), along the map's longer side, top to bottom: an interchange
line (town at each end, a highway of carriageway pairs through every interchange type in turn), a roundabout line
(a large country road through every roundabout type in turn), then a grid of groups (one roundabout, one town per
arm on a ring around it, joined to nothing else). Every placement draws its settings from the seed (sizes, lanes,
splitters, layouts, ramp lengths, levels, islands, ...; right-hand traffic only). On a 16 km map with Small towns:
17-19 interchanges, 29-32 roundabouts in line and 12 groups (about 50 towns); Medium 9 groups, Large 4, Huge 2
(2026-10-12 reach tables: was 13 interchanges and 32-38 roundabouts).
1. An empty flat map (Blank Slate), Remove towns > All towns, Remove all roads. Showcase, Size Small, Seed New,
   Lights Game decides, Traffic Off: Build showcase. First line `[SQST] showcase: seed=N map=…m towns=50
   (Small) lines ix=18 rb=… groups=12 ring=1200m …`; then `showcase_towns` creates the towns `Grid S1` … (Wide grid
   streets), then one line per placement, e.g. `[SQST] showcase Interchange line 3/18 Dumbbell Interchange at x,y
   angle=0 reach=300m [sqrb_ix_arm_length=2 …] built ms=… nodes=… ends=6 arms=4 through=yes reach est=300m
   measured=…m`, and `Group 4 Oval roundabout at … towns=4 reached=4`; the queue shows "Building the showcase".
   Order (faster builds, 2026-10-11): every placement is built back to back first (refusals logged as they come),
   then one wait (`[SQST] showcase: N junctions built; reading their arms in 3 s`, stdout.txt), then the placement
   lines above (arms read), then the links line by line and the group links.
   Since 2026-10-12 every placement line ends with `reach est=Nm measured=Mm` (and `bbox=Km` if the construction's
   bounding volume can be read); after the summary one `[SQST] showcase reach: <type> n measured, k over the
   estimate (worst +Xm); ...` line. **Record** any type with `over` > 0 (paste its placement lines): the estimates
   are offline-measured worst cases, so an `over` means the engine builds bigger than square_roundabouts' updateFn.
   A placement that would overlap the previous one's measured footprint logs `moved Nm along the line: ...` or
   `left out: ...` (counted as refused). Before, each placement waited 3 s:
   with ~60 placements (Small, 16 km) that was ~180 s of waiting, now 3 s, and the bus lines start 3 s (was 5 s)
   after the last link. Note any `link refused 3 times` into the last placements built (they had only the 3 s).
   Each placement line ends with `res_nodes=K` (see 6E2 item 7: record K vs nodes=N).
2. Watch: the interchanges sit in one row near the top edge, the roundabouts in a row below, the groups below that;
   no placement overlaps another or a town; every line ends in its two towns; every group arm reaches its town.
3. Summary: `[SQST] showcase summary seed=N placements=… built=… refused=… links=… linked=… unlinked=… splits=…`
   and the window line `Showcase done: X of Y junctions built, A of B links. Seed N.` Refused placements are left out
   (their line links past them) and listed in a dialog with the seed; note which types and settings (the placement's
   log line) are refused. **A failed link splits its line** (2026-10-12, was: ended it): `[SQST] showcase <line>:
   line split at k/n (link refused); the N built junctions after it are still linked to each other and to Grid S…`
   (or `(no through arm)` for a junction without an arm towards its neighbour); only that link counts as unlinked,
   the rest of the line is linked as usual, and a split line gets no bus route. Before giving up, an arm-to-arm link
   refused with `{Collision}` tries a bent route: `link refused (bent +50m) (...)`, then -50, +90, -90 (5 tries in
   all); success logs `linked ms=… (bent +50m)`. A town link refused with a collision takes the nearest town node
   through a point 60 m along the arm: `linked ms=… (nearest town node, 60m along the arm first)`. Interchange pair
   links copy the narrower highway's carriageways (the 2026-10-12 Roundabout Interchange -> Parclo collision).
   Between two different highways stdout.txt logs `<tag>: pair link copies <template> (ends Nm apart) into the ends
   of <template> (Mm apart)` once per link: at those joins watch for a lane of the wider highway that ends dead
   (the engine sets up the replaced end nodes' lanes; the two highways may differ in lane count).
   In game: watch the bent links and the lead-out bends (no kinks into buildings); paste every `split` line.
   Groups: `towns=N reached=N (k by the nearest arm)` and `<group>: Grid S… has no arm within 60 deg; linked to the
   nearest free arm (D deg off)` when a town has no arm in its direction (ovals: arms leave up to ~33 deg off).
4. Seed: Same as last (N) rebuilds the same layout and settings (after Remove towns > Grid towns and Remove all
   roads): the placement log lines match the first run's.
5. Traffic Bus lines: after the build, a bus line along each line linked end to end without a split (town to town)
   and across every group's ring, at most 40, built by `bus_lines_showcase`. Each route has its road network (`line
   1`, `group 3`): a depot is reused only within it (`depot=D (ours, Nm, group 3)`), new depots go on the route's
   first town's own streets, and no "existing" or "nearest anywhere" depot is taken. **Run with Car traffic =
   Default and capacity x1 first** (docs/findings.md sim crash). Expect per route either `buses from depot=D
   (findBestDepotForLine=D)` or, when the town's depot does not reach the line, a depot built near stop 1
   (`after depot D built 0-400m of stop 1`) or `no depot reaches the line ... destroyed=true` with **no** `bought
   bus=` line. A `setLine failed ...; sold again=true` must not leave a bus in a depot. Depot spots within 400 m of
   the map edge are skipped (`outside=N` in the depot line); a refused depot connection logs `not connected (...)`
   and `depot D removed=true`, then the next spot.
6. With Smart Lanes enabled (Apply automatically) every placement gets its lanes: after the build, `make audit`
   reports on all of them (one `[SQRL] AUDIT` block per junction); compare its junction count with `built=`.
7. Busy: pressing Build showcase, the Junction test or the Crossing test while another of them (or its bus lines) is
   queued or running: "A test is already running (…)" in a dialog, nothing started.
8. Clean-up: Remove towns > Grid towns removes every `Grid S…` town; Remove all roads the junctions and links.

## 6L. Showcase second chances and bus-line dialogs (rev 2, 2026-10-12 run #2 fixes; not run in game yet)
Note 2026-10-12: Showcase v2 (6N) has no options and no line placements: the Showcase parts of items 1-3 (its
up-front money dialog, Seed Same as last, moves along a line) are gone; the Junction / Crossing test parts stay.
Background: plans/square_stress_test/SHOWCASE.md "In-game run 2026-10-12 #2" (E-H).
1. Bus lines without money: a fresh Blank Slate (costs on), Game tab Keep balance **unticked**. Showcase, Traffic Bus
   lines, Build showcase: at once a dialog "Showcase: Traffic is Bus lines. Keep balance (Game tab) is off: ..."
   and the build starts anyway. Same for the Junction test and the Crossing test with Traffic Bus lines (titles
   "Junction test" / "Crossing test"); no such dialog with Keep balance ticked, with No costs, or with Traffic Off.
   After the build (balance far below 1M): a dialog "Showcase bus lines: Bus lines not added: the balance -N is
   below 1M. Tick Keep balance (Game tab) or add money, then build the Showcase again: ..." next to the log line
   `bus_lines_showcase stopped: balance ...`. Auto bus lines (Traffic tab) with a low balance: the same dialog
   titled "Bus lines", ending "then press the button again.".
2. Then tick Keep balance, Remove towns > Grid towns, Remove all roads, Seed Same as last, Build showcase: no
   up-front dialog, and `bus_lines_showcase` lines are built (6K item 5).
3. Second chances (stdout.txt `[SQST] showcase`): a placement refused with "Construction Not Possible" logs
   `refused by the check: Construction Not Possible; redrawn` (the refused params on that line), and then either
   its built line `... [new params] (redrawn) built ...` or `refused by the check: ... (first: Construction Not
   Possible)`. A line placement refused with a Collision logs `...; moved Nm along the line towards the previous
   / next one` and is built there (its links reach it; no overlap with its neighbours). The dialog lists each as
   `<tag>: <first verdict>, then redrawn / moved ... (the refused params are in the log)`. **Record** every
   refused line with its params, and how often the redraw / move helped (summary `refused=`).
4. A Collision line now names what it hit: `(hits 12 other ASSET_GROUP e.g. #N)` or similar. **Record** the kinds
   (seed 747943 had `hits 12 other` at Interchange line 11/17: what is it?). If it is ASSET_GROUP / FIELD /
   MODEL_INSTANCE_LIST, look at the spot (trees, rocks?) and note it in docs/findings.md.
5. The refused settings alone (with the construction menu, flat spot, Rotation 0, no other roads nearby): the
   params of seed 747943's Roundabout line 4/32 and 30/32, Group 7 (Rotation 180) and seed 204313's Roundabout
   line 13/35 (all in SHOWCASE.md; param values are 1-based option indices). Red in the menu too = a square_roundabouts layout bug
   (4/32 is predicted by its engine model: oval, 1 lane, small radius, large arms, no splitter); green = something
   in the Showcase's spot or timing: note which.

## 6M. Flow probes 11a-11h (Probe tab, 2026-10-12, not run in game yet)
Background: plans/square_stress_test/FLOW_PLAN.md step 0, log contract FLOW.md. Eight read-only probes (they send no
command and build nothing) that answer the traffic log's open questions. Needs "Show probe tab (developers)" On
(reload). Each writes `[SQST] probe 11x ...` lines (stdout.txt only) and ends with one
`[SQST-PROBE] flow_11x_<name> ok|fail ...` line (also in the window log). Every probe reads at most 25 items per frame
(11c: 10 queries), so a probe takes a few seconds; 11f takes 10 s more.
1. Map state: a Showcase build (6K) with Traffic **Bus lines**, Lights Game decides, Small towns, finished
   (`showcase summary` and the `bus_lines_showcase` lines done), Smart Lanes enabled. Then let the game run at speed
   4 for **3-5 game minutes** so car traffic and the buses are under way (Keep traffic cleared **off**). Any running
   map with towns, car traffic and at least one SQST Bus line will do for 11a-11f and 11h.
   **Save first**: 11c and 11h call engine functions (`getSimPersonsMovingForTransportNetwork` on street edges and
   nodes, `calcPathPosData` on private cars) on entity kinds no code here has used them on in game yet; pcall can't
   catch a native assert.
2. Move the camera to a roundabout of the roundabout line (centre of the screen on the ring, zoomed so the ring
   fills about a third of the screen): 11c, 11g and 11h read within 300 m of the camera centre.
3. Probe tab: press 11a, wait for its `[SQST-PROBE] flow_11a_movepath` line in the window log, then 11b, 11c, 11d,
   11e, 11f (wait for `flow_11f_bus`, ~12 s), 11g, 11h, one at a time. 11b-11h reuse 11a's 200 drivers for 20 s
   (`reused sample` in their line), so press them soon after 11a, or they take a new sample.
4. Then move the camera to an interchange of the interchange line and press 11g again; then to a group roundabout
   (town ring) and press 11c and 11g again.
5. Save, reload the save, and press 11g at the same roundabout again (do placements survive as CONSTRUCTION entities
   after a reload?).
6. Optional: pause the game (speed 0) and press 11f: the `gameTime delta` should be 0.
7. **Paste back** every line of stdout.txt containing `probe 11` or `flow_11` (e.g.
   `grep -E "probe 11|flow_11" stdout.txt`), and note the game speed during each probe. What they decide (FLOW.md
   "What the probes answer"): 11a the MOVE_PATH read cost and whether `dyn.speed` is in m/s (`speed/speedLimit` med
   below ~1.2, `getSpeed/dyn.speed` near 1); 11b whether a car crossing a junction is on a `node` entity; 11c whether
   `getSimPersonsMovingForTransportNetwork` works on street edges / nodes (`expectedFound` near n/n; `no_tn` = entities
   without a TRANSPORT_NETWORK component, skipped) and its cost;
   11d whether VEHICLE_ORDER exists and what `blocked` means; 11e the town traffic map's cost from the GUI; 11f the
   units of game time, sectionTimes and departures; 11g whether placements stay constructions and edges carry
   PLAYER_OWNED; 11h position cost. **Record** any `fail` line in full, and any `firstError:`.
8. Watch: no stutter while a probe runs (each spreads its reads over frames); the game state is unchanged (no road,
   vehicle or money change; the window log shows no `cmd` line).

## 6N. Showcase v2: one button, groups only, A/B twins (rev 2, 2026-10-12; not run in game yet)
Background: plans/square_stress_test/SHOWCASE.md "Showcase v2" and "Twins". Map: a fresh 16 km Blank Slate, Remove
towns > All towns; Roundabouts & Interchanges and Smart Lanes enabled. Game tab Keep balance **unticked**, costs on.
1. Towns tab, Showcase: only a description and the "Build showcase" button (no Size / Seed / Lights / Traffic rows).
   Press it: no money dialog; the Game tab's Keep balance box ticks itself; stdout.txt has
   `[SQST] showcase keep_balance=on (was off)` and `[SQST] showcase: seed=N map=16384x16384m groups=G sets=S
   interchanges=.. roundabouts=.. plain=.. twins sl=.. game=.. sl_phases=.. towns=T (Small / Medium)`. **Record**
   the line (offline, seed 4242: 22 groups in 10 sets, 6 ix / 8 rb / 8 plain, 87 towns).
2. While it builds: the window's queue line shows the progress; Junction test, Crossing test, Remove all roads and
   Remove towns refuse with a busy dialog.
3. Look at the map: groups of one junction with 3-6 towns close around it (Small and Medium mixed), twins of each
   group side by side in a row (same junction, same rotation, same town sizes), groups not joined by any road.
   Interchanges: their two highway arms reach their towns as two carriageways merging into a large town street;
   their cross road arms as large country roads. Plain crossroads / T-junctions of ordinary streets with different
   lanes per arm and angles from 60 to 120 deg; some with lights, some without (`lights=off` on their line, then
   `lights off at 1`); a lit plain set has three twins (a, b, c).
4. Per placement in stdout.txt: `[SQST] showcase zone id=g3a pair=g3 ab=sl kind=... type=... x= y= r= r_from=measured
   towns=..` before its `Group 3a ... built ...` line; ab is sl / game (and sl_phases for c). **Record** any
   `r_from=est` (measured nothing at the callback or the read) and any `measured=..m` far above `reach est=`.
5. Summary: `[SQST] showcase summary seed=N groups=.. built=.. refused=.. interchanges=a/b roundabouts=a/b
   plain=a/b sl=a/b game=a/b sl_phases=a/b links=.. linked=.. unlinked=.. towns_skipped=.. sets_mismatch=..` and the
   window line `Showcase done: ... (sl a/b, game a/b, sl_phases a/b), .. of .. links; N bus lines queued. Seed N.`
   A dialog only when something was refused or a town skipped (it starts with the same summary). **Record** every
   refused placement (params on its line; a "Construction Not Possible" is redrawn once, `(redrawn)`). Twins
   refused alike redraw alike and keep `match=yes`; when only one twin of a set was redrawn (or a redraw was refused
   again), every twin of that set logs `match=no reason=redrawn` on its zone line and counts in `sets_mismatch`:
   **record** which sets and how often. A town whose spot fails the land check logs `showcase_towns Grid SN at x, y:
   town skipped: no land (...)` and is left out (no "Not enough space" dialog, the build goes on): its arm stays
   unlinked, its set logs `match=no reason=town`, `towns_skipped=` counts it and the window line says `N town(s)
   skipped (no land)`; on a flat Blank Slate expect `towns_skipped=0`.
6. Bus lines: `bus_lines_showcase` adds lines across every group, the same arm pairs in each twin of a set (at most
   40, whole sets), none to a town on a one-way side road; they are not skipped for money. Buses run on both
   twins.
7. Press Build showcase again on the same map after Remove towns > Grid towns and Remove all roads: a different
   seed in the first line, `keep_balance=on (was on)`.
8. ~~Smart Lanes does not yet treat `ab=game` twins differently~~: it does now, see 6O.

## 6O. Showcase twins get their modes in Smart Lanes (rev 2, zones channel 2026-10-12; not run in game yet)
Background: SHOWCASE.md "Twin modes in Smart Lanes", FLOW.md "[SQRL] ZONES". Smart Lanes side: its TESTING.md "ZN".
Map as 6N (16 km Blank Slate, towns removed), Roundabouts & Interchanges and **Smart Lanes enabled**, Smart Lanes
settings at their defaults (Light phases: Game default, Apply automatically On).
1. Build showcase. stdout.txt, in this order: `[SQST] showcase: seed=..`, `[SQST] showcase zones sent n=G run=s<seed>-..
   by_ab=game:a,sl:b,sl_phases:c smart_lanes=yes` (G = groups of the first line, by_ab = its twins counts), then
   Smart Lanes' `[SQRL] ZONES op=set n=G run=<same> by_ab=<same>`, the towns, then `[SQST] showcase zones ack=yes run=<same>
   ms=..` before the first `Group 1a ...` line. **Record** the ack ms (expect 0: the towns take longer).
2. Per group set, look at the twins (Crossing Tool / Smart Lanes tool hover, or the lane arrows):
   - b (`ab=game`): the game's own lanes (lanes cross at a crossroads, the game's ring lanes, traffic lights where
     the game put them, its six default phases at a lit crossing in the Crossing window). Smart Lanes logs `SKIP
     kind=zone zone=game job=.. nodes=.. reason=zone_game` for its job and `SUMMARY ... skips=zone_game:N`; no
     APPLY / LIGHTS / PHASES line names its nodes.
   - a (`ab=sl`): Smart Lanes lanes as without zones (APPLY lines; lights removed at rings / slips with Remove traffic
     lights On; Game default phases re-pointed).
   - c (`ab=sl_phases`, lit plain crossings only): Smart Lanes lanes plus `PHASES src=auto node=.. phases=sl plan=..`
     (or `plan_fail=lit_unknown` then `RECHECK kind=phases ... sent=1`), `SUMMARY ... phases=game sl_plans=1 ...
     zone_phases=1`; the Crossing window shows the planned phases (all-reds, protected turns), unlike twin b.
3. The towns' streets and the links between arm ends and towns stay normal Smart Lanes (outside the zones), except
   arm-end nodes inside a game zone (skipped like the junction). Note any junction node of a game twin that got an
   APPLY line (a zone too small: compare its `showcase zone ... r=` with `measured=`).
4. Save, quit to the main menu, load: Smart Lanes logs `[SQRL] ZONES op=loaded n=G run=<same>` once after `MODE`.
   Build a plain crossroads by hand inside a game twin's circle: left at the game default (`SKIP kind=zone`); the
   same next to an sl twin: Smart Lanes lanes.
5. Smart Lanes tool in a game twin: select its junction, Apply to junction: it is written (manual override), the
   `APPLY src=tool ...` line ends in `zone=game`.
6. Remove all roads: `[SQST] showcase zones cleared by=remove_roads run=.. smart_lanes=yes` and `[SQRL] ZONES op=clear
   n=0`. (Remove towns > Grid towns / All towns: `by=remove_grid` / `by=remove_all`; the nearest town: nothing.)
7. Without Smart Lanes (disabled, reload): Build showcase logs `zones sent ... smart_lanes=no` and `zones ack=absent
   ... ms=0`, no wait, no error; every twin keeps the game's lanes.
8. Paste back: `grep -E "SQST\] showcase (zones|zone |summary)|SQRL\] (ZONES|SKIP kind=zone|SUMMARY|PHASES|ERROR)"
   stdout.txt` and a screenshot of twins b and c of one lit plain set in the Crossing window.

## 6P. Showcase bus lines: depot gates and own-town spots (rev 2, 2026-10-12 seed 488838 fixes; not run in game yet)
Background: SHOWCASE.md "In-game run 2026-10-12 #3", docs/findings/lines-vehicles.md "Script-built road depots".
Map as 6N, Traffic Bus lines (the Showcase always queues its bus lines), Buses 5.
1. Depot gates. stdout.txt `[SQST] bus_lines_showcase <route> depot <ring>: ...`: every sent try ends in `connect:
   success=.. streetEdges at node 1->2 laneConns A->B (entrance edge E, stub ::/infrastructure/street/town/
   town_new_small.street_template) connected=..`. **Record**: is any connect still refused `Construction Not
   Possible` (and with what `laneConns`), and B for the connected ones (expect 2; 0 = the gate is a dead end, the try
   counts as not connected and the depot is removed). In game, click a new depot's gate: no red no-entry sign; the
   short street to it is the small town street.
2. Own-town spots: no depot or stop on a link road, a junction arm or within ~100 m of a junction; each sits on the
   town's grid (the outer street of a 600 m / 400 m grid at most). The ring notes log the edges left out:
   `rings: 300-700m edges=N rejected={highway=..,oneway=..,not_town=..,outside_town=..,zone=..}`.
3. Lines: per route `bus_lines_showcase i/N <route> ok ... buses from depot=D (findBestDepotForLine=D) buses=5/5`.
   A route that still fails names its depot's gate: `no depot reaches the line (findBestDepotForLine=-1; depot D: how,
   gate node=N streetEdges=E laneConns=L) ...`. **Paste** those lines (laneConns > 0 there means the gate is fine and
   the route itself is the problem: note the group's type and twin, `ab=` in its `showcase Group` line).
4. Failed routes don't stop the batch: `... failed after 0 lines: ... (k/10 failed routes, going on)`; the batch
   stops only at 10 failed routes (`stopped after 10 failed routes`). Summary `towns=40 ok=.. failed=.. wastedStops=..`:
   **record** ok / failed / wastedStops.
5. Paste back: `grep -E "bus_lines_showcase" stdout.txt | grep -E "depot rings|fail|ok ms|summary|laneConns"` and a
   screenshot of one new depot's gate.

## 6Q. Node configs on every script node (rev 2, 2026-10-12; not run in game yet)
Background: docs/findings/roads.md "Script link roads without node configs" (every `Engine.h:323` `BaseNodeConfig`
crash in the log archive followed config-less script nodes; the Showcase's links left 37 such nodes). Now every
proposal of the mod (`gui/stress_nodecfg.tl`) gives each node it adds a config, and a joined existing node a full one.
Map as 6N with Smart Lanes enabled; run the Showcase (and once the Junction test, set Interchanges, In line on).
1. `grep -c "reason=no_config" stdout.txt` after the links: **expect 0** (was 37 for seed 204313). Paste any line
   left, with the `showcase ... linked` line before it.
2. No `Engine.h:323` / `Engine.cpp:693` assert during links, bus lines or the 10 minutes after (speed 4, towns
   growing). If one comes: paste the assert block (entity, component type) and the 30 lines before it
   (`make logs-grep PAT='Engine.h:323' ARGS='-C 30'`).
3. Traffic: cars and buses drive through a link's town node and, on an interchange arm, through the merge node in both
   directions (no red dead-end sign on any link node; no U-turn at the merge node).
4. Junction test In line on highway arms: the linked carriageway pairs carry traffic both ways through the replaced
   ends.

## 6R. Traffic log (rev 2, FLOW_PLAN.md steps 4-5, 2026-10-12; not run in game yet)
Background: plans/square_stress_test/FLOW.md "[SQST] FLOW_*" (every key), FLOW_PLAN.md. Reads only; the report is
`make flow` (tools/flow_report.py). Smart Lanes enabled (rev 4 with the zone labels), Roundabouts & Interchanges
enabled. Keep traffic cleared **off**.
1. Map: load the save with the seed 488838 Showcase (session 2026-10-12_0905 in `.cache/logs`), or build a fresh
   Showcase as 6N on a 16 km Blank Slate (wait for `showcase summary` and the bus lines).
2. Traffic tab > Traffic log: Every 30 s, tick it. stdout.txt: one `[SQST] FLOW_START run=1 v=2 interval=30
   interval_unit=game_s zones=Z ... gt_per_s=1000 src=placement|sl_zones sc_run=..` (window log too), then Z
   `FLOW_ZONE` lines. **Record** `src` and Z: a fresh Showcase gives `src=placement` and Z = the `showcase zone`
   lines; the reloaded save `src=sl_zones` with `id_from=sl` (Smart Lanes with labels) or `id_from=order` (zones
   sent by an older Stress Test: ids recomputed; spot-check 3 zones against the old `showcase zone` lines by x / y).
   On the reloaded save, Z = Smart Lanes' `[SQRL] ZONES op=loaded n=`.
3. Game speed 4, run 15-20 game minutes (~4-5 wall minutes). The status line under the toggle counts samples and
   shows `last sweep N ms in F frames, D drivers`. **Record** a typical N, F and D. Watch for stutter: none expected
   (2 ms per frame at most); note any frame-time spike the game's FPS overlay shows during a sweep.
4. stdout.txt per sample: Z `FLOW` lines (zones without cars too: `cars=0 ... v_mean=-`), one `FLOW_ALL`, one
   `FLOW_BUS` per SQST Bus line (`twin=g.. pair=.. ab=.. twin_from=session|stops`; after the reload `stops`), and
   every 60 s wall `FLOW_TOWNS` (scope=all + one per town). Every 10 samples a `FLOW_SUMMARY ... final=0`.
   **Record** from a FLOW_ALL: drivers, sampled, in_zones, persons, sweep_ms, elapsed_ms, capped; from FLOW_TOWNS
   scope=all: ms. Check: `skipped=0` in the summaries (else note the game speed and interval).
5. Bus units (provisional, FLOW.md FLOW_BUS): pick one line's `raw_deps` over two samples 30 game s apart: the
   values are game ms like `gt` (the first stop's departure jumps by the round trip, ~6-7 game min); `raw_sections`
   are seconds that sum to roughly `rt_mean`; `lap_mean` a bit above `rt_mean` (dwell). Paste three FLOW_BUS lines.
6. Turn on Traffic tab > Keep traffic cleared: a dialog "Traffic log: Keep traffic cleared is on ...", the next
   summary has `warn=keep_cleared:N`. Turn it off again. Change Every to 10 s: `FLOW_SUMMARY ... final=1` then
   `FLOW_START run=2 ... interval=10`. Pause the game for a minute: no samples while paused.
7. Untick: `FLOW_SUMMARY run=2 ... final=1` (window log too). Clear queue while it runs also stops it (`final=1`, the
   box unticks).
8. `make flow` (or `make flow ARGS=--last`): the report lists "Twins: per zone" with every twin, "Twins: per pair"
   with sl vs game (and sl_phases vs game) per set, "Bus lines (FLOW_BUS)" paired by twin, "Towns" and "Sampler runs".
   Paste the report's per-pair table and the Sampler runs table, plus `grep -E "FLOW_(START|SUMMARY)" stdout.txt`.

## 6S. Lights showcase (rev 2, 2026-10-12; not run in game yet)
Background: SHOWCASE.md "Lights showcase". Map: a fresh **16 km** Blank Slate (four twins in a row need ~14-16 km
of width), year **1950 or later** (Game tab > Date), Remove towns > All towns. (Since 2026-10-13 the fourth twin d
is `sl_lock`, "Kerb locked" towns, not `sl_fan`: read sl_fan below as sl_lock; step 4 of 6U has the checks.) Smart
Lanes enabled (rev with sl_lock zones), Apply automatically On, its settings at the defaults; Roundabouts & Interchanges not needed. Keep balance
unticked, costs on.
1. Build. Towns tab, Lights showcase: a description and the "Build lights showcase" button only (no option rows);
   it is there without Roundabouts & Interchanges too. Press it: Keep balance ticks itself; stdout.txt has
   `[SQST] lights_showcase keep_balance=on (was off)`, then `[SQST] lights_showcase: seed=N map=16384x16384m
   groups=16 sets=4 crossroads=.. t_junctions=.. twins sl=4 game=4 sl_phases=4 sl_fan=4 towns=T (Medium / Large)
   lights=yes year=Y grow=x10 passes=3` (offline: 16 groups / 4 sets / 56-60 towns for every seed tried; seed 4242:
   12 crossroads + 4 T, 60 towns), `[SQST] showcase zones sent n=16 run=.. by_ab=game:4,sl:4,sl_phases:4,sl_fan:4
   smart_lanes=yes`, Smart Lanes' `[SQRL] ZONES op=set n=16 ... by_ab=<same>`, then `zones ack=yes`. **Record** the
   seed line. Before 1950 (try once, e.g. 1930): a dialog "The year is 1930: the game builds no traffic lights
   before 1950 ..." and `lights_showcase year=1930 before 1950`; the build goes on.
2. Look at the map: 4 rows, each one set of 4 twins side by side (Group Na, Nb, Nc, Nd: same crossing, arm roads and
   town sizes); square layout (SHOWCASE.md "In-game run 2026-10-12 #4"): every crossing at 90 deg and axis-aligned
   (`angle=0`, `sqst_x_angle=1`), its arms COUNTRY roads (no sidewalk kerbs; lanes differing per arm, 1-3 each way);
   a Medium or Large town exactly north / east / south / west of it (T: three), all at one distance; each link one
   straight country road along the axis into the MIDDLE of the town's facing side (where the grid's central street
   meets the perimeter), never a corner, never another town; no roads between groups. Screenshot one set top-down.
   **Record** any `-> Grid Sn: not linked (...)` line (the reason names the town and the side's middle point) and
   any `link refused (... (hits ...))` (what it collided with). An unlinked arm gives `[SQST] showcase zone_match
   id=gNx pair=gN match=no reason=link` for every built twin of that set after the links, and `sets_mismatch=` counts it.
3. Per placement: `[SQST] lights_showcase Group Nx Crossroads|T-junction at .. lights=yes [.. sqst_x_lights=2 ..]
   built ... lit=<node>:pref=yes|auto|?,light=yes|no`. **Record** the pref / light pairs: `pref=yes` means the
   construction's light request took (trafficLightYes / trafficLightNodePreference; square_roundabouts' signals
   use the same fields); `pref=auto,light=no` means it did not and AUTO had not lit it yet: the read then sends Yes
   (`lights forced on at 1`, the dialog lists the twin: "no light at the read; set to Yes (its Smart Lanes phases may
   be missing)"). Every junction must end up lit: check one set of each kind in game.
4. The four twins of one crossroads set and one T set (Crossing window: click the centre node; Smart Lanes tool
   hover for lanes):
   - b (`ab=game`): the game's lanes and its six default phases; Smart Lanes `SKIP kind=zone zone=game ...`.
   - a (`ab=sl`): Smart Lanes lanes, phases as the global Light phases setting (Game default: re-pointed).
   - c (`ab=sl_phases`): Smart Lanes lanes plus `PHASES src=auto node=.. phases=sl plan=..`: the planned phases
     (all-reds, protected turns) in the Crossing window.
   - d (`ab=sl_fan`): the full fan (every entry lane to every exit lane of the other arms) and its split phase plan,
     one approach per phase: `APPLY ... mode=fan`, `PHASES ... plan=x4_fan|t3_fan`, SUMMARY `zone_fan=..`. A forced
     light (step 3) may give `fan=unlit` then `RECHECK kind=phases ... sent=1`: **record** whether d (and c) still got
     their plans after a forced light.
   Screenshot the Crossing window of twins b, c and d of one crossroads set.
5. Summary: `[SQST] lights_showcase summary seed=N groups=16 built=16 refused=0 crossroads=a/b t_junctions=a/b sl=4/4
   game=4/4 sl_phases=4/4 sl_fan=4/4 links=T linked=T unlinked=0 towns_skipped=0 sets_mismatch=0` and the window
   line `Lights showcase done: .. of .. lit crossroads, .. of .. lit T-junctions built (sl 4/4, game 4/4, sl_phases
   4/4, sl_fan 4/4), T of T links; every town then grows x10 in 3 build-out passes, locked to its grid; N bus lines
   queued. Seed N.`
   **Record** refused placements and mismatched sets (dialog and log, as 6N step 5).
6. Growth, then bus lines (since the grid lock: 6T has the lock and leak lines): `[SQST] lights_showcase grow queued
   towns=T factor=x10 passes=3 weights={0,0.1,0.5,1} locked=true ...`, the queue line "Growing x10, locked to the
   grid", per town `lights_showcase_grow town <name> pass p/3 ... buildings a->b`, then `lights_showcase_grow dense
   summary towns=T factor=x10 passes=3 ... buildings a->b ...`. **Record** the summary and how long it took (wall). Only then `bus_lines_lights_showcase` (lines across every twin, the same arm pairs in all four twins of a
   set, at most 40). Check that grown towns did not reach a junction or another group's town (screenshot if so).
7. Traffic log: tick Traffic tab > Traffic log, Every 30 s, before or after the build. After the bus lines it
   restarts by itself (`traffic log run N stopped: zones changed`, a new `FLOW_START ... zones=16 src=placement`,
   16 `FLOW_ZONE` lines, twins a-d). Game speed 4 for 20 game minutes, then `make flow`: the per-pair table now also
   has `sl_fan vs game` and `sl_fan vs sl_phases` rows. Paste the per-pair table and `grep -E "FLOW_(START|SUMMARY)"`.
8. Busy guards: while it builds (or grows, or adds bus lines) the Showcase, Junction test, Crossing test, Remove all
   roads and Remove towns refuse with a busy dialog; the Lights showcase refuses while a Showcase runs.

## 6T. Showcase towns locked into their grids (rev 2, 2026-10-12; not run in game yet)
Background: SHOWCASE.md "Town growth locked into the grid". Same setup as 6N (Showcase: 16 km Blank Slate, year
2000+, Roundabouts & Interchanges and Smart Lanes enabled; Remove towns > All towns first); then once more with the
Lights showcase (6S setup). Keep the stdout.txt of each run.
1. Lock after the towns: right after `showcase_towns summary ...`, one `[SQST] showcase_lock town Grid Sn lock
   pass=towns edges=N unlocked=U ... locked=L refused=0 failed=0 batches=B ...` per town and `[SQST] showcase_lock
   summary pass=towns towns=T locked=.. failed=0 ...`, all before the first `Group 1a ... built` line. **Record**
   `unlocked=` of a few towns (the town's own seed streets) and any `refused=` / `failed=` above 0.
2. Links locked: click a link road and a grid street with the street info (or Organic Towns' dev tool if enabled):
   both locked (no town changes). Smart Lanes must not log `reason=no_config` after the links.
3. Lock after the links: `showcase_lock town .. pass=links ... zone_streets=Z ... stubs=S removed=S` per town (Z:
   unlocked streets in its junction's zone, the crossing's unlinked arms; locked now), summary `stubs_removed=
   .. stubs_kept=0`. Lights showcase: all four stubs of every town go (links join the sides' middles). Look at 3 towns' corners: no 60 m dead-end stub left except the one a link uses; no red dead-end
   sign at a corner.
4. Density: `[SQST] showcase grow queued towns=T factor=x10 passes=3 weights={0,0.1,0.5,1} locked=true`, per town the
   detail `showcase_grow town <name> weights={0,0.1,0.5,1} success=true read_back={0,0.1,0.5,1}` (**record** the
   read_back: nil means the command did not take), per pass `pass p/3 ... buildings a->b` and the leak line
   `[SQST] showcase_grow town <name> outside_streets=N houses_outside=M pass=p/3 ...`.
5. Pass criteria, from the final lines (`... final buildings=B ...`) and the screenshots: **`outside_streets=0` on
   every final leak line**, `houses_outside` only a few per town (houses behind the outer streets beyond 45 m),
   **`houses_perimeter=0`** (houses just outside the outer street: the outer ring is now a country road, which
   should get none; SHOWCASE.md "Country ring"), **no houses along any link road** (country roads; a screenshot of
   one link after x10), and **no street the town built around a junction** (`zone_streets=` on the leak lines: 0, or
   locked at once; the "links" lock pass may report the crossing's own unlinked arms there), the outer blocks of the
   grid still with houses on their inner streets (if the town stalls at its edge, note it: the ring can go back to
   town streets, `sqst_grid_ring` 1),
   no street the town built outside its grid in a top-down screenshot of 3 towns (one Small, one Medium, one
   Large/Lights), and a dense centre: `town <name> levels 1:a 2:b 3:c 4:d centre ...` with mostly level 3-4 in the
   centre. **Record** the `dense summary` line (buildings a->b, outside_streets, houses_outside, locked, levels) and
   compare the levels with a Grow x10 of a plain Test grid town (no weights) if time allows.
6. Leak locking: any `locked=` above 0 on a pass's leak line means the town built a street during the pass and it was
   locked; **record** how many over the run. Any `lock batch .. refused` line: note the node (pending light?) and
   whether the retry went through.
7. Later growth: leave the game running 2 game years at speed 4 (towns keep developing), then screenshot the same 3
   towns: still nothing outside the grid? (A new street there would be unlocked: Grow on the nearest town shows it.)
8. Test grid "Wide grid, locked" (6B / 6F): the lock is batched: `grid_.. Grid A1 street grid locked
   edges=N locked=N batches=1..3 refused=0 failed=0 success=true`. Behaviour change: its outer ring (perimeter
   streets + corner stubs) is now the country road (`sqst_grid_ring` 2, as the Showcases), so no houses outside the
   perimeter; check the outer blocks still get houses on their inner streets and that "Roads = Neighbours" town links
   and the Junction test's links (corner stub tips, now country dead ends) still join.

## 6U. Faster Lights showcase + batched building (rev 2, 2026-10-12; not run in game yet)
Background: SHOWCASE.md "Faster, simpler Lights showcase + batched building". Setup as 6S: 16 km Blank Slate, year
1950+ (Game tab > Date), Smart Lanes enabled, Remove towns > All towns first. Keep stdout.txt.
1. Press **Build lights showcase (2x2 X)** and note the wall-clock time. The first `[SQST] lights_showcase:` line ends
   in `shape=1/4 (2x2 X) bus_lines=no`; the button then reads "(3x3 X)". **Pass: about 2 minutes** until
   `[SQST] lights_showcase finished in N.N min`; **record** the `[SQST] lights_showcase timing towns=.. grids=..
   locks=.. junctions=.. links=.. depots=0 density=.. total=..` line (expected roughly: towns 10-60 s for one create
   command, grids 5-10 s, locks 10-20 s, junctions 15-25 s, links 5-15 s, density 60-90 s; any phase far above that
   is the next target).
2. Batches in the log: `lights_showcase_towns towns batch: one command for N towns success=true ... matched=N
   missing=0` (**record** `ms=`; `missing>0` / `far>0` or "createTowns gave" means the batch fell back, note it),
   `street grid ... batch c/n grids=10`, `street grids locked grids=N edges=E ... refused=0 failed=0`, `links: N in P
   proposals`, `linked ms=.. (one proposal of 8 links)`. Any `street grids batch .. refused`, `link group of .. refused
   (...)` or `lock batch .. refused` line: **record** it with what it hit (the piece then went alone).
3. Square layout: top-down screenshot of 2 sets: every set the same 2x2 X junction, towns straight N / E / S / W,
   links straight into the middle of each grid side; no houses along links or outside the country ring; the final
   leak lines all `outside_streets=0`. Town size (user 2026-10-12): every town **Medium** (8 x 8 blocks, 600 m grid),
   none Large: the first line reads `towns=N (Medium) ... grow=x3 passes=1`, and a 16 km map holds **6 sets** of 4
   (24 twins, 96 towns for an X, 72 for a T; 20 km: 7 sets). **Density**: after the x3 growth the grids fill and
   build up, never out (`lights_showcase grow queued ... factor=x3 passes=1 ... locked=true`; x3 since 2026-10-13,
   sized for about 1000 people per town, SHOWCASE.md "Growth for ~1000 people per town"; was x10). **Population**:
   every final line `lights_showcase_grow town <name> levels ... buildings=N pop=P`, and the dense summary ends
   ` pop min/mean/max=a/b/c (n of N towns read)`: **record** it. **Pass:** the mean near ~1000 (roughly 700-1400)
   and all towns read; far off: note it, `GROW_FILL` (0.85) is then re-derived from the mean. Also **record** a few
   towns' population and buildings (town window) about 5 game minutes after the growth (does it keep rising after
   the final check?), the final leak lines
   (`outside_streets=0 houses_outside=0 ... houses_unread=N houses_pos=bbox:a,con:b,odd:c`: **record** the
   `houses_pos` split; houses_outside must now match the screenshot, i.e. ~0 with no house visibly outside: seed
   530609 logged 1842 with none outside, SHOWCASE.md "houses_outside"), and whether the frame rate / game speed
   suffers with ~100 towns at x3. Optional extra for more traffic: the load setting **Town building
   capacity** x2 / x4 multiplies the residents and workers per town building (experimental; x4 can slow the game;
   don't combine with Car traffic + bus lines, docs/findings.md). Note it with the run if used.
   **Names**: hover / open a few towns: "Smart lanes 1 N", "Game default 1 E", "Smart phases 1 S", "Kerb locked 1 W"
   (twin a-d, set, side of its crossing; N = map +y, E = +x: **record** whether that matches the game's
   north, i.e. the top of the minimap / map view; if not, logic.compassOf needs turning). In the Showcase (step 6) "Parclo 3 N (Smart lanes)" style. **Pass:** the names show in full on the map
   labels; Remove towns > Grid towns lists every one of them (and an old save's "Grid S.." towns) and no real town.
4. Traffic: Traffic tab > Traffic log on (every 10 s), game speed 4, let it run 20 game minutes, then `make flow`.
   No `FLOW_BUS` lines are expected (no bus lines); every pair compares sl / sl_phases / sl_lock with game, and sl
   with sl_lock. **sl_lock twin (2026-10-13)**: the first line `twins sl=N game=N sl_phases=N sl_lock=N`, the zones line
   `by_ab=game:N,sl:N,sl_phases:N,sl_lock:N` and Smart Lanes' `[SQRL] ZONES ... by_ab=` the same (the ack matches:
   `zones ack=yes`), Smart Lanes' `MODE` lines for the d twins kerb-locked with game phases; towns "Kerb locked
   <set> <side>"; `make flow`: `sl_lock vs game` and `sl vs sl_lock` rows. **Record** the per-pair table.
4b. **Town entries + every-driver sampler (2026-10-12, SHOWCASE.md "Town entries")**: rebuild the Lights showcase
   on a fresh 16 km map with Smart Lanes enabled (the entry roundabout is the Stress Test's own construction since
   2026-10-12; Roundabouts & Interchanges is not needed for it). The first line ends in
   `entries=roundabout link_lanes=6`; then once `[SQST] lights_showcase entries: driving side right, ring
   anticlockwise` (left-hand traffic: `left, ring clockwise`; `not read (...)` means right was assumed: record it);
   one `entry <town> kind=roundabout at x,y node=N removed=3 ... reach=46m in_reach=Nm` line per town, then (after
   the settle) `kind=roundabout joined=3/3`, and `[SQST] lights_showcase entries roundabout=96 crossroads=0 broken=0
   joins=288/288`. **Inward arm** (runs 2026-10-12 / 10-13: all 96 refused, first with square_roundabouts' 62 m arms,
   then at 46 m by the inward crossroads): **record** `in_reach=` (the same value in every line is expected) and the
   line `entries: inward arm 46m refused by the check (...), Nm from now on` if present (at most one such line per
   lowering; a second, later one means some sets got different reaches: they show `match=no reason=entry`, record
   which). **Record** every `kind=crossroads (...)` line with its reason: `(roundabout refused by the check: ...
   (inward arm 46m, 42m, 38m, 36m))` means even 36 m collided; its `; known: #id <role> far node (k streets)` part
   names what. Screenshot
   two towns: a 2-lane roundabout at the middle of the side facing the junction, its side arms joined to the ring,
   its inner arm to the central street, the link (now 3 lanes each way) into its outer arm. **Pass:** after 20 game
   minutes at 4x the links' inbound lanes no longer queue solid back to the junction (`make flow`: the "Approaches"
   table's queued per arm stays well below the v2 run's solid queues; FLOW_ALL `capped=0 target=all`, **record**
   `frames=`, `sweep_ms=`, `frame_ms_max=` and any `FLOW_TARGET` line). Screenshot one entry close up: the inward
   arm visibly shorter than the other three when `in_reach` < 46, its join to the central street's crossroads clean;
   **no houses on the ring or its island** (the ring is now `highway_new_medium`, a country one-way), the side arms
   running along the perimeter street into it (no town stubs bent outwards). Third run (2026-10-13, seed 158690):
   12 `arms not read`, 10 broken joins, 15 unlinked; **pass now**: `entries roundabout=96 crossroads=0 broken=0
   joins=288/288`, `linked=` all, `sets_mismatch=0`, no `kind=roundabout locked=` line at log level (a shortfall
   is logged: record it), the joined lines `lights=in:carried` or `in:off (unmapped (...))` /
   `left:off (...)` / `right:off (...)` and no `node not found`; **record** any `arms not read (ends=N found=...)`
   or `arm end N has k streets now` line. Also **record**: the `in_reach=` and `ring_lanes=` values used (expected `ring_lanes=3`, the 3-lane
   `highway_new_large` ring, 2026-10-13; any `entries: 3 lanes ..m refused by the check (...), .. from now on` line,
   and whether the 3-lane ring is refused and the 2-lane one taken: record the refusal reason); a screenshot of one
   3-lane entry (three ring lanes, no houses on it or its island, the arms meeting it cleanly); the `kind=roundabout locked=8 of
   8 streets age=2.x s` lines (detail; at log level only when short or fewer than 8: record those, and any `its
   streets not all locked` / `lights off refused twice` line); that every entry still gets Smart Lanes' ring write
   with the highway ring (`[SQRL] WRITE ring=` at each entry, `ring=4/0/0`): Smart Lanes treats a one-way street
   without sidewalks as a ramp (square_smart_lanes sl_cross.lua:10), so a missing ring write or a ramp verdict on the
   ring nodes is a finding; and the entry's footpath gap (pedestrians detour, no sidewalk on the ring).
5. Press again for 3x3 X (then 3x2 X, T 2x2) on a fresh map: the constructions have `sqst_x_main=6 sqst_x_side=6`
   (3x2 X: main 6, side 5; T: `sqst_x_shape=2`).
6. Showcase (needs Roundabouts & Interchanges): every town Medium (`towns=N (Medium)` on the first line; 9-10 sets
   on 16 km, 14-17 on 20 km by seed). After the links `[SQST] showcase_depots: N route towns ...`, one
   `showcase_depots <route> depot=D (built in ring ...)` per route town, then the growth; later the bus lines log
   `depot=D (ours, ...)` (the pre-built depot). **Pass:** most routes get their line (was 0 of 10 at seed 718344).

## 7. Save, reload and remove

1. Save, quit to the main menu, load the save again: the game loads, the Debug button is back, "Queue: Idle",
   the keep-balance and Keep traffic cleared boxes are unticked (session only), Hide all notifications is ticked.
2. Removing the mod from a save: first untick **Hide all notifications** and press **Restore defaults** (town
   ratings); both live in the save. Then the game warns (severityRemove Warning) and loads; towns, vehicles, lines,
   stops and depots made with it stay. Quit to the main menu before `make unlink` or deleting the mod folder
   (docs/findings.md "Debugging tips").

## Appendix A. Probes (developers)

The in-game experiments the tabs were built from; results in docs/findings.md "Stress Test probes". The Probe tab
exists only with the load-time setting **Show probe tab (developers)** = On (default Off). Each probe changes the
save. Not part of the release check. Probes 9 (car traffic) and 10 (bus lines) have their own steps in
PROBES_TRAFFIC.md and PROBES_BUSLINES.md.

Open the **Probe** tab. Probes 1-4 work at the **camera centre**: move the camera first (where it says so).
Wait for each probe's `[SQST-PROBE]` line before starting the next one (the delays are listed).

### A1: create a town in a running game (`town_create`, `town_create_big`)

1. Move the camera to an empty, flat area away from towns.
2. Click **1a Create town here**. Wait ~5 s.
3. Look for: a new town "SQST Town 1" with streets and houses at the camera centre.
4. Log: `[SQST] town_create callback success=... after N ms`, then
   `[SQST-PROBE] town_create ok|fail pos=... towns=N toAdd=1 toRemove=K(ignored) info.caps={...} ... success=true towns N->N+1 new: town=... initCaps={...} sizeFactors={...} buildings=... personCaps={...}`.
   Note `toRemove`: if it is the number of existing towns, createTowns treats its input as the whole town list
   (the probe never destroys anything).
5. Move to another empty spot, click **1b Create big town here**. Same lines, name `town_create_big`, plus
   `set caps -> {1600,1600,1600}` (or `setting caps failed`). Compare the new town's `initCaps` and size on screen with 1a.

### A2: grow the nearest town x10 (`town_grow_x10`)

1. Centre the camera on a small town. Note its population (town window).
2. Click **2 Grow nearest town x10**. Watch the town for 30 s (game running, not paused).
3. Log: `[SQST] town_grow_x10 callback success=... after N ms; before: town=... sizeFactors={...} buildings=B ...; sent sizeFactors={...}`,
   `[SQST] town_grow_x10 +5s: ...`, and after 30 s `[SQST-PROBE] town_grow_x10 ok|fail callbackMs=... before: ... | +30s: ...`.
4. Look for: did buildings upgrade/appear at once (updateAllBuildings) or slowly; did `sizeFactors` read back as sent
   (×10) or clamped; did the frame rate drop (note how long the callback took).

### A3: develop at a point (`town_develop_1`, `town_develop_9`): OBSOLETE

Settled in the second run (docs/findings.md): `makeTownDevelopAtCmd` adds no streets and no buildings, so the
Towns tab has no "Develop now". No need to run it again; the buttons stay for reference.

1. Centre the camera on the edge of a town (half houses, half empty land).
2. Click **3a Develop at camera (1 call)**. Wait 5 s.
3. Log: `[SQST-PROBE] town_develop_1 ok|fail calls=1 succeeded=1 ... streetEdges(r=600m) A->B (+n) townBuildings C->D (+m)`
   (street edges within 600 m of the camera, counted with the octree; the first run failed with "Cannot loop over this component type", now fixed).
   Look for new streets / houses on screen around the camera centre.
4. Click **3b Develop 3x3 grid (9 calls)** (150 m grid). Same line for `town_develop_9`. Compare how much one call adds.

### A4: a street built from scratch (`street_from_scratch`)

1. Centre the camera on flat empty land (no roads, buildings or water within 50 m).
2. Click **4 Build street here**. Wait 2 s.
3. Look for: an 80 m town street running east-west through the camera centre.
4. Log: `[SQST-PROBE] street_from_scratch ok variant=A ref: edge=... typeIndex=... | A: success=true ... streetEdges N->N+1`
   (A = typeIndex copied from an existing street, no context), or, if A failed,
   `... variant=B(typeIndex=1, ctx.player) ... | A: success=false ... messages={...} | B: success=...`.
   The `messages`/`warnings` show why the engine refused it. Try once on a slope as well, if A works.
   Stops and depots on the new street are not part of this probe yet.

### A5: buy vehicles on a line (`vehicle_buy_1`, `vehicle_buy_5`)

Needs a bus (or any) line of yours with at least one vehicle, and enough money (+100M first).

1. Click **5a Buy 1 vehicle on first line**. Wait 5 s.
2. Look for: a new copy of the line's first vehicle leaving the depot and joining the line (Lines window: vehicle count +1).
3. Log: `[SQST-PROBE] vehicle_buy_1 ok|fail line=... depot=... requested=1 answered=1 bought=1 setLine=1 lineVehicles N->N+1 balance X->Y`.
   `answered` = buy callbacks received (proves callbacks work from the GUI queue).
4. Click **5b Buy 5 in one frame**. Same line with `requested=5`: do all 5 succeed when sent in the same frame?

### A6: speed above 4, large bookings (`speed_8`, `speed_16`, `book_1e9`, `book_3e9`)

1. Click **6a Speed 8**. Log after 1 s: `[SQST] speed_8 +1s speedup=...`; after 15 s:
   `[SQST-PROBE] speed_8 ok|fail success=... estimatedMax=... speedup before=1 +15s=8`. On screen: does the game bar
   show it, does time run visibly faster, does it snap back to 4 or below?
2. Click **6b Speed 16**, same. Then set 1x from the Game tab.
3. Click **6c Book +1 billion**. After 2 s: `[SQST-PROBE] book_1e9 ok|fail success=... amount=1000000000 entry.amount=... balance A -> B delta=...`.
4. Click **6d Book +3 billion (overflow test)**. Same line for `book_3e9`. Look for: `entry.amount` (what the JournalEntry
   kept), and whether the balance went up by 3B, by a wrapped amount (about -1.29B), or not at all.

### A7: runtime write to baseConfig.noCosts (`basecfg_nocosts`)

1. Note the balance. Click **7 Toggle baseConfig.noCosts**.
2. Log: `[SQST-PROBE] basecfg_nocosts ok|fail before=false wrote=true writeOk=... err=... reread=... sameObject=... sandboxMode=...`.
3. Build a short road and a bus stop. Did the balance drop? (No drop = the runtime write works.)
4. Click **7** again to flip it back (`before=true wrote=false`) and build again to compare.

### A8: emissions of 10 entities (`emissions_zero`): SUPERSEDED

The second run failed (read-back zero 0/10 after 2 s, restore reported failure). The likely cause: with
`missionEmissionsScriptFactor` = 1 the base emissions script re-sends every managed emitter (industries, stations,
depots, warehouses) whose value differs from its model, every 5 updates (emissions.script.tl:37-38, :127-131), so a
zero is overwritten within seconds. Superseded by the load-time setting **No noise and pollution** (section 3) and
the Game tab's town ratings action (section 2); the probe is left as it was (its restore is still unreliable).

1. Have some traffic and industries on the map (any running game). Click **8 Zero emissions of 10 entities**.
2. After 2 s: `[SQST] emissions_zero +2s zero=Z/R` (Z of R emitters read back as zero = the command works).
3. After 30 s (keep the game running at 1x): `[SQST-PROBE] emissions_zero ok|fail emitters=N picked=10 factor=F first: e=... noise=... | +2s zero=Z/R | +30s zero=Z2/R2 (still zero = not overwritten); restoring`.
   `+30s zero` lower than `+2s zero` = the base emissions script overwrote our values. `factor` is
   `advancedOptions.missionEmissionsScriptFactor`. The probe then restores the original values.

## 6V. Mixed Lights showcase, ~400-people towns, throughput (rev 2, 2026-10-13; not run in game yet)
Background: SHOWCASE.md "Mixed shapes, smaller towns, throughput" and "Exit-fan twin". A fresh **20 km** Blank Slate
(a 16 km map holds only 6 of the 12 sets), 1950 or later, Smart Lanes enabled (with sl_exitfan), Remove towns > All
towns.
1. Press "Build lights showcase" (no options). **Pass:** the first line `twins sl=12 game=12 sl_exitfan=12 towns=135
   (Medium) lights=yes ... shapes=2x2_X,3x3_X,3x2_X,T_2x2 per_shape=3`; the zones line `by_ab=game:12,sl:12,
   sl_phases:0,sl_exitfan:12` and Smart Lanes' `[SQRL] ZONES op=set ... by_ab=` the same (`zones ack=yes`); 36
   junctions built, `linked=135 unlinked=0`, `entries roundabout=135 crossroads=0 broken=0 joins=405/405`,
   `sets_mismatch=0`. In the e zones (twins `g<k>e`, towns "Exit fan <set> <side>") Smart Lanes' `[SQRL] APPLY ...
   zone=sl_exitfan exit_fan=yes` at every lit junction: **record** any e junction without it. Screenshot one T set
   (three towns) and one set's three twins (their order rotates per shape). Entry locks: **record** how many
   entries locked at the build (`locked=8 of 8 streets (4 already) age=0.0s`, detail log) and how many later (`(at
   the build: the later lock tries again)`, then `age=2.x s`, or `(one lock for K entries)`), and every `kind=roundabout
   stray street ... removed` / `not removed` line; pass: no `arms not read`.
2. Growth: `grow queued ... target=400`, every pass line `(x.. for 400 from pop=..)`; **record** the summary's
   `pop min/mean/max` (**pass:** mean about 400, roughly 300-500; else re-derive from the pass lines' pop before x
   factor vs the final pop).
3. Lanes: at a junction arm's end where it meets its link (2 -> 3 lanes), the node window shows the arm's far lane
   connected to both of the link's inner lanes and both of them back into it; **record** a screenshot.
4. Traffic log on (30 s), 20 game minutes at 4x, then `make flow`. First **record** the 4 `[SQST] FLOW_PATHDBG` lines
   (what a path element is: its reader `[1]` / `first`, its entity, whether that entity is a BASE_EDGE / BASE_NODE,
   and whether any appears in `set=`: run 2026-10-13_0356 had thru=0 everywhere). **Pass:** FLOW lines with `thru=N thru_s=30`
   (not all 0 at busy junctions: if every thru stays 0 while cars cross, the EdgeId.entity assumption in FLOW.md is
   wrong: report it), `q_in=` / `q_out=` per arm; FLOW_START `drive_side=right`; the report's per-pair table has
   `thru/min`, the paired comparison `all` rows over the 12 sets for sl vs game, sl_exitfan vs sl (the fan alone) and
   sl_exitfan vs game, with thru W/L/T; FLOW_ALL
   `capped=0` (thru needs every driver) and **record** `sweep_ms` / `frames` / `frame_ms_max` against the last run
   (the path checks cost frames). A `FLOW_TARGET ... reason=skipped` line means thru is no longer a full count:
   from there `thru_scale=k` (an estimate from every k-th driver by id) until `reason=recovered target=all`;
   **record** both lines, how many samples ran at which scale, and compare pairs only over samples of the same
   scale (one `thru=-` sample at each change).

## 6W. Bench sheet 1: roundabouts and lane drops (rev 2, 2026-10-13; not run in game yet)
Background: plans/square_stress_test/BENCH.md (sheets, the run's phases, the report). One press runs everything.
Setup (once): `make link`; in the Mod Hub enable **Stress Test Debug Tool**, **Smart Lanes** (the version with the
bench zone mode `sl_keeplights`; its settings: Apply automatically On, No lights at roundabouts and ramps On, the rest
as you like) and **Roundabouts & Interchanges**. Start a **new free game, 16 km (Very large) Blank Slate**, any year
(the run sets 1950 if earlier).
1. **Press**: Debug window > Towns tab > **Bench** > **Sheet 1**. **Pass:** a dialog "Bench sheet 1: roundabouts and
   lane drops" with "39 junctions, 132 towns (~53k people), about 11 min to build; 16.0 x 16.0 km map: everything
   fits". A dialog listing a problem instead (Smart Lanes setting, mod missing): fix it and press again.
2. **Confirm**: "Run bench". Then leave the game running, unpaused, in front (no other window over it, no other
   button presses) for about 25 minutes. The Bench section's status line shows the phase (clear, year, build,
   sl_idle, warm-up / recording N of M game s, shots).
3. **Wait** for the status `Bench s1 done (seed N): tell Claude "done" (make bench).` (a dialog "The bench stopped: ..."
   means it aborted: note the reason; the log has it too).
4. **Say "done"**. Claude runs `make bench` (draft in `.cache/bench/`). **Record** while it runs, only if you see it:
   any error dialog, a stutter, a crash.
What Claude checks in the log (no action for you): `BENCH_START ... sl_lights=on ... sl_modes=...,sl_keeplights`;
`bench_s1 summary ... built=39 refused=0 ... linked=132 unlinked=0 ... sets_mismatch=0`; `bench_s1 entries
roundabout=132 crossroads=0 broken=0 joins=396/396`; 39 `BENCH_TWIN` lines (rb4 twins: `lit_nodes` > 0 in the game and
sl_keeplights twins, else test 2 is void: BENCH.md open question 2); `[SQRL] LIGHTS ... to=off zid=g<k>a` in the rb4 sl
twins and `to=kept zone=sl_keeplights zid=g<k>f` in the f twins; `[SQRL] SKIP ... reason=zone_game zid=` naming every
game twin; `[SQRL] APPLY kind=drop ... zid=` at every drop sl twin; `bench_s1 smart_lanes idle=yes`; `FLOW_START ...
interval=10 ... thru_m=pos`, FLOW lines with `thru=` > 0 at busy junctions, `FLOW_PATHOFF` once (or `thru_path`
values); warm-up and record phases at speed 2 (or 1 after a step-down); `BENCH_SHOT` x 5 (3 roundabout twins + 2 drop
twins) and `BENCH_DONE ok=yes`. Screenshots: the game's `screenshots/` folder, the 5 newest files.
