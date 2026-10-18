-- pm_world.lua (Photo Mode subjects) against a fake engine: list cache TTL, lists cached without a copy, the
-- budgeted "interesting" scans (time budget from the pick start, continuation across clicks, the longest
-- train kept between clicks), single component reads per random pick.

local world, fake

local CT = {
	TRANSPORT_VEHICLE = 1, MODEL_PERSON = 2, SIM_PERSON = 3, STATION_GROUP = 4, INDUSTRY = 5,
	BOUNDING_VOLUME = 6, CARRIAGE_LIST = 7, MOVE_PATH = 8, BASE_EDGE = 9, MOVE_PATH_AIRCRAFT = 10, BASE_NODE = 11,
}

local function newFake()
	local f = { now = 0, readCost = 0, lists = {}, comps = {}, listCalls = {}, reads = 0, removed = {} }
	for __, t in pairs(CT) do f.comps[t] = {} end
	f.api = {
		type = {
			ComponentType = CT,
			Clock = { new = function() return { getTime = function() return f.now * 1000 end } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			TransportVehicle = { LoadState = { None = 0, Loading = 1, Unloading = 2, Departing = 3, WaitForScheduledDeparture = 4 } },
			enum = {
				Carrier = { ROAD = 0, RAIL = 1, TRAM = 2, AIR = 3, WATER = 4 },
				TransportVehicleState = { IN_DEPOT = 0, EN_ROUTE = 1 },
				BaseEdgeType = { NORMAL = 0, BRIDGE = 1, TUNNEL = 2 },
				FlightState = { TakeOff = 1, Landing = 2, Approach = 3, Taxi0 = 4, Taxi1 = 5 },
			},
		},
		engine = {
			getEntitiesWithComponent = function(t)
				f.listCalls[t] = (f.listCalls[t] or 0) + 1
				local out = {}
				for i, e in ipairs(f.lists[t] or {}) do out[i] = e end
				f.lastList = out
				return out
			end,
			getComponent = function(e, t)
				f.reads = f.reads + 1
				f.now = f.now + f.readCost -- each component read costs readCost ms of the fake clock
				return f.comps[t][e]
			end,
			entityExists = function(e)
				if f.removed[e] then return false end
				for __, byE in pairs(f.comps) do if byE[e] ~= nil then return true end end
				return false
			end,
			terrain = {
				getHeightAt = function(p) return f.height and f.height(p.x, p.y) or 0 end,
				isOnWater = function(p) return f.water ~= nil and f.water(p.x, p.y) or false end,
			},
			system = {},
		},
	}
	return f
end

--- n running trains 1..n, train i has parts[i] (default 1) cars, each with a bounding volume.
local function addTrains(n, parts)
	local list = {}
	for i = 1, n do
		list[i] = i
		local cars = {}
		for k = 1, (parts and parts[i] or 1) do cars[k] = k end
		fake.comps[CT.TRANSPORT_VEHICLE][i] = { carrier = 1, state = 1, transportVehicleConfig = { vehicles = cars } }
		fake.comps[CT.BOUNDING_VOLUME][i] = { bbox = { min = { x = i, y = 0, z = 0 }, max = { x = i, y = 0, z = 0 } } }
	end
	fake.lists[CT.TRANSPORT_VEHICLE] = list
end

before_each(function()
	reset_modules()
	fake = newFake()
	set_global("api", fake.api)
	world = ug_require "square_photo_mode::/photo_mode/gui/pm_world.lua"
end)

test("lists are cached for their TTL and kept without a copy", function()
	addTrains(3)
	ok(world.pick("train") ~= nil)
	eq(fake.listCalls[CT.TRANSPORT_VEHICLE], 1)
	fake.now = 4000
	world.pick("vehicle")
	eq(fake.listCalls[CT.TRANSPORT_VEHICLE], 1, "within 5 s: cached")
	fake.now = 5100
	world.pick("vehicle")
	eq(fake.listCalls[CT.TRANSPORT_VEHICLE], 2, "after 5 s: rebuilt")
	world.clearCache()
	world.pick("vehicle")
	eq(fake.listCalls[CT.TRANSPORT_VEHICLE], 3, "cleared")
end)

test("a random person reads its position once", function()
	fake.lists[CT.MODEL_PERSON] = { 50 }
	fake.comps[CT.MODEL_PERSON][50] = { position = { x = 7, y = 8, z = 1 } }
	local s = world.pick("person")
	eq(s.entity, 50); eq(s.x, 7); eq(s.y, 8)
	eq(fake.reads, 1, "MODEL_PERSON only")
end)

test("the longest-train scan stops at the budget, continues next click and keeps its best", function()
	local n = 100
	local parts = {}
	for i = 1, n do parts[i] = 1 end
	parts[90] = 12 -- the longest
	parts[20] = 5
	addTrains(n, parts)
	fake.readCost = 1 -- 1 ms per component read: the 35 ms budget covers ~35 trains per click
	local first = world.pick("longest")
	ok(first ~= nil)
	local hits = {}
	local found = false
	for __ = 1, 6 do
		local s = world.pick("longest")
		hits[#hits + 1] = s.entity
		if s.entity == 90 then found = true end
	end
	ok(found, "covered the whole fleet within a few clicks: " .. table.concat(hits, ","))
	-- round 17: the best is kept (re-scored first), but the next click shows another train of the cycle; once the
	-- cycle is full the best comes back, seen from a new view variant
	ok(world.pick("longest").entity ~= 90, "no repeat right after the best")
	local back = nil
	for __ = 1, 8 do
		local s = world.pick("longest")
		if s.entity == 90 then back = s break end
	end
	ok(back ~= nil, "the best comes back after the cycle")
	ok(back.variant >= 1, "seen again from another view")
	-- every click stays within the budget (+ the last read and the winner's framing reads: position, track)
	local t0 = fake.now
	world.pick("longest")
	ok(fake.now - t0 <= world.SCAN_BUDGET_MS + 6, "click took " .. (fake.now - t0) .. " ms")
end)

test("the budget counts the list build of the click", function()
	addTrains(100)
	fake.readCost = 1
	local build = fake.api.engine.getEntitiesWithComponent
	fake.api.engine.getEntitiesWithComponent = function(t)
		fake.now = fake.now + 30 -- a slow list build
		return build(t)
	end
	local t0 = fake.now
	world.pick("longest")
	ok(fake.now - t0 <= world.SCAN_BUDGET_MS + 6, "list + scan " .. (fake.now - t0) .. " ms")
	ok(fake.now - t0 >= 30)
end)

--- Train i on edge 100 + i between nodes 200 + i and 300 + i along +x; types[i] the edge type (default NORMAL).
local function onEdges(n, types, speeds)
	for i = 1, n do
		fake.comps[CT.MOVE_PATH][i] = { path = { edges = { { { entity = 100 + i }, true } } },
			dyn = { pathPos = { edgeIndex = 0 }, speed = speeds and speeds[i] or 10 } }
		fake.comps[CT.BASE_EDGE][100 + i] = { type = types and types[i] or 0, node0 = 200 + i, node1 = 300 + i }
		fake.comps[CT.BASE_NODE][200 + i] = { position = { x = i - 50, y = 0, z = 0 } }
		fake.comps[CT.BASE_NODE][300 + i] = { position = { x = i + 50, y = 0, z = 0 } }
	end
end

test("train on a bridge: the highest deck wins; a great one stops the scan at once", function()
	addTrains(10)
	onEdges(10, { [3] = 1, [8] = 1 })
	fake.comps[CT.BOUNDING_VOLUME][3].bbox.min.z, fake.comps[CT.BOUNDING_VOLUME][3].bbox.max.z = 10, 10
	fake.comps[CT.BOUNDING_VOLUME][8].bbox.min.z, fake.comps[CT.BOUNDING_VOLUME][8].bbox.max.z = 30, 30
	local s = world.pick("bridge")
	eq(s.entity, 8, "the higher bridge")
	ok(s.framing ~= nil and s.framing.d > 90, "framed for a 30 m deck")
	-- side-on to the track (heading 0): look +-pi/2
	near(math.abs(s.framing.look), math.pi / 2, 1e-9)
	eq(world.pick("train") ~= nil, true)
	-- no bridge at all: none
	world.clearCache()
	onEdges(10)
	eq(world.pick("bridge"), nil)
end)

-- Round 17 (user: "The interesting buttons should always be able to click through and get a new view each time")

test("round 17: a one-train bridge pool gives the same train with a new view variant every click", function()
	addTrains(10)
	onEdges(10, { [6] = 1 })
	for i = 1, 20 do
		local s = world.pick("bridge")
		eq(s.entity, 6)
		eq(s.poolKind, "bridge"); eq(s.poolN, 1); eq(s.poolM, 1)
		eq(s.variant, i - 1, "variant of click " .. i)
	end
end)

test("round 17: a five-train bridge pool shows every train once before any comes back", function()
	addTrains(10)
	onEdges(10, { [1] = 1, [3] = 1, [5] = 1, [7] = 1, [9] = 1 })
	for cycle = 1, 3 do
		local seen, order = {}, {}
		for i = 1, 5 do
			local s = world.pick("bridge")
			ok(not seen[s.entity], "cycle " .. cycle .. ": no repeat before all five: " .. table.concat(order, ","))
			seen[s.entity] = true
			order[#order + 1] = s.entity
			eq(s.poolN, i)
			eq(s.poolM, cycle == 1 and i or 5, "the pool as found so far")
			eq(s.variant, cycle - 1)
		end
	end
end)

test("round 17: skyline and viewpoint step through directions and hills instead of repeating", function()
	fake.api.engine.terrain.makeMapFromGame = function()
		return { towns = { { existing = 70, pos = { x = 0, y = 0 } } } }
	end
	fake.api.engine.system.townBuildingSystem = { getTown2personCapacitiesMap = function() return { [70] = { 900 } } end }
	fake.height = function(x, y) return x > 600 and 150 or 0 end
	local looks = {}
	for i = 1, 4 do
		local f = world.pick("skyline").framing
		for __, l in ipairs(looks) do ok(math.abs(l - f.look) > 1e-6, "a new direction each click") end
		looks[#looks + 1] = f.look
	end
	local a, b = world.pick("viewpoint").framing, world.pick("viewpoint").framing
	ok(a.x ~= nil and b.x ~= nil)
	ok(math.abs(a.look - b.look) > 1e-6 or math.abs(a.d - b.d) > 1e-6, "another hill")
end)

test("crossing water: a vehicle on a bridge over water only", function()
	addTrains(4)
	onEdges(4, { [2] = 1, [4] = 1 })
	fake.water = function(x, y) return x > 3.5 end -- train 4 is over water
	eq(world.pick("water").entity, 4)
	fake.water = nil
	world.clearCache()
	eq(world.pick("water"), nil)
end)

test("trains passing: two moving trains close together; standing ones don't count", function()
	addTrains(6)
	onEdges(6, nil, { 10, 10, 0, 10, 10, 10 })
	for i = 1, 6 do fake.comps[CT.BOUNDING_VOLUME][i].bbox = { min = { x = i * 1000, y = 0, z = 0 }, max = { x = i * 1000, y = 0, z = 0 } } end
	fake.comps[CT.BOUNDING_VOLUME][5].bbox = { min = { x = 2060, y = 0, z = 0 }, max = { x = 2060, y = 0, z = 0 } }
	fake.comps[CT.BOUNDING_VOLUME][3].bbox = { min = { x = 2010, y = 0, z = 0 }, max = { x = 2010, y = 0, z = 0 } }
	local s = world.pick("passing")
	ok(s ~= nil)
	near(s.framing.x, 2030, 1e-9, "between trains 2 and 5 (3 stands still)")
end)

test("tunnel portal: a train on the open edge before a tunnel edge, framed from outside", function()
	addTrains(2)
	onEdges(2)
	-- train 1: on edge 101 (nodes 201 -> 301), next edge 901 is a tunnel from node 301 on
	fake.comps[CT.MOVE_PATH][1].path.edges[2] = { { entity = 901 }, true }
	fake.comps[CT.BASE_EDGE][901] = { type = 2, node0 = 301, node1 = 401 }
	fake.comps[CT.BASE_NODE][401] = { position = { x = 200, y = 0, z = 0 } }
	local s = world.pick("tunnel")
	eq(s.entity, 1)
	-- portal = node 301 at x = 51; the open side lies towards node 201 (x = -49): the centre a little out there
	ok(s.framing.x < 51, "outside the portal")
end)

test("train at a platform: standing and loading; longer first", function()
	addTrains(3, { 2, 9, 4 })
	onEdges(3, nil, { 0, 0, 12 })
	fake.comps[CT.TRANSPORT_VEHICLE][1].loadState = 1
	fake.comps[CT.TRANSPORT_VEHICLE][2].loadState = 1
	fake.comps[CT.TRANSPORT_VEHICLE][3].loadState = 1 -- moving: not at a platform
	eq(world.pick("departure").entity, 2)
	fake.comps[CT.TRANSPORT_VEHICLE][2].loadState = 0
	world.clearCache()
	eq(world.pick("departure").entity, 1)
end)

test("fastest: the quickest land vehicle, followed", function()
	addTrains(3)
	onEdges(3, nil, { 20, 45, 30 })
	local s = world.pick("fastest")
	eq(s.entity, 2)
	eq(s.followShot, true)
end)

test("random place: inside the map, inset from the edges", function()
	fake.api.engine.terrain.getBoundingBox = function() return { min = { x = -1000, y = -1000 }, max = { x = 1000, y = 1000 } } end
	for __ = 1, 100 do
		local s = world.pick("place")
		ok(s.x >= -920 and s.x <= 920 and s.y >= -920 and s.y <= 920, "inside: " .. s.x .. "," .. s.y)
		eq(s.kind, "place")
	end
end)

test("skyline and viewpoint sample the terrain around towns", function()
	fake.api.engine.terrain.makeMapFromGame = function()
		return { towns = { { existing = 70, pos = { x = 0, y = 0 } } } }
	end
	fake.api.engine.system.townBuildingSystem = { getTown2personCapacitiesMap = function() return { [70] = { 900 } } end }
	fake.height = function(x, y) return x > 600 and 150 or 0 end -- a ridge east of the town
	fake.water = function(x, y) return y < -800 end -- a lake south
	local sk = world.pick("skyline")
	ok(sk ~= nil)
	ok(sk.framing.y == 0 and sk.framing.x == 0, "looking at the town")
	-- the eye stands over the lake (south): look heading points north (+y)
	ok(math.sin(sk.framing.look) > 0.5, "seen across the water")
	local vp = world.pick("viewpoint")
	ok(vp ~= nil)
	ok(math.cos(vp.framing.look) < -0.5, "from the ridge in the east, looking west at the town")
	fake.height = function() return 0 end
	world.clearCache()
	eq(world.pick("viewpoint"), nil, "flat land: no viewpoint")
end)

test("flight candidates: towns and points inside the map", function()
	fake.api.engine.terrain.getBoundingBox = function() return { min = { x = -1000, y = -1000 }, max = { x = 1000, y = 1000 } } end
	fake.api.engine.terrain.makeMapFromGame = function()
		return { towns = { { existing = 70, pos = { x = 10, y = 20 } } } }
	end
	local c = world.flightCandidates()
	local town, inside = false, true
	for __, p in ipairs(c) do
		if p.why == "town" then town = true end
		if p.x < -1000 or p.x > 1000 or p.y < -1000 or p.y > 1000 then inside = false end
	end
	ok(town); ok(inside)
end)
test("a removed entity is never read with getComponent", function()
	addTrains(3)
	fake.removed[2] = true
	local read = {}
	local get = fake.api.engine.getComponent
	fake.api.engine.getComponent = function(e, t) read[e] = true return get(e, t) end
	for __ = 1, 20 do world.pick("train") end
	world.pick("longest")
	eq(read[2], nil, "the removed train was skipped")
	ok(read[1] or read[3])
end)

test("alive: exists, still a running vehicle or a person", function()
	addTrains(2)
	eq(world.alive({ entity = 1, kind = "train" }), true)
	fake.comps[CT.TRANSPORT_VEHICLE][1].state = 0 -- IN_DEPOT
	eq(world.alive({ entity = 1, kind = "train" }), false, "in a depot")
	fake.removed[2] = true
	eq(world.alive({ entity = 2, kind = "train" }), false, "removed")
	fake.comps[CT.BOUNDING_VOLUME][77] = { bbox = {} } -- the id now belongs to something else
	eq(world.alive({ entity = 77, kind = "road" }), false, "reused id")
	fake.comps[CT.MODEL_PERSON][50] = { position = { x = 0, y = 0, z = 0 } }
	eq(world.alive({ entity = 50, kind = "person" }), true)
	eq(world.alive(nil), false)
	eq(world.alive({ entity = nil, kind = "train" }), false)
end)

test("mapBounds reads the terrain box once and survives a failure", function()
	local calls = 0
	fake.api.engine.terrain.getBoundingBox = function()
		calls = calls + 1
		return { min = { x = -100, y = -50 }, max = { x = 100, y = 50 } }
	end
	eq(world.mapBounds(), { -100, -50, 100, 50 })
	world.mapBounds()
	eq(calls, 1)
	world.clearCache()
	fake.api.engine.terrain.getBoundingBox = function() error("no terrain") end
	eq(world.mapBounds(), nil)
end)

-- Rev 1 feedback (2026-10-13)

test("MODEL_PERSON that can't be listed is tried once, then SIM_PERSON directly", function()
	local get = fake.api.engine.getEntitiesWithComponent
	fake.api.engine.getEntitiesWithComponent = function(t)
		if t == CT.MODEL_PERSON then
			fake.listCalls[t] = (fake.listCalls[t] or 0) + 1
			error("Cannot loop over this component type")
		end
		return get(t)
	end
	fake.lists[CT.SIM_PERSON] = { 60 }
	fake.comps[CT.MODEL_PERSON][60] = { position = { x = 1, y = 2, z = 0 } }
	eq(world.pick("person").entity, 60)
	fake.now = 60000 -- past the persons TTL: the list is rebuilt
	eq(world.pick("person").entity, 60)
	eq(fake.listCalls[CT.MODEL_PERSON], 1, "not retried")
	eq(fake.listCalls[CT.SIM_PERSON], 2)
end)

test("Anything picks a kind that exists and says which", function()
	addTrains(3)
	for __ = 1, 20 do
		local s = world.pick("any")
		ok(s ~= nil, "found")
		eq(s.kind, "train")
		eq(s.why, "any train")
	end
	-- an empty map: nothing, no error
	fake.lists[CT.TRANSPORT_VEHICLE] = {}
	world.clearCache()
	fake.api.engine.terrain.makeMapFromGame = function() return { towns = {} } end
	eq(world.pick("any"), nil)
end)

test("flight candidates: only the ticked subjects; a river is narrow water; none found is logged, not faked", function()
	fake.api.engine.terrain.getBoundingBox = function() return { min = { x = -5000, y = -5000 }, max = { x = 5000, y = 5000 } } end
	fake.api.engine.terrain.makeMapFromGame = function()
		return { towns = { { existing = 70, pos = { x = 10, y = 20 } } } }
	end
	-- a river 200 m wide running north-south at x = 0, and the sea east of x = 3000
	fake.water = function(x, y) return math.abs(x) < 100 or x > 3000 end
	local function whys(subjects)
		world.clearCache()
		local seen = {}
		for __ = 1, 20 do
			for __, p in ipairs(world.flightCandidates(subjects)) do seen[p.why] = (seen[p.why] or 0) + 1 end
		end
		return seen
	end
	local only = function(k) return { [k] = true } end
	local s = whys(only("rivers"))
	ok((s.river or 0) > 0, "rivers found"); eq(s.water, nil); eq(s.town, nil); eq(s.landscape, nil)
	s = whys(only("water"))
	ok((s.water or 0) > 0); eq(s.river, nil)
	s = whys(only("towns"))
	eq(s.town, 20); eq(s.landscape, nil)
	s = whys(only("landscape"))
	ok((s.landscape or 0) > 0); eq(s.water, nil)
	-- no water at all: rivers ticked alone gives nothing (the flight then flies ahead)
	fake.water = nil
	s = whys(only("rivers"))
	eq(next(s), nil, "nothing made up")
end)

test("nearby (This place): constructions from the octree, running vehicles and people inside the radius only", function()
	local CONSTRUCTION = 20
	CT.CONSTRUCTION = CONSTRUCTION
	fake.comps[CONSTRUCTION] = {}
	-- constructions 1101 (inside) and 1102 (the octree's circle is coarse: outside by its bbox centre)
	for e, x in pairs({ [1101] = 30, [1102] = 400 }) do
		fake.comps[CONSTRUCTION][e] = {}
		fake.comps[CT.BOUNDING_VOLUME][e] = { bbox = { min = { x = x, y = 0, z = 0 }, max = { x = x, y = 0, z = 0 } } }
	end
	local asked = nil
	fake.api.engine.util = { octree = { findEntitiesInCircle = function(c, r, t) asked = { c.x, c.y, r, t } return { 1101, 1102 } end } }
	addTrains(300) -- trains at x = 1..300
	fake.lists[CT.MODEL_PERSON] = { 501, 502 }
	fake.comps[CT.MODEL_PERSON][501] = { position = { x = 5, y = 5, z = 0 } }
	fake.comps[CT.MODEL_PERSON][502] = { position = { x = 5000, y = 5, z = 0 } }
	local list = world.nearby(0, 0, 100)
	eq(asked, { 0, 0, 100, CONSTRUCTION })
	local by = {}
	for __, s in ipairs(list) do
		ok(s.x * s.x + s.y * s.y <= 100 * 100, "inside: " .. s.entity)
		by[s.kind] = (by[s.kind] or 0) + 1
		if s.entity == 1102 or s.entity == 502 then ok(false, "outside picked") end
	end
	eq(by.building, 1)
	ok((by.train or 0) >= 1 and by.train <= 16, "running trains inside, at most 16: " .. tostring(by.train))
	eq(by.person, 1)
	-- a moving subject's position read again; gone = nil
	local tr = nil
	for __, s in ipairs(list) do if s.kind == "train" then tr = s end end
	fake.comps[CT.BOUNDING_VOLUME][tr.entity] = { bbox = { min = { x = 42, y = 1, z = 0 }, max = { x = 42, y = 1, z = 0 } } }
	local x, y = world.subjectPosition(tr)
	eq(x, 42); eq(y, 1)
	fake.removed[tr.entity] = true
	eq(world.subjectPosition(tr), nil)
end)

test("nearby: a failing octree query or empty map gives what it can, never raises", function()
	fake.api.engine.util = { octree = { findEntitiesInCircle = function() error("bad type") end } }
	eq(world.nearby(0, 0, 100), {})
	eq(world.nearby(0 / 0, 0, 100), {})
end)

-- Round 8: saved views join the pool ("if you save a shot, that should count in the interesting shots pool")

test("saved views: a random one as a subject with its own view; Anything draws from them; none or corrupt = nil", function()
	eq(world.pick("saved"), nil, "no saved views")
	world.savedViews = function() return { { id = 4, x = 10, y = 20, d = 150, a = 0.5, p = 0.3 } } end
	local s = world.pick("saved")
	eq(s.kind, "saved")
	eq(s.view, { x = 10, y = 20, d = 150, a = 0.5, p = 0.3 })
	eq(s.why, "saved view 4")
	-- an empty map: Anything still has the saved view
	fake.api.engine.terrain.makeMapFromGame = function() return { towns = {} } end
	local a = world.pick("any")
	eq(a and a.kind, "saved")
	eq(a.why, "any saved")
	-- with trains on the map, Anything shows the saved views now and then
	addTrains(3)
	world.clearCache()
	local cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	world.rnd = cam.newRng(3)
	local n = { saved = 0, train = 0 }
	for __ = 1, 200 do
		local p = world.pick("any")
		if p ~= nil and n[p.kind] ~= nil then n[p.kind] = n[p.kind] + 1 end
	end
	ok(n.saved > 20 and n.train > n.saved, "a fair share: saved " .. n.saved .. ", trains " .. n.train)
	world.savedViews = function() return { { id = 1, x = 0 / 0, y = 0, d = 100, a = 0, p = 0.3 } } end
	eq(world.pick("saved"), nil, "a corrupt view is never a subject")
	world.savedViews = function() error("boom") end
	eq(world.pick("saved"), nil, "a failing list is none")
end)

test("round 17: saved views come in shuffled order, each once per cycle, never the same twice in a row", function()
	local list = {}
	for i = 1, 5 do list[i] = { id = i, x = i * 10, y = 0, d = 100, a = 0, p = 0.3 } end
	world.savedViews = function() return list end
	local last = nil
	for cycle = 1, 4 do
		local seen = {}
		for i = 1, 5 do
			local s = world.pick("saved")
			ok(not seen[s.id], "each saved view once per cycle")
			ok(s.id ~= last, "never twice in a row")
			seen[s.id], last = true, s.id
			eq(s.poolN, i); eq(s.poolM, 5)
		end
	end
end)

---------------------------------------------------------------------------
-- Round 15 DEV: anchors for the cutscene aerial

test("round 15: flyCandidates: static entities with a fat model instance, at its transform; moving ones skipped; per-type counts", function()
	CT.MODEL_INSTANCE_LIST, CT.ASSET_GROUP, CT.CONSTRUCTION, CT.CARRIAGE, CT.ANIMAL = 20, 21, 22, 23, 24
	for __, t in ipairs({ 20, 21, 22, 23, 24 }) do fake.comps[t] = {} end
	local function mil(x, y, z)
		return { fatInstances = { { transf = { getTransl = function() return { x = x, y = y, z = z } end } } } }
	end
	fake.comps[20][501] = mil(10, 20, 30)          -- a model entity
	fake.comps[20][502] = mil(15, 20, 0)           -- a carriage: moving, skipped
	fake.comps[CT.CARRIAGE][502] = {}
	fake.comps[20][503] = { fatInstances = {} }    -- thin instances only (a tree group?): no transform
	fake.comps[22][601] = {}                       -- a construction without a model list of its own
	fake.api.engine.util = { octree = { findEntitiesInCircle = function(c, r, t)
		if t == 20 then return { 501, 502, 503 } end
		if t == 21 then error("type not in the octree") end
		return { 601, 501 }
	end } }
	local out = world.flyCandidates(0, 0, 150)
	eq(#out, 1)
	eq(out[1].entity, 501); eq(out[1].x, 10); eq(out[1].y, 20); eq(out[1].z, 30)
	local text = world.flyStatsText()
	ok(text:find("MODEL_INSTANCE_LIST 1/3 (1 moving skipped)", 1, true), text)
	ok(text:find("ASSET_GROUP ERROR", 1, true), text)
	ok(text:find("CONSTRUCTION 0/1", 1, true), text)
	eq(world.flyStatsText(), " (with a fat instance / found)", "cleared after the line")
	eq(#world.flyCandidates(0 / 0, 0, 10), 0, "NaN: nothing")
end)
