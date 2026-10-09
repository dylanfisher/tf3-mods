-- Generic California-style street pool (streetNamesScript): used by the game for new stops in every
-- town, and left alone by the rename script in towns without a city list (cities.lua).
-- Common US street patterns with a California flavour (Spanish mission-era names, oaks, palms and redwoods,
-- coast and mountains, ranchos, vineyards and orchards, counties). Not tied to any one real town, so no
-- per-street fact check is needed; keep each name <= 40 bytes.
return {
	-- core
	"Main Street", "Front Street", "Railroad Avenue", "Depot Street", "Broadway", "Park Avenue", "School Street",
	"Church Street", "Court Street", "Mill Street", "Market Street", "Commercial Street", "Center Street",
	"Grand Avenue", "College Avenue", "Water Street", "Bridge Street", "Mission Street",
	-- numbered
	"1st Street", "2nd Street", "3rd Street", "4th Street", "5th Street", "6th Street", "7th Street",
	"8th Street", "9th Street", "10th Street", "1st Avenue", "2nd Avenue", "3rd Avenue", "4th Avenue",
	"5th Avenue", "6th Avenue", "7th Avenue",
	-- Spanish-language street names common across the state
	"El Camino Real", "Alameda Street", "Camino Del Mar", "Calle Real", "Avenida Del Sol", "Via Verde",
	"Paseo Grande", "Del Monte Avenue", "San Antonio Road", "Santa Rosa Avenue",
	"Arroyo Road", "Rancho Road", "Mesa Drive", "Vista Way", "Loma Drive", "Sierra Avenue", "Monte Vista Drive",
	-- trees and plants
	"Oak Street", "Live Oak Avenue", "Palm Avenue", "Redwood Drive", "Sequoia Avenue", "Cypress Street",
	"Eucalyptus Avenue", "Olive Street", "Orange Avenue", "Lemon Street", "Walnut Street",
	"Almond Avenue", "Laurel Street", "Magnolia Avenue", "Sycamore Street", "Willow Street",
	"Manzanita Drive", "Poppy Lane", "Jacaranda Avenue", "Pine Street", "Cedar Street", "Madrone Avenue",
	-- coast and water
	"Ocean Avenue", "Beach Boulevard", "Harbor Boulevard", "Bay Street", "Shoreline Drive", "Cliff Drive",
	"Pacific Avenue", "Coast Road", "Pier Avenue", "Lighthouse Avenue", "Marina Way",
	"River Road", "Creek Road", "Lake Drive", "Spring Street", "Canal Street", "Levee Road",
	-- mountains, valley and desert
	"Mountain View Avenue", "Sierra Vista Drive", "Foothill Boulevard", "Canyon Road", "Ridge Road",
	"Summit Drive", "Valley Boulevard", "Orchard Avenue", "Vineyard Avenue", "Ranch Road", "Grove Street",
	"Desert View Drive", "Mojave Road", "Joshua Tree Lane", "Sunset Boulevard", "Gold Street",
	-- counties and patriotic
	"Fresno Street", "Kern Street", "Tulare Avenue", "Sonoma Avenue", "Napa Street", "Marin Avenue",
	"Monterey Street", "Placer Street", "Shasta Avenue", "Humboldt Street", "Mendocino Avenue",
	"Washington Street", "Lincoln Avenue", "Jefferson Street", "Franklin Street", "Madison Avenue",
	"Martin Luther King Jr. Boulevard", "Union Street", "Liberty Street", "State Street",
}
