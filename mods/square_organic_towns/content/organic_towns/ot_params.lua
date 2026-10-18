-- Organic Towns: mod params (mod.json "params") -> plain options (pure).
-- At runtime api.engine.config.getModParams()[modId].<key> is the 1-based index of the chosen value
-- (docs/findings.md "Mod params"; square_line_manager_plus reads Off = 1, On = 2 the same way). A missing
-- table or key means the mod.json default. Keep KEYS in step with mod.json. Keys no longer in mod.json are not
-- read: "metropolis" (setting removed 2026-10-12, metropolis is an automatic city style now, ot_metro) stays in old
-- saves' param tables and is ignored.

local M = {}

M.MOD_ID = "square_organic_towns"

-- key -> { values (internal ids, in mod.json order), default (1-based) }
M.KEYS = {
	act_on = { values = { "off", "new", "all" }, default = 2 },
	-- "Town style" (was "Street style"; 2026-10-14, NEXT_PHASE_BRIEF 55): Automatic (the region follows the name
	-- list) / North American grid (forced NA_GRID, as before) / then a style region independent of the names, appended
	-- so saved indices 1 / 2 keep their meaning (STYLE_REGION)
	style = { values = { "auto", "na_grid", "eu", "med", "nordic", "us", "east_asia", "jp", "mixed" }, default = 1 },
	lookahead = { values = { 1, 2, 3 }, default = 2 },
	debug_log = { values = { false, true }, default = 1 },
	start_angle = { values = { "auto", "grid", "mixed", "organic", "default" }, default = 1 },
	-- organic <-> gridded balance (ot_grid, 2026-10-13): the index itself (1 very organic .. 5 very gridded)
	town_layout = { values = { 1, 2, 3, 4, 5 }, default = 2 },
	-- "Starting town size" (ot_townsize, 2026-10-13): Game size (no change) / Smaller / Small
	starting_town_size = { values = { "game", "smaller", "small" }, default = 1 },
	-- "Streets at industries" (ot_indstreets, 2026-10-13): Off (makeInitialStreets = false) / Game default (the
	-- default since the final test: Off apparently drops the roads between towns too)
	industry_streets = { values = { "off", "game" }, default = 2 },
	-- "Town names" (ot_names, 2026-10-13): Landscape names (the default) / Game names. "Generated names" (value 3,
	-- 2026-10-14) was removed from the setting on 2026-10-15 (the user: "remove it"; since §49 it did the same as
	-- Landscape names): a saved 3 reads as Landscape names
	town_names = { values = { "landscape", "game" }, default = 1, alias = { [3] = "landscape" } },
	-- "Satellite towns" (2026-10-14 late, user: "make sure the satellite cities is a mod setting"): the separate towns the
	-- mod founds, districts (ot_district) and Works (ot_works): On / Residential only / Industrial only / Off. The
	-- satellite villages (streets of the parent town, ot_satellite) are not affected.
	satellite_towns = { values = { "on", "residential", "industrial", "off" }, default = 1 },
	-- "Strong town characters" (ot_character, 2026-10-14): On (default for the test iterations) / Off (no strong kinds,
	-- no densify trait; deep forest towns stay as before)
	strong_characters = { values = { true, false }, default = 1 },
	-- "Town growth" (§66, 2026-10-15, ot_rci): By deliveries (each town's R/C/I mix follows what the player delivers,
	-- the default) / Game default (the game's evened-out split, no weighting)
	town_growth = { values = { "deliveries", "game" }, default = 1 },
}

-- "Town style" value -> style region (ot_inputs.REGION); auto / na_grid: none (the name list's region)
M.STYLE_REGION = { eu = "EU", med = "MED", nordic = "NORDIC", us = "US", east_asia = "EAST_ASIA", jp = "JP",
	mixed = "MIXED" }

local function pick(mine, key)
	local spec = M.KEYS[key]
	local raw = type(mine) == "table" and mine[key] or nil
	local i = tonumber(raw)
	-- (a removed value a save may still hold: its alias, e.g. town_names 3 "Generated names" -> landscape)
	if i ~= nil and spec.alias and spec.alias[i] ~= nil then return spec.alias[i], raw end
	if i == nil or i ~= math.floor(i) or spec.values[i] == nil then i = spec.default end
	return spec.values[i], raw
end

--- Options from this mod's param table (getModParams()[MOD_ID]); `all` = the whole getModParams() result
--- (for the map editor flag). Returns { actOn = "off"|"new"|"all", forceGrid, styleRegion = ot_inputs region id or
--- nil (the name list's), lookahead = 1..3, debug,
--- startAngle = "auto"|"grid"|"mixed"|"organic"|"default" (ot_angles), townLayout = 1..5 (ot_grid),
--- townSize = "game"|"smaller"|"small" (ot_townsize), industryStreets = "off"|"game" (ot_indstreets), townNames = "landscape"|"game" (ot_names, ot_placename),
--- satelliteTowns = "on"|"residential"|"industrial"|"off" (districts / Works), strongCharacters = bool (ot_character),
--- townGrowth = "deliveries"|"game" (ot_rci, §66),
--- mapEditor, raw = "key=value ..."
--- for the log }.
function M.parse(mine, all)
	local o = {}
	local raws = {}
	local v, r = pick(mine, "act_on")
	o.actOn = v
	raws[#raws + 1] = "act_on=" .. tostring(r)
	v, r = pick(mine, "style")
	o.forceGrid = v == "na_grid"
	o.styleRegion = M.STYLE_REGION[v]
	raws[#raws + 1] = "style=" .. tostring(r)
	v, r = pick(mine, "lookahead")
	o.lookahead = v
	raws[#raws + 1] = "lookahead=" .. tostring(r)
	v, r = pick(mine, "debug_log")
	o.debug = v
	raws[#raws + 1] = "debug_log=" .. tostring(r)
	v, r = pick(mine, "start_angle")
	o.startAngle = v
	raws[#raws + 1] = "start_angle=" .. tostring(r)
	v, r = pick(mine, "town_layout")
	o.townLayout = v
	raws[#raws + 1] = "town_layout=" .. tostring(r)
	v, r = pick(mine, "starting_town_size")
	o.townSize = v
	raws[#raws + 1] = "starting_town_size=" .. tostring(r)
	v, r = pick(mine, "industry_streets")
	o.industryStreets = v
	raws[#raws + 1] = "industry_streets=" .. tostring(r)
	v, r = pick(mine, "town_names")
	o.townNames = v
	raws[#raws + 1] = "town_names=" .. tostring(r)
	v, r = pick(mine, "strong_characters")
	o.strongCharacters = v
	raws[#raws + 1] = "strong_characters=" .. tostring(r)
	v, r = pick(mine, "satellite_towns")
	o.satelliteTowns = v
	raws[#raws + 1] = "satellite_towns=" .. tostring(r)
	v, r = pick(mine, "town_growth")
	o.townGrowth = v
	raws[#raws + 1] = "town_growth=" .. tostring(r)
	local base = type(all) == "table" and all[""] or nil
	o.mapEditor = type(base) == "table" and base.isMapEditor == true
	o.raw = table.concat(raws, " ")
	return o
end

return M
