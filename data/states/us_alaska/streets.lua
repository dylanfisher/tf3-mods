-- Generic Alaska-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with an Alaskan flavour (glaciers, mountains, rivers, salmon and wildlife,
-- spruce and birch, gold rush, fishing harbours and bush flying). Not tied to any one real town, so no
-- per-street fact check is needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Front Street", "Railroad Avenue", "Depot Road", "Broadway", "Park Avenue", "School Road",
	"Church Street", "Court Street", "Mill Street", "Market Street", "Water Street", "Center Avenue",
	"Bridge Street", "Mission Road",
	-- numbered and lettered
	"1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue", "5th Avenue", "6th Avenue", "7th Avenue",
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "A Street", "B Street",
	"C Street", "D Street",
	-- mountains and glaciers
	"Glacier Avenue", "Glacier View Drive", "Mountain View Drive", "Ridge Road", "Summit Drive",
	"Denali Street", "Chugach Way", "Alpine Drive",
	"Pass Road", "Peak View Lane", "Tundra Road",
	-- water and coast
	"Harbor Way", "Harbor Drive", "Marine Way", "Bay Road", "Beach Road", "Cannery Road", "Dock Street",
	"Ferry Way", "Inlet View Drive", "Lagoon Road", "Spit Road", "Shore Drive", "Tidewater Road",
	"River Road", "Creek Road", "Lake Street", "Slough Road", "Float Plane Road", "Boat Harbor Road",
	-- rivers
	"Yukon Avenue", "Kuskokwim Street", "Tanana Drive", "Susitna Street", "Copper River Road",
	"Kenai Street", "Chena Street", "Matanuska Avenue", "Knik Avenue", "Stikine Street",
	-- fish and wildlife
	"King Salmon Drive", "Sockeye Street", "Coho Street", "Halibut Road", "Moose Avenue", "Caribou Street",
	"Grizzly Lane", "Bear Paw Drive", "Eagle Street", "Raven Street", "Ptarmigan Road", "Wolverine Road",
	"Otter Street", "Loon Lane",
	-- trees and plants
	"Spruce Street", "Birch Road", "Alder Street", "Willow Street", "Cottonwood Lane", "Aspen Avenue",
	"Hemlock Street", "Cedar Street", "Fireweed Lane", "Forget-Me-Not Lane", "Lupine Drive",
	"Blueberry Road", "Salmonberry Lane", "Cranberry Street",
	-- gold rush, bush and frontier
	"Gold Street", "Miner Street", "Dredge Road", "Sourdough Drive", "Klondike Street", "Trapper Lane",
	"Musher Road", "Iditarod Street", "Homestead Road", "Pioneer Drive", "Frontier Road",
	"Cabin Road", "Pipeline Road", "Airport Road", "Bush Pilot Way", "Airstrip Road",
	"Hangar Road",
	-- sky and season
	"Aurora Drive", "Northern Lights Avenue", "Midnight Sun Drive", "North Star Road",
	"Big Dipper Drive", "Snowshoe Lane", "Snow Ridge Road",
	-- people and history
	"Washington Street", "Lincoln Street", "Jefferson Street", "Seward Street", "Baranof Street",
}
