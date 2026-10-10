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
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return nil end })
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
