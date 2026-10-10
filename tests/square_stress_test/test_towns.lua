-- stress_towns.tl against a fake api: grow and spawn run one command at a time (the next only after
-- the callback), spawn names/caps/placement, freeze, the readout, and connect uses keep = true.

local T = 0
local sent        -- every sendCommand: { cmd, cb }
local townsList   -- town entity ids
local comps       -- town id -> TOWN component
local positions   -- town id -> {x, y}
local names       -- entity -> name
local water       -- function(x, y) -> bool
local nextEntity
local camera
local buildingMap -- town id -> list of buildings

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
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
			makeTownUpdateSizeCmd = function(town, f, all) return { kind = "size", town = town, f = f, all = all } end,
			makeTownCreateCmd = function(infos) return { kind = "create", infos = infos } end,
			makeTownSetDevelopmentActiveCmd = function(town, active) return { kind = "dev", town = town, active = active } end,
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
					local t = list[1]
					return { toAdd = { { name = t.name, position = t.pos, initialLandUseCapacities = { 100, 100, 100 } } },
						toRemove = townsList }
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
	T, sent, townsList, comps, positions, names, nextEntity, camera = 0, {}, {}, {}, {}, {}, 100, { 0, 0 }
	water = function() return false end
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

--- Runs the callback of command k: the engine "executes" create commands by adding the town.
local function answer(k, success)
	local s = sent[k]
	local results = {}
	if s.cmd.kind == "create" and success ~= false then
		nextEntity = nextEntity + 1
		local info = s.cmd.infos[1]
		addTown(nextEntity, info.position.x, info.position.y, info.name)
		comps[nextEntity].initialLandUseCapacities = info.initialLandUseCapacities
		results = { { nextEntity, 1 } }
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
	eq(rt.recent[#rt.recent], "[SQST] ignore_town_emissions: no towns")
end)

test("readout counts towns, frozen, capacity and buildings", function()
	comps[2].developmentActive = false
	eq(towns.readout(), "Towns 2 (1 frozen)   Capacity 63   Buildings 3")
end)

test("loading the module calls no engine API", function()
	reset_modules()
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
	local t = ug_require "square_stress_test::/stress/gui/stress_towns.tl"
	eq(type(t.spawn), "function")
end)
