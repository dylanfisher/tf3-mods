-- Smart Lanes: the GUI-thread read / write path for node lane connections, shared by the automatic
-- Phase 1 game script (sl_lanes.script.lua) and the Phase 2 road tool (sl_tool.script.lua).
-- Both run on the GUI thread; each Lua state makes its own instance with Write.new(api, out).
--
-- Reads: an sl_ring world over the live street graph (BASE_NODE, BASE_EDGE, getNodeStreetSegments)
-- and a node's current connections as plain tables.
-- Writes (docs/findings.md "Junction lane connections"): one makeWorldBuildProposalCmd with
-- nodeConfigsToRemove = {nodes} + nodeConfigsToAdd = {entries}, Context{player,
-- cleanupStreetGraph = false}, args (false, true, true), sent with a callback (the Crossing Tool's
-- build shape; undo_tf3_test tool_probe.script.lua:118-135). The tool's Reset uses the same write
-- (never nodeConfigsToRemove alone: that deletes the node's config and crashes the game, findings.md).
-- The node's traffic light phases index its connections, so every write re-points them
-- (W.remapLights, Rules.remapLocked); a node whose phases cannot be re-pointed is not written.
-- An item may carry `phase = { mode = Lights.SAFE | Lights.FREE | Lights.LOCK, kerb = X.kerbPairs }`:
-- the crossroads' kerb turns are then freed in (SAFE: only in phases where nothing green crosses and no crosswalk on the path is green, merges allowed;
-- or, Reset, locked back into) the same re-pointed phases,
-- so lanes and phases go in one proposal (never a second proposal on the node right after: findings.md
-- "A street proposal touching a node whose traffic light change is still pending is refused").
-- W.kerbLights does the same for a node whose lanes stay (a phases-only light proposal).
-- Light phases = Smart Lanes (setting sqrl_light_phases, PHASES_PLAN.md step 4): an item may carry
-- `lightPlan = { view = sl_cross case "X" view, world }` (only for a lit node, X.litOf true): then
-- W.remapLights replaces the phases by a Smart Lanes plan (sl_phaseplan.lua) built from the FINAL
-- connections and the config's crosswalks of the same proposal, validated (PP.validatePlan) and
-- range-checked; the free kerb turn is not applied on top (the plan frees conflict-free kerb turns
-- itself). No plan or an invalid one: the item's `phase` (free kerb turn) and the plain re-pointing
-- as before, the reason in it.planFail. W.planLights writes a plan for a node whose lanes stay (a
-- phases-only light proposal), W.defaultLights gives a node the game's default phases back (states =
-- {}, the Crossing window's "Reset to Default", double_slip_switch.tl:604-612).
-- Fan mode (sl_fan zones, PHASES_PLAN.md "Fan mode"): lightPlan.fan = true asks planFor for the fan plan
-- (sl_phaseplan opts.fan; validated with intra-approach conflicts accepted, nothing else). The fan's
-- lanes cross each other, so a fan item whose plan cannot be made is not written at all (buildEntry
-- fails "lights:fan_<reason>": SKIP), never re-pointed onto the game's phases.
--
-- The api is passed in (not read as a global) so the offline tests can hand in a fake.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Lights = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local Phases = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PhasePlan = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"
local Split = ug_require "square_smart_lanes::/smart_lanes/sl_split.lua"
local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"
local Settings = ug_require "square_smart_lanes::/smart_lanes/sl_settings.lua"

local Write = {}

-- PROBE phases (W.probePhases): lit nodes logged per Lua state, list caps per node, chunk length
Write.PROBE_PHASES_MAX = 200
Write.PROBE_LIST_MAX = 512
Write.PROBE_STATES_MAX = 32
Write.PROBE_CHUNK = 180

local function count(list)
	if list == nil then return 0 end
	local n = 0
	for _ in ipairs(list) do n = n + 1 end
	return n
end
Write.count = count

--- The crosswalk entities of a node config as a plain list (Lights.kerbPhases SAFE ctx).
local function crosswalkList(cfg)
	local out = {}
	local ok = pcall(function()
		for _, x in ipairs(cfg.crosswalks or {}) do out[#out + 1] = x end
	end)
	if not ok then return {} end
	return out
end
Write.crosswalkList = crosswalkList

local function vec(v)
	if v == nil then return nil end
	return { x = v.x, y = v.y }
end

local function fieldsMatch(lc, c)
	return lc.segment0 == c.segment0 and lc.lane0 == c.lane0 and lc.segment1 == c.segment1
		and lc.lane1 == c.lane1 and (lc.withRoad == true) == c.withRoad and (lc.withTram == true) == c.withTram
end

local function setFields(lc, c)
	lc.segment0 = c.segment0
	lc.lane0 = c.lane0
	lc.segment1 = c.segment1
	lc.lane1 = c.lane1
	lc.withRoad = c.withRoad
	lc.withTram = c.withTram
end

local function checkList(list, conns)
	if count(list) ~= #conns then return false end
	for i, c in ipairs(conns) do
		if not fieldsMatch(list[i], c) then return false end
	end
	return true
end

--- New instance. api: the game api (or a fake); out(kind, fields): the log function; opts
-- (optional): { probeOn = function() -> bool } gates W.probePhases (the "Debug: performance log"
-- setting; nil: never).
function Write.new(api, out, opts)
	local W = { how = nil, dead = {}, modes = nil, probeOn = opts and opts.probeOn or nil,
		probeSeen = {}, probeCount = 0 }

	local function getComp(entity, ct)
		local ok, c = pcall(api.engine.getComponent, entity, ct)
		if ok then return c end
		return nil
	end
	W.getComp = getComp

	--- TransportMode enum values from the live api (Ring.MODES as fallback).
	function W.transportModes()
		if W.modes then return W.modes end
		local modes = {}
		for k, v in pairs(Ring.MODES) do modes[k] = v end
		pcall(function()
			local TM = api.type.enum.TransportMode
			for k in pairs(modes) do
				if type(TM[k]) == "number" then modes[k] = TM[k] end
			end
		end)
		W.modes = modes
		return modes
	end

	--- EdgeObjectType values of street stops (STOP_LEFT / STOP_RIGHT, api/type.d.tl:422; base
	-- mission_task_build_construction_util.tl:233 tests a stop the same way), read once; {} without the enum.
	function W.stopKinds()
		if W.stopKindSet then return W.stopKindSet end
		local set = {}
		pcall(function()
			local E = api.type.enum.EdgeObjectType
			if type(E.STOP_LEFT) == "number" then set[E.STOP_LEFT] = true end
			if type(E.STOP_RIGHT) == "number" then set[E.STOP_RIGHT] = true end
		end)
		W.stopKindSet = set
		return set
	end

	--- Street stop entities of a BASE_EDGE (its `objects`: { {entity, EdgeObjectType} }, api/engine.d.tl:105):
	-- the STOP_LEFT / STOP_RIGHT ones; without the enum, the objects with a STATION component (a stop is a
	-- station, base mission/name_util.tl:39). At most 32 objects looked at. {} when none or unreadable.
	local function stopIdsOf(e)
		local out = {}
		local ok = pcall(function()
			local objs = e.objects
			if objs == nil then return end
			local kinds = W.stopKinds()
			local useEnum = next(kinds) ~= nil
			local k = 0
			for _, o in ipairs(objs) do
				k = k + 1
				if k > 32 then break end
				local ent, kind = o[1], o[2]
				if type(ent) == "number" and ent >= 0 then
					if useEnum then
						if kinds[kind] then out[#out + 1] = ent end
					elseif getComp(ent, api.type.ComponentType.STATION) ~= nil then
						out[#out + 1] = ent
					end
				end
			end
		end)
		if not ok then return {} end
		return out
	end
	W.stopIdsOf = stopIdsOf -- tests

	-- The zone list (sl_zones.lua) worlds made from now on see for world.exitFan; set by the caller (the
	-- automatic pass per job, the tool when it reads the zones). nil: no zones.
	W.zones = nil

	--- sl_ring world over the live game, cached per world (make a new one per job / pick).
	-- Nodes also carry z (BASE_NODE.position.z) for the tool's markers.
	function W.makeWorld()
		local CT = api.type.ComponentType
		local modes = W.transportModes()
		local nodes, segs = {}, {}
		-- memo: results derived from this world's reads only (Walk.roadSegs, Ring.ringThrough, ...), as
		-- old as the world; a new world (per job, pick, refresh, batch) starts empty
		local world = { memo = {} }
		function world.node(id)
			if type(id) ~= "number" then return nil end -- defence: a caller's missing id is "no node"
			local c = nodes[id]
			if c ~= nil then return c or nil end
			local bn = getComp(id, CT.BASE_NODE)
			if not bn or not bn.position then
				nodes[id] = false
				return nil
			end
			local list = {}
			local ok, ss = pcall(function() return api.engine.system.streetSystem.getNodeStreetSegments(id) end)
			if ok and ss then for _, s in ipairs(ss) do list[#list + 1] = s end end
			c = { id = id, x = bn.position.x, y = bn.position.y, z = bn.position.z or 0, segs = list }
			nodes[id] = c
			return c
		end
		-- traffic lights of a node (Lights.litOf: true / false / nil = unknown), read once per node and
		-- only when asked (sl_cross: the crossroads it handles)
		local lits = {}
		function world.lit(id)
			if type(id) ~= "number" then return nil end
			local c = lits[id]
			if c == nil then
				local ok, st = pcall(W.lightState, id)
				c = Lights.litOf(ok and st or nil, W.lightEnum())
				if c == nil then c = "unknown" end
				lits[id] = c
			end
			if c == "unknown" then return nil end
			return c
		end
		-- an sl_exitfan zone at node id (sl_zones.lua, sl_cross X.exitFanOf): world.zones when the caller froze
		-- a list into this world (the automatic pass: its job's zones), else W.zones read at the call (the
		-- tool's last read, the re-checks: the current mirror); false outside or without zones
		function world.exitFan(id)
			local zoneList = world.zones
			if zoneList == nil then zoneList = W.zones end
			if type(id) ~= "number" or type(zoneList) ~= "table" or #zoneList == 0 then return false end
			return Zones.nodeAb(zoneList, world, id) == "sl_exitfan"
		end
		function world.seg(id)
			if type(id) ~= "number" then return nil end -- defence, as world.node
			local c = segs[id]
			if c ~= nil then return c or nil end
			local e = getComp(id, CT.BASE_EDGE)
			if not e then
				segs[id] = false
				return nil
			end
			local p0, p1 = vec(e.position0), vec(e.position1)
			if not p0 or not p1 then
				local n0, n1 = world.node(e.node0), world.node(e.node1)
				p0 = p0 or (n0 and { x = n0.x, y = n0.y }) or { x = 0, y = 0 }
				p1 = p1 or (n1 and { x = n1.x, y = n1.y }) or { x = 0, y = 0 }
			end
			c = { id = id, node0 = e.node0, node1 = e.node1, p0 = p0, p1 = p1,
				t0 = vec(e.tangent0), t1 = vec(e.tangent1),
				lanes = Ring.lanesFromConfigs(e.laneConfigs, modes), atMemo = {}, stopIds = stopIdsOf(e) }
			segs[id] = c
			return c
		end
		-- street stops on segment id (sl_cross X.openOf): { { x, y, param } ... } from each stop's EDGE_OBJECT
		-- (transf translation, param 0..1 along the edge; api/engine.d.tl:133-144), read once per segment and
		-- only when asked (the exit roads of a handled crossroads / T); a stop whose EDGE_OBJECT can't be read
		-- counts with no position (sl_cross: at the segment's far end). nil for no segment.
		local stopMemo = {}
		function world.stops(id)
			local c = world.seg(id)
			if not c then return nil end
			local hit = stopMemo[id]
			if hit ~= nil then return hit end
			local out = {}
			for _, ent in ipairs(c.stopIds or {}) do
				local st = {}
				local eo = getComp(ent, CT.EDGE_OBJECT)
				if eo then
					pcall(function()
						if type(eo.param) == "number" then st.param = eo.param end
						local t = eo.transf and eo.transf:getTransl()
						if t and type(t.x) == "number" and type(t.y) == "number" then st.x, st.y = t.x, t.y end
					end)
				end
				out[#out + 1] = st
			end
			stopMemo[id] = out
			return out
		end
		return world
	end

	--- The node's current connections as plain tables (Rules.conn), in the config's order (the
	-- order is the NodeViewer edge index, double_slip_switch.tl:113-118).
	local function connsOfCfg(cfg)
		local list = {}
		if cfg then
			for _, c in ipairs(cfg.laneConnections or {}) do
				list[#list + 1] = Rules.conn(c.segment0, c.lane0, c.segment1, c.lane1, c.withRoad == true, c.withTram == true)
			end
		end
		return list
	end

	function W.currentConns(node)
		return connsOfCfg(getComp(node, api.type.ComponentType.BASE_NODE_CONFIG))
	end

	-- BaseNodeLaneConnectionAndEntity for `node` with `conns`. LaneConnection objects of a read
	-- BaseNodeConfig are read-only, and api.type.LaneConnection.new() works although the tealdef
	-- lacks it (findings.md, 2026-10-08: HOW strategy=ctor). The other strategies stay as
	-- fallbacks; the first that works is remembered (logged once as HOW):
	--   ctor:   api.type.LaneConnection.new()
	--   table:  plain Lua tables assigned to entry.comp.laneConnections (userdata conversion)
	--   owned:  fields of the copies owned by a new entry (entry.comp = cfg, then edit)
	--   subset: no writes: reuse the read objects whose connection is wanted
	local STRATEGIES = {
		ctor = function(entry, cfg, conns)
			local LC = api.type.LaneConnection
			if LC == nil or LC.new == nil then error("no api.type.LaneConnection.new") end
			local list = {}
			for i, c in ipairs(conns) do
				local lc = LC.new()
				setFields(lc, c)
				list[i] = lc
			end
			entry.comp.laneConnections = list
		end,
		table = function(entry, cfg, conns)
			local list = {}
			for i, c in ipairs(conns) do
				list[i] = { segment0 = c.segment0, lane0 = c.lane0, segment1 = c.segment1, lane1 = c.lane1,
					withRoad = c.withRoad, withTram = c.withTram }
			end
			entry.comp.laneConnections = list
		end,
		owned = function(entry, cfg, conns)
			local owned = entry.comp.laneConnections
			if count(owned) < #conns then error("owned_" .. count(owned) .. "_of_" .. #conns) end
			local list = {}
			for i, c in ipairs(conns) do
				local lc = owned[i]
				setFields(lc, c)
				list[i] = lc
			end
			entry.comp.laneConnections = list
		end,
		subset = function(entry, cfg, conns)
			local list, used = {}, {}
			for i, c in ipairs(conns) do
				for j, lc in ipairs(cfg.laneConnections or {}) do
					if not used[j] and fieldsMatch(lc, c) then
						used[j] = true
						list[i] = lc
						break
					end
				end
				if list[i] == nil then error("not_subset") end
			end
			entry.comp.laneConnections = list
		end,
	}
	local ORDER = { "ctor", "table", "owned", "subset" }

	--- New TrafficLightState objects for `c` (a clone of the node's TrafficLightConfig): each with its
	-- old duration, minDuration, canSkip and lockedLanes = lists[i]; assigned to c.states.
	local function setStates(c, lists)
		local states = {}
		for i, st in ipairs(c.states) do
			local ns = api.type.TrafficLightState.new()
			ns.duration, ns.minDuration, ns.canSkip = st.duration, st.minDuration, st.canSkip
			ns.lockedLanes = lists[i]
			states[i] = ns
		end
		c.states = states
		return #states
	end

	--- Errors unless `tlc` reads back with n states whose indices are all in [0, max].
	local function checkStates(tlc, n, max)
		if tlc == nil or count(tlc.states) ~= n then error("lights_readback") end
		for _, st in ipairs(tlc.states) do
			for _, l in ipairs(st.lockedLanes or {}) do
				if type(l) ~= "number" or l < 0 or l > max then error("lights_index_" .. tostring(l)) end
			end
		end
	end

	--- New TrafficLightState objects from a Smart Lanes plan (PP.plan states: locked, duration,
	-- minDuration, canSkip), assigned to c.states (c: a clone of the node's TrafficLightConfig).
	local function setPlanStates(c, plan)
		local states = {}
		for i, st in ipairs(plan.states) do
			local ns = api.type.TrafficLightState.new()
			ns.duration, ns.minDuration, ns.canSkip = st.duration, st.minDuration, st.canSkip == true
			local l = {}
			for j, x in ipairs(st.locked) do l[j] = x end
			ns.lockedLanes = l
			states[i] = ns
		end
		c.states = states
		return #states
	end

	--- A Smart Lanes phase plan for node n: conns = the connections the proposal sends (config
	-- order), cws = the config's crosswalk entities, lp = { view, world } (the sl_cross case "X" view
	-- and the world it was read in; lp.fan = true: the fan plan, sl_phaseplan opts.fan; else the axis plan,
	-- validated with opts.axis). Returns plan, or nil, reason (PP.plan's: "no_axis_shape", "axis_extra",
	-- "invalid_..": the caller keeps the game's phases, PLAN.md "No classic fallback"). Every index of every
	-- state is checked against [0, #conns + #cws - 1] here again (crash rule: VectorMap.h:11 key >= 0).
	local function planFor(n, conns, cws, lp)
		if type(lp) ~= "table" or lp.view == nil or lp.world == nil then return nil, "no_view" end
		if lp.view.case ~= "X" then return nil, "not_x" end
		local info = PhasePlan.infoFromView(lp.view, lp.world, n, conns)
		local M, whyM = Phases.build({ conns = conns, arms = info.arms, crosswalks = cws, cls = info.cls })
		if M == nil then return nil, "map_" .. tostring(whyM) end
		local fan = lp.fan == true
		-- the axis plan, or the fan plan (an sl_fan zone)
		local opts = fan and { fan = true } or nil
		local plan, why = PhasePlan.plan(M, info, opts)
		if plan == nil then return nil, tostring(why) end
		-- an axis plan's conflicts within one road are accepted only with the explicit flag (and plan.axis)
		local vopts = opts
		if not fan then vopts = { axis = true } end
		local okV, whyV = PhasePlan.validatePlan(M, plan, #conns, #cws, vopts)
		if not okV then return nil, "invalid_" .. tostring(whyV) end
		local max = #conns + #cws - 1
		for _, st in ipairs(plan.states) do
			for _, l in ipairs(st.locked) do
				if type(l) ~= "number" or l ~= math.floor(l) or l < 0 or l > max then return nil, "index" end
			end
		end
		return plan
	end
	W.planFor = planFor

	--- Whether the read states equal the plan (lockedLanes as sets, duration, minDuration, canSkip).
	-- structOnly: the plan's structure in whatever durations (Smart lights still on after Re-time, Keep timing
	-- adjusted or the Crossing window's duration slider changed the greens): the same phases in order with the same
	-- locked lanes and canSkip, and the plan's minDuration or less (a timing change lowers it with its phase and never
	-- raises it again: sl_retime.lua minDuration = min(current minDuration, new duration)). A changed lane layout gives another plan
	-- (other phases or locked lanes): not the same.
	local function samePlan(states, plan, structOnly)
		if count(states) ~= #plan.states then return false end
		for i, st in ipairs(states) do
			local want = plan.states[i]
			if (st.canSkip == true) ~= want.canSkip then return false end
			if structOnly then
				local m = st.minDuration
				if type(m) ~= "number" or m ~= m or m < 0 or m > want.minDuration + 1e-6 then return false end
			elseif st.duration ~= want.duration or st.minDuration ~= want.minDuration then
				return false
			end
			local set, n = {}, 0
			for _, l in ipairs(st.lockedLanes or {}) do
				if not set[l] then n = n + 1 end
				set[l] = true
			end
			if n ~= #want.locked then return false end
			for _, l in ipairs(want.locked) do
				if not set[l] then return false end
			end
		end
		return true
	end

	--- This mod's params with the save's in-game settings in force (sl_settings.lua M.effectiveRaw: read each call,
	-- the saved overrides polled at most every Settings.POLL_S).
	function W.modRaw()
		return Settings.effectiveRaw(api)
	end

	--- "Light phases" from this mod's params and the save's in-game setting (read each call, as W.removeLights):
	-- "game" | "sl".
	function W.phasesMode()
		return Rules.fromModParams(W.modRaw()).phases
	end

	--- Re-points the traffic light phases of `entry` (its comp copied from `cfg`) from the old
	-- connections to `conns` (Rules.remapLocked), on a clone of the config as the base node window
	-- does (double_slip_switch.tl:46, 566-577). phase (optional, see the header): then the kerb turns
	-- are freed / locked in the re-pointed phases (Lights.kerbPhases). Returns the number of states,
	-- the number of kerb connections changed and stats { phases = (kerb connection, phase) locks
	-- that differ from the plain re-pointing, merge / cross / ped = pairs "When safe" kept red };
	-- errors when the remap does not read back (the caller then skips the node: stale phases crash
	-- the simulation).
	-- lp (optional, Light phases = Smart Lanes): { view, world }; the phases are then replaced by a
	-- Smart Lanes plan for `conns` (stats.plan = PP.planText), or, when none can be made, re-pointed
	-- as without it (stats.planFail = reason). A node without phases (no light) gets none.
	function W.remapLights(entry, cfg, oldConns, conns, phase, lp)
		local stats = { phases = 0, merge = 0, cross = 0, ped = 0, merged = 0, shared = 0 }
		local tlc = cfg.trafficLightConfig
		local fan = lp ~= nil and lp.fan == true
		if tlc == nil or count(tlc.states) == 0 then
			-- fan lanes never go out without their plan (they cross each other)
			if fan then error("fan_no_phases", 0) end
			if lp ~= nil then stats.planFail = "no_phases" end
			return 0, 0, stats
		end
		local nCross = count(cfg.crosswalks)
		if lp ~= nil then
			local cws = crosswalkList(cfg)
			local okP, plan, why = false, nil, "crosswalks"
			if #cws == nCross then okP, plan, why = pcall(planFor, entry.entity, conns, cws, lp) end
			if okP and plan ~= nil then
				local c = tlc:clone()
				local k = setPlanStates(c, plan)
				entry.comp.trafficLightConfig = c
				checkStates(entry.comp.trafficLightConfig, k, #conns + nCross - 1)
				stats.plan = PhasePlan.planText(plan, #conns)
				stats.pattern = PhasePlan.patternName(plan)
				return k, 0, stats
			end
			stats.planFail = okP and tostring(why) or ("error:" .. tostring(plan):gsub("^.-:%d+: ", ""))
			-- fan lanes never go out without their plan: the item is not written (SKIP reason=lights:fan_..)
			if fan then error("fan_" .. stats.planFail, 0) end
		end
		local c = tlc:clone()
		local olds = {}
		for i, st in ipairs(c.states) do
			local old = {}
			for _, l in ipairs(st.lockedLanes or {}) do old[#old + 1] = l end
			olds[i] = old
		end
		local remapOne = Rules.remapper(oldConns, conns, nCross) -- the matching once, then per state
		local function remap(from)
			local res = {}
			for i, old in ipairs(from) do res[i] = remapOne(old) end
			return res
		end
		local lists = remap(olds)
		local changed = 0
		if phase ~= nil then
			local plain, kerbIdx = lists, Lights.kerbIndices(conns, phase.kerb)
			-- kerb turns freed earlier are locked back with their approach before re-pointing: a
			-- connection new to the node takes its approach's red only where every old connection of
			-- that approach is red (remapLocked bySeg), and a freed kerb turn would make it green in
			-- every phase. Stale old phases (refused) are re-pointed as read.
			local relocked = Lights.kerbPhases(oldConns, Lights.kerbIndices(oldConns, phase.kerb), nCross, olds, Lights.LOCK)
			if relocked ~= nil then lists = remap(relocked) end
			local res, _, why, st = Lights.kerbPhases(conns, kerbIdx, nCross, lists, phase.mode,
				{ kerb = phase.kerb, crosswalks = crosswalkList(cfg) })
			-- remapLocked only makes indices in range, so a refusal here is a bug: keep the plain remap
			if res ~= nil then
				lists = res
				stats.merge, stats.cross, stats.ped, stats.merged, stats.shared = st.merge, st.cross, st.ped, st.merged, st.shared
				-- kerb connections whose red differs from the plain re-pointing in some phase
				local plainSet, listSet = {}, {}
				for sI = 1, #lists do
					local p, q = {}, {}
					for _, l in ipairs(plain[sI]) do p[l] = true end
					for _, l in ipairs(lists[sI]) do q[l] = true end
					plainSet[sI], listSet[sI] = p, q
				end
				for _, j in ipairs(kerbIdx) do
					local diff = false
					for sI = 1, #lists do
						if (plainSet[sI][j] == true) ~= (listSet[sI][j] == true) then
							diff = true
							stats.phases = stats.phases + 1
						end
					end
					if diff then changed = changed + 1 end
				end
			else
				lists = plain
				out("ERROR", { { "where", "kerb_phases" }, { "node", entry.entity }, { "err", why } })
			end
		end
		local k = setStates(c, lists)
		entry.comp.trafficLightConfig = c
		checkStates(entry.comp.trafficLightConfig, k, #conns + nCross - 1)
		return k, changed, stats
	end

	--- Entry for `node` with `conns` (phase, lp: optional, see the header). Returns entry, strategy
	-- name, kerb connections changed in the phases, their stats (W.remapLights: also plan / planFail);
	-- or nil, reason.
	function W.buildEntry(node, conns, phase, lp)
		local CT = api.type.ComponentType
		-- one config read for the check, the old connections and the first try (it was three reads)
		local first = api.engine.getComponent(node, CT.BASE_NODE_CONFIG)
		if first == nil then return nil, "no_config" end
		local notes = {}
		local oldConns = connsOfCfg(first)
		for _, name in ipairs(ORDER) do
			if not W.dead[name] then
				-- a fresh read per later try: a failed try may have left the entry half written
				local cfg = first or api.engine.getComponent(node, CT.BASE_NODE_CONFIG)
				first = nil
				local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
				entry.entity = node
				entry.comp = cfg
				local ok, e = pcall(STRATEGIES[name], entry, cfg, conns)
				if ok then
					local okC, same = pcall(checkList, entry.comp.laneConnections, conns)
					if okC and same then
						local okL, eL, kerbN, kerbStats = pcall(W.remapLights, entry, cfg, oldConns, conns, phase, lp)
						if not okL then
							return nil, "lights:" .. tostring(eL):gsub("^.-:%d+: ", "")
						end
						if W.how ~= name then
							W.how = name
							out("HOW", { { "strategy", name }, { "tried", table.concat(notes, ";") } })
						end
						return entry, name, kerbN or 0, kerbStats
					end
					e = okC and "readback_differs" or ("readback:" .. tostring(same))
				end
				e = tostring(e):gsub("^.-:%d+: ", "") -- drop the '[string "<path>"]:<line>: ' prefix
				-- subset depends on the node; the others fail the same way everywhere
				if name ~= "subset" and not e:find("owned_", 1, true) then W.dead[name] = true end
				notes[#notes + 1] = name .. "=" .. e:sub(-60)
			end
		end
		return nil, "no_strategy:" .. table.concat(notes, ";")
	end

	local function send(removes, entries, onDone)
		local proposal = api.type.SimpleProposal.new()
		proposal.streetProposal.nodeConfigsToRemove = removes
		if entries ~= nil then proposal.streetProposal.nodeConfigsToAdd = entries end
		local context = api.type.Context.new()
		context.player = api.engine.util.getPlayer()
		context.cleanupStreetGraph = false
		local cmd = api.cmd.makeWorldBuildProposalCmd(proposal, context, false, true, true)
		api.cmd.sendCommand(cmd, function(_res, success)
			if onDone then onDone(success == true) end
		end)
	end

	--- Writes connection sets: items = { {node, conns [, phase] [, lightPlan]}, ... } in one proposal.
	-- Items with a lightPlan get it.planText (the plan written) or it.planFail (why not: the phase /
	-- plain re-pointing went instead); they and items sent with a planFail (unlit, lit_unknown: no plan
	-- tried) log one PHASES line each (src = the item's src or keyName):
	--   PHASES src= node= phases=sl pattern=axis|fan|none plan=<PP.planText> | plan_fail=<reason>
	-- Nodes whose entry cannot be built are logged as SKIP <keyName>=<key> node reason.
	-- onDone(success, expect, nodesText): expect = {node = Rules.connsText(conns)} of the sent nodes (bus-lane
	-- connections left out: a { text, bus } pair then, W.verify).
	-- Returns the number of nodes sent (0: nothing sent, onDone is not called), the kerb
	-- connections changed in their phases (items with a phase; each sent item gets it.kerbChanged
	-- and it.kerbStats) and the summed stats (W.remapLights).
	-- onSkip(item, reason) (optional): called for each item left out (the automatic pass's SUMMARY).
	function W.sendConfigs(keyName, key, items, onDone, onSkip)
		local b = W.newBatch()
		for _, it in ipairs(items) do W.addItem(b, keyName, key, it, onSkip) end
		return W.sendBatch(b, onDone)
	end

	--- W.sendConfigs in parts, for a caller that builds one proposal over several steps (the automatic
	-- pass, a frame's share of a job): b = W.newBatch(); W.addItem(b, keyName, key, it, onSkip) per item
	-- (builds its entry at once, from reads made now: call it in the frame the batch is sent); then
	-- W.sendBatch(b, onDone) sends them in one proposal. Same lines and results as W.sendConfigs.
	function W.newBatch()
		return { entries = {}, removes = {}, expect = {}, nodesText = {}, kerbTotal = 0,
			statsTotal = { phases = 0, merge = 0, cross = 0, ped = 0, merged = 0 } }
	end

	--- Builds item `it`'s entry into batch b (see W.sendConfigs for the item fields, the PHASES and SKIP
	-- lines and onSkip). Returns true when the item went into the batch.
	function W.addItem(b, keyName, key, it, onSkip)
		local okB, entry, info, kerbN, kerbStats = pcall(W.buildEntry, it.node, it.conns, it.phase, it.lightPlan)
		if okB and entry then
			it.kerbChanged = kerbN or 0
			it.kerbStats = kerbStats or { phases = 0, merge = 0, cross = 0, ped = 0, merged = 0 }
			if it.lightPlan ~= nil then
				it.planText, it.planFail, it.planPattern = it.kerbStats.plan, it.kerbStats.planFail, it.kerbStats.pattern
				if it.planText == nil and it.planFail == nil then it.planFail = "none" end
			end
			-- (an item may come with planFail already: unlit / lit_unknown, no plan tried)
			if it.lightPlan ~= nil or it.planFail ~= nil then
				-- pattern= (axis | fan): which plan a node got, e.g. a Stress Test twin's; none: the game's
				-- phases stay (re-pointed onto the lanes, with the free curb turn as set), plan_fail= says why
				out("PHASES", { { "src", it.src or keyName }, { "node", it.node }, { "phases", "sl" },
					{ "pattern", it.planText and (it.planPattern or "axis") or "none" },
					it.planText and { "plan", it.planText } or { "plan_fail", it.planFail } })
			end
			Lights.addStats(b.statsTotal, it.kerbStats)
			b.kerbTotal = b.kerbTotal + it.kerbChanged
			b.entries[#b.entries + 1] = entry
			b.removes[#b.removes + 1] = it.node
			-- connections touching a bus-only lane do not count (W.verify): the list's bus set (Rules.mergeTram)
			local bus = it.conns.bus
			local text = Rules.carText(it.conns, bus)
			b.expect[it.node] = bus ~= nil and { text = text, bus = bus } or text
			b.nodesText[#b.nodesText + 1] = tostring(it.node)
			return true
		end
		local reason = okB and info or ("error:" .. tostring(entry))
		out("SKIP", { { keyName, key }, { "node", it.node }, { "reason", reason } })
		if onSkip then pcall(onSkip, it, reason) end
		return false
	end

	--- Sends batch b's entries in one proposal: returns as W.sendConfigs (0: nothing sent, onDone is
	-- not called; else onDone(success, expect, nodesText) when it answered).
	function W.sendBatch(b, onDone)
		if #b.entries == 0 then return 0, 0, b.statsTotal end
		local nodes = table.concat(b.nodesText, ",")
		local expect = b.expect
		send(b.removes, b.entries, function(success)
			if onDone then onDone(success, expect, nodes) end
		end)
		return #b.entries, b.kerbTotal, b.statsTotal
	end

	---------------------------------------------------------------------------
	-- Traffic lights (sl_lights.lua)

	function W.lightEnum()
		local ok, e = pcall(function() return api.type.enum.TrafficLightPreference end)
		if ok and type(e) == "table" then return e end
		return nil
	end

	--- "No lights at roundabouts and ramps" from this mod's params and the save's in-game setting (read each call:
	-- cheap, and the tool and the game script share it).
	function W.removeLights()
		return Rules.fromModParams(W.modRaw()).lights == true
	end

	--- "Free kerb turn at traffic lights" from this mod's params (read each call, as W.removeLights):
	-- the phase mode (Lights.SAFE "When safe", Lights.FREE "Always") or nil (Off).
	function W.freeTurn()
		return Lights.modeFor(Rules.fromModParams(W.modRaw()).freeTurn)
	end

	--- Frees (mode Lights.SAFE: where nothing green crosses it, merges allowed; Lights.FREE: everywhere) or locks back
	-- (Lights.LOCK) the kerb turns `kerb` (sl_cross
	-- X.kerbPairs) in the phases of a node whose lanes stay as they are (SAFE locks them back with
	-- their approach first, as W.remapLights, so an earlier unsafe free does not stay): one light proposal with the
	-- base node window's own call (double_slip_switch.tl:56 createTrafficLightProposal with a cloned
	-- config, its preference kept; the phase editor commits edited lockedLanes this way, :147-170).
	-- Only at a node with a standing light (BASE_NODE_TRAFFIC_LIGHT), whose phases index its current
	-- connections (Lights.kerbPhases refuses stale ones) and where a kerb connection changes. Logs one
	-- LIGHTS line per command sent (to=free_turn | lock_turn). onDone(success) when it answered.
	-- Returns the kerb connections changed (0: nothing sent), a reason when nothing was sent
	-- (no_config, no_light, no_phases, none, stale_phases, error:...) and the Lights.kerbPhases
	-- stats when the phases were read (phases = (kerb connection, phase) locks changed, merge /
	-- cross / ped = pairs "When safe" kept red). LIGHTS adds free_phases|lock_phases= and, for
	-- SAFE, kept=cross:n,ped:n merge_free=n (merges no longer keep a turn red); free_turn: shared_held=n
	-- (kerb connections held with their shared entry lane, Lights.sharedKerb).
	function W.kerbLights(node, kerb, mode, src, onDone)
		local CT = api.type.ComponentType
		local cfg = getComp(node, CT.BASE_NODE_CONFIG)
		if not cfg then return 0, "no_config" end
		if CT.BASE_NODE_TRAFFIC_LIGHT == nil or getComp(node, CT.BASE_NODE_TRAFFIC_LIGHT) == nil then return 0, "no_light" end
		local tlc = cfg.trafficLightConfig
		if tlc == nil or count(tlc.states) == 0 then return 0, "no_phases" end
		local conns = W.currentConns(node)
		if count(cfg.laneConnections) ~= #conns then return 0, "stale_phases" end
		local nCross = count(cfg.crosswalks)
		local lists = {}
		for i, st in ipairs(tlc.states) do
			local l = {}
			for _, x in ipairs(st.lockedLanes or {}) do l[#l + 1] = x end
			lists[i] = l
		end
		local kerbIdx = Lights.kerbIndices(conns, kerb)
		-- When safe starts from the game's locks (as W.remapLights): a kerb turn freed earlier into
		-- conflicting traffic (Always, or by hand) is locked back first, else it would stay green
		local base = lists
		if mode == Lights.SAFE then
			local relocked = Lights.kerbPhases(conns, kerbIdx, nCross, lists, Lights.LOCK)
			if relocked ~= nil then base = relocked end
		end
		local res, n, why, stats = Lights.kerbPhases(conns, kerbIdx, nCross, base, mode,
			{ kerb = kerb, crosswalks = crosswalkList(cfg) })
		if res == nil then return 0, why end
		if base ~= lists then n, stats.phases = Lights.kerbDiff(kerbIdx, lists, res) end
		if n == 0 then return 0, "none", stats end
		local okP, cmd = pcall(function()
			local c = tlc:clone()
			local k = setStates(c, res)
			checkStates(c, k, #conns + nCross - 1)
			local p = api.engine.util.proposal.createTrafficLightProposal(node, c, cfg.trafficLightPreference)
			return api.cmd.makeWorldBuildProposalCmd(p, nil, false, true)
		end)
		if not okP or cmd == nil then
			local e = "error:" .. tostring(cmd):gsub("^.-:%d+: ", "")
			out("SKIP", { { "kind", "lights" }, { "node", node }, { "reason", e } })
			return 0, e, stats
		end
		local um = nil
		pcall(function() um = cfg.userModifiedTrafficLightStates end)
		local f = { { "src", src }, { "node", node }, { "to", mode == Lights.LOCK and "lock_turn" or "free_turn" },
			{ mode == Lights.LOCK and "lock_turn" or "free_turn", n }, { "states", #res },
			{ "pref", Lights.prefName(cfg.trafficLightPreference, W.lightEnum()) }, { "user_modified", tostring(um) },
			{ mode == Lights.LOCK and "lock_phases" or "free_phases", stats.phases } }
		if mode == Lights.SAFE then
			f[#f + 1] = { "kept", Lights.keptText(stats) }
			f[#f + 1] = { "merge_free", stats.merged or 0 }
		end
		if mode ~= Lights.LOCK then f[#f + 1] = { "shared_held", stats.shared or 0 } end
		f[#f + 1] = { "phases", W.phasesMode() }
		out("LIGHTS", f)
		api.cmd.sendCommand(cmd, function(_res, success)
			if onDone then onDone(success == true) end
		end)
		return n, nil, stats
	end

	--- Reads the light of a node for a phases-only proposal: cfg, tlc, conns, crosswalks; or nil, reason
	-- (no_config, no_light, no_phases, stale_conns, crosswalks).
	local function lightRead(node)
		local CT = api.type.ComponentType
		local cfg = getComp(node, CT.BASE_NODE_CONFIG)
		if not cfg then return nil, "no_config" end
		if CT.BASE_NODE_TRAFFIC_LIGHT == nil or getComp(node, CT.BASE_NODE_TRAFFIC_LIGHT) == nil then return nil, "no_light" end
		local tlc = cfg.trafficLightConfig
		if tlc == nil or count(tlc.states) == 0 then return nil, "no_phases" end
		local conns = W.currentConns(node)
		if count(cfg.laneConnections) ~= #conns then return nil, "stale_conns" end
		local cws = crosswalkList(cfg)
		if #cws ~= count(cfg.crosswalks) then return nil, "crosswalks" end
		return { cfg = cfg, tlc = tlc, conns = conns, cws = cws }
	end
	W.lightRead = lightRead

	--- A short signature of a node's read phases (lightRead's tlc): durations, skips and locked lanes, so
	-- a caller can tell whether they changed since it planned (the tool's "Lights only" status).
	function W.statesSig(tlc)
		local parts = {}
		for i, st in ipairs(tlc and tlc.states or {}) do
			if i > 64 then break end
			local l = {}
			for j, x in ipairs(st.lockedLanes or {}) do
				if j > 512 then break end
				l[#l + 1] = tostring(x)
			end
			parts[#parts + 1] = tostring(st.duration) .. "/" .. tostring(st.minDuration) .. "/" .. tostring(st.canSkip == true)
				.. ":" .. table.concat(l, ",")
		end
		return table.concat(parts, ";")
	end

	--- Whether the read phases of a node equal a plan (lightRead's tlc.states; see samePlan). structOnly: the plan's
	-- phases in any durations (Smart lights on, its timing adjusted).
	function W.samePlan(states, plan, structOnly) return samePlan(states, plan, structOnly == true) end

	--- Smart Lanes phases for a node whose lanes stay (Light phases = Smart Lanes): a plan from the
	-- node's current connections and crosswalks (lp = { view, world }: its sl_cross case "X" view and
	-- the world it was read in), sent as a phases-only light proposal with the base node window's own
	-- call (createTrafficLightProposal on a clone, the node's preference kept), only at a node with a
	-- standing light whose phases differ from the plan. The caller makes sure no other proposal on
	-- the node is pending. Logs LIGHTS src= node= to=sl_phases phases=sl states= cycle= pref=
	-- user_modified= plan=. onDone(success) when it answered.
	-- Returns 1 when sent, else 0 and a reason (lightRead's, "same", "plan_fail:<reason>",
	-- "error:..."); and the plan text (sent or same) and its pattern (PP.patternName). extra (optional): log fields appended to the LIGHTS
	-- line (the tool's "Lights only": action=lights_only). keepTiming (optional): phases with the plan's structure in other
	-- durations (Re-time, Keep timing adjusted, the Crossing window) count as "same" too (5th result timed = true), so
	-- their fitted timing stays; without it only the plan's exact phases do (the new-light look: engine phases).
	function W.planLights(node, lp, src, onDone, extra, keepTiming)
		local r, why = lightRead(node)
		if r == nil then return 0, why end
		local okP, plan, whyP = pcall(planFor, node, r.conns, r.cws, lp)
		if not okP then return 0, "plan_fail:error:" .. tostring(plan):gsub("^.-:%d+: ", "") end
		if plan == nil then return 0, "plan_fail:" .. tostring(whyP) end
		local text = PhasePlan.planText(plan, #r.conns)
		local pattern = PhasePlan.patternName(plan)
		if samePlan(r.tlc.states, plan) then return 0, "same", text, pattern end
		-- the plan's phases with adjusted timing (Re-time, Keep timing adjusted, the Crossing window): kept, timed = true
		if keepTiming == true and samePlan(r.tlc.states, plan, true) then return 0, "same", text, pattern, true end
		local okC, cmd = pcall(function()
			local c = r.tlc:clone()
			local k = setPlanStates(c, plan)
			checkStates(c, k, #r.conns + #r.cws - 1)
			local p = api.engine.util.proposal.createTrafficLightProposal(node, c, r.cfg.trafficLightPreference)
			return api.cmd.makeWorldBuildProposalCmd(p, nil, false, true)
		end)
		if not okC or cmd == nil then
			local e = "error:" .. tostring(cmd):gsub("^.-:%d+: ", "")
			out("SKIP", { { "kind", "lights" }, { "node", node }, { "reason", e } })
			return 0, e
		end
		local um = nil
		pcall(function() um = r.cfg.userModifiedTrafficLightStates end)
		local f = { { "src", src }, { "node", node }, { "to", "sl_phases" }, { "phases", "sl" }, { "states", #plan.states },
			{ "cycle", plan.cycle }, { "pref", Lights.prefName(r.cfg.trafficLightPreference, W.lightEnum()) },
			{ "user_modified", tostring(um) } }
		for _, kv in ipairs(extra or {}) do f[#f + 1] = kv end
		f[#f + 1] = { "plan", text }
		out("LIGHTS", f)
		api.cmd.sendCommand(cmd, function(_res, success)
			if onDone then onDone(success == true) end
		end)
		return 1, nil, text, pattern
	end

	--- New phase lengths for a node whose lanes and phases stay (the tool's Re-time, sl_retime.lua): every
	-- state keeps its lockedLanes and canSkip as read, only duration and minDuration change (durations[i],
	-- mins[i] for state i). Sent with the base node window's own call (createTrafficLightProposal on a clone of
	-- the node's TrafficLightConfig, the node's preference kept), only when the read phases are still the
	-- ones planned for: expectSig = W.statesSig of the phases the durations were computed from, with
	-- expectConns = Rules.connsText of the connections (else 0, "changed"). The caller makes sure no other
	-- proposal on the node is pending. Logs LIGHTS src= node= to=retime states= cycle= durations= pref=
	-- user_modified= [extra]. onDone(success) when it answered. Returns 1 when sent, else 0 and a reason
	-- (lightRead's, "changed", "states", "error:...").
	function W.retimeLights(node, durations, mins, expectSig, expectConns, src, onDone, extra)
		local r, why = lightRead(node)
		if r == nil then return 0, why end
		if expectSig ~= nil and (W.statesSig(r.tlc) ~= expectSig or Rules.connsText(r.conns) ~= expectConns) then
			return 0, "changed"
		end
		local n = count(r.tlc.states)
		if n ~= #durations then return 0, "states" end
		local cycle = 0
		local okC, cmd = pcall(function()
			local c = r.tlc:clone()
			local states = {}
			for i, st in ipairs(c.states) do
				local ns = api.type.TrafficLightState.new()
				local d = durations[i]
				if type(d) ~= "number" or d ~= d or d < 1 or d > 60 then error("duration_" .. tostring(d)) end
				local m = mins[i]
				if type(m) ~= "number" or m ~= m or m < 0 then m = 0 end
				if m > d then m = d end
				ns.duration, ns.minDuration, ns.canSkip = d, m, st.canSkip
				local l = {}
				for _, x in ipairs(st.lockedLanes or {}) do l[#l + 1] = x end
				ns.lockedLanes = l
				states[i] = ns
				cycle = cycle + d
			end
			c.states = states
			checkStates(c, n, #r.conns + #r.cws - 1)
			local p = api.engine.util.proposal.createTrafficLightProposal(node, c, r.cfg.trafficLightPreference)
			return api.cmd.makeWorldBuildProposalCmd(p, nil, false, true)
		end)
		if not okC or cmd == nil then
			local e = "error:" .. tostring(cmd):gsub("^.-:%d+: ", "")
			out("SKIP", { { "kind", "lights" }, { "node", node }, { "reason", e } })
			return 0, e
		end
		local um = nil
		pcall(function() um = r.cfg.userModifiedTrafficLightStates end)
		local dl = {}
		for i, d in ipairs(durations) do dl[i] = tostring(d) end
		local f = { { "src", src }, { "node", node }, { "to", "retime" }, { "states", n }, { "cycle", cycle },
			{ "durations", table.concat(dl, "/") }, { "pref", Lights.prefName(r.cfg.trafficLightPreference, W.lightEnum()) },
			{ "user_modified", tostring(um) } }
		for _, kv in ipairs(extra or {}) do f[#f + 1] = kv end
		out("LIGHTS", f)
		api.cmd.sendCommand(cmd, function(_res, success)
			if onDone then onDone(success == true) end
		end)
		return 1
	end

	--- The game's default phases back (the tool's Reset with Light phases = Smart Lanes): states = {}
	-- on a clone of the node's TrafficLightConfig, sent with createTrafficLightProposal and the node's
	-- preference, exactly as the Crossing window's "Reset to Default" button
	-- (gui/entity_window/double_slip_switch.tl:604-612; the engine makes its default phases for an
	-- empty list, findings.md). No index is written, so no stale index is possible. Only at a node
	-- with a standing light and phases. Logs LIGHTS src= node= to=game_phases phases=game states=<before>.
	-- Returns 1 when sent, else 0 and a reason.
	function W.defaultLights(node, src, onDone)
		local r, why = lightRead(node)
		if r == nil then return 0, why end
		local okC, cmd = pcall(function()
			local c = r.tlc:clone()
			c.states = {}
			local p = api.engine.util.proposal.createTrafficLightProposal(node, c, r.cfg.trafficLightPreference)
			return api.cmd.makeWorldBuildProposalCmd(p, nil, false, true)
		end)
		if not okC or cmd == nil then
			local e = "error:" .. tostring(cmd):gsub("^.-:%d+: ", "")
			out("SKIP", { { "kind", "lights" }, { "node", node }, { "reason", e } })
			return 0, e
		end
		out("LIGHTS", { { "src", src }, { "node", node }, { "to", "game_phases" }, { "phases", "game" },
			{ "states", count(r.tlc.states) }, { "pref", Lights.prefName(r.cfg.trafficLightPreference, W.lightEnum()) } })
		api.cmd.sendCommand(cmd, function(_res, success)
			if onDone then onDone(success == true) end
		end)
		return 1
	end

	--- Kerb connections of `node` that are red in at least one phase (the re-checks: whether the game
	-- made or re-made phases after our write). nil without a config or phases.
	function W.kerbLocked(node, kerb)
		local cfg = getComp(node, api.type.ComponentType.BASE_NODE_CONFIG)
		if not cfg or cfg.trafficLightConfig == nil or count(cfg.trafficLightConfig.states) == 0 then return nil end
		local conns = W.currentConns(node)
		-- only the kerb connections that may be freed count: into the exit's kerb lane (the exit fan), on a
		-- dedicated kerb lane (a shared-lane kerb turn stays red with its lane: Lights.sharedKerb)
		local idx = Lights.freeable(conns, Lights.kerbIndices(conns, kerb), kerb)
		local isKerb, hit = {}, {}
		for _, j in ipairs(idx) do isKerb[j] = true end
		for _, st in ipairs(cfg.trafficLightConfig.states) do
			for _, l in ipairs(st.lockedLanes or {}) do
				if isKerb[l] then hit[l] = true end
			end
		end
		local n = 0
		for _ in pairs(hit) do n = n + 1 end
		return n
	end

	--- { pref, light } of a node, nil without a config.
	function W.lightState(node)
		local CT = api.type.ComponentType
		local cfg = getComp(node, CT.BASE_NODE_CONFIG)
		if not cfg then return nil end
		local light = CT.BASE_NODE_TRAFFIC_LIGHT ~= nil and getComp(node, CT.BASE_NODE_TRAFFIC_LIGHT) ~= nil
		return { pref = cfg.trafficLightPreference, light = light }
	end

	--- Sets the light preference of `nodes` to `target` (Lights.OFF / Lights.AUTO) with the base
	-- game's own proposal, as the node window's traffic light buttons do (base
	-- gui/entity_window/double_slip_switch.tl:56 createTrafficLightProposal with a cloned
	-- trafficLightConfig, :489 TrafficLightPreference.NO; makeWorldBuildProposalCmd(p, nil, false, true)).
	-- One command per node, only for nodes that differ. Such a build adds no street segment, so
	-- the automatic pass ignores it (no loop). Logs one LIGHTS line per node sent.
	-- onDone(expect) once every command answered: expect = {node = true} of the accepted ones.
	-- Returns the number of commands sent (0: onDone is not called).
	function W.setLights(nodes, target, src, onDone)
		local enum = W.lightEnum()
		local pref = Lights.prefFor(target, enum)
		if pref == nil then return 0 end
		local cmds = {}
		for _, n in ipairs(nodes) do
			local st = W.lightState(n)
			if Lights.needs(st, target, enum) then
				local okP, cmd = pcall(function()
					local cfg = api.engine.getComponent(n, api.type.ComponentType.BASE_NODE_CONFIG)
					local tlc = cfg.trafficLightConfig
					local okC, c = pcall(function() return tlc:clone() end)
					if okC and c ~= nil then tlc = c end
					local p = api.engine.util.proposal.createTrafficLightProposal(n, tlc, pref)
					return api.cmd.makeWorldBuildProposalCmd(p, nil, false, true)
				end)
				if okP and cmd ~= nil then
					cmds[#cmds + 1] = { node = n, cmd = cmd }
					out("LIGHTS", { { "src", src }, { "node", n }, { "before", Lights.prefName(st.pref, enum) },
						{ "light", st.light }, { "to", target } })
				else
					out("SKIP", { { "kind", "lights" }, { "node", n }, { "reason", "error:" .. tostring(cmd) } })
				end
			end
		end
		if #cmds == 0 then return 0 end
		local left, expect = #cmds, {}
		for _, c in ipairs(cmds) do
			api.cmd.sendCommand(c.cmd, function(_res, success)
				if success == true then expect[c.node] = true end
				left = left - 1
				if left == 0 and onDone then onDone(expect) end
			end)
		end
		return #cmds
	end

	--- Re-reads expect = {node = true} against target: returns done, total, gone (nodes without a
	-- config any more: removed or replaced since, not counted as done).
	function W.verifyLights(expect, target)
		local enum = W.lightEnum()
		local done, total, gone = 0, 0, 0
		for n in pairs(expect) do
			total = total + 1
			local st = W.lightState(n)
			if st == nil then
				gone = gone + 1
			elseif not Lights.needs(st, target, enum) then
				done = done + 1
			end
		end
		return done, total, gone
	end

	--- Re-reads expect = {node = text | {text, bus}} (W.addItem: Rules.carText of the written connections, with
	-- the node's bus set when it has bus-only lanes): returns same, total. Connections touching a bus-only
	-- lane are left out on both sides: they were written as read, and a bus connection the player edits
	-- meanwhile is not ours.
	function W.verify(expect)
		local same, total = 0, 0
		for node, e in pairs(expect) do
			total = total + 1
			local text, bus = e, nil
			if type(e) == "table" then text, bus = e.text, e.bus end
			if Rules.carText(W.currentConns(node), bus) == text then same = same + 1 end
		end
		return same, total
	end

	---------------------------------------------------------------------------
	-- PROBE phases (PHASES_PLAN.md step 0, TESTING.md LP): read-only dump of a lit node's traffic
	-- light, once per node per Lua state, at most Write.PROBE_PHASES_MAX nodes, only while
	-- W.probeOn() (the "Debug: performance log" setting). Nothing is sent. Lines (all match
	-- `grep "PROBE phases"`):
	--   PROBE phases node= type= pref= user_modified= user_lanes= states=N durations= min= skip=
	--     conns=N arms=<letter>=<segment>@<deg>,... crosswalks=<entities> cw_is_edge=y|n,...
	--     light=true|false light_state= light_time= state_times= data_durations= data_locked=
	--     data_same= data_red= data_models=
	--   PROBE phases_conns node= part=i/k list=A1>B4,...  (config order: arm letter + lane index of
	--     segment0 > segment1; suffix t = withTram, x = not withRoad; ?<segment> = not at the node)
	--   PROBE phases_state node= state=i part=i/k duration= min= skip= n= locked=<indices>
	-- Arms are lettered counter-clockwise by the angle of their direction away from the node
	-- (sl_phases P.armsFromWorld). An unlit node (no BASE_NODE_TRAFFIC_LIGHT and no phases) is not
	-- logged and not marked, so a later read logs it once its light came.

	local function num(x)
		if type(x) == "number" then return string.format("%g", x) end
		return tostring(x)
	end

	local function joinList(list, f)
		local parts = {}
		for i, x in ipairs(list or {}) do
			if i > Write.PROBE_LIST_MAX then
				parts[#parts + 1] = "+"
				break
			end
			parts[#parts + 1] = f and f(x) or num(x)
		end
		return #parts > 0 and table.concat(parts, ",") or "-"
	end

	--- Plain copy of a userdata / table list (nil -> {}), at most Write.PROBE_LIST_MAX entries.
	-- A table entry at key 0 (a 0-based map, e.g. trafficLightData's state2* if so converted) comes
	-- first; a native vector, which ipairs sees as empty (findings.md: filterCategories), is read
	-- with :size() / :at(i) (1-based).
	local function plain(list)
		local out = {}
		pcall(function()
			if type(list) == "table" and list[0] ~= nil then out[1] = list[0] end
			for _, x in ipairs(list or {}) do
				if #out >= Write.PROBE_LIST_MAX then break end
				out[#out + 1] = x
			end
		end)
		if #out == 0 and type(list) == "userdata" then
			pcall(function()
				local n = list:size()
				if type(n) ~= "number" then return end
				for i = 1, math.min(n, Write.PROBE_LIST_MAX) do out[#out + 1] = list:at(i) end
			end)
		end
		return out
	end

	--- Comma list split into chunks of at most Write.PROBE_CHUNK characters (at least one chunk).
	local function chunks(text)
		local out, cur = {}, ""
		for item in text:gmatch("[^,]+") do
			if #cur > 0 and #cur + 1 + #item > Write.PROBE_CHUNK then
				out[#out + 1] = cur
				cur = item
			else
				cur = #cur > 0 and (cur .. "," .. item) or item
			end
		end
		out[#out + 1] = cur
		return out
	end

	local function field(obj, key)
		local ok, v = pcall(function() return obj[key] end)
		if ok then return v end
		return nil
	end

	--- Logs the PROBE phases lines of `node` (see above) when the probe is on and the node is lit
	-- and new. world: the sl_ring world of the read (arm angles; nil: arms from the connections, no
	-- angles). Returns true when logged. Never throws (the callers pcall it anyway).
	function W.probePhases(node, world)
		if W.probeOn == nil then return false end
		local okOn, on = pcall(W.probeOn)
		if not okOn or on ~= true then return false end
		if W.probeSeen[node] or W.probeCount >= Write.PROBE_PHASES_MAX then return false end
		local CT = api.type.ComponentType
		local cfg = getComp(node, CT.BASE_NODE_CONFIG)
		if not cfg then return false end
		local tl = CT.BASE_NODE_TRAFFIC_LIGHT ~= nil and getComp(node, CT.BASE_NODE_TRAFFIC_LIGHT) or nil
		local tlc = field(cfg, "trafficLightConfig")
		local states = plain(tlc and field(tlc, "states"))
		if tl == nil and #states == 0 then return false end
		W.probeSeen[node] = true
		W.probeCount = W.probeCount + 1
		local ok, err = pcall(function()
			-- arms: letters by angle (counter-clockwise from +x)
			local arms = {}
			if world ~= nil then arms = Phases.armsFromWorld(world, node) end
			table.sort(arms, function(p, q)
				if p.angle ~= q.angle then return p.angle < q.angle end
				return p.seg < q.seg
			end)
			local letter, armText = {}, {}
			for i, a in ipairs(arms) do
				local l = string.char(64 + math.min(i, 26))
				letter[a.seg] = l
				armText[#armText + 1] = l .. "=" .. tostring(a.seg) .. "@" .. string.format("%.1f", a.angle)
			end
			local conns = W.currentConns(node)
			local function end_(seg, lane)
				return (letter[seg] or ("?" .. tostring(seg))) .. tostring(lane)
			end
			local cText = {}
			for i, c in ipairs(conns) do
				if i > Write.PROBE_LIST_MAX then break end
				cText[#cText + 1] = end_(c.segment0, c.lane0) .. ">" .. end_(c.segment1, c.lane1)
					.. (c.withTram and "t" or "") .. (c.withRoad and "" or "x")
			end
			local cws = plain(field(cfg, "crosswalks"))
			local isEdge = {}
			for _, cw in ipairs(cws) do isEdge[#isEdge + 1] = letter[cw] and "y" or "n" end
			local durations, mins, skips, lists = {}, {}, {}, {}
			for i, st in ipairs(states) do
				if i > Write.PROBE_STATES_MAX then break end
				durations[i] = num(field(st, "duration"))
				mins[i] = num(field(st, "minDuration"))
				skips[i] = tostring(field(st, "canSkip"))
				lists[i] = plain(field(st, "lockedLanes"))
			end
			local f = { { "node", node }, { "type", num(tlc and field(tlc, "trafficLightType")) },
				{ "pref", Lights.prefName(field(cfg, "trafficLightPreference"), W.lightEnum()) },
				{ "user_modified", tostring(field(cfg, "userModifiedTrafficLightStates")) },
				{ "user_lanes", tostring(field(cfg, "userModifiedLaneConnections")) },
				{ "states", #states }, { "durations", joinList(durations, tostring) }, { "min", joinList(mins, tostring) },
				{ "skip", joinList(skips, tostring) }, { "conns", #conns }, { "arms", #armText > 0 and table.concat(armText, ",") or "-" },
				{ "crosswalks", joinList(cws) }, { "cw_is_edge", joinList(isEdge, tostring) }, { "light", tl ~= nil } }
			if tl ~= nil then
				f[#f + 1] = { "light_state", num(field(tl, "state")) }
				f[#f + 1] = { "light_time", num(field(tl, "time")) }
				f[#f + 1] = { "state_times", joinList(plain(field(tl, "stateTimes"))) }
				local data = field(tl, "trafficLightData")
				if data ~= nil then
					f[#f + 1] = { "data_durations", joinList(plain(field(data, "state2duration"))) }
					local dl = plain(field(data, "state2lockedLanes"))
					local counts, same = {}, #dl == #lists
					for i, l in ipairs(dl) do
						local pl = plain(l)
						counts[#counts + 1] = #pl
						if same then
							local a, b = table.concat(pl, ","), table.concat(lists[i] or {}, ",")
							if a ~= b then same = false end
						end
					end
					f[#f + 1] = { "data_locked", joinList(counts) }
					f[#f + 1] = { "data_same", same }
					local red = {}
					for _, l in ipairs(plain(field(data, "state2redLightModelIndices"))) do red[#red + 1] = #plain(l) end
					f[#f + 1] = { "data_red", joinList(red) }
					f[#f + 1] = { "data_models", #plain(field(data, "animatedModels")) }
				end
			end
			out("PROBE phases", f)
			local parts = chunks(#cText > 0 and table.concat(cText, ",") or "-")
			for i, p in ipairs(parts) do
				out("PROBE phases_conns", { { "node", node }, { "part", i .. "/" .. #parts }, { "list", p } })
			end
			for s, list in ipairs(lists) do
				local lp = chunks(joinList(list))
				for i, p in ipairs(lp) do
					out("PROBE phases_state", { { "node", node }, { "state", s }, { "part", i .. "/" .. #lp },
						{ "duration", durations[s] }, { "min", mins[s] }, { "skip", skips[s] }, { "n", #list }, { "locked", p } })
				end
			end
		end)
		if not ok then out("ERROR", { { "where", "probe_phases" }, { "node", node }, { "err", tostring(err) } }) end
		return true
	end

	---------------------------------------------------------------------------
	-- Ring edge splits (sl_split.lua, PLAN.md "Smart Lanes adds the mid nodes")

	local function v3(v)
		if v == nil then return nil end
		return { x = v.x or v[1] or 0, y = v.y or v[2] or 0, z = v.z or v[3] or 0 }
	end
	local function vec3(p) return api.type.Vec3f.new(p.x, p.y, p.z or 0) end

	--- Why ring edge `seg` (its BASE_EDGE e) may not be split, or nil: an edge object on it (a stop, a signal),
	-- a bridge or tunnel, tram tracks, an edge a construction owns (a station's, a depot's).
	function W.splitRefusal(seg, e)
		local okO, nObj = pcall(function() return count(e.objects) end)
		if okO and (nObj or 0) > 0 then return "edge_objects" end
		local okT, ty = pcall(function() return e.type end)
		if okT and ty ~= nil and ty ~= 0 then return "bridge_tunnel" end
		for _, l in ipairs(Ring.lanesFromConfigs(e.laneConfigs, W.transportModes())) do
			if l.tram then return "tram" end
		end
		local okC, con = pcall(function()
			return api.engine.system.streetConnectorSystem.getConstructionEntityForEdge(seg)
		end)
		if okC and type(con) == "number" and con >= 0 then return "construction" end
		return nil
	end

	--- Splits ring edges `list` (sl_split S.edges: { {seg, from, to} }) in one proposal: each edge removed, its two
	-- exact halves added (sl_split S.halves; every field of the edge copied: template, style, lanes, decorations,
	-- town lock, precedence at its old ends, owner), a new node at the middle with straight-on connections, and the
	-- configs of the old end nodes re-pointed to the halves (same order, so their light phases still index them;
	-- crosswalks too). Temp ids: edges -1, -2, ... first, then the new nodes (as square_stress_test's link proposals).
	-- Context cleanupStreetGraph = false (the menu's cleanup is what joined the nodes away). onDone(success).
	-- Returns the number of edges split (0: nothing sent, onDone not called) and, when 0, why.
	function W.sendSplit(list, onDone)
		local CT = api.type.ComponentType
		local n = #list
		if n == 0 then return 0, "nothing" end
		local edgesAdd, nodesAdd, removes = {}, {}, {}
		local remap = {}   -- existing node -> { [old edge] = temp id of its half there }
		local mids = {}    -- temp node id -> { arriving temp edge, leaving temp edge, lanes }
		local order = {}
		for k, it in ipairs(list) do
			local e = getComp(it.seg, CT.BASE_EDGE)
			if e == nil then return 0, "no_edge" end
			local why = W.splitRefusal(it.seg, e)
			if why ~= nil then return 0, why end
			local h = Split.halves(v3(e.position0), v3(e.tangent0), v3(e.position1), v3(e.tangent1))
			if Split.length(h.first) < Split.MIN_PIECE or Split.length(h.second) < Split.MIN_PIECE then return 0, "short" end
			local idA, idB, idM = -(2 * k - 1), -(2 * k), -(2 * n + k)
			local street = getComp(it.seg, CT.BASE_EDGE_STREET)
			local owned = CT.PLAYER_OWNED ~= nil and getComp(it.seg, CT.PLAYER_OWNED) or nil
			local function piece(id, c, n0, n1, first)
				local sg = api.type.SegmentAndEntity.new()
				sg.entity = id
				sg.type = 0
				local comp = sg.comp
				comp.node0, comp.node1 = n0, n1
				comp.position0, comp.position1 = vec3(c.p0), vec3(c.p1)
				comp.tangent0, comp.tangent1 = vec3(c.t0), vec3(c.t1)
				-- the edge as it is: lanes, template, style, decorations, lock (as parallel_tracks' road pieces)
				comp.type = e.type
				comp.typeIndex = e.typeIndex
				comp.laneConfigs = e.laneConfigs
				pcall(function() comp.roadType = e.roadType end)
				pcall(function() comp.roadTemplate = e.roadTemplate end)
				pcall(function() comp.roadStyle = e.roadStyle end)
				pcall(function() comp.edgeDecorations = e.edgeDecorations end)
				pcall(function() comp.roadDevelopmentLocked = e.roadDevelopmentLocked end)
				pcall(function() comp.distance = Split.length(c) end)
				if street ~= nil then
					pcall(function()
						if first then sg.streetEdge.precedenceNode0 = street.precedenceNode0
						else sg.streetEdge.precedenceNode1 = street.precedenceNode1 end
					end)
				end
				if owned ~= nil then pcall(function() sg.playerOwned = owned end) end
				return sg
			end
			edgesAdd[#edgesAdd + 1] = piece(idA, h.first, e.node0, idM, true)
			edgesAdd[#edgesAdd + 1] = piece(idB, h.second, idM, e.node1, false)
			local ne = api.type.NodeAndEntity.new()
			ne.entity = idM
			ne.comp.position = vec3(h.mid)
			nodesAdd[#nodesAdd + 1] = ne
			removes[#removes + 1] = it.seg
			for _, pair in ipairs({ { e.node0, idA }, { e.node1, idB } }) do
				if remap[pair[1]] == nil then
					remap[pair[1]] = {}
					order[#order + 1] = pair[1]
				end
				remap[pair[1]][it.seg] = pair[2]
			end
			mids[idM] = { into = idA, from = idB, lanes = Ring.lanesFromConfigs(e.laneConfigs, W.transportModes()) }
		end
		local LC = api.type.LaneConnection
		local function newLC(s0, l0, s1, l1, road, tram)
			-- (plain tables when the api has no constructor: the "table" strategy of W.buildEntry)
			local lc = (LC ~= nil and LC.new ~= nil) and LC.new() or {}
			lc.segment0, lc.lane0, lc.segment1, lc.lane1 = s0, l0, s1, l1
			lc.withRoad, lc.withTram = road == true, tram == true
			return lc
		end
		local cfgAdd, cfgRemove = {}, {}
		for _, node in ipairs(order) do
			local map = remap[node]
			local cfg = getComp(node, CT.BASE_NODE_CONFIG)
			if cfg == nil then return 0, "no_config" end
			local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
			entry.entity = node
			entry.comp = cfg
			local conns = {}
			for i, c in ipairs(cfg.laneConnections or {}) do
				conns[i] = newLC(map[c.segment0] or c.segment0, c.lane0, map[c.segment1] or c.segment1, c.lane1, c.withRoad, c.withTram)
			end
			entry.comp.laneConnections = conns
			local walks = {}
			for i, w in ipairs(cfg.crosswalks or {}) do walks[i] = map[w] or w end
			pcall(function() entry.comp.crosswalks = walks end)
			cfgAdd[#cfgAdd + 1] = entry
			cfgRemove[#cfgRemove + 1] = node
		end
		-- the new nodes: straight on, every road lane into the same lane (the engine's own plain ring node)
		for k = 1, n do
			local idM = -(2 * n + k)
			local m = mids[idM]
			local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
			entry.entity = idM
			-- a new node has no config to start from (as square_stress_test's nc newEntry for new nodes)
			if entry.comp == nil then entry.comp = {} end
			local conns = {}
			local L = #m.lanes
			for k0 = 0, L - 1 do
				local l = m.lanes[k0 + 1]
				-- a lane runs node0 -> node1 of the old edge when forward: in on the first half, out on the second
				if l.road and l.forward then conns[#conns + 1] = newLC(m.into, L - 1 - k0, m.from, k0, true, false)
				elseif l.road then conns[#conns + 1] = newLC(m.from, k0, m.into, L - 1 - k0, true, false) end
			end
			entry.comp.laneConnections = conns
			pcall(function() entry.comp.crosswalks = {} end)
			cfgAdd[#cfgAdd + 1] = entry
		end
		local proposal = api.type.SimpleProposal.new()
		proposal.streetProposal.nodesToAdd = nodesAdd
		proposal.streetProposal.edgesToAdd = edgesAdd
		proposal.streetProposal.edgesToRemove = removes
		proposal.streetProposal.nodeConfigsToRemove = cfgRemove
		proposal.streetProposal.nodeConfigsToAdd = cfgAdd
		local context = api.type.Context.new()
		context.player = api.engine.util.getPlayer()
		context.cleanupStreetGraph = false
		local cmd = api.cmd.makeWorldBuildProposalCmd(proposal, context, false, true, true)
		api.cmd.sendCommand(cmd, function(_res, success)
			if onDone then onDone(success == true) end
		end)
		return n
	end

	return W
end

return Write
