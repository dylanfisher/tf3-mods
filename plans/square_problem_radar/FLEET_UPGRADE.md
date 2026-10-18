# Problem Radar: Fleet upgrade window (rev 6)

Status: done 2026-10-10 (shipped in revision 6). Open in-game checks: TESTING.md §13.

**Request (2026-10-10):** a button on old-vehicle rows that asks whether to upgrade the fleet, lets the player
choose the vehicle to upgrade to, and shows the line's fleet stats (current load, usage, capacity, earnings, ...).

## Design

- **Row button.** `fleet_old` and `fleet_worn` rows get a sibling button after the row button (like the
  `→` "other train" button): `⇧`, tooltip "Upgrade fleet: line stats and vehicle replacement". Check that the
  HUD font has the glyph (memory: the HUD font lacks ▲). If it's missing, use a short translated text instead.
  Click opens the **Fleet window** for that vehicle.
- **Fleet window** (a separate singleton window, re-targeted when opened for another vehicle; title
  "Fleet: <line name>", or the vehicle name when it has no line). It polls every 2 s with `useStepStateTimer`.
  Engine reads go in the poll, and formatting/`_()` happen in render.
  1. **Line stats**:
     - vehicles: count, and how many are past their lifespan or worn
     - capacity, current load (`getLineCapacityUsages(line, false)` used/capacity), usage % (same formula as
       the base statistics coverage)
     - interval (`1 / getMaxFrequency`, `api.util.formatMinutesSeconds`)
     - transported in the last year (`logbook.getLogValuePerYear(line, "itemsTransported")`)
     - the last 12 months: income, running costs, maintenance, balance. The source is
       `finance.calculateBalance({line}, now - year, now, true[, maintType])`, the same split as `radar.script.tl`
       measureMoney. Income = balance - running - maintenance (costs are negative).
     - average age
  2. **Fleet by model**: vehicles grouped by composition key (sorted model ids with counts, the rule the base
     store uses for multi-replace: `vehicle_store_window.tl:2836-2863`). Each row shows the model name(s)
     (`api.res.modelRep.get(id).metadata.description.name`, or the base `vehicle_store_util`
     `getVehicleNameAndIcons`), the count, the oldest age / lifespan, the number past their lifespan, and an
     **"Upgrade N…"** button.
  3. **Actions**: "Upgrade this vehicle…", "Upgrade old vehicles (N)…" (only when every old one shares one
     composition; otherwise those go per group), and "Upgrade whole fleet (N)…" (only when the whole fleet is one
     composition, or the carrier is not RAIL/TRAM, where mixed single-unit models replace fine), plus
     "Show line" (selectEntity on the line).
- **Choosing the vehicle = the game's own Replace window.** Fire `react.fireEvent(nil, "replaceVehicles",
  VehicleStoreEventParam{vehicleEntities, carrier, transportModes, filterTags, title})`, the exact call of
  the vehicle window's Replace button (`entity_window/vehicle/vehicle.tl:~445-462`). Build `carrier` and `transportModes`
  with `line_util.getLineAndVehicleCompatibleTransportModesAndCarrier`, and `filterTags` with
  `vehicle_store_util.getVehicleFilterTags`.
  - The game's window is the picker and the confirmation. It filters available models by year, carrier, mode and
    cargo, handles trains and multiple units, shows "Replace N Vehicles for $X" and checks money.
  - We send no command ourselves, so the save stays safe (`mods-must-not-impact-saves`).
  - Fallback if the event has no handler in the mod's GUI state: `openVehicleManager {openWithLineEntity}`.
- **Unverified in game:** that `replaceVehicles` fired from a mod opens the store. Add it to `TESTING.md`, and
  record the result in `docs/findings.md`.

## Files

- `content/radar/gui/radar_fleet_model.tl`: pure. It takes raw engine numbers and returns a view (groups, totals,
  usage %, income split, which actions are offered). Unit-tested in `tests/square_problem_radar/test_fleet_model.lua`.
- `content/radar/gui/radar_fleet.tl`: engine reads (poll) + the window recipe + `open(vehicle)`. Use local
  helpers, and keep the main chunk under 200 locals.
- `radar_hud.script.tl`: the row button calls `radar_fleet.open(row.entity)`. The entity guard is the same as in
  focusRow.
- `radar_hud.css.lua`: window id centring, column widths.
- `strings.json`: every new string in all 13 languages.
- Revision 6, a Changelog entry, and a description.html feature line.
