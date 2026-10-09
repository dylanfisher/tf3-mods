-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## Arizona") instead of here.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name (directional prefix
--                  dropped) inside the city's admin boundary.
--   neighborhoods  bus/tram stations. Phoenix: the city's urban villages (maps.phoenix.gov Villages layer)
--                  minus Paradise Valley (also a town name), plus Arcadia.
--   rail           passenger train stations, WITHOUT a trailing "Station". Series policy (D5): mainline and
--                  commuter first, then light rail. Arizona's Amtrak stops (Flagstaff, Kingman, Winslow, Maricopa,
--                  Tucson, Benson, Yuma) are named after their town, which is the engine default, so they need no
--                  entry. Valley Metro and Sun Link stop names are almost all slash/intersection names, which the
--                  series leaves out; Metro Parkway is the exception. Grand Canyon Railway: Williams Depot and
--                  Grand Canyon Depot.
--   airport        airports/airfields: FAA names in their short common form
--   harbor         none: Arizona has no passenger ferry terminals with a known name
-- Station names are unique map-wide; street names are unique per town.
return {
	["Phoenix"] = {
		streets = {
			"Central Avenue", "Washington Street", "Jefferson Street", "Van Buren Street", "Adams Street",
			"Roosevelt Street", "McDowell Road", "Thomas Road", "Indian School Road", "Camelback Road", "Bethany Home Road",
			"Glendale Avenue", "Northern Avenue", "Dunlap Avenue", "Peoria Avenue", "Cactus Road", "Bell Road",
			"Buckeye Road", "Broadway Road", "Baseline Road", "Southern Avenue", "Grand Avenue", "Cave Creek Road",
			"Tatum Boulevard", "Encanto Boulevard", "Osborn Road", "Missouri Avenue", "Jackson Street", "7th Street",
			"7th Avenue", "16th Street", "24th Street", "19th Avenue", "35th Avenue", "51st Avenue", "Lincoln Street",
		},
		neighborhoods = {
			"Ahwatukee Foothills", "Alhambra", "Camelback East", "Central City", "Deer Valley", "Desert View", "Encanto",
			"Estrella", "Laveen", "Maryvale", "North Gateway", "North Mountain", "Rio Vista", "South Mountain", "Arcadia",
		},
		rail = {
			"Metro Parkway",
		},
		airport = {
			"Sky Harbor Airport", "Deer Valley Airport",
		},
	},
	["Tucson"] = {
		streets = {
			"Speedway Boulevard", "Broadway Boulevard", "Congress Street", "Stone Avenue", "Oracle Road", "Grant Road",
			"Campbell Avenue", "Swan Road", "Craycroft Road", "Kolb Road", "Alvernon Way", "Country Club Road",
			"22nd Street", "6th Avenue", "4th Avenue", "Park Avenue", "Euclid Avenue", "Miracle Mile", "Fort Lowell Road",
			"Pima Street", "Valencia Road", "Ajo Way", "Irvington Road", "Golf Links Road", "Tanque Verde Road",
			"Wilmot Road", "Silverbell Road", "Mission Road", "Pennington Street", "Toole Avenue", "University Boulevard",
			"Main Avenue", "Granada Avenue", "Church Avenue",
		},
		neighborhoods = {
			"El Presidio", "Barrio Viejo", "Armory Park", "Sam Hughes", "Dunbar Spring", "Iron Horse", "West University",
			"Pie Allen", "Rincon Heights", "Jefferson Park", "Colonia Solana", "El Encanto", "Menlo Park", "Barrio Anita",
			"Feldman's", "Miramonte", "Civano",
		},
		airport = {
			"Tucson International Airport",
		},
	},
	["Mesa"] = {
		streets = {
			"Main Street", "University Drive", "Broadway Road", "Southern Avenue", "Baseline Road", "Guadalupe Road",
			"McKellips Road", "Brown Road", "McDowell Road", "Country Club Drive", "Alma School Road", "Dobson Road",
			"Mesa Drive", "Stapley Drive", "Gilbert Road", "Lindsay Road", "Val Vista Drive", "Greenfield Road",
			"Higley Road", "Power Road", "Sossaman Road", "Ellsworth Road", "Signal Butte Road", "Center Street",
		},
		airport = {
			"Mesa Gateway Airport", "Falcon Field",
		},
	},
	["Chandler"] = {
		streets = {
			"Arizona Avenue", "Chandler Boulevard", "Ray Road", "Warner Road", "Elliot Road", "Pecos Road", "Germann Road",
			"Queen Creek Road", "Ocotillo Road", "Alma School Road", "Dobson Road", "McClintock Drive", "Kyrene Road",
			"Rural Road", "Price Road", "Cooper Road", "McQueen Road", "Gilbert Road", "Frye Road", "Commonwealth Avenue",
			"Boston Street", "Buffalo Street", "Chandler Heights Road", "Riggs Road",
		},
		airport = {
			"Chandler Municipal Airport",
		},
	},
	["Scottsdale"] = {
		streets = {
			"Scottsdale Road", "Camelback Road", "Indian School Road", "Hayden Road", "Pima Road", "Shea Boulevard",
			"McDonald Drive", "Chaparral Road", "Thomas Road", "McDowell Road", "Osborn Road", "Miller Road", "68th Street",
			"Via Linda", "Frank Lloyd Wright Boulevard", "Pinnacle Peak Road", "Cactus Road", "Thunderbird Road",
			"Raintree Drive", "Bell Road", "Main Street", "Marshall Way", "Stetson Drive", "Goldwater Boulevard",
			"Indian Bend Road", "Lincoln Drive", "Brown Avenue", "5th Avenue", "Dynamite Boulevard", "Granite Reef Road",
		},
		neighborhoods = {
			"Old Town", "McCormick Ranch", "Gainey Ranch", "DC Ranch", "Grayhawk", "Troon",
		},
		airport = {
			"Scottsdale Airport",
		},
	},
	["Gilbert"] = {
		streets = {
			"Gilbert Road", "Val Vista Drive", "Lindsay Road", "Higley Road", "Greenfield Road", "Recker Road",
			"Power Road", "Cooper Road", "McQueen Road", "Elliot Road", "Warner Road", "Ray Road", "Williams Field Road",
			"Pecos Road", "Germann Road", "Queen Creek Road", "Guadalupe Road", "Baseline Road", "Vaughn Avenue",
			"Page Avenue", "Santan Village Parkway", "Market Street",
		},
	},
	["Glendale"] = {
		streets = {
			"Glendale Avenue", "Northern Avenue", "Olive Avenue", "Peoria Avenue", "Bell Road", "Union Hills Drive",
			"Camelback Road", "Bethany Home Road", "Maryland Avenue", "51st Avenue", "59th Avenue", "67th Avenue",
			"75th Avenue", "83rd Avenue", "91st Avenue", "Grand Avenue", "Thunderbird Road", "Cactus Road",
			"Missouri Avenue", "Myrtle Avenue",
		},
		airport = {
			"Glendale Municipal Airport",
		},
	},
	["Tempe"] = {
		streets = {
			"Mill Avenue", "University Drive", "Rio Salado Parkway", "Apache Boulevard", "Broadway Road", "Southern Avenue",
			"Baseline Road", "Guadalupe Road", "Elliot Road", "Warner Road", "Rural Road", "McClintock Drive",
			"Priest Drive", "Hardy Drive", "Kyrene Road", "Lakeshore Drive", "Ash Avenue", "Farmer Avenue",
			"College Avenue", "5th Street", "6th Street", "Curry Road", "Washington Street", "Dorsey Lane", "Price Road",
			"Lemon Street", "Spence Avenue",
		},
	},
	["Peoria"] = {
		streets = {
			"83rd Avenue", "75th Avenue", "91st Avenue", "99th Avenue", "Lake Pleasant Parkway", "Happy Valley Road",
			"Bell Road", "Union Hills Drive", "Thunderbird Road", "Olive Avenue", "Peoria Avenue", "Grand Avenue",
			"Cactus Road", "Beardsley Road", "Pinnacle Peak Road", "Washington Street", "Northern Avenue",
			"Deer Valley Road", "Jomax Road", "El Mirage Road",
		},
	},
	["Flagstaff"] = {
		streets = {
			"Milton Road", "San Francisco Street", "Beaver Street", "Leroux Street", "Humphreys Street", "Aspen Avenue",
			"Birch Avenue", "Cherry Avenue", "Butler Avenue", "Fourth Street", "Country Club Drive", "Lake Mary Road",
			"Fort Valley Road", "Cedar Avenue", "Switzer Canyon Drive", "Lone Tree Road", "Phoenix Avenue",
			"University Avenue", "Elden Street", "Thompson Street", "Woodlands Village Boulevard",
		},
		airport = {
			"Pulliam Airport",
		},
	},
	["Yuma"] = {
		streets = {
			"4th Avenue", "Main Street", "1st Street", "8th Street", "16th Street", "24th Street", "32nd Street",
			"Avenue A", "Avenue B", "Pacific Avenue", "Araby Road", "Madison Avenue", "Orange Avenue", "Palo Verde Street",
			"Arizona Avenue", "Gila Street", "Maiden Lane", "Catalina Drive", "Avenue 3E", "Kennedy Lane",
		},
		airport = {
			"Yuma International Airport",
		},
	},
	["Prescott"] = {
		streets = {
			"Gurley Street", "Montezuma Street", "Cortez Street", "Marina Street", "Goodwin Street", "Sheldon Street",
			"Willow Creek Road", "Iron Springs Road", "Copper Basin Road", "Whipple Street", "Miller Valley Road",
			"Pleasant Street", "Mount Vernon Street", "Granite Street", "Prescott Lakes Parkway", "Senator Highway",
			"Rosser Street", "Grove Avenue", "Alarcon Street", "Carleton Street", "Union Street", "Park Avenue",
		},
		airport = {
			"Prescott Regional Airport",
		},
	},
	["Sedona"] = {
		streets = {
			"Jordan Road", "Schnebly Hill Road", "Soldier Pass Road", "Coffee Pot Drive", "Dry Creek Road", "Airport Road",
			"Brewer Road", "Ranger Road", "Forest Road", "Andante Drive", "Thunder Mountain Road", "Sunset Drive",
			"Mountain Shadows Drive", "Navoti Drive", "Northview Road", "Sanborn Drive",
		},
		airport = {
			"Sedona Airport",
		},
	},
	["Goodyear"] = {
		airport = { "Phoenix Goodyear Airport" },
	},
	["Williams"] = {
		rail = { "Williams Depot" },
	},
	["Grand Canyon Village"] = {
		rail = { "Grand Canyon Depot" },
	},
	["Tusayan"] = {
		airport = { "Grand Canyon Airport" },
	},
}
