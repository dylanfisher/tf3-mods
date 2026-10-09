-- Generic New Mexico-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with a New Mexico flavour (chile and adobe, high-desert plants, mesas and
-- arroyos, ranges, rivers, counties, acequias, Spanish-style camino/calle names, Route 66 and the railroad).
-- Not tied to any one real town, so no per-street fact check is needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Central Avenue", "Railroad Avenue", "Depot Street", "Broadway", "Park Avenue",
	"School Street", "Church Street", "Court Street", "Mill Street", "Market Street", "Front Street",
	"Plaza Street", "Ranch Road", "Rodeo Road", "Fairgrounds Road", "Airport Road", "Route 66",
	-- numbered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Street", "7th Street",
	"8th Street", "10th Street", "12th Street", "1st Avenue", "2nd Avenue", "3rd Avenue",
	-- Spanish-style
	"Camino Real", "Camino del Sol", "Camino de la Sierra", "Calle Encanto",
	"Calle Luna", "Avenida del Sol", "Paseo del Rio", "Paseo de Oñate", "Placita Road",
	"Vista del Valle", "Loma Linda Drive", "Las Lomas Road", "Los Arboles Drive",
	-- acequias, farms and the river
	"Acequia Madre", "Ditch Road", "Bosque Road", "Orchard Lane", "Chile Road", "Pecan Drive",
	"Ristra Lane", "River Road", "Rio Bravo Road", "Rio Grande Avenue", "Pecos Street",
	"Gila Street", "Mimbres Street", "Chama Street", "Canadian Street", "San Juan Avenue",
	-- high-desert plants and trees
	"Pinon Drive", "Juniper Street", "Cottonwood Lane", "Chamisa Road", "Yucca Street", "Cholla Street",
	"Mesquite Street", "Sage Road", "Ponderosa Drive", "Aspen Avenue", "Willow Street", "Elm Street",
	"Desert Willow Drive", "Agave Way",
	-- landscape and sky
	"Mesa Drive", "Arroyo Road", "Canyon Road", "Butte Street", "Ridge Road", "Valley Road",
	"Mountain View Road", "Sunset Boulevard", "Sunrise Drive", "Red Rock Road", "Malpais Road",
	"Adobe Road", "Turquoise Trail", "Silver Street", "Copper Avenue", "Gold Avenue",
	"Mine Road", "Hot Springs Road", "Llano Road", "Prairie Road", "Windmill Road",
	-- ranges
	"Sandia Avenue", "Manzano Street", "Sangre de Cristo Road", "Jemez Street", "Organ Street",
	"Sacramento Avenue", "Capitan Street", "Mogollon Avenue", "Zuni Road",
	-- counties and peoples
	"Navajo Street", "Apache Avenue", "Pueblo Road", "Acoma Street", "Mescalero Road", "Lincoln Avenue",
	"Otero Street", "Luna Street", "Sierra Street", "Socorro Street", "Grant Street", "Colfax Avenue",
	"Union Street", "Lea Street", "Eddy Street", "Chaves Street",
	-- people and history
	"Washington Street", "Jefferson Street", "Madison Street", "Monroe Street", "Kit Carson Road",
	"Santa Fe Trail", "Cesar Chavez Avenue", "Martin Luther King Avenue",
}
