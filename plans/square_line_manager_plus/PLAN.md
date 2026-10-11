# Line Manager Plus: plan for the next features (research 2026-10-10, docs only, nothing checked in game)

Five features on top of rev 1 (Send to Line info + Undo/Redo, see README.md). Research came from the local game files.
Paths are shortened: `MW` = `.cache/game/base/content/gui/line_vehicle_mgmt/manager_window.tl`,
`LU` = `.../line_vehicle_mgmt/line_util.tl`, `LRU` = `.../line_vehicle_mgmt/line_react_util.tl`,
`VSW` = `.../line_vehicle_mgmt/vehicle_store_window.tl`, `POP` = `.../gui/main/popover_react_util.tl`,
`REACT` = `.../gui/main/react.lua`, `CMD` = `.cache/game/api/tealdef/api/cmd.d.tl`,
`ENG` = `.cache/game/api/tealdef/api/engine.d.tl`, `SYS` = `.cache/game/api/tealdef/api/engine/system.d.tl`.

## Summary

| # | Feature | Param key (Off/On, default On unless noted) | Verdict | Hook |
|---|---|---|---|---|
| 1 | Send to Line list: hover info | `send_to_line_list_info` | **yes** | wrap module field `popover_react_util.PopoverWindowContent` and swap in our recipe around `SendToLineSelection` |
| 2 | Before → after estimate | `send_to_line_estimate` | **yes** (an estimate, marked `~`) | `stli_core` + the captured `commonParams` (map tooltip); `params.selection` (list) |
| 3 | Line stats on the colour dot | `line_dot_tooltip` | **yes** | wrap module field `line_react_util.ColorWidget`, only when called from `LineAndDepotListEntry` |
| 4 | Duplicate line / Reverse line | `line_actions` | **yes** | `makeLineCreateCmd` / `makeLineUpdateCmd`; buttons in the line toolbar |
| 5 | Balance vehicles | (none) | **dropped (2026-10-11)** | the probe showed a re-send can't respace buses and the engine already spaces departures ([PROBE_RESULTS.md](PROBE_RESULTS.md)); no button, no param |

All five stay GUI code in the existing `react-replacement-config` install (`lmp.script.lua` `FEATURES`, one pcall per
feature). Features 4 and 5 send game commands on a click. The results are ordinary vanilla data (a line, a changed
line, re-dispatched vehicles), so the mod stays `severity None` and `cosmetic`.

**Added 2026-10-11 (not a PLAN.md phase):** feature `map_shift_click`, "Map: Shift-click a line opens the Line
Manager", moved from Passenger Destinations rev 5 before its upload (that mod keeps only Shift hover). Design:
README.md "Map: Shift-click a line opens the Line Manager"; in-game test: TESTING.md section of the same name.

## User decisions (2026-10-10)

- In scope: features 1-4 above (feature 5 was in scope until the probe; dropped 2026-10-11, see below). **The Buy vehicle button (former feature 6) is dropped entirely**: no phase, param or
  strings.
- **D1** one "Line actions" popover button in the line toolbar (Duplicate / Reverse, later Rate Matcher).
- **D2** the Send to Line list info panel goes to the **right** of the list.
- **D3** Duplicate gets a **new colour**, like a new line (`line_util.makeLineColor`).
- **D4** Reverse **in place** (undoable with our Undo), **keeping stop 1 first**; no "Reverse as copy".
- **D5** Reverse **re-picks terminals** with `getBestLineAssignment`.
- **D6** Balance: **Option A only** (one-shot re-dispatch, no holding). A DEV probe mod runs first; the param defaults
  Off. **Superseded by D8.**
- **D8 (2026-10-11)** Balance is **dropped entirely**: no Balance button, no `line_balance` param or strings, and no
  read-only spacing indicator either. Reason: PROBE_RESULTS.md (a re-send can't respace road vehicles, they ignore the
  stop index; the engine already spaces departures at line frequency).
- Style: the info block's dark colour in `lmp.css.lua` (a mix of AccentVeryDark and BaseDark) is approved. New info
  panels reuse that look where sensible.
- Params: each feature's param is added in the phase that implements it (a param for a feature that doesn't exist yet
  must not show in game).
- `mods/square_line_rate_matcher*` belongs to another session and isn't touched here (merge note below).

## Shared groundwork (phase 1, **done** 2026-10-10)

Undo used to wrap `line_util.makeLineActionDescriptor` and `button_react_util.makeIconToggleButton` for itself.
The new features need the same two things: the manager's `commonParams`, and a slot in a button row. So that the
same base functions aren't wrapped four times, we add:

- **`lmp_capture.lua`**: installs one wrapper of `line_util.makeLineActionDescriptor` (LU:1023, called by every
  manager mode, e.g. MW:1308 in Send to Line mode). It stores the latest `commonParams` (same test as undo.lua's
  `lineActionDescriptor`: `commonParams.lineManagerStateRef`). Accessors:
  - `editedLine()`: `commonParams.lineState:old().entityAndRevision.entity`
  - `selectedVehicles()`: `commonParams.vehicleManagerStateRef:get().vehicleListEntitiesSelected[*].entity`, as
    MW:62-69 `getSelectedVehicleEntities`
  - `addFeedback`, `lineAndDepotListRef`, `gameCtx`, `vehicleStoreOpenForDepotAndLineRef`, `sendVehiclesToLine`,
    `getFirstStopToSendTo`

  Undo switches to it (behaviour unchanged).
- **`lmp_rows.lua`**: one wrapper of `button_react_util.makeIconToggleButton` (line toolbar, anchor = the A+ icon
  `symbol_autorename.tga` inside `LinePanelActionButtons`, MW:3520). The vehicle-toolbar row (`makeIconButton`) was
  only for the Buy button and is dropped with it.
  Features register injectors `{ id, order, build = fn(ctx) -> {nodes} | nil }` (order < 0 left of A+, ≥ 0 right;
  `ctx.params` = the captured commonParams). The wrapper calls `orig(...)` first and checks
  `react.getCurrentRecipeName()`. It then returns `BoxLayout{ before..., node, after... }`, building each injector in
  its own pcall. A failing injector drops only its own buttons; no node added → the base node unchanged.
  Undo is injector `undo`, order -100.
  Precedent: undo.lua `iconToggleButton`; AAT `aat_eow.script.lua:704-716`.
  Both functions are module fields looked up per call (`button_react_util.tl:31-80`).
- Read the original functions inside `install()`, not at load, so other mods' wrappers (Auto Assign Terminals, Line
  Rate Matcher) stay in the chain.
- `mod.json`: each feature's `{"Off","On"}` Button param (like the existing two) and its
  `FEATURES` row are added **in the phase that implements the feature**, with the name and tooltip in all 13
  languages. A feature whose param is Off doesn't load at all.
- **Line Rate Matcher slot** (another session, not touched here): when it merges into LMP it becomes one more `lmp_rows`
  injector on the line toolbar (`order` before undo, as its plan says "left of A+"), plus a `FEATURES` row with param
  `line_rate_matcher`. Its "clone onto this line" helper (PLAN.md of square_line_rate_matcher, verified in
  docs/findings.md "Line Rate, cloning onto a line") should become the shared `lmp_vehicles.lua`.

Line toolbar crowding: today the toolbar reads [Undo][Redo][A+][paint] ··· [Buy Vehicles] (MW:3500-3680). Adding
Duplicate, Reverse, Balance (since dropped) and the rate matcher as four more icons will overflow at narrow widths. **Decided (D1):** one
"Line actions" toggle button that opens a popover holding Duplicate / Reverse (and later Rate Matcher; Balance was planned here, dropped by D8). It
uses `popover_react_util.TogglePopoverButton` (POP:62-139, exported, params `gameCtx`, `icon`, `tooltip`, `recipe`,
`params`, `windowClass`), so it gets the vanilla toggle look without stylesheet rules. Inside, text buttons from
`button_react_util.makeTextButton`. It is an `lmp_rows` injector (order ≥ 0, right of A+).

Stylesheet budget: the repo sits near the ~200-rule load-crash limit (docs/findings.md). The target is **≤ 3 new
rules** for all five features. Plain string tooltips and vanilla button builders need none.

---

## 1. Send to Line list: hover info

**Verdict: yes. Implemented in phase 4 (2026-10-10), not yet seen in game.** Differences from the design below:
- Hovered line: the panel's own `react.useState` polled by `react.onStep` (one `:old()` read and compare per step),
  not `useStepState` (which deep-compares); same thread (Main Thread).
- Panel text: the line's name (game-supplied) as the first line, then `stats.lines(line, selection)`; the estimate
  needs only `send_to_line_estimate` On (not `send_to_line_info`: the panel doesn't extend the map tooltip).
- CSS: one new rule `R::SquareLmpStlPanel TextView!sq-lmp-stl-panel` (same colour as `sq-lmp-stli`, margin 8/8/8/0,
  gravity top-left). Repo stylesheet total for this mod: 7 rules (5 undo + 2 info blocks).
- `install()` shims the shared replacement api like line_dot.lua (a later `ReplaceRecipe` of our wrapper gets the
  wrapped recipe). Placement off-screen near the right edge is not handled (TESTING.md checks it).
- No placeholder text when nothing is hovered (no panel), so no new UI strings.

What vanilla does: the Send to Line button opens `POP.PopoverWindow` with `recipe = SendToLineSelection` (MW:7346-7366
from the vehicle manager; MW:7903-7925 from the line window with `openWithVehicleEntities`).
`SendToLineSelection` (MW:4513-4690) is file-local. Each row is a `builtin.Button{ meta = { class = "line-button",
onMouseOver = ... } }` that only sets `commonParams.sendToLineHoveredLineState` (MW:4626-4636). That state is created
at MW:5917 and passed at MW:6334. There is no tooltip.

**Hook:** `PopoverWindow` renders `popover_react_util.PopoverWindowContent{ recipe = params.recipe, params = ... }`
(POP:41-46), looked up on the module table each render. `PopoverWindowContent` renders `params.recipe(params.params)`
(POP:25-28). We wrap that **module field** with a plain function, the chain-safe way UI Overhaul does it
(`.cache/subscribed/ui_overhaul_1/content/ui_overhaul/gui/terminals.lua:16-20, 1508-1529`). We don't use
`ReplaceRecipe`: that has one slot per recipe (REACT:446-455), and Auto Assign Terminals already uses it on this
recipe (`aat_eow.script.lua:403-441, 704`). Our function:

1. Detects the Send to Line popover: `react.GetRecipeName(p.recipe) == "SendToLineSelection"` (REACT:441-443,
   exported at :743) **and** `p.params.commonParams.sendToLineHoveredLineState` exists **and** `p.params.selection`
   is a table. Otherwise it passes `p` through untouched.
2. Copies `p` and sets `recipe = SquareLmpStlList`, `params = { inner = p.recipe, innerParams = p.params }`, then
   calls the previous function. Only the inner recipe is swapped, so the popover's own hooks (focus, "pressed outside"
   closing at POP:17-23) and other mods' wrappers keep working. Clicks on our panel count as inside the popover. AAT
   does the same swap for the terminal popover (`AatTerminalPopover`, aat_eow.script.lua:416-440).
3. `SquareLmpStlList` returns `BoxLayout{ inner(innerParams), SquareLmpStlPanel{ commonParams, selection } }`. The
   root is a BoxLayout and the recipe is the item itself, never `Component{layout=Recipe{}}`.
4. `SquareLmpStlPanel` reads the hovered line with
   `engine_react_util.useStepState(function() return commonParams.sendToLineHoveredLineState:old() end)`. Our panel is
   not a child of the manager, so it polls instead of re-rendering with it. This runs on the GUI thread (onStep) and
   costs one table read per step. It renders `stli_core.lines(line)` (1 s cache) plus feature 2's estimate lines,
   using the same tooltip classes as the map block. With no row hovered it renders an empty BoxLayout.

**UI placement:** a panel to the **right** of the list inside the same popover. The popover's height is capped
(`line_vehicle_mgmt.css.lua:962-967`, `lvmPopoverMaxHeight`) but its width is not, and it is anchored top-left
(MW:7344-7345, `initialX/Y`), so the list doesn't move. **Decided (D2): right of the list.** The panel reuses the
approved dark info-block look of `lmp.css.lua`.

**Data:** `stli_core` as is. `selection` comes from `params.selection` (MW:4506, the vehicles being sent).

**Risks / fallback:** the whole swap runs in pcall and falls back to the untouched `p`. If `SendToLineSelection` is
renamed, the check is false and vanilla shows. The panel recipe uses pcall per block, as stli.lua does.
To check in game: whether `:old()` of a foreign state is current one step after the set, and the popover width.
CSS: reuse `TOOLTIP_CLASS`. The existing `sq-lmp-stli` rule is scoped to `R::SquareLmpSendToLineInfo`, so either
render the panel's text through a small recipe of that same name (0 new rules) or add one rule
`R::SquareLmpStlPanel TextView!sq-lmp-stli`.

**Strings:** none new (feature 2 brings its own); optional placeholder "Hover a line to see its details."; the param
name/tooltip (`send_to_line_list_info`, added in this feature's phase).

**Tests:** `test_stl_list.lua`. Detection with fake `react.GetRecipeName` (match, wrong recipe, missing state, nil
params); the swap keeps every other field of `p`; the previous wrapper is called exactly once; an error inside →
untouched `p`; the panel's text for hovered nil / a line / a deleted line.

## 2. Before → after estimate (map tooltip and list panel)

**Verdict: yes, as an estimate.** Every after-value is prefixed `~` and labelled as an estimate in the param tooltip.

**Implemented in phase 3 (2026-10-10), not yet seen in game.** Differences from the design below:
- Own setting, but it **needs** `send_to_line_info` On (it extends that tooltip; installed right after it, logs a line
  and stays off otherwise). The param tooltip says so.
- **Utilization: no estimate.** The footer's coverage is the cargo aboard right now / capacity (cargo_util.tl:707-722),
  a snapshot of loads, not the waiting supply, so "utilization × cap / cap after" would only say "the new vehicles
  start empty". The current value stays without an arrow.
- Capacity: per selected vehicle the load-config `config.capacities` for the line's cargo set
  (`getLineCapacityUsages(line, false)`, the footer's source); if 0, the best `allCaps` entry among those cargos
  (reconfigurable trucks); unknown set (no capacity yet) → the whole load config. A vehicle that can carry none of the
  line's cargo adds 0 and is counted in one extra line "Selected vehicles that can't carry this line's cargo: {count}".
- n = 0: Capacity `0 → ~add`; Frequency and Rate keep the plain current value (no round-trip time to scale).
  Rate also has no arrow with capacity 0 or add = 0. Values that round to the same number get no arrow.
- Layout: with any arrow the stats row splits into "Capacity · Utilization" / "Frequency · Rate"; otherwise one row.
- Cache: the line's stats per line for 1 s as before; inside that entry the text per selection key (≤ 8 kept).
  `config.capacities` is read directly (no `calculateCargoColumnDataForVehicle` per vehicle), so no sampling.

**How vanilla gets the numbers:**
- Frequency: `LU:1350-1354` `calculateFrequencySeconds = floor(1 / api.engine.util.line.getMaxFrequency(line))`. The
  native `getMaxFrequency` is documented only as "Get line max frequency" (`engine/util.d.tl:203-206`).
- Rate: `calcLineStationThroughput`. Verified **linear in the number of identical vehicles**, computed rather than
  measured (docs/findings.md "Line Rate, cloning onto a line": 1/2/3 ships → 51/103/154).
- Capacity: `statistics_react_util.calculateCargoColumnDataForLine(line).demand`, the sum of `capacity` over the
  line's cargo types (`statistics/statistics_react_util.tl:194-259`).

**Formulas (pure, in `stli_core.estimate`):** n = vehicles on the line, k = selected vehicles **not already on that
line** (`TRANSPORT_VEHICLE.line ~= target`).
- Capacity after = capacity + Σ over the k vehicles of `statistics_react_util.calculateCargoColumnDataForVehicle(v).demand`
  (vanilla's per-vehicle capacity column, statistics_react_util.tl:227). Better still: count only the cargo types the
  line carries (`TransportVehicle.config.capacities[cargo+1]`, ENG:1418, indexed cargo id + 1 per findings) when the
  line's cargo set is known. Implementer's choice; test both against the footer after a real send.
- Frequency after (an interval in seconds) ≈ interval × n / (n + k). This holds for vehicles of similar speed. With
  n = 0 there is no "before": show "Frequency: ~{after}" only if the native value updates (otherwise omit).
- Rate after ≈ rate × (capacity + Σcap_k) / capacity (throughput ∝ capacity × trips). For identical vehicles this is
  the verified linear rule rate × (n+k)/n.
- Utilization after ≈ utilization × capacity / capacity after (the same waiting supply over more capacity).

**Display:** "Frequency: 7:19 → ~4:53" through one format string `_("{label}: {before} → ~{after}")`. Lato has `→`
(docs/findings.md, GUI font glyphs). A stat that doesn't change (k = 0) keeps the plain form.

**Where the selection comes from:**
- Map tooltip: `VMSendToLine` params are only `{ numVehicles, lineOrDepotEntity }` (MW:1241-1247). Selected vehicles
  come from the captured `commonParams` (`lmp_capture.selectedVehicles()`), the same source the mode uses (MW:1180).
  Check: if the count ≠ `params.numVehicles`, drop the after-values (don't guess).
- List panel: `params.selection` (MW:4506).

**Cache:** `stli_core` caches per line for 1 s. The estimate depends on the selection too, so cache per selection
size and entity list hash, or compute the cheap part (k capacities) uncached. Each `calculateCargoColumnDataForVehicle`
is one call per selected vehicle; above 50 selected, sample or sum `config.capacities` directly.

**Risks:** the estimate can be off for mixed speeds or models, full-load stops, or a line limited by station
capacity. That's why the `~` and the tooltip wording.

**Strings:** `"{label}: {before} → ~{after}"`; param name/tooltip ("Send to Line: before/after estimate").

**Tests:** `test_stli_estimate.lua`: n = 0, k = 0, vehicles already on the line, capacity 0 (no division), rounding,
the format-string order in a fake language (placeholder order).

## 3. Line stats tooltip on the colour dot (line list)

**Verdict: yes. Implemented in phase 2 (2026-10-10), not yet seen in game.** Differences from the design below:
- The LINE check moved from the wrapper to the hover: the wrapper only checks caller, one table argument, `onClick`
  and a numeric entity (no engine call per row render); a non-line entity simply gets no stats when hovered. Depot
  rows don't call ColorWidget at all (manager_window.tl:2130-2154 is inside `if isLine`).
- New safety found in research: our field holds a plain function, so a later mod's `ReplaceRecipe` of
  `line_react_util.ColorWidget` would index react's registry with nil (react.lua:441-455) and break that mod's config.
  `install()` wraps the shared replacement api (bootstrap_game.tl:39-48 hands one table to every config) to pass such
  calls the recipe we wrapped. No known mod replaces it (subscribed, release, our mods searched).
- No refresh while hovered (`useStepStateTimer` left out: a tooltip whose text changes while shown may flicker); the
  next hover after 1 s shows fresh numbers.
- Stylesheet: 0 rules. A `meta.tooltip` string is drawn in the engine's tooltip window, not under our recipe, so the
  dark info-block look can't be scoped to it; vanilla tooltip look.

The dot is `line_react_util.ColorWidget{ tooltip = _("Open Line Window"), entity = entity, onClick = ... }` at
MW:2154-2164, inside `LineAndDepotListEntry` (MW:1957, file-local, the line list row). `ColorWidget` is exported
(LRU:271-306, `line_react_util.d.tl:51-57`). Its `param.tooltip` ends up as `meta.tooltip` on both the dot and its
Button (LRU:292-303).

**Hook:** wrap the **module field** `line_react_util.ColorWidget` with a plain function, not `ReplaceRecipe` (single
slot; also used by town windows, UI Overhaul cards, the vehicle row icon at LRU:157). In the wrapper, the caller's recipe
is known: `react.getCurrentRecipeName() == "LineAndDepotListEntry"` and `param.onClick ~= nil` and the entity has a
LINE component. Only then do we return `SquareLmpLineDot{ orig = previous, param = param }`. Anything else goes
straight to `previous(param)`.

`SquareLmpLineDot` (root BoxLayout): a hover flag via `react.onMouseEvent` Entered/Exited (as `LineAndDepotListEntry`
does at MW:1978-1993, returning false so events pass on). While hovered it calls `previous(copy)` with
`copy.tooltip = <vanilla tooltip> .. "\n" .. stli lines`. Otherwise the param goes through unchanged. This way the
stats are built only for the hovered dot, never for hundreds of rows at render (1 s cache; refresh while hovered with
`useStepStateTimer`).

**Tooltip mechanism:** `meta.tooltip` is a string (`base/tealdef/scripts/builtin.d.tl:637`). Base builds multi-line
tooltips with `"\n"` (`gui/main/cargo_react_util.tl:147`, `menu/mod_selector_page.tl:409`), so no recipe tooltip is
needed. `builtin.ActionTooltip` exists only for the map HUD (LU:1247).

**Content:** `stli_core.lines(line)` (vehicles by model, the stats row), without the "Send N vehicles" line, below the
vanilla "Open Line Window".

**Risks:** to check in game whether a tooltip text that changes after the mouse enters is picked up (the tooltip delay
should hide that). If not, fall back to building the text at render for this one row (the 1 s cache bounds the cost;
measure with SQPERF section `dot_tooltip`). Long tooltips: cap at 5 model rows, as stli_core does. CSS: 0 rules.

**Strings:** none beyond stli's; the param name/tooltip ("Line list: stats on the colour dot").

**Tests:** `test_line_dot.lua`: the wrapper passes through for another caller, for no onClick, for a depot, and on
error. For the list dot: hovered → tooltip has the vanilla line + stats; not hovered → vanilla param unchanged (same table).

## 4. Duplicate line and Reverse line

**Verdict: yes. Implemented in phase 5 (2026-10-10), not yet seen in game.** Differences from the design below:
- Param `line_actions` ("Line editor: Line actions button"), not `line_copy_reverse`: it controls the Line actions
  button with both entries. Later entries (Rate Matcher) register with `lmp_actions.register` and bring their
  own params.
- Button: not `TogglePopoverButton` (its ToggleButton has no class, so it wouldn't look like A+, and it gives the
  recipe no way to close the popover). A copy of the A+ button instead (manager_window.tl:3518-3572): ToggleButton with
  A+'s classes, popover at A+'s anchor with A+'s window classes, our own window key. Icon `symbol_burger_menu.tga`.
  Menu items: `makeIconTextButton("secondary", ...)` with the vanilla Duplicate / Reverse icons; 1 stylesheet rule.
- Selecting the copy: `commonParams.selectLine({ entity }, true, nil)` (deselect all, select, scroll), not the list
  api's `selectLine` (which only selects lines in the stale unselected list).
- No `getDetailedLineProblems` check after the reverse (path computed later; a message from the callback could be
  wrong). The vanilla line problem shows instead, and Undo takes it back.
- Unchanged reverse (2 stops, no waypoints, same terminals): a message, no command. A new terminal that was one of the
  stop's alternatives swaps with the old main terminal. Vehicles are not re-sent.
- Guards: protected lines and several selected lines hide the button (as undo); < 2 stops, a gone station and a command
  in flight (10 s timeout) disable the entries with the reason as tooltip.

**Commands** (CMD:255-283, 760-778):
- `api.cmd.makeLineCreateCmd(name, color, player, lineComp)`. The result entity is `resultEntities[1][1]` in the
  callback, as the vanilla editor's commit at MW:6526-6553 does (also `mission/tasks/vehicle_util/mission_vehicle_util.tl:7-24`).
- `api.cmd.makeLineUpdateCmd(lineEntity, lineComp)` (MW:6555-6561; `cargofilter_window.tl:440`).
- `api.type.Line.new(Line)` is a copy constructor (ENG:493-494). undo_core already builds Line components from
  snapshots, and its builder can be reused.

**Duplicate:** copies `stops` (station, terminal, alternativeTerminals, loadMode, waiting times, stopConfig,
waypoints), `customFilters` and `reservationPriority`.
- Name: `lang_util.format(_("{name} (copy)"), {name})`, made unique against `lineSystem.getLinesForPlayer(player)` with
  `_("{name} (copy {n})")`. This is how the editor names a new line (`LU:66-80` `makeLineName`, which also stores a
  translated name).
- Colour: `line_util.makeLineColor(player)` (LU:40-64, the editor's choice for new lines). **Decided (D3).**
- Vehicles: **left alone**. The copy starts empty, and the player sends vehicles with Send to Line or vanilla Buy
  Vehicles.
- After success: `lineAndDepotListApi.selectLine(newLine, true, ...)` and `scrollToRow` (`manager_window.d.tl:27-35`),
  so the editor switches to the copy.

**Reverse (in place):** `makeLineUpdateCmd` on the edited line with the stop order reversed. The first stop stays first
(`[s1, sn, ..., s2]`), so a line's start and the "first stop to send" schemes don't move. **Decided (D4).**
- Waypoints belong to the segment **after** their stop (ENG:542 "all waypoints after the stop"). Segment i→i+1 becomes
  i+1→i, so each stop's waypoint list moves to the next stop in the new order, reversed in place. `Waypoint` has only
  `edgePos`, `pos` and `tag`, no direction (`type.d.tl:1179-1191, 1243-1256`). Mirroring is well defined, but one-way
  roads or signal-only paths may then have no path.
- Terminals: re-pick them for the new direction with `lineSystem.getBestLineAssignment(line, comp, true)` (SYS:48-52,
  used by `LU:128-245` autoAssignTerminals for stops without a terminal). Road stops on the far side of the street
  need this. **Decided (D5).** Where it has no answer for a stop, keep the player's terminal.
- After the update: `api.engine.util.line.getDetailedLineProblems(line)` (`engine/util.d.tl:207-210`). With
  `noPath`, a feedback message suggests Undo. Our Undo records the reverse as one edit (it polls the LINE component)
  and can take it back. Note: the history tooltip says "line changed".
- Vehicles: left on the line. What a vehicle does with its `stopIndex` after the reorder is engine behaviour. To
  check in game. Option: re-send each with `makeVehicleSetLineCmd(v, line, mappedIndex)` (CMD:916-922) so it keeps
  heading to the same station.

**Guards** (as undo does): disabled for several selected lines, a protected line (`isStopProtected`, undo.lua
`isProtected`), a line with < 2 stops, or while a command is pending. Destroyed stations → message, no command.

**Save impact:** the new or changed line is vanilla data. It persists without the mod and the player can delete it
with Delete Line. No mod resource is referenced, so it's safe to remove the mod.

**UI:** text buttons in the "Line actions" popover (D1). The texts must say "line" (the vehicle toolbar has Clone
vehicle and Reverse vehicle).

**Strings:** "Line actions", "Duplicate line", "Reverse line", "{name} (copy)", "{name} (copy {n})",
"Line Manager Plus: the game refused the new line.", "Line Manager Plus: the reversed line has no path. Undo takes
it back.", disabled-state tooltips ("Select a single line", "The line needs at least 2 stops"), param name/tooltip.

**Tests:** `test_line_ops_core.lua` (pure): reverse with 2/3/n stops; waypoint migration (first and last segment,
empty lists); each stop's settings stay with their stop; duplicate copies everything; unique name with existing
copies; s1 stays first; terminal re-pick with and without an answer. `test_line_ops.lua` with a fake api: the right command per action, callback success and
failure, the guards.

## 5. Balance vehicles (spread out bunched vehicles)

**Verdict: dropped (D8, 2026-10-11).** The probe ([PROBE_RESULTS.md](PROBE_RESULTS.md)) showed `makeVehicleSetLineCmd`
on a vehicle already on its line is accepted but buses ignore the stop index (they drive on in line order), so a
re-send can't respace road vehicles, and the engine already spaces departures at line frequency. Not built in any
form. The design below is kept as a record. Original verdict (2026-10-10): **partly.** TF3 has **no timetable or departure-interval API**. The Line Stop record holds only
`minWaitingTime`, `maxWaitingTime`, `maxAdditionalWaitingTime` and `loadMode` (ENG:518-545). There's no command that
moves a vehicle along its route. What exists:

| Tool | Source | Use |
|---|---|---|
| `makeVehicleSetLineCmd(v, line, stopIndex)` | CMD:916-922, 468-476 | send a vehicle (also one already on the line?) to a stop index; it drives there and skips stops |
| `makeVehicleSetManualDepartureCmd(v, manual)` | CMD:923-930, 478-484 | "will not depart from the terminal under any circumstance": hold a vehicle |
| `makeVehicleTryToDepartCmd(v)` | CMD:943-950 | make a waiting vehicle leave at once |
| `TransportVehicle` fields | ENG:1459-1530 | `stopIndex`, `lineStopDepartures` (last departure per stop), `sectionTimes`, `state`, `loadState`, `timeUntilDeparture`, `autoDeparture` |
| vanilla "Evenly Distributed" send scheme | `first_stop_to_send/scheme_evenlydistributed.script.tl` | spreads **start stops** by stop index (not by time) when vehicles are sent |
| `LoadState.WaitForScheduledDeparture` → "Ensuring safe distance" | ENG:1431, 1494; `entity_window/entity_window_util.tl:2283-2284` | the engine already holds some vehicles for spacing; when and how is unknown |

**Option A, "Respace now" (one click, only vanilla state):** compute each vehicle's progress around the loop in
seconds:
- cumulative `sectionTimes` up to its last stop, plus (game time − `lineStopDepartures[last]`)
- game time from the `GAME_TIME` component, ENG:425-431
- target headway H = round-trip / n

Walk the vehicles in order. Re-send a vehicle sitting < 0.5 H behind the one ahead with `makeVehicleSetLineCmd` to
the stop whose arrival time best fills the largest gap. Nothing persists: after the commands the vehicles run as
vanilla. Unknowns:
- what happens to the cargo or passengers aboard
- whether a re-send to the same line works or is refused
- the route taken (it may turn around)
- whether bunching comes back quickly (it will, without a lasting controller)

**Option B, "Hold at terminal"** (`makeVehicleSetManualDepartureCmd` + `makeVehicleTryToDepartCmd` in a running
loop) is **rejected (D6)**: the manual-departure flag is vehicle state in the save, so a vehicle held when the game is
saved and the mod removed (or the GUI loop stops) would never leave, and vanilla has no button to clear it.

**Plan:** a DEV probe first (`mods/square_lmp_probe`, never uploaded; the user runs it), then Option A as
"Balance vehicles" if the probe shows that re-sending is clean. The param `line_balance` defaults Off.
Probe questions:
1. `makeVehicleSetLineCmd` on a vehicle already on that line: accepted? cargo kept or dropped? route?
2. What triggers `WaitForScheduledDeparture`, and what does `timeUntilNextScheduledDeparture` count down (the
   engine's own spacing)? Read only.
3. Are `sectionTimes`, `lineStopDepartures` and game time consistent enough to rank vehicles by progress?

**UI:** "Balance vehicles" in the Line actions popover, enabled with ≥ 2 vehicles. Result in the manager feedback list:
"Line Manager Plus: respaced {n} of {total} vehicles." / "Line Manager Plus: vehicles are already evenly spaced."

**Strings:** the button text and tooltip, the two results, refusal/failure messages, param name/tooltip (it must say
that it re-routes vehicles now and doesn't keep them spaced).

**Tests:** `test_balance_core.lua` (pure planner): progress from fake components; H; who gets re-sent and to which
stop; already-even → nothing; 2 vehicles; vehicles in depot or going to depot left out; a single stop line.

---

## Phases (one subagent each; each ends with `make check`, `make test`, `make validate`, `make i18n ARGS='--check --lint-modinfo'` for `MOD=mods/square_line_manager_plus`, and a TESTING.md section)

Each phase that implements a feature also adds its param to `mod.json` (name and tooltip in all 13 languages) and
its `FEATURES` row in `lmp.script.lua`.

1. **Groundwork: DONE (2026-10-10).** `lmp_capture.lua`, `lmp_rows.lua` (line toolbar only), undo moved onto them
   (no behaviour change; the undo tests pass unchanged), `test_groundwork.lua`, README "Install path" updated. No new
   params or strings (each feature adds its own). In game: TESTING.md "Phase 1".
2. **Feature 3: DONE (2026-10-10)** (colour dot tooltip, `line_dot_tooltip`): `line_dot.lua` as designed below, plus
   `lmp_stats.lua` (the stli_core model now shared with `stli.lua`, one 1 s cache), `test_line_dot.lua`, param and
   strings in 13 languages (the `sqperf_log` tooltip now says "its additions to the Line Manager", so later phases
   don't change it again). In game: TESTING.md "Phase 2".
3. **Feature 2: DONE (2026-10-10)** (estimate in the map tooltip, `send_to_line_estimate`): `stli_core.estimate` /
   `vehicleCapacity` + `formatLines(info, fmt, after)`, model `lines(line, vehicles)`, `stli.lua` reads the selection
   from `lmp_capture.selectedVehicles()` (through `stli_estimate.lua`), `test_stli_estimate.lua`, param and 2 strings
   in 13 languages. Decisions in "2." below ("Implemented"). In game: TESTING.md "Phase 3".
4. **Feature 1: DONE (2026-10-10)** (list panel, `send_to_line_list_info`): `stl_list.lua` (wraps
   `PopoverWindowContent`, recipes `SquareLmpStlList` / `SquareLmpStlPanel`), reusing 2's estimate through
   `params.selection` (respects `send_to_line_estimate`; `install(replacementApi, params)` now gets the mod's params),
   1 new stylesheet rule, `test_stl_list.lua`, param in 13 languages. Decisions in "1." below ("Implemented"). In game:
   TESTING.md "Phase 4".
5. **Feature 4: DONE (2026-10-10)** (Duplicate / Reverse, `line_actions`) + the "Line actions" popover button (D1),
   an `lmp_rows` injector: `lmp_actions.lua` (button, menu, entry registry), `line_ops.lua` + `line_ops_core.lua`,
   `lmp_capture.resetEditorMode` (now shared with undo), 1 new stylesheet rule, `test_line_ops_core.lua`,
   `test_line_ops.lua`, param and 15 strings in 13 languages. Decisions in "4." above ("Implemented"). In game:
   TESTING.md "Phase 5".
6. **Balance probe: run 1 analysed (2026-10-11), results in [PROBE_RESULTS.md](PROBE_RESULTS.md)** (facts in
   docs/findings.md "Re-sending a vehicle to its own line"). Re-send is accepted and keeps cargo, but **buses ignore
   the stop index** (they drive on to their next stop in order; a 2-stop ship did turn around), the command wipes the
   vehicle's departures/section times, and the engine already spaces departures at line frequency. Recommendation:
   don't build Option A as designed (read-only gap/H display instead, or a restricted design after a run 2; checks
   listed there). Built (2026-10-10): DEV mod `mods/square_lmp_probe` (never uploaded,
   exempt from translation): an LMPP row left of A+ with Snap (read-only 60 s spacing sampler, Q2/Q3) and
   Send:plan / Send:back / Send:same (one `makeVehicleSetLineCmd` on the most bunched vehicle, tracked 60 s, Q1).
   Steps and what each answer decides: PROBE.md. The user runs it and pastes the `[LMPProbe]` log; results go to
   docs/findings.md.
7. **Feature 5: DROPPED (2026-10-11, D8).** The user dropped Balance entirely after
   [PROBE_RESULTS.md](PROBE_RESULTS.md): a re-send can't respace road vehicles (buses ignore the stop index) and the
   engine already spaces departures at line frequency. No Balance button, no read-only spacing indicator, no
   `line_balance` param or strings (none were ever added to the mod). The DEV probe `mods/square_lmp_probe` stays as
   is (never uploaded); it can be unlinked (`make unlink`/remove its staging symlink) and deleted later.

**In game (2026-10-11):** the user tested phases 1-5 and reports "user: looks good" (no detailed checklist results;
TESTING.md).
Fix the same day: the stack traceback printed on every reopen of the Line Manager came from `:old()` on the closed
window's expired `lineState`; `lmp_capture.editedLine` and the Send to Line list's hover read now check
`hasExpired()` first (docs/findings.md "Expired react states", TESTING.md "Expired line state").

After phase 5 (or each phase, at the user's choice), the user runs one combined in-game pass (TESTING.md). Then:
revision bump (if rev 1 is already on mod.io), a Changelog entry in `_metadata/description.html`, the description's
feature list, the cover tagline if needed, and `make sqperf-sync` (new SQPERF sections: `stl_list`, `dot_tooltip`,
`line_ops`).

## Decisions

All decided 2026-10-10, see "User decisions" at the top: D1 one popover button; D2 right of the list; D3 new colour;
D4 in place, stop 1 first; D5 re-pick terminals; D6 Option A only after a probe (superseded); D7 moot (Buy button
dropped); D8 Balance dropped after the probe (2026-10-11).

## Rules that apply to every phase

- Wrap, never rewrite: read the previous function in `install()`, call it, and pcall our part with a fallback to the
  vanilla result. One log line per failure kind (`[LineManagerPlus] <feature>: ...`).
- Every custom recipe returns `builtin.BoxLayout` at its root. Never `Component{layout = Recipe{}}`; recipes are items.
  No `mouseTransparent` on ImageView.
- GUI-thread-only calls (`api.gui.*`, `getApplicationTime`) only in render/onStep. Use `api.type.Clock` for timing.
- Pre-5.3 Lua (`make check` lints). `.script.lua` exports via `data()`. Module-level locals stay under 200.
- Commands are sent from click handlers (GUI thread). Callbacks only check success and show feedback.
- Stylesheet rules: ≤ 3 new in total, all scoped under our recipe names. Count them before and after.
- Every displayed string goes through `_()` into `strings.json` for all 13 languages in the same phase. One format
  string per sentence, `{name}` placeholders.
