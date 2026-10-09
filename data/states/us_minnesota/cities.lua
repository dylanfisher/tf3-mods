-- Real names per city, used by the rename script for NEW player-built stops and stations in a town whose
-- current name matches the key (or an alias). Only well-known, real names; anything less certain goes to
-- plans/square_state_names/data_review.md ("## Minnesota") instead of here.
--   streets        Road Stops (edge-object stops), in this order (first unused wins). Every street was checked
--                  on OpenStreetMap (Overpass, 2026-10-08): a highway way with that name inside the city's admin
--                  boundary (directional prefix or quadrant suffix dropped: Rochester's "2nd Street Southwest"
--                  ships as "2nd Street"; OSM's "Saint Germain Street" ships as "St. Germain Street").
--   neighborhoods  bus/tram stations. Minneapolis: the city's official neighborhoods (Minneapolis_Neighborhoods
--                  layer, City of Minneapolis ArcGIS, 2026-10-08; "Bryn - Mawr" -> "Bryn Mawr", "Nicollet Island"
--                  from "Nicollet Island - East Bank"). St. Paul: the 17 planning districts (City of Saint Paul
--                  District_Councils layer; "Battle Creek - Conway - Eastview - Highwood Hills" split, "West
--                  Seventh" from "West Seventh - Fort Road"). Duluth: the City of Duluth GIS Office neighborhood
--                  layer (hyphenated pairs split: "Lakeside-Lester Park" -> Lakeside, Lester Park). Names that are
--                  also Minnesota towns (Corcoran, Jordan, Waite Park, Windom, Rice Lake) are left out.
--   rail           passenger train stations, WITHOUT a trailing "Station". Series policy (D5): mainline and
--                  commuter first, then light rail with clean names. Amtrak (GTFS 2026-10-08): the Empire Builder
--                  and Borealis stop at St. Paul Union Depot ("Union Depot", Metro Transit's name for the same
--                  building); Red Wing, Winona, St. Cloud, Staples and Detroit Lakes are named after their town
--                  (engine default, no entry). Northstar is not in Metro Transit's current GTFS (no service), so
--                  it is left out. METRO Blue and Green Line names from Metro Transit GTFS (stops.txt), " Station"
--                  dropped, only names without abbreviations, slashes or sponsors; each station's city checked by
--                  its GTFS coordinates. Duluth Depot: North Shore Scenic Railroad (northshorescenicrailroad.org).
--   airport        airports/airfields: FAA names (NASR APT_BASE, cycle 2026-10-01) in their short common form,
--                  keyed to the town the field serves or sits in. Minneapolis-St. Paul International/
--                  Wold-Chamberlain is over 40 bytes in any full form and ships as "MSP International Airport".
--                  St. Cloud Regional was renamed St. Cloud Sky Central in 2025 (FAA cycle shows the new name).
--   harbor         none: Minnesota has no passenger ferry terminal with a formal name (data_review.md).
-- Station names are unique map-wide; street names are unique per town.
return {
	["Minneapolis"] = {
		streets = {
			"Hennepin Avenue", "Nicollet Avenue", "Lake Street", "Lyndale Avenue", "Franklin Avenue", "Washington Avenue",
			"Lowry Avenue", "Broadway Avenue", "University Avenue", "Central Avenue", "Cedar Avenue", "Chicago Avenue",
			"Portland Avenue", "Park Avenue", "Hiawatha Avenue", "Minnehaha Avenue", "Lagoon Avenue", "Marquette Avenue",
			"Plymouth Avenue", "Penn Avenue", "Glenwood Avenue", "Riverside Avenue", "38th Street", "46th Street",
			"Minnehaha Parkway", "Johnson Street", "50th Street", "Lake of the Isles Parkway", "Bloomington Avenue",
			"Excelsior Boulevard",
		},
		neighborhoods = {
			"Linden Hills", "Lowry Hill", "Loring Park", "North Loop", "Elliot Park", "Whittier", "Seward", "Longfellow",
			"Powderhorn Park", "Marcy Holmes", "Northeast Park", "Logan Park", "Bottineau", "Cedar Riverside",
			"East Phillips", "Tangletown", "Lynnhurst", "East Harriet", "King Field", "Armatage", "Diamond Lake",
			"Hiawatha", "Standish", "Ericsson", "Folwell", "Audubon Park", "Columbia Park", "Windom Park", "Shingle Creek",
			"Ventura Village", "Near North", "Downtown East", "Downtown West", "Nicollet Island", "Bryn Mawr",
			"Willard-Hay", "Prospect Park", "Como", "Beltrami", "Holland", "Sheridan", "Bancroft", "Fulton", "Keewaydin",
			"Hawthorne", "McKinley", "East Isles", "Marshall Terrace", "Lyndale",
		},
		rail = {
			"Target Field", "Government Plaza", "Nicollet Mall", "Lake Street Midtown", "East Bank", "West Bank",
			"Stadium Village",
		},
		airport = {
			"MSP International Airport",
		},
	},
	["St. Paul"] = {
		aliases = { "Saint Paul", "St Paul" },
		streets = {
			"Grand Avenue", "Summit Avenue", "University Avenue", "Selby Avenue", "Snelling Avenue", "Lexington Parkway",
			"Rice Street", "Payne Avenue", "Arcade Street", "Kellogg Boulevard", "Shepard Road", "Marshall Avenue",
			"Randolph Avenue", "Ford Parkway", "Cleveland Avenue", "Fairview Avenue", "Hamline Avenue", "Dale Street",
			"Victoria Street", "Como Avenue", "Larpenteur Avenue", "Maryland Avenue", "White Bear Avenue", "Robert Street",
			"Wabasha Street", "Jackson Street", "Concord Street", "Mississippi River Boulevard", "Johnson Parkway",
			"Minnehaha Avenue",
		},
		neighborhoods = {
			"Hamline-Midway", "Macalester-Groveland", "Highland Park", "Dayton's Bluff", "St. Anthony Park", "Como Park",
			"North End", "West Side", "Summit Hill", "Summit-University", "Frogtown", "West Seventh", "Payne-Phalen",
			"Greater East Side", "Battle Creek", "Highwood Hills", "Union Park", "Conway", "Eastview",
		},
		rail = {
			"Union Depot", "Westgate",
		},
		airport = {
			"St. Paul Downtown Airport",
		},
	},
	["Duluth"] = {
		streets = {
			"Superior Street", "London Road", "Michigan Street", "Lake Avenue", "Mesaba Avenue", "Grand Avenue",
			"Central Avenue", "Woodland Avenue", "Arrowhead Road", "Skyline Parkway", "Minnesota Avenue", "Garfield Avenue",
			"Piedmont Avenue", "Jean Duluth Road", "Rice Lake Road", "Haines Road", "Glenwood Street", "4th Street",
			"Railroad Street", "Canal Park Drive", "Commonwealth Avenue", "Martin Road", "Kenwood Avenue",
			"Maple Grove Road", "Trinity Road", "Miller Trunk Highway", "Congdon Park Drive", "Lester River Road",
		},
		neighborhoods = {
			"Park Point", "Lakeside", "Lester Park", "Congdon Park", "Chester Park", "Endion", "Hunters Park", "Woodland",
			"Duluth Heights", "Central Hillside", "East Hillside", "Lincoln Park", "Spirit Valley", "Morgan Park", "Gary",
			"New Duluth", "Fond du Lac", "Riverside", "Smithville", "Oneota", "Denfeld", "Piedmont Heights",
			"Bayview Heights", "Kenwood", "Irving", "Fairmount", "Cody", "Norton Park",
		},
		rail = {
			"Duluth Depot",
		},
		airport = {
			"Duluth International Airport", "Sky Harbor Airport",
		},
	},
	["Rochester"] = {
		streets = {
			"Broadway Avenue", "Civic Center Drive", "Elton Hills Drive", "Salem Road", "Marion Road", "Valleyhigh Drive",
			"2nd Street", "Center Street", "West Circle Drive", "East Circle Drive", "37th Street", "Mayowood Road",
			"55th Street", "Viola Road", "19th Street", "41st Street", "4th Street", "16th Street", "12th Street",
			"7th Street", "Superior Drive", "48th Street", "Pinewood Road", "Bandel Road", "College View Road",
			"Apache Drive", "Cascade Street",
		},
		airport = {
			"Rochester International Airport",
		},
	},
	["Bloomington"] = {
		streets = {
			"American Boulevard", "Old Shakopee Road", "France Avenue", "Lyndale Avenue", "Penn Avenue",
			"Normandale Boulevard", "98th Street", "86th Street", "84th Street", "Xerxes Avenue", "Portland Avenue",
			"Nicollet Avenue", "Bloomington Avenue", "Killebrew Drive", "Lindau Lane", "Bush Lake Road", "90th Street",
			"102nd Street", "Auto Club Road", "Chicago Avenue", "Cedar Avenue", "Hyland Greens Drive",
			"Bloomington Ferry Road", "Dupont Avenue", "Old Cedar Avenue",
		},
		rail = {
			"Bloomington Central",
		},
	},
	["St. Cloud"] = {
		aliases = { "Saint Cloud", "St Cloud" },
		streets = {
			"Division Street", "St. Germain Street", "Roosevelt Road", "3rd Street", "25th Avenue", "Cooper Avenue",
			"Clearwater Road", "33rd Street", "Veterans Drive", "15th Avenue", "9th Avenue", "Lincoln Avenue",
			"Riverside Drive", "10th Street", "8th Street", "Northway Drive", "2nd Street", "Wilson Avenue",
			"Oak Grove Road", "University Drive", "5th Avenue", "Waite Avenue", "County Road 75",
			"Washington Memorial Drive",
		},
		airport = {
			"St. Cloud Sky Central Airport",
		},
	},
	["Mankato"] = {
		streets = {
			"Madison Avenue", "Riverfront Drive", "Front Street", "Victory Drive", "Stadium Road", "Warren Street",
			"Glenwood Avenue", "Belle Avenue", "Broad Street", "Monks Avenue", "Adams Street", "Hoffman Road", "Pohl Road",
			"Raintree Road", "Bassett Drive", "Balcerzak Drive", "2nd Street", "Main Street", "Hickory Street",
			"Walnut Street", "Cherry Street", "Sibley Parkway", "Star Street", "Long Street", "North Riverfront Drive",
			"Lime Valley Road", "Thompson Ravine Road", "Vine Street",
		},
		airport = {
			"Mankato Regional Airport",
		},
	},
	["Moorhead"] = {
		streets = {
			"Main Avenue", "Center Avenue", "8th Street", "11th Street", "12th Avenue", "20th Street", "34th Street",
			"24th Avenue", "14th Street", "30th Avenue", "Belsly Boulevard", "40th Avenue", "River Drive", "1st Avenue",
			"4th Street", "21st Street", "28th Avenue", "15th Avenue", "6th Avenue", "Village Green Boulevard",
			"Holiday Drive", "3rd Avenue", "17th Street", "50th Avenue",
		},
		airport = {
			"Moorhead Municipal Airport",
		},
	},
	["Winona"] = {
		streets = {
			"Huff Street", "Broadway Street", "Sarnia Street", "Gilmore Avenue", "Mankato Avenue", "Main Street",
			"3rd Street", "4th Street", "5th Street", "Lafayette Street", "Johnson Street", "Center Street",
			"Wabasha Street", "Mark Street", "Howard Street", "Riverview Drive", "Lake Boulevard", "Homer Road",
			"Pelzer Street", "Liberty Street", "Market Street", "Franklin Street", "Hilbert Street", "Washington Street",
			"Walnut Street", "King Street", "West Lake Boulevard", "Orrin Street",
		},
		airport = {
			"Winona Municipal Airport",
		},
	},
	["Brainerd"] = {
		streets = {
			"Washington Street", "Oak Street", "Laurel Street", "Front Street", "6th Street", "8th Street", "13th Street",
			"Mill Avenue", "Bluff Avenue", "Willow Street", "Riverside Drive", "Kingwood Street", "Norwood Street",
			"College Drive", "Quince Street", "Maple Street", "Jackson Street", "4th Street", "Pine Street",
			"Wright Street", "Graydon Avenue", "Charles Street", "Rosewood Street", "9th Street", "Buffalo Hills Lane",
			"Excelsior Road", "Juniper Street", "Southeast 13th Street",
		},
		airport = {
			"Brainerd Lakes Regional Airport",
		},
	},
	["Stillwater"] = {
		streets = {
			"Main Street", "Chestnut Street", "Myrtle Street", "Olive Street", "Pine Street", "Greeley Street",
			"Orleans Street", "Owens Street", "Churchill Street", "3rd Street", "4th Street", "2nd Street", "Water Street",
			"Mulberry Street", "Laurel Street", "Stillwater Boulevard", "Curve Crest Boulevard", "Market Drive",
			"Croixwood Boulevard", "Nightingale Boulevard", "Washington Avenue", "Everett Street", "Center Street",
			"Wilkins Street", "Sycamore Street", "Holcombe Street", "William Street", "Linden Street",
		},
	},
	["Bemidji"] = {
		streets = {
			"Paul Bunyan Drive", "Bemidji Avenue", "Beltrami Avenue", "Irvine Avenue", "America Avenue", "15th Street",
			"Anne Street", "Adams Avenue", "Birchmont Drive", "Division Street", "Gillett Drive", "Roosevelt Road",
			"Washington Avenue", "Minnesota Avenue", "3rd Street", "4th Street", "5th Street", "2nd Street", "23rd Street",
			"Park Avenue", "30th Street", "Hannah Avenue", "Mississippi Avenue", "Lake Avenue", "Clausen Avenue",
			"Ridgeway Avenue", "Grant Avenue", "Carr Lake Road", "Calihan Avenue",
		},
		airport = {
			"Bemidji Regional Airport",
		},
	},
	["Eden Prairie"] = {
		airport = {
			"Flying Cloud Airport",
		},
	},
	["Blaine"] = {
		airport = {
			"Anoka County-Blaine Airport",
		},
	},
	["Crystal"] = {
		airport = {
			"Crystal Airport",
		},
	},
	["Lake Elmo"] = {
		airport = {
			"Lake Elmo Airport",
		},
	},
	["Lakeville"] = {
		airport = {
			"Airlake Airport",
		},
	},
	["South St. Paul"] = {
		airport = {
			"Fleming Field Airport",
		},
	},
	["Hibbing"] = {
		airport = {
			"Range Regional Airport",
		},
	},
	["International Falls"] = {
		airport = {
			"Falls International Airport",
		},
	},
	["Thief River Falls"] = {
		airport = {
			"Thief River Falls Regional Airport",
		},
	},
	["Ely"] = {
		airport = {
			"Ely Municipal Airport",
		},
	},
	["Fergus Falls"] = {
		airport = {
			"Fergus Falls Regional Airport",
		},
	},
	["Alexandria"] = {
		airport = {
			"Alexandria Regional Airport",
		},
	},
	["Willmar"] = {
		airport = {
			"Willmar Municipal Airport",
		},
	},
	["Detroit Lakes"] = {
		airport = {
			"Detroit Lakes Airport",
		},
	},
	["Worthington"] = {
		airport = {
			"Worthington Municipal Airport",
		},
	},
	["Austin"] = {
		airport = {
			"Austin Municipal Airport",
		},
	},
	["Albert Lea"] = {
		airport = {
			"Albert Lea Municipal Airport",
		},
	},
	["Owatonna"] = {
		airport = {
			"Owatonna Degner Regional Airport",
		},
	},
	["Faribault"] = {
		airport = {
			"Faribault Municipal Airport",
		},
	},
	["Marshall"] = {
		airport = {
			"Southwest Minnesota Regional Airport",
		},
	},
	["Grand Rapids"] = {
		airport = {
			"Grand Rapids-Itasca County Airport",
		},
	},
	["Red Wing"] = {
		airport = {
			"Red Wing Regional Airport",
		},
	},
	["Baudette"] = {
		airport = {
			"Baudette International Airport",
		},
	},
	["Warroad"] = {
		airport = {
			"Warroad International Airport",
		},
	},
	["Eveleth"] = {
		airport = {
			"Eveleth-Virginia Municipal Airport",
		},
	},
	["Cloquet"] = {
		airport = {
			"Cloquet Carlton County Airport",
		},
	},
	["Two Harbors"] = {
		airport = {
			"Richard B. Helgeson Airport",
		},
	},
}
