-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## New York") instead of here.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name (directional prefix or
--                  suffix dropped: "Erie Boulevard East" ships as "Erie Boulevard") inside the city's admin
--                  boundary. New York City streets use the OSM form ("5th Avenue", "42nd Street").
--   neighborhoods  bus/tram stations. New York City: NYC Planning's 2020 Neighborhood Tabulation Areas (NYC Open
--                  Data 9nt8-h7nd), split at the hyphens into the single neighbourhood names, all five boroughs.
--                  Buffalo, Rochester, Syracuse and Albany: the NYS GIS "NYS_Place_Points" layer
--                  (PLACETYPE = Neighborhood, 2026-10-08). Names that are also New York towns (Yorkville,
--                  Highland, Brighton, Whitehall) or rail stops are left out.
--   rail           passenger train stations, WITHOUT a trailing "Station". Series policy (D5): mainline and
--                  commuter first, then rapid transit with clean names. Names from the operators' GTFS feeds
--                  (stops.txt, 2026-10-08): MTA Metro-North and LIRR (Grand Central, Penn Station, Atlantic
--                  Terminal, Jamaica ...), Amtrak (Albany-Rensselaer, Rhinecliff, Croton-Harmon, Syracuse
--                  Regional Transportation Center; Exchange Street per amtrak.com/stations/bfx), the Staten
--                  Island Railway and a few subway stations whose names are unabbreviated and unique (Bowling
--                  Green, Borough Hall, City Hall ...), and NFTA Metro Rail in Buffalo ("Station" and sponsor
--                  suffixes dropped). Subway names with "St"/"Av" abbreviations, slashes or repeated numbers
--                  (86 St) are left out, as are names that are also neighbourhoods in the same city. "Harlem-125th
--                  Street" is mta.info's spelling (GTFS: "Harlem-125 St"). Amtrak stops named after their town
--                  are the engine default (no entry).
--   airport        airports/airfields: FAA names (NASR APT_BASE, cycle 2026-10-01) in their short common form,
--                  keyed to the FAA city where it is a Census place in the mod (JFK and LaGuardia under New
--                  York, Syracuse Hancock under Syracuse), else the town the field sits in (Buffalo Niagara under
--                  Cheektowaga, Long Island MacArthur under Ronkonkoma). Frederick Douglass/Greater Rochester
--                  International is over 40 bytes and ships as "Greater Rochester International Airport".
--   harbor         Staten Island Ferry terminals (siferry.com), the Governors Island ferry (Battery Maritime
--                  Building), NYC Ferry landings without slashes or brackets (ferry.nyc route pages), and the
--                  ports by their own names (Port of Albany, Port of Oswego, Port of Ogdensburg).
-- Station names are unique map-wide; street names are unique per town.
return {
	["New York"] = {
		streets = {
			"Broadway", "5th Avenue", "Park Avenue", "Madison Avenue", "Lexington Avenue", "Wall Street", "Canal Street",
			"Houston Street", "Bowery", "Delancey Street", "Bleecker Street", "42nd Street", "34th Street", "125th Street",
			"Amsterdam Avenue", "Riverside Drive", "Central Park West", "Flatbush Avenue", "Atlantic Avenue",
			"Eastern Parkway", "Ocean Parkway", "Bedford Avenue", "Grand Concourse", "Fordham Road", "Queens Boulevard",
			"Northern Boulevard", "Roosevelt Avenue", "Victory Boulevard", "Hylan Boulevard", "Fulton Street",
		},
		neighborhoods = {
			"Chelsea", "Chinatown", "East Harlem", "East Village", "Financial District", "Gramercy", "Greenwich Village",
			"Hamilton Heights", "Harlem", "Hell's Kitchen", "Inwood", "Lower East Side", "Morningside Heights", "Murray Hill",
			"SoHo", "Little Italy", "Tribeca", "Upper East Side", "Upper West Side", "Washington Heights", "West Village",
			"Midtown", "Battery Park City", "Kips Bay", "Sugar Hill", "Bay Ridge", "Bedford-Stuyvesant", "Bensonhurst",
			"Borough Park", "Brighton Beach", "Brooklyn Heights", "Brownsville", "Bushwick", "Canarsie", "Carroll Gardens",
			"Cobble Hill", "Red Hook", "Clinton Hill", "Coney Island", "Crown Heights", "DUMBO", "Dyker Heights", "Flatbush",
			"Fort Greene", "Greenpoint", "Park Slope", "Prospect Heights", "Sheepshead Bay", "Sunset Park", "Williamsburg",
			"Midwood", "Gravesend", "East New York", "Astoria", "Bayside", "Corona", "Elmhurst", "Flushing", "Forest Hills",
			"Jackson Heights", "Kew Gardens", "Long Island City", "Maspeth", "Middle Village", "Ozone Park", "Rego Park",
			"Richmond Hill", "Ridgewood", "Sunnyside", "Woodhaven", "Howard Beach", "Whitestone", "College Point",
			"Far Rockaway", "St. Albans", "Riverdale", "Mott Haven", "Hunts Point", "Fordham", "Belmont", "Morrisania",
			"Parkchester", "City Island", "Highbridge", "Throgs Neck", "Kingsbridge", "Pelham Bay", "Soundview",
			"Morris Park", "Co-op City", "Tremont", "West Farms", "St. George", "New Brighton", "Port Richmond", "Todt Hill",
			"Rosebank", "Stapleton", "Tottenville", "Great Kills", "New Dorp", "Annadale", "Huguenot", "Eltingville",
		},
		rail = {
			"Grand Central", "Penn Station", "Atlantic Terminal", "Jamaica", "Woodside", "Harlem-125th Street",
			"Hunterspoint Avenue", "Flushing Main Street", "Spuyten Duyvil", "Marble Hill", "Botanical Garden",
			"Williams Bridge", "University Heights", "Morris Heights", "Bowling Green", "Borough Hall", "City Hall",
			"Grand Army Plaza", "World Trade Center", "Queensboro Plaza", "Broadway Junction", "Pelham Bay Park",
			"Tompkinsville", "Grasmere", "Dongan Hills", "Oakwood Heights", "Grant City", "Pleasant Plains",
			"Richmond Valley", "Arthur Kill",
		},
		airport = {
			"John F. Kennedy International Airport", "LaGuardia Airport",
		},
		harbor = {
			"Whitehall Ferry Terminal", "St. George Ferry Terminal", "Battery Maritime Building", "Stuyvesant Cove",
			"Corlears Hook", "Brooklyn Navy Yard", "East 34th Street", "East 90th Street",
		},
	},
	["Buffalo"] = {
		streets = {
			"Main Street", "Delaware Avenue", "Elmwood Avenue", "Niagara Street", "Genesee Street", "Broadway",
			"Hertel Avenue", "Allen Street", "Chippewa Street", "Richmond Avenue", "Bailey Avenue", "Fillmore Avenue",
			"Jefferson Avenue", "Seneca Street", "South Park Avenue", "Abbott Road", "Kensington Avenue", "Grant Street",
			"Porter Avenue", "Lafayette Avenue", "Amherst Street", "Michigan Avenue", "Washington Street", "Court Street",
			"Pearl Street", "Franklin Street", "Ohio Street", "Elm Street", "Swan Street",
		},
		neighborhoods = {
			"Black Rock", "Broadway-Fillmore", "Kaisertown", "First Ward", "Hamlin Park", "Masten Park", "Schiller Park",
			"Riverside Park", "Parkside", "Columbus", "Lovejoy", "Delaware Park", "North Park", "South Park", "Babcock",
			"Emslie", "Grider", "Kingsley", "Starin Central", "Front Park", "Cazenovia Park", "Willert Park",
			"Abbott McKinley", "Genesee Moselle",
		},
		rail = {
			"Exchange Street", "Canalside", "Fountain Plaza", "Lafayette", "Humboldt", "Summer-Best", "LaSalle",
			"Delavan-Canisius College", "Allen-Medical Campus", "Amherst",
		},
	},
	["Rochester"] = {
		streets = {
			"Main Street", "East Avenue", "Monroe Avenue", "Park Avenue", "University Avenue", "Lake Avenue", "State Street",
			"Clinton Avenue", "Genesee Street", "Lyell Avenue", "Dewey Avenue", "Culver Road", "Goodman Street",
			"Winton Road", "South Avenue", "Mount Hope Avenue", "Exchange Boulevard", "Broad Street", "Chestnut Street",
			"Alexander Street", "Plymouth Avenue", "Joseph Avenue", "Portland Avenue", "Hudson Avenue", "Elmwood Avenue",
			"Norton Street", "Ridgeway Avenue", "Thurston Road", "Jefferson Avenue", "Saint Paul Street",
		},
		neighborhoods = {
			"19th Ward", "Beechwood", "Browncroft", "Charlotte", "Cobbs Hill", "Corn Hill", "Dutchtown", "Edgerton",
			"Ellwanger-Barry", "Maplewood", "Swillburg", "South Wedge", "Upper Falls", "Homestead Heights",
			"Northland-Lyceum", "Brown Square", "Lyell-Otis", "Mayor's Heights", "Genesee-Jefferson", "Plymouth-Exchange",
			"Susan B Anthony", "Atlantic-University", "Culver-Winton", "North Marketview Heights",
		},
		airport = {
			"Greater Rochester International Airport",
		},
	},
	["Syracuse"] = {
		streets = {
			"Salina Street", "Erie Boulevard", "Genesee Street", "James Street", "Warren Street", "Fayette Street",
			"Water Street", "Clinton Street", "Montgomery Street", "State Street", "Townsend Street", "Burnet Avenue",
			"Teall Avenue", "Westcott Street", "Euclid Avenue", "Comstock Avenue", "Crouse Avenue", "University Avenue",
			"Adams Street", "Harrison Street", "Onondaga Avenue", "Geddes Street", "Butternut Street", "Court Street",
			"Grant Boulevard", "Midland Avenue", "Colvin Street", "Brighton Avenue", "Hiawatha Boulevard", "Thompson Road",
		},
		neighborhoods = {
			"Eastwood", "Strathmore", "Salt Springs", "Lincoln Park", "Meadowbrook", "Elmwood", "Near Westside", "Northside",
			"Skunk City", "University Hill", "Washington Square", "Outer Comstock", "Lakefront", "Near Eastside",
		},
		rail = {
			"Syracuse Regional Transportation Center",
		},
		airport = {
			"Syracuse Hancock International Airport",
		},
	},
	["Albany"] = {
		streets = {
			"State Street", "Washington Avenue", "Central Avenue", "Madison Avenue", "Pearl Street", "Broadway",
			"Lark Street", "Eagle Street", "Swan Street", "Delaware Avenue", "New Scotland Avenue", "Western Avenue",
			"Quail Street", "Morton Avenue", "Clinton Avenue", "Northern Boulevard", "Lexington Avenue", "Hudson Avenue",
			"Beaver Street", "Chapel Street", "Dove Street", "Henry Johnson Boulevard", "Manning Boulevard", "Everett Road",
			"Whitehall Road", "Livingston Avenue", "Elk Street", "Hamilton Street",
		},
		neighborhoods = {
			"Arbor Hill", "Center Square", "Pine Hills", "Park South", "South End", "Sheridan Hollow", "Helderberg",
			"West Hill", "Normanskill", "Bishop's Gate", "Mansion Area",
		},
		airport = {
			"Albany International Airport",
		},
		harbor = {
			"Port of Albany",
		},
	},
	["Yonkers"] = {
		streets = {
			"Broadway", "Warburton Avenue", "Palisade Avenue", "Ashburton Avenue", "Nepperhan Avenue", "Riverdale Avenue",
			"McLean Avenue", "Yonkers Avenue", "Central Park Avenue", "Tuckahoe Road", "Saw Mill River Road", "Main Street",
			"Lockwood Avenue", "Park Avenue", "Mile Square Road", "Bronx River Road", "Kimball Avenue", "Midland Avenue",
			"Prospect Street", "Elm Street", "Lake Avenue", "Hawthorne Avenue", "Odell Avenue", "Roberts Avenue",
			"Ludlow Street", "Valentine Lane", "Executive Boulevard", "Bronxville Road",
		},
		rail = {
			"Ludlow", "Glenwood", "Greystone",
		},
	},
	["Ithaca"] = {
		streets = {
			"State Street", "Cayuga Street", "Aurora Street", "Tioga Street", "Buffalo Street", "Seneca Street",
			"Green Street", "Court Street", "Fulton Street", "Meadow Street", "College Avenue", "Dryden Road",
			"Stewart Avenue", "University Avenue", "Cascadilla Street", "Linn Street", "Hudson Street", "Albany Street",
			"Plain Street", "Spencer Road", "Elmira Road", "Mitchell Street", "Hector Street", "Cliff Street",
			"Taughannock Boulevard", "Lake Street", "Giles Street", "Willard Way", "Oak Avenue", "Eddy Street",
		},
		airport = {
			"Ithaca Tompkins International Airport",
		},
	},
	["Schenectady"] = {
		streets = {
			"State Street", "Erie Boulevard", "Union Street", "Nott Terrace", "Broadway", "Liberty Street", "Jay Street",
			"Front Street", "Washington Avenue", "Lafayette Street", "Clinton Street", "Van Vranken Avenue",
			"Eastern Parkway", "Union Avenue", "Brandywine Avenue", "Albany Street", "Crane Street", "Altamont Avenue",
			"Campbell Avenue", "McClellan Street", "Wendell Avenue", "Ferry Street", "Church Street", "Green Street",
			"Fehr Avenue", "Hamilton Street", "Lenox Road", "Rugby Road", "Avenue A",
		},
		airport = {
			"Schenectady County Airport",
		},
	},
	["Utica"] = {
		streets = {
			"Genesee Street", "Bleecker Street", "Oriskany Street", "Columbia Street", "Court Street", "Main Street",
			"Broad Street", "John Street", "Seneca Street", "Mohawk Street", "Sunset Avenue", "Burrstone Road", "French Road",
			"Oneida Street", "Rutger Street", "Elm Street", "Kemble Street", "Champlin Avenue", "Whitesboro Street",
			"Varick Street", "Hopper Street", "Holland Avenue", "Erie Street", "Albany Street", "Herkimer Road",
			"Noyes Street", "Culver Avenue", "Park Avenue",
		},
	},
	["Binghamton"] = {
		streets = {
			"Court Street", "Main Street", "Front Street", "Washington Street", "State Street", "Hawley Street",
			"Henry Street", "Chenango Street", "Conklin Avenue", "Vestal Avenue", "Riverside Drive", "Leroy Street",
			"Robinson Street", "Clinton Street", "Oak Street", "Water Street", "Carroll Street", "Exchange Street",
			"Susquehanna Street", "Prospect Street", "Glenwood Avenue", "Mygatt Street", "Pennsylvania Avenue",
			"Moeller Street", "Grand Avenue", "Murray Street", "Lewis Street", "Tompkins Street", "Seminary Avenue",
			"Laurel Avenue",
		},
		airport = {
			"Greater Binghamton Airport",
		},
	},
	["Saratoga Springs"] = {
		streets = {
			"Broadway", "Union Avenue", "Lake Avenue", "Caroline Street", "Phila Street", "Spring Street", "Circular Street",
			"Nelson Avenue", "Church Street", "Washington Street", "Congress Street", "Division Street", "Henry Street",
			"Putnam Street", "Excelsior Avenue", "West Avenue", "Maple Avenue", "Ballston Avenue", "Clinton Street",
			"Woodlawn Avenue", "East Avenue", "Regent Street", "York Avenue", "Grand Avenue", "Van Dam Street",
			"Franklin Street", "Railroad Place", "Lincoln Avenue", "Crescent Avenue", "Jefferson Street",
		},
		airport = {
			"Saratoga County Airport",
		},
	},
	["Niagara Falls"] = {
		streets = {
			"Main Street", "Pine Avenue", "Niagara Street", "Rainbow Boulevard", "Falls Street", "Old Falls Street",
			"Portage Road", "Military Road", "Highland Avenue", "Hyde Park Boulevard", "Lockport Road", "Buffalo Avenue",
			"Ferry Avenue", "Walnut Avenue", "Ontario Avenue", "Cleveland Avenue", "Linwood Avenue", "Willow Avenue",
			"3rd Street", "Whirlpool Street", "Packard Road", "Cudaback Avenue", "College Avenue", "Garrett Avenue",
			"Michigan Avenue", "Haeberle Avenue", "1st Street", "Cedar Avenue", "Niagara Scenic Parkway",
		},
		airport = {
			"Niagara Falls International Airport",
		},
	},
	["Troy"] = {
		streets = {
			"River Street", "Fulton Street", "Broadway", "4th Street", "5th Avenue", "Congress Street", "Ferry Street",
			"State Street", "Hoosick Street", "Pawling Avenue", "Burdett Avenue", "Oakwood Avenue", "2nd Street",
			"3rd Street", "Federal Street", "Grand Street", "Washington Street", "Liberty Street", "Adams Street",
			"Peoples Avenue", "Sage Avenue", "15th Street", "Pinewoods Avenue", "Spring Avenue", "Campbell Avenue",
			"Glen Avenue", "King Street", "Hutton Street", "Middleburgh Street", "Canal Avenue",
		},
	},
	["Rensselaer"] = {
		rail = {
			"Albany-Rensselaer",
		},
	},
	["Rhinebeck"] = {
		rail = {
			"Rhinecliff",
		},
	},
	["Croton-on-Hudson"] = {
		rail = {
			"Croton-Harmon",
		},
	},
	["Sleepy Hollow"] = {
		rail = {
			"Philipse Manor",
		},
	},
	["Mount Vernon"] = {
		rail = {
			"Fleetwood",
		},
	},
	["Elmont"] = {
		rail = {
			"Belmont Park",
		},
	},
	["Garden City"] = {
		rail = {
			"Nassau Boulevard", "Country Life Press",
		},
	},
	["Cheektowaga"] = {
		airport = {
			"Buffalo Niagara International Airport",
		},
	},
	["Ronkonkoma"] = {
		airport = {
			"Long Island MacArthur Airport",
		},
	},
	["Farmingdale"] = {
		airport = {
			"Republic Airport",
		},
	},
	["New Windsor"] = {
		airport = {
			"Stewart International Airport",
		},
	},
	["Big Flats"] = {
		airport = {
			"Elmira Corning Regional Airport",
		},
	},
	["Plattsburgh"] = {
		airport = {
			"Plattsburgh International Airport",
		},
	},
	["Saranac Lake"] = {
		airport = {
			"Adirondack Regional Airport",
		},
	},
	["Ogdensburg"] = {
		airport = {
			"Ogdensburg International Airport",
		},
		harbor = {
			"Port of Ogdensburg",
		},
	},
	["Massena"] = {
		airport = {
			"Massena International Airport",
		},
	},
	["Watertown"] = {
		airport = {
			"Watertown International Airport",
		},
	},
	["Westhampton Beach"] = {
		airport = {
			"Francis S. Gabreski Airport",
		},
	},
	["East Hampton"] = {
		airport = {
			"East Hampton Town Airport",
		},
	},
	["Rome"] = {
		airport = {
			"Griffiss International Airport",
		},
	},
	["Lake Placid"] = {
		airport = {
			"Lake Placid Airport",
		},
	},
	["Jamestown"] = {
		airport = {
			"Chautauqua County-Jamestown Airport",
		},
	},
	["Poughkeepsie"] = {
		airport = {
			"Hudson Valley Regional Airport",
		},
	},
	["Monticello"] = {
		airport = {
			"Sullivan County International Airport",
		},
	},
	["Montauk"] = {
		airport = {
			"Montauk Airport",
		},
	},
	["White Plains"] = {
		airport = {
			"Westchester County Airport",
		},
	},
	["Glens Falls"] = {
		airport = {
			"Floyd Bennett Memorial Airport",
		},
	},
	["Shirley"] = {
		airport = {
			"Brookhaven Airport",
		},
	},
	["Montgomery"] = {
		airport = {
			"Orange County Airport",
		},
	},
	["Batavia"] = {
		airport = {
			"Genesee County Airport",
		},
	},
	["Endicott"] = {
		airport = {
			"Tri-Cities Airport",
		},
	},
	["Oneonta"] = {
		airport = {
			"Albert S. Nader Regional Airport",
		},
	},
	["Hudson"] = {
		airport = {
			"Columbia County Airport",
		},
	},
	["Seneca Falls"] = {
		airport = {
			"Finger Lakes Regional Airport",
		},
	},
	["Kingston"] = {
		airport = {
			"Kingston-Ulster Airport",
		},
	},
	["Olean"] = {
		airport = {
			"Cattaraugus County-Olean Airport",
		},
	},
	["Oswego"] = {
		harbor = {
			"Port of Oswego",
		},
	},
}
