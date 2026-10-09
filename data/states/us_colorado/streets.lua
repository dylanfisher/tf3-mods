-- Generic Colorado-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with a Rocky Mountain flavour (peaks, passes, mining, trees, rivers, counties,
-- ranch and plains roads). Not tied to any one real town, so no per-street fact check is needed; keep each
-- name <= 40 bytes.
return {
	-- core
	"Main Street", "Front Street", "Railroad Avenue", "Depot Street", "Broadway", "Park Avenue", "School Street",
	"Church Street", "Court Street", "Mill Street", "Market Street", "Commercial Street", "Union Avenue",
	"Center Street", "Grand Avenue", "College Avenue", "Water Street", "Bridge Street",
	-- numbered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Street", "7th Street",
	"8th Street", "9th Street", "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue", "5th Avenue",
	"6th Avenue", "8th Avenue", "10th Avenue", "13th Street", "17th Street",
	-- mountains and passes
	"Pikes Peak Avenue", "Longs Peak Drive", "Sopris Avenue",
	"Elbert Street", "Summit Boulevard", "Divide Road", "Pass Road", "Gore Range Drive",
	"Front Range Drive", "Mountain View Drive", "Peak View Road", "Ridge Road", "Canyon Road", "Mesa Drive",
	"Foothills Road", "Gulch Road", "Red Rocks Road", "Flatirons Way", "Timberline Drive",
	-- mining and rail heritage
	"Silver Street", "Gold Street", "Ore Street", "Mine Road", "Miner Street",
	"Prospector Drive", "Narrow Gauge Street", "Tramway Road",
	-- trees and plants
	"Aspen Street", "Spruce Street", "Pine Street", "Fir Avenue", "Juniper Lane", "Cottonwood Drive",
	"Willow Street", "Pinon Drive", "Ponderosa Way", "Lodgepole Drive", "Columbine Street",
	"Sagebrush Lane", "Elm Street", "Maple Street", "Walnut Street", "Chokecherry Lane",
	-- rivers and water
	"River Road", "Creek Road", "Lake Drive", "Spring Street", "Ditch Road", "Reservoir Road", "Canal Street",
	"Platte Street", "Arkansas Avenue", "Animas Street", "Poudre Street", "Yampa Avenue", "Gunnison Street",
	"Blue River Road", "Eagle Street", "Roaring Fork Drive",
	-- ranch and plains
	"Ranch Road", "County Road", "Prairie Avenue",
	"Rodeo Road", "Windmill Road",
	-- counties and peoples
	"Larimer Street", "Weld Avenue", "Jefferson Street", "Arapahoe Avenue", "Douglas Street",
	"Teller Street", "Fremont Avenue", "Mesa Avenue",
	"Cheyenne Street", "Ute Avenue", "Kiowa Street", "Navajo Street", "Shoshone Street",
	-- Spanish-style
	"Calle del Sol", "Santa Fe Avenue", "Camino Real",
	-- people and history
	"Washington Street", "Lincoln Avenue", "Grant Street", "Adams Street", "Madison Street", "Monroe Street",
	"Franklin Street", "Jackson Street",
}
