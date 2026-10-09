-- square_roundabouts_lanes_probe: lanes.script.lua wiring with a fake api (engine event -> state
-- job -> GUI scan -> write experiment -> persistence checks). Field names as in the tealdefs.

local L = ug_require "/sqrb_lanes/lanes_logic.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_lanes_probe/"
local SCRIPT = here .. "../../mods/square_roundabouts_lanes_probe/content/sqrb_lanes/lanes.script.lua"

local function conn(s0, l0, s1, l1)
	return { segment0 = s0, lane0 = l0, segment1 = s1, lane1 = l1, withRoad = true, withTram = false }
end

-- World: ring node 100 (ring in 10, ring out 11, arm 20), ring node 101 (2 ring segs only).
local function makeWorld(write)
	local W = { sent = {}, clock = 1000, logs = {} }
	local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_NODE_CONFIG = "BNC" }
	W.edges = {
		[10] = { roadTemplate = "town_new_one_way_small", node0 = 101, node1 = 100, type = 0, laneConfigs = {} },
		[11] = { roadTemplate = "town_new_one_way_small", node0 = 100, node1 = 101, type = 0, laneConfigs = {} },
		[20] = { roadTemplate = "town_new_small", node0 = 100, node1 = 200, type = 0,
			laneConfigs = { { forward = true, width = 3, offset = 0, transportModes = {} } } },
	}
	W.nodeSegs = { [100] = { 10, 11, 20 }, [101] = { 10, 11 }, [200] = { 20 } }
	W.configs = {
		[100] = { laneConnections = { conn(10, 0, 11, 0), conn(10, 1, 11, 1), conn(10, 0, 20, 1), conn(10, 1, 20, 1), conn(20, 0, 11, 0) },
			userModifiedLaneConnections = false, crosswalks = {} },
	}
	local function copyCfg(c)
		local list = {}
		for i, x in ipairs(c.laneConnections) do list[i] = x end
		return { laneConnections = list, userModifiedLaneConnections = c.userModifiedLaneConnections, crosswalks = {} }
	end
	W.api = {
		type = {
			ComponentType = CT,
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			BaseNodeLaneConnectionAndEntity = { new = function() return {} end },
			SimpleProposal = { new = function() return { streetProposal = {} } end },
			Context = { new = function() return {} end },
		},
		engine = {
			config = { getModParams = function()
				return { square_roundabouts_lanes_probe = { sqrb_lanes_write = write and 2 or 1 }, [""] = {} }
			end },
			getComponent = function(e, ct)
				if ct == CT.BASE_NODE then return { position = { x = e, y = 0, z = 0 } } end
				if ct == CT.BASE_EDGE then return W.edges[e] end
				if ct == CT.BASE_NODE_CONFIG then return W.configs[e] and copyCfg(W.configs[e]) end
			end,
			system = { streetSystem = { getNodeStreetSegments = function(n) return W.nodeSegs[n] or {} end } },
			util = {
				getPlayer = function() return 7 end,
				octree = { findEntitiesInCircle = function() return { 100, 101, 200 } end },
			},
		},
		cmd = {
			makeWorldBuildProposalCmd = function(p, ctx, ignore, player, dust)
				return { proposal = p, ctx = ctx, args = { ignore, player, dust } }
			end,
			sendCommand = function(cmd, cb)
				W.sent[#W.sent + 1] = cmd
				local e = cmd.proposal.streetProposal.nodeConfigsToAdd[1]
				W.configs[e.entity] = e.comp -- the engine applies it
				if cb then cb(nil, true) end
			end,
		},
	}
	local env = setmetatable({
		api = W.api,
		ug_require = ug_require,
		log = { message = function(s) W.logs[#W.logs + 1] = s end },
		os = { time = function() return W.clock end },
	}, { __index = _ENV })
	local chunk = assert(loadfile(SCRIPT, "t", env))
	chunk()
	W.gs = env.data()
	-- game-script state
	local store = nil
	W.state = {
		subs = nil,
		get = function() return store end,
		set = function(_, v) store = v end,
		hasEventSubscriptions = function(self) return self.subs ~= nil end,
		subscribeToNoEvents = function(self) self.subs = {} end,
		subscribeToEvent = function(self, n) self.subs[#self.subs + 1] = n end,
	}
	return W
end

local function kinds(W, kind)
	local out = {}
	for _, l in ipairs(W.logs) do
		local k, f = L.parse(l)
		if k == kind then out[#out + 1] = f end
	end
	return out
end

local function buildEvent(file)
	local t = {}
	for i = 1, 16 do t[i] = 0 end
	t[13], t[14] = 100, 0
	local proposal = { toAdd = { { fileName = file, transf = t, construction = { params = { sqrb_lanes = 2 } } } },
		toRemove = {}, proposal = { addedNodes = {}, addedSegments = {} } }
	local data = { costs = 0, toAddData = { { boundingVolume = { bbox = { min = { x = 60, y = -40 }, max = { x = 140, y = 40 } } } } } }
	return { proposal, data, {}, true }
end

test("subscribes lazily to the build events", function()
	local W = makeWorld(false)
	W.gs.update({}, W.state, 0.1)
	eq(W.state.subs, { "onPostBuildProposal", "builder.proposalApply" })
	W.gs.update({}, W.state, 0.1)
	eq(#kinds(W, "INFO"), 1)
end)

test("read-only: a placed roundabout is logged and nothing is sent", function()
	local W = makeWorld(false)
	W.gs.update({}, W.state, 0.1)
	W.gs.guiUpdate({}, W.state, nil) -- first GUI frame: nothing old to replay
	W.gs.handleEvent({}, W.state, "", "apply_command", "onPostBuildProposal",
		buildEvent("/infrastructure/street_construction/square_roundabouts.con"))
	eq(#W.state:get().jobs, 1)
	eq(kinds(W, "CON")[1].entry, "main")
	eq(kinds(W, "CON")[1].src, "bbox")
	W.gs.guiUpdate({}, W.state, nil)
	eq(#kinds(W, "SCAN"), 0, "waits JOB_DELAY")
	W.clock = W.clock + 3
	W.gs.guiUpdate({}, W.state, nil)
	local scan = kinds(W, "SCAN")[1]
	eq(scan.junctions, "1")
	eq(#kinds(W, "CONN"), 5 + 0)
	eq(#kinds(W, "SEG") >= 3, true)
	eq(#W.sent, 0)
	eq(#kinds(W, "ERROR"), 0)
	-- the job is not replayed
	W.clock = W.clock + 10
	W.gs.guiUpdate({}, W.state, nil)
	eq(#kinds(W, "SCAN"), 1)
end)

test("non-player builds and foreign constructions make no job", function()
	local W = makeWorld(false)
	local ev = buildEvent("/infrastructure/street_construction/square_roundabouts.con")
	ev[4] = false
	W.gs.handleEvent({}, W.state, "", "apply_command", "onPostBuildProposal", ev)
	eq(W.state:get(), nil)
	W.gs.handleEvent({}, W.state, "", "apply_command", "onPostBuildProposal", buildEvent("station/x.con"))
	eq(#W.state:get().jobs, 0)
end)

test("write experiment: sends one node config and checks it persists", function()
	local W = makeWorld(true)
	W.gs.update({}, W.state, 0.1)
	W.gs.guiUpdate({}, W.state, nil)
	W.gs.handleEvent({}, W.state, "", "apply_command", "onPostBuildProposal",
		buildEvent("/infrastructure/street_construction/square_roundabouts.con"))
	W.gs.guiUpdate({}, W.state, nil) -- sees the job, scans JOB_DELAY s later
	W.clock = W.clock + 3
	W.gs.guiUpdate({}, W.state, nil)
	eq(#W.sent, 1)
	local cmd = W.sent[1]
	eq(cmd.proposal.streetProposal.nodeConfigsToRemove, { 100 })
	eq(cmd.ctx.cleanupStreetGraph, false)
	eq(cmd.ctx.player, 7)
	eq(cmd.args, { false, true, true })
	local w = kinds(W, "WRITE")[1]
	eq(w.lane0, "1")
	eq(w.removedConns, "10:1>20:1:R-")
	eq(w.mode, "set_true")
	eq(W.configs[100].userModifiedLaneConnections, true)
	eq(kinds(W, "WRITE_RESULT")[1].success, "true")
	-- time-based re-reads
	W.clock = W.clock + 2
	W.gs.guiUpdate({}, W.state, nil)
	local p = kinds(W, "PERSIST")
	eq(#p, 1)
	eq(p[1].same, "true")
	-- the engine regenerates the connections; a later build triggers a re-read
	W.configs[100].laneConnections[#W.configs[100].laneConnections + 1] = conn(10, 1, 20, 1)
	W.gs.handleEvent({}, W.state, "", "apply_command", "onPostBuildProposal", buildEvent("station/x.con"))
	W.gs.guiUpdate({}, W.state, nil)
	p = kinds(W, "PERSIST")
	eq(p[#p].same, "false")
	ok(p[#p].reason:find("build", 1, true))
	eq(#kinds(W, "ERROR"), 0)
end)

test("node configs in a build (e.g. the Crossing Tool) are logged", function()
	local W = makeWorld(false)
	local ev = buildEvent("station/x.con")
	ev[1].toAdd = {}
	ev[1].proposal.nodeConfigsToRemove = { 100 }
	ev[1].proposal.nodeConfigsToAdd = { { entity = 100, comp = { laneConnections = { conn(10, 0, 11, 0) }, userModifiedLaneConnections = true } } }
	W.gs.handleEvent({}, W.state, "", "apply_command", "onPostBuildProposal", ev)
	eq(kinds(W, "NCFG")[1].userModLanes, "true")
	eq(kinds(W, "NCFG_CONN")[1].s0, "10")
	eq(kinds(W, "BUILD")[1].ncfgAdd, "1")
end)

test("fallback job when a build adds ring streets but no known construction", function()
	local W = makeWorld(false)
	local ev = buildEvent("station/x.con")
	local sp = ev[1].proposal
	for i = 1, 4 do
		sp.addedSegments[i] = { entity = -i, type = 0, comp = { roadTemplate = "town_new_one_way_small", node0 = -10 - i, node1 = -11 - i } }
		sp.addedNodes[i] = { entity = -10 - i, comp = { position = { x = 80 + 10 * i, y = 0, z = 0 } } }
	end
	W.gs.handleEvent({}, W.state, "", "apply_command", "onPostBuildProposal", ev)
	eq(W.state:get().jobs[1].entry, "streets")
	eq(kinds(W, "JOB")[1].ringSegs, "4")
end)
