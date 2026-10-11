-- DEV probe for square_line_rate_matcher (plans/square_line_rate_matcher/PLAN.md phase 0; steps: PROBE.md).
-- Never upload. Every line it logs starts with "[RMPROBE]" (print, so it lands in stdout.txt).
--
-- Mount: same technique as square_line_revert (line_revert.script.lua:442-465, proven in game):
-- * line_util.makeLineActionDescriptor is wrapped to capture the manager's commonParams; the line shown in the
--   details panel is commonParams.lineState:old().entityAndRevision.entity (manager_window.tl:458-459).
-- * button_react_util.makeIconToggleButton is wrapped; when it builds the Auto-Rename "A+" icon
--   (symbol_autorename.tga) inside the LinePanelActionButtons recipe, our button row is put to its left.
-- doReplace reads the current module functions, so Line Revert's wrappers (order 200, ours 250) stay in the chain.
--
-- Buttons (left of A+): "RM" toggles the row open/closed; "Rep" report, "+1" clone, "-1" sell newest,
-- "Smp" start the Rate sampler only. Every action also starts the sampler (2 min, see SAMPLE_*).
-- The sampler runs in the row's useStepState getter (react.onStep, Main Thread per docs/findings.md
-- "Timers and threads in GUI contexts"), timed with api.type.Clock. So it only runs while the row is mounted:
-- keep the Line Manager open on that line.
--
-- API sources (.cache/game):
--   getLineVehicles               api/tealdef/api/engine/system.d.tl:372
--   calcLineStationThroughput     api/tealdef/api/engine/util.d.tl:202 (the Rate, per year)
--   TRANSPORT_VEHICLE fields      api/tealdef/api/engine.d.tl:1380-1530; TransportVehicleState type.d.tl:444-453
--   capacity/utilization          statistics_react_util.calculateCargoColumnDataForLine (demand / coverage),
--   frequency                     line_util.calculateFrequencySeconds, as stli_core.lua
--   supply walk                   square_industry_production_label production_label_pickup.tl engineAdapter
--   produced / max per year       api.engine.util.stock.getCargoProducedPerYear / getCargoMaxProductionPerYear,
--                                 getInputsOutputsFromRules (util.d.tl:70-84; cargo_react_util.tl:653-680)
--   clone                         manager_window.tl:8494-8570 duplicateVehicles + vehicle_react_util.tl:318-405
--   depot                         api.engine.util.vehicle.findBestLineAndDepotForVehicle (util.d.tl:428),
--                                 fallback line_util.getBestDepotForLine (line_util.tl:1752)
--   commands                      api/tealdef/api/cmd.d.tl:892 buy, :915 send to depot, :922 set line

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local button_react_util = ug_require "::/gui/main/button_react_util.tl"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"

local AUTO_RENAME_ICON = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"
local RECIPE_ACTION_BUTTONS = "LinePanelActionButtons"
local SAMPLE_CHECK_US = 1000000 -- read Rate every 1 s; log when it changed
local SAMPLE_LOG_US = 5000000 -- and at least every 5 s
local SAMPLE_TOTAL_US = 120000000 -- for 2 min after an action

-- Logging --------------------------------------------------------------------------------------------------------
local function say(...)
	local parts = { "[RMPROBE]" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	print(table.concat(parts, " "))
end

local function optional(path)
	local ok, mod = pcall(ug_require, path)
	if ok and type(mod) == "table" then return mod end
	say("require failed", path, mod)
	return nil
end
local statistics_react_util = optional("::/gui/statistics/statistics_react_util.tl")
local industry_util = optional("::/gui/main/industry_util.tl")

--- pcall that logs the error and returns nil on failure.
local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	say("ERROR", label, a)
	return nil
end

-- Clock (safe on every thread, docs/findings.md) ---------------------------------------------------------------------
local clock
local function nowUs()
	if not clock then clock = api.type.Clock.new() end
	return clock:getTime()
end

-- State ------------------------------------------------------------------------------------------------------------
local managerParams -- latest commonParams seen by makeLineActionDescriptor
local status = "idle" -- short text shown in the row and the RM tooltip
local sampler -- { line, label, t0, nextCheck, nextLog, untilUs, lastRate, lastN, lastStates }

local function setStatus(text)
	status = tostring(text)
	say("status", status)
end

local function lineOf(params)
	local ls = params and params.lineState and params.lineState:old()
	local e = ls and ls.entityAndRevision and ls.entityAndRevision.entity or nil
	if e and e >= 0 then return e end
	-- fallback: the single selected line in the list
	local st = params and params.lineManagerStateRef and params.lineManagerStateRef:get()
	local sel = st and st.lineListEntitiesSelected
	if sel and #sel == 1 then
		local s = sel[1]
		if type(s) == "number" then return s end
		if type(s) == "table" or type(s) == "userdata" then return s.entity end
	end
	return nil
end

local function isLine(e)
	return type(e) == "number" and e >= 0 and api.engine.entityExists(e)
		and api.engine.getComponent(e, api.type.ComponentType.LINE) ~= nil
end

local function nameOf(e)
	local ok, n = pcall(function()
		local c = api.engine.getComponent(e, api.type.ComponentType.NAME)
		return c and c.name
	end)
	return ok and n or nil
end

local function cargoName(id)
	local ok, n = pcall(function() return api.res.cargoTypeRep.get(id).name end)
	return (ok and n) and (n .. "#" .. tostring(id)) or ("cargo#" .. tostring(id))
end

local function gameTime()
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	return gt and gt.gameTime or -1
end

local function protectedSet()
	local ok, p = pcall(function()
		local f = managerParams and managerParams.gameCtx and managerParams.gameCtx.filters and managerParams.gameCtx.filters:get()
		return f and f.protectedEntities
	end)
	return ok and p or nil
end

local STATE_NAMES
local function stateName(s)
	if not STATE_NAMES then
		STATE_NAMES = {}
		local e = api.type["enum"].TransportVehicleState
		for _i, k in ipairs({ "IN_DEPOT", "EN_ROUTE", "AT_TERMINAL", "GOING_TO_DEPOT" }) do
			local ok, v = pcall(function() return e[k] end)
			if ok and v ~= nil then STATE_NAMES[v] = k end
		end
	end
	return STATE_NAMES[s] or ("state" .. tostring(s))
end

local function tvOf(v)
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
end

local function lineVehicles(line)
	return api.engine.system.transportVehicleSystem.getLineVehicles(line) or {}
end

--- "EN_ROUTE:2 IN_DEPOT:1" for the line's vehicles.
local function stateCounts(vehicles)
	local counts, keys = {}, {}
	for _i, v in ipairs(vehicles) do
		local ok, name = pcall(function()
			local tv = tvOf(v)
			local n = stateName(tv.state)
			if tv.sellOnArrival then n = n .. "(sell)" end
			return n
		end)
		local k = ok and name or "?"
		if not counts[k] then
			counts[k] = 0
			keys[#keys + 1] = k
		end
		counts[k] = counts[k] + 1
	end
	table.sort(keys)
	local out = {}
	for _i, k in ipairs(keys) do out[#out + 1] = k .. ":" .. counts[k] end
	return table.concat(out, " ")
end

local function rateOf(line)
	return try("rate", function() return api.engine.util.line.calcLineStationThroughput(line) end)
end

-- Sampler ------------------------------------------------------------------------------------------------------------
local function startSampler(line, label)
	local t = nowUs()
	sampler = {
		line = line, label = label, t0 = t, nextCheck = t, nextLog = t, untilUs = t + SAMPLE_TOTAL_US,
	}
	say("sampler start", label, "line", line, "for", SAMPLE_TOTAL_US / 1000000, "s")
end

local function samplerTick()
	local s = sampler
	if not s then return end
	local t = nowUs()
	if t < s.nextCheck then return end
	s.nextCheck = t + SAMPLE_CHECK_US
	if t > s.untilUs or not isLine(s.line) then
		say("sampler end", s.label, "line", s.line)
		sampler = nil
		return
	end
	local vehicles = lineVehicles(s.line)
	local rate = rateOf(s.line)
	local states = stateCounts(vehicles)
	local changed = rate ~= s.lastRate or #vehicles ~= s.lastN or states ~= s.lastStates
	if changed or t >= s.nextLog then
		s.nextLog = t + SAMPLE_LOG_US
		say(string.format("sample %s t=+%.1fs gameTime=%s line=%s rate=%s n=%d states=[%s]%s",
			s.label, (t - s.t0) / 1000000, tostring(gameTime()), tostring(s.line), tostring(rate), #vehicles, states,
			changed and " CHANGED" or ""))
		s.lastRate, s.lastN, s.lastStates = rate, #vehicles, states
		status = string.format("%s +%ds R%s n%d", s.label, math.floor((t - s.t0) / 1000000), tostring(rate), #vehicles)
	end
end

-- Report -------------------------------------------------------------------------------------------------------------
local function reportVehicle(i, v, prot)
	local tv = tvOf(v)
	if not tv then
		say("  vehicle", i, v, "no TRANSPORT_VEHICLE")
		return
	end
	local models, caps = {}, {}
	for _j, part in ipairs(tv.transportVehicleConfig.vehicles) do
		models[#models + 1] = tostring(part.part.modelId)
	end
	local okCap = pcall(function()
		for k, c in ipairs(tv.config.capacities) do
			if c and c > 0 then caps[#caps + 1] = cargoName(k - 1) .. "=" .. tostring(c) end
		end
	end)
	local first = tv.transportVehicleConfig.vehicles[1]
	say(string.format("  vehicle %d entity=%s name=%s state=%s line=%s stopIndex=%s depot=%s sellOnArrival=%s userStopped=%s "
		.. "purchaseTime=%s models=[%s] capacities(index-1=cargo)=[%s]%s protected=%s",
		i, tostring(v), tostring(nameOf(v)), stateName(tv.state), tostring(tv.line), tostring(tv.stopIndex),
		tostring(tv.depot), tostring(tv.sellOnArrival), tostring(tv.userStopped),
		tostring(first and first.purchaseTime), table.concat(models, ","), table.concat(caps, " "),
		okCap and "" or " (capacities unreadable)", tostring(prot ~= nil and prot[v] ~= nil)))
end

--- Station entities reachable from a station group: catchables, or the station construction's industries
--- (production_label_pickup.tl engineAdapter reachableStockLists).
local function reachable(stationGroup)
	local CT = api.type.ComponentType
	local sg = api.engine.getComponent(stationGroup, CT.STATION_GROUP)
	local out, seen = {}, {}
	local function add(e)
		if e ~= nil and e >= 0 and not seen[e] then
			seen[e] = true
			out[#out + 1] = e
		end
	end
	if not sg or not sg.stations then return out end
	for _i, station in ipairs(sg.stations) do
		local catchables = station >= 0 and api.engine.system.catchmentAreaSystem.getStationCatchables(station, true) or nil
		if catchables ~= nil and #catchables > 0 then
			for _j, e in ipairs(catchables) do add(e) end
		elseif station >= 0 then
			local con = api.engine.system.streetConnectorSystem.getConstructionEntityForStation(station)
			local conComp = (con ~= nil and con >= 0) and api.engine.getComponent(con, CT.CONSTRUCTION) or nil
			if conComp ~= nil and conComp.industries ~= nil then
				say("    station", station, "no cargo catchables; construction", con, "industries", #conComp.industries)
				for _j, industry in ipairs(conComp.industries) do
					add(industry)
					local ind = api.engine.getComponent(industry, CT.INDUSTRY)
					if ind ~= nil then add(ind.stockList) end
				end
			end
		end
	end
	return out
end

local function reportProducer(e, loaded)
	local CT = api.type.ComponentType
	local hasStock = api.engine.getComponent(e, CT.STOCK_LIST) ~= nil
	local ind = api.engine.getComponent(e, CT.INDUSTRY)
	if not hasStock and not ind then return end
	local stockList = hasStock and e or (ind and ind.stockList)
	local outputs = try("outputs " .. tostring(e), function()
		return api.engine.util.stock.getInputsOutputsFromRules(stockList)[2]
	end) or {}
	if #outputs == 0 then return end
	local stock = api.engine.getComponent(stockList, CT.STOCK_LIST)
	for idx, c in ipairs(outputs) do
		local produced = try("produced", function() return api.engine.util.stock.getCargoProducedPerYear(stockList, c) end)
		local max = try("max", function() return api.engine.util.stock.getCargoMaxProductionPerYear(stockList, c) end)
		local freq = nil
		pcall(function()
			for k, d in pairs(stock.cargoData) do
				if k == c then freq = d.produceFrequency end
			end
		end)
		local prodData = nil
		if industry_util and ind then
			prodData = try("getIndustryProductionData", function()
				local d = industry_util.getIndustryProductionData(e, false, false, idx, true)
				return d and string.format("{cargo=%s actual=%s total=%s}", tostring(d.cargoTypeId), tostring(d.actual), tostring(d.total)) or "nil"
			end)
		end
		say(string.format("    producer entity=%s name=%s industry=%s stockList=%s out=%s loadedHere=%s producedPerYear=%s "
			.. "maxPerYear=%s cargoData.produceFrequency=%s industryUtil(idx %d)=%s",
			tostring(e), tostring(nameOf(e)), tostring(ind ~= nil), tostring(stockList), cargoName(c),
			tostring(loaded[c] == true), tostring(produced), tostring(max), tostring(freq), idx, tostring(prodData)))
	end
end

local function report(line)
	local CT = api.type.ComponentType
	local comp = api.engine.getComponent(line, CT.LINE)
	say("==== report line", line, "name", nameOf(line), "gameTime", gameTime(),
		"date", (try("formatGameTime", function() return api.util.formatGameTime(gameTime()) end)))
	local vehicles = lineVehicles(line)
	local column = statistics_react_util and try("cargoColumn", function()
		return statistics_react_util.calculateCargoColumnDataForLine(line)
	end)
	say(string.format("  rate=%s vehicles=%d capacity=%s utilization=%s frequencySec=%s states=[%s]",
		tostring(rateOf(line)), #vehicles, tostring(column and column.demand), tostring(column and column.coverage),
		tostring(try("frequency", function() return line_util.calculateFrequencySeconds(line) end)), stateCounts(vehicles)))
	local prot = protectedSet()
	for i, v in ipairs(vehicles) do try("vehicle " .. tostring(v), reportVehicle, i, v, prot) end
	-- supply side
	local passenger = try("passenger", function() return api.res.cargoTypeRep.getPassengerCargoTypeId() end)
	local map = try("lineStopsMap", function() return api.engine.system.lineSystem.getStationGroup2LineStopsMap() end) or {}
	local seenGroups = {}
	for si, s in ipairs(comp and comp.stops or {}) do
		local loaded, loadedNames = {}, {}
		pcall(function()
			for k, v in ipairs(s.stopConfig.load) do
				if v == true then
					loaded[k - 1] = true
					loadedNames[#loadedNames + 1] = cargoName(k - 1)
				end
			end
		end)
		say(string.format("  stop %d group=%s station=%s terminal=%s loadMode=%s loads=[%s]", si, tostring(s.stationGroup),
			tostring(s.station), tostring(s.terminal), tostring(s.loadMode), table.concat(loadedNames, ",")))
		if not seenGroups[s.stationGroup] then
			seenGroups[s.stationGroup] = true
			-- other lines at this group, with their Rate (the "rate of other lines" the target subtracts)
			local others = {}
			for _i, ls in ipairs(map[s.stationGroup] or {}) do
				local other = ls[1]
				if other ~= line then others[#others + 1] = tostring(other) .. "(rate " .. tostring(rateOf(other)) .. ")" end
			end
			say("    other line stops at group:", #others > 0 and table.concat(others, " ") or "none")
			local ents = try("reachable", reachable, s.stationGroup) or {}
			say("    reachable entities", #ents, "passengerCargo", passenger)
			for _i, e in ipairs(ents) do try("producer " .. tostring(e), reportProducer, e, loaded) end
		end
	end
	say("==== end report line", line)
end

-- Clone +1 -----------------------------------------------------------------------------------------------------------
local function cloneOne(line)
	local vehicles = lineVehicles(line)
	local src = vehicles[1]
	if not src then
		setStatus("clone: no vehicle on line")
		return
	end
	local tv = tvOf(src)
	-- duplicateVehicles (manager_window.tl:8494-8506)
	local newConfig = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
	local newVehicles = {}
	for _i, part in ipairs(newConfig.vehicles) do
		newVehicles[#newVehicles + 1] = part
		part.purchaseTime = 0
		part.maintenanceState = 1
	end
	newConfig.vehicles = newVehicles
	-- HandleVehicleChanges (vehicle_react_util.tl:332-342): purchaseTime <= 0 -> now, autoLoadConfig all true
	local gt = gameTime()
	local fixed = {}
	for _i, part in ipairs(newConfig.vehicles) do
		if part.purchaseTime <= 0 then part.purchaseTime = gt end
		local auto = {}
		for k = 1, #part.part.compartment2loadConfig do auto[k] = true end
		part.autoLoadConfig = auto
		fixed[#fixed + 1] = part
	end
	newConfig.vehicles = fixed
	-- mission hook like vanilla (manager_window.tl:8507-8519); a returned string = refused by a mission
	local modelId2quantity = {}
	for _i, part in ipairs(newConfig.vehicles) do
		modelId2quantity[part.part.modelId] = (modelId2quantity[part.part.modelId] or 0) + 1
	end
	local missionError = try("mission.buyVehicle", function()
		return api.gui.fireGuiScriptEvent("vehicleStore", "mission.buyVehicle", { modelId2quantity = modelId2quantity, actuallyBuy = true })
	end)
	if missionError then
		setStatus("clone: mission refused: " .. tostring(missionError))
		return
	end
	try("mission.cloneVehicle", function()
		api.gui.fireGuiScriptEvent("vehicleStore", "mission.cloneVehicle", { entity = src })
	end)
	-- depot: what vanilla uses (findBestLineAndDepotForVehicle on the source vehicle, manager_window.tl:8546-8548)
	local best = try("findBestLineAndDepotForVehicle", function()
		return api.engine.util.vehicle.findBestLineAndDepotForVehicle(src)
	end)
	local bestLine, bestDepot = best and best[1], best and best[2]
	say("clone: source", src, "findBestLineAndDepotForVehicle -> line", bestLine, "depot", bestDepot,
		"| selected line", line, bestLine == line and "(same)" or "(DIFFERENT)")
	local depot, depotFrom = bestDepot, "findBest"
	if not depot or depot < 0 then
		depot = try("getBestDepotForLine", function() return line_util.getBestDepotForLine(line) end)
		depotFrom = "line_util.getBestDepotForLine"
	end
	if not depot or depot < 0 then
		for _i, v in ipairs(vehicles) do
			local t = tvOf(v)
			if t and t.depot and t.depot >= 0 then
				depot, depotFrom = t.depot, "line vehicle in depot"
				break
			end
		end
	end
	say("clone: using depot", depot, "from", depotFrom)
	if not depot or depot < 0 then
		setStatus("clone: no depot found")
		return
	end
	local tSend = nowUs()
	local player = api.engine.util.getPlayer()
	api.cmd.sendCommand(api.cmd.makeVehicleBuyCmd(player, depot, newConfig), function(cmd, success)
		local ok, err = pcall(function()
			local newVehicle = cmd and cmd.resultVehicleEntity
			say(string.format("clone: buy callback success=%s newVehicle=%s after %.2fs", tostring(success), tostring(newVehicle),
				(nowUs() - tSend) / 1000000))
			if not success or not newVehicle or newVehicle < 0 then
				setStatus("clone: buy failed")
				return
			end
			api.cmd.sendCommand(api.cmd.makeVehicleSetLineCmd(newVehicle, line, 0), function(_c, success2)
				local ok2, err2 = pcall(function()
					local t = tvOf(newVehicle)
					say(string.format("clone: setLine callback success=%s vehicle=%s vehicle.line=%s (selected %s) state=%s depot=%s after %.2fs",
						tostring(success2), tostring(newVehicle), tostring(t and t.line), tostring(line),
						t and stateName(t.state) or "?", tostring(t and t.depot), (nowUs() - tSend) / 1000000))
					setStatus(success2 and ("clone ok " .. tostring(newVehicle)) or "clone: setLine failed")
				end)
				if not ok2 then say("ERROR setLine callback", err2) end
			end)
		end)
		if not ok then say("ERROR buy callback", err) end
	end)
	setStatus("clone sent")
end

-- Sell newest -1 -----------------------------------------------------------------------------------------------------
local function sellNewest(line)
	local prot = protectedSet()
	local best, bestTime = nil, nil
	for _i, v in ipairs(lineVehicles(line)) do
		local tv = tvOf(v)
		local first = tv and tv.transportVehicleConfig.vehicles[1]
		local pt = first and first.purchaseTime or -1
		local skip = (prot ~= nil and prot[v] ~= nil) or (tv and tv.sellOnArrival)
		if tv and not skip and (bestTime == nil or pt > bestTime or (pt == bestTime and v > best)) then
			best, bestTime = v, pt
		end
	end
	if not best then
		setStatus("sell: no candidate")
		return
	end
	say("sell: vehicle", best, "purchaseTime", bestTime, "state", stateName(tvOf(best).state))
	local tSend = nowUs()
	api.cmd.sendCommand(api.cmd.makeVehicleSendToDepotCmd(best, true), function(_c, success)
		local ok, err = pcall(function()
			local t = api.engine.entityExists(best) and tvOf(best) or nil
			say(string.format("sell: sendToDepot callback success=%s vehicle=%s state=%s sellOnArrival=%s line=%s after %.2fs",
				tostring(success), tostring(best), t and stateName(t.state) or "gone", tostring(t and t.sellOnArrival),
				tostring(t and t.line), (nowUs() - tSend) / 1000000))
			setStatus(success and ("sell sent " .. tostring(best)) or "sell failed")
		end)
		if not ok then say("ERROR sell callback", err) end
	end)
	setStatus("sell sent")
end

-- Button row ---------------------------------------------------------------------------------------------------------
local function act(label, fn)
	local line = lineOf(managerParams)
	if not isLine(line) then
		setStatus(label .. ": no line selected")
		return
	end
	say("CLICK", label, "line", line, "name", nameOf(line), "rate", rateOf(line), "n", #lineVehicles(line))
	if fn then try(label, fn, line) end
	startSampler(line, label)
end

local function textButton(text, tooltip, onClick)
	-- same shape as the LRPROBE "R" button, proven in this toolbar (square_line_revert_probe lrprobe.script.lua:129-140)
	return builtin.Button{
		meta = { class = "vehicle-button, secondary", tooltip = tooltip },
		content = builtin.TextView{ text = text },
		onClick = function()
			local ok, err = pcall(onClick)
			if not ok then say("ERROR click", text, err) end
		end,
	}
end

local function stepView()
	local ok, err = pcall(samplerTick)
	if not ok then
		say("ERROR sampler", err)
		sampler = nil
	end
	return status
end

local RmProbeRow = react.RegisterRecipe("SquareRmProbeRow", function(_p)
	local open = react.useState(false)
	local view = engine_react_util.useStepState(function()
		return stepView()
	end, nil, function(a, b) return a == b end)
	local text = view:old() or status
	local children = {
		textButton(open:old() and "RM<" or "RM", "Rate Matcher probe: " .. text .. " (click to show/hide actions)", function()
			open:set(not open:old())
		end),
	}
	if open:old() then
		children[#children + 1] = textButton("Rep", "Report: Rate, vehicles, supply to the log", function() act("report", report) end)
		children[#children + 1] = textButton("+1", "Clone the first line vehicle onto this line (buys a vehicle!)", function() act("clone", cloneOne) end)
		children[#children + 1] = textButton("-1", "Send the newest line vehicle to the depot and sell it", function() act("sell", sellNewest) end)
		children[#children + 1] = textButton("Smp", "Log Rate every 5 s for 2 min", function() act("sample", nil) end)
		children[#children + 1] = builtin.TextView{ text = text }
	end
	-- a recipe returns a layout (memory: react-recipe-must-return-layout)
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end)

-- Wrappers -----------------------------------------------------------------------------------------------------------
local origDescriptor
local function lineActionDescriptor(commonParams, ...)
	local ok, err = pcall(function()
		if type(commonParams) == "table" and commonParams.lineManagerStateRef then
			if managerParams ~= commonParams then say("captured commonParams") end
			managerParams = commonParams
		end
	end)
	if not ok then say("ERROR descriptor", err) end
	return origDescriptor(commonParams, ...)
end

local origToggle
local loggedMount = false
local function iconToggleButton(className, path, ...)
	local node = origToggle(className, path, ...)
	if path ~= AUTO_RENAME_ICON then return node end
	local ok, wrapped = pcall(function()
		if react.getCurrentRecipeName() ~= RECIPE_ACTION_BUTTONS or not managerParams then return nil end
		if not loggedMount then
			loggedMount = true
			say("mounted row left of A+ in", RECIPE_ACTION_BUTTONS)
		end
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = { RmProbeRow{}, node }, -- the recipe is the item itself, never a Component layout
		}
	end)
	if not ok then
		say("ERROR mount", wrapped)
		return node
	end
	return wrapped or node
end

local function doReplace(_replacementApi)
	if origToggle or origDescriptor then return end
	-- read the current functions now, so wrappers installed earlier (Line Revert, order 200) stay in the chain
	local toggle, descriptor = button_react_util.makeIconToggleButton, line_util.makeLineActionDescriptor
	if type(toggle) ~= "function" or type(descriptor) ~= "function" then
		say("install FAILED", type(toggle), type(descriptor))
		return
	end
	origToggle, origDescriptor = toggle, descriptor
	button_react_util.makeIconToggleButton = iconToggleButton
	line_util.makeLineActionDescriptor = lineActionDescriptor
	say("installed (order 250)")
end

say("loaded")

-- .script.lua resources export through data() (memory: script-lua-exports-via-data)
function data()
	return {
		doReplace = doReplace,
		RmProbeRow = RmProbeRow,
	}
end
