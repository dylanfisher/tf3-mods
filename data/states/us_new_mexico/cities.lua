-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## New Mexico") instead of here.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name inside the city's admin
--                  boundary (directional prefix or quadrant suffix dropped: Albuquerque's "Central Avenue
--                  Southeast" ships as "Central Avenue"; OSM's "Saint Francis Drive" ships as "St. Francis Drive").
--                  Las Vegas has no list (its Overpass dump failed; data_review.md).
--   neighborhoods  bus/tram stations. Albuquerque: the City's Recognized Neighborhood Associations layer
--                  (coageo.cabq.gov agis/Neighborhood_Associations, 2026-10-08), " NA"/" Association" dropped
--                  ("Historic Old Town Association" -> Old Town, "Downtown Neighborhoods Association" -> Downtown).
--                  Santa Fe: the City of Santa Fe NeighborhoodAssociations and HistoricDistricts layers (ArcGIS org
--                  "City of Santa Fe"), neighbourhood associations only (no HOAs or condos), suffix dropped. Names
--                  that are also New Mexico towns (Kirtland, Torreon, Lee Acres) are left out. Las Cruces has no
--                  official neighbourhood-name layer (data_review.md).
--   rail           passenger train stations, WITHOUT a trailing "Station". Series policy (D5): mainline and
--                  commuter first. Amtrak (GTFS 2026-10-08): Albuquerque's stop is the Alvarado Transportation
--                  Center (Rio Metro's name); Raton, Las Vegas, Lamy, Gallup, Deming and Lordsburg are named after
--                  their town (engine default, no entry). New Mexico Rail Runner Express (Rio Metro GTFS, feed
--                  20260727): " Rail Runner Station" dropped; Belen, Los Lunas and Sandia Pueblo are town names
--                  (default), and the slash names (Los Ranchos/Journal Center, Sandoval County/U.S. 550, Santa Fe
--                  County/N.M. 599) plus "Bernalillo County" are left out (data_review.md). Santa Fe Depot is
--                  also Amtrak's Thruway stop. Cumbres & Toltec Scenic Railroad: the Chama depot
--                  (cumbrestoltec.com, 500 Terrace Avenue); its Osier station is in Colorado.
--   airport        airports/airfields: FAA names (NASR APT_BASE, cycle 2026-10-01) in their short common form,
--                  keyed to the FAA city. Raton's "Raton Muni/Crews Fld" ships without the slash part.
--   harbor         none: New Mexico has no passenger ferry terminals.
-- Station names are unique map-wide; street names are unique per town.
return {
	["Albuquerque"] = {
		streets = {
			"Central Avenue", "Lomas Boulevard", "Menaul Boulevard", "Indian School Road", "Montgomery Boulevard",
			"Candelaria Road", "Montaño Road", "Paseo del Norte", "Academy Road", "Osuna Road", "Gibson Boulevard",
			"Coors Boulevard", "Unser Boulevard", "Rio Grande Boulevard", "Tramway Boulevard", "Juan Tabo Boulevard",
			"Eubank Boulevard", "Wyoming Boulevard", "Louisiana Boulevard", "San Mateo Boulevard", "San Pedro Drive",
			"Carlisle Boulevard", "University Boulevard", "Girard Boulevard", "Yale Boulevard", "Broadway Boulevard",
			"Edith Boulevard", "4th Street", "2nd Street", "12th Street", "Mountain Road", "Gold Avenue", "Silver Avenue",
			"Copper Avenue", "Lead Avenue", "Coal Avenue", "Tijeras Avenue", "Zuni Road", "Constitution Avenue",
			"Sunport Boulevard", "Alameda Boulevard", "Bridge Boulevard", "Avenida César Chávez", "Jefferson Street",
			"Washington Street",
		},
		neighborhoods = {
			"Old Town", "Downtown", "Barelas", "EDo", "Huning Highland", "Huning Castle", "Nob Hill", "University Heights",
			"Martineztown", "Wells Park", "Sawmill", "Los Duranes", "Los Griegos", "Los Poblanos", "Silver Hill",
			"Spruce Park", "Hodgin", "Hoffmantown", "Los Altos", "Mossman", "Netherwood Park", "Altura Park", "Bel-Air",
			"Trumbull Village", "Victory Hills", "Southeast Heights", "Four Hills", "Juan Tabo Hills", "Singing Arrow",
			"Taylor Ranch", "Ladera West", "Piedras Marcadas", "Westgate Heights", "South Broadway", "Mesa del Sol",
		},
		rail = {
			"Alvarado Transportation Center", "Montaño",
		},
		airport = {
			"Albuquerque International Sunport", "Double Eagle II Airport",
		},
	},
	["Santa Fe"] = {
		streets = {
			"Cerrillos Road", "St. Francis Drive", "St. Michaels Drive", "Paseo de Peralta", "Old Pecos Trail",
			"Old Santa Fe Trail", "Canyon Road", "Alameda Street", "Palace Avenue", "San Francisco Street", "Galisteo Street",
			"Guadalupe Street", "Agua Fria Street", "Rufina Street", "Airport Road", "Rodeo Road", "Siringo Road",
			"Richards Avenue", "Don Gaspar Avenue", "Marcy Street", "Water Street", "Washington Avenue", "Bishops Lodge Road",
			"Hyde Park Road", "Camino del Monte Sol", "Acequia Madre", "Old Las Vegas Highway", "Montezuma Avenue",
			"Cordova Road", "Camino Alire", "Siler Road", "Lincoln Avenue", "Grant Avenue", "Sandoval Street",
		},
		neighborhoods = {
			"Historic Guadalupe", "Historic Hillside", "Westside-Guadalupe", "Baca Railyard", "Apodaca Hill", "Talaya Hill",
			"Rancho Siringo", "Santa Fe Midtown", "Las Acequias", "Casa Alegre", "Casa Linda", "Barrio La Canada",
			"Casas Del Cerro", "Vista Encantada", "Arroyo Chamisa",
		},
		rail = {
			"Santa Fe Depot", "South Capitol", "Zia Road",
		},
		airport = {
			"Santa Fe Regional Airport",
		},
	},
	["Las Cruces"] = {
		streets = {
			"Main Street", "Lohman Avenue", "University Avenue", "Picacho Avenue", "Amador Avenue", "Las Cruces Avenue",
			"Telshor Boulevard", "Solano Drive", "Valley Drive", "El Paseo Road", "Avenida de Mesilla", "Missouri Avenue",
			"Idaho Avenue", "Madrid Avenue", "Spruce Avenue", "Griggs Avenue", "Alameda Boulevard", "Mesquite Street",
			"Church Street", "Water Street", "Campo Street", "Del Rey Boulevard", "Roadrunner Parkway",
			"Sonoma Ranch Boulevard", "Northrise Drive", "Engler Road", "Triviz Drive", "Motel Boulevard", "Hadley Avenue",
			"Union Avenue", "Three Crosses Avenue", "Dripping Springs Road", "Mesa Grande Drive",
		},
		airport = {
			"Las Cruces International Airport",
		},
	},
	["Rio Rancho"] = {
		streets = {
			"Southern Boulevard", "Northern Boulevard", "Unser Boulevard", "King Boulevard", "Westside Boulevard",
			"Sara Road", "Rio Rancho Boulevard", "Pat D'Arco Highway", "Golf Course Road", "Country Club Drive",
			"Enchanted Hills Boulevard", "Loma Colorado Boulevard", "Paseo del Volcan", "Broadmoor Boulevard",
			"Cabezon Boulevard", "Idalia Road", "Rockaway Boulevard", "Lincoln Avenue", "Cherry Road", "Grande Boulevard",
			"Rainbow Boulevard", "Riverside Drive", "Iris Road", "Meadows Boulevard", "Camino Encantadas",
			"Wellspring Avenue", "19th Avenue", "17th Avenue", "Abrazo Road", "Sundt Road", "High Resort Boulevard",
		},
	},
	["Roswell"] = {
		streets = {
			"Main Street", "2nd Street", "4th Street", "8th Street", "Country Club Road", "College Boulevard",
			"McGaffey Street", "Hobbs Street", "Alameda Street", "Brasher Road", "Chisum Street", "Poe Street",
			"Pine Lodge Road", "Mescalero Road", "Atkinson Avenue", "Garden Avenue", "Union Avenue", "Kentucky Avenue",
			"Montana Avenue", "Lea Avenue", "Richardson Avenue", "Pennsylvania Avenue", "Virginia Avenue",
			"Washington Avenue", "Sycamore Avenue", "Sunset Avenue", "Wyoming Avenue", "Walnut Street", "Deming Street",
			"Bland Street", "Relief Route", "Earl Cummings Loop", "19th Street", "Hobson Road",
		},
		airport = {
			"Roswell Air Center",
		},
	},
	["Farmington"] = {
		streets = {
			"Main Street", "Broadway Avenue", "Butler Avenue", "Dustin Avenue", "Sullivan Avenue", "Behrend Avenue",
			"Orchard Avenue", "Auburn Avenue", "Miller Avenue", "Hutton Avenue", "Browning Parkway", "Pinon Hills Boulevard",
			"20th Street", "30th Street", "Murray Drive", "Apache Street", "Navajo Street", "Pinon Street", "Maple Street",
			"Arrington Street", "Bloomfield Highway", "Bisti Highway", "La Plata Highway", "Farmington Avenue",
			"College Boulevard", "San Juan Boulevard", "Scott Avenue", "Municipal Drive", "Wall Avenue", "Fairgrounds Road",
			"Lake Street", "Schwartz Avenue", "Old Aztec Highway",
		},
		airport = {
			"Four Corners Regional Airport",
		},
	},
	["Gallup"] = {
		streets = {
			"Aztec Avenue", "Coal Avenue", "Hill Avenue", "Green Avenue", "Logan Avenue", "Maloney Avenue",
			"Jefferson Avenue", "Lincoln Avenue", "Wilson Avenue", "Mesa Avenue", "2nd Street", "3rd Street", "4th Street",
			"Puerco Drive", "Munoz Drive", "Nizhoni Boulevard", "Boardman Avenue", "Allison Road", "Mendoza Road",
			"Ford Drive", "Joseph M Montoya Boulevard", "Country Club Drive", "Church Rock Street", "Rico Street",
			"Arnold Street", "Marguerite Street", "Clark Street", "College Drive", "Red Rock Drive", "Buena Vista Avenue",
			"Park Avenue",
		},
		airport = {
			"Gallup Municipal Airport",
		},
	},
	["Carlsbad"] = {
		streets = {
			"Canal Street", "Greene Street", "Pierce Street", "Mermod Street", "Fox Street", "Church Street", "Texas Street",
			"Lea Street", "Mesa Street", "Halagueno Street", "Canyon Street", "Main Street", "Orchard Lane", "Cherry Lane",
			"Wood Avenue", "Callaway Drive", "San Jose Boulevard", "National Parks Highway", "Hidalgo Road", "Boyd Drive",
			"Pate Street", "Standpipe Road", "Bypass Road", "Derrick Road", "Radio Boulevard", "Center Avenue",
			"Commerce Drive", "Monterey Street", "Happy Valley Road", "Plaza Street", "8th Street", "6th Street",
		},
		airport = {
			"Cavern City Air Terminal",
		},
	},
	["Alamogordo"] = {
		streets = {
			"White Sands Boulevard", "Scenic Drive", "10th Street", "1st Street", "Indian Wells Road", "Florida Avenue",
			"New York Avenue", "Michigan Avenue", "Indiana Avenue", "Maryland Avenue", "Delaware Avenue", "Washington Avenue",
			"Cuba Avenue", "Puerto Rico Avenue", "Hamilton Road", "Panorama Boulevard", "Pecan Drive", "Mesa Village Drive",
			"Airport Road", "Fairgrounds Road", "Juniper Drive", "Ocotillo Drive", "Thunder Road", "Cornell Avenue",
			"College Avenue", "Canal Street", "Walker Avenue", "Madison Avenue", "Wright Avenue", "Collins Avenue",
			"Mescalero Street", "Desert Lakes Road",
		},
		airport = {
			"Alamogordo-White Sands Regional Airport",
		},
	},
	["Clovis"] = {
		streets = {
			"Main Street", "Grand Avenue", "Prince Street", "Norris Street", "Mabry Drive", "7th Street", "14th Street",
			"21st Street", "1st Street", "10th Street", "Llano Estacado Boulevard", "Brady Avenue", "Manana Boulevard",
			"Thornton Street", "Hull Street", "Wheaton Street", "Sycamore Street", "Wilhite Road", "Echols Avenue",
			"Mitchell Street", "Pile Street", "Gidding Street", "Reid Street", "Connelly Street", "Axtell Street",
			"Colonial Parkway", "Schepps Boulevard", "Kelso Avenue", "Sheridan Street", "Commerce Way", "Purdue Avenue",
			"Cesar Chavez Drive",
		},
		airport = {
			"Clovis Regional Airport",
		},
	},
	["Silver City"] = {
		streets = {
			"Bullard Street", "Broadway", "College Avenue", "Hudson Street", "Market Street", "Yankie Street", "Texas Street",
			"Arizona Street", "Cooper Street", "Main Street", "Silver Heights Boulevard", "Pinos Altos Road", "Swan Street",
			"Alabama Street", "Kentucky Street", "Pope Street", "Grant Street", "Gold Street", "Florence Street",
			"San Vicente Street", "Durango Street", "Victoria Street", "Juniper Avenue", "Pine Street", "32nd Street Bypass",
			"Little Walnut Road", "Ridge Road", "Ranch Club Road", "Cottage San Road", "12th Street", "14th Street",
			"Spring Street", "California Avenue",
		},
		airport = {
			"Grant County Airport",
		},
	},
	["Taos"] = {
		streets = {
			"Paseo del Pueblo Norte", "Paseo del Pueblo Sur", "Kit Carson Road", "Camino de la Placita", "Paseo del Canon",
			"Bent Street", "Ledoux Street", "Gusdorf Road", "Salazar Road", "Ranchitos Road", "Upper Ranchitos Road",
			"Lower Ranchitos Road", "Cruz Alta Road", "Los Pandos Road", "Este Es Road", "La Posta Road", "Weimer Road",
			"Valverde Street", "Albright Street", "Witt Road", "Camino del Medio", "Morada Lane", "Civic Plaza Drive",
			"Quesnel Road", "Manzanares Street", "Kit Carson Street", "Camino de Santiago", "Siler Road", "Chamisa Road",
			"Fernandez Road", "Morgan Road",
		},
		airport = {
			"Taos Regional Airport",
		},
	},
	["Bernalillo"] = {
		rail = {
			"Downtown Bernalillo",
		},
	},
	["Belen"] = {
		airport = {
			"Belen Regional Airport",
		},
	},
	["Isleta"] = {
		rail = {
			"Isleta Pueblo",
		},
	},
	["Santo Domingo Pueblo"] = {
		rail = {
			"Kewa",
		},
	},
	["Chama"] = {
		rail = {
			"Chama Depot",
		},
	},
	["Hobbs"] = {
		airport = {
			"Lea County Regional Airport",
		},
	},
	["Ruidoso"] = {
		airport = {
			"Sierra Blanca Regional Airport",
		},
	},
	["Deming"] = {
		airport = {
			"Deming Municipal Airport",
		},
	},
	["Los Alamos"] = {
		airport = {
			"Los Alamos Airport",
		},
	},
	["Las Vegas"] = {
		airport = {
			"Las Vegas Municipal Airport",
		},
	},
	["Raton"] = {
		airport = {
			"Raton Municipal Airport",
		},
	},
	["Truth or Consequences"] = {
		airport = {
			"Truth or Consequences Municipal Airport", "Spaceport America",
		},
	},
	["Moriarty"] = {
		airport = {
			"Moriarty Municipal Airport",
		},
	},
	["Socorro"] = {
		airport = {
			"Socorro Municipal Airport",
		},
	},
	["Grants"] = {
		airport = {
			"Grants-Milan Municipal Airport",
		},
	},
	["Tucumcari"] = {
		airport = {
			"Tucumcari Municipal Airport",
		},
	},
	["Santa Teresa"] = {
		airport = {
			"Doña Ana County International Jetport",
		},
	},
}
