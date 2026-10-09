# Town Street Names (`square_town_street_names`): offline research

Goal: towns with a known name (e.g. "Seattle") get their own street-name list for new street stops ("Pike Street",
"Pine Street", ...). Every other town keeps the normal name-set pool.

Researched 2026-10-08 against the installed build (`.cache/game`, `docs/wiki`, the game binary's strings). Paths
below are relative to the repo root. `.cache/game/api/tealdef/...` is shortened to `api/...`. "Binary" means
`strings -n 6` on the installed `Transport Fever 3/TransportFever3` executable (the naming logic is C++, not Lua).

## Summary

| Question | Answer | Status |
|---|---|---|
| Can a name set give per-town street names? | No. `streetNamesScript` gets only `lang` and `num`. | Confirmed |
| Where do street names show up? | Almost certainly as the default name of edge-object street stops ("Road Stop" / two-sided). Street edges have no name field in the API. | Strong inference, probe confirms |
| Which entity holds a stop's name? | The **station group**. The entity window renames the station group, and `makeEntitySetNameCmd` on a station "sets the stem name instead". | Confirmed for the window path; the stop's NAME layout is probed |
| Town of a stop | `api.engine.system.stationSystem.getTown(station)`, with `api.engine.util.town.getClosestTown(pos)` as a fallback. | API confirmed; values probed |
| Detecting new stops | No "stop built" event. Use `onPostBuildProposal` as a trigger plus a diff of `STATION_GROUP` entities in `update`. Post-event ids are placeholders. | Pattern confirmed in our mods; stop specifics probed |
| Renaming | `api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(group, name))`, sent from `update` and never inside a build event. | Confirmed (base + 2 community mods) |
| Player renames | Towns and stops can be renamed from their window title. There is no "custom name" flag. | Confirmed (UI code). Whether a NAME component's presence means "custom" is probed |
| When `streetNamesScript` runs | Unknown. The base script supports `num == -1` (whole list, shuffled) and `num > 0` (random picks). | Unknown, probed with a logging name set |

## 1. Name sets can't do it

- `docs/wiki/modding/misc/names.md` "Streets": `streetNamesScript` receives `captureParams` and `params = {lang, num}`.
  It returns `num` names, or all of them for `num == -1`. Nothing about the town.
- `api/api/type.d.tl:4120-4125` `NameDesc { name, personNamesScript, townNamesScript, streetNamesScript }`.
- Base implementation `.cache/game/base/content/names/names.script.lua:62-84`: `streetsNameScriptFn` requires
  `<modId>::/names/<path>/<lang>/streets.lua`. For `num < 0` it returns a **shuffled copy of the whole list**, and
  for `num > 0` it returns `num` random picks (with repeats).
- Binary: `NameRep.cpp`, `loadNameList`, `.names.lua`, `GenerateTownNames`, "Town name generation function did not
  return the expected number of names: " and **"Error generating street names"**. Name sets are loaded by `NameRep`.
  The street-name error string sits among the station naming strings (section 2), so street names are generated
  when stops are named.
- `.cache/subscribed/arizonaranger_washington_names`: a plain name set. It reuses the base
  `::/names/names.script@streetsNameScriptFn` with `path = "washington"` and `modId`, and has 84 generic streets
  ("1st Street", "Adams Street", ...). It uses `severityRemove: "Critical"`, which suggests a save remembers its name set.

## 2. Where street names surface, and how names are composed

The naming code is C++ (`Game/ecs/NameSystem.cpp`), and no format strings for it are in `base.mo`. These are the
format strings next to it in the binary:

```
{townName} {constructionName}        (construction naming, near MakeStreetProposal / CreateProposalAddConstruction)
{townName} Station
{stationName} East | North | West | South | Annex | Branch | Central | Exchange | Halt | Sidings | Transfer
Lower {stationName} | Upper {stationName}
{stationName} #{number}
Stop #{number}
{townName} Waypoint #{number} / {townName} Signal #{number} / Waypoint #{number} / Signal #{number}
Error generating street names
```

The NameSystem strings include `name2entity` and `FirstNonExistingWithNumber`, so the engine keeps names unique by
adding suffixes.

Our reading (to be confirmed by the probe):
- **Construction stations** (bus/tram station `modular_terminal.con`, train stations, ...) are named
  "{townName} Station" or "{townName} {constructionName}". The direction/annex suffixes and "#n" break ties.
  Street names are not involved.
- **Edge-object street stops** (`base/content/stations/street/small_stops/small_*.con.lua`, which have an
  `edgeObject = { snapToStreet = true, ... }` block) are named from the **street-name pool**. "Stop #{number}" is the
  fallback. They are the only place street names show up. This is what TF2 did too.
- Street edges: `Engine.Component.BaseEdge` (`api/api/engine.d.tl:99-131`) and `BaseEdgeStreet` (:147-154) have
  no name field. Whether edges carry a NAME component, or the engine keeps a name per street internally, is unknown.
  The probe's `dump street edges` and the `edge=` part of each `NEW` stop line answer it.

Which entity holds the name:
- `Engine.Component.Name { name }` is `api/api/engine.d.tl:795-800`, and `ComponentType.NAME` is :1635.
- `api.engine.util.getEntityName(e)` "computing it from the base construction if needed", and
  `getEntityNameStem(e) -> {name, stemEntity}` (`api/api/engine/util.d.tl:1038-1044`). Some entities have no NAME
  of their own and inherit a stem.
- `api.cmd.makeEntitySetNameCmd(entity, name, forceSameEntity?)` (`api/api/cmd.d.tl:673-679`): "Unless true, things
  like stations that don't have a name on their own will set the stem name instead."
- `base/content/mission/name_util.tl:4-130` renames stations in the campaign. For a **station group** it sets the
  group's NAME, then the NAME of each station that has one ("setNameOptional"). For a construction it sets the
  construction's NAME if it has one and each station group's NAME, and **expects construction stations to have no
  NAME** ("expectNoName"). It warns "Consider removing edge object name!" when an edge-object station was named
  separately. So edge-object stops *can* carry their own NAME.
- The entity window (`base/content/gui/entity_window/make_entity_window.tl:311-315, 391-394, 570-588`) maps a clicked
  station to its **station group**. Its title commit (`view_manager.tl:193-223`) sends `makeEntitySetNameCmd` on that
  key entity. A player rename of a stop therefore renames the station group, and the game shows the group's name
  in lines and windows.

## 3. Town of a stop

- `api.engine.system.stationSystem.getTown(stationEntity)` (`api/api/engine/system.d.tl:76-78`), plus
  `getStation2TownMap()` (:61) and `getTown2StationsMap()` (:75). Base uses `getTown(stationGroup.stations[1])` as
  "the town of this station group" (`base/content/game_mechanics/towns/town_util.tl:1846,1859`,
  `gui/statistics/statistic_stations.tl:34`). auto_line_namer uses `getStation2TownMap()` (`aln.script.lua:79`).
- `api.engine.util.town.getClosestTown(Vec3f)` (`api/api/engine/util.d.tl:679-682`). It's used by
  `mods/release/urbangames_campaign_mission_06/.../deliver_visitors.script.tl:68`.
- `town_util.makeGetClosestTownAndDistanceFunction()` (`town_util.tl:986-1002`) gives the nearest town centre by the
  town's BOUNDING_VOLUME centre (`entity_util.getPosition`, `scripts/entity_util.tl:48-55`).
- Town name: `town_util.getTownName(town) = api.engine.util.getEntityName(town)` (`town_util.tl:1548-1550`).
- Other links: `Parcel.streetSegment` (`engine.d.tl:819`) and `TownBuilding.town` (:1320) link a *building* to its
  street edge and town. They aren't needed for stops. Unknown: what `getTown` returns for a stop outside any town,
  and whether it's valid right after the build. The probe logs all three methods for every new stop.

## 4. Detecting newly built stops

- Build events reach a game script as `handleEvent(..., id = "apply_command", name = "onPreBuildProposal" |
  "onPostBuildProposal", param = {Proposal, ProposalData, resultEntities, playerInitiated})`
  (`mods/square_full_refund/content/refund/refund.script.tl:439-450`; `base/.../towns/towns.script.tl:266-273`).
  The subscription must be made lazily in `update` (`subscribeToNoEvents` + `subscribeToEvent`,
  `base/tealdef/scripts/gamescript.d.tl:40-49`).
- A street stop arrives as `proposal.proposal.edgeObjectsToAdd[i]` with `category` (0 = stop, 1 = waypoint,
  2 = signal), `resultEntity`, `modelInstance.transf` and `left` (`api/api/type.d.tl:2497-2507, 2562-2566`). Base
  reads it the same way (`town_util.tl:1430-1442`, `mission/guide_system/guides/guide_timer.tl:103-108`). New edge
  objects use **placeholder ids** `-400000000 + n` (town_util.tl:1437). square_full_refund also saw placeholder
  (<0) ids and an empty p[3] in post events for street builds (refund.script.tl:116-118). So the event tells us
  *that* and *where* a stop was built, but **not its entity**.
- Construction stations arrive in `proposal.toAdd` (`fileName`) and, after post, in `p[3]` with real ids
  (refund.script.tl:292-299).
- Commands inside onPre/PostBuildProposal assert `!m_betweenChanges` (memory note, square_full_refund). Renames
  must be queued and sent from `update`.
- GUI side: `builder.proposalCreate / proposalPrepareForApply / proposalApply` exist as GUI events
  (`base/content/game_mechanics/company/company.script.tl:385-389, 559`). They need `guiHandleEventScript` +
  `guiUpdateScript` + an engine-side subscription (memory note).
- **Polling precedent:** auto_line_namer keeps the known line ids in the saved state and renames lines it hasn't seen
  in a 2 s scan. Its first scan on a save only records the baseline (`.cache/subscribed/auto_line_namer_1/content/
  auto_line_namer/aln.script.lua:59-90`). Its comment says "TF3 recreates this script's Lua state often", so keep
  anything that must last in `state`. gameburrow_destinationdisplays renames vehicles from its game script
  (`destination_displays.script.tl:20-22`).
- Entity enumeration: `api.engine.getEntitiesWithComponent(ComponentType.STATION_GROUP)` (`engine.d.tl:1713`)
  and `api.engine.util.octree.findEntitiesInCircle(Vec2f, r, type)` (`engine/util.d.tl:329`).
- No official mod renames stops automatically. `mission/name_util.tl` renames at mission init only.

## 5. Player renames

- Towns: the entity window's title is editable for any keyed entity (`view_manager.tl:193-223`), including towns
  (`make_entity_window.tl:441`). Towns can therefore be renamed, so the mod should look up the town's **current
  name** each time it names a stop, not a cached one. Renaming a town to "Seattle" would then switch it to Seattle
  streets for future stops, which is arguably a feature.
- Stops: the player can rename a stop's station group the same way. No API flag marks a name as player-given.
  Options: (a) only ever rename a group once, right after it appears, and remember that in state; (b) if the probe
  shows that default-named groups have **no** NAME component while renamed ones do, use that as the flag.
- Since the mod only renames brand-new stops within about 2 s of being built, it never touches existing, possibly
  player-renamed, stops.

## 6. Unknowns (the probe settles these)

1. Does an edge-object stop's default name come from the street pool, as "Probe Street NN" with the probe name set?
   Do two stops on the same street share a stem with East/West/#2 suffixes?
2. Which entity carries the NAME: the station group, the station (edge object), or both? Does the edge carry one?
3. When is `streetNamesScript` called: once per new game, per load, per stop? With what `num`?
4. Is `stationSystem.getTown` valid in the first scan after the build? What does it return outside towns?
5. Is a new stop's group always new, or can it join an existing group (two-sided stop, near another stop)?
6. Which renaming target sticks and is shown in the UI: the group, the station (stem), or the station with
   forceSameEntity? Are duplicate names accepted or suffixed?
7. Does a player rename (stop or town) change NAME presence? Do construction-station names follow a town rename?
8. Do build events and `update` share a Lua state (module-local hand-off vs `state`)?
