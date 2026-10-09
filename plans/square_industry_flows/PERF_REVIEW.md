# Industry Flows: performance review

## 2026-10-08

Scope: the whole mod (`flows_gather.tl`, `flows_model.tl`, `gui/flows_window.script.tl`). The earlier pass (PLAN "Performance (2026-10-07)") already handled the GUI side: no poll while the window is shelved, an unchanged poll does not re-render, the LayerConfig and action function are cached by view identity, and the cargo icon, type name and cargo name lookups are cached.

### Hot paths

| Path | Frequency | Cost |
|---|---|---|
| `poll()` = `gather.readWorld` + `model.groupTypes` + `model.buildView` + 2× `deepEquals` | every 2 s while the panel is open and visible | engine: per industry 1 system call + 3 `getComponent`, per town 1 `getComponent`; per link 1 `getCargoLogPerYearForTarget`. Lua: dominated by `buildView` |
| `apply(..., rebuild = true)` → `model.buildView` | every type tick, Clear, toggle click | `buildView` |
| render (`typeList`, rows, `hudPreFilter`) | per keystroke and per changed poll | `typeList` 0.015 ms for 25 types; negligible |

`buildView` scales with the **link count**, which is map-wide (potential links have no distance limit): a selected food plant type with ~150 towns already gives thousands of links, and every one gets a `flowCount` call, a record and a place in the sort, even though at most 400 are drawn.

### Changes

| Where | Before | After | Gain (offline, Lua 5.4 / lupa, mean of 30 runs) |
|---|---|---|---|
| `flows_model.tl` `buildView` `add()` de-dup | a string key `tostring(from)..">"..tostring(to)..":"..tostring(cargo)` built and stored for **every** link | recorded (nested `from → to → cargo` tables, no strings) only when both ends are selected industries: the only case a link can be seen twice (one selected industry yields each link once; a link with an unselected end is only reached from its selected end) | see below |
| `flows_model.tl` `buildView` link records | two position tables copied per link, also for links dropped by the cap | copied after the sort, only for the ≤ `MAX_LINKS` links kept | see below |

Synthetic worlds (`chain` of types, town needs on every third cargo, every 5th link active):

| Case | Links | Before | After |
|---|---|---|---|
| 300 industries / 15 types / 150 towns, 3 types selected | 4 200 | 10.7–10.9 ms | 7.9–8.8 ms |
| same, 6 types selected | 8 400 | 21.7–22.6 ms | 15.2–17.4 ms |
| 800 industries / 20 types / 300 towns, all selected | 78 400 | 258–288 ms | 191–199 ms |

About 25–30 % less Lua time per poll and per click. Behaviour is unchanged: same links, same order, same first-seen `input` flag, same `flowCount` calls (new test `buildView: de-dup keeps the first sighting (input flag) and asks flowCount once` passes against both the old and the new code).

### Examined, not changed

- **The sort** of all links (≈ 35–40 % of the remaining `buildView` time on big selections). Only the first 400 are drawn, but total order is what makes an unchanged map give an equal view (no re-render). A bounded-heap selection would save maybe a quarter of the sort for extra code; not worth it.
- **`flowCount` for every link** (the main engine cost on big selections): needed for the `total` / `active` counts in the summary (earlier decision, PLAN).
- **Caching type key / position per entity** in `readWorld`: entity ids can be reused (earlier decision, PLAN). The `CONSTRUCTION` component read per industry per poll remains the main fixed cost of an open panel; at a few hundred industries every 2 s it is acceptable.
- **`hudPreFilter()` every render** (`getGuiSaveData`): renders happen on input and on changed polls only, not per frame.
- `groupTypes` (0.4 ms for 800 industries), `typeList` / `search` (0.015 ms), `deepEquals` of a ≤ 400-link view: negligible.

### In-game check

- [ ] Panel opens, tick one type: arrows appear at once, summary counts unchanged against revision 1 on the same save.
- [ ] Two types that supply each other (e.g. forest + saw mill, or two chained types): the shared arrows draw once, in the same colour as before (input vs output).
- [ ] A big selection (several types on a large map): no hitch every 2 s while the panel is open; the capped line "Showing 400 of N" still shows the right N.
