-- State meta for the "Alaska Towns & Streets" mod (square_names_us_alaska).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_alaska",
	name = "Alaska", -- i18n: ignore (data: the state name, not UI text)
	postal = "AK",
	fips = "02",
	modName = "Alaska Towns & Streets",
	setName = "Alaska (Towns & Streets)",
	summary = "Real Alaska towns, plus real local names for the stops and stations you build.",
	examples = { stops = "4th Avenue or Cushman Street", stations = "Denali, Auke Bay Terminal or Merrill Field" },
	flag = "us_alaska.svg",
	-- The flag's gold stars (#ffb612 in the pinned SVG); its dark blue field is too close to Colorado's #00205B.
	accent = "#FFB612",
	-- interior = Fairbanks and the Tanana/Yukon valleys, southcentral = Anchorage, Mat-Su, Kenai, Prince William
	-- Sound and the Copper River basin, southeast = the Panhandle, islands = Kodiak, the Aleutians and the
	-- Pribilofs, arctic_west = the North Slope, Northwest Arctic, Bering Strait, Y-K Delta and Bristol Bay (default).
	-- Subarctic is the headline climate. Temperate = the maritime south coast; dry = the Arctic tundra and the
	-- semi-arid Interior. Alaska has no tropics, so a tropical map uses the whole state.
	climates = {
		subarctic = { interior = 40, southcentral = 35, arctic_west = 25 },
		temperate = { southeast = 50, southcentral = 30, islands = 20 },
		dry = { arctic_west = 50, interior = 50 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		interior = "the Interior", southcentral = "Southcentral", southeast = "the Panhandle",
		islands = "the islands (Kodiak, Aleutians)", arctic_west = "the Bush (Arctic and west)",
	},
	harborWord = "ferry terminals",
	streetFlavour = "glaciers, rivers, salmon, spruce, gold rush and bush flying",
	townFlavour = "fishing towns and remote villages",
	asciiFallback = true,
	-- Lint floors: Alaska is the deliberately thin state of the series (user decision). It has ~280 Census places
	-- worth keeping (incorporated cities + CDPs >= 50 people in 2010, minus military posts, a mine camp and
	-- road-named suburb tracts), so the 400-town default doesn't fit. Only 9 towns have widely known streets
	-- (Anchorage, Fairbanks, Juneau, Ketchikan, Sitka, Wasilla, Kodiak, Palmer, Homer); the description says so.
	-- The smallest weighted pool (temperate: southeast + southcentral + islands) is ~120.
	minTowns = 250,
	minPool = 100,
	minStreetCities = 9,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = {
		"Alaska has fewer street-name cities than the other states in this series: real streets for 9 towns (Anchorage, Fairbanks, Juneau, Ketchikan, Sitka, Wasilla, Kodiak, Palmer and Homer). Every other town uses the Alaska-style street list.",
		"Not affiliated with the \"Alaskan Names\" mod; all lists here are our own.",
	},
	revision = 5,
	changelog = {
		{ rev = 5, date = "2026-10-10", items = { "New: translations into Russian, German, French, Spanish, Italian, Dutch, Polish, Portuguese (Brazil), Japanese, Korean and Chinese (Simplified and Traditional). The mod follows the game's language setting; town, street and station names stay as they are." } },
		{ rev = 4, date = "2026-10-09", items = { "Clearer description: says up front that the mod renames the stops and stations you build, not just the default name lists." } },
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
