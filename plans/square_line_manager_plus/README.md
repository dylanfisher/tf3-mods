# Line Manager Plus: design notes

`square_line_manager_plus` combines GUI-only Line Manager features in one mod, each behind its own mod setting:

| Feature | Param key | From | Module |
|---|---|---|---|
| Send to Line: target line info | `send_to_line_info` | `square_send_to_line_info` (never published, retired) | `content/line_manager_plus/stli.lua` + `stli_core.lua` |
| Send to Line: before/after estimate | `send_to_line_estimate` | new (PLAN.md feature 2, phase 3) | `content/line_manager_plus/stli_estimate.lua` (+ `stli_core.estimate`) |
| Line editor: Undo and Redo buttons | `line_undo` | `square_line_revert` "Line Editor Undo" (published, rev 4) | `content/line_manager_plus/undo.lua` + `undo_core.lua` + `lmp.css.lua` |
| Line list: stats on the color dot | `line_dot_tooltip` | new (PLAN.md feature 3, phase 2) | `content/line_manager_plus/line_dot.lua` (+ `lmp_stats.lua`) |
| Send to Line list: line info panel | `send_to_line_list_info` | new (PLAN.md feature 1, phase 4) | `content/line_manager_plus/stl_list.lua` (+ `lmp_stats.lua`, `lmp.css.lua`) |
| Line editor: Line actions button (Duplicate / Reverse line) | `line_actions` | new (PLAN.md feature 4, phase 5) | `content/line_manager_plus/line_ops.lua` + `line_ops_core.lua` (+ `lmp_actions.lua`, `lmp.css.lua`) |
| Map: Shift-click a line opens the Line Manager | `map_shift_click` | `square_passenger_destinations` rev 5 (moved before upload, 2026-10-11) | `content/line_manager_plus/map_shift_click.lua` (+ `lmp_line.script.lua` / `lmp_line.res.lua`) |

All feature params: `uiType` Button, values `{"Off", "On"}`, `defaultIndex` 1 (On). At runtime the value is the 1-based
index (Off = 1, On = 2); a missing table or key counts as On. `sqperf_log` (Debug: performance log) stays, default Off.

Nothing is saved: GUI only, `severityAdd`/`severityRemove` None, `cosmetic` true, safe to add to or remove from saves.

## Install path

- `lmp_replace.res.lua`: one `react-replacement-config` (order 250), read by base `gui/main/bootstrap_game.tl:12-47`,
  which calls `lmp.script.lua`'s `doReplace` once at GUI start.
- `lmp.script.lua` `doReplace`: reads the params (`lmp_detect.modParams`), then per feature, each in its own `pcall`:
  param Off → log `"<feature>: off (mod setting)"`, skip; stand-down check (undo only, below); `ug_require` the
  feature module (inside the pcall, so a module that fails to load costs only that feature) and call its
  `install(replacementApi, params)` (params = this mod's, so a feature can read another feature's setting:
  stl_list reads `send_to_line_estimate`). A failure is logged once (`[LineManagerPlus] <feature>: ...`); the other feature still
  installs. `data().status` holds the outcome per key (installed / off / stood down / not installed / failed).
- Shared groundwork (PLAN.md phase 1), so a base function is wrapped once however many features need it:
  - `lmp_capture.lua`: one wrapper of `line_util.makeLineActionDescriptor`; keeps the latest manager `commonParams`
    (`params()`) with accessors `editedLine()`, `selectedLineCount()`, `selectedVehicles()`.
  - `lmp_rows.lua`: one wrapper of `button_react_util.makeIconToggleButton`; at the A+ icon inside
    `LinePanelActionButtons` it builds `BoxLayout{ <order < 0>..., A+, <order >= 0>... }` from the registered
    injectors (`register{ id, order, build = fn(ctx) -> {nodes} | nil }`, `ctx.params` = the captured params), each
    build in its own pcall; nothing added → the base node unchanged. Undo is injector `undo`, order -100.
  - `lmp_actions.lua`: the "Line actions" toggle button right of A+ (an `lmp_rows` injector, order 100) and its
    popover menu. Menu entries: `actions.register{ id, order, label, icon, view(ctx) -> {enabled, tooltip}, run(ctx) }`
    (ctx = `{ params, line }`), each view/run in its own pcall. Duplicate / Reverse today; the Line Rate Matcher
    registers here later (Balance vehicles was dropped, PLAN.md D8). `lmp_capture.resetEditorMode` is shared by
    undo and Reverse.
  - `lmp_stats.lua`: the one `stli_core` model (base modules, formatters, Clock, 1 s cache per line) shared by every
    feature that shows a line's numbers (Send to Line info, the colour dot tooltip). `stats.lines(entity)` errors
    propagate; callers pcall and fall back to vanilla. Warnings as `[LineManagerPlus] stats: ...`.
  - Both read the base function inside `install()` (other mods' wrappers stay in the chain), install once, and warn
    once as `[LineManagerPlus] capture: ...` / `rows: ...`.
- `lmp_perf.lua`: the one SQPERF instrument of the GUI state, shared by every feature (sections `view`,
  `button_render`, `click`, `descriptor`, `toggle_button` for undo; `tooltip` for Send to Line; `dot_tooltip` for the
  colour dot; `stl_list` for the Send to Line list panel; `line_actions` for the Line actions menu and its clicks). Module copy:
  `content/sqperf/square_line_manager_plus.lua` (`make sqperf-sync`).
- Log prefix `[LineManagerPlus] `; the features add `send to line: ` / `estimate: ` / `undo: ` / `dot tooltip: ` /
  `list info: ` / `line ops: ` / `map shift click: ` (and `line actions: ` for the menu host).
- One plugin besides the config: `lmp_line.res.lua` (react-plugin `::LineEowExtensionPoint`, order 99) mounts
  `lmp_line.script.lua`'s `LmpLinePlugin` in every line window. It draws nothing and only tells `map_shift_click.lua`
  which line windows are open; registered whatever the setting.

## Send to Line info (unchanged design from square_send_to_line_info)

Line Manager, vehicle mode, Send to Line: hovering a line on the map shows the vanilla tooltip
"Send N vehicles to <line>." (`manager_tooltips_util.VMSendToLine`, base
`gui/line_vehicle_mgmt/manager_tooltips_util.tl:245`, set at `manager_window.tl:1241-1247`). The feature adds below it:
the line's vehicles grouped by model and the Capacity / Utilization / Frequency / Rate of the Line Manager's
statistics row (`manager_window.tl:3940-4000`).

Robustness (game updates):

- Wraps, never rewrites: `react.CallOriginalRecipe(VMSendToLine, params)` renders the vanilla node with untouched
  params; only `params.lineOrDepotEntity` is read.
- Every step in pcall: install (require, recipe check via `react.GetRecipeId`, `ReplaceRecipe`), the vanilla node,
  the stats. Any failure leaves the vanilla tooltip and logs one line per kind.
- Stats come from the same base helpers the footer uses (`statistics_react_util.calculateCargoColumnDataForLine`,
  `line_util.calculateFrequencySeconds`, `api.engine.util.line.calcLineStationThroughput`, `api.util` formatters,
  `lang_util.formatInt`), each optional and in its own pcall: a renamed helper drops one value, not the tooltip.
- 1 s cache per line (`stli_core.lua`, `api.type.Clock` microseconds, safe on every thread), cleared at 64 entries.
- Style: the vanilla tooltip class string (`line_react_util.makeTooltip`); no stylesheet of our own.
- Recipe root is a `builtin.BoxLayout` (recipe name `SquareLmpSendToLineInfo`).

## Send to Line: before → after estimate (PLAN.md feature 2)

With the vehicles about to be sent, the Send to Line hover text's stats read e.g. `Capacity: 40 → ~80  ·  Utilization:
50%` / `Frequency: 7 min 19 s → ~4 min 53 s  ·  Rate: 66 → ~132` (two rows whenever an arrow shows, so the tooltip
stays narrow; one row as before otherwise). Formulas, evidence and edge cases: header of `stli_core.lua`. In short:

- Own setting `send_to_line_estimate` (default On), FEATURES row right after `send_to_line_info`. It extends that
  tooltip: `stli_estimate.install()` returns false (log line "needs ... On") unless `stli.isInstalled()`, installs
  `lmp_capture` and calls `stli.enableEstimate(capture.selectedVehicles)`.
- Selection: `lmp_capture.selectedVehicles()`; used only when its count equals the tooltip's `params.numVehicles`
  (otherwise current values only, nothing guessed). `stats.lines(line, vehicles)`.
- n = line vehicles, k = selected vehicles with `TRANSPORT_VEHICLE.line ~= line`, add = Σ `stli_core.vehicleCapacity`
  (load-config `config.capacities` for the line's cargo set from `getLineCapacityUsages(line, false)`; 0 there → best
  `allCaps` entry; unknown set → the whole load config). Capacity + add; Frequency × n/(n+k); Rate × (cap+add)/cap
  (the verified linear rule for identical vehicles). Utilization: no estimate (a snapshot of cargo aboard; current value).
- No arrow: k = 0, n = 0 (Frequency/Rate; Capacity still `0 → ~add`), capacity 0 (Rate), a value that rounds to itself.
  Selected vehicles that can't carry any of the line's cargo add a line "Selected vehicles that can't carry this line's
  cargo: N".
- Cache: the line's stats per line for 1 s as before; the text per selection key (entity list) inside that entry
  (≤ 8 texts); the cargo set once per entry. Each step (cargo set, selection, estimate) in its own pcall: a failure
  drops only the arrows, logged once as `[LineManagerPlus] stats: ...`; a failing selection read in stli.lua as
  `send to line: selection`.
- Glyphs: `→` is in Lato (docs/findings.md, GUI font glyphs; `↑` from the same check verified in game), `~` is ASCII,
  Noto Sans CJK has both. 0 stylesheet rules.

## Line list: stats on the colour dot (PLAN.md feature 3)

Hovering only a line's colour dot in the Line Manager's line list adds `stats.lines(line)` (vehicles by model, the
stats row; no "Send N vehicles" line) below the dot's vanilla tooltip "Open Line Window". Design and evidence: header of
`line_dot.lua`. In short:

- Wraps the module field `line_react_util.ColorWidget` (plain function; installed in `doReplace` like the others).
  Acts only for one table argument with `onClick` and a numeric `entity` while `react.getCurrentRecipeName()` is
  `LineAndDepotListEntry` (base manager_window.tl:2154; depot rows have no dot). Everything else goes to the previous
  function unchanged.
- Returns `SquareLmpLineDot{ prev, param }`: root BoxLayout around `prev(param)`, with `react.onMouseEvent`
  Entered/Exited (returns false) keeping a hovered flag. Only while hovered is the param copied with the stats appended
  to `tooltip`; not hovered, the caller's table goes through as is. Non-line entity or any error: untouched param
  (logged once).
- The field now holds a plain function, which react can't map to the recipe. `install()` therefore wraps the shared
  replacement api's `ReplaceRecipe` (one table for every config, bootstrap_game.tl:39-48): a later mod's
  `ReplaceRecipe(line_react_util.ColorWidget, x)` is handed the recipe we wrapped. Remaining edge: another mod's
  `react.GetRecipeName/CallOriginalRecipe(line_react_util.ColorWidget)` after our install sees no recipe (none known).
- Look: vanilla tooltip (a string; the tooltip window isn't under our recipe, so a scoped rule can't reach it).
  0 stylesheet rules. No refresh while the tooltip stays up; the next hover after 1 s reads fresh numbers.

## Send to Line list: line info panel (PLAN.md feature 1)

The Send to Line popup (title, First Stop combo box, list of lines; base `SendToLineSelection`, manager_window.tl:
4513-4690, file-local) gets a panel to the **right** of the list (decision D2) while a row is hovered: the line's name,
`stats.lines(line, selection)` (vehicles by model, the stats row, and the before → after estimate when
`send_to_line_estimate` is On; selection = the popover's `params.selection`, the vehicles being sent). Nothing hovered:
no panel. Design and evidence: header of `stl_list.lua`. In short:

- Wraps the module field `popover_react_util.PopoverWindowContent` with a plain function (chain-safe; UI Overhaul and
  Easy Terminal Assignment do the same for the terminal popover). Not `ReplaceRecipe`: Auto Assign Terminals already
  replaces that recipe (it captured the base recipe at load, so it stays behind us in the chain).
- Swaps only when called with one table whose `recipe` is named `SendToLineSelection` (`react.GetRecipeName`) and whose
  params have a `selection` table and `commonParams.sendToLineHoveredLineState`. The copy keeps every other field
  (onClose, meta) and gets `recipe = SquareLmpStlList`, `params = { inner, innerParams }`. Anything else, or an error,
  goes to the previous function unchanged (logged once). Other popovers are never touched.
- `SquareLmpStlList`: horizontal `BoxLayout{ inner(innerParams), SquareLmpStlPanel{...} }`. The vanilla list renders
  with its own params and doesn't re-render when the hover changes; only the panel does.
- `SquareLmpStlPanel`: own state, polled with `react.onStep` (Main Thread): `commonParams.sendToLineHoveredLineState:old()`,
  a set only on a change. Text built only for a hovered line (lmp_stats, 1 s cache). Root BoxLayout, empty when nothing
  is hovered. No refresh while one row stays hovered.
- `install()` also shims the shared replacement api, as line_dot.lua does, so a later `ReplaceRecipe(<our wrapper>, x)`
  gets the recipe we wrapped.
- Look: one TextView with the tooltip text classes + `sq-lmp-stl-panel`: **one new stylesheet rule**
  (`R::SquareLmpStlPanel TextView!sq-lmp-stl-panel`: the approved dark info-block colour, margin 8/8/8/0, gravity
  top-left). Its width comes from the longest line, so translated text fits. The window grows to the right while the
  panel shows; near the right screen edge it may reach past it (not handled; UI Overhaul moves its terminal popover
  back on screen after layout, a possible follow-up).
- Strings: only the param name and tooltip (13 languages); the line name is the game's, the stats lines are stli's.

## Line actions: Duplicate and Reverse line (PLAN.md feature 4)

A "Line actions" button right of A+ opens a small popover menu with **Duplicate line** and **Reverse line** (decision
D1). Design and evidence: headers of `lmp_actions.lua` (button and menu) and `line_ops.lua` (the two actions). In short:

- Button: a copy of the A+ button (base manager_window.tl:3518-3572): `ToggleButton` with A+'s classes
  `"vehicle-button, secondary"` (same look, no stylesheet rules), icon `line_vehicle_mgmt/icons/symbol_burger_menu.tga`
  (base, 48x48 @2x). Value = "menu open". Opens `popover_react_util.PopoverWindow` under our own key at A+'s popover
  anchor (`commonParams.configureLinesPopoverPosRef`) with A+'s window classes `"configure-lines, management"`; closes
  only our window (`removeWindow`). A+'s press/release "locked" handling is copied. The menu's unmount tells the button
  it closed (a generation counter keeps an older window's unmount from clearing a newer one). Shown only for exactly
  one selected, edited, unprotected line (as undo); otherwise an empty BoxLayout, and an open menu closes.
- Menu: `SquareLmpLineActionsMenu`, vertical BoxLayout of `button_react_util.makeIconTextButton("secondary", icon,
  label, ...)`; the entries' views are polled per step (`useStepState`). **One new stylesheet rule**
  (`R::SquareLmpLineActionsMenu Button`: gravity -1/0.5, margin 4/8/4/8) so the buttons share one width.
- Duplicate: `makeLineCreateCmd(name, line_util.makeLineColor(player), player, undo_core.build(snapshot))`; name
  `"{name} (copy)"`, or `"{name} (copy {n})"` with the smallest free n ≥ 2 among `getLinesForPlayer` names
  (`line_ops_core.copyName`). Vehicles untouched. Success: `commonParams.selectLine({ entity = new }, true, nil)` (the
  map's select-line path; deselects all first, so the fresh line list includes the new line), only when that manager's
  params are still the captured ones. Refused: feedback "the game refused the new line".
- Reverse: `line_ops_core.reverse` (`[s1, sn, ..., s2]`, each stop keeps its settings; segment waypoints move to the
  stop that now starts that segment, reversed), then `lineSystem.getBestLineAssignment(line, comp, true)` per stop
  (`applyAssignment`: negative/missing answer keeps the player's terminal; a new terminal that was an alternative swaps
  with the old main one); a failing query keeps all terminals (logged once). Unchanged result → message, no command.
  Else `resetEditorMode` and `makeLineUpdateCmd`. Undo needs no code: its per-step poll records the change as one edit
  ("stops reordered"), so one Undo restores the original.
- Guards: < 2 stops or a stop whose station is gone → entry disabled, the reason as tooltip (re-checked on click); a
  command in flight → both disabled (cleared by the callback or after 10 s, logged). Failures in a view/run are
  isolated per entry. No noPath check after the reverse (the path is computed later by the engine; not reliable from
  the callback): the player sees the vanilla line problem and can Undo.
- Strings: 13 new UI texts + param name/tooltip (13 languages). The copy's name is stored translated, as the editor's
  "Line N".

## Map: Shift-click a line opens the Line Manager (from square_passenger_destinations rev 5)

Moved from Passenger Destinations before its rev 5 upload (2026-10-11); the behaviour was verified in game there the
same day (plans/square_passenger_destinations/PLAN.md section F, "Game test 2026-10-11, round 2" point 2). Design and
evidence: header of `map_shift_click.lua`. In short:

- Shift (`api.gui.inputAction.modifierOnlyActionIsActive("IA_PRECISION_MODE")`) + click on one of the player's lines
  (`PLAYER_OWNED.player == api.engine.util.getPlayer()`) fires `react.fireEvent(nil, "openVehicleManager",
  { openWithLineEntity = line })`, the line window's own "Manage Line" call (base entity_window/line/line.tl:140-149).
- With a line window open (`lmp_line.script.lua` keeps the list, oldest first), Shift + click on anything that opens
  no window (`view_manager_util.wouldCreateView` nil, or `onSelectNothing`) manages the newest open line. The line
  window draws its line unselectable, so a click on it lands on what is under it.
- Only while the top tool (`game_react_globals.getDefaultToolStackApi().getActiveTool().name`) is `EntityDetailsTool`
  (plain map, entity windows) or `SquarePassengerDestinations` (Passenger Destinations' tool while its Shift hover
  arrows show). Anything else selects as usual; a failing check too (logged once).
- Hook: wraps the field `selector_react_util.makeDefaultSelector`; per call it swaps `builtin.Selector` for a function
  that wraps `onSelect` / `onSelectNothing` in a copy of the params, and afterwards sets `builtin.Selector` back to
  exactly the function it replaced (also on error). Guard flag `squareLmpShiftClick` on the module table.
- Coexistence with Passenger Destinations: it wraps the same field for its Shift hover (proxy ref, guard
  `squarePaxDestShift`, installed when its entry-point plugin loads). Each mod wraps whatever the field holds when it
  installs, so the chain works in either order, with one of them, or with neither. Passenger Destinations clears its
  own Shift hover arrows once another tool (the Line Manager this opens) is on top; this module never touches them.
- Strings: only the param name and tooltip (13 languages). 0 stylesheet rules. SQPERF section `map_click`.

## Undo (unchanged design from square_line_revert rev 4)

See `plans/square_line_revert/PLAN.md`. Only renames: recipe `SquareLmpUndoButton` (the CSS scope in `lmp.css.lua`,
5 rules), feedback texts start with "Line Manager Plus:" instead of "Line Editor Undo:", log prefix
`[LineManagerPlus] undo: `, `install()` instead of `doReplace` (returns true/false). Since PLAN.md phase 1 the two base
wrappers live in `lmp_capture.lua` / `lmp_rows.lua` (same behaviour, same SQPERF section names).

## Line Editor Undo coexistence

`mod.json` lists `square_line_revert` under `incompatibilities` (and Line Editor Undo rev 5 lists us), so the game
warns at activation. If the player keeps both, exactly one set of buttons must appear:

- **Detection** (`lmp_detect.lua`; identical copy `square_line_revert/content/line_revert/line_revert_detect.lua`,
  a test keeps them equal): a mod is active when one of its `react-replacement-config` resources is in
  `api.res.genericRep` (filePath starts with `"<modId>::"`), the same `getAllOfType` call as the bootstrap.
  Evidence that the repository only holds active mods' resources:
  - base `gui/main/bootstrap_game.tl:12-47` calls the `doReplaceFn` of every config it finds there. If a disabled
    mod's config were listed, the bootstrap would run that mod's code. And whatever the bootstrap finds is exactly
    what gets installed, so this check answers the real question ("will its buttons appear?") either way.
  - base `mission/mission_sim.script.tl:206-210` registers every `missiontask_boot` resource as the running
    mission's task, and `:593-594` treats any as "a mission is running", while all 8 campaign mission mods that
    declare one (`mods/release/urbangames_campaign_mission_0N/content/mission/mission.res.lua`) are always
    installed. That only works if disabled mods' resources are absent.
  - Not used: `pcall(ug_require, "square_line_revert::/square_line_revert_presence.lua")`, since whether it fails
    for an installed but disabled mod is unverified.
- **Hand-shake**: Line Editor Undo rev 5 adds `yieldsTo = "square_line_manager_plus"` to its config data and stands
  down (installs nothing, one log line) while we are active with `line_undo` On (it reads our param with
  `getModParams`). We stand down only for a Line Editor Undo config **without** that marker (rev 4 or older, e.g.
  the mod.io version until rev 5 is uploaded), logging one line. Outcomes:

  | Active mods | Undo buttons from |
  |---|---|
  | LMP only | LMP (if `line_undo` On) |
  | LMP + Line Editor Undo rev 5 | LMP; Line Editor Undo logs its stand-down. With LMP's `line_undo` Off: Line Editor Undo |
  | LMP + Line Editor Undo rev ≤ 4 | Line Editor Undo; LMP logs its stand-down (Send to Line info still installs) |
  | Line Editor Undo only | Line Editor Undo |

  Load order doesn't matter: both decide from the resource repository and params, not from what the other did.
- **Fallback**: a failing detection call counts as "not active" in both mods (two sets of buttons are better than
  none) and is logged once.
- Unverified in game: that `genericRep.get(id).data` keeps the extra `yieldsTo` field (the engine has no schema for
  this resource type; the bootstrap reads `order`, an optional field, the same way), and that `getModParams()`
  returns our params during `doReplace` (a failure there means "On").

## Tests

`tests/square_line_manager_plus/`: `test_stli_core.lua`, `test_stli.lua` (from send_to_line_info),
`test_stli_estimate.lua` (estimate math, edge cases, selection path, install),
`test_undo_core.lua`, `test_undo.lua` (from line_revert), `test_detect.lua` (detection helper), `test_lmp.lua`
(param gating, stand-down, failure isolation with stubbed feature modules), `test_groundwork.lua` (capture and
button-row injectors), `test_line_dot.lua` (colour dot tooltip: wrap, pass-through, hover, fallbacks), `test_stl_list.lua` (Send to Line
list panel: install, detection, swap, list and panel recipes, estimate setting, fallbacks), `test_line_ops_core.lua`
(reverse order, waypoint moves, terminal re-pick, copy names, guards), `test_line_ops.lua` (Line actions button and
menu, Duplicate / Reverse commands and callbacks, busy guard, undo integration), `test_map_shift_click.lua` (Shift-click:
install and guard, line / empty map / open line windows, allowed tools, `builtin.Selector` restore, chain with a
Passenger Destinations style wrapper in both orders).
`tests/square_line_revert/` keeps the old mod's tests plus `test_detect.lua` (copy identity) and the stand-down
tests at the end of `test_script.lua`.

## Follow-up: the Send to Line dropdown list

Done in phase 4 as "Send to Line list: line info panel" above (a panel, not a row tooltip).
