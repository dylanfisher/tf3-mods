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
--
-- The api is passed in (not read as a global) so the offline tests can hand in a fake.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"

local Write = {}

local function count(list)
	if list == nil then return 0 end
	local n = 0
	for _ in ipairs(list) do n = n + 1 end
	return n
end
Write.count = count

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

--- New instance. api: the game api (or a fake); out(kind, fields): the log function.
function Write.new(api, out)
	local W = { how = nil, dead = {}, modes = nil }

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

	--- sl_ring world over the live game, cached per world (make a new one per job / pick).
	-- Nodes also carry z (BASE_NODE.position.z) for the tool's markers.
	function W.makeWorld()
		local CT = api.type.ComponentType
		local modes = W.transportModes()
		local nodes, segs = {}, {}
		local world = {}
		function world.node(id)
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
		function world.seg(id)
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
				lanes = Ring.lanesFromConfigs(e.laneConfigs, modes) }
			segs[id] = c
			return c
		end
		return world
	end

	--- The node's current connections as plain tables (Rules.conn), in the config's order (the
	-- order is the NodeViewer edge index, double_slip_switch.tl:113-118).
	function W.currentConns(node)
		local cfg = getComp(node, api.type.ComponentType.BASE_NODE_CONFIG)
		local list = {}
		if cfg then
			for _, c in ipairs(cfg.laneConnections or {}) do
				list[#list + 1] = Rules.conn(c.segment0, c.lane0, c.segment1, c.lane1, c.withRoad == true, c.withTram == true)
			end
		end
		return list
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

	function W.buildEntry(node, conns)
		local CT = api.type.ComponentType
		if api.engine.getComponent(node, CT.BASE_NODE_CONFIG) == nil then return nil, "no_config" end
		local notes = {}
		for _, name in ipairs(ORDER) do
			if not W.dead[name] then
				-- a fresh read per try: a failed try may have left the entry half written
				local cfg = api.engine.getComponent(node, CT.BASE_NODE_CONFIG)
				local entry = api.type.BaseNodeLaneConnectionAndEntity.new()
				entry.entity = node
				entry.comp = cfg
				local ok, e = pcall(STRATEGIES[name], entry, cfg, conns)
				if ok then
					local okC, same = pcall(checkList, entry.comp.laneConnections, conns)
					if okC and same then
						if W.how ~= name then
							W.how = name
							out("HOW", { { "strategy", name }, { "tried", table.concat(notes, ";") } })
						end
						return entry, name
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

	--- Writes connection sets: items = { {node, conns}, ... } in one proposal.
	-- Nodes whose entry cannot be built are logged as SKIP <keyName>=<key> node reason.
	-- onDone(success, expect, nodesText): expect = {node = Rules.connsText(conns)} of the sent nodes.
	-- Returns the number of nodes sent (0: nothing sent, onDone is not called).
	function W.sendConfigs(keyName, key, items, onDone)
		local entries, removes, expect, nodesText = {}, {}, {}, {}
		for _, it in ipairs(items) do
			local okB, entry, info = pcall(W.buildEntry, it.node, it.conns)
			if okB and entry then
				entries[#entries + 1] = entry
				removes[#removes + 1] = it.node
				expect[it.node] = Rules.connsText(it.conns)
				nodesText[#nodesText + 1] = tostring(it.node)
			else
				out("SKIP", { { keyName, key }, { "node", it.node }, { "reason", okB and info or ("error:" .. tostring(entry)) } })
			end
		end
		if #entries == 0 then return 0 end
		local nodes = table.concat(nodesText, ",")
		send(removes, entries, function(success)
			if onDone then onDone(success, expect, nodes) end
		end)
		return #entries
	end

	--- Re-reads expect = {node = connsText}: returns same, total.
	function W.verify(expect)
		local same, total = 0, 0
		for node, text in pairs(expect) do
			total = total + 1
			if Rules.connsText(W.currentConns(node)) == text then same = same + 1 end
		end
		return same, total
	end

	return W
end

return Write
