# square_better_auto_vehicle_renamer: history

## 2026-10-20: lease and run-line retest (19:20Z / 19:28Z sessions)

Live log at the time of writing; archived at the next game start as `2026-10-20_1920_*`. Three loads of the same
save file (`Organic Towns - Subarctic`, "Savegame info ... time = Tue Oct 20 00:52:13 2026" each time, 483 vehicles,
482 names of ours + 1 hand-typed), Normal speed (budget 10), Purchase year "After the name" in all three:
- **19:20:16Z load**: nothing renamed (the names matched). Two `init` lines in this one load (19:20:29Z Sim Pool 6,
  19:21:53Z Sim Pool 5, no "Loading game from file" between): a Lua state whose first update came 84 s game time
  after the first, past the 60 s game-time rule; it also dropped the lease and run fields mid-session. Fixed after
  this run: PLAN.md "One init per load".
- **19:28:15Z load**: a re-render started (`rerender progress 10/482`), then the same save was loaded again at
  19:28:54Z before it went far.
- **19:28:54Z load, re-render**: 482 renames from 19:29:05 to 19:30:37Z (~92 s real), one `rerender done n=482`,
  3 claims in all (2 at the start, 1 handover), `failed=0 dup=0 race=0`, progress lines from one state about every
  5 s real (the thread names vary: the thread is not the state). SQPERF during the run: `update` ~0.48 ms mean /
  2.1 ms max, `get` ~0.47 ms per call. The sticky lease and the run lines passed (K below).
- **Why 482 re-renders although Purchase year never changed**: the game's mod-param dump at each load (the
  "square_better_auto_vehicle_renamer: {" block after the mod list) shows `bavr.numSep` = 1 at 19:20Z, 3 at
  19:28:15Z and 5 at 19:28:54Z (and `sqperf_log` 1 -> 2 at the last load). Number separator is in the settings hash
  but not in the init line, so the re-render was genuine (every name's separator changed), not a rename of
  unchanged names. The code can't send a name equal to the current one (`inspectFull` returns before the lease and
  the send whenever `name == want`; a retry needs `name ~= want` too, at most `RETRY_MAX`). The init line now logs
  `hash=` and `rh=` (and `run=`), so the next such question is answered by the log.

### TESTING.md K as it stood (moved verbatim): Rename lease and run log lines (fixed 2026-10-20 after the first runs; sticky lease and run lines after the 08:12Z run; PLAN.md "Rename lease (2026-10-20)")
Evidence so far: the 08:12Z session (live log at the time of writing; archived at the next game start as
`2026-10-20_0812_*`), Purchase year set to Off between loads, 483 names re-rendered at Normal (budget 10): the limit
held, 150 renames in 58 s real (08:15:14-08:16:12Z; 200 by 08:16:29Z), `failed=0 dup=0 race=0`, but renames came from
8 `Sim Pool` threads (8 Lua states logged, 12 claims), about 5 per 2 s real with the game at 2x or faster (at most
~1.3 per game second against the budget's 5), and the progress lines read `pass progress 0/410 ... 47/410` (a pass
total from an earlier session; no done line). Fixed by the sticky lease and the run lines; retest:
- [ ] **One sender.** Repeat it: quit to the menu, change a name setting (e.g. Purchase year back to "After the name"),
      load the save from C. `make logs-grep PAT='\[SQFN\]' ARGS='--session live'`: an `init ... year=after` line,
      then `sweep` lines where `renamed=` > 0 comes from one Lua state for the whole run (the thread name may change:
      the thread is not the state; one state's `sweep` lines are at least 10 s game time apart, and only its first one
      has `listNew=483`); `claims=` summed over the run 1 (2 when two states raced for the first claim), not one per
      handover as before (12 in the 08:12Z run); the other states' lines show
      `follow=` > 0 and `renamed=0`; `failed=0 dup=0 race=0`.
- [ ] **Rate.** `renamed=` summed over every line equals the vehicles renamed (each sent once, about 482: not the
      hand-typed one). Note the game speed. At 1x the run takes at least 483 / 5 = ~97 s real; expect about 1.5-2x
      that (the leader runs update in only part of the ticks: offline ~85 windows for the ideal 49); before the fix
      the same run would take ~4x (offline 414-427 windows). The renaming state's `sweep` lines show `renamed=` about
      10 x (10 s game / 2 s) x the share of windows it ran in: 30-50 per line instead of 10-20.
- [ ] **Run lines.** `rerender progress a/483` (b = the names of ours at load: 483 records minus hand-typed ones),
      at most one per 10 s game time in all, `a` rising, never `a = b`, then one `rerender done n=<renames>`; no
      `pass progress` / `pass done` line in that run. A reload with the same settings: no `rerender` and no `pass`
      line at all. An Apply run (C) logs `pass progress a/N` and one `pass done n=N` the same way.

## 2026-10-20: first in-game runs

- **`2026-10-20_0539_sqot-sqfn`** (8 min, an Organic Towns save, records=399 at load, Normal speed = budget 10):
  `init welcome=apply records=399 pass=false format=num_model year=after`, so the Apply pass had run earlier (410
  vehicles numbered: `ptotal=410` in the state; that run is not in the archive) and this load re-rendered every
  record for the new format and year (budgeted): 398 renames in ~52 s real time (05:40:53-05:41:45Z; the sum of
  `renamed=` over all sweep lines), the hand-named vehicle kept (`user=1` every cycle), `failed=0 dup=0 race=0
  gone=0` throughout, no `[SQFN] error`. Later in the session five bought vehicles were each named on the next cycle
  (`sweep ... new=1 renamed=1`, 05:44:51-05:47:01Z). The sweep lines came from all 11 `Sim Pool` threads; many
  showed `renamed=10` in the same seconds, which looked like a budget per Lua state, and the `pass progress a/410`
  lines (the re-render's waiting count against the old pass total) came from every state and kept logging `410/410`
  after the run. Analysis and fix: PLAN.md "Rename lease (2026-10-20)".
- **07:53Z session** (live log at the time of writing; archived at the next session start as `2026-10-20_0753_*`):
  the same save settled (`init ... records=483 ... old=off trainLen=wagons`): no `sweep` line at all (the settled
  fleet did no work), but 14 `pass progress 410/410` lines at load from 11 `Sim Pool` threads (Sim Pool 2, 6 and 7
  twice). Fixed: pass lines only while a pass renames, one `pass done n=`.
- **08:12Z session** (live log at the time of writing; archived at the next game start as `2026-10-20_0812_*`): the
  same save loaded (`init ... year=after`), then Purchase year set to Off and loaded again (08:15:05Z, `init ...
  year=off`): every name of ours re-rendered. 150 renames in 58 s real (08:15:14-08:16:12Z), 200 by 08:16:29Z,
  `failed=0 dup=0 race=0`: the rate limit held. But renames came from 8 `Sim Pool` threads (11, 3, 10, 4, 1, 5, 2, 7,
  then 8), the sweep lines summed 12 claims, and the rate was about 5 per 2 s real with the game at 2x or faster (one
  Lua state logged at 08:15:14 and 08:15:19, at least `LOG_MS` = 10 s game time apart): at most ~1.3 renames per game
  second against the budget's 5. The log also showed that the thread name is not the Lua state (`Sim Pool 11` logged
  two states' first lines, `listNew=483` at 08:15:14 and 08:15:25; `Sim Pool 3` logged a state's second line at
  08:15:19) and that each state runs `update` in only part of the ticks (`cycles=2` per 10+ s game time): the leader
  renamed once per cycle of its own and its 10 s lease lapsed between them (docs/findings/game-scripts.md). The
  progress lines read `pass progress 0/410 ... 47/410` from several threads: `st.ptotal` of an Apply pass from an
  earlier session, shown for a re-render, and no `pass done`. "Number existing vehicles on next load" was On: no
  window (`welcome op=done reason=nothing`), as designed for a save answered Apply. Fixed: the sticky lease and the run
  lines (PLAN.md "Rename lease (2026-10-20)"), the setting's tooltip and description now say it does nothing after
  Apply.

## 2026-10-20: the phase 1 / 2 sweep cycle (superseded by PLAN.md "Sweep strategy (2026-10-20)")

Moved verbatim from PLAN.md.

From "How it works", "Where it runs":

- a sweep is due when game time crosses a 2 s boundary (`math.floor(t / 2000)` changes). `update` runs on several
  Lua states, so a module-local timer is unreliable. The state is the shared store.
- one sweep is `getEntitiesWithComponent(TRANSPORT_VEHICLE, { requireOwnedByPlayer })` plus one `getComponent`
  per vehicle, inside `pcall`.

From "Performance":

- A sweep is sliced: at most N vehicles inspected per `update` (start 200, a cursor over the id list re-listed
  once per full cycle), plus the rename budget. A 5000-vehicle save never does all of it in one tick. Hard caps on
  every loop (CLAUDE.md), with a log reason when hit.
- The fast path costs one `getComponent(TRANSPORT_VEHICLE)` plus one string compare per vehicle. The name is
  rendered only when an input changed: a per-vehicle input key (line id + line name + lead model id + settings
  hash + the "old" flag + the train count, and in the register check the number shown), compared before any string
  building. Model names are cached per model id, line names per line, refreshed
  once per cycle.

From "Phase 1", "Choices made":

- **Cycle**: `list` (at most one per 2 s window) -> `prune` -> `scan` (200 per update) -> `end` (the pass). The fast
  path is one `reader.read` and five equality checks; a name is rendered only on a changed input or a name that is
  not ours.

From "Phase 2", "Update, per Lua state":

> Cadence: the sweep's
>   game-time window (a new cycle at most once per 2 s of `GAME_TIME.gameTime` per Lua state), 200 vehicles per
>   update, the rename budget per 2 s window shared in the state.

From "Phase 2", "The lazy register read":

> and every 15 cycles
>   (`PRUNE_EVERY`, 30 s) as a backstop. A settled fleet: about one read per 30 s per Lua state, no writes
>   (`test_game.lua` "state reads"; `test_sweep.lua` "cost": at most 2 reads in 60 updates of a 2000-vehicle fleet).
