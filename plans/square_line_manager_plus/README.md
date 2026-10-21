# Line Manager Plus: design notes

Status: current design reference (rev 5), except the vehicle list features of revs 3-5 (only the cargo row in the
table below; PLAN.md "Open work").

`square_line_manager_plus` combines GUI-only Line Manager features in one mod, each behind its own mod setting:

| Feature | Param key | From | Module |
|---|---|---|---|
| Send to Line: target line info | `send_to_line_info` | `square_send_to_line_info` (never published, retired) | `content/line_manager_plus/stli.lua` + `stli_core.lua` |
| Send to Line: before/after estimate | `send_to_line_estimate` | new (PLAN.md feature 2, phase 3) | `content/line_manager_plus/stli_estimate.lua` (+ `stli_core.estimate`) |
| Line editor: Undo and Redo buttons | `line_undo` | `square_line_revert` "Line Editor Undo" (published, rev 4) | `content/line_manager_plus/undo.lua` + `undo_core.lua` + `lmp.css.lua` |
| Line list: line info on hover | `line_list_hover_info` | new (PLAN.md feature 3; replaced the colour dot tooltip `line_dot_tooltip`, user request 2026-10-11) | `content/line_manager_plus/line_list_hover.lua` (+ `lmp_callout.lua`, `lmp_stats.lua`, `lmp.css.lua`) |
| Send to Line list: line info panel | `send_to_line_list_info` | new (PLAN.md feature 1, phase 4) | `content/line_manager_plus/stl_list.lua` (+ `lmp_callout.lua`, `lmp_stats.lua`, `lmp.css.lua`) |
| Line editor: Line actions button (Duplicate / Reverse / Duplicate + reverse line) | `line_actions` | new (PLAN.md feature 4, phase 5) | `content/line_manager_plus/line_ops.lua` + `line_ops_core.lua` (+ `lmp_actions.lua`, `lmp.css.lua`) |
| Line actions: Match line rate | `line_rate_matcher` | `square_line_rate_matcher` "Line Rate Matcher" (never published, retired; merged 2026-10-11, MERGE_RM_PLAN.md) | `content/line_manager_plus/rate_matcher.lua` + `rate_matcher_*.tl` (+ `lmp_actions.lua`, `lmp.css.lua`) |
| Map: Shift-click a line opens the Line Manager | `map_shift_click` | `square_passenger_destinations` rev 5 (moved before upload, 2026-10-11) | `content/line_manager_plus/map_shift_click.lua` (+ `lmp_line.script.lua` / `lmp_line.res.lua`) |
| Map: line info on hover | `line_map_hover_info` | new (user request 2026-10-11) | `content/line_manager_plus/line_hover.lua` (+ `lmp_stats.lua`, `lmp.css.lua`) |
| Vehicle list: current cargo | `vehicle_list_cargo` | new (player request 2026-10-11) | `content/line_manager_plus/vehicle_cargo.lua` (+ `lmp.css.lua`) |

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
    (ctx = `{ params, line }`), each view/run in its own pcall. Duplicate / Reverse / Duplicate + reverse (line_ops.lua) and Match line
    rate (rate_matcher.lua, order 50, first in the menu; it needs `line_actions` On and reports "not installed" otherwise). Balance
    vehicles was dropped, PLAN.md D8. `lmp_capture.resetEditorMode` is shared by
    undo and Reverse.
  - `lmp_stats.lua`: the one `stli_core` model (base modules, formatters, Clock, 1 s cache per line) shared by every
    feature that shows a line's numbers (Send to Line info, the line info callouts, the map hover). `stats.lines(entity)` errors
    propagate; callers pcall and fall back to vanilla. Warnings as `[LineManagerPlus] stats: ...`.
  - Both read the base function inside `install()` (other mods' wrappers stay in the chain), install once, and warn
    once as `[LineManagerPlus] capture: ...` / `rows: ...`.
- `lmp_perf.lua`: the one SQPERF instrument of the GUI state, shared by every feature (sections `view`,
  `button_render`, `click`, `descriptor`, `toggle_button` for undo; `tooltip` for Send to Line; `list_hover` for the
  line list's hover block; `stl_list` for the Send to Line list block; `line_actions` for the Line actions menu and its clicks; `map_click` for Shift-click; `vehicle_cargo` / `vehicle_cargo_read` / `vehicle_cargo_cell` for the vehicle list's cargo badge; `rate_matcher_step`,
  `rate_matcher_render`, `rate_matcher_click` for the Rate Matcher window; `rate_matcher_catalogue`,
  `rate_matcher_calibration` (cache misses only) and `rate_matcher_empty` for its engine; `buy_filter` for the Buy
  Vehicles cargo filter's clicks). Module copy:
  `content/sqperf/square_line_manager_plus.lua` (`make sqperf-sync`).
- Log prefix `[LineManagerPlus] `; the features add `send to line: ` / `estimate: ` / `undo: ` / `list hover: ` /
  `list info: ` / `line ops: ` / `rate matcher: ` / `map shift click: ` / `vehicle cargo: ` (and `line actions: ` for the menu host).
- Match line rate: empty lines (2026-10-19). A line with no vehicles has no Rate and no LineCargoInfo, so the window
  estimates from geometry (docs/findings/lines-vehicles.md "Line Rate formula"): Rate per vehicle = capacity x 1460 /
  round trip (s), round trip = D x detour / top speed + S x dwell, D = the straight cyclic round trip through the S stops
  (station construction position, else the station's bounding box centre for curbside stops). detour / dwell = medians
  over up to 200 of the player's other lines of the same carrier with single-part vehicles (clamped 1-4 and 0-120 s),
  typical values below 3 samples (water 1.5 / 25 s, road and tram 1.9 / 9 s, air 2.6 / 21 s); cached per carrier for
  3 game minutes. Depot, carrier, transport modes and filter tags come from `line_util.getBestDepotForLine` (as the
  line editor's Buy Vehicles button), so the catalogue is what that store would list. The window shows one table
  (the comparison's columns: per model the count nearest the target, ≈ Rate, Price, Cost/yr, Cost per unit; the
  lowest cost per unit preselected and "best") and a note on the route and where the times come from; Apply buys them
  at that depot onto the line (`commands.buyOntoLine`: the switch's buy step, money all or nothing). Train lines, no
  depot, unreadable stop positions, < 2 stops, no cargo or no buyable model: a reason text instead. Code:
  `rate_matcher_model.tl` (calibrate, estimatePlans), `rate_matcher_engine.tl` (emptyLineInput, calibration,
  stopPositions), `rate_matcher_view.tl` (buildEmpty, estimateNote), `rate_matcher_window.tl` (estimateSection).
- Teal: the Rate Matcher modules are Teal (`rate_matcher_*.tl`) with their types in
  `content/line_manager_plus/rate_matcher_types.d.tl` (loaded as a def module by make check / make test). `tealdef/`
  is the editor-only copy for `make teal`: `tealdef/line_manager_plus/rate_matcher_types.d.tl` (byte copy; make check
  flags drift), `tealdef/sqperf/` and `tealdef/square_line_manager_plus_def.d.tl` (`make sqperf-sync` maintains them).
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

## Line list: line info on hover (PLAN.md feature 3, reworked 2026-10-11)

Hovering anywhere on a line's row in the Line Manager's line list shows the line's info block (name, vehicles by
model, the stats row; no estimate) at once, as a callout OUTSIDE the Line Manager window: right of it (left when the
window's centre is in the right half of the screen), top aligned with the row. The same block, look and behaviour as
the Send to Line list's: both go through `lmp_callout.lua`. It replaced rev 1's first build, the stats appended to the
colour dot's tooltip (`line_dot.lua`, `line_dot_tooltip`; user, 2026-10-11: "same behaviour for both boxes, not just
the coloured circle"). Design and evidence: header of `line_list_hover.lua`. In short:

- The row recipe `LineAndDepotListEntry` (file-local) is the cell recipe of the list's `builtin.DataTable` column
  (manager_window.tl:2722-2736). The row keeps its own hover in a local state through `react.onMouseEvent`, one
  listener per recipe (react.lua:768), so nothing can be added inside it.
- Hook: the module field `builtin.ColumnDesc` is wrapped with a plain function. Only for one table whose `recipe` is
  named `LineAndDepotListEntry`, it passes a copy whose recipe is a plain cell function (one per inner recipe, stable
  across renders) calling `inner(react.ref(holder), { rowKey, colKey, userParam, meta = { onMouseOver = ... } })` in
  place: no extra node, the row sees the same params (react strips `meta` and applies it to the row's node, react.lua:
  308-374), its own mouse listener and tooltip stay. `holder` is a plain object react hands the row's node ref
  (`:set`), which then serves as the callout's parent (`:get` / `:hasExpired`).
- `onMouseOver(true)` opens the block through the module's one `lmp_callout` tracker (text built only then,
  lmp_stats 1 s cache); `onMouseOver(false)` closes it if it is that row's. No onStep, no state. Position by
  `getPositionFn` (the container calls it each step): x = `commonParams.lineAndDepotListRef`'s right / left edge, y =
  the row's top; padding `M.GAP` = 18 px clears the window's card padding (8 px) and border. A read failure keeps the
  last position; the container drops the block when the row node is gone (Line Manager closed, row deleted).
- `install()` shims the shared replacement api like the other module-field wrappers.
- Look: the shared callout (`R::SquareLmpInfoCallout`, class `sq-lmp-stli`): 0 new stylesheet rules.

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
- Since 2026-10-11 the block is a callout outside the popover (header of `stl_list.lua`), drawn by `lmp_callout.lua`
  (recipe `SquareLmpInfoCallout`), shared with the line list's hover block. The first build (a panel inside the card, one stylesheet
  rule): HISTORY.md, "moved from README.md".
- `install()` also shims the shared replacement api, so a later `ReplaceRecipe(<our wrapper>, x)`
  gets the recipe we wrapped.
- Strings: only the param name and tooltip (13 languages); the line name is the game's, the stats lines are stli's.

## Line actions: Duplicate and Reverse line (PLAN.md feature 4)

A "Line actions" button right of A+ opens a small popover menu with **Duplicate line**, **Reverse line** and
**Duplicate + reverse line** (decision D1; the third added 2026-10-20), after Match line rate. Design and evidence: headers of `lmp_actions.lua` (button and menu) and `line_ops.lua` (the two actions). In short:

- Button: a copy of the A+ button (base manager_window.tl:3518-3572): `ToggleButton` with A+'s classes
  `"vehicle-button, secondary"` (same look, no stylesheet rules), icon `line_vehicle_mgmt/icons/symbol_burger_menu.tga`
  (base, 48x48 @2x). Value = "menu open". Opens `popover_react_util.PopoverWindow` under our own key at A+'s popover
  anchor (`commonParams.configureLinesPopoverPosRef`) with A+'s window classes `"configure-lines, management"`; closes
  only our window (`removeWindow`). A+'s press/release "locked" handling is copied. The menu's unmount tells the button
  it closed (a generation counter keeps an older window's unmount from clearing a newer one). Shown only for exactly
  one selected, edited, unprotected line (as undo); otherwise an empty BoxLayout, and an open menu closes.
- Menu (`SquareLmpLineActionsMenu`, restyled 2026-10-20, user choice "Auto-Rename rows"): looks like the base
  Auto-Rename popover beside it (AutoRenameDialog, manager_window.tl:3085-3305; its rules are scoped
  `R::AutoRenameDialog`, so not reusable). A header card "Line actions" (font-scale-headline) built **inline**
  (card_surface + card_contour nine-patches, BaseVeryLight at Low, border BaseVeryLight, size -1 x 36, padding
  2/8/2/8; the base margin 8/8/1/8 as the inline padding of a wrapper Component; both of base class
  `horizontal-spacer` to fill the width). Rows: one `builtin.Button` per entry, content = a `horizontal-spacer`
  Component (fills the button, so icon + text sit left) with icon, a 4 px inline spacer and the label
  (font-scale-body); the rows in a Component with inline padding 3/6/10/6 (the base ScrollArea's margin + padding).
  **3 stylesheet rules** (`R::SquareLmpLineActionsMenu Button` base state: AccentMedium at High, invisible border,
  gravity -1/0.5, margin 2/4/2/4, padding 4/8/4/8; `:hover` AccentLight; `:active` getActiveFromRaw(AccentMedium)):
  inline sheets have no states, margin or gravity. Disabled rows: an inline NeutralMedium wash at VeryHigh plus the
  base disabled text grey; the reason stays in the tooltip. The entries' views are polled per step (`useStepState`).
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
- Duplicate + reverse (order 300): one `makeLineCreateCmd` with `M.reversed(line, comp)` (the reverse's stops and the
  engine's terminals for the new direction, asked of the original line), named and coloured as Duplicate, selected on
  success; the original line and the editor mode are untouched. Guards of both (blockReason + the 3-stop reason); a
  mirror-image route gives the reverse's "same stops" message and sends nothing. Log `duplicated line N reversed as M`.
- Guards: < 2 stops or a stop whose station is gone → entry disabled, the reason as tooltip (re-checked on click); a
  command in flight → both disabled (cleared by the callback or after 10 s, logged). Failures in a view/run are
  isolated per entry. No noPath check after the reverse (the path is computed later by the engine; not reliable from
  the callback): the player sees the vanilla line problem and can Undo.
- Strings: 13 new UI texts + param name/tooltip (13 languages). The copy's name is stored translated, as the editor's
  "Line N".

## Map: line info on hover (added 2026-10-11)

User request: with the Line Manager open in its normal mode, hovering a line on the map should show the same block as
the Send to Line hover text (vehicles by model; Capacity, Utilization, Frequency, Rate), without the estimate.
Design and evidence: header of `line_hover.lua`. In short:

- Hover signal: the manager's main mode (base `manager_window.tl:230` makeActionMainMode) already picks the entity
  under the mouse (`pickedEntity`, :292) and for a line sets `ctx.tooltip(manager_tooltips_util.SelectLine,
  details.line)` (:321-322, "Select Bus Line 1."). Send to Line mode does the same with `VMSendToLine` (:1242-1247),
  which stli.lua wraps. So no new hover detection: we wrap `SelectLine` (manager_tooltips_util.tl:24-28, used nowhere
  else) with `ReplaceRecipe` and `react.CallOriginalRecipe`, exactly like stli.lua. The tooltip only exists while the
  manager's action mode does, so with the manager closed nothing of ours runs; hovering anything but a line never
  renders `SelectLine`.
- Params: `LineUtil.LineSelectionDetails` `{ entity, stopNumber, apiStopIndex0, apiWaypointIndex }`
  (line_util.tl:314-321); we read `entity` only. Vanilla returns nil for a gone entity; then our block is empty too
  (the isLine check in `stli_core`), so the recipe returns an empty BoxLayout.
- Stats: `lmp_stats.lines(entity)` (no vehicles: no estimate), 1 s cache per line, shared with the other features.
- Look: same TextView classes as stli.lua; the `sq-lmp-stli` CSS rule got a second selector part
  `R::SquareLmpLineHoverInfo TextView!sq-lmp-stli` (+1 rule).
- Own setting `line_map_hover_info` (default On), independent of `send_to_line_info`; FEATURES row last.
  SQPERF section `map_hover`. Failures logged once as `[LineManagerPlus] map hover: ...`.

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
button-row injectors), `test_line_list_hover.lua` (line list hover block: ColumnDesc wrap, pass-through, cell function, callout open/close/placement, fallbacks), `test_stl_list.lua` (Send to Line
list panel: install, detection, swap, list and panel recipes, estimate setting, fallbacks), `test_line_ops_core.lua`
(reverse order, waypoint moves, terminal re-pick, copy names, guards), `test_line_ops.lua` (Line actions button and
menu (structure and inline styles), Duplicate / Reverse / Duplicate + reverse commands and callbacks, busy guard, undo integration), `test_map_shift_click.lua` (Shift-click:
install and guard, line / empty map / open line windows, allowed tools, `builtin.Selector` restore, chain with a
Passenger Destinations style wrapper in both orders), `test_line_hover.lua` (map hover text: install, SelectLine
wrap, block without estimate, 1 s cache, fallbacks), and from the former Line Rate Matcher
`test_rate_matcher_model.lua`, `test_rate_matcher_view.lua`, `test_rate_matcher_engine.lua` and
`test_rate_matcher_gui.lua` (the Match line rate menu entry, the window, Apply, an expired closed-manager state, the
empty-line estimate and its Apply).
`tests/square_line_revert/` keeps the old mod's tests plus `test_detect.lua` (copy identity) and the stand-down
tests at the end of `test_script.lua`.
