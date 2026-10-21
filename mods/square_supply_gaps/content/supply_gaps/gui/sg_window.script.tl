-- Supply Gaps: ridge button + a plain singleton window (PLAN "Entry point", "Window", "Release cleanup").
-- The ridge plugin is always mounted (gui/main/game.tl:554 mounts ::MainModButtonAreaExtension), so it
-- owns the overlay tick: react.onStepTimer every overlay.TICK s, react.onStep for the paused fallback,
-- react.onUnmount to drop the session (sg_overlay.shutdown). The overlay is off at game load
-- (overlay.DEFAULT_ON) and switched on when the save says it was on (PLAN "Per-save state": onStep reads
-- the game-script flag via sg_saved.readOn until it is readable, at most sg_saved.LOAD_TRIES seconds).
-- Ticking "Show supply gaps" sends the flag to the game script (sg_saved.sendOn), which saves a change.
-- The window is NOT a tool (a tool is closed by the construction menu, and the
-- markers must survive tool changes): it only edits the session in sg_overlay.tl. Closing the window
-- keeps the overlay on.
-- GUI side is read-only toward the simulation; the only command is the "SupplyGaps.setOn" scripting event
-- (memory "Don't impact existing saves").
-- Patterns: ridge plugin + singleton window from mods/square_problem_radar/content/radar/gui/radar_hud.script.tl
-- (getDefaultWindowApi().addSingletonWindow / removeAllWindows, window-open check via an expiring state).
-- GUI rules (memory): a recipe returns a layout; never Component{layout = Recipe{}}; ScrollArea content
-- is a Component; only fields that exist in builtin.d.tl's *Param records.
-- Widget types: .cache/game/base/tealdef/scripts/builtin.d.tl

-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state (incl. the overlay modules and the
-- area-label install), the ridge plugin's first render, slow calls (> 16 ms, at most one line per
-- section per minute) and, with the "Debug: performance log" mod setting, a 30 s summary. Sections:
-- renders and clicks (GUI thread), the window's snapshot poll (useStepStateTimer, an onStepTimer
-- callback on a worker thread "Main Pool N"; api.type.Clock is safe there, docs/findings.md "Timers
-- and threads in GUI contexts"), the joined load / pause checks (Main Thread). The overlay tick has its
-- own instrument (ctx tick, sg_overlay.tl), the HUD area labels theirs (ctx hud, sg_labels.lua).
local sqperf = ug_require "square_supply_gaps::/sqperf/square_supply_gaps.lua" as SquareSupplyGapsSqPerf
local perf = sqperf.new({ mod = "square_supply_gaps", ctx = "gui", paramKey = "sqperf_log", first = { "ridge_render" } })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil

local overlay = ug_require "square_supply_gaps::/supply_gaps/sg_overlay.tl" as SupplyGapsOverlay
local labels = ug_require "square_supply_gaps::/supply_gaps/sg_labels.lua" as SupplyGapsLabels
local saved = ug_require "square_supply_gaps::/supply_gaps/sg_saved.tl" as SupplyGapsSaved

local LOG_PREFIX <const> = "[SQSG] "
local WINDOW_ID <const> = "squaresupplygaps.window"
local WINDOW_POLL <const> = 0.5
-- Rows of the cargo list before it scrolls.
local MAX_ROWS <const> = 12

--- pcall for a function without results: ok, error text.
local function try(fn : function()) : boolean, string
	local ok, e = pcall(function() : boolean
		fn()
		return true
	end)
	if ok then return true, nil end
	return false, tostring(e)
end

-- Load decision for the per-save flag (reset on unmount, i.e. every game load starts undecided).
local load : SupplyGapsSavedLoad = saved.newLoad()
local loadSec : number = nil

--- GUI thread (joined from onStep), at most once per wall second until decided: read the saved flag and
--- switch the overlay on if the game was saved with it on. Never sends anything (no write at load).
--- SQPERF section "load_check".
local loadCheck = perf:wrap("load_check", function()
	if load.done then return end
	local now = overlay.now()
	if loadSec == now then return end
	loadSec = now
	local ok, v = pcall(saved.readOn)
	local read : boolean = nil -- nil: not readable yet (retry next second)
	if ok then read = v as boolean else log.message(LOG_PREFIX .. "ERR readSaved " .. tostring(v)) end
	local r = saved.loadStep(load, read)
	if r == "on" then overlay.setOn(true) end
	if r == "on" or r == "off" then
		log.message(LOG_PREFIX .. "LOAD saved=" .. r .. " tries=" .. tostring(load.tries))
	end
end)

-- SQPERF section "step_check": the paused fallback check (joined from onStep; ticks in it are also in
-- the overlay's "tick" section).
local stepCheck = perf:wrap("step_check", function() overlay.stepCheck() end)

-- The content's state, set on every render and expired by react once the window is gone.
local windowState : ReactStateT<SupplyGapsSnapshot> = nil

--- After a click in the window (GUI thread): tick now and redraw the window from the new state, instead of
--- waiting up to WINDOW_POLL for the checkbox to flip and up to overlay.TICK for the markers and list.
--- SQPERF section "click_apply" (includes the tick, which is also timed as "tick").
local applyNow = perf:wrap("click_apply", function()
	overlay.tick("click")
	if windowState ~= nil and not windowState:hasExpired() then
		local ok, snap = pcall(overlay.snapshot)
		if ok then windowState:set(snap as SupplyGapsSnapshot) end
	end
end)

--- The "Show supply gaps" checkbox: the player's choice wins over a pending load read, and is sent to
--- the game script so it is saved with the game (only a change is written).
local function setShown(on : boolean)
	load.done = true
	overlay.setOn(on)
	local ok, m = try(function() saved.sendOn(on) end)
	if not ok then log.message(LOG_PREFIX .. "ERR sendOn " .. tostring(m)) end
end

-- Area labels: wrap the base town / Cargo Flow HUD recipes once at script load (sg_labels.lua). The base
-- reads them through the module tables at render time, so HUD icons built after this use the wrappers.
local labelsStatus : string
do
	local ok, r = pcall(labels.install)
	labelsStatus = ok and tostring(r) or ("err " .. tostring(r))
end

-- Inline styles instead of sg_window.css.lua rules (docs/findings.md "Load crash above ~200 mod stylesheet
-- rules": every rule counts). Only size / padding / color here (api gui.d.tl record StyleSheet), built
-- lazily in the window / ridge renders (GUI thread) and reused. Padding order is CSS (top, right, bottom,
-- left), as square_better_minimap's layerAt.
local record Styles
	content : StyleSheet  -- R::SupplyGapsContent: 320 px wide content
	ridge : StyleSheet    -- ridge Button padding
	ridgeOn : StyleSheet  -- ridge Button text while the overlay is on
	ridgeIconButton : StyleSheet  -- "Icon" ridge ToggleButton: 8 px padding (a 40 px tile)
	ridgeIcon : StyleSheet        -- "Icon" ridge icon: 24 px (colour from the base ToggleButton rules)
	ridgeIconButtonOn : StyleSheet  -- the same while the overlay is on: a green contour (Ok)
	dim : StyleSheet      -- legend lines and the "Options" heading
	scope : StyleSheet    -- scope line
end
local stylesCache : Styles = nil

local function styles() : Styles
	if stylesCache == nil then
		local content = styleutil.makeStyle{ size = { 320, -1 } }
		content.padding = api.type.Vec4f.new(4, 8, 8, 8)
		local ridge = api.gui.StyleSheet.new()
		ridge.padding = api.type.Vec4f.new(2, 8, 2, 8)
		-- "Icon" ridge ToggleButton: only its size inline (8 px padding: a 40 px tile like the
		-- layers and Timetables buttons in game); tile, pressed and hover states and the white icon come from
		-- the base ToggleButton rules (builtin.css.lua:138-240).
		-- While the overlay is on, the button's contour (the base border image, invisible except on
		-- hover: builtin.css.lua:138-158, 203-207) is drawn in the base Ok green instead of tinting the icon.
		-- Inline, so it replaces the hover contour while on.
		local colors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data as {string : {number}}
		local ridgeIconButton = api.gui.StyleSheet.new()
		ridgeIconButton.padding = api.type.Vec4f.new(8, 8, 8, 8)
		local ridgeIconButtonOn = styleutil.makeStyle{ borderColor = colors.Ok }
		ridgeIconButtonOn.padding = api.type.Vec4f.new(8, 8, 8, 8)
		stylesCache = {
			content = content,
			ridge = ridge,
			ridgeOn = styleutil.makeStyle{ color = { 0.45, 0.85, 0.55, 1.0 } },
			ridgeIconButton = ridgeIconButton,
			ridgeIconButtonOn = ridgeIconButtonOn,
			ridgeIcon = styleutil.makeStyle{ size = { 24, 24 } },
			dim = styleutil.makeStyle{ color = { 0.75, 0.75, 0.75, 1.0 } },
			scope = styleutil.makeStyle{ color = { 0.85, 0.85, 0.85, 1.0 } },
		}
	end
	return stylesCache
end

local function text(str : string, class? : string, style? : StyleSheet) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body", styleSheet = style },
		text = str,
	}
end

-- Every layout of ours carries "sqsg-box", so the .css.lua targets only our own BoxLayouts.
local function boxClass(class : string) : string
	return class and (class .. ", sqsg-box") or "sqsg-box"
end

local function hbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = boxClass(class) },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end

local function vbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = boxClass(class) },
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end

local function checkBox(label : string, value : boolean, onChange : function(boolean), tooltip : string) : TreeNodeId
	-- CheckBoxParam: builtin.d.tl:1024-1031; meta.tooltip on a CheckBox as base
	-- line_vehicle_mgmt/cargofilter_window.tl:755-758
	return builtin.CheckBox{
		meta = { tooltip = tooltip },
		value = value and 1 or 0,
		label = label,
		onValueChange = function(v : integer)
			local ok, m = try(function() onChange(v == 1) end)
			if not ok then log.message(LOG_PREFIX .. "ERR checkbox " .. tostring(m)) end
			applyNow()
		end,
	}
end

-- CargoTypeId -> icon path. Same node as cargo_react_util.makeCargoIcon(c, class)
-- (base/content/gui/main/cargo_react_util.tl:26-33: makeIcon(class, cargo_util.getCargoIconById(c), name),
-- an ImageView of CargoType.icon, cargo_util.tl:436-439) without its tooltip (the row has one) and
-- with one cargoTypeRep.get per cargo per session (pattern: industry_flows flows_window.script.tl:339-354).
-- No mouseTransparent on ImageView (memory: crashes).
local cargoIconPath : {integer : string} = {}

local function cargoIcon(c : integer) : TreeNodeId
	local path = cargoIconPath[c]
	if path == nil then
		local ok, p = pcall(function() : string return api.res.cargoTypeRep.get(c).icon end)
		path = (ok and p ~= nil) and p as string or ""
		cargoIconPath[c] = path
	end
	if path == "" then return nil end
	-- cargo_react_util.makeIcon(class, path, nil) inlined (cargo_react_util.tl:15-24): console builds ship
	-- their own base GUI scripts that can lack helpers (PS5 report 2026-10-19, Smart Lanes; docs/findings/gui.md
	-- "Base GUI modules differ by platform").
	return builtin.ImageView{ path = path, meta = { class = "text-icon-size-hack, sqsg-cargo-icon" } }
end

local function cargoRow(label : string, count : string, selected : boolean, onClick : function(), cargo : integer, tooltip : string) : TreeNodeId
	local children : {TreeNodeId} = {}
	children[#children + 1] = text(selected and ">" or " ", "font-scale-body, sqsg-row-mark")
	if cargo ~= nil then children[#children + 1] = cargoIcon(cargo) end
	children[#children + 1] = text(label, "font-scale-body, sqsg-row-name")
	children[#children + 1] = text(count, "font-scale-body, sqsg-row-count")
	return builtin.Button{
		meta = { class = selected and "sqsg-row, sqsg-row-selected" or "sqsg-row", tooltip = tooltip },
		content = hbox(children, "sqsg-row-box"),
		onClick = onClick,
	}
end

--- "unreached · starved / needed" (starved part only while starved buildings are shown).
local function countText(unreached : integer, starved : integer, needed : integer, includeStarved : boolean) : string
	if includeStarved then
		return tostring(unreached) .. " · " .. tostring(starved) .. " / " .. tostring(needed)
	end
	return tostring(unreached) .. " / " .. tostring(needed)
end

local function selectCargo(c : integer)
	local ok, m = try(function() overlay.setSelection(c) end)
	if not ok then log.message(LOG_PREFIX .. "ERR select " .. tostring(m)) end
	applyNow()
end

local function cargoList(snap : SupplyGapsSnapshot) : TreeNodeId
	local rows : {TreeNodeId} = {}
	local inc = snap.includeStarved
	local countHelp = inc and _("Count: not reached · in range but empty / buildings that need it.")
		or _("Count: not reached / buildings that need it.")
	rows[#rows + 1] = cargoRow(_("All needed"), countText(snap.unreached, snap.starved, snap.buildings, inc),
		snap.selection == nil, function() selectCargo(nil) end, nil,
		_("Show every cargo the towns need.") .. " " .. countHelp)
	for __, r in ipairs(snap.rows) do
		local c = r.cargo
		rows[#rows + 1] = cargoRow(r.name, countText(r.needed - r.reached, r.starved, r.needed, inc),
			snap.selection == c, function() selectCargo(c) end, c,
			_("Show only this cargo.") .. " " .. countHelp)
	end
	if #rows <= MAX_ROWS then
		return vbox(rows, "sqsg-rows")
	end
	-- ScrollArea content must be a Component with a builtin layout (memory "ScrollArea content is a Component").
	return vbox({
		builtin.ScrollArea{
			meta = { class = "sqsg-scroll" },
			content = builtin.Component{ layout = vbox(rows, "sqsg-rows") },
		},
	})
end

local function summary(snap : SupplyGapsSnapshot) : string
	if snap.ticks == 0 then return _("Reading towns and stops...") end
	local s : string
	if snap.includeStarved then
		s = string.format(_("%d not reached, %d in range but empty (of %d buildings with needs)."),
			snap.unreached, snap.starved, snap.buildings)
	else
		s = string.format(_("%d not reached (of %d buildings with needs)."), snap.unreached, snap.buildings)
	end
	if snap.capped then
		s = s .. " " .. string.format(_("Marking the %d nearest."), snap.markers)
	end
	return s
end

--- Header: which towns the counts cover.
local function scopeLine(snap : SupplyGapsSnapshot) : string
	if snap.ticks == 0 then return nil end
	local s : string
	if snap.scoped then
		if snap.viewTowns == 0 then
			s = _("In view: no towns. Pan to a town or untick \"Only towns in view\".")
		else
			-- viewText: town names from the game (already localized) joined with ", ".
			s = string.format(_("In view: %s"), snap.viewText)
		end
	else
		s = string.format(_("Whole map: %d towns"), snap.viewTowns)
	end
	if snap.pending > 0 then
		s = s .. " " .. string.format(_("(reading %d buildings)"), snap.pending)
	end
	return s
end

-- Only meta (the inline padding / size of this recipe's node, applied by react through
-- WithComponentParams, as base callout_container.tl:122-127 sets a recipe's meta.styleSheet).
local record SupplyGapsContentParam is IRecipeParamWithMeta
end

-- SQPERF sections "window_render" (GUI thread) and "window_poll" (onStepTimer, worker thread).
local SupplyGapsContent = react.RegisterRecipe("SupplyGapsContent", perf:wrap("window_render", function(__ : SupplyGapsContentParam) : TreeNodeId
	local state = engine_react_util.useStepStateTimer(function() : SupplyGapsSnapshot
		local tPoll = perf:start()
		local ok, snap = pcall(overlay.snapshot)
		perf:stop("window_poll", tPoll)
		if ok then return snap as SupplyGapsSnapshot end
		return nil
	end, WINDOW_POLL)
	windowState = state
	local snap = state:old()
	if snap == nil then
		return vbox({ text(_("Supply Gap Overview is not available.")) }, "sqsg-content")
	end
	local rows : {TreeNodeId} = {
		checkBox(_("Show supply gaps"), snap.on, setShown,
			_("Mark town buildings that need a cargo and aren't getting it. Saved with the game.")),
	}
	if not snap.on then
		rows[#rows + 1] = text(_("Tick to mark the town buildings that miss a cargo."), "font-scale-annotation, sqsg-legend, sqsg-wrap",
			styles().dim)
	end
	-- Options above the cargo list, so they keep their place while the list grows and shrinks.
	rows[#rows + 1] = text(_("Options"), "font-scale-body, sqsg-section, sqsg-gap", styles().dim)
	rows[#rows + 1] = checkBox(_("Only towns in view"), snap.scoped, function(on : boolean) overlay.setScoped(on) end,
		_("Count and mark only the towns on screen. Untick for the whole map."))
	rows[#rows + 1] = checkBox(_("Include in-range but empty"), snap.includeStarved, function(on : boolean) overlay.setStarved(on) end,
		_("Also mark buildings in range of a delivering stop whose stock of the cargo stays empty."))
	rows[#rows + 1] = checkBox(_("Area labels"), snap.labels, function(on : boolean) overlay.setLabels(on) end,
		_("Under each town name, the share of each district's buildings that get the cargo (the worst three with All needed)."))
	rows[#rows + 1] = checkBox(_("Count stops without a line"), snap.unlined, function(on : boolean) overlay.setUnlined(on) end,
		_("Treat cargo stops that no line serves yet as delivering, to preview a new stop's coverage."))
	if snap.on then
		local header = scopeLine(snap)
		if header ~= nil then rows[#rows + 1] = text(header, "font-scale-body, sqsg-scope, sqsg-wrap, sqsg-gap", styles().scope) end
		rows[#rows + 1] = cargoList(snap)
		rows[#rows + 1] = text(summary(snap), "font-scale-annotation, sqsg-summary, sqsg-wrap")
		rows[#rows + 1] = text(_("Yellow arrow: no stop that delivers the cargo is in range."), "font-scale-annotation, sqsg-legend, sqsg-wrap",
			styles().dim)
		if snap.includeStarved then
			rows[#rows + 1] = text(_("Red question mark: a delivering stop is in range, but the stock has been empty for about 20 s."),
				"font-scale-annotation, sqsg-legend, sqsg-wrap", styles().dim)
		end
	end
	-- The recipe sits in a Window's content: return a layout (memory "Recipe must return layout").
	return vbox(rows, "sqsg-content")
end))

local record SupplyGapsWindowParam
	onClose : function()
end

-- Window fields differ by platform: the PS5 build rejects `closable` and react.lua makeUserdata then fails
-- the whole UI (docs/findings/gui.md "Window fields differ by platform"). Each field is tried once on a spare
-- Window param object; a field this platform rejects is left out and logged once. Nodes and meta aren't tried.
local windowFieldOk : {string : boolean} = {}
local function platformWindow<T>(p : T) : T
	local t = p as {string : any}
	for k, v in pairs(t) do
		if k ~= "content" and k ~= "header" and k ~= "meta" then
			local key = k .. "=" .. (v is boolean and tostring(v) or type(v))
			if windowFieldOk[key] == nil then
				local made, ud = pcall(function() : {string : any}
					local reactApi = ((api as table).gui as table).react as table
					local builtins = (reactApi.params as table).builtin as table
					return ((builtins.Window as table).new as function() : {string : any})()
				end)
				-- no spare object to try on: keep the field, as before this guard
				windowFieldOk[key] = not made or pcall(function() ud[k] = v end)
				if not windowFieldOk[key] then
					log.warning("[SupplyGaps] this platform's Window rejects '" .. key .. "'; left out")
				end
			end
			if not windowFieldOk[key] then t[k] = nil end
		end
	end
	return p
end

local SupplyGapsWindow = react.RegisterWrapperRecipe("SupplyGapsWindow", builtin.Window, function(params : SupplyGapsWindowParam) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210
	return builtin.Window(platformWindow{
		id = WINDOW_ID,
		title = _("Supply Gap Overview"),
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = SupplyGapsContent({ meta = { styleSheet = styles().content } }),
	})
end)

local function closeWindow()
	windowState = nil
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then wa.removeAllWindows(SupplyGapsWindow) end
end

local function openWindow()
	-- getDefaultWindowApi may return nil (game_react_globals.tl:14-20)
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.message(LOG_PREFIX .. "ERR no window container; cannot open the window")
		return
	end
	wa.addSingletonWindow(SupplyGapsWindow, { onClose = closeWindow })
	wa.moveSingletonWindowToFront(SupplyGapsWindow)
end

local function windowOpen() : boolean
	return windowState ~= nil and not windowState:hasExpired()
end

-- SQPERF section "click_toggle" (onClick: GUI thread).
local toggleWindow = perf:wrap("click_toggle", function()
	local ok, m = try(function()
		if windowOpen() then closeWindow() else openWindow() end
	end)
	if not ok then log.message(LOG_PREFIX .. "ERR toggleWindow " .. tostring(m)) end
end)

-- Ridge button in the "Icon" style (mod.json hudButtonStyle): house with a minus badge, gaps@2x.tga 48x48
-- (tools/render_icon_ridge.py), shown at 24 UI px like the base layers icon and Better Minimap's map icon.
local RIDGE_ICON <const> = "square_supply_gaps::/supply_gaps/gui/gaps.tga"

--- mod.json hudButtonStyle: { "Text", "Icon" } (1-based index; default Icon). Missing or unreadable = Icon.
--- Read once per mount: mod params are fixed per game.
local function ridgeIconSetting() : boolean
	local ok, all = pcall(function() : {string : any} return api.engine.config.getModParams() as {string : any} end)
	local mine = ok and type(all) == "table" and all["square_supply_gaps"] as {string : any} or nil
	local v = type(mine) == "table" and mine["hudButtonStyle"] or nil
	return v ~= 1
end

--- A plugin recipe's root must be a layout (MainModButtonArea mounts plugins as BoxLayout children).
--- SQPERF section "ridge_render" (GUI thread).
local SupplyGapsRidgePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "SupplyGapsRidgePlugin", perf:wrap("ridge_render", function() : TreeNodeId
	-- Hooks first, unconditionally.
	local isMapEditorRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean return api.gui.game.isMapEditor() end)
	local iconRef : ReactRefT<boolean> = react.useRefLazy(ridgeIconSetting)
	-- The "Icon" ToggleButton is pressed while the window is open, however it was closed.
	local openState = react.useState(false) as ReactStateT<boolean>
	local function syncOpen()
		local open = windowOpen()
		if open ~= openState:old() then openState:set(open) end
	end
	local onState = engine_react_util.useStepStateTimer(function() : boolean return overlay.session.on end, WINDOW_POLL)
	-- onStep/onStepTimer run on worker threads ("Main Pool N"); mission markers and the camera are
	-- GUI-thread only (a direct call crashed the game), so the work is joined onto the main thread.
	react.onStepTimer(function()
		if overlay.session.on and not isMapEditorRef:get() then react.enqueueJoin(overlay.timerTick, "SupplyGaps:tick") end
	end, overlay.TICK)
	react.onStep(function()
		if isMapEditorRef:get() then return end
		if iconRef:get() then syncOpen() end
		if not load.done then react.enqueueJoin(loadCheck, "SupplyGaps:load") end
		if overlay.session.on then react.enqueueJoin(stepCheck, "SupplyGaps:stepCheck") end
	end)
	local initRef = react.useRef(false) as ReactRefT<boolean>
	react.onUnmount(function(__ : any)
		overlay.shutdown()
		load, loadSec = saved.newLoad(), nil
	end)

	if not initRef:get() then
		initRef:set(true)
		log.message(LOG_PREFIX .. "INIT mapEditor=" .. tostring(isMapEditorRef:get()) .. " on=" .. tostring(overlay.session.on)
			.. " labels " .. labelsStatus)
	end
	if isMapEditorRef:get() then
		return nil
	end
	local on = onState:old() == true
	local tooltip = _("Supply Gap Overview")
	if iconRef:get() then
		-- "Icon" style: a base ToggleButton like the data layers button next to it (layers_button_ridge.tl:
		-- 529-539) and Timetables' ridge button, pressed while the window is open; a green contour
		-- while the overlay is on (the text turns green).
		return hbox({
			builtin.ToggleButton{
				meta = { class = on and "sqsg-ridge-icon-button, sqsg-ridge-on" or "sqsg-ridge-icon-button",
					styleSheet = on and styles().ridgeIconButtonOn or styles().ridgeIconButton, tooltip = tooltip },
				content = builtin.ImageView{
					meta = { class = "sqsg-ridge-icon", styleSheet = styles().ridgeIcon },
					path = RIDGE_ICON,
				},
				value = openState:old() and 1 or 0,
				onValueChange = function(__ : integer)
					toggleWindow()
					syncOpen()
				end,
			},
		}, "sqsg-ridge")
	end
	return hbox({
		builtin.Button{
			meta = { class = on and "sqsg-ridge-button, sqsg-ridge-on" or "sqsg-ridge-button", styleSheet = styles().ridge,
				tooltip = tooltip },
			content = text(on and _("Gaps: on") or _("Gaps"), nil, on and styles().ridgeOn or nil),
			onClick = toggleWindow,
		},
	}, "sqsg-ridge")
end))

local result = {
	SupplyGapsRidgePlugin = SupplyGapsRidgePlugin,
}

perf:phase("init", perfInit)

return result
