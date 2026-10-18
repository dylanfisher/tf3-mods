-- stress_towns.tl against a fake api: grow and spawn run one command at a time (the next only after
-- the callback), spawn names/caps/placement, freeze, the readout, and connect uses keep = true.

local T = 0
local sent        -- every sendCommand: { cmd, cb }
local zoneEvents  -- the SmartLanes.zones events (kept out of sent)
local townsList   -- town entity ids
local comps       -- town id -> TOWN component
local positions   -- town id -> {x, y}
local names       -- entity -> name
local water       -- function(x, y) -> bool
local nextEntity
local camera
local buildingMap -- town id -> list of buildings
local seeds       -- every createTowns seed
local createOrder -- function(toAdd) -> toAdd in another order (createTowns), nil: as given
local createAt -- answer(): function(info) -> x, y where the engine puts that town (nil: its info position)
local createShuffle, createSkip   -- answer(): the order the engine adds a create command's towns in; infos it leaves out

local function vec2(x, y) return { x = x, y = y } end

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			Vec2f = { new = vec2 },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			ComponentType = { TOWN = "TOWN" },
			Map = { Town = { new = function() return {} end } },
			JournalEntry = { new = function() return { category = {} } end, Type = { OTHER = "OTHER" } },
		},
		cmd = {
			sendCommand = function(cmd, cb)
				if cmd.kind == "event" and cmd.id == "square_smart_lanes" then zoneEvents[#zoneEvents + 1] = cmd return end
				sent[#sent + 1] = { cmd = cmd, cb = cb }
			end,
			makeTownUpdateSizeCmd = function(town, f, all) return { kind = "size", town = town, f = f, all = all } end,
			makeTownCreateCmd = function(infos) return { kind = "create", infos = infos } end,
			makeTownSetDevelopmentActiveCmd = function(town, active) return { kind = "dev", town = town, active = active } end,
			makeTownDestroyCmd = function(town) return { kind = "destroy", town = town } end,
			makeTownConnectWithIndustriesCmd = function(ents, conns, keep) return { kind = "connect", ents = ents, conns = conns, keep = keep } end,
			makeScriptingSendEventCmd = function(src, id, name, param) return { kind = "event", src = src, id = id, name = name, param = param } end,
		},
		gui = { camera = { getCameraData = function() return { x = camera[1], y = camera[2] } end } },
		engine = {
			getEntitiesWithComponent = function(ct)
				eq(ct, "TOWN")
				local out = {}
				for i, t in ipairs(townsList) do out[i] = t end
				return out
			end,
			getComponent = function(e, ct) if ct == "TOWN" then return comps[e] end end,
			entityExists = function(e) return comps[e] ~= nil end,
			terrain = {
				isValidCoordinate = function(p) return math.abs(p.x) <= 10000 and math.abs(p.y) <= 10000 end,
				isOnWater = function(p) return water(p.x, p.y) end,
				getBoundingBox = function() return { min = { x = -10000, y = -10000 }, max = { x = 10000, y = 10000 } } end,
				makeMapFromGame = function(hm, withTowns, ind, assets)
					eq({ hm, withTowns, ind, assets }, { false, true, false, false })
					local ts = {}
					for _, t in ipairs(townsList) do
						ts[#ts + 1] = { existing = t, pos = vec2(positions[t][1], positions[t][2]) }
					end
					return { towns = ts }
				end,
			},
			mapgen = {
				createTowns = function(seed, list)
					seeds[#seeds + 1] = seed
					local out = {}
					for i, t in ipairs(list) do
						out[i] = { name = t.name, position = t.pos, initialLandUseCapacities = { 100, 100, 100 } }
					end
					if createOrder then out = createOrder(out) end
					return { toAdd = out, toRemove = townsList }
				end,
				getDefaultTownConnections = function(list) eq(#list, 2) return { { 0, 1 } } end,
			},
			util = {
				getEntityName = function(e) return names[e] or ("Town" .. e) end,
				getPlayer = function() return 7 end,
				finance = { getPlayersBalance = function() return 0 end },
				town = { getClosestTown = function(p)
					local best, bd = -1, math.huge
					for _, t in ipairs(townsList) do
						local dx, dy = positions[t][1] - p.x, positions[t][2] - p.y
						if dx * dx + dy * dy < bd then best, bd = t, dx * dx + dy * dy end
					end
					return best
				end },
			},
			system = { townBuildingSystem = {
				getTown2BuildingMap = function() return buildingMap end,
				getTown2personCapacitiesMap = function() return { [1] = { 10, 20, 30 }, [2] = { 1, 1, 1 } } end,
			} },
		},
	}
end

local function addTown(id, x, y, name)
	townsList[#townsList + 1] = id
	comps[id] = { sizeFactors = { 1, 1, 1 }, initialLandUseCapacities = { 100, 100, 100 }, developmentActive = true }
	positions[id] = { x, y }
	names[id] = name
end

local rt, towns
before_each(function()
	zoneEvents = {}
	T, sent, townsList, comps, positions, names, nextEntity, camera = 0, {}, {}, {}, {}, {}, 100, { 0, 0 }
	water = function() return false end
	seeds = {}
	createOrder, createShuffle, createSkip, createAt = nil, nil, nil, nil
	buildingMap = { [1] = { 1, 2, 3 } }
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true -- the notifications event is tested in test_runtime.lua
	towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl"
	addTown(1, 0, 0, "Tacoma")
	addTown(2, 6000, 0, "SQST Town 4")
end)

local function frames(n) for _ = 1, n do rt.tick() end end

--- The Wide grid's extra api: our street grid construction resolves, year 2020, flat terrain.
local function wideGridApi(found)
	api.res = { constructionRep = { find = function(n)
		return (found and n == "square_stress_test::/infrastructure/street_construction/square_stress_test_town_grid.con") and 9 or -1
	end } }
	api.engine.util.getYear = function() return 2020 end
	api.engine.terrain.getHeightAt = function() return 0 end
	api.type.Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end }
	api.type.Mat4f = { new = function(a, b, c, d) return { a, b, c, d } end }
	api.type.SimpleProposal = setmetatable({ ConstructionEntity = { new = function() return {} end } },
		{ __index = { new = function() return { streetProposal = {} } end } })
	api.cmd.makeWorldBuildProposalCmd = function(p, ctx, ignore, player) return { kind = "build", p = p, ctx = ctx, ignore = ignore, player = player } end
end

--- Runs the callback of command k: the engine "executes" create commands by adding the town.
local function answer(k, success)
	local s = sent[k]
	local results = {}
	if s.cmd.kind == "create" and success ~= false then
		-- the engine adds every town of the command (createSkip: the infos it leaves out; createShuffle:
		-- the order it adds them in)
		local order = {}
		for i = 1, #s.cmd.infos do order[i] = i end
		if createShuffle then order = createShuffle(order) end
		for _, i in ipairs(order) do
			local info = s.cmd.infos[i]
			if not (createSkip and createSkip(info)) then
				nextEntity = nextEntity + 1
				local x, y = info.position.x, info.position.y
				if createAt then
					local ax, ay = createAt(info)
					if ax then x, y = ax, ay end
				end
				addTown(nextEntity, x, y, info.name)
				comps[nextEntity].initialLandUseCapacities = info.initialLandUseCapacities
				results[#results + 1] = { nextEntity, 1 }
			end
		end
	end
	if s.cmd.kind == "destroy" and success ~= false then
		for i, t in ipairs(townsList) do
			if t == s.cmd.town then table.remove(townsList, i) break end
		end
		comps[s.cmd.town] = nil
	end
	s.cb(s.cmd, success ~= false, results)
end

test("grow all: one town per step, next only after the callback; factors multiply the current ones", function()
	comps[2].sizeFactors = { 2, 2, 2 }
	towns.grow(10)
	frames(3)
	eq(#sent, 1)
	eq(sent[1].cmd, { kind = "size", town = 1, f = { 10, 10, 10 }, all = true })
	answer(1)
	frames(3)
	eq(#sent, 2)
	eq(sent[2].cmd.f, { 20, 20, 20 })
	answer(2)
	frames(1)
	local last = rt.recent[#rt.recent]
	ok(last:find("^%[SQST%] action=grow_x10 count=2 ms=") ~= nil, last)
end)

test("grow nearest: only the town closest to the camera; reset sends {1,1,1}", function()
	camera = { 5000, 100 }
	towns.ui.growTarget = 2
	towns.grow(nil)
	frames(2)
	eq(#sent, 1)
	eq(sent[1].cmd, { kind = "size", town = 2, f = { 1, 1, 1 }, all = true })
end)

test("progress line while growing: Growing x5 1/2", function()
	towns.grow(5)
	frames(1)
	local logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	eq(logic.progress(rt.queue), "Growing x5 1/2")
end)

test("spawn near camera: serialized creates, names continue SQST numbering, caps per size, spacing kept", function()
	camera = { -6000, 0 }
	towns.ui.count = 3 -- 10 towns
	towns.ui.size = 4  -- Huge 3200
	towns.ui.placement = 1
	towns.spawn()
	frames(3)
	eq(#sent, 1)
	local info = sent[1].cmd.infos[1]
	eq(info.name, "SQST Town 5")
	eq(info.initialLandUseCapacities, { 3200, 3200, 3200 })
	eq(#sent[1].cmd.infos, 1)
	answer(1)
	frames(3)
	eq(#sent, 2) -- the second create only after the first callback
	eq(sent[2].cmd.infos[1].name, "SQST Town 6")
	for k = 2, 10 do
		answer(k)
		frames(2)
	end
	eq(#sent, 10)
	frames(2)
	-- all 12 towns at least 2500 m apart (Huge spacing), nothing destroyed
	eq(#townsList, 12)
	for i = 1, #townsList do
		for j = i + 1, #townsList do
			local a, b = positions[townsList[i]], positions[townsList[j]]
			local dx, dy = a[1] - b[1], a[2] - b[2]
			ok(dx * dx + dy * dy >= 2500 * 2500 - 1e-6, "towns " .. i .. "," .. j .. " too close")
		end
	end
	local all = table.concat(rt.recent, "\n")
	ok(all:find("spawn_huge summary requested=10 placed=10 created=10 failed=0 caps=3200", 1, true), all)
	ok(all:find("action=spawn_huge count=10", 1, true), all)
end)

test("spawn skips water and logs fewer positions; no command for a missing position", function()
	water = function(x, _y) return x > 0 end
	towns.ui.count = 2 -- 5
	towns.ui.size = 1  -- Small, 1200 m
	towns.ui.placement = 2 -- spread over map
	towns.spawn()
	for _ = 1, 20 do
		frames(1)
		for k = 1, #sent do if not sent[k].answered then sent[k].answered = true answer(k) end end
	end
	for _, s in ipairs(sent) do
		ok(s.cmd.infos[1].position.x <= -300, "on land")
	end
	local all = table.concat(rt.recent, "\n")
	ok(all:find("summary requested=5", 1, true), all)
	eq(#rt.queue.jobs, 0)
end)

test("spawn then connect: one connect command per pair with keep = true, after the creates", function()
	towns.ui.count = 1
	towns.ui.connect = true
	camera = { -6000, 0 }
	towns.spawn()
	frames(2)
	answer(1)
	frames(3)
	eq(#sent, 2)
	eq(sent[2].cmd.kind, "connect")
	eq(sent[2].cmd.keep, true)
	eq(sent[2].cmd.ents, { 101, 1 }) -- new town and its nearest (Tacoma)
	eq(sent[2].cmd.conns, { { 0, 1 } })
	answer(2)
	frames(1)
	ok(rt.recent[#rt.recent]:find("action=connect_towns count=1", 1, true), rt.recent[#rt.recent])
end)

test("grow form: the Factor choice drives growSelected and the button label; last choice resets", function()
	eq(towns.growLabel(), "Grow all towns x2")
	towns.ui.factor = 3 -- x10
	towns.growSelected()
	frames(1)
	eq(sent[1].cmd.f, { 10, 10, 10 })
	towns.ui.growTarget = 2
	eq(towns.growLabel(), "Grow nearest town x10")
	local logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	towns.ui.factor = #logic.GROW_FACTORS + 1
	eq(towns.selectedFactor(), nil)
	eq(towns.growLabel(), "Reset nearest town to x1")
end)

test("spawn form label follows Count and Size; uiSignature changes with the factor", function()
	eq(towns.spawnLabel(), "Spawn 1 medium town")
	towns.ui.count, towns.ui.size = 2, 3
	eq(towns.spawnLabel(), "Spawn 5 large towns")
	local a = towns.uiSignature()
	towns.ui.factor = 2
	ok(towns.uiSignature() ~= a)
end)

--- Everything logged to stdout.txt (window lines are cut at LOG_LINE_MAX).
local function get_logs()
	local out = {}
	for i, e in ipairs(log_entries()) do out[i] = e.msg end
	return out
end

local function setBuildings(town, n)
	local l = {}
	for i = 1, n do l[i] = i end
	buildingMap[town] = l
end

test("grow with 3 passes: each town gets the command 3 times in a row, later passes re-send the factors", function()
	setBuildings(1, 100)
	setBuildings(2, 100)
	towns.ui.factor = 3 -- x10
	towns.ui.passes = 2 -- 3 passes
	eq(towns.growLabel(), "Grow all towns x10, 3 passes")
	towns.growSelected()
	local gains = { [1] = 300, [2] = 300 }
	for k = 1, 6 do
		frames(2)
		eq(#sent, k) -- one command in flight
		local town = sent[k].cmd.town
		comps[town].sizeFactors = sent[k].cmd.f
		setBuildings(town, #buildingMap[town] + gains[town])
		answer(k)
	end
	frames(2)
	eq(#sent, 6)
	eq({ sent[1].cmd.town, sent[2].cmd.town, sent[3].cmd.town, sent[4].cmd.town }, { 1, 1, 1, 2 })
	eq(sent[1].cmd.f, { 10, 10, 10 })
	eq(sent[2].cmd.f, { 10, 10, 10 }) -- re-sent, not x100
	eq(sent[3].cmd.f, { 10, 10, 10 })
	local all = table.concat(rt.recent, "\n")
	ok(all:find("grow_x10 summary towns=2 passes=3 sent=6 stoppedEarly=0 buildings 200->2000", 1, true), all)
	ok(all:find("action=grow_x10 count=6", 1, true), all)
	local details = table.concat(get_logs(), "\n")
	ok(details:find("pass 2/3 town=1 .-%(build%-out pass%) buildings 400%->700 %(%+300%)"), details)
end)

test("grow passes stop early for a town when a pass adds fewer than 20 buildings", function()
	setBuildings(1, 100)
	setBuildings(2, 100)
	towns.ui.passes = 4 -- 10 passes
	towns.grow(5, 10)
	-- town 1: +300, then +10 (stops); town 2: +5 at once (stops)
	local plan = { 300, 10, 5 }
	for k = 1, 3 do
		frames(12) -- skipped passes take a step each
		eq(#sent, k)
		local town = sent[k].cmd.town
		setBuildings(town, #buildingMap[town] + plan[k])
		answer(k)
	end
	frames(5)
	eq(#sent, 3)
	eq({ sent[1].cmd.town, sent[2].cmd.town, sent[3].cmd.town }, { 1, 1, 2 })
	local all = table.concat(rt.recent, "\n")
	ok(all:find("grow_x5 summary towns=2 passes=10 sent=3 stoppedEarly=2 buildings 200->515", 1, true), all)
	eq(#rt.queue.jobs, 0)
end)

test("grow at cap: the first pass logs at cap, build-out pass; reset ignores passes", function()
	comps[1].sizeFactors = { 1000, 1000, 1000 }
	towns.ui.growTarget = 2
	camera = { 0, 0 }
	towns.grow(10, 1)
	frames(2)
	eq(sent[1].cmd.f, { 1000, 1000, 1000 })
	answer(1)
	frames(1)
	ok(table.concat(get_logs(), "\n"):find("(at cap, build-out pass)", 1, true))
	towns.grow(nil, 5)
	frames(2)
	answer(2)
	frames(3)
	eq(#sent, 2)
end)

test("spawn near camera relaxes when the strict ring is all water: wider ring, logged", function()
	camera = { -6000, 0 }
	towns.ui.count = 1
	towns.ui.size = 1 -- Small, 1200 m
	water = function(x, y) return (x + 6000) ^ 2 + y ^ 2 < 2700 ^ 2 end
	towns.spawn()
	frames(2)
	eq(#sent, 1)
	local p = sent[1].cmd.infos[1].position
	ok((p.x + 6000) ^ 2 + p.y ^ 2 >= 2700 ^ 2)
	local all = table.concat(get_logs(), "\n")
	ok(all:find("relaxation=wider | strict 1200m cands=16 placed=0 (water=16) | wider 1200m", 1, true), all)
	ok(all:find("spawn_small placement: 1 of 1 positions, near camera -6000,0 relaxation=wider", 1, true), all)
end)

test("freeze all: one SetDevelopmentActive(false) per town", function()
	towns.setDevelopment(false)
	frames(1)
	eq(#sent, 2)
	eq(sent[1].cmd, { kind = "dev", town = 1, active = false })
	eq(sent[2].cmd, { kind = "dev", town = 2, active = false })
end)

test("town ratings ignore: noise then pollution sensitivity 0 per town, one event in flight, summary logged", function()
	towns.setRatingSensitivity(true)
	frames(3)
	eq(#sent, 1)
	eq(sent[1].cmd, { kind = "event", src = "", id = "Towns", name = "setTownRatingSensitivity",
		param = { townEntity = 1, rating = "noise", sensitivity = 0 } })
	for k = 1, 4 do
		answer(k)
		frames(2)
	end
	eq(#sent, 4)
	eq(sent[2].cmd.param, { townEntity = 1, rating = "pollution", sensitivity = 0 })
	eq(sent[3].cmd.param, { townEntity = 2, rating = "noise", sensitivity = 0 })
	local found = false
	for _, l in ipairs(rt.recent) do
		if l:find("^%[SQST%] ignore_town_emissions summary towns=2 events=4 ok=4") then found = true end
	end
	ok(found, table.concat(rt.recent, "\n"))
end)

test("town ratings restore: one resetTownRatingSensitivity per town; no towns logs and sends nothing", function()
	towns.setRatingSensitivity(false)
	frames(1)
	answer(1)
	frames(1)
	eq(#sent, 2)
	eq(sent[1].cmd.name, "resetTownRatingSensitivity")
	eq(sent[2].cmd.param, { townEntity = 2 })
	townsList = {}
	sent = {}
	towns.setRatingSensitivity(true)
	frames(2)
	eq(#sent, 0)
	eq(rt.recent[#rt.recent], "[SQST] No towns: There are no towns on the map.")
end)

test("readout counts towns, frozen, capacity and buildings", function()
	comps[2].developmentActive = false
	eq(towns.readout(), "Towns 2 (1 frozen)   Capacity 63   Buildings 3")
end)

local function answerAll(rounds)
	for _ = 1, rounds do
		frames(1)
		for k = 1, #sent do if not sent[k].answered then sent[k].answered = true answer(k) end end
	end
end

test("grid 2x2: four creates at exact positions around the map centre, same seed, angle 0, then 4 neighbour roads", function()
	towns.ui.gridLayout = 1  -- 2 x 2
	towns.ui.gridSpacing = 2 -- 2000 m
	towns.ui.gridSize = 3    -- Large 1600
	towns.ui.gridCentre = 1
	towns.ui.gridConnect = 2 -- neighbours
	eq(towns.gridLabel(), "Create 2 x 2 grid, 2 km")
	towns.spawnGrid()
	frames(2)
	eq(#sent, 1) -- serial: one create in flight
	answerAll(20)
	local creates, connects = {}, {}
	for _, s in ipairs(sent) do
		if s.cmd.kind == "create" then creates[#creates + 1] = s.cmd.infos[1] else connects[#connects + 1] = s.cmd end
	end
	eq(#creates, 4)
	local want = { { -1000, -1000, "Grid A1" }, { 1000, -1000, "Grid A2" }, { -1000, 1000, "Grid B1" }, { 1000, 1000, "Grid B2" } }
	for k, info in ipairs(creates) do
		eq({ info.position.x, info.position.y, info.name }, want[k])
		eq(info.initialLandUseCapacities, { 1600, 1600, 1600 })
		eq(info.majorStreetAngle, 0)
		eq(info.initialMajorStreetAngle, 0)
	end
	eq(seeds, { "sqst_grid", "sqst_grid", "sqst_grid", "sqst_grid" })
	eq(#connects, 4)
	for _, c in ipairs(connects) do
		eq(c.keep, true)
		eq(#c.ents, 2)
	end
	eq(connects[1].ents, { 101, 102 }) -- A1 - A2
	eq(connects[2].ents, { 101, 103 }) -- A1 - B1
	local all = table.concat(rt.recent, "\n")
	ok(all:find("grid_2x2 summary towns=4 created=4 failed=0 spacing=2000m centre=0,0 caps=1600 maxOffset=0.0m", 1, true), all)
	ok(all:find("action=connect_grid count=4", 1, true), all)
	eq(#rt.queue.jobs, 0)
end)

test("grid at the camera, no roads: centred on the camera, no connect commands", function()
	camera = { -5000, 3000 }
	towns.ui.gridLayout = 3  -- 1 x 4
	towns.ui.gridSpacing = 1 -- 1000 m
	towns.ui.gridCentre = 2
	towns.ui.gridConnect = 1
	towns.spawnGrid()
	answerAll(20)
	eq(#sent, 4)
	local xs = {}
	for k, s in ipairs(sent) do
		eq(s.cmd.kind, "create")
		xs[k] = s.cmd.infos[1].position.x
		eq(s.cmd.infos[1].position.y, 3000)
	end
	eq(xs, { -6500, -5500, -4500, -3500 })
end)

test("grid with a point on water: cancelled, nothing created, logged", function()
	water = function(x, y) return x > 0 and y > 0 end
	towns.ui.gridLayout = 1
	towns.ui.gridCentre = 1
	towns.spawnGrid()
	answerAll(10)
	eq(#sent, 0)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("grid_2x2 cancelled: Grid B2 at 1000, 1000 is water", 1, true), all)
	eq(rt.warnings[1].title, "Not enough space", "shown in a dialog")
	eq(#rt.queue.jobs, 0)
end)

test("grid with skipNoLand (Showcase): a point on water is skipped alone and logged, the rest built, onDone gets it", function()
	water = function(x, y) return x > 0 and y > 0 end
	local got
	towns.createGrid({ name = "showcase_towns", label = "x", cols = 3, rows = 1, spacing = 1000, size = { caps = 400, spacing = 1000 },
		useCamera = true, cx = 0, cy = 0, connect = 1, streets = 1, skipNoLand = true,
		points = { { x = -1000, y = -1000, name = "Grid S1" }, { x = 1000, y = 1000, name = "Grid S2" }, { x = 1000, y = -1000, name = "Grid S3" } },
	}, function(created, points, skipped)
		got = { created = created, points = points, skipped = skipped }
	end)
	answerAll(20)
	eq(#sent, 2, "two creates")
	eq({ sent[1].cmd.infos[1].name, sent[2].cmd.infos[1].name }, { "Grid S1", "Grid S3" })
	ok(got ~= nil, "onDone called")
	eq(got.skipped, { [2] = true })
	ok(got.created[1] ~= nil and got.created[2] == nil and got.created[3] ~= nil)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("showcase_towns Grid S2 at 1000, 1000: town skipped: no land (water", 1, true), all)
	ok(all:find("showcase_towns summary towns=3 created=2 failed=0 skipped=1 ", 1, true), all)
	-- the towns made are tracked by entity id with their names for Remove towns > Grid towns
	eq(towns.testTowns[got.created[1]], "Grid S1")
	eq(towns.testTowns[got.created[3]], "Grid S3")
	eq(#rt.warnings, 0, "no Not enough space dialog")
	eq(#rt.queue.jobs, 0)
end)

test("remove nearest: one destroy for the town closest to the camera, logged", function()
	camera = { 5500, 0 }
	eq(towns.removeLabel(), "Remove the nearest town")
	towns.removeTowns()
	answerAll(5)
	eq(#sent, 1)
	eq(sent[1].cmd, { kind = "destroy", town = 2 })
	eq(townsList, { 1 })
	local all = table.concat(rt.recent, "\n")
	ok(all:find("remove_nearest summary towns=1 removed=1 failed=0", 1, true), all)
end)

test("remove grid towns: only Grid names, one destroy in flight at a time", function()
	addTown(10, 0, 0, "Grid A1")
	addTown(11, 0, 0, "Grid B2")
	addTown(12, 0, 0, "Gridiron")
	towns.ui.removeTarget = 2
	towns.removeTowns()
	frames(3)
	eq(#sent, 1) -- serial
	answerAll(5)
	eq(#sent, 2)
	eq({ sent[1].cmd.town, sent[2].cmd.town }, { 10, 11 })
	eq(townsList, { 1, 2, 12 })
end)

test("remove grid towns: old Grid S names, the Showcases' new names and this session's test towns by id; never real towns", function()
	addTown(20, 0, 0, "Grid S35")                     -- a Showcase town of an earlier session (old name)
	addTown(21, 0, 0, "Parclo 3 N (Smart lanes)")     -- Showcase
	addTown(22, 0, 0, "Ring IX 12 NW (Game default)")
	addTown(23, 0, 0, "Smart lanes 1 N")              -- Lights showcase
	addTown(24, 0, 0, "Full fan 6 W")
	addTown(25, 0, 0, "Testville")                    -- made by a test this session under a non-test name
	addTown(26, 0, 0, "Parclo 3 N")                   -- real towns: no mode / not a compass point / no number
	addTown(27, 0, 0, "Smart lanes 1 Q")
	addTown(28, 0, 0, "Full fan city")
	addTown(29, 0, 0, "Springfield")                  -- a real town on an id a removed test town had (reused)
	addTown(30, 0, 0, "Grid W")                       -- the Crossing test
	towns.testTowns[25] = "Testville"
	towns.testTowns[29] = "Grid A7"
	towns.testTowns[99] = "Grid B1"                   -- gone by another path: dropped
	towns.ui.removeTarget = 2
	local list, names = towns.removePlan()
	eq(list, { 20, 21, 22, 23, 24, 25, 30 })
	eq(names[2], "Parclo 3 N (Smart lanes)")
	eq(towns.testTowns[99], nil, "a town that no longer exists is dropped")
	towns.removeTowns()
	answerAll(20)
	eq(townsList, { 1, 2, 26, 27, 28, 29 })
	eq(towns.testTowns[25], nil, "a removed town's id is dropped (ids may be reused)")
end)

test("remove all: every town; a failed destroy is counted; no towns logs and sends nothing", function()
	towns.ui.removeTarget = 3
	eq(towns.removeLabel(), "Remove all towns")
	towns.removeTowns()
	frames(2)
	answer(1, false)
	sent[1].answered = true
	answerAll(5)
	eq(#sent, 2)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("remove_all summary towns=2 removed=1 failed=1", 1, true), all)
	townsList = {}
	sent = {}
	towns.removeTowns()
	frames(2)
	eq(#sent, 0)
	ok(rt.recent[#rt.recent]:find("Remove towns: There are no towns to remove.", 1, true), rt.recent[#rt.recent])
end)

test("loading the module calls no engine API", function()
	reset_modules()
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
	local t = ug_require "square_stress_test::/stress/gui/stress_towns.tl"
	eq(type(t.spawn), "function")
end)

test("grid with Streets = Wide grid: our street grid first at each point, then the town; sized by town size", function()
	wideGridApi(true)
	towns.ui.gridLayout = 1  -- 2 x 2
	towns.ui.gridSpacing = 2 -- 2000 m
	towns.ui.gridSize = 2    -- Medium 400 -> 600 m grid
	towns.ui.gridConnect = 1
	towns.ui.gridStreets = 2
	towns.spawnGrid()
	answerAll(30)
	local kinds = {}
	for k, s in ipairs(sent) do kinds[k] = s.cmd.kind end
	eq(kinds, { "build", "create", "build", "create", "build", "create", "build", "create" })
	local ce = sent[1].cmd.p.constructionsToAdd[1]
	eq(ce.fileName, "square_stress_test::/infrastructure/street_construction/square_stress_test_town_grid.con")
	eq(ce.params.sqst_grid_half, 2)
	eq(ce.params.sqst_grid_era, 1)
	eq(ce.transf[4][1], -1000)
	eq(ce.transf[4][2], -1000)
	eq(1 / ce.transf[1][2], math.huge) -- +0
	eq(sent[1].cmd.ignore, false)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("created=4 failed=0", 1, true), all)
end)

test("Wide grid, locked: after each grid build its new streets are swapped for locked copies, configs re-pointed, then the town", function()
	wideGridApi(true)
	-- a tiny "grid": edges 21 (n1-n2) and 22 (n2-n3) appear once the first build is answered; edge 9 was there before
	local built = false
	local CT = { TOWN = "TOWN", BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", BASE_NODE_CONFIG = "BASE_NODE_CONFIG" }
	api.type.ComponentType = CT
	api.type.Vec2f = { new = function(x, y) return { x = x, y = y } end }
	api.type.SegmentAndEntity = { new = function() return {} end }
	api.type.BaseNodeLaneConnectionAndEntity = { new = function() return {} end }
	api.type.LaneConnection = { new = function() return { ctor = true } end }
	local ends = { [21] = { 1, 2 }, [22] = { 2, 3 }, [9] = { 7, 8 } }
	api.engine.util.octree = { findEntitiesInCircle = function()
		return built and { 9, 21, 22 } or { 9 }
	end }
	local townComp = api.engine.getComponent
	api.engine.getComponent = function(e, ct)
		if ct == "BASE_EDGE" then return ends[e] and { node0 = ends[e][1], node1 = ends[e][2] } or nil end
		if ct == "BASE_EDGE_STREET" then return ends[e] and { street = e } or nil end
		if ct == "BASE_NODE_CONFIG" then
			if e == 2 then
				return { laneConnections = { { segment0 = 21, lane0 = 1, segment1 = 22, lane1 = 2, withRoad = true, withTram = false } }, crosswalks = { 21 } }
			end
			if e == 3 then return nil end   -- a node without a config (script-made)
			return { laneConnections = {}, crosswalks = {} }
		end
		return townComp(e, ct)
	end
	local answer0 = answer
	towns.ui.gridLayout = 3 -- 1 x 4
	towns.ui.gridConnect = 1
	towns.ui.gridStreets = 3
	towns.spawnGrid()
	for _ = 1, 40 do
		frames(1)
		for k = 1, #sent do
			if not sent[k].answered then
				sent[k].answered = true
				if sent[k].cmd.kind == "build" and sent[k].cmd.p.constructionsToAdd then built = true end
				answer0(k)
			end
		end
		T = T + 600000
	end
	local kinds = {}
	for k = 1, 3 do kinds[k] = sent[k].cmd.kind end
	eq(kinds, { "build", "build", "create" }, "grid, lock, town")
	local sp = sent[2].cmd.p.streetProposal
	eq(sp.edgesToRemove, { 21, 22 }, "only the new streets")
	eq(#sp.edgesToAdd, 2)
	for _, seg in ipairs(sp.edgesToAdd) do eq(seg.comp.roadDevelopmentLocked, true) end
	eq(sp.edgesToAdd[1].entity, -1)
	eq(sp.nodeConfigsToRemove, { 1, 2 }, "every node at a swapped street with a config, remove + add")
	-- node 3 had none: a fresh one (its one street: empty), added only (removing a missing config asserts)
	local cfg3
	for _, e in ipairs(sp.nodeConfigsToAdd) do if e.entity == 3 then cfg3 = e end end
	ok(cfg3 ~= nil, "config for node 3")
	eq(#cfg3.comp.laneConnections, 0)
	eq(#sp.nodeConfigsToAdd, 3)
	local cfg2 = sp.nodeConfigsToAdd[2].comp
	eq(cfg2.laneConnections[1].segment0, -1)
	eq(cfg2.laneConnections[1].segment1, -2)
	eq(cfg2.crosswalks, { -1 })
	eq(sp.nodesToAdd, nil, "the nodes stay")
end)

test("Wide grid refused or missing: logged, the town is created anyway", function()
	wideGridApi(false)
	towns.ui.gridLayout = 3 -- 1 x 4
	towns.ui.gridConnect = 1
	towns.ui.gridStreets = 2
	towns.spawnGrid()
	answerAll(30)
	eq(#sent, 4)
	ok(table.concat(rt.recent, "\n"):find("street grid construction not found", 1, true))
end)

test("remove towns: Grid / All towns clear the Showcase's Smart Lanes zones (one clear event); nearest and none do not", function()
	towns.ui.removeTarget = 1
	towns.removeTowns()
	eq(#zoneEvents, 0, "nearest town: zones kept")
	addTown(10, 0, 0, "Grid A1")
	towns.ui.removeTarget = 2
	towns.removeTowns()
	eq(#zoneEvents, 1)
	local ev = zoneEvents[1]
	eq({ ev.src, ev.id, ev.name, ev.param.op }, { "", "square_smart_lanes", "SmartLanes.zones", "clear" })
	ok(type(ev.param.run) == "string" and ev.param.run:match("^[%w%.%-]+$") ~= nil, tostring(ev.param.run))
	ok(table.concat(rt.recent, "\n"):find("[SQST] showcase zones cleared by=remove_grid run=", 1, true))
	answerAll(10)
	towns.ui.removeTarget = 3
	towns.removeTowns()
	eq(#zoneEvents, 2)
	townsList = {}
	answerAll(10)
	towns.removeTowns()
	eq(#zoneEvents, 2, "no towns: nothing sent")
end)

test("grow a given list (Lights showcase): only those towns, x5 in 3 passes, under its own job name", function()
	setBuildings(1, 100)
	setBuildings(2, 100)
	towns.ui.growTarget = 2   -- ignored for a given list
	towns.grow(5, 3, { 2 }, "lights_showcase_grow")
	for k = 1, 3 do
		frames(2)
		eq(#sent, k)
		comps[2].sizeFactors = sent[k].cmd.f
		setBuildings(2, #buildingMap[2] + 300)
		answer(k)
	end
	frames(2)
	eq(#sent, 3)
	for k = 1, 3 do eq(sent[k].cmd.town, 2) end
	eq(sent[1].cmd.f, { 5, 5, 5 })
	eq(sent[3].cmd.f, { 5, 5, 5 })
	local all = table.concat(rt.recent, "\n")
	ok(all:find("lights_showcase_grow summary towns=1 passes=3 sent=3", 1, true), all)
	ok(all:find("action=lights_showcase_grow count=3", 1, true), all)
end)

---------------------------------------------------------------------------
-- Batched createGrid (Showcases, Junction / Crossing test; SHOWCASE.md "batched building")

--- n points 1.5 km apart in a row, named Grid S1..; sizes alternate Medium / Large.
local function rowPoints(n)
	local out = {}
	for k = 1, n do out[k] = { x = (k - 1) * 1500 - 8000, y = 2000, name = "Grid S" .. k, size = k % 2 == 0 and 3 or 2 } end
	return out
end

local function batchOpts(n, streets)
	return { name = "lights_showcase_towns", label = "x", cols = n, rows = 1, spacing = 1000, size = { caps = 400, spacing = 1000 },
		useCamera = true, cx = 0, cy = 0, connect = 1, streets = streets, skipNoLand = true, batch = true, points = rowPoints(n) }
end

test("batched grid: street grids GRID_BATCH per proposal, then every town in ONE create command, mapped back by position", function()
	wideGridApi(true)
	-- createTowns hands the TownInfos back reversed and the engine adds the towns in a shuffled order
	createOrder = function(list)
		local out = {}
		for i = #list, 1, -1 do out[#out + 1] = list[i] end
		return out
	end
	createShuffle = function(order)
		local out = {}
		for i = 2, #order, 2 do out[#out + 1] = order[i] end
		for i = 1, #order, 2 do out[#out + 1] = order[i] end
		return out
	end
	local got
	towns.createGrid(batchOpts(12, 2), function(created, points, skipped, timing) got = { created = created, points = points, timing = timing } end)
	answerAll(40)
	local builds, creates = {}, {}
	for _, x in ipairs(sent) do
		if x.cmd.kind == "build" then builds[#builds + 1] = x.cmd.p end
		if x.cmd.kind == "create" then creates[#creates + 1] = x.cmd end
	end
	eq(#builds, 2, "12 grids: 10 + 2")
	eq(#builds[1].constructionsToAdd, 10)
	eq(#builds[2].constructionsToAdd, 2)
	for k, ce in ipairs(builds[1].constructionsToAdd) do
		eq({ ce.transf[4][1], ce.transf[4][2] }, { (k - 1) * 1500 - 8000, 2000 })
		eq(ce.params.sqst_grid_half, k % 2 == 0 and 3 or 2, "each town's own grid size")
		eq(ce.params.sqst_grid_ring, 1)
		eq({ ce.params.sqst_grid_layout, ce.params.sqst_grid_holes }, { nil, nil }, "no layout params unless asked (every older build)")
	end
	eq(#creates, 1, "one create command")
	eq(#creates[1].infos, 12)
	eq(seeds, { "sqst_grid" }, "one createTowns call")
	for _, info in ipairs(creates[1].infos) do
		local k = tonumber(info.name:match("%d+"))
		eq({ info.position.x, info.position.y }, { (k - 1) * 1500 - 8000, 2000 }, info.name)
		local caps = k % 2 == 0 and 1600 or 400
		eq(info.initialLandUseCapacities, { caps, caps, caps }, info.name .. " caps of its size")
		eq(info.majorStreetAngle, 0)
	end
	ok(got ~= nil)
	for k = 1, 12 do
		local e = got.created[k]
		ok(e ~= nil, "town " .. k)
		eq(names[e], "Grid S" .. k, "mapped to its own point")
	end
	ok(got.timing.towns >= 0 and got.timing.grids >= 0)
	local all = table.concat(rt.recent, "\n")
	ok(all:find("lights_showcase_towns towns batch: one command for 12 towns success=true", 1, true), all)
	ok(all:find("matched=12 missing=0", 1, true), all)
	ok(all:find("lights_showcase_towns summary towns=12 created=12 failed=0 skipped=0", 1, true), all)
	ok(all:find(" batched towns_ms=", 1, true), all)
	eq(#rt.queue.jobs, 0)
end)

test("batched grids with a layout (the City lights options): every grid's construction gets the layout and holes params", function()
	wideGridApi(true)
	local o = batchOpts(3, 2)
	o.gridLayout, o.gridHoles = 3, 7
	towns.createGrid(o, function() end)
	answerAll(40)
	local n = 0
	for _, x in ipairs(sent) do
		if x.cmd.kind == "build" then
			for _, ce in ipairs(x.cmd.p.constructionsToAdd) do
				n = n + 1
				eq({ ce.params.sqst_grid_layout, ce.params.sqst_grid_holes }, { 3, 7 })
			end
		end
	end
	eq(n, 3)
end)

test("a point's own townCaps (the light plans A/B's small towns): its town created at that capacity, its grid the size's; one by one too", function()
	wideGridApi(true)
	local o = batchOpts(4, 2)
	o.points[2].townCaps = 150
	o.points[3].townCaps = 40
	towns.createGrid(o, function() end)
	answerAll(40)
	local builds, creates = {}, {}
	for _, x in ipairs(sent) do
		if x.cmd.kind == "build" then builds[#builds + 1] = x.cmd.p end
		if x.cmd.kind == "create" then creates[#creates + 1] = x.cmd end
	end
	for k, ce in ipairs(builds[1].constructionsToAdd) do eq(ce.params.sqst_grid_half, k % 2 == 0 and 3 or 2, "grid of its size") end
	local caps = {}
	for _, info in ipairs(creates[1].infos) do caps[tonumber(info.name:match("%d+"))] = info.initialLandUseCapacities[1] end
	eq(caps, { 400, 150, 40, 1600 })
	sent = {}
	towns.createGrid({ name = "showcase_towns", label = "x", cols = 1, rows = 1, spacing = 1000, size = { caps = 400, spacing = 1000 },
		useCamera = true, cx = 0, cy = 0, connect = 1, streets = 1, skipNoLand = true,
		points = { { x = -1000, y = -1000, name = "Grid S1", townCaps = 40 } } }, function() end)
	answerAll(20)
	eq(sent[1].cmd.infos[1].initialLandUseCapacities, { 40, 40, 40 })
end)

test("batched grid: a refused grid batch goes one by one (the refused grid logged); towns the create missed are created one by one", function()
	wideGridApi(true)
	local refuseGrid = { [3] = true }
	local answer0 = answer
	answer = function(k, success)
		local s_ = sent[k]
		if s_.cmd.kind == "build" then
			for _, ce in ipairs(s_.cmd.p.constructionsToAdd) do
				local idx = math.floor((ce.transf[4][1] + 8000) / 1500 + 1.5)
				if refuseGrid[idx] then return answer0(k, false) end
			end
		end
		return answer0(k, success)
	end
	local got
	towns.createGrid(batchOpts(4, 2), function(created) got = created end)
	answerAll(60)
	answer = answer0
	local builds, creates = {}, {}
	for _, x in ipairs(sent) do
		if x.cmd.kind == "build" then builds[#builds + 1] = x.cmd.p end
		if x.cmd.kind == "create" then creates[#creates + 1] = x.cmd end
	end
	eq(#builds, 5, "the batch of 4, then each alone")
	eq(#builds[1].constructionsToAdd, 4)
	for k = 2, 5 do eq(#builds[k].constructionsToAdd, 1) end
	local all = table.concat(rt.recent, "\n")
	ok(all:find("street grids batch 1/1 (4 grids) refused", 1, true), all)
	ok(all:find("Grid S3: street grid refused", 1, true), all)
	eq(#creates, 1)
	eq(#got, 4)
end)

test("batched grid: towns the create command missed are created one by one, each logged", function()
	local once = false
	createSkip = function(info)
		if info.name ~= "Grid S2" or once then return false end
		once = true
		return true
	end
	local got
	towns.createGrid(batchOpts(3, 1), function(created) got = created end)
	for _ = 1, 40 do
		answerAll(1)
		T = T + 600000   -- the second look 1 s later
	end
	local creates = {}
	for _, x in ipairs(sent) do if x.cmd.kind == "create" then creates[#creates + 1] = x.cmd end end
	eq(#creates, 2, "the batch, then Grid S2 alone")
	eq(#creates[1].infos, 3)
	eq(#creates[2].infos, 1)
	eq(creates[2].infos[1].name, "Grid S2")
	for k = 1, 3 do eq(names[got[k]], "Grid S" .. k) end
	local all = table.concat(rt.recent, "\n")
	ok(all:find("matched=2 missing=1", 1, true), all)
	ok(all:find("towns batch missed 1 town(s); creating them one by one", 1, true), all)
	ok(all:find("summary towns=3 created=3 failed=0", 1, true), all)
end)

test("batched grid: a town placed far off goes to its point only when that point is its nearest; else a stray, its point created one by one", function()
	-- S1's town 700 m off (nearest still S1: far match); S2's town on S3's spot (+300 m): never S2's, S2 alone
	local moved = false
	createAt = function(info)
		if info.name == "Grid S1" then return info.position.x + 700, info.position.y end
		if info.name == "Grid S2" and not moved then
			moved = true
			return info.position.x + 1800, info.position.y
		end
	end
	local got
	towns.createGrid(batchOpts(3, 1), function(created) got = created end)
	for _ = 1, 40 do
		answerAll(1)
		T = T + 600000
	end
	local creates = {}
	for _, x in ipairs(sent) do if x.cmd.kind == "create" then creates[#creates + 1] = x.cmd end end
	eq(#creates, 2, "the batch, then Grid S2 alone")
	eq(creates[2].infos[1].name, "Grid S2")
	for k = 1, 3 do eq(names[got[k]], "Grid S" .. k) end
	local all = table.concat(rt.recent, "\n")
	ok(all:find("is not in Grid S2's grid; left as it is", 1, true), all)
	ok(all:find("matched=2 missing=1 far=1 stray=1", 1, true), all)
end)

test("batched grid: createTowns giving fewer towns than asked -> every town one by one", function()
	createOrder = function(list) return { list[1] } end
	local got
	towns.createGrid(batchOpts(3, 1), function(created) got = created end)
	answerAll(40)
	local creates = {}
	for _, x in ipairs(sent) do if x.cmd.kind == "create" then creates[#creates + 1] = x.cmd end end
	eq(#creates, 3, "one by one")
	for k = 1, 3 do eq(names[got[k]], "Grid S" .. k) end
	ok(table.concat(rt.recent, "\n"):find("towns batch: createTowns gave 1 of 3 towns; one by one", 1, true))
end)

test("batched grid, locked: every grid's new streets locked together in LOCK_BATCH proposals across towns, then the towns", function()
	wideGridApi(true)
	local CT = { TOWN = "TOWN", BASE_EDGE = "BASE_EDGE", BASE_EDGE_STREET = "BASE_EDGE_STREET", BASE_NODE_CONFIG = "BASE_NODE_CONFIG" }
	api.type.ComponentType = CT
	api.type.Vec2f = { new = function(x, y) return { x = x, y = y } end }
	api.type.SegmentAndEntity = { new = function() return {} end }
	api.type.BaseNodeLaneConnectionAndEntity = { new = function() return {} end }
	api.type.LaneConnection = { new = function() return { ctor = true } end }
	-- each built grid gets 3 street edges at its centre; edge 9 stood there before
	local nodeAt, ends = {}, { [9] = { 1, 2 } }
	nodeAt[1], nodeAt[2] = { -8000, 2000 }, { -7990, 2000 }
	local nextE = 1000
	local logicM = ug_require "square_stress_test::/stress/stress_logic.tl"
	logicM.LOCK_BATCH = 4
	api.engine.util.octree = { findEntitiesInCircle = function(c, r)
		local out = {}
		for e, en in pairs(ends) do
			for _, n in ipairs(en) do
				local p = nodeAt[n]
				if (p[1] - c.x) ^ 2 + (p[2] - c.y) ^ 2 <= r * r then out[#out + 1] = e break end
			end
		end
		table.sort(out)
		return out
	end }
	local townComp = api.engine.getComponent
	api.engine.getComponent = function(e, ct)
		if ct == "BASE_EDGE" then return ends[e] and { node0 = ends[e][1], node1 = ends[e][2] } or nil end
		if ct == "BASE_EDGE_STREET" then return ends[e] and { street = e } or nil end
		if ct == "BASE_NODE_CONFIG" then return { laneConnections = {}, crosswalks = {} } end
		return townComp(e, ct)
	end
	local answer0 = answer
	answer = function(k, success)
		local s_ = sent[k]
		if s_.cmd.kind == "build" and s_.cmd.p.constructionsToAdd then
			for _, ce in ipairs(s_.cmd.p.constructionsToAdd) do
				local x, y = ce.transf[4][1], ce.transf[4][2]
				local a, b, c = nextE + 1, nextE + 2, nextE + 3
				nodeAt[a], nodeAt[b], nodeAt[c] = { x, y }, { x + 50, y }, { x, y + 50 }
				ends[a] = { a, b }
				ends[b] = { a, c }
				ends[c] = { b, c }
				nextE = nextE + 3
			end
		elseif s_.cmd.kind == "build" then
			local sp = s_.cmd.p.streetProposal
			for _, e in ipairs(sp.edgesToRemove or {}) do ends[e] = nil end
		end
		return answer0(k, success)
	end
	towns.createGrid(batchOpts(3, 3), function() end)
	for _ = 1, 40 do
		answerAll(1)
		T = T + 600000
	end
	answer = answer0
	local kinds = {}
	for k, x in ipairs(sent) do kinds[k] = x.cmd.kind .. (x.cmd.p and (x.cmd.p.constructionsToAdd and ":grids" or ":lock") or "") end
	eq(kinds, { "build:grids", "build:lock", "build:lock", "build:lock", "create" }, "3 grids at once, 9 edges in batches of 4 across towns, one create")
	local all = {}
	for k = 2, 4 do
		local sp = sent[k].cmd.p.streetProposal
		for _, e in ipairs(sp.edgesToRemove) do all[#all + 1] = e ok(e ~= 9, "never the street that stood there before") end
		for _, seg in ipairs(sp.edgesToAdd) do eq(seg.comp.roadDevelopmentLocked, true) end
	end
	eq(#all, 9)
	eq(sent[1].cmd.p.constructionsToAdd[1].params.sqst_grid_ring, 2, "the country ring")
	local log_ = table.concat(rt.recent, "\n")
	ok(log_:find("lights_showcase_towns street grids locked grids=3 edges=9 locked=9 batches=3 refused=0 failed=0", 1, true), log_)
end)
