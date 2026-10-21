# Findings: GUI, react and HUD

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Drawing arrows from an entity-window plugin (2026-10-09)

Found with `square_passenger_destinations` rev 1 (user's game test, 2026-10-09). Notes: `plans/square_passenger_destinations/PLAN.md`.

- **An entity-window plugin can draw map layers by stacking its own tool.** EOW plugins get `gameCtx.toolStack`. Pushing a
  window-less `react.RegisterTool{ push = function(ctx, p) ctx.setActionFn(actionFn, key) end, … }` with
  `allowStacking = true` makes its `ActionDescriptor` (e.g. `selector_react_util.makeDefaultSelectorAction(gameCtx,
  layerConfig, true)` with a `cargoFlowRenderableConfig`) the active one, and the arrows draw while the window is open.
- **Pushing shelves the entity window, which hides it** unless it is pinned (`EntityDetailsTool.shelve`,
  `gui/entity_window/view_manager.tl` ~404-415). The push handler runs after the shelve (`builtin.lua` push:
  `shelveNonTop`, then `pushHandler`), so `api.gui.byId.setVisible("temp.view.entity_<keyEntity>", true)` there brings
  it back. In game the station window stayed open with the arrows drawn. Popping the tool un-shelves the window tool.
- **A near-zero-length cargo-flow arrow crashes the game** (2026-10-11, `square_passenger_destinations` rev 5 test build,
  hovering a person's Locate pin in a building window): native assert `render_util.cpp:393 AddEveryNthPoint
  "(num)>=(2)", 1 < 2`, fatal, crash save written. The same second the mod pushed that person's arrows (person -> stop ->
  building), and one of them was most likely only a few metres long. The renderer seems to place points along the arrow
  at a fixed spacing and needs at least 2. Never put a `FlowData` with `from` ≈ `to` (or non-finite coordinates) into a
  `cargoFlowRenderableConfig`: Passenger Destinations drops arrows under 50 m (`MIN_ARROW_M`). The exact minimum isn't known.
- **Locate hover works by patching the shared module table** (2026-10-11): replacing `line_react_util.LocateButton` from
  a GUI script reached the base windows' name rows (vehicle passenger list); log `hover: LocateButton replaced` at load,
  and a hover push re-showed the window hidden by the shelve. `meta.onMouseOver` on a `Component` around the pin fired
  per row; a fast sweep down a list made ~10 pushes a second.

## Window fields differ by platform: PS5 rejects `closable` (player report 2026-10-12)

Player report from PlayStation 5 against `square_line_manager_plus` rev 5 (no log; text copied from the error screen):
opening the Line Rate Matcher window reloaded the UI with `Could not assign value to userdata 'closable'`, in
`react::recipeFn SquareRateMatcherWindow`, from `makeUserdata` in `::/gui/main/react.lua`. The window was
`builtin.Window{ id, title, closable = true, movable = true, onClose, content }`, the same shape every base window and
every square mod window uses on PC.

- **`react.lua` `makeUserdata` (~155-205) copies each param into `api.gui.react.params.builtin.<Name>.new()` and raises
  on the first field the class rejects.** The message names only the key; userdata, value and the engine's error
  follow on the next lines, which a player's screenshot of the first line doesn't show.
- **The console build's `Window` param class doesn't take `closable`** (at least not `true`), although PC's does and
  our extracted PC GUI scripts set it everywhere. The console ships its own build; never assume the PC `builtin.d.tl`
  field list holds there. The base context help already sets `closable = not isGamepadInputState:old()`
  (`gui/context_helper/context_helper_react.tl:864`), a hint that gamepad UI treats closing differently.
- **Pass every Window's params through a guard.** `platformWindow(params)` tries each field (except `content`,
  `header`, `meta`) once per key and value kind with `pcall` on a spare `api.gui.react.params.builtin.Window.new()`
  and leaves out (nil) what fails, logging once. If the spare object can't be made, it keeps the field. Undocumented
  fields such as `onMovedChange` are covered too. Give the window another way to close, since the X may be missing.
  Every square window uses it since 2026-10-12 (LMP rev 6, Problem Radar rev 8, Industry Flows rev 5, Supply Gaps
  rev 5, Better Minimap rev 9, Stress Test rev 2); copy it from any of them. Test:
  `tests/square_line_manager_plus/test_rate_matcher_gui.lua` "a platform whose Window lacks 'closable'".
- **Confirmed on PS5 (player report 2026-10-17, LMP rev 7, no log):** the guard works: the window opens without the
  UI error. But it took no controller input at all and couldn't be closed (stuck): a window without focus gets no
  gamepad input, and without `closable` there is no X. Still open: whether `movable` was accepted.
- **Gamepad windows, the base pattern** (confirmed on PS5 in the Smart Lanes rev 10 welcome, 2026-10-20, below): base windows close on
  the input action `IA_MENU_BACK` and take the focus themselves. The popover (`gui/main/popover_react_util.tl:8-15`,
  `:33-43`) builds its content with `meta = { forceFocusable = true }`, and the content recipe calls
  `react.useInputAction("IA_MENU_BACK", react.iaHandler(onClose))` and `react.onMount(function()
  react.useSelfRef():get():focus() end)`. The vehicle store, finance account and mission end windows set
  `autoFocusOnBecomingVisible = true` on the Window; the mission end window wraps its content in
  `gui_react_util.FocusTraversalScope{ horizontal = true, vertical = true, layout = ... }` (d-pad moves the focus,
  `gui_react_util.tl:457-473`). Gamepad mode: `app_util.isGamepadInputMode()` (`api.util.getInputMode() ==
  InputMode.Gamepad`, GUI thread only). The wiki says nothing about gamepads. Timetables isn't a reference here:
  no back handler, no `forceFocusable`, and its `closeable = true` is a misspelt field.

## Base GUI modules differ by platform: PS5 `content_card` has no `makeInfoHint` (player report 2026-10-19)

Player report from PlayStation 5 against `square_smart_lanes` rev 9 (no other mod active, no log; text copied from the
error screen): the first-load welcome window reloaded the UI with `attempt to call field 'makeInfoHint' (a nil value)`
in `react::recipeFn SmartLanesWelcome`, stack `=[C] (-1): makeInfoHint` / `sl_bg.script.lua (168)`. On PC
`content_card.makeInfoHint` is at `gui/main/content_card.tl:479` and works in a mod window (2026-10-14, above).

- **The console build ships its own base GUI scripts, and they lack functions the PC ones have.** With the
  `closable` report above it is the second PC-only GUI API seen. The extracted `.cache/game` files are the PC build;
  any base module function (`content_card.*`, `gui_react_util.*`, `react.*` hooks) may be missing on console.
- **Guard every base GUI module function a mod window calls:** `type(mod.fn) == "function"` (Teal: a local, then
  `is function`) and a fallback built from `builtin.*` widgets. `infoHint(text)` in Smart Lanes `sl_bg.script.lua`,
  Organic Towns `ot_card.script.tl` and Problem Radar `radar_hud.script.tl` builds the base hint's own tree
  (`info-hint-comp` Component, `info-hint-text` TextView) without the icon image; Organic Towns shows no card when
  `ContentCard` / `makeRecipeAndParam` are missing; the Smart Lanes welcome's gamepad pieces (`useInputAction`,
  `useSelfRef`, `FocusTraversalScope`, `pcall(ug_require, gui_react_util)`) are skipped where absent.
- **Confirmed on PS5 (player report 2026-10-20, Smart Lanes rev 10, no log):** the guarded welcome window works.
  Since the console window has no X (`closable` is left out), answering it (Apply / Not now) means the gamepad
  pattern below took controller input: `autoFocusOnBecomingVisible` on the Window, `forceFocusable` content,
  focus on mount, `IA_MENU_BACK`, `FocusTraversalScope`, each hook only where the platform's `react` has it.
  Which branch ran (base `makeInfoHint` or our fallback, hooks present or skipped) isn't known.
- **The rule for every square mod since 2026-10-20:** a render-time call into a base `::/gui/...` widget helper is
  either inlined, when the base body is a one-liner of `builtin.*` widgets (`gui_react_util.makeHorizontalSpacer`,
  `cargo_react_util.makeIcon`), or guarded with a `builtin.*` fallback or a skip (`content_card.makeInfoHint` /
  `ContentCard` / `makeRecipeAndParam`, `gui_react_util.FocusTraversalScope` / `FocusTextInputField` /
  `makeContentLabelIndictator`, `dialog_react_util.DialogWindow`, `construction_react_util.SimpleTooltipRecipe`,
  the `selector_react_util` / `hud_react_util` / `hud_icon_toolbox` pieces of a tool action, the `react` gamepad
  hooks `useInputAction` / `iaHandler` / `useSelfRef` focus / `setForceFocusable` / `setRestrictMouseFocus`).
  Where each lands: Smart Lanes and Better Auto Vehicle Renamer welcomes; Organic Towns and Passenger Destinations
  cards (no card when `ContentCard` is missing; Passenger Destinations' action keeps only its own LayerConfig);
  Problem Radar `infoHint`; LMP Rate Matcher, Better Minimap window, Bulk Bulldozer tool (gamepad hooks; no cursor
  tooltip without `SimpleTooltipRecipe`); Photo Mode name fields (plain `builtin.TextInputField`); Industry Flows
  action (no HUD icons / selector when missing); Stress Test (own `platformWindow` dialog without `DialogWindow`);
  Supply Gaps, Industry Production Label, Better Bus Overlay HUD pills (the function is resolved once, its first
  call pcall-tried, then an own tree with the base classes). Out of scope: the core `react` API (`RegisterRecipe`,
  `useState`, `onStep`, `setMouseTransparent`...), `engine_react_util.useStepState*`, `builtin.*`, `styleutil`,
  `game_react_globals`, extension points (nothing works without them), data helpers (`cargo_util`, `line_util`,
  `color_util`) and install code that patches a base function, which already checks its type and logs. Tests: each
  mod has one rendering with the functions missing (search the tests for "PS5 report 2026-10-19").
- Still unknown: which of `content_card`'s other functions exist on console, and whether the base `info-hint-*`
  classes are styled there. Tests: `tests/square_smart_lanes/test_tool.lua` "all lights (welcome)" (R6: no
  `makeInfoHint`, gamepad).

## Timers and threads in GUI contexts (2026-10-10)

Probe `square_sqperf_probe` (log lines `[SQPERF-PROBE]`, game stdout.txt), "New Game - desert", build 40420.
`api.type.Clock.new()` and `:getTime()` worked in every GUI context, with no crash or error:

| Context | Thread column in stdout.txt |
|---|---|
| recipe render (GUI script) | Main Thread |
| `react.onStep` | Main Thread |
| `react.onStepTimer` | Main Pool N (worker threads, a different one per tick) |
| `hudIconScript` function and its recipe render | Main Pool N |

- Cost on the Main Thread (20 000 calls): `getTime` 0.07 µs, `os.clock` 1.0 µs. SQPERF's `wrap` adds 0.28 µs per
  call and `hit` 0.03 µs. Use Clock, not `os.clock` (which is also process CPU time over all threads on macOS).
- **How much `os.clock` overstates on the Main Thread under load** (2026-10-15, session
  `2026-10-15_1950_city-lights-2-778824`, 6 cities, 4x): Smart Lanes' background runtime timed its frames with `os.clock`
  and logged snapshot frames of 81.52 and 49.20 ms (`AUTORETIME op=snapshot ... max_frame_ms=`, 19:56:49 and 19:58:30),
  while SQPERF's `api.type.Clock` timing of the same step saw at most 12.8 and 13.8 ms in those 30 s windows
  (`ctx=bg ... auto ... max=12.788`, `max=13.783`); its 1 ms `os.clock` budget summed to 650-960 "ms" per snapshot against
  600-875 ms of Clock time per 30 s for the whole runtime. Roughly 3-6x while the simulation threads run: an
  `os.clock` budget stops early by that factor, and an `os.clock` maximum is no evidence of a stutter.
- So the onStep/onStepTimer split matters: in this probe `react.onStep` ran on the Main Thread, while
  `onStepTimer` and HUD icon scripts ran on worker threads. GUI-thread-only calls (`api.gui.*`,
  `getApplicationTime`) belong in onStep or render, or behind `react.enqueueJoin` from onStepTimer.
  The earlier square_supply_gaps crash ("Main Pool 10") is consistent with a worker-thread callback.

## ImageView raw pixel data (2026-10-09)

`builtin.ImageView{ data = {...}, size = api.type.Vec2i.new(w, h) }` draws a raw image. Verified in game (square_better_minimap network layer, calibration squares + road layer vs town markers):

- One Lua integer per **byte**. The data length must be exactly `w*h*3` or `w*h*4`. The binary checks `bytes / (w*h)` and accepts only 3 or 4 ("only 3 or 4 is supported"). Otherwise it logs an error and shows a default image; it doesn't crash.
- Channel order **RGBA**, and alpha works: alpha 0 is fully transparent over whatever is underneath.
- Rows are **bottom-up**: the first row of the data is drawn at the bottom of the image. Write rows in reverse for a top-down raster.
- Related (same mod): `api.engine.getEntitiesWithComponent(BASE_EDGE)` throws "Cannot loop over this component type". List
  every edge with `api.engine.system.streetSystem.getNode2StreetEdgeMap()` / `getNode2TrackEdgeMap()` (each edge appears
  under both of its nodes, so de-duplicate).

## Window `header` slot (2026-10-10)

`builtin.Window{ header = <node> }` (builtin.d.tl:1209) puts the node at the **left** of the title bar, before the
title, in the dark title tab (square_better_minimap size button). An empty title plus
`Window#<id> Window::Title { visibility = "none" }` removes the title text cleanly. In game, two attempts to
right-align the header next to the pin both left it at the left: `gravity = { -1, 0 }` on the header recipe's root, and
an explicit root `size` (picture width - 56 UI px) with the button at `gravity = { 1, 0 }`. The header container has no
stylesheet name in the base CSS (only `Window::TitleBar`, `TitleLayout`, `Title`, `Icon`, `Content`, `Close`, `Locate`).
The pin sits in its own notch outside the title tab.

## Wrapping rows in a GUI plugin: `builtin.FlowLayout` (2026-10-10)

- **`builtin.FlowLayout{ children = {...} }` wraps its children onto new rows to fit the available width**, also inside
  an entity-window plugin's `ContentCard` (`extraChildrenPermanent`). Its only field is `children`
  (`base/tealdef/scripts/builtin.d.tl:683`); the base game uses it for sparse construction-menu toggle buttons
  (`construction_desc_react_util.tl:970`, `builtin.lua:817`).
- Use it instead of splitting a horizontal `BoxLayout` into rows after a fixed item count: the window width varies (a
  port's station window is narrower than the counts assumed), and wider labels (two-digit numbers) overflow sooner.
  Items past the edge of a `BoxLayout` are silently cut off.
- Spacing: keep each item's gap inside the item (`BoxLayout{ item, gap }` with a fixed-width styled `Component` as the
  gap), so a wrapped row never starts with a bare spacer. Simpler and checked in the base: the FlowLayout's own
  `innerSpacing` through a class rule (it sits between items only; "Inline styleSheets don't apply to layouts" below).
  Never inline padding on a wrapping BoxLayout: it doesn't apply.
- Evidence: `square_passenger_destinations` rev 3. The station card's "Destinations: [] All [] 1 … [] Next stop" row
  (fixed 6 + 10 per row) was cut off in a port window; as one FlowLayout it wrapped correctly in game.

## Firing base react events from a mod: `replaceVehicles` (verified in game 2026-10-10)

- **Verified in game (2026-10-10, Problem Radar rev 6 from the staging area):** a mod GUI script's button
  click that fires `react.fireEvent(nil, "replaceVehicles", VehicleStoreEventParam{vehicleEntities, carrier,
  transportModes, filterTags})` opens the game's own **Replace Vehicles** window, and replacing from it works
  (`mods/square_problem_radar/content/radar/gui/radar_fleet.tl` replaceVehicles). It is the exact call of the
  vehicle window's Replace button (`base/content/gui/entity_window/vehicle/vehicle.tl:445-462`); the listener is
  `react.onEvent("replaceVehicles", ...)` in `vehicle_store_window.tl:4895`. `react.fireEvent` is the native
  `api.gui.react.fireEvent` (`gui/main/react.lua:825`) and reaches base listeners from a mod.
- The param's `onClose` runs on accept (after `vehicle_react_util.HandleVehicleChanges` has sent the
  `makeVehicleReplaceCmd` commands, `vehicle_store_window.tl:4654-4674, 4919-4925`) and on cancel. Replace keeps
  the vehicle entity (`makeVehicleReplaceCmd(entity, config)`, `vehicle_react_util.tl:405-408`). Problem Radar
  uses `onClose` to send a recheck event to its game script. Pending: whether the replace has applied by the
  time that event is handled (the mod re-sends it after 3 s to be safe).
- `fireEvent` returns nothing, so a missing listener can't be detected.
- GUI font glyphs (checked offline with fontTools on `base/content/locale.zip`): Lato (`locale/Lato2OFL/`) has
  `↑ → × ● · – …` but **not** `⇧ ▲ ⬆ △`; Noto Sans CJK has all of them. That matches the HUD showing `▲` as `?`.
  **Verified in game (2026-10-10):** `↑` renders in the radar window's row buttons. Use `↑` for an "upgrade"
  button; pending: whether window text falls back to Noto for `⇧`/`▲`.
  Hourglass (fontTools, 2026-10-20): `⌛` (U+231B) and `⏳` are **not in Lato** Regular / Bold, but are in Noto Sans
  CJK; Lato has `*`, `†`, `×` and `⁺`. Pending (Better Auto Vehicle Renamer TESTING.md I): whether a vehicle name
  with `⌛` shows the glyph or `?` in an English game.
  Check marks (fontTools again, 2026-10-17, build 40422): Lato Regular / Bold have **`√` (U+221A) but not `✓` (U+2713),
  `✔` (U+2714) or `☑` (U+2611)**; Noto Sans CJK has all four. No base game text uses a check glyph (search of
  `base/content` and `api` for ✓ ✔ ☑ ✅: none). Smart Lanes' lane status badge uses `√` for "applied": **renders correctly in game** (user screenshot 2026-10-16, "√ Smart lanes | √ Smart lights" in the Smart Lanes tool's info block, English).
- Window background: the default `Window` rule uses `BaseDarkMedium` with transparency `VeryLow`
  (`gui/main/builtin.css.lua:16, 1946-1953`), so a window over another one lets it show through. The base dialogs
  set `backgroundColor1 = colorDefault.BaseDarkMedium` (opaque, `popover_react_util.css.lua:10-12`); Problem Radar's
  fleet window does the same on its window id. Pending: confirm it looks opaque in game.
- Colours (2026-10-10, from `gui/main/default_colors.gres.lua:50-59`): the base `!positive` class is `Positive` =
  jordyBlue, a light blue that players read as a link; green is `Ok` (kellyGreen), red `Negative` (lightCoral) or
  `Error`. For money, Problem Radar uses `Ok` / `Negative` in its own classes.
- Vehicle age units: `api.engine.util.formatAge` formats "using current ingame speed" (`engine/util.d.tl:1066-1070`),
  and the base vehicle window shows Age that way (`vehicle_util.tl:297-313`), while model lifespans are game ms
  at the default calendar speed (`mdl.md:293`, `vehicle_util.tl:31-34`). Years from `getDefaultYearDuration`
  therefore over-state the Age shown by the game when the calendar runs slower than default. Problem Radar converts
  with `api.util.getYearDuration(GAME_SPEED.millisPerDay)` instead (`radar_checks.calendarYearMs`). Pending: confirm
  in game that the numbers now match the vehicle window.
- Past its lifespan (code reading 2026-10-20, Better Auto Vehicle Renamer's old-vehicle mark): the base vehicle
  window takes the part bought first (ties: the shorter lifespan) and its model's `metadata.maintenance.lifespan *
  1000` as game ms (`vehicle_util.tl:31-51` `getLifespan` / `getMinPurchaseTimeAndLifespan`), and shows a "time
  remaining" only while `GAME_TIME.gameTime < purchaseTime + lifespan` (`vehicle_util.tl:297-313` `getAge`). That
  compares game ms directly, no calendar conversion. A model without `maintenance.lifespan` has 0 (wiki `mdl.md:291`).
  Pending: confirm in game that the mark appears when the vehicle window's time remaining runs out.

## Expired react states print a traceback on `:old()` (verified from the game log 2026-10-11)

A react state (`ReactStateWrap`) whose recipe has unmounted is **expired**. Calling `:old()` on it doesn't raise a Lua
error (`pcall` returns true): it returns `nil`, but the engine writes a message-less `stack traceback` to stdout.txt
at the call, and later, in the timestamped log, `VERBOSE ... Calling Old() on expired ReactStateWrap returns nil`.
`:set()` on an expired `ReactRefWrap` does the same with `MESSAGE ... Ignoring Set() on expired ReactRefWrap`. Check
first with `s:hasExpired()` (on `ReactStateT` and `ReactRefT`, `base/tealdef/scripts/react.d.tl:130-142`), as the base
does (`gui/main/engine_react_util.tl:146`, `builtin.lua:1168`).

Evidence (stdout.txt of 2026-10-11, Line Manager Plus rev 1 in development): each reopen of the Line Manager printed
two tracebacks, `=[C](-1): old` ← `lmp_capture.lua(63): editedLine` ← `undo.lua(93): ensureSession` ← ... ←
`safeView`, the first under `declareStateLazy` ← `useStateLazy` ← `engine_react_util.tl(74)` (the `useStepState`
initial value), the second under `engine_react_util.tl(84): update` (its `onStep`). Each pair is followed by exactly
two `Calling Old() on expired ReactStateWrap returns nil` lines (20 tracebacks, 20 messages; the 12 `set` tracebacks
of another mod match 12 `Ignoring Set()` lines one for one). So reading a state inside a `useStateLazy` initializer is
**not** the problem; the state was expired. The cause: mods that capture the manager window's `commonParams` (from
`line_util.makeLineActionDescriptor`) keep the closed window's table, and the new window's buttons render and step
once before its first descriptor call replaces it. Fix in Line Manager Plus / Line Editor Undo: `hasExpired()` guard
in `editedLine`.

## DataTable cell recipes get a userdata param (verified from the game log 2026-10-11)

A `builtin.ColumnDesc{ recipe = R }` cell recipe is called by the game's C++ DataTable with ONE **userdata**
argument (`Builtin.TableCellParam`: `rowKey`, `colKey`, `userParam`, builtin.d.tl:1125-1129), not with the Lua table
that `builtin.DataTableCell` (builtin.lua:120-123) would build. Fields read by index work (`params.rowKey`,
`params.userParam` is the Lua table the column was given); `pairs()` and `type(p) == "table"` checks don't. Evidence:
Line Manager Plus's row-hover wrapper (line_list_hover.lua) logged `decorate: userdata` and skipped every row while
checking for a table. Wrapping a cell recipe: read the three fields and pass a fresh table on.

Related, when calling a recipe with `react.ref(x)` yourself: a **plain Lua table** `x` is taken as a LIST of refs
(react.lua:355-360: `if type(ref) == "table" then for _, v in ipairs(ref) do v:set(node) end`), so a hand-made
`{ get, set }` holder is never set. Pass `react.ref({ holder })`, or a `react.useRef()` (userdata). Seen in game
2026-10-11: the holder stayed nil, the callout failed with "attempt to index local 'row' (a nil value)".

## DataTable column weights, inline sizes on recipe calls, meta through recipe wrappers (verified in game 2026-10-11)

- `builtin.ColumnDesc{ weight = n }` (`builtin.d.tl:1142`): in the Line Manager's vehicle list (no weights in
  vanilla) giving only the name column `weight = 1` and making the picture column content-sized (CSS
  `size = { -1, -1 }`) handed all spare width to the name column: the picture column shrank to its widest picture
  plus the hover buttons, the names grew. Cells do not stretch over their column by themselves: the cell's root
  recipe needs `gravity = { -1, -1 }` (as base `statistics.css.lua` does for its cell recipes). A long name stayed
  inside the window with `size = { -1, -1 }, minSize = { 120, -1 }, maxSize = { 320, -1 }` on VehicleName.
  Square Line Manager Plus rev 5 (`vehicle_columns.lua`, `lmp.css.lua`).
- Inline `api.gui.StyleSheet` (fields: colours, images, border, `size`, `padding`, `fontSize`, `anchorPoint`; no
  `gravity`, `margin`, `minSize`) passed as `meta = { styleSheet = st }` on a RECIPE call applies to that recipe's
  node: `Badge{ ..., meta = { styleSheet = st } }` with `st.size = Vec2f(w, -1)` set the badge width per row and
  replaced 10 class rules (LMP 33 -> 25 stylesheet rules). As in CSS, `size` is the content size; padding adds.
- react applies a recipe call's `meta` (class, styleSheet, onMouseOver) to that recipe's node and strips it from the
  params. So replacing a base recipe with a wrapper recipe moves the caller's classes onto the wrapper: Square
  Passenger Destinations rev 5's `LocateButton` wrapper got the rows' `hidden-button` class, the base rule
  `#menu.management R::LocateButton!hidden-button Button *` stopped matching and every Locate pin in the Line
  Manager showed on every row. Fix (rev 6): install a plain FUNCTION that sees `meta`, carries it in a param field
  and passes it to the base recipe call as its `meta`.

## Recipe roots, Component layouts and ScrollArea content (verified in game 2026-10-05 to 2026-10-09)

None of these is caught by `make check`; each one crashes the whole game, not just the widget.

- A custom recipe (`react.RegisterRecipe`) must return a **layout** (`builtin.BoxLayout{ children = ... }`) at its
  root. Returning a component (`builtin.ScrollArea`, `TextView`, even `builtin.Component{meta=..., layout=...}`)
  fails with "Recipe child must be a layout" or CRITICAL "Script component root failed" + minidump
  (square_problem_radar settings page 2026-10-05, square_stop_line_view badge 2026-10-09). Put a styled Component
  inside the BoxLayout. Builtin components like ScrollArea are fine directly in a BoxLayout.
- Never `builtin.Component{ layout = MyRecipe{...} }`: react_builtin.cpp:564 "Item of Component must be a layout",
  even when MyRecipe returns a BoxLayout (square_minimap window, 2026-10-06). Put the recipe directly where an
  item/child goes (`FloatingLayoutChild{ item = MyRecipe{} }`, as base finances_cargo_lifetime.tl). Grep new GUI
  code for `layout = [A-Z]`.
- `builtin.ScrollArea{ content = builtin.BoxLayout{...} }` throws "ScrollArea does not accept a Layout as
  content". Wrap it: `content = builtin.Component{ layout = vbox(...) }` (base entity_window_util.tl:715-721;
  hit in square_industry_flows' type list, only shown with more than 8 types).

## ImageView: rotation, icon masks, no mouseTransparent (2026-10-07)

- `builtin.ImageView` takes `rotation` in degrees (`base/tealdef/scripts/builtin.d.tl` ImageViewParam, used at
  `construction_react_util.tl:884`), plus `data` / `numFrames` / `frame`. Search builtin.d.tl for widget params
  before concluding the GUI can't do something.
- GUI icons are greyscale masks tinted by the stylesheet `color` on the ImageView (`game_bar.css.lua:161-165`).
  Textures are in `<TF3 install>/base/content/gui.zip` (`unzip -l`; `sips -s format png` to view). Arrows that
  read well rotated at 16-18 px: `::/gui/construction/build_control/symbol_arrow_straight_up_20.tga`;
  `::/gui/builtin/combobox/arrow_up.tga` is ambiguous when rotated (player feedback).
- ImageView has **no** `mouseTransparent`: passing it crashes at render ("Could not assign value to userdata
  'mouseTransparent'", react.lua:201). `make check` misses unknown fields in `builtin.X{...}` calls (overloaded
  `__call`); a typed `local p : Builtin.ImageViewParam = {...}` catches them.
- The in-game HUD label font renders `▲` as `?`: use an image icon (`iconPath`), not Unicode symbols, in HUD pills.

## Placing GUI items at exact pixels (square_better_minimap, 2026-10-07)

`FloatingLayoutChild` h/v placement is unreliable for anything bigger than a few px (fractional gravity: stuck at
the left edge; h=1,v=1 in a sized container: x ignored; anchorPoint + Overflow: everything left-centre). What
works: one layer per item as `FloatingLayoutChild{ h=-1, v=-1 }` (fill) -> `Component` whose styleSheet has
`size={pw,ph}` and `padding = Vec4f(top, pw-left-w, ph-top-h, left)` (CSS order; set `st.padding` directly,
styleutil.makeStyle has no padding) -> `BoxLayout{ item }`. See `layerAt` in
mods/square_better_minimap/content/minimap/gui/minimap_hud.script.tl. Four in-game rounds to find.

## Window frame minimum height (2026-10-07)

Window surface/contour nine-patches slice vertically at {0, 50, 52, 92} UI px (`builtin.css.lua:1950-1966`; shadow
{0, 89, 96, 156}). A window shorter than ~90 UI px draws overlapping frame and shadow pieces (minimized
square_better_minimap at ~72 px). The top 50 px are the title tab, so a `compact = true` window's own title row
should be ~48 px (36 px clipped "Map" to "Man"). Measured: content 92 -> ~120 px window, clean; content 64 ->
~84 px, glitched. Give short custom windows a >= 92 px minimum height.

## Reading and restoring a window position (square_better_minimap rev 3, 2026-10-07)

- `getPosition()` on a `RegisterWrapperRecipe(..., builtin.Window, ...)` self ref always returns (0,0)-(0,0). Read
  a node inside the window (the content recipe's `useSelfRef`), like base `content_card.useShowCalloutOnRight`.
- Window anchor = content top-right + frame offset; measure the offset once as `requested initialX/Y - content
  top-right` before the player moves it (measured dx 0, dy -0.0404 at 2560x1440).
- Place windows with CSS `anchorPoint` + `initialX/Y` (entity-window pattern). A CSS `gravity` on the window
  prevents initialX/Y from being applied.
- Persist UI prefs with `api.gui.game.setGuiSaveData(modId, table)` / `getGuiSaveData(modId)` (per savegame).
  The first version kept them in `AppConfig.mainMenuState[modId]` + `api.util.saveAppConfig()`; it worked in game,
  but the upload review rejects `saveAppConfig` (2026-10-20, `findings/publishing.md`).

## HUD icon recipes run off the GUI thread (crash 2026-10-07)

`hudIconScript` recipes run on a worker thread. Calling an API documented "Only available in GUI thread" there
(`api.util.getApplicationTime`, `getInputMode`) is a native null deref (EXC_BAD_ACCESS at 0xd8), not a Lua error,
so pcall doesn't help (square_industry_production_label's pickup cache crashed right after "Game is ready"). In HUD
recipes time with `api.type.Clock` (safe in every context, see the thread table) or `os.time()`; grep `.cache/game/api/tealdef` for "GUI thread" before using any api.util /
api.gui call in HUD code. Thread table: "Timers and threads in GUI contexts" above.

## Inline `size` is the content box; padding adds outside it (square_problem_radar rev 8, 2026-10-12)

User's screenshot, 2026-10-12: a ridge `ToggleButton` with `styleSheet` `size = { -1, 40 }` and padding 8 on top
and bottom drew a 56 px tile next to the 40 px base layers button (24 px ImageView + 8 px padding). `size` sizes the
content; the padding goes on top of it. To match an icon tile with text content, pin the content to the icon's
height (`size = { -1, 24 }`) and keep the base padding. Font size setting: body text is 14 / 17 / 19 px
(`base/content/gui/main/font_scaling.css.lua:88-99`), so a fixed 24 px content holds every setting. Not yet
re-checked in game after the fix.

## Quitting runs no react.onUnmount (verified from the game log 2026-10-13)

Session `2026-10-13_0040_sqpq` (DEV `square_photo_quality_probe`): its `::MainModButtonAreaExtension` plugin logs in
`react.onUnmount`, and two "Quit > Return to Main Menu" in one session ("Main menu is ready" at 00:42:53 and
00:43:47) logged no unmount line. The pause menu calls `app.stopGame()` directly (`base/content/gui/main/pause_menu.tl`
~197; "Return to Desktop" is `app.quit(true)`), so the game GUI is torn down without unmount callbacks. Cleanup that
must run before leaving a game can't go in `onUnmount`. Every quit opens the pause menu first: the react event
`"openPauseMenu"` (fired by the game bar's menu button, `game_bar.tl:1195-1210`; the settings page listens to it too,
`settings_page.tl:1471`) is the hook.

**Verified 2026-10-13** (session `2026-10-13_0053_session`): a `::MainModButtonAreaExtension` plugin's
`react.onEvent("openPauseMenu", fn)` fired 5 of 5 times the pause menu opened, from Esc, the game bar's menu button
and Cmd+Q (on macOS Cmd+Q opens the pause menu instead of quitting), always before the player could reach Quit or
Settings. A quit request from outside the game (macOS Force Quit dialog, Steam's stop button) also only logs
`Quit requested` and opens the pause menu (`2026-10-13_0059_sqpq`, user report for both), so the event fires then
too. Not covered: a crash or `kill -9`; keep a next-load safety net for those (untested).

## The HUD filter is base GUI save data; the default selector reads it when it renders (read from the game files 2026-10-13, not verified in game)

For Photo Mode's "Hide labels" (`mods/square_photo_mode/content/photo_mode/gui/pm_hud.lua`):

- The data layers' HUD filter window (`base/content/gui/layers/layer_hud_filter.tl`) stores its state in the
  savegame's base GUI save data: `api.gui.game.getGuiSaveData("")`, field `hudFilter` (`BaseGUISaveData` in
  `gui/main/game_context.d.tl:83-97`: `preFilters` per component type and `preFilterTvCarriers` per Carrier,
  `"Hidden"` / `"Default"`; `showCosts`, `showIncome`, `showEventIcons`, `showCargoFlow`). It writes it with
  `setGuiSaveData("", copy)` on every click. No `api.gui` call shows or hides the HUD icons, and no input action
  toggles them.
- The HUD icons get the filter through `builtin.HudIconManagerConfig{ preFilter, preFilterTvCarriers, showCosts,
  showIncome }`, built by `makePreFilter` when the default selector's action renders
  (`gui/main/selector_react_util.tl:43-86, 194-240`; the default tool's action, `entity_window/view_manager.tl:56`).
  That action re-renders on its two react states, set by the events `"preventReactSelector"` /
  `"allowReactSelector"`, which no base code fires (`react.fireEvent(nil, name, "")`, as `replaceVehicles` is
  fired). Event icons and cargo flow read `hudFilter` live in their own HUD scripts.
- **While prevented, the default selector has no hover** (`selector_react_util.tl:194-232`
  `makeDefaultSelectorCombinedFn`): it adds `makeDefaultSelector` (the highlight under the mouse and the
  click-to-select that opens entity windows) and `makeDefaultSelectorTooltips` (the entity tooltip) only when
  `not selectorPreventedState:old()`; the HUD icon config stays. Photo Mode (round 6, "Hide labels and hover")
  writes the hidden filter, fires `preventReactSelector` and keeps it until the labels come back, then writes the
  player's filter and fires `allowReactSelector`. The state is the action's own `useState(false)`: a selector that
  mounts again (after another tool) starts allowed, so Photo Mode fires prevent again at each tour start. To
  verify in game (TESTING.md G21): labels and hover go at once, a click on the map opens nothing, both come back
  on untick; whether another tool and back brings hover back early.
- **Open (user report, session `2026-10-13_1755_session`): "The tour still has hover and mouse interaction with
  it."** The labels checkbox was on (`labels and hover hidden` at 18:34:46) and every tour start fired
  `preventReactSelector` again. Between them the footer's Camera mode pushed and popped the base free camera
  twice, and the first tour's camera mode probe pushed and popped it again: each pop likely remounts the default
  tool's selector (allowed). Whether a later tour start's prevent took effect is unknown (no log can show the
  selector's state). Photo Mode round 9 prevents the selector for every automated camera move, labels or not, at
  its start and again 2 and 30 frames later, and allows it when the move ends (TESTING.md V1 checks it).
- When every carrier is hidden, `makePreFilter` hides `TRANSPORT_VEHICLE` icons as well. `BASE_NODE` is in the
  default filter list but has no toggle in the window, so a mod should not hide it (the player couldn't undo it).

## Input actions don't reach a hidden GameUIRoot (read from the game files 2026-10-13, not verified in game)

**Update 2026-10-13 (session `2026-10-13_1915_session`): the pause menu DID open while Photo Mode had the UI root
hidden** (`tour: window hidden, game UI hidden` at 19:18:24, then `tour off (pause menu)` at 19:19:56 from the
`openPauseMenu` event, no pause-key escape line between). Which key opened it is not logged (Esc most likely; Cmd+Q
also fires the event), so whether Esc itself reaches the game while hidden is likely but not proven. Photo Mode's
hidden-UI modes still keep the pause-key escape hatch.

For Photo Mode's "Hide UI" (`api.gui.byId.setVisible("react.game-ui-root", false)`, `docs/findings/map-camera.md`
"Hiding the game UI"):

- `base/content/gui/main/game.tl:803` handles Esc (`IA_MENU`) only by forwarding it into the GameUIRoot node
  (`react.useInputAction("IA_MENU", react.iaForward(gameUiRef))`, `uiCloseAll` likewise), and the base comment over
  those proxy-root actions (`game.tl:746-747`) says: "Input Actions declared here are available even when Game UI is
  not visible. Note that forwarding to an invisible GameUIRoot is still impossible." The pause menu opens from
  inside that root (the `openPauseMenu` event handler, `game.tl:195-205`; the game bar's menu button,
  `game_bar.tl:1195-1210`). So Esc most likely does nothing while the root is hidden.
- `api/tealdef/api/gui.d.tl` `InputActionState.Enabled`: "fully enabled ... (except if disabled/invisible due to
  hierarchy)": input actions of an invisible subtree don't fire. Every mod plugin point (`::MainModButtonAreaExtension`,
  `::ModEntryPointExtension`, `game.tl:378, 573-583`) is inside GameUIRoot, so a mod's own
  `react.useInputAction("IA_MENU", ...)` is hidden with it (and while visible it could swallow Esc before the base
  forward when focus is inside the mod's subtree).
- Still available while hidden: the proxy root's own actions (`gamePause`, `gameCycleSpeed`,
  `IA_GAME_PAUSE_OR_CYCLE_SPEED` (Space), `IA_QUICKSAVE`, `game.tl:752-796`), react events (`openPauseMenu` from
  Cmd+Q / quit requests, this file "Quitting runs no react.onUnmount") and plugin `react.onStep`. A mod can notice the
  pause key by reading `GAME_SPEED.speedup` each frame (`api.engine.getComponent(api.engine.util.getWorld(),
  GAME_SPEED)`, as the base GameSpeedHelper does every frame) and treat a change between 0 and running as "bring the
  UI back" (the speed throttle, `game.tl` GameSpeedHelper, lowers 4x but never pauses). Photo Mode does this
  (`gui/pm_hud.lua` escape hatch). To verify in game: Photo Mode TESTING.md G20 (Esc, Space, Cmd+Q while hidden).

## Inline styleSheets don't apply to layouts (user screenshot 2026-10-13; mechanism read from the game files)

Photo Mode rounds 3-5 spaced its window with inline sheets on layouts: each row item wrapped in a
`builtin.BoxLayout{ meta = { styleSheet = st } }` with `st.padding` 4 right / below, labelled rows and the footer
(8 px on all sides) the same way, the content's root BoxLayout with padding and `size`. In game none of it showed
(user screenshot of the Tour tab, round 5 build): the ToggleButtonGroups of consecutive rows touched, checkbox
labels ran into the next box, the footer checkboxes sat on the window's bottom / left edge.

- `react.lua` (~300-385): for a builtin (`DeclareBuiltinWithUserdata`, BoxLayout and FlowLayout included) the
  call's `meta.class` becomes the node's style class, and the other meta fields (styleSheet, tooltip, enabled)
  are handed to `builtin.WithComponentParams{ item = node, ... }` (`builtin.d.tl:634-646`: params of a
  *Component*). A layout isn't a Component, so the sheet has nothing to style. The base game never puts an inline
  `styleSheet` on a layout (every `styleSheet =` in `base/content/gui` sits on a Component, TextView, Button or a
  `WithComponentParams` around one).
- What does space a layout: its `innerSpacing`, set only by stylesheet rules (base `builtin.css.lua`
  "ToggleButtonGroup!flow FlowLayout" { 4, 4 }, "CheckBox BoxLayout!buddy-layout", "R::FeedbackItem > BoxLayout").
  Padding on a layout through a class rule did NOT show either (round 8, next entry). Inline sheets do apply to
  Components (Better Minimap's `layerAt` padding, verified), TextViews and a recipe call's node.
- Fix (Photo Mode round 6, not yet seen in game: TESTING.md G22): classes on the layouts and three rules
  (`R::PhotoModeContent !sqpm-gap` innerSpacing 6/6, `!sqpm-checks` 12/6, `!sqpm-content` padding 8 +
  innerSpacing 8), no element name so one rule covers BoxLayout and FlowLayout. A class on a `builtin.FlowLayout`
  goes the same `meta.class` path as on a BoxLayout (both `DeclareBuiltinWithUserdata`), but no base file does it:
  confirm in game. Offline guard: `tests/square_photo_mode/test_window.lua`. Rules for every mod:
  `docs/ui-guide.md` "Spacing".

## Padding applies to Components, not layouts (user screenshot 2026-10-13, round 8; inferred)

Photo Mode round 7 build, Subjects tab: the footer's checkboxes sat ~6 px from the window's left edge while the
tab content's text sat ~20 px in. The content's root column (the recipe's BoxLayout) carried
`R::PhotoModeContent !sqpm-content { padding = 8, innerSpacing = 8 }`; with the padding applied the footer would
have sat ~14 px in. The ~14 px difference to the tab text is the base `TabWidget::Content` padding (8, a
Component; `builtin.css.lua` ~969-983) plus its frame: so the TabWidget page was padded and our layout was not.

- Inferred: `padding` from a class rule does nothing on a BoxLayout / FlowLayout (the selector itself is the
  base pattern: `R::Recipe > BoxLayout` and descendant classes, e.g. `R::MissionPageContent > BoxLayout`
  innerSpacing, `campaign_menu.css.lua`). No base rule pads a layout: base pads Components (`TabWidget::Content`,
  `R::Component!...`, Buttons). Timetables' `!celmi-tt-content` padding sits on a BoxLayout too, but its window
  also has a `TabWidget` margin of 8, which may be what shows; our Better Minimap's `BoxLayout!minimap-controls`
  padding is equally unconfirmed.
- Photo Mode round 8: the root column sits in a `builtin.Component` with an inline padding of 8; the footer in a
  Component with an inline padding of 8 left and right (the tab page's inset); `!sqpm-content` keeps only its
  innerSpacing. To confirm in game: `plans/square_photo_mode/TESTING.md` U4.

## The base free camera tool from a mod (read from the game files 2026-10-13, not verified in game)

For Photo Mode's camera mode (round 6, `mods/square_photo_mode/content/photo_mode/gui/pm_hud.lua`):

- The game bar's free camera button pushes `free_cam_options.FreeCamTool` on the default tool stack:
  `getToolStackApi(gameCtx).push(free_cam_options.FreeCamTool, nil, { gameCtx = gameCtx }, true)`
  (`gui/game_bar/game_bar_widgets.tl:105`, `game_bar.tl:143`). The tool's `push` calls
  `api.gui.camera.toggleFreeCamera()` (or `enterFollowCameraCockpit` with `cockpitCameraForEntity`), its `pop`
  `leaveFollowCameraCockpit()` (`gui/main/free_cam_options.tl:36-47`); the param's `gameCtx` is not read.
- The UI hides by itself: `!action-follow R::GameUIRoot { visibility = "none" }` and `!action-follow Window,
  !action-camera Window { visibility = "none" }` (`gui/main/game.css.lua:59-70`; findings map-camera.md "Hiding
  the game UI": `toggleFreeCamera` hides the UI root).
- The way back is native: `FreeCamOptions` (mounted in GameUIProxyRoot, outside the hidden root, `game.tl:897`)
  pops the tool on `IA_BACK` / `IA_MENU_BACK` and on the C++ follow action's `stoppedFollowAction`; it also takes
  `IA_GAME_SCREENSHOT` (`takeScreenshot(2)`).
- From a mod: `game_react_globals.getDefaultToolStackApi()` (`gui/main/game_react_globals.tl:22-28`) gives
  `push` / `pop` / `getActiveTool` (`builtin.lua` ToolStack ~1340-1410; a pop of a tool not on the stack does
  nothing). `ug_require "::/gui/main/free_cam_options.tl"` should return the base module: the base requires one
  module as both "/gui/..." and "::/gui/..." (react.lua, which keeps global state, in ~130 files), so the cache is
  shared; a second instance would raise "Already registered a tool with name FreeCam" (`react.lua:584`), which
  Photo Mode catches. `push` runs inside a react state transform, so `getActiveTool` may show the tool a frame
  later.
- Unknown (TESTING.md G23): whether `setCameraData` / `getCameraData` still drive / report the view while the
  free camera is active (round 2 assumed not), and whether the free camera's mouse attachment turns the view.
  Photo Mode probes the first frames (read-back + `getEye` / `getCenter`) and falls back to hiding the UI root.
  Update 2026-10-13: the first probe fell back at once with the read-back equal (map-camera.md "The free camera
  ignores setCameraData", inferred); tours no longer use the free camera by default.
- Seen in game (session `2026-10-13_1755_session`, the footer's Camera mode twice): the push works from a button
  click (`camera mode: on (button)`, the mouse detached first) and Esc pops it natively, noticed through
  `getActiveTool` (`camera mode: left (button session)` 2-5 s later). Three sessions' tour probes all fell back,
  so Photo Mode round 9 removed camera mode from tours; only the footer button pushes the tool.
- **No base code calls `toggleFreeCameraMouseAttachment`** (or `isFreeCameraMouseAttached`; game files
  2026-10-14): the attachment is native input state the game manages itself. Photo Mode rounds 6-12 detached the
  mouse at every push (meant for tours); round 13 stopped (the player reported a hyper-sensitive camera "after some
  interaction", session `2026-10-14_0434_session`, cause not found).
- `Cannot leave cockpit as action does not match` (WARNING) follows a free camera exit by Esc: the native action
  has already ended when the tool's pop calls `leaveFollowCameraCockpit` (sessions `2026-10-13_0100` to
  `2026-10-14_0434`, 1-7 per session, also with no Photo Mode camera mode used, e.g. `2026-10-14_0229_sqrl-sqst`
  02:44:01-02:45:49, and after a cockpit the game ended itself, `2026-10-13_0325_session` 03:33:02). Harmless as
  far as seen (inferred).
- **Verified 2026-10-14** (session `2026-10-14_0633_session`, the first after round 13 stopped toggling the
  attachment): the user reported the footer's Free camera "works that time, actually uses free camera", i.e. it
  behaves as the game bar's own. A mod should push `FreeCamTool` and leave `toggleFreeCameraMouseAttachment` alone.

## The default selector is the default tool's action; a pushed tool takes its place (read from the game files 2026-10-13; effect in game unverified)

For Photo Mode round 10 (`mods/square_photo_mode/content/photo_mode/gui/pm_hud.lua` "tool"). User report, session
`2026-10-13_1915_session`: during tours and Aerials the hover outline and the money floaters ("$1,194") still
showed, with "Hide labels and hover" ticked and `hover off (automated camera move)` logged, i.e. after
`react.fireEvent(nil, "preventReactSelector", "")` had been fired several times.

- The hover, entity tooltips, click-to-select AND the HUD icon config (labels, `showIncome` / `showCosts` money
  floaters) are one ActionDescriptor built by `selector_react_util.makeDefaultSelectorCombinedFn`
  (`gui/main/selector_react_util.tl:194-240`). It is the default tool's action:
  `view_manager.tl` `EntityDetailsTool` (the tool stack's default tool) calls `setDefaultSelectorAction(ctx.setActionFn, ...)`
  in its push and again whenever it is un-shelved, which builds a NEW action function (so a fresh `useState(false)`:
  allowed, and a fresh read of the HUD filter). Actions render through `react.useAction(rendererComponent, ...)` in
  the tool stack's `ToolStackEntryWrap`; only the top entry is made the renderer's active owner
  (`builtin.lua` ToolStack ~1162-1195, `setActiveOwner(selfRef)` when `ctx.isTop`).
- So a fireEvent from a plugin may never reach the selector's `react.onEvent` (events fired with a nil source do
  reach other subtrees, e.g. `selectEntity` from the statistics window to view_manager, but the action renders in the
  renderer's action tree; unverified either way), and every pop of another tool (the free camera, a build menu)
  re-creates the selector allowed. The session matches both: prevent fired, hover stayed.
- A mod can push its own tool with no action on the default tool stack (`react.RegisterTool{ name, push, pop }`;
  `game_react_globals.getDefaultToolStackApi().push(tool, nil, {}, true)`), as the base free camera does
  (`free_cam_options.tl`). Then the default tool is shelved and our (empty) entry is the active owner: inferred, no
  hover, tooltips, click-to-select, and likely no HUD icons / floaters of the default selector at all (none of the
  ActionDescriptor applies). The normal camera's controls are native and stay. Another tool pushed without stacking
  calls the stack's `clear()`, which runs every non-default tool's `pop` handler (ours notices). The stack API also
  has `setActionsDisabled(true)` (base event `disableToolActions`, `game.tl:401`): "behaving as if actionFn would
  always be nil", a global switch with no owner; not used.
- Photo Mode round 10 pushes its tool `SquarePhotoModeView` while a tour, Wander or Orbit runs, while "Hide labels and
  hover" is on, and in its smooth camera; the events stay as a second path. To verify: TESTING.md W1.
- **Refuted for a tool with no action (session `2026-10-14_0055_session`)**: see "A pushed tool with no action leaves
  the hover and click-to-select on" below; round 11 gives the tool an empty action of its own.

## A pushed tool with no action leaves the hover and click-to-select on (from the game log 2026-10-14)

Photo Mode round 10's `SquarePhotoModeView` (the section above: `react.RegisterTool{ name, push = function() end, pop }`,
pushed with `getDefaultToolStackApi().push(def, nil, {}, true)`, no `setActionFn`) did NOT take the default
selector's place. Session `2026-10-14_0055_session`: `view tool on (smooth camera)` at 00:57:11, then at 00:58:09
`Selected entity 32615` (`view_manager.tl:621`, fired by the default selector's `onSelect`), an entity window
opened (`Open EntityDetailsTool for 32615 doCloseAll=true`), which cleared the stack (`view tool: removed by another
tool`); the same at 00:58:55 with the tool pushed for hidden labels at 00:58:41 (`Selected entity 38215`). The user
saw the white hover outline throughout ("Hide labels and hover still doesn't hide hover"). So an entry whose action
is nil leaves the renderer on the default tool's action (how exactly is C++: `ToolStackEntryWrap` makes the top
entry the active owner either way, `builtin.lua` ~1162-1195).

Also seen here: **the 3D view keeps its mouse input while the GameUIRoot is hidden** (the 00:58:09 click came with
Photo Mode's smooth camera hiding `react.game-ui-root`): the renderer's selector and the camera's mouse controls
are not cut off by the hidden root.

What the base does instead (read from the game files 2026-10-14, effect in game unverified): tools that switch the
map's hover off give their entry an EMPTY action, `ctx.setActionFn(function() return builtin.ActionDescriptor{
tool = "musicplayer", children = {} } end)` (`music_player.tl:18`; the calendar editor `game_bar_widgets.tl:769`,
`tool = "calendar"`; the pause menu `pause_menu.tl:337`, `tool = "pause"`). An action with no `builtin.Selector`
child has no hover highlight, no entity tooltip and no click-to-select; the default selector's action also carries
the `builtin.HudIconManagerConfig` (labels, money floaters), so an own action rebuilds it if the labels should stay
(as the base selector does from the HUD filter; its `makePreFilter` is local, the default lists
`selector_react_util.defaultHudIconFilter` / `defaultHudIconFilterTvCarrier` are exported). The descriptor's
`onBack` is the action's back: the construction menu aborts with it (`construction_react_util.tl:1416`) and the line
manager steps back (`line_util.tl:1178`); with the game's "Back With Right-Click" (`mouseEnableRightClickBack`,
on by default) that is a right click on the map (inferred: the C++ side isn't readable; whether a right DRAG, the
camera's turn, also counts is unknown). Photo Mode round 11 pushes its tool with such an action (pm_hud "tool"):
TESTING.md Z1-Z3.

## An empty action stops click-to-select but not the hover outline; `disableToolActions` is the base game's switch (in game 2026-10-14, the second part inferred)

- **Seen** (session `2026-10-14_0633_session`, Photo Mode round 13): with Photo Mode's tool on top of the default
  tool stack and its EMPTY action set (`view tool on (labels hidden): ... action set`; the previous section's
  `builtin.ActionDescriptor{ tool, children = { HudIconManagerConfig } }`, no `builtin.Selector`), two Aerials
  tours logged no `Selected entity` at all (click-to-select gone), yet the user saw the hover outline ("hover still
  active"). So the outline under the mouse is not drawn by a Selector of the active action; the renderer draws it
  whenever it has an action owner (inferred: the C++ RendererComponent isn't readable).
- **The base game's switch** (read from the game files): the cutscene task fires
  `api.gui.fireReactEvent("disableToolActions", true)` (after `"clearToolStack"`) before `playCutscene` and `false`
  when it ends (`base/content/mission/tasks/cutscene/cutscene.tl:38-39, :51`). `gui/main/game.tl:401` turns the
  event into the default tool stack's `setActionsDisabled(disable)`, which calls the renderer component's
  `setActiveOwnerOverride(nil)` (true) or `(false)` (`gui/main/builtin.lua` ToolStack ~1393; RendererComponent
  ~498-529: an override of nil means NO active owner, false means none of the override). So the renderer has no
  action at all while it is on, not an empty one: inferred no hover outline, tooltip, click or HUD icon config.
  The switch is global (whatever tool is on top), has no owner and no counter: whoever turns it on must turn it
  off on every exit path. Photo Mode round 14 used it during automated camera moves only (TESTING.md CC1).
- **Refuted for that use (session `2026-10-14_0658_session`)**: with the switch on, a click still selected and the
  outline stayed; the next section.

## `disableToolActions` outside a cutscene brings the default selector's clicks back (game log 2026-10-14; mechanism inferred)

- **Seen** (session `2026-10-14_0658_session`, Photo Mode round 14): `tool actions off (automated camera move)` at
  07:07:49 (`api.gui.fireReactEvent("disableToolActions", true)`, Photo Mode's empty-action tool on top), then at
  07:07:54 `Selected entity 26133 (stack = nil, dontBlink = false)`, `Open EntityDetailsTool for 26133
  doCloseAll=true`, and the entity window's push cleared the stack (Photo Mode's tool popped). `stack = nil` is the
  default selector's own `onSelect` (`gui/main/selector_react_util.tl:108`: `stack = (allowStacking == nil and
  isGamepadInputMode()) or allowStacking`); every other `selectEntity` source passes `true` / `false`. The user also
  still saw the hover outline. In `2026-10-14_0633_session` the empty action alone had stopped every click (three
  tours, no `Selected entity`).
- **Inferred mechanism**: `setActionsDisabled(true)` sets the renderer's active owner to nil
  (`builtin.lua` RendererComponent ~498-529), which behaves like round 10's tool with NO action (session
  `2026-10-14_0055_session`: clicks selected): the renderer falls back to another bound action, and the default
  tool's selector stays bound while shelved (every tool stack entry renders `react.useAction` in
  `ToolStackEntryWrap`, `builtin.lua` ~1162-1195; `view_manager.tl` `EntityDetailsTool.shelve` never clears its
  action). The base cutscene task can afford the switch because a playing cutscene is a native camera action
  (`action-camera`; the binary's `CameraAction.cpp` strings name `IA_MENU`, `IA_BACK`, `OnSkipCutscene`) that takes
  the map's input itself (inferred).
- **Use instead** (read from the game files 2026-10-14, effect in game untested: Photo Mode TESTING.md CD1-CD2):
  - `api.gui.fireReactEvent("setSelectorEntityFilter", { [id] = true })` (`gui/main/game.tl:160`; the campaign's
    `mission/mission_sim.script.tl:1225` fires it): a non-empty filter makes the default selector's `filter` refuse
    every entity not in it (`selector_react_util.tl:136-139`), so with only an id no entity has (negative) it
    hovers and selects nothing wherever it is bound. `{}` is the free game's own (game.tl's initial value) and turns
    it back. The filter itself can't be read from a mod (game.tl keeps it in its game context), so leave it alone in
    a campaign mission (`api.gui.mission.getMission()` not empty).
  - `api.gui.fireReactEvent("setDisableFeatures", t)` (`game.tl:166`, replaces the table) with
    `OpenEntityWindow = true`: a selection opens no window (`view_manager.tl:623`), so it can't clear the tool stack.
    `game_react_globals.getDisableFeatures()` reads the current table: send a copy plus the key, then the copy back.
  - Keep an empty action of one's own on top (the 0633 result: no clicks); push it again if something clears it.

## What camera input a mod can read (read from the API definitions 2026-10-13)

For Photo Mode round 10's smooth camera:

- The camera controls (pan, rotate, tilt, zoom, edge scroll, `IA_CAMERA_PAN`, `IA_CAMERA_ROTATE_X`,
  `IA_CAMERA_TILT`, `IA_CAMERA_ZOOM_IN/OUT`) are handled natively; the base only lists these names for prompt hints
  (`layers_button_ridge.tl:65`, `context_helper_react.tl:887`). No API exposes the input itself. What a mod sees is
  its effect: `getCameraData` after the game applied it to the view set last frame (the difference = the player's
  step this frame), which is what Photo Mode's smooth camera reads.
- The mouse: `api.gui.mouse.getTerrainPosition()` / `hasTerrainPosition()` (the terrain point under the cursor, any
  time), and `react.onMouseEvent` (`Gui.Mouse.Event`: button, x, y, xrel, yrel) only for events over a component of
  our own. A full-screen component to catch mouse moves would also catch the clicks and drags the camera needs (and
  a mouse-transparent one gets no events), so a free look by plain mouse movement, without a button held, is not
  available on the normal camera; the free camera's mouse attachment (`toggleFreeCameraMouseAttachment`) is the
  game's own and only works for the free camera, which mods can't move.
- `useInputAction` with a camera action's name inside a mod's subtree would compete with the game's handling (and
  is hidden with the UI root); not tried.

## A tool action's mouse cursor and map clicks (read from the game files 2026-10-14, effect in game unverified)

For Photo Mode round 12 (`pm_hud.lua` "tool": a hidden cursor during tours, click-to-glide in the smooth camera).

- `builtin.ActionDescriptor` takes a `mouseCursor` integer besides the fields of its typedef
  (`scripts/builtin.d.tl` ActionDescriptorParam): the construction menu sets it from a state
  (`construction_react_util.tl:1420`), the line tools from their context (`line_util.tl:1183`). The ids are
  `gui_react_util.getMouseCursorInteger` (`gui/main/gui_react_util.tl:14-45`): Default 0, ..., Camera 1004,
  None 1009, Grab 1010, ... Whether "None" hides the cursor over the map is unverified (Photo Mode TESTING.md CA2).
- A click on the map reaches an action through its `builtin.Selector` child: `onSelect(entity, indices, details)`
  (World details carry `pos` when `details.data.kind == api.gui.SelectionDetails.Type.World`,
  `selector_react_util.tl:111`), `onHover`, `filter(entity)` (which entities hover / select), and
  `onSelectNothing` (used by the default selector, not in the typedef). Which callback a click on bare terrain
  fires when `filter` accepts nothing is unknown; `api.gui.mouse.getTerrainPosition()` gives the point under the
  cursor at any time. `onProcessMouseEvent` is in the typedef but no base code sets it.
- The tool stack also has `setActionsDisabled` (event `disableToolActions`, fired with `api.gui.fireReactEvent` by
  the base cutscene task): the renderer gets no action at all while it is on.

## CSS class names: letters, digits and dashes only (user screenshot 2026-10-13; parser read from the game files)

Smart Lanes rev 5 styled its toolbar info block with rules under `R::Component!sqrl_tool_info` (the param
`group` id, which the construction menu adds as a class of the group's Component, `construction.tl:1344-1352`).
In game none of the 6 rules applied: the block stayed a grey disabled button with dark centred text (user
screenshot 2026-10-13, session `2026-10-13_2037_sqrl-sqsg`; no log line about the stylesheet).

- Cause: the base selector parser (`gui/main/stylesheetutil.lua` `add`) reads a class as `![%a%d%-]+`, an id as
  `#[%a%d%-%.]+` and an element as `[%a%d%-]+` (with `::` parts). An underscore ends the name silently:
  `!sqrl_tool_info` became class `sqrl`, which no node had. No error, no log line.
- Rule: class names (and ids) used in our stylesheets take dashes, never underscores. A `meta.class` or param
  `group` that a rule targets follows the same rule. Offline guard in `tests/square_smart_lanes/test_tool.lua`.
  The fix (`sqrl-tool-info`) works in game (user screenshot 2026-10-13, 1:40 PM): plain left-aligned text.

## StyleSheet properties can't be read back from Lua (crash 2026-10-14)

`api.gui.StyleSheet` values (from `StyleSheet.new()` or `styleutil.makeStyle`) are write-only from Lua: reading a
property back (`st.color`) throws "The class is not registered in LuaBridge" (`Unregistered class:
N2UI13StylePropertyI6CVec4fEE`, i.e. `UI::StyleProperty<CVec4f>`), a critical Lua error that ends the game
(session `2026-10-14_0640_sqrl-sqsg`, Problem Radar `radar_inline.tl` reusing a colour sheet's `.color`). Keep the
raw values (colour tables) next to the sheets and build new sheets from those. Offline tests: make stub sheets
raise on a read (`tests/square_problem_radar/test_inline.lua`).

## `builtin.Slider`: integer values, a change per value passed, no release callback (read from the game files 2026-10-14)

- A C++ builtin (`gui/main/builtin.lua:68` `DeclareBuiltinWithUserdata("Slider")`, which sets the style class
  `horizontal` or `vertical` from `horizontal`). Params (base tealdef `scripts/builtin.d.tl` `SliderParam`):
  `min`, `max`, `step` (keys / gamepad), `pageStep`, `value`, `initialValue` (integers), `horizontal`,
  `drawGroove`, `withTicks`, `disableGamepadNavigation`, `stepsForDynamicKeyRepeatSpeed`, `onValueChange(integer)`.
  No release, drag-start or drag-end callback. Base CSS `Slider!horizontal`: `size = { -1, 16 }`, `gravity = { -1,
  0.5 }` (it takes the row's spare width), a 12 px handle; `withTicks` shows ticks on hover only.
- `onValueChange` fires for each value the handle passes while dragged: the base calendar's Weather & Time panel
  sends a `makeGameSetTimeOfDayCmd` (plus two events) and its cloud slider a `setEnvironment` on every call, with
  no throttle (`game_bar/game_bar_widgets.tl` ~404-428, ~506-516; time 1440 steps over 0..86400 s through
  `SliderWithLegend`, which maps any range onto 0..numSteps with step 1 % and pageStep 10 %, ~26-58).
- The base pattern for a live slider whose writes are costly (`gui/main/script_param_util.tl`
  `ScriptParamSliderAndText` ~287-345, the construction menu's sliders): the slider in its own recipe with a
  `react.useState` for the pending value (a move re-renders that recipe only), `react.onMouseEvent` catching
  `evt.button == 0` and `api.gui.mouse.Event.Type.Released` on the recipe to send the coalesced value once, and
  the value text a separate recipe updated through `react.provideApi` / a node ref. Photo Mode's Light tab sliders
  follow it (`gui/pm_slider.lua`: own state, throttled quiet writes, a final set at release or after 400 ms).
- Whether the slider stays controlled by `value` when its recipe re-renders mid-drag (the base sets the pending
  value as `value` while dragging, so inferred yes), and whether an inline `meta.styleSheet` size reaches a
  Slider, are not seen in game (Photo Mode TESTING.md LS4).

## Native cards and button padding set inline (verified in game 2026-10-14)

The base entity-window card renders from an inline `meta.styleSheet`: `api.gui.NinePatch.new()` with
`fileName = "::/gui/entity_window/design/card_surface.tga"`, `horizontal` / `vertical = { 0, 6, 26, 32 }` as
`backgroundImage1` (tinted with `backgroundColor1`), the same for `card_contour.tga` as `borderImage` (tinted with
`borderColor`), plus padding and size: rounded surface and contour as in the base windows, zero stylesheet rules
(Problem Radar fleet window, user screenshot, session `2026-10-14_0753_sqrl-sqsg`, no fallback warning). Pattern from
base `line_vehicle_mgmt/vehicle_react_util.tl:95-105`; code `mods/square_problem_radar/content/radar/gui/radar_inline.tl`
`cardSheet`. Base `primary` / `secondary` Buttons with only an inline `padding` keep their base look (same window).
The same session confirmed the shared leader-marker stylesheet block (Smart Lanes / Bulk Bulldozer "TOOL INFO STYLE":
one "added by", one "skipped in") and the user's full mod set loading a new game at ≈182 mod rules.

## Nested TabWidgets: the base has them, each with rules of its own (read from the game files 2026-10-14, not tried in a mod)

- The base puts a `builtin.TabWidget` inside another's `TabWidgetChild` in three places: the construction menu (the
  category tabs' items are `ConstructionCategory` recipes that return a TabWidget of their own, tag
  `react.construction.menu.innerTabWidget`, `gui/construction/construction.tl` ~2967-3015 inside the outer
  `react.construction.menu.tabwidget` ~4960), the town window (the `town-tabwidget` Town / Editor tabs hold
  `TownInformationTabs`, a TabWidget of Supplies, Bonuses, ... `gui/entity_window/town/town.tl` ~761-810 and
  ~1295-1330) and the debug view (`TabWidget!subtabs`, `gui/main/debug.css.lua` ~138-185).
- Each inner one is styled by rules aimed at it: `R::ConstructionCategory TabWidget::ContentLayout!north
  TabWidget::Content` (`construction.css.lua:312`), `R::TownInformationTabs TabWidget`, `TabWidget::Indicator`,
  `TabWidget::Content` (`entity_window.css.lua:632-684`), `R::TownWindowContent TabWidget!town-tabwidget > BoxLayout >
  TabWidget::ContentLayout > TabWidget::Content` (`:576`, a child selector so the outer rule skips the inner one).
  Unstyled, the base `TabWidget::Content` padding (8 px, `builtin.css.lua` ~969-983) and frame apply at each level:
  an inner page is ~16 px narrower and framed twice (inferred). So a nested TabWidget in a mod works, but looks right
  only with 2-4 rules of its own (the shared ~200-rule budget, `findings/scripting.md`) and another indicator row
  (5 short text labels at most in a ~424 px box, `docs/ui-guide.md`). Photo Mode round 16 put its saved setups in a
  section of the Settings tab instead.

## `AppConfig.mainMenuState` holds nested plain tables; the base copies the whole table to change a key (read from the game files 2026-10-14)

**Superseded for mod data (2026-10-20):** writing a mod key here needs `api.util.saveAppConfig()`, which the upload
review rejects; mods store data with `api.gui.game.setGuiSaveData` instead (`findings/publishing.md`). The
observations below still describe the base game.

- `mainMenuState : table` (`api/tealdef/api/type.d.tl:2886`). The base keeps nested tables there (`newGameState`,
  `mapGenParamsState`, `activeModsState`, `activeModsParamsState`: `gui/menu/new_game_react_util.tl` ~85-175) and
  writes by copying the whole table, changing its key and setting it back (`gui/menu/new_game_or_map_settings_page.tl`
  ~534-539, ~963-966). A mod does the same with a key of its own (Photo Mode: `square_photo_mode` for the high
  graphics marker, `square_photo_mode_setups` for the saved setups, round 16; one key per purpose, because the marker
  is cleared as a whole). It is the game's settings.lua, not a save: nothing there reaches a savegame, so removing a
  mod leaves saves alone. No size limit is documented; Photo Mode caps its setups at 30 (~10 KB).


## Lists in inline cards, the base info hint and inline widths in a mod window (in game 2026-10-14)

User screenshots of Problem Radar's main window (session `2026-10-14_0842_session`, no `[ProblemRadar]` warning):

- Rows as `builtin.Component`s with an inline fixed `size` and padding, odd rows an inline `backgroundColor`
  (NeutralLightest at 0.05), inside one inline native card (the card nine-patch above): render as a zebra list.
- `content_card.makeInfoHint(text, true)` (base `gui/main/content_card.tl`) works in a mod's own window: the blue
  info bubble with its icon, styled by the base's global `content_card.css.lua` rules (zero mod rules).
- The base `vertical-spacer` class on two side-by-side column Components, each ending in a
  `Component{ meta = { class = "vertical-spacer" } }`, top-aligns the columns (the shorter one no longer centred).
- An inline `meta.styleSheet` with `size = { 72, -1 }` applies to a `builtin.DoubleSpinBox`.
- **An inline `size` on a TextView does not clip its text** (inferred from the screenshot): a line name longer than
  its 280 px cell ran on into the next cell, with no gap before the detail text ("…-IC-1Earns 40% of costs"). The
  earlier 170 px inline name cell hid this because the column after it was usually empty. Long texts need a
  `minSize = maxSize` + `textAutoWrap` rule. Also, a settings row of label (wrap rule, min = max 300) · spin box ·
  range text had its spin box at x positions ~10 px apart from row to row: fixed-width Component boxes around the
  cells are the fix (to verify, round 2).

## Wrapping a base recipe: `react-replacement-config`; what stays visible in a cutscene (read from the game files 2026-10-14; the wrapper untested in game)

- **The official mechanism**: a generic resource `{ type = "react-replacement-config", data = { filePath =
  "<mod>::/<path>.script", doReplaceFn = "<fn>", order = n } }` (a `.res.lua`); at bootstrap the game calls every
  config's function with `{ ReplaceRecipe = function(original, replacement) }` before any recipe runs, then forbids
  replacing (`base/content/gui/main/bootstrap_game.tl`, `react.lua` `GloballyReplaceRecipeBeforeInitInternal`). The
  replacement calls `react.CallOriginalRecipe(original, params)` inside its own body to render the original (its
  hooks become the replacement's; not allowed for builtins). The campaign does exactly this
  (`urbangames_campaign_mission_01` `hud_replacement.res.lua` / `.script.tl`: HudIconMasterGame). Only one mod can
  own a recipe's replacement (the last config wins; each calls the ORIGINAL, so they don't chain).
- **What a cutscene leaves on screen**: it hides `react.game-ui-root` (every mod plugin: `MainModButtonArea` and the
  `ModEntryPointExtension` host `EntryPoints` both live inside it, `game.tl` "internal-hidden") and
  `!action-camera Window` hides any Window (`game.css.lua`). GameUIProxyRoot's other children stay: the speed helper,
  `FreeCamOptions` (top right, `h = 1, v = 0`, an empty BoxLayout with the Back / Menu back / F9 screenshot input
  actions), the dialogue overlay and the CalloutContainer (`game.tl:866-918`). No extension point sits there; the
  CalloutContainer renders any recipe (the celebration callout has a clickable Button) but its api is reached only
  through the game context (`gameCtx.calloutContainerRef`), which no public getter hands a mod
  (`game_react_globals.tl` exposes the window container, renderer, tool stack and disable features only).
- So a mod shows controls during a cutscene by wrapping `FreeCamOptions` (whose params carry `getGameContext`).
  Photo Mode round 18 does (`gui/pm_bar.script.lua`: the original plus a small bar while its cutscene plays).
  Open (TESTING.md R18-3): whether the bar shows, and whether the mouse reaches it while the cutscene's camera
  action holds the input. The F9 input action on FreeCamOptions does reach it during a cutscene
  (environment.md "The game's screenshot key works during a cutscene").

## The base button contour: a 9-slice with 9 px corners; small buttons use the compact one; the base arrows (game files 2026-10-14; the compact fix verified in game)

- Every `Button` / `ToggleButton` draws `::/gui/builtin/button/default_contour.tga` (and `default_surface.tga`) as a
  9-slice `{ 0, 9, 21, 30 }` both ways (`builtin.css.lua:140-160`): a 30 px texture (60 px `@2x`) whose rounded
  corner arc runs ~7 px in from each side. `Button!secondary` only colours it (`default.css.lua:104`).
- A button barely larger than the two corners (a one-character text with compact padding: Photo Mode's "<" / ">"
  at about 19-24 px) leaves the stretched straight middle of the side edges at 0-4 px, so the two arcs meet there:
  the "little divot" in the middle of the left and right edges (user screenshot 2026-10-14; the cause inferred from
  the texture and the sizes, not measured on screen).
- The base's own small buttons use `compact_contour.tga` / `compact_surface.tga` (12 px, 24 px `@2x`, slices
  `{ 0, 5, 7, 12 }`): `DoubleSpinBox Button!plusminus` (`builtin.css.lua:1249`), the town window's name buttons
  (`town_react_util.css.lua:393`). The base arrows are icons, not text: `::/gui/builtin/spinbox/arrow_left.tga` /
  `arrow_right.tga` (a filled triangle, 24 px; the DoubleSpinBox's +/- buttons draw them at 8 px), and
  `combobox/arrow_*`, `scrollview/arrow_*` the same shape.
- Photo Mode round 18: step buttons are its compact icon buttons with the spin box arrows (16 px icon + 4 / 6 px
  padding = 24 x 28 px), no new rule. The user still saw a small notch on the left edge (screenshot 2026-10-14,
  2019 session; cause not measured: the 9 px corners are still most of a 24 px high button). Round 19: the arrow
  buttons carry the compact contour INLINE (`meta.styleSheet` with `borderImage` / `backgroundImage1` =
  `api.gui.NinePatch` of `compact_contour` / `compact_surface`, slices `{ 0, 5, 7, 12 }`, as the base
  TextInputField; the same inline route as the entity-window cards above), the `secondary` class still colouring
  it. **Verified 2026-10-14** (user, after the `2026-10-14_2150_r19-test` session: "arrow dent is gone"): the
  notch was the 30 px default contour on a button under ~30 px; the compact contour inline removes it.
- An inline `StyleSheet` (api `gui.d.tl` record StyleSheet) has no `margin`: only colours, background images,
  `borderWidth` / `borderColor` / `borderImage`, `size`, `padding`, `fontSize`, `anchorPoint`. So an inline sheet
  can't trim a base element's outer spacing (Photo Mode round 20: the TabWidget indicator's 18 + 18 px padding
  stays; eight icon tabs fit 424 px only with 16 px icons, `docs/ui-guide.md` "Window").

## Construction toolbar params: "Hidden", the CheckBox, no smaller button (read from the game files 2026-10-14, not verified in game)

Smart Lanes rev 8 (user, 2026-10-14: buttons that would change nothing should vanish, "Lights only" should be a
checkbox, is there a smaller button?). All from `base/content/gui/construction/construction.tl`, `construction.css.lua`
and `gui/main/script_param_util.tl`; the Smart Lanes tool relies on it, not yet seen in game (TESTING.md "Hidden
buttons", "SH" 4).

- **`checkEnabledFn` results:** `"Enabled" | "Hidden" | "Disabled" | "InputActionOnly"` (`construction_menu.d.tl:69-74`).
  The menu calls every param's function each step (heartbeat `onStep` 1901-1925 -> `updateDisabledParams` 1584-1597,
  with `getAllParams()`) and re-renders the bar only when the list of results changed (`deepEquals`). The base street
  builder hides its bridge / tunnel sliders this way (`construction_react_util.tl:1676-1786`).
- **Hidden params leave nothing behind.** The bottom bar (ConstructionParamsContent, 2020-2072) skips a "Hidden" or
  "InputActionOnly" param *before* grouping. A group is a run of consecutive shown params with the same `group` and the
  same `not hideLabel`; `flushGroup` (2023-2046) draws the separator (`ImageView!param-group-separator`, the card heading
  decor, 280 px wide, `construction.css.lua:772-775`) before a group only when the previously flushed group had a shown
  param. So a group whose params are all hidden adds no row, gap or separator. Corner case: two runs of the same group
  id around an all-hidden group of another id join into one row. The side-panel variant (1329-1376) does the same.
  "Disabled" keeps the param drawn with `enabled = false` (grey, clicks ignored).
- **Hidden values are left out of the current values** (`getParamsForValidIndices`, 1516-1525): the action and a custom
  recipe's `getCurrentParams()` don't see them; `getAllParams()` (4727-4744, what `checkEnabledFn` gets) fills missing
  keys with the param's default. So a `checkEnabledFn` reads a hidden param as its default, and on the step a param turns
  visible the others still see that default: keep such state in the mod (from `onChangeFn`), not in the params table.
- **`hideLabel` splits groups:** a param with a label and one without never share a row (2052-2057), even with one `group`.
- **CheckBox params:** `ScriptParamType.CheckBox` with `values = { _("No"), _("Yes") }`: value 1 = unchecked, 2 = checked
  (`script_param_util.tl:515-530`, the CheckBox gets `currentValue - 1`). In the bar its name is the CheckBox's own label
  (vertical = nil for `hideLabel` or the default display mode, `construction.tl:1115-1121`); gamepad mode shows it as a
  ComboBox of the two values (1040-1042). Base example: "Follow Terrain" (`construction_react_util.tl:1883-1897`).
  `onChangeFn(newValue)` runs on every click (1866-1898).
- **A CheckBox param's shown value can be set by the mod** (read 2026-10-14, not verified in game; Smart Lanes "Keep
  timing adjusted" used it until 2026-10-15, superseded by twin Yes / No toggle params whose defaults are the two
  states, shown one at a time from `checkEnabledFn`: right before any click, since `checkEnabledFn` gets no params api;
  the same stored-value sync keeps both twins right after a click; `docs/ui-guide.md` "Construction toolbar",
  unverified in game: TESTING.md KA v4 1-2). Applies to a two-value Button param (the base Yes / No toggle,
  `script_param_util.tl:396-450`, `selected` from the stored value) as to a CheckBox: ConstructionParam re-reads `getStoredValues(category)[param.key]` every step and
  re-renders when it changed (`construction.tl:1044-1051`, `1081-1084`); `getStoredValues` returns the menu's own table
  (`refStoredParams:get()[category]`, 1952-1954), and the params api with `getStoredValues` / `getCategory` is
  `onChangeFn`'s second argument (`param.onChangeFn(newValue, refSelf:get():getApi(), oldValue)`, 1885). So after the
  first click a mod can write `stored[key] = 1 | 2` from its `checkEnabledFn` to show another state. Before the first
  click it has no api (the category's table may not even exist), and `currentParams[index].value` (what
  `getAllParams` / `checkEnabledFn` see) is not changed by such a write.
- **Stored values and their resets:** a param's value is kept per menu category while the menu lives (`refStoredParams`).
  `resetOnMenuClose` clears it when the menu closes (`constructionMenuActive` `{ active = false }`, fired with
  `react.fireEvent` at 5066 and heard by any recipe; 1859-1864), `resetOnDefinitionChange` when another entry is chosen
  (`setActiveDefinition` 1836-1857), `resetOnCategoryChange` with the category. No `onChangeFn` call for these resets.
- **No smaller toolbar button.** Every Button param in the bar is a base `ToggleButton` with the classes
  `right-parameters, ui-type-<n>` (`script_param_util.tl:396-466`); `makeCompactButtonFn` only supplies its content.
  The bottom bar's rules give it 4 px padding (`construction.css.lua:814-816`), at least 32 x 32 px (817-819) and a
  50 x 24 px text box (820-823). There is no size variant: `ScriptParamDisplayMode.Compact` turns the param into a
  callout button that opens a popover with the real control (`script_param_util.tl:363-389`), not a smaller button; the
  base `primary` / `secondary` classes are `Button` classes (`default.css.lua:77-117`), and a param can't add a class to
  its ToggleButton. `IconButton` is the same ToggleButton with an image. A smaller look would need class rules on the
  group's Component (the rule budget). The base tools' own toolbar buttons (Snapping, Symmetry, Catenary) are this same
  button.
  **Update 2026-10-16 (read from the game files, not verified in game):** a one-value Button param with `numbers = { 1 }`
  is drawn as a base `ToggleButtonGroup` with one button instead (`script_param_util.tl:440`: a group when
  `numChoices > 1 or numbers ~= nil`), the widget of a two-value Yes / No toggle. The 32 x 32 px minimum
  (`construction.css.lua:817-819`) targets `ToggleButton!right-parameters`, and in a group that class is on the group,
  so the button is as tall as its content plus the 4 px padding (814-816; a labelled toggle's 0 px, 804-807, needs the
  label wrap). The value stays `numbers[defaultIndex]` = 1 (`construction.tl:958-964`), and a click on the group's
  one (selected) button still calls `onValueChange` (`builtin.lua` ToggleButtonGroup: every ToggleButton click maps to
  its index), so `onChangeFn` runs on every click. Smart Lanes' action buttons use it (TESTING.md "Toolbar rows").
- **A param's tooltip is fixed; its button content's tooltip is not** (read 2026-10-14, not verified in game; Smart
  Lanes rev 8 v2). `ConstructionParam` (`construction.tl:1000-1200`) reads `param.tooltip` into a ref
  (`refTooltip`, 1064) and sets it again only when the param's ParamForUi (uiType, name, values, tooltips,
  makeCompactButtonFn, ...) changes by `deepEquals` (1074-1079); a ref does not re-render. The tooltip sits on the
  outer `Component!construction-menu-param` (1143), which also gets `enabled = false` for "Disabled" (2061). So a
  param's own tooltip can't say why it is grayed now. The button's content from `makeCompactButtonFn` is any recipe
  (`script_param_util.tl:400-402` for the bar's ToggleButton, 177-200 for the compact callout), so a recipe there can
  set its TextView's `meta.tooltip` per frame. The base shows tooltips on disabled widgets themselves
  (`menu/mod_manager_react_util.tl:5943-5947`: `enabled = installed, tooltip = not installed and _("Mod is missing.")`);
  whether a tooltip on a child of a disabled toolbar button shows is the open point (Smart Lanes TESTING.md
  "Toolbar rows"). **In game (user 2026-10-17, Smart Lanes rev 9, Re-time grayed while another junction measured): no
  tooltip showed on the grayed button** (no hover evidence in the log; the user's report). Smart Lanes now also puts
  the reason in its status text (`C.grayLines`).

## TextView: "\n" breaks a line; no wrap without a textAutoWrap rule (code reading 2026-10-16)
- A base `builtin.TextView` shows `"\n"` in its text as a new line (`debug_panel/make_entity_debug_panel.tl:486`
  builds its text with "\n"). Wrapping to a width needs a stylesheet rule (`textAutoWrap = true` plus a size, as
  `popover_react_util.css.lua:46` for the base dialogs); an inline `api.gui.StyleSheet` has no `textAutoWrap`
  (findings scripting.md). A long TextView line in Smart Lanes' welcome window (class "popover, dialog") was cut off
  at the window's edge in game (user screenshot 2026-10-16); the mod now breaks its lines with "\n" in code
  (`sl_allmode.lua` `wrapLine`). Not yet seen in game after the change.

## Bars in an entity-window card: ProgressDisplay is thick, the thin bars are recipe-bound (user screenshot 2026-10-17; game files)

Organic Towns' town card, first native pass (user screenshots 2026-10-17, collapsed and expanded card):

- `entity_window_util.ProgressDisplay` inside a town-window card draws a bar about two text lines tall, far heavier
  than the Town Level bar at the top of the same window: the rule `R::EntityWindowContent R::ProgressDisplay
  ProgressBar` sets `size = { -1, 25 }` (`entity_window.css.lua:1022-1025`). Its `extraValue` (the second bar
  behind, `entity_window_util.tl:1810-1840`, lighter `extra-progress` colour) only shows as a slightly lighter tip
  when it is above `value` (41 → 45 barely visible) and not at all when below (46 → 43): no use as a target marker.
- The base thin bars are styled under their own recipe names only: `R::TownLevelWidget ProgressBar` (8 px, TownGrowth
  fill, BaseVeryLight at VeryLow behind, its own 4 px mask slices: `:582-597`), `R::PersonCapacityWidget ProgressBar`
  (10 px, `:846-852`). A plain `builtin.ProgressBar` elsewhere gets the builtin 20 px look (`builtin.css.lua:1569-1584`,
  mask slices 5 px). No class gives a thin bar.
- The base marker on a bar is `thresholds` (`builtin.d.tl:1013-1018`): `ProgressBar > Threshold` is a 1 px line,
  NeutralLightest at Medium, `!reached` NeutralDarkest at Medium once the fill passes it (`builtin.css.lua:1600-1606`).
- **Confirmed in game (user screenshots 2026-10-17 ~22:40Z):** a `builtin.ProgressBar` with an inline sheet
  `size = { -1, 10 }` (10 px: an inline StyleSheet has no `mask`, and the builtin mask's 5 px corners fit 10), the
  fill colour and the Town Level background renders thin and coloured in a card, and the `thresholds` mark shows on
  it both above and below the fill. Inline `size = { 1, h }` spacer Components give the gaps.

## Entity-window plugins: reading a game script's saved state, the hanging collapse arrow (game 2026-10-17)

- **A `::TownEowExtensionPoint` plugin reads our game script's saved state** with
  `getEntityForGameScript(name)` → `getComponent(e, GAME_SCRIPT).state_native:findPath / :find` (keys
  `frames` / `rc` / `ui` / `no`), polled by `useStepStateTimer` every 2 s: Organic Towns' card logged
  `CARD event=read` for 10 towns with the saved values, no errors (live log 2026-10-17 22:23-22:49Z; not archived,
  overwritten by the next game start; the lines were read before that). Values the game script writes later (the
  `ui` summary, ~30 s batches) show on the next poll.
- **The ContentCard collapse arrow hangs over the bottom border by design**, at a fixed x (`content_card.tl:318-337`,
  `arrow-component` margin 358 "aligned with center of checkmark for industry boosters", `content_card.css.lua:139`):
  the base Town Level card shows the same. A card's permanent part with a right-aligned value (key/value row) puts
  the arrow under that value, as the Line "Transported" card. Not a mod bug; changing it needs a global rule.
- **A custom notification type posted through the base "Notifications" game script** (`add` event, Problem Radar's
  pattern) was sent once per new Works / district town (4 `CARD event=notify` in the same run) and the user saw no
  problems; icon look and survival over a reload not yet checked.

## Construction menu custom actions: `isActive` is not "this tool is selected" (game files + log 2026-10-17)

- **Every entry of the shown construction-menu tab mounts its `customAction.recipe`**, selected or not
  (`construction.tl:806-830` renders a `ConstructionDefinitionItem` per entry; each mounts its recipe at 410-424).
  `isActive` is `actionPresentState`, which starts as `not isGamepadInputMode()` and only drops in gamepad mode
  (`abortAction`, 315-327). In mouse mode it stays true for every entry while the tab is visible.
- **Evidence:** session `2026-10-17_2159_sqrl-sqsg`: with Smart Lanes selected in Road → Tools, Bulk Bulldozer
  logged "tool activated", then "world layer unmounted", then kept taking brush samples every frame.
- **The signal that an entry is the selected tool is its world layer (`setActionFn`'s fn) being mounted:**
  the menu renders only the active definition's bound fn (`propagateActionFn`, 4489-4501). Track it with
  `react.onMount` / `onUnmount` inside that fn (the base does the same, `construction_react_util.tl:1355-1366`)
  and gate per-frame work in the recipe's `onStep` on it (Bulk Bulldozer `refLayerUp`).

## Decorating a cell inside a file-local base recipe; GUI hosts keep ticking while paused (verified in game 2026-10-18)

DEV probe `square_lmp_util_probe` (`plans/square_line_manager_plus/UTIL_PROBE.md`), live session 2026-10-18 (the game
was still running when this was written, so the log was not yet archived; it starts after `2026-10-18_1848_session`;
lines `[LMPUTILPROBE]`), build 40422, a save with 49 player lines, Line Manager Plus active. Target: the Utilization
cell of the Line Manager's bottom statistics row (`LineStatisticDetails`, base `manager_window.tl:3830`, a
file-local recipe that isn't exported).

- **No `debug` library in the GUI Lua state**: `debug.getupvalue` is missing (`Q1 env debug=false`), so a function's
  upvalues (e.g. react.lua's local `recipeFnToRecipeName`, a getter's `params`) can't be read.
- **The global `_react` exposes `recipes`, `recipeReplace` and `originalRecipeFn`** (tables keyed by recipe id; the id
  of the rendering recipe from `react.getCurrentRecipeId()`, 321 here). Wrapping `_react.recipes[id]` (the render
  function) and setting `_react.recipeReplace[id]` both took effect late, after GUI start (`Q1 install T1 render-wrap
  OK via late:T3`, `T2 replace (late, _react.recipeReplace) OK`; renders and creates counted). Both rely on react
  internals: not used in a published mod.
- **`api.util.toStringPercentPrecision` is a table, not a Lua function** (`toStringPercentPrecision is table`), so it
  can't be wrapped by type check; the base calls it, so it is callable. Line Manager Plus calls it through `pcall` and
  falls back to its own `%d%%` format.
- **A one-shot `builtin.TextView` swap armed from a wrapped `engine_react_util.useStepStateTimer` decorates the
  cell.** The module field is looked up at call time. Inside `LineStatisticDetails` (`react.getCurrentRecipeName()`)
  the swap, armed at one call and dropped at the next, catches the value TextView built between the coverage getter
  and the frequency getter (`Q1 MARKER rendered by T3`; `T3miss=0`, `swapMatch` = renders: 17-98 per 10 s with the
  window open, one line and multi-select). Returning a horizontal `BoxLayout { value, extra }` in place of the
  TextView renders. Without `debug` the getter's line can't be read (`line nil`): Line Manager Plus calls each getter
  once while `statistics_react_util.calculateCargoColumnDataForLine` (wrapped) records its argument; only the
  coverage getter calls it. In "loose" mode (arm on every call) the swap stayed in place after the last call of a
  render (`builtinTextViewSwappedNow=true` at every report): arm only for the getter wanted and also restore from a
  host tick.
- **Both always-mounted hosts tick with the Line Manager closed**: empty plugins at `::MainModButtonAreaExtension`
  and `::ModEntryPointExtension` both got `onStep` (~280-890 calls per 10 s) and `onStepTimer(fn, 1.0)` (10-12 per
  10 s) with the window closed for over a minute (`Q2 beat ... lmSeenAgoS=64`).
- **They keep ticking while paused**: with `GAME_SPEED.speedup` 0, `GAME_TIME.gameTime` stood at 49651000 for
  minutes while both hosts' `onStep` (349-891 per 10 s) and `onStepTimer` (10-11 per 10 s) ran at their usual rate
  (log lines ~2756-2794). A sampler that should stop on pause must gate on the game time having advanced.
- **Line capacity sampling cost**: `api.engine.util.line.getLineCapacityUsages(line, false)` summed per line (an array
  indexed by cargo type id + 1, as `cargo_util.tl:894`) for all 49 lines: 470-772 us per pass from `onStepTimer`
  (9.5-15.7 us per line, max 106 us for one line, `getLinesForPlayer` 1-5 us) and 449 / 724 us from `onStep` (Main
  Thread), 12 passes at speed 4, no errors.

## HUD icon scripts share the GUI Lua state; chained makeDefaultSelector proxies (game log 2026-10-20 04:22Z, live session)

Industry Production Label "Show only on hover": a `::ModEntryPointExtension` script wrapped
`selector_react_util.makeDefaultSelector` and set `hover.installed = true` on a module table; the first
`hudIconScript` recipe (thread "Main Pool 1") read the same table: `hover hook in the HUD state: true`. So module
tables written from a mod's GUI entry point are visible to its HUD icon scripts (same Lua state, other threads).

Install order that session: Line Manager Plus, Industry Production Label, Passenger Destinations (outermost).
Each wrapper hands the base (or the next wrapper in) a proxy ref, and Passenger Destinations' proxy has only
`set` / `get`: ours called `inner:hasExpired()` and raised on every hover ("attempt to call method 'hasExpired'",
~100 errors in seconds). A proxy must not assume the ref it got is a real react ref: call `hasExpired` only when
present, and give its own proxy `set`, `get` and `hasExpired`.

Same session, user report: the hovered industry stayed "hovered" until the mouse went over another building;
moving onto terrain or roads never cleared it. So the selector's `onHover` does not report `-1` / nothing
when the mouse leaves an entity (at least not to a proxy ref), and a "hovered" state built on it needs its own
timeout or another signal. Industry Production Label dropped hover for Shift + open windows.

Industry window plugin (`::IndustryEowExtensionPoint`) `params.entityId` is not the construction (game log
2026-10-20 ~04:32Z: `window entity 193532 -> construction 142962`);
`streetConnectorSystem.getConstructionEntityForSubconstruction` maps it, and the HUD label's STOCK_LIST entity
maps to the same construction (the selected industry's pills showed).
