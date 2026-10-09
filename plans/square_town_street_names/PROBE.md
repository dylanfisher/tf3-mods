# Town Street Names probe (mods/square_town_street_names_probe)

DEV ONLY, never upload. It's read-only unless the **Rename test (DEV)** mod param is switched on. Background and
open questions: `research.md` §6.

What it adds:
- A game script (`content/tsnprobe/tsnprobe.script.lua`) that logs `[SQTSN_PROBE]` lines.
- A name set **"DEV TSN Probe"** (`content/names/tsn_probe/`). It names towns Seattle, Tacoma, Spokane, ... first,
  and streets "Probe Street 01".."Probe Street 80" in a fixed order. It logs every call.

Mod params, set in the mod list when starting or loading a game:

| Param | Values | Default |
|---|---|---|
| Rename test (DEV) | Off (read-only) / Rename station group / Rename station (stem) / Rename station (forceSameEntity) | Off |
| Event discovery (DEV) | All events (logs the first 3 of each kind) / Build events only | All events |

If the params dialog misbehaves, set `RENAME_TEST_OVERRIDE = "group"` at the top of `tsnprobe.script.lua` instead.
The `subscribed ... renameTest=<mode> (raw <value>)` line shows what the script read.

## Run

0. `make link` (the probe isn't linked yet). Close the game first, since the mod list is read at start.
1. Watch the log in a terminal:
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered SQTSN_PROBE`
2. **Run A, a new game with the probe name set (read-only).** Free game, enable **DEV Town Street Names Probe**,
   leave both params at their defaults, and pick the name set **DEV TSN Probe** in the game settings. Use a small map
   with a few towns.
   - During map generation and load, expect `names towns call=...` and maybe `names streets call=...` lines.
   - After load: `subscribed mode=all`, `init Lua state`, `dump towns: N` (towns should be Seattle, Tacoma, ...),
     `dump NAME census`, `dump street edges`, `dump station groups`, `baseline: ...`.
   - Optional: `gui script loaded`.
3. In **Seattle**, build three **Road Stops** (small edge-object stops) on **one** street, a few blocks apart, then
   one on a **different** street. Wait about 3 s after each.
   - Expect `build onPostBuildProposal ... edgeObjectsToAdd=1 [cat=0 result=... pos=...]`, then
     `NEW (via postBuild|poll, lastBuild=...) group <id> NAME=... name=... stem=...@...` with the `station` / `edgeObjectConstruction` / `edge=` / `town:` lines below it.
   - Note each stop's default name. Are they "Probe Street NN"? Does the same street repeat the stem with
     East/West/#2 suffixes? Does each `names streets call` line come right before a stop?
4. Build a **Two-Sided Road Stop**, and one Road Stop right next to an existing stop (does it join the group?
   Look for `NEW station ... in group <existing>` or `station ... moved group`).
5. Build one Road Stop on a **country road outside any town**. The `town:` line shows what each method returns there.
6. Build a **Bus/Tram Station** (the modular street station) in Tacoma. Expect `toAdd=1{...modular_terminal.con}`,
   `build   result <id> fileName=...`, then a `NEW` group with `kind=construction`.
7. **Player renames.** Click one of the step 3 stops and rename it in the window title (e.g. "Probe Renamed").
   Click Seattle and rename the town (e.g. "Seattle Renamed"). Within about 2 s expect `name change group ...` and
   `name change town ...`, including whether NAME went from `no` to `yes`. Also look for `name change` lines for
   stations or construction stations that follow the town rename by themselves.
8. Save the game (keep it for run B). Open the line manager and a stop's window: are there any `gui event` lines?
9. **Run B, the rename test.** Back in the main menu, load the save from step 8. In the mod list set **Rename test
   (DEV)** = "Rename station group". Build two Road Stops (in Seattle).
   - Expect `rename queued #1 ... -> "Pike Street"`, then on the next scan `rename #1 sent=true ... before: ...`,
     `rename #1 callback success=true`, and `rename #1 verify (wanted "Pike Street"): group ... | station ...`.
   - The second stop is also set to "Pike Street": does the verify line show "Pike Street" again, or "Pike Street #2" / "Pike Street East"?
   - Check in game: does the stop window and the line manager show the new name? Is it visible on the map label?
10. Optional: repeat step 9 with "Rename station (stem)" and "Rename station (forceSameEntity)" (one load each,
   2 stops each). Note which one changes what the player sees.
11. Optional: load an **existing save** (not the probe name set) with the probe on. This checks that the probe works when added to
   an old save: you should get a `baseline` line and no errors. Build one stop to see default names from your normal name set.

Paste the `[SQTSN_PROBE]` lines (or `grep SQTSN_PROBE stdout.txt > tsn_run1.txt`) and note what the UI showed.
Any `ERROR` line comes from the probe catching an exception, so paste those too. Crash: see the crash-dump memory
note, and disable the probe first.

## Which line answers which question

| Question (research.md §6) | Lines |
|---|---|
| 1 Stop names come from the street pool; same-street suffixes | `NEW ... group ... name=` for steps 3-4 vs `names streets call ... first=` |
| 2 Which entity carries NAME (group / station / edge / construction) | `NAME=` on the group, `station` and `edge=` lines; `dump NAME census` (NAME counts by kind); `dump street edges` |
| 3 When streetNamesScript runs, with which num | `names streets call=N lang= num= clock=` (time-ordered against the `build` lines) |
| 4 Town lookup after a build / outside towns | `town: stationSystem.getTown ... | util.town.getClosestTown ... | nearestCentre ... d=` |
| 5 New group vs joining an existing one | `NEW (via ...) group` vs `NEW station ... in group <old>` / `station ... moved group` |
| 6 Rename target, stickiness, duplicates | `rename #n sent/callback/verify`, and in-game UI |
| 7 Player renames, NAME presence, construction names following the town | `name change <kind> <id> "<old>" (NAME yes/no) -> "<new>" (NAME yes/no)` |
| 8 Build events and update in one Lua state? | `NEW (via postBuild ...)` = same state (module-local flag); `via poll, lastBuild=none` right after a build = different states. `init Lua state <token>` repeating = state recreated |
| Which hooks fire for a stop build | `event #n src= id= name=` and `gui event #n ...` (first 3 of each kind), `event counts` every 2 min |

## Notes

- The probe's saved state holds the known station-group and station ids (baseline) and up to 400 watched names.
  Throwaway saves only. Removing the probe from a save gives the normal "mod removed" warning.
- A save that used the **DEV TSN Probe** name set may need the probe to load (name sets look save-bound, see
  research.md §1). Don't use it on a real save.
- `make test MOD=mods/square_town_street_names_probe` runs an offline smoke test with a fake world. It only guards
  against typos.

## Results

(fill in after the run)

## Results: run 1 (2026-10-08)

New game, "DEV TSN Probe" name set, rename test Off, 7 Road Stops in Seattle. Answers are in
`docs/findings.md` "Street names and Road Stops". Short version: names come from the pool in list order
(not per street), they live on the station group, `onPostBuildProposal` gives the real station id,
`getTown` works right away, and event-to-update flags don't share a Lua state.

Still open: rename-test modes (D2), player renames of a stop/town, two-sided and adjacent stops,
stops outside towns, bus/tram stations, whether the "next unused" counter is per town or global.

## Results: run 2 (2026-10-08)

Rename test "station group" works: the group and its station both show the new name, duplicates are
not suffixed, and a freed default name is reused for the next stop. Settles D2 (target = station
group, no forceSameEntity needed). The real mod must avoid duplicates itself.

## Probe 3 (climate visibility, station names)

Added 2026-10-08 for the State Names series. What it logs: `plans/square_state_names/research.md` §4.3. Run steps: `plans/square_state_names/PLAN.md` "Probe 3".
