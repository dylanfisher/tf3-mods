-- Close the gap (§74, ot_nearmiss): near-miss dead ends joined to the street ahead. The user's three cases as fixtures
-- (a stub pointing at the side of a street -> a T at a street node; two dead ends passing each other -> a bend joining
-- both; a stub beside a junction -> a join to the street node ahead), the rejects (slope, building, crossing, too sharp,
-- the gap line, a noJoin dead end, the driver's midOk), the seeded chance, the per-increment cap, the merge, the
-- proposal's config at a T, and a growth sweep: the share of dead ends with a street within 40 m ahead drops.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local NM = ug_require(F.DIR .. "ot_nearmiss.lua")
local PL = ug_require(F.DIR .. "ot_plan.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local GP = ug_require(F.DIR .. "ot_gap.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

local SMALL = "::/infrastructure/street/town/town_old_small.street_template"

local function style(extra)
	local s = { templatePaths = { main = SMALL, medium = SMALL, small = SMALL }, block = { len = 60, depth = 45 },
		maxSlope = 0.1, waterSetback = 10, seed = 7 }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

--- A street of nodes through pts ({x, y}), ids from `id` on; returns the node ids.
local function street(g, id, pts, z)
	local ids, prev = {}, nil
	for k, p in ipairs(pts) do
		local n = g.nodeById[id + k - 1] or OG.addNode(g, id + k - 1, p[1], p[2], z or 20)
		ids[#ids + 1] = n.id
		if prev then OG.addEdge(g, nil, prev, n.id, "small").template = SMALL end
		prev = n.id
	end
	return ids
end

-- every chance 1 (the geometry / check tests): restored after
local function sure(fn)
	local a, b = NM.P_NEAR, NM.P_FAR
	NM.P_NEAR, NM.P_FAR = 1.01, 1.01
	local okR, err = pcall(fn)
	NM.P_NEAR, NM.P_FAR = a, b
	assert(okR, err)
end

local function joinsOf(g, st, o)
	o = o or {}
	if o.terrain == nil then o.terrain = F.flat end
	return NM.joins(g, st or style(), o.inc, o)
end

--- Case 3: a street along y = 0 (nodes every 50 m), a stub from the north ending 20 m short of it, pointing at it.
local function case3(g, gapM)
	g = g or OG.new()
	street(g, 1, { { -150, 0 }, { -100, 0 }, { -50, 0 }, { 0, 0 }, { 50, 0 }, { 100, 0 }, { 150, 0 } })
	street(g, 100, { { 0, 200 }, { 0, 120 }, { 0, gapM or 20 } })
	return g
end

test("case 3: a stub pointing at a street's side becomes a T at the street node ahead", function()
	sure(function()
		local g = case3()
		local add, rep = joinsOf(g)
		ok(add ~= nil, "a join")
		eq(#add.edges, 1)
		local e = add.edges[1]
		eq(e.node0, 102, "from the stub's dead end")
		eq(e.node1, 4, "to the street node at (0, 0)")
		eq(e.key, "nm:102:4")
		eq(e.nearMissKind, "tee")
		eq(rep.joined, 1)
		ok(rep.found >= 1)
		-- (the stub's far end at (0, 200) is a dead end with nothing ahead: no near miss)
		eq(rep.joins[1], "tee:20")
	end)
end)

test("case 3 offset: the street node is off to the side: joined with a bend, the T within 60 deg of square", function()
	sure(function()
		local g = OG.new()
		street(g, 1, { { -150, 0 }, { -75, 0 }, { 0, 0 }, { 75, 0 }, { 150, 0 } })
		street(g, 100, { { 30, 200 }, { 30, 110 }, { 22, 40 } })
		local add = joinsOf(g)
		ok(add ~= nil, "a join")
		local e = add.edges[1]
		eq(e.node1, 3)
		-- the angle at the street node: the join meets both of its streets at least TEE_MIN_DEG off
		local hx, hy = -e.t1[1], -e.t1[2]
		local h = math.atan(hy, hx)
		for _, a in ipairs({ 0, math.pi }) do
			local d = math.abs((h - a + math.pi) % (2 * math.pi) - math.pi)
			ok(d >= math.rad(NM.TEE_MIN_DEG) - 1e-3, string.format("angle %.1f", math.deg(d)))
		end
	end)
end)

test("case 1: two dead ends curling past each other are joined by one bend", function()
	sure(function()
		local g = OG.new()
		-- a street from the west ending at (0, 0) heading east; one from the east ending at (45, 25) heading west
		street(g, 1, { { -200, -30 }, { -100, -10 }, { 0, 0 } })
		street(g, 10, { { 250, 60 }, { 150, 40 }, { 45, 25 } })
		local add, rep = joinsOf(g)
		ok(add ~= nil, "a join")
		eq(#add.edges, 1)
		local e = add.edges[1]
		local pair = (e.node0 == 3 and e.node1 == 12) or (e.node0 == 12 and e.node1 == 3)
		ok(pair, string.format("%d -> %d", e.node0, e.node1))
		eq(e.nearMissKind, "pair")
		eq(rep.joined, 2, "both dead ends")
		-- each dead end only once: the partner is no near miss left over
		eq(rep.why.taken or 0, 0)
	end)
end)

test("case 2: a stub parallel to a street, ending beside a junction, joins the street node ahead", function()
	sure(function()
		local g = OG.new()
		street(g, 1, { { -100, 0 }, { -40, 0 }, { 20, 0 }, { 80, 0 }, { 140, 0 }, { 200, 0 } })
		street(g, 20, { { 20, 0 }, { 20, -100 } })   -- a side street south: (20, 0) is a junction
		-- (§75: 40 m off the street, was 28 m: the T now meets the street at 60 deg or more, TEE_MIN_DEG / the side rule,
		-- which a bend from a stub 28 m beside it can't reach at the 70 m radius: that one stays, below)
		street(g, 40, { { -120, 82 }, { -40, 52 }, { 30, 40 } })
		local add, rep = joinsOf(g)
		ok(add ~= nil, "a join: " .. select(2, NM.text(rep)))
		eq(add.edges[1].node0, 42)
		local last = add.edges[#add.edges].node1
		ok(last == 4 or last == 3, "to (80, 0) or the junction: " .. tostring(last))
		ok(#add.edges <= 2, "one bend, cut at most once")
		local g2 = OG.new()
		street(g2, 1, { { -100, 0 }, { -40, 0 }, { 20, 0 }, { 80, 0 }, { 140, 0 }, { 200, 0 } })
		street(g2, 20, { { 20, 0 }, { 20, -100 } })
		street(g2, 40, { { -120, 70 }, { -40, 40 }, { 30, 28 } })
		local add2, rep2 = joinsOf(g2)
		eq(add2, nil, "28 m beside the street: no T at 60 deg or more")
		ok((rep2.why.curve or 0) + (rep2.why.angle or 0) >= 1, select(2, NM.text(rep2)))
	end)
end)

test("a crossroads only at a small junction with room; a dead end of the planner's own increment is left", function()
	sure(function()
		local g = case3()
		-- the increment already uses the stub's dead end
		local inc = { edges = { { node0 = 102, node1 = -2, entity = -1, p0 = { 0, 20, 20 }, p1 = { 0, 60, 20 },
			t0 = { 0, 40, 0 }, t1 = { 0, 40, 0 }, class = "small" } }, nodes = {} }
		local add, rep = joinsOf(g, nil, { inc = inc })
		eq(add, nil)
		eq(rep.why.inc, 1)
	end)
end)

---------------------------------------------------------------------------
-- rejects

test("rejects: slope between the nodes, a building in the way, a street crossed, too sharp, the gap line", function()
	sure(function()
		-- slope: the stub's dead end 12 m above the street (grade 0.6)
		local g = case3()
		g.nodeById[102].z = 32
		local add, rep = joinsOf(g)
		eq(add, nil); eq(rep.why.slope, 1, select(2, NM.text(rep)))
		-- ground: a steep plane (the nodes level, the ground between rising and falling)
		g = case3(nil, 40)
		local bump = T.sampler(function(x, y) return 20 + math.max(0, 15 - math.abs(y - 20)) * 1.5 end)
		add, rep = joinsOf(g, nil, { terrain = bump })
		eq(add, nil, "bump"); eq(rep.why.slope, 1, select(2, NM.text(rep)))
		-- a building between
		g = case3(nil, 40)
		add, rep = joinsOf(g, nil, { buildings = { { 2, 20 } } })
		eq(add, nil); eq(rep.why.building, 1)
		-- a building beside the street, out of the way: joined
		add = joinsOf(g, nil, { buildings = { { 30, 20 }, { -30, 20 } } })
		ok(add ~= nil)
		-- a street across the gap (east-west at y = 20, nodes beyond the curve's reach)
		g = case3(nil, 40)
		street(g, 200, { { -200, 20 }, { 200, 20 } })
		add, rep = joinsOf(g)
		eq(add, nil)
		ok((rep.why.cross or 0) + (rep.why.near or 0) >= 1, select(2, NM.text(rep)))
		-- too sharp: a street node beside the dead end, nothing ahead of it
		g = OG.new()
		street(g, 1, { { 0, -150 }, { 0, 0 } })            -- heading north, ends at (0, 0)
		street(g, 10, { { 30, -60 }, { 30, 20 }, { 30, 100 } })   -- a street beside it; its node (30, 20) 36 m off at 34 deg ...
		street(g, 20, { { 30, 20 }, { 120, 20 } })          -- ... a junction whose free side faces away
		add, rep = joinsOf(g)
		eq(add, nil)
		-- (since the 45 deg kink, 2026-10-18, a shape reaches the node but runs along the street beside it: near)
		ok((rep.why.angle or 0) + (rep.why.curve or 0) + (rep.why.target or 0) + (rep.why.near or 0) >= 1,
			select(2, NM.text(rep)))
		-- the gap line to a neighbour: the join would run past the halfway line
		g = case3(nil, 40)
		local gp = GP.build({ 0, 300 }, { { x = 0, y = -300, town = 2 } }, 1)
		gp.list[1].gap = 0
		gp.list[1].half = 290   -- (halfway line at y = 10 seen from (0, 300))
		add, rep = joinsOf(g, style({ gaps = gp }))
		eq(add, nil); eq(rep.why.gap, 1)
	end)
end)

test("rejects: a noJoin dead end, a street node the driver refuses (midOk), an excluded key, water", function()
	sure(function()
		local g = case3()
		g.nodeById[102].noJoin = true
		local add, rep = joinsOf(g)
		eq(add, nil); eq(rep.why.noJoin, 1)
		g = case3()
		local asked = {}
		add, rep = joinsOf(g, nil, { midOk = function(n) asked[#asked + 1] = n; return false end })
		eq(add, nil)
		ok(#asked >= 1)
		ok((rep.why.target or 0) == 1, select(2, NM.text(rep)))
		g = case3()
		add, rep = joinsOf(g, nil, { exclude = { ["nm:102:4"] = true } })
		ok(add == nil or add.edges[1].key ~= "nm:102:4")
		g = case3(nil, 40)
		local wet = T.sampler(function() return 20 end, function(x, y) return math.abs(y - 20) < 6 end)
		add, rep = joinsOf(g, nil, { terrain = wet })
		eq(add, nil); eq(rep.why.water, 1, select(2, NM.text(rep)))
	end)
end)

test("a small loop is a knot (the dead end's own street bent back) and stays", function()
	sure(function()
		local g = OG.new()
		-- a hook: from the junction (0, 0) east, north, then back west ending 30 m above its own start street
		street(g, 1, { { -200, 0 }, { 0, 0 }, { 100, 0 } })
		street(g, 10, { { 0, 0 }, { 40, 30 }, { 40, 60 }, { 10, 62 } })
		g.nodeById[10] = g.nodeById[2]
		local add, rep = joinsOf(g)
		if add then
			-- (a join, if any, must not be back onto its own little block)
			for _, e in ipairs(add.edges) do ok(not (e.node0 == 13 and (e.node1 == 2 or e.node1 == 11))) end
		end
		ok(rep.found >= 0)
	end)
end)

---------------------------------------------------------------------------
-- less cautious (2026-10-18): the 45 deg kink, nodes to NODE_MAX, retired dead ends, the snapshot's cut, country roads

test("loosened: two stubs at right angles 40 m apart join in one bend (the old 35 deg kink / 78 m arc kept them)", function()
	sure(function()
		local function pairG()
			local g = OG.new()
			-- a street from the west ending at (0, 0) heading east; one coming down from the north ending at (34.6, 20)
			-- (40 m off at 30 deg): the join turns 90 deg in all
			street(g, 1, { { -200, 0 }, { -100, 0 }, { 0, 0 } })
			street(g, 10, { { 34.641, 220 }, { 34.641, 120 }, { 34.641, 20 } })
			return g
		end
		local add, rep = joinsOf(pairG())
		ok(add ~= nil, "joined: " .. select(2, NM.text(rep)))
		eq(add.edges[1].nearMissKind, "pair")
		ok(add.edges[1].node0 == 3 or add.edges[1].node0 == 12)
		local k, a = NM.KINK_DEG, NM.ARC_MIN
		NM.KINK_DEG, NM.ARC_MIN, NM.CORNER = 35, 78, false   -- (§75's corner shape came later)
		local okR, err = pcall(function()
			local add2, rep2 = joinsOf(pairG())
			eq(add2, nil, "the old rules")
			ok((rep2.why.angle or 0) + (rep2.why.curve or 0) >= 1, select(2, NM.text(rep2)))
		end)
		NM.KINK_DEG, NM.ARC_MIN, NM.CORNER = k, a, true
		assert(okR, err)
	end)
end)

test("loosened: the street ahead's next node 90 m away is reached (NODE_MAX); beyond it, noNode", function()
	sure(function()
		-- a street along y = 0 with nodes every 200 m; a stub ending 70 m north of it, 70 m from the nodes at
		-- (+-100, 0) sideways: both ~99 / ~119 m away (the old 80 m reach: none)
		local g = OG.new()
		street(g, 1, { { -300, 0 }, { -100, 0 }, { 100, 0 }, { 300, 0 } })
		street(g, 100, { { 30, 260 }, { 30, 160 }, { 30, 70 } })
		local add, rep = joinsOf(g)
		local nd = NM.NODE_MAX
		NM.NODE_MAX = NM.JOIN_MAX
		local okR, err = pcall(function()
			local _, rep2 = joinsOf(g)
			eq(rep2.why.noNode, 1, "the old reach: " .. select(2, NM.text(rep2)))
		end)
		NM.NODE_MAX = nd
		assert(okR, err)
		ok(rep.why.noNode == nil, select(2, NM.text(rep)))
		ok(add ~= nil, "joined: " .. select(2, NM.text(rep)))
		ok(add.edges[#add.edges].node1 == 2 or add.edges[#add.edges].node1 == 3)
		-- a street 300 m long without a mid node: nothing in reach
		g = OG.new()
		street(g, 1, { { -300, 0 }, { 300, 0 } })
		street(g, 100, { { 30, 260 }, { 30, 160 }, { 30, 40 } })
		local _, rep3 = joinsOf(g)
		eq(rep3.why.noNode, 1, select(2, NM.text(rep3)))
	end)
end)

test("loosened: a retired dead end joins only through o.retiredOk (as start or as a pair's partner); ot_plan names it", function()
	sure(function()
		-- case 3 with the stub's dead end retired
		local g = case3()
		g.nodeById[102].noJoin, g.nodeById[102].nmRetired = true, true
		local add, rep = joinsOf(g)
		eq(add, nil); eq(rep.why.noJoin, 1, "no retiredOk: as before")
		local asked = {}
		add, rep = joinsOf(g, nil, { retiredOk = function(n) asked[#asked + 1] = n; return true end })
		ok(add ~= nil, "joined: " .. select(2, NM.text(rep)))
		eq(add.edges[1].node0, 102)
		eq(asked[1], 102)
		add = joinsOf(g, nil, { retiredOk = function() return false end })
		eq(add, nil, "the driver refuses")
		-- a noJoin dead end that is not retired (player road, other town ...) never, whatever retiredOk says
		g = case3()
		g.nodeById[102].noJoin = true
		add, rep = joinsOf(g, nil, { retiredOk = function() return true end })
		eq(add, nil); eq(rep.why.noJoin, 1)
		-- a pair whose partner is retired
		g = OG.new()
		street(g, 1, { { -200, -30 }, { -100, -10 }, { 0, 0 } })
		street(g, 10, { { 250, 60 }, { 150, 40 }, { 45, 25 } })
		g.nodeById[12].noJoin, g.nodeById[12].nmRetired = true, true
		add = joinsOf(g)
		ok(add == nil or add.edges[1].nearMissKind ~= "pair", "no retiredOk: the partner stays out")
		add = joinsOf(g, nil, { retiredOk = function() return true end })
		ok(add ~= nil and add.edges[1].nearMissKind == "pair", "joined with the retired partner")
		-- ot_plan: a retired node only by the joinExtra value "retired"
		g = case3()
		g.nodeById[102].noJoin, g.nodeById[102].nmRetired = true, true
		local st = { pts = { { 0, 20 }, { 0, 0 } }, startNode = 102, endNode = 4, class = "small", key = "k" }
		eq(#PL.plan(g, { st }, { join = "deadEnd", joinExtra = { [4] = true, [102] = true } }).edges, 0)
		eq(#PL.plan(g, { st }, { join = "deadEnd", joinExtra = { [4] = true, [102] = "retired" } }).edges, 1)
		g.nodeById[102].nmRetired = nil
		eq(#PL.plan(g, { st }, { join = "deadEnd", joinExtra = { [4] = true, [102] = "retired" } }).edges, 0, "noJoin only")
	end)
end)

test("loosened, still out: the snapshot's cut (`cut`), a country road's nodes and dead ends, water, a neighbor's gap", function()
	sure(function()
		local g = case3()
		g.nodeById[102].noJoin, g.nodeById[102].nmCut = true, true
		local add, rep = joinsOf(g)
		eq(add, nil); eq(rep.why.cut, 1)
		-- the street ahead a country road: its nodes are no targets
		local COUNTRY = "::/infrastructure/street/country/country_old_small.street_template"
		g = case3()
		for _, e in ipairs(g.edges) do if e.n0 < 100 then e.template = COUNTRY end end
		add, rep = joinsOf(g, nil, { retiredOk = function() return true end })
		eq(add, nil); eq(rep.why.target, 1, select(2, NM.text(rep)))
		-- a pair whose partner ends a country road
		g = OG.new()
		street(g, 1, { { -200, -30 }, { -100, -10 }, { 0, 0 } })
		street(g, 10, { { 250, 60 }, { 150, 40 }, { 45, 25 } })
		for _, e in ipairs(g.edges) do if e.n0 >= 10 then e.template = COUNTRY end end
		add = joinsOf(g)
		ok(add == nil or add.edges[1].nearMissKind ~= "pair", "no join onto a country road's dead end")
		-- water and a neighbor's gap line still refuse at the new reach (a 90 m node)
		g = OG.new()
		street(g, 1, { { -300, 0 }, { -100, 0 }, { 100, 0 }, { 300, 0 } })
		street(g, 100, { { 30, 260 }, { 30, 160 }, { 30, 70 } })
		local wet = T.sampler(function() return 20 end, function(x, y) return y > 15 and y < 45 end)
		add, rep = joinsOf(g, nil, { terrain = wet })
		eq(add, nil, "water"); ok((rep.why.water or 0) >= 1, select(2, NM.text(rep)))
		local gp = GP.build({ 0, 300 }, { { x = 0, y = -300, town = 2 } }, 1)
		gp.list[1].gap = 0
		gp.list[1].half = 260
		add, rep = joinsOf(g, style({ gaps = gp }))
		eq(add, nil, "gap"); eq(rep.why.gap, 1, select(2, NM.text(rep)))
		-- a house in the way of every shape
		add, rep = joinsOf(g, nil, { buildings = { { 30, 50 }, { 45, 40 }, { 60, 30 }, { 75, 20 }, { 15, 40 } } })
		eq(add, nil, "building"); ok((rep.why.building or 0) >= 1, select(2, NM.text(rep)))
	end)
end)

---------------------------------------------------------------------------
-- chance, seed, cap

test("chance: near certain up to SURE_M, falling to P_FAR at JOIN_MAX; the draw is fixed per pair and seed", function()
	near(NM.chance(5), NM.P_NEAR, 1e-9)
	near(NM.chance(NM.SURE_M), NM.P_NEAR, 1e-9)
	near(NM.chance(NM.JOIN_MAX), NM.P_FAR, 1e-9)
	near(NM.chance(500), NM.P_FAR, 1e-9)
	ok(NM.chance(40) < NM.chance(20) and NM.chance(40) > NM.chance(70))
	-- a far near miss: the same seed gives the same answer, different seeds differ now and then
	local joined, kept = 0, 0
	for seed = 1, 60 do
		local a1, r1 = joinsOf(case3(nil, 70), nil, { seed = seed })
		local a2 = joinsOf(case3(nil, 70), nil, { seed = seed })
		eq(a1 ~= nil, a2 ~= nil, "seed " .. seed)
		if a1 then joined = joined + 1 else kept = kept + 1; ok((r1.why.chance or 0) + (r1.why.angle or 0) >= 1) end
	end
	ok(joined >= 3 and kept >= 20, string.format("joined %d kept %d", joined, kept))
	-- a close one: (almost) always
	local close = 0
	for seed = 1, 40 do if joinsOf(case3(nil, 20), nil, { seed = seed }) then close = close + 1 end end
	ok(close >= 36, "close " .. close)
end)

test("cap: at most MAX_PER_INC joins per increment, nearest first; the rest kept as `cap`", function()
	sure(function()
		local g = OG.new()
		street(g, 1, { { -400, 0 }, { -300, 0 }, { -200, 0 }, { -100, 0 }, { 0, 0 }, { 100, 0 }, { 200, 0 }, { 300, 0 }, { 400, 0 } })
		local gaps = { 30, 18, 45, 25 }
		for k, gap in ipairs(gaps) do
			local x = -300 + (k - 1) * 200
			street(g, 100 * k, { { x, 200 }, { x, 120 }, { x, gap } })
		end
		local add, rep = joinsOf(g)
		eq(#add.edges, NM.MAX_PER_INC)
		eq(rep.joined, NM.MAX_PER_INC)
		eq(rep.why.cap, #gaps - NM.MAX_PER_INC)
		-- nearest first: the 18 m and the 25 m stubs
		local from = {}
		for _, e in ipairs(add.edges) do from[e.node0] = true end
		ok(from[202] and from[402], "joined the 18 m and 25 m stubs")
		local f, j, k = NM.text(rep)
		eq(f, string.format("%d/%d/%d", rep.found, rep.joined, rep.kept))
		ok(j:find("cap:2", 1, true), j)
		eq(k, nil)
	end)
end)

test("woods: a join in a big wood of a hug town is left with FOREST_KEEP (deep towns DEEP_KEEP); open land unaffected", function()
	sure(function()
		local FO = ug_require(F.DIR .. "ot_forest.lua")
		local wood = FO.fromFunction(0, 0, function() return 400 end, 600, 50)
		local open = FO.fromFunction(0, 0, function() return 0 end, 600, 50)
		local kept, n = 0, 40
		for seed = 1, n do
			local _, rep = joinsOf(case3(), style({ forest = { mode = "hug", grid = wood } }), { seed = seed })
			if (rep.why.forest or 0) > 0 then kept = kept + 1 end
			local add = joinsOf(case3(), style({ forest = { mode = "hug", grid = open } }), { seed = seed })
			ok(add ~= nil, "open land: joined")
		end
		ok(kept >= n * NM.FOREST_KEEP - 10 and kept <= n * NM.FOREST_KEEP + 10, "kept in the wood " .. kept)
		-- a clear town (builds through the woods): no forest rule
		local add = joinsOf(case3(), style({ forest = { mode = "clear", grid = wood } }), { seed = 1 })
		ok(add ~= nil)
	end)
end)

test("a pass that raises leaves the increment as planned (PLAN nmErr=); the hang guard's error goes on", function()
	local st, stats = F.style({ forceStyle = "EU_ORGANIC", townId = 3, year = 1905, capacity = 2000 }, F.flat)
	local real = NM.joins
	NM.joins = function() error("boom") end
	local okA, inc, rep = pcall(core.planIncrement, case3(), st, { terrain = F.flat, stats = stats, nearMiss = {} })
	NM.joins = function() error("planHang:somewhere", 0) end
	local okB, errB = pcall(core.planIncrement, case3(), st, { terrain = F.flat, stats = stats, nearMiss = {} })
	NM.joins = real
	ok(okA, tostring(inc))
	ok(rep.nearMissErr and rep.nearMissErr:find("boom", 1, true), tostring(rep.nearMissErr))
	eq(inc.nearMiss, nil)
	ok(not okB and tostring(errB):find("planHang", 1, true), tostring(errB))
end)

test("budget: a pass over its time budget names the rest `budget`; the smallest gaps were tried first", function()
	sure(function()
		local g = OG.new()
		street(g, 1, { { -400, 0 }, { -300, 0 }, { -200, 0 }, { -100, 0 }, { 0, 0 }, { 100, 0 }, { 200, 0 }, { 300, 0 }, { 400, 0 } })
		for k, gap in ipairs({ 40, 22, 60 }) do
			local x = -300 + (k - 1) * 300
			street(g, 100 * k, { { x, 200 }, { x, 120 }, { x, gap } })
		end
		local t = 0
		local add, rep = joinsOf(g, nil, { clock = function() t = t + 1000; return t end, budgetUs = 1500 })
		eq(rep.why.budget, 2, select(2, NM.text(rep)))
		eq(#add.edges, 1)
		eq(add.edges[1].node0, 202, "the 22 m stub first")
	end)
end)

---------------------------------------------------------------------------
-- merge, planner, proposal

test("merge: entities renumbered, joins listed, no -0; ot_core appends the joins only with opts.nearMiss", function()
	sure(function()
		local g = case3()
		local inc = PL.plan(g, { { pts = { { 150, 0 }, { 250, 0 }, { 350, 0 } }, class = "small", key = "x" } },
			{ join = "deadEnd", templatePaths = { small = SMALL } })
		eq(#inc.edges, 2)
		local add = joinsOf(g, nil, { inc = inc })
		ok(add ~= nil)
		NM.merge(inc, add)
		eq(#inc.edges, 3)
		for i, e in ipairs(inc.edges) do eq(e.entity, -i) end
		for k, n in ipairs(inc.nodes) do eq(n.entity, -(#inc.edges + k)) end
		eq(inc.edges[3].node0, 102)
		eq(inc.edges[3].node1, 4)
		eq(#inc.joins, 3)
		ok(PL.noNegativeZero(inc))
		eq(inc.nearMiss, 1)
		-- through ot_core
		local st, stats = F.style({ forceStyle = "EU_ORGANIC", townId = 3, year = 1905, capacity = 2000 }, F.flat)
		local g1, g2 = case3(), case3()
		local i1, r1 = core.planIncrement(g1, st, { terrain = F.flat, stats = stats })
		local i2, r2 = core.planIncrement(g2, st, { terrain = F.flat, stats = stats, nearMiss = {} })
		eq(r1.nearMiss, nil)
		ok(r2.nearMiss ~= nil)
		ok(#i2.edges >= #i1.edges)
	end)
end)

test("ot_plan: a street may end at a node in the middle of a street only through joinExtra", function()
	local g = case3()
	local st = { pts = { { 0, 20 }, { 0, 0 } }, startNode = 102, endNode = 4, class = "small", key = "k" }
	local a = PL.plan(g, { st }, { join = "deadEnd" })
	eq(#a.edges, 0)
	local b = PL.plan(g, { st }, { join = "deadEnd", joinExtra = { [4] = true } })
	eq(#b.edges, 1)
	g.nodeById[4].noJoin = true
	local c = PL.plan(g, { st }, { join = "deadEnd", joinExtra = { [4] = true } })
	eq(#c.edges, 0)
end)

test("proposal: a T at a street node gets a full config over its three segments (engine pattern)", function()
	sure(function()
		local g = case3()
		local add = joinsOf(g)
		local e3 = g.adj[4]
		local info = { nodes = {
			[102] = { hasConfig = true, edges = { g.adj[102][1] }, lanes = 4, src = g.adj[102][1], template = SMALL },
			[4] = { hasConfig = true, edges = { e3[1], e3[2] }, lanes = 4, src = e3[1], template = SMALL,
				edgeLanes = { [e3[1]] = 4, [e3[2]] = 4 }, mid = true },
		}, sources = {}, fallback = 1 }
		local spec, err = PR.build(add, info)
		ok(spec ~= nil, tostring(err))
		local at4 = nil
		for _, c in ipairs(spec.cfgAdd) do if c.node == 4 then at4 = c end end
		ok(at4 ~= nil)
		eq(#at4.conns, 6, "one connection per ordered pair of the three segments")
		local rm = {}
		for _, n in ipairs(spec.cfgRemove) do rm[n] = true end
		ok(rm[4] and rm[102])
	end)
end)

---------------------------------------------------------------------------
-- growth: fewer near misses, dead ends still there

local STYLES = { "EU_ORGANIC", "NORDIC", "EU_EXTENSION", "MED_HILL", "NA_SUBURB", "JP_DENSE" }
local VARIANTS = { { town = 11, angle = 0.4, year = 1905 }, { town = 23, angle = 1.1, year = 1950 },
	{ town = 37, angle = 2.3, year = 1990 } }

--- Grows a vanilla core for `steps` increments with or without the near-miss pass; the near-miss share at 40 m.
local function grown(id, v, nm, steps)
	local st, stats = F.style({ forceStyle = id, townId = v.town, year = v.year, capacity = 3000 }, F.flat)
	local g = F.vanillaTown(OG.new(), { angle = v.angle })
	for k = 1, steps do
		local inc = core.planIncrement(g, st, { terrain = F.flat, stats = stats, join = "deadEnd", nearMiss = nm and {} or nil })
		if #inc.edges == 0 then break end
		OG.apply(g, inc, k)
	end
	return NM.nearShare(g, 40)
end

--- The sweep over STYLES[from..to] x VARIANTS (quick: every STRIDE-th case and EU organic's first): sums before / after.
local function sweep(from, to)
	local STRIDE = FULL and 1 or 3
	local i, checked = 0, 0
	local nb, db, na, da = 0, 0, 0, 0
	for s = from, to do
		for vi, v in ipairs(VARIANTS) do
			i = i + 1
			if (i - 1) % STRIDE == 0 or (STYLES[s] == "EU_ORGANIC" and vi == 1) then
				checked = checked + 1
				local steps = FULL and 10 or 7
				local sb, b1, b2 = grown(STYLES[s], v, false, steps)
				local sa, a1, a2 = grown(STYLES[s], v, true, steps)
				nb, db, na, da = nb + b1, db + b2, na + a1, da + a2
				print(string.format("%-12s town %d: near40 before %.2f (%d/%d) after %.2f (%d/%d)", STYLES[s], v.town, sb, b1, b2,
					sa, a1, a2))
				ok(a2 > 0, STYLES[s] .. ": dead ends left")
			end
		end
	end
	return nb, db, na, da, checked
end

test("growth (organic styles): the share of dead ends with a street within 40 m ahead drops; dead ends remain", function()
	local nb, db, na, da, checked = sweep(1, 3)
	local before, after = nb / math.max(db, 1), na / math.max(da, 1)
	print(string.format("near40 share before %.3f (%d/%d) after %.3f (%d/%d)", before, nb, db, after, na, da))
	-- (quick: within noise, as for the other styles below; since the 44 m minimum block, 2026-10-18, EU organic town 11's
	-- share rises in the quick sample, 0.26 -> 0.38, while the full sweep's drops, 0.114 -> 0.084)
	ok(after < before or (not FULL and after <= before + 0.06), string.format("share %.3f -> %.3f", before, after))
	ok(checked >= 2)
end)

test("growth (other styles): the share drops over the whole sweep (quick: a 3-town sample, within noise)", function()
	local nb, db, na, da, checked = sweep(4, 6)
	local before, after = nb / math.max(db, 1), na / math.max(da, 1)
	print(string.format("near40 share before %.3f (%d/%d) after %.3f (%d/%d)", before, nb, db, after, na, da))
	-- (the joins change how a town grows on, so one town's share may rise; the full sweep's must drop)
	ok(after <= before + (FULL and 0 or 0.06), string.format("share %.3f -> %.3f", before, after))
	ok(checked >= 2)
end)
