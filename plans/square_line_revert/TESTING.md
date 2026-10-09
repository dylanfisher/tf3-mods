# Line Editor Undo: in-game test (phase 1 undo, phase 2 redo)

## Setup

1. `make link` (done once; `square_line_revert` is linked into the staging area).
2. Start the game and load a test save. In the mod list **disable DEV Line Revert Probe** (`square_line_revert_probe`):
   its "R" button also mounts left of A+ and would sit next to the new undo icon button. Enable **Line Editor Undo**.
3. In a terminal:
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered LineRevert`
   Expect `[LineRevert] installed` at GUI start.
4. Open the line manager, select one line and enter its stop editor. Expect `[LineRevert] session line <id> stops <n>`
   and, once per game start, `[LineRevert] loadMode type <t> value <v>` (record it below: if the type is `userdata`
   and the button stays enabled on an unchanged line, the equality check in `line_revert_core.lua` needs a fix).

## Checklist

For each case: note whether the button is greyed while the line is unchanged, enabled after the edit (hover: the
tooltip names the change and the change count), and whether one click puts the line back exactly by one edit
(stops, terminals, waiting times, cargo settings in the stop's cargo popup, waypoints). Every edit logs
`[LineRevert] edit <n> on line <id>`; an undo logs `[LineRevert] undid one edit on line <id> (<n> stops)`, Shift+click
`[LineRevert] reverted line <id> (<n> stops)`. After undoing the last edit the button greys out again.

- [ ] Icon matches A+/paint size and greys out when disabled; tooltip still shows.
- [ ] Button: the undo icon sits left of A+ in the stop editor action row; nothing overflows or misaligns. None with
      several lines selected, none in the depot panel.
- [ ] Delete a stop, then Undo.
- [ ] Add a stop, then Undo.
- [ ] Reorder stops (drag/move a stop), then Undo.
- [ ] Change a stop's load mode / waiting time (and a cargo setting), then Undo.
- [ ] Change a terminal and add an alternative terminal, then Undo.
- [ ] Add / move a waypoint (road or rail; also a ship or plane line if one exists), then Undo.

### Undo

- [ ] **One edit = one step.** Make several edits (add a stop, remove a stop, move a stop, add a waypoint, change a
      terminal), then Undo them one by one: each click undoes exactly the last edit, the tooltip's count goes down by
      one, and the last click greys the button. Count the `edit <n>` log lines: **if one editor action logs more than
      one edit, one Undo only undoes part of it** (note which action). Suspects: Auto Assign Terminals reassigning
      terminals after a stop is added (its own command), a slider drag in the cargo window (commits per value).
- [ ] **Our undo isn't recorded.** After an Undo, no new `edit <n>` line; the tooltip count drops. If an Undo is
      followed by an `edit` line and the button stays enabled on what looks like the same line, the engine
      normalised the restored line (a field differs from what we sent): note which field (`loadMode`?, waypoint `tag`?).
- [ ] **Shift+click = revert all.** Make 3+ edits, hold Shift and click: the line is back as opened, the button greys
      out. Also check Shift is seen while the mouse is over the window (no 3D view under the cursor).
- [ ] **Undo after the crash-regression steps** (see "Regression" below): add a stop, Undo, click a road to add a
      waypoint, add a stop; also add a stop, start moving a stop, Undo. No crash, and the new edits are undoable.
- [ ] **Undo while vehicles run**: on a line with vehicles driving, make 2 edits and undo both; vehicles keep
      running, no errors, no stuck vehicles. Also undo the removal of the stop a vehicle was heading to.
- [ ] Fast double click on Undo: only one step per engine round trip (the button is greyed while an undo is in flight).
- [ ] Slider drag in the cargo window (waiting time): how many `edit` lines does one drag make?

### Redo

Redo logs `[LineRevert] redid one edit on line <id> (<n> stops)`; a recorded edit still logs `edit <n>`.

- [ ] **Icons line up.** The row reads [Undo][Redo][A+][paint][Buy Vehicles]: same size, spacing and look as A+; the
      redo arrow mirrors the undo arrow; Redo is greyed (no fade on mount) until an Undo; nothing overflows.
- [ ] **Undo 3x, redo 3x.** Make 3 edits, Undo three times (line back as opened), then Redo three times: each click
      re-applies exactly one edit, in order; after the third Redo it greys out and the line equals the last edit.
      No `edit <n>` lines from our own redos; Undo works again afterwards.
- [ ] **An edit after undo greys out Redo.** Make 2 edits, Undo once (Redo enabled), then make any new edit (add a
      stop): Redo greys out at once and stays greyed.
- [ ] **Revert all, then redo step by step.** Make 3 edits, Shift+click Undo, then click Redo: one edit comes back
      per click, in the original order, and the tooltip's "(N more)" counts down 2, 1, 0.
- [ ] **Tooltips.** Redo greyed: "Redo: nothing to redo". After an Undo: "Redo: <what it re-applies> (N more)"
      (e.g. "1 stop added (0 more)"). While a command is in flight both buttons are greyed ("Undoing..." /
      "Redoing..."). Undo's tooltip count goes back up after a Redo.
- [ ] Fast double click on Redo: one step per engine round trip.
- [ ] Redo after the crash-regression steps: add a stop, Undo, Redo, then click a road to add a waypoint and add a
      stop. No crash.
- [ ] Switch to another line and back, or close and re-open the manager, after an Undo: Redo is greyed (new session).

### Sessions and safety

- [ ] Switch to another line and back: the history resets (the button is greyed for the current state; new
      `session` log line).
- [ ] Close and re-open the manager: new session (greyed, new `session` line).
- [ ] Demolished station: open a line, then demolish one of its stations (or remove a stop and bulldoze that
      station), click Undo until the state with that station. Expect an error message in the manager's feedback list, nothing sent, the line unchanged.
- [ ] With **Auto Assign Terminals** (zhenya_auto_assign_terminals) enabled too: both buttons work, no errors; revert
      restores the exact terminals of the earlier state (AAT may reassign them afterwards on its own).
- [ ] No `ERROR` lines or Lua errors in stdout.txt during the whole run; no crash.

## Open questions to confirm

- Feedback: does the error message show in the manager's feedback list (`commonParams.addFeedback`)?
- Can one editor action produce more than one engine commit (see "One edit = one step")? Then one Undo undoes
  only part of the action.
- Is Shift (`IA_PRECISION_MODE`) reported as held when clicking a GUI button?
- The history starts at the first step the button is mounted for a line. If a line can be edited without
  `LinePanelActionButtons` being shown first (another manager mode), the history starts late. Note any such path.
- Waypoint `tag`s and `edgePos`/`pos` are rebuilt with `api.type.Waypoint.new()`: confirm waypoints come back where they were.

## Results

(paste `[LineRevert]` lines, screenshots, problems)

## Regression: crash after revert (2026-10-07)

Run 1 crashed with `bad argument #2 to 'insert' (position out of bounds)` in `manager_window.tl:6961 addWaypoint`
after reverting: the editor's `{"SEGMENT", n}` still pointed past the end of the now shorter line. Fixed: a revert (now every
undo) switches the editor to `{"SEGMENT", nil}` (end of line). To check: add a stop, revert, then click a road to add a
waypoint, and add a stop. Also: add a stop, start moving a stop, revert.

## Run 2 (2026-10-07): undo

User: "looks good". stdout.txt for line 24618: edits recorded one per action (`edit 1..4`), each undo stepped back one
edit (`undid one edit`, stop counts 2 -> 3 -> 4), Shift+click reverted all (`reverted line 24618 (4 stops)`).
No errors, no crash (the addWaypoint regression did not recur). Not reported yet: slider drag, Auto Assign
Terminals, vehicles running, demolished station.
