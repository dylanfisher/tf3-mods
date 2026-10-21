-- The minimap window (minimap_hud.script.tl MinimapWindow) on a platform whose base react lacks the gamepad hooks
-- (PS5 report 2026-10-19, Smart Lanes: the console build ships its own base GUI scripts, which lack functions the PC
-- copies have; docs/findings/gui.md "Base GUI modules differ by platform"). Rendered with and without
-- react.useInputAction / react.iaHandler: no error, and the back-button handler only where both exist.

local recipes, inputActions

-- Fake react: every recipe is recorded by name; a recipe call returns a plain node (never rendered here).
local function fakeReact(gamepad)
	local r = {
		RegisterRecipe = function(name, fn)
			recipes[name] = fn
			return function(p) return { recipe = name, p = p } end
		end,
		RegisterWrapperRecipe = function(name, _base, fn)
			recipes[name] = fn
			return function(p) return { recipe = name, p = p } end
		end,
		RegisterPluginRecipe = function(_ext, name, fn)
			recipes[name] = fn
			return name
		end,
		useState = function(v) return { old = function() return v end, set = function() end } end,
		useRef = function(v) return { get = function() return v end, set = function(_, x) v = x end } end,
		useRefLazy = function(f) local v = f() return { get = function() return v end, set = function(_, x) v = x end } end,
		useSelfRef = function() return { get = function() return nil end } end,
		onMount = function() end,
		onUnmount = function() end,
		onStep = function() end,
		onStepTimer = function() end,
		onEvent = function() end,
		onMouseEvent = function() end,
		setMouseTransparent = function() end,
	}
	if gamepad then
		r.useInputAction = function(name, h) inputActions[name] = h end
		r.iaHandler = function(fn, enabled) return { action = fn, enabled = enabled } end
	end
	return r
end

local function load(gamepad)
	recipes, inputActions = {}, {}
	reset_modules()
	clear_logs()
	local builtin = setmetatable({
		type = setmetatable({}, { __index = function() return setmetatable({}, { __index = function(_, k) return k end }) end }),
	}, { __index = function(_t, k) return function(p) return { kind = k, p = p or {} } end end })
	stub_module("::/gui/main/react.lua", fakeReact(gamepad))
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/main_mod_button_area.tl", { MainModButtonAreaExtension = "EXT" })
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return nil end })
	stub_module("::/scripts/table_util.tl", { deepEquals = function(a, b) return a == b end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { style = t } end })
	set_global("api", {
		type = { Clock = { new = function() return { getTime = function() return 0 end } end } },
		engine = { config = { getModParams = function() return { square_better_minimap = {} } end } },
		gui = {
			inputAction = { InputActionState = { Enabled = "Enabled", Disabled = "Disabled" } },
			react = { params = { builtin = { Window = { new = function() return {} end } } } },
		},
	})
	ug_require "square_better_minimap::/minimap/gui/minimap_hud.script.tl"
	ok(recipes.MinimapWindow ~= nil, "MinimapWindow registered")
	return recipes.MinimapWindow({ initialX = 1, initialY = 0.1 })
end

test("window renders without react.useInputAction / iaHandler (PS5 report 2026-10-19): no error, no back handler", function()
	local win = load(false)
	eq(win.kind, "Window")
	eq(win.p.id, "squareminimap.window")
	eq(next(inputActions), nil, "no handler where the platform has no hook")
end)

test("window renders with the gamepad hooks: a back-button handler, Enabled while unpinned", function()
	local win = load(true)
	eq(win.kind, "Window")
	local h = inputActions.IA_MENU_BACK
	ok(h ~= nil, "a back-button handler")
	eq(h.enabled(), "Enabled")
end)
