# US State Names: in-game test checklist

Not shipped (lives in `plans/`). Use a **copy** of a save. Report every `[square_names_us_washington]` line and any
Lua error near one:

```
tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered square_names_us
```

## Phase 1: Washington playable (`square_names_us_washington`)

Setup: quit the game, `make link` (the new mod folder needs linking), start the game. In the mod list the mod is
"Washington Towns & Streets"; its settings show **Real street names** and **Real station names** (both On).

1. [ ] **New game, Temperate**, mod on, name set **"Washington (Towns & Streets)"**. Expect one line
   `towns num=<N> climate=<...> via <runFn|configDict|none> -> ... first Seattle`. Paste it: the `via` part is the
   climate route (Probe 3 answer, again). Towns on the map: mostly west-side names (Seattle, Tacoma, Bellevue,
   Everett, Olympia, small Puget Sound towns), a few coast/east ones. If `via none`, it's the whole state (still
   real Washington towns, biggest cities first).
2. [ ] **New game, Desert**: east-side names (Spokane, Yakima, Kennewick, Pasco, Wenatchee, Ellensburg, Moses Lake,
   Palouse towns). Paste the `towns` line.
3. [ ] In Seattle (or Tacoma) build **5 Road Stops** on different streets, one at a time and then several in one
   go. About a second later each gets a real street (Seattle: Pike Street, Pine Street, Union Street, ...), no
   repeats; one `renamed stop group ... -> Pike Street` line each.
4. [ ] A Road Stop in a town **without** a city list (any small town): it keeps the game's name, which comes from
   the Washington generic pool (Cedar Street, Cascade Avenue, NE 8th Street, ...). No `renamed` line.
5. [ ] In Seattle build a **Train Station**, an **Airport** (or airfield), a **Harbour** and a **Bus/Tram Station**:
   King Street / Sea-Tac Airport / Colman Dock / Capitol Hill. Note for each what the **station window** and the
   **line manager** show: "King Street" or "King Street Station"? (Same question as Probe 3 step 4; the answer sets
   `STATION_SUFFIX` in `sn_logic.lua`.) A cargo train station or a helipad keeps its default name.
6. [ ] Load an existing save with **another name set** (e.g. American), add the mod: nothing changes on load, no
   `renamed` line. Rename a town to "Seattle", build a Road Stop there: it becomes Pike Street (or the next unused
   one).
7. [ ] Remove the mod from that save and load it: the given names stay, no errors. (A save **started** with the
   Washington name set auto-activates the mod, "Autoactivating ... (required by nameList)": that's expected.)
8. [ ] Settings: set **Real street names** = Off, build a stop in Seattle: no rename. Set it back On.
9. [ ] Map editor: open the editor with the mod on, place a town and a stop: no `renamed` line and no errors.

Also paste any `ERROR` line from the mod. The probe mod (`square_town_street_names_probe`) can stay linked but
shouldn't be enabled in the same game.

## Phase 2: edge cases (same mod, after `make link`)

Each item is one build and a look at the name (station window title, or hover). Unit tests cover the logic
(`tests/square_names_us_washington/test_rename.lua`, second half); these confirm the engine side.

1. [ ] **No global-variable errors**: start a new game with the set. `crash_dump/stdout.txt` has **no**
   `Global variable in mod` line with `square_names_us_washington` / `SQUARE_NAMES_US_WASHINGTON_RUNFN`, and the
   `towns ...` line says `via runFn` with the map's climate.
2. [ ] **Two-sided Road Stop** in Seattle: one real street on the stop, one `renamed stop group` line. If it keeps
   the default name with no line, paste the `NEW` lines from the probe for a two-sided stop (we may be seeing two
   stations from one edge object, and only one is in the event).
3. [ ] **Stop right next to an existing stop** (same street, close enough to share the station window): the old
   stop keeps its name (also if you renamed it yourself first). No `renamed` line if it joined the old group.
4. [ ] **Road upgrade under a stop**: rename a Seattle stop yourself ("My Stop"), then upgrade the road under it
   (or build a new stop on the same street segment): "My Stop" stays. Any `renamed ... (My Stop)` line is a bug
   (it means `new2oldEdgeObjects` isn't keyed as expected).
5. [ ] **Rename a stop within a second** of building it (open its window right away and rename): your name stays.
6. [ ] **Town renamed**: rename Seattle to something else, build a stop there: no rename. Rename a small town to
   "Tacoma", build a stop: a Tacoma street.
7. [ ] **Stop outside any town** (country road): keeps its default name, no error.
8. [ ] **Bulldoze and rebuild**: build a stop in Seattle (gets e.g. Pike Street), bulldoze it, build another: Pike
   Street again. Bulldoze a stop **right after** placing it (within a second): no error line.
9. [ ] **Fast building**: drop 4-5 stops in Seattle as fast as you can (and one drag of several if the tool allows):
   all different streets, no two alike.
10. [ ] **Save right after building** (within a second), load that save: the stop is renamed shortly after load,
    once; no error.
11. [ ] **Default-name collision**: in a city whose list is used up (build more stops than it has streets, e.g. a
    small city), names go "<Street> East", "<Street> West", ... and never repeat exactly.
12. [ ] **Two state mods** (only once a second state exists): with the Washington set, only Washington renames.
