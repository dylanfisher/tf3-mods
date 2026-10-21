Status: first in-game runs 2026-10-20 (`2026-10-20_0539_sqot-sqfn`, the 07:53Z, 08:12Z, 19:20Z and 19:28Z
sessions: results in `HISTORY.md`); the sticky lease and the run lines passed in the 19:28Z run; open: the rest of
the first run, and K's leftovers (one init per load and a mid-run reload, fixed after the 19:20Z run); revision 1,
not released.

# square_better_auto_vehicle_renamer: in-game test checklist

Setup: quit to the main menu, `make link` (done 2026-10-20: the mod is in the staging area), enable **Better Auto
Vehicle Renamer** and turn its **Debug: performance log** On (SQPERF window lines every 30 s). English game first
(the default-name pattern and the words are English-checked only). Everything below is read back from the live log:
`make logs-grep PAT='\[SQFN\]' ARGS='--session live'` (the archive keeps it after the game closes: `--session last`).
No `[SQFN] error` line may appear anywhere: if one does, copy it into this file and stop.

**First thing to read: the cost of `state:get()`** (PLAN.md "Phase 2", the open performance risk). After step C
(a save with a few hundred vehicles numbered) and with the SQPERF setting On, run
`make perf ARGS='--mod square_better_auto_vehicle_renamer --last'` and
`make logs-grep PAT='mod=square_better_auto_vehicle_renamer ctx=gs' ARGS='--session live'`. Per 30 s window and
Lua state: `get n= ms= max=` (one read: ms / n), `step`, `set`, `update`, `event`, `renamed c=`. Note `get` ms per
call against the record count (`init ... records=N`, or the vehicles numbered). Rule of thumb: about 1 µs per record
means a copy per call (the design already reads it rarely; then nothing to do); far less means a shared table. Also
`phase=first ... get=` (the first read of each Lua state, with the full validate). Targets: `update` max well under
1 ms on a settled 2000-vehicle save, `get` n of about one per 30 s per Lua state when nothing changes (prune
backstop: `PRUNE_MS` 30 s game time), `set` only on renames / new / sold vehicles. The split inside `step`: J.

## A. New game (no vehicles)
- [ ] Start a new free game. Log: one `[SQFN] init welcome=nil records=0 ... gsTr=<word>` line (only one per
      load, whatever the number of Lua states). Note `gsTr=`: in an English game it reads `Truck`; repeat once in
      a German game later and note whether it reads `Lkw` (then `_()` translates in a game script: record it in
      `docs/findings/scripting.md` "Translations").
- [ ] No welcome window. Log: `[SQFN] welcome op=done reason=nothing` a few seconds in (the game script answered
      Apply by itself: no vehicles).
- [ ] Buy a bus on a line, a truck, a train with a loco + wagons, a ship, a plane, a helicopter (and a tram if the
      era has one). Within ~2 s game time each gets (up to ~10 s when the sweep was idle: the back-off, J) `<model> <letter>-0001` (B, T, L, S, A, H, R); the train
      shows the loco's model. Log: `[SQFN] sweep ... renamed=1 new=1 ...` lines (at most one per 10 s per Lua state).
      Tram default name: note what it was (PLAN.md "Open questions").
- [ ] Pause the game, buy a vehicle: no rename while paused; it is renamed within ~2-10 s game time of unpausing.

## B. Existing save, Not now
- [ ] Load a save made without the mod that has vehicles. After ~3 s the welcome window opens, centered, with the
      example name, "Number your N existing vehicles, oldest first" (ticked; N = the save's vehicle count), the save
      hint and [Apply] [Not now]. Log: `[SQFN] welcome op=show kind=first count=N`. Lines wrap, nothing cut off,
      nothing touching; hover the box and both buttons for their tooltips. `make css-rules` stays 0 for this mod.
- [ ] Close the window with its X (counts as Not now). Log: `[SQFN] welcome op=answer answer=later kind=first
      count=N button=later`. Existing vehicles keep their names; a bus bought now gets `... B-0001`.
- [ ] Save, reload: no window (log `welcome op=done reason=nothing`).

## C. Existing save, Apply (oldest first)
- [ ] Load the same save made without the mod again (a copy), press **Apply** with the box ticked. Log:
      `welcome op=answer answer=apply kind=first count=N button=apply`, then after one cycle
      `[SQFN] pass created=N collected=N`, `pass progress a/N` lines (about one per 10 s game time, all from one
      Lua state, K) and one `pass done n=N`. Renames run at the speed setting (Normal: 10 per 2 s game time;
      `sweep ... deferred=` / `follow=` show the waiting ones). (2026-10-20: an Apply numbered 410 vehicles in a run
      that is not in the archive: `ptotal=410` in the state; the `welcome` / `pass created` lines are still unseen.)
- [ ] The oldest vehicle (vehicle list, sort by age) has the lowest number of its type. Vehicles you had named by
      hand keep their names (`sweep ... user=`).
- [ ] Untick the box and Apply on another copy: behaves as Not now (`answer=later ... button=apply`).

## D. Buy, sell, hand-rename, replace (on the save from C)
- [ ] Sell a numbered bus, then buy a new one: it gets the next number, never the sold one's. Log
      `sweep ... pruned=1` (the sale) and `new=1`.
- [ ] Rename a numbered vehicle by hand: the name stays (log `sweep ... user=1` on the next cycles, no rename).
      Clear the name (empty): it gets its fleet name back with the same number. (2026-10-20_0539: the hand-named
      vehicle stayed through a full re-render, `user=` every cycle; clearing it is still open.)
- [ ] **Replace** a vehicle with another model (vehicle window, Replace): the name changes to the new model with
      the same number. Log: `replaced=1` (Replace keeps the id) or `matched=1` (a new id inherited the number) or
      `new=1` (a new number: then Replace matching failed; note it). Record which one in
      `docs/findings/lines-vehicles.md` (PLAN.md "Phase 0": does Replace keep the id).
- [ ] Rename a line: its vehicles' names change only with a line format (Settings), within one cycle (2-10 s game
      time; log `lineHits=`); without a line format the log shows `lineChecks=0`.
- [ ] Vehicle list sorting of `B-0412` / `B-1000`: sensible? (Phase 0 open question.)

## E. Settings between loads
- [ ] Quit to the menu, set Name format "Number + model" and Purchase year "After the name", load: every name of
      ours re-renders over the next sweeps (budgeted), hand-typed ones stay. Purchase years are the years the vehicles
      were bought (a vehicle bought this year shows this year). Log: `init ... format=num_model ... year=after`.
- [ ] Type prefix "Full word" in a German game: names use `Lkw-0001` etc. Log `[SQFN] words src=gui Bus|Lkw|...`
      once (the GUI sent the translated words), no `words src=english reason=timeout`.
- [ ] "Number existing vehicles on next load" does nothing on a save where you chose Apply (every vehicle has its
      number; only Not now leaves vehicles unnumbered): the 08:12Z session had it on a save answered Apply, no window
      (`welcome op=done reason=nothing`). The tooltip and the description say so since 2026-10-20.
- [ ] "Number existing vehicles on next load" = Yes on the Not now save from B: the window shows again with
      "You asked to number ..." and the count of the still-unnumbered vehicles. Log `welcome op=show kind=renumber
      count=N`; Apply numbers them (`kind=renumber`). Reload: no window.

## F. A 40-vehicle burst
- [ ] Renaming speed Fast (25 per 2 s). Buy 40 buses quickly (or Apply on a save with 40+). Log: per 2 s window at
      most 25 renames, `sweep ... failed=0 dup=0 race=0`, every name arrives (no rename of the same vehicle twice:
      `make logs-grep PAT='\[SQFN\] sweep' ARGS='--session live'` shows `renamed` adding up to 40). Note the
      SQPERF `update` max of that window.

## G. Destination Displays (stand-down)
- [ ] With **Destination Displays** (gameburrow_destinationdisplays) also enabled: log
      `[SQFN] standDown reason=destination_displays renamed=none` once per load, no `sweep` lines, no renames.
      The window shows once per save: the stand-down line and [OK]. Reload: no window.
- [ ] Disable Destination Displays again and load: no stand-down line; the normal welcome shows (if unanswered).

## H. Regression (every release)
- [ ] `make gate-full MOD=mods/square_better_auto_vehicle_renamer`, `make css-rules MODS='square_better_auto_vehicle_renamer'`
      = 0, `make i18n ... --check --lint-modinfo`, `make tooltips` 0 long lines.
- [ ] One load of a big save (2000+ vehicles) with SQPERF On: no `slow=` lines from this mod.

## I. Options: per line, old-vehicle mark, train length, fleet register (added 2026-10-20)
- [ ] **Per line.** Quit to the menu, set Counting "Per line", load the save from C. Log: `init ... counter=line`.
      Within a few sweeps every vehicle on a line is `Bus 12 #01 | <model> (<year>)`, `#02` …, in the order they
      were numbered (oldest first after Apply); a vehicle without a line keeps `B-0205 | ...`. Log: `sweep ...
      lineMoved=N` (the first renumbering) and `renamed=` within the budget.
- [ ] Sell the 2nd vehicle of a line with 5+ vehicles: on the next sweeps only the ones behind it move up (`#03` ->
      `#02` …), nothing else is renamed. Log: `sweep ... pruned=1 lineMoved=<behind> renamed=<behind>`. Buy one for
      that line: it gets the next free number at the end, nobody else renamed (`new=1 lineMoved=1 renamed=1`). Move a
      vehicle to another line: it goes to the end of the new line, its old line closes up.
- [ ] Hand-rename a vehicle in the middle of a line: nobody moves (`lineMoved=0`). Replace a vehicle (vehicle window):
      it keeps its `#NN` (`replaced=1` or `matched=1`, `lineMoved=0` or the same numbers back).
- [ ] Back to "Per type" and reload: every name is `B-<its old fleet number>` again (the permanent numbers stayed).
- [ ] **Old-vehicle mark.** Set "Mark vehicles past their lifespan" to Hourglass, load a save with a vehicle whose
      vehicle window shows no time remaining (or an old save; check the window's Age). Its name ends with ` ⌛`; a
      vehicle with time remaining has no mark. Log: `init ... old=glyph`, `sweep ... old=N` (N > 0: inspections of
      old vehicles). **Font:** does the vehicle list, the vehicle window title and the hover label show the hourglass
      or `?` (English game)? Note it in `docs/findings/gui.md` (the pending hourglass line); if `?`, say so in the
      setting's tooltip and the description. Repeat with Star (` *`) and Word: ` (old)` in English, the translated
      word in a German game (` (alt)`, log `words src=gui ...|(alt)`).
- [ ] The mark appears when the window's time remaining runs out (watch one vehicle near its end: the mark arrives
      within ~1-2 s game time of the window's "time remaining" disappearing, even on an idle save: `expDue=1`). Replace that vehicle: the mark clears.
- [ ] **Train length.** Set Train length "Wagons": a loco + 8 wagons train reads `L-0001 | <loco> +8 (<year>)`; add
      or remove a wagon in the vehicle window: the count follows within a sweep. A multiple unit with all cars
      powered shows no count. "All units": `×9` for the same train. Trams and buses: never a count. Log: `init ...
      trainLen=wagons`.
- [ ] **Fleet register.** In the console paste
      `ug_require("square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_console.lua").reg()`.
      `make logs-grep PAT='\[SQFN\] REG' ARGS='--session live'`: one `REG <no> id= ... status=` line per vehicle (500
      at most, then `REG ... N more vehicles not listed`), `REG numbers B next= held= retired=` per type, `REG summary
      vehicles= records= ours= pending= handTyped= untouched= stale= old=`. Check: `ours` + `pending` + `handTyped` =
      `records` - `stale`; the hand-renamed vehicle from D shows `status=hand-typed`; `retired` counts the sold ones.
      If the console shows an error instead, copy it here (the `state_native` `asTable` read is the untested part).
      Then update docs/console.md's row (tested).

## K. Rename lease and run log lines (sticky lease and run lines passed in game 2026-10-20, 19:28Z run: `HISTORY.md`; one init per load after it; PLAN.md "Rename lease (2026-10-20)")
Still open:
- [ ] **Same settings, Apply.** A reload with the same settings: no `rerender` and no `pass` line at all (`init ...
      rh=` equal to `hash=`, `run=none`). An Apply run (C) logs `pass progress a/N` and one `pass done n=N` the same
      way as the 19:28Z re-render did. (Every load of the 19:20Z / 19:28Z sessions changed Number separator, so
      neither was seen.)
- [ ] **New vehicle on an idle save**: named within the usual interval; `claims=1` only when the lease had ended
      (more than 20 s game time after the last run), then up to one window more.
- [ ] **One init line per load** (fixed after the 19:20Z load logged two: PLAN.md "One init per load"). Load a save:
      exactly one `[SQFN] init` line per "Loading game from file", however late the last Lua state's first update
      comes; the init line shows `hash= rh= run=`. Loading twice within 5 min real of the first load may skip the
      second init line (accepted, cosmetic).
- [ ] **Reload of a save made mid-run.** During a re-render or Apply run, save, keep playing a little, quit to the
      menu and load that save (more than 5 min real after the session's first load): the init line shows
      `run=rerender:a/b` (or `pass:a/b`); renames resume within a few seconds (a new claim), progress lines go on from
      the save's `a` to one done line, `failed=0 dup=0 race=0`. Loaded again within 5 min of the session's first
      load: no init line may appear and the first rename may wait up to ~30 s game time (the save's lease ends).

## J. Sweep strategy (2026-10-20): what the first run must show
PLAN.md "Sweep strategy (2026-10-20)". With SQPERF On, on the save from C (a few hundred vehicles numbered, then
settled) and once on a 2000+ vehicle save:
- [ ] **Idle.** After a minute with no change: `sweep` lines stop (no work: confirmed 2026-10-20 07:53Z, a
      settled 483-record save logged no `sweep` line); `make perf ARGS='--mod
      square_better_auto_vehicle_renamer --last'`: `list n=` about one per 10 s game time per Lua state, `scan`
      n= the same, `insBack c=` about 25 per game second per Lua state, `insNew` / `insQueue` / `insFull` 0. Note the
      `list` ms per call against the vehicle count (getEntitiesWithComponent + the diff) and `scan` ms / `insBack`
      (one vehicle read). Targets: `update` max well under 1 ms; `step` mean far below the phase 2 numbers.
- [ ] **Line format On** ("Line + number"): SQPERF `lines` n= / ms (the line watch; `getLinesForPlayer` +
      `getEntityName` + `getLineVehicles` per line, 32 lines per 2 s), `sweep ... lineChecks=` > 0 and `lineErr=0`
      (a `lineErr` > 0 means `getLinesForPlayer` / `getLines` failed in the game script: note it in
      `docs/findings/lines-vehicles.md`; names then follow by the backstop). Rename a line: its vehicles' names follow
      within one cycle (`lineHits=`). Move a vehicle to another line: renamed within one cycle.
- [ ] **Latencies** (game time): a bought vehicle named within ~2 s active / ~10 s idle (`listNew=1`); a sold one
      pruned as fast (`listGone=1 pruned=1`); a Replace (vehicle window) named within n / 25 s (2000 vehicles: up to
      ~80 s, `back=` reads; log `replaced=1` or `matched=1`); the old mark within ~1 s of the expiry (`expDue=1`).
- [ ] **Back-off.** `sweep ... iv=` shows 2 after a change; the SQPERF `list` count drops to about one per 10 s when
      idle; buying a vehicle brings `iv=2` back at once.
- [ ] **Apply run** (C, 2000 vehicles, Normal): `carried=` > 0 while the renames run, `scan` n x ms far below a full
      read per cycle; the renames keep 10 per 2 s (the pass lines: K).
- [ ] No `listErr=` > 0 (a failed vehicle list read: the cycle waits; nothing is pruned).

