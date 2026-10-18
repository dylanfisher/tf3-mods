# Supply Gap Overview: performance review

Status: changes done 2026-10-09 and shipped; the in-game confirmation (`TESTING.md` step 9, DEBUG run) is
still open. Stays here (not `history/`): mod code and `tests/square_supply_gaps/test_perf_bench.lua` link it.

## 2026-10-09

Context: the whole tick runs on the **Main (GUI) thread** (`react.enqueueJoin` from `onStepTimer`, 1 s),
so every ms is a frame hitch, and the overlay is on from game load. Spike numbers (before Phases 2b/2c/2d;
71 stations, 1654 of 3775 buildings with needs, 300 markers): avg ~10 ms, max 20-48 ms, first tick 24 ms.

**Measuring caveat found:** those numbers came from `os.clock()`, which on macOS is the **process CPU time
of all threads**. While the simulation and render pools are busy, a 3 ms main-thread section can read as
10+ ms. The spike numbers (and the `BUDGET_MS` halving they triggered) probably overstate the real cost.
The overlay now times with `api.type.Clock` (wall clock in µs, verified on the Main Thread in
`plans/zhenya_auto_assign_terminals/run1.log`: `side=gui ... timer=clock`), `os.clock` only as a fallback.

### Per-tick costs before this review

Estimates at the spike size (1x) and ~5x (355 stations, 200 lines, ~19k buildings). Counts come from the
offline bench (`tests/square_supply_gaps/test_perf_bench.lua`, real gather/cache/model/scope against a fake
engine). Engine-call unit costs in game are unknown; the counts are what changed.

| Stage | Work per tick (camera still, "Only towns in view") | 1x | 5x |
|---|---|---|---|
| lines | `getStationGroup2LineStopsMap` + one `LINE` read per line + `STATION_GROUP`/`STATION` per stop (memo per call); every load vector walked | 1 map, 40 LINE, ~110 SG + 58 ST | 200 LINE, ~535 SG + 278 ST |
| groups | `STATION_GROUP` per delivering group (`groupStations`), every tick | (in the SG count above) | |
| catchment | `getStationCatchables` round robin, `STATIONS_PER_TICK = 25` (a 71-station map refreshed every 3 s); list copy of ~150 ids each | 12-25 | 25 |
| building map | `getTown2BuildingMap` (all ids) + `flatten` (two new arrays of every id + town sort) | 3775 ids | 19k ids |
| boxes | first tick: one `BOUNDING_VOLUME` per building **of the whole map**, unbounded; then an O(n) "any new id?" scan every tick | 3906 at load | 19k at load (bench: 21 ms Lua alone) |
| scope | camera (8 `screen2World` + `getHeightAt`), towns SAT test; then 3 more O(n) loops over every id (scoped id list, pending count, round-robin pick list) | 3x3775 | 3x19k |
| building reads | in-view ids: urgent up to 800/tick, else n/10 round robin; each = `TOWN_BUILDING` + `STOCK_LIST` + `getStockCount` per need + `PERSON_CAPACITY` + **`BOUNDING_VOLUME` again for every building without needs** (pos only cached for buildings with needs) | ~13 x 4-5 calls | same (scoped) |
| model | `model.compute` every tick: reach index over every catchable (71 x 150), then every counted building with allocations | full | full |
| markers | `markerPlan` sorts every gap with a closure; `markers.apply` diff (sorts 300 keys) | every tick | every tick |
| labels | `areas.labels`: chips for every area (sort per area), nearest 30 | every tick | every tick |
| window | `snapshot` every 0.5 s while open: cargo rows sort, count of shown markers; `useStepStateTimer` deepEquals | small | small |
| HUD | each visible town icon: `rowsFor` + deepEquals every 1 s (plain Lua data) | small | small |

Bench, Lua only (Lua 5.4 offline, engine calls free), before: **1x scoped steady 1.07 ms, first tick 16 ms**;
5x scoped steady 4.95 ms, first 21 ms; 1x whole map 5.75 ms; 5x whole map 26 ms.

### Changes

| Where | Before | After | Gain |
|---|---|---|---|
| `sg_gather.lines(lc)` + `SupplyGapsLineCache` | every LINE read every tick | stop map read every tick; a line is re-read **at once** when it is new or its (group, stop index) set changed (stop added / removed / moved), else ceil(n / `LINE_EVERY` = 10) round robin; returns the same list + `changed = false` when nothing differs | 40 → 4 LINE, ~170 → ~28 SG/ST reads a tick (1x); 200 → 20 LINE (5x) |
| `sg_overlay.updateGroups` | `groupStations` for every group every tick; groupCargo rebuilt every tick | new groups at once, others ceil(n/10) round robin; groupCargo only when lines / "Count stops without a line" changed | ~70 → ~7 SG reads (1x) |
| `sg_cache.step(..., cap)` + `refreshCap` | 25 catchment refreshes a tick | at most ceil(n / `STATION_CYCLE` = 10) (min 5): each station refreshed about every 10 s, like buildings; an unchanged list keeps its table and reports `changed = 0` | 25 → 8 calls (1x); new stations still fetched at once |
| `sg_gather.readBuilding` | `PERSON_CAPACITY` + `BOUNDING_VOLUME` for every building | only for buildings with needs (the overlay drops the rest) | 2 of ~5 reads saved for ~56 % of re-reads |
| `sg_gather.flatten(map, prevIds, prevTownOf)` | two new arrays of every id each tick | compare in place; unchanged → same tables, `false` | no allocation; drives the next row |
| `sg_overlay` building map | demolition pass when an id appeared or the count moved; "new id?" box scan over every id every tick; scoped id list, pending loop over every id | demolition pass and box pass only when the flat list changed; scoped id list (`sids`) rebuilt only when the list or the scope set changed; pending loop over the scoped ids only | 3 O(n_map) loops → O(n_in_view) |
| box pass (`readBoxes`) | every building box of the map in the first tick | resumable pass, ≤ `BOX_PER_TICK` = 2000 reads and ≤ `BOX_BUDGET_MS` = 3 ms a tick; only while "Only towns in view" is on (the whole-map mode doesn't need boxes) | first-tick spike gone (bench 5x scoped first tick 21 → ~8 ms); towns appear as their boxes arrive (1x: a tick or two) |
| `readBuildings` | up to 800 urgent reads in one tick | stops once the tick has run `READ_BUDGET_MS` = 6 ms (after `READ_MIN` = 100 reads); unread urgent ids wait for the next tick (pending, no partial counts) | bounded first tick / town-entry tick |
| model skip (dirty flag) | `model.compute` every tick | only when an input changed: a re-read building differs by `model.sameBuilding` (town, land use, needs, position, starved flag per need; stock counts and short streaks ignored), a catchment list changed, group cargo / stations changed, the order was rebuilt, selection / "Include in-range but empty" changed, or the overlay was switched on | bench 1x camera still: 21-30 of 30 ticks skip |
| marker plan | `markerPlan` + `markers.apply` every tick | only when the view changed, or the camera moved **and** there are more gaps than `MAX_MARKERS` (else the set can't change); a failed marker call retries next tick | no plan/diff while panning a normal town |
| `model.markerPlan` | sort of every gap | > 2x cap gaps: quickselect the cap-th distance, sort only those within it (ties kept: identical result, randomized test against the full sort) | O(g + cap log cap) instead of O(g log g) |
| `sg_areas.candidates` / `nearest` | chips of every area recomputed every tick | chips per (view, selection) kept; camera moves only re-pick the nearest 30, and only when there are more than 30 candidates | labels ~free while nothing changes |
| `overlay.clock` | `os.clock` (CPU time of all threads on macOS) | `api.type.Clock` wall clock, `os.clock` fallback; PERF line says `clock=wall|os` | budgets and BUDGET_MS halving measure the real main-thread time |
| DEBUG PERF line | max/avg + counts | adds `split(avg/max)=` per stage (lines, catch, map, boxes, scope, read, model, markers, labels), `reads=`, `boxReads=`, `boxPass=`, `computes=`/`skips=`, `plans=`, `labelBuilds=`, `clock=` | in-game confirmation |

Bench after (same world, Lua only): **1x scoped steady 0.4-0.6 ms (was 1.07), first tick 3-5 ms (16)**; 5x
scoped steady ~2 ms (4.95), first ~8 ms (21); 1x whole map ~2.5 ms (5.75); 5x whole map 12-18 ms (26: still
1800 round-robin reads a tick by design, capped in game by `READ_BUDGET_MS`). Engine calls a tick, 1x
scoped, camera still: ~450 → ~110 (LINE 40 → 4, STATION_GROUP 112 → 17, STATION 58 → 11, catchment
12-25 → 6-8, no extra PERSON_CAPACITY / BOUNDING_VOLUME for buildings without needs).

**Expected in-game tick** (scoped, camera still, spike map): ~1-3 ms wall, dominated by the building-read
slice (~13 buildings x 4-5 calls) and the stop-map read; model/markers/labels mostly skipped. First tick
after load: lines + one catchment call per delivering station (not budgeted, see below) + ≤ 3 ms boxes +
reads up to the 6 ms budget, so roughly 8-12 ms once, instead of a map-wide box pass (3775 reads) plus up
to 800 building reads.

Behaviour changes (all bounded, documented in code):
- Line cargo-config / terminal edits that don't change the stop map show within ≤ 10 s (stop added to a
  line: still next tick). Station-group membership changes: ≤ 10 s.
- Catchment refresh of existing stations every ~10 s instead of ~3 s on small maps (new stations still at
  once).
- With "Only towns in view" a town on screen right after load can take a few ticks to count (its boxes /
  reads are spread). Whole-map mode skips the box pass.
- Under the read budget, round-robin re-reads skipped in a heavy tick wait for the next cycle.

Tests: 155 (was 136): `test_model` (quickselect vs full sort, `sameBuilding`), `test_areas` (candidates +
nearest = labels), `test_cache` (unchanged list kept / `changed`, `cap`, `refreshCap`), `test_gather` (line
cache: first read, round robin, changed stop set, cargo change, removed / failing lines; flatten with prev;
no extra reads without needs), `test_overlay` (skip when unchanged, streak threshold, catchment / line
change, no plan while panning + off/on re-send, read budget, box pass budget, no box pass on an unchanged
map). Contract change: the "failing planner" overlay test also stubs `areas.candidates` / `areas.nearest`.
Bench: `SQSG_BENCH=1 make test MOD=mods/square_supply_gaps ARGS="-k bench"` (skipped otherwise).

### Examined, not changed

- **First-tick catchment calls**: every delivering station not cached is fetched in the tick it appears
  (tested contract: a stop just added to a line shows next tick). At load that is one call per delivering
  station (71 at the spike size). Budgeting it would delay new stops. Left; watch the first PERF line's
  `catch` split.
- **Whole-map mode** ("Only towns in view" off): re-reads n/10 buildings a tick by design (each re-read
  every 10 s). Bounded by the read budget now; on very large maps it simply cycles slower.
- **`getTown2BuildingMap` every tick**: needed to see new / demolished ids next tick (rebuilt town
  buildings get new ids at the same count, so the count alone can't detect them). The compare is cheap
  now; the engine-side map copy remains.
- **`api.engine.getRevision`** as a change counter for lines: `num[1]` is the creation revision
  (`plans/square_problem_radar/PLAN.md`, base `greenification_display.script.tl:80`), not a modification
  counter. Not used; the stop-map signature + round robin replaces it.
- **Window snapshot** (`overlay.snapshot`, 0.5 s while open): a sort of ~10 cargo rows and a count of
  ≤ 300 markers; `useStepStateTimer` deepEquals only re-renders on change. Negligible.
- **HUD label rows** (`sg_labels.lua`): one `rowsFor` lookup + deepEquals per visible town icon a second,
  plain data. The store keeps its identity while unchanged now. Negligible.
- **`stepCheck` per frame**: one `os.time()` compare; one `GAME_SPEED` read a second. Negligible.

### Future option: engine reads off the main thread

Base does `api.engine` reads on worker threads through parallel work items: `engine_react_util.useStepStateParallel`
→ `react.enqueueParallel(useFnName, params, join)` → `api.gui.react.enqueueParallelWorkItem` (`react.lua:56-65`;
`react.d.tl:401` "computes result in another thread via useFn(useFnName)(...) and applies it via enqueueJoin").
The worker functions read components, e.g. `town_util_parallel.script.tl:168` (`getComponent(..., LINE)`) and
`:277` (`GAME_SCRIPT`). Constraints: the function runs in **another Lua state** loaded by name
(`<file>.script@<module>.<fn>`), so it sees none of our module state; params and results must be plain data
("useFn() cannot return userdata", `town_util_parallel.d.tl:91`); the result is joined a frame later.
A port would send the tick's slice of building ids (+ prev streaks) and the due line / station ids, and get
plain records back; markers, camera and labels stay in the join. Not done now: no mod precedent in this repo,
an extra frame of latency, a new script file loaded by name, and the in-game cost after this review is
expected to be small. Revisit if the DEBUG run shows `read` or `lines` still dominating on large saves.

### In-game check list

TESTING.md step 9 (DEBUG=true run): `clock=wall`; camera still → `skips` most ticks, avg ~1-3 ms, max under
~8 ms; first lines after load show `boxPass=running` then `done` without a tick far above the rest; note the
largest `split` stage; no hitch while panning. Then set `DEBUG` back to `false`.
