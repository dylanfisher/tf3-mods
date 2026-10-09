# Data review: Washington (`data/states/us_washington/`)

Phase 1 ships only names I'm confident are real and current. This file lists what was **left out** because I
wasn't sure, and what **ships but should get the Phase 3 OSM / official-source spot check first**. To add something
from the "left out" list, confirm it, add it to `cities.lua`, and run `make state-mod STATE=us_washington`.

## Left out (not shipped)

| City | Kind | Name | Why not shipped |
|---|---|---|---|
| Auburn | street | Ellingson Road | Mostly in Pacific/Algona; unsure how much is inside Auburn |
| Walla Walla | street | Pleasant Street | Unsure of the exact name/type (Street vs Avenue) |
| Kent | rail | Kent Des Moines | Federal Way Link extension: unsure it's open and of the final name |
| Federal Way | rail | Federal Way Downtown, Star Lake | Same (Federal Way Link extension) |
| Seattle | rail | Judkins Park | 2 Line cross-lake segment: unsure it's open |
| Seattle | rail | University of Washington / UW | Unsure of the current official name |
| Seattle | rail | International District/Chinatown | Real, but the slash form reads badly as a game name; "International District" is a neighbourhood entry |
| SeaTac | rail | SeaTac/Airport | Same slash issue; SeaTac has "Angle Lake" |
| Shoreline | rail | Shoreline South/148th, Shoreline North/185th | Slash names |
| Mount Vernon | rail | Skagit (Skagit Station) | Unsure whether players expect "Skagit" or "Mount Vernon" |
| Centralia | rail | Centralia Union Depot | Fine name, but the city has no street list yet; add with streets |
| Leavenworth | rail | Icicle (Icicle Station) | Amtrak's Leavenworth stop; add if the "Station" form is settled (Probe 3) |
| Wenatchee | rail | Columbia Station | Ambiguous without the town name |
| Everett, Kent, Auburn, Tukwila, Edmonds | rail | "<Town> Station" | Same as the engine's default name, so nothing to do |
| Gig Harbor | airport | Tacoma Narrows Airport | Outside Tacoma city limits; Gig Harbor has no entry yet |
| Tumwater | airport | Olympia Regional Airport | Tumwater has no entry yet |
| Port Angeles | airport | William R. Fairchild International Airport | Long; unsure of the short form people use |
| Ferry towns | harbor | Edmonds, Mukilteo, Kingston, Bainbridge Island, Anacortes, Friday Harbor, Port Townsend, Vashon, Southworth | WSF terminal names equal the town name, so the default is already right |
| Vashon | harbor | Tahlequah | The south-end terminal; Vashon's own terminal is "Vashon" |
| Everett | neighborhood | Pinehurst | Unsure of the official neighbourhood name |

## Shipped, spot-check before release (Phase 3)

- **Seattle rail = Link light rail station names** after King Street (Westlake, Symphony, Pioneer Square, Stadium,
  SODO, Beacon Hill, Mount Baker, Columbia City, Othello, Rainier Beach, Capitol Hill, U District, Roosevelt,
  Northgate). Real names, but light rail rather than mainline rail; decide whether that reads right for a
  player-built train station. Same for Bellevue (2 Line), Redmond (Redmond Technology, Overlake Village, Downtown
  Redmond, Marymoor Village; the last two opened in 2025, confirm), Lynnwood City Center, Tukwila International
  Boulevard, SeaTac Angle Lake.
- **Airports placed in the town players expect, not the town they're in**: Sea-Tac Airport under Seattle (it's in
  SeaTac, which also has it), Pangborn Memorial Airport under Wenatchee (it's in East Wenatchee, which also has it),
  Boeing Field under Seattle (straddles Seattle/Tukwila). Station names are unique map-wide, so each is used once.
- **Tacoma rail**: "Freighthouse Square" (Amtrak's Tacoma stop since 2017) and "Tacoma Dome" (Sounder) are both
  listed; check they don't read as duplicates.
- **Seattle harbours**: "Pier 66" (Bell Street cruise terminal) and "Pier 91" (Smith Cove cruise terminal).
- **Neighbourhoods with medium confidence**: Vancouver (Uptown Village, Bagley Downs, Shumway), Bellevue (Woodridge,
  Old Bellevue), Spokane (Bemiss, Garland District, Perry District), Everett (Port Gardner, Delta), Renton (Highlands),
  Kent (East Hill, West Hill, Panther Lake).
- **Street lists with medium confidence** (OSM check per street): Kennewick, Pasco, Richland, Walla Walla, Wenatchee
  ("Fifth Street"/"Ninth Street" spelled out as signed), Federal Way (numbered streets written without "S"), Auburn
  ("A Street", "M Street"), Bellevue/Redmond/Kirkland numbered avenues ("108th Avenue NE" style).
- **Directional prefixes dropped**: Seattle and Tacoma streets are listed without their N/S/NE prefixes
  ("Rainier Avenue", not "Rainier Avenue S"); Bellevue keeps "NE 8th Street" because that's how it's known.
- **Towns (Census CDPs)**: all names are real Census places, but some read oddly as game towns: Navy Yard City,
  Startup, Bunk Foss, Cohassett Beach, Five Corners, Silver Firs, Tanglewilde, Cavalero, Fobes Hill, Lofall,
  Duluth, Geneva, Lakeview, Clearview, Midland, Union. Drop any with `excludeCdp` in `towns_config.json`, then
  `make state-towns STATE=us_washington` and `make state-mod STATE=us_washington`.
- **CDP populations** are 2010 (the only free source without an API key); 2023 estimates for incorporated places.
  CDPs created after 2010 have population 0 and are only kept when listed in `keepCdp`.
- **Region tags**: west/east from a hand-drawn Cascade crest polyline (`towns_config.json`); towns right at the
  crest (Snoqualmie Pass = east, Trout Lake = west, White Salmon = east) may deserve a `setSide` override.

## Arizona

Data in `data/states/us_arizona/`. Every shipped street had an Overpass hit (highway way, directional prefix
dropped, inside the city's admin_level 8 boundary) on 2026-10-08. Phoenix neighbourhoods = the city's 15 urban villages
(maps.phoenix.gov Villages layer).

### Left out (not shipped)

| City | Kind | Name | Why not shipped |
|---|---|---|---|
| Flagstaff | street | Route 66 | No Overpass hit by that name (OSM likely tags it differently); add once the signed name form is checked |
| Flagstaff | street | Agassiz Street, Railroad Springs Boulevard | No Overpass hit |
| Glendale | street | 43rd Avenue | No hit inside Glendale (border street with Phoenix) |
| Yuma | street | Giss Parkway | No Overpass hit |
| Sedona | street | Back O Beyond Road, Arroyo Pinon Drive | No Overpass hit inside Sedona |
| Mesa | street | Macdonald, Robson | Real suffix-less OSM names, but read oddly as stop names |
| Phoenix | neighborhood | Paradise Valley (urban village) | Also an incorporated town; would confuse |
| Phoenix | rail | Phoenix Union Station | Real building, no passenger service since 1996 |
| Phoenix | rail | Downtown Phoenix Hub | Valley Metro's new downtown transfer name; unsure of the final official form |
| Phoenix/Tempe/Mesa | rail | Other Valley Metro stations | All official names are slash/intersection names ("Washington/Central Avenue") |
| Tucson | rail | Sun Link stops | Intersection names ("Congress Street & Stone Avenue"); "Plaza Centro" only eastbound |
| Williams | rail | Williams Junction | Amtrak platform; unsure it's still served |
| Clarkdale | rail | Verde Canyon Railroad depot | Station name equals the town (default) |
| Prescott | airport | Ernest A. Love Field | Ships as "Prescott Regional Airport"; the Love Field part is a secondary name |
| Sierra Vista | airport | Sierra Vista Municipal Airport / Libby Army Airfield | Joint civil/military field; unsure of the form players expect |
| Lake Havasu City, Kingman, Page | airport | "<Town> Airport" | Same as the engine's default name, nothing to do |
| Tempe, Mesa, Flagstaff | neighborhood | (none) | No official neighbourhood list checked; add later if wanted |

### Shipped, spot-check before release

- **Phoenix rail "Metro Parkway"**: Valley Metro B Line terminus (opened 2024); the only non-slash light rail name.
- **Airports in short form**: "Sky Harbor Airport" (Phoenix Sky Harbor International), "Mesa Gateway Airport"
  (Phoenix-Mesa Gateway), "Pulliam Airport" (Flagstaff Pulliam), "Grand Canyon Airport" under Tusayan (Grand Canyon
  National Park Airport), "Phoenix Goodyear Airport" under Goodyear.
- **Tucson neighbourhoods** (medium confidence on the exact official form): Feldman's, Miramonte, Civano, Barrio Anita,
  Menlo Park. **Scottsdale**: Old Town, McCormick Ranch, Gainey Ranch, DC Ranch, Grayhawk, Troon (master-planned
  communities; check they read right as station names). **Phoenix**: Arcadia (not an urban village).
- **Towns (Census CDPs)**: excluded subdivision-style CDPs (Avenue B and C, Orange Grove Mobile Manor, Wall Lane,
  Lazy Y U, …, list in `towns_config.json`). Still shipped but odd as game towns: Six Shooter Canyon, Icehouse
  Canyon, Elephant Head, Whitecone, Tees Toh, Bitter Springs, Cane Beds, Low Mountain, Walnut Creek, Cedar Creek.
- **Kept despite the drop-word/hyphen filter** (`keepCdp`): Sun City West, Drexel Heights, Heber-Overgaard.
- **Renamed**: "Village of Oak Creek (Big Park)" → "Village of Oak Creek".
- **Region tags**: hand-drawn Mogollon Rim line. Edge towns: Kingman and Golden Valley = desert, Globe/Miami/
  San Carlos = desert, Whiteriver/Canyon Day = high, Safford = desert, Benson = sky. Check `regions.geojson`.

## Florida

Data in `data/states/us_florida/`. Streets: Overpass (highway way inside the city's admin_level 8 boundary,
directional prefix/suffix dropped) on 2026-10-08; 336 shipped, 333 with a direct hit. Neighbourhoods: OSM place/boundary
hits plus a few well-known official names (marked below). Stations: SunRail station list (sunrail.com), Miami-Dade
Metrorail station list (miamidade.gov), Tri-Rail station list (tri-rail.com destination pages + route map).

### Left out (not shipped)

| City | Kind | Name | Why not shipped |
|---|---|---|---|
| Miami | street | Coral Way, Le Jeune Road, Bird Road, Calle Ocho, Tamiami Trail, Venetian Causeway, Sunset Drive | No Overpass hit by that name inside Miami (OSM uses the grid name, e.g. "Southwest 22nd Street", or the street lies outside the city) |
| Tampa | street | MacDill Avenue, Bearss Avenue, Martin Luther King Jr. Boulevard | No Overpass hit (spelling/prefix form unclear) |
| St. Petersburg | street | Martin Luther King Jr. Street | No hit in either spelling |
| Fort Lauderdale | street | Sistrunk Boulevard | Signed co-name of NW 6th Street; no OSM hit |
| Pensacola | street | Zaragoza Street | No hit; check spelling |
| Gainesville | street | Tower Road, Millhopper Road, Glen Springs Road | No hit inside city limits |
| Orlando | street | Church Street | Dropped as a street because the SunRail station "Church Street" ships (lint: one name can't be both) |
| Miami | rail | MiamiCentral | Brightline's station brand (one word); reads like a trademark. Brightline's other stops equal the town name (default) |
| Miami | rail | Civic Center | Now "UHealth / Jackson" (sponsor name) on the county list |
| Miami | rail | Brickell, Coconut Grove, Allapattah | Real Metrorail stations, but the same names ship as Miami neighbourhoods (station names are unique map-wide) |
| Miami / Coral Gables | rail | Douglas Road | Unsure which city the station sits in |
| Miami-Dade | rail | Golden Glades, Metrorail Transfer, Dr. Martin Luther King Jr. Plaza, Northside, Brownsville | Unincorporated / excluded CDPs, or generic names |
| Hialeah | rail | Okeechobee | Same as the town of Okeechobee |
| Orlando | rail | LYNX Central | Agency brand in the name; add if wanted |
| Orlando | rail | Orlando Health / Amtrak, AdventHealth, Tupperware | Slash or sponsor names |
| Jacksonville | rail | JTA Skyway stations | Short people-mover; names not checked |
| Fort Lauderdale | airport | Fort Lauderdale-Hollywood International Airport | Over 40 bytes; no settled short form (in Dania Beach/unincorporated anyway) |
| Key West | harbor | Key West Bight Ferry Terminal | Unsure of the official terminal name |
| Tampa | neighborhood | Port Tampa | Reads too close to the harbour "Port Tampa Bay" |
| Jacksonville / Miami / Orlando | neighborhood | Springfield, Edgewater, Callahan | Also Florida town names |
| Orlando | neighborhood | Colonialtown North/South, Milk District, South Eola | No OSM hit / district rather than neighbourhood |

### Shipped, spot-check before release

- **Near-miss streets** (real, OSM spells "Saint" or the name is a direction word): St. George Street (St. Augustine),
  St. Johns Avenue (Jacksonville), West Avenue (Miami Beach).
- **Neighbourhoods not in OSM, shipped from the official city lists from memory**: Miami Flagami, Upper Eastside,
  Morningside, Silver Bluff; Tampa Channel District, West Tampa, Westshore, Ballast Point, New Tampa. Confirm against
  the cities' neighbourhood maps.
- **Stations placed by city**: Cypress Creek (Tri-Rail) under Fort Lauderdale, Sheridan Street under Hollywood,
  Hialeah Market under Hialeah, University (Metrorail) under Coral Gables, Dadeland North/South under Kendall (CDP),
  Port Everglades under Fort Lauderdale (spans Fort Lauderdale/Hollywood/Dania Beach), Port Canaveral under Cape
  Canaveral, Mayport (St. Johns River Ferry) under Jacksonville, Miami International Airport under Miami
  (unincorporated, players expect Miami). "Miami Airport" = the Tri-Rail/Metrorail station name, distinct from the
  airport entry.
- **Tampa rail "Tampa Union"**: Amtrak's Tampa Union Station without the suffix; check it reads right with "Station".
- **Towns**: all incorporated places + CDPs >= 15,000 (2010) + a keepCdp list (Keys, beach/island CDPs, county
  seats). Excluded suburban-tract CDPs (Country Club, University, Lakeside, The Hammocks, Kendale Lakes, … list in
  `towns_config.json`) and CDPs that shadow a same-named town (Lake Butler CDP in Orange County, Midway CDP in Santa Rosa).
  Still shipped and borderline: Alafaya, Tamiami, Westchester, Lealman, Fruit Cove, Bayonet Point, Oakleaf Plantation.
- **Renamed**: "Islamorada, Village of Islands" → Islamorada; Census "Everglades" (city) → Everglades City.
- **Region tags**: straight latitude bands. Daytona Beach and Ocala (lat ~29.2) come out "north", Port St. Lucie
  "central". Perry (Taylor County, -83.58) is "north". Check `regions.geojson`.

## Colorado

Data in `data/states/us_colorado/`. Streets: Overpass (highway way inside the city's admin_level 6/8 boundary,
directional prefix dropped) on 2026-10-08; 293 shipped, all with a direct hit. Neighbourhoods: Denver's official
statistical neighborhoods (Denver open data ArcGIS layer `ODC_ADMN_NEIGHBORHOOD_A`) plus LoDo (lodo.org) and RiNo
(rinoartdistrict.org); Boulder's local historic districts (bouldercolorado.gov "What is a historic district?") plus
OSM place nodes. Stations: RTD GTFS `stops.txt` (rtd-denver.com, 2026-10-08); Durango Depot and Devil's Gate from the
railroads' own pages (via WebSearch).

### Left out (not shipped)

| City | Kind | Name | Why not shipped |
|---|---|---|---|
| Denver | street | Martin Luther King Jr. Boulevard | No Overpass hit in that spelling |
| Colorado Springs | street | Cache La Poudre Street | No hit (capitalisation/spelling in OSM unclear) |
| Pueblo | street | Lincoln Avenue | No hit inside city limits |
| Lakewood | street | 6th Avenue, Belmar Way | No hit (US 6 is a freeway under another name; Belmar's streets are private/named differently) |
| Durango | street | Wilson Gulch Road | No hit inside city limits |
| Greeley | street | Lincoln Park Drive | No hit |
| Aspen | street | Gillespie Avenue | No hit |
| Durango | street | East 5th Avenue | Hit only with the "East" prefix; left out rather than ship a directional form |
| Denver | neighborhood | Union Station, Central Park | Official neighbourhoods, but the same names ship as rail stations (unique map-wide) |
| Denver | neighborhood | Lincoln Park, Windsor | Official neighbourhoods, but also Colorado town names |
| Boulder | neighborhood | University Hill, Whittier, Newlands, Frasier Meadows | Well known, but no official list found (OSM has "The Hill" and "Frazier Meadows"); Whittier also ships for Denver |
| Colorado Springs | neighborhood | Old Colorado City, Broadmoor, Briargate, Ivywild, Patty Jewett, Knob Hill, Old North End | From memory; the city publishes no neighbourhood layer that I could find, and Overpass failed (500/406) |
| Aurora | rail | Iliff | Real R Line station, but Iliff is also a town (Logan County) |
| Aurora | rail | Florida, Peoria, Dayton, Colfax | Florida reads as the state; Peoria and Dayton sit on the city line (unsure which city); Colfax duplicates the street feel |
| Denver | rail | Evans, Colorado | Evans is also a town; Colorado reads as the state |
| Denver | rail | Decatur-Federal, Oxford-City of Sheridan, slash/"&" names (38th & Blake, 16th Street / California, …) | Series rule: no slash names; hyphen pairs read the same way |
| Golden | rail | Jefferson County Government Center | GTFS form is "Jefferson CO Government-Golden"; no clean official short name |
| Lakewood | rail | Sheridan, Lamar | Both are also town names |
| Arvada | rail | Gold Strike | GTFS name is "60th / Sheridan - Arvada Gold Strike" |
| Manitou Springs | rail | Pikes Peak Cog Railway depot | Unsure of the depot's official name |
| Pueblo | rail | Union Depot | Historic building, no current passenger service |
| Aspen | airport | Aspen/Pitkin County Airport (Sardy Field) | Slash form only; outside Aspen city limits |
| Durango | airport | Durango-La Plata County Airport | ~14 miles outside the city; hyphenated name |
| Greeley | airport | Greeley-Weld County Airport | Hyphenated name; unsure of the short form people use |
| Fort Collins | airport | Northern Colorado Regional Airport | In Loveland, which has no entry |
| Eagle / Gypsum | airport | Eagle County Regional Airport | Neither town has an entry yet |

## California

Data in `data/states/us_california/`. Streets: Overpass (highway way inside the city's admin_level 6/8 boundary,
directional prefix dropped) on 2026-10-08; 360 shipped, all with a hit (MLK Jr. Way and Fourth Street in Berkeley,
De La Vina Street in Santa Barbara via a second spelling query). Neighbourhoods: OSM place/boundary/landuse names
inside the city (LA, SF, San Diego, Oakland). Stations: GTFS `stops.txt` of BART, Caltrain, Metrolink, LA Metro Rail,
San Diego MTS and SacRT (2026-10-08), plus Amtrak GTFS for the town-named stops. Airports and ports from memory of the
FAA/operator names (not fetched): spot-check them.

| City | Kind | Name(s) | Why not shipped |
|---|---|---|---|
| Santa Monica | street | Bundy Drive | No hit inside city limits (it runs on the LA side) |
| San Francisco | neighborhood | Bayview, Mission District, Sea Cliff | No OSM hit in that form (DataSF uses "Bayview Hunters Point", "Mission", "Seacliff") |
| Oakland | neighborhood | Old Oakland, Laurel District, Crocker Highlands, Redwood Heights, Prescott | No OSM hit; the Overpass check was the only source used |
| Oakland | neighborhood | Montclair | Also a California city (San Bernardino County) |
| Oakland | neighborhood | Chinatown, Fruitvale, Rockridge | Ship as BART stations (Chinatown ships for San Francisco) |
| Los Angeles | neighborhood | Brentwood, Chinatown, Leimert Park, Palms, Highland Park (rail) | Brentwood is a California city; the others ship as one kind only (Chinatown in SF, Leimert Park and Palms as rail, Highland Park as a neighbourhood) |
| Oakland | rail | Jack London Square | Amtrak's GTFS calls the stop just "Oakland" (OKJ); the station is signed "Oakland - Jack London Square" |
| Oakland | rail | 12th Street / Oakland City Center | Slash name |
| SF / Oakland | rail | 16th Street / Mission, 24th Street / Mission, Civic Center / UN Plaza | Slash names |
| Oakland | airport | Oakland International Airport | 2024 rename to "San Francisco Bay Oakland International Airport" is contested in court; unclear current name |
| San Jose | airport | Mineta San Jose International Airport | Branding changed (San José Mineta International); unsure of the short form to ship |
| San Diego | rail | Gaslamp Quarter, Barrio Logan, Balboa Avenue, Washington Street, 12th & Imperial, County Center/Little Italy | Gaslamp Quarter ships as a neighbourhood; Balboa Avenue and Washington Street are also streets; "&"/slash names |
| San Diego | rail | Rio Vista | Also a California city (Solano County) |
| Pasadena | rail | Del Mar, Fillmore | Both are also California cities |
| Sacramento | rail | 16th Street, Broadway, City College | 16th Street and Broadway are also streets; City College ships for San Diego (station names are unique map-wide) |
| San Jose | rail | VTA light rail stops | Not checked (VTA GTFS was fetched but not reviewed); Caltrain names ship |
| Avalon | harbor | Cabrillo Mole | Catalina Express terminal; unsure of the official terminal name |
| Long Beach | harbor | Catalina Express landing names | Unsure of the official names |

- **Towns**: 480 incorporated places (Vernon and Industry excluded: industrial-only) + 70 hand-picked CDPs (keepCdp;
  `cdpMinPop` is effectively off). Renamed: San Buenaventura (Ventura) → Ventura, El Paso de Robles (Paso Robles) →
  Paso Robles, Sunnyside-Tahoe City → Tahoe City, Idyllwild-Pine Cove → Idyllwild.
- **Airports outside their city**: San Francisco International (San Mateo County) and Sacramento International
  (unincorporated Sacramento County) ship under the city whose name they carry. Brown Field ships under its common
  short name (FAA "Brown Field Municipal").
- **Region tags**: hand-drawn polygons. Foothill Gold Country towns (Auburn, Placerville, Sonora, Jackson) are "valley";
  Grass Valley and Nevada City are "mountain"; Redding/Red Bluff are "valley"; Clearlake is set to "north" with Lakeport.
  Big Bear, Lake Arrowhead, Crestline, Running Springs, Wrightwood, Idyllwild, Julian and Frazier Park are set to
  "mountain" by hand. Check `regions.geojson`.

## Texas

Data in `data/states/us_texas/`. Streets: Overpass (highway way inside the city's admin_level 8 boundary, directional
prefix dropped) on 2026-10-08; 367 shipped, all with a hit (Galveston's dual names such as "Church Street - Avenue F"
ship as the named half). Neighbourhoods: Houston super neighborhoods (COHGIS `DIR/CityCouncil/MapServer/1`), Austin
neighborhood planning areas (`PLANNINGCADASTRE_neighborhood_planning_areas`), Dallas and San Antonio OSM place hits.
Stations: GTFS `stops.txt` of DART (incl. TRE), Trinity Metro (TEXRail), CapMetro and Houston METRO (2026-10-08).
Airports: AirNav (FAA 5010) for every one; ports: port sites and Texas statutes (checked by a subagent, 2026-10-08).

| City | Kind | Name(s) | Why not shipped |
|---|---|---|---|
| San Antonio | street | César E. Chávez Boulevard | No hit in the ASCII form tried; non-ASCII signed form |
| Galveston | street | Broadway | OSM has "Broadway Avenue", "Broadway - Avenue J" and "Broadway Street"; unclear which form is signed |
| Pasadena | street | Tatar Street, Preston Avenue | No hit inside city limits |
| Dallas | neighborhood | Preston Hollow, Pleasant Grove, Kessler Park, Knox-Henderson, Victory Park, Trinity Groves, The Cedars, M Streets, State Thomas, Junius Heights, Swiss Avenue, Munger Place, Winnetka Heights, Vickery Meadow, West Dallas, Casa Linda, … | No OSM place/boundary hit (Overpass was the only source used); a city neighbourhood layer would likely confirm most |
| San Antonio | neighborhood | Jefferson | Also a Texas town (Marion County, shipped) |
| Houston | neighborhood | Uptown | Ships for Dallas (station names are unique map-wide) |
| Houston | rail | Wheeler | Also a Texas town (Wheeler County, shipped) |
| Houston | rail | Stadium Park/Astrodome ("Houston Stadium" in the GTFS feed) | Slash name; the feed's "Houston Stadium" looks like World Cup naming, METRO's pages still say Stadium Park/Astrodome |
| Houston | rail | Ensemble/HCC, Dryden/TMC, Hermann Park/Rice U, EaDo/Stadium, Burnett Transit Center/Casa de Amigos, … | Slash names |
| Houston | rail | Magnolia Park Transit Center | Magnolia Park ships as a neighbourhood |
| Dallas | rail | Deep Ellum, Lake Highlands | Ship as neighbourhoods |
| Dallas | rail | Lovers Lane, Royal Lane, Forest Lane | Also streets in Dallas |
| Dallas | rail | Pearl/Arts District, Cityplace/Uptown, SMU/Mockingbird, Inwood/Love Field, LBJ/Central, Tyler/Vernon, … | Slash names |
| Dallas | rail | Convention Center, Zoo | Generic ("Convention Center" ships for San Diego in the California mod) |
| Fort Worth | rail | T&P Station | "&" name (formally Texas and Pacific Station); "T&P" alone reads oddly without the suffix |
| Fort Worth | rail | Iron Horse, Smithfield, Grapevine/Main Street | In North Richland Hills / Grapevine, not street cities |
| Austin | rail | Leander | Also a Texas town |
| Austin | neighborhood | Crestview, Highland | Ship as CapMetro rail stations |
| Brownsville | airport | Brownsville South Padre Island International Airport | Over 40 bytes; FAA form uses a slash |
| Port Aransas | harbor | Port Aransas Ferry | TxDOT labels the route "Corpus Christi-Port Aransas" and the landings "Aransas Pass" / "Port Aransas" (town names); unclear form |
| Point Comfort | harbor | Calhoun Port Authority | Point Comfort (pop ~700) is below the gulf town floor |

- **Towns**: 533 of 1,225 incorporated places via per-region floors (`incMinPop`: east 6500, west 800, gulf 1500,
  panhandle 400, valley 2000) + 17 `keepTown` small towns + 13 hand-picked CDPs. Renamed: Town of Pecos → Pecos.
- **Shipped, spot-check**: Dallas-Fort Worth International Airport ships under Dallas (it lies between the cities);
  Jack Brooks Regional under Beaumont (FAA city "Beaumont/Port Arthur"); "Preston Smith International Airport" and
  "Rick Husband International Airport" drop the city prefix for the 40-byte limit; "Fort Worth Alliance Airport" is
  the second half of the FAA name "Perot Field/Fort Worth Alliance Airport"; Killeen Regional Airport (renamed from
  Killeen-Fort Hood Regional in 2023). "Union Station" (Dallas) is DART's "EBJ Union Station".
- **Region tags**: hand-drawn polygons (`regions.geojson`). Wichita Falls, Alice and Victoria are "east"; the Hill
  Country west of ~-98.6 (Kerrville, Fredericksburg, Boerne) is "west"; Lubbock is "panhandle".

## Alaska

2026-10-08. Streets: Overpass (one named-highway dump per city boundary, then candidates matched with the directional
prefix dropped); all shipped streets hit. Stations: alaskarailroad.com depot locations + schedules; AMHS
dot.alaska.gov/amhs/contact.shtml; airports FAA NASR APT_BASE (cycle 2026-10-01); Anchorage neighbourhoods from the
Federation of Community Councils list (communitycouncils.org).

| City | Kind | Name(s) | Why not shipped |
|---|---|---|---|
| Anchorage | rail | Anchorage airport depot ("Bill Sheffield Alaska Railroad Depot") | No alaskarailroad.com page uses a name for it; not on current schedules |
| Anchorage | rail | Anchorage (downtown depot) | The railroad calls it just "Anchorage" = the engine default; no entry needed |
| (none) | rail | Spencer (Glacier) Whistle Stop, Grandview, Hurricane, Chase, Curry, Gold Creek, … | Whistle/flag stops outside every Census town |
| Anchorage | neighborhood | Bayshore/Klatt, Huffman/O'Malley, Old Seward/Oceanview, Taku/Campbell, UMed/Tudor, Northeast | Slash names / directional; the council list is from the Federation site (muni.org Assembly page 404, AMC 2.40 not fetched) |
| Anchorage | neighborhood | Girdwood | Ships as an Alaska Railroad stop |
| Palmer | airport | Warren "Bud" Woods Palmer Municipal Airport | 43 bytes; "Palmer Municipal Airport" not confirmed on an official site |
| Hollis | harbor | Clark Bay (Inter-Island Ferry terminal) | Only secondary sources (DOT survey PDF, The Milepost); Hollis is a town but has no city list |
| Ketchikan | harbor | Revilla / Gravina airport ferry facilities | DOT project names only, no public terminal name |
| Seldovia | harbor | Seldovia | AMHS lists "City of Seldovia" instead of a terminal |
| Fairbanks | street | Geist Road, Farmers Loop Road, Mitchell Expressway (short form) | Outside city limits in OSM / only the long form "Robert Mitchell Expressway" hits |
| Juneau | street | Back Loop Road | No hit in the City and Borough boundary |
| Ketchikan | street | Married Mans Trail, Edmond Street | No highway hit inside city limits |
| Sitka | street | Kogwanton Street, Degroff Street, Japonski Drive, Kincaid Street | No hit |
| Kodiak | street | Center Avenue, Benson Avenue, Near Island Bridge, Simeonoff Street, Upper Mill Bay Road, … | No hit inside the (small) city boundary |
| Homer | street | Beluga Avenue, Diamond Ridge Road, Old Sterling Highway | No hit inside city limits |

- **Towns**: 282 (incorporated + CDPs ≥ 50 in 2010). Excluded military posts (Eielson AFB, Fort Greely, Kodiak
  Station), Red Dog Mine, Seldovia Village / Eagle Village (named after the neighbouring city) and road-named suburb
  tracts (Badger, Steele Creek, Chena Ridge, Farmers Loop, Farm Loop, Gateway, Buffalo Soapstone). Renamed
  Sutton-Alpine → Sutton. Denali Park (CDP new since 2010) ships with population 0. Prudhoe Bay (oil-field CDP) kept.
- **Shipped, spot-check**: "Anchorage International Airport" (airport's own logo; the FAA name is 42 bytes);
  "Lake Hood Seaplane Base" (dot.alaska.gov/anc; FAA record says "Lake Hood"); "Deadhorse Airport" under Prudhoe Bay;
  "Dutch Harbor" (Unalaska's port) as Unalaska's harbour; honorific airport names kept (Sitka Rocky Gutierrez,
  Merle K. (Mudhole) Smith, Edward G. Pitka Sr.).

## New York

2026-10-08. Streets: Overpass (one `[out:csv(name,highway)]` dump of named highways per city boundary, candidates matched
offline with a directional prefix or suffix dropped); all shipped streets hit. Neighbourhoods: NYC Planning 2020 NTAs
(NYC Open Data `9nt8-h7nd`) and the NYS GIS `NYS_Place_Points` layer (Buffalo, Rochester, Syracuse, Albany). Rail: MTA
Metro-North, LIRR and subway GTFS, Amtrak GTFS + amtrak.com station pages, NFTA Metro Rail GTFS. Airports: FAA NASR
APT_BASE (cycle 2026-10-01). Ferries: siferry.com, govisland.com, ferry.nyc route pages. Ports: operators' sites.

| City | Kind | Name(s) | Why not shipped |
|---|---|---|---|
| New York | street | Fifth Avenue, Seventh Avenue, Lenox Avenue | OSM has "5th Avenue"/"7th Avenue" (5th ships) and "Malcolm X Boulevard"; no hit for the spelled-out forms |
| Rochester | street | St. Paul Street | OSM spells it "Saint Paul Street" (that form ships) |
| Utica | street | Lafayette Street | No hit inside the city boundary |
| Niagara Falls | street | Elm Street | No hit inside the city boundary |
| New York | rail | subway stations with "St"/"Av"/"Sq" abbreviations, slashes or repeated numbers (Times Sq-42 St, 86 St, 14 St-Union Sq, Jamaica Center-Parsons/Archer) | Unclear shipped form; would need spelling out |
| New York | rail | Yankees-E 153 St, Mets-Willets Point | Team names (trademarks) plus abbreviations |
| New York | rail | Long Island City, Forest Hills, Kew Gardens, Bayside, Fordham, Tremont, Riverdale, Melrose, Woodlawn, Wakefield, St. Albans … (LIRR/Metro-North) | Ship as neighbourhoods instead (a name can't be both in one city) |
| Elmont | rail | Elmont-UBS Arena | Sponsor name |
| Buffalo | rail | DL&W, Seneca (GTFS "Seneca Station - Merchants Insurance"), Church St, University, Utica | "&" / sponsor suffix / abbreviation / generic / a New York town name |
| Rochester | rail | Louise M. Slaughter Rochester Station | Over 40 bytes; the short form is "Rochester" = engine default |
| Utica | rail | Union Station (Boehlert Center at Union Station) | amtrak.com calls it just "Utica"; the building name not checked on an official page |
| Depew | rail | Depew Station (Amtrak "Buffalo-Depew") | amtrak.com/stations/buf says "Depew Station" = the town name (engine default) |
| New York | harbor | Wall Street/Pier 11, DUMBO/Fulton Ferry, Sunset Park/Brooklyn Army Terminal, Atlantic Avenue/Brooklyn Bridge Park Pier 6 | Slash names |
| New York | harbor | Greenpoint (B), North Williamsburg (A), Hunter's Point South (A), Soundview (Clason Point), Throgs Neck (Ferry Point Park) | Bracketed suffixes; the bare names are neighbourhoods |
| New York | harbor | Soissons Landing (Governors Island side) | Only a search snippet |
| Orient | harbor | Orient Point (Cross Sound Ferry) | Operator site returned nothing; directory listing only |
| Greenport, Shelter Island | harbor | North Ferry / South Ferry terminals | Operators name only the endpoints, no terminal names |
| Bay Shore, Sayville, Patchogue | harbor | Fire Island Ferries, Sayville Ferry, Davis Park Ferry | Operator names, not terminal names (and the towns aren't all in the list) |
| Port Jefferson | harbor | Port Jefferson ferry dock | No formal terminal name found |
| Cumberland Head, Essex | harbor | Lake Champlain ferry landings | Search snippets only; Port Kent looks inactive (closed 2021) |
| Beacon, Newburgh | harbor | Newburgh-Beacon ferry | Discontinued 2025 (bus now) |
| (none) | harbor | Port of Buffalo | Not checked |
| Rochester | airport | Frederick Douglass Greater Rochester International Airport | Over 40 bytes; ships as "Greater Rochester International Airport" |

- **Towns**: 541 (cities and villages over a per-region 2023 floor, CDPs over a per-region 2010 floor, plus keepTown /
  keepCdp for the Hamptons, North Fork, barrier beaches, Fire Island, Catskill and Hudson Valley towns, Finger Lakes
  villages, Adirondack hamlets). Excluded: Fort Drum and West Point (military), the Binghamton University and University
  at Buffalo campus CDPs, and CDPs named after a bigger neighbour already in the list (North Valley Stream, East
  Massapequa, Glens Falls North, Plattsburgh West, South Lockport, …). The boroughs are not Census places, so New York
  City is the single town "New York" (no borough aliases).
- **Shipped, spot-check**: the NYC neighbourhoods are single parts of hyphenated NTA labels ("Carroll Gardens" from
  "Carroll Gardens-Cobble Hill-Gowanus-Red Hook"); Bedford-Stuyvesant is the NYS layer's form (NTA splits it East/West).
  NYS layer spellings shipped as is: "Abbott McKinley", "Genesee Moselle", "Susan B Anthony" (no full stop). Airports
  keyed to the FAA city when that is a town in the mod (Syracuse Hancock under Syracuse, Hudson Valley Regional under
  Poughkeepsie, East Hampton Town Airport under East Hampton though it sits in Wainscott). "Harlem-125th Street" is
  mta.info's spelling. NYC Ferry landings shipped: Stuyvesant Cove, Corlears Hook, Brooklyn Navy Yard, East 34th Street,
  East 90th Street.

## Minnesota

2026-10-08. Streets: Overpass (one `[out:csv(name,highway)]` dump of named highways per city boundary, relation ids
from Nominatim, candidates matched offline with a directional prefix or quadrant suffix dropped); all shipped streets
hit. Neighbourhoods: City of Minneapolis `Minneapolis_Neighborhoods`, City of Saint Paul `District_Councils`, City of
Duluth GIS `Neighborhoods_Duluth` (ArcGIS feature services). Rail: Amtrak GTFS, Metro Transit GTFS (stops.txt, station
cities checked by reverse geocoding the GTFS coordinates), northshorescenicrailroad.org. Airports: FAA NASR APT_BASE
(cycle 2026-10-01).

| City | Kind | Name(s) | Why not shipped |
|---|---|---|---|
| St. Paul | streets | West 7th Street | OSM has "7th Street West" only; the signed/common "West 7th Street" form doesn't hit |
| Minneapolis | streets | Nicollet Mall | Kept as the rail name (one name can't be both) |
| Bloomington, St. Cloud, Moorhead, Winona, Brainerd, Stillwater | streets | Picture Drive; Benton Drive, Pinecone Road, Michigan Avenue; Highway 10; Service Drive; Main Street, Oakwood Drive; Abbott Street | No Overpass hit inside the city boundary |
| (Northstar line) | rail | Big Lake, Elk River, Ramsey, Anoka, Coon Rapids-Riverdale, Fridley | Not in Metro Transit's current GTFS (no Northstar trips): treated as not running |
| Minneapolis | rail | VA Medical Center, Fort Snelling, Terminal 1, Terminal 2 | Stations sit in Fort Snelling Unorganized Territory, not Minneapolis |
| Minneapolis, St. Paul, Bloomington | rail | 38th St, 46th St, Franklin Ave, Snelling Ave, Raymond Ave, Capitol / Rice St, 50th St / Minnehaha Park, American Blvd ... | Abbreviations or slashes (series rule) |
| Minneapolis, Bloomington | rail | U.S. Bank Stadium, Mall of America | Sponsor / trademark names |
| Minneapolis | rail | Prospect Park, Cedar Riverside, Warehouse District/Hennepin Ave | Neighbourhood names (kept as neighbourhoods) / slash |
| St. Paul | rail | Central | Too generic |
| Red Wing, Winona, St. Cloud, Staples, Detroit Lakes | rail | Amtrak stations | Named after their town (engine default) |
| Minneapolis, Duluth | neighborhoods | Corcoran, Jordan, Waite Park, Windom; Rice Lake | Also Minnesota towns |
| Minneapolis | neighborhoods | Kenwood | Duluth also has a Kenwood (station names are unique map-wide); shipped under Duluth |
| Minneapolis | neighborhoods | Steven's Square - Loring Heights, Cedar - Isles - Dean, industrial areas, University of Minnesota | Odd official spelling / not a neighbourhood name players know |
| Duluth | neighborhoods | CBD, Morley Hts/Parkview, Midway Annex, Chester Park-UMD (shipped as Chester Park), North Shore | Abbreviation / slash / generic |
| Minneapolis | airport | Minneapolis-St. Paul International Airport | 42 bytes; ships as "MSP International Airport" (check the form) |
| Grand Marais | airport | Grand Marais/Cook County Airport | Slash name |
| Duluth | harbor | Port of Duluth-Superior, Vista Fleet dock | A freight port and a cruise dock, no passenger terminal name (Grand Portage-Isle Royale ferry leaves from a tribal CDP not in the list) |

- **Towns**: 485 (incorporated cities over a per-region 2023 floor: metro 5000, south 800, prairie 300, lakes 250, north
  150; CDPs over 1000 in 2010; keepTown Lanesboro, Wayzata, Excelsior; keepCdp Soudan, Lutsen, Angle Inlet, Frontenac).
  Excluded: tribal-community CDPs (Red Lake, Redby, Ponemah, Little Rock, White Earth, Naytahwaush, Pine Point, Ball
  Club, Vineland). Census spells "St. Paul", "St. Cloud" (aliases cover "Saint").
- **Shipped, spot-check**: "St. Cloud Sky Central Airport" (renamed from St. Cloud Regional on 2025-09-30, FAA shows the
  new name); Red Wing Regional Airport (FAA lists it under Red Wing, MN; the field is across the river); "Fleming Field
  Airport" (FAA: South St. Paul Muni/Richard E Fleming Fld); "Richard B. Helgeson Airport" (Two Harbors);
  Westgate (Green Line, reverse-geocoded to St. Paul). **Contested**: Rochester (NY wins) and Austin (TX wins) are
  skipped while those mods are active.

## New Mexico

2026-10-08. Streets: Overpass (one `[out:csv(name,highway)]` dump of named highways per city boundary, relation ids
from Nominatim, candidates matched offline with a directional prefix or quadrant suffix dropped); all shipped streets
hit. Neighbourhoods: City of Albuquerque `agis/Neighborhood_Associations` (coageo.cabq.gov), City of Santa Fe
`NeighborhoodAssociations_1` and `HistoricDistricts` (ArcGIS org "City of Santa Fe"). Rail: Amtrak GTFS, Rio Metro
Rail Runner GTFS (mjcaction.com/MJC_GTFS_Public/nmrailrunner_google_transit.zip, feed 20260727, linked from
riometro.org/261/GTFS-Data; station towns by Nominatim reverse geocoding), cumbrestoltec.com. Airports: FAA NASR
APT_BASE (cycle 2026-10-01) plus AirNav for the expanded names.

| City | Kind | Entry | Why it's here |
|---|---|---|---|
| Las Vegas | streets | (whole list) | The Overpass dump for Las Vegas failed on every mirror; the town ships without a street list (airport only) |
| Albuquerque | streets | Isleta Boulevard | Runs through South Valley, no hit inside the city boundary |
| Las Cruces, Taos, Gallup | streets | Foothills Road; Placitas Road; Railroad Avenue | No Overpass hit inside the city boundary |
| Santa Fe | streets | Zia Road | Also the Rail Runner station name in Santa Fe (shipped as rail) |
| Albuquerque, Bernalillo, Santa Fe | rail | Los Ranchos/Journal Center, Sandoval County/U.S. 550, Santa Fe County/N.M. 599 | Slash names (series rule); no unslashed official form |
| South Valley | rail | Bernalillo County | Official Rail Runner name, but a county name reads oddly as a station in a CDP |
| Albuquerque | rail | Downtown Albuquerque | Rail Runner's name for the Alvarado Transportation Center (shipped under that name) |
| Belen, Los Lunas, Sandia Pueblo | rail | Rail Runner stations | Named after their town (engine default) |
| Raton, Las Vegas, Lamy, Gallup, Deming, Lordsburg | rail | Amtrak stations | Named after their town (engine default) |
| Chama | rail | Chama Depot | **Shipped, spot-check**: cumbrestoltec.com says "our Chama, NM depot" / "the Chama, New Mexico station" (500 Terrace Avenue) but gives no branded name |
| (Cumbres & Toltec) | rail | Osier | In Colorado, not New Mexico |
| Las Cruces | neighborhoods | (whole list) | No official neighbourhood-name layer (only "Lift Up Neighborhood 1/2/..." planning areas) |
| Albuquerque | neighborhoods | International District, Westgate | Only in non-City layers |
| Albuquerque, Santa Fe | neighborhoods | Kirtland, Lee Acres, Los Alamos Addition; Torreon | Also New Mexico towns |
| Santa Fe | neighborhoods | Old Santa Fe Trail, Pacheco Street, Canyon, HOAs and condos | Same as a street / too generic / subdivision names |
| Raton | airport | Raton Municipal Airport/Crews Field | Slash name; ships as "Raton Municipal Airport" |
| Truth or Consequences | airport | Spaceport America | **Shipped, spot-check**: FAA 9NM9, private use, FAA city Truth or Consequences (the site is ~30 mi away) |

- **Towns**: 278 (all incorporated places; CDPs >= 300 in 2010; keepCdp South Valley, North Valley, Yah-ta-hey, Upper
  Fruitland, Lamy, Turquoise Trail and high-road villages, and the 2020 CDPs Ojo Caliente, Isleta, Fruitland, Gamerco,
  Tortugas). Excluded: military (Holloman AFB, Cannon AFB, Kirtland AFB, White Sands), Napi Headquarters,
  subdivision-style names (… Acres, Knolls, Meadows, Farm; Las Maravillas, Peak Place), generic names (Midway,
  Sunshine, San Jose, Monterey Park, University Park). Pueblos that are ordinary Census places stay (user decision).
  Renames: "Eldorado at Santa Fe" → Eldorado, "Pueblo of Sandia Village" → Sandia Pueblo. Doña Ana, Peñasco, Peña
  Blanca, Cañon, Cañada de los Alamos keep their ñ in the data (asciiFallback ships them as n).

## Oregon

2026-10-08. Streets: Overpass (one `[out:csv(name,highway)]` dump of named highways per city boundary, relation ids
from Nominatim, candidates matched offline with a directional prefix or quadrant suffix dropped, "Junior" → "Jr");
all shipped streets hit. Neighbourhoods: City of Portland Neighborhood Boundaries
(portlandmaps.com/od/rest/services/COP_OpenData_Boundary/MapServer/3), City of Eugene `EugNeighborhoods`, City of
Salem `CD_Neighborhoods`, City of Bend `Neighborhood_Associations` (ArcGIS feature services owned by each city). Rail:
Amtrak GTFS, TriMet GTFS (developer.trimet.org/schedule/gtfs.zip; station towns by Nominatim reverse geocoding, which
agreed with TriMet's stop descriptions). Airports: FAA NASR APT_BASE (cycle 2026-10-01). Ferries: Marion and Clackamas
County public works pages.

| City | Kind | Entry | Why it's here |
|---|---|---|---|
| Portland | streets | Cesar Chavez Boulevard | No exact OSM hit under that spelling (accented form in OSM); left out |
| Medford | streets | Ross Lane | No Overpass hit inside the city boundary |
| Portland | rail | Hollywood, Goose Hollow, Kenton, Parkrose (Sumner) | MAX stations named after official neighbourhoods; the neighbourhood list carries them |
| Portland | rail | Old Town/Chinatown, Delta Park/Vanport, Interstate/Rose Quarter, Albina/Mississippi, Clinton St/SE 12th Ave, Lincoln St/SW 3rd Ave, Oak/SW 1st Ave, Morrison/SW 3rd Ave | Slash names with no clean single form |
| Portland, Gresham | rail | NE 82nd Ave, E 122nd Ave, SE Division St, N Lombard TC, … (28 street/intersection names) | Pure street or intersection names |
| Portland | rail | Providence Park | Sponsor name (stadium) |
| Portland | rail | Pioneer Place, OMSI, Mt Hood Ave, Gateway North, Portland International Airport (MAX) | Mall name / acronym / street name / platform variant / same as the airport |
| Milwaukie, Tualatin, Wilsonville | rail | Milwaukie/Main St, Tualatin, Wilsonville | Town names (engine default) |
| (Clackamas, unincorporated) | rail | Clackamas Town Center Transit Center, SE Park Ave, SE Fuller Rd | Not inside a Census town in the list / street names |
| Hillsboro | rail | Hillsboro Airport/Fairgrounds | Slash name |
| Eugene | neighborhoods | Active Bethel, Chambers Westside, Industrial Corridor, Downtown, Northeast, Southeast, River Road | Organisation-style or generic names; River Road is also a Eugene street |
| Salem | neighborhoods | North East Salem, Northeast Neighbors, Southwest, Southeast Salem | Generic / organisation-style names |
| The Dalles | airport | Columbia Gorge Regional Airport | FAA city The Dalles, but the field is in Dallesport, Washington |
| Medford | airport | Rogue Valley International-Medford Airport | 42 bytes: ships as "Rogue Valley International Airport" |
| Redmond | airport | Roberts Field / Redmond Municipal Airport | FAA "ROBERTS FLD/REDMOND MUNI": ships as "Redmond Municipal Airport" |
| Canby, Salem area, Independence area, Westport | harbor | Canby Ferry, Wheatland Ferry, Buena Vista Ferry, Wahkiakum County Ferry | Small county river car ferries (landings, not passenger terminals); Wahkiakum only confirmed via Wikipedia/press. Candidates if the series wants ferry landings |
| Albany, Aurora, Ontario, Redmond | contested | city keys | Albany NY, Aurora CO, Ontario CA and Redmond WA are bigger and win; Oregon's lists for these four only apply when those mods are not active |

- **Towns**: 357 (every incorporated place except Greenhorn, which has no residents; CDPs >= 500 in 2010; keepCdp for
  small Cascade, coast and high-desert communities incl. the 2020 CDPs Boring, Chemult, Crescent, Gilchrist, Crooked
  River Ranch, Rhododendron, Mapleton, Keno, Fort Klamath, Bly). Excluded: subdivision or resort CDPs (Deschutes River
  Woods, Eagle Crest, Bayside Gardens, Three Rivers, Oak Hills, Jeffers Gardens, Mount Hood Villages, Seventh Mountain),
  generic names (Four Corners, Green, Redwood, Tri-City, Summit, Annex, Riverside, Alpine, Fair Oaks), Mission
  (Umatilla reservation community), Roseburg North. Rename: "Garden Home-Whitford" → Garden Home.

## Pennsylvania

2026-10-08. Sources: Overpass street dumps per city boundary (Nominatim relation ids), Amtrak GTFS + Great American
Stations pages, SEPTA GTFS (github.com/septadev/GTFS release v202609271), Pittsburgh Regional Transit GTFS
(rideprt.org), Census geocoder for station/airport towns, FAA NASR APT_BASE (cycle 2026-10-01), the City of Philadelphia
"neighborhoods" and City of Pittsburgh PGHWebNeighborhoods layers, riverlinkferry.com, porterie.org, nps.gov/stea.

| City | Kind | Entry | Why it's here |
|---|---|---|---|
| Erie | streets | Elk Street, Peninsula Drive | No Overpass hit inside the city boundary (Peninsula Drive runs in Millcreek) |
| Scranton | streets | Spruce Street | No Overpass hit inside the city boundary |
| Harrisburg | streets | Market Square, Capital Street, Broad Street | No Overpass hit inside the city boundary |
| Bethlehem | streets | Hanover Avenue, Minsi Trail | No Overpass hit inside the city boundary |
| Altoona | streets | Sixth Avenue | OSM spells it "6th Avenue" (shipped) |
| York | streets | Codorus Street, Continental Square | No Overpass hit inside the city boundary |
| Erie | streets | Lake Road | Only "East Lake Road" exists; the stripped form is too generic |
| Wilkes-Barre / Avoca | airport | Wilkes-Barre/Scranton International Airport | FAA "WILKES-BARRE/SCRANTON INTL": slash name, 42 bytes without the slash; field is in Pittston township |
| Reedsville | airport | Mifflin County Airport | Reedsville is not in the town list |
| Philadelphia | airport | Wings Field | FAA city Philadelphia, but the field is in Blue Bell |
| Strasburg | rail | Strasburg Rail Road station | The railroad's site gives only "301 Gap Road, Ronks"; no official station name found |
| Pittsburgh | rail | Duquesne Incline, Monongahela Incline | GTFS has only "... at Lower/Upper Station" forms; funiculars, not trains |
| Philadelphia | rail | Penn Medicine, NRG Station | Naming-rights names |
| Philadelphia | rail | 15th St/City Hall, 5th St/Independence Hall, Broad-Girard, 8th-Market, Race-Vine, … ; 63rd St, 52nd St, … | Slash/intersection or numbered-street names |
| Philadelphia | rail | Manayunk, East Falls, Fox Chase, Somerton, Tacony, Bridesburg, Olney, Logan, Fairmount, Hunting Park, Chinatown, Eastwick, Spring Garden, Overbrook | Also official neighbourhoods; the neighbourhood list carries them |
| Philadelphia | rail | Tioga, Erie, Huntingdon, Somerset, Wyoming, Forest Hills | Also Pennsylvania town names |
| Suburbs | rail | Jenkintown-Wyncote, Clifton-Aldan, Fernwood-Yeadon, Moylan-Rose Valley | Hyphenated station pairs (no clean single form) |
| Suburbs | rail | Cornwells Heights, Exton, Radnor, Wynnewood, Media, … | Stations in townships, not Census places in the list (no key town) |
| Pittsburgh | rail | Westfield | Also a Pennsylvania town |
| Philadelphia | neighborhoods | Center City, Kensington, Germantown, Mount Airy, Fishtown | Not plain names in the City layer ("Center City East", "Fishtown - Lower Kensington", "East/West Mount Airy"); only exact layer names ship |
| Philadelphia / Pittsburgh | neighborhoods | Point Breeze, Spring Garden, Overbrook | In both cities; station names are unique, so Point Breeze ships for Pittsburgh, the others for Philadelphia |
| Pittsburgh | neighborhoods | Allentown, Manchester, Knoxville; Central Business District | Also Pennsylvania towns; generic |
| Philadelphia | harbor | Penn's Landing | Shipped; RiverLink is seasonal and its 2026 schedule loads by JS (not confirmed for October) |
| Erie | harbor | Waterworks Ferry Dock | Presque Isle end of the water taxi, in the state park (Millcreek), not in Erie |

- **Towns**: 488 (incorporated floors per region: southeast 4000, southwest 3500, central 2000, northeast 1500, north
  and northwest 300; CDP floors (2010): southeast 8000, southwest 4000, central 3000, northeast 2000, north and northwest
  500). Excluded: Pocono and lake subdivision CDPs (Penn Estates, Saw Creek, Hemlock Farms, Indian Mountain Lake, The
  Hideout, Emerald Lakes, Treasure Lake, …), suburban tract CDPs (Schlusser, Kenmar, Skyline View, Valley Green,
  Shiloh, Progress, Parkville, Lower Allen), campus CDPs (Penn State Erie (Behrend), Park Forest Village) and CDPs named
  after a bigger neighbour (East York, East Berwick, North Warren, Northwest Harborcreek). Kept below the floors:
  Strasburg, New Hope, Milford, Delaware Water Gap, Hawley, Ligonier, Ohiopyle, Confluence, Eagles Mere, Bird-in-Hand,
  Intercourse, Pocono Pines, Chadds Ford, Paradise. Lake Harmony and Tannersville are not Census places.

## Hawaii

2026-10-08. Sources: Census Gazetteer 2023 + 2010 POP10 (all places are CDPs), Overpass street dumps per CDP boundary
relation (Nominatim ids), TheBus/DTS GTFS 2608_v5 (Skyline route 181) + honolulu.gov/dts/skyline, FAA NASR APT_BASE
(cycle 2026-10-01) + airports.hawaii.gov, go-lanai.com, DLNR DOBOR facility pages, HDOT Harbors, the City and County of
Honolulu "Neighborhoods" GIS layer (AdministrativePolitical layer 0) and Neighborhood Board list (honolulu.gov/nco).

| City | Kind | Entry | Why it's here |
|---|---|---|---|
| Honolulu | rail | Lelepaua (Daniel K. Inouye International Airport Station) | English half is 56 bytes; "Airport" alone is generic; the airport entry carries the name |
| (none) | rail | Makalapa (Joint Base Pearl Harbor-Hickam Station) | Station point is in no CDP (between Halawa and Honolulu) |
| Pearl City | rail | Leeward Community College | Shipped under Pearl City, but the station point is in no CDP (next to Pearl City) |
| East Kapolei | rail | Kualakai | Shipped as the Hawaiian half of "Kualakai, East Kapolei Station" (the English half is the town name) |
| Lahaina | harbor | Lahaina Harbor | DLNR: closed until further notice (2023 fire); the Lanai ferry now uses Maalaea |
| Kaunakakai | harbor | Kaunakakai Harbor | The Molokai passenger ferry has no current operator site (service looks defunct) |
| Kahului / Hilo / Lihue | harbor | Kahului Harbor, Hilo Harbor, Nawiliwili Harbor | Cruise calls (NCL Pride of America) not confirmed per port (portcall schedule is JS-only) |
| Kailua-Kona | harbor | Honokohau Harbor | Tour/charter boats only, no scheduled passenger service |
| Kalaupapa | airport | Kalaupapa Airport | Kalaupapa is not a Census place in the town list |
| Hilo | neighborhoods | Keaukaha, Waiakea, Kaumana, Panaewa, Downtown Hilo | No official Hawaii County list found; Hilo ships without neighbourhoods |
| Honolulu | neighborhoods | Kalihi Kai, Kalihi Uka, Dowsett | Layer names kept out to keep the list short and clean (Kalihi, Kalihi Valley ship) |
| Honolulu | streets | Interstate H-1, Lunalilo/Moanalua Freeway | Freeways are not stop names (left out on purpose) |

- **Towns**: 131, all CDPs (`bigIncludesCdp`). Renamed: Urban Honolulu → Honolulu, Mililani Town → Mililani,
  Haiku-Pauwela → Haiku, Napili-Honokowai → Napili, Kahaluu-Keauhou → Keauhou, and the Big Island's Kailua CDP
  (GEOID 1523000) → Kailua-Kona (new `renameGeoid`). Waimea on Kauai (1,855) is shadowed by Waimea on the Big Island
  (9,212). Excluded: military housing/bases (Schofield Barracks, Hickam Housing, Wheeler AFB, Iroquois Point, Kaneohe
  Base, Helemano), Kalaeloa, Manele, subdivision CDPs (… Estate(s), … Acres, Ocean Pointe, Ewa Gentry, Fern Forest,
  Eden Roc, Discovery Harbour), Makaha Valley and Waimanalo Beach. New-since-2010 CDPs without population left out
  except East Kapolei, Kalapana and Waiahole-Waikane (Black Sands, Kaiminani, Kaloko, Kamaili, Mauna Loa Estates, Royal
  Hawaiian Estates, Seaview, Tiki Gardens, Volcano Golf Course, Waikoloa Beach Resort could be reviewed).
