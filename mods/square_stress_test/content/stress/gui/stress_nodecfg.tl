-- Stress Test: node configs (BASE_NODE_CONFIG) for script street proposals.
--
-- Script-made nodes get no BASE_NODE_CONFIG at all (docs/findings/towns.md "The engine's lane connections
-- at a town junction"), and such a node can crash the simulation at random: Engine.h:323
-- GetComponentDataIndex, "component type is ecs::component::BaseNodeConfig ... entity is not known"
-- (towns.md "Street proposal crash", Organic Towns; the Stress Test's Junction test and Showcase crashed the
-- same way, docs/findings/roads.md "Script link roads without node configs"). So every node a proposal adds
-- gets a config here, and an existing node that gains an edge gets a full new one (remove + add when it has
-- one; removing a missing config asserts Engine.cpp:693).
--
-- The pattern: per ordered pair of different segments a -> b, a's arriving road lanes into b's leaving ones,
-- outer with outer (in_a[k] -> out_b[k]). For two-way streets that is the engine's own town-junction pattern
-- (incoming lane i -> outgoing lane m + 1 - i, i = 1..m/2; towns.md, verified on town_new_small), for a
-- one-way continuation lane i -> m + 1 - i (roads.md "Junction lane connections": straight on a one-way ring).
-- Lane indices are LaneConnection's: zero-based incl. the sidewalks, left to right looking from the node into
-- the segment, i.e. a lane's laneConfigs index at node0 and the mirrored one at node1; a lane leaves the node
-- when it runs forward at node0 or backward at node1 (square_smart_lanes sl_ring.lanesAt, in-game verified).
--
-- Driving side: nc.side reads each lane's direction, so arriving lanes only ever connect to leaving ones in
-- either driving side. "Outer" is the right-hand kerb; in left-hand traffic both sorts flip together, so
-- the pairs run median with median instead (all indices in range). Where widths differ: at a junction (3+
-- streets) one-to-one for the smaller count (the wider side's extra lanes get no connection there); at a joint of
-- two streets the narrower side's last lane fans into (and gathers) all the wider side's extra lanes (nc.pattern,
-- 2026-10-13). In left-hand traffic "last" is the kerb side instead. Only the count model (countSide: unreadable
-- lanes, nc.junctionConns) assumes right-hand traffic; nc.connsAt uses the read lanes when it can.
-- Changed connection lists re-point the node's traffic light phases (nc.relight).

local nc : SquareStressNodeCfg = {} as SquareStressNodeCfg

-- TransportMode values (api/tealdef/api/type.d.tl TransportMode order; square_smart_lanes sl_ring.MODES),
-- replaced by the live enum when it can be read.
local MODES : {string : integer} = { PERSON = 0, CAR = 2, BUS = 3, TRUCK = 4, TRAM = 5, ELECTRIC_TRAM = 6 }
local REVERSAL_COS <const> = 0.866   -- two segments leaving the node within 30 deg: no connection between them

local function modes() : {string : integer}
	local ok, tm = pcall(function() : any return (api.type as {string : any})["enum"] and ((api.type as {string : any})["enum"] as {string : any})["TransportMode"] end)
	if ok and tm ~= nil then
		local live : {string : integer} = {}
		local okR = pcall(function()
			for k in pairs(MODES) do live[k] = (tm as {string : integer})[k] end
		end)
		if okR and live.CAR ~= nil and live.BUS ~= nil and live.TRUCK ~= nil then return live end
	end
	return MODES
end

local function comp(e : integer, ct : Engine.ComponentType) : any
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

local function newLC(seg0 : integer, lane0 : integer, seg1 : integer, lane1 : integer, tram : boolean) : LaneConnection
	local LC = (api.type as {string : any})["LaneConnection"] as {string : function() : any}
	local lc : {string : any} = LC ~= nil and LC.new ~= nil and LC.new() as {string : any} or {}
	lc.segment0 = seg0
	lc.lane0 = lane0
	lc.segment1 = seg1
	lc.lane1 = lane1
	lc.withRoad = true
	lc.withTram = tram == true
	return lc as LaneConnection
end

local function newEntry(node : integer, base : Engine.Component.BaseNodeConfig) : Proposal.BaseNodeLaneConnectionAndEntity
	local T = (api.type as {string : any})["BaseNodeLaneConnectionAndEntity"] as {string : function() : any}
	local entry : Proposal.BaseNodeLaneConnectionAndEntity
	if T ~= nil and T.new ~= nil then
		entry = T.new() as Proposal.BaseNodeLaneConnectionAndEntity
	else
		entry = {} as Proposal.BaseNodeLaneConnectionAndEntity
	end
	entry.entity = node
	if base ~= nil then entry.comp = base end   -- keeps its crosswalks and light settings
	if entry.comp == nil then entry.comp = {} as Engine.Component.BaseNodeConfig end
	return entry
end

local function countSide(lanes : integer) : SquareStressNodeSide
	local n = (lanes ~= nil and lanes >= 3) and lanes or 4
	local m = n - 2
	local h = math.floor(m / 2)
	local s : SquareStressNodeSide = { ins = {}, outs = {}, tram = {}, lanes = n }
	for i = 1, h do s.ins[#s.ins + 1] = i end
	for i = m, m - h + 1, -1 do s.outs[#s.outs + 1] = i end
	return s
end

function nc.side(laneConfigs : any, atEnd : integer, lanes? : integer) : SquareStressNodeSide
	local list : {any} = {}
	local okL = pcall(function()
		local lcs = laneConfigs as {any}
		for i = 1, #lcs do list[#list + 1] = lcs[i] end
	end)
	if not okL then
		list = {}
		okL = pcall(function()
			for _, lc in ipairs(laneConfigs as {any}) do list[#list + 1] = lc end
		end)
	end
	if not okL or #list < 3 then return countSide(lanes or (#list >= 3 and #list or nil)) end
	local M = modes()
	local n = #list
	local info : {{string : boolean}} = {}
	local anyModes = false
	for i, lc in ipairs(list) do
		local set : {integer : boolean} = {}
		local okF, fwd = pcall(function() : boolean return (lc as {string : any}).forward == true end)
		pcall(function()
			local tm = (lc as {string : any}).transportModes as {any : boolean}
			if tm ~= nil then
				for k, v in pairs(tm) do
					if v then set[k as integer] = true; anyModes = true end
				end
			end
		end)
		info[i] = {
			forward = okF and fwd,
			road = set[M.CAR] == true or set[M.BUS] == true or set[M.TRUCK] == true,
			tram = set[M.TRAM] == true or set[M.ELECTRIC_TRAM] == true,
		}
	end
	local s : SquareStressNodeSide = { ins = {}, outs = {}, tram = {}, lanes = n }
	for i = 1, n do
		local k0 = i - 1
		-- without readable modes (fixtures): every lane but the two sidewalks is a road lane
		local road = anyModes and info[i].road or (not anyModes and i > 1 and i < n)
		if road then
			local idx = atEnd == 0 and k0 or n - 1 - k0
			local leaving = (atEnd == 0 and info[i].forward) or (atEnd ~= 0 and not info[i].forward)
			if leaving then s.outs[#s.outs + 1] = idx else s.ins[#s.ins + 1] = idx end
			if info[i].tram then s.tram[idx] = true end
		end
	end
	-- a lane list without any forward flag (unreadable) reads as all arriving: use the count model
	if #s.outs == 0 and #s.ins > 0 and not anyModes then return countSide(n) end
	table.sort(s.ins)                                   -- arriving: outer (driver's right) = lowest index
	table.sort(s.outs, function(a : integer, b : integer) : boolean return a > b end)   -- leaving: outer = highest
	return s
end

--- The lane connections of a node: arriving lanes of each segment to the leaving lanes of every other one, kerb
--- lanes aligned (ins / outs are sorted kerb first). At a junction (3+ segments) one-to-one for the smaller count.
--- At a joint of two segments with different lane counts (the rig's arm -> large country link, link -> entry
--- roundabout arm) the far lane fans: the narrower side's last lane feeds every remaining lane of the wider side,
--- and the wider side's extra lanes all feed the narrower side's last lane (2026-10-13 lane audit of session
--- 2026-10-13_0205_top-up-61157: the link's third lane was never fed from the 2-lane arm and led nowhere into
--- it, so cars had to change lanes on the link, which penalised layouts that pin turns to one lane). No two
--- connections cross (kerb to kerb, then outwards in order).
function nc.pattern(segs : {integer}, sides : {integer : SquareStressNodeSide}, covered? : {integer : boolean}) : {{integer}}
	local out : {{integer}} = {}
	local joint = #segs == 2
	for _, a in ipairs(segs) do
		for _, b in ipairs(segs) do
			local sa, sb = sides[a], sides[b]
			if a ~= b and sa ~= nil and sb ~= nil and not (covered ~= nil and covered[a] and covered[b]) then
				local reversal = sa.dir ~= nil and sb.dir ~= nil and sa.dir[1] * sb.dir[1] + sa.dir[2] * sb.dir[2] > REVERSAL_COS
				if not reversal then
					local na, nb = #sa.ins, #sb.outs
					local n = math.min(na, nb)
					if joint and na > 0 and nb > 0 then n = math.max(na, nb) end
					for k = 1, n do
						local l0, l1 = sa.ins[math.min(k, na)], sb.outs[math.min(k, nb)]
						out[#out + 1] = { a, l0, b, l1, (sa.tram[l0] and sb.tram[l1]) and 1 or 0 }
					end
				end
			end
		end
	end
	return out
end

function nc.junctionConns(segs : {integer}, lanes : {integer : integer}) : {LaneConnection}
	local sides : {integer : SquareStressNodeSide} = {}
	for _, s in ipairs(segs) do sides[s] = countSide(lanes[s] or 4) end
	local conns : {LaneConnection} = {}
	for _, c in ipairs(nc.pattern(segs, sides)) do conns[#conns + 1] = newLC(c[1], c[2], c[3], c[4], false) end
	return conns
end

function nc.newNodeConfig(node : integer, segs : {integer}, lanes : {integer : integer}) : Proposal.BaseNodeLaneConnectionAndEntity
	local entry = newEntry(node, nil)
	entry.comp.laneConnections = nc.junctionConns(segs, lanes)
	return entry
end

function nc.edgeLanes(e : integer) : integer
	local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
	local ok, n = pcall(function() : integer return #be.laneConfigs end)
	if ok and n ~= nil and n >= 3 then return n end
	return 4
end

local function unit2(x : number, y : number) : {number}
	local l = math.sqrt(x * x + y * y)
	if l < 1e-6 then return nil end
	return { x / l, y / l }
end

--- Traffic light phases (docs/findings/roads.md "Traffic light phases index the lane connections"):
--- TrafficLightState.lockedLanes are 0-based indices into the node's laneConnections, then its crosswalks
--- (#laneConnections + k - 1). A config written with a changed connection list keeps the read config's
--- phases, and stale indices crashed the simulation (VectorMap.h:11 "key >= 0"), so every changed list
--- re-points them. old: old connection index (1-based) -> {s0, l0, s1, l1} re-pointed, nil when dropped;
--- new: the written list; cwMap: old crosswalk k -> its new position (nil: dropped). A kept connection
--- keeps its state; a new one takes that of its movement (segment0 > segment1, locked only where every
--- old connection of it was), else of its approach (likewise), else it is unlocked (square_smart_lanes
--- sl_rules.lua remapLocked, verified in game: "Phases survive a Smart Lanes lane write"). A brand-new
--- approach is therefore green in every phase: no crash, but it does not stop for the light, unless it
--- replaces a leg an earlier proposal removed (a seed's ghost, nc.ghost / carryOf: the Lights showcase's
--- town entry joins), whose per-phase states and crosswalk it then takes over.
local function connKey(c : {integer}) : string
	return string.format("%s:%s>%s:%s", tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(c[4]))
end

--- Lookups of an old list's states in one phase: by connection, by movement (segment0 > segment1, locked
--- only where every old connection of it was), by approach (likewise).
local record States
	byKey : {string : boolean}
	byPair : {string : boolean}
	bySeg : {integer : boolean}
end

local function statesOf(old : {integer : {integer}}, nOld : integer, locked : {integer}) : States
	local isLocked : {integer : boolean} = {}
	for _, i in ipairs(locked or {}) do isLocked[i] = true end
	local st : States = { byKey = {}, byPair = {}, bySeg = {} }
	for i = 1, nOld or 0 do
		local c = old[i]
		if c ~= nil then
			local l = isLocked[i - 1] == true
			st.byKey[connKey(c)] = l
			local pk = tostring(c[1]) .. ">" .. tostring(c[3])
			if st.byPair[pk] == nil then st.byPair[pk] = l else st.byPair[pk] = st.byPair[pk] and l end
			if st.bySeg[c[1]] == nil then st.bySeg[c[1]] = l else st.bySeg[c[1]] = st.bySeg[c[1]] and l end
		end
	end
	return st
end

function nc.remapLocked(old : {integer : {integer}}, nOld : integer, new : {{integer}}, cwMap : {integer : integer},
		nCwOld : integer, locked : {integer}, carry? : SquareStressLightCarry, phase? : integer) : {integer}
	local isLocked : {integer : boolean} = {}
	for _, i in ipairs(locked or {}) do isLocked[i] = true end
	local cur = statesOf(old, nOld, locked)
	-- a replaced leg (town entry joins): its connections take the removed leg's states in this phase
	local was : States = nil
	if carry ~= nil and phase ~= nil and carry.locked[phase] ~= nil then was = statesOf(carry.old, carry.nOld, carry.locked[phase]) end
	local out : {integer} = {}
	for j, c in ipairs(new) do
		local l = cur.byKey[connKey(c)]
		local pk = tostring(c[1]) .. ">" .. tostring(c[3])
		if l == nil and was ~= nil and (c[1] == carry.leg or c[3] == carry.leg) then
			l = was.byKey[connKey(c)]
			if l == nil then l = was.byPair[pk] end
			if l == nil then l = was.bySeg[c[1]] end
		end
		if l == nil then l = cur.byPair[pk] end
		if l == nil then l = cur.bySeg[c[1]] end
		if l then out[#out + 1] = j - 1 end
	end
	for k = 1, nCwOld or 0 do
		local nk = cwMap ~= nil and cwMap[k] or nil
		if nk ~= nil and isLocked[(nOld or 0) + k - 1] then out[#out + 1] = #new + nk - 1 end
	end
	return out
end

--- Re-points the phases of entry (its comp taken from the read config cfg) as nc.remapLocked, on a
--- clone of the config as the base Crossing window does (double_slip_switch.tl:46, 566-577). Returns the
--- number of phases written: 0 when cfg has none (no light), -1 when they could not be re-pointed and
--- were reset to the game's default instead (states = {}: the window's Reset to Default,
--- double_slip_switch.tl:604-612; inferred to make the engine re-make them; no stale index either way).
--- carry (a replaced leg, nc.configs): remapLocked's carry per phase, and its re-added crosswalk (at carry.cwIndex)
--- locked in the phases where the removed leg's crosswalk was.
function nc.relight(entry : Proposal.BaseNodeLaneConnectionAndEntity, cfg : Engine.Component.BaseNodeConfig,
		old : {integer : {integer}}, nOld : integer, new : {{integer}}, cwMap : {integer : integer}, nCwOld : integer,
		carry? : SquareStressLightCarry) : integer
	if cfg == nil then return 0 end
	local okN, n = pcall(function() : integer
		local tlc = cfg.trafficLightConfig
		if tlc == nil or tlc.states == nil then return 0 end
		local k = 0
		for _ in ipairs(tlc.states) do k = k + 1 end
		return k
	end)
	if not okN or n == nil or n == 0 then return 0 end
	local ok = pcall(function()
		local c = cfg.trafficLightConfig:clone()
		local states : {Engine.Component.TrafficLightState} = {}
		for i, st in ipairs(c.states) do
			local locked : {integer} = {}
			for _, l in ipairs(st.lockedLanes or {}) do locked[#locked + 1] = l end
			local ns = api.type.TrafficLightState.new()
			ns.duration, ns.minDuration, ns.canSkip = st.duration, st.minDuration, st.canSkip
			local l = nc.remapLocked(old, nOld, new, cwMap, nCwOld, locked, carry, i)
			if carry ~= nil and carry.cwIndex ~= nil and carry.cwLocked ~= nil and carry.cwLocked[i] then l[#l + 1] = carry.cwIndex end
			ns.lockedLanes = l
			states[i] = ns
		end
		c.states = states
		entry.comp.trafficLightConfig = c
	end)
	if ok then return n end
	pcall(function()
		local c = cfg.trafficLightConfig:clone()
		c.states = {}
		entry.comp.trafficLightConfig = c
	end)
	return -1
end

function nc.ghost(node : integer, leg : integer) : SquareStressLightGhost
	if node == nil or leg == nil then return nil end
	local cfg = comp(node, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
	if cfg == nil then return nil end
	local g : SquareStressLightGhost = { leg = leg, conns = {}, cws = {}, locked = {} }
	local uses = false
	local ok = pcall(function()
		local tlc = cfg.trafficLightConfig
		if tlc == nil or tlc.states == nil then return end
		for i, st in ipairs(tlc.states) do
			local l : {integer} = {}
			for _, x in ipairs(st.lockedLanes or {}) do l[#l + 1] = x end
			g.locked[i] = l
		end
		for i = 1, #(cfg.laneConnections or {}) do
			local o = cfg.laneConnections[i]
			g.conns[i] = { o.segment0, o.lane0, o.segment1, o.lane1 }
			if o.segment0 == leg or o.segment1 == leg then uses = true end
		end
		for i = 1, #(cfg.crosswalks or {}) do
			g.cws[i] = cfg.crosswalks[i]
			if g.cws[i] == leg then uses = true end
		end
	end)
	if not ok or #g.locked == 0 or not uses then return nil end
	return g
end

--- A seed's ghost applied to the replacement node's new list (`plain`, its crosswalks `cws` appended to in
--- place): nil and why when the node changed since the ghost was read (another phase count, a connection
--- the ghost did not have) or the new leg is not exactly one added edge.
local function carryOf(g : SquareStressLightGhost, seed : SquareStressNodeSeed, cfg : Engine.Component.BaseNodeConfig,
		oldNow : {integer : {integer}}, nOldNow : integer, added : {integer}, plain : {{integer}}, cws : {integer}) : SquareStressLightCarry, string
	local okN, n = pcall(function() : integer
		local k = 0
		for _ in ipairs(cfg.trafficLightConfig.states) do k = k + 1 end
		return k
	end)
	if not okN or n ~= #g.locked then return nil, string.format("phases %s, were %d", tostring(n), #g.locked) end
	local copies : {integer : boolean} = {}
	for _, v in pairs(seed.newIds or {}) do copies[v] = true end
	local leg : integer = nil
	for _, e in ipairs(added) do
		if not copies[e] then
			if leg ~= nil then return nil, "two new legs" end
			leg = e
		end
	end
	if leg == nil then return nil, "no new leg" end
	local function ren(e : integer) : integer
		if e == g.leg then return leg end
		return (seed.newIds or {})[e] or e
	end
	local carry : SquareStressLightCarry = { old = {}, nOld = #g.conns, locked = g.locked, leg = leg }
	local had : {string : boolean} = {}
	for i, c in ipairs(g.conns) do
		local r = { ren(c[1]), c[2], ren(c[3]), c[4] }
		carry.old[i] = r
		had[connKey(r)] = true
	end
	for i = 1, nOldNow or 0 do
		local c = oldNow[i]
		if c ~= nil and not had[connKey(c)] then return nil, "connection " .. connKey(c) .. " is new" end
	end
	for k, cw in ipairs(g.cws) do
		if cw == g.leg then
			local present = false
			for _, x in ipairs(cws) do if x == leg then present = true end end
			if not present then
				cws[#cws + 1] = leg
				carry.cwIndex = #plain + #cws - 1
				carry.cwLocked = {}
				local idx = #g.conns + k - 1
				for i, l in ipairs(g.locked) do
					local hit = false
					for _, x in ipairs(l) do if x == idx then hit = true end end
					carry.cwLocked[i] = hit
				end
			end
		end
	end
	return carry, nil
end

--- The side of an edge (BaseEdge-like: laneConfigs, node0/node1, tangents) at `node`; nil when it doesn't end there.
local function edgeSide(be : Engine.Component.BaseEdge, node : integer) : SquareStressNodeSide
	if be == nil then return nil end
	local okE, atEnd = pcall(function() : integer
		if be.node0 == node then return 0 end
		if be.node1 == node then return 1 end
		return nil
	end)
	if not okE or atEnd == nil then return nil end
	local s = nc.side((be as {string : any}).laneConfigs, atEnd)
	pcall(function()
		local t = atEnd == 0 and be.tangent0 or be.tangent1
		if t ~= nil then
			local f = atEnd == 0 and 1.0 or -1.0
			s.dir = unit2(f * t.x, f * t.y)
		end
	end)
	return s
end

function nc.connsAt(node : integer, segs : {integer}, bes : {integer : Engine.Component.BaseEdge}, lanes : {integer : integer}) : {LaneConnection}
	local sides : {integer : SquareStressNodeSide} = {}
	for _, s in ipairs(segs) do
		sides[s] = edgeSide(bes ~= nil and bes[s] or nil, node) or countSide(lanes ~= nil and lanes[s] or 4)
	end
	local conns : {LaneConnection} = {}
	for _, c in ipairs(nc.pattern(segs, sides)) do conns[#conns + 1] = newLC(c[1], c[2], c[3], c[4], c[5] == 1) end
	return conns
end

--- A node's old config read as plain connections (newIds re-pointed, gone dropped), its crosswalks the same
--- way, the segments its connections name, and for nc.relight: old index -> re-pointed connection (nil:
--- dropped), the old count, old crosswalk k -> new position, the old crosswalk count. nil without a config.
local record OldConfig
	cfg : Engine.Component.BaseNodeConfig
	conns : {{any}}
	cws : {integer}
	covered : {integer : boolean}
	old : {integer : {integer}}
	nOld : integer
	cwMap : {integer : integer}
	nCwOld : integer
end

local function oldConfig(node : integer, newIds : {integer : integer}, gone : {integer : boolean}) : OldConfig
	if node == nil or node < 0 then return nil end
	local cfg = comp(node, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
	if cfg == nil then return nil end
	newIds = newIds or {}
	gone = gone or {}
	local r : OldConfig = { cfg = cfg, conns = {}, cws = {}, covered = {}, old = {}, nOld = 0, cwMap = {}, nCwOld = 0 }
	r.nOld = #(cfg.laneConnections or {})
	for i = 1, r.nOld do
		local o = cfg.laneConnections[i]
		if not gone[o.segment0] and not gone[o.segment1] then
			local s0, s1 = newIds[o.segment0] or o.segment0, newIds[o.segment1] or o.segment1
			r.conns[#r.conns + 1] = { s0, o.lane0, s1, o.lane1, o.withRoad, o.withTram }
			r.old[i] = { s0, o.lane0, s1, o.lane1 }
			r.covered[s0] = true
			r.covered[s1] = true
		end
	end
	r.nCwOld = #(cfg.crosswalks or {})
	for i = 1, r.nCwOld do
		local c = cfg.crosswalks[i]
		if not gone[c] then
			r.cws[#r.cws + 1] = newIds[c] or c
			r.cwMap[i] = #r.cws
		end
	end
	return r
end

function nc.configs(edges : {Proposal.SegmentAndEntity}, removed : {integer}, have : {integer : boolean},
		seeds? : {integer : SquareStressNodeSeed}) : {Proposal.BaseNodeLaneConnectionAndEntity}, {integer}
	local add : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	local rm : {integer} = {}
	local gone : {integer : boolean} = {}
	for _, e in ipairs(removed or {}) do gone[e] = true end
	-- the added edges at each node
	local at : {integer : {integer}} = {}
	local sides : {integer : {integer : SquareStressNodeSide}} = {}
	local order : {integer} = {}
	for _, seg in ipairs(edges or {}) do
		local be = seg.comp
		for _, n in ipairs({ be.node0, be.node1 }) do
			if at[n] == nil then
				at[n] = {}
				sides[n] = {}
				order[#order + 1] = n
			end
			if sides[n][seg.entity] == nil then
				at[n][#at[n] + 1] = seg.entity
				sides[n][seg.entity] = edgeSide(be, n)
			end
		end
	end
	local map : {integer : {integer}} = nil
	local function streetMap() : {integer : {integer}}
		if map == nil then
			local ok, m = pcall(api.engine.system.streetSystem.getNode2StreetEdgeMap)
			map = (ok and m ~= nil) and m as {integer : {integer}} or {}
		end
		return map
	end
	for _, n in ipairs(order) do
		if not (have or {})[n] then
			local segs : {integer} = {}
			local ss = sides[n]
			if n >= 0 then
				-- an existing node: its remaining edges first (sorted), then the added ones
				local old : {integer} = {}
				local okM = pcall(function()
					local list = streetMap()[n]
					for i = 1, #(list or {}) do
						local e = list[i]
						if not gone[e] and ss[e] == nil then old[#old + 1] = e end
					end
				end)
				if not okM then old = {} end
				table.sort(old)
				for _, e in ipairs(old) do
					local s = edgeSide(comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge, n)
					if s ~= nil then
						segs[#segs + 1] = e
						ss[e] = s
					end
				end
			end
			for _, e in ipairs(at[n]) do
				if ss[e] ~= nil then segs[#segs + 1] = e end
			end
			local seed = seeds ~= nil and seeds[n] or nil
			local oc : OldConfig = nil
			if n >= 0 then
				oc = oldConfig(n, nil, gone)
			elseif seed ~= nil then
				oc = oldConfig(seed.node, seed.newIds, nil)
			end
			local cfg = oc ~= nil and oc.cfg or nil
			local entry = newEntry(n, cfg)
			local list : {LaneConnection} = {}
			local plain : {{integer}} = {}
			for _, c in ipairs(oc ~= nil and oc.conns or {}) do
				list[#list + 1] = newLC(c[1] as integer, c[2] as integer, c[3] as integer, c[4] as integer, c[6] == true)
				plain[#plain + 1] = { c[1] as integer, c[2] as integer, c[3] as integer, c[4] as integer }
			end
			if #segs >= 2 then
				for _, c in ipairs(nc.pattern(segs, ss, oc ~= nil and oc.covered or nil)) do
					list[#list + 1] = newLC(c[1], c[2], c[3], c[4], c[5] == 1)
					plain[#plain + 1] = { c[1], c[2], c[3], c[4] }
				end
			end
			entry.comp.laneConnections = list
			if oc ~= nil then
				-- a seed's ghost: the leg an earlier proposal removed comes back as the link's piece (town entry
				-- joins), so its connections and crosswalk get the removed leg's light states
				local carry : SquareStressLightCarry = nil
				local cws : {integer} = {}
				for _, x in ipairs(oc.cws) do cws[#cws + 1] = x end
				if seed ~= nil and seed.ghost ~= nil then
					local why : string
					carry, why = carryOf(seed.ghost, seed, cfg, oc.old, oc.nOld, at[n], plain, cws)
					seed.ghost.result = carry ~= nil and "carried" or ("unmapped (" .. tostring(why) .. ")")
				end
				entry.comp.crosswalks = cws
				-- pairs added, connections or crosswalks of removed edges dropped: the light phases (indices
				-- into both lists) are re-pointed; stale ones crash the simulation (nc.relight)
				nc.relight(entry, cfg, oc.old, oc.nOld, plain, oc.cwMap, oc.nCwOld, carry)
			end
			if oc == nil and seed ~= nil and seed.ghost ~= nil then seed.ghost.result = "unmapped (no config)" end
			add[#add + 1] = entry
			if n >= 0 and cfg ~= nil then rm[#rm + 1] = n end
		end
	end
	return add, rm
end

function nc.complete(edges : {Proposal.SegmentAndEntity}, removed : {integer}, cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity},
		cfgRm : {integer}, seeds? : {integer : SquareStressNodeSeed})
	local have : {integer : boolean} = {}
	for _, e in ipairs(cfgAdd) do have[e.entity] = true end
	local add, rm = nc.configs(edges, removed, have, seeds)
	for _, e in ipairs(add) do cfgAdd[#cfgAdd + 1] = e end
	for _, n in ipairs(rm) do cfgRm[#cfgRm + 1] = n end
end

function nc.problems(sp : any, lanesOf? : function(seg : integer) : integer) : {string}
	local p = sp as {string : any}
	local out : {string} = {}
	local edges = (p.edgesToAdd or {}) as {Proposal.SegmentAndEntity}
	local cfgAdd = (p.nodeConfigsToAdd or {}) as {Proposal.BaseNodeLaneConnectionAndEntity}
	local cfgRm = (p.nodeConfigsToRemove or {}) as {integer}
	local added : {integer : boolean} = {}
	for _, e in ipairs(cfgAdd) do
		if added[e.entity] then out[#out + 1] = string.format("node %d: two configs", e.entity) end
		added[e.entity] = true
	end
	for _, n in ipairs(cfgRm) do
		if not added[n] then out[#out + 1] = string.format("node %d: config removed without a new one", n) end
		if n < 0 then out[#out + 1] = string.format("node %d: new node in nodeConfigsToRemove", n) end
	end
	local lanes : {integer : integer} = {}
	local nodes : {integer : boolean} = {}
	for _, seg in ipairs(edges) do
		local okN, n = pcall(function() : integer return #seg.comp.laneConfigs end)
		lanes[seg.entity] = (okN and n ~= nil and n >= 3) and n or nil
		nodes[seg.comp.node0] = true
		nodes[seg.comp.node1] = true
	end
	for _, ne in ipairs((p.nodesToAdd or {}) as {Proposal.NodeAndEntity}) do nodes[ne.entity] = true end
	local sorted : {integer} = {}
	for n in pairs(nodes) do sorted[#sorted + 1] = n end
	table.sort(sorted)
	for _, n in ipairs(sorted) do
		if not added[n] then out[#out + 1] = string.format("node %d: no config", n) end
	end
	local function bound(seg : integer) : integer
		if lanes[seg] ~= nil then return lanes[seg] end
		if lanesOf ~= nil then return lanesOf(seg) end
		return nil
	end
	for _, e in ipairs(cfgAdd) do
		local conns = (e.comp ~= nil and e.comp.laneConnections or {}) as {LaneConnection}
		-- light phases index the connections, then the crosswalks: none may point past them
		pcall(function()
			local tlc = e.comp.trafficLightConfig
			if tlc == nil or tlc.states == nil then return end
			local max = #conns + #(e.comp.crosswalks or {}) - 1
			for si, st in ipairs(tlc.states) do
				for _, l in ipairs(st.lockedLanes or {}) do
					if l < 0 or l > max then
						out[#out + 1] = string.format("node %d: phase %d locks index %d past %d connections + crosswalks", e.entity, si, l, max + 1)
					end
				end
			end
		end)
		for _, c in ipairs(conns) do
			for _, pair in ipairs({ { c.segment0, c.lane0 }, { c.segment1, c.lane1 } }) do
				local b = bound(pair[1])
				if pair[2] == nil or pair[2] < 0 or (b ~= nil and pair[2] > b - 1) then
					out[#out + 1] = string.format("node %d: lane %s of segment %d out of range (%s lanes)", e.entity, tostring(pair[2]), pair[1], tostring(b))
				end
			end
		end
	end
	return out
end

return nc
