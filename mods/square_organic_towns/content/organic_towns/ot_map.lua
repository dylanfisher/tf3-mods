-- Organic Towns: map-level rules (pure; 2026-10-13, real map round 3).
--
-- Map edge (user, real map run 2026-10-13_0137_sqot-dev: Axbridge's head start ran an ~800 m empty medium street from
-- the town to the map boundary): no plan piece within MARGIN of the map's bounding box (api.engine.terrain.
-- getBoundingBox, read by ot_engine.mapBounds; the same call square_better_minimap uses), and a seeded shape axis turns
-- its arms away from a near edge (ot_shape). bounds = { minX, minY, maxX, maxY } (m) or nil (unknown: no limit).
--
-- Character towns (user: "It's nice when some towns in every map are drastically different. There should always be
-- secluded towns (maybe near the edge of the map, or on an island, etc.) that really want to sprawl and not build out
-- from the centre"): every map gets a few towns with an extreme form (ot_form CHARACTER). Picked by seclusion: the
-- distance to the nearest other town (over the map's median), plus a bonus near the map edge; the top SHARE of the
-- towns (at least MIN_FEW / MIN_MANY) are character towns. Deterministic for a given set of towns (ties by town id);
-- the pick is saved with the town's frame at its first build (ot_saved `ch`), so a later town doesn't change it.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

M.MARGIN = 400            -- m: no planned street closer than this to the map boundary
M.EXPOSE_REACH = 1500     -- m: arms are tested this far out for the edge (ot_shape axis turn)
M.EXPOSE_STEP = 100

M.SHARE = 0.15            -- share of a map's towns that are character towns ...
M.MIN_FEW = 1             -- ... at least this many on a map of MIN_TOWNS .. MANY_TOWNS - 1 towns
M.MIN_MANY = 2            -- ... and this many from MANY_TOWNS
M.MIN_TOWNS = 3
M.MANY_TOWNS = 8
M.EDGE_NEAR = 2500        -- m: within this of the map edge a town gets an edge bonus (secluded at the rim) ...
M.EDGE_W = 0.6            -- ... up to this (added to the nearest-neighbour distance over the median)
M.NO_NEIGHBOUR = 6000     -- m: a town without any other town counts as this far from one
-- (2026-10-13 round 5, real map run 2026-10-13_0342_sqot: both character towns sat 920 m from the map edge, Bodmin's
-- linear arms ran into the 400 m margin, PLAN edgeHeld=1-11 and "edges=0 blocked=29" late on; it grew as a blob with a
-- 12 % mod share. A town with less than EDGE_ROOM to the edge has no room for an extreme form: EDGE_CRAMP off its score)
M.EDGE_ROOM = 1300
M.EDGE_CRAMP = 0.8

--- Distance (m) from (x, y) to the map boundary (negative outside), or math.huge without bounds.
function M.edgeDist(bounds, x, y)
	if bounds == nil then return math.huge end
	return math.min(x - bounds[1], bounds[3] - x, y - bounds[2], bounds[4] - y)
end

--- true when (x, y) lies within margin (default MARGIN) of the map boundary (or outside it).
function M.nearEdge(bounds, x, y, margin)
	if bounds == nil then return false end
	return M.edgeDist(bounds, x, y) < (margin or M.MARGIN)
end

--- true when any point of the polyline (or its midpoint) lies within the margin of the boundary.
function M.polyNearEdge(bounds, pts, margin)
	if bounds == nil or pts == nil then return false end
	for _, p in ipairs(pts) do
		if M.nearEdge(bounds, p[1], p[2], margin) then return true end
	end
	if #pts >= 2 then
		local mx, my = G.polyAt(pts, 0.5)
		if M.nearEdge(bounds, mx, my, margin) then return true end
	end
	return false
end

--- Share (0..1) of the sample points along the arms (headings, rad) from (cx, cy) out to reach that lie within the
--- margin of the boundary (0 without bounds).
function M.armsExposure(bounds, cx, cy, arms, reach, margin)
	if bounds == nil or arms == nil or #arms == 0 then return 0 end
	reach = reach or M.EXPOSE_REACH
	local n, hit = 0, 0
	for _, a in ipairs(arms) do
		local ca, sa = math.cos(a), math.sin(a)
		for d = M.EXPOSE_STEP, reach, M.EXPOSE_STEP do
			n = n + 1
			if M.nearEdge(bounds, cx + ca * d, cy + sa * d, margin) then hit = hit + 1 end
		end
	end
	return n > 0 and hit / n or 0
end

--- "edge=1234" text: the distance to the boundary rounded to 10 m, or "-".
function M.edgeText(bounds, x, y)
	local d = M.edgeDist(bounds, x, y)
	if d == math.huge then return "-" end
	return string.format("%.0f", math.floor(d / 10 + 0.5) * 10)
end

--- Character towns of a map. towns = { { id, x, y } } (the map's own towns: the driver leaves out the towns the mod
--- created), bounds or nil, fixed = { [id] = true | false } or nil: picks saved on a plan frame (2026-10-14,
--- NEXT_PHASE_BRIEF 48 item 4): true stays a character town and fills a slot of the quota first, false never becomes
--- one; the rest of the quota goes to the other towns by rank. Returns { [id] = { score, rank, character = bool,
--- saved = bool or nil, nnd = m, edgeDist = m } } and the quota (the number of character towns the map should have).
function M.characters(towns, bounds, fixed)
	local out = {}
	local n = #towns
	if n == 0 then return out, 0 end
	local nnd = {}
	for i, a in ipairs(towns) do
		local best = M.NO_NEIGHBOUR
		for j, b in ipairs(towns) do
			if i ~= j then
				local d = G.dist(a[2], a[3], b[2], b[3])
				if d < best then best = d end
			end
		end
		nnd[i] = best
	end
	local sorted = {}
	for i = 1, n do sorted[i] = nnd[i] end
	table.sort(sorted)
	local median = sorted[math.max(1, math.floor((n + 1) / 2))]
	if median <= 1 then median = 1 end
	local list = {}
	for i, a in ipairs(towns) do
		local ed = M.edgeDist(bounds, a[2], a[3])
		local edgeClose = ed == math.huge and 0 or G.clamp(1 - ed / M.EDGE_NEAR, 0, 1)
		local score = nnd[i] / median + M.EDGE_W * edgeClose - ((ed < M.EDGE_ROOM) and M.EDGE_CRAMP or 0)
		local e = { id = a[1], score = score, nnd = nnd[i], edgeDist = ed, character = false }
		out[a[1]] = e
		list[#list + 1] = e
	end
	table.sort(list, function(p, q)
		if math.abs(p.score - q.score) > 1e-9 then return p.score > q.score end
		return p.id < q.id
	end)
	local count = 0
	if n >= M.MIN_TOWNS then
		count = math.floor(n * M.SHARE + 0.5)
		count = math.max(count, n >= M.MANY_TOWNS and M.MIN_MANY or M.MIN_FEW)
	end
	fixed = fixed or {}
	local free = count
	for r, e in ipairs(list) do
		e.rank = r
		if fixed[e.id] == true then e.character, e.saved, free = true, true, free - 1 end
	end
	for _, e in ipairs(list) do
		if free <= 0 then break end
		if fixed[e.id] == nil then e.character, free = true, free - 1 end
	end
	return out, count
end

-- Coastal huggers (2026-10-14, user after run 2026-10-13_2355_sqot: "Could be more extreme coastal city hugging in at
-- least 1-2 cities per map"): the towns with the most coastline (sea or lake shore) around them get the strong shore
-- form (ot_form COASTAL). The coastline is read on COAST_R rings of COAST_DIRS samples: a ring half wet / half dry scores
-- 1 (min(wet, dry) share x 2), wet arcs add a little (a bay, a lake arm), a ring with no water 0; a river (a thin wet
-- arc on every ring) scores low. Top COAST_MAX (1 below COAST_TWO towns) of those scoring COAST_MIN or more; ties by id.
M.COAST_R = { 300, 600, 900 }
M.COAST_DIRS = 24
M.COAST_MIN = 0.45
M.COAST_MAX = 2
M.COAST_TWO = 10          -- towns on the map for a second pick
M.COAST_TOWNS = 80        -- towns scored at most

--- The coastline score of a town at (cx, cy): 0..~1.3, and the wet share of its nearest ring. wet = function(x, y).
function M.coastScore(wet, cx, cy)
	local total, near = 0, 0
	for ri, r in ipairs(M.COAST_R) do
		local w, arcs, prev, first = 0, 0, nil, nil
		for k = 0, M.COAST_DIRS - 1 do
			local a = k * 2 * math.pi / M.COAST_DIRS
			local isW = wet(cx + math.cos(a) * r, cy + math.sin(a) * r) == true
			if isW then w = w + 1 end
			if prev ~= nil and isW and not prev then arcs = arcs + 1 end
			if first == nil then first = isW end
			prev = isW
		end
		if prev ~= nil and first and not prev then arcs = arcs + 1 end
		local share = w / M.COAST_DIRS
		if ri == 1 then near = share end
		total = total + math.min(share, 1 - share) * 2 + 0.05 * math.min(arcs, 3)
	end
	return total / #M.COAST_R, near
end

--- The coastal picks: towns = { { id, x, y } } (character / mod-made towns left out by the caller), wet = function(x, y).
--- Returns { [id] = { coastal = true, score, rank } }, scored list text "id:score,...", count.
function M.coastal(towns, wet)
	local list = {}
	for i, t in ipairs(towns or {}) do
		if i > M.COAST_TOWNS then break end
		local sc, near = M.coastScore(wet, t[2], t[3])
		list[#list + 1] = { id = t[1], score = sc, near = near }
	end
	table.sort(list, function(a, b)
		if math.abs(a.score - b.score) > 1e-9 then return a.score > b.score end
		return a.id < b.id
	end)
	local max = #towns >= M.COAST_TWO and M.COAST_MAX or 1
	local out, n = {}, 0
	for rank, e in ipairs(list) do
		if n < max and e.score >= M.COAST_MIN then
			n = n + 1
			out[e.id] = { coastal = true, score = e.score, rank = rank, near = e.near }
		end
	end
	return out, list, n
end

return M
