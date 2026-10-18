-- ot_select + ot_grow_grid + ot_grow_organic + ot_core: master plans and simulated growth.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local P = ug_require(F.DIR .. "ot_plan.lua")
local S = ug_require(F.DIR .. "ot_select.lua")
local GRID = ug_require(F.DIR .. "ot_grow_grid.lua")
local ORG = ug_require(F.DIR .. "ot_grow_organic.lua")
local core = ug_require(F.DIR .. "ot_core.lua")

local function grow(style, sampler, stats, n, join)
	local g = OG.new()
	local incs = core.simulate(g, style, { terrain = sampler, stats = stats, join = join }, n)
	return g, incs
end

--- Network invariants every simulated town must keep.
local function checkTown(g, incs, label, opts)
	opts = opts or {}
	ok(#incs > 0, label .. ": grew")
	for k, inc in ipairs(incs) do
		ok(#inc.edges <= core.MAX_EDGES, label .. ": increment " .. k .. " within the edge budget")
		ok(P.noNegativeZero(inc), label .. ": no -0 in increment " .. k)
		for _, e in ipairs(inc.edges) do ok(e.template, label .. ": template set") end
	end
	eq(F.components(g), 1, label .. ": one connected network")
	local e1, e2 = F.crossingPair(g)
	ok(e1 == nil, label .. ": no crossing edges" .. (e1 and (" " .. e1.id .. "/" .. e2.id) or ""))
	ok(F.minAngle(g) >= 25 - 1e-6, label .. ": min angle " .. F.minAngle(g))
	local lo, hi = F.edgeLengths(g)
	ok(lo >= 10 - 1e-6, label .. ": shortest edge " .. lo)
	ok(hi <= (opts.maxSeg or core.MAX_SEG_FLAT) + 1e-6, label .. ": longest edge " .. hi)
	if opts.terrain then
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			ok(not T.isWater(opts.terrain, (a.x + b.x) / 2, (a.y + b.y) / 2), label .. ": edge on land")
			if opts.maxGrade then
				ok(T.grade(opts.terrain, a.x, a.y, b.x, b.y) <= opts.maxGrade + 1e-6, label .. ": grade")
			end
		end
	end
end

---------------------------------------------------------------------------
-- grid master plan

test("grid plan: NA lattice spacing 200 x 100 on the axis, main lines through the origin", function()
	local p = F.style({})
	local mp = GRID.masterPlan(p, { extent = 700 })
	near(mp.u[1] - mp.u[0], 200, 200 * 0.05 * 1.7 + 1e-9)
	near(mp.v[1] - mp.v[0], 100, 100 * 0.05 * 1.7 + 1e-9)
	local j = mp.junctions["g0:0"]
	eq({ j[1], j[2] }, { 0, 0 })
	local classes = {}
	for _, pc in ipairs(mp.pieces) do
		classes[pc.key] = pc.class
		ok(G.dist(0, 0, (pc.pts[1][1] + pc.pts[#pc.pts][1]) / 2, (pc.pts[1][2] + pc.pts[#pc.pts][2]) / 2) <= 700)
		eq(mp.junctions[pc.a][1], pc.pts[1][1], "piece starts on its junction")
		eq(mp.junctions[pc.b][2], pc.pts[#pc.pts][2], "piece ends on its junction")
	end
	eq(classes["h0:0"], "main")
	eq(classes["v0:0"], "medium", "late hierarchy: the cross axis is a collector")
	eq(classes["h0:1"], "small")
	-- before 1950: both axes main, no collector lines
	local old = GRID.masterPlan(F.style({ year = 1930 }), { extent = 700 })
	for _, pc in ipairs(old.pieces) do classes[pc.key] = pc.class end
	eq(classes["v0:0"], "main")
	eq(classes["v2:0"], "small")
end)

test("grid plan: deterministic and prefix-stable as the extent grows", function()
	local p = F.style({ nameList = "::/names/japan/x" })
	local a = GRID.masterPlan(p, { extent = 300 })
	local b = GRID.masterPlan(p, { extent = 600 })
	local c = GRID.masterPlan(F.style({ nameList = "::/names/japan/x" }), { extent = 300 })
	for k, j in pairs(a.junctions) do
		eq(b.junctions[k], j, "junction " .. k .. " unchanged")
		eq(c.junctions[k], j)
	end
	ok(#b.pieces > #a.pieces)
end)

test("grid plan: the waterfront line sits at the setback in front of the shore", function()
	local p, stats = F.style({}, F.coast(300))
	local mp = GRID.masterPlan(p, { extent = 600, water = stats.water })
	-- some line along the axis (shore direction) lies at distance - setback from the centre
	local target = stats.water.distance - p.waterSetback
	local best = math.huge
	for j = -6, 6 do
		if mp.v[j] then best = math.min(best, math.abs(math.abs(mp.v[j]) - target)) end
	end
	near(best, 0, 1e-6)
end)

test("grid plan: suburbs beyond 500 m have cul-de-sacs; a strict NA grid bends nothing", function()
	local p = F.style({ year = 1965 })
	local mp = GRID.masterPlan(p, { extent = 1000 })
	local culs, bent, inner = 0, 0, 0
	for _, pc in ipairs(mp.pieces) do
		if pc.zone == "NA_SUBURB" then
			if pc.b:sub(1, 1) == "c" then culs = culs + 1 end
			if pc.curved then bent = bent + 1 end
		elseif pc.curved or pc.b:sub(1, 1) == "c" then
			inner = inner + 1
		end
	end
	ok(culs > 3, "cul-de-sacs " .. culs)
	eq(bent, 0, "no wobbly suburb streets in a strict grid")
	eq(inner, 0, "the grid core stays straight")
end)

---------------------------------------------------------------------------
-- organic master plan

test("organic plan: spokes meet at the centre, pieces share junctions, deterministic", function()
	local p = F.style({ nameList = "::/names/germany/x", capacity = 3000, year = 1900 })
	local mp = ORG.masterPlan(p, { extent = 700 })
	local atCentre = 0
	for _, pc in ipairs(mp.pieces) do
		if pc.a == "C" or pc.b == "C" then atCentre = atCentre + 1 end
		local ja, jb = mp.junctions[pc.a], mp.junctions[pc.b]
		ok(ja and jb, "junctions exist for " .. pc.key)
		near(G.dist(ja[1], ja[2], pc.pts[1][1], pc.pts[1][2]), 0, 1e-9)
		near(G.dist(jb[1], jb[2], pc.pts[#pc.pts][1], pc.pts[#pc.pts][2]), 0, 1e-9)
		ok(G.polyLen(pc.pts) > 1, "no zero-length piece " .. pc.key)
	end
	eq(atCentre, 6)
	local again = ORG.masterPlan(F.style({ nameList = "::/names/germany/x", capacity = 3000, year = 1900 }), { extent = 700 })
	eq(#again.pieces, #mp.pieces)
	for i, pc in ipairs(mp.pieces) do eq(again.pieces[i].pts, pc.pts) end
end)

test("organic plan: spoke/ring junctions are prefix-stable as the extent grows", function()
	local p = F.style({ nameList = "::/names/germany/x", capacity = 3000 })
	local a = ORG.masterPlan(p, { extent = 400 })
	local b = ORG.masterPlan(p, { extent = 900 })
	local n = 0
	for k, j in pairs(a.junctions) do
		if k:sub(1, 1) == "S" then
			n = n + 1
			eq(b.junctions[k], j, "junction " .. k)
		end
	end
	ok(n >= 6)
end)

test("organic plan on a hill: spokes keep within the grade cap", function()
	local p = F.style({ nameList = "::/names/italy/x", climate = "dry" }, F.hill)
	local mp = ORG.masterPlan(p, { extent = 500, terrain = F.hill })
	local worst = 0
	for _, pc in ipairs(mp.pieces) do
		if pc.key:sub(1, 2) == "sp" then
			worst = math.max(worst, T.pathMaxGrade(F.hill, pc.pts, 30))
		end
	end
	ok(worst <= p.maxSlope + 0.01, "steepest spoke " .. worst)
end)

---------------------------------------------------------------------------
-- selection

test("select: an empty town starts at the plan centre and respects the budget", function()
	local p = F.style({})
	local mp = GRID.masterPlan(p, { extent = 500 })
	local streets, rep = S.select(OG.new(), mp, p, { maxEdges = 6 })
	ok(#streets > 0)
	local used = 0
	for _, st in ipairs(streets) do used = used + P.edgeCount(st.pts, 100) end
	ok(used <= 6)
	local first = streets[1].pts
	ok(G.dist(0, 0, first[1][1], first[1][2]) < 1 or G.dist(0, 0, first[#first][1], first[#first][2]) < 1)
	eq(rep.selected, #streets)
end)

test("select: built pieces are recognised, excluded pieces skipped", function()
	local p = F.style({})
	local g = grow(p, F.flat, nil, 3)
	local mp = GRID.masterPlan(p, { extent = 900 })
	local info = S.classify(g, mp, p, {})
	local built = 0
	for _, pc in ipairs(mp.pieces) do if info[pc.key].built then built = built + 1 end end
	ok(built >= 20, "built pieces " .. built)
	local streets = S.select(g, mp, p, {})
	for _, st in ipairs(streets) do ok(not info[st.key].built, "never re-selects a built piece") end
	local excl = {}
	for _, st in ipairs(streets) do excl[st.key] = true end
	local again = S.select(g, mp, p, { exclude = excl })
	for _, st in ipairs(again) do ok(not excl[st.key], "excluded " .. st.key) end
end)

test("select: an engine town with a skewed street gets a connector from its dead end", function()
	-- an engine street at 17 deg, not on the plan
	local g = OG.new()
	local a = OG.addNode(g, nil, -60, -20)
	local b = OG.addNode(g, nil, 60, 17)
	OG.addEdge(g, nil, a.id, b.id)
	local p = F.style({})
	local inc = core.planIncrement(g, p, {})
	ok(#inc.edges > 0, "grew")
	for _, j in ipairs(inc.joins) do
		ok(j.node == a.id or j.node == b.id, "joins only the dead ends")
	end
end)

---------------------------------------------------------------------------
-- simulated towns: invariants per style x terrain

local CASES = {
	{ "NA flat", {}, F.flat },
	{ "NA suburb", { year = 1970 }, F.flat, 30 },
	{ "NA coast", {}, F.coast(300) },
	{ "NA river", {}, F.river(-120) },
	{ "JP station", { nameList = "::/names/japan/x", stations = { { 400, 250 } }, year = 1985 }, F.flat },
	{ "EU flat", { nameList = "::/names/germany/x", year = 1900 }, F.flat },
	{ "EU river", { nameList = "::/names/germany/x", year = 1900 }, F.river(-120) },
	{ "MED hill", { nameList = "::/names/italy/x", climate = "dry", year = 1905 }, F.hill },
	{ "NORDIC coast", { nameList = "::/names/norway/x", climate = "subarctic" }, F.coast(250) },
	{ "ensanche", { nameList = "::/names/spain/x", year = 1930 }, F.flat },
	{ "superblock", { nameList = "::/names/russia/x", year = 1970 }, F.flat },
}

for _, c in ipairs(CASES) do
	test("simulate " .. c[1] .. ": connected, no crossings, angles, lengths, land", function()
		local style, stats = F.style(c[2], c[3])
		local g, incs = grow(style, c[3], stats, c[4] or 8)
		local maxSeg = (stats and stats.meanSlope > core.SLOPE_SPLIT) and core.MAX_SEG_SLOPE or core.MAX_SEG_FLAT
		checkTown(g, incs, c[1], { terrain = c[3], maxSeg = maxSeg, maxGrade = style.maxSlope })
		ok(#g.edges >= 8 * (#incs - 1), c[1] .. ": increments are not tiny (" .. #g.edges .. " edges)")
	end)
end

test("simulate: deterministic for the same town, different for another", function()
	local function run(town)
		local style = F.style({ nameList = "::/names/germany/x", townId = town })
		local _, incs = grow(style, F.flat, nil, 4)
		return F.dump(incs)
	end
	eq(run(3), run(3))
	ok(run(3) ~= run(4))
end)

test("simulate with join = deadEnd: increments only touch dead ends", function()
	local style = F.style({})
	local g = grow(style, F.flat, nil, 2)
	local deadBefore = {}
	for _, id in ipairs(OG.deadEnds(g)) do deadBefore[id] = true end
	local inc = core.planIncrement(g, style, { join = "deadEnd" })
	for _, j in ipairs(inc.joins) do ok(deadBefore[j.node], "join at node " .. j.node .. " was a dead end") end
end)

test("planIncrement: grower by style, short pieces on slopes", function()
	eq(core.grower(F.style({})), GRID)
	eq(core.grower(F.style({ nameList = "::/names/germany/x" })), ORG)
	local style, stats = F.style({ nameList = "::/names/italy/x", climate = "dry" }, F.hill)
	local inc = core.planIncrement(OG.new(), style, { terrain = F.hill, stats = stats })
	for _, e in ipairs(inc.edges) do ok(e.length <= core.MAX_SEG_SLOPE + 1e-6) end
	eq(inc.style, "MED_HILL")
end)

test("alongGraph: a chain of edges along the piece counts as built, a detour does not", function()
	local g = OG.new()
	local a = OG.addNode(g, nil, 0, 0)
	local m = OG.addNode(g, nil, 100, 1)
	local b = OG.addNode(g, nil, 200, 0)
	local d = OG.addNode(g, nil, 100, 80)
	OG.addEdge(g, nil, a.id, m.id)
	OG.addEdge(g, nil, m.id, b.id)
	OG.addEdge(g, nil, a.id, d.id)
	OG.addEdge(g, nil, d.id, b.id)
	ok(S.alongGraph(g, { { 0, 0 }, { 200, 0 } }, a.id, b.id, 6))
	ok(not S.alongGraph(g, { { 0, 0 }, { 100, 80 }, { 200, 0 } }, a.id, m.id, 6))
	ok(S.alongGraph(g, { { 0, 0 }, { 100, 80 }, { 200, 0 } }, a.id, b.id, 6), "the detour piece itself is built")
	ok(not S.alongGraph(g, { { 0, 0 }, { 200, 0 } }, a.id, a.id, 6))
end)

test("matchJunctions: nearest graph node per junction within snapR", function()
	local mp = { junctions = { A = { 0, 0 }, B = { 100, 0 }, C = { 500, 500 } }, pieces = {} }
	local g = OG.new()
	local n1 = OG.addNode(g, nil, 3, 0)
	local n2 = OG.addNode(g, nil, 1, 1)
	local n3 = OG.addNode(g, nil, 100, 9)
	local jnode, keys, used = S.matchJunctions(g, mp, 8)
	eq(keys, { "A", "B", "C" })
	eq(jnode.A, n2.id, "the nearer of two nodes")
	eq(jnode.B, nil, "9 m is beyond snapR")
	ok(used[n2.id] and not used[n1.id] and not used[n3.id])
end)

test("planIncrement reuses the cached master plan while it covers the town", function()
	local style = F.style({ shape = "compact" })
	local g = OG.new()
	local inc1, _, mp1 = core.planIncrement(g, style, { join = "any" })
	OG.apply(g, inc1, 1)
	local inc2, _, mp2 = core.planIncrement(g, style, { join = "any" })
	eq(mp2, mp1, "same plan table")
	OG.apply(g, inc2, 2)
	local plans, last = 1, mp2
	for k = 3, 30 do
		local inc, _, mp = core.planIncrement(g, style, { join = "any" })
		if mp ~= last then plans = plans + 1; last = mp end
		OG.apply(g, inc, k)
	end
	ok(plans >= 2 and plans <= 8, "plans built in 30 increments: " .. plans)
end)

test("leads: no new piece reaches more than one main / two small pieces beyond the existing network (+1 in a shape's arm)", function()
	local SEL = ug_require(F.DIR .. "ot_select.lua")
	for _, names in ipairs({ "::/names/usa/usa.names", "::/names/germany/x", "::/names/japan/x" }) do
		local style = F.style({ nameList = names, capacity = 3000 })
		local g = OG.new()
		local first = core.planIncrement(g, style, { terrain = F.flat, join = "any" })
		OG.apply(g, first, 1)
		local maxD = 0
		for k = 2, 8 do
			local inc, rep = core.planIncrement(g, style, { terrain = F.flat, join = "any" })
			if #inc.edges == 0 then break end
			maxD = math.max(maxD, rep.maxDepth or 0)
			OG.apply(g, inc, k)
		end
		ok(maxD <= 2 + SEL.ARM_LEAD, names .. ": deepest lead " .. maxD)
		ok(maxD >= 1, names .. ": grew")
	end
end)

test("connectors: from an engine dead end only along its street (<= 60 deg) and at least 24 m long", function()
	local SEL = ug_require(F.DIR .. "ot_select.lua")
	-- an east-pointing dead end at (0, 0) and plan junctions north (90 deg off) and east-north-east
	local g = OG.fromSnapshot({ nodes = { { id = 1, x = -80, y = 0 }, { id = 2, x = 0, y = 0 } },
		edges = { { id = 10, node0 = 1, node1 = 2 } } })
	local mp = { junctions = { N = { 0, 40 }, E = { 45, 15 }, F = { 300, 300 } },
		pieces = { { key = "p1", a = "N", b = "F", pts = { { 0, 40 }, { 300, 300 } }, class = "small" },
			{ key = "p2", a = "E", b = "F", pts = { { 45, 15 }, { 300, 300 } }, class = "small" } } }
	local style = F.style({ forceStyle = "EU_ORGANIC" })
	style.centre = { 0, 0 }
	local streets = SEL.select(g, mp, style, { join = "deadEnd", joinR = 100, maxEdges = 4 })
	local conn
	for _, st in ipairs(streets) do if st.key:find("^conn:") then conn = st end end
	ok(conn, "a connector")
	eq(conn.pts[2][1], 45, "toward the junction along the street, not the nearer one 90 deg off")
	SEL.CONN_RULES = false
	streets = SEL.select(g, mp, style, { join = "deadEnd", joinR = 100, maxEdges = 4 })
	SEL.CONN_RULES = true
	for _, st in ipairs(streets) do if st.key:find("^conn:") then conn = st end end
	eq(conn.pts[2][2], 40, "old rule: the nearest")
end)
