-- production_label_model: window headline number (`actual`, else capacity `total`) per output, producing/idle state from
-- `actual` with the produceFrequency fallback, rounding, style choice, formatting, and the pickup-rate value/pills.
-- Plain tables only (shapes: base/tealdef/gui/main/industry_util.d.tl ProductionData,
-- api/tealdef/api/engine.d.tl StockList.CargoData).

local model = ug_require "square_industry_production_label::/production_label/production_label_model.tl"

local function pd(cargoType, total, actual)
	return { cargoTypeId = cargoType, total = total, actual = actual }
end

local function cargoData(freq)
	local out = {}
	for ct, f in pairs(freq or {}) do out[ct] = { produceFrequency = f } end
	return out
end

before_each(function()
	model.PREFIX = ""
end)

-- roundValue ------------------------------------------------------------------

test("roundValue rounds like base mathutil.round (floor(x + 0.5))", function()
	eq(model.roundValue(0), 0)
	eq(model.roundValue(33.49), 33)
	eq(model.roundValue(33.5), 34)
	eq(model.roundValue(34), 34)
	eq(model.roundValue(0.4), 0)
end)

test("roundValue rejects nil, non-numbers, NaN, inf and negatives", function()
	eq(model.roundValue(nil), nil)
	eq(model.roundValue("12"), nil)
	eq(model.roundValue({}), nil)
	eq(model.roundValue(0 / 0), nil)
	eq(model.roundValue(math.huge), nil)
	eq(model.roundValue(-math.huge), nil)
	eq(model.roundValue(-1), nil)
end)

-- isProducing -----------------------------------------------------------------

test("isProducing uses actual when it is a number", function()
	eq(model.isProducing(12, nil), true)
	eq(model.isProducing(0, 50), false) -- actual wins over produceFrequency
	eq(model.isProducing(0.4, nil), false) -- rounds to 0, as the window would show it
	eq(model.isProducing(0.5, nil), true)
end)

test("isProducing falls back to produceFrequency when actual is nil (output-only rules)", function()
	eq(model.isProducing(nil, 34), true)
	eq(model.isProducing(nil, 0), false)
	eq(model.isProducing(nil, nil), false)
	eq(model.isProducing("x", 3), true)
	eq(model.isProducing(nil, "x"), false)
	eq(model.isProducing(0 / 0, nil), false)
end)

-- produceFrequency ----------------------------------------------------------------

test("produceFrequency reads cargoData[cargoType].produceFrequency or nil", function()
	eq(model.produceFrequency(cargoData({ [7] = 20 }), 7), 20)
	eq(model.produceFrequency(cargoData({ [0] = 3 }), 0), 3)
	eq(model.produceFrequency(cargoData({ [7] = 20 }), 8), nil)
	eq(model.produceFrequency({ [7] = "x" }, 7), nil)
	eq(model.produceFrequency(nil, 7), nil)
	eq(model.produceFrequency(cargoData({ [7] = 20 }), nil), nil)
end)

-- makeEntry -----------------------------------------------------------------------

test("fresh fishing ground: full stock, not served -> capacity 34, idle", function()
	-- raw producer: getIndustryProductionData gives actual = nil (foundOutputFraction)
	eq(model.makeEntry(pd(7, 34.2, nil), cargoData({ [7] = 0 })), { cargoType = 7, value = 34, producing = false })
	eq(model.makeEntry(pd(7, 34.2, nil), cargoData({})), { cargoType = 7, value = 34, producing = false })
	eq(model.makeEntry(pd(7, 34.2, nil), nil), { cargoType = 7, value = 34, producing = false })
end)

test("raw producer that is producing", function()
	eq(model.makeEntry(pd(7, 34, nil), cargoData({ [7] = 30 })), { cargoType = 7, value = 34, producing = true })
end)

test("processor: number is the window's Current Production, not the max", function()
	-- cement plant in game: window shows 112 (Current Production) over max 175
	eq(model.makeEntry(pd(9, 175, 112.4), nil), { cargoType = 9, value = 112, producing = true })
	eq(model.makeEntry(pd(9, 120.4, 0), cargoData({ [9] = 61 })), { cargoType = 9, value = 0, producing = false })
end)

test("capacity 0 or invalid gives no entry; idle never does", function()
	eq(model.makeEntry(pd(7, 0, 0), nil), nil)
	eq(model.makeEntry(pd(7, 0.4, 5), nil), nil)
	eq(model.makeEntry(pd(7, nil, 5), nil), nil)
	eq(model.makeEntry(pd(7, -3, 5), nil), nil)
	eq(model.makeEntry(pd(7, 0 / 0, 5), nil), nil)
	eq(model.makeEntry(pd(7, 1, 0), nil), { cargoType = 7, value = 0, producing = false })
end)

test("makeEntry rejects malformed cargo types and inputs", function()
	eq(model.makeEntry(nil, nil), nil)
	eq(model.makeEntry("x", nil), nil)
	eq(model.makeEntry(pd(nil, 34), nil), nil)
	eq(model.makeEntry(pd(-1, 34), nil), nil)
	eq(model.makeEntry(pd(1.5, 34), nil), nil)
	eq(model.makeEntry(pd("7", 34), nil), nil)
	eq(model.makeEntry(pd(0, 34, 1), nil), { cargoType = 0, value = 1, producing = true })
end)

-- view --------------------------------------------------------------------------

test("view keeps output order, one entry per cargo type", function()
	local v = model.view({ pd(12, 10, 10), pd(4, 20, nil), pd(12, 99, 99) }, cargoData({ [4] = 0 }))
	eq(v, { entries = {
		{ cargoType = 12, value = 10, producing = true },
		{ cargoType = 4, value = 20, producing = false },
	} })
end)

test("view skips bad entries and is nil when nothing applies", function()
	eq(model.view(nil, nil), nil)
	eq(model.view("x", nil), nil)
	eq(model.view({}, nil), nil)
	eq(model.view({ pd(7, 0, 0), "junk", pd(nil, 5) }, nil), nil)
	eq(model.view({ "junk", pd(7, 5, nil) }, nil), { entries = { { cargoType = 7, value = 5, producing = false } } })
end)

test("view returns a fresh table each time (useStepStateTimer compares old and new)", function()
	local list = { pd(7, 5, 5) }
	local a, b = model.view(list, nil), model.view(list, nil)
	ok(a ~= b)
	eq(a, b)
end)

-- styleFor ----------------------------------------------------------------------

test("producing: white text, no base shippingState, producing class (green background in CSS)", function()
	local s = model.styleFor(true)
	eq(s.labelFontColor, "Default")
	eq(s.shippingState, nil)
	ok(s.entryClass:find("production-label-producing", 1, true) ~= nil)
	ok(s.entryClass:find("production-label-idle", 1, true) == nil)
end)

test("idle: white text, no base shippingState, idle class (neutral background in CSS)", function()
	local s = model.styleFor(false)
	eq(s.labelFontColor, "Default")
	eq(s.shippingState, nil)
	ok(s.entryClass:find("production-label-idle", 1, true) ~= nil)
	ok(s.entryClass:find("production-label-producing", 1, true) == nil)
	ok(model.styleFor(nil) == s)
end)

test("producing and idle differ only by their background class", function()
	local p, i = model.styleFor(true), model.styleFor(false)
	eq(p.labelFontColor, i.labelFontColor)
	eq(p.shippingState, i.shippingState)
	ok(p.entryClass ~= i.entryClass)
end)

test("style values exist in the base enums (gui_react_util.tl color2Style / shippingStateStyles)", function()
	local colors = { Default = true, Warning = true, Error = true, Positive = true, Negative = true,
		Normal = true, Inferior = true, Poor = true }
	local states = { Warehouse = true, WaitingPassenger = true, Vehicle = true, IndustryInput = true, IndustryOutput = true }
	for _, s in ipairs({ model.STYLE_PRODUCING, model.STYLE_IDLE, model.STYLE_PICKUP }) do
		ok(colors[s.labelFontColor], tostring(s.labelFontColor))
		ok(s.shippingState == nil or states[s.shippingState], tostring(s.shippingState))
	end
end)

-- iconPaths -----------------------------------------------------------------------

local CARGO = "::/gui/icons/cargo/fish.tga"

test("one output: only the capacity icon", function()
	eq(model.iconPaths(CARGO, 1), { model.CAPACITY_ICON })
	eq(model.CAPACITY_ICON, "::/gui/entity_window/icons/building_industry.tga")
end)

test("two or more outputs: capacity icon, then the cargo icon", function()
	eq(model.ICON_MIN_OUTPUTS, 2)
	eq(model.iconPaths(CARGO, 2), { model.CAPACITY_ICON, CARGO })
	eq(model.iconPaths(CARGO, 3), { model.CAPACITY_ICON, CARGO })
end)

test("a missing cargo icon or count never errors and keeps the capacity icon", function()
	eq(model.iconPaths(nil, 2), { model.CAPACITY_ICON })
	eq(model.iconPaths("", 2), { model.CAPACITY_ICON })
	eq(model.iconPaths(CARGO, nil), { model.CAPACITY_ICON })
end)

test("iconPaths returns a fresh table each time", function()
	local a, b = model.iconPaths(CARGO, 2), model.iconPaths(CARGO, 2)
	ok(a ~= b)
	a[1] = "x"
	eq(model.iconPaths(CARGO, 1), { "::/gui/entity_window/icons/building_industry.tga" })
end)

-- formatLabel -------------------------------------------------------------------

test("formatLabel is the bare number (no glyph prefix: the HUD font has no triangle)", function()
	eq(model.PREFIX, "")
	eq(model.formatLabel(34), "34")
	eq(model.formatLabel(0), "0")
end)

test("formatLabel uses the given integer formatter", function()
	eq(model.formatLabel(1234, function(v) return "1,234" end), "1,234")
end)

test("PREFIX is one constant, easy to swap", function()
	model.PREFIX = "+"
	eq(model.formatLabel(5), "+5")
end)

-- pickup rate (PLAN "Pickup rate pill") ----------------------------------------------

test("pickupValue: rounded rate when > 0, else nil", function()
	eq(model.pickupValue({ [7] = 112 }, 7), 112)
	eq(model.pickupValue({ [7] = 111.5 }, 7), 112)
	eq(model.pickupValue({ [0] = 3 }, 0), 3)
	eq(model.pickupValue({ [7] = 0 }, 7), nil)
	eq(model.pickupValue({ [7] = 0.4 }, 7), nil)
	eq(model.pickupValue({ [7] = 112 }, 8), nil)
	eq(model.pickupValue({ [7] = "112" }, 7), nil)
	eq(model.pickupValue({ [7] = 0 / 0 }, 7), nil)
	eq(model.pickupValue({ [7] = -5 }, 7), nil)
	eq(model.pickupValue(nil, 7), nil)
	eq(model.pickupValue("x", 7), nil)
	eq(model.pickupValue({ [7] = 5 }, nil), nil)
end)

test("fishing ground served by a ship line: production 79, pickup 112 on the same entry", function()
	eq(model.makeEntry(pd(7, 79, nil), cargoData({ [7] = 30 }), { [7] = 112 }),
		{ cargoType = 7, value = 79, producing = true, pickup = 112 })
end)

test("no lines (nil / empty / other cargo / zero rate): entry has no pickup", function()
	eq(model.makeEntry(pd(7, 79, nil), nil, nil).pickup, nil)
	eq(model.makeEntry(pd(7, 79, nil), nil, {}).pickup, nil)
	eq(model.makeEntry(pd(7, 79, nil), nil, { [9] = 50 }).pickup, nil)
	eq(model.makeEntry(pd(7, 79, nil), nil, { [7] = 0 }).pickup, nil)
end)

test("a pickup rate never creates an entry for an output without capacity", function()
	eq(model.makeEntry(pd(7, 0, 0), nil, { [7] = 100 }), nil)
	eq(model.view({ pd(7, 0, 0) }, nil, { [7] = 100 }), nil)
end)

test("view passes pickup rates per cargo, in output order", function()
	local v = model.view({ pd(12, 10, 10), pd(4, 20, nil) }, nil, { [4] = 60, [99] = 5 })
	eq(v, { entries = {
		{ cargoType = 12, value = 10, producing = true },
		{ cargoType = 4, value = 20, producing = false, pickup = 60 },
	} })
end)

test("pickupEntries: only entries with a pickup, in order; fresh table; empty for nil", function()
	local v = model.view({ pd(12, 10, 10), pd(4, 20, nil), pd(5, 3, nil) }, nil, { [5] = 7, [12] = 9 })
	local p = model.pickupEntries(v)
	eq(#p, 2)
	eq(p[1].cargoType, 12)
	eq(p[1].pickup, 9)
	eq(p[2].cargoType, 5)
	eq(p[2].pickup, 7)
	ok(model.pickupEntries(v) ~= p)
	eq(model.pickupEntries(nil), {})
	eq(model.pickupEntries(model.view({ pd(7, 5, 5) }, nil, nil)), {})
end)

test("isUnused: every value 0 and no pickup; any number > 0 or any pickup keeps the label", function()
	-- Processor with no input: current production 0 for both outputs (the screenshot case).
	ok(model.isUnused(model.view({ pd(7, 20, 0), pd(3, 10, 0) }, nil, nil)))
	ok(model.isUnused(nil))
	ok(model.isUnused({ entries = {} }))
	-- One output producing: shown.
	ok(not model.isUnused(model.view({ pd(7, 20, 0), pd(3, 10, 4) }, nil, nil)))
	-- Raw producer (actual nil): its capacity is the number, never unused.
	ok(not model.isUnused(model.view({ pd(7, 34, nil) }, nil, nil)))
	-- A line already picks up here: shown even at 0.
	ok(not model.isUnused(model.view({ pd(7, 20, 0) }, nil, { [7] = 50 })))
	-- Pickup rates that round to 0 do not count.
	ok(model.isUnused(model.view({ pd(7, 20, 0) }, nil, { [7] = 0.2 })))
end)

test("pickup pill style: white text, no shippingState, own neutral class", function()
	local s = model.STYLE_PICKUP
	eq(s.labelFontColor, "Default")
	eq(s.shippingState, nil)
	ok(s.entryClass:find("production-label-pickup", 1, true) ~= nil)
	ok(s.entryClass:find("production-label-entry", 1, true) ~= nil)
	ok(s.entryClass:find("production-label-producing", 1, true) == nil)
end)

test("pickup icons: line icon first, cargo icon from ICON_MIN_OUTPUTS outputs on", function()
	eq(model.PICKUP_ICON, "::/gui/game_bar/icons/line_vehicle_manager_30.tga")
	eq(model.iconPaths(CARGO, 1, model.PICKUP_ICON), { model.PICKUP_ICON })
	eq(model.iconPaths(CARGO, 2, model.PICKUP_ICON), { model.PICKUP_ICON, CARGO })
	eq(model.iconPaths(nil, 2, model.PICKUP_ICON), { model.PICKUP_ICON })
	-- the default main icon is still the capacity icon
	eq(model.iconPaths(CARGO, 2, nil), { model.CAPACITY_ICON, CARGO })
end)

-- options (PLAN "Options") ------------------------------------------------------------

test("options: the mod's getModParams entry, 2 = off; missing / malformed = all on", function()
	local on = { showProduction = true, showPickup = true, showWarehouse = true, holdShift = true }
	eq(model.options(nil), on)
	eq(model.options("x"), on)
	eq(model.options(5), on)
	eq(model.options({}), on)
	eq(model.options({ showProduction = 1, showPickup = 1, showWarehouse = 1 }), on)
	eq(model.options({ showProduction = 2, showPickup = 1, showWarehouse = 1 }), { showProduction = false, showPickup = true, showWarehouse = true, holdShift = true })
	eq(model.options({ showProduction = 1, showPickup = 2, showWarehouse = 1 }), { showProduction = true, showPickup = false, showWarehouse = true, holdShift = true })
	eq(model.options({ showProduction = 1, showPickup = 1, showWarehouse = 2 }), { showProduction = true, showPickup = true, showWarehouse = false, holdShift = true })
	eq(model.options({ showProduction = 2, showPickup = 2, showWarehouse = 2 }), { showProduction = false, showPickup = false, showWarehouse = false, holdShift = true })
	eq(model.options({ holdShift = 2 }).holdShift, false)
	eq(model.options({ holdShift = 1 }).holdShift, true)
	-- a float 2.0 (engine number) is still Off; other values and types are On
	eq(model.options({ showProduction = 2.0 }).showProduction, false)
	eq(model.options({ showProduction = "2", showPickup = false, showWarehouse = 0 }), on)
	local t = {}
	ok(model.options(t) ~= t and model.options(nil) ~= model.options(nil), "fresh table")
end)

-- warehouse rates (PLAN "Warehouse rates (2026-10-07)") ------------------------------------------

local function wr(cargoType, incoming, outgoing)
	return { cargoType = cargoType, incoming = incoming, outgoing = outgoing }
end

test("kind: warehouse only for captureParams.kind == \"warehouse\"; industry otherwise", function()
	eq(model.kind({ kind = "warehouse" }), "warehouse")
	eq(model.WAREHOUSE_KIND, "warehouse")
	eq(model.kind(nil), "industry")
	eq(model.kind("warehouse"), "industry")
	eq(model.kind({}), "industry")
	eq(model.kind({ kind = "industry" }), "industry")
	eq(model.kind({ showProduction = true, showPickup = false }), "industry")
	eq(model.kind({ kind = "Warehouse" }), "industry")
end)

test("warehouseEntry rounds counts, malformed / negative counts are 0", function()
	eq(model.warehouseEntry(wr(5, 120.4, 80.5)), { cargoType = 5, incoming = 120, outgoing = 81 })
	eq(model.warehouseEntry(wr(5, 120, nil)), { cargoType = 5, incoming = 120, outgoing = 0 })
	eq(model.warehouseEntry(wr(5, -3, 7)), { cargoType = 5, incoming = 0, outgoing = 7 })
	eq(model.warehouseEntry(wr(5, "x", 0 / 0)), nil)
	eq(model.warehouseEntry(wr(0, 1, 0)), { cargoType = 0, incoming = 1, outgoing = 0 })
end)

test("warehouseEntry: nothing moved (both round to 0) or bad cargo type gives nil", function()
	eq(model.warehouseEntry(wr(5, 0, 0)), nil)
	eq(model.warehouseEntry(wr(5, 0.4, 0.3)), nil)
	eq(model.warehouseEntry(wr(nil, 10, 10)), nil)
	eq(model.warehouseEntry(wr(-1, 10, 10)), nil)
	eq(model.warehouseEntry(wr(1.5, 10, 10)), nil)
	eq(model.warehouseEntry(wr("5", 10, 10)), nil)
	eq(model.warehouseEntry(nil), nil)
	eq(model.warehouseEntry("x"), nil)
end)

test("warehouseView: only cargos that moved, busiest first, ties by cargo type id", function()
	local view = model.warehouseView({ wr(9, 10, 0), wr(2, 0, 0), wr(4, 50, 60), wr(3, 0, 10), wr(1, 5, 5) })
	eq(view, { entries = {
		{ cargoType = 4, incoming = 50, outgoing = 60 },
		{ cargoType = 1, incoming = 5, outgoing = 5 },
		{ cargoType = 3, incoming = 0, outgoing = 10 },
		{ cargoType = 9, incoming = 10, outgoing = 0 },
	} })
end)

test("warehouseView order does not depend on input order", function()
	local a = model.warehouseView({ wr(1, 5, 5), wr(3, 0, 10), wr(4, 50, 60) })
	local b = model.warehouseView({ wr(4, 50, 60), wr(3, 0, 10), wr(1, 5, 5) })
	eq(a, b)
end)

test("warehouseView: one entry per cargo type (first wins), malformed rows skipped", function()
	local view = model.warehouseView({ wr(4, 1, 0), "x", wr(4, 99, 99), wr(nil, 5, 5), 7, wr(2, 0, 3) })
	eq(view, { entries = { { cargoType = 2, incoming = 0, outgoing = 3 }, { cargoType = 4, incoming = 1, outgoing = 0 } } })
end)

test("warehouseView: nil when nothing moved or the input is not a list", function()
	eq(model.warehouseView({}), nil)
	eq(model.warehouseView({ wr(1, 0, 0), wr(2, 0.2, 0) }), nil)
	eq(model.warehouseView(nil), nil)
	eq(model.warehouseView("x"), nil)
end)

test("warehouseView keeps at most MAX_WAREHOUSE_CARGOS, the busiest", function()
	eq(model.MAX_WAREHOUSE_CARGOS, 6)
	local rates = {}
	for ct = 1, 9 do rates[#rates + 1] = wr(ct, ct * 10, 0) end
	local view = model.warehouseView(rates)
	eq(#view.entries, 6)
	eq(view.entries[1].cargoType, 9)
	eq(view.entries[6].cargoType, 4)
	model.MAX_WAREHOUSE_CARGOS = 2
	eq(#model.warehouseView(rates).entries, 2)
	model.MAX_WAREHOUSE_CARGOS = 6
end)

test("warehouseView returns a fresh table each time", function()
	local rates = { wr(1, 5, 5) }
	local a, b = model.warehouseView(rates), model.warehouseView(rates)
	ok(a ~= b and a.entries ~= b.entries and a.entries[1] ~= b.entries[1])
end)

test("warehouse icons: direction icon, then the cargo icon when there is one", function()
	eq(model.warehouseIconPaths(model.INCOMING_ICON, "cargo.tga"), { "::/gui/entity_window/icons/symbol_cargo_received.tga", "cargo.tga" })
	eq(model.warehouseIconPaths(model.OUTGOING_ICON, "cargo.tga"), { "::/gui/entity_window/icons/symbol_cargo_supplied.tga", "cargo.tga" })
	eq(model.warehouseIconPaths(model.INCOMING_ICON, ""), { model.INCOMING_ICON })
	eq(model.warehouseIconPaths(model.INCOMING_ICON, nil), { model.INCOMING_ICON })
	ok(model.warehouseIconPaths("a", "b") ~= model.warehouseIconPaths("a", "b"), "fresh table")
end)

test("incoming / outgoing styles: white text, no shippingState, own classes", function()
	eq(model.STYLE_INCOMING, { labelFontColor = "Default", entryClass = "production-label-entry, production-label-incoming" })
	eq(model.STYLE_OUTGOING, { labelFontColor = "Default", entryClass = "production-label-entry, production-label-outgoing" })
end)

-- withPickup (read cache, PERF_REVIEW.md 2026-10-10) ---------------------------------------------

test("withPickup(view(pds, cd, nil), rates) equals view(pds, cd, rates) for representative inputs", function()
	local cases = {
		{ { { cargoTypeId = 7, total = 34 } }, { [7] = { produceFrequency = 30 } }, { [7] = 112 } },
		{ { { cargoTypeId = 9, total = 175, actual = 112.4 } }, { [9] = { produceFrequency = 112 } }, nil },
		{ { { cargoTypeId = 3, total = 20 }, { cargoTypeId = 17, total = 12.5 } }, { [3] = { produceFrequency = 8 } }, { [3] = 40.6, [17] = 0 } },
		{ { { cargoTypeId = 13, total = 60, actual = 45 }, { cargoTypeId = 11, total = 30 }, { cargoTypeId = 13, total = 99 } }, {}, { [13] = 7, [11] = 0.4, [15] = 50 } },
		{ { { cargoTypeId = 5, total = 10 } }, nil, { [5] = -3 } },
		{ { { cargoTypeId = 5, total = 10 } }, nil, "malformed" },
		{ { { cargoTypeId = 5, total = 0 } }, nil, { [5] = 9 } },
	}
	for i, c in ipairs(cases) do
		eq(model.withPickup(model.view(c[1], c[2], nil), c[3]), model.view(c[1], c[2], c[3]), "case " .. i)
	end
end)

test("withPickup: nil view stays nil; nil rates return the shared view itself; the base is never changed", function()
	eq(model.withPickup(nil, { [7] = 1 }), nil)
	local base = model.view({ { cargoTypeId = 7, total = 34 } }, {}, nil)
	ok(model.withPickup(base, nil) == base)
	local with = model.withPickup(base, { [7] = 112 })
	eq(with.entries[1].pickup, 112)
	eq(base.entries[1].pickup, nil)
	ok(with.entries[1] ~= base.entries[1])
end)
