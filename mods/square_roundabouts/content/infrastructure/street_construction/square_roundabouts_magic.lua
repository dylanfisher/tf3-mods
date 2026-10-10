-- Better Roundabouts: pure geometry of the "Magic Roundabout" menu entry (no api.*), modelled on
-- Swindon's Magic Roundabout: five mini roundabouts ("satellites") on a circle, joined by two-way
-- roads that together form the central ring. With two-way links the ring's inner lane runs
-- against the satellites' direction (contraflow) and its outer lane with it, as in Swindon.
-- Each satellite has one approach arm. See PLAN.md "Phase 3 notes" for why there is no separate
-- one-way central ring.
--
-- Same conventions and output format as square_roundabouts_geometry.build (lists, island), so
-- square_roundabouts_result.lua maps both.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local S = geom.shapes

local magic = {}

local PI = math.pi
local DEG = PI / 180

magic.SATELLITES = 5
magic.FIRST_DEG = 90          -- satellite 1 points north, then every 72 degrees anticlockwise
magic.SAT_LANES = 1           -- default satellites: 1-lane ring (highway_new_small), as the base mini set
-- "Mini roundabout lanes" param: 1 or 2 lanes (indexes geom.RING_TEMPLATES / RING_OFFSET; 2 is
-- town_new_one_way_small). The links stay town_new_small either way.
magic.LANE_CHOICES = 2
magic.LINK = { template = "::/infrastructure/street/town/town_new_small.street_template", halfWidth = 8 }
magic.OUTLINE_SEGMENTS = 120  -- centre island outline points

-- "Size" param: the whole layout scales. Satellite radius param (inside the satellite's ring road)
-- and the distance from the centre to each satellite centre (= link ring centreline radius),
-- 3 x the satellite centreline radius + 1 as in the original 12 m / 52 m layout (Size 3). Large
-- is the Phase 4 Very large; Very large (35 m) makes the top of the range twice as wide as Small.
-- Satellites below geom.MINI_RADIUS_BELOW are mini roundabouts (flat islands).
magic.SIZES = {
	{ radius = 8, distance = 40 },
	{ radius = 10, distance = 46 },
	{ radius = 12, distance = 52 },
	{ radius = 20, distance = 76 },
	{ radius = 35, distance = 121 },
}
magic.DEFAULT_SIZE = 1 -- XS (2026-10-09, user: size menus default to the smallest; was 3 = M)
magic.SIZE_NAMES = { "XS", "S", "M", "L", "XL" } -- button labels (2026-10-09: were Compact / Small / Medium / Large / Huge)

-- shares the main entry's keys for the params both have (same meaning, same values)
local K = geom.PARAM_KEYS
magic.PARAM_KEYS = {
	size = "sqrb_magic_size",
	armType = K.armType,
	direction = K.direction,
	island = K.island,
	lanes = "sqrb_magic_lanes",
}

function magic.readParams(params)
	params = params or {}
	local k = magic.PARAM_KEYS
	return {
		size = geom.index(params[k.size], #magic.SIZES, magic.DEFAULT_SIZE),
		armType = geom.index(params[k.armType], #geom.ARM_TEMPLATES, 1),
		direction = geom.index(params[k.direction], 2, geom.DIRECTION_CCW),
		island = geom.index(params[k.island], 5, geom.ISLAND_NONE),
		lanes = geom.index(params[k.lanes], magic.LANE_CHOICES, magic.SAT_LANES),
		-- dev overrides (geom.readDev): only magicSize, magicRadius, magicDistance apply here
		dev = geom.readDev(params),
	}
end

--- Layout of one size: satellite centres, their ring node parameters (local angles around the
-- satellite centre) and the junction spokes, or nil if the arm road does not fit (unless force).
-- Fit: every satellite edge and link keeps geom.JUNCTION_PLAN outside its junctions (a wide arm's
-- kerb corner cuts far into a small satellite: Size 3 with large arms left 0.5-1.6 m and failed
-- in game), and neighbouring arms keep LEG_CLEARANCE between their kerbs where they start.
-- sz = {radius, distance} replaces magic.SIZES[size] (dev overrides).
function magic.layout(spec, size, force, sz)
	local lanes = spec.lanes or magic.SAT_LANES
	sz = sz or magic.SIZES[size]
	local rs = sz.radius + geom.RING_OFFSET[lanes]
	local hwS = geom.RING_HALF_WIDTH[lanes]
	local hwArm = geom.ARM_HALF_WIDTH[spec.armType]
	local hwL = magic.LINK.halfWidth
	local D = sz.distance
	local dTheta = 2 * math.asin(rs / (2 * D)) -- where a satellite ring crosses the link circle
	local n = magic.SATELLITES
	local step = 2 * PI / n
	local lay = { lanes = lanes, rs = rs, hwS = hwS, D = D, dTheta = dTheta, step = step, size = size, radius = sz.radius, sats = {} }

	-- neighbouring arms: chord between their start points
	local fits = 2 * (D + rs) * math.sin(step / 2) >= 2 * hwArm + geom.LEG_CLEARANCE
	-- links: arc length minus the satellites' half widths at both ends
	fits = fits and D * (step - 2 * dTheta) - 2 * (hwS + 2) >= geom.JUNCTION_PLAN

	-- one satellite (all five are the same, rotated): work at theta = 0, centre (D, 0)
	local c = { D, 0, 0 }
	local plusPos = S.scale(S.dir(dTheta), D)
	local minusPos = S.scale(S.dir(-dTheta), D)
	local function localT(p) return S.wrap(S.atan2(p[2] - c[2], p[1] - c[1])) end
	local tOut, tPlus = 0, localT(plusPos)
	local tMinus = localT(minusPos) - 2 * PI -- negative: below the out node
	local spokeOut = { p = { rs, 0, 0 }, d = { 1, 0, 0 }, w = hwArm }
	local plusDir = S.left(S.dir(dTheta))           -- link leaving towards the next satellite
	local minusDir = S.scale(S.left(S.dir(-dTheta)), -1) -- link leaving towards the previous one
	local spokePlus = { p = S.sub(plusPos, c), d = plusDir, w = hwL }
	local spokeMinus = { p = S.sub(minusPos, c), d = minusDir, w = hwL }

	-- the node between the arm node and a link node goes where both edges keep the same free
	-- length (the arm side loses more to a wide arm); edges stay within MIN_EDGE .. 90 degrees
	local function between(tA, spA, tB, spB)
		local arc = geom.arcLength(rs, rs, tA, tB)
		local cutA = (geom.kerbCut(rs, rs, hwS, tA, tB, spA.p, spA.d, spA.w))
		local cutB = (geom.kerbCut(rs, rs, hwS, tB, tA, spB.p, spB.d, spB.w))
		local la = (arc + cutA - cutB) / 2
		local lo = math.max(geom.MIN_EDGE, arc - geom.MAX_EDGE_ANGLE * rs)
		local hi = math.min(arc - geom.MIN_EDGE, geom.MAX_EDGE_ANGLE * rs)
		la = math.max(lo, math.min(hi, la))
		local free = math.min(la - cutA, arc - la - cutB)
		return tA + (tB - tA) * la / arc, free, lo <= hi
	end
	local tUp, freeUp, okUp = between(tOut, spokeOut, tPlus, spokePlus)
	local tDown, freeDown, okDown = between(tOut, spokeOut, tMinus, spokeMinus)
	fits = fits and okUp and okDown and math.min(freeUp, freeDown) >= geom.JUNCTION_PLAN

	-- the back of the satellite (between the two link nodes): even edges of at most 90 degrees
	local back = (tMinus + 2 * PI) - tPlus
	local nBack = math.max(1, math.ceil(back / geom.MAX_EDGE_ANGLE - 1e-7))
	-- local parameters ascending from the minus node; anchor 1 = arm, 2 = plus, 3 = minus
	local ts, anchor = { tMinus, tDown, tOut, tUp, tPlus }, { 3, nil, 1, nil, 2 }
	for k = 1, nBack - 1 do ts[#ts + 1] = tPlus + back * k / nBack end
	lay.ts, lay.anchor = ts, anchor
	if not (fits or force) then return nil end
	return lay
end

--- Engine-tuned smallest size for the arm road and direction (square_roundabouts_tuning.lua
-- `magic`), or nil. 2-lane satellites use their own rows ("arm,dir,2", search_magic2); without one
-- the 1-lane row applies. The rows differ: the engine took 2-lane Medium with large arms, where
-- 1 lane needs Large (the wider satellites push the arms further apart).
function magic.sizeFloor(spec)
	local t = geom.tuning.magic
	if not t then return nil end
	local row
	local lanes = spec.lanes or magic.SAT_LANES
	if lanes ~= magic.SAT_LANES then
		row = t[spec.armType .. "," .. spec.direction .. "," .. lanes]
	end
	row = row or t[spec.armType .. "," .. spec.direction] or t[tostring(spec.armType)]
	local v = row and row[spec.size]
	if v and v > spec.size and magic.SIZES[v] then return v end
	return nil
end

--- Dev overrides (geom.readDev magicSize / magicRadius / magicDistance): exactly that layout, no
-- growth; built even if the offline model rejects it (lay.offline). The distance is kept at
-- least DEV_MIN_SPACING x the satellite centreline radius, so the links keep a positive length.
magic.DEV_MIN_SPACING = 1.7
function magic.devLayout(spec)
	local dev = spec.dev
	local size = dev.magicSize or spec.size
	local base = magic.SIZES[size]
	local radius = dev.magicRadius or base.radius
	local rs = radius + geom.RING_OFFSET[spec.lanes or magic.SAT_LANES]
	local distance = dev.magicDistance or (dev.magicRadius and 3 * rs + 1) or base.distance
	distance = math.max(distance, magic.DEV_MIN_SPACING * rs)
	local sz = { radius = radius, distance = distance }
	local lay = magic.layout(spec, size, false, sz)
	local offline = lay ~= nil
	if not lay then lay = magic.layout(spec, size, true, sz) end
	lay.offline = offline
	return lay
end

--- Effective size: the chosen one (or the tuning floor), or the smallest larger one at which the
-- arm road fits.
function magic.chooseLayout(spec)
	local dev = spec.dev
	if dev and (dev.magicSize or dev.magicRadius or dev.magicDistance) then return magic.devLayout(spec) end
	for size = magic.sizeFloor(spec) or spec.size, #magic.SIZES do
		local lay = magic.layout(spec, size)
		if lay then return lay end
	end
	-- never reached for the shipped params (tested)
	return magic.layout(spec, #magic.SIZES, true)
end

--- Satellites, links, arms and islands. Returns {
--   lists = {{role, template, halfWidth, edges}}  roles "satellites", "links", "arms"
--   satellites = {{centre, nodes, edges}}, links = {edges}, arms = {edges},
--   rs, halfWidth, distance, size (effective), mini,
--   island = nil | same format as geom.build
-- }
function magic.build(spec)
	local lay = magic.chooseLayout(spec)
	local rs, hwS, D, dTheta, step = lay.rs, lay.hwS, lay.D, lay.dTheta, lay.step
	local n = magic.SATELLITES

	local satellites, satEdges, armEdges, linkEdges = {}, {}, {}, {}
	for i = 1, n do
		local theta = (magic.FIRST_DEG * DEG) + (i - 1) * step
		local c = S.scale(S.dir(theta), D)
		local nodes, byAnchor = {}, {}
		for k, t in ipairs(lay.ts) do
			local an = lay.anchor[k]
			local pos
			if an == 2 then pos = S.scale(S.dir(theta + dTheta), D)      -- towards satellite i + 1
			elseif an == 3 then pos = S.scale(S.dir(theta - dTheta), D)  -- towards satellite i - 1
			else pos = S.add(c, S.scale(S.dir(theta + t), rs)) end
			nodes[k] = { pos = pos, tag = "sqrb_sat_" .. i .. "_" .. k, t = theta + t, anchor = an }
			if an then byAnchor[an] = nodes[k] end
		end
		-- ring edges are built from ascending parameters around the satellite centre
		local rel = {}
		for k, nd in ipairs(nodes) do rel[k] = { pos = nd.pos, tag = nd.tag, t = nd.t } end
		local edges = geom.ringEdges(rs, rs, rel, spec.direction)
		for _, e in ipairs(edges) do
			-- ringEdges works around the origin: positions are the node positions already,
			-- tangents from the circle around the origin are the same around c
			e.satellite = i
			satEdges[#satEdges + 1] = e
		end
		local out = byAnchor[1]
		local u = S.dir(theta)
		local arm = S.straightEdge(out.pos, S.add(out.pos, S.scale(u, hwS + geom.ARM_LENGTH)), out.tag, nil)
		arm.arm = i
		armEdges[#armEdges + 1] = arm
		satellites[i] = { centre = c, theta = theta, nodes = nodes, edges = edges, out = out, plus = byAnchor[2], minus = byAnchor[3] }
	end

	-- links: arcs of the link circle from satellite i's "plus" node to satellite i+1's "minus" node
	local span = step - 2 * dTheta
	local hs = geom.hermiteScale(span) * D
	for i = 1, n do
		local s0, s1 = satellites[i], satellites[i % n + 1]
		local a0 = s0.theta + dTheta
		local a1 = a0 + span
		local e = {
			p0 = s0.plus.pos, t0 = S.scale(S.left(S.dir(a0)), hs),
			p1 = s1.minus.pos, t1 = S.scale(S.left(S.dir(a1)), hs),
			tag0 = s0.plus.tag, tag1 = s1.minus.tag, link = i,
		}
		linkEdges[#linkEdges + 1] = e
	end

	local satRadius = lay.radius
	local built = {
		offline = lay.offline, -- only with dev overrides: whether the offline model accepted the layout
		rs = rs,
		halfWidth = hwS,
		distance = D,
		size = lay.size,
		mini = satRadius < geom.MINI_RADIUS_BELOW,
		satellites = satellites,
		links = linkEdges,
		arms = armEdges,
		lists = {
			{ role = "satellites", template = geom.RING_TEMPLATES[lay.lanes], halfWidth = hwS, edges = satEdges },
			{ role = "links", template = magic.LINK.template, halfWidth = magic.LINK.halfWidth, edges = linkEdges },
			{ role = "arms", template = geom.ARM_TEMPLATES[spec.armType], halfWidth = geom.ARM_HALF_WIDTH[spec.armType], edges = armEdges },
		},
	}
	built.island = magic.islands(spec, built)
	return built
end

--- Centre island (inside the link ring, dented around the satellites) plus a flat island in each
-- satellite, when the island param is not None.
function magic.islands(spec, built)
	local kind = geom.islandKind(spec.island, false)
	if not kind then return nil end
	local D, rs = built.distance, built.rs
	local m = geom.ISLAND_MARGIN
	local outer = D - magic.LINK.halfWidth - m
	local dent = rs + built.halfWidth + m
	local outline, rmin = {}, outer
	for k = 0, magic.OUTLINE_SEGMENTS - 1 do
		local psi = 2 * PI * k / magic.OUTLINE_SEGMENTS
		local rho = outer
		for _, sat in ipairs(built.satellites) do
			local d = psi - sat.theta
			local across = D * math.sin(d)
			if math.cos(d) > 0 and math.abs(across) < dent then
				rho = math.min(rho, D * math.cos(d) - math.sqrt(dent * dent - across * across))
			end
		end
		rmin = math.min(rmin, rho)
		outline[#outline + 1] = { rho * math.cos(psi), rho * math.sin(psi), 0 }
	end
	local hz = geom.COLLIDER_HEIGHT / 2
	local faces = { geom.face(kind, outline) }
	local r = rmin * 0.98
	local colliders = { { type = "CYLINDER", x = 0, y = 0, rot = 0, hx = r, hy = r, hz = hz } }
	local models = geom.islandModels(kind, r, r)

	-- satellites below 15 m are mini roundabouts: trees and fountain become paving
	local satKind = geom.islandKind(spec.island, built.mini)
	for _, sat in ipairs(built.satellites) do
		local o, ai, bi, k = geom.islandOutline(rs, rs, built.halfWidth, sat.centre)
		if o then
			faces[#faces + 1] = geom.face(satKind, o)
			colliders[#colliders + 1] = { type = "CYLINDER", x = sat.centre[1], y = sat.centre[2], rot = 0, hx = ai * k, hy = bi * k, hz = hz }
			for _, m in ipairs(geom.islandModels(satKind, ai, bi)) do
				models[#models + 1] = { id = m.id, x = m.x + sat.centre[1], y = m.y + sat.centre[2], rot = m.rot }
			end
		end
	end
	return { kind = kind, faces = faces, colliders = colliders, models = models }
end

return magic
