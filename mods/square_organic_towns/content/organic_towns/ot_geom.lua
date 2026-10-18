-- Organic Towns: small 2D geometry helpers shared by the pure planning modules (no api.* calls).
-- Points are plain {x, y[, z]} tables (array part: [1] = x, [2] = y, [3] = z) or loose numbers.
-- Angles are radians unless a name says Deg. Lua pre-5.3 compatible (no //, no bit ops, no math.type).

local M = {}

local unit2

local sqrt, floor, abs = math.sqrt, math.floor, math.abs
local atan2 = math.atan2 or math.atan   -- 5.1/5.2: atan2; 5.3+: atan(y, x)

--- Unit vector and length of (dx, dy); 0, 0, 0 for a zero vector.
unit2 = function(dx, dy)
	local l = sqrt(dx * dx + dy * dy)
	if l <= 0 then return 0, 0, 0 end
	return dx / l, dy / l, l
end
M.atan2 = atan2

-- Loop guards (hang fix 2026-10-13, real map run 2026-10-13_1848_sqot): every walk / step loop of the planning path
-- stops after LOOP_CAP rounds, spatial-index loops cover at most MAX_CELLS cells per segment, and coordinates must be
-- finite and within MAX_COORD m. A bad input degrades to a shorter / missing line, never a frozen game.
M.LOOP_CAP = 10000
M.MAX_CELLS = 4096
M.MAX_COORD = 1e6
M.MAX_SAMPLES = 20000   -- resample: pieces per polyline at most

--- true for a finite number within MAX_COORD.
function M.finite(v)
	return type(v) == "number" and v == v and v > -M.MAX_COORD and v < M.MAX_COORD
end

--- Grid cell range of the box around (ax, ay)-(bx, by) padded by pad, cell size `cell`: cx0, cx1, cy0, cy1, or nil when
--- a coordinate is not finite or the box spans more than MAX_CELLS cells (the caller skips the segment).
function M.cellRange(ax, ay, bx, by, pad, cell)
	pad = pad or 0
	if not (M.finite(ax) and M.finite(ay) and M.finite(bx) and M.finite(by)) or not (cell and cell > 0) then return nil end
	local x0, x1 = floor((math.min(ax, bx) - pad) / cell), floor((math.max(ax, bx) + pad) / cell)
	local y0, y1 = floor((math.min(ay, by) - pad) / cell), floor((math.max(ay, by) + pad) / cell)
	if (x1 - x0 + 1) * (y1 - y0 + 1) > M.MAX_CELLS then return nil end
	return x0, x1, y0, y1
end
M.PI = math.pi
M.TAU = 2 * math.pi

--- -0 -> +0 (docs/findings.md "Negative zero": the engine keeps a -0 and refuses the layout).
function M.z0(v)
	if v == 0 then return 0.0 end
	return v
end

--- Rounds to `step` (default 0.001) and normalises -0.
function M.round(v, step)
	step = step or 0.001
	return M.z0(floor(v / step + 0.5) * step)
end

function M.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

function M.lerp(a, b, t) return a + (b - a) * t end

function M.len(dx, dy) return sqrt(dx * dx + dy * dy) end

function M.dist(ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	return sqrt(dx * dx + dy * dy)
end

--- Angle wrapped to [-pi, pi).
function M.wrap(a)
	a = math.fmod(a + math.pi, 2 * math.pi)
	if a < 0 then a = a + 2 * math.pi end
	return a - math.pi
end

--- Smallest absolute difference between two headings (radians, 0..pi).
function M.angleDiff(a, b)
	return abs(M.wrap(a - b))
end

--- Smallest angle between two undirected lines (0..pi/2).
function M.lineAngleDiff(a, b)
	local d = abs(M.wrap(a - b))
	if d > math.pi / 2 then d = math.pi - d end
	return d
end

function M.heading(ax, ay, bx, by) return atan2(by - ay, bx - ax) end

--- Rotates (x, y) by angle a.
function M.rot(x, y, a)
	local c, s = math.cos(a), math.sin(a)
	return x * c - y * s, x * s + y * c
end

--- Distance from point p to segment a-b, and the segment parameter t (0..1) of the closest point.
function M.pointSegDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = 0
	if l2 > 0 then t = M.clamp(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1) end
	local cx, cy = ax + dx * t, ay + dy * t
	return M.dist(px, py, cx, cy), t
end

--- Proper intersection of segments a-b and c-d (interiors cross; shared endpoints and touching ends don't count
--- when they lie within `eps` of an endpoint). Returns t (on a-b), u (on c-d) or nil.
function M.segIntersect(ax, ay, bx, by, cx, cy, dx, dy, eps)
	eps = eps or 1e-6
	local rx, ry = bx - ax, by - ay
	local sx, sy = dx - cx, dy - cy
	local den = rx * sy - ry * sx
	if abs(den) < 1e-12 then return nil end
	local qx, qy = cx - ax, cy - ay
	local t = (qx * sy - qy * sx) / den
	local u = (qx * ry - qy * rx) / den
	if t <= eps or t >= 1 - eps or u <= eps or u >= 1 - eps then return nil end
	return t, u
end

--- Total length of a polyline {{x, y}, ...}.
function M.polyLen(pts)
	local s = 0
	for i = 2, #pts do s = s + M.dist(pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2]) end
	return s
end

--- Point at arc-length fraction f (0..1) of a polyline; returns x, y, segment index.
function M.polyAt(pts, f)
	local total = M.polyLen(pts)
	if total <= 0 or #pts < 2 then return pts[1][1], pts[1][2], 1 end
	local want = M.clamp(f, 0, 1) * total
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = M.dist(a[1], a[2], b[1], b[2])
		if acc + l >= want or i == #pts then
			local t = 0
			if l > 0 then t = M.clamp((want - acc) / l, 0, 1) end
			return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, i - 1
		end
		acc = acc + l
	end
	local last = pts[#pts]
	return last[1], last[2], #pts - 1
end

--- Unit direction blended between the directions two points carry ([3], [4]: curves from ot_geom.fillet,
--- hermitePts and the organic arcs carry their exact tangent); nil when either carries none.
function M.lerpDir(a, b, t)
	if a[3] == nil or b[3] == nil then return nil end
	local x, y = unit2(a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t)
	if x == 0 and y == 0 then return a[3], a[4] end
	return x, y
end

--- Splits a polyline at arc-length fractions (sorted, strictly inside 0..1). Carried directions are kept
--- (cut points get blended ones). Returns a list of polylines whose
--- consecutive end/start points are identical tables' values; `cuts[k]` may carry exact points {f, x, y} so the
--- cut point equals a junction computed elsewhere.
function M.polySplit(pts, cuts)
	local out = {}
	local total = M.polyLen(pts)
	local cur = { { pts[1][1], pts[1][2], pts[1][3], pts[1][4] } }
	local acc = 0
	local ci = 1
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = M.dist(a[1], a[2], b[1], b[2])
		while ci <= #cuts and total > 0 and cuts[ci][1] * total <= acc + l + 1e-9 do
			local c = cuts[ci]
			local x, y = c[2], c[3]
			local t = 0
			if l > 0 then t = M.clamp((c[1] * total - acc) / l, 0, 1) end
			if x == nil then x, y = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t end
			local dx, dy = M.lerpDir(a, b, t)
			cur[#cur + 1] = { x, y, dx, dy }
			out[#out + 1] = cur
			cur = { { x, y, dx, dy } }
			ci = ci + 1
		end
		local lastc = cur[#cur]
		if M.dist(lastc[1], lastc[2], b[1], b[2]) > 1e-6 then cur[#cur + 1] = { b[1], b[2], b[3], b[4] } end
		acc = acc + l
	end
	if #cur >= 2 then out[#out + 1] = cur end   -- else the last cut fell on the end point
	return out
end

--- Resamples a polyline into pieces no longer than maxLen: keeps every original vertex and splits each run
--- evenly. Returns a new list of points.
function M.resample(pts, maxLen)
	local out = { { pts[1][1], pts[1][2] } }
	-- (guards: a zero / NaN step or an endless segment never loops without end; at most MAX_SAMPLES pieces in all)
	if not (maxLen and maxLen > 0) then maxLen = math.huge end
	local left = M.MAX_SAMPLES
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = M.dist(a[1], a[2], b[1], b[2])
		local n = math.max(1, math.ceil(l / maxLen - 1e-9))
		if not (n <= left) then n = math.max(1, left) end
		left = left - n
		for k = 1, n do
			local t = k / n
			out[#out + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t }
		end
	end
	return out
end

--- Simplified copy of a polyline: Douglas-Peucker with tolerance `tol` (m), then interior vertices closer
--- than `minDist` to the previous kept vertex or to the end are dropped. Ends are always kept.
function M.simplify(pts, tol, minDist)
	local n = #pts
	if n <= 2 then
		local out = {}
		for i = 1, n do out[i] = { pts[i][1], pts[i][2] } end
		return out
	end
	local keep = { [1] = true, [n] = true }
	local stack = { { 1, n } }
	while #stack > 0 do
		local seg = stack[#stack]
		stack[#stack] = nil
		local i0, i1 = seg[1], seg[2]
		local worst, wi = -1, nil
		for i = i0 + 1, i1 - 1 do
			local d = M.pointSegDist(pts[i][1], pts[i][2], pts[i0][1], pts[i0][2], pts[i1][1], pts[i1][2])
			if d > worst then worst, wi = d, i end
		end
		if wi and worst > tol then
			keep[wi] = true
			stack[#stack + 1] = { i0, wi }
			stack[#stack + 1] = { wi, i1 }
		end
	end
	local out = { { pts[1][1], pts[1][2] } }
	local last = pts[n]
	for i = 2, n - 1 do
		if keep[i] then
			local p, q = out[#out], pts[i]
			if M.dist(p[1], p[2], q[1], q[2]) >= (minDist or 0)
				and M.dist(q[1], q[2], last[1], last[2]) >= (minDist or 0) then
				out[#out + 1] = { q[1], q[2] }
			end
		end
	end
	out[#out + 1] = { last[1], last[2] }
	return out
end

--- Deterministic 1D value noise in [-1, 1]: smooth interpolation between hashed lattice values.
--- `h(i)` must return a value in [0, 1) for integer i.
function M.smoothNoise(h, t)
	local i = floor(t)
	local f = t - i
	local a, b = h(i) * 2 - 1, h(i + 1) * 2 - 1
	local s = f * f * (3 - 2 * f)
	return a + (b - a) * s
end

---------------------------------------------------------------------------
-- smooth lines (town street templates: minCurveRadius 44 m, minCurveRadiusBuild 60 m; ot_check)

M.unit = unit2

-- turn angle (0..pi) and side (+1 left, -1 right) at corner b of a-b-c
local function corner(a, b, c)
	local ux, uy, la = unit2(b[1] - a[1], b[2] - a[2])
	local vx, vy, lc = unit2(c[1] - b[1], c[2] - b[2])
	local cr = ux * vy - uy * vx
	local dt = M.clamp(ux * vx + uy * vy, -1, 1)
	return math.acos(dt), cr >= 0 and 1 or -1, la, lc, ux, uy, vx, vy
end

-- fillet tangent length available at interior vertex i (each segment lends half its length to each of its
-- corners; the first and last segments all of it to their only corner)
local function avail(pts, i, la, lc)
	local n = #pts
	local fa = (i == 2) and la or la / 2
	local fc = (i == n - 1) and lc or lc / 2
	return math.min(fa, fc)
end

--- Moves interior vertices whose corner can't take a fillet of radius R toward their neighbours' midpoint
--- (half way per pass), up to `iters` passes. `fixed[i] = true` keeps vertex i. Ends never move. In place.
function M.relaxCorners(pts, R, iters, fixed)
	fixed = fixed or {}
	for _ = 1, iters or 40 do
		local moved = false
		for i = 2, #pts - 1 do
			if not fixed[i] then
				local th, _, la, lc = corner(pts[i - 1], pts[i], pts[i + 1])
				if th > 1e-6 and R * math.tan(th / 2) > avail(pts, i, la, lc) * 1.0001 then
					local a, b, c = pts[i - 1], pts[i], pts[i + 1]
					b[1] = b[1] + 0.5 * ((a[1] + c[1]) / 2 - b[1])
					b[2] = b[2] + 0.5 * ((a[2] + c[2]) / 2 - b[2])
					moved = true
				end
			end
		end
		if not moved then break end
	end
	return pts
end

M.FILLET_MAX = 1000   -- m: widest fillet arc

--- Corner-rounded copy of a polyline: each interior corner becomes the widest circular arc that fits (see
--- avail; at most FILLET_MAX; below R only where relaxCorners could not make room), sampled every `stepDeg` degrees of turn (default 2). Straight runs stay single
--- segments. Returns the points and the smallest radius used (math.huge without corners).
function M.fillet(pts, R, stepDeg)
	local n = #pts
	local fx, fy = unit2(pts[2][1] - pts[1][1], pts[2][2] - pts[1][2])
	local out = { { pts[1][1], pts[1][2], fx, fy } }
	local minR = math.huge
	local step = math.rad((stepDeg and stepDeg > 0) and stepDeg or 2)
	for i = 2, n - 1 do
		local th, side, la, lc, ux, uy, vx, vy = corner(pts[i - 1], pts[i], pts[i + 1])
		local b = pts[i]
		if th < 1e-4 or la <= 0 or lc <= 0 then
			out[#out + 1] = { b[1], b[2], vx, vy }
		else
			-- the widest arc that fits (curvature spread as evenly as the corners allow), at most FILLET_MAX
			local t = math.tan(th / 2)
			local av = avail(pts, i, la, lc)
			local r = math.min(math.max(R, M.FILLET_MAX), av / t)
			local d = r * t
			if r < minR then minR = r end
			local px, py = b[1] - ux * d, b[2] - uy * d
			-- centre: left normal of the incoming direction times side
			local nx, ny = -uy * side, ux * side
			local ox, oy = px + nx * r, py + ny * r
			local k = math.max(1, math.ceil(th / step - 1e-9))
			local rx, ry = px - ox, py - oy
			local last = out[#out]
			if M.dist(last[1], last[2], px, py) > 1e-6 then out[#out + 1] = { px, py, ux, uy } end
			for s = 1, k do
				local a = side * th * s / k
				local qx, qy = M.rot(rx, ry, a)
				local tx, ty = M.rot(ux, uy, a)
				out[#out + 1] = { ox + qx, oy + qy, tx, ty }
			end
			-- the arc ends exactly at b + v * d
			out[#out] = { b[1] + vx * d, b[2] + vy * d, vx, vy }
		end
	end
	local last, e = out[#out], pts[n]
	local ex, ey = unit2(e[1] - pts[n - 1][1], e[2] - pts[n - 1][2])
	if M.dist(last[1], last[2], e[1], e[2]) > 1e-6 then out[#out + 1] = { e[1], e[2], ex, ey } end
	return out, minR
end

--- Smooth copy of a polyline whose curvature radius is at least R where it can be: corners relaxed (ends
--- fixed), then filleted. opts = { iters (relax passes, default 200), stepDeg }. Returns points, smallest
--- radius used.
function M.smoothLine(pts, R, opts)
	opts = opts or {}
	local w = {}
	for i, p in ipairs(pts) do
		local q = w[#w]
		if q == nil or M.dist(q[1], q[2], p[1], p[2]) > 0.05 then w[#w + 1] = { p[1], p[2] } end
	end
	if #w < 2 then w[2] = { pts[#pts][1], pts[#pts][2] } end
	if #w <= 2 then
		local ux, uy = unit2(w[2][1] - w[1][1], w[2][2] - w[1][2])
		return { { w[1][1], w[1][2], ux, uy }, { w[2][1], w[2][2], ux, uy } }, math.huge
	end
	M.relaxCorners(w, R, opts.iters or 200)
	return M.fillet(w, R, opts.stepDeg)
end

--- Smallest circumradius of three consecutive points (the discrete curvature radius; math.huge if straight).
function M.minDiscreteRadius(pts)
	local best = math.huge
	for i = 2, #pts - 1 do
		local a, b, c = pts[i - 1], pts[i], pts[i + 1]
		local area2 = abs((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]))
		if area2 > 1e-9 then
			local r = M.dist(a[1], a[2], b[1], b[2]) * M.dist(b[1], b[2], c[1], c[2]) * M.dist(a[1], a[2], c[1], c[2])
				/ (2 * area2)
			if r < best then best = r end
		end
	end
	return best
end

--- Unit direction at every vertex (the carried ones when every point has them; else bisectors of the
--- neighbouring segment directions, at the ends the next vertex's direction mirrored about the end chord)
--- and the cumulative arc length. Returns dirs ({ {ux, uy} }), cum (cum[1] = 0).
function M.polyDirs(pts)
	local n = #pts
	local segs, cum = {}, { 0 }
	for i = 2, n do
		local ux, uy, l = unit2(pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2])
		segs[i - 1] = { ux, uy }
		cum[i] = cum[i - 1] + l
	end
	local dirs = {}
	local carried = true
	for i = 1, n do if pts[i][3] == nil then carried = false; break end end
	if carried then
		for i = 1, n do
			local x, y = unit2(pts[i][3], pts[i][4])
			dirs[i] = { x, y }
		end
		return dirs, cum
	end
	for i = 1, n do
		local a, b = segs[i - 1], segs[i]
		if a and b then
			local x, y = unit2(a[1] + b[1], a[2] + b[2])
			if x == 0 and y == 0 then x, y = b[1], b[2] end
			dirs[i] = { x, y }
		else
			local s = a or b or { 1, 0 }
			dirs[i] = { s[1], s[2] }
		end
	end
	-- ends: mirror the neighbour's tangent about the end chord (exact on a circle), not the chord itself
	if n >= 3 then
		local c, d = segs[1], dirs[2]
		local delta = atan2(c[1] * d[2] - c[2] * d[1], c[1] * d[1] + c[2] * d[2])
		dirs[1] = { M.rot(c[1], c[2], -delta) }
		c, d = segs[n - 1], dirs[n - 1]
		delta = atan2(d[1] * c[2] - d[2] * c[1], d[1] * c[1] + d[2] * c[2])
		dirs[n] = { M.rot(c[1], c[2], delta) }
	end
	return dirs, cum
end

--- Point and unit direction at arc length s of a polyline with polyDirs data (directions blended linearly
--- between the vertices). Returns x, y, ux, uy.
function M.frameAt(pts, dirs, cum, s)
	local n = #pts
	if s <= 0 then return pts[1][1], pts[1][2], dirs[1][1], dirs[1][2] end
	if s >= cum[n] then return pts[n][1], pts[n][2], dirs[n][1], dirs[n][2] end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = floor((lo + hi) / 2)
		if cum[mid] <= s then lo = mid else hi = mid end
	end
	local l = cum[hi] - cum[lo]
	local t = l > 0 and (s - cum[lo]) / l or 0
	local a, b = pts[lo], pts[hi]
	local da, db = dirs[lo], dirs[hi]
	local ux, uy = unit2(da[1] + (db[1] - da[1]) * t, da[2] + (db[2] - da[2]) * t)
	if ux == 0 and uy == 0 then ux, uy = da[1], da[2] end
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, ux, uy
end

--- Hermite curve a -> b with unit end directions d0, d1 and tangent length = chord, sampled at n + 1 points.
function M.hermitePts(ax, ay, bx, by, d0, d1, n)
	n = n or 16
	local L = M.dist(ax, ay, bx, by)
	local t0x, t0y, t1x, t1y = d0[1] * L, d0[2] * L, d1[1] * L, d1[2] * L
	local out = {}
	for i = 0, n do
		local s = i / n
		local s2, s3 = s * s, s * s * s
		local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
		local a1, b1, c1, d1 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, -6 * s2 + 6 * s, 3 * s2 - 2 * s
		local dx, dy = unit2(a1 * ax + b1 * t0x + c1 * bx + d1 * t1x, a1 * ay + b1 * t0y + c1 * by + d1 * t1y)
		out[#out + 1] = { h00 * ax + h10 * t0x + h01 * bx + h11 * t1x, h00 * ay + h10 * t0y + h01 * by + h11 * t1y,
			dx, dy }
	end
	return out
end

--- The longest stretch (m) of polyline pts along which the heading stays within tolDeg of the heading where the
--- stretch starts (the "straight run" of a link or lane; 2026-10-14 late). Measured on the polyline resampled every
--- `step` m (default 10).
function M.maxStraightRun(pts, tolDeg, step)
	local f = M.resample(pts, step or 10)
	local n = #f
	if n < 2 then return 0 end
	local hs, ls = {}, {}
	for i = 1, n - 1 do
		hs[i] = atan2(f[i + 1][2] - f[i][2], f[i + 1][1] - f[i][1])
		ls[i] = M.dist(f[i][1], f[i][2], f[i + 1][1], f[i + 1][2])
	end
	local tol = math.rad(tolDeg or 4)
	local best = 0
	for i = 1, n - 1 do
		local run = 0
		for j = i, n - 1 do
			if math.abs(M.angleDiff(hs[j], hs[i])) > tol then break end
			run = run + ls[j]
		end
		if run > best then best = run end
	end
	return best
end

return M
