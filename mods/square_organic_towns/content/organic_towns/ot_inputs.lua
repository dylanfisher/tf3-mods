-- Organic Towns: input layer. Turns raw game data (config dict nameList / climate, year, person capacity,
-- station positions, terrain stats, existing street graph) into a plain `inputs` table that ot_style resolves.
-- Pure: the engine layer reads the values and passes them in.

local GR = ug_require "square_organic_towns::/organic_towns/ot_grid.lua"

local M = {}

-- Regions (base profiles in ot_style).
-- (ASIA, 2026-10-14, NEXT_PHASE_BRIEF 48 item 3: the base "asia" list, ~100 megacities from Karachi to Seoul and the
-- Middle East, docs/findings/towns.md; as EAST_ASIA it made 14 of 16 towns JP_DENSE in run 2026-10-14_0814_sqot load 3.
-- Its own, mixed bias now; korea / china stay EAST_ASIA, japan JP)
M.REGION = { US = "US", OCEANIA = "OCEANIA", EU = "EU", MED = "MED", NORDIC = "NORDIC", RU = "RU", JP = "JP",
	EAST_ASIA = "EAST_ASIA", ASIA = "ASIA", MIXED = "MIXED" }
-- (MIXED, 2026-10-14, NEXT_PHASE_BRIEF 55: only from the "Town style" setting, never from a name list: every
-- regional style alike, ot_site / ot_metro / ot_angles)

-- nameList path fragment -> region, country (country tells e.g. Spain apart inside MED). Checked in order;
-- the first match wins, so specific names come before generic ones (`asia` after japan/korea/china).
M.NAME_RULES = {
	{ "square_names_us_", "US", "usa" },
	{ "/usa", "US", "usa" },
	{ "square_names_ca_", "US", "canada" },
	{ "canada", "US", "canada" },
	{ "oceania", "OCEANIA", "oceania" },
	{ "germany", "EU", "germany" },
	{ "france", "EU", "france" },
	{ "england", "EU", "england" },
	{ "netherlands", "EU", "netherlands" },
	{ "poland", "EU", "poland" },
	{ "italy", "MED", "italy" },
	{ "spain", "MED", "spain" },
	{ "portugal", "MED", "portugal" },
	{ "norway", "NORDIC", "norway" },
	{ "sweden", "NORDIC", "sweden" },
	{ "russia", "RU", "russia" },
	{ "japan", "JP", "japan" },
	{ "korea", "EAST_ASIA", "korea" },
	{ "china", "EAST_ASIA", "china" },
	{ "asia", "ASIA", "asia" },
	{ "europe", "EU", "europe" },
}

M.CLIMATES = { "temperate", "dry", "subarctic", "tropical" }

-- Era bands (PLAN.md 2.2): upper year bounds, exclusive.
M.ERA_BOUNDS = { 1850, 1920, 1950, 1980 }
M.ERA_NAMES = { "pre1850", "1850-1920", "1920-1950", "1950-1980", "post1980" }
-- Base town templates: town_old_* until 1940, town_new_* from 1940 (availability in
-- base/content/infrastructure/street/town/town_*.street_template.lua).
M.NEW_TEMPLATES_FROM = 1940

-- Size tiers by total person capacity (upper bounds, exclusive).
M.SIZE_BOUNDS = { 500, 2000, 6000 }

--- Region and country from a nameList resource path (e.g. "::/names/europe/europe.names",
--- "square_names_us_texas::/names/..."). Returns region, country or nil, nil when unknown.
function M.region(nameList)
	if type(nameList) ~= "string" or nameList == "" then return nil, nil end
	local s = nameList:lower()
	for _, r in ipairs(M.NAME_RULES) do
		if s:find(r[1], 1, true) then return r[2], r[3] end
	end
	return nil, nil
end

--- Climate id from a config dict value (an id like "temperate" or a path containing it); default temperate.
function M.climate(value)
	if type(value) == "string" then
		local s = value:lower()
		for _, c in ipairs(M.CLIMATES) do
			if s:find(c, 1, true) then return c end
		end
	end
	return "temperate"
end

--- Era band 1..5 from a year (nil -> 1950-1980 band, the base default start).
function M.era(year)
	year = tonumber(year) or 1960
	for i, b in ipairs(M.ERA_BOUNDS) do
		if year < b then return i end
	end
	return #M.ERA_BOUNDS + 1
end

--- true when town_new_* templates are available in that year.
function M.newTemplates(year)
	return (tonumber(year) or 1960) >= M.NEW_TEMPLATES_FROM
end

--- Size tier 1..4 from total person capacity.
function M.sizeTier(capacity)
	capacity = tonumber(capacity) or 0
	for i, b in ipairs(M.SIZE_BOUNDS) do
		if capacity < b then return i end
	end
	return #M.SIZE_BOUNDS + 1
end

--- Region fallback from the climate alone (PLAN.md 2.2: then "EU central", the base default name set).
function M.regionFromClimate(climate)
	if climate == "subarctic" then return "NORDIC" end
	if climate == "dry" then return "MED" end
	return "EU"
end

--- Builds the inputs table.
--- raw = { nameList, climate, year, capacity, townId, pos = {x, y}, stations = {{x, y}, ...},
---         terrain = ot_terrain.stats result or nil, axis = {angle = rad, strength = 0..1} or nil (existing
---         street axis from ot_graph.dominantAxis), radius = current town radius in m, forceStyle = style id or nil,
---         frame = { axis = rad, origin = {x, y} } or nil (saved plan frame, see ot_style.resolve),
---         keepOuter = bool (a forced style still gets its era's outer zone; dev tools),
---         shape = shape id (ot_shape.IDS; forced, dev tools) or nil, form = town form id (ot_form; forced, dev tools), exits = ot_shape.exits result (roads
---         leaving the town), neighbours = { {dir = rad, dist = m} } other towns nearest first,
---         wide = ot_terrain.wide result (2 km survey for the site classifier) or nil,
---         autoStyle = bool (the style comes from the town's site, ot_site; the region only biases),
---         industry = ot_industry.forTown result or nil (industries near the town: shape axis, cost),
---         layout = 1..5 (mod param "Town layout", ot_grid; nil: default), bounds = { minX, minY, maxX, maxY } (map
---         edge, ot_map) or nil, character = { character = bool, score, rank, nnd, edgeDist } (ot_map) or nil,
---         nbrPicks = ot_diverse.gather result (neighbour diversity) or nil,
---         motif = ot_motif kind id (forced, dev tools) or nil, roads = ot_roads.trace result or nil,
---         railStations = { {x, y, fx, fy, front, tracks, box, file} } rail passenger stations near the town or nil,
---         styleRegion = region id from the "Town style" setting (ot_params) or nil: follow the name list }
--- The result's region is the style region (setting, else name list, else climate; regionSource says which);
--- nameRegion is the name list's region (nil when unknown), for the names.
function M.build(raw)
	raw = raw or {}
	local climate = M.climate(raw.climate)
	local region, country = M.region(raw.nameList)
	-- the name list's own region (names follow it whatever the "Town style" setting picks; nil: unknown list)
	local nameRegion = region
	local regionSource = "nameList"
	if raw.styleRegion ~= nil and M.REGION[raw.styleRegion] then
		-- the "Town style" setting (ot_params styleRegion, NEXT_PHASE_BRIEF 55): the style region alone; the
		-- country only where it is the name list's own region (a Spanish map set to Mediterranean keeps Spain)
		if raw.styleRegion ~= region then country = nil end
		region = raw.styleRegion
		regionSource = "setting"
	elseif region == nil then
		region = M.regionFromClimate(climate)
		regionSource = "climate"
	end
	local pos = raw.pos or { 0, 0 }
	return {
		region = region,
		regionSource = regionSource,
		nameRegion = nameRegion,
		country = country,
		climate = climate,
		year = tonumber(raw.year) or 1960,
		era = M.era(raw.year),
		newTemplates = M.newTemplates(raw.year),
		capacity = tonumber(raw.capacity) or 0,
		tier = M.sizeTier(raw.capacity),
		townId = raw.townId or 0,
		pos = { pos[1] or pos.x or 0, pos[2] or pos.y or 0 },
		stations = raw.stations or {},
		terrain = raw.terrain,
		axis = raw.axis,
		radius = tonumber(raw.radius) or 0,
		forceStyle = raw.forceStyle,
		keepOuter = raw.keepOuter == true,
		frame = raw.frame,
		shape = raw.shape,
		form = raw.form,
		exits = raw.exits or {},
		neighbours = raw.neighbours or {},
		wide = raw.wide,
		autoStyle = raw.autoStyle == true,
		industry = raw.industry,
		layout = raw.layout,
		-- organic <-> gridded balance (ot_grid): the era trend x the Town layout setting
		gridBias = GR.ON and GR.bias(tonumber(raw.year) or 1960, raw.layout) or nil,
		bounds = raw.bounds,
		character = raw.character,
		-- neighbour diversity (ot_diverse): { {town, dist, style, form, shape} } picks of the towns nearby, nearest first
		nbrPicks = raw.nbrPicks or {},
		-- a motif kind forced by the dev tools (ot_motif), or nil
		motif = raw.motif,
		-- the country roads around the town (ot_roads.trace: roads, junctions, segs), or nil (M2 road motifs)
		roads = raw.roads,
		-- rail passenger stations near the town (ot_engine.railStations records: x, y, fx, fy, front, tracks, box), or nil
		-- (M3 station quarter)
		railStations = raw.railStations,
		-- a coastal hugger pick (ot_map.coastal: { coastal, score, rank }) or nil (2026-10-14)
		coastal = raw.coastal,
		-- the town's forest share (ot_forest grid) or nil: terrain-squeezed towns (ot_site squeeze, 2026-10-14)
		forestShare = tonumber(raw.forestShare),
	}
end

return M
