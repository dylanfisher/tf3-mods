-- ot_check (curve radius, angles, kinks of planned edges) and the smooth-line geometry behind it: every
-- profile's simulated increments must pass the town street templates' limits (findings "Town street
-- templates": minCurveRadius 44 m, minCurveRadiusBuild 60 m; planner target 70 m).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local P = ug_require(F.DIR .. "ot_plan.lua")
local C = ug_require(F.DIR .. "ot_check.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local core = ug_require(F.DIR .. "ot_core.lua")

local function edge(p0, t0, p1, t1, extra)
	local e = { entity = -1, node0 = -2, node1 = -3, p0 = p0, p1 = p1, t0 = t0, t1 = t1 }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

test("minRadius: straight edge is unbounded, a quarter circle of 100 m reads ~100 m", function()
	local s = C.edge(edge({ 0, 0, 0 }, { 50, 0, 0 }, { 50, 0, 0 }, { 50, 0, 0 }))
	ok(s.minRadius > 1e6)
	near(s.chord, 50, 1e-9)
	-- quarter arc, radius 100: tangent length 4/3 tan(pi/8) x 3 x R would be the Bezier match; with the
	-- arc length (TF convention) the curve stays within a few percent of the circle
	local L = math.pi / 2 * 100
	local q = C.edge(edge({ 100, 0, 0 }, { 0, L, 0 }, { 0, 100, 0 }, { -L, 0, 0 }))
	ok(q.minRadius > 85 and q.minRadius < 110, "quarter arc radius " .. q.minRadius)
	near(q.dev0, 45, 1e-6)
end)

test("root cause: the old tangents (chord at a piece end, Catmull-Rom inside) made 19 m edges with R ~13 m", function()
	-- the shape the planner emitted before the fix (EU organic, ring piece rg2:1#1: chord 19 m, the end tangent
	-- 21.6 deg off the chord, the start tangent on the chord, both chord length)
	local c, dev = 19, math.rad(21.6)
	local e = edge({ 0, 0, 0 }, { c, 0, 0 }, { c, 0, 0 }, { c * math.cos(dev), c * math.sin(dev), 0 })
	local s = C.edge(e)
	ok(s.minRadius < 20, "radius " .. s.minRadius)
	local rep = C.increment({ edges = { e }, nodes = {} })
	eq(rep.counts.radius, 1)
	ok(rep.bad[1].hard, "below the template's 44 m too")
end)

test("angles and kinks at nodes use the actual tangents; corners between lines are not kinks", function()
	local inc = { nodes = {}, edges = {
		edge({ 0, 0, 0 }, { 50, 0, 0 }, { 50, 0, 0 }, { 50, 0, 0 }, { entity = -1, node0 = -10, node1 = -11, key = "rg1:1#1" }),
		edge({ 50, 0, 0 }, { 50, 5, 0 }, { 100, 5, 0 }, { 50, 5, 0 }, { entity = -2, node0 = -11, node1 = -12, key = "rg1:1#2" }),
		edge({ 0, 0, 0 }, { 30, 10, 0 }, { 30, 10, 0 }, { 30, 10, 0 }, { entity = -3, node0 = -10, node1 = -13, key = "ln9" }),
	} }
	local rep = C.increment(inc)
	eq(rep.counts.kink, 1, "5.7 deg break where ring line rg1:1 continues")
	eq(rep.counts.angle, 1, "18 deg between the ring and the lane at node -10")
	eq(C.lineOf("rg1:1#2"), "rg1:1")
	eq(C.lineOf("h3:-2"), nil, "lattice corners are corners")
	eq(C.lineOf("v-1:4"), nil)
	-- two different lines meeting at 40 deg: a corner, no violation
	local corner = C.increment({ nodes = {}, edges = {
		edge({ 0, 0, 0 }, { 50, 0, 0 }, { 50, 0, 0 }, { 50, 0, 0 }, { entity = -1, node0 = -10, node1 = -11, key = "a" }),
		edge({ 50, 0, 0 }, { 38, 32, 0 }, { 88, 32, 0 }, { 38, 32, 0 }, { entity = -2, node0 = -11, node1 = -12, key = "b" }),
	} })
	eq(corner.counts.kink, nil)
	ok(corner.maxCorner > 39 and corner.maxCorner < 41)
end)

test("smoothLine: corners become arcs of at least R with exact tangents; ends kept", function()
	local pts = { { 0, 0 }, { 100, 0 }, { 160, 60 }, { 160, 200 } }
	local out, minR = G.smoothLine(pts, 80)
	ok(minR >= 80 - 1e-6, "radius " .. minR)
	ok(G.minDiscreteRadius(out) >= 80 * 0.98, "discrete " .. G.minDiscreteRadius(out))
	eq({ out[1][1], out[1][2] }, { 0, 0 })
	eq({ out[#out][1], out[#out][2] }, { 160, 200 })
	for _, p in ipairs(out) do near(G.len(p[3], p[4]), 1, 1e-9) end
	-- a bend too sharp for its legs is relaxed until it fits
	local tight, r2 = G.smoothLine({ { 0, 0 }, { 20, 15 }, { 40, 0 } }, 80)
	ok(r2 >= 80 - 1e-6, "relaxed radius " .. r2)
	ok(#tight >= 3)
	-- polySplit keeps the carried directions (cut points blended)
	local parts = G.polySplit(out, { { 0.5 } })
	eq(#parts, 2)
	local cut = parts[1][#parts[1]]
	ok(cut[3] ~= nil and math.abs(G.len(cut[3], cut[4]) - 1) < 1e-9)
	eq(parts[2][1][3], cut[3])
end)

test("streetPoints: a curved street is cut so every edge's Hermite reaches MIN_RADIUS, one tangent per node", function()
	local arc = {}
	for k = 0, 40 do
		local a = k / 40 * math.pi / 2
		arc[#arc + 1] = { 120 * math.cos(a), 120 * math.sin(a) }
	end
	local inc = P.plan(OG.new(), { { pts = arc, curved = true } }, { maxSeg = 100 })
	ok(#inc.edges >= 2)
	local rep = C.increment(inc)
	ok(C.passes(rep), C.summary(rep))
	ok(rep.minRadius >= P.MIN_RADIUS)
	for i = 2, #inc.edges do
		local a, b = inc.edges[i - 1], inc.edges[i]
		near(G.angleDiff(G.atan2(a.t1[2], a.t1[1]), G.atan2(b.t0[2], b.t0[1])), 0, 1e-6)
	end
	-- an unsmoothed sharp polyline (a bent lane) is smoothed first
	local bent = P.plan(OG.new(), { { pts = { { 0, 0 }, { 40, 12 }, { 80, 0 } }, curved = true } }, { maxSeg = 100 })
	local r2 = C.increment(bent)
	ok(#bent.edges >= 1 and C.passes(r2), C.summary(r2))
end)

test("plan drops a curved piece whose edge would stay too tight (reason curve)", function()
	-- smooth=true promises a smooth curve; this one has a 10 m kink, so no cut can fix it
	local inc = P.plan(OG.new(), { { pts = { { 0, 0, 1, 0 }, { 30, 0, 1, 0 }, { 30.1, 0.1, 0, 1 }, { 30.1, 30, 0, 1 } },
		curved = true, smooth = true } }, { maxSeg = 100 })
	local curve = 0
	for _, d in ipairs(inc.dropped) do if d.reason == "curve" then curve = curve + 1 end end
	ok(curve >= 1, "dropped as curve")
	ok(C.passes(C.increment(inc)))
end)

test("single: one edge of an increment with its new nodes renumbered and its join", function()
	local inc = { nodes = { { entity = -3, x = 0, y = 0, z = 1 }, { entity = -4, x = 50, y = 0, z = 1 } },
		edges = {
			{ entity = -1, node0 = -3, node1 = -4, p0 = { 0, 0, 1 }, p1 = { 50, 0, 1 }, t0 = { 50, 0, 0 }, t1 = { 50, 0, 0 } },
			{ entity = -2, node0 = -4, node1 = 77, p0 = { 50, 0, 1 }, p1 = { 90, 0, 1 }, t0 = { 40, 0, 0 }, t1 = { 40, 0, 0 } },
		}, joins = { { node = 77, edge = -2 } } }
	local s = PR.single(inc, 2)
	eq(#s.edges, 1)
	eq(s.edges[1].entity, -1)
	eq(s.edges[1].node0, -2)
	eq(s.edges[1].node1, 77)
	eq(#s.nodes, 1)
	eq(s.nodes[1].entity, -2)
	eq(s.nodes[1].x, 50)
	eq(s.joins, { { node = 77, edge = -1 } })
	eq(inc.edges[2].entity, -2, "the increment is not changed")
	eq(PR.single(inc, 3), nil)
end)

-- every profile x terrain: all emitted edges pass (radius >= 70 m, angles >= 25 deg, >= 10 m, slope <= 0.2,
-- tangents within 60 deg of the chord, kinks <= 8 deg where a line continues)
local TERRAINS = { flat = F.flat, hill = F.hill, river = F.river(), coast = F.coast() }
local LIMITS = { maxKink = 8 }
for _, id in ipairs({ "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "NA_SUBURB", "JP_DENSE", "NORDIC", "NA_GRID" }) do
	test("profile " .. id .. ": every simulated increment passes the checker", function()
		for tname, sampler in pairs(TERRAINS) do
			for _, town in ipairs({ 1, 7 }) do
				local style, stats = F.style({ forceStyle = id, keepOuter = true, townId = town, year = 1960,
					nameList = "::/names/germany/germany.names" }, sampler)
				local g = OG.new()
				local n = 0
				for k = 1, 8 do
					local inc = core.planIncrement(g, style, { terrain = sampler, stats = stats, join = "any" })
					if #inc.edges == 0 then break end
					local rep = C.increment(inc, g, LIMITS)
					ok(C.passes(rep), string.format("%s %s town %d inc %d: %s", id, tname, town, k, C.summary(rep)))
					local sc = C.selfClearance(inc)
					ok(#sc == 0, string.format("%s %s town %d inc %d: %d self-conflicts, first %s d=%.1f", id, tname, town, k,
						#sc, sc[1] and sc[1].kind or "-", sc[1] and sc[1].d or 0))
					OG.apply(g, inc, k)
					n = n + #inc.edges
				end
				if tname == "flat" then ok(n >= 60, id .. " grows on flat land: " .. n) end
			end
		end
	end)
end

-- planner self-collisions (showcase v2: "REFUSED ... Collision partners=ent-20", a new edge against the plan's own
-- new node): new edges of one increment never cross or overlap except at shared nodes
test("self-clearance: crossing, parallel and end-to-body conflicts; shared nodes allowed", function()
	local function e(n0, n1, x0, y0, x1, y1, class)
		return { node0 = n0, node1 = n1, p0 = { x0, y0, 0 }, p1 = { x1, y1, 0 }, t0 = { x1 - x0, y1 - y0, 0 },
			t1 = { x1 - x0, y1 - y0, 0 }, class = class or "small" }
	end
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0), e(-3, -4, 50, -50, 50, 50) } }), 1, "crossing")
	eq(C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0), e(-3, -4, 50, -50, 50, 50) } })[1].kind, "crossesNew")
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0), e(-3, -4, 0, 10, 100, 10) } }), 1, "10 m apart, parallel")
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0), e(-3, -4, 0, 30, 100, 30) } }), 0, "30 m apart")
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0, "main"), e(-3, -4, 0, 18, 100, 18) } }), 1,
		"a main (medium) street needs 20 m")
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0), e(-3, -4, 50, 6, 50, 80) } }), 1, "a dead end 6 m off a street")
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0), e(-2, -3, 100, 0, 100, 80) } }), 0, "corner at a shared node")
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 100, 0), e(-1, -3, 0, 0, 100, 8) } }), 1,
		"from one node but running alongside")
	-- T-junction taps 14 m apart along a street (organic lanes on both sides): allowed
	eq(#C.selfClearance({ edges = { e(-1, -2, 0, 0, 50, 0), e(-2, -3, 50, 0, 64, 0), e(-3, -4, 64, 0, 120, 0),
		e(-2, -5, 50, 0, 50, 60), e(-3, -6, 64, 0, 64, -60) } }), 0, "offset T-junctions")
end)

test("plan refuses a new edge running alongside one it already accepted (nearNew)", function()
	local inc = P.plan(OG.new(), {
		{ pts = { { 0, 0 }, { 100, 0 } }, class = "small" },
		{ pts = { { 0, 9 }, { 100, 9 } }, class = "small" },
	}, { maxSeg = 100, requireConnected = false })
	local near = 0
	for _, d in ipairs(inc.dropped) do if d.reason == "nearNew" then near = near + 1 end end
	eq(#inc.edges, 1)
	eq(near, 1)
	eq(#C.selfClearance(inc), 0)
end)

for _, id in ipairs({ "EU_ORGANIC", "EU_EXTENSION", "NA_GRID", "NA_SUBURB" }) do
	test("profile " .. id .. ": dead-end joins only (as in game), no self-conflicts", function()
		for _, town in ipairs({ 3, 11 }) do
			local style, stats = F.style({ forceStyle = id, keepOuter = true, townId = town, year = 1960 }, F.flat)
			local g = OG.new()
			for k = 1, 10 do
				local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = k == 1 and "any" or "deadEnd" })
				if #inc.edges == 0 then break end
				local sc = C.selfClearance(inc)
				ok(#sc == 0, string.format("%s town %d inc %d: %d self-conflicts (%s)", id, town, k, #sc, sc[1] and sc[1].kind or "-"))
				OG.apply(g, inc, k)
			end
		end
	end)
end
