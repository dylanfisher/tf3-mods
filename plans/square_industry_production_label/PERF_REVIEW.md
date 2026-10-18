# Industry Production Label: performance review

Status: current. Both rounds are in the code; their in-game check lists are still open. Mod code and tests cite this file by name.

## 2026-10-10: shared read cache, sliced pickup rebuild

### Evidence (SQPERF, desert save, 107 industries, 250 lines, 175 s, ctx=hud)

`read_industry` 23 204 calls (133/s over the session, ~220/s in the windows with labels on screen), 7.5 ms/s,
max 27 ms; `industry_render` 2116, `hud_icon_fn` 2437 (mount/re-render rate ~14/s); `pickup_rebuild` 11 calls,
avg 9.4 ms, max 27 ms. All `ctx=hud` lines carry one `vm=` id while the thread column moves over
"Main Pool 1..10": **one Lua state** for every HUD label of a load, called from varying worker threads.

### Root cause

Each label polls with `useStepStateTimer(readView, 2.0)`, plus one read per mount (`useStateLazy`). At 2 s a
single label per industry would be ~54 reads/s for 107 industries; the windows show ~220/s with only ~5
renders/s, so the reads are timer-driven and come to ~4 reads per industry per 2 s. The engine runs a
separate `HudIconMasterGame` (and with it our recipe and its timer) per HUD icon instance; base
`hud_icon_toolbox.tl:340-356` mounts the custom recipe for every icon of the first subconstruction,
independent of `params.index`, and the HUD may keep icons mounted beyond the visible ones (both unverified).
Which of these multiplies it is not visible from Lua, but every extra poller reads the **same entity** and each did
the full read (1 + 2 per output STOCK_LIST conversions, `GetIndustryBoost`, base `getStockListInputOutputData`
twice per output). Base polls its own stock pill per icon at 0.5 s with no cache; we already poll 4x slower.

### Changes

| Where | Change |
|---|---|
| `content/production_label/production_label_readcache.tl` (new) | Per-entity cache `{at, value}`, TTL 1.5 s, sweep of expired entries every 30 s. Plain module table: one Lua state, the engine runs one callback at a time in it and get/put never yield, so no torn entries. |
| `production_label.script.tl` `readIndustry` / `readWarehouse` | Labels read through the cache; the cached industry view has no pickup, each label adds its own (`model.withPickup`), so pickup-on/off labels share a read. Errors are not cached (each label still fails and warns once, as before). Clock: `api.type.Clock` (worker-thread safe), fallback `os.time`. |
| `production_label_model.tl` `model.withPickup` | Copies entries with `pickupValue`; equals `model.view(pds, cd, rates)`. |
| `production_label_pickup.tl` `newBuild` / `step` / `tick` | Rebuild as a resumable job. The first build runs at once (as before); later rebuilds run in ~4 ms slices, at most one per 100 ms (all labels' timer reads of a frame run back to back, so the gap spreads slices over frames), old rates served until the new set is complete, a build older than 3 s finishes in its next slice. Same result as one pass (tested). |
| SQPERF | `read_industry` / `read_warehouse` now time only the engine reads behind the cache; counters `read_cache_hit`, `read_cache_hit_wh`, `read_cache_new`; `pickup_rebuild` = one slice, counter `pickup_built` = completed rebuilds. |

Staleness introduced: a label may show a read up to 1.5 s old (TTL) at its poll, below the 2 s poll
interval. Pickup: a rebuild completes up to ~1 s later than before (vs its 15 s interval).

### Expected in game

`read_industry` n drops to about one per industry per ~1.5-2 s of labels on screen (from ~4): ~55/s instead
of ~220/s in busy windows, ms/s from ~7.5 to ~2. `read_cache_hit` ≈ the old read count minus the new one.
`pickup_rebuild` max from 27 ms to ~4-8 ms (n rises, one per slice; `pickup_built` ≈ old n).

### In-game check list

- [ ] DEV "SQPERF: all mods" on, desert save, 5 min over industry clusters and warehouses, `make perf ARGS=--last`.
- [ ] Production numbers still tick (a processor's Current Production changes within ~2-4 s of the window's).
- [ ] Start a line loading at an industry: the pickup pill appears within ~15 s, as before.
- [ ] Warehouse in/out pills update as before.


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
