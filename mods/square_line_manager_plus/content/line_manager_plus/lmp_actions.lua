-- Line Manager Plus, the "Line actions" button (PLAN.md decision D1): one toggle button right of Auto-Rename (A+) in
-- the line editor's toolbar that opens a small popover menu. Features add entries to that menu instead of more
-- toolbar icons (Duplicate / Reverse line, line_ops.lua; Match line rate, rate_matcher.lua).
--
-- Entries: actions.register{ id, order, label = "English key", icon = path, view = fn(ctx) -> { enabled, tooltip },
-- run = fn(ctx) }. ctx = { params = the manager's commonParams (lmp_capture), line = the edited line entity }.
-- Entries sort by order, then registration; registering an id again replaces it. The label is translated at render
-- (`_(label)`), so register the English key and list it in strings.json. view() runs every step while the menu is
-- open and must be cheap; run() runs from the click (GUI thread), may send commands, and the menu closes after it.
-- Each view() and run() runs in its own pcall: a failing view shows its entry disabled, a failing run gives one
-- feedback line; both are logged once per entry.
--
-- The button: an lmp_rows injector (order 100: right of A+). Shown only while exactly one line is selected and edited
-- and that line isn't protected (as the undo buttons), otherwise an empty BoxLayout (a recipe must return a layout).
-- It copies the A+ button (base manager_window.tl:3518-3572): a ToggleButton with A+'s classes
-- "vehicle-button, secondary" (so it looks like its neighbours without stylesheet rules) whose value is "menu open",
-- opening popover_react_util.PopoverWindow at the A+ popover's anchor (commonParams.configureLinesPopoverPosRef,
-- getPosition(1, 1)) with A+'s window classes "configure-lines, management" (vanilla popover look, title bar hidden,
-- height capped: line_vehicle_mgmt.css.lua:950-975). The same "locked" handling as A+: a press on the button while
-- the menu is open closes it (the popover's PressedOutside) and the release must not reopen it.
-- Our window has its own key (KEY), so closing it never removes another popover (removeWindow, builtin.d.tl:1231);
-- opening it removes the others first, as every vanilla popover does. The menu tells the button when it goes away
-- (unmount), so the toggle never stays "on" after another popover replaced ours.
--
-- The menu recipe (SquareLmpLineActionsMenu): a vertical BoxLayout of icon+text Buttons
-- (button_react_util.makeIconTextButton, class "secondary"); lmp.css.lua stretches them to one width (1 rule).
-- SQPERF section "line_actions": the menu's per-step view and the clicks.

local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local popover_react_util = ug_require "::/gui/main/popover_react_util.tl"
local button_react_util = ug_require "::/gui/main/button_react_util.tl"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
local capture = ug_require "square_line_manager_plus::/line_manager_plus/lmp_capture.lua"
local rows = ug_require "square_line_manager_plus::/line_manager_plus/lmp_rows.lua"

local M = {}

-- base "list" glyph, 48x48 @2x greyscale mask like A+ (gui.zip gui/line_vehicle_mgmt/icons/symbol_burger_menu@2x.tga,
-- used by the vehicle store's layout toggle, vehicle_store_window.tl:2411)
M.ICON = "::/gui/line_vehicle_mgmt/icons/symbol_burger_menu.tga"
M.KEY = "square-lmp-line-actions"
M.WINDOW_CLASS = "configure-lines, management"
M.ORDER = 100

local PREFIX = "[LineManagerPlus] line actions: "

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end
M.warnOnce = warnOnce

-- Registry ----------------------------------------------------------------------------------------------------------
local entries = {}
local seq = 0

--- Adds (or replaces, same id) a menu entry. Errors on a malformed entry.
function M.register(e)
	assert(type(e) == "table" and type(e.id) == "string" and type(e.label) == "string"
		and type(e.view) == "function" and type(e.run) == "function", "entry needs id, label, view and run")
	for i = #entries, 1, -1 do
		if entries[i].id == e.id then table.remove(entries, i) end
	end
	seq = seq + 1
	entries[#entries + 1] = { id = e.id, order = type(e.order) == "number" and e.order or 0, label = e.label,
		icon = e.icon, view = e.view, run = e.run, seq = seq }
	table.sort(entries, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.seq < b.seq
	end)
end

--- Registered entry ids in menu order (tests, logging).
function M.ids()
	local out = {}
	for i, e in ipairs(entries) do out[i] = e.id end
	return out
end

-- Shared helpers for entries -----------------------------------------------------------------------------------------

--- commonParams.addFeedback (manager_window.d.tl:133-138) plus a log line; never throws.
function M.feedback(params, message, isError)
	say(message)
	local ok, err = pcall(function()
		if params and params.addFeedback then params.addFeedback(message, isError and "Error" or nil, nil, nil) end
	end)
	if not ok then warnOnce("addFeedback", err) end
end

local function isProtected(params, line)
	-- as manager_window.tl:744 asks before an edit (undo.lua isProtected)
	local filters = params.gameCtx and params.gameCtx.filters and params.gameCtx.filters:get()
	local protected = filters and filters.protectedEntities
	return protected ~= nil and line_util.isStopProtected(line, nil, protected)
end

--- ctx for the entries, or nil when the button should not show: no manager params, not exactly one selected line,
--- no edited line, the line is gone or protected.
function M.context()
	local params = capture.params()
	if not params or capture.selectedLineCount(params) ~= 1 then return nil end
	local line = capture.editedLine(params)
	if not (line and api.engine.entityExists(line)) then return nil end
	if isProtected(params, line) then return nil end
	return { params = params, line = line }
end

-- Menu -------------------------------------------------------------------------------------------------------------
-- shown: our popover window is open (set on open, cleared on close / unmount); gen: counts the opens, so the unmount
-- of an older menu window never clears the flag of a newer one
local menu = { shown = false, gen = 0 }

local function windowApi(params)
	return params.gameCtx.windowContainer:get():getApi()
end

local function closeMenu(params)
	if not menu.shown then return end
	menu.shown = false
	local ok, err = pcall(function() windowApi(params).removeWindow(popover_react_util.PopoverWindow, M.KEY) end)
	if not ok then warnOnce("close", err) end
end
M.closeMenu = closeMenu

--- { hidden } or { line, items = { { id, enabled, tooltip } } } for the open menu.
local HIDDEN = { hidden = true }
local function menuView()
	local ctx = M.context()
	if not ctx then return HIDDEN end
	local items = {}
	for i, e in ipairs(entries) do
		local ok, v = pcall(e.view, ctx)
		if not ok or type(v) ~= "table" then
			if not ok then warnOnce(e.id .. " view", v) end
			v = { enabled = false, tooltip = _(e.label) } -- i18n: ignore
		end
		items[i] = { id = e.id, enabled = v.enabled == true, tooltip = v.tooltip }
	end
	return { line = ctx.line, items = items }
end
M.menuView = menuView

local function sameView(a, b)
	if a.hidden or b.hidden then return a.hidden == b.hidden end
	if a.line ~= b.line or #a.items ~= #b.items then return false end
	for i, x in ipairs(a.items) do
		local y = b.items[i]
		if x.id ~= y.id or x.enabled ~= y.enabled or x.tooltip ~= y.tooltip then return false end
	end
	return true
end
M.sameView = sameView

local function entryById(id)
	for _i, e in ipairs(entries) do
		if e.id == id then return e end
	end
	return nil
end

--- Runs entry `id` on the current context (a click in the menu); closes the menu.
function M.runEntry(id, params)
	local tPerf = perf:start()
	local e = entryById(id)
	local ctx = M.context()
	if e and ctx then
		local ok, err = pcall(e.run, ctx)
		if not ok then
			warnOnce(id .. " run", err)
			M.feedback(ctx.params, _("Line Manager Plus: the line action failed (see log)."), true)
		end
	end
	closeMenu(params or (ctx and ctx.params))
	perf:stop("line_actions", tPerf)
end

local Menu = react.RegisterRecipe("SquareLmpLineActionsMenu", function(p)
	react.onUnmount(function()
		-- our window went away (closed by us, by a click outside, or replaced by another popover)
		if p == nil or p.gen == nil or p.gen == menu.gen then menu.shown = false end
	end)
	local state = engine_react_util.useStepState(function()
		local tPerf = perf:start()
		local ok, v = pcall(menuView)
		perf:stop("line_actions", tPerf)
		if not ok then
			warnOnce("view", v)
			return HIDDEN
		end
		return v
	end, nil, sameView)
	local v = state:old() or HIDDEN
	local children = {}
	if not v.hidden then
		for i, item in ipairs(v.items) do
			local e = entryById(item.id)
			if e then
				children[#children + 1] = button_react_util.makeIconTextButton(
					"secondary",
					e.icon,
					_(e.label), -- i18n: ignore
					function() M.runEntry(item.id, p and p.params) end,
					item.tooltip,
					item.enabled
				)
			end
			if i > 64 then break end
		end
	end
	-- a recipe returns a layout at its root (memory: react-recipe-must-return-layout); entries are items
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end)
M.Menu = Menu

local function openMenu(params, selfRef)
	local wc = windowApi(params)
	local pos
	local okPos, err = pcall(function()
		local anchor = params.configureLinesPopoverPosRef and params.configureLinesPopoverPosRef:get()
		if anchor then
			pos = anchor:getPosition(1.0, 1.0)
		elseif selfRef and selfRef:get() then
			pos = selfRef:get():getPosition(1.0, 0.0) -- as popover_react_util.TogglePopoverButton does
		end
	end)
	if not okPos then warnOnce("position", err) end
	wc.removeAllWindows(popover_react_util.PopoverWindow)
	menu.gen = menu.gen + 1
	menu.shown = true
	wc.addWindow(popover_react_util.PopoverWindow, M.KEY, {
		onClose = function() closeMenu(params) end,
		x = pos and pos.x or nil,
		y = pos and pos.y or nil,
		windowTitle = _("Line actions"),
		windowClass = M.WINDOW_CLASS,
		recipe = Menu,
		params = { params = params, gen = menu.gen },
		inputActionBubbleUpFilter = builtin.type.InputActionBubbleUpFilter
			and builtin.type.InputActionBubbleUpFilter.filterOut{ "IA_CAMPAIGN_MISSION_MENU_OPEN" } or nil,
	})
end

-- Toolbar button ---------------------------------------------------------------------------------------------------
local Button = react.RegisterRecipe("SquareLmpLineActions", function(p)
	local params = p and p.params
	local selfRef = react.useSelfRef()
	local openState = react.useState(false)
	local lockedState = react.useState(false)
	local visible = engine_react_util.useStepState(function()
		local ok, ctx = pcall(M.context)
		if not ok then
			warnOnce("context", ctx)
			return false
		end
		return ctx ~= nil
	end)

	react.onStep(function()
		-- follow the menu (closed by a click outside, another popover, an action) and close it when we hide
		if openState:old() ~= menu.shown then openState:set(menu.shown) end
		if menu.shown and not visible:old() then closeMenu(params) end
	end)
	react.onUnmount(function()
		if menu.shown and params then closeMenu(params) end
	end)
	react.onMouseEvent(function(evt)
		-- as LinePanelActionButtons (manager_window.tl:3506-3515): a press while the menu is open closes it through
		-- the popover's PressedOutside; the click's value change must then not reopen it
		local T = api.gui.mouse.Event.Type
		if evt.type == T.Pressed then
			if openState:old() then lockedState:set(true) end
		elseif evt.type == T.Released then
			lockedState:set(false)
		end
		return false
	end)

	if not visible:old() or not params then
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = {} }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			-- the A+ button's shape (button_react_util.makeIconToggleButton): ToggleButton + AutoFit ImageView, same
			-- classes. No mouseTransparent on ImageView (crashes).
			builtin.ToggleButton{
				meta = { class = "vehicle-button, secondary", tooltip = _("Line actions") },
				content = builtin.ImageView{ path = M.ICON, scaling = builtin.type.ImageViewScaling.AutoFit },
				value = openState:old() and 1 or 0,
				onValueChange = function(value)
					local ok, err = pcall(function()
						if value == 1 and not lockedState:old() then
							openMenu(params, selfRef)
							openState:set(true)
						else
							lockedState:set(false)
							closeMenu(params)
							openState:set(false)
						end
					end)
					if not ok then warnOnce("toggle", err) end
				end,
			},
		},
	}
end)
M.Button = Button

-- Install ----------------------------------------------------------------------------------------------------------
local installed = false

local function build(ctx)
	if #entries == 0 then return nil end
	return { Button{ params = ctx.params } }
end
M.build = build

--- Installs lmp_rows (and lmp_capture) and registers the button injector; true when installed (now or before).
function M.install()
	if installed then return true end
	if not rows.install() then return false end
	rows.register({ id = "line_actions", order = M.ORDER, build = build })
	installed = true
	return true
end

return M
