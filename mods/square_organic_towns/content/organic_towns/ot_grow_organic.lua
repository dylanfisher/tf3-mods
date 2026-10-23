-- Organic Towns: organic growth (EU organic core, EU 19th-c. extension outer zone, MED hill town). Pure.
--
-- Master plan, all from the town seed (stable while the town grows; a larger extent only adds to it):
--   spokes  `radial.spokes` streets from the centre, heading jittered, wobbling (`curve`) and on slopes bent
--           toward the contour (`contour`), integrated in 30 m steps;
--   rings   an inner ring at ~0.45 x `radial.ringEvery` (old wall line), then every ringEvery m (radius
--           varied), arcs between consecutive spokes;
--   infill  per cell (between two spokes and two rings): secondary radials about block.len apart, joined by
--           cross lanes about block.depth apart; for low gridness the lanes of neighbouring strips are offset
--           (T-junctions instead of crossings) and bent. Inside the first ring only cross lanes between spokes.
-- Lines carry "taps" (junctions where infill meets them); each line is split at its taps into plan pieces.

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"
local OG = ug_require "square_organic_towns::/organic_towns/ot_graph.lua"
local S = ug_require "square_organic_towns::/organic_towns/ot_select.lua"
local T = ug_require "square_organic_towns::/organic_towns/ot_terrain.lua"
local style_ = ug_require "square_organic_towns::/organic_towns/ot_style.lua"
local rng = ug_require "square_organic_towns::/organic_towns/ot_rng.lua"

local M = {}

local cos, sin, floor, max, abs = math.cos, math.sin, math.floor, math.max, math.abs
local STEP = 10          -- spoke integration step (m)
local MIN_GAP = 14       -- taps closer than this along a line (or to its ends) snap together
-- Every plan line is a smooth curve of at least this radius (ot_geom.smoothLine), so the edges cut from it
-- pass the town street templates' curve limits (minCurveRadius 44 m, player tool 60 m; ot_check) and keep
-- one tangent through the junctions along it. The planner's edge check is 70 m (ot_plan.MIN_RADIUS).
M.LINE_RADIUS = 80
M.SPOKE_RADIUS = 90              -- m: spokes steer with at most STEP / SPOKE_RADIUS radians per step
M.INNER_RING_MIN = 100           -- m: the inner ring never tighter (MED hill's 0.45 x 150 m was 67 m)
-- Deep arms (2026-10-12, Showcase v5: shaped towns' arms read as ladders / fishbones, a spine with cross stubs).
-- Ribbon villages and street villages have back lanes parallel to the main street, joined into closed blocks. In
-- a shaped town (ot_shape linear / ridge / cross / fingers) every spoke an arm sits on gets BACK_ROWS back streets
-- on each side in the ring cells beside it: offsets of the spoke at BACK_OFFSET x block.depth, 2 x ..., where the
-- cell is wide enough (the second row further out), replacing the cell's secondary radials there (they diverge from
-- the spoke), and cross lanes between the spoke and the rows about every ARM_LANE x block.len (instead of every
-- block depth: blocks lie along the main street). Spoke and rows carry `armLine` (ot_select keeps a line's tip a
-- dead end when a lane meets it, so it can grow on: the game joins only dead ends).
M.DEEP_ARMS = true
M.BACK_ROWS = 2
M.BACK_OFFSET = 1.0
M.ARM_SPOKE_TOL = math.rad(12)   -- an arm sits on a spoke within this angle (ot_shape puts them exactly on spokes)
M.ARM_LANE = 0.85
M.BACK_FROM_RING = 2             -- back rows from this ring outward (the first ring cell lies in the game's own core)

--- A line with taps. pts from its start junction to its end junction.
local function newLine(pts, ka, kb, class, key)
	return { pts = pts, a = ka, b = kb, class = class, key = key, taps = {}, len = G.polyLen(pts) }
end

--- Junction key for the point at fraction f of `line` (an existing tap or end within MIN_GAP is reused).
local function tap(mp, line, f)
	f = G.clamp(f, 0, 1)
	local at = f * line.len
	if at < MIN_GAP then return line.a end
	if line.len - at < MIN_GAP then return line.b end
	for _, t in ipairs(line.taps) do
		if abs(t.f * line.len - at) < MIN_GAP then return t.key end
	end
	local x, y = G.polyAt(line.pts, f)
	local key = line.key .. "@" .. #line.taps + 1
	line.taps[#line.taps + 1] = { f = f, key = key }
	mp.junctions[key] = { x, y }
	return key
end

--- Splits every line at its taps into pieces.
local function emit(mp, line, curved)
	table.sort(line.taps, function(p, q) return p.f < q.f end)
	local cuts, keys = {}, { line.a }
	for _, t in ipairs(line.taps) do
		local j = mp.junctions[t.key]
		cuts[#cuts + 1] = { t.f, j[1], j[2] }
		keys[#keys + 1] = t.key
	end
	keys[#keys + 1] = line.b
	local parts = G.polySplit(line.pts, cuts)
	for i, pts in ipairs(parts) do
		-- snap the ends exactly onto the junctions
		local ja, jb = mp.junctions[keys[i]], mp.junctions[keys[i + 1]]
		if ja and jb then
			pts[1] = { ja[1], ja[2], pts[1][3], pts[1][4] }
			pts[#pts] = { jb[1], jb[2], pts[#pts][3], pts[#pts][4] }
			mp.pieces[#mp.pieces + 1] = { key = line.key .. "#" .. i, a = keys[i], b = keys[i + 1], pts = pts,
				class = line.class, curved = curved, smooth = true, armLine = line.armLine, ringArc = line.ringArc }
		end
	end
end

--- Distance from a point to a polyline.
local function polyDist(pts, x, y)
	local best = math.huge
	for i = 2, #pts do
		local d = G.pointSegDist(x, y, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2])
		if d < best then best = d end
	end
	return best
end

--- Fraction along ring line `ring` (fromEnd: near its end) where its distance from the spoke polyline reaches d;
--- nil when the ring's middle is closer than d (the cell is too narrow for that row).
local function backFraction(ring, spokePts, d, fromEnd, cx, cy)
	-- (only the spoke's points near the ring's radius: the nearest point lies within ~d of the crossing)
	local r0 = G.dist(cx, cy, ring.pts[1][1], ring.pts[1][2])
	local r1 = G.dist(cx, cy, ring.pts[#ring.pts][1], ring.pts[#ring.pts][2])
	local lo_, hi_ = math.min(r0, r1) - 1.5 * d - 40, math.max(r0, r1) + 1.5 * d + 40
	local near = {}
	for k, p in ipairs(spokePts) do
		local r = G.dist(cx, cy, p[1], p[2])
		if r >= lo_ and r <= hi_ then
			if #near == 0 and k > 1 then near[1] = spokePts[k - 1] end
			near[#near + 1] = p
		elseif r > hi_ then
			near[#near + 1] = p
			break
		end
	end
	if #near >= 2 then spokePts = near end
	local function distAt(f)
		local x, y = G.polyAt(ring.pts, fromEnd and (1 - f) or f)
		return polyDist(spokePts, x, y)
	end
	if distAt(0.5) < d then return nil end
	local lo, hi = 0, 0.5
	for _ = 1, 16 do
		local mid = (lo + hi) / 2
		if distAt(mid) < d then lo = mid else hi = mid end
	end
	local f = (lo + hi) / 2
	return fromEnd and (1 - f) or f
end

--- A back street's polyline from junction A (inner ring) to B (outer ring): the spoke offset by d to the left
--- (sigma 1) or right (-1) of its outward direction, between the rings; straight when the offset can't keep
--- LINE_RADIUS.
local function backPts(spokePts, sigma, d, A, B, cx, cy)
	local rA, rB = G.dist(cx, cy, A[1], A[2]), G.dist(cx, cy, B[1], B[2])
	local pts = { { A[1], A[2] } }
	local lastR = rA
	for _, p in ipairs(spokePts) do
		if p[3] then
			local x, y = p[1] - sigma * p[4] * d, p[2] + sigma * p[3] * d
			local r = G.dist(cx, cy, x, y)
			if r > lastR + 30 and r < rB - 30 then
				pts[#pts + 1] = { x, y }
				lastR = r
			end
		end
	end
	pts[#pts + 1] = { B[1], B[2] }
	if #pts > 2 and G.minDiscreteRadius(pts) >= M.LINE_RADIUS * 1.5 then
		-- (already smooth: the spoke's own curvature, offset; no relaxation needed)
		local dirs = G.polyDirs(pts)
		for k, p in ipairs(pts) do p[3], p[4] = dirs[k][1], dirs[k][2] end
		return pts, true
	end
	if #pts > 2 then
		local sm = G.smoothLine(pts, M.LINE_RADIUS)
		if G.minDiscreteRadius(sm) >= M.LINE_RADIUS * 0.9 then return sm, true end
	end
	return { { A[1], A[2] }, { B[1], B[2] } }, false
end

--- Cross lanes between an arm's spoke and its back streets (or two rows) across a ring gap: about one per
--- ARM_LANE x block.len (blocks along the main street), spaced at least MIN_BLOCK.
function M.armLaneCount(gap, blockLen)
	local n = G.clamp(floor(gap / (M.ARM_LANE * blockLen) + 0.5) - 1, 0, 8)
	local cap = floor(gap / style_.MIN_BLOCK) - 1
	return G.clamp(math.min(n, cap), 0, 8)
end

--- Spoke polyline from the centre out to `extent` (prefix-stable: a larger extent only appends points).
local function spoke(style, i, theta, extent, terrain)
	local cx, cy = style.centre[1], style.centre[2]
	local seed = style.seed or 1
	local pts = { { cx, cy } }
	local x, y = cx, cy
	local curve = math.rad(style.curve or 0)
	local contour = style.contour or 0
	local maxSlope = max(style.maxSlope or 0.1, 0.01)
	local function noise(n) return rng.unit(seed, "spoke", i, n) end
	local steps = 0
	local pdx, pdy = nil, nil
	while G.dist(cx, cy, x, y) < extent and steps < extent / STEP * 3 do
		steps = steps + 1
		local r = G.dist(cx, cy, x, y)
		-- (deep forest towns, ot_forest.deepStyle: a shorter wobble, curveWave 110 m)
		local want = theta + curve * G.smoothNoise(noise, r / (style.curveWave or 200))
		local dx, dy = cos(want), sin(want)
		if terrain and contour > 0 and r > STEP then
			local gx, gy = T.gradient(terrain, x, y)
			local sl = G.len(gx, gy)
			local cap = maxSlope * 0.85
			if contour >= 0.3 and sl > cap then
				-- too steep along `want`: turn to the nearest heading whose grade is within the cap
				-- (|cos(angle to the gradient)| <= cap / slope); several turns make a winding street
				local gh = G.atan2(gy, gx)
				local phi = G.wrap(want - gh)
				local lim = math.acos(cap / sl)
				local a = G.clamp(abs(phi), lim, math.pi - lim)
				local h2 = gh + (phi >= 0 and a or -a)
				-- the street can only turn slowly (SPOKE_RADIUS): keep to the side of the gradient it is on,
				-- or a flip of `want` across the gradient would steer it straight uphill
				if pdx and a > lim - 1e-9 then
					local ph = G.atan2(pdy, pdx)
					local other = gh - (phi >= 0 and a or -a)
					if G.angleDiff(other, ph) < G.angleDiff(h2, ph) then h2 = other end
				end
				dx, dy = cos(h2), sin(h2)
			else
				local ch = T.contourHeading(terrain, x, y, want)
				if ch then
					local w = contour * G.clamp(sl / maxSlope, 0, 1) * 0.85
					dx, dy = dx * (1 - w) + cos(ch) * w, dy * (1 - w) + sin(ch) * w
				end
			end
		end
		-- never turn back toward the centre
		local ox, oy = cos(theta), sin(theta)
		if r > 0 then ox, oy = (x - cx) / r, (y - cy) / r end
		local l = G.len(dx, dy)
		if l < 1e-6 then dx, dy, l = ox, oy, 1 end
		dx, dy = dx / l, dy / l
		if dx * ox + dy * oy < 0.05 then dx, dy = dx + ox * 0.3, dy + oy * 0.3; l = G.len(dx, dy); dx, dy = dx / l, dy / l end
		-- steer like a street: curvature radius at least SPOKE_RADIUS (the polyline needs no smoothing)
		if pdx then
			local maxTurn = STEP / math.max(M.LINE_RADIUS, style.spokeRadius or M.SPOKE_RADIUS)
			local turn = G.wrap(G.atan2(dy, dx) - G.atan2(pdy, pdx))
			if abs(turn) > maxTurn then
				local h = G.atan2(pdy, pdx) + (turn > 0 and maxTurn or -maxTurn)
				dx, dy = cos(h), sin(h)
			end
		end
		pdx, pdy = dx, dy
		x, y = x + dx * STEP, y + dy * STEP
		pts[#pts + 1] = { x, y }
	end
	local dirs = G.polyDirs(pts)
	for k, p in ipairs(pts) do p[3], p[4] = dirs[k][1], dirs[k][2] end
	return pts
end

--- Point where polyline `pts` (from the centre) first reaches distance r; returns x, y, index after it and
--- the line's direction there (when the points carry directions).
local function atRadius(pts, cx, cy, r)
	for k = 2, #pts do
		local d0 = G.dist(cx, cy, pts[k - 1][1], pts[k - 1][2])
		local d1 = G.dist(cx, cy, pts[k][1], pts[k][2])
		if d1 >= r then
			local t = 0
			if d1 > d0 then t = G.clamp((r - d0) / (d1 - d0), 0, 1) end
			local a, b = pts[k - 1], pts[k]
			local dx, dy = G.lerpDir(a, b, t)
			return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, k, dx, dy
		end
	end
	return nil
end

--- Polyline of `pts` between the ring crossings at index ranges (inclusive), with exact end points.
local function subPoly(pts, x0, y0, k0, x1, y1, k1, d0, d1)
	d0, d1 = d0 or {}, d1 or {}
	local out = { { x0, y0, d0[1], d0[2] } }
	for k = k0, k1 - 1 do out[#out + 1] = { pts[k][1], pts[k][2], pts[k][3], pts[k][4] } end
	out[#out + 1] = { x1, y1, d1[1], d1[2] }
	-- drop near-duplicate points
	local clean = { out[1] }
	for k = 2, #out do
		local p, q = clean[#clean], out[k]
		if G.dist(p[1], p[2], q[1], q[2]) > 1 then clean[#clean + 1] = q end
	end
	if #clean == 1 then clean[2] = out[#out] end
	clean[#clean] = out[#out]
	return clean
end

--- Arc from junction A to junction B around the centre (counter-clockwise): a polar curve r(angle), the
--- radius blended with a smoothstep plus noise weighted by sin^2, so it leaves and reaches the spokes square
--- to the centre (neighbouring arcs share one tangent at the junction). Sampled densely (<= 4 deg, <= 12 m);
--- the noise is halved until the curve's radius is at least LINE_RADIUS (dropped after 4 tries).
local function arc(style, cx, cy, a, b, key, jitterAmp)
	local ra, rb = G.dist(cx, cy, a[1], a[2]), G.dist(cx, cy, b[1], b[2])
	local aa, ab = G.atan2(a[2] - cy, a[1] - cx), G.atan2(b[2] - cy, b[1] - cx)
	local span = ab - aa
	-- (hang fix: modulo, not a loop; NaN stays NaN and makes a 2-point arc)
	if span <= 0 then span = span % (2 * math.pi); if span <= 0 then span = span + 2 * math.pi end end
	local rMin = math.min(ra, rb)
	local n = max(2, math.ceil(span / math.min(math.rad(4), 12 / math.max(rMin, 1)) - 1e-9))
	local function h(i) return rng.unit(style.seed or 1, "arc", key, i) end
	local amp = jitterAmp
	local function at(t)
		local sm = t * t * (3 - 2 * t)
		local w = sin(t * math.pi)
		local r = ra + (rb - ra) * sm + amp * w * w * G.smoothNoise(h, t * 2.5)
		local ang = aa + span * t
		return cx + cos(ang) * r, cy + sin(ang) * r
	end
	local pts
	for try = 1, 5 do
		pts = {}
		for k = 0, n do
			local t = k / n
			local x, y = at(t)
			local x0, y0 = at(math.max(0, t - 1e-4))
			local x1, y1 = at(math.min(1, t + 1e-4))
			local dx, dy = G.unit(x1 - x0, y1 - y0)
			pts[#pts + 1] = { x, y, dx, dy }
		end
		pts[1][1], pts[1][2] = a[1], a[2]
		pts[#pts][1], pts[#pts][2] = b[1], b[2]
		if G.minDiscreteRadius(pts) >= M.LINE_RADIUS or amp == 0 then break end
		amp = (try >= 4) and 0 or amp * 0.5
	end
	return pts
end

--- Deep forest towns (ot_forest.deepStyle `wiggle` { amp, wave }, 2026-10-14): a long straight lane from a to b as
--- gentle bows, offset(s) = A x sin(pi m s / L) with m = round(L / wave) half waves (one bow up to ~1.5 x wave, then an
--- S ...), sampled every 10 m. The amplitude is at most amp and at most 0.9 x (L / (m pi))^2 / LINE_RADIUS, so the bows'
--- radius stays above LINE_RADIUS (checked: the discrete radius; nil when it is not met, the caller keeps its line).
--- Each bow leaves its ends at A m pi / L off the chord (about 10-15 deg, like the existing bent lanes); the longest
--- straight stretch (heading within 4 deg) is about a quarter of a bow. Lines shorter than MIN_WIGGLE stay (nil).
M.MIN_WIGGLE = 50
function M.wiggle(a, b, wg, sign)
	if wg == nil or (wg.amp or 0) <= 0 then return nil end
	local l = G.dist(a[1], a[2], b[1], b[2])
	local wave = wg.wave or 90
	if not (l >= M.MIN_WIGGLE) or l > 4000 then return nil end
	local m = math.max(1, floor(l / wave + 0.5))
	local half = l / (m * math.pi)
	local A = math.min(wg.amp, 0.9 * half * half / M.LINE_RADIUS)
	if A < 1 then return nil end
	A = A * (sign or 1)
	local nx, ny = -(b[2] - a[2]) / l, (b[1] - a[1]) / l
	local n = math.max(4, math.ceil(l / 10))
	local pts = {}
	for k = 0, n do
		local t = k / n
		local o = A * sin(math.pi * m * t)
		pts[#pts + 1] = { a[1] + (b[1] - a[1]) * t + nx * o, a[2] + (b[2] - a[2]) * t + ny * o }
	end
	pts[1], pts[#pts] = { a[1], a[2] }, { b[1], b[2] }
	if G.minDiscreteRadius(pts) < M.LINE_RADIUS then return nil end
	local dirs = G.polyDirs(pts)
	for k, p in ipairs(pts) do p[3], p[4] = dirs[k][1], dirs[k][2] end
	return pts
end

--- A lane between two junctions, bent by up to `bend` m sideways at its middle (wg: a deep town's wiggle instead, for
--- lanes long enough, M.wiggle).
local function lane(mp, ka, kb, class, key, bend, seed, wg)
	local a, b = mp.junctions[ka], mp.junctions[kb]
	local l = G.dist(a[1], a[2], b[1], b[2])
	if l < MIN_GAP or ka == kb then return end
	local pts = { { a[1], a[2] }, { b[1], b[2] } }
	local amp = bend * (rng.unit(seed, "bend", key) * 2 - 1)
	local wp = wg and M.wiggle(a, b, wg, amp < 0 and -1 or 1) or nil
	if wp then
		pts = wp
	elseif abs(amp) > 1 then
		local nx, ny = -(b[2] - a[2]) / l, (b[1] - a[1]) / l
		pts = { pts[1], { (a[1] + b[1]) / 2 + nx * amp, (a[2] + b[2]) / 2 + ny * amp }, pts[2] }
		pts = G.smoothLine(pts, M.LINE_RADIUS)
	end
	mp.pieces[#mp.pieces + 1] = { key = key, a = ka, b = kb, pts = pts, class = class, curved = #pts > 2,
		smooth = true }
end

--- Secondary radials in a ring cell: about one per block.len along the middle arc, but never closer than
--- ot_style.MIN_BLOCK along the inner (shorter) arc (lot depth, HANDOFF "Phase 2 preview issues").
function M.stripCount(innerLen, outerLen, blockLen)
	local arcMid = (innerLen + outerLen) / 2
	local m = G.clamp(floor(arcMid / blockLen + 0.5) - 1, 0, 8)
	local cap = floor(math.min(innerLen, outerLen) / style_.MIN_BLOCK) - 1
	return G.clamp(math.min(m, cap), 0, 8)
end

--- Cross lanes across a gap of `gap` metres: about one per block.depth, spaced at least MIN_BLOCK. The core
--- cell (inside the first ring) places its lanes over 65 % of the gap, hence the tighter cap there.
function M.laneCount(gap, blockDepth, core)
	local n = G.clamp(floor(gap / blockDepth + 0.5) - 1, 0, 8)
	local usable = core and gap * 0.65 or gap
	local cap = floor(usable / style_.MIN_BLOCK) - (core and 0 or 1)
	return G.clamp(math.min(n, cap), 0, 8)
end

M.MAX_EXTENT = 8000    -- m: a master plan never reaches farther (hang guard; ot_core caps at 6400)
M.MAX_RINGS = 64
-- Organic ring geometry (style.ringWobble, ot_style ORGANIC_RINGS, 2026-10-14 §56; user: "eu organic looks strange with
-- the big equal circles on the outside"): rings spaced unevenly (each RING_GAP x ringEvery beyond the last), each ring
-- crossing its spokes at its own radius (x 1 +- WOBBLE, less for gridded styles), its arcs wobbling WOBBLE_ARC x
-- ringEvery between them, the ring nearest the ring road motif's radius left out (the ring road takes its place:
-- RING_ROAD_GAP x ringEvery), the secondary radials (the stubs onto the rings) spaced irregularly and some left out.
M.RING_GAP = { 0.75, 1.3 }
M.RING_GAP_DIFF = 0.15    -- x ringEvery: two consecutive gaps differ by this at least
M.WOBBLE = 0.14
M.WOBBLE_ARC = 0.12
M.RING_MIN_GAP = 0.5      -- x ringEvery: two rings never closer on a spoke
M.RING_ROAD_GAP = 0.45
-- (tests: a table here collects { kind = "lane" | "radial" | "row", m = metres } for every pair of neighbouring parallel
-- streets the master plan lays out (lanes along both strips, secondary radials along the shorter arc, back rows off their
-- spoke), the strips' ends included; nil in game)
M.TRACE = nil
M.SR_JITTER = 0.35        -- secondary radials: at least this much of a strip's share jittered
M.SR_DROP = 0.15          -- ... and this share of them left out (a cell keeps one at least)

--- The ring road motif's radius (saved, else when first picked) of a style, or nil.
local function ringRoadR(style)
	for _, m in ipairs(style.motifs or {}) do
		if m.id == "ring_road" then
			local R = (m.ringSaved and m.ringR) or m.ringR0 or m.ringR
			if tonumber(R) then return R end
		end
	end
	return nil
end
M.ringRoadR = ringRoadR

--- Master plan. opts = { extent, terrain }.
function M.masterPlan(style, opts)
	opts = opts or {}
	local extent = opts.extent or 600
	-- (hang fix 2026-10-13: a NaN / endless extent or a ring spacing <= 1 m never loops without end)
	if not (extent > 0 and extent <= M.MAX_EXTENT) then extent = (extent and extent > M.MAX_EXTENT) and M.MAX_EXTENT or 600 end
	local terrain = opts.terrain
	local seed = style.seed or 1
	local cx, cy = style.centre[1], style.centre[2]
	local radial = style.radial or { spokes = 5, ringEvery = 250 }
	local k = max(3, radial.spokes)
	local R = radial.ringEvery
	if not (R and R > 1) then R = 250 end
	local mp = { junctions = { C = { cx, cy } }, pieces = {} }
	local spokeClass = (style.tier or 2) <= 1 and "medium" or "main"

	-- spokes
	local spokes = {}
	local jit = math.rad(style.jitter or 0)
	local armOf = {}   -- deep arms: spoke index -> true when a shape arm sits on it
	local shape = style.shape
	local deep = M.DEEP_ARMS and not style.noDeepArms and shape ~= nil and shape.arms ~= nil and (shape.id == "linear" or shape.id == "ridge"
		or shape.id == "cross" or shape.id == "fingers")
	-- (opts.yield: the driver's plan slice may end between the spokes / cells, 2026-10-13 slice budget)
	local yield = opts.yield or function() end
	for i = 1, k do
		yield()
		local theta = (style.axis or 0) + (i - 1) * 2 * math.pi / k + jit * (rng.unit(seed, "theta", i) * 2 - 1)
		spokes[i] = spoke(style, i, theta, extent + R, terrain)
		if deep then
			for _, a in ipairs(shape.arms) do
				if G.angleDiff(theta, a) < M.ARM_SPOKE_TOL then armOf[i] = true end
			end
		end
	end
	-- rings: radius r_j, crossing points on each spoke
	-- an inner ring (old town wall line) at ~0.45 R, then one every R
	local J = 0
	local radii = {}
	local wob = style.ringWobble == true
	local rr = wob and ringRoadR(style) or nil
	local prev = 0
	local n = 0
	local prevGap = nil
	while true do
		n = n + 1
		local r
		if n == 1 then
			r = max(M.INNER_RING_MIN, R * (0.45 + 0.05 * (rng.unit(seed, "ring", 0) * 2 - 1)))
		elseif wob then
			-- (uneven spacing: each ring its own gap beyond the last, never within RING_GAP_DIFF of the previous gap)
			local gap = R * (M.RING_GAP[1] + (M.RING_GAP[2] - M.RING_GAP[1]) * rng.unit(seed, "ringGap", n))
			if prevGap and abs(gap - prevGap) < M.RING_GAP_DIFF * R then
				local up = prevGap + M.RING_GAP_DIFF * R
				local down = prevGap - M.RING_GAP_DIFF * R
				if (gap >= prevGap and up <= M.RING_GAP[2] * R) or down < M.RING_GAP[1] * R then gap = up else gap = down end
			end
			if n == 2 then gap = max(gap, R * 0.9 - prev) end
			prevGap = gap
			r = prev + gap
		else
			r = (n - 1) * R * (1 + 0.15 * (rng.unit(seed, "ring", n - 1) * 2 - 1))
		end
		if not (r <= extent) or J >= M.MAX_RINGS or n > 4 * M.MAX_RINGS then break end
		prev = r
		-- (the ring road motif's circle takes the place of the ring nearest it: one ring there, not two side by side)
		if not (rr and n > 1 and abs(r - rr) < M.RING_ROAD_GAP * R) then
			J = J + 1
			radii[J] = r
		end
	end
	-- each ring's own radius per spoke (wobble; the first ring, the old wall line, stays round)
	local wAmp = wob and M.WOBBLE * (1 - 0.5 * (style.gridness or 0.5)) or 0
	local cross = {}   -- cross[i][j] = {x, y, idx}
	for i = 1, k do
		cross[i] = { [0] = { cx, cy, 2, { spokes[i][1][3], spokes[i][1][4] } } }
		local last = 0
		for j = 1, J do
			local rj = radii[j]
			if wAmp > 0 and j > 1 then
				rj = rj * (1 + wAmp * (rng.unit(seed, "ringWob", i, j) * 2 - 1))
				rj = max(rj, last + M.RING_MIN_GAP * R)
			end
			last = rj
			local x, y, idx, dx, dy = atRadius(spokes[i], cx, cy, rj)
			if x == nil then break end
			cross[i][j] = { x, y, idx, { dx, dy } }
			mp.junctions["S" .. i .. ":" .. j] = { x, y }
		end
	end
	local function skey(i, j)
		if j == 0 then return "C" end
		return "S" .. i .. ":" .. j
	end

	-- spoke pieces (lines) between consecutive rings; the last runs out to the extent as a dead end
	local radials = {}
	for i = 1, k do
		yield()
		radials[i] = {}
		for j = 0, J - 1 do
			local p0, p1 = cross[i][j], cross[i][j + 1]
			if p0 and p1 then
				local pts = subPoly(spokes[i], p0[1], p0[2], p0[3], p1[1], p1[2], p1[3], p0[4], p1[4])
				if j == 0 then pts[1] = { cx, cy, pts[1][3], pts[1][4] } end
				radials[i][j] = newLine(pts, skey(i, j), skey(i, j + 1), spokeClass, "sp" .. i .. ":" .. j)
				if armOf[i] then
					radials[i][j].armSpoke = i
					if j >= M.BACK_FROM_RING then radials[i][j].armLine = "A" .. i .. ":S" end
				end
			end
		end
	end
	-- ring arcs between consecutive spokes
	local rings = {}
	for i = 1, k do
		yield()
		rings[i] = {}
		local i2 = i % k + 1
		for j = 1, J do
			if j % 2 == 0 then yield() end   -- (2026-10-21: one spoke's arcs took up to ~7 ms in one go)
			local a, b = cross[i][j], cross[i2][j]
			if a and b then
				local key = "rg" .. i .. ":" .. j
				local pts = arc(style, cx, cy, a, b, key, R * (wob and M.WOBBLE_ARC or 0.06) * (1 - (style.gridness or 0.5) * 0.5))
				rings[i][j] = newLine(pts, skey(i, j), skey(i2, j), "medium", key)
				-- (ring pieces wait for the houses, ot_select RING_LEAD_M; the old wall line inside the core is free)
				if wob and j > 1 then rings[i][j].ringArc = true end
			end
		end
	end

	-- infill
	for i = 1, k do
		local i2 = i % k + 1
		for j = 0, J - 1 do
			yield()
			local zone = style_.zone(style, j == 0 and 0 or radii[j])
			local bl, bd = zone.block.len, zone.block.depth
			local gridness = zone.gridness or 0.5
			local bend = (zone.block.depth or 40) * 0.25 * (1 - gridness)
			local tOff = gridness < 0.5 and 0.25 or 0
			local strips = {}
			if j == 0 then
				if radials[i][0] and radials[i2][0] then strips = { radials[i][0], radials[i2][0] } end
			elseif rings[i][j] and rings[i][j + 1] and radials[i][j] and radials[i2][j] then
				local inner, outer = rings[i][j], rings[i][j + 1]
				local m = M.stripCount(inner.len, outer.len, bl)
				strips[1] = radials[i][j]
				-- deep arms: back rows beside arm spokes (L: left of spoke i, R: right of spoke i2), as many as fit
				local Lr, Rr = {}, {}
				if deep and (armOf[i] or armOf[i2]) and j >= M.BACK_FROM_RING then
					-- (rows at least MIN_BLOCK apart: MED hill's 30 m block depth made one-row blocks; the arm's band
					-- stays as wide as BACK_ROWS rows of the style's depth, so wider rows mean fewer of them, not a
					-- wider cut into the land beside the arm: deep towns' groves)
					local u = max(style_.MIN_BLOCK, M.BACK_OFFSET * bd)
					local uMax = max(u, M.BACK_ROWS * M.BACK_OFFSET * bd)
					for side = 1, 2 do
						local sp = side == 1 and i or i2
						if armOf[sp] then
							local list = side == 1 and Lr or Rr
							for lv = 1, M.BACK_ROWS do
								if lv * u > uMax + 1e-6 then break end
								local fi = backFraction(inner, spokes[sp], lv * u, side == 2, cx, cy)
								local fo = fi and backFraction(outer, spokes[sp], lv * u, side == 2, cx, cy)
								if not (fi and fo) then break end
								list[lv] = { fi = fi, fo = fo, d = lv * u }
								if M.TRACE then M.TRACE[#M.TRACE + 1] = { kind = "row", m = u } end
							end
						end
					end
					-- the innermost rows of both sides at least MIN_BLOCK apart on both rings
					local function room()
						local l, r = Lr[#Lr], Rr[#Rr]
						return ((r and r.fi or 1) - (l and l.fi or 0)) * inner.len >= style_.MIN_BLOCK
							and ((r and r.fo or 1) - (l and l.fo or 0)) * outer.len >= style_.MIN_BLOCK
					end
					while (#Lr > 0 or #Rr > 0) and not room() do
						if #Lr >= #Rr then Lr[#Lr] = nil else Rr[#Rr] = nil end
					end
				end
				local function addBack(row, lv, sp, sigma, tag)
					local ka, kb = tap(mp, inner, row.fi), tap(mp, outer, row.fo)
					local a, b = mp.junctions[ka], mp.junctions[kb]
					if ka == kb or G.dist(a[1], a[2], b[1], b[2]) <= MIN_GAP then return end
					local pts, curved = backPts(spokes[sp], sigma, row.d, a, b, cx, cy)
					local line = newLine(pts, ka, kb, "small", "bk" .. i .. ":" .. j .. ":" .. tag .. lv)
					line.curved, line.armSpoke, line.armLine = curved, sp, "A" .. sp .. ":" .. tag .. lv
					strips[#strips + 1] = line
				end
				for lv, row in ipairs(Lr) do addBack(row, lv, i, 1, "L") end
				local minGap = math.max(style_.MIN_BLOCK, 0.5 * M.BACK_OFFSET * bd)
				local lIn, lOut = Lr[#Lr] and Lr[#Lr].fi, Lr[#Lr] and Lr[#Lr].fo
				local rIn, rOut = Rr[#Rr] and Rr[#Rr].fi, Rr[#Rr] and Rr[#Rr].fo
				-- (the jitter never brings two secondary radials, or one and the cell's spokes, closer than MIN_BLOCK
				-- on the shorter arc: stripCount caps only the mean spacing. A jittered radial is shifted into
				-- [previous kept + fMin, 1 - (radials left + 1) x fMin], so the count stays; stripCount's cap,
				-- (m + 1) x MIN_BLOCK <= the shorter arc, keeps that range open)
				local fMin = style_.MIN_BLOCK / max(1, math.min(inner.len, outer.len))
				local fPrev = 0
				for s = 1, m do
					local jit = 0.6 * (1 - gridness)
					if wob then jit = max(jit, M.SR_JITTER) end
					local f = (s + jit * (rng.unit(seed, "sub", i, j, s) - 0.5)) / (m + 1)
					f = math.min(max(f, fPrev + fMin), 1 - (m - s + 1) * fMin)
					local fits = f >= fPrev + fMin - 1e-9 and f <= 1 - fMin + 1e-9
					-- (organic rings: some secondary radials left out, so the stubs onto the rings are not evenly spaced)
					local drop = wob and m >= 2 and rng.unit(seed, "srDrop", i, j, s) < M.SR_DROP
					-- (secondary radials too close to a back row are left out: the rows replace them)
					local clear = (lIn == nil or ((f - lIn) * inner.len >= minGap and (f - lOut) * outer.len >= minGap))
						and (rIn == nil or ((rIn - f) * inner.len >= minGap and (rOut - f) * outer.len >= minGap))
					local ka, kb
					if clear and not drop and fits then
						ka, kb = tap(mp, inner, f), tap(mp, outer, f)
						if M.TRACE then
							local L = math.min(inner.len, outer.len)
							M.TRACE[#M.TRACE + 1] = { kind = "radial", m = (f - fPrev) * L }
							M.TRACE[#M.TRACE + 1] = { kind = "radialEnd", m = (1 - f) * L }
						end
						fPrev = f
					end
					local key = "sr" .. i .. ":" .. j .. ":" .. s
					local a, b = ka and mp.junctions[ka], kb and mp.junctions[kb]
					if a and b and ka ~= kb and G.dist(a[1], a[2], b[1], b[2]) > MIN_GAP then
						local pts = { { a[1], a[2] }, { b[1], b[2] } }
						local amp = bend * (rng.unit(seed, "srb", key) * 2 - 1)
						local l = G.dist(a[1], a[2], b[1], b[2])
						local wp = style.wiggle and M.wiggle(a, b, style.wiggle, amp < 0 and -1 or 1) or nil
						if wp then
							pts = wp
						elseif abs(amp) > 1 then
							local nx, ny = -(b[2] - a[2]) / l, (b[1] - a[1]) / l
							pts = { pts[1], { (a[1] + b[1]) / 2 + nx * amp, (a[2] + b[2]) / 2 + ny * amp }, pts[2] }
							pts = G.smoothLine(pts, M.LINE_RADIUS)
						end
						local line = newLine(pts, ka, kb, "small", key)
						line.curved = #pts > 2
						strips[#strips + 1] = line
					end
				end
				for lv = #Rr, 1, -1 do addBack(Rr[lv], lv, i2, -1, "R") end
				strips[#strips + 1] = radials[i2][j]
			end
			-- cross lanes between consecutive strips
			local gap = j == 0 and radii[1] or (radii[j + 1] - radii[j])
			if gap and #strips >= 2 then
				local n0 = M.laneCount(gap, bd, j == 0)
				local nArm = M.armLaneCount(gap, bl)
				for a = 1, #strips - 1 do
					yield()   -- (2026-10-21, TICKCOST round: a big cell's lanes took up to ~9 ms in one go)
					local off = ((a + i) % 2 == 0) and tOff or -tOff
					-- between an arm spoke and its rows: cross lanes about a block length apart
					local armPair = j > 0 and strips[a].armSpoke ~= nil and strips[a].armSpoke == strips[a + 1].armSpoke
					local n = armPair and nArm or n0
					-- (each lane at least MIN_BLOCK from the previous one, or the strip's start, on both strips, and from
					-- its end: the offsets and wobble below moved the first lane to ~0.55 of a block off the ring it runs
					-- along; laneCount caps only the mean spacing. A lane is shifted into [previous kept + gMin,
					-- 1 - (lanes left + 1) x gMin] on both strips, its tilt dropped when both don't fit; only a lane
					-- with no room even then (small core cells, strips shortened by a wobbled ring) is left out. gMin
					-- from the shorter of the two strips and the ring gap)
					local lenA, lenB = strips[a].len, strips[a + 1].len
					local gMin = style_.MIN_BLOCK / max(1, math.min(gap, lenA, lenB))
					local pa, pb = 0, 0
					for t = 1, n do
						local wob = (1 - gridness) * (rng.unit(seed, "cl", i, j, a, t) - 0.5)
						local g
						local tilt = (1 - gridness) * 0.35 / (n + 1) * (rng.unit(seed, "tilt", i, j, a, t) * 2 - 1)
						local keep = rng.unit(seed, "skip", i, j, a, t) >= (1 - gridness) * 0.25
						if armPair then
							-- arm strip: the lanes of all rows on one side of a spine line up (a lane meets each back
							-- street where the next row's lane leaves it: no T pairs a few metres apart); the two
							-- sides stagger by half a block in irregular styles (T's at the spine)
							local sp = strips[a].armSpoke
							local half = gridness < 0.5 and (sp == i and 0.25 or -0.25) or 0
							g = (t + half + 0.4 * (1 - gridness) * (rng.unit(seed, "acl", sp, j, t) - 0.5)) / (n + 1)
							tilt, keep = 0, true
						elseif j == 0 then
							g = 0.3 + 0.65 * (t - 0.5 + off * 0.5 + 0.6 * wob) / n
						else
							g = (t + off + 0.4 * wob) / (n + 1)
						end
						local hi = 1 - (n - t + 1) * gMin
						local lo, up = max(pa + tilt, pb - tilt) + gMin, hi - abs(tilt)
						if lo > up + 1e-9 then tilt, lo, up = 0, max(pa, pb) + gMin, hi end
						if lo > up + 1e-9 then keep = false else g = math.min(max(g, lo), up) end
						-- irregular cores: lanes start a little apart on each side and some are missing
						if keep then
							if M.TRACE then
								local T_ = M.TRACE
								T_[#T_ + 1] = { kind = "lane", m = (g - tilt - pa) * lenA }
								T_[#T_ + 1] = { kind = "lane", m = (g + tilt - pb) * lenB }
								T_[#T_ + 1] = { kind = "laneEnd", m = (1 - g + tilt) * lenA }
								T_[#T_ + 1] = { kind = "laneEnd", m = (1 - g - tilt) * lenB }
							end
							pa, pb = g - tilt, g + tilt
							local ka, kb = tap(mp, strips[a], g - tilt), tap(mp, strips[a + 1], g + tilt)
							lane(mp, ka, kb, "small", "ln" .. i .. ":" .. j .. ":" .. a .. ":" .. t, bend, seed, style.wiggle)
						end
					end
				end
			end
			for s = 2, #strips - 1 do
				if s % 4 == 0 then yield() end
				emit(mp, strips[s], strips[s].curved)
			end
		end
	end
	for i = 1, k do
		for j = 0, J - 1 do
			yield()
			if radials[i][j] then emit(mp, radials[i][j], true) end
		end
		for j = 1, J do
			yield()
			if rings[i][j] then emit(mp, rings[i][j], true) end
		end
		-- beyond the last ring: the spoke runs on as a dead end toward the next ring
		local last = cross[i][J]
		if last and J >= 0 then
			local tipR = (radii[J] or 0) + R * 0.6
			-- (a wobbled last ring may cross this spoke farther out: the tip stays beyond it)
			if wob and J > 0 then tipR = max(tipR, G.dist(cx, cy, last[1], last[2]) + R * 0.4) end
			local tipX, tipY, tipIdx, tdx, tdy = atRadius(spokes[i], cx, cy, tipR)
			if tipX then
				local key = "tip" .. i
				mp.junctions[key] = { tipX, tipY }
				local pts = subPoly(spokes[i], last[1], last[2], last[3], tipX, tipY, tipIdx, last[4],
					{ tdx, tdy })
				if J == 0 then pts[1] = { cx, cy, pts[1][3], pts[1][4] } end
				mp.pieces[#mp.pieces + 1] = { key = key, a = skey(i, J), b = key, pts = pts, class = spokeClass,
					curved = true, smooth = true, armLine = (armOf[i] and J >= M.BACK_FROM_RING) and ("A" .. i .. ":S") or nil }
			end
		end
	end
	-- arm pieces: the lines and every piece between two junctions of one arm's lines (its cross lanes, the ring
	-- arcs across the strip); ot_select gives them the strip distance
	-- (armOuter: such a piece off the spine, between two back streets)
	local armAt, spineAt = {}, {}
	for _, pc in ipairs(mp.pieces) do
		if pc.armLine then
			mp.hasArmLines = true
			local sp = pc.armLine:match("^(A%d+):")
			armAt[pc.a], armAt[pc.b] = sp, sp
			if pc.armLine:sub(-2) == ":S" then spineAt[pc.a], spineAt[pc.b] = true, true end
		end
	end
	mp.armJunction = armAt
	for _, pc in ipairs(mp.pieces) do
		if pc.armLine or (armAt[pc.a] and armAt[pc.a] == armAt[pc.b]) then
			pc.armPiece = armAt[pc.a]
			if not pc.armLine and not spineAt[pc.a] and not spineAt[pc.b] then pc.armOuter = true end
		end
	end
	return mp
end

--- Extent the master plan must cover for the current graph.
function M.extentFor(g, style)
	local cx, cy = style.centre[1], style.centre[2]
	local r = (#g.nodes > 0) and OG.radius(g, cx, cy, 1.0) or 0
	local R = style.radial and style.radial.ringEvery or 250
	return r + R * (1 + (style.lead or 1) * 0.5)
end

--- Master plan for the town. opts = { terrain, extent }.
function M.planFor(g, style, opts)
	opts = opts or {}
	return M.masterPlan(style, { extent = opts.extent or M.extentFor(g, style), terrain = opts.terrain, yield = opts.yield })
end

--- Plans the next organic increment. opts as ot_grow_grid.grow. Returns streets, master plan, select report.
function M.grow(g, style, opts)
	opts = opts or {}
	local mp = opts.mp or M.planFor(g, style, opts)
	local streets, report = S.select(g, mp, style, opts)
	return streets, mp, report
end

return M
