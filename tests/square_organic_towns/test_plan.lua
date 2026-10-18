-- ot_plan: polylines -> SimpleProposal-shaped node/edge specs.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local P = ug_require(F.DIR .. "ot_plan.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local G = ug_require(F.DIR .. "ot_geom.lua")

local TPL = { main = "M.tpl", medium = "D.tpl", small = "S.tpl" }

local function reasons(inc)
	local r = {}
	for _, d in ipairs(inc.dropped) do r[d.reason] = (r[d.reason] or 0) + 1 end
	return r
end

--- A T-shaped existing network: (0,0)-(100,0)-(200,0) and (100,0)-(100,100). Dead ends: 1, 3, 4.
local function tee()
	return OG.fromSnapshot({
		nodes = { { id = 1, x = 0, y = 0, z = 5 }, { id = 2, x = 100, y = 0, z = 5 }, { id = 3, x = 200, y = 0, z = 5 },
			{ id = 4, x = 100, y = 100, z = 5 } },
		edges = { { id = 10, node0 = 1, node1 = 2 }, { id = 11, node0 = 2, node1 = 3 }, { id = 12, node0 = 2, node1 = 4 } },
	})
end

test("straight street on an empty graph: split evenly, SimpleProposal id convention", function()
	local inc = P.plan(OG.new(), { { pts = { { 0, 0 }, { 250, 0 } }, class = "main" } },
		{ maxSeg = 100, templatePaths = TPL })
	eq(#inc.edges, 3)
	eq(#inc.nodes, 4)
	eq({ inc.edges[1].entity, inc.edges[2].entity, inc.edges[3].entity }, { -1, -2, -3 })
	eq({ inc.nodes[1].entity, inc.nodes[4].entity }, { -4, -7 })
	eq(inc.edges[1].node0, -4)
	eq(inc.edges[1].node1, inc.edges[2].node0, "pieces share nodes")
	eq(inc.edges[1].template, "M.tpl")
	eq(inc.edges[1].class, "main")
	near(inc.edges[1].length, 250 / 3, 1e-9)
	eq(inc.joins, {})
	near(inc.stats.length, 250, 1e-9)
end)

test("tangents: chord length with z on straight pieces; smooth on curved streets", function()
	local s = F.plane(0.05, 0)
	local inc = P.plan(OG.new(), { { pts = { { 0, 0 }, { 80, 0 } } } }, { terrain = s })
	local e = inc.edges[1]
	eq(e.t0, { 80, 0, 4 })
	eq(e.t1, { 80, 0, 4 })
	eq(e.p0[3], 50)
	eq(e.p1[3], 54)
	-- curved: a quarter arc; at the shared middle node both edges have the same tangent direction
	local arc = {}
	for k = 0, 8 do
		local a = k / 8 * math.pi / 2
		arc[#arc + 1] = { 200 * math.cos(a), 200 * math.sin(a) }
	end
	local c = P.plan(OG.new(), { { pts = arc, curved = true } }, { maxSeg = 100 })
	ok(#c.edges >= 4)
	for i = 2, #c.edges do
		local a, b = c.edges[i - 1], c.edges[i]
		eq(a.node1, b.node0)
		local h1 = G.atan2(a.t1[2], a.t1[1])
		local h0 = G.atan2(b.t0[2], b.t0[1])
		near(G.angleDiff(h1, h0), 0, 1e-3)
		near(G.len(b.t0[1], b.t0[2]), b.length, 1e-2)
	end
end)

test("streets snap onto each other's nodes", function()
	local inc = P.plan(OG.new(), {
		{ pts = { { 0, 0 }, { 100, 0 } } },
		{ pts = { { 100.5, 3 }, { 100, 100 } } },
	}, {})
	eq(#inc.edges, 2)
	eq(#inc.nodes, 3)
	eq(inc.edges[1].node1, inc.edges[2].node0)
end)

test("join policy: dead ends join, a degree-3 node is blocked unless join = any", function()
	local g = tee()
	local inc = P.plan(g, { { pts = { { 0, 0 }, { -100, 0 } } } }, {})
	eq(#inc.edges, 1)
	eq(inc.edges[1].node0, 1)
	eq(inc.joins, { { node = 1, edge = -1 } })
	eq(inc.edges[1].p0[3], 5, "existing node z kept")
	local blocked = P.plan(g, { { pts = { { 100, 0 }, { 100, -100 } } } }, {})
	eq(#blocked.edges, 0)
	eq(reasons(blocked).blockedNode, 1)
	local any = P.plan(g, { { pts = { { 100, 0 }, { 100, -100 } } } }, { join = "any" })
	eq(#any.edges, 1)
	eq(any.edges[1].node0, 2)
	local none = P.plan(g, { { pts = { { 0, 0 }, { -100, 0 } } } }, { join = "none" })
	eq(#none.edges, 0)
	-- explicit startNode goes through the same check
	local ex = P.plan(g, { { pts = { { 100, 0 }, { 100, -100 } }, startNode = 2 } }, {})
	eq(#ex.edges, 0)
	local ex2 = P.plan(g, { { pts = { { 0, 0 }, { -100, 0 } }, startNode = 1 } }, {})
	eq(ex2.edges[1].node0, 1)
end)

test("growth must connect: free-standing streets are dropped on a non-empty graph", function()
	local g = tee()
	local inc = P.plan(g, {
		{ pts = { { 0, 0 }, { -100, 0 } } },
		{ pts = { { 500, 500 }, { 600, 500 } } },
	}, {})
	eq(#inc.edges, 1)
	eq(reasons(inc).disconnected, 1)
	local free = P.plan(g, { { pts = { { 500, 500 }, { 600, 500 } } } }, { requireConnected = false })
	eq(#free.edges, 1)
end)

test("refusals: crossing existing / new streets, steep, water, sharp angle, short, duplicate", function()
	local g = tee()
	-- the 180 m piece splits at (75, 0), right on the existing street: refused as a blocked node (new nodes
	-- keep `clear` metres off existing streets) or, without the split, as a crossing
	local r1 = reasons(P.plan(g, { { pts = { { 0, 0 }, { 0, -50 }, { 150, 50 } } } }, {}))
	ok((r1.crossesExisting or 0) + (r1.blockedNode or 0) >= 1)
	eq(reasons(P.plan(g, { { pts = { { 0, 0 }, { 0, -50 }, { 50, 30 } } } }, {})).crossesExisting, 1)
	local cross = P.plan(OG.new(), {
		{ pts = { { 0, 0 }, { 100, 0 } } },
		{ pts = { { 50, -50 }, { 50, 50 } } },
	}, {})
	eq(reasons(cross).crossesNew, 1)
	local steep = P.plan(OG.new(), { { pts = { { 0, 0 }, { 100, 0 } } } }, { terrain = F.plane(0.15, 0) })
	eq(reasons(steep).steep, 1)
	local okSlope = P.plan(OG.new(), { { pts = { { 0, 0 }, { 0, 100 } } } }, { terrain = F.plane(0.15, 0) })
	eq(#okSlope.edges, 1, "along the contour is fine")
	local wet = P.plan(OG.new(), { { pts = { { 200, 0 }, { 290, 0 } } } }, { terrain = F.coast(300) })
	eq(reasons(wet).water, 1)
	local sharp = P.plan(g, { { pts = { { 200, 0 }, { 110, 30 } } } }, { join = "any" })
	local rs = reasons(sharp)
	ok((rs.angle or 0) + (rs.nearExisting or 0) == 1, "18 deg off the existing street (runs alongside it too)")
	-- alongside an existing street, 10 m off its centre line: refused (pavements overlap)
	local along = reasons(P.plan(g, { { pts = { { 10, 12 }, { 90, 12 } } } }, { requireConnected = false }))
	eq(along.nearExisting, 1, "parallel 12 m off: nearExisting")
	local apart = P.plan(g, { { pts = { { 10, 40 }, { 70, 40 } } } }, { requireConnected = false })
	eq(#apart.edges, 1, "40 m off: fine")
	eq(reasons(P.plan(OG.new(), { { pts = { { 0, 0 }, { 6, 0 } } } }, {})).short, 1)
	local dup = P.plan(g, { { pts = { { 0, 0 }, { 100, 0 } } } }, { join = "any" })
	eq(reasons(dup).exists, 1)
end)

test("budget: at most maxEdges edges, later streets dropped", function()
	local streets = {}
	for k = 0, 9 do streets[#streets + 1] = { pts = { { k * 200, 0 }, { k * 200 + 100, 0 } } } end
	local inc = P.plan(OG.new(), streets, { maxEdges = 4, requireConnected = false })
	ok(#inc.edges <= 4)
	ok(reasons(inc).budget >= 1)
end)

test("edgeCount matches what plan builds", function()
	local pts = { { 0, 0 }, { 120, 0 }, { 121, 0.5 }, { 250, 40 } }
	local inc = P.plan(OG.new(), { { pts = pts } }, { maxSeg = 60 })
	eq(P.edgeCount(pts, 60), #inc.edges)
end)

test("no -0 anywhere, even for mirrored geometry", function()
	local mirrored = { { -0.0, -0.0 }, { -0.0, -100 }, { -0.0004, -200 } }
	local inc = P.plan(OG.new(), { { pts = mirrored, class = "small" } }, {})
	ok(P.noNegativeZero(inc))
	local fake = { nodes = { { x = -0.0, y = 0, z = 0 } }, edges = {} }
	ok(not P.noNegativeZero(fake), "the guard sees a -0")
end)

---------------------------------------------------------------------------
-- junction footprints (showcase v3: short `conn:` joint edges at sharp angles refused with Construction Not
-- Possible and no collision; ot_check.footprint)

test("footprint: a short edge turning sharply at a dead end is refused, a straight or long one is not", function()
	local C = ug_require(F.DIR .. "ot_check.lua")
	near(C.footprint(0, 8, math.pi / 2, 8), 8, 1e-9, "right angle: half the width")
	ok(C.footprint(0, 8, math.rad(46), 8) > 18, "46 deg: ~19 m")
	eq(C.footprint(0, 8, math.pi, 8), 0, "straight on")
	-- dead end 3 at (200, 0), its street arriving from the west: a 22 m street turning back at 150 deg
	local g = tee()
	local back = math.rad(150)
	local function street(len, ang)
		return { pts = { { 200, 0 }, { 200 + len * math.cos(ang), len * math.sin(ang) } }, class = "small", startNode = 3 }
	end
	local inc = P.plan(g, { street(22, back) }, { templatePaths = TPL, minAngle = 25 })
	eq(#inc.edges, 0, "short sharp joint refused")
	eq(reasons(inc).footprint, 1)
	inc = P.plan(g, { street(22, 0) }, { templatePaths = TPL })
	eq(#inc.edges, 1, "straight continuation fits")
	inc = P.plan(g, { street(60, back) }, { templatePaths = TPL, minAngle = 25 })
	eq(#inc.edges, 1, "a long one fits its footprints")
	-- off: the old behaviour
	inc = P.plan(g, { street(22, back) }, { templatePaths = TPL, minAngle = 25, footprint = false })
	eq(#inc.edges, 1)
end)

test("footprint: an accepted short edge is protected when a later street meets it at a sharp angle", function()
	local g = tee()
	-- 3 -> (224, 0) straight (24 m), then from (226, 0) a street back toward the town at 40 deg: the first edge
	-- would hold 0 + 8/tan(20 deg) = 22 m + 4 m margin + the joint's footprint: refused
	local s1 = { pts = { { 200, 0 }, { 224, 0 } }, class = "small", startNode = 3 }
	local a = math.rad(180 - 40)
	local s2 = { pts = { { 224, 0 }, { 224 + 80 * math.cos(a), 80 * math.sin(a) } }, class = "small" }
	local inc = P.plan(g, { s1, s2 }, { templatePaths = TPL, minAngle = 25 })
	eq(#inc.edges, 1)
	local r = reasons(inc)
	ok((r.footprint or 0) + (r.nearNew or 0) + (r.nearExisting or 0) == 1, "the sharp second street is dropped")
	-- the footprint alone (clearances off): still refused
	inc = P.plan(g, { s1, s2 }, { templatePaths = TPL, minAngle = 25, clearEdge = 0, clear = 0 })
	ok(#inc.edges <= 1)
end)
