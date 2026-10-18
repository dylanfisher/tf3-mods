# US State Names series: plan

One mod per US state, Washington first. Each mod gives a new game **real towns of that state (chosen by the map's
climate)**, gives **known cities their real streets** for new bus stops (Seattle → "Pike Street"), and gives new
**train stations, airports, harbours and bus/tram stations real names** ("King Street Station", "Paine Field",
"Colman Dock", "Capitol Hill"). Everything else the engine names after towns (industries, their stations, depots)
picks up the real town names by itself.

Research and citations: `research.md`. Supersedes `plans/square_town_street_names/PLAN.md` (its probe,
`mods/square_town_street_names_probe`, stays the shared dev probe).

Status: all 13 state mods are published on mod.io; each is at revision 6 (2026-10-10) in the repo (`make modio-status`
tells whether rev 6 is live). The 12-state rollout finished 2026-10-08; no further state is planned. Open: the
in-game checklist (`TESTING.md`), the station-suffix question, the font check for non-ASCII names, and the
per-state review items in `data_review.md`. Docs tidied 2026-10-12: finished phases, the rollout plan and the
per-state rollout notes are in `HISTORY.md`.

## Shipped

Generated from `templates/state_names/` + `data/states/<key>/` by `tools/gen_state_mod.py`; every state carries the
same revision history (changelog entries live in each `state.lua`).

- **Rev 1 (2026-10-08):** Washington plus the 12 rollout states (Arizona, Florida, Colorado, California, Texas, Alaska,
  New York, Minnesota, New Mexico, Oregon, Pennsylvania, Hawaii).
- **Rev 2 (2026-10-08):** less work per build and per frame (`history/PERF_REVIEW.md` P1-P6).
- **Rev 3 (2026-10-08):** map-editor check cached (`history/PERF_REVIEW.md` P7).
- **Rev 4 (2026-10-09):** clearer description, SQPERF log, second gallery slide.
- **Rev 5 (2026-10-10):** translations into the 12 other game languages (they live in the generator: CLAUDE.md "Translations").
- **Rev 6 (2026-10-10):** `severityRemove: Critical`: a game started with the name set crashes without the mod at the
  next new name (`docs/findings/towns.md`).

## Open work

1. **In-game checklist** `TESTING.md` (Phase 1, Phase 2, rev 3 checks): nothing is ticked yet. Evidence so far is
   listed at the top of that file.
2. **Station suffix** (Probe 3 step 4, TESTING Phase 1 item 5): `sn_logic.STATION_SUFFIX` is still `""` for every kind
   with a TODO. In game, a rail group was renamed "Seattle Station" -> "King Street" (session
   `2026-10-09_0044_sqrl-crash`); whether the station window then reads "King Street" or "King Street Station" is
   not recorded.
3. **Font check** for non-ASCII names (NEXT_STATES.md G4): until it passes, every state keeps `asciiFallback = true`.
4. **Data review:** `data_review.md` lists left-out and spot-check entries per state.
5. Any template change: regenerate all 13 (`make state-mods`, `--check` clean), bump every `revision` and add a
   changelog entry in each `state.lua` (Phase 4 rule below).
6. A new state: `NEXT_STATES.md` §5 checklist + `HANDOFF.md` workflow.

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

- `severityAdd: None`, `severityRemove: Critical` (2026-10-10: a save whose name set is gone crashes on the next new name), `cosmetic: true` (the probe with a name set and game script kept
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

## Runtime behaviour (decided in Phases 1-2)

From Phase 1:

- Choices beyond the plan: guaranteed big towns are only those with the climate's top-weighted tag, at most half
  the requested towns (top 3 always, the rest at random) so small maps vary; station names are unique map-wide,
  street names per town; construction stations are only renamed when the build removes no construction (upgrades
  skipped) and the station has a passenger terminal (cargo skipped); helipads skipped; rename runs >= 1 s after
  the build so the engine's own name is in place.

From Phase 2, behaviour decisions:

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

## Phases (summary)

Detail moved to `HISTORY.md` ("2026-10-12: moved from PLAN.md").

- **Probe 3** (climate visibility, station names): answered except step 4 (station suffix, open work 2).
- **Phase 1** (shared runtime + Washington playable) and **Phase 2** (edge cases): done 2026-10-08, offline green;
  in-game run open (`TESTING.md`).
- **Phase 3** (release prep for Washington): done; Washington released 2026-10-08. The cover's final numbers differ
  from the "Cover" spec above: see `branding/README.md` "State series".
- **Phase 4** (next states): done as the 12-state rollout (`NEXT_STATES.md`, `HANDOFF.md`). Rule that still applies:
  any change to the templates goes back into `templates/state_names` and is regenerated for every state (each mod
  bumps its own `revision` and changelog when its generated files change).

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
