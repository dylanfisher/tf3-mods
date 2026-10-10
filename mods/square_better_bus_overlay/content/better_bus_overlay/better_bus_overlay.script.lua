-- Better Bus Overlay: while a street bus/tram stop (ACTION_STREET_TERMINAL_BUILDER) or a bus/tram station (isStopDefinition) is being placed, the map shows every
-- bus and tram line in its colour, tints town buildings by type (residential / commercial / industrial) with the ones nobody
-- reaches by your lines in full colour and the served ones faded, and puts a waiting-passenger badge on every stop.
-- GUI only: no game script, nothing in the savegame.
--
-- Two module-table wrappers, installed by doReplace (better_bus_overlay_replace.res.lua):
-- * construction_react_util.getActionParams: construction.tl:4438 calls it through the module table on every render
--   of the construction menu's action. For a street stop:
--   - res.layerConfig gets a DestinationColor town building painter (as the Passenger Flow layer,
--     layer_passenger_flow.tl:81-100, all towns, your lines only): per land use, "min" for buildings no one travels
--     to by line, "max" for the rest (api/type.d.tl DestinationColor). Base enables the plain district colours only
--     for tools whose hudIcons set showDistricts (construction_react_util.tl:590-631). A data layer the player
--     picked still wins (mergeLayerConfig, construction_react_util.tl:3985-3990).
--   - res.hudIconManagerParams gets our master recipe (HudIconMaster below) and STATION_GROUP in its preFilter.
--   Precedent: square_smart_lanes sl_tool.script.lua (showOneWay).
-- * builtin.ActionDescriptor: construction.tl:4481 builds the menu's descriptor right after getActionParams, with
--   tool = "construction-menu-<category>". When the last getActionParams was for a street stop, the bus lane
--   tool or the crosswalk tool, a non-selectable
--   LineViewer with all bus and tram lines is appended to its children (same builtin the station window uses,
--   station_group.tl:958-967). Precedent for wrapping ActionDescriptor: square_supply_gaps sg_patch.lua.
--
-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state, slow calls (> 16 ms, at most one line
-- per section per minute) and, with the "Debug: performance log" mod setting, a 30 s summary. Two
-- instruments: perf (ctx gui) for our part of the construction menu wrappers (GUI thread; the base
-- getActionParams / ActionDescriptor themselves are not timed), perfHud (ctx hud) for the stop tag / pin
-- recipes, their useStepStateTimer polls and the UseDefaultHudIcon wrapper (HUD recipes and onStepTimer
-- callbacks: worker threads "Main Pool N", where api.type.Clock is safe, docs/findings.md "Timers and
-- threads in GUI contexts"). Local counters only; nothing is saved. Pin styles: section "pin_styles" (perf,
-- the one-time build in doReplace; with the debug gate On also a "phase=pin_styles" line) and counter
-- "pin_style_miss" (perfHud, a style built during a render; expected never).
local sqperf = ug_require "square_better_bus_overlay::/sqperf/square_better_bus_overlay.lua"
local perf = sqperf.new({ mod = "square_better_bus_overlay", ctx = "gui", paramKey = "sqperf_log" })
local perfHud = sqperf.new({ mod = "square_better_bus_overlay", ctx = "hud", paramKey = "sqperf_log" })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local construction_react_util = ug_require "::/gui/construction/construction_react_util.tl"
local ConstructionMenuHudIconMaster = ug_require "::/gui/construction/constructionHudIconMaster.tl"
local color_util = ug_require "::/gui/main/color_util.tl"
local layer_react_util = ug_require "::/gui/layers/layer_react_util.tl"
local hud_react_util = ug_require "::/gui/hud/hud_react_util.tl"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local cargo_util = ug_require "::/gui/main/cargo_util.tl"
local gui_react_util = ug_require "::/gui/main/gui_react_util.tl"
local lang_util = ug_require "::/scripts/lang_util.tl"

local STOP_ACTION = "ACTION_STREET_TERMINAL_BUILDER"
-- street tools that get the line routes only, no building tints or stop tags: the bus lane tool
-- (bus_lane_tool.script.tl:11) and the crosswalk tool (crosswalk_modifier_tool.script.tl:20)
local LINES_ONLY_ACTIONS = {
	ACTION_BUS_LANE_TOOL = true,
	ACTION_CROSSWALK_MODIFIER_TOOL = true,
}
local CONSTRUCTION_ACTION = "ACTION_CONSTRUCTION_BUILDER"
-- bus/tram constructions: menu entries in this category tagged "passenger" (the street stations' passenger templates,
-- modular_terminal.con.lua:76-84, and the small stop constructions, small_stops/*.con.lua:26-31). Depots have no
-- filter tag there and the cargo station is tagged "cargo" only (:134-139), so both keep the default view.
local STATION_MENU = "road_buildings"
local STATION_FILTER = "passenger"
local TOOL_PREFIX = "construction-menu-"
local PREFIX = "[BetterBusLines] "
-- served buildings: their district colour mixed this far toward SERVED_GREY. 0.85 keeps a hint (15 %) of the type: at 0.7
-- a lone faded building in a mixed-zone town could not be told from a full-colour one without a same-type neighbour
-- to compare (player feedback, 2026-10-09), and the 10 % of 0.9 was too faint; 1.0 (plain grey) lost the type entirely
local SERVED_FADE = 0.85
local SERVED_GREY = { 0.62, 0.64, 0.66 }

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

local logged = {}
local function logOnce(key, msg)
	if logged[key] then return end
	logged[key] = true
	say(msg)
end

-- Building colours -----------------------------------------------------------------------------------------------
-- gres colours are {r, g, b[, a]} (color_util.toVec4)
local function faded(c)
	local t = SERVED_FADE
	return api.type.Vec4f.new(
		c[1] + (SERVED_GREY[1] - c[1]) * t,
		c[2] + (SERVED_GREY[2] - c[2]) * t,
		c[3] + (SERVED_GREY[3] - c[3]) * t,
		c[4] or 1.0)
end

-- gres data read once (first stop render), as base reads it once at module load (layer_civilization.tl:16-17).
-- Only these plain data tables are kept; the LayerConfig userdata below is still built fresh on every render.
local layerColors, districtColors = nil, nil
local function addServedColours(cfg)
	if districtColors == nil then
		layerColors = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/layers/layer_colors.gres")).data
		districtColors = api.gui.genericRep.get(api.gui.genericRep.find("::/game_mechanics/towns/district_colors.gres")).data
	end
	-- min = no one travels here by line (full district colour), max = served (faded)
	local function range(c)
		return api.type.LayerConfig.ColorPassFn.BaseRangeColor.new({ color_util.toVec4(c.max), faded(c.max) }, true)
	end
	local painter = api.type.LayerConfig.ColorPassFn.DestinationColor.new()
	painter.residential = range(districtColors.Residential)
	painter.commercial = range(districtColors.Commercial)
	painter.industrial = range(districtColors.Industrial)
	painter.numBuildingLevels = 2
	painter.town = -1
	painter.showPlayerTransport = true
	painter.showPrivateTransport = false

	-- underground mode already has base's white screen (construction_react_util.tl:516-518, 550-552): keep it
	local whiteScreen = cfg.undergroundMode == true
	local colorPassFn
	if whiteScreen then
		colorPassFn = cfg.colorPassFn
	else
		colorPassFn = api.type.LayerConfig.ColorPassFn.new()
		colorPassFn.fallbackColor = layer_react_util.createDefaultFallbackColor(
			layerColors.Construction.Fallback.Surface, layerColors.Construction.Fallback.Details)
	end
	colorPassFn.townBuildingPainter = painter
	cfg.colorPassFn = colorPassFn

	local buildingRenderableConfig = api.type.LayerConfig.BuildingRenderableConfig.new()
	buildingRenderableConfig.isVisible = true
	buildingRenderableConfig.includeTownBuildingMainModel = true
	cfg.buildingRenderableConfig = buildingRenderableConfig
	cfg.colorPassFnForBuildingRenderableOnly = not whiteScreen
end

-- Stop badges ----------------------------------------------------------------------------------------------------
-- The game's own free-play station tag (createStationIcon, hud_icon_toolbox.tl:112-142): the passenger icon and the
-- waiting count on the blue "WaitingPassenger" tag, the number in yellow when some waiting passengers are unhappy
-- and red when more than half are (gui_react_util.css.lua:88-104). Built inside HudIconMaster, as base does,
-- so no recipe of our own (a recipe must return a layout: a Component root crashed the game, 2026-10-09).
-- Earlier tries: the Passenger Satisfaction layer's tag with the emote (too big), the game's HUD scale (no effect,
-- docs/findings.md) and an own number-only pill (too minimal).
local function stationBadge(happiness)
	local fontColor = "Normal"
	if happiness.unhappy > 0 then
		fontColor = happiness.unhappy > happiness.totalWaiting / 2 and "Poor" or "Inferior"
	end
	return gui_react_util.makeContentLabelIndictator{
		iconPath = cargo_util.getPassengerCargoIcon(),
		label = lang_util.formatInt(happiness.totalWaiting),
		labelFontColor = fontColor,
		labelMode = "HudIconMain",
		shippingState = "WaitingPassenger",
	}
end

local function hasValue(list, v)
	for _, x in ipairs(list or {}) do
		if x == v then return true end
	end
	return false
end

-- Stops no line passes through yet: a dark tag with the bus icon and "No line" in place of the stop icon, built like
-- the waiting tag but without a shipping state, so it keeps the base dark HUD tag fill (hud-icon-background,
-- gui_react_util.css.lua:59-69; text colour :115-121). Icon: the HUD filter's road vehicle icon
-- (layer_hud_filter.tl:103). Lines per station group: lineSystem.getLineStops (api/engine/system.d.tl:27-29), as the
-- station window does (station_group.tl:913-918).
local NO_LINE_ICON = "::/gui/layers/icons/filter/vehicle_bus.tga"
local NO_LINE_TEXT = _("No line")

local function noLineTag()
	return builtin.BoxLayout{
		meta = { class = "station-icon-layout" },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			gui_react_util.makeContentLabelIndictator{
				iconPath = NO_LINE_ICON,
				label = NO_LINE_TEXT,
				labelFontColor = "Default",
				labelMode = "HudIconMain",
			},
		},
	}
end

local function hasNoLine(stationGroup)
	return #api.engine.system.lineSystem.getLineStops(stationGroup) == 0
end

-- Stations: the base icon (or the default one when base would skip stations) plus the badge. Anything else goes to
-- the base master unchanged. A recipe child that renders nothing is fine (layer_passenger_flow.tl:60 wraps the base
-- master the same way).
-- SQPERF: the poll's returns go through pollDone (section "hud_station_poll"; no allocation per call)
local function pollDone(t, v)
	perfHud:stop("hud_station_poll", t)
	return v
end

-- SQPERF sections "hud_station_render" and "hud_station_poll" (perfHud)
local HudIconMaster = react.RegisterRecipe("SquareBetterBusLinesHudIconMaster", perfHud:wrap("hud_station_render", function(param, userParam)
	-- runs per icon every 0.5 s (engine_react_util.tl:141-154, called with the previous state). Whether an entity is a
	-- station group never changes, so once known: non-stations (towns, industries, ...) return the old state at no
	-- engine cost (the base master below keeps its own existence check, constructionHudIconMaster.tl:13-15), and
	-- stations skip re-reading the whole STATION_GROUP component.
	local state = engine_react_util.useStepStateTimer(function(old)
		local t = perfHud:start()
		if old ~= nil and not old.station then return pollDone(t, old) end
		if param.entity < 0 or not api.engine.entityExists(param.entity) then return pollDone(t, nil) end
		if old == nil and api.engine.getComponent(param.entity, api.type.ComponentType.STATION_GROUP) == nil then
			return pollDone(t, { station = false })
		end
		local passenger = cargo_util.getPassengerCargoTypeId()
		local data
		-- SelectionDetails.Type.Station: a plain enum field read (api/gui.d.tl:112-123), no call; base reads it in
		-- the same HUD context (HudStationWithLineStops, manager_hud_util.tl:382)
		if param.index ~= -1 and param.details and param.details.data
				and param.details.data.kind == api.gui.SelectionDetails.Type.Station then
			data = api.engine.util.cargo.getCargoQualityDataAtTerminal(param.entity, param.details.data.stationTerminal, passenger)
		else
			data = api.engine.util.cargo.getCargoQualityDataAtStationGroup(param.entity, passenger)
		end
		return pollDone(t, { station = true, noLine = hasNoLine(param.entity),
			happiness = { totalWaiting = data.countTotal, unhappy = data.countBad } })
	end)
	local s = state:old()
	if s == nil then return nil end
	if not s.station then
		return builtin.BoxLayout{ children = { ConstructionMenuHudIconMaster(param, userParam) } }
	end
	react.setMouseTransparent(true)
	-- With waiting passengers the tag replaces the stop icon, in the base station layout, as in free play
	-- (createStationIcon, hud_icon_toolbox.tl:112-142; its class also hides the number at far LOD,
	-- hud_icon_master.css.lua:149-151). Next to the stop icon, "!hud-icon-main > BoxLayout" (gravity {-1, 0},
	-- gui_react_util.css.lua:54-57) stretched the tag to the icon's height: tall, narrow and unlike vanilla (2026-10-09).
	-- every icon of the stop: close to the camera the HUD draws one icon per terminal (index >= 0) instead of the
	-- group icon (index -1), and none of them has a line either (2026-10-09: near stops kept the plain pin)
	if s.noLine then
		return noLineTag()
	end
	if s.happiness.totalWaiting > 0 then
		return builtin.BoxLayout{
			meta = { class = "station-icon-layout" },
			orientation = builtin.type.Orientation.Horizontal,
			children = { stationBadge(s.happiness) },
		}
	end
	return builtin.BoxLayout{
		children = {
			hasValue(userParam.defaultIcons, api.type.ComponentType.STATION_GROUP)
				and ConstructionMenuHudIconMaster(param, userParam) or builtin.UseDefaultHudIcon(param),
		},
	}
end))

-- Lines window (line manager) ------------------------------------------------------------------------------------
-- Stops no line passes through show the "No line" tag in place of their pin (ShadedStopIcon below), in the overview
-- and while a line is edited. Only the pin is swapped, so the base recipe keeps its terminal numbers above it (shown
-- for the per-terminal icons near the camera, manager_hud_util.tl:546-557), its edit buttons and its clicks. Replacing
-- the whole icon (until 2026-10-09) hid the terminal numbers when zoomed in and left the tags out while editing.

-- Busy stops: in the Lines window the stop's blue pin is shaded light (few waiting) to dark (many waiting).
-- The pin is the engine's builtin.UseDefaultHudIcon (builtin.lua:233), which takes no colour and which no stylesheet
-- reaches, so doReplace wraps that builtin: when HudStationWithLineStops (manager_hud_util.tl:375-716, the recipe for
-- every stop in both overview and line editing) asks for it, ShadedStopIcon draws a copy instead: the game's pin mask
-- (gui.zip gui/hud/icons/hud_background@2x.tga) tinted by level, with its bus glyph (vehicle_bus_front_32@2x.tga) on
-- top; looks are in better_bus_overlay.css.lua. The line dots (StopLinesDisplay) and terminal numbers around it stay the
-- base ones. The earlier gold/red terminal numbers clashed with the yellow line dots (player feedback, 2026-10-09).
-- Colour by passengers waiting at the stop, a gradient through PIN_STOPS: light blue (quiet) -> yellow -> red
-- (busiest). Dark navy pins read as "busy" too weakly (player feedback, 2026-10-09). The colour is set per pin as an
-- inline styleSheet (styleutil.makeStyle, as manager_hud_util.tl:658-660 colours its terminal tags); the count is
-- rounded to PIN_STEP so a pin only re-renders when its colour visibly changes. The styles are made once (pinStyles
-- below), not per render.
local styleutil = ug_require "::/gui/main/styleutil.tl"
local PIN_STOPS = {
	{ 0, { 0.62, 0.77, 0.92 } },  -- light blue: nobody waiting
	{ 40, { 0.96, 0.78, 0.20 } }, -- yellow: kind of busy
	{ 80, { 0.89, 0.25, 0.22 } }, -- red: busiest (and anything above)
}
local PIN_STEP = 4
local GLYPH_DARK = { 0.11, 0.17, 0.27, 1.0 }
local GLYPH_LIGHT = { 1.0, 1.0, 1.0, 1.0 }
local STATION_RECIPE = "HudStationWithLineStops"

-- waiting count rounded down to PIN_STEP, capped at the last stop
local function pinStep(stationGroup)
	local data = api.engine.util.cargo.getCargoQualityDataAtStationGroup(stationGroup, cargo_util.getPassengerCargoTypeId())
	local cap = PIN_STOPS[#PIN_STOPS][1]
	local n = math.min(data.countTotal, cap)
	return n - n % PIN_STEP
end

local function pinColour(waiting)
	local prev = PIN_STOPS[1]
	for i = 2, #PIN_STOPS do
		local nextStop = PIN_STOPS[i]
		if waiting <= nextStop[1] then
			local t = (waiting - prev[1]) / (nextStop[1] - prev[1])
			local c = {}
			for k = 1, 3 do c[k] = prev[2][k] + (nextStop[2][k] - prev[2][k]) * t end
			c[4] = 1.0
			return c
		end
		prev = nextStop
	end
	local last = PIN_STOPS[#PIN_STOPS][2]
	return { last[1], last[2], last[3], 1.0 }
end

-- the white glyph vanishes on the light blue and yellow pins: dark glyph when the pin is light
local function glyphColour(c)
	local luminance = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
	return luminance > 0.6 and GLYPH_DARK or GLYPH_LIGHT
end

-- Pin styles, made once (2026-10-10). ShadedStopIcon renders inside the HUD icon manager's master recipe
-- (LineVehicleManagerHudIconMaster -> HudStationWithLineStops, manager_hud_util.tl:894, 1196), so on the HUD worker
-- threads ("Main Pool N", docs/findings.md "Timers and threads in GUI contexts"), and styleutil.makeStyle calls
-- api.gui.StyleSheet.new (gui/main/styleutil.tl). So every style is made up front by warmPinStyles, which doReplace
-- runs on the Main Thread at GUI start (bootstrap_game.tl; log: "installed pin=ok" from Main Thread), and the
-- render only looks them up. The set is closed: pinStep gives 0, PIN_STEP, ... up to the last PIN_STOPS count (21
-- pin colours), and glyphColour one of two glyph colours. A step outside it is built lazily on the render's thread
-- and counted (perfHud "pin_style_miss"): base makes StyleSheets in that same render anyway (StopLinesDisplay,
-- manager_hud_util.tl:119-135, one per line dot of every stop, drawn next to this pin), and StyleSheet.new is not
-- documented "Only available in GUI thread" (api/gui.d.tl:20), unlike getApplicationTime.
local pinStyleCache = {}   -- step -> { bg = StyleSheet, bus = StyleSheet }
local glyphStyleCache = {} -- GLYPH_DARK / GLYPH_LIGHT -> StyleSheet

local function buildPinStyles(step)
	local colour = pinColour(step)
	local glyph = glyphColour(colour)
	local bus = glyphStyleCache[glyph]
	if bus == nil then
		bus = styleutil.makeStyle{ color = glyph }
		glyphStyleCache[glyph] = bus
	end
	local entry = { bg = styleutil.makeStyle{ color = colour }, bus = bus }
	pinStyleCache[step] = entry
	return entry
end

local function pinStyles(step)
	local entry = pinStyleCache[step]
	if entry ~= nil then return entry end
	perfHud:hit("pin_style_miss")
	return buildPinStyles(step)
end

-- every step pinStep can return; returns how many pin styles exist
local function warmPinStyles()
	local n = 0
	for step = 0, PIN_STOPS[#PIN_STOPS][1], PIN_STEP do
		if pinStyleCache[step] == nil then buildPinStyles(step) end
		n = n + 1
	end
	return n
end

-- Vanilla size, measured from in-game screenshots (2026-10-09): the default pin is the same mask drawn at about
-- 72 % of its natural 40x52, with a ~20 px glyph. A nine-patch background can't shrink its corners and tail (the
-- first copy came out ~40 % too big), so the pin is an ImageView (scales the whole mask) with the glyph stacked on
-- top: two full-size FloatingLayoutChild layers in a sized frame, placed only by padding (memory
-- tf3-gui-pixel-placement; minimap_hud.script.tl layerAt). Sizes and padding are in better_bus_overlay.css.lua.
local PIN_PATH = "::/gui/hud/icons/hud_background.tga"
local BUS_PATH = "::/gui/hud/icons/vehicle_bus_front_32.tga"

local function pinLayer(class, item)
	return builtin.FloatingLayoutChild{
		h = -1,
		v = -1,
		item = builtin.Component{
			meta = { class = class },
			mouseTransparent = true,
			layout = builtin.BoxLayout{ children = { item } },
		},
	}
end

-- SQPERF sections "pin_render" and "pin_poll" (perfHud)
local ShadedStopIcon = react.RegisterRecipe("SquareBetterBusLinesShadedStopIcon", perfHud:wrap("pin_render", function(param)
	local state = engine_react_util.useStepStateTimer(function()
		local t = perfHud:start()
		local ok, step = pcall(pinStep, param.entity)
		local okLine, noLine = pcall(hasNoLine, param.entity)
		perfHud:stop("pin_poll", t)
		return { step = ok and step or 0, noLine = okLine and noLine }
	end)
	react.setMouseTransparent(true)
	if state:old().noLine then
		return noLineTag()
	end
	local styles = pinStyles(state:old().step)
	-- a recipe must return a layout at its root (memory react-recipe-must-return-layout); ImageView takes no
	-- mouseTransparent (memory tf3-imageview-rotation-icons)
	return builtin.BoxLayout{
		children = {
			builtin.Component{
				meta = { class = "sqslv-pin" },
				mouseTransparent = true,
				layout = builtin.FloatingLayout{
					children = {
						pinLayer("sqslv-pin-bg-layer", builtin.ImageView{
							meta = { class = "sqslv-pin-bg", styleSheet = styles.bg },
							path = PIN_PATH,
							scaling = builtin.type.ImageViewScaling.Stretch,
						}),
						pinLayer("sqslv-pin-bus-layer", builtin.ImageView{
							meta = { class = "sqslv-pin-bus", styleSheet = styles.bus },
							path = BUS_PATH,
							scaling = builtin.type.ImageViewScaling.AutoFit,
						}),
					},
				},
			},
		},
	}
end))

local origUseDefaultHudIcon

-- builtins are called as (params) or (ref, params); only the plain form from the stop recipe is replaced
local function useDefaultHudIcon(p, ...)
	if select("#", ...) == 0 and p ~= nil then
		local okName, name = pcall(react.getCurrentRecipeName)
		if okName and name == STATION_RECIPE then
			local okEntity, entity = pcall(function() return p.entity end)
			if okEntity and type(entity) == "number" and entity >= 0 then
				return ShadedStopIcon(p)
			end
		end
	end
	return origUseDefaultHudIcon(p, ...)
end

local function addStopBadges(res, accessNotificationCacheFn)
	local base = res.hudIconManagerParams
	-- copies: preFilter is the definition's own componentTypes table (construction_react_util.tl:1256-1280)
	local preFilter = {}
	for i, t in ipairs(base and base.preFilter or {}) do preFilter[i] = t end
	if not hasValue(preFilter, api.type.ComponentType.STATION_GROUP) then
		preFilter[#preFilter + 1] = api.type.ComponentType.STATION_GROUP
	end
	res.hudIconManagerParams = {
		userParam = base and base.userParam or { defaultIcons = {}, accessNotificationCacheFn = accessNotificationCacheFn },
		masterRecipe = HudIconMaster,
		preFilter = preFilter,
		visibilityThresholds = base and base.visibilityThresholds or hud_react_util.makeDefaultVisibilityThresholds(),
	}
	logOnce("badges", "badges hud=" .. (base and "base" or "new") .. " preFilter=" .. #preFilter)
end

-- Line routes ----------------------------------------------------------------------------------------------------
-- The menu's action re-renders on hover and param changes, so the list is rebuilt at most once a second
-- (os.time: GUI thread, but no need for finer timing).
-- Only bus and tram lines: train, air and water lines cluttered the street view (player feedback, 2026-10-09).
-- Carrier check as the Lines window filters by carrier (isLineCompatibleWithAnyCarrier, api/engine/util.d.tl:228;
-- manager_window.tl:156).
local LINE_CARRIERS = nil
local function isStreetLine(line)
	LINE_CARRIERS = LINE_CARRIERS or { api.type.enum.Carrier.ROAD, api.type.enum.Carrier.TRAM }
	return api.engine.util.line.isLineCompatibleWithAnyCarrier(line, LINE_CARRIERS, false)
end

local linesCache, linesStamp = nil, nil
local function lineVisualizations()
	local now = os.time()
	if linesCache and linesStamp == now then return linesCache end
	local list = {}
	for _, line in ipairs(api.engine.system.lineSystem.getLines()) do
		if isStreetLine(line) then
			local vis = builtin.type.LineVisualization.new()
			vis.entity = line
			vis.transparency = 1.0
			list[#list + 1] = vis
		end
	end
	linesCache, linesStamp = list, now
	return list
end

local snapFactors = nil
local function lineViewer()
	local lines = lineVisualizations()
	if #lines == 0 then return nil end
	snapFactors = snapFactors or hud_react_util.makeDefaultLineViewerSnapFactors()
	return builtin.LineViewer{
		selectable = false,
		-- marks the line stops (base turns it on while a line is being created, line_util.tl:1200)
		showTerminals = true,
		maxSnapFactorView = snapFactors.view,
		maxSnapFactorWorld = snapFactors.world,
		showLines = lines,
	}
end

-- Wrappers -------------------------------------------------------------------------------------------------------
local origGetActionParams, origActionDescriptor
-- set by every getActionParams call, consumed by the next construction-menu ActionDescriptor (construction.tl
-- always calls the two in that order in one render)
local linesPending = false

-- Street stops, and bus/tram station constructions (template definitions keep their own menuCategory,
-- construction_react_util.tl:1074-1097). A template's menuCategory comes from the engine's template object
-- (constructionTemplates_native:at, :1040-1042), so its lists may be native vectors, not Lua tables: ipairs found
-- nothing on them and the bus station never matched (2026-10-09). listItems reads both kinds.
local function listItems(v)
	if type(v) == "table" then return v end
	if v == nil then return {} end
	local out = {}
	local okSize, n = pcall(function() return v:size() end)
	if okSize and type(n) == "number" then
		for i = 1, n do out[i] = v:at(i) end
		return out
	end
	n = #v
	for i = 1, n do out[i] = v[i] end
	return out
end

local function menuMatches(menu)
	local seen = {}
	for _, c in ipairs(listItems(menu.categories)) do
		local filters = listItems(c.filterCategories)
		seen[#seen + 1] = tostring(c.category) .. "[" .. table.concat(filters, ",") .. "]"
		if c.category == STATION_MENU then
			for _, f in ipairs(filters) do
				if f == STATION_FILTER then return true, table.concat(seen, " ") end
			end
		end
	end
	return false, table.concat(seen, " ")
end

-- The definition that reaches getActionParams has no menuCategory for template entries (log "menu=nil" for the bus
-- station, 2026-10-09), so its template's menuCategory is read from the construction itself:
-- api.res.constructionRep.findAndGet(resName) (api/res.d.tl:33, as hud_icon_toolbox.tl:247), template index
-- definition.constructionTemplate (zero based, construction_react_util.tl:1095), constructionTemplates_native
-- (api/type.d.tl:1713, read as construction_react_util.tl:1040-1042). Cached per entry: resources don't change in game.
local templateMenuCache = {}

local function templateMenu(definition)
	local key = tostring(definition.resName) .. "#" .. tostring(definition.constructionTemplate)
	local cached = templateMenuCache[key]
	if cached == nil then
		cached = false
		local desc = api.res.constructionRep.findAndGet(definition.resName)
		local idx = definition.constructionTemplate
		if desc ~= nil and type(idx) == "number" then
			local templates = desc.constructionTemplates_native
			if templates ~= nil and idx + 1 <= templates:size() then
				cached = templates:at(idx + 1).menuCategory or false
			end
		end
		templateMenuCache[key] = cached
	end
	return cached or nil
end

local function matchesStationMenu(definition)
	local menu = definition.menuCategory
	local source = "def"
	if menu == nil then
		menu = templateMenu(definition)
		source = "rep"
	end
	if menu == nil then return false, "menu=nil" end
	local match, seen = menuMatches(menu)
	return match, source .. " " .. seen
end

local function isStopDefinition(definition)
	if definition.action == STOP_ACTION then return true end
	if definition.action ~= CONSTRUCTION_ACTION then return false end
	local ok, match, seen = pcall(matchesStationMenu, definition)
	if not ok then
		warnOnce("menu", match)
		return false
	end
	-- once per construction entry: what the menu check saw (diagnostics for station matching)
	logOnce("menu:" .. tostring(definition.resName) .. "#" .. tostring(definition.constructionTemplate),
		"menu " .. (match and "match" or "skip") .. " res=" .. tostring(definition.resName)
		.. " template=" .. tostring(definition.constructionTemplate) .. " " .. tostring(seen))
	return match
end

-- getActionParams(definition, params, repository, isGamepadMode, refParams, entity, accessNotificationCacheFn, ...)
-- (construction_react_util.tl:3604-3606)
local function getActionParams(definition, params, repository, isGamepadMode, refParams, entity, accessNotificationCacheFn, ...)
	local res = origGetActionParams(definition, params, repository, isGamepadMode, refParams, entity, accessNotificationCacheFn, ...)
	local t = perf:start() -- SQPERF section "action_params": our part only (GUI thread)
	linesPending = false
	if res ~= nil and definition ~= nil and LINES_ONLY_ACTIONS[definition.action] then
		logOnce("def:" .. tostring(definition.resName), "match " .. tostring(definition.action) .. " res=" .. tostring(definition.resName))
		linesPending = true
	elseif res ~= nil and definition ~= nil and isStopDefinition(definition) then
		logOnce("def:" .. tostring(definition.resName), "match " .. tostring(definition.action) .. " res=" .. tostring(definition.resName))
		linesPending = true
		local ok, e = pcall(function()
			if res.layerConfig == nil then res.layerConfig = api.type.LayerConfig.new() end
			addServedColours(res.layerConfig)
		end)
		if not ok then warnOnce("colours", e) end
		ok, e = pcall(addStopBadges, res, accessNotificationCacheFn)
		if not ok then warnOnce("badges", e) end
	end
	perf:stop("action_params", t)
	return res
end

-- builtins are called as (params) or (ref, params); only the plain form is touched
local function actionDescriptor(p, ...)
	if linesPending and select("#", ...) == 0 and type(p) == "table" then
		linesPending = false
		local t = perf:start() -- SQPERF section "line_viewer" (GUI thread)
		local tool = p.tool
		if type(tool) == "string" and tool:sub(1, #TOOL_PREFIX) == TOOL_PREFIX then
			local ok, viewer = pcall(lineViewer)
			if not ok then
				warnOnce("lines", viewer)
			elseif viewer ~= nil then
				local children = {}
				for i, child in ipairs(p.children or {}) do children[i] = child end
				children[#children + 1] = viewer
				p.children = children
			end
		end
		perf:stop("line_viewer", t)
	end
	return origActionDescriptor(p, ...)
end

local function doReplace(_replacementApi)
	if origGetActionParams or origActionDescriptor then return end -- already installed
	-- read the current functions now, not at load, so wrappers of other mods stay in the chain
	local gap, ad = construction_react_util.getActionParams, builtin.ActionDescriptor
	if type(gap) ~= "function" or ad == nil then
		warnOnce("install", "getActionParams " .. type(gap) .. ", ActionDescriptor " .. type(ad))
		return
	end
	origGetActionParams, origActionDescriptor = gap, ad
	construction_react_util.getActionParams = getActionParams
	builtin.ActionDescriptor = actionDescriptor
	if builtin.UseDefaultHudIcon ~= nil then
		origUseDefaultHudIcon = builtin.UseDefaultHudIcon
		builtin.UseDefaultHudIcon = perfHud:wrap("default_icon", useDefaultHudIcon) -- SQPERF section (HUD renders)
	end
	say("installed pin=" .. (origUseDefaultHudIcon ~= nil and "ok" or "missing"))
	-- the pin styles, on this (Main) thread; SQPERF section "pin_styles" (perf). The stop opens perf's first window,
	-- which reads the debug gate, so the check line below is only written with the debug gate On.
	local t = perf:start()
	local okStyles, nStyles = pcall(warmPinStyles)
	local ms = perf:stop("pin_styles", t)
	if not okStyles then
		warnOnce("pin_styles", nStyles)
	elseif perf.on then
		sqperf.emit(perf.prefix .. string.format(" phase=pin_styles ms=%.3f styles=%d glyphs=%d", ms, nStyles,
			(glyphStyleCache[GLYPH_DARK] and 1 or 0) + (glyphStyleCache[GLYPH_LIGHT] and 1 or 0)))
	end
end

perf:phase("init", perfInit)

-- .script.lua resources expose their exports through data(), not a return value (memory: script-lua-exports-via-data)
function data()
	return {
		doReplace = doReplace,
	}
end
