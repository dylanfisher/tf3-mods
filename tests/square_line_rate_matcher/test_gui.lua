-- rate_matcher.script.lua + rate_matcher_window.tl against fake react / builtin / engine / commands: the mount left of
-- A+ (lines only, one selected), the window's texts for WC Logs (target 101, 3 ≈ 99 preselected, cost columns, the
-- model comparison as DataTables with a select column, row clicks, the "best" tag), Apply (clone, sell, model switch) with the result message, the Line Manager vehicle list update
-- and the re-read after 1 s, a typed target (per keystroke), the Replace window button, reopening for another line,
-- close. Recipes render eagerly here (a recipe call runs its function), so every render path runs offline;
-- the real widgets' behaviour is checked in game (plans/square_line_rate_matcher/TESTING.md).

local PASSENGER, LOGS = 0, 4
local AUTO_RENAME = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"

local T -- fake clock, µs
local W -- fake world
local currentRecipe
local calls
local lastClasses, lastMouse

local function set(...)
	local s = {}
	for _, c in ipairs({ ... }) do s[c] = true end
	return s
end

local function ships(n, cargo)
	local out = {}
	for i = 1, n do
		out[i] = { id = 100 + i, model = 7, capacities = { [cargo or LOGS] = 20 }, purchaseTime = i, value = 30000, running = 5000,
			capital = 1200 }
	end
	return out
end

-- fakes ---------------------------------------------------------------------------------------------------------
local function recipe(name, fn)
	return setmetatable({ name = name }, {
		__call = function(_self, params) return { recipe = name, tree = fn(params or {}) } end,
	})
end

local fakeReact = {
	RegisterRecipe = function(name, fn) return recipe(name, fn) end,
	RegisterWrapperRecipe = function(name, _wrapped, fn) return recipe(name, fn) end,
	getCurrentRecipeName = function() return currentRecipe end,
	setStyleClasses = function(...) lastClasses = table.concat({ ... }, ",") end,
	onMouseEvent = function(fn) lastMouse = fn end,
}

local fakeBuiltin = setmetatable({
	type = {
		Orientation = { Horizontal = "H", Vertical = "V" },
		ImageViewScaling = { AutoFit = "AutoFit" },
		ScrollBarPolicy = { AlwaysOff = "AlwaysOff" },
	},
}, { __index = function(_t, k) return function(p) return { kind = k, p = p or {} } end end })

local fakeEngineReactUtil = {
	useStepState = function(getter)
		local v = getter()
		return { old = function() return v end, hasExpired = function() return false end }
	end,
}

local wa
local function newWindowApi()
	return {
		windows = {},
		addSingletonWindow = function(r, params) wa.windows[#wa.windows + 1] = { recipe = r, params = params } end,
		removeAllWindows = function(_r) wa.windows = {} end,
		moveSingletonWindowToFront = function(_r) end,
	}
end

local lineData = {}
local function snapshot(line)
	local d = lineData[line]
	if not d then return nil end
	return { line = line, rate = d.rate, vehicles = d.vehicles, supply = d.supply, passengerCargo = PASSENGER, year = 1900 }
end

local fakeEngine = {
	readLine = function(line) local d = snapshot(line); if not d then return nil, "not_a_line" end; return d end,
	lineRate = function(line) return lineData[line] and lineData[line].rate end,
	lineVehicles = function(line) return lineData[line] and lineData[line].vehicles end,
	modelCatalogue = function(_ids, cargo)
		if cargo == PASSENGER then return nil, "multi_part" end
		return {
			{ model = 7, name = "Small Ship", capacity = 20, speed = 10, price = 1000, running = 6000, capital = 400, available = true },
			{ model = 9, name = "Big Ship", capacity = 60, speed = 10, price = 3000, running = 15000, capital = 900, available = true },
		}, nil
	end,
	modelInfo = function(m) return { model = m, name = "M" .. m, capacity = 20, speed = 10 } end,
	lineTiming = function(line, cargo)
		calls.timing = { line, cargo }
		return { cargo = cargo, section = 100, drive = 80, sections = 2, loadShare = 0.2 }
	end,
	currentFor = function(info, pv) return info and { model = info.model, capacity = info.capacity, speed = info.speed, perVehicle = pv } end,
	candidatesOf = function(cat)
		local out = {}
		for _, m in ipairs(cat or {}) do out[#out + 1] = { model = m.model, capacity = m.capacity, speed = m.speed } end
		return out
	end,
}

local fakeCommands = {
	clonePrice = function() return 1000 end,
	priceReport = function(v) return "vehicle " .. tostring(v) end,
	cloneOntoLine = function(template, line, count, onDone)
		calls[#calls + 1] = { "clone", template, line, count }
		calls.onDone = onDone
	end,
	sellVehicles = function(ids, onDone)
		calls[#calls + 1] = { "sell", ids }
		calls.onDone = onDone
	end,
	switchModel = function(plan, line, template, onDone)
		calls[#calls + 1] = { "switch", plan.model, line, template, plan.count }
		calls.onDone = onDone
	end,
	replaceViaWindow = function(ids, onClose)
		calls[#calls + 1] = { "replace", ids }
		calls.onClose = onClose
		return true
	end,
}

local origToggle = function(class, path) return { kind = "OrigToggle", path = path, class = class } end
local origDescriptor = function(params) return { kind = "Descriptor", params = params } end
local button_react_util = { makeIconToggleButton = origToggle }
local line_util = { makeLineActionDescriptor = origDescriptor }

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			Vec4f = { new = function(...) return { ... } end },
		},
		engine = { util = { getEntityName = function(e) return ({ [1] = "WC Logs", [3] = "Harbour Ferry" })[e] or "?" end } },
		gui = {
			genericRep = {
				find = function() return 1 end,
				get = function() return { data = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) } end,
			},
			mouse = { Event = { Type = { Clicked = "Clicked", Pressed = "Pressed" } } },
		},
		util = { formatMoney = function(m) return "$" .. tostring(m) end },
		res = {
			cargoTypeRep = { get = function(c) return { name = ({ [LOGS] = "Logs", [PASSENGER] = "Passengers" })[c] } end },
			genericRep = { getAllOfType = function() return {} end, get = function() return nil end },
		},
	}
end

-- tree helpers ----------------------------------------------------------------------------------------------------
local function walk(node, fn)
	if type(node) ~= "table" then return end
	fn(node)
	for k, v in pairs(node) do
		if k ~= "recipe" and type(v) == "table" then walk(v, fn) end
	end
end

local function texts(node)
	local out = {}
	walk(node, function(n) if n.kind == "TextView" then out[#out + 1] = n.p.text end end)
	return out
end

local function hasText(node, s)
	for _, t in ipairs(texts(node)) do if t == s then return true end end
	return false
end

local function find(node, pred)
	local found
	walk(node, function(n) if not found and pred(n) then found = n end end)
	return found
end

local function buttonLabelled(node, label)
	return find(node, function(n) return n.kind == "Button" and hasText(n.p.content, label) end)
end

-- DataTables: the cells the game would create (each column's recipe per row key, with the table's userParam)
local function renderTable(dt)
	local rows = {}
	for r, key in ipairs(dt.p.rowKeys) do
		local row = { key = key, cells = {} }
		for c, col in ipairs(dt.p.columns) do
			lastClasses, lastMouse = nil, nil
			local out = col.p.recipe({ rowKey = key, colKey = c - 1, userParam = dt.p.userParam })
			row.cells[c] = { node = out, classes = lastClasses, click = lastMouse }
		end
		rows[r] = row
	end
	return rows
end

local function cellText(row, c)
	return texts(row.cells[c].node)[1]
end

local function rowHas(row, str)
	for c = 1, #row.cells do
		if hasText(row.cells[c].node, str) then return true end
	end
	return false
end

-- the DataTable one of whose rows shows `str`, and its rendered rows
local function tableWith(node, str)
	local found, foundRows
	walk(node, function(n)
		if found or n.kind ~= "DataTable" then return end
		local rows = renderTable(n)
		for _, row in ipairs(rows) do
			if rowHas(row, str) then found, foundRows = n, rows; return end
		end
	end)
	return found, foundRows
end

local function headersOf(dt)
	local out = {}
	for i, col in ipairs(dt.p.columns) do out[i] = col.p.name end
	return out
end

local function checkboxOf(row)
	return find(row.cells[1].node, function(n) return n.kind == "CheckBox" end)
end

local function selectedRow(rows)
	for i, row in ipairs(rows) do
		if checkboxOf(row).p.value == 1 then return i end
	end
	return nil
end

local function clickRow(row, c)
	row.cells[c or 2].click({ type = "Clicked", button = 0 })
end

-- setup -----------------------------------------------------------------------------------------------------------
local script, params
local listCalls = {}

local function managerParams(line, selected)
	return {
		lineManagerStateRef = { get = function() return { lineListEntitiesSelected = selected or { line } } end },
		lineState = { old = function() return { entityAndRevision = { entity = line } } end },
		gameCtx = { filters = { get = function() return { protectedEntities = {}, vehicleFilter = nil } end } },
		addOrRemoveVehicleToVehicleList = function(d)
			listCalls[#listCalls + 1] = { d.entity, d.removeFromList }
		end,
	}
end

before_each(function()
	T = 0
	calls = {}
	listCalls = {}
	currentRecipe = nil
	wa = newWindowApi()
	lineData = {
		[1] = {
			rate = 66,
			vehicles = ships(2),
			supply = {
				line = 1, passengerCargo = PASSENGER,
				stops = {
					{ stationGroup = 10, loads = set(LOGS), producers = {
						{ stockList = 500, cargo = LOGS, maxPerYear = 101, producedPerYear = 112 } } },
					{ stationGroup = 20, loads = set(), producers = {} },
				},
				otherLines = {},
			},
		},
		[3] = {
			rate = 103,
			vehicles = ships(2, PASSENGER),
			supply = {
				line = 3, passengerCargo = PASSENGER,
				stops = { { stationGroup = 30, loads = set(PASSENGER), producers = {} } },
				otherLines = {},
			},
		},
	}
	reset_modules()
	button_react_util.makeIconToggleButton = origToggle
	line_util.makeLineActionDescriptor = origDescriptor
	set_global("api", fakeApi())
	stub_module("::/gui/main/react.lua", fakeReact)
	stub_module("::/gui/main/builtin.lua", fakeBuiltin)
	stub_module("::/gui/main/engine_react_util.tl", fakeEngineReactUtil)
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return wa end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { style = t } end })
	stub_module("::/gui/main/button_react_util.tl", button_react_util)
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", line_util)
	stub_module("square_line_rate_matcher::/rate_matcher/rate_matcher_engine.tl", fakeEngine)
	stub_module("square_line_rate_matcher::/rate_matcher/rate_matcher_commands.tl", fakeCommands)
	ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher.script.lua"
	script = data()
	script.doReplace({})
	params = managerParams(1)
end)

local function toolbar(p, recipeName)
	line_util.makeLineActionDescriptor(p)
	currentRecipe = recipeName or "LinePanelActionButtons"
	return button_react_util.makeIconToggleButton("vehicle-button, secondary", AUTO_RENAME)
end

local function toggleOf(node)
	return find(node, function(n) return n.kind == "ToggleButton" end)
end

local function render()
	local w = wa.windows[#wa.windows]
	if not w then return nil end
	return w.recipe(w.params)
end

-- tests -----------------------------------------------------------------------------------------------------------
test("mount: our button left of A+ for one selected line; nothing for depots or several lines", function()
	local node = toolbar(params)
	eq(node.kind, "BoxLayout")
	eq(node.p.children[2].kind, "OrigToggle")
	local tb = toggleOf(node.p.children[1])
	ok(tb, "toggle button rendered")
	eq(tb.p.meta.tooltip, "Match line rate")
	eq(tb.p.meta.class, "vehicle-button, secondary")
	eq(tb.p.value, 0)
	eq(tb.p.content.p.path, "::/gui/line_vehicle_mgmt/icons/stat_load_speed.tga")

	eq(toolbar(params, "LinePanelDepotActionButtons").kind, "OrigToggle", "depot panel untouched")
	eq(button_react_util.makeIconToggleButton("x", "::/other.tga").kind, "OrigToggle", "other icons untouched")
	local multi = toolbar(managerParams(1, { 1, 2 }))
	eq(toggleOf(multi), nil, "hidden with two lines selected")
	eq(line_util.makeLineActionDescriptor(params).kind, "Descriptor", "descriptor passes through")
end)

local function input(node)
	return find(node, function(n) return n.kind == "TextInputField" end)
end

local function content()
	return render().tree.p.content
end

test("WC Logs window: summary, supply, target 101, plan table with costs, model comparison", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	eq(#wa.windows, 1)
	eq(wa.windows[1].params.title, "WC Logs")
	eq(calls.timing, { 1, LOGS }, "the round-trip split is read for the line's cargo")
	local root = render()
	local win = root.tree
	eq(win.kind, "Window")
	eq(win.p.id, "squarelineratematcher.window")
	eq(win.p.closable, true)
	local c = win.p.content
	-- the stats row (Line Manager style): title above value
	for _, t in ipairs({ "Rate", "66/yr", "Vehicles", "2", "Per vehicle", "33/yr", "Running costs per year", "$10000" }) do
		ok(hasText(c, t), "stats row has " .. t)
	end
	ok(hasText(c, "Logs in reach: up to 101/yr · measured 112"))
	eq(input(c).p.value, "101")
	eq(input(c).p.acceptOnFocusLoss, true)
	ok(type(input(c).p.onTyping) == "function", "per-keystroke callback")
	eq(input(c).p.filter("12"), true); eq(input(c).p.filter("1a"), false)
	ok(hasText(c, "suggested"))
	ok(hasText(c, "Small Ship (current)"), "the selected model as the section heading")

	-- the plan table: a builtin.DataTable with weighted columns, numbers right-aligned in cells and headers
	local plans, rows = tableWith(c, "+1")
	ok(plans ~= nil, "plan table")
	eq(headersOf(plans), { " ", "Change", "Vehicles", "≈ Rate", "Price", "Cost/yr", "Cost per unit", " " })
	eq(plans.p.columns[3].p.headerStyleClass, "right-aligned")
	eq(plans.p.columns[2].p.headerStyleClass, nil)
	eq(plans.p.columns[1].p.headerStyleClass, nil)
	ok(plans.p.columns[7].p.tooltip:find("\n") ~= nil, "tooltips wrap")
	ok(plans.p.columns[6].p.tooltip:find("lifespan") ~= nil, "Cost/yr header explains itself")
	eq(#rows, 2)
	eq(selectedRow(rows), 1, "3 vehicles preselected")
	local r1 = rows[1]
	eq({ cellText(r1, 2), cellText(r1, 3), cellText(r1, 4), cellText(r1, 5), cellText(r1, 6), cellText(r1, 7), cellText(r1, 8) },
		{ "+1", "3", "99", "$1000", "$18800", "$190", "suggested" })
	eq(r1.cells[4].classes, "right-aligned,highlight", "selected row: right-aligned + the base highlight")
	eq(r1.cells[1].classes, "highlight")
	eq(rows[2].cells[4].classes, "right-aligned")
	eq(rows[2].cells[8].classes, nil)
	-- "suggested" / "best" in the base "positive" colour (as the Line Manager's Balance)
	local function tagClass(row) return find(row.cells[8].node, function(n) return n.kind == "TextView" end).p.meta.class end
	eq(tagClass(r1), "font-scale-body, positive")
	-- the tables have no scroll bars
	eq(plans.p.scrollPolicyVertical, "AlwaysOff")
	eq({ cellText(rows[2], 3), cellText(rows[2], 5), cellText(rows[2], 6), cellText(rows[2], 7) }, { "4", "$2000", "$25200", "$191" })
	local tip = find(r1.cells[6].node, function(n) return n.kind == "TextView" end).p.meta.tooltip
	eq(tip, "Running costs $16000/yr\n+ purchase prices spread over the lifespan $2800/yr")

	-- the comparison: Big Ship (3x capacity: 1 ≈ 99) is cheaper per Rate and tagged "best"
	local models, mrows = tableWith(c, "Big Ship")
	eq(headersOf(models), { " ", "Model", "Vehicles", "≈ Rate", "Price", "Cost/yr", "Cost per unit", " " })
	for i = 1, 8 do
		eq(models.p.columns[i].p.weight, plans.p.columns[i].p.weight, "same column widths in both tables")
	end
	ok(models.p.meta.localKey ~= plans.p.meta.localKey)
	eq(models.p.columns[2].p.headerStyleClass, nil, "names stay left-aligned")
	eq(#mrows, 2)
	eq(selectedRow(mrows), 1)
	eq({ cellText(mrows[2], 2), cellText(mrows[2], 3), cellText(mrows[2], 4), cellText(mrows[2], 5), cellText(mrows[2], 6),
		cellText(mrows[2], 7), cellText(mrows[2], 8) }, { "Big Ship", "1", "99", "$-57000", "$15900", "$161", "best" })
	eq(cellText(mrows[1], 8), "")
	eq(find(mrows[2].cells[8].node, function(n) return n.kind == "TextView" end).p.meta.class, "font-scale-body, positive",
		"best looks like suggested")
	ok(models.p.rowKeys[1] ~= plans.p.rowKeys[1], "row keys are unique per table")
	ok(hasText(c, "Buys 1 copy of the line's vehicle for this line."), "what Apply does")
	-- the toggle shows checked while the window is open for this line
	eq(toggleOf(toolbar(params)).p.value, 1)
	-- every recipe returns a layout (cells too); no Component has a recipe as its layout
	local function layoutsOnly(node)
		walk(node, function(n)
			if n.recipe ~= nil and n.tree ~= nil and n.recipe ~= "SquareRateMatcherWindow" then
				eq(n.tree.kind, "BoxLayout", n.recipe .. " returns a BoxLayout")
			end
			if n.kind == "Component" and n.p.layout ~= nil then
				ok(n.p.layout.recipe == nil, "Component layout is a builtin layout")
			end
		end)
	end
	layoutsOnly(root)
	for _, row in ipairs(rows) do for _, cell in ipairs(row.cells) do layoutsOnly(cell.node) end end
end)

test("rows select by click anywhere or by their box; a re-render gives fresh row keys", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	local plans, rows = tableWith(content(), "+1")
	local oldKey = plans.p.rowKeys[1]
	clickRow(rows[2], 6) -- a click on the Cost/yr cell of "4 vehicles"
	plans, rows = tableWith(content(), "+1")
	eq(selectedRow(rows), 2)
	ok(plans.p.rowKeys[1] ~= oldKey, "fresh keys: DataTable rebuilds the cells")
	ok(hasText(content(), "Buys 2 copies of the line's vehicle for this line."))
	checkboxOf(rows[1]).p.onValueChange(1)
	__, rows = tableWith(content(), "+1")
	eq(selectedRow(rows), 1)
	-- a right click does nothing
	rows[2].cells[3].click({ type = "Clicked", button = 2 })
	__, rows = tableWith(content(), "+1")
	eq(selectedRow(rows), 1)
end)

test("no sorting: compare values keep the display order, a descending sort recreates the table", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	local plans = tableWith(content(), "+1")
	for i, key in ipairs(plans.p.rowKeys) do
		for c = 1, 8 do eq(plans.p.columns[c].p.getCompareValue(key), i) end
	end
	local key0 = plans.p.meta.localKey
	plans.p.onSortColumnChange(4, true)
	eq(tableWith(content(), "+1").p.meta.localKey, key0, "ascending = display order: nothing to do")
	plans.p.onSortColumnChange(4, false)
	ok(tableWith(content(), "+1").p.meta.localKey ~= key0, "descending: a fresh, unsorted table")
end)

test("target row: -/+ and the texts share the text box's padding", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	local c = content()
	local minus = buttonLabelled(c, "-")
	ok(minus.p.meta.styleSheet ~= nil, "compact button")
	eq(buttonLabelled(c, "Apply").p.meta.styleSheet, nil)
	eq(buttonLabelled(c, "Apply").p.meta.class, "primary", "enabled Apply: primary")
	eq(buttonLabelled(c, "Apply").p.meta.tooltip, nil, "no Apply tooltip: the line above says it")
	local tip = buttonLabelled(c, "Replace window").p.meta.tooltip
	ok(tip:find("\n") ~= nil, "wrapped tooltip")
end)

test("Apply buys the preselected clone, adds it to the vehicle list, re-reads after 1 s", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	buttonLabelled(content(), "Apply").p.onClick()
	eq(calls[1], { "clone", 102, 1, 1 })
	ok(hasText(content(), "Working..."))
	eq(buttonLabelled(content(), "Apply").p.meta.enabled, false, "no second Apply while busy")
	-- the buy + set-line callbacks arrive; the line now has 3 ships
	lineData[1].vehicles = ships(3)
	lineData[1].rate = 99
	calls.onDone({ status = "ok", requested = 1, done = { 103 }, unassigned = {}, reasons = {} })
	local c = content()
	ok(hasText(c, "Bought 1 vehicle for this line."))
	eq(listCalls, { { 103, false } }, "the new ship joins the Line Manager's vehicle list")
	T = T + 1100000
	c = content()
	eq(listCalls[2], { 103, false }, "repeated at the re-read")
	ok(hasText(c, "99/yr")); ok(hasText(c, "$15000"))
	local __, rows = tableWith(c, "=")
	eq(cellText(rows[1], 3), "3")
	eq(buttonLabelled(c, "Apply").p.meta.enabled, false, "keep: nothing to apply")
	eq(buttonLabelled(c, "Apply").p.meta.class, "secondary", "a disabled Apply stays readable (outlined style)")
	-- the manager shows another line now: the list is left alone
	params = managerParams(3)
	line_util.makeLineActionDescriptor(params)
	T = T + 2000000
	content()
	eq(#listCalls, 2)
end)

test("typing a target, selling, the Suggested button, -/+ and selecting a row", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	input(content()).p.onTyping("33")
	local c = content()
	eq(input(c).p.value, "33", "the typed text stays")
	local __, rows = tableWith(c, "-1")
	eq(#rows, 1)
	eq(cellText(rows[1], 3), "1")
	eq(cellText(rows[1], 5), "$-30000", "the refund of the sold ship")
	buttonLabelled(c, "Apply").p.onClick()
	eq(calls[1], { "sell", { 102 } })
	calls.onDone({ status = "ok", requested = 1, done = { 102 }, unassigned = {}, reasons = {} })
	ok(hasText(content(), "Sent 1 vehicle to the depot to be sold."))
	eq(listCalls, { { 102, true } })

	-- an empty box keeps the target; Enter puts its number back
	input(content()).p.onTyping("")
	eq(input(content()).p.value, "")
	ok(tableWith(content(), "-1") ~= nil, "plans unchanged")
	input(content()).p.onValueChange("")
	eq(input(content()).p.value, "33")

	buttonLabelled(content(), "Suggested: 101").p.onClick()
	c = content()
	eq(input(c).p.value, "101")
	buttonLabelled(c, "+").p.onClick()
	eq(input(content()).p.value, "102")
	buttonLabelled(content(), "-").p.onClick()
	c = content()
	eq(input(c).p.value, "101")
	__, rows = tableWith(c, "+1")
	clickRow(rows[2])
	c = content()
	__, rows = tableWith(c, "+1")
	eq(selectedRow(rows), 2)
	buttonLabelled(c, "Apply").p.onClick()
	eq(calls[2], { "clone", 102, 1, 2 })
	calls.onDone({ status = "partial", requested = 2, done = { 103 }, unassigned = {}, reasons = { not_enough_money = 1 } })
	ok(hasText(content(), "Bought 1 of 2 vehicles: not enough money for the rest."))
end)

test("selecting another model: its plans, Apply switches the fleet, the list follows", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	local __, mrows = tableWith(content(), "Big Ship")
	clickRow(mrows[2])
	local c = content()
	__, mrows = tableWith(c, "Big Ship")
	eq(selectedRow(mrows), 2)
	local plans, rows = tableWith(c, "198")
	ok(plans ~= nil, "Big Ship's plans: 1 ≈ 99 and 2 ≈ 198")
	eq(#rows, 2)
	eq(selectedRow(rows), 1)
	eq(cellText(rows[1], 2), "-1")
	ok(hasText(c, "Replaces every vehicle with Big Ship and sells the rest: 1 in total."))
	buttonLabelled(c, "Apply").p.onClick()
	eq(calls[1], { "switch", 9, 1, 102, 1 })
	calls.onDone({ status = "ok", requested = 2, done = { 101, 102 }, replaced = { 101 }, bought = {}, sold = { 102 },
		unassigned = {}, reasons = {} })
	c = content()
	ok(hasText(c, "Switched to Big Ship: 1 replaced, 0 bought, 1 sent to be sold."))
	eq(listCalls, { { 101, false }, { 102, true } })
	ok(hasText(c, "Small Ship (current)"), "after Apply the selection is back on the fleet's model")
end)

test("Replace window button, reopening for another line, line gone, close", function()
	toggleOf(toolbar(params)).p.onValueChange(1)
	buttonLabelled(content(), "Replace window").p.onClick()
	eq(calls[1], { "replace", { 101, 102 } })

	-- another line: the window is replaced and shows that line
	local p3 = managerParams(3)
	toggleOf(toolbar(p3)).p.onValueChange(1)
	eq(#wa.windows, 1)
	eq(wa.windows[1].params.title, "Harbour Ferry")
	local c = content()
	ok(hasText(c, "No supply target for passengers: type a target."))
	ok(hasText(c, "No model suggestions for trains and multiple units."))
	eq(input(c).p.value, "103")
	eq(toggleOf(toolbar(params)).p.value, 0, "line 1's toggle is unchecked")

	-- the line disappears
	lineData[3] = nil
	T = T + 2100000
	c = content()
	ok(hasText(c, "This line no longer exists."))
	buttonLabelled(c, "Close").p.onClick()
	eq(#wa.windows, 0)
	eq(toggleOf(toolbar(p3)).p.value, 0)
end)
