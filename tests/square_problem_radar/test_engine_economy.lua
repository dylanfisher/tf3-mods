-- Phase 7 smoke test of the engine script's lines group (radar.script.tl scanLines -> scanMoney /
-- scanUse) against a small fake api: calculateBalance per line with a cost split, utilisation from
-- getLineCapacityUsages, the saved averages, Off dropping them, and a failing calculateBalance
-- isolated from the rest. Every other scan group runs against empty fake data.

local YEAR = 365 * 4 * 1000

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[deepcopy(k)] = deepcopy(x) end
	return out
end

-- Any field of these tables is its own name: enum values / component types as distinct keys.
local function names()
	return setmetatable({}, { __index = function(_, k) return k end })
end

local function fakeState()
	local st = { value = nil, sets = 0, subscribed = false }
	function st:get() return deepcopy(self.value) end
	function st:set(v) self.value = deepcopy(v); self.sets = self.sets + 1 end
	function st:hasEventSubscriptions() return self.subscribed end
	function st:subscribeToNoEvents() self.subscribed = true end
	function st:subscribeToEvent() end
	return st
end

-- world: lines 10 (losing money, nearly empty) and 11 (profitable, half full), 3 stops, 2 vehicles each
local world = {
	now = 0, tick = 0,
	balanceFails = false,
	balanceCalls = 0,
	usage = { [10] = { used = 1, capacity = 100 }, [11] = { used = 50, capacity = 100 } },
	-- per year: income, vehicle running costs, vehicle maintenance
	money = { [10] = { 300, 600, 400 }, [11] = { 2000, 600, 400 } },
}

local CT = names()
local TVS = { EN_ROUTE = 1, AT_TERMINAL = 2, IN_DEPOT = 3 }
local JE = { Maintenance = { VEHICLE = "VEH", VEHICLE_MAINTENANCE = "VM" } }

local function installApi()
	local api = {
		type = {
			ComponentType = CT,
			enum = setmetatable({ TransportVehicleState = TVS }, { __index = function() return names() end }),
			LineIssue = { Type = names() },
			Failure = { Reason = names() },
			Line = { LoadMode = { FULL_LOAD_ANY = 1, FULL_LOAD_ALL = 2 } },
			JournalEntry = JE,
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
		},
		engine = {
			config = { getModParams = function() return { [""] = { isMapEditor = false } } end },
			entityExists = function(e) return e ~= nil and e >= 0 end,
			getRevision = function() return { num = { 1 } } end,
			forEachEntityWithComponent = function() end,
			getComponent = function(e, ct)
				if ct == "GAME_TIME" then return { gameTime = world.now, tickCount = world.tick, updateCount = world.tick } end
				if ct == "PLAYER_OWNED" then return { player = 1 } end
				if ct == "LINE" and (e == 10 or e == 11) then
					return { stops = { { stationGroup = 1, loadMode = 0 }, { stationGroup = 2, loadMode = 0 }, { stationGroup = 3, loadMode = 0 } } }
				end
				if ct == "TRANSPORT_VEHICLE" then return { state = TVS.EN_ROUTE, lineStopDepartures = {}, line = 10 } end
				return nil
			end,
			util = {
				getWorld = function() return 0 end,
				getPlayer = function() return 1 end,
				getEntityName = function(e) return "E" .. tostring(e) end,
				line = {
					getLineProblems = function() return {} end,
					getLinesIssues = function() return {} end,
					getLineStationProblems = function() return {} end,
					getLineCapacityUsages = function(l) return { [1] = world.usage[l] } end,
					getMaxFrequency = function() return 0 end,
				},
				vehicle = {
					getVehicleProblems = function() return {} end,
					getSpeed = function() return 5 end,
					getVehicleMaintenanceState = function() return 1 end,
				},
				finance = {
					calculateBalance = function(ents, from, to, maintIncomeOnly, mt)
						world.balanceCalls = world.balanceCalls + 1
						if world.balanceFails then error("calculateBalance not available on this thread") end
						assert(maintIncomeOnly == true)
						-- summed over the entities (the network cost reference passes every eligible line)
						local span = (to - math.max(from, 0)) / YEAR
						local sum = 0
						for _, e in ipairs(ents) do
							local m = world.money[e]
							if mt == "VEH" then sum = sum + math.floor(-m[2] * span)
							elseif mt == "VM" then sum = sum + math.floor(-m[3] * span)
							else sum = sum + math.floor((m[1] - m[2] - m[3]) * span) end
						end
						return sum
					end,
				},
			},
			system = {
				lineSystem = { getLines = function() return { 10, 11 } end, getLinesForStationGroup = function() return {} end },
				transportVehicleSystem = {
					getLineVehicles = function(l) return { l * 10 + 1, l * 10 + 2 } end,
					getNoPathVehicles = function() return {} end,
					getVehiclesWithState = function() return {} end,
				},
				simEntityAtTerminalSystem = { getLineStopSimEntitiesCount = function() return 0 end },
				simEntityAtVehicleSystem = { getVehiclesWithRoundTripCount = function() return {} end },
				landVehicleMoveSystem = { getBlockedTrains = function() return {} end },
			},
		},
		util = { getDefaultYearDuration = function() return YEAR end },
		res = { cargoTypeRep = { get = function() return nil end } },
		cmd = {
			makeScriptingSendEventCmd = function(...) return { ... } end,
			sendCommand = function() end,
		},
	}
	set_global("api", api)
end

stub_module("::/gui/line_vehicle_mgmt/vehicle_util.tl", {
	getVehicleTypeFromModel = function() return "Train" end,
	getLifespan = function() return 0 end,
})
stub_module("::/scripts/entity_util.tl", {
	makeEntityAndRevision0 = function(e) return { entity = e, revision = { num = { 1 } } } end,
})

local function loadScript()
	installApi()
	reset_modules()
	return ug_require "square_problem_radar::/radar/radar.script.tl"
end

-- One lines pass (slot 1) at game time t.
local function linesPass(script, state, t, pass)
	world.now = t
	world.tick = pass * 12 -- SLOT_SPACING 3 x 4 groups: tick % 12 == 0 is the lines slot
	script.update(nil, state, 0.2)
end

local function alertById(state, id)
	for _, a in ipairs(state.value.alerts or {}) do
		if a.id == id then return a end
	end
	return nil
end

local function warnings()
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.level == "warning" then out[#out + 1] = e.msg end
	end
	return out
end

test("engine: losing line listed by tier; utilisation averages saved; low use after half a year", function()
	clear_logs()
	local script = loadScript()
	local state = fakeState()
	local t0 = 2 * YEAR
	linesPass(script, state, t0, 0)
	eq(warnings(), {}, "no scan failures")
	eq(state.value.version, 6)
	-- Line 10: income 300 vs costs 1000 -> 30 % coverage (very poor); its 700 loss is 35 % of both
	-- lines' 2000 vehicle costs (very big): Critical. Line 11 profitable.
	local a = alertById(state, "line_unprofitable:10")
	ok(a ~= nil, "losing line listed (priming lists at once)")
	eq(a.tier, 1)
	eq(a.tab, "economy")
	eq(a.code, "Loss")
	eq(a.arg, "-700|4|30|35")
	eq(alertById(state, "line_unprofitable:11"), nil)
	eq(world.balanceCalls, 10, "2 for the network costs, 7 for the losing line, 1 for the profitable one")
	eq(state.value.tierCounts[1] >= 1, true)
	-- both lines tracked from their first sample
	local saved = state.value.memory.useAvg
	eq(saved[10], { 100, t0, t0 })
	eq(saved[11], { 5000, t0, t0 })
	eq(alertById(state, "line_low_use:10"), nil, "not tracked long enough")
	-- a few more passes over 0.6 years: line 10 averages 1 % -> Critical low use
	local sets = state.sets
	for i = 1, 6 do linesPass(script, state, t0 + i * (YEAR // 10), i) end
	local low = alertById(state, "line_low_use:10")
	ok(low ~= nil, "low use after half a year")
	eq(low.tier, 1)
	eq(low.metric, "1%")
	eq(alertById(state, "line_low_use:11"), nil)
	ok(state.sets - sets <= 6, "at most one state write per pass")
	eq(warnings(), {})
end)

test("engine: averages survive a reload; line_low_use Off drops them", function()
	clear_logs()
	local script = loadScript()
	local state = fakeState()
	local t0 = 2 * YEAR
	for i = 0, 6 do linesPass(script, state, t0 + i * (YEAR // 10), i) end
	ok(alertById(state, "line_low_use:10") ~= nil)
	local saved = deepcopy(state.value)
	-- "load": a fresh Lua state (module-locals gone) with the saved game-script state
	script = loadScript()
	state = fakeState()
	state.value = saved
	linesPass(script, state, t0 + 7 * (YEAR // 10), 7)
	ok(alertById(state, "line_low_use:10") ~= nil, "still listed after the load")
	eq(state.value.memory.useAvg[10][2], t0, "tracking start kept")
	-- switch it off: averages forgotten
	script.handleEvent(nil, state, "", "ProblemRadar", "ProblemRadar.setSetting", { notify = { line_low_use = "off" } })
	linesPass(script, state, t0 + 8 * (YEAR // 10), 8)
	eq(state.value.memory.useAvg, {})
	eq(alertById(state, "line_low_use:10"), nil)
	eq(warnings(), {})
end)

test("engine: a failing calculateBalance keeps the other line alerts and the utilisation averages", function()
	clear_logs()
	local script = loadScript()
	local state = fakeState()
	local t0 = 2 * YEAR
	linesPass(script, state, t0, 0)
	ok(alertById(state, "line_unprofitable:10") ~= nil)
	world.balanceFails = true
	linesPass(script, state, t0 + YEAR // 12, 1) -- a month later: both lines due again
	local w = warnings()
	eq(#w, 1)
	ok(w[1]:find("calculateBalance", 1, true) ~= nil, w[1])
	ok(alertById(state, "line_unprofitable:10") ~= nil, "previous row carried")
	eq(state.value.memory.useAvg[10][1], 100, "averages unaffected")
	-- a failing line is not marked checked: it is retried on the very next pass (so the failure count
	-- keeps rising toward FAIL_DROP_AFTER instead of the rows being carried until next month)
	local calls = world.balanceCalls
	linesPass(script, state, t0 + YEAR // 12 + 2400, 2)
	ok(world.balanceCalls > calls, "retried next pass")
	world.balanceFails = false
end)

test("engine: money re-checked at most once per game month per line; a pending row after the smoothing window", function()
	clear_logs()
	world.money[11] = { 2000, 600, 400 }
	local script = loadScript()
	local state = fakeState()
	local t0 = 2 * YEAR
	local month = YEAR // 12
	world.balanceCalls = 0
	linesPass(script, state, t0, 0)
	eq(world.balanceCalls, 10)
	-- the next passes within the month: no calculateBalance at all, rows carried
	linesPass(script, state, t0 + 2400, 1)
	linesPass(script, state, t0 + month - 1, 2)
	eq(world.balanceCalls, 10)
	ok(alertById(state, "line_unprofitable:10") ~= nil, "carried")
	-- line 11 starts losing; seen at its next check a month later -> pending (smoothSec 30 s)
	world.money[11] = { 300, 600, 400 }
	linesPass(script, state, t0 + month, 3)
	eq(world.balanceCalls, 10 + 2 + 14, "network costs again (a month old) + both lines")
	eq(alertById(state, "line_unprofitable:11"), nil, "pending, not listed yet")
	-- re-checked once the smoothing window has passed (not a month later), so it matures
	linesPass(script, state, t0 + month + 15000, 4)
	eq(world.balanceCalls, 26, "inside the window: not due")
	linesPass(script, state, t0 + month + 30000, 5)
	eq(world.balanceCalls, 33, "only the pending line, all 7 calls (network costs still fresh)")
	ok(alertById(state, "line_unprofitable:11") ~= nil, "listed after the window")
	-- a reload (fresh Lua state): every line is due again at once
	local saved = deepcopy(state.value)
	script = loadScript()
	state = fakeState()
	state.value = saved
	linesPass(script, state, t0 + month + 32400, 6)
	eq(world.balanceCalls, 33 + 2 + 14, "network costs (fresh Lua state) + both lines")
	-- Off and back on: every line re-checked at once (its rows were dropped while off)
	script.handleEvent(nil, state, "", "ProblemRadar", "ProblemRadar.setSetting", { notify = { line_unprofitable = "off" } })
	linesPass(script, state, t0 + month + 34800, 7)
	eq(alertById(state, "line_unprofitable:10"), nil)
	script.handleEvent(nil, state, "", "ProblemRadar", "ProblemRadar.setSetting", { notify = { line_unprofitable = "passive" } })
	linesPass(script, state, t0 + month + 37200, 8)
	eq(world.balanceCalls, 33 + 2 + 14 + 2 + 14, "Off forgot the network costs too")
	world.money[11] = { 2000, 600, 400 }
	eq(warnings(), {})
end)

test("engine: the saved averages are not rewritten on every pass", function()
	clear_logs()
	local script = loadScript()
	local state = fakeState()
	local t0 = 2 * YEAR
	-- noisy utilisation on line 11 (20 % / 90 %: above line_underused's hold, so its own sustain timer
	-- stays off); line_unprofitable off so only the averages can write
	script.handleEvent(nil, state, "", "ProblemRadar", "ProblemRadar.setSetting", { notify = { line_unprofitable = "off" } })
	linesPass(script, state, t0, 0)
	local sets = state.sets
	local month = YEAR // 12
	local n = 0
	for i = 1, 40 do
		world.usage[11] = { used = (i % 2 == 0) and 90 or 20, capacity = 100 }
		linesPass(script, state, t0 + i * 2400, i)
		n = i
	end
	eq(state.sets - sets, 0, "40 passes inside a month: no write")
	linesPass(script, state, t0 + month, n + 1)
	eq(state.sets - sets, 1, "the monthly write")
	world.usage[11] = { used = 50, capacity = 100 }
	eq(warnings(), {})
end)

test("engine: nothing judged for money before the game is a year old", function()
	clear_logs()
	local script = loadScript()
	local state = fakeState()
	world.balanceCalls = 0
	linesPass(script, state, YEAR - 1, 0)
	eq(world.balanceCalls, 0)
	eq(alertById(state, "line_unprofitable:10"), nil)
	eq(warnings(), {})
end)
