-- Deep arms (Showcase v5, 2026-10-12): shaped towns' arms reached out but read as ladders / fishbones (one spine,
-- short dead-end stubs every block on both sides). Real ribbon villages have a main street plus back lanes parallel
-- to it, joined at intervals into closed blocks. Measured from a round vanilla-like core (F.roundCore) as in
-- test_envelope, 10 and 20 increments of 18 edges, on our own edges in the arm corridors (ot_metrics.ladder):
-- ladder share (rungs: dead-end stubs shorter than a block running across the arm / arm streets), depth (rows of
-- parallel streets beside the spine, in blocks), closed blocks; whole-town metrics alongside. "before" = the same run
-- with the deep-arms switches off (the Shapes round state). In these towns the old arms were mostly U-shaped combs
-- (separate one-block U's off the spine) rather than open stubs, so the gain shows most in depth and blocks.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")

local TOWNS = { 1, 7, 13, 21 }
local MAXE = 18
local SHAPES = { "linear", "ridge", "cross", "fingers" }

local SH = ug_require(F.DIR .. "ot_shape.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local ORG = ug_require(F.DIR .. "ot_grow_organic.lua")

local function ours(e) return e.increment ~= nil end

--- Runs fn with the deep-arms changes off (the Shapes round state: arms off the spokes, narrow corridors, no back
--- rows, no strip cost, no line tips); restores them after.
local function before(fn)
	local saved = { SH.SPOKE_SNAP, SH.STRIP_BAND, ORG.DEEP_ARMS, SEL.STRIP, SEL.ARM_TIPS }
	SH.SPOKE_SNAP, SH.STRIP_BAND, ORG.DEEP_ARMS, SEL.STRIP, SEL.ARM_TIPS = false, 0.6, false, false, false
	local okRun, err = pcall(fn)
	SH.SPOKE_SNAP, SH.STRIP_BAND, ORG.DEEP_ARMS, SEL.STRIP, SEL.ARM_TIPS = saved[1], saved[2], saved[3], saved[4], saved[5]
	assert(okRun, err)
end

--- Grows one town from a round core; returns { [k] = { ladder, metrics, houses } } at the steps in `at`.
local function grow(styleId, shape, town, at)
	-- (the plan axis from the core's streets, as the driver passes it: a seeded axis would put the arms on the
	-- spokes in both versions)
	local style, stats = F.style({ forceStyle = styleId, townId = town, year = 2020, shape = shape,
		axis = { angle = 0.3 * town, strength = 1 } }, F.flat)
	local g = F.roundCore(OG.new(), { angle = 0.3 * town })
	local out, last = {}, at[#at]
	for k = 1, last do
		local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = MAXE })
		if #inc.edges == 0 then break end
		OG.apply(g, inc, k)
		for _, s in ipairs(at) do
			if s == k then
				out[k] = { l = MT.ladder(g, style.shape, style.block, ours), m = MT.graph(g, 0, 0),
					h = F.houses(g, 180 + 45 * k), edges = #g.edges }
			end
		end
	end
	out.zigzags, out.lassos = MT.zigzags(g, ours), MT.lassos(g)
	return out, style
end

local cache = {}
--- Mean over TOWNS at steps 10 and 20 for a style / shape (cached per file run).
local function mean(styleId, shape, old)
	local key = styleId .. ":" .. shape .. (old and ":old" or "")
	if cache[key] then return cache[key] end
	local acc = {}
	for _, k in ipairs({ 10, 20 }) do
		acc[k] = { share = 0, depth = 0, blocks = 0, stubs = 0, segs = 0, elong = 0, arms = 0, side = 0, helong = 0, edges = 0 }
	end
	acc.zigzags, acc.lassos = 0, 0
	for _, town in ipairs(TOWNS) do
		local r
		if old then before(function() r = grow(styleId, shape, town, { 10, 20 }) end)
		else r = grow(styleId, shape, town, { 10, 20 }) end
		local w = 1 / #TOWNS
		for _, k in ipairs({ 10, 20 }) do
			local x, a = r[k], acc[k]
			if x then
				local l = x.l or { share = 0, depth = 0, blocks = 0, stubs = 0, segs = 0 }
				a.share, a.depth, a.blocks = a.share + l.share * w, a.depth + l.depth * w, a.blocks + l.blocks * w
				a.stubs, a.segs = a.stubs + l.stubs * w, a.segs + l.segs * w
				a.elong, a.arms, a.side = a.elong + x.m.elong * w, a.arms + x.m.arms * w, a.side + x.m.side * w
				a.helong, a.edges = a.helong + x.h.elong * w, a.edges + x.edges * w
			end
		end
		acc.zigzags, acc.lassos = acc.zigzags + r.zigzags, acc.lassos + r.lassos
	end
	cache[key] = acc
	return acc
end

local function row(styleId, shape, k, a)
	return string.format("%-12s %-8s %2d: ladder=%.2f (%.1f/%.1f) depth=%.2f blocks=%.1f | elong=%.2f arms=%.1f side=%.2f houses=%.2f edges=%.0f",
		styleId, shape, k, a.share, a.stubs, a.segs, a.depth, a.blocks, a.elong, a.arms, a.side, a.helong, a.edges)
end

local function report(styleId)
	local m = {}
	for _, shape in ipairs(SHAPES) do
		local o, n = mean(styleId, shape, true), mean(styleId, shape)
		m[shape] = { old = o, new = n }
		for _, k in ipairs({ 10, 20 }) do
			print("before " .. row(styleId, shape, k, o[k]))
			print("after  " .. row(styleId, shape, k, n[k]))
		end
		print(string.format("   zigzags / lassos (4 towns, 20 steps): before %d / %d, after %d / %d", o.zigzags, o.lassos,
			n.zigzags, n.lassos))
	end
	return m
end

test("arms grow as strips with back streets (EU extension 2020): ladder share, depth, closed blocks", function()
	local m = report("EU_EXTENSION")
	for _, shape in ipairs(SHAPES) do
		local o, n = m[shape].old, m[shape].new
		for _, k in ipairs({ 10, 20 }) do
			local tag = shape .. " " .. k .. ": " .. row("EU_EXTENSION", shape, k, n[k])
			ok(n[k].share <= 0.5 * o[k].share + 0.02, "ladder share halved: " .. tag)
			-- (fingers: six arms share the increments, and their narrow corridors take the second row late)
			local minDepth = shape == "fingers" and 1.4 or 1.8
			ok(n[k].depth >= minDepth and n[k].depth <= 3.6, "strips 2-3 blocks deep: " .. tag)
			ok(n[k].blocks >= o[k].blocks, "no fewer closed blocks: " .. tag)
			ok(n[k].edges >= 0.95 * o[k].edges, "grows as much: " .. tag)
		end
		ok(n.zigzags == 0, shape .. ": no zig-zags")
		ok(n.lassos <= o.lassos, shape .. ": no more lassos")
	end
	-- the whole-town shapes hold (test_envelope's goals)
	ok(m.linear.new[10].elong >= 4, "linear long")
	ok(m.ridge.new[10].elong >= 3.5, "ridge long")
	ok(m.cross.new[10].arms >= 3.5, "cross 4 arms")
	ok(m.fingers.new[10].arms >= 3.5, "fingers several arms")
end)

test("arms in EU organic and NA grid (report)", function()
	for _, styleId in ipairs({ "EU_ORGANIC", "NA_GRID" }) do report(styleId) end
end)

test("ot_metrics.ladder: a fishbone is all stubs, a strip with back lanes has none and is deeper", function()
	local shape = { id = "linear", arms = { 0, math.pi }, centre = { 0, 0 } }
	local blk = { len = 100, depth = 80 }
	-- fishbone: spine along x from 200 to 1000, a 50 m stub every 100 m on both sides
	local fish = OG.new()
	local prev = OG.addNode(fish, nil, 200, 0, 0)
	for x = 300, 1000, 100 do
		local n = OG.addNode(fish, nil, x, 0, 0)
		OG.addEdge(fish, nil, prev.id, n.id, "small")
		for _, s in ipairs({ -50, 50 }) do
			local t = OG.addNode(fish, nil, x, s, 0)
			OG.addEdge(fish, nil, n.id, t.id, "small")
		end
		prev = n
	end
	local lf = MT.ladder(fish, shape, blk)
	ok(lf.share > 0.6, "fishbone ladder share " .. lf.share)
	eq(lf.blocks, 0)
	-- strip: spine + back lanes at +-80 m joined every 100 m
	local strip = OG.new()
	local ids = {}
	for r, y in ipairs({ -80, 0, 80 }) do
		ids[r] = {}
		for i, x in ipairs({ 200, 300, 400, 500, 600, 700, 800, 900, 1000 }) do
			ids[r][i] = OG.addNode(strip, nil, x, y, 0).id
			if i > 1 then OG.addEdge(strip, nil, ids[r][i - 1], ids[r][i], "small") end
			if r > 1 then OG.addEdge(strip, nil, ids[r - 1][i], ids[r][i], "small") end
		end
	end
	local ls = MT.ladder(strip, shape, blk)
	eq(ls.stubs, 0)
	ok(ls.depth >= 1.9, "strip depth " .. ls.depth)
	ok(lf.depth < 0.1, "fishbone depth " .. lf.depth)
	ok(ls.blocks >= 14, "closed blocks " .. ls.blocks)
	eq(MT.ladder(strip, { id = "compact", centre = { 0, 0 } }, blk), nil)
	ok(MT.ladderText(ls):find("ladder=", 1, true))
end)

test("young towns: a 3 x 3 core with two dead ends always plans something (relaxed connectors when empty)", function()
	-- (dev showcase fake town, 2026-10-12: its centre's streets are not joinable and no plan junction lay within
	-- joinR of either dead end at <= CONN_TURN, so every increment came out empty; with or without deep arms)
	local function tiny()
		local g = OG.new()
		local at = {}
		for _, dx in ipairs({ -100, 0, 100 }) do
			for _, dy in ipairs({ -100, 0, 100 }) do at[dx .. ":" .. dy] = OG.addNode(g, nil, dx, dy, 20).id end
		end
		for _, d in ipairs({ -100, 0, 100 }) do
			OG.addEdge(g, nil, at[d .. ":-100"], at[d .. ":0"], "small"); OG.addEdge(g, nil, at[d .. ":0"], at[d .. ":100"], "small")
			OG.addEdge(g, nil, at["-100:" .. d], at["0:" .. d], "small"); OG.addEdge(g, nil, at["0:" .. d], at["100:" .. d], "small")
		end
		OG.addEdge(g, nil, at["100:0"], OG.addNode(g, nil, 200, 0, 20).id, "small")
		OG.addEdge(g, nil, at["0:100"], OG.addNode(g, nil, 0, 200, 20).id, "small")
		return g
	end
	local CASES = { { "EU_EXTENSION", "linear" }, { "EU_EXTENSION", "cross" }, { "EU_ORGANIC", "lens" },
		{ "EU_ORGANIC", "linear" }, { "MED_HILL", "linear" } }
	local function empties()
		local n = {}
		for _, case in ipairs(CASES) do
			local key = case[1] .. " " .. case[2]
			n[key] = 0
			for town = 1, 30 do
				local style, stats = F.style({ forceStyle = case[1], townId = town, year = 1970, shape = case[2], capacity = 400,
					axis = { angle = 0, strength = 1 } }, F.flat)
				local inc = core.planIncrement(tiny(), style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
				if #inc.edges == 0 then n[key] = n[key] + 1 end
			end
		end
		return n
	end
	local function strictly(fn)
		local r, t, m0 = SEL.CONN_RELAX_R, SEL.CONN_RELAX_TURN, SEL.CONN_RELAX_MIN
		SEL.CONN_RELAX_R, SEL.CONN_RELAX_TURN, SEL.CONN_RELAX_MIN = 1, SEL.CONN_TURN, 0
		local okRun, res = pcall(fn)
		SEL.CONN_RELAX_R, SEL.CONN_RELAX_TURN, SEL.CONN_RELAX_MIN = r, t, m0
		assert(okRun, res)
		return res
	end
	local now = empties()
	local strict = strictly(empties)
	local old
	before(function() old = strictly(empties) end)
	for _, case in ipairs(CASES) do
		local key = case[1] .. " " .. case[2]
		print(string.format("%-20s empty first plans of 30: now %d, strict connectors %d, before deep arms (strict) %d", key,
			now[key], strict[key], old[key]))
		-- (MED hill: its 40 m plan pieces at a 100 m grid core are refused by the planner (curve / angle at the dead
		-- ends); open, as before deep arms)
		if case[1] ~= "MED_HILL" then eq(now[key], 0, key .. ": every young town plans") end
	end
end)
