-- Line actions button (lmp_actions.lua) and Duplicate / Reverse line (line_ops.lua) with fake react / builtin /
-- popover / button utils and a fake api: the injector right of A+, visibility (one unprotected line), the menu's
-- entries and disabled states, the commands built (create with copy name and new colour, update with the reversed
-- stops and re-picked terminals), callbacks (success selects the copy, failure gives feedback), the busy guard, menu
-- open / close handling and isolation of a failing entry.

local AUTO_RENAME = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"

local world, sent, feedbacks, selects, windows, clockUs, recipeName
local react, builtin, button_react_util, line_util, popover, actions, ops
local hooks -- per recipe render: { steps = {}, unmounts = {}, mouse = {} }

local function stop(group, terminal, wps)
	local w = {}
	for i, t in ipairs(wps or {}) do w[i] = { tag = t, pos = { x = t, y = 0, z = 0 } } end
	return {
		stationGroup = group, station = 0, terminal = terminal or 0, alternativeTerminals = {},
		loadMode = 0, minWaitingTime = 0, maxWaitingTime = 600, maxAdditionalWaitingTime = 30,
		waypoints = w, stopConfig = { load = { true }, maxLoad = { 1 }, forceUnload = false,
			destroyForConfigChange = false, destroyForRefresh = false },
	}
end

local function lineComp(stops)
	return { stops = stops, customFilters = false, reservationPriority = 0 }
end

local function state(v) return { old = function() return v.value end, get = function() return v.value end } end

local function makeParams(lineEntity, selected)
	local sel = {}
	for i = 1, selected or 1 do sel[i] = { entity = lineEntity } end
	local wc = {
		removeAllWindows = function() windows.removedAll = windows.removedAll + 1; windows.open = nil end,
		removeWindow = function(_r, key) windows.removed[#windows.removed + 1] = key; windows.open = nil end,
		addWindow = function(_r, key, p) windows.open = { key = key, p = p } end,
	}
	return {
		lineState = state({ value = { entityAndRevision = { entity = lineEntity } } }),
		lineManagerStateRef = state({ value = { lineListEntitiesSelected = sel } }),
		gameCtx = {
			filters = state({ value = { protectedEntities = {} } }),
			windowContainer = state({ value = { getApi = function() return wc end } }),
		},
		configureLinesPopoverPosRef = state({ value = { getPosition = function(_s, a, b)
			return { x = 100 * a, y = 50 * b } end } }),
		addFeedback = function(msg, mode) feedbacks[#feedbacks + 1] = { msg, mode } end,
		selectLine = function(details, scroll, seg) selects[#selects + 1] = { details.entity, scroll, seg } end,
		getModeState = function() return { "SEGMENT", 3 } end,
		switchMode = function(m) world.modes[#world.modes + 1] = m end,
	}
end

local function ctor(name)
	return { new = function(...)
		local o = { _type = name }
		if name == "StationTerminal" then o.station, o.terminal = ... end
		if name == "Vec3f" then o.x, o.y, o.z = ... end
		return o
	end }
end

before_each(function()
	reset_modules()
	clear_logs()
	world = { lines = {}, groups = { [1] = { stations = { 1 } }, [2] = { stations = { 1 } }, [3] = { stations = { 1 } },
		[4] = { stations = { 1 } } }, names = {}, player = 99, playerLines = {}, assignment = nil, modes = {} }
	sent, feedbacks, selects, clockUs = {}, {}, {}, 1e9
	windows = { removedAll = 0, removed = {} }
	recipeName = "LinePanelActionButtons"

	local Line = ctor("Line")
	Line.Stop = ctor("Stop")
	Line.StopConfig = ctor("StopConfig")
	set_global("api", {
		engine = {
			config = { getModParams = function() return {} end },
			entityExists = function(e) return world.lines[e] ~= nil or world.groups[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] end
				if ct == "STATION_GROUP" then return world.groups[e] end
			end,
			util = {
				getPlayer = function() return world.player end,
				getEntityName = function(e) return world.names[e] or ("Line " .. tostring(e)) end,
			},
			system = { lineSystem = {
				getLinesForPlayer = function(p) eq(p, world.player); return world.playerLines end,
				getBestLineAssignment = function(line, comp, allow)
					world.assignCall = { line = line, comp = comp, allow = allow }
					if world.assignment == "error" then error("no assignment") end
					return world.assignment
				end,
			} },
		},
		type = {
			Clock = { new = function() return { getTime = function() return clockUs end } end },
			ComponentType = { LINE = "LINE", STATION_GROUP = "STATION_GROUP" },
			Line = Line, StationTerminal = ctor("StationTerminal"), Waypoint = ctor("Waypoint"),
			EdgePos = ctor("EdgePos"), EdgeId = ctor("EdgeId"), Vec3f = ctor("Vec3f"),
		},
		gui = { mouse = { Event = { Type = { Pressed = "P", Released = "R" } } } },
		cmd = {
			makeLineUpdateCmd = function(line, comp) return { kind = "update", line = line, comp = comp } end,
			makeLineCreateCmd = function(name, color, player, comp)
				return { kind = "create", name = name, color = color, player = player, comp = comp }
			end,
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
		},
	})

	hooks = nil
	local states = {} -- per recipe name and hook order, kept across renders (react's useState)
	react = {
		getCurrentRecipeName = function() return recipeName end,
		-- a recipe is called as Recipe{params}; it renders at once and records its hooks
		RegisterRecipe = function(name, fn) return function(p)
			hooks = { steps = {}, unmounts = {}, mouse = {}, name = name, n = 0 }
			local node = fn(p or {})
			node.hooks = hooks
			return node
		end end,
		useSelfRef = function() return state({}) end,
		useState = function(v0)
			hooks.n = hooks.n + 1
			local key = hooks.name .. hooks.n
			local box = states[key] or { value = v0 }
			states[key] = box
			return { old = function() return box.value end, set = function(_s, v) box.value = v end }
		end,
		onStep = function(f) hooks.steps[#hooks.steps + 1] = f end,
		onUnmount = function(f) hooks.unmounts[#hooks.unmounts + 1] = f end,
		onMouseEvent = function(f) hooks.mouse[#hooks.mouse + 1] = f end,
	}
	builtin = {
		type = { Orientation = { Horizontal = "H", Vertical = "V" }, ImageViewScaling = { AutoFit = "AutoFit" } },
		BoxLayout = function(p) return { kind = "BoxLayout", orientation = p.orientation, children = p.children } end,
		ToggleButton = function(p) return { kind = "ToggleButton", meta = p.meta, content = p.content, value = p.value,
			onValueChange = p.onValueChange } end,
		Button = function(p) return { kind = "Button", meta = p.meta, onClick = p.onClick, content = p.content } end,
		ImageView = function(p)
			for k in pairs(p) do
				if k ~= "path" and k ~= "scaling" then error("unexpected ImageView field " .. tostring(k)) end
			end
			return { kind = "ImageView", path = p.path }
		end,
	}
	local engine_react_util = {
		useStepState = function(get) local v = get(); return { old = function() return v end } end,
	}
	button_react_util = {
		makeIconToggleButton = function(class, path) return { kind = "Toggle", class = class, path = path } end,
		makeIconTextButton = function(class, path, text, onClick, tooltip, enabled)
			return { kind = "Item", class = class, path = path, text = text, onClick = onClick, tooltip = tooltip,
				enabled = enabled }
		end,
	}
	line_util = {
		makeLineActionDescriptor = function(cp, x) return { cp = cp, x = x } end,
		isStopProtected = function(line, _g, protected) return protected[line] == true end,
		makeLineColor = function(p) eq(p, world.player); return { x = 0.1, y = 0.2, z = 0.3 } end,
	}
	popover = { PopoverWindow = { recipe = "PopoverWindow" } }
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/engine_react_util.tl", engine_react_util)
	stub_module("::/gui/main/button_react_util.tl", button_react_util)
	stub_module("::/gui/main/popover_react_util.tl", popover)
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", line_util)

	ops = ug_require "square_line_manager_plus::/line_manager_plus/line_ops.lua"
	actions = ug_require "square_line_manager_plus::/line_manager_plus/lmp_actions.lua"
	ok(ops.install({}, {}))
end)

-- a manager with line 7 (stops of groups 1, 2, 3) open and selected
local function manager(selected, stops)
	world.lines[7] = lineComp(stops or { stop(1), stop(2), stop(3) })
	world.names[7] = "Bus 1"
	world.playerLines = { 7 }
	local p = makeParams(7, selected)
	line_util.makeLineActionDescriptor(p)
	return p
end

-- render the A+ button through the wrappers; returns our button node (the SquareLmpLineActions BoxLayout) or nil
local function renderToolbar()
	local node = button_react_util.makeIconToggleButton("vehicle-button, secondary", AUTO_RENAME, function() end, "tip")
	if node.kind ~= "BoxLayout" then return nil, node end
	for i, c in ipairs(node.children) do
		if c.kind == "Toggle" then return node.children[i + 1], node end
	end
end

local function items()
	local m = actions.Menu({})
	local out = {}
	for _i, it in ipairs(m.children) do out[it.text] = it end
	return out, m
end

local function warnings(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

-- toolbar --------------------------------------------------------------------------------------------------------------

test("the Line actions button sits right of A+ with A+'s look, only for one selected line", function()
	manager()
	local btn, row = renderToolbar()
	ok(btn, "button rendered")
	eq(row.children[1].kind, "Toggle")
	local toggle = btn.children[1]
	eq(toggle.kind, "ToggleButton")
	eq(toggle.meta.class, "vehicle-button, secondary")
	eq(toggle.meta.tooltip, "Line actions")
	eq(toggle.content.path, actions.ICON)
	eq(toggle.value, 0)
	eq(actions.ids(), { "duplicate", "reverse" })

	manager(2)
	btn = renderToolbar()
	eq(#btn.children, 0, "two selected lines: hidden")
end)

test("hidden for a protected or deleted line, and before any manager params", function()
	local btn, node = renderToolbar()
	eq(btn, nil)
	eq(node.kind, "Toggle")
	local p = manager()
	p.gameCtx.filters = state({ value = { protectedEntities = { [7] = true } } })
	eq(#renderToolbar().children, 0)
	manager()
	world.lines[7] = nil
	eq(#renderToolbar().children, 0)
end)

test("toggle opens the menu at the A+ popover anchor with A+'s window classes; toggling off closes only ours", function()
	local p = manager()
	local btn = renderToolbar()
	btn.children[1].onValueChange(1)
	ok(windows.open, "window added")
	eq(windows.open.key, actions.KEY)
	eq(windows.open.p.windowClass, "configure-lines, management")
	eq(windows.open.p.x, 100)
	eq(windows.open.p.y, 50)
	eq(windows.open.p.windowTitle, "Line actions")
	ok(windows.open.p.params.params == p)
	eq(windows.removedAll, 1, "other popovers closed first, as vanilla")
	btn.children[1].onValueChange(0)
	eq(windows.removed, { actions.KEY })
end)

test("the toggle follows the menu: closed elsewhere -> step turns it off; hidden while open -> closes", function()
	manager()
	local btn = renderToolbar()
	local h = btn.hooks
	btn.children[1].onValueChange(1)
	-- the menu window unmounts (click outside / another popover)
	local menu = actions.Menu(windows.open.p.params)
	for _i, f in ipairs(menu.hooks.unmounts) do f() end
	for _i, f in ipairs(h.steps) do f() end
	-- re-render: off
	eq(renderToolbar().children[1].value, 0)

	-- open again, then the line gets two selected -> hidden -> the next step closes our window
	btn = renderToolbar()
	btn.children[1].onValueChange(1)
	manager(2)
	btn = renderToolbar()
	for _i, f in ipairs(btn.hooks.steps) do f() end
	eq(windows.removed[#windows.removed], actions.KEY)
end)

test("an older menu's unmount doesn't clear a newer open menu", function()
	manager()
	local btn = renderToolbar()
	btn.children[1].onValueChange(1)
	local old = actions.Menu(windows.open.p.params)
	btn.children[1].onValueChange(1) -- reopened (new gen)
	for _i, f in ipairs(old.hooks.unmounts) do f() end
	btn = renderToolbar()
	for _i, f in ipairs(btn.hooks.steps) do f() end
	eq(renderToolbar().children[1].value, 1)
end)

test("press while open locks: the release's value change doesn't reopen", function()
	manager()
	local btn = renderToolbar()
	btn.children[1].onValueChange(1)
	btn = renderToolbar()
	btn.hooks.mouse[1]({ type = "P" })
	btn.children[1].onValueChange(1)
	eq(windows.removed[#windows.removed], actions.KEY, "closed, not reopened")
	eq(windows.open, nil)
end)

-- menu ---------------------------------------------------------------------------------------------------------------

test("menu: Duplicate and Reverse, enabled, with their icons, tooltips and the secondary class", function()
	manager()
	local it, m = items()
	eq(m.orientation, "V")
	eq(#m.children, 2)
	eq(m.children[1].text, "Duplicate line")
	eq(m.children[2].text, "Reverse line")
	ok(it["Duplicate line"].enabled)
	ok(it["Reverse line"].enabled)
	eq(it["Duplicate line"].class, "secondary")
	eq(it["Duplicate line"].path, "::/gui/line_vehicle_mgmt/icons/symbol_square_copy.tga")
	eq(it["Reverse line"].path, "::/gui/line_vehicle_mgmt/icons/symbol_arrow_reverse.tga")
	ok(it["Reverse line"].tooltip:find("Stop 1 stays first", 1, true))
end)

test("menu: a line with 1 stop or a gone station disables both with the reason", function()
	manager(1, { stop(1) })
	local it = items()
	eq(it["Duplicate line"].enabled, false)
	eq(it["Duplicate line"].tooltip, "The line needs at least 2 stops.")
	eq(it["Reverse line"].tooltip, "The line needs at least 2 stops.")
	manager()
	world.groups[2] = nil
	it = items()
	eq(it["Reverse line"].enabled, false)
	eq(it["Reverse line"].tooltip, "A station of this line no longer exists.")
end)

test("menu: empty when the context is gone (several lines selected)", function()
	manager(2)
	local _it, m = items()
	eq(#m.children, 0)
end)

-- the toolbar button's useStepState (lazy init + step) and the menu run before a new manager window's descriptor call:
-- the closed window's expired lineState must not be read (the engine prints a traceback for :old() on it)
test("an expired lineState of a closed manager window is never read: hidden, no warning", function()
	local p = manager()
	ok(#renderToolbar().children > 0)
	local reads = 0
	p.lineState = {
		hasExpired = function() return true end,
		old = function() reads = reads + 1; error("old() on an expired state") end,
	}
	eq(#renderToolbar().children, 0)
	local _it, m = items()
	eq(#m.children, 0)
	eq(reads, 0)
	eq(warnings(), 0)
	manager()
	ok(#renderToolbar().children > 0)
end)

test("menu: a failing entry view shows it disabled and warns once; the other entry is unaffected", function()
	manager()
	actions.register({ id = "broken", order = 300, label = "Broken entry", view = function() error("v boom") end,
		run = function() end })
	local it = items()
	eq(it["Broken entry"].enabled, false)
	ok(it["Duplicate line"].enabled)
	items()
	eq(warnings("v boom"), 1)
end)

test("menu: a failing run gives one feedback line and closes the menu", function()
	manager()
	actions.register({ id = "broken", order = 300, label = "Broken entry",
		view = function() return { enabled = true, tooltip = "t" } end, run = function() error("r boom") end })
	renderToolbar().children[1].onValueChange(1)
	items()["Broken entry"].onClick()
	eq(feedbacks[1], { "Line Manager Plus: the line action failed (see log).", "Error" })
	eq(windows.removed[#windows.removed], actions.KEY)
	eq(warnings("r boom"), 1)
end)

-- duplicate ------------------------------------------------------------------------------------------------------------

test("duplicate: one create command with the same stops, a copy name, the new colour, the player", function()
	manager(1, { stop(1, 2, { 5 }), stop(2, 1), stop(3) })
	items()["Duplicate line"].onClick()
	eq(#sent, 1)
	local c = sent[1].cmd
	eq(c.kind, "create")
	eq(c.name, "Bus 1 (copy)")
	eq(c.color, { x = 0.1, y = 0.2, z = 0.3 })
	eq(c.player, 99)
	eq(#c.comp.stops, 3)
	eq(c.comp.stops[1].stationGroup, 1)
	eq(c.comp.stops[1].terminal, 2)
	eq(#c.comp.stops[1].waypoints, 1)
	eq(c.comp.stops[3].stationGroup, 3)
	eq(#world.modes, 0, "duplicate leaves the editor mode alone")
end)

test("duplicate: name avoids the player's existing copies", function()
	manager()
	world.playerLines = { 7, 8, 9 }
	world.names[8] = "Bus 1 (copy)"
	world.names[9] = "Bus 1 (copy 2)"
	items()["Duplicate line"].onClick()
	eq(sent[1].cmd.name, "Bus 1 (copy 3)")
end)

test("duplicate: success selects the new line in that manager; failure gives feedback", function()
	manager()
	items()["Duplicate line"].onClick()
	sent[1].cb({}, true, { { 42, 1 } })
	eq(selects, { { 42, true, nil } })
	items()["Duplicate line"].onClick()
	sent[2].cb({}, false, {})
	eq(feedbacks[1], { "Line Manager Plus: the game refused the new line.", "Error" })
	eq(#selects, 1)
end)

test("duplicate: no selection when another manager window took over meanwhile", function()
	manager()
	items()["Duplicate line"].onClick()
	manager() -- new commonParams captured
	sent[1].cb({}, true, { { 42, 1 } })
	eq(selects, {})
end)

-- reverse ------------------------------------------------------------------------------------------------------------

test("reverse: one update command, stop 1 first, waypoints moved, engine terminals applied; editor mode reset", function()
	manager(1, { stop(1, 0, { 10 }), stop(2, 0, { 20 }), stop(3, 0, { 30, 31 }) })
	world.assignment = { { station = 0, terminal = 0 }, { station = 0, terminal = 4 }, { station = -1, terminal = -1 } }
	items()["Reverse line"].onClick()
	eq(#sent, 1)
	local c = sent[1].cmd
	eq(c.kind, "update")
	eq(c.line, 7)
	local g, t = {}, {}
	for i, s in ipairs(c.comp.stops) do g[i] = s.stationGroup; t[i] = s.terminal end
	eq(g, { 1, 3, 2 })
	eq(t, { 0, 4, 0 }, "re-picked where answered, kept otherwise")
	eq(c.comp.stops[1].waypoints[1].tag, 31)
	eq(c.comp.stops[1].waypoints[2].tag, 30)
	eq(c.comp.stops[2].waypoints[1].tag, 20)
	eq(c.comp.stops[3].waypoints[1].tag, 10)
	eq(world.assignCall.line, 7)
	eq(world.assignCall.allow, true)
	-- the assignment was asked for the reversed order
	eq(world.assignCall.comp.stops[2].stationGroup, 3)
	eq(world.modes, { { "SEGMENT", nil }, { "SEGMENT", nil } })
end)

test("reverse: a failing terminal query keeps the player's terminals and warns once", function()
	manager(1, { stop(1, 1), stop(2, 2), stop(3, 0) })
	world.assignment = "error"
	items()["Reverse line"].onClick()
	local t = {}
	for i, s in ipairs(sent[1].cmd.comp.stops) do t[i] = s.terminal end
	eq(t, { 1, 0, 2 })
	eq(warnings("no assignment"), 1)
end)

test("reverse: nothing to change -> no command, a plain feedback line", function()
	manager(1, { stop(1), stop(2) })
	items()["Reverse line"].onClick()
	eq(#sent, 0)
	eq(feedbacks[1], { "Line Manager Plus: reversing doesn't change this line.", nil })
end)

test("reverse: failure gives feedback; success only logs", function()
	manager()
	items()["Reverse line"].onClick()
	sent[1].cb({}, true)
	eq(#feedbacks, 0)
	items()["Reverse line"].onClick()
	sent[2].cb({}, false)
	eq(feedbacks[1], { "Line Manager Plus: the game refused the reversed line.", "Error" })
end)

test("reverse: a station gone between render and click -> feedback, no command", function()
	manager()
	local it = items()
	world.groups[3] = nil
	it["Reverse line"].onClick()
	eq(#sent, 0)
	eq(feedbacks[1], { "A station of this line no longer exists.", "Error" })
end)

-- busy ---------------------------------------------------------------------------------------------------------------

test("busy: entries disabled while a command is in flight, free again after the callback or 10 s", function()
	manager()
	items()["Reverse line"].onClick()
	local it = items()
	eq(it["Duplicate line"].enabled, false)
	eq(it["Reverse line"].enabled, false)
	ok(it["Reverse line"].tooltip:find("opposite order", 1, true), "the normal tooltip")
	it["Duplicate line"].onClick()
	eq(#sent, 1, "a click while busy sends nothing")
	sent[1].cb({}, true)
	ok(items()["Duplicate line"].enabled)

	items()["Duplicate line"].onClick()
	eq(items()["Reverse line"].enabled, false)
	clockUs = clockUs + ops.BUSY_US + 1
	ok(items()["Reverse line"].enabled)
	eq(warnings("no callback"), 1)
end)

test("install twice registers once", function()
	ok(ops.install({}, {}))
	eq(actions.ids(), { "duplicate", "reverse" })
	eq(actions.build({ params = {} }) ~= nil, true)
end)

-- undo integration ----------------------------------------------------------------------------------------------------

test("with the undo feature installed, a reverse is one Undo step that restores the original line", function()
	local undo = ug_require "square_line_manager_plus::/line_manager_plus/undo.lua"
	ok(undo.install({}))
	manager(1, { stop(1, 0, { 10 }), stop(2), stop(3) })
	local original = world.lines[7]
	local _btn, row = renderToolbar() -- undo session starts with the original line
	eq(row.children[1].children[1].kind, "Button", "undo button left of A+")
	items()["Reverse line"].onClick()
	-- the engine applies the update
	world.lines[7] = sent[1].cmd.comp
	sent[1].cb({}, true)
	_btn, row = renderToolbar() -- the undo buttons poll the line: one recorded edit
	local undoBtn = row.children[1].children[1]
	ok(undoBtn.meta.enabled)
	ok(undoBtn.meta.tooltip:find("stops reordered", 1, true), undoBtn.meta.tooltip)
	ok(undoBtn.meta.tooltip:find("1 change", 1, true), undoBtn.meta.tooltip)
	undoBtn.onClick()
	eq(#sent, 2)
	eq(sent[2].cmd.kind, "update")
	local g = {}
	for i, st in ipairs(sent[2].cmd.comp.stops) do g[i] = st.stationGroup end
	eq(g, { 1, 2, 3 })
	eq(sent[2].cmd.comp.stops[1].waypoints[1].tag, original.stops[1].waypoints[1].tag)
end)
