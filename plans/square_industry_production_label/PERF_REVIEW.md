# Industry Production Label: performance review

## 2026-10-08

### Changes

| Where | Before | After | Gain |
|---|---|---|---|
| `content/production_label/production_label_pickup.tl` `pickup.aggregate` (`producers` helper + `consider`) | Every cargo-loading stop walked its group's whole reach (all cargo catchables: mostly town buildings with no output) × each catchable's outputs. A group with k loading stops walked its reach k times. | Each group's reach × outputs is flattened once per rebuild into the few producing `(stockList, cargo)` pairs; every stop walks only those. Engine reads unchanged (reach once per group, outputs once per StockList, same as before). Result identical (sets per line). | Pure-Lua rebuild time, offline harness (Lua 5.4 via lupa, stub adapter): 300 groups / 200 lines / 60 catchables per group: 6.7 → 3.9 ms; 1000 groups / 1500 lines / 300 catchables: 174 → 65 ms (the rest is the stub's own reads). Runs once per 15 s, only while the game is running and "Show line pickup rate" is on. |

Test added: `tests/square_industry_production_label/test_pickup.lua` "busy group with many non-producing catchables: reach and outputs read once, same sums".

### Examined, not changed

- **Industry label refresh** (`production_label.script.tl` `readView`, every 2 s per mounted label): one STOCK_LIST read, `getStockListInputOutputData`, and per output `getIndustryProductionData` (which re-reads STOCK_LIST, computes the boost and calls `getStockListInputOutputData` again). About 5 component reads for one output, 8 for two. The base stock pill on the same icon refreshes every 0.5 s with `cargo_util.calculateStockConfigs`, which is heavier, so the label adds well under the base cost. Dropping the up-front `getStockListInputOutputData` would need either an extra `getIndustryProductionData` call (worse: it computes the boost before the nil check) or a copy of base's minPriority logic (fragile). Not worth it.
- **Re-render**: `useStepStateTimer` compares with `table_util.deepEquals` by default (`engine_react_util.tl:126-157`), so the pill tree is only rebuilt when a number or state changes, not every 2 s.
- **Warehouse refresh**: 2 `getCargoLogValueDiffPerYear` per cargo type every 2 s, plus `cargoTypeRep.getAll()`. The base stock pill does the same `getAll()` walk with per-stock reads every 0.5 s (`cargo_util.calculateStockCargoCount`). Caching the cargo list at module level would survive a load with another mod set; not worth the risk.
- **`getModParams` in `hudIconFn`**: once per HUD icon mount (camera moves), not per frame. A cache was deliberately removed (rev 3 bug: settings kept across loads). Left as is.
- **Pickup cache staleness/lookup**: `pcall` + `os.time` + one table lookup per label per 2 s; GAME_TIME read only after the 15 s interval. Fine.
- **Pickup rebuild engine cost**: dominated by one STOCK_LIST read per cargo catchable (town buildings included) per rebuild. No API filters catchables to producers without a read, and caching outputs across rebuilds by entity id risks stale data after id reuse. Left as is; measure on a large save (below).
- **`mod.script.lua` loadConstruction modifier**: a few string ops per construction at load. Negligible.

### In-game check list

- [ ] Large save, "Show line pickup rate" on: pickup pills show the same numbers as revision 3 (compare a few industries with the line windows).
- [ ] Set `pickup.DEBUG = true` once on a large save and note the "cache built in N ms" line; no visible hitch every 15 s. Set it back to false.
- [ ] No new warnings from `square_industry_production_label` in stdout.
