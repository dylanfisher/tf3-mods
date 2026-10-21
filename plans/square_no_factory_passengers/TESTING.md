# square_no_factory_passengers: in-game tests

Setup: `make link`, enable the mod, load a save. Watch stdout.txt
(`~/Library/Application Support/Steam/userdata/<id>/3493540/local/crash_dump/stdout.txt`).

## 0. Patch installed
- After the save loads, expect once:
  `[NoFactoryPassengers] installed (line_util.autoLoadConfig wrapped)`
- If it is missing, the replacement config did not run: check for errors mentioning
  `nfp_patch`.

## 1. First stop at a factory: passengers off right away
1. Turn the mod's "Debug: performance log" On (per-stop lines). Open the line manager, start a new
   line, click a factory station with a passenger terminal.
   - Expected log: `[NoFactoryPassengers] stop 1 group <id>: cargo line (stop 1 reaches an industry or warehouse) -> passengers OFF`
   - The stop's load config shows no passengers.

## 2. Factory → town line (rev 5)
1. New line: factory station, then a town station.
   - Expected: `passengers OFF` for both stops; cargo flags as the game set them.
2. Add or move a stop: the OFF lines repeat.

## 3. Town station that also reaches a factory (rev 5)
1. A cargo-capable town station whose catchment covers houses and a factory, to a town station.
   - Expected: both stops OFF.

## 3b. Warehouse and dock lines
1. Warehouse station → dock: both OFF. Dock → town station with no industry/warehouse in reach:
   no `[NoFactoryPassengers] stop` lines.

## 3c. Passenger lines untouched
1. Bus line between two bus stops, one of them next to a factory: no `stop` lines, passengers on.
2. Bus stop that shares a station group with a truck station at a factory: a bus line from it keeps
   passengers (own station decides); a truck line from the truck station is OFF.

## 4. Manual re-enable persists
1. On a fixed line, open the cargo filter window for the factory stop, turn passengers on, confirm
   (this sets custom filters on the line).
2. Add or move a stop, save, reload.
   - Expected: passengers stay on; no `[NoFactoryPassengers] stop` lines for that line's edits.

## 5. Existing lines in an old save
1. Add the mod to a save with a factory line that loads passengers. Load, run a while.
   - Expected: the line is unchanged (nothing is written without an editor edit).
2. Edit that line's route: the game recomputes its automatic settings and the mod applies (OFF
   at the factory stop). Expected, documented in the mod description.

## 6. Removing the mod
1. Disable the mod, load the save: no warning dialog (severityRemove None), lines unchanged.
   New edits get the base passenger default again.

## Things only checkable in game
- `getStationCatchables(st, true)` returns the INDUSTRY / WAREHOUSE entities themselves (no fallback
  for separate stock list entities, by choice: a full entity scan per edit is a hitch). If a
  factory stop keeps passengers (no OFF line), this assumption is wrong.
- `stop.station1` is the stop's own station after the base autoLoadConfig (3c.2).
- No visible hitch when adding stops to a long line on a large map.
- `react-replacement-config` runs before the line editor first opens (test 0 before test 1).
