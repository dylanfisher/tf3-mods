# US State Names series (`square_names_us_<state>`): research

Status: done 2026-10-08. Its open unknowns were answered by Probe 3 or carried into PLAN.md "Open work".

Goal: one mod per US state (Washington first). Each mod adds a name set (towns, generic streets, person names) and a
game script that gives known cities their real streets (Seattle → "Pike Street") and other real names. Town choice
should follow the map's climate where possible. Background from the single-mod plan:
`plans/square_town_street_names/{research,PROBE,PLAN}.md` and `docs/findings.md` "Street names and Road Stops".

Researched 2026-10-08 against the installed build (`.cache/game`, `docs/wiki`, the game binary's strings, and the
probe run logs in `<userdata>/crash_dump/stdout.txt`). "Binary" means `strings -n 5` on
`Transport Fever 3/TransportFever3`. `api/` is short for `.cache/game/api/tealdef/api/`, `base/` for
`.cache/game/base/content/`.

## Summary

| Question | Answer | Status |
|---|---|---|
| Stops can be renamed to real streets | Yes: `onPostBuildProposal` gives the real station id, `stationSystem.getTown` gives the town, `makeEntitySetNameCmd(stationGroup, name)` from `update` sticks | **Confirmed** in game (findings.md) |
| When does the engine ask for town names? | **Once per new game**, with `num` = number of towns (13), after the config dict and mod params are logged and after the ModelRep load | **Confirmed** (probe log) |
| Which town gets which name? | In the order the script returns them: entity ids 15357, 15358, … got Seattle, Tacoma, … (the list order) | **Confirmed** (probe log). Whether the first town is the biggest one is unknown (§4.4) |
| Climates in the base game | `temperate` ("Temperate"), `dry` ("Desert"/"Dry"), `tropical` ("Tropical"), `subarctic` ("Subarctic"). Mods can add more | **Confirmed** (`base/climates/*/*.gen.lua`, `.clima.lua`) |
| Can a name script see the climate? | Its params are only `{lang, num}`. `api.engine.config.getConfigDict()` exists, and `runFn` gets `configDict.climate`. Name scripts have **no `api.engine`**; the `runFn` global **is** visible (same Lua state) | **Confirmed** Probe 3 (2026-10-08, findings.md) |
| Can a game script see the climate? | `api.engine.config.getConfigDict()` returns `{climate, economy, nameList}` (`api/engine.d.tl:1803-1807`); base game scripts already call its sibling `getModParams()` | API **confirmed**, runtime check in Probe 3 |
| Renaming towns after game start by climate | Possible in principle, but industries are already named "{town} {industry}" with the *old* town name at generation (§5.2). Rejected | Inference from probe log |
| Several name sets in one mod | Fine. `NameRep` loads every `*.names.lua` from the resource file system; the base game ships 20 sets from one package | **Confirmed** (binary, `base/names/`) |
| What else does the engine name? | Industries "{town} {industry}", construction stations "{townName} Station" + suffixes, edge-object stops from the street pool, waypoints/signals "{townName} Waypoint #n". All follow the town names automatically | **Confirmed** (binary strings + probe dump) |
| Safe extra renames | Player-built passenger stations (train, bus/tram, airport, harbour) to real landmark names, same detection pattern as stops | Mechanism confirmed for stops; for constructions the displayed form ("X" vs "X Station") is **Probe 3** |
| Cover flag | `cover.js` renders an SVG string in headless Chrome from a `file://` page; an `<image href>` to a local file already works (Better Minimap cover). An SVG flag drawn through `<image>` runs no scripts | **Confirmed** (branding/, Chrome behaviour) |

## 1. Prior results that carry over

From `docs/findings.md` "Street names and Road Stops" (probe runs 1 and 2, 2026-10-08):

- `streetNamesScript` is only called with `num = -1` (262 calls in one session). The engine picks the **first unused
  name in list order**. The counter is global per map, not per street, and a freed name is reused.
- The stop's name lives on the **station group**; the station shows the same value.
- `onPostBuildProposal`: `proposal.proposal.edgeObjectsToAdd[i]` has category 0 and, after the build, the **real
  station id**. `playerInitiated` is true for player builds.
- `stationSystem.getTown(station)` is right immediately after the build.
- Build events and `update` behave like separate Lua states (module locals don't carry over). Pass data via `state`.
  Base `towns.script.tl:232-337` calls `state:set` inside `handleEvent`, so a build event may write the state; it
  just may not send commands (memory `gs-no-sendcommand-in-build-events`).
- `api.cmd.sendCommand(cmd)` without callback from `update` works; with a callback it fails ("Callbacks are
  currently disallowed").
- `makeEntitySetNameCmd(stationGroup, name)` renames group and station within one update. **Duplicates are accepted
  as-is** (no suffix), so the mod must avoid them itself.

## 2. How names are generated (engine side)

- Binary, next to `NameRep.cpp`: `.names.lua`, `loadNameList`, `GenerateTownNames`, "Town name generation function
  did not return the expected number of names: ", `townNamesScript`, `streetNamesScript`, `personNamesScript`,
  `isMale`. Next to the industry builder: `townNames.size() >= result.toAdd.size()`, "Error generating town names".
  The `NameRep` constructor takes the file system, a resource cache, a `lua::Loader` and a `ScriptRep`, so name scripts
  run through the ordinary script repository (which Lua state is unknown, §4.3).
- Probe log (`stdout.txt` line 3593 and again at 5130 for a second new game): exactly one
  `names towns call=1 lang=en num=13` per new game, logged after "Config dict: climate … nameList …", "mod params"
  and "ModelRep load complete", and before "Towns 'Olympia' and 'Kent' connected". The main-menu map preview also
  generates towns ("Average town size", "Create Industries") but **does not** call the town script.
- The 13 names went to the town entities in order: `dump town 15357 "Seattle"`, `15358 "Tacoma"`, … `15369
  "Kirkland"` = the first 13 entries of the probe list. So the script controls not just *which* names appear but
  *which town* gets which name (by creation order).
- Name sets are save-bound: loading or starting a game with a mod's name set logs
  "Autoactivating square_town_street_names_probe (required by nameList)". A save that uses our set always loads the
  mod. With the probe (`cosmetic: true`) the log said "Achievements earnable: true".
- Base scripts (`base/names/names.script.lua`): `townsNameScriptFn` loads `<modId>::/names/<path>/<lang>/towns.lua`,
  returns everything for `num < 0`, else a reservoir sample. `streetsNameScriptFn` returns a fresh shuffle for
  `num < 0`. `personNameScriptFn` combines first and last names from `personnameutil.lua` (`names.usa.en` has
  ~100 male, ~100 female first names and ~3,000 last names).
- Base list sizes: `usa/en/towns.lua` 2,211 towns, `usa/en/streets.lua` 75 streets; england 1,033/49, germany
  1,895/62.

## 3. What else can be named

### 3.1 What the engine names by itself

Format strings in the binary (around `name_util.cpp`, `preprocess_proposal.cpp`, `VehicleDepotSystem.cpp`):

```
{townName} {constructionName}            constructions: industries, depots, stations (CreateProposalAddConstruction)
{constructionName} {subConstructionType}
{townName} Station                       construction stations
{stationName} East|North|West|South|Annex|Branch|Central|Exchange|Halt|Sidings|Transfer, Lower/Upper {stationName}
{stationName} #{number}, Stop #{number}  tie-breakers
{townName} Waypoint #{number}, {townName} Signal #{number}
```

Probe dump on the Washington test map (temperate, 13 towns): industries became `"Tacoma Crop Farm"`,
`"Seattle Fishing Grounds"`, `"Olympia Oil Refinery"`, `"Spokane Clay Pit"`; their station groups carry those names
as NAME, and the stations show `"<group> Station"`. So **industries, their stations, depots, waypoints and signals
automatically pick up our town names**. Nothing to do there; the description can still advertise it.

### 3.2 Candidates for a rename on build

| Entity | Default | Real-world option | Verdict |
|---|---|---|---|
| Edge-object stops (Road Stop, two-sided) | next street from the pool | per-city real streets | **Do it** (core feature, proven) |
| Player train station (passenger) | "{town} Station" (assumed from the format string) | King Street Station, Union Station (Tacoma), Everett Station, Spokane Intermodal Center… | **Do it** for the first one or few per city; data is small and verifiable |
| Airport / airfield | "{town} …" | Seattle–Tacoma International, Boeing Field, Paine Field, Spokane International, Bellingham International, Tri-Cities Airport, Pangborn Memorial… | **Do it** (one or two per city) |
| Harbour (passenger) | "{town} …" | Colman Dock, Port of Tacoma, Port Angeles Ferry Terminal, Anacortes Ferry Terminal… | **Do it** |
| Bus/tram station (modular street station) | "{town} Station" | neighbourhood names: Capitol Hill, Ballard, Fremont, University District… | **Do it** with a per-city neighbourhood list ("{Neighbourhood}" or "{Neighbourhood} Station", depends on Probe 3) |
| Cargo stations, depots | "{town} …" | yards (Interbay, Stampede…) | Later, low value |
| Industries | "{town} {industry}" | company names | **No**: generated at map creation, not player-built, and real company names are trademarks |
| Person names | base `usa` parts | state-flavoured surnames | Reuse base `usa` via `::/names/names.script@personNameScriptFn` (no copying). State flavour has little visible effect and no good public source |
| Lines, vehicles | player-named / "Line n" | | **No**: auto_line_namer covers lines |
| Towns | from our name set | | Name set (with climate, §4) |

All renames use the confirmed pattern: detect in `onPostBuildProposal` (real ids after the build: stops in
`edgeObjectsToAdd[i]` results, constructions in `param[3]` result entities, `refund.script.tl:292-299`), queue the
station ids in `state`, rename the **station group** from `update`. Construction kinds come from the construction's
resource (`ConstructionType` `RAIL_STATION`, `STREET_STATION`, `AIRPORT`, `HARBOR`, … `api/type.d.tl:2192-2213`) or
the file name (`stations/rail/modular_station`, `stations/street/modular_street_station`, `stations/air/airport`,
`stations/water/harbor_modular`, …).

Open for constructions (Probe 3, step 4): for industries the group NAME is "Tacoma Crop Farm" and the station
shows "Tacoma Crop Farm Station", so setting a group to "King Street Station" might display "King Street Station
Station". `base/mission/name_util.tl:4-130` sets group NAMEs for constructions and expects construction stations to
have no NAME of their own, which fits. The probe now renames construction groups to "King Street" etc. (without
"Station") and logs what the station and group show.

## 4. Climate awareness

### 4.1 Climates

`base/climates/<c>/<c>.gen.lua` (`climate = "<c>.clima"`, `name`, `order`): temperate (order 0, "Temperate"),
dry (1, "Desert"), subarctic (1, "Subarctic"), tropical (2, "Tropical"). Map types per climate: dry: Lakes / Rivers /
Mountains; tropical: Ocean / Islands; subarctic: Water / Swamps; temperate: Lakes / Rivers / …. Economies:
`base/economy/{temperate,dry,subarctic,tropic,all}.eco.lua`. The config dict holds the resource name, e.g.
`climate: ::/climates/temperate/temperate.clima` (probe log). Mod climates have other names, so match on the last path
segment and fall back to "all" for unknown ones.

### 4.2 Where the climate is visible

| Context | Climate visible? | Source |
|---|---|---|
| `preRunFn` / `runFn` / `postRunFn` | Yes: `configDict.climate` (`runFn(captureParams, settings, allModParams)`, `settings.climate`) | `base/base/base_mod.lua:8-17`, findings.md |
| Game script (`update` / `handleEvent`) | Yes (API): `api.engine.config.getConfigDict()` | `api/engine.d.tl:1803-1807` |
| Name scripts | Only `{lang, num}` (+ static captureParams). No modifier or file-filter category for names (`docs/wiki/modding/scripting/modifiersfilters.md`) | `docs/wiki/modding/misc/names.md` |
| Name script → `api.engine.config.getConfigDict()` | **No**: `api.engine` is nil there | Probe 3 (2026-10-08, findings.md) |
| Name script → global set by `runFn` | **Yes**: both run in "Load Game Pool 1" (`runFnGlobal climate=::/climates/tropical/tropical.clima`). A plain assignment logs ERROR "Global variable in mod" (base `init.lua` `_G.__newindex`), so write it with `rawset(_G, …)` | Probe 3 (2026-10-08, findings.md) |

### 4.3 Probe 3 (added to `mods/square_town_street_names_probe`, 2026-10-08)

- `mod.json` now has a `runScript` → `content/mod.script.lua` `runFn`, which stores
  `SQTSN_PROBE_RUNFN = {climate, nameList, n}` as a global in every state it runs in.
- The name set's three scripts (towns, streets and now **persons**) log one
  `[SQTSN_PROBE] names ctx <kind> | _VERSION | api= | api.engine= | getConfigDict climate=… | getModParams[""] |
  isMapEditor | runFnGlobal climate=… | game= | logmsg=` line per Lua state, through `print` and `log.message` (the
  latter shows the thread column, i.e. which state runs the name scripts). Person names log the first 3 calls and
  every 200th.
- The game script logs `dump configDict climate=… economy=… nameList=…` and each town's
  `initialCap=… sizeFactors=…` (is the first-named town the biggest?).
- With the rename test on, construction-station groups get "King Street", "Union Station", "Sea-Tac Airport",
  … (no "Station" suffix) so the verify line shows whether the engine appends " Station".
- `make check` / `make test` / `make validate` pass (test `climate probe: runFn global, name script context and
  person names`). Run steps are in `PLAN.md` "Probe 3".

### 4.4 Options

| Option | How | Pros | Cons |
|---|---|---|---|
| **A. Climate-aware name script** | `townsFn` reads the climate (`getConfigDict()` or the `runFn` global) and samples from climate-tagged town pools | Correct names from the start; one name set per state; works for industries too | Depends on Probe 3 |
| **B. Rename towns in a game script at `initNewGame`** | GS sees climate, renames towns via `makeEntitySetNameCmd` | No probe dependency | Industries and their stations were already named after the *old* town names ("Seattle Fishing Grounds" next to a town now called Yakima); would have to rename those too. Must never fire on an existing save. Fragile. **Rejected** |
| **C. One name set per region** | e.g. "Washington: West (wet)" and "Washington: East (dry)" (+ "Washington: All") from one mod | Zero risk, works today, explicit player choice | Player must pick the matching set; more entries in the name-set list |
| D. `runFn` file hand-off | `runFn` writes a file, name script reads it | | Needs `io` in both sandboxes; untested and hacky |

**Decided (Probe 3, 2026-10-08): A via the `runFn` global** (rawset, plus a shared module table as fallback); C stays
off (`emitRegionalSets = false`). Original recommendation: A, with C as the fallback. Run Probe 3 first (one new game on Desert, one on Temperate). If the
name script sees the climate by either route, ship one climate-aware set per state. If not, ship regional sets (C);
the generator supports both from the same data (region tags), so the decision doesn't change the data format.

Probe 3 answer: town sizes are random relative to name order (Seattle, 1st name, `initialCap` 94; the 9th name 335).
Putting big-city names first does not make them the big towns; the ordering stays (harmless) but is never advertised.

## 5. Other design facts

### 5.1 Name-set discovery and multiple sets per mod

- The game finds sets by the `.names.lua` extension anywhere in the resource tree (binary `.names.lua` +
  `loadNameList`; the probe's `content/names/tsn_probe/tsn_probe.names.lua` showed up and was selectable). The base
  package registers 20 (`base/names/*/*.names.lua`), so several per mod are fine.
- The binary also lists base set aliases (`::/names/usa.names` → `::/names/usa/usa.names`), i.e. sets are referenced
  by resource path in the save's config dict (`nameList: square_town_street_names_probe::/names/tsn_probe/tsn_probe.names`).
  **Renaming or moving a set file after release breaks saves that use it.** Paths are permanent.

### 5.2 Several state mods active at once

- Every active state mod runs its own game script. Two mods that both know a town name (Portland ME vs Portland OR,
  Vancouver WA vs nothing yet) would both rename the same stop.
- Resource paths are a shared overlay (mods override base files by path), so two mods shipping the same relative
  path (e.g. `content/state_names/runtime.lua`) would shadow each other. **Every file path must contain the modId.**
- `getConfigDict().nameList` tells each script which name set the game uses; `getModParams()` is keyed by modId
  (findings.md), so a mod with at least one param can see which other state mods are active.

### 5.3 Third-party "Washington Names"

`.cache/subscribed/arizonaranger_washington_names` (mod.io "Washington Names" by AZ-Ranger): a plain set named
"Washington", 635 towns and 84 generic streets, using the base scripts with `path = "washington"`,
`severityRemove: "Critical"`. We don't copy or derive from its files. Our names must not read as the same mod: avoid
the display names "Washington Names" and plain "Washington", and avoid `content/names/washington/` (a path clash
would shadow one set with the other when both are active).

### 5.4 Data sources

- **Towns**: US Census Bureau (public domain, US federal work).
  - Gazetteer places file (`<year>_Gaz_place_national.txt`): GEOID, NAME with LSAD suffix ("Seattle city",
    "Ahtanum CDP"), ALAND, `INTPTLAT`/`INTPTLONG`. Gives location for the region split.
  - Population estimates for incorporated places by state (`SUB-EST<year>_<fips>.csv`, popest "cities and towns").
    Gives a size tier ("big" towns first).
  - Washington: state FIPS 53, ~281 incorporated places plus ~350 CDPs.
- **Region split for Washington**: the Cascade crest. Longitude alone gets most places right (west of about
  -121.0 is wet side), with a short reviewed override list for valley towns near the crest (Leavenworth, Cle Elum,
  Roslyn, Skykomish, North Bend, Packwood…). Coast/islands and mountain tags are hand-added (San Juan, Island,
  Clallam, Jefferson, Grays Harbor, Pacific counties; Methow/Okanogan/Pend Oreille).
- **Streets per city**: drafted by hand (only well-known, major streets), checked against OpenStreetMap: each
  drafted name must exist as a `highway=*` way inside the city boundary (Overpass query per city). We use OSM as a
  check, not as a bulk source, so the list stays our own small curation.
- **Station / airport / harbour names**: real facility names (WSDOT ferry terminals, FAA airport names, Amtrak
  station names). Use short common forms; avoid trademarks such as airline or company names.

## 6. Cover with a flag sticker

- `branding/cover.js` builds a 1920×1080 SVG string; `render.html?mod=<id>` draws it and `tools/render_covers.py`
  screenshots it with headless Chrome (`--virtual-time-budget=3000`, `file://` URL).
- Local files are already referenced from a cover: Better Minimap's glyph uses
  `<image href="../plans/square_better_minimap/shots/01-overview.jpg">` (`branding/mods.js:95-107`). An `.svg` flag
  works the same way (`<image href="flags/us_washington.svg">`, relative to `branding/`). SVG drawn through
  `<image>` is rendered as a static image: no scripts, no external loads. Still sanitize before committing (the file
  also lives in the repo).
- Filters needed for the sticker (white die-cut border, `feDropShadow`, a peeled corner) are plain SVG and already used
  (`bmShadow` in the Better Minimap glyph).
- `tools/render_covers.py` finds mods by the regex `^\s*id:\s*'…'` in `mods.js`, so a series helper must still
  write `id: '…'` at the start of a line.
- **Flag sources**: Wikimedia Commons "Flag of <State>.svg". US state flags are generally public domain (old designs,
  or tagged PD-ineligible / PD-self on Commons), but this has to be checked **per file** through the Commons API
  (`prop=imageinfo&iiprop=url|sha1|extmetadata`: `LicenseShortName`, `Artist`). Some states regulate the use of their
  **state seal** (Washington's flag carries the seal; RCW 1.20.080 restricts the seal's commercial use, as far as I
  know: **verify**). A free mod cover is not commercial, but the user should be aware.

## 7. Unknowns

1. ~~Does the name script see the climate?~~ Answered (Probe 3): the runFn global yes ("Load Game Pool 1"), getConfigDict no.
2. When and how often are person names requested (per sim person, once per load)? (Probe 3)
3. ~~Is the first-named town the biggest?~~ Answered (Probe 3): no, sizes are random relative to name order.
4. Construction-station rename: does "King Street" display as "King Street Station"? What's the default name of a
   player-built train station, airport, harbour, bus station? (Probe 3 step 4; PROBE.md step 6 was never run)
5. Two-sided stops, a stop joining an existing group, stops outside towns: handled defensively in Phase 2 (unit tests);
   in-game confirmation in TESTING.md "Phase 2".
6. Map editor: does the town script run when a town is placed, with `isMapEditor = true`? (Probe 3 optional step)
7. Exact rules for using each state flag/seal (per-state check before each release).
