-- Head start per form (2026-10-13, real map round 3). User: "Especially in the beginning, most towns look the same. It
-- would be nice if they could immediately start with more character: longer, skinny, sprawling, etc." and the real map
-- run's Axbridge (an ~800 m empty medium street to the map edge in the head start's round 2). The head start now plans
-- with a lead limit (every piece within ot_driver HEAD_LEAD_M of a street with houses, the arms' fill lead the same) and
-- form steering (armed shapes: pieces off the arms cost more), and runs 2-5 rounds by size / form.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

local TOWNS = { 1, 7, 13, 21 }
local FORMS = { "clustered", "linear", "fingers", "radiating", "sprawling", "wide" }

--- A round game core with its houses (as the game makes a new map's town: ~250 buildings), then `rounds` head-start
--- increments of 12 edges (no houses arrive meanwhile). Returns the graph, the new edges' max distance from a housed
--- street midpoint (m), the new street length and the core's edge count.
local function headStart(form, town, rounds, limits, styleId)
	local style, stats
	F.withForms(function()
		style, stats = F.style({ forceStyle = styleId or "EU_ORGANIC", townId = town, year = 1900, form = form,
			nameList = "::/names/europe/europe.names" }, F.flat)
	end)
	local g = F.roundCore(OG.new(), { angle = 0.3 * town })
	F.markBuilt(g, 250)
	local housed = {}
	for _, e in ipairs(g.edges) do
		if (e.built or 0) > 0 then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			housed[#housed + 1] = { (a.x + b.x) / 2, (a.y + b.y) / 2 }
		end
	end
	local n0 = #g.edges
	local lead, len = 0, 0
	for k = 1, rounds do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = D.HEAD_EDGES,
			limits = limits })
		if #inc.edges == 0 then break end
		for _, e in ipairs(inc.edges) do
			len = len + G.dist(e.p0[1], e.p0[2], e.p1[1], e.p1[2])
			for _, p in ipairs({ e.p0, e.p1 }) do
				local best = math.huge
				for _, h in ipairs(housed) do best = math.min(best, G.dist(p[1], p[2], h[1], h[2])) end
				lead = math.max(lead, best)
			end
		end
		OG.apply(g, inc, k)
		-- (the game keeps its housed state: head-start streets wait for the houses)
		for _, e in ipairs(g.edges) do if e.built == nil then e.built = 0 end end
	end
	return g, lead, len, n0, style
end

local HEAD = D.headLimits()

test("head start per form: distinct shapes from day one, every piece within the lead limit", function()
	local m = {}
	for _, form in ipairs(FORMS) do
		local acc = { elong = 0, arms = 0, side = 0, lead = 0, len = 0, edges = 0 }
		for _, town in ipairs(TOWNS) do
			local g, lead, len, n0 = headStart(form, town, 4, HEAD)
			-- (the head start's own streets: where the first new quarters go; the round game core is the same in all)
			local segs = {}
			for i = n0 + 1, #g.edges do
				local e = g.edges[i]
				local p, q = g.nodeById[e.n0], g.nodeById[e.n1]
				segs[#segs + 1] = { p.x, p.y, q.x, q.y }
			end
			local mt = #segs > 0 and MT.segments(segs, 0, 0) or { elong = 1, arms = 0, side = 0.5 }
			local w = 1 / #TOWNS
			acc.elong, acc.arms, acc.side = acc.elong + mt.elong * w, acc.arms + mt.arms * w, acc.side + mt.side * w
			acc.lead = math.max(acc.lead, lead)
			acc.len, acc.edges = acc.len + len * w, acc.edges + (#g.edges - n0) * w
		end
		m[form] = acc
		print(string.format("      %-9s new streets: elong %.2f arms %.1f side %.2f | %.0f m in %.0f edges, worst lead %.0f m", form, acc.elong,
			acc.arms, acc.side, acc.len, acc.edges, acc.lead))
		ok(acc.lead <= D.HEAD_LEAD_M + 1, form .. ": lead within the limit: " .. acc.lead)
		ok(acc.edges >= 8, form .. ": the head start builds: " .. acc.edges)
	end
	local c = m.clustered
	ok(m.linear.elong >= c.elong + 0.25, string.format("linear longer: %.2f vs %.2f", m.linear.elong, c.elong))
	ok(m.fingers.arms >= c.arms + 1 or m.radiating.arms >= c.arms + 1, string.format("spokes: fingers %.1f / radiating %.1f vs %.1f",
		m.fingers.arms, m.radiating.arms, c.arms))
	ok(m.wide.elong >= c.elong + 0.1, string.format("wide an oval: %.2f vs %.2f", m.wide.elong, c.elong))
end)

test("head start form steering: linear arms take more of the head start than without it", function()
	local inArm, inArm0 = 0, 0
	for _, town in ipairs(TOWNS) do
		for pass = 1, 2 do
			local lim = pass == 1 and HEAD or { leadM = D.HEAD_LEAD_M, armFillM = D.HEAD_LEAD_M }   -- (no steering, no reach)
			local g, _, _, n0, style = headStart("linear", town, 3, lim)
			local SH = ug_require(F.DIR .. "ot_shape.lua")
			local a, t = 0, 0
			for i = n0 + 1, #g.edges do
				local e = g.edges[i]
				local p, q = g.nodeById[e.n0], g.nodeById[e.n1]
				local l = G.dist(p.x, p.y, q.x, q.y)
				t = t + l
				if SH.inArm(style.shape, (p.x + q.x) / 2, (p.y + q.y) / 2) then a = a + l end
			end
			if pass == 1 then inArm = inArm + a / math.max(t, 1) / #TOWNS else inArm0 = inArm0 + a / math.max(t, 1) / #TOWNS end
		end
	end
	print(string.format("      linear head start: share of new length in the arms %.2f (without steering %.2f)", inArm, inArm0))
	ok(inArm >= inArm0, "steering keeps or raises the arm share")
	ok(inArm >= 0.5, "most head-start length goes along the arms: " .. inArm)
end)

test("lead limit: without it a lens head start may run far ahead of the houses; with it never beyond the limit", function()
	local worst0, worst = 0, 0
	local savedMax = SEL.MAX_LEAD_M
	for _, town in ipairs(TOWNS) do
		SEL.MAX_LEAD_M = nil
		local _, l0 = headStart("wide", town, 4, { headForm = true }, "EU_EXTENSION")
		SEL.MAX_LEAD_M = savedMax
		local _, l1 = headStart("wide", town, 4, HEAD, "EU_EXTENSION")
		worst0, worst = math.max(worst0, l0), math.max(worst, l1)
	end
	SEL.MAX_LEAD_M = savedMax
	print(string.format("      EU extension lens, 4 rounds: worst lead %.0f m without the limit, %.0f m with it", worst0, worst))
	ok(worst <= D.HEAD_LEAD_M + 1, "with the limit")
	ok(worst <= worst0, "never more than without")
end)

test("head rounds by size and form: 2..5, long / spidery / character forms more", function()
	eq(D.headRounds(50, "clustered", false), 2)
	eq(D.headRounds(50, "linear", false), 3)
	eq(D.headRounds(260, "clustered", false), 4)
	eq(D.headRounds(400, "fingers", true), 5)
	eq(D.headRounds(0, nil, false), D.HEAD_ROUNDS)
end)
