# Line Rate Matcher (`square_line_rate_matcher`): plan

Adds a button to the Line Manager that matches a cargo line's **Rate** to the supply it serves.
For example, a logging camp makes 101/yr and the line's Rate is 66 with 2 ships: the mod suggests adding 2 ships
(≈132), or another model and count that comes closer. Asked for on 2026-10-10.

## Decisions (user, 2026-10-10)

- **Flow:** the button opens a popup with the numbers and a suggestion. The target box can be edited, and nothing
  is bought or sold before **Apply**.
- **v1 actions:** add clones, remove surplus (send to depot and sell on arrival), suggest other models
  (applied through the game's own Replace Vehicles window).
- **Placement:** in the line details toolbar next to A+, using the wrapper trick from Line Revert.

## Research summary (2026-10-10, docs only, nothing checked in game yet)

| Need | Source |
|---|---|
| Inject the button | Wrap `button_react_util.makeIconToggleButton` in a `react-replacement-config` doReplace. Match the A+ icon `symbol_autorename.tga` and return a BoxLayout `[ours, orig]`. Reach the line through a wrapped `line_util.makeLineActionDescriptor` (`commonParams.lineState`). Precedent: `mods/square_line_revert/content/line_revert/line_revert.script.lua:442-453`, `plans/square_line_revert/PLAN.md`. The wrappers chain, so it can coexist with Line Revert: use a different `order` and read the current function inside doReplace. |
| Rate | `api.engine.util.line.calcLineStationThroughput(line)`, per year (tooltip at MW:3997). Native code, so the formula is unknown. Capacity, Utilization and Frequency as in `stli_core.lua`. |
| Supply (target) | Copy `production_label_pickup.tl` `engineAdapter` (`lineStops`, `reachableStockLists`, `outputCargoTypes`, `terminalCargoLoad`) and the "rate of other lines per stock list" sum. Production: `industry_util.getIndustryProductionData`, falling back to `STOCK_LIST.cargoData[c].produceFrequency` for raw producers. Max: `api.engine.util.stock.getCargoMaxProductionPerYear`. |
| Clone onto this line | Rebuild the vanilla `duplicateVehicles` path ourselves, so the clone lands on **this** line (vanilla calls `findBestLineAndDepotForVehicle`). Copy the `TRANSPORT_VEHICLE.transportVehicleConfig` and reset `purchaseTime=0` and `maintenanceState=1`. Then `makeVehicleBuyCmd(player, depot, config)` and, in the callback, `makeVehicleSetLineCmd(cmd.resultVehicleEntity, line, stop)`. For the depot, use the one from `findBestLineAndDepotForVehicle`, or the depot of a vehicle on the line. Fire `mission.buyVehicle` like vanilla does (MW:8494-8570, `vehicle_react_util.tl:318-405`). |
| Remove surplus | `makeVehicleSendToDepotCmd(v, true)` (sell on arrival). Skip `protectedEntities` (mission vehicles). Prefer empty or newest vehicles? Decide in phase 1. |
| Other models | Per-model capacity for a cargo: `vehicle_store_util.getVehicleCargoCapacities` pattern on `modelRep.get(id).metadata.transportVehicle`. Apply with `react.fireEvent(nil, "replaceVehicles", ...)` (verified in game, `docs/findings.md`). |

## Suggestion maths

- `perVehicle = Rate / n` (n = vehicles on the line). `need = ceil(target / perVehicle)`, `delta = need - n`.
  This assumes Rate grows linearly with the vehicle count. **Probe it.**
- Target default = current production of the reachable producers of the cargo the line loads, minus the Rate of
  other lines that load the same cargo at those producers, never below 0. The popup shows "max" next to it
  (secondary industries).
- Other model m: estimate `perVehicle_m = perVehicle * cap_m/cap_cur * speed_m/speed_cur`, labelled "≈".
  List the 3-5 models of the same carrier/transport mode, available in the current year, that carry the cargo and
  come closest to the target. After Apply, the popup re-reads the real Rate.
- No suggestion for passenger lines (passenger cargo id). A typed target still works.
- Lines that load several cargo types: one target per cargo, and the suggestion uses the cargo that needs the
  most vehicles (shown with its reason).

## Phases (one subagent each)

0. **Probe (DEV mod, never uploaded):**
   - Does Rate change linearly when vehicles are added or removed?
   - Do vehicles in a depot or on their way count?
   - When does a new clone show up in Rate?
   - Is the button next to A+ visible, and does it work alongside Line Revert?
   - Does makeVehicleBuyCmd + SetLine put the clone on the selected line?
   Record the answers in `docs/findings.md`.
1. **Pure model + tests** (`tests/square_line_rate_matcher/`): target from supply, delta, model ranking, surplus pick.
2. **Engine adapter:** line reading, supply walk (copied from Production Label), model catalogue. Read only, pcall
   everywhere.
3. **GUI:** toolbar button, popup (numbers, target box, suggestion rows, Apply/Cancel), commands, feedback text.
   BoxLayout root, FlowLayout for the button rows.
4. **Release prep:** translations (13 languages), cover entry in `branding/mods.js`, `description.html` with
   Changelog, `make validate`/`check`/`test`/`i18n --check --lint-modinfo`.

## Save safety

GUI-only. No game script and nothing stored in the savegame. It only sends the vanilla buy, set-line,
send-to-depot and replace commands that the player could send by hand.

## Probe results (2026-10-10, `docs/findings.md` "Line Rate, cloning onto a line, sell on arrival")

- Rate is exactly linear in identical vehicles (51/103/154), updates within 1 s even paused: re-read Rate after Apply.
- Buy + SetLine lands on the selected line; send-to-depot-and-sell leaves the line (and Rate) at once.
- Target = max production (`getCargoMaxProductionPerYear`, 101 for the logging camp); measured produced/yr (98-112)
  is noisy, show it as a hint only. Other-lines sum must filter by the cargo each line loads at that group.
- Rounding: WC Logs is 33/ship vs target 101, so 3 ships ≈ 99 and 4 ships ≈ 132. Show both neighbours. Preselect the
  count closest to the target. Mixed-model lines: perVehicle per model from its capacity share.

## Phase 3: GUI (2026-10-10, run in game: window and buying work; feedback in phase 3b)

- `rate_matcher.script.lua` (doReplace, order 260; the two Line Revert wrappers) mounts
  `rate_matcher_window.tl` `ToolbarButton` left of A+ and hands the manager context (line when exactly one is
  selected, protected entities, mission vehicle filter) to the window module. mod.json marks the DEV probe as
  incompatible (both would mount a button).
- `rate_matcher_window.tl`: icon ToggleButton (base `stat_load_speed` icon, A+'s class, checked while the window
  shows the line) and one singleton window (Current, Supply, Target box, Options, Other models, result message,
  Apply / Close). Engine reads and commands on the GUI main thread only (click, useStepState); command callbacks
  write into the session table. Re-read 1 s and 3 s after Apply or the Replace window; Rate + vehicles every 2 s.
- `rate_matcher_view.tl`: pure view model + every displayed text (`_()` keys, `{name}` placeholders).
- Styles inline; one CSS rule (`rate_matcher.css.lua`: window background and placement).
- Tests: `test_view.lua` (view model, texts), `test_gui.lua` (mount + window with fake react/builtin/engine).
- In-game checklist: `TESTING.md`.

## Phase 3b: feedback from the first GUI test (2026-10-10, written, not yet run in game)

In-game checklist: `TESTING.md` (rewritten for 3b). Still 1 stylesheet rule.

1. **Tidier window:** title = line name (the title size is the base `Window::Title` style, not ours); one summary
   line ("Rate 66/yr · 2 vehicles · 33 each · running $X/yr"); supply on one line per cargo; the redundant hints
   ("Suggested target", "Replace with one of them ...") dropped. Table rows use fixed-width columns (inline-size
   Components, numbers right-aligned by the base `horizontal-spacer`), so no new CSS rule.
2. **Vehicle list refresh:** the Line Manager's vehicle list is the vehicle manager's `vehicleManagerStateRef`, filled
   when a line is selected (`manager_window.tl:1405-1410`) and never re-read from the line. Vanilla Clone adds its
   clones in the button's `onBuy` (`vehicleManagerApi.addVehiclesToVehicleListAndSelect`, `:5108-5117`); the
   `duplicateVehicles` listener (`:8494-8570`) only buys. We call `commonParams.addOrRemoveVehicleToVehicleList`
   (`:7000-7017`; the commonParams we already capture) for bought / replaced vehicles and to drop sold ones, after
   the callbacks and again at the 1 s / 3 s re-reads, only while the manager shows our line. Firing
   `duplicateVehicles` ourselves would not refresh the list either (that happens in the caller's onBuy, which would
   need the same hook) and would put the clone on `findBestLineAndDepotForVehicle`'s line, which is not guaranteed
   to be ours.
3. **Models as plans with a cost analysis:** a comparison table (fleet model first, then rankModels' top 5), click
   = select; the selected model's below / above counts are the option rows. Another model = a switch of the whole
   fleet like the vanilla Replace window: `makeVehicleReplaceCmd` in place for the overlap (keeps the vehicle and
   its line running, the Replace window's own path, `vehicle_react_util.tl:398-405`), extra vehicles bought onto the
   line, surplus old ones sent to the depot and sold. Costs: Buy = new × store price (`cost.price`) − resale
   (`getDepreciatedValue`, the Replace window's refund, `vehicle_store_window.tl:3525-3541`, `:4267-4278`);
   Running/yr = kept vehicles' `getRunningCost` + new × `maintenance.runningCosts` (the store's "{cost}/year",
   `vehicle_store_window.tl:118-125`); Per rate = Running/yr ÷ Rate. Money check all or nothing (the store's
   `hasEnoughMoney`, `:2992-3003`). Mission vehicles block a switch. The Replace window stays as a button.
4. **Target updates while typing:** `DoubleSpinBox` has only `onValueChange` (`builtin.d.tl:920-931`);
   `TextInputField` has `onTyping` (`:935-957`, used per keystroke by the vehicle store search,
   `vehicle_store_window.tl:2259-2277`). The box is now a digits-only TextInputField (onTyping updates the plans,
   Enter / focus loss commits) with `-` / `+` buttons.

Code: `rate_matcher_model.tl` (planCost, plansFromSuggestion, switchPlans, modelPerVehicle, fleetRunning),
`rate_matcher_view.tl` (build with model rows / plans, compact texts, planCells, planActionText),
`rate_matcher_commands.tl` (switchModel, store prices), `rate_matcher_engine.tl` (vehicle value / running, model
running), `rate_matcher_window.tl`, `rate_matcher.script.lua` (listAdd / listRemove). Tests: 64.

## Phase 3c: second GUI test (2026-10-10, written, not yet run in game)

Feedback: table columns didn't line up (header vs rows, row vs row, selected vs unselected); spacing; "Per rate" was
$2,771 for every model; Buy for one Sydfart showed $548,640 where phase 3 showed $70,484. In-game checklist:
`TESTING.md` (rewritten for 3c). Stylesheet: 3 rules (was 1).

1. **Tables = the game's table.** Both tables are `builtin.DataTable` + `builtin.ColumnDesc` (name, tooltip, weight,
   headerStyleClass), the component of the management window's Lines tab (`gui/statistics/statistic_lines.tl:403-457`)
   and of the Line Manager's line list (`manager_window.tl:2730-2760`). Header and cells share the table's weighted
   columns. Numbers right-aligned like the Lines tab: cells `react.setStyleClasses("right-aligned")` (`:103`),
   headers `headerStyleClass = "right-aligned"`; the base rule doing it is scoped to `#menu.statistics.window`
   (`statistics.css.lua:386-391`), so `rate_matcher.css.lua` repeats its two parts for our window (+2 rules; inline
   StyleSheets have no gravity / textAlignment). First column: a `builtin.CheckBox` (the Line Manager's line rows,
   `manager_window.tl:1873-1891`; there is no radio style), selected row also gets the base
   `Table !table-item!highlight` background (`builtin.css.lua:1439-1441`); a left click anywhere on a row selects it
   (`react.onMouseEvent` Clicked, `credits_react_util.tl:204`). DataTable passes `userParam` only to newly created
   cells (`builtin.d.tl:1170`), so each render uses fresh row keys (cells rebuilt; a handful of rows).
2. **Spacing / type:** one gap scale (6 inside a section, 12 summary to target, 20 before each section heading and
   before the buttons); both section headings ("<model> (current)", "Compare models (estimate)") `font-scale-headline`;
   cells `font-scale-body`; hints / notes dim annotation. Content 680 px.
3. **Why Per rate was constant:** base vehicles have `cost.price = -1` and `maintenance.runningCosts = -1`;
   `model_metadata_util.addCostMetadata` (`base/content/base/model_metadata_util.lua:488-552`, a `loadModel` modifier,
   `base_mod.lua:81`) sets runningCosts = round(c × averageSpeed × maxCapacity / 4) and price = 6 × that (water:
   averageSpeed = 0.65 × topSpeed). Our estimate scaled Rate by capacity × speed too, so running / rate was the same
   for every model (rounding aside). It was computed per row: Trawler 266,700 / 96.25 (unrounded ≈ Rate) = 2,771.
   Lifespans are equal for base ships (36525), so even cost of ownership alone stays constant; the time at stops is
   what really separates them.
4. **New Rate estimate** (`rate_matcher_model.tl` header): round trip = driving (∝ 1 / top speed) + time at stops
   (∝ capacity / metadata `transportVehicle.loadSpeed`). f = share of the current round trip at stops =
   1 − Σ driveSectionTimes / Σ sectionTimes of `transportVehicleSystem.getLineCargoInfo(line, cargo)`
   (`system.d.tl:393-396`, `type.d.tl:4185-4199`). perVehicle_m = perVehicle × (cap_m / cap_cur) /
   ((1 − f) × speed_cur / speed_m + f × (cap_m / load_m) / (cap_cur / load_cur)). Current model exact; f or a load speed
   unknown → the old capacity × speed scaling. LineCargoInfo is not used by the base GUI: units unverified, logged
   (`[RateMatcher] timing`).
5. **Cost of ownership:** Cost/yr = running + capital, capital = each vehicle's store price × yearMs / lifespanMs
   (lifespan × 1000 game ms, `vehicle_util.getLifespan`; yearMs = calendar year at the current speed as Problem
   Radar's `radar_checks.calendarYearMs`). Per rate = Cost/yr ÷ ≈ Rate of that row; the comparison tags the lowest
   "best" (within 0.5 %; none on a tie). Buy now = price − resale (cash needed). Running/yr column dropped (it is in the
   Cost/yr tooltip).
6. **Price:** the store shows metadata `cost.price` (`vehicle_store_util.tl:309`, `vehicle_store_window.tl:117`), =
   6 × 91,440 = $548,640 for a Sydfart; no inflation factor for vehicles (`finances_util.scaleWithInflation` is only
   used by subventions); the difficulty's vehiclePurchaseCostScale is already in it (`post_run_util.tl`). Phase 3's
   $70,484 was `getPartPrice` of the template's own (depreciated) part. Not settled offline: what the buy command
   charges for our clone config (`purchaseTime = now`; vanilla Clone sets 0, `manager_window.tl:8504`). Logged:
   `[RateMatcher] price ...` (every candidate) on open and `[RateMatcher] clone charged: balance A -> B = X` after
   a buy (same for a switch).

Code: model (`loadShare`, `modelPerVehicle`, `capitalPerYear`, `bestByPerRate`, planCost capital / costYear),
engine (`calendarYearMs`, `yearMs`, `lineTiming`, vehicle capital, model loadSpeed / lifespan / capital), commands
(`priceReport`, charged logs), view (`planCells` numbers only, `costTip`, best), window (DataTable tables, gaps),
css (3 rules). Tests: 73.

## Phase 3d: polish after the third GUI test (2026-10-11, written, not yet run in game)

3c in game: alignment good, per-unit costs differ, "best" works; timing `at stops 0.1206`; prices: store cost.price =
getPartPrice(fresh clone part) = 548,640, getPartPrice(owned part) = getDepreciatedValue = 70,484 (so Buy now is right
unless the buy command charges otherwise: `clone charged` still to be logged).

- **No sorting:** the sort caret `DataTable::SortButton::Icon` (builtin.css.lua:1483-1486) hidden by one scoped rule
  (`visibility = "none"`, as entity_window_util.css.lua:145 hides table headers). Every column's getCompareValue = display
  order (ascending sort is a no-op); a descending sort calls onSortColumnChange (builtin.d.tl) and we recreate the table
  through a new `meta.localKey` (the base forces regeneration the same way, statistics.tl:626). Stylesheet: 4 rules.
- **Same columns in both tables:** 8 columns, weights = UI px of the 700 px table (select 28, Change / Model 154,
  Vehicles 76, ≈ Rate 64, Buy now 94, Cost/yr 94, Cost per unit 110, note 80); window 740 px.
- **Line Manager look, no rules:** three group panels with the Line Manager sections' card nine-patches and colours
  (`R::LineManager / R::VehicleManager / R::LinePanel`, line_vehicle_mgmt.css.lua:169-187: card_surface + card_contour,
  BaseMedium, border BaseVeryLight), built as inline StyleSheets with `api.gui.NinePatch.new()` as
  vehicle_react_util.tl:95-106 does. The summary line became a stats row like `R::LineStatisticDetails !details`
  (line_vehicle_mgmt.css.lua:1594-1606: compact_surface, BaseVeryLight at transparency High; title above value,
  manager_window.tl:3891-3925). Those base rules are scoped by recipe names, so their classes can't be reused. The
  DataTable has no alternating row backgrounds in the base CSS (only hover / highlight), so none.
- **Target row:** -/+ and "Suggested" buttons get the TextInputField's vertical padding (2, builtin.css.lua:1074-1090),
  the label and "suggested" the same padding, so one line height and baseline.
- **Tooltips** wrapped with "\n" in the keys; Apply has none (the line above it). "Per rate" renamed "Cost per unit".
- **Texture errors** (`Could not find texture ''`): not ours. They appear in sessions without this mod (05:45, 06:52-07:09
  loads), on LoadPool threads, and none after our 07:12 open; our only image is the constant toolbar icon. The base CSS
  itself has `fileName = ""` nine-patches (builtin.css.lua:1093-1095).
Tests: 75.

## Phase 3e: polish after the fourth GUI test (2026-10-11, written, not yet run in game)

- Tables: `scrollPolicyVertical = AlwaysOff` too (the default policy showed a bar top right). The base sets vertical
  policies only to AsNeededButAlwaysReserveSpace in big scrolling lists (manager_window.tl:2751, vehicle_store_table.tl:581),
  so AlwaysOff in a small table is ours to verify (rows must not be cut).
- Stats row: fixed cell widths 150 / 120 / 160 / 258 px (money cell widest), title "Running costs per year", value
  without "/yr".
- "suggested" / "best": the same green tag (inline compact_surface nine-patch, base `Ok` colour, dark text), also next
  to the target box. No rules.
- "Buy now" renamed "Price" (tooltip: price of the new vehicles minus what the vehicles leaving the line sell for).
- Stylesheet: still 4 rules. Tests: 75.

## Phase 3f: polish after the fifth GUI test (2026-10-11, written, not yet run in game)

3e verified: a clone costs exactly metadata cost.price (548,640, balance log; docs/findings.md).
- Tags "suggested" / "best": plain text in the base class `positive` (default.css.lua:12-14), the colour of the Line
  Manager's Balance value (line_react_util.tl:630-635); no background. Note column 118 px (de "vorgeschlagen").
- Widths: in 3e the stats cells (fixed sizes + padding) poked out of the first panel and the tables ended short, which
  fits "StyleSheet size = content size, padding on top". Now: panel size = content width − panel padding (its outer
  edge = the content's), tables = panel inner width (724), stats cells = shares of that minus gaps and their padding,
  the last cell takes the remainder. Columns rebalanced to 724 px.
- Disabled Apply: rendered "secondary" while disabled (the base disabled primary is NeutralVeryDark text on NeutralDark,
  default.css.lua:91-100; disabled secondary only dims its border, :116-119).
- Stylesheet: still 4 rules. Tests: 75.
