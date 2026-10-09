# square_no_factory_passengers: plan

## Goal
In the line editor, don't turn passenger loading on at stops whose station only serves an
industry. The base GUI turns it on at every passenger-capable stop
(`.cache/game/base/content/gui/line_vehicle_mgmt/line_util.tl:454` `addPassengerByDefault`, called
from `autoLoadConfig` at `:495`).

## History
v0 was an engine game script that post-fixed lines. It failed in game: a factory→factory line
kept passengers, and it could never act on the first stop, because the editor keeps its own
`lineState` and reruns `autoLoadConfig` on every edit (`manager_window.tl:6712`, `6786`, `6845`,
`6879`, `6963`). It was replaced by the GUI patch below; the game script and its saved state are gone.

## Design: wrap `line_util.autoLoadConfig` in the GUI VM
- `content/no_factory_passengers/gui/nfp_patch.res.lua`: a `react-replacement-config` resource.
  The GUI bootstrap calls every such `doReplaceFn` once per game load, before the GUI is built
  (`gui/main/bootstrap_game.tl:12-53`), so the patch is in place before the line editor opens.
  Same hook zhenya_auto_assign_terminals uses to wrap `line_util.makeNewStop`
  (`gui/aat_stop_config.res.lua`, `gui/aat_eow.script.lua:685-698`).
- `gui/nfp_patch.script.lua` `doReplace`: `ug_require "::/gui/line_vehicle_mgmt/line_util.tl"`
  and replace the `autoLoadConfig` field with a wrapper (marker field `_square_nfp_wrapped` keeps
  it idempotent). Every caller looks the field up at call time (`line_util.autoLoadConfig(...)`).
- Same table as manager_window: `ug_require` caches by resolved path (`base/init.lua:62-91`).
  manager_window's `"/gui/line_vehicle_mgmt/line_util.tl"` (`manager_window.tl:13`) is "absolute in
  the current mod" = base (`docs/wiki/modding/general/resourcetypes.md:84-88`), i.e. `"::/gui/..."`.
  From the mod, `"/gui/..."` would resolve into the mod, so `"::/"` is required.
- Wrapper: call the original, then, unless `line.customFilters`, for each `via.stop` whose
  `passThroughStopData.stopConfig.load[paxId + 1]` is on: clear it when the station group reaches
  an industry and no town buildings. `load` is read, changed and assigned back (the
  read is a copy; as keepCargo, `line_util.tl:501-512`). Works for a 1-stop line.
- Line rule (rev 2, `logic.decideLine`): once the line has an industry-only stop, every other
  passenger stop whose group reaches no town buildings is cleared too (factory → dock: the dock
  reaches no homes, only transfers). The line pass reuses each group's home result (no
  extra fetch); lines without an industry-only stop are unchanged from rev 1.
- Industry test per catchable from `getStationCatchables(station, true)`: the entity has an
  INDUSTRY component (industries hold their own STOCK_LIST, `industry_util.tl:634-635`, `719-720`).
- Homes test: a catchable from `getStationCatchables(station, false)` has a TOWN_BUILDING
  component (town buildings hold their own PERSON_CAPACITY, `town.tl:441-444`; the base tells
  industry workplaces apart the same way, `industry_workers.script.tl:38-39`). Not the base
  "non-empty" check (`line_util.tl:569-572`): the factory's own workplaces are passenger catchables.
- Performance (runs on the GUI thread per edit): no `forEachEntityWithComponent` fallback scans
  for separate stock list / person capacity entities; homes are tested first (rev 3), so a town
  stop stops at its first town building and cargo catchables are fetched only for groups with no
  homes; every lookup short-circuits; one decision per station group. See PERF_REVIEW.md.
- Station loop as autoLoadConfig (`line_util.tl:551-552`, STATION_GROUP.stations).
- Pure decision in `nfp_logic.lua` (unit-tested); one `log.message` line per cleared stop.

## Save safety
No game script, no saved state, no base-file overrides (an in-memory wrap only). Lines change only
through the editor's own commit. `severityAdd: None`, `severityRemove: None`
(`docs/wiki/modding/general/moddefinition.md:59-65`: removing cannot harm the save), `cosmetic: false`
(affects the simulation, `:69`).
