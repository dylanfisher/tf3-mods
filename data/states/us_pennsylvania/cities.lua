-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## Pennsylvania") instead of here.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name inside the city's admin
--                  boundary (directional prefix or suffix dropped: "North Broad Street" ships as "Broad Street",
--                  "East Carson Street" as "Carson Street"; OSM's "Junior" ships as "Jr"). Allentown's
--                  "Emaus Avenue" keeps the signed one-m spelling.
--   neighborhoods  bus/tram stations. Philadelphia: the City's "neighborhoods" layer (services.arcgis.com
--                  fLeGjb7u4uXqeF9q, MAPNAME, 2026-10-08). Pittsburgh: the City's PGHWebNeighborhoods layer
--                  (WPRDC, the 90 official neighbourhoods). Names that are also Pennsylvania towns (Tioga,
--                  Manchester, Knoxville, Allentown) or rail stops are left out; Point Breeze ships only for
--                  Pittsburgh, Spring Garden and Overbrook only for Philadelphia (station names are unique).
--   rail           passenger train stations, WITHOUT a trailing "Station". Series policy (D5): mainline and
--                  commuter first, then rapid transit with clean names. Amtrak (GTFS 2026-10-08; Great American
--                  Stations pages): Philadelphia's William H. Gray III 30th Street Station ships in the short
--                  common form "30th Street"; Pittsburgh's is Union Station, Harrisburg's the Harrisburg
--                  Transportation Center; the other Keystone/Pennsylvanian stops are named after their town
--                  (engine default, no entry). SEPTA Regional Rail and Metro (GTFS release v202609271): "St"/"Av"/
--                  "Ln" expanded (Chelten Avenue, Queen Lane), "Transit Center" as SEPTA writes it; intersection
--                  names (Broad-Girard, 8th-Market), slash names (15th St/City Hall), numbered streets (52nd St),
--                  hyphenated station pairs (Jenkintown-Wyncote), naming-rights names (NRG, Penn Medicine) and
--                  names that are also neighbourhoods or towns (Manayunk, East Falls, Tioga, Erie, Huntingdon,
--                  Somerset) are left out. Pittsburgh Regional Transit light rail (rideprt.org GTFS): stop names
--                  title-cased, street-only stops left out. Steamtown National Historic Site (nps.gov/stea), the
--                  steam excursion base in Scranton. Strasburg Rail Road: no station name on its site (data_review).
--   airport        airports/airfields: FAA names (NASR APT_BASE, cycle 2026-10-01) in their short common form,
--                  keyed to the FAA city where it is a town in the mod (Philadelphia International, Pittsburgh
--                  International, Harrisburg International and Lehigh Valley International sit in townships next to
--                  Philadelphia, Pittsburgh, Harrisburg and Allentown). Wilkes-Barre/Scranton International is over
--                  40 bytes without the slash and is left out (data_review).
--   harbor         Penn's Landing (RiverLink Ferry to Camden, riverlinkferry.com) and Dobbins Landing (Presque
--                  Isle Water Taxi, porterie.org), both seasonal passenger ferries.
-- Station names are unique map-wide; street names are unique per town.
return {
	["Philadelphia"] = {
		streets = {
			"Broad Street", "Market Street", "Chestnut Street", "Walnut Street", "Spruce Street", "Pine Street",
			"Locust Street", "South Street", "Arch Street", "Race Street", "Vine Street", "Spring Garden Street",
			"Girard Avenue", "Lehigh Avenue", "Allegheny Avenue", "Roosevelt Boulevard", "Frankford Avenue",
			"Germantown Avenue", "Ridge Avenue", "Passyunk Avenue", "Kelly Drive", "Lincoln Drive",
			"Benjamin Franklin Parkway", "Christopher Columbus Boulevard", "Washington Avenue", "Oregon Avenue",
			"Cottman Avenue", "Castor Avenue", "Baltimore Avenue", "Lancaster Avenue",
		},
		neighborhoods = {
			"Old City", "Society Hill", "Rittenhouse", "Logan Square", "Washington Square West", "Chinatown", "Queen Village",
			"Bella Vista", "Northern Liberties", "Old Kensington", "East Kensington", "Port Richmond", "Fairmount",
			"Spring Garden", "Brewerytown", "Francisville", "Graduate Hospital", "Passyunk Square", "East Passyunk",
			"Pennsport", "Girard Estates", "Grays Ferry", "University City", "Powelton", "Spruce Hill", "Cedar Park",
			"Kingsessing", "Eastwick", "Manayunk", "Roxborough", "East Falls", "Chestnut Hill", "West Mount Airy",
			"East Mount Airy", "Southwest Germantown", "Nicetown", "Strawberry Mansion", "Hunting Park", "Olney", "Logan",
			"Frankford", "Bridesburg", "Tacony", "Mayfair", "Holmesburg", "Fox Chase", "Bustleton", "Somerton", "Rhawnhurst",
			"Oxford Circle", "Wynnefield", "Overbrook", "Cobbs Creek", "Navy Yard", "Fitler Square", "Callowhill", "Andorra",
		},
		rail = {
			"30th Street", "Suburban Station", "Jefferson", "North Philadelphia", "Temple University", "Wayne Junction",
			"Chestnut Hill East", "Chestnut Hill West", "Holmesburg Junction", "Fern Rock Transit Center",
			"Frankford Transit Center", "Olney Transit Center", "Arrott Transit Center", "Cecil B. Moore", "Wissahickon",
			"Queen Lane", "Chelten Avenue", "Tulpehocken", "Upsal", "Richard Allen Lane", "St. Martins", "Wister", "Stenton",
			"Sedgwick", "Gravers", "Wyndmoor", "Torresdale", "Lawndale", "Ryers", "Angora", "Berks", "Snyder",
		},
		airport = {
			"Philadelphia International Airport", "Northeast Philadelphia Airport",
		},
		harbor = {
			"Penn's Landing",
		},
	},
	["Pittsburgh"] = {
		streets = {
			"Liberty Avenue", "Penn Avenue", "Smithfield Street", "Grant Street", "Forbes Avenue", "Fifth Avenue",
			"Butler Street", "Carson Street", "Baum Boulevard", "Centre Avenue", "Murray Avenue", "Walnut Street",
			"Bigelow Boulevard", "Boulevard of the Allies", "Fort Pitt Boulevard", "Brownsville Road", "Banksville Road",
			"Saw Mill Run Boulevard", "Stanwix Street", "Highland Avenue", "Negley Avenue", "Ellsworth Avenue",
			"Craig Street", "Frankstown Avenue", "Ohio Street", "Grandview Avenue", "Shady Avenue", "Beechwood Boulevard",
			"Second Avenue",
		},
		neighborhoods = {
			"Strip District", "Lower Lawrenceville", "Central Lawrenceville", "Upper Lawrenceville", "Shadyside",
			"Squirrel Hill North", "Squirrel Hill South", "North Oakland", "Central Oakland", "South Oakland", "West Oakland",
			"Bloomfield", "Polish Hill", "Mount Washington", "Duquesne Heights", "South Side Flats", "South Side Slopes",
			"Hazelwood", "Homewood North", "Homewood South", "East Liberty", "Point Breeze", "Highland Park", "Troy Hill",
			"Brookline", "Beechview", "Carrick", "Greenfield", "Garfield", "Friendship", "Morningside", "Stanton Heights",
			"Larimer", "Regent Square", "Swisshelm Park", "Allegheny West", "Allegheny Center", "Central Northside",
			"North Shore", "Brighton Heights", "Perry North", "Sheraden", "Crafton Heights", "Elliott", "West End",
			"Banksville", "Upper Hill", "Middle Hill", "Bluff", "Chateau", "Fineview", "Lincoln Place",
		},
		rail = {
			"Union Station", "Steel Plaza", "Wood Street", "Gateway", "First Avenue", "Station Square", "Allegheny",
			"North Side", "South Hills Junction", "South Bank", "Palm Garden", "Fallowfield", "McNeilly", "Bon Air",
		},
		airport = {
			"Pittsburgh International Airport", "Allegheny County Airport",
		},
	},
	["Allentown"] = {
		streets = {
			"Hamilton Street", "Tilghman Street", "Union Boulevard", "Lehigh Street", "Cedar Crest Boulevard", "7th Street",
			"Linden Street", "Chew Street", "Gordon Street", "Walnut Street", "Liberty Street", "Turner Street",
			"Allen Street", "Emaus Avenue", "Hanover Avenue", "Sumner Avenue", "Martin Luther King Jr Drive",
			"Susquehanna Street", "15th Street", "19th Street", "Fountain Street", "Union Street", "Basin Street",
			"American Parkway", "Washington Street", "Ott Street",
		},
		airport = {
			"Lehigh Valley International Airport",
		},
	},
	["Erie"] = {
		streets = {
			"State Street", "Peach Street", "Parade Street", "French Street", "Holland Street", "Sassafras Street",
			"Myrtle Street", "Bayfront Parkway", "Liberty Street", "Cherry Street", "Pine Avenue", "Buffalo Road",
			"12th Street", "26th Street", "38th Street", "Greengarden Boulevard", "Cascade Street", "Raspberry Street",
			"Chestnut Street", "Walnut Street", "Plum Street", "Wayne Street", "Ash Street", "Grandview Boulevard",
			"Front Street", "East Avenue", "Broad Street",
		},
		airport = {
			"Erie International Airport",
		},
		harbor = {
			"Dobbins Landing",
		},
	},
	["Reading"] = {
		streets = {
			"Penn Street", "Washington Street", "Court Street", "Franklin Street", "5th Street", "Perkiomen Avenue",
			"Schuylkill Avenue", "Centre Avenue", "Buttonwood Street", "Spring Street", "Greenwich Street", "Douglass Street",
			"Walnut Street", "Cherry Street", "Chestnut Street", "Bingaman Street", "Hampden Boulevard", "Pershing Boulevard",
			"Mineral Spring Road", "Lancaster Avenue", "Elm Street", "Oley Street", "Robeson Street", "Exeter Street",
			"Rockland Street", "9th Street", "11th Street", "13th Street", "Museum Road", "Kenhorst Boulevard",
		},
		airport = {
			"Reading Regional Airport",
		},
	},
	["Scranton"] = {
		streets = {
			"Lackawanna Avenue", "Wyoming Avenue", "Linden Street", "Mulberry Street", "Adams Avenue", "Jefferson Avenue",
			"Washington Avenue", "Penn Avenue", "Main Avenue", "Keyser Avenue", "Moosic Street", "Cedar Avenue",
			"Pittston Avenue", "Meadow Avenue", "Prospect Avenue", "Green Ridge Street", "Sanderson Avenue",
			"Providence Road", "Electric Street", "Market Street", "Luzerne Street", "Jackson Street", "Oak Street",
			"Capouse Avenue", "Olive Street", "Vine Street", "Gibson Street", "Hemlock Street", "Court Street",
		},
		rail = {
			"Steamtown National Historic Site",
		},
	},
	["Harrisburg"] = {
		streets = {
			"Market Street", "Front Street", "2nd Street", "3rd Street", "State Street", "Walnut Street", "Chestnut Street",
			"Forster Street", "Maclay Street", "Derry Street", "Cameron Street", "Paxton Street", "Herr Street",
			"Verbeke Street", "Division Street", "Reily Street", "Calder Street", "Green Street", "North Street",
			"Locust Street", "Pine Street", "Mulberry Street", "Susquehanna Street", "Kelker Street", "Hamilton Street",
			"Commonwealth Avenue", "6th Street",
		},
		rail = {
			"Harrisburg Transportation Center",
		},
		airport = {
			"Harrisburg International Airport", "Capital City Airport",
		},
	},
	["Lancaster"] = {
		streets = {
			"King Street", "Queen Street", "Duke Street", "Prince Street", "Orange Street", "Chestnut Street",
			"Walnut Street", "Lemon Street", "James Street", "Lime Street", "Vine Street", "Mulberry Street", "Water Street",
			"Christian Street", "Manor Street", "New Holland Avenue", "Columbia Avenue", "Harrisburg Avenue",
			"Marietta Avenue", "Strawberry Street", "Ann Street", "Plum Street", "Fremont Street", "Farnum Street",
			"Conestoga Street", "Church Street", "Frederick Street", "Charlotte Street", "Liberty Street", "Ruby Street",
		},
		airport = {
			"Lancaster Airport",
		},
	},
	["Bethlehem"] = {
		streets = {
			"Main Street", "Broad Street", "Union Boulevard", "New Street", "3rd Street", "4th Street", "Linden Street",
			"Stefko Boulevard", "Church Street", "Market Street", "Wyandotte Street", "Brodhead Avenue", "Elizabeth Avenue",
			"Center Street", "Schoenersville Road", "Easton Avenue", "Macada Road", "Eaton Avenue", "Pembroke Road",
			"Polk Street", "Packer Avenue", "Mechanic Street", "Spring Street", "8th Avenue", "Wood Street", "High Street",
			"Prospect Avenue",
		},
	},
	["State College"] = {
		streets = {
			"College Avenue", "Beaver Avenue", "Atherton Street", "Allen Street", "Pugh Street", "Fraser Street",
			"Garner Street", "Locust Lane", "Burrowes Street", "Hamilton Avenue", "Calder Way", "Foster Avenue",
			"Nittany Avenue", "Park Avenue", "Highland Avenue", "Westerly Parkway", "Easterly Parkway", "University Drive",
			"Whitehall Road", "Curtin Road", "Waupelani Drive", "Holmes Street", "McKee Street", "Hetzel Street",
			"Sparks Street", "Prospect Avenue", "Fairmount Avenue", "Branch Road", "Southgate Drive", "Corl Street",
		},
		airport = {
			"State College Regional Airport",
		},
	},
	["Altoona"] = {
		streets = {
			"Plank Road", "7th Avenue", "Union Avenue", "17th Street", "58th Street", "Pleasant Valley Boulevard",
			"Broad Avenue", "Chestnut Avenue", "Juniata Gap Road", "6th Avenue", "8th Avenue", "12th Avenue", "Beale Avenue",
			"Lexington Avenue", "Margaret Avenue", "Washington Avenue", "Green Avenue", "4th Avenue", "31st Street",
			"Logan Boulevard", "Crawford Avenue", "Walton Avenue", "11th Avenue", "13th Avenue", "Fairview Avenue",
			"Wopsononock Avenue", "Broadway", "Bell Avenue", "Ward Avenue",
		},
		airport = {
			"Altoona Blair County Airport",
		},
	},
	["Wilkes-Barre"] = {
		streets = {
			"Public Square", "Market Street", "Main Street", "River Street", "Franklin Street", "Washington Street",
			"Northampton Street", "Wilkes-Barre Boulevard", "Hazle Street", "Carey Avenue", "Kidder Street", "Scott Street",
			"Wyoming Street", "Academy Street", "Ross Street", "Dana Street", "Grant Street", "Parrish Street",
			"Sambourne Street", "Coal Street", "Blackman Street", "Union Street", "Pennsylvania Avenue", "Barney Street",
			"Old River Road", "South Street", "North Street", "Hanover Street", "Mundy Street", "Butler Street",
		},
		airport = {
			"Wilkes-Barre Wyoming Valley Airport",
		},
	},
	["York"] = {
		streets = {
			"Market Street", "George Street", "Duke Street", "Beaver Street", "Queen Street", "Philadelphia Street",
			"King Street", "Princess Street", "Pershing Avenue", "Penn Street", "Richland Avenue", "Roosevelt Avenue",
			"Carlisle Avenue", "Kings Mill Road", "Belvidere Avenue", "Prospect Street", "Pattison Street", "Broad Street",
			"Linden Avenue", "College Avenue", "Jackson Street", "Maple Street", "Locust Street", "Arch Street", "Gay Avenue",
			"Hartley Street", "Newberry Street", "Hay Street",
		},
		airport = {
			"York Airport",
		},
	},
	["Ardmore"] = {
		rail = {
			"Ardmore Junction",
		},
	},
	["Beaver Falls"] = {
		airport = {
			"Beaver County Airport",
		},
	},
	["Bedford"] = {
		airport = {
			"Bedford County Airport",
		},
	},
	["Bethel Park"] = {
		rail = {
			"South Hills Village", "Washington Junction", "Bethel Village",
		},
	},
	["Bradford"] = {
		airport = {
			"Bradford Regional Airport",
		},
	},
	["Butler"] = {
		airport = {
			"Butler Regional Airport",
		},
	},
	["Carlisle"] = {
		airport = {
			"Carlisle Airport",
		},
	},
	["Chester"] = {
		rail = {
			"Chester Transit Center",
		},
	},
	["Clarion"] = {
		airport = {
			"Clarion County Airport",
		},
	},
	["Clearfield"] = {
		airport = {
			"Clearfield-Lawrence Airport",
		},
	},
	["Coatesville"] = {
		airport = {
			"Chester County Airport",
		},
	},
	["Corry"] = {
		airport = {
			"Corry-Lawrence Airport",
		},
	},
	["Dormont"] = {
		rail = {
			"Dormont Junction", "Potomac",
		},
	},
	["Doylestown"] = {
		airport = {
			"Doylestown Airport",
		},
	},
	["DuBois"] = {
		airport = {
			"DuBois Regional Airport",
		},
	},
	["Franklin"] = {
		airport = {
			"Venango Regional Airport",
		},
	},
	["Grove City"] = {
		airport = {
			"Grove City Airport",
		},
	},
	["Hazleton"] = {
		airport = {
			"Hazleton Regional Airport",
		},
	},
	["Indiana"] = {
		airport = {
			"Indiana County Airport",
		},
	},
	["Johnstown"] = {
		airport = {
			"Johnstown Cambria County Airport",
		},
	},
	["King of Prussia"] = {
		rail = {
			"Hughes Park",
		},
	},
	["Lansdale"] = {
		rail = {
			"Pennbrook",
		},
	},
	["Latrobe"] = {
		airport = {
			"Arnold Palmer Regional Airport",
		},
	},
	["Lock Haven"] = {
		airport = {
			"William T. Piper Memorial Airport",
		},
	},
	["Meadville"] = {
		airport = {
			"Port Meadville Airport",
		},
	},
	["Monongahela"] = {
		airport = {
			"Rostraver Airport",
		},
	},
	["Mount Pocono"] = {
		airport = {
			"Pocono Mountains Regional Airport",
		},
	},
	["New Castle"] = {
		airport = {
			"New Castle Municipal Airport",
		},
	},
	["Norristown"] = {
		rail = {
			"Norristown Transit Center",
		},
	},
	["Perkasie"] = {
		airport = {
			"Pennridge Airport",
		},
	},
	["Philipsburg"] = {
		airport = {
			"Mid-State Airport",
		},
	},
	["Pottstown"] = {
		airport = {
			"Heritage Field",
		},
	},
	["Pottsville"] = {
		airport = {
			"Schuylkill County Airport",
		},
	},
	["Quakertown"] = {
		airport = {
			"Quakertown Airport",
		},
	},
	["Selinsgrove"] = {
		airport = {
			"Penn Valley Airport",
		},
	},
	["Somerset"] = {
		airport = {
			"Somerset County Airport",
		},
	},
	["St. Marys"] = {
		airport = {
			"St. Marys Municipal Airport",
		},
	},
	["Titusville"] = {
		airport = {
			"Titusville Airport",
		},
	},
	["Towanda"] = {
		airport = {
			"Bradford County Airport",
		},
	},
	["Washington"] = {
		airport = {
			"Washington County Airport",
		},
	},
	["Williamsport"] = {
		airport = {
			"Williamsport Regional Airport",
		},
	},
	["Zelienople"] = {
		airport = {
			"Zelienople Municipal Airport",
		},
	},
}
