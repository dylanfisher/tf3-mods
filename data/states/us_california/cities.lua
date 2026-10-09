-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## California") instead of here.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name (directional prefix
--                  dropped) inside the city's admin boundary. "Martin Luther King Jr. Way" (Oakland, Berkeley)
--                  ships in its signed form; OSM spells it "Martin Luther King Junior Way".
--   neighborhoods  bus/tram stations. LA, San Francisco, San Diego and Oakland: OSM place/boundary hits inside
--                  the city (2026-10-08), minus names that are also California towns (Brentwood, Montclair) or
--                  rail stops (Chinatown in LA, Leimert Park, Palms, Old Town, Glen Park, Fruitvale, Rockridge).
--   rail           passenger train stations, WITHOUT a trailing "Station". Series policy (D5): mainline and
--                  commuter first, then light rail. Names from the operators' GTFS feeds (stops.txt, 2026-10-08):
--                  Caltrain, BART, Metrolink, LA Metro Rail, San Diego MTS (incl. Santa Fe Depot, Coaster
--                  Sorrento Valley), SacRT. Slash and "&" names left out (Civic Center / UN Plaza, 12th & Imperial),
--                  and names that are also California towns (Del Mar, Fillmore, Rio Vista, Mariposa). Amtrak stops
--                  are named after their town (the engine default, no entry).
--   airport        airports/airfields: FAA names in their short common form (Hollywood Burbank Airport is the
--                  airport's own name). San Francisco International and Sacramento International sit just outside
--                  their city limits but carry the city's name.
--   harbor         ports and ferry terminals by their own name (San Francisco Bay Ferry, Golden Gate Ferry)
-- Station names are unique map-wide; street names are unique per town.
return {
	["Los Angeles"] = {
		streets = {
			"Sunset Boulevard", "Hollywood Boulevard", "Wilshire Boulevard", "Santa Monica Boulevard", "Melrose Avenue",
			"Figueroa Street", "Grand Avenue", "Broadway", "Spring Street", "Main Street", "Alameda Street",
			"Olympic Boulevard", "Pico Boulevard", "Venice Boulevard", "Vermont Avenue", "Western Avenue", "La Brea Avenue",
			"Fairfax Avenue", "La Cienega Boulevard", "Highland Avenue", "Vine Street", "Cahuenga Boulevard",
			"Ventura Boulevard", "Van Nuys Boulevard", "Sepulveda Boulevard", "Crenshaw Boulevard", "Mulholland Drive",
			"Temple Street", "Hope Street", "Flower Street",
		},
		neighborhoods = {
			"Hollywood", "Echo Park", "Silver Lake", "Los Feliz", "Koreatown", "Westwood", "Venice", "Boyle Heights",
			"Highland Park", "Eagle Rock", "Studio City", "Sherman Oaks", "Encino", "Pacific Palisades", "San Pedro",
			"Wilmington", "Watts", "Little Tokyo", "Arts District", "Westchester", "Mar Vista", "Atwater Village", "Tarzana",
			"Woodland Hills", "Reseda", "Bel Air", "Hancock Park", "Toluca Lake", "Sylmar", "Granada Hills",
		},
		rail = {
			"Union Station", "Pershing Square", "Historic Broadway", "North Hollywood", "Chatsworth", "Northridge",
			"Van Nuys", "Sun Valley", "Cal State LA", "Soto", "Southwest Museum", "Farmdale", "Palms", "Leimert Park",
			"Hyde Park",
		},
		airport = {
			"Los Angeles International Airport", "Van Nuys Airport", "Whiteman Airport",
		},
		harbor = {
			"Port of Los Angeles",
		},
	},
	["San Diego"] = {
		streets = {
			"Broadway", "Harbor Drive", "Market Street", "Kettner Boulevard", "India Street", "5th Avenue", "4th Avenue",
			"University Avenue", "El Cajon Boulevard", "Park Boulevard", "Washington Street", "Adams Avenue", "Garnet Avenue",
			"Mission Boulevard", "Rosecrans Street", "Midway Drive", "Sports Arena Boulevard", "Morena Boulevard",
			"Clairemont Mesa Boulevard", "Balboa Avenue", "Genesee Avenue", "Friars Road", "Mission Gorge Road",
			"Imperial Avenue", "Euclid Avenue", "Torrey Pines Road", "La Jolla Boulevard", "Prospect Street", "Girard Avenue",
			"Pacific Highway",
		},
		neighborhoods = {
			"Gaslamp Quarter", "Little Italy", "East Village", "Hillcrest", "North Park", "South Park", "Golden Hill",
			"Normal Heights", "University Heights", "Mission Hills", "Ocean Beach", "Pacific Beach", "Mission Beach",
			"Point Loma", "La Jolla", "Clairemont", "Linda Vista", "Tierrasanta", "Logan Heights", "Mira Mesa",
			"Rancho Bernardo", "Kensington", "City Heights",
		},
		rail = {
			"Santa Fe Depot", "Old Town", "America Plaza", "Civic Center", "Convention Center", "Seaport Village",
			"Fashion Valley", "Hazard Center", "Mission San Diego", "Fenton Parkway", "Tecolote Road", "Clairemont Drive",
			"Nobel Drive", "UTC", "Sorrento Valley", "City College",
		},
		airport = {
			"San Diego International Airport", "Montgomery-Gibbs Executive Airport", "Brown Field",
		},
		harbor = {
			"Port of San Diego", "Broadway Pier",
		},
	},
	["San Jose"] = {
		streets = {
			"Santa Clara Street", "San Carlos Street", "San Fernando Street", "1st Street", "2nd Street", "Market Street",
			"Almaden Boulevard", "Alum Rock Avenue", "King Road", "Story Road", "Tully Road", "Capitol Expressway",
			"Stevens Creek Boulevard", "Winchester Boulevard", "Bascom Avenue", "Meridian Avenue", "Lincoln Avenue",
			"The Alameda", "Monterey Road", "Blossom Hill Road", "Hillsdale Avenue", "Saratoga Avenue", "Coleman Avenue",
			"Taylor Street", "Julian Street", "Hedding Street", "Berryessa Road", "Capitol Avenue", "Santa Teresa Boulevard",
			"White Road",
		},
		rail = {
			"San Jose Diridon", "Tamien", "Capitol", "Blossom Hill", "College Park",
		},
	},
	["San Francisco"] = {
		streets = {
			"Market Street", "Mission Street", "Valencia Street", "Castro Street", "Haight Street", "Fillmore Street",
			"Divisadero Street", "Van Ness Avenue", "Geary Boulevard", "Lombard Street", "Columbus Avenue", "Grant Avenue",
			"Stockton Street", "California Street", "Hyde Street", "Polk Street", "Folsom Street", "Howard Street",
			"The Embarcadero", "Clement Street", "Irving Street", "Judah Street", "Taraval Street", "Ocean Avenue",
			"24th Street", "19th Avenue", "Kearny Street", "Sansome Street", "Union Street", "Chestnut Street",
		},
		neighborhoods = {
			"North Beach", "Chinatown", "Nob Hill", "Russian Hill", "Pacific Heights", "Hayes Valley", "Noe Valley",
			"Bernal Heights", "Potrero Hill", "Mission Bay", "South of Market", "Tenderloin", "Japantown", "Inner Sunset",
			"Outer Richmond", "Excelsior", "Presidio Heights", "Twin Peaks", "Haight-Ashbury", "Cole Valley", "Dogpatch",
			"Telegraph Hill", "Cow Hollow",
		},
		rail = {
			"Embarcadero", "Montgomery Street", "Powell Street", "Glen Park", "Balboa Park", "22nd Street",
		},
		airport = {
			"San Francisco International Airport",
		},
		harbor = {
			"Ferry Building", "Pier 41",
		},
	},
	["Fresno"] = {
		streets = {
			"Blackstone Avenue", "Shaw Avenue", "Herndon Avenue", "Ashlan Avenue", "Shields Avenue", "Clinton Avenue",
			"McKinley Avenue", "Olive Avenue", "Belmont Avenue", "Ventura Avenue", "Kings Canyon Road", "Tulare Street",
			"Fulton Street", "Van Ness Avenue", "Fresno Street", "Divisadero Street", "Palm Avenue", "First Street",
			"Cedar Avenue", "Chestnut Avenue", "Peach Avenue", "Bullard Avenue", "Nees Avenue", "Friant Road", "Marks Avenue",
			"West Avenue", "Fruit Avenue", "Maple Avenue", "Willow Avenue",
		},
		airport = {
			"Fresno Yosemite International Airport", "Fresno Chandler Executive Airport",
		},
	},
	["Sacramento"] = {
		streets = {
			"Capitol Mall", "J Street", "K Street", "L Street", "Broadway", "Freeport Boulevard", "Land Park Drive",
			"Riverside Boulevard", "Folsom Boulevard", "Alhambra Boulevard", "Stockton Boulevard", "Franklin Boulevard",
			"Florin Road", "Fruitridge Road", "16th Street", "21st Street", "Del Paso Boulevard", "Northgate Boulevard",
			"Arden Way", "Fair Oaks Boulevard", "Garden Highway", "Truxel Road", "Richards Boulevard", "Front Street",
			"Capitol Avenue", "T Street", "X Street", "Sutterville Road", "Power Inn Road", "Meadowview Road",
		},
		rail = {
			"Sacramento Valley", "Archives Plaza", "Cathedral Square", "St. Rose of Lima Park", "Dos Rios", "Globe Avenue",
			"Royal Oaks", "Swanston", "29th Street", "39th Street", "48th Street", "59th Street", "Power Inn", "Fruitridge",
			"Florin", "Meadowview", "Center Parkway",
		},
		airport = {
			"Sacramento International Airport", "Sacramento Executive Airport",
		},
	},
	["Long Beach"] = {
		streets = {
			"Ocean Boulevard", "Pine Avenue", "Atlantic Avenue", "Long Beach Boulevard", "Broadway", "4th Street",
			"7th Street", "Anaheim Street", "Pacific Coast Highway", "Willow Street", "Wardlow Road", "Carson Street",
			"Del Amo Boulevard", "Artesia Boulevard", "Bellflower Boulevard", "Lakewood Boulevard", "Redondo Avenue",
			"Cherry Avenue", "Spring Street", "Magnolia Avenue", "Santa Fe Avenue", "Shoreline Drive", "2nd Street",
			"Studebaker Road", "Livingston Drive", "Termino Avenue", "Junipero Avenue",
		},
		rail = {
			"Downtown Long Beach", "1st Street", "5th Street", "Wardlow", "Del Amo",
		},
		airport = {
			"Long Beach Airport",
		},
		harbor = {
			"Port of Long Beach",
		},
	},
	["Oakland"] = {
		streets = {
			"Broadway", "Telegraph Avenue", "San Pablo Avenue", "Grand Avenue", "Lakeshore Avenue", "Harrison Street",
			"Webster Street", "Franklin Street", "International Boulevard", "Foothill Boulevard", "MacArthur Boulevard",
			"College Avenue", "Piedmont Avenue", "Park Boulevard", "Fruitvale Avenue", "High Street", "Hegenberger Road",
			"Embarcadero", "14th Street", "Market Street", "Shattuck Avenue", "Claremont Avenue", "Mountain Boulevard",
			"Skyline Boulevard", "Lakeside Drive", "Adeline Street", "40th Street", "Redwood Road", "Lincoln Avenue",
			"Martin Luther King Jr. Way",
		},
		neighborhoods = {
			"Temescal", "Uptown", "Adams Point", "Grand Lake", "Dimond District", "Glenview", "Elmhurst", "Jingletown",
			"Trestle Glen", "Mosswood", "Longfellow", "Lower Bottoms", "Maxwell Park", "Millsmont", "Eastlake", "Clinton",
		},
		rail = {
			"19th Street Oakland", "Lake Merritt", "West Oakland", "MacArthur", "Rockridge", "Fruitvale", "Coliseum",
		},
		harbor = {
			"Port of Oakland",
		},
	},
	["Santa Barbara"] = {
		streets = {
			"State Street", "Cabrillo Boulevard", "Milpas Street", "Anacapa Street", "Chapala Street", "Bath Street",
			"Castillo Street", "Carrillo Street", "Mission Street", "Haley Street", "Gutierrez Street", "Figueroa Street",
			"Canon Perdido Street", "Anapamu Street", "Micheltorena Street", "Victoria Street", "Valerio Street",
			"Garden Street", "Laguna Street", "Santa Barbara Street", "Shoreline Drive", "Cliff Drive", "Las Positas Road",
			"Alamar Avenue", "Mission Canyon Road", "Salsipuedes Street", "Yanonali Street", "De La Vina Street",
		},
		airport = {
			"Santa Barbara Airport",
		},
	},
	["Pasadena"] = {
		streets = {
			"Colorado Boulevard", "Lake Avenue", "Fair Oaks Avenue", "Arroyo Parkway", "Orange Grove Boulevard",
			"Green Street", "Union Street", "Walnut Street", "Del Mar Boulevard", "California Boulevard", "Raymond Avenue",
			"Marengo Avenue", "Los Robles Avenue", "Allen Avenue", "Hill Avenue", "Sierra Madre Boulevard",
			"Washington Boulevard", "Altadena Drive", "Lincoln Avenue", "Mountain Street", "Linda Vista Avenue",
			"Glenarm Street", "Arroyo Boulevard", "Villa Street",
		},
		rail = {
			"Memorial Park", "Lake", "Allen", "Sierra Madre Villa",
		},
	},
	["Berkeley"] = {
		streets = {
			"Telegraph Avenue", "Shattuck Avenue", "University Avenue", "Bancroft Way", "Durant Avenue", "Channing Way",
			"Dwight Way", "Ashby Avenue", "Alcatraz Avenue", "College Avenue", "Piedmont Avenue", "Euclid Avenue",
			"Hearst Avenue", "Cedar Street", "Hopkins Street", "Solano Avenue", "San Pablo Avenue", "Sacramento Street",
			"Gilman Street", "Center Street", "Addison Street", "Oxford Street", "Spruce Street", "Grizzly Peak Boulevard",
			"Martin Luther King Jr. Way",
		},
		rail = {
			"Downtown Berkeley", "North Berkeley", "Ashby",
		},
	},
	["Santa Monica"] = {
		streets = {
			"Ocean Avenue", "Main Street", "Wilshire Boulevard", "Santa Monica Boulevard", "Lincoln Boulevard",
			"Colorado Avenue", "Broadway", "Arizona Avenue", "Montana Avenue", "San Vicente Boulevard", "Pico Boulevard",
			"Ocean Park Boulevard", "4th Street", "2nd Street", "14th Street", "26th Street", "Cloverfield Boulevard",
			"Olympic Boulevard", "California Avenue", "Idaho Avenue", "Neilson Way", "Barnard Way", "Ocean Front Walk",
		},
		rail = {
			"Downtown Santa Monica",
		},
		airport = {
			"Santa Monica Airport",
		},
	},
	["Palm Springs"] = {
		streets = {
			"Palm Canyon Drive", "Indian Canyon Drive", "Tahquitz Canyon Way", "Ramon Road", "Sunrise Way", "Vista Chino",
			"Farrell Drive", "Gene Autry Trail", "Arenas Road", "Alejo Road", "Amado Road", "Andreas Road", "Baristo Road",
			"Belardo Road", "Avenida Caballeros", "Racquet Club Road", "Tramway Road", "Via Escuela", "San Rafael Drive",
			"Mesquite Avenue", "Sunny Dunes Road", "Dinah Shore Drive", "El Cielo Road", "Calle Encilia",
		},
		airport = {
			"Palm Springs International Airport",
		},
	},
	["Burbank"] = {
		airport = {
			"Hollywood Burbank Airport",
		},
	},
	["Ontario"] = {
		airport = {
			"Ontario International Airport",
		},
	},
	["Larkspur"] = {
		harbor = {
			"Larkspur Ferry Terminal",
		},
	},
	["Vallejo"] = {
		harbor = {
			"Vallejo Ferry Terminal",
		},
	},
}
