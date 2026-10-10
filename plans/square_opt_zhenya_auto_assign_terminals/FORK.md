# SQ Opt: Auto Assign Terminals

Fork of **Auto Assign Terminals** by Zhenya_ (`zhenya_auto_assign_terminals`, mod.io 6416135), local only.
Base: upstream revision 19, forked 2026-10-09. Mechanics: `tools/fork_mod.py`.

## Changes

One entry per change, so a merge can check each one survived. Name the files and functions it touches and
mark the code with `-- optimized:` comments.

All of them are performance fixes from `plans/zhenya_auto_assign_terminals/AUDIT.md` (numbers in brackets), first
built and measured in game in the perf-test harness `mods/square_aat_perftest/` (`content/opt/`,
`content/gui/opt_eow.lua`). Every changed spot carries an `-- optimized:` comment: after a merge,
`grep -n "optimized" mods/square_opt_zhenya_auto_assign_terminals/content -r` should still find each entry below.
Nothing else differs from upstream (`diff -ru forks/<forkId>/base mods/<forkId>`; mod.json differs only by the fork
tool's revision, incompatibility and JSON formatting).

Measured (run 1, 250 lines; details and caveats in `plans/zhenya_auto_assign_terminals/PERFTEST.md`): worst sweep
tick 39.7 → 9.8 ms, sweep cost 27.4 → 13.0 ms per real second, vehicles read 1,697 → 594 per second, mod GUI cost
0.586 → 0.022 ms per frame, GUI state copies 84 → 3.6 per second.

**Game script, `content/aat.script.lua`** (all in `sweep` unless noted)

- **A. Resumable sweep with a wall-clock budget** [3]. `BATCH_MS` (8 ms) now limits the whole pass, signatures
  included, not just reassignment. `s.cursor = { i, line, n }` (saved state) records where the pass resumes; `pause(i)`
  sets it, and the loop is `for idx = first, #lines` with a budget check at the top. `worked = true` at the end of
  each line, so a tick always gets at least one line done. Both old `overBudget()` branches (network check and
  reassignment) now `pause(idx)` and `break`, so they no longer set `more = true` in place. After the loop, lines not
  visited in this tick (`k < first or k > last`) copy their `checked`/`retry` from `s`. `s.cursor = nil` once the pass
  completes. `s.check` (taken from `s.changes`) is only taken when a pass starts (`first == 1`). In `handleEvent`
  "refresh", `s.cursor = nil` restarts the pass so lines before the cursor see the request. The budget uses the new
  local `nowMs()` helper (`api.type.Clock` µs/1000, falling back to `os.clock`), defined above `lineCargo`. The
  original "without a clock: one line per tick" mode is gone.
  *Behaviour:* a pass over all lines can span several ticks, so a refresh spinner or a player edit can take one extra
  pass to settle.
- **B. Clean-ups by `lineLive`, once per pass** [3]. `lineLive[lkey]` (built with `comps`, see C) replaces
  `checked[lkey]` in the deleted-line clean-ups of `s.lineOverrides`, `s.lineModes`, `s.blocked`, `s.done`/`s.doneLines`
  and `s.settle`. This is required by A: an unvisited line isn't in `checked` but still exists. `if more then return more end`
  before the station-group clean-up (`s.stations`, `s.doneGroups`) runs that clean-up once per pass, not every tick.
  The same spot evicts `cargoCache` entries of deleted lines.
- **C. One LINE component read per sweep call** [3]. `comps[l]` is filled in the priority-sort loop and reused by the
  main loop (`local comp = comps[lineId]`) and by `spreadLoad`'s `mains` count (`local c = comps[l]`).
- **D. lineCargo cache, shared by the VMs** [3]. The original `lineCargo(lineId)` body is now
  `readLineCargo(lineId, vehicles)`. It takes the vehicle list instead of reading it. The new `lineCargo(lineId, s)`
  (called as `pcall(lineCargo, lineId, s)` in `sweep`) reads `getLineVehicles` and keeps
  `s.cargo[lkey] = { v, at, c }` in the saved state: `v` is a numeric hash of the vehicle ids (count and two sums,
  no strings), `at` is `s.lastClock` (os.time seconds, see O), `c` is the cargo key (`"P1,5"`) or false; `cargoFromKey`
  rebuilds `{ pax, cargo, key }` from it. An entry expires after `CARGO_TTL + lineId % CARGO_SPREAD` s (30 s + up to
  15 s, spread per line). Entries of deleted lines go in the once-per-pass clean-up (B). If upstream changes
  `lineCargo`'s body, merge it into `readLineCargo`; if the result gains fields beyond `pax`/`cargo`/`key`,
  `cargoFromKey` must rebuild them too.
  *Behaviour:* a changed load config on existing vehicles shows up within about 30–45 s. New or removed vehicles show
  up at once. The state grows by about 40 bytes per line.
  *History:* rev 1 kept the cache per VM (module local, keyed on the id string). Run 1 measured only 53% hits: the
  simulation VMs take turns sweeping, so each VM missed every line once per TTL (2026-10-10).
- **E. Fingerprinted terminal tags in the signature** [2]. In `sweep`, `tags(group)` caches
  `params.fingerprint(net.groupTags(group))` instead of the raw tag list, which made stored signatures (`s.checked`,
  `s.retry[].sig`) long. Only compared for equality.
  *Behaviour:* the signature format changed, so after loading a save made with upstream (or the first time) every
  line is re-checked once. Terminals stay the same, and the "changed by player → manual" check doesn't fire, because
  that needs equal suffixes.
- **F. Stop slots in one pass** [3]. `local allSlots = params.stopSlots(comp.stops)` per line replaces the O(n²)
  `params.stopSlot(comp.stops, i)` calls in the override clean-up and the signature loop.
- **G. lineModes once per line** [6]. Module-local `modesMemo` (set to `{}` around `pcall(sweep, s)` in `runSweep`,
  `nil` after) memoises `lineModes(line)` by component. In the loop, `local modes = lineModes(comp)` feeds
  `lineKind(modes)` and the signature suffix (`table.concat(modes, ",")`).
- **H. describeSets only with debug logging** [6]. In `assignStop`'s candidate loop, `local debugOn = options().debugLog`
  makes the two `dropped[...]` strings skip `describeSets(x)` when it's off.
- **I. Removed (2026-10-10), the build handler is upstream's again.** It tried `state:get_native():findPath({ "stations", g })`
  per new group in place of a full `state:get()`. In game, every call threw `gamescript_util.cpp:385` "Assertion 'false'
  failed" on the Simulation Thread. The pcall fallback kept behaviour correct, but each build event logged a fatal error
  and could write a crash dump. Don't reintroduce it; see `docs/findings.md` "Game-script `get_native` asserts".

- **O. Sweep interval on real seconds (os.time)** (2026-10-10). Above `BATCH_MS`: `clock` is now the engine wall
  clock (`wallClock`, seconds; `os.clock` fallback) and only used for debug timings; the new `realTime = os.time`
  (falls back to `clock`) drives `timing()` and the `not realTime and dt` check in `update`. Upstream timed the
  interval with `os.clock`, which is process CPU time on macOS (all threads together), so a 2 s interval passed in
  well under 2 real seconds: run 1 measured ~1.7–1.8 sweep ticks/s and 0.82 passes/s instead of one pass per 2 s.
  `s.lastClock`, settle times (`SETTLE_S`, `SETTLE_MAX`) and `INVERT_S` all use the same clock, so they are now real
  seconds at 1 s resolution: a settling line sweeps about every 1 s instead of 0.5 s.
  *Behaviour:* sweeps at the configured interval in real time (fewer than before on macOS); `s.lastClock` from an
  older save is far in the past, so the first update sweeps at once. On Windows `os.clock` is wall time, so upstream is
  right there; this is a macOS/Linux fix. **Not measured in game yet**: the cause of the 1.7×/s is inferred from
  `os.clock`'s known behaviour (`docs/findings.md` "Timers and threads in GUI contexts").

**`content/aat_net.lua`**

- **J. TRANSPORT_NETWORK and tpNetData memo per sweep call** [4]. Module-local `tnCache`/`tpCache` and
  `net.beginCache()`/`net.endCache()` are called in `runSweep` around `pcall(sweep, s)`. `networkOf(entity)` is used by
  `edgeOf` (so by `net.path`, `legsAt` and `net.pathPrint`), and `tpNetData()` by `net.groupTerminals` and
  `net.path` (the `countChanges` branch). Outside a sweep (GUI,
  build events) both read through as before. The caches never live across ticks.

**`content/aat_params.lua`**

- **K. New helpers** `M.stopSlots(stops)` (for F; returns the same strings as `stopSlot`) and `M.fingerprint(str)`
  (for E; `"len.hex.hex"`, two polynomial hashes mod primes below 2^31, so they stay exact in doubles; never contains
  `#` or `|`). Inserted right after `M.stopSlot`. Tests: `tests/square_opt_zhenya_auto_assign_terminals/test_params.lua`.

**GUI, `content/gui/aat_eow.script.lua`**

- **L. Partial state read** [1]. `readState()` first tries `readNative(gs)`, which reads only `STATE_KEYS` through
  `gs.state_native:find(key)` (`:asTable()` on native subtables). It falls back to the full `gs.state` copy. If
  upstream's GUI starts reading another state key, **add it to `STATE_KEYS`**, or it will silently be nil.
  *Behaviour:* the `state_native` path isn't verified in game. On failure the fallback is the old full copy (correct,
  but slow).
- **M. Polling every 0.25 s instead of every frame** [1][5]. `POLL_S = 0.25`, and the five
  `engine_react_util.useStepState(fn, nil, same)` calls (`AatRefreshButton`, `AatStopRefreshButton`, `AatStationCard`,
  `AatStopCard`, `AatLinePlugin`) are now `useStepStateTimer(fn, POLL_S, same)`. A new `useStepState` from upstream
  should get the same treatment.
  *Behaviour:* cards and buttons update up to 0.25 s later.
- **N. Game-bar widget and hasChoice** [1][5]. `AatLhtPrompt` polls `pollLht` every 0.5 s. `pollLht` skips the state
  read once `lhtDone and (introShown or introDone)` and then only keeps open dialogs alive. `introDone` is set in
  `checkLht` when the state says `intro == "done"`. `hasChoice(group)` is memoised for `CHOICE_S` = 1 s in
  `choiceMemo`.

- **P. One state read and one LINE read shared by all pollers** (2026-10-10). `readState()` keeps its result for
  `SHARE_S` = 0.1 s in `stateMemo`, and the new `lineComp(line)` keeps LINE components for the same window in
  `lineMemo` (replaced each window, so it never grows). `lineProblem`, `AatStopRefreshButton`, `AatStopCard` and
  `AatLinePlugin` call `lineComp` in place of `getComponent(..., LINE)`. Each card and button polls on its own 0.25 s
  timer (M); the line manager's stop list has a refresh button per stop, each of which read the state and the line
  itself, so 20 stops meant ~80 state copies/s. `hasChoice`'s memo (N) uses the same `shareNow()` wall clock in place of
  `os.clock`. Callers only read the shared tables, so keep it that way.
  *Behaviour:* what a card shows can be up to 0.1 s older (on top of M's 0.25 s).

## Open questions

- **22 vs 24 initial line updates.** On the same unsaved save, the original sent 22 line updates (250 lines assigned)
  in its first pass, and the optimized code sent 24 (253). See PERFTEST.md, run 1. It's unknown whether the 2 extra come
  from a behaviour difference (e.g. A's multi-tick pass or E's re-check) or from timing (retries, builds during the
  run). Compare the assigned terminals of both runs line by line before trusting the fork with a big save.
- **Sweeps ran ~1.7×/s across the simulation VMs** instead of once per `interval` (2 s). Likely cause, fixed in O:
  `os.clock` is CPU time. Confirm in game (a perf run should show ~0.4–0.5 passes/s). Parallel VMs may still sweep
  twice in one step now and then (`docs/findings.md`, hitch probe: "more than one game-script pause per period").
- **Not done from the audit:** a dirty flag so `runSweep` only calls `state:set(s)` when something changed [2]. Every
  sweep tick still writes the full state. Low priority: run 1 measured `stateSet` at 0.3 ms/s.
- **Next candidate: per-tick fixed cost of a multi-tick pass.** Every tick of a pass re-reads all LINE components,
  sorts them and calls `getLineProblems`, even when it resumes at the cursor. Unmeasured; either read LINE components
  lazily from the cursor on (keeping the sorted order in `s.cursor`), or raise `BATCH_MS` now that the hitch probe
  showed game-script pauses don't delay frames (`docs/findings.md`, 2026-10-10).
- Run 1 measured about 1 min per mode with unmatched routines. A second, matched run would firm up the numbers.

## Merge log

Newest first: upstream revision merged, date, conflicts and how they were resolved.
