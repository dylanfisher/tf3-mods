-- Industry Production Label: pure model (PLAN "Value" / "Format"). No api.*, no base modules, so it
-- is unit-tested offline (tests/square_industry_production_label/test_model.lua).
--
-- Input: what the HUD recipe reads through the base industry_util (production_label.script.tl):
--   * productionDatas: the results of industry_util.getIndustryProductionData(entity, false, false, i, true)
--     for every output i, i.e. { cargoTypeId, actual, total }
--     (.cache/game/base/content/gui/main/industry_util.tl:310-380, d.tl: base/tealdef/gui/main/industry_util.d.tl:31-36).
--   * cargoData: STOCK_LIST cargoData ({ [cargoType] = { produceFrequency } },
--     .cache/game/api/tealdef/api/engine.d.tl:1184-1188).
--
-- Number = the industry window's headline number (.cache/game/base/content/gui/entity_window/industry_react_util.tl:318-346):
-- "Current Production" `round(actual)` when the window has it (processors, e.g. cement plant 112 of max 175),
-- else the capacity `round(total)`, the only number the window draws for raw producers (fishing ground 34).
-- State = producing or idle, from the live rate: `actual` when the window has one, else the STOCK_LIST
-- produceFrequency of that cargo. getIndustryProductionData returns `actual = produceFrequency` too, but
-- sets it to nil for every output-only (raw producer) rule (`foundOutputFraction`, industry_util.tl:367-377),
-- so `actual` alone would leave every mine, forest and fishing ground permanently "idle".
-- Pickup = the summed line rate of the lines loading that cargo in reach, from the shared cache in
-- production_label_pickup.tl ({cargoTypeId -> rate}); shown in a second pill row only when > 0
-- (PLAN "Pickup rate pill").
-- Options = which pills to draw (mod settings, PLAN "Options"), from the mod's getModParams() entry (read live in hudIconFn).
-- Warehouses (PLAN "Warehouse rates (2026-10-07)"): per-cargo incoming / outgoing per-year counts, see
-- model.warehouseView below.

local model : SquareProductionLabelModel = {}

-- No text prefix: "▲" is not in the HUD font and rendered as "?" in game (PLAN "Format").
-- The pill is marked as capacity by CAPACITY_ICON instead.
model.PREFIX = ""

-- Industry icon the industry window draws next to its production figures
-- (.cache/game/base/content/gui/entity_window/industry_react_util.tl:715,
-- gui/entity_window/industry/industry_eow.script.tl:78). Sized like the stock pill's cargo icon by
-- makeContentLabelIndictator (class "iconlabelindicator-icon-size,hud-icon" = 26x26,
-- gui_react_util.tl:283-291, gui_react_util.css.lua:28-30).
model.CAPACITY_ICON = "::/gui/entity_window/icons/building_industry.tga"

-- From this many outputs on, each entry also shows its cargo icon so the numbers can be told apart.
-- A single output does not need it: the stock pill right above already shows that cargo.
model.ICON_MIN_OUTPUTS = 2

-- Both states keep white text (labelFontColor "Default", like the stock pill) and no shippingState
-- (every base ShippingState except Vehicle is the stock pill's blue, gameplay_colors.gres.lua:13-18).
-- The background colour that tells them apart comes from our scoped CSS on entryClass
-- (production_label.css.lua): producing = dark green, idle = neutral dark (production-label-neutral).
model.STYLE_PRODUCING = {
	labelFontColor = "Default",
	shippingState = nil,
	entryClass = "production-label-entry, production-label-producing",
}

model.STYLE_IDLE = {
	labelFontColor = "Default",
	shippingState = nil,
	entryClass = "production-label-entry, production-label-idle, production-label-neutral",
}

-- Pickup-rate pill icon: the game bar's Line Manager button (truck + route arrows,
-- .cache/game/base/content/gui/game_bar/game_bar.tl:769), so it reads "lines". Base candidates checked in
-- gui.zip: entity_window/icons/symbol_cargo (the line window's "Rate" icon, line_eow.script.tl:43-46) is
-- a plain box that reads as stock next to the stock pill; symbol_cargo_supplied is the industry
-- window's "Supplied" column (industry_eow.script.tl:505), a different number.
model.PICKUP_ICON = "::/gui/game_bar/icons/line_vehicle_manager_30.tga"

-- Pickup pills: same white text, neutral dark background like idle (production-label-neutral,
-- production_label.css.lua).
model.STYLE_PICKUP = {
	labelFontColor = "Default",
	shippingState = nil,
	entryClass = "production-label-entry, production-label-pickup, production-label-neutral",
}

-- Same as base mathutil.round (.cache/game/base/content/scripts/mathutil.lua:1-3), plus guards.
function model.roundValue(v : any) : integer
	if type(v) ~= "number" then return nil end
	local n = v as number
	if n ~= n or n == math.huge or n == -math.huge or n < 0 then return nil end
	return math.floor(n + 0.5)
end

local function toCargoType(v : any) : integer
	if type(v) ~= "number" then return nil end
	local n = v as number
	if n ~= n or n < 0 or n ~= math.floor(n) then return nil end
	return math.floor(n)
end

function model.produceFrequency(cargoData : any, cargoType : integer) : any
	if type(cargoData) ~= "table" or cargoType == nil then return nil end
	local entry = (cargoData as {integer : any})[cargoType]
	if type(entry) ~= "table" then return nil end
	return (entry as {string : any}).produceFrequency
end

function model.isProducing(actual : any, produceFrequency : any) : boolean
	local rate = actual
	if type(rate) ~= "number" then
		rate = produceFrequency
	end
	local rounded = model.roundValue(rate)
	return rounded ~= nil and rounded > 0
end

function model.pickupValue(pickupRates : any, cargoType : integer) : integer
	if type(pickupRates) ~= "table" or cargoType == nil then return nil end
	local rate = model.roundValue((pickupRates as {integer : any})[cargoType])
	if rate == nil or rate <= 0 then return nil end
	return rate
end

function model.makeEntry(productionData : any, cargoData : any, pickupRates? : any) : SquareProductionLabelEntry
	if type(productionData) ~= "table" then return nil end
	local pd = productionData as {string : any}
	local cargoType = toCargoType(pd.cargoTypeId)
	local capacity = model.roundValue(pd.total)
	if cargoType == nil or capacity == nil or capacity <= 0 then return nil end
	-- Headline number like the window: live "Current Production" when present, else capacity.
	local current = model.roundValue(pd.actual)
	return {
		cargoType = cargoType,
		value = current ~= nil and current or capacity,
		producing = model.isProducing(pd.actual, model.produceFrequency(cargoData, cargoType)),
		pickup = model.pickupValue(pickupRates, cargoType),
	}
end

function model.view(productionDatas : any, cargoData : any, pickupRates? : any) : SquareProductionLabelView
	if type(productionDatas) ~= "table" then return nil end
	local entries : {SquareProductionLabelEntry} = {}
	local seen : {integer : boolean} = {}
	for __, pd in ipairs(productionDatas as {any}) do
		local entry = model.makeEntry(pd, cargoData, pickupRates)
		if entry ~= nil and not seen[entry.cargoType] then
			seen[entry.cargoType] = true
			entries[#entries + 1] = entry
		end
	end
	if #entries == 0 then return nil end
	return { entries = entries }
end

function model.pickupEntries(view : SquareProductionLabelView) : {SquareProductionLabelEntry}
	local out : {SquareProductionLabelEntry} = {}
	if view == nil or view.entries == nil then return out end
	for __, entry in ipairs(view.entries) do
		if entry.pickup ~= nil then
			out[#out + 1] = entry
		end
	end
	return out
end

-- The read cache (production_label_readcache.tl) keeps the view without pickup, shared by every label
-- of that industry; each label adds its pickup rates here. Entries are copied, never changed in place.
function model.withPickup(view : SquareProductionLabelView, pickupRates : any) : SquareProductionLabelView
	if view == nil or pickupRates == nil then return view end
	local entries : {SquareProductionLabelEntry} = {}
	for i, e in ipairs(view.entries) do
		entries[i] = {
			cargoType = e.cargoType,
			value = e.value,
			producing = e.producing,
			pickup = model.pickupValue(pickupRates, e.cargoType),
		}
	end
	return { entries = entries }
end

-- Options (PLAN "Options", "Settings read live (2026-10-07)"): the mod's own entry of
-- api.engine.config.getModParams(), read by production_label.script.tl when a HUD icon is mounted.
-- Each value is the 1-based index of the chosen mod.json value ({"On", "Off"}): 2 = Off. Anything else
-- (1, missing key, missing / malformed table, other types) is On, the default.
local PARAM_OFF <const> = 2

local function optionOn(v : any) : boolean
	return v ~= PARAM_OFF
end

function model.options(modParams : any) : SquareProductionLabelOptions
	if type(modParams) ~= "table" then
		return { showProduction = true, showPickup = true, showWarehouse = true }
	end
	local t = modParams as {string : any}
	return {
		showProduction = optionOn(t.showProduction),
		showPickup = optionOn(t.showPickup),
		showWarehouse = optionOn(t.showWarehouse),
	}
end

function model.styleFor(producing : boolean) : SquareProductionLabelStyle
	if producing then
		return model.STYLE_PRODUCING
	end
	return model.STYLE_IDLE
end

function model.iconPaths(cargoIconPath : string, entryCount : integer, mainIcon? : string) : {string}
	local paths : {string} = { mainIcon or model.CAPACITY_ICON }
	if entryCount ~= nil and entryCount >= model.ICON_MIN_OUTPUTS and cargoIconPath ~= nil and cargoIconPath ~= "" then
		paths[#paths + 1] = cargoIconPath
	end
	return paths
end

-- Warehouse rates (PLAN "Warehouse rates (2026-10-07)") ----------------------------------------------
--
-- Input: per cargo type the warehouse's per-year incoming and outgoing counts, read in
-- production_label.script.tl with api.engine.util.stock.getCargoLogValueDiffPerYear(entity,
-- "itemsUnloaded" | "itemsLoaded", cargoTypeId) (.cache/game/api/tealdef/api/engine/util.d.tl:89-94). These are
-- the logs behind the warehouse window's Incoming / Outgoing chart
-- (gui/entity_window/warehouse/warehouse_eow.script.tl:159) and the base stock pill's trend
-- (gui/main/cargo_util.tl:238-239).

-- captureParams.kind that content/mod.script.lua sets on warehouse constructions. Anything else
-- ({kind = "industry"}, or a missing kind) is an industry.
model.WAREHOUSE_KIND = "warehouse"

-- Direction icons: the industry window's "Received" and "Supplied" column headers, a cargo box with a
-- down arrow (in) and an up arrow (out) (industry_eow.script.tl:384, 505; town.tl:403). Base masks in
-- gui.zip (gui/entity_window/icons/symbol_cargo_received@2x.tga, symbol_cargo_supplied@2x.tga), tinted
-- white by the pill like the other icons.
model.INCOMING_ICON = "::/gui/entity_window/icons/symbol_cargo_received.tga"
model.OUTGOING_ICON = "::/gui/entity_window/icons/symbol_cargo_supplied.tga"

-- At most this many cargos per warehouse label (the busiest ones), so a universal warehouse that
-- handles many cargos does not grow a label wider than the screen.
model.MAX_WAREHOUSE_CARGOS = 6

-- Incoming / outgoing pills: white text, no shippingState; the background comes from our CSS
-- (production_label.css.lua), in the colours of the warehouse window chart (Positive / Negative).
model.STYLE_INCOMING = {
	labelFontColor = "Default",
	shippingState = nil,
	entryClass = "production-label-entry, production-label-incoming",
}

model.STYLE_OUTGOING = {
	labelFontColor = "Default",
	shippingState = nil,
	entryClass = "production-label-entry, production-label-outgoing",
}

function model.kind(captureParams : any) : string
	if type(captureParams) == "table" and (captureParams as {string : any}).kind == model.WAREHOUSE_KIND then
		return model.WAREHOUSE_KIND
	end
	return "industry"
end

-- A per-year count as shown: rounded, 0 for nil / malformed / negative values.
local function countValue(v : any) : integer
	local n = model.roundValue(v)
	if n == nil then return 0 end
	return n
end

function model.warehouseEntry(raw : any) : SquareProductionLabelWarehouseEntry
	if type(raw) ~= "table" then return nil end
	local t = raw as {string : any}
	local cargoType = toCargoType(t.cargoType)
	if cargoType == nil then return nil end
	local incoming = countValue(t.incoming)
	local outgoing = countValue(t.outgoing)
	if incoming <= 0 and outgoing <= 0 then return nil end
	return { cargoType = cargoType, incoming = incoming, outgoing = outgoing }
end

function model.warehouseView(rates : any) : SquareProductionLabelWarehouseView
	if type(rates) ~= "table" then return nil end
	local entries : {SquareProductionLabelWarehouseEntry} = {}
	local seen : {integer : boolean} = {}
	for __, raw in ipairs(rates as {any}) do
		local entry = model.warehouseEntry(raw)
		if entry ~= nil and not seen[entry.cargoType] then
			seen[entry.cargoType] = true
			entries[#entries + 1] = entry
		end
	end
	if #entries == 0 then return nil end
	-- Busiest first (incoming + outgoing), ties by cargo type id: a stable order whatever order the
	-- cargo types came in (the engine read walks api.res.cargoTypeRep.getAll() with pairs).
	table.sort(entries, function(a : SquareProductionLabelWarehouseEntry, b : SquareProductionLabelWarehouseEntry) : boolean
		local ta = a.incoming + a.outgoing
		local tb = b.incoming + b.outgoing
		if ta ~= tb then return ta > tb end
		return a.cargoType < b.cargoType
	end)
	for i = #entries, model.MAX_WAREHOUSE_CARGOS + 1, -1 do
		entries[i] = nil
	end
	return { entries = entries }
end

function model.warehouseIconPaths(directionIcon : string, cargoIconPath : string) : {string}
	local paths : {string} = { directionIcon }
	if cargoIconPath ~= nil and cargoIconPath ~= "" then
		paths[#paths + 1] = cargoIconPath
	end
	return paths
end

function model.formatLabel(value : integer, formatInt? : function(integer) : string) : string
	local text : string
	if formatInt ~= nil then
		text = formatInt(value)
	else
		text = tostring(value)
	end
	return model.PREFIX .. text
end

return model
