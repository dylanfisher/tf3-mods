-- State meta for the "Texas Towns & Streets" mod (square_names_us_texas).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_texas",
	name = "Texas", -- i18n: ignore (data: the state name, not UI text)
	postal = "TX",
	fips = "48",
	modName = "Texas Towns & Streets",
	setName = "Texas (Towns & Streets)",
	summary = "Real Texas towns, plus real local names for the stops and stations you build.",
	examples = { stops = "Westheimer Road or Congress Avenue", stations = "Union Station, Fort Worth Central or Dallas Love Field" },
	flag = "us_texas.svg",
	-- The flag's red (#BF0A30 in the pinned SVG): its blue (#00205B) is exactly Colorado's accent.
	accent = "#BF0A30",
	-- Regions (towns_config.json polygons, first match wins): valley = the Lower Rio Grande Valley,
	-- gulf = the coastal band from Beaumont-Port Arthur to Corpus Christi and Kingsville, panhandle = the
	-- Panhandle and South Plains (Amarillo, Lubbock), west = west of the dry line (Trans-Pecos, Permian Basin,
	-- Edwards Plateau, Big Country, border country), east = the rest (default: DFW, Houston, Austin,
	-- San Antonio, the Piney Woods). Texas has no real subarctic: the high, cold-wintered Panhandle stands in.
	climates = {
		dry = { west = 70, panhandle = 30 },
		temperate = { east = 70, panhandle = 15, gulf = 15 },
		subarctic = { panhandle = 100, west = 0 },
		tropical = { gulf = 50, valley = 50 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		west = "West Texas", panhandle = "the Panhandle and South Plains", east = "East and Central Texas",
		gulf = "the Gulf Coast", valley = "the Rio Grande Valley",
	},
	harborWord = "ports",
	streetFlavour = "courthouse squares, live oaks, pecans, mesquite, ranch roads and bayous",
	townFlavour = "small ranch, oil, border and coast towns",
	asciiFallback = true,
	-- Lint floors: Texas has 1,225 incorporated places; the mod keeps ~530 towns via per-region population
	-- floors (towns_config.json incMinPop), so the 400-town default holds. The user's target is 10-12 street
	-- cities; Texas ships 13. The smallest weighted pool (subarctic: the Panhandle) is ~73 towns.
	minTowns = 400,
	minPool = 70,
	minStreetCities = 12,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = { "Not affiliated with the \"Texas Names\" mod; all lists here are our own." },
	revision = 5,
	changelog = {
		{ rev = 5, date = "2026-10-10", items = { "New: translations into Russian, German, French, Spanish, Italian, Dutch, Polish, Portuguese (Brazil), Japanese, Korean and Chinese (Simplified and Traditional). The mod follows the game's language setting; town, street and station names stay as they are." } },
		{ rev = 4, date = "2026-10-09", items = { "Clearer description: says up front that the mod renames the stops and stations you build, not just the default name lists." } },
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
