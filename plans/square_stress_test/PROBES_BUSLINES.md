# Probe 10: automatic bus lines

Question: can the Stress Test build a bus line by script (two stops on existing streets, a road depot
connected to a street, one line, buses on it)? That would be a traffic generator that needs no player setup.
Probe 5 already showed that buying and `SetLine` works on an existing line; probe 4 that a street edge
built by script is accepted (`makeWorldBuildProposalCmd`, variant A, cost ~36.6k).

## Status after the fifth run (2026-10-10, docs/findings.md "Stress Test probes")

- **10a/10b work**: variant A on all 6 stops, ~40k each, one new `STATION_GROUP` per stop.
- **10c** built the depot only 2 of 5 times (`messages={Collision}` on both sides, once critical "Construction Not
  Possible"), and the follow-up read the wrong entity: `resultEntities[1][1]` is not the construction. The entrance
  connection never ran.
- **10d** found no depot (the carrier / position lookup missed the two new ones).

Fixed since (needs a re-run of 10c and 10d):

- 10c tries up to 18 spots per edge (along the edge at 0.5, 0.25, 0.75; right and left; free entrance node 30, 45,
  60 m off the street centre) over the 3 eligible edges nearest the camera. Each spot is **pre-checked without
  building** with `api.engine.util.proposal.makeProposalData`: the depot proposal and a stand-in stub street from
  the split point to the entrance. Only clean spots are sent (at most 6 build commands); if the pre-check is
  unavailable, every spot is sent until one succeeds. The new depot is found by **diffing `VEHICLE_DEPOT`** and
  mapped to its construction with `streetConnectorSystem.getConstructionEntityForDepot`; the log lists what
  `resultEntities` held (`id:con|depot|edge|node|?`). Then the edge is split **at the spot's param** and a stub
  goes to the depot's free node; `connected=true` when the node gained a street edge.
- 10d uses 10c's depot, else the nearest road depot within 1500 m: road = `carrier` ROAD **or** a BUS/TRUCK/CAR
  transport mode; position = the construction's transform, else the depot's bounding volume; depots with in/out
  nodes first. The line now names what it saw per depot (`id:road/how/distance/nodes=`).
- The helpers moved to `content/stress/gui/stress_buslines.tl` (header: all citations), shared with the Traffic
  tab's **Auto bus lines** (TESTING.md section 6C).

What we knew before the first run (desk research, 2026-10-10):

- **A stop is an edge object, and edge objects only go on a new edge of the same proposal**
  (`api/tealdef/api/type.d.tl:2764-2784`, "must be a new edge in edgesToAdd, starting from -1"). The stop
  tool's proposal replaces the street edge: 1 removed segment, 1 added segment whose `comp.objects` holds a
  `STOP_LEFT`/`STOP_RIGHT` entry (base `mission/tasks/build_construction/mission_task_build_construction_util.tl:222-240`).
  A new edge object's temporary id in `comp.objects` is `-400000000 + index` (base
  `game_mechanics/towns/town_util.tl:1433-1442`). The probe copies the edge (`BASE_EDGE` and
  `BASE_EDGE_STREET`, as subscribed move_it does) and re-points the junction node configs at the copy.
  Variant A sets `comp.objects` itself, variant B (only if A fails) leaves it out.
- Stop resource: `::/stations/street/small_stops/small_{old,mid,new}.con` by year (before 1920, 1920–1980,
  from 1980), one-sided, `edgeObject.snapToStreet`, `minDistToCrossing` 10 m (`small_new.con.lua:55-62`).
- **Depot**: `constructionsToAdd` with `::/depots/road/road_depot/road_depot.con`, `params = {seed = 1}`
  (the updateFn asserts a seed). Its entrance street edge runs from local (0,-35), a free snap node, to
  (0,-20.26) (`road_depot.script.lua:110-112, 149-155`). The GUI tool connects it by snapping to the street; a
  script proposal does not snap, so 10c builds the depot first and then a second proposal splits the street
  edge at its middle and adds a short street (22 m) to the depot's free node.
- **Line**: `makeLineCreateCmd(name, color, player, Line{stops = {Stop{stationGroup, station = 0, terminal = 0}, ...}})`,
  the line entity in `resultEntities[1][1]` (base `mission/tasks/vehicle_util/mission_vehicle_util.tl:5-30`).
  **Bus**: the newest model on sale this year that the vehicle shop would list for a road depot (carrier `ROAD`,
  transport mode `BUS`, filter tag `default`, year window), bought with `makeVehicleBuyCmd` at the depot, then
  `makeVehicleSetLineCmd(vehicle, line, 0)`.

## Buttons (Probe tab)

| Button | Log name | What it does |
|---|---|---|
| 10a Bus stop on nearest street | `bus_stop_on_street` | Picks the street edge whose middle is nearest the camera (within 300 m; at least 30 m long, no stop or signal on it, not part of a construction), replaces it with a copy that has a stop at param 0.5 on the right side. Counts `STATION_GROUP` before/after and looks for a station within 40 m of the stop. |
| 10b Two bus stops 300-600 m apart | `bus_stop_pair` | Two stops like 10a, on two different edges whose middles are 300–600 m apart (searched within 900 m of the camera, nearest first). Keeps both station groups for 10d. |
| 10c Road depot by nearest street | `road_depot_here` | Walks the depot spots beside the 3 street edges nearest the camera (see "Status"), pre-checks each, builds at the first clean one, finds the new depot by the `VEHICLE_DEPOT` diff and its construction, finds the free entrance node, and sends a second proposal that splits the street edge at the spot and adds the stub (30-60 m). Logs the spot counts by pre-check verdict, each sent try, the new depots, and the street edges at the entrance node. Keeps the depot for 10d. |
| 10d Bus line + 1 bus | `bus_line_from_pair` | Line over 10b's two stops (else the two highest-id station groups within 1500 m of the camera), one bus at 10c's depot (else the nearest road depot within 1500 m, with a per-depot diagnostic), `SetLine`. After 5 s: the line's vehicles, the bus's state and `findBestDepotForLine` (a depot id there means the depot reaches the line; `sameDepot`). |

## Steps

Use a test save: 10a–10c change the street network and cost money.

1. Load a free game (not the map editor) in a year with buses (1900+; the bus pick logs the year).
2. Centre the camera on a **town street area with open space beside the road**: the depot is about
   56 × 40 m and its gate sits 30-60 m off the street centre, on either side. A straight street at the edge of town,
   with fields next to it, is ideal. Zoom in so that you can see the street under the camera.
3. Open the Stress Test window, **Probe** tab. Unpause at speed 1 (commands run in the next simulation step).
4. Click **10a Bus stop on nearest street**. A bus stop should appear on the street nearest the screen
   centre, at the middle of that street segment, on the right-hand side of the segment's direction (either
   side of the road on screen). Wait for the `bus_stop_on_street` line (~2 s).
5. Click **10b Two bus stops 300-600 m apart**. Two more stops appear, a few blocks apart (one may be off
   screen). Wait for `bus_stop_pair` (~4 s).
6. Click **10c Road depot by nearest street**. A road depot should appear beside one of the streets near the screen
   centre (either side, 30-60 m off), and a short street from the street to its gate. Wait for `road_depot_here`
   (~2-10 s, depending on how many spots collide).
   Click the depot: does its window open, and does the street at the gate look connected (no gap, no
   dead-end marker)?
7. Click **10d Bus line + 1 bus**. A line "SQST Bus N" appears in the line manager with two stops, and a bus
   leaves the depot. Wait for `bus_line_from_pair` (~6 s), then watch the bus for a minute: does it reach
   both stops?

If 10a fails, still run 10c (the depot does not need the stops). If 10b or 10c fails, 10d falls back to stops
and a depot near the camera: build them with the game's tools and click 10d again.

## Log

```sh
LOG=~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt
grep -h "\[SQST-PROBE\] \(bus_\|road_depot\)" $LOG               # the four result lines
grep -h "\[SQST\] \(cmd\|callback\) \(bus_\|road_depot\)" $LOG   # failed commands and callback errors
```

## What to send back

- The four `[SQST-PROBE]` lines and any `[SQST] cmd ... failed` lines.
- What appeared on screen: stops (where, which side), the depot (facing the street?), the connecting street,
  and whether the bus drove the line.

## How to read the result

- `variant=A(objects) success=true` with `new={id}`: a stop can be placed exactly as the GUI does it. A
  `variant=B` line means the engine wants `comp.objects` left to it; the `A:` part gives the error. `critical=` /
  `messages=` name the reason (too close to a crossing, wrong resource, collision).
- `STATION_GROUP a->b` growing by 1 per stop with `group=` set: the station group is found by diffing the list;
  `nearStop(40m)` shows whether the octree lookup finds it too (for a future generator that places many stops).
- `road_depot_here`: `spots=N tried=K pre={Collision=a,ok=b,unavailable=c,stub:...=d} sent=S [try; try]`:
  `pre=` counts the pre-check verdicts (`unavailable` = makeProposalData didn't answer, so the engine decided);
  each sent try shows `e<edge> t=<param> R|L<gap> origin=... success=`. `VEHICLE_DEPOT +n new=[id(con=.. dist
  nodes=..)] result=n{id:tag,...}` shows the diff and what `resultEntities` held. `freeNode=` and its distance from
  the target say whether the transform put the entrance where expected (~0 m); `connect: success=true ...
  connected=true` means the split and stub worked. `already connected` would mean the engine snapped the depot by
  itself. If a pre-check said `ok` but the build was refused, the pre-check misses something (please paste it).
- `bus_line_from_pair`: `line=` set means `makeLineCreateCmd` works from the GUI state; `vehicle=` and
  `setLine=true` that buying works at a fresh depot; `findBestDepotForLine=<depot id>` (not -1) that the depot
  reaches the line by road. `vehicleState` is the `TransportVehicleState` value after 5 s.
