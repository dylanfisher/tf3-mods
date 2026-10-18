-- Organic Towns: country lanes laid well ahead (pure; 2026-10-13, round after the names run).
--
-- User (run 2026-10-13_2113_sqot-dev, Henley-in-Arden): "Country roads built way off in advance would make more sense,
-- and then offshoots of streets at the end of the country road offshoot." So a town picked for it (sparingly, seeded,
-- a map quota) lays ONE country lane out from a dead end at its edge, along its growth direction: toward a neighbour
-- town, along its shape's axis, or toward its satellite village's site, LEN m beyond the edge (a few hundred metres to
-- ~1 km). The lane is the era's base country template (ot_lane.templateFor), locked (roadDevelopmentLocked: the game
-- never turns it into a town street, and no houses line it); at its far end a few plain town streets, unlocked, so the
-- town grows there later on its own: a hamlet (a T and a stub on) or a ribbon (the lane's last RIBBON_F as a town street).
--
-- Rules: the far end stays on this town's side of every gap line (ot_gap: R3 gaps, never past the halfway line, the
-- engine's owner near the line), inside the map margin, dry (no water along: no bridge), at most MAX_GRADE, clear of the
-- town's streets and of the obstacles beyond the snapshot (ot_satellite.linkClear / clearOfObstacles), not along an
-- existing country road (that way is served already). Forest is fine for a lane (it gets no houses) but open land or
-- the forest edge scores better. The first edge from the dead end is a joined town street (the proposal never makes a
-- joined edge a lane), every new node gets its BASE_NODE_CONFIG like any increment (ot_proposal).
--
-- Save-safe: plain base templates; the town's frame keeps `ld` once it is built (ot_saved), so a reload never lays a
-- second one. Every loop is bounded by the tables (targets x dead ends x shortening steps). Plain Lua, pre-5.3.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local SAT = ug_require "square_organic_towns::/organic_towns/ot_satellite.lua"
local GP = ug_require "square_organic_towns::/organic_towns/ot_gap.lua"
local MAP = ug_require "square_organic_towns::/organic_towns/ot_map.lua"
local FO = ug_require "square_organic_towns::/organic_towns/ot_forest.lua"
local LK = ug_require "square_organic_towns::/organic_towns/ot_link.lua"

local M = {}

M.ON = true
M.CHANCE = 0.3            -- seeded share of the eligible towns
M.MIN_BUILDINGS = 60      -- a town this big (buildings) at least ...
M.MAX_BUILDINGS = 1500    -- ... and not yet this big ("early")
M.NO_STYLE = { SUPERBLOCK = true, MED_ENSANCHE = true }
M.MAP_SHARE = 0.25        -- map quota: at most this share of the towns (MAP_MIN at least) lay one
M.MAP_MIN = 1
-- (2026-10-14, the vanilla baseline: the long straight empty lanes ending in a T were the mod's most visible flaw,
-- Chipping Campden / Ampthill / Chorleywood / Henley-in-Arden; 400-1000 m until now) shorter and curved (BEND: a seeded
-- waypoint off the line, ot_link.route), more ribbon ends; a town with a district lays none (ot_driver)
M.LEN = { 250, 600 }      -- m beyond the dead end (seeded per town), shortened in SHORTEN steps to fit
M.MIN_LEN = 200
M.BEND = { 0.08, 0.16 }   -- the curve's waypoint off the line, x its length, either side (seeded)
M.SHORTEN = 50
M.EDGE_F = 0.6            -- the dead end at least this x the houses' extent radius from the centre (the town's edge)
M.AIM_DEG = 40            -- dead ends whose outward heading lies within this of the target heading
M.MAX_GRADE = 0.08
M.ROAD_R = 150            -- a road (not a town street) this close to the lane's far half: that way is served already
M.NEIGHBOUR_MAX = 6000    -- m: neighbours this near are targets
M.NEIGHBOUR_MIN = 1200
M.END_HAMLET = 0.4        -- seeded share of hamlet ends (the rest: ribbon ends)
M.T_ARM = 60              -- m: the far T's arms
M.T_ON = 50               -- m: its stub on along the lane
M.RIBBON_F = 0.3          -- the ribbon end: the lane's last share as a town street ...
M.RIBBON_MAX_M = 120      -- ... at most this long (run 2026-10-13_2240_sqot-dev: Tickhill's 5-edge ribbon end 800 m
                          -- out stayed empty; the game fills by network distance from the core)
M.END_FILL = true         -- the far end's town streets get a dose (DevelopAt beside them) at the build: the houses
                          -- start there instead of waiting for the town to reach them (the driver's fill)
M.FOREST_W = 0.5          -- score: a wooded lane costs this x its mean cover
M.KIND_RANK = { neighbour = 0, satellite = 0.15, axis = 0.3, frame = 0.5 }

--- Is town t a lead-lane town? o = { seed, buildings, metro (bool), has (one already), styleId, quotaLeft (bool) }.
--- Returns true / false, why ("off" | "has" | "small" | "big" | "metro" | "style" | "quota" | "rare" | "seeded").
function M.eligible(o)
	if not M.ON then return false, "off" end
	if o.has then return false, "has" end
	local b = o.buildings or 0
	if b < M.MIN_BUILDINGS then return false, "small" end
	if b > M.MAX_BUILDINGS then return false, "big" end
	if o.metro then return false, "metro" end
	if M.NO_STYLE[o.styleId or ""] then return false, "style" end
	-- (§66: a residential lean by deliveries lays its ribbon ahead more often; ot_rci CHANCE_MUL)
	if rng.decide(o.dv, o.seed or 1, "leadLane") >= M.CHANCE * (tonumber(o.chanceMul) or 1) then return false, "rare" end
	if o.quotaLeft == false then return false, "quota" end
	return true, "seeded"
end

--- The map quota for n towns.
function M.quota(n)
	return math.max(M.MAP_MIN, math.ceil(M.MAP_SHARE * (n or 0)))
end

--- Target headings, best first: { { heading, kind = "neighbour" | "satellite" | "axis", d } }. o = { cx, cy,
--- neighbours = { { dir, dist } } (ot_driver neighbours), axis = the shape's axis (rad) or nil, sat = { x, y } or nil,
--- frameAxis = the plan frame's axis (rad: the last resort) or nil }.
function M.targets(o)
	local out = {}
	for _, nb in ipairs(o.neighbours or {}) do
		if nb.dist >= M.NEIGHBOUR_MIN and nb.dist <= M.NEIGHBOUR_MAX and #out < 4 then
			out[#out + 1] = { heading = nb.dir, kind = "neighbour", d = nb.dist }
		end
	end
	if o.sat then out[#out + 1] = { heading = G.atan2(o.sat[2] - o.cy, o.sat[1] - o.cx), kind = "satellite" } end
	if o.axis then
		out[#out + 1] = { heading = o.axis, kind = "axis" }
		out[#out + 1] = { heading = G.wrap(o.axis + math.pi), kind = "axis" }
	end
	-- (no neighbour, satellite or shape: the plan frame's axis, both ways and across; every town has one)
	if #out == 0 and o.frameAxis then
		for k = 0, 3 do out[#out + 1] = { heading = G.wrap(o.frameAxis + k * math.pi / 2), kind = "frame" } end
	end
	return out
end

local function coverAlong(fo, pts)
	if fo == nil or fo.grid == nil then return 0 end
	local ok, c = pcall(FO.pen, fo, pts)
	return ok and c or 0
end

--- The lane: { deadEnd = {x, y, node}, pts, len, heading, target (kind), score, cover, grade, endKind } or nil, why.
--- o = { cx, cy, r (the houses' extent), sampler, seed, deadEnds = { {x, y, node} }, targets (M.targets), gaps (ot_gap),
--- bounds (ot_map) or nil, g (town graph: links clear of its streets) or nil, obstacles (ot_engine.obstacles) or nil,
--- roads = { {x, y} } (midpoints of non-town streets) or nil, forest (the style's forest info) or nil,
--- owner = function(x, y) (the engine's closest town is this one) or nil }.
function M.pick(o)
	local s = o.sampler
	if s == nil or o.deadEnds == nil or #o.deadEnds == 0 then return nil, "noDeadEnd" end
	if o.targets == nil or #o.targets == 0 then return nil, "noTarget" end
	local L0 = M.LEN[1] + rng.unit(o.seed or 1, "leadLen") * (M.LEN[2] - M.LEN[1])
	local best, why = nil, "noFit"
	local tried = 0
	for ti, tg in ipairs(o.targets) do
		for _, de in ipairs(o.deadEnds) do
			local dd = G.dist(o.cx, o.cy, de[1], de[2])
			local out = G.atan2(de[2] - o.cy, de[1] - o.cx)
			if dd >= M.EDGE_F * (o.r or 0) and math.abs(G.angleDiff(out, tg.heading)) <= math.rad(M.AIM_DEG) then
				tried = tried + 1
				local L = L0
				while L >= M.MIN_LEN do
					local fx, fy = de[1] + math.cos(tg.heading) * L, de[2] + math.sin(tg.heading) * L
					local u = rng.unit((o.seed or 1) + ti, "leadBend")
					local off = (M.BEND[1] + (M.BEND[2] - M.BEND[1]) * u) * ((rng.unit((o.seed or 1) + ti, "leadSide") < 0.5) and -1 or 1)
					local pts = LK.route(de[1], de[2], fx, fy, off, o.seed)
					local okP = not MAP.polyNearEdge(o.bounds, pts, MAP.MARGIN)
					okP = okP and GP.held(o.gaps, pts, "small") == nil
					okP = okP and (o.owner == nil or o.owner(fx, fy))
					okP = okP and not T.wetAlong(s, pts, 20, 40)
					local grade = okP and T.pathMaxGrade(s, pts, 40) or 1
					okP = okP and grade <= M.MAX_GRADE
					okP = okP and SAT.linkClear(o.g, pts, de[3]) and SAT.clearOfObstacles(o.obstacles, pts, SAT.START_SKIP)
					if okP then
						-- an existing road along the far half: that way is served already
						local served = false
						for _, rp in ipairs(o.roads or {}) do
							for k = 5, #pts do
								if G.dist(rp[1], rp[2], pts[k][1], pts[k][2]) <= M.ROAD_R then served = true break end
							end
							if served then break end
						end
						if not served then
							local cover = coverAlong(o.forest, pts)
							local score = math.abs(G.angleDiff(out, tg.heading)) / math.rad(M.AIM_DEG)
								+ (M.KIND_RANK[tg.kind] or 0.5) + M.FOREST_W * cover + 5 * grade + 0.3 * (1 - L / L0)
								+ 0.25 * rng.unit(o.seed or 1, "leadPick", de[3], ti)
							if best == nil or score < best.score then
								best = { deadEnd = de, pts = pts, len = L, heading = tg.heading, target = tg.kind, score = score,
									cover = cover, grade = grade }
							end
						else
							why = "served"
						end
						break
					end
					L = L - M.SHORTEN
				end
			end
		end
	end
	if best == nil then return nil, tried == 0 and "noAlignedDeadEnd" or why end
	best.endKind = rng.decide(o.dv, o.seed or 1, "leadEnd") < M.END_HAMLET and "hamlet" or "ribbon"
	return best, tried
end

--- ot_plan streets for the lane: the lane from the dead end (key "lead:lane", lead = "lane"; a ribbon end splits off
--- its last RIBBON_F as "lead:ribbon", lead = "end") and, for a hamlet end, a T at the far end (two arms and a stub on,
--- lead = "end").
function M.streets(site)
	local de, pts = site.deadEnd, site.pts
	local out = {}
	local n = #pts
	local fx, fy = pts[n][1], pts[n][2]
	if site.endKind == "ribbon" then
		local L = G.polyLen(pts)
		local cut = math.floor(n * (1 - M.RIBBON_F) + 0.5)
		cut = math.max(2, math.min(n - 1, cut))
		-- (the ribbon at most RIBBON_MAX_M: the cut moves out while the rest is longer)
		local function restLen(c)
			local l = 0
			for i = c, n - 1 do l = l + G.dist(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]) end
			return l
		end
		while cut < n - 1 and restLen(cut) > M.RIBBON_MAX_M do cut = cut + 1 end
		local lane, rib = {}, {}
		for i = 1, cut do lane[#lane + 1] = { pts[i][1], pts[i][2] } end
		for i = cut, n do rib[#rib + 1] = { pts[i][1], pts[i][2] } end
		out[#out + 1] = { pts = lane, class = "small", startNode = de[3], key = "lead:lane", lead = "lane", curved = true }
		out[#out + 1] = { pts = rib, class = "small", key = "lead:ribbon", lead = "end", len = math.min(L * M.RIBBON_F, restLen(cut)) }
		return out
	end
	-- (2026-10-14 late: planned as a curved street, so the bend is real curves, not straight chords with kinks)
	out[#out + 1] = { pts = pts, class = "small", startNode = de[3], key = "lead:lane", lead = "lane", curved = true }
	local a = G.heading(pts[n - 1][1], pts[n - 1][2], fx, fy)
	local ux, uy = math.cos(a), math.sin(a)
	local px, py = -uy, ux
	out[#out + 1] = { pts = { { fx, fy }, { fx + px * M.T_ARM, fy + py * M.T_ARM } }, class = "small", key = "lead:t1", lead = "end" }
	out[#out + 1] = { pts = { { fx, fy }, { fx - px * M.T_ARM, fy - py * M.T_ARM } }, class = "small", key = "lead:t2", lead = "end" }
	out[#out + 1] = { pts = { { fx, fy }, { fx + ux * M.T_ON, fy + uy * M.T_ON } }, class = "small", key = "lead:on", lead = "end" }
	return out
end

--- Marks an increment planned from M.streets: the lane street's edges between two new nodes get the country template
--- (e.forestLane = path: ot_proposal makes them locked country edges, a joined edge stays the town street). Returns the
--- lane edge count, the end (town street) edge count and the lane length.
function M.mark(inc, streets, path)
	local lane, ends, len = 0, 0, 0
	for _, e in ipairs(inc and inc.edges or {}) do
		local st = streets[e.street]
		if st and st.lead == "lane" and (e.node0 or 0) < 0 and (e.node1 or 0) < 0 and not e.bridge then
			e.forestLane = path
			lane = lane + 1
			len = len + G.dist(e.p0[1], e.p0[2], e.p1[1], e.p1[2])
		elseif st and st.lead == "end" then
			ends = ends + 1
		end
	end
	return lane, ends, len
end

--- Are the end streets of a lane plan joined to the lane (one network with the joined first edge)? Returns the end
--- edges joined, the end edges in all. Union-find over the increment's node ids (new < 0, existing > 0).
function M.endJoined(inc, streets)
	local parent = {}
	local function find(x)
		local r = x
		for _ = 1, 10000 do
			if parent[r] == nil or parent[r] == r then break end
			r = parent[r]
		end
		return r
	end
	local function union(a, b)
		if a == nil or b == nil then return end
		local ra, rb = find(a), find(b)
		if ra ~= rb then parent[ra] = rb end
	end
	local root = nil
	for _, e in ipairs(inc and inc.edges or {}) do
		union(e.node0, e.node1)
		local st = streets[e.street]
		if st and st.lead == "lane" and root == nil and ((e.node0 or 0) > 0 or (e.node1 or 0) > 0) then
			root = (e.node0 or 0) > 0 and e.node0 or e.node1
		end
	end
	local joined, all = 0, 0
	for _, e in ipairs(inc and inc.edges or {}) do
		local st = streets[e.street]
		if st and st.lead == "end" then
			all = all + 1
			if root ~= nil and e.node0 ~= nil and find(e.node0) == find(root) then joined = joined + 1 end
		end
	end
	return joined, all
end

--- DevelopAt points beside the far end's town streets: { {x, y} }, one per end edge (both sides alternating), at most n,
--- off (metres) to the side.
function M.endFillPoints(inc, streets, off, n)
	local out = {}
	if not M.END_FILL then return out end
	local k = 0
	for _, e in ipairs(inc and inc.edges or {}) do
		local st = streets[e.street]
		if st and st.lead == "end" and #out < (n or 2) then
			local dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
			local l = math.sqrt(dx * dx + dy * dy)
			if l > 1 then
				k = k + 1
				local side = (k % 2 == 1) and 1 or -1
				local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
				out[#out + 1] = { mx - dy / l * off * side, my + dx / l * off * side }
			end
		end
	end
	return out
end

return M
