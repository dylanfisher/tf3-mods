-- square_smart_lanes: sl_lanes.script.lua wiring with a fake api (engine build event -> state job ->
-- GUI ring detection -> one node-config proposal -> our own build ignored -> verify). Field names as
-- in the tealdefs (BaseEdge, BaseNodeConfig, LaneConnection, SimpleProposal).

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

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

test("subscribes lazily, to the zones, kept and auto events and onPostBuildProposal, once per load", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	eq(G.state.subs, { "SmartLanes.zones", "SmartLanes.kept", "SmartLanes.auto", "onPostBuildProposal", "SmartLanes.qlen" })
	G.state.subs[#G.state.subs + 1] = "marker"
	G.gs.update({}, G.state, 0.1)
	eq(G.state.subs, { "SmartLanes.zones", "SmartLanes.kept", "SmartLanes.auto", "onPostBuildProposal", "SmartLanes.qlen", "marker" }, "not again in the same load")
	eq(#G.logs, 0, "quiet")
end)

test("Apply automatically Off: the zones, kept and auto events and the build event (for the new-lights look), builds do nothing", function()
	for _, params in ipairs({ { sqrl_auto = 2 } }) do
		local G = makeGame(params)
		G.gs.update({}, G.state, 0.1)
		-- onPostBuildProposal too (2026-10-16): the new-lights look runs whatever Apply automatically says
		eq(G.state.subs, { "SmartLanes.zones", "SmartLanes.kept", "SmartLanes.auto", "onPostBuildProposal" })
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
	eq(#G.kinds("VERIFY"), 2, "lanes + lights")
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

test("GUI poll: the state copied (state:get) only when its change stamp moved; the engine sweep reads it every JOB_SWEEP updates", function()
	local G = makeGame()
	local get = G.state.get
	local gets = 0
	G.state.get = function(self)
		gets = gets + 1
		return get(self)
	end
	-- the GAME_SCRIPT component the stamp is read from (state_native:find over the same state)
	G.api.type.ComponentType.GAME_SCRIPT = "GS"
	G.api.engine.system.gameScriptSystem = { getEntityForGameScript = function() return 77 end }
	local gc = G.api.engine.getComponent
	G.api.engine.getComponent = function(e, c)
		if c == "GS" then
			return { state_native = { find = function(_, k)
				local s = get(G.state)
				return type(s) == "table" and s[k] or nil
			end } }
		end
		return gc(e, c)
	end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	gets = 0
	G.frames(100)
	ok(gets <= 1, "nothing changed: at most the first poll copies (" .. gets .. ")")
	-- a build: its job is seen at the next poll
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	gets = 0
	G.frames(20)
	eq(#G.sent, 1)
	ok(gets >= 1 and gets <= 2, tostring(gets))
	-- the engine's sweep: one read every JOB_SWEEP (100) updates; the job gone after JOB_TTL (300)
	gets = 0
	for _ = 1, 400 do G.gs.update({}, G.state, 0.1) end
	eq(gets, 4)
	eq(#get(G.state).jobs, 0)
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
	eq(sp.nodeConfigsToRemove, { 1, 2, 3, 4 }, "the slip nodes and the centre T (crossing rule)")
	eq(#sp.nodeConfigsToAdd, 4)
	for _, e in ipairs(sp.nodeConfigsToAdd) do eq(e.comp.crosswalks, { 1, 2 }, "other config fields kept") end
	eq(Rules.connsText(G.configs[2].laneConnections), Rules.connsText(F.parseConns(
		"12:1>21:2:R-,12:1>21:1:R-,12:1>11:4:R-,12:2>11:3:R-,11:1>12:4:R-,11:2>12:3:R-")))
	local applies = G.kinds("APPLY")
	eq(#applies, 4)
	for _, l in ipairs(applies) do ok(l:find("kind=slip", 1, true), l) end
	ok(table.concat(applies, "\n"):find("node=2 shape=diverge case=B side=right", 1, true))
	ok(table.concat(applies, "\n"):find("node=4 shape=diverge+merge", 1, true))
	eq(#G.kinds("SKIP"), 0, "plain nodes (centre, arm ends) are not logged")
	ok(G.kinds("WRITE")[1]:find("kind=slip", 1, true))
	ok(G.kinds("WRITE")[1]:find("success=true", 1, true))
	G.frames(40)
	ok(G.kinds("VERIFY")[1]:find("kind=slip", 1, true), G.kinds("VERIFY")[1])
	ok(G.kinds("VERIFY")[1]:find("same=4 nodes=4", 1, true))
	-- the same build again: already applied, nothing sent
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(20)
	eq(#G.sent, 1)
	eq(#G.kinds("ERROR"), 0)
end)

test("lights: slip nodes of a timed-out proposal are not relit (lightsKept); a late callback sends none either", function()
	local function run(lose)
		local G = makeGame(nil, FX_CHANNEL)
		G.configs[2].laneConnections = F.parseConns("12:1>11:3:R-,12:1>11:4:R-,12:2>11:3:R-,12:2>11:4:R-,12:1>21:1:R-,12:2>21:2:R-,11:1>12:3:R-,11:2>12:4:R-")
		for n = 1, 4 do G.lights[n] = true end
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		G.lose = lose and function() return true end or nil
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
		G.frames(15)
		return G
	end
	-- control: the slip nodes (not the centre crossing: it keeps its lights) get lights off
	local C = run(false)
	C.frames(20)
	ok(C.lightCmds ~= nil and #C.lightCmds >= 1, "slip nodes lose their lights")
	for _, c in ipairs(C.lightCmds) do eq(c.pref, C.TLP.NO) end
	-- the slip proposal never answers: after the timeout no node of it gets a light proposal
	local G = run(true)
	eq(#G.sent, 1)
	eq(#G.lost, 1)
	G.frames(650)
	eq(#G.kinds("TIMEOUT"), 1)
	ok(G.kinds("WRITE")[1]:find(" timeout=4", 1, true), G.kinds("WRITE")[1])
	eq(G.lightCmds, nil, "timed-out nodes not relit")
	eq(#G.kinds("VERIFY"), 0, "nothing landed: no verify")
	G.lost[1]()
	G.frames(60)
	eq(#G.kinds("LATE"), 1)
	eq(G.lightCmds, nil, "late callback: still no light proposal")
	eq(#G.kinds("ERROR"), 0)
end)

--- Two phases on the Channelized Junction's centre T (node 1) over its engine-default-like
-- connections: phase 1 locks everything from segment 15 (the side road) plus crosswalk 2, phase 2
-- everything from 11 and 13.
local function phasedCentre(G)
	local conns = {}
	local segs = { 11, 13, 15 }
	for _, a in ipairs(segs) do
		for _, b in ipairs(segs) do
			if a ~= b then
				for l = 1, 2 do conns[#conns + 1] = Rules.conn(a, l, b, l + 2, true, false) end
			end
		end
	end
	G.configs[1].laneConnections = conns
	local p1, p2 = {}, {}
	for i, c in ipairs(conns) do
		if c.segment0 == 15 then p1[#p1 + 1] = i - 1 else p2[#p2 + 1] = i - 1 end
	end
	p1[#p1 + 1] = #conns + 1 -- crosswalk 2 (0-based 1)
	G.configs[1].trafficLightConfig = G.tlc({ { lockedLanes = p1, duration = 20 }, { lockedLanes = p2, duration = 30 } })
	return conns
end

test("traffic light phases are re-pointed to the new connections (in-game crash 2026-10-11)", function()
	local G = makeGame(nil, FX_CHANNEL)
	local old = phasedCentre(G)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(15)
	local cfg = G.configs[1]
	local conns = cfg.laneConnections
	ok(#conns ~= #old, "the crossing rule changed the connection count")
	local states = cfg.trafficLightConfig.states
	eq(#states, 2, "same phases")
	eq(states[1].duration, 20)
	eq(states[2].duration, 30)
	local max = #conns + #cfg.crosswalks - 1
	for k, st in ipairs(states) do
		for _, l in ipairs(st.lockedLanes) do ok(l >= 0 and l <= max, "phase " .. k .. " index " .. l .. " in range") end
	end
	-- phase 1: every connection from the side road locked, nothing else; crosswalk 2 moved along
	local set1 = {}
	for _, l in ipairs(states[1].lockedLanes) do set1[l] = true end
	for i, c in ipairs(conns) do eq(set1[i - 1] == true, c.segment0 == 15, "phase 1 conn " .. Rules.connsText({ c })) end
	ok(set1[#conns + 1], "crosswalk 2 locked at its new index")
	ok(not set1[#conns], "crosswalk 1 not locked")
	eq(#G.kinds("ERROR"), 0)
end)

test("a node whose phases cannot be re-pointed is not written", function()
	local G = makeGame(nil, FX_CHANNEL, { noLightState = true })
	local old = phasedCentre(G)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(15)
	eq(Rules.connsText(G.configs[1].laneConnections), Rules.connsText(old), "centre untouched")
	local skips = table.concat(G.kinds("SKIP"), "\n")
	ok(skips:find("node=1 reason=lights:", 1, true), skips)
	eq(#G.sent, 1, "the slip nodes (no phases) still written")
end)

test("rings and slip nodes in one build: a proposal per ring, one for the slip nodes", function()
	local G = makeGame(nil, FX_CHANNEL)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G, true))
	G.frames(15)
	eq(#G.sent, 2)
	eq(#G.sent[1].proposal.streetProposal.nodeConfigsToAdd, 4, "ring first")
	eq(#G.sent[2].proposal.streetProposal.nodeConfigsToAdd, 4, "then the slip nodes and the centre T")
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

---------------------------------------------------------------------------
-- Traffic lights ("No lights at roundabouts and ramps", sl_lights.lua)

test("lights: the ring's arm junctions get no lights after the lane write, verified", function()
	local G = makeGame()
	G.lights[22768] = true
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(17)
	eq(#G.sent, 1, "one lane proposal")
	ok(G.lightCmds ~= nil and #G.lightCmds == 4, "one light command per arm junction")
	for _, c in ipairs(G.lightCmds) do
		eq(c.pref, G.TLP.NO)
		eq(c.args, { false, true }, "as the base node window")
	end
	eq(G.configs[22768].trafficLightPreference, G.TLP.NO)
	eq(G.lights[22768], nil)
	eq(#G.kinds("LIGHTS"), 4)
	ok(G.kinds("LIGHTS")[1]:find("before=auto", 1, true))
	G.frames(40)
	local v = {}
	for _, l in ipairs(G.kinds("VERIFY")) do if l:find("kind=lights", 1, true) then v[#v + 1] = l end end
	eq(#v, 1)
	ok(v[1]:find("off=4 nodes=4 gone=0", 1, true), v[1])
end)

test("lights: nodes already without lights are not sent again", function()
	local G = makeGame()
	for id in pairs(G.configs) do G.configs[id].trafficLightPreference = G.TLP.NO end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(60)
	eq(G.lightCmds, nil)
	eq(#G.kinds("LIGHTS"), 0)
end)

test("lights: setting Off leaves the game's choice", function()
	local G = makeGame({ sqrl_lights = 2 })
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(60)
	eq(#G.sent, 1, "lanes still written")
	eq(G.lightCmds, nil)
end)

test("lights: a light build (no segments) never starts a job", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal",
		{ { proposal = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = { { entity = 22768 } } }, toAdd = {} }, {}, {}, true })
	eq(G.state:get(), nil)
end)

---------------------------------------------------------------------------
-- Free kerb turn at traffic lights (setting sqrl_free_turn, sl_lights.lua L.kerbPhases)

local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local LightsM = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"

-- "Free kerb turn at traffic lights": 1 Off, 2 When safe, 3 Always (default)
local OFF, SAFE, ALWAYS = { sqrl_free_turn = 1 }, { sqrl_free_turn = 2 }, { sqrl_free_turn = 3 }

--- The probe ring plus a plain 3x3 crossroads far away: node 901, 911 west, 912 east (main road),
-- 913 north, 914 south (side road); 902-905 dead ends.
local FX_CROSS = {
	world = function()
		return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.build(
			{ [901] = { 0, -800 }, [902] = { -60, -800 }, [903] = { 60, -800 }, [904] = { 0, -740 }, [905] = { 0, -860 } },
			{ [911] = { 901, 902, F.TPL.large }, [912] = { 901, 903, F.TPL.large }, [913] = { 901, 904, F.TPL.large },
				[914] = { 901, 905, F.TPL.large } }))
	end,
	conns = F.PROBE_4LANE_MEDIUM.conns,
}

local function crossBuild(G)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, id in ipairs({ 901, 902, 903, 904, 905 }) do sp.addedNodes[#sp.addedNodes + 1] = { entity = id } end
	for _, id in ipairs({ 911, 912, 913, 914 }) do
		local sg = G.world.segs[id]
		sp.addedSegments[#sp.addedSegments + 1] = { entity = id, comp = { node0 = sg.node0, node1 = sg.node1 } }
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

--- The game's style of phases for `conns` (findings.md: the kerb turn red with its approach): phase 1
-- the main road goes (the side road red, crosswalk 1 red), phase 2 the side road (main road red,
-- crosswalk 2 red); crosswalks follow the connections (2 per makeGame config).
local function gamePhases(conns)
	local p1, p2 = {}, {}
	for i, c in ipairs(conns) do
		if c.segment0 == 913 or c.segment0 == 914 then p1[#p1 + 1] = i - 1 else p2[#p2 + 1] = i - 1 end
	end
	p1[#p1 + 1] = #conns
	p2[#p2 + 1] = #conns + 1
	return { { lockedLanes = p1, duration = 20, minDuration = 5, canSkip = false },
		{ lockedLanes = p2, duration = 30, minDuration = 6, canSkip = true } }
end

--- A crossroads game: lanes = "default" (the game's model) or "rule" (already Smart Lanes'),
-- lit: a light stands (AUTO), phases: the game's phases for those lanes.
local function crossGame(params, lanes, lit, phases)
	local G = makeGame(params, FX_CROSS)
	local v = Slip.classify(G.world, 901)
	assert(v.case == "X")
	G.kerb = Cross.kerbPairs(v)
	local conns = lanes == "rule" and Slip.plan(G.world, 901, function() return {} end).conns or Slip.defaultConns(v)
	G.configs[901].laneConnections = conns
	G.configs[901].trafficLightPreference = G.TLP.AUTO
	G.lights[901] = lit or nil
	if phases then G.configs[901].trafficLightConfig = G.tlc(gamePhases(conns)) end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	return G
end

--- Kerb connections of node 901 red in some phase, and the phases' index range check.
local function kerbRed(G)
	local cfg = G.configs[901]
	local conns = cfg.laneConnections
	local isKerb = {}
	for _, j in ipairs(LightsM.kerbIndices(conns, G.kerb)) do isKerb[j] = true end
	local red, max = 0, #conns + #cfg.crosswalks - 1
	for _, st in ipairs(cfg.trafficLightConfig and cfg.trafficLightConfig.states or {}) do
		for _, l in ipairs(st.lockedLanes) do
			ok(type(l) == "number" and l >= 0 and l <= max, "index " .. tostring(l) .. " in range 0.." .. max)
			if isKerb[l] then red = red + 1 end
		end
	end
	return red, isKerb
end

test("free turn: a lit crossroads gets its kerb turns out of every phase in the lane write itself", function()
	for _, params in ipairs({ ALWAYS, {} }) do -- {}: the default (Always)
		local G = crossGame(params, "default", true, true)
		local old = G.configs[901].laneConnections
		local oldStates = G.configs[901].trafficLightConfig.states
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
		G.frames(15)
		eq(#G.sent, 1, "one proposal")
		eq(G.sent[1].proposal.streetProposal.nodeConfigsToRemove, { 901 })
		eq(G.lightCmds, nil, "no second proposal on the node")
		local cfg = G.configs[901]
		local conns = cfg.laneConnections
		ok(Rules.connsText(conns) ~= Rules.connsText(old), "the crossing rule rewrote the lanes")
		local states = cfg.trafficLightConfig.states
		eq(#states, 2, "same phases")
		eq({ states[1].duration, states[1].minDuration, states[1].canSkip }, { 20, 5, false })
		eq({ states[2].duration, states[2].minDuration, states[2].canSkip }, { 30, 6, true })
		local red, isKerb = kerbRed(G)
		eq(red, 0, "no kerb turn red in any phase")
		local nKerb = 0
		for _ in pairs(isKerb) do nKerb = nKerb + 1 end
		eq(nKerb, 4, "a 3x3 crossroads: one kerb turn connection per approach (its kerb lane turns only)")
		-- every other index is the plain re-pointing (crosswalks included)
		for s, st in ipairs(states) do
			local want = {}
			for _, l in ipairs(Rules.remapLocked(old, conns, 2, oldStates[s].lockedLanes)) do
				if not isKerb[l] then want[#want + 1] = l end
			end
			eq(st.lockedLanes, want, "phase " .. s)
		end
		local sum = G.kinds("SUMMARY")[1]
		ok(sum:find("cross=1 ", 1, true) and sum:find(" free_turn=4", 1, true), sum)
		-- lit at the read: nothing to re-check
		G.frames(700)
		eq(#G.kinds("RECHECK"), 0)
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("free turn: a connection new to the node takes its approach's red although the kerb turn was freed", function()
	local G = crossGame(ALWAYS, "rule", true, false)
	local v = Slip.classify(G.world, 901)
	local far = {}
	for _, ap in ipairs(v.approaches) do
		if ap.seg == 913 then
			for _, ex in ipairs(ap.exits) do
				if ex.cat == "far" then far[ex.seg] = true end
			end
		end
	end
	ok(next(far) ~= nil, "the side road has a far turn")
	-- the node lacks the side road's far turn, and its kerb turns were freed earlier
	local conns = {}
	for _, c in ipairs(G.configs[901].laneConnections) do
		if not (c.segment0 == 913 and far[c.segment1]) then conns[#conns + 1] = c end
	end
	G.configs[901].laneConnections = conns
	local lists = {}
	for i, st in ipairs(gamePhases(conns)) do lists[i] = st.lockedLanes end
	local freed = LightsM.kerbPhases(conns, LightsM.kerbIndices(conns, G.kerb), 2, lists, LightsM.FREE)
	local states = gamePhases(conns)
	for i, st in ipairs(states) do st.lockedLanes = freed[i] end
	G.configs[901].trafficLightConfig = G.tlc(states)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "the far turn is added: a lane write")
	local cfg = G.configs[901]
	local red = {}
	for _, l in ipairs(cfg.trafficLightConfig.states[1].lockedLanes) do red[l] = true end
	local n = 0
	for i, c in ipairs(cfg.laneConnections) do
		if c.segment0 == 913 and far[c.segment1] then
			n = n + 1
			ok(red[i - 1], "the new far turn is red while its approach is red (phase 1)")
		end
	end
	ok(n > 0, "far turn written")
	eq(kerbRed(G), 0, "kerb turns free again")
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn: setting Off re-points the phases only (kerb turns keep their red)", function()
	local G = crossGame(OFF, "default", true, true)
	local old = G.configs[901].laneConnections
	local oldStates = G.configs[901].trafficLightConfig.states
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	local conns = G.configs[901].laneConnections
	for s, st in ipairs(G.configs[901].trafficLightConfig.states) do
		eq(st.lockedLanes, Rules.remapLocked(old, conns, 2, oldStates[s].lockedLanes), "phase " .. s .. " unchanged")
	end
	ok(kerbRed(G) > 0, "kerb turns still red with their approach")
	ok(G.kinds("SUMMARY")[1]:find(" free_turn=off", 1, true), G.kinds("SUMMARY")[1])
	G.frames(700)
	eq(#G.kinds("RECHECK"), 0)
	eq(G.lightCmds, nil)
end)

test("free turn: lanes already right: a phases-only light proposal, preference kept; again: nothing sent", function()
	local G = crossGame(ALWAYS, "rule", true, true)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 0, "no lane write")
	eq(#G.lightCmds, 1)
	eq(G.lightCmds[1].node, 901)
	eq(G.lightCmds[1].pref, G.TLP.AUTO, "the node's preference, unchanged")
	eq(kerbRed(G), 0)
	eq(#G.configs[901].trafficLightConfig.states, 2)
	local l = G.kinds("LIGHTS")[1]
	ok(l:find("src=auto node=901 to=free_turn free_turn=4 states=2 pref=auto", 1, true), l)
	ok(G.kinds("SUMMARY")[1]:find("same=1 ", 1, true) and G.kinds("SUMMARY")[1]:find(" free_turn=4", 1, true))
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.lightCmds, 1, "already free: nothing sent")
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn: phases-only path refuses stale phases and unlit nodes", function()
	local G = crossGame(ALWAYS, "rule", true, true)
	local st = G.configs[901].trafficLightConfig.states
	st[1].lockedLanes[#st[1].lockedLanes + 1] = 999 -- past the list: stale
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(G.lightCmds, nil, "stale phases: nothing sent")
	local G2 = crossGame(ALWAYS, "rule", false, true) -- phases but no light standing
	G2.gs.handleEvent({}, G2.state, "", "apply_command", "onPostBuildProposal", crossBuild(G2))
	G2.frames(15)
	eq(G2.lightCmds, nil, "no light: no light proposal")
	eq(#G.kinds("ERROR") + #G2.kinds("ERROR"), 0)
end)

test("free turn: unknown lights at the read: lights and phases the game adds later are freed by the re-check", function()
	local G = crossGame(ALWAYS, "default", false, false) -- AUTO, no light, no phases yet
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	ok(G.kinds("SUMMARY")[1]:find(" free_turn=0", 1, true), G.kinds("SUMMARY")[1])
	-- the game puts its light and default phases on the junction (our lanes)
	G.lights[901] = true
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
	ok(kerbRed(G) > 0)
	G.frames(60)
	local r = G.kinds("RECHECK")
	eq(#r, 1)
	ok(r[1]:find("kind=free_turn job=1 nodes=1 phases=1 locked=1 sent=1 changed=0", 1, true), r[1])
	eq(#G.lightCmds, 1)
	eq(kerbRed(G), 0, "freed")
	ok(G.kinds("LIGHTS")[1]:find("src=recheck node=901 to=free_turn free_turn=4", 1, true), G.kinds("LIGHTS")[1])
	G.frames(600)
	r = G.kinds("RECHECK")
	eq(#r, 2)
	ok(r[2]:find("phases=1 locked=0 sent=0", 1, true), r[2])
	eq(#G.lightCmds, 1)
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn: the re-check never sends for a node a newer write has not landed on yet", function()
	local G = crossGame(ALWAYS, "default", false, false)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	-- lights come; the player builds there again and that write is still on its way at the re-check
	G.lights[901] = true
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
	G.configs[901].laneConnections = Slip.defaultConns(Slip.classify(G.world, 901))
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
	G.defer = true
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(65)
	eq(#G.sent, 2, "the second job's lane write went out (not landed)")
	local r = G.kinds("RECHECK")
	eq(#r, 1)
	ok(r[1]:find("locked=0 sent=0 changed=1", 1, true), r[1])
	eq(G.lightCmds, nil, "no light proposal on a node with a write in flight")
	G.defer = false
	G.flush()
	eq(kerbRed(G), 0, "the second write freed the kerb turns itself")
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn: the re-check leaves a junction whose lanes changed since alone", function()
	local G = crossGame(ALWAYS, "default", false, false)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	-- the player edits the lanes; lights come
	G.configs[901].laneConnections = F.parseConns("911:1>912:3:R-,912:1>911:3:R-")
	G.lights[901] = true
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
	G.frames(60)
	ok(G.kinds("RECHECK")[1]:find("locked=0 sent=0 changed=1", 1, true), G.kinds("RECHECK")[1])
	eq(G.lightCmds, nil)
end)

test("bus lanes: the automatic pass sets a lit crossroads' car lanes, keeps the bus connections and their signal", function()
	local G = makeGame(ALWAYS, FX_CROSS)
	-- the main road with 2 car lanes and a kerb bus lane per direction (from 901 out: bus in 1, car in 2-3,
	-- car out 4-5, bus out 6)
	for _, sid in ipairs({ 911, 912 }) do G.world.segs[sid].lanes = F.lanes("BS BU BV BV FV FV FU FS") end
	local v = Slip.classify(G.world, 901)
	assert(v.case == "X" and v.bus ~= nil)
	G.kerb = Cross.kerbPairs(v)
	-- the game's lanes, its bus lanes straight on, and the player's bus right turns (911 -> 914 and
	-- 912 -> 913: kerb movements)
	local bus = F.parseConns("911:1>912:6:R-,912:1>911:6:R-,911:1>914:3:R-,912:1>913:3:R-")
	local conns = Slip.defaultConns(v)
	for _, c in ipairs(bus) do conns[#conns + 1] = c end
	G.configs[901].laneConnections = conns
	G.configs[901].trafficLightPreference = G.TLP.AUTO
	G.lights[901] = true
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(conns))
	-- the bus turns' red phases in the game's phases
	local function redOf(list, states)
		local out = {}
		for i, c in ipairs(list) do
			if c.lane0 == 1 and (c.segment0 == 911 or c.segment0 == 912) then
				local k = Rules.connsText({ c })
				out[k] = {}
				for p, st in ipairs(states) do
					for _, l in ipairs(st.lockedLanes) do if l == i - 1 then out[k][#out[k] + 1] = p end end
				end
			end
		end
		return out
	end
	local before = redOf(conns, G.configs[901].trafficLightConfig.states)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	local cfg = G.configs[901]
	local kept = {}
	for _, c in ipairs(cfg.laneConnections) do
		if Rules.touchesBus(c, v.bus) then kept[#kept + 1] = c end
	end
	eq(Rules.connsText(kept), Rules.connsText(bus), "bus connections kept exactly")
	eq(redOf(cfg.laneConnections, cfg.trafficLightConfig.states), before, "bus turns keep their phases (no free kerb turn)")
	ok(LightsM.kerbIndices(cfg.laneConnections, G.kerb)[1] ~= nil, "car kerb turns there")
	-- the side roads' car kerb turns (3-lane roads: the kerb lane turns only) are freed (Always); the main
	-- road's (2 car lanes: its kerb car lane goes straight too) stay red with their lane (Lights.sharedKerb)
	local _, isKerb = kerbRed(G)
	local redBy = {}
	for _, st in ipairs(cfg.trafficLightConfig.states) do
		for _, l in ipairs(st.lockedLanes) do
			if isKerb[l] then
				local a = cfg.laneConnections[l + 1].segment0
				redBy[a] = (redBy[a] or 0) + 1
			end
		end
	end
	eq(redBy, { [911] = 1, [912] = 1 }, "side kerb turns freed, main road's shared-lane ones red in the side road's phase")
	G.frames(40)
	ok(G.kinds("VERIFY")[1]:find("same=1 nodes=1", 1, true), G.kinds("VERIFY")[1])
	-- the player adds a bus connection; the same build again: already applied, nothing sent
	table.insert(cfg.laneConnections, Rules.conn(911, 1, 913, 3, true, false))
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(20)
	eq(#G.sent, 1, "a player's bus connection: still smart lanes")
	eq(#G.kinds("ERROR"), 0)
end)

--- One phase per approach at 901 (only that approach's connections green), both crosswalks red.
local function approachPhases(conns)
	local out = {}
	for s, a in ipairs({ 911, 912, 913, 914 }) do
		local list = {}
		for i, c in ipairs(conns) do
			if c.segment0 ~= a then list[#list + 1] = i - 1 end
		end
		list[#list + 1] = #conns
		list[#list + 1] = #conns + 1
		out[s] = { lockedLanes = list, duration = 10 + s, minDuration = 5, canSkip = false }
	end
	return out
end

--- The phases (sorted lists) where kerb connection j is red, per kerb pair "a>b".
local function kerbRedPhases(G)
	local cfg = G.configs[901]
	local conns = cfg.laneConnections
	local out = {}
	for _, j in ipairs(LightsM.kerbIndices(conns, G.kerb)) do
		local c = conns[j + 1]
		local k = c.segment0 .. ">" .. c.segment1
		out[k] = out[k] or {}
		for s, st in ipairs(cfg.trafficLightConfig.states) do
			for _, l in ipairs(st.lockedLanes) do
				if l == j then out[k][#out[k] + 1] = s end
			end
		end
	end
	return out
end

test("free turn When safe: one phase per approach: freed everywhere, also merging under the green straight into its lane", function()
	for _, params in ipairs({ SAFE }) do
		local G = crossGame(params, "default", true, false)
		G.configs[901].trafficLightConfig = G.tlc(approachPhases(G.configs[901].laneConnections))
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
		G.frames(15)
		eq(#G.sent, 1, "one proposal (lanes and phases)")
		eq(G.lightCmds, nil, "no second proposal on the node")
		local cfg = G.configs[901]
		local states = cfg.trafficLightConfig.states
		eq(#states, 4, "no phase added or removed")
		eq({ states[2].duration, states[2].minDuration }, { 12, 5 })
		-- phase s = approach 910 + s green; each kerb turn A>E (3-lane roads: a dedicated kerb lane) goes in
		-- every phase: nothing crosses it, every crosswalk is red. The green straights end in E's other lanes
		-- (the kerb lane is the turn's), so no merge here (merges: test_lights.lua)
		local red = kerbRedPhases(G)
		local n = 0
		for k, phases in pairs(red) do
			n = n + 1
			eq(phases, {}, "kerb " .. k .. ": green in every phase")
		end
		eq(n, 4)
		-- crosswalks stay red everywhere; indices in range
		for _, st in ipairs(states) do
			local set = {}
			for _, l in ipairs(st.lockedLanes) do
				set[l] = true
				ok(l >= 0 and l <= #cfg.laneConnections + 1)
			end
			ok(set[#cfg.laneConnections] and set[#cfg.laneConnections + 1], "crosswalks red")
		end
		local sum = G.kinds("SUMMARY")[1]
		ok(sum:find(" free_turn=4 free_phases=12 kept=- merge_free=0 shared_held=0", 1, true), sum)
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("free turn When safe: the game's two phases at a 3x3 crossroads: the crosswalks (not the node's roads: conservative) keep every kerb turn red", function()
	local G = crossGame(SAFE, "default", true, true)
	local old = G.configs[901].laneConnections
	local oldStates = G.configs[901].trafficLightConfig.states
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	local conns = G.configs[901].laneConnections
	for s, st in ipairs(G.configs[901].trafficLightConfig.states) do
		eq(st.lockedLanes, Rules.remapLocked(old, conns, 2, oldStates[s].lockedLanes), "phase " .. s .. ": the plain re-pointing")
	end
	ok(G.kinds("SUMMARY")[1]:find(" free_turn=0 free_phases=0 kept=ped:4 merge_free=0", 1, true), G.kinds("SUMMARY")[1])
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn When safe: a green crosswalk keeps the kerb turns red (crosswalk entities not the node's roads: conservative)", function()
	local G = crossGame(SAFE, "default", true, false)
	local states = approachPhases(G.configs[901].laneConnections)
	-- crosswalk 1 green in every phase
	for _, st in ipairs(states) do table.remove(st.lockedLanes, #st.lockedLanes - 1) end
	G.configs[901].trafficLightConfig = G.tlc(states)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	for k, phases in pairs(kerbRedPhases(G)) do eq(#phases, 3, k .. ": red wherever its approach is") end
	local sum = G.kinds("SUMMARY")[1]
	ok(sum:find(" free_turn=0 free_phases=0 kept=ped:12 merge_free=0", 1, true), sum)
	-- the crosswalk index stays green, the other red
	local cfg = G.configs[901]
	for _, st in ipairs(cfg.trafficLightConfig.states) do
		local set = {}
		for _, l in ipairs(st.lockedLanes) do set[l] = true end
		ok(not set[#cfg.laneConnections] and set[#cfg.laneConnections + 1], "crosswalks as read")
	end
end)

test("free turn When safe: relock first: a connection new to the node takes its approach's red; phases-only path and its LIGHTS line", function()
	local G = crossGame(SAFE, "rule", true, false)
	local conns = G.configs[901].laneConnections
	-- kerb turns freed everywhere earlier (Always), then the node lost the side road's far turn
	local v = Slip.classify(G.world, 901)
	local far = {}
	for _, ap in ipairs(v.approaches) do
		if ap.seg == 913 then
			for _, ex in ipairs(ap.exits) do if ex.cat == "far" then far[ex.seg] = true end end
		end
	end
	local cut = {}
	for _, c in ipairs(conns) do
		if not (c.segment0 == 913 and far[c.segment1]) then cut[#cut + 1] = c end
	end
	G.configs[901].laneConnections = cut
	local states = approachPhases(cut)
	local lists = {}
	for i, st in ipairs(states) do lists[i] = st.lockedLanes end
	local freed = LightsM.kerbPhases(cut, LightsM.kerbIndices(cut, G.kerb), 2, lists, LightsM.FREE)
	for i, st in ipairs(states) do st.lockedLanes = freed[i] end
	G.configs[901].trafficLightConfig = G.tlc(states)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "the far turn is added: a lane write")
	local cfg = G.configs[901]
	for s, st in ipairs(cfg.trafficLightConfig.states) do
		local red = {}
		for _, l in ipairs(st.lockedLanes) do red[l] = true end
		for i, c in ipairs(cfg.laneConnections) do
			if c.segment0 == 913 and far[c.segment1] then
				eq(red[i - 1] == true, s ~= 3, "phase " .. s .. ": the new far turn red unless 913 goes")
			end
		end
	end
	-- green everywhere (the merging phase too: merges are allowed)
	for k, phases in pairs(kerbRedPhases(G)) do eq(#phases, 0, k) end
	-- phases-only: the game re-makes its per-approach phases for our lanes; a new build frees them
	G.configs[901].trafficLightConfig = G.tlc(approachPhases(cfg.laneConnections))
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "no lane write")
	eq(#G.lightCmds, 1)
	local l = G.kinds("LIGHTS")[1]
	ok(l:find("src=auto node=901 to=free_turn free_turn=4 states=4 pref=auto", 1, true), l)
	ok(l:find(" free_phases=12 kept=- merge_free=0 shared_held=0", 1, true), l)
	for k, phases in pairs(kerbRedPhases(G)) do eq(#phases, 0, k) end
	-- again: nothing sent
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.lightCmds, 1, "already as safe as it gets")
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn When safe: phases-only path locks an earlier unsafe free (Always) back", function()
	local G = crossGame(SAFE, "rule", true, false)
	local conns = G.configs[901].laneConnections
	local states = approachPhases(conns)
	-- crosswalk 1 (not one of the node's roads: on every kerb turn's path) green in every phase
	for _, st in ipairs(states) do table.remove(st.lockedLanes, #st.lockedLanes - 1) end
	local lists = {}
	for i, st in ipairs(states) do lists[i] = st.lockedLanes end
	local freed = LightsM.kerbPhases(conns, LightsM.kerbIndices(conns, G.kerb), 2, lists, LightsM.FREE)
	for i, st in ipairs(states) do st.lockedLanes = freed[i] end
	G.configs[901].trafficLightConfig = G.tlc(states)
	for _, phases in pairs(kerbRedPhases(G)) do eq(#phases, 0, "Always: green everywhere") end
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 0, "no lane write")
	eq(#G.lightCmds, 1)
	for k, phases in pairs(kerbRedPhases(G)) do eq(#phases, 3, k .. ": red again wherever its approach is (green crosswalk)") end
	ok(G.kinds("LIGHTS")[1]:find(" free_phases=12 kept=ped:12 merge_free=0", 1, true), G.kinds("LIGHTS")[1])
	eq(#G.kinds("ERROR"), 0)
end)

test("free turn When safe: stale phases refused on the phases-only path; Off sends nothing", function()
	local G = crossGame(SAFE, "rule", true, false)
	local states = approachPhases(G.configs[901].laneConnections)
	states[1].lockedLanes[#states[1].lockedLanes + 1] = 999
	G.configs[901].trafficLightConfig = G.tlc(states)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(G.lightCmds, nil, "stale phases: nothing sent")
	local G2 = crossGame(OFF, "rule", true, false)
	G2.configs[901].trafficLightConfig = G2.tlc(approachPhases(G2.configs[901].laneConnections))
	G2.gs.handleEvent({}, G2.state, "", "apply_command", "onPostBuildProposal", crossBuild(G2))
	G2.frames(700)
	eq(G2.lightCmds, nil, "Off: no light proposal")
	eq(#G2.sent, 0)
	ok(G2.kinds("SUMMARY")[1]:find(" free_turn=off$"), G2.kinds("SUMMARY")[1])
	eq(#G.kinds("ERROR") + #G2.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Plain lane drops and gains (sl_slip case "D", PHASE7.md step 2)

--- The probe ring plus a straight two-way road far away: 501 -> 502 (segment 601, 3 + 3 lanes),
-- 502 -> 503 (segment 602, 2 + 2 lanes), 503 -> 504 (segment 603, 2 + 2 lanes): node 502 is a lane
-- drop + gain, node 503 a plain node, 501 and 504 dead ends.
local FX_DROP = {
	world = function()
		return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.build({ [501] = { 0, 500 }, [502] = { 80, 500 }, [503] = { 160, 500 },
			[504] = { 240, 500 } }, { [601] = { 501, 502, F.TPL.large }, [602] = { 502, 503, F.TPL.medium },
			[603] = { 503, 504, F.TPL.medium } }))
	end,
	conns = F.PROBE_4LANE_MEDIUM.conns,
}

local function dropBuild(G, withRing)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	local nodes, segs = { 501, 502, 503, 504 }, { 601, 602, 603 }
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

test("lane drop: a built road narrowing 3 -> 2 gets the drop rule at that node only; lights kept", function()
	local G = makeGame(nil, FX_DROP)
	-- engine stand-in at 502: every lane into every lane (crossing)
	G.configs[502].laneConnections = F.parseConns("601:1>602:3:R-,601:1>602:4:R-,601:2>602:3:R-,601:2>602:4:R-,601:3>602:3:R-,601:3>602:4:R-,602:1>601:4:R-,602:1>601:5:R-,602:1>601:6:R-,602:2>601:4:R-,602:2>601:5:R-,602:2>601:6:R-")
	G.lights[502] = true
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", dropBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	local sp = G.sent[1].proposal.streetProposal
	eq(sp.nodeConfigsToRemove, { 502 }, "only the drop node: 503 keeps its lanes, the dead ends have none")
	eq(#sp.nodeConfigsToAdd, 1)
	eq(Rules.connsText(G.configs[502].laneConnections), Rules.connsText(F.parseConns(
		"601:1>602:4:R-,601:2>602:4:R-,601:3>602:3:R-,602:1>601:6:R-,602:1>601:5:R-,602:2>601:4:R-")))
	local applies = G.kinds("APPLY")
	eq(#applies, 1)
	ok(applies[1]:find("kind=drop node=502 shape=lane_drop+gain case=D side=right side_from=two_way", 1, true), applies[1])
	eq(#G.kinds("SKIP"), 0, "plain nodes are not logged")
	G.frames(40)
	ok(G.kinds("VERIFY")[1]:find("same=1 nodes=1", 1, true), G.kinds("VERIFY")[1])
	eq(G.lightCmds, nil, "a lane drop keeps the game's lights")
	eq(G.lights[502], true)
	-- the same build again: already applied
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", dropBuild(G))
	G.frames(20)
	eq(#G.sent, 1)
	eq(#G.kinds("ERROR"), 0)
end)

test("lane drop: a ring and a drop in one build: the ring by the ring rule, the drop in the slip proposal", function()
	local G = makeGame(nil, FX_DROP)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", dropBuild(G, true))
	G.frames(15)
	eq(#G.sent, 2)
	eq(#G.sent[1].proposal.streetProposal.nodeConfigsToAdd, 4, "ring first")
	eq(G.sent[2].proposal.streetProposal.nodeConfigsToRemove, { 502 })
	for _, l in ipairs(G.kinds("APPLY")) do ok(not (l:find("kind=drop", 1, true) and l:find("node=22768", 1, true)), l) end
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- SUMMARY line per processed job (PHASE7.md step 6)

local function summaries(G) return G.kinds("SUMMARY") end

test("summary: a placed roundabout: one line, ring=applied/same/skipped; the same build again: same", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	local s = summaries(G)
	eq(#s, 1)
	ok(s[1]:find("^%[SQRL%] SUMMARY job=%d+ nodes=4 rings=1 ring=4/0/0 slip=0 cross=0 drop=0 same=0 skip=0 skips=%- phases=game free_turn=0 free_phases=0 shared_held=0$"), s[1])
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	s = summaries(G)
	eq(#s, 2)
	ok(s[2]:find("rings=1 ring=0/4/0 slip=0 cross=0 drop=0 same=4 skip=0 skips=-", 1, true), s[2])
end)

test("summary: nodes the write layer refuses count as skips under the reason's first word", function()
	local G = makeGame(nil, nil, { readonly = true, noTables = true })
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	local s = summaries(G)
	eq(#s, 1)
	ok(s[1]:find("ring=0/0/4 slip=0 cross=0 drop=0 same=0 skip=4 skips=no_strategy:4", 1, true), s[1])
end)

test("summary: a Channelized Junction: slip nodes and the centre crossing counted apart", function()
	local G = makeGame(nil, FX_CHANNEL)
	G.configs[2].laneConnections = F.parseConns("12:1>11:3:R-,12:1>11:4:R-,12:2>11:3:R-,12:2>11:4:R-,12:1>21:1:R-,12:2>21:2:R-,11:1>12:3:R-,11:2>12:4:R-")
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(15)
	local s = summaries(G)
	eq(#s, 1)
	ok(s[1]:find("nodes=7 rings=0 ring=0/0/0 slip=3 cross=1 drop=0 same=0 skip=0 skips=-", 1, true), s[1])
end)

test("summary: a centre whose phases cannot be re-pointed: cross=0, skips=lights:1", function()
	local G = makeGame(nil, FX_CHANNEL, { noLightState = true })
	phasedCentre(G)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(15)
	local s = summaries(G)
	eq(#s, 1)
	ok(s[1]:find("slip=3 cross=0 drop=0 same=0 skip=1 skips=lights:1", 1, true), s[1])
end)

test("summary: a ring and a lane drop in one build: one line for the job", function()
	local G = makeGame(nil, FX_DROP)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", dropBuild(G, true))
	G.frames(15)
	local s = summaries(G)
	eq(#s, 1)
	ok(s[1]:find("nodes=8 rings=1 ring=4/0/0 slip=0 cross=0 drop=1", 1, true), s[1])
end)

test("summary: a build of plain road only (no ring, no candidate) logs nothing", function()
	local G = makeGame(nil, FX_DROP)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	local sp = { addedNodes = { { entity = 504 } }, addedSegments = { { entity = 603, comp = { node0 = 503, node1 = 504 } } },
		nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	eq(#G.state:get().jobs, 1, "a job was queued")
	G.frames(20)
	eq(#G.sent, 0)
	eq(#summaries(G), 0)
	eq(#G.kinds("ERROR"), 0)
end)

test("APPLY: a node with one-way roads handed to the crossing rule logs why (via=terminal)", function()
	-- a diamond off-ramp end meeting the two-way road at about a right angle (sl_slip slipReason "terminal")
	local G = makeGame(nil, { world = function()
		return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.rampNode({ ramps = { { id = 33, leaving = true, tan = -85, far = -90 } } }))
	end, conns = F.PROBE_4LANE_MEDIUM.conns })
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	local sp = { addedNodes = { { entity = 1 } }, addedSegments = { { entity = 33, comp = { node0 = 1, node1 = 41 } } },
		nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	G.frames(15)
	local applies = G.kinds("APPLY")
	eq(#applies, 1)
	ok(applies[1]:find("kind=slip node=1 shape=t_junction case=X via=terminal side=right", 1, true), applies[1])
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Performance (PHASE7.md step 7): one job of 160 nodes, printed cost and component reads

--- A world of mixed junctions far apart: 6 Channelized X junctions (crossroads with slip lanes:
-- bypass walks), 4 ramp nodes (shallow-ramp chord walks), 4 merge and 4 diverge lines with lanes
-- added / dropped upstream (look-ahead walks, lane drops) and a 7 x 7 one-way grid of alternating
-- streets (a ring search at every junction). Returns the fixture and the job's nodes (at most 160).
local function mixedFixture()
	local subs = {}
	for k = 1, 6 do subs[#subs + 1] = F.channelX({ main = F.TPL.large, mirror = k % 2 == 0 }) end
	for k = 1, 4 do
		subs[#subs + 1] = F.rampNode({ mirror = k % 2 == 0, ramps = { { id = 33, leaving = true, tan = -80, far = -20 },
			{ id = 34, leaving = false, tan = -100, far = -160 } } })
	end
	local one3, one2 = "B- FV FV FV F-", "B- FV FV F-"
	for k = 1, 4 do
		subs[#subs + 1] = F.mergeLine({ mirror = k % 2 == 0, ramp = F.RAMP2, up = { { one3, 120 }, { one2, 150 } },
			down = { { one3, 100 }, { one2, 200 } } })
		subs[#subs + 1] = F.divergeLine({ mirror = k % 2 == 0, up = { { one3, 150 }, { one2, 150 } },
			down = { { one2, 200 } } })
	end
	subs[#subs + 1] = F.oneWayGrid(7, 60, 0, true)
	local seeds, worlds = {}, {}
	for k, w in ipairs(subs) do
		local sw = F.shift(w, 100000 * k, 3000 * k, 4000)
		worlds[#worlds + 1] = sw
		local ids = {}
		for id in pairs(sw.nodes) do ids[#ids + 1] = id end
		table.sort(ids)
		for _, id in ipairs(ids) do seeds[#seeds + 1] = id end
	end
	while #seeds > 160 do table.remove(seeds) end
	return {
		world = function()
			local w = F.PROBE_4LANE_MEDIUM.world()
			for _, sw in ipairs(worlds) do F.merge(w, sw) end
			return w
		end,
		conns = F.PROBE_4LANE_MEDIUM.conns,
	}, seeds
end

--- Runs one job of `seeds` through the script (build event, the GUI frames); returns ms of the frames
-- and the component reads by type.
local function timedJob(G, seeds)
	local reads = {}
	local gc = G.api.engine.getComponent
	G.api.engine.getComponent = function(e, ct)
		reads[ct] = (reads[ct] or 0) + 1
		return gc(e, ct)
	end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	local sp = { addedNodes = {}, addedSegments = { { entity = 0, comp = {} } }, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, n in ipairs(seeds) do sp.addedNodes[#sp.addedNodes + 1] = { entity = n } end
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	-- the job runs in one frame (after JOB_POLL / JOB_DELAY): the slowest frame and its reads
	local ms, worst = 0, {}
	for _ = 1, 20 do
		reads = {}
		local t0 = os.clock()
		G.frames(1)
		local dt = (os.clock() - t0) * 1000
		if dt > ms then ms, worst = dt, reads end
	end
	G.api.engine.getComponent = gc
	return ms, worst
end


test("perf: a 160-node job of mixed junctions, a one-way grid and Channelized X centres (printed)", function()
	local fx, seeds = mixedFixture()
	eq(#seeds, 160)
	local G = makeGame(nil, fx)
	local ms, reads = timedJob(G, seeds)
	eq(#G.kinds("ERROR"), 0)
	local s = G.kinds("SUMMARY")
	eq(#s, 1, "the job ran in that frame")
	-- the worst case of Phase 1: an acyclic one-way grid (no ring closes: a full search at every node)
	local gw = F.oneWayGrid(13, 40, 900000, false)
	local gseeds = {}
	for id in pairs(gw.nodes) do gseeds[#gseeds + 1] = id end
	table.sort(gseeds)
	while #gseeds > 160 do table.remove(gseeds) end
	local G2 = makeGame(nil, { world = function() return F.merge(F.PROBE_4LANE_MEDIUM.world(), gw) end,
		conns = F.PROBE_4LANE_MEDIUM.conns })
	local ms2, reads2 = timedJob(G2, gseeds)
	-- 160 Channelized X centres (every one with bypass walks): the worst case of the crossing rule
	local xw = F.PROBE_4LANE_MEDIUM.world()
	local xseeds = {}
	for k = 1, 160 do
		F.merge(xw, F.shift(F.channelX({ main = F.TPL.large }), 1000 * k, 400 * k, 8000))
		xseeds[#xseeds + 1] = 1000 * k + 1
	end
	local G3 = makeGame(nil, { world = function() return xw end, conns = F.PROBE_4LANE_MEDIUM.conns })
	local ms3, reads3 = timedJob(G3, xseeds)
	local function r(t) return string.format("BN %d BE %d BNC %d", t.BN or 0, t.BE or 0, t.BNC or 0) end
	print(string.format("job 160 mixed: %.1f ms (%s); acyclic one-way grid: %.1f ms (%s); X centres: %.1f ms (%s)",
		ms, r(reads), ms2, r(reads2), ms3, r(reads3)))
	-- generous bounds: every node and segment is read once per job (the world caches them)
	ok((reads.BN or 0) <= 400 and (reads.BE or 0) <= 700, r(reads))
	ok((reads2.BN or 0) <= 200 and (reads2.BE or 0) <= 400, r(reads2))
end)

test("automatic pass: a fresh Roundabout Interchange ring gives its on-ramp its own lane (APPLY entry=own_lane)", function()
	local base = 500000
	local iw = F.shift(F.interchange({ dir = "ccw" }), base, 5000, 5000)
	local fx = { world = function() return F.merge(F.PROBE_4LANE_MEDIUM.world(), iw) end, conns = F.PROBE_4LANE_MEDIUM.conns }
	local G = makeGame(nil, fx)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	local sp = { addedNodes = {}, addedSegments = { { entity = 0, comp = {} } }, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for id = base + 1, base + 4 do sp.addedNodes[#sp.addedNodes + 1] = { entity = id } end
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	G.frames(20)
	eq(#G.kinds("ERROR"), 0)
	local own, give = {}, 0
	for _, l in ipairs(G.kinds("APPLY")) do
		if l:find("entry=own_lane", 1, true) then own[#own + 1] = l end
		if l:find("entry=give_way", 1, true) then give = give + 1 end
	end
	eq(#own, 1, table.concat(G.kinds("APPLY"), "\n"))
	eq(give, 0)
	ok(own[1]:find("node=" .. (base + 2) .. " ", 1, true), own[1])
	ok(own[1]:find("entries=1 turbo=false", 1, true), own[1])
	-- the written config: the ramp (arm 2000 + 2) into ring-out lane 2 (outer), both ring lanes into lane 1
	local rin, rout, arm = base + 1001, base + 1002, base + 2002
	local exp = string.format("%d:1>%d:1:R-,%d:2>%d:1:R-,%d:1>%d:2:R-", rin, rout, rin, rout, arm, rout)
	eq(Rules.connsText(G.configs[base + 2].laneConnections), Rules.connsText(F.parseConns(exp)))
end)

---------------------------------------------------------------------------
-- Junction audit (sl_audit.lua, TESTING.md X)

local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"

test("audit: a placed Channelized Junction: AUDIT for the flagged centre, one AUDIT_SUMMARY after SUMMARY", function()
	local G = makeGame(nil, FX_CHANNEL)
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(15)
	local a = G.kinds("AUDIT")
	eq(#a, 1, table.concat(a, "\n"))
	eq(a[1], "[SQRL] AUDIT node=1 case=X shape=t_junction findings=shared:1 detail=shared:11:fs src=auto job=1")
	local s = G.kinds("AUDIT_SUMMARY")
	eq(#s, 1)
	ok(s[1]:find("src=auto job=1 audited=4 flagged=1 findings=shared:1 forced=shared:2,squeeze:2 skips=-", 1, true), s[1])
	-- the lines follow the job's SUMMARY
	local iS, iA = nil, nil
	for i, l in ipairs(G.logs) do
		if l:find("[SQRL] SUMMARY ", 1, true) then iS = i end
		if l:find("[SQRL] AUDIT_SUMMARY ", 1, true) then iA = i end
	end
	ok(iS ~= nil and iA ~= nil and iS < iA)
	eq(#G.kinds("ERROR"), 0)
end)

test("audit: a placed roundabout (ring junctions) is audited; plain road builds stay quiet", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(15)
	local s = G.kinds("AUDIT_SUMMARY")
	eq(#s, 1)
	ok(s[1]:find("audited=4 flagged=0 findings=-", 1, true), s[1])
	eq(#G.kinds("AUDIT"), 0)
end)

test("audit: a failing audit is logged (ERROR where=audit) and the job's write still went out", function()
	local G = makeGame(nil, FX_CHANNEL)
	local real = Audit.audit
	Audit.audit = function() error("audit boom") end
	local okR, e = pcall(function()
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
		G.frames(15)
	end)
	Audit.audit = real
	assert(okR, e)
	eq(#G.sent, 1, "the slip proposal was sent")
	ok(G.kinds("ERROR")[1] and G.kinds("ERROR")[1]:find("where=audit", 1, true), G.kinds("ERROR")[1])
	eq(#G.kinds("ERROR"), 1, "the job's first failure only")
	ok(G.kinds("AUDIT_SUMMARY")[1]:find("audited=0 flagged=0 findings=- forced=- failed=4", 1, true), G.kinds("AUDIT_SUMMARY")[1])
end)

test("audit: a big job logs at most MAX_LINES AUDIT lines; the summary keeps the totals (unlogged=)", function()
	local xw = F.PROBE_4LANE_MEDIUM.world()
	local seeds = {}
	for k = 1, 60 do
		F.merge(xw, F.shift(F.channelX({ main = F.TPL.large }), 1000 * k, 400 * k, 8000))
		seeds[#seeds + 1] = 1000 * k + 1
	end
	local G = makeGame(nil, { world = function() return xw end, conns = F.PROBE_4LANE_MEDIUM.conns })
	timedJob(G, seeds)
	local a, s = G.kinds("AUDIT"), G.kinds("AUDIT_SUMMARY")
	eq(#s, 1)
	eq(#a, Audit.MAX_LINES, "capped")
	local flagged = tonumber(s[1]:match(" flagged=(%d+)"))
	ok(flagged ~= nil and flagged > Audit.MAX_LINES, s[1])
	ok(s[1]:find(" unlogged=" .. (flagged - Audit.MAX_LINES), 1, true), s[1])
	-- the totals count every flagged junction (60 centres, shared:2 each)
	ok(s[1]:find("findings=shared:120", 1, true), s[1])
end)

test("perf: the audit's share of the 160-node jobs (printed; component reads unchanged)", function()
	-- stub: no audit work; else the time inside Audit.safe is summed (spent, ms per job)
	local function run(fx, seeds, stub)
		local real = Audit.safe
		local spent = 0
		if stub then
			Audit.safe = function() return { counts = {}, forced = {}, detail = {}, total = 0, skipped = "stub" } end
		else
			Audit.safe = function(...)
				local t0 = os.clock()
				local a, b = real(...)
				spent = spent + (os.clock() - t0) * 1000
				return a, b
			end
		end
		local best, reads = math.huge, nil
		for _ = 1, 3 do
			local G = makeGame(nil, fx)
			local ms, r = timedJob(G, seeds)
			if ms < best then best, reads = ms, r end
		end
		Audit.safe = real
		return best, reads, spent / 3
	end
	local fx, seeds = mixedFixture()
	local xw = F.PROBE_4LANE_MEDIUM.world()
	local xseeds = {}
	for k = 1, 160 do
		F.merge(xw, F.shift(F.channelX({ main = F.TPL.large }), 1000 * k, 400 * k, 8000))
		xseeds[#xseeds + 1] = 1000 * k + 1
	end
	local xfx = { world = function() return xw end, conns = F.PROBE_4LANE_MEDIUM.conns }
	local mA, rA, mS = run(fx, seeds, false)
	local mB, rB = run(fx, seeds, true)
	local xA, rxA, xS = run(xfx, xseeds, false)
	local xB, rxB = run(xfx, xseeds, true)
	local function r(t) return string.format("BN %d BE %d BNC %d", t.BN or 0, t.BE or 0, t.BNC or 0) end
	print(string.format("job 160 mixed: %.1f ms with the audit (%.2f ms in it), %.1f ms without; 160 X centres: "
		.. "%.1f ms (%.2f ms in it) / %.1f ms", mA, mS, mB, xA, xS, xB))
	eq(r(rA), r(rB), "the audit reads nothing more (mixed)")
	eq(r(rxA), r(rxB), "the audit reads nothing more (X centres)")
end)

---------------------------------------------------------------------------
-- Traffic lights decide the crossroads rule's extra straight shares (TESTING.md Y)

--- A placed Channelized Junction (centre T node 1) with the centre's light state set first:
-- pref = "YES" | "NO" | "AUTO", light = a light standing. Returns G and the centre's light reads.
local function litChannel(pref, light)
	local G = makeGame(nil, FX_CHANNEL)
	G.configs[1].trafficLightPreference = G.TLP[pref]
	G.lights[1] = light or nil
	local reads, get = {}, G.api.engine.getComponent
	G.api.engine.getComponent = function(e, ct)
		if ct == "BNTL" then reads[e] = (reads[e] or 0) + 1 end
		return get(e, ct)
	end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	-- the job's frame, then the lights-off pass (queued after the write answered: the next frame)
	G.frames(16)
	return G, reads
end

local function centreApply(G)
	for _, l in ipairs(G.kinds("APPLY")) do
		if l:find("node=1 ", 1, true) then return l end
	end
end

test("lights: the automatic pass reads the centre's light once and logs lit=; unlit drops the straight share", function()
	-- AUTO without a light standing: unknown, the rule as before (the share stays, flagged as before)
	local G, reads = litChannel("AUTO", false)
	local a = centreApply(G)
	ok(a and a:find(" lit=unknown", 1, true) and not a:find("unshared=", 1, true), a)
	eq(reads[1], 1, "one light read for the crossroads")
	for _, n in ipairs({ 2, 3, 4 }) do eq(reads[n], 1, "slip node " .. n .. ": the lights pass reads it (unchanged)") end
	local lanesUnknown = a:match("lanes=(%S+)")
	ok(G.kinds("AUDIT")[1]:find("node=1 case=X shape=t_junction findings=shared:1", 1, true), G.kinds("AUDIT")[1])
	local textUnknown = Rules.connsText(G.configs[1].laneConnections)
	-- lit (AUTO with a light, or YES): the share stays, the audit calls it by design
	for _, v in ipairs({ { "AUTO", true }, { "YES", false } }) do
		local GL, rl = litChannel(v[1], v[2])
		local l = centreApply(GL)
		ok(l and l:find(" lit=yes", 1, true) and not l:find("unshared=", 1, true), l)
		eq(l:match("lanes=(%S+)"), lanesUnknown, "lit lanes = unknown lanes")
		eq(Rules.connsText(GL.configs[1].laneConnections), textUnknown, v[1] .. " written as before")
		eq(rl[1], 1)
		eq(#GL.kinds("AUDIT"), 0, "nothing avoidable: " .. table.concat(GL.kinds("AUDIT"), "\n"))
		local s = GL.kinds("AUDIT_SUMMARY")[1]
		ok(s:find("audited=4 flagged=0 findings=- forced=shared:2,squeeze:2,shared_lit:1 skips=-", 1, true), s)
		eq(#GL.kinds("ERROR"), 0)
	end
	-- NO: unlit, the west approach's share is dropped, no avoidable sharing left
	local GN, rn = litChannel("NO", false)
	local n = centreApply(GN)
	ok(n and n:find(" lit=no unshared=13", 1, true), n)
	ok(n:find("lanes=11:s|s;13:s|f;15:f ", 1, true), n)
	ok(lanesUnknown == "11:s|s;13:s|sf;15:f", lanesUnknown)
	ok(n:match("lanes=(%S+)") ~= lanesUnknown)
	eq(rn[1], 1)
	ok(Rules.connsText(GN.configs[1].laneConnections) ~= textUnknown, "written without the share")
	eq(#GN.kinds("AUDIT"), 0, table.concat(GN.kinds("AUDIT"), "\n"))
	ok(GN.kinds("AUDIT_SUMMARY")[1]:find("audited=4 flagged=0 findings=- forced=shared:2,squeeze:2 skips=-", 1, true),
		GN.kinds("AUDIT_SUMMARY")[1])
	-- the crossroads keeps its lights: no LIGHTS line for node 1 in any case
	for _, g in ipairs({ G, GN }) do
		for _, l in ipairs(g.kinds("LIGHTS")) do ok(not l:find("node=1 ", 1, true), l) end
	end
	eq(GN.configs[1].trafficLightPreference, GN.TLP.NO, "the player's choice stays")
	eq(#GN.kinds("ERROR"), 0)
end)

test("lights: a fake game without the light enum or component reads unknown and plans as before", function()
	local G = makeGame(nil, FX_CHANNEL)
	G.api.type.enum.TrafficLightPreference = nil
	G.api.type.ComponentType.BASE_NODE_TRAFFIC_LIGHT = nil
	G.configs[1].trafficLightPreference = 1 -- NO, but without the enum nobody can tell
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", channelBuild(G))
	G.frames(15)
	local a = centreApply(G)
	ok(a and a:find(" lit=unknown", 1, true), a)
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Light phases = Smart Lanes (setting sqrl_light_phases, PHASES_PLAN.md step 4): the plan written with
-- the lanes, phases-only, re-check, fallback, index safety. Game default: today's behaviour.

local PhasesM = ug_require "square_smart_lanes::/smart_lanes/sl_phases.lua"
local PPM = ug_require "square_smart_lanes::/smart_lanes/sl_phaseplan.lua"

local SL = { sqrl_light_phases = 2 }
local function with(a, b)
	local o = {}
	for k, v in pairs(a or {}) do o[k] = v end
	for k, v in pairs(b or {}) do o[k] = v end
	return o
end

--- The probe ring plus a crossroads (or a T without 914) at node 901 of template tpl; mirror: left-hand
-- traffic. 911 west, 912 east (main road), 913 north, 914 south.
local function fxJunction(tpl, t, mirror)
	return {
		world = function()
			local nodes = { [901] = { 0, -800 }, [902] = { -60, -800 }, [903] = { 60, -800 }, [904] = { 0, -740 } }
			local segs = { [911] = { 901, 902, tpl }, [912] = { 901, 903, tpl }, [913] = { 901, 904, tpl } }
			if not t then
				nodes[905] = { 0, -860 }
				segs[914] = { 901, 905, tpl }
			end
			return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.build(nodes, segs, mirror))
		end,
		conns = F.PROBE_4LANE_MEDIUM.conns,
	}
end

--- The game's six default phases (findings.md): main road (911 / 912) green, all-red 6 s, side road
-- green, all-red 6 s, pedestrians 3 s, all-red 9 s; canSkip everywhere, minDuration 1.5.
local function gameSix(conns, nCross)
	local function phase(green, cwGreen, d)
		local l = {}
		for i, c in ipairs(conns) do
			if not green[c.segment0] then l[#l + 1] = i - 1 end
		end
		for k = 1, nCross do
			if not cwGreen then l[#l + 1] = #conns + k - 1 end
		end
		return { lockedLanes = l, duration = d, minDuration = 1.5, canSkip = true }
	end
	return { phase({ [911] = true, [912] = true }, false, 23.7012), phase({}, false, 6),
		phase({ [913] = true, [914] = true }, false, 23.7012), phase({}, false, 6), phase({}, true, 3), phase({}, false, 9) }
end

--- A junction game: lanes "default" (the game's model) or "rule" (Smart Lanes'), lit: a light stands
-- (AUTO), phases: the game's six phases; crosswalks = the node's edge ids (cws: other entities).
local function junctionGame(params, fx, lanes, lit, phases, cws)
	local G = makeGame(params, fx)
	local v = Slip.classify(G.world, 901)
	assert(v.case == "X", "case X")
	G.kerb = Cross.kerbPairs(v)
	local conns = lanes == "rule" and Slip.plan(G.world, 901, function() return {} end).conns or Slip.defaultConns(v)
	G.configs[901].laneConnections = conns
	if cws == nil then
		cws = {}
		for _, s in ipairs(G.world.nodes[901].segs) do cws[#cws + 1] = s end
	end
	G.configs[901].crosswalks = cws
	G.configs[901].trafficLightPreference = G.TLP.AUTO
	G.lights[901] = lit or nil
	if phases then G.configs[901].trafficLightConfig = G.tlc(gameSix(conns, #cws)) end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	return G
end

--- onPostBuildProposal param: the junction's nodes and segments added.
local function junctionBuild(G)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, id in ipairs({ 901, 902, 903, 904, 905 }) do
		if G.world.nodes[id] then sp.addedNodes[#sp.addedNodes + 1] = { entity = id } end
	end
	for _, id in ipairs({ 911, 912, 913, 914 }) do
		local sg = G.world.segs[id]
		if sg then sp.addedSegments[#sp.addedSegments + 1] = { entity = id, comp = { node0 = sg.node0, node1 = sg.node1 } } end
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

--- The plan for node 901 as it stands (its connections and crosswalks), from a fresh world read.
local function expectedPlan(G, opts)
	local cfg = G.configs[901]
	local v = Slip.classify(G.world, 901)
	local info = PPM.infoFromView(v, G.world, 901, cfg.laneConnections)
	local M = assert(PhasesM.build({ conns = cfg.laneConnections, arms = info.arms, crosswalks = cfg.crosswalks, cls = info.cls }))
	return PPM.plan(M, info, opts), M
end

--- Node 901's states equal `plan` and pass the crash rules: every index within [0, #conns + #cws - 1],
-- fields set, durations 1..60 whole s, minDuration 0..30 in 0.5 s steps, the plan validates.
local function checkWritten(G, plan, M, tag)
	local cfg = G.configs[901]
	local states = cfg.trafficLightConfig.states
	local max = #cfg.laneConnections + #cfg.crosswalks - 1
	eq(#states, #plan.states, tag .. ": state count")
	for s, st in ipairs(states) do
		for _, l in ipairs(st.lockedLanes) do ok(type(l) == "number" and l >= 0 and l <= max, tag .. ": index " .. tostring(l)) end
		local a, b = {}, {}
		for i, x in ipairs(st.lockedLanes) do a[i] = x end
		for i, x in ipairs(plan.states[s].locked) do b[i] = x end
		table.sort(a)
		table.sort(b)
		eq(a, b, tag .. ": phase " .. s .. " locked")
		eq({ st.duration, st.minDuration, st.canSkip }, { plan.states[s].duration, plan.states[s].minDuration, plan.states[s].canSkip },
			tag .. ": phase " .. s .. " timing")
		ok(st.duration >= 1 and st.duration <= 60 and st.duration == math.floor(st.duration), tag .. ": duration")
		ok(st.minDuration >= 0 and st.minDuration <= 30 and st.minDuration * 2 == math.floor(st.minDuration * 2), tag .. ": min")
		eq(type(st.canSkip), "boolean")
	end
	local asPlan = { states = {} }
	for s, st in ipairs(states) do
		asPlan.states[s] = { locked = st.lockedLanes, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
	end
	-- an axis plan's within-road conflicts: accepted with its road list and the explicit flag only (sl_write
	-- planFor validates so); the states read back carry no road list
	asPlan.axis = plan.axis
	eq({ PPM.validatePlan(M, asPlan, #cfg.laneConnections, #cfg.crosswalks, { axis = plan.axis ~= nil }) }, { true }, tag .. ": validates")
end

test("light phases Smart Lanes: lit 2x2 X, 3x3 X and T get the plan in the lane write itself (both traffic sides)", function()
	for _, fx in ipairs({ { F.TPL.medium, false, "2x2 X" }, { F.TPL.large, false, "3x3 X" }, { F.TPL.medium, true, "T" } }) do
		for _, mir in ipairs({ false, true }) do
			local tag = fx[3] .. (mir and " left" or " right")
			local G = junctionGame(with(SL, ALWAYS), fxJunction(fx[1], fx[2], mir), "default", true, true)
			ok(G.kinds("MODE")[1]:find("phases=sl free_turn=always", 1, true), G.kinds("MODE")[1])
			G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
			G.frames(15)
			eq(#G.sent, 1, tag .. ": one proposal (lanes and phases)")
			eq(G.lightCmds, nil, tag .. ": no second proposal on the node")
			local plan, M = expectedPlan(G)
			ok(plan ~= nil, tag .. ": a plan")
			checkWritten(G, plan, M, tag)
			-- the free kerb turn (Always) is not applied on top: kerb turns stay red where the plan has them
			local ph = G.kinds("PHASES")
			eq(#ph, 1, tag)
			-- Rules.line writes spaces as "_"
			local text = PPM.planText(plan, #G.configs[901].laneConnections):gsub("%s+", "_")
			ok(ph[1]:gsub(" pattern=%a+", ""):find("src=auto node=901 phases=sl plan=" .. text, 1, true) ~= nil, ph[1])
			local sum = G.kinds("SUMMARY")[1]
			ok(sum:find("cross=1 ", 1, true) and sum:find(" phases=sl sl_plans=1 plan_fail=- free_turn=0", 1, true), tag .. ": " .. sum)
			ok(G.kinds("WRITE")[1]:find("phases=sl sl_plans=1 plan_fails=0", 1, true), G.kinds("WRITE")[1])
			G.frames(700)
			eq(#G.kinds("RECHECK"), 0, tag .. ": lit at the read: no re-check")
			eq(#G.kinds("ERROR"), 0, tag)
			if not mir then print(tag .. ": " .. PPM.planText(plan, #G.configs[901].laneConnections)) end
		end
	end
end)

test("free turn: 1- and 2-lane crossroads (a player's report 2026-10-14): every kerb lane goes straight too, so no kerb turn is freed (When safe, Always); SUMMARY shared_held=4; both sides", function()
	for _, tpl in ipairs({ { F.TPL.small, "1-lane" }, { F.TPL.medium, "2-lane" } }) do
		for _, mir in ipairs({ false, true }) do
			for _, params in ipairs({ SAFE, ALWAYS }) do
				local tag = tpl[2] .. (mir and " left " or " right ") .. (params == SAFE and "safe" or "always")
				local G = junctionGame(params, fxJunction(tpl[1], false, mir), "default", true, true)
				G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
				G.frames(15)
				local cfg = G.configs[901]
				local idx = LightsM.kerbIndices(cfg.laneConnections, G.kerb)
				eq(#idx, 4, tag .. ": a kerb turn per approach")
				-- each kerb turn red in the phases where its lane is red (the approach's straight)
				local max = #cfg.laneConnections + #cfg.crosswalks - 1
				for _, j in ipairs(idx) do
					local c = cfg.laneConnections[j + 1]
					for s, st in ipairs(cfg.trafficLightConfig.states) do
						local red, mates, allRed = {}, 0, true
						for _, l in ipairs(st.lockedLanes) do
							ok(l >= 0 and l <= max, tag .. ": index in range")
							red[l] = true
						end
						for i, d in ipairs(cfg.laneConnections) do
							if i - 1 ~= j and d.withRoad and d.segment0 == c.segment0 and d.lane0 == c.lane0 then
								mates = mates + 1
								if not red[i - 1] then allRed = false end
							end
						end
						ok(mates > 0, tag .. ": the kerb lane carries another movement")
						if allRed then ok(red[j], tag .. " phase " .. s .. ": " .. Rules.connsText({ c }) .. " red with its lane") end
					end
				end
				local sum = G.kinds("SUMMARY")[1]
				ok(sum:find(" free_turn=0 free_phases=0", 1, true) and sum:find(" shared_held=4", 1, true), tag .. ": " .. sum)
				eq(#G.kinds("ERROR"), 0, tag)
			end
		end
	end
end)

test("light phases Game default (default): byte-for-byte today's write (re-pointed phases, free kerb turn), no PHASES line", function()
	-- Game default never plans: the planner and the map builder fail if called
	local origPlan, origBuild = PPM.plan, PhasesM.build
	PPM.plan = function() error("planner called in Game default") end
	PhasesM.build = function() error("map built in Game default") end
	local function run(params, lanes)
		-- 3-lane roads: a dedicated kerb lane, so the free kerb turn has something to free (Lights.sharedKerb)
		local G = junctionGame(params, fxJunction(F.TPL.large, false, false), lanes or "default", true, true)
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
		G.frames(15)
		return G
	end
	local okRun, res = pcall(function()
		return { run(ALWAYS), run(with({ sqrl_light_phases = 1 }, ALWAYS)), run(ALWAYS, "rule"),
			run(with({ sqrl_light_phases = 1 }, ALWAYS), "rule") }
	end)
	PPM.plan, PhasesM.build = origPlan, origBuild
	if not okRun then error(res, 0) end
	local G0, G1, R0, R1 = res[1], res[2], res[3], res[4]
	eq(#G0.sent, 1)
	--- A deep copy without functions (the fake configs' clone closures differ per object).
	local function plainCopy(x, seen)
		if type(x) ~= "table" then
			if type(x) == "function" then return nil end
			return x
		end
		seen = seen or {}
		if seen[x] then return seen[x] end
		local t = {}
		seen[x] = t
		for k, v in pairs(x) do t[k] = plainCopy(v, seen) end
		return t
	end
	-- the whole lane proposal (configs, removals, context, flags), every light command and every log line
	eq(plainCopy(G0.sent), plainCopy(G1.sent), "the same lane proposal")
	eq(plainCopy(G0.lightCmds), plainCopy(G1.lightCmds), "the same light commands")
	eq(G0.logs, G1.logs, "the same log")
	-- lanes already right: the free kerb turn's phases-only proposal, the same either way
	eq(#R0.sent, 0)
	ok(R0.lightCmds ~= nil and #R0.lightCmds == 1, "the free kerb turn as a light proposal")
	eq(plainCopy(R0.lightCmds), plainCopy(R1.lightCmds), "the same phases-only proposal")
	eq(R0.logs, R1.logs, "the same log (phases-only)")
	eq(#G0.kinds("ERROR") + #R0.kinds("ERROR"), 0)
	eq(#G0.configs[901].trafficLightConfig.states, 6, "the game's six phases, re-pointed")
	eq(#G0.kinds("PHASES") + #G1.kinds("PHASES"), 0)
	ok(G0.kinds("SUMMARY")[1]:find(" phases=game free_turn=", 1, true), G0.kinds("SUMMARY")[1])
	ok(G0.kinds("MODE")[1]:find("phases=game free_turn=always", 1, true), G0.kinds("MODE")[1])
end)

test("light phases Smart Lanes: no plan or an invalid one falls back to the free kerb turn and the re-pointing, reason logged", function()
	local orig = PPM.plan
	local cases = {
		{ "refused", function() return nil, "test_refused" end, "plan_fail=test_refused" },
		-- a plan that greens everything at once: validation catches the conflicts
		{ "invalid", function(M) return { kind = "x", cycle = 10, states = { { locked = {}, green = {}, duration = 10, minDuration = 0, canSkip = false } } } end,
			"plan_fail=invalid_conflict" },
		-- an index past the list: validation catches it
		{ "index", function(M) return { kind = "x", cycle = 10, states = { { locked = { M.size + 3 }, green = {}, duration = 10, minDuration = 0, canSkip = false } } } end,
			"plan_fail=invalid_index" },
	}
	for _, cs in ipairs(cases) do
		PPM.plan = cs[2]
		local okRun, e = pcall(function()
			-- 3-lane roads: dedicated kerb lanes, the free kerb turn frees them (Lights.sharedKerb)
			local G = junctionGame(with(SL, ALWAYS), fxJunction(F.TPL.large, false, false), "default", true, true)
			G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
			G.frames(15)
			eq(#G.sent, 1, cs[1])
			local states = G.configs[901].trafficLightConfig.states
			eq(#states, 6, cs[1] .. ": the game's phases kept, re-pointed")
			local max = #G.configs[901].laneConnections + #G.configs[901].crosswalks - 1
			for _, st in ipairs(states) do
				for _, l in ipairs(st.lockedLanes) do ok(l >= 0 and l <= max, cs[1] .. ": index") end
			end
			ok(G.kinds("PHASES")[1]:find(cs[3], 1, true), G.kinds("PHASES")[1])
			local sum = G.kinds("SUMMARY")[1]
			ok(sum:find(" sl_plans=0 plan_fail=", 1, true) and sum:find(" free_turn=4", 1, true), cs[1] .. ": " .. sum)
			eq(#G.kinds("ERROR"), 0)
		end)
		PPM.plan = orig
		if not okRun then error(e, 0) end
	end
end)

test("light phases Smart Lanes: lanes already right: a phases-only proposal (preference kept); again: nothing sent", function()
	local G = junctionGame(SL, fxJunction(F.TPL.medium, false, false), "rule", true, true)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.sent, 0, "no lane write")
	eq(#G.lightCmds, 1)
	eq(G.lightCmds[1].pref, G.TLP.AUTO)
	local plan, M = expectedPlan(G)
	checkWritten(G, plan, M, "phases-only")
	local l = G.kinds("LIGHTS")[1]
	ok(l:find("src=auto node=901 to=sl_phases phases=sl states=" .. #plan.states, 1, true), l)
	ok(l:find(" plan=x4_", 1, true), l)
	ok(G.kinds("SUMMARY")[1]:find("same=1 ", 1, true) and G.kinds("SUMMARY")[1]:find(" sl_plans=1 ", 1, true), G.kinds("SUMMARY")[1])
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.lightCmds, 1, "the plan stands: nothing sent")
	eq(#G.kinds("ERROR"), 0)
end)

-- user 2026-10-16: Smart lights stays on after its timing was adjusted (Re-time, Keep timing adjusted, the Crossing
-- window): the build pass keeps the plan's phases in other durations, and writes again when the structure differs.
test("light phases Smart Lanes: lanes already right: re-timed plan phases are kept; another phase structure is written", function()
	local G = junctionGame(SL, fxJunction(F.TPL.medium, false, false), "rule", true, true)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.lightCmds, 1)
	-- re-timed: every green changed, a skippable phase cut below its minDuration (Re-time: min(min, duration))
	local st = {}
	for i, ph in ipairs(G.configs[901].trafficLightConfig.states) do
		local d = ph.duration + 7
		local m = ph.minDuration
		if i == 1 and ph.canSkip then d = 1; m = math.min(m or 0, 1) end
		st[i] = { lockedLanes = ph.lockedLanes, duration = d, minDuration = m, canSkip = ph.canSkip }
	end
	G.configs[901].trafficLightConfig = G.tlc(st)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.lightCmds, 1, "the re-timed plan stands: nothing sent")
	-- the structure differs (a phase's locked lanes): the plan is written again
	st[1].lockedLanes = {}
	G.configs[901].trafficLightConfig = G.tlc(st)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.lightCmds, 2, "another structure: the plan again")
	eq(#G.kinds("ERROR"), 0)
end)

test("light phases Smart Lanes: phases-only never while a write on the node is pending; the next job waits for it", function()
	local G = junctionGame(SL, fxJunction(F.TPL.medium, false, false), "default", true, true)
	G.defer = true
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "the lane write went out, not landed")
	-- a second build while it is in flight: the lanes look right already (we flip the config to ours)
	G.configs[901].laneConnections = Slip.plan(G.world, 901, function() return {} end).conns
	G.configs[901].trafficLightConfig = G.tlc(gameSix(G.configs[901].laneConnections, #G.configs[901].crosswalks))
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(G.lightCmds, nil, "busy: no light proposal on a node with a write in flight")
	eq(#G.kinds("SUMMARY"), 1, "job 2 waits while its node's write is in flight")
	G.defer = false
	G.flush()
	-- the first write landed with its plan; job 2 then reads it and finds it in place
	local plan, M = expectedPlan(G)
	checkWritten(G, plan, M, "landed")
	G.frames(60)
	local s = G.kinds("SUMMARY")
	ok(s[2] and s[2]:find("SUMMARY job=2 ", 1, true) and s[2]:find(" same=1 ", 1, true), tostring(s[2]))
	eq(#G.sent, 1, "no second lane write")
	eq(G.lightCmds, nil, "the plan stands: nothing sent")
	eq(#G.kinds("ERROR"), 0)
end)

test("light phases Smart Lanes: a write whose callback never comes holds its node for a bounded time only", function()
	local G = junctionGame(SL, fxJunction(F.TPL.medium, false, false), "default", true, true)
	G.defer = true -- the lane write never answers
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	G.configs[901].laneConnections = Slip.plan(G.world, 901, function() return {} end).conns
	G.configs[901].trafficLightConfig = G.tlc(gameSix(G.configs[901].laneConnections, #G.configs[901].crosswalks))
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(G.lightCmds, nil, "held while the write may still answer")
	G.frames(620)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	ok(G.lightCmds ~= nil and #G.lightCmds == 1, "released after the timeout: the phases-only proposal goes out")
	eq(#G.kinds("ERROR"), 0)
end)

test("light phases Smart Lanes: unknown light at the read: the re-check writes the plan once the game's light stands", function()
	local G = junctionGame(SL, fxJunction(F.TPL.medium, false, false), "default", false, false) -- AUTO, no light, no phases
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	eq(#G.kinds("PHASES"), 1)
	ok(G.kinds("PHASES")[1]:gsub(" pattern=%a+", ""):find("node=901 phases=sl plan_fail=lit_unknown", 1, true), G.kinds("PHASES")[1])
	ok(G.kinds("SUMMARY")[1]:find(" sl_plans=0 plan_fail=lit_unknown:1 ", 1, true), G.kinds("SUMMARY")[1])
	-- the game puts its light and default phases on the junction (our lanes)
	G.lights[901] = true
	G.configs[901].trafficLightConfig = G.tlc(gameSix(G.configs[901].laneConnections, #G.configs[901].crosswalks))
	G.frames(60)
	local r = G.kinds("RECHECK")
	eq(#r, 1)
	ok(r[1]:find("kind=phases job=1 nodes=1 phases=1 sent=1 same=0 fail=0 changed=0", 1, true), r[1])
	eq(#G.lightCmds, 1)
	local plan, M = expectedPlan(G)
	checkWritten(G, plan, M, "re-check")
	ok(G.kinds("LIGHTS")[1]:find("src=recheck node=901 to=sl_phases", 1, true), G.kinds("LIGHTS")[1])
	G.frames(600)
	r = G.kinds("RECHECK")
	eq(#r, 2)
	ok(r[2]:find("sent=0 same=1", 1, true), r[2])
	eq(#G.lightCmds, 1)
	eq(#G.kinds("ERROR"), 0)
end)

test("light phases Smart Lanes: index range over junction variants (templates, T / X, sides, lanes, crosswalk kinds)", function()
	local n = 0
	for _, tpl in ipairs({ F.TPL.small, F.TPL.medium, F.TPL.large }) do
		for _, t in ipairs({ false, true }) do
			for _, mir in ipairs({ false, true }) do
				for _, lanes in ipairs({ "default", "rule" }) do
					for _, cwKind in ipairs({ "edges", "unknown", "none", "partial" }) do
						local fx = fxJunction(tpl, t, mir)
						local cws = nil
						if cwKind == "unknown" then cws = { 1, 2 }
						elseif cwKind == "none" then cws = {}
						elseif cwKind == "partial" then cws = { 911, 913 } end
						local G = junctionGame(SL, fx, lanes, true, true, cws)
						G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
						G.frames(15)
						local cfg = G.configs[901]
						local max = #cfg.laneConnections + #cfg.crosswalks - 1
						for _, st in ipairs(cfg.trafficLightConfig.states) do
							for _, l in ipairs(st.lockedLanes) do
								ok(type(l) == "number" and l >= 0 and l <= max, "index in range")
							end
							ok(st.duration >= 1 and st.duration <= 60)
						end
						local plan, M = expectedPlan(G)
						if plan ~= nil and (#G.kinds("PHASES") > 0 or (G.lightCmds and #G.lightCmds > 0)) then
							checkWritten(G, plan, M, "variant")
							n = n + 1
						end
						eq(#G.kinds("ERROR"), 0)
					end
				end
			end
		end
	end
	ok(n >= 40, "plans written: " .. n)
end)

---------------------------------------------------------------------------
-- Zones (sl_zones.lua): another mod's GUI marks circles game / sl / sl_phases through
-- makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.zones", payload) -> handleEvent -> state.

local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"
local RING_C = { x = -246.6, y = -1692.1 } -- PROBE_4LANE_MEDIUM's ring centre
local X901 = { x = 0, y = -800 }          -- fxJunction's centre node

local function zonesEvent(G, payload)
	return G.gs.handleEvent({}, G.state, "", Zones.EVENT_ID, Zones.EV_ZONES, payload)
end

local function zone(at, r, ab) return { x = at.x, y = at.y, r = r, ab = ab } end

test("zones: event round trip: stored in the saved state, ZONES op=set line, mirrored by the GUI; clear removes them", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	eq(G.kinds("ZONES"), { "[SQRL] ZONES op=loaded n=0 run=-" })
	zonesEvent(G, { op = "set", run = "777.1", zones = { zone(RING_C, 100, "game"), zone(X901, 90, "sl"), zone({ x = 5000, y = 0 }, 50, "sl_phases") } })
	local s = G.state:get()
	eq(#s.zones, 3)
	eq(s.zones[1], { x = RING_C.x, y = RING_C.y, r = 100, ab = "game" })
	eq(s.zrun, "777.1")
	eq(s.zseq, 1)
	eq(G.kinds("ZONES")[2], "[SQRL] ZONES op=set n=3 run=777.1 by_ab=game:1,sl:1,sl_phases:1")
	-- a build's job queued after the zones keeps them (jobs and zones share the state)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	eq(#G.state:get().zones, 3)
	eq(#G.state:get().jobs, 1)
	zonesEvent(G, { op = "clear", run = "c1" })
	s = G.state:get()
	eq(s.zones, nil)
	eq(s.zrun, "c1")
	eq(s.zseq, 2)
	eq(#s.jobs, 1, "jobs untouched")
	eq(G.kinds("ZONES")[3], "[SQRL] ZONES op=clear n=0 run=c1 by_ab=game:0,sl:0,sl_phases:0")
	eq(#G.kinds("ERROR"), 0)
end)

test("zones: payload validation: anything malformed is ignored as a whole (state unchanged, one line, capped)", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	local good = zone(X901, 50, "game")
	local many = {}
	for i = 1, Zones.MAX + 1 do many[i] = zone({ x = i, y = 0 }, 10, "sl") end
	local bad = {
		{ "not a table", "not_table" },
		{ { op = "replace", zones = { good } }, "op" },
		{ { op = "set" }, "zones" },
		{ { op = "set", zones = many }, "too_many" },
		{ { op = "set", zones = { good, "x" } }, "zone2" },
		{ { op = "set", zones = { zone({ x = 0 / 0, y = 0 }, 10, "sl") } }, "xy1" },
		{ { op = "set", zones = { zone({ x = math.huge, y = 0 }, 10, "sl") } }, "xy1" },
		{ { op = "set", zones = { zone({ x = 0, y = 2e6 }, 10, "sl") } }, "xy1" },
		{ { op = "set", zones = { zone(X901, 2001, "sl") } }, "r1" },
		{ { op = "set", zones = { zone(X901, 0, "sl") } }, "r1" },
		{ { op = "set", zones = { zone(X901, "10", "sl") } }, "r1" },
		{ { op = "set", zones = { zone(X901, 10, "SL") } }, "ab1" },
		{ { op = "set", zones = { zone(X901, 10, nil) } }, "ab1" },
		{ { op = "set", run = "has space", zones = { good } }, "run" },
		{ { op = "set", run = string.rep("a", 41), zones = { good } }, "run" },
		{ { op = "clear", run = {} }, "run" },
	}
	for i, b in ipairs(bad) do
		zonesEvent(G, b[1])
		-- SL-4: nothing of the payload is kept; only the refusal (run, reason) and the accepted modes
		local st = G.state:get()
		eq(st.zones, nil, "case " .. i)
		eq(st.zrun, nil, "case " .. i)
		local run = type(b[1]) == "table" and Zones.runOf(b[1].run) or nil
		eq(st.zerr, { run = run or "-", reason = b[2] }, "case " .. i)
		eq(st.zmodes, Zones.AB, "case " .. i)
		local lines = G.kinds("ZONES")
		eq(lines[#lines], "[SQRL] ZONES op=ignored reason=" .. b[2], "case " .. i)
	end
	-- exactly the cap and r = R_MAX pass; a numeric run id becomes text
	local cap = {}
	for i = 1, Zones.MAX do cap[i] = zone({ x = i, y = 0 }, Zones.R_MAX, "sl") end
	zonesEvent(G, { op = "set", run = 42, zones = cap })
	eq(#G.state:get().zones, Zones.MAX)
	eq(G.state:get().zrun, "42")
	-- an empty set stores no list (the state stays small)
	zonesEvent(G, { op = "set", zones = {} })
	eq(G.state:get().zones, nil)
	eq(G.state:get().zrun, "-")
	-- the ignored lines are capped at 20 per session
	for _ = 1, 30 do zonesEvent(G, 7) end
	local n = 0
	for _, l in ipairs(G.kinds("ZONES")) do if l:find("op=ignored", 1, true) then n = n + 1 end end
	eq(n, 20)
end)

test("zones: an old save (subscribed to onPostBuildProposal only) is re-subscribed once per load: the event arrives", function()
	local G = makeGame()
	-- the saved subscriptions of a save from before the zones event
	G.state.subs = { "onPostBuildProposal" }
	G.gs.update({}, G.state, 0.1)
	eq(G.state.subs, { "SmartLanes.zones", "SmartLanes.kept", "SmartLanes.auto", "onPostBuildProposal", "SmartLanes.qlen" })
	-- the next load (a fresh Lua state, same saved state): subscribes again, once
	local G2 = makeGame()
	G2.state = G.state
	G.state.subs = { "onPostBuildProposal" }
	G2.gs.update({}, G2.state, 0.1)
	eq(G2.state.subs, { "SmartLanes.zones", "SmartLanes.kept", "SmartLanes.auto", "onPostBuildProposal", "SmartLanes.qlen" })
	-- the map editor: nothing subscribed, events ignored
	local M = makeGame()
	M.api.engine.config.getModParams = function() return { square_smart_lanes = {}, [""] = { isMapEditor = true } } end
	M.gs.update({}, M.state, 0.1)
	eq(M.state.subs, nil)
	zonesEvent(M, { op = "set", zones = { zone(X901, 50, "game") } })
	eq(M.state:get(), nil)
end)

test("zones: a reload keeps them: ZONES op=loaded n= run= from the saved state", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	zonesEvent(G, { op = "set", run = "r9", zones = { zone(RING_C, 100, "game"), zone(X901, 90, "sl_phases") } })
	local G2 = makeGame()
	G2.state = G.state
	G2.gs.update({}, G2.state, 0.1)
	G2.frames(3)
	eq(G2.kinds("ZONES"), { "[SQRL] ZONES op=loaded n=2 run=r9" })
	-- and they act: the ring in the game zone is left alone
	G2.gs.handleEvent({}, G2.state, "", "apply_command", "onPostBuildProposal", ringBuild(G2))
	G2.frames(20)
	eq(#G2.sent, 0)
end)

test("zones: game zone: the automatic pass leaves the ring alone (SKIP reason=zone_game, SUMMARY skips=zone_game); sl / outside: as before", function()
	local function run(z)
		local G = makeGame()
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		if z then zonesEvent(G, { op = "set", run = "t", zones = { z } }) end
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
		G.frames(60)
		return G
	end
	local base = run(nil)
	eq(#base.sent, 1, "no zones: the ring rule as before")
	local game = run(zone(RING_C, 120, "game"))
	eq(#game.sent, 0, "nothing written")
	eq(game.lightCmds, nil, "no light change")
	eq(#game.kinds("APPLY"), 0)
	local skip = game.kinds("SKIP")
	eq(#skip, 1)
	ok(skip[1]:find("kind=zone zone=game job=1 nodes=4 reason=zone_game", 1, true), skip[1])
	local sum = game.kinds("SUMMARY")[1]
	ok(sum ~= nil and sum:find("skip=4 skips=zone_game:4", 1, true), tostring(sum))
	-- a zone covering only one ring node still keeps the whole ring alone
	local part = run(zone({ x = -215.6, y = -1692.1 }, 5, "game"))
	eq(#part.sent, 0)
	ok(part.kinds("SKIP")[1]:find("kind=zone", 1, true))
	-- sl zone and a game zone elsewhere: exactly as without zones
	for _, z in ipairs({ zone(RING_C, 120, "sl"), zone(X901, 120, "game") }) do
		local G = run(z)
		eq(#G.sent, 1)
		local a, b = G.sent[1].proposal.streetProposal.nodeConfigsToAdd, base.sent[1].proposal.streetProposal.nodeConfigsToAdd
		eq(#a, #b)
		for i = 1, #b do
			eq(a[i].entity, b[i].entity)
			eq(Rules.connsText(a[i].comp.laneConnections), Rules.connsText(b[i].comp.laneConnections))
		end
		eq(#G.kinds("SKIP"), 0)
	end
	eq(#game.kinds("ERROR") + #part.kinds("ERROR"), 0)
end)

test("zones: sl_phases zone: a lit crossroads gets the Smart Lanes phase plan although Light phases = Game default", function()
	local function run(z)
		local G = junctionGame(ALWAYS, fxJunction(F.TPL.medium, false, false), "default", true, true)
		if z then zonesEvent(G, { op = "set", run = "p", zones = { z } }) end
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
		G.frames(15)
		return G
	end
	local plain = run(nil)
	eq(#plain.kinds("PHASES"), 0, "Game default: no plan")
	local G = run(zone(X901, 90, "sl_phases"))
	ok(G.kinds("MODE")[1]:find("phases=game", 1, true))
	eq(#G.sent, 1, "one proposal (lanes and phases)")
	eq(G.lightCmds, nil)
	local plan, M = expectedPlan(G)
	ok(plan ~= nil)
	checkWritten(G, plan, M, "sl_phases zone")
	local ph = G.kinds("PHASES")
	eq(#ph, 1)
	ok(ph[1]:gsub(" pattern=%a+", ""):find("src=auto node=901 phases=sl plan=", 1, true), ph[1])
	local sum = G.kinds("SUMMARY")[1]
	ok(sum:find(" phases=game sl_plans=1 plan_fail=- zone_phases=1 ", 1, true), sum)
	ok(G.kinds("WRITE")[1]:find("phases=game sl_plans=1 plan_fails=0", 1, true), G.kinds("WRITE")[1])
	-- an sl zone: the global setting (Game default) as without zones
	local sl = run(zone(X901, 90, "sl"))
	eq(#sl.kinds("PHASES"), 0)
	eq(#sl.sent, 1)
	-- a game zone: the crossroads keeps the game's lanes and its six phases
	local gz = run(zone(X901, 90, "game"))
	eq(#gz.sent, 0)
	eq(gz.lightCmds, nil)
	eq(#gz.configs[901].trafficLightConfig.states, 6)
	eq(#G.kinds("ERROR") + #gz.kinds("ERROR"), 0)
end)

test("no classic fallback (automatic pass): a lit crossroads skewed past 45 deg has no axis plan: Light phases = Smart Lanes keeps the game's phases (re-pointed), PHASES pattern=none plan_fail=no_axis_shape", function()
	local fx = fxJunction(F.TPL.large, false, false)
	-- arm 914 at 330 deg instead of 270: the 913-914 pair is 60 deg off a road (PP.AXIS_TOL 45)
	fx.world = function()
		local nodes = { [901] = { 0, -800 }, [902] = { -60, -800 }, [903] = { 60, -800 }, [904] = { 0, -740 }, [905] = { 52, -830 } }
		local segs = { [911] = { 901, 902, F.TPL.large }, [912] = { 901, 903, F.TPL.large }, [913] = { 901, 904, F.TPL.large },
			[914] = { 901, 905, F.TPL.large } }
		return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.build(nodes, segs, false))
	end
	local G = junctionGame(with(SL, ALWAYS), fx, "default", true, true)
	local cfg0 = G.configs[901]
	local info0 = PPM.infoFromView(Slip.classify(G.world, 901), G.world, 901, cfg0.laneConnections)
	local M0 = assert(PhasesM.build({ conns = cfg0.laneConnections, arms = info0.arms, crosswalks = cfg0.crosswalks, cls = info0.cls }))
	eq({ PPM.plan(M0, info0) }, { nil, "no_axis_shape" }, "fixture: no axis plan")
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "the lane write")
	local cfg = G.configs[901]
	eq(#cfg.trafficLightConfig.states, 6, "the game's six phases, re-pointed")
	local max = #cfg.laneConnections + #cfg.crosswalks - 1
	for _, st in ipairs(cfg.trafficLightConfig.states) do
		for _, l in ipairs(st.lockedLanes) do ok(l >= 0 and l <= max, "index " .. l) end
	end
	ok(G.kinds("PHASES")[1]:find("src=auto node=901 phases=sl pattern=none plan_fail=no_axis_shape", 1, true), G.kinds("PHASES")[1])
	ok(G.kinds("SUMMARY")[1]:find(" sl_plans=0 plan_fail=no_axis_shape:1 ", 1, true), G.kinds("SUMMARY")[1])
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- Fan mode (sl_fan zones, PHASES_PLAN.md "Fan mode"): lit crossroads get every entry lane to every exit
-- lane of every other arm plus the fan plan in one proposal; unlit / unknown keep the rule.

--- The fan plan node 901 should carry (its written connections and crosswalks).
local function expectedFanPlan(G)
	local cfg = G.configs[901]
	local v = Slip.classify(G.world, 901)
	local info = PPM.infoFromView(v, G.world, 901, cfg.laneConnections)
	local M = assert(PhasesM.build({ conns = cfg.laneConnections, arms = info.arms, crosswalks = cfg.crosswalks, cls = info.cls }))
	return PPM.plan(M, info, { fan = true }), M
end

test("zones: sl_fan zone: a lit crossroads gets the full fan and the fan plan in ONE proposal, both sides, X and T", function()
	for _, t in ipairs({ false, true }) do
		for _, mir in ipairs({ false, true }) do
			local tag = (t and "T" or "X") .. (mir and " left" or " right")
			local G = junctionGame(ALWAYS, fxJunction(F.TPL.medium, t, mir), "default", true, true)
			zonesEvent(G, { op = "set", run = "f", zones = { zone(X901, 90, "sl_fan") } })
			eq(G.kinds("ZONES")[2], "[SQRL] ZONES op=set n=1 run=f by_ab=game:0,sl:0,sl_phases:0,sl_fan:1", tag)
			G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
			G.frames(15)
			eq(#G.sent, 1, tag .. ": one proposal (lanes and phases)")
			eq(G.lightCmds, nil, tag)
			local v = Slip.classify(G.world, 901)
			eq(Rules.roadText(G.configs[901].laneConnections), Rules.roadText(Cross.fanConns(v)), tag .. ": the fan")
			local plan, M = expectedFanPlan(G)
			ok(plan ~= nil and plan.fan == true, tag .. ": a fan plan")
			-- written as planned, every index in range; validates only as a fan plan
			local cfg = G.configs[901]
			local states = cfg.trafficLightConfig.states
			local max = #cfg.laneConnections + #cfg.crosswalks - 1
			eq(#states, #plan.states, tag)
			local asPlan = { states = {} }
			for s, st in ipairs(states) do
				for _, l in ipairs(st.lockedLanes) do ok(type(l) == "number" and l >= 0 and l <= max, tag .. ": index") end
				eq({ st.duration, st.minDuration, st.canSkip }, { plan.states[s].duration, plan.states[s].minDuration, plan.states[s].canSkip }, tag)
				asPlan.states[s] = { locked = st.lockedLanes, duration = st.duration, minDuration = st.minDuration, canSkip = st.canSkip }
			end
			ok(PPM.validatePlan(M, asPlan, #cfg.laneConnections, #cfg.crosswalks, { fan = true }), tag .. ": validates")
			local a = G.kinds("APPLY")
			local fanApply = nil
			for _, l in ipairs(a) do if l:find("node=901", 1, true) then fanApply = l end end
			ok(fanApply and fanApply:find(" mode=fan", 1, true), tostring(fanApply))
			local ph = G.kinds("PHASES")
			eq(#ph, 1, tag)
			ok(ph[1]:gsub(" pattern=%a+", ""):find("src=auto node=901 phases=sl plan=" .. (t and "t3_fan" or "x4_fan"), 1, true), ph[1])
			local sum = G.kinds("SUMMARY")[1]
			ok(sum:find(" phases=game sl_plans=1 plan_fail=- zone_fan=1 ", 1, true), sum)
			-- the fan crosses by design: no AUDIT line for it
			for _, l in ipairs(G.kinds("AUDIT")) do ok(not l:find("node=901 ", 1, true), l) end
			-- again: the fan and its plan stand, nothing sent
			G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
			G.frames(15)
			eq(#G.sent, 1, tag .. ": nothing more")
			eq(G.lightCmds, nil, tag)
			eq(#G.kinds("ERROR"), 0, tag)
			if not t and not mir then print("sl_fan zone 2x2 X: " .. PPM.planText(plan, #cfg.laneConnections)) end
		end
	end
end)

test("zones: sl_fan zone: unlit keeps the rule (fan=unlit); other zones and outside unchanged", function()
	-- unlit (no light, no phases): the rule's lanes, as an sl_phases zone
	local G = junctionGame(ALWAYS, fxJunction(F.TPL.medium, false, false), "default", false, false)
	G.lights[901] = false
	G.configs[901].trafficLightPreference = G.TLP.NO
	zonesEvent(G, { op = "set", run = "f", zones = { zone(X901, 90, "sl_fan") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	eq(Rules.roadText(G.configs[901].laneConnections), Rules.roadText(Slip.plan(G.world, 901, function() return {} end).conns))
	local a = nil
	for _, l in ipairs(G.kinds("APPLY")) do if l:find("node=901", 1, true) then a = l end end
	ok(a and a:find(" fan=unlit", 1, true) and not a:find("mode=fan", 1, true), tostring(a))
	-- the same junction lit, in an sl / sl_phases zone or outside: never the fan
	for _, z in ipairs({ false, "sl", "sl_phases" }) do
		local H = junctionGame(ALWAYS, fxJunction(F.TPL.medium, false, false), "default", true, true)
		if z then zonesEvent(H, { op = "set", run = "o", zones = { zone(X901, 90, z) } }) end
		H.gs.handleEvent({}, H.state, "", "apply_command", "onPostBuildProposal", junctionBuild(H))
		H.frames(15)
		eq(#H.sent, 1)
		eq(Rules.roadText(H.configs[901].laneConnections), Rules.roadText(Slip.plan(H.world, 901, function() return {} end).conns),
			tostring(z))
		for _, l in ipairs(H.kinds("APPLY")) do ok(not l:find("fan", 1, true), l) end
		ok(not H.kinds("SUMMARY")[1]:find("zone_fan", 1, true))
		eq(#H.kinds("ERROR"), 0)
	end
	eq(#G.kinds("ERROR"), 0)
end)

test("zones: sl_fan zone: no fan plan: the fan is not written (SKIP lights:fan_..), nothing else changes", function()
	local orig = PPM.plan
	PPM.plan = function(M, info, opts)
		if opts and opts.fan then return nil, "too_many_phases" end
		return orig(M, info, opts)
	end
	local okRun, e = pcall(function()
		local G = junctionGame(ALWAYS, fxJunction(F.TPL.medium, false, false), "default", true, true)
		local before = Rules.connsText(G.configs[901].laneConnections)
		zonesEvent(G, { op = "set", run = "f", zones = { zone(X901, 90, "sl_fan") } })
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
		G.frames(15)
		eq(#G.sent, 0, "nothing sent")
		eq(Rules.connsText(G.configs[901].laneConnections), before)
		eq(#G.configs[901].trafficLightConfig.states, 6, "the game's phases")
		local skip = G.kinds("SKIP")
		ok(skip[1] and skip[1]:find("node=901 reason=lights:fan_too_many_phases", 1, true), tostring(skip[1]))
		eq(#G.kinds("ERROR"), 0)
	end)
	PPM.plan = orig
	if not okRun then error(e, 0) end
end)

test("zones: sl_fan zone: unknown light at the read: the rule, then the re-check writes fan + plan in one proposal", function()
	local G = junctionGame(ALWAYS, fxJunction(F.TPL.medium, false, false), "default", false, false) -- AUTO, no light yet
	zonesEvent(G, { op = "set", run = "f", zones = { zone(X901, 90, "sl_fan") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", junctionBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	local rule = Slip.plan(G.world, 901, function() return {} end).conns
	eq(Rules.roadText(G.configs[901].laneConnections), Rules.roadText(rule), "the rule first")
	ok(G.kinds("PHASES")[1]:find("plan_fail=lit_unknown", 1, true), G.kinds("PHASES")[1])
	-- the game's light and phases arrive on our lanes
	G.lights[901] = true
	G.configs[901].trafficLightConfig = G.tlc(gameSix(G.configs[901].laneConnections, #G.configs[901].crosswalks))
	G.frames(60)
	eq(#G.sent, 2, "the fan went out")
	local v = Slip.classify(G.world, 901)
	eq(Rules.roadText(G.configs[901].laneConnections), Rules.roadText(Cross.fanConns(v)))
	local plan = expectedFanPlan(G)
	eq(#G.configs[901].trafficLightConfig.states, #plan.states)
	local r = G.kinds("RECHECK")
	ok(r[1] and r[1]:find("kind=phases job=1 nodes=1 phases=1 sent=1 same=0 fail=0 changed=0", 1, true), tostring(r[1]))
	local a = G.kinds("APPLY")
	ok(a[#a]:find("src=recheck", 1, true) and a[#a]:find(" mode=fan", 1, true), a[#a])
	ok(G.kinds("PHASES")[2]:gsub(" pattern=%a+", ""):find("src=recheck node=901 phases=sl plan=x4_fan", 1, true), tostring(G.kinds("PHASES")[2]))
	-- the later re-check: lanes are no longer the rule's text (the fan replaced them): left alone
	G.frames(600)
	eq(#G.sent, 2)
	eq(G.lightCmds, nil)
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- sl_lock zones (sl_zones.lua): Smart Lanes lanes, the game's phases, the kerb turn never freed
-- (Lights.LOCK in the lane write, as the tool's Reset), whatever "Free kerb turn" / "Light phases" say.

--- A crossroads game (crossGame) inside an sl_lock zone; freed: the kerb turns are out of every phase
-- already (an earlier Always write).
local function lockGame(params, lanes, lit, phases, freed)
	local G = crossGame(params, lanes, lit, phases)
	if freed then
		local cfg = G.configs[901]
		local conns = cfg.laneConnections
		local lists = {}
		for i, st in ipairs(cfg.trafficLightConfig.states) do lists[i] = st.lockedLanes end
		-- every kerb connection out of every phase, as an Always write before rev 8 (or a hand edit) left them;
		-- LightsM.FREE no longer frees a kerb turn whose lane also goes straight (the game's lanes here)
		local isKerb = {}
		for _, j in ipairs(LightsM.kerbIndices(conns, G.kerb)) do isKerb[j] = true end
		local states = gamePhases(conns)
		for i, st in ipairs(states) do
			local l = {}
			for _, x in ipairs(lists[i]) do if not isKerb[x] then l[#l + 1] = x end end
			st.lockedLanes = l
		end
		cfg.trafficLightConfig = G.tlc(states)
		eq(kerbRed(G), 0, "freed before")
	end
	zonesEvent(G, { op = "set", run = "l", zones = { zone(X901, 90, "sl_lock") } })
	return G
end

--- Each phase of node 901 as the game's phases for its current connections (the kerb turn red with its approach).
local function asGamePhases(G, tag)
	local conns = G.configs[901].laneConnections
	local want = gamePhases(conns)
	local got = G.configs[901].trafficLightConfig.states
	eq(#got, #want, tag .. ": same phases")
	for s = 1, #want do
		local a, b = {}, {}
		for _, l in ipairs(got[s].lockedLanes) do a[#a + 1] = l end
		for _, l in ipairs(want[s].lockedLanes) do b[#b + 1] = l end
		table.sort(a)
		table.sort(b)
		eq(a, b, tag .. ": phase " .. s)
	end
end

test("zones: sl_lock zone: Smart Lanes lanes, kerb turn kept red although the setting is Always; APPLY / SUMMARY say so", function()
	local G = lockGame(ALWAYS, "default", true, true)
	local old = G.configs[901].laneConnections
	local oldStates = G.configs[901].trafficLightConfig.states
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "one proposal")
	eq(G.lightCmds, nil, "no second proposal")
	local conns = G.configs[901].laneConnections
	ok(Rules.connsText(conns) ~= Rules.connsText(old), "the crossing rule rewrote the lanes")
	for s, st in ipairs(G.configs[901].trafficLightConfig.states) do
		eq(st.lockedLanes, Rules.remapLocked(old, conns, 2, oldStates[s].lockedLanes), "phase " .. s .. ": as with Off")
	end
	eq(kerbRed(G), 4, "each kerb turn red with its approach")
	local a = G.kinds("APPLY")[1]
	ok(a:find(" zone=sl_lock free_turn=off$"), a)
	local sum = G.kinds("SUMMARY")[1]
	ok(sum:find(" zone_lock=1 lock_turn=0 lock_phases=0 free_turn=0 free_phases=0", 1, true), sum)
	eq(#G.kinds("PHASES"), 0)
	G.frames(700)
	eq(#G.kinds("RECHECK"), 0)
	eq(#G.kinds("ERROR"), 0)
	-- the same junction in an sl zone: freed (the setting)
	local S = crossGame(ALWAYS, "default", true, true)
	zonesEvent(S, { op = "set", run = "s", zones = { zone(X901, 90, "sl") } })
	S.gs.handleEvent({}, S.state, "", "apply_command", "onPostBuildProposal", crossBuild(S))
	S.frames(15)
	eq(kerbRed(S), 0, "sl zone: freed")
	ok(not S.kinds("APPLY")[1]:find("sl_lock", 1, true))
	ok(not S.kinds("SUMMARY")[1]:find("zone_lock", 1, true), S.kinds("SUMMARY")[1])
end)

test("zones: sl_lock zone: kerb turns freed earlier end locked (lane write and lanes already right); indices in range", function()
	for _, params in ipairs({ ALWAYS, SAFE, OFF }) do
		-- a lane write: the freed turns locked back before re-pointing, then locked in the new phases
		local G = lockGame(params, "default", true, true, true)
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
		G.frames(15)
		eq(#G.sent, 1)
		eq(G.lightCmds, nil)
		eq(kerbRed(G), 4, "locked back")
		asGamePhases(G, "write")
		local sum = G.kinds("SUMMARY")[1]
		ok(sum:find(" zone_lock=1 lock_turn=4 lock_phases=4 ", 1, true), sum)
		ok(sum:find(" free_turn=" .. (params == OFF and "off" or "0"), 1, true), sum)
		eq(#G.kinds("ERROR"), 0)
		-- lanes already right: a phases-only lock; again: nothing sent
		local R = lockGame(params, "rule", true, true, true)
		R.gs.handleEvent({}, R.state, "", "apply_command", "onPostBuildProposal", crossBuild(R))
		R.frames(15)
		eq(#R.sent, 0, "no lane write")
		eq(#R.lightCmds, 1)
		eq(R.lightCmds[1].pref, R.TLP.AUTO)
		eq(kerbRed(R), 4)
		asGamePhases(R, "same")
		local l = R.kinds("LIGHTS")[1]
		ok(l:find("src=auto node=901 to=lock_turn lock_turn=4 states=2", 1, true), l)
		local rs = R.kinds("SUMMARY")[1]
		ok(rs:find(" zone_lock=1 lock_turn=4 lock_phases=4 ", 1, true), rs)
		R.gs.handleEvent({}, R.state, "", "apply_command", "onPostBuildProposal", crossBuild(R))
		R.frames(15)
		eq(#R.lightCmds, 1, "already locked: nothing sent")
		R.frames(700)
		eq(#R.lightCmds, 1)
		eq(#R.kinds("ERROR"), 0)
	end
end)

test("zones: sl_lock zone: Light phases = Smart Lanes: no plan there (game phases, kerb locked); outside the zone the plan", function()
	local P = { sqrl_free_turn = 3, sqrl_light_phases = 2 }
	local G = lockGame(P, "default", true, true, true)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	ok(G.kinds("MODE")[1]:find("phases=sl", 1, true), G.kinds("MODE")[1])
	eq(#G.sent, 1)
	eq(#G.kinds("PHASES"), 0, "no Smart Lanes plan in an sl_lock zone")
	eq(kerbRed(G), 4)
	asGamePhases(G, "phases=sl")
	eq(#G.kinds("ERROR"), 0)
	local O = crossGame(P, "default", true, true)
	O.gs.handleEvent({}, O.state, "", "apply_command", "onPostBuildProposal", crossBuild(O))
	O.frames(15)
	ok(#O.kinds("PHASES") > 0, "outside: the plan")
end)

test("zones: sl_lock zone: unknown light at the read: no re-check; phases the game makes later stay as made", function()
	local G = lockGame(ALWAYS, "default", false, false)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	G.lights[901] = true
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
	G.frames(700)
	eq(#G.kinds("RECHECK"), 0)
	eq(G.lightCmds, nil)
	eq(kerbRed(G), 4)
	eq(#G.kinds("ERROR"), 0)
end)

test("zones: sl_lock zone: a job on a node with a write in flight waits, then locks a turn freed since (phases-only)", function()
	local G = lockGame(ALWAYS, "default", true, true)
	G.defer = true
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "the lane write went out, not landed")
	-- a second build while it is in flight: the lanes look right already
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(2)
	G.configs[901].laneConnections = Slip.plan(G.world, 901, function() return {} end).conns
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
	G.defer = false
	G.flush()
	-- the landed write's phases, then the kerb turns freed by someone else before the re-check
	local cfg = G.configs[901]
	local lists = {}
	for i, st in ipairs(cfg.trafficLightConfig.states) do lists[i] = st.lockedLanes end
	local res = assert(LightsM.kerbPhases(cfg.laneConnections, LightsM.kerbIndices(cfg.laneConnections, G.kerb), 2, lists, LightsM.FREE))
	local states = gamePhases(cfg.laneConnections)
	for i, st in ipairs(states) do st.lockedLanes = res[i] end
	cfg.trafficLightConfig = G.tlc(states)
	eq(kerbRed(G), 0)
	G.frames(700)
	eq(kerbRed(G), 4, "locked back")
	asGamePhases(G, "recheck")
	ok(#G.kinds("LIGHTS") >= 1 and G.kinds("LIGHTS")[#G.kinds("LIGHTS")]:find("to=lock_turn", 1, true), tostring(G.kinds("LIGHTS")[1]))
	ok(G.kinds("LIGHTS")[1]:find("src=auto node=901 to=lock_turn lock_turn=4 ", 1, true), G.kinds("LIGHTS")[1])
	ok(G.kinds("SUMMARY")[2]:find(" same=1 ", 1, true) and G.kinds("SUMMARY")[2]:find(" zone_lock=1 lock_turn=4 ", 1, true), G.kinds("SUMMARY")[2])
	eq(#G.kinds("ERROR"), 0)
end)

---------------------------------------------------------------------------
-- sl_exitfan zones (sl_zones.lua; PLAN.md "Exit-lane fan (sl_exitfan zones)"): Smart Lanes lanes with every turn
-- fanned into the exit lanes its game phase leaves it, the game's phases (re-pointed), a freed kerb turn only
-- into the exit's kerb lane.

--- The exit fan's connections of node 901 (a fixture world lit and inside the zone).
local function exitFanConns()
	local w = FX_CROSS.world()
	w.lit = function() return true end
	w.exitFan = function() return true end
	local r = Slip.plan(w, 901, function() return {} end)
	assert(r.view.exitFan == true)
	return r.conns, Cross.kerbPairs(r.view)
end

--- Phase checks of node 901 under the exit fan (setting Always, the gamePhases style): every index in range;
-- a kerb connection into the exit's kerb lane green in every phase, one into another lane red exactly where
-- its approach is red; every other connection as the plain re-pointing (approach's phase). Returns the counts.
local function exitFanPhases(G, tag, freed)
	local cfg = G.configs[901]
	local conns = cfg.laneConnections
	local _, kerb = exitFanConns()
	local max = #conns + #cfg.crosswalks - 1
	local states = cfg.trafficLightConfig.states
	local nFree, nHeld = 0, 0
	for i, c in ipairs(conns) do
		local side = c.segment0 == 913 or c.segment0 == 914
		local pos = kerb[c.segment0 .. ">" .. c.segment1]
		for s, st in ipairs(states) do
			local red = false
			for _, l in ipairs(st.lockedLanes) do
				ok(type(l) == "number" and l >= 0 and l <= max, tag .. ": index " .. tostring(l) .. " in range 0.." .. max)
				if l == i - 1 then red = true end
			end
			local approachRed = (s == 1) == side
			if type(pos) == "table" and pos[c.lane1] == 1 and freed then
				eq(red, false, tag .. ": kerb-lane turn " .. Rules.connsText({ c }) .. " freed in phase " .. s)
			else
				eq(red, approachRed, tag .. ": " .. Rules.connsText({ c }) .. " red with its approach in phase " .. s)
			end
		end
		if type(pos) == "table" then
			if pos[c.lane1] == 1 then nFree = nFree + 1 else nHeld = nHeld + 1 end
		end
	end
	return nFree, nHeld
end

test("zones: sl_exitfan zone: lit 3x3 crossroads gets the exit fan; Always frees only the kerb-lane connection", function()
	for _, params in ipairs({ ALWAYS, SAFE, OFF }) do
		local G = crossGame(params, "default", true, true)
		zonesEvent(G, { op = "set", run = "e", zones = { zone(X901, 90, "sl_exitfan") } })
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
		G.frames(15)
		eq(#G.sent, 1, "one proposal")
		eq(G.lightCmds, nil, "no second proposal on the node")
		local want = exitFanConns()
		eq(Rules.roadText(G.configs[901].laneConnections), Rules.roadText(want), "the exit fan")
		-- 3-lane roads (FX_CROSS: a dedicated kerb lane, so the free kerb turn has something to free)
		eq(Rules.roadCount(G.configs[901].laneConnections), 24)
		local nFree, nHeld = exitFanPhases(G, "write", params == ALWAYS)
		eq({ nFree, nHeld }, { 4, 4 }, "per approach one kerb-lane and one other-lane kerb connection")
		local a = G.kinds("APPLY")[1]
		ok(a:find(" exit_fan=yes", 1, true) and a:find(" zone=sl_exitfan", 1, true), a)
		local sum = G.kinds("SUMMARY")[1]
		ok(sum:find(" zone_exitfan=1 exit_fan=1", 1, true), sum)
		eq(#G.kinds("PHASES"), 0)
		G.frames(700)
		eq(#G.kinds("ERROR"), 0)
	end
	-- the same junction in an sl zone and outside every zone: today's rule, no exit_fan field
	for _, ab in ipairs({ "sl", false }) do
		local S = crossGame(ALWAYS, "default", true, true)
		if ab then zonesEvent(S, { op = "set", run = "s", zones = { zone(X901, 90, ab) } }) end
		S.gs.handleEvent({}, S.state, "", "apply_command", "onPostBuildProposal", crossBuild(S))
		S.frames(15)
		eq(Rules.roadText(S.configs[901].laneConnections), Rules.roadText(Slip.plan(S.world, 901, function() return {} end).conns))
		eq(Rules.roadCount(S.configs[901].laneConnections), 16, "today's 16")
		ok(not S.kinds("APPLY")[1]:find("exit_fan", 1, true), S.kinds("APPLY")[1])
		ok(not S.kinds("SUMMARY")[1]:find("exitfan", 1, true), S.kinds("SUMMARY")[1])
	end
end)

test("zones: sl_exitfan zone: an existing lit junction with today's lanes and freed phases re-applied: indices in range", function()
	-- an earlier Always write: the rule's lanes, kerb turns out of every phase
	local G = crossGame(ALWAYS, "rule", true, true)
	local cfg = G.configs[901]
	local conns = cfg.laneConnections
	local lists = {}
	for i, st in ipairs(cfg.trafficLightConfig.states) do lists[i] = st.lockedLanes end
	local res = assert(LightsM.kerbPhases(conns, LightsM.kerbIndices(conns, G.kerb), 2, lists, LightsM.FREE))
	local states = gamePhases(conns)
	for i, st in ipairs(states) do st.lockedLanes = res[i] end
	cfg.trafficLightConfig = G.tlc(states)
	eq(kerbRed(G), 0, "freed before")
	zonesEvent(G, { op = "set", run = "e", zones = { zone(X901, 90, "sl_exitfan") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	eq(G.lightCmds, nil)
	eq(Rules.roadCount(G.configs[901].laneConnections), 24, "16 -> 24 (3-lane roads)")
	local nFree, nHeld = exitFanPhases(G, "re-applied", true)
	eq({ nFree, nHeld }, { 4, 4 })
	eq(#G.configs[901].trafficLightConfig.states, 2, "same phases")
	eq(#G.kinds("ERROR"), 0)
	-- built again: the fan is in place (same), nothing new to free
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1, "no second lane write")
	eq(G.lightCmds, nil, "phases already right")
	-- and back in an sl zone: today's lanes again, every index in range, the kerb turns freed
	zonesEvent(G, { op = "set", run = "s", zones = { zone(X901, 90, "sl") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 2)
	eq(Rules.roadCount(G.configs[901].laneConnections), 16, "20 -> 16")
	eq(kerbRed(G), 0, "today's Always")
	eq(#G.kinds("ERROR"), 0)
end)

test("zones: sl_exitfan zone: Light phases = Smart Lanes: no plan there (game phases re-pointed), the fan", function()
	local G = crossGame({ sqrl_free_turn = 3, sqrl_light_phases = 2 }, "default", true, true)
	zonesEvent(G, { op = "set", run = "e", zones = { zone(X901, 90, "sl_exitfan") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
	G.frames(15)
	eq(#G.sent, 1)
	eq(#G.kinds("PHASES"), 0, "no Smart Lanes plan in an sl_exitfan zone")
	eq(Rules.roadText(G.configs[901].laneConnections), Rules.roadText((exitFanConns())))
	exitFanPhases(G, "phases=sl", true)
	eq(#G.kinds("ERROR"), 0)
end)

test("zones: sl_exitfan zone: unknown light at the read: today's lanes, the fan once the light stands (re-check)", function()
	for _, params in ipairs({ ALWAYS, OFF }) do
		local G = crossGame(params, "default", false, false)
		zonesEvent(G, { op = "set", run = "e", zones = { zone(X901, 90, "sl_exitfan") } })
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
		G.frames(15)
		eq(#G.sent, 1)
		eq(Rules.roadCount(G.configs[901].laneConnections), 16, "unknown light: the rule")
		ok(G.kinds("APPLY")[1]:find(" exit_fan=lit_unknown", 1, true), G.kinds("APPLY")[1])
		-- the game adds its light and phases (for the connections in place)
		G.lights[901] = true
		G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
		G.frames(100)
		eq(#G.sent, 2, "the fan's lane write")
		eq(Rules.roadText(G.configs[901].laneConnections), Rules.roadText((exitFanConns())))
		exitFanPhases(G, "recheck", params == ALWAYS)
		local a = G.kinds("APPLY")
		ok(a[#a]:find("src=recheck", 1, true) and a[#a]:find(" exit_fan=yes", 1, true), a[#a])
		G.frames(700)
		eq(#G.sent, 2, "the later re-check leaves it")
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("job: a node whose step throws is logged (ERROR where=slip_step) and the job goes on with the next node", function()
	local G = crossGame(ALWAYS, "default", true, true)
	local plan = Slip.plan
	Slip.plan = function(world, n, ...)
		if n == 902 then error("boom") end
		return plan(world, n, ...)
	end
	local okRun, e = pcall(function()
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", crossBuild(G))
		G.frames(15)
	end)
	Slip.plan = plan
	ok(okRun, tostring(e))
	local errs = G.kinds("ERROR")
	ok(errs[1] ~= nil and errs[1]:find("where=slip_step", 1, true) ~= nil, tostring(errs[1]))
	eq(#G.sent, 1, "node 901 still written")
	ok(G.kinds("SUMMARY")[1] ~= nil, "the job finished")
end)

---------------------------------------------------------------------------
-- Stress Test bench additions (plans/square_stress_test/BENCH.md "What Smart Lanes must add", SL-1 .. SL-6)

local RING_NODES = { 22768, 23292, 23293, 23294 }

--- A zone covering the probe ring's arm junctions (mode ab, optional id label).
local function ringZone(G, ab, id)
	local sx, sy = 0, 0
	for _, n in ipairs(RING_NODES) do
		local p = G.world.node(n)
		sx, sy = sx + p.x, sy + p.y
	end
	local cx, cy = sx / #RING_NODES, sy / #RING_NODES
	local r = 0
	for _, n in ipairs(RING_NODES) do
		local p = G.world.node(n)
		r = math.max(r, math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2))
	end
	return { x = cx, y = cy, r = r + 40, ab = ab, id = id }
end

--- The ring game with its arm junctions lit (AUTO, a light standing), loaded.
local function litRing(params)
	local G = makeGame(params)
	for _, n in ipairs(RING_NODES) do
		G.configs[n].trafficLightPreference = G.TLP.AUTO
		G.lights[n] = true
	end
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	return G
end

test("SL-2: MODE says lights=on|off (the \"No lights at roundabouts and ramps\" setting)", function()
	for _, x in ipairs({ { {}, "on" }, { { sqrl_lights = 1 }, "on" }, { { sqrl_lights = 2 }, "off" } }) do
		local G = makeGame(x[1])
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		ok(G.kinds("MODE")[1]:find(" lights=" .. x[2] .. "$"), G.kinds("MODE")[1])
	end
end)

test("SL-1: an sl_keeplights zone keeps the ring's lights (LIGHTS to=kept, SUMMARY zone_keeplights= lights_kept=); lanes as sl", function()
	local K = litRing()
	zonesEvent(K, { op = "set", run = "k", zones = { ringZone(K, "sl_keeplights", "g1f") } })
	K.gs.handleEvent({}, K.state, "", "apply_command", "onPostBuildProposal", ringBuild(K))
	K.frames(20)
	eq(#K.sent, 1, "the lane proposal")
	eq(K.lightCmds, nil, "no light switched off")
	for _, n in ipairs(RING_NODES) do eq(K.lights[n], true) end
	local l = K.kinds("LIGHTS")
	eq(#l, 4, table.concat(l, "\n"))
	for _, x in ipairs(l) do ok(x:find("src=auto node=%d+ to=kept zone=sl_keeplights zid=g1f$"), x) end
	local sum = K.kinds("SUMMARY")[1]
	ok(sum:find(" zone_keeplights=4 lights_kept=4", 1, true), sum)
	K.frames(700)
	eq(K.lightCmds, nil, "the late look keeps them too")
	eq(#K.kinds("ERROR"), 0)
	-- the same ring in an sl zone: lights off, the same lanes
	local S = litRing()
	zonesEvent(S, { op = "set", run = "s", zones = { ringZone(S, "sl", "g1b") } })
	S.gs.handleEvent({}, S.state, "", "apply_command", "onPostBuildProposal", ringBuild(S))
	S.frames(20)
	eq(#S.lightCmds, 4)
	eq(Rules.connsText(S.sent[1].proposal.streetProposal.nodeConfigsToAdd[1].comp.laneConnections),
		Rules.connsText(K.sent[1].proposal.streetProposal.nodeConfigsToAdd[1].comp.laneConnections), "lanes as sl")
	ok(not S.kinds("SUMMARY")[1]:find("keeplights", 1, true), S.kinds("SUMMARY")[1])
	-- setting Off: nothing to keep, nothing logged
	local O = litRing({ sqrl_lights = 2 })
	zonesEvent(O, { op = "set", run = "o", zones = { ringZone(O, "sl_keeplights") } })
	O.gs.handleEvent({}, O.state, "", "apply_command", "onPostBuildProposal", ringBuild(O))
	O.frames(20)
	eq(#O.kinds("LIGHTS"), 0)
	ok(O.kinds("SUMMARY")[1]:find(" zone_keeplights=4 lights_kept=0", 1, true), O.kinds("SUMMARY")[1])
end)

test("SL-3: zid= on APPLY / LIGHTS / VERIFY-free lines of nodes in a zone with an id; SKIP kind=zone lists its zones' ids", function()
	local G = litRing()
	zonesEvent(G, { op = "set", run = "z", zones = { ringZone(G, "sl", "g2b") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	local a = G.kinds("APPLY")
	ok(#a > 0)
	for _, x in ipairs(a) do ok(x:find(" zid=g2b$"), x) end
	for _, x in ipairs(G.kinds("LIGHTS")) do ok(x:find(" zid=g2b$"), x) end
	ok(not G.kinds("WRITE")[1]:find("zid", 1, true), "lines without a node stay as they are")
	-- a game zone: the SKIP line names the ids
	local Gg = litRing()
	local z1, z2 = ringZone(Gg, "game", "g2a"), ringZone(Gg, "game", "g9a")
	z2.x = z2.x + 1e5
	zonesEvent(Gg, { op = "set", run = "g", zones = { z1, z2 } })
	Gg.gs.handleEvent({}, Gg.state, "", "apply_command", "onPostBuildProposal", ringBuild(Gg))
	Gg.frames(20)
	local sk = Gg.kinds("SKIP")[1]
	ok(sk:find("kind=zone zone=game job=1 nodes=%d+ reason=zone_game zid=g2a$"), sk)
	-- zones without ids: no zid anywhere
	local N = litRing()
	zonesEvent(N, { op = "set", run = "n", zones = { ringZone(N, "sl") } })
	N.gs.handleEvent({}, N.state, "", "apply_command", "onPostBuildProposal", ringBuild(N))
	N.frames(20)
	for _, x in ipairs(N.logs) do ok(not x:find("zid=", 1, true), x) end
end)

test("SL-4: zmodes and zrun on an accepted payload, zerr = the last refusal's run and reason", function()
	local G = litRing()
	zonesEvent(G, { op = "set", run = "ok1", zones = { ringZone(G, "sl_keeplights") } })
	local st = G.state:get()
	eq(st.zrun, "ok1")
	eq(st.zmodes, Zones.AB)
	eq(st.zerr, nil)
	zonesEvent(G, { op = "set", run = "bad1", zones = { ringZone(G, "sl_newmode") } })
	st = G.state:get()
	eq(st.zerr, { run = "bad1", reason = "ab1" })
	eq(st.zrun, "ok1", "the refused payload changed nothing else")
	eq(#st.zones, 1)
	zonesEvent(G, { op = "set", run = "ok2", zones = {} })
	eq(G.state:get().zerr, { run = "bad1", reason = "ab1" }, "the last refusal stays")
end)

--- Routes our GUI's script events (SL-5) into the game script's handleEvent, as the engine does.
local function routeEvents(G)
	G.events = {}
	G.api.cmd.makeScriptingSendEventCmd = function(_, id, name, param) return { event = { id = id, name = name, param = param } } end
	local send = G.api.cmd.sendCommand
	G.api.cmd.sendCommand = function(cmd, cb)
		if cmd.event ~= nil then
			G.events[#G.events + 1] = cmd.event
			G.gs.handleEvent({}, G.state, "", cmd.event.id, cmd.event.name, cmd.event.param)
			return
		end
		return send(cmd, cb)
	end
end

test("SL-5: qlen in the state while zones are set: jobs, light queue and pending verifies, 0 when idle", function()
	local G = litRing()
	routeEvents(G)
	zonesEvent(G, { op = "set", run = "q", zones = { ringZone(G, "sl", "g3b") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	eq(G.state:get().qlen, 1, "the new job, before the GUI took it")
	local most = 0
	for _ = 1, 60 do
		G.frames(1)
		most = math.max(most, G.state:get().qlen or 0)
	end
	ok(most >= 1, "busy: " .. most)
	G.frames(900)
	eq(G.state:get().qlen, 0, "idle")
	ok(#G.events >= 2, "reports sent")
	for _, e in ipairs(G.events) do eq(e.name, "SmartLanes.qlen") end
	-- the reports are throttled (one per 30 frames at most)
	ok(#G.events <= 1000 / 30 + 2, "throttled: " .. #G.events)
	eq(#G.kinds("ERROR"), 0)
end)

test("SL-5 / SL-6 off outside zones: no qlen, no report, no late lights look (the default stays as before)", function()
	local G = litRing()
	routeEvents(G)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	eq(#G.lightCmds, 4)
	-- the game puts a light back later: outside zones nothing looks again (as before)
	G.lights[22768], G.configs[22768].trafficLightPreference = true, G.TLP.AUTO
	G.frames(900)
	eq(#G.lightCmds, 4)
	eq(#G.events, 0, "no qlen report")
	local st = G.state:get()
	eq({ st.qlen, st.qgui, st.zmodes, st.zerr }, { nil, nil, nil, nil })
	eq(#G.kinds("RECHECK"), 0)
end)

test("SL-6: in a zone, a light the game puts back after the pass is switched off by the one late look; never again", function()
	local G = litRing()
	zonesEvent(G, { op = "set", run = "l", zones = { ringZone(G, "sl", "g4b") } })
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	eq(#G.lightCmds, 4)
	G.lights[22768], G.configs[22768].trafficLightPreference = true, G.TLP.AUTO
	G.frames(700)
	eq(#G.lightCmds, 5, "switched off again")
	eq(G.lights[22768], nil)
	local r = G.kinds("RECHECK")
	ok(r[1] and r[1]:find("kind=lights job=", 1, true) and r[1]:find(" nodes=4 lit=1 queued=1", 1, true), tostring(r[1]))
	-- the late entry has no late look of its own
	G.lights[22768], G.configs[22768].trafficLightPreference = true, G.TLP.AUTO
	G.frames(1500)
	eq(#G.lightCmds, 5, "bounded: once")
	eq(#G.kinds("RECHECK"), 1)
	eq(#G.kinds("ERROR"), 0)
end)

--- SL-3 check: every APPLY / SKIP / LIGHTS / PHASES / AUDIT line with node= carries zid=<id>; returns the kinds seen
-- ("APPLY kind=drop", "APPLY ring", "LIGHTS src=recheck", ...).
local function allZid(G, id, tag)
	local seen = {}
	for _, l in ipairs(G.logs) do
		local kind = l:match("^%[SQRL%] (%u+) ")
		if kind and (kind == "APPLY" or kind == "SKIP" or kind == "LIGHTS" or kind == "PHASES" or kind == "AUDIT")
			and l:find(" node=%d") then
			ok(l:find(" zid=" .. id .. "$") ~= nil, tag .. ": " .. l)
			local sub = l:match(" kind=(%S+)") or (l:find(" ring=", 1, true) and "ring") or "-"
			local src = l:match(" src=(%S+)") or "-"
			seen[kind .. " " .. sub .. " src=" .. src] = true
		end
	end
	return seen
end

local function bigZone(ab, id) return { x = 0, y = 0, r = 2000, ab = ab, id = id } end

test("SL-3: zid= on every line kind with a node in a zone: ring, drop, slip, cross, lights, phases, rechecks, audit", function()
	local seen = {}
	local function add(s) for k in pairs(s) do seen[k] = true end end
	-- ring (APPLY ring=, LIGHTS src=auto) and a lane drop (APPLY kind=drop) in one build
	local D = makeGame(nil, FX_DROP)
	D.lights[22768], D.configs[22768].trafficLightPreference = true, D.TLP.AUTO
	D.gs.update({}, D.state, 0.1)
	D.frames(1)
	zonesEvent(D, { op = "set", run = "d", zones = { bigZone("sl", "g1a") } })
	D.gs.handleEvent({}, D.state, "", "apply_command", "onPostBuildProposal", dropBuild(D, true))
	D.frames(30)
	add(allZid(D, "g1a", "ring+drop"))
	-- the Channelized T (slip nodes, their lights, the centre T, audit)
	local C = makeGame(nil, FX_CHANNEL)
	for id in pairs(C.configs) do C.configs[id].trafficLightPreference = C.TLP.AUTO end
	C.gs.update({}, C.state, 0.1)
	C.frames(1)
	zonesEvent(C, { op = "set", run = "c", zones = { bigZone("sl", "g2a") } })
	C.gs.handleEvent({}, C.state, "", "apply_command", "onPostBuildProposal", channelBuild(C))
	C.frames(30)
	add(allZid(C, "g2a", "channel"))
	-- a lit crossroads, Light phases = Smart Lanes (PHASES) and Always (free turn), then lanes already right (LIGHTS)
	for _, params in ipairs({ { sqrl_light_phases = 2 }, ALWAYS }) do
		local X = crossGame(params, "default", true, true)
		zonesEvent(X, { op = "set", run = "x", zones = { bigZone("sl", "g3a") } })
		X.gs.handleEvent({}, X.state, "", "apply_command", "onPostBuildProposal", crossBuild(X))
		X.frames(30)
		-- the game re-makes its phases: the same lanes, kerb turns red again (LIGHTS src=auto to=free_turn)
		X.configs[901].trafficLightConfig = X.tlc(gamePhases(X.configs[901].laneConnections))
		X.gs.handleEvent({}, X.state, "", "apply_command", "onPostBuildProposal", crossBuild(X))
		X.frames(30)
		add(allZid(X, "g3a", "cross"))
	end
	-- unknown light at the write, the light comes: the re-check (LIGHTS src=recheck) and the exit fan's (APPLY src=recheck)
	for _, ab in ipairs({ "sl", "sl_exitfan" }) do
		local R = crossGame(ALWAYS, "default", false, false)
		zonesEvent(R, { op = "set", run = "r", zones = { bigZone(ab, "g4a") } })
		R.gs.handleEvent({}, R.state, "", "apply_command", "onPostBuildProposal", crossBuild(R))
		R.frames(15)
		R.lights[901] = true
		R.configs[901].trafficLightConfig = R.tlc(gamePhases(R.configs[901].laneConnections))
		R.frames(700)
		add(allZid(R, "g4a", "recheck " .. ab))
	end
	-- a game zone: the SKIP kind=zone line (no node=, its own zid list) and an sl_keeplights zone (LIGHTS to=kept)
	local K = makeGame()
	K.lights[22768], K.configs[22768].trafficLightPreference = true, K.TLP.AUTO
	K.gs.update({}, K.state, 0.1)
	K.frames(1)
	zonesEvent(K, { op = "set", run = "k", zones = { bigZone("sl_keeplights", "g5f") } })
	K.gs.handleEvent({}, K.state, "", "apply_command", "onPostBuildProposal", ringBuild(K))
	K.frames(30)
	add(allZid(K, "g5f", "keeplights"))
	local list = {}
	for k in pairs(seen) do list[#list + 1] = k end
	table.sort(list)
	print("      zid on: " .. table.concat(list, "; "))
	for _, want in ipairs({ "APPLY ring src=-", "APPLY drop src=-", "APPLY slip src=-", "APPLY slip src=recheck",
		"LIGHTS - src=auto", "LIGHTS - src=recheck", "PHASES - src=auto", "AUDIT - src=auto" }) do
		ok(seen[want], "kind covered: " .. want)
	end
end)

test("bench: inside zones, nodes looked at and left unchanged log SKIP kind= node= reason=same|plain zid= once per job; outside none", function()
	local function run(zones)
		local D = makeGame(nil, FX_DROP)
		D.gs.update({}, D.state, 0.1)
		D.frames(1)
		if zones then zonesEvent(D, { op = "set", run = "p", zones = zones }) end
		for _ = 1, 2 do
			D.gs.handleEvent({}, D.state, "", "apply_command", "onPostBuildProposal", dropBuild(D, true))
			D.frames(30)
		end
		local X = crossGame(OFF, "rule", false, false)
		if zones then zonesEvent(X, { op = "set", run = "p", zones = zones }) end
		X.gs.handleEvent({}, X.state, "", "apply_command", "onPostBuildProposal", crossBuild(X))
		X.frames(30)
		return D, X
	end
	local D, X = run({ bigZone("sl", "g7a") })
	local function skips(G, pat)
		local out = {}
		for _, l in ipairs(G.kinds("SKIP")) do if l:find(pat) then out[#out + 1] = l end end
		return out
	end
	-- job 1: the drop is applied, the ring written; the plain road nodes 501, 503, 504 (dead ends, a plain node)
	local plain = skips(D, "reason=plain")
	for _, n in ipairs({ 501, 503, 504 }) do
		local c = 0
		for _, l in ipairs(plain) do if l:find("SKIP kind=node node=" .. n .. " reason=plain zid=g7a$") then c = c + 1 end end
		eq(c, 2, "node " .. n .. ": once per job (2 jobs)")
	end
	-- job 2: the drop and every ring junction already right
	local same = skips(D, "reason=same")
	ok(#skips(D, "^%[SQRL%] SKIP kind=drop node=502 reason=same zid=g7a$") == 1, table.concat(same, "\n"))
	local ringSame = skips(D, "^%[SQRL%] SKIP kind=ring ring=%S+ node=%d+ reason=same zid=g7a$")
	eq(#ringSame, 4, table.concat(same, "\n"))
	-- the crossroads already right
	eq(#skips(X, "^%[SQRL%] SKIP kind=cross node=901 reason=same zid=g7a$"), 1, table.concat(X.kinds("SKIP"), "\n"))
	-- once per node per job: no node twice in one job's same / plain lines
	local perJob, job = {}, 0
	for _, l in ipairs(D.logs) do
		if l:find("^%[SQRL%] SUMMARY ") then job = job + 1 end
		local nd = l:match("^%[SQRL%] SKIP kind=%S+ .*node=(%d+) reason=[sp][al][ma][ei]")
		if nd then
			local k = job .. ":" .. nd
			ok(not perJob[k], "once: " .. l)
			perJob[k] = true
		end
	end
	-- outside every zone: none of these lines (the default logs as before)
	local D0, X0 = run(nil)
	for _, G in ipairs({ D0, X0 }) do
		for _, l in ipairs(G.kinds("SKIP")) do
			ok(not l:find("reason=same", 1, true) and not l:find("reason=plain", 1, true), l)
		end
	end
	eq(#D0.kinds("SKIP"), 0)
	eq(#X0.kinds("SKIP"), 0)
	-- the same scenario in a zone without an id: the lines, without zid
	local Dn = run({ bigZone("sl") })
	ok(#Dn.kinds("SKIP") > 0)
	for _, l in ipairs(Dn.kinds("SKIP")) do ok(not l:find("zid=", 1, true), l) end
end)

---------------------------------------------------------------------------
-- Ring layout variants (zone modes sl_rturbo .. sl_rspread; PLAN.md "Ring layout variants (bench)")

--- A build that touches only ring junction 22768 (one arm segment at it), as a link road joining one arm.
local RingM = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"

local function oneArmBuild(G)
	local seg = nil
	for _, sid in ipairs(G.world.nodes[22768].segs) do
		local s = G.world.segs[sid]
		if not ({ [23299] = true, [23300] = true, [23301] = true, [23302] = true })[sid] then seg = s end
	end
	assert(seg ~= nil)
	local sp = { addedNodes = { { entity = 22768 } }, addedSegments = { { entity = seg.id, comp = { node0 = seg.node0, node1 = seg.node1 } } },
		nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

local function ringConfigs(G)
	local t = {}
	for _, n in ipairs(RING_NODES) do t[#t + 1] = n .. "=" .. Rules.connsText(G.configs[n].laneConnections) end
	return table.concat(t, "|")
end

test("ring variants (auto): a zone writes its variant on every junction (layout=, zone_ring=); a later one-arm build changes nothing", function()
	for _, variant in ipairs(Rules.RING_VARIANTS) do
		local G = makeGame()
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		zonesEvent(G, { op = "set", run = "v", zones = { ringZone(G, variant, "rv1") } })
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
		G.frames(20)
		-- sl_rmid2 (Rules.SPLIT_VARIANTS) splits this ring's stretches first (test_rmid2.lua has the whole flow)
		if Rules.SPLIT_VARIANTS[variant] then
			ok(#G.kinds("SPLIT") >= 1, variant .. ": SPLIT")
			eq(#G.kinds("ERROR"), 0)
		else
			local a = G.kinds("APPLY")
			ok(#a >= 1, variant)
			-- sl_rsplit / sl_rmid on this ring (no plain ring node between its junctions): written as sl_rspiral, one RSPLIT line why
			local written = Rules.MID_VARIANTS[variant] and Rules.MID_FALLBACK[variant] or variant
			for _, l in ipairs(a) do ok(l:find(" layout=" .. written .. " zid=rv1$"), l) end
			if Rules.MID_VARIANTS[variant] then
				local rs = G.kinds("RSPLIT")
				eq(#rs, 1)
				ok(rs[1]:find("mids=0 fallback=" .. written .. " reason=no_mid_nodes zid=rv1$"), rs[1])
			else
				eq(#G.kinds("RSPLIT"), 0, variant)
			end
			ok(G.kinds("SUMMARY")[1]:find(" zone_ring=1", 1, true), G.kinds("SUMMARY")[1])
			-- the expected connections: the plan of the whole ring with the variant
			local ring = assert(RingM.findRing(G.world, 22768))
			local want = Rules.planRing(G.world, ring, (function() local s = {} for rn in pairs(ring.nodeSet) do s[rn] = true end return s end)(),
				variant, function() return {} end)
			for _, r in ipairs(want.nodes) do
				eq(Rules.roadText(G.configs[r.node].laneConnections), Rules.roadText(r.conns), variant .. " node " .. r.node)
			end
			local after = ringConfigs(G)
			-- a later build joins one arm: the zone plans the whole ring again with the same rule: nothing changes
			G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G))
			G.frames(20)
			eq(ringConfigs(G), after, variant .. ": seed order does not matter")
			eq(#G.kinds("ERROR"), 0)
		end
	end
end)

test("ring variants (auto): outside the zones the default rule, on the whole ring: a later one-arm build keeps turbo (no flip)", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ringBuild(G))
	G.frames(20)
	local a = G.kinds("APPLY")
	for _, l in ipairs(a) do ok(not l:find("layout=", 1, true), l) end
	ok(not G.kinds("SUMMARY")[1]:find("zone_ring", 1, true), G.kinds("SUMMARY")[1])
	ok(a[1]:find(" turbo=true fresh=true", 1, true), a[1])
	local after, nApply = ringConfigs(G), #a
	-- the build at one arm rebuilds that junction (the engine's defaults there)
	G.configs[22768].laneConnections = Rules.engineDefault(RingM.nodeView(G.world, assert(RingM.findRing(G.world, 22768)), 22768))
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", oneArmBuild(G))
	G.frames(20)
	local a2 = G.kinds("APPLY")
	-- until 2026-10-13 this flipped the seed to matched (turbo=false fresh=false); the whole ring is planned now
	eq(#a2, nApply + 1)
	ok(a2[#a2]:find("node=22768 .* turbo=true fresh=true "), tostring(a2[#a2]))
	eq(ringConfigs(G), after, "back to the ring's turbo layout")
	-- a zone of another mode (sl) changes nothing either
	local S = makeGame()
	S.gs.update({}, S.state, 0.1)
	S.frames(1)
	zonesEvent(S, { op = "set", run = "s", zones = { ringZone(S, "sl", "rs1") } })
	S.gs.handleEvent({}, S.state, "", "apply_command", "onPostBuildProposal", ringBuild(S))
	S.frames(20)
	for _, l in ipairs(S.kinds("APPLY")) do ok(not l:find("layout=", 1, true), l) end
	ok(S.kinds("APPLY")[1]:find(" turbo=true fresh=true", 1, true), S.kinds("APPLY")[1])
	ok(not S.kinds("SUMMARY")[1]:find("zone_ring", 1, true), S.kinds("SUMMARY")[1])
end)

---------------------------------------------------------------------------
-- Nearby junctions stay as they are (PLAN.md "Nearby junctions stay as they are", user decision 2026-10-17): a build
-- leaves an existing junction it did not change alone (in-game: session 2026-10-17_2159_sqrl-sqsg, node 32350)

--- Segment `id` of the fake world as an event's SegmentAndEntity (its BaseEdge as the fake game reads it).
local function segEntry(G, id)
	return { entity = id, type = 0, comp = G.api.engine.getComponent(id, G.api.type.ComponentType.BASE_EDGE) }
end

--- Adds segment id (n0 to n1, lanes) to the fake world.
local function addSeg(G, id, n0, n1, lanes)
	local W = G.world
	local p, q = W.nodes[n0], W.nodes[n1]
	local d = { x = q.x - p.x, y = q.y - p.y }
	W.segs[id] = { id = id, node0 = n0, node1 = n1, lanes = lanes, p0 = { x = p.x, y = p.y }, p1 = { x = q.x, y = q.y },
		t0 = d, t1 = { x = d.x, y = d.y } }
	table.insert(p.segs, id)
	table.insert(q.segs, id)
end

--- Takes segment id out of the fake world. Returns its event entry (read before).
local function removeSeg(G, id)
	local W = G.world
	local e = segEntry(G, id)
	local s = W.segs[id]
	W.segs[id] = nil
	for _, nd in ipairs({ W.nodes[s.node0], W.nodes[s.node1] }) do
		for i = #nd.segs, 1, -1 do
			if nd.segs[i] == id then table.remove(nd.segs, i) end
		end
	end
	return e, s
end

--- The lanes of a segment drawn the other way (reversed, each lane's direction flipped).
local function flipLanes(lanes)
	local out = {}
	for i = #lanes, 1, -1 do
		local l = lanes[i]
		out[#out + 1] = { forward = not l.forward, road = l.road, car = l.car, tram = l.tram, walk = l.walk }
	end
	return out
end

--- A road joined partway along segment `old` (a to b), as the game builds it: `old` is replaced by ids.pa (a to the new
-- node ids.m halfway; o.flip: drawn from m to a) and ids.pb (m to b), and the new road ids.road runs from m to the
-- new node ids.far (dx, dy from m). The world follows; returns the build event (the end configs re-pointed in
-- nodeConfigsToAdd, as the engine's proposal dump of 2026-10-17).
local function joinPartway(G, old, ids, dx, dy, o)
	local W = G.world
	local before, s = removeSeg(G, old)
	local a, b = W.nodes[s.node0], W.nodes[s.node1]
	W.nodes[ids.m] = { id = ids.m, x = (a.x + b.x) / 2, y = (a.y + b.y) / 2, segs = {} }
	W.nodes[ids.far] = { id = ids.far, x = W.nodes[ids.m].x + dx, y = W.nodes[ids.m].y + dy, segs = {} }
	if o and o.flip then addSeg(G, ids.pa, ids.m, s.node0, flipLanes(s.lanes)) else addSeg(G, ids.pa, s.node0, ids.m, s.lanes) end
	addSeg(G, ids.pb, ids.m, s.node1, s.lanes)
	addSeg(G, ids.road, ids.m, ids.far, s.lanes)
	local sp = { addedNodes = { { entity = ids.m }, { entity = ids.far } },
		addedSegments = { segEntry(G, ids.pa), segEntry(G, ids.pb), segEntry(G, ids.road) },
		removedSegments = { before }, removedNodes = {},
		nodeConfigsToAdd = { { entity = s.node0 }, { entity = s.node1 }, { entity = ids.m }, { entity = ids.far } },
		nodeConfigsToRemove = { s.node0, s.node1 } }
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

--- The engine's re-pointing of node n's config from segment `from` onto `to` (findings roads.md "A replaced arm keeps
-- the junction's lanes"): the same connections and phases, the replaced segment's id swapped.
local function repoint(G, n, from, to)
	for _, c in ipairs(G.configs[n].laneConnections) do
		if c.segment0 == from then c.segment0 = to end
		if c.segment1 == from then c.segment1 = to end
	end
end

local function linesFor(G, kind, n)
	local out = {}
	for _, l in ipairs(G.kinds(kind)) do
		if l:find(" node=" .. n .. " ", 1, true) then out[#out + 1] = l end
	end
	return out
end

test("nearby junctions: a road joined partway along an arm leaves the existing lit crossroads at its far end alone", function()
	for _, flip in ipairs({ false, true }) do
		local G = crossGame({}, "default", true, true)
		local states = #G.configs[901].trafficLightConfig.states
		local ev = joinPartway(G, 911, { m = 950, far = 960, pa = 921, pb = 922, road = 923 }, 0, 60, { flip = flip })
		repoint(G, 901, 911, 921)
		local before = Rules.roadText(G.configs[901].laneConnections)
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ev)
		eq(G.state:get().jobs[1].quiet, { 901, 902 }, "the far end and the dead end are quiet")
		G.frames(30)
		eq(#linesFor(G, "APPLY", 901), 0, "no APPLY at the crossroads (flip=" .. tostring(flip) .. ")")
		local skip = linesFor(G, "SKIP", 901)
		eq(#skip, 1)
		ok(skip[1]:find("kind=cross node=901 reason=unchanged", 1, true), skip[1])
		for _, cmd in ipairs(G.sent) do
			for _, e in ipairs(cmd.proposal.streetProposal.nodeConfigsToAdd or {}) do ok(e.entity ~= 901, "901 not written") end
		end
		for _, c in ipairs(G.lightCmds or {}) do ok(c.node ~= 901, "901's lights not touched") end
		eq(Rules.roadText(G.configs[901].laneConnections), before)
		eq(#G.configs[901].trafficLightConfig.states, states)
		local sum = G.kinds("SUMMARY")
		ok(#sum == 1 and sum[1]:find("skips=[^ ]*unchanged:1"), tostring(sum[1]))
		eq(#G.kinds("ERROR"), 0)
	end
end)

test("nearby junctions: a road joined directly onto the crossroads, an arm upgraded to another road or a stop placed on an arm: handled", function()
	-- an arm built onto the junction (no segment replaced there)
	local G = crossGame({}, "default", true, true)
	local sp = { addedNodes = { { entity = 905 } }, addedSegments = { segEntry(G, 914) }, removedSegments = {},
		nodeConfigsToAdd = { { entity = 901 }, { entity = 905 } }, nodeConfigsToRemove = { 901 } }
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	eq(G.state:get().jobs[1].quiet, nil)
	G.frames(30)
	eq(#linesFor(G, "APPLY", 901), 1)
	eq(#G.kinds("ERROR"), 0)
	-- the west arm upgraded from large to medium (the street upgrade tool replaces the segment, same ends)
	local U = crossGame({}, "default", true, true)
	local old, s = removeSeg(U, 911)
	addSeg(U, 931, s.node0, s.node1, F.lanes(F.TPL.medium))
	local up = { addedNodes = {}, addedSegments = { segEntry(U, 931) }, removedSegments = { old },
		nodeConfigsToAdd = { { entity = 901 }, { entity = 902 } }, nodeConfigsToRemove = { 901, 902 } }
	U.gs.handleEvent({}, U.state, "", "apply_command", "onPostBuildProposal", { { proposal = up, toAdd = {} }, {}, {}, true })
	eq(U.state:get().jobs[1].quiet, nil, "an arm with another road: changed")
	U.frames(30)
	eq(#linesFor(U, "APPLY", 901), 1)
	eq(#U.kinds("ERROR"), 0)
	-- a street stop placed on the west arm (it rebuilds that piece, same road): the stop may open exit lanes
	-- (PLAN.md "Open exit lanes near stops and close junctions"), so the junction is handled
	local S = crossGame({}, "default", true, true)
	local old2, s2 = removeSeg(S, 911)
	addSeg(S, 932, s2.node0, s2.node1, s2.lanes)
	S.world.segs[932].objects = { { 7001, S.EOT.STOP_RIGHT } }
	S.edgeObjects[7001] = { param = 0.4 }
	local st = { addedNodes = {}, addedSegments = { segEntry(S, 932) }, removedSegments = { old2 },
		nodeConfigsToAdd = { { entity = 901 }, { entity = 902 } }, nodeConfigsToRemove = { 901, 902 } }
	S.gs.handleEvent({}, S.state, "", "apply_command", "onPostBuildProposal", { { proposal = st, toAdd = {} }, {}, {}, true })
	eq(S.state:get().jobs[1].quiet, nil, "a stop placed: no quiet node")
	S.frames(30)
	eq(#linesFor(S, "APPLY", 901), 1)
	eq(#S.kinds("ERROR"), 0)
end)

test("nearby junctions: a quiet junction in a job merged with a build that changed it is handled", function()
	local G = crossGame({}, "default", true, true)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal",
		joinPartway(G, 911, { m = 950, far = 960, pa = 921, pb = 922, road = 923 }, 0, 60))
	repoint(G, 901, 911, 921)
	local sp = { addedNodes = { { entity = 905 } }, addedSegments = { segEntry(G, 914) }, removedSegments = {},
		nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", { { proposal = sp, toAdd = {} }, {}, {}, true })
	G.frames(30)
	eq(#linesFor(G, "APPLY", 901), 1)
	eq(#linesFor(G, "SKIP", 901), 0)
	ok(G.kinds("SUMMARY")[1]:find(" merged=2", 1, true), G.kinds("SUMMARY")[1])
	eq(#G.kinds("ERROR"), 0)
end)

test("nearby junctions: Smart Lanes' lanes kept by the engine at a quiet crossroads: no lane write, its curb turns freed again", function()
	-- the engine carried the lanes over re-pointed and made the game's phases again (session 2026-10-14_1729, job 8)
	local G = crossGame(ALWAYS, "rule", true, true)
	-- a long west arm, so the new T stays beyond the open-exit distance (sl_cross X.OPEN_M) and the rule's lanes hold
	local W = G.world
	W.nodes[902].x = -400
	W.segs[911].p1 = { x = -400, y = -800 }
	W.segs[911].t0, W.segs[911].t1 = { x = -400, y = 0 }, { x = -400, y = 0 }
	G.configs[901].laneConnections = Slip.plan(W, 901, function() return {} end).conns
	local ev = joinPartway(G, 911, { m = 950, far = 960, pa = 921, pb = 922, road = 923 }, 0, 60)
	repoint(G, 901, 911, 921)
	G.configs[901].trafficLightConfig = G.tlc(gamePhases(G.configs[901].laneConnections))
	ok(kerbRed(G) > 0)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ev)
	G.frames(30)
	eq(#linesFor(G, "APPLY", 901), 0)
	eq(#linesFor(G, "SKIP", 901), 0)
	for _, cmd in ipairs(G.sent) do
		for _, e in ipairs(cmd.proposal.streetProposal.nodeConfigsToAdd or {}) do ok(e.entity ~= 901, "901's lanes not written") end
	end
	local l = linesFor(G, "LIGHTS", 901)
	eq(#l, 1)
	ok(l[1]:find("src=auto node=901 to=free_turn", 1, true), l[1])
	eq(kerbRed(G), 0)
	eq(#G.kinds("ERROR"), 0)
end)

test("nearby junctions: a ring junction reached only through a replaced arm segment: the whole ring, no light switched", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	local ring = assert(RingM.findRing(G.world, 22768))
	local arm = nil
	for _, sid in ipairs(G.world.nodes[23293].segs) do
		if not ring.segSet[sid] then arm = sid end
	end
	assert(arm ~= nil)
	G.lights[23293] = true
	local ev = joinPartway(G, arm, { m = 950, far = 960, pa = 921, pb = 922, road = 923 }, 40, 40)
	repoint(G, 23293, arm, 921)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ev)
	local q = G.state:get().jobs[1].quiet
	ok(q ~= nil and q[1] == 23293, "23293 is quiet")
	G.frames(40)
	local ringSent = nil
	for _, cmd in ipairs(G.sent) do
		if #(cmd.proposal.streetProposal.nodeConfigsToAdd or {}) == 4 then ringSent = cmd end
	end
	ok(ringSent ~= nil, "one proposal with the ring's four junctions")
	local a = {}
	for _, l in ipairs(G.kinds("APPLY")) do
		if l:find("ring=", 1, true) then a[#a + 1] = l end
	end
	eq(#a, 4)
	for _, l in ipairs(a) do ok(l:find(" turbo=true fresh=true ", 1, true), l) end
	for _, c in ipairs(G.lightCmds or {}) do ok(c.node ~= 23293, "the quiet junction keeps its light") end
	eq(#G.kinds("ERROR"), 0)
end)

test("nearby junctions: a hand-edited ring junction reached only through a replaced arm: the ring is left alone", function()
	local G = makeGame()
	G.gs.update({}, G.state, 0.1)
	G.frames(1)
	local ring = assert(RingM.findRing(G.world, 22768))
	local arm = nil
	for _, sid in ipairs(G.world.nodes[23293].segs) do
		if not ring.segSet[sid] then arm = sid end
	end
	-- the player edited 23293 with the Crossing Tool (one connection less)
	local list = {}
	for i, c in ipairs(G.configs[23293].laneConnections) do if i > 1 then list[#list + 1] = c end end
	G.configs[23293].laneConnections = list
	local ev = joinPartway(G, arm, { m = 950, far = 960, pa = 921, pb = 922, road = 923 }, 40, 40)
	repoint(G, 23293, arm, 921)
	local edited = Rules.roadText(G.configs[23293].laneConnections)
	G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", ev)
	G.frames(40)
	for _, cmd in ipairs(G.sent) do
		for _, e in ipairs(cmd.proposal.streetProposal.nodeConfigsToAdd or {}) do ok(not ring.nodeSet[e.entity], "ring node written") end
	end
	local skip = G.kinds("SKIP")
	ok(#skip >= 1 and skip[1]:find("ring=22768 node=23293 reason=hand_edit$"), tostring(skip[1]))
	eq(Rules.roadText(G.configs[23293].laneConnections), edited)
	-- left alone as a whole: not planned at all (so no mid-node split either)
	ok(G.kinds("SUMMARY")[1]:find(" rings=0 ", 1, true), G.kinds("SUMMARY")[1])
	eq(#G.kinds("ERROR"), 0)
end)
