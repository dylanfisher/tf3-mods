-- Multi-state harness (plans/square_problem_radar/PERF_VMS.md): TF3 runs a game script's update once
-- per tick, but in whichever of ~14 simulation Lua states is free. Each state has its own module
-- locals; GameScriptState is engine-side and shared. Here: N independent instances of radar.script.tl
-- (each its own module locals), one fake shared state, and every tick dispatched to a random instance
-- (fixed seed). Each test checks one behaviour that must not depend on which state runs a tick:
-- priming, the toast budget, young stuck / blocked timers, failure counts, rotations, the averages.

local YEAR = 365 * 4 * 1000
local MINUTE = 60 * 1000
local TICK_MS = 200 -- game ms per update at 1x (dt 0.2 s)
local TPM = 60 * 1000 // TICK_MS -- ticks per game minute (300)
local N_STATES = 14

local function deepcopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[deepcopy(k)] = deepcopy(x) end
	return out
end

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

-- The fake world. Lines: { [id] = { stops = n, vehicles = {ids}, used = x, capacity = y, money = {income, veh, maint} } }.
-- Vehicles: { [id] = { speed = s, carrier = "ROAD", line = id } } (all EN_ROUTE, owned).
local W

local function newWorld()
	W = {
		now = 2 * YEAR, tick = 0,
		lines = {}, vehicles = {}, stations = {}, lineStationProblems = {}, blocked = {},
		failStations = false,
		sent = {},          -- every "Notifications"/"add" sent: { t = gameTime, more = n | nil, kind = k }
		measured = {},      -- line ids measured for line quality, in order
		moneyChecked = {},  -- line ids whose money was checked (single-line calculateBalance year call), in order
	}
end
newWorld()

local CT = names()
local TVS = { EN_ROUTE = 1, AT_TERMINAL = 2, IN_DEPOT = 3 }
local JE = { Maintenance = { VEHICLE = "VEH", VEHICLE_MAINTENANCE = "VM" } }

local function sortedIds(m)
	local out = {}
	for k in pairs(m) do out[#out + 1] = k end
	table.sort(out)
	return out
end

local function installApi()
	set_global("api", {
		type = {
			ComponentType = CT,
			enum = setmetatable({ TransportVehicleState = TVS }, { __index = function() return names() end }),
			LineIssue = { Type = names() },
			Failure = { Reason = names() },
			Line = { LoadMode = { FULL_LOAD_ANY = 1, FULL_LOAD_ALL = 2 } },
			JournalEntry = JE,
		},
		engine = {
			config = { getModParams = function() return { [""] = { isMapEditor = false } } end },
			entityExists = function(e) return e ~= nil and e >= 0 end,
			getRevision = function() return { num = { 1 } } end,
			forEachEntityWithComponent = function(fn, ct)
				if ct == "STATION_GROUP" then
					for _, sg in ipairs(sortedIds(W.stations)) do fn(sg) end
				elseif ct == "TRANSPORT_VEHICLE" then
					for _, v in ipairs(sortedIds(W.vehicles)) do fn(v) end
				end
			end,
			getComponent = function(e, ct)
				if ct == "GAME_TIME" then return { gameTime = W.now, tickCount = W.tick, updateCount = W.tick } end
				if ct == "PLAYER_OWNED" then return { player = 1 } end
				if ct == "LINE" and W.lines[e] then
					local stops = {}
					for i = 1, W.lines[e].stops do stops[i] = { stationGroup = 900 + i, loadMode = 0 } end
					return { stops = stops }
				end
				if ct == "TRANSPORT_VEHICLE" and W.vehicles[e] then
					local v = W.vehicles[e]
					return { state = TVS.EN_ROUTE, carrier = v.carrier, userStopped = false, line = v.line or -1, stopIndex = 0,
						lineStopDepartures = {} }
				end
				return nil
			end,
			util = {
				getWorld = function() return 0 end,
				getPlayer = function() return 1 end,
				getEntityName = function(e) return "E" .. tostring(e) end,
				line = {
					getLineProblems = function() return {} end,
					getLinesIssues = function() return {} end,
					getLineStationProblems = function()
						if W.failStations then error("getLineStationProblems failed (test)") end
						return W.lineStationProblems
					end,
					getLineCapacityUsages = function(l)
						W.measured[#W.measured + 1] = l
						local line = W.lines[l]
						return { [1] = { used = line.used or 50, capacity = line.capacity or 100 } }
					end,
					getMaxFrequency = function() return 0 end,
				},
				vehicle = {
					getVehicleProblems = function() return {} end,
					getSpeed = function(v) return W.vehicles[v] and W.vehicles[v].speed or 5 end,
					getVehicleMaintenanceState = function() return 1 end,
				},
				station = {
					calculateStationGroupCargo = function(sg)
						return { overflow = W.stations[sg].overflow == true, used = 10, capacity = 5 }
					end,
				},
				finance = {
					calculateBalance = function(ents, from, to, _, mt)
						if #ents == 1 and mt == nil and to - from == YEAR then
							W.moneyChecked[#W.moneyChecked + 1] = ents[1]
						end
						local sum = 0
						for _, e in ipairs(ents) do
							local m = W.lines[e] and W.lines[e].money or { 1000, 300, 200 }
							local span = (to - math.max(from, 0)) / YEAR
							if mt == "VEH" then sum = sum - math.floor(m[2] * span)
							elseif mt == "VM" then sum = sum - math.floor(m[3] * span)
							else sum = sum + math.floor((m[1] - m[2] - m[3]) * span) end
						end
						return sum
					end,
				},
			},
			system = {
				lineSystem = {
					getLines = function() return sortedIds(W.lines) end,
					getLinesForStationGroup = function(sg) return W.stations[sg] and { W.stations[sg].line } or {} end,
				},
				transportVehicleSystem = {
					getLineVehicles = function(l) return W.lines[l] and W.lines[l].vehicles or {} end,
					getNoPathVehicles = function() return {} end,
					getVehiclesWithState = function(st)
						if st ~= TVS.EN_ROUTE then return {} end
						return sortedIds(W.vehicles)
					end,
				},
				simEntityAtTerminalSystem = { getLineStopSimEntitiesCount = function() return 0 end },
				simEntityAtVehicleSystem = { getVehiclesWithRoundTripCount = function() return {} end },
				landVehicleMoveSystem = {
					getBlockedTrains = function() return W.blocked end,
					isTrainWaitingForFreePath = function() return false end,
				},
			},
		},
		util = { getDefaultYearDuration = function() return YEAR end },
		res = { cargoTypeRep = { get = function() return nil end } },
		cmd = {
			makeScriptingSendEventCmd = function(_, id, name, param) return { id = id, name = name, param = param } end,
			sendCommand = function(cmd)
				if cmd.id == "Notifications" and cmd.name == "add" then
					local p = cmd.param.params
					W.sent[#W.sent + 1] = { t = W.now, more = p.more, kind = p.kind }
				end
			end,
		},
	})
end

stub_module("::/gui/line_vehicle_mgmt/vehicle_util.tl", {
	getVehicleTypeFromModel = function() return "Train" end,
	getLifespan = function() return 0 end,
})
stub_module("::/scripts/entity_util.tl", {
	makeEntityAndRevision0 = function(e) return { entity = e, revision = { num = { 1 } } } end,
})

-- N independent Lua states: every instance re-requires the script and its modules (own module locals).
local function newStates(n)
	installApi()
	local scripts = {}
	for i = 1, n do
		reset_modules()
		scripts[i] = ug_require "square_problem_radar::/radar/radar.script.tl"
	end
	return scripts
end

-- One engine tick: game time and updateCount advance, the update runs in one random state.
local function tick(scripts, state, pick)
	W.tick = W.tick + 1
	W.now = W.now + TICK_MS
	local k = pick and pick(W.tick) or math.random(#scripts)
	scripts[k].update(nil, state, 0.2)
end

local function run(scripts, state, ticks, pick)
	for _ = 1, ticks do tick(scripts, state, pick) end
end

-- Run until the next tick of the given scan group (1 lines, 2 stations, 3 vehicles, 4 fleet) has run.
local function runUntilGroup(scripts, state, group, pick)
	repeat tick(scripts, state, pick) until W.tick % 3 == 0 and (W.tick // 3) % 4 + 1 == group
end

local function alert(state, id)
	for _, a in ipairs(state.value and state.value.alerts or {}) do
		if a.id == id then return a end
	end
	return nil
end

-- A save that is older than the mod: problems already there, the radar never ran.
local function addLine(id, opts)
	opts = opts or {}
	W.lines[id] = { stops = opts.stops or 2, vehicles = opts.vehicles or { id * 100 + 1 }, used = opts.used, capacity = opts.capacity,
		money = opts.money }
	for _, v in ipairs(W.lines[id].vehicles) do W.vehicles[v] = { speed = 5, carrier = "ROAD", line = id } end
end

local function seeded()
	math.randomseed(20261010)
	newWorld()
end

---------------------------------------------------------------------------

test("priming: adding the mod to a save with existing problems toasts nothing, whichever state runs", function()
	-- Regression guard: with default settings the only "notify" kind already there is line_no_vehicles,
	-- whose 2-minute MIN_AGE also hid the per-state priming (see the v4 test below for one that doesn't).
	seeded()
	-- 10 lines without vehicles (line_no_vehicles is "notify").
	for i = 1, 10 do addLine(i, { vehicles = {} }) end
	addLine(20)
	local scripts = newStates(N_STATES)
	local state = fakeState()
	run(scripts, state, TPM * 5) -- 5 game minutes (MIN_AGE of line_no_vehicles: 2 min)
	for i = 1, 10 do ok(alert(state, "line_no_vehicles:" .. i) ~= nil, "listed " .. i) end
	eq(#W.sent, 0, "nothing toasted: the problems were there when the mod was added")
	eq(state.value.rt == nil or state.value.rt.prime == nil, true, "priming over")
	-- A problem that appears now is new: it toasts (after the smoothing window and MIN_AGE).
	addLine(30, { vehicles = {} })
	run(scripts, state, TPM * 4)
	eq(#W.sent, 1, "the new line toasts once")
	eq(W.sent[1].kind, "line_no_vehicles")
end)

test("priming: an old-revision save (v4, no notify maps) with vehicles already stuck toasts nothing, whichever state runs", function()
	-- Default settings: line_no_vehicles' 2-minute MIN_AGE gives the one priming Lua state time to mark
	-- its rows (the test above also passes per state); veh_stuck has no MIN_AGE, so its rows show the
	-- per-state priming at once. v4 kept the stuck timers, so the rows are there on the first pass.
	seeded()
	addLine(1)
	local now = W.now
	local stopped = {}
	for v = 1, 6 do
		W.vehicles[v] = { speed = 0, carrier = "ROAD", line = 1 }
		stopped[v] = now - 10 * MINUTE
	end
	local scripts = newStates(N_STATES)
	local state = fakeState()
	state.value = { version = 4, settings = {}, alerts = {}, total = 0, kindCounts = {},
		memory = { stoppedSince = stopped, blockedSince = {}, blockedBy = {}, overloadSince = {}, underusedSince = {},
			bunchingSince = {}, lineCursor = -1 } }
	run(scripts, state, TPM * 3)
	for v = 1, 6 do ok(alert(state, "veh_stuck:" .. v) ~= nil, "listed " .. v) end
	eq(#W.sent, 0, "the vehicles stuck before the update never toast")
end)

test("priming: switching a kind to notify marks its listed rows silently, whichever state runs", function()
	seeded()
	addLine(1)
	for sg = 1, 6 do W.stations[sg] = { overflow = true, line = 1 } end
	local scripts = newStates(N_STATES)
	local state = fakeState()
	run(scripts, state, TPM * 2)
	ok(alert(state, "station_overcrowded:3") ~= nil, "listed (passive)")
	eq(#W.sent, 0)
	-- the GUI event goes to one (random) state
	scripts[math.random(#scripts)].handleEvent(nil, state, "", "ProblemRadar", "ProblemRadar.setSetting",
		{ notify = { station_overcrowded = "notify" } })
	run(scripts, state, TPM * 3)
	eq(#W.sent, 0, "the rows already listed never toast")
end)

test("toast budget: at most 3 toasts + 1 summary per 2 game minutes over all states", function()
	seeded()
	addLine(1)
	local scripts = newStates(N_STATES)
	local state = fakeState()
	run(scripts, state, TPM) -- priming over, nothing toasted
	eq(#W.sent, 0)
	-- a new line without vehicles every 6 game seconds for 10 game minutes (100 new problems)
	local nextId = 100
	for t = 1, TPM * 14 do
		if t <= TPM * 10 and t % 30 == 0 then
			addLine(nextId, { vehicles = {} })
			nextId = nextId + 1
		end
		tick(scripts, state)
	end
	ok(#W.sent > 0, "toasts sent")
	-- the designed rule: a window starts with its first send and lasts 2 game minutes; at most 3 toasts
	-- and 1 summary in it
	local windowStart, items, summaries = nil, 0, 0
	local totalItems = 0
	for _, s in ipairs(W.sent) do
		if windowStart == nil or s.t - windowStart >= 2 * MINUTE then
			windowStart, items, summaries = s.t, 0, 0
		end
		if s.more ~= nil then summaries = summaries + 1 else items = items + 1 totalItems = totalItems + 1 end
		ok(items <= 3, "at most 3 toasts in the window from " .. windowStart .. " (got " .. items .. ")")
		ok(summaries <= 1, "at most 1 summary in the window from " .. windowStart .. " (got " .. summaries .. ")")
	end
	ok(totalItems <= 3 * 7, "14 game minutes: at most 7 windows of 3 toasts (got " .. totalItems .. ")")
end)

test("young timers: stuck vehicles and blocked trains alert after the designed delay, whichever state runs", function()
	seeded()
	addLine(1)
	for v = 1, 10 do W.vehicles[v] = { speed = 5, carrier = "ROAD", line = 1 } end
	W.vehicles[50] = { speed = 5, carrier = "RAIL", line = 1 }
	W.vehicles[51] = { speed = 5, carrier = "RAIL", line = 1 }
	local scripts = newStates(N_STATES)
	local state = fakeState()
	run(scripts, state, TPM)
	-- vehicles stop at staggered times; record the first vehicles pass that saw each standing
	local stopAt, firstSeen, listedAt = {}, {}, {}
	local t0 = W.tick
	local blockedFrom, blockedSeen, blockedListed
	for t = 1, TPM * 8 do
		local v = t // 125 + 1 -- one vehicle every 25 s
		if v <= 10 and W.vehicles[v].speed ~= 0 and t % 125 == 7 then
			W.vehicles[v].speed = 0
			stopAt[v] = W.now
		end
		if t == 500 then
			W.blocked = { { 50, 51 } }
			blockedFrom = W.now
		end
		tick(scripts, state)
		if W.tick % 12 == 6 then -- a vehicles pass just ran: the vehicles standing at this pass
			for u, at in pairs(stopAt) do
				if firstSeen[u] == nil and at < W.now then firstSeen[u] = W.now end
			end
			if blockedFrom ~= nil and blockedSeen == nil then blockedSeen = W.now end
		end
		for u in pairs(stopAt) do
			if listedAt[u] == nil and alert(state, "veh_stuck:" .. u) ~= nil then listedAt[u] = W.now end
		end
		if blockedListed == nil and alert(state, "train_blocked_by:51") ~= nil then blockedListed = W.now end
	end
	ok(W.tick > t0)
	-- designed: the timer starts at the first vehicles pass that sees the vehicle standing, the row is
	-- detected at the first pass >= 3 min (road) later and listed after the 30 s smoothing window, at the
	-- first vehicles pass after that: at most 2 passes (2 x 2.4 s) after start + 3 min + 30 s.
	local PASS = 12 * TICK_MS
	for v = 1, 10 do
		ok(listedAt[v] ~= nil, "vehicle " .. v .. " listed")
		local due = firstSeen[v] + 3 * MINUTE + 30000
		ok(listedAt[v] >= due and listedAt[v] <= due + 2 * PASS,
			"vehicle " .. v .. " listed " .. (listedAt[v] - firstSeen[v]) / 1000 .. " s after it first stood (designed 210 s, +<= 4.8)")
	end
	ok(blockedListed ~= nil, "blocked train listed")
	local due = blockedSeen + 5 * MINUTE + 30000
	ok(blockedListed >= due and blockedListed <= due + 2 * PASS,
		"train_blocked_by listed " .. (blockedListed - blockedSeen) / 1000 .. " s after the pair was first seen (designed 330 s)")
end)

test("failure counts: a failing group is dropped after FAIL_DROP_AFTER failures in a row, whichever state runs", function()
	seeded()
	addLine(1)
	addLine(2)
	W.stations[7] = { overflow = false, line = 1 }
	W.lineStationProblems = { { 1, 7, "StopUseless" }, { 2, 7, "StopUseless" } }
	local scripts = newStates(N_STATES)
	local state = fakeState()
	run(scripts, state, TPM)
	ok(alert(state, "station_useless:7:1:StopUseless") ~= nil, "station rows listed")
	local before = state.value.kindCounts.station_useless
	eq(before, 2)
	W.failStations = true
	local fails = 0
	local droppedAfter
	for _ = 1, 400 do
		runUntilGroup(scripts, state, 2)
		fails = fails + 1
		if (state.value.kindCounts.station_useless or 0) == 0 then
			droppedAfter = fails
			break
		end
		if fails < 10 then eq(state.value.kindCounts.station_useless, before, "carried while < 10 failures (" .. fails .. ")") end
	end
	-- 10th failure: merged with no alerts; the rows linger for the 30 s smoothing window (stations passes
	-- 2.4 s apart: missed for 31.2 s at the 13th pass after): gone at failure 23.
	ok(droppedAfter ~= nil and droppedAfter >= 10 and droppedAfter <= 23,
		"rows dropped after " .. tostring(droppedAfter) .. " failed stations passes (designed 10, + the smoothing window)")
	W.failStations = false
end)

test("rotations: line quality and line money cover every line in order, whichever state runs", function()
	seeded()
	for i = 1, 40 do addLine(i, { money = { 1000, 300, 200 } }) end
	local scripts = newStates(N_STATES)
	local state = fakeState()
	-- 10 lines passes from the mod being added
	for _ = 1, 10 do runUntilGroup(scripts, state, 1) end
	-- line quality: 8 lines per pass, continuing after the last measured line
	local expect = {}
	for i = 1, #W.measured do expect[i] = (i - 1) % 40 + 1 end
	eq(#W.measured, 80, "8 lines per pass")
	eq(W.measured, expect, "lines measured in rotation order")
	-- line money: 4 lines per pass after the shared cursor: every line checked once in 10 passes
	local seen, dup = {}, 0
	for _, l in ipairs(W.moneyChecked) do
		if seen[l] then dup = dup + 1 end
		seen[l] = true
	end
	local covered = 0
	for _ in pairs(seen) do covered = covered + 1 end
	eq(covered, 40, "every line's money checked within L / 4 passes")
	eq(dup, 0, "none twice")
end)

test("rotations: switching line_unprofitable off and on re-checks every line in the next pass, whichever state runs it", function()
	seeded()
	for i = 1, 8 do addLine(i) end
	local scripts = newStates(4)
	local state = fakeState()
	-- every state checks every line (the lines passes go to the 4 states in turn, 2 each)
	local k = 0
	for _ = 1, 8 do
		k = k % #scripts + 1
		runUntilGroup(scripts, state, 1, function(t) return t % 12 == 0 and k or 1 end)
	end
	-- off: one lines pass in state 1; on: the next lines pass in state 3
	scripts[2].handleEvent(nil, state, "", "ProblemRadar", "ProblemRadar.setSetting", { notify = { line_unprofitable = "off" } })
	runUntilGroup(scripts, state, 1, function() return 1 end)
	scripts[2].handleEvent(nil, state, "", "ProblemRadar", "ProblemRadar.setSetting", { notify = { line_unprofitable = "passive" } })
	local n = #W.moneyChecked
	runUntilGroup(scripts, state, 1, function() return 3 end)
	eq(#W.moneyChecked - n, 4, "4 lines re-checked at once (the cap), not a month later")
end)

test("averages: every state's samples count (the same averages as one state would compute)", function()
	local function simulate(nStates)
		seeded()
		addLine(1)
		addLine(2)
		local scripts = newStates(nStates)
		local state = fakeState()
		local seq = 7
		for _ = 1, TPM * 6 do -- 6 game minutes = 3 game months
			if W.tick % 12 == 11 then
				-- noisy utilisation before each lines pass (same sequence in both runs)
				seq = (seq * 1103515245 + 12345) % 2147483648
				W.lines[1].used = seq % 100
				W.lines[2].used = (seq // 100) % 100
			end
			tick(scripts, state)
		end
		return state.value.memory.useAvg
	end
	local one = simulate(1)
	local many = simulate(N_STATES)
	for _, l in ipairs({ 1, 2 }) do
		eq(many[l][2], one[l][2], "same tracking start")
		eq(many[l][3], one[l][3], "same last sample")
		ok(math.abs(many[l][1] - one[l][1]) <= 10,
			"line " .. l .. ": " .. many[l][1] .. " bp with " .. N_STATES .. " states vs " .. one[l][1] .. " with one")
	end
end)

---------------------------------------------------------------------------
-- state.rt: old saves and garbage

test("state.rt: a v6 save without it loads and scans; garbage is sanitised; empty parts are not stored", function()
	local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"
	-- an older v6 state (no rt): kept as is by upgradeState, not a change
	local old = checks.freshState()
	local s, changed = checks.upgradeState(deepcopy(old))
	eq(changed, false)
	eq(s.rt, nil)
	-- carried by upgradeState and merge
	old.rt = { lineCursor = 5 }
	eq(checks.upgradeState(deepcopy(old)).rt, { lineCursor = 5 })
	eq(checks.merge(deepcopy(old), "fleet", {}, 1000).rt, { lineCursor = 5 })
	-- garbage
	local r = checks.cleanRuntime({ prime = 3, budget = { windowStart = "x" }, fails = { lines = 2.0, x = -1, [3] = 4 },
		lineCursor = 7.0, young = { at = 100, stopped = { [5] = 50.0, x = 1 }, blockedSince = "no" }, ineligible = { [9] = "t" } })
	eq(r.prime, nil)
	eq(r.budget, nil)
	eq(r.fails, { lines = 2 })
	eq(r.lineCursor, 7)
	eq(r.young, { at = 100, stopped = { [5] = 50 }, blockedSince = {}, blockedBy = {} })
	eq(r.ineligible, {})
	eq(checks.cleanRuntime(nil), {})
	eq(checks.cleanRuntime("x"), {})
	-- pack: empty parts dropped, nil when nothing is left
	eq(checks.packRuntime({ fails = {}, ineligible = {}, prime = { all = false, kinds = {}, seen = { lines = true } } }), nil)
	eq(checks.packRuntime({ fails = { stuck = 1 } }), { fails = { stuck = 1 } })
	ok(checks.sameRuntime(nil, nil))
	ok(checks.sameRuntime({ lineCursor = 5 }, { lineCursor = 5.0 }))
	ok(not checks.sameRuntime({ lineCursor = 5 }, nil))
	ok(not checks.sameRuntime({ fails = { stuck = 1 } }, { fails = { stuck = 2 } }))
	-- youngTimers is the complement of agedTimers
	local since = { [1] = 0, [2] = 21000, [3] = 29000 }
	eq(checks.youngTimers(since, 50000, 30000), { [2] = 21000, [3] = 29000 })
	eq(checks.agedTimers(since, 50000, 30000), { [1] = 0 })
end)

test("state.rt: an old save without it runs every group in every state without errors; the window's seq stays when idle", function()
	seeded()
	addLine(1)
	local scripts = newStates(3)
	local state = fakeState()
	local old = ug_require("square_problem_radar::/radar/radar_checks.tl").freshState()
	old.version = 6
	state.value = old
	clear_logs()
	run(scripts, state, TPM)
	for _, e in ipairs(log_entries()) do ok(e.level ~= "warning", e.msg) end
	local seq = state.value.seq
	run(scripts, state, TPM)
	eq(state.value.seq, seq, "nothing the window shows changed")
end)
