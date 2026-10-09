-- Industry Flows: engine reads (GUI thread, read-only). Turns the map into plain records
-- (IndustryFlowsWorld, industry_flows_types.d.tl) for the pure model (flows_model.tl), which does
-- the grouping, search, link building, toggles, de-duplication and cap.
-- Read here, as the base industry window does (.cache/game/base/content/gui/entity_window/industry/industry.tl:195-247):
--   * per industry: rule inputs / outputs and stock types from STOCK_LIST (industry_util.tl:603-647)
--   * per town: TOWN.cargoNeeds (town_util.tl:1883-1909)
--   * actual vs potential: cargo_util.getCargoFlowCount(from, to, cargoType, isTown) > 0
--   * position: top centre of the BOUNDING_VOLUME bbox
--   * type name: description.name of the construction resource (see gather.typeName)
--   * cargo names: CargoType.name, so the search also matches input / output cargos (gather.cargoName)

local cargo_util = ug_require "::/gui/main/cargo_util.tl" as CargoUtil

local gather : IndustryFlowsGather = {}

--- Industry entities carry INDUSTRY and STOCK_LIST (industry_util.tl:637-638 reads STOCK_LIST of
--- each INDUSTRY entity); they are the industry subconstruction. Its construction is found like the
--- base HUD does (.cache/game/base/content/gui/main/hud_icon_toolbox.tl:242-245).
function gather.typeOf(industryEntity : integer) : string
	local conEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(industryEntity)
	if conEntity == nil or conEntity < 0 then return "" end
	local con = api.engine.getComponent(conEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if con == nil or con.fileName == nil then return "" end
	return con.fileName as string
end

-- typeKey -> localized name; nameMissing marks keys without a usable name. Construction resources
-- do not change during a session, so one lookup per key is enough (a GUI-side cache, nothing saved).
local nameCache : {string : string} = {}
local nameMissing : {string : boolean} = {}

--- The construction's description.name. Lookup as the base game does for a CONSTRUCTION.fileName:
--- constructionRep.find + get (.cache/game/base/content/gui/construction/construction.tl:1236-1240;
--- findAndGet errors on a missing resource, api/tealdef/api/res.d.tl:30-33). The name is already
--- localized when the .con is loaded (its data() calls _("INDUSTRIES_..._NAME")): the base game shows
--- conData.description.name to players as is (availability_notifications.script.tl:69 ->
--- notifications/types/con_availability.script.tl:44-45; construction menu construction_react_util.tl:979).
function gather.typeName(typeKey : string) : string
	if typeKey == nil or typeKey == "" then return nil end
	if nameCache[typeKey] ~= nil or nameMissing[typeKey] then return nameCache[typeKey] end
	local ok, name = pcall(function() : string
		local id = api.res.constructionRep.find(typeKey)
		if id == nil or id < 0 then return nil end
		local desc = api.res.constructionRep.get(id)
		if desc == nil or desc.description == nil then return nil end
		return desc.description.name
	end)
	if ok and type(name) == "string" and name ~= "" then
		nameCache[typeKey] = name as string
	else
		nameMissing[typeKey] = true
	end
	return nameCache[typeKey]
end

-- CargoTypeId -> localized name, cached like nameCache (cargo resources do not change in a session).
local cargoNameCache : {integer : string} = {}
local cargoNameMissing : {integer : boolean} = {}

--- CargoType.name is the display name: the base game shows it as is (cargo icon tooltips,
--- gui/main/cargo_react_util.tl:27-28).
function gather.cargoName(cargo : integer) : string
	if cargo == nil then return nil end
	if cargoNameCache[cargo] ~= nil or cargoNameMissing[cargo] then return cargoNameCache[cargo] end
	local ok, name = pcall(function() : string
		local ct = api.res.cargoTypeRep.get(cargo)
		return ct ~= nil and ct.name or nil
	end)
	if ok and type(name) == "string" and name ~= "" then
		cargoNameCache[cargo] = name as string
	else
		cargoNameMissing[cargo] = true
	end
	return cargoNameCache[cargo]
end

--- Top centre of the bbox, as plain numbers (industry.tl:195-202). nil without a BOUNDING_VOLUME.
local function positionOf(entity : integer) : {number}
	local bv = api.engine.getComponent(entity, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if bv == nil then return nil end
	local mn, mx = bv.bbox.min, bv.bbox.max
	return { mn.x + 0.5 * (mx.x - mn.x), mn.y + 0.5 * (mx.y - mn.y), mx.z }
end

local function setToList(set : {integer : boolean}) : {integer}
	local out : {integer} = {}
	for c in pairs(set) do out[#out + 1] = c end
	table.sort(out)
	return out
end

local function readIndustry(e : integer) : IndustryFlowsIndustry
	local stockList = api.engine.getComponent(e, api.type.ComponentType.STOCK_LIST) as Engine.Component.StockList
	if stockList == nil then return nil end
	local inputs : {integer : boolean} = {}
	local outputs : {integer : boolean} = {}
	local inputStocks : {integer : boolean} = {}
	local outputStocks : {integer : boolean} = {}
	local stocks = stockList.stocks
	for i = 1, #stockList.rules do
		local rule = stockList.rules[i]
		local ruleInputs = rule.input[1]
		if ruleInputs ~= nil then
			for j = 1, #ruleInputs do
				if ruleInputs[j] > 0 and stocks[j] ~= nil then
					inputs[stocks[j].cargoType as integer] = true
				end
			end
		end
		for cargoType, __ in pairs(rule.output) do
			outputs[cargoType as integer] = true
		end
	end
	local inputType = api.type["enum"].StockListType.InputStock
	local outputType = api.type["enum"].StockListType.OutputStock
	for j = 1, #stocks do
		local s = stocks[j]
		if s.type == inputType then
			inputStocks[s.cargoType as integer] = true
		elseif s.type == outputType then
			outputStocks[s.cargoType as integer] = true
		end
	end
	return {
		entity = e,
		typeKey = gather.typeOf(e),
		pos = positionOf(e),
		inputs = setToList(inputs),
		outputs = setToList(outputs),
		inputStocks = setToList(inputStocks),
		outputStocks = setToList(outputStocks),
	}
end

local function readTown(t : integer) : IndustryFlowsTown
	local town = api.engine.getComponent(t, api.type.ComponentType.TOWN) as Engine.Component.Town
	if town == nil then return nil end
	local needs : {integer} = {}
	for __, cargoNeeds in ipairs(town.cargoNeeds) do
		for __, cargoAndLevel in ipairs(cargoNeeds) do
			needs[#needs + 1] = cargoAndLevel[1] as integer
		end
	end
	return { entity = t, pos = positionOf(t), needs = needs }
end

function gather.readWorld() : IndustryFlowsWorld
	local world : IndustryFlowsWorld = { industries = {}, towns = {}, typeNames = {}, cargoNames = {} }
	-- src: .cache/game/base/content/gui/statistics/statistic_industries.tl:392
	for __, e in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.INDUSTRY)) do
		local info = readIndustry(e)
		if info ~= nil then
			world.industries[#world.industries + 1] = info
			if info.typeKey ~= "" and world.typeNames[info.typeKey] == nil then
				world.typeNames[info.typeKey] = gather.typeName(info.typeKey)
			end
			for __, cargos in ipairs({ info.inputs, info.outputs }) do
				for __, c in ipairs(cargos) do
					if world.cargoNames[c] == nil then world.cargoNames[c] = gather.cargoName(c) end
				end
			end
		end
	end
	for __, t in ipairs(api.engine.getEntitiesWithComponent(api.type.ComponentType.TOWN)) do
		local town = readTown(t)
		if town ~= nil then world.towns[#world.towns + 1] = town end
	end
	return world
end

-- getCargoFlowCount(from, to, cargo, isTown): .cache/game/base/content/gui/main/cargo_util.tl:976-986
-- (for towns it swaps the arguments itself, like industry.tl:216).
function gather.flowCount(from : integer, to : integer, cargo : integer, toTown : boolean) : integer
	return cargo_util.getCargoFlowCount(from, to, cargo, toTown)
end

return gather
