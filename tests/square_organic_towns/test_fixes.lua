-- Phase 2 preview fixes (HANDOFF "Phase 2 preview issues") and the Phase 3 hooks in the pure core:
-- strict grids without wobble, minimum block size from lot depth, fewer dead-end stubs, joinable nodes,
-- piece keys on edges, saved plan frames.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local GRID = ug_require(F.DIR .. "ot_grow_grid.lua")
local ORG = ug_require(F.DIR .. "ot_grow_organic.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local P = ug_require(F.DIR .. "ot_plan.lua")
local core = ug_require(F.DIR .. "ot_core.lua")

--- Local lattice coordinates (u along the axis, v across) of a world point.
local function toLocal(style, origin, x, y)
	local ca, sa = math.cos(style.axis), math.sin(style.axis)
	local dx, dy = x - origin[1], y - origin[2]
	return dx * ca + dy * sa, -dx * sa + dy * ca
end

test("strict NA grid: every junction sits exactly on its lattice lines (no jitter, no bends)", function()
	local p = F.style({ year = 1965 })
	ok(p.gridness >= ST.STRICT_GRID)
	local mp = GRID.masterPlan(p, { extent = 1200 })
	for k, j in pairs(mp.junctions) do
		local i, jj = k:match("^g(%-?%d+):(%-?%d+)$")
		if i then
			local u, v = toLocal(p, mp.origin, j[1], j[2])
			near(u, mp.u[tonumber(i)], 1e-6, "u of " .. k)
			near(v, mp.v[tonumber(jj)], 1e-6, "v of " .. k)
		end
	end
	for _, pc in ipairs(mp.pieces) do ok(not pc.curved, "straight piece " .. pc.key) end
end)

test("grid lines never closer than MIN_BLOCK (lot depth), even with a big spread", function()
	local pos = GRID.lines(12345, "u", 50, 0.4, 30)
	for i = -30, 29 do
		ok(pos[i + 1] - pos[i] >= ST.MIN_BLOCK - 1e-9, "gap " .. i .. " = " .. (pos[i + 1] - pos[i]))
	end
	-- (44 m since 2026-10-18: a 16 m small street + 28 m of land, one row of 3-cell lots; 40 m left 1-cell slivers)
	eq(ST.MIN_BLOCK, 44)
	ok(ST.MIN_BLOCK - 16 >= 3 * ST.LOT_CELL, "a row of 3-cell lots between two small streets")
end)

test("suburb cul-de-sacs only on even cross lines (never two facing each other)", function()
	local p = F.style({ year = 1965 })
	local mp = GRID.masterPlan(p, { extent = 1400 })
	local n = 0
	for _, pc in ipairs(mp.pieces) do
		if pc.culDeSac then
			n = n + 1
			local i = tonumber(pc.key:match("^v(%-?%d+):"))
			eq(i % 2, mp.culParity, pc.key)
			ok(i % 2 == 1 or p.collectorEvery == nil, "never on a collector line")
		end
	end
	ok(n > 0)
end)

test("organic infill respects MIN_BLOCK along the inner arc and across the ring gap", function()
	for _, c in ipairs({ { 120, 200, 60 }, { 400, 520, 60 }, { 90, 400, 110 } }) do
		local m = ORG.stripCount(c[1], c[2], c[3])
		if m > 0 then ok(c[1] / (m + 1) >= ST.MIN_BLOCK, "strips " .. m .. " on " .. c[1]) end
	end
	for _, gap in ipairs({ 60, 140, 300 }) do
		local n = ORG.laneCount(gap, 45, false)
		if n > 0 then ok(gap / (n + 1) >= ST.MIN_BLOCK, "lanes " .. n .. " on " .. gap) end
		local nc = ORG.laneCount(gap, 45, true)
		if nc > 0 then ok(gap * 0.65 / nc >= ST.MIN_BLOCK, "core lanes " .. nc .. " on " .. gap) end
	end
	eq(ORG.stripCount(60, 80, 60), 0, "a narrow cell gets no secondary radial")
end)

-- (2026-10-18, user: "a square of road where only one large building fits", "two roads very close": the offsets,
-- wobble and tilt of the organic grower brought neighbouring parallel streets below MIN_BLOCK, since laneCount /
-- stripCount cap only the mean spacing. Every lane along both its strips, every secondary radial along the shorter
-- arc, every back row off its spoke, the strips' ends included, at least MIN_BLOCK apart: ot_grow_organic.TRACE)
local FULL = os.getenv("TEST_FULL") ~= nil
test("organic plans: neighbouring parallel streets never closer than MIN_BLOCK, whatever the jitter", function()
	local I = ug_require(F.DIR .. "ot_inputs.lua")
	local STRIDE = FULL and 1 or 5
	local styles = { "EU_ORGANIC", "MED_HILL", "EU_EXTENSION" }
	local n, worst, kinds = 0, {}, {}
	local k = 0
	for town = 1, 30 do
		for si, id in ipairs(styles) do
			for _, deep in ipairs({ false, true }) do
				k = k + 1
				-- (every style, both deep modes and the first towns always; a stride over the rest)
				if FULL or town <= 2 or k % STRIDE == 0 then
					local inp = I.build({ forceStyle = id, townId = town, year = 1900 + 7 * town, pos = { 0, 0 },
						capacity = 900 + 300 * si, nameList = "::/names/germany/germany.names" })
					inp.deep = deep or nil
					local style = ST.resolve(inp)
					ORG.TRACE = {}
					local okP, err = pcall(ORG.masterPlan, style, { extent = 900, terrain = F.flat })
					local tr = ORG.TRACE
					ORG.TRACE = nil
					assert(okP, err)
					for _, r in ipairs(tr) do
						n = n + 1
						kinds[r.kind] = (kinds[r.kind] or 0) + 1
						if worst[r.kind] == nil or r.m < worst[r.kind].m then
							worst[r.kind] = { m = r.m, at = id .. (deep and " deep" or "") .. " town " .. town }
						end
					end
				end
			end
		end
	end
	local t = {}
	for kind, w in pairs(worst) do t[#t + 1] = string.format("%s %d min %.1f m (%s)", kind, kinds[kind], w.m, w.at) end
	table.sort(t)
	print("      " .. table.concat(t, " | "))
	for _, kind in ipairs({ "lane", "laneEnd", "radial", "radialEnd", "row" }) do
		ok((kinds[kind] or 0) > 0, "traced " .. kind)
		if worst[kind] then ok(worst[kind].m >= ST.MIN_BLOCK - 1e-6, kind .. " " .. worst[kind].m .. " m at " .. worst[kind].at) end
	end
end)

test("prune drops dangling small streets, keeps main stubs, cul-de-sacs and existing-node ends", function()
	local chosen = {
		{ key = "a", a = "J1", b = "J2", class = "main" },          -- main stub: stays
		{ key = "b", a = "J1", b = "J3", class = "small" },         -- J3 used by nobody else: dangling
		{ key = "c", a = "J1", b = "J4", class = "small", culDeSac = true },
		{ key = "d", a = "J2", b = "J5", class = "small" },         -- J5 is an existing node
		{ key = "e", a = "J2", b = "J6", class = "small" },         -- chain e-f dangling at J7
		{ key = "f", a = "J6", b = "J7", class = "small" },
	}
	local removed = SEL.prune(chosen, { J1 = 10, J5 = 11 })
	eq(removed, 3)
	local keys = {}
	for _, pc in ipairs(chosen) do keys[#keys + 1] = pc.key end
	eq(keys, { "a", "c", "d" })
end)

test("NA grid simulation: few dead-end stubs (was 23 in the Phase 2 preview)", function()
	local p = F.style({ year = 1965 })
	local g = OG.new()
	local incs = core.simulate(g, p, { terrain = F.flat }, 16)
	ok(#incs >= 12)
	local de = #OG.deadEnds(g)
	-- (2026-10-12: 12, half of them the outer zone's planned cul-de-sacs, now on the odd cross lines)
	ok(de <= 13, "dead ends " .. de)
	eq(F.components(g), 1)
	eq(F.crossingPair(g), nil)
end)

--- Engine-style town: a plus of four 100 m streets from (0, 0); dead ends 2..5.
local function plus()
	return OG.fromSnapshot({
		nodes = { { id = 1, x = 0, y = 0, z = 0 }, { id = 2, x = 100, y = 0, z = 0 }, { id = 3, x = -100, y = 0, z = 0 },
			{ id = 4, x = 0, y = 100, z = 0 }, { id = 5, x = 0, y = -100, z = 0 } },
		edges = { { id = 11, node0 = 1, node1 = 2 }, { id = 12, node0 = 1, node1 = 3 }, { id = 13, node0 = 1, node1 = 4 },
			{ id = 14, node0 = 1, node1 = 5 } },
	})
end

test("joinable: noJoin nodes and nodes with 2+ edges are never joined in deadEnd mode", function()
	local g = plus()
	ok(P.joinable(g, g.nodeById[2], "deadEnd"))
	ok(not P.joinable(g, g.nodeById[1], "deadEnd"))
	ok(P.joinable(g, g.nodeById[1], "any"))
	g.nodeById[2].noJoin = true
	ok(not P.joinable(g, g.nodeById[2], "deadEnd"))
	ok(not P.joinable(g, g.nodeById[2], "any"))
	ok(not P.joinable(g, nil, "any"))
end)

test("planIncrement in game mode joins only joinable dead ends and tags edges with piece keys", function()
	local g = plus()
	g.nodeById[2].noJoin = true
	g.nodeById[3].noJoin = true
	local p = F.style({ year = 1965 })
	local inc = core.planIncrement(g, p, { terrain = F.flat, maxEdges = 24 })
	ok(#inc.edges > 0)
	for _, j in ipairs(inc.joins) do
		ok(j.node == 4 or j.node == 5, "joined " .. j.node)
	end
	for _, e in ipairs(inc.edges) do
		ok(type(e.key) == "string", "edge key")
		ok(type(e.street) == "number")
	end
	ok(P.noNegativeZero(inc))
end)

test("planIncrement: excluded piece keys are left out", function()
	local g = plus()
	local p = F.style({ year = 1965 })
	local inc = core.planIncrement(g, p, { terrain = F.flat, maxEdges = 24 })
	local ex = {}
	for _, e in ipairs(inc.edges) do ex[e.key] = true end
	local inc2 = core.planIncrement(g, p, { terrain = F.flat, maxEdges = 24, exclude = ex })
	for _, e in ipairs(inc2.edges) do ok(not ex[e.key], "excluded " .. e.key) end
end)

test("saved frame: the plan lattice is anchored at the frame origin with the frame axis", function()
	local p = F.style({ year = 1965, frame = { axis = 0.3, origin = { 37, -12 } } })
	near(p.axis, 0.3, 1e-12)
	eq(p.axisSource, "saved")
	local mp = GRID.planFor(plus(), p, { extent = 800 })
	ok(mp.anchored)
	eq(mp.origin, { 37, -12 })
	local j = mp.junctions["g0:0"]
	near(j[1], 37, 1e-9)
	near(j[2], -12, 1e-9)
	-- the outer-zone profile keeps the frame
	local z = ST.zone(p, 5000)
	eq(z.frame, p.frame)
end)

test("Canada name lists resolve to the NA grid", function()
	local I = ug_require(F.DIR .. "ot_inputs.lua")
	eq(I.region("square_names_ca_ontario::/names/x.names"), "US")
	eq(ST.pickProfile(I.build({ nameList = "::/names/canada/canada.names" })), "NA_GRID")
	eq(ST.pickProfile(I.build({ nameList = "::/names/germany/germany.names" })), "EU_ORGANIC")
	near(G.z0(-0.0), 0, 0)
end)

test("plan: new nodes keep clear of existing streets, new edges don't brush past existing nodes", function()
	local g = plus()
	-- ends 3 m beside the east street: a new node there would overlap it
	local onStreet = P.plan(g, { { pts = { { 0, 100 }, { 50, 3 } }, startNode = 4 } }, { join = "deadEnd", maxSeg = 200 })
	eq(#onStreet.edges, 0)
	eq(onStreet.dropped[1].reason, "blockedNode")
	-- from the north dead end east and down past the east dead end (100, 0) at 2 m: refused
	local brush = P.plan(g, { { pts = { { 0, 100 }, { 102, 60 }, { 102, -60 } }, startNode = 4 } }, { join = "deadEnd", maxSeg = 200 })
	local nearExisting = 0
	for _, d in ipairs(brush.dropped) do if d.reason == "nearExisting" then nearExisting = nearExisting + 1 end end
	eq(nearExisting, 1)
	eq(#brush.edges, 1, "the first piece is fine")
end)

test("select: a dead end missing a plan junction by under 2 x snapR stands in for it", function()
	-- the east dead end at (100, 0) moved 12 m off the lattice junction near it
	local g = OG.fromSnapshot({
		nodes = { { id = 1, x = 0, y = 0, z = 0 }, { id = 2, x = 112, y = 0, z = 0 } },
		edges = { { id = 11, node0 = 1, node1 = 2 } },
	})
	local p = F.style({ year = 1965 })
	local mp = GRID.masterPlan(p, { extent = 600, origin = { 0, 0 } })
	-- put a junction exactly 12 m from node 2
	mp.junctions["g1:0"] = { 100, 0 }
	mp.jindex = nil
	local streets, report = SEL.select(g, mp, p, { maxEdges = 24, join = "deadEnd", terrain = F.flat })
	ok(report.adopted >= 1, "adopted " .. tostring(report.adopted))
	local fromDeadEnd = 0
	for _, st in ipairs(streets) do
		if st.startNode == 2 or st.endNode == 2 then fromDeadEnd = fromDeadEnd + 1 end
	end
	ok(fromDeadEnd >= 1, "streets start at the dead end itself")
end)

test("green reserves over every dead end: an empty increment plans again without them (greenRelax), others stay", function()
	F.withGreen(function()
		local g = F.vanillaTown(nil, { n = 3, spacing = 90, stub = 60 })
		local style = F.style({ nameList = "::/names/europe/europe.names", year = 1900 })
		-- a reserve 70 m beyond each dead end (radius 60: the next piece runs into it) and one far away
		local greens = {}
		for _, id in ipairs(OG.deadEnds(g)) do
			local nd = g.nodeById[id]
			local d = math.sqrt(nd.x * nd.x + nd.y * nd.y)
			greens[#greens + 1] = { nd.x + nd.x / d * 70, nd.y + nd.y / d * 70, 60 }
		end
		greens[#greens + 1] = { 900, 900, 80 }
		style.greens = greens
		local kept, n = core.greensClearOfDeadEnds(g, style)
		eq(n, #greens - 1)
		eq(#kept, 1)
		eq(kept[1][1], 900)
		core.GREEN_RELAX = false
		local inc0 = core.planIncrement(g, style, { terrain = nil })
		core.GREEN_RELAX = true
		eq(#inc0.edges, 0, "every growth point covered: nothing planned")
		local inc, report = core.planIncrement(g, style, {})
		ok(#inc.edges > 0, "planned once the covering reserves are relaxed")
		eq(report.greenRelax, #greens - 1)
		eq(#style.greens, #greens, "the style keeps its reserves")
	end)
end)

test("growth front (2026-10-18): a stuck town's limits.frontRelax and a fast grower's limits.frontExtra widen it", function()
	-- (a front at the innermost junction: every piece of the shaped town beyond its junctions is held, the plan comes out empty;
	-- frontRelax lets it through only when the increment would be empty, at most that many blocks, frontExtra always)
	local reach0, q0 = SEL.FRONT_REACH, SEL.FRONT_Q
	SEL.FRONT_REACH, SEL.FRONT_Q = 0, 0.01
	local okRun, err = pcall(function()
		local function plan(limits)
			local style, stats = F.style({ forceStyle = "EU_EXTENSION", townId = 7, year = 2020, shape = "linear",
				axis = { angle = 2.1, strength = 1 } }, F.flat)
			local g = F.roundCore(OG.new(), { angle = 2.1 })
			local inc, report = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd",
				maxEdges = 18, limits = limits })
			return inc, report
		end
		local inc0, rep0 = plan(nil)
		local incR, repR = plan({ frontRelax = SEL.FRONT_RELAX })
		local incX, repX = plan({ frontExtra = 3 })
		print(string.format("        edges: none %d, frontRelax %d (steps %s), frontExtra %d; front %.0f / %.0f / %.0f m",
			#inc0.edges, #incR.edges, tostring(repR.frontRelax), #incX.edges, rep0.frontCap or -1, repR.frontCap or -1,
			repX.frontCap or -1))
		ok((rep0.frontHeld or 0) > 0, "the front holds pieces")
		ok(#incR.edges > #inc0.edges, "frontRelax: more edges than with the bare front")
		ok((repR.frontRelax or 0) >= 1 and repR.frontRelax <= SEL.FRONT_RELAX, "frontRelax: 1..FRONT_RELAX steps")
		ok(#incX.edges > #inc0.edges, "frontExtra: more edges")
		ok(repX.frontCap > rep0.frontCap, "frontExtra: the front farther out")
	end)
	SEL.FRONT_REACH, SEL.FRONT_Q = reach0, q0
	assert(okRun, err)
end)
