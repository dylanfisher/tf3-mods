-- Line Manager Plus colour dot tooltip (line_dot.lua) with fake react / builtin / base modules and a fake api.
-- Covers: install (wraps line_react_util.ColorWidget once, keeps the previous wrapper in the chain, skips a missing
-- field, shims ReplaceRecipe), the wrapper's pass-through (other caller, no onClick, a ref argument, a non-numeric
-- entity, an error), the list dot (SquareLmpLineDot root BoxLayout, mouse listener returns false, not hovered: the
-- caller's param table unchanged; hovered: the vanilla tooltip plus the stats lines; a depot/deleted entity or a
-- stats error: the untouched param, logged once).

local react, builtin, lru, dot, recipeName, recipeFns, hook, world, colorCalls
local RAPI_CALLS

local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	recipeName = "LineAndDepotListEntry"
	recipeFns, colorCalls, RAPI_CALLS = {}, {}, {}
	hook = { state = nil, mouse = nil }
	world = { lines = { [1] = { 11, 12 } }, vehicles = { [11] = 100, [12] = 200 } }
	set_global("api", {
		type = {
			ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" },
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
		},
		gui = { mouse = { Event = { Type = { Entered = "E", Exited = "X", Pressed = "P" } } } },
		engine = {
			entityExists = function(e) return world.lines[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] and {} or nil end
				if ct == "TV" and world.vehicles[e] then
					return { transportVehicleConfig = { vehicles = { { part = { modelId = world.vehicles[e] } } } } }
				end
			end,
			system = { transportVehicleSystem = { getLineVehicles = function(line)
				if world.failList then error("list boom") end
				return world.lines[line]
			end } },
			util = { line = { calcLineStationThroughput = function() return 4321 end } },
		},
		res = { modelRep = { get = function(id)
			return { metadata = { description = { name = id == 100 and "Bus A" or "Bus B" } } }
		end } },
		util = {
			toStringPercentPrecision = function(v) return tostring(math.floor(v * 100)) .. "%" end,
			formatMinutesSeconds = function(s) return string.format("%d:%02d", s // 60, s % 60) end,
		},
	})
	react = {
		-- a recipe call returns a node; the test renders our recipe through recipeFns with the fake hooks below
		RegisterRecipe = function(name, fn)
			recipeFns[name] = fn
			return function(p) return { recipe = name, p = p } end
		end,
		getCurrentRecipeName = function() return recipeName end,
		useState = function(init)
			if not hook.state then
				local st = { v = init, sets = 0 }
				function st:old() return self.v end
				function st:set(v) self.v = v; self.sets = self.sets + 1 end
				hook.state = st
			end
			return hook.state
		end,
		onMouseEvent = function(fn) hook.mouse = fn end,
	}
	builtin = {
		BoxLayout = function(p) return { kind = "BoxLayout", children = p.children } end,
	}
	lru = {}
	if opts.noField ~= true then
		lru.ColorWidget = function(...)
			colorCalls[#colorCalls + 1] = table.pack(...)
			if opts.failColor then error("color boom") end
			return { kind = "ColorWidget", args = table.pack(...) }
		end
	end
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/line_vehicle_mgmt/line_react_util.tl", lru)
	stub_module("::/scripts/lang_util.tl", { format = format, formatInt = function(n) return tostring(n) end })
	stub_module("::/gui/statistics/statistics_react_util.tl", { calculateCargoColumnDataForLine = function()
		return { demand = 80, coverage = 0.25 }
	end })
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", { calculateFrequencySeconds = function() return 90 end })
	dot = ug_require "square_line_manager_plus::/line_manager_plus/line_dot.lua"
end

local function rapi()
	return { ReplaceRecipe = function(orig, repl) RAPI_CALLS[#RAPI_CALLS + 1] = { orig = orig, repl = repl } end }
end

local function warnings(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

local function listParam(entity)
	return { tooltip = "Open Line Window", entity = entity or 1, onClick = function() end }
end

-- render our recipe node (as the engine would) and return its result
local function render(node)
	eq(node.recipe, "SquareLmpLineDot")
	return recipeFns.SquareLmpLineDot(node.p)
end

local STATS = "Vehicles on this line: 2\n1× Bus A\n1× Bus B\n"
	.. "Capacity: 80  ·  Utilization: 25%  ·  Frequency: 1:30  ·  Rate: 4321"

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps ColorWidget once and logs installed", function()
	setup()
	local orig = lru.ColorWidget
	ok(dot.install(rapi()))
	ok(lru.ColorWidget ~= orig)
	local w = lru.ColorWidget
	ok(dot.install(rapi()))
	ok(lru.ColorWidget == w)
	eq(warnings(), 0)
end)

test("install: a missing ColorWidget installs nothing and warns once", function()
	setup({ noField = true })
	eq(dot.install(rapi()), false)
	eq(lru.ColorWidget, nil)
	eq(warnings("install"), 1)
end)

test("install: keeps the previous wrapper in the chain", function()
	setup()
	local prev, chained = lru.ColorWidget, 0
	lru.ColorWidget = function(...) chained = chained + 1; return prev(...) end
	dot.install(rapi())
	recipeName = "TownWindow"
	lru.ColorWidget({ entity = 1 })
	eq(chained, 1)
	eq(#colorCalls, 1)
end)

test("install: a later ReplaceRecipe of our wrapper gets the wrapped recipe; others pass unchanged", function()
	setup()
	local orig = lru.ColorWidget
	local api_ = rapi()
	dot.install(api_)
	local other = function() end
	api_.ReplaceRecipe(lru.ColorWidget, "R1")
	api_.ReplaceRecipe(other, "R2")
	ok(RAPI_CALLS[1].orig == orig)
	eq(RAPI_CALLS[1].repl, "R1")
	ok(RAPI_CALLS[2].orig == other)
	setup()
	ok(dot.install(nil)) -- no replacement api: still installs
end)

-- wrapper pass-through -----------------------------------------------------------------------------------------------

test("wrapper: other callers, no onClick, a ref argument or a non-numeric entity go straight to ColorWidget", function()
	setup()
	dot.install(rapi())
	local L = "LineAndDepotListEntry"
	local cases = {
		{ "TownWindow", { listParam() } },
		{ L, { { tooltip = "x", entity = 1 } } },
		{ L, { "ref", listParam() } },
		{ L, { { tooltip = "x", entity = "1", onClick = function() end } } },
		{ L, { "notatable" } },
	}
	for i, c in ipairs(cases) do
		recipeName = c[1]
		local args = c[2]
		local node = lru.ColorWidget(table.unpack(args))
		eq(node.kind, "ColorWidget", "case " .. i)
		eq(node.args.n, #args)
		for j = 1, #args do ok(node.args[j] == args[j]) end
	end
	eq(warnings(), 0)
end)

test("wrapper: an error while deciding passes through to ColorWidget and warns once", function()
	setup()
	dot.install(rapi())
	react.getCurrentRecipeName = function() error("no ctx") end
	for _i = 1, 3 do
		local p = listParam()
		local node = lru.ColorWidget(p)
		eq(node.kind, "ColorWidget")
		ok(node.args[1] == p)
	end
	eq(warnings("wrap"), 1)
end)

-- the list dot -------------------------------------------------------------------------------------------------------

test("list dot: our recipe; not hovered renders ColorWidget with the caller's param table unchanged", function()
	setup()
	dot.install(rapi())
	local p = listParam()
	local node = lru.ColorWidget(p)
	eq(node.recipe, "SquareLmpLineDot")
	eq(#colorCalls, 0) -- nothing built until the engine renders our recipe
	local out = render(node)
	eq(out.kind, "BoxLayout")
	eq(#out.children, 1)
	eq(out.children[1].kind, "ColorWidget")
	ok(out.children[1].args[1] == p)
	eq(p.tooltip, "Open Line Window")
	ok(type(hook.mouse) == "function")
end)

test("list dot: Entered sets hovered, Exited clears it; the listener returns false; other events change nothing", function()
	setup()
	dot.install(rapi())
	render(lru.ColorWidget(listParam()))
	eq(hook.mouse({ type = "E" }), false)
	eq(hook.state:old(), true)
	eq(hook.mouse({ type = "P" }), false)
	eq(hook.state:old(), true)
	eq(hook.mouse({ type = "E" }), false)
	eq(hook.state.sets, 1) -- no set when unchanged
	eq(hook.mouse({ type = "X" }), false)
	eq(hook.state:old(), false)
end)

test("list dot: hovered shows the vanilla tooltip, then the line's vehicles and stats; the caller's param stays", function()
	setup()
	dot.install(rapi())
	local p = listParam()
	local node = lru.ColorWidget(p)
	render(node)
	hook.mouse({ type = "E" })
	local out = render(node)
	local q = out.children[1].args[1]
	ok(q ~= p)
	eq(q.tooltip, "Open Line Window\n" .. STATS)
	ok(q.onClick == p.onClick)
	eq(q.entity, 1)
	eq(p.tooltip, "Open Line Window")
	eq(warnings(), 0)
end)

test("list dot: hovered without a vanilla tooltip shows the stats alone", function()
	setup()
	dot.install(rapi())
	local p = listParam()
	p.tooltip = nil
	local node = lru.ColorWidget(p)
	render(node)
	hook.mouse({ type = "E" })
	eq(render(node).children[1].args[1].tooltip, STATS)
end)

test("list dot: a depot or deleted entity, hovered, keeps the caller's param (same table), no warning", function()
	setup()
	dot.install(rapi())
	local p = listParam(77)
	local node = lru.ColorWidget(p)
	render(node)
	hook.mouse({ type = "E" })
	ok(render(node).children[1].args[1] == p)
	eq(warnings(), 0)
end)

test("list dot: stats errors keep the caller's param and log once", function()
	setup()
	dot.install(rapi())
	world.failList = true
	local p = listParam()
	local node = lru.ColorWidget(p)
	render(node)
	hook.mouse({ type = "E" })
	for _i = 1, 3 do ok(render(node).children[1].args[1] == p) end
	eq(warnings("[LineManagerPlus] dot tooltip: stats"), 1)
end)

test("list dot: a broken mouse event is ignored and logged once", function()
	setup()
	dot.install(rapi())
	render(lru.ColorWidget(listParam()))
	eq(hook.mouse(nil), false)
	eq(hook.mouse(nil), false)
	eq(hook.state:old(), false)
	eq(warnings("mouse"), 1)
end)

test("hoveredParam: one stats build per hover render, cached per line", function()
	setup()
	dot.install(rapi())
	local listCalls = 0
	local get = api.engine.system.transportVehicleSystem.getLineVehicles
	api.engine.system.transportVehicleSystem.getLineVehicles = function(l) listCalls = listCalls + 1; return get(l) end
	local p = listParam()
	for _i = 1, 3 do eq(dot.hoveredParam(p).tooltip, "Open Line Window\n" .. STATS) end
	eq(listCalls, 1) -- the 1 s cache of lmp_stats (the fake clock stands still)
end)
