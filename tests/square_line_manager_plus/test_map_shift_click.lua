-- Line Manager Plus "Map: Shift-click a line opens the Line Manager" (map_shift_click.lua) and the line window plugin
-- (lmp_line.script.lua), with fake react / builtin / base modules and a fake api. Ported from Passenger Destinations'
-- test_vehicle.lua ("shift click ..." tests, rev 5 before upload). Covers: install (wraps makeDefaultSelector once,
-- guard flag, keeps the previous wrapper, missing field), the Shift-click on a line / on empty map with a line window
-- open, the allowed top tools (Passenger Destinations' tool included), builtin.Selector restored after each call (also
-- on error), a failing click check, and the chain with a Passenger Destinations style wrapper in either order.

local F -- per-test fakes and records

local LINE = 50       -- the player's line
local OTHER_LINE = 51 -- another company's line
local VEHICLE = 100
local WATER = 2       -- opens no window

local function widget(name)
	return function(p) return { w = name, p = p } end
end

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	F = { events = {}, activeTool = "EntityDetailsTool", shift = false, mounts = {}, unmounts = {} }
	local comps = {
		[LINE] = { LINE = {}, PLAYER_OWNED = { player = 7 } },
		[OTHER_LINE] = { LINE = {}, PLAYER_OWNED = { player = 99 } },
		[VEHICLE] = { TRANSPORT_VEHICLE = {} },
	}
	set_global("api", {
		type = {
			Clock = { new = function() return { getTime = function() return 1e9 end } end },
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
		},
		gui = { inputAction = { modifierOnlyActionIsActive = function(id)
			return id == "IA_PRECISION_MODE" and F.shift == true
		end } },
		engine = {
			getComponent = function(e, ct) return comps[e] and comps[e][ct] or nil end,
			util = { getPlayer = function()
				if F.playerError then error("player boom") end
				return 7
			end },
		},
	})
	stub_module("::/gui/main/react.lua", {
		fireEvent = function(_ref, name, param) F.events[#F.events + 1] = { name = name, param = param } end,
		RegisterPluginRecipe = function(_ext, _name, fn) return fn end,
		onMount = function(fn) F.mounts[#F.mounts + 1] = fn end,
		onUnmount = function(fn) F.unmounts[#F.unmounts + 1] = fn end,
	})
	F.builtin = { Selector = widget("Selector"), BoxLayout = widget("BoxLayout") }
	stub_module("::/gui/main/builtin.lua", F.builtin)
	F.sru = {}
	if opts.noField ~= true then
		-- as the base: builds the Selector through builtin.Selector (selector_react_util.tl:100) and reports hovers
		-- to the ref it is given
		F.sru.makeDefaultSelector = function(_rc, ref)
			F.selectorRef = ref
			if F.baseError then error("selector boom") end
			return F.builtin.Selector{
				onSelect = function(e) F.baseSelected = e; return true end,
				onSelectNothing = function() F.baseNothing = true; return false end,
				onHover = function(e) ref:set(e) end,
			}
		end
	end
	stub_module("::/gui/main/selector_react_util.tl", F.sru)
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultToolStackApi = function()
		return { getActiveTool = function() return { name = F.activeTool } end }
	end })
	stub_module("::/gui/entity_window/view_manager_util.tl", {
		wouldCreateView = function(e) if e == nil or e < 0 or e == WATER then return nil end return e end,
	})
	stub_module("::/gui/entity_window/line/line_eow.script.tl", { LineEowExtensionPoint = "line" })
	F.m = ug_require "square_line_manager_plus::/line_manager_plus/map_shift_click.lua"
end

--- A Passenger Destinations style wrapper of makeDefaultSelector (its rev 5 code without the click part): passes a
--- proxy ref that records each hover and forwards it.
local function paxDestWrap()
	local sru = F.sru
	local base = sru.makeDefaultSelector
	if base == nil or sru.squarePaxDestShift ~= nil then return end
	sru.squarePaxDestShift = true
	sru.makeDefaultSelector = function(refRC, selectedEntityRef, allowStacking, filters, inverted)
		local proxy = {
			set = function(_self, entity)
				F.paxHover = entity
				selectedEntityRef:set(entity)
			end,
			get = function(_self) return selectedEntityRef:get() end,
		}
		return base(refRC, proxy, allowStacking, filters, inverted)
	end
end

--- What a default selector action does: calls the (wrapped) makeDefaultSelector. Returns the node and the real ref.
local function selector()
	local real = { v = -1 }
	function real:set(x) self.v = x end
	function real:get() return self.v end
	local node = F.sru.makeDefaultSelector({}, real, false)
	eq(node.w, "Selector")
	return node, real
end

local function lines(level, text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if (level == nil or e.level == level) and e.msg:find(text, 1, true) then n = n + 1 end
	end
	return n
end

--- Mounts the line window plugin for `line`; returns its unmount.
local function openLineWindow(line)
	ug_require "square_line_manager_plus::/line_manager_plus/lmp_line.script.lua"
	local plugin = data().LmpLinePlugin
	F.mounts, F.unmounts = {}, {}
	local node = plugin({ entityId = line, gameCtx = {} })
	eq(node.w, "BoxLayout")
	for _i, fn in ipairs(F.mounts) do fn() end
	local unmounts = F.unmounts
	return function() for _i, fn in ipairs(unmounts) do fn() end end
end

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps makeDefaultSelector once, sets the guard flag and logs installed", function()
	setup()
	local orig = F.sru.makeDefaultSelector
	ok(F.m.install({}, {}))
	ok(F.sru.makeDefaultSelector ~= orig)
	ok(F.sru.squareLmpShiftClick == true)
	local w = F.sru.makeDefaultSelector
	ok(F.m.install({}, {}))
	ok(F.sru.makeDefaultSelector == w, "no second wrap")
	eq(lines("message", "[LineManagerPlus] map shift click: installed"), 1)
	eq(lines("warning", "map shift click"), 0)
end)

test("install: a missing makeDefaultSelector installs nothing and warns once", function()
	setup({ noField = true })
	eq(F.m.install({}, {}), false)
	eq(F.sru.makeDefaultSelector, nil)
	eq(F.sru.squareLmpShiftClick, nil)
	eq(lines("warning", "[LineManagerPlus] map shift click: install"), 1)
end)

-- clicks -------------------------------------------------------------------------------------------------------------

test("shift click on one of the player's lines opens the line manager on it; anything else selects as usual", function()
	setup()
	F.m.install({}, {})
	local node = selector()
	local onSelect = node.p.onSelect
	F.shift = true
	ok(onSelect(LINE, {}, nil))
	eq(#F.events, 1)
	eq(F.events[1].name, "openVehicleManager")
	eq(F.events[1].param.openWithLineEntity, LINE)
	eq(F.baseSelected, nil, "the line window was not opened")
	eq(lines("message", "open the Line Manager for line 50 (clicked 50)"), 1)
	onSelect(OTHER_LINE, {}, nil)
	eq(F.baseSelected, OTHER_LINE, "another company's line: the usual select")
	eq(#F.events, 1)
	F.shift = false
	onSelect(LINE, {}, nil)
	eq(F.baseSelected, LINE, "no Shift: the usual select")
	F.shift = true
	onSelect(VEHICLE, {}, nil)
	eq(F.baseSelected, VEHICLE, "a vehicle: the usual select")
	F.activeTool = "Manager"
	F.baseSelected = nil
	onSelect(LINE, {}, nil)
	eq(F.baseSelected, LINE, "the line manager on top: the usual select")
	eq(#F.events, 1)
end)

test("shift click on empty map with a line window open manages that line; without one it selects as usual", function()
	setup()
	F.m.install({}, {})
	local p = selector().p
	F.shift = true
	p.onSelect(WATER, {}, nil) -- water, no line window
	eq(F.baseSelected, WATER, "no line window: the usual select")
	eq(#F.events, 0)
	local close = openLineWindow(LINE)
	ok(p.onSelect(WATER, {}, nil))
	eq(#F.events, 1); eq(F.events[1].param.openWithLineEntity, LINE, "the open line window's line")
	ok(p.onSelectNothing())
	eq(#F.events, 2, "a click on nothing too")
	F.baseSelected = nil
	p.onSelect(VEHICLE, {}, nil)
	eq(F.baseSelected, VEHICLE, "a vehicle still opens its window")
	F.shift = false
	p.onSelect(WATER, {}, nil)
	eq(#F.events, 2, "no Shift: nothing special")
	p.onSelectNothing()
	ok(F.baseNothing)
	F.shift = true
	close()
	F.baseNothing = nil
	eq(p.onSelectNothing(), false, "window closed: the base onSelectNothing")
	ok(F.baseNothing)
	eq(#F.events, 2)
end)

test("empty map manages the newest open line window; another company's line window doesn't count", function()
	setup()
	F.m.install({}, {})
	local p = selector().p
	F.shift = true
	local closeMine = openLineWindow(LINE)
	local closeOther = openLineWindow(OTHER_LINE)
	eq(p.onSelectNothing(), false, "newest window: not the player's line")
	eq(#F.events, 0)
	closeOther()
	ok(p.onSelectNothing())
	eq(F.events[1].param.openWithLineEntity, LINE)
	closeMine()
	eq(#F.m.openLines(), 0)
end)

test("Passenger Destinations' tool on top (its Shift hover arrows showing): Shift-click still works", function()
	setup()
	F.m.install({}, {})
	local p = selector().p
	F.shift = true
	F.activeTool = "SquarePassengerDestinations"
	ok(p.onSelect(LINE, {}, nil))
	openLineWindow(LINE)
	ok(p.onSelectNothing())
	eq(#F.events, 2)
	F.activeTool = "Construction"
	eq(p.onSelectNothing(), false, "construction on top: nothing")
	eq(#F.events, 2)
end)

test("a failing click check selects as usual and warns once", function()
	setup()
	F.m.install({}, {})
	local p = selector().p
	F.shift = true
	local real = F.m.click
	F.m.click = function() error("click boom") end
	p.onSelect(LINE, {}, nil)
	p.onSelect(LINE, {}, nil)
	eq(F.baseSelected, LINE)
	eq(#F.events, 0)
	eq(lines("warning", "[LineManagerPlus] map shift click: click: "), 1)
	F.m.click = real
	F.playerError = true
	F.baseSelected = nil
	p.onSelect(LINE, {}, nil)
	eq(F.baseSelected, LINE, "getPlayer failing: not the player's line, the usual select")
end)

-- builtin.Selector swap ----------------------------------------------------------------------------------------------

test("builtin.Selector is swapped only during the call and restored to exactly what was there, also on error", function()
	setup()
	local before = F.builtin.Selector
	F.m.install({}, {})
	selector()
	ok(F.builtin.Selector == before, "restored after the call")
	local plain = F.builtin.Selector{ onSelect = function() return "plain" end }
	F.shift = true
	eq(plain.p.onSelect(LINE), "plain", "a Selector built elsewhere is never wrapped")
	eq(#F.events, 0)
	F.baseError = true
	local okCall, err = pcall(F.sru.makeDefaultSelector, {}, { set = function() end }, false)
	ok(not okCall and tostring(err):find("selector boom", 1, true) ~= nil, "the base error propagates")
	ok(F.builtin.Selector == before, "restored after the error")
end)

test("the Selector's other params pass through unchanged", function()
	setup()
	F.m.install({}, {})
	local node, real = selector()
	node.p.onHover(VEHICLE)
	eq(real.v, VEHICLE)
end)

-- chain with Passenger Destinations' wrapper -------------------------------------------------------------------------

local function chainChecks()
	local node, real = selector()
	node.p.onHover(VEHICLE)
	eq(F.paxHover, VEHICLE, "Passenger Destinations' proxy sees the hover")
	eq(real.v, VEHICLE, "and forwards it")
	F.shift = true
	ok(node.p.onSelect(LINE, {}, nil), "Shift-click handled")
	eq(F.events[1].param.openWithLineEntity, LINE)
	node.p.onSelect(VEHICLE, {}, nil)
	eq(F.baseSelected, VEHICLE)
end

test("chain: Passenger Destinations wraps first, then Line Manager Plus", function()
	setup()
	local before = F.builtin.Selector
	paxDestWrap()
	F.m.install({}, {})
	chainChecks()
	ok(F.builtin.Selector == before)
end)

test("chain: Line Manager Plus wraps first, then Passenger Destinations", function()
	setup()
	local before = F.builtin.Selector
	F.m.install({}, {})
	paxDestWrap()
	chainChecks()
	ok(F.builtin.Selector == before)
end)

test("chain: Passenger Destinations alone keeps its hover; plain clicks; no Selector swap", function()
	setup()
	local before = F.builtin.Selector
	paxDestWrap()
	local node, real = selector()
	node.p.onHover(VEHICLE)
	eq(F.paxHover, VEHICLE); eq(real.v, VEHICLE)
	F.shift = true
	node.p.onSelect(LINE, {}, nil)
	eq(F.baseSelected, LINE, "no Line Manager Plus: the usual select")
	eq(#F.events, 0)
	ok(F.builtin.Selector == before)
end)
