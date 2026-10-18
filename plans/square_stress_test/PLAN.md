# square_stress_test — plan

"Stress Test Debug Tool": a shipped dev mod that turns any free game into a dense, high-traffic, high-population
benchmark in minutes, so square mods can be performance-tested under load (`make perf`).
Research and citations: `RESEARCH.md` (read it first). Most commands are untested in game, so Phase 1
ships the real mod skeleton with a **Probe** tab that settles the open questions before the
generators are built on them.

## Unlike other square mods

This mod **deliberately modifies the save** (towns, vehicles, money, date). The usual
"must not impact saves" rules don't apply, but:
- Nothing happens until the player presses a button (no automatic actions on load).
- `severityAdd: None`, `severityRemove: Warning`, not cosmetic.
- The description says plainly: "for testing; changes your save; use a copy".
- Small saved state, lazy init (the mod may be added to an existing save).

## Architecture

- `mod.json` params (load time, `runFn` → `game.config` / baseConfig):
  - No costs (`noCosts`), Sandbox mode (`sandboxMode`): the official toggles, applied in our own runFn
  - Vehicles never expire (`loadModel` modifier, `yearTo = 0`, as `urbangames_vehicles_no_end_year` does)
  - No noise and pollution (Phase 4; replaced "Town noise ignored"): preRunFn `missionEmissionsScriptFactor = 0` +
    `emission.townNoise*Affected = false`, runFn `loadModel` modifier zeroing vehicle emissions, postRunFn town
    noise/pollution sensitivity 0 in `town_ratings_sensitivity.res`
  - Show probe tab (developers), default Off: without it the Probe tab and `stress_probes.tl` are never loaded
  - Sim person destination recomputation probability (x1 / x2 / x5)
  - Town develop interval (default / fast)
  Numeric params are doubles (`60.0`), and values are 1-based option indices (docs/findings.md).
- **GUI script**: one window opened from a HUD button, with tabs **Game**, **Towns**, **Traffic** (and **Probe** with its param).
  Buttons queue jobs. Commands are sent from `react.onStep` (Main Thread), throttled to N per frame,
  with a progress line. Never from `onStepTimer` or build events (memory notes).
- **Game script** only where needed (state or periodic work such as the money top-up): GUI → game-script
  events via `sendScriptEvent` + `guiHandleEvent` (needs `guiUpdateScript` and `subscribeToEvent`, memory).
- Every action logs one `[SQST]` line to stdout.txt (what, count, ms), so results land in the log next to SQPERF.

## Features (v1)

| Tab | Action | Mechanism |
|---|---|---|
| Game | Add money (+10M / +100M), keep balance above X (toggle) | `makeJournalBookAssetCmd`; top-up reads the player `ACCOUNT` |
| Game | Jump to year (input + Go) | `makeGameSetDateCmd(Date.new(y,1,1))` |
| Game | Game speed 1/2/4/8/16 | `makeGameSetSpeedCmd` (>4 depends on Probe) |
| Game | Town ratings: ignore noise and pollution / restore defaults | base Towns game-script events `setTownRatingSensitivity` (0) / `resetTownRatingSensitivity`, as the town editor sends them (probe 8's per-entity `makeEntitySetEmissionsCmd` route failed; the load-time param covers emissions) |
| Towns | Grow all towns / the town nearest the camera by a factor (x2, x5, x10, x25, x100, reset to x1) | `makeTownUpdateSizeCmd(updateAllBuildings=true)`, serialized |
| Towns | Readout: towns, frozen, person capacity, buildings | read only, every 4 s while the window is open |
| Towns | Spawn N towns (size S) spread over the map / near the camera | `mapgen.createTowns` + `makeTownCreateCmd` (one in flight), optional `makeTownConnectWithIndustriesCmd` |
| Towns | Freeze/unfreeze development | `makeTownSetDevelopmentActiveCmd` |
| Traffic | Add N vehicles to each existing line (cloned from the line's first vehicle and depot) | `makeVehicleBuyCmd` + `makeVehicleSetLineCmd` |
| Traffic | Auto bus lines: per town, stops + depot + line + K buses; remove them again | stop/depot/street proposals (probe 10), `makeLineCreateCmd`, buy + SetLine, `makeLineDestroyCmd` |
| Traffic | Readout: population, vehicles, sim persons, cars driving | read only (drivers from the last clear scan) |
| Traffic | Clear traffic once / keep cleared every N s | `api.cmd.debug.makeSimPersonSetStateCmd(e, 2)` to each driver (probe 9) |

## Phases (each in its own subagent; done = `make check`, `make test`, `make validate` pass)

1. **Skeleton + Game tab + Probe tab.** Scaffold the mod (`make new-mod`), the params, the window, the job queue,
   `[SQST]` logging, Game tab actions, and Probe buttons for RESEARCH.md probes 1–8. Each Probe button runs one
   experiment and logs the outcome. Write `TESTING.md` with the exact in-game probe steps.
   **Stop here: the user runs the probes in game**, and the results go to `docs/findings.md`.
2. **Towns tab**, built on the probe results. (Done. "Develop now" dropped: probe 3 showed DevelopAt adds no streets.)
3. **Traffic tab**: bulk vehicles on lines, the readout, auto bus lines if the probe passed.
   (Part A done, untested in game: add N vehicles per line (serial buy + SetLine, stop after 3 failures or when the
   money runs out), sell the added vehicles, readout lines / vehicles / sim persons (no cheap moving-car count
   exists). Same pass: every tab section became a form with a green action button on its heading row.
   **3B done** (untested in game): "Clear traffic" sends `makeSimPersonSetStateCmd(e, 2)` (jump home) to every
   person driving now, scanned 5,000 per frame over a snapshot and sent 200 per frame through the queue, plus
   "Keep traffic cleared" (every 2 / 5 / 10 s) and "Driving now" in the readout (probe 9, docs/findings.md fourth run).
   **3C auto bus lines done** (untested in game): probe 10's fifth run confirmed stops (variant A, ~40k each); the
   depot build collided often and its result entity was misread, so 10c now walks pre-checked spots
   (`makeProposalData`), finds the depot by the `VEHICLE_DEPOT` diff and connects its entrance; 10d's depot lookup
   was fixed. The helpers live in `gui/stress_buslines.tl`, shared by the probes and the Traffic tab's "Auto bus
   lines": per town 1/2/4 lines of two stops 300-800 m apart, a depot (`findBestDepotForLine`, ours within 1.5 km,
   or a new one at the town's edge), 2/5/10 of the newest buses; serial, a town stops at its first failure, the
   batch after 3 failed towns in a row; "Remove added bus lines" sells the buses and deletes the lines (stops and
   depots stay). TESTING.md 5C. Re-run 10c/10d first.)
   **3C sixth-run fixes** (docs/findings.md "Sixth run"; not re-run yet): the town's depot comes first (ours or any
   player road depot within 2 km, else buildDepot over rings 300-700 / 700-1200 / 1200-2000 / 0-300 m, 15
   fewest-buildings edges per ring, gaps 30/45/60/80 m, else the nearest depot anywhere if findBestDepotForLine
   confirms one); no depot = nothing built. A line left with no bus is destroyed (`wastedStops` in the summary).
   Line names count 1, 2, 3 after the highest "SQST Bus N" (the stop names had shared the counter). The buttons
   refuse while the same kind of job is queued or running (`rt.busyJob`). Crash guards: `rt.isVehicle` /
   `rt.isLine` / `rt.ownedByPlayer` before every vehicle or line command (also in stress_traffic.tl), removal
   waits for the sold buses to be gone and keeps a line that still lists vehicles, stop edges avoid our stops,
   depot gates and edges with moving sim persons, and every bus and stop id is logged.)
4. **Polish** (done, not verified in game yet): "No noise and pollution" load-time param (three parts, see
   Architecture; cited in `stress_logic.tl`), Game tab "Town ratings" (ignore noise and pollution / restore defaults),
   the Probe tab behind "Show probe tab (developers)" (default Off; the module isn't required without it), stale
   phase/probe hints removed from the window, final `description.html` and modinfo, TESTING.md as a pre-release
   checklist (probes in Appendix A). Probe 8 left as it was, marked superseded. Cover entry was already in
   `branding/mods.js` (`_metadata/0.png` rendered).

5. **Junction test** (rev 2, not run in game yet): Towns tab section shown when square_roundabouts' constructions
   resolve (`api.res.constructionRep.find`). `gui/stress_junctions.tl`: a test grid (`towns.createGrid`, no town
   links; the grid code was split out of `spawnGrid`) sized by `logic.junctionGrid` for the selected cases
   (`logic.JUNCTION_CASES`: all 7 menu entries, Channelized X / T and the three Roundabout Interchange layouts as
   separate cases = 10), one construction per cell centre turned 45 deg (pre-checked with `makeProposalData`),
   arm ends = new street nodes within 520 m with one edge (diff 1 s after the callback), grouped within 45 m (highway
   highway carriageway pairs run on as a highway to the town and merge in one node 60 m before it, each one-way edge extended in its own direction; links replace the existing nodes they join so the engine sets up their lanes), assigned to the
   corner town in their direction, then one straight street proposal per arm (pieces <= 200 m, copies of the arm's
   or the town node's edge) to the best town node (`logic.rankTownNodes`; 3 nodes tried). TESTING.md 6E.

6. **Wide streets + Clear traffic Where** (rev 2, not run in game yet): (a) load-time "Town streets: Wide" (REMOVED 2026-10-11: crashed town development, docs/findings.md)
   (`loadStreetTemplate` modifier: simBuildable off on every town template but the large ones, wiki
   tracksstreets.md "simBuildable"); (b) Streets = Wide grid for Test grid / Junction test: our own construction
   `infrastructure/street_construction/square_stress_test_town_grid.con.lua` (geometry `stress/stress_grid_streets.lua`,
   all nodes free, +-200/300/400 m by town size, inside the 485 m reach) built at each grid point before its town;
   (c) Clear traffic Where (Everywhere / In towns / Outside towns): driver position from
   `api.engine.util.vehicle.getPosition` or the MOVE_PATH edge, town areas from sampled building positions
   (cached 60 s). TESTING.md 6F.

7. **More car traffic** (7a built 2026-10-11, not run in game yet; 7b after the test): load-time "Car traffic"
   (town buildings disallow WALK + LINES via `personCapacity.disallowedMoveModes`) and "Town building capacity"
   (x1/x2/x4), both through a `loadScript` modifier wrapping the town building `updateFn`; Traffic tab Scan and the
   DRIVE / WALK / LINES split. Plan, unknowns and test: `MORE_TRAFFIC.md`, TESTING.md 6I.

8. **Bench** (built 2026-10-13, rev 2, unreleased, not run in game yet): Towns tab > Bench, one button per 16 km sheet
   runs a Smart Lanes A/B test end to end (clear the map, year 1950, build twins with towns only on the arms that need
   traffic, Smart Lanes idle, record 20 game min at 2x, screenshots, `BENCH_DONE`); `make bench` writes the RESULTS.md
   draft. Design, sheets, files: `BENCH.md`; in-game steps: TESTING.md 6W. The traffic log's `thru` now counts by
   position (`thru_path` keeps the path count).

9. **Light plans A/B** (built 2026-10-14, rev 3, unreleased; first run 2026-10-15 session `2026-10-15_0355_top-up-488195`:
   axis +23-26 % thru/min vs game, classic worse than game, 6/6 sets): Towns tab > Lights showcase > Build light plans
   A/B: 2x2 X and 3x3 X lit crossroads, 3 sets each on a 16 km map, twins game / sl_phases (Smart Lanes' axis plan) /
   **sl_auto** (the axis plan with Smart Lanes' automatic re-timing, since 2026-10-14 (2); sl_classic, the classic
   patterns, was the console variant `jn.buildLightPlans(seed, "classic")` until 2026-10-16: removed with Smart Lanes'
   classic patterns), balanced (~600-people towns) and
   **unbalanced** sets (north town ~150, south ~40) in turn; `make flow` compares the plans per shape and demand, in an
   auto twin's settled window, and splits a twin re-timed by hand (Smart Lanes' Re-time) before / after. Next to it the
   **Auto re-time** buttons (All lit junctions / Clear: Smart Lanes' `SmartLanes.auto`, whole map; `make flow` splits
   before / after). SHOWCASE.md "Light plans A/B"; steps: TESTING.md 6Z1 (auto twins) and 6Z2 (whole map); not run in
   game yet.

## Verified in game vs not (2026-10-10, docs/findings.md "Stress Test probes")

Verified: the window, HUD button and form layout; Add money, Keep balance, Jump to year, speed 8, the Hide all
notifications event (`success=true`); spawn towns near the camera and spread over the map (Small to Huge), grow
with passes, connect towns, freeze/unfreeze; Add vehicles to lines (25 buses, 0 failures); Clear traffic and Keep
traffic cleared; bus stops by script (probe 10a/b).

Not verified yet: speed 16 read-back; whether every notification popup stays hidden; Reset to x1; Sell added
vehicles; non-bus lines for Add vehicles; Auto bus lines and their removal (depot spot search, depot lookup,
entrance connection: the user's next test); the Game tab's town ratings action; every load-time setting (No costs,
Sandbox, Vehicles never expire, No noise and pollution, trip recalculation, develop interval, Show probe tab).
Checklist: TESTING.md "Release gate".

Unit tests (`tests/square_stress_test/`) cover the pure logic: job queue throttling, town grid sampling,
factor math, param → config mapping.
