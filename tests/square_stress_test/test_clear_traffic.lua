-- stress_traffic.tl Clear traffic against a fake api: only drivers get makeSimPersonSetStateCmd(e, 2)
-- (DRIVE + MOVE_PATH, not at a vehicle, never a TRANSPORT_VEHICLE), the scan runs in chunks of
-- CLEAR_SCAN_PER_FRAME over a snapshot, the commands go out CLEAR_SEND_PER_FRAME per frame without
-- waiting on callbacks, and Keep traffic cleared repeats, skips a busy cycle and stops on uncheck or
-- when the queue is cleared.

local T = 0
local FRAME_US = 16667
local sent      -- every sendCommand: { cmd, cb }
local persons   -- entity -> { mode, path, atP, atE, tv } (mode 1 = DRIVE)
local order     -- SIM_PERSON list order
local listCalls -- getEntitiesWithComponent(SIM_PERSON) calls

local CT = {
	SIM_PERSON = "SIM_PERSON", MOVE_PATH = "MOVE_PATH", SIM_PERSON_AT_VEHICLE = "SIM_PERSON_AT_VEHICLE",
	SIM_ENTITY_AT_VEHICLE = "SIM_ENTITY_AT_VEHICLE", TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE",
	TOWN_BUILDING = "TOWN_BUILDING", CONSTRUCTION = "CONSTRUCTION",
}
local buildings -- building entity -> {x, y}; town -> list in town2buildings
local town2buildings

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = CT,
			enum = { MoveMode = { WALK = 0, DRIVE = 1, LINES = 2 } },
		},
		cmd = {
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
			debug = {
				makeSimPersonSetStateCmd = function(e, state) return { kind = "setState", e = e, state = state } end,
			},
		},
		engine = {
			getEntitiesWithComponent = function(ct)
				if ct == CT.SIM_PERSON then
					listCalls = listCalls + 1
					local out = {}
					for i, e in ipairs(order) do out[i] = e end
					return out
				end
				if ct == CT.TRANSPORT_VEHICLE then
					local out = {}
					for e, p in pairs(persons) do if p.tv then out[#out + 1] = e end end
					return out
				end
				error("Cannot loop over this component type")
			end,
			getComponent = function(e, ct)
				if ct == CT.TOWN_BUILDING then return buildings[e] and { construction = e + 100000 } or nil end
				if ct == CT.CONSTRUCTION then
					local b = buildings[e - 100000]
					return b and { transf = { getTransl = function() return { x = b[1], y = b[2], z = 0 } end } } or nil
				end
				local p = persons[e]
				if p == nil then return nil end
				if ct == CT.SIM_PERSON then return { lastMoveMode = p.mode } end
				if ct == CT.MOVE_PATH then return p.path and {} or nil end
				if ct == CT.SIM_PERSON_AT_VEHICLE then return p.atP and {} or nil end
				if ct == CT.SIM_ENTITY_AT_VEHICLE then return p.atE and {} or nil end
				if ct == CT.TRANSPORT_VEHICLE then return p.tv and {} or nil end
			end,
			entityExists = function(e) return persons[e] ~= nil end,
			util = {
				getPlayer = function() return 7 end,
				vehicle = { getPosition = function(e)
					local p = persons[e]
					if p == nil or p.pos == nil then error("no position") end
					return { x = p.pos[1], y = p.pos[2], z = 0 }
				end },
			},
			system = {
				townBuildingSystem = { getTown2BuildingMap = function() return town2buildings end },
				lineSystem = { getLinesForPlayer = function() return {} end },
				simPersonSystem = { getCount = function() return #order end },
			},
		},
	}
end

local rt, traffic, logic
local windowLines

local function addPerson(e, p)
	persons[e] = p
	order[#order + 1] = e
end

local function addDrivers(first, n)
	for e = first, first + n - 1 do addPerson(e, { mode = 1, path = true }) end
end

before_each(function()
	T, sent, persons, order, listCalls = 0, {}, {}, {}, 0
	buildings, town2buildings = {}, {}
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	traffic = ug_require "square_stress_test::/stress/gui/stress_traffic.tl"
	logic = ug_require "square_stress_test::/stress/stress_logic.tl"
	windowLines = {}
	local log0 = rt.log
	rt.log = function(msg)
		windowLines[#windowLines + 1] = msg
		log0(msg)
	end
end)

local function frames(n)
	for _ = 1, n do
		T = T + FRAME_US
		rt.tick()
	end
end

local function answerAll(success)
	for _, s in ipairs(sent) do
		if not s.answered then
			s.answered = true
			s.cb(s.cmd, success ~= false)
		end
	end
end

local function window() return table.concat(windowLines, "\n") end

local function count(pattern)
	local n = 0
	for _, l in ipairs(windowLines) do if l:find(pattern, 1, true) then n = n + 1 end end
	return n
end

local function details(pattern)
	local n = 0
	for _, l in ipairs(log_entries()) do if l.msg:find(pattern, 1, true) then n = n + 1 end end
	return n
end

test("only drivers get jump home; transport vehicles and persons in vehicles are untouched", function()
	addPerson(1, { mode = 1, path = true })              -- driving
	addPerson(2, { mode = 0, path = true })              -- walking
	addPerson(3, { mode = 1, path = false })             -- DRIVE but at home
	addPerson(4, { mode = 1, path = true, atP = true })  -- seated in a vehicle
	addPerson(5, { mode = 1, path = true, atE = true })
	addPerson(6, { mode = 1, path = true, tv = true })   -- a transport vehicle (never)
	addPerson(7, { mode = 1, path = true })
	addPerson(8, { mode = 2, path = true })              -- on a line
	traffic.clearTraffic()
	frames(3)
	eq(#sent, 2)
	eq(sent[1].cmd, { kind = "setState", e = 1, state = 2 })
	eq(sent[2].cmd, { kind = "setState", e = 7, state = 2 })
	for _, s in ipairs(sent) do ok(s.cmd.e ~= 6, "transport vehicle touched") end
	eq(traffic.driving, 2)
	eq(count("clear_traffic scanned"), 0) -- callbacks not in yet
	answerAll()
	frames(1)
	ok(window():find("[SQST] clear_traffic scanned=8 drivers=2 sent=2 ok=2 ms=", 1, true), window())
	eq(#rt.queue.jobs, 0)
	ok(traffic.readout():find("Driving now 2", 1, true), traffic.readout())
end)

test("readout: no Driving now before the first scan", function()
	addDrivers(1, 3)
	ok(not traffic.readout():find("Driving", 1, true), traffic.readout())
end)

test("sends in batches of 200 per frame without waiting on callbacks; ok counted as they come", function()
	addDrivers(1, 450)
	traffic.clearTraffic()
	frames(1)
	eq(#sent, 0)        -- frame 1: snapshot + scan
	eq(traffic.cycle.scanned, 450)
	frames(1)
	eq(#sent, 200)
	frames(1)
	eq(#sent, 400)
	eq(logic.progress(rt.queue), "Clearing traffic 3/4")
	frames(1)
	eq(#sent, 450)
	frames(2)
	eq(#sent, 450)
	eq(#rt.queue.jobs, 0)
	for k = 1, 450 do
		sent[k].answered = true
		sent[k].cb(sent[k].cmd, k % 10 ~= 0) -- every 10th fails
	end
	frames(1)
	ok(window():find("clear_traffic scanned=450 drivers=450 sent=450 ok=405 ms=", 1, true), window())
	eq(count("cmd "), 0) -- no line per failed command
end)

test("the scan runs 5000 persons per frame over one snapshot", function()
	for e = 1, 12000 do addPerson(e, { mode = (e % 1000 == 0) and 1 or 0, path = true }) end
	traffic.clearTraffic()
	frames(1)
	eq(traffic.cycle.scanned, 5000)
	eq(#traffic.cycle.drivers, 5)
	addPerson(20000, { mode = 1, path = true }) -- joins after the snapshot: not seen in this cycle
	frames(1)
	eq(traffic.cycle.scanned, 10000)
	eq(traffic.driving, nil) -- set when the scan finishes
	frames(1)
	eq(traffic.cycle.scanned, 12000)
	eq(traffic.driving, 12)
	eq(listCalls, 1)
	frames(1)
	eq(#sent, 12)
	for _, s in ipairs(sent) do ok(s.cmd.e ~= 20000) end
end)

test("other queued jobs keep running during a clear (one chunk per frame)", function()
	for e = 1, 20000 do addPerson(e, { mode = 0 }) end
	traffic.clearTraffic()
	local ran = 0
	rt.enqueue("other", 6, function() ran = ran + 1 end)
	frames(1)
	eq(traffic.cycle.scanned, 5000)
	eq(ran, 3) -- 4 steps per frame: 1 clear chunk + 3 others
	frames(1)
	eq(ran, 6)
end)

test("a second Clear while one runs is refused", function()
	addDrivers(1, 3)
	traffic.clearTraffic()
	traffic.clearTraffic()
	ok(window():find("a clear is still running", 1, true), window())
	eq(#rt.queue.jobs, 1)
end)

test("no debug command: logs and does nothing", function()
	api.cmd.debug = nil
	addDrivers(1, 3)
	traffic.clearTraffic()
	eq(#rt.queue.jobs, 0)
	ok(window():find("makeSimPersonSetStateCmd is not available", 1, true), window())
end)

test("missing callbacks: the cycle ends after the timeout", function()
	addDrivers(1, 3)
	traffic.clearTraffic()
	frames(3)
	eq(#sent, 3)
	eq(traffic.cycle.finished, false)
	T = T + logic.CLEAR_CALLBACK_TIMEOUT_US
	frames(1)
	ok(window():find("sent=3 ok=0 ms=%d+ answered=0") or window():find("answered=0", 1, true), window())
	eq(traffic.cycle.finished, true)
end)

test("Clear queue mid-cycle ends the cycle", function()
	for e = 1, 12000 do addPerson(e, { mode = 1, path = true }) end
	traffic.clearTraffic()
	frames(1)
	rt.clearQueue()
	frames(2)
	eq(#sent, 0)
	ok(window():find("stopped (queue cleared)", 1, true), window())
end)

test("Keep cleared: repeats every interval with a fresh snapshot", function()
	addDrivers(1, 3)
	traffic.setKeepCleared(true) -- default every 5 s
	ok(window():find("keep_traffic_cleared on (every 5 s)", 1, true), window())
	frames(3)
	eq(#sent, 3)
	answerAll()
	frames(1)
	eq(listCalls, 1)
	addDrivers(10, 2)
	T = T + 5000000
	frames(3)
	eq(listCalls, 2)
	eq(#sent, 8)
	answerAll()
	frames(1)
	eq(details("[SQST] keep_traffic_cleared scanned="), 2)
end)

test("Keep cleared: skips a cycle while the previous one waits for callbacks", function()
	traffic.setClearInterval(1) -- 2 s
	addDrivers(1, 3)
	traffic.setKeepCleared(true)
	frames(3)
	eq(#sent, 3)
	T = T + 2000000
	frames(1) -- interval due, callbacks still missing
	eq(listCalls, 1)
	eq(details("cycle skipped"), 1)
	answerAll()
	frames(1)
	T = T + 2000000
	frames(3)
	eq(listCalls, 2)
end)

test("Keep cleared: unchecking stops the running cycle and the repeats", function()
	for e = 1, 12000 do addPerson(e, { mode = 1, path = true }) end
	traffic.setKeepCleared(true)
	frames(1)
	traffic.setKeepCleared(false)
	frames(5)
	eq(#sent, 0)
	T = T + 20000000
	frames(5)
	eq(listCalls, 1)
	eq(#sent, 0)
	ok(window():find("keep_traffic_cleared off", 1, true), window())
	eq(#rt.queue.jobs, 0)
end)

test("Keep cleared: Clear queue switches it off", function()
	addDrivers(1, 3)
	traffic.setKeepCleared(true)
	frames(3)
	answerAll()
	frames(1)
	rt.clearQueue()
	frames(1)
	eq(traffic.ui.keepCleared, false)
	ok(window():find("keep_traffic_cleared off (queue cleared)", 1, true), window())
	T = T + 20000000
	frames(3)
	eq(listCalls, 1)
end)

test("Keep cleared: at most one window summary per 30 s, per-cycle lines go to stdout only", function()
	traffic.setClearInterval(1) -- 2 s
	addDrivers(1, 2)
	traffic.setKeepCleared(true)
	for _ = 1, 30 do -- 60 s
		frames(3)
		answerAll()
		frames(1)
		T = T + 2000000
	end
	local summaries = count("keep_traffic_cleared cycles=")
	ok(summaries >= 2 and summaries <= 3, tostring(summaries))
	ok(details("[SQST] keep_traffic_cleared scanned=") >= 25)
	eq(count("keep_traffic_cleared scanned="), 0)
end)

test("uiSignature follows the Keep cleared box and the interval", function()
	local a = traffic.uiSignature()
	traffic.setKeepCleared(true)
	local b = traffic.uiSignature()
	traffic.setClearInterval(3)
	ok(a ~= b and b ~= traffic.uiSignature())
	traffic.setClearInterval(9) -- out of range: ignored
	eq(traffic.ui.clearInterval, 3)
end)

test("Keep cleared offers 2, 5, 10, 60 and 120 s", function()
	eq(logic.CLEAR_INTERVALS, { 2, 5, 10, 60, 120 })
	traffic.setClearInterval(5)
	eq(traffic.ui.clearInterval, 5)
	traffic.setClearInterval(2)
end)

---------------------------------------------------------------------------
-- Where

--- A town of buildings on a 3 x 3 grid 100 m apart around (x, y): area radius ~141 + 60 m.
local function town(id, x, y)
	local list = {}
	for i = -1, 1 do
		for j = -1, 1 do
			local b = id * 100 + (i + 1) * 3 + (j + 2)
			buildings[b] = { x + i * 100, y + j * 100 }
			list[#list + 1] = b
		end
	end
	town2buildings[id] = list
end

local function whereScenario()
	town(1, 0, 0)
	town(2, 2000, 0)
	addPerson(11, { mode = 1, path = true, pos = { 50, 50 } })     -- in town 1
	addPerson(12, { mode = 1, path = true, pos = { 1990, 150 } })  -- in town 2 (inside 141 + 60)
	addPerson(13, { mode = 1, path = true, pos = { 1000, 0 } })    -- between the towns (a junction)
	addPerson(14, { mode = 1, path = true, pos = { 2000, 300 } })  -- just outside town 2 (300 > 201)
	addPerson(15, { mode = 1, path = true })                       -- position unreadable
	addPerson(16, { mode = 0, pos = { 0, 0 } })                    -- walking: never
end

local function sentTo()
	local out = {}
	for _, x in ipairs(sent) do out[#out + 1] = x.cmd.e end
	table.sort(out)
	return out
end

test("Where = In towns: only drivers inside a town's area go home; the rest and unknown positions keep driving", function()
	whereScenario()
	traffic.ui.clearWhere = 2
	traffic.clearTraffic()
	frames(6)
	eq(sentTo(), { 11, 12 })
	answerAll(true)
	frames(2)
	local line = table.concat(windowLines, "\n")
	ok(line:find("drivers=2 sent=2 ok=2", 1, true), line)
	ok(line:find("where=In towns towns=2 kept=2 unknown=1", 1, true), line)
	eq(traffic.driving, 5)
end)

test("Where = Outside towns: the opposite set; Everywhere: every driver as before", function()
	whereScenario()
	traffic.ui.clearWhere = 3
	traffic.clearTraffic()
	frames(6)
	eq(sentTo(), { 13, 14 })
	answerAll(true)
	frames(2)
	sent = {}
	traffic.ui.clearWhere = 1
	traffic.clearTraffic()
	frames(6)
	eq(sentTo(), { 11, 12, 13, 14, 15 })
	answerAll(true)
	frames(2)
	ok(not windowLines[#windowLines]:find("where=", 1, true), windowLines[#windowLines])
end)

test("townArea, inTownArea, clearWanted", function()
	local a = logic.townArea({ { 0, 0 }, { 100, 0 } }, 60)
	near(a.x, 50)
	near(a.r, 110)
	eq(logic.townArea({}, 60), nil)
	eq(logic.inTownArea({ a }, 50, 100), true)
	eq(logic.inTownArea({ a }, 50, 120), false)
	eq(logic.clearWanted(1, false), true)
	eq(logic.clearWanted(2, false), false)
	eq(logic.clearWanted(3, false), true)
end)
