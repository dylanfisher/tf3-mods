-- Stress Test Traffic tab actions (PLAN.md Phase 3 part A): add vehicles to the player's lines, sell the
-- vehicles added in this session, and the traffic readout.
--
-- BUY FLOW (built on probe 5's code in stress_probes.tl, NOT verified in game yet; probe 5 needs a save
-- with a line): each new vehicle copies the config of its line's first vehicle (same models and wagons),
-- as the base "duplicate vehicles" handler does (base gui/line_vehicle_mgmt/manager_window.tl:8494-8526,
-- vehicle_react_util.tl:331-382: purchaseTime, maintenanceState 1, autoLoadConfig all true), and is
-- bought with makeVehicleBuyCmd at the depot api.engine.util.vehicle.findBestLineAndDepotForVehicle
-- returns for the original (api/tealdef/api/engine/util.d.tl:428; the same lookup the base handler
-- uses), falling back to the original's own depot if it is standing in one (TransportVehicle.depot).
-- makeVehicleSetLineCmd(new, line, 0) follows in the buy callback (VehicleBuyCommandData
-- .resultVehicleEntity, cmd.d.tl:424-433), then the job resumes: one purchase in flight at a time
-- (the queue's serial lane, stress_logic.tick).
--
-- DEFENSIVE: every step and callback is pcall'd, each failure writes one [SQST] line, and the batch
-- stops after logic.MAX_BUY_FAILURES failures in a row. A line whose depot can't be found is skipped
-- once (logged) instead of failing every step. Without "Keep balance" the batch stops when the balance
-- can't pay the next vehicle (part prices from api.engine.util.vehicle.getPartPrice, util.d.tl:472).
--
-- SELL: makeVehicleSellCmd({v}) (cmd.d.tl:908) for the vehicles bought here this session (ids kept in
-- memory only; a reload forgets them), one at a time.
--
-- CLEAR TRAFFIC (Phase 3B, docs/findings.md "Stress Test probes" fourth run): a private car is a SIM_PERSON
-- with lastMoveMode DRIVE, a MOVE_PATH and no SIM_PERSON_AT_VEHICLE / SIM_ENTITY_AT_VEHICLE (all 63
-- such persons of the census also had a LAND_VEHICLE). api.cmd.debug.makeSimPersonSetStateCmd(e, 2)
-- ("jump home", the base entity debug panel's list, gui/debug_panel/make_entity_debug_panel.tl:669-690)
-- put every tested driver at home within 2 s, from a GUI script in a normal game; they start their next
-- trip within ~15 s, hence Keep traffic cleared. One cycle = one queue job (maxPerTick 1: one chunk per
-- frame, on the Main Thread): step 1 snapshots getEntitiesWithComponent(SIM_PERSON) (iterable, 693 persons
-- read in 1 ms), each step scans logic.CLEAR_SCAN_PER_FRAME persons, then sends CLEAR_SEND_PER_FRAME
-- commands per step. Callbacks are only counted (no rt.send: a failed command must not log one line
-- each); the cycle's [SQST] line is written when every callback is in, or CLEAR_CALLBACK_TIMEOUT_US
-- after the last send. TRANSPORT_VEHICLE entities are never sent anything.
--
-- READOUT: lines (lineSystem.getLinesForPlayer), transport vehicles (TRANSPORT_VEHICLE is iterable,
-- docs/findings.md "Stress Test probes"), sim persons (simPersonSystem.getCount, system.d.tl:133-136)
-- and "Driving now" from the last clear scan (no scan only for the readout).

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime

local traffic : SquareStressTraffic = {
	ui = { perLine = 1, keepCleared = false, clearInterval = 2 },
	added = {},
}

---------------------------------------------------------------------------
-- Reads

local function entityName(e : integer) : string
	local ok, n = pcall(api.engine.util.getEntityName, e)
	return ok and tostring(n) or "?"
end

local function playerLines() : {integer}
	return api.engine.system.lineSystem.getLinesForPlayer(rt.player()) as {integer}
end

local function lineVehicles(line : integer) : {integer}
	local ok, vs = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, line)
	if not ok or vs == nil then return {} end
	return vs as {integer}
end

local function transportVehicle(v : integer) : Engine.Component.TransportVehicle
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
end

--- A copy of the vehicle's config ready to buy (probe 5 cloneConfig; base duplicate handler).
local function cloneConfig(vehicle : integer) : TransportVehicleConfig
	local tv = transportVehicle(vehicle)
	local cfg = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	local parts : {TransportVehiclePart} = {}
	for _, part in ipairs(cfg.vehicles) do
		part.purchaseTime = math.floor(gt.gameTime)
		part.maintenanceState = 1
		local auto : {boolean} = {}
		for k = 1, #part.part.compartment2loadConfig do auto[k] = true end
		part.autoLoadConfig = auto
		parts[#parts + 1] = part
	end
	cfg.vehicles = parts
	return cfg
end

--- Price of a config (sum of part prices), nil when unknown.
local function configPrice(cfg : TransportVehicleConfig) : number
	local prices : {number} = {}
	for i, part in ipairs(cfg.vehicles) do
		local ok, p = pcall(api.engine.util.vehicle.getPartPrice, part)
		if not ok or p == nil then return nil end
		prices[i] = p as number
	end
	return logic.configPrice(prices)
end

--- Whether building costs nothing (baseConfig.noCosts); false when unreadable.
local function noCosts() : boolean
	local ok, v = pcall(function() : boolean return api.res.getBaseConfig().noCosts end)
	return ok and v == true
end

--- The depot to buy a copy of this vehicle at, nil when there is none; second result: how it was found.
local function depotFor(vehicle : integer) : integer, string
	local ok, ld = pcall(api.engine.util.vehicle.findBestLineAndDepotForVehicle, vehicle)
	if ok and ld ~= nil and ld[2] ~= nil and ld[2] >= 0 then return ld[2], "best" end
	local okT, tv = pcall(transportVehicle, vehicle)
	if okT and tv ~= nil and tv.depot ~= nil and tv.depot >= 0 then return tv.depot, "own" end
	return nil, ok and "none found" or ("lookup error: " .. tostring(ld))
end

---------------------------------------------------------------------------
-- Add vehicles to lines

local VEHICLE_JOBS : {string} = { "add_vehicles_", "remove_vehicles" }

--- Logs and returns true when an add/sell vehicles job is still queued or running (no stacking).
local function refuseBusy(name : string) : boolean
	local busy = rt.busyJob(VEHICLE_JOBS)
	if busy == nil then return false end
	rt.log(string.format("[SQST] %s: refused, %s is still queued or running", name, busy))
	return true
end

function traffic.addVehicles()
	local n = logic.VEHICLES_PER_LINE[traffic.ui.perLine] or 1
	local name = string.format("add_vehicles_%d", n)
	if refuseBusy(name) then return end
	local lines : {SquareStressLineVehicle} = {}
	for _, line in ipairs(playerLines()) do
		lines[#lines + 1] = { line = line, vehicle = lineVehicles(line)[1] }
	end
	local plan, skipped = logic.buyPlan(lines, n)
	for _, line in ipairs(skipped) do
		rt.log(string.format("[SQST] %s: line %d (%s) has no vehicle to copy; skipped", name, line, entityName(line)))
	end
	if #plan == 0 then
		rt.log(string.format("[SQST] %s: no line with a vehicle (lines=%d)", name, #lines))
		return
	end
	rt.log(string.format("[SQST] %s: %d lines x %d = %d vehicles (%d skipped: no vehicle)", name, #lines - #skipped, n, #plan, #skipped))

	local failsInRow, bought, setLine, failed, lineSkips = 0, 0, 0, 0, 0
	local depots : {integer : integer} = {}       -- line -> depot
	local deadLines : {integer : boolean} = {}    -- lines with no depot (or no vehicle left)
	local stopReason : string = nil
	local balance0 = rt.balance()

	local function fail(job : SquareStressJob, what : string)
		failed = failed + 1
		failsInRow = failsInRow + 1
		rt.log(string.format("[SQST] %s %s (%d/%d failures in a row)", name, what, failsInRow, logic.MAX_BUY_FAILURES))
		if failsInRow >= logic.MAX_BUY_FAILURES then
			stopReason = string.format("%d failures in a row", failsInRow)
			rt.log(string.format("[SQST] %s stopped after %d failures in a row", name, failsInRow))
			logic.stop(job)
		else
			logic.resume(job)
		end
	end

	local function stop(job : SquareStressJob, reason : string)
		stopReason = reason
		rt.log(string.format("[SQST] %s stopped: %s", name, reason))
		logic.stop(job)
	end

	local function buyStep(i : integer, job : SquareStressJob)
		local entry = plan[i]
		local line = entry.line
		if deadLines[line] or not api.engine.entityExists(line) then
			lineSkips = lineSkips + 1
			logic.resume(job)
			return
		end
		-- The template: the planned vehicle, or the line's current first vehicle if it was sold since.
		local template = entry.vehicle
		if not api.engine.entityExists(template) then
			template = lineVehicles(line)[1]
			if template == nil then
				deadLines[line] = true
				lineSkips = lineSkips + 1
				rt.log(string.format("[SQST] %s: line %d (%s) has no vehicle left; skipped", name, line, entityName(line)))
				logic.resume(job)
				return
			end
		end
		local depot = depots[line]
		if depot == nil then
			local how : string
			depot, how = depotFor(template)
			if depot == nil then
				deadLines[line] = true
				lineSkips = lineSkips + 1
				rt.log(string.format("[SQST] %s: line %d (%s) vehicle %d: no depot (%s); line skipped", name, line,
					entityName(line), template, how))
				logic.resume(job)
				return
			end
			depots[line] = depot
			rt.detail(string.format("[SQST] %s line %d (%s) depot=%d (%s)", name, line, entityName(line), depot, how))
		end
		local cfg = cloneConfig(template)
		if not rt.keepBalance and not noCosts() then
			local price = configPrice(cfg)
			local balance = rt.balance()
			if not logic.canAfford(balance, price) then
				stop(job, string.format("balance %s can't pay the next vehicle (%s); tick Keep balance or add money",
					logic.formatMoney(balance), logic.formatMoney(price)))
				return
			end
		end
		local t0 = rt.nowUs()
		rt.send(name .. ":buy", api.cmd.makeVehicleBuyCmd(rt.player(), depot, cfg), function(success : boolean, data : any)
			if not success then
				fail(job, string.format("%d/%d buy failed line=%d depot=%d template=%d", i, #plan, line, depot, template))
				return
			end
			local newV = (data as VehicleBuyCommandData).resultVehicleEntity
			if newV == nil or newV < 0 then
				fail(job, string.format("%d/%d buy succeeded but returned no vehicle line=%d depot=%d", i, #plan, line, depot))
				return
			end
			bought = bought + 1
			traffic.added[#traffic.added + 1] = newV
			rt.detail(string.format("[SQST] %s %d/%d bought vehicle=%d depot=%d", name, i, #plan, newV, depot))
			if not rt.isVehicle(newV) or not rt.ownedByPlayer(newV) then
				fail(job, string.format("%d/%d bought vehicle=%d is not a vehicle of yours now; setLine skipped", i, #plan, newV))
				return
			end
			local ok, err : boolean, any = pcall(rt.send, name .. ":setLine", api.cmd.makeVehicleSetLineCmd(newV, line, 0),
				function(ok2 : boolean, _d : any)
					rt.detail(string.format("[SQST] %s %d/%d line=%d (%s) vehicle=%d depot=%d setLine=%s ms=%.0f", name, i,
						#plan, line, entityName(line), newV, depot, tostring(ok2), (rt.nowUs() - t0) / 1000))
					if ok2 then
						setLine = setLine + 1
						failsInRow = 0
						logic.resume(job)
					else
						fail(job, string.format("%d/%d setLine failed vehicle=%d line=%d (bought, stays in the depot)", i, #plan, newV, line))
					end
				end)
			if not ok then fail(job, string.format("%d/%d setLine error vehicle=%d: %s", i, #plan, newV, tostring(err))) end
		end)
	end

	rt.enqueue(name, #plan, function(i : integer, job : SquareStressJob)
		local ok, err : boolean, any = pcall(buyStep, i, job)
		if not ok then fail(job, string.format("%d/%d error: %s", i, #plan, tostring(err))) end
	end, { serial = true, label = "Buying", timeoutMs = logic.VEHICLE_TIMEOUT_MS })

	-- Runs right after the buy job (the next job in the serial lane), however it ended.
	rt.enqueue(name .. ":summary", 1, function(_i : integer, job : SquareStressJob)
		logic.resume(job)
		rt.log(string.format("[SQST] %s summary planned=%d bought=%d setLine=%d failed=%d lineSkips=%d balance %s->%s%s",
			name, #plan, bought, setLine, failed, lineSkips, logic.formatMoney(balance0), logic.formatMoney(rt.balance()),
			stopReason ~= nil and (" stopped: " .. stopReason) or ""))
	end, { serial = true, quiet = true })
end

---------------------------------------------------------------------------
-- Remove added vehicles

local function forget(v : integer)
	for k = #traffic.added, 1, -1 do
		if traffic.added[k] == v then table.remove(traffic.added, k) end
	end
end

function traffic.removeAdded()
	local name = "remove_vehicles"
	local list : {integer} = {}
	for i, v in ipairs(traffic.added) do list[i] = v end
	if #list == 0 then
		rt.log("[SQST] " .. name .. ": no vehicles added in this session")
		return
	end
	if refuseBusy(name) then return end
	local sold, gone, failed = 0, 0, 0
	rt.enqueue(name, #list, function(i : integer, job : SquareStressJob)
		local v = list[i]
		if not rt.isVehicle(v) then   -- gone, or the id now names something else: never sell it
			gone = gone + 1
			forget(v)
			logic.resume(job)
			return
		end
		local ok, err : boolean, any = pcall(rt.send, name, api.cmd.makeVehicleSellCmd({ v }), function(success : boolean, _d : any)
			if success then
				sold = sold + 1
				forget(v)
			else
				failed = failed + 1
				rt.log(string.format("[SQST] %s %d/%d sell failed vehicle=%d", name, i, #list, v))
			end
			rt.detail(string.format("[SQST] %s %d/%d vehicle=%d success=%s", name, i, #list, v, tostring(success)))
			logic.resume(job)
		end)
		if not ok then
			failed = failed + 1
			rt.log(string.format("[SQST] %s %d/%d error vehicle=%d: %s", name, i, #list, v, tostring(err)))
			logic.resume(job)
		end
	end, { serial = true, label = "Selling", timeoutMs = logic.VEHICLE_TIMEOUT_MS })
	rt.enqueue(name .. ":summary", 1, function(_i : integer, job : SquareStressJob)
		logic.resume(job)
		rt.log(string.format("[SQST] %s summary requested=%d sold=%d gone=%d failed=%d left=%d", name, #list, sold, gone,
			failed, #traffic.added))
	end, { serial = true, quiet = true })
end

---------------------------------------------------------------------------
-- Readout (called every few seconds while the window is open, never per frame)

function traffic.readout() : string
	local function count(fn : function() : integer) : integer
		local ok, n = pcall(fn)
		return ok and n or nil
	end
	local lines = count(function() : integer return #playerLines() end)
	local vehicles = count(function() : integer
		return #api.engine.getEntitiesWithComponent(api.type.ComponentType.TRANSPORT_VEHICLE)
	end)
	local persons = count(function() : integer return api.engine.system.simPersonSystem.getCount() end)
	return logic.trafficReadout(lines, vehicles, persons, #traffic.added, traffic.driving)
end

function traffic.uiSignature() : string
	return string.format("%d/%d/%s/%d", traffic.ui.perLine, #traffic.added, tostring(traffic.ui.keepCleared),
		traffic.ui.clearInterval)
end

---------------------------------------------------------------------------
-- Clear traffic

local driveMode : any = nil   -- MoveMode.DRIVE, resolved on first use (1 in game, docs/findings.md)

local function driveValue() : any
	if driveMode == nil then
		local ok, v = pcall(function() : any return (api.type["enum"] as {string : {string : any}}).MoveMode.DRIVE end)
		driveMode = (ok and v ~= nil) and v or 1
	end
	return driveMode
end

local function has(e : integer, ct : Engine.ComponentType) : boolean
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	return ok and c ~= nil
end

--- Driving a car right now (logic.isDriver). The cheap test first: only DRIVE persons get more reads.
local function isDriver(e : integer) : boolean
	local CT = api.type.ComponentType
	local ok, sp : boolean, any = pcall(api.engine.getComponent, e, CT.SIM_PERSON)
	if not ok or sp == nil then return false end
	local drive = (sp as Engine.Component.SimPerson).lastMoveMode == driveValue()
	if not drive then return false end
	return logic.isDriver(drive, has(e, CT.MOVE_PATH),
		has(e, CT.SIM_PERSON_AT_VEHICLE) or has(e, CT.SIM_ENTITY_AT_VEHICLE), has(e, CT.TRANSPORT_VEHICLE))
end

-- Keep traffic cleared state (session only)
local nextCycleUs = 0
local clearsSeen = 0          -- rt.queueClears when Keep cleared was switched on
local summary = { cycles = 0, skipped = 0, drivers = 0, sent = 0, ok = 0 }
local lastSummaryUs : integer = nil

local function resetSummary()
	summary.cycles, summary.skipped, summary.drivers, summary.sent, summary.ok = 0, 0, 0, 0, 0
end

local function intervalUs() : integer
	return math.floor((logic.CLEAR_INTERVALS[traffic.ui.clearInterval] or 5) * 1000000)
end

local function busy() : boolean
	return traffic.cycle ~= nil and not traffic.cycle.finished
end

--- Writes the cycle's line (manual: window log; Keep cleared: stdout.txt, plus a window summary at
--- most every CLEAR_SUMMARY_US) and lets the next cycle start.
local function finishCycle(c : SquareStressClearCycle, now : integer)
	if c.finished then return end
	c.finished = true
	c.workDoneUs = c.workDoneUs or now
	local line = logic.clearLine(c.name, c.scanned, #c.drivers, c.sent, c.ok, c.answered, (now - c.startedUs) / 1000, c.note)
	if not c.keep then
		rt.log(line)
		return
	end
	rt.detail(line)
	summary.cycles = summary.cycles + 1
	summary.drivers = summary.drivers + #c.drivers
	summary.sent = summary.sent + c.sent
	summary.ok = summary.ok + c.ok
	if lastSummaryUs == nil or now - lastSummaryUs >= logic.CLEAR_SUMMARY_US then
		rt.log(string.format("[SQST] keep_traffic_cleared cycles=%d skipped=%d drivers=%d sent=%d ok=%d (last: %s)",
			summary.cycles, summary.skipped, summary.drivers, summary.sent, summary.ok,
			string.format("scanned=%d drivers=%d ms=%.0f", c.scanned, #c.drivers, (now - c.startedUs) / 1000)))
		lastSummaryUs = now
		resetSummary()
	end
end

local function inQueue(job : SquareStressJob) : boolean
	for _, j in ipairs(rt.queue.jobs) do
		if j == job then return true end
	end
	return false
end

--- One frame of a cycle: snapshot, then one scan chunk or one send chunk.
local function clearStep(c : SquareStressClearCycle, job : SquareStressJob)
	local CT = api.type.ComponentType
	if c.list == nil then
		local ok, list = pcall(api.engine.getEntitiesWithComponent, CT.SIM_PERSON)
		if not ok or list == nil then
			c.list = {}
			c.note = "error: SIM_PERSON not listable: " .. tostring(list)
		else
			c.list = list as {integer}
		end
	end
	if c.cursor <= #c.list then
		local last = logic.chunkLast(c.cursor, #c.list, logic.CLEAR_SCAN_PER_FRAME)
		for k = c.cursor, last do
			local e = c.list[k]
			if isDriver(e) then c.drivers[#c.drivers + 1] = e end
		end
		c.scanned = c.scanned + (last - c.cursor + 1)
		c.cursor = last + 1
		if c.cursor > #c.list then traffic.driving = #c.drivers end
	elseif c.sendCursor <= #c.drivers then
		local last = logic.chunkLast(c.sendCursor, #c.drivers, logic.CLEAR_SEND_PER_FRAME)
		local dbg = api.cmd.debug
		for k = c.sendCursor, last do
			local e = c.drivers[k]
			c.sent = c.sent + 1
			api.cmd.sendCommand(dbg.makeSimPersonSetStateCmd(e, logic.CLEAR_STATE_JUMP_HOME) as Command<ICommandData>,
				function(_d : ICommandData, success : boolean)
					c.answered = c.answered + 1
					if success then c.ok = c.ok + 1 end
				end)
		end
		c.sendCursor = last + 1
	end
	local left = logic.clearStepsLeft(#c.list - c.cursor + 1, #c.drivers - c.sendCursor + 1,
		logic.CLEAR_SCAN_PER_FRAME, logic.CLEAR_SEND_PER_FRAME)
	job.total = job.done + left
	if left == 0 then
		c.workDoneUs = rt.nowUs()
		if c.answered >= c.sent then finishCycle(c, c.workDoneUs) end
	end
end

local function startCycle(keep : boolean) : boolean
	if busy() then return false end
	local c : SquareStressClearCycle = {
		name = keep and "keep_traffic_cleared" or "clear_traffic", keep = keep,
		cursor = 1, drivers = {}, sendCursor = 1, scanned = 0, sent = 0, answered = 0, ok = 0,
		startedUs = rt.nowUs(), finished = false,
	}
	traffic.cycle = c
	c.job = rt.enqueue(c.name, 1, function(_i : integer, job : SquareStressJob)
		local ok, err : boolean, any = pcall(clearStep, c, job)
		if not ok then
			c.note = "error: " .. tostring(err)
			logic.stop(job)
			c.workDoneUs = rt.nowUs()
			if c.answered >= c.sent then finishCycle(c, c.workDoneUs) end
		end
	end, { quiet = true, label = "Clearing traffic", maxPerTick = 1 })
	return true
end

function traffic.clearTraffic()
	local dbg = api.cmd.debug
	if dbg == nil or dbg.makeSimPersonSetStateCmd == nil then
		rt.log("[SQST] clear_traffic: api.cmd.debug.makeSimPersonSetStateCmd is not available")
		return
	end
	if not startCycle(false) then
		rt.log("[SQST] clear_traffic: a clear is still running; try again in a moment")
	end
end

function traffic.setKeepCleared(on : boolean)
	if on == traffic.ui.keepCleared then return end
	traffic.ui.keepCleared = on
	if on then
		nextCycleUs = 0
		clearsSeen = rt.queueClears
		lastSummaryUs = nil
		resetSummary()
		rt.log(string.format("[SQST] keep_traffic_cleared on (every %d s)", logic.CLEAR_INTERVALS[traffic.ui.clearInterval] or 5))
	else
		local c = traffic.cycle
		if c ~= nil and c.keep and c.workDoneUs == nil then
			-- stop the running cycle: nothing more is sent
			logic.stop(c.job)
			c.note = "stopped (unchecked)"
			c.workDoneUs = rt.nowUs()
		end
		rt.log("[SQST] keep_traffic_cleared off")
	end
	rt.version = rt.version + 1
end

function traffic.setClearInterval(index : integer)
	if logic.CLEAR_INTERVALS[index] == nil then return end
	traffic.ui.clearInterval = index
end

function traffic.tickClear(now : integer)
	local c = traffic.cycle
	if c ~= nil and not c.finished then
		if c.workDoneUs == nil and not inQueue(c.job) then
			-- the queue was cleared mid-cycle
			c.note = "stopped (queue cleared)"
			finishCycle(c, now)
		elseif c.workDoneUs ~= nil and (c.answered >= c.sent or now - c.workDoneUs >= logic.CLEAR_CALLBACK_TIMEOUT_US) then
			finishCycle(c, now)
		end
	end
	if not traffic.ui.keepCleared then return end
	if rt.queueClears ~= clearsSeen then
		traffic.ui.keepCleared = false
		rt.log("[SQST] keep_traffic_cleared off (queue cleared)")
		rt.version = rt.version + 1
		return
	end
	if now < nextCycleUs then return end
	nextCycleUs = now + intervalUs()
	if busy() then
		summary.skipped = summary.skipped + 1
		rt.detail("[SQST] keep_traffic_cleared: previous cycle still running; cycle skipped")
		return
	end
	startCycle(true)
end

rt.addTickHook(function(now : integer) traffic.tickClear(now) end)

return traffic
