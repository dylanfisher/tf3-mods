-- bulk_bulldozer.script: the BulkBulldozerAction recipe's right click and close handling
-- (user feedback 2026-10-07). A fake react runs the recipe: hooks by call order, mount/unmount
-- and step handlers kept, the world layer (actionFn) captured through setActionFn.

local T = { Pressed = "Pressed", Released = "Released", Clicked = "Clicked", Moved = "Moved",
	Wheel = "Wheel", DoubleClicked = "DoubleClicked", Entered = "Entered", Exited = "Exited",
	PressedOutside = "PressedOutside" }

local fired
local shiftDown   -- what api.gui.inputAction reports for IA_PRECISION_MODE

local function fakeReact()
	local h = { states = {}, refs = {}, events = {}, steps = {}, mounts = {}, unmounts = {}, inputs = {} }
	h.react = {
		useState = function(init)
			local st = { v = init }
			function st:old() return self.v end
			function st:set(v) self.v = v end
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
		onMount = function(fn) h.mounts[#h.mounts + 1] = fn end,
		onUnmount = function(fn) h.unmounts[#h.unmounts + 1] = fn end,
		setForceFocusable = function() end,
		setRestrictMouseFocus = function() end,
		useInputAction = function(name, fn) h.inputs[name] = fn end,
		iaHandler = function(fn) return fn end,
	}
	return h
end

local function node(kind) return function(p) return { builtin = kind, param = p } end end

local h, reg, script, sel

before_each(function()
	reset_modules()
	fired = {}
	shiftDown = false
	h = fakeReact()
	reg = {}
	h.react.RegisterRecipe = function(name, fn)
		reg[name] = fn
		return setmetatable({ name = name }, { __call = function(_s, p) return { recipe = name, param = p } end })
	end
	stub_module("::/gui/main/react.lua", h.react)
	stub_module("::/gui/main/builtin.lua", {
		BoxLayout = node("BoxLayout"), TextView = node("TextView"), Selector = node("Selector"),
		ActionDescriptor = node("ActionDescriptor"), ActionTooltip = node("ActionTooltip"),
		EdgeRenderable = node("EdgeRenderable"),
		type = { Orientation = { Horizontal = "Horizontal", Vertical = "Vertical" } },
	})
	stub_module("::/gui/construction/construction_react_util.tl", {})
	set_global("api", {
		type = {
			enum = {
				ScriptParamType = { Slider = "Slider", Button = "Button", CheckBox = "CheckBox" },
				ScriptParamLocation = { Toolbar = "Toolbar" },
			},
			ComponentType = { PLAYER = "PLAYER", PLAYER_OWNED = "PLAYER_OWNED" },
			Vec4f = { new = function(r, g, b, a) return { r, g, b, a } end },
		},
		gui = {
			fireReactEvent = function(name, payload) fired[#fired + 1] = { name = name, payload = payload } end,
			mouse = { Event = { Type = T }, hasTerrainPosition = function() return false end },
			inputAction = { modifierOnlyActionIsActive = function(ia)
				return ia == "IA_PRECISION_MODE" and shiftDown
			end },
		},
		engine = {
			util = { getPlayer = function() return 1 end },
			getComponent = function() return nil end,
		},
	})
	script = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bulk_bulldozer.script.tl"
	sel = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl"
end)

-- Renders the action recipe once with isActive; returns the param (actionFn in param.actionFn).
local function render(param)
	h.refs, h.states, h.steps, h.mounts, h.unmounts = {}, {}, {}, {}, {}
	reg["BulkBulldozerAction"](param)
	return param
end

local function newParam(active)
	local p = { isActive = active }
	p.setActionFn = function(fn) p.actionFn = fn end
	p.getCurrentParams = function() return {} end
	p.abort = function() p.aborted = true end
	return p
end

-- Mouse handler of the world layer's Selector.
local function mouseHandler(p)
	local tree = p.actionFn()
	return tree.param.children[1].param.onProcessMouseEvent, tree
end

-- The Selection held by the recipe (the ref whose value has a stroke), or nil.
local function selection()
	for _, r in ipairs(h.refs) do
		local v = r:get()
		if type(v) == "table" and v.stroke ~= nil then return v end
	end
end

-- LMB press, then one kept road in the stroke, then LMB release: a selection waiting for Bulldoze.
local function paintOne(onMouse)
	onMouse({ type = T.Pressed, button = 0, x = 10, y = 10, handled = false })
	local s = selection()
	ok(s ~= nil, "press starts a selection")
	sel.add(s.stroke, { entity = 4242, kind = "road", objects = 0 })
	onMouse({ type = T.Released, button = 0, x = 10, y = 10, handled = false })
	s = selection()
	ok(s ~= nil and s.phase == "selected", "selection waits for the button")
end

test("shift stroke: removes from a waiting selection and keeps the rest", function()
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	paintOne(onMouse)
	local s = selection()
	sel.add(s.stroke, { entity = 4343, kind = "track", objects = 0 })
	shiftDown = true
	onMouse({ type = T.Pressed, button = 0, x = 10, y = 10, handled = false })
	s = selection()
	eq(s.phase, "painting")
	eq(s.erasing, true, "Shift at the press makes an erase stroke")
	sel.remove(s.stroke, { 4242 })   -- what a brush sample over the road does
	onMouse({ type = T.Released, button = 0, x = 10, y = 10, handled = false })
	s = selection()
	eq(s.phase, "selected", "the rest still waits for Bulldoze")
	eq(s.erasing, false)
	eq(sel.entities(s.stroke), { 4343 })
	-- erasing everything ends the selection
	onMouse({ type = T.Pressed, button = 0, x = 10, y = 10, handled = false })
	sel.remove(selection().stroke, { 4343 })
	onMouse({ type = T.Released, button = 0, x = 10, y = 10, handled = false })
	eq(selection(), nil, "empty after erasing: back to the hover preview")
end)

test("shift stroke: with nothing selected it selects nothing", function()
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	shiftDown = true
	onMouse({ type = T.Pressed, button = 0, x = 10, y = 10, handled = false })
	eq(selection().erasing, true)
	onMouse({ type = T.Released, button = 0, x = 10, y = 10, handled = false })
	eq(selection(), nil)
end)

test("shift stroke: a plain stroke after it adds again", function()
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	paintOne(onMouse)
	eq(selection().erasing, false, "no Shift: adds")
end)

test("right click: Clicked (the event that arrives in game) clears a waiting selection", function()
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	paintOne(onMouse)
	-- In game only PressedOutside + Clicked of button 2 arrive (log 2026-10-07).
	eq(onMouse({ type = T.PressedOutside, button = 2, x = 300, y = 200, handled = false }), false)
	eq(onMouse({ type = T.Clicked, button = 2, x = 303, y = 198, handled = false }), true)
	eq(selection(), nil, "selection cleared")
	-- A second release event (Released after Clicked) finds nothing pending.
	eq(onMouse({ type = T.Released, button = 2, x = 303, y = 198, handled = false }), false)
end)

test("right click: a drag (camera) keeps the selection", function()
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	paintOne(onMouse)
	onMouse({ type = T.PressedOutside, button = 2, x = 300, y = 200, handled = false })
	eq(onMouse({ type = T.Clicked, button = 2, x = 420, y = 200, handled = false }), false)
	ok(selection() ~= nil, "selection kept after a drag")
end)

test("right click: Pressed + Released also clear (if the engine ever delivers them)", function()
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	paintOne(onMouse)
	eq(onMouse({ type = T.Pressed, button = 2, x = 50, y = 50, handled = false }), false, "press only remembers")
	ok(selection() ~= nil)
	eq(onMouse({ type = T.Released, button = 2, x = 50, y = 50, handled = false }), true)
	eq(selection(), nil)
end)

test("Esc / back: onBack clears a selection, else aborts the tool", function()
	local p = render(newParam(true))
	local onMouse, tree = mouseHandler(p)
	paintOne(onMouse)
	tree = p.actionFn()
	tree.param.onBack()
	eq(selection(), nil)
	eq(p.aborted, nil)
	tree.param.onBack()
	eq(p.aborted, true)
end)

test("tool closed: isActive dropping clears the selection at the next render", function()
	local p = render(newParam(true))
	paintOne(mouseHandler(p))
	-- Same recipe instance re-rendered inactive: refs keep their values (re-run with old refs).
	local refs, states = h.refs, h.states
	local i, j = 0, 0
	h.react.useRef = function(init) i = i + 1; return refs[i] end
	h.react.useState = function(init) j = j + 1; return states[j] end
	p.isActive = false
	reg["BulkBulldozerAction"](p)
	eq(selection(), nil, "cleared by the inactive render")
end)

test("tool closed: unmount clears the selection and resets the status chip text", function()
	local p = render(newParam(true))
	paintOne(mouseHandler(p))
	-- Publish a non-idle status the way onStep does.
	for _, f in ipairs(h.steps) do f() end
	local last = fired[#fired]
	ok(last ~= nil and last.name == "BulkBulldozer.status")
	eq(string.sub(last.payload.head, 1, 10), "1 selected")
	local unmounts = h.unmounts
	for _, f in ipairs(unmounts) do f() end
	eq(selection(), nil)
	last = fired[#fired]
	eq(last.name, "BulkBulldozer.status")
	eq(last.payload.head, "Nothing selected")
	eq(last.payload.detail, "Paint with the left mouse button")
	-- A fresh status chip (next mount) starts from the reset file-scope text.
	local tree = reg["BulkBulldozerStatus"]({})
	eq(tree.param.children[1].param.text, "Nothing selected")
end)

test("world layer unmounted and not remounted: cleared on the next step (tool switched)", function()
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	-- actionFn registered its own mount/unmount handlers after the recipe's two.
	local layerUnmount = h.unmounts[#h.unmounts]
	paintOne(onMouse)
	layerUnmount()
	-- Remount in the same frame (re-binding): nothing happens.
	h.mounts[#h.mounts]()
	ok(selection() ~= nil, "same-frame remount keeps the selection")
	layerUnmount()
	local t0 = os.clock()
	while os.clock() - t0 < 0.3 do end   -- LAYER_GONE_SECONDS
	for _, f in ipairs(h.steps) do f() end
	eq(selection(), nil, "cleared after the layer stayed gone")
end)

test("another tool of the tab selected (world layer never mounted): steps read no cursor and sample nothing", function()
	local cursorReads, queries = 0, 0
	api.gui.mouse.hasTerrainPosition = function() cursorReads = cursorReads + 1; return true end
	api.gui.mouse.getTerrainPosition = function() return { x = 100, y = 100, z = 0 } end
	api.type.Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end }
	api.type.Vec2f = { new = function(x, y) return { x = x, y = y } end }
	api.engine.util.octree = { findEntitiesInCircle = function() queries = queries + 1; return {} end }
	-- isActive stays true for every entry of the shown tab (mouse mode).
	local p = render(newParam(true))
	mouseHandler(p)   -- actionFn registered, but its layer is not mounted
	for _ = 1, 3 do for _, f in ipairs(h.steps) do f() end end
	eq(cursorReads, 0)
	eq(queries, 0)
	eq(selection(), nil, "no hover preview")
	-- The entry is selected: its world layer mounts and the hover preview samples.
	h.mounts[#h.mounts]()
	for _, f in ipairs(h.steps) do f() end
	ok(cursorReads > 0, "cursor read once the layer is up")
	ok(queries > 0, "hover sample once the layer is up")
end)

test("toolbar sync: an unticked Roads box survives a remount (never re-ticked by defaults)", function()
	local p = render(newParam(true))
	-- The player unticks Roads (onChangeFn → EV_FILTER), category 3.
	h.events["BulkBulldozer.filter"]("BulkBulldozer.filter", { field = "roads", on = false, category = "3", shown = { roads = false } })
	eq(h.states[2]:old().roads, false)
	-- Tool closed and opened again: a fresh recipe instance (new hooks) in the same Lua state.
	for _, f in ipairs(h.unmounts) do f() end
	render(newParam(true))
	eq(h.states[2]:old().roads, false, "fresh mount starts from the toolbar memory")
	for _, f in ipairs(h.steps) do f() end   -- activation edge: getCurrentParams {} changes nothing
	eq(h.states[2]:old().roads, false)
	-- The menu shows the toolbar again (checkEnabledFn → EV_SHOWN) with Roads ticked: adopted.
	h.events["BulkBulldozer.shown"]("BulkBulldozer.shown", { values = { roads = true } })
	eq(h.states[2]:old().roads, true)
end)


test("highlight overlay: a growing selection only builds pieces for the new entities (PERF_REVIEW)", function()
	local made = 0
	local function obj() return {} end
	api.type.Vec2f = { new = function(x, y) return { x = x, y = y } end }
	api.type.EdgeGeometry = { new = obj, Straight = { new = obj }, Arc = { new = obj } }
	local builtin = ug_require "::/gui/main/builtin.lua"
	builtin.type.EdgeRenderable = { Edge = { new = function(g) made = made + 1; return { g = g } end } }
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	local function straight(x0, y0, x1, y1)
		return { p0x = x0, p0y = y0, p1x = x1, p1y = y1, t0x = x1 - x0, t0y = y1 - y0, t1x = x1 - x0, t1y = y1 - y0,
			p0z = 0, p1z = 0, t0z = 0, t1z = 0 }
	end
	local function overlayCount(tree)
		for _, c in ipairs(tree.param.children) do
			if c.builtin == "EdgeRenderable" then return #c.param.edges end
		end
		return 0
	end
	-- Stroke 1: one 60 m road (4 pieces of 15 m).
	onMouse({ type = T.Pressed, button = 0, x = 10, y = 10, handled = false })
	local s = selection()
	s.cache.descs[4242] = { entity = 4242, isEdge = true, gone = false, full = true, curve = straight(0, 0, 60, 0) }
	sel.add(s.stroke, { entity = 4242, kind = "road", objects = 0 })
	onMouse({ type = T.Released, button = 0, x = 10, y = 10, handled = false })
	eq(overlayCount(p.actionFn()), 4)
	eq(made, 4)
	-- Stroke 2 adds a 30 m road (2 pieces): only those are made, the first road's pieces are reused.
	onMouse({ type = T.Pressed, button = 0, x = 10, y = 10, handled = false })
	s = selection()
	s.cache.descs[4243] = { entity = 4243, isEdge = true, gone = false, full = true, curve = straight(0, 10, 30, 10) }
	sel.add(s.stroke, { entity = 4243, kind = "road", objects = 0 })
	onMouse({ type = T.Released, button = 0, x = 10, y = 10, handled = false })
	eq(overlayCount(p.actionFn()), 6)
	eq(made, 6, "only the new road's 2 pieces were made")
end)

-- SQPERF rollout: the per-event mouse log (Phase 1 spike) only with "Debug: performance log" On.
local function mouseLogLines(debugOn)
	local lines = {}
	set_global("log", { message = function(m) lines[#lines + 1] = m end })
	api.engine.config = { getModParams = function()
		return { square_bulk_bulldozer = { sqperf_log = debugOn and 2 or 1 } }
	end }
	local p = render(newParam(true))
	local onMouse = mouseHandler(p)
	paintOne(onMouse)
	set_global("log", nil)
	local mouse, sqperf = 0, 0
	for _, m in ipairs(lines) do
		if string.find(m, "[BulkBulldozer] mouse ", 1, true) == 1 then mouse = mouse + 1 end
		if string.find(m, "[SQPERF] mod=square_bulk_bulldozer ctx=gui", 1, true) == 1 then sqperf = sqperf + 1 end
	end
	return mouse, sqperf, lines
end

test("debug log: mouse events are not logged with the performance log Off", function()
	local mouse = mouseLogLines(false)
	eq(mouse, 0)
end)

test("debug log: mouse events are logged with the performance log On", function()
	local mouse, sqperf = mouseLogLines(true)
	eq(mouse, 2, "press + release")
	ok(sqperf >= 1, "level 1 / level 3 SQPERF lines while On")
end)

test("a platform whose base react / construction_react_util lack the focus, ESC and tooltip helpers (PS5 report 2026-10-19): renders, no error", function()
	-- docs/findings/gui.md "Base GUI modules differ by platform" (Smart Lanes player report): the console build's base
	-- GUI scripts lack functions the PC copies have. Without them the tool keeps working: no focus pins, no ESC hook
	-- (onBack still clears), no cursor tooltip; with the base tooltip recipe the ring carries it.
	local function run(withTooltip)
		reset_modules()
		h = fakeReact()
		reg = {}
		h.react.RegisterRecipe = function(name, fn)
			reg[name] = fn
			return setmetatable({ name = name }, { __call = function(_s, p) return { recipe = name, param = p } end })
		end
		h.react.setForceFocusable, h.react.setRestrictMouseFocus = nil, nil
		h.react.useInputAction, h.react.iaHandler = nil, nil
		stub_module("::/gui/main/react.lua", h.react)
		stub_module("::/gui/main/builtin.lua", {
			BoxLayout = node("BoxLayout"), TextView = node("TextView"), Selector = node("Selector"),
			ActionDescriptor = node("ActionDescriptor"), ActionTooltip = node("ActionTooltip"),
			EdgeRenderable = node("EdgeRenderable"),
			type = { Orientation = { Horizontal = "Horizontal", Vertical = "Vertical" },
				EdgeRenderable = { Edge = { new = function(g) return { geometry = g } end } } },
		})
		stub_module("::/gui/construction/construction_react_util.tl",
			withTooltip and { SimpleTooltipRecipe = function(p) return p end } or {})
		api.type.Vec2f = { new = function(x, y) return { x = x, y = y } end }
		api.type.EdgeGeometry = setmetatable({ Arc = { new = function() return {} end } },
			{ __index = function() return nil end })
		api.type.EdgeGeometry.new = function() return {} end
		api.engine.terrain = { getHeightAt = function() return 0 end }
		script = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bulk_bulldozer.script.tl"
		sel = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl"
		local p = render(newParam(true))
		local onMouse = mouseHandler(p)
		paintOne(onMouse)
		h.states[3]:set({ x = 10, y = 10, z = 0 }) -- cursorState: the ring and its tooltip at the cursor
		-- the same instance re-rendered (old refs and states, by call order) with a waiting selection: the ESC branch
		local refs, states = h.refs, h.states
		local i, j = 0, 0
		h.react.useRef = function() i = i + 1; return refs[i] end
		h.react.useState = function() j = j + 1; return states[j] end
		reg["BulkBulldozerAction"](p)
		eq(next(h.inputs), nil, "no ESC hook where the platform has none")
		local tree = p.actionFn()
		local tips = 0
		for _, c in ipairs(tree.param.children) do if c.builtin == "ActionTooltip" then tips = tips + 1 end end
		eq(tips, withTooltip and 1 or 0)
		tree.param.onBack()
		eq(selection(), nil, "onBack still clears")
	end
	run(false)
	run(true)
end)
