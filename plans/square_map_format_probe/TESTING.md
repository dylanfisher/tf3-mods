# Map Format probe: testing

DEV mod `mods/square_map_format_probe` (never upload; deleted 2026-10-13 after the three crashes below, this file kept as the record). Question: can a mod make maps in formats the new-game
menu doesn't offer (1:6, 1:8, turned 5:1 / 2:1)? Background: the menu's sizes are hard-coded in
`base/content/gui/menu/new_game_or_map_settings_page.tl` `getNumTiles` (x is always the short side), the format
list is a base `mod.json` param, and a mod can't replace a base file (`docs/wiki/modding/general/resourcetypes.md`
"File Names & References": every mod has its own `<modId>::/` namespace). So the probe restarts the map editor
itself on a blank map: `app.startGame2(map, ..., isMapEditor = true, ...)`.

## Run 1

1. `make link`, start the game, Map Editor → new map (any size, e.g. Small 1:1), enable **DEV Map Format Probe**.
2. In the editor, top-left: the size button cycles presets (default `1:8 Large 20 x 160`). Click **Stop + new map**.
3. In the new editor: the map's shape (minimap / overview), then Generate heightmap, towns, industries.
4. Save it as a map, back to the main menu, Play Map → that map → start a game. Does it load and run?
5. Repeat with `5:1 Large (turned)` and one big one (`1:8 Huge`, 28 x 224).

Evidence: `[SQMF]` lines in `stdout.txt` (`make logs-grep PAT='\[SQMF\]'`): `restart`, `configDict`, `modParams`,
`mods`, `map ok`, `stopGame`, `startGame2 ok|ERROR` (`stopFirst=true` on every restart now). Results go to `docs/findings/` (new topic or map-camera).

## Open questions

- Does `startGame2` work from a running game at all (Q2)?
- Do the active mods carry over? `getModParams()` may list only mods with params; the `mods` line shows what was passed.
- Turned maps (x > y): any engine assumption that x is the short side (terrain, towns, minimap)?
- Beyond 160 tiles long (1:6 / 1:8 Huge): the base game's longest is 250 (Gigantomaniac 1:5).

## Results

- 2026-10-13 `2026-10-13_2030_sqmf`: **New map** (direct, 1:8 Large 20 x 160) → `startGame2 ok`, then a native
  crash while the new map loaded over the running editor. The first try that day did nothing: getConfigDict's
  list shape (fixed).
- 2026-10-13 `2026-10-13_2035_sqmf`: direct **New map** again (the stop-first button was meant, `stopFirst=false` in
  the log): the same crash. Direct button removed; one button **Stop + new map** left.
- 2026-10-13 `2026-10-13_2037_sqmf` (20:44Z): **Stop + new map** → `stopGame ok`, `startGame2 ok`, the same crash
  at "Debug mode is active"; the old game never logged "Game is stopped". Open: a control with
  `1:5 Large (control)` (a menu size, 24 x 126) would tell whether the restart path or the map crashes.
