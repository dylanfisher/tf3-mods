-- stress_probes.tl: the Probe tab's button list covers RESEARCH.md open probes 1-8, probe 9
-- (private car traffic, PROBES_TRAFFIC.md), probe 10 (bus lines, PROBES_BUSLINES.md) and probe 11 (Flow, FLOW.md), ids are unique, and loading the module calls no engine API
-- (nothing runs until a button is pressed).

before_each(function()
	reset_modules()
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
end)

test("one or more buttons per open probe 1-11, unique ids, all callable", function()
	local probes = ug_require "square_stress_test::/stress/gui/stress_probes.tl"
	local seen, perProbe = {}, {}
	for _, p in ipairs(probes.list) do
		ok(not seen[p.id], "duplicate id " .. p.id)
		seen[p.id] = true
		eq(type(p.run), "function")
		ok(#p.label > 0 and #p.tooltip > 0, p.id .. " has label and tooltip")
		local n = tonumber(p.id:match("^p(%d+)_"))
		ok(n ~= nil, "id names its probe number: " .. p.id)
		perProbe[n] = (perProbe[n] or 0) + 1
	end
	for n = 1, 11 do ok(perProbe[n] ~= nil, "probe " .. n .. " has a button") end
	eq(perProbe[9], 5)
	eq(perProbe[10], 4)
	eq(perProbe[11], 8)
	eq(#probes.list, 31)
end)

test("streetEdgesNear: octree BASE_EDGE query, counts only edges with a BASE_EDGE_STREET", function()
	local probes = ug_require "square_stress_test::/stress/gui/stress_probes.tl"
	local query
	set_global("api", {
		type = {
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			ComponentType = { BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET" },
		},
		engine = {
			util = { octree = { findEntitiesInCircle = function(c, r, t)
				query = { c.x, c.y, r, t }
				return { 11, 12, 13, 14 }
			end } },
			getComponent = function(e, t)
				eq(t, "BASE_EDGE_STREET")
				if e == 12 or e == 14 then return {} end -- 11, 13 are tracks
				return nil
			end,
			-- must not be used: throws in game for BASE_EDGE_STREET
			getEntitiesWithComponent = function() error("Cannot loop over this component type") end,
		},
	})
	local n, first = probes.streetEdgesNear(100, 200, 600)
	eq(n, 2)
	eq(first, 12)
	eq(query, { 100, 200, 600, "BASE_EDGE" })
	api.engine.util.octree.findEntitiesInCircle = function() error("boom") end
	eq(probes.streetEdgesNear(0, 0, 10), -1)
end)

-- Probe 9 against a fake api: runs the button, then ticks the runtime queue.
local function probeApi(extra)
	local T = 0
	local a = {
		type = {
			Clock = { new = function() return { getTime = function() T = T + 1000 return T end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			enum = { MoveMode = { WALK = 0, DRIVE = 1, LINES = 2 } },
		},
		gui = { camera = { getCameraData = function() return { x = 10, y = 20 } end } },
		cmd = { sendCommand = function(cmd, cb) cb({}, true, {}) end },
		engine = {
			terrain = { isValidCoordinate = function() return true end },
			entityExists = function() return true end,
			getComponent = function() return nil end,
			getEntitiesWithComponent = function() return {} end,
			util = { getPlayer = function() return 7 end, finance = { getPlayersBalance = function() return 1 end },
				octree = { findEntitiesInCircle = function() return {} end } },
			system = { simPersonSystem = { getCount = function() return 0 end } },
		},
	}
	for k, v in pairs(extra or {}) do a[k] = v end
	return a
end

local function runProbe(id, fakeApi)
	local probes = ug_require "square_stress_test::/stress/gui/stress_probes.tl"
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	set_global("api", fakeApi)
	rt.notificationsSent = true
	clear_logs()
	for _, p in ipairs(probes.list) do if p.id == id then p.run() end end
	for _ = 1, 5 do rt.tick() end
	local lines = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQST-PROBE]", 1, true) then lines[#lines + 1] = e.msg end
	end
	return lines
end

test("9b without api.cmd.debug: one clean fail line, no command sent", function()
	local sent = 0
	local a = probeApi()
	a.cmd = { sendCommand = function() sent = sent + 1 end }
	local lines = runProbe("p9_jump_home", a)
	eq(#lines, 1)
	ok(lines[1]:find("^%[SQST%-PROBE%] simperson_setstate_2 fail api.cmd.debug=false") ~= nil, lines[1])
	eq(sent, 0)
end)

test("9b with debug but no driver found: clean fail line naming the search", function()
	local a = probeApi()
	a.cmd.debug = { makeSimPersonSetStateCmd = function(e, s) return { e = e, s = s } end }
	local lines = runProbe("p9_jump_home", a)
	eq(#lines, 1)
	ok(lines[1]:find("simperson_setstate_2 fail no person driving", 1, true) ~= nil, lines[1])
end)

test("9a census counts persons by lastMoveMode and drivers on the road", function()
	local persons = {
		[1] = { sp = { lastMoveMode = 1 }, path = true },                    -- driving
		[2] = { sp = { lastMoveMode = 1 }, path = true, atVeh = true },      -- DRIVE but seated
		[3] = { sp = { lastMoveMode = 0 }, path = true },
		[4] = { sp = { lastMoveMode = 2 } },
	}
	local a = probeApi()
	a.engine.getEntitiesWithComponent = function(ct)
		if ct == "SIM_PERSON" then return { 1, 2, 3, 4 } end
		if ct == "LAND_VEHICLE" then error("Cannot loop over this component type") end
		return { 100 }
	end
	a.engine.getComponent = function(e, ct)
		local p = persons[e]
		if not p then return nil end
		if ct == "SIM_PERSON" then return p.sp end
		if ct == "MOVE_PATH" then return p.path and { state = 1, path = { edges = { {}, {} } }, dyn = { speed = 5 }, blocked = 0 } or nil end
		if ct == "SIM_PERSON_AT_VEHICLE" then return p.atVeh and {} or nil end
		return nil
	end
	a.engine.system.simPersonSystem.getCount = function() return 4 end
	local lines = runProbe("p9_census", a)
	eq(#lines, 1)
	local l = lines[1]
	ok(l:find("simperson_census ok iter=getEntitiesWithComponent total=4 scanned=4", 1, true) ~= nil, l)
	ok(l:find("byLastMoveMode={DRIVE=2,LINES=1,WALK=1}", 1, true) ~= nil, l)
	ok(l:find("drivingNow(DRIVE+MOVE_PATH-AT_VEHICLE)=1", 1, true) ~= nil, l)
	ok(l:find("LAND_VEHICLE=not iterable TRANSPORT_VEHICLE=1", 1, true) ~= nil, l)
	ok(l:find("firstDriver=1", 1, true) ~= nil, l)
end)

test("9b sends the state command to drivers found near the camera, reports after 15 s", function()
	local a = probeApi()
	local cmds = {}
	a.cmd.debug = { makeSimPersonSetStateCmd = function(e, s) cmds[#cmds + 1] = { e, s } return {} end }
	a.engine.util.octree.findEntitiesInCircle = function() return { 50 } end
	a.engine.system.simPersonSystem.getSimPersonsMovingForTransportNetwork = function(edge)
		eq(edge, 50)
		return { 1, 2 }
	end
	a.engine.getComponent = function(e, ct)
		if e == 50 and ct == "BASE_EDGE_STREET" then return {} end
		if e == 1 and ct == "SIM_PERSON" then return { lastMoveMode = 1 } end
		if e == 1 and ct == "MOVE_PATH" then return {} end
		if e == 2 and ct == "SIM_PERSON" then return { lastMoveMode = 0 } end
		return nil
	end
	local probes = ug_require "square_stress_test::/stress/gui/stress_probes.tl"
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	set_global("api", a)
	rt.notificationsSent = true
	clear_logs()
	for _, p in ipairs(probes.list) do if p.id == "p9_new_path" then p.run() end end
	-- the fake clock advances 1 ms per read: tick until the 15 s follow-up has run
	local lines = {}
	for _ = 1, 20000 do
		rt.tick()
		for _, e in ipairs(log_entries()) do
			if e.msg:find("[SQST-PROBE]", 1, true) then lines[#lines + 1] = e.msg end
		end
		if #lines > 0 then break end
	end
	eq(cmds, { { 1, 1 } })
	eq(#lines, 1)
	ok(lines[1]:find("simperson_setstate_1 ok state=1 (new path) picked=1 from near camera", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("callbacks=1 succeeded=1", 1, true) ~= nil, lines[1])
end)

-- Probe 10 (bus lines) against a fake api -------------------------------------------------------

-- Runs a button and ticks the queue until the first [SQST-PROBE] line (the fake clock advances 1 ms
-- per read, so delayed follow-ups need many ticks).
local function runUntilProbe(id, fakeApi)
	local probes = ug_require "square_stress_test::/stress/gui/stress_probes.tl"
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	set_global("api", fakeApi)
	rt.notificationsSent = true
	clear_logs()
	for _, p in ipairs(probes.list) do if p.id == id then p.run() end end
	local lines = {}
	for _ = 1, 50000 do
		rt.tick()
		for _, e in ipairs(log_entries()) do
			if e.msg:find("[SQST-PROBE]", 1, true) then lines[#lines + 1] = e.msg end
		end
		if #lines > 0 then break end
	end
	return lines
end

-- A world with one straight street edge 50 from node 1 (0,0) to node 2 (100,0) near the camera.
local function busApi()
	local a = probeApi()
	local T = a.type
	T.Vec4f = { new = function(x, y, z, w) return { x, y, z, w } end }
	T.Mat4f = { new = function(c1, c2, c3, c4) return { c1, c2, c3, c4 } end }
	T.SimpleProposal = { new = function() return { streetProposal = {} } end,
		ConstructionEntity = { new = function() return {} end } }
	T.SimpleStreetProposal = { EdgeObject = { new = function() return {} end } }
	T.SegmentAndEntity = { new = function() return { comp = {} } end }
	T.NodeAndEntity = { new = function() return { comp = {} } end }
	T.BaseNodeLaneConnectionAndEntity = { new = function() return {} end }
	T.enum.EdgeObjectType = { STOP_LEFT = 0, STOP_RIGHT = 1, SIGNAL = 2 }
	T.enum.Carrier = { ROAD = 0 }
	T.enum.TransportMode = { BUS = 5 }
	a.world = {
		[50] = { BASE_EDGE = function() return { node0 = 1, node1 = 2, objects = {},
			tangent0 = { x = 100, y = 0, z = 0 }, tangent1 = { x = 100, y = 0, z = 0 } } end,
			BASE_EDGE_STREET = function() return {} end },
		[1] = { BASE_NODE = function() return { position = { x = 0, y = 0, z = 0 } } end },
		[2] = { BASE_NODE = function() return { position = { x = 100, y = 0, z = 0 } } end },
	}
	a.lists = {}
	a.sent = {}
	a.onSend = function(cmd) return true, {}, {} end
	a.engine.getComponent = function(e, ct)
		local w = a.world[e]
		return w and w[ct] and w[ct]() or nil
	end
	a.engine.getEntitiesWithComponent = function(ct) return a.lists[ct] or {} end
	a.engine.util.octree.findEntitiesInCircle = function(_c, _r, ct) return ct == "BASE_EDGE" and { 50 } or {} end
	a.engine.util.getYear = function() return 2000 end
	a.engine.terrain.getHeightAt = function() return 0 end
	a.engine.system.streetConnectorSystem = { getConstructionEntityForEdge = function() return -1 end }
	a.cmd = {
		makeWorldBuildProposalCmd = function(p) return { proposal = p } end,
		sendCommand = function(cmd, cb)
			a.sent[#a.sent + 1] = cmd
			local success, data, res = a.onSend(cmd)
			cb(data, success, res)
		end,
	}
	return a
end

test("10a-10d with no street edges, stops or depots: one clean fail line each, nothing sent", function()
	for _, case in ipairs({
		{ "p10_stop", "bus_stop_on_street fail no eligible street edge near the camera: edges(r=300m)=0" },
		{ "p10_stop_pair", "bus_stop_pair fail no two eligible street edges 300-600 m apart" },
		{ "p10_depot", "road_depot_here fail no eligible street edge near the camera" },
		{ "p10_line", "bus_line_from_pair fail groups={} (newest near camera (0 groups" },
	}) do
		local a = probeApi()
		local sent = 0
		a.cmd = { sendCommand = function() sent = sent + 1 end }
		a.engine.system.streetConnectorSystem = { getConstructionEntityForEdge = function() return -1 end }
		local lines = runProbe(case[1], a)
		eq(#lines, 1, case[1])
		ok(lines[1]:find(case[2], 1, true) ~= nil, lines[1])
		eq(sent, 0, case[1])
	end
end)

test("10d without stops or depot names what is missing", function()
	local lines = runProbe("p10_line", probeApi())
	ok(lines[1]:find("needs two stops and a road depot (run 10b and 10c first)", 1, true) ~= nil, lines[1])
end)

test("10b with a single edge finds no pair", function()
	local lines = runUntilProbe("p10_stop_pair", busApi())
	eq(#lines, 1)
	ok(lines[1]:find("bus_stop_pair fail no two eligible", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("eligible=1", 1, true) ~= nil, lines[1])
end)

test("10a replaces the edge by a copy carrying a right-side stop and reports the new station group", function()
	local a = busApi()
	a.lists.STATION_GROUP = { 7 }
	a.onSend = function(cmd)
		a.lists.STATION_GROUP = { 7, 99 }
		return true, {}, {}
	end
	local lines = runUntilProbe("p10_stop", a)
	eq(#lines, 1)
	local l = lines[1]
	ok(l:find("bus_stop_on_street ok edges(r=300m)=1 eligible=1", 1, true) ~= nil, l)
	ok(l:find("edge=50 len=100m mid=50,0 model=::/stations/street/small_stops/small_new.con", 1, true) ~= nil, l)
	ok(l:find("variant=A(objects) success=true", 1, true) ~= nil, l)
	ok(l:find("STATION_GROUP 1->2 new={99}", 1, true) ~= nil, l)
	ok(l:find("group=99", 1, true) ~= nil, l)
	eq(#a.sent, 1)
	local sp = a.sent[1].proposal.streetProposal
	eq(sp.edgesToRemove, { 50 })
	local seg = sp.edgesToAdd[1]
	eq(seg.entity, -1)
	eq(seg.type, 0)
	eq({ seg.comp.node0, seg.comp.node1 }, { 1, 2 })
	eq(seg.comp.objects, { { -400000000, 1 } })
	local eo = sp.edgeObjectsToAdd[1]
	eq({ eo.edgeEntity, eo.param, eo.left, eo.oneWay, eo.playerEntity }, { -1, 0.5, false, false, 7 })
	-- the edge's end nodes have no config here (a script-made node): each gets a fresh one, add only
	local cfgNodes = {}
	for _, e in ipairs(sp.nodeConfigsToAdd) do cfgNodes[#cfgNodes + 1] = e.entity end
	table.sort(cfgNodes)
	eq(cfgNodes, { 1, 2 })
	eq(sp.nodeConfigsToRemove, {})
end)

test("4 Build street here: both new nodes get an (empty) node config", function()
	local a = busApi()
	a.type.Context = { new = function() return {} end }
	a.type.enum.BaseEdgeType = { NORMAL = 0 }
	a.type.enum.RoadType = { STREET = 0 }
	a.res = { streetTemplateRep = { find = function(p) return p end, get = function() return { laneConfigs = { 1, 2, 3, 4 }, streetStyle = "s" } end } }
	runUntilProbe("p4_street", a)
	ok(#a.sent >= 1, "sent")
	local sp = a.sent[1].proposal.streetProposal
	local got = {}
	for _, e in ipairs(sp.nodeConfigsToAdd) do got[#got + 1] = { e.entity, #e.comp.laneConnections } end
	table.sort(got, function(x, y) return x[1] < y[1] end)
	eq(got, { { -4, 0 }, { -3, 0 } })
end)

test("10a falls back to variant B (no comp.objects) when A fails", function()
	local a = busApi()
	a.onSend = function(cmd)
		local objs = cmd.proposal.streetProposal.edgesToAdd[1].comp.objects
		return #objs == 0, {}, {}
	end
	local lines = runUntilProbe("p10_stop", a)
	eq(#a.sent, 2)
	ok(lines[1]:find("variant=B(no objects)", 1, true) ~= nil, lines[1])
	-- no new station group in this fake: a clean fail
	ok(lines[1]:find("bus_stop_on_street fail", 1, true) ~= nil, lines[1])
end)

test("10c builds the depot facing the street (no -0 in the transform), finds it by the VEHICLE_DEPOT diff, then splits the edge and connects it", function()
	local a = busApi()
	a.lists.VEHICLE_DEPOT = {}
	-- depot construction 700: entrance edge 60 from free node 10 (at the target) to frozen node 11
	a.world[700] = { CONSTRUCTION = function() return { depots = { 800 }, frozenNodes = { 11 }, frozenEdges = { 60 },
		transf = { [13] = 50, [14] = -65, [15] = 0 } } end }
	a.world[60] = { BASE_EDGE = function() return { node0 = 10, node1 = 11 } end }
	a.world[10] = { BASE_NODE = function() return { position = { x = 50, y = -30, z = 0 } } end }
	a.world[11] = { BASE_NODE = function() return { position = { x = 50, y = -44.7, z = 0 } } end }
	-- the depot maps to its construction; resultEntities[1][1] is some other entity (fifth run)
	a.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function(d) eq(d, 800) return 700 end
	a.world[800] = { VEHICLE_DEPOT = function() return { carrier = 0, inNodes = { {} }, outNodes = {} } end }
	local node2edges = { [10] = { 60 } }
	a.engine.system.streetSystem = { getNode2StreetEdgeMap = function() return node2edges end }
	a.onSend = function(cmd)
		local p = cmd.proposal
		if p.constructionsToAdd then
			a.lists.VEHICLE_DEPOT = { 800 }
			return true, {}, { { 10438, 1 }, { 700, 1 } }
		end
		node2edges[10] = { 60, 61 }
		return true, {}, {}
	end
	local lines = runUntilProbe("p10_depot", a)
	eq(#lines, 1)
	local l = lines[1]
	ok(l:find("road_depot_here ok", 1, true) ~= nil, l)
	ok(l:find("spots=24 tried=1 pre={unavailable=1} sent=1 [e50 t=0.50 R30 origin=50.0,-65.0,0.0 success=true]", 1, true) ~= nil, l)
	ok(l:find("VEHICLE_DEPOT +1 new=[800(con=700 0m nodes=true)] (total 1) result=2{10438:?,700:con}", 1, true) ~= nil, l)
	ok(l:find("depot=800 construction=700 frozenNodes=1 frozenEdges=1 freeNode=10 at 50.0,-30.0 (0.0m from target)", 1, true) ~= nil, l)
	ok(l:find("streetEdges at node 1->2 laneConns -1->-1 (entrance edge 60, stub copy) connected=true", 1, true) ~= nil, l)
	ok(l:find("depot=800 VEHICLE_DEPOT 0->1", 1, true) ~= nil, l)
	eq(#a.sent, 2)
	local ce = a.sent[1].proposal.constructionsToAdd[1]
	eq(ce.fileName, "::/depots/road/road_depot/road_depot.con")
	eq(ce.params, { seed = 1 })
	eq(ce.playerEntity, 7)
	-- edge along +x, right side n = (0,-1): local x -> (-1, 0), local y -> (0, -1), origin entrance + 35 n
	local m = ce.transf
	eq(m[1], { -1, 0, 0, 0 })
	eq(m[2], { 0, -1, 0, 0 })
	eq(m[4], { 50, -65, 0, 1 })
	for c = 1, 4 do for r = 1, 4 do
		if m[c][r] == 0 then ok(1 / m[c][r] > 0, "no -0 at column " .. c .. " row " .. r) end
	end end
	local sp = a.sent[2].proposal.streetProposal
	eq(sp.edgesToRemove, { 50 })
	eq(sp.nodesToAdd[1].entity, -4)
	eq(sp.nodesToAdd[1].comp.position, { x = 50, y = 0, z = 0 })
	eq(#sp.edgesToAdd, 3)
	local e1, e2, e3 = sp.edgesToAdd[1], sp.edgesToAdd[2], sp.edgesToAdd[3]
	eq({ e1.comp.node0, e1.comp.node1, e2.comp.node0, e2.comp.node1, e3.comp.node0, e3.comp.node1 }, { 1, -4, -4, 2, -4, 10 })
	eq(e1.comp.tangent1, { x = 50, y = 0, z = 0 })
	eq(e3.comp.tangent0, { x = 0, y = -30, z = 0 })
	eq({ e1.comp.node0, e3.comp.node1 }, { 1, 10 })
end)

test("10d falls back to stops and depot near the camera, buys the newest bus on sale and sets the line", function()
	local a = busApi()
	a.engine.util.octree.findEntitiesInCircle = function(_c, _r, ct) return ct == "STATION" and { 300, 301, 302 } or {} end
	a.engine.system.stationGroupSystem = { getStationGroup = function(st) return ({ [300] = 900, [301] = 901, [302] = 901 })[st] end }
	a.lists.VEHICLE_DEPOT = { 800, 810 }
	a.world[800] = { VEHICLE_DEPOT = function() return { carrier = 0 } end }
	a.world[810] = { VEHICLE_DEPOT = function() return { carrier = 1 } end } -- rail: skipped
	a.world[700] = { CONSTRUCTION = function() return { transf = { getTransl = function() return { x = 30, y = 40, z = 0 } end } } end }
	a.engine.system.streetConnectorSystem.getConstructionEntityForDepot = function() return 700 end
	a.world[1000] = { GAME_TIME = function() return { gameTime = 12345.6 } end }
	a.engine.util.getWorld = function() return 1000 end
	a.world[555] = { TRANSPORT_VEHICLE = function() return { state = 2 } end }
	local models = {
		["bus/old.mdl"] = { id = 1, md = { transportVehicle = { carrier = 0, transportModes = { 5 }, filterTags = { "default" }, compartments = { {} } }, availability = { yearFrom = 1950, yearTo = 1990 } } },
		["bus/new.mdl"] = { id = 2, md = { transportVehicle = { carrier = 0, transportModes = { 5 }, filterTags = { "default" }, compartments = { {}, {} } }, availability = { yearFrom = 1995, yearTo = 0 } } },
		["bus/future.mdl"] = { id = 3, md = { transportVehicle = { carrier = 0, transportModes = { 5 }, filterTags = { "default" }, compartments = {} }, availability = { yearFrom = 2030, yearTo = 0 } } },
		["truck/t.mdl"] = { id = 4, md = { transportVehicle = { carrier = 0, transportModes = { 6 }, filterTags = { "default" }, compartments = {} }, availability = {} } },
	}
	local byId = {}
	for path, m in pairs(models) do byId[m.id] = m end
	a.res = { modelRep = {
		forEachModelWithMetadata = function(key, fn) eq(key, "transportVehicle") for path in pairs(models) do fn(path) end end,
		find = function(path) return models[path].id end,
		get = function(id) return { metadata = byId[id].md } end,
	} }
	a.type.Line = { new = function() return {} end, Stop = { new = function() return {} end } }
	a.type.TransportVehiclePart = { new = function() return { part = {} } end }
	a.type.LoadConfig = { new = function() return {} end }
	a.type.TransportVehicleConfig = { new = function() return {} end }
	a.cmd.makeLineCreateCmd = function(name, color, player, line) return { kind = "line", name = name, line = line } end
	a.cmd.makeVehicleBuyCmd = function(player, depot, cfg) return { kind = "buy", depot = depot, cfg = cfg } end
	a.cmd.makeVehicleSetLineCmd = function(v, line, stop) return { kind = "setLine", v = v, line = line, stop = stop } end
	a.engine.system.transportVehicleSystem = { getLineVehicles = function() return { 555 } end }
	a.engine.util.vehicle = { findBestDepotForLine = function() return 800 end }
	a.onSend = function(cmd)
		if cmd.kind == "line" then return true, {}, { { 4000, 1 } } end
		if cmd.kind == "buy" then return true, { resultVehicleEntity = 555 }, {} end
		return true, {}, {}
	end
	local lines = runUntilProbe("p10_line", a)
	eq(#lines, 1)
	local l = lines[1]
	ok(l:find("bus_line_from_pair ok groups={901,900} (newest near camera (2 groups within 1500m)) depot=800 (nearest road depot (28m) depots=2 road=1 withPos=2 [800:road/carrier/28m/nodes=false 810:notRoad/carrier=1/28m/nodes=false])", 1, true) ~= nil, l)
	ok(l:find("year=2000 models=4 roadBuses=3 errors=0 pick=bus/new.mdl(id=2 yearFrom=1995)", 1, true) ~= nil, l)
	ok(l:find("line=4000 (SQST Bus", 1, true) ~= nil, l)
	ok(l:find("vehicle=555 setLine=true +5s: lineVehicles=1 vehicleState=2 findBestDepotForLine=800 (sameDepot=true)", 1, true) ~= nil, l)
	eq(#a.sent, 3)
	local line = a.sent[1].line
	eq(#line.stops, 2)
	eq({ line.stops[1].stationGroup, line.stops[1].station, line.stops[1].terminal }, { 901, 0, 0 })
	local cfg = a.sent[2].cfg
	eq(a.sent[2].depot, 800)
	eq(cfg.vehicleGroups, { 1 })
	local part = cfg.vehicles[1]
	eq({ part.part.modelId, part.purchaseTime, #part.part.compartment2loadConfig }, { 2, 12345, 2 })
	eq(part.autoLoadConfig, { true, true })
	eq({ a.sent[3].v, a.sent[3].line, a.sent[3].stop }, { 555, 4000, 0 })
end)
