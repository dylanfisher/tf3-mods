-- State meta for the "Minnesota Towns & Streets" mod (square_names_us_minnesota).
-- Read by tools/gen_state_mod.py (copied into the mod as data/state.lua) and by the mod's runtime.
-- Climate keys are the last path segment of the config dict's climate ("::/climates/dry/dry.clima" -> "dry").
-- Weights per tag; 0 = top-up only (used when the weighted pools run dry). Unknown climates use the whole state.
return {
	key = "us_minnesota",
	name = "Minnesota", -- i18n: ignore (data: the state name, not UI text)
	postal = "MN",
	fips = "27",
	modName = "Minnesota Towns & Streets",
	setName = "Minnesota (Towns & Streets)",
	summary = "Real Minnesota towns, plus real local names for the stops and stations you build.",
	examples = { stops = "Nicollet Avenue or Grand Avenue", stations = "Union Depot, Target Field or Duluth International Airport" },
	flag = "us_minnesota.svg",
	-- The 2024 flag's light blue (#52C9E8 in the pinned SVG): its dark blue (#002D5D) is close to Colorado's
	-- accent (#00205B).
	accent = "#52C9E8",
	-- Regions (towns_config.json polygons, first match wins): metro = the Twin Cities, lakes = central lake
	-- country (Brainerd Lakes, Alexandria, Detroit Lakes, Park Rapids), prairie = the western prairie and the
	-- Red River Valley (Moorhead, Crookston, Marshall, Worthington), north = the Arrowhead, the Iron Range and
	-- the north woods (Duluth, Hibbing, Ely, Bemidji, International Falls), south = the rest (default: the
	-- southern and central farm belt, St. Cloud, Rochester, Mankato, the river towns). Minnesota has no desert:
	-- the drier western prairie stands in for dry, and the resort lakes (beaches, cabins) for tropical.
	climates = {
		temperate = { south = 50, metro = 30, lakes = 20 },
		subarctic = { north = 85, lakes = 15 },
		dry = { prairie = 100, south = 0 },
		tropical = { lakes = 70, metro = 30 },
	},
	-- Description wording (tools/gen_state_mod.py).
	regionLabels = {
		south = "the southern farm belt", metro = "the Twin Cities", lakes = "the lake country",
		north = "the North Woods (Arrowhead, Iron Range)", prairie = "the western prairie (Red River Valley)",
	},
	streetFlavour = "lakes, pines, river towns, prairie section roads and the Iron Range",
	townFlavour = "small lake, farm, river and Iron Range towns",
	asciiFallback = true,
	-- Lint floors: Minnesota has ~850 incorporated cities and few CDPs; the mod keeps ~485 via per-region
	-- floors (towns_config.json incMinPop), so the 400-town default holds. The user's target is 10-12 street
	-- cities; Minnesota ships 12. The smallest weighted pool (subarctic: north + lakes) is ~151 towns, right at
	-- the 150 default, so the floor is 120 to leave room for config edits.
	minTowns = 400,
	minPool = 120,
	minStreetCities = 12,
	-- Option C regional sets: off (see the Washington state.lua).
	emitRegionalSets = false,
	regionalSets = {},
	stationSuffix = nil,
	notes = { "Not affiliated with the \"Minnesota Names\" mod; all lists here are our own." },
	revision = 5,
	changelog = {
		{ rev = 5, date = "2026-10-10", items = { "New: translations into Russian, German, French, Spanish, Italian, Dutch, Polish, Portuguese (Brazil), Japanese, Korean and Chinese (Simplified and Traditional). The mod follows the game's language setting; town, street and station names stay as they are." } },
		{ rev = 4, date = "2026-10-09", items = { "Clearer description: says up front that the mod renames the stops and stations you build, not just the default name lists." } },
		{ rev = 3, date = "2026-10-08", items = { "Faster in the map editor: the mod no longer reads every mod's settings on every frame." } },
		{ rev = 2, date = "2026-10-08", items = { "Faster: less work on every build and every frame, and a quicker street name check in big towns." } },
		{ rev = 1, date = "2026-10-08", items = { "New: first release." } },
	},
}
