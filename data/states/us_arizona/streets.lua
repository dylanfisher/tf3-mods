-- Generic Arizona-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with a Southwest flavour (desert plants, ranges, rivers, counties, canals,
-- section-line roads, Spanish-style names). Not tied to any one real town, so no per-street fact check is
-- needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Central Avenue", "Center Street", "Commerce Street", "Railroad Avenue", "Depot Street",
	"Broadway", "Park Avenue", "School Street", "Church Street", "Court Street", "Mill Avenue", "State Street",
	"Market Street", "Front Street", "Union Street", "Ranch Road", "Rodeo Road",
	-- numbered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Street", "7th Street",
	"8th Street", "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue", "5th Avenue", "6th Avenue",
	"7th Avenue", "16th Street", "19th Avenue", "24th Street", "35th Avenue",
	-- section-line roads and canals
	"Baseline Road", "Indian School Road", "Canal Road", "Ditch Road",
	-- desert plants and trees
	"Saguaro Drive", "Mesquite Street", "Palo Verde Drive", "Ocotillo Road", "Cholla Street", "Yucca Street",
	"Agave Way", "Ironwood Drive", "Desert Willow Drive", "Prickly Pear Lane", "Jojoba Way", "Creosote Lane",
	"Acacia Drive", "Juniper Street", "Pinon Drive", "Ponderosa Drive", "Aspen Avenue", "Cottonwood Lane",
	"Sycamore Street", "Oleander Avenue", "Olive Avenue", "Orange Street",
	-- landscape
	"Mesa Drive", "Butte Avenue", "Canyon Road", "Arroyo Drive", "Wash Road", "Mountain View Road",
	"Sunset Boulevard", "Sunrise Drive", "Red Rock Road", "Desert Sky Drive", "Rim Road", "Ridge Road",
	"Valley Road", "Foothills Drive", "Spring Street", "Lake Drive", "River Road",
	"Copper Street", "Turquoise Avenue", "Silver Street", "Gold Street", "Mine Road",
	-- ranges
	"Camelback Road", "Superstition Boulevard", "Catalina Avenue", "Huachuca Street", "Chiricahua Street",
	"Bradshaw Drive", "Mingus Avenue", "Rincon Road", "Santa Rita Road",
	-- rivers, counties and peoples
	"Gila Street", "Salt River Road", "Verde Street", "Santa Cruz Avenue", "San Pedro Street",
	"Colorado Avenue", "Maricopa Avenue", "Pima Street", "Yavapai Street", "Cochise Avenue", "Navajo Boulevard",
	"Apache Avenue", "Coconino Street", "Mohave Street", "Pinal Avenue", "Yuma Street", "Hopi Drive",
	-- Spanish-style
	"Camino del Sol", "Camino Real", "Avenida del Sol", "Calle Encanto", "Via Linda", "Paseo Verde",
	-- people and history
	"Washington Street", "Jefferson Street", "Lincoln Street", "Grant Street", "Adams Street", "Madison Street",
	"Monroe Street", "Jackson Street", "Van Buren Street", "Roosevelt Street", "Franklin Avenue",
	"Cesar Chavez Avenue",
}
