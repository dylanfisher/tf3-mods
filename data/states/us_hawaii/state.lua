-- State meta for the "Hawaii Towns & Streets" mod (square_names_us_hawaii).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_hawaii",
	name = "Hawaii", -- i18n: ignore (data: the state name, not UI text)
	postal = "HI",
	fips = "15",
	modName = "Hawaii Towns & Streets",
	setName = "Hawaii (Towns & Streets)",
	summary = "Real Hawaii towns, plus real local names for the stops and stations you build.",
	examples = { stops = "Kalakaua Avenue or Alii Drive", stations = "Waikiki, Pearlridge or Kona International Airport" },
	flag = "us_hawaii.svg",
	-- Hibiscus pink (not a flag colour): the flag's navy (#012169) is close to Colorado's #00205B and its red
	-- (#C8102E) is Florida's/Texas's. Pinker than the No Factory Passengers red, redder than the orchid.
	accent = "#D63384",
	-- Regions (towns_config.json polygons, first match wins): oahu = Oahu (Honolulu County), maui = Maui, Molokai
	-- and Lanai (Maui County), kauai = Kauai, big_island = Hawaii County (default). Extra tags from hand lists:
	-- leeward = the dry Kona sides (Waianae coast and Ewa plain, South and West Maui, the Kona/Kohala coasts and
	-- Ka'u, Kauai's south and west shore); upcountry = the cool uplands on the slopes of Mauna Kea, Kilauea and
	-- Haleakala (Waimea, Volcano, Mountain View, Kula, Makawao, Pukalani, Olinda) plus Lanai City.
	-- Tropical is the headline climate and takes every island by size. Dry = the leeward coasts; temperate and
	-- subarctic (Hawaii has neither) lean on upcountry, which is the closest stand-in (Mauna Kea and Haleakala
	-- summits get frost and snow, but no one lives there).
	climates = {
		tropical = { oahu = 40, big_island = 25, maui = 20, kauai = 15 },
		dry = { leeward = 80, oahu = 10, maui = 10 },
		temperate = { upcountry = 40, big_island = 25, maui = 20, kauai = 15 },
		subarctic = { upcountry = 85, big_island = 15, maui = 0 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		oahu = "Oahu", big_island = "the Big Island", maui = "Maui County (Maui, Molokai, Lanai)", kauai = "Kauai",
		leeward = "the leeward coasts (Kona, Kihei, Waianae)", upcountry = "upcountry (Waimea, Volcano, Kula)",
	},
	-- The second-biggest CDP is East Honolulu (a Honolulu suburb), so the intro names Hilo instead.
	introTowns = { "Honolulu", "Hilo" },
	harborWord = "harbours",
	streetFlavour = "mauka and makai, plumeria, koa and kukui, native birds, plantation camps and numbered streets",
	townFlavour = "plantation villages, beach towns and upcountry ranch towns",
	asciiFallback = true,
	-- Lint floors: Hawaii is the deliberately thin state of the series (user decision). It has no incorporated
	-- places at all: all 163 Census places are CDPs, and ~131 are worth keeping after military housing and
	-- subdivision-style CDPs are left out (towns_config.json), so the 400/250-town floors can't apply. The
	-- smallest weighted pool (subarctic: upcountry + Big Island + Maui top-up) is ~65 towns. Streets cover the
	-- 13 towns with OSM-checked, well-known streets.
	minTowns = 120,
	minPool = 60,
	minStreetCities = 13,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = {
		"Hawaii is the smallest state in this series: every Census place in Hawaii is an unincorporated community (CDP), so the list has about 130 towns. Real streets cover 13 towns; every other town uses the Hawaii-style street list. Names are plain ASCII (no okina or kahako), as Census and most street signs write them.",
		"Not affiliated with the \"Hawaii Names\" mod; all lists here are our own.",
	},
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
