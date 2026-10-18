-- Shared groundwork (lmp_capture.lua, lmp_rows.lua) with fake react / builtin / line_util / button_react_util:
-- capture of the manager's commonParams and its accessors, chain-safe single install, and the button-row injector
-- dispatch (anchor only, order, isolation of a failing injector, fallback to the base node).

local AUTO_RENAME = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"

local recipeName, toggleCalls, descriptorCalls
local react, builtin, line_util, button_react_util, capture, rows

local function state(v) return { old = function() return v end, get = function() return v end } end

local function makeParams(line, selectedLines, vehicles)
	local sel = {}
	for i = 1, selectedLines or 1 do sel[i] = { entity = line } end
	local vsel = {}
	for i, v in ipairs(vehicles or {}) do vsel[i] = { entity = v } end
	return {
		lineState = state({ entityAndRevision = { entity = line } }),
		lineManagerStateRef = state({ lineListEntitiesSelected = sel }),
		vehicleManagerStateRef = state({ vehicleListEntitiesSelected = vsel }),
	}
end

before_each(function()
	reset_modules()
	clear_logs()
	recipeName = "LinePanelActionButtons"
	toggleCalls, descriptorCalls = 0, 0
	set_global("api", {
		engine = { config = { getModParams = function() return {} end } },
		type = { Clock = { new = function() return { getTime = function() return 1e9 end } end } },
	})
	react = { getCurrentRecipeName = function() return recipeName end }
	builtin = {
		type = { Orientation = { Horizontal = "H" } },
		BoxLayout = function(p) return { kind = "BoxLayout", orientation = p.orientation, children = p.children } end,
	}
	button_react_util = {
		makeIconToggleButton = function(class, path, _fn, tip)
			toggleCalls = toggleCalls + 1
			return { kind = "Toggle", class = class, path = path, tip = tip }
		end,
	}
	line_util = {
		makeLineActionDescriptor = function(cp, x)
			descriptorCalls = descriptorCalls + 1
			return { cp = cp, x = x }
		end,
	}
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/button_react_util.tl", button_react_util)
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", line_util)
	capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"
	rows = ug_require "square_line_manager_plus::/line_manager_plus/lmp_rows.lua"
end)

local function warnings(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

local function aplus()
	return button_react_util.makeIconToggleButton("vehicle-button, secondary", AUTO_RENAME, function() end, "tip")
end

local function kinds(node)
	local out = {}
	for i, c in ipairs(node.children) do out[i] = c.kind == "Toggle" and "A+" or c.id end
	return out
end

local function inj(id, order, extra)
	return { id = id, order = order, build = function(ctx)
		if extra == "error" then error(id .. " boom") end
		if extra == "none" then return nil end
		return { { kind = "X", id = id, params = ctx.params } }
	end }
end

-- capture ----------------------------------------------------------------------------------------------------------

test("capture: nothing before a manager call; keeps the latest manager params, ignores others", function()
	ok(capture.install())
	eq(capture.params(), nil)
	eq(capture.editedLine(), nil)
	eq(capture.selectedLineCount(), 0)
	eq(capture.selectedVehicles(), {})
	local p1, p2 = makeParams(7), makeParams(8, 2, { 101, 102 })
	local r = line_util.makeLineActionDescriptor(p1, 42)
	ok(r.cp == p1)
	eq(r.x, 42)
	ok(capture.params() == p1)
	line_util.makeLineActionDescriptor({ other = true }, 1)
	line_util.makeLineActionDescriptor(nil, 1)
	ok(capture.params() == p1)
	line_util.makeLineActionDescriptor(p2)
	ok(capture.params() == p2)
	eq(capture.editedLine(), 8)
	eq(capture.selectedLineCount(), 2)
	eq(capture.selectedVehicles(), { 101, 102 })
	eq(capture.editedLine(p1), 7)
end)

test("capture: accessors tolerate missing parts", function()
	eq(capture.editedLine({ lineState = state(nil) }), nil)
	eq(capture.editedLine({ lineState = state({}) }), nil)
	eq(capture.selectedLineCount({ lineManagerStateRef = state({}) }), 0)
	eq(capture.selectedVehicles({ vehicleManagerStateRef = state({}) }), {})
	eq(capture.selectedVehicles({}), {})
end)

test("capture: an expired lineState (closed manager window) is not read", function()
	local reads = 0
	local st = { hasExpired = function() return true end, old = function() reads = reads + 1; return nil end }
	eq(capture.expired(st), true)
	eq(capture.editedLine({ lineState = st }), nil)
	eq(reads, 0)
	eq(capture.expired({ hasExpired = function() return false end }), false)
	eq(capture.expired(state(nil)), false) -- no hasExpired: live
	eq(capture.expired(nil), false)
end)

test("capture: expired line / vehicle manager refs (closed manager window) are not read", function()
	local reads = 0
	local function expired()
		return { hasExpired = function() return true end, get = function() reads = reads + 1; error("get() on expired") end }
	end
	eq(capture.selectedLineCount({ lineManagerStateRef = expired() }), 0)
	eq(capture.selectedVehicles({ vehicleManagerStateRef = expired() }), {})
	eq(reads, 0)
end)

test("capture: installs once and keeps the previous wrapper in the chain", function()
	local prev = line_util.makeLineActionDescriptor
	local chained = 0
	line_util.makeLineActionDescriptor = function(...) chained = chained + 1; return prev(...) end
	ok(capture.install())
	ok(capture.install())
	line_util.makeLineActionDescriptor(makeParams(1))
	eq(chained, 1)
	eq(descriptorCalls, 1)
end)

test("capture: a missing base function declines the install with one warning", function()
	line_util.makeLineActionDescriptor = nil
	eq(capture.install(), false)
	eq(warnings("[LineManagerPlus] capture: install"), 1)
end)

-- rows -------------------------------------------------------------------------------------------------------------

test("rows: install also installs capture, once", function()
	ok(rows.install())
	ok(rows.install())
	line_util.makeLineActionDescriptor(makeParams(1))
	ok(capture.params() ~= nil)
	rows.register(inj("a", -1))
	aplus()
	eq(toggleCalls, 1)
end)

test("rows: a missing base function declines the install", function()
	button_react_util.makeIconToggleButton = nil
	eq(rows.install(), false)
	eq(warnings("[LineManagerPlus] rows: install"), 1)
end)

test("rows: no injectors, other icons, other recipes or no params give the base node unchanged", function()
	rows.install()
	line_util.makeLineActionDescriptor(makeParams(1))
	eq(aplus().kind, "Toggle")
	rows.register(inj("a", -1))
	eq(button_react_util.makeIconToggleButton("c", "::/other.tga").kind, "Toggle")
	recipeName = "VehicleManagerActionButtons"
	eq(aplus().kind, "Toggle")
	recipeName = "LinePanelActionButtons"
	eq(aplus().kind, "BoxLayout")
end)

test("rows: no params captured yet gives the base node", function()
	rows.install()
	rows.register(inj("a", -1))
	eq(aplus().kind, "Toggle")
end)

test("rows: order negative left of A+, otherwise right; ties by registration; ctx carries the params", function()
	rows.install()
	local p = makeParams(1)
	line_util.makeLineActionDescriptor(p)
	rows.register(inj("after", 10))
	rows.register(inj("undo", -100))
	rows.register(inj("zero", 0))
	rows.register(inj("rate", -200))
	rows.register(inj("undo2", -100))
	eq(rows.ids(), { "rate", "undo", "undo2", "zero", "after" })
	local node = aplus()
	eq(node.kind, "BoxLayout")
	eq(node.orientation, "H")
	eq(kinds(node), { "rate", "undo", "undo2", "A+", "zero", "after" })
	ok(node.children[1].params == p)
	eq(node.children[4].path, AUTO_RENAME)
end)

test("rows: all injectors left of A+ puts A+ last; registering an id again replaces it", function()
	rows.install()
	line_util.makeLineActionDescriptor(makeParams(1))
	rows.register(inj("a", -2))
	rows.register(inj("b", -1))
	rows.register(inj("a", 5))
	eq(rows.ids(), { "b", "a" })
	eq(kinds(aplus()), { "b", "A+", "a" })
end)

test("rows: an injector returning several nodes adds them in order", function()
	rows.install()
	line_util.makeLineActionDescriptor(makeParams(1))
	rows.register({ id = "two", order = -1, build = function()
		return { { kind = "X", id = "x1" }, { kind = "X", id = "x2" } }
	end })
	eq(kinds(aplus()), { "x1", "x2", "A+" })
end)

test("rows: a failing injector drops only its own nodes and warns once", function()
	rows.install()
	line_util.makeLineActionDescriptor(makeParams(1))
	rows.register(inj("bad", -2, "error"))
	rows.register(inj("good", -1))
	eq(kinds(aplus()), { "good", "A+" })
	eq(kinds(aplus()), { "good", "A+" })
	eq(warnings("[LineManagerPlus] rows: bad:"), 1)
end)

test("rows: injectors that add nothing give the base node", function()
	rows.install()
	line_util.makeLineActionDescriptor(makeParams(1))
	rows.register(inj("none", -1, "none"))
	rows.register(inj("bad", 1, "error"))
	eq(aplus().kind, "Toggle")
end)

test("rows: an error in the wrapper itself falls back to the base node and warns once", function()
	rows.install()
	line_util.makeLineActionDescriptor(makeParams(1))
	rows.register(inj("a", -1))
	react.getCurrentRecipeName = function() error("no recipe") end
	eq(aplus().kind, "Toggle")
	eq(aplus().kind, "Toggle")
	eq(warnings("[LineManagerPlus] rows: button:"), 1)
end)

test("rows: a malformed injector is refused", function()
	raises(function() rows.register({ id = "x" }) end)
	raises(function() rows.register({ build = function() end }) end)
	eq(rows.ids(), {})
end)
