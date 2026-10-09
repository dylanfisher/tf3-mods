# US State Names series: next states and rollout

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

**Prerequisite for every new state:** finish Washington's in-game run (`TESTING.md` Phase 1 + 2). The station-suffix
answer (Phase 1 item 5) and a font check (gap G4 below) decide how the rail data and non-ASCII names are written.
Every new state depends on both, so no new state's data is final until they're answered.

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

### Existing mod.io name sets (conflict check)

The slug survey (mod.io search and API need JS or a key, so slugs were probed) found a "**<State> Names**" mod for
**all 50 states**, all described as "<State> town and street names". This is almost certainly AZ-Ranger's batch, ids
6418624 (Alaska, "Alaskan Names") and 6424725–6430129. Only Washington's author and contents are confirmed: the local
copy has 635 towns and 84 streets, set name "Washington", at `content/names/washington/`. Utah has a second, curated
set ("Utah Names", 154 towns, 582 streets) by an unknown author.

What this means:
- No state is uncontested. What sets ours apart is everywhere: real streets per city, real stations, climate-aware towns.
  The description already leads with these. Keep that order.
- Paths: ours are `content/names/<modId>/…` and `content/<modId>/…`, so they never clash with `content/names/<state>/`.
- Picker labels: theirs show as bare "<State>", ours as "<State> (Towns & Streets)", so they're distinct.
- Add the WA-style note to every state (`notes` in `state.lua`): "Not affiliated with the "<State> Names" mod; all lists
  here are our own." Alaska's is "Alaskan Names".
- Never open or derive from their lists, same rule as research.md §5.3. Our sources are Census, OSM (check only) and
  official agency lists.

### Overlap between our own state mods

The owner rule (`sn_logic.isActive`):
- **The game uses a series set** (`nameList` starts with `square_names_us_`): only the mod that owns it renames.
  "Portland" on an Oregon map gets Oregon streets even with Maine active. **No conflict.**
- **The game uses a base or third-party set**: every active series mod renames towns found in its own `cities.lua`.
  For a shared key (Portland OR/ME, Springfield IL/MA/MO/OR, Aurora CO/IL, Glendale AZ/CA, Pasadena CA/TX,
  Arlington TX/VA, Jacksonville FL/NC, Lakewood CO/WA/OH, Richmond CA/VA, Albany NY/OR/GA, Salem OR/MA), both mods
  queue the same stop. The second usually skips because of the "renamed since the build" check. If both send in the
  same window, the last one lands. Either way the stop gets a real name, but **a town can end up mixing two cities'
  streets** (stop 1 Oregon, stop 2 Maine).
- Proposed fix (G9): the generator knows every state's `cities.lua`, so for each contested key it records the
  winner (the bigger city by Census population) in every mod involved. At runtime the losing mod skips that city
  when the winner's modId shows up in `getModParams()`. Older mods learn about new contests when they're regenerated
  (Phase 4 rule: a revision bump each time).
- Only `cities.lua` keys matter. Shared **town** names (Miami AZ, Duluth WA) are harmless.

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

## 5. Per-state checklist (repeatable)

Copy into `plans/square_state_names/states/<key>.md` and tick it off. `<key>` = `us_<state>`, modId =
`square_names_us_<state>`.

1. **Data: towns**
   - Write `data/states/<key>/towns_config.json` (FIPS, postal, region polygons and `countyTags`, CDP filters).
   - Run `make state-towns STATE=<key> ARGS=--fetch`, then `make state-towns STATE=<key>`.
   - Check `regions.geojson` on a map, review oddly named CDPs, iterate on the config (never on the TSV).
2. **Data: streets and cities**
   - Write `streets.lua` (generic, ≥ 120) and `cities.lua` (≥ 10 cities with streets unless the state is waived,
     stations for the major ones).
   - Give every entry a source: an Overpass hit for streets, an operator list for stations.
   - Unsure entries go to the state's `data_review.md` section, not into the data.
3. **Meta:** write `state.lua` (names, climates, notes incl. "<State> Names" non-affiliation, accent, `minTowns` if
   waived, revision 1, changelog "unreleased").
4. **Generate:** `make state-mod STATE=<key>`, then `make state-mods ARGS=--check` (clean, WA unchanged).
5. **Checks:** `make check MOD=mods/square_names_us_<state>`, `make test MOD=…`, `make validate MOD=…` (the cover
   warning is OK until step 7).
6. **Flag:**
   - `make flags ARGS='--lookup "Flag of <State>.svg" --key <key>'`, pin it in `SOURCES.json` (PD/CC0 only), then
     `make flags STATE=<key>`.
   - Check the sanitizer output (element counts).
7. **Cover:** add a `Square.stateCover({...})` entry in `branding/mods.js` (aspect from SOURCES.json), check it in
   `branding/index.html`, run `make covers MOD=mods/square_names_us_<state>`, add the README palette row.
8. **In-game test** (user): `make link`, then the `TESTING.md` Phase 1 items with the state's set and cities:
   - one new game per mapped climate
   - stops in two big cities
   - one station per kind that has data
   - the non-ASCII check (G4) if the state has such names
   - the two-state check (Phase 2 #12) with Washington active.
9. **Slides:** captures into `plans/square_names_us_<state>/shots/`, add a `Square.slides(...)` entry in
   `branding/shots.js`, run `make shots MOD=…`.
10. **Release:** set the changelog date in `state.lua`, regenerate, run `make validate` with no warnings. The user
    uploads via Mod Hub → My Mods.

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

## 7. Data-quality gate (applies to every state, enforced in review)

- **Towns:** Census places only. Renames only to the form people actually use ("Urban Honolulu" → "Honolulu"), each
  with a comment in `towns_config.json`. No invented places, no military bases or tribal-community CDP names
  (follow WA's `excludeCdp` pattern; tribal *towns* that are ordinary Census places stay).
- **Streets, neighbourhoods and stations:** each entry must be real and current, with a source: an Overpass hit inside
  the city, the operator's or agency's station list, the FAA name, or the city's neighbourhood map. Prefer the signed
  form. Leave directional prefixes out unless they're part of how the street is known (WA rule). No slash names, no
  trademarks or sponsor names.
- **Uncertain entries go to the state's section of `data_review.md`** with the reason. Never ship "probably". Examples:
  a stop not open yet, a name with an unclear official form, a facility outside the city players expect.
- **Generic street pools** must be clearly generic (trees, terrain, numbered streets) and need no per-name fact check,
  but no real person's name unless it's a common street name (Washington, Lincoln, MLK).
- **Before release:** a second pass by a fresh subagent that only checks sources (spot-check 20 % of entries, all
  stations). Any miss sends the whole list back for checking.

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

## 9. User decisions (2026-10-08)

- **All 12 states now**, sequentially, one subagent per state, in rank order: Arizona, Florida, Colorado, California,
  Texas, Alaska, New York, Minnesota, New Mexico, Oregon, Pennsylvania, Hawaii. A Phase 0 subagent (generator
  fixes) runs first. Each subagent appends what it learned to `HANDOFF.md` for the next one.
- **Keep data reasonable**: just enough names to feel real. Towns: roughly 250–500 per state (fewer for small states,
  lint floors per state). Cities: ~6–12 with streets (15–30 streets each), stations for the major ones. No Census API
  key; 2010 CDP counts + `keepCdp` are fine. Thin states (Alaska, Hawaii, New Mexico) are OK if the description is honest.
- **Accents: plain ASCII** for now (`asciiFallback` on for every state; Cañon City → Canon City). Revisit after the
  font check.
- **Rail lists: mainline/commuter first, then light rail.**
- **Shared city keys: the bigger city wins** (G9, built in Phase 0; Washington regenerated too).
- **Scope per state: data + generated mod + checks + flag + cover.** In-game tests, slides and upload stay with the user.
