-- Organic Towns: road / village motifs (pure). Phase M2 of the motifs plan (plans/square_organic_towns/MOTIFS_BRIEF.md,
-- 2026-10-13). Registered into the ot_motif registry by ot_motif (RD.registerAll(MO)); drawn kinds (0-2 per town, seeded,
-- saved on the frame, neighbour diversity), MO.IDS 7-9.
--
--   ribbon_village     (Strassendorf / English ribbon development) houses strung along a country road out of town: the
--                      road itself can't be joined (country-road nodes: ot_roads header), so a town street runs beside
--                      it at a setback (32-45 m: one row of lots between it and the road), from the town's dead end
--                      nearest where the road leaves the houses (L.anchors), 450-750 m out, with 2-4 short dead-end
--                      lanes off its far side; the plan's other streets kept out of the strip (the ribbon reads as one
--                      street of houses along the road, meadow behind). The build's DevelopAt dose goes on the road side
--                      (the houses face the road), its streets are locked (the game hangs no side streets on them).
--   village_green      (Angerdorf / English green) an oval green (a lens: the street splits around it and joins again)
--                      or, at a road fork (two roads leaving 35-120 deg apart), a triangle along the two roads; 240-360 m
--                      out from the centre (at the edge of a small town's core, inside it later), bounded by streets on
--                      every side, linked to the town's dead end by a short stub (L.anchors); the plan's streets kept out
--                      of the green, the green's streets locked (no side streets into it). Houses line it outside; the
--                      game's lots on the inner side leave a meadow in the middle.
--   crossroads_hamlet  a small cluster where two country roads meet 0.45-1.6 km out: the satellite stage (ot_satellite)
--                      seeds it beside the crossroads (in a quadrant between the roads, 90-170 m from the junction) with
--                      its own link street from the town (the junction can't be joined); smaller towns qualify
--                      (HAMLET_MIN_BUILDINGS), no seeded chance. The motif only picks the junction (style.hamlet).
--
-- Country roads: style.roads (ot_roads.trace, from the driver: followed beyond the snapshot) or, without it, the roads
-- in the town graph (ot_roads.fromGraph). Geometry is derived each session from the centre, the roads, the terrain and the
-- seed (stable), not saved beyond the frame's motif ids.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"
local RDS = ug_require "square_organic_towns::/organic_towns/ot_roads.lua"
local L = ug_require "square_organic_towns::/organic_towns/ot_motif_land.lua"

local M = {}

local cos, sin, abs, floor, max, min = math.cos, math.sin, math.abs, math.floor, math.max, math.min

M.ON = true
M.VIRTUAL_K = 0.8          -- ribbon / green on virtual roads (ot_roads.virtual: no country road near the town)
M.ERA_LATE = 1950          -- ribbon / green: x LATE_K from this year (the motor age: estates, not ribbons)
M.LATE_K = 0.55

-- ribbon village
M.RB = {
	OFF = { 0.6, 32, 45 },     -- setback of the ribbon street from the road: x block depth, clamped (m)
	LEN = { 450, 750 },        -- m beyond the town (seeded)
	MIN_LEN = 200,             -- m beyond the town at least
	STEP = 20,
	CLEAR = 22,                -- m from other streets / roads beyond the town
	GRADE = 0.8,               -- x maxSlope between steps at most
	LANES = { 2, 4 },          -- side lanes (seeded)
	LANE_GAP = { 140, 190 },   -- m between them (seeded)
	LANE_LEN = { 1.4, 60, 110 },
	LANE_MIN = 40,
	LANE_GRADE = 0.75,
}
-- village green
M.VG = {
	D = { 240, 360 },          -- m from the centre to the green's town end (seeded)
	PUSH = 60, PUSH_N = 4,     -- ... pushed out this much (up to n times) while the town's streets occupy it
	LEN = { 220, 280 },        -- lens length (seeded)
	WIDTH = 0.3,               -- lens half width x its length
	SIDE = { 220, 270 },       -- triangle side (seeded)
	HALF = { math.rad(25), math.rad(40) },  -- triangle half angle (the fork's half, clamped)
	STUB = 150,                -- m: the link stub toward the town (anchors join its town 70 %)
	CLEAR = 20,                -- m from other streets / roads
	SLOPE = 0.7,               -- x maxSlope inside the green at most
	DIRS = 16,
	FORK_TOL = math.rad(20),   -- directions tried around a fork's bisector (+-)
	OURS = 1,                  -- built edges along the green's lines: the green is there (keep it, never move it)
	LOT = 35,                  -- m: the inner lots (the green's measure counts houses deeper inside as on the green)
	ROOM = 26,                 -- m: the plan's own streets keep this far from the green's streets (but at a T)
}
-- crossroads hamlet
M.HM = {
	D = { 450, 1600 },         -- m from the centre
	GAP = 220,                 -- m beyond the houses' extent at least
}

local function blk(style) return L.blk(style) end

local function roadsOf(style, g)
	if style.roads then return style.roads end
	if g == nil then return nil end
	return RDS.fromGraph(g, style.centre[1], style.centre[2], max(style.radius or 0, blk(style)))
end

---------------------------------------------------------------------------
-- segment index (country-road segments beyond the snapshot)

local SEG_CELL = 100
local function segIndex(segs)
	local idx = {}
	for _, sg in ipairs(segs or {}) do
		-- (G.cellRange: a bad / huge segment stays out of the index, hang guard)
		local x0, x1, y0, y1 = G.cellRange(sg[1], sg[2], sg[3], sg[4], 40, SEG_CELL)
		for cx = x0 or 1, x1 or 0 do
			for cy = y0, y1 do
				local k = cx * 65536 + cy
				local l = idx[k]
				if l == nil then l = {}; idx[k] = l end
				l[#l + 1] = sg
			end
		end
	end
	return idx
end

local function segNear(idx, x, y, r)
	for _, sg in ipairs(idx[floor(x / SEG_CELL) * 65536 + floor(y / SEG_CELL)] or {}) do
		if G.pointSegDist(x, y, sg[1], sg[2], sg[3], sg[4]) < r then return true end
	end
	return false
end

local function segCross(idx, ax, ay, bx, by)
	local seen = {}
	for _, p in ipairs({ { ax, ay }, { bx, by } }) do
		for _, sg in ipairs(idx[floor(p[1] / SEG_CELL) * 65536 + floor(p[2] / SEG_CELL)] or {}) do
			if not seen[sg] then
				seen[sg] = true
				if G.segIntersect(ax, ay, bx, by, sg[1], sg[2], sg[3], sg[4], 1e-6) then return true end
			end
		end
	end
	return false
end

local function pointInPoly(poly, x, y)
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
		if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
		j = i
	end
	return inside
end

local function polyDist(poly, x, y)
	local best = math.huge
	for i = 1, #poly do
		local a, b = poly[i], poly[i % #poly + 1]
		local d = G.pointSegDist(x, y, a[1], a[2], b[1], b[2])
		if d < best then best = d end
	end
	return best
end

--- Drops (in place) the plan's own pieces (not motif pieces) that come within r m of any of the indexed lines anywhere
--- but at an end lying on one (a T onto the motif's street): the motif's streets keep their room (the climb's corridor
--- likewise), the town's streets reach them only head on.
local function clearAround(mp, ixs, r)
	-- (a box around the lines: pieces wholly outside it are kept without a look)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, ix in ipairs(ixs) do
		for _, p in ipairs(ix.pts) do
			x0, y0, x1, y1 = min(x0, p[1]), min(y0, p[2]), max(x1, p[1]), max(y1, p[2])
		end
	end
	x0, y0, x1, y1 = x0 - r, y0 - r, x1 + r, y1 + r
	local kept = {}
	for _, pc in ipairs(mp.pieces) do
		local drop = false
		local outside = true
		for _, p in ipairs(pc.pts) do
			if p[1] >= x0 and p[1] <= x1 and p[2] >= y0 and p[2] <= y1 then outside = false; break end
		end
		if outside and #pc.pts >= 2 then
			-- (a long straight piece may cross the box between its points)
			local a, b = pc.pts[1], pc.pts[#pc.pts]
			if G.dist(a[1], a[2], b[1], b[2]) > 0.5 * min(x1 - x0, y1 - y0) then outside = false end
		end
		if pc.motif == nil and not outside then
			local a, b = pc.pts[1], pc.pts[#pc.pts]
			local function onLine(p)
				for _, ix in ipairs(ixs) do if L.nearest(ix, p[1], p[2], 2) then return true end end
				return false
			end
			local ta, tb = onLine(a), onLine(b)
			for _, p in ipairs(G.resample(pc.pts, 10)) do
				local nearEnd = (ta and G.dist(p[1], p[2], a[1], a[2]) < r + 5) or (tb and G.dist(p[1], p[2], b[1], b[2]) < r + 5)
				if not nearEnd then
					for _, ix in ipairs(ixs) do
						if L.nearest(ix, p[1], p[2], r) then drop = true; break end
					end
				end
				if drop then break end
			end
		end
		if not drop then kept[#kept + 1] = pc end
	end
	mp.pieces = kept
	mp._through, mp._corr, mp._corrMain = nil, nil, nil
end
M.clearAround = clearAround

local function eraK(ctx)
	return (ctx.year or 1900) >= M.ERA_LATE and M.LATE_K or 1
end

--- DevelopAt points beside the build's edges on the indexed line, on side sgn (> 0: left of travel), off m out; at
--- most n, spread along the line.
local function doseSide(ix, edges, off, n, sgn)
	local out = {}
	for _, e in ipairs(edges or {}) do
		if e.p0 and e.p1 then
			local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
			local d, s = L.nearest(ix, mx, my, 10)
			if d then
				local x, y, ux, uy = L.at(ix, s)
				out[#out + 1] = { s = s, x = x - uy * off * sgn, y = y + ux * off * sgn }
			end
		end
	end
	table.sort(out, function(a, b) return a.s < b.s end)
	local pts = {}
	local k = min(n, #out)
	for i = 1, k do
		local c = out[max(1, min(#out, floor((i - 0.5) * #out / k) + 1))]
		pts[#pts + 1] = { G.round(c.x, 1), G.round(c.y, 1) }
	end
	return pts
end

---------------------------------------------------------------------------
-- ribbon village

--- The ribbon's plan geometry (pure): { line, ix, road (index), sd (side of the road: the street = road + left x off x
--- sd), off, lanes = { { s, x0, y0, x1, y1, len } }, r0, laneMax, stop, beyond (m of line beyond the town) } or nil, why.
function M.ribbonGeo(style, g, sampler, extent)
	if sampler == nil then return nil, "noTerrain" end
	local roads = roadsOf(style, g)
	if roads == nil or #(roads.roads or {}) == 0 then return nil, "noRoad" end
	local rb = M.RB
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local b = blk(style)
	local r = max(style.radius or 0, b)
	local depth = style.block and style.block.depth or 60
	local off = L.clampSpec(rb.OFF, depth)
	-- (virtual roads, ot_roads.virtual: no road to keep beside: the ribbon street is the road out of town itself)
	local virtual = roads.virtual == true
	if virtual then off = 0 end
	local setback = style.waterSetback or 25
	local maxSlope = style.maxSlope or 0.1
	local sStart = max(r - b, 0.5 * r)
	local want = rb.LEN[1] + rng.unit(seed, "mrbLen") * (rb.LEN[2] - rb.LEN[1])
	extent = extent or 1500
	local sidx = segIndex(roads.segs)
	local best = nil
	for ri, rd in ipairs(roads.roads) do
		if rd.out >= r + rb.MIN_LEN and #rd.pts >= 2 then
			local rix = L.index(rd.pts)
			local s0 = nil
			for s = 0, rix.len, 10 do
				local x, y = L.at(rix, s)
				if G.dist(cx, cy, x, y) >= sStart then s0 = s; break end
			end
			if s0 then
				local s1 = min(rix.len, s0 + want + (r - sStart))
				-- (streets on this side's offset line, or ending on it: the ribbon's own and the town's streets meeting it in
				-- a T, from earlier builds; they never stop the line, so the geometry stays put as the town builds it)
				local function onLine(n, sd)
					local d, _, side = L.nearest(rix, n.x, n.y, off + 10)
					if virtual then return d ~= nil and d < 8 end
					return d ~= nil and abs(d - off) < 8 and side * sd > 0
				end
				for _, sd in ipairs(virtual and { 1 } or { 1, -1 }) do
					local raw, zPrev, stop = {}, nil, "len"
					local ours = 0
					for _, e in ipairs(g and g.edges or {}) do
						local a, b2 = g.nodeById[e.n0], g.nodeById[e.n1]
						if a and b2 and e.locked and onLine(a, sd) and onLine(b2, sd) and G.dist(cx, cy, a.x, a.y) > r then
							ours = ours + 1
						end
					end
					for s = s0, s1, rb.STEP do
						local x, y, ux, uy = L.at(rix, s)
						local px, py = x - uy * off * sd, y + ux * off * sd
						local dc = G.dist(cx, cy, px, py)
						if L.wetNear(sampler, px, py, setback) then stop = "water"; break end
						if L.offEdge(style, px, py) then stop = "edge"; break end
						if dc > extent then stop = "extent"; break end
						-- (only the country roads stop it: the town's own streets come and go as it grows, and the planner
						-- refuses a piece that would hit one; the line must stay put across plans)
						if dc > r + 0.5 * b then
							if segNear(sidx, px, py, rb.CLEAR) then stop = "road"; break end
							local q = raw[#raw]
							if q and segCross(sidx, q[1], q[2], px, py) then stop = "cross"; break end
						end
						local z = T.height(sampler, px, py)
						if zPrev and abs(z - zPrev) / rb.STEP > rb.GRADE * maxSlope then stop = "steep"; break end
						raw[#raw + 1] = { px, py }
						zPrev = z
					end
					local beyond = 0
					for i = 2, #raw do
						if G.dist(cx, cy, raw[i][1], raw[i][2]) > r then
							beyond = beyond + G.dist(raw[i - 1][1], raw[i - 1][2], raw[i][1], raw[i][2])
						end
					end
					if beyond >= rb.MIN_LEN then
						-- (a side the ribbon was begun on stays the ribbon's)
						local sc = beyond + 40 * rng.unit(seed, "mrbPick", ri, sd) + (ours >= 2 and 10000 or 0)
						if best == nil or sc > best.score then
							best = { raw = raw, road = ri, sd = sd, stop = stop, beyond = beyond, score = sc }
						end
					end
				end
			end
		end
	end
	if best == nil then return nil, "noRoom" end
	local line = L.smooth(best.raw, 100)
	if line == nil or G.polyLen(line) < rb.MIN_LEN then return nil, "noRoom" end
	local ix = L.index(line)
	local sd = best.sd
	-- side lanes off the far side (away from the road), beyond the town
	local r0 = L.dropFrom(style)
	local laneMax = L.clampSpec(rb.LANE_LEN, depth)
	local nWant = rb.LANES[1] + floor(rng.unit(seed, "mrbLanes") * (rb.LANES[2] - rb.LANES[1] + 1))
	local gap = rb.LANE_GAP[1] + rng.unit(seed, "mrbGap") * (rb.LANE_GAP[2] - rb.LANE_GAP[1])
	local sA = nil
	for s = 0, ix.len, 10 do
		local x, y = L.at(ix, s)
		if G.dist(cx, cy, x, y) >= r0 + 20 then sA = s; break end
	end
	local lanes = {}
	if sA then
		local s = sA + gap * (0.3 + 0.4 * rng.unit(seed, "mrbFirst"))
		local guard = G.LOOP_CAP
		while s < ix.len - 40 and #lanes < nWant and guard > 0 do
			guard = guard - 1
			local x, y, ux, uy = L.at(ix, s)
			-- (a virtual road: the lanes alternate sides, there is no road side to keep free)
			local lsd = (virtual and #lanes % 2 == 1) and -sd or sd
			local nx, ny = -uy * lsd, ux * lsd
			local len, z = 0, T.height(sampler, x, y)
			for d = 10, laneMax, 10 do
				local px, py = x + nx * d, y + ny * d
				if L.wetNear(sampler, px, py, setback) or L.offEdge(style, px, py) then break end
				if segNear(sidx, px, py, rb.CLEAR) then break end
				local pz = T.height(sampler, px, py)
				if abs(pz - z) / 10 > rb.LANE_GRADE * maxSlope then break end
				len, z = d, pz
			end
			if len >= rb.LANE_MIN then
				lanes[#lanes + 1] = { s = s, x0 = x, y0 = y, x1 = x + nx * len, y1 = y + ny * len, len = len }
			end
			s = s + gap
		end
	end
	return { line = line, ix = ix, road = best.road, sd = sd, off = off, lanes = lanes, r0 = r0, laneMax = laneMax,
		stop = best.stop, beyond = best.beyond, want = nWant, gap = gap, virtual = virtual }
end

local function ribbonPlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why = M.ribbonGeo(style, env.g, env.terrain, env.extent)
	if geo == nil then m.planWhy = why; return end
	local cx, cy = style.centre[1], style.centre[2]
	local stops = {}
	for i, ln in ipairs(geo.lanes) do
		stops[#stops + 1] = { s = ln.s, key = "mrb:L" .. i }
		ln.key = "mrb:L" .. i
	end
	local zone = geo.laneMax + 20
	local function drop(x, y, tee)
		if G.dist(cx, cy, x, y) < geo.r0 then return false end
		local d, _, side = L.nearest(geo.ix, x, y, zone)
		if d == nil then return false end
		-- (between the ribbon and the road: one row of lots; the far side: the lanes and meadow, except the plan's
		-- streets meeting the ribbon in a T; a virtual road has no road side)
		if side * geo.sd < 0 and not geo.virtual then return true end
		return not tee
	end
	local anchors = L.anchors(env.g, style, geo.ix, 0, { 1 }, env.terrain)
	local res = L.layMain(mp, geo.line, { prefix = "mrb", approach = L.approach(style), teeK = L.COST_TEE,
		dense = L.dense(style), band = L.band(style), motif = m.id, class = "small", costK = L.COST_MAIN, lead = true,
		every = 90, stops = stops, part = "ribbon", mid = 0, drop = drop }, anchors)
	local made = 0
	for i, ln in ipairs(geo.lanes) do
		local j = mp.junctions[ln.key]
		if j then
			L.overlay(mp, { { j[1], j[2] }, { ln.x1, ln.y1 } }, { prefix = "mrbL" .. i, motif = m.id, class = "small",
				curved = false, costK = L.COST_LANE, startKey = ln.key, deadEnd = true, part = "lane", branch = "start",
				drop = drop })
			made = made + 1
		end
	end
	geo.pieces, geo.cut, geo.lanesMade, geo.anchors, geo.links = res.pieces, res.cut, made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function ribbonMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local len, spans, n = L.builtAlong(env.g, geo.ix, 8)
	local lanes = 0
	for _, ln in ipairs(geo.lanes) do
		local mx, my = (ln.x0 + ln.x1) / 2, (ln.y0 + ln.y1) / 2
		if L.segBuilt(env.g, ln.x0, ln.y0, mx, my, 8) then lanes = lanes + 1 end
	end
	local houses = L.housesAlong(env.pts, geo.ix, spans, 45)
	local roadSide = 0
	for _, p in ipairs(env.pts or {}) do
		local d, s, side = L.nearest(geo.ix, p[1], p[2], geo.off)
		if d and side * geo.sd < 0 then
			for _, sp in ipairs(spans) do
				if s >= sp[1] - 10 and s <= sp[2] + 10 then roadSide = roadSide + 1; break end
			end
		end
	end
	return { edges = L.incEdges(env.inc, "mrb"), total = n, houses = houses, len = len, lanes = lanes, roadSide = roadSide,
		text = string.format("ribbon=%.0f/%.0f,lanes=%d/%d,off=%.0f,roadSide=%d,stop=%s,anchors=%d/%d%s", len, geo.ix.len, lanes,
			#geo.lanes, geo.off, roadSide, tostring(geo.stop), geo.anchors or 0, geo.links or 0, geo.virtual and ",virtual" or "") }
end

local function ribbonEligible(ctx)
	local st = ctx.style
	local roads = (ctx.inputs and ctx.inputs.roads) or st.roads
	if roads == nil then return 0, "noRoads" end
	local r = max(st.radius or 0, blk(st))
	local n, bestOut = 0, 0
	for _, rd in ipairs(roads.roads or {}) do
		if rd.out >= r + M.RB.MIN_LEN + 100 then
			n = n + 1
			if rd.out > bestOut then bestOut = rd.out end
		end
	end
	if n == 0 then return 0, string.format("short:n=%d", #(roads.roads or {})) end
	local tier = ctx.tier or 2
	if tier >= 4 or st.metro then return 0, "big" end
	local s = 0.75 * (tier == 3 and 0.5 or 1) * eraK(ctx) * L.styleK(st)
	if #(roads.roads or {}) >= 3 then s = s * 0.85 end   -- (a through road: the classic Strassendorf)
	if roads.virtual then s = s * M.VIRTUAL_K end
	if s <= 0 then return 0, "style" end
	return s, string.format("%s:n=%d,out=%.0f", roads.virtual and "virtual" or "road", n, bestOut)
end

local function ribbonDose(m, edges, off, n)
	local geo = m.geo
	if geo == nil then return {} end
	-- (the row between the ribbon street and the road: the houses face the road side)
	return doseSide(geo.ix, edges, min(off, geo.off * 0.55), n, -geo.sd)
end

---------------------------------------------------------------------------
-- village green

local function greenShape(style, theta, d, fork)
	local vg = M.VG
	local seed = style.seed or 1
	local cx, cy = style.centre[1], style.centre[2]
	local ux, uy = cos(theta), sin(theta)
	local nx, ny = -uy, ux
	local px, py = cx + ux * d, cy + uy * d
	local s0 = { px - ux * vg.STUB, py - uy * vg.STUB }
	local P = { px, py }
	local lead, branch, poly, shape
	if fork then
		shape = "triangle"
		local S = vg.SIDE[1] + rng.unit(seed, "mvgSide") * (vg.SIDE[2] - vg.SIDE[1])
		local a = G.clamp(fork.angle / 2, vg.HALF[1], vg.HALF[2])
		local B = { px + cos(theta + a) * S, py + sin(theta + a) * S }
		local C = { px + cos(theta - a) * S, py + sin(theta - a) * S }
		lead = { s0, P, B, C }
		branch = { P, C }
		poly = { P, B, C }
	else
		shape = "lens"
		local Lg = vg.LEN[1] + rng.unit(seed, "mvgLen") * (vg.LEN[2] - vg.LEN[1])
		local W = vg.WIDTH * Lg
		local left, right = {}, {}
		for k = 0, 10 do
			local t = k / 10
			local w = W * sin(math.pi * t)
			left[#left + 1] = { px + ux * t * Lg + nx * w, py + uy * t * Lg + ny * w }
			right[#right + 1] = { px + ux * t * Lg - nx * w, py + uy * t * Lg - ny * w }
		end
		lead = { s0 }
		for _, p in ipairs(left) do lead[#lead + 1] = p end
		branch = right
		poly = {}
		for _, p in ipairs(left) do poly[#poly + 1] = p end
		for i = #right - 1, 2, -1 do poly[#poly + 1] = right[i] end
	end
	return { lead = lead, branch = branch, poly = poly, shape = shape, P = P, theta = theta, d = d, stub = vg.STUB }
end

--- The green's boundary lines (lead without the stub, the branch) resampled every ~20 m.
local function greenLines(sh)
	local lead = {}
	for i = 2, #sh.lead do lead[#lead + 1] = sh.lead[i] end
	return { G.resample(lead, 20), G.resample(sh.branch, 20) }
end

--- The village green's plan geometry (pure): the shape (greenShape) + { ours (built), slope, fork, pick = { theta, d } }
--- or nil, why. pick (optional): the place chosen before this session (the motif record keeps it: the plan is rebuilt
--- as the town grows, the green must not move); else the search: a seeded distance and the fork's bisector (or 16
--- seeded directions), pushed out while the land / roads don't fit or older streets stand inside; a place whose ring
--- already has the mod's locked streets along it (an earlier session's green) wins.
function M.greenGeo(style, g, sampler, extent, pick)
	if sampler == nil then return nil, "noTerrain" end
	local vg = M.VG
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local roads = roadsOf(style, g)
	local forks = RDS.forks(roads)
	local fork = forks[1]
	local sidx = segIndex(roads and roads.segs)
	local setback = style.waterSetback or 25
	local maxSlope = style.maxSlope or 0.1
	extent = extent or 1500
	-- (seeded; a new green at least half a block beyond the houses (the town's extent when the style was resolved),
	-- an earlier one found at any of the steps)
	local dBase = vg.D[1] + rng.unit(seed, "mvgD") * (vg.D[2] - vg.D[1])
	local kMin = max(0, math.ceil(((style.radius or 0) + 0.5 * blk(style) - dBase) / vg.PUSH))
	local dirs = {}
	if fork then
		for _, k in ipairs({ 0, -1, 1 }) do dirs[#dirs + 1] = fork.bisector + k * vg.FORK_TOL end
	else
		local rot = rng.unit(seed, "mvgRot") * 2 * math.pi / vg.DIRS
		for k = 0, vg.DIRS - 1 do dirs[#dirs + 1] = rot + k * 2 * math.pi / vg.DIRS end
	end
	if pick then
		local sh = greenShape(style, pick.theta, pick.d, fork and pick.fork and fork or nil)
		sh.fork, sh.ours, sh.pick, sh.along = fork, pick.ours, pick, 0
		return sh
	end
	local best, ours = nil, nil
	for di, th in ipairs(dirs) do
		for k = 0, kMin + vg.PUSH_N do
			local sh = greenShape(style, th, dBase + k * vg.PUSH, fork)
			local lines = greenLines(sh)
			-- the land: dry, inside the map / plan extent, gentle, clear of the country roads
			local okLand = true
			local all = {}
			for _, ln in ipairs(lines) do for _, p in ipairs(ln) do all[#all + 1] = p end end
			for _, p in ipairs(G.resample(sh.lead, 20)) do all[#all + 1] = p end
			for _, p in ipairs(all) do
				if L.wetNear(sampler, p[1], p[2], setback) or L.offEdge(style, p[1], p[2])
					or G.dist(cx, cy, p[1], p[2]) > extent or segNear(sidx, p[1], p[2], vg.CLEAR) then
					okLand = false; break
				end
			end
			local slope = 0
			if okLand then
				local mx, my = 0, 0
				for _, p in ipairs(sh.poly) do mx, my = mx + p[1], my + p[2] end
				mx, my = mx / #sh.poly, my / #sh.poly
				local samples = { { mx, my } }
				for _, p in ipairs(sh.poly) do samples[#samples + 1] = { (p[1] + mx) / 2, (p[2] + my) / 2 } end
				for _, q in ipairs(samples) do
					local sl = T.slope(sampler, q[1], q[2], 6)
					if sl > slope then slope = sl end
				end
				if slope > vg.SLOPE * maxSlope then okLand = false end
				for _, ln in ipairs({ sh.lead, sh.branch }) do
					if okLand and T.pathMaxGrade(sampler, ln) > 0.9 * maxSlope then okLand = false end
				end
				for _, ln in ipairs({ sh.lead, sh.branch }) do
					for i = 2, #ln do
						if okLand and segCross(sidx, ln[i - 1][1], ln[i - 1][2], ln[i][1], ln[i][2]) then okLand = false end
					end
				end
			end
			if okLand then
				-- built streets along the green's lines (ours, from an earlier build / session), or town streets inside it
				-- (the planner never puts any there: only older or game-made ones; the green moves on before it is begun)
				local along, blocked = 0, false
				for _, e in ipairs(g and g.edges or {}) do
					local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
					if a and b then
						local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
						local onLine = false
						for _, ln in ipairs(lines) do
							for i = 2, #ln do
								if G.pointSegDist(mx, my, ln[i - 1][1], ln[i - 1][2], ln[i][1], ln[i][2]) <= 8
									and G.pointSegDist(a.x, a.y, ln[i - 1][1], ln[i - 1][2], ln[i][1], ln[i][2]) <= 30 then
									onLine = true; break
								end
							end
							if onLine then break end
						end
						-- (the mod's own: locked, ot_driver.lockKeys; town streets merely lying along a line don't count)
						if onLine then
							if e.locked then along = along + 1 end
						else
							for _, q in ipairs({ { mx, my }, { a.x, a.y }, { b.x, b.y } }) do
								if pointInPoly(sh.poly, q[1], q[2]) and polyDist(sh.poly, q[1], q[2]) > 15 then blocked = true end
							end
						end
					end
				end
				local sc = slope / max(maxSlope, 1e-6) + 0.15 * (k - kMin) + 0.3 * rng.unit(seed, "mvgPick", di, k)
				if fork then sc = sc + 0.2 * (di - 1) end
				if along >= vg.OURS then
					if ours == nil or along > ours.along then
						sh.along, sh.slope, sh.score = along, slope, sc
						ours = sh
					end
				elseif not blocked and along == 0 and k >= kMin then
					if best == nil or sc < best.score then
						sh.along, sh.slope, sh.score = along, slope, sc
						best = sh
					end
				end
			end
		end
	end
	local geo = ours or best
	if geo == nil then return nil, fork and "noRoom:fork" or "noRoom" end
	geo.fork = fork
	geo.ours = ours ~= nil
	geo.pick = { theta = geo.theta, d = geo.d, fork = geo.shape == "triangle", ours = geo.ours }
	return geo
end

local function greenPlan(mp, style, m, env)
	m.geo = nil
	if not M.ON then return end
	local geo, why = M.greenGeo(style, env.g, env.terrain, env.extent, m.greenPick)
	if geo == nil then m.planWhy = why; return end
	m.greenPick = geo.pick
	local ixLead = L.index(geo.lead)
	-- the stub from the town to P (anchored on its town 70 %), then both sides of the green leaving P together (branches
	-- at the stub's end: one junction built at once, the game joins only dead ends) and meeting again at the far end
	local s0, sP = geo.lead[1], geo.lead[2]
	local stub = { s0, sP }
	local stubIx = L.index({ s0, { s0[1] + (sP[1] - s0[1]) * 0.7, s0[2] + (sP[2] - s0[2]) * 0.7 } })
	local anchors = L.anchors(env.g, style, stubIx, 0, { 1 }, env.terrain)
	local function drop(x, y)
		return pointInPoly(geo.poly, x, y)
	end
	local curved = geo.shape == "lens"
	local res = L.layMain(mp, stub, { prefix = "mvg", approach = L.approach(style), teeK = L.COST_TEE,
		band = L.band(style), motif = m.id, class = "small", costK = L.COST_MAIN, lead = true, part = "stub", mid = 0,
		curved = false, drop = drop }, anchors)
	local made = 0
	if mp.junctions["mvg:Z"] then
		local left = {}
		for i = 2, #geo.lead do left[#left + 1] = geo.lead[i] end
		local stops = nil
		if geo.shape == "triangle" then stops = { { s = G.dist(left[1][1], left[1][2], left[2][1], left[2][2]), key = "mvgL:B" } } end
		L.overlay(mp, left, { prefix = "mvgL", motif = m.id, class = "small", costK = L.COST_MAIN, startKey = "mvg:Z",
			part = "green", branch = "start", every = 80, curved = curved, stops = stops, band = L.band(style), drop = drop })
		if mp.junctions["mvgL:Z"] then
			L.overlay(mp, geo.branch, { prefix = "mvgR", motif = m.id, class = "small", costK = L.COST_MAIN, startKey = "mvg:Z",
				endKey = "mvgL:Z", part = "green", branch = "start", every = 80, curved = curved, band = L.band(style),
				drop = drop })
			made = 2
		end
	end
	-- (the green's streets and its stub keep their room: the town's streets meet them only head on)
	clearAround(mp, { ixLead, L.index(geo.branch) }, M.VG.ROOM)
	geo.ix = ixLead
	geo.boundary = (function()
		local b = {}
		for i = 2, #geo.lead do b[#b + 1] = geo.lead[i] end
		for i = #geo.branch - 1, 1, -1 do b[#b + 1] = geo.branch[i] end
		return b
	end)()
	geo.pieces, geo.cut, geo.branchMade, geo.anchors, geo.links = res.pieces, res.cut, made, res.anchors, res.links
	m.geo = geo
	m.planWhy = nil
end

local function greenMeasure(env, m)
	local geo = m.geo
	if geo == nil then return { edges = 0, total = 0, houses = 0, text = "none:" .. tostring(m.planWhy or "-") } end
	local bix = L.index(geo.boundary)
	local len, _, n = L.builtAlong(env.g, bix, 8)
	local onGreen, ring = 0, 0
	for _, p in ipairs(env.pts or {}) do
		local inside = pointInPoly(geo.poly, p[1], p[2])
		local d = polyDist(geo.poly, p[1], p[2])
		if inside and d > M.VG.LOT then onGreen = onGreen + 1
		elseif not inside and d <= 45 then ring = ring + 1 end
	end
	local cover = bix.len > 0 and len / bix.len or 0
	return { edges = L.incEdges(env.inc, "mvg"), total = n, houses = ring, len = len, cover = cover, onGreen = onGreen,
		closed = cover >= 0.9,
		text = string.format("shape=%s,ring=%.0f/%.0f,cover=%.2f,onGreen=%d,ring=%d,d=%.0f,ours=%s,anchors=%d/%d", geo.shape,
			len, bix.len, cover, onGreen, ring, geo.d, tostring(geo.ours), geo.anchors or 0, geo.links or 0) }
end

local function greenEligible(ctx)
	local st = ctx.style
	local tier = ctx.tier or 2
	if tier >= 4 or st.metro then return 0, "big" end
	local t = ctx.terrain
	local grade = t and t.relief and t.relief.grade or 0
	if t and (t.meanSlope or 0) > 0.1 then return 0, string.format("rough:slope=%.3f", t.meanSlope) end
	local flat = G.clamp((0.08 - grade) / 0.05, 0, 1)
	-- (a green sits where a country road leaves the town: at a fork of two, else beside the town's edge on one)
	local roads = (ctx.inputs and ctx.inputs.roads) or st.roads
	if roads == nil or #(roads.roads or {}) == 0 then return 0, "noRoads" end
	local forks = RDS.forks(roads)
	local s = (#forks > 0 and 0.8 or 0.45) * flat * (tier == 3 and 0.5 or 1) * eraK(ctx) * L.styleK(st)
	if roads.virtual then s = s * M.VIRTUAL_K end
	if s <= 0 then return 0, string.format("steep:grade=%.3f", grade) end
	if #forks > 0 then return s, string.format("fork:angle=%.0f,grade=%.3f", math.deg(forks[1].angle), grade) end
	return s, string.format("edge:grade=%.3f", grade)
end

---------------------------------------------------------------------------
-- crossroads hamlet

--- The crossroads for a hamlet of a town: the nearest junction of 3+ country roads HM.D m out, beyond the houses'
--- extent + GAP, nearer this town (`own ~= false`), or nil.
function M.hamletJunction(style, roads)
	if roads == nil then return nil end
	local r = style.radius or 0
	for _, j in ipairs(roads.junctions or {}) do
		if j.d >= M.HM.D[1] and j.d <= M.HM.D[2] and j.d >= r + M.HM.GAP and j.own ~= false and (j.deg or 0) >= 3
			and not L.offEdge(style, j.x, j.y) then
			return j
		end
	end
	return nil
end

local function hamletEligible(ctx)
	local st = ctx.style
	local tier = ctx.tier or 2
	if tier >= 4 or st.metro then return 0, "big" end
	if st.id == "SUPERBLOCK" or st.id == "MED_ENSANCHE" then return 0, "style" end
	local roads = (ctx.inputs and ctx.inputs.roads) or st.roads
	local j = M.hamletJunction(st, roads)
	if j == nil then return 0, (roads and roads.virtual) and "virtualRoads" or "noJunction" end
	local s = (j.deg >= 4 and 0.85 or 0.7) * (tier == 3 and 0.6 or 1)
	return s, string.format("crossroads:d=%.0f,deg=%d", j.d, j.deg)
end

local function hamletStyle(p, m, env)
	local j = M.hamletJunction(p, p.roads)
	m.junction = j
	if j then p.hamlet = { x = j.x, y = j.y, d = j.d, deg = j.deg, heads = j.heads, node = j.node } end
end

local function hamletMeasure(env, m)
	local sat = env.sat
	local j = env.style and env.style.hamlet
	if sat == nil then
		return { edges = 0, total = 0, houses = 0, text = "none:" .. (j and "waiting" or "noJunction") }
	end
	local n = 0
	for _, p in ipairs(env.pts or {}) do
		if G.dist(sat.x, sat.y, p[1], p[2]) <= 220 then n = n + 1 end
	end
	local jd = j and G.dist(sat.x, sat.y, j.x, j.y) or -1
	return { edges = 0, total = sat.edges or 0, houses = n,
		text = string.format("site=%.0f:%.0f,junction=%.0f,at=%s,near=%d,coreEdges=%d", sat.x, sat.y, jd,
			tostring(sat.at or "-"), n, sat.edges or 0) }
end

---------------------------------------------------------------------------

--- Registers the M2 kinds (append order = their save indices after the M1 kinds: 7-9).
function M.registerAll(MO)
	-- (group road: the ribbon and the green both lay the town's street out along / beside its road)
	MO.register({ id = "ribbon_village", group = "road", lock = true, eligible = ribbonEligible, plan = ribbonPlan,
		measure = ribbonMeasure, dose = ribbonDose })
	MO.register({ id = "village_green", group = "road", lock = true, eligible = greenEligible, plan = greenPlan,
		measure = greenMeasure })
	MO.register({ id = "crossroads_hamlet", group = "hamlet", eligible = hamletEligible, style = hamletStyle,
		measure = hamletMeasure })
end

M.segIndex, M.segNear, M.segCross, M.pointInPoly = segIndex, segNear, segCross, pointInPoly
M.doseSide = doseSide   -- (M4 headland street)

return M
