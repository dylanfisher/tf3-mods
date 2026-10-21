-- rate_matcher.lua + rate_matcher_window.tl against fake react / builtin / engine / commands (moved from
-- tests/square_line_rate_matcher/test_gui.lua, 2026-10-11): the "Match line rate" entry in the Line actions menu
-- (lmp_actions.lua; one selected line; line_actions Off = not installed), the window's texts for WC Logs (target 101, 3 ≈ 99 preselected, cost columns, the
-- model comparison as DataTables with a select column, row clicks, the "best" tag), Apply (clone, sell, model switch) with the result message, the Line Manager vehicle list update
-- and the re-read after 1 s, a typed target (per keystroke), the Replace window button, reopening for another line,
-- close, and a closed Line Manager whose expired states are never read. Recipes render eagerly here (a recipe call
-- runs its function), so every render path runs offline; the real widgets' behaviour is checked in game
-- (plans/square_line_manager_plus/TESTING.md "Line Rate Matcher").

local PASSENGER, LOGS = 0, 4

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
local recipeParams = setmetatable({}, { __mode = "k" })
local function recipe(name, fn)
	return setmetatable({ name = name }, {
		__call = function(_self, params)
			local node = { recipe = name, tree = fn(params or {}) }
			recipeParams[node] = params -- kept out of the node, so walk() doesn't visit them
			return node
		end,
	})
end

local inputActions, mounts, selfNode = {}, {}, nil
local fakeReact = {
	RegisterRecipe = function(name, fn) return recipe(name, fn) end,
	RegisterWrapperRecipe = function(name, _wrapped, fn) return recipe(name, fn) end,
	getCurrentRecipeName = function() return currentRecipe end,
	setStyleClasses = function(...) lastClasses = table.concat({ ... }, ",") end,
	onMouseEvent = function(fn) lastMouse = fn end,
	-- touched by lmp_actions / lmp_rows recipes (never rendered here)
	useSelfRef = function() return { get = function() return selfNode end } end,
	-- gamepad: the content's back-button handler and focus on mount (rate_matcher_window.tl RateMatcherContent)
	useInputAction = function(name, h) inputActions[name] = h end,
	iaHandler = function(fn) return { action = fn } end,
	onMount = function(fn) mounts[#mounts + 1] = fn end,
	useState = function(v0) return { old = function() return v0 end, set = function() end } end,
	onStep = function(_f) end,
	onUnmount = function(_f) end,
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
	emptyLineInput = function(line, cargo)
		calls.emptyInput = { line, cargo }
		local d = lineData[line]
		if d and d.empty then return d.empty end
		return nil, d and d.emptyWhy or "not_a_line"
	end,
	currentFor = function(info, pv) return info and { model = info.model, capacity = info.capacity, speed = info.speed, perVehicle = pv } end,
	candidatesOf = function(cat)
		local out = {}
		for _, m in ipairs(cat or {}) do out[#out + 1] = { model = m.model, capacity = m.capacity, speed = m.speed } end
		return out
	end,
}

local fakeCommands = {
	clonePrice = function(template) return (calls.clonePrice and calls.clonePrice[template]) or 1000 end,
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
	buyOntoLine = function(modelId, count, line, depot, onDone)
		calls[#calls + 1] = { "buy", modelId, count, line, depot }
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
local line_util = { makeLineActionDescriptor = origDescriptor, isStopProtected = function() return false end }

-- Window param fields the fake engine rejects, like the PS5 build's 'closable' (player report 2026-10-12)
local rejectWindow = {}

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			Vec4f = { new = function(...) return { ... } end },
		},
		engine = {
			util = { getEntityName = function(e) return ({ [1] = "WC Logs", [3] = "Harbour Ferry", [5] = "Fish Ferry" })[e] or "?" end },
			entityExists = function(e) return lineData[e] ~= nil end,
			config = { getModParams = function() return {} end },
		},
		gui = {
			genericRep = {
				find = function() return 1 end,
				get = function() return { data = setmetatable({}, { __index = function() return { 1, 1, 1, 1 } end }) } end,
			},
			mouse = { Event = { Type = { Clicked = "Clicked", Pressed = "Pressed" } } },
			react = { params = { builtin = { Window = { new = function()
				return setmetatable({}, { __newindex = function(t, k, v)
					if rejectWindow[k] then error("no field " .. k) end
					rawset(t, k, v)
				end })
			end } } } },
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
local rm, actions, window, params
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
	rejectWindow = {}
	set_global("api", fakeApi())
	stub_module("::/gui/main/react.lua", fakeReact)
	stub_module("::/gui/main/builtin.lua", fakeBuiltin)
	stub_module("::/gui/main/engine_react_util.tl", fakeEngineReactUtil)
	stub_module("::/gui/main/gui_react_util.tl", {
		FocusTraversalScope = function(p) return { kind = "FocusTraversalScope", p = p } end,
	})
	inputActions, mounts, selfNode = {}, {}, nil
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return wa end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { style = t } end })
	stub_module("::/gui/main/button_react_util.tl", button_react_util)
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", line_util)
	stub_module("square_line_manager_plus::/line_manager_plus/rate_matcher_engine.tl", fakeEngine)
	stub_module("square_line_manager_plus::/line_manager_plus/rate_matcher_commands.tl", fakeCommands)
	stub_module("::/gui/main/popover_react_util.tl", { PopoverWindow = "PopoverWindow" })
	clear_logs()
	rm = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher.lua"
	actions = ug_require "square_line_manager_plus::/line_manager_plus/lmp_actions.lua"
	window = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_window.tl"
	ok(rm.install({}, {}), "installed")
	params = managerParams(1)
end)

--- The manager window calls makeLineActionDescriptor with its commonParams (captured by lmp_capture), then the
--- player clicks "Match line rate" in the Line actions menu.
local function openWindow(p)
	line_util.makeLineActionDescriptor(p or params)
	actions.runEntry("rate_matcher")
end

local function warnings()
	local n = 0
	for _, e in ipairs(log_entries()) do
		if e.level == "warning" then n = n + 1 end
	end
	return n
end

local function render()
	local w = wa.windows[#wa.windows]
	if not w then return nil end
	return w.recipe(w.params)
end

-- tests -----------------------------------------------------------------------------------------------------------
test("install: a Match line rate entry in the Line actions menu; hidden for several lines; line_actions Off", function()
	local ids = actions.ids()
	eq(ids[1], "rate_matcher")
	line_util.makeLineActionDescriptor(params)
	local mv = actions.menuView()
	eq(mv.line, 1)
	eq(mv.items[1].id, "rate_matcher")
	eq(mv.items[1].enabled, true)
	ok(mv.items[1].tooltip:find("Rate", 1, true) ~= nil, "tooltip")
	eq(window.ICON, "::/gui/line_vehicle_mgmt/icons/stat_load_speed.tga")
	actions.runEntry("rate_matcher")
	eq(#wa.windows, 1)
	eq(wa.windows[1].params.title, "WC Logs")
	ok(window.isOpenFor(1))
	eq(line_util.makeLineActionDescriptor(params).kind, "Descriptor", "descriptor passes through")

	line_util.makeLineActionDescriptor(managerParams(1, { 1, 2 }))
	eq(actions.menuView().hidden, true, "hidden with two lines selected")

	-- fresh modules: with the Line actions button Off there is no menu, so no entry
	reset_modules()
	line_util.makeLineActionDescriptor = origDescriptor
	button_react_util.makeIconToggleButton = origToggle
	local rm2 = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher.lua"
	eq(rm2.install({}, { line_actions = 1 }), false)
	eq(line_util.makeLineActionDescriptor, origDescriptor, "nothing wrapped")
	eq(#(ug_require "square_line_manager_plus::/line_manager_plus/lmp_actions.lua").ids(), 0)
end)

local function input(node)
	return find(node, function(n) return n.kind == "TextInputField" end)
end

local function content()
	return render().tree.p.content
end

test("WC Logs window: summary, supply, target 101, plan table with costs, model comparison", function()
	openWindow()
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
	ok(window.isOpenFor(1), "open for this line")
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

test("a platform whose Window lacks 'closable' (PS5): the field is left out, warned once; Close still closes", function()
	rejectWindow = { closable = true }
	openWindow()
	local win = render().tree
	eq(win.p.closable, nil)
	eq(win.p.movable, true)
	render()
	eq(warnings(), 1, "one warning, not one per render")
	buttonLabelled(content(), "Close").p.onClick()
	eq(window.isOpenFor(1), false)
end)

test("gamepad (PS5): focusable content takes the focus on mount, d-pad scope, the back button closes", function()
	openWindow()
	local win = render().tree
	eq(win.p.autoFocusOnBecomingVisible, true)
	eq(recipeParams[win.p.content].meta.forceFocusable, true)
	local tree = content().tree.p.children[1]
	eq(tree.kind, "FocusTraversalScope")
	eq(tree.p.horizontal, true)
	eq(tree.p.vertical, true)
	ok(buttonLabelled(tree, "Close") ~= nil, "the buttons are inside the scope")
	local focused = 0
	selfNode = { focus = function() focused = focused + 1 end }
	for _, fn in ipairs(mounts) do fn() end
	ok(focused >= 1, "focused on mount")
	-- no node to focus (not mounted yet): logged once, nothing raised
	selfNode = nil
	for _, fn in ipairs(mounts) do fn() end
	eq(warnings(), 1)
	ok(inputActions.IA_MENU_BACK ~= nil, "a back-button handler")
	inputActions.IA_MENU_BACK.action()
	eq(window.isOpenFor(1), false)
	eq(#wa.windows, 0)
end)

test("a platform whose base react / gui_react_util lack the gamepad helpers (PS5 report 2026-10-19): renders, no error", function()
	-- docs/findings/gui.md "Base GUI modules differ by platform" (Smart Lanes player report): the console build's base
	-- GUI scripts lack functions the PC copies have. Without them: no back-button handler, no focus on mount, the
	-- layout without the d-pad scope; the window still renders and Close still closes.
	local saved = {}
	for _, k in ipairs({ "useInputAction", "iaHandler", "useSelfRef", "onMount" }) do
		saved[k] = fakeReact[k]
		fakeReact[k] = nil
	end
	stub_module("::/gui/main/gui_react_util.tl", {})
	reset_modules()
	stub_module("::/gui/main/react.lua", fakeReact)
	local okT, e = pcall(function()
		rm = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher.lua"
		actions = ug_require "square_line_manager_plus::/line_manager_plus/lmp_actions.lua"
		window = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_window.tl"
		ok(rm.install({}, {}), "installed")
		openWindow()
		local tree = content().tree.p.children[1]
		ok(tree.kind ~= "FocusTraversalScope", "no scope")
		ok(buttonLabelled(tree, "Close") ~= nil, "the buttons render")
		eq(next(inputActions), nil, "no back-button handler")
		eq(#mounts, 0, "no focus on mount")
		buttonLabelled(tree, "Close").p.onClick()
		eq(window.isOpenFor(1), false)
	end)
	for k, v in pairs(saved) do fakeReact[k] = v end
	if not okT then error(e, 0) end
end)

test("rows select by click anywhere or by their box; a re-render gives fresh row keys", function()
	openWindow()
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
	openWindow()
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
	openWindow()
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
	openWindow()
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
	openWindow()
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
	ok(hasText(content(), "Sold 1 vehicle."))
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
	openWindow()
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
	ok(hasText(c, "Switched to Big Ship: 1 replaced, 0 bought, 1 sold."))
	eq(listCalls, { { 101, false }, { 102, true } })
	ok(hasText(c, "Small Ship (current)"), "after Apply the selection is back on the fleet's model")
end)

test("Replace window button, reopening for another line, line gone, close", function()
	openWindow()
	buttonLabelled(content(), "Replace window").p.onClick()
	eq(calls[1], { "replace", { 101, 102 } })

	-- another line: the window is replaced and shows that line
	local p3 = managerParams(3)
	openWindow(p3)
	eq(#wa.windows, 1)
	eq(wa.windows[1].params.title, "Harbour Ferry")
	local c = content()
	ok(hasText(c, "No supply target for passengers: type a target."))
	ok(hasText(c, "No model suggestions for trains and multiple units."))
	eq(input(c).p.value, "103")
	eq(window.isOpenFor(1), false, "no longer open for line 1")
	ok(window.isOpenFor(3))

	-- the line disappears
	lineData[3] = nil
	T = T + 2100000
	c = content()
	ok(hasText(c, "This line no longer exists."))
	buttonLabelled(c, "Close").p.onClick()
	eq(#wa.windows, 0)
	eq(window.isOpenFor(3), false)
end)

-- The window outlives the Line Manager: once the manager has closed, its captured lineState / lineManagerStateRef
-- have expired and the engine prints "Calling Old() on expired ReactStateWrap" plus a traceback for every :old() /
-- :get() (docs/findings.md "Expired react states"). The live refresh, Apply and the re-read must not touch them.
-- A render builds the view once with the last template's cached clone price, and again only when the template (the
-- line's newest vehicle of its main model) has another price.
test("render: one view build when the template's price is known; a new template's price shows", function()
	local view = ug_require "square_line_manager_plus::/line_manager_plus/rate_matcher_view.tl"
	local build, builds = view.build, 0
	view.build = function(...) builds = builds + 1; return build(...) end
	calls.clonePrice = { [104] = 2000 }
	openWindow()
	content()
	eq(builds, 2, "first render: the price is learnt")
	builds = 0
	local _, rows = tableWith(content(), "+1")
	eq(builds, 1, "then one build per render")
	eq(cellText(rows[1], 5), "$1000")
	-- live refresh: a newer vehicle 104 of the same model becomes the template
	lineData[1].vehicles = { ships(1)[1], { id = 104, model = 7, capacities = { [LOGS] = 20 }, purchaseTime = 9,
		value = 30000, running = 5000, capital = 1200 } }
	T = T + 2100000
	builds = 0
	_, rows = tableWith(content(), "+1")
	eq(builds, 2, "the new template's price differs: built again")
	eq(cellText(rows[1], 5), "$2000")
	builds = 0
	content()
	eq(builds, 1)
	view.build = build
end)

test("an expired lineState of a closed manager window is never read", function()
	openWindow()
	local reads, listed = 0, 0
	local function expired()
		return {
			hasExpired = function() return true end,
			old = function() reads = reads + 1; error("old() on an expired state") end,
			get = function() reads = reads + 1; error("get() on an expired state") end,
		}
	end
	params.lineState = expired()
	params.lineManagerStateRef = expired()
	params.addOrRemoveVehicleToVehicleList = function() listed = listed + 1 end
	-- live refresh (every 2 s)
	T = T + 2100000
	local c = content()
	ok(hasText(c, "66/yr"), "still renders line 1")
	-- Apply a clone; the callback and the 1 s re-read would update the manager's vehicle list
	buttonLabelled(content(), "Apply").p.onClick()
	eq(calls[1], { "clone", 102, 1, 1 })
	lineData[1].vehicles = ships(3)
	calls.onDone({ status = "ok", requested = 1, done = { 103 }, unassigned = {}, reasons = {} })
	ok(hasText(content(), "Bought 1 vehicle for this line."))
	T = T + 1100000
	content()
	T = T + 2100000
	content()
	eq(reads, 0, "no :old() / :get() on an expired state")
	eq(listed, 0, "no vehicle list call into the closed manager")
	eq(warnings(), 0)
	eq(wa.windows[1].params.title, "WC Logs")
	eq(actions.menuView().hidden, true, "no menu for a closed manager")
	eq(reads, 0)
end)

-- A fish ship line with no vehicles (2026-10-19): the estimate table instead of "no vehicles to copy", Apply buys the
-- selected model onto the line, the check line once the line has a Rate. Route 6 km, line 124996's times: a 20-fish
-- ship ≈ 29.2/yr, a 50-fish ship ≈ 72.9/yr; the fish farm makes 32/yr.
local function fishLine()
	lineData[5] = {
		rate = 0,
		vehicles = {},
		supply = {
			line = 5, passengerCargo = PASSENGER,
			stops = {
				{ stationGroup = 50, loads = set(LOGS), producers = { { stockList = 600, cargo = LOGS, maxPerYear = 32 } } },
				{ stationGroup = 51, loads = set(), producers = {} },
			},
			otherLines = {},
		},
		empty = { line = 5, depot = 300, cargo = LOGS, distance = 6072, stops = 2, yearSeconds = 1460,
			times = { carrier = "water", detour = 955.2 / (6072 / 8.3333), dwell = 22.9, n = 4, fallback = false },
			catalogue = {
				{ model = 7, name = "Small Ship", capacity = 20, speed = 8.3333, price = 1000, running = 600, capital = 100 },
				{ model = 9, name = "Big Ship", capacity = 50, speed = 8.3333, price = 3000, running = 800, capital = 300 },
			} },
	}
end

test("empty line: estimate table, note, Apply buys the selected model onto the line, then the check log", function()
	fishLine()
	openWindow(managerParams(5))
	eq(calls.emptyInput, { 5, LOGS }, "the estimate input is read for the line's cargo")
	local c = content()
	ok(not hasText(c, "This line has no vehicles to copy."))
	ok(hasText(c, "Suggested vehicles (estimate)"))
	ok(hasText(c, "Estimated from the route: 6.1 km round trip, 2 stops. Times from 4 other ship lines."))
	eq(input(c).p.value, "32")
	local dt, rows = tableWith(c, "Big Ship")
	ok(dt ~= nil, "the estimate table")
	eq(headersOf(dt), { " ", "Model", "Vehicles", "≈ Rate", "Price", "Cost/yr", "Cost per unit", " " })
	eq(#rows, 2)
	-- Small Ship 1 ≈ 29 (diff 2.8) before Big Ship 1 ≈ 73; per unit Small 700 / 29.2 = 24 vs Big 1100 / 72.9 = 15
	eq({ cellText(rows[1], 2), cellText(rows[1], 3), cellText(rows[1], 4) }, { "Small Ship", "1", "≈ 29" })
	eq({ cellText(rows[2], 2), cellText(rows[2], 3), cellText(rows[2], 4), cellText(rows[2], 5), cellText(rows[2], 8) },
		{ "Big Ship", "1", "≈ 73", "$3000", "best" })
	eq(selectedRow(rows), 2, "the lowest cost per unit is preselected")
	ok(hasText(c, "Buys 1 new vehicle (Big Ship) for this line."))
	eq(buttonLabelled(c, "Replace window"), nil, "nothing to replace")
	eq(buttonLabelled(c, "Apply").p.meta.enabled, true)
	-- pick the small ship
	clickRow(rows[1])
	c = content()
	__, rows = tableWith(c, "Big Ship")
	eq(selectedRow(rows), 1)
	ok(hasText(c, "Buys 1 new vehicle (Small Ship) for this line."))
	-- a higher target: more of them
	input(c).p.onTyping("60")
	c = content()
	__, rows = tableWith(c, "Big Ship")
	eq(cellText(rows[1], 3), "2")
	ok(hasText(c, "Buys 2 new vehicles (Small Ship) for this line."))

	buttonLabelled(c, "Apply").p.onClick()
	eq(calls[1], { "buy", 7, 2, 5, 300 })
	-- the vehicles arrive on the line
	lineData[5].vehicles = { { id = 201, model = 7, capacities = { [LOGS] = 20 }, purchaseTime = 1, running = 600 },
		{ id = 202, model = 7, capacities = { [LOGS] = 20 }, purchaseTime = 1, running = 600 } }
	lineData[5].rate = 55
	calls.onDone({ status = "ok", requested = 2, done = { 201, 202 }, bought = { 201, 202 }, replaced = {}, sold = {},
		unassigned = {}, reasons = {} })
	c = content()
	ok(hasText(c, "Bought 2 vehicles for this line."))
	eq(listCalls, { { 201, false }, { 202, false } }, "the Line Manager's list gets them")
	T = T + 1100000
	c = content()
	ok(hasText(c, "55/yr"))
	ok(tableWith(c, "+1") ~= nil, "now the fleet's own plans")
	local checks = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("empty estimate check line 5: predicted 58.34 (2 x model 7", 1, true) and e.msg:find("rate 55.00", 1, true) then
			checks = checks + 1
		end
	end
	eq(checks, 1, "one check line")
	T = T + 2100000
	content()
	checks = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("empty estimate check", 1, true) then checks = checks + 1 end
	end
	eq(checks, 1, "only once")
	local estimateLogs = 0
	for _, e in ipairs(log_entries()) do
		if e.msg:find("empty estimate line 5 carrier water: 6072.00 m, 2 stops", 1, true) then estimateLogs = estimateLogs + 1 end
	end
	eq(estimateLogs, 1, "the estimate is logged once per read of the empty line")
	eq(warnings(), 0)
end)

test("empty line without an estimate: the reason; target 0; a vehicle bought elsewhere switches the path", function()
	fishLine()
	lineData[5].empty, lineData[5].emptyWhy = nil, "no_depot"
	openWindow(managerParams(5))
	local c = content()
	ok(hasText(c, "No estimate: no depot reaches this line."))
	eq(buttonLabelled(c, "Apply").p.meta.enabled, false)

	fishLine()
	lineData[5].supply.stops[1].producers = {}
	window.close()
	openWindow(managerParams(5))
	c = content()
	eq(input(c).p.value, "0")
	ok(hasText(c, "Type a target above 0 for a suggestion."))
	ok(hasText(c, "Estimated from the route: 6.1 km round trip, 2 stops. Times from 4 other ship lines."))
	eq(buttonLabelled(c, "Apply").p.meta.enabled, false)
	-- the player buys a ship in the store: the live refresh reads the line fully (fleet path)
	calls.emptyInput = nil
	lineData[5].vehicles = { { id = 201, model = 7, capacities = { [LOGS] = 20 }, purchaseTime = 1, running = 600 } }
	lineData[5].rate = 29
	T = T + 2100000
	c = content()
	eq(calls.emptyInput, nil, "no estimate for a line with vehicles")
	ok(hasText(c, "29/yr"))
	ok(not hasText(c, "Suggested vehicles (estimate)"))
end)
