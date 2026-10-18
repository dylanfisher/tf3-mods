-- Gaps between towns (round R3, 2026-10-13; ot_gap): new streets stop 150-300 m short of the halfway line to a
-- neighbour's centre; twins' main roads go on to the line; nothing past it or on another town's land.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local GP = ug_require(F.DIR .. "ot_gap.lua")

test("build / held: the gap line, twins' main roads, owner, bad points", function()
	local gp = GP.build({ 0, 0 }, { { dist = 2000, dir = 0, town = 9 } }, 5)
	eq(#gp.list, 1)
	local nb = gp.list[1]
	ok(nb.gap >= GP.GAP_MIN and nb.gap <= GP.GAP_MAX, "gap " .. nb.gap)
	eq(nb.twin, false)
	eq(GP.held(gp, { { 0, 0 }, { 500, 0 } }, "small"), nil, "well inside")
	eq(GP.held(gp, { { 0, 0 }, { 1000 - nb.gap + 5, 0 } }, "main"), "gap", "in the gap")
	eq(GP.held(gp, { { 1010, 0 } }, "main"), "half", "past the halfway line")
	eq(GP.held(gp, { { 900, 2000 } }, "small"), "gap", "the line is a line, not a disc")
	eq(GP.held(gp, { { 0 / 0, 0 } }, "small"), "bad")
	-- symmetric per pair
	local other = GP.build({ 2000, 0 }, { { dist = 2000, dir = math.pi, town = 5 } }, 9)
	near(other.list[1].gap, nb.gap, 1e-9, "same gap seen from both towns")
	-- twins: main / medium go on to the line, small streets keep the gap
	local tw = GP.build({ 0, 0 }, { { dist = 1200, dir = 0, town = 9 } }, 5)
	ok(tw.list[1].twin)
	local p = { { 0, 0 }, { 590, 0 } }
	eq(GP.held(tw, p, "main"), nil, "twin main road")
	eq(GP.held(tw, p, "small"), "gap")
	eq(GP.held(tw, { { 610, 0 } }, "main"), "half")
	-- owner: the engine gives (x > 300) to another town
	local ow = GP.build({ 0, 0 }, { { dist = 2000, dir = 0, town = 9 } }, 5, { owner = function(x) return x < 300 end })
	eq(GP.held(ow, { { 200, 0 } }, "small"), nil)
	ok(GP.held(ow, { { 700, 0 } }, "small") == "owner" or 700 > 1000 - ow.list[1].gap - GP.OWNER_BAND, "owner near the line")
	eq(GP.build({ 0, 0 }, {}, 1), nil)
	eq(GP.build({ 0, 0 }, { { dist = 9000, dir = 0, town = 2 } }, 1), nil, "far neighbours ignored")
	ok(GP.text(gp):find("^1:1000%-"))
	eq(GP.text(nil), "-")
end)

--- n increments of 18 edges from a round core, a neighbour 900 m east (twin unless twinNear 0). Returns the new streets.
local function grow(styleId, n, twinNear)
	local r = { forceStyle = styleId, townId = 11, year = 1960, nameList = "::/names/germany/germany.names" }
	local style, stats = F.style(r, F.flat)
	style.gaps = twinNear ~= false and GP.build({ 0, 0 }, { { dist = 900, dir = 0, town = 12 } }, 11, { twinNear = twinNear }) or nil
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local out, held = {}, 0
	for k = 1, n do
		local inc, report = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
		held = math.max(held, report and report.gapHeld or 0)
		if #inc.edges == 0 then break end
		for _, e in ipairs(inc.edges) do out[#out + 1] = { e.p0, e.p1, class = e.class } end
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + 70 * k)
	end
	return out, style.gaps, held
end

for _, id in ipairs({ "EU_ORGANIC", "NA_GRID" }) do
	test("planner (" .. id .. "): no new street in the gap toward a neighbour 900 m east; it grows elsewhere", function()
		local segs, gp, held = grow(id, 10, 0)
		local line = 450 - gp.list[1].gap
		local east, west = 0, 0
		for _, s in ipairs(segs) do
			for _, p in ipairs({ s[1], s[2] }) do
				ok(p[1] <= line + 1, "inside the gap line: " .. p[1] .. " <= " .. line)
				if p[1] > 150 then east = east + 1 elseif p[1] < -150 then west = west + 1 end
			end
		end
		local base = grow(id, 10, false)
		print(string.format("      %s: %d edges (no neighbour %d), line %.0f m, east %d / west %d points, gapHeld %d", id, #segs, #base,
			line, east, west, held))
		ok(#segs >= 0.4 * #base, "the town still grows: " .. #segs .. " vs " .. #base)
		ok(held > 0, "pieces held")
	end)
end

test("planner: twins meet along their main road only (small streets keep the gap)", function()
	local segs, gp = grow("EU_ORGANIC", 10, nil)
	local line = 450 - gp.list[1].gap
	for _, s in ipairs(segs) do
		for _, p in ipairs({ s[1], s[2] }) do
			ok(p[1] <= 451, "never past the halfway line")
			if p[1] > line + 1 then ok(s.class == "main" or s.class == "medium", "only main roads in the gap: " .. tostring(s.class)) end
		end
	end
end)

-- R4 (2026-10-13): no empty loops in organic styles (ot_select EMPTY_LOOP)
test("R4 empty loops: an organic town whose houses lag holds loop-closing pieces far from houses; grids unaffected", function()
	local SEL = ug_require(F.DIR .. "ot_select.lua")
	local function run(styleId, on)
		local saved = SEL.EMPTY_LOOP
		SEL.EMPTY_LOOP = on
		local r = { forceStyle = styleId, townId = 13, year = 1960, nameList = "::/names/germany/germany.names" }
		local style, stats = F.style(r, F.flat)
		local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
		F.markBuilt(g, 100)   -- houses on the old core only: they never follow
		local held, edges = 0, 0
		for k = 1, 5 do
			local inc, report = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
			held = held + (report and report.emptyLoopHeld or 0)
			edges = edges + #inc.edges
			if #inc.edges == 0 then break end
			OG.apply(g, inc, k)
		end
		SEL.EMPTY_LOOP = saved
		return held, edges
	end
	local hOn, eOn = run("EU_ORGANIC", true)
	local hOff, eOff = run("EU_ORGANIC", false)
	print(string.format("      EU organic, houses lagging: emptyLoopHeld %d (edges %d; rule off %d / %d)", hOn, eOn, hOff, eOff))
	ok(hOn > 0, "loop pieces held")
	eq(hOff, 0)
	local hGrid = run("NA_GRID", true)
	eq(hGrid, 0, "grids close blocks as before")
end)
