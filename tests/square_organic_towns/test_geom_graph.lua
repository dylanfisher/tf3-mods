-- ot_geom helpers and the ot_graph snapshot model.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"

local function isNegZero(v) return v == 0 and 1 / v < 0 end

---------------------------------------------------------------------------
-- ot_geom

test("z0 / round never return -0", function()
	ok(isNegZero(-0.0), "the test value is -0")
	ok(not isNegZero(G.z0(-0.0)))
	ok(not isNegZero(G.round(-0.0)))
	ok(not isNegZero(G.round(-0.0004)))
	ok(not isNegZero(G.round(-1e-9, 0.5)))
	eq(G.round(1.23456), 1.235)
	eq(G.round(-1.23456), -1.235)
	eq(G.z0(-3), -3)
end)

test("angles: wrap, angleDiff, lineAngleDiff", function()
	near(G.wrap(3 * math.pi), -math.pi, 1e-9)
	near(G.wrap(-math.pi / 2), -math.pi / 2, 1e-12)
	near(G.angleDiff(math.rad(170), math.rad(-170)), math.rad(20), 1e-9)
	near(G.lineAngleDiff(0, math.rad(170)), math.rad(10), 1e-9)
	near(G.heading(0, 0, 0, 5), math.pi / 2, 1e-12)
	local x, y = G.rot(1, 0, math.pi / 2)
	near(x, 0, 1e-12)
	near(y, 1, 1e-12)
end)

test("pointSegDist and segIntersect (touching ends don't count)", function()
	local d, t = G.pointSegDist(5, 3, 0, 0, 10, 0)
	near(d, 3)
	near(t, 0.5)
	near((G.pointSegDist(-4, 3, 0, 0, 10, 0)), 5)
	local a, b = G.segIntersect(0, 0, 10, 0, 5, -5, 5, 5)
	near(a, 0.5)
	near(b, 0.5)
	eq(G.segIntersect(0, 0, 10, 0, 10, 0, 10, 5), nil, "shared end point")
	eq(G.segIntersect(0, 0, 10, 0, 0, 1, 10, 1), nil, "parallel")
	eq(G.segIntersect(0, 0, 10, 0, 5, 1, 5, 5), nil, "no contact")
end)

test("polylines: length, point at fraction, split at exact cuts", function()
	local pts = { { 0, 0 }, { 10, 0 }, { 10, 10 } }
	near(G.polyLen(pts), 20)
	local x, y = G.polyAt(pts, 0.75)
	near(x, 10)
	near(y, 5)
	local parts = G.polySplit(pts, { { 0.25 }, { 0.5, 10, 0 }, { 0.75 } })
	eq(#parts, 4)
	eq(parts[1], { { 0, 0 }, { 5, 0 } })
	eq(parts[2][#parts[2]], { 10, 0 })
	eq(parts[3][1], { 10, 0 })
	eq(parts[4][#parts[4]], { 10, 10 })
end)

test("resample keeps vertices and splits runs evenly; simplify drops straight / close points", function()
	local r = G.resample({ { 0, 0 }, { 250, 0 }, { 250, 30 } }, 100)
	eq(#r, 5)   -- 250 m -> 3 pieces, 30 m -> 1
	near(r[2][1], 250 / 3, 1e-9)
	eq(r[4], { 250, 0 })
	local s = G.simplify({ { 0, 0 }, { 10, 0.2 }, { 20, -0.3 }, { 30, 0 }, { 30, 30 } }, 1.5, 5)
	eq(s, { { 0, 0 }, { 30, 0 }, { 30, 30 } })
	local close = G.simplify({ { 0, 0 }, { 3, 4 }, { 20, 0 } }, 0.1, 10)
	eq(close, { { 0, 0 }, { 20, 0 } }, "vertex 5 m from the start dropped")
end)

test("smoothNoise: continuous, in [-1, 1], hits the lattice values", function()
	local function h(i) return ((i * 7919) % 101) / 101 end
	near(G.smoothNoise(h, 3), h(3) * 2 - 1, 1e-12)
	for k = 0, 100 do
		local v = G.smoothNoise(h, k / 10)
		ok(v >= -1 and v <= 1)
	end
	near(G.smoothNoise(h, 2.999999), G.smoothNoise(h, 3), 1e-4)
end)

---------------------------------------------------------------------------
-- ot_graph

local function grid(n, spacing, angle)
	-- n x n nodes, rotated by angle
	local snap = { nodes = {}, edges = {} }
	local id = 100
	local ids = {}
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local x, y = G.rot(i * spacing, j * spacing, angle or 0)
			id = id + 1
			ids[i .. ":" .. j] = id
			snap.nodes[#snap.nodes + 1] = { id = id, x = x, y = y, z = 0 }
		end
	end
	local eid = 1000
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			if i < n - 1 then eid = eid + 1; snap.edges[#snap.edges + 1] = { id = eid, node0 = ids[i .. ":" .. j], node1 = ids[(i + 1) .. ":" .. j], class = "small" } end
			if j < n - 1 then eid = eid + 1; snap.edges[#snap.edges + 1] = { id = eid, node0 = ids[i .. ":" .. j], node1 = ids[i .. ":" .. (j + 1)], class = "small" } end
		end
	end
	return snap, ids
end

test("fromSnapshot: ids sorted, order independent, nextId past them", function()
	local snap = grid(3, 50)
	local rev = { nodes = {}, edges = {} }
	for i = #snap.nodes, 1, -1 do rev.nodes[#rev.nodes + 1] = snap.nodes[i] end
	for i = #snap.edges, 1, -1 do rev.edges[#rev.edges + 1] = snap.edges[i] end
	local a, b = OG.fromSnapshot(snap), OG.fromSnapshot(rev)
	eq(#a.nodes, 9)
	eq(#a.edges, 12)
	for i = 1, 9 do eq(a.nodes[i].id, b.nodes[i].id) end
	for i = 1, 12 do eq(a.edges[i].id, b.edges[i].id) end
	ok(a.nextId > 1012)
	ok(a.nodes[1].existing)
end)

test("degree, dead ends, other, connected", function()
	local g = OG.new()
	local a = OG.addNode(g, nil, 0, 0)
	local b = OG.addNode(g, nil, 100, 0)
	local c = OG.addNode(g, nil, 100, 100)
	local e = OG.addEdge(g, nil, a.id, b.id, "main")
	OG.addEdge(g, nil, b.id, c.id)
	eq(OG.degree(g, b.id), 2)
	eq(OG.deadEnds(g), { a.id, c.id })
	eq(OG.other(e, a.id), b.id)
	ok(OG.connected(g, a.id, b.id))
	ok(not OG.connected(g, a.id, c.id))
	near(OG.headingFrom(g, e, b.id), math.pi, 1e-12)
end)

test("dominantAxis: grid angle mod 90 deg, strength 1; mixed headings weaker", function()
	local snap = grid(4, 80, math.rad(30))
	local ang, s = OG.dominantAxis(OG.fromSnapshot(snap))
	near(math.deg(ang), 30, 1e-6)
	near(s, 1, 1e-9)
	local snap2 = grid(4, 80, math.rad(-20))
	near(math.deg((OG.dominantAxis(OG.fromSnapshot(snap2)))), -20, 1e-6)
	-- a star of 7 spokes: no 90 deg axis
	local g = OG.new()
	local c = OG.addNode(g, nil, 0, 0)
	for k = 0, 6 do
		local n = OG.addNode(g, nil, math.cos(k * 2 * math.pi / 7) * 100, math.sin(k * 2 * math.pi / 7) * 100)
		OG.addEdge(g, nil, c.id, n.id)
	end
	local _, s3 = OG.dominantAxis(g)
	ok(s3 < 0.2, "star strength " .. s3)
	eq({ OG.dominantAxis(OG.new()) }, { 0.0, 0 })
end)

test("centre, radius, bbox", function()
	local g = OG.fromSnapshot(grid(3, 100))
	local c = OG.centre(g)
	near(c[1], 100, 1e-9)
	near(c[2], 100, 1e-9)
	near(OG.radius(g, 100, 100, 1.0), math.sqrt(2) * 100, 1e-9)
	eq(OG.bbox(g), { 0, 0, 200, 200 })
	eq(OG.centre(OG.new()), nil)
	eq(OG.bbox(OG.new()), nil)
end)

test("nearestNode (hash and linear), distToEdges with skip, crossing", function()
	local snap, ids = grid(3, 100)
	local g = OG.fromSnapshot(snap)
	local n, d = OG.nearestNode(g, 104, 3, 10)
	eq(n.id, ids["1:0"])
	near(d, 5)
	eq(OG.nearestNode(g, 150, 150, 10), nil)
	eq(OG.nearestNode(g, 1e5, 1e5, math.huge).id, ids["2:2"])
	near(OG.distToEdges(g, 50, 4, 10), 4)
	eq(OG.distToEdges(g, 50, 50, 10), nil)
	-- skipping both end nodes of the nearest edge
	eq(OG.distToEdges(g, 50, 4, 10, { [ids["0:0"]] = true, [ids["1:0"]] = true }), nil)
	ok(OG.crossing(g, 50, -10, 50, 10) ~= nil)
	eq(OG.crossing(g, 50, 10, 50, 90), nil)
	eq(OG.crossing(g, 0, 0, -50, -50), nil, "touching a node end is no crossing")
	local skip = {}
	local e = OG.crossing(g, 50, -10, 50, 10)
	skip[e.n0] = true
	eq(OG.crossing(g, 50, -10, 50, 10, skip), nil)
end)

test("frontier: dead ends first, then outermost", function()
	local g = OG.new()
	local a = OG.addNode(g, nil, 0, 0)
	local b = OG.addNode(g, nil, 100, 0)
	local c = OG.addNode(g, nil, 300, 0)
	local d = OG.addNode(g, nil, 100, 50)
	OG.addEdge(g, nil, a.id, b.id)
	OG.addEdge(g, nil, b.id, c.id)
	OG.addEdge(g, nil, b.id, d.id)
	eq(OG.frontier(g, 0, 0), { c.id, d.id, a.id })
	eq(OG.frontier(g, 0, 0, 1), { c.id })
end)

test("apply: an increment becomes graph nodes/edges with fresh ids", function()
	local g = OG.new()
	local root = OG.addNode(g, 5, 0, 0)
	local inc = {
		nodes = { { entity = -3, x = 50, y = 0, z = 1 }, { entity = -4, x = 100, y = 0, z = 2 } },
		edges = {
			{ entity = -1, node0 = 5, node1 = -3, class = "main", t0 = { 50, 0, 1 }, t1 = { 50, 0, 1 } },
			{ entity = -2, node0 = -3, node1 = -4, class = "small" },
		},
	}
	local map = OG.apply(g, inc, 1)
	eq(#g.nodes, 3)
	eq(#g.edges, 2)
	ok(map[-3] > 5 and map[-4] > 5)
	eq(OG.degree(g, root.id), 1)
	eq(g.edges[1].increment, 1)
	eq(g.edges[1].existing, false)
end)
