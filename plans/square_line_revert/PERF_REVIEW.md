# Line Editor Undo: performance review (2026-10-08)

## Hot paths

| Path | Frequency | Before |
|---|---|---|
| `computeView` via `useStepState` in both button recipes | every GUI step while the line manager shows one selected line | twice per step: `getComponent(LINE)`, full `core.snapshot` (one table per stop, alt terminal, waypoint, stop config list), `deepEqual` vs the newest state, plus `core.diffSummary` for the Undo and Redo tooltips (another full `deepEqual` + counting + string building) |
| `send` (click) | per click | cold, unchanged |
| wrappers `makeLineActionDescriptor` / `makeIconToggleButton` | per render of the manager rows | a field check / string compare, unchanged |

## Changes (revision 2)

| Where | Before | After | Gain |
|---|---|---|---|
| `line_revert_core.lua` `core.matchesLive`, `core.observeLive` | every step built a full snapshot of the live line to compare it with the newest state | walks the live component in place and compares field by field with the newest state; only snapshots when something differs. `observeLive` then feeds the stored state itself to `observe`, which decides by `deepEqual` only, so it records exactly what it did before | no per-step allocation (was ~42 KB/step at 10 stops, ~166 KB/step at 40 stops, offline) |
| `line_revert.script.lua` `cachedDiff` | `diffSummary` for both tooltips every step | remembered per slot for the last (a, b) state pair; states are never mutated once stored | tooltip text built only after an edit / undo / redo |
| `line_revert.script.lua` `stepView` | each button recipe computed the whole view (line read + compare) | Undo's step computes it, Redo's step reuses it when Undo produced a new one since Redo last looked, else computes its own. Cleared when the action row is built | one `getComponent(LINE)` per step instead of two |

Measured offline (lupa / Lua 5.4, plain tables, 4 waypoints per stop, one edit in the history; excludes `getComponent`):
10 stops 325 us -> 18 us per step, 40 stops 1262 us -> 57 us per step. In game, userdata field reads cost more and
are still done once per step, so the real gain is smaller but the allocation and double read are gone.

Tests: `matchesLive` is checked against `equal(snapshot(comp), snap)` for 37 single-field and structural
mutations in both directions; `observeLive` against `observe(snapshot)`; the script test counts one LINE read per
step and no `diffSummary` call on unchanged steps.

## Examined, not changed

- Gating the poll on `api.engine.getRevision(line)`: would skip even the walk, but which `num[i]` moves on a LINE
  component update is unverified in game; a miss would silently lose undo steps. Not worth the risk untested.
- `isProtected`, `selectedCount`, `editedLine`: table lookups per step, negligible.
- `ensureSession` reads the line twice at session start: once per line opened, cold.
- `core.beginUndo` / `finishCommand` array copies: per click, cap 50, cold.

## In-game check

- [ ] Log shows `[LineRevert] edit <n>` exactly once per editor action (no change in behaviour).
- [ ] Undo / Redo enabled state and tooltips update right after an edit, an undo and a redo (Redo may lag one frame at most).
- [ ] Our own undo/redo is still not recorded as an edit; a refused command still restores both stacks.
- [ ] Switching lines and closing/reopening the manager: no stale tooltip from the previous line.
