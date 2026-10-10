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
