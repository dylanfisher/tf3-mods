# Findings: Game scripts

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Game-script pauses don't stall rendering (2026-10-10)

Probe `square_hitch_probe` (`[HITCH]` lines, report `plans/hitch_probe/hitch_report.py`, steps in its README), a big
save at 1x, camera panning, ~60 fps.

- **A long game-script `update` does not delay rendered frames.** Busy-waiting 40 ms in `update` gave 0 of 13 pauses
  a slow frame, 100 ms gave 0 of 8 (worst frame of that level 50 ms). The control, a 40 ms busy-wait in the GUI's
  `react.onStep`, hit 6 of 6. The tester felt no difference either. `update` runs on `Sim Pool N` / `Simulation Thread`
  threads beside the `Main Thread`. So a slow sweep costs simulation time, not frames; per-frame GUI work is what
  players feel.
- **`GAME_TIME.tickCount` is not per frame**, despite its doc comment ("once per frame"): read from the GUI, it moved by
  4 once per simulation step, about every 200 ms (~20/s), with ~12-18 frames sharing a value.
- Game-script `update` ran in more than one simulation Lua state within the same 40-tick period (10 periods paused
  twice although the period was stored in the shared state), so a "once per interval" guard in a module local or even
  in the state can fire more than once.

## Game-script `get_native` asserts (2026-10-10)

- **`state:get_native():findPath({...})` in a game script's `handleEvent` throws a fatal assertion in game**:
  `gamescript_util.cpp:385` "Assertion 'false' failed" on the Simulation Thread (exception type "Fatal error"). The
  game keeps running when the call is wrapped in `pcall`, but every call logs the fatal error, and the first one wrote
  a crash dump (`crash_dump/*.dmp`, same second). The binary places that file in `GameScriptTableHelper` /
  `SyncTableBack`, the native state accessors (`get_native`, `set_native`; `gamescript.d.tl:42`).
- Evidence: `square_opt_zhenya_auto_assign_terminals` rev 1 called it per new station group in
  `onPostBuildProposal`. It was the only script among 21 active mods that used `get_native`. A save with it active
  logged 10 asserts 2–7 s apart (16:55:32Z–16:56:40Z) during a construction session; earlier unexplained cases
  (02:55Z, 06:32Z) all date from after the fork was linked. Not yet confirmed by a game run without the fork. Which
  call asserts (`get_native` or `findPath`, and whether only for missing paths) isn't isolated.
- Use `state:get()` in game scripts. The GUI-side `gameScript.state_native:find(key)` / `findPath(...):asTable()`
  (used by the base game, `industry_productivity_util.tl:11`) runs on the Main Thread, and no assert came from it in
  the same log.

## Mission marker types are a fixed list (verified in game 2026-10-10)

`api.gui.mission.setMarkerAtEntity/AtPosition(key, ..., type, ...)` (`api/gui.d.tl:719-739`) has no colour argument,
and `type` is not a file path: `MarkerManager` maps it through a fixed table `m_type2modelName` (strings in the
`TransportFever3` binary): `arrow`, `exclamation`, `question`, `question_red`, `locate`
→ `assets/markers/marker_<type>.mdl`. There is **no `exclamation_red` type**, although
`marker_exclamation_red.mdl` exists (its path in the binary is part of a legacy model-rename list). An unknown type
logs `MarkerManager.cpp:33: SetOrAddMarker: Assertion 'm_type2modelName.find(type) != m_type2modelName.end()'
failed` per marker and shows the default model; no Lua error, so pcall doesn't catch it (Supply Gaps rev 4 test
with `exclamation_red`: every marker yellow, assertion in stdout.txt).
Colours (albedo textures in `base/content/assets/markers.zip`): `arrow`/`exclamation`/`question` yellow (~#EBD92B),
`question_red` red, `locate` blue (a different icon). A mod can't add a type or colour; replacing a base marker
model would recolour it for every user (missions, campaign). Supply Gaps uses yellow `arrow` + red `question_red`;
`question_red` renders red in free play (verified in game 2026-10-10).

## guiHandleEvent needs guiUpdateScript and subscribeToEvent (verified in game 2026-10-07)

For a mod game script to receive `api.gui.fireGuiScriptEvent` calls in `guiHandleEvent` (e.g. to veto
"mission.buyVehicle", square_confirm_clone):
1. The `.gs.lua` must register a `guiUpdateScript` (a no-op is fine). Without it the script is never loaded on
   the Main (GUI) thread, only on Sim threads.
2. The engine-side `update` must call `state:subscribeToNoEvents(); state:subscribeToEvent("<event name>")`
   (base/tealdef/scripts/gamescript.d.tl:45-48), guarded by `hasEventSubscriptions()` + a version in state.
   Without it guiHandleEvent is never called, not even for other events.
A string returned from guiHandleEvent vetoes mission.buyVehicle in free play. Reference:
.cache/subscribed/parallel_tracks_1/content/parallel_tracks/parallel_tracks.script.lua:93-99. The wiki only says
"registered gui event"; three in-game rounds were spent finding this.

## No sendCommand inside build-proposal events (2026-10-08)

`api.cmd.sendCommand(...)` while handling `onPreBuildProposal` / `onPostBuildProposal` (`id == "apply_command"`)
throws `Assertion '!m_betweenChanges' failed` (Engine.cpp BeginModification), seen in Lua as `std::exception`
(square_full_refund's journal booking). Store what to send in state and send it from the next `update`. Other
handleEvent sources (square_quota_run) can send. In post, the proposal's removed entity ids no longer match pre:
pair pre/post by counts.

## `.script.lua` exports via `data()` (2026-10-06)

A `.script.lua` referenced as `<modId>::/path/file.script@fn` (e.g. from a `.gs.lua` updateScript) must expose its
functions through a global `function data() return script end`. `return script` loads offline and passes
`make test`, but in game fails every tick with "Expected table at path: game <modId>::/.../x.script"
(luabridge_util.cpp GetPathAsLuaRef; square_no_factory_passengers). Plain helper modules loaded via `ug_require`
still `return M`. Tests should load the script with `ug_require` and call `data()`.
