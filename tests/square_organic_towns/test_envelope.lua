-- Shapes round (SHAPES_BRIEF 2026-10-12): Showcase v4's shape row read as round blobs. Whole-town metrics (game
-- core + our streets, and a house proxy) from a round vanilla-like core as in game (F.roundCore: ~70 edges,
-- 14 dead ends), 10 increments of 18 edges (the in-game increment), EU extension 2020 as in the showcase.
-- Causes found: the driver's street snapshot held only the streets within the building extent + 300 m, so arm
-- tips further out were never reached (reproduced with F.snapshotCut); pieces filled all round the core because
-- the growth front is a quantile of the effective distance, which a round core widens (now the shape envelope,
-- ot_select.envelopeCap); bare main-street spines ran ahead of their cross streets (now arm fronts).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")

local TOWNS = { 1, 7, 13, 21 }
local N, MAXE = 10, 18

--- houses after k showcase steps (v4: 223 buildings after step 1, ~600 after step 10)
local function houseCount(k) return 180 + 45 * k end

--- One town grown n increments from a round core. cut = true: the old in-game snapshot (streets within the house
--- extent + 300 m only). Returns streets metrics, houses metrics, graph, style, the increments' reports.
local function grow(shape, town, n, cut, styleId)
	local style, stats = F.style({ forceStyle = styleId or "EU_EXTENSION", townId = town, year = 2020, shape = shape }, F.flat)
	local g = F.roundCore(OG.new(), { angle = 0.3 * town })
	local reps = {}
	for k = 1, n or N do
		local pg = g
		if cut then
			local _, r90 = F.houses(g, houseCount(k))
			pg = F.snapshotCut(g, r90 + 300)
		end
		local inc, rep = core.planIncrement(pg, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = MAXE })
		if #inc.edges == 0 then break end
		reps[#reps + 1] = { rep = rep, inc = inc, g0 = #g.edges }
		OG.apply(g, inc, k)
	end
	local h = F.houses(g, houseCount(n or N))
	return MT.graph(g, 0, 0), h, g, style, reps
end

local function mean(shape, cut, n, styleId)
	local acc = { elong = 0, arms = 0, side = 0, waist = 0, drift = 0, helong = 0, harms = 0, hside = 0, edges = 0 }
	for _, town in ipairs(TOWNS) do
		local m, h, g = grow(shape, town, n, cut, styleId)
		local w = 1 / #TOWNS
		for _, k in ipairs({ "elong", "arms", "side", "waist", "drift" }) do acc[k] = acc[k] + m[k] * w end
		acc.helong, acc.harms, acc.hside = acc.helong + h.elong * w, acc.harms + h.arms * w, acc.hside + h.side * w
		acc.edges = acc.edges + #g.edges * w
	end
	return acc
end

local function text(m)
	return string.format("streets elong=%.2f arms=%.1f side=%.2f waist=%.2f drift=%.2f | houses elong=%.2f arms=%.1f side=%.2f | edges=%.0f",
		m.elong, m.arms, m.side, m.waist, m.drift, m.helong, m.harms, m.hside, m.edges)
end

test("round core, whole town after 10 x 18 edges: each shape reads (streets + house proxy)", function()
	local m = {}
	for _, id in ipairs(SH.IDS) do
		m[id] = mean(id)
		print(string.format("%-8s %s", id, text(m[id])))
	end
	local c = m.compact
	ok(c.elong <= 1.6, "compact stays round: " .. text(c))
	ok(m.linear.elong >= 3, "linear >= 3 on the whole town: " .. text(m.linear))
	ok(m.ridge.elong >= 3, "ridge along its line (flat: as linear): " .. text(m.ridge))
	ok(m.cross.arms >= 3.3, "cross: 4 arms (an X on the 6 spokes): " .. text(m.cross))
	ok(m.fingers.arms >= 3.5, "fingers: several arms: " .. text(m.fingers))
	ok(m.fan.side >= 0.75, "fan one-sided: " .. text(m.fan))
	ok(m.twin.drift >= c.drift + 0.4 and m.twin.side >= 0.75, "twin leans to its second core: " .. text(m.twin))
	ok(m.lens.elong >= 1.7 and m.lens.elong <= 2.6 and m.lens.arms <= 2, "lens an oval: " .. text(m.lens))
	-- houses follow the streets only partly (the game core holds ~60 % of the 630 houses), but the long shapes show
	ok(m.linear.helong >= c.helong + 0.4, "linear houses elongated: " .. text(m.linear))
	ok(m.ridge.helong >= c.helong + 0.3, "ridge houses elongated: " .. text(m.ridge))
	for id, x in pairs(m) do ok(x.edges >= 215, id .. " grows: " .. x.edges) end
end)

test("the old snapshot cut reproduces Showcase v4 (round linear town); the full network fixes it", function()
	local cut = mean("linear", true)
	local full = mean("linear", false)
	print("cut  " .. text(cut))
	print("full " .. text(full))
	-- (2.5 before deep arms, 2026-10-12: strips grow along the arm near the core too, so the cut town gets a little
	-- longer; the full network still runs out much further)
	ok(cut.elong <= 2.8, "with the cut the linear town stays short: " .. text(cut))
	ok(full.elong >= cut.elong + 2, "the arms run out with the whole network: " .. text(full))
end)

test("envelope: no new edge beyond the (widened) envelope; arm tips stay within their arm front", function()
	for _, shape in ipairs({ "linear", "cross", "fingers", "fan", "lens", "twin" }) do
		local _, _, g, style, reps = grow(shape, 7, 8)
		local blk = math.max(style.block.len, style.block.depth)
		for _, r in ipairs(reps) do
			local env = r.rep.envCap
			ok(env ~= nil, shape .. ": envelope known")
			if env then
				local cap = env * (r.rep.envScale or 1) * SEL.ENV_RELAX_F ^ (r.rep.envRelax or 0)
				for _, e in ipairs(r.inc.edges) do
					local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
					local d = SH.distance(style.shape, mx, my, F.flat)
					-- an edge belongs to a piece whose midpoint passed; half a piece of slack (in effective distance)
					ok(d <= cap + 0.75 * blk * 2.5, string.format("%s: edge at de %.0f beyond the envelope %.0f", shape, d, cap))
				end
			end
		end
	end
end)

test("compact towns have no envelope; switching it off restores the old growth", function()
	local _, _, _, _, reps = grow("compact", 7, 3)
	for _, r in ipairs(reps) do eq(r.rep.envCap, nil) end
	SEL.ENVELOPE, SEL.ARM_FRONT = false, false
	local okRun, err = pcall(function()
		local _, _, _, _, r2 = grow("linear", 7, 2)
		for _, r in ipairs(r2) do eq(r.rep.envCap, nil) end
	end)
	SEL.ENVELOPE, SEL.ARM_FRONT = true, true
	assert(okRun, err)
end)

test("cross on 6 spokes is an X of 4 arms (two straight lines); fingers keep one arm per spoke", function()
	for _, town in ipairs({ 1, 7, 13 }) do
		local style = F.style({ forceStyle = "EU_EXTENSION", townId = town, year = 2020, shape = "cross" }, F.flat)
		eq(#style.shape.arms, 4, "4 arms")
		local a = style.shape.arms
		ok(G.angleDiff(a[1], a[3]) > math.rad(175), "arms 1 and 3 opposite")
		ok(G.angleDiff(a[2], a[4]) > math.rad(175), "arms 2 and 4 opposite")
	end
end)

test("houses metrics: ot_metrics.points weighs each building the same", function()
	local strip, round = {}, {}
	for i = -20, 20 do strip[#strip + 1] = { i * 20, (i % 3) * 10 } end
	for k = 1, 40 do round[#round + 1] = { 200 * math.cos(k), 200 * math.sin(k) } end
	ok(MT.points(strip, 0, 0).elong > 5, "a strip of houses is long")
	ok(MT.points(round, 0, 0).elong < 1.3, "a ring of houses is round")
	eq(MT.short(nil), "-")
	ok(MT.short(MT.points(strip, 0, 0)):find("/", 1, true))
end)
