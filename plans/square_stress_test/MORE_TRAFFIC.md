# square_stress_test: more car traffic (Phase 7)

Goal: a load-time way to put many more private cars on the roads, so road/junction mods (Smart Lanes,
Roundabouts & Interchanges) and the HUD mods can be measured under heavy traffic. Today the tool can only
*remove* cars (Clear traffic) and add *line* vehicles.

Status: 7a built 2026-10-11 (not run in game yet; test: TESTING.md 6I). Deviations from the plan below: the
runFn config line can't know the wrapped count (scripts load after runFn), so a separate
`[SQST] town_building_wrap` line reports it once 3 scripts are wrapped; Scan is always shown (the test steps rescan). Read `PLAN.md`, `RESEARCH.md` and `docs/findings.md` "Stress Test
probes" first.

## Why there is no simple setting

- A private car is not an entity: it is a `SIM_PERSON` with `lastMoveMode` DRIVE, a `MOVE_PATH` and a
  `LAND_VEHICLE` component (docs/findings.md, fourth run). No command creates sim persons or cars;
  `api.cmd.debug.makeSimPersonSetStateCmd` only moves existing persons (jump/go home, shopping, work).
- `BaseConfig` (`.cache/game/api/tealdef/api/type.d.tl:3473`) has no car share or traffic density field. The
  only related ones are `simPersonDestinationRecomputationProbability` (already our "Sim person trip
  recalculation" param) and `townCapacityScalingFactor`, which only feeds the sandbox town builder
  (`base/content/gui/construction/construction_react_util.tl:3532`), not existing towns.
- Car models' `metadata.car.spawnWeight` (e.g. `vehicle/car/corolla/corolla.mdl:419`) only picks the model.

So traffic volume = number of persons x share of trips by car x trip frequency. The two levers left are the
town buildings' `personCapacity`:

1. **Mode choice.** A `personCapacity` may carry `disallowedMoveModes` (move modes `WALK`, `DRIVE`, `LINES`,
   `api/type.d.tl:2364`) and `destinationWeight`. The base game uses it: industries set
   `disallowedMoveModes = {"WALK", "DRIVE"}` so workers must come by line (`base/content/industries/
   industryutil.lua:444-457`, flat fields on `personCapacity`); landmarks and the campaign 6 school do the same
   (`landmarks/landmark_util_serialized.tl:200-221`). The engine stores it as
   `PERSON_CAPACITY.pathfindingPreference` (`api/engine.d.tl:827-843`); town buildings read
   `destinationWeight=1, disallowedMoveModes={}` in game (probe 9d). Disallowing `WALK` and `LINES` on town
   buildings should turn every trip into a car trip.
2. **Capacity.** Town buildings set `capacity = params.capacity` (`base/content/buildings/townbuildingutil.lua:216-220`).
   A multiplier means more residents, workers and shoppers, so more trips.

## Hook: `loadScript` modifier wrapping the town building updateFn

Town building `.con.lua` files return `townbuildingutil.makeBuildingStatic(...)` whose `updateScript.fileName` is
`<name>.script@updateFn` (`townbuildingutil.lua:44-95`); the `.script.lua` next to it returns
`townbuildingutil.makeBuildingScript(generatedData, ...)`, a table with `updateFn(captureParams, params)` that
builds `result.personCapacity` (`townbuildingutil.lua:98-220`). Plan: in `runFn`,
`addModifier("loadScript", fn)` (listed in docs/wiki/modding/scripting/modifiersfilters.md; the base game uses it in
`base/content/mission/modifier.lua:135`). For script files under `/buildings/` whose data has an `updateFn`,
replace it with a wrapper that calls the original and then patches `result.personCapacity`:

```lua
local orig = data.updateFn
data.updateFn = function(captureParams, params)
    local result = orig(captureParams, params)
    logic.patchTownBuildingResult(result, cfg)   -- pure, unit-tested
    return result
end
```

Patch rules (`logic.patchTownBuildingResult`, no engine calls):
- Only when `result.townBuilding ~= nil` and `result.personCapacity ~= nil` (town buildings only; never
  industries, landmarks, stations).
- Mode: set `result.personCapacity.disallowedMoveModes` (flat, as industryutil does) to the variant's list.
  Keep any existing entries; never disallow `DRIVE`.
- Capacity: `capacity = math.floor(capacity * factor + 0.5)`, only `personCapacity.capacity`. Cargo rules were
  already computed from `params.capacity`, so cargo demand stays unchanged.
- Default options write nothing and register no modifier.

### Unknowns (the probe settles them before the final options)

| # | Question | How we find out |
|---|---|---|
| U1 | Does `loadScript` get the town building `.script.lua` tables, and is `updateFn` a callable function in that data (not stripped or serialized)? What does `fileName` look like? | `[SQST]` log line: wrapped count + the first 3 file names, at load |
| U2 | Does the wrapper's result reach the engine (no load error, no "Expected table")? | Load a game; town buildings still build; probe 9d reads `pathfindingPreference` |
| U3 | Does `disallowedMoveModes` act on trips *to* a building (destination), *from* it (residents), or both? | Variant A vs B below, census DRIVE/WALK/LINES share |
| U4 | Do existing buildings pick up the change on load, or only when rebuilt? | Census right after load vs after Towns tab Grow (updateAllBuildings rebuilds) |
| U5 | Do persons with no road path to a destination get stuck, unhappy, or drop out? Does town growth collapse? | Watch town ratings and Driving now for 5 game minutes at speed 4 |
| U6 | Does a capacity change survive town development (the town re-issues `params.capacity`)? | Building window capacity before/after a develop tick |

## Params (mod.json, load time, need a reload)

Phase 7a ships test variants; Phase 7b collapses them to what the test showed works.

- `car_traffic` "Car traffic" (7a values): `Default` / `Drive: destinations` (commercial + industrial town
  buildings disallow WALK + LINES) / `Drive: all town buildings` (residential too).
  7b: `Default` / `More cars` (whichever variant won), maybe `Cars only` if a mixed setting is possible.
- `town_capacity` "Town building capacity": `x1` / `x2` / `x4`.

Tooltips state plainly that this changes town buildings in the save, is for testing only, and that removing the
mod restores the defaults only as buildings are rebuilt (U4).

## Phases (each in its own subagent; done = `make check`, `make test`, `make validate`,
## `make i18n ... --check --lint-modinfo` and `make tooltips` pass for MOD=mods/square_stress_test)

### 7a. Build + probe instrumentation (no in-game run)

1. `stress_logic.tl`: `PARAM_KEYS` += `car_traffic`, `town_capacity`; `CAR_TRAFFIC_MODES` (list per option),
   `CAPACITY_FACTORS = {1.0, 2.0, 4.0}`; `configFromParams` fills `carTrafficMode` (nil = default) and
   `townCapacityFactor`; `logic.isTownBuildingScript(fileName)`; `logic.patchTownBuildingResult(result, cfg)`
   returning true when it changed something.
2. `stress_types.d.tl` and its editor copy `tealdef/stress/stress_types.d.tl` (keep identical): new
   `SquareStressConfig` fields.
3. `mod.script.tl` `runFn`: register the `loadScript` modifier only when either option is non-default (no
   register-once guard, memory tf3-runfn-no-register-once-guard). Count wrapped scripts and patched results;
   log `[SQST] config car_traffic=... town_capacity=... wrapped=N first=<file>,<file>,<file>` once per
   runFn and `[SQST] town_building_patch first=<file> modes=... capacity=a->b` for the first patched result
   only (never a line per building). Everything in pcall; a failure logs one `log.warning` and returns the
   original result.
4. Traffic tab readout: add the move-mode split of the last scan (`DRIVE / WALK / LINES` persons, from
   `lastMoveMode`) next to "Driving now", so U3/U5 can be read without the Probe tab. Reuse the clear-traffic
   scan (no extra scan per frame); "Scan" button if no scan has run.
5. mod.json params with `name`/`tooltip`/`values` in all 13 languages (`strings.json`); tooltips wrapped
   (`make tooltips MOD=mods/square_stress_test ARGS=--fix`).
6. Tests `tests/square_stress_test/test_more_traffic.lua`: param mapping (defaults write nothing), file name
   filter (town building scripts yes; industries, landmarks, `.con.lua` no), patch rules (non-town-building
   results untouched, existing disallowed modes kept, DRIVE never added, capacity rounding, nil-safe).
7. `TESTING.md` section "6I. More car traffic (Phase 7, not run in game yet)" with the steps below;
   `PLAN.md` Phases list gets a line 7 pointing here. Changelog: if rev 2 is still unreleased add the entry to
   it, else bump `revision` to 3 and add a rev 3 entry (ask the user to run `! make modio-status
   MOD=mods/square_stress_test` to know which).

**Stop: the user runs the in-game test.**

### In-game test (user, TESTING.md 6I)

Use a copy of a save with 2-3 grown towns connected by road, game speed 4.
1. Baseline: all new params default. Traffic tab: Scan; note Driving now and DRIVE/WALK/LINES.
2. Car traffic = `Drive: destinations`, reload. Check stdout.txt for `[SQST] config ... wrapped=N` (U1) and
   `town_building_patch` (U2). Scan right after load and again after 2 game minutes (U4). Then Towns tab Grow x1
   on one town (rebuilds) and Scan (U4).
3. Car traffic = `Drive: all town buildings`, reload, same scans (U3).
4. Watch 5 game minutes: town ratings, cars stuck or circling, population trend (U5).
5. Town building capacity = x4 (car traffic Default), reload: one building's window capacity before/after, Scan
   (U6).
Report: the `[SQST]` lines, the scan numbers per step, and screenshots of busy roads.

### 7b. Finalize (after the test)

Collapse `car_traffic` to the variants that worked, update the tooltips and translations, write the results to
`docs/findings.md` ("More car traffic", with date and evidence: wrapped count, DRIVE share before/after), mark
TESTING.md 6I verified, and update the description's feature list. If U1/U2 fail (no `updateFn` in
`loadScript` data), fallback: a `loadConstruction` modifier on town building `.con.lua` that points
`updateScript.fileName` at our own `square_stress_test::stress/town_building.script@updateFn` with the original
reference in `params`, and that script calls the original script's `updateFn`. Research how a script ref can be
loaded from Lua (`require` on the `.script.lua` path) before building it.
