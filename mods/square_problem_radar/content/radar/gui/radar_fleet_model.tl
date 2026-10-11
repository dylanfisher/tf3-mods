-- Problem Radar fleet window model (rev 6, plans/square_problem_radar/FLEET_UPGRADE.md). PURE: no api.*,
-- no base modules, so it is unit-tested offline (tests/square_problem_radar/test_fleet_model.lua).
-- build(raw) turns the window poll's raw engine numbers (radar_fleet.tl) into a small view for
-- useStepStateTimer's deepEquals (.cache/game/base/content/gui/main/engine_react_util.tl:126-145):
-- the line totals, usage %, the 12-month money split, the fleet grouped by composition and which
-- "Upgrade" actions are offered. Ages are whole years, so a poll only re-renders when something
-- visible changed. Numbers only: render (radar_fleet.tl) formats and translates.

local model : ProblemRadarFleetModel = {}

-- Default calendar year in game ms if the engine gave none (radar_checks.tl DEFAULT_YEAR_MS:
-- lifespan units are quarter days, vehicle_util.tl:31-34 multiplies them by 1000).
local DEFAULT_YEAR_MS <const> = 365 * 4 * 1000

local function int(v : any) : integer
	if type(v) ~= "number" then return nil end
	return math.floor(v as number)
end

--- The base store treats vehicles as the same type when their model id -> count maps are equal
--- (vehicle_store_window.tl:2836-2863, replaceAndAllAreOfSameType). The key encodes that map.
function model.compositionKey(modelIds : {integer}) : string
	local counts : {integer : integer} = {}
	local ids : {integer} = {}
	for __, id in ipairs(modelIds or {}) do
		if counts[id] == nil then
			counts[id] = 0
			ids[#ids + 1] = id
		end
		counts[id] = counts[id] + 1
	end
	table.sort(ids)
	local parts : {string} = {}
	for i, id in ipairs(ids) do parts[i] = tostring(id) .. "x" .. tostring(counts[id]) end
	return table.concat(parts, ",")
end

function model.compositionName(modelIds : {integer}, nameOf : function(integer) : string) : string
	local counts : {integer : integer} = {}
	local order : {integer} = {}
	for __, id in ipairs(modelIds or {}) do
		if counts[id] == nil then
			counts[id] = 0
			order[#order + 1] = id
		end
		counts[id] = counts[id] + 1
	end
	local parts : {string} = {}
	for i, id in ipairs(order) do
		local name = nameOf(id)
		if name == nil or name == "" then name = "#" .. tostring(id) end
		parts[i] = counts[id] > 1 and (tostring(counts[id]) .. "× " .. name) or name
	end
	return table.concat(parts, " + ")
end

local function emptyView(vehicle : integer, gone : boolean) : ProblemRadarFleetView
	return {
		vehicle = vehicle, gone = gone, count = 0, old = 0, worn = 0, capacity = 0, used = 0, intervalS = 0,
		transported = 0, balance = 0, groups = {},
	}
end

function model.build(raw : ProblemRadarFleetRaw) : ProblemRadarFleetView
	if raw == nil then return emptyView(nil, true) end
	if raw.gone then return emptyView(raw.vehicle, true) end
	local view = emptyView(raw.vehicle, false)
	local yearMs = (raw.yearMs ~= nil and raw.yearMs > 0) and raw.yearMs or DEFAULT_YEAR_MS
	local wornAt = raw.wornAt or 0
	local names = raw.names or {}
	view.line = raw.line

	local byKey : {string : ProblemRadarFleetGroup} = {}
	local groups : {ProblemRadarFleetGroup} = {}
	local oldestMs : {string : integer} = {}
	local ageSum, ageCount = 0, 0
	local lifeSum, lifeCount = 0, 0
	local oldAll : {integer} = {}
	local oldKeys : {string : boolean} = {}
	local oldKeyCount = 0
	local all : {integer} = {}
	for __, v in ipairs(raw.vehicles or {}) do
		local e = int(v.entity)
		if e ~= nil then
			local key = v.key or ""
			local g = byKey[key]
			if g == nil then
				g = { key = key, name = names[key] or "", count = 0, old = 0, worn = 0, oldestYears = 0, lifeYears = 0,
					vehicles = {}, oldVehicles = {}, hasTarget = false, offerOld = false }
				byKey[key] = g
				groups[#groups + 1] = g
			end
			g.count = g.count + 1
			g.vehicles[#g.vehicles + 1] = e
			all[#all + 1] = e
			if e == raw.vehicle then g.hasTarget = true end
			local age, life = int(v.ageMs), int(v.lifespanMs) or 0
			if life > 0 then lifeSum, lifeCount = lifeSum + life, lifeCount + 1 end
			if age ~= nil then
				ageSum, ageCount = ageSum + age, ageCount + 1
				if oldestMs[key] == nil or age > oldestMs[key] then
					oldestMs[key] = age
					g.oldestYears = math.floor(age / yearMs)
					g.lifeYears = math.floor(life / yearMs + 0.5)
				end
				-- Same rule as fleet_old (radar_checks.fleet): lifespan 0 means "never old".
				if life > 0 and age > life then
					g.old = g.old + 1
					g.oldVehicles[#g.oldVehicles + 1] = e
					oldAll[#oldAll + 1] = e
					if not oldKeys[key] then oldKeys[key], oldKeyCount = true, oldKeyCount + 1 end
				end
			end
			-- Same rule as fleet_worn: condition at or below the threshold.
			if type(v.condition) == "number" and v.condition <= wornAt then g.worn = g.worn + 1 end
		end
	end

	for __, g in ipairs(groups) do
		table.sort(g.vehicles)
		table.sort(g.oldVehicles)
		view.count = view.count + g.count
		view.old = view.old + g.old
		view.worn = view.worn + g.worn
	end
	-- The vehicle's own group first, then the biggest groups, then by key (stable order per poll).
	table.sort(groups, function(a : ProblemRadarFleetGroup, b : ProblemRadarFleetGroup) : boolean
		if a.hasTarget ~= b.hasTarget then return a.hasTarget end
		if a.count ~= b.count then return a.count > b.count end
		return a.key < b.key
	end)
	view.groups = groups
	if ageCount > 0 then view.avgYears = math.floor(ageSum / ageCount / yearMs + 0.5) end
	-- The average lifespan (vehicles with one) as context for the average age; avgPastLife compares the
	-- unrounded averages, so "12 y · lifespan 12 y" can still be past it.
	if lifeCount > 0 then
		view.avgLifeYears = math.floor(lifeSum / lifeCount / yearMs + 0.5)
		view.avgPastLife = ageCount > 0 and ageSum / ageCount > lifeSum / lifeCount
	end

	-- Actions (plan "Actions"). Old vehicles of one composition replace together; spread over
	-- several compositions, each group row offers its own old ones instead.
	table.sort(oldAll)
	local onlyTarget = #oldAll == 1 and oldAll[1] == raw.vehicle
	if #oldAll > 0 and oldKeyCount == 1 and not onlyTarget then
		view.oldVehicles = oldAll
	end
	if oldKeyCount > 1 then
		for __, g in ipairs(groups) do
			g.offerOld = g.old > 0 and g.old < g.count
		end
	end
	-- The whole fleet: one composition, or a carrier where mixed single-unit models replace fine.
	table.sort(all)
	if #all > 1 and (#groups == 1 or not raw.multiUnit) then
		view.fleetVehicles = all
	end

	if raw.line ~= nil then
		view.capacity = int(raw.capacity) or 0
		view.used = int(raw.used) or 0
		-- Base line Utilization / statistics coverage: Σ used / Σ capacity
		-- (statistics_react_util.tl:194-218, cargo_util.tl:709-711).
		if view.capacity > 0 then view.usagePct = math.floor(view.used / view.capacity * 100 + 0.5) end
		view.intervalS = int(raw.intervalS) or 0
		view.transported = int(raw.transported) or 0
		view.balance = int(raw.balance) or 0
		-- calculateBalance(maintenanceIncomeOnly = true) = income + running costs + maintenance, the
		-- costs negative (radar.script.tl measureMoney): income is what is left.
		local running, maint = int(raw.running), int(raw.maintenance)
		if running ~= nil and maint ~= nil then
			view.running = running
			view.maintenance = maint
			view.income = view.balance - running - maint
		end
	end
	return view
end

return model
