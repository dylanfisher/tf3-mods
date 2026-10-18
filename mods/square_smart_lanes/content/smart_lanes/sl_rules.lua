-- Smart Lanes: pure lane rules (no api.* calls), unit-tested in tests/square_smart_lanes/.
-- Turns the per-node views of sl_ring.lua into LaneConnection sets, keeps the engine's tram
-- connections and every connection touching a bus-only lane (M.mergeTram), models the engine default
-- (sanity check against the probe log), checks that every entry can reach every exit through node
-- connections alone, and holds params and log format.
--
-- A connection is a plain table { segment0, lane0, segment1, lane1, withRoad, withTram }
-- (LaneConnection, api/tealdef/api/type.d.tl:1197-1213).

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"

local M = {}

M.MOD_ID = "square_smart_lanes"
M.PREFIX = "[SQRL]"

-- Layouts. The road tool applies one layout, the most fitting one ("turbo", shown as "Smart lanes"):
-- lanes matched one to one, plus the exit-only outer lane wherever the ring qualifies (every exit on
-- the ring has >= 2 lanes, no skipped junction, >= 3 ring lanes: 2-lane rings get matched lanes,
-- M.matchedDefault, and with one-lane exits the mid-node spiral, M.spiralDefault); otherwise plain
-- matched lanes (reason logged). The automatic rule after a build is "two_lane": the same, but exit-only only when
-- every junction of the ring is a seed; the automatic pass seeds every arm junction of a ring a build
-- touched (M.autoSeeds), so there it is the same as "turbo" unless a junction was edited by hand.
-- "matched" (never exit-only) stays for tests and fallbacks;
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

--- Whether connection c starts or ends on a bus-only lane: bus = Ring.busLanes at its node
-- ({ [seg] = { [lane] = true } }, nil: no bus lane there, always false).
function M.touchesBus(c, bus)
	if bus == nil then return false end
	local a, b = bus[c.segment0], bus[c.segment1]
	return (a ~= nil and a[c.lane0] == true) or (b ~= nil and b[c.lane1] == true)
end

--- `list` without the connections touching a bus-only lane (M.touchesBus); the list itself when bus is nil.
function M.withoutBus(list, bus)
	if bus == nil then return list or {} end
	local out = {}
	for _, c in ipairs(list or {}) do
		if not M.touchesBus(c, bus) then out[#out + 1] = c end
	end
	return out
end

--- connsText without the connections touching a bus-only lane: the "same" checks of a write (VERIFY, the
-- free kerb turn's re-check, the tool's Reset snapshot), so a bus connection the player adds or edits
-- never counts as a change of ours.
function M.carText(list, bus)
	return M.connsText(M.withoutBus(list, bus))
end

--- `list`'s connections that touch no bus-only lane plus `current`'s that do, exactly as they are (the
-- tool's Reset from a snapshot: the lanes as before the Apply, the bus connections as the player has them
-- now). The list carries `bus` as M.mergeTram's.
function M.keepBus(list, current, bus)
	if bus == nil then return list end
	local out = M.withoutBus(list, bus)
	for _, c in ipairs(current or {}) do
		if M.touchesBus(c, bus) then out[#out + 1] = c end
	end
	out.bus = bus
	return out
end

--- connsText of the road connections only (tram flags and tram-only connections ignored, as
-- mergeTram leaves them alone; connections touching a bus-only lane too when `bus` is given, Ring.busLanes):
-- the tool's lane status badge compares with this.
--- Whether every approach of `list` (road connections not touching a bus-only lane, by segment0) enters on
-- exactly one lane: a junction of roads with one car lane each way, where the game's lanes and smart lanes
-- are the same (nothing to improve; the tool's lane status says so). false for an empty list.
function M.oneLaneEach(list, bus)
	local lanes, any = {}, false
	for _, c in ipairs(list or {}) do
		if c.withRoad and not M.touchesBus(c, bus) then
			any = true
			local l = lanes[c.segment0]
			if l == nil then
				lanes[c.segment0] = c.lane0
			elseif l ~= c.lane0 then
				return false
			end
		end
	end
	return any
end

function M.roadText(list, bus)
	local road = {}
	for _, c in ipairs(list or {}) do
		if c.withRoad and not M.touchesBus(c, bus) then
			road[#road + 1] = M.conn(c.segment0, c.lane0, c.segment1, c.lane1, true, false)
		end
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
-- fresh: every ring junction node is planned (a seed) this time, so the whole ring gets the same
-- layout (the tool's Turbo layout passes true; the automatic pass seeds whole rings, M.autoSeeds, and
-- is not fresh only around a junction edited by hand).
-- Returns { turbo, reason }: turbo = the outer lane exits only. Only when every exit on the ring
-- has at least two lanes (so a vehicle in the outer lane can always leave at the next arm) and the
-- whole ring is planned. reason (when not turbo): one_lane_ring, skip_node, no_exit,
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

---------------------------------------------------------------------------
-- Ring layout variants (zone modes for the Stress Test bench; PLAN.md "Ring layout variants (bench)").
-- Only inside zones of these modes (sl_zones.lua); everywhere else the rules above, unchanged.

M.RING_VARIANTS = { "sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread", "sl_rsplit", "sl_rmid",
	"sl_rmid2", "sl_rturbo_in" }
M.RING_VARIANT_SET = {}
for _, k in ipairs(M.RING_VARIANTS) do M.RING_VARIANT_SET[k] = true end
-- variants whose entry-only ramp junctions may take their own ring lane (rule 5), as "turbo" today
local VARIANT_OWN_ENTRY = { sl_rturbo = true, sl_rspread = true }

--- Road connections of ring junction v (sl_ring nodeView, kind "arm") under ring layout variant `variant`
-- (M.RING_VARIANTS). ctx: { turbo = the ring qualifies for the exit-only outer lane (M.ringPlan with fresh =
-- true), A = ring junctions with exits }. Lanes kerb first (o1 = outer). A 1-lane ring: matched lanes (as the
-- automatic rule, which has no exit-only there). See PLAN.md for the rules and their counts.
function M.variantConns(v, variant, ctx)
	ctx = ctx or {}
	local Rn, E, N = #v.o_in, #v.x, #v.e
	if Rn < 2 or variant == "sl_rmatch" then return M.twoLaneConns(v, { turbo = false }) end
	if variant == "sl_rturbo" then return M.twoLaneConns(v, { turbo = ctx.turbo == true }) end
	local list, seen = {}, {}
	local function enter()
		for j = 1, N do push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[math.min(j, Rn)]) end
	end
	if variant == "sl_rout1" then
		-- only the outer lane leaves, into every exit lane; every ring lane continues; entries 1:1
		for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		for j = 1, E do push(list, seen, v.ringIn, v.o_in[1], v.arm, v.x[j]) end
		enter()
		return list
	end
	if variant == "sl_r2exit" then
		-- the two outer lanes leave (o1 exit-only into x1, o2 into x2..x_E); the inner lanes only circulate
		for i = 1, Rn do
			if not (i == 1 and E >= 2) then push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		end
		if E >= 1 then push(list, seen, v.ringIn, v.o_in[1], v.arm, v.x[1]) end
		for j = 2, E do push(list, seen, v.ringIn, v.o_in[2], v.arm, v.x[j]) end
		enter()
		return list
	end
	if variant == "sl_rspiral" then
		-- spiral by destination: D = min(R, A) lanes (A = the ring's junctions with exits, the own arm's U-turn
		-- included); at a junction with exits the outer lane leaves (into every exit lane) and lanes 2..D shift one
		-- lane outwards; the innermost spiral lane also circulates when the ring has more exits than spiral lanes;
		-- lanes past D circulate. Entry lane j joins lane min(j, D) (it leaves at the j-th exit downstream); the
		-- innermost entry lane also joins the deeper spiral lanes (the farther exits and the U-turn stay reachable)
		local A = ctx.A or 0
		local D = math.max(1, math.min(Rn, A))
		if E > 0 then
			for j = 1, E do push(list, seen, v.ringIn, v.o_in[1], v.arm, v.x[j]) end
			for i = 2, Rn do
				if i <= D then push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i - 1]) end
				if i > D or (i == D and D < A) then push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
			end
		else
			for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		end
		for j = 1, N do
			push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[math.min(j, D)])
			if j == N then
				for i = N + 1, D do push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[i]) end
			end
		end
		return list
	end
	if variant == "sl_rsplit" then
		-- the spiral with its inward lane change moved off the junction (PLAN.md "Mid-node spiral (sl_rsplit)"):
		-- here as sl_rspiral (the outer lane exits only, the spiral lanes shift one lane outwards, the innermost
		-- spiral lane also circulates when D < A), but every entry lane joins only its own lane o_min(j, D): the
		-- entering traffic crosses no shifting stream. The move inwards (o_i -> o_(i+1)) is made at the ring's
		-- plain node between this junction and the next (M.splitMidConns). planRing gives this variant only with
		-- such a node on every stretch (else sl_rspiral, M.splitMids)
		local A = ctx.A or 0
		local D = math.max(1, math.min(Rn, A))
		if E > 0 then
			for j = 1, E do push(list, seen, v.ringIn, v.o_in[1], v.arm, v.x[j]) end
			for i = 2, Rn do
				if i <= D then push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i - 1]) end
				if i > D or (i == D and D < A) then push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
			end
		else
			for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		end
		for j = 1, N do push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[math.min(j, D)]) end
		return list
	end
	if variant == "sl_rmid" then
		-- no lane change at the junction (PLAN.md "Mid-node lane changes (sl_rmid)"): the outer lanes leave only, the
		-- others go straight on only; without exits every lane goes straight on. Every lane change, inwards and outwards,
		-- is made at the ring's plain nodes between two junctions (M.midBothConns); planRing gives this variant only with
		-- such a node on every stretch (ctx.m: the fewest on one stretch)
		-- X exit-only lanes o1..oX, X = min(E, floor(R / 2), m) (at least 1): the outer half of the ring leaves, the
		-- inner half circulates, and a vehicle entering in o1 for a farther exit reaches o_(X+1) on the m mid nodes of
		-- one stretch (one lane each); one in the innermost lane reaches o_X there when R - X <= m. o_i -> x_i for i < X,
		-- o_X -> x_X..x_E (a fan into the arm's other exit lanes); o_i (i > X) straight only. Entries lane for lane,
		-- e_j -> o_min(j, R): the entry lanes into the exit-only lanes meet no ring stream, the inner ones join their
		-- circulating lane (the give-way); nothing crosses
		local X = math.max(1, math.min(E, math.floor(Rn / 2), ctx.m or 1))
		if E > 0 then
			for i = 1, X - 1 do push(list, seen, v.ringIn, v.o_in[i], v.arm, v.x[i]) end
			for j = X, E do push(list, seen, v.ringIn, v.o_in[X], v.arm, v.x[j]) end
			for i = X + 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		else
			for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		end
		for j = 1, N do push(list, seen, v.arm, v.e[j], v.ringOut, v.o_out[math.min(j, Rn)]) end
		return list
	end
	if variant == "sl_rmid2" then
		-- sl_rmid for wider exits (PLAN.md "Ring lane use (in progress)"): as sl_rmid (X exit-only lanes o1..oX, no lane
		-- change at the junction, every lane change at the mid nodes, M.midBothConns), but an exit wider than X lanes is
		-- fed by the first circulating lane too: o_(X+1) -> x_(X+1)..x_E, and it also goes straight on, instead of
		-- sl_rmid's fan o_X -> x_X..x_E. Every exit lane is fed by exactly one ring lane; o_(X+1)'s exit crosses no
		-- continuing lane outside it (o1..oX leave). 2-lane ring with 2-lane exits: o1 -> x1 only, o2 -> x2 and straight,
		-- e1 -> o1, e2 -> o2 (the turbo junction), with o1 <-> o2 at the mid nodes: a car entering in the curb lane can move
		-- in for a farther exit, so through traffic is no longer bound to the inner entry lane. Exits of at most X lanes:
		-- exactly sl_rmid
		local X = math.max(1, math.min(E, math.floor(Rn / 2), ctx.m or 1))
		if E > 0 then
			for i = 1, X do push(list, seen, v.ringIn, v.o_in[i], v.arm, v.x[i]) end
			for j = X + 1, E do push(list, seen, v.ringIn, v.o_in[X + 1], v.arm, v.x[j]) end
			for i = X + 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		else
			for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
		end
		enter()
		return list
	end
	if variant == "sl_rturbo_in" then
		-- turbo with the inner lanes fed (PLAN.md "Ring lane use (in progress)"): on a ring where turbo qualifies, an arm
		-- that leaves ring lanes out (R > X = min(E, R)) gets the inner lanes as a spiral: o1 -> x1 only (turbo),
		-- o_i -> x_i and straight for 2 <= i < X, o_X -> x_X only (exit-only), o_i -> o_(i-1) for X < i <= R (one lane
		-- outwards) and o_R also straight (it circles for the far exits and the U-turn). The innermost entry lane also
		-- feeds the lanes inside its own (e_N -> o_N..o_R, a split). No two ring lanes into one lane, every exit lane fed
		-- by one ring lane, every entry reaches every exit without a lane change on a segment. An arm with R <= X, a ring
		-- where turbo does not qualify (a one-lane exit): sl_rturbo, the entries' split included only with turbo
		if ctx.turbo ~= true then return M.twoLaneConns(v, { turbo = false }) end
		local X = M.exitLanes(Rn, E)
		if E > 0 and Rn > X then
			push(list, seen, v.ringIn, v.o_in[1], v.arm, v.x[1])
			for i = 2, X - 1 do
				push(list, seen, v.ringIn, v.o_in[i], v.arm, v.x[i])
				push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i])
			end
			for j = X, E do push(list, seen, v.ringIn, v.o_in[X], v.arm, v.x[j]) end
			for i = X + 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i - 1]) end
			push(list, seen, v.ringIn, v.o_in[Rn], v.ringOut, v.o_out[Rn])
		else
			for _, c in ipairs(M.twoLaneConns(v, { turbo = true })) do push(list, seen, c.segment0, c.lane0, c.segment1, c.lane1) end
		end
		enter()
		if N > 0 and N < Rn then
			for i = N + 1, Rn do push(list, seen, v.arm, v.e[N], v.ringOut, v.o_out[i]) end
		end
		return list
	end
	if variant == "sl_rspread" then
		-- turbo, and the lanes the arm leaves out: the inner ring lanes leave into the innermost exit lane, the
		-- innermost entry lane splits into them
		local base = M.twoLaneConns(v, { turbo = ctx.turbo == true })
		for _, c in ipairs(base) do push(list, seen, c.segment0, c.lane0, c.segment1, c.lane1) end
		local X = M.exitLanes(Rn, E)
		if E > 0 and Rn > X then
			for i = X + 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.arm, v.x[X]) end
		end
		if N > 0 and Rn > N then
			for i = N + 1, Rn do push(list, seen, v.arm, v.e[N], v.ringOut, v.o_out[i]) end
		end
		return list
	end
	error("unknown ring variant " .. tostring(variant))
end

--- sl_rsplit's plain ring node between two junctions (sl_ring nodeView, kind "plain"): every ring lane continues
-- in its own lane, and the spiral lanes may move one lane inwards: o_i -> o_(i+1) for i < D (D = min(R, A), as
-- variantConns). A vehicle that entered in o1 stays there for the next exit or moves in for a farther one; the
-- junction after it shifts it out again (o_(i+1) -> o_i). Lanes outer first (o1 = outer). 1-lane ring: straight.
function M.splitMidConns(v, ctx)
	ctx = ctx or {}
	local list, seen = {}, {}
	local Rn = #v.o_in
	local D = math.max(1, math.min(Rn, ctx.A or 0))
	for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
	for i = 1, D - 1 do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i + 1]) end
	return list
end

--- sl_rmid's plain ring node between two junctions (kind "plain"): every ring lane straight on, and every pair of
-- neighbouring lanes changes either way: o_i -> o_(i+1) and o_(i+1) -> o_i for i < R. The two changes of a pair cross
-- at the node. A vehicle moves one lane per mid node: in towards the centre lanes, out before its exit. 1-lane ring:
-- straight.
function M.midBothConns(v)
	local list, seen = {}, {}
	local Rn = #v.o_in
	for i = 1, Rn do push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i]) end
	for i = 1, Rn - 1 do
		push(list, seen, v.ringIn, v.o_in[i], v.ringOut, v.o_out[i + 1])
		push(list, seen, v.ringIn, v.o_in[i + 1], v.ringOut, v.o_out[i])
	end
	return list
end

--- The ring layout variants that write the ring's mid nodes (M.splitMids), with their mid node rule.
M.MID_VARIANTS = { sl_rsplit = true, sl_rmid = true, sl_rmid2 = true }
--- What their junctions get on a ring without a mid node on every entry-to-exit stretch (res.layout).
M.MID_FALLBACK = { sl_rsplit = "sl_rspiral", sl_rmid = "sl_rspiral", sl_rmid2 = "sl_rturbo" }
--- The variant zones in which Smart Lanes adds the missing mid nodes itself (sl_split, as the default spiral does:
-- res.splitWanted); the other mid-node variants fall back (the bench builds their mid nodes, Sheet 4).
M.SPLIT_VARIANTS = { sl_rmid2 = true }

--- sl_rsplit's and sl_rmid's mid nodes of a ring: every plain ring node of every stretch between two neighbouring ring
-- junctions (views of kind ~= "plain", in travel order; a vehicle can change one lane at each). Returns { [node] = true },
-- the list in ring order and m, the fewest mid nodes on one stretch (>= 1), or nil and why: "one_lane_ring" (R < 2: nothing to change), "no_junction",
-- "no_mid_nodes" (a stretch without a plain node: square_roundabouts builds them only with its dev override
-- ringMid, plans/square_roundabouts/PLAN.md "Ring mid nodes (dev)"). views: { [node] = sl_ring nodeView }. Bounded by
-- the ring's nodes (Ring.MAX_RING_SEGS): every stretch walk ends at the next junction, all of them after n steps.
function M.splitMids(world, ring, views)
	if (ring.lanes or 0) < 2 then return nil, "one_lane_ring" end
	local nodes, segs = ring.nodes, ring.segs
	local n = #nodes
	local first = nil
	for i = 1, n do
		local v = views[nodes[i]]
		if v and v.kind ~= "plain" then first = i; break end
	end
	if first == nil then return nil, "no_junction" end
	local set, list, fewest = {}, {}, nil
	local i, steps = first, 0
	repeat
		-- the stretch from junction i to the next junction: its plain nodes. Needed only on a stretch from a junction
		-- with entries to one with exits (where an entering car may have to move in); the stretch between a
		-- splitter's exit and entry legs of one arm needs none
		local plain, k = 0, i
		local vi = views[nodes[i]]
		repeat
			k = k % n + 1
			local v = views[nodes[k]]
			if v and v.kind == "plain" then
				plain = plain + 1
				set[nodes[k]] = true
				list[#list + 1] = nodes[k]
			end
			steps = steps + 1
		until (views[nodes[k]] and views[nodes[k]].kind ~= "plain") or steps > n
		local vk = views[nodes[k]]
		local needed = vi ~= nil and vk ~= nil and #(vi.e or {}) > 0 and #(vk.x or {}) > 0
		if needed then
			if plain == 0 then return nil, "no_mid_nodes" end
			if fewest == nil or plain < fewest then fewest = plain end
		end
		i = k
	until i == first or steps > n
	if fewest == nil then return nil, "no_mid_nodes" end
	return set, list, fewest
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

--- The engine default model for a ring junction with the node's tram and bus connections kept (the
-- tool's Reset fallback when the engine does not regenerate the node itself).
function M.defaultConns(v, current)
	return M.mergeTram(M.engineDefault(v), current, v.bus)
end

--- Final connection list for a node: the rule's road connections plus the engine's tram
-- connections from `current`, untouched (a lane pair with both keeps withTram on the road entry), and
-- every connection of `current` touching a bus-only lane (bus = Ring.busLanes, the view's v.bus; nil:
-- none), exactly as it is (withRoad and withTram as read): the rules plan car lanes only and never name a
-- bus lane, so the game's or the player's bus connections stay (user request 2026-10-13). The list carries
-- the set as out.bus (not a list entry): the write's VERIFY (sl_write W.addItem) leaves those out.
function M.mergeTram(roadConns, current, bus)
	local out, byKey = {}, {}
	for _, c in ipairs(current or {}) do
		if M.touchesBus(c, bus) then
			local t = M.conn(c.segment0, c.lane0, c.segment1, c.lane1, c.withRoad == true, c.withTram == true)
			byKey[key(t)] = t
			out[#out + 1] = t
		elseif c.withTram then
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
	out.bus = bus
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
-- world: sl_ring world; ring: sl_ring.findRing result; seeds: set {nodeId = true} of the nodes to
-- write (the automatic pass: M.autoSeeds, normally every arm junction of the ring; the tool: the
-- picked junction or every ring junction); variant:
-- "two_lane" (automatic: exit-only outer lane only when every ring junction is a seed, fresh),
-- "matched" (never exit-only),
-- "turbo" (exit-only wherever the ring qualifies, fresh or not; two_lane and turbo give a 2-lane ring matched lanes,
-- M.matchedDefault: res.default = true, defaultWhy "two_lane_exits", layout "matched", turboReason "two_lane_ring";
-- or the mid-node spiral, M.spiralDefault: defaultWhy "one_lane_exits"), "engine" (the tool's Game default
-- and Reset: the engine default model, M.defaultConns), anything else ("game") is skipped;
-- currentConns(nodeId) -> list of the node's current connections (plain tables).
-- Returns { fresh, turbo, turboReason, nodes = { {node, status, reason, before, after, conns, entry,
-- entryWhy} } }.
-- Ring layout variants (M.RING_VARIANTS) add res.variant (the zone's) and res.layout (the one the junctions got:
-- sl_rsplit / sl_rmid without a mid node on every stretch get sl_rspiral, sl_rmid2 sl_rturbo: M.MID_FALLBACK,
-- res.split = M.splitMids' reason; res.splitWanted = true when Smart Lanes should add the mid nodes itself: the default
-- spiral and M.SPLIT_VARIANTS, reason no_mid_nodes); the mid-node variants with them add res.mids (their count), res.midsPerStretch (the fewest on one stretch) and one node result per mid node
-- after the junctions (r.mid = true, a plain view).
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
	-- the default rule on a 2-lane ring whose every exit has >= 2 lanes (M.matchedDefault, PLAN.md "Default: matched
	-- lanes on 2-lane rings with wide exits"): matched lanes, no exit-only outer lane (user decision 2026-10-15 after
	-- bench s5: matched 89.1 vs turbo 73.8 cars/min, ring lane use ~50/50 vs ~20/80). Fresh or not: the same lanes.
	local matchedDefault = (variant == "two_lane" or variant == "turbo") and M.matchedDefault(ring.lanes, junctions)
	if matchedDefault then plan = { turbo = false, reason = "two_lane_ring" } end
	local res = { fresh = fresh, turbo = plan.turbo, turboReason = plan.reason, nodes = {} }
	if matchedDefault then res.default, res.defaultWhy, res.layout = true, "two_lane_exits", "matched" end
	local isVariant = M.RING_VARIANT_SET[variant] == true
	local known = variant == "two_lane" or variant == "matched" or variant == "turbo" or variant == "engine" or isVariant
	-- rule 5 (the ramp's own-lane entry) stays on matched-default rings: the zip merge sits right before an exit of
	-- >= 2 lanes (M.rampEntryWhy), as on the Roundabout Interchange's mixed rings, which have always been matched
	local ownEntry = variant == "two_lane" or variant == "turbo" or VARIANT_OWN_ENTRY[variant] == true
	-- the default rule on a 2-lane ring whose every exit has one lane (M.spiralDefault, PLAN.md "Default: the mid-node
	-- spiral"): sl_rmid (no lane change at the arms, every lane change at the mid nodes; user decision 2026-10-14 after
	-- Sheet 4 v4 / v5, before that sl_rsplit), sl_rspiral without a mid node on every stretch, written as that variant
	local layoutVariant = isVariant and variant or nil
	if (variant == "two_lane" or variant == "turbo") and M.spiralDefault(ring.lanes, junctions, plan) then
		layoutVariant = "sl_rmid"
		res.default, res.defaultWhy = true, "one_lane_exits"
		ownEntry = false
	end
	-- ring layout variants: the ring-level facts their rules need (turbo as for a fresh ring; exit junctions)
	local vctx = nil
	if layoutVariant ~= nil then
		local A = 0
		for _, v in ipairs(junctions) do
			if v.kind == "arm" and #v.x > 0 then A = A + 1 end
		end
		vctx = { turbo = M.ringPlan(ring.lanes, junctions, true).turbo, A = A }
		res.layout = layoutVariant
		if isVariant then res.variant = variant end
	end
	-- sl_rsplit / sl_rmid (M.MID_VARIANTS): their mid nodes (M.splitMids), else the junctions get sl_rspiral
	-- (res.layout; res.split = why)
	local mids, midList = nil, nil
	local midRule = ((layoutVariant == "sl_rmid" or layoutVariant == "sl_rmid2") and M.midBothConns)
		or (layoutVariant == "sl_rsplit" and M.splitMidConns) or nil
	if midRule ~= nil then
		local why, fewest
		mids, why, fewest = M.splitMids(world, ring, views)
		if mids == nil then
			res.layout, res.split = M.MID_FALLBACK[layoutVariant] or "sl_rspiral", why
			-- Smart Lanes splits the stretches itself (sl_split; the automatic pass and the tool's ring Apply): the
			-- default spiral, and the variant zones of M.SPLIT_VARIANTS
			if why == "no_mid_nodes" and (res.default == true or M.SPLIT_VARIANTS[variant] == true) then res.splitWanted = true end
		else
			midList = why
			res.mids, res.midsPerStretch = #midList, fewest
			-- sl_rmid: a vehicle changes one lane per mid node, so at most that many ring lanes may exit
			vctx.m = fewest
		end
	end
	local junctionVariant = res.layout or variant
	-- the default spiral writes its mid nodes with the whole ring (every junction a seed: the automatic pass's whole
	-- rings, the tool's ring Apply), not with one junction alone
	local midSeeded = function(n) return seeds[n] == true or (res.default == true and fresh) end
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
			if variant == "engine" then conns = M.defaultConns(v, cur)
			elseif layoutVariant ~= nil then conns = M.mergeTram(M.variantConns(v, junctionVariant, vctx), cur, v.bus)
			else conns = M.mergeTram(M.twoLaneConns(v, plan), cur, v.bus) end
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
	-- the mid nodes (plain ring nodes: r.mid = true), after the junctions, in ring order
	for _, n in ipairs(midList or {}) do
		local v = views[n]
		local r = { node = n, view = v, mid = true }
		if not midSeeded(n) then
			r.status = "untouched"
		else
			local cur = currentConns(n) or {}
			local conns = M.mergeTram(midRule(v, vctx), cur, v.bus)
			r.before, r.after = M.roadCount(cur), M.roadCount(conns)
			r.conns, r.cur = conns, cur
			if M.connsText(conns) == M.connsText(cur) then r.status = "same" else r.status = "apply" end
		end
		res.nodes[#res.nodes + 1] = r
	end
	-- Reset ("engine"): plain ring nodes with more than the straight-on connections (a mid node an earlier spiral
	-- wrote) get the game's straight-on lanes back; plain nodes already straight on are left out (r.mid = true)
	if variant == "engine" then
		for _, n in ipairs(ring.nodes) do
			local v = views[n]
			if v.kind == "plain" and seeds[n] then
				local cur = currentConns(n) or {}
				local conns = M.defaultConns(v, cur)
				if M.roadText(cur, v.bus) ~= "" and M.roadText(cur, v.bus) ~= M.roadText(conns, v.bus) then
					res.nodes[#res.nodes + 1] = { node = n, view = v, mid = true, status = "apply", conns = conns, cur = cur,
						before = M.roadCount(cur), after = M.roadCount(conns) }
				end
			end
		end
	end
	return res
end

--- Whether the default rule ("two_lane", the tool's "turbo") gives ring junctions `junctions` (planRing's views) the
-- mid-node layout (sl_rmid; sl_rspiral without mid nodes): a 2-lane ring with an exit, no skipped junction, and
-- every exit one lane (ringPlan reason narrow_exit, and no 2+-lane exit: a mixed ring such as the Roundabout
-- Interchange's keeps the matched lanes and its ramp rules). Measured: Stress Test Sheet 4 v2 / v3 (RESULTS.md).
function M.spiralDefault(ringLanes, junctions, plan)
	if ringLanes ~= 2 or plan == nil or plan.reason ~= "narrow_exit" then return false end
	local any = false
	for _, v in ipairs(junctions) do
		if v.kind == "arm" and #v.x > 0 then
			any = true
			if #v.x ~= 1 then return false end
		end
	end
	return any
end

--- Whether the default rule ("two_lane", the tool's "turbo") gives ring junctions `junctions` (planRing's views)
-- matched lanes instead of the exit-only outer lane (PLAN.md "Default: matched lanes on 2-lane rings with wide exits";
-- user decision 2026-10-15, RESULTS.md bench s5): a 2-lane ring where turbo would qualify (an exit, no skipped
-- junction, every exit >= 2 lanes; M.ringPlan with fresh = true). 3- and 4-lane rings keep turbo; 2-lane rings with
-- one-lane exits get the spiral (M.spiralDefault); mixed exits were matched lanes already (reason narrow_exit).
-- Ring layout variant zones (sl_rturbo ...) are not affected: the bench still builds turbo twins.
function M.matchedDefault(ringLanes, junctions)
	if ringLanes ~= 2 then return false end
	return M.ringPlan(ringLanes, junctions, true).turbo == true
end

--- Which of the forms the automatic pass accepts at ring junction v (sl_ring nodeView, kind "arm") its
-- current connections have, compared by their road connections only (M.roadText: order-insensitive, tram
-- flags, tram-only connections and connections touching a bus-only lane ignored): "turbo" / "matched" (M.twoLaneConns with and without the
-- exit-only outer lane: an older Smart Lanes pass may have written matched lanes on a qualifying ring, and before
-- 2026-10-15 turbo on 2-lane rings whose default is matched lanes now, M.matchedDefault: both are ours, so such a
-- ring is re-planned whole, never kept as a hand edit),
-- "mid" / "split" / "spiral" (the default's junction forms on a 2-lane ring, and the earlier default's, with ctx = { A }),
-- "own_lane" (M.rampEntryConns, an entry-only ramp narrower than the ring), "engine" (M.engineDefault, the
-- engine's own model) or "none" (no road connection: no config read, as the tests' worlds and
-- M.rampEntries treat it). nil: anything else, a hand edit (Crossing Tool), or a form this model does not
-- know (an engine default the model misses, a ring layout variant written inside a bench zone).
function M.ringForm(v, current, ctx)
	local cur = M.roadText(current, v.bus)
	if cur == "" then return "none" end
	-- the default spiral of a 2-lane ring with one-lane exits (M.spiralDefault): sl_rsplit or sl_rspiral at the
	-- junction (ctx.A: the ring's junctions with exits)
	if ctx ~= nil and #v.o_in == 2 then
		if cur == M.roadText(M.variantConns(v, "sl_rmid", ctx)) then return "mid" end
		if cur == M.roadText(M.variantConns(v, "sl_rsplit", ctx)) then return "split" end
		if cur == M.roadText(M.variantConns(v, "sl_rspiral", ctx)) then return "spiral" end
	end
	if cur == M.roadText(M.twoLaneConns(v, { turbo = true })) then return "turbo" end
	if cur == M.roadText(M.twoLaneConns(v, { turbo = false })) then return "matched" end
	if #v.x == 0 and #v.e > 0 and #v.e < #v.o_in and cur == M.roadText(M.rampEntryConns(v)) then return "own_lane" end
	if cur == M.roadText(M.engineDefault(v)) then return "engine" end
	return nil
end

--- The automatic pass's seeds for a ring one of whose nodes the build seeded (PLAN.md "Whole rings in the
-- automatic pass"): every arm junction of the ring, so planRing ("two_lane") decides the exit-only outer lane
-- from the ring's own qualification and writes every junction alike: the layout does not depend on the order
-- the arms were built in. Skipped junctions (kind "skip") are not added (they are never written; the ring
-- then gets no exit-only lane anyway, reason skip_node), plain ring nodes neither.
-- The player's hand edits: an arm junction the build did not seed is added only when its current connections
-- are one of M.ringForm's forms. When any is not, the ring keeps the seeds of the build (handEdit lists those
-- junctions): planRing's freshness rule then gives the seeds matched lanes (not_fresh) and leaves the rest
-- alone, as before this rule. Turbo is a ring-level decision (the outer lane of every exit junction exits
-- only), so it is never applied around a junction we may not write.
-- held(n) (optional): true while a proposal of ours naming n is unanswered; such an added junction is not
-- read (its read would miss that write): the result is { wait = n } and the caller tries again later.
-- currentConns(nodeId) -> the node's current connections (read in the world of the write).
-- Returns { seeds, whole, extra = {added nodes}, handEdit = {nodes} } (lists in ring order), or { wait = n }.
-- whole: every arm junction of the ring is a seed.
function M.autoSeeds(world, ring, seeds, currentConns, held)
	local extraViews = {}
	for _, n in ipairs(ring.nodes) do
		if not seeds[n] then
			local v = Ring.nodeView(world, ring, n)
			if v.kind == "arm" then extraViews[#extraViews + 1] = v end
		end
	end
	if held ~= nil then
		for _, v in ipairs(extraViews) do
			if held(v.node) then return { wait = v.node } end
		end
	end
	-- the ring's junctions with exits (the spiral forms' A)
	local A = 0
	for _, n in ipairs(ring.nodes) do
		local v = Ring.nodeView(world, ring, n)
		if v.kind == "arm" and #v.x > 0 then A = A + 1 end
	end
	local fctx = { A = A }
	local extra, handEdit = {}, {}
	for _, v in ipairs(extraViews) do
		if M.ringForm(v, currentConns(v.node) or {}, fctx) == nil then
			handEdit[#handEdit + 1] = v.node
		else
			extra[#extra + 1] = v.node
		end
	end
	if #handEdit > 0 then return { seeds = seeds, whole = false, extra = {}, handEdit = handEdit } end
	local out = {}
	for n in pairs(seeds) do out[n] = true end
	for _, n in ipairs(extra) do out[n] = true end
	return { seeds = out, whole = true, extra = extra, handEdit = handEdit }
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
		local own = M.mergeTram(M.rampEntryConns(r.view), r.cur, r.view.bus)
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
	-- car travel only: connections touching a bus-only lane (kept as the game or the player has them) are
	-- left out
	local function carConn(node, c) return c.withRoad and not M.touchesBus(c, Ring.busLanes(world, node)) end
	local function lanesOf(node, seg, lane)
		if not laneChange then return { lane } end
		local out, seen = {}, {}
		for _, c in ipairs(connsByNode[node] or {}) do
			if carConn(node, c) and c.segment0 == seg and not seen[c.lane0] then
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
			if carConn(node, c) and c.segment0 == seg and c.lane0 == lane then out[#out + 1] = c end
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
