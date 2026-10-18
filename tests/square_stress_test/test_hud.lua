-- stress_hud.script.tl: the Probe tab exists only with the load-time param "Show probe tab
-- (developers)", and stress_probes.tl is never required without it. React and builtin are stubbed:
-- recipes are captured by name and widgets come back as plain { _w = <widget name>, ... } tables.

local recipes
local probeRequires
local realPcall = pcall

local function auto()
	return setmetatable({}, { __index = function(t, k) local v = auto() rawset(t, k, v) return v end })
end

local function stateOf(v)
	local s = { v = v }
	function s:old() return self.v end
	function s:set(n) self.v = n end
	function s:hasExpired() return false end
	return s
end

local function refOf(v)
	local r = { v = v }
	function r:get() return self.v end
	function r:set(n) self.v = n end
	return r
end

local function stubs()
	recipes = {}
	local react = {
		RegisterRecipe = function(name, fn) recipes[name] = fn return fn end,
		RegisterWrapperRecipe = function(name, _base, fn) recipes[name] = fn return fn end,
		RegisterPluginRecipe = function(_ext, name, fn) recipes[name] = fn return fn end,
		useStateLazy = function(fn) return stateOf(fn()) end,
		useState = function(v) return stateOf(v) end,
		useRef = function(v) return refOf(v) end,
		useRefLazy = function(fn) return refOf(fn()) end,
		onStep = function(_fn) end,
	}
	local builtin = setmetatable({ type = auto() }, { __index = function(_, k)
		return function(params) params = params or {} params._w = k return params end
	end })
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/main_mod_button_area.tl", { MainModButtonAreaExtension = "ext" })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return t end })
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return nil end })
	stub_module("::/gui/menu/dialog_react_util.tl", { DialogWindow = "DialogWindow" })
	probeRequires = 0
	stub_module("square_stress_test::/stress/gui/stress_probes.tl",
		{ list = { { id = "p1", label = "1", tooltip = "", run = function() end } } })
	-- The HUD script requires the probe module through pcall(ug_require, path): count those calls.
	set_global("pcall", function(f, ...)
		if select(1, ...) == "square_stress_test::/stress/gui/stress_probes.tl" then probeRequires = probeRequires + 1 end
		return realPcall(f, ...)
	end)
end

local function fakeApi(probeParam)
	return {
		type = auto(),
		engine = {
			config = { getModParams = function()
				return { [""] = {}, square_stress_test = { show_probe_tab = probeParam } }
			end },
		},
	}
end

local function tabsOf(tree)
	local found
	local seen = {}
	local function walk(n)
		if type(n) ~= "table" or found or seen[n] then return end
		seen[n] = true
		if rawget(n, "_w") == "TabWidget" then found = n.tabs return end
		for _, c in pairs(n) do walk(c) end
	end
	walk(tree)
	return found
end

local function render(probeParam)
	reset_modules()
	clear_logs()
	stubs()
	set_global("api", fakeApi(probeParam))
	ug_require "square_stress_test::/stress/gui/stress_hud.script.tl"
	return tabsOf(recipes.SquareStressContent())
end

test("probe tab off (default): three tabs, the probe module is never used", function()
	local tabs = render(1)
	eq(#tabs, 3)
	local keys = {}
	for i, t in ipairs(tabs) do keys[i] = t.localKey end
	eq(keys, { "sqst_tab_game", "sqst_tab_towns", "sqst_tab_traffic" })
	eq(probeRequires, 0)
	eq(#render(nil), 3)
end)

test("probe tab on: a fourth tab, Probe", function()
	local tabs = render(2)
	eq(#tabs, 4)
	eq(tabs[4].localKey, "sqst_tab_probe")
	eq(probeRequires, 1)
end)

test("getModParams failing hides the tab instead of throwing", function()
	reset_modules()
	stubs()
	set_global("api", { type = auto(), engine = { config = { getModParams = function() error("no engine") end } } })
	ug_require "square_stress_test::/stress/gui/stress_hud.script.tl"
	eq(#tabsOf(recipes.SquareStressContent()), 3)
end)

---------------------------------------------------------------------------
-- Confirm dialogs: Remove all roads / Remove towns act only after the dialog's Remove choice.

local function findButton(tree, tooltipStart)
	local found
	local seen = {}
	local function walk(n)
		if type(n) ~= "table" or found or seen[n] then return end
		seen[n] = true
		if rawget(n, "_w") == "Button" and type(n.meta) == "table" and type(n.meta.tooltip) == "string"
				and n.meta.tooltip:sub(1, #tooltipStart) == tooltipStart then
			found = n
			return
		end
		for _, c in pairs(n) do walk(c) end
	end
	walk(tree)
	return found
end

local function renderWithDialogs(prepApi)
	reset_modules()
	clear_logs()
	stubs()
	local wa = { windows = {}, removed = 0 }
	function wa.addSingletonWindow(recipe, params) wa.windows[#wa.windows + 1] = { recipe = recipe, params = params } end
	function wa.removeAllWindows(_recipe) wa.removed = wa.removed + 1 end
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return wa end })
	local calls = { removeAll = 0 }
	stub_module("square_stress_test::/stress/gui/stress_roads.tl", {
		count = function() return 412, 6 end,
		removeAll = function() calls.removeAll = calls.removeAll + 1 end,
	})
	local fake = fakeApi(1)
	if prepApi then prepApi(fake) end
	set_global("api", fake)
	ug_require "square_stress_test::/stress/gui/stress_hud.script.tl"
	-- Render with the Towns tab selected (only the selected tab's content is built).
	local react = ug_require "::/gui/main/react.lua"
	local useState = react.useState
	react.useState = function(v) return useState(v == "game" and "towns" or v) end
	return recipes.SquareStressContent(), wa, calls
end

test("Remove all roads asks first: Cancel does nothing, Remove runs it once", function()
	local tree, wa, calls = renderWithDialogs()
	local b = findButton(tree, "Remove every street")
	ok(b ~= nil, "Remove all roads button")
	b.onClick()
	eq(calls.removeAll, 0) -- nothing before the dialog's choice
	eq(#wa.windows, 1)
	local d = wa.windows[1]
	eq(d.recipe, "DialogWindow")
	eq(d.params.windowTitle, "Remove all roads")
	ok(d.params.displayText:find("Remove all 412 street pieces", 1, true), d.params.displayText)
	ok(d.params.displayText:find("6 that belong to stations", 1, true), d.params.displayText)
	eq(d.params.choices[2].text, "Cancel")
	eq(d.params.onBackChoiceIndex, 2)
	d.params.choices[2].onClick()
	eq(calls.removeAll, 0)
	d.params.choices[1].onClick()
	eq(calls.removeAll, 1)
	d.params.onClose()
	eq(wa.removed, 1)
end)

test("warnings: rt.warn opens one OK dialog; more wait and are shown together after it closes", function()
	local _, wa = renderWithDialogs(function(fake)
		fake.gui = fake.gui or {}
		fake.gui.game = { isMapEditor = function() return false end }
		rawset(fake.type, "Vec4f", { new = function(a, b, c, d) return { a, b, c, d } end })
	end)
	local react = ug_require "::/gui/main/react.lua"
	local steps = {}
	react.onStep = function(fn) steps[#steps + 1] = fn end
	recipes.SquareStressHudPlugin()
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	local function step() for _, fn in ipairs(steps) do fn() end end
	step()
	eq(#wa.windows, 0, "nothing to show")
	rt.warn("Not enough space", "Grid B2 is water.")
	step()
	eq(#wa.windows, 1)
	local d = wa.windows[1].params
	eq(d.windowTitle, "Not enough space")
	eq(d.displayText, "Grid B2 is water.")
	eq(#d.choices, 1)
	eq(d.choices[1].text, "OK")
	rt.warn("Busy", "a: b is running.")
	rt.warn("Junction test", "2 refused.")
	step()
	eq(#wa.windows, 1, "waits while the dialog is open")
	d.onClose()
	step()
	eq(#wa.windows, 2)
	local d2 = wa.windows[2].params
	eq(d2.windowTitle, "Stress Test")
	eq(d2.displayText, "Busy: a: b is running.\n\nJunction test: 2 refused.")
	eq(#rt.warnings, 0)
end)

test("Remove towns asks first and lists the towns", function()
	local tree, wa = renderWithDialogs()
	local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl"
	local removed
	towns.removePlan = function() return { 5, 6 }, { "Grid A1", "Grid A2" } end
	towns.removeTowns = function(list) removed = list end
	local b = findButton(tree, "Destroy the target town")
	ok(b ~= nil, "Remove towns button")
	b.onClick()
	eq(removed, nil)
	local d = wa.windows[1]
	ok(d.params.displayText:find("Remove 2 towns", 1, true), d.params.displayText)
	ok(d.params.displayText:find("Grid A1, Grid A2", 1, true), d.params.displayText)
	d.params.choices[1].onClick()
	eq(removed, { 5, 6 })
end)

test("Junction test: a hint without Roundabouts & Interchanges, the form with it", function()
	local function texts(tree)
		local out = {}
		local seen = {}
		local function walk(n)
			if type(n) ~= "table" or seen[n] then return end
			seen[n] = true
			if rawget(n, "_w") == "TextView" and type(n.text) == "string" then out[#out + 1] = n.text end
			for _, c in pairs(n) do walk(c) end
		end
		walk(tree)
		return table.concat(out, "\n")
	end
	local tree = renderWithDialogs()
	ok(texts(tree):find("Junction test: enable Roundabouts & Interchanges", 1, true))
	eq(findButton(tree, "Create a grid of test towns"), nil)
	-- the Crossing test needs only this mod
	ok(findButton(tree, "Create 4 towns around the map centre") ~= nil, "Crossing test button")
	ok(texts(tree):find("Build crossing test", 1, true), texts(tree))
	eq(findButton(tree, "Fill the map with groups"), nil, "no Showcase without it")
	tree = renderWithDialogs(function(fake)
		fake.res = { constructionRep = { find = function(name) return name:find("^square_roundabouts::/") and 3 or -1 end } }
	end)
	local b = findButton(tree, "Create a grid of test towns")
	ok(b ~= nil, "Junction test button")
	ok(texts(tree):find("Build 10 junctions, 2 km", 1, true), texts(tree))
	-- the Showcase is one button and a short description: no options (user 2026-10-12)
	ok(findButton(tree, "Fill the map with groups") ~= nil, "Showcase button")
	local all = texts(tree)
	ok(all:find("Build showcase", 1, true), all)
	ok(not all:find("New seed", 1, true), "no Seed choice")
	ok(not all:find("Same as last", 1, true), "no Seed choice")
	local from = all:find("Build showcase", 1, true)
	local to = all:find("\nRemove towns\n", from, true) or #all
	local section = all:sub(from, to)
	for _, word in ipairs({ "Size", "Lights", "Traffic", "Seed" }) do
		ok(not section:find("\n" .. word .. "\n", 1, true), "no " .. word .. " row in the Showcase section")
	end
	ok(section:find("Keep balance on", 1, true), section)
end)

test("Lights showcase: one button (every shape, no options) and a short description; shown without Roundabouts & Interchanges too", function()
	local function texts(tree)
		local out = {}
		local seen = {}
		local function walk(n)
			if type(n) ~= "table" or seen[n] then return end
			seen[n] = true
			if rawget(n, "_w") == "TextView" and type(n.text) == "string" then out[#out + 1] = n.text end
			for _, c in pairs(n) do walk(c) end
		end
		walk(tree)
		return table.concat(out, "\n")
	end
	for _, withRb in ipairs({ false, true }) do
		local tree = renderWithDialogs(withRb and function(fake)
			fake.res = { constructionRep = { find = function(name) return name:find("^square_roundabouts::/") and 3 or -1 end } }
		end or nil)
		local b = findButton(tree, "Fill the map with every lit junction shape")
		ok(b ~= nil, "Lights showcase button")
		-- the light plans A/B: a second button in the section (SHOWCASE.md "Light plans A/B")
		ok(findButton(tree, "A focused light-plan A/B") ~= nil, "Light plans A/B button")
		local all = texts(tree)
		ok(all:find("\nLights showcase\n", 1, true), all)
		local from = all:find("Build lights showcase", 1, true)
		ok(from ~= nil, all)
		local to = all:find("\nRemove towns\n", from, true) or #all
		local section = all:sub(from, to)
		for _, word in ipairs({ "Size", "Lights", "Traffic", "Seed" }) do
			ok(not section:find("\n" .. word .. "\n", 1, true), "no " .. word .. " row in the Lights showcase section")
		end
		ok(section:find("Keep balance on", 1, true) and section:find("grow once after the links, to about 400 people each", 1, true) and section:find("No bus lines", 1, true)
			and section:find("2x2 X, 3x3 X, 3x2 X", 1, true), section)
		ok(section:find("Build light plans A/B", 1, true) and section:find("timing kept adjusted", 1, true) and section:find("about 600 people", 1, true)
			and section:find("about 150 (\"small\")", 1, true) and section:find("about 40 (\"tiny\")", 1, true) and section:find("90 game minutes", 1, true), section)
		-- City lights at scale: the bench's city run (BENCH.md "City lights at scale")
		ok(section:find("\nCity lights at scale\n", 1, true), section)
		ok(findButton(tree, "City lights at scale: automatic") ~= nil, "City lights button")
		ok(section:find("6 big grid towns", 1, true) and section:find("15 game minutes as they are", 1, true)
			and section:find("then 90 more", 1, true) and section:find("Debug: performance log On", 1, true), section)
		-- its options (BENCH.md "Funnel layouts"): Layout / Baseline choices, Busy / Swap roles checkboxes
		ok(section:find("\nLayout\nPlain grid\nHourglass\nHoles\n", 1, true) and section:find("\nBaseline\n15 min\n30 min\n", 1, true)
			and section:find("81 lit crossings each", 1, true) and section:find("Swap roles: run again with the same seed", 1, true), section)
		-- Auto re-time: all lit junctions / Clear (Smart Lanes' SmartLanes.auto, whole map)
		ok(section:find("\nAuto re-time\n", 1, true), section)
		ok(findButton(tree, "Smart Lanes keeps the timing of every lit junction") ~= nil, "Auto re-time all button")
		ok(findButton(tree, "Stops Smart Lanes' automatic re-timing") ~= nil, "Auto re-time clear button")
	end
end)

test("HUD button: an icon by default (also without the param), the Debug text with hudButtonStyle Text", function()
	for _, style in ipairs({ 2, false, 1 }) do
		local fake = fakeApi(1)
		local params = fake.engine.config.getModParams()
		params.square_stress_test.hudButtonStyle = style or nil
		fake.engine.config.getModParams = function() return params end
		fake.gui = { game = { isMapEditor = function() return false end } }
		rawset(fake.type, "Vec4f", { new = function(a, b, c, d) return { a, b, c, d } end })
		reset_modules()
		stubs()
		set_global("api", fake)
		ug_require "square_stress_test::/stress/gui/stress_hud.script.tl"
		local root = recipes.SquareStressHudPlugin()
		local button = root.children[1]
		if style == 1 then
			eq(button.meta.class, "sqst-hud-button")
		else
			eq(button._w, "ToggleButton")
			eq(button.meta.class, "sqst-hud-icon-button")
			eq(button.meta.styleSheet.backgroundColor1, nil)
			eq(button.meta.styleSheet.padding, { 8, 8, 8, 8 })
			eq(button.value, 0)
			eq(button.content.path, "square_stress_test::/stress/gui/gauge.tga")
			eq(button.content.meta.styleSheet.size, { 24, 24 })
		end
	end
end)
