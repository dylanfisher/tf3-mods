-- State meta for the "Arizona Towns & Streets" mod (square_names_us_arizona).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_arizona",
	name = "Arizona",
	postal = "AZ",
	fips = "04",
	modName = "Arizona Towns & Streets",
	setName = "Arizona (Towns & Streets)",
	summary = "Real Arizona towns, streets for your stops, and real station names.",
	examples = { stops = "Camelback Road or Speedway Boulevard", stations = "Sky Harbor Airport, Williams Depot or Falcon Field" },
	flag = "us_arizona.svg",
	-- The flag's copper star (#ce5c17 in the pinned SVG); its red and blue are common to many states.
	accent = "#CE5C17",
	-- desert = low and Sonoran desert (default), high = Colorado Plateau and central highlands (Mogollon Rim and
	-- north/east of it), sky = the southeast high grassland, river = Colorado River towns (a hand list).
	-- Arizona has no real tropics: the river towns and the low desert are the warmest stand-in.
	climates = {
		dry = { desert = 75, sky = 10, high = 15 },
		temperate = { high = 70, sky = 30, desert = 0 },
		subarctic = { high = 100, desert = 0 },
		tropical = { river = 50, desert = 50 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		desert = "the low desert", high = "the high country", sky = "the southeast grasslands",
		river = "the Colorado River",
	},
	harborWord = "harbours",
	streetFlavour = "saguaros, mesquite, mountain ranges, canals and counties",
	townFlavour = "small desert, mining and reservation towns",
	asciiFallback = true,
	-- Lint floors: Arizona has ~275 Census places worth keeping (incorporated + CDPs >= 300 people in 2010,
	-- minus subdivision-style names), so the 400-town default doesn't fit. The user's target is 6-12 street
	-- cities; Arizona ships 13. The smallest weighted pool (subarctic: high country) is ~109 towns.
	minTowns = 250,
	minPool = 100,
	minStreetCities = 10,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = { "Not affiliated with the \"Arizona Names\" mod; all lists here are our own." },
	revision = 3,
	changelog = {
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
