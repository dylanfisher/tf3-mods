# State rollout handoff notes

Each state subagent appends a short section (newest last): what it changed in templates/tools, pitfalls, sources that worked, time sinks to avoid.

## Phase 0 (generator)

2026-10-08. G1, G2, G2b, G4, G5, G6, G9 and G10 are done; G7 is dropped (no API key, user decision). Washington was
regenerated: `towns.tsv` is unchanged. The generated mod changed in four places: the description (new climate bullet,
"ferry terminals" wording), the new `data/contested.lua`, the `state.lua` copy, and the runtime (contested check,
wider `normalize`). Tests: `make test MOD=mods/square_names_us_washington` (74 Lua tests) and `make test-tools`
(18 Python tests for `state_towns.py` and `gen_state_mod.py`, in `tests/tools/`).

### New `towns_config.json` keys (tools/state_towns.py)

- `regions`: an ordered list of polygons with vertices in `[lat, lon]` order. The first match wins.
  `"regions": [{"tag": "high", "polygon": [[37.0, -114.1], [37.0, -109.05], [33.6, -109.05], [34.55, -112.9]]}]`
- `defaultTag`: the tag for towns that fall outside every polygon. `"defaultTag": "desert"`
- How regions combine with `crest`: without `crest`, the region tag is the town's first tag ("side"), so rules can
  test it with `"side"`. With `crest`, the crest side comes first and the region tag is added second.
- `rules` now also take `latLt` and `lonGe`: `{"tag": "south", "latLt": 27.0, "side": "central"}`. Every condition
  in a rule must hold.
- `countyTags`: tags by county. A county name works with or without its suffix (" County", " Borough",
  " Census Area", …). `"countyTags": {"keys": ["Monroe"]}`
- `bigIncludesCdp`: CDPs can also get the "big" tag. `"bigIncludesCdp": true`
- `rename` also accepts a name that has an unknown LSAD suffix: map it to itself to silence the warning.
  `"rename": {"Athens-Clarke County": "Athens", "Urban Honolulu": "Honolulu"}`
- With `regions` set, the tool also writes `data/states/<key>/regions.geojson` (polygons plus town points coloured
  by first tag). Paste it into geojson.io to check the boundaries. GeoJSON stores points as `[lon, lat]`; the tool
  converts for you.

### New `state.lua` fields (tools/gen_state_mod.py)

- `asciiFallback = true`: set it in every new state (user decision). The generator transliterates every shipped
  name (Cañon City → Canon City, Utqiaġvik → Utqiagvik, okina dropped). The data files keep the official spelling.
- `minTowns = 250, minPool = 100, minStreetCities = 8`: lint floors. The defaults are 400 / 150 / 15, which
  Washington still uses. Add a comment explaining why. `minStreetCities` is new; add it whenever there are fewer
  than 15 street cities, since the user's target is 6–12.
- `regionLabels = { desert = "the low desert", high = "the high country" }`: names the regions in the
  description's climate sentence. A tag without a label prints as the raw tag, so label every weighted tag.
- `harborWord = "ports"`: the harbour noun (default "harbours"). The harbour sentence is dropped when there are no
  harbours.
- `streetFlavour = "saguaros, mesquite, mountain ranges and canals"`: the text in brackets after the generic street
  count. Leave it out to drop the brackets.
- `townFlavour = "small desert and mining towns"`: completes "from big cities to …" (default "small towns").
- The station and neighbourhood bullets and the intro list only the kinds that have data. Climates without
  positive weights are listed as "use the whole state".

### Per-state workflow

```
# 1. towns
make state-towns STATE=us_<state> ARGS=--fetch    # first time: Census files (+ county files when countyTags is set)
make state-towns STATE=us_<state>                 # iterate on towns_config.json; check warnings + regions.geojson
uv run tools/state_towns.py us_<state> --config /path/draft.json   # optional dry run, prints only
# 2. write streets.lua, cities.lua, state.lua (asciiFallback = true, minTowns/minPool/minStreetCities, wording fields)
make state-mod STATE=us_<state>
make state-mods                                   # regenerates EVERY state: contested.lua can change in older mods
make state-mods ARGS=--check
make check MOD=mods/square_names_us_<state>
make test MOD=mods/square_names_us_<state>
make validate MOD=mods/square_names_us_<state>
make test MOD=mods/square_names_us_washington     # WA again if its contested.lua changed
```

### Pitfalls

- **Run `make state-mods` (all states), not just `state-mod`.** Contested city keys are computed across every
  `data/states/*/cities.lua`, so a new state can change `contested.lua` in older mods (Washington included) and
  `--check` then reports them stale. While Washington is unreleased this needs no revision bump. Once a mod is
  released, any change to its generated files needs a `revision` bump and a changelog entry.
- The popest remote file has no leading zero for single-digit FIPS (`sub-est2023_2.csv` for Alaska), and its PLACE
  column isn't zero-padded either. Both are handled now. Before the fix, every Alaska city had population 0.
- The Census does not publish a 2020 place-to-county relationship file (`rel2020/place/` only has place20 to
  place10). Counties come from the 2020 block assignment file instead: each place goes to the county holding most of
  its blocks. That is a block count, not land area. A place created after 2020 has no county; the tool lists those
  places in one warning.
- An unknown LSAD suffix now prints `warn: unknown LSAD suffix …`. Fix it with a `rename` (to the short name, or to
  itself). " (balance)" is stripped first. Montana's "Butte-Silver Bow (balance)" counts as a known form;
  "Anaconda-Deer Lodge County" still warns, so give it a rename.
- A throwaway Alaska config (regions, a rule, `countyTags` for Kodiak/Aleutians, `cdpMinPop` 50) drafted 294 towns
  with no warnings. Juneau, Anchorage, Sitka and Wrangell came out clean, and Utqiaġvik keeps its ġ in the TSV
  (`asciiFallback` handles it at generation).
- `sn_logic.normalize` now strips quote marks before folding and uses ASCII classes (`[^0-9a-z#]`). `string.lower`
  and `%w` follow the C locale, and under lupa they treated bytes ≥ 128 as letters ("Hawaiʻi" came out as
  "hawai\234i"). Don't go back to `%w` there.
- `tests/run_tests.py` crashes with a `UnicodeDecodeError` (no test report) when a failing assertion message holds
  invalid UTF-8. Run with `-k` to find the test.
- Cover titles fit up to "New Hampshire" (the widest line 1 measured, 237 px clear of the diagonal). "Towns &
  Streets" on line 2 is the tightest line and the same on every state. `cover.js` is unchanged.

## Arizona

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

## Florida

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

## Colorado

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

## California

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

## Texas

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

## Alaska

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

## New York

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

## Minnesota

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

## New Mexico

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

## Oregon

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

## Pennsylvania

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

## Hawaii

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
