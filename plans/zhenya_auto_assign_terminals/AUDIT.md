# Auto Assign Terminals: performance audit

Mod: `zhenya_auto_assign_terminals` (Zhenya_, mod.io 6416135), revision 19, copied 2026-10-09 to `original/`.
This is a third-party mod: the copy is for reading and local experiments only. Don't republish it without the author's OK.
The way to share fixes is upstream to the author.

Everything below comes from reading the code. Nothing has been timed in game yet (see "Measuring" at the end).

## How it runs

- **Game script** (`aat.script.lua`, `update`): every `interval` seconds (default 2 s, real time, also while paused) it
  runs `sweep()` over **every player line**. For each line it builds a signature string. If the signature matches
  the stored one, nothing else happens; otherwise the stops are assigned again (path searches) under an 8 ms budget per tick.
- **GUI** (`gui/aat_eow.script.lua`): the station window card, the line window card, the stop config card, the refresh buttons,
  and an invisible game-bar widget (`AatLhtPrompt`). All of them poll through `engine_react_util.useStepState`,
  which calls the getter **every GUI frame** (`react.onStep`, `engine_react_util.tl:91`).

## Findings, highest impact first

### 1. The GUI copies the whole game-script state every frame, forever (GUI, high)

`readState()` (`aat_eow.script.lua:17`) reads `GAME_SCRIPT.state`, which converts the **entire** saved state into a fresh
Lua table. `AatLhtPrompt` → `checkLht` (`:560`) is mounted in the game bar for the whole session and calls
`readState()` on every frame, even after the left-hand-traffic notice and the intro are long done. Each open
station, line or stop card and each refresh button does another full copy per frame.

The state is large (see #2). The cost scales with the number of lines and is paid at frame rate, as allocation and GC churn.

Fixes:
- `checkLht`: once `lhtDone and introShown` (or the state says `intro ~= "ask"`), return immediately without reading state.
- Read only the keys you need through `state_native` the way the base game does
  (`industry_productivity_util.tl:11`: `gameScript.state_native:findPath({...}):asTable()`), e.g.
  `findPath({"stations", tostring(group)})`, `find("force")`, `find("settle")`.
- Poll with `engine_react_util.useStepStateTimer(fn, 0.25)` in place of `useStepState`. Nothing here needs per-frame
  updates; the game script only changes state every 0.5–2 s.

### 2. The saved state holds very long signature strings (both sides, high)

Each entry in `s.checked[line]` (and `s.retry[line].sig`) is the full signature (`:922`). Per stop it contains
`tags(group)`, which is `"stationEntity.tag"` for **every terminal of the station group** (`aat_net.lua:31`). A
10-stop line through 12-track stations comes to about 2–4 KB, so a few hundred lines make 0.5–1 MB of strings.
That state gets:
- deep-copied by `state:get()` and written back by `state:set()` on **every sweep** (`:1201`, `:1181`), whether or not anything changed,
- deep-copied on **every build** of any kind (`handleEvent` `onPostBuildProposal` → `state:get()`, `:1228`) just to check `stations`,
- copied by the GUI every frame (#1),
- written into the savegame.

Fixes:
- Store `hash(suffix)` in place of the suffix. The suffix is only compared for equality (`:930`); only the `keys`
  part before the first `#` is parsed. The keys part should stay readable.
- In the build handler, use `state:get_native():findPath({"stations", g})` in place of `state:get()`.
- Only call `state:set(s)` when the sweep changed something (a dirty flag). Most sweeps change nothing but `lastClock`/`lastSweep`.
  Those two could stay in VM-local variables, as long as the cross-VM comments around `lastSeen` still hold. That needs a check in game.

### 3. The steady-state sweep reads every vehicle of every line every 2 s, without a budget (game script, high)

The 8 ms `BATCH_MS` budget only covers network checks and reassignment. Building the signature for **all** lines
runs in a single tick with no budget, and includes:
- `lineCargo(lineId)` (`:58`): `getLineVehicles` plus `getComponent(TRANSPORT_VEHICLE)` for **every vehicle**.
  That component is big (config, capacities, allCaps, per-part autoLoadConfig). With 2,000 vehicles, that is 2,000
  heavy component conversions every 2 s. This is the most likely cause of a periodic stutter in large games.
- `getComponent(LINE)` twice per line (once for priority sorting, `:785`, once in the loop, `:824`), plus a third full
  pass in `spreadLoad` when anything gets assigned.
- Per stop: `params.stopSlot` (O(i), so O(n²) per line; `aat_params.lua:91`), `effectiveSettings` (several table
  allocations), `stopLoads`, `altPairs`/`stopKey`, and string concatenation.
- `getLineProblems()` for all lines, every sweep.
- Clean-up passes: `entityExists` plus `getComponent(STATION_GROUP)` for every stored station group, every sweep (`:1069`).

Fixes:
- Cache `lineCargo` per line, keyed on the vehicle id list, and re-read one or two lines' vehicles per sweep
  round-robin to catch load-config edits. A new or removed vehicle still changes the key at once.
- Make the signature phase resumable: keep a cursor and stop after the budget, the same way the reassignment phase already does.
- Read each LINE component once per sweep and reuse it for priority, the loop and `spreadLoad`.
- Compute all stop slots in one pass (a running count per group) in place of calling `stopSlot(i)` per stop.
- Run the station-group clean-up every Nth sweep. A deleted station isn't urgent.

### 4. `edgeOf` re-converts whole TRANSPORT_NETWORK components (assignment path, medium)

`edgeOf` (`aat_net.lua:4`) calls `getComponent(entity, TRANSPORT_NETWORK)` for one edge. For a station or
other construction, that component holds **all** of its edges and nodes. It is called per path step in
`net.path`, again per port in `legsAt` (each turnout within 1.5 km of either end), and per step in
`pathPrint`. A 20-track station gives 40 path searches per stop, each one re-reading the same station component
many times.

Fix: memoise `getComponent(TRANSPORT_NETWORK)` per entity for the duration of one sweep. Pass a cache table, or reset a
module-local one at the start of `sweep`.

### 5. Station window refresh button: every line's stops per frame (GUI, medium)

`refreshStatus({group})` (`aat_eow.script.lua:164`) calls `getLinesForStationGroup` and then, for **each line**,
`lineProblem`: LINE component, `getLineVehicles`, and per stop `hasChoice` (STATION_GROUP plus every STATION component plus
a `pcall` into the street connector system) and `stopSlot`. It does this every frame while the station window is open. On a
hub with 40 lines that adds up to thousands of component reads per frame. The line-manager button does the same for all selected lines.

Fix: the timer from #1 (0.25–0.5 s) covers most of this. Also cache `hasChoice(group)` per poll, since it is
called once per stop with the same group.

### 6. Smaller items (low)

- `lineModes(comp)` is rebuilt 2–3 times per line per sweep (`:839`, `:922`, and in `assignStop`). Compute it once.
- `describeSets` strings for dropped terminals are built even with debug logging off (`:362`, `:364`); only
  `debug()`'s output is gated.
- `net.path` calls `getTpNetData()` per call. It's cheap, but it can be hoisted per sweep alongside #4.

## What not to change

- Keep the modId and the `aat.gs` resource name, or existing saves lose their state (`aat.gs.lua` says so).
- A staging copy with the same modId **overrides** the subscribed mod (CLAUDE.md). That's useful for an A/B test, but
  remember to unlink it afterwards.

## Measuring before/after

The mod already has timing: turn on the `debugLog` mod setting and it prints `[AAT] sweep X ms` per sweep and
`network checks X ms` (`:1177`, `:1048`). For a baseline, load a large save, leave it at 1x for a minute, then save the log.
Instrumenting #1 and #3 needs a few extra `os.clock()` lines around `lineCargo` and `readState`.

## Suggested order

1. #1 (GUI per-frame state copy, plus the timer). Small, isolated, safe.
2. #2 (hashed suffix, dirty-flag `state:set`). The new suffix format never matches stored ones, so every line gets
   one re-check after the update. The "changed by the player → manual" check needs equal suffixes, so it won't
   fire by mistake. Unchanged results send no command. Expect one heavier sweep after loading, as with a `RULES` bump.
3. #3 (lineCargo cache, resumable signature phase).
4. #4 (TRANSPORT_NETWORK memo).
