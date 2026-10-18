-- Towns follow the landscape (2026-10-13, real map round 5). User: "I still wish cities were more spread out around the
-- landscape, not just radiating from the centre. Hugging coastlines more often is probably not a bad idea." and on
-- Middlewich (a hillside town along its contour with one long street up the hill): "very cool".
--
-- Before / after on synthetic terrain: the round-5 weights (forms, shapes, shore share, hillside gain, one road out,
-- lobes along the roads / the contour) against the round-4 values (BEFORE, swapped in). Per site several towns grow from
-- a round core (F.roundCore, ~250 houses) to 4x in STEPS steps: the game adds streets nearest its centre at its unlocked
-- tips (as test_bigform, kept off the water), the mod one demand-sized increment per step (ot_core.planIncrement with
-- the driver's lock rule), houses by network distance. Measured: ot_metrics.landSpread of the houses (ratio of the
-- radius of gyration to an equal-area disc's, share beyond 1.5 x its radius, lobes) and the form / shape mix.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local WG = ug_require(F.DIR .. "ot_wedge.lua")

local H0, X, STEPS, LPE, GAME_K = 150, 6, 8, 7, 0.8

-- round-4 values of everything round 5 changed for the spread
local function copy(t)
	local o = {}
	for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
	return o
end
local BEFORE = {
	{ FM, "STYLE_WEIGHTS", {
		NA_GRID = { sprawling = 2, linear = 1.5, clustered = 1, radiating = 1, wide = 0.5 },
		NA_SUBURB = { sprawling = 2.5, fingers = 1.5, radiating = 1, clustered = 0.5 },
		EU_ORGANIC = { clustered = 2.5, radiating = 1.5, sprawling = 1, linear = 0.75, wide = 0.75 },
		EU_EXTENSION = { clustered = 1.5, radiating = 1.5, sprawling = 1, fingers = 0.75, linear = 0.75, wide = 0.5 },
		MED_HILL = { clustered = 3, radiating = 0.75, linear = 0.75 },
		MED_ENSANCHE = { clustered = 2, sprawling = 1, wide = 1 },
		JP_DENSE = { clustered = 3, radiating = 1.5, sprawling = 1, linear = 0.75 },
		NORDIC = { linear = 2, clustered = 1, sprawling = 1, wide = 0.75 },
		SUPERBLOCK = { sprawling = 2, clustered = 1, radiating = 1, linear = 0.5 } } },
	{ FM, "SITE_K", { sprawlTight = 0.7, clusteredTight = 0.8, linearRough = 0, fingersRough = 0 } },
	{ FM, "SHORE_P", { base = 0.1, island = 0.15, near = 0.06, nearM = 150, weak = 0.6, max = 0.4 } },
	{ SH, "SHORE_GAIN", 0.25 }, { SH, "SHORE_GAIN_NORDIC", 0.4 }, { SH, "HILLSIDE_GAIN", 0.8 }, { SH, "ONE_EXIT_GAIN", 0.5 },
	{ D, "LOBE_FILL", false },
}
local function withBefore(fn)
	local saved = {}
	for i, b in ipairs(BEFORE) do
		saved[i] = b[1][b[2]]
		b[1][b[2]] = type(b[3]) == "table" and copy(b[3]) or b[3]
	end
	local sw = { FM.STYLE_WEIGHTS.EU_ORGANIC, SH.STYLE_WEIGHTS.EU_ORGANIC, SH.STYLE_WEIGHTS.EU_EXTENSION, SH.STYLE_WEIGHTS.MED_HILL,
		SH.STYLE_WEIGHTS.JP_DENSE, SH.STYLE_WEIGHTS.NORDIC, FM.DEF.clustered, FM.DEF.sprawling, SH.GEOM.shore }
	SH.STYLE_WEIGHTS.EU_ORGANIC = { compact = 3, twin = 1.5, linear = 1, lens = 1, cross = 0.5 }
	SH.STYLE_WEIGHTS.EU_EXTENSION = { compact = 2, cross = 1.5, fingers = 1, linear = 1, twin = 1, lens = 0.5 }
	SH.STYLE_WEIGHTS.MED_HILL = { compact = 2, ridge = 2, lens = 0.5 }
	SH.STYLE_WEIGHTS.JP_DENSE = { linear = 0.75, compact = 3, cross = 1 }
	SH.STYLE_WEIGHTS.NORDIC = { fingers = 2, linear = 1.5, compact = 1.5, fan = 0.5 }
	FM.DEF.clustered = { shape = "compact", block = 0.9, front = 0.6, sector = 0.4, greens = 0 }
	FM.DEF.sprawling = { block = 1.35, front = 1.9, sector = 1.6, hotspots = 3, pull = 0.6, greensAdd = 2, greensMin = 3 }
	SH.GEOM.shore = { ka = 3.0, kb = 0.45, cf = 2.0, link = 0.35, depth = 3.5, depthMin = 140, depthMax = 350, steep = 4,
		island = 0.75, wetM = 30, env = 1.3 }
	local ok, err = pcall(fn, true)
	for i, b in ipairs(BEFORE) do b[1][b[2]] = saved[i] end
	SH.STYLE_WEIGHTS.EU_ORGANIC, SH.STYLE_WEIGHTS.EU_EXTENSION, SH.STYLE_WEIGHTS.MED_HILL = sw[2], sw[3], sw[4]
	SH.STYLE_WEIGHTS.JP_DENSE, SH.STYLE_WEIGHTS.NORDIC = sw[5], sw[6]
	FM.DEF.clustered, FM.DEF.sprawling, SH.GEOM.shore = sw[7], sw[8], sw[9]
	assert(ok, err)
end

local function rng(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

--- Houses: the first n lots (25 m, both sides, dry) by network distance from the centre node; the lots nearest each
--- dose-fill point (fills: the driver's D.fillPoints, DOSE_N lots within DOSE_R, Showcase v6: ~7 buildings within 60 m
--- per DevelopAt) come first.
local DOSE_N, DOSE_R = 7, 80
local function houses(g, n, s, fills)
	local start = OG.nearestNode(g, 0, 0, 1e9)
	local dist, done, heap = { [start.id] = 0 }, {}, { start.id }
	while true do
		local best, bd, bi = nil, math.huge, nil
		for i, id in ipairs(heap) do
			if dist[id] < bd then best, bd, bi = id, dist[id], i end
		end
		if not best then break end
		table.remove(heap, bi)
		if not done[best] then
			done[best] = true
			for _, eid in ipairs(g.adj[best]) do
				local e = g.edgeById[eid]
				local o = OG.other(e, best)
				local nd = bd + OG.edgeLength(g, e)
				if not done[o] and (dist[o] == nil or nd < dist[o]) then
					dist[o] = nd
					heap[#heap + 1] = o
				end
			end
		end
	end
	local lots = {}
	for _, e in ipairs(g.edges) do
		e.built = 0
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		local l = OG.edgeLength(g, e)
		local k = math.floor(l / 25)
		for i = 1, k do
			local t = (i - 0.5) / k
			local d = math.min((dist[e.n0] or 1e9) + l * t, (dist[e.n1] or 1e9) + l * (1 - t))
			local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
			if d < 1e8 and not T.isWater(s, x, y) then
				lots[#lots + 1] = { e, d, x, y }
				lots[#lots + 1] = { e, d, x, y }
			end
		end
	end
	for _, f in ipairs(fills or {}) do
		local near = {}
		for _, l in ipairs(lots) do
			local dd = math.sqrt((l[3] - f[1]) ^ 2 + (l[4] - f[2]) ^ 2)
			if dd <= DOSE_R and l[2] >= 0 then near[#near + 1] = { l, dd } end
		end
		table.sort(near, function(p, q) return p[2] < q[2] end)
		for i = 1, math.min(DOSE_N, #near) do near[i][1][2] = -1 end
	end
	table.sort(lots, function(p, q) return p[2] < q[2] end)
	local pts = {}
	for i = 1, math.min(n, #lots) do
		local l = lots[i]
		l[1].built = l[1].built + 1
		pts[#pts + 1] = { l[3], l[4] }
	end
	g.hasBuilt = true
	return pts
end

--- The game's streets (test_bigform's model, kept off the water and steep grades): n new streets nearest its centre.
local function gameStreets(g, n, rnd, s)
	local made = 0
	for _ = 1, n do
		local cands = {}
		for _, nd in ipairs(g.nodes) do
			local adj = g.adj[nd.id]
			if #adj == 1 and not g.edgeById[adj[1]].locked then
				cands[#cands + 1] = { id = nd.id, k = math.sqrt(nd.x * nd.x + nd.y * nd.y) + rnd() * 150, tip = true }
			elseif #adj == 2 and not g.edgeById[adj[1]].locked and not g.edgeById[adj[2]].locked then
				cands[#cands + 1] = { id = nd.id, k = math.sqrt(nd.x * nd.x + nd.y * nd.y) + 120 + rnd() * 150 }
			end
		end
		table.sort(cands, function(p, q) return p.k < q.k end)
		for i = 1, math.min(#cands, 60) do
			local c = cands[i]
			local a = g.nodeById[c.id]
			local e = g.edgeById[g.adj[c.id][1]]
			local o = g.nodeById[OG.other(e, c.id)]
			local h = math.atan(a.y - o.y, a.x - o.x)
			if c.tip then h = h + (rnd() - 0.5) * math.pi / 2
			else h = h + (rnd() < 0.5 and 1 or -1) * math.pi / 2 + (rnd() - 0.5) * 0.4 end
			local len = 60 + rnd() * 40
			local px, py = a.x + math.cos(h) * len, a.y + math.sin(h) * len
			local skip = { [c.id] = true }
			if not T.isWater(s, px, py) and not T.isWater(s, (a.x + px) / 2, (a.y + py) / 2)
				and T.grade(s, a.x, a.y, px, py) <= 0.12
				and not OG.crossing(g, a.x, a.y, px, py, skip) and not OG.distToEdges(g, px, py, 20, skip) then
				local nd = OG.addNode(g, nil, px, py, T.height(s, px, py))
				local ne = OG.addEdge(g, nil, c.id, nd.id, "small")
				ne.game, ne.built = true, 0
				made = made + 1
				break
			end
		end
	end
	return made
end

local SITES = {
	{ name = "flat", s = F.flat, style = "EU_ORGANIC" },
	{ name = "flat+roads", s = F.flat, style = "EU_ORGANIC", exits = { { 0.4, 1 }, { 2.6, 1 }, { 4.3, 0.8 } } },
	{ name = "coast", s = F.coast(420), style = "EU_ORGANIC" },
	{ name = "valley", s = F.valley(0.5), style = "EU_ORGANIC" },
	{ name = "hillside", s = F.plane(0.07, 1.2), style = "MED_HILL" },
}
local TOWNS = { 3, 8, 14, 21, 27, 33 }

local function grow(site, town)
	local style, stats
	F.withForms(function()
		style, stats = F.style({ forceStyle = site.style, townId = town, year = 1920, exits = site.exits,
			nameList = "::/names/europe/europe.names" }, site.s)
	end)
	-- (as the driver: lobes along the roads / contour, green wedges for armed shapes, a wedge frame now and then)
	style.lobeDirs = D.lobeDirs(site.exits, stats)
	style._irr = nil
	style.wedges = WG.applies(style) or nil
	local g = F.roundCore(OG.new(), { angle = 0.3 * town, rings = { 80, 160 }, counts = { 6, 10 } })
	-- (the core's streets on the water side are dropped: a coast town's core sits on the shore)
	for i = #g.edges, 1, -1 do
		local e = g.edges[i]
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if T.isWater(site.s, a.x, a.y) or T.isWater(site.s, b.x, b.y) then OG.removeEdge(g, e.id) end
	end
	for _, e in ipairs(g.edges) do e.game = true end
	local rnd = rng(town * 7 + #site.name)
	local fills = {}
	local pts = houses(g, H0, site.s)
	local placed, mod, game = #pts, 0, 0
	local rate = X ^ (1 / STEPS)
	for k = 1, STEPS do
		local H = H0 * rate ^ k
		local need = (H - H0 * rate ^ (k - 1)) / LPE
		game = game + gameStreets(g, math.floor(need * GAME_K + rnd()), rnd, site.s)
		if style.wedges and k % 2 == 0 then
			local inc = core.frameIncrement(g, style, { terrain = site.s })
			if inc then
				local map = OG.apply(g, inc, k)
				for _, e in ipairs(inc.edges) do
					local ge = g.edgeById[map[e.entity]]
					ge.locked, ge.built, ge.mod = true, 0, true
				end
				mod = mod + #inc.edges
			end
		end
		local me = math.max(6, math.min(36, math.floor((H - placed) / LPE + need + 0.5)))
		local inc, rep = core.planIncrement(g, style, { terrain = site.s, stats = stats, join = "deadEnd", maxEdges = me })
		if #inc.edges > 0 then
			local map = OG.apply(g, inc, k)
			local keys = D.lockKeys({ inc = inc, style = style, report = rep, sampler = site.s })
			for _, e in ipairs(inc.edges) do
				local ge = g.edgeById[map[e.entity]]
				ge.built, ge.mod = 0, true
				if keys and e.key and keys[e.key] then ge.locked = true end
			end
			mod = mod + #inc.edges
			-- the driver's dose fill after a build (shaped towns' arm / rim streets, sprawling towns' outer streets)
			local kind = D.fillKind({ style = style, town = town }, {}, nil, nil, placed, nil, nil)
			if kind == "dose" then
				local edges = {}
				for _, e in ipairs(inc.edges) do edges[#edges + 1] = { p0 = e.p0, p1 = e.p1 } end
				for _, p in ipairs(D.fillPoints("dose", edges, style.shape, rep and D.envLevel(rep), site.s, style)) do
					fills[#fills + 1] = p
				end
			end
		end
		pts = houses(g, math.floor(H + 0.5), site.s, fills)
		placed = #pts
	end
	local sp = MT.landSpread(pts, 0, 0)
	if os.getenv("OT_SPREAD_V") then
		local nOld = 0
		for _, e in ipairs(g.edges) do if e.game then nOld = nOld + 1 end end
		local mids = {}
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			mids[#mids + 1] = { (a.x + b.x) / 2, (a.y + b.y) / 2 }
		end
		print(string.format("        %s town %d %s/%s: edges %d (game %d, mod %d) houses %d spread %s streets %s", site.name, town,
			style.form and style.form.id or "-", style.shape and style.shape.id or "-", #g.edges, nOld, mod, placed,
			MT.spreadText(sp), MT.spreadText(MT.landSpread(mids, 0, 0))))
	end
	return { form = style.form and style.form.id or "-", shape = style.shape and style.shape.id or "-", sp = sp,
		share = mod / math.max(1, mod + game), housed = placed / (H0 * X) }
end

local function run()
	local out = {}
	for _, site in ipairs(SITES) do
		local r = { ratio = 0, beyond = 0, lobes = 0, n = 0, forms = {}, housed = 0 }
		for _, town in ipairs(TOWNS) do
			local x = grow(site, town)
			r.n = r.n + 1
			r.ratio, r.beyond, r.lobes = r.ratio + x.sp.ratio, r.beyond + x.sp.beyond, r.lobes + x.sp.lobes
			r.housed = r.housed + x.housed
			r.forms[#r.forms + 1] = x.form .. "/" .. x.shape
		end
		r.ratio, r.beyond, r.lobes, r.housed = r.ratio / r.n, r.beyond / r.n, r.lobes / r.n, r.housed / r.n
		out[site.name] = r
	end
	return out
end

test("spread across the landscape (round 5): towns on coast / valley / hillside / roads reach farther than a disc, fewer round forms; still housed", function()
	local before
	withBefore(function() before = run() end)
	local after = run()
	local sb, sa, nRound = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0 }
	for _, site in ipairs(SITES) do
		local b, a = before[site.name], after[site.name]
		print(string.format("      %-10s before ratio %.2f beyond %2.0f %% lobes %.1f housed %3.0f %% | after ratio %.2f beyond %2.0f %% lobes %.1f housed %3.0f %%",
			site.name, b.ratio, 100 * b.beyond, b.lobes, 100 * b.housed, a.ratio, 100 * a.beyond, a.lobes, 100 * a.housed))
		print("                 before " .. table.concat(b.forms, " "))
		print("                 after  " .. table.concat(a.forms, " "))
		sb[1], sb[2], sb[3] = sb[1] + b.ratio, sb[2] + b.beyond, sb[3] + b.lobes
		sa[1], sa[2], sa[3] = sa[1] + a.ratio, sa[2] + a.beyond, sa[3] + a.lobes
		for _, f in ipairs(b.forms) do if f:find("^clustered") or f:find("^wide") then nRound[1] = nRound[1] + 1 end end
		for _, f in ipairs(a.forms) do if f:find("^clustered") or f:find("^wide") then nRound[2] = nRound[2] + 1 end end
		-- (the model's valley sides are too steep for many streets either way; shore strips are single-loaded)
		ok(a.housed >= b.housed - 0.1, string.format("%s: houses its growth about as well: %.2f vs %.2f", site.name, a.housed,
			b.housed))
	end
	local n = #SITES
	print(string.format("      mean: before ratio %.2f beyond %.0f %% lobes %.2f, after ratio %.2f beyond %.0f %% lobes %.2f; clustered / wide %d -> %d of %d",
		sb[1] / n, 100 * sb[2] / n, sb[3] / n, sa[1] / n, 100 * sa[2] / n, sa[3] / n, nRound[1], nRound[2], n * #TOWNS))
	ok(sa[1] > sb[1], "spread ratio up")
	ok(sa[2] > sb[2], "more buildings beyond 1.5 x the disc")
	ok(nRound[2] < nRound[1], "fewer clustered / wide towns")
	ok(after.coast.ratio >= before.coast.ratio, "coast towns at least as spread")
end)

test("landSpread / hillRoad metrics: a disc reads ~1, a strip and two lobes more; the steepest arm's climb", function()
	local disc, strip, two = {}, {}, {}
	for i = -10, 10 do
		for j = -10, 10 do
			if i * i + j * j <= 100 then disc[#disc + 1] = { i * 30, j * 30 } end
		end
	end
	for i = -40, 40 do strip[#strip + 1] = { i * 25, 0 }; strip[#strip + 1] = { i * 25, 30 } end
	for _, p in ipairs(disc) do
		if p[1] * p[1] + p[2] * p[2] <= 120 * 120 then
			two[#two + 1] = { p[1], p[2] }
			two[#two + 1] = { p[1] + 700, p[2] }
		end
	end
	local d, s, t = MT.landSpread(disc, 0, 0), MT.landSpread(strip, 0, 0), MT.landSpread(two, 0, 0)
	print(string.format("      disc %s, strip %s, two lobes %s", MT.spreadText(d), MT.spreadText(s), MT.spreadText(t)))
	ok(math.abs(d.ratio - 1) < 0.15, "disc ~1: " .. d.ratio)
	ok(s.ratio > 2, "strip spread: " .. s.ratio)
	eq(d.lobes, 1)
	eq(t.lobes, 2, "two lobes")
	ok(t.beyond > 0.3, "half beyond: " .. t.beyond)
	eq(MT.spreadText(nil), "-")
	eq(MT.landSpread({ { 0, 0 } }, 0, 0), nil)
	-- hill road: a linear town on a plane rising east; its east arm climbs
	local g = OG.new()
	local prev = OG.addNode(g, nil, 0, 0, 0)
	for k = 1, 8 do
		local nd = OG.addNode(g, nil, k * 100, 0, 0)
		OG.addEdge(g, nil, prev.id, nd.id, "small")
		prev = nd
	end
	local sh = { id = "linear", centre = { 0, 0 }, axis = 0, arms = { 0, math.pi }, block = 80, reach = 1, ka = 2.5, kb = 0.42 }
	local s8 = F.plane(0.08, 0)
	local pts = {}
	for k = 2, 8 do pts[#pts + 1] = { k * 100 - 50, 15 } end
	local h = MT.hillRoad(g, sh, pts, s8)
	print("      hill road " .. MT.hillText(h))
	ok(h and h.len >= 600 and h.climb > 40 and h.houses >= 5, MT.hillText(h))
	eq(MT.hillRoad(g, { id = "compact", centre = { 0, 0 } }, pts, s8), nil)
end)
