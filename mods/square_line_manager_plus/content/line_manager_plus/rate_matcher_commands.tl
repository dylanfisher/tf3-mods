-- Line Rate Matcher: the commands Apply sends (plans/square_line_manager_plus/RATE_MATCHER.md phases 2-3). Only the vanilla
-- commands a player sends by hand: buy + set line (clone), sell (the vanilla Sell button), and the game's own
-- Replace Vehicles window. GUI thread only (a button click): it fires gui script / react events.
--
-- Ported from the in-game probe (mods/square_line_rate_matcher_probe/content/rmprobe/rmprobe.script.lua cloneOne /
-- sellNewest, docs/findings.md "Line Rate, cloning onto a line, sell on arrival"):
--   * clone = vanilla duplicateVehicles (manager_window.tl:8494-8570) + HandleVehicleChanges
--     (vehicle_react_util.tl:318-405), but the clone goes onto OUR line: copy TRANSPORT_VEHICLE.transportVehicleConfig,
--     purchaseTime = now, maintenanceState = 1, autoLoadConfig all true; fire "mission.buyVehicle" (a returned string =
--     refused by a mission) and "mission.cloneVehicle"; makeVehicleBuyCmd(player, depot, config) -> callback
--     cmd.resultVehicleEntity -> makeVehicleSetLineCmd(new, line, 0). Verified: the clone is EN_ROUTE on the line.
--   * a failed buy is "not enough money" as vanilla reads it (vehicle_react_util.tl:362-366). Before sending, the
--     clones are capped by the player's ACCOUNT balance (read as square_bulk_bulldozer does, verified there) over
--     api.engine.util.vehicle.getPartPrice of the parts (the store's price, vehicle_store_window.tl:3765).
--   * sell = makeVehicleSellCmd({ v }), the vanilla Sell button (entity_window/vehicle/vehicle.tl:361,
--     manager_window.tl:2244): sold at once. Not makeVehicleSendToDepotCmd(v, true) (sell on arrival), which no base
--     GUI sends: the sim crashed when ships sold that way reached the depot (docs/findings/lines-vehicles.md "Sell on
--     arrival crash", session 2026-10-13_2140_sqrl-sqsg-crash).
--   * replace window = react.fireEvent(nil, "replaceVehicles", ...) exactly as radar_fleet.tl replaceVehicles (verified).
--   * model switch (switchModel) = what the Replace window's accept does (vehicle_store_window.tl:4038-4075 single-part
--     "buy immediately" path + vehicle_react_util.HandleVehicleChanges :318-405): a fresh single-part config
--     (vehicle_util.makePart, vehicleGroups {1}, no MU), mission.buyVehicle once for the whole plan, then per old
--     vehicle makeVehicleReplaceCmd(entity, config) (the vehicle keeps its entity and line), extra ones bought at the
--     line's depot and set on the line, surplus old ones sold. Money as the store's
--     hasEnoughMoney (:2992-3003): net = price x new vehicles - resale (getDepreciatedValue) of the replaced ones.
--   * prices = the store's: metadata cost.price per part (buy mode totalPrice, vehicle_store_window.tl:3765-3771,
--     4038-4040). getPartPrice ("vehicle part value", util.d.tl:469-472) is only the fallback: for a part already
--     bought it may be a depreciated value (the store uses it only in Modify mode for existing parts).
--   * price check (2026-10-10, second GUI test: Buy showed $548,640 for one Sydfart, the phase-3 build $70,484): base
--     vehicles have cost.price = -1, filled at load by model_metadata_util.addCostMetadata as 6 x the auto running
--     cost (base/content/base/model_metadata_util.lua:548-549; 548,640 = 6 x 91,440, the Sydfart's running cost);
--     the difficulty's vehiclePurchaseCostScale is applied to it in postRunFn (base/post_run_util.tl
--     applyModelTypeScale). The store shows exactly that number (vehicle_store_util.tl:309, vehicle_store_window.tl:117)
--     and no inflation factor applies to vehicles (finances_util.scaleWithInflation is used by subventions only).
--     $70,484 was getPartPrice of the template's OWN part, i.e. its depreciated value. What the buy command
--     really charges is logged: priceReport on open, "[LineManagerPlus] rate matcher: clone charged" (balance before - after) after.

local commands : SquareRateMatcherCommands = {}

commands.MAX_CLONES = 100

local function optional(path : string) : any
	local ok, m = pcall(ug_require, path)
	if ok and type(m) == "table" then return m end
	return nil
end

local function warn(msg : string)
	log.warning("[LineManagerPlus] rate matcher: " .. msg)
end

-- Every vehicle id is re-checked with tvOf right before a native call or command that takes it: a stale id (sold,
-- replaced, entity 0 = the world) there is a fatal engine assert ("it != components.end()"), which pcall can't catch
-- (the base store hit it in findBestLineAndDepotForVehicle on entity 0, session 2026-10-05_0518_session-crash).
local function tvOf(v : integer) : Engine.Component.TransportVehicle
	if type(v) ~= "number" or v <= 0 or not api.engine.entityExists(v) then return nil end
	return api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE) as Engine.Component.TransportVehicle
end

local function lineAlive(line : integer) : boolean
	local ok, yes = pcall(function() : boolean
		return type(line) == "number" and line > 0 and api.engine.entityExists(line)
			and api.engine.getComponent(line, api.type.ComponentType.LINE) ~= nil
	end)
	return ok and yes == true
end

local function newResult(requested : integer) : SquareRateMatcherCommandResult
	return { status = "ok", requested = requested, done = {}, unassigned = {}, reasons = {} }
end

local function addReason(r : SquareRateMatcherCommandResult, reason : string, n? : integer)
	r.reasons[reason] = (r.reasons[reason] or 0) + (n or 1)
end

local function finish(r : SquareRateMatcherCommandResult) : SquareRateMatcherCommandResult
	if r.requested == 0 then
		r.status = "invalid"
	elseif #r.done >= r.requested then
		r.status = "ok"
	elseif #r.done > 0 then
		r.status = "partial"
	else
		r.status = "failed"
	end
	return r
end

local function invalid(reason : string, requested : integer, onDone : function(SquareRateMatcherCommandResult)) : SquareRateMatcherCommandResult
	local r = newResult(requested or 0)
	addReason(r, reason)
	r.status = "invalid"
	if onDone ~= nil then onDone(r) end
	return r
end

-- depot ------------------------------------------------------------------------------------

function commands.resolveDepot(template : integer, line : integer) : integer, string
	local okBest, best : boolean, {integer} = false, nil
	if tvOf(template) ~= nil then
		okBest, best = pcall(api.engine.util.vehicle.findBestLineAndDepotForVehicle, template)
	end
	local bestLine = okBest and best ~= nil and best[1] or nil
	local bestDepot = okBest and best ~= nil and best[2] or nil
	if bestDepot ~= nil and bestDepot >= 0 and bestLine == line then return bestDepot, "findBest" end
	local lu = optional("::/gui/line_vehicle_mgmt/line_util.tl") as LineUtil
	if lu ~= nil then
		local ok, d = pcall(lu.getBestDepotForLine, line)
		if ok and d ~= nil and d >= 0 then return d, "line_util.getBestDepotForLine" end
	end
	if bestDepot ~= nil and bestDepot >= 0 then return bestDepot, "findBest_other_line" end
	local okV, vehicles = pcall(api.engine.system.transportVehicleSystem.getLineVehicles, line)
	for __, v in ipairs(okV and vehicles or {}) do
		local tv = tvOf(v)
		if tv ~= nil and tv.depot ~= nil and tv.depot >= 0 then return tv.depot, "line_vehicle_depot" end
	end
	return nil, nil
end

-- clone ------------------------------------------------------------------------------------

local function gameTime() : integer
	local gt = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME) as Engine.Component.GameTime
	return math.floor(gt.gameTime)
end

-- A fresh buyable copy of the template's config (duplicateVehicles + HandleVehicleChanges).
local function cloneConfig(tv : Engine.Component.TransportVehicle) : TransportVehicleConfig
	local cfg = api.type.TransportVehicleConfig.new(tv.transportVehicleConfig)
	local now = gameTime()
	local parts : {TransportVehiclePart} = {}
	for __, part in ipairs(cfg.vehicles) do
		part.purchaseTime = now
		part.maintenanceState = 1
		local auto : {boolean} = {}
		for k = 1, #part.part.compartment2loadConfig do auto[k] = true end
		part.autoLoadConfig = auto
		parts[#parts + 1] = part
	end
	cfg.vehicles = parts
	return cfg
end

local function metadataPrice(modelId : integer) : integer
	local ok, p = pcall(function() : integer
		local m = api.res.modelRep.get(modelId)
		local cost = m ~= nil and m.metadata ~= nil and m.metadata["cost"] as ModelMetadata.Cost or nil
		return cost ~= nil and cost.price or nil
	end)
	if ok and type(p) == "number" and p > 0 then return p end
	return nil
end

function commands.modelPrice(modelId : integer) : integer
	return metadataPrice(modelId)
end

local function priceOf(tv : Engine.Component.TransportVehicle) : integer
	local ok, p = pcall(function() : integer
		local sum = 0
		for __, part in ipairs(tv.transportVehicleConfig.vehicles) do
			local price = metadataPrice(part.part.modelId)
			if price == nil then price = api.engine.util.vehicle.getPartPrice(part) end
			sum = sum + price
		end
		return sum
	end)
	if ok and type(p) == "number" and p > 0 then return p end
	return nil
end

function commands.clonePrice(template : integer) : integer
	local tv = tvOf(template)
	if tv == nil then return nil end
	return priceOf(tv)
end

--- One log line with every price candidate for the template (store price, part values, resale, running costs).
function commands.priceReport(template : integer) : string
	local ok, res = pcall(function() : string
		local tv = tvOf(template)
		if tv == nil then return "template gone" end
		local parts : {string} = {}
		local cfg = cloneConfig(tv)
		for i, part in ipairs(tv.transportVehicleConfig.vehicles) do
			local m = part.part.modelId
			local okOwn, own = pcall(api.engine.util.vehicle.getPartPrice, part)
			local okNew, new = pcall(api.engine.util.vehicle.getPartPrice, cfg.vehicles[i])
			local md = api.res.modelRep.get(m)
			local mt = md ~= nil and md.metadata["maintenance"] as ModelMetadata.Maintenance or nil
			parts[#parts + 1] = "model " .. tostring(m) .. ": store cost.price " .. tostring(metadataPrice(m))
				.. ", getPartPrice(owned part) " .. tostring(okOwn and own or nil)
				.. ", getPartPrice(clone part) " .. tostring(okNew and new or nil)
				.. ", metadata runningCosts " .. tostring(mt ~= nil and mt.runningCosts or nil)
				.. ", lifespan " .. tostring(mt ~= nil and mt.lifespan or nil)
		end
		local okDep, dep = pcall(api.engine.util.vehicle.getDepreciatedValue, template)
		local okRun, run = pcall(api.engine.util.vehicle.getRunningCost, template)
		return table.concat(parts, "; ") .. "; vehicle " .. tostring(template) .. ": getDepreciatedValue "
			.. tostring(okDep and dep or nil) .. ", getRunningCost " .. tostring(okRun and run or nil)
	end)
	if ok then return res end
	return "failed: " .. tostring(res)
end

local function balance() : integer
	local ok, b = pcall(function() : integer
		local acc = api.engine.getComponent(api.engine.util.getPlayer(), api.type.ComponentType.ACCOUNT) as Engine.Component.Account
		return acc ~= nil and acc.balance or nil
	end)
	if ok and type(b) == "number" then return b end
	return nil
end

--- Buys `count` copies of `template` and puts each on `line` (stop 0). onDone(result) runs once every callback
--- has come back (or right away when nothing was sent); the returned result fills in as callbacks arrive.
function commands.cloneOntoLine(template : integer, line : integer, count : integer, onDone? : function(SquareRateMatcherCommandResult)) : SquareRateMatcherCommandResult
	if type(count) ~= "number" or count < 1 then return invalid("invalid_count", 0, onDone) end
	count = math.min(math.floor(count), commands.MAX_CLONES)
	local tv = tvOf(template)
	if tv == nil then return invalid("invalid_template", count, onDone) end
	local okLine, isLine = pcall(function() : boolean
		return api.engine.entityExists(line) and api.engine.getComponent(line, api.type.ComponentType.LINE) ~= nil
	end)
	if not okLine or not isLine then return invalid("invalid_line", count, onDone) end

	local r = newResult(count)
	local depot, depotFrom = commands.resolveDepot(template, line)
	r.depot, r.depotFrom = depot, depotFrom
	if depot == nil then
		addReason(r, "no_depot", count)
		finish(r)
		if onDone ~= nil then onDone(r) end
		return r
	end

	-- Money: send only what the balance covers (unknown price or balance: send all, the buy callback tells).
	local n = count
	local price, bal = priceOf(tv), balance()
	if price ~= nil and bal ~= nil then
		n = math.max(0, math.min(n, math.floor(bal / price)))
		if n < count then addReason(r, "not_enough_money", count - n) end
	end

	local pending = 0
	local sending = true
	local function settle()
		if pending == 0 and not sending then
			finish(r)
			-- what the buy really cost (the balance moves when the command runs; running costs tick too, so
			-- this is approximate): compare with the window's Buy column and the store price
			local after = balance()
			if bal ~= nil and after ~= nil and #r.done + #r.unassigned > 0 then
				log.message("[LineManagerPlus] rate matcher: clone charged: balance " .. tostring(bal) .. " -> " .. tostring(after)
					.. " = " .. tostring(bal - after) .. " for " .. tostring(#r.done + #r.unassigned)
					.. " vehicle(s); store price each " .. tostring(price))
			end
			if onDone ~= nil then
				local ok, err : boolean, any = pcall(onDone, r)
				if not ok then warn("clone onDone failed: " .. tostring(err)) end
			end
		end
	end

	local player = api.engine.util.getPlayer()
	for i = 1, n do
		local okCfg, cfg = pcall(cloneConfig, tv)
		if not okCfg then
			warn("clone config failed: " .. tostring(cfg))
			addReason(r, "invalid_template", n - i + 1)
			break
		end
		local modelId2quantity : {integer : integer} = {}
		for __, part in ipairs(cfg.vehicles) do
			modelId2quantity[part.part.modelId] = (modelId2quantity[part.part.modelId] or 0) + 1
		end
		local okM, missionError = pcall(api.gui.fireGuiScriptEvent, "vehicleStore", "mission.buyVehicle",
			{ modelId2quantity = modelId2quantity, actuallyBuy = true })
		if okM and type(missionError) == "string" then
			r.message = missionError as string
			addReason(r, "mission", n - i + 1)
			break
		end
		pcall(api.gui.fireGuiScriptEvent, "vehicleStore", "mission.cloneVehicle", { entity = template })
		pending = pending + 1
		local okSend, sendErr : boolean, any = pcall(api.cmd.sendCommand, api.cmd.makeVehicleBuyCmd(player, depot, cfg),
			function(cmd : VehicleBuyCommandData, success : boolean)
				local newVehicle = cmd ~= nil and cmd.resultVehicleEntity or nil
				if not success or newVehicle == nil or newVehicle < 0 then
					addReason(r, "not_enough_money")
					pending = pending - 1
					settle()
					return
				end
				if tvOf(newVehicle) == nil or not lineAlive(line) then
					r.unassigned[#r.unassigned + 1] = newVehicle
					addReason(r, "set_line_failed")
					pending = pending - 1
					settle()
					return
				end
				local okSet, setErr : boolean, any = pcall(api.cmd.sendCommand, api.cmd.makeVehicleSetLineCmd(newVehicle, line, 0),
					function(__ : VehicleSetLineCommandData, success2 : boolean)
						if success2 then
							r.done[#r.done + 1] = newVehicle
						else
							r.unassigned[#r.unassigned + 1] = newVehicle
							addReason(r, "set_line_failed")
						end
						pending = pending - 1
						settle()
					end)
				if not okSet then
					warn("set line failed: " .. tostring(setErr))
					r.unassigned[#r.unassigned + 1] = newVehicle
					addReason(r, "set_line_failed")
					pending = pending - 1
					settle()
				end
			end)
		if not okSend then
			warn("buy failed: " .. tostring(sendErr))
			addReason(r, "buy_failed")
			pending = pending - 1
		end
	end
	sending = false
	settle()
	return r
end

-- sell -------------------------------------------------------------------------------------

--- Sells each vehicle at once (the vanilla Sell). Skips vehicles that are gone, protected (missions) or
--- already selling. onDone(result) after the last callback.
function commands.sellVehicles(ids : {integer}, onDone? : function(SquareRateMatcherCommandResult), protected? : {integer : any}) : SquareRateMatcherCommandResult
	local list = ids or {}
	local r = newResult(#list)
	if #list == 0 then
		r.status = "invalid"
		if onDone ~= nil then onDone(r) end
		return r
	end
	local pending = 0
	local sending = true
	local function settle()
		if pending == 0 and not sending then
			finish(r)
			if onDone ~= nil then
				local ok, err : boolean, any = pcall(onDone, r)
				if not ok then warn("sell onDone failed: " .. tostring(err)) end
			end
		end
	end
	for __, v in ipairs(list) do
		local tv = tvOf(v)
		if tv == nil then
			addReason(r, "gone")
		elseif protected ~= nil and protected[v] ~= nil and protected[v] ~= false then
			addReason(r, "protected")
		elseif tv.sellOnArrival then
			addReason(r, "already_selling")
		else
			pending = pending + 1
			log.message("[LineManagerPlus] rate matcher: sell vehicle " .. tostring(v))
			local ok, err : boolean, any = pcall(api.cmd.sendCommand, api.cmd.makeVehicleSellCmd({ v }),
				function(__ : VehicleSellCommandData, success : boolean)
					if success then
						r.done[#r.done + 1] = v
					else
						addReason(r, "sell_failed")
					end
					pending = pending - 1
					settle()
				end)
			if not ok then
				warn("sell failed: " .. tostring(err))
				addReason(r, "sell_failed")
				pending = pending - 1
			end
		end
	end
	sending = false
	settle()
	return r
end

-- model switch -----------------------------------------------------------------------------

-- A new single-part vehicle of a model, ready to buy or to replace with (the store's buy-immediately config,
-- vehicle_store_window.tl:4042-4045, prepared as HandleVehicleChanges does, vehicle_react_util.tl:331-342).
local function newModelConfig(modelId : integer) : TransportVehicleConfig
	local vehicle_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_util.tl" as VehicleUtil
	local part = vehicle_util.makePart(modelId, true, nil)
	part.purchaseTime = gameTime()
	local auto : {boolean} = {}
	for k = 1, #part.part.compartment2loadConfig do auto[k] = true end
	part.autoLoadConfig = auto
	local cfg = api.type.TransportVehicleConfig.new()
	cfg.vehicles = { part }
	cfg.vehicleGroups = { 1 } -- not a multiple unit
	cfg.muFileNames = {}
	return cfg
end

local function depreciated(v : integer) : number
	local ok, val = pcall(api.engine.util.vehicle.getDepreciatedValue, v)
	if ok and type(val) == "number" and val > 0 then return val end
	return 0
end

function commands.switchModel(plan : SquareRateMatcherPlan, line : integer, template : integer, onDone? : function(SquareRateMatcherCommandResult), protected? : {integer : any}) : SquareRateMatcherCommandResult
	if plan == nil or not plan.switch or plan.model == nil then return invalid("invalid_model", 0, onDone) end
	local replace, remove = plan.replace or {}, plan.remove or {}
	local buy = math.max(0, math.floor(plan.buy or 0))
	local total = #replace + buy + #remove
	if total == 0 then return invalid("invalid_count", 0, onDone) end
	local okLine, isLine = pcall(function() : boolean
		return api.engine.entityExists(line) and api.engine.getComponent(line, api.type.ComponentType.LINE) ~= nil
	end)
	if not okLine or not isLine then return invalid("invalid_line", total, onDone) end
	local okCfg0, cfg0 = pcall(newModelConfig, plan.model)
	if not okCfg0 or cfg0 == nil then
		warn("switch config failed: " .. tostring(cfg0))
		return invalid("invalid_model", total, onDone)
	end
	local r = newResult(total)
	r.replaced, r.bought, r.sold = {}, {}, {}
	local function failAll(reason : string) : SquareRateMatcherCommandResult
		addReason(r, reason, total)
		finish(r)
		if onDone ~= nil then onDone(r) end
		return r
	end
	for __, v in ipairs(replace) do
		if tvOf(v) == nil then return failAll("invalid_template") end
		if protected ~= nil and protected[v] ~= nil and protected[v] ~= false then return failAll("protected") end
	end
	local depot : integer = nil
	if buy > 0 then
		depot, r.depotFrom = commands.resolveDepot(template, line)
		r.depot = depot
		if depot == nil then return failAll("no_depot") end
	end

	-- money, all or nothing (the store's hasEnoughMoney with the replace refund)
	local price, bal = metadataPrice(plan.model), balance()
	if price ~= nil and bal ~= nil then
		local need : number = price * (#replace + buy)
		for __, v in ipairs(replace) do need = need - depreciated(v) end
		if need > bal then return failAll("not_enough_money") end
	end
	-- the mission hook once for the whole order, as the store's accept (vehicle_store_window.tl:4227-4234)
	local newCount = #replace + buy
	if newCount > 0 then
		local okM, missionError = pcall(api.gui.fireGuiScriptEvent, "vehicleStore", "mission.buyVehicle",
			{ modelId2quantity = { [plan.model] = newCount }, actuallyBuy = true })
		if okM and type(missionError) == "string" then
			r.message = missionError as string
			return failAll("mission")
		end
	end

	local pending = 0
	local sending = true
	local function settle()
		if pending == 0 and not sending then
			finish(r)
			local after = balance()
			if bal ~= nil and after ~= nil then
				log.message("[LineManagerPlus] rate matcher: switch charged: balance " .. tostring(bal) .. " -> " .. tostring(after)
					.. " = " .. tostring(bal - after) .. " (plan net " .. tostring(plan.net) .. ")")
			end
			if onDone ~= nil then
				local ok, err : boolean, any = pcall(onDone, r)
				if not ok then warn("switch onDone failed: " .. tostring(err)) end
			end
		end
	end
	local function send(cmd : Command<ICommandData>, cb : function(ICommandData, boolean), failReason : string)
		pending = pending + 1
		local ok, err : boolean, any = pcall(api.cmd.sendCommand, cmd, function(c : ICommandData, success : boolean)
			local okCb, errCb : boolean, any = pcall(cb, c, success)
			if not okCb then warn("switch callback failed: " .. tostring(errCb)) end
			pending = pending - 1
			settle()
		end)
		if not ok then
			warn(failReason .. ": " .. tostring(err))
			addReason(r, failReason)
			pending = pending - 1
		end
	end

	-- 1. replace in place: the vehicle keeps its entity and its line (findings "replaceVehicles")
	for i, v in ipairs(replace) do
		local cfg = i == 1 and cfg0 or newModelConfig(plan.model)
		if tvOf(v) == nil then
			addReason(r, "gone")
		else
			send(api.cmd.makeVehicleReplaceCmd(v, cfg) as Command<ICommandData>, function(__ : ICommandData, success : boolean)
				if success then
					r.replaced[#r.replaced + 1] = v
					r.done[#r.done + 1] = v
				else
					addReason(r, "not_enough_money")
				end
			end, "replace_failed")
		end
	end
	-- 2. extra vehicles: buy at the line's depot, then onto the line (as cloneOntoLine)
	local player = api.engine.util.getPlayer()
	for __ = 1, buy do
		local cfg = newModelConfig(plan.model)
		send(api.cmd.makeVehicleBuyCmd(player, depot, cfg) as Command<ICommandData>, function(c : ICommandData, success : boolean)
			local cmd = c as VehicleBuyCommandData
			local newVehicle = cmd ~= nil and cmd.resultVehicleEntity or nil
			if not success or newVehicle == nil or newVehicle < 0 then
				addReason(r, "not_enough_money")
				return
			end
			if tvOf(newVehicle) == nil or not lineAlive(line) then
				r.unassigned[#r.unassigned + 1] = newVehicle
				addReason(r, "set_line_failed")
				return
			end
			send(api.cmd.makeVehicleSetLineCmd(newVehicle, line, 0) as Command<ICommandData>, function(__ : ICommandData, success2 : boolean)
				if success2 then
					r.bought[#r.bought + 1] = newVehicle
					r.done[#r.done + 1] = newVehicle
				else
					r.unassigned[#r.unassigned + 1] = newVehicle
					addReason(r, "set_line_failed")
				end
			end, "set_line_failed")
		end, "buy_failed")
	end
	-- 3. surplus old vehicles: sold at once
	for __, v in ipairs(remove) do
		local tv = tvOf(v)
		if tv == nil then
			addReason(r, "gone")
		elseif protected ~= nil and protected[v] ~= nil and protected[v] ~= false then
			addReason(r, "protected")
		elseif tv.sellOnArrival then
			addReason(r, "already_selling")
		else
			log.message("[LineManagerPlus] rate matcher: sell vehicle " .. tostring(v))
			send(api.cmd.makeVehicleSellCmd({ v }) as Command<ICommandData>, function(__ : ICommandData, success : boolean)
				if success then
					r.sold[#r.sold + 1] = v
					r.done[#r.done + 1] = v
				else
					addReason(r, "sell_failed")
				end
			end, "sell_failed")
		end
	end
	sending = false
	settle()
	return r
end

-- replace ----------------------------------------------------------------------------------

--- The vehicle window's Replace button for a list of vehicles (radar_fleet.tl replaceVehicles; vehicle.tl:445-462,
--- listener vehicle_store_window.tl:4895-4934). onClose runs on accept (after the replace commands) and on cancel.
function commands.replaceViaWindow(vehicleIds : {integer}, onClose? : function()) : boolean, string
	local react = optional("::/gui/main/react.lua") as React
	if react == nil then return false, "no_react" end
	local list : {integer} = {}
	for __, v in ipairs(vehicleIds or {}) do
		if tvOf(v) ~= nil then list[#list + 1] = v end
	end
	if #list == 0 then return false, "no_vehicles" end
	local ok, err : boolean, any = pcall(function()
		local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl" as LineUtil
		local vehicle_store_util = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_util.tl" as VehicleStoreUtil
		local tmc = line_util.getLineAndVehicleCompatibleTransportModesAndCarrier(list)
		if tmc == nil or tmc.carrier == nil then error("no common carrier") end
		local param : VehicleStoreWindow.VehicleStoreEventParam = {
			vehicleEntities = list,
			carrier = tmc.carrier,
			transportModes = tmc.transportModes,
			filterTags = vehicle_store_util.getVehicleFilterTags(list),
			onClose = function()
				if onClose ~= nil then
					local okC, errC : boolean, any = pcall(onClose)
					if not okC then warn("replace onClose failed: " .. tostring(errC)) end
				end
			end,
		}
		react.fireEvent(nil, "replaceVehicles", param)
	end)
	if ok then return true, nil end
	warn("replace window not available (" .. tostring(err) .. "); opening the vehicle manager")
	local p : ManagerWindow.ManagerWindowEventParam = { openWithVehicleEntities = list }
	pcall(react.fireEvent, nil, "openVehicleManager", p)
	return false, "fallback_manager"
end

return commands
