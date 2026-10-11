-- Industry Flows: ridge button + panel window that draws the base game's 3D cargo-flow arrows for
-- every industry of the selected types at once (PLAN phase 3: search field, type list with counts
-- and multi-select, Outputs / Inputs / Potential toggles, summary line).
-- GUI only, read-only: no game script, no commands, nothing saved. The panel remembers its search,
-- selection and toggles in a module-level table (GUI memory for the session, never the savegame).
-- Widget types: .cache/game/base/tealdef/scripts/builtin.d.tl
--
-- HOW THE ARROWS GET DRAWN (PLAN, answered in phase 1):
-- A builtin.LayerConfig only takes effect as a child of the builtin.ActionDescriptor of the TOP tool
-- on the game's ToolStack. Each tool entry binds its action function to the renderer component and
-- the stack makes the top entry the active owner (.cache/game/base/content/gui/main/builtin.lua:
-- 1162-1194 ToolStackEntryWrap: react.useAction + setActiveOwner when ctx.isTop; :1240-1248
-- updateTop; :1339-1353 push; :1383-1390 push without allowStacking clears the stack first).
-- Base windows that draw arrows are tools that call ctx.setActionFn: the industry window
-- (entity_window/industry/industry.tl:362-410), the subsidy window (subventions_gui.tl:438-472),
-- the layers (layers/layer_cargo_flow.tl:327-352) and Statistics (statistics/statistics.tl:279-467).
-- react.useAction itself is marked "for internal use only" (.cache/game/base/tealdef/scripts/react.d.tl:372).
-- So this window is registered as a TOOL with tool_react_util.registerToolWithWindow (the base
-- MusicPlayer / Company / Finances pattern: gui/music_player/music_player.tl:265-287,
-- game_mechanics/company/company.tl:965), pushed onto the default tool stack that
-- game_react_globals exposes to mods (.cache/game/base/content/gui/main/game_react_globals.tl:22-28,
-- game.tl:608-610), and its content calls payload.setActionFn with an ActionDescriptor holding the
-- LayerConfig. Closing the window pops the tool (tool_react_util.tl:16-25, :52-59), which clears the
-- action (builtin.lua:1287-1305, setActionFn(nil) at :1300), so the arrows go away with the window.

-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state, the panel's first render, slow
-- renders / clicks / view rebuilds (> 16 ms, at most one line per section per minute), and with the
-- "Debug: performance log" mod setting a 30 s summary. Most timed sections run on the GUI thread
-- (recipe renders, onClick / onValueChange handlers). The slow poll runs in a react onStepTimer
-- callback (worker thread "Main Pool N", engine_react_util.tl useStepStateTimer) and is timed too:
-- api.type.Clock is safe there (docs/findings.md "Timers and threads in GUI contexts"); it makes no
-- api.gui call (the window visibility comes from react.onStep). "poll_shelved" counts the timer
-- ticks skipped while the panel is shelved. Local counters only; nothing is saved.
local sqperf = ug_require "square_industry_flows::/sqperf/square_industry_flows.lua" as SquareIndustryFlowsSqPerf
local perf = sqperf.new({ mod = "square_industry_flows", ctx = "gui", paramKey = "sqperf_log", first = { "content_render" } })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local cargo_react_util = ug_require "::/gui/main/cargo_react_util.tl" as CargoReactUtil
local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local lang_util = ug_require "::/scripts/lang_util.tl" as LangUtil
local table_util = ug_require "::/scripts/table_util.tl" as TableUtil
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
-- mod precedent for game_react_globals: .cache/game/mods/release/urbangames_campaign_mission_05/content/mission/perk_icons_replacement.script.tl:4
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local hud_icon_toolbox = ug_require "::/gui/main/hud_icon_toolbox.tl" as HudIconToolbox
local hud_react_util = ug_require "::/gui/hud/hud_react_util.tl" as HudReactUtil
local selector_react_util = ug_require "::/gui/main/selector_react_util.tl" as SelectorReactUtil
local tool_react_util = ug_require "::/gui/main/tool_react_util.tl" as ToolReactUtil

local gather = ug_require "square_industry_flows::/industry_flows/flows_gather.tl" as IndustryFlowsGather
local model = ug_require "square_industry_flows::/industry_flows/flows_model.tl" as IndustryFlowsModel

local REFRESH_SECONDS <const> = 2.0
local SCROLL_ROWS <const> = 8                    -- more matching types than this: the list scrolls
local WINDOW_ID <const> = "squareindustryflows.window"
local TOOL_NAME <const> = "SquareIndustryFlows"     -- react.RegisterTool names are global (react.lua:576-590)
local ACTION_KEY <const> = "square_industry_flows"  -- key2 of setActionFn (industry.tl:410 uses "industry")
local RIDGE_BUTTON_PADDING <const> : {number} = { 2, 8, 2, 8 }  -- inline (was Button!flows-ridge-button in the .css.lua)

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body" },
		text = str,
	}
end

-- Every layout of ours carries "flows-box", so the .css.lua rules target only our own BoxLayouts.
local function box(children : {TreeNodeId}, horizontal : boolean, class? : string) : TreeNodeId
	return builtin.BoxLayout{
		meta = { class = class and (class .. ", flows-box") or "flows-box" },
		orientation = horizontal and builtin.type.Orientation.Horizontal or builtin.type.Orientation.Vertical,
		children = children,
	}
end

local function vbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return box(children, false, class)
end

local function hbox(children : {TreeNodeId}, class? : string) : TreeNodeId
	return box(children, true, class)
end

-- .gres data by path. GUI resources do not change during a session, so each is looked up once
-- (the base industry window keeps its layer colours in module locals too, industry.tl:20-21).
local gresCache : {string : any} = {}

local function gres(path : string) : any
	local data = gresCache[path]
	if data == nil then
		data = api.gui.genericRep.get(api.gui.genericRep.find(path)).data
		gresCache[path] = data
	end
	return data
end

---------------------------------------------------------------------------
-- Session memory (GUI only). Survives closing and reopening the panel until the game's GUI Lua
-- state is rebuilt (e.g. loading another save). Nothing here reaches the savegame or game script.

local session : IndustryFlowsPanelState = nil

local function getSession() : IndustryFlowsPanelState
	if session == nil then session = model.newPanelState() end
	return session
end

-- The last engine read, so a selection / toggle change rebuilds the arrows at once without
-- re-reading the map, and typing only filters the type list of the last poll.
local lastWorld : IndustryFlowsWorld = nil

---------------------------------------------------------------------------
-- LayerConfig from a view, exactly like industry.tl:329-361: actual links move (speed 40) in the
-- "Actual" colours with full cargo icons, potential links stand still (speed 0) in the "Potential"
-- colours at transparency VeryLow with icons at 0.6. Inputs use Suppliers3D, outputs Consumers3D.

local record FlowColors
	inActual : {Vec4f}
	inPotential : {Vec4f}
	outActual : {Vec4f}
	outPotential : {Vec4f}
end

local colorsCache : FlowColors = nil

local function flowColors() : FlowColors
	if colorsCache == nil then
		-- src: industry.tl:20-21 (the same two .gres lookups)
		local layerColors = gres("::/gui/layers/layer_colors.gres") as LayerColors
		local transparency = gres("::/gui/main/transparency.gres") as GResTransparency
		colorsCache = {
			inActual = color_util.toArray4(layerColors.CargoFlow.Suppliers3D.Actual),
			inPotential = color_util.toArray4WithTransparency(layerColors.CargoFlow.Suppliers3D.Potential, transparency.VeryLow),
			outActual = color_util.toArray4(layerColors.CargoFlow.Consumers3D.Actual),
			outPotential = color_util.toArray4WithTransparency(layerColors.CargoFlow.Consumers3D.Potential, transparency.VeryLow),
		}
	end
	return colorsCache
end

local function vec3(p : {number}) : Vec3f
	return api.type.Vec3f.new(p[1], p[2], p[3])
end

local function buildLayerConfig(view : IndustryFlowsView) : LayerConfig
	local layerConfig = api.type.LayerConfig.new()
	if view == nil or #view.links == 0 then
		return layerConfig
	end
	local colors = flowColors()
	local flowData : {LayerConfig.CargoFlowRenderableConfig.FlowData} = {}
	for __, link in ipairs(view.links) do
		local d = api.type.LayerConfig.CargoFlowRenderableConfig.FlowData.new()
		d.from = vec3(link.from)
		d.to = vec3(link.to)
		d.speed = link.active and 40.0 or 0.0
		if link.input then
			d.arrowColors = link.active and colors.inActual or colors.inPotential
		else
			d.arrowColors = link.active and colors.outActual or colors.outPotential
		end
		d.cargoIconAlpha = link.active and 1.0 or 0.6
		d.cargoTypes = { link.cargo }
		flowData[#flowData + 1] = d
	end
	local cargoFlowRenderableConfig = api.type.LayerConfig.CargoFlowRenderableConfig.new()
	cargoFlowRenderableConfig.flowData = flowData
	layerConfig.cargoFlowRenderableConfig = cargoFlowRenderableConfig
	return layerConfig
end

---------------------------------------------------------------------------
-- HUD icons (town / station / industry labels, vehicles) while the panel's action is active.
-- An action without a HudIconManagerConfig shows no HUD icons. Same config as the base default
-- action (.cache/game/base/content/gui/main/selector_react_util.tl:324-345, makeDefaultSelectorAction,
-- used e.g. by the warehouse window, entity_window/warehouse/warehouse.tl:96) with the player's HUD
-- filter (makePreFilter, selector_react_util.tl:43-86, re-done here because it is local there).
-- That helper is not used directly because its selector does not stack entity windows on top of
-- this tool (makeDefaultSelector(..., allowStacking = nil), selector_react_util.tl:108).
-- No accessNotificationCacheFn (the plugin gets no gameCtx): HudIconMasterGame then skips the
-- notification icons (hud_icon_toolbox.tl:359); the layers pass one only for those icons
-- (layer_cargo_flow.tl:339-342).

local record HudPreFilter
	preFilter : {Engine.ComponentType}
	preFilterTvCarriers : {Carrier}
	showCosts : boolean
	showIncome : boolean
end

local function hudPreFilter() : HudPreFilter
	local ok, saved = pcall(api.gui.game.getGuiSaveData, "")
	local filters : BaseGUISaveData.HUDFilter = nil
	if ok and saved ~= nil then
		filters = (saved as BaseGUISaveData).hudFilter
	end
	if filters == nil or filters.preFilters == nil then
		-- makePreFilter's default branch (selector_react_util.tl:71-78)
		return { preFilter = selector_react_util.defaultHudIconFilter, preFilterTvCarriers = nil, showCosts = true, showIncome = true }
	end
	local preFilters = filters.preFilters
	local carriers : {Carrier} = nil
	if filters.preFilterTvCarriers ~= nil then
		carriers = {}
		for __, carrier in ipairs(selector_react_util.defaultHudIconFilterTvCarrier) do
			if filters.preFilterTvCarriers[carrier] ~= "Hidden" then
				carriers[#carriers + 1] = carrier
			end
		end
		if #carriers == 0 then
			-- every carrier hidden: hide vehicles altogether (selector_react_util.tl:61-64; we copy
			-- preFilters itself, so the saved GUI data is never modified)
			carriers = nil
			preFilters = table_util.copy(preFilters) as {Engine.ComponentType : BaseGUISaveData.FilterState}
			preFilters[api.type.ComponentType.TRANSPORT_VEHICLE] = "Hidden"
		end
	end
	local preFilter : {Engine.ComponentType} = {}
	for __, componentType in ipairs(selector_react_util.defaultHudIconFilter) do
		if preFilters[componentType] ~= "Hidden" then
			preFilter[#preFilter + 1] = componentType
		end
	end
	return { preFilter = preFilter, preFilterTvCarriers = carriers, showCosts = filters.showCosts, showIncome = filters.showIncome }
end

-- Plain == per element: works whether the enums are numbers or engine constants, and a false
-- "changed" only costs one action rebind (the behaviour before the cache).
local function sameList<T>(a : {T}, b : {T}) : boolean
	if a == b then return true end
	if a == nil or b == nil or #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function samePreFilter(a : HudPreFilter, b : HudPreFilter) : boolean
	return a ~= nil and b ~= nil and sameList(a.preFilter, b.preFilter)
		and sameList(a.preFilterTvCarriers, b.preFilterTvCarriers)
		and a.showCosts == b.showCosts and a.showIncome == b.showIncome
end

local function makeHudIconManagerConfig(pre : HudPreFilter) : TreeNodeId
	-- src: selector_react_util.tl:327-345
	local hudGuiConfig = gres("::/gui/hud/hud_gui_config.gres") as HudGuiConfig
	local sfxFinance = gres("::/game_mechanics/finance/sound/finance_sfx.gres") as FinanceSFX
	return builtin.HudIconManagerConfig{
		userParam = {},
		masterRecipe = hud_icon_toolbox.HudIconMasterGame,
		preFilter = pre.preFilter,
		preFilterTvCarriers = pre.preFilterTvCarriers,
		showCosts = pre.showCosts,
		showIncome = pre.showIncome,
		incomeSFX = sfxFinance.Income or {},
		costsRenderDistance = hudGuiConfig.renderDistances.Costs,
		visibilityThresholds = hud_react_util.makeDefaultVisibilityThresholds(),
		vehicleIconOffsets = hud_react_util.makeVehicleIconOffsets(hudGuiConfig.vehicleIconOffsets),
	}
end

-- The action of the last render. setActionFn ignores a call with the same function and key2
-- (builtin.lua:1165-1175, propagateActionFn returns cur); a new function makes react.useAction
-- unbind the old action and bind the new one (react.lua:611-614), which re-evaluates the whole
-- ActionDescriptor (HUD icon manager, selector, LayerConfig). So the function is only replaced when
-- something it closes over changes, not on every keystroke or checkbox click.
local record LayerCache
	view : IndustryFlowsView      -- the view the config was built from (compared by identity)
	config : LayerConfig
	pre : HudPreFilter            -- the HUD filter actionFn was built with
	rc : any                      -- the renderer component actionFn was built with
	actionFn : function() : TreeNodeId
end

---------------------------------------------------------------------------
-- Data: one engine read per poll; the view is rebuilt from the cached read on every change.

local record PanelData
	types : {IndustryFlowsType}   -- model.groupTypes of the last read (the search filters these)
	view : IndustryFlowsView      -- nil: not read (or the read failed)
end

local function buildView(world : IndustryFlowsWorld, state : IndustryFlowsPanelState) : IndustryFlowsView
	if world == nil then return nil end
	local ok, view = pcall(model.buildView, world, state.selection, state.toggles, gather.flowCount)
	if not ok then
		log.warning("[IndustryFlows] buildView failed: " .. tostring(view))
		return nil
	end
	return view as IndustryFlowsView
end

--- False while the window is hidden by the tool stack (shelved under a stacked entity window,
--- tool_react_util.tl:61-71 setVisible(windowId, false)). Then our action is not the top one and its
--- arrows are not drawn (builtin.lua:1162-1194, only the top entry is the active owner), so the
--- poll would be wasted. Own flag only (api/tealdef/api/gui.d.tl:404-407), not isVisibleRecursive:
--- with the whole GUI hidden the tool stays on top and its arrows still show.
--- GUI THREAD ONLY: called from react.onStep (Main Thread, docs/findings.md "Timers and threads in
--- GUI contexts"; base reads byId visibility in onStep too: mission_framework_react.tl:947 and
--- game_bar.tl:347 via engine_react_util.useStepState). Never from the onStepTimer poll: it runs on
--- worker threads, where api.gui calls can hard-crash the game.
local function panelVisible() : boolean
	local ok, visible = pcall(api.gui.byId.isVisible, WINDOW_ID)
	return not ok or visible ~= false
end

--- Read the map (slow poll) and build the view for the current session state.
local function poll() : PanelData
	local ok, world = pcall(gather.readWorld)
	if not ok then
		log.warning("[IndustryFlows] readWorld failed: " .. tostring(world))
		return { types = {}, view = nil }
	end
	lastWorld = world as IndustryFlowsWorld
	return { types = model.groupTypes(lastWorld), view = buildView(lastWorld, getSession()) }
end

-- SQPERF section "poll_open": the panel's first poll, run by useStateLazy inside the first render
-- (GUI thread), so it can be timed; the timer polls are only counted ("poll").
local pollOnOpen = perf:wrap("poll_open", poll)

-- Diagnostics for the in-game test: every industry type with its display name and count, logged once
-- per session when the panel first opens (confirms the type keys and the localized names).
local loggedTypes = false
local function logTypesOnce(data : PanelData)
	if loggedTypes or data == nil then return end
	loggedTypes = true
	local parts : {string} = {}
	for __, t in ipairs(data.types) do
		parts[#parts + 1] = t.name .. " = " .. t.key .. " x" .. tostring(t.count)
	end
	log.message("[IndustryFlows] industry types: " .. table.concat(parts, ", "))
end

local function logView(view : IndustryFlowsView)
	if view == nil or #view.typeKeys == 0 then return end
	log.message("[IndustryFlows] " .. table.concat(view.typeKeys, ", ") .. ": " .. tostring(view.industries) .. " industries, "
		.. tostring(view.total) .. " links (" .. tostring(view.active) .. " active), " .. tostring(view.drawn) .. " drawn")
end

---------------------------------------------------------------------------
-- Tool + window.

local record IndustryFlowsToolParam is ToolReactUtil.IToolParam
end

-- Small right chevron between input and output cargos (base: main/collapsible_checkbox_list.tl).
local CARGO_ARROW_ICON <const> = "::/gui/builtin/combobox/arrow_right.tga"
local CARGO_ARROW_SIZE <const> : {number} = { 10, 10 }        -- inline (was ImageView!flows-cargo-arrow in the .css.lua)

--- The type's cargos as icons, "inputs > outputs" (a raw producer shows only its outputs). Each icon
--- has the cargo name as tooltip; 20 px like the Statistics industry table
--- (statistics/statistic_industries.tl:97, "text-icon-size-hack" = 20x20 in main/default.css.lua:70-72).
local record CargoIconInfo
	path : string
	tooltip : string
end

-- CargoTypeId -> icon path and tooltip. cargo_react_util.makeCargoIcon does two
-- api.res.cargoTypeRep.get per icon (cargo_react_util.tl:26-33 and cargo_util.getCargoIconById,
-- cargo_util.tl:436-439) on every render; cargo resources do not change in a session (the same
-- assumption as gather.cargoName), so each cargo is looked up once.
local cargoIconCache : {integer : CargoIconInfo} = {}

--- Same node as cargo_react_util.makeCargoIcon(c, class): makeIcon(class, cargoType.icon, cargoType.name).
local function cargoIcon(c : integer) : TreeNodeId
	local info = cargoIconCache[c]
	if info == nil then
		local cargoType = api.res.cargoTypeRep.get(c)
		info = { path = cargoType.icon, tooltip = cargoType.name }
		cargoIconCache[c] = info
	end
	return cargo_react_util.makeIcon("text-icon-size-hack, flows-cargo", info.path, info.tooltip)
end

local function cargoIcons(row : IndustryFlowsTypeRow) : TreeNodeId
	local icons : {TreeNodeId} = {}
	for __, c in ipairs(row.inputs) do
		icons[#icons + 1] = cargoIcon(c)
	end
	if #row.inputs > 0 then
		-- "flows-cargo" gives the chevron the icons' gravity; its 10x10 size is inline, so it needs no
		-- stylesheet rule of its own (docs/findings.md "Load crash above ~200 mod stylesheet rules").
		-- Window render: GUI thread, where api.gui.StyleSheet may be created.
		icons[#icons + 1] = builtin.ImageView{
			meta = { class = "flows-cargo, flows-cargo-arrow", styleSheet = styleutil.makeStyle{ size = CARGO_ARROW_SIZE } },
			path = CARGO_ARROW_ICON,
		}
	end
	for __, c in ipairs(row.outputs) do
		icons[#icons + 1] = cargoIcon(c)
	end
	return hbox(icons, "flows-cargos")
end

--- One type row: checkbox labelled with the name (a click on the label toggles too, CheckBoxParam.label,
--- builtin.d.tl:1024-1031), the type's cargo icons and the on-map count on the right.
local function typeRow(row : IndustryFlowsTypeRow, onToggle : function(string)) : TreeNodeId
	return hbox({
		-- controlled CheckBox: value + onValueChange (builtin.d.tl:1022-1023; base: menu/mod_selector_page.tl:443-448)
		builtin.CheckBox{
			meta = { class = "flows-type-check" },
			value = row.selected and 1 or 0,
			onValueChange = function(__ : integer)
				onToggle(row.key)
			end,
			label = row.name,
		},
		cargoIcons(row),
		text(tostring(row.count), "font-scale-body, flows-count"),
	}, "flows-type-row, flows-wide")
end

--- One arrow toggle (Outputs / Inputs / Potential links): base labelled checkbox
--- (line_vehicle_mgmt/cargofilter_window.tl:755-764, layers/layer_react_util.tl:68-74).
local function toggleBox(label : string, tooltip : string, on : boolean, onChange : function(boolean)) : TreeNodeId
	return builtin.CheckBox{
		meta = { class = "flows-toggle", tooltip = tooltip },
		value = on and 1 or 0,
		onValueChange = function(value : integer)
			onChange(value == 1)
		end,
		label = label,
	}
end

local function summaryRows(s : IndustryFlowsSummary) : {TreeNodeId}
	local lines : {string} = {}
	if s.state == "empty" then
		lines[1] = _("Select an industry type to show its cargo flows.")
	elseif s.state == "loading" then
		lines[1] = _("Reading industries...")
	elseif s.state == "none" then
		lines[1] = _("None of the selected types on the map.")
	else
		lines[1] = lang_util.format(_("{n} industries · {links} links · {active} active"), {
			n = tostring(s.industries), links = tostring(s.total), active = tostring(s.active),
		})
		if s.capped then
			lines[2] = lang_util.format(_("Showing {drawn} of {total} (active first)"), {
				drawn = tostring(s.drawn), total = tostring(s.total),
			})
		end
	end
	local rows : {TreeNodeId} = {}
	for i, line in ipairs(lines) do
		rows[i] = text(line, "font-scale-annotation, flows-summary")
	end
	return rows
end

-- SQPERF section "content_render" (its first call includes the first poll, via useStateLazy).
local IndustryFlowsContent = react.RegisterRecipe("IndustryFlowsContent", perf:wrap("content_render", function(payload : ToolReactUtil.ToolWindowParamPayload<IndustryFlowsToolParam>) : TreeNodeId
	-- UI state starts from (and is written back to) the session memory, so reopening restores it.
	local uiState : ReactStateT<IndustryFlowsPanelState> = react.useStateLazy(function() : IndustryFlowsPanelState
		return model.copyPanelState(getSession())
	end)
	local dataState : ReactStateT<PanelData> = react.useStateLazy(pollOnOpen)

	-- Slow poll for actual vs potential (src pattern: engine_react_util.tl:128-149
	-- useStepStateTimer). It reads the session table, never a captured selection, so it always uses
	-- the current choice; deepEquals skips re-renders of an unchanged poll. Types and view are
	-- compared apart and an unchanged part keeps its old table: the LayerConfig and the action are
	-- cached by view identity, so a poll that only changes the type list (an unrelated industry built
	-- or removed) does not rebuild the arrows. No poll while shelved; the next tick after the panel
	-- comes back refreshes it. The timer runs on worker threads ("Main Pool N"), so it makes no
	-- api.gui call: react.onStep (Main Thread) copies the window's visibility into visibleRef every
	-- frame and the timer only reads that plain Lua flag (base: construction.tl:4308-4311 keeps its
	-- onStepTimer to refs and hands the byId visibility work to the main thread).
	local visibleRef : ReactRefT<boolean> = react.useRef(true)
	react.onStep(function()
		local visible = panelVisible()
		if visible ~= visibleRef:get() then
			visibleRef:set(visible)
			if perf.on then
				-- Debug: performance log On only; the log's thread column shows where this ran
				log.message("[IndustryFlows] panel visible=" .. tostring(visible) .. " (onStep)")
			end
		end
	end)
	react.onStepTimer(function()
		if dataState:hasExpired() then return end
		if not visibleRef:get() then
			perf:hit("poll_shelved") -- SQPERF count: ticks skipped while shelved
			return
		end
		-- SQPERF section "poll": onStepTimer (worker thread); Clock is safe there (docs/findings.md)
		local tPoll = perf:start()
		local old = dataState:old()
		local data = poll()
		local sameTypes = old ~= nil and table_util.deepEquals(data.types, old.types)
		local sameView = old ~= nil and table_util.deepEquals(data.view, old.view)
		if not (sameTypes and sameView) then
			dataState:set({
				types = sameTypes and old.types or data.types,
				view = sameView and old.view or data.view,
			})
		end
		perf:stop("poll", tPoll)
	end, REFRESH_SECONDS)

	react.onMount(function()
		logTypesOnce(dataState:old())
		logView(dataState:old().view)
	end)

	-- The LayerConfig of the last view drawn: typing in the search re-renders without changing the
	-- view, so the arrows (up to MAX_LINKS FlowData userdata) and the action function (LayerCache)
	-- are only rebuilt for a new view.
	local layerRef : ReactRefT<LayerCache> = react.useRef({ view = nil, config = nil } as LayerCache)

	local ui = uiState:old()
	local data = dataState:old()

	--- New UI state; rebuild = the selection or the toggles changed (the arrows change at once).
	local function apply(newState : IndustryFlowsPanelState, rebuild : boolean)
		session = model.copyPanelState(newState)
		uiState:set(newState)
		if rebuild then
			local old = dataState:old()
			-- SQPERF section "rebuild_view": selection / toggle clicks (GUI thread handlers)
			local tView = perf:start()
			local view = buildView(lastWorld, newState)
			perf:stop("rebuild_view", tView)
			dataState:set({ types = old and old.types or {}, view = view })
			logView(view)
		end
	end
	-- Handlers start from the session table (updated synchronously by apply), not this render's
	-- ui, so two clicks before the next render both count.
	local function update(change : function(IndustryFlowsPanelState), rebuild : boolean)
		local s = model.copyPanelState(getSession())
		change(s)
		apply(s, rebuild)
	end
	local function withQuery(query : string)
		if query == getSession().query then return end
		update(function(s : IndustryFlowsPanelState) s.query = query or "" end, false)
	end
	local function toggleType(key : string)
		update(function(s : IndustryFlowsPanelState) s.selection = model.toggleSelected(s.selection, key) end, true)
	end
	local function clearSelection()
		update(function(s : IndustryFlowsPanelState) s.selection = model.newSelection() end, true)
	end
	local function setToggle(name : string, on : boolean)
		update(function(s : IndustryFlowsPanelState) s.toggles = model.withToggle(s.toggles, name, on) end, true)
	end

	-- The action of this tool while it is on top of the tool stack: the industry window's shape
	-- (industry.tl:363-410): HUD icons, the default selector so clicks on the map still open entity
	-- windows, its hover tooltips, and our LayerConfig.
	-- allowStacking = true (like the layers, layer_cargo_flow.tl:345): a clicked entity's window is
	-- stacked on top of this tool (this window is shelved = hidden, tool_react_util.tl:61-71) instead
	-- of closing it; closing the entity window brings the panel and its arrows back.
	local view = data and data.view
	local cache = layerRef:get()
	if cache.config == nil or cache.view ~= view then
		cache.view = view
		local tLayer = perf:start() -- SQPERF section "layer_config" (render, GUI thread)
		cache.config = buildLayerConfig(view)
		perf:stop("layer_config", tLayer)
		cache.actionFn = nil
	end
	-- The HUD filter is still read every render, as before (it used to be read inside the action,
	-- which every render re-bound); a change rebuilds the action.
	local pre = hudPreFilter()
	local rendererComponent = payload.toolParam.gameCtx.rendererComponent
	if cache.actionFn == nil or cache.rc ~= (rendererComponent as any) or not samePreFilter(pre, cache.pre) then
		cache.pre = pre
		cache.rc = rendererComponent
		local layerConfig = cache.config
		cache.actionFn = function() : TreeNodeId
			local selectedEntityRef : ReactRefT<Engine.Entity> = react.useRef(-1)
			return builtin.ActionDescriptor{
				horizontalPromptList = true,
				terrainCirclePolicy = "Never",
				children = {
					makeHudIconManagerConfig(pre),
					selector_react_util.makeDefaultSelector(rendererComponent, selectedEntityRef, true),
					selector_react_util.makeDefaultSelectorTooltips(selectedEntityRef),
					builtin.LayerConfig{
						config = layerConfig,
					},
				},
			}
		end
	end
	payload.setActionFn(cache.actionFn, ACTION_KEY)

	local rows : {TreeNodeId} = {}

	-- 1. Search: base search field (statistics/statistics_react_util.tl:167-183: value + onTyping +
	-- onValueChange; also menu/mod_manager_react_util.tl:1110-1116). onTyping fires per keystroke.
	rows[#rows + 1] = builtin.TextInputField{
		meta = { class = "font-scale-body, search, flows-search" },
		placeholderText = _("Search industries or cargo..."),
		value = ui.query,
		onTyping = withQuery,
		onValueChange = withQuery,
	}

	-- 2. Matching types, multi-select. Selected types stay selected when the search hides them.
	local list = model.typeList(data and data.types or {}, ui.query, ui.selection)
	local header : {TreeNodeId} = {
		text(list.selectedCount > 0
			and lang_util.format(_("Industry types ({n} selected)"), { n = tostring(list.selectedCount) })
			or _("Industry types"), "font-scale-body, flows-heading"),
	}
	if list.selectedCount > 0 then
		header[#header + 1] = builtin.Button{
			meta = { class = "flows-clear", tooltip = _("Deselect all industry types") },
			content = text(_("Clear"), "font-scale-annotation"),
			onClick = clearSelection,
		}
	end
	rows[#rows + 1] = hbox(header, "flows-header, flows-wide")

	local typeRows : {TreeNodeId} = {}
	for __, row in ipairs(list.rows) do
		typeRows[#typeRows + 1] = typeRow(row, toggleType)
	end
	if #typeRows == 0 then
		local empty = (data == nil or #data.types == 0) and _("No industries on the map.")
			or lang_util.format(_("No industry type matches \"{q}\"."), { q = ui.query })
		rows[#rows + 1] = text(empty, "font-scale-annotation, flows-hint")
	elseif #typeRows > SCROLL_ROWS then
		-- A builtin ScrollArea directly in a BoxLayout is fine (memory "Recipe must return layout" is
		-- about custom recipes). Height from flows_window.css.lua (ScrollArea!flows-types).
		-- Its content must be a Component, not a layout ("ScrollArea does not accept a Layout as
		-- content"); base shape: entity_window/entity_window_util.tl:715-721.
		rows[#rows + 1] = builtin.ScrollArea{
			meta = { class = "flows-types" },
			content = builtin.Component{
				layout = vbox(typeRows, "flows-type-list"),
			},
			horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
			verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
		}
	else
		rows[#rows + 1] = vbox(typeRows, "flows-type-list")
	end
	if list.hiddenSelected > 0 then
		rows[#rows + 1] = text(lang_util.format(_("+{n} selected, not in this list"), { n = tostring(list.hiddenSelected) }),
			"font-scale-annotation, flows-hint")
	end

	-- 3. Arrow toggles.
	rows[#rows + 1] = vbox({
		toggleBox(_("Outputs"), _("Selected industries to the industries and towns that take their cargo"), ui.toggles.outputs,
			function(on : boolean) setToggle("outputs", on) end),
		toggleBox(_("Inputs"), _("Suppliers to the selected industries"), ui.toggles.inputs,
			function(on : boolean) setToggle("inputs", on) end),
		toggleBox(_("Potential links"), _("Also show links with no cargo moving yet (faded, still arrows)"), ui.toggles.potential,
			function(on : boolean) setToggle("potential", on) end),
	}, "flows-toggles")

	-- 4. Summary.
	for __, r in ipairs(summaryRows(model.summary(data and data.view, ui.selection))) do
		rows[#rows + 1] = r
	end

	-- 5. Legend.
	rows[#rows + 1] = text(_("Moving arrows: cargo delivered in the last year. Faded, still arrows: possible links."),
		"font-scale-annotation, flows-hint")

	-- The recipe sits in a Window's content: return a layout (memory "Recipe must return layout").
	return vbox(rows, "flows-content")
end))

local IndustryFlowsWindow = react.RegisterWrapperRecipe("IndustryFlowsWindow", builtin.Window, function(param : ToolReactUtil.IToolWindowParam<IndustryFlowsToolParam>) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210. The id must equal the tool's window id: shelve/unshelve
	-- toggle visibility by id (tool_react_util.tl:37, :61-71).
	return builtin.Window{
		id = WINDOW_ID,
		title = _("Industry Flows"),
		closable = true,
		movable = true,
		onClose = param.onClose,
		content = IndustryFlowsContent(param.payload),
	}
end)

local function getDebugString(_toolParam : IndustryFlowsToolParam) : string
	return "types: " .. table.concat(model.selectedKeys(getSession().selection), ", ")
end

-- Registered once, when this module first loads (react.RegisterTool errors on a duplicate name).
local IndustryFlowsTool = tool_react_util.registerToolWithWindow(TOOL_NAME, WINDOW_ID, IndustryFlowsWindow, getDebugString)

--- The plugin gets no gameCtx; build the parts the tool uses from the globals game.tl exposes:
--- windowContainer (tool_react_util.tl:8-10 push/pop/shelve), rendererComponent (selector), toolStack.
local function makeToolParam() : IndustryFlowsToolParam
	local gameCtx : GameContext = {
		rendererComponent = game_react_globals.getDefaultRendererComponent(),
		windowContainer = game_react_globals.getDefaultWindowContainer(),
		toolStack = game_react_globals.getDefaultToolStack(),
	}
	return { gameCtx = gameCtx }
end

local function isOpen(toolStackApi : Builtin.ToolStackAPI) : boolean
	local active = toolStackApi.getActiveTool()
	return (active as any) == (IndustryFlowsTool as any)
end

--- Ridge button: open (push, replacing other tools like Statistics does, statistics.tl:690-693 and :701) or
--- close (pop) the panel. SQPERF section "click_toggle" (onClick: GUI thread).
local togglePanel = perf:wrap("click_toggle", function()
	local toolStackApi = game_react_globals.getDefaultToolStackApi()
	local wc = game_react_globals.getDefaultWindowContainer()
	if toolStackApi == nil or wc == nil or wc:hasExpired() then
		log.warning("[IndustryFlows] no tool stack / window container; cannot open the panel")
		return
	end
	if isOpen(toolStackApi) then
		toolStackApi.pop(IndustryFlowsTool, nil)
	else
		toolStackApi.push(IndustryFlowsTool, nil, makeToolParam(), false)
	end
end)

--- A plugin recipe's root must be a layout (MainModButtonArea mounts plugins as BoxLayout children;
--- base shape: game_bar_display_transported.tl:28).
local IndustryFlowsRidgePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "IndustryFlowsRidgePlugin", perf:wrap("ridge_render", function() : TreeNodeId
	local isMapEditorRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean return api.gui.game.isMapEditor() end)
	if isMapEditorRef:get() then
		return nil
	end
	-- Inline padding instead of a stylesheet rule (docs/findings.md "Load crash above ~200 mod stylesheet
	-- rules"). No base rule sets a Button's padding per state, so it is the same in every state.
	-- Order is CSS (top, right, bottom, left). Plugin render: GUI thread (isMapEditor above).
	local buttonStyle = styleutil.makeStyle{}
	buttonStyle.padding = api.type.Vec4f.new(RIDGE_BUTTON_PADDING[1], RIDGE_BUTTON_PADDING[2], RIDGE_BUTTON_PADDING[3], RIDGE_BUTTON_PADDING[4])
	return hbox({
		builtin.Button{
			meta = {
				class = "flows-ridge-button",
				styleSheet = buttonStyle,
				tooltip = _("Industry Flows: cargo arrows for every industry of the types you pick"),
			},
			content = text(_("Flows")),
			onClick = togglePanel,
		},
	})
end))

local result = {
	IndustryFlowsRidgePlugin = IndustryFlowsRidgePlugin,
}

perf:phase("init", perfInit)

return result
