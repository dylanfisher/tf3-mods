-- flows_window.script.tl with SQPERF: the wrapped recipes / handlers still return and do the same
-- thing, the onStepTimer poll is timed like the rest (Clock is safe on its worker thread,
-- docs/findings.md "Timers and threads in GUI contexts") and makes no api.gui call (the window
-- visibility is read in react.onStep on the Main Thread), and the 30 s summary (Debug:
-- performance log On) lists every section. Base GUI modules and the engine API are faked; the
-- engine world is empty (the model has its own tests in test_model.lua).
-- run_tests: no-split (each test reloads the module; the fakes record per test)

local MOD = "square_industry_flows"
local PATH = MOD .. "::/industry_flows/gui/flows_window.script.tl"

-- Fake GUI tree: every widget is { w = name, p = param }.
local function widget(name)
	return function(p) return { w = name, p = p } end
end

local function class(node)
	return node and node.p and node.p.meta and node.p.meta.class
end

-- Depth-first search for the first node matching pred.
local function find(node, pred)
	if type(node) ~= "table" then return nil end
	if node.w ~= nil and pred(node) then return node end
	if node.p == nil then return nil end
	for _, child in ipairs(node.p.children or {}) do
		local hit = find(child, pred)
		if hit then return hit end
	end
	if node.p.content then return find(node.p.content, pred) end
	if node.p.layout then return find(node.p.layout, pred) end
	return nil
end

local F -- per-test fakes and records

-- Hook slots of the component being rendered by render() (react keeps them across renders);
-- outside render() every hook call is a fresh mount.
local function slot(init)
	if F.owner == nil then return init() end
	F.hookIdx = F.hookIdx + 1
	local hooks = F.hooks[F.owner]
	if hooks[F.hookIdx] == nil then hooks[F.hookIdx] = init() end
	return hooks[F.hookIdx]
end

local function stubs()
	local recipes = {}
	F.recipes = recipes
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(name, fn) recipes[name] = fn; return fn end,
		RegisterWrapperRecipe = function(name, _base, fn) recipes[name] = fn; return fn end,
		RegisterPluginRecipe = function(_ext, name, fn) recipes[name] = fn; return fn end,
		useStateLazy = function(init)
			return slot(function()
				local s = { v = init(), sets = 0 }
				function s:old() return self.v end
				function s:set(v) self.v = v; self.sets = self.sets + 1 end
				function s:hasExpired() return false end
				F.states[#F.states + 1] = s
				return s
			end)
		end,
		onStepTimer = function(fn, seconds) F.timer = fn; F.timerSeconds = seconds end,
		-- the ridge plugin renders without an owner; its onStep must not replace the panel's
		onStep = function(fn) if F.owner == "ridge" then F.ridgeStep = fn else F.step = fn end end,
		useState = function(v)
			return slot(function()
				local s = { v = v, sets = 0 }
				function s:old() return self.v end
				function s:set(x) self.v = x; self.sets = self.sets + 1 end
				return s
			end)
		end,
		onMount = function(fn) F.mount = fn end,
		useRef = function(v)
			return slot(function()
				local r = { v = v }
				function r:get() return self.v end
				function r:set(x) self.v = x end
				return r
			end)
		end,
		useRefLazy = function(init)
			local r = { v = init() }
			function r:get() return self.v end
			return r
		end,
	})
	stub_module("::/gui/main/builtin.lua", {
		TextView = widget("TextView"), BoxLayout = widget("BoxLayout"), CheckBox = widget("CheckBox"),
		ImageView = widget("ImageView"), Button = widget("Button"), ToggleButton = widget("ToggleButton"), TextInputField = widget("TextInputField"),
		ScrollArea = widget("ScrollArea"), Component = widget("Component"), Window = widget("Window"),
		ActionDescriptor = widget("ActionDescriptor"), LayerConfig = widget("LayerConfig"),
		HudIconManagerConfig = widget("HudIconManagerConfig"),
		type = {
			Orientation = { Horizontal = "H", Vertical = "V" },
			ScrollBarPolicy = { AlwaysOff = 0, AsNeeded = 1 },
		},
	})
	stub_module("::/gui/main/cargo_react_util.tl", { makeIcon = function(c, p, t) return { w = "Icon", p = { meta = { class = c } } } end })
	-- inline styles (ridge button padding, cargo chevron size): record what the script sets
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) local st = {}; for k, v in pairs(t) do st[k] = v end; return st end })
	stub_module("::/gui/main/color_util.tl", { toArray4 = function(c) return c end, toArray4WithTransparency = function(c) return c end })
	stub_module("::/scripts/lang_util.tl", { format = function(s, args)
		return (s:gsub("{(%w+)}", function(k) return tostring(args[k]) end))
	end })
	stub_module("::/scripts/table_util.tl", {
		copy = function(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end,
		deepEquals = function(a, b)
			local function de(x, y)
				if x == y then return true end
				if type(x) ~= "table" or type(y) ~= "table" then return false end
				for k, v in pairs(x) do if not de(v, y[k]) then return false end end
				for k in pairs(y) do if x[k] == nil then return false end end
				return true
			end
			return de(a, b)
		end,
	})
	stub_module("::/gui/main/main_mod_button_area.tl", { MainModButtonAreaExtension = "ext" })
	local toolStackApi = {
		getActiveTool = function() return F.active end,
		push = function(tool, _, param, stack) F.pushes = F.pushes + 1; F.active = tool end,
		pop = function(tool) F.pops = F.pops + 1; F.active = nil end,
	}
	stub_module("::/gui/main/game_react_globals.tl", {
		getDefaultRendererComponent = function() return "rc" end,
		getDefaultWindowContainer = function()
			return { hasExpired = function() return false end }
		end,
		getDefaultToolStack = function() return "stack" end,
		getDefaultToolStackApi = function() return toolStackApi end,
	})
	stub_module("::/gui/main/hud_icon_toolbox.tl", { HudIconMasterGame = "master" })
	stub_module("::/gui/hud/hud_react_util.tl", {})
	stub_module("::/gui/main/selector_react_util.tl", { defaultHudIconFilter = { 1, 2 }, defaultHudIconFilterTvCarrier = {} })
	stub_module("::/gui/main/tool_react_util.tl", { registerToolWithWindow = function() return F.tool end })
	stub_module("::/gui/main/cargo_util.tl", { getCargoFlowCount = function() return 0 end })
end

-- Every api.gui function records its call; called from the timer (F.inTimer, the worker-thread
-- path in game) it records the name in F.timerGuiCalls and throws, like the crash it would be.
local function guardGui(t, path)
	for k, v in pairs(t) do
		local name = path .. "." .. k
		if type(v) == "table" then
			guardGui(v, name)
		elseif type(v) == "function" then
			t[k] = function(...)
				F.guiCalls[#F.guiCalls + 1] = name
				if F.inTimer then
					F.timerGuiCalls[#F.timerGuiCalls + 1] = name
					error("api.gui call on the onStepTimer (worker thread) path: " .. name)
				end
				return v(...)
			end
		end
	end
	return t
end

local function fakeApi(sqperfLog, hudButtonStyle)
	set_global("api", {
		type = {
			Clock = { new = function()
				return { getTime = function() return F.clockUs end }
			end },
			ComponentType = { INDUSTRY = 1, TOWN = 2, TRANSPORT_VEHICLE = 3 },
			LayerConfig = { new = function() return { layerConfig = true } end },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
		},
		engine = {
			getEntitiesWithComponent = function() F.reads = F.reads + 1; return {} end,
			config = { getModParams = function() return { [MOD] = { sqperf_log = sqperfLog, hudButtonStyle = hudButtonStyle } } end },
		},
		gui = guardGui({
			genericRep = {
				find = function(path) return path end,
				get = function(path)
					eq(path, "::/gui/main/default_colors.gres")
					return { data = { BaseMedium = { 0.2, 0.2, 0.2, 1 }, NeutralLightest = { 1, 1, 1, 1 } } }
				end,
			},
			byId = { isVisible = function(id) eq(id, "squareindustryflows.window"); return F.visible end },
			game = {
				isMapEditor = function() return F.mapEditor end,
				getGuiSaveData = function() return nil end,
			},
		}, "api.gui"),
	})
end

local function load(sqperfLog, hudButtonStyle)
	F = { states = {}, hooks = {}, hookIdx = 0, pushes = 0, pops = 0, clockUs = 1e9, tool = { tool = true }, mapEditor = false,
		visible = true, reads = 0, guiCalls = {}, timerGuiCalls = {}, inTimer = false }
	clear_logs()
	stubs()
	fakeApi(sqperfLog or 1, hudButtonStyle)
	reset_modules()
	return ug_require(PATH)
end

local function payload()
	local p = { toolParam = { gameCtx = { rendererComponent = "rc" } }, actions = {} }
	p.setActionFn = function(fn, key) p.actions[#p.actions + 1] = { fn = fn, key = key } end
	return p
end

-- One render of the panel content with persistent hook slots.
local function render(p)
	F.owner, F.hookIdx = "content", 0
	F.hooks.content = F.hooks.content or {}
	local root = F.recipes.IndustryFlowsContent(p)
	F.owner = nil
	return root
end

-- One onStepTimer tick, as on its worker thread: any api.gui call throws (guardGui).
local function tick()
	F.inTimer = true
	local okRun, err = pcall(F.timer)
	F.inTimer = false
	eq(#F.timerGuiCalls, 0, "api.gui calls from the timer: " .. table.concat(F.timerGuiCalls, ", "))
	ok(okRun, tostring(err))
end

local function sqperfLines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("[SQPERF]", 1, true) and (pattern == nil or e.msg:find(pattern, 1, true)) then out[#out + 1] = e.msg end
	end
	return out
end

test("ridge plugin: an icon button by default (also without the param), nothing in the map editor", function()
	for _, style in ipairs({ 2, false }) do
		local m = load(nil, style or nil)
		local root = m.IndustryFlowsRidgePlugin()
		eq(root.w, "BoxLayout")
		local button = root.p.children[1]
		eq(button.w, "ToggleButton")
		eq(class(button), "flows-ridge-icon-button")
		-- inline size only (no stylesheet rule, no colour: the base ToggleButton rules give the tile and states)
		eq(table.concat(button.p.meta.styleSheet.padding, ","), "8,8,8,8")
		eq(button.p.meta.styleSheet.backgroundColor1, nil)
		eq(button.p.value, 0)
		eq(button.p.content.w, "ImageView")
		eq(button.p.content.p.path, "square_industry_flows::/industry_flows/gui/flows.tga")
		eq(button.p.content.p.meta.styleSheet.size, { 24, 24 })
		eq(button.p.content.p.meta.styleSheet.color, nil)
		F.mapEditor = true
		eq(m.IndustryFlowsRidgePlugin(), nil)
	end
end)

test("ridge plugin: hudButtonStyle Text gives the Flows text button", function()
	local m = load(nil, 1)
	local button = m.IndustryFlowsRidgePlugin().p.children[1]
	eq(button.w, "Button")
	eq(class(button), "flows-ridge-button")
	-- padding inline (no stylesheet rule): CSS order top, right, bottom, left
	eq(table.concat(button.p.meta.styleSheet.padding, ","), "2,8,2,8")
end)

test("ridge button opens and closes the panel tool (click_toggle wrapper)", function()
	local m = load(nil, 1)
	local onClick = m.IndustryFlowsRidgePlugin().p.children[1].p.onClick
	eq(onClick(), nil)
	eq(F.pushes, 1)
	eq(F.active, F.tool)
	eq(onClick(), nil)
	eq(F.pops, 1)
	eq(F.active, nil)
end)

test("icon ToggleButton: toggles the panel and is pressed while the tool is active", function()
	local m = load()
	-- one ridge render with persistent hook slots
	local function ridgeButton()
		F.owner, F.hookIdx = "ridge", 0
		F.hooks.ridge = F.hooks.ridge or {}
		local root = m.IndustryFlowsRidgePlugin()
		F.owner = nil
		return root.p.children[1]
	end
	ridgeButton().p.onValueChange(1)
	eq(F.pushes, 1)
	eq(ridgeButton().p.value, 1)
	-- closed some other way (the window's X pops the tool): the next step releases the button
	F.active = nil
	F.ridgeStep()
	eq(ridgeButton().p.value, 0)
	ridgeButton().p.onValueChange(1)
	eq(F.pushes, 2)
	ridgeButton().p.onValueChange(0)
	eq(F.pops, 1)
	eq(ridgeButton().p.value, 0)
end)

test("content render returns the panel layout and binds the action (content_render wrapper)", function()
	load()
	local p = payload()
	local root = render(p)
	eq(root.w, "BoxLayout")
	eq(class(root), "flows-content, flows-box")
	eq(#p.actions, 1)
	eq(p.actions[1].key, "square_industry_flows")
	-- first poll ran via useStateLazy (poll_open wrapper) and gave an empty type list
	local data = F.states[2]:old()
	eq(#data.types, 0)
	ok(find(root, function(n) return class(n) == "font-scale-annotation, flows-hint" end) ~= nil)
	eq(F.timerSeconds, 2.0)
	-- second render with the same view keeps the action function
	render(p)
	eq(p.actions[2].fn, p.actions[1].fn)
end)

test("a toggle click rebuilds the view; an unchanged timer poll sets nothing", function()
	load()
	local p = payload()
	local root = render(p)
	local dataState = F.states[2]
	local outputs = find(root, function(n) return n.w == "CheckBox" and n.p.label == "Outputs" end)
	ok(outputs ~= nil, "Outputs toggle")
	outputs.p.onValueChange(0)
	eq(dataState.sets, 1)
	eq(F.states[1].v.toggles.outputs, false)
	tick()
	eq(dataState.sets, 1)
end)

test("Debug log On: the 30 s summary lists the sections, the timer poll timed", function()
	load(2)
	local m = ug_require(PATH)
	m.IndustryFlowsRidgePlugin() -- first stop: opens the level 3 window
	local p = payload()
	local root = render(p)
	find(root, function(n) return n.w == "CheckBox" and n.p.label == "Inputs" end).p.onValueChange(0)
	tick()
	tick()
	m.IndustryFlowsRidgePlugin().p.children[1].p.onValueChange(1)
	F.clockUs = F.clockUs + 31e6
	m.IndustryFlowsRidgePlugin() -- next window boundary: summary line
	local lines = sqperfLines("win_ms=")
	eq(#lines, 1)
	local line = lines[1]
	for _, s in ipairs({ "content_render n=1 ms=", "poll_open n=1 ms=", "layer_config n=1 ms=",
		"rebuild_view n=1 ms=", "click_toggle n=1 ms=", "ridge_render n=" }) do
		ok(line:find(s, 1, true), s .. " in " .. line)
	end
	ok(line:find("| poll n=2 ms=", 1, true), "poll timed: " .. line)
	eq(#sqperfLines("phase=first"), 1)
end)

test("Debug log Off: no SQPERF lines from normal use", function()
	load(1)
	local p = payload()
	render(p)
	tick()
	F.clockUs = F.clockUs + 31e6
	render(p)
	eq(#sqperfLines(), 0)
end)

test("timer poll: reads the map, no api.gui call (worker thread)", function()
	load()
	local p = payload()
	render(p)
	F.step() -- Main Thread: reads the window visibility
	eq(F.guiCalls[#F.guiCalls], "api.gui.byId.isVisible")
	local before = F.reads
	tick()
	tick()
	ok(F.reads > before, "the timer polled the map")
	eq(#F.timerGuiCalls, 0)
end)

test("hidden (shelved) panel: the timer skips the poll; the next tick after it comes back polls", function()
	load()
	local p = payload()
	render(p)
	F.visible = false
	F.step()
	local before = F.reads
	tick()
	tick()
	eq(F.reads, before, "no poll while shelved")
	F.visible = true
	F.step()
	tick()
	ok(F.reads > before, "first tick after unshelving polls")
end)

test("isVisible failing (pcall) counts as visible, like before", function()
	load()
	render(payload())
	F.visible = false
	F.step()
	api.gui.byId.isVisible = function() error("no such id") end
	F.step()
	local before = F.reads
	tick()
	ok(F.reads > before)
end)

test("Debug log On: a visibility change logs from onStep and shelved ticks are counted", function()
	load(2)
	local m = ug_require(PATH)
	m.IndustryFlowsRidgePlugin()
	render(payload())
	tick() -- opens the first window
	F.visible = false
	F.step()
	F.step() -- no change: no second line
	tick()
	tick()
	local lines = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("panel visible=", 1, true) then lines[#lines + 1] = e.msg end
	end
	eq(#lines, 1)
	ok(lines[1]:find("[IndustryFlows] panel visible=false (onStep)", 1, true), lines[1])
	F.clockUs = F.clockUs + 31e6
	m.IndustryFlowsRidgePlugin()
	local summary = sqperfLines("win_ms=")
	eq(#summary, 1)
	ok(summary[1]:find("poll_shelved n=2", 1, true), summary[1])
end)

test("Debug log Off: a visibility change logs nothing", function()
	load(1)
	render(payload())
	F.visible = false
	F.step()
	for _, e in ipairs(log_entries()) do
		ok(not e.msg:find("panel visible=", 1, true), e.msg)
	end
end)
