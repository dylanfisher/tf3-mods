-- square_smart_lanes test fixtures: street templates (laneConfigs as logged by the probe and as in
-- .cache/game/base/content/infrastructure/street/**.street_template.lua) and ring worlds.
-- Loaded by the test files with dofile; returns a table.

local F = {}

-- lane codes: S sidewalk, V car lane, T car+tram lane, U bus lane (BUS+TRUCK, no CAR), - shoulder,
-- O tram-only track. Upper case first letter "F"/"B" = forward.
local function lanes(spec)
	local out = {}
	for item in spec:gmatch("%S+") do
		local dir, kind = item:sub(1, 1), item:sub(2, 2)
		local l = { forward = dir == "F", road = false, car = false, tram = false, walk = kind == "S" }
		if kind == "V" then l.road, l.car = true, true
		elseif kind == "T" then l.road, l.car, l.tram = true, true, true
		elseif kind == "U" then l.road = true
		elseif kind == "O" then l.tram = true end
		out[#out + 1] = l
	end
	return out
end
F.lanes = lanes

F.TPL = {
	one_way_small = "BS FV FV FS",              -- town_new_one_way_small (2 lanes)
	one_way_medium = "BS FV FV FV FV FS",       -- town_new_one_way_medium (4 lanes)
	highway_small = "B- FV F-",                 -- highway_new_small (1 lane)
	one_way_small_tram = "BS FV FT FS",         -- town_new_one_way_small_tram_electrified
	one_way_small_bus = "BS FV FU FS",          -- bus lane on the kerb side
	small = "BS BV FV FS",                      -- town_new_small / country_new_small
	medium = "BS BV BV FV FV FS",               -- town_new_medium
	large = "BS BV BV BV FV FV FV FS",          -- town_new_large
	medium_bus = "BS BU BV FV FU FS",           -- town_new_medium_bus
	small_tram = "BS BT FT FS",                 -- town_new_small_tram
	one_way_leg = "BS FV FV FS",                -- splitter leg (town_new_one_way_xsmall)
	tram_only = "BS BO FO FS",
	highway_ramp2 = "B- FV FV F-",              -- 2-lane one-way ramp, no sidewalk
	one_way_town1 = "BS FV FS",                 -- 1-lane one-way town street (sidewalks)
}

--- Reverses a template's lane order (the mirror image of the street: left-hand traffic).
function F.mirrorLanes(list)
	local out = {}
	for i = #list, 1, -1 do
		local l = list[i]
		out[#out + 1] = { forward = l.forward, road = l.road, car = l.car, tram = l.tram, walk = l.walk }
	end
	return out
end

--- A world from node and segment tables (the sl_ring world interface).
function F.world(nodes, segs)
	local W = { nodes = nodes, segs = segs }
	-- node.segs from the segments
	for _, n in pairs(nodes) do n.segs = {} end
	local ids = {}
	for id in pairs(segs) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local s = segs[id]
		s.id = id
		s.p0 = s.p0 or { x = nodes[s.node0].x, y = nodes[s.node0].y }
		s.p1 = s.p1 or { x = nodes[s.node1].x, y = nodes[s.node1].y }
		if not s.t0 then
			s.t0 = { x = s.p1.x - s.p0.x, y = s.p1.y - s.p0.y }
			s.t1 = { x = s.t0.x, y = s.t0.y }
		end
		table.insert(nodes[s.node0].segs, id)
		table.insert(nodes[s.node1].segs, id)
	end
	function W.node(id) return nodes[id] end
	function W.seg(id) return segs[id] end
	return W
end

--- Tangent of an arc from angle a0 to a1 (radians, signed sweep) on a circle of radius r, at angle a.
local function arcTangent(r, a, sweep)
	local len = math.abs(sweep) * r
	local s = sweep > 0 and 1 or -1
	return { x = -math.sin(a) * len * s, y = math.cos(a) * len * s }
end

--- A roundabout world.
-- opt: arms = list of arm specs (one per arm, in angle order, nil = no arm at that ring node), each
--   { tpl = "small", flip = bool (arm segment drawn from the far node), splitter = bool, through = bool }
-- ringTpl, radius (default 30), dir "ccw"/"cw", flipRing (ring segments drawn against travel,
-- lanes forward=false), extraNodes (plain ring nodes between arms), cx, cy, mirror (left-hand
-- traffic: reflect y and reverse every template).
-- Node ids: ring nodes 1.., far nodes 100+, centre node 900; segment ids: ring 1000+, arms 2000+,
-- legs 3000+, through 4000+.
function F.ring(opt)
	local nodes, segs = {}, {}
	local r = opt.radius or 30
	local cx, cy = opt.cx or 0, opt.cy or 0
	local ccw = (opt.dir or "ccw") == "ccw"
	local ringLanes = lanes(F.TPL[opt.ringTpl or "one_way_small"])
	local arms = opt.arms or {}
	-- ring positions: one entry per arm, splitter arms get two nodes (exit X, then entry E in travel)
	local slots = {}
	local nArms = #arms
	for k = 1, nArms do
		local base = 2 * math.pi * (k - 1) / nArms
		local a = arms[k]
		if a and a.splitter then
			local d = 0.25 * (ccw and 1 or -1)
			slots[#slots + 1] = { angle = base - d, arm = a, role = "X", k = k }
			slots[#slots + 1] = { angle = base + d, arm = a, role = "E", k = k }
		else
			slots[#slots + 1] = { angle = base, arm = a, role = "A", k = k }
		end
		-- extraNodes plain ring nodes evenly between this arm and the next
		local nx = opt.extraNodes or 0
		for k2 = 1, nx do
			local step = 2 * math.pi / nArms
			slots[#slots + 1] = { angle = base + step * k2 / (nx + 1), role = "P" }
		end
	end
	if not ccw then
		-- clockwise: travel order is decreasing angle; keep slot order = travel order
		table.sort(slots, function(p, q) return p.angle > q.angle end)
	else
		table.sort(slots, function(p, q) return p.angle < q.angle end)
	end
	for i, sl in ipairs(slots) do
		sl.id = i
		nodes[i] = { id = i, x = cx + r * math.cos(sl.angle), y = cy + r * math.sin(sl.angle) }
	end
	-- ring segments in travel order
	for i, sl in ipairs(slots) do
		local nx = slots[(i % #slots) + 1]
		local a0, a1 = sl.angle, nx.angle
		local sweep = a1 - a0
		if ccw and sweep <= 0 then sweep = sweep + 2 * math.pi end
		if (not ccw) and sweep >= 0 then sweep = sweep - 2 * math.pi end
		local t0, t1 = arcTangent(r, a0, sweep), arcTangent(r, a0 + sweep, sweep)
		local sid = 1000 + i
		if opt.flipRing then
			local l = {}
			for _, x in ipairs(ringLanes) do l[#l + 1] = { forward = false, road = x.road, car = x.car, tram = x.tram } end
			-- drawn from the next node back: laneConfigs reversed (left/right swap with the drawing direction)
			local rev = {}
			for j = #l, 1, -1 do rev[#rev + 1] = l[j] end
			segs[sid] = { node0 = nx.id, node1 = sl.id, lanes = rev,
				t0 = { x = -t1.x, y = -t1.y }, t1 = { x = -t0.x, y = -t0.y } }
		else
			segs[sid] = { node0 = sl.id, node1 = nx.id, lanes = ringLanes, t0 = t0, t1 = t1 }
		end
	end
	-- arms
	local far = 100
	for _, sl in ipairs(slots) do
		local a = sl.arm
		if a and not a.splitter then
			far = far + 1
			local ang = sl.angle
			nodes[far] = { id = far, x = cx + (r + 40) * math.cos(ang), y = cy + (r + 40) * math.sin(ang) }
			local l = lanes(F.TPL[a.tpl or "small"])
			if a.flip then
				segs[2000 + sl.id] = { node0 = far, node1 = sl.id, lanes = l }
			else
				segs[2000 + sl.id] = { node0 = sl.id, node1 = far, lanes = l }
			end
			if a.through then
				nodes[900] = nodes[900] or { id = 900, x = cx, y = cy }
				segs[4000 + sl.id] = { node0 = sl.id, node1 = 900, lanes = lanes(F.TPL.small) }
			end
		end
	end
	-- splitter: X -> S (exit leg), S -> E (entry leg), S -> far (two-way arm)
	local byK = {}
	for _, sl in ipairs(slots) do
		if sl.arm and sl.arm.splitter then
			byK[sl.k] = byK[sl.k] or {}
			byK[sl.k][sl.role] = sl
		end
	end
	for k, pair in pairs(byK) do
		local base = (pair.X.angle + pair.E.angle) / 2
		local sId, fId = 200 + k, 300 + k
		nodes[sId] = { id = sId, x = cx + (r + 25) * math.cos(base), y = cy + (r + 25) * math.sin(base) }
		nodes[fId] = { id = fId, x = cx + (r + 70) * math.cos(base), y = cy + (r + 70) * math.sin(base) }
		local leg = lanes(F.TPL[pair.X.arm.legTpl or "one_way_leg"])
		segs[3000 + pair.X.id] = { node0 = pair.X.id, node1 = sId, lanes = leg }
		segs[3000 + pair.E.id] = { node0 = sId, node1 = pair.E.id, lanes = leg }
		segs[2000 + sId] = { node0 = sId, node1 = fId, lanes = lanes(F.TPL[pair.X.arm.tpl or "medium"]) }
	end
	if opt.mirror then
		for _, n in pairs(nodes) do n.y = -n.y end
		for _, s in pairs(segs) do
			s.lanes = F.mirrorLanes(s.lanes)
			if s.t0 then
				s.t0 = { x = s.t0.x, y = -s.t0.y }
				s.t1 = { x = s.t1.x, y = -s.t1.y }
			end
		end
	end
	local W = F.world(nodes, segs)
	W.slots = slots
	return W
end

--- Roundabout Interchange quarter (in game 2026-10-11, square_roundabouts, ring 63759, right-hand
-- traffic): a 2-lane ring with an entry-only junction for a 1-lane on-ramp (node 63772), the next
-- junction downstream a 3-lane arm (node 63771, arm 127589), a 1-lane off-ramp (so the ring gets no
-- exit-only lane: turbo_reason=narrow_exit, as in game) and another 3-lane arm. Arms in angle order
-- {large, ramp in, large, ramp out}: the ramp's next junction downstream is a 3-lane arm in both ring
-- directions. opt: dir, mirror, ringTpl, rampTpl (the on-ramp), nextTpl / nextFlip (the junction after
-- the ramp), outTpl (the off-ramp).
function F.interchange(opt)
	opt = opt or {}
	local ccw = (opt.dir or "ccw") == "ccw"
	local nextArm = { tpl = opt.nextTpl or "large", flip = opt.nextFlip }
	local arms = { { tpl = "large" }, { tpl = opt.rampTpl or "highway_small", flip = true }, { tpl = "large" },
		{ tpl = opt.outTpl or "highway_small" } }
	if ccw then arms[3] = nextArm else arms[1] = nextArm end
	return F.ring({ ringTpl = opt.ringTpl or "one_way_small", arms = arms, dir = opt.dir, mirror = opt.mirror })
end

---------------------------------------------------------------------------
-- Slip-lane junctions (sl_slip.lua)

local function lanesFor(spec, mirror)
	local l = F.lanes(spec)
	if mirror then l = F.mirrorLanes(l) end
	return l
end

local function scaleV(v, k) return { x = v.x * k, y = v.y * k } end

--- World from nodes {id = {x, y}} and segs {id = {node0, node1, tpl, t0dir, t1dir}} (t dirs are
-- unit directions, scaled to the chord length). mirror: left-hand traffic (x -> -x, lanes reversed).
function F.build(nodes, segs, mirror)
	local N, S = {}, {}
	local sx = mirror and -1 or 1
	for id, p in pairs(nodes) do N[id] = { id = id, x = sx * p[1], y = p[2] } end
	for id, s in pairs(segs) do
		local a, b = N[s[1]], N[s[2]]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		local seg = { node0 = s[1], node1 = s[2], lanes = lanesFor(s[3], mirror) }
		if s[4] then
			seg.t0 = scaleV({ x = sx * s[4][1], y = s[4][2] }, len)
			seg.t1 = scaleV({ x = sx * s[5][1], y = s[5][2] }, len)
		end
		S[id] = seg
	end
	return F.world(N, S)
end

function F.dir(deg) return { math.cos(math.rad(deg)), math.sin(math.rad(deg)) } end

--- Channelized Junction, layout T, near-side slip lanes (square_roundabouts_channel.lua ch.build:
-- main road east-west, side road north, slip lanes {east -> north} and {north -> west}, straight
-- two-way arms drawn from the inner node out, slip edges ch.slipEdge with the slip angle).
-- Nodes: 1 centre, 2 east slip node, 3 west slip node, 4 north slip node, 5/6/7 arm ends.
-- Segments: 11 centre-east, 12 east arm, 13 centre-west, 14 west arm, 15 centre-north,
-- 16 north arm, 21 slip east -> north, 22 slip north -> west.
function F.channelT(opt)
	opt = opt or {}
	local Lm, Ls = opt.Lm or 40, opt.Ls or 35
	local a = math.rad(opt.angle or 40)
	local ca, sa = math.cos(a), math.sin(a)
	local main, side, slip = opt.main or F.TPL.medium, opt.side or F.TPL.small, opt.slip or F.TPL.one_way_leg
	local nodes = {
		[1] = { 0, 0 }, [2] = { Lm, 0 }, [3] = { -Lm, 0 }, [4] = { 0, Ls },
		[5] = { Lm + 30, 0 }, [6] = { -Lm - 30, 0 }, [7] = { 0, Ls + 30 },
	}
	local segs = {
		[11] = { 1, 2, main }, [12] = { 2, 5, main }, [13] = { 1, 3, main }, [14] = { 3, 6, main },
		[15] = { 1, 4, side }, [16] = { 4, 7, side },
		-- slipEdge(ua, La, ub, Lb): t0 = -cos(a) ua + sin(a) ub, t1 = cos(a) ub - sin(a) ua
		[21] = { 2, 4, slip, { -ca, sa }, { -sa, ca } },  -- ua = east, ub = north
		[22] = { 4, 3, slip, { -sa, -ca }, { -ca, -sa } }, -- ua = north, ub = west
	}
	return F.build(nodes, segs, opt.mirror)
end

--- Channelized Junction, layout X, near-side slip lanes (square_roundabouts_channel.lua ch.build,
-- SLIP_SETS near X: {east -> north}, {north -> west}, {west -> south}, {south -> east}; no splitter
-- islands): F.channelT plus a south arm. Every arm's slip node has one slip lane leaving and one joining.
-- Nodes: 1 centre, 2 east, 3 west, 4 north, 8 south slip node, 5/6/7/9 arm ends.
-- Segments: 11 centre-east, 12 east arm, 13 centre-west, 14 west arm, 15 centre-north, 16 north arm,
-- 17 centre-south, 18 south arm; slips 21 east -> north, 22 north -> west, 23 west -> south,
-- 24 south -> east. opt as F.channelT (side: the north-south road).
function F.channelX(opt)
	opt = opt or {}
	local Lm, Ls = opt.Lm or 40, opt.Ls or 35
	local a = math.rad(opt.angle or 40)
	local ca, sa = math.cos(a), math.sin(a)
	local main, side, slip = opt.main or F.TPL.medium, opt.side or F.TPL.small, opt.slip or F.TPL.one_way_leg
	local nodes = {
		[1] = { 0, 0 }, [2] = { Lm, 0 }, [3] = { -Lm, 0 }, [4] = { 0, Ls }, [8] = { 0, -Ls },
		[5] = { Lm + 30, 0 }, [6] = { -Lm - 30, 0 }, [7] = { 0, Ls + 30 }, [9] = { 0, -Ls - 30 },
	}
	local segs = {
		[11] = { 1, 2, main }, [12] = { 2, 5, main }, [13] = { 1, 3, main }, [14] = { 3, 6, main },
		[15] = { 1, 4, side }, [16] = { 4, 7, side }, [17] = { 1, 8, side }, [18] = { 8, 9, side },
		-- slipEdge(ua, La, ub, Lb): t0 = -cos(a) ua + sin(a) ub, t1 = cos(a) ub - sin(a) ua
		[21] = { 2, 4, slip, { -ca, sa }, { -sa, ca } },   -- ua = east, ub = north
		[22] = { 4, 3, slip, { -sa, -ca }, { -ca, -sa } }, -- ua = north, ub = west
		[23] = { 3, 8, slip, { ca, -sa }, { sa, -ca } },   -- ua = west, ub = south
		[24] = { 8, 2, slip, { sa, ca }, { ca, sa } },     -- ua = south, ub = east
	}
	return F.build(nodes, segs, opt.mirror)
end

--- A main road along +x through the merge node 1 with a ramp joining at 30 deg from the kerb side
-- (the right of eastbound traffic; mirror: left-hand traffic, everything reflected), for the merge
-- look-ahead (sl_walk.lua, sl_slip S.mergeLook). Lane templates of the main road are in travel order
-- (drawn west to east, so two-way templates have their eastbound lanes forward).
-- opt: up = { {tpl, len}, ... } from node 1 back upstream (first = the through segment), down = { {tpl,
--   len}, ... } from node 1 on, ramp (template, default 1-lane highway), upJunction (a side road at
--   the far upstream node: a 3-road junction there), downExit = "right" | "left" (an off-ramp at the
--   far downstream node, the main road continuing), mirror.
-- Node ids: 1 merge node, 4 ramp start, upstream 101, 102, ... (101 nearest), downstream 201, 202, ...;
-- segments: ramp 33, upstream 301, 302, ..., downstream 401, 402, ..., junction extras 34-37.
function F.mergeLine(opt)
	local nodes, segs = { [1] = { 0, 0 } }, {}
	local d = F.dir(30)
	nodes[4] = { -50 * d[1], -50 * d[2] }
	segs[33] = { 4, 1, opt.ramp or F.TPL.highway_small, d, d }
	local x, prev = 0, 1
	for k, sp in ipairs(opt.up or {}) do
		x = x - sp[2]
		nodes[100 + k] = { x, 0 }
		segs[300 + k] = { 100 + k, prev, sp[1] }
		prev = 100 + k
	end
	if opt.upJunction then
		local tpl = opt.up[#opt.up][1]
		nodes[8] = { x - 60, 0 }
		nodes[5] = { x, -60 }
		segs[37] = { 8, prev, tpl }
		segs[34] = { prev, 5, F.TPL.small }
	end
	x, prev = 0, 1
	for k, sp in ipairs(opt.down or {}) do
		x = x + sp[2]
		nodes[200 + k] = { x, 0 }
		segs[400 + k] = { prev, 200 + k, sp[1] }
		prev = 200 + k
	end
	if opt.downExit then
		local tpl = opt.down[#opt.down][1]
		local e = F.dir(opt.downExit == "left" and 30 or -30)
		nodes[7] = { x + 80, 0 }
		nodes[6] = { x + 50 * e[1], 50 * e[2] }
		segs[36] = { prev, 7, tpl }
		segs[35] = { prev, 6, F.TPL.highway_small, e, e }
	end
	return F.build(nodes, segs, opt.mirror)
end

--- A main road along +x through the diverge node 1 with an off-ramp leaving at 30 deg to the kerb side
-- (the right of eastbound traffic; branch = "left": a left exit; mirror: left-hand traffic, everything
-- reflected), for the exit-only look-ahead (sl_slip S.divergeLook). Lane templates of the main road
-- are in travel order (drawn west to east, so two-way templates have their eastbound lanes forward).
-- opt: up = { {tpl, len}, ... } from node 1 back upstream (first = the main road's in segment), down =
--   { {tpl, len}, ... } from node 1 on (first = the through segment), ramp (template, default 1-lane
--   highway), branch "right" | "left", upJunction (a side road at the far upstream node), mirror.
-- Node ids: 1 diverge node, 4 ramp end, upstream 101, 102, ..., downstream 201, 202, ...; segments:
-- ramp 33, upstream 301, ..., downstream 401, ..., junction extras 34, 37.
function F.divergeLine(opt)
	local nodes, segs = { [1] = { 0, 0 } }, {}
	local d = F.dir(opt.branch == "left" and 30 or -30)
	nodes[4] = { 50 * d[1], 50 * d[2] }
	segs[33] = { 1, 4, opt.ramp or F.TPL.highway_small, d, d }
	local x, prev = 0, 1
	for k, sp in ipairs(opt.up or {}) do
		x = x - sp[2]
		nodes[100 + k] = { x, 0 }
		segs[300 + k] = { 100 + k, prev, sp[1] }
		prev = 100 + k
	end
	if opt.upJunction then
		local tpl = opt.up[#opt.up][1]
		nodes[8] = { x - 60, 0 }
		nodes[5] = { x, -60 }
		segs[37] = { 8, prev, tpl }
		segs[34] = { prev, 5, F.TPL.small }
	end
	x, prev = 0, 1
	for k, sp in ipairs(opt.down or {}) do
		x = x + sp[2]
		nodes[200 + k] = { x, 0 }
		segs[400 + k] = { prev, 200 + k, sp[1] }
		prev = 200 + k
	end
	return F.build(nodes, segs, opt.mirror)
end

--- A two-way main road along x through node 1 (segments 11 west: 1 -> 2, 12 east: 1 -> 3, both drawn
-- from node 1 out; template `main`, default town large 3+3) with one-way ramps at node 1 that leave
-- (or join) at tangent heading `tan` there (degrees ccw from +x, pointing away from node 1, as the
-- game log's seg@heading) and run on at heading `far` beyond a short stub (in game 2026-10-11: ramps
-- peeling off alongside a 3+3 road whose tangents at the node were 80-100 deg off it).
-- ramps: list of { id, leaving (true: traffic leaves node 1 on it), tan, far, tpl (default 2-lane
-- ramp), stub (m, default 8), len (m beyond the stub, default 70) }. Ramp k: plain node 40 + k, far
-- node 50 + k; the stub is segment id, the rest id + 100. extra: { [segId] = { node, x, y, tpl } }
-- two-way side roads drawn from node 1 out to a new node. mirror: left-hand traffic.
F.RAMP2 = "B- FV FV F-"
F.RAMP4 = "B- FV FV FV FV F-"
function F.rampNode(opt)
	local main = opt.main or F.TPL.large
	local nodes = { [1] = { 0, 0 }, [2] = { -100, 0 }, [3] = { 100, 0 } }
	local segs = { [11] = { 1, 2, main }, [12] = { 1, 3, main } }
	for k, r in ipairs(opt.ramps or {}) do
		local tpl, stub, len = r.tpl or F.RAMP2, r.stub or 8, r.len or 70
		local t, f = F.dir(r.tan), F.dir(r.far)
		local mx, my = t[1] + f[1], t[2] + f[2]
		local ml = math.sqrt(mx * mx + my * my)
		local P = { stub * mx / ml, stub * my / ml }
		local Q = { P[1] + len * f[1], P[2] + len * f[2] }
		nodes[40 + k], nodes[50 + k] = P, Q
		local back, tback = F.dir(r.far + 180), F.dir(r.tan + 180)
		if r.leaving then
			segs[r.id] = { 1, 40 + k, tpl, t, f }
			segs[r.id + 100] = { 40 + k, 50 + k, tpl, f, f }
		else
			segs[r.id + 100] = { 50 + k, 40 + k, tpl, back, back }
			segs[r.id] = { 40 + k, 1, tpl, back, tback }
		end
	end
	for id, e in pairs(opt.extra or {}) do
		nodes[e[1]] = { e[2], e[3] }
		segs[id] = { 1, e[1], e[4] or main }
	end
	return F.build(nodes, segs, opt.mirror)
end

--- Adds every node and segment of world `other` to `world` (both F.world results; ids must not
-- collide). Returns world.
function F.merge(world, other)
	for id, n in pairs(other.nodes) do world.nodes[id] = n end
	for id, s in pairs(other.segs) do world.segs[id] = s end
	return world
end

--- A copy of world `w` (an F.world result) with every node and segment id raised by `base` and every
-- position moved by (dx, dy), so several copies of one fixture fit in one world (benchmarks).
function F.shift(w, base, dx, dy)
	local nodes, segs = {}, {}
	for id, n in pairs(w.nodes) do nodes[id + base] = { id = id + base, x = n.x + dx, y = n.y + dy } end
	for id, s in pairs(w.segs) do
		segs[id + base] = { node0 = s.node0 + base, node1 = s.node1 + base, lanes = s.lanes,
			p0 = { x = s.p0.x + dx, y = s.p0.y + dy }, p1 = { x = s.p1.x + dx, y = s.p1.y + dy },
			t0 = s.t0 and { x = s.t0.x, y = s.t0.y }, t1 = s.t1 and { x = s.t1.x, y = s.t1.y } }
	end
	return F.world(nodes, segs)
end

--- A grid of g x g nodes `gap` m apart (ids base + i * g + j) joined by one-way roads (template
-- tpl, default one-way small): rows run east, columns north, or (alternate) every other row / column
-- the other way (one-way blocks: cycles everywhere, kinked). Segment ids from base + g * g + 1.
function F.oneWayGrid(g, gap, base, alternate, tpl)
	tpl = tpl or F.TPL.one_way_small
	local nodes, segs = {}, {}
	local function id(i, j) return base + i * g + j end
	for i = 0, g - 1 do
		for j = 0, g - 1 do nodes[id(i, j)] = { i * gap, j * gap } end
	end
	local sid = base + g * g
	for i = 0, g - 1 do
		for j = 0, g - 1 do
			if i < g - 1 then
				sid = sid + 1
				if alternate and j % 2 == 1 then segs[sid] = { id(i + 1, j), id(i, j), tpl }
				else segs[sid] = { id(i, j), id(i + 1, j), tpl } end
			end
			if j < g - 1 then
				sid = sid + 1
				if alternate and i % 2 == 1 then segs[sid] = { id(i, j + 1), id(i, j), tpl }
				else segs[sid] = { id(i, j), id(i, j + 1), tpl } end
			end
		end
	end
	return F.build(nodes, segs)
end

---------------------------------------------------------------------------
-- Real data from the probe log (game stdout.txt, [SQRB-LANES] lines, 2026-10-08)

local function parseConns(text)
	local out = {}
	for s0, l0, s1, l1, rt in text:gmatch("(%d+):(%d+)>(%d+):(%d+):(%S%S)") do
		out[#out + 1] = { segment0 = tonumber(s0), lane0 = tonumber(l0), segment1 = tonumber(s1),
			lane1 = tonumber(l1), withRoad = rt:sub(1, 1) == "R", withTram = rt:sub(2, 2) == "T" }
	end
	return out
end
F.parseConns = parseConns

--- Probe ring: nodes (id, x, y) in travel order, ring segments (id, node0, node1), arms (node -> seg, far).
local function probeRing(def)
	local nodes, segs = {}, {}
	local cx, cy = def.cx, def.cy
	for _, n in ipairs(def.nodes) do nodes[n[1]] = { id = n[1], x = n[2], y = n[3] } end
	local r = math.sqrt((def.nodes[1][2] - cx) ^ 2 + (def.nodes[1][3] - cy) ^ 2)
	for _, s in ipairs(def.ring) do
		local a0 = math.atan(nodes[s[2]].y - cy, nodes[s[2]].x - cx)
		local a1 = math.atan(nodes[s[3]].y - cy, nodes[s[3]].x - cx)
		local sweep = a1 - a0
		if sweep <= 0 then sweep = sweep + 2 * math.pi end
		segs[s[1]] = { node0 = s[2], node1 = s[3], lanes = lanes(def.ringTpl),
			t0 = arcTangent(r, a0, sweep), t1 = arcTangent(r, a1, sweep) }
	end
	for _, a in ipairs(def.arms) do
		local n = nodes[a[1]]
		local dx, dy = n.x - cx, n.y - cy
		nodes[a[3]] = { id = a[3], x = n.x + dx, y = n.y + dy }
		segs[a[2]] = { node0 = a[1], node1 = a[3], lanes = lanes(def.armTpl) }
	end
	return F.world(nodes, segs)
end

-- build 1: 2-lane ring (town_new_one_way_small), small arms (town_new_small), CCW
F.PROBE_2LANE_SMALL = {
	world = function()
		return probeRing({ cx = -128.7, cy = -1511.3, ringTpl = F.TPL.one_way_small, armTpl = F.TPL.small,
			nodes = { { 17955, -99.7, -1511.3 }, { 17959, -128.7, -1482.3 }, { 17965, -157.7, -1511.3 }, { 17973, -128.7, -1540.3 } },
			ring = { { 18141, 17955, 17959 }, { 18142, 17959, 17965 }, { 18143, 17965, 17973 }, { 18144, 17973, 17955 } },
			arms = { { 17955, 18164, 18137 }, { 17959, 18191, 18138 }, { 17965, 18586, 18139 }, { 17973, 18593, 18140 } } })
	end,
	conns = { [17955] = parseConns("18144:1>18141:2:R-,18144:1>18164:2:R-,18144:2>18141:1:R-,18164:1>18141:1:R-,18164:1>18141:2:R-") },
}

-- build 2: 2-lane ring, medium arms (town_new_medium), CCW
F.PROBE_2LANE_MEDIUM = {
	world = function()
		return probeRing({ cx = -334.1, cy = -1512.3, ringTpl = F.TPL.one_way_small, armTpl = F.TPL.medium,
			nodes = { { 19132, -305.1, -1512.3 }, { 19133, -334.1, -1483.3 }, { 19134, -363.1, -1512.3 }, { 19145, -334.1, -1541.3 } },
			ring = { { 19600, 19132, 19133 }, { 19883, 19133, 19134 }, { 19939, 19134, 19145 }, { 20359, 19145, 19132 } },
			arms = { { 19132, 20602, 19224 }, { 19133, 20606, 19348 }, { 19134, 20607, 19398 }, { 19145, 20608, 19545 } } })
	end,
	conns = { [19132] = parseConns("20359:1>19600:2:R-,20359:1>20602:3:R-,20359:1>20602:4:R-,20359:2>19600:1:R-,20602:1>19600:2:R-,20602:2>19600:1:R-") },
}

-- build 4: 4-lane ring (town_new_one_way_medium), medium arms, CCW
F.PROBE_4LANE_MEDIUM = {
	world = function()
		return probeRing({ cx = -246.6, cy = -1692.1, ringTpl = F.TPL.one_way_medium, armTpl = F.TPL.medium,
			nodes = { { 22768, -215.6, -1692.1 }, { 23292, -246.6, -1661.1 }, { 23293, -277.6, -1692.1 }, { 23294, -246.6, -1723.1 } },
			ring = { { 23299, 22768, 23292 }, { 23300, 23292, 23293 }, { 23301, 23293, 23294 }, { 23302, 23294, 22768 } },
			arms = { { 22768, 23303, 23295 }, { 23292, 23304, 23296 }, { 23293, 23398, 23297 }, { 23294, 23399, 23298 } } })
	end,
	conns = {
		[22768] = parseConns("23302:1>23299:4:R-,23302:2>23299:3:R-,23302:3>23299:2:R-,23302:4>23299:1:R-,23302:1>23303:3:R-,23302:1>23303:4:R-,23303:1>23299:3:R-,23303:1>23299:4:R-,23303:2>23299:1:R-,23303:2>23299:2:R-"),
		[23294] = parseConns("23301:1>23302:4:R-,23301:2>23302:3:R-,23301:3>23302:2:R-,23301:4>23302:1:R-,23399:1>23302:3:R-,23399:1>23302:4:R-,23399:2>23302:1:R-,23399:2>23302:2:R-,23301:1>23399:3:R-,23301:1>23399:4:R-"),
	},
}

return F
