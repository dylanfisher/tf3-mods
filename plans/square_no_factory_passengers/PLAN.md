# square_no_factory_passengers: plan

## Goal
In the line editor, don't turn passenger loading on for lines that can carry cargo. Passengers stay
on only on passenger-only lines (two bus stops, a passenger train line). The base GUI turns it on at every passenger-capable stop
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
- Wrapper: call the original, then, unless `line.customFilters`: when any stop of the line is a
  cargo stop, clear `passThroughStopData.stopConfig.load[paxId + 1]` at every stop. `load` is read,
  changed and assigned back (the read is a copy; as keepCargo, `line_util.tl:501-512`). Works for a
  1-stop line.
- Cargo-line rule (rev 5, `logic.findCargoStop`, user request 2026-10-17): a stop is a cargo stop
  when its own station (`stop.station1` into STATION_GROUP.stations; the whole group when no
  station is assigned) is a cargo station (`api.engine.util.station.isStationOfType(st, true)`)
  with an INDUSTRY or WAREHOUSE entity among `getStationCatchables(st, true)` (stock list owners,
  `cargo_util.tl:565-582`). Town buildings are cargo catchables too (goods) but don't count.
  Homes in reach no longer matter. Replaces the rev 1-4 rule (clear at stops reaching an industry
  and no TOWN_BUILDING; on such a line, also at stops reaching no homes).
- The own station, not the group: a bus stop grouped with a truck station at a factory stays a
  passenger stop on a bus line.
- Performance (runs on the GUI thread per edit): passenger catchables are never fetched; cargo
  catchables only for cargo stations, once per distinct stop station; the scan stops at the first
  cargo source of the first cargo stop. No `forEachEntityWithComponent` fallback scans. Worst case:
  a line of town cargo stations with no industry (each town building tested, 2 component reads).
  See PERF_REVIEW.md (written for rev 3).
- Pure decision in `nfp_logic.lua` (unit-tested); one `log.message` line per cleared stop (Debug log On).

## Save safety
No game script, no saved state, no base-file overrides (an in-memory wrap only). Lines change only
through the editor's own commit. `severityAdd: None`, `severityRemove: None`
(`docs/wiki/modding/general/moddefinition.md:59-65`: removing cannot harm the save), `cosmetic: false`
(affects the simulation, `:69`).
