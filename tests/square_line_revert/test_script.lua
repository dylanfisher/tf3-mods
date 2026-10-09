-- line_revert.script.lua with fake react / builtin / line_util / button_react_util and a fake api.
-- Covers: data() exports, wrapper install + chaining, the icon button only next to A+ in LinePanelActionButtons,
-- history start on first step, enabled state, session reset, undo / revert-all commands, our own undo not
-- recorded, failed commands, missing-station feedback, the editor-mode reset (crash regression), and redo (second
-- icon button, redo stack cleared by an edit or a new session, revert-all then redo step by step).

local AUTO_RENAME = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"

local world, sent, feedbacks, recipeName, origToggleCalls, shift
local react, builtin, line_util, button_react_util, script

local function stop(group, station)
	return {
		stationGroup = group, station = station or 0, terminal = 0, alternativeTerminals = {},
		loadMode = 0, minWaitingTime = 0, maxWaitingTime = 600, maxAdditionalWaitingTime = 30,
		waypoints = {}, stopConfig = { load = { true }, maxLoad = { 1 }, forceUnload = false,
			destroyForConfigChange = false, destroyForRefresh = false },
	}
end

local function lineComp(groups)
	local stops = {}
	for i, g in ipairs(groups) do stops[i] = stop(g) end
	return { stops = stops, customFilters = false, reservationPriority = 0 }
end

local function state(v) return { old = function() return v.value end, get = function() return v.value end } end

-- commonParams as the manager hands them to makeLineActionDescriptor
local function makeParams(lineEntity, selected)
	local ls = { value = { entityAndRevision = { entity = lineEntity } } }
	local sel = {}
	for i = 1, selected or 1 do sel[i] = { entity = lineEntity } end
	local p = {
		_ls = ls,
		lineState = state(ls),
		lineManagerStateRef = state({ value = { lineListEntitiesSelected = sel } }),
		gameCtx = { filters = state({ value = { protectedEntities = {} } }) },
		addFeedback = function(msg, mode) feedbacks[#feedbacks + 1] = { msg, mode } end,
	}
	return p
end

local function ctor(name)
	return { new = function(...)
		local o = { _type = name }
		if name == "StationTerminal" then o.station, o.terminal = ... end
		if name == "EdgeId" then o.entity, o.index = ... end
		if name == "Vec3f" then o.x, o.y, o.z = ... end
		return o
	end }
end

before_each(function()
	reset_modules()
	clear_logs()
	world = { lines = {}, groups = {} }
	sent, feedbacks, origToggleCalls, shift = {}, {}, 0, false
	recipeName = "LinePanelActionButtons"

	local Line = ctor("Line")
	Line.Stop = ctor("Stop")
	Line.StopConfig = ctor("StopConfig")
	set_global("api", {
		engine = {
			entityExists = function(e) return world.lines[e] ~= nil or world.groups[e] ~= nil end,
			getComponent = function(e, ct)
				if ct == "LINE" then return world.lines[e] end
				if ct == "STATION_GROUP" then return world.groups[e] end
			end,
		},
		type = {
			ComponentType = { LINE = "LINE", STATION_GROUP = "STATION_GROUP" },
			Line = Line, StationTerminal = ctor("StationTerminal"), Waypoint = ctor("Waypoint"),
			EdgePos = ctor("EdgePos"), EdgeId = ctor("EdgeId"), Vec3f = ctor("Vec3f"),
		},
		gui = { inputAction = { modifierOnlyActionIsActive = function(ia)
			if ia ~= "IA_PRECISION_MODE" then error("unexpected input action " .. tostring(ia)) end
			return shift
		end } },
		cmd = {
			makeLineUpdateCmd = function(line, comp) return { line = line, comp = comp } end,
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
		},
	})

	react = {
		getCurrentRecipeName = function() return recipeName end,
		-- a recipe is called as Recipe{params}; here it renders at once, each call = one step
		RegisterRecipe = function(_name, fn) return function(p) return fn(p or {}) end end,
	}
	builtin = {
		type = { Orientation = { Horizontal = "H" }, ImageViewScaling = { AutoFit = "AutoFit" } },
		BoxLayout = function(p) return { kind = "BoxLayout", children = p.children } end,
		Button = function(p) return { kind = "Button", meta = p.meta, onClick = p.onClick, content = p.content } end,
		ImageView = function(p)
			-- only fields of Builtin.ImageViewParam; mouseTransparent in particular crashes the game (memory note)
			for k in pairs(p) do
				if k ~= "path" and k ~= "scaling" then error("unexpected ImageView field " .. tostring(k)) end
			end
			return { kind = "ImageView", path = p.path, scaling = p.scaling }
		end,
	}
	local engine_react_util = {
		useStepState = function(get) local v = get(); return { old = function() return v end } end,
	}
	button_react_util = {
		makeIconToggleButton = function(class, path)
			origToggleCalls = origToggleCalls + 1
			return { kind = "Toggle", class = class, path = path }
		end,
	}
	line_util = {
		makeLineActionDescriptor = function(cp, x) return { cp = cp, x = x } end,
		isStopProtected = function(line, _g, protected) return protected[line] == true end,
	}
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/engine_react_util.tl", engine_react_util)
	stub_module("::/gui/main/button_react_util.tl", button_react_util)
	stub_module("::/gui/line_vehicle_mgmt/line_util.tl", line_util)

	ug_require "square_line_revert::/line_revert/line_revert.script.lua"
	script = data()
	script.doReplace({})
end)

-- render the A+ button through the wrapper; returns our Button node (or nil) and the whole node
local function renderAPlus()
	local node = button_react_util.makeIconToggleButton("vehicle-button, secondary", AUTO_RENAME, function() end, "tip")
	if node.kind ~= "BoxLayout" then return nil, node end
	local inner = node.children[1].children[1]
	return inner, node
end

-- the redo Button node (second child of the wrapper: [Undo, Redo, A+])
local function renderRedo()
	local node = button_react_util.makeIconToggleButton("vehicle-button, secondary", AUTO_RENAME, function() end, "tip")
	if node.kind ~= "BoxLayout" then return nil end
	return node.children[2].children[1]
end

-- the engine applies sent command i (the built Line becomes the live LINE component), then calls back
local function apply(i, success)
	if success ~= false then world.lines[sent[i].cmd.line] = sent[i].cmd.comp end
	sent[i].cb(nil, success ~= false)
end

local function groupsOf(comp)
	local out = {}
	for i, s in ipairs(comp.stops) do out[i] = s.stationGroup end
	return out
end

local function addGroups(...)
	for _i, g in ipairs({ ... }) do world.groups[g] = { stations = { g * 10 } } end
end

test("data() exports doReplace and the recipe; wrappers installed and chained", function()
	ok(type(script.doReplace) == "function")
	ok(type(script.LineRevertButton) == "function")
	local p = makeParams(1)
	local r = line_util.makeLineActionDescriptor(p, 42)
	eq(r.x, 42)
	ok(r.cp == p)
	-- other icons pass through untouched
	local other = button_react_util.makeIconToggleButton("c", "::/other.tga")
	eq(other.kind, "Toggle")
	-- a second doReplace doesn't stack wrappers
	script.doReplace({})
	button_react_util.makeIconToggleButton("c", "::/other.tga")
	eq(origToggleCalls, 2)
end)

test("no button before commonParams are captured, or outside LinePanelActionButtons", function()
	world.lines[1] = lineComp({ 10, 20 })
	eq(renderAPlus(), nil)
	line_util.makeLineActionDescriptor(makeParams(1))
	recipeName = "LineManagerActionButtons"
	local btn, node = renderAPlus()
	eq(btn, nil)
	eq(node.kind, "Toggle")
end)

test("button left of A+, disabled until the line changes, then enabled with a diff", function()
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	local btn, node = renderAPlus()
	eq(btn.kind, "Button")
	eq(btn.content.kind, "ImageView")
	eq(btn.content.path, "::/gui/node_editor/icons/undo.tga")
	eq(btn.content.scaling, "AutoFit")
	eq(btn.meta.class, "vehicle-button, secondary")
	eq(btn.meta.enabled, false)
	eq(node.children[3].path, AUTO_RENAME)
	world.lines[1] = lineComp({ 10 })
	btn = renderAPlus()
	eq(btn.meta.enabled, true)
	ok(btn.meta.tooltip:find("Undo: 1 stop removed (1 change since you opened this line).", 1, true))
	ok(btn.meta.tooltip:find("Shift+click: revert all.", 1, true))
end)

test("hidden with several lines selected or a protected line", function()
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1, 2))
	local btn, node = renderAPlus()
	eq(node.kind, "BoxLayout")
	eq(node.children[1].children, {})
	local p = makeParams(1)
	p.gameCtx.filters = state({ value = { protectedEntities = { [1] = true } } })
	line_util.makeLineActionDescriptor(p)
	btn, node = renderAPlus()
	eq(node.children[1].children, {})
end)

test("undo sends makeLineUpdateCmd with the previous state; a refusal reports an error", function()
	world.groups[10] = { stations = { 100 } }
	world.groups[20] = { stations = { 200 } }
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus() -- snapshot
	world.lines[1] = lineComp({ 20 })
	local btn = renderAPlus()
	btn.onClick()
	eq(#sent, 1)
	eq(sent[1].cmd.line, 1)
	local comp = sent[1].cmd.comp
	eq(comp._type, "Line")
	eq(#comp.stops, 2)
	eq(comp.stops[1].stationGroup, 10)
	eq(comp.stops[2].stationGroup, 20)
	sent[1].cb(nil, false)
	eq(#feedbacks, 1)
	eq(feedbacks[1][2], "Error")
	sent[1].cb(nil, true)
	eq(#feedbacks, 1)
end)

test("a demolished station in the snapshot: no command, error feedback", function()
	world.groups[10] = { stations = { 100 } }
	world.groups[20] = { stations = { 200 } }
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	world.groups[20] = nil
	world.lines[1] = lineComp({ 10 })
	renderAPlus().onClick()
	eq(#sent, 0)
	eq(#feedbacks, 1)
	ok(feedbacks[1][1]:find("1 station", 1, true))
end)

test("session resets when the edited line changes and for a new manager window", function()
	world.lines[1] = lineComp({ 10, 20 })
	world.lines[2] = lineComp({ 30 })
	local p = makeParams(1)
	line_util.makeLineActionDescriptor(p)
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	eq(renderAPlus().meta.enabled, true)
	-- switch to line 2 and back: line 1's new state becomes the snapshot
	p._ls.value = { entityAndRevision = { entity = 2 } }
	eq(renderAPlus().meta.enabled, false)
	p._ls.value = { entityAndRevision = { entity = 1 } }
	eq(renderAPlus().meta.enabled, false)
	-- new manager window (new commonParams table), same line: new session
	world.lines[1] = lineComp({ 10, 20 })
	eq(renderAPlus().meta.enabled, true)
	line_util.makeLineActionDescriptor(makeParams(1))
	eq(renderAPlus().meta.enabled, false)
end)

test("errors in the view fall back to a hidden button, not a crash", function()
	world.lines[1] = lineComp({ 10 })
	local p = makeParams(1)
	p.lineState = { old = function() error("boom") end }
	line_util.makeLineActionDescriptor(p)
	local _btn, node = renderAPlus()
	eq(node.children[1].children, {})
	eq(node.children[3].path, AUTO_RENAME)
end)

test("undo resets a stale editor segment to the end of the line (addWaypoint crash)", function()
	world.groups[10] = { stations = { 100 } }
	world.groups[20] = { stations = { 200 } }
	world.groups[30] = { stations = { 300 } }
	world.lines[1] = lineComp({ 10, 20 })
	local p = makeParams(1)
	local mode = { "SEGMENT", 3 }
	local switches = {}
	p.getModeState = function() return mode end
	p.switchMode = function(m) switches[#switches + 1] = m; mode = m end
	line_util.makeLineActionDescriptor(p)
	renderAPlus() -- snapshot
	world.lines[1] = lineComp({ 10, 20, 30 })
	renderAPlus().onClick()
	eq(#sent, 1)
	eq(#switches, 2) -- twice, so the stale mode is not kept as "previous"
	eq(mode[1], "SEGMENT")
	eq(mode[2], nil)
	apply(1)
	eq(groupsOf(world.lines[1]), { 10, 20 })
	-- MAIN mode is left alone
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	switches = {}
	mode = { "MAIN", nil }
	renderAPlus().onClick()
	eq(#sent, 2)
	eq(#switches, 0)
end)

test("each edit is one undo step; undo pops one step at a time", function()
	addGroups(10, 20, 30, 40)
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus() -- history[1]
	world.lines[1] = lineComp({ 10, 20, 30 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 20, 30, 40 })
	local btn = renderAPlus()
	ok(btn.meta.tooltip:find("Undo: 1 stop added (2 changes since", 1, true))
	btn.onClick()
	eq(#sent, 1)
	eq(groupsOf(sent[1].cmd.comp), { 10, 20, 30 })
	-- in flight: disabled, the old live state isn't recorded
	btn = renderAPlus()
	eq(btn.meta.enabled, false)
	apply(1)
	btn = renderAPlus()
	eq(btn.meta.enabled, true)
	ok(btn.meta.tooltip:find("(1 change since", 1, true))
	btn.onClick()
	eq(groupsOf(sent[2].cmd.comp), { 10, 20 })
	apply(2)
	btn = renderAPlus()
	eq(btn.meta.enabled, false)
	eq(#sent, 2)
	-- nothing left: a click sends nothing
	btn.onClick()
	eq(#sent, 2)
end)

test("an edit after the last step is recorded at click time and undone first", function()
	addGroups(10, 20, 30)
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	local btn = renderAPlus()
	world.lines[1] = lineComp({ 10, 30 }) -- not seen by a step yet
	btn.onClick()
	eq(groupsOf(sent[1].cmd.comp), { 10 })
end)

test("our own undo is not recorded; a user edit before it lands is", function()
	addGroups(10, 20, 30, 50)
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 30 })
	renderAPlus().onClick()
	apply(1)
	local btn = renderAPlus()
	ok(btn.meta.tooltip:find("(1 change since", 1, true))
	-- second undo, but the user edits before the engine applies it
	btn.onClick()
	world.lines[1] = lineComp({ 50 })
	btn = renderAPlus()
	eq(btn.meta.enabled, true)
	ok(btn.meta.tooltip:find("(1 change since", 1, true))
	ok(btn.meta.tooltip:find("Undo: 2 stops removed, 1 stop added", 1, true))
	btn.onClick()
	eq(groupsOf(sent[3].cmd.comp), { 10, 20 })
end)

test("a failed undo command restores the entry and reports it", function()
	addGroups(10, 20, 30)
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 30 })
	renderAPlus().onClick()
	apply(1, false)
	eq(#feedbacks, 1)
	eq(feedbacks[1][2], "Error")
	local btn = renderAPlus()
	eq(btn.meta.enabled, true)
	ok(btn.meta.tooltip:find("(2 changes since", 1, true))
	btn.onClick()
	eq(groupsOf(sent[2].cmd.comp), { 10 })
end)

test("shift+click reverts all and leaves only the first entry", function()
	addGroups(10, 20, 30, 40)
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 30 })
	renderAPlus()
	world.lines[1] = lineComp({ 40, 10, 30 })
	shift = true
	renderAPlus().onClick()
	eq(#sent, 1)
	eq(groupsOf(sent[1].cmd.comp), { 10, 20 })
	apply(1)
	local btn = renderAPlus()
	eq(btn.meta.enabled, false)
	btn.onClick()
	eq(#sent, 1)
	-- later edits undo back to the same start
	shift = false
	world.lines[1] = lineComp({ 20 })
	renderAPlus().onClick()
	eq(groupsOf(sent[2].cmd.comp), { 10, 20 })
end)

test("shift detection failing falls back to a plain undo", function()
	addGroups(10, 20, 30)
	api.gui.inputAction.modifierOnlyActionIsActive = function() error("not on this thread") end
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 30 })
	renderAPlus().onClick()
	eq(groupsOf(sent[1].cmd.comp), { 10 })
	eq(#feedbacks, 0)
end)

test("history is capped at 50 entries; shift+click still reaches the start", function()
	world.lines[1] = lineComp({ 1 })
	addGroups(1)
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	for i = 1, 60 do
		world.lines[1] = lineComp({ 1, 100 + i })
		renderAPlus()
	end
	local btn = renderAPlus()
	ok(btn.meta.tooltip:find("(60 changes since", 1, true))
	shift = true
	btn.onClick()
	eq(groupsOf(sent[1].cmd.comp), { 1 })
end)

test("a missing station in the undo target: nothing sent, history kept", function()
	addGroups(10, 20)
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	world.groups[20] = nil
	local btn = renderAPlus()
	btn.onClick()
	eq(#sent, 0)
	eq(#feedbacks, 1)
	eq(renderAPlus().meta.enabled, true)
end)

test("session reset clears the history", function()
	addGroups(10, 20, 30)
	world.lines[1] = lineComp({ 10, 20 })
	world.lines[2] = lineComp({ 30 })
	local p = makeParams(1)
	line_util.makeLineActionDescriptor(p)
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 30 })
	eq(renderAPlus().meta.enabled, true)
	p._ls.value = { entityAndRevision = { entity = 2 } }
	renderAPlus()
	p._ls.value = { entityAndRevision = { entity = 1 } }
	local btn = renderAPlus()
	eq(btn.meta.enabled, false)
	shift = true
	btn.onClick()
	eq(#sent, 0)
end)

-- Redo ---------------------------------------------------------------------------------------------------------

-- number of "edit <n> on line" log lines (one per recorded user edit)
local function editLogs()
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.msg:find("] edit ", 1, true) then n = n + 1 end
	end
	return n
end

-- line 1 opened as {10, 20}, then edited to {10}, {10, 30}, {10, 30, 40}; every group exists
local function threeEdits(params)
	addGroups(10, 20, 30, 40)
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(params or makeParams(1))
	renderAPlus()
	world.lines[1] = lineComp({ 10 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 30 })
	renderAPlus()
	world.lines[1] = lineComp({ 10, 30, 40 })
	renderAPlus()
end

test("both icons render in order [Undo, Redo, A+], same class; redo disabled until an undo", function()
	threeEdits()
	local _undo, node = renderAPlus()
	eq(#node.children, 3)
	local undo, redo = node.children[1].children[1], node.children[2].children[1]
	eq(undo.content.path, "::/gui/node_editor/icons/undo.tga")
	eq(redo.kind, "Button")
	eq(redo.content.kind, "ImageView")
	eq(redo.content.path, "::/gui/node_editor/icons/redo.tga")
	eq(redo.content.scaling, "AutoFit")
	eq(redo.meta.class, undo.meta.class)
	eq(node.children[3].path, AUTO_RENAME)
	eq(redo.meta.enabled, false)
	eq(redo.meta.tooltip, "Redo: nothing to redo")
	redo.onClick()
	eq(#sent, 0)
	-- hidden together with undo
	line_util.makeLineActionDescriptor(makeParams(1, 2))
	_undo, node = renderAPlus()
	eq(node.children[2].children, {})
end)

test("undo then redo restores the state; redo enabled with a diff tooltip, disabled in flight", function()
	threeEdits()
	renderAPlus().onClick()
	-- both buttons disabled while the undo is in flight
	eq(renderRedo().meta.enabled, false)
	eq(renderAPlus().meta.enabled, false)
	apply(1)
	local redo = renderRedo()
	eq(redo.meta.enabled, true)
	eq(redo.meta.tooltip, "Redo: 1 stop added (0 more)")
	redo.onClick()
	eq(#sent, 2)
	eq(groupsOf(sent[2].cmd.comp), { 10, 30, 40 })
	eq(renderRedo().meta.enabled, false)
	eq(renderAPlus().meta.enabled, false)
	apply(2)
	eq(renderRedo().meta.enabled, false)
	local undo = renderAPlus()
	eq(undo.meta.enabled, true)
	ok(undo.meta.tooltip:find("Undo: 1 stop added (3 changes since", 1, true))
end)

test("several undo / redo steps walk the history both ways", function()
	threeEdits()
	for i = 1, 3 do
		renderAPlus().onClick()
		apply(i)
	end
	eq(groupsOf(world.lines[1]), { 10, 20 })
	eq(renderAPlus().meta.enabled, false)
	ok(renderRedo().meta.tooltip:find("(2 more)", 1, true))
	renderRedo().onClick(); apply(4)
	eq(groupsOf(world.lines[1]), { 10 })
	renderRedo().onClick(); apply(5)
	eq(groupsOf(world.lines[1]), { 10, 30 })
	-- undo in the middle, then redo twice
	renderAPlus().onClick(); apply(6)
	eq(groupsOf(world.lines[1]), { 10 })
	renderRedo().onClick(); apply(7)
	renderRedo().onClick(); apply(8)
	eq(groupsOf(world.lines[1]), { 10, 30, 40 })
	eq(renderRedo().meta.enabled, false)
	ok(renderAPlus().meta.tooltip:find("(3 changes since", 1, true))
	-- no edit was recorded from our own commands
	eq(editLogs(), 3)
end)

test("an edit after undo clears redo", function()
	threeEdits()
	renderAPlus().onClick(); apply(1)
	renderAPlus().onClick(); apply(2)
	eq(renderRedo().meta.enabled, true)
	world.lines[1] = lineComp({ 10, 40 })
	local redo = renderRedo()
	eq(redo.meta.enabled, false)
	redo.onClick()
	eq(#sent, 2)
	-- an edit not yet seen by a step is recorded at click time, so redo sends nothing
	renderAPlus().onClick(); apply(3)
	eq(renderRedo().meta.enabled, true)
	world.lines[1] = lineComp({ 30 })
	renderRedo().onClick()
	eq(#sent, 3)
end)

test("revert all then redo steps forward one state at a time", function()
	threeEdits()
	shift = true
	renderAPlus().onClick(); apply(1)
	shift = false
	eq(groupsOf(world.lines[1]), { 10, 20 })
	ok(renderRedo().meta.tooltip:find("Redo: 1 stop removed (2 more)", 1, true))
	renderRedo().onClick(); apply(2)
	eq(groupsOf(world.lines[1]), { 10 })
	renderRedo().onClick(); apply(3)
	eq(groupsOf(world.lines[1]), { 10, 30 })
	renderRedo().onClick(); apply(4)
	eq(groupsOf(world.lines[1]), { 10, 30, 40 })
	eq(renderRedo().meta.enabled, false)
	-- shift on the redo button is ignored: still one step
	renderAPlus().onClick(); apply(5)
	shift = true
	renderRedo().onClick(); apply(6)
	eq(groupsOf(world.lines[1]), { 10, 30, 40 })
end)

test("a failed redo command restores both stacks and reports it", function()
	threeEdits()
	renderAPlus().onClick(); apply(1)
	renderAPlus().onClick(); apply(2)
	renderRedo().onClick()
	apply(3, false)
	eq(#feedbacks, 1)
	eq(feedbacks[1][2], "Error")
	ok(feedbacks[1][1]:find("redo", 1, true))
	local redo = renderRedo()
	eq(redo.meta.enabled, true)
	ok(redo.meta.tooltip:find("(1 more)", 1, true))
	ok(renderAPlus().meta.tooltip:find("(1 change since", 1, true))
	redo.onClick()
	eq(groupsOf(sent[4].cmd.comp), { 10, 30 })
end)

test("our own redo is not recorded as an edit; a user edit before it lands is", function()
	threeEdits()
	renderAPlus().onClick(); apply(1)
	renderAPlus().onClick(); apply(2)
	clear_logs()
	renderRedo().onClick()
	-- not applied yet: the old live state is ignored, redo stays pending
	renderAPlus()
	apply(3)
	renderAPlus()
	eq(editLogs(), 0)
	local redo = renderRedo()
	eq(redo.meta.enabled, true) -- one redo left, not cleared by our own command
	ok(renderAPlus().meta.tooltip:find("(2 changes since", 1, true))
	-- second redo, but the user edits before it lands: recorded on top of the redone state, redo cleared
	redo.onClick()
	world.lines[1] = lineComp({ 40 })
	eq(renderRedo().meta.enabled, false)
	eq(editLogs(), 1)
	ok(renderAPlus().meta.tooltip:find("(4 changes since", 1, true))
end)

test("the redo target with a demolished station: nothing sent, redo kept", function()
	threeEdits()
	renderAPlus().onClick(); apply(1)
	world.groups[40] = nil
	renderRedo().onClick()
	eq(#sent, 1)
	eq(#feedbacks, 1)
	eq(renderRedo().meta.enabled, true)
end)

test("redo resets a stale editor segment like undo", function()
	local params = makeParams(1)
	local mode = { "MAIN", nil }
	local switches = 0
	params.getModeState = function() return mode end
	params.switchMode = function(m) switches = switches + 1; mode = m end
	threeEdits(params)
	renderAPlus().onClick(); apply(1)
	mode, switches = { "SEGMENT", 5 }, 0
	renderRedo().onClick()
	eq(#sent, 2)
	eq(switches, 2)
	eq(mode[1], "SEGMENT")
	eq(mode[2], nil)
end)

test("session reset clears redo", function()
	threeEdits()
	renderAPlus().onClick(); apply(1)
	eq(renderRedo().meta.enabled, true)
	-- new manager window, same line
	line_util.makeLineActionDescriptor(makeParams(1))
	eq(renderRedo().meta.enabled, false)
	renderRedo().onClick()
	eq(#sent, 1)
end)

test("one line read per step for both buttons; the tooltip diff is computed once per state pair", function()
	world.lines[1] = lineComp({ 10, 20 })
	line_util.makeLineActionDescriptor(makeParams(1))
	renderAPlus() -- session start
	local reads = 0
	local get = api.engine.getComponent
	api.engine.getComponent = function(e, ct)
		if ct == "LINE" then reads = reads + 1 end
		return get(e, ct)
	end
	world.lines[1] = lineComp({ 10 })
	local _btn, node = renderAPlus() -- one step: Undo then Redo
	eq(reads, 1)
	eq(node.children[1].children[1].meta.enabled, true)
	eq(node.children[2].children[1].meta.enabled, false)
	local core = ug_require "square_line_revert::/line_revert/line_revert_core.lua"
	local diffs = 0
	local diff = core.diffSummary
	core.diffSummary = function(a, b) diffs = diffs + 1; return diff(a, b) end
	for _i = 1, 5 do renderAPlus() end
	eq(diffs, 0)
	core.diffSummary = diff
	api.engine.getComponent = get
end)
