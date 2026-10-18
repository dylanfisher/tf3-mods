-- Minimap window (plans/square_better_minimap/PLAN.md, phases 2-3): a ridge button toggles a
-- pinnable window with builtin.MapPreviewComp fed by api.engine.terrain.makeMapFromGame, industry
-- icons and a camera box on top, and click-to-jump. GUI-only: reads the game, never writes game
-- state (no commands, no game script); session settings live in module-level Lua tables, nothing
-- goes into the save. Position, pin, size and the industry toggle are also remembered across game
-- loads in the game settings (AppConfig.mainMenuState; see "Remembered settings" below).
--
-- WIRING (same as square_problem_radar's radar_hud.script.tl):
--   * minimap_hud.res.lua mounts MinimapHudPlugin at "::MainModButtonAreaExtension"
--     (.cache/game/base/content/gui/main/main_mod_button_area.tl:7-13); one row high.
--   * the window is a RegisterWrapperRecipe around builtin.Window, opened with addSingletonWindow
--     (builtin.d.tl:1186-1232; base: .cache/game/base/content/gui/menu/main_page.tl:44-63).
--
-- THREADS: react.onStepTimer callbacks are deferred (react.lua:525-534 enqueueDeferredStep, "call
-- this function with restricted api, in parallel to rendering preparations", react.d.tl:400), where
-- api.gui.camera.* throws "API is currently restricted" (phase 1 log). react.onStep runs on the GUI
-- main thread (engine_react_util.useStepState -> react.onStep, used with
-- api.gui.camera.getHeightAboveTerrain() at line_vehicle_mgmt/line_util.tl:1119-1121). So every
-- timer here only raises a "due" flag, and the work (camera reads, revision checks, rebuilds,
-- window position reads) happens in onStep.
--
-- PREVIEW (the map editor's pattern, .cache/game/base/content/gui/map_editor/map_editor.tl):
--   * makeMapFromGame(withHeightmap, withTowns, withIndustries, withAssets) (:326; api:
--     .cache/game/api/tealdef/api/engine.d.tl:1762), rebuilt only when the terrain entity
--     revisions, the towns' revisions (useAutoUpdater :298-345) or the set of industries change.
--     Checked every REV_CHECK_SECONDS while the window is open; no periodic rebuild.
--   * MapPreviewComp params as in the map editor's Preview (:2670-2685), mode = a "keep everything,
--     generate nothing" HeighmapGenerationMode (phase 1: renders the save as-is), re-mounted (new
--     localKey) on every rebuild with the map as both inputMap and initialMap.
--
-- CAMERA BOX: getCameraData() {x, y, distance, angle, pitch} (gui.d.tl:430-433). The footprint is
-- the four screen corners traced onto the terrain (screen2World + traceToTerrain, gui.d.tl:483-506),
-- falling back to a square of +-distance around the centre. Positioned with FloatingLayoutChild
-- gravities over the picture (finances_cargo_lifetime.tl:65-124, 297-311), sized per render with
-- meta.styleSheet (styleutil.makeStyle; cargo_react_util.tl:752).
--
-- PIN: builtin.Window{ pinnable, pinned, onPinned } (builtin.d.tl:1186-1209) only draws the pin
-- toggle and reports it; what pinning means is up to the owner. Base: entity windows
-- (entity_window/view_manager.tl:245-247, 312-323, 392-395, 527-540) close on ESC (IA_MENU_BACK)
-- and are replaced/closed by tool changes unless pinned; moving one pins it (onMovedChange, also
-- music_player.tl:275-281). ESC also fires IA_CLOSE_TOPMOST_WINDOW, which the engine (C++) handles
-- for closable windows (callout_react_util.tl:19-20, construction.tl:1490-1492); that, not our
-- IA_MENU_BACK handler, closed the pinned minimap in the phase 2 test. Here: unpinned = ESC closes
-- (hides) it; pinned = closable is false (no X, nothing for close-topmost to close) and our
-- IA_MENU_BACK handler is Disabled, so ESC reaches the pause menu; a close request that still
-- arrives while pinned is ignored, and the ridge plugin re-shows a pinned window something else hid.
-- Closing = hiding by id (api.gui.byId.setVisible, as view_manager.tl shelves entity windows), so
-- the window keeps its position, size and state; it is only re-created after an unmount.
--
-- INDUSTRY MARKERS (phase 3): the preview draws every industry with one generic CSS marker
-- (MapPreviewComp::IndustryMarker, base builtin.css.lua:1917-1921), so the GameMap is built with
-- withIndustries = false and our own layer draws one ImageView per industry. Icon = the cargo icon
-- of the industry's first product (else first input, else the generic industry icon), which is how
-- the base game marks industries: HUD CargoInputOutputIndicator from
-- api.engine.util.stock.getInputsOutputsFromRules(industry.stockList) (entity_window_hud.tl:107-160,
-- cargo_react_util.tl:653-680), industry window ProductionIconWithBubble with
-- cargo_util.getCargoIconById = CargoType.icon (industry_react_util.tl:323-325, cargo_util.tl:436-439).
-- Position = BOUNDING_VOLUME bbox centre (industry.tl:195-202); name = api.engine.util.getEntityName
-- (game_tooltips.tl:20). Read once per map build (main thread), laid out per picture size with
-- geom.markerLayout; each marker uses the camera box's sized-container trick.
--
-- CLICK: react.onMouseEvent + useSelfRef():containsPosition / getPosition(gravityX, gravityY)
-- (react.d.tl:153-200, 342). Phase 1: getPosition returns 0..1 screen fractions, events pixels;
-- minimap_geom.eventToFrac handles both.
--
-- INDUSTRY FILTER (phase 7, PLAN.md "Phase 7"; rules in minimap_filter.tl): a set of industry type
-- keys (construction fileName, read in readIndustry), empty = all, remembered in the prefs. Shift
-- (IA_PRECISION_MODE) + pointer over an icon fades the other types (MinimapMarkers hover state, set
-- by the canvas through markersHoverFn; the layout cache and the other layers are untouched).
-- Shift+click filters (filter.shiftClick) instead of jumping. The "Filter" checkbox (shown while Ind
-- is on) opens and closes the filter window (MinimapFilterWindow) and shows whether it is open. Both go through setFilter, which re-renders its listeners.

-- SQPERF (plans/sqperf/README.md): load time of this GUI Lua state, slow calls, and with the
-- "Debug: performance log" setting On a 30 s summary. Two instruments, local counters only,
-- nothing saved:
--   * perf (ctx gui): recipe renders and click handlers.
--   * perfStep (ctx step): the work done in react.onStep callbacks (map build, industry read,
--     revision check, camera read, position/fit polls, guard tick), kept apart so the log tells
--     per-frame work from renders and its phase=first line covers the first map build.
--   Both use SQPERF's default timer, api.type.Clock (one per Lua state), which is safe in render,
--   onStep and onStepTimer (docs/findings.md "Timers and threads in GUI contexts"). The
--   "[Minimap] ... built in" log lines keep their own os.clock helper (clock below).
local sqperf = ug_require "square_better_minimap::/sqperf/square_better_minimap.lua" as SquareBetterMinimapSqPerf
local perf = sqperf.new({ mod = "square_better_minimap", ctx = "gui", paramKey = "sqperf_log", first = { "hud_render" } })
local perfInit = perf:start()

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local table_util = ug_require "::/scripts/table_util.tl" as TableUtil
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil

-- Base colour table (default_colors.gres.lua), read on first use in a render like statistics.tl:202.
-- Fixed colours of single widgets go inline (meta.styleSheet) instead of into minimap_hud.css.lua:
-- the game crashes on load above ~200 mod stylesheet rules (docs/findings.md), so the sheet stays small.
local colorTable : {string : {number}} = nil
local function colors() : {string : {number}}
	if colorTable == nil then
		colorTable = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data as {string : {number}}
	end
	return colorTable
end

--- 24 px white icon on a button (HUD "Icon" style, size toggle): map@2x.tga and zoom@2x.tga are 48x48, 1:1.
local function icon24Style() : StyleSheet
	return styleutil.makeStyle{ size = { 24, 24 }, color = colors().NeutralLightest }
end

--- Top-bar "Icon" button (mod.json hudButtonStyle): a base ToggleButton like the data layers button
--- (layers_button_ridge.tl:529-539) and Timetables' ridge button, so the tile, its pressed (AccentMedium)
--- and hover states and the white icon all come from the base rules (builtin.css.lua:138-240). Only the
--- size is ours, inline: 8 px padding (the base default) around the 24 px icon, a 40 px tile like the
--- layers and Timetables buttons in game. No colour here: an inline colour would override the states.
local function ridgeToggleStyle() : StyleSheet
	local st = api.gui.StyleSheet.new()
	st.padding = api.type.Vec4f.new(8, 8, 8, 8)
	return st
end
local function ridgeIconStyle() : StyleSheet
	return styleutil.makeStyle{ size = { 24, 24 } }
end

--- Shift hover (phase 7): the other types' faded marker. Overrides the minimap-industry-icon rule's tile
--- (BaseDark at 0.75) with a fainter one and fades the cargo icon through the tint's alpha.
local function mutedIconStyle(size : integer) : StyleSheet
	local tile = colors().BaseDark
	return styleutil.makeStyle{
		size = { size, size },
		color = { 1, 1, 1, 0.25 },
		backgroundColor = { tile[1], tile[2], tile[3], 0.2 },
	}
end

local geom = ug_require "square_better_minimap::/minimap/minimap_geom.tl" as SquareMinimapGeom
local net = ug_require "square_better_minimap::/minimap/minimap_net.tl" as SquareMinimapNet
local netscan = ug_require "square_better_minimap::/minimap/minimap_netscan.tl" as SquareMinimapNetScan
local filter = ug_require "square_better_minimap::/minimap/minimap_filter.tl" as SquareMinimapFilter

local WINDOW_ID <const> = "squareminimap.window"
local REV_CHECK_SECONDS <const> = 2.0    -- terrain/town/industry change check while the window is open
local CAM_POLL_SECONDS <const> = 0.1     -- camera box refresh (~10 Hz)
local POS_POLL_SECONDS <const> = 0.5     -- window position read (remembered for re-creation and the next load)
local FIT_POLL_SECONDS <const> = 1.0     -- picture vs window width check (log only)
local CAM_BOX_MIN_PX <const> = 12      -- keeps the 2 px outline visible as a box when zoomed all the way in
local CAM_MAX_DIST_FACTOR <const> = 4    -- footprint corners at most 4x the camera distance from the centre
-- View direction arrow in the camera box: a slim white triangle with a faint dark halo (own icon,
-- rendered by tools/render_icon_square_better_minimap.py; the game loads cam_arrow@2x.tga, 32x32),
-- turned with ImageView.rotation (degrees, builtin.d.tl:816; base turns its construction brush icon
-- by any angle with it: construction_react_util.tl:884). It replaced the base block arrow with a
-- shaft (too heavy) and before that the combobox triangle (too wide and flat: rotated, it read as
-- a shapeless wedge with no clear tip).
local ARROW_ICON <const> = "square_better_minimap::/minimap/gui/cam_arrow.tga"
local ARROW_PX <const> = 16
-- Sign of ImageView.rotation: 1 if positive turns clockwise on screen. Not documented and the base
-- game only uses symmetric turns (180), so this is the one value to flip if the arrow turns mirrored.
local ARROW_ROT_SIGN <const> = 1
-- Lowest top edge a remembered window may have (screen fraction). 0: the game lets the player drag
-- the window to the very top, and 0.06 moved such a window ~45 px down on every restore.
local WINDOW_MIN_TOP <const> = 0
-- Where a window without a remembered position opens: its top-right anchor (CSS anchorPoint {1, 0})
-- in screen fractions, right edge, below the top bar. Always passed as initialX/Y, like entity
-- windows (view_manager.tl:310-311); no CSS gravity (that is the dialogs' alternative to initialX/Y,
-- popover_react_util.css.lua:14-22, and kept the remembered position from being applied).
local DEFAULT_ANCHOR_X <const> = 1.0
local DEFAULT_ANCHOR_Y <const> = 0.12

-- Picture long side in UI px per size step (the short side keeps the map's aspect) ...
local SIZES : {integer} = { 200, 560 }
-- ... but never narrower than the window's minimum content width (title bar with pin + close, and
-- the control row), per step so S < L also for portrait maps ...
-- Estimated from builtin.css.lua:2000-2050 (title bar) + the control row; see TESTING.md "fit".
local MIN_WIDTHS : {integer} = { 180, 360 }
-- ... and the long side never above the cap (wins over MIN_WIDTHS, so a 1:5 strip stays on screen;
-- it gets a narrow band instead). Per step so strips still grow S < L; 1:2 maps fill exactly.
local MAX_LONG : {integer} = { 360, 720 }
-- ... except that the picture is never narrower than the window itself can get. With one control
-- row that was ~171 px (a 121 px picture clipped "Hi-vis", 2026-10-10); narrow pictures now get two
-- rows (geom.controlRows), so the floor is the window frame + header alone (estimate: check
-- the `fit:` log for EMPTY BAND). It wins over MAX_LONG up to ABS_MAX_LONG (two thirds of a
-- 1080 UI px screen): a 1:3 strip at S stays 121x360; only strips that would pass 720 px get a band.
local FLOOR_W <const> = 120
-- Control row packing (geom.controlRows): estimated UI px per checkbox from its translated label
-- (geom.controlWidth: one row "Ind Net Viz" measured ~155 px in the 2026-10-10 screenshot -> ~47 px per
-- 3-letter label, "Filter" ~68 px), the row's spacing and its left + right padding (minimap-controls).
-- Estimates: TESTING.md P7.
local CONTROL_SPACING <const> = 6
local CONTROL_PAD <const> = 8
local ABS_MAX_LONG <const> = 720
local SIZE_LABELS : {string} = { "S", "L" } -- log only; the button shows SIZE_ICON
-- Size toggle icon: our own tight white magnifier mask (zoom@2x.tga, 48x48, rendered by
-- tools/render_icon_square_better_minimap.py; loaded by the plain name like cam_arrow). The base
-- magnifier (gui/line_vehicle_mgmt/icons/inspector@2x.tga) has its glyph in only the middle 40% of
-- the image and read as a ~9 px dot at 22 UI px in game (2026-10-10). Tinted and sized inline
-- (icon24Style).
local SIZE_ICON <const> = "square_better_minimap::/minimap/gui/zoom.tga"
-- Top-bar button in the "Icon" style (mod.json hudButtonStyle): folded-map mask, map@2x.tga 48x48
-- (tools/render_icon_square_better_minimap.py), shown at 24 UI px like the base layers icon.
local HUD_ICON <const> = "square_better_minimap::/minimap/gui/map.tga"
-- Where the size button sits: true = the window header (builtin.Window `header`, builtin.d.tl:1209;
-- base use: the industry window's tab row, make_entity_window.tl:236), next to the pin; false = the
-- control row under the map. In game (2026-10-10) the 14 px icon in the control row was too small
-- to read, so it moved to the header (left end; no title) and grew (stylesheet R::MinimapSizeButton).
local SIZE_BUTTON_IN_HEADER <const> = true
local DEFAULT_SIZE <const> = 1 -- S: the minimap opens small

local ORIENT : SquareMinimapOrient = geom.DEFAULT_ORIENT

-- Industry marker edge in UI px per size step (S/L).
local MARKER_PX : {integer} = { 12, 18 }
-- Generic industry icon (base: industry_react_util.tl:715), for industries without a cargo icon.
local FALLBACK_ICON <const> = "::/gui/entity_window/icons/building_industry.tga"
-- Hit test tolerance around a marker (UI px) for the Shift hover / Shift+click (phase 7).
local HIT_TOL_PX <const> = 2

-- Industry filter window (phase 7): its own small window (builtin.Window, id below), next to the
-- minimap. Chevron between input and output cargo icons, as Industry Flows' type rows
-- (flows_window.script.tl CARGO_ARROW_ICON).
local FILTER_WINDOW_ID <const> = "squareminimap.filter"
local FILTER_SCROLL_ROWS <const> = 8   -- more matching types than this: the list scrolls (as Industry Flows)
local FILTER_WINDOW_FRAC_W <const> = 0.17 -- estimated filter window width (screen fraction) for placing it
local CARGO_ARROW_ICON <const> = "::/gui/builtin/combobox/arrow_right.tga"

---------------------------------------------------------------------------
-- Logging

local function logm(msg : string)
	log.message("[Minimap] " .. msg)
end

local warned : {string : boolean} = {}

--- One warning per key, so a failure in a 10 Hz poll doesn't flood the log.
local function warnOnce(key : string, msg : string)
	if warned[key] then return end
	warned[key] = true
	log.warning("[Minimap] " .. key .. " failed: " .. msg .. " (further failures not logged)")
end

local clock : function() : number = (os ~= nil and os.clock ~= nil) and os.clock or function() : number return 0 end

local perfStep = sqperf.new({ mod = "square_better_minimap", ctx = "step", paramKey = "sqperf_log",
	first = { "map_gen", "industries_read" } })

local function ms(t0 : number, t1 : number) : string
	return string.format("%.1f ms", (t1 - t0) * 1000)
end

---------------------------------------------------------------------------
-- Session state (GUI-local module tables, never saved; reset when the GUI scripts reload).

local record Session
	withAssets : boolean
	showIndustries : boolean
	showNet : boolean  -- network layer (phase 6); default off
	hiVis : boolean    -- network layer in the high-visibility palette; default off
	sizeIdx : integer
	pinned : boolean
	posX : number      -- window anchor (top-right, CSS anchorPoint {1, 0}) in screen fractions
	posY : number
	open : boolean     -- the player has the window open (set by open/close actions only, not by unmounts)
	filter : SquareMinimapFilterSel -- industry types shown (phase 7); empty = all
	filterQuery : string            -- filter window search text (session only, not remembered)
end

-- Window lifecycle. The window is added once and then only hidden/shown by id (like the base
-- game's shelved entity windows, view_manager.tl:333-336, 410-414), so it keeps its position.
local windowMounted = false  -- MinimapWindow is in the window container
local hiddenByUs = false     -- we hid it (Map button, X); anything else hiding it while pinned is undone

local function isShown() : boolean
	local ok, vOrErr = pcall(api.gui.byId.isVisible, WINDOW_ID)
	if not ok then return true end -- unknown: behave as visible (polls keep running)
	return vOrErr == true
end

local session : Session = {
	withAssets = false,
	showIndustries = true,
	showNet = false,
	hiVis = false,
	sizeIdx = DEFAULT_SIZE,
	pinned = false,
	open = false,
	filter = {},
	filterQuery = "",
}

---------------------------------------------------------------------------
-- Remembered settings: position, pin, size, industry toggle and whether a pinned window was open
-- survive game loads (the GUI scripts reload and reset `session`). Stored in the game settings, not
-- the save: AppConfig.mainMenuState is "filled by the UI scripts to persist things"
-- (type.d.tl:2885). Same read-copy-write as the base new-game page
-- (new_game_or_map_settings_page.tl:532-541); setAppConfig "does not save" (util.d.tl:260), so
-- saveAppConfig follows (settings_page.tl:1400). Main thread only (the plugin's onStep): loaded
-- once, written once the values have been stable for PREFS_STABLE_TICKS guard ticks (a drag
-- produces many positions; only the final one is written).

local PREFS_KEY <const> = "square_better_minimap"
local PREFS_STABLE_TICKS <const> = 4 -- x GUARD_SECONDS (0.25 s) = 1 s without changes

local prefsLoaded = false
local savedPrefs : SquareMinimapPrefs = nil   -- what the settings hold (as last read or written)
local pendingPrefs : SquareMinimapPrefs = nil -- unsaved values and how many ticks they held still
local pendingTicks = 0

local function currentPrefs() : SquareMinimapPrefs
	return {
		posX = session.posX ~= nil and geom.round(session.posX, 4) or nil,
		posY = session.posY ~= nil and geom.round(session.posY, 4) or nil,
		pinned = session.pinned,
		sizeIdx = session.sizeIdx,
		showIndustries = session.showIndustries,
		showNet = session.showNet,
		hiVis = session.hiVis,
		open = session.open and session.pinned,
		filterTypes = filter.toPrefs(session.filter),
	}
end

local function prefsText(p : SquareMinimapPrefs) : string
	return string.format("pos %s, pinned=%s, size=%s, industries=%s, net=%s, hivis=%s, open=%s, filter=%s",
		p.posX ~= nil and string.format("%.4f,%.4f", p.posX, p.posY) or "(none)",
		tostring(p.pinned), tostring(p.sizeIdx), tostring(p.showIndustries), tostring(p.showNet), tostring(p.hiVis), tostring(p.open),
		(p.filterTypes == nil or p.filterTypes == "") and "all" or p.filterTypes)
end

--- Read the remembered settings into `session`, once. Never throws.
local function loadPrefs()
	if prefsLoaded then return end
	prefsLoaded = true
	local ok, rawOrErr = pcall(function() : any
		local mm = api.type.AppConfig.new(api.util.getAppConfig()).mainMenuState as {string : any}
		return mm ~= nil and mm[PREFS_KEY] or nil
	end)
	if not ok then
		warnOnce("load settings", tostring(rawOrErr))
		savedPrefs = currentPrefs()
		return
	end
	local p = geom.readPrefs(rawOrErr, #SIZES, WINDOW_MIN_TOP)
	if p.posX ~= nil then session.posX, session.posY = p.posX, p.posY end
	if p.pinned ~= nil then session.pinned = p.pinned end
	if p.sizeIdx ~= nil then session.sizeIdx = p.sizeIdx end
	if p.showIndustries ~= nil then session.showIndustries = p.showIndustries end
	if p.showNet ~= nil then session.showNet = p.showNet end
	if p.hiVis ~= nil then session.hiVis = p.hiVis end
	if p.filterTypes ~= nil then session.filter = filter.fromPrefs(p.filterTypes) end
	session.open = p.open == true and session.pinned
	savedPrefs = currentPrefs()
	logm("settings: loaded " .. (rawOrErr ~= nil and prefsText(savedPrefs) or "nothing stored, defaults"))
end

local function writePrefs(p : SquareMinimapPrefs)
	local ok, err = pcall(function() : any
		local cfg = api.type.AppConfig.new(api.util.getAppConfig())
		local mm = cfg.mainMenuState
		local t = (mm ~= nil and table_util.copy(mm) or {}) as {string : any}
		t[PREFS_KEY] = {
			posX = p.posX, posY = p.posY, pinned = p.pinned, sizeIdx = p.sizeIdx,
			showIndustries = p.showIndustries, showNet = p.showNet, hiVis = p.hiVis, open = p.open,
			filterTypes = p.filterTypes,
		}
		cfg.mainMenuState = t
		api.util.setAppConfig(cfg, false)
		api.util.saveAppConfig()
		return nil
	end)
	-- Marked saved even on failure, so a broken API is warned about once, not retried every second.
	savedPrefs = p
	if ok then
		logm("settings: saved " .. prefsText(p))
	else
		warnOnce("save settings", tostring(err))
	end
end

--- Called every guard tick: write the settings once they changed and then held still.
local function maintainPrefs()
	if not prefsLoaded then return end
	local cur = currentPrefs()
	if table_util.deepEquals(cur, savedPrefs) then
		pendingPrefs, pendingTicks = nil, 0
		return
	end
	if pendingPrefs ~= nil and table_util.deepEquals(cur, pendingPrefs) then
		pendingTicks = pendingTicks + 1
	else
		pendingPrefs, pendingTicks = cur, 0
	end
	if pendingTicks >= PREFS_STABLE_TICKS then
		pendingPrefs, pendingTicks = nil, 0
		writePrefs(cur)
	end
end

---------------------------------------------------------------------------
-- Engine reads

local record RevState
	terrain : {integer : {integer, integer}}
	towns : {integer : {integer, integer}}
	industries : {integer : boolean}
	bounds : {number} -- terrain bounding box: the map editor can resize the map
	heights : {number} -- base height on a HEIGHT_GRID x HEIGHT_GRID grid
end

local HEIGHT_GRID <const> = 9 -- 81 getBaseHeightAt calls per check

--- map_editor.tl:308-323 (terrain entity revisions + town revisions), plus the set of industries
--- (INDUSTRY component: mission_savegame_util.tl:39). Industry revisions are not used: they change
--- with production all the time; only founding/removing one changes the picture.
--- The terrain bounds catch a map editor resize (the box drives every world <-> picture mapping).
--- The height grid catches the map editor's Generate Heightmap: makeWorldReplaceTerrainCmd leaves the
--- terrain entity revisions unchanged (in game 2026-10-10: no rebuild after Generate). Base height,
--- not getHeightAt: construction alignments would rebuild on every station placed.
local function readRevState() : RevState
	local terrain : {integer : {integer, integer}} = {}
	for e, r in pairs(api.engine.terrain.getTerrainEntityRevisions()) do
		terrain[e as integer] = { r.num[1], r.num[2] }
	end
	local towns : {integer : {integer, integer}} = {}
	api.engine.forEachEntityWithComponent(function(e : Engine.Entity)
		local r = api.engine.getRevision(e)
		towns[e as integer] = { r.num[1], r.num[2] }
	end, api.type.ComponentType.TOWN)
	local industries : {integer : boolean} = {}
	api.engine.forEachEntityWithComponent(function(e : Engine.Entity)
		industries[e as integer] = true
	end, api.type.ComponentType.INDUSTRY)
	local bb = api.engine.terrain.getBoundingBox()
	local bounds = { bb.min.x, bb.min.y, bb.max.x, bb.max.y }
	local heights : {number} = {}
	local w, h = bb.max.x - bb.min.x, bb.max.y - bb.min.y
	for i = 0, HEIGHT_GRID - 1 do
		for j = 0, HEIGHT_GRID - 1 do
			local p = api.type.Vec2f.new(bb.min.x + w * (i + 0.5) / HEIGHT_GRID, bb.min.y + h * (j + 0.5) / HEIGHT_GRID)
			heights[#heights + 1] = api.engine.terrain.getBaseHeightAt(p)
		end
	end
	return { terrain = terrain, towns = towns, industries = industries, bounds = bounds, heights = heights }
end

--- Which parts of two RevStates differ, for the rebuild log line.
local function revDiff(a : RevState, b : RevState) : string
	if a == nil or b == nil then return "first read" end
	local parts : {string} = {}
	for _i, k in ipairs({ "terrain", "towns", "industries", "bounds", "heights" }) do
		if not table_util.deepEquals((a as table)[k], (b as table)[k]) then parts[#parts + 1] = k end
	end
	return table.concat(parts, "+")
end

local function countList(list : any) : integer
	local n = 0
	local ok = pcall(function()
		for __ in ipairs(list as {any}) do n = n + 1 end
	end)
	return ok and n or -1
end

---------------------------------------------------------------------------
-- Industries (main thread; read once per map build)

local cargoIconCache : {integer : string} = {}
local cargoNameCache : {integer : string} = {} -- filter search; "" when unknown

--- CargoType.icon (cargo_util.tl:436-439) and .name (the base game shows it as is: cargo icon
--- tooltips, cargo_react_util.tl:27-28); "" when unknown. Cached: cargo resources don't change.
local function cargoIcon(cargoTypeId : integer) : string
	local cached = cargoIconCache[cargoTypeId]
	if cached ~= nil then return cached end
	local ok, ctOrErr = pcall(function() : CargoType
		return api.res.cargoTypeRep.get(cargoTypeId as CargoTypeId)
	end)
	local path, name = "", ""
	if ok and ctOrErr ~= nil then
		local ct = ctOrErr as CargoType
		if type(ct.icon) == "string" then path = ct.icon end
		if type(ct.name) == "string" then name = ct.name end
	elseif not ok then
		warnOnce("cargo icon", tostring(ctOrErr))
	end
	cargoIconCache[cargoTypeId] = path
	cargoNameCache[cargoTypeId] = name
	return path
end

local function cargoIcons(ids : {CargoTypeId}) : {string}
	local out : {string} = {}
	if ids == nil then return out end
	for i = 1, #ids do
		out[#out + 1] = cargoIcon(ids[i] as integer)
	end
	return out
end

local function cargoIdList(ids : {CargoTypeId}) : {integer}
	local out : {integer} = {}
	if ids == nil then return out end
	for i = 1, #ids do out[#out + 1] = ids[i] as integer end
	return out
end

--- Industry type key (phase 7): the construction's fileName, found like Industry Flows' gather.typeOf
--- (mods/square_industry_flows/content/industry_flows/flows_gather.tl; base hud_icon_toolbox.tl:242-245).
--- "" when unknown. Throws on API errors.
local function industryTypeOf(e : Engine.Entity) : string
	local conEntity = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(e)
	if conEntity == nil or (conEntity as integer) < 0 then return "" end
	local con = api.engine.getComponent(conEntity, api.type.ComponentType.CONSTRUCTION) as Engine.Component.Construction
	if con == nil or con.fileName == nil then return "" end
	return con.fileName as string
end

-- typeKey -> localized construction description.name (gather.typeName); misses cached too.
local typeNameCache : {string : string} = {}
local typeNameMissing : {string : boolean} = {}

--- constructionRep.find + get (construction.tl:1236-1240), as Industry Flows' gather.typeName. nil when unknown.
local function industryTypeName(typeKey : string) : string
	if typeKey == nil or typeKey == "" then return nil end
	if typeNameCache[typeKey] ~= nil or typeNameMissing[typeKey] then return typeNameCache[typeKey] end
	local ok, name = pcall(function() : string
		local id = api.res.constructionRep.find(typeKey)
		if id == nil or id < 0 then return nil end
		local desc = api.res.constructionRep.get(id)
		if desc == nil or desc.description == nil then return nil end
		return desc.description.name
	end)
	if ok and type(name) == "string" and name ~= "" then
		typeNameCache[typeKey] = name as string
	else
		typeNameMissing[typeKey] = true
	end
	return typeNameCache[typeKey]
end

local record IndustryRead
	list : {SquareMinimapIndustry}
	byOutput : integer
	byInput : integer
	fallback : integer
	noPos : integer
	failed : integer
end

--- One INDUSTRY entity -> SquareMinimapIndustry (nil without a position). Throws on API errors.
local function readIndustry(e : Engine.Entity) : SquareMinimapIndustry, string
	local bv = api.engine.getComponent(e, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if bv == nil then return nil, nil end
	local mn, mx = bv.bbox.min, bv.bbox.max
	local outputs, inputs : {string}, {string} = {}, {}
	local outIds, inIds : {integer}, {integer} = {}, {}
	local okIo, ioErr = pcall(function() : any
		local ind = api.engine.getComponent(e, api.type.ComponentType.INDUSTRY) as Engine.Component.Industry
		local stockList = e
		if ind ~= nil and ind.stockList ~= nil and (ind.stockList as integer) >= 0 then stockList = ind.stockList end
		local io = api.engine.util.stock.getInputsOutputsFromRules(stockList)
		if io ~= nil then
			inputs = cargoIcons(io[1])
			outputs = cargoIcons(io[2])
			inIds = cargoIdList(io[1])
			outIds = cargoIdList(io[2])
		end
		return nil
	end)
	if not okIo then warnOnce("industry cargo", tostring(ioErr)) end
	local okType, typeOrErr = pcall(industryTypeOf, e)
	local rawType = ""
	if okType then
		rawType = typeOrErr as string
	else
		warnOnce("industry type", tostring(typeOrErr))
	end
	local icon, source = geom.pickIcon(outputs, inputs, FALLBACK_ICON)
	local okName, nameOrErr = pcall(api.engine.util.getEntityName, e)
	local name : string = nil
	if okName and type(nameOrErr) == "string" and nameOrErr ~= "" then name = nameOrErr as string end
	return {
		entity = e as integer,
		x = mn.x + 0.5 * (mx.x - mn.x),
		y = mn.y + 0.5 * (mx.y - mn.y),
		icon = icon,
		name = name,
		typeKey = filter.normKey(rawType),
		typeName = industryTypeName(rawType),
		inputs = inIds,
		outputs = outIds,
	}, source
end

--- Every INDUSTRY entity (mission_savegame_util.tl:39 / statistic_industries.tl:392). Never throws.
local function readIndustries() : IndustryRead
	local r : IndustryRead = { list = {}, byOutput = 0, byInput = 0, fallback = 0, noPos = 0, failed = 0 }
	local okList, listOrErr = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.INDUSTRY)
	if not okList or listOrErr == nil then
		warnOnce("industry list", tostring(listOrErr))
		return r
	end
	for __, e in ipairs(listOrErr as {Engine.Entity}) do
		local ok, itOrErr, source = pcall(readIndustry, e)
		if not ok then
			r.failed = r.failed + 1
			warnOnce("industry read", tostring(itOrErr))
		elseif itOrErr == nil then
			r.noPos = r.noPos + 1
		else
			r.list[#r.list + 1] = itOrErr as SquareMinimapIndustry
			if source == "output" then
				r.byOutput = r.byOutput + 1
			elseif source == "input" then
				r.byInput = r.byInput + 1
			else
				r.fallback = r.fallback + 1
			end
		end
	end
	return r
end

local record MapData
	gen : integer
	map : GameMap
	box : SquareMinimapBox
	industries : {SquareMinimapIndustry}
	builtAt : number   -- clock() when built (onReady logs the delay)
	buildText : string
end

local genCounter = 0

--- Builds the GameMap + the terrain box. Never throws; nil on failure (logged once).
local function buildMapData(reason : string) : MapData
	local t0 = clock()
	local tPerf = perfStep:start()
	-- withIndustries = false: no generic preview markers; ours are drawn by MinimapMarkers.
	local okMap, mapOrErr = pcall(api.engine.terrain.makeMapFromGame, true, true, false, session.withAssets)
	perfStep:stop("map_gen", tPerf) -- also failed builds
	local t1 = clock()
	if not okMap or mapOrErr == nil then
		warnOnce("makeMapFromGame", tostring(mapOrErr))
		return nil
	end
	local map = mapOrErr as GameMap
	local okBox, bbOrErr = pcall(api.engine.terrain.getBoundingBox)
	if not okBox or bbOrErr == nil then
		warnOnce("getBoundingBox", tostring(bbOrErr))
		return nil
	end
	local bb = bbOrErr as Box2f
	local box = geom.boxFromBounds(bb.min.x, bb.min.y, bb.max.x, bb.max.y)
	genCounter = genCounter + 1
	local t2 = clock()
	tPerf = perfStep:start()
	local ind = readIndustries()
	perfStep:stop("industries_read", tPerf)
	local t3 = clock()
	local text = string.format("%d towns, %d industries, built in %s",
		countList(map.towns), #ind.list, ms(t0, t1))
	logm(string.format("map gen %d (%s, assets=%s): %s", genCounter, reason, tostring(session.withAssets), text))
	logm(string.format("industries gen %d: %d markers, icons %d from product + %d from input, %d fallback; %d without position, %d failed; read in %s",
		genCounter, #ind.list, ind.byOutput, ind.byInput, ind.fallback, ind.noPos, ind.failed, ms(t2, t3)))
	return { gen = genCounter, map = map, box = box, industries = ind.list, builtAt = t1, buildText = text }
end

local record PreviewEnv
	coloring : PreviewColoring
	economy : string
	locations : BaseConfig.Locations
end

local previewEnvCache : PreviewEnv = nil

--- mapColoring / economy / locations exactly as map_editor.tl:2671-2681; the climate falls back to
--- the GameMap's own climateId.
local function previewEnv(map : GameMap) : PreviewEnv
	if previewEnvCache ~= nil then return previewEnvCache end
	local ok, envOrErr = pcall(function() : PreviewEnv
		local base = api.res.getBaseConfig()
		local climate = base.climate
		if climate == nil or climate == "" then climate = map.climateId end
		local desc = api.res.climateRep.get(api.res.climateRep.find(climate))
		return { coloring = desc.mapColoring, economy = base.economyId, locations = base.locations }
	end)
	if not ok then
		warnOnce("previewEnv", tostring(envOrErr))
		return {}
	end
	previewEnvCache = envOrErr as PreviewEnv
	return previewEnvCache
end

local keepModeCache : any = nil

--- map_editor.tl:546-553 with everything kept and nothing generated (phase 1: shows the save as-is).
--- One object for the session (a fresh userdata each render could make the component regenerate).
local function keepMode() : any
	if keepModeCache ~= nil then return keepModeCache end
	local ok, modeOrErr = pcall(function() : any
		local m = api.type.HeighmapGenerationMode.new()
		m.generateTowns = false
		m.generateIndustries = false
		m.generateAssets = false
		m.keepHeightmap = true
		m.keepBiomes = true
		return m
	end)
	if not ok then
		warnOnce("previewMode", tostring(modeOrErr))
		return nil
	end
	keepModeCache = modeOrErr
	return keepModeCache
end

---------------------------------------------------------------------------
-- Camera (main thread only: call from react.onStep or input callbacks)

local record CamView
	cx : number          -- camera centre, minimap fraction
	cy : number
	rect : SquareMinimapRect
	hx : number          -- view direction (screen up projected onto the ground), fraction space; nil = unknown
	hy : number
end

local loggedFootprint = false -- reset per overlay mount: the first footprint is logged in full

local function v3(v : Vec3f) : string
	if v == nil then return "nil" end
	return string.format("(%.0f,%.0f,%.0f)", v.x, v.y, v.z)
end

local function dist2(a : Vec3f, b : Vec3f) : number
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2
end

--- The four screen corners projected onto the horizontal plane through the camera centre's ground
--- height, each at most CAM_MAX_DIST_FACTOR x distance from the centre (geom.groundPoint), as
--- minimap fractions. Each corner ray runs from the screen2World point at depth 0 to the one at
--- depth 1 (gui.d.tl:483-484), ordered by distance to the eye so a reversed depth range still works.
--- (Phase 2 used traceToTerrain(eye, far-plane point, 0, 30): with the far plane kilometres away the
--- 30 steps were so coarse that the hits barely moved; in game the box hardly followed the camera.)
--- Also returns the view direction in fraction space: the midpoint of the top screen corners minus
--- the midpoint of the bottom ones on the ground. Works at any pitch, also straight down (it is
--- then the screen's up), and needs no convention for getCameraData's angle.
local function cameraFootprint(box : SquareMinimapBox, d : Vec5f) : SquareMinimapRect, number, number
	local cam = api.gui.camera
	local size = cam.getSize()
	local eye = cam.getEye()
	local planeZ : number
	local okH, hOrErr = pcall(api.engine.terrain.getHeightAt, api.type.Vec2f.new(d.x, d.y))
	if okH and hOrErr ~= nil then
		planeZ = hOrErr as number
	else
		planeZ = cam.getCenter().z
	end
	local maxDist = CAM_MAX_DIST_FACTOR * math.max(d.z, 50)
	local corners : {{number, number}} = { { 0, 0 }, { size.x, 0 }, { size.x, size.y }, { 0, size.y } }
	local pts : {number} = {}
	local logLines : {string} = {}
	for i, c in ipairs(corners) do
		local p0 = cam.screen2World(api.type.Vec3f.new(c[1], c[2], 0.0))
		local p1 = cam.screen2World(api.type.Vec3f.new(c[1], c[2], 1.0))
		local nearP, farP = p0, p1
		if nearP == nil then nearP = eye end
		if farP ~= nil and dist2(farP, eye) < dist2(nearP, eye) then nearP, farP = farP, nearP end
		local gx, gy : number, number
		local hit = false
		if farP == nil or dist2(nearP, farP) < 1e-6 then
			gx, gy = d.x, d.y
		else
			gx, gy, hit = geom.groundPoint(nearP.x, nearP.y, nearP.z, farP.x, farP.y, farP.z, planeZ, d.x, d.y, maxDist)
		end
		local fx, fy = geom.worldToFrac(gx, gy, box, ORIENT)
		pts[#pts + 1] = fx
		pts[#pts + 1] = fy
		if not loggedFootprint then
			logLines[#logLines + 1] = string.format("  corner %d (%d,%d): depth0 %s depth1 %s -> ground (%.0f,%.0f) %s, frac (%.3f,%.3f)",
				i, c[1], c[2], v3(p0), v3(p1), gx, gy, hit and "hit" or "capped", fx, fy)
		end
	end
	local rect = geom.rectFromPoints(pts)
	if not loggedFootprint then
		loggedFootprint = true
		local cx, cy = geom.worldToFrac(d.x, d.y, box, ORIENT)
		logm(string.format("first camera footprint: viewport %dx%d, eye %s, centre (%.0f,%.0f) frac (%.3f,%.3f), distance %.0f, plane z %.1f, cap %.0f m; rect x %.3f..%.3f y %.3f..%.3f",
			size.x, size.y, v3(eye), d.x, d.y, cx, cy, d.z, planeZ, maxDist, rect.x0, rect.x1, rect.y0, rect.y1))
		for __, line in ipairs(logLines) do logm(line) end
	end
	-- corners 1, 2: top of the screen; 3, 4: bottom (see `corners`)
	local hx = (pts[1] + pts[3] - pts[5] - pts[7]) / 2
	local hy = (pts[2] + pts[4] - pts[6] - pts[8]) / 2
	return rect, hx, hy
end

local function readCamView(box : SquareMinimapBox) : CamView
	local d = api.gui.camera.getCameraData()
	local cx, cy = geom.worldToFrac(d.x, d.y, box, ORIENT)
	local ok, rOrErr, hx, hy = pcall(cameraFootprint, box, d)
	local rect : SquareMinimapRect = nil
	if ok then
		rect = rOrErr as SquareMinimapRect
	else
		hx, hy = nil, nil
		warnOnce("camera footprint", tostring(rOrErr))
	end
	if rect == nil then
		rect = geom.rectAround(d.x, d.y, math.max(d.z, 50), box, ORIENT)
	end
	return { cx = cx, cy = cy, rect = rect, hx = hx as number, hy = hy as number }
end

local function jumpTo(wx : number, wy : number)
	local ok, err = pcall(function() : any
		local d = api.gui.camera.getCameraData()
		-- keep distance, angle and pitch; move the look-at point (Vec5f layout: gui.d.tl:430-437)
		api.gui.camera.setCameraData(api.type.Vec5f.new(wx, wy, d.z, d.w, d.q))
		return nil
	end)
	if not ok then
		warnOnce("setCameraData", tostring(err))
	end
end

---------------------------------------------------------------------------
-- Industry filter state (phase 7; pure rules in minimap_filter.tl). One selection (session.filter,
-- remembered in the prefs) shared by Shift+click on the map and the filter window. Recipes that
-- show it register a re-render callback in filterListeners on every render (like cycleSizeFn);
-- setFilter calls them. GUI thread only (click and widget handlers).

local filterSeq = 0                                -- bumped on every selection change
local filterListeners : {string : function(integer)} = {}
local shownData : MapData = nil                    -- the map MinimapContent shows (set on its render)
local typesCache : {SquareMinimapFilterType} = nil -- filter.groupTypes of typesCacheGen
local typesCacheGen = -1

--- Industry types of a map (grouped once per map generation).
local function typesFor(data : MapData) : {SquareMinimapFilterType}
	if data == nil then return {} end
	if typesCacheGen ~= data.gen or typesCache == nil then
		local ok, tOrErr = pcall(filter.groupTypes, data.industries, cargoNameCache, _("Other"))
		if ok then
			typesCache = tOrErr as {SquareMinimapFilterType}
		else
			warnOnce("industry types", tostring(tOrErr))
			typesCache = {}
		end
		typesCacheGen = data.gen
	end
	return typesCache
end

local function setFilter(sel : SquareMinimapFilterSel, why : string)
	if filter.same(sel, session.filter) then return end
	session.filter = sel
	filterSeq = filterSeq + 1
	local types = typesFor(shownData)
	local shown, total = filter.shownCount(types, sel)
	logm(string.format("filter: %s -> %s (%d of %d types on the map shown)", why, filter.describe(sel), shown, total))
	for __, fn in pairs(filterListeners) do
		local ok, err = pcall(function() : any
			fn(filterSeq)
			return nil
		end)
		if not ok then warnOnce("filter listener", tostring(err)) end
	end
end

--- Shift (IA_PRECISION_MODE, Shift by default; base construction_react_util.tl:1916) held. GUI thread.
local function shiftHeld() : boolean
	local ok, vOrErr = pcall(api.gui.inputAction.modifierOnlyActionIsActive, "IA_PRECISION_MODE")
	if not ok then
		warnOnce("shift read", tostring(vOrErr))
		return false
	end
	return vOrErr == true
end

-- The marker layout the markers layer shows (published by MinimapMarkers), for the canvas's hit
-- test, and the markers layer's hover setter (nil while it isn't mounted).
local shownMarkers : {SquareMinimapMarkerPx} = nil
local shownMarkerSize = 0
local markersHoverFn : function(string) = nil

---------------------------------------------------------------------------
-- Widgets

local function text(str : string, class? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-body" },
		text = str,
	}
end

local function boxClass(class : string) : string
	return class and (class .. ", minimap-box") or "minimap-box"
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

--- A flag raised by a (deferred, restricted-API) step timer and consumed in onStep (main thread).
--- Must be called unconditionally from a recipe (it uses hooks).
local function useMainThreadTick(intervalSeconds : number) : function() : boolean
	local dueRef = react.useRef(true) as ReactRefT<boolean>
	react.onStepTimer(function()
		dueRef:set(true)
	end, intervalSeconds)
	return function() : boolean
		if not dueRef:get() then return false end
		dueRef:set(false)
		return true
	end
end

---------------------------------------------------------------------------
-- Preview layer

local record PreviewParam
	data : MapData
	w : integer
	h : integer
end

local MinimapPreview = react.RegisterRecipe("MinimapPreview", perf:wrap("preview_render", function(params : PreviewParam) : TreeNodeId
	-- map_editor.tl:2652-2662: the editor shows the component one step after mounting.
	local readyState = react.useState(false) as ReactStateT<boolean>
	react.onStep(function()
		if not readyState:old() then readyState:set(true) end
	end)
	if not readyState:old() or params.data == nil then
		-- Placeholder of the picture's size, so the window doesn't jump when the map arrives.
		return vbox({
			builtin.Component{
				meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
				layout = vbox({ builtin.TextView{
					-- Colour inline (meta.styleSheet), not a stylesheet rule: mod rules are capped (docs/findings.md
					-- "Load crash above ~200 mod stylesheet rules").
					meta = {
						class = "font-scale-annotation, minimap-status",
						styleSheet = styleutil.makeStyle{ color = colors().NeutralLight },
					},
					text = _("Loading map..."),
				} }),
			},
		})
	end
	local data = params.data
	-- Every content render (toggles, filter changes) re-renders this recipe; building the
	-- MapPreviewComp params again cost ~4 ms (SQPERF 2026-10-10, 75 calls). While the map and the
	-- size are unchanged the old node is returned (findOldChildByLocalKey, as MinimapNetStrip).
	local reuseKey = string.format("pv_%d_%d_%d", data.gen, params.w, params.h)
	local findOld = (react as {string : any})["findOldChildByLocalKey"] as function(string) : TreeNodeId
	if findOld ~= nil then
		local old = findOld(reuseKey)
		if old ~= nil then
			perf:count("preview_reused")
			return old
		end
	end
	local env = previewEnv(data.map)
	local mountedAt = clock()
	return builtin.BoxLayout{
		meta = { class = boxClass(nil), localKey = reuseKey },
		orientation = builtin.type.Orientation.Vertical,
		children = { builtin.MapPreviewComp{
			meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
			mapColoring = env.coloring,
			showMapSize = false,
			showTownAndIndustryCount = false,
			showBiomesColors = false,
			inputMap = data.map,
			initialMap = data.map,
			mode = keepMode(),
			economy = env.economy,
			locationsConfig = env.locations,
			onReady = function(_map : GameMap, _feedback : {string})
				local now = clock()
				logm(string.format("preview ready gen %d (%dx%d px): %s after mount, %s after build",
					data.gen, params.w, params.h, ms(mountedAt, now), ms(data.builtAt, now)))
			end,
			onTownConnectionsChanged = function(_c : {{integer, integer}})
				-- Preview-local edit (map_editor.tl:2697-2707 writes it into its own copy); ignored.
			end,
		} },
	}
end))

---------------------------------------------------------------------------
-- Industry markers (re-mounted with the preview; no polling, nothing per camera tick)

local record MarkersParam
	data : MapData
	w : integer
	h : integer
	size : integer
	filterSeq : integer -- re-render on a filter change (the selection itself is session.filter)
end

--- A full-picture layer (h = v = -1, which fills the parent: proven in game) whose padding
--- leaves exactly a w x h content area at (left, top), holding `item`. Placement uses only sizes
--- and padding: in game, FloatingLayoutChild h/v placement failed for anything but a tiny child
--- (gravity: stuck at the left edge; sized container at 1,1: x ignored; anchorPoint + Overflow:
--- everything at left-centre). Padding order is CSS (top, right, bottom, left), as the base
--- *.css.lua files use it (e.g. { 2, 8, 2, 8 } for wide buttons).
local function layerAt(key : string, left : integer, top : integer, w : integer, h : integer,
		pw : integer, ph : integer, item : TreeNodeId) : TreeNodeId
	local st = styleutil.makeStyle{ size = { pw, ph } }
	st.padding = api.type.Vec4f.new(top, math.max(0, pw - left - w), math.max(0, ph - top - h), left)
	return builtin.FloatingLayoutChild{
		localKey = key,
		h = -1,
		v = -1,
		item = builtin.Component{
			meta = { styleSheet = st },
			mouseTransparent = true,
			layout = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = { item },
			},
		},
	}
end

local record MarkerIconsParam
	key : string                        -- reuse key: layout key + filter sequence (+ hovered type)
	layout : {SquareMinimapMarkerPx}
	w : integer
	h : integer
	size : integer
	hover : string                      -- Shift hover type: every other type's icons are faded; nil = none
end

-- One layer of industry icons. While its key is unchanged the old node is returned
-- (react.findOldChildByLocalKey at the recipe root, as MinimapNetStrip), so canvas re-renders
-- (toggles, S/L) and hover changes build no ImageViews.
local MinimapMarkerIcons = react.RegisterRecipe("MinimapMarkerIcons", perf:wrap("marker_icons_render", function(params : MarkerIconsParam) : TreeNodeId
	react.setMouseTransparent(true)
	local findOld = (react as {string : any})["findOldChildByLocalKey"] as function(string) : TreeNodeId
	if findOld ~= nil then
		local old = findOld(params.key)
		if old ~= nil then
			perf:count("marker_icons_reused")
			return old
		end
	end
	perf:count("marker_icons_built")
	local size = params.size
	local sel = session.filter
	local children : {TreeNodeId} = {}
	for __, m in ipairs(params.layout) do
		if filter.isVisible(m.typeKey, sel) then
			local muted = params.hover ~= nil and m.typeKey ~= params.hover
			children[#children + 1] = layerAt(m.key, m.left, m.top, size, size, params.w, params.h, builtin.ImageView{
				meta = {
					class = muted and "minimap-industry-icon, minimap-industry-muted" or "minimap-industry-icon",
					tooltip = m.name,
					-- Shift hover (phase 7): the faded look of the other types inline (an inline style beats the
					-- minimap-industry-icon rule; base: vehicle.tl:100-105 bubble backgroundColor1).
					styleSheet = muted and mutedIconStyle(size) or styleutil.makeStyle{ size = { size, size } },
				},
				scaling = builtin.type.ImageViewScaling.AutoFit,
				path = m.icon,
			})
		end
	end
	return builtin.BoxLayout{
		meta = { class = boxClass(nil), localKey = params.key },
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.Component{
				meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
				mouseTransparent = true,
				layout = builtin.FloatingLayout{ children = children },
			},
		},
	}
end))

local MinimapMarkers = react.RegisterRecipe("MinimapMarkers", perf:wrap("markers_render", function(params : MarkersParam) : TreeNodeId
	-- Layout cached per map generation + picture/marker size (pure data; nodes are made each render).
	local layoutRef = react.useRef(nil) as ReactRefT<{SquareMinimapMarkerPx}>
	local layoutKeyRef = react.useRef("") as ReactRefT<string>
	-- Shift hover (phase 7): the type under the pointer while Shift is held; others are drawn faded.
	-- Set by the canvas through markersHoverFn: only this recipe re-renders (same layout key, no
	-- re-mount of the preview or the net layer).
	local hoverState = react.useState(nil) as ReactStateT<string>
	-- One setter per mount; the unmount only clears the module slots if they are still this
	-- mount's (on a re-mount, gen/size key, the new layer renders before the old one unmounts).
	-- The setter reads the state through a ref refreshed on every render (never a stale capture).
	local hoverStateRef = react.useRef(hoverState) as ReactRefT<ReactStateT<string>>
	hoverStateRef:set(hoverState)
	local hoverFnRef = react.useRefLazy(function() : function(string)
		return function(typeKey : string)
			local st = hoverStateRef:get()
			if st:old() ~= typeKey then
				st:set(typeKey)
				perf:count("hover_changes")
			end
		end
	end) as ReactRefT<function(string)>
	markersHoverFn = hoverFnRef:get()
	react.onUnmount(function()
		if markersHoverFn == hoverFnRef:get() then
			markersHoverFn = nil
			shownMarkers = nil
		end
	end)
	local key = string.format("%d_%d_%d_%d", params.data.gen, params.w, params.h, params.size)
	if layoutKeyRef:get() ~= key then
		local ok, lOrErr = pcall(geom.markerLayout, params.data.industries, params.data.box, ORIENT, params.w, params.h, params.size)
		if ok then
			layoutRef:set(lOrErr as {SquareMinimapMarkerPx})
		else
			warnOnce("marker layout", tostring(lOrErr))
			layoutRef:set({})
		end
		layoutKeyRef:set(key)
		logm(string.format("industry markers gen %d: %d drawn (%dx%d px picture, %d px icons)",
			params.data.gen, #layoutRef:get(), params.w, params.h, params.size))
	end
	shownMarkers, shownMarkerSize = layoutRef:get(), params.size
	-- One icon layer, its node reused while layout, filter and hover are unchanged, so canvas
	-- re-renders (toggles, S/L) build no icons. A hover change re-styles every icon (~2 ms, SQPERF
	-- 2026-10-10). Tried instead (2026-10-10, both rejected in game): a dark layer over the map with
	-- the hovered icons on top (covered map and network); swapping a normal and a faded cached layer
	-- with api.gui.byId.setVisible (every icon flashed on each hover change).
	local hover = hoverState:old()
	local layers : {TreeNodeId} = {
		builtin.FloatingLayoutChild{ h = -1, v = -1, localKey = "all",
			item = MinimapMarkerIcons{ key = "mk_" .. key .. "_" .. tostring(filterSeq) .. "_" .. (hover or ""),
				layout = layoutRef:get(), w = params.w, h = params.h, size = params.size, hover = hover } },
	}
	-- Same frame as the camera overlay: sized, mouse-transparent Component, builtin FloatingLayout.
	return hbox({
		builtin.Component{
			meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
			mouseTransparent = true,
			layout = builtin.FloatingLayout{
				children = layers,
			},
		},
	})
end))


---------------------------------------------------------------------------
-- Network layer (phase 6, plans/square_better_minimap/PLAN.md): streets, tracks and town
-- buildings drawn into one RGBA image (builtin.ImageView{ data, size }, builtin.d.tl:799-816)
-- laid over the preview, under the industry icons. Toggled with the "Net" checkbox; default off.
--
-- OFF = NO COST: the layer recipe (MinimapNetLayer) is only mounted while the toggle is on, so
-- off means no onStep, no timer, no engine read, no ImageView. Toggling off PARKS the finished
-- image, grid and entity caches (netPark; the Lua encode buffers are dropped) for NET_OFF_KEEP_SECONDS:
-- toggling on again within that time shows the cached image at once and runs only an incremental
-- rescan (no grid allocation, no first build, no burst of garbage). The release check piggybacks on
-- the plugin's guard tick (one comparison per 0.25 s, netCheckParked). While on but the window is
-- hidden, nothing is read (checked once a second), and after NET_HIDDEN_RELEASE_SECONDS hidden the
-- caches are dropped (re-opening rebuilds). Unmounting the window or an error drops them at once.
--
-- HI-VIS: a second palette (net.COLORS_HIVIS). The grid stores layer counts, not colours, so a
-- switch only re-encodes (time-sliced like any encode, net.recolorAction); nothing is re-read.
--
-- STRIPS: the image is shown as horizontal strips of 64 rows (net STRIPS, net.STRIP_BANDS), each
-- its own ImageView with its own buffer and params userdata. The one Lua -> C++ copy of a whole
-- 512x512 image took 7.9-8.2 ms in ONE frame (stdout.txt 2026-10-10), for every update; now only
-- the strips whose bands changed are handed off, one strip (~1 ms) per frame, and published
-- together (one version bump: the picture never shows half-old strips). Placement: strip rows
-- r0 .. r1 - 1 sit at round(r0 * h / H) .. round(r1 * h / H) UI px (net.stripPlacement).
--
-- IMAGE HAND-OFF: react.lua makeUserdata copies a `data` table into the C++ params on EVERY
-- builtin.ImageView{ data = ... } node (0.5-1 M Lua values per copy). Instead, each finished strip is
-- copied once into an ImageView params userdata (api.gui.react.params.builtin.ImageView.new(), the
-- class makeUserdata uses); a new node passes that userdata, which makeUserdata hands to
-- class.new(ud), a C++ copy, and the strip's Lua buffer is reused by the next encode (only its
-- changed bands are rewritten). No Vector<integer> constructor is exposed to Lua (type.d.tl:29-37 has no global; the
-- base game only passes engine-made image_native vectors, savegame_react_util.tl:85-95), so
-- data_native can't be built directly. The first image checks the userdata path (copy keeps size +
-- byte count); if anything fails it falls back to the table.
--
-- RE-RENDERS: every render of MinimapContent (a toggle, S/L, a map rebuild) re-renders the canvas
-- and with it this layer (SQPERF 2026-10-09: net_render n = canvas_render n). Each strip is a
-- MinimapNetStrip recipe whose root carries a localKey per strip version and picture size
-- (net.stripKey); a render with an unchanged key returns the old node
-- (react.findOldChildByLocalKey, the base game's construction menu cache,
-- construction.tl:3031-3044), so no ImageView is rebuilt and no pixels are copied. Camera moves
-- never reach this layer (the overlay has its own state).
--
-- DATA (main thread only: react.onStep, never onStepTimer; docs/findings.md "Timers and threads"):
--   * edges: getEntitiesWithComponent(BASE_EDGE) throws "Cannot loop over this component type" in
--     game (2026-10-09, docs/findings.md), so the street system's node maps are used:
--     streetSystem.getNode2StreetEdgeMap / getNode2TrackEdgeMap (engine/system.d.tl:302-304; each
--     edge at both its nodes, de-duplicated). Per new edge: BASE_EDGE (position/tangent 0/1, type:
--     engine.d.tl:99-131); kind from the map; BaseEdgeType.TUNNEL = dashed.
--   * town buildings: townBuildingSystem.getTown2BuildingMap() (engine/system.d.tl:122; base
--     town.tl:432) + BOUNDING_VOLUME bbox (as square_supply_gaps' sg_gather.tl positionOf).
--   The scheduler is minimap_netscan.tl (pure; see its header): three list calls in three frames,
--   everything else sliced to NET_BUDGET_MS per frame (api.type.Clock), changed bands re-encoded,
--   each changed strip's hand-off in a frame of its own, scans backing off while nothing changes.
--
-- IMAGE: NET_LONG px on the long side whatever the S/L size (Stretch-scaled to the picture), so a
-- size change re-mounts the image but never re-rasterises. Same world -> picture mapping as the
-- industry markers (geom.worldToFrac with ORIENT). Pixel format: 4 bytes per pixel, see
-- minimap_net.tl IMAGE DATA; NET_ORDER / NET_FLIP_ROWS are the constants to flip if the in-game
-- calibration patch (NET_CALIBRATE) shows other colours or sits at the bottom.

-- The network layer's private state lives in this do-block: Lua allows 200 locals per function and
-- the main chunk passed that (in game 2026-10-10: "too many local variables"). Only these names
-- are used outside it.
local netState : SquareMinimapNetState = nil
local netNextCheckMs : number = 0   -- no state yet (hidden window): next look
local netFailed = false             -- a Lua error in the step: stopped until toggled off and on
local netRelease : function(why : string)
local netPark : function(why : string)
local netCheckParked : function()
local record NetLayerParam
	box : SquareMinimapBox
	w : integer
	h : integer
end
local MinimapNetLayer : Recipe<NetLayerParam> -- assigned in the block
do
-- Long side of the network image in pixels (S picture 200-360, L 560-720 UI px).
local NET_LONG <const> = 512
local NET_BUDGET_MS <const> = 2.0          -- work per frame (list calls and the hand-off: one per frame)
local NET_HIDDEN_RELEASE_SECONDS <const> = 60.0
local NET_OFF_KEEP_SECONDS <const> = 60.0  -- caches kept after the toggle goes off (instant re-enable)
local NET_RESUME_DELAY_MS <const> = 500.0  -- re-enabled from the kept caches: rescan starts after this
-- Byte order of a pixel ("RGBA", "BGRA", "ARGB" or "ABGR") and whether the first row is the
-- bottom one. Undocumented: NET_CALIBRATE paints red, green, blue and 50% white squares (left to
-- right) at the top-left corner of the map. Red and blue swapped -> "BGRA"; squares at the
-- bottom-left -> NET_FLIP_ROWS = true; wrong colours everywhere -> try "ARGB" / "ABGR".
local NET_ORDER <const> = "RGBA"
local NET_FLIP_ROWS <const> = true -- in game 2026-10-09: the first row is drawn at the bottom
local NET_CALIBRATE <const> = false -- in game 2026-10-09: RGBA confirmed, transparency works
local NET_LOG_UPDATES <const> = 5  -- update passes logged in full per state
-- Colours per layer: net.COLORS_NORMAL / net.COLORS_HIVIS (minimap_net.tl), picked by session.hiVis.

-- Wall clock in ms for the frame budget (api.type.Clock, microseconds: type.d.tl:1860-1866; safe
-- on the main thread, docs/findings.md "Timers and threads in GUI contexts").
local netClockObj : Clock = nil
local netClockTried = false
local function nowMs() : number
	if not netClockTried then
		netClockTried = true
		local ok, cOrErr = pcall(api.type.Clock.new)
		if ok then netClockObj = cOrErr as Clock end
	end
	if netClockObj ~= nil then return netClockObj:getTime() / 1000 end
	return clock() * 1000
end

-- ImageView params userdata (api.gui.react.params.builtin.ImageView; react.lua makeUserdata). Only
-- the fields assigned or read here; the engine class is untyped in the tealdefs.
local record NetParamsUd
	data : {integer}
	size : Vec2i
	scaling : any
	data_native : Vector<integer>
end

local record NetParamsClass
	new : function(...: any) : NetParamsUd
end

local type NetState = SquareMinimapNetState

-- "streetSystem": in game (2026-10-09) getEntitiesWithComponent(BASE_EDGE) throws "Cannot loop over this
-- component type" (docs/findings.md). Set it to nil to re-test the component listing (netListStreets).
local netEdgeMode : string = "streetSystem"
local netRenderSeq = 0              -- bumped on every image change; the layer's re-render trigger

local netHandoff : string = nil      -- image hand-off: nil = not tried yet, "params" (userdata) or "table"

netRelease = function(why : string)
	if netState == nil then return end
	logm(string.format("net: released (%s): %d edges, %d buildings cached", why, netState.edgeCount, netState.buildingCount))
	netState = nil
	netRenderSeq = netRenderSeq + 1
end

--- An engine map as a plain Lua table of arrays (the scheduler resumes it with next()). The maps
--- are expected to be tables already (then returned as is); anything else is copied with pairs.
local function netPlainMap(m : any) : {any : {integer}}
	if m == nil then return nil end
	if type(m) == "table" then
		local _k, v = next(m as {any : any})
		if v == nil or type(v) == "table" then return m as {any : {integer}} end
	end
	local copy : {any : {integer}} = {}
	for k, arr in pairs(m as {any : any}) do
		local ids : {integer} = {}
		for __, e in ipairs(arr as {integer}) do ids[#ids + 1] = e end
		copy[k] = ids
	end
	return copy
end

local function netCallMap(getter : function() : any, what : string) : {any : {integer}}
	local ok, mapOrErr = pcall(getter)
	if not ok or mapOrErr == nil then
		warnOnce("net " .. what, tostring(mapOrErr))
		return nil
	end
	return netPlainMap(mapOrErr)
end

--- Street edges (node -> edges); nil if the listing failed (the scan is then skipped, nothing is removed).
local function netListStreets() : {any : {integer}}
	if netEdgeMode ~= "streetSystem" then
		-- Re-test path only: every edge as one list, kind unknown (read as BASE_EDGE_STREET presence).
		local ok, listOrErr = pcall(api.engine.getEntitiesWithComponent, api.type.ComponentType.BASE_EDGE)
		if ok and listOrErr ~= nil then
			if netEdgeMode == nil then
				netEdgeMode = "component"
				logm("net: edges listed with getEntitiesWithComponent(BASE_EDGE)")
			end
			return { [0] = listOrErr as {integer} }
		end
		netEdgeMode = "streetSystem"
		logm("net: BASE_EDGE can't be listed (" .. tostring(listOrErr) .. "); using the street system's node maps")
	end
	return netCallMap(api.engine.system.streetSystem.getNode2StreetEdgeMap as (function() : any), "street edge map")
end

local function netListTracks() : {any : {integer}}
	if netEdgeMode == "component" then return {} end -- already in the component list
	return netCallMap(api.engine.system.streetSystem.getNode2TrackEdgeMap as (function() : any), "track edge map")
end

local function netListBuildings() : {any : {integer}}
	return netCallMap(api.engine.system.townBuildingSystem.getTown2BuildingMap as (function() : any), "building list")
end

--- One edge -> cached item in image pixels. Throws on API errors (called through pcall).
local function netReadEdgeRaw(st : NetState, e : integer, kind : integer) : SquareMinimapNetItem
	local CT = api.type.ComponentType
	local be = api.engine.getComponent(e, CT.BASE_EDGE) as Engine.Component.BaseEdge
	if be == nil or be.position0 == nil or be.position1 == nil or be.tangent0 == nil or be.tangent1 == nil then
		return { seen = st.stamp, kind = net.KIND_NONE }
	end
	if kind == nil or kind == net.KIND_NONE then
		kind = api.engine.getComponent(e, CT.BASE_EDGE_STREET) ~= nil and net.KIND_STREET or net.KIND_TRACK
	end
	local p0, p1, t0, t1 = be.position0, be.position1, be.tangent0, be.tangent1
	return {
		seen = st.stamp,
		kind = kind,
		dashed = be.type == api.type.enum.BaseEdgeType.TUNNEL,
		pts = net.hermitePolyline(st.xf, p0.x, p0.y, t0.x, t0.y, p1.x, p1.y, t1.x, t1.y),
	}
end

--- One town building -> its bounding box as a pixel rect. Throws on API errors.
local function netReadBuildingRaw(st : NetState, b : integer) : SquareMinimapNetItem
	local bv = api.engine.getComponent(b, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
	if bv == nil or bv.bbox == nil then return { seen = st.stamp, kind = net.KIND_NONE } end
	local mn, mx = bv.bbox.min, bv.bbox.max
	local x0, y0, x1, y1 = net.rectFromBounds(st.xf, mn.x, mn.y, mx.x, mx.y)
	return { seen = st.stamp, kind = net.KIND_TOWN, x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

local function netReadFailed(st : NetState, what : string, err : any) : SquareMinimapNetItem
	st.stats.readFailed = st.stats.readFailed + 1
	warnOnce("net " .. what .. " read", tostring(err))
	return { seen = st.stamp, kind = net.KIND_NONE }
end

local function netReadEdge(st : NetState, e : integer, kind : integer) : SquareMinimapNetItem
	local ok, itOrErr = pcall(netReadEdgeRaw, st, e, kind)
	if ok then return itOrErr as SquareMinimapNetItem end
	return netReadFailed(st, "edge", itOrErr)
end

local function netReadBuilding(st : NetState, b : integer) : SquareMinimapNetItem
	local ok, itOrErr = pcall(netReadBuildingRaw, st, b)
	if ok then return itOrErr as SquareMinimapNetItem end
	return netReadFailed(st, "building", itOrErr)
end

local function netLogPass(st : NetState, published : boolean)
	local s = st.stats
	local wall = nowMs() - s.startMs
	if st.recolor then
		logm(string.format("net: palette %s drawn: encode %.1f ms (%d bands), hand-off %.1f ms (%d strips) over %d frames (%.0f ms wall), no re-read",
			st.hiVis and "hi-vis" or "normal", s.encodeMs, s.bands, s.handoffMs, s.stripsHanded, s.frames, wall))
		return
	end
	if st.passes == 1 and published then
		logm(string.format("net: first build: %d edges (%d streets, %d tracks, %d tunnels, %d without geometry) via %s, %d town buildings (%d without box), %d read failures",
			st.edgeCount, s.streets, s.tracks, s.tunnels, s.noGeom, tostring(netEdgeMode), st.buildingCount, s.noBox, s.readFailed))
		logm(string.format("net: first build took list %.1f ms, flatten %.1f ms, sweep %.1f ms, read %.1f ms, raster %.1f ms, encode %.1f ms (%d bands), hand-off %.1f ms (%s, %d strips) over %d frames (%.0f ms wall); image %dx%d %s%s%s, next scan in %.0f s",
			s.listMs, s.flattenMs, s.sweepMs, s.readMs, s.rasterMs, s.encodeMs, s.bands, s.handoffMs, tostring(netHandoff), s.stripsHanded, s.frames, wall, st.w, st.h, NET_ORDER,
			NET_FLIP_ROWS and " rows flipped" or "", NET_CALIBRATE and ", CALIBRATION patch on" or "", st.scanSeconds))
		return
	end
	if st.updatesLogged >= NET_LOG_UPDATES then return end
	st.updatesLogged = st.updatesLogged + 1
	logm(string.format("net: update %d%s: edges +%d -%d, buildings +%d -%d (now %d / %d); list %.1f ms, flatten %.1f ms, sweep %.1f ms, read %.1f ms, raster %.1f ms, encode %.1f ms (%d bands), hand-off %.1f ms (%d strips), %d frames, next scan in %.0f s%s",
		st.updatesLogged, published and "" or " (no visible change)", #(st.addE or {}), #(st.remE or {}), #(st.addB or {}), #(st.remB or {}), st.edgeCount, st.buildingCount,
		s.listMs, s.flattenMs, s.sweepMs, s.readMs, s.rasterMs, s.encodeMs, s.bands, s.handoffMs, s.stripsHanded, s.frames, st.scanSeconds,
		st.updatesLogged == NET_LOG_UPDATES and " (further updates not logged)" or ""))
end

local function netParamsClass() : NetParamsClass
	local r = (api.gui as {string : any})["react"] as {string : any}
	local p = r ~= nil and r["params"] as {string : any} or nil
	local b = p ~= nil and p["builtin"] as {string : any} or nil
	return b ~= nil and b["ImageView"] as NetParamsClass or nil
end

--- Strip s's finished bytes -> an ImageView params userdata (one Lua -> C++ copy of the strip, see
--- IMAGE HAND-OFF), or nil when that path isn't usable (the strip then keeps its Lua table).
local function netMakeParams(st : NetState, s : integer, out : {integer}, rows : integer) : NetParamsUd
	if netHandoff == "table" then return nil end
	local first = netHandoff == nil
	local ok, udOrErr = pcall(function() : NetParamsUd
		local cls = netParamsClass()
		if cls == nil or cls.new == nil then error("api.gui.react.params.builtin.ImageView not found") end
		-- Two userdata per strip, alternating: the one of the shown version stays untouched until the
		-- publish swaps the staged one in (every mounted ImageView holds its own copy anyway, made by
		-- class.new(ud) at render; a node built in between, e.g. on S/L, still gets the old bytes).
		local ud = (st.spareParams[s] as NetParamsUd) or cls.new()
		st.spareParams[s] = nil
		ud.data = out
		ud.size = api.type.Vec2i.new(st.w, rows)
		ud.scaling = builtin.type.ImageViewScaling.Stretch
		if first then
			-- What a render does with it: react.lua makeUserdata -> class.new(userdata). The copy must
			-- keep the size and every byte, else the engine would show its placeholder image.
			local copy = cls.new(ud)
			if copy == nil or copy.size == nil or copy.size.x ~= st.w or copy.size.y ~= rows then
				error("the params copy lost the size")
			end
			local n = copy.data_native ~= nil and copy.data_native:size() or -1
			if n ~= #out then error(string.format("the params copy holds %d bytes, expected %d", n, #out)) end
		end
		return ud
	end)
	if not ok then
		netHandoff = "table"
		logm("net: image hand-off: Lua table, copied on every new image node (params userdata not usable: " .. tostring(udOrErr) .. ")")
		return nil
	end
	if first then netHandoff = "params" end
	return udOrErr as NetParamsUd
end

--- io.handoff: strip s's finished buffer -> st.staged[s] (not shown until netPublish). False if the
--- buffer is wrong (the strip is encoded whole again next time).
local function netHandoffStrip(st : NetState, s : integer) : boolean
	local t0 = nowMs()
	local tPerf = perfStep:start()
	local out = st.bufs[s]
	local r0, r1 = net.stripRange(st.h, s)
	-- Never hand the engine a buffer of the wrong length (it infers bytes per pixel from it).
	if out == nil or #out ~= net.expectedLength(st.w, r1 - r0) then
		warnOnce("net image", string.format("strip %d buffer has %d values, expected %d; not shown", s,
			out ~= nil and #out or -1, net.expectedLength(st.w, r1 - r0)))
		st.bufs[s] = nil -- start this strip's next encode on a fresh buffer
		perfStep:stop("net_handoff", tPerf)
		return false
	end
	local first = netHandoff == nil
	local strip : SquareMinimapNetStrip = { r0 = r0, r1 = r1 }
	local ud = netMakeParams(st, s, out, r1 - r0)
	if ud ~= nil then
		strip.params = ud -- the bytes live in C++ now: the next encode rewrites only changed bands of out
	else
		strip.data = out -- the image owns the table; the strip's next encode starts a new one
		st.bufs[s] = nil
	end
	st.staged[s] = strip
	perfStep:stop("net_handoff", tPerf)
	local dt = nowMs() - t0
	st.stats.handoffMs = st.stats.handoffMs + dt
	if first and netHandoff == "params" then
		logm(string.format("net: image hand-off: params userdata, checked (one Lua -> C++ copy per changed strip of %d rows: %.1f ms for strip %d incl. the check; new nodes copy it in C++)",
			r1 - r0, dt, s))
	end
	return true
end

--- io.publish: every staged strip -> the shown image (a new version, all strips at once). The
--- strips that didn't change keep their node (same version in their localKey).
local function netPublish(st : NetState) : boolean
	if st.staged == nil or next(st.staged) == nil then return false end
	st.version = st.version + 1
	local old = st.image
	local strips : {SquareMinimapNetStrip} = {}
	for s = 1, st.strips do
		local staged = st.staged[s]
		if staged ~= nil then
			staged.version = st.version
			strips[s] = staged
			local prev = old ~= nil and old.strips[s] or nil
			if prev ~= nil and prev.params ~= nil then st.spareParams[s] = prev.params end
		elseif old ~= nil then
			strips[s] = old.strips[s]
		end
	end
	st.image = { strips = strips, w = st.w, h = st.h, version = st.version, atMs = nowMs() }
	netRenderSeq = netRenderSeq + 1
	return true
end

local netIo : SquareMinimapNetIo = {
	now = nowMs,
	listStreets = netListStreets,
	listTracks = netListTracks,
	listBuildings = netListBuildings,
	readEdge = netReadEdge,
	readBuilding = netReadBuilding,
	handoff = netHandoffStrip,
	publish = netPublish,
	passDone = netLogPass,
	perf = perfStep as SquareMinimapNetPerf,
	flipRows = NET_FLIP_ROWS,
	calibrate = NET_CALIBRATE and function(st : NetState)
		-- Into the top strip (always fully encoded while calibrating), squares sized from the picture.
		local r0, r1 = net.stripRange(st.h, 1)
		if st.bufs[1] ~= nil then
			net.paintCalibration(st.bufs[1], st.w, r1 - r0, NET_ORDER, NET_FLIP_ROWS, math.min(st.w, st.h))
		end
	end or nil,
}

--- Applies session.hiVis to a state: new palette, then re-encode only (net.recolorAction).
local function netApplyPalette(st : NetState, now : number)
	st.hiVis = session.hiVis
	st.palette = net.paletteFor(st.hiVis, NET_ORDER)
	local action = net.recolorAction(st.phase, st.image ~= nil)
	if action == "encode" then
		st.stats = netscan.newStats(now)
		st.recolor = true
		netscan.startEncode(st, true)
	elseif action == "restart" then
		netscan.startEncode(st, true)
	elseif action == "dirty" then
		st.dirty = true -- the pass's encode sees the palette change (startEncode: bufHiVis) and does every band
	end
	perfStep:count("net_recolor")
	logm(string.format("net: palette %s (%s; re-encode only, nothing re-read)", st.hiVis and "hi-vis" or "normal", action))
end

--- Net toggled off: keep image, grid and entity caches for NET_OFF_KEEP_SECONDS (released by
--- netCheckParked), abort a running pass. No layer = no per-frame work.
netPark = function(why : string)
	local st = netState
	if st == nil then return end
	if st.image == nil then
		netRelease(why .. ", nothing drawn yet")
		return
	end
	local now = nowMs()
	if st.phase ~= "idle" then
		-- Items read so far stay cached and drawn (consistent); the next pass re-lists, and dirty
		-- makes it encode.
		if st.phase == "encode" or st.phase == "handoff" then st.dirty = true end -- the shown image is older than the grid
		netscan.endScan(st, now)
	end
	-- The Lua encode buffers (~1 M values, ~16 MB) are KEPT while parked and freed with the rest after
	-- NET_OFF_KEEP_SECONDS. In game (2026-10-10, run 2) dropping them made the first encodes after a
	-- re-enable build fresh 128K-entry tables while the GC swept the old ones: 21-37 ms per pass
	-- instead of 6.7, and a 10.1 ms net_encode step (PERF_REVIEW.md "Run 2").
	st.recolor = false
	st.parkedSinceMs = now
	logm(string.format("net: off (%s): image v%d + %d edges, %d buildings kept for %.0f s (encode buffers kept; %s hand-off)",
		why, st.image.version, st.edgeCount, st.buildingCount, NET_OFF_KEEP_SECONDS, tostring(netHandoff)))
end

--- From the plugin's guard tick: frees parked caches once NET_OFF_KEEP_SECONDS have passed.
netCheckParked = function()
	local st = netState
	if st == nil or st.parkedSinceMs == nil then return end
	if net.parkExpired(st.parkedSinceMs, nowMs(), NET_OFF_KEEP_SECONDS) then
		netRelease(string.format("off for %.0f s", NET_OFF_KEEP_SECONDS))
	end
end

--- The layer's per-frame step (react.onStep, main thread). Returns true when the image changed
--- (published or released). Idle: one Clock read and a comparison per frame.
local function netStep(box : SquareMinimapBox) : boolean
	if netFailed then return false end
	local now = nowMs()
	local st = netState
	if st ~= nil and st.parkedSinceMs ~= nil then
		-- Toggled on again with the caches kept: the layer already rendered the cached image; only an
		-- incremental rescan runs (a pending palette change is drawn by that pass's encode).
		perfStep:count("net_on_cached")
		logm(string.format("net: on (cached image v%d, %.0f s old, off for %.1f s): %d edges, %d buildings kept; incremental rescan in %.1f s, no first build",
			st.image.version, (now - st.image.atMs) / 1000, (now - st.parkedSinceMs) / 1000, st.edgeCount, st.buildingCount,
			NET_RESUME_DELAY_MS / 1000))
		st.parkedSinceMs = nil
		st.hiddenSinceMs = nil
		st.scanSeconds = st.baseSeconds -- back-off reset on toggle-on
		netscan.startScan(st, now)
		-- Not in the frames right after the toggle (render + mount): the list calls wait a moment.
		st.waitUntilMs = now + NET_RESUME_DELAY_MS
		return false
	end
	if st == nil then
		if now < netNextCheckMs then return false end
	elseif now < st.waitUntilMs then
		return false
	end
	if not isShown() then
		-- Paused: no engine reads. Look again in a second; a long-hidden window frees the caches.
		netNextCheckMs = now + 1000
		if st ~= nil then
			st.waitUntilMs = now + 1000
			if st.hiddenSinceMs == nil then st.hiddenSinceMs = now end
			if now - st.hiddenSinceMs >= NET_HIDDEN_RELEASE_SECONDS * 1000 then
				netRelease(string.format("window hidden for %.0f s", NET_HIDDEN_RELEASE_SECONDS))
				return true
			end
		end
		return false
	end
	if st ~= nil and (st.minX ~= box.minX or st.minY ~= box.minY or st.maxX ~= box.maxX or st.maxY ~= box.maxY) then
		netRelease("map extent changed")
		st = nil
	end
	if st == nil then
		local t0 = nowMs()
		local tPerf = perfStep:start()
		st = netscan.newState(box, ORIENT, NET_LONG, session.hiVis, NET_ORDER)
		perfStep:stop("net_grid", tPerf)
		netState = st
		perfStep:count("net_on_cold")
		logm(string.format("net: on (cold): image %dx%d px in %d strips (%s%s, %s), grid in %.1f ms; budget %.1f ms/frame, scan every %.0f s or more (up to %.0f s while nothing changes)%s",
			st.w, st.h, st.strips, NET_ORDER, NET_FLIP_ROWS and ", rows flipped" or "", st.hiVis and "hi-vis" or "normal palette", nowMs() - t0, NET_BUDGET_MS,
			netscan.SCAN_SECONDS, netscan.BACKOFF_MAX_SECONDS,
			NET_CALIBRATE and "; CALIBRATION patch on: expect red, green, blue, half-white squares at the map's top-left" or ""))
		return false -- the grid allocation was this frame's work
	end
	if st.hiddenSinceMs ~= nil then
		-- Shown again after a pause: scan now, from the base interval.
		st.hiddenSinceMs = nil
		st.scanSeconds = st.baseSeconds
	end
	st.waitUntilMs = 0
	if st.hiVis ~= session.hiVis then netApplyPalette(st, now) end
	if st.phase == "idle" then netscan.startScan(st, now) end
	return netscan.run(st, netIo, NET_BUDGET_MS)
end

local findOldChild = (react as {string : any})["findOldChildByLocalKey"] as function(string) : TreeNodeId

--- The params userdata path failed at render: from now on every strip is a Lua table. Every strip
--- is encoded again (whole, into new buffers) and handed off as a table.
local function netParamsFailed(err : any)
	if netHandoff == "table" then return end
	warnOnce("net image params", tostring(err))
	netHandoff = "table"
	local st = netState
	if st == nil then return end
	st.bufs, st.spareParams = {}, {}
	for s = 1, st.strips do st.pending[s] = true end
	-- The shown strips' userdata can't be drawn: show nothing until the table image is published.
	if st.image ~= nil then
		for _, strip in ipairs(st.image.strips) do strip.params = nil end
	end
	if st.parkedSinceMs == nil and net.recolorAction(st.phase, true) == "encode" then
		st.stats = netscan.newStats(nowMs())
		st.recolor = true
		netscan.startEncode(st, true)
		st.waitUntilMs = 0
	else
		st.dirty = true
	end
end

local record NetStripParam
	strip : SquareMinimapNetStrip
	key : string   -- net.stripKey: strip, its version, picture size, mode
	imageW : integer
	w : integer    -- UI px
	h : integer
end

-- One strip of the network image (net STRIPS), its own recipe so the reuse below works at a
-- recipe root exactly like the base game's (construction.tl:3031-3044): while the strip's version
-- and the picture size are unchanged, the old node is returned (no ImageView, no pixel copy). A
-- 1-strip update therefore builds 1 ImageView; the other strips are untouched.
local MinimapNetStrip = react.RegisterRecipe("MinimapNetStrip", perf:wrap("net_render_strip", function(params : NetStripParam) : TreeNodeId
	react.setMouseTransparent(true)
	if findOldChild ~= nil then
		local old = findOldChild(params.key)
		if old ~= nil then
			perf:count("net_render_reused")
			return old
		end
	end
	local tPerf = perf:start()
	local strip = params.strip
	local node : TreeNodeId = nil
	if strip.params ~= nil then
		-- Userdata hand-off (IMAGE HAND-OFF): makeUserdata copies the params in C++. meta can't ride
		-- on a userdata, so the size goes on a WithComponentParams wrapper (what react.lua does with
		-- meta.styleSheet itself, react.lua:362-373; base use: entity_window_util.tl:404).
		local ud = strip.params as NetParamsUd
		local ok, nodeOrErr = pcall(function() : TreeNodeId
			return builtin.ImageView(ud as Builtin.ImageViewParam)
		end)
		if ok then
			node = builtin.WithComponentParams{
				styleSheet = styleutil.makeStyle{ size = { params.w, params.h } },
				item = nodeOrErr as TreeNodeId,
			}
		else
			netParamsFailed(nodeOrErr)
		end
	elseif strip.data ~= nil then
		node = builtin.ImageView{
			meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
			data = strip.data,
			size = api.type.Vec2i.new(params.imageW, strip.r1 - strip.r0),
			scaling = builtin.type.ImageViewScaling.Stretch,
			-- no mouseTransparent: ImageView has no such field; layerAt's Component is mouse-transparent
		}
	end
	perf:count("net_render_built")
	perf:stop("net_render_img", tPerf)
	return builtin.BoxLayout{
		meta = { class = boxClass(nil), localKey = params.key },
		orientation = builtin.type.Orientation.Vertical,
		children = { node },
	}
end))

-- Mounted only while the Net toggle is on (MinimapCanvas). Re-mounted with the preview (gen/size
-- key) to stay above it; the caches live in netState, so a re-mount never re-reads or re-draws.
-- Builds a few small layout nodes per render; the strips' ImageViews only when their version or
-- the picture size changed (MinimapNetStrip).
MinimapNetLayer = react.RegisterRecipe("MinimapNetLayer", perf:wrap("net_render", function(params : NetLayerParam) : TreeNodeId
	local paramsRef = react.useRef(params) as ReactRefT<NetLayerParam>
	paramsRef:set(params)
	local seqState = react.useState(netRenderSeq) as ReactStateT<integer>
	react.onStep(function()
		local ok, changedOrErr = pcall(netStep, paramsRef:get().box)
		if not ok then
			warnOnce("net step", tostring(changedOrErr))
			netFailed = true
			netRelease("error")
		end
		if seqState:old() ~= netRenderSeq then seqState:set(netRenderSeq) end
	end)
	local tPerf = perf:start()
	local img = netState ~= nil and netState.image or nil
	local children : {TreeNodeId} = {}
	if img ~= nil then
		-- Strip s at rows r0 .. r1 - 1 of the image, stretched to its share of the picture: rounded
		-- edges, so the strips tile it without gaps (net.stripPlacement; a seam is <= 0.5 px off).
		for s = 1, #img.strips do
			local strip = img.strips[s]
			if strip ~= nil and (strip.params ~= nil or strip.data ~= nil) then
				local top, hpx = net.stripPlacement(strip.r0, strip.r1, img.h, params.h)
				if hpx > 0 then
					local key = net.stripKey(s, strip.version, params.w, params.h, strip.params ~= nil and "params" or "table")
					-- New key per strip version: a changed strip is created with its data, never updated in place.
					children[#children + 1] = layerAt("flc_" .. key, 0, top, params.w, hpx, params.w, params.h,
						MinimapNetStrip{ strip = strip, key = key, imageW = img.w, w = params.w, h = hpx })
				end
			end
		end
	end
	local root = builtin.BoxLayout{
		meta = { class = boxClass(nil), localKey = string.format("minimap_net_%dx%d", params.w, params.h) },
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
				mouseTransparent = true,
				layout = builtin.FloatingLayout{
					children = children,
				},
			},
		},
	}
	perf:stop("net_render_tree", tPerf)
	return root
end))
end -- network layer block

---------------------------------------------------------------------------
-- Mod settings (mod.json "params", chosen in the mod selection when a game is started or loaded;
-- docs/wiki/modding/general/modscripts.md). getModParams() (engine.d.tl:1806-1807) gives each
-- param as the 1-based index of the chosen value (community GUI scripts read it the same way,
-- e.g. zhenya_doubleclick_to_edit dce.script.lua:75). Params only change on a game load, so read once.

local MOD_ID <const> = "square_better_minimap"
local showArrowCache : boolean = nil

--- This mod's raw mod.json param value (1-based option index), nil if missing or unreadable.
local function modParam(key : string) : number
	local ok, allOrErr = pcall(api.engine.config.getModParams)
	if not ok then
		warnOnce("mod params", tostring(allOrErr))
		return nil
	end
	local all = allOrErr as {string : table}
	local mine = all ~= nil and all[MOD_ID] as {string : number} or nil
	return mine ~= nil and mine[key] or nil
end

--- mod.json showArrow: values { "On", "Off" } -> 1 = on. Missing/unreadable (older saves, errors) = on.
local function showArrowSetting() : boolean
	if showArrowCache ~= nil then return showArrowCache end
	local v = modParam("showArrow")
	showArrowCache = v ~= 2
	logm(string.format("setting: showArrow=%s (raw %s)", tostring(showArrowCache), tostring(v)))
	return showArrowCache
end

---------------------------------------------------------------------------
-- Camera overlay

local record OverlayParam
	box : SquareMinimapBox
	w : integer
	h : integer
end

local overlayUpdatesLogged = 0 -- first few box moves per overlay mount, for the in-game test

local MinimapOverlay = react.RegisterRecipe("MinimapOverlay", perf:wrap("overlay_render", function(params : OverlayParam) : TreeNodeId
	-- The poll reads the latest params through a ref (the step closure is created once).
	local paramsRef = react.useRef(params) as ReactRefT<OverlayParam>
	paramsRef:set(params)
	local camState = react.useState(nil) as ReactStateT<SquareMinimapCamPx>
	local camDue = useMainThreadTick(CAM_POLL_SECONDS)
	local mountedRef = react.useRef(false) as ReactRefT<boolean>
	if not mountedRef:get() then
		mountedRef:set(true)
		overlayUpdatesLogged = 0
		loggedFootprint = false
		logm(string.format("camera overlay mount (%dx%d px)", params.w, params.h))
	end

	react.onStep(function()
		if not camDue() then return end
		if not isShown() then return end -- hidden window: no camera reads
		local p = paramsRef:get()
		local tPerf = perfStep:start()
		local ok, vOrErr = pcall(readCamView, p.box)
		perfStep:stop("cam_read", tPerf)
		if not ok then
			warnOnce("readCamView", tostring(vOrErr))
			return
		end
		local v = vOrErr as CamView
		local px = geom.camPx(v.rect, v.cx, v.cy, p.w, p.h, CAM_BOX_MIN_PX)
		if v.hx ~= nil and v.hy ~= nil and showArrowSetting() then
			-- fraction -> pixel space (w, h scale the axes differently on non-square pictures)
			px.arrowDeg = geom.headingDegrees(v.hx * p.w, v.hy * p.h)
		end
		-- Only re-render when a marker moved by a whole pixel (or the picture was resized).
		if not geom.sameCamPx(px, camState:old()) then
			if overlayUpdatesLogged < 3 then
				overlayUpdatesLogged = overlayUpdatesLogged + 1
				logm(string.format("camera box -> %d,%d %dx%d (map %dx%d)", px.boxCX, px.boxCY, px.boxW, px.boxH, p.w, p.h))
			end
			camState:set(px)
			perfStep:count("cam_moves")
		end
	end)
	react.setMouseTransparent(true)

	local cam = camState:old()
	local children : {TreeNodeId} = {}
	if cam ~= nil then
		-- Keys change with the pixel position: a FloatingLayoutChild whose h/v change in place
		-- isn't re-laid out (in game the box stayed put after a jump), so each move re-mounts it.
		local posKey = string.format("%d_%d_%d_%d_%d_%d", cam.boxCX, cam.boxCY, cam.boxW, cam.boxH, cam.dotX, cam.dotY)
		-- Top-left corner at (left, top), clipped to the picture (layerAt: padding placement).
		local bl, bt, bw, bh = geom.clipBox(cam.boxCX, cam.boxCY, cam.boxW, cam.boxH, params.w, params.h)
		if bw > 0 and bh > 0 then
			children[#children + 1] = layerAt("minimap_cam_box_" .. posKey, bl, bt, bw, bh, params.w, params.h, builtin.Component{
				meta = {
					class = "minimap-cam-box",
					-- Hollow rectangle, styled inline (no stylesheet rule; mod rules are capped).
					styleSheet = styleutil.makeStyle{
						size = { bw, bh },
						borderWidth = { 2, 2, 2, 2 },
						borderColor = colors().Warning,
						backgroundColor = colors().Invisible,
					},
				},
				mouseTransparent = true,
			})
		end
		-- View direction arrow centred on the box centre (kept inside the picture), turned to the
		-- heading. Re-mounted per position/angle like the box (key), not updated in place.
		if cam.arrowDeg ~= nil and params.w >= ARROW_PX and params.h >= ARROW_PX then
			local al = math.max(0, math.min(params.w - ARROW_PX, cam.boxCX - ARROW_PX // 2))
			local at = math.max(0, math.min(params.h - ARROW_PX, cam.boxCY - ARROW_PX // 2))
			children[#children + 1] = layerAt(string.format("minimap_cam_arrow_%d_%d_%d", al, at, cam.arrowDeg),
				al, at, ARROW_PX, ARROW_PX, params.w, params.h, builtin.ImageView{
				meta = {
					class = "minimap-cam-arrow",
					-- White, untinted (its dark halo is baked into the icon).
					styleSheet = styleutil.makeStyle{ size = { ARROW_PX, ARROW_PX }, color = colors().NeutralLightest },
				},
				path = ARROW_ICON,
				scaling = builtin.type.ImageViewScaling.AutoFit, -- 16 UI px icon (32 px @2x) at ARROW_PX: 1:1
				-- no mouseTransparent: ImageView has no such field (crashes in makeUserdata); the
				-- layerAt wrapper Component is already mouse-transparent
				rotation = ARROW_ROT_SIGN * cam.arrowDeg,
			})
		end
	end
	-- Sized, mouse-transparent Component around the markers (CargoLifetimeMarkers pattern). Its
	-- layout is a builtin FloatingLayout, never a custom recipe (that crashes the game).
	return hbox({
		builtin.Component{
			meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
			mouseTransparent = true,
			layout = builtin.FloatingLayout{
				children = children,
			},
		},
	})
end))

---------------------------------------------------------------------------
-- Canvas: preview + overlay + click-to-jump

local record CanvasParam
	data : MapData
	w : integer
	h : integer
	markerSize : integer
	showIndustries : boolean
	showNet : boolean
	bandW : integer -- width of the band the picture is centred in (= w unless a strip is narrower than MIN_WIDTHS)
	filterSeq : integer -- passed on to the markers (re-render on a filter change)
end

local lastWindowFracW : number = 0 -- 0 = unknown; window content width (screen fraction) from the position poll; fit log

-- WINDOW POSITION. getPosition() on the Window (the wrapper recipe's self ref) returned 0,0-0,0 in
-- game, so nothing was ever remembered. Base code reads window-relative positions from a node inside
-- the window instead (content_card.useShowCalloutOnRight(refSelf), town.tl:1178), so the content
-- root is read here, and the window anchor = content top-right + an offset (window frame and title
-- bar). The offset is measured once per window: right after creation, before any move, the anchor
-- is the initialX/Y we passed (requestedX/Y), so offset = requested - content top-right.
local requestedX : number = nil -- initialX/Y of the current window
local requestedY : number = nil
local anchorDX : number = nil   -- window anchor minus content top-right (screen fractions); nil = not measured
local anchorDY : number = nil
local windowMoved = false       -- moved since creation (offset can no longer be measured)

local MinimapCanvas = react.RegisterRecipe("MinimapCanvas", perf:wrap("canvas_render", function(params : CanvasParam) : TreeNodeId
	local selfRef = react.useSelfRef()
	local pressedRef = react.useRef(false) as ReactRefT<boolean>
	local paramsRef = react.useRef(params) as ReactRefT<CanvasParam>
	paramsRef:set(params)
	local fitDue = useMainThreadTick(FIT_POLL_SECONDS)
	local fitLoggedRef = react.useRef("") as ReactRefT<string>

	-- Fit check (log only): picture width vs window width, both in screen fractions. A window
	-- clearly wider than the picture means an empty band (MIN_WIDTHS too small).
	react.onStep(function()
		if not fitDue() then return end
		if not isShown() then return end
		local tPerf = perfStep:start()
		local ok, err = pcall(function() : any
			local node = selfRef:get()
			if node == nil then return nil end
			local p0 = node:getPosition(0, 0)
			local p1 = node:getPosition(1, 1)
			local screen = api.gui.camera.getSize()
			local l, t = geom.normalizeScreenPos(p0.x, p0.y, screen.x, screen.y)
			local r, b = geom.normalizeScreenPos(p1.x, p1.y, screen.x, screen.y)
			local p = paramsRef:get()
			local winW = lastWindowFracW
			if winW <= 0 then return nil end
			local gap = winW - (r - l)
			local key = string.format("%d_%d_%.3f", p.w, p.h, gap)
			if key == fitLoggedRef:get() then return nil end
			fitLoggedRef:set(key)
			local gapPx = (r - l) > 0 and gap / (r - l) * p.w or 0
			-- The band of a narrow strip (bandW - w) is intended, not an empty band.
			local bandPx = (p.bandW or p.w) - p.w
			logm(string.format("fit: picture %dx%d px = %.4f x %.4f screen, window width %.4f, extra width %.4f (~%.0f UI px, band %d)%s",
				p.w, p.h, r - l, b - t, winW, gap, gapPx, bandPx, gapPx - bandPx > 12 and " -> EMPTY BAND, raise MIN_WIDTHS" or ""))
			return nil
		end)
		perfStep:stop("fit_poll", tPerf)
		if not ok then warnOnce("fit check", tostring(err)) end
	end)

	--- Event position -> picture fraction (throws on API errors; GUI thread).
	local function eventFrac(ex : integer, ey : integer) : number, number
		local node = selfRef:get()
		local p0 = node:getPosition(0, 0)
		local p1 = node:getPosition(1, 1)
		local screen = api.gui.camera.getSize()
		local fx, fy = geom.eventToFrac(ex, ey, p0.x, p0.y, p1.x, p1.y, screen.x, screen.y)
		return fx, fy
	end

	--- The industry marker drawn at a picture fraction (filtered-out ones don't count), or nil.
	local function markerAtFrac(fx : number, fy : number) : SquareMinimapMarkerPx
		local p = paramsRef:get()
		if shownMarkers == nil or not p.showIndustries then return nil end
		local sel = session.filter
		return geom.hitMarker(shownMarkers, fx * p.w, fy * p.h, shownMarkerSize, HIT_TOL_PX,
			function(m : SquareMinimapMarkerPx) : boolean return filter.isVisible(m.typeKey, sel) end)
	end

	local function clickAt(ex : integer, ey : integer)
		local p = paramsRef:get()
		if p.data == nil then return end
		-- Shift+click with industries on (phase 7): filter, never jump.
		local shift = p.showIndustries and shiftHeld()
		local tPerf = perf:start() -- onMouseEvent: GUI thread
		local ok, err = pcall(function() : any
			local fx, fy = eventFrac(ex, ey)
			if fx < -0.05 or fx > 1.05 or fy < -0.05 or fy > 1.05 then
				return nil
			end
			if shift then
				local m = markerAtFrac(fx, fy)
				local sel, action = filter.shiftClick(session.filter, m ~= nil and m.typeKey or nil)
				local why : string
				if action == "only" then
					why = "shift+click on " .. m.typeKey
				elseif m ~= nil then
					why = "shift+click on the only filtered type"
				else
					why = "shift+click on an empty spot"
				end
				setFilter(sel, why)
				return nil
			end
			local wx, wy = geom.fracToWorld(geom.clamp(fx, 0, 1), geom.clamp(fy, 0, 1), p.data.box, ORIENT)
			jumpTo(wx, wy)
			return nil
		end)
		perf:stop(shift and "click_filter" or "click_jump", tPerf)
		if not ok then
			warnOnce("click", tostring(err))
		end
	end

	-- SHIFT HOVER (phase 7): the pointer over the canvas (event pixels; nil = not over it) and the
	-- last Shift state. Moved/Entered/Exited events update the pointer; the step below polls Shift
	-- only while the pointer is over the canvas, industries are on and the window is shown, so
	-- pressing or releasing Shift without moving the mouse also updates the preview. The hovered
	-- type goes to the markers layer only (markersHoverFn): nothing else re-renders.
	local pointerRef = react.useRef(nil) as ReactRefT<{integer}>
	local shiftRef = react.useRef(false) as ReactRefT<boolean>

	local function updateHover()
		local fn = markersHoverFn
		if fn == nil then return end
		local pt = pointerRef:get()
		local typeKey : string = nil
		if pt ~= nil and shiftRef:get() and paramsRef:get().showIndustries then
			local tPerf = perf:start()
			local ok, kOrErr = pcall(function() : string
				local fx, fy = eventFrac(pt[1], pt[2])
				local m = markerAtFrac(fx, fy)
				return m ~= nil and m.typeKey or nil
			end)
			perf:stop("hover_hit", tPerf)
			if ok then
				typeKey = kOrErr as string
			else
				warnOnce("hover", tostring(kOrErr))
			end
		end
		fn(typeKey)
	end

	react.onStep(function()
		if pointerRef:get() == nil then return end -- not over the canvas: nothing polled
		local tPerf = perfStep:start()
		if not paramsRef:get().showIndustries or not isShown() then
			pointerRef:set(nil)
			shiftRef:set(false)
			if markersHoverFn ~= nil then markersHoverFn(nil) end
		else
			local shift = shiftHeld()
			if shift ~= shiftRef:get() then
				shiftRef:set(shift)
				perfStep:count("shift_changes")
				updateHover()
			end
		end
		perfStep:stop("shift_poll", tPerf)
	end)

	react.setMouseTransparent(false)
	react.onMouseEvent(function(evt : Gui.Mouse.Event) : boolean
		local T = api.gui.mouse.Event.Type
		if evt.type == T.Moved or evt.type == T.Entered then
			if paramsRef:get().showIndustries then
				local node = selfRef:get()
				local hadShift = shiftRef:get()
				if node ~= nil and node:containsPosition(api.type.Vec2i.new(evt.x, evt.y)) then
					pointerRef:set({ evt.x, evt.y })
					shiftRef:set(shiftHeld())
				else
					pointerRef:set(nil)
				end
				-- Without Shift (before and now) a move costs only the Shift read above.
				if hadShift or shiftRef:get() or pointerRef:get() == nil then updateHover() end
			end
			return false
		elseif evt.type == T.Exited then
			if pointerRef:get() ~= nil then
				pointerRef:set(nil)
				updateHover()
			end
			return false
		end
		if evt.button ~= 0 then return false end
		if evt.type ~= T.Pressed and evt.type ~= T.Released and evt.type ~= T.Clicked then
			return false
		end
		local node = selfRef:get()
		if node == nil then return false end
		local inside = node:containsPosition(api.type.Vec2i.new(evt.x, evt.y))
		if evt.type == T.Pressed then
			if inside then
				pressedRef:set(true)
				return true
			end
		elseif evt.type == T.Released then
			if pressedRef:get() then
				pressedRef:set(false)
				if inside then clickAt(evt.x, evt.y) end
				return true
			end
		elseif evt.type == T.Clicked then
			return inside
		end
		return false
	end)

	local gen = params.data ~= nil and params.data.gen or 0
	local children : {TreeNodeId} = {
		builtin.FloatingLayoutChild{
			h = 0,
			v = 0,
			-- New localKey per map generation / size: the preview re-mounts with the new map.
			localKey = "minimap_preview_" .. tostring(gen) .. "_" .. tostring(params.w),
			-- A custom recipe can't be a Component's layout ("Item of Component must be a layout");
			-- like finances_cargo_lifetime.tl:297-305 it goes straight into the child's item.
			item = MinimapPreview{ data = params.data, w = params.w, h = params.h },
		},
	}
	if params.data ~= nil and params.showNet then
		-- Network layer over the preview, under the industry icons. Same re-mount key scheme as the
		-- markers (a fixed key would leave it below a re-mounted preview); nothing is re-drawn.
		children[#children + 1] = builtin.FloatingLayoutChild{
			h = -1,
			v = -1,
			localKey = "minimap_net_" .. tostring(gen) .. "_" .. tostring(params.w),
			item = MinimapNetLayer{ box = params.data.box, w = params.w, h = params.h },
		}
	end
	if params.data ~= nil and params.data.industries ~= nil and params.showIndustries then
		-- Between the preview and the camera overlay; re-mounted with them (same key scheme).
		children[#children + 1] = builtin.FloatingLayoutChild{
			h = -1,
			v = -1,
			localKey = "minimap_markers_" .. tostring(gen) .. "_" .. tostring(params.w) .. "_" .. tostring(params.markerSize),
			item = MinimapMarkers{ data = params.data, w = params.w, h = params.h, size = params.markerSize, filterSeq = params.filterSeq },
		}
	end
	if params.data ~= nil then
		children[#children + 1] = builtin.FloatingLayoutChild{
			h = -1,
			v = -1,
			-- Re-mounted with the preview (same gen/size key) so it stays above the new preview;
			-- with a fixed key the box vanished after an Assets rebuild.
			localKey = "minimap_overlay_" .. tostring(gen) .. "_" .. tostring(params.w),
			item = MinimapOverlay{ box = params.data.box, w = params.w, h = params.h },
		}
	end
	return builtin.FloatingLayout{
		children = children,
	}
end))

---------------------------------------------------------------------------
-- Window content

local function checkBox(label : string, tooltip : string, value : boolean, onChange : function(boolean), enabled ?: boolean) : TreeNodeId
	return builtin.CheckBox{
		meta = { tooltip = tooltip, enabled = enabled ~= false },
		value = value and 1 or 0,
		label = label,
		onValueChange = function(v : integer) onChange(v == 1) end,
	}
end

-- The size toggle lives in MinimapContent's state; the button may render in the window header
-- (another recipe), so MinimapContent publishes its handler here on every render.
local cycleSizeFn : function()

-- The button stays at the left of the header. Right-aligning it next to the pin failed in game
-- (2026-10-10): CSS gravity -1 on the header root and an explicit root width (picture width - 56)
-- both left it at the left; the header container has no stylesheet name to target.

--- The size toggle button, as its own recipe so one stylesheet rule sizes it in the header or in
--- the control row. Root is a BoxLayout (a custom recipe must return a layout).
local MinimapSizeButton = react.RegisterRecipe("MinimapSizeButton", function() : TreeNodeId
	return hbox({
		builtin.Button{
			meta = { class = "minimap-size-button", tooltip = _("Toggle the map size: small / large") },
			content = builtin.ImageView{ meta = { class = "minimap-size-icon", styleSheet = icon24Style() }, path = SIZE_ICON },
			onClick = function()
				if cycleSizeFn ~= nil then cycleSizeFn() end
			end,
		},
	})
end)

---------------------------------------------------------------------------
-- Industry filter window (phase 7): a small movable window of its own (like Industry Flows' panel,
-- mods/square_industry_flows/content/industry_flows/gui/flows_window.script.tl): search field,
-- "Show all", one checkbox row per industry type on the map with its cargo icons (inputs > outputs)
-- and its count. Same selection as Shift+click on the map (setFilter). Opened and closed with the
-- "Filter" checkbox; added once with addSingletonWindow (like the minimap: builtin.d.tl:1216-1232) and
-- then only hidden/shown by id, so it keeps the place the player dragged it to. Closed when the
-- minimap hides or Ind is switched off; reopening the minimap doesn't reopen it.

local filterWindowMounted = false
local filterWindowListener : function(boolean) = nil -- MinimapContent's "Filter" checkbox state

local function filterWindowChanged(open : boolean)
	if filterWindowListener ~= nil then filterWindowListener(open) end
end

local function isFilterShown() : boolean
	if not filterWindowMounted then return false end
	local ok, vOrErr = pcall(api.gui.byId.isVisible, FILTER_WINDOW_ID)
	return ok and vOrErr == true
end

local function setFilterWindowVisible(visible : boolean) : boolean, any
	return pcall(function() : any
		api.gui.byId.setVisible(FILTER_WINDOW_ID, visible)
		return nil
	end)
end

local record FilterWindowParam
	onClose : function()
	initialX : number -- top-right anchor (CSS anchorPoint {1, 0}), screen fractions, as the minimap
	initialY : number
end

local MinimapFilterWindow : Recipe<FilterWindowParam> -- assigned below

local function closeFilterWindow(why : string)
	-- The checkbox unchecks even when the window is already gone (its X may hide it before onClose).
	filterWindowChanged(false)
	if not isFilterShown() then return end
	local ok, err = setFilterWindowVisible(false)
	if not ok then
		warnOnce("hide filter window", tostring(err))
		local wa = game_react_globals.getDefaultWindowApi()
		if wa ~= nil then wa.removeAllWindows(MinimapFilterWindow) end
	end
	logm("filter window closed (" .. why .. ")")
end

--- Where a new filter window goes: left of the minimap (top edges level), or right of it when
--- there is no room on the left. Estimates (FILTER_WINDOW_FRAC_W); see TESTING.md P7.
local function filterWindowAnchor() : number, number
	local mx, my = session.posX, session.posY
	if mx == nil then mx, my = DEFAULT_ANCHOR_X, DEFAULT_ANCHOR_Y end
	local mw = lastWindowFracW > 0 and lastWindowFracW or 0.2
	local gap = 0.004
	local x = mx - mw - gap
	if x - FILTER_WINDOW_FRAC_W < 0 then
		x = math.min(1.0, mx + FILTER_WINDOW_FRAC_W + gap)
	end
	return x, math.max(WINDOW_MIN_TOP, my)
end

local function openFilterWindow()
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		warnOnce("filter window", "no window container")
		return
	end
	if filterWindowMounted then
		local ok, err = setFilterWindowVisible(true)
		if not ok then warnOnce("show filter window", tostring(err)) end
		wa.moveSingletonWindowToFront(MinimapFilterWindow)
		filterWindowChanged(true)
		logm("filter window shown again")
		return
	end
	local x, y = filterWindowAnchor()
	logm(string.format("filter window opened at anchor %.4f,%.4f", x, y))
	wa.addSingletonWindow(MinimapFilterWindow, {
		onClose = function() closeFilterWindow("closed") end,
		initialX = x,
		initialY = y,
	})
	filterWindowMounted = true -- also set by onMount; set here so a quick second click hides, not re-adds
	wa.moveSingletonWindowToFront(MinimapFilterWindow)
	filterWindowChanged(true)
end

--- The "Filter" checkbox (GUI thread).
local setFilterWindowOpen = perf:wrap("click_filter_box", function(open : boolean)
	if not open then
		closeFilterWindow("Filter box")
	elseif not isFilterShown() then
		openFilterWindow()
	end
end) as function(boolean)

--- Cargo icon as cargo_react_util.makeIcon(class, cargoType.icon, cargoType.name) (cargo_react_util.tl:15-24),
--- from this file's cargo caches (filled by the industry read).
local function filterCargoIcon(c : integer) : TreeNodeId
	local path = cargoIcon(c)
	return builtin.ImageView{
		meta = { class = "text-icon-size-hack, minimap-filter-cargo", tooltip = cargoNameCache[c] },
		path = path ~= "" and path or FALLBACK_ICON,
	}
end

--- Inputs, a chevron, outputs (Industry Flows' cargoIcons).
local function filterCargoIcons(t : SquareMinimapFilterType) : TreeNodeId
	local icons : {TreeNodeId} = {}
	for __, c in ipairs(t.inputs) do icons[#icons + 1] = filterCargoIcon(c) end
	if #t.inputs > 0 and #t.outputs > 0 then
		-- Shares the cargo icons' class (gravity rule); its 10 px size inline.
		icons[#icons + 1] = builtin.ImageView{
			meta = { class = "minimap-filter-cargo, minimap-filter-cargo-arrow", styleSheet = styleutil.makeStyle{ size = { 10, 10 } } },
			path = CARGO_ARROW_ICON,
		}
	end
	for __, c in ipairs(t.outputs) do icons[#icons + 1] = filterCargoIcon(c) end
	return hbox(icons, "minimap-filter-cargos")
end

-- Name budget of a type row (the label does not shrink: a long game-translated name ran into the cargo
-- icons in Russian, 2026-10-10 screenshot). From that screenshot: list content ~274 px (284 minus the
-- scroll bar), box + gap ~22, cargo icon ~20 with spacing, arrow ~12, count ~8 per digit, 2 x 6 row
-- spacing, ~7.5 px per letter (31 Cyrillic letters ~225 px). Cut names get "..." and the full name as tooltip.
local FILTER_ROW_PX <const> = 274 - 22 - 2 * 6
local FILTER_ICON_PX <const> = 20
local FILTER_ARROW_PX <const> = 12
local FILTER_DIGIT_PX <const> = 8

local function filterNameUnits(t : SquareMinimapFilterType) : integer
	local px = FILTER_ROW_PX - FILTER_ICON_PX * (#t.inputs + #t.outputs) - FILTER_DIGIT_PX * #tostring(t.count)
	if #t.inputs > 0 and #t.outputs > 0 then px = px - FILTER_ARROW_PX end
	return math.max(8, math.floor(px * 2 / 15))
end

--- One type row (Industry Flows' typeRow): controlled CheckBox labelled with the name (builtin.d.tl:1024-1031),
--- cargo icons, the count on the map.
local function filterTypeRow(t : SquareMinimapFilterType, selected : boolean, onToggle : function(string)) : TreeNodeId
	local label, cut = geom.fitText(t.name, filterNameUnits(t))
	return hbox({
		builtin.CheckBox{
			meta = { class = "minimap-filter-check", tooltip = cut and t.name or nil },
			value = selected and 1 or 0,
			onValueChange = function(__ : integer)
				onToggle(t.key)
			end,
			label = label,
		},
		filterCargoIcons(t),
		text(tostring(t.count), "font-scale-body, minimap-filter-count"),
	}, "minimap-filter-row, minimap-filter-fill")
end

local MinimapFilterContent = react.RegisterRecipe("MinimapFilterContent", perf:wrap("filter_render", function() : TreeNodeId
	local seqState = react.useState(filterSeq) as ReactStateT<integer>
	local queryState = react.useState(session.filterQuery) as ReactStateT<string>
	local genState = react.useState(shownData ~= nil and shownData.gen or 0) as ReactStateT<integer>
	filterListeners.window = function(seq : integer)
		if seqState:old() ~= seq then seqState:set(seq) end
	end
	react.onUnmount(function()
		filterListeners.window = nil
	end)
	-- A map rebuild (new industries) re-renders the list: one integer comparison per frame.
	react.onStep(function()
		local g = shownData ~= nil and shownData.gen or 0
		if genState:old() ~= g then genState:set(g) end
	end)

	local function withQuery(q : string)
		if q == nil or q == queryState:old() then return end
		session.filterQuery = q
		queryState:set(q)
	end
	local function toggleType(key : string)
		setFilter(filter.toggle(session.filter, key), "window toggle " .. key)
	end

	local sel = session.filter
	local types = typesFor(shownData)
	local query = queryState:old()
	local rows : {TreeNodeId} = {}

	-- Search: base search field as Industry Flows (statistics_react_util.tl:167-183: value + onTyping + onValueChange).
	rows[#rows + 1] = builtin.TextInputField{
		meta = { class = "font-scale-body, search, minimap-filter-search, minimap-filter-fill" },
		placeholderText = _("Search industries or cargo..."),
		value = query,
		onTyping = withQuery,
		onValueChange = withQuery,
	}

	local shown, total = filter.shownCount(types, sel)
	local heading : string
	if filter.isEmpty(sel) then
		heading = _("Showing all industry types")
	else
		heading = string.format(_("Showing %d of %d types"), shown, total)
	end
	rows[#rows + 1] = hbox({
		text(heading, "font-scale-body, minimap-filter-heading"),
		builtin.Button{
			meta = { class = "minimap-filter-all", tooltip = _("Show every industry type again"), enabled = not filter.isEmpty(sel) },
			content = text(_("Show all"), "font-scale-annotation"),
			onClick = function()
				setFilter({}, "window show all")
			end,
		},
	}, "minimap-filter-header, minimap-filter-fill")

	local typeRows : {TreeNodeId} = {}
	local onMap : {string : boolean} = {}
	for __, t in ipairs(types) do onMap[t.key] = true end
	for __, t in ipairs(filter.search(types, query)) do
		typeRows[#typeRows + 1] = filterTypeRow(t, sel[t.key] == true, toggleType)
	end
	if #typeRows == 0 then
		local empty = #types == 0 and _("No industries on the map.")
			or string.format(_("No industry type matches \"%s\"."), query)
		rows[#rows + 1] = text(empty, "font-scale-annotation, minimap-filter-hint")
	elseif #typeRows > FILTER_SCROLL_ROWS then
		-- ScrollArea content must be a Component, not a layout (memory "ScrollArea content is a
		-- Component"; base: entity_window_util.tl:715-721). Height inline, full width from the stylesheet.
		rows[#rows + 1] = builtin.ScrollArea{
			meta = { class = "minimap-filter-types, minimap-filter-fill", styleSheet = styleutil.makeStyle{ size = { -1, 220 } } },
			content = builtin.Component{
				layout = vbox(typeRows, "minimap-filter-list"),
			},
			horizontalPolicy = builtin.type.ScrollBarPolicy.AlwaysOff,
			verticalPolicy = builtin.type.ScrollBarPolicy.AsNeeded,
		}
	else
		rows[#rows + 1] = vbox(typeRows, "minimap-filter-list")
	end
	local notOnMap = 0
	for k, v in pairs(sel) do
		if v and not onMap[k] then notOnMap = notOnMap + 1 end
	end
	if notOnMap > 0 then
		rows[#rows + 1] = text(string.format(_("+%d selected, not on this map"), notOnMap), "font-scale-annotation, minimap-filter-hint")
	end
	rows[#rows + 1] = text(_("Shift+click an icon on the minimap: only its type. Again: all."), "font-scale-annotation, minimap-filter-hint")
	-- A recipe in a Window's content returns a layout (memory "Recipe must return layout").
	return vbox(rows, "minimap-filter-root")
end))

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
					log.warning("[Minimap] this platform's Window rejects '" .. key .. "'; left out")
				end
			end
			if not windowFieldOk[key] then t[k] = nil end
		end
	end
	return p
end

MinimapFilterWindow = react.RegisterWrapperRecipe("MinimapFilterWindow", builtin.Window, perf:wrap("filter_window_render", function(params : FilterWindowParam) : TreeNodeId
	react.onMount(function()
		filterWindowMounted = true
	end)
	react.onUnmount(function()
		filterWindowMounted = false
		logm("filter window unmounted")
	end)
	return builtin.Window(platformWindow{
		meta = { class = "minimap-window" }, -- stylesheet Window!minimap-window (anchor)
		id = FILTER_WINDOW_ID,
		title = _("Industry filter"),
		closable = true,
		movable = true,
		autoFocusOnBecomingVisible = false,
		autoVisibilityOnFocusChange = false,
		initialX = params.initialX,
		initialY = params.initialY,
		onClose = params.onClose,
		content = MinimapFilterContent(),
	})
end))

local MinimapContent = react.RegisterRecipe("MinimapContent", perf:wrap("content_render", function() : TreeNodeId
	local selfRef = react.useSelfRef()
	local posDue = useMainThreadTick(POS_POLL_SECONDS)
	local lastPosRef = react.useRef("") as ReactRefT<string>
	local dataState = react.useState(nil) as ReactStateT<MapData>
	local industriesState = react.useState(session.showIndustries) as ReactStateT<boolean>
	local netOnState = react.useState(session.showNet) as ReactStateT<boolean>
	local hiVisState = react.useState(session.hiVis) as ReactStateT<boolean>
	local sizeState = react.useState(session.sizeIdx) as ReactStateT<integer>
	-- Industry filter (phase 7): re-render (Filter tooltip, markers) on every selection change.
	local filterSeqState = react.useState(filterSeq) as ReactStateT<integer>
	filterListeners.content = function(seq : integer)
		if filterSeqState:old() ~= seq then filterSeqState:set(seq) end
	end
	local filterOpenState = react.useState(isFilterShown()) as ReactStateT<boolean>
	filterWindowListener = function(open : boolean)
		if filterOpenState:old() ~= open then filterOpenState:set(open) end
	end
	react.onUnmount(function()
		filterListeners.content = nil
		filterWindowListener = nil
	end)
	local revsRef = react.useRef(nil) as ReactRefT<RevState>
	local startedRef = react.useRef(false) as ReactRefT<boolean>
	local revDue = useMainThreadTick(REV_CHECK_SECONDS)

	local function rebuild(reason : string)
		local d = buildMapData(reason)
		if d ~= nil then dataState:set(d) end
	end

	local function readRevs() : RevState
		local tPerf = perfStep:start()
		local ok, revsOrErr = pcall(readRevState)
		perfStep:stop("rev_read", tPerf)
		if not ok then
			warnOnce("readRevState", tostring(revsOrErr))
			return nil
		end
		return revsOrErr as RevState
	end

	react.onStep(function()
		-- First build one step after mounting (not during render), like the editor's deferred preview.
		if not startedRef:get() then
			startedRef:set(true)
			revsRef:set(readRevs())
			rebuild("open")
			return
		end
		-- Rebuild only when terrain, towns or the set of industries changed (map_editor.tl:335-340).
		-- Not while hidden: the first check after showing it again catches up.
		if not revDue() then return end
		if not isShown() then return end
		local revs = readRevs()
		if revs ~= nil and not table_util.deepEquals(revs, revsRef:get()) then
			local what = revDiff(revsRef:get(), revs)
			revsRef:set(revs)
			rebuild("changed: " .. what)
		end
	end)

	-- Remember where the window is (see WINDOW POSITION). Raw values are logged on every change.
	react.onStep(function()
		if not posDue() then return end
		if not isShown() then return end -- a hidden window reports no useful position
		local tPerf = perfStep:start()
		local ok, errOrNil = pcall(function() : any
			local node = selfRef:get()
			if node == nil then return nil end
			local p0 = node:getPosition(0, 0)
			local p1 = node:getPosition(1, 1)
			local screen = api.gui.camera.getSize()
			local l, t = geom.normalizeScreenPos(p0.x, p0.y, screen.x, screen.y)
			local r, b = geom.normalizeScreenPos(p1.x, p1.y, screen.x, screen.y)
			local raw = string.format("content (%.4f,%.4f)-(%.4f,%.4f) screen %dx%d", p0.x, p0.y, p1.x, p1.y, screen.x, screen.y)
			if raw == lastPosRef:get() then return nil end
			lastPosRef:set(raw)
			-- Validity check of the content rect (nil for 0,0-0,0 before layout, NaN, off screen).
			if geom.windowAnchor(l, t, r, b, -1) == nil then
				logm("position: ignored " .. raw)
				return nil
			end
			lastWindowFracW = r - l
			if anchorDX == nil then
				if windowMoved or requestedX == nil then
					logm("position: moved before the frame offset was measured; not remembered this time " .. raw)
					return nil
				end
				anchorDX, anchorDY = requestedX - r, requestedY - t
				logm(string.format("position: frame offset %.4f,%.4f (requested anchor %.4f,%.4f)", anchorDX, anchorDY, requestedX, requestedY))
			end
			-- Window edges from the content rect (side/bottom frame taken as wide as the right one).
			local x, y = geom.windowAnchor(l - anchorDX, t + anchorDY, r + anchorDX, b + anchorDX, WINDOW_MIN_TOP)
			if x == nil then
				logm("position: ignored " .. raw)
				return nil
			end
			session.posX = x
			session.posY = y
			logm(string.format("position: saved %s -> anchor %.4f,%.4f", raw, x, y))
			return nil
		end)
		perfStep:stop("pos_poll", tPerf)
		if not ok then
			warnOnce("window position", tostring(errOrNil))
		end
	end)

	local data = dataState:old()
	shownData = data
	local sizeIdx = sizeState:old()
	local stepIdx = SIZES[sizeIdx] ~= nil and sizeIdx or DEFAULT_SIZE
	local longSide = SIZES[stepIdx]
	local minW = MIN_WIDTHS[stepIdx]
	local w, h = math.max(longSide, minW), longSide
	if data ~= nil then
		w, h = geom.pictureSize(data.box, longSide, minW, MAX_LONG[stepIdx], ORIENT, FLOOR_W, ABS_MAX_LONG)
	end

	local function setIndustries(v : boolean)
		if v == session.showIndustries then return end
		session.showIndustries = v
		industriesState:set(v)
		logm("option: industries=" .. tostring(v))
		if not v then closeFilterWindow("Ind off") end
	end

	local function setNet(v : boolean)
		if v == session.showNet then return end
		session.showNet = v
		netOnState:set(v)
		logm("option: net=" .. tostring(v))
		if v then
			netFailed = false
			netNextCheckMs = 0
		else
			netPark("toggled off")
		end
	end

	local function setHiVis(v : boolean)
		if v == session.hiVis then return end
		session.hiVis = v
		hiVisState:set(v)
		logm("option: hivis=" .. tostring(v))
		-- Applied by the layer's next step (re-encode only). Parked or off: on the next switch-on.
		if netState ~= nil and netState.parkedSinceMs == nil then netState.waitUntilMs = 0 end
	end

	local function cycleSize()
		local nextIdx = sizeIdx % #SIZES + 1
		session.sizeIdx = nextIdx
		sizeState:set(nextIdx)
		local nw, nh = 0, 0
		if data ~= nil then nw, nh = geom.pictureSize(data.box, SIZES[nextIdx], MIN_WIDTHS[nextIdx], MAX_LONG[nextIdx], ORIENT, FLOOR_W, ABS_MAX_LONG) end
		logm(string.format("option: size=%s (%dx%d px)", SIZE_LABELS[nextIdx], nw, nh))
	end

	cycleSizeFn = cycleSize

	-- "Filter" (phase 7): only while Ind is on; checked while the filter window is open. The
	-- tooltip says how many types the filter shows. "Viz" only while Net is on.
	-- Translated labels (strings.json); their length sizes the control rows (geom.controlWidth).
	local labels : {string : string} = { ind = _("Ind"), filter = _("Filter"), net = _("Net"), viz = _("Viz") }
	local showFilter = industriesState:old()
	local filterBox : TreeNodeId = nil
	if showFilter then
		local tip : string
		if filter.isEmpty(session.filter) then
			tip = _("Filter industries: show only some types. Tip: Shift+click an icon on the map to show only its type, Shift+click again to show all.")
		else
			local shown, total = filter.shownCount(typesFor(data), session.filter)
			if shown == 0 then
				tip = _("No selected industry type is on this map, so no industries are shown.")
			else
				tip = string.format(_("Filter active: showing %d of %d industry types. Shift+click the map to show all."), shown, total)
			end
		end
		filterBox = checkBox(labels.filter, tip, filterOpenState:old(), setFilterWindowOpen)
	end
	local controlNodes : {string : TreeNodeId} = {
		ind = checkBox(labels.ind, _("Show industries with the icon of what they produce"), industriesState:old(), setIndustries),
		filter = filterBox,
		net = checkBox(labels.net, _("Show roads, tracks and town buildings on the map"), netOnState:old(), setNet),
	}
	if netOnState:old() then
		controlNodes.viz = checkBox(labels.viz, _("High visibility: draw the network in bright, opaque colours"),
			hiVisState:old(), setHiVis)
	end
	local shownIds : {string} = {}
	local controlW : {string : integer} = {}
	for __, id in ipairs({ "ind", "filter", "net", "viz" }) do
		if controlNodes[id] ~= nil then shownIds[#shownIds + 1] = id end
		controlW[id] = geom.controlWidth(labels[id])
	end
	local rowIds = geom.controlRows(math.max(w, FLOOR_W), shownIds, controlW, CONTROL_SPACING, CONTROL_PAD)
	local rows : {TreeNodeId} = {}
	for i, ids in ipairs(rowIds) do
		local items : {TreeNodeId} = {}
		for __, id in ipairs(ids) do
			if controlNodes[id] ~= nil then items[#items + 1] = controlNodes[id] end
		end
		if i == 1 and not SIZE_BUTTON_IN_HEADER then items[#items + 1] = MinimapSizeButton() end
		rows[#rows + 1] = hbox(items, i == 1 and "minimap-controls" or "minimap-controls, minimap-controls-2")
	end

	local canvas = MinimapCanvas{ data = data, w = w, h = h, markerSize = MARKER_PX[stepIdx] or MARKER_PX[DEFAULT_SIZE],
		showIndustries = industriesState:old(), showNet = netOnState:old(), bandW = math.max(w, FLOOR_W),
		filterSeq = filterSeqState:old() }
	if w < FLOOR_W then
		-- Only strips whose long side would pass ABS_MAX_LONG (ABS_MAX_LONG beat FLOOR_W): the window
		-- is wider than the picture, so a FLOOR_W-wide band centres it. The padding adds to the style size (a { minW, h } size made the window 60 px too
		-- wide in game), so size = the picture. The canvas node stays w x h: clicks map as before.
		local left = (FLOOR_W - w) // 2
		local st = styleutil.makeStyle{ size = { w, h } }
		st.padding = api.type.Vec4f.new(0, FLOOR_W - w - left, 0, left)
		canvas = builtin.Component{
			meta = { styleSheet = st },
			layout = hbox({ canvas }),
		}
	end

	local children : {TreeNodeId} = { canvas }
	for __, r in ipairs(rows) do children[#children + 1] = r end
	return vbox(children, "minimap-root")
end))

---------------------------------------------------------------------------
-- Window + ridge button

local record MinimapWindowParam
	onClose : function()
	-- Read by builtin.WindowContainer from the addSingletonWindow params (builtin.lua:421-427) and
	-- by the Window itself: screen fractions of the window's anchorPoint (entity windows pass 1, 0
	-- with anchorPoint {1, 0}: view_manager.tl:310-311 + entity_window.css.lua:33-37; popovers pass a
	-- button's getPosition(1, 0): popover_react_util.tl:94-109). Only used when the window is
	-- (re-)created; closing just hides it.
	initialX : number
	initialY : number
end

local MinimapWindow : Recipe<MinimapWindowParam> -- assigned below (hideWindow's fallback names it)

local function setWindowVisible(visible : boolean) : boolean, any
	return pcall(function() : any
		api.gui.byId.setVisible(WINDOW_ID, visible)
		return nil
	end)
end

local function hideWindow(why : string)
	hiddenByUs = true
	session.open = false
	closeFilterWindow("minimap hidden")
	local ok, err = setWindowVisible(false)
	if not ok then
		warnOnce("hide window", tostring(err))
		-- Fallback: remove it (the next open re-creates it at the saved position).
		local wa = game_react_globals.getDefaultWindowApi()
		if wa ~= nil then wa.removeAllWindows(MinimapWindow) end
	end
	logm(string.format("window hidden (%s); position kept %s", why,
		session.posX ~= nil and string.format("%.4f,%.4f", session.posX, session.posY) or "(none saved)"))
end

--- onClose of the Window: the X button (only shown while unpinned) or whatever else the engine
--- closes windows with (IA_CLOSE_TOPMOST_WINDOW on ESC, handled in C++; callout_react_util.tl:19).
local function onWindowClose()
	if session.pinned then
		-- Pinned windows have no X (closable = false), so this is not the player's click: ESC or
		-- another engine close. Keep the window; the plugin's step re-shows it if it was hidden.
		logm("close request while pinned ignored (ESC?)")
		hiddenByUs = false
		return
	end
	hideWindow("closed")
end

MinimapWindow = react.RegisterWrapperRecipe("MinimapWindow", builtin.Window, perf:wrap("window_render", function(params : MinimapWindowParam) : TreeNodeId
	local pinnedState = react.useState(session.pinned) as ReactStateT<boolean>

	react.onMount(function()
		windowMounted = true
	end)
	-- The window can also go away without us (e.g. a game load); the next open re-creates it.
	react.onUnmount(function()
		windowMounted = false
		logm("window unmounted")
		netRelease("window unmounted")
	end)

	local function setPinned(pin : boolean)
		if pin == session.pinned and pin == pinnedState:old() then return end
		session.pinned = pin
		pinnedState:set(pin)
		logm("option: pinned=" .. tostring(pin))
	end

	-- Unpinned: ESC closes the minimap when it has focus, like an unpinned entity window
	-- (view_manager.tl:245-247). Pinned: Disabled (not Inactive), which "leaves the keys for other
	-- actions" (gui.d.tl:332-335), so ESC reaches the pause menu.
	react.useInputAction("IA_MENU_BACK", react.iaHandler(function()
		onWindowClose()
	end, function() : Gui.InputAction.InputActionState
		if session.pinned then return api.gui.inputAction.InputActionState.Disabled end
		return api.gui.inputAction.InputActionState.Enabled
	end))

	local pinned = pinnedState:old()
	local winParams : Builtin.WindowParam = {
		id = WINDOW_ID,
		-- No title (2026-10-10, user): the header holds only the size button and the pin. emptyNameAllowed
		-- defaults to true (builtin.d.tl:1207).
		title = "",
		-- Pinned: no X and not closable, so the engine's close-topmost-window (ESC) has nothing to
		-- close (the context help window is the base precedent for pinned + conditional closable:
		-- context_helper_react.tl:862-875). Close a pinned minimap with the Map button, or unpin.
		closable = not pinned,
		movable = true,
		pinnable = true,
		pinned = pinned,
		onPinned = setPinned,
		autoFocusOnBecomingVisible = false,
		autoVisibilityOnFocusChange = false,
		initialX = params.initialX,
		initialY = params.initialY,
		onClose = onWindowClose,
		content = MinimapContent(),
		header = SIZE_BUTTON_IN_HEADER and MinimapSizeButton() or nil,
	}
	-- Undocumented in builtin.d.tl but used by both base pinnable windows (view_manager.tl:318-322,
	-- music_player.tl:278-280): a window the player moved counts as pinned.
	local extra = winParams as {string : any}
	extra.meta = { class = "minimap-window" } -- stylesheet Window!minimap-window (anchor)
	extra.onMovedChange = function()
		windowMoved = true
		setPinned(true)
	end
	return builtin.Window(platformWindow(winParams))
end))

local function showWindow(wa : Builtin.WindowAPI)
	hiddenByUs = false
	session.open = true
	local ok, err = setWindowVisible(true)
	if not ok then warnOnce("show window", tostring(err)) end
	wa.moveSingletonWindowToFront(MinimapWindow)
	logm("window shown again (position kept by the hidden window)")
end

local function toggleWindow()
	loadPrefs()
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		log.warning("[Minimap] no window container; cannot open the minimap window")
		return
	end
	if windowMounted then
		if isShown() then
			hideWindow("map button")
		else
			showWindow(wa)
		end
		return
	end
	hiddenByUs = false
	session.open = true
	-- The remembered anchor (this session or from the settings), else the default spot.
	local x, y = session.posX, session.posY
	if x ~= nil then
		logm(string.format("position: restore anchor %.4f,%.4f (initialX/initialY)", x, y))
	else
		x, y = DEFAULT_ANCHOR_X, DEFAULT_ANCHOR_Y
		logm(string.format("position: none saved, default anchor %.4f,%.4f", x, y))
	end
	requestedX, requestedY = x, y
	anchorDX, anchorDY = nil, nil
	windowMoved = false
	wa.addSingletonWindow(MinimapWindow, { onClose = onWindowClose, initialX = x, initialY = y })
	windowMounted = true -- also set by onMount; set here so a quick second click hides, not re-adds
	wa.moveSingletonWindowToFront(MinimapWindow)
end

--- The Map button's onClick (GUI thread), timed. Not used for the guard's re-open, which runs in
--- onStep and is timed there as part of perfStep's "guard" section.
local toggleWindowClick = perf:wrap("click_toggle", toggleWindow)

local GUARD_SECONDS <const> = 0.25
local REOPEN_MAX_TRIES <const> = 40 -- x GUARD_SECONDS: wait up to 10 s for the window container after a load
local reopenTries = 0               -- module state: re-open once per GUI load, not per plugin re-mount

--- The plugin's guard tick (onStep, every GUARD_SECONDS): settings load/save, re-open of a pinned
--- window after a load, re-show of a pinned window something else hid.
local function guardTick()
	loadPrefs()
	maintainPrefs()
	netCheckParked() -- frees a switched-off network layer's kept caches after NET_OFF_KEEP_SECONDS
	-- The filter window follows the minimap: closed when the minimap went away without hideWindow
	-- (an engine close, an unmount) or industries are off. Nothing to do while it isn't mounted.
	if filterWindowMounted and (not windowMounted or not session.showIndustries or not isShown()) then
		closeFilterWindow("minimap hidden")
	end
	-- Re-open a window that was pinned and open when the settings were last written (e.g.
	-- before loading this save), once the window container exists.
	if session.open and not windowMounted and reopenTries < REOPEN_MAX_TRIES then
		reopenTries = reopenTries + 1
		if game_react_globals.getDefaultWindowApi() ~= nil then
			reopenTries = REOPEN_MAX_TRIES
			logm("settings: re-opening the pinned minimap")
			toggleWindow()
		end
		return
	end
	if not windowMounted or hiddenByUs or not session.pinned then return end
	if isShown() then return end
	local ok, err = setWindowVisible(true)
	if ok then
		logm("pinned window was hidden by something else (ESC?); shown again")
	else
		warnOnce("re-show pinned window", tostring(err))
	end
end

-- SQPERF section "hud_render" (first: the first render after a load).
local MinimapHudPlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "MinimapHudPlugin", perf:wrap("hud_render", function() : TreeNodeId
	-- Hooks first, unconditionally (same order as square_problem_radar's plugin).
	-- Also mounts in the map editor (game.tl mounts MainModButtonArea there too).
	-- mod.json hudButtonStyle: { "Text", "Icon" }, default Icon (rev 9; missing = Icon too); read once per
	-- mount (mod params are fixed per game).
	local hudIconRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean
		local v = modParam("hudButtonStyle")
		logm(string.format("setting: hudButtonStyle=%s (raw %s)", v ~= 1 and "icon" or "text", tostring(v)))
		return v ~= 1
	end)
	local guardDue = useMainThreadTick(GUARD_SECONDS)
	-- The "Icon" ToggleButton is pressed while the minimap is shown (read in the guard tick, main thread:
	-- isShown calls api.gui).
	local shownState = react.useState(false) as ReactStateT<boolean>
	local function syncShown()
		local shown = windowMounted and isShown()
		if shown ~= shownState:old() then shownState:set(shown) end
	end
	-- Fallback for the pinned case: if anything but us hid the pinned window (e.g. the engine's
	-- ESC handling hides windows itself), show it again at once. Runs here because this button is
	-- always mounted and visible, unlike the window.
	react.onStep(function()
		if not guardDue() then return end
		local tPerf = perfStep:start()
		guardTick()
		syncShown()
		perfStep:stop("guard", tPerf)
	end)
	-- A plugin root must be a layout (MainModButtonArea mounts plugins as BoxLayout children).
	local button : TreeNodeId
	if hudIconRef:get() then
		-- "Icon" style: map icon on a base ToggleButton, pressed while the minimap is shown.
		button = builtin.ToggleButton{
			meta = { class = "minimap-hud-icon-button", tooltip = _("Better Minimap"), styleSheet = ridgeToggleStyle() },
			content = builtin.ImageView{ meta = { class = "minimap-hud-icon", styleSheet = ridgeIconStyle() }, path = HUD_ICON },
			value = shownState:old() and 1 or 0,
			onValueChange = function(__ : integer)
				toggleWindowClick()
				syncShown()
			end,
		}
	else
		button = builtin.Button{
			meta = { class = "minimap-hud-button", tooltip = _("Better Minimap") },
			content = text(_("Map")),
			onClick = toggleWindowClick,
		}
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { button },
	}
end))

local result = {
	MinimapHudPlugin = MinimapHudPlugin,
}

perf:phase("init", perfInit)

return result
