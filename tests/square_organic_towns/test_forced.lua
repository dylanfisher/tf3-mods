-- Forced increments keep their empty limits (2026-10-14 §57; showcase run 2026-10-14_2237: the roundabout town's long
-- empty snaking roads, Shape cross's empty combs, EU organic's thin dead-end fingers): the showcase forces increments
-- regardless of demand and its plans skipped the own empty budget, so each one ran on from a street with a house or two.
-- Now the driver's forced plans keep the own empty budget (floored at core.OWN_EMPTY_MIN edges) and the sparse-street
-- hold (ot_select SPARSE): the unhoused street length stays within the budget, no new piece among nearly empty streets,
-- every new piece within the lead limit of a housed street.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local CH = ug_require(F.DIR .. "ot_character.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

local function styleOf(kind, styleId, id)
	local r = { townId = id or 11, year = 1975, nameList = "::/names/france/france.names", pos = { 0, 0 }, capacity = 900 }
	r.terrain = T.stats(F.flat, 0, 0, 600, 24)
	local inp = I.build(r)
	inp.wide = T.wide(F.flat, 0, 0, 2000)
	if kind then
		inp.charKind, inp.charForm, inp.charMotifs = kind, CH.formFor(kind), CH.motifsFor(kind)
		inp.charSite = { region = inp.region }
		inp.autoStyle = true
	else
		inp.forceStyle = styleId
	end
	return ST.resolve(inp)
end

--- n forced plans, the houses lagging (fill lots a plan): with the driver's forced-plan limits (on) or as before (off).
--- Returns { empty = unhoused m at the end, own = own unhoused m, far = the farthest new point from a housed street
--- at its plan, sparseHeld, edges, plans }.
local function forced(st, n, fill, on)
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local out = { far = 0, sparseHeld = 0, edges = 0, plans = 0, overBudget = 0 }
	for k = 1, n do
		local opts = { terrain = F.flat, join = "deadEnd", maxEdges = 18 }
		if on then
			opts.limits = { sparse = true }
			opts.ownEmptyFloor = core.OWN_EMPTY_MIN
			opts.ownEmpty = function(e) return e.increment ~= nil end
		end
		local inc, report = core.planIncrement(g, st, opts)
		if report then out.sparseHeld = out.sparseHeld + (report.sparseHeld or 0) end
		if #inc.edges > 0 then
			out.plans, out.edges = out.plans + 1, out.edges + #inc.edges
			local idx = SEL.housedIndexM(g, 2000)
			for _, e in ipairs(inc.edges) do
				for _, p in ipairs({ e.p0, e.p1 }) do
					local d = idx and SEL.housedDist(idx, p[1], p[2]) or 0
					if d > out.far then out.far = d end
				end
			end
			OG.apply(g, inc, k)
		end
		F.markBuilt(g, 120 + fill * k)
	end
	out.empty = MT.emptyLen(g) or 0
	out.own = MT.emptyLen(g, function(e) return e.increment ~= nil end) or 0
	local L = 0
	for _, e in ipairs(g.edges) do L = L + OG.edgeLength(g, e) end
	out.length = L
	return out
end

local CASES = {
	{ label = "roundabout town (cross arms)", kind = "roundabout_town" },
	{ label = "EU organic", style = "EU_ORGANIC" },
}

for _, c in ipairs(CASES) do
	test("forced plans with lagging houses keep the empty limits: " .. c.label, function()
		FM.ENABLED = true
		local okR, err = pcall(function()
			local ids = FULL and { 11, 12, 13 } or { 11 }
			for _, id in ipairs(ids) do
				local st = styleOf(c.kind, c.style, id)
				local before = forced(st, 14, 30, false)
				local after = forced(styleOf(c.kind, c.style, id), 14, 30, true)
				print(string.format("%s %d: unhoused %.0f m -> %.0f m (own %.0f -> %.0f), farthest new point %.0f -> %.0f m, "
					.. "edges %d -> %d in %d -> %d plans, sparse held %d", c.label, id, before.empty, after.empty, before.own,
					after.own, before.far, after.far, before.edges, after.edges, before.plans, after.plans, after.sparseHeld))
				-- the lead limit holds in both; the own unhoused streets stay near the budget (+ the floor's edges a plan)
				ok(after.far <= SEL.MAX_LEAD_M + 1, "within the lead limit")
				local budget = core.OWN_EMPTY_BASE + core.OWN_EMPTY_SHARE * after.length
				ok(after.own <= budget + core.OWN_EMPTY_MIN * core.EMPTY_EDGE_M * 3, "own empty near the budget")
				ok(after.empty <= 0.8 * before.empty, "fewer empty streets than before")
				ok(after.plans >= 0.5 * before.plans, "still grows")
			end
		end)
		FM.ENABLED = false
		assert(okR, err)
	end)
end

test("sparse streets: a piece among nearly empty streets is held, one among housed streets is not", function()
	local g = OG.new()
	-- a housed core (east, 1 km) and a long empty finger (west, 1.6 km)
	local prev = OG.addNode(g, nil, 0, 0, 0)
	for i = 1, 20 do
		local n = OG.addNode(g, nil, -i * 80, 0, 0)
		local e = OG.addEdge(g, nil, prev.id, n.id, "small")
		e.built = 0
		prev = n
	end
	prev = g.nodes[1]
	for i = 1, 12 do
		local n = OG.addNode(g, nil, i * 80, 0, 0)
		local e = OG.addEdge(g, nil, prev.id, n.id, "small")
		e.built = 12
		prev = n
	end
	g.hasBuilt = true
	local idx = assert(SEL.sparseIndex(g))
	ok(SEL.sparseAt(idx, -1200, 0), "the finger is sparse")
	ok(not SEL.sparseAt(idx, 700, 0), "the core is not")
	ok(not SEL.sparseAt(idx, 0, 2000), "no streets: not sparse (the lead limits decide)")
	-- too little empty street in the town, or a town without houses yet: no index
	for _, e in ipairs(g.edges) do e.built = 3 end
	eq(SEL.sparseIndex(g), nil)
	for _, e in ipairs(g.edges) do e.built = 0 end
	eq(SEL.sparseIndex(g), nil)
end)

---------------------------------------------------------------------------
-- the stall (2026-10-15 §59; showcase run 2026-10-15_0234 load 1, Blank Slate 2020: EU organic, town 7041, a linear town,
-- built its own plans for 3 steps, then every forced plan came out empty, `reached=14 blocked=4-5 excluded=14-16`,
-- and the showcase stopped it after 7 steps while its houses went on from 373 to 572): the frontier of a growing town
-- is its newest, emptiest streets, so the sparse-street hold held every piece. Replayed here as a linear EU organic
-- town (2020) from a round core, the showcase's house counts arriving from the core outward.

local D = ug_require(F.DIR .. "ot_driver.lua")
local SHOW_HOUSES = { 185, 251, 313, 373, 418, 468, 513, 560, 600, 640, 680 }

--- Forced plans of a 7041-like town: { edges per plan, relaxed plans, the largest relaxed plan, farthest new point }.
local function stallReplay(town)
	local style, stats = F.style({ forceStyle = "EU_ORGANIC", townId = town, year = 2020, shape = "linear",
		axis = { angle = 0, strength = 1 } }, F.flat)
	local g = F.roundCore(OG.new(), {})
	F.markBuilt(g, SHOW_HOUSES[1])
	local out = { edges = {}, relaxed = 0, relaxMax = 0, far = 0, held = {} }
	for k = 1, #SHOW_HOUSES - 1 do
		local opts = { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18, limits = { sparse = true },
			ownEmptyFloor = core.OWN_EMPTY_MIN, ownEmpty = function(e) return e.increment ~= nil end }
		local inc, report = core.planIncrement(g, style, opts)
		out.edges[k] = #inc.edges
		out.held[k] = D.heldText(report)
		if report and report.sparseRelax then
			out.relaxed = out.relaxed + 1
			out.relaxMax = math.max(out.relaxMax, #inc.edges)
		end
		if #inc.edges > 0 then
			local idx = SEL.housedIndexM(g, 2000)
			for _, e in ipairs(inc.edges) do
				for _, p in ipairs({ e.p0, e.p1 }) do
					local d = idx and SEL.housedDist(idx, p[1], p[2]) or 0
					if d > out.far then out.far = d end
				end
			end
			OG.apply(g, inc, k)
		end
		F.markBuilt(g, SHOW_HOUSES[k + 1])
	end
	return out
end

test("stall replay (showcase 0234, EU organic 7041): a town with houses keeps getting forced plans", function()
	FM.ENABLED = true
	local okR, err = pcall(function()
		local towns = FULL and { 7041, 11, 12, 13 } or { 7041, 12 }
		for _, town in ipairs(towns) do
			-- before: without the starve relaxation the sparse hold empties plans while the houses keep coming
			local keep = SEL.SPARSE_RELAX_EDGES
			SEL.SPARSE_RELAX_EDGES = 0
			local before = stallReplay(town)
			SEL.SPARSE_RELAX_EDGES = keep
			local after = stallReplay(town)
			local nb, na = 0, 0
			for k = 1, #after.edges do
				if before.edges[k] == 0 then nb = nb + 1 end
				if after.edges[k] == 0 then na = na + 1 end
			end
			print(string.format("town %d: edges before %s (empty %d), after %s (empty %d, relaxed %d, largest relaxed %d, "
				.. "farthest %.0f m); first plan held %s", town, table.concat(before.edges, "/"), nb,
				table.concat(after.edges, "/"), na, after.relaxed, after.relaxMax, after.far, before.held[1]))
			ok(nb >= 1, "the replay reproduces the stall without the relaxation")
			eq(na, 0, "every plan of a town with houses has streets")
			ok(after.relaxed >= 1, "the relaxation did it")
			ok(after.relaxMax <= SEL.SPARSE_RELAX_EDGES, "a relaxed plan stays small")
			ok(after.far <= SEL.MAX_LEAD_M + 1, "the lead limit still holds")
		end
	end)
	FM.ENABLED = false
	assert(okR, err)
end)

test("demand play: a town held by the lead limit says so and grows again as the houses arrive", function()
	-- a wide core (rings 300 / 600 / 900 m) whose houses stand only round the centre: every dead end ~650 m out from them
	local g = F.roundCore(OG.new(), { rings = { 300, 600, 900 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 40)
	local style, stats = F.style({ forceStyle = "EU_ORGANIC", townId = 21, year = 1960 }, F.flat)
	local inc, report = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 12 })
	local text, top = D.heldText(report)
	print(string.format("held: %d edges, %s", #inc.edges, text))
	eq(#inc.edges, 0, "every piece beyond the lead limit")
	eq(top, "lead", "the empty plan names its hold")
	-- the houses arrive along the empty streets: the lead limit lets the pieces come again
	F.markBuilt(g, 2000)
	local inc2 = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 12 })
	print(string.format("after the houses: %d edges", #inc2.edges))
	ok(#inc2.edges > 0, "plans again once houses stand near the dead ends")
end)

test("the held text and the STUCK line's schedule", function()
	eq(D.heldText(nil), "-")
	eq(D.heldText({ leadHeld = 0 }), "-")
	local t, top = D.heldText({ leadHeld = 2, sparseHeld = 14, sparseRelax = true })
	eq(t, "lead=2,sparse=14,sparseRelax")
	eq(top, "sparse")
	ok(D.STUCK_AT >= 2 and D.STUCK_EVERY >= 1)
	-- (§75 follow-up: the knot holds on the empty PLAN / STUCK lines too)
	eq(D.knotText(nil), "0")
	eq(D.knotText({ knotHeld = 0 }), "0")
	eq(D.knotText({ knotHeld = 3, knotWhy = { parallel = 1, side = 2 } }), "3:0/1/0/2/0")
	-- (one empty row at a time, 2026-10-19: a fifth count)
	eq(D.knotText({ knotHeld = 4, knotWhy = { row = 4 } }), "4:0/0/0/0/4")
end)

---------------------------------------------------------------------------
-- the look zone (EU organic's east grid block, the same run: a 2060 grid look of 0.59 on the whole organic plan)

local GR = ug_require(F.DIR .. "ot_grid.lua")

local function euOrganic(year, id)
	local r = { townId = id or 11, year = year, nameList = "::/names/france/france.names", pos = { 0, 0 }, capacity = 900 }
	r.terrain = T.stats(F.flat, 0, 0, 600, 24)
	local inp = I.build(r)
	inp.wide = T.wide(F.flat, 0, 0, 2000)
	inp.forceStyle = "EU_ORGANIC"
	return ST.resolve(inp), inp
end

test("look zone: a late organic town is regular only outward, blended in steps, never a full lattice", function()
	local on0 = GR.ON
	GR.ON = true
	local okR, err = pcall(F.withOrganicRings, function()
	local p, inp = euOrganic(2060)
	ok(inp.gridBias.look > ST.LOOK_CORE, "a high look " .. inp.gridBias.look)
	ok(p.outer and p.outer.lookZone, "the look as an outer zone")
	near(p.gridLook, ST.LOOK_CORE, 1e-9, "the core keeps LOOK_CORE")
	local prev, steps = nil, {}
	local blend = ST.ZONE_BLEND * ((p.radial and p.radial.ringEvery) or 250)
	for _, d in ipairs({ 0, 200, ST.LOOK_FROM - 1, ST.LOOK_FROM + 0.3 * blend, ST.LOOK_FROM + 0.6 * blend,
		ST.LOOK_FROM + 0.9 * blend, ST.LOOK_FROM + blend + 50, 1500 }) do
		local z = ST.zone(p, d)
		steps[#steps + 1] = string.format("%.0f:%.2f", d, z.gridness)
		if prev then ok(z.gridness >= prev - 1e-9, "no step down at " .. d) end
		prev = z.gridness
	end
	print("gridness by distance: " .. table.concat(steps, " "))
	local core, far = ST.zone(p, 0).gridness, ST.zone(p, 1500).gridness
	ok(core < far, "more regular outward")
	-- every blend step at most a third of the rise (ZONE_BLEND_STEPS 3): no seam
	local z1 = ST.zone(p, ST.LOOK_FROM + 0.3 * blend).gridness
	ok(z1 - core <= (far - core) / 2 + 1e-9, "blended, not cut in")
	-- never the full look's lattice: the zone's look at most LOOK_ZONE_MAX
	local full = { grower = "organic", gridness = ST.PROFILES.EU_ORGANIC.gridness }
	GR.applyLook(full, inp.gridBias.look)
	ok(far < full.gridness, string.format("zone %.2f below the full look's %.2f", far, full.gridness))
	-- an early town (a low look) keeps its plan as before: no zone
	local e = euOrganic(1925)
	ok(e.outer == nil or not e.outer.lookZone, "no look zone in 1925")
	end)
	GR.ON = on0
	assert(okR, err)
end)

test("wedge frame: a link through empty land far from the houses waits (ring lead 160 m)", function()
	local WG = ug_require(F.DIR .. "ot_wedge.lua")
	local g = OG.new()
	-- a linear town along x: housed core, two dead ends in the north wedge 300 m apart, one near houses, one far out
	local c0 = OG.addNode(g, nil, -200, 0, 0)
	local c1 = OG.addNode(g, nil, 200, 0, 0)
	OG.addEdge(g, nil, c0.id, c1.id, "small").built = 12
	local a = OG.addNode(g, nil, 0, 0, 0)
	local t1 = OG.addNode(g, nil, -60, 230, 0)
	local t2 = OG.addNode(g, nil, 150, 300, 0)
	local m1 = OG.addNode(g, nil, -60, 120, 0)
	OG.addEdge(g, nil, a.id, m1.id, "small").built = 6
	OG.addEdge(g, nil, m1.id, t1.id, "small").built = 2
	local m2 = OG.addNode(g, nil, 150, 160, 0)
	OG.addEdge(g, nil, c1.id, m2.id, "small").built = 0
	OG.addEdge(g, nil, m2.id, t2.id, "small").built = 0
	g.hasBuilt = true
	local shape = { centre = { 0, 0 }, arms = { 0, math.pi }, axis = 0 }
	local hidx = SEL.housedIndexM(g, WG.LEAD_M)
	local base = { coreR = 150, housedIdx = hidx, housedDist = SEL.housedDist, noTails = true }
	local free = WG.frameStreets(g, shape, base)
	local held = WG.frameStreets(g, shape, { coreR = 150, housedIdx = hidx, housedDist = SEL.housedDist, noTails = true,
		ringLead = SEL.RING_LEAD_M })
	local function far(list)
		local m = 0
		for _, st in ipairs(list) do
			local p, q = st.pts[1], st.pts[#st.pts]
			for k = 0, 4 do
				local f = k / 4
				m = math.max(m, SEL.housedDist(hidx, p[1] + (q[1] - p[1]) * f, p[2] + (q[2] - p[2]) * f))
			end
		end
		return m
	end
	print(string.format("frame links: %d (farthest %.0f m from houses) -> %d with the ring lead (%.0f m)", #free, far(free),
		#held, far(held)))
	ok(#free >= 1 and far(free) > SEL.RING_LEAD_M, "without the rule: a link far from the houses")
	ok(far(held) <= SEL.RING_LEAD_M + 1e-6, "within the ring lead")
	-- (§59) two tips close together, both ~200 m out from the houses: their short link runs no farther out than the
	-- tips (the game's streets would start there anyway) and comes; the long link above still waits
	local g2 = OG.new()
	local h0 = OG.addNode(g2, nil, -200, 0, 0)
	local h1 = OG.addNode(g2, nil, 200, 0, 0)
	OG.addEdge(g2, nil, h0.id, h1.id, "small").built = 12
	local tips = {}
	for i, x in ipairs({ -40, 60 }) do
		local base = OG.addNode(g2, nil, x, 0, 0)
		local mid = OG.addNode(g2, nil, x, 110, 0)
		OG.addEdge(g2, nil, base.id, mid.id, "small").built = 0
		tips[i] = OG.addNode(g2, nil, x, 200, 0)
		OG.addEdge(g2, nil, mid.id, tips[i].id, "small").built = 0
	end
	g2.hasBuilt = true
	local hidx2 = SEL.housedIndexM(g2, WG.LEAD_M)
	local o2 = { coreR = 150, housedIdx = hidx2, housedDist = SEL.housedDist, noTails = true, ringLead = SEL.RING_LEAD_M }
	local short = WG.frameStreets(g2, shape, o2)
	local keep = WG.FAR_LINK_M
	WG.FAR_LINK_M = nil
	local none = WG.frameStreets(g2, shape, o2)
	WG.FAR_LINK_M = keep
	local function far2(list)
		local m = 0
		for _, st in ipairs(list) do
			local p, q = st.pts[1], st.pts[#st.pts]
			for k = 0, 4 do
				local f = k / 4
				m = math.max(m, SEL.housedDist(hidx2, p[1] + (q[1] - p[1]) * f, p[2] + (q[2] - p[2]) * f))
			end
		end
		return m
	end
	local tipD = math.max(SEL.housedDist(hidx2, tips[1].x, tips[1].y), SEL.housedDist(hidx2, tips[2].x, tips[2].y))
	print(string.format("short link between far tips (%.0f m out): %d (farthest %.0f m) with FAR_LINK_M, %d without", tipD,
		#short, far2(short), #none))
	ok(tipD > SEL.RING_LEAD_M, "the tips lie beyond the ring lead")
	eq(#short, 1, "the short link between the far tips comes")
	ok(far2(short) <= tipD + WG.FAR_SLACK_M + 1e-6, "no farther out than its tips")
	eq(#none, 0, "held by the ring lead alone")
end)
