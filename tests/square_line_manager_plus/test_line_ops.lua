-- Line actions button (lmp_actions.lua) and Duplicate / Reverse / Duplicate + reverse line (line_ops.lua) with fake react / builtin /
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
		Component = function(p) return { kind = "Component", meta = p.meta, layout = p.layout } end,
		TextView = function(p) return { kind = "TextView", meta = p.meta, text = p.text } end,
		ImageView = function(p)
			for k in pairs(p) do
				if k ~= "path" and k ~= "scaling" and k ~= "meta" then error("unexpected ImageView field " .. tostring(k)) end
			end
			return { kind = "ImageView", path = p.path, meta = p.meta }
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

-- the menu's rows as { text, path, tooltip, enabled, onClick, node } (header card first, then the rows' Component)
local function rowOf(btn)
	local kids = btn.content.layout.children
	return { text = kids[3].text, path = kids[1].path, tooltip = btn.meta.tooltip, enabled = btn.meta.enabled,
		onClick = btn.onClick, node = btn }
end

local function items()
	local m = actions.Menu({})
	local out, list = {}, {}
	if #m.children > 0 then
		for _i, btn in ipairs(m.children[2].layout.children) do
			local r = rowOf(btn)
			out[r.text] = r
			list[#list + 1] = r
		end
	end
	return out, m, list
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
	eq(actions.ids(), { "duplicate", "reverse", "duplicate_reversed", "set_cargo" })

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

test("menu: header card, then Duplicate, Reverse, Duplicate + reverse and Set cargo, enabled, with icons and tooltips", function()
	manager()
	local it, m, list = items()
	eq(m.orientation, "V")
	eq(#m.children, 2)
	-- Auto-Rename look: a filling header wrapper with the title card, then the filling rows wrapper
	local headerWrap = m.children[1]
	eq(headerWrap.meta.class, "horizontal-spacer")
	local card = headerWrap.layout.children[1]
	eq(card.meta.class, "horizontal-spacer")
	eq(card.layout.children[1].meta.class, "font-scale-headline")
	eq(card.layout.children[1].text, "Line actions")
	eq(m.children[2].meta.class, "horizontal-spacer")
	eq(#list, 4)
	eq(list[1].text, "Duplicate line")
	eq(list[2].text, "Reverse line")
	eq(list[3].text, "Duplicate + reverse line")
	eq(list[4].text, "Set cargo for all stops")
	ok(list[4].enabled)
	eq(list[4].path, "::/gui/line_vehicle_mgmt/icons/symbol_cargo.tga")
	ok(list[4].tooltip:find("clear the cargo selection", 1, true))
	ok(it["Duplicate line"].enabled)
	ok(it["Reverse line"].enabled)
	ok(it["Duplicate + reverse line"].enabled)
	-- rows: no class (lmp.css.lua styles every Button in the menu), content fills the button, text in body font
	local btn = it["Duplicate line"].node
	eq(btn.meta.class, nil)
	eq(btn.content.meta.class, "horizontal-spacer")
	eq(btn.content.layout.orientation, "H")
	eq(btn.content.layout.children[3].meta.class, "font-scale-body")
	eq(it["Duplicate line"].path, "::/gui/line_vehicle_mgmt/icons/symbol_square_copy.tga")
	eq(it["Reverse line"].path, "::/gui/line_vehicle_mgmt/icons/symbol_arrow_reverse.tga")
	eq(it["Duplicate + reverse line"].path, "::/gui/line_vehicle_mgmt/icons/symbol_square_copy.tga")
	ok(it["Reverse line"].tooltip:find("Stop 1 stays first", 1, true))
	ok(it["Duplicate + reverse line"].tooltip:find("opposite order", 1, true))
end)

test("menu: inline styles: header card (nine-patches, 36 px), wrapper paddings, grey wash on disabled rows only", function()
	manager(1, { stop(1), stop(2) })
	local function obj() return {} end
	api.gui.StyleSheet = { new = obj }
	api.gui.NinePatch = { new = obj }
	api.type.Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end }
	api.type.Vec2f = { new = function(a, b) return { a, b } end }
	local res = {
		colors = { BaseVeryLight = { 0.3, 0.3, 0.4, 1 }, NeutralMedium = { 0.5, 0.5, 0.5, 1 } },
		transparency = { Low = 0.75, VeryHigh = 0.1 },
	}
	api.gui.genericRep = {
		find = function(name) return name:find("transparency", 1, true) and "transparency" or "colors" end,
		get = function(id) return { data = res[id] } end,
	}
	local it, m = items()
	local wrap = m.children[1].meta.styleSheet
	eq(wrap.padding, { 8, 8, 1, 8 })
	local card = m.children[1].layout.children[1].meta.styleSheet
	eq(card.size, { -1, 36 })
	eq(card.padding, { 2, 8, 2, 8 })
	eq(card.backgroundColor1, { 0.3, 0.3, 0.4, 0.75 })
	eq(card.backgroundImage1.fileName, "::/gui/entity_window/design/card_surface.tga")
	eq(card.borderImage.fileName, "::/gui/entity_window/design/card_contour.tga")
	eq(m.children[2].meta.styleSheet.padding, { 3, 6, 10, 6 })
	eq(it["Duplicate line"].node.meta.styleSheet, nil)
	eq(it["Reverse line"].node.meta.styleSheet.backgroundColor1, { 0.5, 0.5, 0.5, 0.1 })
	eq(warnings(), 0)
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
	eq(it["Duplicate + reverse line"].enabled, false)
	eq(it["Duplicate + reverse line"].tooltip, "A station of this line no longer exists.")
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

test("reverse: 2 stops -> entry disabled with the 3-stop reason; a click anyway gives it as feedback, no command", function()
	manager(1, { stop(1), stop(2) })
	local it = items()
	ok(it["Duplicate line"].enabled)
	eq(it["Reverse line"].enabled, false)
	eq(it["Reverse line"].tooltip, "Reversing needs at least 3 stops: with 2, the line already runs both ways.")
	it["Reverse line"].onClick()
	eq(#sent, 0)
	eq(feedbacks[1], { "Reversing needs at least 3 stops: with 2, the line already runs both ways.", nil })
end)

test("reverse: a mirror-image route (A, B, C, B) -> enabled, but no command and the same-stops feedback", function()
	manager(1, { stop(1), stop(2), stop(3), stop(2) })
	local it = items()
	ok(it["Reverse line"].enabled)
	it["Reverse line"].onClick()
	eq(#sent, 0)
	eq(feedbacks[1], { "Line Manager Plus: this line visits the same stops in both directions, so reversing doesn't change it.", nil })
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

-- duplicate + reverse -------------------------------------------------------------------------------------------------

test("duplicate + reverse: one create command with the reversed stops and terminals, copy name, new colour", function()
	manager(1, { stop(1, 0, { 10 }), stop(2, 0, { 20 }), stop(3, 0, { 30, 31 }) })
	world.assignment = { { station = 0, terminal = 0 }, { station = 0, terminal = 4 }, { station = -1, terminal = -1 } }
	items()["Duplicate + reverse line"].onClick()
	eq(#sent, 1)
	local c = sent[1].cmd
	eq(c.kind, "create")
	eq(c.name, "Bus 1 (copy)")
	eq(c.color, { x = 0.1, y = 0.2, z = 0.3 })
	eq(c.player, 99)
	local g, t = {}, {}
	for i, st in ipairs(c.comp.stops) do g[i] = st.stationGroup; t[i] = st.terminal end
	eq(g, { 1, 3, 2 })
	eq(t, { 0, 4, 0 })
	eq(c.comp.stops[1].waypoints[1].tag, 31)
	eq(c.comp.stops[3].waypoints[1].tag, 10)
	eq(world.assignCall.line, 7, "terminals asked of the original line")
	eq(#world.modes, 0, "the original line and the editor mode stay")
	sent[1].cb({}, true, { { 42, 1 } })
	eq(selects, { { 42, true, nil } })
	local logged = false
	for _i, e in ipairs(log_entries()) do
		if e.msg:find("duplicated line 7 reversed as 42 (3 stops)", 1, true) then logged = true end
	end
	ok(logged, "log line")
end)

test("duplicate + reverse: 2 stops disabled with the 3-stop reason; mirror route and refusal give feedback", function()
	manager(1, { stop(1), stop(2) })
	local it = items()
	eq(it["Duplicate + reverse line"].enabled, false)
	eq(it["Duplicate + reverse line"].tooltip,
		"Reversing needs at least 3 stops: with 2, the line already runs both ways.")
	it["Duplicate + reverse line"].onClick()
	eq(#sent, 0)
	manager(1, { stop(1), stop(2), stop(3), stop(2) })
	items()["Duplicate + reverse line"].onClick()
	eq(#sent, 0)
	eq(feedbacks[2], { "Line Manager Plus: this line visits the same stops in both directions, so reversing doesn't change it.", nil })
	manager()
	items()["Duplicate + reverse line"].onClick()
	eq(items()["Duplicate line"].enabled, false, "busy while in flight")
	sent[1].cb({}, false, {})
	eq(feedbacks[3], { "Line Manager Plus: the game refused the new line.", "Error" })
	eq(#selects, 0)
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
	eq(actions.ids(), { "duplicate", "reverse", "duplicate_reversed", "set_cargo" })
	eq(actions.build({ params = {} }) ~= nil, true)
end)

-- set cargo for all stops ----------------------------------------------------------------------------------------------
-- cargo ids 0 Passengers, 1 Coal (order 20), 2 Grain (order 10), 3 Goods (order 30, not produced), 4 Logs (order 40)

local stockCalls

-- terminals per group: flags { p, pu, c, cu }; stocks per group: { input = {..}, output = {..} }
local function cargoWorld(terminals, stocks)
	stockCalls = 0
	world.stations = {}
	for g, flags in pairs(terminals) do
		world.groups[g] = { stations = { 100 + g } }
		world.stations[100 + g] = { terminals = { { passengersLoad = flags.p == true,
			passengersUnload = flags.pu == true, cargoLoad = flags.c == true, cargoUnload = flags.cu == true } } }
	end
	local cargo = {
		[0] = { name = "Passengers", icon = "passengers.tga", order = 0 },
		[1] = { name = "Coal", icon = "coal.tga", order = 20 },
		[2] = { name = "Grain", icon = "grain.tga", order = 10 },
		[3] = { name = "Goods", icon = "goods.tga", order = 30 },
		[4] = { name = "Logs", icon = "logs.tga", order = 40 },
	}
	api.res = { cargoTypeRep = {
		getAll = function(inv) eq(inv, true); return { [0] = "PASSENGERS", [1] = "COAL", [2] = "GRAIN", [3] = "GOODS",
			[4] = "LOGS" } end,
		getPassengerCargoTypeId = function() return 0 end,
		get = function(id) return cargo[id] end,
	} }
	api.engine.util.stock = { isCargoTypeCurrentlyProduced = function(id) return id ~= 3 end }
	api.type.ComponentType.STATION = "STATION"
	local getComponent = api.engine.getComponent
	api.engine.getComponent = function(e, ct)
		if ct == "STATION" then return world.stations[e] end
		return getComponent(e, ct)
	end
	local function set(list)
		local t = {}
		for _i, c in ipairs(list or {}) do t[c] = true end
		return t
	end
	stub_module("::/gui/main/cargo_util.tl", {
		getInputOutputStocksForStation = function(station)
			stockCalls = stockCalls + 1
			local sk = stocks[station - 100] or {}
			return set(sk.input), #(sk.input or {}), set(sk.output), #(sk.output or {})
		end,
	})
end

local function cargoStop(group, load, maxLoad)
	local s = stop(group)
	s.loadMode = "LOAD_IF_AVAILABLE"
	s.stopConfig = { load = load or {}, maxLoad = maxLoad or {}, forceUnload = true, destroyForConfigChange = false,
		destroyForRefresh = true }
	return s
end

-- bus stop 1 (passengers), cargo stop 2 (coal + grain in reach, loads coal), cargo stop 3 (logs to unload), bus stop 4
local function cargoLine()
	cargoWorld({ [1] = { p = true, pu = true }, [2] = { c = true, cu = true }, [3] = { cu = true },
		[4] = { p = true, pu = true } },
		{ [2] = { output = { 1, 2 } }, [3] = { input = { 4 } } })
	return manager(1, { cargoStop(1, { true }, { 1 }), cargoStop(2, { false, true }, { 1, 0.5 }), cargoStop(3),
		cargoStop(1) })
end

local function headerText(m)
	return m.children[1].layout.children[1].layout.children[1].text
end

local function openCargoPage()
	renderToolbar().children[1].onValueChange(1)
	items()["Set cargo for all stops"].onClick()
end

test("set cargo: the entry opens a second page in the same popover: Back, Clear all, Passengers, then by order", function()
	cargoLine()
	openCargoPage()
	ok(windows.open, "the menu stays open")
	eq(#windows.removed, 0)
	eq(actions.page(), "set_cargo")
	local it, m, list = items()
	eq(headerText(m), "Set cargo for all stops")
	local texts = {}
	for i, r in ipairs(list) do texts[i] = r.text end
	eq(texts, { "Back", "Clear all", "Passengers", "Grain", "Coal", "Logs" }, "goods: not produced")
	eq(it["Back"].path, "::/gui/menu/icons/back.tga")
	eq(it["Clear all"].path, "::/gui/line_vehicle_mgmt/icons/symbol_trash_bin.tga")
	ok(it["Clear all"].enabled)
	eq(it["Grain"].path, "grain.tga")
	eq(it["Grain"].node.content.layout.children[1].meta.class, "text-icon-size-hack")
	eq(it["Back"].node.content.layout.children[1].meta, nil)
	ok(it["Passengers"].enabled)
	eq(it["Passengers"].tooltip, "Load only Passengers at the 2 of 4 stops that can take it.\nThe other stops stay as they are.")
	-- coal: stop 2 has it in reach and loads only it; stop 3 (a cargo terminal) takes it because stop 2 loads it
	ok(it["Coal"].enabled)
	eq(it["Coal"].tooltip, "Load only Coal at the 2 of 4 stops that can take it.\nThe other stops stay as they are.")
	ok(it["Logs"].enabled)
	eq(stockCalls, 2, "one catchment query per cargo station")
	items()
	eq(stockCalls, 2, "the page's rows are cached")
	clockUs = clockUs + ops.CHOICES_TTL_US
	items()
	eq(stockCalls, 4, "re-read after the TTL")
end)

test("set cargo: Passengers -> one update command; supported stops load only passengers, the others unchanged", function()
	cargoLine()
	local before = world.lines[7]
	openCargoPage()
	items()["Passengers"].onClick()
	eq(windows.removed[#windows.removed], actions.KEY, "menu closed")
	eq(actions.page(), nil)
	eq(#sent, 1)
	local c = sent[1].cmd
	eq(c.kind, "update")
	eq(c.line, 7)
	eq(c.comp.customFilters, true)
	local stops = c.comp.stops
	eq(#stops, 4)
	eq(stops[1].stopConfig.load, { true, false, false, false, false }, "sized to the cargo types")
	eq(stops[1].stopConfig.maxLoad, { 1, 1, 1, 1, 1 })
	eq(stops[4].stopConfig.load, { true, false, false, false, false })
	eq(stops[2].stopConfig.load, { false, true }, "cargo stop: unchanged")
	eq(stops[2].stopConfig.maxLoad, { 1, 0.5 })
	eq(stops[3].stopConfig.load, {})
	eq(stops[1].stopConfig.forceUnload, true)
	eq(stops[1].stopConfig.destroyForConfigChange, false)
	eq(stops[1].loadMode, "LOAD_IF_AVAILABLE")
	eq(world.modes, { { "SEGMENT", nil }, { "SEGMENT", nil } }, "editor mode reset")
	ok(world.lines[7] == before, "the live line is not touched")
	eq(items()["Duplicate line"].enabled, false, "busy while in flight")
	sent[1].cb({}, true)
	eq(#feedbacks, 0)
	ok(items()["Duplicate line"].enabled)
end)

test("set cargo: a freight choice; refusal gives feedback", function()
	cargoLine()
	openCargoPage()
	items()["Logs"].onClick()
	local stops = sent[1].cmd.comp.stops
	eq(stops[3].stopConfig.load, { false, false, false, false, true }, "unloading terminal with logs in its inputs")
	eq(stops[1].stopConfig.load, { true }, "bus stops unchanged")
	eq(stops[2].stopConfig.load, { false, true })
	sent[1].cb({}, false)
	eq(feedbacks[1], { "Line Manager Plus: the game refused the cargo change.", "Error" })
end)

test("set cargo: Clear all clears every stop; disabled when no stop loads anything", function()
	cargoLine()
	openCargoPage()
	items()["Clear all"].onClick()
	local stops = sent[1].cmd.comp.stops
	for k = 1, 4 do
		for _i, v in ipairs(stops[k].stopConfig.load) do eq(v, false) end
	end
	eq(#stops[1].stopConfig.load, 5)
	eq(stops[2].stopConfig.maxLoad, { 1, 0.5, 1, 1, 1 })
	eq(sent[1].cmd.comp.customFilters, true)
	sent[1].cb({}, true)

	world.lines[7] = sent[1].cmd.comp
	openCargoPage()
	local it = items()
	eq(it["Clear all"].enabled, false)
	eq(it["Clear all"].tooltip, "No stop of this line has a cargo selected.")
	-- a click anyway (state changed between render and click): no command, a feedback line
	it["Clear all"].onClick()
	eq(#sent, 1)
	eq(feedbacks[1], { "Line Manager Plus: the stops already have this cargo selection.", nil })
end)

test("set cargo: Back returns to the entries; reopening starts there; hint rows send nothing", function()
	cargoWorld({ [1] = {}, [2] = {}, [3] = {} }, {})
	manager()
	openCargoPage()
	local it, m = items()
	eq(it["No cargo type fits these stops"].enabled, false)
	ok(it["No cargo type fits these stops"].tooltip:find("No stop has a terminal", 1, true))
	it["No cargo type fits these stops"].onClick()
	eq(#sent, 0)
	openCargoPage()
	it, m = items()
	it["Back"].onClick()
	eq(actions.page(), nil)
	ok(windows.open, "still open")
	it, m = items()
	eq(headerText(m), "Line actions")
	ok(it["Set cargo for all stops"])
	actions.openPage("set_cargo")
	renderToolbar().children[1].onValueChange(0)
	renderToolbar().children[1].onValueChange(1)
	eq(actions.page(), nil, "a new menu starts at the entries")
	eq(headerText(select(2, items())), "Line actions")
end)

test("set cargo: while a command is in flight the page shows one disabled reason row", function()
	cargoLine()
	openCargoPage()
	ops.setCargo({ params = makeParams(7), line = 7 }, 0)
	eq(#sent, 1)
	clockUs = clockUs + ops.CHOICES_TTL_US
	local _it, _m, list = items()
	eq(#list, 2)
	eq(list[2].text, "A change to this line is still in progress.")
	eq(list[2].enabled, false)
end)

test("set cargo: a failing choices list shows only Back and warns once; a failing choose gives feedback", function()
	manager()
	actions.register({ id = "pick", order = 500, label = "Broken entry",
		view = function() return { enabled = true } end,
		choices = function() error("c boom") end, choose = function() error("x boom") end })
	renderToolbar().children[1].onValueChange(1)
	items()["Broken entry"].onClick()
	local _it, _m, list = items()
	eq(#list, 1)
	eq(list[1].text, "Back")
	items()
	eq(warnings("c boom"), 1)
	actions.runChoice("pick", 1)
	eq(feedbacks[1], { "Line Manager Plus: the line action failed (see log).", "Error" })
	eq(warnings("x boom"), 1)
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

test("with the undo feature installed, a cargo change is one Undo step that restores every stop's selection", function()
	local undo = ug_require "square_line_manager_plus::/line_manager_plus/undo.lua"
	ok(undo.install({}))
	cargoLine()
	local original = world.lines[7]
	renderToolbar() -- undo session starts with the original line
	openCargoPage()
	items()["Passengers"].onClick()
	world.lines[7] = sent[1].cmd.comp
	sent[1].cb({}, true)
	local _btn, row = renderToolbar()
	local undoBtn = row.children[1].children[1]
	ok(undoBtn.meta.enabled)
	ok(undoBtn.meta.tooltip:find("2 stops changed", 1, true), undoBtn.meta.tooltip)
	undoBtn.onClick()
	eq(#sent, 2)
	for k = 1, 4 do eq(sent[2].cmd.comp.stops[k].stopConfig.load, original.stops[k].stopConfig.load) end
end)
