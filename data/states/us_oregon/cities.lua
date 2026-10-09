-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## Oregon") instead of here.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name inside the city's admin
--                  boundary (directional prefix or quadrant suffix dropped: Portland's "Southeast Hawthorne
--                  Boulevard" ships as "Hawthorne Boulevard", Salem's "Commercial Street Southeast" as
--                  "Commercial Street"; OSM's "Junior" ships as "Jr").
--   neighborhoods  bus/tram stations. Portland: the City's Neighborhood Boundaries layer (portlandmaps.com
--                  COP_OpenData_Boundary/MapServer/3, 2026-10-08), neighbourhood associations only (no shared
--                  slash areas). Eugene: the City of Eugene EugNeighborhoods layer, area names (association
--                  suffix dropped; generic ones like Downtown/Northeast and River Road, also a street, left out).
--                  Salem: the City of Salem CD_Neighborhoods layer, area names. Bend: the City of Bend
--                  Neighborhood_Associations layer.
--   rail           passenger train stations, WITHOUT a trailing "Station". Series policy (D5): mainline and
--                  commuter first, then light rail. Amtrak (GTFS 2026-10-08): Portland's stop is Union Station;
--                  Salem, Albany, Eugene, Oregon City, Klamath Falls and Chemult are named after their town
--                  (engine default, no entry). TriMet WES and MAX (TriMet GTFS 2026-10-08): " MAX Station" and
--                  "TC" expanded/dropped, the part before the slash kept where it is a place name ("Hillsboro
--                  Central/SE 3rd TC" -> Hillsboro Central). Pure street or intersection names (NE 82nd Ave,
--                  SE 17th Ave & Holgate Blvd), slash pairs (Old Town/Chinatown, Delta Park/Vanport), a sponsor
--                  name (Providence Park), a mall (Pioneer Place) and names that are also neighbourhoods or towns
--                  (Hollywood, Goose Hollow, Kenton, Parkrose, Milwaukie, Tualatin, Wilsonville) are left out.
--   airport        airports/airfields: FAA names (NASR APT_BASE, cycle 2026-10-01) in their short common form,
--                  keyed to the town they are in (Portland-Hillsboro and Portland-Troutdale sit in Hillsboro and
--                  Troutdale). The Dalles' Columbia Gorge Regional is in Dallesport, Washington: left out.
--   harbor         none: Oregon's ferries are small county river car ferries (data_review.md).
-- Station names are unique map-wide; street names are unique per town.
return {
	["Portland"] = {
		streets = {
			"Burnside Street", "Broadway", "Hawthorne Boulevard", "Belmont Street", "Division Street", "Powell Boulevard",
			"Foster Road", "Sandy Boulevard", "Alberta Street", "Mississippi Avenue", "Killingsworth Street",
			"Lombard Street", "Interstate Avenue", "Williams Avenue", "Martin Luther King Jr Boulevard", "Grand Avenue",
			"Naito Parkway", "Barbur Boulevard", "Macadam Avenue", "Terwilliger Boulevard", "Capitol Highway",
			"Glisan Street", "Stark Street", "Morrison Street", "Yamhill Street", "Lovejoy Street", "Fremont Street",
			"Woodstock Boulevard", "23rd Avenue", "82nd Avenue",
		},
		neighborhoods = {
			"Pearl District", "Old Town", "Portland Downtown", "Northwest District", "Goose Hollow", "Lloyd", "Buckman",
			"Kerns", "Hosford-Abernethy", "Brooklyn", "Sellwood-Moreland", "Eastmoreland", "Woodstock", "Richmond",
			"Sunnyside", "Mt. Tabor", "Montavilla", "Laurelhurst", "Hollywood", "Irvington", "Alameda", "Beaumont-Wilshire",
			"Rose City Park", "Grant Park", "Concordia", "Cully", "King", "Sabin", "Vernon", "Eliot", "Boise", "Humboldt",
			"Overlook", "Arbor Lodge", "Kenton", "St. Johns", "Cathedral Park", "University Park", "Portsmouth", "Piedmont",
			"Woodlawn", "Lents", "Foster-Powell", "Mt. Scott-Arleta", "Brentwood-Darlington", "Hillsdale", "Multnomah",
			"South Portland", "Arlington Heights", "Linnton", "Hayden Island", "Parkrose", "Hazelwood",
		},
		rail = {
			"Union Station", "Rose Quarter Transit Center", "Gateway Transit Center", "Lloyd Center", "Convention Center",
			"Pioneer Square North", "Pioneer Square South", "Pioneer Courthouse", "Galleria", "Library", "Yamhill District",
			"City Hall", "PSU Urban Center", "PSU South", "South Waterfront", "Washington Park", "Cascades", "Overlook Park",
			"Rosa Parks", "Expo Center", "Lents Town Center",
		},
		airport = {
			"Portland International Airport",
		},
	},
	["Eugene"] = {
		streets = {
			"Willamette Street", "Franklin Boulevard", "Coburg Road", "11th Avenue", "13th Avenue", "18th Avenue",
			"Pearl Street", "Oak Street", "High Street", "Olive Street", "Charnelton Street", "Lincoln Street", "Broadway",
			"River Road", "Chambers Street", "Hilyard Street", "Agate Street", "Alder Street", "Jefferson Street",
			"Polk Street", "Blair Boulevard", "Amazon Parkway", "Delta Highway", "Cal Young Road", "Goodpasture Island Road",
			"Martin Luther King Jr Boulevard", "Garfield Street", "Roosevelt Boulevard", "Bailey Hill Road", "Crest Drive",
		},
		neighborhoods = {
			"Whiteaker", "Friendly", "Jefferson Westside", "Amazon", "Cal Young", "Churchill", "Fairmount", "Harlow",
			"Laurel Hill Valley", "Santa Clara", "South University", "West University", "Southwest Hills", "Trainsong",
			"Goodpasture Island", "West Eugene",
		},
		airport = {
			"Mahlon Sweet Field",
		},
	},
	["Salem"] = {
		streets = {
			"State Street", "Commercial Street", "Liberty Street", "High Street", "Church Street", "Winter Street",
			"Summer Street", "Capitol Street", "Court Street", "Center Street", "Marion Street", "Chemeketa Street",
			"Ferry Street", "Trade Street", "Mission Street", "Front Street", "Broadway Street", "Portland Road",
			"Lancaster Drive", "Market Street", "Silverton Road", "Kuebler Boulevard", "Wallace Road", "River Road",
			"Liberty Road", "Fairgrounds Road", "Cherry Avenue", "Hawthorne Avenue", "12th Street", "17th Street",
		},
		neighborhoods = {
			"Grant", "Highland", "Morningside", "Northgate", "Sunnyslope", "West Salem", "Faye Wright", "East Lancaster",
			"North Lancaster", "South Gateway", "Southeast Mill Creek", "Central Area", "South Central",
		},
		airport = {
			"Salem McNary Field",
		},
	},
	["Gresham"] = {
		streets = {
			"Powell Boulevard", "Division Street", "Burnside Road", "Stark Street", "Glisan Street", "Halsey Street",
			"Eastman Parkway", "Hogan Road", "Kane Drive", "Main Avenue", "Roberts Avenue", "Cleveland Avenue", "Hood Avenue",
			"Birdsdale Avenue", "Towle Avenue", "Palmquist Road", "Orient Drive", "182nd Avenue", "181st Avenue",
			"162nd Avenue", "Sandy Boulevard", "Powell Valley Road", "Highland Drive", "Pleasant View Drive", "Regner Road",
			"Barnes Road", "Walters Drive",
		},
		rail = {
			"Gresham Central Transit Center", "Gresham City Hall", "Civic Drive", "Ruby Junction", "Rockwood",
		},
	},
	["Hillsboro"] = {
		streets = {
			"Main Street", "Baseline Street", "Cornell Road", "Evergreen Parkway", "Cornelius Pass Road", "Brookwood Parkway",
			"Century Boulevard", "Tualatin Valley Highway", "Glencoe Road", "Shute Road", "Walker Road",
			"Jackson School Road", "Butler Street", "Oak Street", "Washington Street", "1st Avenue", "2nd Avenue",
			"10th Avenue", "Amberglen Parkway", "Orenco Station Parkway", "Quatama Street", "Minter Bridge Road",
			"River Road", "Witch Hazel Road", "Helvetia Road", "Lincoln Street", "Dawson Creek Drive",
		},
		rail = {
			"Hatfield Government Center", "Hillsboro Central", "Hillsboro Health District", "Orenco", "Quatama",
			"Hawthorn Farm", "Willow Creek",
		},
		airport = {
			"Portland-Hillsboro Airport",
		},
	},
	["Beaverton"] = {
		streets = {
			"Canyon Road", "Murray Boulevard", "Scholls Ferry Road", "Hall Boulevard", "Cedar Hills Boulevard",
			"Allen Boulevard", "Farmington Road", "Walker Road", "Jenkins Road", "Broadway Street", "Watson Avenue",
			"Hocken Avenue", "Lombard Avenue", "Western Avenue", "Beaverton Hillsdale Highway", "Barnes Road", "Cornell Road",
			"Denney Road", "Hart Road", "Davis Road", "Weir Road", "Barrows Road", "Merlo Road", "Brockman Street",
			"Greenway", "Garden Home Road", "5th Street", "Center Street",
		},
		rail = {
			"Beaverton Transit Center", "Sunset Transit Center", "Beaverton Central", "Beaverton Creek", "Millikan Way",
			"Elmonica",
		},
	},
	["Bend"] = {
		streets = {
			"Wall Street", "Bond Street", "Greenwood Avenue", "Franklin Avenue", "Newport Avenue", "Galveston Avenue",
			"Century Drive", "Mount Washington Drive", "Reed Market Road", "Butler Market Road", "Empire Avenue",
			"Division Street", "3rd Street", "27th Street", "15th Street", "8th Street", "Revere Avenue", "Olney Avenue",
			"Colorado Avenue", "Simpson Avenue", "Brookswood Boulevard", "Murphy Road", "Purcell Boulevard", "Neff Road",
			"Shevlin Park Road", "Skyliners Road", "Industrial Way", "Bear Creek Road", "Cooley Road", "Wilson Avenue",
		},
		neighborhoods = {
			"Awbrey Butte", "Boyd Acres", "Century West", "Larkspur", "Mountain View", "Old Bend", "Old Farm District",
			"Orchard District", "River West", "Southern Crossing", "Summit West", "Southeast Bend", "Southwest Bend",
		},
		airport = {
			"Bend Municipal Airport",
		},
	},
	["Medford"] = {
		streets = {
			"Main Street", "Central Avenue", "Riverside Avenue", "Jackson Street", "Biddle Road", "Crater Lake Avenue",
			"Crater Lake Highway", "McAndrews Road", "Barnett Road", "Stewart Avenue", "Garfield Street",
			"Siskiyou Boulevard", "Highland Drive", "Delta Waters Road", "Springbrook Road", "Foothill Road",
			"Table Rock Road", "Columbus Avenue", "Oakdale Avenue", "Holly Street", "Lozier Lane", "Kings Highway",
			"Center Drive", "Owen Drive", "Black Oak Drive", "Spring Street", "Court Street", "8th Street", "Hillcrest Road",
		},
		airport = {
			"Rogue Valley International Airport",
		},
	},
	["Corvallis"] = {
		streets = {
			"Monroe Avenue", "Harrison Boulevard", "Van Buren Avenue", "Jefferson Avenue", "Madison Avenue",
			"Western Boulevard", "Philomath Boulevard", "Circle Boulevard", "Walnut Boulevard", "Kings Boulevard",
			"Highland Drive", "9th Street", "3rd Street", "2nd Street", "4th Street", "5th Street", "15th Street",
			"26th Street", "29th Street", "35th Street", "53rd Street", "Buchanan Avenue", "Grant Avenue", "Garfield Avenue",
			"Witham Hill Drive", "Country Club Drive", "Brooklane Drive", "Conifer Boulevard", "Jackson Avenue",
			"Adams Avenue", "Washington Way",
		},
		airport = {
			"Corvallis Municipal Airport",
		},
	},
	["Albany"] = {
		streets = {
			"Pacific Boulevard", "Santiam Highway", "Main Street", "1st Avenue", "2nd Avenue", "Lyon Street",
			"Ellsworth Street", "Queen Avenue", "9th Avenue", "14th Avenue", "34th Avenue", "53rd Avenue", "Geary Street",
			"Waverly Drive", "Elm Street", "Hill Street", "Broadway Street", "Jackson Street", "Salem Avenue", "Water Avenue",
			"Knox Butte Road", "Gibson Hill Road", "Columbus Street", "Washington Street", "Calapooia Street",
			"Thurston Street", "Grand Prairie Road", "Ferry Street", "Oak Street",
		},
		airport = {
			"Albany Municipal Airport",
		},
	},
	["Astoria"] = {
		streets = {
			"Marine Drive", "Commercial Street", "Duane Street", "Exchange Street", "Bond Street", "Franklin Avenue",
			"Grand Avenue", "Irving Avenue", "Jerome Avenue", "Niagara Avenue", "Lexington Avenue", "Leif Erickson Drive",
			"Coxcomb Drive", "Olney Avenue", "Alameda Avenue", "Florence Avenue", "Harrison Avenue", "Madison Avenue",
			"Tongue Point Road", "Williamsport Road", "8th Street", "11th Street", "14th Street", "16th Street",
			"33rd Street",
		},
		airport = {
			"Astoria Regional Airport",
		},
	},
	["Ashland"] = {
		streets = {
			"Main Street", "Siskiyou Boulevard", "Ashland Street", "Lithia Way", "Mountain Avenue", "Oak Street",
			"Hersey Street", "A Street", "B Street", "Walker Avenue", "Tolman Creek Road", "Granite Street", "Pioneer Street",
			"Water Street", "Helman Street", "Wimer Street", "Iowa Street", "Beach Street", "Clay Street", "Normal Avenue",
			"Crowson Road", "Wightman Street", "1st Street", "3rd Street", "4th Street", "8th Street",
		},
		airport = {
			"Ashland Municipal Airport",
		},
	},
	["Aurora"] = {
		airport = {
			"Aurora State Airport",
		},
	},
	["Baker City"] = {
		airport = {
			"Baker City Municipal Airport",
		},
	},
	["Brookings"] = {
		airport = {
			"Brookings Airport",
		},
	},
	["Burns"] = {
		airport = {
			"Burns Municipal Airport",
		},
	},
	["Cascade Locks"] = {
		airport = {
			"Cascade Locks State Airport",
		},
	},
	["Cottage Grove"] = {
		airport = {
			"Cottage Grove State Airport",
		},
	},
	["Florence"] = {
		airport = {
			"Florence Municipal Airport",
		},
	},
	["Gold Beach"] = {
		airport = {
			"Gold Beach Municipal Airport",
		},
	},
	["Grants Pass"] = {
		airport = {
			"Grants Pass Airport",
		},
	},
	["Hermiston"] = {
		airport = {
			"Hermiston Municipal Airport",
		},
	},
	["Hood River"] = {
		airport = {
			"Ken Jernstedt Airfield",
		},
	},
	["Independence"] = {
		airport = {
			"Independence State Airport",
		},
	},
	["John Day"] = {
		airport = {
			"Grant County Regional Airport",
		},
	},
	["Klamath Falls"] = {
		airport = {
			"Crater Lake-Klamath Regional Airport",
		},
	},
	["La Grande"] = {
		airport = {
			"La Grande/Union County Airport",
		},
	},
	["Lakeview"] = {
		airport = {
			"Lake County Airport",
		},
	},
	["Lebanon"] = {
		airport = {
			"Lebanon State Airport",
		},
	},
	["Madras"] = {
		airport = {
			"Madras Municipal Airport",
		},
	},
	["McMinnville"] = {
		airport = {
			"McMinnville Municipal Airport",
		},
	},
	["Newport"] = {
		airport = {
			"Newport Municipal Airport",
		},
	},
	["North Bend"] = {
		airport = {
			"Southwest Oregon Regional Airport",
		},
	},
	["Ontario"] = {
		airport = {
			"Ontario Municipal Airport",
		},
	},
	["Pendleton"] = {
		airport = {
			"Eastern Oregon Regional Airport",
		},
	},
	["Prineville"] = {
		airport = {
			"Prineville Airport",
		},
	},
	["Redmond"] = {
		airport = {
			"Redmond Municipal Airport",
		},
	},
	["Roseburg"] = {
		airport = {
			"Roseburg Regional Airport",
		},
	},
	["Scappoose"] = {
		airport = {
			"Scappoose Airport",
		},
	},
	["Seaside"] = {
		airport = {
			"Seaside Municipal Airport",
		},
	},
	["Sunriver"] = {
		airport = {
			"Sunriver Airport",
		},
	},
	["Tigard"] = {
		rail = {
			"Tigard Transit Center",
		},
	},
	["Tillamook"] = {
		airport = {
			"Tillamook Airport",
		},
	},
	["Troutdale"] = {
		airport = {
			"Portland-Troutdale Airport",
		},
	},
}
