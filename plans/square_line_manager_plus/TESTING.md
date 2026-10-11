# Line Manager Plus: in-game test (revision 1)

Nothing below has been seen in game yet. Record the results here (date, build, language) and move confirmed facts
to `docs/findings.md`. The undo checklist is Line Editor Undo's (`plans/square_line_revert/TESTING.md`, runs 1-2 passed
there); the Send to Line part was never run in game.

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
- [ ] **Debug: performance log** On: `[SQPERF] mod=square_line_manager_plus ctx=gui` summary every 30 s while using
      both features (sections `tooltip`, `view`, `button_render`, `click`, `descriptor`, `toggle_button`).
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

## Phase 1: shared groundwork (2026-10-10; 2026-10-11 user: looks good)

Undo now gets the manager params from `lmp_capture.lua` and its row slot from `lmp_rows.lua` instead of wrapping the
two base functions itself. Nothing should look or behave differently; there are no new settings or texts.

- [ ] Log at GUI start: `[LineManagerPlus] undo: installed`, and no `[LineManagerPlus] capture:` or `rows:` warning
      during the whole session.
- [ ] Row still reads [Undo][Redo][A+][paint] ··· [Buy Vehicles], same look as before; none with several lines
      selected, none in the depot panel, none in other button rows (vehicle toolbar, other windows with an A+-like
      toggle).
- [ ] Quick undo pass: delete a stop, Undo, Redo, Shift+click Undo. Each acts once; tooltips count as before.
- [ ] Close and re-open the Line Manager, switch lines: buttons follow the edited line (the capture keeps the newest
      window's params).
- [ ] With Auto Assign Terminals enabled (it wraps the same two base functions): both work, in either load order.
- [ ] Line Editor Undo rev 5 enabled too: still exactly one set of buttons (LMP's), as verified before.
- [ ] **Debug: performance log** On: the SQPERF summary still has `descriptor` and `toggle_button` (now timed by the
      shared wrappers).

## Phase 2: line stats on the colour dot (2026-10-10; 2026-10-11 user: looks good)

Setting **Line list: stats on the color dot** (`line_dot_tooltip`, default On). Expect at GUI start
`[LineManagerPlus] dot tooltip: installed`.

- [ ] Line Manager, line list: hover a line's **colour dot**. The tooltip reads "Open Line Window", then the line's
      vehicles by model ("Vehicles on this line: N", "k× Model" rows, at most 5 + "other models") and the stats row
      (Capacity · Utilization · Frequency · Rate), matching the statistics row at the bottom for that line.
      **Key check:** the stats appear in the first tooltip shown. (The text is added when the mouse enters the dot, a
      moment before the tooltip delay ends. If only "Open Line Window" shows, or the stats appear only after moving
      the mouse off and back on, note it: the fallback is building the text at render for the hovered row.)
- [ ] Hovering anywhere else on the row (name, buttons, empty space) behaves exactly as vanilla: the same tooltips,
      the row's hover highlight and its rename / locate / delete buttons appear as before.
- [ ] The dot looks and sits exactly as before (size, vertical centre, hover/active colours, selected-row colours);
      compare with the setting Off.
- [ ] Clicking the dot still opens the line window; clicking the row still selects the line.
- [ ] Line with 0 vehicles: "No vehicles on this line." plus the stats row. Cargo line and passenger line both sensible.
- [ ] Depot rows: unchanged (they have no dot).
- [ ] Other places with a line colour dot are unchanged: vehicle rows in the manager, station window, town / sim
      person window, statistics lines (also UI Overhaul's line and industry cards, if enabled).
- [ ] Moving the mouse quickly down the list across many dots: no stutter.
- [ ] Delete a line while hovering its dot (or right after): no error.
- [ ] With Auto Assign Terminals and UI Overhaul enabled: everything above still works; no `[LineManagerPlus]` warning.
- [ ] Setting Off: log `[LineManagerPlus] dot tooltip: off (mod setting)`, the dot shows "Open Line Window" only.
- [ ] **Debug: performance log** On: SQPERF summary has section `dot_tooltip` after hovering dots. The settings
      dialog shows the new setting translated (one other language), and the debug tooltip's new wording.
- [ ] Other language: the stats lines translated, CJK renders.

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

- [ ] Line Manager, select vehicles, click **Send to Line**: the popup (title "Send to Line", First Stop combo box, the
      list of lines) opens exactly as before, at the same place and size, with **no panel** yet.
- [ ] Hover a row: a dark block (same colour as the map info block) appears **right of the list**, top aligned with the
      header: the line's name, "Vehicles on this line: N" with "k× Model" rows, then Capacity · Utilization ·
      Frequency · Rate, with "→ ~after" arrows for vehicles not already on that line. Numbers match the map hover on
      the same line. Move to another row: the panel follows at once (if it lags a step or flickers between rows,
      note it). Leave the list: the panel goes away. **Key check:** does the window shrink back when it goes? (If it
      stays wide, note it: the fallback is a fixed-width panel slot.)
- [ ] The list doesn't move or change: row width, scroll position (scroll down, hover, the list stays where it was),
      hover highlight and the map highlight of the hovered line, clicking a row sends the vehicles and closes the
      popup, the First Stop combo box opens and changes, the "only visible lines" toggle works, Esc and a click outside
      close it.
- [ ] Hovering the panel itself or clicking on it does not close the popup (it is inside the popover) and does nothing.
- [ ] A line with 0 vehicles: "No vehicles on this line." plus the stats row. A long model name or long line name:
      the panel grows, the text isn't cut. With the popup near the right edge of the screen (manager window moved
      right, or a small resolution): does the panel reach past the edge? (Not handled; note how far.)
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
- [ ] Undo feature Off (setting): Reverse still works (no Undo button). Reverse a 2-stop line without waypoints where
      the terminals don't change: message "reversing doesn't change this line", no change.
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

## Results

- 2026-10-11, phases 1-5: user: looks good (no detailed checklist results).
- 2026-10-11, Map: Shift-click a line (with Passenger Destinations rev 5): user played two games, ready (no detailed
  checklist results).

(paste `[LineManagerPlus]` / `[LineRevert]` lines, screenshots, problems)
