# Industry Production Label (`square_industry_production_label`): plan

Shows each industry's headline production number from its industry window ("Current Production" when the window has it, else the "Production" capacity) on its in-world HUD label, in a pill below the output stock pill: `[factory icon] 34`. The pill is green while the output is producing and neutral dark while it is idle.

## Decisions (2026-10-06)

| Topic | Decision |
|---|---|
| Value | **Revised again 2026-10-06 (third in-game test):** the window's *headline* number. That is `round(actual)` ("Current Production") when `actual ~= nil`, e.g. 112 on a cement plant whose window shows 112 over "Max. 175"; the user said the label must show the current production, not the 175. Otherwise it is `round(total)` (capacity), which is the only number the window shows for raw producers (fishing ground 34). Entries still need capacity > 0. *Previous rule, kept for context:* **Capacity, always** (revised 2026-10-06 after the first in-game test). It is the window's `max = math_util.round(productionData.total)`, from `industry_util.getIndustryProductionData(entity, false, false, i, true).total`, for each output `i` of `industry_util.getStockListInputOutputData(entity, false, false, 0)`. The base functions are reused through `ug_require "::/gui/main/industry_util.tl"`, so the number always matches the window, boosts included. Shown whenever it rounds to > 0. |
| Why not the live rate | On a brand-new game, a full (300/300), unserved fishing ground showed exactly one number in its window: **34**. The window draws "Current Production" only when `productionData.actual ~= nil`, but it always draws `max` (tooltip "Production"; headline font when `onlyOneProductionLine`) (`gui/entity_window/industry_react_util.tl:318-346`). For output-only rules (every raw producer), `getIndustryProductionData` sets `actual = nil` (`foundOutputFraction`, `gui/main/industry_util.tl:367-377`). So the 34 is `total`. The user: "I'd still expect to see a 34, perhaps in a different color/style to understand what the capacity is at a glance." |
| State | **Producing** when the live rate rounds to > 0; otherwise **idle** (nil, 0 or missing; this includes a full stock or no transport, if the engine reports 0 then). The live rate is `actual` when it is a number. Otherwise it is `stockList.cargoData[cargo].produceFrequency`, the same value `actual` would be (`industry_util.tl:333-339`). Without that fallback, every raw producer would be idle forever, because their `actual` is always nil. The label is never hidden for being idle. |
| Format | **Revised 2026-10-06 after the second in-game test** (the first pill showed `?110`: small, dark, grey text). One pill per output cargo (deduplicated), in `getStockListInputOutputData` order, built like the stock pill: `makeContentLabelIndictator{labelMode = "HudIconMain", labelFontColor = "Default", iconPath = ...}` (`hud_icon_toolbox.tl:78-84`). **No text prefix** (`model.PREFIX = ""`): `▲` is **not in the HUD font** and rendered as `?` in game (the Noto CJK `unicodeFontMap` fallback does not apply there). **Icon:** `model.CAPACITY_ICON = "::/gui/entity_window/icons/building_industry.tga"`, the icon the industry window draws next to its production figures (`industry_react_util.tl:715`, `industry_eow.script.tl:78`). Other base candidates were checked in `gui.zip`: `production_booster` (gear + arrow) reads as "boost", `building_industry_gear_30` is the map editor's generator button. From `model.ICON_MIN_OUTPUTS = 2` outputs on, each pill gets `{CAPACITY_ICON, cargo icon}` (a `{string}` iconPath becomes a horizontal BoxLayout of icons, `gui_react_util.tl:296-307`). **Size:** the icon gets `iconlabelindicator-icon-size,hud-icon` = 26x26 and the label `font-scale-annotation`, the same as the stock pill (`gui_react_util.tl:136-150, 283-291`, `gui_react_util.css.lua:28-30`), so height and text size match. **Text:** white (`labelFontColor "Default"`, no override) in both states. **State = background colour**, from scoped CSS on our wrapper class: producing = `Satisfaction.Happy` (shamrock, the base "good" colour, already a HUD pill background in `!hud-icon-layer !hud-icon-background!Normal`) mixed 30 % towards `NeutralDarkest` for white-text contrast, at the stock pill's `transparency.Low`. Idle = `NeutralDarkest` (the base neutral pill colour) at `transparency.Low` instead of the base Medium. No base `ShippingState` fits: all but Vehicle are the stock pill's `electricRoyal` blue (`gameplay_colors.gres.lua:13-18`), and Vehicle is black. Styles live in `model.STYLE_PRODUCING` / `STYLE_IDLE` (both without `shippingState`). |
| Save safety | Read-only and cosmetic: `severityAdd: None`, `severityRemove: None` (or `Warning`), `cosmetic: true`. No game script and no saved state. |

## Mechanism

- **Hook.** `HudIconMasterGame` (`base/content/gui/main/hud_icon_toolbox.tl:~160-372`) appends `desc.hudIconScript` as an extra child of the same HUD icon that shows the stock. It does this when `con.subconstructions[1] == params.entity`, which for base industries is the industry subconstruction with STOCK_LIST (`industries/industryutil.lua:~489`). No base industry sets `hudIconScript`.
- **Injection.** `content/mod.script.lua` `runFn` calls `addModifier("loadConstruction", fn)`.
  - It sets `data.hudIconScript = { fileName = "square_industry_production_label::/production_label/production_label.script@hudIconFn" }`.
  - It only does this when `data.isIndustry` is true **and** `hudIconScript` is empty, so it never overrides another mod.
  - Registration must be idempotent, because `runFn` may run more than once.
  - Model on `.cache/game/mods/release/urbangames_vehicles_no_end_year/content/mod.script.lua`.
  - Fallback if the modifier is ignored: `api.res.constructionRep.getAsTable/setAsTable` in `postRunScript`.
- **Recipe.** `hudIconFn(captureParams, params, userParam)` returns a registered recipe, `ProductionLabelHudIcon{ entity = params.entity }`.
  - The recipe uses `engine_react_util.useStepStateTimer(getFromEngine, interval?, stateEqualsFn?)` (`base/tealdef/gui/main/engine_react_util.d.tl:20-24`) with `REFRESH_INTERVAL = 2.0` s instead of the 0.5 s default, because `getIndustryProductionData` is heavier (`getIndustryBoost` plus a rule walk; about 3 STOCK_LIST reads per output).
  - Each refresh does one `getStockListInputOutputData`, one `getIndustryProductionData` per output and one STOCK_LIST read (for the `produceFrequency` fallback), all inside a `pcall`, so a malformed modded industry shows no label instead of a HUD error.
  - Pure logic (entry/state/style/format) is in `production_label_model.tl`.
  - It returns a horizontal BoxLayout. Each entry is wrapped in a BoxLayout that carries `production-label-producing|idle`. It returns an empty layout when there is no output with capacity > 0.
  - `isIndustry = true`, as the industry window passes it (`industry_eow.script.tl:734`).
  - Index mapping: output `i` of `getStockListInputOutputData(..., 0)` is the `index` that `getIndustryProductionData` looks up (it calls the same function with `maxNum = index`). The window passes a per-rule `adjustedIndex` (`industry_util.tl:439`), which is identical for single-rule industries, as all base ones are.
- **CSS.** `production_label.css.lua` scoped to `R::ProductionLabelHudIcon`:
  - Spacing that matches `R::StockHudIcon`.
  - Producing / idle background colours on `!hud-icon-background` under our wrapper classes.
  - Hide the whole pill (background `R::Component`, plus `TextView` and `ImageView` for safety) at far LOD, like `HudIconManager::Button!hud-lod-far BoxLayout!stock-icon-layout TextView` (`gui/main/hud_icon_master.css.lua:~146`). The icon sits inside the pill's Component, so the rule still covers it.
  - Make selectors more specific than base (see `mods/square_bigger_line_dots`).

## Phases

1. **Build.** Scaffold the mod (`make new-mod`), then add the modifier, recipe, CSS and pure helpers (a format function plus "pick output cargos from a stock list table") with tests in `tests/square_industry_production_label/`. Done when `make check`, `make test` and `make validate` pass for the mod.
2. **Review.** Run the validator agent plus a code review of the phase 1 diff, then fix the findings.
3. **In-game test.** Follow `TESTING.md` (user).

## Open risks

- The producing/idle backgrounds rely on our selector `... BoxLayout!production-label-producing !hud-icon-background` beating base `!hud-icon-background`. If both pills look the same dark colour in game, the selector did not match.
- Pill with two icons (multi-output) is wider than the stock pill; no base industry has several outputs, so it is untested.

- Whether a `loadConstruction`-modifier-set `hudIconScript` is honoured. This is unverified until tested in game, and the fallback is listed above.
- The `isIndustry` flag was confirmed for fishing grounds. 32 base industry `.con.lua` files set it. Check the rest in phase 1.
- Whether `produceFrequency` drops to 0 for a raw producer with a full output stock or no transport. If it doesn't, such an industry still shows as producing. Check in game (TESTING §3).
- Multi-rule industries with several different outputs: the window's per-rule index quirk could make the window and the label differ. There are none in base. Check modded ones if they come up.
- Hook call inside a registered recipe (safe) vs. directly in `hudIconFn` (unverified). Use the registered recipe.

## Pickup rate pill (2026-10-07)

A second row under the production pill shows, per output cargo, how much the player's lines can carry away from this industry: `[line icon] 112` under `[factory icon] 79`. Production and pickup capacity can be compared at a glance.

### Decisions

| Topic | Decision |
|---|---|
| Value | Sum of `api.engine.util.line.calcLineStationThroughput(line)` (`api/tealdef/api/engine/util.d.tl:199-202`, per year, the "Rate" of the line window: `line_eow.script.tl:43-56`) over every line that **loads this output cargo** at a station group whose catchment reaches the industry. Each line counts once per (industry, cargo), even when it stops several times at that group or at both an input and output terminal. Rounded like the window (floor(x + 0.5)). |
| When shown | Only for an output with a summed rate > 0. No line, no pill. Same order as the production pills, one per output cargo that has a production pill. |
| Icon | `model.PICKUP_ICON = "::/gui/game_bar/icons/line_vehicle_manager_30.tga"`: the game bar's **Line Manager** button (`gui/game_bar/game_bar.tl:769`), a truck with route arrows, so it reads "lines / transport". Checked in `gui.zip` against `symbol_cargo` (LineRate's plain box: reads as stock next to the stock pill), `symbol_cargo_supplied` (box + up arrow: the industry window's "Supplied" column, a different number) and `relation_vehicle_train_bus`. Cargo icon added from `ICON_MIN_OUTPUTS` outputs on, the same rule as the production pill (count = number of production pills, so a two-output industry with one pickup pill still says which cargo it is). |
| Layout | The recipe's outer `production-label-layout` BoxLayout is now **vertical** with one horizontal `production-label-row` per row (production, then pickup only when it has pills); it replaces the single horizontal layout of PLAN "Recipe". Spacing {4, 4} on both (`production_label.css.lua`); the far-LOD rules already cover every descendant. |
| Style | Same pill as production (`makeContentLabelIndictator`, `HudIconMain`, white text), class `production-label-pickup` with the idle pill's neutral background (`model.STYLE_PICKUP`). |
| Mixed-cargo lines | v1 adds the line's full rate to every output cargo it loads here. A line carrying fish and grain, or loading at two industries of the same group, is over-counted. Known limitation; a per-cargo split (`getLineCapacityUsages`) is a possible v2. |
| Pause | No rebuild while the simulation is paused (`GAME_TIME.updateCount` unchanged, `api/tealdef/api/engine.d.tl:425-436`; read like `statistic_lines.tl:289`). Lines edited while paused show up after unpausing (≤ 15 s). |

### Mechanism

There is no industry → lines API, so the inverse is built in one pass (`content/production_label/production_label_pickup.tl`):

1. `api.engine.system.lineSystem.getStationGroup2LineStopsMap()` (`api/tealdef/api/engine/system.d.tl:44-45`): station group → `{{line, stopIndex0}}`. Unused in base; the pair shape matches `getLineStopsForTerminal`, whose second value base names `stopIndex0` (`gui/entity_window/station_group/station_group.tl:695-702`; `SIM_ENTITY_AT_TERMINAL.lineStop0` is read as `line.stops[lineStop0 + 1]`, `sim_person_eow.script.tl:335`). So stop = `LINE.stops[stopIndex0 + 1]`. If that stop's `stationGroup` differs, the aggregation falls back to every stop of the line at that group and counts a mismatch (debug log).
2. Per stop: skip `loadMode == LEGACY_UNLOAD_ONLY` (enum declaration order → 3, unverified; `engine.d.tl:497-502`, base casts it with `as integer`, `cargofilter_window.tl:819`). Loaded cargos are `stop.stopConfig.load[cargoTypeId + 1]` (copied into a plain table per stop: components and their vectors are engine userdata, so `type(load) == "table"` would fail and a reference into an unretained component is unsafe) (`engine.d.tl:505-509`, read like `cargo_util.getConfiguredStopCargoTypes`, `cargo_util.tl:818-835`). Stops that load nothing but passengers (`api.res.cargoTypeRep.getPassengerCargoTypeId()`) are skipped before any catchment query, so bus/tram stations cost nothing. A terminal with `cargoLoad == false` is skipped (STATION component, `stations[stop.station + 1].terminals[stop.terminal + 1]`, 0-based like `line_util.tl:100-106`; `Terminal.cargoLoad`, `api/tealdef/api/type.d.tl:1286-1287`). Unknown terminal data does not skip.
3. Reach of a station group = union over `STATION_GROUP.stations` of `api.engine.system.catchmentAreaSystem.getStationCatchables(station, true)` (`system.d.tl:445-448`, StockList entities). This mirrors base `autoLoadConfig` (`gui/line_vehicle_mgmt/line_util.tl:545-589` → `cargo_util.getInputOutputStocksForStation`, `cargo_util.tl:544-563`), which also unions all stations of the group. Built-in industry stations (fishing grounds, oil platform, sand excavator): when a station has no cargo catchables, `streetConnectorSystem.getConstructionEntityForStation(station)` → CONSTRUCTION `industries` → each industry entity and its `INDUSTRY.stockList` are added (`system.d.tl:250-252`, `engine.d.tl:321-324`).
4. Output cargos of a StockList: its `OutputStock` stocks' `api.engine.util.stock.getStockCargoTypes(entity, i - 1)` (same as `cargo_util.getInputOutputStocksForStockList(entity, true)`, `cargo_util.tl:505-537`).
5. Result: `stockListEntity → {cargoTypeId → rate}`. The label looks up `params.entity` (the industry's STOCK_LIST subconstruction, PLAN "Hook"); this is expected to be the same entity the catchables return (unverified, TESTING §7).

### Cache design (efficiency first)

- **One shared cache** in the module (`pickup.cache`). `ug_require` caches modules (`base/init.lua` ~56-110), so every label recipe in the GUI Lua state shares it.
- **Lazy, single-flight rebuild** by whichever label finds it stale during its existing 2 s `useStepStateTimer` read (no extra timer). Stale = never built, or `pickup.REFRESH_INTERVAL` (15 s of `os.time()`, wall-clock seconds; **not** `api.util.getApplicationTime()`, which is GUI-thread only (`api/tealdef/api/util.d.tl:174`) and crashed the game in the HUD recipe's worker thread, null deref at +0xd8, crash dump 2026-10-07) elapsed **and** `updateCount` changed. `updateCount` is read only after the interval check passed. A smaller `updateCount` (another game loaded) also counts as stale. When paused (count unchanged) the interval restarts, so GAME_TIME is read once per interval instead of once per label refresh. A `building` flag prevents re-entry.
- **Rebuild cost** scales with station groups that have line stops: one bulk map call, then per line one LINE read and at most one `calcLineStationThroughput` (only for lines that serve something), per cargo-loading station group one STATION_GROUP read and one `getStationCatchables` per station, per StockList one STOCK_LIST read, per station one STATION read for the terminal check. All memoised per rebuild.
- **Per label per refresh:** one table lookup. The rate is stored on the existing `SquareProductionLabelEntry` as `pickup` (integer, nil when none), so the recipe state stays plain and the base deepEquals cheap.
- **Failure:** the whole rebuild runs in `pcall`; on error the last good cache stays, the attempt still counts (no retry before the next interval), and the error is logged once.
- **Testability:** `pickup.aggregate(adapter)` is pure; the engine calls live in `pickup.engineAdapter()` (stubbed in `tests/square_industry_production_label/test_pickup.lua`).
- **Debug:** `pickup.DEBUG = true` for the first in-game test: one log line after the first rebuild (station groups, lines, cargo stops, industries with pickup, stopIndex mismatches, fallback stations, ms) and one line for each of the first 5 label lookups (hit with rates, or miss). Set it to `false` after the test.

### Open risks

- `getStationCatchables` entity == label `params.entity` (else every lookup misses: no pickup pill anywhere). The debug lookup lines show it.
- Fishing grounds / oil platform built-in terminals: whether catchables or the construction fallback find the industry.
- `stopIndex` base (0 assumed; mismatches are logged and handled by the fallback scan).
- `LEGACY_UNLOAD_ONLY == 3` (only skips stops; wrong value would at worst count an unload-only stop).
- Rate scale: `calcLineStationThroughput` is per year like the production numbers? Compare in game.
- Mixed-cargo over-count (by design in v1).

## Options (2026-10-07)

Both pills can be switched off in the mod settings (the mod selection when a game is started or loaded). Cosmetic only: nothing is saved, `severityAdd` / `severityRemove` stay `None`.

### Decisions

| Topic | Decision |
|---|---|
| Declaration | `mod.json` `params` (`docs/wiki/modding/general/modscripts.md` "Mod Params"): `showProduction` "Show production" and `showPickup` "Show line pickup rate", each `uiType: "Button"`, `values: ["On", "Off"]`, `defaultIndex: 0` (0-based, so On by default; the wiki tip under "Mod Params"). Plain English name and tooltip, same as `mods/square_better_minimap` (`showArrow`); this repo's mods ship no `strings.json`. |
| Value | The 1-based index of the chosen value (`modscripts.md` "Mod Params": `numbers` unset → 1, 2, …; read as `allModParams[modId].<key>` in the wiki's param filter example): 1 = On, 2 = Off. Anything other than 2 (missing table or key, other types) counts as On. |
| Where read | **Superseded 2026-10-07 by "Settings read live (2026-10-07)".** Was: once per game load in `runFn(configDict, allModParams)` (`content/mod.script.lua`; `modscripts.md` "runScript"), the only place it is sure to be current: `runFn` runs on every load, the HUD's module state survives loads. Not `api.engine.config.getModParams()` (`api/tealdef/api/engine.d.tl:1806-1807`) in the HUD: it is not marked GUI-thread only and better_minimap uses it in GUI code, but a read-once cache there would keep the previous game's choice after loading another save, and reading it per call is wasted work. |
| Transport to the HUD | **Superseded 2026-10-07 by "Settings read live (2026-10-07)".** Was: as the hudIconScript's ScriptRef `params` (`{showProduction, showPickup}` booleans): HudIconMasterGame passes `customRecipe.params` to `hudIconFn` as `captureParams` (`base/content/gui/main/hud_icon_toolbox.tl:353-356`; `ScriptRef.params`, `api/tealdef/api/type.d.tl:1388-1389`; `constructions/basics.md` "HUD Icon Script"). Base passes booleans the same way (`industries/oil_platform/oil_platform.con.lua:153-156` `snappingWater = true`). No engine read, no thread question. `model.options(captureParams)` treats `false` and `0` as off, anything else (incl. a missing table) as on. |
| Pickup off | `readView` never calls `pickup.ratesFor`, so the shared cache is never stale-checked or rebuilt: no line, station or catchment read at all. The production pill path is unchanged. |
| Production off | The production row is not built. The engine reads stay the same (the pickup entries need the output list and capacities from `getIndustryProductionData`; only outputs with a production entry get a pickup pill, as before). The cargo-icon rule still counts all outputs. |
| Both off | **Superseded 2026-10-07 by "Settings read live (2026-10-07)".** Now: industries still get the script; `hudIconFn` returns an empty `BoxLayout` without mounting the recipe (no timer, no read). Was: `runFn` registers **no** `loadConstruction` modifier, so industries get no hudIconScript: no recipe, no timer, no read. If `hudIconFn` is called anyway, it returns an empty `BoxLayout` (the hudIconScript contract wants a layout) without mounting the recipe. |
| Save compatibility | Options live in the mod selection and only change which HUD rows are drawn; the construction resource is still only changed in memory. Toggling between loads is safe. |

### Open risks

- *(Obsolete since "Settings read live (2026-10-07)": the params now only carry `kind`.)* ScriptRef `params` survive the construction converter as a Lua table with booleans (base relies on it for `updateScript` / `formatValueScript`, but not seen for `hudIconScript` in base). If they were dropped, both pills would simply stay on (the default); "both off" still works because it registers nothing. TESTING §8.

## Warehouse rates (2026-10-07)

Warehouses get their own label rows under the vanilla warehouse stock pill: per cargo, `[in icon][cargo] 120` in an incoming row and `[out icon][cargo] 90` in an outgoing row below it. Toggle: new mod setting "Show warehouse rates" (default On).

### Decisions

| Topic | Decision |
|---|---|
| Value | Per cargo type, `api.engine.util.stock.getCargoLogValueDiffPerYear(entity, "itemsUnloaded", cargo)` (incoming) and `(..., "itemsLoaded", cargo)` (outgoing) (`api/tealdef/api/engine/util.d.tl:89-94`): the per-year logs behind the warehouse window's Incoming / Outgoing statistics chart (`gui/entity_window/warehouse/warehouse_eow.script.tl:159`, which draws them summed over all cargos) and the base stock pill's trend (`gui/main/cargo_util.tl:238-239`). Rounded like the industry pills; nil / negative = 0. |
| Which cargos | Every cargo type of `api.res.cargoTypeRep.getAll()` except passengers (`getPassengerCargoTypeId`), the same walk as base `cargo_util.calculateStockCargoCount` (`cargo_util.tl:214`), then only cargos with incoming **or** outgoing > 0. Not limited to what is stored now or to the configured cargo filter, so a cargo that only passes through, or that was filtered out recently, still shows while it has log entries in the last year. Both rows list the same cargos in the same order, so a cargo with outgoing 0 still shows `0` in the outgoing row (stock piling up is visible). |
| Order and cap | Busiest first (incoming + outgoing), ties by cargo type id (stable whatever `pairs` order `getAll` yields). At most `model.MAX_WAREHOUSE_CARGOS = 6` cargos so a busy universal warehouse stays a sane width. Pure logic in `model.warehouseView` / `warehouseEntry` (`production_label_model.tl`, tested in `test_model.lua`). |
| Icons | `model.INCOMING_ICON = "::/gui/entity_window/icons/symbol_cargo_received.tga"` (cargo box + down arrow) and `model.OUTGOING_ICON = "::/gui/entity_window/icons/symbol_cargo_supplied.tga"` (box + up arrow): the industry window's "Received" / "Supplied" column headers (`industry_eow.script.tl:384, 505`; `town.tl:403`). Masks in `gui.zip` (`gui/entity_window/icons/symbol_cargo_received@2x.tga`, `symbol_cargo_supplied@2x.tga`, checked visually). Each pill is `{direction icon, cargo icon}` (always both: a warehouse holds several cargos and the stock pills above may be in another order). Other candidates: `line_vehicle_mgmt/icons/symbol_cargo_arrow_down_receive` / `_up_send` are pixel-identical copies used in the line cargo filter; `entity_window/icons/stock_increasing*` are the stock-trend arrows (would read as "stock trend"). |
| Style | Same `makePill` / `makeContentLabelIndictator` (`HudIconMain`, white text) as the industry pills. Classes `production-label-incoming` / `-outgoing` (`model.STYLE_INCOMING` / `STYLE_OUTGOING`), backgrounds from the warehouse chart's colours `Positive` (jordyBlue) / `Negative` (lightCoral) (`warehouse_eow.script.tl:161-164`, `default_colors.gres.lua:58-59`), mixed 50 % towards `NeutralDarkest` (pastels need more darkening than shamrock for white text), `transparency.Low`. |
| Toggle | `mod.json` param `showWarehouse` "Show warehouse rates", On/Off, `defaultIndex 0`. **Superseded 2026-10-07 by "Settings read live (2026-10-07)".** Now read live in `hudIconFn`; off → empty layout for warehouses. Was: read in `runFn` with the others (`readOptions`). Off: warehouses get no `hudIconScript`. `runFn` registers the modifier when any of production / pickup / warehouse is on; industries only get the script when production or pickup is on. Log: `loadConstruction modifier registered (production on, pickup on, warehouse on)`; all off: `all labels are off in the mod settings, no label script set`. |
| Refresh | `useStepStateTimer` with the same `REFRESH_INTERVAL` (2 s). Read-only, no commands, no saved state, no GUI-thread-only API. |
| Save safety | Unchanged: `severityAdd/Remove: None`, `cosmetic: true`. The warehouse construction resource is only changed in memory. |

### Mechanism

- **Detection** (`content/mod.script.lua` `isWarehouse`): not `isIndustry`, and either the modifier's `fileName` (minus a trailing `.lua`) is `warehouses/warehouse.con` or ends in `/warehouses/warehouse.con` (covers `::/…`, `base::/…`, `res/construction/…`), or `data.updateScript.fileName` is `warehouse.script@updateFn` or ends in `/warehouse.script@updateFn`. Base `warehouse.con.lua` has no `isIndustry`, no `hudIconScript` and `updateScript = "warehouse.script@updateFn"`; every `warehouse_era_*.metacon.tl` preset builds it via `createTemplateFn` → `constructionFileName = "warehouse.con"` (`warehouses/warehouse.script.lua:42-54`), so all placed warehouses are that one resource. The exact `fileName` string a `loadConstruction` modifier receives is not documented (base resource names look like `::/stations/…/x.con`, `mission/guide_system/main/guide_system_story.tl:12`; `mission/modifier.lua:98-108` strips everything up to a `::` segment), hence both checks. An existing `hudIconScript` is never overridden (`isEmptyScriptRef`).
- **Transport**: `hudIconScript = { fileName = <same hudIconFn>, params = { kind = "warehouse" } }`. `hudIconFn` checks `model.kind(captureParams)` first: `"warehouse"` mounts `ProductionLabelWarehouseHudIcon{entity}`, anything else (incl. the industry params, which have no `kind`) runs the industry path unchanged.
- **Hook entity**: `HudIconMasterGame` appends the custom script for `con.subconstructions[1]` (`hud_icon_toolbox.tl:242-251`); for a warehouse that is the subconstruction with `warehouse = {}` and the StorageStocks (`warehouses/warehouse.script.lua:331, 349`), the entity `StockHudIcon` passes to `calculateStockCargoCount` (`hud_icon_toolbox.tl:56-108`). So the logs are read on the same entity as the base stock pill's trend.
- **Recipe** (`production_label.script.tl`): `readWarehouseView` (entityExists, STOCK_LIST present, then 2 log reads per non-passenger cargo type) inside `pcall`; first error is logged once and the label goes blank (same `failed` ref as the industry recipe). Returns a vertical `production-label-layout` with two `production-label-row`s, or an empty layout when nothing moved.
- **CSS** (`production_label.css.lua`): spacing, two-icon spacing and far-LOD hiding now loop over both scopes `R::HudIconMasterGame R::ProductionLabelHudIcon` and `R::HudIconMasterGame R::ProductionLabelWarehouseHudIcon`; incoming / outgoing backgrounds are scoped to the warehouse recipe.

### Open risks

- The modifier `fileName` format: if neither the name nor the `updateScript` check matches in game, warehouses get no label (log line still says `warehouse on`). TESTING §9.
- `getCargoLogValueDiffPerYear` semantics: "difference in the last year" is assumed to equal the chart's latest yearly value. Check the order of magnitude against the warehouse window (TESTING §9).
- Cost: 2 log reads × ~(cargo types − 1) per warehouse every 2 s, on top of the base stock pill's own reads. Fine for a handful of warehouses; on maps with many warehouses watch for stutter (raise the interval for warehouses if needed).
- The incoming blue (darkened jordyBlue) might read too close to the stock pill's electricRoyal; swap the mix amount or colour in the CSS if so.
- Modded warehouses that are a different construction (own `.con`, own update script) are not detected; by design for now.

## Settings read live (2026-10-07)

**Bug (user report, revision 3 unreleased):** switching "Show warehouse rates" Off in the mod settings and loading the game did not remove the warehouse pills. The industry toggles were built the same way, and the TESTING §8 existing-save checks had never been ticked.

**Cause (hypothesis, not confirmed):** the settings were read in `runFn` and baked into the construction resources by the `loadConstruction` modifier, either as the `hudIconScript` ScriptRef params (`{showProduction, showPickup}`) or by not setting the script at all (warehouse off, both industry pills off). The game apparently does not re-run construction loading (or reuses the loaded construction resources) when only the mod params change, so the previous choice stays in the resources. Whatever the exact cause, baking settings into resources is fragile.

**Change:**

- `content/mod.script.lua`: the modifier is always registered and always attaches the `hudIconScript` (still never overriding an existing non-empty one): industries get `params = { kind = "industry" }`, warehouses (`isWarehouse`, unchanged) `{ kind = "warehouse" }`. `runFn` still reads `allModParams[modId]`, only for the log line `loadConstruction modifier registered (settings at load: production on, pickup on, warehouse on)`.
- `production_label.script.tl` `hudIconFn`: `readSettings()` calls `pcall(api.engine.config.getModParams)` and passes `[modId]` to `model.options` on **every** call (once per HUD icon mount, not per frame; cheap). No cache: a cache would survive loading another save with other settings; params only change on a game load, which rebuilds the HUD. On error: one warning (`could not read the mod settings, showing all pills`), then all on. Warehouse kind: `showWarehouse` off → empty `BoxLayout`, else the warehouse recipe. Industry: production and pickup off → empty `BoxLayout`, else the industry recipe with the live options. Same pattern as `mods/square_better_minimap/content/minimap/gui/minimap_hud.script.tl` (`showArrowSetting`, verified in game), minus its read-once cache.
- `model.options(modParams)`: the mod's own `getModParams()` entry (`{showProduction, showPickup, showWarehouse}`, 1-based value index) → three booleans, 2 = off, anything else (missing, malformed) = on.

**Risk:** `getModParams` is not marked GUI-thread only (`api/tealdef/api/engine.d.tl:1806-1807`), and better_minimap calls it from its HUD script, but HUD icon recipes do not run on the GUI thread (`getApplicationTime` hard-crashed there). If it crashes or errors in `hudIconFn`, that shows up on the first load with an industry on screen (crash) or as the warning above (all pills on). TESTING §8.
