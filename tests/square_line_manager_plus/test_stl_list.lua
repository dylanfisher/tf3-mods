-- Line Manager Plus Send to Line list panel (stl_list.lua) with fake react / builtin / base modules and a fake api.
-- Covers: install (wraps popover_react_util.PopoverWindowContent once, keeps the previous wrapper in the chain, skips a
-- missing field, shims ReplaceRecipe, reads the estimate setting), detection (the Send to Line popover only: other
-- recipes, missing hovered state, missing selection, nil params, a ref argument pass through untouched; an error
-- passes through and is logged once), the swap (every other field kept, the previous function called once), the list
-- recipe (BoxLayout root: the vanilla list with its untouched params, then the panel), and the panel (nothing while no
-- line is hovered; the line's name, vehicles and stats while hovered; the estimate only with the setting On; a deleted
-- line or a stats error: no panel text, logged once; polling sets the state only on a change).

local react, builtin, pop, list, recipeFns, hook, world, prevCalls, RAPI_CALLS, baseRecipes

local function format(s, vars)
	return (s:gsub("{(%w+)}", function(k) return tostring(vars[k]) end))
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	recipeFns, prevCalls, RAPI_CALLS = {}, {}, {}
	hook = { state = nil, step = nil }
	world = {
		lines = { [1] = { 11, 12 } },
		vehicles = { [11] = 100, [12] = 200, [21] = 100 },
		vehicleLine = { [11] = 1, [12] = 1, [21] = 2 },
		names = { [1] = "Bus Line 1" },
	}
	set_global("api", {
		type = {
			ComponentType = { LINE = "LINE", TRANSPORT_VEHICLE = "TV" },
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
		},
		engine = {
			entityExists = function(e) return world.lines[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] and {} or nil end
				if ct == "TV" and world.vehicles[e] then
					return {
						line = world.vehicleLine[e],
						config = { capacities = { 40 }, allCaps = { 40 } }, -- 40 of cargo 0 (index cargo id + 1)
						transportVehicleConfig = { vehicles = { { part = { modelId = world.vehicles[e] } } } },
					}
				end
			end,
			system = { transportVehicleSystem = { getLineVehicles = function(line)
				if world.failList then error("list boom") end
				return world.lines[line]
			end } },
			util = {
				getEntityName = function(e) return world.names[e] end,
				line = {
					calcLineStationThroughput = function() return 4321 end,
					getLineCapacityUsages = function() return { [1] = { capacity = 80 } } end,
				},
			},
		},
		res = { modelRep = { get = function(id)
			return { metadata = { description = { name = id == 100 and "Bus A" or "Bus B" } } }
		end } },
		util = {
			toStringPercentPrecision = function(v) return tostring(math.floor(v * 100)) .. "%" end,
			formatMinutesSeconds = function(s) return string.format("%d:%02d", s // 60, s % 60) end,
		},
	})
	local names = {}
	react = {
		RegisterRecipe = function(name, fn)
			recipeFns[name] = fn
			local r = function(p) return { recipe = name, p = p } end
			names[r] = name
			return r
		end,
		GetRecipeName = function(fn) return names[fn] end,
		useState = function(init)
			if not hook.state then
				local st = { v = init, sets = 0 }
				function st:old() return self.v end
				function st:set(v) self.v = v; self.sets = self.sets + 1 end
				hook.state = st
			end
			return hook.state
		end,
		onStep = function(fn) hook.step = fn end,
	}
	builtin = {
		type = { Orientation = { Vertical = "V", Horizontal = "H" } },
		BoxLayout = function(p) return { kind = "BoxLayout", orientation = p.orientation, children = p.children } end,
		TextView = function(p) return { kind = "TextView", class = p.meta and p.meta.class, text = p.text } end,
	}
	-- the base recipes the test needs: the vanilla list and another popover
	baseRecipes = {
		SendToLineSelection = react.RegisterRecipe("SendToLineSelection", function() return "vanilla list" end),
		TerminalSelection = react.RegisterRecipe("TerminalSelection", function() return "terminals" end),
	}
	pop = {}
	if opts.noField ~= true then
		pop.PopoverWindowContent = function(...)
			prevCalls[#prevCalls + 1] = table.pack(...)
			return { kind = "PopoverWindowContent", args = table.pack(...) }
		end
	end
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/popover_react_util.tl", pop)
	stub_module("::/scripts/lang_util.tl", { format = format, formatInt = function(n) return tostring(n) end })
	stub_module("::/gui/statistics/statistics_react_util.tl", { calculateCargoColumnDataForLine = function()
		return { demand = 80, coverage = 0.25 }
	end })
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", { calculateFrequencySeconds = function() return 90 end })
	list = ug_require "square_line_manager_plus::/line_manager_plus/stl_list.lua"
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

local function messages(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "message" and e.msg:find(text, 1, true) then n = n + 1 end
	end
	return n
end

-- a fake manager state for the hovered line
local function hoverState(v)
	local st = { v = v }
	function st:old() return self.v end
	return st
end

-- the PopoverWindow's param for the Send to Line popover (manager_window.tl:7336-7366 shape)
local function stl(selection)
	return {
		meta = { forceFocusable = true },
		onClose = function() end,
		recipe = baseRecipes.SendToLineSelection,
		params = {
			commonParams = { sendToLineHoveredLineState = hoverState(nil) },
			selection = selection or { 21 },
			sendToLine = function() end,
			onlyVisible = false,
		},
	}
end

-- render the List node (as the engine would), then return { listNode, panelNode }
local function renderList(node)
	eq(node.recipe, "SquareLmpStlList")
	return recipeFns.SquareLmpStlList(node.p)
end

local function renderPanel(node)
	eq(node.recipe, "SquareLmpStlPanel")
	return recipeFns.SquareLmpStlPanel(node.p)
end

local STATS = "Vehicles on this line: 2\n1× Bus A\n1× Bus B\n"
	.. "Capacity: 80  ·  Utilization: 25%  ·  Frequency: 1:30  ·  Rate: 4321"

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps PopoverWindowContent once and logs installed", function()
	setup()
	local orig = pop.PopoverWindowContent
	ok(list.install(rapi(), nil))
	ok(pop.PopoverWindowContent ~= orig)
	local w = pop.PopoverWindowContent
	ok(list.install(rapi(), nil))
	ok(pop.PopoverWindowContent == w)
	eq(messages("[LineManagerPlus] list info: installed"), 1)
	eq(warnings(), 0)
end)

test("install: a missing PopoverWindowContent installs nothing and warns once", function()
	setup({ noField = true })
	eq(list.install(rapi(), nil), false)
	eq(pop.PopoverWindowContent, nil)
	eq(warnings("[LineManagerPlus] list info: install"), 1)
end)

test("install: a missing react.GetRecipeName installs nothing", function()
	setup()
	local orig = pop.PopoverWindowContent
	react.GetRecipeName = nil
	eq(list.install(rapi(), nil), false)
	ok(pop.PopoverWindowContent == orig)
	eq(warnings("install"), 1)
end)

test("install: keeps the previous wrapper in the chain (called once per render)", function()
	setup()
	local prev, chained = pop.PopoverWindowContent, 0
	pop.PopoverWindowContent = function(...) chained = chained + 1; return prev(...) end
	list.install(rapi(), nil)
	pop.PopoverWindowContent(stl())
	eq(chained, 1)
	eq(#prevCalls, 1)
end)

test("install: a later ReplaceRecipe of our wrapper gets the wrapped recipe; others pass unchanged", function()
	setup()
	local orig = pop.PopoverWindowContent
	local api_ = rapi()
	list.install(api_, nil)
	local other = function() end
	api_.ReplaceRecipe(pop.PopoverWindowContent, "R1")
	api_.ReplaceRecipe(other, "R2")
	ok(RAPI_CALLS[1].orig == orig)
	eq(RAPI_CALLS[1].repl, "R1")
	ok(RAPI_CALLS[2].orig == other)
	setup()
	ok(list.install(nil, nil)) -- no replacement api: still installs
end)

test("install: estimate Off is logged", function()
	setup()
	list.install(rapi(), { send_to_line_estimate = 1 })
	eq(messages("installed (estimate off: mod setting)"), 1)
end)

-- detection and swap -------------------------------------------------------------------------------------------------

test("wrapper: other popovers and malformed params go to the previous function untouched", function()
	setup()
	list.install(rapi(), nil)
	local term = stl()
	term.recipe = baseRecipes.TerminalSelection
	local noState = stl()
	noState.params.commonParams = {}
	local noSel = stl()
	noSel.params.selection = nil
	local noParams = stl()
	noParams.params = nil
	local cases = {
		{ term }, { noState }, { noSel }, { noParams }, { "ref", stl() }, { "notatable" }, { { params = {} } },
	}
	for i, args in ipairs(cases) do
		local node = pop.PopoverWindowContent(table.unpack(args))
		eq(node.kind, "PopoverWindowContent", "case " .. i)
		eq(node.args.n, #args)
		for j = 1, #args do ok(node.args[j] == args[j], "case " .. i) end
	end
	eq(warnings(), 0)
end)

test("wrapper: the Send to Line popover gets our recipe; every other field kept; previous called once", function()
	setup()
	list.install(rapi(), nil)
	local p = stl()
	local node = pop.PopoverWindowContent(p)
	eq(#prevCalls, 1)
	local q = node.args[1]
	ok(q ~= p)
	eq(node.args.n, 1)
	eq(react.GetRecipeName(q.recipe), "SquareLmpStlList")
	ok(q.recipe == list.List)
	ok(q.params.inner == p.recipe)
	ok(q.params.innerParams == p.params)
	ok(q.onClose == p.onClose)
	ok(q.meta == p.meta)
	ok(p.recipe == baseRecipes.SendToLineSelection) -- the caller's table unchanged
end)

test("wrapper: an error while deciding passes through untouched and warns once", function()
	setup()
	list.install(rapi(), nil)
	react.GetRecipeName = function() error("no names") end
	for _i = 1, 3 do
		local p = stl()
		local node = pop.PopoverWindowContent(p)
		ok(node.args[1] == p)
	end
	eq(warnings("[LineManagerPlus] list info: swap"), 1)
end)

-- list and panel -----------------------------------------------------------------------------------------------------

local function swapped(selection, params)
	list.install(rapi(), params)
	local p = stl(selection)
	local q = pop.PopoverWindowContent(p).args[1]
	return p, q
end

test("list: horizontal BoxLayout root, the vanilla list with its untouched params first, then the panel", function()
	setup()
	local p, q = swapped()
	local out = renderList(q.recipe(q.params))
	eq(out.kind, "BoxLayout")
	eq(out.orientation, "H")
	eq(#out.children, 2)
	eq(out.children[1].recipe, "SendToLineSelection")
	ok(out.children[1].p == p.params)
	eq(out.children[2].recipe, "SquareLmpStlPanel")
	ok(out.children[2].p.commonParams == p.params.commonParams)
	ok(out.children[2].p.selection == p.params.selection)
end)

test("panel: nothing hovered renders an empty BoxLayout and builds no stats", function()
	setup()
	local listCalls = 0
	local get = api.engine.system.transportVehicleSystem.getLineVehicles
	api.engine.system.transportVehicleSystem.getLineVehicles = function(l) listCalls = listCalls + 1; return get(l) end
	local _p, q = swapped()
	local panel = renderList(q.recipe(q.params)).children[2]
	local out = renderPanel(panel)
	eq(out.kind, "BoxLayout")
	eq(#out.children, 0)
	hook.step()
	hook.step()
	eq(hook.state.sets, 0) -- still nil: no set, no re-render
	eq(listCalls, 0)
end)

test("panel: a hovered line shows its name, vehicles and stats with the estimate (setting On)", function()
	setup()
	local p, q = swapped({ 21 })
	local panel = renderList(q.recipe(q.params)).children[2]
	renderPanel(panel)
	p.params.commonParams.sendToLineHoveredLineState.v = 1
	hook.step()
	eq(hook.state:old(), 1)
	hook.step()
	eq(hook.state.sets, 1) -- unchanged: no second set
	local out = renderPanel(panel)
	eq(#out.children, 1)
	local tv = out.children[1]
	eq(tv.kind, "TextView")
	eq(tv.class, list.PANEL_CLASS)
	ok(tv.text:find("^Bus Line 1\nVehicles on this line: 2\n1× Bus A\n1× Bus B\n") ~= nil, tv.text)
	-- vehicle 21 (on line 2) adds its 40: capacity 80 -> 120, frequency 90 s * 2/3, rate 4321 * 120/80
	ok(tv.text:find("Capacity: 80 → ~120", 1, true) ~= nil, tv.text)
	ok(tv.text:find("Frequency: 1:30 → ~1:00", 1, true) ~= nil, tv.text)
	ok(tv.text:find("Rate: 4321 → ~6482", 1, true) ~= nil, tv.text)
	-- unhover: the panel goes away
	p.params.commonParams.sendToLineHoveredLineState.v = nil
	hook.step()
	eq(#renderPanel(panel).children, 0)
	eq(warnings(), 0)
end)

test("panel: with the estimate setting Off the same text as the plain stats", function()
	setup()
	local p, q = swapped({ 21 }, { send_to_line_estimate = 1 })
	local panel = renderList(q.recipe(q.params)).children[2]
	renderPanel(panel)
	p.params.commonParams.sendToLineHoveredLineState.v = 1
	hook.step()
	eq(renderPanel(panel).children[1].text, "Bus Line 1\n" .. STATS)
end)

test("panel: a line without a name shows the stats alone", function()
	setup()
	world.names[1] = nil
	eq(list.panelText(1, nil), STATS)
end)

test("panel: a deleted line or a depot shows nothing, no warning", function()
	setup()
	local p, q = swapped()
	local panel = renderList(q.recipe(q.params)).children[2]
	renderPanel(panel)
	p.params.commonParams.sendToLineHoveredLineState.v = 77
	hook.step()
	eq(#renderPanel(panel).children, 0)
	eq(warnings(), 0)
end)

test("panel: a stats error shows nothing and logs once; a broken hover state logs once", function()
	setup()
	local p, q = swapped()
	local panel = renderList(q.recipe(q.params)).children[2]
	renderPanel(panel)
	world.failList = true
	p.params.commonParams.sendToLineHoveredLineState.v = 1
	hook.step()
	for _i = 1, 3 do eq(#renderPanel(panel).children, 0) end
	eq(warnings("[LineManagerPlus] list info: stats"), 1)
	p.params.commonParams.sendToLineHoveredLineState = {} -- no :old()
	hook.step()
	hook.step()
	eq(warnings("[LineManagerPlus] list info: hover"), 1)
end)

test("panelText: the cached stats list is not changed (name added to a copy)", function()
	setup()
	eq(list.panelText(1, nil), "Bus Line 1\n" .. STATS)
	eq(list.panelText(1, nil), "Bus Line 1\n" .. STATS) -- same text from the 1 s cache, no name twice
end)
