# Findings: Lines, vehicles and traffic

In-game verified facts; index and rules for adding entries: `docs/findings.md`.

## Stress Test probes (2026-10-10)

First in-game run of `square_stress_test`'s Probe tab (plans/square_stress_test/TESTING.md), a running free game
(not the map editor), build 40420. Evidence: `[SQST]` / `[SQST-PROBE]` lines in stdout.txt. All commands were sent
from the GUI state's `react.onStep` (Main Thread) through `api.cmd.sendCommand`.

- **Create a town in a running game (`town_create`): works.** `api.engine.mapgen.createTowns(seed, { one Map.Town })`
  then `api.cmd.makeTownCreateCmd` on its `toAdd`. `toRemove` came back as **all existing towns** (3 of 3): createTowns
  treats its input as the whole town list. The probe ignored it and no town was lost. Callback after 655 ms; the new
  town had `initialLandUseCapacities` {100,100,100}, `sizeFactors` {1,1,1}, 58 buildings, person capacities {97,93,93}.
- **Bigger towns (`town_create_big`): accepted.** Overwriting the TownInfo's `initialLandUseCapacities` with
  {1600,1600,1600} before `makeTownCreateCmd` was kept as given. Callback after 3962 ms; 580 buildings, person
  capacities {1537,1561,1416}.
- **Grow a town (`town_grow_x10`): works, almost at once.** `makeTownUpdateSizeCmd` with `sizeFactors` {10,10,10} and
  `updateAllBuildings = true`: callback after 2700 ms, `sizeFactors` read back {10,10,10} (not clamped), buildings
  58 → 343 within 5 s and 345 at 30 s; person capacities {97,93,93} → {836,878,974}.
- **Year jump:** `makeGameSetDateCmd(Date.new(2100, 1, 1))` → `success=true`, `getYear()` 2100 at once.
- **Money top-up:** the keep-balance loop (`makeJournalBookAssetCmd`, player `ACCOUNT` balance read) worked; the balance
  showed 204M on screen.
- **`api.engine.getEntitiesWithComponent(BASE_EDGE_STREET)` throws "Cannot loop over this component type".** `BASE_EDGE`
  throws the same (square_better_minimap, 2026-10-09). To list every edge, use
  `api.engine.system.streetSystem.getNode2StreetEdgeMap()` / `getNode2TrackEdgeMap()` (each edge appears under both of
  its nodes, so de-duplicate). Not every
  component type can be listed this way; `TOWN` works. Base GUI code only lists `TOWN`, `INDUSTRY`, `VEHICLE_DEPOT`,
  `TRANSPORT_VEHICLE`, `WAREHOUSE` and `STATION_GROUP` with it. Count street edges with
  `api.engine.util.octree.findEntitiesInCircle(pos, r, BASE_EDGE)` filtered by a `BASE_EDGE_STREET` component instead
  (that made probes 3a/3b fail; fixed, not re-run yet).

Second run (2026-10-10, build 40420, same setup):

- **Big growth factors (`town_grow` with {100,100,100}, `updateAllBuildings = true`) on Tacoma** (initCaps {233,314,244}):
  callback 3956 ms; buildings 499 → 816 within 5 s (818–821 at 30 s); person capacities {1347,2033,1742} →
  {4415,6958,7522}, about 19k capacity. The factor is **not clamped**, but the **building count plateaus** (probably
  street space) while the person capacity per building keeps rising.
- **`makeTownDevelopAtCmd(pos, true, true)` is not a useful generator.** 9 calls on a 150 m grid all returned success,
  but street edges +0 and buildings +0 (Tacoma 155 → 155, Vancouver 23 → 23 edges). The single-call run showed
  buildings +344, but a ×10 growth of the same town ran at the same time, so that number is not DevelopAt's. It adds no
  streets; the Stress Test has no "Develop now" button.
- **Town creation must be serialized.** `town_create_big` clicked several times quickly: all succeeded, but the
  callbacks slowed to 10–12 s and the before/after town-set diff reported the same "new" town for two creations (a race
  in the probe). One `makeTownCreateCmd` in flight at a time, the next after the callback.
- **Speed 8 sticks:** `makeGameSetSpeedCmd(8)` → `GAME_SPEED.speedup` 8 after 15 s, while
  `getEstimatedMaximumGameSpeed()` said 23. Speed 16 not tested yet.
- **`GAME_SPEED.speedup` reads 0 while paused (console, 2026-10-17, live session of that day)**:
  `api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED).speedup` printed `0`
  paused and `4` at speed x4 (the tealdef's "0 = paused"). Game-script `guiUpdate` keeps running while paused and
  real-time clocks keep moving, so a mod that must stand still while paused gates on this (Organic Towns rev 2).
- **Journal booking of 1e9 works** (balance 204M → 1.204B). 3e9 (32-bit overflow) not tested yet.
- **Emissions (`emissions_zero`) unresolved:** `makeEntitySetEmissionsCmd(e, 0, 0, r, r)` on 10 of 5180
  `EMISSION_EMITTER` entities (that type *is* iterable with `getEntitiesWithComponent`): read-back zero = 0/10 after 2 s
  and 0/9 after 30 s, with `missionEmissionsScriptFactor` = 1; the restore command reported failure. Either the command
  doesn't take effect or the read-back reads a different field.
- **Not run yet:** probes 4 (street from scratch), 5 (buy vehicles: the test save had no line), 6b (speed 16),
  6d (3e9 booking), 7 (runtime `baseConfig.noCosts`).

Third run (2026-10-10 06:15–06:26Z, build 40420, Towns and Traffic tabs; user: "it looks like it's working well"):

- **Spawn spread over the map** (bounds -4096..4096): 5 + 8 medium towns created serially, 1.3–2.0 s each,
  `initialLandUseCapacities` 400 kept, 175–250 buildings each. `makeTownCreateCmd`'s `resultEntities` came back
  **empty** (results=0); the new town is found by diffing the town list.
- **Placement was too strict:** Huge (3200, spacing 2500 m) near the camera placed 0 of 1 (16 candidates: near=12,
  edge=4), so Huge is still untested; after ~16 towns the coarse spread grid had 0 valid spots for Small (near=16).
  Fixed afterwards by relaxation steps (wider ring, 70 %, 50 % of the spacing, finer grid; never below 800 m).
- **`makeTownConnectWithIndustriesCmd`** with `getDefaultTownConnections`' `{{0,1}}` (0-based) and `keep = true`:
  success, ~0.8 s each.
- **Grow: one `makeTownUpdateSizeCmd` builds only ~250–350 buildings, and re-sending it keeps building.** Callbacks
  0.4–8 s per town, longer for bigger towns. With the SAME factor (1000, already capped) and
  `updateAllBuildings = true`, Town 10 went 889 → 1193 → 1494 → 1732 → 2065 → 2314 over 5 calls (~4 s each). The
  factor isn't the limit (this replaces the second run's "plateau" reading); hence the Grow form's build-out passes.
- **Freeze/unfreeze** 19 towns (`makeTownSetDevelopmentActiveCmd`): ~100 ms.
- **Hide notifications:** success with 29 type names from `getNotificationType2Label`, so `notification_util`
  resolves from a mod GUI script.
- **Add vehicles:** 25 buses on one line from depot 11332 (`findBestLineAndDepotForVehicle`), `makeVehicleSetLineCmd`
  true for all 25, ~0.6 s per vehicle, 0 failures; balance 193.1M → 104.4M (price check fine). Lines with no vehicle
  were skipped correctly.
- **Speed 16** was sent; no read-back logged (still unconfirmed).

Fourth run (2026-10-10 06:42–06:44Z, build 40420, Probe tab probes 4 and 9, Towns tab):

- **Street from scratch (`street_from_scratch`, probe 4 variant A): works.** A `SimpleProposal` street edge (`type` 0,
  `typeIndex` -1, `streetEdge` copied from a reference edge, template `country_new_small.street_template`) sent with
  `makeWorldBuildProposalCmd`: `success=true`, `critical=false`, no messages, cost ~36.6k, street edges +1. Worked 3 of 3
  times. Auto bus lines can build their own streets; stops and depot are still open (probe 10).
- **`SIM_PERSON` is iterable** with `getEntitiesWithComponent` (9a census: 693 persons, `scanMs=1`). By `lastMoveMode`:
  DRIVE=79, WALK=614. Persons driving right now (DRIVE + `MOVE_PATH`, no `SIM_PERSON_AT_VEHICLE`) = 63, and **all 63 have
  a `LAND_VEHICLE` component**: a private car is a `SIM_PERSON` with `LAND_VEHICLE` + `MOVE_PATH`, not an entity of its
  own. `LAND_VEHICLE` itself is **not** iterable. `lastMoveMode` 1 = DRIVE. `SIM_PERSON` fields: cargoType,
  destinations{3}, moveModes{3}, travelTimes, targetOrAtEntity, lastNonResType, lastMoveMode, walkSpeed, modelIdPerson,
  colorConfigPerson, modelIdCar, colorConfigCar, lastDestinationUpdate, landUse2ReachableWalkDrive,
  landUse2ReachableLines, pickupTime, happiness.
- **`api.cmd.debug.makeSimPersonSetStateCmd` works from a GUI script in a normal (release) game.**
  - State **2 (jump home)**: all 5 picked drivers were at their home building with no `MOVE_PATH` after 2 s; the car
    disappears from the road. Repeated 4×5 with the same result. By +15 s, 1–4 of the 5 were driving again (they start
    their next trip), so clearing traffic for good means repeating it.
  - State 1 (new path): no visible effect (still driving).
  - State 0: the command failed (callback `success=false`).
- **`PERSON_CAPACITY.pathfindingPreference`** on town buildings (9d): `destinationWeight=1`, `disallowedMoveModes={}`.
  Read-only: no command writes it.
- **Spawn Huge (3200)**: `initialLandUseCapacities` {3200,3200,3200} kept, 716 buildings, person capacities
  {1972,2605,2688}, 5.5 s.

Fifth run (2026-10-10 07:05–07:07Z, build 40420, Traffic tab Clear traffic, Probe tab probes 10a–10d):

- **Clear traffic works at scale.** One click scanned 11,096 `SIM_PERSON`s and found 285 drivers: 285 sent, 285 ok,
  333 ms wall (spread over frames). A second click right after found 64 drivers, 54 ok (the other 10 had changed state
  in between). **Keep cleared every 5 s** finds 205–349 drivers again each cycle (traffic regenerates within 5 s),
  382–394 ms per cycle, ok ≈ sent.
- **Bus stops by script work (10a/10b).** Variant A (the replacement edge's `comp.objects` holds the stop with the temp id
  `-400000000 + index`, `STOP_RIGHT`) succeeded on all 6 stops, cost ~39–42k each, one new `STATION_GROUP` per stop
  (found by diffing the list). Stops on edges 31–88 m long worked. Variant B was never needed.
- **Road depot (10c): placement often collides.** With the depot's free entrance node 22 m off the street centre
  (construction origin ~57 m from the edge middle), the build often came back `messages={Collision}` on both sides,
  once `critical` "Construction Not Possible" (the transform has no `-0` entries: every one goes through `z0`;
  cause unknown, maybe terrain). It succeeded 2 of 5 times.
- **A construction build's `resultEntities[1][1]` is not the construction.** The log said
  "construction=10438 has no CONSTRUCTION component" while `VEHICLE_DEPOT` went 0→2 (new 11468, 11587). Find a new
  depot by diffing the `VEHICLE_DEPOT` list and map it to its construction with
  `streetConnectorSystem.getConstructionEntityForDepot`. The probe stopped there, so the entrance connection is
  still untested. `cmd road_depot_here:build failed` lines next to a success are the refused tries of the other side.
- **10d found no depot**: "depot=nil (none)" although 11468/11587 existed. The fallback (nearest road depot within
  1500 m of the camera) filtered on `VehicleDepot.carrier == ROAD` and read the position through
  `construction.transf:getTransl()`; one of the two failed. Base code derives a depot's carrier from its
  `transportModes` (`gui/line_vehicle_mgmt/vehicle_util.tl:54-75`). The lookup now accepts either and falls back to the
  depot's `BOUNDING_VOLUME`, and logs per depot what it saw (not re-run yet).
- Fixed afterwards (not run yet): 10c walks candidate spots (along the edge at 0.5/0.25/0.75, both sides, entrance
  30/45/60 m off) over the 3 nearest edges, pre-checks each with `api.engine.util.proposal.makeProposalData` (depot and a
  stand-in stub street) and sends only clean spots; the new depot comes from the `VEHICLE_DEPOT` diff.

Sixth run (2026-10-10 07:40–07:45Z, build 40420, a 53k-person map, Traffic tab):

- **Auto bus lines in a dense town (SQST Town 6): the depot search failed every time**:
  `depot: edges=4 spots=72 tried=72 pre={Collision=72} sent=0 | no spot left` (the 4 outermost town edges, 3 gaps x
  3 params x 2 sides each, all refused by the `makeProposalData` pre-check). The stops and the line had been built
  **before** the depot step, so each failed try left an empty line with 2 stops behind (SQST Bus 3, 6, 9, 12) and
  spent the stop money. Fixed afterwards: the depot comes first (nothing is built without one), searched in rings
  outward from the centre with more gaps, any player road depot within 2 km counts, and a line left with no bus is
  destroyed again (not re-run yet).
- **Once a depot existed (151591, built by the user), 2 runs of 4 lines x 10 buses all worked**:
  `findBestDepotForLine` found 151591, 40 buses each run, ~6 s per line (11–14 s while Keep traffic cleared ran),
  2 stops 301–440 m apart on built-up edges.
- **Line names skipped by 3** (SQST Bus 3, 6, 9, 12, 15, 18): one counter was shared by the 2 stop names and the line
  name. Fixed: a counter of its own, continuing after the highest existing "SQST Bus N".
- **Three quick clicks queued 3 batches** (3 "bus_lines: 1 towns x 4 lines" plans). The buttons now refuse while the
  same kind of job is queued or running (bus lines / their removal; add / sell vehicles).
- **Remove added bus lines works**: 40 sold, 8 lines deleted, 0 failures (`makeLineDestroyCmd` after the buses are
  sold). **Ignore town emissions** (Game tab town ratings): 13 towns, 26 events ok. **Add vehicles 10**: 10/10
  bought. **Keep traffic cleared on 53.8k persons**: 2.4k–12k drivers per 5 s cycle, 1.1–3.8 s wall per cycle,
  0 skipped cycles.
- **Crash at 07:45:22Z, unexplained.** In the same second as the 3rd batch's "bus_lines 4/4 ... ok" and its summary
  (12 lines and 120 buses this session; 40 buses sold and 8 lines destroyed at 07:41:59), the Simulation Thread hit
  `Engine.h:323 GetComponentDataIndex` "Assertion it != components.end()" for entity 152444, component type 73 =
  TransportVehicle. 152444 then had TpNetLink, BoundingVolume, LotList and TerrainAlignmentList, which looks like
  a street stop / edge object, near the ids of the stops just built (station groups ~1525xx–1530xx). Suspected:
  something still referenced a sold bus's id after the id was reused, or a vehicle on an edge our stop proposal
  replaced; not proven, and no `[SQST]` line named 152444. Guards added afterwards: every vehicle or line id is
  re-checked (TRANSPORT_VEHICLE / LINE component, PLAYER_OWNED) right before its command, removal waits until the
  sold buses are gone and never deletes a line that still lists vehicles, stop edges with moving sim persons
  (`getSimPersonsMovingForTransportNetwork`; on street edges see "`getSimPersonsMovingForTransportNetwork` on streets" below) and edges near our stops or depot gates
  come last, and every bought bus id and every stop's station group and result entities are logged (`rt.detail`)
  so a future crash entity can be matched against stdout.txt.
- **Unrelated(?)**: at 06:32:24Z, during a save load (no `[SQST]` line nearby), the Simulation Thread hit
  `gamescript_util.cpp:385` "Assertion 'false' failed", logged as a fatal-error exception, but the game kept
  running. Later traced to `state:get_native()` in the SQ Opt AAT fork; see "Game-script `get_native` asserts".

## Line Rate, cloning onto a line, sell on arrival (verified in game 2026-10-10)

Probe `mods/square_line_rate_matcher_probe` (log `plans/square_line_manager_plus/rm_probe_run1.log`, plan
`plans/square_line_manager_plus/history/RM_PROBE.md`), passenger ship line, game paused (game time constant all run).

- **Rate (`calcLineStationThroughput`) is linear in the vehicle count and computed, not measured:** 1 / 2 / 3 identical
  ships gave 51 / 103 / 154, and it updated within 1 s of the command **while paused**. So `perVehicle = rate / n`
  predicts the Rate of n±k exactly for identical vehicles.
- **Clone onto the selected line works:** copy `TRANSPORT_VEHICLE.transportVehicleConfig`, `makeVehicleBuyCmd(player,
  depot, config)` (callback success, `cmd.resultVehicleEntity`, ~0.35 s), then `makeVehicleSetLineCmd(new, line, 0)`
  (~0.55 s): the vehicle is `EN_ROUTE` on the line. `findBestLineAndDepotForVehicle(src)` returned the selected line
  and its depot here (single test; it may differ on other lines).
- **`makeVehicleSendToDepotCmd(v, true)` drops the vehicle from the line at once:** state `GOING_TO_DEPOT`, `line=-1`,
  `sellOnArrival=true`, and Rate falls immediately. A vehicle heading to the depot is not counted. Only the
  command was probed, not the arrival: see "Sell on arrival crash" below; sell with `makeVehicleSellCmd` instead.
- `TransportVehicleConfig` capacities are indexed by cargo type id + 1 (`Passengers#0=20`).
- A button left of A+ via the wrapped `makeIconToggleButton` (order 250) sits left of Line Revert's undo/redo (order 200)
  and both work.
- Supply walk on a cargo line (WC Logs, 2 ships, Rate 66): stop 1 reaches the logging camp; `getCargoMaxProductionPerYear`
  = `produceFrequency` = `getIndustryProductionData.total` = **101** (the industry window's number), while
  `getCargoProducedPerYear` is a measured value that drifts (112 one minute, 98 the next). Use 101 as the target and show
  the measured value only as a hint. The other lines at that station group were passenger lines: the "other lines
  loading this cargo" sum must check each line's stop `load[cargo+1]`, not just the shared station group.
- **A clone bought with `purchaseTime = now` costs exactly the model's metadata `cost.price`** (verified 2026-10-11,
  Line Rate Matcher phase 3e, WC Logs, one Sydfart): balance 2,062,832 -> 1,514,192 = 548,640 = `cost.price` =
  `getPartPrice` of the fresh clone part = the vehicle store's price. `getPartPrice` of the owned template part
  returned 70,484 = its `getDepreciatedValue` (a used part's value, not a new price). Base vehicles have
  `cost.price = -1` / `runningCosts = -1`, filled at load as runningCosts = c x averageSpeed x capacity and
  price = 6 x runningCosts (`base/content/base/model_metadata_util.lua:488-552`); `getRunningCost` of an owned
  vehicle (91,440) matched the metadata. Log: `[RateMatcher] clone charged: balance 2062832 -> 1514192 = 548640 for 1
  vehicle(s); store price each 548640`.

## Sell on arrival crash (game log 2026-10-13, inferred, strong)

Session `2026-10-13_2140_sqrl-sqsg-crash` ("sub-arctic - line manager test", build 40420, Line Manager Plus rev 7
before this fix): at 21:41:39Z the Rate Matcher sent 7 ships of line 183929 to their depot with
`makeVehicleSendToDepotCmd(v, true)` (callbacks `ok 7/7`). 17 s later the Simulation thread logged `ProposalData error:
Collision` and then the fatal `Engine.h:323 GetComponentDataIndex` "it != components.end()" for entity 184016,
component type 71 = `TransportVehicle`; 184016 was a ship being removed (revision 41 -> 42, still listing
TransportVehicle, Ship, MovePathAircraft, CarriageList, Account, LogBook). Crash save
`crash_sub-arctic - line manager test_2026-10-13_14-41-57`. Session `2026-10-13_2213_sqrl-sqsg` (same save, the
fix: `makeVehicleSellCmd`, ids logged) sold the same 7 ships, **184016 among them**, so the crashed ship was one sent
to be sold on arrival; the sim then ran about 35 s (twice the time to the earlier crash) through two more Rate
Matcher switches and sells, with no assert, and the player quit to the main menu normally. Telling point: **no base GUI ever sends sell on arrival**: every
Sell (vehicle window `vehicle.tl:361`, manager `manager_window.tl:2244`, `:5344`, `:7261`, mission tasks) uses
`makeVehicleSellCmd({...})`, and "Send to depot" passes `false`. Rule: sell with `makeVehicleSellCmd`, never
`sellOnArrival = true`. Open checks: a longer run with the fix; loading the crash save (ships still sold on arrival)
should crash again when they reach the depot.

## Re-sending a vehicle to its own line, departure schedule (verified in game 2026-10-10)

Probe `mods/square_lmp_probe` (log `plans/square_line_manager_plus/probe_run1.log`, analysis
`plans/square_line_manager_plus/history/PROBE_RESULTS.md`). Bus line, 4 stops, 4 buses (8 seats), already evenly spaced
(gap/H 0.91-1.11); one cargo ship line (Logs, 2 stops, 2 ships). Game speed 1x, later 4x. No train line tested.

- **`makeVehicleSetLineCmd(v, sameLine, i)` on a vehicle already on that line is accepted** (callback `success=true`
  after 0.23-0.37 s, 5 of 5) and the vehicle stays on the line (`line` unchanged, never `-1`).
- **Buses ignored the stop index: each drove on to its next stop in line order and served every stop** (4 of 4: sent
  to 1 from stop 3 → arrived at stop 0; sent to 3 while heading to 0 → stopped at 0, then 1; sent to 0 while heading to
  2 → stopped at 2; sent to 3 while heading to 3 → stop 3). `stopIndex` right after the command was the old next stop
  (`SEND plan ... stopIndex=3 -> makeVehicleSetLineCmd(123418, 125579, 1)` then `track callback ... stopIndex=0`). The
  cyclic order of the buses never changed. Whether the engine ignores the index or routes along the line through every
  stop is not settled; either way a bus can't be moved forward into a gap this way.
- **A ship on a 2-stop line took the index:** heading to stop 1, sent to 0 → `stopIndex=0` at once, and its track
  curved round (distance to stop 0: 899 → 993 → 700 over 22 s), i.e. it turned around. Arrival not observed.
- **A train ignored the stop index too (console 2026-10-18, live session of 2026-10-18_1920):** `Train 1` (123940,
  3-stop line, next stop 2, state 2) sent with `makeVehicleSetLineCmd(v, sameLine, 1)`: callback `ok=true`, but
  `stopIndex` right after was still 2 (`SQSEND direct Train 1 123940 ok= true was 2 target 1 now 2 state 2`), as with
  the buses. Whether it then drove on to stop 2 was not watched.
- **Sending it to a depot first doesn't help (console 2026-10-19 00:30Z, live log):** vehicle 97147 on 4-stop line
  115108, next stop 2: `makeVehicleSendToDepotCmd(v, false)` (ok) and, from its callback, `makeVehicleSetLineCmd(v,
  line, 0)` (ok) left it on the line with `stopIndex` 2 and state 1 (`SQSEND relink ok= true target 0 now 2 state 1
  line 115108`): the index didn't stick. Not tried: `jumpToDepotEntity` (teleport into a depot) before the relink.
  So a running vehicle can't be sent to a chosen stop of its line (buses, train, depot route); only the ship on a
  2-stop line took it.
- **Cargo stays on board:** 8/8, 8/8 and 7/8 passengers and 20/20 Logs were still aboard after the command; the buses
  unloaded normally at their next stop (`Passengers#0=8/8` → `3/8` → `0/8` at stop 3). A bus sent while
  `AT_TERMINAL`/`Loading` (0/8, just unloaded) **left at once without loading**.
- **The command wipes the vehicle's history:** `lineStopDepartures` → all 0, `sectionTimes` → all 0,
  `visitedStops` → `[]`, `lastLineStopDeparture` → 0; they refill as it departs/arrives again (first departure after
  30-163 s here, one section per arrival, a full round trip ≈ 6 game min before its `sectionTimes` are complete).
  `line_util.calculateFrequencySeconds` moved from 97-100 to 109-111 s on the bus line and 404 → 415 s on the ship
  line after the wipes.
- **Units:** `GAME_TIME.gameTime` and `lineStopDepartures` are milliseconds (10 000 per 10 s at 1x);
  `sectionTimes`, `timeUntilDeparture`, `timeUntilNextScheduledDeparture` are seconds. `lineStopDepartures[i]` is the
  last departure from stop i (1-based); the stop of the latest one agrees with `stopIndex` (0-based next stop) in every
  sample. `sectionTimes[i]` = driving time stop i → i+1, **without dwell**, set on arrival (175083 left stop 0 at
  79682600, `sectionTimes=[58.40,...]` on arrival ≈ 79741000, departed 79751200: departure gap 68.6 = 58.4 + 10.2 s
  dwell). So Σ`sectionTimes` (356 s) is ~10% short of the departure-to-departure round trip (392 s) and of
  frequency × n (400 s).
- **`timeUntilNextScheduledDeparture` counts down only while the vehicle is at a stop** (frozen en route) and is set on
  arrival to (latest other-vehicle departure from that stop + line frequency) − now: 123418 arrived at stop 3 with
  +15.80 s, and 175083 had left stop 3 at 79529400 (+100 s = 79629400 ≈ 79614000 + 15.8 s); 134570 at stop 1: +0.60
  ↔ 72235's departure + 100 s. Late vehicles show large negatives (−81). With no recorded departure at that stop
  (all wiped) it starts at ≈ 0. Departures at each stop were 93-108 s apart (frequency 100 s) before the probe.
- **`WaitForScheduledDeparture` seen once** (bus 123418 at stop 0, after its re-send): `tUntilDep` 7.40 → 3.40 → left,
  while `tUntilSched` was already negative (−5.60). So it isn't simply "`tUntilSched` > 0"; its trigger is still open.
- The probe's `simEntityAtVehicleSystem.getVehicleSimEntitiesCount(v)` printed `table: 0x...`: it returns a table, not
  a number. `getVehicleSimEntitiesCountForCargoType(v, cargo)` returns the count.

## Sim crash while bus lines were added with "Car traffic" on (2026-10-11, cause suspected, not verified)

Stress Test Showcase with Traffic = Bus lines, load settings Car traffic = Drive: destinations (town shops and
workplaces disallow WALK and LINES) and Town building capacity = x4 (`[SQST] town_building_patch` active): seconds
after the first two showcase bus lines were created, failed (`setLine failed`, `findBestDepotForLine=-1`: the reused
depot was in an unconnected town group) and were destroyed, and a depot connect was refused (`Construction Not
Possible` at the map edge), the simulation thread asserted `Engine.h:323 GetComponentDataIndex it !=
components.end()` (entity 21742 "not known, probably being added", component type index 27; crash json
ca9a2f49-..._3.json). Suspect: the patched `disallowedMoveModes` meeting the save's first lines. Next check: the
same run with Car traffic = Default and capacity x1 (TESTING 6I / 6K). Until settled, don't combine Car traffic
with bus lines. Update 2026-10-12: the same session's Showcase links had left 37 nodes without `BASE_NODE_CONFIG`, two of
them in the towns of the route being worked on at the crash; roads.md "Script link roads without node configs" (the
more likely cause now, still a correlation).

## Script-built road depots: the gate join (game log 2026-10-12, seeds 204313 and 488838; fix not run in game yet)

`square_stress_test` Showcase bus lines (`[SQST] bus_lines_showcase`, archived sessions
`2026-10-12_0525_showcase-204313-crash` and `2026-10-12_0905_top-up-488838`). The depot (`road_depot.con`, its
entrance street `entrance_new` from the free node at local (0,-35), 4 lanes 3/5/5/3 m) is built first, then a second
proposal splits a street edge and adds a stub from the split node to the depot's free node.

- **A stub copied from an 8-lane `town_new_large` street into the depot's free node was refused "Construction Not
  Possible" every time** (seed 488838: 12-18 sends per route, 3 routes; seed 204313 the same), while the same split
  and stub to a new stand-in node pre-checked `ok` (`makeProposalData`). The only difference: the stub ending on the
  depot's existing node, whose one edge is the 4-lane entrance street. Inferred (not proven): a joint of two lane
  layouts at an existing node is refused, as the pre-check's "Construction Not Possible" for a lane index past a
  street's lanes (towns.md). The stub is now the small town street (`town_new_small` has the entrance street's exact
  lanes and style) with a full gate config; the next run's `laneConns` log settles it.
- **A gate that did join (`streetEdges at node 1->2`) kept 0 lane connections: the HUD's red no-entry sign at the
  depot entrance (user screenshot), and `findBestDepotForLine` = -1 for a line next to it.** Same as the plain join of
  a town dead end (towns.md "Joining a script street to a town dead end", D1). Joins need the D3 config: the node in
  `nodeConfigsToRemove` (only if it has a config) and a full config in `nodeConfigsToAdd`; for the 4-lane gate
  `entrance -> stub` and `stub -> entrance`, lane 1 -> lane 2. Check a script-built depot's gate by its node's
  `BASE_NODE_CONFIG.laneConnections` (0 = dead end), not by the street edge count.
- **`api.engine.util.town.getClosestTown` is no "on the town's streets" test**: a Showcase junction's arm 700-1200 m
  out still named the nearest town, so a depot went next to a highway ramp. Keep script stops and depots to the
  town's own street area (here its square grid) and out of junction areas.

## Passenger catchables include industry workplaces (verified in game 2026-10-07)

`api.engine.system.catchmentAreaSystem.getStationCatchables(station, false)` returns every PersonCapacity holder in
reach, including an industry's own workplaces: a factory-only stop had 1 passenger catchable and 0 town buildings
(square_no_factory_passengers). To test for real homes or town jobs, keep only entities with a `TOWN_BUILDING`
component, or the entity a `TownBuilding.personCapacity` points to.

## `getEntitiesWithComponent(MODEL_PERSON)` can't be listed (verified from the game log 2026-10-13)

Photo Mode's person picker (GUI script, Main Thread) called `api.engine.getEntitiesWithComponent(
api.type.ComponentType.MODEL_PERSON)`: it raised `Cannot loop over this component type` at every call (session
`2026-10-13_0325_session`, `[PhotoMode] list persons: MODEL_PERSON not listable ...`, 4 times). `SIM_PERSON` lists
fine (8765 persons, 0.5-0.9 ms), and the picked persons got a position (Photo Mode reads `MODEL_PERSON.position`
with `getComponent`, else the bounding volume; which of the two answered was not logged). List `SIM_PERSON`; don't
call the MODEL_PERSON listing at all (each failed call logs a traceback).

At 12.5k persons the `SIM_PERSON` listing still fits in a ~2 ms frame (inferred bound, session
`2026-10-15_1950_city-lights-2-778824`): Smart Lanes' snapshot listed 12 518 persons at ~20:03:05 and SQPERF's
wall-clock maximum of that step over 20:02:40-20:03:10 was 1.886 ms (`ctx=bg ... auto ... max=1.886`), the list call
included. The 49 / 81 ms "person-list spikes" of that run were `os.clock` readings (docs/findings/gui.md "Timers and
threads"). No per-area person query is verified: whether `api.engine.util.octree.findEntitiesInCircle` returns
`SIM_PERSON` entities is untested (console snippet: plans/square_smart_lanes/TESTING.md "KA v4" step 14).

## `getSimPersonsMovingForTransportNetwork` on streets: persons routed through, cheap; junction nodes often 0 (game log 2026-10-12)

Stress Test probe 11c, session `2026-10-12_0905_top-up-488838` (`.cache/logs`, lines ~18635-18660), congested
Showcase map, entities near the camera:
- Street edges: 12 of 12 calls ok, 240-360 persons each (median 315), 32-232 us per call (median 34). Junction
  nodes: 13 of 13 ok, but median **0** (some 311-709), 29-329 us.
- Neighboring edges return nearly the same list (same leading ids), and 300+ per edge is far more than the cars on
  one edge: the list is persons whose **route** passes the entity (demand), not cars on it now. Every one sampled
  was a driver (600 / 600 on edges). Whether it is complete for the cars on the entity was not checked (no known
  driver was in the sample: `expectedFound=0/0`).
- Use: a cheap candidate list of drivers near a junction (query its segments, not only the node), then filter by
  position and `MOVE_PATH` (square_smart_lanes Re-time, `sl_retimer.lua`). Plans: `plans/square_stress_test/FLOW_PLAN.md`
  "Probe answers".
- **On a removed segment it costs ~100 ms and an engine assertion** (session `2026-10-15_0509_light-plans-auto-863105`,
  05:14:12, inferred from timing, not isolated): Smart Lanes' automatic re-timing asked the routed lists of a junction's
  segments every 3 s; the Stress Test replaced two of them (306823, 297327) mid-window, and in the same second the Main
  Thread logged `Engine.h:323 GetComponentDataIndex` "Assertion it != components.end()" for exactly those two ids,
  "Component Type Index: 0" (the only two such lines in the session), and SQPERF timed that frame of the runtime at
  249 ms (`ctx=bg slow=auto max=249.0 over=1/25482`). Whether it also throws into Lua is unknown (the call was pcall'd and
  its error ignored); the cost is the engine's assertion and trace. Check the entity first (`getComponent(e, BASE_EDGE)` pcall'd; `entityExists` is
  not enough: ids are reused at once) and drop it when gone (`sl_autoretime.lua`: the snapshot skips it, `op=snapshot gone=`;
  `op=member_gone` before step B v4).

## A driver's `MOVE_PATH.path.edges` elements are userdata read as `elem.edgeId.entity`; a positional pass count matches the path count (verified from the game log 2026-10-13)

Session `2026-10-13_0610_session` (Stress Test bench sheets 1 and 2, seeds 954486 and 571569; the traffic log sampler,
`mods/square_stress_test/content/stress/gui/stress_flow_log.tl`, FLOW.md "thru").
- **The path elements.** Every element of a sim person's `MOVE_PATH.path.edges` is a userdata. `elem[1].entity`,
  `elem.first.entity` and `elem.entity` read nothing; `elem.edgeId.entity` (the sampler's reader 4) gives the entity id
  (`FLOW_PATHDBG ... elems=15:userdata/r4/138536/BASE_NODE+TRANSPORT_NETWORK,16:userdata/r4/140558/BASE_EDGE+
  BASE_EDGE_STREET+TRANSPORT_NETWORK,...`). The path alternates junction nodes (`BASE_NODE`) and street edges
  (`BASE_EDGE`), so a junction is ahead / behind a driver by node or edge id; `dyn.pathPos.edgeIndex` indexes it
  (0-based). Earlier sessions (`2026-10-13_0356_top-up-779299`, `2026-10-13_0447_top-up-726115`) read 0 with the first
  three readers only.
- **Two independent pass counts agree.** Per junction and sample the sampler counts cars through (a) by path: on the
  path ahead at one sample, behind at the next; (b) by position: on an inbound approach road (or in the junction) at
  one sample, gone from it at the next (10 game s apart). Over every sample where both were complete: sheet 1 5031
  zone-samples, 52117 by position vs 51709 by path (+0.8 %; per junction 0.99-1.08); sheet 2 5226 zone-samples, 62503
  vs 62431 (+0.1 %; per junction 0.99-1.03). So at 10 game s per sample the positional count is a full count, and it
  needs no path reads (the sampler's heaviest part, ~16 us per driver with them).

## Line "Rate" is carried volume, not capacity; no utilization history (console 2026-10-18, live session)

`api.engine.util.line.calcLineStationThroughput(line)` (the Line Manager's Rate cell) compared with
`api.engine.util.logbook.getLogValuePerYear(line, "itemsTransported")` and the live
`getLineCapacityUsages(line, false)` (used / capacity) over 27 lines of one save:

- One-way cargo lines: transported/year ~= Rate (WC Fish 220 vs 221, 173 vs 168; RC Fish 60 vs 59, 50 vs 47).
- Bus passenger lines: transported/year ~= 1.1-2x Rate (130 vs 69, 54 vs 28, 80 vs 74), passengers both ways.
- New or changed lines differ either way (20 vs 46, 45 vs 97).

So Rate measures what the line carries per year, not what it offers: `transported / Rate` is no utilization. The
Utilization cell is a live snapshot (sum of `used` / sum of `capacity` over cargo types, via
`statistics_react_util.calculateCargoColumnDataForLine(line).coverage`). The only line logbook series the base reads is
`itemsTransported` (yearly); no load or capacity history exists, so an average utilization must be sampled by the mod.

## Listing depots and stations with their construction and cargo / passenger flags (console 2026-10-18, live session)

- `api.engine.getEntitiesWithComponent(api.type.ComponentType.VEHICLE_DEPOT)` lists every depot and maintenance station
  (18 on the test map). `streetConnectorSystem.getConstructionEntityForDepot(depot)` returned the construction for all
  of them; its `CONSTRUCTION.fileName` is `::/depots/road/road_depot/road_depot.con`, `::/depots/road/road_maint_station.con`,
  `::/depots/rail/rail_depot.con`, `::/depots/water/water_depot.con`, `::/depots/water/water_maint_station.con`.
- `getEntitiesWithComponent(STATION)` (238) includes curbside stops (no construction) and every industry's own station
  (`::/industries/<name>/<name>.con`). `getConstructionEntityForStation` gives the construction.
- `api.engine.util.station.isStationOfType(st, true / false)` (cargo / passenger; console: `api.engine.util.station`,
  not `require "util"`, which errors there): cargo rail `stations/rail/modular_station/modular_station.con` cargo true /
  passenger false; a cargo truck terminal `stations/street/modular_street_station/modular_terminal.con` true / false, a
  passenger one false / true, a mixed one true / true; `stations/water/harbor_modular.con` true / true; **industry
  stations report true / true** (passenger true although they take no passengers): filter them by path, not by the
  flags. No airport on the map (stations/air unverified).
- Used by: Organic Towns `ot_engine.facilities` / `ot_industry.classifyFacility` (away from player facilities).

## Default vehicle names and the NAME component (console 2026-10-20, live session of 2026-10-20 02:1xZ)

Read-only console probe for `plans/square_better_auto_vehicle_renamer/PLAN.md` (English game, one vehicle per carrier,
`SQFN veh` / `SQFN names` lines in stdout.txt).
- **Default names are "<carrier word> <number>"**: `Road Vehicle 263`, `Train 13`, `Ship 76`, `Aircraft 2`. The tram word is
  not seen yet (the save had no trams). The words are presumably localized in other game languages (not checked).
- **A default-named vehicle already has a NAME component** (`getComponent(v, NAME)` returned userdata for all four), so
  "no NAME component" does not mark a default name.
- **`api.type.enum.Carrier` values**: ROAD 0, RAIL 1, TRAM 2, AIR 3, WATER 4.
- **`transportVehicleSystem.getVehicleNames(carrier)`** returns the current names of the player's vehicles of that carrier
  (268 road, 14 train, 0 tram, 79 ship, 2 aircraft), unordered.
- `transportVehicleConfig.vehicles[1].purchaseTime` is game-time ms (168703000); a steam train reported 2 parts
  (`2-6-0 Mogul` first); the model display name is `api.res.modelRep.get(part.modelId).metadata.description.name`.
- **Renaming a vehicle works (console 2026-10-20, live session of 04:2xZ)**: `api.cmd.makeEntitySetNameCmd(212817, "Test B-0412")`
  from the console: callback `ok=true`, and `getEntityName` inside the callback already read the new name. The name
  survives a save and reload ("Organic Towns - Subarctic", reloaded 04:29Z: `getEntityName` read `Test B-0412`).
- **Helicopter vs plane**: same carrier (AIR 3). Base planes live under `::/vehicle/plane/`, helicopters under
  `::/vehicle/helicopter/` (`api.res.modelRep.getName(modelId)`); the model's metadata says so too
  (`airVehicle.isHelicopter = true` in `agusta_westland_aw101.mdl`, tealdef `type.d.tl` AirVehicle). Reading it
  from a script works: `api.res.modelRep.get(find(".../agusta_westland_aw101.mdl")).metadata.airVehicle.isHelicopter`
  printed `true` (console 2026-10-20).

## Line Rate formula; driving vs straight-line distance per carrier (console 2026-10-20, live session)

Console read over the save's lines (`SQRMCAL` / `SQRMCAL2` lines in the live log): per line the first vehicle's
capacity for the loaded cargo, `getLineCargoInfo` Σ`sectionTimes` / Σ`driveSectionTimes`, the stops' straight-line
distances (station construction `transf:getTransl()`, cyclic), model top speed and `calcLineStationThroughput`.

- **Rate = Σ over the line's vehicles of capacity × 1460 / Σ`sectionTimes` (s)**, 1460 = the default year (365 × 4 s,
  `api.util.getDefaultYearDuration`), not the calendar year at the current speed (5844 here, millisPerDay 16000).
  Exact on 11 single-model lines (2 bus, 8 ship, 1 air: 115 vs 114.8, 85 vs 85.1, 29 vs 29, 198 vs 198, ...); two
  lines off by 0.92 / 1.25 are most likely mixed fleets (only the first vehicle's capacity was used).
- **Σ driveSectionTimes / (straight round-trip distance / top speed):** ships 1.19-2.07 (median ~1.5, 12 lines),
  buses 1.83 / 2.04, one air line 2.63 (taxi, approach, acceleration).
- **Time at stops (Σ section - Σ drive) per stop:** 9-53 s for ships (13-30 s on single-ship lines), 7-10 s for the two
  bus lines, 21 s air; not explained by capacity / loadSpeed (1-4 s). It includes waiting for other vehicles.
- With no vehicles on a line, `getLineCargoInfo` is nil and `getMaxFrequency` is 0 (Rate Matcher timing log
  2026-10-18_1920 line 59985 before its first vehicle), so an estimate for an empty line must come from geometry.
- Used by: Line Manager Plus Rate Matcher, no-vehicles estimate.

## Vehicle top speed scale: `makeVehicleSetModifiersCmd` (console 2026-10-20, live session of 2026-10-20 05:39Z)

- **`api.cmd.makeVehicleSetModifiersCmd(v, m)` with `m = getComponent(v, TRANSPORT_VEHICLE).modifiers` and
  `m.topSpeedScale = 0.5` is accepted on a running line vehicle** (`ok=true`), and the new value reads back in the
  callback (`SQMOD set 195774 true 0.5`, `SQMOD toggle 105105 ... was 1 ok true now 0.5`). Defaults read
  `topSpeedScale noiseScale pollutionScale comfortScale` = `1 1 1 1`. Setting 1 again restores it (`SQMOD undo 195774
  true 1`, twice). It is not on the game's undo: put the old value back with the same command.
- **The vehicle slowed down visibly** at 0.5 (the user watching road vehicle 105105, model top speed 9.72 m/s); not
  measured. Untested: values above 1, whether the scale is saved with the game, how it meets traffic and speed limits.
- **Reading a vehicle's speed:** the TRANSPORT_VEHICLE entity has no MOVE_PATH (`noMovePath`). Carriage-level
  MOVE_PATH and a position/time measurement (first carriage's `MODEL_INSTANCE_LIST.fatInstances[1].transf`) are untried.
- **A click selects a carriage, not the vehicle** (`Selected entity 199966` had no TRANSPORT_VEHICLE): map it back
  through the vehicles' `CARRIAGE_LIST.carriages`. The console has no "selected entity" call (the selection lives in
  the entity window's `view_manager.tl` state); pick the line vehicle whose first carriage is nearest the camera
  center (`getCameraData().x/y`) instead.

## A line's stop load settings name its cargo exactly (console 2026-10-20, live session)

`LINE.stops[i].stopConfig.load` (37 entries here, index = cargo type id + 1, true = load it) over 15 lines with
vehicles: every bus stop `[0]` (passengers), the loading stop of a one-way cargo line its one cargo (`[6]` fish,
`[7]` meat, `[3]` fertilizer, `[31]` furniture), unload-only stops `[]`; a stone line `[24]` at 6 of 8 stops. So the
stops give a line's cargo without any vehicles (`SQSTOPLOAD` lines). Used by: Line Manager Plus buy_line_filter.lua
(store cargo filter, stops first, vehicle capacity as the fallback).

## Reversing a line vehicle: `makeVehicleReverseCmd` (console 2026-10-20, live session of 2026-10-20 05:39Z)

- **The base Reverse button's command flips the next stop on a 2-stop line:** ship 130260 (carrier 4 = WATER, line
  66530, 2 stops, state 1 = en route) `next 0` → reverse → `ok true next 1`; reversed again → `next 0`. The new
  `stopIndex` reads back in the callback. Reversing twice undoes it (time lost on the way aside).
- Open: what it does on a line with 3+ stops (reversed stop order, or a turn back to the same next stop) and for road
  / rail vehicles. On a 2-stop line "next stop flipped" can't tell the two apart.
