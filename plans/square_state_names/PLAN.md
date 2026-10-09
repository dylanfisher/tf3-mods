# US State Names series: plan

One mod per US state, Washington first. Each mod gives a new game **real towns of that state (chosen by the map's
climate)**, gives **known cities their real streets** for new bus stops (Seattle → "Pike Street"), and gives new
**train stations, airports, harbours and bus/tram stations real names** ("King Street Station", "Paine Field",
"Colman Dock", "Capitol Hill"). Everything else the engine names after towns (industries, their stations, depots)
picks up the real town names by itself.

Research and citations: `research.md`. Supersedes `plans/square_town_street_names/PLAN.md` (its probe,
`mods/square_town_street_names_probe`, stays the shared dev probe).

**Status (2026-10-08):** Phase 1 implemented (offline green, awaiting the in-game run in `TESTING.md` Phase 1).
Probe 3 answered the climate route (runFn global via rawset, findings.md) and town order (random sizes); the
station-suffix question (step 4) is still open. Phase 2 (edge cases) implemented, offline green (see its Status).

## Decisions for the user

| # | Question | Recommendation |
|---|---|---|
| U1 | modId scheme | `square_names_us_<state>` (e.g. `square_names_us_washington`): sorts as a series, leaves room for non-US sets later, and avoids the Georgia (US) vs Georgia (country) clash. Shorter alternative: `square_names_<state>` |
| U2 | Mod display name | **"Washington Towns & Streets"** (series: "<State> Towns & Streets"). Doesn't read like the third-party "Washington Names" |
| U3 | Name-set display name (game settings list) | **"Washington (Towns & Streets)"**; regional fallback sets "Washington: Westside", "Washington: Eastside" |
| U4 | Station renames on by default? | Yes, as a mod param "Real station names" (On/Off). Stop renames also get a param ("Real street names") |
| U5 | Climate approach if Probe 3 fails | Regional sets (option C below). If it succeeds: one climate-aware set |
| U6 | Flag use | Washington's flag carries the state seal; check the seal-use rule (research.md §6) and decide before the cover ships |

## How it works

### Name set (towns, streets, persons)

- One `.names.lua` per mod at `content/names/<modId>/<stateKey>.names.lua` (path contains the modId: research.md §5.2,
  and **never moved after release**: saves reference it, §5.1).
- `townNamesScript` → our `townsFn`. Every town in the data has region tags. The state data maps climates to tag
  weights. For Washington:

  | Climate (config dict, last path segment) | Town pool |
  |---|---|
  | `temperate` | 70 % `west` (Puget Sound, southwest), 15 % `coast`, 15 % `east` |
  | `dry` (Desert) | 85 % `east` (Columbia Basin, Yakima Valley, Tri-Cities, Palouse, Spokane), 15 % `mountain` |
  | `subarctic` | `mountain` + `north` (Methow, Okanogan, Stevens/Pend Oreille, Cascade passes), topped up from `west` |
  | `tropical` (Ocean/Islands) | `coast` + `islands` (San Juans, Whidbey, Olympic and Long Beach peninsulas), topped up from `west` |
  | unknown (mod climates) or not visible | whole state, weighted by population tier |

  Sampling: weighted by tag, no duplicates; when a tag pool runs dry, top up from the other tags, then (only past
  ~600 towns) allow repeats like the base script. Big towns (`big` tag, top ~15 by population, e.g. Seattle,
  Spokane, Tacoma, Vancouver, Bellevue, Yakima, Kennewick) that fit the climate are guaranteed a place. Probe 3:
  town sizes are random relative to name order, so their going first is only a stable order (never advertised).
- `streetNamesScript` → our `streetsFn`: a state-flavoured generic pool (~120 names: numbered streets and avenues,
  "NE 8th Street" style, trees such as Cedar, Alder, Hemlock, Madrona, plus Cascade, Columbia, Pioneer, Railroad,
  Front, Main, Division), returned as a fresh shuffle for `num = -1` (like base). Used for stops in towns without a
  city list.
- `personNamesScript` → base `::/names/names.script@personNameScriptFn` with `path = "usa"` (no copied lists).
- **Climate approach: A via the runFn global (confirmed by Probe 3, 2026-10-08)**: name scripts have no `api.engine`,
  but run in the same Lua state as `runFn`, which stores `configDict.climate` with `rawset(_G, …)` (a plain
  assignment logs ERROR "Global variable in mod") and in the shared module `sn_shared.lua`. Option C stays off. If
  neither worked,
  the generator emits regional sets instead: "Washington: Westside" (tags west+coast) and "Washington: Eastside"
  (east+mountain), plus "Washington (Towns & Streets)" for the whole state. Same data either way (research.md §4.4).
  Renaming towns after map creation (option B) is rejected: industries are already named after the old towns.

### Game script (real streets and stations)

Same pattern as the proven probe (research.md §1):

1. `update` subscribes lazily: `subscribeToNoEvents` + `subscribeToEvent("onPostBuildProposal")`. Does nothing in the
   map editor (`getModParams()[""].isMapEditor`).
2. `handleEvent` (`id == "apply_command"`, `name == "onPostBuildProposal"`, `param[4] == true` = player build):
   collects new station ids: edge objects with category 0 and a result id ≥ 0, plus result entities of added
   constructions whose kind is a passenger station (rail, street, airport, harbour). Appends `{station, kind}` to
   `state.queue` (cap 64) with `state:set`. No commands here.
3. `update` (at most every 0.5 s, and only while the queue is non-empty): for each queued station, find its group
   (`stationGroupSystem.getStationGroup`) and town (`stationSystem.getTown`). Skip when: no town; the town's
   **current** name has no city entry; the group holds stations that weren't in this build (joined an existing
   group, Phase 2); or the group name changed since the build (player rename). Otherwise pick a name and send
   `makeEntitySetNameCmd(group, name)` without a callback. Clear the queue.
4. Picking a name (pure `sn_logic.lua`, unit-tested):
   - Stops: the first street of the city's list (per-town order: list order, or shuffled with the town entity id as
     the seed) that no station group in that town uses yet (`getTown2StationsMap()[town]` → group names, compared
     without suffixes). All used → the same street with the engine's own suffix style (" East", " West", " #2")
     so names stay unique (the engine accepts duplicates: findings.md).
   - Stations by kind: the city's `rail` / `airport` / `harbor` list in order; bus/tram stations take the city's
     `neighborhoods`. Exhausted list → leave the default name. The "Station" suffix question is Probe 3 step 4.
5. Several state mods active: the mod whose name set is the game's `nameList` handles all renames and the others stay
   idle. If the game uses another set (base, or third-party), each state mod renames only towns in its own data. A
   town known by two active mods (Portland ME/OR) gets renamed by both and keeps whichever lands last: a real name
   either way. Accepted limitation.

### Save safety (memory `mods-must-not-impact-saves`)

- `severityAdd: None`, `severityRemove: Warning`, `cosmetic: true` (the probe with a name set and game script kept
  "Achievements earnable: true"). Note: a save started with our name set auto-activates the mod
  ("Autoactivating … (required by nameList)"), so it can't really be removed from such a save. On any other save,
  removing it leaves the given names and stops renaming.
- Only stations from a **player** build seen in this session are renamed, once, seconds after the build. Never
  existing stops, never anything on load, never in the map editor.
- Saved state: the pending queue only (normally empty). Lazy init; no reliance on `init`/`initNewGame`.
- Every entry point wrapped in `pcall`; each distinct error logged once with the `[<modId>]` tag. Plain Lua, pre-5.3;
  `.script.lua` exports via `data()` (memory notes).

## Repo layout

```
data/states/us_washington/          per-state data (reviewed, committed)
  state.lua                         meta: key, state name, postal code, display names, flag file, climate→tag weights,
                                    region overrides, description blurbs
  towns.tsv                         name <TAB> tags <TAB> population <TAB> lat <TAB> lon <TAB> note
                                    (draft from Census by tools/state_towns.py, then hand-edited)
  streets.lua                       generic street pool
  cities.lua                        per city: aliases, streets, neighborhoods, rail, airport, harbor
templates/state_names/              shared runtime, with {{MOD_ID}} / {{STATE_KEY}} placeholders
  mod.json.tmpl, modinfo.json.tmpl, description.html.tmpl
  content/mod.script.lua            runFn: stores configDict.climate in a namespaced global (only if option A uses it)
  content/names/names.script.lua    townsFn / streetsFn
  content/runtime/sn_logic.lua      pure logic (normalize, climate key, town sampling, street/station picking)
  content/runtime/rename.script.lua game script; rename.gs.lua registration
  tests/test_logic.lua, test_names.lua, test_rename.lua, test_data.lua
tools/gen_state_mod.py              data + templates → mods/<modId>/ and tests/<modId>/
tools/state_towns.py                Census files → towns.tsv draft (region tags from lon/lat + overrides)
tools/fetch_flags.py                pinned Commons URLs → sanitized branding/flags/<stateKey>.svg
branding/flags/                     <stateKey>.svg + SOURCES.json (file page, URL, sha1, licence, author, date)
mods/square_names_us_washington/    GENERATED, committed (it's what make link/validate/upload use)
tests/square_names_us_washington/   GENERATED from templates/state_names/tests
```

Generated mod layout (all paths namespaced by modId, research.md §5.2):

```
mods/square_names_us_washington/
  mod.json, _metadata/{modinfo.json, description.html, 0.png}
  content/mod.script.lua                                        (runFn; only if climate option A needs it)
  content/names/square_names_us_washington/us_washington.names.lua
  content/square_names_us_washington/{names.script.lua, sn_logic.lua, rename.script.lua, rename.gs.lua}
  content/square_names_us_washington/data/{towns.lua, streets.lua, cities.lua, state.lua}
```

Every generated file starts with `-- GENERATED by tools/gen_state_mod.py from templates/state_names and
data/states/<key>; edit those, not this file.` `description.html` and `0.png` are generated too (the changelog
entries live in `state.lua`, so the template can render them).

### Data format (examples)

```lua
-- data/states/us_washington/state.lua
return {
  key = "us_washington", name = "Washington", postal = "WA", fips = "53",
  modName = "Washington Towns & Streets", setName = "Washington (Towns & Streets)",
  regionalSets = { { id = "westside", name = "Washington: Westside", tags = { "west", "coast", "islands" } },
                   { id = "eastside", name = "Washington: Eastside", tags = { "east", "mountain", "north" } } },
  climates = {
    temperate = { west = 70, coast = 15, east = 15 },
    dry       = { east = 85, mountain = 15 },
    subarctic = { mountain = 50, north = 50, west = 0 },   -- 0 = top-up only
    tropical  = { coast = 50, islands = 50, west = 0 },
  },
  flag = "us_washington.svg", accent = "#00843D",
  revision = 1, changelog = { { rev = 1, date = "YYYY-MM-DD", items = { "First release." } } },
}
```

```
# towns.tsv (excerpt)
name	tags	population	lat	lon	note
Seattle	west,big	755078	47.62	-122.35
Yakima	east,big	96968	46.59	-120.53
Friday Harbor	islands,coast	2600	48.53	-123.03
Winthrop	mountain,north	500	48.47	-120.18
```

```lua
-- cities.lua (excerpt)
return {
  ["Seattle"] = {
    streets = { "Pike Street", "Pine Street", "Union Street", "University Street", "Seneca Street", "Spring Street",
                "Madison Street", "Marion Street", "Columbia Street", "Cherry Street", "James Street", "Yesler Way",
                "Jackson Street", "Denny Way", "Mercer Street", "Broadway", "Westlake Avenue", "Eastlake Avenue",
                "Rainier Avenue", "Aurora Avenue", "Fremont Avenue", "Stone Way", "Roosevelt Way", "Leary Way" },
    neighborhoods = { "Capitol Hill", "Ballard", "Fremont", "University District", "Queen Anne", "Columbia City" },
    rail = { "King Street Station" }, airport = { "Sea-Tac Airport", "Boeing Field" }, harbor = { "Colman Dock" },
  },
  ["Tacoma"] = { streets = { "Pacific Avenue", "Commerce Street", "Tacoma Avenue", "Division Avenue", "6th Avenue",
                             "Puyallup Avenue", "Ruston Way" }, rail = { "Tacoma Dome Station" } },
}
```

Lint (generator `--check` and `test_data.lua`): every string non-empty, ≤ 40 bytes, valid UTF-8, no duplicates per
list; town names unique after normalization; every tag used in `climates` exists; each climate pool (with top-ups)
yields ≥ 150 distinct towns; every city key matches a town in `towns.tsv` (or an alias); streets of a city don't
appear twice across its kinds.

### Generator (`tools/gen_state_mod.py`)

- `make state-mod STATE=us_washington` renders one mod; `make state-mods` renders all; `--check` exits 1 if a
  generated file differs from what's on disk (stale) or the data lint fails.
- Converts `towns.tsv` to a Lua table, copies the runtime, substitutes `{{MOD_ID}}` / `{{STATE_KEY}}`, writes
  `mod.json` (params as Button On/Off, no `numbers`), `modinfo.json` (author square, tags "Script Mod" + the name-set
  tag the wiki/mod.io uses), `description.html`, and `tests/<modId>/`. Adds the `branding/mods.js` entry if missing.
- Next state = new folder under `data/states/` + `make state-mod STATE=us_oregon` + flag + cover. No code copy.

## Cover: flag sticker (series look)

Every state cover is the normal Diagonal Split (title = mod name, tagline **"Real towns, streets & stations"**, 30
characters) plus the state flag as a sticker. Implemented once in `cover.js` as `Square.stateCover({...})`, which
calls `Square.register` with `id`, `name`, `tagline`, `accent` and a glyph; `mods.js` gets one call per state with
`id: '…'` at the start of a line (`render_covers.py` greps for it).

- **Pictogram (behind the sticker)**: an ink street-name sign, a post with a blank blade and two knocked-out bars, lower
  right of the dark side (flat, no text, per README). Same for every state.
- **Sticker**: the flag, 700 px wide on the cover (height from the flag's viewBox aspect, recorded in SOURCES.json),
  centred at (1390, 470) so it overlaps the teal stripe a little, rotated **-8°**. 22 px white die-cut border with
  20 px corner radius, `feDropShadow` dy 16 / blur 22 / 45 % black. Bottom-right corner peeled: a 90 px triangle cut
  from the flag, with a white fold triangle shaded by a short grey gradient. Same position, angle and size for
  every state.
- `accent`: the flag's main colour (WA green `#00843D`), only for the README palette table; the pictogram stays ink.
- Flag files: `branding/flags/<stateKey>.svg`, loaded with `<image href="flags/us_washington.svg">`.

### Fetching flags (`tools/fetch_flags.py`)

- `branding/flags/SOURCES.json` pins each flag: Commons file page, `upload.wikimedia.org` URL, sha1, licence
  (`LicenseShortName`), author, retrieval date. `--lookup "Flag of Washington.svg"` queries the Commons API once and
  prints these for the user to pin. The tool refuses anything not "Public domain" / "CC0" unless `--allow` is given.
- Download into its own empty directory `.cache/flags/raw/<stateKey>/` (gitignored), verify the sha1, then sanitize
  with a separate script run as `python -I tools/sanitize_svg.py <in> <out>`: reject DOCTYPE/ENTITY; keep only shape,
  group, gradient, clip and `use` elements; drop `script`, `foreignObject`, `image`, `style` with `@import` or
  `url(http…)`, every `on*` attribute, and every `href` not starting with `#`. Write to `branding/flags/` and print
  the size and element counts for review. Nothing from the download dir is executed or imported.

## Description template (generated)

```html
<p>Play in Washington: towns from Seattle to Spokane, real streets for your bus stops, and real names for stations,
airports and ferry docks.</p>
<h4>Features</h4>
<ul>
<li><strong>Washington towns</strong>: a name set with N real towns. The map's climate picks the region: temperate
maps get the wet west side, desert maps the dry east, ocean maps the islands and coast.</li>
<li><strong>Real streets</strong>: new bus stops in M cities (Seattle, Tacoma, Spokane, …) are named after real
streets, like Pike Street or Pacific Avenue. Other towns use Washington-style street names.</li>
<li><strong>Real stations</strong>: new train stations, airports, ferry docks and bus stations in those cities get real
names, like King Street Station, Paine Field or Colman Dock.</li>
<li><strong>Everything else follows</strong>: industries, depots and their stations are named after your Washington
towns by the game itself.</li>
</ul>
<h4>Settings</h4>
<ul>
<li><strong>Real street names</strong> (default On) …</li>
<li><strong>Real station names</strong> (default On) …</li>
</ul>
<h4>Notes</h4>
<ul>
<li>Choose "Washington (Towns & Streets)" as the name set when starting a new game. Street and station names also work
with any other name set, in towns that have a Washington city's name.</li>
<li>Only renames what you build, right after you build it. Your own renames are never touched. Safe to add to an
existing save.</li>
<li>Not affiliated with the "Washington Names" mod. All lists are our own.</li>
</ul>
<hr>
<h2>Changelog</h2>
<h4>Revision 1 (YYYY-MM-DD)</h4>
<ul><li>First release.</li></ul>
```

## Phases (one subagent each, memory `phases-in-subagents`)

### Probe 3 (user, before Phase 1): climate visibility and station names

Code is in place (`mods/square_town_street_names_probe`, see research.md §4.3); `make check/test/validate` pass.

0. Quit the game. `make link` (probe linked). Watch the log:
   `tail -f ~/Library/Application\ Support/Steam/userdata/*/3493540/local/crash_dump/stdout.txt | grep --line-buffered SQTSN_PROBE`
1. **New game, Desert climate**, small map, probe enabled, name set **DEV TSN Probe**, params default.
   Expect `names ctx towns | … | getConfigDict climate=… | runFnGlobal climate=… | logmsg=…` (twice: once from
   `print`, once from `log.message` with a thread column). Note the thread and both climate values.
   Then `dump configDict climate=::/climates/dry/dry.clima …` and `dump   town … initialCap=… sizeFactors=…`.
2. Play a minute at speed: look for `names ctx persons` and `names persons call=1..3` (when person names are made).
3. Save. **New game, Temperate**: the `names ctx towns` climate must change to temperate (if it showed one at all).
4. Back in the Desert save with mod param **Rename test (DEV)** = "Rename station group": build a **Train Station**,
   a **Bus/Tram Station**, an **Airport** (or airfield) and a **Harbour** in the town Seattle (or whichever town).
   Each gets `rename queued … -> "King Street"` etc. and `rename #n verify (wanted "King Street"): group … | station
   …`. Note what the station window and line manager show: "King Street" or "King Street Station"? Also note each
   building's default name in its `NEW … group` line before the rename.
5. Optional: map editor, new map with the probe set, place a town: is there a `names ctx towns` line with
   `isMapEditor=true`?
6. Optional (old PROBE.md steps 4-5): a two-sided stop, a stop right next to an existing one, a stop outside towns.

Paste the `[SQTSN_PROBE]` lines. Outcome → this plan: climate route for `townsFn` (or option C), station
naming form, town order vs size, findings.md entry.

### Phase 1: shared runtime + Washington playable

- Scope: `templates/state_names/` (runtime + tests), `tools/gen_state_mod.py` (+ Makefile targets
  `state-mod`, `state-mods`), `tools/state_towns.py` (Census draft; the downloaded Census files go to
  `.cache/census/<file>/`, read with `python -I`), `data/states/us_washington/` (≥ 400 tagged towns, ~120 generic
  streets, ≥ 15 cities with streets, stations for the major ones), generated `mods/square_names_us_washington/`
  and `tests/square_names_us_washington/`. Climate route per Probe 3.
- Not in scope: cover, flag, final description wording, edge cases below.
- Done: `make state-mods ARGS=--check` clean; `make check MOD=mods/square_names_us_washington`,
  `make test MOD=…`, `make validate MOD=…` pass (validate may warn about the missing cover). Tests cover: town
  sampling per climate (no duplicates, pool sizes, big towns present), unknown climate fallback, street pick with
  names in use and exhaustion suffixes, station pick by kind, name normalization (case, spaces, accents), the GS
  flow with a fake world (queue in the event, rename only from update, map editor no-op, unknown town no-op,
  player-renamed group skipped), and the data lint.
- User tests in game: (1) new game, Temperate, set "Washington (Towns & Streets)": towns are west-side names;
  (2) new game, Desert: east-side names; (3) in Seattle/Tacoma build 5 Road Stops: real streets, no repeats;
  (4) a stop in a non-city town: generic Washington street; (5) a train station and an airport in Seattle: real
  names; (6) load an existing save with another name set, add the mod: nothing changes until you build; rename a
  town to "Seattle", build a stop: Pike Street; (7) remove the mod from that save: names stay, no errors.

**Status (2026-10-08): implemented, offline green.**
- Files: `templates/state_names/` (content: `sn_logic.lua`, `names.script.lua`, `rename.script.lua`,
  `rename.gs.lua`, `mod.script.lua`; `tests/test_{logic,names,rename,data}.lua`; `description.html.tmpl`),
  `tools/gen_state_mod.py`, `tools/state_towns.py`, Makefile targets `state-towns`, `state-mod`, `state-mods`,
  `data/states/us_washington/{state.lua, towns_config.json, towns.tsv, streets.lua, cities.lua}`, generated
  `mods/square_names_us_washington/` and `tests/square_names_us_washington/`. Review list: `data_review.md`.
- Data: 520 towns (281 incorporated, 2023 estimates; 239 CDPs, 2010 counts) from Census files in `.cache/census/`;
  tags west 345 / east 175 / coast 63 / islands 19 / mountain 39 / north 28 / big 15. 132 generic streets.
  24 cities with street lists (374 streets), 13 with neighbourhoods (120), rail names in 9 cities (33), airports
  in 12 (14), harbours in 4 (7).
- Generator: data lint + render; `--check` reports stale/extra files; re-running gives no diff. `mod.json` params
  are ComboBox On/Off with `numbers` 1.0/0.0 (index 2 or number 0 = Off). Everything lives under paths with the
  modId (`content/<modId>/`, `content/names/<modId>/us_washington.names.lua`), incl. the runFn
  (`<modId>::/<modId>/mod.script@runFn`).
- Probe 3 points (isolated, defaults in place):
  1. Climate route **(answered, Phase 2)**: `names.script.lua` `currentClimate()` reads the runFn global
     (`SQUARE_NAMES_US_WASHINGTON_RUNFN`, written with `rawset` by `mod.script.lua`), then `sn_shared.lua`, then
     `getConfigDict()` (nil in that state today), else no climate. Option C regional sets stay off
     (`emitRegionalSets = false` in `state.lua`; generator emits `<key>_<region>.names.lua` when true).
  2. Station suffix: `sn_logic.STATION_SUFFIX` (TODO Probe 3 step 4); rail names stored without "Station",
     airports/harbours full names. Per-state override `stationSuffix` in `state.lua`.
  3. Town order vs size **(answered)**: sizes are random relative to name order; `BIG_FIRST` stays as a harmless
     stable order and is not claimed anywhere.
- Choices beyond the plan: guaranteed big towns are only those with the climate's top-weighted tag, at most half
  the requested towns (top 3 always, the rest at random) so small maps vary; station names are unique map-wide,
  street names per town; construction stations are only renamed when the build removes no construction (upgrades
  skipped) and the station has a passenger terminal (cargo skipped); helipads skipped; rename runs >= 1 s after
  the build so the engine's own name is in place.

### Phase 2: edge cases

- Scope (runtime + tests only, regenerated mod): two-sided stops (one group, maybe two stations); a stop joining an
  existing group (never rename the old group); the player renames a stop or town between build and rename (skip),
  or renames a town to/from a city name (lookup uses the current name); stops outside towns (no-op); bulldoze and
  rebuild (the freed real name is reused first); many stops in one build or in quick succession (one pass, names
  in use updated as they're assigned, no repeats); the map editor; two state mods active (owner rule); towns whose
  default pool already contains a city street (compare without suffix).
- Done: new unit tests for each case; `make check/test/validate` clean; a short `TESTING.md` in
  `plans/square_state_names/` with the in-game checklist.
- User tests in game: the TESTING.md checklist (each item one build and a look at the name).

**Status (2026-10-08): implemented, offline green** (66 tests: 24 new in `test_rename.lua` second half and
`test_names.lua`). Files: `templates/state_names/content/{rename.script.lua, mod.script.lua, names.script.lua,
sn_logic.lua (comments), sn_shared.lua (new)}`, `templates/state_names/tests/{test_rename.lua, test_names.lua}`,
`tools/gen_state_mod.py` (copies `sn_shared.lua`), regenerated Washington. In-game checklist: `TESTING.md` Phase 2.
Behaviour decisions:
- **New vs existing stop**: a stop the proposal only re-creates (road upgrade, edge split next to a new build) is
  never queued: `new2oldEdgeObjects` has an entry for its placeholder (`-400000000 + i - 1`, as base `town_util.tl`)
  or its real id, or `old2newEdgeObjects` lists it. Without this a player-renamed stop on an upgraded road would
  be renamed.
- **Joined groups**: a group is only renamed when every station in it is still queued (any build in the pending
  window, not just the same build). So a stop joining an older group is skipped, a new group that took over an old
  station is skipped, and two stops built a moment apart into one new group get one name. Two-sided stops (one
  station, or two stations in one group from one build) get one command.
- **Player renames**: the group's name at the build is stored; any change before the rename (player or another
  state mod renaming first) skips it. Player names count as used names afterwards.
- **Town**: looked up by its current name at rename time; a town that's gone or no town = no-op.
- **Queue**: entries become due 1 s after their build and are processed then; younger ones stay queued (no
  starvation while building fast, cap 64). Each station id is queued once. Bulldozed or reused ids fail the
  exists/group/name checks and are dropped; the due part of the queue is always dropped, even on error.
- **No repeats**: names given in a pass are added to the in-use sets at once (also when the default already equals
  the pick, which sends no command); names sent but not yet applied by the engine are remembered per group for
  30 s in the update's Lua state (session-only) so the next pass can't hand them out again.
- **Default-name collisions**: in-use names are compared without the engine's suffixes; station names map-wide
  ("King Street Station" in another town blocks "King Street").
- **Save/load**: the saved state is `{v, q, b}` with plain numbers/strings; a queue saved mid-delay is finished on
  the first update after load with all the same checks (the builds happened); old/broken state is reset.
- **Map editor**: never subscribes, never processes a loaded queue, never writes state.
- **Several state mods**: unchanged owner rule (`isActive`), incl. regional set paths of the owning mod.

### Phase 3: release prep for Washington

- Scope: `tools/fetch_flags.py` + `tools/sanitize_svg.py`; `branding/flags/us_washington.svg` + `SOURCES.json`
  (licence checked, seal question answered, U6); `Square.stateCover` in `cover.js`, the Washington entry in `mods.js`,
  README palette row and a "State series" section; `make covers MOD=mods/square_names_us_washington`; gallery
  slides (stops with real names in Seattle, the name-set picker, a station window) via `branding/shots.js` +
  `make shots`; final `description.html` with Changelog (revision 1); data review pass (spelling, only real
  streets, OSM spot check per city).
- Done: `make validate MOD=mods/square_names_us_washington` with no warnings; `make state-mods ARGS=--check` clean;
  cover and slides look right in `branding/index.html`.
- User: final in-game smoke test, then upload via Mod Hub → My Mods (the user does the upload).

**Status (2026-10-08): release prep done except slides, data review and the upload.**
- Flags: `tools/fetch_flags.py` (`make flags`) + `tools/sanitize_svg.py`; `branding/flags/{SOURCES.json, us_washington.svg}`
  (Commons, Public domain, WA Secretary of State, sha1 pinned). Seal question skipped per user decision.
- Cover: `Square.stateCover` in `cover.js` (hooks `titleLines` + `overlay` added to `render`); final numbers differ
  from the spec above: sticker 680 px at (1390, 625), -7°, 120 px peel, so it clears the two-line title; street sign
  blade top right above the sticker. Rules in `branding/README.md` "State series". `render.html` pins the SVG with
  `position: fixed` (the sticker's shadow made the page scroll by ~65 px).
- Description: template rewritten; all counts from data (`gen_state_mod.description`, new placeholders); climate
  wording left out until Probe 3 (TODO in the generator). State-specific notes via `notes` in `state.lua`.
- Open: gallery slides (need captures), OSM spot check of the city lists, changelog date in `state.lua`
  (`"unreleased"` → upload date).

### Phase 4 (later): next state

**Status (2026-10-08):** the generator has been generalised for more states (NEXT_STATES.md Phase 0; `HANDOFF.md`).
New config fields include `regions` / `countyTags` / `asciiFallback` / per-state lint floors / description wording,
plus contested city keys (`data/contested.lua`). The 12-state rollout follows NEXT_STATES.md §9.

`data/states/us_oregon/` + `make state-mod STATE=us_oregon` + flag + cover. Any change needed to the templates goes
back into `templates/state_names` and is regenerated for every state (each mod bumps its own `revision` and
changelog when its generated files change).

## Risks

- Probe 3 may show that name scripts see neither the config dict nor the runFn global: fall back to regional sets
  (C), which is less automatic.
- Construction-station names may need "Station" handling per kind (Probe 3 step 4).
- The street/station lists are only as good as the review: wrong or made-up street names are the most visible
  failure. OSM spot checks are part of Phase 3.
- A name-set path or modId change after release breaks saves that use the set.
- Flag/seal use rules differ per state; check each before release.
- Cross-mod conflicts for duplicate city names (Portland, Springfield, Vancouver): the bigger city wins via `data/contested.lua` (G9, Phase 0).

## User decisions (2026-10-08)
- Series scheme: modId `square_names_us_<state>`, mod "<State> Towns & Streets", name set "<State> (Towns & Streets)".
- Real station names: param **On** by default.
- Flags: use the real state flags as-is; no legal check (user's call). Skip the seal-rule research.
