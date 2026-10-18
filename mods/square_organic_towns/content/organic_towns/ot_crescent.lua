-- Organic Towns: crescents around a green (pure). Showcase v9 round (2026-10-12).
--
-- User on the Showcase v8 EU organic town: "I like EU organic and in general moments like this: the empty green space
-- and big curve is interesting" (a sweeping street of ~150-250 m radius wrapped around an unbuilt meadow of ~150 x
-- 200 m, dense blocks on the outside of the curve, short streets radiating off it). As a deliberate motif: the first
-- style.crescents green reserves (ot_style.greenReserves, entry [4] = true) get a long smooth arc around them. The
-- master plan is cut at the circle (radius = the meadow's + ARC_SETBACK): pieces inside are dropped (the meadow gets
-- no interior streets; ot_select.inGreen keeps the town's planner out too), pieces crossing it end at the circle in
-- a T on the arc, and arc pieces run between neighbouring crossings, except across the widest gap (and any gap over
-- MAX_GAP_DEG): a crescent open on one side, not a ring. Plain town streets ("small"; the arc's curvature stays
-- within the town templates' radius, ot_plan) that the town lines with houses on both sides; the meadow side's lots
-- only nibble at its edge. Not saved: derived from the style each session like the reserves.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local C = {}

C.ON = true
C.ARC_SETBACK = 10       -- m: arc radius = meadow radius + this (inGreen tests < r; the planner cuts the arc into
                         -- chords of up to 40 deg, whose midpoints lie 6 % of R inside it: they stay outside the meadow)
C.MAX_GAP_DEG = 150      -- no arc across a gap wider than this between two crossings
C.MIN_ARC_M = 25         -- arcs shorter than this are left out (two crossings close together)
C.STEP_DEG = 5           -- arc points every this many degrees (unit tangents carried: a smooth curve for ot_plan)
-- Organic ring geometry (style.ringWobble, 2026-10-14 §56): the crescent runs on a seeded curve r(angle) = R x (1 + BULGE x
-- (1 + 0.6 sin(2 a + p1) + 0.4 sin(3 a + p2)) / 2) instead of the circle: outward only (the meadow keeps its size), up to
-- BULGE x R wider, so the crescent is no circle segment; the plan is cut where it meets that curve.
C.BULGE = 0.1
C.MIN_RADIUS = 80
C.CUT_STEP = 8           -- m: the curve crossings are searched in steps of this along each piece (bisection after)

--- The crescent's radius function (a circle without style.ringWobble).
function C.radiusFn(style, gi, R)
	if not (style and style.ringWobble) then return function() return R end end
	local seed = style.seed or 1
	local p1, p2 = 2 * math.pi * rng.unit(seed, "crescentP1", gi), 2 * math.pi * rng.unit(seed, "crescentP2", gi)
	return function(a)
		return R * (1 + C.BULGE * (1 + 0.6 * math.sin(2 * a + p1) + 0.4 * math.sin(3 * a + p2)) / 2)
	end
end

local function atan2(y, x)
	if math.atan2 then return math.atan2(y, x) end
	return math.atan(y, x)
end

--- Fractions (by length) where polyline pts crosses the curve r(angle) around (cx, cy) (Rf; a circle: the exact roots):
--- sorted list of { f, x, y }.
local function curveCrossings(pts, cx, cy, Rf)
	local out = {}
	local total = G.polyLen(pts)
	if total <= 0 then return out end
	local function f(x, y) return G.dist(cx, cy, x, y) - Rf(atan2(y - cy, x - cx)) end
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local l = G.dist(a[1], a[2], b[1], b[2])
		if l > 0 then
			local n = math.max(1, math.min(400, math.ceil(l / C.CUT_STEP)))
			local t0, v0 = 0, f(a[1], a[2])
			for k = 1, n do
				local t1 = k / n
				local v1 = f(a[1] + (b[1] - a[1]) * t1, a[2] + (b[2] - a[2]) * t1)
				if (v0 < 0) ~= (v1 < 0) then
					local lo, hi = t0, t1
					for _ = 1, 30 do
						local m = (lo + hi) / 2
						local vm = f(a[1] + (b[1] - a[1]) * m, a[2] + (b[2] - a[2]) * m)
						if (vm < 0) == (v0 < 0) then lo = m else hi = m end
					end
					local t = (lo + hi) / 2
					if t > 1e-6 and t < 1 - 1e-6 then
						out[#out + 1] = { (acc + t * l) / total, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t }
					end
				end
				t0, v0 = t1, v1
			end
		end
		acc = acc + l
	end
	table.sort(out, function(p, q) return p[1] < q[1] end)
	return out
end

--- Fractions (by length) where polyline pts crosses the circle (cx, cy, R): sorted list of { f, x, y }.
local function crossings(pts, cx, cy, R)
	local out = {}
	local total = G.polyLen(pts)
	if total <= 0 then return out end
	local acc = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		local l = math.sqrt(dx * dx + dy * dy)
		if l > 0 then
			-- |a + t (b - a) - c|^2 = R^2
			local fx, fy = a[1] - cx, a[2] - cy
			local A = dx * dx + dy * dy
			local B = 2 * (fx * dx + fy * dy)
			local Cc = fx * fx + fy * fy - R * R
			local disc = B * B - 4 * A * Cc
			if disc > 0 then
				local sq = math.sqrt(disc)
				for _, t in ipairs({ (-B - sq) / (2 * A), (-B + sq) / (2 * A) }) do
					if t > 1e-6 and t < 1 - 1e-6 then
						out[#out + 1] = { (acc + t * l) / total, a[1] + t * dx, a[2] + t * dy }
					end
				end
			end
		end
		acc = acc + l
	end
	table.sort(out, function(p, q) return p[1] < q[1] end)
	return out
end

--- Arc points on the circle from angle t0 to t1 (counter-clockwise, t1 > t0) with unit tangents.
local function arcPts(cx, cy, R, t0, t1, Rf)
	local n = math.max(2, math.ceil(math.deg(t1 - t0) / C.STEP_DEG))
	local pts = {}
	for k = 0, n do
		local t = t0 + (t1 - t0) * k / n
		local r = Rf and Rf(t) or R
		pts[#pts + 1] = { cx + r * math.cos(t), cy + r * math.sin(t), -math.sin(t), math.cos(t) }
	end
	if Rf then
		-- (the curve's own tangents)
		local dirs = G.polyDirs(pts)
		for k, p in ipairs(pts) do p[3], p[4] = dirs[k][1], dirs[k][2] end
	end
	return pts
end

--- Applies the crescents of style (style.greens entries with [4] = true) to master plan mp in place. Returns the
--- number of crescents made (a green with at least one arc piece); mp.crescents = { {x, y, R, arcs = n} }.
function C.apply(mp, style)
	mp.crescents = {}
	if not C.ON or mp == nil or style == nil or style.greens == nil then return 0 end
	local made = 0
	for gi, gr in ipairs(style.greens) do
		if gr[4] then
			local cx, cy, R = gr[1], gr[2], gr[3] + C.ARC_SETBACK
			-- (organic ring geometry: the curve, outward of the circle; else the circle as before)
			local Rf = style.ringWobble and C.radiusFn(style, gi, R) or nil
			local function outside(x, y)
				if Rf then return G.dist(cx, cy, x, y) >= Rf(atan2(y - cy, x - cx)) end
				return G.dist(cx, cy, x, y) >= R
			end
			local kept, cross = {}, {}
			for _, pc in ipairs(mp.pieces) do
				local cs = Rf and curveCrossings(pc.pts, cx, cy, Rf) or crossings(pc.pts, cx, cy, R)
				if #cs == 0 then
					local mx, my = G.polyAt(pc.pts, 0.5)
					if outside(mx, my) then kept[#kept + 1] = pc end   -- (inside: the meadow, dropped)
				else
					local cuts, keys = {}, { pc.a }
					for k, c in ipairs(cs) do
						local key = "X" .. gi .. ":" .. pc.key .. ":" .. k
						mp.junctions[key] = { c[2], c[3] }
						cuts[k] = { c[1], c[2], c[3] }
						keys[#keys + 1] = key
						cross[#cross + 1] = { t = atan2(c[3] - cy, c[2] - cx), key = key }
					end
					keys[#keys + 1] = pc.b
					local parts = G.polySplit(pc.pts, cuts)
					for i, pts in ipairs(parts) do
						local mx, my = G.polyAt(pts, 0.5)
						if keys[i + 1] and outside(mx, my) then
							local np = {}
							for k, v in pairs(pc) do np[k] = v end
							np.key, np.a, np.b, np.pts = pc.key .. "~" .. gi .. ":" .. i, keys[i], keys[i + 1], pts
							-- (the original end directions only where the original ends are)
							if i ~= 1 then np.dirA = nil end
							if i ~= #parts then np.dirB = nil end
							-- (a planned cul-de-sac cut at the circle keeps its dead end only on its outer part)
							kept[#kept + 1] = np
						end
					end
				end
			end
			-- arcs between neighbouring crossings, the widest gap open
			table.sort(cross, function(p, q) return p.t < q.t end)
			local arcs = 0
			if #cross >= 2 then
				local wide, wi = -1, 1
				for i = 1, #cross do
					local nx = cross[i % #cross + 1]
					local gap = (nx.t - cross[i].t) % (2 * math.pi)
					if gap > wide then wide, wi = gap, i end
				end
				for i = 1, #cross do
					local nx = cross[i % #cross + 1]
					local gap = (nx.t - cross[i].t) % (2 * math.pi)
					if i ~= wi and gap <= math.rad(C.MAX_GAP_DEG) and gap * R >= C.MIN_ARC_M then
						local t0 = cross[i].t
						local pts = arcPts(cx, cy, R, t0, t0 + gap, Rf)
						-- (the arc's ends exactly on the crossings)
						if Rf then
							local ca, cb = mp.junctions[cross[i].key], mp.junctions[nx.key]
							pts[1][1], pts[1][2] = ca[1], ca[2]
							pts[#pts][1], pts[#pts][2] = cb[1], cb[2]
						end
						kept[#kept + 1] = { key = "arc" .. gi .. ":" .. i, a = cross[i].key, b = nx.key,
							pts = pts, class = "small", curved = true, smooth = true, crescent = gi }
						arcs = arcs + 1
					end
				end
			end
			mp.pieces = kept
			if arcs > 0 then made = made + 1 end
			mp.crescents[#mp.crescents + 1] = { cx, cy, R, arcs = arcs }
		end
	end
	return made
end

return C
