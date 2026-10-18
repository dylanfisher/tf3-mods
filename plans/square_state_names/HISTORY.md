# US State Names series: history

Finished phases, the rollout plan and per-state rollout notes, moved here verbatim (newest first). Read it only to
learn why something is the way it is; the current state is in `PLAN.md`.

## 2026-10-12: moved from PLAN.md (status, open user questions, draft description, phase detail; written 2026-10-08)

Old status line:

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
- Choices beyond the plan: kept in PLAN.md "Runtime behaviour".


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

(The behaviour decisions are kept in PLAN.md "Runtime behaviour".)


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

## 2026-10-12: moved from NEXT_STATES.md (rollout plan, written 2026-10-08)

Old header:

Written 2026-10-08, from `PLAN.md`, `research.md`, `TESTING.md`, `data_review.md`, the template/generator code, the
Census Gazetteer files (2010 national, cached in `.cache/census/`; 2023 per-state files for 11 candidates, fetched
for this count) and a mod.io slug survey. Nothing here is built yet. Washington (`mods/square_names_us_washington`)
is the template.

**Status (2026-10-08):** Phase 0 (generator) done: G1, G2 (via the 2020 block assignment file, since there's no
rel2020 place-to-county file), G2b, G4, G5, G6, G9, G10 (no change needed). G7 dropped. Details, new fields and the
per-state workflow: `HANDOFF.md` "Phase 0 (generator)". Next: Arizona.

**Arizona (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_arizona`). 275 towns, 13
street cities / 316 streets (Overpass-checked), 38 neighbourhoods, 3 rail, 14 airports, no harbours; open items in
`data_review.md` "## Arizona"; notes in `HANDOFF.md` "## Arizona". In-game test pending (user). Next: Florida.

**Florida (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_florida`). 479 towns, 13
street cities / 336 streets (Overpass-checked), 63 neighbourhoods, 15 rail, 14 airports, 5 ports; open items in
`data_review.md` "## Florida"; notes in `HANDOFF.md` "## Florida". In-game test pending (user). Next: Colorado.

**Colorado (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_colorado`). 334 towns, 12
street cities / 293 streets (Overpass-checked), 42 neighbourhoods, 20 rail, 5 airports, no harbours; open items in
`data_review.md` "## Colorado"; notes in `HANDOFF.md` "## Colorado". In-game test pending (user). Next: California.

**California (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_california`). 550 towns, 13
street cities / 360 streets (Overpass-checked), 92 neighbourhoods, 79 rail, 17 airports, 9 ports; open items in
`data_review.md` "## California"; notes in `HANDOFF.md` "## California". In-game test pending (user). Next: Texas.

**Texas (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_texas`). 533 towns, 13 street
cities / 367 streets (Overpass-checked), 88 neighbourhoods, 54 rail, 28 airports, 9 ports; Pasadena contested (Texas
wins, California's `contested.lua` regenerated); new `incMinPop`/`keepTown` town filters; open items in
`data_review.md` "## Texas"; notes in `HANDOFF.md` "## Texas". In-game test pending (user). Next: Alaska.

**Alaska (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_alaska`). 282 towns, 9
street cities / 250 streets (Overpass-checked), 28 neighbourhoods (Anchorage), 3 rail, 31 airports, 14 ferry terminals;
thin by design (D7, description says so); open items in `data_review.md` "## Alaska"; notes in `HANDOFF.md` "## Alaska".
In-game test pending (user). Next: New York.

**New York (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_new_york`). 541 towns, 13
street cities / 382 streets (Overpass-checked), 177 neighbourhoods (NYC, Buffalo, Rochester, Syracuse, Albany), 52 rail,
39 airports, 11 harbours; no dry region (whole state); new per-region `cdpMinPop`; open items in `data_review.md`
"## New York"; notes in `HANDOFF.md` "## New York". In-game test pending (user). Next: Minnesota.

**Minnesota (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_minnesota`). 485 towns, 12
street cities / 329 streets (Overpass-checked), 96 neighbourhoods (Minneapolis, St. Paul, Duluth), 11 rail, 38 airports,
no harbours; 2024 flag (PD); Rochester and Austin contested (NY/TX win); open items in `data_review.md` "## Minnesota";
notes in `HANDOFF.md` "## Minnesota". In-game test pending (user). Next: New Mexico.

**New Mexico (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_new_mexico`). 278 towns, 12
street cities / 401 streets (Overpass-checked), 50 neighbourhoods (Albuquerque, Santa Fe), 9 rail, 26 airports, no
harbours; tropical stand-in = desert + Rio Grande valley; open items in `data_review.md` "## New Mexico"; notes in
`HANDOFF.md` "## New Mexico". In-game test pending (user). Next: Oregon.

**Oregon (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_oregon`). 357 towns, 12 street
cities / 342 streets (Overpass-checked), 95 neighbourhoods (Portland, Eugene, Salem, Bend), 40 rail (Amtrak, WES, MAX),
41 airports, no harbours; Albany/Aurora/Ontario/Redmond contested (NY/CO/CA/WA win); open items in `data_review.md`
"## Oregon"; notes in `HANDOFF.md` "## Oregon". In-game test pending (user). Next: Pennsylvania.

**Pennsylvania (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_pennsylvania`). 488 towns,
13 street cities / 372 streets (Overpass-checked), 109 neighbourhoods (Philadelphia, Pittsburgh), 58 rail (Amtrak, SEPTA,
PRT, Steamtown), 49 airports, 2 ferry landings; no dry region (whole state); no contested keys; open items in
`data_review.md` "## Pennsylvania"; notes in `HANDOFF.md` "## Pennsylvania". In-game test pending (user). Next: Hawaii.

**Hawaii (2026-10-08):** data + mod + checks + flag + cover done (`mods/square_names_us_hawaii`). 131 towns (all CDPs),
13 street cities / 299 streets (Overpass-checked), 51 neighbourhoods (Honolulu, East Honolulu), 11 rail (Skyline), 14
airports, 4 harbours; thin by design; new `renameGeoid` (Kailua-Kona) and `introTowns`; open items in `data_review.md`
"## Hawaii"; notes in `HANDOFF.md` "## Hawaii". All 13 state mods re-verified (check/test/validate). In-game test
pending (user). Rollout complete.

## 1. Ranked shortlist

Scores are 1–5. **Total = 2×appeal + 2×data + climate + flag + overlap**, where overlap 5 = few shared city names. Town
counts are an estimate: 2010 incorporated places + CDPs with ≥ 300 people, without hyphens. The 2023 place counts are
higher because 2020 added CDPs, but CDPs new since 2010 have no free population figure (G7).

| # | State | FIPS | Appeal | Data | Climate | Flag | Overlap | Total | Towns (est.) | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | California | 06 | 5 | 5 | 5 | 5 | 3 | **33** | ~1,250 | LA/SF/SD, Union Station, Caltrain, BART, cable cars. Has all four climates: coast temperate, deserts and Central Valley dry, Sierra subarctic, SoCal coast and Channel Islands tropical. Bear flag reads instantly. Most region work of any state |
| 2 | Texas | 48 | 5 | 5 | 4 | 5 | 3 | **32** | ~1,525 | Houston/Dallas/Austin/San Antonio/El Paso. East is humid temperate, west dry, Gulf and Rio Grande Valley pass for tropical, no real subarctic. Lone Star is the best sticker. Non-ASCII CDPs (César Chávez, Salineño) |
| 3 | Arizona | 04 | 4 | 4 | 5 | 5 | 4 | **30** | ~310–340 | The dry showcase, plus high country (Flagstaff, Prescott) for temperate. Amtrak (Flagstaff, Winslow, Tucson, Yuma), Valley Metro, Grand Canyon Railway. Almost no harbours. Copper-star flag is excellent at thumbnail size |
| 4 | Florida | 12 | 5 | 5 | 4 | 3 | 3 | **30** | ~870 | The tropical showcase. Miami/Orlando/Tampa/Jacksonville. Brightline, Tri-Rail, Metrorail, SunRail, Amtrak. Ports and the Keys. Flag: red saltire with a small seal, reads like Alabama's |
| 5 | Colorado | 08 | 4 | 4 | 4 | 5 | 3 | **28** | ~360–400 | Rail heritage: Denver Union Station, Durango & Silverton, Georgetown Loop, Moffat Tunnel. Mountains = subarctic, plains = dry, Front Range = temperate, no tropical. The "C" flag is iconic. Overlaps: Aurora, Lakewood, Louisville, Westminster |
| 6 | Alaska | 02 | 4 | 2 | 5 | 5 | 5 | **27** | ~225 (all 355 places at a low CDP floor) | The natural subarctic state. Alaska Railroad, Marine Highway ferries, many airports. Only about 3–5 cities have well-known streets (fails the 10-city bar). Exposes the most generator gaps (G1–G6) |
| 7 | New York | 36 | 5 | 4 | 3 | 2 | 3 | **26** | ~1,140 | NYC subway, Grand Central, Penn Station. Temperate, Adirondacks as subarctic, Long Island coast as tropical, no dry. Blue seal flag reads as a blue rectangle |
| 8 | Minnesota | 27 | 3 | 4 | 4 | 4 | 3 | **25** | ~875 | Great Northern and the Duluth ore docks. Arrowhead = subarctic, south = temperate, western prairie = weak dry. New simple flag (2024): check its Commons licence |
| 9 | New Mexico | 35 | 2 | 3 | 5 | 5 | 4 | **24** | ~290 | Dry/high desert. Rail Runner, Amtrak (Lamy, Albuquerque, Gallup), Cumbres & Toltec. Only ~4 cities have well-known streets (Albuquerque, Santa Fe, Las Cruces, Roswell). Zia flag is perfect. Eight non-ASCII CDPs (Doña Ana, Peñasco …) |
| 10 | Oregon | 41 | 3 | 4 | 4 | 2 | 3 | **23** | ~325–370 | Same Cascade-crest split as WA: zero template risk and cross-sells with WA, but no new climate. Portland Union Station, MAX, Amtrak Cascades. Navy/gold seal flag with text, two different sides. Overlaps: Portland (ME), Salem, Springfield, Albany, Dallas |
| 11 | Pennsylvania | 42 | 4 | 4 | 2 | 2 | 3 | 23 | ~1,640 | PRR, Horseshoe Curve, 30th Street, Steamtown. Temperate only. Seal flag. Has "municipality" LSAD places |
| 12 | Hawaii | 15 | 3 | 1 | 4 | 4 | 5 | 21 | ~140 (0 incorporated) | Tropical only, ~160 CDPs, no "big" tier (G5), Skyline as the only rail. Census names are ASCII (2023 file checked); ʻokina only in hand lists (G4). Defer |

("Existing mod.io name sets" and "Overlap between our own state mods" stay in NEXT_STATES.md.)

## 2. First batch: Arizona, Florida, Colorado

| State | Climate it proves | Template gaps it flushes out |
|---|---|---|
| **Arizona** | **dry** as the main climate (WA only had dry as its east side) | The region boundary isn't a north–south crest (G1), the zero-harbour description (G6), the ~330-town floor (G5) |
| **Florida** | **tropical** as the main climate | A latitude split plus a coast/Keys tag by county (G1, G2), no dry region (fallback path), the biggest data load of the batch (~870 towns) |
| **Colorado** | **subarctic** via the mountains | Three-way polygon regions (G1), no tropical (fallback), shared city names with WA/IL/KY (G9) |

Why not California or Texas first: they score highest, but they're the biggest data jobs and need every generator
fix. Doing the three mid-size states first makes CA and TX **pure data work** (batch 2). Why Colorado over Alaska for
subarctic: Colorado clears every data bar (10+ street cities, 300+ towns, rail), while Alaska fails the street bar
and is mostly a gap test. Alaska follows in batch 2 as a deliberately small mod, once the generator fixes are in.

**Batch 2:** California, Texas, Alaska. **Batch 3:** New York, Minnesota, New Mexico (or Oregon as a quick WA
companion whenever there's a gap in the schedule).

## 3. Per-state data recipes (batch 1, plus CA/TX/AK sketches)

Every recipe: `towns_config.json` (`fips`, `postal`, `gazetteerYear` 2023, `popestYear` 2023, `bigCount` 15, region
rules), `streets.lua` (~120 generic names in the state's style), `cities.lua`, and `state.lua` (climate weights,
`notes`, accent). Region tags use the new `regions` / `countyTags` config (G1, G2). Every boundary below is a draft
polygon to be checked on a map (geojson.io paste) before the tags are reviewed.

**Verification sources for all states:** every street must exist as a `highway=*` way inside the city boundary
(Overpass query per city, as research.md §5.4). Rail station names come from the operator's official station list
(Amtrak station pages, the transit agency's map/GTFS `stops.txt`). Airports use the FAA name (5010 data / the airport's
own site), in the short common form. Ferry terminals use the operator's terminal list. Neighbourhoods use the city's
official neighbourhood map. A name without a source link goes to the state's `data_review.md` section.

### Arizona (`us_arizona`, FIPS 04, AZ)

- **Regions:** `desert` (default: low and Sonoran desert) vs `high` (a polygon around the Colorado Plateau and
  central highlands, i.e. the Mogollon Rim and everything north/east of it). Draft line, south edge of `high`: (35.2,
  -114.1) Kingman → (34.55, -112.9) south of Prescott → (34.2, -111.7) → (34.05, -111.2) Payson → (33.9, -110.0) →
  (33.6, -109.05) NM border. Plus `river` from a list (Colorado River: Lake Havasu City, Bullhead City, Parker,
  Ehrenberg, Yuma, Page, Quartzsite?) and `sky` for the southeast high grassland (Sierra Vista, Bisbee, Willcox,
  Patagonia), drawn as a polygon.
- **Climate weights:** dry {desert 75, sky 10, high 15}; temperate {high 70, sky 30, desert 0}; subarctic {high 100,
  desert 0}; tropical {river 50, desert 50}. Lint: each pool (with top-ups) ≥ the state's `minPool` (G5).
- **Cities with streets (≥10):** Phoenix, Tucson, Mesa, Chandler, Scottsdale, Tempe, Glendale, Gilbert, Peoria,
  Flagstaff, Yuma, Prescott, Sedona.
- **Neighbourhoods:** Phoenix (urban villages), Tucson, Tempe, Scottsdale.
- **Rail:** Amtrak (Flagstaff, Williams Junction, Winslow, Kingman, Tucson, Benson, Maricopa, Yuma), Valley Metro
  light rail names (follow the series policy on light rail, decision D5), Grand Canyon Railway (Williams Depot,
  Grand Canyon Depot), Tucson's Sun Link.
- **Airports:** Phoenix Sky Harbor, Mesa Gateway, Tucson International, Flagstaff Pulliam, Yuma International, Grand
  Canyon National Park Airport.
- **Harbours:** practically none. The Lake Havasu passenger boats aren't a known terminal name, so leave the list
  empty and let G6 drop the sentence.
- **Generic street flavour:** saguaro, mesquite, palo verde, ocotillo, mountain ranges (Camelback, Superstition,
  Catalina), canals, "Indian School Road" style section-line roads. All generic, none tied to a real town.

### Florida (`us_florida`, FIPS 12, FL)

- **Regions:** `panhandle` (lon < -83.6, lat > 29.6: Pensacola, Tallahassee, Panama City), `north` (lat ≥ 29.0, not
  panhandle: Jacksonville, Gainesville, St. Augustine, Ocala), `central` (27.0 ≤ lat < 29.0: Orlando, Tampa, Lakeland,
  Daytona), `south` (lat < 27.0). `keys` = Monroe County, by `countyTags`. `coast` = coastal counties by
  `countyTags` minus inland places, or a barrier-island list (Miami Beach, Palm Beach, Sanibel …).
- **Climate weights:** tropical {south 55, keys 15, central 30, north 0}; temperate {north 45, panhandle 40, central 15};
  subarctic {panhandle 50, north 50}, for which Florida is the least-bad fit; dry: leave it out (whole state, G3
  fallback). Florida has no desert, and that is the honest answer.
- **Cities with streets:** Miami, Miami Beach, Orlando, Tampa, St. Petersburg, Jacksonville, Tallahassee, Fort
  Lauderdale, West Palm Beach, Key West, Gainesville, Pensacola, Sarasota, St. Augustine.
- **Neighbourhoods:** Miami (Little Havana, Wynwood, Brickell, Coconut Grove …), Tampa (Ybor City …), Orlando,
  Jacksonville.
- **Rail:** Brightline (Miami, Aventura, Fort Lauderdale, Boca Raton, West Palm Beach, Orlando), Tri-Rail, Metrorail,
  SunRail, Amtrak (Jacksonville, Orlando, Tampa Union Station, Sebring …). Use each operator's official list. Where
  two operators name a stop differently, list one form only.
- **Airports:** MIA, FLL, PBI, MCO, TPA, JAX, Key West International, Tallahassee International: FAA names, short form.
- **Harbours:** PortMiami, Port Everglades, Port Canaveral, Key West ferry terminal. Check each against the port's own
  terminal naming. Cruise "Terminal A" style names stay out.

### Colorado (`us_colorado`, FIPS 08, CO)

- **Regions:** `front` (a polygon around the Front Range urban corridor, from Fort Collins to Pueblo along roughly
  -105.3…-104.6), `plains` (east of the corridor), `mountain` (a polygon from the Front Range foothills west to
  about -107.3, covering the Rockies, the San Juans and the San Luis Valley), `slope` (the Western Slope valleys west of
  that: Grand Junction, Montrose, Delta, Cortez, Durango).
- **Climate weights:** subarctic {mountain 80, slope 20, front 0}; dry {plains 50, slope 30, front 20}; temperate {front
  60, mountain 20, slope 20}; tropical: none (whole state).
- **Cities with streets:** Denver, Colorado Springs, Aurora, Fort Collins, Boulder, Pueblo, Lakewood, Grand Junction,
  Durango, Golden, Greeley, Aspen. Aspen and Durango are small, but players know them.
- **Neighbourhoods:** Denver (LoDo, Capitol Hill, Five Points, RiNo, Highlands, Cherry Creek …), Boulder.
- **Rail:** Denver Union Station, RTD commuter rail/light rail station names (D5), Amtrak (California Zephyr:
  Fraser-Winter Park, Glenwood Springs, Grand Junction; Southwest Chief: Trinidad, La Junta, Lamar), Durango &
  Silverton (Durango, Silverton), Georgetown Loop, Pikes Peak Cog Railway (Manitou Springs). No slash names.
- **Airports:** Denver International, Colorado Springs, Eagle County Regional, Aspen/Pitkin County (Sardy Field).
  If a name only exists in slash form, use a plain one-word form, and only if it's known (else `data_review`).
- **Harbours:** none (G6).

### Batch 2 sketches

- **California (06):** `countyTags` do most of the work: `north`/`bay`/`central_coast`/`socal` coastal counties,
  `valley` (Central Valley counties), `desert` (Imperial, Riverside east of the San Jacinto Mountains, San Bernardino
  desert part by polygon, Inyo), `sierra` polygon (elevation proxy: east of ~-120.5 between 36° and 40°), `islands`
  list (Avalon, …). dry {desert 50, valley 40, socal 10}, temperate {bay 35, north 25, central_coast 20, valley 20},
  subarctic {sierra 70, north 30}, tropical {socal 60, islands 10, central_coast 30}. 20+ street cities. Rail: LA
  Union Station, Caltrain, BART, Metrolink, Amtrak California, SF cable car lines (as rail? D5). Harbours: SF Ferry
  Building, Larkspur, Sausalito, Avalon, Long Beach.
- **Texas (48):** `east` / `west` split along the dry line (polyline near -98.5, curving to -100 in the north),
  `gulf` coastal counties (`countyTags`), `valley` (Cameron, Hidalgo, Starr, Willacy), `panhandle` (lat > 34.3). dry {west
  70, panhandle 30}, temperate {east 70, panhandle 15, gulf 15}, tropical {gulf 50, valley 50}, subarctic {panhandle
  100, east 0}. 15+ street cities. Rail: Houston and Dallas Union Stations, Fort Worth Central, DART, TEXRail. Harbours:
  Galveston–Port Bolivar ferry, Port Aransas ferry.
- **Alaska (02):** fix the LSAD names first (G2). `southcentral` polygon (Anchorage, Mat-Su, Kenai), `interior`
  (Fairbanks, the Yukon), `southeast` (lon > -141: Juneau, Sitka, Ketchikan), `arctic_west` (lon < -156 or lat > 66),
  `islands` (Kodiak, Aleutians East/West boroughs by `countyTags`). subarctic {interior 35, southcentral 35,
  arctic_west 30}, temperate {southeast 50, southcentral 50}, dry {interior 60, arctic_west 40}, tropical {southeast 50,
  islands 50}. `cdpMinPop` around 50, `minTowns` around 300 (G5). Streets: Anchorage, Fairbanks, Juneau,
  Ketchikan, Sitka, Wasilla, at most. Rail: the Alaska Railroad depots. Harbours: Marine Highway terminals. Airports:
  Ted Stevens Anchorage, Fairbanks International, Juneau International, plus bush airports by town name (default,
  nothing to do).

## 4. Template and generator gaps a new state exposes

Each fix goes into `templates/state_names/` or `tools/`, with a unit test. Afterwards `make state-towns
STATE=us_washington` and `make state-mod STATE=us_washington` must give **no diff for Washington** (regression gate).

| # | Gap | Hits | Fix |
|---|---|---|---|
| G1 | `state_towns.py` region tagging only knows `crest` (a west/east split by longitude-at-latitude) plus `lonLt`/`latGe` rules. It can't express the Mogollon Rim, Florida's bands, or Colorado's four regions | AZ, FL, CO, CA, TX, AK | Add `regions`: an ordered list of `{tag, polygon: [[lat, lon], …]}`, first match wins, plus `defaultTag`; point-in-polygon in the tool. Add `latLt` / `lonGe` to `rules`. Keep `crest` working (WA unchanged). Print per-tag counts and write a `regions.geojson` next to towns.tsv so the polygons can be checked on a map |
| G2 | No county information, so coast and island tags need long hand lists | FL keys/coast, CA, TX gulf, AK boroughs | Read the Census 2020 place-to-county relationship file (`tab20_place20_county20_natl.txt`, into `.cache/census/rel2020_place_county/`) and assign each place to the county with the largest land part. New config `countyTags: {"keys": ["Monroe"], …}` |
| G2b | `strip_lsad` suffixes are only city/town/CDP/village/borough. "Juneau city and borough" becomes "Juneau city and" (**bug**). "Anchorage municipality" keeps its suffix. "(balance)", "unified/consolidated/metro government" and "urban county" aren't handled | AK (3 + Anchorage), PA (3 municipalities), GA, KY, TN, IN, MT | Longest-first suffix list incl. " city and borough", " municipality". Strip " (balance)". Consolidated governments go through `rename` ("Athens-Clarke County unified government (balance)" → "Athens"). Warn on any unknown suffix instead of the silent "?" kind. Tests with these names |
| G3 | States without a natural fit for one of the four climates | FL dry, CO/AZ tropical, TX subarctic | Already works (a missing climate = whole state). Document it in `state.lua` and have the description's climate sentence list only the mapped climates |
| G4 | Non-ASCII names. `sn_logic.normalize` folds only 2-byte Latin-1 (`\195`). ġ (Utqiaġvik, U+0121), Hawaiian ā/ō (U+0101/014D) and ʻokina (U+02BB) don't fold, so "Utqiaġvik" never matches a town the player typed as "Utqiagvik". **Unknown whether the game's town-label/HUD font has ñ, ġ, ʻ** (memory: the HUD font lacks ▲) | NM (8 CDPs), TX (4), CA (2), CO (Cañon City), AK (Utqiaġvik), HI (hand lists) | Extend FOLD to Latin Extended-A (`\196`, `\197`). Drop U+02BB and U+2018 like apostrophes. Add `TESTING.md` item: rename a town to "Cañon City" and to "Utqiaġvik", build a stop there, screenshot the label. Add `asciiFallback = true` in `state.lua`: the generator transliterates names (Cañon → Canon) if the font check fails. Ship Census spelling otherwise |
| G5 | `MIN_TOWNS = 400` and `MIN_POOL = 150` are constants. "big" only counts incorporated places | AZ (~330), NM, OR, AK, HI (0 incorporated) | Per-state `minTowns` / `minPool` in `state.lua`, with a comment saying why. `bigIncludesCdp` in `towns_config.json` (HI's "Urban Honolulu" via `rename` → "Honolulu") |
| G6 | `description.html.tmpl` hard-codes "ferry docks", "farm and harbour towns", "{{HARBOR_COUNT}} ferry terminals and docks" and the WA street flavour "(numbered avenues, trees, mountains, rivers and counties)". With zero harbours you get "0 ferry terminals" | AZ, CO, NM, inland states | The generator builds the station sentence from the non-empty kinds only. New `state.lua` fields: `harborWord` ("ferry terminals" / "ports" / "harbours"), `streetFlavour`, `townFlavour`. Climate sentence from a new `regionLabels` map (`desert = "the low desert"`). This also clears the generator's climate TODO now that Probe 3 is answered |
| G7 | CDP populations are 2010 only. CDPs created in 2020 have population 0 and need `keepCdp` by hand. The keyless 2020 PL API call returned "Missing Key" (`.cache/census/dec2020_pl_53/places.json` is an error page) | FL, AZ, TX (many new CDPs) | Optional `CENSUS_API_KEY` in `.hub.env`. With a key, `--fetch` gets 2020 P1 totals for CDPs. Without one, keep 2010 plus `keepCdp`. Delete the stale error page |
| G8 | Station suffix not settled (Probe 3 step 4) | all | Answered by Washington's TESTING Phase 1 item 5. Rail data is already stored without "Station", so the data format doesn't change |
| G9 | Shared city keys between series mods when a non-series set is active (§1) | OR/ME, CO/IL, AZ/CA, TX/VA, … | Generator: `contested.lua` per mod (key → winning modId by population). Runtime: skip if the winner is active. Optional, decision D4 |
| G10 | Long state names on the cover and in the picker: "Pennsylvania Towns & Streets", "North Carolina (Towns & Streets)" | PA, MA, NC, SC, … (not batch 1) | Render a dummy `Square.stateCover` for the longest name now and check `titleLines`. Picker label length checked in game once |
| G11 | `accent` must stay distinct from existing mods. Many flags are red or blue | all | Pick the flag's secondary colour when the main one is taken (AZ copper `#C4622D`, FL red `#C8102E`, CO blue `#002868`?). Check against the README palette table |
| G12 | Light rail vs mainline in `rail` (the open WA review item) | AZ, CO, CA, TX, FL | Decide once for the series (D5) and write it into the `cities.lua` header comment |

## 6. Phases (one subagent per phase or state; the main session orchestrates)

**Phase 0: generator generalisation (one subagent).**
*Status: done 2026-10-08 (see `HANDOFF.md`).*
- Scope: G1, G2, G2b, G4 (fold + `asciiFallback` plumbing), G5, G6, G7 (optional key path), G9 if D4 = yes, G10 dry
  render. Tests for every fix (Python: unit tests for `state_towns.py` region/LSAD/county code under `tests/`; Lua:
  `test_logic.lua` normalize cases for ñ, ġ, ʻ).
- Done:
  - `make state-towns STATE=us_washington` and `make state-mods ARGS=--check` give no diff.
  - `make check/test/validate MOD=mods/square_names_us_washington` pass.
  - A throwaway config for Alaska drafts towns without unknown-suffix warnings ("Juneau", "Anchorage" present).
  - The description renders with zero harbours.

**Phases 1–3: one subagent per state (Arizona, Florida, Colorado). They can run in parallel after Phase 0.**
- Scope: checklist steps 1–7 for that state, data under `data/states/<key>/`, a review section in `data_review.md`.
  Template changes go back to the main session as a request; a state subagent never edits `templates/` or `tools/`.
- Done:
  - checklist steps 1–7 ticked
  - every climate pool ≥ `minPool`
  - ≥ 300 towns (or a waived `minTowns`)
  - ≥ 10 street cities with every street verified on Overpass (the query log in `plans/square_state_names/states/<key>.md`)
  - station names with source links
  - `make state-mods ARGS=--check` clean
  - cover rendered.

**Phase 4: in-game round (user), then fixes (one subagent).**
- The user runs checklist step 8 for all three states in one session.
- The subagent turns the results into fixes and `docs/findings.md` entries (font coverage, climate routes per new
  climate).
- Done: all TESTING items ticked or logged as accepted limitations.

**Phase 5: slides and release (one subagent per state, or one for all three).**
- Checklist steps 9–10, with releases staggered (D3).

**Phase 6 onward: batch 2 (CA, TX, AK) and batch 3,** same pattern, Phase 0 only if a new gap shows up.

## 8. Decisions for you

| # | Decision | Recommendation |
|---|---|---|
| D1 | First batch | **Arizona, Florida, Colorado** (dry / tropical / subarctic-mountain). Alternative: swap Colorado for Alaska if a "real" subarctic state matters more than data depth |
| D2 | Naming | Keep the scheme: modId `square_names_us_<state>` with underscores for two-word states (`square_names_us_new_mexico`); "<State> Towns & Streets"; set "<State> (Towns & Streets)". Confirm the long-name forms (G10) |
| D3 | Release cadence | Washington first, alone. Then one state every 1–2 weeks rather than all three at once, so feedback can reach the template before the next. Every template change bumps every released state's revision |
| D4 | Contested city names (G9) | Build it in Phase 0 (cheap, deterministic, needs regenerating older mods), or keep the "accepted limitation" note |
| D5 | Light rail in `rail` lists | Mainline and commuter names first, then light rail (it reads fine for a player-built station). Or mainline only |
| D6 | Non-ASCII names | Ship Census spelling (Cañon City, Doña Ana, Utqiaġvik) if the font check passes, else transliterate |
| D7 | Alaska's lower bar | OK to ship a state with < 10 street cities and ~300 towns, as long as the description says so honestly? |
| D8 | Census API key | Get a free key for 2020 CDP populations (G7), or stay on 2010 + `keepCdp` |

## 2026-10-12: moved from HANDOFF.md (per-state rollout notes, written 2026-10-08)

Each state subagent appended its section (oldest first).

### Arizona

2026-10-08. 275 towns (big 15, desert 150, high 109, river 14, sky 16), 13 street cities / 316 streets (all
Overpass-checked), 38 neighbourhoods (Phoenix, Tucson, Scottsdale), 3 rail, 14 airports, 0 harbours, 129 generic
streets. Flag PD (Commons, pinned), cover rendered. All checks pass; Washington regenerated with no diff.

- **Tool change**: the description said "a Arizona city's name". New placeholder `{{A_STATE_NAME}}` ("a"/"an" by
  first letter) in `templates/state_names/description.html.tmpl` + `tools/gen_state_mod.py`, test in
  `tests/tools/test_state_names_tools.py`. Washington output unchanged.
- **Overpass**: one query per city with all candidates as one regex: `rel(area.s)[boundary=administrative]
  [admin_level=8][name=X]; map_to_area->.c; way(area.c)[highway][name~"^((North|South|East|West|N|S|E|W) )?(A|B|…)$"];
  out tags;`. Overpass regex is POSIX ERE: no `(?:…)` (HTTP 400). 13 cities took ~3 min. Then the server got busy
  (429/504, mirrors returned 500), so neighbourhoods came from official sources instead: the Phoenix urban villages
  are in `maps.phoenix.gov/pub/rest/services/public/Villages/MapServer/0/query?where=1%3D1&outFields=*&f=json`.
  Script: write a small Python verifier in the scratchpad (cand.json → found/missing per city); ~95 % of drafted
  streets hit, misses went to data_review.
- **Rail reality for Sun Belt states**: Amtrak stops are named after their town (= engine default, no entry) and
  Valley Metro / Sun Link stop names are all slash or "&" intersection names, so the rail list is tiny (Metro
  Parkway, Williams Depot, Grand Canyon Depot). Expect the same for other light rail systems with intersection names;
  airports carry the station bullet instead.
- **Towns**: AZ has many subdivision-style CDPs (Avenue B and C, Lazy Y U, Wall Lane, … Estates/Mobile Manor) and
  CDPs named after a bigger city (Goodyear Village, Maricopa Colony): exclude them. The drop-word filter hides real
  places (Sun City West, Drexel Heights) and hyphens hide Heber-Overgaard: grep the 2010 file
  (`.cache/census/gaz2010_places_extracted/gaz2010_<postal>.txt`) for CDPs ≥ 300 with a drop word or hyphen and
  `keepCdp` the real ones. `rename` handles a Census name with a parenthesis ("Village of Oak Creek (Big Park)").
- **Pools**: `minTowns 250, minPool 100, minStreetCities 10` (smallest pool: subarctic = high, 109).
- Accent = the flag's copper star `#CE5C17` (read the colour from the sanitized SVG). Title "Arizona" fits easily.
- Time sinks: Overpass rate limiting (pause 60 s+ or switch to official sources); `json.dumps(indent=2)` explodes
  polygons onto one line per number, which is valid but long.

### Florida

2026-10-08. 479 towns (big 15, central 179, south 143, north 87, panhandle 70, keys 11), 13 street cities / 336
streets (Overpass-checked), 63 neighbourhoods (Miami, Tampa, Orlando, Jacksonville), 15 rail, 14 airports, 5 ports,
137 generic streets. Flag PD (Commons, pinned, red saltire `#C60013` = accent), cover rendered. All checks pass;
Washington and Arizona regenerated with no diff. No template/tool changes.

- **Towns**: Florida keeps all ~410 incorporated places, so the CDP floor does the trimming: `cdpMinPop` 15000 gave
  479 (5000 gave 597). Then `keepCdp` for the Keys (Monroe CDPs are small) and beach towns. Miami-Dade CDPs are
  suburban tracts (Country Club, University, Lakeside, Kendale Lakes, …): exclude them. **Same-name shadowing**: a
  bigger CDP replaces a same-named town (Lake Butler CDP 15k beat the Union County town), so `excludeCdp` the CDP.
  `keepCdp` names that aren't 2023 CDPs just warn (Ponte Vedra Beach is inside "Palm Valley" CDP; Santa Rosa Beach,
  Boca Grande aren't CDPs).
- **OSM city names**: Overpass boundaries are "Saint Petersburg"/"Saint Augustine" (0 hits under "St."), and OSM
  street names spell out "Saint". The verifier's directional strip also eats "West Avenue". Miami's grid names
  (Coral Way = SW 22nd St, Calle Ocho = SW 8th St) don't hit; ship the numbered form.
- **Lint**: a name can't be both a street and a rail name in one city (Orlando's Church Street). Also keep rail
  names distinct from neighbourhood names (Metrorail Brickell vs Brickell) and from town names (Okeechobee).
- **Sources**: sunrail.com/stations (clean list). miamidade.gov's Metrorail page 404s; WebSearch summarised the
  county list (`transportation-publicworks/metrorail-stations.asp`). tri-rail.com and gobrightline.com don't render
  lists (403/JS); Tri-Rail destination pages per county + Wikipedia route map filled in.
- **Neighbourhood check**: Overpass `nwr(area.c)[place][name~…]` + `[boundary][name~…]` hit ~60 %; islands match too
  (Virginia Key), so read the hits.
- Time sinks: Overpass 504/429 on ~1 in 3 queries; the script retries 30 s then a mirror. 4 batches total (~6 min).

### Colorado

2026-10-08. 334 towns (big 15, front 106, mountain 103, plains 83, slope 42), 12 street cities / 293 streets (all
Overpass hits), 42 neighbourhoods (Denver 32, Boulder 10), 20 rail (RTD + Durango Depot + Devil's Gate), 5 airports,
0 harbours, 125 generic streets. Flag PD (Commons, pinned; blue `#00205B` = accent), cover rendered. All checks pass;
WA/AZ/FL regenerated with no diff (no shared city keys, `contested.lua` stays empty). No template/tool changes.

- **Towns**: `cdpMinPop` 300 gives ~335 after exclusions. Exclude military CDPs (Fort Carson, Air Force Academy) and
  Denver-suburb subdivision CDPs (… Estates, Ranchettes, Stonegate, Meridian, Inverness, The Pinery). `keepCdp`
  Pueblo West, Security-Widefield, Cascade-Chipita Park (hyphen/drop-word filter). **LSAD strip bug-alike**: Census
  "Central city" comes out as "Central"; `rename` keys are the *stripped* name (`"Central": "Central City"`), not
  the Census full name. Also "City of Creede" → Creede, "Raymer (New Raymer)" → Raymer. Exclude zero-population
  paper towns (Carbonate).
- **Regions**: four polygons were easy as three (front, slope, mountain; plains = default). Front's west edge and
  mountain's east edge share vertices; Cañon City/Florence fall into front via a kink at (38.35, -105.4).
- **Station/town collisions**: grep every station/neighbourhood name against towns.tsv (Iliff, Evans, Lamar,
  Sheridan, Lincoln Park, Windsor all collide in CO). The lint doesn't catch it; a 10-line Python check does.
- **Sources that worked**: RTD GTFS (`rtd-denver.com/files/gtfs/google_transit.zip`, parent stations =
  `location_type 1`) gives every official rail name in one go; the operator's web pages 404. Denver neighbourhoods:
  `services1.arcgis.com/zdB7qR0BtYrg0Xpl/arcgis/rest/services/ODC_ADMN_NEIGHBORHOOD_A/FeatureServer/13/query?where=1%3D1&outFields=NBHD_NAME&returnGeometry=false&f=json`.
  Overpass city queries with `admin_level~"^(6|8)$"` cover Denver (consolidated city-county).
- Time sinks: Overpass 429/504 on 2 of 13 street queries (retry after 45 s worked); the neighbourhood place query
  failed for Colorado Springs on every mirror, so CS ships without neighbourhoods (listed in data_review).

### California

2026-10-08. 550 towns (socal 187, valley 112, bay 102, desert 42, central 37, north 36, mountain 34; big 15), 13
street cities / 360 streets (Overpass-checked), 92 neighbourhoods (LA, SF, San Diego, Oakland), 79 rail, 17 airports,
9 ports. 127 generic streets. Flag PD (Commons, pinned; bear brown `#5C462B` = accent, since the red is Florida's and
the green is Washington's), cover rendered. All checks pass; other states regenerated with no diff (no shared keys,
`contested.lua` stays empty; Glendale CA was left out on purpose because Glendale AZ would win). No template/tool
changes.

- **Big states**: 482 incorporated places already fill the town budget, so set `cdpMinPop` absurdly high and pick CDPs
  only with `keepCdp`, aimed at the thin pools (mountain, north, desert). **keepCdp and setSide use the name after
  `rename`** (the tool renames first): keep "Tahoe City", not "Sunnyside-Tahoe City".
- **Regions**: polygons only, no countyTags (no county fetch needed). Order mountain → desert → valley → north → socal →
  central, default bay. Mountain resorts outside the Sierra (Big Bear, Idyllwild, …) via `setSide`. Census internal
  points can sit oddly (Hesperia's at 34.397 needed the desert edge lowered to 34.35).
- **GTFS feeds that worked** (Python urllib, stops.txt only): BART `bart.gov/dev/schedules/google_transit.zip`,
  Caltrain `data.trilliumtransit.com/gtfs/caltrain-ca-us/caltrain-ca-us.zip`, LA Metro Rail
  `gitlab.com/LACMTA/gtfs_rail/-/raw/master/gtfs_rail.zip`, Metrolink `metrolinktrains.com/globalassets/about/gtfs/gtfs.zip`,
  MTS `sdmts.com/google_transit_files/google_transit.zip` (parent stations = location_type 1), Amtrak
  `content.amtrak.com/content/gtfs/GTFS.zip`. SacRT `iportal.sacrt.com/GTFS/SRTD/google_transit.zip` has an expired
  TLS cert (curl -k) and no parent stations: join routes(route_type 0) → trips → stop_times → stops.
- **Many station names are also town names** in a state this size (Del Mar, Fillmore, Rio Vista, Mariposa, Montclair,
  Brentwood): the clash check against towns.tsv is essential.
- **Overpass**: Oakland failed on every mirror the first time, then worked on a retry minutes later; Sacramento/Santa
  Monica likewise. A resumable verifier (skip cities already in the result JSON) saves re-querying. ~25 min total.
- `harborWord = "ports and ferry terminals"` reads badly ("airports and ports and ferry terminals"); use one word.

### Texas

2026-10-08. 533 towns (east 242, west 110, panhandle 73, gulf 69, valley 39; big 15), 13 street cities / 367 streets
(Overpass-checked), 88 neighbourhoods (Houston, Austin, Dallas, San Antonio), 54 rail, 28 airports, 9 ports/ferry
landings, 128 generic streets. Flag PD (Commons, pinned; red `#BF0A30` = accent, since the blue is exactly Colorado's),
cover rendered. All checks pass. **Contested**: Pasadena TX (146,716) beats Pasadena CA (133,560), so California's
`contested.lua` changed (`pasadena` → Texas); CA tests pass. No other shared keys.

- **Tool change**: `towns_config.json` takes `incMinPop` (a number or `{regionTag: floor}`; the tag is setSide, else the
  region polygon/defaultTag, else the crest side) and `keepTown` (exempt names). Needed for states with far more
  incorporated places than the budget (Texas 1,225; Pennsylvania next). Test `test_inc_min_pop`; all other states'
  towns.tsv unchanged. Per-region floors keep thin pools alive (east 6500 vs panhandle 400).
- **Sources that worked**: DART GTFS `dart.org/transitdata/latest/google_transit.zip` (includes TRE), CapMetro
  `data.texas.gov/download/r4v4-vz24/application%2Fzip`, Houston METRO `metro.resourcespace.com/pages/download.php?ref=4835&ext=zip`
  (stop names have NB/SB suffixes; no parent stations), Trinity Metro `gtfsdata.ridetm.org/gtfs/fwtatransitdata.zip`.
  Houston super neighborhoods: `geogimsms.houstontx.gov/arcgis/rest/services/DIR/CityCouncil/MapServer/1/query?where=1%3D1&outFields=SNBNAME&returnGeometry=false&f=json`.
  Austin: `services.arcgis.com/0L95CJ0VTaxqcmED/ArcGIS/rest/services/PLANNINGCADASTRE_neighborhood_planning_areas/FeatureServer/0`.
  Airports: a general-purpose subagent checked all 29 on AirNav (FAA 5010) in ~2.5 min while streets ran — worth repeating.
- **Pitfalls**: Overpass took ~15 min for 13 cities (Houston/San Antonio needed the third retry). The FAA names of some
  airports exceed 40 bytes (Lubbock, Amarillo, Brownsville): shorten or data_review. Galveston streets are dual-named
  in OSM ("Church Street - Avenue F"). The verifier's directional strip maps "South Congress Avenue" onto
  "Congress Avenue": drop such duplicates.

### Alaska

2026-10-08. 282 towns (arctic_west 112, southcentral 70, interior 48, southeast 33, islands 19; big 15), 9 street
cities / 250 streets (all Overpass hits), 28 neighbourhoods (Anchorage community councils), 3 rail (Girdwood, Portage,
Denali), 31 airports, 14 ferry terminals, 128 generic streets. `minTowns 250, minPool 100, minStreetCities 9`. Flag PD
(Commons, pinned; gold stars `#FFB612` = accent, since the dark blue is close to Colorado's), cover rendered. All checks
pass; other states regenerated with no diff (no shared city keys). No template/tool changes.

- **Overpass, faster recipe**: instead of a candidate regex per city, dump every named highway once per city boundary
  (`rel(<id>);map_to_area->.c;way(area.c)[highway][name];out tags;`, relation ids from one
  `rel(area.s)[boundary=administrative][admin_level~"^(6|7|8)$"][name~"A|B|…"]; out tags;` query), save to JSON, then
  pick from the trunk/primary/secondary/tertiary names and match candidates offline. 12 cities ≈ 6 min with retries;
  no re-querying while editing lists. Juneau/Sitka/Anchorage boundaries are admin_level 6 (consolidated).
- **Towns**: LSAD names came out clean (no renames needed besides Sutton-Alpine → Sutton). Islands work better as
  region polygons (Kodiak box + Aleutians box, listed first) than as `countyTags`, because a countyTag is only an extra
  tag and the town's first tag would still be the default region.
- **Wording**: region labels containing "and" read badly in the climate sentence ("plus Southcentral and Kodiak and
  the Aleutians"); use brackets ("the islands (Kodiak, Aleutians)"). Use `notes` for an honest coverage caveat.
- **Sources**: a background subagent verified ARRC depots, AMHS terminals, FAA names (it pulled the NASR APT_BASE.csv
  zip directly when airnav rate-limited: `nfdc.faa.gov/webContent/28DaySub/extra/<DD_Mon_YYYY>_APT_CSV.zip`) and the
  Anchorage council list in ~5 min while streets downloaded. ARRC uses bare place names (most = engine default).

### New York

2026-10-08. 541 towns (upstate 230, island 142, downstate 88, north 81; big 15), 13 street cities / 382 streets (all
Overpass hits), 177 neighbourhoods (NYC 104, Buffalo 24, Rochester 24, Syracuse 14, Albany 11),
52 rail, 39 airports, 11 harbours, 129 generic streets. `minPool 75, minStreetCities 12`. Flag PD (Commons, pinned;
seal gold `#ECC875` = accent, since the blue field is close to Colorado's and the red to Texas's), cover rendered
("New York" fits on line 1 easily). All checks pass; other states regenerated with no diff (no shared city keys).

- **Tool change**: `cdpMinPop` now also takes `{regionTag: floor}` (same lookup as `incMinPop`; unlisted tags have no
  floor). New York needs it: Long Island hamlets are 10k+ suburbs, Adirondack hamlets a few hundred. Test
  `test_cdp_min_pop_per_region`; every other state's towns.tsv is byte-identical.
- **Overpass, faster still**: `[out:csv(name,highway;false;"\t")]` instead of `out tags` keeps the NYC dump at 1.6 MB
  (8,370 names). Relation ids from Nominatim (`nominatim.openstreetmap.org/search?q=Utica,+New+York&format=json`, 1 req/s)
  because the area-scoped `rel(area.s)…` lookup timed out on every mirror. Strip directional *suffixes* too
  ("Erie Boulevard East"). Yonkers failed once (all mirrors 500), worked on a rerun.
- **Neighbourhoods**: the NYS GIS layer `gisservices.its.ny.gov/arcgis/rest/services/NYS_Place_Points/FeatureServer/0`
  with `where=PLACETYPE='Neighborhood'` has official names for NYC, Buffalo, Rochester, Syracuse and Albany in one
  query. NYC's 2020 NTAs (`data.cityofnewyork.us/resource/9nt8-h7nd.json`) give the per-borough names (split the
  hyphenated labels). Watch town clashes (Yorkville, Highland, Brighton, Whitehall are NY villages/CDPs).
- **Rail**: MTA GTFS at `rrgtfsfeeds.s3.amazonaws.com/gtfsmnr.zip`, `gtfslirr.zip`, `gtfs_subway.zip`; NFTA rail
  `metro.nfta.com/__googletransit/rail/google_transit.zip`. Most LIRR/Metro-North stops in NYC are neighbourhood names,
  so decide per name which kind gets it. Subway: only unabbreviated, unique names (Bowling Green, City Hall …); SIR
  names work well. The background airport/ferry subagent (FAA NASR + operator sites) took ~4 min again.
- **Towns**: NY has 595 incorporated places and ~700 hamlet CDPs; per-region floors for both, then keep lists for
  resort/beach places. Exclude CDPs named after a bigger neighbour (North Valley Stream, Glens Falls North).

### Minnesota

2026-10-08. 485 towns (south 148, metro 98, prairie 88, north 81, lakes 70; big 15), 12 street cities / 329 streets (all
Overpass hits), 96 neighbourhoods (Minneapolis 49, St. Paul 19, Duluth 28), 11 rail, 38 airports, 0 harbours, 129
generic streets. `minPool 120, minStreetCities 12`. Flag: the 2024 flag, Commons PD (pinned; light blue `#52C9E8` =
accent, since the dark blue is close to Colorado's), cover rendered. All checks pass. **Contested**: Rochester (NY
wins) and Austin (TX wins, MN Austin only carries an airport); New York's and Texas's `contested.lua` gained the
entries, their tests pass. No template/tool changes.

- **Regions**: metro box first, then lakes (central lake country, the tropical stand-in), prairie (western strip incl.
  Red River Valley, the dry stand-in), north (Arrowhead/Iron Range/north woods, subarctic); south = default. Metro
  floor 5000 or the suburbs swamp the list.
- **Sources that worked first time**: Metro Transit GTFS `svc.metrotransit.org/mtgtfs/gtfs.zip` (no parent stations;
  join routes 0/2 → trips → stop_times). Northstar has no trips in it (service ended), so no commuter rail. Official
  neighbourhood layers via the ArcGIS Online search API (`arcgis.com/sharing/rest/search?q=<city> neighborhoods
  type:"Feature Service"`) found all three cities' city-owned layers in one go. Reverse-geocode GTFS coordinates
  (Nominatim `reverse`, zoom 10) to check which city a station is in (VA Medical Center is not in Minneapolis).
- **Pitfalls**: Overpass took ~15 min for 12 cities (504/429/500 on about half the first tries; the retry loop got all).
  Rochester MN uses quadrant suffixes ("2nd Street Southwest"); the verifier must try prefix-only and suffix-only strips,
  and map "Saint " → "St.". When writing cities.lua from Python, wrap lines at item boundaries (textwrap split a quoted
  name and lupa raised "unfinished string").
- The FAA renamed STC to "St. Cloud Sky Central" (2025): trust the current NASR cycle over memory.

### New Mexico

2026-10-08. 278 towns (rio 76, desert 60, high 55, west 54, plains 33; big 15), 12 street cities / 401 streets (all
Overpass hits), 50 neighbourhoods (Albuquerque 35, Santa Fe 15), 9 rail, 26 airports, 0 harbours, 128 generic streets.
`minTowns 250, minPool 100, minStreetCities 12`. Flag PD (Commons, pinned; turquoise `#0095B6` = accent, the state gem,
since the Zia red is Texas's and the yellow sits between Alaska's gold and the hazard yellow), cover rendered ("New
Mexico" fits line 1). All checks pass; other states regenerated with no diff (no shared city keys). No template/tool
changes.

- **Towns**: thin state, so `cdpMinPop` 300 with every incorporated place gives ~280 directly. Exclude AFB/White Sands
  CDPs, Napi Headquarters, "… Acres/Knolls/Meadows" subdivisions. 89 CDPs are new in 2020 (no 2010 count): grep the 2023
  gazetteer against the 2010 file and `keepCdp` the known ones (Ojo Caliente, Isleta, Fruitland, Gamerco, Tortugas).
- **Regions**: six polygons with repeated tags (two `rio`, two `high`) work fine: an Española-valley box before the main
  Rio Grande corridor, and a Sacramento Mountains box for Ruidoso/Cloudcroft. Turquoise Trail villages fell in a gap
  (`setSide`).
- **Sources**: Rio Metro GTFS (Rail Runner) via riometro.org/261/GTFS-Data (the mobilitydatabase URL is stale); most
  Rail Runner names are towns or slash names, so only 6 ship. Albuquerque/Santa Fe neighbourhood-association layers are
  official; strip " NA"/" Association" and skip HOAs. A background subagent did rail/airports/neighbourhoods in ~4.5 min.
- **Overpass**: 12 of 13 city dumps in ~5 min; Las Vegas failed every mirror (left out, data_review). The `dump.py`
  pattern (Nominatim relation id → csv dump, resumable) is worth reusing.
- A second `notes` item gives the honest street-coverage line in the description.

### Oregon

2026-10-08. 357 towns (west 240, east 117, coast 58, south 53, mountain 35; big 15), 12 street cities / 342 streets (all
Overpass hits), 95 neighbourhoods (Portland 53, Eugene 16, Salem 13, Bend 13), 40 rail, 41 airports, 0 harbours, 162
generic streets. `minTowns 300, minPool 90, minStreetCities 12`. Flag: Commons "Flag of Oregon.svg" (the obverse, PD,
pinned); accent Douglas fir green `#2C5E3F` (navy ~ Colorado, gold ~ Alaska/New York). Cover rendered. All checks pass.
**Contested**: Oregon loses albany (NY), aurora (CO), ontario (CA), redmond (WA); those four older mods'
`contested.lua` gained the entries (tests pass). Albany OR has a full street list that only applies without the NY mod.
No template/tool changes.

- **Towns**: WA's `crest` continued south (Mt Hood, Santiam Pass, Three Sisters, Crater Lake, Mt McLoughlin) plus two
  rules (`coast` lonLt -123.7, `south` latLt 43.4 on the west side) and a `mountain` hand list; no polygons needed.
  `removeTags` is `{town: [tags]}`, not `{tag: [towns]}` (the tool warns "config names a town that is not in the draft").
  `cdpMinPop` 500 + ~70 keepCdp (many 2020-only CDPs: Boring, Chemult, Crescent, Rhododendron) gives ~357.
- **Rail**: TriMet GTFS: two thirds of MAX names are streets/intersections or slash pairs; several more are official
  Portland neighbourhoods (Hollywood, Kenton, Goose Hollow, Parkrose) — let the neighbourhood list keep those. Amtrak OR
  stops are all town names except Portland ("Union Station").
- **Process**: the background subagent (GTFS + NASR + 4 city neighbourhood layers + ferries, ~5 min) ran while the
  resumable dump script (`dump.py` from NM, Nominatim ids) pulled 12 cities in ~10 min; Albany needed a second run.
  The scratchpad `orst/` holds dump/verify/build/emit scripts reusable for Pennsylvania.

### Pennsylvania

2026-10-08. 488 towns (southeast 105, northeast 89, southwest 86, north 82, central 77, northwest 49; big 15), 13 street
cities / 372 streets (all Overpass hits), 109 neighbourhoods (Philadelphia 57, Pittsburgh 52), 58 rail, 49 airports, 2
ferry landings (Penn's Landing, Dobbins Landing), 137 generic streets. Flag PD (Commons, pinned); accent = the seal
shield's sea blue `#1F5290` (the field is exactly Colorado's `#00205B`). "Pennsylvania" + "Towns & Streets" fit the
cover on two lines. All checks pass; other states regenerated with no diff (no shared city keys, `contested.lua`
unchanged). No template/tool changes.

- **Towns**: the three "municipality" LSADs (Bethel Park, Monroeville, Murrysville) and Bloomsburg "town" strip with no
  warnings. Per-region `incMinPop`/`cdpMinPop` (southeast 4000/8000 … north 300/500) gave ~520, then excludes for
  Pocono/lake subdivision CDPs (Penn Estates, Saw Creek, Hemlock Farms, …) and suburban tract CDPs. The `north` polygon
  dips to 41.0 in the west to take in the Pennsylvania Wilds (DuBois, Clearfield, Clarion), else the subarctic pool is thin.
- **Process**: the background research subagent (Amtrak/SEPTA/PRT GTFS, Census geocoder for station towns, NASR, two
  city neighbourhood layers, ferries) took ~8 min while `dump.py` pulled 13 cities; Pittsburgh and State College failed
  every mirror on the first pass and worked on a rerun ~15 min later. Scripts in the scratchpad `pa/` (dump, verify,
  build, emit) are reusable.
- **SEPTA**: GTFS (github.com/septadev/GTFS releases) abbreviates ("Chelten Av") and writes "Transit Center"; Metro lines
  use the new L/B/M ids. Most suburban Regional Rail stops sit in townships (no Census place), so only a few key towns
  get entries. PRT GTFS is ALL CAPS (title-case it).
- **Philadelphia's neighbourhood layer** has no plain "Center City", "Kensington", "Germantown", "Mount Airy"; only the
  exact layer names ship (data_review). Point Breeze/Spring Garden/Overbrook exist in both big cities: one owner each.
- **For Hawaii (last)**: 0 incorporated places, so `bigIncludesCdp: true`, `rename` "Urban Honolulu" → "Honolulu", and
  `cdpMinPop` does all the trimming; ʻokina names only via `asciiFallback`.

### Hawaii

2026-10-08. 131 towns, all CDPs (oahu 42, big_island 37, maui 29, kauai 23; extra tags leeward 43, upcountry 10; big
15), 13 street cities / 299 streets (all Overpass hits), 51 neighbourhoods (Honolulu 41, East Honolulu 10), 11 rail
(Skyline), 14 airports, 4 harbours, 123 generic streets. `minTowns 120, minPool 60, minStreetCities 13`. Flag PD
(Commons, pinned, 2:1; the Union Jack canton reads fine on the cover); accent hibiscus pink `#D63384` (flag navy ~
Colorado, red ~ Florida/Texas). All 13 state mods: `--check` clean, check/test/validate pass; no contested keys.

- **Tool changes**: `towns_config.json` `renameGeoid` (`{"<GEOID>": "Name"}`, applied before `rename`; keepCdp and the
  hyphen filter see the new name; warns on an unknown GEOID) for Hawaii's two "Kailua" CDPs (the Big Island one →
  Kailua-Kona; otherwise the same-name rule drops it). `state.lua` `introTowns` (the "from A to B" pair in the
  description; default the two biggest; must be in towns.tsv) because Hawaii's #2 is East Honolulu. Tests
  `test_rename_geoid` and an `introTowns` case; every other state regenerates byte-identical.
- **Overpass on CDPs**: Hawaii has no municipal boundaries, but OSM carries the Census CDP polygons as relations
  (`boundary=census` or `place=*`, ids 119xxx from Nominatim). `dump.py` works unchanged on those ids; 13 dumps in ~2 min.
  OSM names carry okina/macrons ("Kalākaua Avenue", "Ho'okele"): fold them (drop ʻ ' ’, strip combining marks) before
  matching and ship ASCII.
- **Regions**: island boxes as polygons + `tagLists` for leeward/upcountry (weights work on any tag, not just the first).
- Skyline official names are "Hawaiian, English Station"; the English half ships. Scripts: scratchpad `hi/`.
