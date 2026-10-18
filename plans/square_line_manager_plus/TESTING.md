# Line Manager Plus: in-game test

Status: rev 5 (2026-10-11). Phases 1-5 and Shift-click: user "looks good" 2026-10-11 (no detailed ticks); their
sections stay as the regression checklist. Record results under "Results" (date, build, language) and move confirmed
game facts to `docs/findings.md`. Passed one-off checks and old results: HISTORY.md.

Open checks (not yet run in game): "Phase 2: line list, line info on hover" (rework), "Expired line state", "Line Rate
Matcher", "Map: line info on hover". The vehicle list features of revs 3-5 have no section yet (PLAN.md "Open work").

## Setup

1. `make link` (done; `square_line_manager_plus` is linked into the staging area). Line Editor Undo
   (`square_line_revert`, rev 5 locally) stays linked for the coexistence cases.
2. Start the game. In the mod list enable **Line Manager Plus**; disable **Line Editor Undo** and **DEV Line Revert
   Probe** for the main checklist. Load a save with several bus/truck/train lines (some with mixed models, one with
   no vehicles, one cargo line).
3. In a terminal:
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered -E 'LineManagerPlus|LineRevert'`
   Expect at GUI start `[LineManagerPlus] send to line: installed` and `[LineManagerPlus] undo: installed`. Any
   other `[LineManagerPlus]` warning is a failure report (logged once per kind): copy it here.

## Send to Line info

Open the Line Manager, select vehicles, click **Send to Line**, hover lines on the map.

- [ ] The replacement takes effect at all: the hover shows the game's "Send N vehicles to <line>." and our block
      below it. (Unverified mechanism for this recipe: the tooltip is rendered through
      `builtin.ActionTooltip{recipe = ...}`, line_util.tl:1247. UI Overhaul replaces the sibling `LMAddStop` the same
      way, which suggests it works. If only the vanilla text shows and `installed` was logged, the engine calls the
      recipe by id and skips `_react.recipeReplace`: note it here.)
- [ ] Look: our block uses the vanilla tooltip classes, so it should look like a second tooltip box directly under
      the first. Note whether the two boxes read as one tooltip, whether their widths differ, and whether a seam or
      gap shows. If it looks poor, options: a 1-2 rule stylesheet scoped to `R::SquareLmpSendToLineInfo` (keep the
      rule count low, docs/findings.md "Load crash above ~200 mod stylesheet rules").
- [ ] Line with 0 vehicles: "No vehicles on this line." plus the stats row.
- [ ] Line with many vehicles of several models: "Vehicles on this line: N", one "k× Model" row per model, largest
      first, at most 5 rows, then "k× other models". Model names are the store names (multiple-unit trains show the
      unit's name, other trains the first car's, normally the locomotive).
- [ ] Numbers match the statistics row at the bottom of the Line Manager for the same line: Capacity, Utilization,
      Frequency (m:ss), Rate. (Ours are cached for 1 s and don't update while the hover stays on one line.)
- [ ] Cargo line (trucks, freight train) and passenger line both show sensible values.
- [ ] Hovering a depot ("Send N vehicles to <depot>.") is unchanged (separate recipe, not touched).
- [ ] Clicking a line still sends the vehicles; the Send to Line dropdown list still works (hover, click, "Stop To
      Send Vehicles To" combo, only-visible toggle).
- [ ] Hovering quickly across many lines: no stutter (each line is read at most once per second).
- [ ] A line deleted while hovering it (or while the tooltip is up): no error, the vanilla text only.
- [ ] With UI Overhaul enabled (it replaces other Line Manager recipes, not `VMSendToLine`): both work.

## Undo and Redo

Undo logs `[LineManagerPlus] undo: undid one edit on line <id> (<n> stops)`, Shift+click
`... reverted line <id> ...`, Redo `... redid one edit on line <id> ...`. With **Debug: performance log** On, each
recorded edit also logs `[LineManagerPlus] undo: edit <n> on line <id>` and a new line `... session line <id> ...`.

- [ ] Row reads [Undo][Redo][A+][paint][Buy Vehicles]: same size, spacing and look as A+ (unchecked-toggle colours
      from `lmp.css.lua`); greyed (no fade on mount) while there is nothing to undo / redo. None with several lines
      selected, none in the depot panel.
- [ ] Delete / add / reorder a stop, change load mode / waiting time / a cargo setting, change a terminal, add or
      move a waypoint: each is one Undo step and comes back exactly.
- [ ] Several edits, then Undo one by one: the tooltip count goes down by one per click; the last click greys Undo.
- [ ] Shift+click Undo reverts all; Redo then steps forward one edit per click, "(N more)" counting down.
- [ ] An edit after an Undo greys out Redo.
- [ ] Crash regression: add a stop, Undo, click a road to add a waypoint, add a stop; also add a stop, start moving
      a stop, Undo. No crash.
- [ ] Demolished station in the target state: error message in the manager's feedback list, starting with
      "Line Manager Plus:", nothing changed.
- [ ] Switch to another line and back, or close and re-open the manager: history and redo reset.
- [ ] With Auto Assign Terminals enabled too: both work.

## Mod settings

Change them in the mod selection when loading the save (settings only change on a game load).

- [ ] **Send to Line: target line info** Off: only the vanilla hover text; log `[LineManagerPlus] send to line: off
      (mod setting)`; undo still works.
- [ ] **Line editor: Undo and Redo buttons** Off: no undo/redo buttons, A+ in its usual place; log
      `[LineManagerPlus] undo: off (mod setting)`; Send to Line info still works.
- [ ] Both Off: nothing changes in the Line Manager; no errors.
- [ ] **Line actions: Match line rate** (`line_rate_matcher`) Off: the Line actions menu has only Duplicate and
      Reverse; log `[LineManagerPlus] rate matcher: off (mod setting)`. With **Line editor: Line actions button** Off
      (and Match line rate On): no button; log `[LineManagerPlus] rate matcher: needs the Line actions button
      (line_actions Off), not installed`.
- [ ] **Debug: performance log** On: `[SQPERF] mod=square_line_manager_plus ctx=gui` summary every 30 s while using
      both features (sections `tooltip`, `view`, `button_render`, `click`, `descriptor`, `toggle_button`; with the Rate
      Matcher window open `rate_matcher_step`, `rate_matcher_render`, `rate_matcher_click`).
- [ ] Settings dialog: the three settings' names and tooltips are translated (check one other language).

## Coexistence with Line Editor Undo

- [ ] **Both enabled** (Line Editor Undo rev 5 from the staging area): the game warns about the incompatibility when
      activating (and/or when starting the game). Continue anyway: the undo buttons appear **once**. Log:
      `[LineRevert] Line Manager Plus (square_line_manager_plus) is active ... Line Editor Undo stays off.` and
      `[LineManagerPlus] undo: installed`. Undo works, with "Line Manager Plus:" messages.
      This is the check that `genericRep` lists our config to Line Editor Undo.
- [ ] Both enabled, Line Manager Plus's undo setting Off: Line Editor Undo's buttons appear once (no stand-down line
      from `[LineRevert]`).
- [ ] Both enabled with Line Editor Undo **rev 4** (the mod.io version, e.g. subscribed and the staging link
      removed; optional): `[LineManagerPlus] undo: Line Editor Undo (square_line_revert) is active ...` and one set
      of buttons (Line Editor Undo's); Send to Line info still installed. This checks that `genericRep` keeps the
      `yieldsTo` field: if rev 5 + LMP shows **no** buttons, the field was dropped (both stood down): report it.
- [ ] **Line Editor Undo installed but disabled**, Line Manager Plus enabled: Line Manager Plus's undo works, no
      stand-down line. (This is the check that a disabled mod's config is absent from `genericRep`.)
- [ ] Line Editor Undo alone (Line Manager Plus disabled but installed): its buttons work, no stand-down line.

## Saves

- [ ] Add Line Manager Plus to an existing save (load a save made without it): no warning beyond the usual, both
      features work.
- [ ] Remove it again and load: no warning about missing content, nothing changes in the save (GUI only).
- [ ] Switching from Line Editor Undo to Line Manager Plus on an existing save: no warning (both have severity None).

## Language

- [ ] Other language (e.g. Russian or German, Settings then restart if needed): tooltips, feedback messages and our
      Send to Line block are translated, the stat names match the Line Manager's own labels, CJK renders (also "×"
      and "·").

## Phase 2: line list, line info on hover (reworked 2026-10-11; not yet run)

Setting **Line list: line info on hover** (`line_list_hover_info`, default On; replaces rev 1's first build, the stats
under the colour dot's tooltip, `line_dot_tooltip`). Expect at GUI start `[LineManagerPlus] list hover: installed`
and no `dot tooltip` line. The block is the Send to Line list's (Phase 4), drawn by the shared `lmp_callout.lua`, as a
callout on the game's mouse-transparent callout overlay. Hook: `builtin.ColumnDesc` for the line list's column; the
row recipe gets `meta.onMouseOver` and a ref holder, no extra node (line_list_hover.lua header).
Unverified in game: that a plain function works as the column's cell recipe, that `meta.onMouseOver` on the row
fires for the whole row (also over its buttons) without false/true pairs while the mouse moves inside it, and the
18 px gap.

- [ ] **Key check (layout):** open the Line Manager. The line list looks exactly as before with the setting On and Off:
      row height and width, the scrollbar, the checkbox, colour dot, name, notification icons; the rename / locate /
      delete buttons appear on hover as before; selected-row and hover colours. If the list is broken or empty, note the
      log (`[LineManagerPlus] list hover: column` / `row` warnings) and switch the setting Off.
- [ ] **Key check (hover):** hover a line's row anywhere (checkbox, dot, name, empty space, the icons on the right): a
      dark block appears **at once** (no tooltip delay) **outside the Line Manager, to its right**, its top level
      with the hovered row, in the same darker blue as the Send to Line list's block. Contents: the line's name,
      "Vehicles on this line: N" with "k× Model" rows, then Capacity · Utilization · Frequency · Rate (no arrows);
      numbers match the statistics row at the bottom for that line. It stays steady while the mouse moves within the
      row (note any blink when crossing the buttons).
- [ ] Gap: the block sits just outside the window frame, not overlapping it (note the gap in px if it looks too large
      or overlaps; `M.GAP` = 18 in line_list_hover.lua).
- [ ] Move down the list: the block follows row by row (note a one-frame blink between rows, if any). Leave the list
      (to the search field, the header, the vehicle card, outside the window): the block goes. Scroll with the wheel
      while hovering: the block follows the row or goes; never left behind on its own.
- [ ] Move the Line Manager to the **right half** of the screen: the block opens **left of the window**. Near the
      bottom edge it stays on screen.
- [ ] The list works as before: click a row selects the line; checkboxes; the colour dot opens the line window; rename,
      locate, delete (also delete the hovered line: the block goes, no error); double-click follows the line; search
      and filters; the game's "Select Line" / "Open Line Window" tooltips still appear after their delay.
- [ ] Depot rows: no block. A line with 0 vehicles: "No vehicles on this line." plus the stats row.
- [ ] Close the Line Manager while a block shows (Esc, or the toolbar button): the block goes with it, no block left on
      screen (a "CalloutContainer: parent node has been destroyed" warning in stdout is harmless; note it).
- [ ] Other tables unchanged: the vehicle list in the manager, statistics, station / depot vehicle tables.
- [ ] Send to Line from the manager while hovering the list: the popover's own block works (Phase 4); the two never
      show at once.
- [ ] Moving the mouse quickly down a long list: no stutter.
- [ ] With Auto Assign Terminals and UI Overhaul enabled: everything above still works; no `[LineManagerPlus]` warning.
- [ ] Setting Off: log `[LineManagerPlus] list hover: off (mod setting)`, no block, the list as vanilla.
- [ ] **Debug: performance log** On: SQPERF summary has section `list_hover` after hovering rows. The settings
      dialog shows the new setting name and tooltip translated (one other language).
- [ ] Other language: the block's lines translated, CJK renders.

## Phase 3: Send to Line before → after estimate (2026-10-10; 2026-10-11 user: looks good)

Setting **Send to Line: before/after estimate** (`send_to_line_estimate`, default On; needs **Send to Line: target line
info** On). Expect at GUI start `[LineManagerPlus] estimate: installed` after `send to line: installed`.

- [ ] Select 2 buses on line A, Send to Line, hover bus line B on the map: the stats take two rows,
      "Capacity: 40 → ~80  ·  Utilization: 50%" and "Frequency: 7 min 19 s → ~4 min 53 s  ·  Rate: 66 → ~132" (the
      "→" and "~" render; the tooltip isn't much wider than before). Note the numbers, click to send, then compare
      with the footer of line B a few seconds later: Capacity should match exactly; Frequency and Rate should be close
      for vehicles of the same model (Rate exactly, per docs/findings.md "Line Rate"); record how far off they are for
      a mixed fleet.
- [ ] Hover the vehicles' own line A: no arrows (they are already on it), one stats row as before.
- [ ] Select vehicles from A and B, hover B: only the ones from A count (capacity grows by theirs only).
- [ ] Line with 0 vehicles: "Capacity: 0 → ~N", Frequency and Rate without arrows. After sending, check whether the
      footer's frequency appears at once (if the native value updates immediately, a later version could show it).
- [ ] Cargo: send trucks of one cargo (e.g. logs) to a truck line of another cargo: no capacity arrow, and the line
      "Selected vehicles that can't carry this line's cargo: N". Universal trucks set to another cargo: capacity grows
      by their capacity for the line's cargo, no note.
- [ ] Select vehicles, then change the selection without leaving the mode: the hover follows the new selection (the
      tooltip's "Send N vehicles" count and our arrows agree). If the arrows are missing although N matches, the
      captured selection lags: note it.
- [ ] Setting Off: the info as before (one row, no arrows); log `[LineManagerPlus] estimate: off (mod setting)`.
      Target line info Off and the estimate On: neither shows; log `[LineManagerPlus] estimate: not installed: it
      needs "Send to Line: target line info" On`.
- [ ] Other language (de, ru, ja): the arrow line reads naturally, the note is translated, CJK renders `→` and `~`;
      the settings dialog shows the new setting translated.
- [ ] No `[LineManagerPlus] stats:` / `estimate:` warnings during the session.

## Phase 4: Send to Line list panel (2026-10-10; 2026-10-11 user: looks good)

Setting **Send to Line list: line info panel** (`send_to_line_list_info`, default On). Expect at GUI start
`[LineManagerPlus] list info: installed` (or `installed (estimate off: mod setting)` with the estimate Off).

2026-10-11 rework (user report: the panel inside the card squeezed the list, names clipped, hovering a row's right part
flickered): the card has a fixed 440 px width (popover_react_util.css.lua:14-17), so the panel now opens as a
**callout outside the card** on the game's callout overlay (the layer of the entity windows' card callouts), which is
mouse-transparent. Unverified in game: that the overlay draws above the popover and passes the mouse through.

- [ ] Line Manager, select vehicles, click **Send to Line**: the popup (title "Send to Line", First Stop combo box, the
      list of lines) opens exactly as vanilla, same place and **same width**, full line names, the scrollbar at the
      card's right edge, and **no block** yet.
- [ ] **Key check (flicker):** hover a row on its **left** part, then its **middle**, then its **right** part next to
      the scrollbar: a dark block appears **outside the card, to its right** (8 px gap, top aligned with the card's
      top), in **the same darker blue as the map hover info block** (compare with hovering the line on the map in Send
      to Line mode). It stays steady anywhere on the row: no flicker, the row keeps its hover highlight, line names are
      never clipped, the card never changes width. Contents: the line's name, "Vehicles on this line: N" with
      "k× Model" rows, then Capacity · Utilization · Frequency · Rate, with "→ ~after" arrows for vehicles not
      already on that line; numbers match the map hover on the same line.
- [ ] Move to another row: the block follows at once (note a one-frame blink between rows, if any). Leave the list
      (to the header, the combo box, outside): the block goes away. Close the popup (Esc, click outside, send to a
      line): the block goes with it, no block left on screen, no "CalloutContainer: parent node has been destroyed"
      warning in stdout (if there is one, note it; harmless).
- [ ] Move the Line Manager so the popup is in the **right half** of the screen: the block opens **left of the card**
      instead, not covering the rows. Near a screen edge it stays on screen.
- [ ] The list doesn't move or change: row width, scroll position (scroll down, hover, the list stays where it was),
      hover highlight and the map highlight of the hovered line, clicking a row sends the vehicles and closes the
      popup, the First Stop combo box opens and changes, the "only visible lines" toggle works, Esc and a click outside
      close it.
- [ ] The block takes no mouse: moving the mouse onto it doesn't change anything in the list; clicking on it acts as a
      click outside the card (the popup closes, as when clicking beside it).
- [ ] While the block shows, an entity window card callout (hover a card info icon in a station window, if one is
      open) replaces it: hovering a list row again brings ours back.
- [ ] A line with 0 vehicles: "No vehicles on this line." plus the stats row. A long model name or long line name:
      the block grows, the text isn't cut.
- [ ] Popup opened from the **line window** (Send to Line there, `openWithVehicleEntities`): same panel.
- [ ] Other popovers unchanged, no panel: the stop's "Select Terminals" popover in the line editor, the auto-rename
      dialog, the configure-lines popover, any toolbar popover. Also with **UI Overhaul** and **Easy Terminal
      Assignment** (they wrap the same function for the terminal popover): their terminal popovers still work.
- [ ] With **Auto Assign Terminals** enabled (it replaces the PopoverWindowContent recipe): its terminal popover
      refresh button and station card still work, and our panel shows in Send to Line. Try both mod orders if possible.
- [ ] Setting Off: log `[LineManagerPlus] list info: off (mod setting)`, the popup as vanilla. Estimate setting Off:
      the panel without arrows.
- [ ] **Debug: performance log** On: SQPERF section `stl_list` after hovering rows; hovering quickly down a long list
      causes no stutter.
- [ ] Other language (de, ru, ja): the panel text translated, CJK renders; the settings dialog shows the new setting
      translated.
- [ ] No `[LineManagerPlus] list info:` warnings during the session.

## Phase 5: Line actions, Duplicate and Reverse line (2026-10-10; 2026-10-11 user: looks good)

Setting **Line editor: Line actions button** (`line_actions`, default On). Expect at GUI start
`[LineManagerPlus] line ops: installed`.

- [ ] Select one line: a list icon right of A+ (before the paint bucket), same size and look as A+, tooltip
      "Line actions". Several lines selected, no line, or a mission-protected line: no button. **Look check:** the icon
      is the same size as A+ and the row doesn't shift.
- [ ] Click it: a small popover opens below the toolbar where A+'s popover opens, with "Duplicate line" and "Reverse
      line" (icons: two squares, curved arrow), both buttons equally wide. Click the button again: it closes (and does
      not reopen on release). Click outside: it closes and the button is no longer "pressed". Open it, then click A+:
      A+'s popover replaces ours and our button is no longer pressed. Esc closes it.
- [ ] **Duplicate a bus line**: a new line "<name> (copy)" appears with the same stops, terminals, waypoints, load mode
      and waiting times, a new colour (as a new line gets), no vehicles; the manager switches to it (selected, editor
      open). Duplicate the same line again: "(copy 2)". The original line and its vehicles are unchanged.
- [ ] Duplicate a **train line** (platform choices kept) and a **ship line** (water waypoints kept): the copy has a
      valid path (no line problem icon).
- [ ] **Reverse a bus line** of 4+ stops on a two-way street: stop 1 stays first, the rest run backwards; road stops
      switch to the other side where the stop has two sides; the line has a path. Vehicles keep running (note what they
      do right after the reverse: continue to their next stop? turn around?). The Undo tooltip says "stops reordered"
      (1 change); **one Undo click restores the original order and terminals**; Redo reverses again.
- [ ] Reverse a train line with waypoints and a line on one-way roads: if the reversed line has no path, the game shows
      its line problem; Undo takes it back. Note what happened.
- [ ] Undo feature Off (setting): Reverse still works (no Undo button). A 2-stop line: Reverse is greyed out with the
      tooltip "Reversing needs at least 3 stops: with 2, the line already runs both ways." A mirror-image route
      (A, B, C, B): Reverse gives "this line visits the same stops in both directions, so reversing doesn't change it",
      no change.
- [ ] Failure cases: a line with 1 stop (both entries greyed out, tooltip "The line needs at least 2 stops."); demolish
      a station of a line, then open the menu (greyed out, "A station of this line no longer exists."). Clicking twice
      fast: only one command is sent.
- [ ] Other language (de, ru, ja): menu, tooltips, the copy's name "(Kopie)" / "（コピー）", the setting translated.
- [ ] **Mod removal after duplicating/reversing:** save with a duplicated and a reversed line, quit to the menu,
      disable Line Manager Plus, load: both lines are there and work; the copy can be deleted with Delete Line.
- [ ] **Debug: performance log** On: SQPERF section `line_actions` after using the menu. No `[LineManagerPlus] line
      ops:` / `line actions:` warnings.

## Expired line state (2026-10-11, not yet run)

Reopening the Line Manager printed a message-less `stack traceback` (`=[C](-1): old` ← `lmp_capture.lua(63):
editedLine` ← `undo.lua`) to stdout.txt, twice per reopen: the captured params of the closed window were read once in
the buttons' lazy init and once in their first step. `capture.editedLine` (and the Send to Line list's hover read) now
skip an expired state (docs/findings.md "Expired react states").

- [ ] Open the Line Manager, close it, open it again (also via a vehicle's / line's window and Shift-click on the map),
      several times: no `stack traceback` with `lmp_capture` / `undo.lua` / `lmp_actions.lua` and no `Calling Old() on
      expired ReactStateWrap` line in stdout.txt.
- [ ] Undo / Redo and the Line actions button still appear for the edited line right after reopening.

## Line Rate Matcher (merged from square_line_rate_matcher, 2026-10-11, not yet run)

The former mod Line Rate Matcher (rev 1, never published) is now the feature **Line actions: Match line rate**
(`line_rate_matcher`, MERGE_RM_PLAN.md): an entry in the Line actions menu instead of its own button left of A+. The
window itself is unchanged. Design history: RATE_MATCHER.md (the former PLAN.md), history/RM_PROBE.md, rm_probe_run*.log.
**Apply buys and sells vehicles**: use a test save (the probe's WC Logs save is ideal).

Setup: Line Manager Plus only. **Disable Line Rate Matcher** if it is still in the mod list (it is retired), and the
DEV **Line Rate Matcher Probe** (`square_line_rate_matcher_probe`): it mounts its own "RM" row next to A+. The log
filter `LineManagerPlus` now covers it: `[LineManagerPlus] rate matcher: installed` at GUI start, then `open line ...`,
`timing line ...`, `price ...`, `clone charged ...` (formerly `[RateMatcher] ...`).

Merge checks:

- [ ] The Line actions menu (list icon right of A+, one selected line) has a first entry **Match line rate** with the
      clock-and-box icon, above Duplicate and Reverse; its tooltip explains it. Click: the menu closes and the Rate
      Matcher window opens, titled with the line's name, looking and working as before (opaque, placed right of
      centre, right-aligned columns, no sort caret, no grey highlight when hovering or pressing a column header).
- [ ] Clicking Match line rate again for the same line brings the window to the front and re-reads the line; for
      another line the window switches to that line.
- [ ] A protected (mission) line: no Line actions button, so no Match line rate (the old button showed there;
      accepted with the merge).
- [ ] **No tracebacks**: leave the Rate Matcher window open, close the Line Manager, wait a minute (the window
      re-reads every 2 s), press Apply once: stdout.txt has no `stack traceback` and no `Calling Old() on expired
      ReactStateWrap` (the old mod printed ~70 per session). Then reopen the Line Manager on the line: Apply again adds
      the new vehicles to the manager's vehicle list.
- [ ] Settings: see "Mod settings" (Off, and Line actions button Off).
- [ ] **Performance** (Debug: performance log On, Rate Matcher window open on the biggest line you have, ~1 min idle,
      then a few target keystrokes): `make perf ARGS='--mod square_line_manager_plus'` shows `rate_matcher_step` about
      once per frame with a tiny mean (most frames do nothing; every 2 s one Rate + vehicles read), and
      `rate_matcher_render` only a few times while idle (renders only when Rate or the vehicles change), once per
      keystroke while typing; no `slow=rate_matcher_*` lines. With the window closed, no `rate_matcher_*` section
      counts up. (Offline, 2026-10-11, 100 vehicles / 200 other lines / 300 models: step 0.4 µs, live refresh
      0.2 ms, render 0.6 ms, open 3.8 ms in the test harness's Lua; the game's engine calls cost more.)

From the former checklist (phase 3f, the last state tested 2026-10-11):

| # | Step | Expect |
|---|---|---|
| f1 | **Right edges** | The stats row's last cell, both tables (incl. the selected row's highlight) and the three panels end at the same right edge; nothing pokes out of a panel |
| f2 | **Tags** | "suggested" (top table, next to the target box) and "best" are plain light-blue text, the colour of the Line Manager's Balance value; no background; "suggested" not cut off |
| f3 | **Disabled Apply** | After "Bought 1 vehicle for this line." Apply is an outlined button with readable dimmed text; enabled again it is the filled primary button |
| f4 | Widths | If f1 is off by a constant, the assumption that a StyleSheet `size` excludes padding is wrong: say roughly how much |

Core checks (condensed):

| # | Step | Expect |
|---|---|---|
| 1 | Select **WC Logs** (2 ships, Rate 66), Match line rate | Target **101** "suggested", rows "3 · +1 · 99" (checked, "suggested") and "4 · +2 · 132". Log `open line ...`, `timing line ...`, `price ...` |
| 2 | Alignment | Headers over their columns, numbers right-aligned, both tables the same width, nothing cut off |
| 3 | Select | Click anywhere on a row or its check box: it becomes selected, the Apply line changes; same in the comparison (its rows replace the plan table). Header clicks don't sort |
| 4 | Price | "3 · +1" Price = the store price; after Apply `clone charged: ... = X` matches |
| 5 | Cost/yr, Cost per unit | Cost/yr = running + purchase over the lifespan (tooltip shows both); Cost per unit = Cost/yr ÷ ≈ Rate |
| 6 | Compare models | Per-model figures differ when the timing line has a share at stops > 0; "best" on the cheapest |
| 7 | Estimate vs reality (optional) | Switch model, wait 1-3 s: real Rate vs the promised ≈ Rate |
| 8 | Type `33` (no Enter) | Rows update while typing, focus stays; "1 · -1 · 33", Price negative |
| 9 | Apply buy / sell / model switch / Replace window / passenger line / train / mission vehicles / reopen / close Line Manager | Vehicle list follows, Rate updates within 1-3 s, hints for passengers / trains / mission vehicles |
| 10 | Spacing | Room above "Compare models" and above the buttons; both headings alike |

After the run: `grep -E 'LineManagerPlus\] rate matcher.*(failed|further failures)|ERROR' stdout.txt` should be empty.

Unverified in game (from the former mod): `builtin.DataTable` height with few rows and its click / check box / style
class handling; the two right-aligned rules; `getLineCargoInfo` section vs drive times (the estimate depends on them);
`makeVehicleReplaceCmd` switches and money checks (a 2026-10-11 switch of 3 replaced + 3 bought logged `failed 0/6`,
probably the all-or-nothing money check).

## Map: Shift-click a line (moved from Passenger Destinations, 2026-10-11; 2026-10-11 user: ready after two games)

Ported from plans/square_passenger_destinations/TESTING.md F.8 and F.11 (passed there 2026-10-11). Expect at GUI start
`[LineManagerPlus] map shift click: installed`; each Shift-click that opens the manager logs `[LineManagerPlus] map
shift click: open the Line Manager for line N (clicked M)`.

- [ ] (F.8) Shift-click one of your lines on the map: the Line Manager opens on that line, no line window first. A
      plain click still opens the line window. Shift-click a vehicle or station: its usual window. Another company's
      line: its usual line window.
- [ ] (F.11) Click one of your lines (its window opens), then Shift-click the drawn line (or any water / ground): the
      Line Manager opens on that line. Shift-click a vehicle or station there: its usual window.
- [ ] Line Manager, construction menu or a layer on top: Shift-click does what a click does there (no manager opens
      from the map).
- [ ] With Passenger Destinations on (rev 5, the click code removed there): Shift-hover a vehicle so its arrows show,
      move onto one of your lines and click within ~¼ s: the manager opens and PaxDest's arrows go (`[PaxDest] hover
      pop (another tool on top: Manager)`); closing the manager brings no arrows back. Shift hover itself still works
      afterwards. Both mods log their `makeDefaultSelector` line at start (`[PaxDest] shift hover: makeDefaultSelector
      wrapped`, `[LineManagerPlus] map shift click: installed`).
- [ ] Setting **Map: Shift-click a line opens the Line Manager** Off (on load): Shift-click a line opens the line
      window; log `[LineManagerPlus] map shift click: off (mod setting)`.

## Map: line info on hover (2026-10-11, not yet run)

Expect at GUI start `[LineManagerPlus] map hover: installed`. Open the Line Manager (normal mode: line list, no
Send to Line), hover lines on the map.

- [ ] The replacement takes effect: below the game's "Select <line>." text, our block (vehicles by model, then
      Capacity · Utilization · Frequency · Rate), the same look as the Send to Line block (darker box, 4 px gap).
- [ ] Numbers match the Send to Line hover / the line list hover block / the footer for the same line; no "→ ~" arrows.
- [ ] Line with 0 vehicles: "No vehicles on this line." plus the stats row. Cargo and passenger lines, a train line.
- [ ] Clicking a line still selects it (sound, list scrolls); stations still show "Create new line…", depots
      their texts; with a line selected, hovering another line still shows the block.
- [ ] Send to Line mode: still the Send to Line block with the estimate (separate recipe); segment / move-stop modes
      unchanged ("Select section", etc.).
- [ ] Line Manager closed: the map hover of a line is the game's usual one (no block, nothing logged).
- [ ] Hovering quickly across many lines and along one line: no stutter (SQPERF section `map_hover` with
      **Debug: performance log** On).
- [ ] A line deleted while hovering it: no error.
- [ ] Setting **Map: line info on hover** Off (on load): only "Select <line>."; log
      `[LineManagerPlus] map hover: off (mod setting)`. With **Send to Line: target line info** Off and this On, the
      map hover still shows the block.
- [ ] A long translated text (de/ru) and CJK: the block wraps within the tooltip's max width.

## Results

(paste `[LineManagerPlus]` / `[LineRevert]` lines, screenshots, problems)
