-- Smart Lanes tool: the street through a clicked segment (pure, no api.* calls), unit-tested in
-- tests/square_smart_lanes/test_tool.lua. plans/square_smart_lanes/PHASE7.md "Step 4".
--
-- Two modes (user decision 2026-10-11, "Ends only, Shift extends"):
--   * opt.ends = true (a plain click / hover): both ways through plain nodes only, stopping at the
--     FIRST junction (3+ road segments) on each side, which is part of it when handled; handled
--     plain nodes in between (lane drops) count too, at most opt.maxDrops (Street.ENDS_MAX_DROPS,
--     then stop "max_drops"). Caps: opt.maxDist or Street.ENDS_MAX_DIST, MAX_NODES. Stop "end" at
--     that junction. So at most 2 junctions + the lane drops between them.
--   * otherwise (Shift+click, "follow"): as below, capped by opt.maxJunctions / opt.maxDist
--     (defaults Street.MAX_JUNCTIONS, Street.MAX_DIST).
-- Street.walk(world, seg, opt) follows the road both ways from segment `seg`, one segment at a time
-- and the two ends in turn (so a capped street stays centred on the click):
--   * through plain nodes (exactly two road segments, Walk.roadSegs: tram-only tracks do not count),
--     whatever their lanes (a lane drop is part of the street);
--   * through a junction (3+ road segments) while the street continues: the leaving segment with the
--     smallest turn from the arriving one (S.turnDeg by the tangents; two candidates less than
--     TIE_DEG apart are told apart by their far ends, S.farTurnDeg, as at tangential ramps), at most
--     MAX_TURN_DEG, with the same road lanes per travel direction as the arriving segment (lanes
--     arriving = lanes leaving on, and back: one-way-ness included);
--   * stop: "turn" (nothing within MAX_TURN_DEG), "fork" (two ways on within TIE_DEG, at the node
--     and at their far ends: a symmetric fork), "lanes" (the straightest way on has another lane
--     layout), "dead_end", "ring" (a roundabout node: rings have their own Apply to roundabout, so
--     the street never enters one; that node is not part of it), "loop" (a node already passed),
--     "no_node" / "no_seg" (missing from the world), "max_dist" (the street would pass MAX_DIST),
--     "max_junctions" (MAX_JUNCTIONS handled junctions found), "max_nodes" (MAX_NODES nodes passed),
--     "end" / "max_drops" (ends mode only, see above).
-- opt.handled(n) -> bool: whether node n is a junction the tool handles (the caller's Slip.classify);
-- opt.isRing(n) -> bool: whether node n is on a roundabout (asked at junctions only). A junction where the street stops is
-- part of it (the street arrives there).
-- opt.ends, opt.maxJunctions, opt.maxDist, opt.maxDrops: see "Two modes" above.
-- Returns { seg, segs = {segments, the clicked one first}, junctions = {handled nodes in street
-- order}, dist (m), stops = { a = reason, b = reason } } or nil, reason ("no_seg": the clicked
-- segment is missing or has no road lanes).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Walk = ug_require "square_smart_lanes::/smart_lanes/sl_walk.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"

local Street = {}

Street.MAX_JUNCTIONS = 10 -- follow mode (Shift+click); was 60 until the 2026-10-11 decision
Street.MAX_DIST = 1000   -- m, the whole street in follow mode (was 3 km)
Street.ENDS_MAX_DROPS = 4 -- ends mode: handled plain nodes (lane drops) between the two ends
Street.ENDS_MAX_DIST = 3000 -- m, ends mode: a bound on the plain-node walk to the end junctions
Street.MAX_NODES = 400   -- nodes passed (plain ones included), a hard bound on the work
Street.MAX_TURN_DEG = 30
Street.TIE_DEG = 5

--- Lane counts of a segment at a node match for traffic going on: arriving lanes = leaving lanes
-- on the next segment, both directions.
local function sameLanes(arr, nxt)
	return #arr.incoming == #nxt.outgoing and #arr.outgoing == #nxt.incoming
end

--- The way on at junction `at` for traffic arriving on segment `sid` (roads = Walk.roadSegs).
-- Returns the next segment id or nil, reason.
local function continuation(world, at, sid, roads)
	local cands = {}
	for _, r in ipairs(roads) do
		if r.sid ~= sid then
			local okT, deg = pcall(Slip.turnDeg, world, at, sid, r.sid)
			if okT and math.abs(deg) <= Street.MAX_TURN_DEG then
				cands[#cands + 1] = { r = r, deg = math.abs(deg) }
			end
		end
	end
	if #cands == 0 then return nil, "turn" end
	table.sort(cands, function(a, b) return a.deg < b.deg end)
	local best = cands[1]
	if cands[2] ~= nil and cands[2].deg - best.deg < Street.TIE_DEG then
		local ok1, f1 = pcall(Slip.farTurnDeg, world, at, sid, best.r.sid)
		local ok2, f2 = pcall(Slip.farTurnDeg, world, at, sid, cands[2].r.sid)
		if not (ok1 and ok2) or math.abs(math.abs(f2) - math.abs(f1)) < Street.TIE_DEG then
			-- a symmetric fork: neither way is the street's (never an arbitrary pick)
			return nil, "fork"
		end
		if math.abs(f2) < math.abs(f1) then best = cands[2] end
	end
	local s = world.seg(sid)
	local arr = s and Ring.lanesAt(s, at)
	if not arr then return nil, "no_seg" end
	if not sameLanes(arr, best.r.la) then return nil, "lanes" end
	return best.r.sid
end

--- See the header.
function Street.walk(world, seg, opt)
	opt = opt or {}
	local handled = opt.handled or function() return false end
	local isRing = opt.isRing or function() return false end
	local ends = opt.ends == true
	local maxJ = ends and math.huge or (opt.maxJunctions or Street.MAX_JUNCTIONS)
	local maxDist = opt.maxDist or (ends and Street.ENDS_MAX_DIST or Street.MAX_DIST)
	local maxDrops = opt.maxDrops or Street.ENDS_MAX_DROPS
	local drops = 0
	local s = world.seg(seg)
	if not s or Ring.roadLaneCount(s) == 0 then return nil, "no_seg" end
	local st = { seg = seg, segs = { seg }, dist = Ring.segLength(s), stops = {} }
	local found = { a = {}, b = {} }
	local count, nodes = 0, 0
	local visited, onStreet = {}, { [seg] = true }
	-- walker a arrives at node1, walker b at node0, both along the clicked segment
	local walkers = {
		{ name = "a", at = s.node1, sid = seg },
		{ name = "b", at = s.node0, sid = seg },
	}
	local function stop(w, why)
		w.done = true
		st.stops[w.name] = why
	end
	local function advance(w)
		local at, sid = w.at, w.sid
		if visited[at] then return stop(w, "loop") end
		if nodes >= Street.MAX_NODES then return stop(w, "max_nodes") end
		visited[at] = true
		nodes = nodes + 1
		local roads, why = Walk.roadSegs(world, at)
		if not roads then return stop(w, why) end
		-- only a junction can be on a ring the street did not start on: a plain ring node has just
		-- its two ring segments, so the walk reaches one only from a ring junction
		if #roads >= 3 and isRing(at) then return stop(w, "ring") end
		if handled(at) then
			if ends and #roads == 2 then
				if drops >= maxDrops then return stop(w, "max_drops") end
				drops = drops + 1
			end
			local list = found[w.name]
			list[#list + 1] = at
			count = count + 1
			if count >= maxJ then return stop(w, "max_junctions") end
		end
		if #roads <= 1 then return stop(w, "dead_end") end
		if ends and #roads >= 3 then return stop(w, "end") end
		local nxt
		if #roads == 2 then
			for _, r in ipairs(roads) do
				if r.sid ~= sid then nxt = r.sid end
			end
			if nxt == nil then return stop(w, "loop") end -- a segment with both ends here
		else
			local reason
			nxt, reason = continuation(world, at, sid, roads)
			if nxt == nil then return stop(w, reason) end
		end
		-- the two ends met on one segment (a closed street)
		if onStreet[nxt] then return stop(w, "loop") end
		local ns = world.seg(nxt)
		if not ns then return stop(w, "no_seg") end
		local len = Ring.segLength(ns)
		if st.dist + len > maxDist then return stop(w, "max_dist") end
		st.dist = st.dist + len
		st.segs[#st.segs + 1] = nxt
		onStreet[nxt] = true
		w.sid = nxt
		w.at = (ns.node0 == at) and ns.node1 or ns.node0
	end
	-- the two ends in turn; every advance passes a node or stops its walker, so this ends after at
	-- most MAX_NODES + 2 advances
	while not (walkers[1].done and walkers[2].done) do
		for _, w in ipairs(walkers) do
			if not w.done then
				if count >= maxJ then
					stop(w, "max_junctions")
				else
					advance(w)
				end
			end
		end
	end
	-- street order: end b ... clicked segment ... end a
	local list = {}
	for i = #found.b, 1, -1 do list[#list + 1] = found.b[i] end
	for _, n in ipairs(found.a) do list[#list + 1] = n end
	st.junctions = list
	return st
end

return Street
