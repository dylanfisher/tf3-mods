-- Generic Florida-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with a Florida flavour (palms and citrus, shore and water words, wading birds,
-- Spanish-style names, rivers, lakes and counties). Not tied to any one real town, so no per-street fact check
-- is needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Central Avenue", "Commerce Street", "Railroad Avenue", "Depot Street", "Broadway",
	"Park Avenue", "School Street", "Church Street", "Court Street", "Market Street", "Front Street",
	"Mill Street", "Dixie Highway", "Old Dixie Highway", "Federal Highway", "Military Trail",
	-- numbered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Street", "7th Street",
	"8th Street", "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue", "5th Avenue", "6th Avenue",
	"10th Avenue", "13th Street", "17th Street", "22nd Avenue", "34th Street",
	-- palms, citrus and trees
	"Palm Avenue", "Royal Palm Way", "Palmetto Street", "Sabal Palm Drive", "Coconut Grove Drive",
	"Orange Avenue", "Grapefruit Lane", "Lemon Street", "Lime Street", "Tangerine Avenue", "Mango Street",
	"Banyan Street", "Mangrove Drive", "Magnolia Avenue", "Live Oak Lane", "Cypress Street", "Pine Street",
	"Hibiscus Avenue", "Bougainvillea Drive", "Jasmine Street", "Gardenia Street", "Oleander Street",
	"Poinciana Drive", "Seagrape Drive", "Sea Oats Lane",
	-- shore and water
	"Ocean Boulevard", "Ocean Drive", "Beach Boulevard", "Bay Drive", "Bayshore Drive", "Bayview Drive",
	"Gulf Boulevard", "Seaside Avenue", "Shore Drive", "Harbor Drive", "Marina Drive", "Inlet Drive",
	"Lagoon Drive", "Lake Shore Drive", "Lake Avenue", "River Road", "Riverside Drive", "Canal Street",
	"Causeway Boulevard", "Island Way", "Dune Road", "Coral Way", "Lighthouse Road", "Sunset Drive",
	"Sunrise Boulevard", "Spring Street", "Springs Road",
	-- birds and wildlife
	"Pelican Way", "Heron Drive", "Egret Street", "Flamingo Drive", "Ibis Avenue", "Osprey Lane",
	"Sandpiper Drive", "Seagull Lane", "Dolphin Street", "Manatee Avenue", "Tarpon Avenue", "Gator Lane",
	-- Spanish-style
	"Calle Real", "Avenida del Mar", "Via Del Mar", "Paseo Drive", "Alhambra Circle", "Granada Boulevard",
	"Ponce de Leon Boulevard", "De Soto Street", "Cordova Street", "Valencia Avenue", "Sevilla Avenue",
	-- rivers, lakes and counties
	"Suwannee Avenue", "St. Johns Avenue", "Withlacoochee Street", "Peace River Drive", "Okeechobee Road",
	"Kissimmee Street", "Everglades Boulevard", "Seminole Boulevard", "Osceola Avenue", "Alachua Street",
	"Volusia Avenue", "Marion Street", "Polk Street", "Lee Street", "Duval Street", "Escambia Street",
	-- people and history
	"Washington Street", "Jefferson Street", "Lincoln Avenue", "Adams Street", "Madison Street",
	"Monroe Street", "Jackson Street", "Franklin Street", "Flagler Avenue", "Martin Luther King Jr. Boulevard",
}
