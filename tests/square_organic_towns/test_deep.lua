-- Deep forest towns (2026-10-14; PLAN.md 6.3 "Deep forest towns"): 1-3 towns per map in dense forest (ot_forest
-- deepPick), saved on the frame (`fd`), planned winding (ot_forest.deepStyle: the organic grower's existing knobs),
-- every street near the trees locked, groves inside the town kept, a quarter of the clearing budget, 2 of 3 lanes, no
-- districts / Works / level weights. Synthetic forests only (the in-game read: TESTING.md "Deep forest towns").

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local FO = ug_require(F.DIR .. "ot_forest.lua")
local LN = ug_require(F.DIR .. "ot_lane.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local CK = ug_require(F.DIR .. "ot_check.lua")
local UP = ug_require(F.DIR .. "ot_upward.lua")
local WK = ug_require(F.DIR .. "ot_works.lua")
local DT = ug_require(F.DIR .. "ot_district.lua")

local DENSE = 200
-- groves (wooded islands) in the open ring the town grows into, forest beyond 420 m with three clearings
local GROVES = { { 330, 120, 55 }, { -300, -150, 55 }, { 60, -340, 50 } }
local CLEARINGS = { { 600 * math.cos(math.rad(30)), 600 * math.sin(math.rad(30)), 140 },
	{ 600 * math.cos(math.rad(150)), 600 * math.sin(math.rad(150)), 140 }, { 0, -600, 140 } }
local function deepWood(x, y)
	for _, g in ipairs(GROVES) do
		if (x - g[1]) ^ 2 + (y - g[2]) ^ 2 < g[3] ^ 2 then return DENSE end
	end
	local r2 = x * x + y * y
	if r2 < 420 * 420 then return 0 end
	for _, c in ipairs(CLEARINGS) do
		if (x - c[1]) ^ 2 + (y - c[2]) ^ 2 < c[3] ^ 2 then return 0 end
	end
	return DENSE
end
local function eastForest(x, _y) return x > 150 and DENSE or 0 end

local GRID = FO.fromFunction(0, 0, deepWood, 1200, 50)
local function info(mode, fn)
	local fg = fn and FO.fromFunction(0, 0, fn, 1200, 50) or GRID
	return { grid = fg, mode = mode, share = fg.share }
end

--- The resolved style of a town (deep: resolved again with inputs.deep, as the driver does).
local function styleOf(id, town, deep, year)
	local r = { forceStyle = id, townId = town or 11, year = year or 1920, nameList = "::/names/germany/germany.names",
		pos = { 0, 0 }, capacity = 900 }
	r.terrain = nil
	local inp = I.build(r)
	inp.deep = deep or nil
	return ST.resolve(inp)
end

local function extentOf(g)
	local r = 0
	for _, n in ipairs(g.nodes) do r = math.max(r, G.dist(0, 0, n.x, n.y)) end
	return r
end

--- n increments of 18 edges from a round core (houses after each). mode = "deep" | "hug" | "clear". Returns
--- { segs, incs, g, style, fo, geoBad }.
local function grow(id, mode, n, town)
	local style = styleOf(id, town, mode == "deep")
	local fo = info(mode)
	if mode == "deep" then style.deep = { why = "test" } end
	style.forest = fo
	if FO.active(fo) then fo.budget = FO.budgetFor({}, 1920, 2, 100, mode == "deep" and FO.DEEP.BUDGET_F or nil) end
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local out = { segs = {}, incs = {}, g = g, style = style, fo = fo, geoBad = 0, groveHeld = 0 }
	for k = 1, n do
		fo.frameR = FO.DEEP.FRAME_F * extentOf(g)
		local inc, report = core.planIncrement(g, style, { terrain = F.flat, join = "deadEnd", maxEdges = 18 })
		if #inc.edges == 0 then break end
		local geo = CK.increment(inc, g)
		if CK.badText(geo) ~= "none" then out.geoBad = out.geoBad + 1; out.badWhy = CK.badText(geo) end
		out.groveHeld = out.groveHeld + ((report and report.groveHeld) or 0)
		for _, e in ipairs(inc.edges) do out.segs[#out.segs + 1] = { e.p0[1], e.p0[2], e.p1[1], e.p1[2], key = e.key } end
		out.incs[#out.incs + 1] = inc
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + 70 * k)
	end
	return out
end

local function length(segs)
	local t = 0
	for _, s in ipairs(segs) do t = t + G.dist(s[1], s[2], s[3], s[4]) end
	return t
end

--- Forest cells (cover >= FOREST_COVER) within R of the centre that no new street passes within `clear` m of: kept / all.
local function keptShare(fg, segs, R, clear)
	local tot, kept = 0, 0
	for i = 0, fg.n - 1 do
		for j = 0, fg.n - 1 do
			local x, y = fg.x0 + (i + 0.5) * fg.cell, fg.y0 + (j + 0.5) * fg.cell
			if x * x + y * y <= R * R and (fg.cover[i * fg.n + j + 1] or 0) >= FO.FOREST_COVER then
				tot = tot + 1
				local hit = false
				for _, s in ipairs(segs) do
					if G.pointSegDist(x, y, s[1], s[2], s[3], s[4]) < clear then hit = true break end
				end
				if not hit then kept = kept + 1 end
			end
		end
	end
	return tot > 0 and kept / tot or 1, tot
end

--- Of the new edges with forest within lot depth or just beyond (corridor max >= DEEP.LOCK), the share the forest
--- lock takes (ot_forest.facesForest for the mode's forest info).
local function lockShare(o)
	local adj, locked = 0, 0
	for _, inc in ipairs(o.incs) do
		for _, e in ipairs(inc.edges) do
			if not e.forestLane then
				local co = FO.corridor(o.fo, { e.p0, e.p1 })
				if math.max(co.c, co.l, co.r, co.bl, co.br) >= FO.DEEP.LOCK then
					adj = adj + 1
					if FO.facesForest(o.fo, e.p0, e.p1, false, false) then locked = locked + 1 end
				end
			end
		end
	end
	return adj > 0 and locked / adj or 1, adj
end

local function windOf(o)
	local mx, bends, n = 0, 0, 0
	for _, inc in ipairs(o.incs) do
		local okR, rep = pcall(CK.straightRuns, inc, {})
		local m, b, k = FO.windStats(inc, okR and rep and rep.max or 0)
		mx, bends, n = math.max(mx, m), bends + b, n + k
	end
	return mx, bends, n
end


-- the driver against test_driver's fake engine (copied: test files run in their own sandbox), with a tree reader
local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local TOWN = 100
local US_NAMES = "square_names_us_texas::/names/usa/usa.names"

--- The fake world: nodes 1..13, edges 101..116.
local function world()
	local nodes, edges = {}, {}
	local id = 0
	local at = {}
	local function node(x, y)
		id = id + 1
		nodes[id] = { id = id, x = x, y = y, z = 10, cfg = true }
		at[x .. ":" .. y] = id
		return id
	end
	for _, x in ipairs({ -100, 0, 100 }) do
		for _, y in ipairs({ -100, 0, 100 }) do node(x, y) end
	end
	local eid = 100
	local function edge(a, b, extra)
		eid = eid + 1
		local na, nb = nodes[a], nodes[b]
		local e = { id = eid, n0 = a, n1 = b, p0 = { na.x, na.y, 10 }, p1 = { nb.x, nb.y, 10 },
			t0 = { nb.x - na.x, nb.y - na.y, 0 }, t1 = { nb.x - na.x, nb.y - na.y, 0 }, template = SMALL, lanes = 4,
			objects = 0, owned = false, inConstruction = false, parcels = 10, built = 10 }
		for k, v in pairs(extra or {}) do e[k] = v end
		edges[#edges + 1] = e
		return e
	end
	for _, x in ipairs({ -100, 0, 100 }) do
		edge(at[x .. ":-100"], at[x .. ":0"])
		edge(at[x .. ":0"], at[x .. ":100"])
	end
	for _, y in ipairs({ -100, 0, 100 }) do
		edge(at["-100:" .. y], at["0:" .. y])
		edge(at["0:" .. y], at["100:" .. y])
	end
	local e1 = node(200, 0); edge(at["100:0"], e1)
	local e2 = node(-200, 0); edge(at["-100:0"], e2, { owned = true })
	local e3 = node(0, 200); edge(at["0:100"], e3)
	local e4 = node(0, -200); edge(at["0:-100"], e4)
	nodes[e4].cfg = false
	return { nodes = nodes, edges = edges, deadEnds = { east = e1, west = e2, north = e3, south = e4 } }
end

local function fakeEngine(o)
	o = o or {}
	local W = world()
	local E = { t = 0, logs = {}, events = {}, prechecks = {}, grows = {}, W = W, bal = 5000000 }
	E.precheckOk = o.precheckOk or function() return true end
	function E.nowUs() return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return o.cfg or { nameList = US_NAMES, climate = "::/climates/temperate" } end
		return nil
	end
	-- default: the grid forced (these tests were written for the NA grid; Automatic picks per site, see below)
	function E.modParams() return o.params or { act_on = 3, debug_log = 2, style = 2 }, {} end
	function E.gameTime() return o.gameTime or 10 * SV.FRESH_GAME_TIME end
	function E.year() return o.year or 1970 end
	function E.balance() return E.bal end
	function E.towns() return { TOWN } end
	function E.name(t) return "Testville" .. t end
	function E.boxCentre(_t) return 0, 0 end
	function E.townCaps(_t) return { target = 1000, actual = 900, sizeFactors = { 1, 1, 1 } } end
	function E.town2buildings() return {} end
	function E.townBuildings(_t, _m)
		local pts, builtBy = {}, {}
		for x = -90, 90, 30 do
			for y = -90, 90, 30 do pts[#pts + 1] = { x, y } end
		end
		for _, e in ipairs(W.edges) do builtBy[e.id] = e.built end
		return pts, builtBy
	end
	function E.parcelMap()
		local m = {}
		for _, e in ipairs(W.edges) do if e.parcels then m[e.id] = { n = e.parcels } end end
		return m
	end
	function E.parcelCount(pd) return pd.n end
	function E.closestTown(_x, _y) return TOWN end
	function E.streets(x, y, r)
		if o.streetsError then error("octree exploded") end
		local out = {}
		for _, e in ipairs(W.edges) do
			if F_dist(e.p0, x, y) <= r or F_dist(e.p1, x, y) <= r then out[#out + 1] = e end
		end
		return out
	end
	function E.nodeStreetEdges(n)
		local out = {}
		for _, e in ipairs(W.edges) do if e.n0 == n or e.n1 == n then out[#out + 1] = e.id end end
		return out
	end
	function E.hasConfig(n) return W.nodes[n] ~= nil and W.nodes[n].cfg end
	function E.nodeInConstruction(_n) return false end
	function E.sampler() return F.flat end
	function E.templateExists(_p) return true end
	function E.proposal(spec) return { spec = spec } end
	function E.context() return {} end
	function E.precheck(p, _ctx)
		E.prechecks[#E.prechecks + 1] = p.spec
		local okP = E.precheckOk(p.spec)
		return { ok = okP, msgs = okP and {} or { "Collision" }, collisions = okP and 0 or 3, buildings = 0, cost = 1234,
			us = 1500 }
	end
	function E.sendBuild(p, _ctx, cb)
		E.pending = { spec = p.spec, cb = cb }
	end
	function E.sendEvent(id, name, param) E.events[#E.events + 1] = { id = id, name = name, param = param } end
	function E.growTown(t, f, cb) E.grows[#E.grows + 1] = { town = t, f = f, cb = cb } end
	return E
end

function F_dist(p, x, y) return math.sqrt((p[1] - x) ^ 2 + (p[2] - y) ^ 2) end

--- Ticks the driver every 0.1 s of fake real time until pred() or n ticks.
local function run(d, E, n, saved, pred)
	for _ = 1, n do
		d:tick(E.t, saved)
		E.t = E.t + 100000
		if pred and pred() then return true end
	end
	return false
end

local function logsWith(E, what)
	local out = {}
	for _, l in ipairs(E.logs) do
		if l:find("[SQOT] " .. what, 1, true) then out[#out + 1] = l end
	end
	return out
end

local GERMANY = "::/names/germany/germany.names"
--- A fake tree reader: dense forest (48 trees / ha) beyond 160 m of the town centre.
local function denseReader(E)
	E.forestReader = function(_cx, _cy, _r, o)
		return { stats = { groups = 1, reads = 1, trees = 0, nonTree = 0, stride = 1, capped = false, listUs = 0 },
			step = function(self)
				for x = -1490, 1490, 25 do
					for y = -1490, 1490, 25 do
						if x * x + y * y > 160 * 160 then o.add(x, y, 3); self.stats.trees = self.stats.trees + 3 end
					end
				end
				return true
			end }
	end
end

test("driver: a dense-forest town goes deep at its first plan, saves fd with its frame and stays deep after a reload", function()
	local p0, m0 = FO.DEEP_P, FO.P_MAX
	FO.DEEP_P, FO.P_MAX = 10, 1.01   -- (the draw always says yes here: the pipeline, not the odds)
	local okT, err = pcall(function()
		local E = fakeEngine({ cfg = { nameList = GERMANY, climate = "temperate" }, params = { act_on = 3, debug_log = 2 }, year = 1910 })
		denseReader(E)
		local d = D.new(E)
		ok(run(d, E, 600, nil, function() return E.pending ~= nil end), "a proposal was sent (a town in the woods creeps on)")
		local fl = logsWith(E, "FOREST")
		local deepLine
		for _, l in ipairs(fl) do if l:find("mode=deep why=", 1, true) then deepLine = l end end
		ok(deepLine and deepLine:find("why=ring=", 1, true), tostring(deepLine))
		local st = logsWith(E, "STYLE")[1]
		ok(st and st:find(":deep", 1, true) and st:find("deep=ring=", 1, true), tostring(st))
		local plan = logsWith(E, "PLAN")[1]
		ok(plan and plan:find("forestMode=deep", 1, true) and not plan:find("deepLocks=-", 1, true)
			and plan:find("maxStraight=%d") ~= nil and plan:find("bends=%d") ~= nil, tostring(plan))
		print("      " .. plan:match("forestMode=.-us=") .. " ... " .. (plan:match("deepLocks=.*") or ""))
		E.pending.cb(true, { cost = 300000, msgs = {} })
		run(d, E, 2)
		local fp
		for _, ev in ipairs(E.events) do if ev.name == SV.EV_FRAME then fp = ev.param end end
		ok(fp and fp.fd == 1, "the frame saves fd")
		-- reload: a new driver on the saved state; the draw would now say no (odds back), the frame keeps it deep
		FO.DEEP_P, FO.P_MAX = 0, m0
		local saved = SV.applyFrame(nil, fp)
		local E2 = fakeEngine({ cfg = { nameList = GERMANY, climate = "temperate" }, params = { act_on = 3, debug_log = 2 }, year = 1910 })
		denseReader(E2)
		local d2 = D.new(E2)
		ok(run(d2, E2, 600, saved, function() return E2.pending ~= nil end), "the reloaded town plans again")
		local again
		for _, l in ipairs(logsWith(E2, "FOREST")) do if l:find("mode=deep why=", 1, true) then again = l end end
		ok(again and again:find("why=saved", 1, true), tostring(again))
		ok(logsWith(E2, "PLAN")[1]:find("forestMode=deep", 1, true), "plans as deep")
		-- a town framed without fd never turns deep (the draw back on)
		FO.DEEP_P, FO.P_MAX = 10, 1.01
		local fp0 = {}
		for k, v in pairs(fp) do fp0[k] = v end
		fp0.fd = nil
		local E3 = fakeEngine({ cfg = { nameList = GERMANY, climate = "temperate" }, params = { act_on = 3, debug_log = 2 }, year = 1910 })
		denseReader(E3)
		local d3 = D.new(E3)
		ok(run(d3, E3, 600, SV.applyFrame(nil, fp0), function() return E3.pending ~= nil end))
		ok(not logsWith(E3, "PLAN")[1]:find("forestMode=deep", 1, true), "a framed town without fd stays as it was")
	end)
	FO.DEEP_P, FO.P_MAX = p0, m0
	assert(okT, err)
end)

test("pick: dense-forest towns go deep (seeded, small / early / organic / character), never metro / grid / big / sparse", function()
	local function share(id, year, tier, character, fg)
		local n, deep = 0, 0
		for town = 1, 300 do
			local st = { id = id, year = year, tier = tier, seed = town * 7919, form = character and { character = true } or nil }
			if FO.deepPick(fg or GRID, st, { count = 0 }) then deep = deep + 1 end
			n = n + 1
		end
		return deep / n
	end
	local ring = FO.ringShare(GRID, FO.DEEP_RING[1], FO.DEEP_RING[2])
	local early, late = share("EU_ORGANIC", 1900, 2), share("EU_ORGANIC", 2015, 2)
	local small, big = share("EU_ORGANIC", 1900, 1), share("EU_ORGANIC", 1900, 3)
	local ch = share("EU_ORGANIC", 1960, 2, true)
	local plain = share("EU_ORGANIC", 1960, 2)
	print(string.format("      ring share %.2f; deep share EU 1900 t1 %.2f t2 %.2f t3 %.2f, 2015 %.2f; 1960 %.2f / character %.2f; Nordic %.2f",
		ring, small, early, big, late, plain, ch, share("NORDIC", 1900, 2)))
	ok(ring >= FO.DEEP_SHARE, "the fixture is deep forest: " .. ring)
	ok(early > 0.5 and small >= early, "early small / medium organic towns in deep forest mostly go deep")
	-- (§59: the deep era curve full to 1960, DEEP_ERA_LATE from 2010: a 1995 town still goes deep fairly often)
	ok(late < early * 0.5 and big < early * 0.5, "later and bigger towns less")
	ok(ch > plain, "character towns more")
	eq(share("EU_ORGANIC", 1900, 4), 0, "never tier 4")
	eq(share("NA_GRID", 1900, 2), 0, "never a grid style")
	eq(share("JP_DENSE", 1900, 2), 0)
	eq(select(2, FO.deepPick(GRID, { id = "EU_ORGANIC", tier = 1, year = 1900, metro = { variant = "grid" } })), "metro")
	eq(select(2, FO.deepPick(GRID, { id = "EU_ORGANIC", tier = 1, year = 1900, offshoot = true })), "offshoot")
	-- a half-wooded town (forest east of 150 m): ring share ~0.45 or less, mostly not deep
	local half = FO.fromFunction(0, 0, eastForest, 1200, 50)
	local hr = FO.ringShare(half, FO.DEEP_RING[1], FO.DEEP_RING[2])
	local d, why = FO.deepPick(half, { id = "EU_ORGANIC", tier = 1, year = 1900, seed = 1 })
	print(string.format("      half wooded: ring %.2f -> %s (%s)", hr, tostring(d), why))
	-- (2026-10-14: DEEP_SHARE 0.40 at the lower DEEP_COVER: the half-wooded ring may pass the share, the sector rule
	-- (woods around, DEEP_SECTORS of 8) keeps it a hug town; was hr < DEEP_SHARE)
	ok(not d and why:find("^share") ~= nil, "a half-wooded town is a hug candidate, not deep")
	-- the quota: DEEP_MAX per map
	local st
	for town = 1, 300 do
		st = { id = "EU_ORGANIC", year = 1900, tier = 1, seed = town * 7919 }
		if FO.deepPick(GRID, st, { count = 0 }) then break end
	end
	ok(FO.deepPick(GRID, st, { count = FO.DEEP_MAX - 1 }), "under the quota")
	local q, qWhy = FO.deepPick(GRID, st, { count = FO.DEEP_MAX })
	ok(not q and qWhy:find("^quota") ~= nil, qWhy)
	ok(FO.deepPick(GRID, { id = "NA_GRID", tier = 4 }, { force = true }), "the dev force")
	eq(select(2, FO.deepPick(nil, st)), "noGrid")
	-- forStyle: a deep style is deep whatever the share reads later (streets cleared trees)
	local fo = FO.forStyle(FO.fromFunction(0, 0, function() return 0 end, 1200, 50), { id = "EU_ORGANIC", deep = { why = "saved" } })
	eq(fo.mode, "deep")
	ok(FO.active(fo) and FO.isDeep(fo))
	eq(FO.text(fo):match(":(%a+)$"), "deep")
end)

test("saved: the frame keeps `fd`; a reload stays deep, a frame without it never turns deep", function()
	local style = styleOf("EU_ORGANIC", 11, true)
	style.deep = { why = "test" }
	local fp = SV.frameParam(11, style, nil)
	eq(fp.fd, 1)
	local raw = SV.applyFrame(nil, fp)
	raw = SV.normalize(raw)
	eq(SV.frame(raw, 11).deep, true)
	eq(SV.deepTowns(raw), 1)
	local plain = SV.frameParam(12, styleOf("EU_ORGANIC", 12, false), nil)
	eq(plain.fd, nil)
	raw = SV.applyFrame(raw, plain)
	eq(SV.frame(raw, 12).deep, nil)
	-- the driver: a saved deep frame stays deep whatever the draw / quota say; a frame without fd never; no frame: draw
	local d = D.new({ nowUs = function() return 0 end, name = function(t) return "T" .. t end, log = function() end }, "[T]")
	d.saved = raw
	d.debug = function() end
	local logs = {}
	d.log = function(_, tag, f) logs[#logs + 1] = { tag = tag, f = f } end
	local s11 = d:townState(11)
	s11.forest = GRID
	local st = { id = "NA_GRID", tier = 4, year = 2000, seed = 3 }   -- (the draw alone would say no)
	local deep, why = d:deepFor(11, s11, st, SV.frame(raw, 11), "main", {})
	ok(deep and why == "saved", tostring(why))
	ok(#logs == 1 and logs[1].tag == "FOREST", "FOREST mode=deep logged")
	local s12 = d:townState(12)
	s12.forest = GRID
	deep, why = d:deepFor(12, s12, { id = "EU_ORGANIC", tier = 1, year = 1900, seed = 5 }, SV.frame(raw, 12), "main", {})
	ok(not deep and why == "framed", tostring(why))
	-- the quota counts the saved deep frame and this session's picks
	eq(d:deepCount(12), 1)
	eq(d:deepCount(11), 0, "not itself")
	ok(d:isDeepTown(11) and not d:isDeepTown(12))
	-- dev force
	d:devDeep(12)
	deep, why = d:deepFor(12, s12, { id = "NA_GRID" }, SV.frame(raw, 12), "main", {})
	ok(deep and why == "force", tostring(why))
end)

test("geometry: deep towns resolve curvier, smaller-block, organic all the way out; others unchanged", function()
	local a, b = styleOf("EU_ORGANIC", 11, false), styleOf("EU_ORGANIC", 11, true)
	ok(b.curve > a.curve and b.gridness < a.gridness, "curvier")
	ok(b.block.len < a.block.len and b.block.len >= ST.MIN_BLOCK, "smaller blocks, never below MIN_BLOCK")
	eq(b.outer, nil, "no gridded outer zone")
	ok(b.wiggle and b.curveWave and b.spokeRadius >= 80, "wiggle / wave / spoke radius within LINE_RADIUS")
	eq(a.wiggle, nil)
	local n0, n1 = styleOf("NORDIC", 11, false), styleOf("NORDIC", 11, true)
	ok(n1.cluster.green > n0.cluster.green, "Nordic: more green cells")
end)

-- EU organic and MED hill deep vs hug vs clear in the grove fixture, 4 town seeds x 8 increments
local SEEDS = { 21, 22, 23, 24 }
for _, id in ipairs({ "EU_ORGANIC", "MED_HILL" }) do
	test("plan (" .. id .. "): deep keeps the groves, locks the forest edges, winds (max straight <= 2 blocks), still grows", function()
		local r = {}
		for _, mode in ipairs({ "deep", "hug", "clear" }) do
			local acc = { kept = 0, lock = 0, len = 0, maxS = 0, bends = 0, edges = 0, geoBad = 0, grove = 0, adj = 0 }
			for _, town in ipairs(SEEDS) do
				local o = grow(id, mode, 8, town)
				local R = FO.DEEP.FRAME_F * extentOf(o.g)
				local kept = keptShare(GRID, o.segs, math.min(R, 420), 20)
				local ls, adj = lockShare(o)
				local mx, b, n = windOf(o)
				acc.kept = acc.kept + kept / #SEEDS
				acc.lock = acc.lock + ls / #SEEDS
				acc.adj = acc.adj + adj
				acc.len = acc.len + length(o.segs) / #SEEDS
				acc.maxS = math.max(acc.maxS, mx)
				acc.bends, acc.edges = acc.bends + b, acc.edges + n
				acc.geoBad = acc.geoBad + o.geoBad
				acc.grove = acc.grove + o.groveHeld
				if o.badWhy then acc.badWhy = o.badWhy end
			end
			r[mode] = acc
			print(string.format("      %-5s grove cells kept %.2f | forest-adjacent edges locked %.2f (%d) | length %.0f m | maxStraight %.0f m | bends %d/%d | groveHeld %d | geoBad %d %s",
				mode, acc.kept, acc.lock, acc.adj, acc.len, acc.maxS, acc.bends, acc.edges, acc.grove, acc.geoBad, acc.badWhy or ""))
		end
		local dp, hg = r.deep, r.hug
		-- (MED hill 0.85 since the 44 m minimum block, 2026-10-18: its 30 m lanes floor at the minimum, so its pieces are
		-- longer and fewer fit between the groves; deep 0.95 -> 0.86, hug 0.91 -> 0.68, clear 0.68 -> 0.61)
		ok(dp.kept >= (id == "MED_HILL" and 0.85 or 0.88), "deep keeps the groves inside its frame: " .. dp.kept)
		ok(dp.kept >= hg.kept, "at least as many as a hug town")
		ok(dp.lock >= 0.95 and dp.lock > hg.lock, "deep locks its forest-adjacent edges: " .. dp.lock .. " vs " .. hg.lock)
		-- (two minimum blocks: 80 m until the 44 m minimum, 2026-10-18; a deep town's block depth floors at MIN_BLOCK, so
		-- its lanes, and the straight runs between them, are 10 % farther apart: EU organic 72 -> 88 m)
		ok(dp.maxS <= 2 * ST.MIN_BLOCK, "no straight run over two blocks: " .. dp.maxS)
		eq(dp.geoBad, 0, "geoBad=none in every increment")
		ok(dp.len >= 0.35 * r.clear.len, "the deep town still grows: " .. dp.len .. " vs clear " .. r.clear.len)
	end)
end

test("lanes / budget / locks / gates: 2 of 3 lanes, a quarter of the budget, held lots dearer, near streets locked, no offshoots or levels", function()
	-- lanes: the chance and the cap; seeded over a street across a forest belt (test_lane's fixture): ~2 of 3
	local function belt(x, _y) return (x >= 200 and x <= 500) and DENSE or 0 end
	local beltFo = { deep = info("deep", belt), hug = info("hug", belt) }
	local function streetInc()
		local inc = { edges = {}, nodes = {} }
		for k = 0, 6 do
			inc.edges[#inc.edges + 1] = { entity = -(100 + k), node0 = k == 0 and 5 or -(k + 1), node1 = -(k + 2),
				p0 = { k * 100, 0, 0 }, p1 = { (k + 1) * 100, 0, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 }, class = "small",
				street = 1, key = "s1" }
		end
		return inc
	end
	local shares = {}
	for _, mode in ipairs({ "deep", "hug" }) do
		local n = 0
		for seed = 1, 300 do
			if #LN.mark(streetInc(), { forest = beltFo[mode], seed = seed, year = 1960 }, { seed = seed }) > 0 then n = n + 1 end
		end
		shares[mode] = n / 300
	end
	print(string.format("      lanes per eligible crossing (1960): deep %.2f, hug %.2f", shares.deep, shares.hug))
	ok(shares.deep > 0.55 and shares.deep < 0.8, "deep: about 2 of 3")
	ok(shares.deep > shares.hug)
	local deep = { forest = info("deep"), year = 1990 }
	near(LN.chance(deep), LN.DEEP_P, 1e-9, "2 of 3 whatever the era")
	eq(LN.maxFor(deep, LN.MAX_PER_TOWN), LN.DEEP_MAX_PER_TOWN)
	eq(LN.maxFor({ forest = info("hug") }, LN.MAX_PER_TOWN), LN.MAX_PER_TOWN)
	-- budget: a quarter
	local b = FO.budgetFor({}, 1900, 2, 100, FO.DEEP.BUDGET_F)
	near(b.total, FO.BUDGET_HA[2] * FO.DEEP.BUDGET_F, 1e-9)
	-- held lots spend more
	local e = info("deep", eastForest)
	local co = FO.corridor(e, { { 500, -100 }, { 500, 100 } })
	near(FO.lotSpend(e, co), co.lotHa * FO.DEEP.SPEND_F, 1e-9)
	near(FO.lotSpend(info("hug", eastForest), co), co.lotHa, 1e-9)
	-- locks: a street 60 m off the forest edge (x = 90, forest from 150): open lots, forest just beyond -> deep locks it
	-- ("near"), hug only when the beyond band reaches FACE_LOCK
	local hug = info("hug", eastForest)
	local face, why = FO.facesForest(e, { 60, -100 }, { 60, 100 })
	print(string.format("      x=60: deep %s (%s), hug %s", tostring(face), tostring(why), tostring((FO.facesForest(hug, { 60, -100 }, { 60, 100 })))))
	ok(face, "deep: a street within ~60-90 m of the trees is locked")
	ok(not FO.facesForest(e, { -300, -100 }, { -300, 100 }), "open land stays unlocked")
	-- the driver's lock keys count near streets
	local inc = { edges = {
		{ key = "a#1", node0 = 5, node1 = -1, p0 = { 60, -100 }, p1 = { 60, 0 } },
		{ key = "b#1", node0 = 6, node1 = -3, p0 = { -300, 0 }, p1 = { -200, 0 } } } }
	local job = { inc = inc, style = { forest = e } }
	local keys = D.lockKeys(job)
	ok(keys and keys["a#1"] and not keys["b#1"])
	eq(D.deepLockText(inc, { forest = e }), "1/2")
	eq(D.deepLockText(inc, { forest = hug }), "-")
	-- districts / Works / level weights
	local okD, whyD = DT.eligible({ fresh = true, buildings = 5000, seed = 1, deep = true, quotaLeft = true })
	ok(not okD and whyD == "deep", tostring(whyD))
	local okW, whyW = WK.eligible({ fresh = true, buildings = 5000, seed = 1, deep = true, quotaLeft = true })
	ok(not okW and whyW == "deep", tostring(whyW))
	local act, _, whyL = UP.levelDecide({ on = true, buildings = 900, pb = 2, mat = 1, ours = 0, deep = true })
	ok(act == nil and whyL == "deep", tostring(whyL))
	act = UP.levelDecide({ on = true, buildings = 900, pb = 2, mat = 1, ours = 0.5, deep = true })
	eq(act, "clear", "weights of ours sent before are cleared")
end)
