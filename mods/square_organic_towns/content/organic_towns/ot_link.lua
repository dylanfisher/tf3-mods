-- Organic Towns: the robust link road between two towns' dead ends (pure; 2026-10-14, round after the 2355 run).
--
-- Run 2026-10-13_2355_sqot: both Works towns (Haslemere Works, Chorleywood Works) were created, but no road ever joined
-- them to their parent: the old link (ot_works.link) tried the 12 nearest dead-end pairs on ONE line each and gave up on
-- the first problem of each (`crossing` x2, `obstacle`), and the one plan it sent joined only one end (`notJoined`: the
-- planner dropped the edge into the Works' dead end). Now:
--   * many pairs (MAX_PAIRS, nearest first, MIN_D..MAX_D apart), each with several routes: the seeded gentle bend, then
--     detours through a waypoint OFFSETS x the length off the straight line on either side (at most MAX_OFF m), so a
--     route goes round a street, a field or a farm instead of failing on it;
--   * each route tested cheapest first: not doubling back at either dead end (BACK_DEG: the planner's min angle at the
--     joint would drop the end edge: `notJoined`), no street of the snapshot crossed (only the two end nodes' own
--     streets skipped), clear of obstacles beyond the snapshot (roads, tracks, constructions, fields; END_SKIP m at
--     each end untested: the ends' own streets), outside the industry keep-clear zones (ot_industry.zoneHit), dry,
--     gentle (MAX_GRADE);
--   * up to MAX_OUT passing routes come back, best first (length + detour), so the driver plans them one after the
--     other with ot_plan and sends the first whose both ends are joined (no more `notJoined`).
-- Joining at a node in the middle of a street is not supported by the planner and the proposal layer (only dead ends
-- with a node config are joined: the crash rule), so it is not tried. Every loop is bounded by MAX_PAIRS x OFFSETS and
-- MAX_TESTS. Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local SAT = ug_require "square_organic_towns::/organic_towns/ot_satellite.lua"
local IND = ug_require "square_organic_towns::/organic_towns/ot_industry.lua"

local M = {}

M.MAX_PAIRS = 24          -- dead-end pairs looked at, nearest first
M.OFFSETS = { 0, 0.22, -0.22, 0.42, -0.42 }   -- route detours: waypoint off the line, x its length (0: the seeded bend)
-- (2026-10-14, run 2026-10-14_0613_sqot: 1 of 7 offshoots linked; 4 failed `why=back` (43-63 of 90 routes), 2 on
-- crossings. A route left each dead end on the straight line to the other end, so a dead end pointing away was useless.)
-- LEAD: after the seeded bend, a route that leaves both dead ends straight on along their own streets (a cubic curve with
-- the ends' outward headings, LEAD_K x the length out, at most LEAD_MAX m) and swings round to the other end.
M.LEAD = true
M.LEAD_K = 0.35
M.LEAD_MAX = 260
M.LEAD_SIDE = 0.8         -- ... and swung to one side (both tried) by this x the lead length: round its own street
M.MAX_OFF = 420           -- m: a detour's waypoint at most this far off the line
M.MIN_D, M.MAX_D = 120, 2500
M.END_SKIP = 35           -- m at each end not tested against obstacles (the ends' own streets)
M.MAX_TESTS = 90          -- routes tested at most per call
M.MAX_OUT = 4             -- passing routes returned at most
M.MAX_GRADE = 0.10
M.BACK_DEG = 60           -- the link must leave a dead end at least this far from its own street's direction back
M.DETOUR_COST = 0.6       -- score: m of length + this x m of waypoint offset
M.CLEAR = 18              -- m: the link keeps this far from streets of the snapshot (SAT.LINK_CLEAR)

--- The route points from a to b through a waypoint `off` x length to the left of the line (0: SAT.linkPts' seeded bend).
function M.route(ax, ay, bx, by, off, seed)
	if off == 0 then return SAT.linkPts(ax, ay, bx, by, seed) end
	local L = G.dist(ax, ay, bx, by)
	local nx, ny = -(by - ay) / math.max(L, 1e-6), (bx - ax) / math.max(L, 1e-6)
	local o = G.clamp(off * L, -M.MAX_OFF, M.MAX_OFF)
	-- a quadratic Bezier whose middle passes the waypoint (control point at twice the offset), 12 points
	local cx, cy = (ax + bx) / 2 + nx * o * 2, (ay + by) / 2 + ny * o * 2
	local pts = {}
	for i = 0, 12 do
		local t = i / 12
		local u = 1 - t
		pts[#pts + 1] = { u * u * ax + 2 * u * t * cx + t * t * bx, u * u * ay + 2 * u * t * cy + t * t * by }
	end
	return pts, math.abs(o)
end

-- the heading from dead end `node` back along its own street (nil: unknown)
local function backHeading(g, node)
	if g == nil or node == nil or g.adj == nil or g.adj[node] == nil or #g.adj[node] ~= 1 then return nil end
	local e = g.edgeById[g.adj[node][1]]
	if e == nil or g.nodeById[node] == nil then return nil end
	local ok, h = pcall(OG.headingFrom, g, e, node)
	if ok then return h end
	return nil
end

--- A lead-out route (M.LEAD): a cubic curve from a leaving along heading ha, arriving at b along heading hb reversed (both
--- outward headings of the dead ends; nil: toward the other end), its control points swung `side` (-1 / 0 / 1) to one
--- side by LEAD_SIDE, 16 points.
function M.leadRoute(ax, ay, ha, bx, by, hb, side)
	local L = G.dist(ax, ay, bx, by)
	local k = math.min(M.LEAD_MAX, M.LEAD_K * L)
	ha = ha or G.atan2(by - ay, bx - ax)
	hb = hb or G.atan2(ay - by, ax - bx)
	local sd = (side or 0) * M.LEAD_SIDE * k
	local c1x, c1y = ax + math.cos(ha) * k - math.sin(ha) * sd, ay + math.sin(ha) * k + math.cos(ha) * sd
	local c2x, c2y = bx + math.cos(hb) * k + math.sin(hb) * sd, by + math.sin(hb) * k - math.cos(hb) * sd
	local pts = {}
	for i = 0, 16 do
		local t = i / 16
		local u = 1 - t
		pts[#pts + 1] = { u * u * u * ax + 3 * u * u * t * c1x + 3 * u * t * t * c2x + t * t * t * bx,
			u * u * u * ay + 3 * u * u * t * c1y + 3 * u * t * t * c2y + t * t * t * by }
	end
	return pts
end

--- A lead route swinging round must keep CLEAR from the end nodes' own streets (clearOfStreets skips them, so a route
--- running back along its own street would pass): true when every point beyond END_SKIP of both ends does.
local function ownClear(g, pts, a, b)
	if g == nil or g.adj == nil then return true end
	local segs = {}
	for _, node in ipairs({ a, b }) do
		for _, eid in ipairs(g.adj[node] or {}) do
			local e = g.edgeById[eid]
			local n0, n1 = e and g.nodeById[e.n0], e and g.nodeById[e.n1]
			if n0 and n1 then segs[#segs + 1] = { n0.x, n0.y, n1.x, n1.y } end
		end
	end
	local x0, y0, x1, y1 = pts[1][1], pts[1][2], pts[#pts][1], pts[#pts][2]
	for _, p in ipairs(G.resample(pts, 15)) do
		if G.dist(p[1], p[2], x0, y0) > M.END_SKIP and G.dist(p[1], p[2], x1, y1) > M.END_SKIP then
			for _, sg in ipairs(segs) do
				if G.pointSegDist(p[1], p[2], sg[1], sg[2], sg[3], sg[4]) < M.CLEAR then return false end
			end
		end
	end
	return true
end

local function leavesOk(g, node, px, py, qx, qy)
	local h = backHeading(g, node)
	if h == nil then return true end
	local lh = G.atan2(qy - py, qx - px)
	return math.abs(G.angleDiff(h, lh)) >= math.rad(M.BACK_DEG)
end

--- true when the polyline crosses no street of g and keeps CLEAR from every street, except at the end nodes a and b.
function M.clearOfStreets(g, pts, a, b)
	if g == nil then return true end
	local skip = { [a] = true, [b] = true }
	for i = 2, #pts do
		if OG.crossing(g, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], skip) then return false end
	end
	local x0, y0 = pts[1][1], pts[1][2]
	local x1, y1 = pts[#pts][1], pts[#pts][2]
	for i = 1, #pts - 1 do
		local p, q = pts[i], pts[i + 1]
		local L = G.dist(p[1], p[2], q[1], q[2])
		local n = math.max(1, math.ceil(L / 20))
		for k = 0, n do
			local px, py = p[1] + (q[1] - p[1]) * k / n, p[2] + (q[2] - p[2]) * k / n
			if G.dist(px, py, x0, y0) > M.END_SKIP and G.dist(px, py, x1, y1) > M.END_SKIP
				and OG.distToEdges(g, px, py, M.CLEAR, skip) then
				return false
			end
		end
	end
	return true
end

--- The route's points more than END_SKIP from both ends (for the obstacle test), as a polyline; nil when too short.
local function middle(pts)
	local x0, y0 = pts[1][1], pts[1][2]
	local x1, y1 = pts[#pts][1], pts[#pts][2]
	local fine = G.resample(pts, 15)
	local out = {}
	for _, p in ipairs(fine) do
		if G.dist(p[1], p[2], x0, y0) > M.END_SKIP and G.dist(p[1], p[2], x1, y1) > M.END_SKIP then out[#out + 1] = p end
	end
	if #out < 2 then return nil end
	return out
end

--- The passing link routes between dead ends `from` ({ {x, y, node} }) and `to`, best first. o = { sampler, seed,
--- from, to, g (the street graph holding both ends: crossings / clearance), obstacles (ot_engine.obstacles or nil),
--- zones (an ot_industry info with zones, or nil), maxOut, maxGrade }. Returns list { { from, to, pts, len, off, pair,
--- score } }, why (the most frequent failure when the list is empty: "noDeadEnds" | "far" | "back" | "crossing" |
--- "obstacle" | "zone" | "wet" | "steep"), info { pairs, tests, fails = { [why] = n } }.
function M.candidates(o)
	local s = o.sampler
	local info = { pairs = 0, tests = 0, fails = {} }
	local pairs_ = {}
	for _, a in ipairs(o.from or {}) do
		for _, b in ipairs(o.to or {}) do
			if a[3] ~= b[3] then pairs_[#pairs_ + 1] = { a = a, b = b, d = G.dist(a[1], a[2], b[1], b[2]) } end
		end
	end
	if #pairs_ == 0 then return {}, "noDeadEnds", info end
	table.sort(pairs_, function(p, q)
		if p.d ~= q.d then return p.d < q.d end
		if p.a[3] ~= q.a[3] then return p.a[3] < q.a[3] end
		return p.b[3] < q.b[3]
	end)
	local function fail(w) info.fails[w] = (info.fails[w] or 0) + 1 end
	local out = {}
	local maxOut = o.maxOut or M.MAX_OUT
	local grade = o.maxGrade or M.MAX_GRADE
	local usedFrom, usedTo = {}, {}
	for i = 1, math.min(#pairs_, M.MAX_PAIRS) do
		if #out >= maxOut or info.tests >= M.MAX_TESTS then break end
		local p = pairs_[i]
		info.pairs = info.pairs + 1
		-- (one route per end pair is enough: the next candidates start from other dead ends, so a refusal of one
		-- end's street does not sink every candidate)
		if p.d < M.MIN_D or p.d > M.MAX_D then fail("far")
		elseif not (usedFrom[p.a[3]] and usedTo[p.b[3]]) then
			local offs = { M.OFFSETS[1] }
			if M.LEAD then offs[#offs + 1] = "lead"; offs[#offs + 1] = "leadL"; offs[#offs + 1] = "leadR" end
			for k = 2, #M.OFFSETS do offs[#offs + 1] = M.OFFSETS[k] end
			for oi, off in ipairs(offs) do
				if info.tests >= M.MAX_TESTS then break end
				info.tests = info.tests + 1
				local pts, offM
				local lead = type(off) == "string"
				if lead then
					local ha, hb = backHeading(o.g, p.a[3]), backHeading(o.g, p.b[3])
					pts = M.leadRoute(p.a[1], p.a[2], ha and ha + math.pi or nil, p.b[1], p.b[2], hb and hb + math.pi or nil,
						off == "leadL" and 1 or (off == "leadR" and -1 or 0))
					-- (its detour for the score: the farthest point off the straight line)
					offM = 0
					for _, q in ipairs(pts) do
						offM = math.max(offM, G.pointSegDist(q[1], q[2], p.a[1], p.a[2], p.b[1], p.b[2]))
					end
				else
					pts, offM = M.route(p.a[1], p.a[2], p.b[1], p.b[2], off, o.seed)
				end
				offM = offM or 0
				local why = nil
				local n = #pts
				if not leavesOk(o.g, p.a[3], pts[1][1], pts[1][2], pts[2][1], pts[2][2])
					or not leavesOk(o.g, p.b[3], pts[n][1], pts[n][2], pts[n - 1][1], pts[n - 1][2]) then
					why = "back"
				elseif lead and not ownClear(o.g, pts, p.a[3], p.b[3]) then
					why = "back"
				elseif not M.clearOfStreets(o.g, pts, p.a[3], p.b[3]) then why = "crossing"
				else
					local mid = middle(pts)
					if mid and o.obstacles and not SAT.clearOfObstacles(o.obstacles, mid) then why = "obstacle"
					elseif mid and o.zones and IND.zoneHit(o.zones, mid) then why = "zone"
					elseif s and T.wetAlong(s, pts, 20, 40) then why = "wet"
					elseif s and T.pathMaxGrade(s, pts, 40) > grade then why = "steep" end
				end
				if why then fail(why)
				else
					local len = 0
					for k = 2, n do len = len + G.dist(pts[k - 1][1], pts[k - 1][2], pts[k][1], pts[k][2]) end
					out[#out + 1] = { from = p.a, to = p.b, pts = pts, len = len, off = off, offM = offM, pair = i,
						score = len + M.DETOUR_COST * offM, route = oi }
					usedFrom[p.a[3]], usedTo[p.b[3]] = true, true
					break
				end
			end
		end
	end
	table.sort(out, function(x, y)
		if math.abs(x.score - y.score) > 1e-6 then return x.score < y.score end
		return x.pair < y.pair
	end)
	if #out == 0 then
		local best, bn = "noFit", 0
		for _, w in ipairs({ "far", "back", "crossing", "obstacle", "zone", "wet", "steep" }) do
			if (info.fails[w] or 0) > bn then best, bn = w, info.fails[w] end
		end
		return out, best, info
	end
	return out, nil, info
end

--- "why:n/why:n" of info.fails ("-" when none).
function M.failText(info)
	if info == nil or info.fails == nil then return "-" end
	local parts = {}
	for _, w in ipairs({ "far", "back", "crossing", "obstacle", "zone", "wet", "steep" }) do
		if info.fails[w] then parts[#parts + 1] = w .. ":" .. info.fails[w] end
	end
	return #parts > 0 and table.concat(parts, "/") or "-"
end

--- ot_plan streets of a link (key "<key>:link", lead = "lane": ot_lead.mark makes its middle the era's country lane).
function M.streets(lk, key)
	return { { pts = lk.pts, class = "small", startNode = lk.from[3], endNode = lk.to[3], key = (key or "link") .. ":link",
		lead = "lane", curved = true } }
end

return M
