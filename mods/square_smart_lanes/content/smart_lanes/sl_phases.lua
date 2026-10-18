-- Smart Lanes: conflict map of a lit junction's movements (pure, no api.* calls), unit-tested in
-- tests/square_smart_lanes/test_phases.lua. Step 1 of PHASES_PLAN.md (designed traffic light phases):
-- which lane connections and crosswalks of one node must never be green in the same phase.
--
-- TF3 has no permissive turn: a connection unlocked in a phase drives as if it had green and never
-- gives way (docs/findings.md "A connection unlocked in a phase does not give way"), so a phase is
-- safe only when no two of its green entries conflict.
--
-- Indices are the phases' own (findings.md "Traffic light phases index the lane connections"):
-- 0-based, the node's laneConnections in config order, then its crosswalks (#conns + k - 1 for
-- crosswalk k). The relation is symmetric; an entry never conflicts with itself.
--
-- Model (a disk with ports on its rim):
--   * Every lane end at the node is a port on the rim. The arms are ordered counter-clockwise by the
--     angle of their direction away from the node; within an arm the lanes are ordered by their
--     connection index, which counts from left to right looking from the node out along the road
--     (api/tealdef/api/type.d.tl:1201-1208 LaneConnection lane0 / lane1), so going counter-clockwise
--     the index falls. This is the traffic side by itself: in right-hand traffic the incoming lanes
--     have the lower indices (sl_cross sideOf), so they lie counter-clockwise of the outgoing ones and
--     the outgoing lanes run kerb lane first (sl_cross ex.o, kerbFirst); in left-hand traffic the
--     other way round. No side flag is needed, and lanes that are in no list (bus, tram) still have
--     a place.
--   * A connection is a path inside the disk from its entry port (segment0, lane0) to its exit port
--     (segment1, lane1). Two paths with four different ports cross exactly when their ports
--     interleave around the rim (one port of the second between the first's two ports, the other
--     outside): "cross". This also orders movements of one approach: side-by-side lanes into
--     different exits cross when their exits are swapped.
--   * Same exit port (same exit lane), different entry: "merge" (both enter one lane and neither
--     gives way). Same entry port: a lane splitting into several turns, the vehicles queue in one
--     lane: no conflict. Same entry and exit (a road and a tram connection of one lane pair): none.
--   * U-turns (segment0 == segment1): the interleaving only sees the ports the U-turn encloses, but a
--     U-turn swings into the junction's middle and back, cutting paths twice, which the rim order
--     cannot see. So by default (opts.uTurn ~= "chord") a U-turn conflicts ("cross") with every
--     connection of another approach that is no kerb turn; kerb turns hug their corner and keep the
--     rim rule (as L.kerbConflict: "a U-turn connection the game made that ends on E is caught by the
--     lane rule").
--   * "ped": a crosswalk is on the end of one arm (BaseNodeConfig.crosswalks: entities, inferred to be
--     the node's edge ids, findings.md "Crosswalk entries of a node config"). It conflicts with every
--     connection that enters or leaves by that arm. A crosswalk entity that is none of the arms (or a
--     missing one) is unknown: it conflicts with every connection (conservative, as L.kerbConflict).
--   * A connection on a segment with no arm angle is unknown: it crosses every connection that does
--     not share its entry port (conservative).
--
-- Agreement with sl_lights L.kerbConflict (the "When safe" free kerb turn): for a kerb turn A -> E
-- into exit lane l, the ports between its entry and exit are A's own kerbward entry lanes (none: it
-- starts in the kerb lane) and E's exit lanes nearer the kerb than l. So another approach's stream
-- ending in E nearer the kerb crosses it, one in lane l merges, one farther out runs beside it: the
-- same rule. L.kerbConflict calls the approach's own connections never a conflict; the map checks
-- their interleaving (none in sl_cross's lane rule or the game's default: each lane's exits are
-- contiguous). The one place the map is stricter: an arm with incoming lanes only that lies between
-- A and E (a one-way street entering inside the kerb corner): its movements cross the kerb turn,
-- which L.kerbConflict does not look at.
-- Since 2026-10-12 a "merge" with a kerb turn is accepted by "When safe" (sl_lights L.kerbPhases SAFE) and
-- by the planner's step 4b (sl_phaseplan); the map still reports it as "merge".
--
-- Bounded: at most P.MAX_CONNS connections, P.MAX_CROSS crosswalks and P.MAX_ARMS arms (else
-- refused, the caller keeps the game's phases); the pair loop is quadratic in that.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"

local P = {}

P.MAX_CONNS = 256
P.MAX_CROSS = 32
P.MAX_ARMS = 8
P.LANE_SPAN = 1024 -- port slots per arm (a lane index at or above it is unknown)

P.CROSS = "cross"
P.MERGE = "merge"
P.PED = "ped"

local atan2 = math.atan2 or math.atan

local function norm(deg)
	deg = deg % 360
	if deg < 0 then deg = deg + 360 end
	return deg
end
P.norm = norm

--- Angle (deg, counter-clockwise from +x, [0, 360)) of segment s's direction away from `node`: the
-- tangent at that end, else the chord (sl_cross awayDir). nil when s does not end at node.
function P.awayAngle(s, node)
	if s == nil then return nil end
	local e = Ring.endAt(s, node)
	if e == nil then return nil end
	local t, sign
	if e == 0 then t, sign = s.t0, 1 else t, sign = s.t1, -1 end
	local x, y
	if t and (t.x ~= 0 or t.y ~= 0) then x, y = t.x * sign, t.y * sign end
	if x == nil and s.p0 and s.p1 then x, y = (s.p1.x - s.p0.x) * sign, (s.p1.y - s.p0.y) * sign end
	if x == nil or (x == 0 and y == 0) then return nil end
	return norm(math.deg(atan2(y, x)))
end

--- Arms of node n in an sl_ring world: { {seg, angle} } for every segment at the node with an angle.
function P.armsFromWorld(world, n)
	local out = {}
	local node = world and world.node(n)
	if node == nil then return out end
	for i, sid in ipairs(node.segs or {}) do
		if i > P.MAX_ARMS then break end
		local a = P.awayAngle(world.seg(sid), n)
		if a ~= nil then out[#out + 1] = { seg = sid, angle = a } end
	end
	return out
end

--- Arms of an sl_cross case "X" view from its turn angles alone (no world): the first approach at
-- 0 deg, then for every approach A and exit E (ap.allExits, ex.deg: signed turn, left positive)
-- angle(E) = angle(A) + 180 + deg, and back for approaches only reached through their exits.
-- Only the order and spacing matter. Bounded: at most P.MAX_ARMS + 1 passes.
function P.armsFromView(v)
	local angle, order = {}, {}
	local aps = (v and v.approaches) or {}
	local function note(seg)
		if angle[seg] == nil then order[#order + 1] = seg end
	end
	if #aps == 0 then return {} end
	note(aps[1].seg)
	angle[aps[1].seg] = 0
	for _ = 1, P.MAX_ARMS + 1 do
		local changed = false
		for _, ap in ipairs(aps) do
			for _, ex in ipairs(ap.allExits or ap.exits or {}) do
				if type(ex.deg) == "number" then
					if angle[ap.seg] ~= nil and angle[ex.seg] == nil then
						note(ex.seg)
						angle[ex.seg] = norm(angle[ap.seg] + 180 + ex.deg)
						changed = true
					elseif angle[ex.seg] ~= nil and angle[ap.seg] == nil then
						note(ap.seg)
						angle[ap.seg] = norm(angle[ex.seg] - 180 - ex.deg)
						changed = true
					end
				end
			end
		end
		if not changed then break end
	end
	local out = {}
	for _, seg in ipairs(order) do out[#out + 1] = { seg = seg, angle = angle[seg] } end
	return out
end

--- Movement class per connection (1-based, as conns) from an sl_cross view: the exit's category
-- ("kerb" | "straight" | "far", ap.allExits) or "u_turn" (segment0 == segment1); nil when the view
-- has no such movement.
function P.classesFromView(conns, v)
	local cat = {}
	for _, ap in ipairs((v and v.approaches) or {}) do
		for _, ex in ipairs(ap.allExits or ap.exits or {}) do
			cat[tostring(ap.seg) .. ">" .. tostring(ex.seg)] = ex.cat
		end
	end
	local out = {}
	for i, c in ipairs(conns or {}) do
		if c.segment0 == c.segment1 then out[i] = "u_turn"
		else out[i] = cat[tostring(c.segment0) .. ">" .. tostring(c.segment1)] end
	end
	return out
end

local function isLane(l)
	return type(l) == "number" and l == math.floor(l) and l >= 0 and l < P.LANE_SPAN
end

--- Builds the conflict map.
-- input = {
--   conns = { {segment0, lane0, segment1, lane1, withRoad, withTram}, ... } in config order,
--   arms = { {seg, angle}, ... } (angle: deg, direction away from the node; P.armsFromWorld /
--     P.armsFromView),
--   crosswalks = { entity, ... } in config order (nil: none),
--   cls = { [i] = "kerb" | "straight" | "far" | "u_turn" } per connection (1-based; optional:
--     P.classesFromView; only the U-turn rule reads it: a kerb turn keeps the rim rule),
--   uTurn = "strict" (default) | "chord" }
-- Returns M = { n, nCross, size = n + nCross, kinds = { [i] = { [j] = kind } } (0-based, both
-- directions), counts = { cross, merge, ped } (pairs), cwSeg = { [k] = arm segment or false },
-- unknown = { [i] = true } connections without a known arm or lane, cls, seg0 = { [i] = segment0 }
-- (0-based: the approach of each connection; sl_phaseplan's fan plans accept conflicts within one
-- approach), lane0 = { [i] = lane0 } (0-based: the entry lane, with seg0 the key of sl_phaseplan's
-- whole-lane rule), seg1 = { [i] = segment1 } (0-based: the exit), armAngle = { [seg] = angle } (deg,
-- normalized; sl_phaseplan's validator checks an axis plan's road pairs with them) }; or nil, reason
-- ("conns" | "crosswalks" | "arms": over a bound).
function P.build(input)
	input = input or {}
	local conns = input.conns or {}
	local cws = input.crosswalks or {}
	if #conns > P.MAX_CONNS then return nil, "conns" end
	if #cws > P.MAX_CROSS then return nil, "crosswalks" end
	local armList = input.arms or {}
	if #armList > P.MAX_ARMS then return nil, "arms" end
	-- arm rank by angle (ties by segment id)
	local sorted = {}
	for _, a in ipairs(armList) do
		if a.seg ~= nil and type(a.angle) == "number" then sorted[#sorted + 1] = { seg = a.seg, angle = norm(a.angle) } end
	end
	table.sort(sorted, function(p, q)
		if p.angle ~= q.angle then return p.angle < q.angle end
		return tostring(p.seg) < tostring(q.seg)
	end)
	local rank = {}
	for r, a in ipairs(sorted) do
		if rank[a.seg] == nil then rank[a.seg] = r - 1 end
	end
	local function port(seg, lane)
		local r = rank[seg]
		if r == nil or not isLane(lane) then return nil end
		return r * P.LANE_SPAN + (P.LANE_SPAN - 1 - lane)
	end
	local n = #conns
	local cls = input.cls or {}
	local strictU = input.uTurn ~= "chord"
	local M = { n = n, nCross = #cws, size = n + #cws, kinds = {}, counts = { cross = 0, merge = 0, ped = 0 },
		cwSeg = {}, unknown = {}, cls = cls, seg0 = {}, lane0 = {}, seg1 = {}, armAngle = {} }
	for _, a in ipairs(sorted) do
		if M.armAngle[a.seg] == nil then M.armAngle[a.seg] = a.angle end
	end
	local ent, ex = {}, {}
	for i, c in ipairs(conns) do
		M.seg0[i - 1], M.lane0[i - 1], M.seg1[i - 1] = c.segment0, c.lane0, c.segment1
		ent[i], ex[i] = port(c.segment0, c.lane0), port(c.segment1, c.lane1)
		if ent[i] == nil or ex[i] == nil then M.unknown[i - 1] = true end
	end
	for i = 0, M.size - 1 do M.kinds[i] = {} end
	local function set(i, j, kind)
		M.kinds[i][j] = kind
		M.kinds[j][i] = kind
		M.counts[kind] = M.counts[kind] + 1
	end
	local function between(x, lo, hi) return x > lo and x < hi end
	for i = 1, n do
		local c, pi, qi = conns[i], ent[i], ex[i]
		local ui = c.segment0 == c.segment1
		for j = i + 1, n do
			local d, pj, qj = conns[j], ent[j], ex[j]
			local kind = nil
			if pi == nil or qi == nil or pj == nil or qj == nil then
				-- unknown arm or lane: conservative, except a shared entry lane
				if not (c.segment0 == d.segment0 and c.lane0 == d.lane0) then kind = P.CROSS end
			elseif pi == pj then
				kind = nil -- one lane splitting (or the same path): queued, no conflict
			elseif qi == qj then
				kind = P.MERGE
			elseif pi == qj or qi == pj then
				kind = P.CROSS -- an entry lane that is also an exit lane: bad data, conservative
			else
				local lo, hi = math.min(pi, qi), math.max(pi, qi)
				if between(pj, lo, hi) ~= between(qj, lo, hi) then kind = P.CROSS end
				local uj = d.segment0 == d.segment1
				if kind == nil and strictU and c.segment0 ~= d.segment0 then
					if (ui and cls[j] ~= "kerb") or (uj and cls[i] ~= "kerb") then kind = P.CROSS end
				end
			end
			if kind ~= nil then set(i - 1, j - 1, kind) end
		end
	end
	-- crosswalks: the arm each one is on (false: unknown) and the connections using that arm
	for k, cw in ipairs(cws) do
		M.cwSeg[k] = (cw ~= nil and rank[cw] ~= nil) and cw or false
		local x = n + k - 1
		for i, c in ipairs(conns) do
			local seg = M.cwSeg[k]
			if seg == false or c.segment0 == seg or c.segment1 == seg then set(i - 1, x, P.PED) end
		end
	end
	return M
end

--- The conflict between 0-based entries i and j (connections, then crosswalks): "cross" | "merge" |
-- "ped" | nil.
function P.kind(M, i, j)
	local row = M and M.kinds[i]
	return row and row[j] or nil
end

--- Every conflict of entry i: { {j, kind} } sorted by j.
function P.conflictsOf(M, i)
	local out = {}
	for j, kind in pairs((M and M.kinds[i]) or {}) do out[#out + 1] = { j, kind } end
	table.sort(out, function(a, b) return a[1] < b[1] end)
	return out
end

--- The conflicting pairs green together in one phase. locked: the phase's lockedLanes (0-based).
-- Returns { {i, j, kind} } (i < j, sorted), or nil, "stale_phases" when an index is out of range.
function P.phaseConflicts(M, locked)
	local red = {}
	for _, l in ipairs(locked or {}) do
		if type(l) ~= "number" or l ~= math.floor(l) or l < 0 or l >= M.size then return nil, "stale_phases" end
		red[l] = true
	end
	local out = {}
	for i = 0, M.size - 1 do
		if not red[i] then
			for j, kind in pairs(M.kinds[i]) do
				if j > i and not red[j] then out[#out + 1] = { i, j, kind } end
			end
		end
	end
	table.sort(out, function(a, b)
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[2] < b[2]
	end)
	return out
end

--- Conflicts of every phase: per phase the list of P.phaseConflicts, and the pair counts by kind
-- over all phases. nil, "stale_phases" when any phase indexes past the map.
function P.checkPhases(M, states)
	local per, counts = {}, { cross = 0, merge = 0, ped = 0 }
	for s, locked in ipairs(states or {}) do
		local list, why = P.phaseConflicts(M, locked)
		if list == nil then return nil, why end
		per[s] = list
		for _, c in ipairs(list) do counts[c[3]] = counts[c[3]] + 1 end
	end
	return per, counts
end

return P
