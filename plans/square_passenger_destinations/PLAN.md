# Passenger Destinations (`square_passenger_destinations`): plan

Show where passengers are going, drawn with the base game's 3D cargo-flow arrows.

- Revision 1 (2026-10-09): first in-game-testable version. GUI only, `cosmetic: true`,
  `severityAdd: None`, `severityRemove: Warning`. No game script, no commands, nothing saved.
- 2026-10-09, first game test (user): stacking works (the window stays open, arrows draw), but the original
  "next stop" semantics wasn't useful (it's just the next bus stop). Changed to the **final destination**
  (the home / shop / work building, `SIM_PERSON.targetOrAtEntity`) by default. Next stop is still there
  behind a "Next stop instead of final destination" checkbox, because the code already existed and costs
  nothing while unticked. Still rev 1 (not uploaded).

## Features

**A. Station window.** Compact card without a title (plugin of `::StationGroupEowExtensionPoint`; the extension
point mounts plugins above the waiting halls and Terminals, `station_group.tl:863-866`, and `order` can't move it,
so the card is kept small). One horizontal row: `Destinations: [] All [] 1 [] 2 … [] Next stop`, terminals numbered
like the base window (flat over all stations of the group, all terminals counted; tooltip "Terminal N"); more than
`FIRST_ROW_TERMINALS` = 6 wrap onto rows of 10. Nothing else until a box is ticked; then the summary appears below.
- *Final (default)*: each waiting passenger's target building goes into a grid cell of `CLUSTER_M` = 150 m.
  One arrow from the station group to each cell's centroid, biggest cells first, at most 30 ("X of Y areas
  drawn"). Arrows aren't scaled by count: `FlowData` has no width or amount field (`api/type.d.tl:4875-4896`).
  The card shows "N waiting passengers, going to:", a "Home N · Shop N · Work N" line (plus "Other N" when the
  target matches none of the three destinations), and up to 12 towns with counts ("+N more towns").
  Town = `TOWN_BUILDING.town` of the target; anything else (industry workplaces) counts as "Other".
- *Next stop*: one arrow per destination station group, counted per stop (the earlier behaviour).
The station's catchment area is drawn too, so the map still looks like the vanilla station window.

**B. Person window.** Card (plugin of `::SimPersonEowExtensionPoint`, order 41, right under "Current Route"
at 40) with "Show destination" and the mode checkbox. The arrow always starts at the person, or at their stop /
vehicle when the person has no bounding box. *Final*: it ends at the target building. *Next stop*: it ends at the
next-stop station group when waiting or riding. Note: "Riding <line>, off at <stop> -> Work, <town>", "Waiting for
...", "-> Home, <town>" when walking or driving, "At Home, <town>: no trip right now." at a building (no arrow).

Both refresh every 1 s while on, and only while on. Changing the mode needs no re-push (the compute closure
reads the per-plugin box).

## Data sources (all in `.cache/game/`)

| What | Source |
|---|---|
| Plugin params (`entityId`, `gameCtx`, `showCalloutOnRightSide`) | `base/content/gui/entity_window/station_group/station_group.tl:847-865`, `sim_person/sim_person.tl:123-136`; `base/tealdef/gui/entity_window/eow_extension_util.d.tl` |
| Extension point ids | `station_group_eow.script.tl:7`, `sim_person_eow.script.tl:12`; base route plugin order 40 `sim_person_eow_route.res.lua` |
| Stations of a group | `STATION_GROUP.stations` (`api/tealdef/api/engine.d.tl:1121-1126`) |
| Line stops of a terminal | `api.engine.system.lineSystem.getLineStopsForTerminal(station, terminal0)` (`api/engine/system.d.tl:36`) |
| Waiting passengers | `simEntityAtTerminalSystem.getLineStopSimEntities(line, stopIndex, cargo)` (`system.d.tl:198`) |
| Next stop | `SIM_ENTITY_AT_TERMINAL.lineStop1` / `SIM_ENTITY_AT_VEHICLE.lineStop1` (zero based, `engine.d.tl:1002-1031`) → `LINE.stops[lineStop1 + 1].stationGroup` (`engine.d.tl:523-531`) |
| The whole station chain | mirrors base `station_group.tl:620-700` (`makeStopTooltip` → "Destinations:" tooltip) |
| Passenger cargo id | `api.res.cargoTypeRep.getPassengerCargoTypeId()` (`api/res.d.tl:95`, base `cargo_util.tl:24-26`); `SIM_PERSON.cargoType` is documented "always 0". Logged once as `[PaxDest] passenger cargo type id = N` |
| Final destination | `SIM_PERSON.targetOrAtEntity` (`engine.d.tl:1095-1096`); at a building = `SIM_ENTITY_AT_BUILDING` present (as `sim_person.tl:53`) |
| Home / Shop / Work | index of `targetOrAtEntity` in `SIM_PERSON.destinations[1..3]` (base `sim_person.tl:77-86`), labels 0 Home, 1 Shop, 2 Work (`sim_person_eow.script.tl:61-71`) |
| Town of a building | `TOWN_BUILDING.town` (`engine.d.tl:1305-1320`), name via `api.engine.util.getEntityName`; no TOWN_BUILDING → "Other" |
| Building position + town cache | module table per building entity (buildings don't move), dropped at 20 000 entries; town names cached per session |
| Positions | `BOUNDING_VOLUME` bbox top centre (base `industry.tl:195-202`). Station group: own bbox, else mean of its stations (station's construction bbox via `streetConnectorSystem.getConstructionEntityForStation`, else station bbox, else the middle of the terminal's first person edge via `TRANSPORT_NETWORK` + `api.engine.util.transport.calcPosition`). Vehicles: `api.engine.util.vehicle.getPosition` (`engine/util.d.tl:445`). A person driving is its own `LAND_VEHICLE` (`sim_person.tl:39`). Each group logs its position source once (`[PaxDest] position of group N from construction/station/edge/group/NOTHING`). |
| Arrows | `LayerConfig.cargoFlowRenderableConfig.flowData` (`api/type.d.tl:4875-4896`), colours `layer_colors.gres` `CargoFlow.Consumers3D.Actual`, speed 40, passenger cargo icon. Same as `square_industry_flows` `buildLayerConfig` and base `industry.tl:329-361`. |

## Drawing: our tool over the entity window

A `LayerConfig` only works inside the `ActionDescriptor` of the **top** tool of the tool stack
(`base/content/gui/main/builtin.lua:1162-1194`). The plugin gets `gameCtx.toolStack`. On toggle it pushes
`SquarePassengerDestinations` (no window, key `square_passenger_destinations`) with `allowStacking = true`
(`builtin.lua` provideApi push). The tool's push handler calls `ctx.setActionFn(actionFn)`. `actionFn` is the base
`selector_react_util.makeDefaultSelectorAction(gameCtx, layerConfig, true)` (HUD icons, entity selection and
tooltips, `selector_react_util.tl:324-372`) with our LayerConfig. It polls with `engine_react_util.useStepStateTimer`
inside the action (as the station window's own action does, `station_group.tl:911-925`), so it only refreshes while
our tool is top, and changing the terminal selection needs no re-push (the closure reads a per-plugin box table).

**Shelving.** Pushing shelves every tool below (`shelveNonTop`). `EntityDetailsTool.shelve` hides the entity window
unless it is pinned (`entity_window/view_manager.tl:404-415`). Our push handler runs after that (`builtin.lua` push:
`shelveNonTop` then `pushHandler`) and sets `temp.view.entity_<entity>` visible again (`view_manager.tl:62-64`). For a
station it also tries the windows of the stations' constructions, and only touches ids that exist and are hidden.
Popping our tool un-shelves the entity tool, which shows its window and is top again, so its own action
(catchment, line viewer) comes back.

**Never orphaned.** Module `active = {owner, entity, toolStackApi}`; one tool at a time.
- Untoggle → pop (click handler, GUI thread).
- Plugin unmount (window closed) → pop via `react.enqueueJoin`.
- Plugin re-rendered for a different `entityId` → pop via `enqueueJoin`, UI off.
- Tool popped elsewhere (clicking another entity: the default selector without stacking clears the stack and calls our
  pop handler; the vanilla close button pops the window tool and removes the window → unmount) or replaced by another
  plugin's push → a 0.5 s `onStepTimer` sees `active.owner ~= mine` and turns the UI off.
- Every push/pop/shelve/refresh logs `[PaxDest] ...` (refresh only when the numbers change, or every 10 s).

## Risks and how they're handled

| Risk | Handling | Verified? |
|---|---|---|
| Pushing over the entity window hides it (shelve) | Re-show from our push handler; logged as `push: window ... was hidden by the shelve -> reshown=true` | Yes, user 2026-10-09: the window stays open and the arrows draw |
| Window id isn't `temp.view.entity_<group>` (station shown in a construction window) | Also tries the station constructions' window ids; logs every id it checks | No |
| The vanilla entity window keeps its action active and our arrows never show | Ours is top; the entity wrap only takes the renderer owner when `ctx.isTop` (`builtin.lua:1185-1194`) | No |
| Orphaned tool | Pops on untoggle / unmount / entity change; loss detection; pop handler clears `active` | Partly (code paths) |
| GUI calls on worker threads crash (memory) | Timers only read the engine and mutate Lua tables; pushes/pops from timers or unmount go through `react.enqueueJoin` | By design |
| Recipe roots must be layouts; `Component{layout=Recipe}` crashes (memory) | Both plugins return `BoxLayout{ child = ContentCard{...} }` or an empty `BoxLayout`; no ScrollArea, no recipe as a layout | `grep 'layout = [A-Z]'` clean |
| Big stations: hundreds/thousands of waiting passengers | Final mode: two `getComponent` per passenger per second while on (SIM_ENTITY_AT_TERMINAL, SIM_PERSON); the target building's bbox + town are cached. The vanilla station window's tooltip state already does the first scan every step. Arrows capped at 30, town rows at 12. | No measurement yet |
| Clustering looks wrong (too many / too few arrows) | `CLUSTER_M` constant, 150 m; tune after the game test | No |
| Station group without a usable position | Fallback chain + one-time log of the source; a destination without a position is listed but not drawn | No |
| Save impact | GUI only, nothing saved, no game script, `cosmetic` | Add/remove check in TESTING.md |

## Fallback plan (not built)

If stacking a tool over the entity window misbehaves (window hidden and not reshown, flicker, arrows never show,
selection breaks): build a standalone follow panel like Industry Flows (`tool_react_util.registerToolWithWindow`,
pushed **without** stacking from a button in the cards). The cards would then only open the panel with the entity
preselected; the panel owns the tool, its window and the arrows, and closing it pops everything. Cost: the entity window
closes when the panel opens (non-stacking push clears the stack), so the panel has to show the counts itself.

## Later

- Cover + gallery (`branding/mods.js`), skipped for rev 1.
- Arrow origin per terminal instead of the group centre, if that looks wrong at big stations.
