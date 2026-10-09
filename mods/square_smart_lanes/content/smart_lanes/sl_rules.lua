-- Smart Lanes: pure lane rules (no api.* calls), unit-tested in tests/square_smart_lanes/.
-- Turns the per-node views of sl_ring.lua into LaneConnection sets, keeps the engine's tram
-- connections, models the engine default (sanity check against the probe log), checks that every
-- entry can reach every exit through node connections alone, and holds params and log format.
--
-- A connection is a plain table { segment0, lane0, segment1, lane1, withRoad, withTram }
-- (LaneConnection, api/tealdef/api/type.d.tl:1197-1213).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"

local M = {}

M.MOD_ID = "square_smart_lanes"
M.PREFIX = "[SQRL]"

-- Layouts. The road tool applies one layout, the most fitting one ("turbo", shown as "Smart lanes"):
-- lanes matched one to one, plus the exit-only outer lane wherever the ring qualifies (every exit on
-- the ring has >= 2 lanes, no skipped junction, >= 2 ring lanes); otherwise plain matched lanes
-- (reason logged). The automatic rule after a build is "two_lane": the same, but exit-only only when
-- the whole ring was just built. "matched" (never exit-only) stays for tests and fallbacks;
-- "game" is the tool's Reset (the engine default model, planned as variant "engine").
M.LAYOUTS = { "turbo" }
M.LAYOUT_NAMES = { matched = "Matched lanes", turbo = "Smart lanes", game = "Game default" }

--- Layout key from a toolbar value (1-based index; anything else -> "matched").
function M.layoutFromValue(v)
	local i = tonumber(v)
	if i == nil or i ~= math.floor(i) or i < 1 or i > #M.LAYOUTS then i = 1 end
	return M.LAYOUTS[i]
end

-- Mod params (mod.json "params"; values are 1-based indices, docs/findings.md).
M.KEYS = { auto = "sqrl_auto" }
M.VALUES = { auto = { true, false } }
M.DEFAULTS = { auto = 1 }
M.RING_RULE = "two_lane" -- the automatic rule (no setting: Apply automatically Off disables it)

--- Settings from this mod's raw mod params (nil or a table of 1-based indices).
function M.fromModParams(raw)
	raw = type(raw) == "table" and raw or {}
	local cfg = {}
	for name, key in pairs(M.KEYS) do
		local list = M.VALUES[name]
		local i = tonumber(raw[key])
		if i == nil or i < 1 or i > #list or i ~= math.floor(i) then i = M.DEFAULTS[name] end
		cfg[name] = list[i]
	end
	cfg.ring = M.RING_RULE
	return cfg
end

--- "[SQRL] KIND k=v ..." from an ordered list of {key, value}; values without whitespace.
function M.line(kind, fields)
	local parts = { M.PREFIX, kind }
	for _, kv in ipairs(fields or {}) do
		local s = tostring(kv[2]):gsub("%s+", "_")
		if #s > 200 then s = s:sub(1, 197) .. "..." end
		parts[#parts + 1] = kv[1] .. "=" .. s
	end
	return table.concat(parts, " ")
end

function M.conn(s0, l0, s1, l1, road, tram)
	return { segment0 = s0, lane0 = l0, segment1 = s1, lane1 = l1, withRoad = road ~= false, withTram = tram == true }
end

local function key(c)
	return string.format("%s:%s>%s:%s", tostring(c.segment0), tostring(c.lane0), tostring(c.segment1), tostring(c.lane1))
end

--- Sorted "s0:l0>s1:l1:RT" list joined with "," (canonical form for comparisons and logs).
function M.connsText(list)
	local out = {}
	for _, c in ipairs(list or {}) do
		out[#out + 1] = key(c) .. ":" .. (c.withRoad and "R" or "-") .. (c.withTram and "T" or "-")
	end
	table.sort(out)
	return table.concat(out, ",")
end

--- connsText of the road connections only (tram flags and tram-only connections ignored, as
-- mergeTram leaves them alone): the tool's lane status badge compares with this.
function M.roadText(list)
	local road = {}
	for _, c in ipairs(list or {}) do
		if c.withRoad then road[#road + 1] = M.conn(c.segment0, c.lane0, c.segment1, c.lane1, true, false) end
	end
	return M.connsText(road)
end

local function push(list, seen, s0, l0, s1, l1)
	local c = M.conn(s0, l0, s1, l1, true, false)
	local k = key(c)
	if not seen[k] then
		seen[k] = true
		list[#list + 1] = c
	end
end

---------------------------------------------------------------------------
-- Rules

--- Ring-level decisions for the lane rule (key "two_lane", shown as "Matched lanes").
-- views: node views of every ring junction (kind "arm" or "skip"; "plain" nodes are ignored).
-- fresh: every ring junction node was built or changed by this build (the tool's Turbo layout
-- passes true).
-- Returns { turbo, reason }: turbo = the outer lane exits only. Only when every exit on the ring
-- has at least two lanes (so a vehicle in the outer lane can always leave at the next arm) and the
-- whole ring was just built. reason (when not turbo): one_lane_ring, skip_node, no_exit,
-- narrow_exit or not_fresh (first that applies).
function M.ringPlan(ringLanes, views, fresh)
	local allTwo, anySkip, anyExit = true, false, false
	for _, v in ipairs(views) do
		if v.kind == "skip" then anySkip = true end
		if v.kind == "arm" and #v.x > 0 then
			anyExit = true
			if M.exitLanes(ringLanes, #v.x) < 2 then allTwo = false end
		end
	end
	local reason = nil
	if ringLanes < 2 then reason = "one_lane_ring"
	elseif anySkip then reason = "skip_node"
	elseif not anyExit then reason = "no_exit"
	elseif not allTwo then reason = "narrow_exit"
	elseif not fresh then reason = "not_fresh" end
	return { turbo = reason == nil, reason = reason }
end

--- Ring lanes that exit at an arm with E exit lanes: one ring lane per exit lane.
function M.exitLanes(ringLanes, E)
	if E <= 0 then return 0 end
	return math.min(E, ringLanes)
end

--- Road connections for one ring junction ("Matched lanes"): lanes are matched one to one, so no
-- two lanes squeeze into one unless the road really gets narrower.
-- v: node view (sl_ring.nodeView, kind "arm"); plan: M.ringPlan result. Lane 1 = kerb side.
--   * circulating: every ring lane continues in its own lane (the outer lane not in turbo mode);
--   * exits: ring lane i -> exit lane i for i <= X = min(E, R); with more exit lanes than ring
--     lanes the innermost ring lane fans out over the rest (o_R -> x_R..x_E), no merge;
--   * entries: entry lane j -> ring lane j for j <= R; with more entry lanes than ring lanes the
--     extra (far-side) entry lanes merge into the innermost ring lane, the only unavoidable merge.
-- An entry lane meets the circulating lane of the same index: that is the roundabout's give-way,
-- not a lane drop. Reaching an exit with fewer lanes than the ring relies on vehicles changing
-- lanes between junctions, as the engine's own default does (findings.md).
function M.twoLaneConns(v, plan)
	local list, seen = {}, {}
	local Rn, E, N = #v.o_in, #v.x, #v.e
	local X = M.exitLanes(Rn, E)
	for i = 1, Rn do
		if not (plan.turbo and i == 1 and E > 0) then
			push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i])
		end
	end
	if E > 0 then
		for i = 1, X do push(list, seen, v.ringIn, v.o_in[i], v.arm, v.x[i]) end
		for j = X + 1, E do push(list, seen, v.ringIn, v.o_in[X], v.arm, v.x[j]) end
	end
	for j = 1, N do push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[math.min(j, Rn)]) end
	return list
end

--- Model of what the engine generates at a ring junction (probe log 2026-10-08, findings.md):
-- every ring lane straight on, the outer lane also into every exit lane, entry lanes split the ring
-- lanes kerb first (1 entry lane -> all; 2 entry lanes on 4 ring lanes -> 2 each).
-- Only verified for 1 or 2 entry lanes on 2- and 4-lane rings.
function M.engineDefault(v)
	local list, seen = {}, {}
	local Rn, E, N = #v.o_in, #v.x, #v.e
	for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
	for j = 1, E do push(list, seen, v.ringIn, v.o_in[1], v.arm, v.x[j]) end
	if N > 0 then
		for i = 1, Rn do
			local j = math.floor((i - 1) * N / Rn) + 1
			push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[i])
		end
	end
	return list
end

--- The engine default model for a ring junction with the node's tram connections kept (the tool's
-- Reset fallback when the engine does not regenerate the node itself).
function M.defaultConns(v, current)
	return M.mergeTram(M.engineDefault(v), current)
end

--- Final connection list for a node: the rule's road connections plus the engine's tram
-- connections from `current`, untouched (a lane pair with both keeps withTram on the road entry).
function M.mergeTram(roadConns, current)
	local out, byKey = {}, {}
	for _, c in ipairs(current or {}) do
		if c.withTram then
			local t = M.conn(c.segment0, c.lane0, c.segment1, c.lane1, false, true)
			byKey[key(t)] = t
			out[#out + 1] = t
		end
	end
	for _, c in ipairs(roadConns) do
		local k = key(c)
		if byKey[k] then
			byKey[k].withRoad = true
		else
			local r = M.conn(c.segment0, c.lane0, c.segment1, c.lane1, true, false)
			byKey[k] = r
			out[#out + 1] = r
		end
	end
	return out
end

--- Number of connections with withRoad.
function M.roadCount(list)
	local n = 0
	for _, c in ipairs(list or {}) do if c.withRoad then n = n + 1 end end
	return n
end

---------------------------------------------------------------------------
-- Planning a ring

--- Plans one ring.
-- world: sl_ring world; ring: sl_ring.findRing result; seeds: set {nodeId = true} of nodes this
-- build added or changed (the tool: the picked junction or every ring junction); variant:
-- "two_lane" (automatic: exit-only outer lane only on a fresh ring), "matched" (never exit-only),
-- "turbo" (exit-only wherever the ring qualifies, fresh or not), "engine" (the tool's Game default
-- and Reset: the engine default model, M.defaultConns), anything else ("game") is skipped;
-- currentConns(nodeId) -> list of the node's current connections (plain tables).
-- Returns { fresh, turbo, turboReason, nodes = { {node, status, reason, before, after, conns} } }.
-- status: "apply" (conns differ, write them), "same", "skip" (logged), "untouched" (not a seed).
function M.planRing(world, ring, seeds, variant, currentConns)
	local views, junctions = {}, {}
	local fresh = true
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(world, ring, n)
		if v.kind ~= "plain" then
			junctions[#junctions + 1] = v
			if not seeds[n] then fresh = false end
		end
	end
	local plan = M.ringPlan(ring.lanes, junctions, fresh or variant == "turbo")
	if variant == "matched" then plan = { turbo = false, reason = "matched" } end
	local res = { fresh = fresh, turbo = plan.turbo, turboReason = plan.reason, nodes = {} }
	local known = variant == "two_lane" or variant == "matched" or variant == "turbo" or variant == "engine"
	for _, v in ipairs(junctions) do
		local r = { node = v.node, view = v }
		if not seeds[v.node] then
			r.status = "untouched"
		elseif v.kind == "skip" then
			r.status, r.reason = "skip", v.reason
		elseif not known then
			r.status, r.reason = "skip", "variant_" .. tostring(variant)
		else
			local cur = currentConns(v.node) or {}
			local conns
			if variant == "engine" then conns = M.defaultConns(v, cur) else conns = M.mergeTram(M.twoLaneConns(v, plan), cur) end
			r.before, r.after = M.roadCount(cur), M.roadCount(conns)
			r.conns = conns
			if M.connsText(conns) == M.connsText(cur) then r.status = "same" else r.status = "apply" end
		end
		res.nodes[#res.nodes + 1] = r
	end
	return res
end

---------------------------------------------------------------------------
-- Reachability (offline checks; also usable for a debug log)

--- Simulates lane-level travel through node connections. Without laneChange vehicles keep their
-- lane between nodes; with laneChange they may use any lane of a ring segment (the engine's own
-- defaults rely on that, findings.md).
-- connsByNode: {nodeId = {conn...}}. Returns reach[armSegIn][armSegOut] = true for every arm
-- (by segment id) whose entry lanes can reach that arm's exit lanes, and deadLanes: ring lanes
-- (as "seg:idx") reachable from an entry from which no exit is reachable.
function M.reachability(world, ring, connsByNode, laneChange)
	-- every lane of `seg` arriving at `node` that has a connection there, or just `lane`
	local function lanesOf(node, seg, lane)
		if not laneChange then return { lane } end
		local out, seen = {}, {}
		for _, c in ipairs(connsByNode[node] or {}) do
			if c.withRoad and c.segment0 == seg and not seen[c.lane0] then
				seen[c.lane0] = true
				out[#out + 1] = c.lane0
			end
		end
		if #out == 0 then out[1] = lane end
		return out
	end
	-- state: incoming (seg, lane idx at the node it arrives at, node)
	local function nextStates(node, seg, lane)
		local out = {}
		for _, c in ipairs(connsByNode[node] or {}) do
			if c.withRoad and c.segment0 == seg and c.lane0 == lane then out[#out + 1] = c end
		end
		return out
	end
	local reach, dead = {}, {}
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(world, ring, n)
		if v.kind == "arm" and #v.e > 0 then
			local seen, stack, exits = {}, {}, {}
			for _, l in ipairs(v.e) do stack[#stack + 1] = { node = n, seg = v.arm, lane = l } end
			local ringLanes = {}
			while #stack > 0 do
				local st = table.remove(stack)
				local k = st.node .. "|" .. st.seg .. "|" .. st.lane
				if not seen[k] then
					seen[k] = true
					for _, c in ipairs(nextStates(st.node, st.seg, st.lane)) do
						local s1 = world.seg(c.segment1)
						if ring.segSet[c.segment1] then
							local _, b = Ring.travel(s1)
							for _, idx in ipairs(lanesOf(b, c.segment1, Ring.otherEndIndex(s1, c.lane1))) do
								ringLanes[c.segment1 .. ":" .. idx] = true
								stack[#stack + 1] = { node = b, seg = c.segment1, lane = idx }
							end
						else
							exits[c.segment1] = true
						end
					end
				end
			end
			reach[v.arm] = exits
			-- a ring lane is dead when nothing reachable from it leaves the ring
			for lk in pairs(ringLanes) do
				local sid, idx = lk:match("^(%d+):(%d+)$")
				sid, idx = tonumber(sid), tonumber(idx)
				local _, b = Ring.travel(world.seg(sid))
				local seen2, st2, ok = {}, { { node = b, seg = sid, lane = idx } }, false
				while #st2 > 0 and not ok do
					local st = table.remove(st2)
					local k = st.node .. "|" .. st.seg .. "|" .. st.lane
					if not seen2[k] then
						seen2[k] = true
						for _, c in ipairs(nextStates(st.node, st.seg, st.lane)) do
							if ring.segSet[c.segment1] then
								local s1 = world.seg(c.segment1)
								local _, b2 = Ring.travel(s1)
								for _, idx in ipairs(lanesOf(b2, c.segment1, Ring.otherEndIndex(s1, c.lane1))) do
									st2[#st2 + 1] = { node = b2, seg = c.segment1, lane = idx }
								end
							else
								ok = true
							end
						end
					end
				end
				if not ok then dead[lk] = true end
			end
		end
	end
	return reach, dead
end

return M
