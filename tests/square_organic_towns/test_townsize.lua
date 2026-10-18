-- "Starting town size" (ot_townsize, 2026-10-13, a test round): the param's factor, preRunFn's write to
-- baseConfig.locations.town.populationDensity (Game size: untouched), the head start's scaling and the START summary.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local TS = ug_require(F.DIR .. "ot_townsize.lua")
local PA = ug_require(F.DIR .. "ot_params.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

--- A baseConfig stand-in: locations.town as base's preRunFn leaves it (other fields kept), writes counted.
local function baseConfig(pd)
	local writes = 0
	local town = { maxNumberPerArea = 0.2, allowInRoughTerrain = false, townFrequency = 0.4 }
	local raw = { populationDensity = pd }
	setmetatable(town, {
		__index = function(_, k) return raw[k] end,
		__newindex = function(_, k, v) writes = writes + 1; raw[k] = v end,
	})
	return { locations = { town = town } }, function() return writes end
end

test("param: starting_town_size maps to game / smaller / small and the factors", function()
	eq(PA.parse(nil).townSize, "game")
	eq(PA.parse({ starting_town_size = 1 }).townSize, "game")
	eq(PA.parse({ starting_town_size = 2 }).townSize, "smaller")
	eq(PA.parse({ starting_town_size = 3 }).townSize, "small")
	eq(PA.parse({ starting_town_size = 9 }).townSize, "game", "out of range: the default")
	eq(TS.factor("game"), nil)
	eq(TS.factor("smaller"), 0.6)
	eq(TS.factor("small"), 0.35)
	ok(PA.parse({ starting_town_size = 3 }).raw:find("starting_town_size=3", 1, true))
end)

test("apply: Game size leaves baseConfig untouched; Smaller / Small scale the player's Population factor", function()
	local bc, writes = baseConfig(1.5)
	local r = TS.apply(bc, "game")
	eq(writes(), 0, "no write at all")
	eq(bc.locations.town.populationDensity, 1.5)
	eq(r.applied, false)
	ok(TS.line("TOWNSIZE", TS.fields(r)):find("populationDensity=1.5->1.5", 1, true))
	bc, writes = baseConfig(1.5)
	r = TS.apply(bc, "small")
	eq(writes(), 1)
	ok(math.abs(bc.locations.town.populationDensity - 0.525) < 1e-9, tostring(bc.locations.town.populationDensity))
	eq(bc.locations.town.maxNumberPerArea, 0.2, "other fields kept")
	eq(bc.locations.town.townFrequency, 0.4)
	eq(r.applied, true)
	local line = TS.line("TOWNSIZE", TS.fields(r))
	ok(line:find("^%[SQOT%] TOWNSIZE ") and line:find("choice=small", 1, true)
		and line:find("populationDensity=1.5->0.525", 1, true), line)
	-- no value to scale (base didn't set it): nothing written
	bc, writes = baseConfig(nil)
	r = TS.apply(bc, "smaller")
	eq(writes(), 0)
	eq(r.err, "noValue")
	-- a broken baseConfig: no error escapes
	r = TS.apply(nil, "smaller")
	eq(r.applied, false)
	ok(r.err ~= nil)
end)

test("head start scaling: smaller starting towns get more rounds and larger increments", function()
	eq(TS.head("game").rounds, 0)
	eq(D.headRounds(50, "clustered", false, TS.head("game").rounds), D.headRounds(50, "clustered", false))
	eq(D.headRounds(50, "clustered", false, TS.head("smaller").rounds), 3)
	eq(D.headRounds(50, "clustered", false, TS.head("small").rounds), 4)
	-- the max rises with the setting
	eq(D.headRounds(1000, "fingers", true, 0), D.HEAD_ROUNDS_MAX)
	eq(D.headRounds(1000, "fingers", true, TS.head("small").rounds), D.HEAD_ROUNDS_MAX + 2)
	eq(D.headEdges(nil, TS.head("game").edgesMul), D.HEAD_EDGES)
	eq(D.headEdges(nil, TS.head("small").edgesMul), 18)
	eq(D.headEdges("clustered", TS.head("smaller").edgesMul), 13)
	-- the lead limit is the same for every size
	eq(D.headLimits().leadM, D.HEAD_LEAD_M)
end)

test("START summary: mean / median per field", function()
	local s = TS.summary({ { buildings = 10, edges = 4, length = 400, cap = 100 },
		{ buildings = 30, edges = 8, length = 800, cap = 300 }, { buildings = 200, edges = 30, length = 3000, cap = 2000 } })
	eq(s.towns, 3)
	eq(s.buildings.mean, 80)
	eq(s.buildings.median, 30)
	eq(s.edges.median, 8)
	eq(s.length.mean, 1400)
	local line = D.line("START summary", TS.summaryFields(s, "small"))
	ok(line:find("towns=3 townSize=small buildings=mean80/median30 edges=mean14/median8", 1, true), line)
	local e = TS.summary({})
	eq(e.towns, 0)
	eq(e.cap.median, 0)
end)

test("Streets at industries (ot_indstreets, round 5): Off writes makeInitialStreets = false, Game default leaves it; INDSTREETS line", function()
	local IS = ug_require(F.DIR .. "ot_indstreets.lua")
	eq(PA.parse(nil).industryStreets, "game", "default Game default")
	eq(PA.parse({ industry_streets = 2 }).industryStreets, "game")
	eq(PA.parse({ industry_streets = 7 }).industryStreets, "game", "out of range: the default")
	ok(PA.parse({ industry_streets = 2 }).raw:find("industry_streets=2", 1, true))
	local writes = 0
	local raw = { makeInitialStreets = true }
	local loc = setmetatable({}, { __index = raw, __newindex = function(_, k, v) writes = writes + 1; raw[k] = v end })
	local r = IS.apply({ locations = loc }, "game")
	eq(writes, 0, "Game default: untouched")
	eq(raw.makeInitialStreets, true)
	r = IS.apply({ locations = loc }, "off")
	eq(writes, 1)
	eq(raw.makeInitialStreets, false)
	eq(r.applied, true)
	local line = TS.line("INDSTREETS", IS.fields(r, "preRunFn"))
	ok(line:find("^%[SQOT%] INDSTREETS ") and line:find("choice=off", 1, true)
		and line:find("makeInitialStreets=true->false", 1, true) and line:find("applied=true", 1, true), line)
	-- a broken baseConfig: no error escapes, nothing applied
	r = IS.apply(nil, "off")
	eq(r.applied, false)
	ok(r.err ~= nil)
end)
