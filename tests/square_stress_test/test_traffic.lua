-- stress_traffic.tl against a fake api: buying runs one purchase at a time (SetLine in the buy callback,
-- the next buy only after SetLine answered), lines without a vehicle are skipped, the batch stops after
-- 3 failures in a row or when the money runs out, sold vehicles are tracked, and the readout.

local T = 0
local sent        -- every sendCommand: { cmd, cb }
local lines       -- player's lines
local lineVehicles -- line -> {vehicle}
local exists      -- entity -> bool
local depotOf     -- vehicle -> depot (findBestLineAndDepotForVehicle)
local balance
local partPrice
local noCosts
local nextVehicle
local persons
local notVehicle  -- ids that exist but are no longer transport vehicles

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			ComponentType = { TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE", GAME_TIME = "GAME_TIME" },
			TransportVehicleConfig = { new = function(c)
				local parts = {}
				for i, p in ipairs(c.vehicles) do
					parts[i] = { part = { modelId = p.part.modelId, compartment2loadConfig = { 0, 0 } }, purchaseTime = 0 }
				end
				return { vehicles = parts, vehicleGroups = c.vehicleGroups }
			end },
			JournalEntry = { new = function() return { category = {} } end, Type = { OTHER = "OTHER" } },
		},
		res = { getBaseConfig = function() return { noCosts = noCosts } end },
		cmd = {
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
			makeVehicleBuyCmd = function(player, depot, cfg) return { kind = "buy", player = player, depot = depot, cfg = cfg } end,
			makeVehicleSetLineCmd = function(v, line, stop) return { kind = "setLine", v = v, line = line, stop = stop } end,
			makeVehicleSellCmd = function(vs) return { kind = "sell", vs = vs } end,
		},
		engine = {
			getEntitiesWithComponent = function(ct)
				eq(ct, "TRANSPORT_VEHICLE")
				local out = {}
				for e, ok_ in pairs(exists) do if ok_ and e >= 100 then out[#out + 1] = e end end
				return out
			end,
			getComponent = function(e, ct)
				if ct == "GAME_TIME" then return { gameTime = 12345 } end
				if ct == "TRANSPORT_VEHICLE" then
					if notVehicle[e] then return nil end
					return { depot = -1, transportVehicleConfig = { vehicles = { { part = { modelId = e * 10 } }, { part = { modelId = e * 10 + 1 } } }, vehicleGroups = { 2 } } }
				end
			end,
			entityExists = function(e) return exists[e] == true end,
			util = {
				getEntityName = function(e) return "Line" .. e end,
				getPlayer = function() return 7 end,
				getWorld = function() return 0 end,
				finance = { getPlayersBalance = function() return balance end },
				vehicle = {
					findBestLineAndDepotForVehicle = function(v) return { -1, depotOf[v] or -1 } end,
					getPartPrice = function(_part) return partPrice end,
				},
			},
			system = {
				lineSystem = { getLinesForPlayer = function(p) eq(p, 7) return lines end },
				transportVehicleSystem = { getLineVehicles = function(l) return lineVehicles[l] or {} end },
				simPersonSystem = { getCount = function() return persons end },
			},
		},
	}
end

local rt, traffic, logic
before_each(function()
	T, sent, nextVehicle, balance, partPrice, noCosts, persons, notVehicle = 0, {}, 500, 1e9, 1000, false, 4321, {}
	lines = { 1, 2, 3 }
	lineVehicles = { [1] = { 101 }, [2] = {}, [3] = { 103, 104 } }
	exists = { [1] = true, [2] = true, [3] = true, [101] = true, [103] = true, [104] = true }
	depotOf = { [101] = 11, [103] = 13 }
	reset_modules()
	set_global("api", fakeApi())
	clear_logs()
	rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true -- the notifications event is tested in test_runtime.lua
	traffic = ug_require "square_stress_test::/stress/gui/stress_traffic.tl"
	logic = ug_require "square_stress_test::/stress/stress_logic.tl"
end)

local function frames(n) for _ = 1, n do rt.tick() end end

--- Answers command k: a buy creates a vehicle; success false = refused.
local function answer(k, success)
	local s = sent[k]
	local data = s.cmd
	if s.cmd.kind == "buy" and success ~= false then
		nextVehicle = nextVehicle + 1
		exists[nextVehicle] = true
		data = { resultVehicleEntity = nextVehicle }
	elseif s.cmd.kind == "sell" and success ~= false then
		for _, v in ipairs(s.cmd.vs) do exists[v] = nil end
	end
	s.cb(data, success ~= false, {})
end

local function allLog() return table.concat(rt.recent, "\n") end

test("serial buying: one buy in flight, SetLine in its callback, next buy only after SetLine", function()
	traffic.ui.perLine = 1 -- 1 per line
	traffic.addVehicles()
	frames(3)
	eq(#sent, 1)
	eq(sent[1].cmd.kind, "buy")
	eq(sent[1].cmd.depot, 11)
	eq(sent[1].cmd.player, 7)
	-- the config copies the template's models and wagons, with fresh purchase data
	eq(sent[1].cmd.cfg.vehicles[1].part.modelId, 1010)
	eq(sent[1].cmd.cfg.vehicles[2].part.modelId, 1011)
	eq(sent[1].cmd.cfg.vehicles[1].purchaseTime, 12345)
	eq(sent[1].cmd.cfg.vehicles[1].maintenanceState, 1)
	eq(sent[1].cmd.cfg.vehicles[1].autoLoadConfig, { true, true })
	eq(logic.progress(rt.queue), "Buying 1/2 (+1 job queued)")
	answer(1)
	frames(3)
	eq(#sent, 2)
	eq(sent[2].cmd, { kind = "setLine", v = 501, line = 1, stop = 0 })
	answer(2)
	frames(2)
	eq(#sent, 3)
	eq(sent[3].cmd.kind, "buy")
	eq(sent[3].cmd.depot, 13) -- line 3's template 103
	answer(3)
	frames(1)
	answer(4)
	frames(3)
	eq(#sent, 4)
	eq(#rt.queue.jobs, 0)
	eq(traffic.added, { 501, 502 })
	local all = allLog()
	ok(all:find("line 2 (Line2) has no vehicle to copy; skipped", 1, true), all)
	ok(all:find("add_vehicles_1 summary planned=2 bought=2 setLine=2 failed=0", 1, true), all)
	ok(all:find("action=add_vehicles_1 count=2", 1, true), all)
end)

test("N per line goes round robin over the lines", function()
	traffic.ui.perLine = 2 -- 5 per line
	traffic.addVehicles()
	local depots = {}
	for _ = 1, 30 do
		frames(1)
		for k = 1, #sent do
			if not sent[k].answered then
				sent[k].answered = true
				if sent[k].cmd.kind == "buy" then depots[#depots + 1] = sent[k].cmd.depot end
				answer(k)
			end
		end
	end
	eq(depots, { 11, 13, 11, 13, 11, 13, 11, 13, 11, 13 })
	eq(#traffic.added, 10)
end)

test("no line with a vehicle: logs and queues nothing", function()
	lineVehicles = {}
	traffic.addVehicles()
	eq(#rt.queue.jobs, 0)
	ok(allLog():find("no line with a vehicle (lines=3)", 1, true), allLog())
end)

test("stops after 3 failed buys in a row", function()
	traffic.ui.perLine = 3 -- 10 per line = 20
	traffic.addVehicles()
	for k = 1, 3 do
		frames(2)
		eq(#sent, k)
		answer(k, false)
	end
	frames(5)
	eq(#sent, 3)
	eq(#rt.queue.jobs, 0)
	local all = allLog()
	ok(all:find("stopped after 3 failures in a row", 1, true), all)
	ok(all:find("summary planned=20 bought=0 setLine=0 failed=3", 1, true), all)
	ok(all:find("action=add_vehicles_10 count=3", 1, true), all)
end)

test("a success resets the failure streak", function()
	traffic.ui.perLine = 3
	traffic.addVehicles()
	local outcomes = { false, false, true, false, false, false }
	local k = 0
	for _ = 1, 40 do
		frames(1)
		for j = 1, #sent do
			if not sent[j].answered then
				sent[j].answered = true
				if sent[j].cmd.kind == "buy" then
					k = k + 1
					answer(j, outcomes[k] == true)
				else
					answer(j)
				end
			end
		end
	end
	-- buys: F F T(+setLine) F F F -> stops after the 6th buy
	local buys = 0
	for _, s in ipairs(sent) do if s.cmd.kind == "buy" then buys = buys + 1 end end
	eq(buys, 6)
	eq(#rt.queue.jobs, 0)
end)

test("a failed SetLine counts as a failure; an error in a step too", function()
	traffic.addVehicles()
	frames(2)
	answer(1)
	frames(1)
	answer(2, false)
	frames(2)
	ok(allLog():find("setLine failed vehicle=501 line=1", 1, true), allLog())
	eq(sent[3].cmd.kind, "buy") -- continues (1 failure)
end)

test("a line without a depot is skipped once, not failed per vehicle", function()
	depotOf[101] = nil
	traffic.ui.perLine = 2 -- 5 per line
	traffic.addVehicles()
	for _ = 1, 30 do
		frames(1)
		for k = 1, #sent do if not sent[k].answered then sent[k].answered = true answer(k) end end
	end
	local all = allLog()
	local _, n = all:gsub("no depot", "")
	eq(n, 1)
	eq(#traffic.added, 5)
	ok(all:find("lineSkips=5", 1, true), all)
end)

test("balance too low without keep-balance: logs and stops before buying", function()
	balance = 1500 -- price 2 parts x 1000
	traffic.addVehicles()
	frames(3)
	eq(#sent, 0)
	eq(#rt.queue.jobs, 0)
	ok(allLog():find("can't pay the next vehicle", 1, true), allLog())
end)

test("keep-balance on or no costs: buys even when the balance is low", function()
	balance = 10
	rt.keepBalance = true
	traffic.addVehicles()
	frames(1)
	local buys = 0
	for _, s in ipairs(sent) do if s.cmd.kind == "buy" then buys = buys + 1 end end
	eq(buys, 1)
	rt.keepBalance = false
	logic.clear(rt.queue)
	sent = {}
	noCosts = true
	traffic.addVehicles()
	frames(1)
	eq(#sent, 1)
end)

test("sell added vehicles: one sell at a time, tracked ids forgotten when sold or gone", function()
	traffic.added = { 501, 502, 503 }
	exists[501], exists[502] = true, true -- 503 is already gone
	traffic.removeAdded()
	frames(2)
	eq(#sent, 1)
	eq(sent[1].cmd, { kind = "sell", vs = { 501 } })
	eq(logic.progress(rt.queue), "Selling 1/3 (+1 job queued)")
	answer(1)
	frames(2)
	eq(#sent, 2)
	answer(2, false)
	frames(3)
	eq(#sent, 2) -- 503 doesn't exist: no command
	eq(traffic.added, { 502 })
	local all = allLog()
	ok(all:find("remove_vehicles summary requested=3 sold=1 gone=1 failed=1 left=1", 1, true), all)
end)

test("sell with nothing added: logs only", function()
	traffic.removeAdded()
	eq(#rt.queue.jobs, 0)
	ok(allLog():find("no vehicles added in this session", 1, true), allLog())
end)

test("bought vehicles are tracked for selling", function()
	traffic.addVehicles()
	frames(1) answer(1) frames(1) answer(2) frames(1) answer(3) frames(1) answer(4) frames(2)
	eq(traffic.added, { 501, 502 })
	traffic.removeAdded()
	frames(1)
	eq(sent[5].cmd, { kind = "sell", vs = { 501 } })
end)

test("readout: lines, transport vehicles, sim persons, added", function()
	eq(traffic.readout(), "Lines 3   Vehicles 3   Sim persons 4.3k")
	traffic.added = { 1, 2 }
	eq(traffic.readout(), "Lines 3   Vehicles 3   Sim persons 4.3k   Added 2")
	api.engine.system.simPersonSystem.getCount = function() error("no") end
	eq(traffic.readout(), "Lines 3   Vehicles 3   Added 2")
end)

test("uiSignature changes with the selection and the added count", function()
	local a = traffic.uiSignature()
	traffic.ui.perLine = 2
	local b = traffic.uiSignature()
	traffic.added[1] = 9
	ok(a ~= b and b ~= traffic.uiSignature())
end)

test("loading the module calls no engine API", function()
	reset_modules()
	set_global("api", setmetatable({}, { __index = function(_, k) error("api." .. tostring(k) .. " used at load time") end }))
	local t = ug_require "square_stress_test::/stress/gui/stress_traffic.tl"
	eq(type(t.addVehicles), "function")
end)

test("debounce: add / sell vehicles refuse while either is queued or running", function()
	traffic.ui.perLine = 1
	traffic.addVehicles()
	traffic.addVehicles()
	traffic.added = { 101 }
	traffic.removeAdded()
	local all = allLog()
	local _, plans = all:gsub("lines x 1 = 2 vehicles", "")
	eq(plans, 1)
	ok(all:find("Busy: add_vehicles_1: add_vehicles_1 is still queued or running", 1, true), all)
	ok(all:find("Busy: remove_vehicles: add_vehicles_1 is still queued or running", 1, true), all)
	eq(#rt.queue.jobs, 2)   -- one buy job and its summary
end)

test("guards: no SetLine on a bought id that is not a vehicle; a tracked id that changed type is never sold", function()
	traffic.ui.perLine = 1
	traffic.addVehicles()
	frames(1)
	notVehicle[501] = true
	answer(1)
	frames(3)
	eq(sent[2].cmd.kind, "buy")   -- no setLine for 501; the next line's buy follows
	ok(allLog():find("bought vehicle=501 is not a vehicle of yours now; setLine skipped", 1, true), allLog())
	answer(2) frames(1) answer(3) frames(3)
	sent = {}
	traffic.added = { 103 }
	notVehicle[103] = true
	traffic.removeAdded()
	frames(3)
	eq(#sent, 0)
	ok(allLog():find("remove_vehicles summary requested=1 sold=0 gone=1", 1, true), allLog())
end)
