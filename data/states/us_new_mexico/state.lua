-- State meta for the "New Mexico Towns & Streets" mod (square_names_us_new_mexico).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_new_mexico",
	name = "New Mexico",
	postal = "NM",
	fips = "35",
	modName = "New Mexico Towns & Streets",
	setName = "New Mexico (Towns & Streets)",
	summary = "Real New Mexico towns, plus real local names for the stops and stations you build.",
	examples = { stops = "Central Avenue or Cerrillos Road", stations = "Santa Fe Depot, Alvarado Transportation Center or Albuquerque International Sunport" },
	flag = "us_new_mexico.svg",
	-- Turquoise, the state gem: the Zia flag's red is Texas's accent and its yellow sits between Alaska's gold
	-- (#FFB612) and the Bulk Bulldozer hazard yellow (#F4D32B). Bluer and darker than the family teal and the
	-- Smart Lanes cyan.
	accent = "#0095B6",
	-- Regions (towns_config.json polygons, first match wins): rio = the Rio Grande corridor (Espanola valley,
	-- Albuquerque metro, East Mountains, Estancia valley, Belen, Socorro), high = the northern mountains (Santa Fe,
	-- Taos, Los Alamos, Chama, Las Vegas, Raton) plus the Sacramento Mountains (Ruidoso, Cloudcroft), west = Four
	-- Corners, Navajo and Zuni country, Grants, Gallup and Catron County, plains = the eastern plains (Clovis,
	-- Tucumcari, Clayton, Hobbs), desert = the rest (default: the Chihuahuan south, Las Cruces, Alamogordo, Roswell,
	-- Carlsbad, Deming, Silver City). New Mexico has no tropics: the stand-in is the warm low south plus the green
	-- Rio Grande valley (irrigated bosque, chile and pecan farms), which reads better on a lush map than the
	-- mountains or the plains would.
	climates = {
		dry = { desert = 50, plains = 25, west = 15, rio = 10 },
		temperate = { rio = 50, high = 25, west = 25 },
		subarctic = { high = 80, west = 20 },
		tropical = { desert = 60, rio = 40 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		desert = "the Chihuahuan desert", rio = "the Rio Grande valley", high = "the northern mountains",
		west = "the Four Corners country", plains = "the eastern plains",
	},
	harborWord = "harbours",
	streetFlavour = "chile, adobe, acequias, mesas, ranges, Spanish caminos and Route 66",
	townFlavour = "small adobe villages, pueblos, ranch and railroad towns",
	asciiFallback = true,
	-- Lint floors: New Mexico has ~278 Census places worth keeping (all 102 incorporated places plus CDPs with
	-- >= 300 people in 2010, minus military and subdivision-style names), so the 400-town default doesn't fit.
	-- 12 street cities (the user's target is 6-12). The smallest weighted pool (subarctic: high + west) is
	-- ~109 towns.
	minTowns = 250,
	minPool = 100,
	minStreetCities = 12,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = {
		"Not affiliated with the \"New Mexico Names\" mod; all lists here are our own.",
		"Streets cover 12 cities (Albuquerque, Santa Fe, Las Cruces, Rio Rancho and eight regional towns); every other town uses the generic New Mexico pool.",
	},
	revision = 4,
	changelog = {
		{ rev = 4, date = "2026-10-09", items = { "Clearer description: says up front that the mod renames the stops and stations you build, not just the default name lists." } },
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
