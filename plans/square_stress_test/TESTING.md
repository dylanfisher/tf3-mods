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
`findBestDepotForLine`'s depot (else the town's). **A line that ends up with no bus is destroyed again** and its
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
