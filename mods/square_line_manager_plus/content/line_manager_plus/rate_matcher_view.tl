-- Line Rate Matcher: view model and texts of the popup (plans/square_line_manager_plus/RATE_MATCHER.md phase 3). Pure: no
-- api.*, only the model and the `_` global, so tests/square_line_manager_plus/test_rate_matcher_view.lua runs it offline. The
-- window (rate_matcher_window.tl) reads the engine, calls build() on every render and shows these texts.
--
-- Texts: every displayed literal goes through _() with {name} placeholders (one format string per sentence,
-- CLAUDE.md "Translations"). Called from render only (GUI thread), where _() translates at once. Counts of 1 get
-- their own key ("1 vehicle ...") instead of a plural rule. The vehicle noun is the generic "vehicles" (v1).
--
-- Choices:
--   * Supply: model.targetsFromSupply, then model.suggestForCargos over those targets; its cargo is the one the
--     options follow (the cargo needing the most vehicles), its target the prefilled box value. A typed target
--     applies to that cargo. Without supply targets (passengers, a transfer line) the options follow the lowest
--     non-passenger cargo the line loads, else passengers, else equal shares (cargo nil), and the box starts at
--     the current Rate (so the options read "keep").
--   * Plans (phase 3b, after the first GUI test): the comparison table lists the fleet's model first (its plans =
--     the suggestion's below / above counts: clones or sells), then the other models rankModels picks (their plans =
--     a switch of the whole fleet, model.switchPlans). The selected model's plans are the option rows; the
--     selection is kept by model and count across re-renders and falls back to the fleet model / the suggestion.
--   * Compact texts: facts joined by " · ", each fact its own translatable phrase (a list, not a sentence).
--   * Costs (after the second GUI test): the tables show Price (net cash), Cost/yr (running + purchase spread over
--     the lifespan, model.planCost) and Per rate (Cost/yr / ≈ Rate); the comparison marks the lowest Per rate "best"
--     (model.bestByPerRate). Other models' Rate estimate uses the line's time at stops (data.timing.loadShare) and
--     each model's load speed (rate_matcher_model.tl header).

local model = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_model.tl" as SquareRateMatcherModel

local view : SquareRateMatcherView = {}

view.MAX_TARGET = 1000000

local function num(v : any) : number
	if type(v) ~= "number" then return nil end
	local n = v as number
	if n ~= n or n == math.huge or n == -math.huge then return nil end
	return n
end

function view.fmt(v : any) : string
	local n = num(v)
	if n == nil then return "?" end
	return string.format("%d", math.floor(n + 0.5))
end

function view.fmtPer(v : any) : string
	local n = num(v)
	if n == nil then return "?" end
	if math.abs(n) < 10 then
		local s = string.format("%.1f", math.floor(n * 10 + 0.5) / 10)
		return (s:gsub("%.0$", ""))
	end
	return view.fmt(n)
end

function view.fill(s : string, vars : {string : any}) : string
	return (s:gsub("{([%w_]+)}", function(k : string) : string
		local v = vars[k]
		if v == nil then return "{" .. k .. "}" end
		return tostring(v)
	end))
end

-- supply ------------------------------------------------------------------------------------

-- Lowest loaded non-passenger cargo, else passengers, else nil.
local function loadedCargo(supply : SquareRateMatcherSupplyInput) : integer, boolean, boolean
	local best : integer = nil
	local anyPassenger, anyCargo = false, false
	for __, s in ipairs(supply ~= nil and supply.stops or {}) do
		for c, b in pairs(s.loads or {}) do
			if b == true then
				if c == supply.passengerCargo then
					anyPassenger = true
				else
					anyCargo = true
					if best == nil or c < (best as integer) then best = c end
				end
			end
		end
	end
	if best == nil and anyPassenger then best = supply.passengerCargo end
	return best, anyCargo, anyPassenger
end

function view.supplyView(data : SquareRateMatcherLineData) : SquareRateMatcherSupplyView
	local out : SquareRateMatcherSupplyView = { kind = "none", targets = {}, unsupplied = {} }
	if data == nil or data.supply == nil then return out end
	local targets, unsupplied = model.targetsFromSupply(data.supply)
	out.targets, out.unsupplied = targets, unsupplied
	local cargo, anyCargo, anyPassenger = loadedCargo(data.supply)
	out.cargo = cargo
	if #targets > 0 then
		out.kind = "cargo"
		local byCargo : {integer : number} = {}
		for __, t in ipairs(targets) do byCargo[t.cargo] = t.target end
		local s = model.suggestForCargos(data.rate, data.vehicles, byCargo)
		if s ~= nil and s.cargo ~= nil and byCargo[s.cargo] ~= nil then
			out.cargo = s.cargo
			out.suggested = model.roundValue(byCargo[s.cargo])
			out.reason = s.reason
		else
			out.cargo = targets[1].cargo
			out.suggested = targets[1].target
		end
	elseif anyCargo then
		out.kind = "no_producer"
	elseif anyPassenger then
		out.kind = "passenger"
	end
	return out
end

function view.defaultTarget(data : SquareRateMatcherLineData, supply : SquareRateMatcherSupplyView) : integer
	if supply ~= nil and supply.suggested ~= nil then return supply.suggested end
	local r = data ~= nil and model.roundValue(data.rate) or nil
	return r or 0
end

function view.parseTarget(text : string) : integer
	if type(text) ~= "string" then return nil end
	local digits = text:gsub("[^0-9]", "")
	if digits == "" then return nil end
	return view.clampTarget(tonumber(digits:sub(1, 9)))
end

function view.clampTarget(v : any) : integer
	local n = num(v)
	if n == nil then return nil end
	if n < 0 then n = 0 end
	local r = math.floor(n + 0.5)
	if r > view.MAX_TARGET then r = view.MAX_TARGET end
	return r
end

-- plans -------------------------------------------------------------------------------------

function view.pickPlan(plans : {SquareRateMatcherPlan}, count : integer) : SquareRateMatcherPlan
	if plans == nil or #plans == 0 then return nil end
	if count ~= nil then
		for __, p in ipairs(plans) do
			if p.count == count then return p end
		end
	end
	for __, p in ipairs(plans) do
		if p.suggested then return p end
	end
	return plans[1]
end

local function suggestedOf(plans : {SquareRateMatcherPlan}) : SquareRateMatcherPlan
	return view.pickPlan(plans, nil)
end

function view.build(data : SquareRateMatcherLineData, supply : SquareRateMatcherSupplyView, target : number, input : SquareRateMatcherBuildInput) : SquareRateMatcherViewState
	local v : SquareRateMatcherViewState = { status = "no_vehicles", models = {}, plans = {}, target = target }
	if data == nil then return v end
	local inp : SquareRateMatcherBuildInput = input or {}
	v.rate = data.rate
	local active = 0
	for __, x in ipairs(data.vehicles or {}) do
		if not x.selling then active = active + 1 end
	end
	v.count = active
	v.fleetRunning = model.fleetRunning(data.vehicles)
	local cargo = supply ~= nil and supply.cargo or nil
	local s = model.suggest(data.rate, data.vehicles, cargo, target)
	if s.status == "no_capacity" and cargo ~= nil and (supply == nil or supply.kind ~= "cargo") then
		-- the vehicles don't carry the guessed cargo (no supply target): fall back to equal shares
		cargo = nil
		s = model.suggest(data.rate, data.vehicles, nil, target)
	end
	v.cargo = cargo
	v.suggestion = s
	v.status = s.status
	if s.status ~= "ok" then return v end
	v.perVehicle = s.perVehicle
	v.capped = s.capped
	v.templateModel = s.templateModel
	v.templateVehicle = s.templateVehicle

	-- the fleet's model
	local cur : SquareRateMatcherModelInfo = nil
	if inp.infoOf ~= nil then cur = inp.infoOf(s.templateModel) end
	local curCosts : SquareRateMatcherModelCosts = {
		price = inp.clonePrice or (cur ~= nil and cur.price or nil),
		running = cur ~= nil and cur.running or nil,
		capital = cur ~= nil and cur.capital or nil,
	}
	local curPlans = model.plansFromSuggestion(s, data.vehicles, curCosts)
	v.models[1] = { model = s.templateModel, name = cur ~= nil and cur.name or nil, current = true,
		plans = curPlans, plan = suggestedOf(curPlans) }

	-- other models: rankModels' choice, each as a switch of the whole fleet
	local why = inp.catalogueWhy
	if inp.catalogue ~= nil and cur ~= nil and (target or 0) > 0 then
		local current : SquareRateMatcherCurrent = { model = cur.model or s.templateModel, capacity = cur.capacity,
			speed = cur.speed, perVehicle = s.perVehicle, loadSpeed = cur.loadSpeed,
			loadShare = data.timing ~= nil and data.timing.loadShare or nil }
		local candidates : {SquareRateMatcherCandidate} = {}
		local infoOf : {integer : SquareRateMatcherModelInfo} = {}
		for __, m in ipairs(inp.catalogue) do
			candidates[#candidates + 1] = { model = m.model, capacity = m.capacity, speed = m.speed, loadSpeed = m.loadSpeed }
			infoOf[m.model] = m
		end
		for __, opt in ipairs(model.rankModels(candidates, current, target)) do
			local info = infoOf[opt.model]
			local plans, whyNot = model.switchPlans(opt.model, opt.perVehicle, target, data.vehicles,
				{ price = info.price, running = info.running, capital = info.capital })
			if #plans > 0 then
				v.models[#v.models + 1] = { model = opt.model, name = info.name, current = false,
					plans = plans, plan = suggestedOf(plans) }
			elseif whyNot == "protected" then
				why = "protected"
			end
		end
	elseif inp.catalogue ~= nil and cur == nil then
		why = "no_current"
	end
	if #v.models == 1 then v.modelsWhy = why or "none" end
	local rowPlans : {SquareRateMatcherPlan} = {}
	for i, row in ipairs(v.models) do rowPlans[i] = row.plan or {} as SquareRateMatcherPlan end
	for i in pairs(model.bestByPerRate(rowPlans)) do v.models[i].best = true end

	v.selectedModel = v.models[1]
	for __, row in ipairs(v.models) do
		if inp.selectedModel ~= nil and row.model == inp.selectedModel then v.selectedModel = row end
	end
	v.plans = v.selectedModel.plans
	v.selected = view.pickPlan(v.plans, inp.selectedCount)
	return v
end

-- texts -------------------------------------------------------------------------------------

local SEP <const> = " · "

local function join(parts : {string}) : string
	return table.concat(parts, SEP)
end

function view.summaryText(v : SquareRateMatcherViewState, data : SquareRateMatcherLineData, money : function(integer) : string) : string
	local rate = v ~= nil and v.rate or (data ~= nil and data.rate or nil)
	local count = v ~= nil and v.count or 0
	local parts : {string} = { view.fill(_("Rate {rate}/yr"), { rate = view.fmt(rate) }) }
	if count == 0 then
		parts[#parts + 1] = _("no vehicles")
		return join(parts)
	end
	if count == 1 then
		parts[#parts + 1] = _("1 vehicle")
	else
		parts[#parts + 1] = view.fill(_("{count} vehicles"), { count = count })
		local per = v ~= nil and v.perVehicle or nil
		if per == nil then
			local r = num(rate)
			per = r ~= nil and r / count or nil
		end
		parts[#parts + 1] = view.fill(_("{per} each"), { per = view.fmtPer(per) })
	end
	local running = v ~= nil and v.fleetRunning or nil
	if running ~= nil then
		local m = money ~= nil and money(math.floor(running + 0.5)) or view.fmt(running)
		parts[#parts + 1] = view.fill(_("running {money}/yr"), { money = m })
	end
	return join(parts)
end

function view.statsCells(v : SquareRateMatcherViewState, data : SquareRateMatcherLineData, money : function(integer) : string) : {SquareRateMatcherStatCell}
	local rate = v ~= nil and v.rate or (data ~= nil and data.rate or nil)
	local count = v ~= nil and v.count or 0
	local per = v ~= nil and v.perVehicle or nil
	if per == nil and count > 0 then
		local r = num(rate)
		per = r ~= nil and r / count or nil
	end
	local running = v ~= nil and v.fleetRunning or nil
	local runText = "?"
	if running ~= nil then
		runText = money ~= nil and money(math.floor(running + 0.5)) or view.fmt(running)
	end
	return {
		{ title = _("Rate"), value = view.fill(_("{rate}/yr"), { rate = view.fmt(rate) }) },
		{ title = _("Vehicles"), value = tostring(count) },
		{ title = _("Per vehicle"), value = count > 0 and view.fill(_("{rate}/yr"), { rate = view.fmtPer(per) }) or "–" },
		{ title = _("Running costs per year"), value = runText,
			tip = _("The vehicles' running costs per year,\nas their vehicle windows show them.") },
	}
end

function view.supplyLines(supply : SquareRateMatcherSupplyView, cargoName : function(integer) : string) : {string}
	local out : {string} = {}
	if supply == nil then return out end
	local function name(c : integer) : string
		local n = cargoName ~= nil and cargoName(c) or nil
		return n or tostring(c)
	end
	if supply.kind == "cargo" then
		for __, t in ipairs(supply.targets) do
			local parts : {string} = { view.fill(_("{cargo} in reach: up to {max}/yr"),
				{ cargo = name(t.cargo), max = view.fmt(t.maxSupply) }) }
			if t.produced ~= nil then
				parts[#parts + 1] = view.fill(_("measured {produced}"), { produced = view.fmt(t.produced) })
			end
			if (t.otherRate or 0) > 0 then
				parts[#parts + 1] = view.fill(_("other lines take {rate}"), { rate = view.fmt(t.otherRate) })
			end
			out[#out + 1] = join(parts)
		end
		for __, c in ipairs(supply.unsupplied) do
			out[#out + 1] = view.fill(_("{cargo}: no producer in reach"), { cargo = name(c) })
		end
		if supply.reason == "most_vehicles" and supply.cargo ~= nil then
			out[#out + 1] = view.fill(_("The target follows {cargo}: it needs the most vehicles."), { cargo = name(supply.cargo) })
		end
	elseif supply.kind == "no_producer" then
		out[#out + 1] = _("No producer in reach where this line loads: type a target.")
	elseif supply.kind == "passenger" then
		out[#out + 1] = _("No supply target for passengers: type a target.")
	else
		out[#out + 1] = _("This line loads nothing: type a target.")
	end
	return out
end

function view.statusText(v : SquareRateMatcherViewState) : string
	if v == nil then return _("No line selected.") end
	if v.status == "no_vehicles" then return _("This line has no vehicles to copy.") end
	if v.status == "no_rate" then return _("The line's Rate is 0, so there is nothing to scale from.") end
	if v.status == "no_capacity" then return _("The line's vehicles carry none of this cargo.") end
	if v.status == "invalid_target" then return _("Type a target of 0 or more.") end
	if v.status == "ok" and v.capped and v.selectedModel ~= nil and v.selectedModel.current then
		return view.fill(_("Even {n} more vehicles stay below the target."), { n = model.MAX_ADD })
	end
	return nil
end

local function moneyOf(x : number, money : function(integer) : string) : string
	local n = num(x)
	if n == nil then return "?" end
	local i = math.floor(n + 0.5)
	if i == 0 then return "–" end
	if money ~= nil then return money(i) end
	return tostring(i)
end

function view.planCells(p : SquareRateMatcherPlan, money : function(integer) : string) : {string}
	local change : string
	if p.delta > 0 then
		change = "+" .. tostring(p.delta)
	elseif p.delta < 0 then
		change = "-" .. tostring(-p.delta)
	else
		change = "="
	end
	return {
		tostring(p.count),
		change,
		view.fmt(p.rate),
		moneyOf(p.net, money),
		moneyOf(p.costYear, money),
		moneyOf(p.perRate, money),
	}
end

function view.costTip(p : SquareRateMatcherPlan, money : function(integer) : string) : string
	if p == nil or p.running == nil or p.capital == nil then return nil end
	local function m(x : number) : string
		local i = math.floor(x + 0.5)
		if money ~= nil then return money(i) end
		return tostring(i)
	end
	return view.fill(_("Running costs {running}/yr\n+ purchase prices spread over the lifespan {capital}/yr"),
		{ running = m(p.running), capital = m(p.capital) })
end

function view.modelName(row : SquareRateMatcherModelRow) : string
	local name = row ~= nil and row.name or nil
	if name == nil then name = "?" end
	if row ~= nil and row.current then return view.fill(_("{name} (current)"), { name = name }) end
	return name
end

function view.planActionText(p : SquareRateMatcherPlan, modelName : string) : string
	if p == nil then return _("Nothing to change.") end
	local vars : {string : any} = { n = math.abs(p.delta), model = modelName or "?", count = p.count }
	if p.switch then
		if p.delta > 0 then
			return view.fill(_("Replaces every vehicle with {model} and buys more: {count} in total."), vars)
		elseif p.delta < 0 then
			return view.fill(_("Replaces every vehicle with {model} and sells the rest: {count} in total."), vars)
		end
		return view.fill(_("Replaces every vehicle with {model}: {count} in total."), vars)
	end
	if p.delta > 0 then
		if p.delta == 1 then return _("Buys 1 copy of the line's vehicle for this line.") end
		return view.fill(_("Buys {n} copies of the line's vehicle for this line."), vars)
	elseif p.delta < 0 then
		if p.delta == -1 then return _("Sells the newest vehicle at once.") end
		return view.fill(_("Sells the {n} newest vehicles at once."), vars)
	end
	return _("Nothing to change.")
end

function view.modelsHint(reason : string) : string
	if reason == "multi_part" then return _("No model suggestions for trains and multiple units.") end
	if reason == "mixed_carriers" then return _("No model suggestions: the line mixes vehicle types.") end
	if reason == "no_vehicles" or reason == "vehicle_gone" then return _("No model suggestions without vehicles.") end
	if reason == "protected" then return _("No model switch: the line has mission vehicles.") end
	return _("No other buyable model carries this cargo.")
end

local function reasonCount(r : SquareRateMatcherCommandResult, key : string) : integer
	return r ~= nil and r.reasons ~= nil and r.reasons[key] or 0
end

function view.resultText(kind : string, r : SquareRateMatcherCommandResult, modelName? : string) : string, boolean
	if r == nil then return _("Nothing was changed."), true end
	local done, req = #(r.done or {}), r.requested or 0
	local vars : {string : any} = { n = done, total = req }
	if reasonCount(r, "mission") > 0 and r.message ~= nil then
		return view.fill(_("The mission does not allow this: {message}"), { message = r.message }), true
	end
	if kind == "switch" then
		local sv : {string : any} = { model = modelName or "?", replaced = #(r.replaced or {}),
			bought = #(r.bought or {}), sold = #(r.sold or {}) }
		if r.status == "ok" then
			return view.fill(_("Switched to {model}: {replaced} replaced, {bought} bought, {sold} sold."), sv), false
		end
		if r.status == "partial" then
			return view.fill(_("Switched in part to {model}: {replaced} replaced, {bought} bought, {sold} sold."), sv), true
		end
		if reasonCount(r, "not_enough_money") > 0 then return _("Not enough money for this switch."), true end
		if reasonCount(r, "no_depot") > 0 then return _("No depot found for this line."), true end
		if reasonCount(r, "protected") > 0 then return _("No model switch: the line has mission vehicles."), true end
		return _("Could not switch the model (see the game log)."), true
	end
	if kind == "sell" then
		if r.status == "ok" then
			if done == 1 then return _("Sold 1 vehicle."), false end
			return view.fill(_("Sold {n} vehicles."), vars), false
		elseif r.status == "partial" then
			return view.fill(_("Sold {n} of {total} vehicles."), vars), true
		end
		return _("Could not sell the vehicles."), true
	end
	-- clone
	if r.status == "ok" then
		if done == 1 then return _("Bought 1 vehicle for this line."), false end
		return view.fill(_("Bought {n} vehicles for this line."), vars), false
	end
	if r.status == "partial" then
		if reasonCount(r, "not_enough_money") > 0 then
			return view.fill(_("Bought {n} of {total} vehicles: not enough money for the rest."), vars), true
		end
		if reasonCount(r, "set_line_failed") > 0 then
			return view.fill(_("Bought {n} of {total} vehicles; the others could not join the line and wait in the depot."), vars), true
		end
		return view.fill(_("Bought {n} of {total} vehicles."), vars), true
	end
	if reasonCount(r, "not_enough_money") > 0 then return _("Not enough money to buy a vehicle."), true end
	if reasonCount(r, "no_depot") > 0 then return _("No depot found for this line."), true end
	if reasonCount(r, "set_line_failed") > 0 then
		return _("The vehicles were bought but could not join the line; they wait in the depot."), true
	end
	return _("Could not buy vehicles (see the game log)."), true
end

return view
