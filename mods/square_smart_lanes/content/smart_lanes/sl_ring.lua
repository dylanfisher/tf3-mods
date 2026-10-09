-- Smart Lanes: pure street-graph logic (no api.* calls), unit-tested in tests/square_smart_lanes/.
-- Lane model of a segment at a node, one-way detection, one-way ring search, ring direction and
-- the per-node view (ring in / ring out / arm) the rules work on.
--
-- World interface (plain tables; the game script builds them from components, tests from fixtures):
--   world.node(id) -> { id, x, y, segs = { segId, ... } }                       or nil
--   world.seg(id)  -> { id, node0, node1, p0 = {x, y}, p1, t0 = {x, y}, t1,
--                       lanes = { { forward, road, car, tram }, ... } }         or nil
-- lanes are the edge's laneConfigs in file order (BaseEdge.laneConfigs, api/tealdef/api/engine.d.tl:99-130);
-- road = CAR, BUS or TRUCK in transportModes, car = CAR, tram = TRAM or ELECTRIC_TRAM.
-- t0/t1 are BaseEdge.tangent0/1: both point from node0 to node1, length about the segment length
-- (urbangames_campaign_mission_02 mission_params_02.tl:265-290).
--
-- Lane index convention (docs/findings.md "Junction lane connections"; LaneConnection doc,
-- api/tealdef/api/type.d.tl:1197-1213): LaneConnection.lane0/lane1 count every laneConfig incl.
-- sidewalks, left to right looking from the node along the segment. laneConfigs run left to right
-- looking from node0 to node1, so at node0 the index is the laneConfig index (0-based) and at node1
-- it is (#lanes - 1 - index). Verified on the probe log: incoming ring lane 1 is the outer lane of a
-- counterclockwise ring, and straight on is i -> n + 1 - i.

local R = {}

R.MAX_RING_SEGS = 32     -- segments in one ring
R.MAX_RING_LEN = 1200    -- m, ring circumference
R.MAX_SEARCH_NODES = 160 -- nodes the ring search may visit from one start node
R.MAX_KINK_DEG = 45      -- max direction change at a ring node (rings are smooth curves)

local function len2(x, y) return math.sqrt(x * x + y * y) end

-- Per-segment results the ring search asks for again and again, keyed by the segment table (weak:
-- a world's segment tables never change, and a new world makes new ones).
local lenMemo = setmetatable({}, { __mode = "k" })
local oneWayMemo = setmetatable({}, { __mode = "k" })

local function segLengthOf(s)
	local chord = len2(s.p1.x - s.p0.x, s.p1.y - s.p0.y)
	if s.t0 and s.t1 then
		local t = (len2(s.t0.x, s.t0.y) + len2(s.t1.x, s.t1.y)) / 2
		if t > 0 then return math.max(t, chord) end
	end
	return chord
end

--- Length of a segment (m): mean tangent length (Hermite tangents are about the arc length), else chord.
function R.segLength(s)
	local m = lenMemo[s]
	if m == nil then
		m = segLengthOf(s)
		lenMemo[s] = m
	end
	return m
end

--- Which end of segment s is at node: 0, 1, or nil.
function R.endAt(s, node)
	if s.node0 == node then return 0 end
	if s.node1 == node then return 1 end
	return nil
end

--- Connection lane index at the node end `e` for the 0-based laneConfig index k.
function R.connIndex(s, e, k)
	if e == 0 then return k end
	return #s.lanes - 1 - k
end

--- Index of the same physical lane seen from the other end of the segment.
function R.otherEndIndex(s, idx)
	return #s.lanes - 1 - idx
end

--- Road lanes of segment s at node: { e, incoming = {idx asc}, outgoing = {idx asc}, busOnly }.
-- busOnly: a road lane without CAR (bus lane), which the rules do not handle.
function R.lanesAt(s, node)
	local e = R.endAt(s, node)
	if e == nil then return nil end
	local inc, out, busOnly = {}, {}, false
	for k0 = 0, #s.lanes - 1 do
		local lc = s.lanes[k0 + 1]
		if lc.road then
			if not lc.car then busOnly = true end
			local idx = R.connIndex(s, e, k0)
			local leaving = (e == 0 and lc.forward) or (e == 1 and not lc.forward)
			if leaving then out[#out + 1] = idx else inc[#inc + 1] = idx end
		end
	end
	table.sort(inc)
	table.sort(out)
	return { e = e, incoming = inc, outgoing = out, busOnly = busOnly }
end

local function oneWayOf(s)
	local f, b = 0, 0
	for _, lc in ipairs(s.lanes) do
		if lc.road then
			if lc.forward then f = f + 1 else b = b + 1 end
		end
	end
	if f > 0 and b == 0 then return "fwd" end
	if b > 0 and f == 0 then return "bwd" end
	return nil
end

--- One-way direction of a segment: "fwd" (node0 -> node1), "bwd", or nil (two-way / no road lane).
function R.oneWay(s)
	local m = oneWayMemo[s]
	if m == nil then
		m = oneWayOf(s) or false
		oneWayMemo[s] = m
	end
	return m or nil
end

function R.roadLaneCount(s)
	local n = 0
	for _, lc in ipairs(s.lanes) do if lc.road then n = n + 1 end end
	return n
end

--- Travel start and end node of a one-way segment.
function R.travel(s)
	local d = R.oneWay(s)
	if d == "fwd" then return s.node0, s.node1 end
	if d == "bwd" then return s.node1, s.node0 end
	return nil
end

--- Unit travel direction of a one-way segment at its start ("start") or end ("end").
local function travelDir(s, where)
	local d = R.oneWay(s)
	local t
	if d == "fwd" then t = (where == "start") and s.t0 or s.t1
	else t = (where == "start") and s.t1 or s.t0 end
	local x, y
	if t and len2(t.x, t.y) > 1e-6 then
		x, y = t.x, t.y
	else
		x, y = s.p1.x - s.p0.x, s.p1.y - s.p0.y
	end
	if d == "bwd" then x, y = -x, -y end
	local l = len2(x, y)
	if l < 1e-9 then return 0, 0 end
	return x / l, y / l
end

--- Points along a segment's Hermite curve in travel direction (without the end point).
local function samples(s, n)
	local p0, p1, t0, t1 = s.p0, s.p1, s.t0 or { x = s.p1.x - s.p0.x, y = s.p1.y - s.p0.y },
		s.t1 or { x = s.p1.x - s.p0.x, y = s.p1.y - s.p0.y }
	local pts = {}
	for i = 0, n - 1 do
		local u = i / n
		if R.oneWay(s) == "bwd" then u = 1 - u end
		local u2, u3 = u * u, u * u * u
		local h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
		pts[#pts + 1] = {
			x = h00 * p0.x + h10 * t0.x + h01 * p1.x + h11 * t1.x,
			y = h00 * p0.y + h10 * t0.y + h01 * p1.y + h11 * t1.y,
		}
	end
	return pts
end

--- Signed area of a ring (list of segments in travel order): > 0 counterclockwise.
function R.signedArea(world, segIds)
	local pts = {}
	for _, id in ipairs(segIds) do
		for _, p in ipairs(samples(world.seg(id), 8)) do pts[#pts + 1] = p end
	end
	local a = 0
	for i = 1, #pts do
		local p, q = pts[i], pts[(i % #pts) + 1]
		a = a + (p.x * q.y - q.x * p.y)
	end
	return a / 2
end

--- Shortest directed cycle of one-way road segments through `start` (Dijkstra by length).
-- Pruned by the straight line back to start (a lower bound of the rest of any cycle, as a segment
-- is never shorter than its chord): nodes from which no cycle of at most MAX_RING_LEN (or shorter
-- than the best found) can close are never queued, so a big one-way network without rings is
-- searched within MAX_RING_LEN / 2 of start instead of MAX_RING_LEN.
-- Returns { segs = {segId in travel order, starting at start}, nodes = {nodeId, starting at start},
-- length } or nil, reason.
function R.shortestCycle(world, start)
	local dist, prevSeg, done, open = {}, {}, {}, {}
	local best, bestLast, bestLen = nil, nil, math.huge
	local sn = world.node(start)
	local sx, sy = sn and sn.x, sn and sn.y
	dist[start] = 0
	open[start] = true
	local visited = 0
	while true do
		local u, du = nil, math.huge
		for n in pairs(open) do
			local d = dist[n]
			if d < du then u, du = n, d end
		end
		if u == nil or du >= bestLen or du > R.MAX_RING_LEN then break end
		open[u] = nil
		done[u] = true
		visited = visited + 1
		if visited > R.MAX_SEARCH_NODES then break end
		local node = world.node(u)
		for _, sid in ipairs((node and node.segs) or {}) do
			local s = world.seg(sid)
			if s then
				local a, b = R.travel(s)
				if a == u then
					local nd = du + R.segLength(s)
					if b == start then
						if nd < bestLen then bestLen, best, bestLast = nd, u, sid end
					elseif not done[b] and (dist[b] == nil or nd < dist[b]) then
						local back = 0
						if sx ~= nil then
							local p = (b == s.node1) and s.p1 or s.p0
							back = len2(p.x - sx, p.y - sy) - 1 -- 1 m slack for position rounding
						end
						local bound = nd + back
						if bound <= R.MAX_RING_LEN and bound < bestLen then
							dist[b] = nd
							prevSeg[b] = sid
							open[b] = true
						end
					end
				end
			end
		end
	end
	if best == nil then return nil, "no_cycle" end
	-- walk back from `best` to start
	local segs = { bestLast }
	local n = best
	while n ~= start do
		local sid = prevSeg[n]
		table.insert(segs, 1, sid)
		local a = R.travel(world.seg(sid))
		n = a
		if #segs > R.MAX_RING_SEGS + 1 then return nil, "too_long" end
	end
	local nodes = {}
	for _, sid in ipairs(segs) do nodes[#nodes + 1] = (R.travel(world.seg(sid))) end
	return { segs = segs, nodes = nodes, length = bestLen }
end

--- Finds the one-way ring through `start`, validated: smooth, closed, at most MAX_RING_SEGS segments
-- and MAX_RING_LEN metres, the same number of road lanes on every ring segment, no bus lanes.
-- Returns ring { segs, nodes, length, side (+1 counterclockwise, -1 clockwise), lanes (R),
-- key (lowest node id, identifies the ring), segSet, nodeSet } or nil, reason.
function R.findRing(world, start)
	local cyc, why = R.shortestCycle(world, start)
	if not cyc then return nil, why end
	if #cyc.segs > R.MAX_RING_SEGS then return nil, "too_many_segs" end
	if #cyc.segs < 2 then return nil, "degenerate" end
	if cyc.length > R.MAX_RING_LEN then return nil, "too_long" end
	local lanes = nil
	for _, sid in ipairs(cyc.segs) do
		local s = world.seg(sid)
		local n = R.roadLaneCount(s)
		if lanes == nil then lanes = n elseif n ~= lanes then return nil, "mixed_ring_lanes" end
		for _, lc in ipairs(s.lanes) do
			if lc.road and not lc.car then return nil, "bus_lane_ring" end
		end
	end
	local maxKink = math.cos(math.rad(R.MAX_KINK_DEG))
	for i, sid in ipairs(cyc.segs) do
		local nxt = cyc.segs[(i % #cyc.segs) + 1]
		local ax, ay = travelDir(world.seg(sid), "end")
		local bx, by = travelDir(world.seg(nxt), "start")
		if ax * bx + ay * by < maxKink then return nil, "kink" end
	end
	local area = R.signedArea(world, cyc.segs)
	if math.abs(area) < 1 then return nil, "no_area" end
	local ring = { segs = cyc.segs, nodes = cyc.nodes, length = cyc.length, lanes = lanes,
		side = area > 0 and 1 or -1, segSet = {}, nodeSet = {} }
	local key = nil
	for _, sid in ipairs(cyc.segs) do ring.segSet[sid] = true end
	for _, n in ipairs(cyc.nodes) do
		ring.nodeSet[n] = true
		if key == nil or n < key then key = n end
	end
	ring.key = key
	return ring
end

--- The one-way ring through node n, or nil, reason. A ring node has at least one one-way
-- segment arriving and one leaving (cheap test before the ring search).
function R.ringThrough(world, n)
	local node = world.node(n)
	if not node then return nil, "no_node" end
	local inc, outg = false, false
	for _, sid in ipairs(node.segs or {}) do
		local s = world.seg(sid)
		local a, b = nil, nil
		if s then a, b = R.travel(s) end
		if a == n then outg = true end
		if b == n then inc = true end
	end
	if not (inc and outg) then return nil, "no_one_way_through" end
	return R.findRing(world, n)
end

-- TransportMode enum values (api/tealdef/api/type.d.tl:2217-2234, order PERSON=0, CARGO, CAR, BUS,
-- TRUCK, TRAM, ELECTRIC_TRAM, ...; the probe logged a car lane as modes "2+3+4"). The game script
-- passes the live api.type.enum.TransportMode values when it can read them.
R.MODES = { CAR = 2, BUS = 3, TRUCK = 4, TRAM = 5, ELECTRIC_TRAM = 6 }

--- Plain lane list from BaseEdge.laneConfigs (userdata or tables): { forward, road, car, tram }.
-- transportModes is a {TransportMode : boolean} map, read with pairs (as the probe did).
function R.lanesFromConfigs(laneConfigs, modes)
	modes = modes or R.MODES
	local out = {}
	for _, lc in ipairs(laneConfigs or {}) do
		local set = {}
		local okM, tm = pcall(function() return lc.transportModes end)
		if okM and tm ~= nil then
			pcall(function()
				for k, v in pairs(tm) do if v then set[k] = true end end
			end)
		end
		local car = set[modes.CAR] == true
		out[#out + 1] = {
			forward = lc.forward == true,
			car = car,
			road = car or set[modes.BUS] == true or set[modes.TRUCK] == true,
			tram = set[modes.TRAM] == true or set[modes.ELECTRIC_TRAM] == true,
		}
	end
	return out
end

local function reversed(list)
	local out = {}
	for i = #list, 1, -1 do out[#out + 1] = list[i] end
	return out
end

--- Orders lane indices (ascending input) from the turn side (outer/kerb) inwards.
-- side +1 = counterclockwise ring: the turn side is the driver's right. Looking from the node,
-- an incoming segment's ascending index runs from the driver's right to left, an outgoing one's
-- from the driver's left to right.
function R.outerFirst(asc, incoming, side)
	if (incoming and side == 1) or ((not incoming) and side == -1) then return asc end
	return reversed(asc)
end

--- The rules' view of one ring node:
-- { node, kind = "plain" | "arm" | "skip", reason, ringIn, ringOut, arm,
--   o_in = {ring in lanes outer first}, o_out = {ring out lanes outer first},
--   x = {arm exit lanes kerb first}, e = {arm entry lanes kerb first} }
-- "plain": only the two ring segments. "skip": something the rules don't handle (two non-ring
-- segments such as a road through the centre, a second ring touching, bus lanes).
function R.nodeView(world, ring, nodeId)
	local node = world.node(nodeId)
	local v = { node = nodeId, x = {}, e = {} }
	if not node then
		v.kind, v.reason = "skip", "no_node"
		return v
	end
	local others = {}
	for _, sid in ipairs(node.segs) do
		local s = world.seg(sid)
		if s and ring.segSet[sid] then
			local _, b = R.travel(s)
			if b == nodeId then v.ringIn = sid else v.ringOut = sid end
		elseif s then
			others[#others + 1] = sid
		end
	end
	if not v.ringIn or not v.ringOut then
		v.kind, v.reason = "skip", "not_on_ring"
		return v
	end
	local si, so = R.lanesAt(world.seg(v.ringIn), nodeId), R.lanesAt(world.seg(v.ringOut), nodeId)
	v.o_in = R.outerFirst(si.incoming, true, ring.side)
	v.o_out = R.outerFirst(so.outgoing, false, ring.side)
	if #v.o_in ~= ring.lanes or #v.o_out ~= ring.lanes then
		v.kind, v.reason = "skip", "ring_lanes"
		return v
	end
	-- non-ring segments without road lanes (e.g. a tram-only track) do not count as arms
	local arms = {}
	for _, sid in ipairs(others) do
		local la = R.lanesAt(world.seg(sid), nodeId)
		if la and (#la.incoming + #la.outgoing) > 0 then arms[#arms + 1] = { sid = sid, la = la } end
	end
	if #arms == 0 then
		v.kind = "plain"
		return v
	end
	if #arms > 1 then
		v.kind, v.reason = "skip", "multi_arm"
		return v
	end
	local a = arms[1]
	if a.la.busOnly then
		v.kind, v.reason = "skip", "bus_lane_arm"
		return v
	end
	v.kind, v.arm = "arm", a.sid
	v.x = R.outerFirst(a.la.outgoing, false, ring.side)
	v.e = R.outerFirst(a.la.incoming, true, ring.side)
	return v
end

return R
