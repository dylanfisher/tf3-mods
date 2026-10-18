-- Smart Lanes: the tool's drawing of a plain ring node's lane connections (the mid nodes of the mid-node spiral,
-- PLAN.md "Default: the mid-node spiral"). The game's NodeViewer can't draw them (it asserts when a node has more
-- connections than network edges, docs/findings/roads.md "Junction lane connections"; the Crossing Tool can't pick a
-- plain 2-edge node either), so the tool draws one short curve per connection itself: from the lane it leaves, LEAD m
-- before the node, to the lane it enters, LEAD m after it. Pure (no api.*): the GUI script turns the curves into
-- EdgeRenderable edges. Lua 5.1 syntax.
--
-- Lane positions: laneConfigs run left to right looking from node0 to node1 (sl_ring header); a lane's lateral
-- position is its laneConfig `offset` (sl_ring R.lanesFromConfigs), signed so that it grows left to right, or, without
-- offsets, LANE_W m per lane around the centre.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"

local V = {}

V.LEAD = 6        -- m before / after the node
V.LANE_W = 3.5    -- m per lane when the lanes have no offset
V.MAX_CURVES = 64 -- per call (a ring has at most 32 nodes of a few connections each)

local function unit(x, y)
	local l = math.sqrt(x * x + y * y)
	if l < 1e-9 or l ~= l then return nil end
	return x / l, y / l
end

--- Lateral position (m, growing to the right looking node0 -> node1) of 0-based laneConfig index k of segment s.
function V.lateral(s, k)
	local lanes = s.lanes or {}
	local n = #lanes
	local first, last = lanes[1] and lanes[1].offset, lanes[n] and lanes[n].offset
	local o = lanes[k + 1] and lanes[k + 1].offset
	if type(o) == "number" and type(first) == "number" and type(last) == "number" and o == o and first ~= last then
		return (last > first) and o or -o
	end
	return (k - (n - 1) / 2) * V.LANE_W
end

--- Unit direction node0 -> node1 of segment s at its end e (0 or 1): its tangent there, else the chord.
local function dirAt(s, e)
	local t = (e == 0) and s.t0 or s.t1
	local x, y
	if t ~= nil then x, y = unit(t.x, t.y) end
	if x == nil then x, y = unit(s.p1.x - s.p0.x, s.p1.y - s.p0.y) end
	return x, y
end

--- The point of lane `idx` (a connection lane index at node end e) of segment s, `along` m into the segment from the node.
local function lanePoint(s, e, idx, along)
	local ux, uy = dirAt(s, e)
	if ux == nil then return nil end
	local k = (e == 0) and idx or (#s.lanes - 1 - idx)
	local lat = V.lateral(s, k)
	local p = (e == 0) and s.p0 or s.p1
	local sign = (e == 0) and 1 or -1 -- into the segment: along u at node0, against it at node1
	-- right of u: (uy, -ux)
	return { x = p.x + sign * along * ux + lat * uy, y = p.y + sign * along * uy - lat * ux }, ux * sign, uy * sign
end

--- Curves for node n's connections `conns` (plain tables: segment0, lane0, segment1, lane1, withRoad) in `world`:
-- { { a = {x, y}, b = {x, y}, ta = {x, y}, tb = {x, y}, change = bool } } (Hermite end points and tangents, a -> b
-- in travel direction; change: the connection changes lanes, not just straight on). Road connections only; a
-- connection naming a segment that is not at n is left out. At most MAX_CURVES.
function V.curves(world, n, conns)
	local out = {}
	local node = world.node(n)
	if node == nil then return out end
	for _, c in ipairs(conns or {}) do
		if #out >= V.MAX_CURVES then break end
		if c.withRoad then
			local s0, s1 = world.seg(c.segment0), world.seg(c.segment1)
			local e0, e1 = s0 and Ring.endAt(s0, n), s1 and Ring.endAt(s1, n)
			if e0 ~= nil and e1 ~= nil then
				-- a: on the incoming segment, LEAD before the node (direction into the segment reversed = travel)
				local a, ax, ay = lanePoint(s0, e0, c.lane0, V.LEAD)
				local b, bx, by = lanePoint(s1, e1, c.lane1, V.LEAD)
				if a ~= nil and b ~= nil then
					local L = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
					-- lateral positions to the right of travel: travel runs along u into node1 and out of node0
					local lat0 = V.lateral(s0, (e0 == 0) and c.lane0 or (#s0.lanes - 1 - c.lane0))
					local lat1 = V.lateral(s1, (e1 == 0) and c.lane1 or (#s1.lanes - 1 - c.lane1))
					local latIn = (e0 == 1) and lat0 or -lat0
					local latOut = (e1 == 0) and lat1 or -lat1
					out[#out + 1] = {
						a = a, b = b,
						-- travel direction: at a towards the node (minus "into the segment"), at b away from it
						ta = { x = -ax * L, y = -ay * L }, tb = { x = bx * L, y = by * L },
						-- a lane change: the lane's lateral position (looking along travel) differs on the two sides
						change = math.abs(latIn - latOut) > 0.5,
					}
				end
			end
		end
	end
	return out
end

return V
