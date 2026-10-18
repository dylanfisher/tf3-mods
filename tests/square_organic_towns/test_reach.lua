-- Showcase v7 round (2026-10-12, NEXT_PHASE_BRIEF 14): long arms only where the shape wants them (ot_shape.reach),
-- arms fill before they extend (ot_select ARM_FILL), straight wide streets (ot_core.straightWide).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")

local EU = "::/names/europe/europe.names"

test("reach: forced and site-picked linear arms are strong; style / neighbour picks are mild and shorter", function()
	local forced = F.style({ forceStyle = "EU_EXTENSION", shape = "linear", townId = 3 })
	eq(forced.shape.reach, 1)
	-- a valley: linear from the site (strong)
	local valley = F.style({ forceStyle = "EU_EXTENSION", townId = 3, nameList = EU }, F.valley(0.4))
	if valley.shape.id == "linear" then
		ok(valley.shape.reason:find("valley", 1, true), valley.shape.reason)
		eq(valley.shape.reach, 1, "site-picked linear: strong")
	end
	-- style towns with a neighbour 2.5 km away (the showcase grid): linear rarer and mild
	local lin, n = 0, 0
	for id = 1, 60 do
		for _, style in ipairs({ "JP_DENSE", "NA_SUBURB", "EU_ORGANIC" }) do
			local p = F.style({ forceStyle = style, townId = id, pos = { id * 37, 0 },
				neighbours = { { dir = 0, dist = 2500, town = 999 } } })
			n = n + 1
			if p.shape.id == "linear" then
				lin = lin + 1
				ok(p.shape.reach < 1, style .. " linear from " .. p.shape.reason .. ": mild")
			end
		end
	end
	print(string.format("      style towns with a neighbour at 2.5 km: %d of %d linear", lin, n))
	-- (round 5, 2026-10-13: the styles' own linear weight went up, "spread out across the landscape"; the neighbour's
	-- pull stays small: still a minority, every one of them mild)
	ok(lin / n < 0.4, lin .. " of " .. n .. " linear (v6: most)")
	-- mild arms reach less far along the axis than strong ones (same effective distance level)
	local sh = { id = "linear", centre = { 0, 0 }, axis = 0, arms = { 0, math.pi }, block = 100, reach = 1 }
	local strong = SH.distance(sh, 800, 0)
	sh.reach = SH.MILD_REACH
	ok(SH.distance(sh, 800, 0) > strong * 1.3, "mild: 800 m along the arm costs more")
	ok(SH.text(sh):find("reach=mild", 1, true))
end)

--- A round core whose streets all have houses (edge.built), then n increments of a strong linear EU extension town
--- whose new streets get none (houses never come). Returns the graph and the style.
local function emptyArms(n, fill)
	local saved = SEL.ARM_FILL
	SEL.ARM_FILL = fill
	local style, stats = F.style({ forceStyle = "EU_EXTENSION", townId = 7, year = 2020, shape = "linear",
		axis = { angle = 0.3, strength = 1 } }, F.flat)
	local g = F.roundCore(OG.new(), { angle = 0.3 })
	for _, e in ipairs(g.edges) do e.built = 3 end
	g.hasBuilt = true
	local okRun, err = pcall(function()
		for k = 1, n do
			local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
			if #inc.edges == 0 then break end
			OG.apply(g, inc, k)
			for _, e in ipairs(g.edges) do if e.built == nil then e.built = 0 end end
		end
	end)
	SEL.ARM_FILL = saved
	assert(okRun, err)
	return g, style
end

test("arms fill before they extend: streets run at most the lead beyond the last housed street (v6: 400-900 m)", function()
	local g, style = emptyArms(10, true)
	local g0 = emptyArms(10, false)
	local gaps, gaps0 = SEL.armGaps(g, style), SEL.armGaps(g0, style)
	local blk = math.max(style.block.len, style.block.depth)
	local lead = math.max(SEL.ARM_FILL_LEAD * blk, SEL.ARM_FILL_MIN_M)
	local worst, worst0 = 0, 0
	for i, x in ipairs(gaps) do worst = math.max(worst, x.street - x.housed) end
	for _, x in ipairs(gaps0) do worst0 = math.max(worst0, x.street - x.housed) end
	print(string.format("      empty arms after 10 increments: worst gap %.0f m with the fill rule, %.0f m without (%s / %s)",
		worst, worst0, SEL.armGapText(gaps), SEL.armGapText(gaps0)))
	-- (one 100 m edge of slack: the limit counts from the housed street midpoint)
	ok(worst <= lead + 100, "worst gap " .. worst)
	ok(worst < worst0, "the rule holds the arms back")
end)

test("one arm at a time: a new arm waits at the housed radius while another runs ahead unhoused (run 2240)", function()
	local style = F.style({ forceStyle = "EU_EXTENSION", townId = 7, shape = "fingers" })
	local sh = style.shape
	ok(sh.arms and #sh.arms >= 3, "a fingers town has 3+ arms")
	local g = F.roundCore(OG.new(), { angle = sh.axis })
	for _, e in ipairs(g.edges) do e.built = 2 end
	g.hasBuilt = true
	-- arm 1: an unhoused street out to 700 m from the core's edge along the first arm
	local a = sh.arms and sh.arms[1] or sh.axis
	local best, bd = nil, -math.huge
	for _, n in ipairs(OG.deadEnds(g)) do
		local nd = g.nodeById[n]
		local along = nd.x * math.cos(a) + nd.y * math.sin(a)
		if along > bd then best, bd = nd, along end
	end
	local prev = best
	for k = 1, 7 do
		local nx, ny = prev.x + 100 * math.cos(a), prev.y + 100 * math.sin(a)
		local nd = OG.addNode(g, nil, nx, ny, 0)
		local e = OG.addEdge(g, nil, prev.id, nd.id)
		e.built = 0
		prev = nd
	end
	local w0 = SEL.ARM_WAIT
	SEL.ARM_WAIT = false
	local f0 = SEL.armBuiltFronts(g, style)
	SEL.ARM_WAIT = true
	local f1 = SEL.armBuiltFronts(g, style)
	SEL.ARM_WAIT = w0
	print(string.format("      fronts without %.0f/%.0f, with the wait %.0f/%.0f (rq %.0f, lead %.0f, leader %s)",
		f0[1], f0[2], f1[1], f1[2], f1.rq, f1.lead, tostring(f1.leader)))
	eq(f1.leader, 1, "the arm with the unhoused street leads")
	ok(f1.waiting >= 1)
	eq(f1[1], f0[1], "the leading arm keeps its lead")
	for i = 2, #sh.arms do
		ok(f1[i] < f0[i], "arm " .. i .. " waits: " .. f1[i] .. " vs " .. f0[i])
	end
	-- (a linear town's two arms grow together: no wait)
	local lin = F.style({ forceStyle = "EU_EXTENSION", townId = 7, shape = "linear" })
	SEL.ARM_WAIT = true
	local fl = SEL.armBuiltFronts(g, lin)
	SEL.ARM_WAIT = w0
	eq(fl.waiting, 0)
end)

test("arm fill rule: no data (graph without built) -> not applied; housed arms may lead", function()
	local style = F.style({ forceStyle = "EU_EXTENSION", townId = 7, shape = "linear" })
	local g = F.roundCore(OG.new(), { angle = 0.3 })
	eq(SEL.armBuiltFronts(g, style), nil, "no built data")
	for _, e in ipairs(g.edges) do e.built = 0 end
	g.hasBuilt = true
	eq(SEL.armBuiltFronts(g, style), nil, "no housed street at all: no data to go by")
	for _, e in ipairs(g.edges) do e.built = 1 end
	local fronts, housed, behind = SEL.armBuiltFronts(g, style)
	ok(fronts and #fronts == 2 and behind[1] < fronts[1])
end)

--- One wide piece of 3 edges along a polyline of headings (deg), 90 m each, template `size`.
local LARGE = "::/infrastructure/street/town/town_new_large.street_template"
local MEDIUM = "::/infrastructure/street/town/town_new_medium.street_template"
local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local function piece(headings, template, bend)
	local inc = { edges = {}, nodes = {} }
	local x, y = 0, 0
	for i, h in ipairs(headings) do
		local a = math.rad(h)
		local b = math.rad(h + (bend or 0))
		local nx, ny = x + 90 * math.cos(a), y + 90 * math.sin(a)
		inc.edges[i] = { entity = -i, node0 = -(10 + i), node1 = -(11 + i), p0 = { x, y, 0 }, p1 = { nx, ny, 0 },
			t0 = { 90 * math.cos(a - math.rad(bend or 0) / 2), 90 * math.sin(a - math.rad(bend or 0) / 2), 0 },
			t1 = { 90 * math.cos(a + math.rad(bend or 0) / 2), 90 * math.sin(a + math.rad(bend or 0) / 2), 0 },
			template = template, key = "S1#1", class = "main", through = true }
		x, y = nx, ny
	end
	return inc
end

test("straight wide streets: large keeps gentle bends, sharper ones become medium or small", function()
	local inc = piece({ 0, 4, 8 }, LARGE)
	local h = core.straightWide(inc, inc.edges, SMALL)
	eq(inc.edges[1].template, LARGE, "4 deg joints: large")
	eq(h.bent, 0)
	ok(h.maxDefl.large <= 12)
	inc = piece({ 0, 20, 40 }, LARGE)
	h = core.straightWide(inc, inc.edges, SMALL)
	eq(inc.edges[2].template, MEDIUM, "20 deg joints: medium")
	eq(h.bent, 1)
	inc = piece({ 0, 45, 90 }, LARGE)
	core.straightWide(inc, inc.edges, SMALL)
	eq(inc.edges[1].template, SMALL, "45 deg joints: small")
	inc = piece({ 0, 0, 0 }, LARGE, 30)
	core.straightWide(inc, inc.edges, SMALL)
	eq(inc.edges[1].template, SMALL, "30 deg within each edge: over the medium limit too")
	inc = piece({ 0, 0, 0 }, MEDIUM, 40)
	core.straightWide(inc, inc.edges, SMALL)
	eq(inc.edges[1].template, SMALL, "medium bending 40 deg per edge: small")
	inc = piece({ 0, 15, 30 }, MEDIUM)
	core.straightWide(inc, inc.edges, SMALL)
	eq(inc.edges[1].template, MEDIUM, "medium: modest curves stay")
	-- a T at a node (two pieces of different lines) is not a bend
	inc = piece({ 0 }, LARGE)
	local e2 = { entity = -9, node0 = inc.edges[1].node1, node1 = -99, p0 = inc.edges[1].p1, p1 = { 90, 90, 0 },
		t0 = { 0, 90, 0 }, t1 = { 0, 90, 0 }, template = LARGE, key = "S2#1", class = "main" }
	inc.edges[2] = e2
	core.straightWide(inc, inc.edges, SMALL)
	eq(inc.edges[1].template, LARGE); eq(e2.template, LARGE)
end)

test("straight wide streets in planned towns: kept large pieces bend <= 12 deg, medium <= 30 deg", function()
	for _, id in ipairs({ "NA_GRID", "NA_SUBURB", "SUPERBLOCK", "EU_EXTENSION", "EU_ORGANIC" }) do
		local style, stats = F.style({ forceStyle = id, townId = 5, year = 1980, capacity = 3000 }, F.flat)
		local g = OG.new()
		local maxL, maxM, bent = 0, 0, 0
		for k = 1, 8 do
			local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "any" })
			if #inc.edges == 0 then break end
			maxL = math.max(maxL, inc.hier.maxDefl.large)
			maxM = math.max(maxM, inc.hier.maxDefl.medium)
			bent = bent + inc.hier.bent
			OG.apply(g, inc, k)
		end
		print(string.format("      %-12s wide pieces: max deflection large %.0f, medium %.0f deg, narrowed %d", id, maxL, maxM, bent))
		ok(maxL <= core.STRAIGHT_LIMITS.large.joint + 1e-6, id .. " large " .. maxL)
		ok(maxM <= core.STRAIGHT_LIMITS.medium.joint + 1e-6, id .. " medium " .. maxM)
	end
end)
