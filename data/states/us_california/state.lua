-- State meta for the "California Towns & Streets" mod (square_names_us_california).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_california",
	name = "California", -- i18n: ignore (data: the state name, not UI text)
	postal = "CA",
	fips = "06",
	modName = "California Towns & Streets",
	setName = "California (Towns & Streets)",
	summary = "Real California towns, plus real local names for the stops and stations you build.",
	examples = { stops = "Sunset Boulevard or Market Street", stations = "Union Station, Santa Fe Depot or the Ferry Building" },
	flag = "us_california.svg",
	-- The bear's brown (#5C462B in the pinned SVG): the flag's red is Florida's, its green is Washington's.
	accent = "#5C462B",
	-- Regions (towns_config.json polygons, first match wins): mountain = the Sierra Nevada plus hand-set
	-- Southern California mountain towns, desert = the Mojave and Colorado deserts and the Owens Valley,
	-- valley = the Central Valley and its foothills, north = the far north and the north coast,
	-- socal = the rest south of 34.5 (coast and Inland Empire), central = the Central Coast, bay = the rest
	-- (Bay Area, Napa/Sonoma; default).
	climates = {
		dry = { desert = 50, valley = 40, socal = 10 },
		temperate = { bay = 35, central = 25, north = 20, valley = 20 },
		subarctic = { mountain = 70, north = 30 },
		tropical = { socal = 70, central = 30 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		mountain = "the Sierra Nevada and the high mountains", desert = "the deserts", valley = "the Central Valley",
		north = "the North Coast and far north", socal = "Southern California", central = "the Central Coast",
		bay = "the Bay Area",
	},
	harborWord = "ports",
	streetFlavour = "missions, oaks, palms, redwoods, coast, orchards and counties",
	townFlavour = "small mountain, desert, farm and beach towns",
	asciiFallback = true,
	-- Lint floors: California has 482 incorporated cities; the mod ships all but two industrial ones plus ~70
	-- hand-picked CDPs (550 towns), so the 400-town default holds. The user's target is 10-12 street cities;
	-- California ships 13. The smallest weighted pool (subarctic: mountain + north) is ~70 towns, because few
	-- incorporated places sit in the high country.
	minTowns = 400,
	minPool = 65,
	minStreetCities = 12,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = { "Not affiliated with the \"California Names\" mod; all lists here are our own." },
	revision = 6,
	changelog = {
		{ rev = 6, date = "2026-10-10", items = { "Removing this mod is now marked Critical in the mod list. A game started with this mod's name set crashes without it as soon as it needs a new name (building a road, for example); turning the mod back on fixes the save." } },
		{ rev = 5, date = "2026-10-10", items = { "New: translations into Russian, German, French, Spanish, Italian, Dutch, Polish, Portuguese (Brazil), Japanese, Korean and Chinese (Simplified and Traditional). The mod follows the game's language setting; town, street and station names stay as they are." } },
		{ rev = 4, date = "2026-10-09", items = { "Clearer description: says up front that the mod renames the stops and stations you build, not just the default name lists." } },
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
