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

## What the console can't do (use a DEV/probe mod)

- Event handlers and anything that has to run over many ticks (a console line runs once).
- Stylesheets (`.css.lua` runs in its own Lua state) and load-time code (`runFn`, construction/model modifiers).
- Read a GUI plugin's module state: a console `ug_require` of a mod module gets its own copy, not the plugin's
  (2026-10-15: Smart Lanes' background plugin ran its `g.auto` runtime, SQPERF `ctx=bg ... auto n=3309` every 30 s,
  while `ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"` in the console had `g.auto == nil`; inferred:
  the console runs in a separate Lua state or module cache). Check plugin state through its log lines instead.
- GUI layout and look checks that need a real window in a mod.
