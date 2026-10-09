-- bulk_bulldozer.script: getDefinition builds the toolbar (radius, [Bulldoze] [Clear] buttons,
-- status chip, 6 filter CheckBoxes) and the onChangeFns fire the react events the recipe listens to.

local fired = {}
-- A recipe is a callable table here: calling it gives { recipe = name, param = p }.
local recipes = {}
stub_module("::/gui/main/react.lua", {
	RegisterRecipe = function(name, fn)
		local r = setmetatable({ name = name, fn = fn }, {
			__call = function(_self, p) return { recipe = name, param = p } end,
		})
		recipes[name] = r
		return r
	end,
})
local function node(kind) return function(p) return { builtin = kind, param = p } end end
stub_module("::/gui/main/builtin.lua", {
	BoxLayout = node("BoxLayout"),
	TextView = node("TextView"),
	type = { Orientation = { Horizontal = "Horizontal", Vertical = "Vertical" } },
})
stub_module("::/gui/construction/construction_react_util.tl", {})
set_global("resolve", function(p) return "resolved:" .. p end)
set_global("api", {
	type = { enum = {
		ScriptParamType = { Slider = "Slider", Button = "Button", CheckBox = "CheckBox" },
		ScriptParamLocation = { Toolbar = "Toolbar" },
		ScriptParamDisplayMode = { Horizontal = "Horizontal" },
	} },
	gui = { fireReactEvent = function(name, payload) fired[#fired + 1] = { name = name, payload = payload } end },
})

local script = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bulk_bulldozer.script.tl"
local sel = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl"

local def = script.getDefinition("bulk_bulldozer.res", nil, {})

local function param(key)
	for _, p in ipairs(def.params) do if p.key == key then return p end end
end

test("toolbar: radius, Bulldoze + Clear, status, 6 filter CheckBoxes with PLAN defaults", function()
	eq(#def.params, 10)
	eq(def.params[1].key, "bulk_bulldozer_radius")
	eq(def.params[2].key, "bulk_bulldozer_bulldoze")
	eq(def.params[3].key, "bulk_bulldozer_clear")
	eq(def.params[4].key, "bulk_bulldozer_status")
	for _, p in ipairs(def.params) do
		if p.key == "bulk_bulldozer_mode" then error("Paint/Stamp mode button must be gone") end
	end
	local defaults = sel.defaultFilters()
	local expect = {
		{ "bulk_bulldozer_f_roads", "roads" },
		{ "bulk_bulldozer_f_tracks", "tracks" },
		{ "bulk_bulldozer_f_stations", "stations" },
		{ "bulk_bulldozer_f_assets", "assets" },
		{ "bulk_bulldozer_f_town_buildings", "townBuildings" },
		{ "bulk_bulldozer_f_underground", "underground" },
	}
	for i, kv in ipairs(expect) do
		local p = def.params[i + 4]
		eq(p.key, kv[1])
		eq(p.uiType, "CheckBox")
		eq(p.location, "Toolbar")
		eq(#p.values, 2)
		eq(p.numbers, nil, "CheckBox has no numbers")
		eq(p.defaultIndex, defaults[kv[2]] and 2 or 1, kv[1] .. " default")
		eq(p.checkEnabledFn({}), "Enabled")
		eq(p.group, "bulk_bulldozer_filters")
	end
end)

test("filter onChangeFn fires the event with field and on/off", function()
	fired = {}
	local p = param("bulk_bulldozer_f_tracks")
	p.onChangeFn(2, nil, 1)
	p.onChangeFn(1, nil, 2)
	p.onChangeFn(1, nil, 1)   -- unchanged: no event
	eq(#fired, 2)
	eq(fired[1].name, "BulkBulldozer.filter")
	eq(fired[1].payload, { field = "tracks", on = true, shown = { tracks = true } })
	eq(fired[2].payload, { field = "tracks", on = false, shown = { tracks = false } })
	-- With the menu API: category and every filter the toolbar certainly shows ride along.
	fired = {}
	local menuApi = {
		getCategory = function() return 3 end,
		getCurrentParams = function() return { bulk_bulldozer_f_roads = 1, bulk_bulldozer_f_tracks = 1,
			bulk_bulldozer_f_assets = 7 } end,
	}
	p.onChangeFn(2, menuApi, 1)
	eq(fired[1].payload, { field = "tracks", on = true, category = "3",
		shown = { roads = false, tracks = true } }, "the toggled value wins; 7 is unknown")
	-- A menu API that throws still fires the plain event.
	fired = {}
	p.onChangeFn(1, { getCategory = function() error("x") end, getCurrentParams = function() error("y") end }, 2)
	eq(fired[1].payload, { field = "tracks", on = false, shown = { tracks = false } })
end)

test("checkEnabledFn: filters only record, the status chip fires the shown values", function()
	fired = {}
	local shownParams = { bulk_bulldozer_f_roads = 1, bulk_bulldozer_f_tracks = 2, bulk_bulldozer_radius = 20 }
	eq(param("bulk_bulldozer_f_roads").checkEnabledFn(shownParams), "Enabled")
	eq(#fired, 0)
	eq(param("bulk_bulldozer_status").checkEnabledFn(shownParams), "Disabled")
	eq(#fired, 1)
	eq(fired[1].name, "BulkBulldozer.shown")
	eq(fired[1].payload, { values = { roads = false, tracks = true } })
	-- No filter keys (another definition's params): nothing fired.
	fired = {}
	param("bulk_bulldozer_status").checkEnabledFn({})
	eq(#fired, 0)
end)

local function buttonCase(key, label, event)
	local p = param(key)
	eq(p.uiType, "Button")
	eq(p.location, "Toolbar")
	eq(#p.values, 1)
	eq(p.defaultIndex, 1)
	eq(p.hideLabel, true)
	eq(p.group, "bulk_bulldozer_actions", "same group + hideLabel = one row")
	eq(p.checkEnabledFn({}), "Enabled")
	-- Label wrapped in a BoxLayout (not a direct TextView child of the button: 50 px CSS clip).
	local content = p.makeCompactButtonFn(1)
	eq(content.builtin, "BoxLayout")
	eq(content.param.children[1].builtin, "TextView")
	eq(content.param.children[1].param.text, label)
	fired = {}
	p.onChangeFn(1, nil, 1)   -- same value: still a click
	p.onChangeFn(1, nil, 1)
	eq(#fired, 2)
	eq(fired[1].name, event)
end

test("Bulldoze button: one-value toolbar Button in the actions row, fires on every click", function()
	buttonCase("bulk_bulldozer_bulldoze", "Bulldoze", "BulkBulldozer.bulldoze")
end)

test("Clear button: next to Bulldoze, fires the clear event on every click", function()
	buttonCase("bulk_bulldozer_clear", "Clear", "BulkBulldozer.clear")
	eq(def.params[2].group, def.params[3].group)
end)

test("status chip: disabled one-value Button whose content is the status recipe", function()
	local p = param("bulk_bulldozer_status")
	eq(p.uiType, "Button")
	eq(p.location, "Toolbar")
	eq(p.hideLabel, true)
	eq(p.group, nil, "no group: no separator between the buttons and the chip")
	eq(p.checkEnabledFn({}), "Disabled")
	eq(p.makeCompactButtonFn(1).recipe, "BulkBulldozerStatus")
	fired = {}
	p.onChangeFn(1, nil, 1)
	eq(#fired, 0, "the chip fires nothing")
end)

-- Minimal react hooks for running one recipe function: states/refs by call order, handlers kept.
local function fakeReact()
	local h = { states = {}, refs = {}, events = {}, steps = {} }
	h.react = {
		useState = function(init)
			local st = { v = init }
			function st:old() return self.v end
			function st:set(v) self.v = v; h.dirty = true end
			h.states[#h.states + 1] = st
			return st
		end,
		useRef = function(init)
			local r = { v = init }
			function r:get() return self.v end
			function r:set(v) self.v = v end
			h.refs[#h.refs + 1] = r
			return r
		end,
		onEvent = function(name, fn) h.events[name] = fn end,
		onStep = function(fn) h.steps[#h.steps + 1] = fn end,
	}
	return h
end

test("status recipe: renders two lines and takes EV_STATUS updates", function()
	-- Re-load the script with a fake react that can run hooks.
	reset_modules()
	local h = fakeReact()
	local reg = {}
	h.react.RegisterRecipe = function(name, fn) reg[name] = fn; return setmetatable({ name = name }, { __call = function(_s, p) return { recipe = name, param = p } end }) end
	stub_module("::/gui/main/react.lua", h.react)
	stub_module("::/gui/main/builtin.lua", {
		BoxLayout = node("BoxLayout"),
		TextView = node("TextView"),
		type = { Orientation = { Horizontal = "Horizontal", Vertical = "Vertical" } },
	})
	stub_module("::/gui/construction/construction_react_util.tl", {})
	ug_require "square_bulk_bulldozer::/bulk_bulldozer/bulk_bulldozer.script.tl"
	local render = reg["BulkBulldozerStatus"]
	ok(render ~= nil)
	local tree = render({})
	eq(tree.builtin, "BoxLayout")
	eq(tree.param.orientation, "Vertical")
	eq(tree.param.children[1].param.text, "Nothing selected")
	eq(tree.param.children[2].param.text, "Paint with the left mouse button")
	ok(h.events["BulkBulldozer.status"] ~= nil, "listens to the status event")
	h.events["BulkBulldozer.status"]("BulkBulldozer.status", { head = "12 selected · $34,500", detail = "8 roads", version = 1 })
	eq(h.states[1]:old(), { head = "12 selected · $34,500", detail = "8 roads" })
	-- The step poll only acts on a new g_status version (none published here): no overwrite.
	for _, f in ipairs(h.steps) do f() end
	eq(h.states[1]:old().head, "12 selected · $34,500")
end)

test("menu entries and custom action unchanged", function()
	eq(def.action, "ACTION_CUSTOM")
	eq(def.customAction.recipe.name, "BulkBulldozerAction")
	eq(def.menuCategory.categories[1], { category = "roads_tools", order = 5 })
	eq(def.menuCategory.categories[2], { category = "rail_tools", order = 5 })
end)
