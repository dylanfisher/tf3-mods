-- Generic New York-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with a New York flavour (village greens, the Erie Canal, Hudson River and Dutch
-- colonial patterns, Haudenosaunee nation names that are common street names across upstate, orchards and
-- vineyards, Adirondack woods and lakes, Long Island shore). Not tied to any one real town, so no per-street
-- fact check is needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Broadway", "State Street", "Front Street", "Water Street", "Market Street", "Church Street",
	"Court Street", "Mill Street", "School Street", "Center Street", "Union Street", "Division Street",
	"Railroad Avenue", "Depot Street", "Bridge Street", "Pearl Street", "Liberty Street", "Academy Street",
	"Park Avenue", "Park Place", "Prospect Street", "Pleasant Street", "Elm Street", "High Street",
	-- presidents and founders (common across the state)
	"Washington Avenue", "Jefferson Street", "Madison Avenue", "Franklin Street", "Hamilton Street",
	"Clinton Street", "Lincoln Avenue", "Jay Street", "Monroe Street", "Grant Avenue",
	-- numbered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Street", "7th Street",
	"8th Street", "9th Street", "10th Street", "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue",
	-- canal, river and rail towns
	"Canal Street", "Towpath Road", "Lock Street", "Erie Boulevard", "Ferry Street", "Dock Street",
	"River Road", "River Street", "Hudson Avenue", "Mohawk Street", "Genesee Street", "Seneca Street",
	"Cayuga Street", "Oneida Street", "Onondaga Avenue", "Tioga Street", "Chemung Street",
	-- roads and turnpikes
	"Turnpike Road", "Post Road", "Ridge Road", "Lake Road", "Mountain Road", "Hill Road",
	"County Road", "Old State Road", "Plank Road", "Stage Road", "Mill Road", "Station Road", "Town Line Road",
	-- trees, farms and orchards
	"Maple Avenue", "Oak Street", "Chestnut Street", "Walnut Street", "Cherry Street", "Birch Lane",
	"Hemlock Road", "Spruce Street", "Pine Street", "Willow Street", "Sycamore Street", "Linden Street",
	"Orchard Street", "Apple Tree Lane", "Vineyard Road", "Farm Road",
	"Barn Road", "Meadow Lane", "Clover Road",
	-- villages and greens
	"Village Green", "Green Street", "Chapel Street", "Grove Street", "Garden Street",
	"Spring Street",
	-- woods, lakes and mountains
	"Lake Street", "Lake Shore Drive", "Pond Road", "Brook Road", "Falls Road", "Gorge Road", "Glen Road",
	"Forest Avenue", "Notch Road", "Summit Avenue", "Valley Road", "Hollow Road",
	"Camp Road", "Loon Lake Road", "Beaver Dam Road",
	-- shore and harbour
	"Bay Avenue", "Harbor Road", "Ocean Avenue", "Shore Road", "Beach Lane", "Dune Road", "Bayview Avenue",
	"Cove Road", "Lighthouse Road", "Sound Avenue",
}
