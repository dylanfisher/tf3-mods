-- Shared fixtures for the square_organic_towns tests (loaded with loadfile from the test files):
-- synthetic terrain samplers, a style builder going through the real input layer, and network invariants.

local DIR = "square_organic_towns::/organic_towns/"
local G = ug_require(DIR .. "ot_geom.lua")
local OG = ug_require(DIR .. "ot_graph.lua")
local T = ug_require(DIR .. "ot_terrain.lua")
local I = ug_require(DIR .. "ot_inputs.lua")
local ST = ug_require(DIR .. "ot_style.lua")
local MT = ug_require(DIR .. "ot_metrics.lua")

local F = { DIR = DIR }

-- Green reserves (ot_select.GREEN, Showcase v7 round) are off for the tests of the other rules: their baselines
-- (even vs irregular growth, shape metrics, young towns) were measured without them. test_metro.lua turns them on
-- for its own checks (F.withGreen).
local SEL = ug_require(DIR .. "ot_select.lua")
SEL.GREEN = false
function F.withGreen(fn)
	SEL.GREEN = true
	local ok, err = pcall(fn)
	SEL.GREEN = false
	assert(ok, err)
end

-- Town forms (ot_form, Showcase v8 round) likewise: off here, test_form.lua turns them on (F.withForms).
local FM = ug_require(DIR .. "ot_form.lua")
FM.ENABLED = false
function F.withForms(fn)
	FM.ENABLED = true
	local ok, err = pcall(fn)
	FM.ENABLED = false
	assert(ok, err)
end

-- Organic <-> gridded (ot_grid, 2026-10-13) likewise: off here, test_grid.lua turns it on (F.withGrid).
local GR = ug_require(DIR .. "ot_grid.lua")
GR.ON = false
function F.withGrid(fn)
	GR.ON = true
	local ok, err = pcall(fn)
	GR.ON = false
	assert(ok, err)
end

-- Organic ring geometry (ot_style.ORGANIC_RINGS, 2026-10-14 §56: wobbling rings, ring lead, zone blend) likewise: off
-- here (the growth baselines were measured with the even rings), test_rings.lua turns it on (F.withOrganicRings).
ST.ORGANIC_RINGS = false
function F.withOrganicRings(fn)
	ST.ORGANIC_RINGS = true
	local ok, err = pcall(fn)
	ST.ORGANIC_RINGS = false
	assert(ok, err)
end

F.flat = T.sampler(function() return 20 end)

--- Plane rising `grade` per metre toward heading `dir` (radians).
function F.plane(grade, dir)
	local ux, uy = math.cos(dir or 0), math.sin(dir or 0)
	return T.sampler(function(x, y) return 50 + grade * (x * ux + y * uy) end)
end

--- Round hill (top at hx, hy) whose flank at the origin is ~11 %.
F.hill = T.sampler(function(x, y)
	local dx, dy = x - 300, y
	return 15 + 80 * math.exp(-(dx * dx + dy * dy) / (2 * 400 * 400))
end)

--- River along y = c (50 m wide), banks rising gently.
function F.river(c)
	c = c or -120
	return T.sampler(function(x, y)
		local d = math.abs(y - c)
		if d < 25 then return -2 end
		return 5 + math.min(d - 25, 400) * 0.01
	end)
end

--- Sea beyond x = shore (east), land rising inland.
function F.coast(shore)
	shore = shore or 300
	return T.sampler(function(x, y)
		if x > shore then return -3 end
		return 2 + (shore - x) * 0.02
	end)
end

--- A bay (motifs M1, harbour crescent): the sea beyond x = 650 and a round bay of radius 350 centred at (650, 0)
--- cut into the land (its shore 300 m east of the origin), land rising gently inland (2 %).
function F.bay()
	return T.sampler(function(x, y)
		local d = math.sqrt((x - 650) ^ 2 + y * y)
		if x > 650 or d < 350 then return -3 end
		return 2 + math.min(d - 350, 650 - x) * 0.02
	end)
end

--- A hillside with shelves (motifs M1, hill climb terraces): rising ~6 % toward +x, flatter shelves every 240 m
--- (the grade swings 2 .. 10 %).
F.terraces = T.sampler(function(x, y)
	return 50 + 0.06 * x + 1.5 * math.sin(2 * math.pi * x / 240)
end)

--- A sloped straight shore (motifs M1, fishing village): the sea beyond x = shore (east), the land rising `grade`
--- per metre inland (default 6 %).
function F.shoreSlope(shore, grade)
	shore, grade = shore or 250, grade or 0.06
	return T.sampler(function(x, y)
		if x > shore then return -3 end
		return 2 + (shore - x) * grade
	end)
end

--- A valley along heading `dir` through the origin: the ground rises with the square of the distance from the
--- valley line (9 m at 150 m, 36 m at 300 m). ridge = true turns it upside down (a crest).
function F.valley(dir, ridge)
	local ux, uy = math.cos(dir or 0), math.sin(dir or 0)
	return T.sampler(function(x, y)
		local perp = -x * uy + y * ux
		local h = 0.0004 * perp * perp
		return ridge and (150 - h) or (20 + h)
	end)
end

--- A steep hillside (motifs M4, switchbacks): rising `grade` (default 11 %) toward +x with gentler shelves every 200 m
--- (the local grade swings +- `swing`, default 0.05).
function F.steep(grade, swing)
	grade, swing = grade or 0.11, swing or 0.05
	local A = swing * 200 / (2 * math.pi)
	return T.sampler(function(x, y) return 60 + grade * x + A * math.sin(2 * math.pi * x / 200) end)
end

--- A crest along the x axis (motifs M4, ridge street) whose flanks are gentle west of x = 0 (as F.valley(0, true)) and
--- three times steeper east of it.
function F.ridgeVar()
	return T.sampler(function(x, y)
		local k = x < 0 and 0.0004 or 0.0012
		return 150 - k * y * y
	end)
end

--- A cliff coast (motifs M4, headland street): a plateau ~30 m above the sea, rising 1 % inland, its brink at
--- x = brink(y) (default 320 - bend x y^2: bend 0 a straight coast, > 0 a headland bulging east), a 60 m cliff, the sea
--- beyond.
function F.cliff(bend)
	bend = bend or 0
	return T.sampler(function(x, y)
		local xb = 320 - bend * y * y
		if x <= xb then return 30 + 0.01 * (xb - x) end
		if x <= xb + 60 then return 30 - 33 * (x - xb) / 60 end
		return -3
	end)
end

--- StyleParams for a town at (0, 0) through ot_inputs + ot_style. raw overrides (nameList, year, ...).
-- Town-structure / era motifs (ot_motif_town, M3 2026-10-13) likewise: off here (their eligibility 0, so the other
-- kinds' draws stay as measured), test_motif_town.lua turns them on (F.withTownMotifs).
local TW = ug_require(DIR .. "ot_motif_town.lua")
TW.ON = false
function F.withTownMotifs(fn)
	TW.ON = true
	local ok, err = pcall(fn)
	TW.ON = false
	assert(ok, err)
end

-- More terrain motifs (ot_motif_relief, M4 2026-10-13): off here likewise, test_motif_relief.lua turns them on
-- (F.withReliefMotifs).
local RL = ug_require(DIR .. "ot_motif_relief.lua")
RL.ON = false
function F.withReliefMotifs(fn)
	RL.ON = true
	local ok, err = pcall(fn)
	RL.ON = false
	assert(ok, err)
end

function F.style(raw, sampler)
	local r = { townId = 7, pos = { 0, 0 }, capacity = 1500, year = 1960, nameList = "::/names/usa/usa.names" }
	for k, v in pairs(raw or {}) do r[k] = v end
	if sampler then r.terrain = T.stats(sampler, 0, 0, 600, 24) end
	return ST.resolve(I.build(r)), r.terrain
end

--- A vanilla-like town core (what the game's own town generator leaves, the start of every in-game town): a
--- grid of n x n nodes `spacing` m apart around (cx, cy), turned by `angle` (rad), all edges, plus a dead-end stub
--- of `stub` m outward from every perimeter node that is not a corner. Returns the graph.
function F.vanillaTown(g, o)
	o = o or {}
	g = g or OG.new()
	local n, sp, stub = o.n or 5, o.spacing or 90, o.stub or 40
	local cx, cy, a = o.cx or 0, o.cy or 0, o.angle or 0
	local ca, sa = math.cos(a), math.sin(a)
	local function at(u, v) return cx + u * ca - v * sa, cy + u * sa + v * ca end
	local ids = {}
	local half = (n - 1) / 2
	for i = 0, n - 1 do
		ids[i] = {}
		for j = 0, n - 1 do
			local x, y = at((i - half) * sp, (j - half) * sp)
			ids[i][j] = OG.addNode(g, nil, x, y, 20).id
		end
	end
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			if i < n - 1 then OG.addEdge(g, nil, ids[i][j], ids[i + 1][j], "small") end
			if j < n - 1 then OG.addEdge(g, nil, ids[i][j], ids[i][j + 1], "small") end
		end
	end
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local edge = i == 0 or j == 0 or i == n - 1 or j == n - 1
			local corner = (i == 0 or i == n - 1) and (j == 0 or j == n - 1)
			if edge and not corner then
				local du = (i == 0 and -1) or (i == n - 1 and 1) or 0
				local dv = (j == 0 and -1) or (j == n - 1 and 1) or 0
				local x, y = at((i - half) * sp + du * stub, (j - half) * sp + dv * stub)
				local d = OG.addNode(g, nil, x, y, 20)
				OG.addEdge(g, nil, ids[i][j], d.id, "small")
			end
		end
	end
	return g
end

--- A round vanilla-like core as the game makes it (Showcase v4: ~70 edges, 12 dead ends, building extent ~250 m):
--- three rings (90 / 180 / 270 m, 6 / 10 / 14 nodes, wobbled), radials, and a 50 m dead-end stub outward from
--- every outer node (o.stubStep: every n-th). o.angle turns it. Returns the graph.
function F.roundCore(g, o)
	o = o or {}
	local rings = o.rings or { 90, 180, 270 }
	local counts = o.counts or { 6, 10, 14 }
	local rot = o.angle or 0
	local c = OG.addNode(g, nil, 0, 0, 20)
	local ringIds = {}
	for ri, r in ipairs(rings) do
		ringIds[ri] = {}
		local n = counts[ri]
		for k = 0, n - 1 do
			local a = rot + k / n * 2 * math.pi + 0.15 * math.sin(k * 2.3 + ri)
			local rr = r * (1 + 0.08 * math.sin(k * 1.7 + ri * 3))
			ringIds[ri][k] = OG.addNode(g, nil, rr * math.cos(a), rr * math.sin(a), 20).id
		end
		for k = 0, n - 1 do OG.addEdge(g, nil, ringIds[ri][k], ringIds[ri][(k + 1) % n], "small") end
	end
	-- radials: centre to ring 1, ring i to nearest node on ring i+1
	for k = 0, counts[1] - 1 do OG.addEdge(g, nil, c.id, ringIds[1][k], "small") end
	for ri = 1, #rings - 1 do
		for k = 0, counts[ri] - 1 do
			local a = g.nodeById[ringIds[ri][k]]
			local best, bd = nil, math.huge
			for j = 0, counts[ri + 1] - 1 do
				local b = g.nodeById[ringIds[ri + 1][j]]
				local d = G.dist(a.x, a.y, b.x, b.y)
				if d < bd then best, bd = b, d end
			end
			OG.addEdge(g, nil, a.id, best.id, "small")
		end
	end
	-- stubs outward from every (stubStep-th) outer node
	local last = #rings
	for k = 0, counts[last] - 1, (o.stubStep or 1) do
		local a = g.nodeById[ringIds[last][k]]
		local r = math.sqrt(a.x * a.x + a.y * a.y)
		local d = OG.addNode(g, nil, a.x * (1 + 50 / r), a.y * (1 + 50 / r), 20)
		OG.addEdge(g, nil, a.id, d.id, "small")
	end
	return g
end

--- House proxy (SHAPES_BRIEF 2026-10-12): lots every 25 m on both sides of every street, the first n filled in
--- order of network distance from the node nearest the centre (town development spreads from the core along the
--- streets). Returns the houses' metrics (ot_metrics.segments) and their 90 % radius (the driver's extent).
function F.houses(g, n, cx, cy)
	cx, cy = cx or 0, cy or 0
	local start = OG.nearestNode(g, cx, cy, 1e9)
	local dist = { [start.id] = 0 }
	local done = {}
	while true do
		local best, bd = nil, math.huge
		for id, d in pairs(dist) do if not done[id] and d < bd then best, bd = id, d end end
		if not best then break end
		done[best] = true
		for _, eid in ipairs(g.adj[best]) do
			local e = g.edgeById[eid]
			local o = OG.other(e, best)
			local nd = bd + OG.edgeLength(g, e)
			if dist[o] == nil or nd < dist[o] then dist[o] = nd end
		end
	end
	local lots = {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		local l = OG.edgeLength(g, e)
		local k = math.floor(l / 25)
		for i = 1, k do
			local t = (i - 0.5) / k
			local x, y = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
			local d = math.min((dist[e.n0] or 1e9) + l * t, (dist[e.n1] or 1e9) + l * (1 - t))
			lots[#lots + 1] = { x, y, d }
			lots[#lots + 1] = { x, y, d }
		end
	end
	table.sort(lots, function(p, q) return p[3] < q[3] end)
	local segs, ds = {}, {}
	for i = 1, math.min(n, #lots) do
		local p = lots[i]
		segs[#segs + 1] = { p[1] - 1, p[2], p[1] + 1, p[2] }
		ds[#ds + 1] = math.sqrt((p[1] - cx) ^ 2 + (p[2] - cy) ^ 2)
	end
	table.sort(ds)
	local r90 = ds[math.max(1, math.floor(#ds * 0.9 + 0.5))] or 0
	return MT.segments(segs, cx, cy), r90
end

--- In-game house arrival (Showcase v7): fill the first n lots (25 m, both sides) in order of network distance from
--- the node nearest the centre, and set each edge's `built` (houses on it) and `g.hasBuilt`, as the driver's
--- snapshot does from the parcels. The game fills by demand from the core outward, so streets far out stay empty.
function F.markBuilt(g, n, cx, cy)
	cx, cy = cx or 0, cy or 0
	local start = OG.nearestNode(g, cx, cy, 1e9)
	local dist = { [start.id] = 0 }
	local done = {}
	while true do
		local best, bd = nil, math.huge
		for id, d in pairs(dist) do if not done[id] and d < bd then best, bd = id, d end end
		if not best then break end
		done[best] = true
		for _, eid in ipairs(g.adj[best]) do
			local e = g.edgeById[eid]
			local o = OG.other(e, best)
			local nd = bd + OG.edgeLength(g, e)
			if dist[o] == nil or nd < dist[o] then dist[o] = nd end
		end
	end
	local lots = {}
	for _, e in ipairs(g.edges) do
		e.built = 0
		local l = OG.edgeLength(g, e)
		local k = math.floor(l / 25)
		for i = 1, k do
			local t = (i - 0.5) / k
			local d = math.min((dist[e.n0] or 1e9) + l * t, (dist[e.n1] or 1e9) + l * (1 - t))
			lots[#lots + 1] = { e, d }
			lots[#lots + 1] = { e, d }
		end
	end
	table.sort(lots, function(p, q) return p[2] < q[2] end)
	for i = 1, math.min(n, #lots) do lots[i][1].built = lots[i][1].built + 1 end
	g.hasBuilt = true
	return g
end

--- The in-game street snapshot before 2026-10-12: only the edges within R of the centre (the driver used the
--- building extent + 300 m); nodes whose true degree is cut off are not joinable (noJoin). Node and edge ids kept.
function F.snapshotCut(g, R)
	local sg = OG.new()
	local keep = {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		if math.sqrt(a.x ^ 2 + a.y ^ 2) <= R or math.sqrt(b.x ^ 2 + b.y ^ 2) <= R then keep[#keep + 1] = e end
	end
	local deg = {}
	for _, e in ipairs(keep) do
		for _, id in ipairs({ e.n0, e.n1 }) do
			if not sg.nodeById[id] then local n = g.nodeById[id]; OG.addNode(sg, id, n.x, n.y, n.z) end
			deg[id] = (deg[id] or 0) + 1
		end
		OG.addEdge(sg, e.id, e.n0, e.n1, e.class, true, e.t0, e.t1)
	end
	for id, d in pairs(deg) do if d < #g.adj[id] then sg.nodeById[id].noJoin = true end end
	return sg
end

--- Number of connected components of the graph's edges.
function F.components(g)
	local seen, count = {}, 0
	for _, n in ipairs(g.nodes) do
		if not seen[n.id] and OG.degree(g, n.id) > 0 then
			count = count + 1
			local stack = { n.id }
			seen[n.id] = true
			while #stack > 0 do
				local id = stack[#stack]
				stack[#stack] = nil
				for _, eid in ipairs(g.adj[id]) do
					local o = OG.other(g.edgeById[eid], id)
					if not seen[o] then seen[o] = true; stack[#stack + 1] = o end
				end
			end
		end
	end
	return count
end

--- First pair of edges whose chords properly cross (nil if none).
function F.crossingPair(g)
	for i = 1, #g.edges do
		local e = g.edges[i]
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		for j = i + 1, #g.edges do
			local f = g.edges[j]
			if f.n0 ~= e.n0 and f.n0 ~= e.n1 and f.n1 ~= e.n0 and f.n1 ~= e.n1 then
				local c, d = g.nodeById[f.n0], g.nodeById[f.n1]
				if G.segIntersect(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y, 1e-4) then return e, f end
			end
		end
	end
	return nil
end

--- Smallest angle (degrees) between two edges at any node.
function F.minAngle(g)
	local worst = 180
	for _, n in ipairs(g.nodes) do
		local hs = {}
		for _, eid in ipairs(g.adj[n.id]) do hs[#hs + 1] = OG.headingFrom(g, g.edgeById[eid], n.id) end
		for i = 1, #hs do
			for j = i + 1, #hs do
				local d = math.deg(G.angleDiff(hs[i], hs[j]))
				if d < worst then worst = d end
			end
		end
	end
	return worst
end

--- Longest and shortest edge chord.
function F.edgeLengths(g)
	local lo, hi = math.huge, 0
	for _, e in ipairs(g.edges) do
		local l = OG.edgeLength(g, e)
		if l < lo then lo = l end
		if l > hi then hi = l end
	end
	return lo, hi
end

--- Serialises an increment list to a string (determinism checks).
function F.dump(incs)
	local parts = {}
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			parts[#parts + 1] = string.format("%d:%d:%d:%.3f,%.3f:%.3f,%.3f:%s", e.entity, e.node0, e.node1,
				e.p0[1], e.p0[2], e.p1[1], e.p1[2], e.class)
		end
		parts[#parts + 1] = "|"
	end
	return table.concat(parts, ";")
end

return F
