Status: shelved 2026-10-12, probe mod deleted. The recheck rate (`simPersonDestinationRecomputationProbability`)
can only be set at load (preRunFn; BaseConfig is read-only at runtime), so no line-change boost. Settled desert
save (6.8k people): 20 % vs 100 % = ~18 % cheaper sim step, but the sim already kept up at 4x. Big young save
(106k people, sim at ~half speed): re-picks only ~10-15 % fewer at 20 %, no visible speed gain (most re-picks come
from growth). Trade-off: slower reaction to new lines. Rendering (Phase 2) is mostly covered by the game's
geometry quality option. Untested: a big, settled, years-old save. Results: TESTING.md; game facts in
docs/findings (BaseConfig read-only, event subscriptions, deterministic reload).

# Performance Tuner (working title)

A general TF3 performance mod: one settings page of measured levers (simulation, rendering, anything else the
game exposes), each with a sane default and a clear trade-off in its tooltip. Only levers a probe shows to work
and help make it in. The first two come from TF2 Workshop mods:

- "Megalomaniac Performance Tuner" (Steam 3769119054): lowers how often the simulation re-picks
  destinations (`simPersonDestinationRecomputationProbability`), town development and maintenance.
- "Performance tuning" (Steam 2850163097): shorter LOD/view distances beyond a threshold from the camera,
  a hard far cutoff, extra-aggressive presets for expensive models (bridges).

## What the game files say (build as extracted, 2026-10-12)

- `base/content/base/mod.script.tl:104-108`: `townDevelopInterval = 60`, `chargeMaintenanceInterval = 60`,
  `simPersonDestinationRecomputationProbability = 1.0`. No in-game option for any of them.
- Wiki baseconfig: the probability is "that a person will look for a new job or shopping facility. Smaller
  values reduce performance load. Larger values will adapt to changes in the offered public transport faster."
  It is about re-picking destinations, not re-routing to the current one (unverified which one costs the CPU).
- `game_mechanics/towns/towns.script.tl:10` and `company/company.script.tl:12` hardcode an interval of 30 with
  "TODO: read value from base_config: townDevelopInterval": the config value only partly governs town growth.
- `api.res.getBaseConfig()` exists (`api/tealdef/api/res.d.tl:172`); the wiki only documents writing it in
  `runFn` / `postRunFn`. Whether it is writable at runtime, and whether the engine re-reads it, is unknown.
- Rendering: `geometryQualityOptions` (`mod.script.tl:147`) already gives Low/Medium/High far planes
  7200/9000/11250 m with `lodDistanceScaling` 0.64/0.8/1.0. A threshold ("full detail within 500 m") and per-model
  rules (bridges) need a `loadModel` modifier rewriting `lods[i].visibleTo` (wiki `modifiersfilters.md`; unverified in TF3).

## Lever inventory (Phase 1 research step)

List every `BaseConfig` / settings field (`api/tealdef/api/type.d.tl`, `base/content/base/mod.script.tl`, wiki
baseconfig) and base-game script interval that plausibly trades CPU/GPU for fidelity: sim rates, town/industry
development, animals, particles, grass/terrain, icon/sign render distances, emission, etc. Per lever: default,
where it is read, load-time only or runtime, expected effect. Goes in `LEVERS.md`; candidates get added to the probe.

## Phase 1: sim recompute probe (DEV, never upload)

Mod `mods/square_sim_tuner_probe/`. Questions, each answered by a log line in `stdout.txt` (tag `[SQSTP]`):

1. **Q1 set at load:** does a mod.json param applied in `runFn` (`game.config.simPersonDestinationRecomputationProbability`)
   reach the running game? Read it back from a game script via `api.res.getBaseConfig()`.
2. **Q2 writable at runtime:** can a game script (and the GUI script) assign the field on `api.res.getBaseConfig()`
   without an error, and does the read-back show the new value?
3. **Q3 engine honours a runtime change:** does the destination churn rate actually change? Measure: sample N sim
   persons (stable set of entity ids) every few in-game days, log how many changed destination (job/shop/residence
   target) since the last sample, under the low value and after switching to 1.0. Needs research on which component
   exposes a sim person's destination (`entity_window_util.d.tl:81` SimPersonDestinationButton is a lead).
4. **Q4 boost on line change:** detect line created/changed (poll the line list + stop counts, or a GUI/game event),
   raise to 1.0 for a configurable window, then drop back; log every switch.
5. **Q5 does it help:** sim tick cost at 1.0 vs 0.4 on a big map (game's own debug/profiler numbers or SQPERF timing
   of the sim step, whatever is available), plus how fast a new line's ridership grows at each value.

Controls: mod.json params for base value (100/70/40/20/5 %), boost on/off, boost length; a GUI button to flip
between low and 1.0 by hand for Q3/Q5 A/B. Read-only otherwise: nothing written to the save.

Done when: `make check MOD=mods/square_sim_tuner_probe` passes, `make validate` has no errors, and `TESTING.md`
lists the in-game run steps. The user runs it; results go to `docs/findings/` (game facts) and here.

**Built (2026-10-12):** `mods/square_sim_tuner_probe/` (check and validate pass; linked into staging).
- `content/mod.script.lua`: preRunFn / runFn / postRunFn; the param "Set at load via" picks where the base value is
  written (preRunFn `baseConfig`, runFn `game.config`, postRunFn `api.res.getBaseConfig()`); extra A/B levers
  `townDevelopInterval` and `animal.populationDensityMultiplier` via preRunFn.
- `content/sqstp/sqstp.script.lua` (+ `.gs.lua`): game script; read-back per Lua state at start, every 30 days and on
  change; handleEvent "write" does the game-script runtime write. Never `state:set`, never subscribes (save untouched).
- `content/sqstp/sqstp_gui.script.lua` (+ `.res.lua`): top-bar button (mode auto / hold 1.0 / hold base); in
  `react.onStep`: line poll (3 s) + boost window, runtime writes (param "Runtime writer": GUI, game script via event,
  or both), churn sampler (400 persons, every 10 days, 50 reads per frame), sim step times and ridership.

**Static API findings (from files, not yet verified in game):**
- No TF3 file uses `game.config`; base and official mods write BaseConfig in `preRunFn` (4th argument). The wiki's
  runFn / postRunFn ways are TF2-era (LEVERS.md "How BaseConfig gets set").
- The probability has no Lua reader: only the engine uses it. Q3 therefore needs the churn sampler.
- `SIM_PERSON.lastDestinationUpdate` ("timestamp of the latest destination recalculation", `engine.d.tl:1109`) is a
  direct churn measure, readable in game (`docs/findings/lines-vehicles.md:84-90`); its unit is unknown (logged raw).
- No line-changed game event exists (gamescript.d.tl has only ticket-price, line-usage and arrive-at-stop events),
  so Q4 polls `lineSystem.getLines()` and each LINE's stops.
- `api.gui.benchMark.getGameStepTimes()` (`gui.d.tl:904`, GUI thread only, unused by the base game) gives sim step
  times: the Q5 cost measure, with game days per real second as the fallback.
- `townDevelopInterval` is largely shadowed by hardcoded Lua cadences (`towns.script.tl:10`, `company.script.tl:12`
  TODOs; `town_growth.script.tl:12`).
- `missionEmissionsScriptFactor` is read by Lua every update (`emissions.script.tl:27`): if runtime writes work, it is
  a certain-effect runtime lever and a clean write witness (not in the probe yet).

## Phase 2 (later): LOD threshold / bridge probe

Mod `mods/square_lod_tuner_probe/`. `addModifier("loadModel", fn)` in `runFn`: log that it fires, for which
model kinds, then rewrite each `lods[i].visibleFrom/visibleTo` as `d' = T + (d - T) * k` for `d > T` (T threshold,
k scale), hard cutoff at a far limit, extra factor for bridge/tunnel models. Check: no gaps between LODs, no
popping near the camera, loading time, and frame time / instance count (in-game debug "Total instances")
before/after on a big map. Only worth it if Phase 1's measuring setup shows rendering is a bottleneck.
