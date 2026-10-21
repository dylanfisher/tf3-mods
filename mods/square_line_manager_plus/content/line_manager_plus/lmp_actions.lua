-- Line Manager Plus, the "Line actions" button (PLAN.md decision D1): one toggle button right of Auto-Rename (A+) in
-- the line editor's toolbar that opens a small popover menu. Features add entries to that menu instead of more
-- toolbar icons (Duplicate / Reverse / Duplicate + reverse line, line_ops.lua; Match line rate, rate_matcher.lua).
--
-- Entries: actions.register{ id, order, label = "English key", icon = path, view = fn(ctx) -> { enabled, tooltip },
-- run = fn(ctx) }. ctx = { params = the manager's commonParams (lmp_capture), line = the edited line entity }.
-- Entries sort by order, then registration; registering an id again replaces it. The label is translated at render
-- (`_(label)`), so register the English key and list it in strings.json. view() runs every step while the menu is
-- open and must be cheap; run() runs from the click (GUI thread), may send commands, and the menu closes after it.
-- Each view() and run() runs in its own pcall: a failing view shows its entry disabled, a failing run gives one
-- feedback line; both are logged once per entry.
-- A second level (the registry's only one): an entry with choices = fn(ctx) -> { { id, label = translated text,
-- icon, iconClass?, enabled, tooltip } } and choose = fn(ctx, choiceId) (instead of run) opens a page in the same
-- popover when clicked: the header card shows the entry's label, a "Back" row (base back.tga, town window tabs) leads
-- to the entries again, then one row per choice in the entries' look. choices() runs every step while its page is
-- open (cache in the entry when it is costly); a click on a choice runs choose() (pcall, as run) and closes the menu.
-- The page is closed whenever the menu opens or closes. Set cargo for all stops (line_ops.lua) uses it.
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
-- The menu recipe (SquareLmpLineActionsMenu) looks like the base Auto-Rename popover next to it (AutoRenameDialog,
-- manager_window.tl:3085-3305; styles line_vehicle_mgmt.css.lua:977-1017, 1162-1187, all scoped R::AutoRenameDialog,
-- so their classes can't be reused; user choice "Auto-Rename rows", 2026-10-20):
-- * a header card with the title "Line actions" (font-scale-headline), built INLINE like "!auto-rename-lines-header":
--   card_surface + card_contour nine-patches, BaseVeryLight at transparency Low, border BaseVeryLight, height 36,
--   padding 2 8 2 8. Inline sheets have no margin or gravity: the base 8 8 1 8 margin is the inline padding of a
--   wrapper Component, and both get the base class "horizontal-spacer" (default.css.lua, gravity -1 0) to fill the
--   width (the Photo Mode footer pattern, docs/ui-guide.md).
-- * one full-width Button per entry: icon left, then the text (font-scale-body) left-aligned, in a content Component
--   of class "horizontal-spacer" (fills the button, so the row starts at the left like Auto-Rename's
--   "Button > *" gravity 0 -1); a 4 px spacer gives the base 2 + 6 px icon/text gap on top of the 4 px innerSpacing.
--   The rows sit in a Component with inline padding 3 6 10 6 (the base ScrollArea's margin 1 4 8 4 + padding 2).
--   Look (AccentMedium at transparency High, invisible border, margin 2 4 2 4, padding 4 8 4 8, hover AccentLight,
--   active getActiveFromRaw(AccentMedium)): 3 rules in lmp.css.lua (base state, :hover, :active; states can't be
--   inline). A disabled entry gets an inline grey wash (NeutralMedium at VeryHigh) over that, and the base
--   "Button:disabled" text / icon grey (builtin.css.lua:268-274); its tooltip gives the reason.
-- Offline (tests) the inline sheets are nil.
-- SQPERF section "line_actions": the menu's per-step view and the clicks.

local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf
local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local popover_react_util = ug_require "::/gui/main/popover_react_util.tl"
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
		and type(e.view) == "function"
		and (type(e.run) == "function" or (type(e.choices) == "function" and type(e.choose) == "function")),
		"entry needs id, label, view and run (or choices and choose)")
	for i = #entries, 1, -1 do
		if entries[i].id == e.id then table.remove(entries, i) end
	end
	seq = seq + 1
	entries[#entries + 1] = { id = e.id, order = type(e.order) == "number" and e.order or 0, label = e.label,
		icon = e.icon, view = e.view, run = e.run, choices = e.choices, choose = e.choose, seq = seq }
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
-- of an older menu window never clears the flag of a newer one; page: the id of the entry whose choices are shown
local menu = { shown = false, gen = 0, page = nil }

M.BACK = "::/gui/menu/icons/back.tga" -- the town window's back tab (entity_window/town/town.tl:765)
M.BACK_ID = "__back"
M.MAX_ROWS = 64 -- rows of one page (loop cap)

local function windowApi(params)
	return params.gameCtx.windowContainer:get():getApi()
end

local function closeMenu(params)
	menu.page = nil
	if not menu.shown then return end
	menu.shown = false
	local ok, err = pcall(function() windowApi(params).removeWindow(popover_react_util.PopoverWindow, M.KEY) end)
	if not ok then warnOnce("close", err) end
end
M.closeMenu = closeMenu

local function entryById(id)
	for _i, e in ipairs(entries) do
		if e.id == id then return e end
	end
	return nil
end

-- the open page's rows: Back, then the entry's choices (at most MAX_ROWS)
local function pageItems(e, ctx)
	local items = { { id = M.BACK_ID, enabled = true, label = _("Back"), icon = M.BACK } }
	local ok, list = pcall(e.choices, ctx)
	if not ok or type(list) ~= "table" then
		if not ok then warnOnce(e.id .. " choices", list) end
		list = {}
	end
	for i, c in ipairs(list) do
		if i > M.MAX_ROWS then break end
		if type(c) == "table" and c.id ~= nil then
			items[#items + 1] = { id = c.id, enabled = c.enabled == true, tooltip = c.tooltip,
				label = tostring(c.label or c.id), icon = c.icon, iconClass = c.iconClass }
		end
	end
	return items
end

--- { hidden } or { line, page, title, items = { { id, enabled, tooltip, label, icon, iconClass } } } for the open
--- menu: page nil lists the entries (title "Line actions"), page = an entry id lists its choices.
local HIDDEN = { hidden = true }
local function menuView()
	local ctx = M.context()
	if not ctx then return HIDDEN end
	local pageEntry = menu.page and entryById(menu.page)
	if pageEntry and pageEntry.choices then
		return { line = ctx.line, page = pageEntry.id, title = _(pageEntry.label), -- i18n: ignore
			items = pageItems(pageEntry, ctx) }
	end
	local items = {}
	for i, e in ipairs(entries) do
		local ok, v = pcall(e.view, ctx)
		if not ok or type(v) ~= "table" then
			if not ok then warnOnce(e.id .. " view", v) end
			v = { enabled = false, tooltip = _(e.label) } -- i18n: ignore
		end
		items[i] = { id = e.id, enabled = v.enabled == true, tooltip = v.tooltip,
			label = _(e.label), icon = e.icon } -- i18n: ignore
	end
	return { line = ctx.line, title = _("Line actions"), items = items }
end
M.menuView = menuView

local function sameView(a, b)
	if a.hidden or b.hidden then return a.hidden == b.hidden end
	if a.line ~= b.line or a.page ~= b.page or a.title ~= b.title or #a.items ~= #b.items then return false end
	for i, x in ipairs(a.items) do
		local y = b.items[i]
		if x.id ~= y.id or x.enabled ~= y.enabled or x.tooltip ~= y.tooltip or x.label ~= y.label
			or x.icon ~= y.icon or x.iconClass ~= y.iconClass then return false end
	end
	return true
end
M.sameView = sameView

--- Shows entry `id`'s choices (id nil: the entries again); the menu stays open.
function M.openPage(id)
	menu.page = id
end

--- The id of the entry whose choices are shown, or nil.
function M.page()
	return menu.page
end

--- Runs entry `id` on the current context (a click in the menu); closes the menu.
function M.runEntry(id, params)
	local tPerf = perf:start()
	local e = entryById(id)
	if e and e.choices and not e.run then
		-- a second level: show its choices, keep the menu open
		M.openPage(e.id)
		perf:stop("line_actions", tPerf)
		return
	end
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

--- Runs choice `choiceId` of entry `entryId`'s page (a click in it); Back returns to the entries, any other choice
--- runs the entry's choose() and closes the menu.
function M.runChoice(entryId, choiceId, params)
	if choiceId == M.BACK_ID then
		M.openPage(nil)
		return
	end
	local tPerf = perf:start()
	local e = entryById(entryId)
	local ctx = M.context()
	if e and e.choose and ctx then
		local ok, err = pcall(e.choose, ctx, choiceId)
		if not ok then
			warnOnce(entryId .. " choose", err)
			M.feedback(ctx.params, _("Line Manager Plus: the line action failed (see log)."), true)
		end
	end
	closeMenu(params or (ctx and ctx.params))
	perf:stop("line_actions", tPerf)
end

-- Inline styles (built once on first render; nil offline) -----------------------------------------------------------
local styleCache = nil

local function vec4(t, r, b, l) return api.type.Vec4f.new(t, r, b, l) end

local function ninePatch(file)
	local n = api.gui.NinePatch.new()
	n.fileName = file
	n.horizontal = { 0, 6, 26, 32 }
	n.vertical = { 0, 6, 26, 32 }
	return n
end

local function sheet(fields)
	local s = api.gui.StyleSheet.new()
	for k, val in pairs(fields) do s[k] = val end
	return s
end

local function buildSheets()
	local c = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data
	local tr = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data
	local function col(rgb, a) return vec4(rgb[1], rgb[2], rgb[3], a or rgb[4] or 1) end
	return {
		-- the base header's margin 8 8 1 8 (line_vehicle_mgmt.css.lua:993-997)
		headerWrap = sheet{ padding = vec4(8, 8, 1, 8) },
		-- "!auto-rename-lines-header" (:977-991, :1006-1008)
		header = sheet{
			backgroundImage1 = ninePatch("::/gui/entity_window/design/card_surface.tga"),
			borderImage = ninePatch("::/gui/entity_window/design/card_contour.tga"),
			backgroundColor1 = col(c.BaseVeryLight, tr.Low),
			borderColor = col(c.BaseVeryLight),
			size = api.type.Vec2f.new(-1, 36),
			padding = vec4(2, 8, 2, 8),
		},
		-- the base ScrollArea's margin 1 4 8 4 plus its padding 2 (:1010-1016)
		rowsWrap = sheet{ padding = vec4(3, 6, 10, 6) },
		gap = sheet{ size = api.type.Vec2f.new(4, 1) },
		disabled = sheet{ backgroundColor1 = col(c.NeutralMedium, tr.VeryHigh) },
	}
end

local NO_SHEETS = {}
local function sheets()
	if styleCache == nil then
		local ok, sh = pcall(buildSheets)
		if not ok then
			if api and api.gui and api.gui.StyleSheet then warnOnce("styles", sh) end
			sh = NO_SHEETS
		end
		styleCache = sh
	end
	return styleCache
end

-- A Component that fills the menu's width (base class "horizontal-spacer", gravity -1 0) around a vertical list.
local function fill(styleSheet, children)
	return builtin.Component{
		meta = { class = "horizontal-spacer", styleSheet = styleSheet },
		layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children },
	}
end

local function header(sh, title)
	return builtin.Component{
		meta = { class = "horizontal-spacer", styleSheet = sh.header },
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = { builtin.TextView{ meta = { class = "font-scale-headline" }, text = title } },
		},
	}
end

--- One menu row: an Auto-Rename style Button (icon, gap, text left-aligned); lmp.css.lua colours it. `item` carries
--- the translated label, the icon path and an optional icon class (cargo icons: the base "text-icon-size-hack",
--- 20 x 20, default.css.lua:70-72).
local function row(item, onClick)
	local sh = sheets()
	local icon = item.iconClass
		and builtin.ImageView{ meta = { class = item.iconClass }, path = item.icon,
			scaling = builtin.type.ImageViewScaling.AutoFit }
		or builtin.ImageView{ path = item.icon, scaling = builtin.type.ImageViewScaling.AutoFit }
	return builtin.Button{
		meta = {
			tooltip = item.tooltip,
			enabled = item.enabled,
			styleSheet = (not item.enabled) and sh.disabled or nil,
		},
		content = builtin.Component{
			meta = { class = "horizontal-spacer" },
			layout = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = {
					icon,
					builtin.Component{ meta = { styleSheet = sh.gap } },
					builtin.TextView{ meta = { class = "font-scale-body" }, text = item.label },
				},
			},
		},
		onClick = onClick,
	}
end
M.row = row

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
	local rowsList = {}
	if not v.hidden then
		for i, item in ipairs(v.items) do
			if v.page then
				rowsList[#rowsList + 1] = row(item, function() M.runChoice(v.page, item.id, p and p.params) end)
			elseif entryById(item.id) then
				rowsList[#rowsList + 1] = row(item, function() M.runEntry(item.id, p and p.params) end)
			end
			if i > M.MAX_ROWS then break end
		end
	end
	local children = {}
	if #rowsList > 0 then
		local sh = sheets()
		children = {
			fill(sh.headerWrap, { header(sh, v.title or _("Line actions")) }),
			fill(sh.rowsWrap, rowsList),
		}
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
	menu.page = nil
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
