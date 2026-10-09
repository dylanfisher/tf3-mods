# Line Editor Undo (`square_line_revert`): plan

**Name:** the display name is "Line Editor Undo" (modinfo, cover, description, feedback messages). The modId, folder and
file names stay `square_line_revert` / `line_revert` (renamed from "Line Revert" on 2026-10-08 before the first upload).

A button in the line manager, left of the Auto-Rename "A+" button, that works as a **line undo**: each click undoes
one edit of the selected line's stops, and Shift+click puts them back the way they were when you opened that line.
It's for "I clicked or deleted a stop by accident and don't remember which". A **Redo** icon button right of Undo
re-applies undone states one at a time.

**Status (2026-10-07):** probe done (`PROBE.md`, `mods/square_line_revert_probe`). Phase 1 code done (`mods/square_line_revert`, tests pass, check/validate clean except the missing cover). Reworked from a single snapshot to an undo history (same day); verified in game (TESTING.md run 2: step undo, Shift+click revert all, no crash). Phase 2: undo icon done (base `::/gui/node_editor/icons/undo.tga`, not yet seen in game). **Redo** added
(2026-10-08): second icon button right of Undo, per-session redo stack, unit-tested (57 tests), not yet tried in game
(TESTING.md "Redo"). Next: the remaining phase 2 edge cases, then phase 3 (cover, release).
**Phase 3 (2026-10-08):** renamed to "Line Editor Undo"; cover (`branding/mods.js`, accent `#C964E8`), three gallery
slides (`branding/shots.js`) and description done; validate/check/test clean. Next: upload.

## What the probe proved (PROBE.md, run 1)

- A button can be mounted **left of A+** in `LinePanelActionButtons`. To do it, a `react-replacement-config`
  doReplace wraps `button_react_util.makeIconToggleButton` and matches the A+ icon path
  `::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga` (manager_window.tl:3520, :6317).
- The manager's `commonParams` can be captured by wrapping `line_util.makeLineActionDescriptor`. From them:
  - the line being edited is `commonParams.lineState:old().entityAndRevision.entity`;
  - the editor's own path is `lineState:old().path`;
  - the selection is `lineManagerStateRef:get().lineListEntitiesSelected`.
  Precedent: zhenya_auto_assign_terminals `aat_eow.script.lua:625-698`.
- The editor **commits every edit immediately** with `makeLineUpdateCmd` (manager_window.tl:6531-6561, addStop
  :6767, removeStop :6791, moveStop :6851). Pressing R after a deletion showed the line already changed, so
  the snapshot must be taken **before the first edit**, as soon as a line is shown in the panel.
- The full stop data is readable with `getComponent(line, LINE)`: stationGroup, station, terminal,
  alternativeTerminals, loadMode, min/max/maxAdditional waiting time, waypoints and stopConfig. The line
  component also carries customFilters and reservationPriority.
- Open: one click reported a new entity id (24050) for "Line 1" with the stops reversed. This is probably a
  new line built by hand, but it isn't confirmed. The design below doesn't depend on the answer.

## Decisions

| Topic | Decision |
|---|---|
| Placement | Row reads [Undo][Redo][A+][paint][Buy Vehicles]. Icon buttons left of A+ in the line panel's action row, same `vehicle-button, secondary` class. Only in `LinePanelActionButtons` (single line); none for multi-select. |
| Icon | Base `::/gui/node_editor/icons/undo.tga` (gui.zip `gui/node_editor/icons/undo@2x.tga`, a 48x48 greyscale mask like `symbol_autorename@2x.tga`), in a `Button` + AutoFit `ImageView` as `button_react_util.makeIconButton` (button_react_util.tl:31-55). A Button because undo is one-shot; `line_revert.css.lua` copies the unchecked-toggle colours (builtin.css.lua:162-247) so it looks like A+ and the paint bucket. No generated icon. |
| Undo granularity | A slider drag in the cargo window (waiting time, max load) commits on every value change (cargofilter_window.tl:257-265), so one drag is several undo steps. **By choice: no coalescing.** Each step is a real committed state, and Shift+click still reverts everything. |
| What is reverted | **One edit per click (undo).** Each state is the whole LINE component as the base editor sends it: `stops` (every field, deep copy), `customFilters`, `reservationPriority`. Name, colour and vehicles are untouched. The editor commits every action as one `makeLineUpdateCmd` (one `reactLineCommit` per action, manager_window.tl:6714-6992), so each change the button's step sees is one history entry. A click restores `history[#history-1]` and pops the top. **Shift+click** (`IA_PRECISION_MODE`, as aat_eow.script.lua:670) restores `history[1]`, "revert all". |
| History | Per session, GUI memory only. `history[1]` = the line when the session started (first time the panel renders with line X as the edited line, before any click can reach the editor). Each step: live line ≠ last entry (`core.equal`) → push. Cap 50: the oldest edit is dropped, never `history[1]`, so revert all always reaches the start. Pure logic in `line_revert_core.lua` (`newHistory`, `observe`, `beginUndo`, `finishUndo`). |
| Session end | The history and the redo stack are dropped when the panel shows a different line or the manager closes. Re-opening the line starts a new session. Kept in GUI memory only and never saved. |
| Enabled state | Disabled (greyed, no fade) while `#history <= 1` or an undo is in flight. Tooltip: "Undo: <diff of the top state vs the one before> (N changes since you opened this line). Shift+click: revert all." N counts edits dropped by the cap too. |
| After revert | Undo: the top entry is popped. Our own command is not recorded as an edit: `expected` = the state sent, the old live state (`stale`) is ignored until the engine applies it, and the live line equal to `expected` clears it. An edit by the user before the engine applies the undo is recorded normally. A refused command puts the popped entries back (plus edits recorded since). Revert all leaves `history = {history[1]}`. Every send resets the editor's `{"SEGMENT", n}` mode (crash fix, TESTING.md "Regression"). |
| Redo | Per-session `redo` stack beside `states` (core `beginRedo`, `redoTarget`, `canRedo`; `finishCommand` for both). Undo pushes the state it leaves onto `redo`; revert all pushes every undone state, top first, so redo steps forward one state at a time. Redo pops the top, sends it, and pushes it back onto `states`. **Any edit recorded by observe** (not our own in-flight command) **clears `redo`**, also one made while an undo/redo is in flight. Same send path as undo (`send(kind)`): missing-station check, `resetEditorMode`, `expected`/`stale`, and a refused command restores both stacks (redo stays empty if an edit was recorded meanwhile). Both buttons are disabled while any command is in flight. Cap 50 holds for `redo` too (trimmed from the far end); the cap's dropped count is parked while an undo reaches `states[1]` and comes back on redo. Shift+click on Redo is a plain redo. |
| Redo button | Base `::/gui/node_editor/icons/redo.tga` (gui.zip `gui/node_editor/icons/redo@2x.tga`, next to undo@2x). Second recipe `SquareLineRedoButton` from the same `makeButtonRecipe` as Undo (same Button + AutoFit ImageView, class), and `line_revert.css.lua` adds every rule under both recipe scopes (no fade included). Mounted by the same A+ wrapper: one horizontal BoxLayout [Undo, Redo, A+]. Disabled when the stack is empty ("Redo: nothing to redo"). Tooltip "Redo: <diffSummary(current, redo target)> (N more)", N = redo steps left after this one. |
| Confirmation | None. The revert is one click and itself revertible by hand. Feedback goes through the manager's `commonParams.addFeedback` if it fits, otherwise a log line. |
| Safety | A stationGroup or station in the snapshot no longer exists → no send, show a message. Line entity gone → button disabled. Mission-protected lines (`line_util.isStopProtected`) → hidden. Check the command's `success` flag. |
| Saves | GUI-only. No game script and no state in the savegame, `severityAdd`/`severityRemove` = None, cosmetic. Safe to add or remove at any time. |
| Coexistence | Wrappers read the current module function inside doReplace, so they chain with Auto Assign Terminals (which also wraps `makeLineActionDescriptor`) and any other wrapper. Every wrapper body is in pcall and falls back to the original node. |

## Architecture

```
mods/square_line_revert/
  mod.json, _metadata/{modinfo.json, description.html, 0.png}
  content/line_revert/
    line_revert_replace.res.lua   react-replacement-config -> line_revert.script@doReplace
    line_revert.css.lua           button look (unchecked-toggle colours, no fade)
    line_revert.script.lua        wrappers, snapshot store, button, send + feedback (GUI thread)
    line_revert_core.lua          pure: snapshot <-> plain tables, equality, diff summary. Unit-tested.
tests/square_line_revert/test_core.lua
```

- **Snapshot** = plain Lua tables copied field by field from the userdata (`Engine.Component.Line`). A
  reference would follow the live line.
- **Restore** = `api.type.Line.new()`, stops rebuilt with the same constructors the base uses
  (manager_window.tl ~6510-6561, `line_util.autoAssignTerminals` is NOT re-run: the exact terminals are restored),
  then `api.cmd.sendCommand(api.cmd.makeLineUpdateCmd(line, comp), cb)`.

## Phases

### Phase 1: working revert (text button)
1. Scaffold `square_line_revert` (author square, Script Mod tag, description.html with Changelog).
2. `line_revert_core.lua`: `snapshot(lineComp)`, `equal(a, b)`, `diffSummary(a, b)`, undo history. Offline tests with fake components.
3. `line_revert.script.lua`: the doReplace wrappers (from the probe), snapshot-on-first-render keyed by line
   entity, button (text label for now) enabled when it differs, revert via makeLineUpdateCmd with a callback log.
4. Find in the base how a stop is built for the update (`api.type.LineStop`? the stop constructor in
   manager_window.tl / line_util) and how waypoints, alternativeTerminals and stopConfig are set, so every field round-trips.
5. `make check`, `make test`, `make validate`, `make link`. Write `TESTING.md` with the in-game checklist:
   delete a stop then revert, add a stop then revert, reorder then revert, change load mode / waiting time then
   revert, a line with vehicles running, switch lines (snapshot resets), close and re-open the manager, a
   demolished station in the snapshot, and with Auto Assign Terminals enabled.

### Phase 2: polish
- ~~An undo icon instead of text~~ **done**: base `::/gui/node_editor/icons/undo.tga`, see Decisions "Icon".
- Diff tooltip and translated strings (`strings.lua` / `_()`).
- Edge cases from the phase 1 test run: vehicle stop indices after the stop count changes, entity replaced, protected lines.

### Phase 3: release
Cover (`branding/mods.js` + `make covers`), screenshots, description, `make validate`, the tf3-mod-validator agent, upload.
Disable and unlink the probe before uploading.
