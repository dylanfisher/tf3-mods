# Passenger Destinations: in-game test (rev 1)

Log: `<userdata>/crash_dump/stdout.txt`. Follow it with `tail -f .../stdout.txt | grep -F "[PaxDest]"`.
Last Lua error: `crash_dump/error.json`.

## Setup

1. `make link` (done; adding a staging mod with the game open is fine, removing one isn't: quit to the menu first).
2. Main menu → load a save with a few bus or train lines that carry passengers. Enable **Passenger Destinations** in
   the mod list (Add to save).
3. On load stdout should show `square_passenger_destinations loaded` and no `Lua` errors naming the mod.

## A. Station window

Already confirmed by the user on 2026-10-09 with the next-stop version: the window stays open and the arrows draw.
Re-check that quickly, then focus on the final-destination data.

1. Click a busy passenger station. A compact card with no title sits above the waiting hall and Terminals: one row
   `Destinations: [] All [] 1 [] 2 … [] Next stop` (the terminal numbers are passenger terminals with line stops;
   hover shows "Terminal N"). More than 6 terminals wrap onto further rows of 10. Nothing else shows until a box
   is ticked. A station with no passenger lines shows no card.
2. Tick **1**. Log: `passenger cargo type id = N` (first time; expected 0), `push: …`, `push handler: …`,
   `push: window temp.view.entity_<group> was hidden by the shelve -> reshown=true` (or `visible=true` if pinned),
   `position of group …`, `refresh owner=… dests=<areas> drawn=<arrows> pax=<waiting>`.
3. **Final destination (default)** on the map and card:
   - arrows fan out from the station into the residential / commercial / industrial areas, one per 150 m cell,
     at most 30, and not to other bus stops;
   - card: "N waiting passengers, going to:", a "Home N · Shop N · Work N" line (and "Other N" if any), then
     "-> <Town>: n" rows (biggest first, up to 12), "X of Y areas drawn" when capped;
   - spot check: open a waiting passenger from that terminal (person window → Current Route shows Home/Shop/Work);
     its building should sit under one of the arrow tips;
   - judge the clustering: too many tiny arrows → raise `CLUSTER_M`; arrows landing between districts → lower it.
4. Tick **Next stop**: within ~1 s the arrows switch to the next stops (one per stop) and
   the rows to "-> <Stop>: n". The `refresh` line changes, and there is no new `push` line. Untick it to go back.
5. Tick more terminals, then **All**: arrows and counts update within ~1 s.
6. Untick everything: `pop (untoggled)` + `pop handler`, arrows gone, the summary under the row disappears, the station's own catchment and line view come back.
7. Tick again, then **close the window** with X: `pop (unmount)`. No arrows left.
8. Tick again, then **click another station or a vehicle**: the arrows go; reopen the first station: boxes off.
9. Open Layers or Statistics with arrows on: note what happens (expected: our arrows hide while it's on top,
   `shelve handler … shelved=true`, and return when it closes).
10. Busiest station you have, All on: note FPS and whether the card lags. The log's `pax=` is the number of
    passengers scanned every second.

## B. Person window

1. Click a waiting passenger at a stop (or one riding, via the vehicle's passenger list). The card sits right under
   **Current Route**: "Show destination" and the next-stop checkbox.
2. Tick **Show destination**: `push …`, `refresh … dests=1 drawn=1 pax=1`.
   - Waiting: note "Waiting for <line>, off at <stop> -> Home|Shop|Work, <town>". The arrow runs from the person (or
     the stop) to the target building, not to the stop. "Home/Shop/Work" must match Current Route's destination.
   - Riding: "Riding <line>, off at <stop> -> …". The arrow start follows the vehicle in 1 s steps.
   - Walking or driving: "-> Work, <town>", arrow to the building.
   - At a building: "At Home, <town>: no trip right now.", no arrow.
3. Tick **Next stop instead of final destination** while waiting or riding: the arrow moves to the next stop, and the
   note stays the same.
4. When the person boards / gets off / arrives, the note and arrow change within ~1 s.
5. Untick → `pop (untoggled)`; close → `pop (unmount)`; follow the person until they disappear → `pop (unmount)`.

## What to report back

- The `push: window …` line (hidden → reshown, or visible). If the window disappears anyway, or flickers.
- Whether arrows show at all with the window open (if not: the vanilla window's action stays active; fallback plan
  in PLAN.md).
- Any `[PaxDest] read failed`, `push failed`, `pop failed`, `position … from NOTHING`.
- Any orphaned arrows: arrows still on the map with no Passenger destinations box ticked.
- How the compact row looks (spacing, wrapping at 7+ terminals).
- A busy station's FPS with All on, and the `pax=` / `dests=` numbers there.
- Whether 150 m clusters look right (number and placement of arrows), and whether the town split and
  Home/Shop/Work counts look plausible ("Other" share in particular).

## Save safety (add / remove)

1. **Add to an existing save**: done in Setup. The save loads with no warning; nothing happens until a box is ticked.
2. With arrows on, **save the game**, quit to the main menu, reload: everything is off; the save loads.
3. **Remove from the save**: main menu → mod list → disable Passenger Destinations → load the same save. Expect only the
   generic "mod removed" warning (`severityRemove: Warning`), then a normal game: no errors, nothing missing (the mod
   stores nothing).
4. Achievements stay allowed (`cosmetic: true`).
5. Don't `make unlink` or delete the folder while a save is loaded (findings: "cannot remove mods in game").

## C. Vehicle window (rev 5)

1. Click a bus / train / ship carrying passengers. Under Basics: one row `Destinations: [] Show arrows [] Next stop`.
   A freight-only vehicle shows no row.
2. Tick **Show arrows**: `push: …`, the window stays open, arrows fan out from the vehicle to the areas its
   passengers are going to. The card: "N passengers on board, going to:" (N matches Basics' passenger count),
   "Home N · Shop N · Work N", "-> <Town>: n" rows.
3. Let it drive: the arrows' start follows the vehicle (1 s steps). At a stop the counts change within ~1 s.
4. Tick **Next stop**: arrows to the stops where they get off, "getting off at:", "-> <Stop>: n".
5. Untick / close the window / click elsewhere: `pop (…)`, arrows gone (as A.6-8).
6. With "Debug: performance log" On: the 30 s SQPERF summary lists `vehicle_render`, `compute_vehicle` and
   `read_on_board` (the all-vehicles map read; note its max ms in a big save).

## D. Locate hover (rev 5)

Follow `grep -F "[PaxDest] hover"`.

1. After load: `hover: LocateButton replaced` (if it only appears after opening a station/vehicle/person window, the
   module loads lazily: note that).
2. Open a vehicle with passengers, expand the passenger list, hover a person's pin: an arrow from the person (or the
   vehicle) to their home/shop/work. Log `hover push #N: person=… gameCtx=true visible windows=temp.view.entity_<vehicle>`.
   Does the window stay visible, flicker, or vanish? Mouse out: `hover pop (mouse out)`, arrow gone.
3. Move the mouse down the list slowly: one push per row, `#N` grows by one per row (not in bursts). A warning
   `hover throttled` every second while the mouse is still = loop: report it.
4. Same in a station's waiting list and a town building's residents list (`visible windows=` empty there = that
   window got hidden: report which window id it has).
5. Station arrows on (card ticked), then hover a pin: hover arrow replaces them, mouse out brings them back, the card
   stays ticked.
6. Close the window while hovering (Esc): `hover pop (unmount)`, no arrow left.

## E. One card, two jumps (rev 5)

1. Station, vehicle and person windows show the same row `Destinations: [] Show arrows`; a station with 2+ passenger
   terminals adds `Terminals: [] 1 [] 2 …`, all ticked. No Next stop box anywhere.
2. Show arrows: strong arrows to the stops where they get off, faded arrows from each of those stops to the areas.
   Is the difference visible enough? (Faded = `Consumers3D.Potential` at `transparency.Low`; if too faint or too
   alike, note it.)
3. Station: untick a terminal: its passengers leave the counts and arrows within ~1 s.
4. Person window, riding or waiting: strong arrow to the alighting stop, faded on to the building. Walking: one
   strong arrow.
5. Person window: hover the pins under Locations (home / work town names): arrow from the person to that building.

## F. Shift hover on the map (rev 5)

Log: `shift hover: makeDefaultSelector wrapped` at load; `hover push #N: entity=… token=-2` per Shift hover.

1. No window open. Hold Shift, move the mouse onto a bus / train / ship: its arrows (strong to stops, faded to areas).
   Onto a station: the station's arrows + catchment. Onto a walking person: their arrows.
2. Keep Shift, move to another vehicle: arrows switch after ~¼ s (no flicker?). Move onto empty ground: gone after ~¼ s.
3. Release Shift: arrows gone.
4. Shift-hover with a station window open: works, the window stays visible.
5. Open the line manager, construction menu, a layer (traffic etc.) or statistics: Shift-hover does nothing there, and
   Shift keeps its normal meaning (precision mode in builders).
6. Shift-hover a vehicle, then click it: its window opens normally, arrows go (Shift hover resets).
7. Does onHover fire again while the mouse moves over the same entity? (If yes, pressing Shift while already over
   something will also work after a small mouse move.)
8. Right after loading a save (no window opened yet): Shift-hover a vehicle works. Log at start: `hover: LocateButton
   replaced`, `shift hover: makeDefaultSelector wrapped`.
9. Rest the mouse on a vehicle, then press Shift: arrows appear without moving the mouse.
10. If arrows stop drawing again: note what you did just before, and look for `[PaxDest] diag:` lines.
11. (2026-10-11 user: ready after two games) With Line Manager Plus on (Shift-click a line moved there
    2026-10-11): Shift-hover a vehicle or station next to one of your lines so its arrows show, then, still holding
    Shift, move onto the line and click within ~¼ s (before the arrows leave on their own): the line manager opens
    and the arrows go (log `hover pop (another tool on top: Manager)`). Close the manager: no arrows come back.
    Without Line Manager Plus a Shift-click on a line just opens the line window.
