-- Roundabout variety and rings in every town (ot_ring, 2026-10-14, NEXT_PHASE_BRIEF 56): sizes by the crossing's class
-- (mini / s / m / l from square_roundabouts' radius list), the era / region rates of ordinary towns, the roundabout
-- town's higher share, pairs (both rings or neither), no ring with arms into empty land, and for every size: one-way,
-- counter-clockwise, a node config on every new node, no live junction touched, no -0.

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
local rng = ug_require(F.DIR .. "ot_rng.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")

local RB_DIR = here .. "../../mods/square_roundabouts/content"
local cache = {}
--- ug_require for square_roundabouts' modules (loaded from the repo, as test_character does).
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

---------------------------------------------------------------------------
-- synthetic crossings

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local MEDIUM = "::/infrastructure/street/town/town_new_medium.street_template"
local LARGE = "::/infrastructure/street/town/town_new_large.street_template"
local TPL = { small = SMALL, medium = SMALL, main = MEDIUM, wide = LARGE }

--- An increment: crossings { { x, y, arms = { { dx, dy, class } } } } (arm vectors from the crossing; an arm whose end
--- lies on another crossing joins them). Arms' far ends are existing nodes (ids 100+) unless shared. Returns inc, the
--- existing ids.
local function crossingInc(list)
	local nodes, edges = {}, {}
	local nid = -100
	local at = {}
	local function nodeAt(x, y, new)
		local k = string.format("%.1f:%.1f", x, y)
		if at[k] then return at[k] end
		local id
		if new then
			nid = nid - 1
			id = nid
			nodes[#nodes + 1] = { entity = id, x = x, y = y, z = 20 }
		else
			id = 100 + #edges + 1
		end
		at[k] = id
		return id
	end
	for _, c in ipairs(list) do nodeAt(c.x, c.y, true) end
	local seen = {}
	for _, c in ipairs(list) do
		local a = nodeAt(c.x, c.y, true)
		for _, arm in ipairs(c.arms) do
			local x1, y1 = c.x + arm[1], c.y + arm[2]
			local b = nodeAt(x1, y1, false)
			local key = math.min(a, b) .. ":" .. math.max(a, b)
			if not seen[key] then
				seen[key] = true
				local L = G.dist(c.x, c.y, x1, y1)
				edges[#edges + 1] = { entity = 0, node0 = a, node1 = b, p0 = { c.x, c.y, 20 }, p1 = { x1, y1, 20 },
					t0 = { arm[1], arm[2], 0 }, t1 = { arm[1], arm[2], 0 }, class = arm[3] == "wide" and "main" or arm[3] or "small",
					template = TPL[arm[3] or "small"], length = L, key = "k" .. #edges }
			end
		end
	end
	-- renumber like the planner: edges -1..-E, new nodes after
	local E = #edges
	local map = {}
	for i, n in ipairs(nodes) do map[n.entity] = -(E + i); n.entity = -(E + i) end
	local joins = {}
	for i, e in ipairs(edges) do
		e.entity = -i
		if e.node0 < 0 then e.node0 = map[e.node0] end
		if e.node1 < 0 then e.node1 = map[e.node1] end
		if e.node0 > 0 then joins[#joins + 1] = { node = e.node0, edge = -i } end
		if e.node1 > 0 then joins[#joins + 1] = { node = e.node1, edge = -i } end
	end
	return { nodes = nodes, edges = edges, joins = joins, stats = { edges = E, nodes = #nodes } }
end

--- A plus crossing at (x, y) of four arms of length L and the given classes (E, N, W, S).
local function plus(x, y, L, cls)
	cls = cls or { "small", "small", "small", "small" }
	local all = { { L, 0, cls[1] }, { 0, L, cls[2] }, { -L, 0, cls[3] }, { 0, -L, cls[4] } }
	local arms = {}
	for k = 1, #cls do arms[k] = all[k] end
	return { x = x, y = y, arms = arms }
end

--- The proposal info for an increment (every joined node an existing town node with a config).
local function infoFor(inc)
	local nodes = {}
	for _, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n > 0 then nodes[n] = { hasConfig = true, edges = { 9000 + n }, lanes = 4, src = 9000 + n, template = SMALL } end
		end
	end
	return { nodes = nodes, sources = { [SMALL] = 77, [MEDIUM] = 78, [LARGE] = 79 }, fallback = 77 }
end

--- The ring checks of test_character for an increment with rings: one-way CCW ring edges on new nodes, the joins of
--- the plain plan kept, a config on every new node, the one-way pattern at ring nodes, no -0.
local function checkRings(inc, joinsBefore, g)
	for _, e in ipairs(inc.edges) do
		-- (a roundabout town's dead-end hub joins a dead end of the graph, ot_ring §57: the planner's kind of join)
		local function joinOk(n) return joinsBefore[n] or (e.hubArm and g ~= nil and OG.degree(g, n) == 1) end
		if e.node0 > 0 then ok(joinOk(e.node0), "join kept") end
		if e.node1 > 0 then ok(joinOk(e.node1), "join kept") end
		if e.ring then
			ok(e.node0 < 0 and e.node1 < 0, "ring nodes are new")
			ok(e.oneway == true and e.template == RG.ONEWAY, "one-way")
		end
	end
	for _, r in ipairs(inc.rings) do
		local cx, cy = r.centre[1], r.centre[2]
		for _, e in ipairs(inc.edges) do
			if e.ring and G.dist(e.p0[1], e.p0[2], cx, cy) < r.R * 1.2 then
				local rx, ry = e.p0[1] - cx, e.p0[2] - cy
				ok(rx * e.t0[2] - ry * e.t0[1] > 0, "counter-clockwise")
				near(G.dist(e.p0[1], e.p0[2], cx, cy), r.R, 0.5, "on the ring")
			end
		end
	end
	local spec, err = PR.build(inc, infoFor(inc))
	ok(spec ~= nil, tostring(err))
	local cfg = {}
	for _, c in ipairs(spec.cfgAdd) do cfg[c.node] = c end
	for _, nd in ipairs(inc.nodes) do ok(cfg[nd.entity] ~= nil, "config on new node " .. nd.entity) end
	ok(PR.noNegativeZero(spec), "no -0")
	local byEnt = {}
	for _, e in ipairs(inc.edges) do byEnt[e.entity] = e end
	for _, nd in ipairs(inc.nodes) do
		if nd.ring then
			local inOut = false
			for _, cn in ipairs(cfg[nd.entity].conns) do
				local a, b = byEnt[cn[1]], byEnt[cn[3]]
				if a.ring then ok(a.node1 == nd.entity, "only the arriving ring edge leads on") end
				if b.ring then ok(b.node0 == nd.entity, "only into the leaving ring edge") end
				if a.ring and b.ring then inOut = true end
			end
			ok(inOut, "the ring goes round")
		end
	end
end

local function joinsOf(inc)
	local s = {}
	for _, e in ipairs(inc.edges) do
		if e.node0 > 0 then s[e.node0] = true end
		if e.node1 > 0 then s[e.node1] = true end
	end
	return s
end

local ALWAYS = { main = 1, mini = 1, gate = 1, pair = 0, spacing = 0 }
local function zero() return 0 end

---------------------------------------------------------------------------
-- sizes

test("sizes: four classes from square_roundabouts' radius list, mini to large", function()
	local want = { mini = { 17 }, s = { 19, 24 }, m = { 34, 39 }, l = { 49, 59 } }
	for cl, rs in pairs(want) do
		local list = GEO.classes[cl]
		ok(list ~= nil, cl)
		eq(#list, #rs, cl)
		for i, R in ipairs(rs) do near(list[i].R, R, 0.01, cl .. i) eq(list[i].template, RG.ONEWAY) end
	end
	-- the order tried: the seeded radius, smaller ones, then the smaller classes
	local Rs = {}
	for _, sz in ipairs(RG.sizesFor(GEO, "l", 0.99)) do Rs[#Rs + 1] = math.floor(sz.R + 0.5) end
	eq(table.concat(Rs, ","), "59,49,39,34,24,19,17")
	Rs = {}
	for _, sz in ipairs(RG.sizesFor(GEO, "m", 0)) do Rs[#Rs + 1] = math.floor(sz.R + 0.5) end
	eq(table.concat(Rs, ","), "34,24,19,17")
end)

test("sizes: chosen by the crossing's class (minor mini, one main s, main x main m, gateway / wide l)", function()
	eq(RG.classOf({ main = 0, med = 0 }), "mini")
	eq(RG.classOf({ main = 0, med = 1 }), "mini")
	eq(RG.classOf({ main = 0, med = 2 }), "s")
	eq(RG.classOf({ main = 1, med = 0 }), "s")
	eq(RG.classOf({ main = 1, med = 1 }), "m")
	eq(RG.classOf({ main = 1, med = 0, edges = { 1, 2, 3, 4 } }), "m")
	eq(RG.classOf({ main = 2, med = 0 }), "m")
	eq(RG.classOf({ main = 2, wide = true }), "l")
	eq(RG.classOf({ main = 3 }), "l")
	eq(RG.classOf({ main = 1, gate = true }), "m")
	eq(RG.classOf({ main = 2, gate = true }), "l")
	eq(RG.classOf({ main = 0, med = 2, gate = true }), "s")
	-- on an increment: the ring's size follows the class, room permitting
	local cases = {
		{ cls = { "small", "small", "small", "small" }, want = "mini" },
		{ cls = { "main", "small", "small" }, want = "s" },
		{ cls = { "main", "small", "small", "small" }, want = "m" },
		{ cls = { "main", "small", "main", "small" }, want = "m" },
		{ cls = { "main", "main", "main", "small" }, want = "l" },
		{ cls = { "wide", "small", "wide", "small" }, want = "l" },
	}
	for _, cs in ipairs(cases) do
		local inc = crossingInc({ plus(0, 0, 160, cs.cls) })
		local res = RG.mark(inc, { geo = GEO, share = ALWAYS, draw = zero })
		eq(#res.rings, 1, cs.want)
		eq(res.rings[1].class, cs.want)
	end
	-- no room for the large ring (an existing node 70 m off): the next size down that fits
	local g = OG.new()
	OG.addNode(g, 1, 0, 75, 20)
	local inc = crossingInc({ plus(0, 0, 160, { "main", "main", "main", "small" }) })
	local res = RG.mark(inc, { geo = GEO, g = g, share = ALWAYS, draw = zero })
	eq(#res.rings, 1)
	ok(res.rings[1].R + RG.CLEAR + 10 <= 75, "fits: R=" .. res.rings[1].R)
	eq(res.rings[1].wanted, "l")
	-- short arms: a smaller ring keeps ARM_MIN beyond it
	inc = crossingInc({ plus(0, 0, 60, { "main", "main", "main", "small" }) })
	res = RG.mark(inc, { geo = GEO, share = ALWAYS, draw = zero })
	eq(#res.rings, 1)
	ok(res.rings[1].R <= 60 - RG.ARM_MIN, "R=" .. res.rings[1].R)
end)

test("every size: one-way, counter-clockwise, every new node configured, no live junction touched, no -0", function()
	for _, cl in ipairs(RG.CLASSES) do
		for _, sz in ipairs(GEO.classes[cl]) do
			for _, rot in ipairs({ 0, 0.37, 1.1 }) do
				local c, s = math.cos(rot), math.sin(rot)
				local arms = {}
				for k, cls in ipairs({ "main", "medium", "small", "main" }) do
					if k <= (rot > 1 and 3 or 4) then
						local a = (k - 1) * math.pi / 2 + (k == 3 and 0.2 or 0)
						local L = 150 + 10 * k
						arms[#arms + 1] = { L * math.cos(a) * c - L * math.sin(a) * s, L * math.cos(a) * s + L * math.sin(a) * c, cls }
					end
				end
				local inc = crossingInc({ { x = 0, y = 0, arms = arms } })
				local before = joinsOf(inc)
				local cands = RG.candidates(inc)
				eq(#cands, 1)
				local rec = RG.place(inc, cands[1], sz, 1)
				ok(rec ~= nil, cl .. " placed")
				inc.rings = { rec }
				checkRings(inc, before)
			end
		end
	end
end)

---------------------------------------------------------------------------
-- rates

test("rates: rare before 1960, common in France / Europe from the 1970s, few in the US, none in JP dense", function()
	eq(RG.rate({ year = 1935, region = "EU" }), nil)
	local r50 = RG.rate({ year = 1950, region = "EU" })
	local r80 = RG.rate({ year = 1980, region = "EU" })
	local fr = RG.rate({ year = 1980, region = "EU", country = "france" })
	local us = RG.rate({ year = 1980, region = "US" })
	local jp = RG.rate({ year = 1980, region = "JP", style = "JP_DENSE" })
	local med = RG.rate({ year = 1967, region = "EU" })
	ok(r50.main < 0.05, "rare before 1960: " .. r50.main)
	ok(med.main > r50.main and med.main < r80.main, "rising through the 1960s")
	ok(fr.main > r80.main and r80.main > us.main, "France > Europe > US")
	ok(us.main <= 0.05, "few in the US")
	eq(jp, nil)
	ok(r80.mini < r80.main, "minor crossings rarer")
	ok(r80.cap >= 1 and r80.max <= 2, "ordinary towns: a few")
	-- the roundabout town: a much higher share, gateways, pairs, more a plan
	local tw = RG.townShare({ main = 0.95, mini = 0.5 })
	ok(tw.main > 3 * fr.main and tw.mini > 3 * fr.mini and tw.pair > fr.pair and tw.max > fr.max, "the roundabout town")
	ok(tw.spacing < fr.spacing, "closer together")
end)

--- n increments of a style on flat land from a round core; rings marked with share; returns the count, the incs.
local function ringRun(st, share, n, hd, fill)
	local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
	F.markBuilt(g, 120)
	local out = { rings = 0, pairs = 0, deferred = 0, empty = 0, incs = {}, sizes = {}, why = {}, recs = {}, extended = 0 }
	local pend = nil
	for k = 1, n do
		local inc = core.planIncrement(g, st, { terrain = F.flat, join = "deadEnd", maxEdges = 24 })
		if #inc.edges == 0 then break end
		local before = joinsOf(inc)
		local hidx = SEL.housedIndexM(g, RG.ARM_LEAD)
		local hdist = hidx and function(x, y) return SEL.housedDist(hidx, x, y) end or nil
		local res = RG.mark(inc, { geo = GEO, g = g, share = share, max = share.max, centre = st.centre, radius = st.radius,
			existing = RG.existing(g), housedDist = hd or hdist, armLead = RG.ARM_LEAD, pending = pend, canDefer = true,
			draw = function(x, y, tag) return rng.unit(st.seed, "rb" .. tostring(tag), math.floor(x / 10), math.floor(y / 10)) end })
		out.rings = out.rings + #res.rings
		for _, r in ipairs(res.rings) do
			out.sizes[#out.sizes + 1] = (r.wanted ~= r.class) and (r.wanted .. ">" .. r.class) or r.class
			out.recs[#out.recs + 1] = r
		end
		for _, sk in ipairs(res.skipped) do local w = sk.why:match("^(%a+)") or sk.why; out.why[w] = (out.why[w] or 0) + 1 end
		if res.pair and res.pair.ok then out.pairs = out.pairs + 1 end
		-- (the driver's deferred pair: placed, one plan less, or a new reservation)
		if pend and res.deferred then
			if res.deferred.ok then
				out.pairs, out.deferred, pend = out.pairs + 1, out.deferred + 1, nil
			else
				pend.n = pend.n - 1
				if pend.n <= 0 then pend = nil end
			end
		end
		if res.pending then pend = res.pending end
		for _, e in ipairs(inc.edges) do if e.ringExtended then out.extended = out.extended + 1 end end

		for _, sk in ipairs(res.skipped) do if sk.why == "emptyArm" then out.empty = out.empty + 1 end end
		if inc.rings then
			checkRings(inc, before, g)
			-- every ring's arms end within the lead of a housed street
			if hdist then
				local ringNode = {}
				for _, nd in ipairs(inc.nodes) do if nd.ring then ringNode[nd.entity] = true end end
				for _, e in ipairs(inc.edges) do
					if e.ringArm then
						local p = ringNode[e.node0] and e.p1 or e.p0
						ok(hdist(p[1], p[2]) <= RG.ARM_LEAD, "arm near houses")
					end
				end
			end
		end
		out.incs[#out.incs + 1] = inc
		OG.apply(g, inc, k)
		F.markBuilt(g, 120 + (fill or 70) * k)
	end
	out.g = g
	return out
end

local function townStyle(kind, year, list, id)
	local r = { townId = id or 11, year = year or 1975, nameList = list or "::/names/france/france.names", pos = { 0, 0 },
		capacity = 900 }
	r.terrain = T.stats(F.flat, 0, 0, 600, 24)
	local inp = I.build(r)
	inp.wide = T.wide(F.flat, 0, 0, 2000)
	if kind then
		inp.charKind, inp.charForm, inp.charMotifs = kind, CH.formFor(kind), CH.motifsFor(kind)
		inp.charSite = { region = inp.region }
	else
		inp.forceStyle = "EU_EXTENSION"
	end
	inp.autoStyle = true
	return ST.resolve(inp)
end

test("the roundabout town builds many more rings than an ordinary town", function()
	FM.ENABLED = true
	local okR, err = pcall(function()
		local tw, ord, sizes, pairs_, why = 0, 0, {}, 0, {}
		for id = 11, 14 do
			local st = townStyle("roundabout_town", nil, nil, id)
			local o = ringRun(st, RG.townShare(st.rings), 8)
			tw, pairs_ = tw + o.rings, pairs_ + o.pairs
			for _, c in ipairs(o.sizes) do sizes[c] = (sizes[c] or 0) + 1 end
			for w, n in pairs(o.why) do why[w] = (why[w] or 0) + n end
			local st2 = townStyle(nil, 1975, nil, id)
			ord = ord + ringRun(st2, assert(RG.rate({ year = 1975, region = "EU", country = "france" })), 8).rings
		end
		local ss, ws = {}, {}
		for c, n in pairs(sizes) do ss[#ss + 1] = c .. "=" .. n end
		for w, n in pairs(why) do ws[#ws + 1] = w .. "=" .. n end
		table.sort(ss)
		table.sort(ws)
		print(string.format("4 roundabout towns: %d rings (%s), %d pairs, skipped %s; 4 ordinary French towns of 1975: %d",
			tw, table.concat(ss, " "), pairs_, table.concat(ws, " "), ord))
		ok(tw >= 8, "roundabout town rings " .. tw)
		ok(tw >= 2 * ord, "more than ordinary towns")
		local kinds = 0
		for _ in pairs(sizes) do kinds = kinds + 1 end
		ok(kinds >= 2, "different sizes")
	end)
	FM.ENABLED = false
	assert(okR, err)
end)

--- The size mix of rings: { n, [class] = count, major = { n, m, l } (rings wanted m / l: main x main or a gateway) }.
local function mixOf(recs)
	local out = { n = 0, major = { n = 0 } }
	for _, r in ipairs(recs) do
		out.n = out.n + 1
		out[r.class] = (out[r.class] or 0) + 1
		if r.wanted == "m" or r.wanted == "l" then
			out.major.n = out.major.n + 1
			out.major[r.class] = (out.major[r.class] or 0) + 1
		end
	end
	return out
end
local function mixText(m)
	local parts = {}
	for _, c in ipairs(RG.CLASSES) do parts[#parts + 1] = string.format("%s=%d", c, m[c] or 0) end
	local mj = m.major
	return string.format("%d rings (%s); main x main / gateway %d: m=%d l=%d s=%d mini=%d", m.n, table.concat(parts, " "),
		mj.n, mj.m or 0, mj.l or 0, mj.s or 0, mj.mini or 0)
end

test("size mix: the roundabout towns use all four sizes; m / l at main x main crossings and gateways", function()
	FM.ENABLED = true
	local okR, err = pcall(function()
		local recs, pairs_, deferred, extended = {}, 0, 0, 0
		for id = 11, 18 do
			local st = townStyle("roundabout_town", nil, nil, id)
			-- (the houses keep up with the streets, as in a growing town: the rings' arms end near houses)
			local o = ringRun(st, RG.townShare(st.rings), 10, nil, 160)
			for _, r in ipairs(o.recs) do recs[#recs + 1] = r end
			pairs_, deferred, extended = pairs_ + o.pairs, deferred + o.deferred, extended + o.extended
		end
		local m = mixOf(recs)
		print("8 roundabout towns: " .. mixText(m) .. string.format("; %d pairs (%d deferred); %d extended arms", pairs_,
			deferred, extended))
		ok(pairs_ >= 2, "pairs")
		for _, c in ipairs(RG.CLASSES) do ok((m[c] or 0) > 0, "size " .. c) end
		ok(m.major.n >= 4, "main crossings")
		ok((m.major.m or 0) >= 0.25 * m.major.n, "m at main x main")
		ok((m.major.l or 0) >= 0.1 * m.major.n, "l at gateways / wide")
		-- ordinary EU towns (every eligible crossing drawn): mostly mini and s, some m
		local orecs = {}
		for id = 11, 18 do
			local st = townStyle(nil, 1980, "::/names/germany/germany.names", id)
			local sure = assert(RG.rate({ year = 1980, region = "EU" }))
			sure.main, sure.mini, sure.gate, sure.pair = 1, 1, 1, 0
			for _, r in ipairs(ringRun(st, sure, 10, nil, 160).recs) do orecs[#orecs + 1] = r end
		end
		local om = mixOf(orecs)
		print("8 ordinary EU towns (every eligible crossing): " .. mixText(om))
		ok((om.mini or 0) + (om.s or 0) >= 0.5 * om.n, "mostly mini / s")
		ok((om.m or 0) > 0, "some m")
	end)
	FM.ENABLED = false
	assert(okR, err)
end)

test("an ordinary town gets rings at its rate, spaced apart", function()
	local st = townStyle(nil, 1980)
	local share = assert(RG.rate({ year = 1980, region = "EU", country = "france" }))
	-- (sure draws: every eligible crossing, to see the spacing and the per-plan limit)
	local sure = {}
	for k, v in pairs(share) do sure[k] = v end
	sure.main, sure.mini, sure.gate, sure.pair = 1, 1, 1, 0
	local o = ringRun(st, sure, 8)
	ok(o.rings >= 1, "rings " .. o.rings)
	for _, inc in ipairs(o.incs) do ok(#(inc.rings or {}) <= share.max, "per plan") end
	local cs = RG.existing(o.g)
	for i = 1, #cs do
		for j = i + 1, #cs do ok(G.dist(cs[i].x, cs[i].y, cs[j].x, cs[j].y) >= RG.SPACING - 1, "spaced") end
	end
	-- JP dense: never
	eq(RG.rate({ year = 1990, region = "JP", style = "JP_DENSE" }), nil)
end)

---------------------------------------------------------------------------
-- pairs

--- Two crossings 300 m apart on one main street (A at 0, B at 300), each with a cross street.
local function twoOnAStreet()
	return crossingInc({
		{ x = 0, y = 0, arms = { { 300, 0, "main" }, { 0, 150, "main" }, { -150, 0, "main" }, { 0, -150, "medium" } } },
		{ x = 300, y = 0, arms = { { -300, 0, "main" }, { 0, 150, "main" }, { 150, 0, "main" }, { 0, -150, "medium" } } },
	})
end

test("pairs: two rings at the ends of one main street in one increment, the same size", function()
	local inc = twoOnAStreet()
	local before = joinsOf(inc)
	local res = RG.mark(inc, { geo = GEO, share = { main = 0, mini = 0, pair = 1, spacing = 260 }, max = 4, draw = zero })
	ok(res.pair ~= nil and res.pair.ok, "pair")
	eq(res.pair.kind, "street")
	eq(#res.rings, 2)
	eq(res.rings[1].R, res.rings[2].R)
	eq(res.rings[1].pair, "street")
	checkRings(inc, before)
	-- opposite sides of the town (centre between them): kind opposite
	inc = crossingInc({ plus(-260, 40, 150, { "main", "small", "main", "small" }),
		plus(250, -30, 150, { "main", "small", "small", "main" }) })
	-- (the two plus crossings' E-W arms point at each other only roughly: rotate one off the line)
	inc.edges[1].p1 = { -260 + 150, 40 + 60, 20 }
	inc.edges[1].t0, inc.edges[1].t1 = { 150, 60, 0 }, { 150, 60, 0 }
	res = RG.mark(inc, { geo = GEO, share = { main = 0, mini = 0, pair = 1, spacing = 260 }, max = 4, draw = zero,
		centre = { 0, 0 }, radius = 300 })
	ok(res.pair ~= nil and res.pair.ok, "opposite pair")
	eq(res.pair.kind, "opposite")
	eq(#res.rings, 2)
end)

test("pairs: both or neither (the second ring refused: the first comes out too)", function()
	local inc = twoOnAStreet()
	local nE, nN = #inc.edges, #inc.nodes
	local g = OG.new()
	OG.addNode(g, 1, 300, 38, 20)   -- (an existing node beside B: no ring fits there)
	local res = RG.mark(inc, { geo = GEO, g = g, share = { main = 0, mini = 0, pair = 1, spacing = 260 }, max = 4,
		draw = zero })
	ok(res.pair ~= nil and not res.pair.ok, "no pair")
	ok(res.pair.why:find("^second:"), res.pair.why)
	eq(#res.rings, 0)
	eq(#inc.edges, nE)
	eq(#inc.nodes, nN)
	eq(inc.rings, nil)
	-- the draw says no: nothing either
	inc = twoOnAStreet()
	res = RG.mark(inc, { geo = GEO, share = { main = 0, mini = 0, pair = 0.3, spacing = 260 }, max = 4,
		draw = function() return 0.5 end })
	ok(res.pair ~= nil and not res.pair.ok and res.pair.why:find("^draw"), "draw")
	eq(#res.rings, 0)
	-- a refused pre-check strips both rings of a pair at once
	inc = twoOnAStreet()
	res = RG.mark(inc, { geo = GEO, share = { main = 0, mini = 0, pair = 1, spacing = 260 }, max = 4, draw = zero })
	eq(#res.rings, 2)
	eq(RG.strip(inc), 2)
	eq(#inc.edges, nE)
	eq(inc.rings, nil)
end)

test("longer arms: a larger ring extends its arms through plain continuation nodes, never through a junction", function()
	-- a main x main crossing whose arms are split at 45 m by new 2-edge nodes (the plan's taps), 150 m in all
	local function split()
		local inc = crossingInc({ plus(0, 0, 45, { "main", "main", "main", "main" }) })
		-- (the four arms end at existing nodes 45 m out: make them new nodes going on 105 m further)
		local E = #inc.edges
		local edges, nodes = {}, {}
		for _, n in ipairs(inc.nodes) do nodes[#nodes + 1] = { entity = n.entity, x = n.x, y = n.y, z = n.z } end
		local nid = -1000
		for i, e in ipairs(inc.edges) do
			local d = { e.p1[1] - e.p0[1], e.p1[2] - e.p0[2] }
			nid = nid - 1
			local mid = nid
			nodes[#nodes + 1] = { entity = mid, x = e.p1[1], y = e.p1[2], z = 20 }
			edges[#edges + 1] = { entity = 0, node0 = e.node0, node1 = mid, p0 = e.p0, p1 = e.p1, t0 = e.t0, t1 = e.t1,
				class = "main", template = MEDIUM, length = 45, key = "a" .. i }
			local far = { e.p1[1] + d[1] / 45 * 105, e.p1[2] + d[2] / 45 * 105, 20 }
			local t = { d[1] / 45 * 105, d[2] / 45 * 105, 0 }
			edges[#edges + 1] = { entity = 0, node0 = mid, node1 = 500 + i, p0 = e.p1, p1 = far, t0 = t, t1 = t,
				class = "main", template = MEDIUM, length = 105, key = "b" .. i }
		end
		local map = {}
		for i, n in ipairs(nodes) do map[n.entity] = -(#edges + i); n.entity = -(#edges + i) end
		local joins = {}
		for i, e in ipairs(edges) do
			e.entity = -i
			if e.node0 < 0 then e.node0 = map[e.node0] end
			if e.node1 < 0 then e.node1 = map[e.node1] end
			if e.node1 > 0 then joins[#joins + 1] = { node = e.node1, edge = -i } end
		end
		return { nodes = nodes, edges = edges, joins = joins, stats = { edges = #edges, nodes = #nodes } }, E
	end
	local inc = split()
	local before = joinsOf(inc)
	local res = RG.mark(inc, { geo = GEO, share = ALWAYS, draw = function() return 0.99 end })
	eq(#res.rings, 1)
	eq(res.rings[1].class, "l")
	ok(res.rings[1].R >= 59, "R " .. res.rings[1].R)
	local ext = 0
	for _, e in ipairs(inc.edges) do if e.ringExtended then ext = ext + 1 end end
	eq(ext, 4)
	checkRings(inc, before)
	-- through a junction (a third street at the split node): no
	inc = split()
	local mid = inc.edges[1].node1
	inc.edges[#inc.edges + 1] = { entity = -(#inc.edges + 100), node0 = mid, node1 = 900, p0 = inc.edges[1].p1,
		p1 = { 45, 80, 20 }, t0 = { 0, 80, 0 }, t1 = { 0, 80, 0 }, class = "small", template = SMALL, length = 80, key = "x" }
	local cands = RG.candidates(inc)
	local c = nil
	for _, cc in ipairs(cands) do if math.abs(cc.x) < 1e-6 and math.abs(cc.y) < 1e-6 then c = cc end end
	ok(c ~= nil)
	RG.extendArms(inc, c, 80)
	local extended = {}
	for _, e in ipairs(inc.edges) do if e.ringExtended then extended[#extended + 1] = e end end
	eq(#extended, 3)
	for _, e in ipairs(extended) do ok(e.key ~= "a1", "not through the junction") end
end)

test("deferred pairs: a ring alone reserves its partner along its street; the next increment places it, same size", function()
	-- increment 1: A alone (town centre to the west); increment 2: B 300 m on east, an arm pointing back
	local inc1 = crossingInc({ plus(0, 0, 150, { "main", "main", "main", "small" }) })
	local share = { main = 1, mini = 0, pair = 1, spacing = 110 }
	local o = { geo = GEO, share = share, max = 4, draw = zero, centre = { -600, 0 }, radius = 500, canDefer = true }
	o.centre = { -600, 0 }
	local r1 = RG.mark(inc1, o)
	eq(#r1.rings, 1)
	ok(r1.pending ~= nil, "reserved")
	near(r1.pending.h, 0, 1e-6, "along the street east")
	eq(r1.pending.n, RG.PAIR_WAIT)
	local inc2 = crossingInc({ plus(300, 10, 150, { "main", "small", "main", "small" }) })
	local before = joinsOf(inc2)
	local r2 = RG.mark(inc2, { geo = GEO, share = { main = 0, mini = 0, pair = 1, spacing = 110 }, max = 4, draw = zero,
		pending = r1.pending, existing = { { x = 0, y = 0 } } })
	ok(r2.deferred ~= nil and r2.deferred.ok, "placed: " .. tostring(r2.deferred and r2.deferred.why))
	eq(#r2.rings, 1)
	eq(r2.rings[1].R, r1.rings[1].R)
	ok(r2.rings[1].deferred)
	checkRings(inc2, before)
	-- no partner along the street (a crossing off to the north): none, the reservation waits
	local inc3 = crossingInc({ plus(0, 300, 150, { "main", "small", "main", "small" }) })
	local r3 = RG.mark(inc3, { geo = GEO, share = { main = 0, mini = 0, pair = 1, spacing = 110 }, max = 4, draw = zero,
		pending = r1.pending })
	ok(r3.deferred ~= nil and not r3.deferred.ok)
	eq(r3.deferred.why, "none")
	eq(#r3.rings, 0)
	-- saved on the frame, cleared again (an additive field; no frame: ignored)
	local st = SV.applyFrame(nil, { town = 9, a = 0, x = 0, y = 0 })
	local s2, ch = SV.applyPair(st, { town = 9, x = 1, y = 2, h = 0.5, r = 34, n = 3 })
	ok(ch)
	local fr = SV.frame(SV.normalize(s2), 9)
	eq(fr.pendingPair.R, 34)
	eq(fr.pendingPair.n, 3)
	local s3 = SV.applyPair(s2, { town = 9, n = 0 })
	eq(SV.frame(s3, 9).pendingPair, nil)
	local _, ch2 = SV.applyPair(nil, { town = 77, x = 1, y = 2, h = 0, r = 34, n = 3 })
	eq(ch2, false)
end)

---------------------------------------------------------------------------
-- empty land

test("no ring whose arms lead into empty land beyond the lead", function()
	-- houses only west of x = 50: the east arm's end lies 160 m out, the crossing at 0
	local function hd(x, y) return math.max(0, x - 50) + 0 * y end
	local inc = crossingInc({ plus(0, 0, 160, { "main", "main", "main", "small" }) })
	local res = RG.mark(inc, { geo = GEO, share = ALWAYS, draw = zero, housedDist = hd, armLead = 100 })
	eq(#res.rings, 0)
	eq(res.skipped[1].why, "emptyArm")
	-- arms ending within the lead: the ring goes in
	inc = crossingInc({ plus(0, 0, 160, { "main", "main", "main", "small" }) })
	res = RG.mark(inc, { geo = GEO, share = ALWAYS, draw = zero, housedDist = hd, armLead = 120 })
	eq(#res.rings, 1)
	-- a whole run: every placed ring's arms end near houses (checked in ringRun), some skipped for it
	FM.ENABLED = true
	local okR, err = pcall(function()
		local st = townStyle("roundabout_town")
		local o = ringRun(st, RG.townShare(st.rings), 6)
		print(string.format("roundabout town run: %d rings, %d skipped as emptyArm", o.rings, o.empty))
	end)
	FM.ENABLED = false
	assert(okR, err)
end)

---------------------------------------------------------------------------
-- organic ring roads (ot_style ORGANIC_RINGS: the grower's rings, the ring road motif, crescents, ring lead, zone blend)

local ORG = ug_require(F.DIR .. "ot_grow_organic.lua")
local TW = ug_require(F.DIR .. "ot_motif_town.lua")
local CR = ug_require(F.DIR .. "ot_crescent.lua")

--- A style of id (EU_ORGANIC ...) through the input layer; frame optional (ot_saved.frame shape).
local function orgStyle(id, frame, o)
	o = o or {}
	local r = { townId = o.town or 21, year = o.year or 1960, nameList = "::/names/europe/europe.names", pos = { 0, 0 },
		capacity = 1500 }
	r.terrain = T.stats(F.flat, 0, 0, 600, 24)
	local inp = I.build(r)
	inp.forceStyle = id
	inp.keepOuter = true
	inp.frame = frame
	return ST.resolve(inp)
end

--- The grower's ring crossings: { [j] = { radius per spoke } } from the master plan's S i:j junctions.
local function ringRadii(mp, st)
	local out = {}
	for key, p in pairs(mp.junctions) do
		local i, j = key:match("^S(%d+):(%d+)$")
		if i then
			j = tonumber(j)
			out[j] = out[j] or {}
			out[j][#out[j] + 1] = G.dist(st.centre[1], st.centre[2], p[1], p[2])
		end
	end
	return out
end

local function stats(list)
	local s, s2 = 0, 0
	for _, v in ipairs(list) do s = s + v end
	local m = s / #list
	for _, v in ipairs(list) do s2 = s2 + (v - m) ^ 2 end
	return m, math.sqrt(s2 / #list)
end

test("organic rings: only new towns and towns framed with them; the frame keeps the flag (og)", function()
	F.withOrganicRings(function()
		ok(orgStyle("EU_ORGANIC").ringWobble == true, "a new town")
		eq(orgStyle("EU_ORGANIC", { axis = 0.3, origin = { 0, 0 } }).ringWobble, nil)
		ok(orgStyle("EU_ORGANIC", { axis = 0.3, origin = { 0, 0 }, organicRings = true }).ringWobble == true, "framed with")
		local st = orgStyle("EU_ORGANIC")
		local fp = SV.frameParam(5, st, { origin = { 0, 0 } })
		eq(fp.og, 1)
		local saved = SV.applyFrame(nil, fp)
		eq(SV.frame(saved, 5).organicRings, true)
		-- an old frame (no og): none
		local old = SV.applyFrame(nil, { town = 6, a = 0.2, x = 0, y = 0 })
		eq(SV.frame(old, 6).organicRings, nil)
	end)
	-- the setting off (the tests' default): none
	eq(orgStyle("EU_ORGANIC").ringWobble, nil)
end)

test("organic rings: the grower's rings wobble per spoke and are spaced unevenly; old towns keep even rings", function()
	local evenCv
	do
		local st = orgStyle("EU_ORGANIC", { axis = 0.3, origin = { 0, 0 } })
		local rs = ringRadii(ORG.masterPlan(st, { extent = 1500 }), st)
		local m, sd = stats(rs[3])
		evenCv = sd / m
	end
	F.withOrganicRings(function()
		for town = 21, 26 do
			local st = orgStyle("EU_ORGANIC", nil, { town = town })
			ok(st.ringWobble)
			local R = st.radial.ringEvery
			local rs = ringRadii(ORG.masterPlan(st, { extent = 1500 }), st)
			local means, cvs = {}, {}
			for j = 2, #rs do
				if rs[j] and #rs[j] >= 3 then
					local m, sd = stats(rs[j])
					ok(sd / m > 0.015, string.format("ring %d wobbles: cv %.3f", j, sd / m))
					means[#means + 1] = m
					cvs[#cvs + 1] = sd / m
				end
			end
			ok(stats(cvs) > 0.035, "rings wobble: mean cv " .. stats(cvs))
			ok(#means >= 3, "rings")
			-- no two rings at equal radius; the gaps between them not all alike
			local gaps = {}
			for k = 2, #means do
				ok(means[k] - means[k - 1] >= 0.5 * R, "apart")
				gaps[#gaps + 1] = means[k] - means[k - 1]
			end
			for k = 2, #gaps do
				ok(math.abs(gaps[k] - gaps[k - 1]) > 0.04 * R, string.format("gaps %.0f / %.0f", gaps[k - 1], gaps[k]))
			end
		end
	end)
	ok(evenCv < 0.02, "the old plan's rings stay even: " .. evenCv)
end)

test("organic rings: the ring road's radius wobbles, and no grower ring runs beside it", function()
	F.withOrganicRings(function()
		local st = orgStyle("EU_ORGANIC")
		local R = 436
		local Rt = TW.ringRad(st, R)
		local lo, hi = math.huge, 0
		for k = 0, 359 do
			local r = Rt(math.rad(k))
			lo, hi = math.min(lo, r), math.max(hi, r)
		end
		ok((hi - lo) / R > 0.08, string.format("wobble %.3f", (hi - lo) / R))
		ok((hi - lo) / R < 0.3, "not wild")
		-- smooth: the curve's radius far above the town streets' limit
		local pts = {}
		for k = 0, 360, 2 do local th = math.rad(k); pts[#pts + 1] = { Rt(th) * math.cos(th), Rt(th) * math.sin(th) } end
		ok(G.minDiscreteRadius(pts) > 150, "smooth: " .. G.minDiscreteRadius(pts))
		-- without the geometry: a circle
		local st0 = orgStyle("EU_ORGANIC", { axis = 0.3, origin = { 0, 0 } })
		eq(TW.ringRad(st0, R)(1.234), R)
		-- the grower leaves out its ring nearest the ring road
		st.motifs = { { id = "ring_road", ringR0 = R } }
		local rs = ringRadii(ORG.masterPlan(st, { extent = 1500 }), st)
		for j = 2, #rs do
			local m = stats(rs[j])
			ok(math.abs(m - R) >= ORG.RING_ROAD_GAP * st.radial.ringEvery * 0.8, string.format("ring %d at %.0f", j, m))
		end
	end)
end)

test("organic rings: ring pieces wait for the houses (no ring arc beyond the ring lead)", function()
	F.withOrganicRings(function()
		-- (town 22: town 21 held 4 ring pieces, then none at the 44 m minimum block, 2026-10-18; towns 15-30 show the
		-- wait 13 of 16 times before and after)
		local st = orgStyle("EU_ORGANIC", nil, { town = 22 })
		local g = F.roundCore(OG.new(), { rings = { 70, 140, 210 }, counts = { 6, 10, 14 } })
		F.markBuilt(g, 120)
		local held, arcs = 0, 0
		for k = 1, 8 do
			local inc, report = core.planIncrement(g, st, { terrain = F.flat, join = "deadEnd", maxEdges = 24 })
			if #inc.edges == 0 then break end
			held = held + ((report and report.ringHeld) or 0)
			local idx = SEL.housedIndexM(g, SEL.RING_LEAD_M)
			for _, e in ipairs(inc.edges) do
				local j = tonumber(tostring(e.key or ""):match("^rg%d+:(%d+)#"))
				if j and j > 1 then
					arcs = arcs + 1
					for _, p in ipairs({ e.p0, e.p1 }) do
						ok(SEL.housedDist(idx, p[1], p[2]) <= SEL.RING_LEAD_M + 1, "ring arc near houses")
					end
				end
			end
			OG.apply(g, inc, k)
			-- (the houses lag a little behind: the ring pieces ahead wait)
			F.markBuilt(g, 120 + 50 * k)
		end
		print(string.format("ring arcs built: %d, ring pieces held: %d", arcs, held))
		ok(arcs > 0, "ring arcs come")
		ok(held > 0, "ring arcs wait")
	end)
end)

test("organic rings: the outer zone blends in over its seam", function()
	F.withOrganicRings(function()
		local st = orgStyle("EU_ORGANIC", nil, { year = 1960 })
		ok(st.outer ~= nil, "an outer zone")
		local from = st.outer.from
		local inner = ST.zone(st, from - 1)
		local outer = ST.zone(st, from + 10000)
		local prev = inner.gridness
		local steps = 0
		for d = from, from + ST.ZONE_BLEND * st.radial.ringEvery, 20 do
			local z = ST.zone(st, d)
			ok(z.gridness >= prev - 1e-9 and z.gridness <= outer.gridness + 1e-9, "monotone")
			if z.gridness > inner.gridness + 1e-9 and z.gridness < outer.gridness - 1e-9 then steps = steps + 1 end
			prev = z.gridness
		end
		ok(steps > 0, "in between")
	end)
	-- an old town: the cut stays
	local st = orgStyle("EU_ORGANIC", { axis = 0.3, origin = { 0, 0 } }, { year = 1960 })
	eq(ST.zone(st, st.outer.from + 5).gridness, ST.zone(st, st.outer.from + 10000).gridness)
end)

test("organic rings: crescents bulge outward, never into their meadow", function()
	local function mpOf(st)
		local mp = { junctions = {}, pieces = {} }
		-- straight streets through the meadow's circle, every 30 deg
		for k = 0, 5 do
			local a = math.rad(k * 30 + 7)
			local ka, kb = "a" .. k, "b" .. k
			mp.junctions[ka] = { 400 * math.cos(a), 400 * math.sin(a) }
			mp.junctions[kb] = { -400 * math.cos(a), -400 * math.sin(a) }
			mp.pieces[#mp.pieces + 1] = { key = "p" .. k, a = ka, b = kb, pts = { mp.junctions[ka], mp.junctions[kb] }, class = "small" }
		end
		CR.apply(mp, st)
		return mp
	end
	F.withOrganicRings(function()
		local st = { greens = { { 0, 0, 110, true } }, seed = 5, ringWobble = true }
		local mp = mpOf(st)
		local bulged = 0
		for _, pc in ipairs(mp.pieces) do
			if pc.crescent then
				local far = 0
				for _, p in ipairs(pc.pts) do
					local d = G.dist(0, 0, p[1], p[2])
					ok(d >= 110 + CR.ARC_SETBACK - 0.01, "outside the meadow")
					far = math.max(far, d)
				end
				if far > 110 + CR.ARC_SETBACK + 3 then bulged = bulged + 1 end
				ok(#pc.pts < 3 or G.minDiscreteRadius(pc.pts) >= CR.MIN_RADIUS, "smooth")
			end
		end
		ok(bulged >= 2, "bulged arcs " .. bulged)
	end)
	local mp = mpOf({ greens = { { 0, 0, 110, true } }, seed = 5 })
	for _, pc in ipairs(mp.pieces) do
		if pc.crescent then
			for _, p in ipairs(pc.pts) do near(G.dist(0, 0, p[1], p[2]), 110 + CR.ARC_SETBACK, 0.01) end
		end
	end
end)
