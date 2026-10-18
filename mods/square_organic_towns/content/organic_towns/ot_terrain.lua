-- Organic Towns: terrain analysis over an injected sampler (pure; the engine layer adapts
-- api.engine.terrain.getHeightAt / isOnWater, tests pass synthetic fields).
--
-- sampler = { height = function(x, y) -> z, water = function(x, y) -> bool (optional),
--             waterLevel = number (optional, default 0: mod heightmaps have sea level 0, docs/findings.md) }
-- Without `water`, a point is wet when its height is below waterLevel.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

local sqrt, abs, cos, sin = math.sqrt, math.abs, math.cos, math.sin

--- Wraps plain functions into a sampler table.
function M.sampler(heightFn, waterFn, waterLevel)
	return { height = heightFn, water = waterFn, waterLevel = waterLevel or 0 }
end

function M.height(s, x, y) return s.height(x, y) end

function M.isWater(s, x, y)
	if s.water then return s.water(x, y) and true or false end
	return s.height(x, y) < (s.waterLevel or 0)
end

--- Height gradient (dz/dx, dz/dy) by central differences over +/- h metres (default 4, the base height
--- resolution of getBaseHeightAt).
function M.gradient(s, x, y, h)
	h = h or 4
	local gx = (s.height(x + h, y) - s.height(x - h, y)) / (2 * h)
	local gy = (s.height(x, y + h) - s.height(x, y - h)) / (2 * h)
	return gx, gy
end

--- Slope (grade, rise over run) at a point.
function M.slope(s, x, y, h)
	local gx, gy = M.gradient(s, x, y, h)
	return sqrt(gx * gx + gy * gy)
end

--- Heading along the contour line (perpendicular to the gradient), the one of the two closest to `prefer`
--- (radians; default: the +90 deg one). nil on flat ground (slope < minSlope, default 0.005).
function M.contourHeading(s, x, y, prefer, minSlope)
	local gx, gy = M.gradient(s, x, y)
	if sqrt(gx * gx + gy * gy) < (minSlope or 0.005) then return nil end
	local a = G.atan2(gy, gx) + math.pi / 2
	if prefer ~= nil and G.angleDiff(a, prefer) > math.pi / 2 then a = a + math.pi end
	return G.wrap(a)
end

--- Heading straight downhill, nil on flat ground.
function M.downhill(s, x, y, minSlope)
	local gx, gy = M.gradient(s, x, y)
	if sqrt(gx * gx + gy * gy) < (minSlope or 0.005) then return nil end
	return G.atan2(-gy, -gx)
end

--- Grade between two points from their end heights.
function M.grade(s, ax, ay, bx, by)
	local l = G.dist(ax, ay, bx, by)
	if l <= 0 then return 0 end
	return abs(s.height(bx, by) - s.height(ax, ay)) / l
end

--- Steepest grade along a polyline, sampled every `step` metres (default 20).
function M.pathMaxGrade(s, pts, step)
	step = step or 20
	local fine = G.resample(pts, step)
	local worst = 0
	local prevZ = s.height(fine[1][1], fine[1][2])
	for i = 2, #fine do
		local z = s.height(fine[i][1], fine[i][2])
		local l = G.dist(fine[i - 1][1], fine[i - 1][2], fine[i][1], fine[i][2])
		if l > 0 then
			local g = abs(z - prevZ) / l
			if g > worst then worst = g end
		end
		prevZ = z
	end
	return worst
end

--- true when the polyline runs over water or within `setback` metres of it (samples every `step` m, each
--- also checked at +/- setback and +/- setback/2 to the side, and the ends `setback` beyond).
function M.wetAlong(s, pts, setback, step)
	setback = setback or 0
	step = step or 10
	local fine = G.resample(pts, step)
	for i = 1, #fine do
		local p = fine[i]
		if M.isWater(s, p[1], p[2]) then return true end
		if setback > 0 then
			local a = fine[math.max(1, i - 1)]
			local b = fine[math.min(#fine, i + 1)]
			local dx, dy = b[1] - a[1], b[2] - a[2]
			local l = sqrt(dx * dx + dy * dy)
			if l > 0 then
				local nx, ny = -dy / l, dx / l
				for _, k in ipairs({ 1, -1, 0.5, -0.5 }) do
					if M.isWater(s, p[1] + nx * setback * k, p[2] + ny * setback * k) then return true end
				end
				if i == 1 and M.isWater(s, p[1] - dx / l * setback, p[2] - dy / l * setback) then return true end
				if i == #fine and M.isWater(s, p[1] + dx / l * setback, p[2] + dy / l * setback) then return true end
			end
		end
	end
	return false
end

--- Distance from (x, y) to the nearest water sample (rings every `step` m, 16 directions), or nil within maxR.
function M.clearance(s, x, y, maxR, step)
	maxR = maxR or 300
	step = step or 10
	if not (step > 0) then step = 10 end   -- (hang guard: a zero / NaN step never rings forever)
	if not (maxR <= 1e5) then maxR = 1e5 end
	if M.isWater(s, x, y) then return 0 end
	local r = step
	while r <= maxR + 1e-9 do
		for k = 0, 15 do
			local a = k * math.pi / 8
			if M.isWater(s, x + cos(a) * r, y + sin(a) * r) then return r end
		end
		r = r + step
	end
	return nil
end

M.DIR_N = 16                 -- directions sampled for the relief axes
M.DIR_RADII = { 0.25, 0.5, 0.75 }   -- x radius
M.VALLEY_RISE = 8            -- m: both sides of an axis at least this much higher (valley) / lower (ridge)

--- Directional relief around (cx, cy) (town shapes, ot_shape): heights on DIR_N rays at DIR_RADII x radius
--- (dry points only). For each undirected axis: how much the ground changes along it (`level`, mean |dh| on its
--- two rays) and on its two sides (perpendicular rays). Returns { axis = heading (rad) of the most level axis,
--- level, sideA, sideB (mean height difference of the two perpendicular sides to the centre), valley = bool (both
--- sides rise), ridge = bool (both sides fall), contrast = min(|sideA|, |sideB|) }, or nil (no dry samples).
function M.dirRelief(s, cx, cy, radius)
	radius = radius or 600
	local n = M.DIR_N
	local hc = s.height(cx, cy)
	local mean = {}
	for k = 0, n - 1 do
		local a = k / n * 2 * math.pi
		local sum, c = 0, 0
		for _, f in ipairs(M.DIR_RADII) do
			local x, y = cx + cos(a) * radius * f, cy + sin(a) * radius * f
			if not M.isWater(s, x, y) then
				sum, c = sum + s.height(x, y) - hc, c + 1
			end
		end
		mean[k] = c > 0 and sum / c or nil
	end
	local best, bl = nil, math.huge
	local half, q = n / 2, n / 4
	for k = 0, half - 1 do
		local a, b = mean[k], mean[k + half]
		if a and b then
			local l = (abs(a) + abs(b)) / 2
			if l < bl - 1e-9 then best, bl = k, l end
		end
	end
	if best == nil then return nil end
	local sa, sb = mean[(best + q) % n], mean[(best + q + half) % n]
	sa, sb = sa or 0, sb or 0
	local rise = M.VALLEY_RISE
	return { axis = G.wrap(best / n * 2 * math.pi), level = bl, sideA = sa, sideB = sb,
		valley = sa > rise and sb > rise and math.min(sa, sb) > 2 * bl,
		ridge = sa < -rise and sb < -rise and math.min(-sa, -sb) > 2 * bl,
		contrast = math.min(abs(sa), abs(sb)) }
end

M.WIDE_N = 16                      -- directions of the wide survey
M.WIDE_RADII = { 0.25, 0.5, 0.75, 1.0 }   -- x its radius

--- Wide survey around a town (site classifier, ot_site): heights and water on WIDE_N rays at WIDE_RADII x radius
--- (default 2000 m; 64 points, once per town and session). Returns { water = share of wet points, sd = standard
--- deviation of the dry heights (m), range = highest - lowest dry height (m), rise = mean |dry height - centre|,
--- samples, waterDirs = rays (of WIDE_N) with a wet point (water on many sides: an island, ot_site), hc = the centre's
--- height, rays = { [1..WIDE_N] = { { r, x, y, wet, h (dry points) } per radius } } (§62 landscape pull, ot_land) }.
function M.wide(s, cx, cy, radius)
	radius = radius or 2000
	local hc = s.height(cx, cy)
	local n, wet, sum, sum2, lo, hi, dev = 0, 0, 0, 0, math.huge, -math.huge, 0
	local dirs = 0
	local rays = {}
	for k = 0, M.WIDE_N - 1 do
		local a = k / M.WIDE_N * 2 * math.pi
		local rayWet = false
		local ray = {}
		rays[k + 1] = ray
		for _, f in ipairs(M.WIDE_RADII) do
			local x, y = cx + cos(a) * radius * f, cy + sin(a) * radius * f
			n = n + 1
			local pt = { r = radius * f, x = x, y = y }
			ray[#ray + 1] = pt
			if M.isWater(s, x, y) then
				pt.wet = true
				wet = wet + 1
				rayWet = true
			else
				local h = s.height(x, y)
				pt.h = h
				sum, sum2 = sum + h, sum2 + h * h
				if h < lo then lo = h end
				if h > hi then hi = h end
				dev = dev + abs(h - hc)
			end
		end
		if rayWet then dirs = dirs + 1 end
	end
	local dry = n - wet
	local out = { water = n > 0 and wet / n or 0, sd = 0, range = 0, rise = 0, samples = n, waterDirs = dirs, hc = hc,
		rays = rays }
	if dry > 0 then
		local mean = sum / dry
		out.sd = sqrt(math.max(0, sum2 / dry - mean * mean))
		out.range = hi - lo
		out.rise = dev / dry
	end
	return out
end

---------------------------------------------------------------------------
-- Shoreline (coast / lake shore towns, 2026-10-12; PLAN.md 6.3 "Shore towns"). The disc statistics only give the
-- water's direction and a straight shore axis; a town that hugs its shore needs the shore's actual curve (bays,
-- lake shores, an island's coast). M.shoreline walks the land / water boundary from the point nearest the town both
-- ways in SHORE_STEP steps (each step: a point one step ahead, the boundary found across it by bisection; sharper
-- turns tried in widening angles), until SHORE_LEN each way, SHORE_MAXR from the town, a cliff (inland grade above
-- SHORE_STEEP twice) or the loop closes. A closed loop tells a lake (water inside) from an island (land inside).
-- About 10 samples per step, ~1500 per town, once per town and session (the engine sampler memoises them).

M.SHORE = true
M.SHORE_STEP = 40          -- m between shore points
M.SHORE_LEN = 3000         -- m traced each way
M.SHORE_MAXR = 3500        -- m: the trace stops this far from the town
M.SHORE_START = 700        -- m: nearest water searched within this
M.SHORE_TOL = 3            -- m: bisection tolerance (the engine sampler's grid is 2 m)
M.SHORE_STEEP = 0.2        -- inland grade that stops the trace (a cliff, a headland's rock) ...
M.SHORE_STEEP_IN = 60      -- ... measured this far inland
M.POND_PERIM = 1500        -- m: a closed lake shore shorter than this is a pond (no shore town; ~480 m across)
M.RIVER_ELONG = 6          -- in-disc water is a river only when this elongated (variance ratio; a round lake isn't)
local TURNS = { 0, 20, -20, 40, -40, 60, -60, 85, -85, 110, -110 }

--- The dry end of the boundary between dry (ax, ay) and wet (bx, by), to within tol.
local function bisect(s, ax, ay, bx, by, tol)
	for _ = 1, 14 do
		if G.dist(ax, ay, bx, by) <= tol then break end
		local mx, my = (ax + bx) / 2, (ay + by) / 2
		if M.isWater(s, mx, my) then bx, by = mx, my else ax, ay = mx, my end
	end
	return ax, ay
end

--- The boundary on the line through (x, y) along the unit normal (nx, ny) (toward the water) within +-reach: its
--- dry end, or nil.
local function crossAt(s, x, y, nx, ny, reach, tol)
	local sign = M.isWater(s, x, y) and -1 or 1
	local px, py = x, y
	for k = 1, 4 do
		local o = reach * k / 4 * sign
		local qx, qy = x + nx * o, y + ny * o
		local w = M.isWater(s, qx, qy)
		if sign > 0 and w then return bisect(s, px, py, qx, qy, tol) end
		if sign < 0 and not w then return bisect(s, qx, qy, px, py, tol) end
		px, py = qx, qy
	end
	return nil
end

--- One way along the shore from P (unit tangent tx, ty; side +1: water on the right of travel, -1 on the left).
--- Returns the points (P excluded), why it stopped ("len"|"far"|"steep"|"lost"|"closed"|"met"), length.
local function walk(s, cx, cy, P, tx, ty, side, o, other)
	local out, len, steep, why = {}, 0, 0, "len"
	local px, py = P[1], P[2]
	local step = o.step
	for k = 1, math.ceil(o.len / step) * 2 + 4 do
		local fx, fy
		for _, td in ipairs(TURNS) do
			local ux, uy = G.rot(tx, ty, math.rad(td))
			local qx, qy = crossAt(s, px + ux * step, py + uy * step, side * uy, -side * ux, step, o.tol)
			if qx and (qx - px) * tx + (qy - py) * ty > 0.1 * step and G.dist(px, py, qx, qy) >= 0.4 * step then
				fx, fy = qx, qy
				break
			end
		end
		if fx == nil then why = "lost" break end
		local d = G.dist(px, py, fx, fy)
		tx, ty = (fx - px) / d, (fy - py) / d
		px, py = fx, fy
		len = len + d
		out[#out + 1] = { px, py }
		if k > 4 and G.dist(px, py, P[1], P[2]) < 0.75 * step then why = "closed" break end
		if other and #other > 0 and k > 2 then
			local q = other[#other]
			if G.dist(px, py, q[1], q[2]) < 0.75 * step then why = "met" break end
		end
		if G.dist(cx, cy, px, py) > o.maxR then why = "far" break end
		local ix, iy = px - side * ty * o.steepIn, py + side * tx * o.steepIn
		if not M.isWater(s, ix, iy) and M.slope(s, ix, iy, 8) > o.steep then steep = steep + 1 else steep = 0 end
		if steep >= 2 then why = "steep" break end
		if len >= o.len then why = "len" break end
	end
	return out, why, len
end

--- The shoreline near (cx, cy): { pts = {{x, y}} (water on the right of the travel direction), cum (arc length at
--- each point), L, i0 / s0 (index / arc length of the point nearest the town), closed, island (closed with land
--- inside), lake (closed with water inside), area (m2, closed only), stops = "why1/why2", start = distance (m) from
--- the town to the shore } or nil (no water within SHORE_START, the town on water, or no boundary found).
--- opts = { step, len, maxR, start, tol, steep, steepIn } (defaults SHORE_*).
function M.shoreline(s, cx, cy, opts)
	opts = opts or {}
	local o = { step = opts.step or M.SHORE_STEP, len = opts.len or M.SHORE_LEN, maxR = opts.maxR or M.SHORE_MAXR,
		tol = opts.tol or M.SHORE_TOL, steep = opts.steep or M.SHORE_STEEP, steepIn = opts.steepIn or M.SHORE_STEEP_IN }
	local maxStart = opts.start or M.SHORE_START
	if M.isWater(s, cx, cy) then return nil end
	-- nearest water: rings every half step, 32 directions
	if not (o.step > 0) then o.step = M.SHORE_STEP end   -- (hang guard)
	local dr = o.step / 2
	local a0, r0 = nil, nil
	local r = dr
	while r <= maxStart + 1e-9 and a0 == nil do
		for k = 0, 31 do
			local a = k * math.pi / 16
			if M.isWater(s, cx + cos(a) * r, cy + sin(a) * r) then a0, r0 = a, r break end
		end
		r = r + dr
	end
	if a0 == nil then return nil end
	local nx, ny = cos(a0), sin(a0)
	local px, py = bisect(s, cx + nx * (r0 - dr), cy + ny * (r0 - dr), cx + nx * r0, cy + ny * r0, o.tol)
	local P = { px, py }
	local w1, why1 = walk(s, cx, cy, P, -ny, nx, 1, o, nil)
	local pts, i0, closed, why2 = {}, 1, false, "-"
	if why1 == "closed" then
		pts[1] = P
		for _, q in ipairs(w1) do pts[#pts + 1] = q end
		closed = true
	else
		local w2
		w2, why2 = walk(s, cx, cy, P, ny, -nx, -1, o, w1)
		for i = #w2, 1, -1 do pts[#pts + 1] = w2[i] end
		pts[#pts + 1] = P
		i0 = #pts
		for _, q in ipairs(w1) do pts[#pts + 1] = q end
		closed = why2 == "met"
	end
	if #pts < 2 then return nil end
	local cum = { 0 }
	for i = 2, #pts do cum[i] = cum[i - 1] + G.dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
	local L = cum[#pts]
	local out = { pts = pts, cum = cum, L = L, i0 = i0, s0 = cum[i0], closed = closed, stops = why1 .. "/" .. why2,
		start = G.dist(cx, cy, px, py) }
	if closed then
		L = L + G.dist(pts[#pts][1], pts[#pts][2], pts[1][1], pts[1][2])
		out.L = L
		local A = 0
		for i = 1, #pts do
			local p, q = pts[i], pts[i % #pts + 1]
			A = A + p[1] * q[2] - q[1] * p[2]
		end
		A = A / 2
		-- water on the right: a counter-clockwise loop (A > 0) has the water outside (an island), clockwise inside
		out.area = abs(A)
		out.island = A > 0
		out.lake = A < 0
	end
	return out
end

---------------------------------------------------------------------------
-- Cliffs (M4 headland street, 2026-10-13): the brink of a steep coast, where the ground falls CLIFF_DROP per m over
-- the next CLIFF_PROBE m toward the sea (that point may be water).

M.CLIFF_DROP = 0.25
M.CLIFF_PROBE = 20
M.CLIFF_MIN_H = 8          -- m above the water at least (a low bank is no cliff)
M.CLIFF_REACH = 550        -- m: the brink searched this far from the town toward its water

--- The brink on the line from (x, y) along unit (nx, ny) (seaward) within [-back, fwd] m (6 m steps): x, y, height,
--- or nil (no cliff: a beach, or water first).
function M.brinkOn(s, x, y, nx, ny, back, fwd)
	local d = -back
	local probe = M.CLIFF_PROBE
	local wl = s.waterLevel or 0
	while d <= fwd do
		local px, py = x + nx * d, y + ny * d
		if M.isWater(s, px, py) then return nil end
		local z = s.height(px, py)
		local qx, qy = px + nx * probe, py + ny * probe
		-- (over water: the water's surface, not the bed; a beach's last metres are no cliff)
		local zq = M.isWater(s, qx, qy) and wl or s.height(qx, qy)
		if z - zq >= M.CLIFF_DROP * probe and z - wl >= M.CLIFF_MIN_H then return px, py, z end
		d = d + 6
	end
	return nil
end

--- The cliff between (cx, cy) and its water (heading dir): { x, y, z (the brink), d (m from the town), h (m above the
--- water), dir } or nil.
function M.cliff(s, cx, cy, dir)
	if dir == nil then return nil end
	local bx, by, bz = M.brinkOn(s, cx, cy, cos(dir), sin(dir), 0, M.CLIFF_REACH)
	if bx == nil then return nil end
	return { x = bx, y = by, z = bz, d = G.dist(cx, cy, bx, by), h = bz - (s.waterLevel or 0), dir = dir }
end

--- Terrain statistics of a disc (PLAN.md 2.2: 600 m disc, 24 x 24 grid = 576 samples):
--- { meanSlope, p95Slope (dry samples), waterFraction, samples,
---   water = nil | { kind = "river"|"coast", dir = heading from the centre to the water centroid,
---                   axis = heading of the bank / shoreline (undirected), distance = m from centre to nearest water,
---                   body = "river"|"lake"|"pond"|"open"|nil (M.shoreline) },
---   shore = M.shoreline result (coast / lake towns) or nil, cliff = M.cliff toward the water (coast / lake) or nil,
---   high = {x, y, z} highest dry sample, lowZ, highZ,
---   relief = { dir = downhill heading of the best-fit plane, grade } }
function M.stats(s, cx, cy, radius, n)
	radius = radius or 600
	n = n or 24
	local cell = 2 * radius / n
	local slopes, total, wet = {}, 0, 0
	local sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0
	local cells = {}
	local high, lowZ, highZ = nil, math.huge, -math.huge
	-- plane fit sums (dry and wet; heights only)
	local pxx, pyy, pxy, pxz, pyz = 0, 0, 0, 0, 0
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local ox, oy = -radius + (i + 0.5) * cell, -radius + (j + 0.5) * cell
			if ox * ox + oy * oy <= radius * radius then
				local x, y = cx + ox, cy + oy
				total = total + 1
				local isWet = M.isWater(s, x, y)
				local z = s.height(x, y)
				pxx, pyy, pxy = pxx + ox * ox, pyy + oy * oy, pxy + ox * oy
				pxz, pyz = pxz + ox * z, pyz + oy * z
				cells[#cells + 1] = { ox, oy, isWet }
				if isWet then
					wet = wet + 1
					sx, sy = sx + ox, sy + oy
					sxx, syy, sxy = sxx + ox * ox, syy + oy * oy, sxy + ox * oy
				else
					slopes[#slopes + 1] = M.slope(s, x, y, cell / 2)
					if z > highZ then highZ = z; high = { x, y, z } end
					if z < lowZ then lowZ = z end
				end
			end
		end
	end
	table.sort(slopes)
	local mean = 0
	for _, v in ipairs(slopes) do mean = mean + v end
	if #slopes > 0 then mean = mean / #slopes end
	local p95 = 0
	if #slopes > 0 then p95 = slopes[math.max(1, math.min(#slopes, math.floor(#slopes * 0.95 + 0.5)))] end
	local out = {
		meanSlope = mean, p95Slope = p95, samples = total,
		waterFraction = total > 0 and wet / total or 0,
		high = high, lowZ = lowZ, highZ = highZ,
	}
	-- relief: least squares plane z = a*ox + b*oy + c (sample offsets are symmetric about 0, so mean ox = 0)
	local det = pxx * pyy - pxy * pxy
	if total > 0 and abs(det) > 1e-9 then
		local a = (pxz * pyy - pyz * pxy) / det
		local b = (pyz * pxx - pxz * pxy) / det
		out.relief = { dir = G.atan2(-b, -a), grade = sqrt(a * a + b * b) }
	end
	out.dirRelief = M.dirRelief(s, cx, cy, radius)
	if wet > 0 and wet < total then
		local mx, my = sx / wet, sy / wet
		local cxx, cyy, cxy = sxx / wet - mx * mx, syy / wet - my * my, sxy / wet - mx * my
		local axis = 0.5 * G.atan2(2 * cxy, cxx - cyy)
		-- dry land on both sides of the water's principal line through its centroid -> river, else coast
		local ux, uy = cos(axis), sin(axis)
		local pos, neg = 0, 0
		for _, c in ipairs(cells) do
			if not c[3] then
				local side = (c[1] - mx) * (-uy) + (c[2] - my) * ux
				if side > cell then pos = pos + 1 elseif side < -cell then neg = neg + 1 end
			end
		end
		-- (2026-10-12, shore towns: and elongated; a round lake inside the disc has land all round but is no river)
		local tr, det = cxx + cyy, cxx * cyy - cxy * cxy
		local root = sqrt(math.max(0, tr * tr / 4 - det))
		local elong = (tr / 2 + root) / math.max(tr / 2 - root, 1)
		local kind = "coast"
		if math.min(pos, neg) > 0.15 * total and (elong >= M.RIVER_ELONG or not M.SHORE) then kind = "river" end
		local dir = G.atan2(my, mx)
		local water = { kind = kind, dir = dir, distance = M.clearance(s, cx, cy, radius, cell / 2) or radius }
		if kind == "river" then water.axis = G.wrap(axis) else water.axis = G.wrap(dir + math.pi / 2) end
		-- body: "river" | "lake" / "pond" (a closed shore around water) | "open" (sea or a large lake: the shore runs
		-- on beyond the trace; ot_site tells them apart by the wide survey) | nil (no shore traced)
		water.body = kind == "river" and "river" or nil
		if kind ~= "river" and M.SHORE then
			local okS, sh = pcall(M.shoreline, s, cx, cy, { maxR = math.max(M.SHORE_MAXR, radius * 2) })
			if okS and sh then
				out.shore = sh
				if sh.lake then water.body = sh.L < M.POND_PERIM and "pond" or "lake"
				else water.body = "open" end
			end
		end
		out.water = water
		-- (a steep coast: the cliff toward the water, M4 headland street; ~90 x 2 samples)
		if kind ~= "river" then out.cliff = M.cliff(s, cx, cy, dir) end
	end
	return out
end

return M
