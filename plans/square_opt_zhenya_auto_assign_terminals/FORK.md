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
- **D. lineCargo cache** [3]. The original `lineCargo(lineId)` body is now `readLineCargo(lineId, vehicles)`. It takes
  the vehicle list instead of reading it. The new `lineCargo(lineId)` reads `getLineVehicles` and keys
  `cargoCache[lineId]` (per VM) on the vehicle id list. An entry expires after `CARGO_TTL + lineId % CARGO_SPREAD` ms
  (30 s + up to 15 s, spread per line, no per-sweep refresh cap). If upstream changes `lineCargo`'s body, merge it into
  `readLineCargo`.
  *Behaviour:* a changed load config on existing vehicles shows up within about 30–45 s. New or removed vehicles show
  up at once.
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
- **I. Build handler reads only the stations it needs** [2]. In `handleEvent` `onPostBuildProposal`,
  `state:get_native():findPath({ "stations", g })` per new group replaces a full `state:get()`, which is still the
  fallback when the pcall fails.
  *Behaviour:* `get_native`/`findPath` are typed in the API but not verified in game. If they throw, the fallback keeps
  behaviour identical, but the saving is lost.

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

## Open questions

- **22 vs 24 initial line updates.** On the same unsaved save, the original sent 22 line updates (250 lines assigned)
  in its first pass, and the optimized code sent 24 (253). See PERFTEST.md, run 1. It's unknown whether the 2 extra come
  from a behaviour difference (e.g. A's multi-tick pass or E's re-check) or from timing (retries, builds during the
  run). Compare the assigned terminals of both runs line by line before trusting the fork with a big save.
- **Sweeps run ~1.7×/s across the simulation VMs** instead of once per `interval` (2 s). Each VM seems to sweep on
  its own: `lastSeen` is VM-local, and `s.lastClock` is only read after `loadState`. Not fixed in the fork, and
  upstream has the same behaviour. It's the next candidate.
- **Not done from the audit:** a dirty flag so `runSweep` only calls `state:set(s)` when something changed [2]. Every
  sweep tick still writes the full state.
- Run 1 measured about 1 min per mode with unmatched routines. A second, matched run would firm up the numbers.

## Merge log

Newest first: upstream revision merged, date, conflicts and how they were resolved.
