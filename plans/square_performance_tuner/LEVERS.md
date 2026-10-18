Status: research from game files only (2026-10-12, build as extracted in `.cache/game`); nothing here is verified in game yet. Probe: `mods/square_sim_tuner_probe/` (TESTING.md).

# Lever inventory: Performance Tuner

Every BaseConfig field and base-game script interval that plausibly trades CPU/GPU for fidelity. Paths are
relative to `.cache/game/` unless they start with `docs/` or `mods/`. `type.d.tl` = `api/tealdef/api/type.d.tl`,
`mod.script.tl` = `base/content/base/mod.script.tl`.

## How BaseConfig gets set and read (applies to every row)

- **Write at load: `preRunFn(captureParams, configDict, allModParams, baseConfig)`.** The base game sets all of
  its defaults there (`mod.script.tl:16-255`); the official mods do too (`mods/release/urbangames_no_costs/content/mod.script.tl:4-6`,
  mod.json `preRunScript`). Proven in game for our mods: Stress Test's preRunFn `noCosts` / `sandboxMode`
  (log `2026-10-12_0525_showcase-204313-crash`, `[SQST] config noCosts=true sandboxMode=true`), Organic Towns'
  `townMajorStreetAngleRange` read back 45 at runtime (`docs/findings/towns.md:52`).
- **`game.config` in runFn** is the wiki's way (`docs/wiki/modding/scripting/baseconfig.md:17`, TF2-era page with a
  Wip banner). No TF3 file uses `game.config` (`rg game\.config .cache/game` = 0 hits). The probe tests it (load_via=runFn).
- **Write in postRunFn via `api.res.getBaseConfig()`**: wiki `baseconfig.md:18`; base postRunFn only reads it
  (`mod.script.tl:298`). Probe tests it (load_via=postRunFn).
- **Read at runtime: `api.res.getBaseConfig()`** (`api/tealdef/api/res.d.tl:172`). Base game scripts call it
  every update for some fields (rows marked "Lua, per update" below), so for those a runtime write *would* take
  effect on the Lua side if the object is writable and shared. Whether a runtime write is accepted (userdata
  setter) and whether the C++ simulation re-reads the value is unknown: Q2/Q3 of the probe.
- Prior attempt: Stress Test probe 7 (`mods/square_stress_test/content/stress/gui/stress_probes.tl:506-525`)
  writes `noCosts` at runtime with a read-back, but was never run (`docs/findings/lines-vehicles.md:54`).

## Simulation levers (CPU)

| Lever | Default (where set) | Who reads it | Load / runtime | Expected effect | Confidence |
|---|---|---|---|---|---|
| `simPersonDestinationRecomputationProbability` | 1.0 (`mod.script.tl:108`; type `type.d.tl:3696`) | C++ only (no Lua reader) | load proven for other fields; runtime unknown | Wiki: "probability that a person will look for a new job or shopping facility. Smaller values reduce performance load. Larger values will adapt to changes in the offered public transport faster" (`baseconfig.md:182`). Fewer destination picks = fewer path searches. A TF2 mod's main lever. | effect: wiki claim only; size unmeasured |
| `townDevelopInterval` | 60 "half days" (`mod.script.tl:104`; `type.d.tl:3692`; wiki `baseconfig.md:179`) | C++ (if at all) | load | Wiki: town grow/shrink interval. **But** the Lua town scripts hardcode their own cadence: `game_mechanics/towns/towns.script.tl:10` `UpdateIntervalTownCount = 30 -- TODO: read value from base_config: townDevelopInterval` (used `:100`: each town once per 30x4 = 120 sim updates) and `towns/town_growth.script.tl:11-12,344` (same 120-update cycle, no TODO). So the config value governs town development only partly, perhaps not at all. | low |
| (hardcoded) company update | 30 x 4 updates (`game_mechanics/company/company.script.tl:11-12`, TODO "read value from base_config: townDevelopInterval"; used `:279`) | Lua | not configurable (would need a script replacement) | Company/progression step per 120 updates; cheap (one player). | high (file) |
| `chargeMaintenanceInterval` | 60 half days (`mod.script.tl:105`; `type.d.tl:3693`) | C++ | load | Maintenance booking cadence; negligible CPU. Not a lever. | medium |
| `simulateCargoWeight` | true (`mod.script.tl:107`; `type.d.tl:3695`) | C++ | load | Off skips cargo weight in vehicle dynamics; probably small CPU gain, changes gameplay (loaded trains climb like empty ones). | low |
| `townCapacityScalingFactor` | not set by base (`type.d.tl:3721`); read in `gui/construction/construction_react_util.tl:3532` | Lua (town builder) | load | Fewer persons per building = fewer sim persons = the biggest sim cost cut, but it is gameplay (smaller towns). Out of scope for a "same game, faster" mod; maybe an "extreme" preset. | medium |
| `locations.town.populationDensity` / `townFrequency` | difficulty scale (`mod.script.tl:198-199`; `type.d.tl:3544-3546`) | map generation | new maps only | Fewer people/towns at generation. Map setting already exists; not a lever for existing saves. | high |
| `animal.populationDensityMultiplier` | 1 (`mod.script.tl:138-143`; `type.d.tl:3501-3502`) | C++ spawner | load | Fewer animals to spawn/animate/render. Small CPU+GPU. In the probe as an A/B load param. | medium |
| `animal.useLocalSpawning` / `localTileSize` | true / 1000 (`mod.script.tl:140-141`) | C++ | load | Spawner bookkeeping; tiny. | low |
| `advancedOptions.isReforestationActive` | game setting (`mod.script.tl:253-254`) | Lua, per update (`base/content/terrain/reforestation.script.tl:18`) | runtime-readable | Off skips the per-update reforestation proposal (`:52-56`). Already a game setting; nothing to add. | high (file) |
| `advancedOptions.missionEmissionsScriptFactor` | 1 (set by missions) | Lua, per update (`game_mechanics/emission/emissions.script.tl:27-29`) | runtime-readable | 0 makes the emissions script return early: no per-5-update `forEachEntityWithComponent` over industries/stations/depots/warehouses (`:12-18,38,198-251`). Real Lua CPU saving on big maps, but emitter values freeze (Stress Test "No noise and pollution" uses it). Also a good **runtime write witness**: if a runtime write works, the next emissions update sees it. | high (file); gain unmeasured |
| `economy.industryDevelopment.*` (`closureProbability`, `extendTimeSpan`, `spawnIndustries`) | `mod.script.tl:165-172` | Lua per update (`industries/industries.script.tl:55,128-132`) | runtime-readable | Gameplay pacing, not cost. | high (file) |
| (hardcoded) emissions cadence | every 5 updates per kind (`emission/emissions.script.tl:12-18`) | Lua | script replacement only | See factor above. | high (file) |
| (hardcoded) towns construction-boni check | every 20 updates (`towns/towns.script.tl:11,191`) | Lua | script replacement only | Small. | high (file) |
| (hardcoded) industry closure check | every 100 updates (`industries/industries.script.tl:4,54`) | Lua | script replacement only | Small. | high (file) |

Base game scripts that run every update (`find base/content -name '*.gs.lua'`, 28 files): towns, town_cargo,
company, company_progression, industries, industry_workers (iterates its industries state each update,
`industries/industry_workers.script.tl:17-40`), emissions, reforestation, arrival_tracker, subventions,
notifications, achievements, landmarks, celebrations, fun_elements, vehicle_modifier, game_time, loan, mission,
guide_system, HUD displays. Their cost is unmeasured; SQPERF-style timing can't wrap base scripts.
`docs/findings/game-scripts.md`: game-script time costs simulation time, not frames.

## Rendering levers (GPU/CPU render)

| Lever | Default (where set) | Load / runtime | Expected effect | Confidence |
|---|---|---|---|---|
| `settings.geometryQualityOptions[i]` `viewNearFar`, `lodDistanceScaling` | Low 7200 m / 0.64, Medium 9000 / 0.8, High 11250 / 1.0, camera tool 22500 / 5.0, cockpit 7200 / 1.0, camera preview (`mod.script.tl:146-155`; `type.d.tl:3604-3622`) | load | Shorter far plane and LOD scaling = fewer instances. The game's Geometry Quality option already picks one; a mod could add a "Very low" by editing entry 1. `fogStartEndFarPerc` is documented "Unused" (`type.d.tl:3615-3616`). Phase 2. | high (file); gain unmeasured |
| `terrain.lodErrorMultiplier` | 1.0 (`mod.script.tl:79`) | load | "(Deprecated) Only used with legacy terrain" (`type.d.tl:3558-3561`): no effect expected. | high |
| Per-model `lods[i].visibleFrom/visibleTo` | each `.mdl` | load (`loadModel` modifier) | Threshold/bridge rules from the TF2 mod; Phase 2. | medium (wiki, TF3 untested) |
| `gui.signConfig.signRenderDistance`, `gui.iconRenderDistances` | wiki `baseconfig.md:105-108` | n/a | **Not in the TF3 `BaseConfig` typedef** (`type.d.tl:3473-3727` has no `gui`): TF2-era wiki rows. Not a lever unless found elsewhere. | high (absent) |
| `particles.textures`, `water.textures` | `mod.script.tl:157-163` | load | Textures only, no density/count knob in TF3 BaseConfig. Not a lever. | high |

## Measuring

- `api.gui.benchMark.getGameStepTimes()` (`api/tealdef/api/gui.d.tl:875-905`): "the simulation update time. Only
  available in GUI thread", a list of `{frameTime, gameTime}`. Also `getReplicateTimes`, `getCommandTimes`
  (GUI thread), `getBeginFrameTimes`, `getCoreStepTimes`, `getRenderTimes`, `getSwapTimes`. No base file calls
  any of them: units and buffer length unknown (the probe logs raw values and the first pull).
- Achieved game speed: GAME_TIME `gameTime` advance per real second vs GAME_SPEED `speedup` / `millisPerDay`
  (`api/tealdef/api/engine.d.tl:415-438`). At high speedup on a big map a slow sim shows as fewer game days per second.
- In-game debug panel: `base/content/gui/debug_panel/make_entity_debug_panel.tl` is the per-entity inspector
  (SIM_PERSON buttons "Pick New Destimations", `:669-692`); no profiler UI in the Lua files.
- `sample <pid>` on macOS profiles the live game (`docs/findings/debugging.md`).

## Sim person data (for Q3)

`SIM_PERSON` component (`api/tealdef/api/engine.d.tl:1086-1115`): `destinations` {residence, shopping, work},
`targetOrAtEntity`, `lastNonResType`, `lastMoveMode`, `lastDestinationUpdate` ("the timestamp of the latest
destination recalculation"), `landUse2ReachableWalkDrive`, `landUse2ReachableLines`. Base readers:
`gui/entity_window/entity_window_util.tl:1312-1313` (the SimPersonDestinationButton lead,
`base/tealdef/gui/entity_window/entity_window_util.d.tl:81-85`), `game_mechanics/towns/town_growth.script.tl:655-660`.
`SimPersonSystem` (`api/tealdef/api/engine/system.d.tl:133-158`): `getCount`, `getDestination2SpMap`,
`getSimPersonsForLine`, `getSimPersonsForDestination`. Sampling via `api.engine.getEntitiesWithComponent(SIM_PERSON)`
(`engine.d.tl:1713`). Verified in game by the Stress Test: `SIM_PERSON` is iterable that way (693 persons in 1 ms) and
the fields above, `lastDestinationUpdate` included, are readable (`docs/findings/lines-vehicles.md:84-90`). The unit of
`lastDestinationUpdate` (game-time ms like `GAME_TIME.gameTime`?) is not known: the probe logs its raw range.

## Candidates for the probe (Phase 1)

- In: `simPersonDestinationRecomputationProbability` (main), `townDevelopInterval` (does the engine read it at
  all, given the hardcoded Lua cadence), `animal.populationDensityMultiplier` (cheap A/B), step timing.
- Later, if Phase 1 shows runtime writes work: `missionEmissionsScriptFactor` as a runtime toggle (Lua reader, so
  its effect is certain), and as the cleanest witness that a runtime write reaches other Lua states.
- Not levers: `chargeMaintenanceInterval`, `lodErrorMultiplier`, `fogStartEndFarPerc`, `gui.*`, textures.
