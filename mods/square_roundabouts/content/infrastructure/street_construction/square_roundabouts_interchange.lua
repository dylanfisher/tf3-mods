-- Better Roundabouts: pure geometry of the "Roundabout Interchange" menu entry (no api.*).
-- A highway (two one-way carriageways, as the base interchanges) crossed by a roundabout
-- junction on another level, with four one-way slip roads that diverge from and merge into the
-- carriageways like the base diamond interchange. Layouts:
--   Two-bridge ring: one ring around the highway, crossing it on two bridges;
--   Dumbbell: a ring each side of the highway, joined by a two-way link road on a bridge;
--   Peanut: one one-way loop with a lobe each side, the waist two opposite one-way bridges.
-- Levels: the ring level over the highway (highway at grade, ring roads at HEIGHT, the parts over
-- the highway on bridges: the diamond pattern) or the highway over the ring level (highway at
-- HEIGHT, bridged over the ring roads: the diverging-diamond pattern). No tunnels (PHASE5.md
-- "Phase 5a notes", spike 4). Every node is freed: once built, it is ordinary editable roads.
-- See PHASE5.md "Phase 5d notes".
--
-- Frame: highway along x, cross road along y, z up. Built for right-hand traffic (eastbound
-- carriageway south, rings anticlockwise) and mirrored in x for left-hand traffic.
-- Same output format as square_roundabouts_geometry.build (lists, island), so
-- square_roundabouts_result.lua maps it; lists may carry edgeType / edgeTypeName (bridges).

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local ramps = ug_require(DIR .. "square_roundabouts_ramps.lua")
local S = geom.shapes

local ix = {}

local PI = math.pi
local TWO_PI = 2 * PI
local HALF_PI = PI / 2
local DEG = PI / 180
local add, sub, scale, dot, dist, dir = S.add, S.sub, S.scale, S.dot, S.dist, S.dir

ix.LAYOUT_TWO_BRIDGE = 1
ix.LAYOUT_DUMBBELL = 2
ix.LAYOUT_PEANUT = 3
ix.LEVEL_RING_OVER = 1
ix.LEVEL_HIGHWAY_OVER = 2

-- Highway frame constants, shared with the other highway entries (square_roundabouts_ramps.lua,
-- Phase 7a): the same tables, re-exported (templates, MEDIAN 4, MERGE_OFFSET 4, GORE_GAP 1,
-- GORE_RUN 30, GORE_SLOPE 2.5, HEIGHT 8, steel / concrete bridges with CONCRETE_FROM 1970, CLEAR 8).
ix.HIGHWAYS = ramps.HIGHWAYS
ix.DEFAULT_HIGHWAY = ramps.DEFAULT_HIGHWAY
ix.RAMP = ramps.RAMP
ix.MEDIAN = ramps.MEDIAN
ix.MERGE_OFFSET = ramps.MERGE_OFFSET
ix.GORE_GAP = ramps.GORE_GAP
ix.GORE_RUN = ramps.GORE_RUN
ix.GORE_SLOPE = ramps.GORE_SLOPE
ix.HEIGHT = ramps.HEIGHT
ix.BRIDGE_STEEL = ramps.BRIDGE_STEEL
ix.BRIDGE_CONCRETE = ramps.BRIDGE_CONCRETE
ix.CONCRETE_FROM = ramps.CONCRETE_FROM
ix.CLEAR = ramps.CLEAR
-- Radius slider (inside the ring road, like the main entry): a minimum. The rings grow until the
-- layout fits (ix.plan), up to GROW_RADII.
ix.RADII = { 15, 20, 25, 30, 35, 40, 45, 50, 55, 60 }
ix.DEFAULT_RADIUS = 2 -- 20 m
ix.GROW_RADII = { 70, 80, 90, 100, 110, 120 }
-- Phase 7c3: the menu's Radius is a button row of presets (as geom.RADIUS_PRESETS): Small / Medium /
-- Large / Huge = ix.RADII indices (15 / 20 / 30 / 45 m), own key ix.RADIUS_PRESET_KEY; ix.readParams
-- falls back to the full-range index key sqrb_ix_radius (tests, goldens, the DEV probe).
ix.RADIUS_PRESETS = { 1, 2, 4, 7 }
ix.RADIUS_PRESET_NAMES = { "S", "M", "L", "XL" } -- 2026-10-09: were Small / Medium / Large / Huge
ix.DEFAULT_RADIUS_PRESET = 1 -- S 15 m (2026-10-09, user: size menus default to the smallest; was 2 = M)
ix.RADIUS_PRESET_KEY = "sqrb_ix_radius_size"
-- "Arm length": the cross road beyond the ring's outer kerb and the highway beyond the outer slip
-- road nodes.
ix.ARM_LENGTHS = { 30, 40, 50, 60 }
ix.DEFAULT_ARM_LENGTH = 1
-- "Slip road length": distance along the highway between a slip road's ring node and its
-- carriageway node. The climb starts after the gore (30-33 m): 120 m leaves 87 m or more for 8 m,
-- the base diamond's steepest ramps (average 10 %, peak 15 %).
ix.SLIP_LENGTHS = { 120, 140, 160, 180 }
ix.DEFAULT_SLIP_LENGTH = 2
ix.DEFAULT_CROSS = 2 -- Town, medium
-- Two-bridge ring: the slip nodes are the bridge ends, at +-alpha from the highway axis, where the
-- ring and the slip road clear the highway by CLEAR. At most ALPHA_MAX (else the ring grows).
-- The slip roads join there parallel to the highway, 90 deg - alpha off the ring's tangent.
-- Phase 5f: the engine rejected every 4-lane two-bridge ring (p5_all: 30 of 30, alpha 52-58 deg,
-- slip roads 32-38 deg off the 4-lane ring) and accepted the 1- and 2-lane ones (36-43 deg). Like
-- the channelized junction's slip lanes on 3-lane arms (rejected at 40 deg, accepted at 50 deg),
-- a wide ring needs a steeper join: 4 lanes cap alpha (the ring grows instead). Phase 5g: p5f_all
-- placed every 4-lane two-bridge ring at 40 deg (96 of 96) and p5f_search accepted 30 / 35 / 40 /
-- 45 deg for every highway and level (6 of 6 each); 45 deg (joins >= 45 deg) keeps the ring
-- smallest: 15 m slider -> 30 / 45 / 50 m (small / medium / large highway; 40 deg: 35 / 45 / 55 m).
ix.ALPHA_MAX = 60 * DEG
ix.ALPHA_MAX_LANES = { 60 * DEG, 60 * DEG, 45 * DEG }
-- Slip roads join a ring along its inward normal turned GAMMA towards the circulation (leave along
-- the outward normal turned with it): an entry / exit at a roundabout, curving towards the
-- highway. Dumbbell and peanut: at the rings' / lobes' east and west nodes. Two-bridge: at the
-- bridge ends, gamma = alpha (the slip roads join parallel to the highway, as in the base diamond).
ix.GAMMA = 35 * DEG
-- Peanut: the two waist bridges keep at least WAIST_GAP between their kerbs at the pinch; the
-- lobes' waist nodes are at 270 +- beta (north lobe), beta the smallest from BETA_MIN that keeps
-- the gap. The waist edges leave the lobes along the circle (tangent length = chord).
ix.WAIST_GAP = 6
ix.BETA_MIN = 30 * DEG
ix.BETA_MAX = 85 * DEG
-- Ring edges keep geom.JUNCTION_PLAN outside the junctions at their ends (geom.kerbCut, the
-- shipping junction model), no kerb corner more than BEHIND_ARM behind an arm / link node or
-- BEHIND_RAMP behind a slip road's node (the engine-fitted model's 1 m / 6 m for arms / legs).
ix.BEHIND_ARM = 1.0
ix.BEHIND_RAMP = 5.8
ix.RAMP_SAMPLES = 24

local K = geom.PARAM_KEYS
ix.PARAM_KEYS = {
	layout = "sqrb_ix_layout",
	highway = "sqrb_ix_highway",
	level = "sqrb_ix_level",
	lanes = K.lanes,         -- same values and meaning as the roundabouts' Ring lanes
	radius = "sqrb_ix_radius",
	cross = "sqrb_ix_cross",
	slipLength = "sqrb_ix_slip_length",
	armLength = "sqrb_ix_arm_length",
	direction = K.direction, -- same values and meaning as the roundabouts' Direction
	island = K.island,       -- same values and meaning as the roundabouts' Centre island
}

function ix.readParams(params)
	params = params or {}
	local k = ix.PARAM_KEYS
	local index = geom.index
	local spec = {
		layout = index(params[k.layout], 3, ix.LAYOUT_TWO_BRIDGE),
		highway = index(params[k.highway], #ix.HIGHWAYS, ix.DEFAULT_HIGHWAY),
		level = index(params[k.level], 2, ix.LEVEL_RING_OVER),
		lanes = index(params[k.lanes], #geom.RING_TEMPLATES, 2),
		radiusIndex = index(params[k.radius], #ix.RADII, ix.DEFAULT_RADIUS),
		cross = index(params[k.cross], #geom.ARM_TEMPLATES, ix.DEFAULT_CROSS),
		slipLength = index(params[k.slipLength], #ix.SLIP_LENGTHS, ix.DEFAULT_SLIP_LENGTH),
		armLength = index(params[k.armLength], #ix.ARM_LENGTHS, ix.DEFAULT_ARM_LENGTH),
		direction = index(params[k.direction], 2, geom.DIRECTION_CCW),
		island = index(params[k.island], 5, geom.ISLAND_NONE),
		-- the current year (base updateFns read params.year, e.g. modules.script.lua:149); may be missing
		year = tonumber(params.year),
		-- dev overrides (geom.readDev): only ixClear, ixGamma, ixGoreRun, ixWaistGap apply here
		dev = geom.readDev(params),
	}
	if params[ix.RADIUS_PRESET_KEY] ~= nil then
		spec.radiusIndex = ix.RADIUS_PRESETS[index(params[ix.RADIUS_PRESET_KEY], #ix.RADIUS_PRESETS, ix.DEFAULT_RADIUS_PRESET)]
	end
	spec.radius = ix.RADII[spec.radiusIndex]
	return spec
end

--- Bridge type for the year (nil: concrete, as the base interchanges): ramps.bridgeType.
ix.bridgeType = ramps.bridgeType

--- A tunable of a spec: the module constant, or the DEV-ONLY probe's override (geom.readDev).
local function tuned(spec, name, default)
	local v = spec and spec.dev and spec.dev[name]
	if v then return v end
	return default
end

--- Largest alpha of the two-bridge ring's slip nodes (radians): per ring lanes, or the DEV-ONLY
-- probe's ixAlphaMax (degrees).
function ix.alphaMax(spec)
	local v = tuned(spec, "ixAlphaMax", nil)
	if v then return v * DEG end
	return ix.ALPHA_MAX_LANES[spec.lanes] or ix.ALPHA_MAX
end

--- Cross-section numbers of a spec.
-- The highway part is ramps.frame (highway, hwH, c, hwRamp, corr, clear, yClear); the ring and
-- cross road add hwR, offset, hwX.
function ix.frame(spec)
	local f = ramps.frame(spec.highway, tuned(spec, "ixClear", ix.CLEAR))
	f.hwR = geom.RING_HALF_WIDTH[spec.lanes]
	f.offset = geom.RING_OFFSET[spec.lanes]
	f.hwX = geom.ARM_HALF_WIDTH[spec.cross]
	return f
end

local function node(t, kind, slip)
	return { t = t, kind = kind, slip = slip }
end

--- Ring nodes: anchors {t, kind, slip} (any order) plus the fewest plain nodes so that no edge
-- spans more than geom.MAX_EDGE_ANGLE; ascending t from the first anchor. open: an arc from the
-- first anchor (smallest t) to the last (no closing edge).
local function fill(anchors, open)
	table.sort(anchors, function(a, b) return a.t < b.t end)
	local out = {}
	local n = #anchors
	for i, a in ipairs(anchors) do
		out[#out + 1] = a
		if i < n or not open then
			local nextT = i < n and anchors[i + 1].t or anchors[1].t + TWO_PI
			local gap = nextT - a.t
			local m = math.max(1, math.ceil(gap / geom.MAX_EDGE_ANGLE - 1e-7))
			for k = 1, m - 1 do out[#out + 1] = node(a.t + gap * k / m, "plain") end
		end
	end
	return out
end

--- Slip road directions at a ring node of parameter t (anticlockwise ring): joining (in) along the
-- inward normal turned gamma towards the circulation, leaving (out) along the outward normal
-- turned gamma with it.
function ix.slipDir(t, gamma, io)
	if io == "in" then return dir(t + PI - gamma) end
	return dir(t + gamma)
end

-- slip road ends on the carriageways (right-hand frame): south = eastbound (+x), north =
-- westbound (-x); "in" = off-ramp (carriageway -> ring), "out" = on-ramp (ring -> carriageway)
local SLIPS = {
	s_in = { cw = "s", io = "in" }, s_out = { cw = "s", io = "out" },
	n_in = { cw = "n", io = "in" }, n_out = { cw = "n", io = "out" },
}
ix.SLIPS = SLIPS

--- Ring layout for one centreline radius rc (no fit check). Returns {rings = {{centre, rc, nodes,
-- open, bridge = fn(i)}}, gamma, waist?, link?} or nil if the layout cannot exist at that radius.
function ix.layout(spec, f, rc)
	local lay = { rc = rc, f = f, spec = spec }
	local gamma = tuned(spec, "ixGamma", nil)
	gamma = gamma and gamma * DEG or ix.GAMMA
	if spec.layout == ix.LAYOUT_TWO_BRIDGE then
		local s = math.max(f.yClear / (rc - f.hwR), (f.yClear + f.hwRamp) / rc)
		if s > math.sin(ix.alphaMax(spec)) then return nil end
		local alpha = math.asin(s)
		lay.alpha, lay.gamma = alpha, alpha
		local nodes = fill({
			node(alpha, "slip", SLIPS.n_in), node(HALF_PI, "arm"), node(PI - alpha, "slip", SLIPS.n_out),
			node(PI + alpha, "slip", SLIPS.s_in), node(3 * HALF_PI, "arm"), node(TWO_PI - alpha, "slip", SLIPS.s_out),
		})
		-- the arcs over the highway (between the two slip nodes of a side) are the bridges
		local function bridge(i)
			local a, b = nodes[i].t, (nodes[i % #nodes + 1].t)
			if i == #nodes then b = b + TWO_PI end
			return math.abs(math.sin((a + b) / 2)) < s
		end
		lay.rings = { { centre = { 0, 0, 0 }, rc = rc, nodes = nodes, bridge = bridge } }
	elseif spec.layout == ix.LAYOUT_DUMBBELL then
		local D = f.yClear + f.hwR + rc
		lay.D, lay.gamma = D, gamma
		lay.rings = {
			{ centre = { 0, D, 0 }, rc = rc, nodes = fill({
				node(0, "slip", SLIPS.n_in), node(HALF_PI, "arm"), node(PI, "slip", SLIPS.n_out), node(3 * HALF_PI, "link"),
			}) },
			{ centre = { 0, -D, 0 }, rc = rc, nodes = fill({
				node(0, "slip", SLIPS.s_out), node(HALF_PI, "link"), node(PI, "slip", SLIPS.s_in), node(3 * HALF_PI, "arm"),
			}) },
		}
	else
		-- peanut: the smallest beta whose waist bridges keep WAIST_GAP at the pinch
		local yw = f.yClear + f.hwR
		local beta
		for b = ix.BETA_MIN, ix.BETA_MAX + 1e-9, DEG do
			local xw = rc * math.sin(b)
			if xw - (2 * yw) * math.cos(b) / 4 - f.hwR >= tuned(spec, "ixWaistGap", ix.WAIST_GAP) / 2 then beta = b; break end
		end
		if not beta then return nil end
		local D = yw + rc * math.cos(beta)
		lay.D, lay.beta, lay.yw, lay.gamma = D, beta, yw, gamma
		lay.rings = {
			{ centre = { 0, D, 0 }, rc = rc, open = true, nodes = fill({
				node(beta - HALF_PI, "waist"), node(0, "slip", SLIPS.n_in), node(HALF_PI, "arm"),
				node(PI, "slip", SLIPS.n_out), node(3 * HALF_PI - beta, "waist"),
			}, true) },
			{ centre = { 0, -D, 0 }, rc = rc, open = true, nodes = fill({
				node(HALF_PI + beta, "waist"), node(PI, "slip", SLIPS.s_in), node(3 * HALF_PI, "arm"),
				node(TWO_PI, "slip", SLIPS.s_out), node(5 * HALF_PI - beta, "waist"),
			}, true) },
		}
	end
	-- world positions (z later), the slip nodes' distance from the cross road axis
	lay.xSlip = 0
	for _, r in ipairs(lay.rings) do
		for _, n in ipairs(r.nodes) do
			n.pos = add(r.centre, scale(dir(n.t), rc))
			if n.slip then lay.xSlip = math.max(lay.xSlip, math.abs(n.pos[1])) end
		end
	end
	lay.xm = lay.xSlip + ix.SLIP_LENGTHS[spec.slipLength]
	return lay
end

--- Slip road edges (plan + heights) for a slip node n (world position, ring parameter n.t), in
-- driving order. Two edges:
--   gore: at the highway's height, from the carriageway node (MERGE_OFFSET beside it, same tag,
--         parallel: the base diamond's merge) out to a plain node G where the slip road's band is
--         GORE_GAP clear of the carriageway's, GORE_RUN (at least) along the highway;
--   climb: from G (parallel to the highway) up / down to the ring node, joining it along
--         ix.slipDir. It carries the whole height change, so the part of the slip road beside the
--         carriageway stays level with it (the base diamond's ramps are 1.6-3.1 m up where they
--         clear the carriageway; a single Hermite edge was up to 7.8 m up there on the peanut).
-- Returns the edges in driving order and the carriageway tag; each edge has .part "gore" / "climb".
-- (ramps.gore + ramps.slipEdges, Phase 7a.)
function ix.rampEdges(lay, n, zRing, zHw)
	local gore = ramps.gore(lay.f, n.slip.cw, n.slip.io, lay.xm, tuned(lay.spec, "ixGoreRun", ix.GORE_RUN), "sqrb_ix_", zHw)
	local edges = ramps.slipEdges(gore, { n.pos[1], n.pos[2], zRing }, ix.slipDir(n.t, lay.gamma, n.slip.io), n.tag)
	return edges, gore.tag
end

--- Fit at one radius: every ring arc keeps JUNCTION_PLAN outside its junctions (arms, link and
-- slip roads as spokes, geom.kerbCut) and its chord >= MIN_EDGE; kerb corners behind a node within
-- BEHIND_ARM / BEHIND_RAMP. Returns the worst free length and the farthest corners behind.
function ix.fit(lay)
	local f = lay.f
	local worst, behindArm, behindRamp = math.huge, 0, 0
	for _, r in ipairs(lay.rings) do
		local c, rc = r.centre, r.rc
		local spokes = {}
		for i, n in ipairs(r.nodes) do
			local sp = {}
			if n.kind == "arm" or n.kind == "link" then
				sp[1] = { p = sub(n.pos, c), d = dir(n.t), w = f.hwX, kind = "arm" }
			elseif n.slip then
				local edges = ix.rampEdges(lay, n, 0, 0)
				local e = n.slip.io == "in" and edges[2] or edges[1]
				local pts = geom.polyline(e, n.slip.io == "in", ix.RAMP_SAMPLES)
				for k, q in ipairs(pts) do pts[k] = { q[1] - c[1], q[2] - c[2], 0 } end
				sp[1] = { p = pts[1], d = S.norm(sub(pts[2], pts[1])), w = f.hwRamp, pts = pts, kind = "ramp" }
			end
			spokes[i] = sp
		end
		local nn = #r.nodes
		local last = r.open and nn - 1 or nn
		for i = 1, last do
			local j = i % nn + 1
			local t0, t1 = r.nodes[i].t, r.nodes[j].t
			if j == 1 then t1 = t1 + TWO_PI end
			local cut0, cut1 = 0, 0
			for _, sp in ipairs(spokes[i]) do
				local cut, along = geom.kerbCut(rc, rc, f.hwR, t0, t1, sp.p, sp.d, sp.w, sp.pts)
				cut0 = math.max(cut0, cut)
				if sp.kind == "arm" then behindArm = math.max(behindArm, -along) else behindRamp = math.max(behindRamp, -along) end
			end
			for _, sp in ipairs(spokes[j]) do
				local cut, along = geom.kerbCut(rc, rc, f.hwR, t1, t0, sp.p, sp.d, sp.w, sp.pts)
				cut1 = math.max(cut1, cut)
				if sp.kind == "arm" then behindArm = math.max(behindArm, -along) else behindRamp = math.max(behindRamp, -along) end
			end
			local chord = dist(r.nodes[i].pos, r.nodes[j].pos)
			local free = geom.arcLength(rc, rc, t0, t1) - cut0 - cut1
			if chord < geom.MIN_EDGE then free = math.min(free, chord - geom.MIN_EDGE) end
			worst = math.min(worst, free)
		end
	end
	return worst, behindArm, behindRamp
end

function ix.fits(lay)
	local free, ba, br = ix.fit(lay)
	return free >= geom.JUNCTION_PLAN and ba <= ix.BEHIND_ARM + 1e-9 and br <= ix.BEHIND_RAMP + 1e-9
end

--- The layout at the slider radius, or the smallest larger one (slider, then GROW_RADII) that fits.
function ix.plan(spec)
	local f = ix.frame(spec)
	local radii = {}
	for i = spec.radiusIndex, #ix.RADII do radii[#radii + 1] = ix.RADII[i] end
	for _, r in ipairs(ix.GROW_RADII) do radii[#radii + 1] = r end
	for _, r in ipairs(radii) do
		local lay = ix.layout(spec, f, r + f.offset)
		if lay and ix.fits(lay) then
			lay.radius = r
			return lay
		end
	end
	-- never reached for the shipped params (tested)
	local lay = ix.layout(spec, f, radii[#radii] + f.offset)
	lay.radius, lay.forced = radii[#radii], true
	return lay
end

local list = ramps.list
local highwayBridgeHalf = ramps.highwayBridgeHalf

--- Rings, link / waist, arms, slip roads, highway and islands for a spec from readParams. Returns {
--   lists = {{role, template, halfWidth, edges, edgeType?, edgeTypeName?}}
--          roles "highway", "ring", "link", "arms", "ramps"
--   ramps = {edges, each with .cw "s"/"n", .io "in"/"out"}, rings = plan rings (nodes with pos, tag),
--   radius (effective, >= the slider), rc, xm, xb (highway bridge half, highway over), bridge,
--   zRing, zHighway, mirrored, spec, island = nil | same format as geom.build
-- }
function ix.build(spec)
	local lay = ix.plan(spec)
	local f = lay.f
	local over = spec.level == ix.LEVEL_RING_OVER
	local zRing, zHw = over and ix.HEIGHT or 0, over and 0 or ix.HEIGHT
	local bridgeName = ix.bridgeType(spec.year)
	local rc = lay.rc

	local ringN, ringB, linkE, armE, rampE = {}, {}, {}, {}, {}
	local upper = {} -- ring-level roads that may cross the highway (rings, link, waist)
	local function addRing(e, bridge, hw)
		if bridge and over then ringB[#ringB + 1] = e else ringN[#ringN + 1] = e end
		upper[#upper + 1] = { e = e, hw = hw }
	end
	local byKind = {}
	for ri, r in ipairs(lay.rings) do
		for k, n in ipairs(r.nodes) do
			n.tag = "sqrb_ix_r" .. ri .. "_" .. k
			n.pos = { n.pos[1], n.pos[2], zRing }
			if n.kind ~= "plain" then
				byKind[n.kind] = byKind[n.kind] or {}
				byKind[n.kind][#byKind[n.kind] + 1] = n
			end
		end
		local edges = geom.ringEdges(rc, rc, r.nodes, geom.DIRECTION_CCW)
		local last = r.open and #edges - 1 or #edges
		for i = 1, last do addRing(edges[i], r.bridge and r.bridge(i), f.hwR) end
	end

	if spec.layout == ix.LAYOUT_DUMBBELL then
		-- two-way link between the rings' facing nodes, over / under the highway
		local a, b = byKind.link[1], byKind.link[2]
		local e = S.straightEdge(a.pos, b.pos, a.tag, b.tag)
		linkE[1] = e
		upper[#upper + 1] = { e = e, hw = f.hwX }
	elseif spec.layout == ix.LAYOUT_PEANUT then
		-- waist: one-way bridges continuing the lobes (west: north lobe -> south lobe, east: back)
		local function waistNode(north, east)
			for _, n in ipairs(byKind.waist) do
				if (n.pos[2] > 0) == north and (n.pos[1] > 0) == east then return n end
			end
		end
		local nw, ne, sw, se = waistNode(true, false), waistNode(true, true), waistNode(false, false), waistNode(false, true)
		local T = 2 * lay.yw
		local function tangent(n) return scale(S.left(dir(n.t)), T) end
		lay.waist = {
			{ p0 = nw.pos, t0 = tangent(nw), p1 = sw.pos, t1 = tangent(sw), tag0 = nw.tag, tag1 = sw.tag },
			{ p0 = se.pos, t0 = tangent(se), p1 = ne.pos, t1 = tangent(ne), tag0 = se.tag, tag1 = ne.tag },
		}
		for _, e in ipairs(lay.waist) do
			e.waist = true
			addRing(e, true, f.hwR)
		end
	end

	-- cross road arms, outwards from the arm nodes
	for _, n in ipairs(byKind.arm) do
		local u = dir(n.t)
		armE[#armE + 1] = S.straightEdge(n.pos, add(n.pos, scale(u, f.hwR + ix.ARM_LENGTHS[spec.armLength])), n.tag, nil)
	end

	-- the highway bridge (highway over the ring level) and the carriageway nodes
	local xb
	if not over then
		xb = highwayBridgeHalf(f, upper)
		lay.xm = math.max(lay.xm, xb + geom.MIN_EDGE)
	end
	local xm, L = lay.xm, ix.ARM_LENGTHS[spec.armLength]

	-- slip roads
	for _, n in ipairs(byKind.slip) do
		for _, e in ipairs((ix.rampEdges(lay, n, zRing, zHw))) do
			e.cw, e.io = n.slip.cw, n.slip.io
			rampE[#rampE + 1] = e
		end
	end

	-- carriageways: south eastbound (+x), north westbound (-x), straight
	local cwNodes = {}
	for _, cw in ipairs({ "s", "n" }) do
		local xs = { -xm - L, -xm, xm, xm + L }
		local tags = { false, "sqrb_ix_" .. cw .. "_w", "sqrb_ix_" .. cw .. "_e", false }
		local bridged = {}
		if xb then
			xs = { -xm - L, -xm, -xb, xb, xm, xm + L }
			tags = { false, tags[2], "sqrb_ix_" .. cw .. "_bw", "sqrb_ix_" .. cw .. "_be", tags[3], false }
			bridged[3] = true
		end
		cwNodes[cw] = { xs = xs, tags = tags, bridged = bridged }
	end
	local hwN, hwB = ramps.carriageways(f, cwNodes, zHw)

	local ringEntry = { template = geom.RING_TEMPLATES[spec.lanes] }
	local crossEntry = { template = geom.ARM_TEMPLATES[spec.cross] }
	local lists = {
		list("highway", f.highway, f.hwH, hwN),
		list("highway", f.highway, f.hwH, hwB, bridgeName),
		list("ring", ringEntry, f.hwR, ringN),
		list("ring", ringEntry, f.hwR, ringB, bridgeName),
		list("link", crossEntry, f.hwX, linkE, over and bridgeName or nil),
		list("arms", crossEntry, f.hwX, armE),
		list("ramps", ix.RAMP, f.hwRamp, rampE),
	}
	local kept = {}
	for _, l in ipairs(lists) do if #l.edges > 0 then kept[#kept + 1] = l end end

	local built = {
		lists = kept,
		ramps = rampE,
		rings = lay.rings,
		radius = lay.radius,
		rc = rc,
		xm = xm,
		xb = xb,
		alpha = lay.alpha,
		beta = lay.beta,
		D = lay.D,
		forced = lay.forced,
		bridge = bridgeName,
		zRing = zRing,
		zHighway = zHw,
		spec = spec,
		frame = f,
	}
	built.island = ix.islands(spec, built, lay)
	if spec.direction == geom.DIRECTION_CW then geom.mirrorX(built) end
	built.mirrored = spec.direction == geom.DIRECTION_CW
	return built
end

--- One island piece of a ring cut by the line dot(p, w) = cut (keeping the side w points to),
-- w = left(e): face, box collider (one side on the cut), centre model and bushes that fit.
local function cutIsland(kind, outline, e, cut, bushes, centre, faces, colliders, models)
	local w = S.left(e)
	local half = S.clipHalfPlane(outline, w, cut)
	if #half < 3 then return end
	half = S.ccw(half)
	if S.area(half) < geom.ISLAND_MIN_AREA then return end
	faces[#faces + 1] = geom.face(kind, half)
	local box = S.boxFrom(half, e, cut)
	if box then
		colliders[#colliders + 1] = { type = "BOX", x = box.x, y = box.y, rot = box.rot, hx = box.hx, hy = box.hy, hz = geom.COLLIDER_HEIGHT / 2 }
		local id = kind == geom.ISLAND_TREES and geom.MODEL_TREE or kind == geom.ISLAND_FOUNTAIN and geom.MODEL_FOUNTAIN or nil
		if id and S.fits(box.x, box.y, geom.MODEL_RADIUS[id], half) then
			models[#models + 1] = { id = id, x = box.x, y = box.y, rot = 0 }
		end
	end
	for _, m in ipairs(bushes) do
		local x, y = m.x + centre[1], m.y + centre[2]
		if S.fits(x, y, geom.MODEL_RADIUS[m.id], half) then models[#models + 1] = { id = m.id, x = x, y = y, rot = m.rot } end
	end
end

--- Centre islands (Centre island param, same values as the roundabouts'): Two-bridge: two halves
-- beside the highway (as the roundabouts' halves beside a through road); Dumbbell: one per ring;
-- Peanut: one per lobe, cut along its waist nodes. Islands stay at ground level (terrain).
function ix.islands(spec, built, lay)
	local kind = geom.islandKind(spec.island, false)
	if not kind then return nil end
	local f, rc = lay.f, lay.rc
	local faces, colliders, models = {}, {}, {}
	local function append(isl, centre)
		if not isl then return end
		for _, fc in ipairs(isl.faces) do
			local o = {}
			for i, p in ipairs(fc.outline) do o[i] = { p[1] + centre[1], p[2] + centre[2], 0 } end
			fc.outline = o
			faces[#faces + 1] = fc
		end
		for _, c in ipairs(isl.colliders) do
			c.x, c.y = c.x + centre[1], c.y + centre[2]
			colliders[#colliders + 1] = c
		end
		for _, m in ipairs(isl.models) do
			m.x, m.y = m.x + centre[1], m.y + centre[2]
			models[#models + 1] = m
		end
	end
	local ring = { a = rc, b = rc, halfWidth = f.hwR, mini = false, legs = {} }
	if spec.layout == ix.LAYOUT_TWO_BRIDGE then
		-- the roundabouts' island halves beside a through road, the highway (both carriageways) as the road
		ring.axis = true
		ring.through = { p0 = { -1, 0, 0 }, p1 = { 1, 0, 0 } }
		append(geom.islands({ island = spec.island }, ring, f.corr), { 0, 0, 0 })
	elseif spec.layout == ix.LAYOUT_DUMBBELL then
		for _, r in ipairs(lay.rings) do append(geom.islands({ island = spec.island }, ring, nil), r.centre) end
	else
		for _, r in ipairs(lay.rings) do
			local outline, ai, bi = geom.islandOutline(rc, rc, f.hwR, r.centre)
			if outline then
				local north = r.centre[2] > 0
				local bushes = geom.islandModels(kind, ai, bi, false)
				cutIsland(kind, outline, north and { 1, 0, 0 } or { -1, 0, 0 }, lay.yw, bushes, r.centre, faces, colliders, models)
			end
		end
	end
	if #faces == 0 then return nil end
	return { kind = kind, faces = faces, colliders = colliders, models = models }
end

return ix
