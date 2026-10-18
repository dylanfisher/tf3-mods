-- Look rules (ot_select, showcase v2 screenshots 2026-10-11): no zig-zag chains (three corners in a row
-- turning alternately left / right at nodes with two streets) and no loops hanging off the town by a stem
-- (lassos).
-- Grown as in game: from a vanilla town core, joining at dead ends only.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")

local TOWNS = { 1, 7, 13 }
local N = 12

local function grow(id, guards, sampler)
	sampler = sampler or F.flat
	SEL.ZIGZAG, SEL.LOOP_GUARD, core.LOOK_CHECK = guards, guards, guards
	local acc = { zig = 0, lasso = 0, edges = 0, comps = 0 }
	local okRun, err = pcall(function()
		for _, town in ipairs(TOWNS) do
			local style, stats = F.style({ forceStyle = id, keepOuter = true, townId = town, year = 1960 }, sampler)
			local g = F.vanillaTown(OG.new(), { angle = math.rad(7 * town) })
			for k = 1, N do
				local inc = core.planIncrement(g, style, { terrain = sampler, stats = stats, join = "deadEnd" })
				if #inc.edges == 0 then break end
				OG.apply(g, inc, k)
			end
			acc.zig = acc.zig + MT.zigzags(g)
			acc.lasso = acc.lasso + MT.lassos(g, SEL.HUG * math.max(style.block.len, style.block.depth))
			acc.edges = acc.edges + #g.edges
			acc.comps = math.max(acc.comps, F.components(g))
		end
	end)
	SEL.ZIGZAG, SEL.LOOP_GUARD, core.LOOK_CHECK = true, true, true
	assert(okRun, err)
	return acc
end

test("metrics: zig-zags and lassos of hand-made networks", function()
	local g = OG.new()
	-- an S: (0,0)-(100,0)-(100,100)-(200,100): corners left then right: allowed
	for i, p in ipairs({ { 0, 0 }, { 100, 0 }, { 100, 100 }, { 200, 100 }, { 200, 200 } }) do OG.addNode(g, i, p[1], p[2], 0) end
	OG.addEdge(g, 11, 1, 2); OG.addEdge(g, 12, 2, 3); OG.addEdge(g, 13, 3, 4)
	eq(MT.zigzags(g), 0, "a single S")
	-- one more step up: a staircase of three alternating corners
	OG.addEdge(g, 14, 4, 5)
	eq(MT.zigzags(g), 1, "a zig-zag chain")
	-- a U (both corners the same way) is not a zig-zag
	local u = OG.new()
	for i, p in ipairs({ { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 } }) do OG.addNode(u, i, p[1], p[2], 0) end
	OG.addEdge(u, 11, 1, 2); OG.addEdge(u, 12, 2, 3); OG.addEdge(u, 13, 3, 4)
	eq(MT.zigzags(u), 0)
	-- core square with a stem to a small loop
	local l = OG.new()
	local pts = { { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 }, { 300, 0 }, { 400, 0 }, { 400, 80 }, { 320, 80 }, { 200, 0 } }
	for i, p in ipairs(pts) do OG.addNode(l, i, p[1], p[2], 0) end
	OG.addEdge(l, 21, 1, 2); OG.addEdge(l, 22, 2, 3); OG.addEdge(l, 23, 3, 4); OG.addEdge(l, 24, 4, 1)
	OG.addEdge(l, 25, 2, 9); OG.addEdge(l, 30, 9, 5)   -- a stem of two edges
	OG.addEdge(l, 26, 5, 6); OG.addEdge(l, 27, 6, 7); OG.addEdge(l, 28, 7, 8); OG.addEdge(l, 29, 8, 5)
	local n, big = MT.lassos(l)
	eq(n, 1, "a loop 200 m out on a stem")
	eq(big, 4)
	eq((MT.lassos(l, 250)), 0, "within 250 m it hugs the town")
	local short = OG.new()
	for i, p in ipairs({ { 0, 0 }, { 100, 0 }, { 100, 100 }, { 0, 100 }, { 300, 0 }, { 400, 0 }, { 400, 80 }, { 320, 80 } }) do
		OG.addNode(short, i, p[1], p[2], 0)
	end
	OG.addEdge(short, 21, 1, 2); OG.addEdge(short, 22, 2, 3); OG.addEdge(short, 23, 3, 4); OG.addEdge(short, 24, 4, 1)
	OG.addEdge(short, 25, 2, 5)
	OG.addEdge(short, 26, 5, 6); OG.addEdge(short, 27, 6, 7); OG.addEdge(short, 28, 7, 8); OG.addEdge(short, 29, 8, 5)
	eq((MT.lassos(short)), 0, "a loop right at the end of a dead-end street (one stem edge) is a block patch")
	local st = OG.structure(l)
	eq(st.bridges[25], true)
	eq(st.gateway[6], 2, "the loop hangs from core node 2")
	eq(st.gateway[3], 3)
end)

for _, id in ipairs({ "NA_GRID", "NA_SUBURB", "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "JP_DENSE", "NORDIC" }) do
	test("look " .. id .. ": no zig-zags or lassos with the rules on (vs off)", function()
		local off, on = grow(id, false), grow(id, true)
		print(string.format("%s off: zig=%d lasso=%d edges=%d | on: zig=%d lasso=%d edges=%d", id, off.zig, off.lasso, off.edges,
			on.zig, on.lasso, on.edges))
		eq(on.zig, 0, "no zig-zags")
		ok(on.lasso <= 1, "at most one lasso in " .. #TOWNS .. " towns (off: " .. off.lasso .. ")")
		ok(on.edges >= off.edges * 0.85, "growth not much smaller: " .. on.edges .. " vs " .. off.edges)
		eq(on.comps, 1, "one network")
	end)
end
