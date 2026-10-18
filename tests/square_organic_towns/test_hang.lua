-- Loop guards (hang fix 2026-10-13, real map run 2026-10-13_1848_sqot: Henley-on-Thames' head-start round 2 froze the game
-- after SNAPSHOT). Every walk / step loop of the planning path ends on bad input (NaN / endless coordinates, zero steps,
-- endless extents) instead of spinning: a shorter / missing line, never a frozen Main Thread. Each case runs under an
-- instruction cap, so a regression fails here instead of hanging the test run.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local L = ug_require(F.DIR .. "ot_motif_land.lua")
local ORG = ug_require(F.DIR .. "ot_grow_organic.lua")
local GRID = ug_require(F.DIR .. "ot_grow_grid.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local core = ug_require(F.DIR .. "ot_core.lua")

local INF, NAN = math.huge, 0 / 0

--- Runs fn under an instruction cap (default 2e7): true, results, or false, "HANG" when it would not end.
local function capped(fn, limit)
	local n = 0
	debug.sethook(function()
		n = n + 1
		if n * 1e5 > (limit or 2e7) then debug.sethook(); error("HANG", 0) end
	end, "", 1e5)
	local res = table.pack(pcall(fn))
	debug.sethook()
	return table.unpack(res, 1, res.n)
end

local function ends(name, fn, limit)
	local okC, err = capped(fn, limit)
	ok(okC, name .. ": " .. tostring(err))
end

test("geometry: resample / fillet / cellRange end on zero steps and endless or NaN points", function()
	ends("resample step 0", function() eq(#G.resample({ { 0, 0 }, { 100, 0 } }, 0), 2) end)
	ends("resample NaN step", function() G.resample({ { 0, 0 }, { 100, 0 } }, NAN) end)
	ends("resample endless segment", function()
		ok(#G.resample({ { 0, 0 }, { INF, 0 } }, 10) <= G.MAX_SAMPLES + 2)
	end)
	ends("fillet step 0", function() G.fillet({ { 0, 0 }, { 100, 0 }, { 100, 100 } }, 50, 0) end)
	eq(G.cellRange(-INF, 0, 10, 10, 0, 50), nil)
	eq(G.cellRange(NAN, 0, 10, 10, 0, 50), nil)
	eq(G.cellRange(0, 0, 1e5, 1e5, 0, 50), nil, "too many cells")
	local x0, x1 = G.cellRange(0, 0, 120, 10, 0, 50)
	eq(x0, 0); eq(x1, 2)
end)

test("motif lines: index / nearest / overlay end on endless and NaN points", function()
	ends("index endless", function()
		local ix = L.index({ { 0, 0 }, { -INF, 50 }, { 100, 0 } })
		ok(ix ~= nil)
	end)
	ends("index NaN", function() L.index({ { 0, 0 }, { NAN, NAN }, { 100, 0 } }) end)
	ends("nearest endless r", function()
		local ix = L.index({ { 0, 0 }, { 100, 0 } })
		L.nearest(ix, 50, 10, INF)
		eq(L.nearest(ix, NAN, 0, 20), nil)
	end)
	ends("overlay endless line", function()
		local mp = { junctions = {}, pieces = { { key = "p", a = "a", b = "b", pts = { { -50, -50 }, { 50, 50 } } } } }
		mp.junctions.a, mp.junctions.b = { -50, -50 }, { 50, 50 }
		L.overlay(mp, { { -100, 0 }, { INF, 0 } }, { prefix = "t", every = 80, dense = { cx = 0, cy = 0, r0 = 0, r1 = 1e9, step = 20 } })
	end)
end)

test("graph and terrain queries end on endless / NaN points and zero steps", function()
	local g = F.vanillaTown(nil, { n = 3 })
	ends("nearestNode -inf", function() eq(OG.nearestNode(g, -INF, 0, 50), nil) end)
	ends("edgesNear NaN", function() eq(#OG.edgesNear(g, NAN, 0, 10, 10, 5), 0) end)
	ends("distToEdges endless", function() OG.distToEdges(g, INF, 0, 30) end)
	ends("edgesNear huge box: every edge", function() eq(#OG.edgesNear(g, -1e5, -1e5, 1e5, 1e5, 0), #g.edges) end)
	ends("clearance step 0", function() T.clearance(F.flat, 0, 0, 100, 0) end)
	ends("clearance NaN step", function() T.clearance(F.flat, 0, 0, 100, NAN) end)
	local fg = FO.newGrid(0, 0, 500, 50)
	ends("forest pen endless segment", function() FO.pen({ grid = fg }, { { 0, 0 }, { INF, 0 } }) end)
end)

test("master plans end on endless / NaN extents and a zero ring spacing", function()
	local style = F.style({ forceStyle = "EU_ORGANIC", nameList = "::/names/europe/europe.names" }, F.flat)
	for _, ext in ipairs({ INF, NAN, -5 }) do
		ends("organic extent " .. tostring(ext), function() ORG.masterPlan(style, { extent = ext }) end, 4e9)
	end
	local s2 = {}
	for k, v in pairs(style) do s2[k] = v end
	s2.radial = { spokes = 6, ringEvery = 0 }
	ends("organic ring spacing 0", function() ORG.masterPlan(s2, { extent = 800 }) end, 5e8)
	local grid = F.style({ forceStyle = "NA_GRID" }, F.flat)
	ends("grid extent NaN", function() GRID.masterPlan(grid, { extent = NAN }) end, 5e8)
	-- a stray node 50 km out (a country road / the town network) keeps the plan's extent within core.MAX_EXTENT
	local g = F.vanillaTown(nil, { n = 3 })
	local far = OG.addNode(g, nil, 50000, 0, 20)
	OG.addEdge(g, nil, g.nodes[1].id, far.id, "small")
	ends("plan with a far node", function()
		local inc = core.planIncrement(g, style, { terrain = F.flat, join = "deadEnd", maxEdges = 6 })
		ok(inc ~= nil)
	end, 2e9)
end)

test("selection: the greedy loop stops at its cap (report.iterCap)", function()
	local style = F.style({ forceStyle = "EU_ORGANIC", nameList = "::/names/europe/europe.names" }, F.flat)
	local g = F.vanillaTown(nil, { n = 3 })
	local savedK, savedB = SEL.ITER_PER_EDGE, SEL.ITER_BASE
	SEL.ITER_PER_EDGE, SEL.ITER_BASE = 0, 2
	local okC, streets, _, report = capped(function()
		return ORG.grow(g, style, { terrain = F.flat, maxEdges = 12, join = "deadEnd" })
	end, 2e9)
	SEL.ITER_PER_EDGE, SEL.ITER_BASE = savedK, savedB
	ok(okC, tostring(streets))
	eq(report.iterCap, 2)
	ok(#streets <= 2, "at most one piece per round: " .. #streets)
end)
