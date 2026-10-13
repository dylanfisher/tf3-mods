-- Stress Test "Crossings": the pure geometry of the test crossing construction
-- (infrastructure/street_construction/square_stress_test_crossing.con.lua): one plain street crossing
-- of a main road (along local x) and a side road, every node free, so once built it is ordinary
-- streets (as stress_grid_streets.lua and square_roundabouts). Built by the Junction test's
-- "Crossings" set to try lane rules at ordinary junctions with real traffic. No api.*: unit-tested.
--
-- Shapes: X (side road both ways along y), T (side road towards +y only), skewed X (side road at
-- SKEW_DEG to the main road). Each arm is ARM long; its end is a dead end the Junction test links to a
-- town. Every coordinate is +0, never -0 (docs/findings.md "Negative zero").
-- Showcase (plain groups) also sets the side road's angle (X and T: ANGLES, arms at least 60 deg
-- apart) and the second main / side arm's own road (main2 / side2: 1 = the same road as the first arm,
-- k + 1 = ROADS[k]), so the lane counts differ per arm. Without them (Crossing test) it is as before.
-- Lights (Lights showcase): 2 = Yes asks for a traffic light at the centre node on every edge list
-- through both construction fields square_roundabouts' signals use, `trafficLightYes` (entry indices,
-- base tealdef construction_util_serialized.d.tl:150) and `trafficLightNodePreference` ({{index, "YES"}},
-- wiki modding/constructions/basics.md:690); 1 (default) leaves it to the game (AUTO, lights from 1950).

local cross = {}

cross.KEYS = { shape = "sqst_x_shape", main = "sqst_x_main", side = "sqst_x_side", angle = "sqst_x_angle",
	main2 = "sqst_x_main2", side2 = "sqst_x_side2", lights = "sqst_x_lights" }
-- 4 Straight (the bench's lane drop, plans/square_stress_test/BENCH.md): the main road only, its east arm on
-- main2's road, so the lanes change at the one centre node
cross.SHAPES = { "X", "T", "Skewed X", "Straight" }
cross.SKEW_DEG = 60
cross.ARM = 60
-- The side road's direction from the main road's east arm (X and T; Skewed X keeps SKEW_DEG): the
-- first is the default (the Crossing test's square crossings).
cross.ANGLES = { 90, 60, 75, 105, 120 }
cross.LIGHTS = { "Game decides", "Yes" }

-- Roads by the main / side params (1-based). lanes = road lanes per direction (one-way: all lanes).
local T = "::/infrastructure/street/"
cross.ROADS = {
	{ label = "Town small", template = T .. "town/town_new_small.street_template", lanes = 1 },
	{ label = "Town medium", template = T .. "town/town_new_medium.street_template", lanes = 2 },
	{ label = "Town large", template = T .. "town/town_new_large.street_template", lanes = 3 },
	{ label = "Country small", template = T .. "country/country_new_small.street_template", lanes = 1 },
	{ label = "Country medium", template = T .. "country/country_new_medium.street_template", lanes = 2 },
	{ label = "Country large", template = T .. "country/country_new_large.street_template", lanes = 3 },
	{ label = "One-way small", template = T .. "town/town_new_one_way_small.street_template", lanes = 2, oneWay = true },
	{ label = "One-way medium", template = T .. "town/town_new_one_way_medium.street_template", lanes = 4, oneWay = true },
	{ label = "Town large, bus lanes", template = T .. "town/town_new_large_bus.street_template", lanes = 3 },
	{ label = "Town large, tram", template = T .. "town/town_new_large_tram_electrified.street_template", lanes = 3,
		tram = "ELECTRIC" },
}

local function z0(v)
	if v == 0 then return 0 end -- -0 == 0: +0
	return v
end

local function index(v, n, default)
	local i = tonumber(v)
	if i == nil or i < 1 or i > n or i ~= math.floor(i) then return default end
	return i
end

--- One straight edge entry pair { {p0, t}, {p1, t} } from (x0, y0) to (x1, y1).
local function edge(x0, y0, x1, y1)
	local t = { z0(x1 - x0), z0(y1 - y0), 0 }
	return { { z0(x0), z0(y0), 0 }, t }, { { z0(x1), z0(y1), 0 }, t }
end

--- Arm directions (degrees from local +x) of the main and the side road for a shape index and the
--- side road's angle (degrees, default 90; Skewed X ignores it).
function cross.arms(shape, angle)
	local a = angle or 90
	if shape == 2 then return { 180, 0 }, { a } end
	if shape == 3 then return { 180, 0 }, { cross.SKEW_DEG, cross.SKEW_DEG + 180 } end
	if shape == 4 then return { 180, 0 }, {} end
	return { 180, 0 }, { a, a + 180 }
end

--- The edges of one arm: from its end into the centre on the main road's west arm and the side
--- road's first arm (inward), out from the centre on the others, so a one-way road flows straight
--- through (west -> east, side: first arm -> second).
local function armEdges(out, d, len, inward)
	local x, y = len * math.cos(math.rad(d)), len * math.sin(math.rad(d))
	if math.abs(x) < 1e-9 then x = 0 end
	if math.abs(y) < 1e-9 then y = 0 end
	local a, b
	if inward then a, b = edge(x, y, 0, 0) else a, b = edge(0, 0, x, y) end
	out[#out + 1] = a
	out[#out + 1] = b
end

local function edgeList(road, entries, lit)
	local free = {}
	for i = 1, #entries do free[i] = i - 1 end
	local params = { type = road.template }
	if road.tram then params.tramTrackType = road.tram end
	local el = { type = "STREET", params = params, edges = entries, snapNodes = {}, freeNodes = free }
	if lit then
		-- every entry at the centre (0, 0): the one node all arms meet in
		local yes, pref = {}, {}
		for i, e in ipairs(entries) do
			if e[1][1] == 0 and e[1][2] == 0 then
				yes[#yes + 1] = i - 1
				pref[#pref + 1] = { i - 1, "YES" }
			end
		end
		el.trafficLightYes = yes
		el.trafficLightNodePreference = pref
	end
	return el
end

--- The road of an arm's "own road" param (main2 / side2): nil = the same as the first arm.
local function ownRoad(v)
	local i = index(v, #cross.ROADS + 1, 1)
	if i == 1 then return nil end
	return cross.ROADS[i - 1]
end

--- The construction result for the params (1-based; defaults: X, town large x town medium, 90 deg).
--- One edge list per road; a second arm with its own road (main2 / side2) gets a list of its own,
--- meeting the others in the one centre node.
function cross.result(params)
	params = params or {}
	local shape = index(params[cross.KEYS.shape], #cross.SHAPES, 1)
	local main = cross.ROADS[index(params[cross.KEYS.main], #cross.ROADS, 3)]
	local side = cross.ROADS[index(params[cross.KEYS.side], #cross.ROADS, 2)]
	local angle = cross.ANGLES[index(params[cross.KEYS.angle], #cross.ANGLES, 1)]
	local lit = index(params[cross.KEYS.lights], #cross.LIGHTS, 1) == 2
	local mainDirs, sideDirs = cross.arms(shape, angle)
	local lists = {}
	for _, road in ipairs({ { main, mainDirs, ownRoad(params[cross.KEYS.main2]) }, { side, sideDirs, ownRoad(params[cross.KEYS.side2]) } }) do
		local first, own = {}, {}
		for k, d in ipairs(road[2]) do
			armEdges((k > 1 and road[3] ~= nil) and own or first, d, cross.ARM, k == 1)
		end
		-- a road without arms (Straight: no side road) gets no edge list
		if #first > 0 then lists[#lists + 1] = edgeList(road[1], first, lit) end
		if #own > 0 then lists[#lists + 1] = edgeList(road[3], own, lit) end
	end
	return {
		edgeLists = lists,
		models = {},
		groundFaces = {},
		cost = 0,
	}
end

--- "Town large x Town small, T".
function cross.label(shape, main, side)
	local m, s = cross.ROADS[main], cross.ROADS[side]
	return string.format("%s x %s, %s", m and m.label or "?", s and s.label or "?", cross.SHAPES[shape] or "?")
end

return cross
