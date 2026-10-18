-- Map edge, character towns and river bridges (2026-10-13, real map round 3; ot_map, ot_form CHARACTER, ot_bridge).
-- Real map run 2026-10-13_0137_sqot-dev: Axbridge's arm ran to the map boundary; the user wants a few drastically
-- different (secluded, sprawling) towns on every map, and towns that jump across a river.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local G = ug_require(F.DIR .. "ot_geom.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MAP = ug_require(F.DIR .. "ot_map.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local BR = ug_require(F.DIR .. "ot_bridge.lua")
local P = ug_require(F.DIR .. "ot_plan.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")

test("map edge: no planned street within the margin, 10 increments of a town 600 m from the edge", function()
	-- the map's east edge 600 m from the town centre (bounds as getBoundingBox gives them)
	local bounds = { -4000, -4000, 600, 4000 }
	local worst, n = math.huge, 0
	for _, town in ipairs({ 1, 7, 13 }) do
		local style, stats = F.style({ forceStyle = "EU_EXTENSION", townId = town, year = 1930, bounds = bounds,
			shape = "linear", nameList = "::/names/europe/europe.names" }, F.flat)
		local g = F.roundCore(OG.new(), { angle = 0.3 * town })
		for k = 1, 10 do
			local inc = core.planIncrement(g, style, { terrain = F.flat, stats = stats, join = "deadEnd", maxEdges = 18 })
			if #inc.edges == 0 then break end
			for _, e in ipairs(inc.edges) do
				for _, p in ipairs({ e.p0, e.p1 }) do
					worst = math.min(worst, MAP.edgeDist(bounds, p[1], p[2]))
					n = n + 1
				end
			end
			OG.apply(g, inc, k)
		end
	end
	print(string.format("      nearest planned node to the map edge: %.0f m (margin %d), %d nodes", worst, MAP.MARGIN, n))
	ok(n > 100, "the towns still grow")
	ok(worst >= MAP.MARGIN - 1, "never within the margin: " .. worst)
end)

test("map edge: a seeded shape axis turns its arms away from a near edge", function()
	local bounds = { -4000, -4000, 700, 4000 }
	local turned, exposed0, exposed1 = 0, 0, 0
	for town = 1, 12 do
		local free = F.style({ forceStyle = "EU_EXTENSION", townId = town, year = 1930, shape = "linear" }, F.flat)
		local near = F.style({ forceStyle = "EU_EXTENSION", townId = town, year = 1930, shape = "linear", bounds = bounds }, F.flat)
		exposed0 = exposed0 + MAP.armsExposure(bounds, 0, 0, free.shape.arms)
		exposed1 = exposed1 + MAP.armsExposure(bounds, 0, 0, near.shape.arms)
		if near.shape.edgeTurned then turned = turned + 1 end
	end
	print(string.format("      12 linear towns 700 m from the edge: %d turned, arm exposure %.2f -> %.2f", turned, exposed0 / 12, exposed1 / 12))
	ok(exposed1 < exposed0, "less exposure")
	ok(turned >= 3, "some turned")
	eq(MAP.edgeText(nil, 0, 0), "-")
	ok(MAP.nearEdge(bounds, 500, 0) and not MAP.nearEdge(bounds, 0, 0))
end)

test("character towns: the most secluded 15 % (at least 1-2), near the edge or far from others; deterministic", function()
	local towns = {}
	local k = 0
	-- a 4 x 4 grid of towns 3 km apart (a 16-town map), plus nothing special
	for i = 0, 3 do for j = 0, 3 do k = k + 1; towns[#towns + 1] = { 100 + k, -4500 + i * 3000, -4500 + j * 3000 } end end
	-- one far out in a corner, one secluded by a gap
	-- (round 5: 1.6 km from the edge; a town cramped at the rim, < EDGE_ROOM, has no room for an extreme form)
	towns[#towns + 1] = { 200, 6600, 6700 }
	towns[#towns + 1] = { 201, 7700, -7750 }
	local bounds = { -8192, -8192, 8192, 8192 }
	local chars, count = MAP.characters(towns, bounds)
	eq(count, 3, "15 % of 18 = 3")
	ok(chars[200].character and chars[200].rank == 1, "the corner town is the most secluded")
	ok(chars[201].edgeDist < MAP.EDGE_ROOM and chars[201].rank > chars[200].rank, "the cramped rim town ranks lower: "
		.. chars[201].rank)
	local again = MAP.characters(towns, bounds)
	for id, c in pairs(chars) do eq(again[id].character, c.character) end
	local _, c3 = MAP.characters({ { 1, 0, 0 }, { 2, 3000, 0 }, { 3, 0, 9000 } }, nil)
	eq(c3, 1, "a small map: at least one")
	local _, c2 = MAP.characters({ { 1, 0, 0 }, { 2, 3000, 0 } }, nil)
	eq(c2, 0, "two towns: none")
end)

test("character quota: only the map's own towns count, created towns never; saved picks stay (NEXT_PHASE_BRIEF 48.4)", function()
	local D = ug_require(F.DIR .. "ot_driver.lua")
	-- run 2026-10-14_0814_sqot load 3: 16 towns -> 2 character towns; a created town made it 17 -> 3 (Shanghai added)
	local pos = {}
	local ids = {}
	local k = 0
	for i = 0, 3 do for j = 0, 3 do
		k = k + 1
		ids[#ids + 1] = 100 + k
		pos[100 + k] = { -4500 + i * 3000 + (k % 3) * 170, -4500 + j * 3000 + (k % 5) * 130 }
	end end
	local lines = {}
	local E = { nowUs = function() return 0 end, towns = function() return ids end,
		boxCentre = function(t) local p = pos[t]; if p then return p[1], p[2] end return nil end,
		name = function(t) return "T" .. t end, log = function(l) lines[#lines + 1] = l end }
	local d = D.new(E, "[T]")
	d.verbose = true
	local function picks()
		local out = {}
		for _, id in ipairs(ids) do
			local c = d:characterOf(id, 0)
			if c and c.character then out[#out + 1] = id end
		end
		table.sort(out)
		return table.concat(out, ",")
	end
	local before = picks()
	local n0 = 0
	for _ in before:gmatch("%d+") do n0 = n0 + 1 end
	eq(n0, 2, "16 own towns: 2 character towns")
	-- a created town (a Works town, then a district) appears beside a town: the quota and the picks stay
	ids[#ids + 1] = 900
	pos[900] = { pos[101][1] + 900, pos[101][2] + 400 }
	d.worksTowns = { [900] = true }
	d.townList = nil
	eq(picks(), before, "a created Works town changes nothing")
	ids[#ids + 1] = 901
	pos[901] = { pos[116][1] - 700, pos[116][2] + 300 }
	d.saved = { dk = { { t = 901, p = 116 } } }
	d.townList = nil
	eq(picks(), before, "a saved district town changes nothing")
	local last = lines[#lines] or ""
	ok(last:find("towns=16", 1, true) and last:find("created=2", 1, true) and last:find("count=2", 1, true),
		"CHARACTER towns=16 created=2 count=2: " .. last)
	ok(d:characterOf(900, 0) == nil and d:characterOf(901, 0) == nil, "created towns are never ranked")
	-- saved picks stay: a framed character town keeps its pick even when it ranks low now; a framed town without it
	-- never becomes one; the quota's other slot goes to the best unframed town
	local first = tonumber(before:match("^(%d+)"))
	local low = nil
	for _, id in ipairs({ 106, 107, 110, 111 }) do
		if not before:find(tostring(id), 1, true) then low = id break end
	end
	ok(low ~= nil, "an inner town")
	d.saved = { dk = { { t = 901, p = 116 } }, frames = {
		[tostring(low)] = { a = 0, x = pos[low][1], y = pos[low][2], ch = 1 },
		[tostring(first)] = { a = 0, x = pos[first][1], y = pos[first][2] } } }
	ids[#ids + 1] = 902
	pos[902] = { 20000, 20000 }   -- (one more own town, far out: the ranking is redone)
	d.townList = nil
	local after = picks()
	ok(after:find(tostring(low), 1, true) ~= nil, "the saved character town stays one: " .. after)
	ok(after:find(tostring(first), 1, true) == nil, "a framed town without the pick never becomes one: " .. after)
	ok(after:find("902", 1, true) ~= nil, "the far new own town takes the free slot: " .. after)
	-- the pure rule
	local towns = { { 1, 0, 0 }, { 2, 3000, 0 }, { 3, 0, 3000 }, { 4, 3000, 3000 }, { 5, 9000, 9000 }, { 6, 1500, 1500 },
		{ 7, -3000, 0 }, { 8, 0, -3000 } }
	local plain = MAP.characters(towns, nil)
	local fx = MAP.characters(towns, nil, { [5] = false, [6] = true })
	ok(plain[5].character and not fx[5].character, "fixed false: never")
	ok(fx[6].character and fx[6].saved, "fixed true: always")
end)

test("character towns take extreme forms (sprawling with gaps, long arms) and keep them through the saved frame", function()
	F.withForms(function()
		local counts = {}
		local sprawl, normal = nil, nil
		for town = 1, 40 do
			local p = F.style({ forceStyle = "EU_ORGANIC", townId = town, year = 1900, character = { character = true, rank = 1, score = 3 } }, F.flat)
			ok(p.form and p.form.character, "character form")
			counts[p.form.id] = (counts[p.form.id] or 0) + 1
			if p.form.id == "sprawling" and sprawl == nil then sprawl = p end
		end
		normal = F.style({ forceStyle = "EU_ORGANIC", townId = 3, year = 1900, form = "clustered" }, F.flat)
		local t = {}
		for id, c in pairs(counts) do t[#t + 1] = id .. "=" .. c end
		table.sort(t)
		print("      40 character towns (flat, no water): " .. table.concat(t, " "))
		ok((counts.sprawling or 0) >= 12, "mostly sprawling")
		ok((counts.linear or 0) + (counts.fingers or 0) >= 8, "long / spidery ones too")
		ok(sprawl.shape.id == "compact" and #sprawl.greens >= 5, string.format("sprawling character: unshaped (hotspots) with many meadows: %s %d", sprawl.shape.id, #sprawl.greens))
		ok(sprawl.block.len >= normal.block.len * 1.4, "much larger blocks")
		-- saved: the frame keeps it
		local fp = SV.frameParam(5, sprawl, nil, nil)
		eq(fp.ch, 1)
		local st = SV.applyFrame(nil, fp)
		local fr = SV.frame(st, 5)
		ok(fr.character == true and fr.form == "sprawling")
		local re = F.style({ forceStyle = "EU_ORGANIC", townId = 5, year = 1900, frame = fr }, F.flat)
		ok(re.form.character and re.form.why == "saved", "saved character form")
		-- a character sprawl grows patches with gaps: more meadows, lower street density than a clustered town
		local function grow(p)
			local g = F.roundCore(OG.new(), { angle = 0.3 })
			for k = 1, 8 do
				local inc = core.planIncrement(g, p, { terrain = F.flat, join = "deadEnd", maxEdges = 18 })
				if #inc.edges == 0 then break end
				OG.apply(g, inc, k)
			end
			local m = MT.graph(g, 0, 0)
			return g, m
		end
		local gs, ms = grow(sprawl)
		local clustered = F.style({ forceStyle = "EU_ORGANIC", townId = sprawl.seed and 7 or 7, year = 1900, form = "clustered" }, F.flat)
		local gc, mc = grow(clustered)
		local function extent(g)
			local r = 0
			for _, n in ipairs(g.nodes) do r = math.max(r, math.sqrt(n.x * n.x + n.y * n.y)) end
			return r
		end
		print(string.format("      sprawling character: %d edges out to %.0f m; clustered: %d edges out to %.0f m", #gs.edges, extent(gs),
			#gc.edges, extent(gc)))
		ok(extent(gs) > extent(gc), "the character sprawl reaches farther with the same budget")
	end)
end)

-- a river along y = c, 60 m wide, flat banks (height 5) rising gently
local function riverSampler(c, w)
	return T.sampler(function(x, y)
		local d = math.abs(y - c)
		if d < w / 2 then return -2 end
		return 5 + math.min(d - w / 2, 400) * 0.005
	end)
end

test("bridge: a straight crossing at a narrow point, nodes on land, a valid proposal spec with node configs", function()
	local s = riverSampler(-200, 60)
	-- a town north of the river: a small grid core with a dead end pointing south
	local g = OG.new()
	local a = OG.addNode(g, nil, 0, 0, 5.5)
	local b = OG.addNode(g, nil, 0, -80, 5.3)
	local c = OG.addNode(g, nil, 80, 0, 5.5)
	local e1 = OG.addEdge(g, nil, a.id, b.id, "small")
	OG.addEdge(g, nil, a.id, c.id, "small")
	local tpl = "::/infrastructure/street/town/town_new_small.street_template"
	local bp, why, cands = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5.3, tpl } }, axis = 0, g = g, seed = 1 })
	ok(bp ~= nil, "planned: " .. tostring(why))
	print(string.format("      span %.0f m, approach %.0f m, far street %.0f m, deck %.1f m, %d edges, %d nodes, %d candidates", bp.span,
		bp.approach, bp.far, bp.deck, #bp.inc.edges, #bp.inc.nodes, cands))
	ok(bp.span >= 56 and bp.span <= 68, "spans the river: " .. bp.span)
	local nb = 0
	for _, e in ipairs(bp.inc.edges) do
		if e.bridge then
			nb = nb + 1
			ok(not T.isWater(s, e.p0[1], e.p0[2]) and not T.isWater(s, e.p1[1], e.p1[2]), "bridge ends on land")
		else
			ok(not T.wetAlong(s, { e.p0, e.p1 }, 0, 4), "only the bridge edge crosses water")
		end
	end
	eq(nb, 1, "one bridge edge")
	for _, nd in ipairs(bp.inc.nodes) do ok(not T.isWater(s, nd.x, nd.y), "every new node on land") end
	-- the spec: every new node gets a node config (dead ends an empty one), the joined dead end a full one
	local info = { nodes = { [b.id] = { hasConfig = true, edges = { e1.id }, lanes = 4, src = e1.id, template = tpl } },
		sources = { [tpl] = e1.id }, fallback = e1.id, lockKeys = bp.lockKeys, bridgeType = 3 }
	local spec, err = PR.build(bp.inc, info)
	ok(spec ~= nil, tostring(err))
	local cfgNodes = {}
	for _, cf in ipairs(spec.cfgAdd) do cfgNodes[cf.node] = #cf.conns end
	for _, nd in ipairs(bp.inc.nodes) do ok(cfgNodes[nd.entity] ~= nil, "config for new node " .. nd.entity) end
	ok(cfgNodes[b.id] and cfgNodes[b.id] > 0, "full config at the joined dead end")
	ok(PR.noNegativeZero(spec), "no -0")
	local bridges, locked = 0, 0
	for _, e in ipairs(spec.edges) do
		if e.bridge then bridges = bridges + 1; eq(e.bridge, 3) end
		if e.locked then locked = locked + 1 end
	end
	eq(bridges, 1)
	eq(locked, 2, "approach + bridge locked")
	-- no bridge type: no spec
	info.bridgeType = nil
	local none, err2 = PR.build(bp.inc, info)
	ok(none == nil and err2 == "noBridgeType")
end)

test("bridge: none over a wide river, none without water, eligibility seeded and once", function()
	local g = OG.new()
	local b = OG.addNode(g, nil, 0, -80, 5.3)
	local tpl = "x"
	local wide = riverSampler(-300, 300)
	local bp, why = BR.plan({ sampler = wide, deadEnds = { { b.x, b.y, b.id, 5.3, tpl } }, axis = 0, g = g })
	ok(bp == nil, "too wide: " .. tostring(why))
	local dry = T.sampler(function() return 10 end)
	local bp2, why2 = BR.plan({ sampler = dry, deadEnds = { { b.x, b.y, b.id, 5.3, tpl } }, axis = 0, g = g })
	ok(bp2 == nil and why2 == "noCrossing", tostring(why2))
	local n = 0
	for seed = 1, 200 do if BR.eligible({ seed = seed, buildings = 500, river = true }) then n = n + 1 end end
	ok(n >= 125 and n <= 175, "seeded share ~0.75: " .. n)
	ok(not BR.eligible({ seed = 1, buildings = 500, river = true, done = true }))
	ok(not BR.eligible({ seed = 1, buildings = 50, river = true }))
	ok(not BR.eligible({ seed = 1, buildings = 500, river = false }))
	-- saved once built
	local st = SV.applyFrame(nil, { town = 9, a = 0, x = 0, y = 0 })
	local st2, changed = SV.applyBridge(st, { town = 9 })
	ok(changed and SV.frame(st2, 9).bridge == true)
	local _, again = SV.applyBridge(st2, { town = 9 })
	ok(not again, "idempotent")
end)

test("bridge: narrow water found by rays from the centre (no river in the disc); the crossing planned toward it", function()
	-- a 60 m river 700 m south of the centre (beyond the 600 m disc: the town reads no river), a lake-like wide water
	-- 900 m north (too wide)
	local s = T.sampler(function(x, y)
		if math.abs(y + 700) < 30 then return -2 end
		if y > 900 then return -2 end
		return 5
	end)
	local pts = BR.narrowWater(s, 0, 0)
	ok(#pts >= 3, "narrow points: " .. #pts)
	for _, p in ipairs(pts) do
		ok(p[2] < 0 and p[3] >= 40 and p[3] <= 160, string.format("a river point %.0f,%.0f width %.0f", p[1], p[2], p[3]))
	end
	eq(#BR.narrowWater(T.sampler(function() return 5 end), 0, 0), 0, "dry: none")
	-- a dead end 400 m south (300 m from the river): the plan without an axis heads to the nearest point
	local g = OG.new()
	local a = OG.addNode(g, nil, 0, -300, 5)
	local b = OG.addNode(g, nil, 0, -400, 5)
	OG.addEdge(g, nil, a.id, b.id, "small")
	local bp, why = BR.plan({ sampler = s, deadEnds = { { b.x, b.y, b.id, 5, "x" } }, points = pts, g = g })
	ok(bp ~= nil, "planned: " .. tostring(why))
	if bp then
		near(bp.span, 60, 10, "span")
		ok(P.noNegativeZero(bp.inc), "no -0")
	end
end)

test("forms on a coast: a fan no longer makes every coast town a wide oval (real map run: 7 of 16 wide)", function()
	F.withForms(function()
		local counts, n = {}, 40
		for town = 1, n do
			local p = F.style({ forceStyle = "EU_ORGANIC", townId = town, year = 1900, nameList = "::/names/europe/europe.names" },
				F.coast(250))
			local id = p.form and p.form.id or "-"
			counts[id] = (counts[id] or 0) + 1
		end
		local t, kinds = {}, 0
		for id, c in pairs(counts) do t[#t + 1] = id .. "=" .. c; kinds = kinds + 1 end
		table.sort(t)
		print("      40 EU organic coast towns: " .. table.concat(t, " "))
		ok((counts.wide or 0) <= n * 0.35, "wide a minority: " .. (counts.wide or 0))
		ok(kinds >= 4, "several forms")
	end)
end)
