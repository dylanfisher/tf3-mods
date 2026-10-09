# Line Editor Undo probe (mods/square_line_revert_probe)

DEV ONLY - never upload. Read-only: buttons only log, nothing changes a line.

Question: where can a "revert this line to before I started editing" button live?

| Probe | Where | Mechanism | Precedent |
|---|---|---|---|
| A `toggle` | **"R" button left of A+** in the line manager action row (LinePanelActionButtons) | wrap `button_react_util.makeIconToggleButton` in a `react-replacement-config` doReplace | zhenya_auto_assign_terminals wraps `builtin.Button` the same way |
| B `params` | (no UI) captures the manager's `commonParams` to read the edited line | wrap `line_util.makeLineActionDescriptor` | aat_eow.script.lua:625-674 |
| C `eow` | "LRPROBE C" row in the **line window** (click a line in the world) | official `LineEowExtensionPoint` plugin | line_eow_basics.res.lua, aat_line.res.lua |
| D `event` / `eow-event` | (no UI) hears "openVehicleManager" | `react.onEvent` in a mod plugin | manager_window.tl:8447 |

## Run

1. `make link`, start the game, enable **DEV Line Revert Probe** in a test save (Auto Assign Terminals on too is fine and tests coexistence).
2. In a terminal:
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered LRPROBE`
   Expect `loaded`, `toggle installed wrapper`, `params installed wrapper` at GUI start.
3. Open the line manager, select a line, enter its stop editor (the view in the screenshot). Look for **R** left of A+. Click it.
   Expect `toggle CLICK in LinePanelActionButtons`, `managerParams yes`, `editedLine <id>`, then one `stop` line per stop.
   Also check: is R there in the plain line list (no line selected / several selected)? What does `editedLine` say then?
4. Click a line in the world (line window). Look for the **LRPROBE C** row and click it. Expect `eow CLICK line <id>` + stops.
5. In that window press **Manage Line**. Expect `event heard openVehicleManager openWithLineEntity <id>` (and/or `eow-event`).
   Also open the manager from the bottom bar: expect `openWithLineEntity nil`.
6. Edit a stop, click R again: does `editedLine` stay the same and the stop dump show the change?

## Record

Paste the `[LRPROBE]` lines (or a summary) and screenshots of R / LRPROBE C here, plus any `ERROR` lines or UI glitches
(R misaligned, A+ row overflow, crash). Crash: see memory note on crash dumps; disable the probe first.

## Results

### Run 1 (2026-10-07)

- **A works.** R appeared left of A+ in the stop editor; click logged
  `toggle CLICK in LinePanelActionButtons managerParams yes editedLine 24047 editorPathVias 2`, then both stops
  (group/station/terminal/alts/loadMode/wait 0 600 30/waypoints/stopConfig). No errors, no crash.
- **B works.** `params captured commonParams in ActionFn` as soon as the manager opened; edited line = selected line.
- **D works.** A mod plugin hears `openVehicleManager` (fired with target nil). Opened from the bottom bar:
  `openWithLineEntity nil`, as expected.
- **R after deleting a stop works.** Same entity 24047, `editorPathVias 1`, `stops 1` (stop 2, group 24046, gone).
  So the editor commits immediately and R sees the live line; a snapshot must be taken before the first edit.
- **Open question:** a later click showed `editedLine 24050` "Line 1" with the two stops reversed (24046, 22328).
  New entity id: was that a new line built by hand, or did the editor recreate the line? A revert keyed on the
  entity id would lose track if the editor ever does that.
- Not yet checked: C (line window row), Manage Line with a line id.
