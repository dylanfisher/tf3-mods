# Probe 9: clearing private car traffic

Question: can a mod clear private car traffic (for a "Clear cars" stress button, or to reset a jammed town)?

What we know before the run (desk research, 2026-10-09):

- A private car is not an entity of its own. It is a `SIM_PERSON` whose `lastMoveMode` is `DRIVE`
  (`.cache/game/api/tealdef/api/engine.d.tl:1086-1112`: `modelIdCar`, `colorConfigCar`). While driving it
  should carry a `MOVE_PATH`, without `SIM_PERSON_AT_VEHICLE` (that one means seated in a bus or train).
- No command destroys or despawns a person. Removing entities by other means kills the simulation thread
  (docs/findings.md, `nodeConfigsToRemove` assertion), so the probes never try it.
- The one candidate is `api.cmd.debug.makeSimPersonSetStateCmd(entity, state)` (`cmd.d.tl:994-1003`). Its
  state values are not documented in the tealdef, but the base entity debug panel names them
  (`base/content/gui/debug_panel/make_entity_debug_panel.tl:669-690`):
  0 pick new destinations, 1 new path, **2 jump home**, 3 jump shopping, 4 jump working, 5 go home,
  6 go shopping, 7 go working. Campaign mission 1 sends 2 to every `SIM_PERSON` through
  `forEachEntityWithComponent` (`mods/release/urbangames_campaign_mission_01/content/mission/mission_story.tl:2835-2840`,
  "2 means: jump home"). "Jump home" should take a driver off the road at once; that is what 9b tests.
- `PERSON_CAPACITY.pathfindingPreference.disallowedMoveModes` (`engine.d.tl:830-843`) could forbid `DRIVE`
  per building, but no command writes it. 9d only reads it to see its shape.

## Buttons (Probe tab)

| Button | Log name | What it does |
|---|---|---|
| 9a SimPerson census | `simperson_census` | Lists `SIM_PERSON` (getEntitiesWithComponent, else forEachEntityWithComponent), inspects up to 200,000: counts by `lastMoveMode`, with `SIM_PERSON_AT_VEHICLE` / `SIM_ENTITY_AT_VEHICLE` / `MOVE_PATH`, drivers on the road now, `DRIVE` persons with a `LAND_VEHICLE`; also `LAND_VEHICLE` / `TRANSPORT_VEHICLE` list counts, `simPersonSystem.getCount()` and the scan time. Dumps the first driver's `SIM_PERSON` and `MOVE_PATH` to stdout.txt. Read only. |
| 9b Cars near camera: jump home | `simperson_setstate_2` | Picks 5 persons driving now (on street edges within 400 m of the camera, else anywhere), logs them, sends `makeSimPersonSetStateCmd(e, 2)` to each, re-reads after 2 s and 15 s. |
| 9c Cars near camera: new path | `simperson_setstate_1` | The same with state 1. |
| 9d Person capacity dump | `person_capacity_dump` | `PERSON_CAPACITY` of up to 3 town buildings nearest the camera: type, capacity, node counts, persons with it as a destination, the whole `pathfindingPreference`. Read only. |
| 9e Cars near camera: new destinations | `simperson_setstate_0` | The same as 9b with state 0. |

## Steps

Use a test save (9b/9c/9e change where a few people are going; nothing is deleted).

1. Load a free game with a **grown town and visible car traffic** (a town of a few thousand; the Towns tab's
   grow x10 on a fresh town works, then let it run a few in-game months at speed 4 until cars are on the streets).
2. Centre the camera on a **busy town road** and zoom in so that you can see individual cars (the 9b/9c/9e
   search uses the street edges within 400 m of the camera centre).
3. Open the Stress Test window, **Probe** tab.
4. Click **9a SimPerson census**. The game may freeze for a moment on a big map (the scan time is in the line).
   Wait for the `simperson_census` line.
5. Click **9d Person capacity dump**. Wait for its line (immediate).
6. Pause is fine for 9a/9d, but **unpause at speed 1** for the rest: the commands run in the next simulation step.
7. Click **9b Cars near camera: jump home**, then watch the road under the camera for 15 s:
   - Do some cars **vanish** (or pop to a house) right away? How many of the visible cars?
   - Does a car stop in place, turn around, or keep driving?
   Wait for the `simperson_setstate_2` probe line (15 s).
8. Click **9c Cars near camera: new path**, watch the same way, wait 15 s for `simperson_setstate_1`.
9. Click **9e Cars near camera: new destinations**, watch, wait 15 s for `simperson_setstate_0`.
10. Optional: if 9b made cars vanish, click it 3 to 4 more times on another busy road to see whether the
    effect is reliable, and whether those people come back on the road later (they go out again from home).

## Log

```sh
LOG=~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt
grep -h "\[SQST-PROBE\] \(simperson\|person_capacity\)" $LOG          # the five result lines
grep -h "\[SQST\] \(simperson\|person_capacity\)" $LOG                # per-person before / +2s / +15s detail, field dumps
```

## What to send back

- The five `[SQST-PROBE]` lines and the `[SQST] simperson_*` detail lines.
- For 9b, 9c, 9e: what the cars did on screen (vanished, teleported, stopped, kept driving).

## How to read the result

- `simperson_census`: `iter=` says whether `SIM_PERSON` can be listed (a clear-all button needs that), `scanMs`
  what a full pass costs, `drivingNow` how many cars are on the roads. `DRIVE+LAND_VEHICLE` > 0 would mean the
  car is a component on the person.
- `simperson_setstate_N`: `callbacks/succeeded` say whether the debug command is accepted from a mod's GUI state.
  At +2 s / +15 s, `drivingNow` going to 0 with `atBuilding` up means the state worked; `gone` > 0 would mean
  the person was deleted (unexpected).
- If 9b clears cars, a "Clear cars" button can send state 2 to every driver found by the census (in queue
  batches, `rt.PER_FRAME` per frame), the way campaign mission 1 does for all persons.
- `person_capacity_dump`: the `disallowed=` list and the `pref:` dump show whether a building already forbids
  modes (nothing writes it, so this is for completeness only).
