-- Organic Towns: one-way rings at the plan's own new crossings (pure; 2026-10-14, the roundabout town, CHARACTERS_BRIEF
-- "roundabout town", NEXT_PHASE_BRIEF 54).
--
-- User: "one character could push roundabouts more"; earlier: "a roundabout built with a regular two-way street isn't a
-- real roundabout". So the ring is one-way (counter-clockwise: right-hand traffic), in the one-way town street template
-- square_roundabouts' own geometry uses, with every ring node's lane connections in the engine's own one-way ring
-- pattern (ot_proposal.junctionConnsDir; docs/findings/roads.md "Junction lane connections").
--
-- Where (RG.mark, on a planned increment before it is pre-checked): a NEW node of the increment where 3 or 4 of its new
-- streets meet (never an existing node: a live junction is never rebuilt, findings towns.md: removing town edges
-- demolishes houses, replacing nodes with 2+ edges crashed), the arms at least ARM_GAP apart, every arm long enough to
-- give up the ring's radius, and the spot still empty: no existing street or node within the ring + CLEAR, no other new
-- street of the increment within the ring + CLEAR (the spot is reserved while it is empty land at the frontier). The
-- ring replaces the crossing node: each arm ends on the ring (its Hermite curve cut where it meets the ring, so the arm
-- keeps its own course), the ring's arcs join the arm points counter-clockwise (an arc wider than ARC_MAX gets ring
-- nodes between). Every new node gets a node config in ot_proposal.build (the crash rule): the arm nodes the one-way
-- pattern over ring in / ring out / arm, the ring's in-between nodes ring in -> ring out.
--
-- Sizes: square_roundabouts' presets (geom.build with sqrb_radius_size 1..3: XS / S / M, the ring's centreline radius
-- `a` and its ring template), loaded through its presence file (RG.load); without that mod the roundabout town is not
-- picked (ot_character `why=noRoundabouts`). Main x main crossings take S / M, a crossing of minor streets the mini XS.
--
-- All or nothing: the original increment is kept on inc.ringUndo; a refused pre-check sends the plain crossing again
-- (RG.strip, the driver's send stage). Every number goes through z0 (findings "Negative zero").
--
-- Roundabout variety and rings in every town (2026-10-14, NEXT_PHASE_BRIEF 56; user on the showcase run
-- 2026-10-14_2150: "it would be nice if there were different sized roundabouts used. also, roundabouts shouldnt be
-- limited to just that roundabout town ... perhaps a pair of round abouts added at same time on opposite parts of a
-- city, or street, for a unique intentional effect"):
--   sizes   four classes from square_roundabouts' own radius list (geom.RADII, the island radius; the ring's centreline
--           radius `a` = it + the one-way small street's offset 9 m): mini R 17 (a crossing of minor streets; the
--           smallest the geometry gives), s R 19 / 24 (one main arm, or two medium), m R 34 / 39 (main x main), l R 49 /
--           59 (a gateway on a main street at the town's edge, main x main with wide arms, three main arms). The class
--           by the crossing (RG.classOf), the radius within it seeded, smaller sizes tried when the room is short.
--   rates   every town may get rings (RG.rate: by era and region; rare before 1960, common in France / Europe from the
--           1970s, few in the US, none in JP dense towns); the roundabout town many more (RG.TOWN), gateways too.
--   pairs   two rings in one increment, at the two ends of one main street (RG.pairOf "street") or on opposite sides
--           of the town ("opposite"), the same size: both or neither (RB event=pair).
--   empty   a ring whose arms end farther than o.armLead from a street with houses is never placed (`emptyArm`).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"

local RG = {}

RG.ON = true
RG.PRESENCE = "square_roundabouts::/square_roundabouts_presence.lua"
RG.GEOM = "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"
RG.SIZES = { 1, 2, 3 }
RG.SIZE_NAMES = { "XS", "S", "M" }
RG.ONEWAY = "::/infrastructure/street/town/town_new_one_way_small.street_template"
RG.ARM_GAP = math.rad(55)   -- arms at least this far apart in heading
RG.ARC_MAX = math.rad(110)  -- a ring arc spans at most this (else ring nodes between)
RG.CLEAR = 18               -- m beyond the ring: no other street (new or existing) or node this close
RG.ARM_MIN = 22             -- m: an arm keeps at least this length beyond the ring
RG.MAX_PER_INC = 2          -- rings per increment at most
RG.MAIN_SIZE = 2            -- (presets, RG.load sizes: S)
RG.MINI_SIZE = 1            -- (presets: XS)
-- size classes (2026-10-14 §56): square_roundabouts geom.RADII values (island radius, m) per class
RG.CLASSES = { "mini", "s", "m", "l" }
RG.CLASS_RADII = { mini = { 8 }, s = { 10, 15 }, m = { 25, 30 }, l = { 40, 50 } }
RG.RANK = { mini = 1, s = 2, m = 3, l = 4 }
RG.GATE_F = 0.8             -- x the houses' radius: a major crossing this far out is a gateway
RG.GATE_MIN = 140           -- m: ... and at least this far from the centre
RG.SPACING = 260            -- m between rings of an ordinary town (existing or new; a pair's two excepted)
RG.PAIR_MIN = 120           -- m: a pair's rings at least this far apart
RG.PAIR_ALIGN = math.rad(22) -- "street" pair: a major arm of each points at the other within this
RG.PAIR_OPPOSITE = math.rad(120) -- "opposite" pair: this far apart around the centre at least
-- deferred pairs (2026-10-14 §56 follow-up: a pair in one increment was rare, the plan's increments are local): a ring
-- placed alone may reserve its partner along its street (o.canDefer; the driver saves it on the frame, `pp*`), placed in
-- a later increment at a crossing PAIR_MIN..PAIR_REACH m on along the street's heading (within PAIR_DEFER_ALIGN) whose
-- arm points back; the reservation lapses after PAIR_WAIT of the town's plans.
RG.PAIR_REACH = 700
RG.PAIR_DEFER_ALIGN = math.rad(30)
RG.PAIR_WAIT = 4
RG.PAIR_WAIT_HUB = 8        -- plans a roundabout town's hub waits for its twin (§57; 6 until round 3)
RG.PAIR_HUB_ALIGN = math.rad(40)   -- a hub twin's window: within this of its street (both ways) or of the way across
RG.PAIR_REACH_OPP = 1600    -- m: an "opposite" twin (k = 2) across the town at most this far
RG.HUB_TRIES = 6            -- hub sites tried a plan
RG.ARM_LEAD = 200           -- m: every arm's far end within this of a street with houses (no arms into empty land)
-- the roundabout town (ot_character roundabout_town): shares and limits
RG.TOWN = { main = 0.95, mini = 0.5, gate = 1, pair = 0.6, pairMinor = true, max = 4, spacing = 110, cap = 40, hubs = true }
-- every other town (RG.rate): the major-crossing share by region at full era, minor crossings x MINOR_K
RG.RATE = { france = 0.16, EU = 0.09, MED = 0.08, NORDIC = 0.06, RU = 0.04, OCEANIA = 0.08, US = 0.02, JP = 0.015,
	EAST_ASIA = 0.03, ASIA = 0.03, MIXED = 0.06, default = 0.05 }
RG.RATE_NONE = { JP_DENSE = true }   -- styles with no rings (dense Japanese cores)
RG.ERA_FROM, RG.ERA_RARE, RG.ERA_FULL = 1940, 1960, 1975   -- none before (no one-way town street), x RARE_K to 1960,
RG.RARE_K = 0.15                                          -- then rising to the full rate by ERA_FULL
-- (2026-10-14, the seed-a usa run (1960 start): ordinary US towns drew at 0.00; modern US towns build a few: the late
-- rate rises from the region's full rate at ERA_FULL to RATE_LATE by ERA_LATE)
RG.ERA_LATE = 1995
RG.RATE_LATE = { US = 0.05, OCEANIA = 0.1 }
RG.MINOR_K = 0.15
RG.GATE_K = 1.6
-- (an ordinary town's pair share: drawn once per pair, i.e. per candidate pair in an increment and once per placed ring for
-- its later twin; 1.5 until 2026-10-14 §57: 7 pair draws of the 2237 showcase at 0.14, none came; still rare)
RG.PAIR_K = 2
RG.PAIR_MAX = 0.3
RG.ORDINARY = { max = 2, cap = 4 }  -- rings per increment / per town (counted in the graph, RG.existing) for an ordinary town
RG.SAMPLES = 12             -- Hermite samples per edge (clearance checks)

local z0 = G.z0

--- Loads the ring sizes from square_roundabouts (req = ug_require): { sizes = { [i] = { R, template, name } } } or nil,
--- why ("noMod" | "noGeometry" | "noSizes").
function RG.load(req)
	if not RG.ON then return nil, "off" end
	req = req or ug_require
	local okP = pcall(req, RG.PRESENCE)
	if not okP then return nil, "noMod" end
	local okG, geom = pcall(req, RG.GEOM)
	if not okG or type(geom) ~= "table" or type(geom.build) ~= "function" or type(geom.readParams) ~= "function" then
		return nil, "noGeometry"
	end
	local out = { sizes = {} }
	for i, size in ipairs(RG.SIZES) do
		local ok, b = pcall(function() return geom.build(geom.readParams({ sqrb_arms = 3, sqrb_radius_size = size })) end)
		if ok and type(b) == "table" and tonumber(b.a) and b.a > 0 then
			local tpl = RG.ONEWAY
			for _, l in ipairs(b.lists or {}) do
				if l.role == "ring" and type(l.template) == "string" then tpl = l.template end
			end
			-- (only the small one-way town street: its lanes are what junctionConnsDir and the lane checks know)
			if tpl ~= RG.ONEWAY then tpl = RG.ONEWAY end
			out.sizes[i] = { R = b.a, template = tpl, name = RG.SIZE_NAMES[i] }
		end
	end
	-- the size classes (2026-10-14 §56): the island radii of RG.CLASS_RADII through the full radius list (sqrb_radius)
	out.classes = {}
	local radii = type(geom.RADII) == "table" and geom.RADII or {}
	for _, cl in ipairs(RG.CLASSES) do
		local list = {}
		for _, r in ipairs(RG.CLASS_RADII[cl]) do
			local idx = nil
			for i, v in ipairs(radii) do if v == r then idx = i end end
			if idx then
				local ok, b = pcall(function() return geom.build(geom.readParams({ sqrb_arms = 3, sqrb_radius = idx })) end)
				if ok and type(b) == "table" and tonumber(b.a) and b.a > 0 then
					list[#list + 1] = { R = b.a, template = RG.ONEWAY, name = cl, class = cl, island = r }
				end
			end
		end
		if #list > 0 then out.classes[cl] = list end
	end
	-- (a geometry without the full radius list: the presets stand in, XS as mini / s, S as m, M as l)
	if next(out.classes) == nil then
		local map = { mini = 1, s = 1, m = 2, l = 3 }
		for cl, i in pairs(map) do
			local sz = out.sizes[i]
			if sz then out.classes[cl] = { { R = sz.R, template = sz.template, name = cl, class = cl } } end
		end
	end
	if out.sizes[1] == nil and out.sizes[2] == nil and next(out.classes) == nil then return nil, "noSizes" end
	return out
end

--- The ring share for a town that is not a roundabout town (o = { year, region, country, style }): { main, mini, gate,
--- pair, max, spacing, cap, rate } or nil, why (era, a style without rings, a zero rate).
function RG.rate(o)
	o = o or {}
	if o.style and RG.RATE_NONE[o.style] then return nil, "style:" .. tostring(o.style) end
	local y = tonumber(o.year) or 1960
	if y < RG.ERA_FROM then return nil, "era" end
	local base = (o.country == "france" and RG.RATE.france) or RG.RATE[o.region or ""] or RG.RATE.default
	local k
	if y < RG.ERA_RARE then k = RG.RARE_K
	elseif y >= RG.ERA_FULL then k = 1
	else k = RG.RARE_K + (1 - RG.RARE_K) * (y - RG.ERA_RARE) / (RG.ERA_FULL - RG.ERA_RARE) end
	local late = RG.RATE_LATE[o.region or ""]
	if late and y > RG.ERA_FULL and o.country ~= "france" then
		base = base + (late - base) * math.min(1, (y - RG.ERA_FULL) / (RG.ERA_LATE - RG.ERA_FULL))
	end
	local r = base * k
	if r <= 0 then return nil, "rate" end
	return { main = r, mini = r * RG.MINOR_K, gate = math.min(1, r * RG.GATE_K), pair = math.min(RG.PAIR_MAX, r * RG.PAIR_K),
		max = RG.ORDINARY.max, spacing = RG.SPACING, cap = RG.ORDINARY.cap, rate = r }
end

--- The roundabout town's shares (a copy of RG.TOWN; ot_character's p.rings may override main / mini).
function RG.townShare(rings)
	local out = {}
	for k, v in pairs(RG.TOWN) do out[k] = v end
	if type(rings) == "table" then
		for k, v in pairs(rings) do out[k] = v end
	end
	out.town = true
	return out
end

--- Ring centres already in graph g: the one-way small town street edges grouped by the nodes they share (one ring's
--- arcs form a closed chain; §57 round 3: grouping by 90 m from a first edge split an l ring (R 49 / 59) in two, which
--- the spacing and the town's cap then counted twice). { { x, y, n } } (centre = the mean of the ring nodes).
function RG.existing(g)
	local res = {}
	if g == nil then return res end
	local parent = {}
	local function root(x)
		local r = x
		for _ = 1, 100000 do
			if parent[r] == nil or parent[r] == r then break end
			r = parent[r]
		end
		return r
	end
	local ringEdges = {}
	for _, e in ipairs(g.edges or {}) do
		local t = e.template
		if type(t) == "string" and t:find("town_new_one_way_small", 1, true) and g.nodeById[e.n0] and g.nodeById[e.n1] then
			ringEdges[#ringEdges + 1] = e
			parent[e.n0], parent[e.n1] = parent[e.n0] or e.n0, parent[e.n1] or e.n1
			local a, b = root(e.n0), root(e.n1)
			if a ~= b then parent[a] = b end
		end
	end
	local groups, order = {}, {}
	for _, e in ipairs(ringEdges) do
		local r = root(e.n0)
		local gr = groups[r]
		if gr == nil then gr = { nodes = {}, n = 0, sx = 0, sy = 0, edges = 0 }; groups[r] = gr; order[#order + 1] = r end
		gr.edges = gr.edges + 1
		for _, id in ipairs({ e.n0, e.n1 }) do
			if not gr.nodes[id] then
				gr.nodes[id] = true
				local nd = g.nodeById[id]
				gr.sx, gr.sy, gr.n = gr.sx + nd.x, gr.sy + nd.y, gr.n + 1
			end
		end
	end
	for _, r in ipairs(order) do
		local gr = groups[r]
		if gr.edges >= 2 then res[#res + 1] = { x = gr.sx / gr.n, y = gr.sy / gr.n, n = gr.edges } end
	end
	return res
end

--- The crossing's size class (c from RG.candidates: main / med arm counts, wide, gate).
function RG.classOf(c)
	local main, med = c.main or 0, c.med or 0
	if (c.gate and main >= 2) or (main >= 2 and c.wide) or main >= 3 then return "l" end
	if main >= 2 or (main >= 1 and (c.gate or med >= 1 or #(c.edges or {}) >= 4)) then return "m" end
	if main >= 1 or med >= 2 then return "s" end
	return "mini"
end

--- A major crossing (main / medium streets): the `main` share; else the `mini` one.
function RG.major(c) return (c.main or 0) >= 1 or (c.med or 0) >= 2 end

--- The sizes to try for class cl: its seeded radius and the smaller ones of the class, then the smaller classes'
--- (largest first).
function RG.sizesFor(geo, cl, u)
	local out = {}
	local cls = geo and geo.classes or {}
	local rank = RG.RANK[cl] or 1
	for r = rank, 1, -1 do
		local list = cls[RG.CLASSES[r]]
		if list and #list > 0 then
			local n = #list
			-- (the seeded radius of the class, then only smaller ones: the room decides downward)
			local first = (r == rank) and math.min(n, math.floor((u or 0) * n) + 1) or n
			for i = first, 1, -1 do out[#out + 1] = list[i] end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Hermite helpers (3D points / tangents)

local function herm(e, t)
	local t2, t3 = t * t, t * t * t
	local h00, h10, h01, h11 = 2 * t3 - 3 * t2 + 1, t3 - 2 * t2 + t, -2 * t3 + 3 * t2, t3 - t2
	local out = {}
	for k = 1, 3 do
		out[k] = h00 * (e.p0[k] or 0) + h10 * (e.t0[k] or 0) + h01 * (e.p1[k] or 0) + h11 * (e.t1[k] or 0)
	end
	return out
end

local function hermD(e, t)
	local t2 = t * t
	local d00, d10, d01, d11 = 6 * t2 - 6 * t, 3 * t2 - 4 * t + 1, -6 * t2 + 6 * t, 3 * t2 - 2 * t
	local out = {}
	for k = 1, 3 do
		out[k] = d00 * (e.p0[k] or 0) + d10 * (e.t0[k] or 0) + d01 * (e.p1[k] or 0) + d11 * (e.t1[k] or 0)
	end
	return out
end
RG.herm, RG.hermD = herm, hermD

local function pts(e, n)
	local out = {}
	n = n or RG.SAMPLES
	for i = 0, n do out[#out + 1] = herm(e, i / n) end
	return out
end

--- The parameter on edge e where it leaves the circle of radius R around (cx, cy), from the end at the centre
--- (`atStart`: node0 is the centre). Bisection (40 steps). nil when the edge never leaves it.
local function cutParam(e, cx, cy, R, atStart)
	local function d(t) local p = herm(e, t); return G.dist(p[1], p[2], cx, cy) end
	local inT, outT = atStart and 0 or 1, atStart and 1 or 0
	if d(outT) <= R then return nil end
	for _ = 1, 40 do
		local m = (inT + outT) / 2
		if d(m) <= R then inT = m else outT = m end
	end
	return (inT + outT) / 2
end

local function v3(a) return { z0(G.round(a[1], 0.001)), z0(G.round(a[2], 0.001)), z0(G.round(a[3] or 0, 0.001)) } end
local function scale(a, k) return { a[1] * k, a[2] * k, (a[3] or 0) * k } end

--- The edge e cut to the part outside the ring (the far end kept): a new edge table (same fields) or nil.
function RG.trim(e, centreId, cx, cy, R)
	local atStart = e.node0 == centreId
	local t = cutParam(e, cx, cy, R, atStart)
	if t == nil then return nil end
	local p, dp = herm(e, t), hermD(e, t)
	local out = {}
	for k, v in pairs(e) do out[k] = v end
	if atStart then
		local f = 1 - t
		out.p0, out.t0, out.t1 = v3(p), v3(scale(dp, f)), v3(scale(e.t1, f))
	else
		local f = t
		out.p1, out.t1, out.t0 = v3(p), v3(scale(dp, f)), v3(scale(e.t0, f))
	end
	-- (the arc length again, sampled)
	local L, prev = 0, nil
	for _, q in ipairs(pts(out, 16)) do
		if prev then L = L + G.dist(prev[1], prev[2], q[1], q[2]) end
		prev = q
	end
	out.length = L
	out.ringArm = true
	return out, p
end

---------------------------------------------------------------------------
-- candidates

--- Heading of edge e leaving node id (2D, from its tangent).
local function leaving(e, id)
	if e.node0 == id then return G.atan2(e.t0[2], e.t0[1]) end
	return G.atan2(-e.t1[2], -e.t1[1])
end

--- Candidate crossings of an increment: { { node (entity), x, y, z, edges = { edge }, main = count, wide = bool } }
--- (new nodes with 3-4 new edges, arms ARM_GAP apart).
function RG.candidates(inc)
	local at = {}
	for _, e in ipairs(inc.edges or {}) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n < 0 then
				at[n] = at[n] or {}
				local l = at[n]
				l[#l + 1] = e
			end
		end
	end
	local out = {}
	for _, nd in ipairs(inc.nodes or {}) do
		local l = at[nd.entity]
		if l and (#l == 3 or #l == 4) then
			local hs = {}
			local self2 = false
			for _, e in ipairs(l) do
				if e.node0 == e.node1 then self2 = true end
				hs[#hs + 1] = G.wrap(leaving(e, nd.entity))
			end
			table.sort(hs)
			local okGap = not self2
			for i = 1, #hs do
				local a, b = hs[i], hs[i % #hs + 1]
				local gap = b - a
				if i == #hs then gap = gap + 2 * math.pi end
				if gap < RG.ARM_GAP then okGap = false end
			end
			if okGap then
				local main, med, wide, heads, allHeads = 0, 0, false, {}, {}
				for _, e in ipairs(l) do
					allHeads[#allHeads + 1] = leaving(e, nd.entity)
					if e.class == "main" then main = main + 1 end
					if e.class == "medium" then med = med + 1 end
					if e.class == "main" or e.class == "medium" then heads[#heads + 1] = leaving(e, nd.entity) end
					if type(e.template) == "string" and e.template:find("_large", 1, true) then wide = true end
				end
				out[#out + 1] = { node = nd.entity, x = nd.x, y = nd.y, z = nd.z, edges = l, main = main, med = med, wide = wide,
					heads = heads, allHeads = allHeads }
			end
		end
	end
	table.sort(out, function(a, b) return a.node > b.node end)   -- (the plan's first new nodes first)
	return out
end

--- Is the ring at (cx, cy) of radius R clear? Other new edges of inc (not the arms) and the graph's existing nodes /
--- edges keep R + CLEAR off its centre. Returns ok, why.
function RG.clear(inc, g, c, R)
	local need = R + RG.CLEAR
	local armSet = {}
	for _, e in ipairs(c.edges) do armSet[e] = true end
	for _, e in ipairs(inc.edges or {}) do
		if not armSet[e] then
			for _, p in ipairs(pts(e, RG.SAMPLES)) do
				if G.dist(p[1], p[2], c.x, c.y) < need then return false, "nearNew" end
			end
		end
	end
	if g then
		for _, n in ipairs(g.nodes or {}) do
			if G.dist(n.x, n.y, c.x, c.y) < need + 10 then return false, "nearNode" end
		end
		for _, e in ipairs(g.edges or {}) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				if (G.pointSegDist(c.x, c.y, a.x, a.y, b.x, b.y)) < need then return false, "nearStreet" end
				-- (a curved existing street: its Hermite curve, not only its chord; §57 round 2, the 2347 run's refused
				-- pair at Shape fan, Collision x4, with every chord clear)
				if e.t0 and e.t1 and G.dist(a.x, a.y, c.x, c.y) < need + 200 then
					local he = { p0 = { a.x, a.y, 0 }, p1 = { b.x, b.y, 0 }, t0 = { e.t0[1] or e.t0.x or 0, e.t0[2] or e.t0.y or 0, 0 },
						t1 = { e.t1[1] or e.t1.x or 0, e.t1[2] or e.t1.y or 0, 0 } }
					for _, p in ipairs(pts(he, 8)) do
						if G.dist(p[1], p[2], c.x, c.y) < need then return false, "nearCurve" end
					end
				end
			end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- the ring

--- Ring arcs (CCW) through the arm points around (cx, cy): returns nodes { {x, y, z, arm = index or nil} } in CCW order
--- and arcs { { from = node index, to = node index, p0, t0, p1, t1, length } }.
function RG.arcs(cx, cy, R, armPts)
	local list = {}
	for i, p in ipairs(armPts) do
		list[#list + 1] = { a = G.wrap(G.atan2(p[2] - cy, p[1] - cx)), x = p[1], y = p[2], z = p[3] or 0, arm = i }
	end
	table.sort(list, function(a, b) return a.a < b.a end)
	local nodes = {}
	for k, n in ipairs(list) do
		nodes[#nodes + 1] = n
		local nx = list[k % #list + 1]
		local gap = nx.a - n.a
		if k == #list then gap = gap + 2 * math.pi end
		local m = math.ceil(gap / RG.ARC_MAX - 1e-9)
		for j = 1, m - 1 do
			local a = n.a + gap * j / m
			nodes[#nodes + 1] = { a = a, x = cx + R * math.cos(a), y = cy + R * math.sin(a),
				z = n.z + (nx.z - n.z) * j / m }
		end
	end
	local arcs = {}
	for k, n in ipairs(nodes) do
		local nx = nodes[k % #nodes + 1]
		local gap = G.wrap(nx.a - n.a)
		if gap <= 0 then gap = gap + 2 * math.pi end
		local L = 4 * R * math.tan(gap / 4)
		local d0 = { -math.sin(n.a), math.cos(n.a) }
		local d1 = { -math.sin(nx.a), math.cos(nx.a) }
		local dz = (nx.z or 0) - (n.z or 0)
		arcs[#arcs + 1] = { from = k, to = k % #nodes + 1,
			p0 = v3({ n.x, n.y, n.z }), p1 = v3({ nx.x, nx.y, nx.z }),
			t0 = v3({ d0[1] * L, d0[2] * L, dz }), t1 = v3({ d1[1] * L, d1[2] * L, dz }), length = R * gap }
	end
	return nodes, arcs
end

local function copyInc(inc)
	local function cp(t)
		if type(t) ~= "table" then return t end
		local o = {}
		for k, v in pairs(t) do o[k] = cp(v) end
		return o
	end
	return { nodes = cp(inc.nodes), edges = cp(inc.edges), joins = cp(inc.joins), stats = cp(inc.stats) }
end

--- Renumbers an increment: edges -1..-E, new nodes -(E+1).. in their order; joins from the edges.
local function renumber(inc)
	local E = #inc.edges
	local map, nextId = {}, -(E + 1)
	for _, n in ipairs(inc.nodes) do
		map[n.entity] = nextId
		n.entity = nextId
		nextId = nextId - 1
	end
	local joins, total = {}, 0
	for i, e in ipairs(inc.edges) do
		e.entity = -i
		if e.node0 < 0 then e.node0 = map[e.node0] end
		if e.node1 < 0 then e.node1 = map[e.node1] end
		if e.node0 > 0 then joins[#joins + 1] = { node = e.node0, edge = -i } end
		if e.node1 > 0 then joins[#joins + 1] = { node = e.node1, edge = -i } end
		total = total + (e.length or 0)
	end
	inc.joins = joins
	inc.stats = { edges = #inc.edges, nodes = #inc.nodes, length = total }
end

-- Longer arms for the larger rings (2026-10-14 §56 follow-up: offline, m / l fell back to s on short plan edges): an arm
-- whose far end is a new node with exactly one more new edge going on (a plain continuation within EXTEND_TURN) is
-- merged with that edge into one Hermite edge (the node dropped), at most EXTEND_MAX times per arm, until the arm
-- reaches `need` m from the crossing. Only new nodes of the increment: never an existing (live) one.
RG.EXTEND_TURN = math.rad(35)
RG.EXTEND_MAX = 3

local function unit2(v)
	local l = math.sqrt((v[1] or 0) ^ 2 + (v[2] or 0) ^ 2)
	if l < 1e-9 then return nil end
	return { v[1] / l, v[2] / l }
end
--- Direction of travel leaving node n along e, and arriving at node n along e (unit 2D or nil).
local function leaveDir(e, n)
	if e.node0 == n then return unit2(e.t0) end
	return unit2({ -e.t1[1], -e.t1[2] })
end
local function arriveDir(e, n)
	if e.node1 == n then return unit2(e.t1) end
	return unit2({ -e.t0[1], -e.t0[2] })
end
local function endPt(e, n) if e.node0 == n then return e.p0 end return e.p1 end

--- Extends crossing c's arms in inc (see above). Returns the number of merges (inc renumbered when > 0).
function RG.extendArms(inc, c, need)
	local merges = 0
	local at = {}
	local function index()
		at = {}
		for _, e in ipairs(inc.edges) do
			for _, n in ipairs({ e.node0, e.node1 }) do
				if n < 0 then at[n] = at[n] or {}; at[n][#at[n] + 1] = e end
			end
		end
	end
	index()
	for _, arm in ipairs(c.edges) do
		local e = arm
		for _ = 1, RG.EXTEND_MAX do
			local f = (e.node0 == c.node) and e.node1 or e.node0
			if f >= 0 or f == c.node then break end
			local fp = endPt(e, f)
			if G.dist(fp[1], fp[2], c.x, c.y) >= need then break end
			local l = at[f]
			if l == nil or #l ~= 2 then break end
			local e2 = (l[1] == e) and l[2] or l[1]
			if e2 == e or e2.ring or e2.node0 == e2.node1 then break end
			local far = (e2.node0 == f) and e2.node1 or e2.node0
			if far == c.node then break end
			local dIn, dOut = arriveDir(e, f), leaveDir(e2, f)
			if not (dIn and dOut) then break end
			if G.angleDiff(G.atan2(dIn[2], dIn[1]), G.atan2(dOut[2], dOut[1])) > RG.EXTEND_TURN then break end
			local dc, dfar = leaveDir(e, c.node), arriveDir(e2, far)
			if not (dc and dfar) then break end
			local pc, pf = endPt(e, c.node), endPt(e2, far)
			local L = G.dist(pc[1], pc[2], pf[1], pf[2])
			local dz = (pf[3] or 0) - (pc[3] or 0)
			local m = {}
			for k, v in pairs(e) do m[k] = v end
			if e.node0 == c.node then
				m.node0, m.node1 = c.node, far
				m.p0, m.p1 = v3(pc), v3(pf)
				m.t0, m.t1 = v3({ dc[1] * L, dc[2] * L, dz }), v3({ dfar[1] * L, dfar[2] * L, dz })
			else
				m.node0, m.node1 = far, c.node
				m.p0, m.p1 = v3(pf), v3(pc)
				m.t0, m.t1 = v3({ -dfar[1] * L, -dfar[2] * L, -dz }), v3({ -dc[1] * L, -dc[2] * L, -dz })
			end
			m.length = (e.length or 0) + (e2.length or 0)
			m.ringExtended = (e.ringExtended or 0) + 1
			local edges = {}
			for _, x in ipairs(inc.edges) do
				if x == e then edges[#edges + 1] = m elseif x ~= e2 then edges[#edges + 1] = x end
			end
			local nodes = {}
			for _, nd in ipairs(inc.nodes) do if nd.entity ~= f then nodes[#nodes + 1] = nd end end
			inc.edges, inc.nodes = edges, nodes
			merges = merges + 1
			e = m
			index()
		end
	end
	return merges
end

---------------------------------------------------------------------------
-- ring hubs (the roundabout town's own ring sites, 2026-10-14 §57; showcase run 2026-10-14_2237: 3 rings in 18
-- increments, 6 candidate crossings in all: its organic / grid increments rarely make a new crossing of 3-4 new streets,
-- and the seed-a usa run's NA grid roundabout town got 0 rings in 14 plans). The town makes its own: on a new street of
-- the increment (a plain continuation node of two new edges, or the middle of a long new edge, split) it adds 1-2 new
-- arms across the street, so the spot is a new crossing of 3-4 new streets, and puts the ring there in the same
-- increment. A hub keeps HUB_GAP_MIN..MAX (seeded per site) from every ring of the town; its class by the street it sits
-- on (a gateway on a main / medium street l, a main street m, a medium street s, a small one s or mini, seeded); no ring
-- fits: the arms come out again (the increment as planned). Grower-free: organic and grid towns alike. Every new node
-- is a plain new node of the increment (a node config in ot_proposal.build), never an existing one.
RG.HUB_GAP_MIN, RG.HUB_GAP_MAX = 220, 400   -- (250-450 until the 2347 run's round 2: about one ring a step)   -- m between a hub and every other ring of the town (seeded per site)
RG.HUB_PER_INC = 2          -- hubs a plan (a deferred pair's partner hub besides)
RG.HUB_TURN = math.rad(35)  -- a continuation node: the street turns at most this there
RG.HUB_SPLIT_MIN = 92       -- m: a new edge this long may be split at its middle for a hub (s / mini room each side)
RG.HUB_STUB = { mini = 55, s = 62, m = 78, l = 95 }   -- m: the new arms' length by class (the class's largest R + room)
RG.HUB_CLEAR = 16           -- m: a new arm keeps this far from every other street (existing or new) ...
RG.HUB_NODE_CLEAR = 26      -- ... and its end this far from every node
RG.HUB_GRADE = 0.09         -- the arm's grade at most
RG.HUB_STUB_CLASS = { main = "medium", medium = "small", small = "small" }
RG.HUB_MINI = 0.5           -- a hub on a small street: mini at this share, else s
RG.HUB_TRIES_ALL = 14       -- hub tries a plan in all (§57 round 2)
RG.HUB_MIX = { { "l", 0.2 }, { "m", 0.35 }, { "s", 0.3 }, { "mini", 0.15 } }   -- the wanted class's seeded mix
RG.HUB_SLIDE = { 32, 52, 76, 104 }   -- m beyond R: a dead-end hub's centre this far out along its street, nearest first
RG.HUB_DE_MAX = 40          -- dead ends looked at a plan at most (nearest the houses first)
RG.HUB_HOUSED = 170         -- m: a hub site at most this far from a street with houses (its arms within ARM_LEAD)

local function edgeHead(e, n)
	if e.node0 == n then return G.atan2(e.t0[2], e.t0[1]) end
	return G.atan2(-e.t1[2], -e.t1[1])
end

--- Hub sites of an increment: { { x, y, z, node = new node id (a continuation node) or nil, edge = e (split) or nil, h =
--- the street's heading, cls = the street's class } } (continuation nodes first, then long edges' midpoints).
function RG.hubSites(inc)
	local at = {}
	for _, e in ipairs(inc.edges or {}) do
		if not e.ring and e.node0 ~= e.node1 then
			for _, n in ipairs({ e.node0, e.node1 }) do
				if n < 0 then at[n] = at[n] or {}; at[n][#at[n] + 1] = e end
			end
		end
	end
	local rank = { main = 3, medium = 2, small = 1 }
	local out = {}
	for _, nd in ipairs(inc.nodes or {}) do
		local l = at[nd.entity]
		if l and #l == 2 and not nd.ring then
			local hIn = edgeHead(l[1], nd.entity) + math.pi
			local hOut = edgeHead(l[2], nd.entity)
			if G.angleDiff(hIn, hOut) <= RG.HUB_TURN then
				local cls = (rank[l[1].class] or 1) >= (rank[l[2].class] or 1) and l[1].class or l[2].class
				out[#out + 1] = { x = nd.x, y = nd.y, z = nd.z, node = nd.entity, h = hOut, cls = cls or "small",
					edges = { l[1], l[2] } }
			end
		end
	end
	for _, e in ipairs(inc.edges or {}) do
		if not e.ring and e.node0 ~= e.node1 and (e.length or 0) >= RG.HUB_SPLIT_MIN then
			local p, d = herm(e, 0.5), hermD(e, 0.5)
			out[#out + 1] = { x = p[1], y = p[2], z = p[3], edge = e, h = G.atan2(d[2], d[1]), cls = e.class or "small" }
		end
	end
	return out
end

--- The room round hub site st (m, up to HUB_L_ROOM + 20): the nearest point of another new edge of inc (not the
--- site's own street: its edges, or the edges sharing their street key) or node of g.
RG.HUB_L_ROOM = 80
function RG.room(inc, g, st)
	local best = RG.HUB_L_ROOM + 20
	local own, keys = {}, {}
	for _, e in ipairs(st.edges or { st.edge }) do own[e] = true; if e.key then keys[e.key] = true end end
	for _, e in ipairs(inc.edges or {}) do
		if not own[e] and not (e.key and keys[e.key]) then
			for _, p in ipairs(pts(e, 8)) do
				local d = G.dist(p[1], p[2], st.x, st.y)
				if d < best then best = d end
			end
		end
	end
	if g then
		for _, n in ipairs(g.nodes or {}) do
			local d = G.dist(n.x, n.y, st.x, st.y)
			if d < best then best = d end
		end
	end
	return best
end

--- The hub class for a site: l (a gateway on a main / medium street), m (main; a medium street at HUB_MEDIUM_M),
--- else s, mini / s (small, seeded u).
RG.HUB_MEDIUM_M = 0.5
function RG.hubClass(site, gate, u)
	if (site.cls == "main" or site.cls == "medium") and gate then return "l" end
	if site.cls == "main" then return "m" end
	if site.cls == "medium" then return (u or 0) < RG.HUB_MEDIUM_M and "m" or "s" end
	return (u or 0) < RG.HUB_MINI and "mini" or "s"
end

--- May a new arm run from the hub (x, y) along heading a for L m? Returns the end point { x, y, z } or nil, why. o.g
--- (existing streets / nodes), inc (other new streets), skip (the hub's own street edges), o.height(x, y).
local function stubOk(inc, o, site, a, L, R, skip)
	local ca, sa = math.cos(a), math.sin(a)
	local ex, ey = site.x + ca * L, site.y + sa * L
	local ez = site.z or 0
	if o.height then
		local okH, h = pcall(o.height, ex, ey)
		if okH and tonumber(h) and h == h then ez = h end
	end
	if math.abs(ez - (site.z or 0)) > RG.HUB_GRADE * L then return nil, "grade" end
	-- (no arm into empty land: its end near houses, as RG.armsOk wants every arm)
	if o.housedDist and o.housedDist(ex, ey) > (o.armLead or RG.ARM_LEAD) then return nil, "emptyArm" end
	local g = o.g
	-- (the part beyond the ring: the ring's own clearance is RG.clear's)
	local from = math.min(L - 4, R + 4)
	local steps = math.max(2, math.ceil((L - from) / 8))
	for i = 0, steps do
		local s = from + (L - from) * i / steps
		local x, y = site.x + ca * s, site.y + sa * s
		if g and OG.distToEdges(g, x, y, RG.HUB_CLEAR) then return nil, "nearStreet" end
		for _, e in ipairs(inc.edges or {}) do
			if not skip[e] then
				local prev = nil
				for _, q in ipairs(pts(e, 8)) do
					if prev and G.pointSegDist(x, y, prev[1], prev[2], q[1], q[2]) < RG.HUB_CLEAR then return nil, "nearNew" end
					prev = q
				end
			end
		end
	end
	if g then
		if OG.crossing(g, site.x + ca * from, site.y + sa * from, ex, ey) then return nil, "crosses" end
		for _, n in ipairs(g.nodes or {}) do
			if G.dist(n.x, n.y, ex, ey) < RG.HUB_NODE_CLEAR then return nil, "nearNode" end
		end
	end
	for _, n in ipairs(inc.nodes or {}) do
		if G.dist(n.x, n.y, ex, ey) < RG.HUB_NODE_CLEAR then return nil, "nearNode" end
	end
	return { ex, ey, ez }
end

--- Adds a hub at site (RG.hubSites) of class cl to inc: 1-2 new arms across the street (both sides when both are clear,
--- else the one; none: nil, why), the long edge split first when the site is a midpoint. Returns the hub node's
--- position { x, y } (inc renumbered) or nil, why. inc changes only on success.
function RG.addHub(inc, site, cl, o, R)
	local L = RG.HUB_STUB[cl] or RG.HUB_STUB.s
	-- (the site's edges by entity: a failed try before may have put back a copy of the increment)
	local ents = {}
	for _, e in ipairs(site.edges or { site.edge }) do ents[e.entity] = true end
	local skip, splitE = {}, nil
	for _, e in ipairs(inc.edges) do
		if ents[e.entity] then
			skip[e] = true
			if site.edge and e.entity == site.edge.entity then splitE = e end
		end
	end
	if site.edge and splitE == nil then return nil, "gone" end
	local ends = {}
	local why = "noArm"
	for _, side in ipairs({ 1, -1 }) do
		local p, w = stubOk(inc, o, site, site.h + side * math.pi / 2, L, R, skip)
		if p then ends[#ends + 1] = p else why = w end
	end
	if #ends == 0 then return nil, why end
	local low = 0
	for _, n in ipairs(inc.nodes) do if n.entity < low then low = n.entity end end
	for _, e in ipairs(inc.edges) do if e.entity < low then low = e.entity end end
	local hubId = site.node
	local edges, nodes = {}, {}
	for _, n in ipairs(inc.nodes) do nodes[#nodes + 1] = n end
	if hubId == nil then
		-- (split the long edge at its middle: two Hermite halves, the same street key)
		local e = splitE
		low = low - 1
		hubId = low
		local p, d = herm(e, 0.5), hermD(e, 0.5)
		local a, b = {}, {}
		for k, v in pairs(e) do a[k] = v; b[k] = v end
		a.node1, a.p1, a.t0, a.t1 = hubId, v3(p), v3(scale(e.t0, 0.5)), v3(scale(d, 0.5))
		b.node0, b.p0, b.t0, b.t1 = hubId, v3(p), v3(scale(d, 0.5)), v3(scale(e.t1, 0.5))
		a.length, b.length = (e.length or 0) / 2, (e.length or 0) / 2
		for _, x in ipairs(inc.edges) do
			if x == e then edges[#edges + 1] = a; edges[#edges + 1] = b else edges[#edges + 1] = x end
		end
		nodes[#nodes + 1] = { entity = hubId, x = z0(G.round(p[1], 0.001)), y = z0(G.round(p[2], 0.001)),
			z = z0(G.round(p[3] or 0, 0.001)) }
	else
		for _, x in ipairs(inc.edges) do edges[#edges + 1] = x end
	end
	local hx, hy, hz = site.x, site.y, site.z or 0
	for _, n in ipairs(nodes) do
		if n.entity == hubId then hx, hy, hz = n.x, n.y, n.z or hz end
	end
	local stubCls = RG.HUB_STUB_CLASS[site.cls] or "small"
	local tpl = o.templates and o.templates[stubCls] or nil
	for k, p in ipairs(ends) do
		low = low - 1
		local endId = low
		nodes[#nodes + 1] = { entity = endId, x = z0(G.round(p[1], 0.001)), y = z0(G.round(p[2], 0.001)),
			z = z0(G.round(p[3], 0.001)) }
		local dx, dy, dz = p[1] - hx, p[2] - hy, p[3] - hz
		edges[#edges + 1] = { entity = 0, node0 = hubId, node1 = endId, p0 = v3({ hx, hy, hz }), p1 = v3(p),
			t0 = v3({ dx, dy, dz }), t1 = v3({ dx, dy, dz }), class = stubCls, template = tpl, length = G.dist(hx, hy, p[1], p[2]),
			key = string.format("rbh:%.0f:%.0f:%d", hx, hy, k), hubArm = true }
	end
	inc.edges, inc.nodes = edges, nodes
	renumber(inc)
	return { x = hx, y = hy, arms = #ends }
end

--- The wanted hub class of a seeded u (RG.HUB_MIX).
function RG.hubWant(u)
	local acc = 0
	for _, m in ipairs(RG.HUB_MIX) do
		acc = acc + m[2]
		if (u or 0) < acc then return m[1] end
	end
	return RG.HUB_MIX[#RG.HUB_MIX][1]
end

-- Dead-end hubs (§57 round 2; the 2347 run: 4 hubs in 20 steps, the game's plans of 1-9 edges gave almost no
-- continuation node or long edge): a dead end of the town's own streets near houses gets its street carried on to a new
-- crossing (the hub) with 1-2 arms across and one on: the planner's own join (a dead end, never a junction), every
-- other node new. The hub slides out along the street (RG.HUB_SLIDE) until its ring has room.

--- Dead-end hub sites for rings up to radius R: { { x, y, z, deadEnd = node id, h, slide, cls, edges = {} } }.
function RG.deadEndSites(inc, o, R)
	local out = {}
	local g = o.g
	if g == nil or not RG.DEAD_END_HUBS then return out end
	local joined = {}
	for _, e in ipairs(inc.edges or {}) do
		if e.node0 > 0 then joined[e.node0] = true end
		if e.node1 > 0 then joined[e.node1] = true end
	end
	local list = {}
	for _, n in ipairs(g.nodes or {}) do
		local adj = g.adj[n.id]
		if adj and #adj == 1 and not n.noJoin and not joined[n.id] and n.id > 0 then
			-- (houses at the dead end itself, §57 round 3: in the 0234 run a mini ring sat alone at the town's edge with its
			-- arms in empty land and an l ring at the end of a road: the dead end within HUB_DE_HOUSED of a housed street
			-- and HUB_DE_HOUSES buildings on the streets round it)
			local hd = o.housedDist and o.housedDist(n.x, n.y) or 0
			if hd <= RG.HUB_DE_HOUSED and RG.housesNear(g, n.x, n.y, RG.HUB_DE_NEAR) >= (g.hasBuilt and RG.HUB_DE_HOUSES or 0) then
				list[#list + 1] = { n = n, hd = hd }
			end
		end
	end
	table.sort(list, function(a, b)
		if a.hd ~= b.hd then return a.hd < b.hd end
		return a.n.id < b.n.id
	end)
	for i, it in ipairs(list) do
		if i > RG.HUB_DE_MAX then break end
		local n = it.n
		local e = g.edgeById[g.adj[n.id][1]]
		local m = g.nodeById[OG.other(e, n.id)]
		if m and G.dist(m.x, m.y, n.x, n.y) > 1 then
			local h = G.atan2(n.y - m.y, n.x - m.x)
			for k, extra in ipairs(RG.HUB_SLIDE) do
				local D = R + extra
				out[#out + 1] = { x = n.x + math.cos(h) * D, y = n.y + math.sin(h) * D, z = n.z, deadEnd = n.id, dx = n.x,
					dy = n.y, dz = n.z, h = h, D = D, slide = k - 1, cls = e.class or "small", edges = {} }
			end
		end
	end
	return out
end
RG.DEAD_END_HUBS = true
RG.HUB_DE_HOUSED = 80       -- m: a dead-end hub's dead end this close to a housed street at most ...
RG.HUB_DE_NEAR = 120        -- ... with HUB_DE_HOUSES buildings on the streets (midpoints) within HUB_DE_NEAR m
RG.HUB_DE_HOUSES = 6
RG.HUB_CENTRE_LEAD = 140    -- m: every hub's centre this close to a housed street at most (the ring among houses)

--- Buildings on the streets of g whose midpoints lie within r m of (x, y).
function RG.housesNear(g, x, y, r)
	local n = 0
	for _, e in ipairs(g and g.edges or {}) do
		if (e.built or 0) > 0 then
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b and G.dist((a.x + b.x) / 2, (a.y + b.y) / 2, x, y) <= r then n = n + e.built end
		end
	end
	return n
end

--- Adds a dead-end hub (site from RG.deadEndSites) of class cl to inc: the stem from the dead end to the hub, the arm on
--- and the arms across (each clear, its end near houses); the stem and at least two more. Returns { x, y, arms } or nil,
--- why. inc changes only on success.
function RG.addDeadEndHub(inc, site, cl, o, R)
	local g = o.g
	local hz = site.dz or 0
	if o.height then
		local okH, h = pcall(o.height, site.x, site.y)
		if okH and tonumber(h) and h == h then hz = h end
	end
	if math.abs(hz - (site.dz or 0)) > RG.HUB_GRADE * site.D then return nil, "grade" end
	-- the stem: clear of every other street (the dead end's own edge aside) and of the plan's new streets
	local skipN = { [site.deadEnd] = true }
	local ca, sa = math.cos(site.h), math.sin(site.h)
	local steps = math.max(2, math.ceil(site.D / 8))
	for i = 0, steps do
		local t = 18 + (site.D - 18) * i / steps
		local x, y = site.dx + ca * t, site.dy + sa * t
		if g and OG.distToEdges(g, x, y, RG.HUB_CLEAR, skipN) then return nil, "nearStreet" end
		for _, e in ipairs(inc.edges or {}) do
			local prev = nil
			for _, q in ipairs(pts(e, 8)) do
				if prev and G.pointSegDist(x, y, prev[1], prev[2], q[1], q[2]) < RG.HUB_CLEAR then return nil, "nearNew" end
				prev = q
			end
		end
	end
	if g and OG.crossing(g, site.dx + ca * 2, site.dy + sa * 2, site.x, site.y, skipN) then return nil, "crosses" end
	if g then
		for _, n in ipairs(g.nodes or {}) do
			if n.id ~= site.deadEnd and G.dist(n.x, n.y, site.x, site.y) < R + RG.CLEAR + 12 then return nil, "nearNode" end
		end
	end
	local hubSite = { x = site.x, y = site.y, z = hz }
	local L = RG.HUB_STUB[cl] or RG.HUB_STUB.s
	local ends = {}
	for _, a in ipairs({ site.h, site.h + math.pi / 2, site.h - math.pi / 2 }) do
		local p = stubOk(inc, o, hubSite, a, L, R, {})
		if p then ends[#ends + 1] = p end
	end
	if #ends < 2 then return nil, "noArm" end
	local low = 0
	for _, n in ipairs(inc.nodes) do if n.entity < low then low = n.entity end end
	for _, e in ipairs(inc.edges) do if e.entity < low then low = e.entity end end
	local edges, nodes = {}, {}
	for _, x in ipairs(inc.edges) do edges[#edges + 1] = x end
	for _, n in ipairs(inc.nodes) do nodes[#nodes + 1] = n end
	low = low - 1
	local hubId = low
	local hx, hy = z0(G.round(site.x, 0.001)), z0(G.round(site.y, 0.001))
	hz = z0(G.round(hz, 0.001))
	nodes[#nodes + 1] = { entity = hubId, x = hx, y = hy, z = hz }
	local cls = site.cls or "small"
	local tpl = o.templates and o.templates[cls] or nil
	local key = string.format("rbd:%.0f:%.0f", hx, hy)
	local dx, dy, dz = hx - site.dx, hy - site.dy, hz - (site.dz or 0)
	edges[#edges + 1] = { entity = 0, node0 = site.deadEnd, node1 = hubId, p0 = v3({ site.dx, site.dy, site.dz or 0 }),
		p1 = v3({ hx, hy, hz }), t0 = v3({ dx, dy, dz }), t1 = v3({ dx, dy, dz }), class = cls, template = tpl,
		length = G.dist(site.dx, site.dy, hx, hy), key = key, hubArm = true }
	local stubCls = RG.HUB_STUB_CLASS[cls] or "small"
	for k, p in ipairs(ends) do
		low = low - 1
		local endId = low
		nodes[#nodes + 1] = { entity = endId, x = z0(G.round(p[1], 0.001)), y = z0(G.round(p[2], 0.001)), z = z0(G.round(p[3], 0.001)) }
		local ex, ey, ez = p[1] - hx, p[2] - hy, p[3] - hz
		-- (the arm on keeps the street's class; the arms across one below)
		local c2 = k == 1 and G.angleDiff(G.atan2(ey, ex), site.h) < 0.1 and cls or stubCls
		edges[#edges + 1] = { entity = 0, node0 = hubId, node1 = endId, p0 = v3({ hx, hy, hz }), p1 = v3(p),
			t0 = v3({ ex, ey, ez }), t1 = v3({ ex, ey, ez }), class = c2, template = o.templates and o.templates[c2] or tpl,
			length = G.dist(hx, hy, p[1], p[2]), key = key .. ":" .. k, hubArm = true }
	end
	inc.edges, inc.nodes = edges, nodes
	renumber(inc)
	return { x = hx, y = hy, arms = #ends }
end

--- Replaces candidate crossing c of inc by a one-way ring of size sz ({ R, template, name }). Returns the ring record
--- { centre, R, size, arms, nodes, keys } or nil, why. inc is changed only on success.
function RG.place(inc, c, sz, idx)
	local R = sz.R
	local trims, armPts = {}, {}
	for i, e in ipairs(c.edges) do
		local t, p = RG.trim(e, c.node, c.x, c.y, R)
		if t == nil then return nil, "short" end
		if (t.length or 0) < RG.ARM_MIN then return nil, "armShort" end
		trims[i] = t
		armPts[i] = p
	end
	local nodes, arcs = RG.arcs(c.x, c.y, R, armPts)
	-- new node entities (temporary, below every id in use; renumbered after)
	local low = 0
	for _, n in ipairs(inc.nodes) do if n.entity < low then low = n.entity end end
	for _, e in ipairs(inc.edges) do if e.entity < low then low = e.entity end end
	local ents = {}
	for k, n in ipairs(nodes) do
		ents[k] = low - k
	end
	-- the arms end on their ring nodes
	local armNode = {}
	for k, n in ipairs(nodes) do if n.arm then armNode[n.arm] = ents[k] end end
	local keys = {}
	local newEdges = {}
	for _, e in ipairs(inc.edges) do
		local ai = nil
		for i, a in ipairs(c.edges) do if a == e then ai = i end end
		if ai then
			local t = trims[ai]
			if t.node0 == c.node then t.node0 = armNode[ai] else t.node1 = armNode[ai] end
			newEdges[#newEdges + 1] = t
		else
			newEdges[#newEdges + 1] = e
		end
	end
	for k, a in ipairs(arcs) do
		local key = string.format("rb:%d:%d", idx or 1, k)
		keys[#keys + 1] = key
		newEdges[#newEdges + 1] = { entity = 0, node0 = ents[a.from], node1 = ents[a.to], p0 = a.p0, p1 = a.p1, t0 = a.t0,
			t1 = a.t1, class = "small", template = sz.template, length = a.length, key = key, ring = true, oneway = true }
	end
	local newNodes = {}
	for _, n in ipairs(inc.nodes) do
		if n.entity ~= c.node then newNodes[#newNodes + 1] = n end
	end
	for k, n in ipairs(nodes) do
		newNodes[#newNodes + 1] = { entity = ents[k], x = z0(G.round(n.x, 0.001)), y = z0(G.round(n.y, 0.001)),
			z = z0(G.round(n.z or c.z or 0, 0.001)), ring = true }
	end
	inc.edges, inc.nodes = newEdges, newNodes
	renumber(inc)
	return { centre = { c.x, c.y }, R = R, size = sz.name, arms = #c.edges, nodes = #nodes, keys = keys, main = c.main }
end

--- The far end of arm edge e of crossing c (the end that is not the crossing).
local function farEnd(e, node)
	if e.node0 == node then return e.p1 end
	return e.p0
end

--- Are the crossing's arms housed? Every arm's far end (and the crossing) within o.armLead (RG.ARM_LEAD) of a street
--- with houses (o.housedDist(x, y) -> m); no data (o.housedDist nil): yes. Returns true or false, "emptyArm".
function RG.armsOk(c, o)
	if o == nil or o.housedDist == nil then return true end
	local lead = o.armLead or RG.ARM_LEAD
	if o.housedDist(c.x, c.y) > lead then return false, "emptyArm" end
	for _, e in ipairs(c.edges) do
		local p = farEnd(e, c.node)
		if p and o.housedDist(p[1], p[2]) > lead then return false, "emptyArm" end
	end
	return true
end

--- Annotates candidates with the town centre / houses' radius: c.d (m from the centre), c.th (angle), c.gate.
local function annotate(cands, o)
	local cx, cy = o.centre and o.centre[1], o.centre and o.centre[2]
	for _, c in ipairs(cands) do
		if cx then
			c.d = G.dist(cx, cy, c.x, c.y)
			c.th = G.atan2(c.y - cy, c.x - cx)
			c.gate = (c.main or 0) >= 1 and o.radius ~= nil and c.d >= math.max(RG.GATE_F * o.radius, RG.GATE_MIN)
		end
	end
	return cands
end

--- Does a major arm of crossing a point at (x, y) (within PAIR_ALIGN)?
local function pointsAt(a, x, y, any)
	local h = G.atan2(y - a.y, x - a.x)
	for _, hd in ipairs(any and a.allHeads or a.heads or {}) do
		if G.angleDiff(hd, h) <= RG.PAIR_ALIGN then return true end
	end
	return false
end

--- The pair of an increment's candidates (major crossings, PAIR_MIN apart; any crossings with o.minor, the roundabout
--- town): "street" (each has a major arm (any arm with o.minor) pointing at the other: the two ends of one street) before
--- "opposite" (on opposite sides of the centre, OPPOSITE apart, both beyond half the houses' radius); the farthest
--- apart of the kind. Returns { a, b, kind, d } or nil.
function RG.pairOf(cands, o)
	o = o or {}
	local any = o.minor == true
	local best, bestRank, bestD = nil, 0, 0
	for i = 1, #cands do
		local a = cands[i]
		if any or RG.major(a) then
			for j = i + 1, #cands do
				local b = cands[j]
				local d = G.dist(a.x, a.y, b.x, b.y)
				if (any or RG.major(b)) and d >= RG.PAIR_MIN then
					local kind, rank = nil, 0
					if pointsAt(a, b.x, b.y, any) and pointsAt(b, a.x, a.y, any) then kind, rank = "street", 2
					elseif a.th and b.th and G.angleDiff(a.th, b.th) >= RG.PAIR_OPPOSITE and o.radius
						and a.d >= 0.5 * o.radius and b.d >= 0.5 * o.radius then kind, rank = "opposite", 1 end
					if kind and (rank > bestRank or (rank == bestRank and d > bestD)) then
						best, bestRank, bestD = { a = a, b = b, kind = kind, d = d }, rank, d
					end
				end
			end
		end
	end
	return best
end

--- Marks rings on an increment. o = { geo = RG.load result, g = the snapshot graph, share = { main = p, mini = p,
--- gate = p, pair = p, spacing = m, town = bool } (RG.rate / RG.townShare), draw = fn(x, y, tag) -> 0..1 (seeded), max =
--- rings at most (MAX_PER_INC), centre = { x, y } and radius (the houses' extent: gateways, opposite pairs), housedDist
--- = fn(x, y) -> m and armLead (no arms into empty land), existing = { { x, y } } (rings already built: spacing) }.
--- pending = { x, y, h, R, n } (a deferred pair's first ring: its partner placed first, along heading h), canDefer = a
--- ring placed alone may reserve its partner (res.pending).
--- Returns { rings = { record }, skipped = { { x, y, why } }, pair = { kind, d, ok, why } or nil, deferred = { ok, why,
--- size, R, d } or nil (o.pending tried), pending = { x, y, h, R, n } or nil (a new reservation) }; inc.rings /
--- inc.ringUndo set when a ring went in.
function RG.mark(inc, o)
	o = o or {}
	local res = { rings = {}, skipped = {} }
	if not RG.ON or o.geo == nil or inc == nil or #(inc.edges or {}) == 0 then return res end
	local share = o.share or {}
	local maxN = o.max or RG.MAX_PER_INC
	local spacing = share.spacing or RG.SPACING
	local function draw(c, tag) return o.draw and o.draw(c.x, c.y, tag) or 0 end
	local undo = nil
	local placedAt = {}
	-- (the candidates' edge tables change with each ring: look the node up again)
	local function find(c0)
		for _, cc in ipairs(annotate(RG.candidates(inc), o)) do
			if math.abs(cc.x - c0.x) < 1e-6 and math.abs(cc.y - c0.y) < 1e-6 then return cc end
		end
		return nil
	end
	-- (except: a ring centre { x, y } not counted: a deferred pair's first ring)
	local function spaced(c, except)
		local function skip(p) return except ~= nil and G.dist(p.x, p.y, except.x, except.y) < 30 end
		for _, e in ipairs(o.existing or {}) do
			if not skip(e) and G.dist(e.x, e.y, c.x, c.y) < spacing then return false end
		end
		for _, p in ipairs(placedAt) do
			if not skip(p) and G.dist(p.x, p.y, c.x, c.y) < spacing then return false end
		end
		return true
	end
	-- one ring at c0 of class cl (sizes from u downward): the record or nil, why
	local function try(c0, cl, u, idx, sizeFirst, exact)
		local c = find(c0)
		if c == nil then return nil, "gone" end
		for _, e in ipairs(c.edges) do if e.ring then return nil, "ring" end end
		local okA, wa = RG.armsOk(c, o)
		if not okA then return nil, wa end
		local sizes = RG.sizesFor(o.geo, cl, u)
		if exact then
			-- (a hub, §57 round 2: only its class's sizes; no room there: the next spot, not a smaller ring)
			local list = {}
			for _, sz in ipairs(sizes) do if (sz.class or sz.name) == cl then list[#list + 1] = sz end end
			sizes = list
		end
		if sizeFirst then
			-- (a pair's second ring: the first one's size first, then smaller)
			local list = { sizeFirst }
			for _, sz in ipairs(sizes) do if sz.R < sizeFirst.R then list[#list + 1] = sz end end
			sizes = list
		end
		local why = "noSize"
		-- (the larger sizes: the arms extended through plain continuation nodes first; put back when no size fits)
		local snapX = nil
		if sizes[1] and RG.extendArms ~= nil then
			local need = sizes[1].R + RG.ARM_MIN + 6
			local short = false
			for _, e in ipairs(c.edges) do
				local f = (e.node0 == c.node) and e.p1 or e.p0
				if G.dist(f[1], f[2], c.x, c.y) < need then short = true end
			end
			if short then
				local before = copyInc(inc)
				if RG.extendArms(inc, c, need) > 0 then
					undo = undo or before
					snapX = before
					renumber(inc)
					c = find(c0)
					-- (the longer arms must still end near houses; else the plain arms as planned)
					if c == nil or not RG.armsOk(c, o) then
						local r = copyInc(before)
						inc.nodes, inc.edges, inc.joins, inc.stats = r.nodes, r.edges, r.joins, r.stats
						snapX = nil
						c = find(c0)
						if c == nil then return nil, "gone" end
					end
				end
			end
		end
		local fell = {}
		for _, sz in ipairs(sizes) do
			local okC, cw = RG.clear(inc, o.g, c, sz.R)
			if okC then
				undo = undo or copyInc(inc)
				local rec, pw = RG.place(inc, c, sz, idx)
				if rec then
					rec.class, rec.wanted, rec.gate = sz.class or sz.name, cl, c.gate or nil
					-- (why the larger sizes did not fit: RB `fell=`)
					rec.fell = #fell > 0 and table.concat(fell, ",") or nil
					placedAt[#placedAt + 1] = { x = c.x, y = c.y }
					return rec, nil, sz
				end
				why = pw
			else
				why = cw
			end
			fell[#fell + 1] = string.format("%.0f:%s", sz.R, tostring(why))
		end
		if snapX then
			-- (a fresh copy: the snapshot may also be the increment's undo record)
			local r = copyInc(snapX)
			inc.nodes, inc.edges, inc.joins, inc.stats = r.nodes, r.edges, r.joins, r.stats
		end
		return nil, why
	end
	local cands = annotate(RG.candidates(inc), o)
	-- a pair first (the seeded motif): both rings or neither
	if (share.pair or 0) > 0 and maxN >= 2 then
		local pr = RG.pairOf(cands, { centre = o.centre, radius = o.radius, minor = share.pairMinor })
		if pr then
			local u = draw(pr.a, "pair")
			res.pair = { kind = pr.kind, d = pr.d, ok = false, x1 = pr.a.x, y1 = pr.a.y, x2 = pr.b.x, y2 = pr.b.y }
			if u >= share.pair then
				res.pair.why = string.format("draw:%.2f>=%.3f", u, share.pair)
			elseif not spaced(pr.a) or not spaced(pr.b) then
				res.pair.why = "near"
			else
				-- (the twins: the smaller class of the two, one size)
				local ca, cb = RG.classOf(pr.a), RG.classOf(pr.b)
				local cl = (RG.RANK[ca] or 1) <= (RG.RANK[cb] or 1) and ca or cb
				local snap = copyInc(inc)
				local undo0, placed0 = undo, #placedAt
				local r1, w1, sz1 = try(pr.a, cl, draw(pr.a, "size"), 1)
				local r2, w2 = nil, nil
				if r1 then r2, w2 = try(pr.b, cl, 0, 2, sz1) end
				if r1 and r2 then
					r1.pair, r2.pair = pr.kind, pr.kind
					res.rings[#res.rings + 1] = r1
					res.rings[#res.rings + 1] = r2
					res.pair.ok, res.pair.size, res.pair.R = true, r1.class, r1.R
				else
					inc.nodes, inc.edges, inc.joins, inc.stats = snap.nodes, snap.edges, snap.joins, snap.stats
					undo = undo0
					for k = #placedAt, placed0 + 1, -1 do placedAt[k] = nil end
					res.pair.why = r1 and ("second:" .. tostring(w2)) or ("first:" .. tostring(w1))
				end
			end
		end
	end
	-- a deferred pair's second ring (o.pending, saved: an earlier increment's ring waiting for its partner along its street,
	-- or (k = 2, the roundabout town's hubs, §57) across the town)
	local pd = o.pending
	-- (a hub's twin, §57 round 3: in the 0234 run 12 twins were reserved and 2 placed, mostly `why=none`: the street
	-- window looked only outward, past the houses. A hub twin (pd.hub) looks both ways along its street and within
	-- PAIR_HUB_ALIGN; an older reservation keeps the outward window)
	local function inWindow(x, y)
		local d = G.dist(pd.x, pd.y, x, y)
		local opp = pd.k == 2
		if d < RG.PAIR_MIN or d > (opp and RG.PAIR_REACH_OPP or RG.PAIR_REACH) then return nil end
		local hdg = G.atan2(y - pd.y, x - pd.x)
		local align = (pd.k ~= nil) and RG.PAIR_HUB_ALIGN or RG.PAIR_DEFER_ALIGN
		local off = G.angleDiff(hdg, pd.h)
		if pd.k == 1 then off = math.min(off, G.angleDiff(hdg, pd.h + math.pi)) end
		if off > align then return nil end
		if opp and o.centre and d < G.dist(pd.x, pd.y, o.centre[1], o.centre[2]) then return nil end
		return d
	end
	local function firstSize()
		local first = nil
		for _, cl in ipairs(RG.CLASSES) do
			for _, sz in ipairs(o.geo.classes and o.geo.classes[cl] or {}) do
				if math.abs(sz.R - (pd.R or 0)) < 0.5 then first = sz end
			end
		end
		return first
	end
	if pd and #res.rings < maxN then
		local kind = pd.k == 2 and "opposite" or "street"
		local best, bd = nil, math.huge
		for _, c in ipairs(cands) do
			local d = inWindow(c.x, c.y)
			if d and d < bd and (pd.k == 2 or pointsAt(c, pd.x, pd.y, true)) then best, bd = c, d end
		end
		res.deferred = { kind = kind, d = bd, ok = false, x1 = pd.x, y1 = pd.y, deferred = true }
		if best == nil then
			res.deferred.why = "none"
		elseif not spaced(best, pd) then
			res.deferred.why = "near"
		else
			-- (the first ring's size first, then smaller)
			local first = firstSize()
			local rec, why = try(best, first and first.class or RG.classOf(best), 0, #res.rings + 1, first)
			res.deferred.x2, res.deferred.y2 = best.x, best.y
			if rec then
				rec.pair = kind
				rec.deferred = true
				res.rings[#res.rings + 1] = rec
				res.deferred.ok, res.deferred.size, res.deferred.R = true, rec.class, rec.R
			else
				res.deferred.why = tostring(why)
			end
		end
	end
	-- ring hubs (the roundabout town, share.hubs, §57): the waiting partner's hub first, then the plan's own hub
	res.hubs = {}
	local function hubRing(site, cl, sizeFirst, exact)
		local before = copyInc(inc)
		local undo0, placed0 = undo, #placedAt
		local R = (sizeFirst and sizeFirst.R) or 0
		for _, sz in ipairs(o.geo.classes and o.geo.classes[cl] or {}) do if sz.R > R then R = sz.R end end
		local h, hw
		if site.deadEnd then h, hw = RG.addDeadEndHub(inc, site, cl, o, R) else h, hw = RG.addHub(inc, site, cl, o, R) end
		if h == nil then return nil, hw end
		undo = undo or before
		local rec, why = try({ x = h.x, y = h.y }, cl, draw(site, "size"), #res.rings + 1, sizeFirst, exact)
		if rec == nil then
			inc.nodes, inc.edges, inc.joins, inc.stats = before.nodes, before.edges, before.joins, before.stats
			undo = undo0
			for k = #placedAt, placed0 + 1, -1 do placedAt[k] = nil end
			return nil, why
		end
		rec.hub, rec.hubArms, rec.street, rec.deadEnd = true, h.arms, site.cls, site.deadEnd ~= nil
		return rec
	end
	local function ringDist(x, y)
		local best = math.huge
		for _, e in ipairs(o.existing or {}) do best = math.min(best, G.dist(e.x, e.y, x, y)) end
		for _, p in ipairs(placedAt) do best = math.min(best, G.dist(p.x, p.y, x, y)) end
		return best
	end
	if share.hubs and pd and res.deferred and not res.deferred.ok and #res.rings < maxN then
		local first = firstSize()
		local cl = first and first.class or "s"
		local list = {}
		local allSites = RG.hubSites(inc)
		for _, st in ipairs(RG.deadEndSites(inc, o, (first and first.R) or 24)) do allSites[#allSites + 1] = st end
		for _, st in ipairs(allSites) do
			local d = inWindow(st.x, st.y)
			local hd = o.housedDist and o.housedDist(st.x, st.y) or 0
			if d and hd <= RG.HUB_CENTRE_LEAD and ringDist(st.x, st.y) >= RG.HUB_GAP_MIN then st.d = d; list[#list + 1] = st end
		end
		table.sort(list, function(a, b) return a.d < b.d end)
		local why = res.deferred.why
		for i, st in ipairs(list) do
			if i > RG.HUB_TRIES then break end
			local rec, w = hubRing(st, cl, first)
			if rec then
				rec.pair, rec.deferred = res.deferred.kind, true
				res.rings[#res.rings + 1] = rec
				res.hubs[#res.hubs + 1] = { rec = rec, site = st, partner = true }
				res.deferred.ok, res.deferred.size, res.deferred.R, res.deferred.d = true, rec.class, rec.R, st.d
				res.deferred.x2, res.deferred.y2, res.deferred.hub, res.deferred.why = st.x, st.y, true, nil
				break
			end
			why = "hub:" .. tostring(w)
		end
		if not res.deferred.ok then res.deferred.why = why end
	end
	local hubsNow = 0
	-- (the sites for a class, again after each hub: a placed ring renumbers the increment). Street sites need the
	-- class's room round them (RG.room); dead-end sites slide out along their street until the ring has room (§57 round 2:
	-- in game 3 of 4 hubs wanted l and shrank to s at a fixed spot, `nearNode` / `nearNew`)
	local function hubList(cl)
		local rank = { main = 3, medium = 2, small = 1 }
		local list = {}
		local Rmin, Rmax = math.huge, 0
		for _, sz in ipairs(o.geo.classes and o.geo.classes[cl] or {}) do Rmin, Rmax = math.min(Rmin, sz.R), math.max(Rmax, sz.R) end
		if Rmax == 0 then return list end
		local sites = {}
		for _, st in ipairs(RG.hubSites(inc)) do
			st.room = RG.room(inc, o.g, st)
			if st.room >= Rmin + RG.CLEAR + 2 then sites[#sites + 1] = st end
		end
		for _, st in ipairs(RG.deadEndSites(inc, o, Rmax)) do sites[#sites + 1] = st end
		for _, st in ipairs(sites) do
			local dc = o.centre and G.dist(o.centre[1], o.centre[2], st.x, st.y) or 0
			st.gate = o.radius ~= nil and dc >= math.max(RG.GATE_F * o.radius, RG.GATE_MIN)
			local gap = RG.HUB_GAP_MIN + (RG.HUB_GAP_MAX - RG.HUB_GAP_MIN) * draw(st, "hubGap")
			local rd = ringDist(st.x, st.y)
			if pd and G.dist(pd.x, pd.y, st.x, st.y) < gap then rd = 0 end
			-- (among houses: a site whose arms would end beyond the lead is no try; nearer the houses first)
			st.hd = o.housedDist and o.housedDist(st.x, st.y) or 0
			if st.hd > RG.HUB_CENTRE_LEAD then rd = 0 end
			if rd >= gap then
				-- (spread over the town: farther out first, a street of the class's rank, a seeded pick)
				st.rank = (rank[st.cls] or 1) * 0.3 + 0.5 * draw(st, "hubPick") - st.hd / RG.HUB_HOUSED
					+ (o.radius and o.radius > 0 and math.min(1.5, dc / o.radius) or 0) - (st.slide or 0) * 0.15
				list[#list + 1] = st
			end
		end
		table.sort(list, function(a, b)
			if a.rank ~= b.rank then return a.rank > b.rank end
			if a.x ~= b.x then return a.x < b.x end
			return a.y < b.y
		end)
		return list
	end
	local tried = 0
	for k = 1, RG.HUB_PER_INC do
		if not share.hubs or #res.rings >= maxN or tried >= RG.HUB_TRIES_ALL then break end
		local placed = false
		-- the wanted class (seeded mix, RG.HUB_MIX), then smaller classes when no spot has room for it
		local want = RG.hubWant(draw({ x = k * 37, y = #inc.edges }, "hubWant"))
		for r = RG.RANK[want] or 2, 1, -1 do
			local cl = RG.CLASSES[r]
			local n = 0
			for _, st in ipairs(hubList(cl)) do
				if tried >= RG.HUB_TRIES_ALL or n >= RG.HUB_TRIES then break end
				tried, n = tried + 1, n + 1
				local rec, w = hubRing(st, cl, nil, true)
				if rec then
					placed = true
					rec.wanted = want
					hubsNow = hubsNow + 1
					res.rings[#res.rings + 1] = rec
					local hb = { rec = rec, site = st }
					res.hubs[#res.hubs + 1] = hb
					-- (its twin, drawn often: at the other end of its street, or across the town; placed by a later plan)
					if o.canDefer and pd == nil and res.pending == nil and (share.pair or 0) > 0
						and draw(st, "pairLater") < share.pair then
						local h, kk = st.h, 1
						local cx, cy = o.centre and o.centre[1], o.centre and o.centre[2]
						if cx and (st.cls == "small" or draw(st, "pairKind") < 0.5) and G.dist(cx, cy, st.x, st.y) > RG.PAIR_MIN then
							h, kk = G.atan2(cy - st.y, cx - st.x), 2
						elseif cx and math.cos(st.h - G.atan2(st.y - cy, st.x - cx)) < 0 then
							h = st.h + math.pi
						end
						res.pending = { x = rec.centre[1], y = rec.centre[2], h = G.wrap(h), R = rec.R, n = RG.PAIR_WAIT_HUB, k = kk }
						hb.reserved = kk == 2 and "opposite" or "street"
					end
					break
				else
					res.skipped[#res.skipped + 1] = { x = st.x, y = st.y, why = "hub:" .. tostring(w), main = 0, arms = 0, class = cl }
				end
			end
			if placed then break end
		end
		if not placed then break end
	end
	-- single rings
	local tries = 0
	for _, c0 in ipairs(cands) do
		if #res.rings >= maxN then break end
		tries = tries + 1
		if tries > 32 then break end
		local c = find(c0)
		if c ~= nil then
			local isMajor = RG.major(c)
			local p = isMajor and (share.main or 0) or (share.mini or 0)
			if c.gate then p = math.max(p, share.gate or 0) end
			local u = draw(c, "ring")
			local why = nil
			for _, e in ipairs(c.edges) do if e.ring then why = "ring" end end
			if why == nil and u >= p then why = string.format("draw:%.2f>=%.3f", u, p)
			elseif why == nil and not spaced(c) then why = "near" end
			if why == nil then
				local rec, pw = try(c, RG.classOf(c), draw(c, "size"), #res.rings + 1)
				if rec then
					res.rings[#res.rings + 1] = rec
					-- (no partner in this increment: the pair draw may reserve one along the ring's street, later)
					if o.canDefer and not (res.pair and res.pair.ok) and pd == nil and res.pending == nil and isMajor
						and (share.pair or 0) > 0 and draw(c, "pairLater") < share.pair then
						local h = nil
						local best = -2
						for _, hd in ipairs(c.heads or {}) do
							local dot = 1
							if c.th then dot = math.cos(hd - c.th) end
							if dot > best then h, best = hd, dot end
						end
						if h then res.pending = { x = rec.centre[1], y = rec.centre[2], h = h, R = rec.R, n = RG.PAIR_WAIT } end
					end
				else
					why = pw
				end
			end
			if why then
				res.skipped[#res.skipped + 1] = { x = c.x, y = c.y, why = why, main = c.main, arms = #c.edges, class = RG.classOf(c) }
			end
		end
	end
	if #res.rings > 0 then
		inc.rings = res.rings
		inc.ringUndo = undo
	end
	return res
end

--- Takes the rings out again (a refused pre-check): the plain crossings as planned. Returns the rings removed.
function RG.strip(inc)
	if inc == nil or inc.ringUndo == nil then return 0 end
	local n = #(inc.rings or {})
	local u = inc.ringUndo
	inc.nodes, inc.edges, inc.joins, inc.stats = u.nodes, u.edges, u.joins, u.stats
	inc.rings, inc.ringUndo = nil, nil
	return n
end

--- The keys of the ring edges in inc (lock them: { [key] = true }).
function RG.lockKeys(inc)
	local out = {}
	for _, e in ipairs(inc and inc.edges or {}) do
		if e.ring and e.key then out[e.key] = true end
	end
	return out
end

--- The refused rings' surroundings for the RB `event=refused` line (§57 round 2: the 2347 run's refused pair had no
--- DIAG lines): per ring "x:y:R:node=<m beyond the ring to the nearest node>:street=<to the nearest street centre line,
--- chord or curve>", joined by "/".
function RG.nearText(g, rings)
	local out = {}
	for _, r in ipairs(rings or {}) do
		local cx, cy = r.centre[1], r.centre[2]
		local dn, de = math.huge, math.huge
		for _, n in ipairs(g and g.nodes or {}) do dn = math.min(dn, G.dist(n.x, n.y, cx, cy)) end
		for _, e in ipairs(g and g.edges or {}) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			if a and b then
				de = math.min(de, G.pointSegDist(cx, cy, a.x, a.y, b.x, b.y))
				if e.t0 and e.t1 then
					local he = { p0 = { a.x, a.y, 0 }, p1 = { b.x, b.y, 0 }, t0 = { e.t0[1] or e.t0.x or 0, e.t0[2] or e.t0.y or 0, 0 },
						t1 = { e.t1[1] or e.t1.x or 0, e.t1[2] or e.t1.y or 0, 0 } }
					for _, p in ipairs(pts(he, 8)) do de = math.min(de, G.dist(p[1], p[2], cx, cy)) end
				end
			end
		end
		out[#out + 1] = string.format("%.0f:%.0f:%.0f:node=%.0f:street=%.0f", cx, cy, r.R or 0, dn - (r.R or 0), de - (r.R or 0))
	end
	return #out > 0 and table.concat(out, "/") or "-"
end

--- RB text of a ring record: "m:R=34:arms=4:main=2".
function RG.text(r)
	if r == nil then return "-" end
	return string.format("%s:R=%.0f:arms=%d:main=%d", tostring(r.class or r.size), r.R or 0, r.arms or 0, r.main or 0)
end

return RG
