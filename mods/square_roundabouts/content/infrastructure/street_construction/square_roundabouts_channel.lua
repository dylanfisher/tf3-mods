-- Better Roundabouts: pure geometry of the "Channelized Junction" menu entry (no api.*).
-- A T or X junction of two two-way roads with one-way slip lanes across its corners (each with a
-- triangle island between the slip lane and the corner), and optional splitter islands on the
-- side road. Every node is freed, so after placement it is ordinary, editable streets built from
-- base templates. See PHASE5.md "Phase 5b notes".
--
-- Frame: main road along x (east-west), side road north (+y) and, for X, south. The layout is
-- built for right-hand traffic and mirrored in x for left-hand traffic, so the side road stays
-- north and each one-way road keeps its driving direction along the edge.
-- Same output format as square_roundabouts_geometry.build (lists, island), so
-- square_roundabouts_result.lua maps it.

local DIR = "square_roundabouts::/infrastructure/street_construction/"
local geom = ug_require(DIR .. "square_roundabouts_geometry.lua")
local S = geom.shapes

local ch = {}

local PI = math.pi
local DEG = PI / 180
local add, sub, scale, dot, left, norm, combine = S.add, S.sub, S.scale, S.dot, S.left, S.norm, S.combine

ch.LAYOUT_T = 1
ch.LAYOUT_X = 2
ch.SLIPS_NEAR = 1   -- near-side corners: right turns (right-hand traffic) / left turns (left-hand)
ch.SLIPS_MAIN = 2   -- every turn off the main road onto the side road
ch.SLIPS_NONE = 3
ch.SPLITTER_OFF = geom.SPLITTER_OFF
ch.SPLITTER_ON = geom.SPLITTER_ON

-- "Arm length": how far each arm runs beyond its outermost node (the slip lane node; without slip
-- lanes the split node, or the crossing road's kerb). 30 m = geom.ARM_LENGTH, the roundabouts' arms.
ch.ARM_LENGTHS = { 30, 40, 50, 60 }
ch.DEFAULT_ARM_LENGTH = 1
-- "Islands" param -> geom island kind (no trees or fountain: the triangles are narrow).
ch.ISLAND_KINDS = { geom.ISLAND_NONE, geom.ISLAND_GRASS, geom.ISLAND_PAVED }
ch.DEFAULT_MAIN = 2 -- Town, medium
ch.DEFAULT_SIDE = 1 -- Town, small

-- Slip lanes: one-way town xsmall (14 m, the splitter legs' template), leaving and joining the
-- arms at SLIP_ANGLE. A shallower angle makes the gore (the junction between the slip lane and
-- the arm it runs beside) longer: the set-back below grows with it.
ch.SLIP = geom.LEG
ch.SLIP_ANGLE = 40 * DEG
-- Slip lane templates (dev override chSlip, tuning row `slip`): one-way xsmall (2 lanes, 14 m),
-- small (2 lanes, 16 m), medium (4 lanes, 24 m): the splitter legs' list, geom.DEV_LEGS.
ch.SLIP_TEMPLATES = { geom.DEV_LEGS[1].entry, geom.DEV_LEGS[2].entry, geom.DEV_LEGS[3].entry }
-- Car lanes per direction of each arm road (geom.ARM_TEMPLATES: small 1, medium 2, large 3).
ch.LANES = { 1, 2, 3, 1, 2, 3 }
-- Phase 5f, engine data (p5_all, p5_channel_search; PHASE5.md "Phase 5f notes"): the engine
-- rejects a slip node on a wide road at a shallow angle. A node with one slip lane (the main road's
-- in a T) takes 40 deg up to 2 lanes per direction and needs 50 deg with 3; a node shared by two
-- slip lanes (the side road's in a T, every node in an X) takes 40 deg with 1 lane, 50 deg on
-- country medium, and with xsmall slip lanes nothing up to 50 deg on town medium (without
-- splitter islands) or large roads. The tuning table's `channel` rows hold the accepted angle per
-- layout, main road, side road and splitter; rows with `none` (nothing accepted) build the
-- FALLBACK below. The roundabouts' splitter search saw the same at a split node (an arm forking
-- into two one-way roads): town medium arms needed 65 deg with 2-lane legs, large arms 4-lane
-- legs (one-way medium) at 50 deg. So the fallback, per the most lanes per direction of a road
-- with shared slip nodes: 2 lanes -> one-way small slip lanes at 65 deg, 3 lanes -> one-way
-- medium at 50 deg (p5f_all placed it on all 81 combos). Phase 5g: p5f_search (50 / 65 / 80 deg x
-- the three templates on exactly these combos) accepted one-way xsmall at 65 deg on 52 of them
-- and at 80 deg on all 81; both are narrower and set back less than the fallback (65 deg xsmall
-- 1-2 m less than 65 deg small, 7-53 m less than 50 deg medium), so the tuning table now has a
-- row with an angle for every combo and no `none` row: the fallback only applies to a table
-- regenerated without the p5f search.
ch.FALLBACK = { [2] = { angle = 65, slip = 2 }, [3] = { angle = 50, slip = 3 } }

-- Arms in the right-hand frame: 1 east, 2 north, 3 west, 4 south; main road east-west.
ch.ARMS = {
	{ u = { 1, 0, 0 }, road = "main" },
	{ u = { 0, 1, 0 }, road = "side" },
	{ u = { -1, 0, 0 }, road = "main" },
	{ u = { 0, -1, 0 }, road = "side" },
}
ch.LAYOUT_ARMS = { { 1, 2, 3 }, { 1, 2, 3, 4 } }
-- Slip lanes {from arm, to arm} in the right-hand frame, per Slip lanes value and layout.
ch.SLIP_SETS = {
	[ch.SLIPS_NEAR] = { { { 1, 2 }, { 2, 3 } }, { { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 } } },
	[ch.SLIPS_MAIN] = { { { 1, 2 }, { 3, 2 } }, { { 1, 2 }, { 3, 2 }, { 3, 4 }, { 1, 4 } } },
	[ch.SLIPS_NONE] = { {}, {} },
}

local K = geom.PARAM_KEYS
ch.PARAM_KEYS = {
	layout = "sqrb_ch_layout",
	main = "sqrb_ch_main",
	side = "sqrb_ch_side",
	slips = "sqrb_ch_slips",
	splitter = "sqrb_ch_splitter",
	armLength = "sqrb_ch_arm_length",
	direction = K.direction, -- same meaning and values as the roundabouts' Direction
	island = "sqrb_ch_island",
}

function ch.readParams(params)
	params = params or {}
	local k = ch.PARAM_KEYS
	local index = geom.index
	return {
		layout = index(params[k.layout], #ch.LAYOUT_ARMS, ch.LAYOUT_T),
		main = index(params[k.main], #geom.ARM_TEMPLATES, ch.DEFAULT_MAIN),
		side = index(params[k.side], #geom.ARM_TEMPLATES, ch.DEFAULT_SIDE),
		slips = index(params[k.slips], 3, ch.SLIPS_NEAR),
		splitter = index(params[k.splitter], 2, ch.SPLITTER_OFF),
		armLength = index(params[k.armLength], #ch.ARM_LENGTHS, ch.DEFAULT_ARM_LENGTH),
		direction = index(params[k.direction], 2, geom.DIRECTION_CCW),
		island = index(params[k.island], #ch.ISLAND_KINDS, 1),
		-- dev overrides (geom.readDev): only chSlipAngle, chCornerGap, chSlipFree apply here
		dev = geom.readDev(params),
	}
end

--- Tuning row of a spec (square_roundabouts_tuning.lua `channel`: "layout,main,side,splitter";
-- the slip lanes set, traffic side, arm length and islands never changed a verdict), or nil.
function ch.tuningRow(spec)
	local t = geom.tuning.channel
	return t and t[spec.layout .. "," .. spec.main .. "," .. spec.side .. "," .. spec.splitter]
end

--- Slip lane angle (degrees) and template index from the engine data: the accepted angle of the
-- spec's tuning row, ch.FALLBACK where the engine accepted nothing (`none`), else SLIP_ANGLE with
-- one-way xsmall. Third result: "engine" (accepted), "fallback" (unverified) or nil (shipped).
function ch.slipRule(spec)
	local row = spec and ch.tuningRow(spec)
	if row and row.none then
		local lanes = ch.LANES[spec.side]
		if spec.layout == ch.LAYOUT_X then lanes = math.max(lanes, ch.LANES[spec.main]) end
		local fb = ch.FALLBACK[lanes] or { angle = 50, slip = 1 }
		return fb.angle, fb.slip, "fallback"
	end
	if row and row.angle then return row.angle, row.slip or 1, "engine" end
	return ch.SLIP_ANGLE / DEG, 1, nil
end

--- Tunables of a spec: the DEV-ONLY probe's override (geom.readDev), else ch.slipRule.
function ch.slipAngle(spec)
	local v = spec and spec.dev and spec.dev.chSlipAngle
	if v then return v * DEG end
	return (ch.slipRule(spec)) * DEG
end

--- Slip lane template {template, halfWidth} of a spec.
function ch.slipRoad(spec)
	local v = spec and spec.dev and spec.dev.chSlip
	if v and ch.SLIP_TEMPLATES[v] then return ch.SLIP_TEMPLATES[v] end
	local _, slip = ch.slipRule(spec)
	return ch.SLIP_TEMPLATES[slip] or ch.SLIP
end
local function tuned(spec, name, default)
	local v = spec and spec.dev and spec.dev[name]
	if v then return v end
	return default
end

--- Splitter legs of the side road: the roundabout's engine-tuned splitter set for that arm road
-- (geom.splitParams: split distance, fork, spread, leg template; the rules are the same for every
-- ring lane count, so lanes = 2 picks them).
-- The legs join a straight main road, which can be wider than any ring: if the triangle between
-- them stays under SPLIT_TRIANGLE_MIN (country medium side roads: 8-15 m^2, none on a town large
-- main road), the split node moves out in SPLIT_GROW steps, at most SPLIT_GROW_MAX. Checked
-- whatever the Islands param, so the road layout never depends on it.
ch.SPLIT_TRIANGLE_MIN = 15
ch.SPLIT_GROW = 2
ch.SPLIT_GROW_MAX = 12

--- Legs of the north arm (right-hand frame) for split params sp: exit, entry, split position.
function ch.northLegs(spec, sp, tags)
	tags = tags or {}
	local u = { 0, 1, 0 }
	local d = sp.leg.halfWidth + sp.spread
	local splitPos = scale(u, geom.ARM_HALF_WIDTH[spec.main] + sp.split)
	-- right-hand traffic: the entry leg on the right of an inbound driver (west), exit east
	local exit, entry = geom.legCurves(u, u, splitPos, sp.fork, { d, 0, 0 }, { -d, 0, 0 }, 1, tags.x, tags.e, tags.split)
	return exit, entry, splitPos
end

function ch.splitParams(spec)
	local sp = geom.splitParams({ armType = spec.side, lanes = 2, tram = geom.TRAM_OFF })
	local limit = geom.ARM_HALF_WIDTH[spec.main] + geom.ISLAND_MARGIN
	local base = sp.split
	while sp.split < base + ch.SPLIT_GROW_MAX do
		local exit, entry = ch.northLegs(spec, sp)
		local tri = geom.legTriangle({ exit = exit, entry = entry }, sp.leg.halfWidth, 1, function(p) return p[2] >= limit end)
		if tri and S.area(tri) >= ch.SPLIT_TRIANGLE_MIN then break end
		sp.split = sp.split + ch.SPLIT_GROW
	end
	return sp
end

-- Slip lane set-backs (distance of the slip node from the junction centre). Two rules, tuned
-- offline against the engine-fitted junction model (tests/square_roundabouts/checks.lua
-- engineModel), the overlap check and the island sizes for every shipped combination
-- (PHASE5.md "Phase 5b notes"):
-- 1. Junction room: set-back = start + SLIP_FREE + gore(arm half width). start: the crossing
--    road's kerb (with splitter islands: beyond the leg node, or the split node plus a leg half
--    width on the side road); gore: how much of the arm the slip lane's junction takes, the kerb
--    corner of a straight slip lane ((hw + hwSlip cos a) / tan a + hwSlip sin a). The engine took
--    2.0 m of free length; the model asks 2.5 m, SLIP_FREE leaves a margin over it.
-- 2. Island room: the slip lane's kerb keeps CORNER_GAP from the corner of the two roads' kerbs
--    (and from the splitter leg on that side), so a triangle island fits between them. Both
--    set-backs grow by the same amount (bisection, rounded up to SETBACK_STEP).
ch.SLIP_FREE = 4
ch.CHORD_MARGIN = 2 * DEG
ch.CORNER_GAP = 7
ch.SETBACK_STEP = 0.5
ch.SLIP_SAMPLES = 24

function ch.gore(hw, angle, hl)
	local a = angle or ch.SLIP_ANGLE
	hl = hl or ch.SLIP.halfWidth
	return (hw + hl * math.cos(a)) / math.tan(a) + hl * math.sin(a)
end

--- Slip lane from the slip node on arm a (distance La) to the one on arm b (Lb): leaves arm a
-- towards the centre, turned SLIP_ANGLE towards arm b, and joins arm b heading out, SLIP_ANGLE
-- off its axis. angle: ch.slipAngle(spec) (default ch.SLIP_ANGLE).
function ch.slipEdge(ua, La, ub, Lb, tag0, tag1, angle)
	local a = angle or ch.SLIP_ANGLE
	local ca, sa = math.cos(a), math.sin(a)
	return S.curveEdge(scale(ua, La), combine(ua, -ca, ub, sa), scale(ub, Lb), combine(ub, ca, ua, -sa), tag0, tag1)
end

--- Slip node distances from the centre: main arms, side arms. leg (optional): the splitter leg
-- in the north-east corner (the corner every other one mirrors).
function ch.setbacks(spec, sp, leg)
	local hwM, hwS = geom.ARM_HALF_WIDTH[spec.main], geom.ARM_HALF_WIDTH[spec.side]
	local hl = ch.slipRoad(spec).halfWidth
	local angle = ch.slipAngle(spec)
	local free, gap = tuned(spec, "chSlipFree", ch.SLIP_FREE), tuned(spec, "chCornerGap", ch.CORNER_GAP)
	local mainStart, sideStart = hwS, hwM
	if spec.splitter == ch.SPLITTER_ON then
		mainStart = sp.leg.halfWidth + sp.spread + sp.leg.halfWidth
		sideStart = hwM + sp.split + sp.leg.halfWidth
	end
	local Lm = mainStart + free + ch.gore(hwM, angle, hl)
	local Ls = sideStart + free + ch.gore(hwS, angle, hl)
	-- one-way bend: the chord between the slip nodes must point between the two end headings
	-- (with CHORD_MARGIN to spare), else the slip lane bends back towards the longer arm in an
	-- S-curve and runs alongside it (a long gore; splitter islands push the side node far out).
	-- The chord lies between them while atan(Ls / Lm) is between min(a, 90 - a) and max(a, 90 - a).
	-- Up to 50 deg the factor is tan(a + margin) as the engine saw it (p5_channel_search; above 45
	-- deg that only scales both set-backs up), steeper angles use tan(90 deg - a + margin).
	local k = math.tan((angle <= 50 * DEG + 1e-9 and angle or (PI / 2 - angle)) + ch.CHORD_MARGIN)
	Lm, Ls = math.max(Lm, Ls * k), math.max(Ls, Lm * k)
	-- island room in the north-east corner (east arm -> north arm)
	local corner = { hwS, hwM, 0 }
	local legPts
	if leg then
		legPts = {}
		for k = 0, ch.SLIP_SAMPLES do legPts[#legPts + 1] = (S.hermite(leg, k / ch.SLIP_SAMPLES)) end
	end
	local function room(extra)
		local e = ch.slipEdge({ 1, 0, 0 }, Lm + extra, { 0, 1, 0 }, Ls + extra, nil, nil, angle)
		local worst = math.huge
		for k = 0, ch.SLIP_SAMPLES do
			local p = S.hermite(e, k / ch.SLIP_SAMPLES)
			worst = math.min(worst, S.dist(p, corner) - hl)
			for _, q in ipairs(legPts or {}) do
				worst = math.min(worst, S.dist(p, q) - hl - sp.leg.halfWidth)
			end
		end
		return worst
	end
	if room(0) < gap then
		local lo, hi = 0, 100
		for _ = 1, 30 do
			local mid = (lo + hi) / 2
			if room(mid) >= gap then hi = mid else lo = mid end
		end
		local extra = math.ceil(hi / ch.SETBACK_STEP) * ch.SETBACK_STEP
		Lm, Ls = Lm + extra, Ls + extra
	end
	return Lm, Ls
end

--- Corner island between a slip lane (from arm a to arm b, edge e) and its corner, bounded by
-- kerb lines + ISLAND_MARGIN: arm a's kerb, the slip lane, arm b's kerb and, with splitter
-- islands, the leg on that side of the side road. Returns the polygon or nil.
local function cornerIsland(lay, a, b, e)
	local m = geom.ISLAND_MARGIN
	local big = 400
	local ua, ub = lay.arms[a].u, lay.arms[b].u
	local hwa, hwb = lay.arms[a].hw, lay.arms[b].hw
	local ka = { combine(ub, hwa + m, ua, -big), combine(ub, hwa + m, ua, big) }       -- outwards
	local kb = { combine(ua, hwb + m, ub, big), combine(ua, hwb + m, ub, -big) }       -- inwards
	local pMid, dMid = S.hermite(e, 0.5)
	local side = dot(left(norm(dMid)), scale(pMid, -1)) > 0 and 1 or -1 -- towards the corner
	local ks = S.offsetPolyline(e, side, lay.slipHw + m, 40, 10)
	local chains = { ka, ks, kb }
	local sideArm = lay.arms[a].road == "side" and a or b
	local legs = lay.legsByArm[sideArm]
	if legs then
		local mainU = lay.arms[sideArm == a and b or a].u
		-- the leg whose main-road node lies on this corner's side of the side road
		local leg = dot(legs.exit.p0, mainU) > 0 and legs.exit or legs.entry
		local lp, ld = S.hermite(leg, 0.5)
		local lside = dot(left(norm(ld)), mainU) > 0 and 1 or -1
		local kl = S.offsetPolyline(leg, lside, lay.legHw + m, 40, 10)
		-- runs from arm b's road to arm a's road: reverse it if the leg goes the other way
		local fromMain = leg == legs.exit -- exit leg: main-road node -> split node
		local bIsSide = sideArm == b
		if fromMain == bIsSide then
			local rev = {}
			for i = #kl, 1, -1 do rev[#rev + 1] = kl[i] end
			kl = rev
		end
		chains[4] = kl
	end
	local poly = S.chainPolygon(chains)
	if not poly or S.area(poly) < geom.ISLAND_MIN_AREA then return nil end
	return poly, ua, ub, hwa, hwb
end

--- Box collider inside a corner island (keeps town buildings off), or nil: sides along the two
-- arms, one side on the kerb line of the arm whose left is the other arm.
local function cornerCollider(poly, ua, ub, hwa, hwb)
	local e, s0 = ua, hwa + geom.ISLAND_MARGIN
	if dot(left(ua), ub) < 0.5 then e, s0 = ub, hwb + geom.ISLAND_MARGIN end
	local box = S.boxFrom(poly, e, s0)
	if not box then return nil end
	local w = left(e)
	local c = { box.x, box.y, 0 }
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			local q = add(c, combine(e, sx * box.hx, w, sy * box.hy))
			if not S.pointInPolygon(q[1], q[2], poly) then return nil end
		end
	end
	return { type = "BOX", x = box.x, y = box.y, rot = box.rot, hx = box.hx, hy = box.hy, hz = geom.COLLIDER_HEIGHT / 2 }
end

local function list(role, template, halfWidth, edges)
	return { role = role, template = template, halfWidth = halfWidth, edges = edges }
end

--- Arms, slip lanes, splitter legs and islands for a spec from readParams. Returns {
--   lists = {{role, template, halfWidth, edges}}  roles "main", "side", "slips", "legs"
--   slips = {edges, each with .from, .to (arm numbers, right-hand frame)}, legs = {{arm, entry, exit, split}},
--   setback = {main, side}, mirrored (left-hand traffic), spec,
--   island = nil | same format as geom.build
-- }
function ch.build(spec)
	local hwM, hwS = geom.ARM_HALF_WIDTH[spec.main], geom.ARM_HALF_WIDTH[spec.side]
	local splitter = spec.splitter == ch.SPLITTER_ON
	local sp = ch.splitParams(spec)
	local legHw = sp.leg.halfWidth
	local d = legHw + sp.spread
	local slipRoad = ch.slipRoad(spec)
	local lay = { arms = {}, legsByArm = {}, legHw = legHw, slipHw = slipRoad.halfWidth }
	for i, arm in ipairs(ch.ARMS) do
		lay.arms[i] = { u = arm.u, road = arm.road, hw = arm.road == "main" and hwM or hwS }
	end
	local armLength = ch.ARM_LENGTHS[spec.armLength]
	local slipSet = ch.SLIP_SETS[spec.slips][spec.layout]

	local centre = { pos = { 0, 0, 0 }, tag = "sqrb_ch_centre" }
	local mainEdges, sideEdges, legEdges, slipEdges, legs = {}, {}, {}, {}, {}
	local inner = {}
	if splitter then
		local mw = { pos = { -d, 0, 0 }, tag = "sqrb_ch_main_w" }
		local me = { pos = { d, 0, 0 }, tag = "sqrb_ch_main_e" }
		mainEdges[#mainEdges + 1] = S.straightEdge(mw.pos, me.pos, mw.tag, me.tag)
		inner[1], inner[3] = me, mw
		for _, i in ipairs(ch.LAYOUT_ARMS[spec.layout]) do
			local arm = lay.arms[i]
			if arm.road == "side" then
				local u = arm.u
				local splitPos = scale(u, hwM + sp.split)
				local splitTag = "sqrb_ch_split_" .. i
				-- right-hand traffic: the entry leg on the right of an inbound driver (left(u) side)
				local ePos = scale(left(u), d)
				local eNode = ePos[1] < 0 and mw or me
				local xNode = eNode == mw and me or mw
				local exit, entry = geom.legCurves(u, u, splitPos, sp.fork, xNode.pos, eNode.pos, 1, xNode.tag, eNode.tag, splitTag)
				exit.leg, entry.leg, exit.arm, entry.arm = "exit", "entry", i, i
				legEdges[#legEdges + 1] = exit
				legEdges[#legEdges + 1] = entry
				legs[#legs + 1] = { arm = i, entry = entry, exit = exit, split = splitPos }
				lay.legsByArm[i] = legs[#legs]
				inner[i] = { pos = splitPos, tag = splitTag }
			end
		end
	else
		for i = 1, 4 do inner[i] = centre end
	end

	-- slip nodes on every arm a slip lane leaves or joins (the set-backs do not depend on the
	-- layout, the slip lanes chosen or the traffic side: every corner has the same shape)
	local Lm, Ls = ch.setbacks(spec, sp, lay.legsByArm[2] and lay.legsByArm[2].exit)
	local slipNode = {}
	for _, s in ipairs(slipSet) do
		for _, i in ipairs(s) do
			if not slipNode[i] then
				local L = lay.arms[i].road == "main" and Lm or Ls
				slipNode[i] = { pos = scale(lay.arms[i].u, L), tag = "sqrb_ch_slip_" .. i, L = L }
			end
		end
	end

	-- two-way arms: inner node -> slip node -> end
	for _, i in ipairs(ch.LAYOUT_ARMS[spec.layout]) do
		local arm = lay.arms[i]
		local into = arm.road == "main" and mainEdges or sideEdges
		local from = inner[i]
		local base
		if slipNode[i] then
			local n = slipNode[i]
			local e = S.straightEdge(from.pos, n.pos, from.tag, n.tag)
			e.arm = i
			into[#into + 1] = e
			from, base = n, n.L
		elseif splitter then
			base = arm.road == "main" and d + legHw or hwM + sp.split
		else
			base = arm.road == "main" and hwS or hwM
		end
		local e = S.straightEdge(from.pos, scale(arm.u, base + armLength), from.tag, nil)
		e.arm = i
		into[#into + 1] = e
	end

	-- slip lanes
	for _, s in ipairs(slipSet) do
		local a, b = s[1], s[2]
		local na, nb = slipNode[a], slipNode[b]
		local e = ch.slipEdge(lay.arms[a].u, na.L, lay.arms[b].u, nb.L, na.tag, nb.tag, ch.slipAngle(spec))
		e.from, e.to = a, b
		slipEdges[#slipEdges + 1] = e
	end

	local lists = {}
	lists[#lists + 1] = list("main", geom.ARM_TEMPLATES[spec.main], hwM, mainEdges)
	lists[#lists + 1] = list("side", geom.ARM_TEMPLATES[spec.side], hwS, sideEdges)
	if #legEdges > 0 then lists[#lists + 1] = list("legs", sp.leg.template, legHw, legEdges) end
	if #slipEdges > 0 then lists[#lists + 1] = list("slips", slipRoad.template, slipRoad.halfWidth, slipEdges) end

	local built = {
		lists = lists,
		slips = slipEdges,
		legs = legs,
		setback = { main = Lm, side = Ls },
		-- slip lane angle (degrees) and template from the engine data (ch.slipRule): source
		-- "engine" (accepted), "fallback" (nothing accepted yet: unverified) or nil (shipped 40 deg)
		slipAngle = ch.slipAngle(spec) / DEG,
		slipRoad = slipRoad,
		slipSource = select(3, ch.slipRule(spec)),
		spec = spec,
	}
	built.island = ch.islands(spec, built, lay)
	if spec.direction == geom.DIRECTION_CW then ch.mirror(built) end
	built.mirrored = spec.direction == geom.DIRECTION_CW
	return built
end

--- Triangle islands between each slip lane and its corner, and the splitter triangles between
-- the side road's legs; nil for Islands None (or nothing that fits).
function ch.islands(spec, built, lay)
	local kind = ch.ISLAND_KINDS[spec.island]
	if kind == geom.ISLAND_NONE then return nil end
	local faces, colliders = {}, {}
	for _, e in ipairs(built.slips) do
		local poly, ua, ub, hwa, hwb = cornerIsland(lay, e.from, e.to, e)
		if poly then
			faces[#faces + 1] = geom.face(kind, poly)
			colliders[#colliders + 1] = cornerCollider(poly, ua, ub, hwa, hwb)
		end
	end
	local limit = geom.ARM_HALF_WIDTH[spec.main] + geom.ISLAND_MARGIN
	for _, leg in ipairs(built.legs) do
		local u = lay.arms[leg.arm].u
		local tri = geom.legTriangle(leg, lay.legHw, 1, function(p) return dot(p, u) >= limit end)
		if tri then faces[#faces + 1] = geom.face(kind, tri) end
	end
	if #faces == 0 then return nil end
	return { kind = kind, faces = faces, colliders = colliders, models = {} }
end

--- Left-hand traffic: the right-hand layout mirrored in x (x -> -x). Every edge keeps its
-- direction (a one-way road still runs from its p0 to its p1); outlines turn CCW again.
function ch.mirror(built)
	geom.mirrorX(built)
	for _, leg in ipairs(built.legs) do leg.split = S.mirrorX(leg.split) end
end

return ch
