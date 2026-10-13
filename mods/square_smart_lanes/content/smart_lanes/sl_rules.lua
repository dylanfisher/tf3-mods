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
-- lights: "No lights at roundabouts and ramps" at roundabout and slip-lane junctions (sl_lights.lua).
-- freeTurn: "Free kerb turn at traffic lights" at crossroads and T-junctions (sl_lights.lua L.kerbPhases):
-- "off" / "safe" (When safe) / "always" (Always, the default; user decision 2026-10-12); sl_lights L.modeFor gives the phase mode.
-- phases: "Light phases" at crossroads and T-junctions with traffic lights: "game" (Game default, the
-- default: the game's phases, re-pointed) / "sl" (Smart Lanes: sl_phaseplan.lua plans written with the
-- lanes, sl_write.lua W.remapLights / W.planLights; PHASES_PLAN.md step 4).
M.KEYS = { auto = "sqrl_auto", lights = "sqrl_lights", freeTurn = "sqrl_free_turn", phases = "sqrl_light_phases" }
M.VALUES = { auto = { true, false }, lights = { true, false }, freeTurn = { "off", "safe", "always" }, phases = { "game", "sl" } }
M.DEFAULTS = { auto = 1, lights = 1, freeTurn = 3, phases = 1 }
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

--- "key:count,..." from a map {key = count}, most frequent first (ties by key), at most `max`
-- characters (default 190, under M.line's 200 cap): keys that do not fit become "+N" (N more keys).
-- "-" when the map is empty. The SUMMARY line's skips= (PHASE7.md step 6).
function M.countsText(counts, max)
	max = max or 190
	local list = {}
	for k, c in pairs(counts or {}) do list[#list + 1] = { k = tostring(k), c = c } end
	table.sort(list, function(a, b)
		if a.c ~= b.c then return a.c > b.c end
		return a.k < b.k
	end)
	local parts, len = {}, 0
	for i, e in ipairs(list) do
		local p = e.k .. ":" .. e.c
		local more = "+" .. (#list - i + 1)
		-- room for this entry plus, when more follow, the "+N" tail
		local need = len + #p + (i < #list and #more + 2 or 0)
		if need > max then
			parts[#parts + 1] = more
			break
		end
		parts[#parts + 1] = p
		len = len + #p + 1
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
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

--- Traffic light phase remap for a changed connection list (TrafficLightState.lockedLanes: 0-based
-- indices into the node's laneConnections, then its crosswalks; base gui/entity_window/
-- double_slip_switch.tl:115-131). Writing new connections with the old phases left indices past the
-- new list and crashed the simulation (in game 2026-10-11: VectorMap.h:11 "key >= 0" right after a
-- 36 -> 16 crossroads write on a node with lights). A new connection takes the old state of the
-- same connection, else of the same movement (segment0 -> segment1: locked only if every such old
-- connection was), else of its incoming segment (likewise), else unlocked; crosswalk k keeps its own.
-- old, new: connection lists in config order; crosswalks: count; locked: the state's lockedLanes.
function M.remapLocked(old, new, crosswalks, locked)
	return M.remapper(old, new, crosswalks)(locked)
end

--- M.remapLocked with the connection matching done once: returns remap(locked) -> the new
-- lockedLanes for one state (same result as M.remapLocked(old, new, crosswalks, locked)). A node
-- with six phases remaps every phase against the same two lists (twice with a free kerb turn), and
-- the string keys per state were the write's biggest cost (PERF_REVIEW.md 2026-10-12).
function M.remapper(old, new, crosswalks)
	-- the old indices (0-based) each new connection takes its state from: the same connection (the
	-- last old one with that key, as a map assignment would keep), else every old one of the same
	-- movement (locked only if all are), else every old one of the incoming segment; none: unlocked
	local byKey, byPair, bySeg = {}, {}, {}
	for i, c in ipairs(old) do
		byKey[key(c)] = i - 1
		local p = tostring(c.segment0) .. ">" .. tostring(c.segment1)
		local lp = byPair[p]
		if lp == nil then
			lp = {}
			byPair[p] = lp
		end
		lp[#lp + 1] = i - 1
		local s = c.segment0
		if s ~= nil then
			local ls = bySeg[s]
			if ls == nil then
				ls = {}
				bySeg[s] = ls
			end
			ls[#ls + 1] = i - 1
		end
	end
	local from = {} -- j -> old index (number), list of old indices (table) or false
	for j, c in ipairs(new) do
		local f = byKey[key(c)]
		if f == nil then f = byPair[tostring(c.segment0) .. ">" .. tostring(c.segment1)] end
		if f == nil and c.segment0 ~= nil then f = bySeg[c.segment0] end
		from[j] = f == nil and false or f
	end
	local nOld, nNew, nCross = #old, #new, crosswalks or 0
	return function(locked)
		local isLocked = {}
		for _, i in ipairs(locked or {}) do isLocked[i] = true end
		local out = {}
		for j = 1, nNew do
			local f = from[j]
			local l = false
			if type(f) == "number" then
				l = isLocked[f] == true
			elseif f then
				l = true
				for _, i in ipairs(f) do
					if not isLocked[i] then
						l = false
						break
					end
				end
			end
			if l then out[#out + 1] = j - 1 end
		end
		for k = 0, nCross - 1 do
			if isLocked[nOld + k] then out[#out + 1] = nNew + k end
		end
		return out
	end
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

--- Ramp entry-only junction (user's hand edit 2026-10-11, square_roundabouts Roundabout Interchange,
-- ring 63759 node 63772): entry lane j -> ring-out lane j (kerb first, its own lane: the ramp never
-- yields), the R circulating lanes fold into the inner R - N ring-out lanes without crossing, aligned
-- from the inside (o_in[i] -> o_out[max(i, N + 1)]: the outer circulating lanes zip into o_out[N + 1]).
-- v: node view of an arm with entry lanes only, N < R.
function M.rampEntryConns(v)
	local list, seen = {}, {}
	local Rn, N = #v.o_in, #v.e
	for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[math.max(i, N + 1)]) end
	for j = 1, N do push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[j]) end
	return list
end

--- Is segment sid a ramp: one-way without a sidewalk (also sl_cross X.isRamp, which calls this).
-- Town arms and splitter legs have sidewalks. A missing segment is none.
function M.isRampSeg(world, sid)
	local s = sid and world.seg(sid)
	if not s or not s.lanes or Ring.oneWay(s) == nil then return false end
	for _, l in ipairs(s.lanes or {}) do if l.walk then return false end end
	return true
end

--- Entry-only junction k of `junctions` (ring junction views in travel order): why its ramp keeps the
-- give-way entry, or nil when the ramp may take its own ring lane (the reachability check follows in
-- planRing). Reasons: one_lane_ring, wide_entry (N >= R), not_ramp, narrow_next_exit (the next ring
-- junction downstream has no exit of >= 2 lanes, so the zip-merged circulating traffic could not leave
-- right after the merge from either lane and would queue on the ring).
function M.rampEntryWhy(world, junctions, k)
	local v = junctions[k]
	local Rn, N = #v.o_in, #v.e
	if Rn < 2 then return "one_lane_ring" end
	if N >= Rn then return "wide_entry" end
	if not M.isRampSeg(world, v.arm) then return "not_ramp" end
	local nxt = junctions[(k % #junctions) + 1]
	if nxt == v or nxt.kind ~= "arm" or #nxt.x < 2 then return "narrow_next_exit" end
	return nil
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

--- Appends a planRing node result's entry decision to APPLY log fields (entry=own_lane|give_way,
-- why=<reason> for give_way); nothing for other junctions. Returns fields.
function M.withEntry(fields, r)
	if r and r.entry then
		fields[#fields + 1] = { "entry", r.entry }
		if r.entry ~= "own_lane" then fields[#fields + 1] = { "why", r.entryWhy or "-" } end
	end
	return fields
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
-- Returns { fresh, turbo, turboReason, nodes = { {node, status, reason, before, after, conns, entry,
-- entryWhy} } }.
-- status: "apply" (conns differ, write them), "same", "skip" (logged), "untouched" (not a seed).
-- entry (variants two_lane / turbo, entry-only junctions): "own_lane" (a ramp narrower than the ring
-- takes the outer ring lanes, M.rampEntryConns) or "give_way" (twoLaneConns) with entryWhy (the first
-- M.rampEntryWhy reason, or "reachability"); nil elsewhere.
function M.planRing(world, ring, seeds, variant, currentConns)
	local views, junctions = {}, {}
	local fresh = true
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(world, ring, n)
		views[n] = v
		if v.kind ~= "plain" then
			junctions[#junctions + 1] = v
			if not seeds[n] then fresh = false end
		end
	end
	local plan = M.ringPlan(ring.lanes, junctions, fresh or variant == "turbo")
	if variant == "matched" then plan = { turbo = false, reason = "matched" } end
	local res = { fresh = fresh, turbo = plan.turbo, turboReason = plan.reason, nodes = {} }
	local known = variant == "two_lane" or variant == "matched" or variant == "turbo" or variant == "engine"
	local ownEntry = variant == "two_lane" or variant == "turbo"
	local candidates = {}
	for k, v in ipairs(junctions) do
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
			r.conns, r.cur = conns, cur
			if M.connsText(conns) == M.connsText(cur) then r.status = "same" else r.status = "apply" end
			if ownEntry and v.kind == "arm" and #v.x == 0 and #v.e > 0 then
				r.entry, r.entryWhy = "give_way", M.rampEntryWhy(world, junctions, k)
				if r.entryWhy == nil then candidates[#candidates + 1] = r end
			end
		end
		res.nodes[#res.nodes + 1] = r
	end
	if #candidates > 0 then M.rampEntries(world, ring, views, res, candidates, currentConns) end
	return res
end

--- Lets each candidate ramp entry (planRing) take its own ring lane when, with the plan so far, every
-- entry on the ring still reaches every exit and no ring lane is dead (M.reachability with lane
-- changes between nodes, as the engine default and the matched rule rely on); otherwise it keeps the
-- give-way entry (entryWhy "reachability"). Candidates are tried in travel order, each on top of the
-- ones accepted before it. Plain and untouched nodes count with their current connections (the engine
-- default model when a node has none, e.g. in tests).
function M.rampEntries(world, ring, views, res, candidates, currentConns)
	local byNode = {}
	for _, r in ipairs(res.nodes) do byNode[r.node] = r end
	local m = {}
	for _, n in ipairs(ring.nodes) do
		local r = byNode[n]
		local c = r and r.conns
		if c == nil then
			c = currentConns(n)
			local v = views[n]
			if (c == nil or #c == 0) and v and v.kind ~= "skip" and v.o_in then c = M.engineDefault(v) end
		end
		m[n] = c or {}
	end
	local entries, exits = {}, {}
	for _, n in ipairs(ring.nodes) do
		local v = views[n]
		if v and v.kind == "arm" then
			if #v.e > 0 then entries[#entries + 1] = v.arm end
			if #v.x > 0 then exits[#exits + 1] = v.arm end
		end
	end
	local function ok()
		local reach, dead = M.reachability(world, ring, m, true)
		if next(dead) ~= nil then return false end
		for _, a in ipairs(entries) do
			for _, b in ipairs(exits) do
				if not (reach[a] and reach[a][b]) then return false end
			end
		end
		return true
	end
	for _, r in ipairs(candidates) do
		local give = r.conns
		local own = M.mergeTram(M.rampEntryConns(r.view), r.cur)
		m[r.node] = own
		if ok() then
			r.conns, r.entry, r.after = own, "own_lane", M.roadCount(own)
			if M.connsText(own) == M.connsText(r.cur) then r.status = "same" else r.status = "apply" end
		else
			m[r.node] = give
			r.entryWhy = "reachability"
		end
	end
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
	-- does ring lane lk ("seg:idx") lead off the ring through connections (to any non-ring segment)
	local function leadsOff(lk)
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
						for _, i2 in ipairs(lanesOf(b2, c.segment1, Ring.otherEndIndex(s1, c.lane1))) do
							st2[#st2 + 1] = { node = b2, seg = c.segment1, lane = i2 }
						end
					else
						ok = true
					end
				end
			end
		end
		return ok
	end
	local reach, dead = {}, {}
	-- whether a ring lane leads off the ring does not depend on the entry: searched once per lane and
	-- call (planRing's ramp entries run this once per candidate)
	local leaves = {}
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
				if leaves[lk] == nil then leaves[lk] = leadsOff(lk) end
				if not leaves[lk] then dead[lk] = true end
			end
		end
	end
	return reach, dead
end

return M
