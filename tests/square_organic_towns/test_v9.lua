-- Showcase v9 round (2026-10-12, NEXT_PHASE_BRIEF 16): housed front (no empty streets ahead of the houses,
-- polycentric), metropolis mechanics for the grid styles (style.mech: lock all, bigger increments, dosed fill), NA grid
-- grid-like from the first increments, Nordic cluster loops with cul-de-sacs and green cells, crescents around a
-- green, the new metrics (axisShare, emptyLen).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local MET = ug_require(F.DIR .. "ot_metro.lua")
local GRID = ug_require(F.DIR .. "ot_grow_grid.lua")
local CR = ug_require(F.DIR .. "ot_crescent.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")

local function houses(k) return 150 + 75 * k end

local function segsOf(inc)
	local s = {}
	for _, e in ipairs(inc.edges) do s[#s + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2] } end
	return s
end

--- n increments from a round game-made core, houses arriving after each (F.markBuilt). Returns per step
--- { edges, grid (axisShare of the increment), empty (unhoused m after the houses came) }, g, style.
local function grow(style, stats, n, town, maxEdges)
	local g = F.roundCore(OG.new(), { angle = 0.3 * town })
	F.markBuilt(g, houses(0))
	local steps = {}
	for k = 1, n do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = maxEdges })
		local gs = #inc.edges > 0 and (MT.axisShare(segsOf(inc), style.axis)) or 0
		if #inc.edges > 0 then OG.apply(g, inc, k) end
		F.markBuilt(g, houses(k))
		steps[k] = { edges = #inc.edges, grid = gs, empty = (MT.emptyLen(g)) }
	end
	return steps, g
end

test("metrics: axisShare on the town axis, emptyLen of unhoused streets", function()
	local a = math.rad(20)
	local segs = { { 0, 0, 100 * math.cos(a), 100 * math.sin(a) }, { 0, 0, -50 * math.sin(a), 50 * math.cos(a) },
		{ 0, 0, 100 * math.cos(a + math.rad(45)), 100 * math.sin(a + math.rad(45)) } }
	near((MT.axisShare(segs, a)), 150 / 250, 1e-9)
	near((MT.axisShare(segs, a + math.pi / 2)), 150 / 250, 1e-9, "mod 90 deg")
	local g = OG.new()
	local n1, n2, n3 = OG.addNode(g, nil, 0, 0), OG.addNode(g, nil, 100, 0), OG.addNode(g, nil, 100, 50)
	local e1 = OG.addEdge(g, nil, n1.id, n2.id)
	local e2 = OG.addEdge(g, nil, n2.id, n3.id)
	eq(MT.emptyLen(g), nil, "no data")
	e1.built, e2.built, g.hasBuilt = 3, 0, true
	local len, n = MT.emptyLen(g)
	near(len, 50, 1e-9); eq(n, 1)
end)

test("housed front: no piece farther than the lead from a housed street; relaxed when the increment would starve", function()
	local style = F.style({ forceStyle = "NA_GRID", townId = 5, year = 2020 }, F.flat)
	ok(style.housedLead ~= nil)
	local g = F.roundCore(OG.new(), { angle = 0.4 })
	F.markBuilt(g, 120)
	local idx = SEL.housedIndex(g, style)
	ok(idx and idx.n > 0)
	local inc = core.planIncrement(g, style, { terrain = F.flat, join = "deadEnd", maxEdges = 28 })
	ok(#inc.edges > 0, "plans")
	local lim = idx.lead + SEL.HOUSED_RELAX * math.max(style.block.len, style.block.depth) + 1
	for _, e in ipairs(inc.edges) do
		for _, p in ipairs({ e.p0, e.p1 }) do
			ok(SEL.housedDist(idx, p[1], p[2]) <= lim, string.format("edge end %.0f m from a house", SEL.housedDist(idx, p[1], p[2])))
		end
	end
	-- no data: no limit
	local g2 = F.roundCore(OG.new(), { angle = 0.4 })
	eq(SEL.housedIndex(g2, style), nil)
end)

test("polycentric: the housed front keeps the unhoused street length down (Showcase v8: ~3-4 km of empty arterials)", function()
	local function run(housed)
		local tot, worst = 0, 0
		for _, town in ipairs({ 3, 11 }) do
			local base = F.style({ forceStyle = "NA_GRID", townId = town, year = 2020, capacity = 3000 }, F.flat)
			local st = MET.apply(base, { variant = "polycentric" }, { cap = 3000, forcedCentres = true })
			if not housed then st.housedLead, st.emptyBudget = nil, nil end
			local steps = grow(st, nil, 10, town, 36)
			for _, s in ipairs(steps) do
				tot = tot + (s.empty or 0) / (10 * 2)
				worst = math.max(worst, s.empty or 0)
			end
		end
		return tot, worst
	end
	local m0, w0 = run(false)
	local m1, w1 = run(true)
	print(string.format("      polycentric unhoused street length per step: mean %.0f -> %.0f m, worst %.0f -> %.0f m", m0, m1, w0, w1))
	ok(m1 < 0.4 * m0, "housed front + empty budget cut the empty length: " .. m1 .. " vs " .. m0)
	ok(m1 <= MET.POLY_EMPTY, "within the budget on average")
end)

test("NA grid (style.mech, 28-edge increments, lock all): grid streets on the town axis from the first increments", function()
	local sum1, sumAll, n = 0, 0, 0
	local base1 = 0
	for _, town in ipairs({ 1, 7, 13, 21 }) do
		local st, stats = F.style({ forceStyle = "NA_GRID", townId = town, year = 2020 }, F.flat)
		ok(st.mech and st.mech.lockAll and st.mech.maxEdges == 28)
		local steps = grow(st, stats, 3, town, st.mech.maxEdges)
		local s3 = 0
		for k = 1, 3 do s3 = s3 + steps[k].grid / 3 end
		sum1, n = sum1 + s3, n + 1
		-- v8: 18 edges, no housed front
		local st0 = F.style({ forceStyle = "NA_GRID", townId = town, year = 2020 }, F.flat)
		st0.housedLead = nil
		local b = grow(st0, stats, 3, town, 18)
		for k = 1, 3 do base1 = base1 + b[k].grid / 3 end
		sumAll = sumAll + steps[1].edges
	end
	print(string.format("      NA grid steps 1-3 gridShare %.2f (v8 settings %.2f), step-1 edges %.1f", sum1 / n, base1 / n, sumAll / n))
	ok(sum1 / n >= 0.6, "grid share " .. sum1 / n)
end)

test("Nordic: cluster loops (curved), cul-de-sacs into the cells, green cells without streets", function()
	local st = F.style({ nameList = "::/names/norway/x", climate = "temperate", year = 1960, townId = 9 })
	eq(st.id, "NORDIC")
	ok(st.cluster and st.sub)
	local mp = GRID.masterPlan(st, { extent = 900 })
	local cul, curved, small, other = 0, 0, 0, 0
	for _, pc in ipairs(mp.pieces) do
		if pc.culDeSac then cul = cul + 1 end
		if pc.curved or pc.dirA then curved = curved + 1 end
		if pc.class == "small" and not pc.culDeSac then small = small + 1 elseif not pc.culDeSac then other = other + 1 end
	end
	print(string.format("      Nordic plan: %d pieces, %d cul-de-sacs, %d curved / tangent, %d loop pieces", #mp.pieces, cul, curved, small + other))
	ok(cul > 0.25 * #mp.pieces, "many cul-de-sacs")
	ok(curved > 0.3 * #mp.pieces, "curving loops")
	-- grown from a core: dead ends and green
	local g = F.roundCore(OG.new(), { angle = 0.2 })
	for k = 1, 10 do
		local inc = core.planIncrement(g, st, { terrain = F.flat, join = "deadEnd", maxEdges = 18 })
		if #inc.edges > 0 then OG.apply(g, inc, k) end
	end
	local dead = #OG.deadEnds(g)
	print(string.format("      Nordic 10 increments: %d edges, %d dead ends", #g.edges, dead))
	ok(#g.edges > 100 and dead >= 8)
end)

test("crescents: arcs around the crescent meadows, nothing inside, a few per town", function()
	F.withGreen(function()
		local s = F.style({ forceStyle = "EU_ORGANIC", townId = 4, year = 1900, nameList = "::/names/germany/x" })
		local nc = 0
		for _, gr in ipairs(s.greens) do if gr[4] then nc = nc + 1 end end
		eq(nc, math.min(#s.greens, s.crescents))
		local g = OG.new()
		local arcEdges = 0
		for k = 1, 25 do
			local inc = core.planIncrement(g, s, { terrain = F.flat, join = "any" })
			if #inc.edges == 0 then break end
			OG.apply(g, inc, k)
		end
		local mp = core.masterPlan(g, s, { terrain = F.flat }, 8)
		local made = 0
		for _, c in ipairs(mp.crescents or {}) do if c.arcs > 0 then made = made + 1 end end
		ok(made >= 1, "a crescent planned")
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			for _, gr in ipairs(s.greens) do
				ok(math.sqrt((mx - gr[1]) ^ 2 + (my - gr[2]) ^ 2) >= gr[3] - 1, "no street inside a meadow")
				if gr[4] then
					local d = math.sqrt((mx - gr[1]) ^ 2 + (my - gr[2]) ^ 2)
					if math.abs(d - gr[3] - CR.ARC_SETBACK) < 12 then arcEdges = arcEdges + 1 end
				end
			end
		end
		print(string.format("      EU organic 25 increments: %d crescents planned of %d, %d edges on their arcs, green %s",
			made, #mp.crescents, arcEdges, MT.greenText(MT.greenGaps(g, {}))))
		ok(arcEdges >= 2, "arc streets built")
	end)
	-- unit: a straight street through the meadow is cut, an arc made around
	local mp = { junctions = { A = { -300, 0 }, B = { 300, 0 }, C = { 0, -300 }, D = { 0, 300 } }, pieces = {
		{ key = "h", a = "A", b = "B", pts = { { -300, 0 }, { 300, 0 } }, class = "small" },
		{ key = "v", a = "C", b = "D", pts = { { 0, -300 }, { 0, 300 } }, class = "small" },
		{ key = "in", a = "E", b = "F", pts = { { -20, 20 }, { 20, 20 } }, class = "small" } } }
	local made = CR.apply(mp, { greens = { { 0, 0, 100, true } } })
	eq(made, 1)
	local arcs, inside = 0, 0
	for _, pc in ipairs(mp.pieces) do
		if pc.crescent then arcs = arcs + 1 end
		local x, y = pc.pts[1][1], pc.pts[1][2]
		if pc.key == "in" then inside = inside + 1 end
		ok(pc.crescent or math.sqrt(x * x + y * y) >= 100 or math.sqrt(pc.pts[#pc.pts][1] ^ 2 + pc.pts[#pc.pts][2] ^ 2) >= 100)
	end
	eq(inside, 0, "the street inside the meadow dropped")
	eq(arcs, 3, "four crossings, the widest gap open: three arcs")
	eq(#mp.pieces, 4 + 3)
end)

test("driver: style.mech locks every new street, plans bigger increments, doses the fill beside any new street", function()
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local inc = { edges = { { key = "a", p0 = { 0, 0, 0 }, p1 = { 80, 0, 0 } }, { key = "b", p0 = { 80, 0, 0 }, p1 = { 80, 90, 0 } },
		{ key = "a", p0 = { 80, 90, 0 }, p1 = { 100, 90, 0 } } } }
	local compact = { id = "compact", centre = { 0, 0 } }
	local st = { mech = { lockAll = true, maxEdges = 28, fill = "dose" }, shape = compact, centre = { 0, 0 } }
	local keys, n, mode = D.lockKeys({ style = st, inc = inc })
	eq(n, 2); eq(mode, "mech"); ok(keys.a and keys.b)
	eq(D.lockKeys({ style = st, inc = inc, lock = "off" }), nil, "a job's lock off still wins")
	-- a metropolis keeps its own rule
	eq(select(3, D.lockKeys({ style = { metro = { variant = "grid", centres = {} }, mech = st.mech, centre = { 0, 0 } }, inc = inc })), "metro")
	local caps = { actual = 900, target = 1000, initial = 750 }
	local kind, why = D.fillKind({ style = st }, {}, caps, nil, 200, 0)
	eq(kind, "dose"); eq(why, "mech")
	eq(select(2, D.fillKind({ style = { shape = compact } }, {}, caps, nil, 200, 0)), "unshaped", "no mech: compact towns no dose")
	local pts = D.fillPoints("dose", inc.edges, compact, nil, nil, st)
	eq(#pts, D.FILL_POINTS, "beside any new street")
	eq(#D.fillPoints("dose", inc.edges, compact, nil, nil, { shape = compact }), 0, "no mech: arm / rim streets only")
	local saved = D.MECH
	D.MECH = false
	eq(D.lockKeys({ style = st, inc = inc }), nil, "MECH off: v8")
	D.MECH = saved
	-- profiles
	for _, id in ipairs({ "NA_GRID", "NA_SUBURB", "MED_ENSANCHE", "SUPERBLOCK" }) do
		local p = ST.profile(id)
		ok(p.mech and p.mech.lockAll and p.mech.maxEdges >= 28, id .. " borrows the metropolis mechanics")
	end
	for _, id in ipairs({ "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "JP_DENSE", "NORDIC" }) do eq(ST.profile(id).mech, nil, id) end
	-- a metropolis drops the style's copy and keeps its own
	local base = F.style({ forceStyle = "NA_GRID", townId = 2, year = 2020 })
	local m = MET.apply(base, { variant = "grid" }, { cap = 6000 })
	eq(m.mech, nil); eq(m.housedLead, nil); eq(m.emptyBudget, nil)
	local pc = MET.apply(base, { variant = "polycentric" }, { cap = 6000, forcedCentres = true })
	eq(pc.housedLead, MET.POLY_HOUSED); eq(pc.emptyBudget, MET.POLY_EMPTY)
end)
