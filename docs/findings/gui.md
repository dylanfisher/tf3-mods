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
- Not yet confirmed on console: whether the rev 6 guard opens the window, whether `movable` is accepted, and how a
  gamepad closes a window without `closable`.

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
- Persist UI prefs across loads in `AppConfig.mainMenuState[modId]` (getAppConfig -> AppConfig.new copy ->
  setAppConfig + saveAppConfig); works from in-game GUI onStep.

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
- When every carrier is hidden, `makePreFilter` hides `TRANSPORT_VEHICLE` icons as well. `BASE_NODE` is in the
  default filter list but has no toggle in the window, so a mod should not hide it (the player couldn't undo it).

## Input actions don't reach a hidden GameUIRoot (read from the game files 2026-10-13, not verified in game)

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
  "ToggleButtonGroup!flow FlowLayout" { 4, 4 }, "CheckBox BoxLayout!buddy-layout", "R::FeedbackItem > BoxLayout");
  padding on a layout through a class rule (Timetables' `!celmi-tt-content` on its tab BoxLayout, our Better
  Minimap `BoxLayout!minimap-controls`). Inline sheets do apply to Components (Better Minimap's `layerAt` padding,
  verified), TextViews and a recipe call's node.
- Fix (Photo Mode round 6, not yet seen in game: TESTING.md G22): classes on the layouts and three rules
  (`R::PhotoModeContent !sqpm-gap` innerSpacing 6/6, `!sqpm-checks` 12/6, `!sqpm-content` padding 8 +
  innerSpacing 8), no element name so one rule covers BoxLayout and FlowLayout. A class on a `builtin.FlowLayout`
  goes the same `meta.class` path as on a BoxLayout (both `DeclareBuiltinWithUserdata`), but no base file does it:
  confirm in game. Offline guard: `tests/square_photo_mode/test_window.lua`. Rules for every mod:
  `docs/ui-guide.md` "Spacing".

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
