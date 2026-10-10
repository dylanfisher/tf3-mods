-- Shared highway helpers (square_roundabouts_ramps.lua, INTERCHANGES.md Phase 7a): extracted from
-- square_roundabouts_interchange.lua with no behaviour change (the Roundabout Interchange's
-- goldens, test_entries_unchanged_interchange.lua, prove the whole build); these tests pin the
-- helpers themselves for the Highway Interchange (Phase 7b).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local S = loadfile(here .. "checks.lua", "t", _ENV)().strictShapes(geom.shapes) -- S.dot: plan-only, fails on two 3D vectors
local ramps = ug_require(DIR .. "square_roundabouts_ramps.lua")
local ix = ug_require(DIR .. "square_roundabouts_interchange.lua")

local function sameEdge(a, b, msg)
	for _, k in ipairs({ "p0", "t0", "p1", "t1" }) do
		for i = 1, 3 do eq(a[k][i], b[k][i], msg .. " " .. k .. "[" .. i .. "]") end
	end
	eq(a.tag0, b.tag0, msg .. " tag0"); eq(a.tag1, b.tag1, msg .. " tag1"); eq(a.part, b.part, msg .. " part")
end

test("ramps: ix re-exports the same tables and values", function()
	for _, k in ipairs({ "HIGHWAYS", "DEFAULT_HIGHWAY", "RAMP", "MEDIAN", "MERGE_OFFSET", "GORE_GAP", "GORE_RUN",
		"GORE_SLOPE", "HEIGHT", "BRIDGE_STEEL", "BRIDGE_CONCRETE", "CONCRETE_FROM", "CLEAR" }) do
		ok(ix[k] ~= nil and rawequal(ix[k], ramps[k]), k)
	end
	ok(rawequal(ix.bridgeType, ramps.bridgeType), "bridgeType")
	eq(ramps.bridgeType(1969), ramps.BRIDGE_STEEL)
	eq(ramps.bridgeType(1970), ramps.BRIDGE_CONCRETE)
	eq(ramps.bridgeType(nil), ramps.BRIDGE_CONCRETE)
end)

test("ramps: frame numbers per highway", function()
	local want = { { 4.5, 6.5, 11 }, { 9, 11, 20 }, { 11.5, 13.5, 25 } }
	for h, w in ipairs(want) do
		local f = ramps.frame(h, 8)
		eq(f.highway, ramps.HIGHWAYS[h]); eq(f.hwH, w[1]); eq(f.c, w[2]); eq(f.corr, w[3])
		eq(f.hwRamp, 4.5); eq(f.clear, 8); eq(f.yClear, w[3] + 8)
		local ixf = ix.frame(ix.readParams({ sqrb_ix_highway = h }))
		for _, k in ipairs({ "hwH", "c", "corr", "hwRamp", "clear", "yClear" }) do eq(ixf[k], f[k], k) end
	end
	eq(ramps.frame(2, 6).yClear, 26)
end)

test("ramps: gore nodes, tags and run (medium and large highway)", function()
	local f = ramps.frame(2, 8)
	-- eastbound off-ramp: leaves before the junction (west), G towards it
	local g = ramps.gore(f, "s", "in", 200, 30, "p_", 0)
	eq(g.tag, "p_s_w"); eq(g.before, -1)
	eq(g.m[1], -200); eq(g.m[2], -15); eq(g.m[3], 0)
	eq(g.g[1], -170); eq(g.g[2], -25.5)
	eq(g.head[1], 1)
	-- the four slips of a side pair: on-ramps join after the junction
	eq(ramps.gore(f, "s", "out", 200, 30, "p_", 0).tag, "p_s_e")
	eq(ramps.gore(f, "n", "in", 200, 30, "p_", 0).tag, "p_n_e")
	local nOut = ramps.gore(f, "n", "out", 200, 30, "p_", 8)
	eq(nOut.tag, "p_n_w"); eq(nOut.m[1], -200); eq(nOut.g[1], -170); eq(nOut.g[2], 25.5); eq(nOut.g[3], 8); eq(nOut.head[1], -1)
	-- wide highway: GORE_SLOPE x lateral (13 m) beats GORE_RUN
	local L = ramps.gore(ramps.frame(3, 8), "s", "in", 200, 30, "p_", 0)
	eq(L.g[1], -200 + 32.5)
	-- a longer dev run wins
	eq(ramps.gore(f, "s", "in", 200, 40, "p_", 0).g[1], -160)
end)

-- The pre-Phase-7a ix.rampEdges, verbatim (constants via ix): the extraction must give the same edges.
local function oldRampEdges(lay, n, zRing, zHw)
	local f = lay.f
	local io, cw = n.slip.io, n.slip.cw
	local sgn = cw == "s" and -1 or 1
	local head = cw == "s" and { 1, 0, 0 } or { -1, 0, 0 }
	local before = (io == "in") == (cw == "s") and -1 or 1
	local tag = "sqrb_ix_" .. cw .. (before < 0 and "_w" or "_e")
	local m = { before * lay.xm, sgn * (f.c + ix.MERGE_OFFSET), zHw }
	local lateral = f.hwH + f.hwRamp + ix.GORE_GAP - ix.MERGE_OFFSET
	local run = math.max((lay.spec.dev and lay.spec.dev.ixGoreRun) or ix.GORE_RUN, ix.GORE_SLOPE * lateral)
	local g = { m[1] - before * run, sgn * (f.c + f.hwH + f.hwRamp + ix.GORE_GAP), zHw }
	local p = { n.pos[1], n.pos[2], zRing }
	local d = ix.slipDir(n.t, lay.gamma, io)
	local gore, climb
	if io == "in" then
		gore, climb = S.curveEdge(m, head, g, head, tag, nil), S.curveEdge(g, head, p, d, nil, n.tag)
	else
		gore, climb = S.curveEdge(g, head, m, head, nil, tag), S.curveEdge(p, d, g, head, n.tag, nil)
	end
	gore.part, climb.part = "gore", "climb"
	if io == "in" then return { gore, climb }, tag end
	return { climb, gore }, tag
end

test("ramps: gore + slipEdges equal the pre-extraction ix.rampEdges on every layout / highway / level", function()
	local n = 0
	for layout = 1, 3 do
		for highway = 1, 3 do
			for level = 1, 2 do
				local p = { sqrb_ix_layout = layout, sqrb_ix_highway = highway, sqrb_ix_level = level }
				local spec = ix.readParams(p)
				local lay = ix.plan(spec)
				local zRing, zHw = level == 1 and 8 or 0, level == 1 and 0 or 8
				for _, r in ipairs(lay.rings) do
					for _, node in ipairs(r.nodes) do
						if node.slip then
							node.tag = node.tag or "ring_node"
							local a, ta = ix.rampEdges(lay, node, zRing, zHw)
							local b, tb = oldRampEdges(lay, node, zRing, zHw)
							eq(ta, tb); eq(#a, 2); eq(#b, 2)
							for i = 1, 2 do sameEdge(a[i], b[i], layout .. "/" .. highway .. "/" .. level .. " edge " .. i) end
							n = n + 1
						end
					end
				end
			end
		end
	end
	eq(n, 3 * 3 * 2 * 4)
end)

test("ramps: slipEdges orientation (driving order, level gore, climb carries the height)", function()
	local f = ramps.frame(2, 8)
	local off = ramps.slipEdges(ramps.gore(f, "s", "in", 150, 30, "p_", 0), { -20, -40, 8 }, { 0, -1, 0 }, "t")
	eq(off[1].part, "gore"); eq(off[2].part, "climb")
	eq(off[1].tag0, "p_s_w"); eq(off[2].tag1, "t")
	eq(off[1].p0[3], 0); eq(off[1].p1[3], 0); eq(off[2].p1[3], 8)
	ok(rawequal(off[1].p1, off[2].p0), "shared G")
	local on = ramps.slipEdges(ramps.gore(f, "s", "out", 150, 30, "p_", 0), { 20, -40, 8 }, { 0, 1, 0 }, "t")
	eq(on[1].part, "climb"); eq(on[2].part, "gore")
	eq(on[1].tag0, "t"); eq(on[2].tag1, "p_s_e")
	ok(rawequal(on[1].p1, on[2].p0), "shared G")
	-- the gore is parallel to the highway at both ends
	eq(on[2].t0[2], 0); eq(on[2].t1[2], 0); ok(on[2].t0[1] > 0)
end)

test("ramps: carriageways for arbitrary gore lists", function()
	local f = ramps.frame(1, 8)
	local nodes = {
		s = { xs = { -300, -200, -120, -20, 20, 90, 300 }, tags = { false, "a", "b", "c", "d", "e", false }, bridged = { [4] = true } },
		n = { xs = { -300, -150, 150, 300 }, tags = { false, "x", "y", false } },
	}
	local plain, bridged = ramps.carriageways(f, nodes, 3)
	eq(#plain, 5 + 3); eq(#bridged, 1)
	-- south first, eastwards, contiguous, tags on the nodes
	local south = {}
	for _, e in ipairs(plain) do if e.cw == "s" then south[#south + 1] = e end end
	eq(#south, 5)
	eq(bridged[1].p0[1], -20); eq(bridged[1].p1[1], 20); eq(bridged[1].tag0, "c"); eq(bridged[1].tag1, "d")
	eq(plain[1].p0[1], -300); eq(plain[1].tag0, nil); eq(plain[1].tag1, "a")
	for _, e in ipairs(plain) do
		eq(e.p0[3], 3); eq(e.p1[3], 3)
		if e.cw == "s" then eq(e.p0[2], -f.c); ok(e.p1[1] > e.p0[1]) else eq(e.p0[2], f.c); ok(e.p1[1] < e.p0[1]) end
	end
	-- north runs west: first edge from +300 to the "y" node
	local north = plain[6]
	eq(north.cw, "n"); eq(north.p0[1], 300); eq(north.tag1, "y"); eq(plain[8].p1[1], -300); eq(plain[8].tag0, "x")
	-- bridged index counts from the west on both carriageways
	local _, nb = ramps.carriageways(f, { s = { xs = { 0, 1, 2 }, tags = {} }, n = { xs = { 0, 10, 20 }, tags = {}, bridged = { [1] = true } } }, 0)
	eq(#nb, 1); eq(nb[1].p0[1], 10); eq(nb[1].p1[1], 0)
end)

test("ramps: highway bridge half", function()
	local f = ramps.frame(2, 8) -- corr 20, clear 8
	-- a cross road along y at x = 0 (half width 5): 0 + 5 + 8
	local cross = { e = S.straightEdge({ 0, -60, 0 }, { 0, 60, 0 }), hw = 5 }
	eq(ramps.highwayBridgeHalf(f, { cross }), 13)
	-- one at x = 20.4: rounded up
	local off = { e = S.straightEdge({ 20.4, -60, 0 }, { 20.4, 60, 0 }), hw = 5 }
	eq(ramps.highwayBridgeHalf(f, { cross, off }), 34)
	-- a road that never comes within corr + hw + clear of the highway axis
	local far = { e = S.straightEdge({ -50, 40, 0 }, { 50, 40, 0 }), hw = 5 }
	eq(ramps.highwayBridgeHalf(f, { far }), 0)
end)

test("ramps: list", function()
	local l = ramps.list("ramps", ramps.RAMP, 4.5, {}, nil)
	eq(l.template, ramps.RAMP.template); eq(l.edgeType, nil); eq(l.edgeTypeName, nil)
	local b = ramps.list("highway", ramps.HIGHWAYS[1], 4.5, {}, ramps.BRIDGE_STEEL)
	eq(b.edgeType, "BRIDGE"); eq(b.edgeTypeName, ramps.BRIDGE_STEEL)
end)

-- Phase 7b helpers (Highway Interchange) -------------------------------------------------------

test("ramps.goreEdge: the same edge as slipEdges' gore edge, both directions", function()
	for h = 1, 3 do
		local f = ramps.frame(h, 8)
		for _, io in ipairs({ "in", "out" }) do
			for _, cw in ipairs({ "s", "n" }) do
				local gore = ramps.gore(f, cw, io, 140, 30, "t_", 0)
				local slip = ramps.slipEdges(gore, { 0, 50, 8 }, { 1, 0, 0 }, "end")
				sameEdge(ramps.goreEdge(gore), io == "in" and slip[1] or slip[2], io .. cw)
			end
		end
	end
end)

test("ramps.arcEdges: fewest <= 90 deg edges on the circle, exact ends, both senses", function()
	for _, c in ipairs({ { sweep = math.pi, n = 2 }, { sweep = -math.pi, n = 2 }, { sweep = math.pi / 2, n = 1 }, { sweep = -1.5 * math.pi, n = 3 }, { sweep = 0.3, n = 1 } }) do
		local centre, r, a0 = { 10, -20, 0 }, 35, 0.4
		local from, to = { 1, 2, 0 }, { 3, 4, 0 }
		local edges = ramps.arcEdges(centre, r, a0, c.sweep)
		eq(#edges, c.n, "edges for " .. c.sweep)
		local total = 0
		for i, e in ipairs(edges) do
			for k = 0, 16 do
				local p = S.hermite(e, k / 16)
				near(S.dist(p, centre), r, 0.02 * r, "on the circle")
			end
			local a = math.atan(S.cross(e.t0, e.t1), S.pdot(e.t0, e.t1))
			total = total + a
			if i > 1 then eq(e.p0, edges[i - 1].p1) end
			near(S.len(e.t0), geom.hermiteScale(math.abs(c.sweep) / c.n) * r, 1e-9)
		end
		near(total, c.sweep, 1e-9, "turns by the sweep")
		local pinned = ramps.arcEdges(centre, r, a0, c.sweep, from, to)
		eq(pinned[1].p0, from); eq(pinned[#pinned].p1, to)
	end
end)

test("ramps.profile / ramps.gradient: smoothstep by plan length, flat ends, continuous slopes", function()
	local edges = {
		S.straightEdge({ 0, 0, 0 }, { 40, 0, 0 }),
	}
	for _, e in ipairs(ramps.arcEdges({ 40, 30, 0 }, 30, -math.pi / 2, math.pi, { 40, 0, 0 }, { 40, 60, 0 })) do edges[#edges + 1] = e end
	local total = ramps.profile(edges, 0, 8)
	near(total, 40 + 30 * math.pi, 0.1, "plan length")
	eq(edges[1].p0[3], 0); eq(edges[#edges].p1[3], 8)
	near(edges[1].t0[3], 0, 1e-12); near(edges[#edges].t1[3], 0, 1e-12)
	for i = 2, #edges do
		eq(edges[i].p0[3], edges[i - 1].p1[3])
		near(edges[i].t0[3] / S.len({ edges[i].t0[1], edges[i].t0[2], 0 }), edges[i - 1].t1[3] / S.len({ edges[i - 1].t1[1], edges[i - 1].t1[2], 0 }), 1e-12, "same slope")
	end
	local plan, avg, peak = ramps.gradient(edges)
	near(plan, total, 0.1)
	near(avg, 8 / plan, 1e-9)
	ok(peak <= 1.5 * avg * 1.05 and peak >= 1.5 * avg * 0.95, string.format("peak %.4f ~ 1.5 x avg %.4f", peak, avg))
	-- downhill
	ramps.profile(edges, 8, 0)
	eq(edges[1].p0[3], 8); eq(edges[#edges].p1[3], 0)
end)

test("ramps.loop: stub west from the terminal, clockwise half circle up to G, then the gore", function()
	for h = 1, 3 do
		local f = ramps.frame(h, 8)
		for _, r in ipairs({ 25, 60 }) do
			local gore = ramps.gore(f, "s", "out", -40, 30, "t_", 0)
			local edges = ramps.loop(gore, r, "term", 8)
			local parts = {}
			for i, e in ipairs(edges) do parts[i] = e.part end
			eq(parts, { "stub", "loop", "loop", "gore" })
			local stub, last = edges[1], edges[#edges]
			eq(stub.tag0, "term"); eq(stub.p0[1], 0); near(stub.p0[2], gore.g[2] - 2 * r, 1e-12); eq(stub.p0[3], 8)
			ok(stub.t0[1] < 0, "stub heads west")
			eq(edges[3].p1[1], gore.g[1]); eq(edges[3].p1[2], gore.g[2]); eq(edges[3].p1[3], 0)
			sameEdge(last, ramps.goreEdge(gore), "gore")
			eq(last.tag1, gore.tag)
			for i = 2, 3 do
				local a = math.atan(S.cross(edges[i].t0, edges[i].t1), S.pdot(edges[i].t0, edges[i].t1))
				near(a, -math.pi / 2, 1e-9, "right turns")
			end
		end
	end
end)

test("tests' strict S: S.dot fails on two 3D vectors (the 7b tangent bug); pdot / dot3 say which", function()
	local u, v = S.norm({ 1, 0, 0.1 }), S.norm({ 1, 0, 0.1 })
	raises(function() return S.dot(u, v) end, "S.dot3")
	ok(S.pdot(u, v) < 1 - 1e-6, "plan dot of parallel climbing tangents is below 1")
	near(S.dot3(u, v), 1, 1e-12)
	eq(S.dot({ 1, 2, 8 }, { 3, 4, 0 }), 11, "one flat vector: plan dot allowed")
end)
