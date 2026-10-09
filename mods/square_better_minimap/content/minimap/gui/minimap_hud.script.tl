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

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local table_util = ug_require "::/scripts/table_util.tl" as TableUtil
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil

local geom = ug_require "square_better_minimap::/minimap/minimap_geom.tl" as SquareMinimapGeom

local WINDOW_ID <const> = "squareminimap.window"
local REV_CHECK_SECONDS <const> = 2.0    -- terrain/town/industry change check while the window is open
local CAM_POLL_SECONDS <const> = 0.1     -- camera box refresh (~10 Hz)
local POS_POLL_SECONDS <const> = 0.5     -- window position read (remembered for re-creation and the next load)
local FIT_POLL_SECONDS <const> = 1.0     -- picture vs window width check (log only)
local CAM_BOX_MIN_PX <const> = 12      -- keeps the 2 px outline visible as a box when zoomed all the way in
local CAM_MAX_DIST_FACTOR <const> = 4    -- footprint corners at most 4x the camera distance from the centre
-- View direction arrow in the camera box: the base block arrow with a shaft (white mask, tinted by
-- the stylesheet `color`), turned with ImageView.rotation (degrees, builtin.d.tl:816; base turns its
-- construction brush icon by any angle with it: construction_react_util.tl:884). Like the combobox
-- triangle it replaced, only the @2x file exists (gui.zip) and it loads by the plain name. The
-- triangle was too wide and flat: rotated, it read as a shapeless wedge with no clear tip.
local ARROW_ICON <const> = "::/gui/construction/build_control/symbol_arrow_straight_up_20.tga"
local ARROW_PX <const> = 18
-- Sign of ImageView.rotation: 1 if positive turns clockwise on screen. Not documented and the base
-- game only uses symmetric turns (180), so this is the one value to flip if the arrow turns mirrored.
local ARROW_ROT_SIGN <const> = 1
local WINDOW_MIN_TOP <const> = 0.06      -- keep the window's top edge below the HUD ridge (screen fraction)
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
local SIZE_LABELS : {string} = { "S", "L" }
local DEFAULT_SIZE <const> = 1 -- S: the minimap opens small

local ORIENT : SquareMinimapOrient = geom.DEFAULT_ORIENT

-- Industry marker edge in UI px per size step (S/L).
local MARKER_PX : {integer} = { 12, 18 }
-- Generic industry icon (base: industry_react_util.tl:715), for industries without a cargo icon.
local FALLBACK_ICON <const> = "::/gui/entity_window/icons/building_industry.tga"

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

local function ms(t0 : number, t1 : number) : string
	return string.format("%.1f ms", (t1 - t0) * 1000)
end

---------------------------------------------------------------------------
-- Session state (GUI-local module tables, never saved; reset when the GUI scripts reload).

local record Session
	withAssets : boolean
	showIndustries : boolean
	sizeIdx : integer
	pinned : boolean
	posX : number      -- window anchor (top-right, CSS anchorPoint {1, 0}) in screen fractions
	posY : number
	open : boolean     -- the player has the window open (set by open/close actions only, not by unmounts)
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
	sizeIdx = DEFAULT_SIZE,
	pinned = false,
	open = false,
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
		open = session.open and session.pinned,
	}
end

local function prefsText(p : SquareMinimapPrefs) : string
	return string.format("pos %s, pinned=%s, size=%s, industries=%s, open=%s",
		p.posX ~= nil and string.format("%.4f,%.4f", p.posX, p.posY) or "(none)",
		tostring(p.pinned), tostring(p.sizeIdx), tostring(p.showIndustries), tostring(p.open))
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
			showIndustries = p.showIndustries, open = p.open,
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
end

--- map_editor.tl:308-323 (terrain entity revisions + town revisions), plus the set of industries
--- (INDUSTRY component: mission_savegame_util.tl:39). Industry revisions are not used: they change
--- with production all the time; only founding/removing one changes the picture.
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
	return { terrain = terrain, towns = towns, industries = industries }
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

--- CargoType.icon (cargo_util.tl:436-439); "" when unknown. Cached: cargo resources don't change.
local function cargoIcon(cargoTypeId : integer) : string
	local cached = cargoIconCache[cargoTypeId]
	if cached ~= nil then return cached end
	local ok, pOrErr = pcall(function() : string
		local ct = api.res.cargoTypeRep.get(cargoTypeId as CargoTypeId)
		return ct ~= nil and ct.icon or ""
	end)
	local path = ""
	if ok and type(pOrErr) == "string" then
		path = pOrErr as string
	elseif not ok then
		warnOnce("cargo icon", tostring(pOrErr))
	end
	cargoIconCache[cargoTypeId] = path
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
	local okIo, ioErr = pcall(function() : any
		local ind = api.engine.getComponent(e, api.type.ComponentType.INDUSTRY) as Engine.Component.Industry
		local stockList = e
		if ind ~= nil and ind.stockList ~= nil and (ind.stockList as integer) >= 0 then stockList = ind.stockList end
		local io = api.engine.util.stock.getInputsOutputsFromRules(stockList)
		if io ~= nil then
			inputs = cargoIcons(io[1])
			outputs = cargoIcons(io[2])
		end
		return nil
	end)
	if not okIo then warnOnce("industry cargo", tostring(ioErr)) end
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
	-- withIndustries = false: no generic preview markers; ours are drawn by MinimapMarkers.
	local okMap, mapOrErr = pcall(api.engine.terrain.makeMapFromGame, true, true, false, session.withAssets)
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
	local ind = readIndustries()
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

local MinimapPreview = react.RegisterRecipe("MinimapPreview", function(params : PreviewParam) : TreeNodeId
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
				layout = vbox({ text(_("Loading map..."), "font-scale-annotation, minimap-status") }),
			},
		})
	end
	local data = params.data
	local env = previewEnv(data.map)
	local mountedAt = clock()
	return vbox({
		builtin.MapPreviewComp{
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
		},
	})
end)

---------------------------------------------------------------------------
-- Industry markers (re-mounted with the preview; no polling, nothing per camera tick)

local record MarkersParam
	data : MapData
	w : integer
	h : integer
	size : integer
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

local MinimapMarkers = react.RegisterRecipe("MinimapMarkers", function(params : MarkersParam) : TreeNodeId
	-- Layout cached per map generation + picture/marker size (pure data; nodes are made each render).
	local layoutRef = react.useRef(nil) as ReactRefT<{SquareMinimapMarkerPx}>
	local layoutKeyRef = react.useRef("") as ReactRefT<string>
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
	local size = params.size
	local children : {TreeNodeId} = {}
	for __, m in ipairs(layoutRef:get()) do
		children[#children + 1] = layerAt(m.key, m.left, m.top, size, size, params.w, params.h, builtin.ImageView{
			meta = {
				class = "minimap-industry-icon",
				tooltip = m.name,
				styleSheet = styleutil.makeStyle{ size = { size, size } },
			},
			scaling = builtin.type.ImageViewScaling.AutoFit,
			path = m.icon,
		})
	end
	-- Same frame as the camera overlay: sized, mouse-transparent Component, builtin FloatingLayout.
	return hbox({
		builtin.Component{
			meta = { styleSheet = styleutil.makeStyle{ size = { params.w, params.h } } },
			mouseTransparent = true,
			layout = builtin.FloatingLayout{
				children = children,
			},
		},
	})
end)

---------------------------------------------------------------------------
-- Mod settings (mod.json "params", chosen in the mod selection when a game is started or loaded;
-- docs/wiki/modding/general/modscripts.md). getModParams() (engine.d.tl:1806-1807) gives each
-- param as the 1-based index of the chosen value (community GUI scripts read it the same way,
-- e.g. zhenya_doubleclick_to_edit dce.script.lua:75). Params only change on a game load, so read once.

local MOD_ID <const> = "square_better_minimap"
local showArrowCache : boolean = nil

--- mod.json showArrow: values { "On", "Off" } -> 1 = on. Missing/unreadable (older saves, errors) = on.
local function showArrowSetting() : boolean
	if showArrowCache ~= nil then return showArrowCache end
	local ok, allOrErr = pcall(api.engine.config.getModParams)
	if not ok then
		warnOnce("mod params", tostring(allOrErr))
		showArrowCache = true
		return true
	end
	local all = allOrErr as {string : table}
	local mine = all ~= nil and all[MOD_ID] as {string : number} or nil
	local v = mine ~= nil and mine.showArrow or nil
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

local MinimapOverlay = react.RegisterRecipe("MinimapOverlay", function(params : OverlayParam) : TreeNodeId
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
		local ok, vOrErr = pcall(readCamView, p.box)
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
					styleSheet = styleutil.makeStyle{ size = { bw, bh } },
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
					styleSheet = styleutil.makeStyle{ size = { ARROW_PX, ARROW_PX } },
				},
				path = ARROW_ICON,
				scaling = builtin.type.ImageViewScaling.AutoFit, -- 20 UI px icon into ARROW_PX, as the markers
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
end)

---------------------------------------------------------------------------
-- Canvas: preview + overlay + click-to-jump

local record CanvasParam
	data : MapData
	w : integer
	h : integer
	markerSize : integer
	showIndustries : boolean
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

local MinimapCanvas = react.RegisterRecipe("MinimapCanvas", function(params : CanvasParam) : TreeNodeId
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
			logm(string.format("fit: picture %dx%d px = %.4f x %.4f screen, window width %.4f, extra width %.4f (~%.0f UI px)%s",
				p.w, p.h, r - l, b - t, winW, gap, gapPx, gapPx > 12 and " -> EMPTY BAND, raise MIN_WIDTHS" or ""))
			return nil
		end)
		if not ok then warnOnce("fit check", tostring(err)) end
	end)

	local function clickAt(ex : integer, ey : integer)
		local p = paramsRef:get()
		if p.data == nil then return end
		local ok, err = pcall(function() : any
			local node = selfRef:get()
			local p0 = node:getPosition(0, 0)
			local p1 = node:getPosition(1, 1)
			local screen = api.gui.camera.getSize()
			local fx, fy = geom.eventToFrac(ex, ey, p0.x, p0.y, p1.x, p1.y, screen.x, screen.y)
			if fx < -0.05 or fx > 1.05 or fy < -0.05 or fy > 1.05 then
				return nil
			end
			local wx, wy = geom.fracToWorld(geom.clamp(fx, 0, 1), geom.clamp(fy, 0, 1), p.data.box, ORIENT)
			jumpTo(wx, wy)
			return nil
		end)
		if not ok then
			warnOnce("click", tostring(err))
		end
	end

	react.setMouseTransparent(false)
	react.onMouseEvent(function(evt : Gui.Mouse.Event) : boolean
		local T = api.gui.mouse.Event.Type
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
	if params.data ~= nil and params.data.industries ~= nil and params.showIndustries then
		-- Between the preview and the camera overlay; re-mounted with them (same key scheme).
		children[#children + 1] = builtin.FloatingLayoutChild{
			h = -1,
			v = -1,
			localKey = "minimap_markers_" .. tostring(gen) .. "_" .. tostring(params.w) .. "_" .. tostring(params.markerSize),
			item = MinimapMarkers{ data = params.data, w = params.w, h = params.h, size = params.markerSize },
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
end)

---------------------------------------------------------------------------
-- Window content

local function checkBox(label : string, tooltip : string, value : boolean, onChange : function(boolean)) : TreeNodeId
	return builtin.CheckBox{
		meta = { tooltip = tooltip },
		value = value and 1 or 0,
		label = label,
		onValueChange = function(v : integer) onChange(v == 1) end,
	}
end

local function smallButton(label : string, tooltip : string, onClick : function()) : TreeNodeId
	return builtin.Button{
		meta = { class = "minimap-small-button", tooltip = tooltip },
		content = text(label, "font-scale-annotation"),
		onClick = onClick,
	}
end

local MinimapContent = react.RegisterRecipe("MinimapContent", function() : TreeNodeId
	local selfRef = react.useSelfRef()
	local posDue = useMainThreadTick(POS_POLL_SECONDS)
	local lastPosRef = react.useRef("") as ReactRefT<string>
	local dataState = react.useState(nil) as ReactStateT<MapData>
	local industriesState = react.useState(session.showIndustries) as ReactStateT<boolean>
	local sizeState = react.useState(session.sizeIdx) as ReactStateT<integer>
	local revsRef = react.useRef(nil) as ReactRefT<RevState>
	local startedRef = react.useRef(false) as ReactRefT<boolean>
	local revDue = useMainThreadTick(REV_CHECK_SECONDS)

	local function rebuild(reason : string)
		local d = buildMapData(reason)
		if d ~= nil then dataState:set(d) end
	end

	local function readRevs() : RevState
		local ok, revsOrErr = pcall(readRevState)
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
			revsRef:set(revs)
			rebuild("game changed")
		end
	end)

	-- Remember where the window is (see WINDOW POSITION). Raw values are logged on every change.
	react.onStep(function()
		if not posDue() then return end
		if not isShown() then return end -- a hidden window reports no useful position
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
		if not ok then
			warnOnce("window position", tostring(errOrNil))
		end
	end)

	local data = dataState:old()
	local sizeIdx = sizeState:old()
	local stepIdx = SIZES[sizeIdx] ~= nil and sizeIdx or DEFAULT_SIZE
	local longSide = SIZES[stepIdx]
	local minW = MIN_WIDTHS[stepIdx]
	local w, h = math.max(longSide, minW), longSide
	if data ~= nil then
		w, h = geom.pictureSize(data.box, longSide, minW, MAX_LONG[stepIdx], ORIENT)
	end

	local function setIndustries(v : boolean)
		if v == session.showIndustries then return end
		session.showIndustries = v
		industriesState:set(v)
		logm("option: industries=" .. tostring(v))
	end

	local function cycleSize()
		local nextIdx = sizeIdx % #SIZES + 1
		session.sizeIdx = nextIdx
		sizeState:set(nextIdx)
		local nw, nh = 0, 0
		if data ~= nil then nw, nh = geom.pictureSize(data.box, SIZES[nextIdx], MIN_WIDTHS[nextIdx], MAX_LONG[nextIdx], ORIENT) end
		logm(string.format("option: size=%s (%dx%d px)", SIZE_LABELS[nextIdx], nw, nh))
	end

	return vbox({
		MinimapCanvas{ data = data, w = w, h = h, markerSize = MARKER_PX[stepIdx] or MARKER_PX[DEFAULT_SIZE], showIndustries = industriesState:old() },
		hbox({
			checkBox(_("Ind"), _("Show industries with the icon of what they produce"), industriesState:old(), setIndustries),
			smallButton(SIZE_LABELS[sizeIdx] or "S", _("Map size: small / large"), cycleSize),
		}, "minimap-controls"),
	}, "minimap-root")
end)

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

MinimapWindow = react.RegisterWrapperRecipe("MinimapWindow", builtin.Window, function(params : MinimapWindowParam) : TreeNodeId
	local pinnedState = react.useState(session.pinned) as ReactStateT<boolean>

	react.onMount(function()
		windowMounted = true
	end)
	-- The window can also go away without us (e.g. a game load); the next open re-creates it.
	react.onUnmount(function()
		windowMounted = false
		logm("window unmounted")
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
		title = _("Map"), -- short: at size S the title bar sets the window's minimum width
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
	}
	-- Undocumented in builtin.d.tl but used by both base pinnable windows (view_manager.tl:318-322,
	-- music_player.tl:278-280): a window the player moved counts as pinned.
	local extra = winParams as {string : any}
	extra.onMovedChange = function()
		windowMoved = true
		setPinned(true)
	end
	return builtin.Window(winParams)
end)

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

local GUARD_SECONDS <const> = 0.25
local REOPEN_MAX_TRIES <const> = 40 -- x GUARD_SECONDS: wait up to 10 s for the window container after a load
local reopenTries = 0               -- module state: re-open once per GUI load, not per plugin re-mount

local MinimapHudPlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "MinimapHudPlugin", function() : TreeNodeId
	-- Hooks first, unconditionally (same order as square_problem_radar's plugin).
	local isMapEditorRef : ReactRefT<boolean> = react.useRefLazy(function() : boolean return api.gui.game.isMapEditor() end)
	local guardDue = useMainThreadTick(GUARD_SECONDS)
	-- Fallback for the pinned case: if anything but us hid the pinned window (e.g. the engine's
	-- ESC handling hides windows itself), show it again at once. Runs here because this button is
	-- always mounted and visible, unlike the window.
	react.onStep(function()
		if not guardDue() then return end
		if isMapEditorRef:get() then return end
		loadPrefs()
		maintainPrefs()
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
	end)
	if isMapEditorRef:get() then
		return nil
	end
	-- A plugin root must be a layout (MainModButtonArea mounts plugins as BoxLayout children).
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { class = "minimap-hud-button", tooltip = _("Show or hide the minimap") },
				content = text(_("Map")),
				onClick = toggleWindow,
			},
		},
	}
end)

local result = {
	MinimapHudPlugin = MinimapHudPlugin,
}

return result
