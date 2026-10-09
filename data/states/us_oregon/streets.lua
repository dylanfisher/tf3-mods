-- Generic Oregon-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with an Oregon flavour (Douglas fir and filbert orchards, Portland-style
-- quadrant avenues, Cascade peaks and coast headlands, rivers, counties, high-desert sage and juniper,
-- logging and pioneer-trail history).
-- Not tied to any one real town, so no per-street fact check is needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Front Street", "Commercial Street", "Market Street", "Division Street", "Railroad Avenue",
	"Water Street", "Pioneer Way", "Center Street", "Broadway", "Park Avenue", "School Street",
	"Mill Street", "Depot Street", "Church Street", "Court Street", "Union Street", "State Street",
	"Highway 99", "Pacific Highway", "Airport Road", "Fairgrounds Road",
	-- numbered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Street", "7th Street",
	"8th Street", "9th Street", "10th Street", "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue",
	"5th Avenue", "6th Avenue", "7th Avenue", "8th Avenue", "9th Avenue", "10th Avenue",
	-- Portland quadrant style
	"SE 39th Avenue", "NE 82nd Avenue", "SE 122nd Avenue", "NE 15th Avenue", "SW 4th Avenue", "N 33rd Avenue",
	"NW 23rd Avenue", "SE 50th Avenue", "NE 60th Avenue", "SW 10th Avenue",
	-- trees, plants and farms
	"Fir Street", "Douglas Avenue", "Cedar Street", "Alder Street", "Hemlock Street", "Spruce Street",
	"Maple Street", "Oak Street", "Ash Street", "Myrtle Street", "Madrone Way", "Dogwood Lane",
	"Laurel Street", "Willow Street", "Cottonwood Drive", "Juniper Street", "Ponderosa Drive", "Tamarack Lane",
	"Sagebrush Road", "Filbert Street", "Hazelnut Drive", "Orchard Avenue", "Cherry Street", "Pear Street",
	"Hop Yard Road", "Vineyard Lane", "Berry Lane", "Grange Road", "Oregon Grape Lane", "Huckleberry Lane",
	-- landscape
	"Cascade Avenue", "Mountain View Drive", "Hood Street", "Jefferson Street", "Sisters View Road",
	"Coast Highway", "Ocean View Drive", "Beach Drive", "Bay Street", "Harbor Street", "Headland Road",
	"Lake Street", "River Road", "Valley View Road", "Canyon Road", "Ridge Road", "Summit Avenue",
	"Prairie Road", "Hillside Drive", "Creek Road", "Falls Street", "Butte Avenue", "Rimrock Road",
	"High Desert Lane", "Gorge Road", "Dune Road", "Lava Road",
	-- rivers, counties and regions
	"Willamette Street", "Columbia Avenue", "Santiam Highway", "McKenzie Street", "Rogue River Road",
	"Umpqua Street", "Siuslaw Street", "Deschutes Avenue", "Clackamas Street", "Tualatin Avenue",
	"Yamhill Street", "Nehalem Street", "Klamath Avenue", "John Day Street", "Owyhee Avenue",
	"Malheur Street", "Grande Ronde Street", "Sandy Boulevard", "Molalla Avenue", "Calapooia Street",
	"Clatsop Street", "Tillamook Street", "Benton Street", "Linn Avenue", "Marion Street", "Polk Street",
	"Lane Street", "Coos Street", "Curry Street", "Josephine Street", "Wasco Street", "Umatilla Avenue",
	"Harney Street", "Wallowa Avenue", "Ochoco Street", "Siskiyou Boulevard", "Multnomah Street",
	-- people and history
	"Washington Street", "Lincoln Street", "Grant Street", "Adams Street", "Madison Street",
	"Monroe Street", "Jackson Street", "Franklin Avenue", "Hamilton Street", "Garfield Street",
	"Oregon Trail Road", "Mill Race Road", "Sawmill Road", "Logging Road", "Ferry Street", "Stage Road",
}
