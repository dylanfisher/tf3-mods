-- Smart Lanes: which junctions lose their traffic lights (pure, no api.* calls), unit-tested in
-- tests/square_smart_lanes/test_lights.lua.
--
-- From 1950 the game puts lights on any junction whose preference is AUTO (base
-- infrastructure/traffic_light/traffic_light_config.res.lua trafficLightYearFrom), and a
-- construction's nodes all start as AUTO. Lights belong to a node and stop every vehicle passing
-- it, so on a roundabout junction or where a slip lane or ramp leaves or joins a road they stop
-- traffic that should only give way or merge. Smart Lanes sets those nodes to NO (setting "Remove
-- traffic lights"); ordinary crossroads keep AUTO. The tool's Reset sets AUTO again.
--
-- A node state is { pref = TrafficLightPreference value, light = true when the node has a
-- BASE_NODE_TRAFFIC_LIGHT component }; `enum` is api.type.enum.TrafficLightPreference (YES/NO/AUTO).

local L = {}

L.OFF = "off"
L.AUTO = "auto"

--- Ring junctions whose lights go: the arm junctions the plan handled ("apply" or "same").
-- Skipped nodes keep theirs: a road through the centre ("Road + traffic lights" asks for lights
-- there), a second ring touching. Plain ring nodes have no junction. A junction with a bus lane
-- (the view's bus, Ring.busLanes) keeps its lights too: its car lanes are set, but a light there may be
-- the player's bus priority (user request 2026-10-13: "I add the bus connections / bus light phases myself").
function L.ringNodes(plan)
	local out = {}
	for _, r in ipairs(plan.nodes or {}) do
		if (r.status == "apply" or r.status == "same") and r.view and r.view.kind == "arm" and r.view.bus == nil then
			out[#out + 1] = r.node
		end
	end
	return out
end

--- Whether nodes of an sl_slip view case keep the game's lights: crossroads and T-junctions (case
-- "X", sl_cross.lua: there the lights take turns between crossing streams) and plain lane drops and
-- gains (case "D": no junction there; whatever the player or the game set stays). bus (optional): the
-- view's bus-only lane ends (Ring.busLanes); a node with a bus lane keeps its lights whatever the case
-- (a light there may be the player's bus priority, as L.ringNodes).
function L.keepsLights(case, bus)
	return case == "X" or case == "D" or bus ~= nil
end

--- Whether a planned slip node (sl_slip S.plan result) loses its lights (not L.keepsLights).
function L.slipNode(r)
	return r ~= nil and (r.status == "apply" or r.status == "same") and not (r.view and L.keepsLights(r.view.case, r.view.bus))
end

--- The preference value for a target, nil when the enum is missing.
function L.prefFor(target, enum)
	if enum == nil then return nil end
	if target == L.OFF then return enum.NO end
	return enum.AUTO
end

--- Whether a node has to be sent to reach `target`: "off" when its preference is not NO or a light
-- still stands; "auto" when its preference is not AUTO. A nil state (no config) is never sent.
function L.needs(state, target, enum)
	if state == nil or enum == nil then return false end
	if target == L.OFF then return state.pref ~= enum.NO or state.light == true end
	return state.pref ~= enum.AUTO
end

--- Whether a node counts as lit for the crossroads rule (sl_cross X.allocateView: the extra straight
-- shares stay only under lights): true for preference YES, or AUTO with a light standing; false for
-- NO; nil (unknown) for AUTO without a light, a missing state or enum. AUTO without a light is not
-- "unlit": the game adds AUTO lights from 1950 (trafficLightYearFrom) and only at some junctions, and
-- whether every light already stands when the automatic pass reads the node is not known (in game
-- 2026-10-11 the Channelized X slip nodes had theirs then: LIGHTS src=auto light=true; other new
-- AUTO nodes had none), so unknown keeps the rule's shares as before.
function L.litOf(state, enum)
	-- a missing preference never matches a missing enum value (nil == nil would read as unlit)
	if state == nil or enum == nil or state.pref == nil then return nil end
	if state.pref == enum.NO then return false end
	if state.pref == enum.YES then return true end
	if state.light == true then return true end
	return nil
end

--- Name of a preference value for the log ("yes" / "no" / "auto" / the raw value).
function L.prefName(pref, enum)
	if enum ~= nil then
		if pref == enum.YES then return "yes" end
		if pref == enum.NO then return "no" end
		if pref == enum.AUTO then return "auto" end
	end
	return tostring(pref)
end

---------------------------------------------------------------------------
-- Free kerb turn at traffic lights (setting "Free kerb turn at traffic lights", sqrl_free_turn:
-- Off / When safe / Always)
--
-- A phase (BaseNodeConfig.trafficLightConfig.states[i]) lists in lockedLanes the 0-based indices of
-- the connections that have red: laneConnections first, then crosswalks (#laneConnections + k - 1;
-- docs/findings.md "Traffic light phases index the lane connections"). The game's default phases
-- lock the kerb turn (right in right-hand traffic) together with its approach. Every Smart Lanes
-- write at a crossroads or T-junction (sl_cross case "X") changes the kerb turn connections' red:
--   * SAFE ("When safe", the default): a kerb connection goes green in a phase where nothing green
--     in that phase crosses its path and no green crosswalk lies on it (L.kerbConflict "cross" /
--     "ped"). A merge (another approach's green stream ending in the kerb turn's exit lane) is
--     allowed (user decision 2026-10-12): an unlocked connection does not give way in TF3 (findings
--     roads.md "A connection unlocked in a phase does not give way"), but in game the freed turners
--     merged into the green stream tolerably and the junction ran more efficiently than with the
--     turn held red ("Later observations" there); a crossing or a green crosswalk stays a hard
--     conflict (pedestrians are avoided only mostly).
--   * FREE ("Always"): out of every phase, conflicts or not (kerb turners cut across green traffic
--     and drive over green crosswalks; the default).
--   * LOCK (the tool's Reset): a kerb connection is red in the phases where every other road
--     connection of its approach is red, as the game's default has it.
-- Only a kerb turn on a dedicated kerb lane is freed (SAFE and FREE; 2026-10-14, a player's report,
-- PLAN.md "Free curb turn: dedicated curb lanes only"): one whose entry lane (segment0, lane0) carries no
-- other connection than kerb turns. A kerb turn that shares its lane with a straight or far movement
-- (a 1-lane approach: every movement from one lane) stays with that lane (L.sharedKerb): red in every
-- phase where all its lane mates are red. Freed there, it was green while the car at the head of the
-- lane waited for a red straight or far movement: the turners queued behind it anyway, and the lane,
-- never empty, kept a demand-actuated phase (canSkip) from ending (inferred from the report: the free
-- curb turn "When safe" stopped phases from skipping; TESTING.md "SH"). Counted in stats.shared (log
-- shared_held=).
-- A freeable kerb turn whose approach has a bus-only entry lane (the kerb set's bus, Ring.busLanes) is freed
-- only in phases where a connection out of such a bus lane is green (2026-10-14, a player's report, not
-- verified in game: with the curbside bus lane red, the stopped buses' collision check reaches ahead into
-- the junction and the car lane's right turn beside it does not drive; PHASES_PLAN.md "Whole lanes and bus
-- lanes"). Freed there it would gain nothing and keep its lane busy; in the other phases it stays as the
-- phases have it. The same rule as the planner's (sl_phaseplan steps 3 / 4b: a car lane with a curb turn
-- joins a phase beside a bus lane only where that bus lane is green). Bus connections themselves are never
-- changed (L.kerbIndices leaves them out).
-- Crosswalk indices and the phases themselves (count, durations) stay; a phase left with nothing
-- red is kept. Tram connections (withTram) are never changed: trams keep the signal; so do connections
-- touching a bus-only lane (L.kerbIndices: the kerb set's bus, sl_cross X.kerbPairs).
--
-- Conflict model (L.kerbConflict; SAFE blocks on cross and ped only), for kerb connection k = approach A -> exit E, exit lane l, in phase p
-- (a connection is green in p when its index is not in p's lockedLanes, after the kerb connections
-- freed before it in the same phase; a kerb connection is freed only when the ones freed before it
-- still pass with it green, so no conflicting pair is freed whatever the order):
--   * merge: a green connection of another approach (segment0 ~= A), road or tram, ends on E in lane
--     l: both streams enter the same lane, and neither gives way. Not blocking under SAFE: the
--     pair is counted as merged (stats.merged, log merged=n).
--   * cross: a green connection of another approach ends on E in a lane on the kerb side of l. The
--     game's lane curve runs from the approach lane's end to the exit lane's start; a kerb turner
--     comes into E from the kerb side, so its curve cuts every stream that ends nearer the kerb, and
--     runs beside the streams that end farther out (those are no conflict). Lane positions come from
--     the exit's lanes kerb first (sl_cross ex.o, carried as the kerb set's value: X.kerbPairs);
--     without them every other green lane of E counts as a crossing (conservative). Other paths do
--     not reach the kerb corner between A and E: the far side's movements and E's own incoming
--     traffic stay on the other side of the junction, and U-turns (> 135 deg) are no exits (sl_cross
--     MAX_TURN_DEG); a U-turn connection the game made that ends on E is caught by the lane rule.
--   * Connections of A itself are A's own phase logic: never a conflict (where A goes, the default
--     already has k green; a kerb turn and A's other lanes do not cross, sl_cross gives each lane a
--     contiguous range of exits).
--   * ped: BaseNodeConfig.crosswalks is a list of entities (api/tealdef/api/engine.d.tl:190), the
--     edges whose end at the node has a crosswalk (inferred: a game-made 3-way node had 3, a dead end
--     1, findings.md "The engine's lane connections at a town junction"; community mods re-point them
--     with the edge ids). A green crosswalk on A or E (the two a kerb turner drives over) is a
--     conflict; one on another of the node's segments is not; a crosswalk entity that is none of
--     the node's segments (or a missing list) counts on every kerb turn (conservative).
-- Each (kerb connection, phase) kept red is counted once under its first kind (cross, ped; a merge
-- never keeps one red since 2026-10-12, so kept= shows no merge); each (kerb connection, phase)
-- freed while a green stream ends in its lane counts once in stats.merged.

L.FREE = "free"
L.SAFE = "safe"
L.LOCK = "lock"

--- The mode for a "Free kerb turn" setting value (Rules.VALUES.freeTurn): nil for Off.
function L.modeFor(setting)
	if setting == "safe" then return L.SAFE end
	if setting == "always" then return L.FREE end
	return nil
end

local function pairKey(a, b) return tostring(a) .. ">" .. tostring(b) end
L.pairKey = pairKey

--- 0-based indices of the kerb turn connections in `conns` (config order, Rules.conn tables):
-- road connections (withRoad, not withTram) whose "segment0>segment1" is in `kerb` (a set, as
-- sl_cross X.kerbPairs: the value is true or the exit's lane positions). Empty for a missing set.
-- A connection touching a bus-only lane (kerb.bus, Ring.busLanes; as sl_rules M.touchesBus) is none:
-- the kerb turn is the kerb car lane's turn, and bus connections keep their signal as trams do.
function L.kerbIndices(conns, kerb)
	local out = {}
	if type(kerb) ~= "table" then return out end
	local bus = type(kerb.bus) == "table" and kerb.bus or nil
	for i, c in ipairs(conns or {}) do
		if c.withRoad == true and c.withTram ~= true and kerb[pairKey(c.segment0, c.segment1)]
			and not (bus ~= nil and ((bus[c.segment0] ~= nil and bus[c.segment0][c.lane0] == true)
				or (bus[c.segment1] ~= nil and bus[c.segment1][c.lane1] == true))) then
			out[#out + 1] = i - 1
		end
	end
	return out
end

--- The exit fan (sl_exitfan zones; the kerb set carries kerbLaneOnly = true, sl_cross X.kerbPairs): of the kerb
-- connections kerbIdx, the ones that may be freed (into the exit's kerb lane: position 1 of the set's lane
-- positions, or positions unknown: the value true) and the held ones (into its other lanes, or a lane the
-- positions do not list: fail closed; they stay red with their approach, as LOCK). Without the flag every kerb connection may be freed (held is empty).
function L.splitKerb(conns, kerbIdx, kerb)
	local free, held = {}, {}
	local only = type(kerb) == "table" and kerb.kerbLaneOnly == true
	for _, j in ipairs(kerbIdx or {}) do
		local c = conns and conns[j + 1]
		local pos = only and c and kerb[pairKey(c.segment0, c.segment1)] or nil
		-- fail closed: a lane the positions do not list (or no connection) is held, never freed
		if only and (c == nil or (type(pos) == "table" and pos[c.lane1] ~= 1)) then
			held[#held + 1] = j
		else
			free[#free + 1] = j
		end
	end
	return free, held
end

--- Of the kerb connections kerbIdx (0-based, L.kerbIndices), the ones on a dedicated kerb lane
-- (dedicated) and the ones whose entry lane (segment0, lane0) also carries another vehicle connection
-- (shared): any road or tram connection out of that lane that is not itself in kerbIdx (a straight,
-- a far turn, a U-turn, a tram, a connection into a bus lane). Third result: per shared one its lane
-- mates (0-based, the other connections of its lane that are not in kerbIdx). An unknown index is left out.
-- allKerb (optional): every kerb connection of the node when kerbIdx is a part of them (the exit fan's
-- free ones, L.splitKerb): a kerb turn into another exit lane is no lane mate (still a kerb pair).
function L.sharedKerb(conns, kerbIdx, allKerb)
	local dedicated, shared, mates = {}, {}, {}
	conns = conns or {}
	local isKerb = {}
	for _, j in ipairs(kerbIdx or {}) do isKerb[j] = true end
	for _, j in ipairs(allKerb or {}) do isKerb[j] = true end
	local byLane = {}
	for i, c in ipairs(conns) do
		if (c.withRoad == true or c.withTram == true) and not isKerb[i - 1] then
			local key = tostring(c.segment0) .. ":" .. tostring(c.lane0)
			local list = byLane[key]
			if list == nil then
				list = {}
				byLane[key] = list
			end
			list[#list + 1] = i - 1
		end
	end
	for _, j in ipairs(kerbIdx or {}) do
		local c = conns[j + 1]
		if c ~= nil then
			local list = byLane[tostring(c.segment0) .. ":" .. tostring(c.lane0)]
			if list ~= nil and #list > 0 then
				shared[#shared + 1] = j
				mates[j] = list
			else
				dedicated[#dedicated + 1] = j
			end
		end
	end
	return dedicated, shared, mates
end

--- The kerb connections that may be freed: L.splitKerb's free ones that are on a dedicated kerb lane
-- (L.sharedKerb). The re-checks count these (W.kerbLocked).
function L.freeable(conns, kerbIdx, kerb)
	local free = L.splitKerb(conns, kerbIdx, kerb)
	return (L.sharedKerb(conns, free, kerbIdx))
end

local function isIndex(l, max)
	-- l % 1 == 0: a whole number (as l == math.floor(l) for the finite l the range test leaves)
	return type(l) == "number" and l >= 0 and l <= max and l % 1 == 0
end

--- What decides kerb connection j's conflicts (L.kerbConflict), worked out once per node: the
-- connections of other approaches that end on j's exit, each with the conflict it is when green
-- ("merge" / "cross" / false: beside it), and the crosswalks that count when green.
local function conflictInfo(conns, j, nCross, ctx)
	local c = conns[j + 1]
	local a, e, l = c.segment0, c.segment1, c.lane1
	local ord = ctx and type(ctx.kerb) == "table" and ctx.kerb[pairKey(a, e)] or nil
	if type(ord) ~= "table" then ord = nil end
	local cands = {}
	for i, d in ipairs(conns) do
		if i - 1 ~= j and d.segment1 == e and d.segment0 ~= a then
			local kind = false
			local pl, pd = ord and ord[l], ord and ord[d.lane1]
			if pl ~= nil and pd ~= nil then
				if pd == pl then kind = "merge" elseif pd < pl then kind = "cross" end
			elseif d.lane1 == l then
				kind = "merge"
			else
				kind = "cross"
			end
			if kind then cands[#cands + 1] = { i - 1, kind } end
		end
	end
	local cws = ctx and ctx.crosswalks or {}
	local segs = ctx and ctx.segs or {}
	local peds = {}
	for k = 1, nCross or 0 do
		local cw = cws[k]
		if cw == nil or cw == a or cw == e or not segs[cw] then peds[#peds + 1] = #conns + k - 1 end
	end
	return { cands = cands, peds = peds }
end

--- L.kerbConflict on conflictInfo: "merge" before "cross" before "ped", as there.
local function conflictOf(info, green)
	local cross = false
	for _, x in ipairs(info.cands) do
		if green(x[1]) then
			if x[2] == "merge" then return "merge" end
			cross = true
		end
	end
	if cross then return "cross" end
	for _, i in ipairs(info.peds) do
		if green(i) then return "ped" end
	end
	return nil
end

--- What keeps kerb connection j red under SAFE: "cross" before "ped", nil when it may go; second
-- value true when a green stream ends in its lane (a merge: allowed, counted as merged).
local function blockOf(info, green)
	local cross, merge = false, false
	for _, x in ipairs(info.cands) do
		if green(x[1]) then
			if x[2] == "merge" then merge = true else cross = true end
		end
	end
	if cross then return "cross", merge end
	for _, i in ipairs(info.peds) do
		if green(i) then return "ped", merge end
	end
	return nil, merge
end

--- The conflict kind of kerb connection j in a phase (the map's classification, see the header;
-- SAFE keeps the turn red only for "cross" and "ped"): "merge", "cross", "ped" or nil. green(i): whether 0-based index i is green; ctx: { kerb = set,
-- crosswalks = {entity, ...}, segs = {[segment] = true} }; nCross: the crosswalk count.
function L.kerbConflict(conns, j, nCross, green, ctx)
	return conflictOf(conflictInfo(conns, j, nCross, ctx), green)
end

--- New lockedLanes for every phase. conns: the node's connections in config order (the ones the
-- write sends); kerbIdx: L.kerbIndices of them; nCross: the crosswalk count; states: one list of
-- locked indices per phase (plain Lua lists); mode: L.SAFE, L.FREE or L.LOCK (see the header; LOCK:
-- each kerb connection red where every other road connection from its segment0 is red; one whose
-- approach has no other road connection is left as it is). ctx (SAFE only): { kerb = the kerb set
-- (X.kerbPairs), crosswalks = the config's crosswalk entities in order }; missing parts count as
-- conflicts.
-- SAFE and FREE free only kerb turns on a dedicated kerb lane (L.sharedKerb); a shared-lane one is
-- locked where every lane mate is red (as LOCK, with its lane instead of its approach), never freed.
-- Returns lists, changed (kerb connections whose lock changed in at least one phase), nil, stats
-- = { phases = (kerb connection, phase) locks changed, merge, cross, ped = (kerb connection, phase)
-- pairs SAFE kept red, by kind (merge stays 0: merges are allowed), merged = pairs SAFE freed while
-- a green stream ends in the same lane, shared = kerb connections held as their entry lane is shared
-- (SAFE / FREE) }; or nil, 0, reason when an input index is out of range
-- [0, #conns + nCross - 1] or not an integer ("stale_phases": the caller writes nothing then) or
-- the mode is unknown. Nothing else changes: every other index keeps its place, no phase is added
-- or removed. A kerb connection already green in a phase stays green.
function L.kerbPhases(conns, kerbIdx, nCross, states, mode, ctx)
	if mode ~= L.FREE and mode ~= L.LOCK and mode ~= L.SAFE then return nil, 0, "mode" end
	conns = conns or {}
	local max = #conns + (nCross or 0) - 1
	for _, list in ipairs(states or {}) do
		for _, l in ipairs(list) do
			-- isIndex inlined (every index of every phase, twice per write)
			if type(l) ~= "number" or l < 0 or l > max or l % 1 ~= 0 then return nil, 0, "stale_phases" end
		end
	end
	local isKerb, kerbList = {}, {}
	for _, j in ipairs(kerbIdx or {}) do
		if isIndex(j, #conns - 1) and not isKerb[j] then
			isKerb[j] = true
			kerbList[#kerbList + 1] = j
		end
	end
	local stats = { phases = 0, merge = 0, cross = 0, ped = 0, merged = 0, shared = 0 }
	-- the exit fan (ctx.kerb.kerbLaneOnly): only the connections into the exit's kerb lane may be freed;
	-- the others (held) are locked as LOCK does, red where every non-kerb road connection of the approach is
	local heldList = {}
	if mode ~= L.LOCK and ctx ~= nil and type(ctx.kerb) == "table" and ctx.kerb.kerbLaneOnly == true then
		kerbList, heldList = L.splitKerb(conns, kerbList, ctx.kerb)
	end
	-- a kerb turn sharing its entry lane with another movement is never freed (header): it stays with
	-- its lane, red where every lane mate is red
	local sharedList, laneMates = {}, {}
	if mode ~= L.LOCK then
		local all = {}
		for j in pairs(isKerb) do all[#all + 1] = j end
		kerbList, sharedList, laneMates = L.sharedKerb(conns, kerbList, all)
		stats.shared = #sharedList
	end
	-- kerb turns beside a bus lane: the connections out of their approach's bus-only lanes (header)
	local busMates = {}
	local bus = mode ~= L.LOCK and ctx ~= nil and type(ctx.kerb) == "table" and type(ctx.kerb.bus) == "table" and ctx.kerb.bus or nil
	if bus ~= nil then
		local bySeg = {}
		for i, c in ipairs(conns) do
			local b = bus[c.segment0]
			if type(b) == "table" and b[c.lane0] == true then
				bySeg[c.segment0] = bySeg[c.segment0] or {}
				table.insert(bySeg[c.segment0], i - 1)
			end
		end
		for _, j in ipairs(kerbList) do busMates[j] = bySeg[conns[j + 1].segment0] end
	end
	--- Whether kerb connection j may be freed beside its approach's bus lane in a phase (locked: its set).
	local function busOk(j, locked)
		local list = busMates[j]
		if list == nil then return true end
		for _, i in ipairs(list) do
			if not locked[i] then return true end
		end
		return false
	end
	local isHeld = {}
	for _, j in ipairs(heldList) do isHeld[j] = true end
	for _, j in ipairs(sharedList) do isHeld[j] = true end
	-- LOCK: the other road connections of each kerb connection's approach (segment0); held ones alike
	local others = {}
	local lockList = mode == L.LOCK and kerbList or heldList
	if #lockList > 0 then
		for _, j in ipairs(lockList) do
			local a, list = conns[j + 1].segment0, {}
			for i, c in ipairs(conns) do
				if not isKerb[i - 1] and c.withRoad == true and c.segment0 == a then list[#list + 1] = i - 1 end
			end
			others[j] = list
		end
	end
	-- SAFE: the node's segments (a crosswalk on none of them is not mapped)
	local sctx = nil
	if mode == L.SAFE then
		local segs = {}
		for _, c in ipairs(conns) do
			if c.segment0 ~= nil then segs[c.segment0] = true end
			if c.segment1 ~= nil then segs[c.segment1] = true end
		end
		sctx = { kerb = ctx and ctx.kerb, crosswalks = (ctx and ctx.crosswalks) or {}, segs = segs }
	end
	-- SAFE: each kerb connection's conflict candidates, once for all phases
	local infos = {}
	if mode == L.SAFE then
		for _, j in ipairs(kerbList) do infos[j] = conflictInfo(conns, j, nCross, sctx) end
	end
	local out, changed = {}, {}
	for s, list in ipairs(states or {}) do
		local locked, res = {}, {}
		for _, l in ipairs(list) do locked[l] = true end
		if mode == L.FREE then
			for _, l in ipairs(list) do
				if isKerb[l] and not isHeld[l] and busOk(l, locked) then
					if not changed[l] then changed[l] = true end
					stats.phases = stats.phases + 1
				else
					res[#res + 1] = l
				end
			end
		elseif mode == L.SAFE then
			local freed, freedList = {}, {}
			local function green(i) return not locked[i] end
			for _, j in ipairs(kerbList) do
				if locked[j] and busOk(j, locked) then
					local why, merged = blockOf(infos[j], green)
					if not why then
						-- "cross" is one-sided (j may end kerbward of a kerb turn freed before it,
						-- which that one's check would call a crossing): re-check the freed ones with
						-- j green, so the result never frees a crossing pair whatever the order
						locked[j] = nil
						for _, f in ipairs(freedList) do
							why = blockOf(infos[f], green)
							if why then break end
						end
						locked[j] = true
					end
					if why then
						stats[why] = stats[why] + 1
					else
						if merged then stats.merged = stats.merged + 1 end
						locked[j] = nil
						freed[j] = true
						freedList[#freedList + 1] = j
						changed[j] = true
						stats.phases = stats.phases + 1
					end
				end
			end
			for _, l in ipairs(list) do
				if not freed[l] then res[#res + 1] = l end
			end
		end
		if mode == L.LOCK or #heldList > 0 or #sharedList > 0 then
			if mode == L.LOCK then
				for _, l in ipairs(list) do res[#res + 1] = l end
			end
			-- held: red where every one of `o` is red; lockList with its approach, sharedList with its lane
			local holds = {}
			for _, j in ipairs(lockList) do holds[#holds + 1] = { j, others[j] } end
			for _, j in ipairs(sharedList) do holds[#holds + 1] = { j, laneMates[j] } end
			for _, h in ipairs(holds) do
				local j, o = h[1], h[2]
				if #o > 0 and not locked[j] then
					local all = true
					for _, i in ipairs(o) do
						if not locked[i] then all = false break end
					end
					if all then
						res[#res + 1] = j
						locked[j] = true
						changed[j] = true
						stats.phases = stats.phases + 1
					end
				end
			end
		end
		out[s] = res
	end
	local n = 0
	for _ in pairs(changed) do n = n + 1 end
	return out, n, nil, stats
end

--- How the kerb connections' red differs between phase lists `a` and `b` (same phase count):
-- the kerb connections that differ in at least one phase, and the (kerb connection, phase) pairs.
function L.kerbDiff(kerbIdx, a, b)
	local n, phases = 0, 0
	for _, j in ipairs(kerbIdx or {}) do
		local diff = false
		for s = 1, math.max(#(a or {}), #(b or {})) do
			local x, y = false, false
			for _, l in ipairs((a and a[s]) or {}) do if l == j then x = true break end end
			for _, l in ipairs((b and b[s]) or {}) do if l == j then y = true break end end
			if x ~= y then
				diff = true
				phases = phases + 1
			end
		end
		if diff then n = n + 1 end
	end
	return n, phases
end

--- "merge:n,cross:n,ped:n" of the SAFE conflicts kept red (kinds with 0 left out), "-" for none.
function L.keptText(stats)
	local parts = {}
	for _, k in ipairs({ "merge", "cross", "ped" }) do
		local n = stats and stats[k] or 0
		if n > 0 then parts[#parts + 1] = k .. ":" .. n end
	end
	return #parts > 0 and table.concat(parts, ",") or "-"
end

--- Adds kerbPhases stats `b` into `a` (a = { phases, merge, cross, ped, merged, shared }); returns a.
function L.addStats(a, b)
	for _, k in ipairs({ "phases", "merge", "cross", "ped", "merged", "shared" }) do a[k] = (a[k] or 0) + (b and b[k] or 0) end
	return a
end

--- Nodes in `list` not yet in `seen` (seen is updated): keeps one entry per node.
function L.addUnique(out, seen, list)
	for _, n in ipairs(list or {}) do
		if not seen[n] then
			seen[n] = true
			out[#out + 1] = n
		end
	end
	return out
end

return L
