-- Better Roundabouts: pure 2D/3D helpers shared by the geometry modules (no api.*, no base
-- modules). Plain Lua for the game's pre-5.3 runtime and the offline harness (Lua 5.4).
--
-- Points and vectors are {x, y, z} tables; polygons are lists of points (z ignored).

local shapes = {}

local PI = math.pi
local TWO_PI = 2 * PI
local EPS = 1e-9

-- math.atan2 in the game's 5.1-style runtime; math.atan(y, x) in Lua 5.3+ (offline tests).
shapes.atan2 = math.atan2 or math.atan
local atan2 = shapes.atan2

function shapes.vec(x, y, z) return { x, y, z or 0 } end
function shapes.add(p, q) return { p[1] + q[1], p[2] + q[2], p[3] + q[3] } end
function shapes.sub(p, q) return { p[1] - q[1], p[2] - q[2], p[3] - q[3] } end
function shapes.scale(v, s) return { v[1] * s, v[2] * s, v[3] * s } end
function shapes.dot(p, q) return p[1] * q[1] + p[2] * q[2] end
function shapes.cross(p, q) return p[1] * q[2] - p[2] * q[1] end
function shapes.len(v) return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) end
function shapes.dist(p, q) return shapes.len(shapes.sub(p, q)) end

function shapes.norm(v)
	local l = shapes.len(v)
	if l < EPS then return { 0, 0, 0 } end
	return { v[1] / l, v[2] / l, v[3] / l }
end

--- Unit vector at angle phi (radians, 0 = +x, counter-clockwise).
function shapes.dir(phi) return { math.cos(phi), math.sin(phi), 0 } end

--- v rotated by +90 degrees (counter-clockwise) in the xy plane.
function shapes.left(v) return { -v[2], v[1], 0 } end

--- a * u + b * v
function shapes.combine(u, a, v, b) return { u[1] * a + v[1] * b, u[2] * a + v[2] * b, u[3] * a + v[3] * b } end

function shapes.wrap(t)
	t = math.fmod(t, TWO_PI)
	if t < 0 then t = t + TWO_PI end
	if t >= TWO_PI - EPS then t = 0 end
	return t
end

--- Cubic Hermite point and derivative at s in [0, 1] of an edge {p0, t0, p1, t1}.
function shapes.hermite(e, s)
	local s2, s3 = s * s, s * s * s
	local h00, h10, h01, h11 = 2 * s3 - 3 * s2 + 1, s3 - 2 * s2 + s, -2 * s3 + 3 * s2, s3 - s2
	local d00, d10, d01, d11 = 6 * s2 - 6 * s, 3 * s2 - 4 * s + 1, -6 * s2 + 6 * s, 3 * s2 - 2 * s
	local p, d = {}, {}
	for i = 1, 3 do
		p[i] = h00 * e.p0[i] + h10 * e.t0[i] + h01 * e.p1[i] + h11 * e.t1[i]
		d[i] = d00 * e.p0[i] + d10 * e.t0[i] + d01 * e.p1[i] + d11 * e.t1[i]
	end
	return p, d
end

--- Straight edge from p0 to p1 (tangents = chord, as base street_util straight edges).
function shapes.straightEdge(p0, p1, tag0, tag1)
	local d = shapes.sub(p1, p0)
	return { p0 = p0, t0 = d, p1 = p1, t1 = d, tag0 = tag0, tag1 = tag1 }
end

--- Hermite edge from p0 to p1 leaving along unit d0 and arriving along unit d1; both tangents are
-- scaled to the chord length (a gentle curve without loops for direction changes below ~90 deg).
function shapes.curveEdge(p0, d0, p1, d1, tag0, tag1)
	local l = shapes.dist(p0, p1)
	return { p0 = p0, t0 = shapes.scale(d0, l), p1 = p1, t1 = shapes.scale(d1, l), tag0 = tag0, tag1 = tag1 }
end

--- Approximate arc length of a Hermite edge.
function shapes.edgeLength(e, n)
	n = n or 32
	local total, prev = 0, e.p0
	for k = 1, n do
		local p = shapes.hermite(e, k / n)
		total = total + shapes.dist(prev, p)
		prev = p
	end
	return total
end

-- ellipse x = a cos t, y = b sin t (centred on the origin)

function shapes.ellipsePoint(a, b, t) return { a * math.cos(t), b * math.sin(t), 0 } end
function shapes.ellipseDeriv(a, b, t) return { -a * math.sin(t), b * math.cos(t), 0 } end

function shapes.ellipseNormal(a, b, t)
	local nx, ny = b * math.cos(t), a * math.sin(t)
	local l = math.sqrt(nx * nx + ny * ny)
	return { nx / l, ny / l, 0 }
end

--- Ellipse parameter of the point that lies in direction phi from the centre. Monotonic in phi.
function shapes.paramForAngle(a, b, phi)
	return shapes.wrap(atan2(a * math.sin(phi), b * math.cos(phi)))
end

--- Distance from point q to the ellipse (a, b): Newton on the foot-point parameter.
function shapes.distToEllipse(a, b, q)
	local t = atan2(q[2] * a, q[1] * b)
	for _ = 1, 12 do
		local c, s = math.cos(t), math.sin(t)
		local px, py = a * c - q[1], b * s - q[2]
		local dx, dy = -a * s, b * c
		local f = px * dx + py * dy
		local df = dx * dx + dy * dy + px * (-a * c) + py * (-b * s)
		if math.abs(df) < EPS then break end
		t = t - f / df
	end
	return shapes.dist(q, shapes.ellipsePoint(a, b, t))
end

-- polygons

function shapes.area(poly)
	local s = 0
	for i, p in ipairs(poly) do
		local q = poly[i % #poly + 1]
		s = s + p[1] * q[2] - q[1] * p[2]
	end
	return s / 2
end

function shapes.ccw(poly)
	if shapes.area(poly) >= 0 then return poly end
	local out = {}
	for i = #poly, 1, -1 do out[#out + 1] = poly[i] end
	return out
end

function shapes.pointInPolygon(x, y, poly)
	local inside = false
	local j = #poly
	for i = 1, #poly do
		local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
		if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi) then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function distToSegment(q, a, b)
	local ab = shapes.sub(b, a)
	local l2 = shapes.dot(ab, ab)
	local s = 0
	if l2 > EPS then s = math.max(0, math.min(1, shapes.dot(shapes.sub(q, a), ab) / l2)) end
	return shapes.dist({ q[1], q[2], 0 }, { a[1] + ab[1] * s, a[2] + ab[2] * s, 0 })
end
shapes.distToSegment = distToSegment

--- Distance from (x, y) to the polygon boundary.
function shapes.distToBoundary(x, y, poly)
	local q = { x, y, 0 }
	local best = math.huge
	for i, p in ipairs(poly) do
		best = math.min(best, distToSegment(q, p, poly[i % #poly + 1]))
	end
	return best
end

--- True if a disc of radius r at (x, y) lies inside the polygon.
function shapes.fits(x, y, r, poly)
	return shapes.pointInPolygon(x, y, poly) and shapes.distToBoundary(x, y, poly) >= r
end

--- Sutherland-Hodgman: the part of the polygon where dot(p, n) >= c.
function shapes.clipHalfPlane(poly, n, c)
	local out = {}
	for i, p in ipairs(poly) do
		local q = poly[i % #poly + 1]
		local dp, dq = shapes.dot(p, n) - c, shapes.dot(q, n) - c
		if dp >= 0 then out[#out + 1] = p end
		if (dp >= 0) ~= (dq >= 0) then
			local s = dp / (dp - dq)
			out[#out + 1] = { p[1] + (q[1] - p[1]) * s, p[2] + (q[2] - p[2]) * s, 0 }
		end
	end
	return out
end

--- Interval [lo, hi] of dot(p, e) over the points of a convex polygon on the line dot(p, w) = s.
local function chordInterval(poly, e, w, s)
	local lo, hi = math.huge, -math.huge
	for i, p in ipairs(poly) do
		local q = poly[i % #poly + 1]
		local sp, sq = shapes.dot(p, w), shapes.dot(q, w)
		if (sp - s) * (sq - s) <= 0 and math.abs(sp - sq) > EPS then
			local k = (s - sp) / (sq - sp)
			local t = shapes.dot(p, e) + (shapes.dot(q, e) - shapes.dot(p, e)) * k
			lo, hi = math.min(lo, t), math.max(hi, t)
		elseif math.abs(sp - s) <= EPS then
			lo, hi = math.min(lo, shapes.dot(p, e)), math.max(hi, shapes.dot(p, e))
		end
	end
	return lo, hi
end

--- Largest box (by sampling) inside a convex polygon with sides along the unit vectors e and
-- w = left(e), one side on the line dot(p, w) = s0. Returns {x, y, rot, hx, hy} (half extents
-- along e and w) or nil. For a convex polygon the box [s0, s1] x (I(s0) and I(s1)) is inside.
function shapes.boxFrom(poly, e, s0, gap)
	gap = gap or 0.2
	local w = shapes.left(e)
	local smax = -math.huge
	for _, p in ipairs(poly) do smax = math.max(smax, shapes.dot(p, w)) end
	local a = s0 + gap
	if smax - gap <= a then return nil end
	local lo0, hi0 = chordInterval(poly, e, w, a)
	local best
	for k = 1, 24 do
		local s1 = a + (smax - gap - a) * k / 24
		local lo1, hi1 = chordInterval(poly, e, w, s1)
		local lo, hi = math.max(lo0, lo1) + gap, math.min(hi0, hi1) - gap
		if hi > lo then
			local areaK = (hi - lo) * (s1 - a)
			if not best or areaK > best.areaK then
				best = { lo = lo, hi = hi, s1 = s1, areaK = areaK }
			end
		end
	end
	if not best then return nil end
	local tc, sc = (best.lo + best.hi) / 2, (a + best.s1) / 2
	local c = shapes.combine(e, tc, w, sc)
	return { x = c[1], y = c[2], rot = atan2(e[2], e[1]), hx = (best.hi - best.lo) / 2, hy = (best.s1 - a) / 2 }
end

--- First intersection of two polylines (walking a from its start), or nil.
-- Returns the point and the segment indices.
function shapes.polylineIntersection(a, b)
	for i = 1, #a - 1 do
		local p, r = a[i], shapes.sub(a[i + 1], a[i])
		for j = 1, #b - 1 do
			local q, s = b[j], shapes.sub(b[j + 1], b[j])
			local den = shapes.cross(r, s)
			if math.abs(den) > EPS then
				local qp = shapes.sub(q, p)
				local u = shapes.cross(qp, s) / den
				local v = shapes.cross(qp, r) / den
				if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
					return { p[1] + r[1] * u, p[2] + r[2] * u, 0 }, i, j
				end
			end
		end
	end
	return nil
end

--- Kerb line of a Hermite edge: n + 1 points offset by `off` to the left of the driving direction
-- (side = 1) or to the right (side = -1), from p0 to p1, extended straight by `ext` metres beyond
-- both ends along the end tangents (so a crossing just past a node is still found).
function shapes.offsetPolyline(e, side, off, n, ext)
	n, ext = n or 40, ext or 0
	local pts = {}
	for k = 0, n do
		local p, d = shapes.hermite(e, k / n)
		local o = shapes.add(p, shapes.scale(shapes.left(shapes.norm(d)), side * off))
		pts[#pts + 1] = { o[1], o[2], 0 }
	end
	if ext > 0 then
		local d0, d1 = shapes.norm(e.t0), shapes.norm(e.t1)
		local first, last = pts[1], pts[#pts]
		table.insert(pts, 1, { first[1] - d0[1] * ext, first[2] - d0[2] * ext, 0 })
		pts[#pts + 1] = { last[1] + d1[1] * ext, last[2] + d1[2] * ext, 0 }
	end
	return pts
end

--- Polygon bounded by a closed cycle of polylines ("chains"): chain i runs from where it meets
-- chain i - 1 to where it meets chain i + 1 (the first crossing walking chain i), the last chain
-- meets the first. Returns the polygon (CCW) or nil if two neighbouring chains do not cross or
-- the crossings come in the wrong order along a chain.
function shapes.chainPolygon(chains)
	local n = #chains
	local cut = {} -- cut[i] = {point, segment index in chain i, segment index in chain i + 1}
	for i = 1, n do
		local pt, a, b = shapes.polylineIntersection(chains[i], chains[i % n + 1])
		if not pt then return nil end
		cut[i] = { pt, a, b }
	end
	local poly = {}
	for i = 1, n do
		local prev = cut[(i - 2) % n + 1] -- where chain i starts (its segment index: prev[3])
		local nxt = cut[i]                -- where chain i ends (segment index nxt[2])
		if nxt[2] < prev[3] then return nil end
		poly[#poly + 1] = prev[1]
		for k = prev[3] + 1, nxt[2] do poly[#poly + 1] = chains[i][k] end
	end
	return shapes.ccw(poly)
end

--- p mirrored in x (x -> -x): left-hand traffic layouts built from right-hand ones.
function shapes.mirrorX(p) return { -p[1], p[2], p[3] } end

--- Column-major 4x4: rotation about z by rot, translation (x, y, z) (base model transf layout).
function shapes.transf(x, y, z, rot)
	local c, s = math.cos(rot or 0), math.sin(rot or 0)
	return { c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, x, y, z or 0, 1 }
end

return shapes
