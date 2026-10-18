-- The roundabout town's ring hubs (ot_ring §57, 2026-10-14; NEXT_PHASE_BRIEF 57): the town makes its own ring sites on
-- its new streets (a continuation node or a long edge's middle, 1-2 new arms across), at 250-450 m from every other
-- ring, sized by the street (l gateway, m main, s medium, s / mini small), in organic and grid towns alike; their twins
-- reserved and placed by later plans; every ring one-way, every new node configured, no live junction touched.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local CH = ug_require(F.DIR .. "ot_character.lua")
local RG = ug_require(F.DIR .. "ot_ring.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local RB_DIR = here .. "../../mods/square_roundabouts/content"
local cache = {}
local function req(path)
	if cache[path] ~= nil then return cache[path] end
	local mod, rel = path:match("^([%w_]+)::(/.*)$")
	if mod ~= "square_roundabouts" then return ug_require(path) end
	local env = setmetatable({ ug_require = req }, { __index = _ENV })
	local m = assert(loadfile(RB_DIR .. rel, "t", env))()
	cache[path] = m
	return m
end
local GEO = assert(RG.load(req))
local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local MEDIUM = "::/infrastructure/street/town/town_new_medium.street_template"
local LARGE = "::/infrastructure/street/town/town_new_large.street_template"
local FULL = os.getenv("TEST_FULL") ~= nil

local function infoFor(inc)
	local nodes = {}
	for _, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n > 0 then nodes[n] = { hasConfig = true, edges = { 9000 + n }, lanes = 4, src = 9000 + n, template = SMALL } end
		end
	end
	return { nodes = nodes, sources = { [SMALL] = 77, [MEDIUM] = 78, [LARGE] = 79 }, fallback = 77 }
end

local function joinsOf(inc)
	local s = {}
	for _, e in ipairs(inc.edges) do
		if e.node0 > 0 then s[e.node0] = true end
		if e.node1 > 0 then s[e.node1] = true end
	end
	return s
end

--- One-way CCW rings, the plain plan's joins kept (no live junction touched), a config on every new node, no -0.
local function checkInc(inc, joinsBefore, g)
	for _, e in ipairs(inc.edges) do
		-- (a dead-end hub's stem joins a dead end of the graph: the planner's own kind of join, never a junction)
		local function joinOk(n)
			if joinsBefore[n] then return true end
			return e.hubArm and g ~= nil and OG.degree(g, n) == 1
		end
		if e.node0 > 0 then ok(joinOk(e.node0), "join kept") end
		if e.node1 > 0 then ok(joinOk(e.node1), "join kept") end
		if e.ring then
			ok(e.node0 < 0 and e.node1 < 0, "ring nodes are new")
			ok(e.oneway == true and e.template == RG.ONEWAY, "one-way")
		end
		-- (hub arms on new nodes; a dead-end hub's stem starts at its dead end)
		if e.hubArm then ok((e.node0 < 0 or OG.degree(g, e.node0) == 1) and e.node1 < 0, "hub arms on new nodes") end
	end
	for _, r in ipairs(inc.rings or {}) do
		for _, e in ipairs(inc.edges) do
			if e.ring and G.dist(e.p0[1], e.p0[2], r.centre[1], r.centre[2]) < r.R * 1.2 then
				local rx, ry = e.p0[1] - r.centre[1], e.p0[2] - r.centre[2]
				ok(rx * e.t0[2] - ry * e.t0[1] > 0, "counter-clockwise")
			end
		end
	end
	local spec, err = PR.build(inc, infoFor(inc))
	ok(spec ~= nil, tostring(err))
	if spec == nil then return end
	local cfg = {}
	for _, c in ipairs(spec.cfgAdd) do cfg[c.node] = c end
	for _, nd in ipairs(inc.nodes) do ok(cfg[nd.entity] ~= nil, "config on new node " .. nd.entity) end
	ok(PR.noNegativeZero(spec), "no -0")
end

local function townStyle(list, id, year, kind)
	local r = { townId = id or 11, year = year or 1975, nameList = list, pos = { 0, 0 }, capacity = 900 }
	r.terrain = T.stats(F.flat, 0, 0, 600, 24)
	local inp = I.build(r)
	inp.wide = T.wide(F.flat, 0, 0, 2000)
	kind = kind or "roundabout_town"
	inp.charKind, inp.charForm, inp.charMotifs = kind, CH.formFor(kind), CH.motifsFor(kind)
	inp.charSite = { region = inp.region }
	inp.autoStyle = true
	return ST.resolve(inp)
end

--- n forced plans of a town (the showcase: increments regardless of demand), the houses filling `fill` lots a plan, the
--- driver's ring call (share, templates, height, a deferred pair carried and counted down). Returns counts.
local function run(st, n, fill, maxEdges)
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local share = RG.townShare(st.rings)
	local out = { rings = 0, hubs = 0, sizes = {}, pairs = 0, reserved = 0, plans = 0, gates = 0, why = {} }
	local pend = nil
	for k = 1, n do
		local inc = core.planIncrement(g, st, { terrain = F.flat, join = "deadEnd", maxEdges = maxEdges or 14 })
		if #inc.edges == 0 then break end
		out.plans = out.plans + 1
		local before = joinsOf(inc)
		local hidx = SEL.housedIndexM(g, RG.ARM_LEAD)
		local res = RG.mark(inc, { geo = GEO, g = g, share = share, max = share.max, centre = st.centre, radius = st.radius,
			existing = RG.existing(g), armLead = RG.ARM_LEAD, pending = pend, canDefer = true,
			templates = st.templatePaths, height = function(x, y) return T.height(F.flat, x, y) end,
			housedDist = hidx and function(x, y) return SEL.housedDist(hidx, x, y) end or nil,
			draw = function(x, y, tag)
				local key = (tag == nil or tag == "ring") and "rb" or ("rb" .. tostring(tag))
				return rng.unit(st.seed, key, math.floor(x / 10), math.floor(y / 10))
			end })
		out.rings = out.rings + #res.rings
		for _, r in ipairs(res.rings) do
			out.sizes[r.class] = (out.sizes[r.class] or 0) + 1
			if r.wanted and r.wanted ~= r.class then
				local k = r.wanted .. ">" .. r.class
				out.fell = out.fell or {}
				out.fell[k] = (out.fell[k] or 0) + 1
			end
		end
		for _, h in ipairs(res.hubs or {}) do
			-- (round 3: every hub among houses: its centre within HUB_CENTRE_LEAD of a housed street)
			if hidx then
				local hd = SEL.housedDist(hidx, h.rec.centre[1], h.rec.centre[2])
				ok(hd <= RG.HUB_CENTRE_LEAD + 1, string.format("hub centre near houses (%.0f m)", hd))
			end
			out.hubs = out.hubs + 1
			if h.rec.deadEnd then out.deadEnd = (out.deadEnd or 0) + 1 end
			if h.site.gate then out.gates = out.gates + 1 end
		end
		for _, sk in ipairs(res.skipped) do local w = sk.why:match("^([%a:]+)") or sk.why; out.why[w] = (out.why[w] or 0) + 1 end
		if res.pair and res.pair.ok then out.pairs = out.pairs + 1 end
		if pend and res.deferred then
			if res.deferred.ok then out.pairs, pend = out.pairs + 1, nil
			else
				pend.n = pend.n - 1
				if pend.n <= 0 then pend = nil end
			end
		end
		if res.pending then pend, out.reserved = res.pending, out.reserved + 1 end
		if inc.rings then checkInc(inc, before, g) end
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + fill * k)
	end
	out.g = g
	return out
end

local function text(o)
	local s = {}
	for _, c in ipairs(RG.CLASSES) do s[#s + 1] = c .. "=" .. (o.sizes[c] or 0) end
	local w = {}
	for k, v in pairs(o.why) do w[#w + 1] = k .. "=" .. v end
	table.sort(w)
	local f = {}
	for k, v in pairs(o.fell or {}) do f[#f + 1] = k .. "=" .. v end
	table.sort(f)
	return string.format("%d rings in %d plans (%d hubs, %d gateways; %s; smaller than wanted %s), %d pairs (%d reserved); "
		.. "skipped %s", o.rings, o.plans, o.hubs, o.gates, table.concat(s, " "), #f > 0 and table.concat(f, " ") or "-", o.pairs,
		o.reserved, table.concat(w, " "))
end

local TOWNS = FULL and { 11, 12, 13, 14, 15, 16 } or { 11, 13, 15 }

--- The roundabout towns of TOWNS on a list (each run once per test file: the sweeps below share them).
local runs = {}
local function townRuns(list, year, maxEdges)
	local key = list .. ":" .. year .. ":" .. tostring(maxEdges)
	if runs[key] == nil then
		FM.ENABLED = true
		local okR, out = pcall(function()
			local o = {}
			for _, id in ipairs(TOWNS) do
				local st = townStyle(list, id, year)
				local r = run(st, 12, 70, maxEdges)
				r.id, r.style = id, st.id
				o[#o + 1] = r
			end
			return o
		end)
		FM.ENABLED = false
		assert(okR, out)
		runs[key] = out
	end
	return runs[key]
end
local EU_LIST, US_LIST = "::/names/france/france.names", "::/names/usa/usa.names"

local function rateCheck(rs, label)
	local rings, plans = 0, 0
	for _, o in ipairs(rs) do
		print(string.format("%s town %d (%s): %s", label, o.id, o.style, text(o)))
		ok(o.rings >= 0.4 * o.plans, "rings in town " .. o.id .. ": " .. o.rings .. "/" .. o.plans)
		rings, plans = rings + o.rings, plans + o.plans
		-- every two rings of the town apart (a hub keeps HUB_GAP_MIN from the others; the town's own spacing)
		local cs = RG.existing(o.g)
		for i = 1, #cs do
			for j = i + 1, #cs do ok(G.dist(cs[i].x, cs[i].y, cs[j].x, cs[j].y) >= RG.TOWN.spacing - 1, "rings apart") end
		end
	end
	print(string.format("%s: %d rings in %d plans (%.2f a plan)", label, rings, plans, rings / math.max(1, plans)))
	ok(rings >= 0.5 * plans, "a ring every second plan at least")
end

test("hubs: the roundabout town (EU, organic) has a ring at least every second plan", function()
	rateCheck(townRuns(EU_LIST, 1975), "EU")
end)

test("hubs: the NA grid roundabout town (usa list) gets its rings too", function()
	local rs = townRuns(US_LIST, 1975)
	for _, o in ipairs(rs) do eq(o.style, "NA_GRID") end
	rateCheck(rs, "NA grid")
end)

test("hubs: small plans as in game (the 2347 run: 1-9 edges a plan) still get about a ring a plan", function()
	-- (round 2: the game's plans gave almost no continuation node or long edge, 4 hubs in 20 steps; dead-end hubs since)
	local rings, plans, de = 0, 0, 0
	for _, list in ipairs({ EU_LIST, US_LIST }) do
		for _, o in ipairs(townRuns(list, 1975, 5)) do
			print(string.format("small plans, town %d (%s): %s", o.id, o.style, text(o)))
			rings, plans, de = rings + o.rings, plans + o.plans, de + (o.deadEnd or 0)
		end
	end
	print(string.format("small plans: %d rings in %d plans (%.2f a plan), %d dead-end hubs", rings, plans,
		rings / math.max(1, plans), de))
	ok(rings >= 0.7 * plans, "about a ring a plan")
	ok(de > 0, "dead-end hubs")
end)

test("hubs: all four sizes, hubs and gateways among them", function()
	local sizes, hubs, gates = {}, 0, 0
	for _, list in ipairs({ EU_LIST, US_LIST }) do
		for _, o in ipairs(townRuns(list, 1975)) do
			for c, v in pairs(o.sizes) do sizes[c] = (sizes[c] or 0) + v end
			hubs, gates = hubs + o.hubs, gates + o.gates
		end
	end
	local t = {}
	for _, c in ipairs(RG.CLASSES) do t[#t + 1] = c .. "=" .. (sizes[c] or 0) end
	print(string.format("%d towns: sizes %s; %d hubs, %d at gateways", 2 * #TOWNS, table.concat(t, " "), hubs, gates))
	for _, c in ipairs(RG.CLASSES) do ok((sizes[c] or 0) > 0, "size " .. c) end
	ok(hubs > 0 and gates > 0, "hubs and gateways")
end)

test("hubs: pairs form (twins reserved and placed by later plans)", function()
	local pairs_, reserved = 0, 0
	for _, list in ipairs({ EU_LIST, US_LIST }) do
		for _, o in ipairs(townRuns(list, 1975)) do pairs_, reserved = pairs_ + o.pairs, reserved + o.reserved end
	end
	print(string.format("%d towns: %d pairs formed, %d twins reserved", 2 * #TOWNS, pairs_, reserved))
	ok(pairs_ >= #TOWNS, "pairs form")
	-- (round 3: most twins complete; the 0234 run placed 2 of 12)
	ok(pairs_ >= 0.6 * reserved, "most twins complete")
end)

test("hubs: none in an ordinary town; a hub with no room for a ring leaves the plan as it was", function()
	FM.ENABLED = true
	local okR, err = pcall(function()
		local st = townStyle("::/names/france/france.names", 11, 1980, "garden_city")
		ok(st.rings == nil)
		local share = assert(RG.rate({ year = 1980, region = "EU", country = "france" }))
		ok(not share.hubs, "ordinary towns: no hubs")
		-- a hub site whose arms would cross an existing street: no ring, no new arms
		local g = OG.new()
		local a = OG.addNode(g, nil, -300, 0, 20)
		local b = OG.addNode(g, nil, 0, 0, 20)
		OG.addEdge(g, nil, a.id, b.id, "main")
		-- existing streets right across the new one's middle, 30 m off on both sides
		local c1, c2 = OG.addNode(g, nil, 80, 30, 20), OG.addNode(g, nil, 80, 300, 20)
		OG.addEdge(g, nil, c1.id, c2.id, "small")
		local c3, c4 = OG.addNode(g, nil, 80, -30, 20), OG.addNode(g, nil, 80, -300, 20)
		OG.addEdge(g, nil, c3.id, c4.id, "small")
		-- (80 m edges: no split site, the continuation node at x = 80 the only hub site)
		local inc = { nodes = { { entity = -3, x = 80, y = 0, z = 20 }, { entity = -4, x = 160, y = 0, z = 20 } },
			edges = {
				{ entity = -1, node0 = b.id, node1 = -3, p0 = { 0, 0, 20 }, p1 = { 80, 0, 20 }, t0 = { 80, 0, 0 }, t1 = { 80, 0, 0 },
					class = "main", template = MEDIUM, length = 80, key = "a" },
				{ entity = -2, node0 = -3, node1 = -4, p0 = { 80, 0, 20 }, p1 = { 160, 0, 20 }, t0 = { 80, 0, 0 }, t1 = { 80, 0, 0 },
					class = "main", template = MEDIUM, length = 80, key = "a" } },
			joins = { { node = b.id, edge = -1 } }, stats = { edges = 2, nodes = 2, length = 160 } }
		local n0 = #inc.edges
		RG.DEAD_END_HUBS = false
		local res = RG.mark(inc, { geo = GEO, g = g, share = RG.townShare({}), max = 4, centre = { 0, 0 }, radius = 600,
			templates = { main = MEDIUM, medium = SMALL, small = SMALL }, draw = function() return 0 end })
		RG.DEAD_END_HUBS = true
		eq(#res.rings, 0)
		eq(#inc.edges, n0, "the plan as it was")
		-- room on both sides (the existing street gone): a hub with two arms and its ring, every node configured
		local g2 = OG.new()
		local a2 = OG.addNode(g2, nil, -300, 0, 20)
		local b2 = OG.addNode(g2, nil, 0, 0, 20)
		OG.addEdge(g2, nil, a2.id, b2.id, "main")
		local before = joinsOf(inc)
		RG.DEAD_END_HUBS = false
		res = RG.mark(inc, { geo = GEO, g = g2, share = RG.townShare({}), max = 4, centre = { 0, 0 }, radius = 600,
			templates = { main = MEDIUM, medium = SMALL, small = SMALL }, draw = function() return 0 end })
		RG.DEAD_END_HUBS = true
		eq(#res.rings, 1)
		eq(#res.hubs, 1)
		eq(res.hubs[1].rec.hubArms, 2)
		checkInc(inc, before)
	end)
	FM.ENABLED = false
	assert(okR, err)
end)

test("hubs: an opposite twin's kind is saved on the frame (pk) and read back", function()
	local saved = SV.applyFrame(nil, { town = 7, a = 0, x = 0, y = 0 })
	saved = SV.applyPair(saved, { town = 7, x = 10, y = 20, h = 1.5, r = 34, n = 6, k = 2 })
	local fr = SV.frame(SV.normalize(saved), 7)
	ok(fr.pendingPair and fr.pendingPair.k == 2, "opposite kept")
	saved = SV.applyPair(saved, { town = 7, x = 10, y = 20, h = 1.5, r = 34, n = 6 })
	eq(SV.frame(SV.normalize(saved), 7).pendingPair.k, nil)
	saved = SV.applyPair(saved, { town = 7, n = 0 })
	eq(SV.frame(SV.normalize(saved), 7).pendingPair, nil)
end)

test("rates: modern US towns see a few rings by the 1990s (seed-a usa run: 0.00 from 1960)", function()
	local r60 = assert(RG.rate({ year = 1960, region = "US" }))
	local r75 = assert(RG.rate({ year = 1975, region = "US" }))
	local r95 = assert(RG.rate({ year = 1995, region = "US" }))
	print(string.format("US major-crossing share 1960 %.4f, 1975 %.3f, 1995 %.3f", r60.main, r75.main, r95.main))
	ok(r60.main < r75.main and r75.main < r95.main, "rising")
	near(r95.main, RG.RATE_LATE.US, 1e-9)
	-- Europe unchanged by the late rate
	near(assert(RG.rate({ year = 1995, region = "EU" })).main, RG.RATE.EU, 1e-9)
end)

test("dead-end hubs: only at a dead end with houses round it; never at an empty road's end", function()
	local g = OG.new()
	-- a housed street (west) ending in a dead end at x = 0, and an empty road going on to a dead end at x = 600
	local prev = OG.addNode(g, nil, -400, 0, 20)
	for i = 1, 4 do
		local n = OG.addNode(g, nil, -400 + i * 100, 0, 20)
		local e = OG.addEdge(g, nil, prev.id, n.id, "small")
		e.built = 8
		prev = n
	end
	local far = OG.addNode(g, nil, -300, 600, 20)
	local mid = OG.addNode(g, nil, -300, 100, 20)
	OG.addEdge(g, nil, g.nodes[2].id, mid.id, "small").built = 0
	OG.addEdge(g, nil, mid.id, far.id, "small").built = 0
	g.hasBuilt = true
	local hidx = SEL.housedIndexM(g, RG.ARM_LEAD)
	local o = { g = g, housedDist = function(x, y) return SEL.housedDist(hidx, x, y) end }
	local ends = {}
	for _, st in ipairs(RG.deadEndSites({ edges = {}, nodes = {} }, o, 34)) do ends[st.deadEnd] = true end
	ok(ends[prev.id], "the housed street's dead end")
	ok(not ends[far.id], "not the empty road's end")
	ok(not ends[g.nodes[1].id] or RG.housesNear(g, -400, 0, RG.HUB_DE_NEAR) >= RG.HUB_DE_HOUSES)
end)
