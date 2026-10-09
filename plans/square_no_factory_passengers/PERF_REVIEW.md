# square_no_factory_passengers: performance review

## 2026-10-08 (revision 3)

### Hot path
The only runtime code is the wrapper around `line_util.autoLoadConfig` (GUI thread). It runs once
per line-editor edit (new line, add/remove/move stop, add waypoint; `manager_window.tl:6712`, `6786`,
`6845`, `6879`, `6963`), never per frame or per tick. No game script, no update/HUD script, no state.
For scale: the base `autoLoadConfig` itself already fetches every stop's cargo catchables and runs
`getInputOutputStocksForStockList` (several component reads) on each of them
(`cargo_util.tl:544-563`, `line_util.tl:551-590`), so the mod's work is a fraction of the base cost.

### Change
| Where | Before | After | Gain |
|---|---|---|---|
| `content/no_factory_passengers/nfp_logic.lua` `logic.decide` / `logic.decideLine` | Industry test first: every group fetched its cargo catchables and, at a town stop (no industry), called `getComponent(INDUSTRY)` on every catchable (every town building in reach) before giving up. Passenger catchables fetched only for industry groups, or in the line pass. | Homes test first: fetch passenger catchables, stop at the first `TOWN_BUILDING`. Cargo catchables are fetched and scanned only for groups with no homes. The line pass reuses each group's home result instead of refetching. | Synthetic 10-stop town line, 200 buildings per stop (`scratchpad nfp_bench.py`): entity tests per edit 2000 -> 10, catchable fetches 10 -> 10. Factory/dock groups: same work as before. Real-world: removes O(buildings in reach) component reads per town stop per edit; a few ms per edit on big-city lines at most, invisible on small lines. |

Behaviour is unchanged: a group with a home in reach is never cleared (old: `decide` kept it; the
line pass skipped groups with an industry and recomputed `not anyHome` for the others, which is
false for a group with homes). The only difference is the internal `industry` flag for groups
with both homes and an industry (now false, it was true), which is read only for the log text of
cleared stops, and such groups are never cleared. Tests updated: `test_logic.lua` (new fetch
order, 3-value `decide`), `test_patch.lua` (fetch/read counters, town-line test).

### Examined, not changed
- `fixLine` loop: one `STATION_GROUP` read per distinct group, small per-stop tables; trivial next
  to the base function.
- `log.message` per cleared stop: only for factory/dock stops, a handful per edit.
- `pcall(fixLine, line)`: one per edit, not a hot loop.
- `cargo_util.getPassengerCargoTypeId()` per call: one call per edit.
- Install (`doReplace`): once per game load.

### In-game check
1. TESTING.md sections 0-5 still pass (factory stop OFF, factory -> dock both OFF, town station
   with a factory in reach keeps passengers, town stops never logged).
2. Edit a long bus/tram line through a big city: adding or moving stops feels no slower than
   without the mod.
