-- square_smart_lanes: sl_lanes.script.lua wiring with a fake api (engine build event -> state job ->
-- GUI ring detection -> one node-config proposal -> our own build ignored -> verify). Field names as
-- in the tealdefs (BaseEdge, BaseNodeConfig, LaneConnection, SimpleProposal).

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local SCRIPT = here .. "../../mods/square_smart_lanes/content/smart_lanes/sl_lanes.script.lua"

local MODES = { CAR = 12, BUS = 13, TRUCK = 14, TRAM = 15, ELECTRIC_TRAM = 16 } -- deliberately not the defaults

--- Fake game over a fixture world (probe 4-lane ring by default).
local function makeGame(params, fx, opts)
	fx = fx or F.PROBE_4LANE_MEDIUM
	local world = fx.world()
	local G = { sent = {}, logs = {}, world = world }
	local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_NODE_CONFIG = "BNC" }
	-- configs: the engine default for the fixture nodes we know, empty otherwise
	G.configs = {}
	for id in pairs(world.nodes) do G.configs[id] = { laneConnections = {}, crosswalks = { 1, 2 }, trafficLightPreference = 2 } end
	for id, conns in pairs(fx.conns) do G.configs[id].laneConnections = conns end
	local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
	local ring = Ring.findRing(world, 22768)
	for _, n in ipairs(ring.nodes) do
		if #G.configs[n].laneConnections == 0 then
			G.configs[n].laneConnections = Rules.engineDefault(Ring.nodeView(world, ring, n))
		end
	end
	local function laneConfigs(lanes)
		local out = {}
		for _, l in ipairs(lanes) do
			local tm = {}
			if l.car then tm[MODES.CAR] = true end
			if l.road then tm[MODES.BUS], tm[MODES.TRUCK] = true, true end
			if l.tram then tm[MODES.TRAM] = true end
			out[#out + 1] = { forward = l.forward, transportModes = tm }
		end
		return out
	end
	-- opts.readonly models the game (2026-10-08): read LaneConnections refuse writes and, with
	-- opts.noTables, BaseNodeConfig.laneConnections only takes real LaneConnection objects
	local RO = {}
	local function lcObj(x)
		local f = { segment0 = x.segment0, lane0 = x.lane0, segment1 = x.segment1, lane1 = x.lane1,
			withRoad = x.withRoad, withTram = x.withTram }
		if not (opts and opts.readonly) then return f end
		return setmetatable({}, { __index = f, __newindex = function() error("cannot write to readonly property") end,
			__metatable = RO })
	end
	local function copyCfg(c)
		local list = {}
		for i, x in ipairs(c.laneConnections) do list[i] = lcObj(x) end
		local cfg = { laneConnections = list, crosswalks = c.crosswalks, trafficLightPreference = c.trafficLightPreference }
		if not (opts and opts.noTables) then return cfg end
		local raw = cfg
		return setmetatable({}, { __index = raw, __newindex = function(_, k, v)
			if k == "laneConnections" then
				for _, lc in ipairs(v) do
					if getmetatable(lc) ~= RO then error("expected LaneConnection") end
				end
				local copy = {}
				for i, lc in ipairs(v) do copy[i] = lcObj(lc) end
				v = copy
			end
			raw[k] = v
		end })
	end
	G.api = {
		type = {
			ComponentType = CT,
			enum = { TransportMode = MODES },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			Context = { new = function() return {} end },
		},
		engine = {
			config = { getModParams = function()
				return { square_smart_lanes = params or {}, [""] = {} }
			end },
			getComponent = function(e, ct)
				if ct == CT.BASE_NODE then
					local n = world.nodes[e]
					return n and { position = { x = n.x, y = n.y, z = 0 } }
				end
				if ct == CT.BASE_EDGE then
					local s = world.segs[e]
					return s and { node0 = s.node0, node1 = s.node1, position0 = s.p0, position1 = s.p1,
						tangent0 = s.t0, tangent1 = s.t1, laneConfigs = laneConfigs(s.lanes) }
				end
				if ct == CT.BASE_NODE_CONFIG then return G.configs[e] and copyCfg(G.configs[e]) end
			end,
			system = { streetSystem = { getNodeStreetSegments = function(n)
				local node = world.nodes[n]
				return node and node.segs or {}
			end } },
			util = { getPlayer = function() return 7 end },
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
				return { proposal = p, ctx = ctx, args = { ignore, player, dust } }
			end,
			sendCommand = function(cmd, cb)
				G.sent[#G.sent + 1] = cmd
				for _, e in ipairs(cmd.proposal.streetProposal.nodeConfigsToAdd) do G.configs[e.entity] = e.comp end
				if cb then cb(nil, true) end
			end,
		},
	}
	local env = setmetatable({
		api = G.api,
		ug_require = ug_require,
		log = { message = function(s) G.logs[#G.logs + 1] = s end },
	}, { __index = _ENV })
	local chunk = assert(loadfile(SCRIPT, "t", env))
	chunk()
	G.gs = env.data()
	local store = nil
	G.state = {
		subs = nil,
		get = function() return store end,
		set = function(_, v) store = v end,
		hasEventSubscriptions = function(self) return self.subs ~= nil end,
		subscribeToNoEvents = function(self) self.subs = {} end,
		subscribeToEvent = function(self, n) self.subs[#self.subs + 1] = n end,
	}
	function G.frames(n)
		for _ = 1, n do G.gs.guiUpdate({}, G.state, nil) end
	end
	function G.kinds(kind)
		local out = {}
		for _, l in ipairs(G.logs) do
			if l:find("[SQRL] " .. kind .. " ", 1, true) then out[#out + 1] = l end
		end
		return out
	end
	return G
end

--- onPostBuildProposal param for a build that added the ring segments and nodes.
local function ringBuild(G, opts)
	opts = opts or {}
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	if not opts.configOnly then
		for _, id in ipairs({ 22768, 23292, 23293, 23294 }) do sp.addedNodes[#sp.addedNodes + 1] = { entity = id } end
		for _, id in ipairs({ 23299, 23300, 23301, 23302 }) do
			local s = G.world.segs[id]
			sp.addedSegments[#sp.addedSegments + 1] = { entity = id, comp = { node0 = s.node0, node1 = s.node1 } }
		end
	else
		sp.nodeConfigsToAdd = { { entity = 22768 } }
		sp.nodeConfigsToRemove = { 22768 }
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, opts.player ~= false }
end

test("subscribes lazily, only to onPostBuildProposal", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	eq(G.state.subs, { "onPostBuildProposal" })
	G.gs.update({}, G.state, 0.1)
	eq(G.state.subs, { "onPostBuildProposal" })
	eq(#G.logs, 0, "quiet")
end)

test("Apply automatically Off: no subscription, nothing happens", function()
	for _, params in ipairs({ { sqrl_auto = 2 } }) do
		local G = makeGame(params)
		G.gs.update({}, G.state, 0.1)
		eq(G.state.subs, nil)
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
		eq(G.state:get(), nil)
		G.frames(30)
		eq(#G.sent, 0)
	end
end)

test("a placed 4-lane roundabout gets the rule at all four nodes in one proposal", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1) -- first GUI frame: nothing old to replay
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	eq(#G.state:get().jobs, 1)
	G.frames(2)
	eq(#G.sent, 0, "waits JOB_DELAY frames")
	G.frames(15)
	eq(#G.sent, 1)
	local cmd = G.sent[1]
	eq(cmd.args, { false, true, true })
	eq(cmd.ctx.cleanupStreetGraph, false)
	eq(cmd.ctx.player, 7)
	local sp = cmd.proposal.streetProposal
	eq(#sp.nodeConfigsToAdd, 4)
	table.sort(sp.nodeConfigsToRemove)
	eq(sp.nodeConfigsToRemove, { 22768, 23292, 23293, 23294 })
	for _, e in ipairs(sp.nodeConfigsToAdd) do
		eq(#e.comp.laneConnections, 7)
		eq(e.comp.crosswalks, { 1, 2 }, "other config fields kept")
	end
	eq(G.configs[22768].laneConnections[1].withRoad, true)
	eq(#G.kinds("APPLY"), 4)
	ok(G.kinds("APPLY")[1]:find("turbo=true", 1, true))
	ok(G.kinds("APPLY")[1]:find("before=10 after=7", 1, true))
	eq(#G.kinds("WRITE"), 1)
	ok(G.kinds("WRITE")[1]:find("success=true", 1, true))
	-- our own build is config-only: ignored, no loop
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G, { configOnly = true }))
	eq(#G.state:get().jobs, 1)
	G.frames(40)
	eq(#G.sent, 1)
	eq(#G.kinds("VERIFY"), 1)
	ok(G.kinds("VERIFY")[1]:find("same=4 nodes=4", 1, true))
	eq(#G.kinds("ERROR"), 0)
end)

test("a second identical build changes nothing (already applied: same)", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	eq(#G.sent, 1)
end)

test("non-player builds and jobs saved before the load are ignored; jobs expire from the state", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G, { player = false }))
	eq(G.state:get(), nil)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(30) -- first GUI read sees the job as old (it was in the state before this GUI session)
	eq(#G.sent, 0)
	for _ = 1, 400 do G.gs.update({}, G.state, 0.1) end
	eq(#G.state:get().jobs, 0, "state empties itself")
end)

test("read-only LaneConnections: plain tables are used, logged once as HOW", function()
	local G = makeGame(nil, nil, { readonly = true })
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	eq(#G.sent, 1)
	eq(#G.sent[1].proposal.streetProposal.nodeConfigsToAdd, 4)
	eq(#G.kinds("HOW"), 1)
	ok(G.kinds("HOW")[1]:find("strategy=table", 1, true))
	ok(G.kinds("HOW")[1]:find("ctor=", 1, true))
	eq(#G.kinds("ERROR"), 0)
end)

test("read-only and no tables: only subsets of the current connections are written, others skipped", function()
	local G = makeGame(nil, nil, { readonly = true, noTables = true })
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	-- the 4-lane turbo rule adds o2 -> x2, which the engine default lacks: no node is a subset
	eq(#G.sent, 0)
	eq(#G.kinds("SKIP"), 4)
	ok(G.kinds("SKIP")[1]:find("no_strategy:", 1, true))
	ok(G.kinds("SKIP")[1]:find("subset=", 1, true))
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Slip-lane junctions (sl_slip.lua) in the automatic pass

--- The probe ring plus a Channelized Junction T (F.channelT: nodes 1-7, segments 11-22).
local FX_CHANNEL = {
	world = function() return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.channelT()) end,
	conns = F.PROBE_4LANE_MEDIUM.conns,
}

--- onPostBuildProposal param for placing the Channelized Junction (every node and segment new).
local function channelBuild(G, withRing)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	local nodes = { 1, 2, 3, 4, 5, 6, 7 }
	local segs = { 11, 12, 13, 14, 15, 16, 21, 22 }
	if withRing then
		for _, id in ipairs({ 22768, 23292, 23293, 23294 }) do nodes[#nodes + 1] = id end
		for _, id in ipairs({ 23299, 23300, 23301, 23302 }) do segs[#segs + 1] = id end
	end
	for _, id in ipairs(nodes) do sp.addedNodes[#sp.addedNodes + 1] = { entity = id } end
	for _, id in ipairs(segs) do
		local s = G.world.segs[id]
		sp.addedSegments[#sp.addedSegments + 1] = { entity = id, comp = { node0 = s.node0, node1 = s.node1 } }
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

test("a placed Channelized Junction gets the slip rule at its three slip nodes in one proposal", function()
	local G = makeGame(nil, FX_CHANNEL)
	-- engine default stand-in: every slip node fans its lanes out (what the user saw)
	G.configs[2].laneConnections = F.parseConns("12:1>11:3:R-,12:1>11:4:R-,12:2>11:3:R-,12:2>11:4:R-,12:1>21:1:R-,12:2>21:2:R-,11:1>12:3:R-,11:2>12:4:R-")
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	local sp = G.sent[1].proposal.streetProposal
	table.sort(sp.nodeConfigsToRemove)
	eq(sp.nodeConfigsToRemove, { 2, 3, 4 })
	eq(#sp.nodeConfigsToAdd, 3)
	for _, e in ipairs(sp.nodeConfigsToAdd) do eq(e.comp.crosswalks, { 1, 2 }, "other config fields kept") end
	eq(Rules.connsText(G.configs[2].laneConnections), Rules.connsText(F.parseConns(
		"12:1>21:2:R-,12:1>21:1:R-,12:1>11:4:R-,12:2>11:3:R-,11:1>12:4:R-,11:2>12:3:R-")))
	local applies = G.kinds("APPLY")
	eq(#applies, 3)
	for _, l in ipairs(applies) do ok(l:find("kind=slip", 1, true), l) end
	ok(table.concat(applies, "\n"):find("node=2 shape=diverge case=B side=right", 1, true))
	ok(table.concat(applies, "\n"):find("node=4 shape=diverge+merge", 1, true))
	eq(#G.kinds("SKIP"), 0, "plain nodes (centre, arm ends) are not logged")
	ok(G.kinds("WRITE")[1]:find("kind=slip", 1, true))
	ok(G.kinds("WRITE")[1]:find("success=true", 1, true))
	G.frames(40)
	ok(G.kinds("VERIFY")[1]:find("kind=slip", 1, true), G.kinds("VERIFY")[1])
	ok(G.kinds("VERIFY")[1]:find("same=3 nodes=3", 1, true))
	-- the same build again: already applied, nothing sent
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(20)
	eq(#G.sent, 1)
	eq(#G.kinds("ERROR"), 0)
end)

test("rings and slip nodes in one build: a proposal per ring, one for the slip nodes", function()
	local G = makeGame(nil, FX_CHANNEL)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G, true))
	G.frames(15)
	eq(#G.sent, 2)
	eq(#G.sent[1].proposal.streetProposal.nodeConfigsToAdd, 4, "ring first")
	eq(#G.sent[2].proposal.streetProposal.nodeConfigsToAdd, 3, "then the slip nodes")
	eq(#G.kinds("ERROR"), 0)
end)

test("slip nodes the build did not touch are left alone", function()
	local G = makeGame(nil, FX_CHANNEL)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	-- a build that only added the east arm's outer segment: seeds 2 and 5
	local sp = { addedNodes = {}, addedSegments = { { entity = 12, comp = { node0 = 2, node1 = 5 } } },
		nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	G.frames(15)
	eq(#G.sent, 1)
	eq(G.sent[1].proposal.streetProposal.nodeConfigsToRemove, { 2 })
end)
