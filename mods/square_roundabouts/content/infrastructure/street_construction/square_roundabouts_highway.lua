-- Better Roundabouts: pure geometry of the "Highway Interchange" (no api.*), INTERCHANGES.md
-- Phase 7b. A highway (two one-way carriageways, base templates) crossed by a two-way road on the
-- other level, joined by one-way ramps in up to four quadrants: the Diamond and the partial
-- cloverleaf ("parclo") types A4, B4, A2, B2, AB2 (section 1 of the plan). Every node is freed:
-- once built, it is ordinary editable roads. Same output format as the other entries
-- (square_roundabouts_result.lua maps it).
--
-- Frame (as square_roundabouts_interchange.lua): highway along x, cross road along y (x = 0), z up.
-- Right-hand traffic: eastbound carriageway "s" (y < 0), westbound "n". Quadrants SW, SE (beside
-- the eastbound carriageway), NE, NW. One canonical builder per ramp shape, for the SW quadrant:
--   "off": a diagonal off-ramp (ramps.gore + ramps.slipEdges, the Roundabout Interchange's slip
--          road) from the eastbound carriageway up to the outer terminal T_o;
--   "A":   a loop on-ramp (ramps.loop) from the inner terminal T_i down to the eastbound
--          carriageway before the cross road, plus a diagonal off-ramp that wraps around the loop
--          (concentric, TERM_GAP outside it) to T_o.
-- The other quadrants are exact images: NE = SW rotated 180 deg (eastbound <-> westbound), SE =
-- SW mirrored in x with every edge reversed (an off-ramp becomes an on-ramp, a loop on a loop
-- off; "on" = mirror-reverse(off), "B" = mirror-reverse(A)), NW = SE rotated.
-- Left-hand traffic: the whole right-hand build mirrored in x (geom.mirrorX), as the other entries.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local ramps = ug_require(DIR .. "square_roundabouts_ramps.lua")
local S = geom.shapes

local hx = {}

local PI = math.pi
local HALF_PI = PI / 2

-- Type param (append-only; INTERCHANGES.md section 2).
hx.TYPE_A4 = 1
hx.TYPE_B4 = 2
hx.TYPE_A2 = 3
hx.TYPE_B2 = 4
hx.TYPE_AB2 = 5
hx.TYPE_DIAMOND = 6
-- Quadrant kinds per type: SW / NE take "off" or "A", SE / NW "on" or "B"; missing = empty.
hx.TYPES = {
	{ name = "A4", quads = { sw = "A", se = "on", ne = "A", nw = "on" } },
	{ name = "B4", quads = { sw = "off", se = "B", ne = "off", nw = "B" } },
	{ name = "A2", quads = { sw = "A", ne = "A" } },
	{ name = "B2", quads = { se = "B", nw = "B" } },
	{ name = "AB2", quads = { sw = "A", nw = "B" } },
	{ name = "Diamond", quads = { sw = "off", se = "on", ne = "off", nw = "on" } },
}
hx.QUADS = { "sw", "se", "ne", "nw" }
-- the canonical (SW) shape of each kind; SE / NW are mirror-reversed, NE / NW rotated
hx.CANONICAL = { off = "off", on = "off", A = "A", B = "A" }
hx.MIRRORED = { sw = false, se = true, ne = false, nw = true }
hx.ROTATED = { sw = false, se = false, ne = true, nw = true }

hx.LEVEL_ROAD_OVER = 1
hx.LEVEL_HIGHWAY_OVER = 2

-- Scale (Phase 7c2: a button row Small / Medium / Large, as the base interchanges; a minimum, grows if
-- the layout does not fit, hx.plan): parclo loop centreline radius (25 m = the base cloverleaf's
-- tightest loop, INTERCHANGES.md research table); diamond: distance of the terminals beyond the
-- closest point a ramp may meet the cross road (Small = the tight urban diamond, terminal at the
-- cross road bridge's end). Small = 7c's Compact, Medium = 7c's Large, Large beyond 7c's Very large
-- (60 m loops, 50 m terminals): not yet engine-probed (INTERCHANGES.md "Phase 7c2 notes").
hx.LOOP_RADII = { 25, 45, 80 }
hx.GROW_RADII = { 90, 100 }
hx.TERMINAL_DISTANCES = { 0, 40, 100 }
hx.GROW_DISTANCES = { 110, 120 }
hx.DEFAULT_SIZE = 1
-- Phase 7c3 (user: "Scale often makes no visible difference"): every Scale value also scales the
-- footprint by about 1 / 1.6 / 2.5 (hx.SCALES), so the three differ clearly for every type, highway
-- and level: the terminal gap / loop-to-diagonal gap (hx.TERM_GAPS) and the shortest ramp (parclo: at
-- least SCALES x the Small layout's xmMin; diamond: hx.DIAMOND_RAMP_MINS). A layout that grows beyond
-- Large keeps Large's. The gore run stays ramps.GORE_RUN: a longer gore (tried 48 / 75 m) makes the
-- ramp / carriageway junction stretch longer than the 40 m the overlap check (GORE_MAX) allows.
hx.SCALES = { 1, 1.6, 2.5 }
hx.TERM_GAPS = { 30, 48, 75 }
hx.DIAMOND_RAMP_MINS = { 120, 192, 300 }
-- Ramp length (Phase 7c, buttons since 7c2: Short / Medium / Long): extra length over the type's
-- shortest ramp. The ramp length (xm) runs along the highway from the cross road axis to the
-- diagonal ramps' carriageway node. Shortest = the layout minimum xmMin for parclos (the diagonal
-- wrapped around the loop: 155-370 m, by loop radius, highway and cross road), DIAMOND_RAMP_MIN for
-- the diamond (its geometric minimum is far too steep). Still grows in RAMP_GROW_STEP steps if the
-- layout does not fit (gradients).
hx.RAMP_EXTRAS = { 0, 30, 60 }
hx.DEFAULT_RAMP_LENGTH = 1
hx.DIAMOND_RAMP_MIN = 120 -- = DIAMOND_RAMP_MINS[1]
hx.RAMP_GROW_STEP = 10
hx.RAMP_GROW_MAX = 400
-- Arm length (buttons since 7c2): the cross road beyond the outer terminals, the highway beyond the
-- outermost gores.
hx.ARM_LENGTHS = { 30, 45, 60 }
hx.DEFAULT_ARM_LENGTH = 1
hx.DEFAULT_CROSS = 2 -- Town, medium
-- Centreline gap between the inner (loop) and outer (diagonal) terminal on one side of the cross
-- road; also the gap between a loop and the diagonal wrapped around it (concentric). 30 m keeps
-- the cross road between the two junctions 21 m free (ramp half width 4.5 m at each end) and
-- the two ramps' kerbs 21 m apart. First guess (INTERCHANGES.md section 3); dev override hxTermGap.
hx.TERM_GAP = 30
-- "Highway over road": the plain carriageway piece between a loop's carriageway node and the
-- highway bridge's end, per highway (ramps.HIGHWAYS index). Engine-tuned (probe p7_hx_all,
-- INTERCHANGES.md "Phase 7e notes"): the large highway was refused with 10.5 m (every parclo with
-- 25 / 35 m loops) and placed with 17.5 m (45 m loops); small and medium placed with 10 m
-- (= geom.MIN_EDGE). 17.5 m makes the 25 / 35 m loops' carriageway, gore and bridge end the 45 m
-- loop's placed layout.
hx.BRIDGE_PIECE = { 10, 10, 17.5 }
-- Reach: no edge point further than this from the construction's origin (plan, m). Engine-measured
-- (probe p7_hx_scale, INTERCHANGES.md "Phase 7e2 notes"): every one of the 190 refused Scale Large
-- parclos reached |x| >= 486.25 m (highway end = outermost gore + Arm length), every placed one
-- <= 481.25 m ("Highway over road" placed up to 462.5 m); no other edge measure (length, gradient,
-- y reach) separated them. Per level (hx.LEVEL_ROAD_OVER, "Highway over road") the largest reach
-- that placed, so every placed build stays byte-identical (the limit for "Highway over road" lies
-- in 462.5-486.25 m, unmeasured). hx.rampStart caps the ramp length (Ramp length / Scale then build
-- the cap: Scale Large with Long ramps or 60 m arms, large highway over road), hx.fits rejects a
-- longer layout.
hx.MAX_REACH = { 481.25, 462.5 }
-- Ramp gradient limits (PHASE5.md 5a, from the base interchanges): average and steepest sample.
hx.AVG_MAX = 0.10
hx.PEAK_MAX = 0.15

local K = geom.PARAM_KEYS
-- Phase 7c2: one menu entry per type (square_roundabouts_highway_<type>.con.lua), the type fixed by
-- the entry (updateScript params = captureParams.type, hx.specFor); `type` is no menu param any more,
-- only the probe and the tests pass it. Scale, Ramp length and Arm length are button rows with new
-- values, so they have new keys (7c's sqrb_hx_size / sqrb_hx_ramp_length / sqrb_ix_arm_length
-- meant other values; nothing was released).
hx.PARAM_KEYS = {
	type = "sqrb_hx_type",
	highway = "sqrb_ix_highway",     -- shared with the Roundabout Interchange (same values)
	level = "sqrb_hx_level",
	cross = "sqrb_ix_cross",         -- shared (the six arm roads)
	size = "sqrb_hx_scale",
	rampLength = "sqrb_hx_ramp",
	armLength = "sqrb_hx_arm_length",
	direction = K.direction,         -- shared (1 right-hand, 2 left-hand traffic)
}

function hx.readParams(params)
	params = params or {}
	local k = hx.PARAM_KEYS
	local index = geom.index
	return {
		type = index(params[k.type], #hx.TYPES, hx.TYPE_A4),
		highway = index(params[k.highway], #ramps.HIGHWAYS, ramps.DEFAULT_HIGHWAY),
		level = index(params[k.level], 2, hx.LEVEL_ROAD_OVER),
		cross = index(params[k.cross], #geom.ARM_TEMPLATES, hx.DEFAULT_CROSS),
		size = index(params[k.size], #hx.LOOP_RADII, hx.DEFAULT_SIZE),
		rampLength = index(params[k.rampLength], #hx.RAMP_EXTRAS, hx.DEFAULT_RAMP_LENGTH),
		armLength = index(params[k.armLength], #hx.ARM_LENGTHS, hx.DEFAULT_ARM_LENGTH),
		direction = index(params[k.direction], 2, geom.DIRECTION_CCW),
		-- the current year (bridge type); may be missing
		year = tonumber(params.year),
		-- dev overrides (geom.readDev, DEV-ONLY probe): hxClear, hxGoreRun, hxTermGap, hxLoopRadius
		dev = geom.readDev(params),
	}
end

-- Phase 7c3: the menu's "Layout" button row (A / B, A / B / AB) on the two parclo entries; its
-- index picks one of the entry's captureParams.types. Not in PARAM_KEYS (no probe axis: the probe
-- and the tests pass the type itself, sqrb_hx_type).
hx.LAYOUT_KEY = "sqrb_hx_layout"

--- The spec of one menu entry's updateFn call: readParams, with the type fixed by the entry's
-- updateScript params: captureParams.types (Phase 7c3, hx.TYPE_* list) picked by the Layout button
-- (hx.LAYOUT_KEY); without that key params' own type key when it is one of the entry's types (the
-- DEV probe), else the first. captureParams.type (7c2) fixes one type. Without captureParams (tests,
-- goldens) params' own type key.
function hx.specFor(captureParams, params)
	local spec = hx.readParams(params)
	local cp = captureParams or {}
	local types = cp.types
	if types == nil and cp.type ~= nil then types = { cp.type } end
	if type(types) ~= "table" or #types == 0 then return spec end
	local t
	local li = params and params[hx.LAYOUT_KEY]
	if li ~= nil then
		t = types[geom.index(li, #types, 1)]
	elseif params and params[hx.PARAM_KEYS.type] ~= nil then
		for _, x in ipairs(types) do if x == spec.type then t = x end end
	end
	spec.type = geom.index(t or types[1], #hx.TYPES, hx.TYPE_A4)
	return spec
end

--- A tunable of a spec: the module constant, or the DEV-ONLY probe's override (geom.readDev).
local function tuned(spec, name, default)
	local v = spec and spec.dev and spec.dev[name]
	if v then return v end
	return default
end

function hx.hasLoops(spec) return spec.type ~= hx.TYPE_DIAMOND end

--- Cross-section numbers: ramps.frame plus hwX (cross road half width), yg (|y| of a gore's G:
-- the ramp band GORE_GAP clear of its carriageway), goreRun / run (ramps.gore's run), xCross
-- (|x| the highway keeps clear of the cross road: its band + clear, rounded up = the highway
-- bridge half for "Highway over road", ramps.highwayBridgeHalf), bridgePiece (hx.BRIDGE_PIECE).
-- scale: the Scale index whose terminal gap / shortest ramp apply (default spec.size).
function hx.frame(spec, scale)
	scale = scale or spec.size
	local f = ramps.frame(spec.highway, tuned(spec, "hxClear", ramps.CLEAR))
	f.scale = scale
	f.hwX = geom.ARM_HALF_WIDTH[spec.cross]
	f.yg = f.corr + f.hwRamp + ramps.GORE_GAP
	f.goreRun = tuned(spec, "hxGoreRun", ramps.GORE_RUN)
	f.run = math.max(f.goreRun, ramps.GORE_SLOPE * (f.hwH + f.hwRamp + ramps.GORE_GAP - ramps.MERGE_OFFSET))
	f.xCross = math.ceil(f.hwX + f.clear)
	f.bridgePiece = math.max(geom.MIN_EDGE, hx.BRIDGE_PIECE[spec.highway])
	return f
end

--- Layout numbers for one size value (loop radius / terminal distance) and ramp length (no fit
-- check). Parclo (right-hand frame, SW quadrant; the rest by symmetry):
--   R, Ro = R + TERM_GAP: loop / wrapped diagonal centreline radii around one centre (-dx, -(yg + R));
--   dx: the loop's stub length = |x| of the loop centre: the loop band keeps `clear` from the cross
--       road band, its merge node (dx - run) stays clear of the cross road (and of the highway
--       bridge plus f.bridgePiece, hx.BRIDGE_PIECE, for "Highway over road");
--   yTi = yg + 2R, yTo = yTi + TERM_GAP: inner / outer terminal |y|;
--   xm: diagonal ramps' carriageway node |x| = rampLength (hx.rampStart), at least xmMin (the wrapped diagonal's
--       gore, then a quarter turn of radius R, then the concentric arc), never in (xmMin, xmMin + MIN_EDGE).
-- Diamond: yTo = yClear + hwRamp + distance (the ramp band clears the highway by `clear` there);
--   the cross road bridge ends at yClear, or at the terminal when that would leave an edge under MIN_EDGE.
-- yb: the cross road bridge's half length ("Road over highway").
function hx.layout(spec, f, size, rampLength)
	local over = spec.level == hx.LEVEL_ROAD_OVER
	local lay = { f = f, spec = spec, size = size, over = over }
	if hx.hasLoops(spec) then
		local R = size
		local gap = tuned(spec, "hxTermGap", hx.TERM_GAPS[f.scale])
		lay.R, lay.Ro, lay.termGap = R, R + gap, gap
		lay.dx = math.ceil(math.max(geom.MIN_EDGE, R + f.hwRamp + f.hwX + f.clear,
			f.run + f.xCross + (over and 0 or f.bridgePiece)))
		lay.yTi = f.yg + 2 * R
		lay.yTo = lay.yTi + gap
		lay.yb = f.yClear
		lay.xmMin = lay.dx + lay.Ro + R + f.run
		local xm = math.max(rampLength, lay.xmMin)
		if xm > lay.xmMin and xm < lay.xmMin + geom.MIN_EDGE then xm = lay.xmMin + geom.MIN_EDGE end
		lay.xm = xm
	else
		lay.yTo = f.yClear + f.hwRamp + size
		lay.yb = (lay.yTo - f.yClear < geom.MIN_EDGE) and lay.yTo or f.yClear
		lay.xmMin = f.xCross + geom.MIN_EDGE + f.run
		lay.xm = math.max(rampLength, lay.xmMin)
	end
	lay.rampLength = rampLength
	return lay
end

local function tagged(e, part, kind)
	e.part, e.kind = part, kind
	return e
end

--- The canonical SW quadrant of kind "off" or "A" (right-hand frame) at highway height zHw and
-- cross road height zX. Returns {edges = {...}, gores = {{x, tag}}}: ramp edges in driving order
-- per ramp (.ramp "d" diagonal / "l" loop, .part, .io "in" off / "out" on), the carriageway nodes
-- their gores join. Symbolic tags: "TO" / "TI" (outer / inner terminal), "GD" / "GL" (the
-- diagonal's / loop's carriageway node); hx.build renames them per quadrant.
function hx.quadrant(lay, kind, zHw, zX)
	local f = lay.f
	local out, gores = {}, {}
	local function add(edges, ramp, io)
		for _, e in ipairs(edges) do
			e.ramp, e.io = ramp, io
			out[#out + 1] = e
		end
	end
	if kind == "off" then
		local gore = ramps.gore(f, "s", "in", lay.xm, f.goreRun, "", zHw)
		gore.tag = "GD"
		local edges = ramps.slipEdges(gore, { 0, -lay.yTo, zX }, { 1, 0, 0 }, "TO")
		add(edges, "d", "in")
		gores[1] = { x = gore.m[1], tag = "GD" }
		return { edges = out, gores = gores }
	end
	-- "A": wrapped diagonal off-ramp, then the loop on-ramp (driving order along the carriageway)
	local R, Ro, dx = lay.R, lay.Ro, lay.dx
	local yc = -(f.yg + R)              -- y of the loop's centre (and of the wrapped arc's)
	local dg = ramps.gore(f, "s", "in", lay.xm, f.goreRun, "", zHw)
	dg.tag = "GD"
	local diag = { ramps.goreEdge(dg) }
	local xw = -dx - Ro - R             -- the quarter turn's start (x)
	local start = dg.g
	if xw - dg.g[1] > 1e-9 then
		-- level, GORE_GAP beside the carriageway band, until the turn
		local w = { xw, dg.g[2], zHw }
		diag[#diag + 1] = tagged(S.straightEdge(dg.g, w), "level")
		start = w
	end
	local climb = {}
	-- quarter turn right (east -> south), radius R, centre (xw, yc): to W = (xw + R, yc)
	local w = { xw + R, yc, 0 }
	for _, e in ipairs(ramps.arcEdges({ xw, yc, 0 }, R, HALF_PI, -HALF_PI, start, w)) do climb[#climb + 1] = e end
	-- concentric arc around the loop, radius Ro, turning left (south -> east): to B = (-dx, -yTo)
	local b = { -dx, -lay.yTo, 0 }
	for _, e in ipairs(ramps.arcEdges({ -dx, yc, 0 }, Ro, PI, HALF_PI, w, b)) do climb[#climb + 1] = e end
	-- straight east to the outer terminal
	climb[#climb + 1] = S.straightEdge(b, { 0, -lay.yTo, 0 }, nil, "TO")
	ramps.profile(climb, zHw, zX)
	for _, e in ipairs(climb) do diag[#diag + 1] = tagged(e, "climb") end
	add(diag, "d", "in")
	gores[1] = { x = dg.m[1], tag = "GD" }

	local lg = ramps.gore(f, "s", "out", -(dx - f.run), f.goreRun, "", zHw)
	lg.tag = "GL"
	add(ramps.loop(lg, R, "TI", zX), "l", "out")
	gores[2] = { x = lg.m[1], tag = "GL" }
	return { edges = out, gores = gores }
end

local function copy(p) return { p[1], p[2], p[3] } end

--- Quadrant q's edges and gore nodes from the canonical SW quadrant c: mirrored (x -> -x, every
-- edge reversed, io swapped) for SE / NW, rotated 180 deg for NE / NW; symbolic tags renamed.
function hx.place(c, q)
	local side = hx.ROTATED[q] and "n" or "s"
	local function name(tag)
		if tag == "TO" then return "sqrb_hx_x" .. side .. "_o" end
		if tag == "TI" then return "sqrb_hx_x" .. side .. "_i" end
		if tag == "GD" then return "sqrb_hx_" .. q .. "_d" end
		if tag == "GL" then return "sqrb_hx_" .. q .. "_l" end
		return tag
	end
	local mx = hx.MIRRORED[q] and -1 or 1
	local rs = hx.ROTATED[q] and -1 or 1
	local function pt(p) return { rs * mx * p[1], rs * p[2], p[3] } end
	local out = {}
	local src = c.edges
	local n = #src
	for i = 1, n do
		local e = hx.MIRRORED[q] and src[n + 1 - i] or src[i]
		local o
		if hx.MIRRORED[q] then
			-- reversed: p0 <- p1, t0 <- -t1 (mirrored)
			local t0, t1 = pt(e.t1), pt(e.t0)
			o = { p0 = pt(e.p1), t0 = { -t0[1], -t0[2], -t0[3] }, p1 = pt(e.p0), t1 = { -t1[1], -t1[2], -t1[3] },
				tag0 = name(e.tag1), tag1 = name(e.tag0), io = e.io == "in" and "out" or "in" }
		else
			o = { p0 = pt(e.p0), t0 = pt(e.t0), p1 = pt(e.p1), t1 = pt(e.t1), tag0 = name(e.tag0), tag1 = name(e.tag1), io = e.io }
		end
		o.part, o.kind, o.quad, o.cw = e.part, e.ramp, q, side
		o.ramp = q .. "_" .. e.ramp
		out[i] = o
	end
	local gores = {}
	for i, g in ipairs(c.gores) do gores[i] = { x = rs * mx * g.x, tag = name(g.tag), cw = side } end
	return out, gores
end

--- Plan-level fit of a layout: every climb within AVG_MAX / PEAK_MAX, every ramp edge at least
-- MIN_EDGE, the gores of a quadrant apart and clear of the cross road (and the highway bridge),
-- JUNCTION_PLAN free on the cross road between junctions and on the ramps' terminal edges, the
-- wrapped diagonal LEG_CLEARANCE clear of its loop. Returns ok, reason.
function hx.fits(lay)
	local f, spec = lay.f, lay.spec
	local kinds = {}
	for _, kind in pairs(hx.TYPES[spec.type].quads) do kinds[hx.CANONICAL[kind]] = true end
	local minGoreX = lay.over and geom.MIN_EDGE / 2 or f.xCross + f.bridgePiece
	for kind in pairs(kinds) do
		local c = hx.quadrant(lay, kind, 0, ramps.HEIGHT)
		local chains = {}
		for _, e in ipairs(c.edges) do
			if S.dist(e.p0, e.p1) < geom.MIN_EDGE - 1e-9 then return false, "short ramp edge" end
			if e.part ~= "gore" and e.part ~= "level" then
				chains[e.ramp] = chains[e.ramp] or {}
				local ch = chains[e.ramp]
				ch[#ch + 1] = e
			end
			-- terminal edges keep JUNCTION_PLAN beyond the cross road's band
			if (e.tag0 == "TO" or e.tag0 == "TI" or e.tag1 == "TO" or e.tag1 == "TI")
				and S.dist(e.p0, e.p1) - f.hwX < geom.JUNCTION_PLAN then return false, "terminal edge" end
		end
		for _, ch in pairs(chains) do
			local _, avg, peak = ramps.gradient(ch)
			if avg > hx.AVG_MAX or peak > hx.PEAK_MAX then return false, "gradient" end
		end
		-- gores (m .. g spans along x) of the quadrant: apart by MIN_EDGE, the innermost clear
		local spans = {}
		for _, e in ipairs(c.edges) do
			if e.part == "gore" then
				spans[#spans + 1] = { math.min(e.p0[1], e.p1[1]), math.max(e.p0[1], e.p1[1]) }
			end
		end
		table.sort(spans, function(a, b) return a[1] < b[1] end)
		for i = 2, #spans do
			if spans[i][1] - spans[i - 1][2] < geom.MIN_EDGE then return false, "gores overlap" end
		end
		for _, g in ipairs(c.gores) do
			if math.abs(g.x) < minGoreX - 1e-9 then return false, "gore near the cross road" end
		end
	end
	-- cross road between junctions (perpendicular ramps take hwRamp each side of a terminal)
	local ys = { { y = lay.yTo, cut = f.hwRamp } }
	if lay.yTi then ys[#ys + 1] = { y = lay.yTi, cut = f.hwRamp } end
	if lay.over and lay.yb < lay.yTo - 1e-9 then ys[#ys + 1] = { y = lay.yb, cut = 0 } end
	table.sort(ys, function(a, b) return a.y < b.y end)
	for i = 2, #ys do
		if ys[i].y - ys[i - 1].y - ys[i].cut - ys[i - 1].cut < geom.JUNCTION_PLAN then return false, "terminals" end
	end
	if lay.Ro and lay.Ro - lay.R - 2 * f.hwRamp < geom.LEG_CLEARANCE then return false, "loop clearance" end
	if hx.reach(lay) > hx.MAX_REACH[spec.level] + 1e-9 then return false, "reach" end
	return true
end

--- The plan distance from the origin to the furthest edge point: the highway ends (outermost gore
-- xm + Arm length) or the cross road arms' ends (yTo + Arm length). Phase 7e2: <= hx.MAX_REACH[level].
function hx.reach(lay)
	return math.max(lay.xm, lay.yTo) + hx.ARM_LENGTHS[lay.spec.armLength]
end

--- The ramp length the plan starts from for one size value: the type's shortest ramp (parclo:
-- the layout minimum xmMin; diamond: DIAMOND_RAMP_MIN) plus the slider's extra length.
-- Phase 7c3: at least hx.SCALES[f.scale] x the Small layout's (parclo) or DIAMOND_RAMP_MINS (diamond).
function hx.rampStart(spec, f, size)
	local shortest
	if hx.hasLoops(spec) then
		local small = hx.layout(spec, hx.frame(spec, 1), hx.LOOP_RADII[1], 0).xmMin
		shortest = hx.layout(spec, f, size, 0).xmMin
		if f.scale > 1 then shortest = math.max(shortest, hx.SCALES[f.scale] * small) end
	else
		shortest = hx.DIAMOND_RAMP_MINS[f.scale]
	end
	local x = shortest + hx.RAMP_EXTRAS[spec.rampLength]
	-- Phase 7e2: capped so the highway ends stay within hx.MAX_REACH (never below the layout's
	-- minimum, and never in (xmMin, xmMin + MIN_EDGE), where hx.layout would push it past the cap)
	local cap = hx.MAX_REACH[spec.level] - hx.ARM_LENGTHS[spec.armLength]
	if x > cap then
		local xmMin = hx.layout(spec, f, size, 0).xmMin
		x = math.max(cap, xmMin)
		if x > xmMin and x < xmMin + geom.MIN_EDGE then x = xmMin end
	end
	return x
end

--- The layout at the Size slider (loop radius / terminal distance) and the ramp length slider, or
-- the next sizes (slider, then GROW_*), each with the smallest ramp length from hx.rampStart up (in
-- RAMP_GROW_STEP steps) that fits. Never forced for the shipped params (tested); a forced plan is
-- flagged lay.forced.
function hx.plan(spec)
	local values, grow = hx.TERMINAL_DISTANCES, hx.GROW_DISTANCES
	if hx.hasLoops(spec) then values, grow = hx.LOOP_RADII, hx.GROW_RADII end
	-- {size value, Scale index}: the slider's, the larger ones, then GROW_* at the largest Scale
	local sizes = {}
	local devR = hx.hasLoops(spec) and tuned(spec, "hxLoopRadius", nil)
	if devR then
		sizes[1] = { devR, spec.size }
	else
		for i = spec.size, #values do sizes[#sizes + 1] = { values[i], i } end
		for _, v in ipairs(grow) do sizes[#sizes + 1] = { v, #values } end
	end
	local last
	for _, sv in ipairs(sizes) do
		local size, f = sv[1], hx.frame(spec, sv[2])
		local tried
		local start = hx.rampStart(spec, f, size)
		for x = start, math.max(start, hx.RAMP_GROW_MAX), hx.RAMP_GROW_STEP do
			local lay = hx.layout(spec, f, size, x)
			-- below the layout's own minimum every ramp length builds the same layout
			if lay.xm ~= tried then
				tried = lay.xm
				if hx.fits(lay) then return lay end
			end
			last = lay
		end
	end
	last.forced = true
	return last
end

local list = ramps.list

--- Every zero coordinate of every edge's positions and tangents becomes +0 (in place).
-- Phase 7e fix-up (INTERCHANGES.md round 13): the parclos' SE on-ramp had tangents (+x, -0, -0)
-- (built by mirroring and negating the canonical quadrant). The construction tool's transform at
-- rotation 0 is (cos, sin) = (1, -0), so the world tangent's y stayed -0 (-0 * x + -0) for that one
-- ramp only, and the engine refused the layout ("Construction Not Possible"); any other rotation, the
-- probe's +0 transform and the 180-degree twin (nw_d) gave +0. +0 everywhere removes the asymmetry.
function hx.positiveZeros(lists)
	for _, l in ipairs(lists) do
		for _, e in ipairs(l.edges) do
			for _, v in ipairs({ e.p0, e.p1, e.t0, e.t1 }) do
				for i = 1, 3 do
					if v[i] == 0 then v[i] = 0.0 end
				end
			end
		end
	end
end

--- Highway, cross road, terminals and ramps for a spec from readParams. Returns {
--   lists = {{role, template, halfWidth, edges, edgeType?, edgeTypeName?}}
--          roles "highway", "cross" (between the outer terminals), "arms" (beyond), "ramps"
--   ramps = every ramp edge, each with .ramp ("sw_d", "sw_l", ...), .quad, .kind "d" / "l",
--          .part ("gore", "level", "climb", "stub", "loop"), .io "in" / "out", .cw "s" / "n",
--   type (hx.TYPES name), size (loop radius / terminal distance, effective), R, Ro, dx, xm, xmMin, yTi, yTo,
--   yb, xb (highway bridge half, "Highway over road"), forced, bridge, zCross, zHighway, mirrored,
--   spec, frame
-- }
function hx.build(spec)
	local lay = hx.plan(spec)
	local f = lay.f
	local over = lay.over
	local zX, zHw = over and ramps.HEIGHT or 0, over and 0 or ramps.HEIGHT
	local bridgeName = ramps.bridgeType(spec.year)
	local tdef = hx.TYPES[spec.type]

	-- ramps: canonical quadrants once per kind, placed in every quadrant of the type
	local canon, rampE, goreNodes = {}, {}, { s = {}, n = {} }
	for _, q in ipairs(hx.QUADS) do
		local kind = tdef.quads[q]
		if kind then
			local ck = hx.CANONICAL[kind]
			canon[ck] = canon[ck] or hx.quadrant(lay, ck, zHw, zX)
			local edges, gores = hx.place(canon[ck], q)
			for _, e in ipairs(edges) do rampE[#rampE + 1] = e end
			for _, g in ipairs(gores) do
				local l = goreNodes[g.cw]
				l[#l + 1] = g
			end
		end
	end

	-- cross road, south to north: arm, terminals, (bridge,) terminals, arm
	local L = hx.ARM_LENGTHS[spec.armLength]
	local stops = {}
	stops[#stops + 1] = { y = lay.yTo, tag = "o" }
	if lay.yTi then stops[#stops + 1] = { y = lay.yTi, tag = "i" } end
	if over then
		if lay.yb < lay.yTo - 1e-9 then stops[#stops + 1] = { y = lay.yb, tag = "b" } else stops[1].bridgeEnd = true end
	end
	table.sort(stops, function(a, b) return a.y > b.y end) -- outermost first
	local pts = {}
	for _, s in ipairs(stops) do pts[#pts + 1] = { pos = { 0, -s.y, zX }, tag = "sqrb_hx_xs_" .. s.tag } end
	for i = #stops, 1, -1 do
		local s = stops[i]
		pts[#pts + 1] = { pos = { 0, s.y, zX }, tag = "sqrb_hx_xn_" .. s.tag }
	end
	local crossN, crossB, armE = {}, {}, {}
	local mid = #stops -- the edge between the innermost nodes crosses the highway
	for i = 1, #pts - 1 do
		local e = S.straightEdge(pts[i].pos, pts[i + 1].pos, pts[i].tag, pts[i + 1].tag)
		if i == mid and over then crossB[#crossB + 1] = e else crossN[#crossN + 1] = e end
	end
	local yEnd = lay.yTo + L
	armE[1] = S.straightEdge(pts[1].pos, { 0, -yEnd, zX }, pts[1].tag, nil)
	armE[2] = S.straightEdge(pts[#pts].pos, { 0, yEnd, zX }, pts[#pts].tag, nil)

	-- the highway bridge (highway over road): over the cross road
	local xb
	if not over then
		local lower = {}
		for _, e in ipairs(crossN) do lower[#lower + 1] = { e = e, hw = f.hwX } end
		for _, e in ipairs(armE) do lower[#lower + 1] = { e = e, hw = f.hwX } end
		xb = ramps.highwayBridgeHalf(f, lower)
	end

	-- carriageways: gore nodes, ends beyond the outermost gore, bridge ends
	local xEnd = 0
	for _, cw in ipairs({ "s", "n" }) do
		for _, g in ipairs(goreNodes[cw]) do xEnd = math.max(xEnd, math.abs(g.x)) end
	end
	local cwNodes = {}
	for _, cw in ipairs({ "s", "n" }) do
		local nodes = { { x = -xEnd - L, tag = false }, { x = xEnd + L, tag = false } }
		for _, g in ipairs(goreNodes[cw]) do nodes[#nodes + 1] = { x = g.x, tag = g.tag } end
		if xb then
			nodes[#nodes + 1] = { x = -xb, tag = "sqrb_hx_" .. cw .. "_bw", bridgeStart = true }
			nodes[#nodes + 1] = { x = xb, tag = "sqrb_hx_" .. cw .. "_be" }
		end
		table.sort(nodes, function(a, b) return a.x < b.x end)
		local xs, tags, bridged = {}, {}, {}
		for i, nd in ipairs(nodes) do
			xs[i], tags[i] = nd.x, nd.tag
			if nd.bridgeStart then bridged[i] = true end
		end
		cwNodes[cw] = { xs = xs, tags = tags, bridged = bridged }
	end
	local hwN, hwB = ramps.carriageways(f, cwNodes, zHw)

	local crossEntry = { template = geom.ARM_TEMPLATES[spec.cross] }
	local lists = {
		list("highway", f.highway, f.hwH, hwN),
		list("highway", f.highway, f.hwH, hwB, bridgeName),
		list("cross", crossEntry, f.hwX, crossN),
		list("cross", crossEntry, f.hwX, crossB, bridgeName),
		list("arms", crossEntry, f.hwX, armE),
		list("ramps", ramps.RAMP, f.hwRamp, rampE),
	}
	local kept = {}
	for _, l in ipairs(lists) do if #l.edges > 0 then kept[#kept + 1] = l end end
	local built = {
		lists = kept,
		ramps = rampE,
		type = tdef.name,
		size = lay.size,
		R = lay.R,
		Ro = lay.Ro,
		dx = lay.dx,
		xm = lay.xm,
		xmMin = lay.xmMin,
		yTi = lay.yTi,
		yTo = lay.yTo,
		yb = over and lay.yb or nil,
		xb = xb,
		forced = lay.forced,
		bridge = bridgeName,
		zCross = zX,
		zHighway = zHw,
		spec = spec,
		frame = f,
	}
	if spec.direction == geom.DIRECTION_CW then geom.mirrorX(built) end
	built.mirrored = spec.direction == geom.DIRECTION_CW
	-- after the mirror (it negates x and so makes new -0s)
	hx.positiveZeros(built.lists)
	return built
end

return hx
