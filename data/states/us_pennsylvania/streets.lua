-- Generic Pennsylvania-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with a Pennsylvania flavour (Philadelphia-grid tree streets, borough squares and
-- diamonds, numbered streets, turnpikes and pikes, canal and furnace towns, coal and rail patches, Pennsylvania
-- Dutch farm country, ridge-and-valley gaps and runs, the Northern Tier woods). Not tied to any one real town,
-- so no per-street fact check is needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Market Street", "High Street", "Broad Street", "Front Street", "Water Street",
	"Church Street", "Mill Street", "School Street", "Center Street", "Union Street", "Railroad Street",
	"Depot Street", "Bridge Street", "Liberty Street", "Market Square", "Diamond Street", "Penn Street",
	"Park Avenue", "Prospect Street", "Pleasant Street", "Second Street", "Third Street", "Fourth Street",
	-- presidents, founders and the Commonwealth
	"Washington Street", "Franklin Street", "Jefferson Avenue", "Madison Avenue", "Hamilton Street",
	"Lincoln Avenue", "Monroe Street", "Grant Street", "Commonwealth Avenue", "Keystone Avenue",
	-- numbered
	"1st Street", "5th Street", "6th Street", "7th Street", "8th Street", "9th Street", "10th Street",
	"11th Street", "12th Street", "13th Street", "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue",
	-- the Philadelphia tree grid (common across the state)
	"Chestnut Street", "Walnut Street", "Spruce Street", "Pine Street", "Locust Street", "Cherry Street",
	"Vine Street", "Sassafras Street", "Mulberry Street", "Cedar Street", "Poplar Street", "Hickory Lane",
	-- pikes, turnpikes and old roads
	"Turnpike Road", "Pike Street", "Old Pike Road", "Valley Pike", "Ridge Road", "Ridge Avenue",
	"Plank Road", "Stage Road", "Post Road", "Township Line Road", "County Line Road", "State Road",
	"Lancaster Avenue", "Easton Road", "Old York Road",
	-- rivers, canals and iron towns
	"Canal Street", "Towpath Road", "Lock Street", "River Road", "Ferry Street", "Wharf Street",
	"Furnace Road", "Forge Road", "Iron Street", "Foundry Street", "Mill Race Road",
	"Susquehanna Avenue", "Schuylkill Avenue", "Lehigh Street", "Juniata Street", "Allegheny Avenue",
	"Monongahela Avenue", "Delaware Avenue", "Conestoga Street",
	-- coal and rail towns
	"Coal Street", "Mine Road", "Breaker Street", "Colliery Road", "Shaft Road", "Patch Road",
	"Station Road", "Junction Road", "Tunnel Road", "Incline Street",
	-- farm country
	"Farm Lane", "Mill Road", "Orchard Road", "Meadow Lane", "Barn Road", "Creamery Road", "Covered Bridge Road",
	"Meeting House Road", "Schoolhouse Road", "Springhouse Road", "Stone Hill Road", "Clover Lane",
	-- ridges, gaps and woods
	"Mountain Road", "Gap Road", "Summit Street", "Valley Road", "Hollow Road", "Run Road", "Laurel Street",
	"Hemlock Street", "Maple Avenue", "Oak Street", "Elm Street", "Birch Street", "Beech Street",
	"Sugar Maple Lane", "Forest Avenue", "Lake Street", "Creek Road", "Falls Road", "Glen Road",
	"Lookout Road", "Camp Road",
}
