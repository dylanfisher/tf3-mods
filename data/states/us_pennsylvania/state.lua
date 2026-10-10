-- State meta for the "Pennsylvania Towns & Streets" mod (square_names_us_pennsylvania).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_pennsylvania",
	name = "Pennsylvania", -- i18n: ignore (data: the state name, not UI text)
	postal = "PA",
	fips = "42",
	modName = "Pennsylvania Towns & Streets",
	setName = "Pennsylvania (Towns & Streets)",
	summary = "Real Pennsylvania towns, plus real local names for the stops and stations you build.",
	examples = { stops = "Broad Street or Liberty Avenue", stations = "30th Street, Steel Plaza or Philadelphia International Airport" },
	flag = "us_pennsylvania.svg",
	-- The seal shield's sea blue (#1F5290 in the pinned SVG): the flag's blue field (#00205B) is exactly
	-- Colorado's accent, the seal's gold sits next to Alaska's and New York's, its red next to Texas's and its
	-- green next to Washington's. Lighter than Colorado's navy, darker than the series' turquoise and cyan.
	accent = "#1F5290",
	-- Regions (towns_config.json polygons, first match wins): northwest = Erie, the Lake Erie shore and the
	-- Shenango/French Creek valleys (Meadville, Sharon, Franklin); north = the Northern Tier and the Pennsylvania
	-- Wilds (Allegheny National Forest, Warren, Bradford, Wellsboro, Towanda, DuBois, Clearfield);
	-- northeast = Scranton, Wilkes-Barre, the Poconos, the Endless Mountains and the anthracite coal region
	-- (Hazleton, Pottsville); southwest = Pittsburgh, its river towns and the Laurel Highlands (Johnstown,
	-- Somerset, Uniontown); southeast = Philadelphia, the Lehigh Valley, Reading, Lancaster and Lebanon;
	-- central = the rest (default: Harrisburg, York, State College, Altoona, Williamsport and the
	-- ridge-and-valley). Pennsylvania is humid everywhere, so a dry map uses the whole state. The southeast
	-- (humid subtropical Delaware Valley) stands in for tropical with the Pittsburgh river valleys; the Northern
	-- Tier woods and the Poconos stand in for subarctic.
	climates = {
		temperate = { central = 30, southeast = 25, southwest = 25, northwest = 10, northeast = 10 },
		subarctic = { north = 65, northeast = 35, central = 0 },
		tropical = { southeast = 75, southwest = 25 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		southeast = "the southeast (Philadelphia, Lehigh Valley)", southwest = "the southwest (Pittsburgh)",
		central = "central Pennsylvania", northeast = "the northeast (Scranton, Poconos)",
		north = "the Northern Tier (Allegheny forest)", northwest = "the Lake Erie shore",
	},
	harborWord = "ferry landings",
	streetFlavour = "tree streets, borough squares, pikes, canals, coal patches and ridges",
	townFlavour = "small boroughs, coal towns, river towns and Pocono villages",
	asciiFallback = true,
	-- Lint floors: Pennsylvania has ~2,000 Census places (1,013 incorporated: cities, boroughs, one town and
	-- three municipalities; townships are not Census places); the mod keeps ~490 via per-region floors
	-- (towns_config.json incMinPop/cdpMinPop), so the 400-town default holds. The user's target is 10-12
	-- street cities; Pennsylvania ships 13. The smallest weighted pool (subarctic: Northern Tier + northeast)
	-- is well above 150; the smallest region (northwest, ~49) only carries a temperate share.
	minTowns = 400,
	minStreetCities = 12,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = { "Not affiliated with the \"Pennsylvania Names\" mod; all lists here are our own." },
	revision = 5,
	changelog = {
		{ rev = 5, date = "2026-10-10", items = { "New: translations into Russian, German, French, Spanish, Italian, Dutch, Polish, Portuguese (Brazil), Japanese, Korean and Chinese (Simplified and Traditional). The mod follows the game's language setting; town, street and station names stay as they are." } },
		{ rev = 4, date = "2026-10-09", items = { "Clearer description: says up front that the mod renames the stops and stations you build, not just the default name lists." } },
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
