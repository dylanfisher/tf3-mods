# square_no_factory_passengers: in-game tests

Setup: `make link`, enable the mod, load a save. Watch stdout.txt
(`~/Library/Application Support/Steam/userdata/<id>/3493540/local/crash_dump/stdout.txt`).

## 0. Patch installed
- After the save loads, expect once:
  `[NoFactoryPassengers] installed (line_util.autoLoadConfig wrapped)`
- If it is missing, the replacement config did not run: check for errors mentioning
  `nfp_patch`.

## 1. First stop at a factory: passengers off right away
1. Open the line manager, start a new line, click a factory station (one with a passenger
   terminal, no houses in reach).
   - Expected log: `[NoFactoryPassengers] stop 1 group <id>: industry in reach, no town buildings -> passengers OFF`
   - The stop's load config shows no passengers.
2. Add a second factory station (factory→factory line).
   - Expected: both stops OFF in the log, no passengers in the stop configs.

## 2. Factory → town line
1. New line: factory-only station, then a town station.
   - Expected: factory stop `passengers OFF`; no log line for the town stop (kept stops are not
     logged).
     Cargo flags at both stops as the game set them.
2. Add or move a stop: the log repeats the OFF line and the factory stop stays without passengers.

## 3. Town station that also reaches a factory keeps passengers
1. Find or build a town station whose catchment covers houses and a factory, with a passenger
   terminal.
2. New line from it to a factory-only station.
   - Expected: no log line for the town station (kept), `passengers OFF` for the factory-only
     stop.

## 3b. Factory → dock line (rev 2)
1. New line: factory-only station, then a dock (or truck stop at a harbour) with no houses in reach.
   - Expected: `stop 1 ... industry in reach, no town buildings -> passengers OFF` and
     `stop 2 ... no town buildings, line serves an industry-only stop -> passengers OFF`.
2. New line: the same dock to a town station (no factory stop).
   - Expected: no `[NoFactoryPassengers] stop` lines; the dock keeps passengers.

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
- `getStationCatchables` returns the INDUSTRY / TOWN_BUILDING entities themselves (no fallback
  for separate stock list or person capacity entities, by choice: a full entity scan per edit is a
  hitch). If a factory-only stop keeps passengers (no OFF line), this assumption is wrong.
- No visible hitch when adding stops to a long line on a large map.
- `react-replacement-config` runs before the line editor first opens (test 0 before test 1).
