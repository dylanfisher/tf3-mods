# In-game console: try an API call in seconds

The first step for any "does this API call work / what does it return" question (CLAUDE.md "Testing a question in
the game"). The console opens with the key below Esc (`, § or ^ depending on the layout) and runs Lua live with `api`
available. Input runs once it is syntactically complete, so a pasted multi-line block works too (wiki
`modding/tools/ingame.md` "Console"). Up/Down recall the history; Ctrl+Space and Tab autocomplete API names.

Verified facts (multi-statement lines, `sendCommand` callbacks, where `print` goes): `docs/findings/debugging.md`.

## Writing a snippet for the user

- One line where possible (`local a = ...; api.cmd.sendCommand(...)`), ready to paste.
- Take inputs from where the player is: the camera centre `api.gui.camera.getCameraData()` (`.x`, `.y`), the point
  under the cursor `api.gui.mouse.getTerrainPosition()` (the mouse must be over the map when Enter is pressed), or
  an entity the player clicks (the log prints `Selected entity <id>`).
- `print(...)` the result. A command's result comes in the `sendCommand` callback: `function(d, ok) print("ok=", ok, ...) end`.
- `print` output lands in the live `stdout.txt` (no timestamp prefix) and may not show in the console. Read it with
  `make logs-grep PAT='...' ARGS='--session live'`.
- A line that returns a value (an expression, or a call like `M.who()`) has it echoed: in the console and in
  `stdout.txt` as a timestamped line with the value in quotes (2026-10-20, `[SQOT] WHO` twice, once bare from `print`,
  once quoted). A Lua error (e.g. "attempt to call global 'who' (a nil value)") shows **only in the console window**,
  not in `stdout.txt`: ask the user what the console showed when the log has nothing. The typed lines are kept in
  `console-history.lua` (the Steam userdata `local/` folder, beside `crash_dump/`; newest last), handy to see what was
  actually run.
- Nothing of a mod is global in the console: call helpers through `ug_require("<modId>::/<path>.lua").fn(...)`, the
  whole line each time.
- Finding an edge near a point: `findEntitiesInCircle(p, r, BASE_EDGE)` matches an edge by its middle, so search with
  r = the wanted distance + half the longest edge, then keep the nearest by curve (findings roads.md).
- List the alternative argument forms to try if the first fails (e.g. a file name with or without `::/`).
- Say when the snippet changes the save (spends money, builds, spawns). Never chain a destructive step after a test.
- Every loop in a snippet has a fixed count (the game thread rule in CLAUDE.md applies to the console too).

## Good first tries

| Question | Snippet |
|---|---|
| Where am I looking? | `local c = api.gui.camera.getCameraData(); print(c.x, c.y, c.z, c.w, c.q)` (centre x/y, distance, angle, pitch: `Vec5f` fields `x y z w q`) |
| Where is the cursor? | `local p = api.gui.mouse.getTerrainPosition(); print(p.x, p.y, p.z)` |
| Does entity N exist, what is it? | `print(api.engine.entityExists(N), api.engine.getComponent(N, api.type.ComponentType.ANIMAL))` (swap the component type; list: `api/tealdef/api/engine.d.tl` `record ComponentType`) |
| Is a resource loaded? | `print(api.res.modelRep.find("::/animal/cougar/cougar.mdl"))` (index, -1 when missing) |
| Does a command work? | `api.cmd.sendCommand(api.cmd.makeXxxCmd(...), function(d, ok) print("ok=", ok, d) end)` |
| Show me the result | `api.gui.camera.focusEntity(id)` moves the camera to an entity |
| Who is the player, how much money? | `local p = api.engine.util.getPlayer(); print(p, api.engine.util.finance.getPlayersBalance(p))` |

Rows other than the camera, cursor and `sendCommand` callback are untested in the console itself: when one works or
fails, note it in `docs/findings/debugging.md`.

## Our mods' console helpers

A mod module can be `ug_require`d from the console and its functions called, but it gets its own copy (below): a
helper must read what it needs from the engine or a game script's saved state (`state_native`), never from a GUI
plugin's or the game script's module tables.

| Mod | Question | Snippet |
|---|---|---|
| Organic Towns | Who built this street (the mod, which plan piece, or the game)? | Hover the street, then paste the whole line `ug_require("square_organic_towns::/organic_towns/ot_prov.lua").who()` (a bare `who()` is undefined); or `.who(<edge id>)`, `.who(<x>, <y>)`. Prints `[SQOT] WHO edge= ... ours=yes / likely / probably / no ...`, or `WHO no street within 40 m ... the nearest street <d> m` / `WHO error <reason>` (`make logs-grep PAT='\[SQOT\] WHO' ARGS='--session live'`). Records from 2026-10-19 on, the newest ~700 edges of the map (`plans/square_organic_towns/PLAN.md` §75 "Follow-ups built"). Loads and prints in game (2026-10-20); the 40 m search missed a long street before the 300 m octree circle (fixed, to confirm). |
| Better Auto Vehicle Renamer | Which fleet number does each vehicle have, which names are ours, which typed by hand, how many numbers are retired? | Paste the whole line `ug_require("square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_console.lua").reg()` (`.reg(2000)` lists more). Prints `[SQFN] REG B-0205 id= type= t= a= m= lp= model= year= line= status=ours / pending / hand-typed / untouched old= parts= wagons= name=` per vehicle (the first 500, then `REG ... N more vehicles not listed`), `REG numbers <letter> next= held= retired=` per type and `REG summary vehicles= records= ours= ... stale= old= welcome= counter=`; returns the summary line (`make logs-grep PAT='\[SQFN\] REG' ARGS='--session live'`). Read-only: the saved state through `state_native:find(...):asTable()`, the vehicles through the mod's reader. Untested in game (`plans/square_better_auto_vehicle_renamer/TESTING.md` I). |

## What the console can't do (use a DEV/probe mod)

- Event handlers and anything that has to run over many ticks (a console line runs once).
- Stylesheets (`.css.lua` runs in its own Lua state) and load-time code (`runFn`, construction/model modifiers).
- Read a GUI plugin's module state: a console `ug_require` of a mod module gets its own copy, not the plugin's
  (2026-10-15: Smart Lanes' background plugin ran its `g.auto` runtime, SQPERF `ctx=bg ... auto n=3309` every 30 s,
  while `ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"` in the console had `g.auto == nil`; inferred:
  the console runs in a separate Lua state or module cache). Check plugin state through its log lines instead.
  A module that requires `::/gui/main/react.lua` doesn't even load there (2026-10-18, Line Manager Plus
  `lmp_util_avg.lua`: `ERROR Missing builtin recipeId for WithComponentParams` at `react.lua(433)`).
- GUI layout and look checks that need a real window in a mod.
