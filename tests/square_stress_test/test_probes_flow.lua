-- stress_probes_flow.tl: probes 11a-11h "Flow" (plans/square_stress_test/FLOW.md) against a fake api:
-- every probe ends with one [SQST-PROBE] line, sends no command, caps the driver sample at 200, reads
-- at most READ_PER_FRAME (25) items per frame, and survives an api where every read throws.

before_each(function()
	reset_modules()
end)

local WORLD = 9999

-- Persons 1..250 drive, 251..300 walk. Driver d is on street edge 1000 (lane 0), or on node 2000 when
-- d % 3 == 0; every 4th driver stands (speed 0, timeStanding 12, blocked 1).
local function flowApi(opts)
	opts = opts or {}
	local T = 0
	local counters = { sent = 0, tnReads = 0 }
	local function onNode(d) return d % 3 == 0 end
	local function movePath(d)
		return {
			state = 0, blocked = d % 4 == 0 and 1 or 0, reverse = false,
			path = { edges = { { { entity = 1000, index = 0 }, true }, { { entity = 2000, index = 0 }, true }, { { entity = 1001, index = 1 }, true } } },
			dyn = { pathPos = { edgeIndex = onNode(d) and 1 or 0, pos = 3, pos01 = 0.5 }, speed = d % 4 == 0 and 0 or 10,
				timeStanding = d % 4 == 0 and 12 or 0, accel = 0, brakeDecel = 0, timeUntilAccel = 0, timeToIgnore = 0 },
		}
	end
	local edgeTn = { edges = { { speedLimit = 13.9, curveSpeedLimit = 20, curSpeed = 10 }, { speedLimit = 13.9 } } }
	local fixed = {
		[1000] = { BASE_EDGE_STREET = {}, BASE_EDGE = { node0 = 2000, node1 = 2001 }, TRANSPORT_NETWORK = edgeTn, PLAYER_OWNED = { player = 7 } },
		[1001] = { BASE_EDGE_STREET = {}, BASE_EDGE = { node0 = 2001, node1 = 2002 }, TRANSPORT_NETWORK = edgeTn },
		[6000] = { BASE_EDGE = { node0 = 2001, node1 = 2002 } },   -- a track edge
		[2000] = { BASE_NODE = { position = { x = 0, y = 0 } }, TRANSPORT_NETWORK = { edges = {} } },
		[2001] = { BASE_NODE = { position = { x = 100, y = 0 } } },
		[2002] = { BASE_NODE = { position = { x = 200, y = 0 } } },
		[700] = { CONSTRUCTION = { fileName = "street/sqrb_roundabout.con", timeBuilt = 5, frozenNodes = { 2001 }, frozenEdges = {},
			transf = { getTransl = function() return { x = 1, y = 2 } end } }, PLAYER_OWNED = { player = 7 } },
		[800] = { TRANSPORT_VEHICLE = { line = 900, stopIndex = 0, state = 1, lastLineStopDeparture = 1000,
			lineStopDepartures = { 1000, 500 }, sectionTimes = { 30.5, 40 }, timeUntilDeparture = 0 } },
		[801] = { TRANSPORT_VEHICLE = { line = 900, stopIndex = 1, state = 1, lastLineStopDeparture = 0,
			lineStopDepartures = { 0, 0 }, sectionTimes = {}, timeUntilDeparture = 0 } },
		[900] = { LINE = {} }, [901] = { LINE = {} },
	}
	local gameTimeMs = 100000
	local function getComponent(e, ct)
		if opts.throw then error("read failed") end
		if ct == "TRANSPORT_NETWORK" then counters.tnReads = counters.tnReads + 1 end
		if e == WORLD then
			if ct == "GAME_TIME" then gameTimeMs = gameTimeMs + 50 return { gameTime = gameTimeMs, gameTime0 = gameTimeMs - 50, timeOfDaySec = 3600 } end
			if ct == "GAME_SPEED" then return { speedup = 4 } end
			return nil
		end
		if fixed[e] then return fixed[e][ct] end
		if type(e) == "number" and e >= 1 and e <= 300 then
			if ct == "SIM_PERSON" then return { lastMoveMode = e <= 250 and 1 or 0 } end
			if ct == "MOVE_PATH" and e <= 250 then return movePath(e) end
			if ct == "LAND_VEHICLE" and e <= 250 then return { dyn = { brakingTimer = e % 4 == 0 and 1 or 0, turnLeft = false, turnRight = e % 5 == 0 } } end
		end
		return nil
	end
	local function persons()
		local l = {}
		for i = 1, 300 do l[i] = i end
		return l
	end
	local a = {
		type = {
			Clock = { new = function() return { getTime = function()
				if not opts.frozen then T = T + 1000 end
				return T
			end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			enum = { MoveMode = { WALK = 0, DRIVE = 1, LINES = 2 }, TransportVehicleState = { IN_DEPOT = 0, EN_ROUTE = 1 } },
		},
		gui = { camera = { getCameraData = function() return { x = 10, y = 20 } end } },
		cmd = { sendCommand = function() counters.sent = counters.sent + 1 end },
		engine = {
			entityExists = function(e)
				if opts.throw then error("exists failed") end
				return fixed[e] ~= nil or (e >= 1 and e <= 300) or e == WORLD
			end,
			getComponent = getComponent,
			getEntitiesWithComponent = function(ct)
				if opts.throw then error("Cannot loop") end
				if ct == "SIM_PERSON" then return persons() end
				return {}
			end,
			util = {
				getPlayer = function() return 7 end,
				getWorld = function() return WORLD end,
				getEntityName = function(e)
					if e == 900 then return "SQST Bus 1" end
					if e == 901 then return "Other line" end
					return "Town " .. tostring(e)
				end,
				finance = { getPlayersBalance = function() return 1 end },
				octree = { findEntitiesInCircle = function(_c, _r, ct)
					if opts.throw then error("octree failed") end
					if ct == "BASE_EDGE" then return { 1000, 1001, 6000 } end
					if ct == "CONSTRUCTION" then return { 700 } end
					return {}
				end },
				vehicle = {
					getSpeed = function() return 10 end,
					getPosition = function() return { x = 5, y = 5, z = 0 } end,
					calcPathPosData = function() return {} end,
				},
				town = { computeTownsTrafficSpeedMap = function(coef)
					return { [300] = { 0.8 * coef, { 5, 2, 1 } }, [301] = { 0.5, { 1, 1, 1 } } }
				end },
				line = { getMaxFrequency = function() return 0.01 end },
			},
			system = {
				simPersonSystem = { getSimPersonsMovingForTransportNetwork = function(e)
					local out = {}
					for d = 1, 250 do
						if (e == 1000 and d % 3 ~= 0) or (e == 2000 and d % 3 == 0) then out[#out + 1] = d end
					end
					return out
				end },
				lineSystem = { getLinesForPlayer = function() return { 900, 901 } end },
				transportVehicleSystem = { getLineVehicles = function(l) return l == 900 and { 800, 801 } or {} end },
				streetConnectorSystem = {
					getConstructionEntityForEdge = function() return -1 end,
					getConstructionEntityForNode = function(n) return n == 2001 and 700 or -1 end,
				},
			},
		},
	}
	return a, counters
end

-- Runs a probe button and ticks the queue until its [SQST-PROBE] line (or maxTicks). Returns the
-- probe lines, the "[SQST] probe" detail lines and the number of ticks.
local function run(id, fakeApi, maxTicks, perTick)
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
	local flow = ug_require "square_stress_test::/stress/gui/stress_probes_flow.tl"
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	local list = {}
	flow.addTo(list)
	set_global("api", fakeApi)
	rt.notificationsSent = true
	clear_logs()
	for _, p in ipairs(list) do if p.id == id then p.run() end end
	local probeLines, details, ticks = {}, {}, 0
	for _ = 1, maxTicks or 50000 do
		ticks = ticks + 1
		rt.tick()
		if perTick then perTick() end
		for _, e in ipairs(log_entries()) do
			if e.msg:find("[SQST-PROBE]", 1, true) then probeLines[#probeLines + 1] = e.msg end
		end
		if #probeLines > 0 then break end
	end
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQST] probe 11", 1, true) then details[#details + 1] = e.msg end
	end
	return probeLines, details, ticks, flow
end

local function has(lines, text)
	for _, l in ipairs(lines) do if l:find(text, 1, true) then return l end end
	return nil
end

local IDS = { "p11_movepath", "p11_path_entity", "p11_moving", "p11_order", "p11_towns", "p11_bus", "p11_placements", "p11_position" }

test("eight buttons with labels 11a-11h and line-broken tooltips; loading uses no api", function()
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
	local flow = ug_require "square_stress_test::/stress/gui/stress_probes_flow.tl"
	local list = {}
	flow.addTo(list)
	eq(#list, 8)
	for i, p in ipairs(list) do
		eq(p.id, IDS[i])
		ok(p.label:find("^11" .. string.char(96 + i) .. " Flow: ") ~= nil, p.label)
		ok(p.tooltip:find("Read only.", 1, true) ~= nil, p.id)
		for line in (p.tooltip .. "\n"):gmatch("(.-)\n") do ok(#line <= 70, p.id .. " tooltip line too long: " .. line) end
	end
end)

test("every probe ends with one ok line and sends no command", function()
	for _, id in ipairs(IDS) do
		local a, counters = flowApi()
		local lines = run(id, a)
		eq(#lines, 1, id)
		ok(lines[1]:find("^%[SQST%-PROBE%] flow_11%a_[%a_]+ ok ") ~= nil, lines[1])
		eq(counters.sent, 0, id .. " sent a command")
	end
end)

test("11a: 200 of 250 drivers, standing count, lane speed ratio", function()
	local lines, details = run("p11_movepath", (flowApi()))
	ok(lines[1]:find("flow_11a_movepath ok drivers=200 (scan of 300 persons", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("read=200 nilPath=0 gone=0", 1, true) ~= nil, lines[1])
	ok(has(details, "11a movepath_read_us n=200") ~= nil, "read cost line")
	ok(has(details, "11a path_edges n=200 min=3 med=3") ~= nil, "path length line")
	ok(has(details, "standing(<0.5)=50") ~= nil, "standing count")
	ok(has(details, "11a time_standing_of_standing n=50 min=12") ~= nil, "timeStanding of standing")
	-- lanes: 134 on edge 1000 lane 0 (limit 13.9); the 66 on node 2000 have no TN edge
	ok(has(details, "11a lane speedLimit n=134") ~= nil, "lane limit")
	local s = 0
	for _, l in ipairs(details) do if l:find("11a sample", 1, true) then s = s + 1 end end
	eq(s, 12)
end)

test("11b: current step kinds street_edge vs node, transitions over whole paths", function()
	local lines, details = run("p11_path_entity", (flowApi()))
	ok(lines[1]:find("current={street_edge:134,node:66}", 1, true) ~= nil, lines[1])
	ok(has(details, "11b transitions node>street_edge:20,street_edge>node:20") ~= nil, "transitions")
	ok(has(details, "11b sample e=3 entity=2000 kind=node lane=0") ~= nil, "node sample")
end)

test("11c: driver-occupied edges and nodes return their driver; camera groups queried", function()
	local lines, details = run("p11_moving", (flowApi()))
	ok(lines[1]:find("expectedFound{camera_edge:0/0,camera_node:0/0,driver_edge:20/20,driver_node:20/20}", 1, true) ~= nil, lines[1])
	local cam = has(details, "11c group=camera_edge queried=2 ok=2")
	ok(cam ~= nil, "camera edges (track edge 6000 left out)")
	-- nodes 2001 / 2002 have no TRANSPORT_NETWORK component: never queried (native assert risk)
	ok(has(details, "11c group=camera_node queried=3 ok=1 err=0 gone=0 no_tn=2") ~= nil, "camera nodes")
end)

test("11c: no network query on an entity without TRANSPORT_NETWORK", function()
	local a = flowApi()
	local queried = {}
	local inner = a.engine.system.simPersonSystem.getSimPersonsMovingForTransportNetwork
	a.engine.system.simPersonSystem.getSimPersonsMovingForTransportNetwork = function(e)
		queried[#queried + 1] = e
		return inner(e)
	end
	run("p11_moving", a)
	ok(#queried > 0, "queried something")
	for _, e in ipairs(queried) do ok(e ~= 2001 and e ~= 2002, "queried node without TN: " .. tostring(e)) end
end)

test("bounded: one 4 ms budget per frame shared by two probes running at once", function()
	-- the clock advances 1 ms per read: two probes queued together must not each spend 4 ms per frame
	local a = flowApi()
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
	local flow = ug_require "square_stress_test::/stress/gui/stress_probes_flow.tl"
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	local list = {}
	flow.addTo(list)
	set_global("api", a)
	rt.notificationsSent = true
	clear_logs()
	for _, p in ipairs(list) do if p.id == "p11_movepath" or p.id == "p11_order" then p.run() end end
	local worst, lines = 0, 0
	for _ = 1, 50000 do
		local t0 = rt.nowUs()
		rt.tick()
		local spent = rt.nowUs() - t0
		if spent > worst then worst = spent end
		lines = 0
		for _, e in ipairs(log_entries()) do if e.msg:find("[SQST-PROBE]", 1, true) then lines = lines + 1 end end
		if lines >= 2 then break end
	end
	eq(lines, 2)
	-- 4 ms budget + the item that crosses it + the queue's own clock reads (1 ms each in this fake):
	-- 24 ms here; with a budget per slice instead of per frame it was 37 ms
	ok(worst <= 30000, "worst frame " .. worst .. " us")
end)

test("11d: VEHICLE_ORDER absent, blocked and state distribution", function()
	local a = flowApi()
	-- the real list has no VEHICLE_ORDER: a plain table without it
	a.type.ComponentType = { SIM_PERSON = "SIM_PERSON", MOVE_PATH = "MOVE_PATH", SIM_PERSON_AT_VEHICLE = "SIM_PERSON_AT_VEHICLE",
		SIM_ENTITY_AT_VEHICLE = "SIM_ENTITY_AT_VEHICLE", LAND_VEHICLE = "LAND_VEHICLE" }
	local lines, details = run("p11_order", a)
	ok(lines[1]:find("VEHICLE_ORDER=false", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("blocked{0:150,1:50}", 1, true) ~= nil, lines[1])
	ok(has(details, "11d component_types n=5") ~= nil, "component type keys listed")
	ok(has(details, "11d speed_x_blocked moving+blocked=0:150,standing+blocked=1:50") ~= nil, "cross table")
end)

test("11e: both coefficients, per-town lines", function()
	local lines, details = run("p11_towns", (flowApi()))
	ok(lines[1]:find("coef=1 us=", 1, true) ~= nil and lines[1]:find("coef=0.1 us=", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("towns=2", 1, true) ~= nil, lines[1])
	ok(has(details, "11e town=300 name=Town_300 speed=0.8 levels={5,2,1}") ~= nil, "town line")
end)

test("11f: SQST Bus vehicles read now and after 10 s with game-time delta", function()
	local lines, details = run("p11_bus", (flowApi()))
	ok(lines[1]:find("flow_11f_bus ok 1 SQST Bus lines vehicles=2", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("departuresChanged=0/2", 1, true) ~= nil, lines[1])
	ok(has(details, "11f t0 vehicle=800 line=900") ~= nil, "t0 read")
	ok(has(details, "11f t1 vehicle=800") ~= nil, "t1 read")
	ok(has(details, "sectionSum=70.5") ~= nil, "section sum")
	ok(has(details, "11f game_time gameTime=") ~= nil, "game time line")
end)

test("11f without any line vehicle: clean fail line", function()
	local a = flowApi()
	a.engine.system.transportVehicleSystem.getLineVehicles = function() return {} end
	local lines = run("p11_bus", a)
	ok(lines[1]:find("flow_11f_bus fail 1 SQST Bus lines: no vehicle", 1, true) ~= nil, lines[1])
end)

test("11g: constructions and street edges by owner and construction", function()
	local lines, details = run("p11_placements", (flowApi()))
	ok(lines[1]:find("constructions=1 files{street/sqrb_roundabout.con:1}", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("streetEdges=2 edges{ours+free:1,unowned+free:1}", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("nodes{unowned+free:2,unowned+in_con:1}", 1, true) ~= nil, lines[1])
	ok(has(details, "11g construction=700 file=street/sqrb_roundabout.con owner=7 ours=true frozenNodes=1") ~= nil, "construction line")
end)

test("11h: position costs and the path fallback distance", function()
	local lines, details = run("p11_position", (flowApi()))
	ok(lines[1]:find("read=200 zero=0 failed=0", 1, true) ~= nil, lines[1])
	ok(lines[1]:find("lineVehicles=2", 1, true) ~= nil, lines[1])
	ok(has(details, "11h getPosition_us n=200") ~= nil, "cost line")
	ok(has(details, "11h line_vehicles getPosition_us n=2") ~= nil, "bus line")
end)

test("a driver sample is reused by the next probe", function()
	local a = flowApi()
	local _, _, _, flow = run("p11_movepath", a)
	eq(#flow.drivers, 200)
	local lines = run("p11_order", a)
	-- run() re-requires nothing between calls (same module cache), so the sample is still fresh
	ok(lines[1]:find("reused sample", 1, true) ~= nil, lines[1])
end)

test("bounded: at most 25 lane reads per frame with a frozen clock", function()
	local a, counters = flowApi({ frozen = true })
	local maxPerTick, last = 0, 0
	local lines = run("p11_movepath", a, 1000, function()
		local d = counters.tnReads - last
		last = counters.tnReads
		if d > maxPerTick then maxPerTick = d end
	end)
	eq(#lines, 1)
	ok(maxPerTick > 0 and maxPerTick <= 25, "lane reads per frame: " .. maxPerTick)
end)

test("nil-safe: every read throws, each probe still ends with one line", function()
	for _, id in ipairs(IDS) do
		local a = flowApi({ throw = true })
		local lines = run(id, a)
		eq(#lines, 1, id .. " lines")
		ok(lines[1]:find("^%[SQST%-PROBE%] flow_11") ~= nil, lines[1])
	end
end)

test("nil-safe: empty world (no persons, no lines, nothing near the camera)", function()
	for _, id in ipairs(IDS) do
		local a = flowApi()
		a.engine.getEntitiesWithComponent = function() return {} end
		a.engine.util.octree.findEntitiesInCircle = function() return {} end
		a.engine.system.lineSystem.getLinesForPlayer = function() return {} end
		a.engine.util.town.computeTownsTrafficSpeedMap = function() return {} end
		local lines = run(id, a)
		eq(#lines, 1, id .. " lines")
	end
end)
