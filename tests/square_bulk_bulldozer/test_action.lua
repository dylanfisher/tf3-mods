-- bulk_bulldozer.script: the BulkBulldozerAction recipe's right click and close handling
-- (user feedback 2026-10-07). A fake react runs the recipe: hooks by call order, mount/unmount
-- and step handlers kept, the world layer (actionFn) captured through setActionFn.

local T = { Pressed = "Pressed", Released = "Released", Clicked = "Clicked", Moved = "Moved",
	Wheel = "Wheel", DoubleClicked = "DoubleClicked", Entered = "Entered", Exited = "Exited",
	PressedOutside = "PressedOutside" }

local fired

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

