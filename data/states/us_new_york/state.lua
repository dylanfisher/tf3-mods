-- State meta for the "New York Towns & Streets" mod (square_names_us_new_york).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_new_york",
	name = "New York",
	postal = "NY",
	fips = "36",
	modName = "New York Towns & Streets",
	setName = "New York (Towns & Streets)",
	summary = "Real New York towns, plus real local names for the stops and stations you build.",
	examples = { stops = "Broadway or Delaware Avenue", stations = "Grand Central, Penn Station or LaGuardia Airport" },
	flag = "us_new_york.svg",
	-- The seal's gold (#ECC875 in the pinned SVG): the flag's blue field (#002D72) is close to Colorado's accent
	-- and its red (#BE1F1F) to Texas's. Paler and less orange than Alaska's gold.
	accent = "#ECC875",
	-- Regions (towns_config.json polygons, first match wins): island = Long Island (Nassau and Suffolk),
	-- north = the North Country and the Adirondacks, downstate = New York City, Westchester, Rockland and the
	-- lower and mid-Hudson Valley, upstate = the rest (default: Capital Region, Catskills, Central and Western
	-- New York, Finger Lakes, Southern Tier). New York has no dry region (humid everywhere), so a dry map uses
	-- the whole state. The Long Island shore stands in for tropical, the Adirondacks for subarctic.
	climates = {
		temperate = { upstate = 45, downstate = 30, island = 25 },
		subarctic = { north = 100, upstate = 0 },
		tropical = { island = 70, downstate = 30 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		upstate = "upstate New York", downstate = "downstate (NYC, Hudson Valley)", island = "Long Island",
		north = "the North Country (Adirondacks)",
	},
	streetFlavour = "village greens, canal towns, maples, orchards, lakes and the Long Island shore",
	townFlavour = "small canal, mountain, lake and beach towns",
	asciiFallback = true,
	-- Lint floors: New York has ~1,290 Census places (595 incorporated); the mod keeps ~540 via per-region
	-- floors (towns_config.json incMinPop/cdpMinPop), so the 400-town default holds. The user's target is
	-- 10-12 street cities; New York ships 13. The smallest weighted pool (subarctic: the North Country) is
	-- ~81 towns.
	minTowns = 400,
	minPool = 75,
	minStreetCities = 12,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = { "Not affiliated with the \"New York Names\" mod; all lists here are our own." },
	revision = 4,
	changelog = {
		{ rev = 4, date = "2026-10-09", items = { "Clearer description: says up front that the mod renames the stops and stations you build, not just the default name lists." } },
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
