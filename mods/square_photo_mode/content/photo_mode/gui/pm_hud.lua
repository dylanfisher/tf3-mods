-- Photo Mode: what the player sees besides the 3D view (GUI thread only: window clicks, the plugin's onStep and
-- its openPauseMenu event). PLAN: plans/square_photo_mode/PLAN.md "Clean view: labels, UI, tour".
--
--   labels   "Hide labels" (round 18; "Hide labels and hover" before): the base HUD filter (the data layers' "HUD filter" window, base
--            gui/layers/layer_hud_filter.tl) is GUI save data of the savegame, key "" field hudFilter
--            (BaseGUISaveData, gui/main/game_context.d.tl:83-97). Hide = a copy of that data with every filter
--            toggle off (pm_core.hiddenHudFilter), written with setGuiSaveData("", copy) exactly as the base window
--            does. The base default selector reads the filter only when its action renders
--            (gui/main/selector_react_util.tl:43-86, 194-240). Its action keeps a react state set by the events
--            "preventReactSelector" / "allowReactSelector" (no base code fires them): while prevented it builds
--            no makeDefaultSelector and no makeDefaultSelectorTooltips (selector_react_util.tl:194-232), i.e. no
--            hover highlight, no entity tooltip and no click-to-select on the map. So hiding fires
--            "preventReactSelector" and KEEPS it (round 6, user: "disable hover while in photo mode"): the
--            action re-renders with the hidden filter and without hover; showing writes the filter back and
--            fires "allowReactSelector" (re-render: labels and hover back). A remounted selector (another tool
--            and back) starts allowed: a tour start fires "preventReactSelector" again while hidden. Off = the player's own
--            hudFilter back (as it was, also "absent"), unless the player changed the filter meanwhile (then it
--            stays as they set it). The player's filter is also kept in our own GUI save data (key modId, field
--            hud), so a save made while hidden (autosave) gets its labels back on the next load.
--            Off on: the checkbox, the pause menu. Not on window close (the player may want clean shots).
--   hover    round 9 (user: "The tour still has hover and mouse interaction with it. It should by default not."):
--            while an automated camera move runs (a tour of any mode, Wander, Orbit; pm_driver D.onAutoMode) the
--            selector is prevented too, labels or not: no hover highlight, no entity tooltip, no click-to-select.
--            Fired at the start and again 2 and 30 frames later (a selector remounted meanwhile starts allowed);
--            allowed again when the move ends by any path (camera input, Esc / the pause menu, the window, a new
--            game: nothing is saved), unless "Hide labels and hover" keeps it prevented. Mouse look during a
--            flight is camera input, not the selector: unaffected.
--   tool     round 10 (user: hover and money floaters still showed during tours, "Hide labels and hover" didn't stop
--            the hover, although "hover off" was logged): the events above have no proven receiver (the default
--            selector is the default TOOL's action, rendered through the tool stack's useAction; whether a
--            fireEvent(nil, ...) from a plugin reaches it is unverified, and a re-shelved default tool builds a
--            fresh, allowed selector: view_manager.tl EntityDetailsTool.shelve -> setDefaultSelectorAction). So
--            while hover must be off (an automated move, the labels hidden, the smooth camera) we push our own
--            tool, "SquarePhotoModeView" (react.RegisterTool, empty push / pop, no action), on the default tool
--            stack, as the game's free camera does (free_cam_options.tl): the top tool owns the renderer's
--            action (builtin.lua ToolStack: setActiveOwner of the top entry), ours has none, so the default
--            selector's action (hover, entity tooltips, click-to-select, the HUD icon config with the money
--            floaters) is shelved, not just asked to stop. The normal camera keeps the player's controls and our
--            setCameraData (only the free camera is a camera of its own). Popped when nothing needs it; another
--            tool clearing the stack (a build menu) pops it too (our pop handler notices; not pushed again until
--            the need ends). The events stay as a second path. Inferred from the game files: TESTING.md W1.
--            Round 11: it did NOT work (session 2026-10-14_0055_session: "Selected entity 32615" at 00:58:09 with
--            our tool pushed for the smooth camera, "Selected entity 38215" at 00:58:55 with it pushed for hidden
--            labels; each click opened an entity window, whose EntityDetailsTool cleared the stack and popped
--            ours). A tool with NO action leaves the renderer on the default selector's. The base tools that switch
--            the hover off give theirs an EMPTY action instead: the music player, the calendar editor and the
--            pause menu call setActionFn(function() return builtin.ActionDescriptor{ tool = "...", children = {} }
--            end) (music_player.tl:18, game_bar_widgets.tl:769, pause_menu.tl:337). So our push sets one too: no
--            Selector child (no hover, tooltip or click-to-select), the HUD icon config built as the base selector
--            builds it from the HUD filter (labels as the filter says: hidden while "Hide labels" is on; re-set
--            with a new key when the filter changes), and onBack: the action's back (the construction menu's
--            right-click abort, construction_react_util.tl:1416) ends the smooth camera / the camera move
--            (H.onBack). Inferred: TESTING.md Z1-Z3.
--            Round 12 (session 2026-10-14_0229_sqrl-sqst: hover and the cursor during tours): the tool was NOT on
--            during the tours at all. A tool removed by another one (02:50:33) was refused "until the need ends",
--            and "Hide labels" stayed on the whole session, so the need never ended and every later tour ran with
--            the game's selector ("hover off" logged, no "view tool on"; same in 2026-10-14_0055 after 00:58:55).
--            Now every NEW request (a move starting, the smooth camera, hiding the labels: the player pressed one
--            of our controls) clears the refusal and pushes again. Two more parts of the action: during a tour
--            (UI hidden) mouseCursor = 1009, the base's "None" cursor (gui_react_util.tl:14-45; the construction
--            and line tools set their cursor the same way, construction_react_util.tl:1420; inferred: hides the
--            cursor over the map); in the smooth camera a Selector whose filter accepts nothing (no hover) and
--            whose click (onSelect / onSelectNothing, both taken) reads the terrain point under the cursor
--            (the click's World details, else api.gui.mouse.getTerrainPosition) for H.onWorldClick: the
--            click-to-glide. Inferred: TESTING.md CA1-CA3.
--            Round 13: the smooth camera and its click selector are removed (PLAN.md "Round 13"). The action's
--            onBack (the right-click back) is set only while an automated move runs: with only the labels hidden
--            the tool stays on in the normal game, where a right click must keep its game meaning (close a
--            window, abort), not end nothing.
--            Round 14 (session 2026-10-14_0633_session, user: "hover still active" on an Aerials tour with the
--            view tool on, "action set", hover off logged, and no "Selected entity" at all): the empty action
--            stopped click-to-select but NOT the hover outline. So the outline is not drawn by a Selector of the
--            top action (none is left); the renderer draws it whenever it has an action owner (inferred: the
--            C++ side isn't readable). The base game's own cure is the cutscene task's: it fires
--            api.gui.fireReactEvent("disableToolActions", true) before playCutscene and false at its end
--            (base mission/tasks/cutscene/cutscene.tl:39, :51); game.tl:401 turns that into the tool stack's
--            setActionsDisabled, which sets the renderer's active owner override to nil (builtin.lua ToolStack
--            ~1393, RendererComponent setActiveOwnerOverride ~527): the renderer has no action at all, not an
--            empty one. While an automated move runs (S.auto: tours, Wander, Orbit) Photo Mode now does the same
--            ("tool actions off"), and turns them back on at every end of it: the move ending by any path, the
--            pause menu, another tool taking over, a new game, and a safety check each frame (actions off with
--            no move running are turned back on). Not for "Hide labels and hover" alone: the switch is global,
--            so a build menu opened in the normal game would have no action either. Costs: during a move the
--            action's right-click back is gone too (camera input and the pause key still end a move), and
--            whether the labels show with no action at all is unverified (TESTING.md CC1).
--            Round 15 (session 2026-10-14_0658_session: "I can still select items in tours, can still interact with
--            the world and hover"): the switch made it WORSE. 07:07:49 "tool actions off", 07:07:54 "Selected entity
--            26133 (stack = nil ...)": stack = nil is the default selector's own onSelect
--            (selector_react_util.tl:108), the entity window it opened cleared the stack (our tool popped). In 0633
--            the empty action alone had stopped every click (no "Selected entity" in three tours). With the
--            override nil the renderer has no active owner's action, the same as round 10's tool with NO action
--            (0055: clicks selected): the default tool's action, shelved but still bound to the renderer
--            (ToolStackEntryWrap useAction for every entry; view_manager.tl EntityDetailsTool.shelve keeps it), is
--            what the renderer falls back to (inferred, strong: C++). The base cutscene task can afford it because
--            a playing cutscene is a native camera action ("action-camera", CameraAction.cpp handles IA_MENU,
--            IA_BACK and OnSkipCutscene: the binary's strings) that takes the map's input itself. So round 15
--            never fires disableToolActions for our moves; it locks the world instead ("world lock", S.lock):
--              - our empty action stays on top (the 0633 result: no clicks); if anything takes it off during a
--                move (a cleared stack) it is pushed again on top at once (with stacking: another tool below is
--                kept and comes back when ours pops), at most LOCK_REPUSH times a move;
--              - the base selector entity filter (game.tl:160 "setSelectorEntityFilter", as the campaign's
--                mission_sim.script.tl:1225 fires it): a non-empty filter makes the default selector's filter
--                refuse every entity not in it (selector_react_util.tl:136-139), and ours holds only an id no
--                entity has, so the default selector, wherever it is bound, hovers and selects nothing; back to
--                {} (the free game's own) at the end. Not in a campaign mission (api.gui.mission.getMission()
--                not empty): its filter can't be read back to restore;
--              - the base disabled features (game.tl:166 "setDisableFeatures"): the player's table plus
--                OpenEntityWindow = true, so a selection that still happens opens no window
--                (view_manager.tl:623) and can't clear the tool stack; exactly the player's table back at the end
--                (game_react_globals.getDisableFeatures reads it). A frame later the lock reads it back and
--                logs whether the event reached the game ("world lock check").
--            Every exit undoes it: the move ending by any path, the pause menu, a new game (a fresh game context:
--            nothing to undo), and the per-frame safety check (a lock with no move running). Whether the filter
--            also takes the hover outline away is the in-game check (TESTING.md CD2).
--   hide UI  the fallback of camera mode (round 6: the footer's Hide UI checkbox became the Camera mode button): api.gui.byId.setVisible("react.game-ui-root", false) (holds; docs/findings/map-camera.md
--            "Hiding the game UI"). Stays hidden until the player presses Esc: the pause menu shows it again
--            (H.pauseMenu), as does every game start (H.start). No timer, no mouse or camera trigger (user
--            feedback 2026-10-13: moving the mouse to frame the shot brought the UI back).
--   tour     a tour hides our window (byId.setVisible(window id), as base tool windows are hidden,
--            gui/main/tool_react_util.tl:37-65) and the UI root until the tour stops: on camera input
--            (pm_driver), the pause menu (Esc) or the window closing; everything shows again then. No timer (user
--            feedback 2026-10-13: the UI came back by itself during an Aerials tour, the old 60 s fallback), the
--            same rule as the Hide UI checkbox. "Hide labels during tours" hides the labels for the tour and
--            brings them back after it (the hover goes for every automated move, see "hover").
--   camera   camera mode (round 6): the base FreeCamTool (gui/main/free_cam_options.tl, the
--            game bar's free camera) pushed on the default tool stack (game_react_globals.getDefaultToolStackApi
--            push(FreeCamTool, nil, {}, true), as game_bar_widgets.tl:105). Its push calls toggleFreeCamera:
--            the game hides its UI itself (the !action-follow / !action-camera rules of gui/main/game.css.lua),
--            and its options recipe, mounted in GameUIProxyRoot (outside the hidden root), pops the tool on
--            IA_BACK / IA_MENU_BACK: Esc / back return natively. The same module is reached with ug_require
--            "::/gui/main/free_cam_options.tl" (base mixes "/gui/..." and "::/gui/..." for one module, e.g.
--            react.lua, so the cache is shared; a second instance would raise "Already registered a tool").
--            Only the footer's "Free camera" button (round 6-9: "Camera mode") uses it (a free look around; no tour): the free camera is its
--            own camera, setCameraData doesn't move it (sessions 2026-10-13_0733, _0856 and _1755 probed it in
--            tours, every probe fell back; findings map-camera.md "The free camera ignores setCameraData"), so
--            round 9 removed the tours' "Try camera mode" option and its probe. If the tool can't be pushed, the
--            button hides the UI root instead (Hide UI, back with Esc / the pause key).
--            Round 13: the push no longer detaches the mouse from the free camera
--            (toggleFreeCameraMouseAttachment, rounds 6-12, meant for tours, which no longer use it): no base
--            code ever calls that toggle, it is native input state of unknown reach, and the player's report of
--            a hyper-sensitive camera "after some interaction" (session 2026-10-14_0434_session) follows the only
--            input state Photo Mode changed. The footer's free camera is now exactly the game bar's.
--   escape   Esc while the UI root is hidden is doubtful: base game.tl forwards IA_MENU (Esc) into the hidden
--            GameUIRoot, and its own comment says "forwarding to an invisible GameUIRoot is still impossible"
--            (gui/main/game.tl:746-747, 803); input actions of an invisible hierarchy don't fire (api gui.d.tl
--            InputActionState), and our plugin sits inside that root too, so a useInputAction of ours can't
--            help. What does work while hidden: the pause key (Space; "gamePause" / IA_GAME_PAUSE_OR_CYCLE_SPEED
--            are declared on GameUIProxyRoot, "available even when Game UI is not visible") and any
--            "openPauseMenu" event (Cmd+Q / quit requests, findings gui.md). So while the root is hidden the
--            step reads GAME_SPEED.speedup each frame (as the base GameSpeedHelper does) and a change between
--            paused and running (the pause key; the speed throttle never pauses) brings everything back
--            (H.onEscape: the tour stops; Hide UI unticks). Logged "ui shown (pause key)" / "(pause menu)".
-- Every api call in pcall; visibility is always put back (show on every exit path, and at every game start).

local react = ug_require "::/gui/main/react.lua"
local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"

local H = {}

H.UI_ROOT = "react.game-ui-root"
H.WINDOW_ID = "squarephotomode.window" -- pm_window.lua W.WINDOW_ID

-- Set by pm_window.lua: writes our GUI save data (views + H.saveMarker()).
H.persist = function() end
-- Set by the plugin: something the window shows changed.
H.changed = function() end
-- Set by the plugin: the player asked for the UI back while it was hidden (the pause key): stop the tour.
H.onEscape = function(why) end
-- Frames after hiding during which the speed read only settles (a speed command of ours may still land).
H.ESCAPE_SETTLE_FRAMES = 30
-- Frames after the footer's camera mode push before "not the active tool" counts as left (the tool stack applies
-- a push through a react state).
H.ACTIVE_GRACE = 5
-- Round 10: our own tool's name on the default tool stack (see "tool").
H.TOOL_NAME = "SquarePhotoModeView"
-- Round 11: our tool's action name (the ActionDescriptor's tool; letters and dashes, findings gui.md "CSS class").
H.ACTION_TOOL = "sqpm-view"
-- Round 11: set by the plugin: the back of our tool's action (a right click with the game's "Back With
-- Right-Click", inferred) while our tool is on during a camera move: the move ends.
H.onBack = function(why) end
-- Round 12: the base's "None" mouse cursor (gui/main/gui_react_util.tl getMouseCursorInteger), set on our action
-- during a tour (UI hidden: nothing to point at).
H.CURSOR_NONE = 1009
-- Frames after an automated move's start at which the selector is prevented again (a remounted one starts allowed).
H.AUTO_REASSERT = { [2] = true, [30] = true }

local S = {
	labels = false, -- labels hidden by us
	orig = nil,     -- the player's hudFilter (deep copy) while hidden
	had = false,    -- the player had a hudFilter at all
	refresh = 0,    -- frames until "allowReactSelector" is fired (0 = none pending)
	ui = nil,       -- Hide UI: true while hidden
	tourWindow = false, -- our window hidden for a tour
	tourUi = false, -- the UI root hidden for a tour
	tourLabels = false, -- labels hidden for a tour ("Hide labels during tours"): shown again when it ends
	camManual = nil, -- the free camera tool pushed by the footer button: { frames }
	auto = nil,     -- round 9: an automated camera move runs (hover off): { frames }
	reprevent = 0,  -- frames until "preventReactSelector" is fired again (labels shown during an automated move)
	watch = nil,    -- while the root is hidden: { frames, paused } (the pause-key escape hatch)
	tool = nil,     -- round 10: our tool pushed: { why }
	toolCtx = nil,  -- round 11: its tool stack context (setActionFn), from its push
	toolGone = false, -- our tool was popped by someone else (another tool, the stack cleared)
	toolRefused = false, -- ... so it is not pushed again until nothing needs it
	lock = nil,     -- round 15: the world lock during an automated move: { filter, features, orig, checked, repush }
}
H.S = S

local function try(what, fn)
	local ok, err = pcall(fn)
	if not ok then core.log(what .. " ERROR " .. tostring(err)) end
	return ok
end

---------------------------------------------------------------------------
-- Labels

local function hudTypes()
	local CT = api.type.ComponentType
	return { CT.STATION_GROUP, CT.INDUSTRY, CT.WAREHOUSE, CT.TOWN, CT.SUBCONSTRUCTION, CT.TRANSPORT_VEHICLE }
end

local function hudCarriers()
	local C = api.type.enum.Carrier
	return { C.ROAD, C.RAIL, C.TRAM, C.AIR, C.WATER }
end

local function baseData()
	local data = api.gui.game.getGuiSaveData("")
	return type(data) == "table" and data or nil
end

--- Writes the base GUI save data with hudFilter = f (nil: none) on a copy of the rest, as the base window does.
local function writeFilter(f)
	local copy = core.deepCopy(baseData()) or {}
	copy.hudFilter = f
	api.gui.game.setGuiSaveData("", copy)
end

local function preventSelector()
	try("preventReactSelector", function() react.fireEvent(nil, "preventReactSelector", "") end)
end

--- The default selector re-reads the filter when it renders: prevent now, allow next frame (H.step). Only for
--- a game start's repair; hiding keeps the selector prevented (no hover) until the labels come back.
local function refreshSelector()
	preventSelector()
	S.refresh = 2
end

local function allowSelector()
	S.refresh = 0
	try("allowReactSelector", function() react.fireEvent(nil, "allowReactSelector", "") end)
end

---------------------------------------------------------------------------
-- The world lock during automated moves (round 15, see "tool" in the header; replaces round 14's
-- disableToolActions, which let the default selector's clicks through)

-- An id no entity has (entities are >= 0): the only entry of our selector entity filter.
H.NO_ENTITY = -424242
-- Re-pushes of our tool per move (something clearing the stack over and over can't loop us).
H.LOCK_REPUSH = 10

local function fireBase(name, param)
	return try(name, function() api.gui.fireReactEvent(name, param) end)
end

local function inMission()
	local ok, m = pcall(function() return api.gui.mission.getMission() end)
	return ok and type(m) == "string" and m ~= ""
end

local function readFeatures()
	local ok, f = pcall(function()
		return (ug_require "::/gui/main/game_react_globals.tl").getDisableFeatures()
	end)
	if not ok or f == nil then return nil end
	local copy = {}
	local okP = pcall(function() for k, v in pairs(f) do copy[k] = v end end)
	return okP and copy or nil
end

--- Round 15: the world lock on (on = true) or off. Idempotent.
local function lockWorld(on, why)
	if on then
		if S.lock ~= nil then return end
		local L = { filter = false, features = false, orig = nil, checked = false, repush = 0 }
		S.lock = L
		if inMission() then
			core.log("world lock: in a campaign mission, the selector filter is left alone")
		else
			L.filter = fireBase("setSelectorEntityFilter", { [H.NO_ENTITY] = true })
		end
		L.orig = readFeatures()
		local f = {}
		for k, v in pairs(L.orig or {}) do f[k] = v end
		f.OpenEntityWindow = true
		L.features = fireBase("setDisableFeatures", f)
		core.log("world lock on (" .. why .. "): selector filter " .. (L.filter and "set" or "not set")
			.. ", entity windows " .. (L.features and "off" or "NOT off") .. ", player's features "
			.. (L.orig ~= nil and "read" or "unreadable"))
	else
		local L = S.lock
		if L == nil then return end
		S.lock = nil
		if L.filter then fireBase("setSelectorEntityFilter", {}) end
		if L.features then fireBase("setDisableFeatures", L.orig or {}) end
		core.log("world lock off (" .. why .. ")")
	end
end
H.lockWorld = lockWorld

function H.locked()
	return S.lock ~= nil
end

---------------------------------------------------------------------------
-- Our tool (round 10, see "tool" in the header)

--- Round 11: the HUD icon config of our action, as the base default selector builds it
--- (gui/main/selector_react_util.tl:207-224) from the HUD filter in the GUI save data; nil when a base piece is
--- missing (then the action has none). No notification cache (the game context isn't reachable from a mod; the
--- base toolbox skips it when nil, hud_icon_toolbox.tl:359).
local function hudIconConfig(builtin)
	local sru = ug_require "::/gui/main/selector_react_util.tl"
	local toolbox = ug_require "::/gui/main/hud_icon_toolbox.tl"
	local hru = ug_require "::/gui/hud/hud_react_util.tl"
	local rep = api.gui.genericRep
	local hudGui = rep.get(rep.find("::/gui/hud/hud_gui_config.gres")).data
	local sfx = rep.get(rep.find("::/game_mechanics/finance/sound/finance_sfx.gres")).data
	local data = baseData()
	local pre = core.hudPreFilter(data and data.hudFilter or nil, sru.defaultHudIconFilter,
		sru.defaultHudIconFilterTvCarrier, api.type.ComponentType.TRANSPORT_VEHICLE)
	return builtin.HudIconManagerConfig{
		userParam = {},
		masterRecipe = toolbox.HudIconMasterGame,
		preFilter = pre.preFilter,
		preFilterTvCarriers = pre.preFilterTvCarriers,
		showCosts = pre.showCosts,
		showIncome = pre.showIncome,
		incomeSFX = sfx.Income or {},
		costsRenderDistance = hudGui.renderDistances.Costs,
		visibilityThresholds = hru.makeDefaultVisibilityThresholds(),
		vehicleIconOffsets = hru.makeVehicleIconOffsets(hudGui.vehicleIconOffsets),
	}
end

local iconConfigLogged = false

--- Round 11: our tool's action (see "tool"): an ActionDescriptor with no Selector (no hover, entity tooltip or
--- click-to-select), the HUD icon config from the filter, and the back (H.onBack). A react render function: every
--- piece in pcall, so a missing base module only drops the icon config.
local function viewAction()
	local okB, builtin = pcall(ug_require, "::/gui/main/builtin.lua")
	if not okB then return nil end
	local children = {}
	local okC, cfg = pcall(hudIconConfig, builtin)
	if okC and cfg ~= nil then
		children[1] = cfg
	elseif not iconConfigLogged then
		iconConfigLogged = true
		core.log("view tool: no HUD icon config (" .. tostring(cfg) .. ")")
	end
	return builtin.ActionDescriptor{
		tool = H.ACTION_TOOL,
		terrainCirclePolicy = "Never",
		crosshair = false,
		-- round 12: no cursor over the map during a tour (nil: the default)
		mouseCursor = S.tourUi and H.CURSOR_NONE or nil,
		-- round 13: the right-click back only while a move runs (labels hidden alone: the game's right click)
		onBack = S.auto ~= nil and function() try("back", function() H.onBack("right click") end) end or nil,
		children = children,
	}
end
H.viewAction = viewAction

local actionKey = 0
--- Sets (again, with a new key: the renderer rebuilds it) our tool's action on its stack context.
local function setToolAction(ctx)
	if ctx == nil or type(ctx.setActionFn) ~= "function" then return false end
	actionKey = actionKey + 1
	return try("view tool action", function() ctx.setActionFn(viewAction, H.ACTION_TOOL .. "-" .. actionKey) end)
end

--- Round 11: the HUD filter changed while our tool is on (labels hidden / shown): its icon config is rebuilt.
local function refreshToolAction()
	if S.tool ~= nil and S.toolCtx ~= nil then setToolAction(S.toolCtx) end
end
H.refreshToolAction = refreshToolAction

local photoTool = nil -- { def } once registered (or { def = nil } when it can't be)
local function toolDef()
	if photoTool == nil then
		local ok, def = pcall(react.RegisterTool, {
			name = H.TOOL_NAME,
			push = function(ctx)
				-- round 11: an empty action of our own takes the renderer from the default selector's
				S.toolCtx = ctx
				setToolAction(ctx)
			end,
			pop = function()
				S.toolCtx = nil
				-- popped by anyone: by us (S.toolPopping) or by another tool / a cleared stack
				if not S.toolPopping and S.tool ~= nil then S.toolGone = true end
			end,
		})
		photoTool = { def = ok and def or nil }
		if not ok then core.log("view tool: not available (" .. tostring(def) .. ")") end
	end
	return photoTool.def
end
H.toolDef = toolDef

local function stackApi()
	local ok, api2 = pcall(function()
		return (ug_require "::/gui/main/game_react_globals.tl").getDefaultToolStackApi()
	end)
	return ok and api2 or nil
end

local function needTool()
	return S.auto ~= nil or S.labels
end

local function pushTool(why)
	local def, st = toolDef(), stackApi()
	if def == nil or st == nil then return false end
	local ok, err = pcall(function() st.push(def, nil, {}, true) end)
	if not ok then
		core.log("view tool: push ERROR " .. tostring(err))
		S.toolRefused = true
		return false
	end
	S.tool = { why = why }
	S.toolGone = false
	core.log("view tool on (" .. why .. "): no hover, tooltips or click-to-select; action "
		.. (S.toolCtx ~= nil and "set" or "pending"))
	return true
end

local function popTool(why)
	if S.tool == nil then return end
	S.tool = nil
	local def, st = toolDef(), stackApi()
	if def == nil or st == nil then return end
	S.toolPopping = true
	local ok, err = pcall(function() st.pop(def, nil) end)
	S.toolPopping = false
	core.log("view tool off (" .. why .. ")" .. (ok and "" or (" ERROR " .. tostring(err))))
end

--- Pushes / pops our tool to match what needs it (an automated move, hidden labels).
--- fresh: a new request (a move starting, the labels hidden: the player used one of our
--- controls) clears an earlier refusal (round 12: a tool removed once kept every later tour without ours).
local function syncTool(why, fresh)
	if fresh and S.tool == nil then S.toolRefused = false end
	if needTool() then
		if S.tool == nil and not S.toolRefused then pushTool(why) end
	else
		S.toolRefused = false
		if S.tool ~= nil then popTool(why) end
	end
end
H.syncTool = syncTool

function H.toolOn()
	return S.tool ~= nil
end

local setVisible, updateRoot -- below

--- Our save data's marker while labels are hidden: { hidden = true, had, orig } (nil when shown).
function H.saveMarker()
	if not S.labels then return nil end
	return { hidden = true, had = S.had, orig = core.deepCopy(S.orig) }
end

function H.labelsHidden()
	return S.labels
end

local function hideLabels()
	local data = baseData()
	local f = data and data.hudFilter or nil
	S.had = f ~= nil
	S.orig = core.deepCopy(f)
	writeFilter(core.hiddenHudFilter(hudTypes(), hudCarriers()))
	S.labels = true
	S.refresh = 0
	preventSelector() -- re-renders the selector's action: the hidden filter, and no hover until shown again
	core.log("labels and hover hidden (player's filter " .. (S.had and "kept" or "absent") .. ")")
	refreshToolAction() -- round 11: our action's icon config reads the hidden filter
	syncTool("labels hidden", true)
end

--- The player's filter back, unless they changed it while hidden (then theirs stays). The selector re-renders
--- (allow) to read it; during an automated move it is prevented again next frame (the hover stays off).
local function showLabels(why)
	S.labels = false
	local data = baseData()
	local cur = data and data.hudFilter or nil
	if core.isHiddenHudFilter(cur, hudTypes(), hudCarriers()) then
		writeFilter(S.had and core.deepCopy(S.orig) or nil)
		core.log("labels shown (" .. why .. ")")
	else
		core.log("labels shown (" .. why .. "): the filter was changed meanwhile, kept")
	end
	S.orig, S.had = nil, false
	allowSelector() -- re-renders the selector's action: the filter back, hover back
	if S.auto ~= nil then S.reprevent = 2 end
	refreshToolAction() -- round 11: our action (still on for a move) shows the labels again
	syncTool("labels shown")
end

--- Round 9: an automated camera move started (on) or the last one ended: hover, tooltips and click-to-select
--- off meanwhile (see the header); back afterwards unless "Hide labels and hover" keeps them off.
function H.setAutoHover(on)
	if on then
		if S.auto ~= nil then return end
		S.auto = { frames = 0 }
		S.refresh = 0
		preventSelector()
		core.log("hover off (automated camera move)")
		local had = S.tool ~= nil
		syncTool("automated camera move", true)
		if had then refreshToolAction() end -- round 13: the right-click back comes with the move
		lockWorld(true, "automated camera move")
	else
		if S.auto == nil then return end
		S.auto = nil
		S.reprevent = 0
		lockWorld(false, "camera move ended")
		if not S.labels then
			allowSelector()
			core.log("hover back (camera move ended)")
		end
		syncTool("camera move ended")
		refreshToolAction() -- round 13: a tool kept for the labels loses the right-click back
	end
end

function H.autoHover()
	return S.auto ~= nil
end

--- While the labels are hidden: the selector prevented again (a remounted selector starts allowed).
function H.reassertHidden()
	if S.labels then preventSelector() end
end

--- The "Hide labels" checkbox (on = hidden).
function H.setLabels(on, why)
	if on == S.labels then return end
	try("labels " .. (on and "hide" or "show"), function()
		if on then hideLabels() else showLabels(why or "checkbox") end
	end)
	try("save data", H.persist)
	H.changed()
end

---------------------------------------------------------------------------
-- UI root and our window

setVisible = function(id, on)
	return try("setVisible " .. id, function() api.gui.byId.setVisible(id, on) end)
end

local function rootHidden() return S.ui ~= nil or S.tourUi end

--- True when the game is paused (GAME_SPEED.speedup 0), nil when unreadable.
local function pausedNow()
	local ok, sp = pcall(function()
		return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED).speedup
	end)
	if not ok or type(sp) ~= "number" then return nil end
	return sp == 0
end

updateRoot = function()
	local hidden = rootHidden()
	setVisible(H.UI_ROOT, not hidden)
	if hidden then
		if S.watch == nil then S.watch = { frames = 0, paused = pausedNow() } end
	else
		S.watch = nil
	end
end

function H.uiHidden()
	return S.ui ~= nil
end

--- The "Hide UI" checkbox (ticked while hidden; H.showUi unticks it): the whole game UI (our window included)
--- until the pause menu (Esc) or the next game start.
function H.hideUi()
	if S.ui ~= nil then return end
	S.ui = true
	updateRoot()
	core.log("ui hidden (back on Esc or the pause key)")
	H.changed() -- the window's "Hide UI" checkbox shows ticked
end

function H.showUi(why)
	if S.ui == nil then return end
	S.ui = nil
	updateRoot()
	core.log("ui shown (" .. why .. ")")
	H.changed()
end

---------------------------------------------------------------------------
-- Camera mode: the base free camera tool (see the header)

local freeCam = nil -- { tool } once looked up
local function freeCamTool()
	if freeCam == nil then
		local ok, fc = pcall(ug_require, "::/gui/main/free_cam_options.tl")
		freeCam = { tool = ok and type(fc) == "table" and fc.FreeCamTool or nil }
		if freeCam.tool == nil then core.log("camera mode: the free camera tool is not available (" .. tostring(fc) .. ")") end
	end
	return freeCam.tool
end

local function toolStack()
	local ok, api2 = pcall(function()
		return (ug_require "::/gui/main/game_react_globals.tl").getDefaultToolStackApi()
	end)
	return ok and api2 or nil
end

--- Pushes the free camera tool (the game hides its UI itself); true when pushed.
local function pushFreeCam(why)
	local tool, st = freeCamTool(), toolStack()
	if tool == nil or st == nil then return false end
	local ok, err = pcall(function() st.push(tool, nil, {}, true) end)
	if not ok then
		core.log("camera mode: push ERROR " .. tostring(err))
		return false
	end
	core.log("camera mode: on (" .. why .. ")")
	return true
end

--- True while the free camera tool is the active tool, false when it isn't, nil when unreadable.
local function freeCamActive()
	local tool, st = freeCamTool(), toolStack()
	if tool == nil or st == nil then return nil end
	local ok, def = pcall(function() return st.getActiveTool() end)
	if not ok then return nil end
	return def == tool
end

--- Pops the free camera tool (a no-op when Esc / back already did: pop of a tool not on the stack does nothing,
--- builtin.lua ToolStack pop); its pop handler leaves the free camera and the UI comes back.
local function popFreeCam(why)
	local tool, st = freeCamTool(), toolStack()
	if tool == nil or st == nil then return end
	local ok, err = pcall(function() st.pop(tool, nil) end)
	core.log("camera mode: off (" .. why .. ")" .. (ok and "" or (" ERROR " .. tostring(err))))
end

--- The footer's "Free camera" (round 10; was "Camera mode"): the game's free camera (UI hidden by the game, back with Esc). If it can't be
--- pushed, the UI root is hidden instead (Hide UI: back with Esc or the pause key). Returns true for camera mode.
function H.cameraMode()
	if S.camManual ~= nil then return true end
	if pushFreeCam("button") then
		S.camManual = { frames = 0 }
		return true
	end
	core.log("camera mode: not available, hiding the UI instead")
	H.hideUi()
	return false
end

function H.cameraModeOn()
	return S.camManual ~= nil
end

--- A tour started (on = true; opts = { hideLabels }) or ended: our window and the UI root hidden / shown; labels
--- hidden for the tour.
function H.tourHide(on, opts)
	opts = type(opts) == "table" and opts or {}
	if on then
		S.tourWindow = true
		setVisible(H.WINDOW_ID, false)
		if opts.hideLabels and not S.labels then
			H.setLabels(true, "tour")
			S.tourLabels = S.labels
		elseif S.labels then
			H.reassertHidden()
		end
		S.tourUi = true
		updateRoot()
		refreshToolAction() -- round 12: no cursor over the map during the tour
		core.log("tour: window hidden, game UI hidden" .. (S.tourLabels and ", labels hidden" or "")
			.. (S.tool ~= nil and ", view tool on" or ", view tool OFF"))
	else
		local hadWindow, hadUi = S.tourWindow, S.tourUi
		S.tourWindow = false
		S.tourUi = false
		if hadWindow then setVisible(H.WINDOW_ID, true) end
		if hadUi then updateRoot() refreshToolAction() end
		if S.tourLabels then
			S.tourLabels = false
			if S.labels then H.setLabels(false, "tour ended") end
		end
		if hadWindow or hadUi then core.log("tour: window shown" .. (hadUi and ", game UI shown" or "")) end
	end
end

---------------------------------------------------------------------------
-- Every frame while busy (plugin onStep)

function H.busy()
	return S.refresh > 0 or S.watch ~= nil or S.camManual ~= nil or S.auto ~= nil or S.reprevent > 0 or S.tool ~= nil
		or S.lock ~= nil
end

--- The pause key while the UI is hidden: everything back (the tour stops through H.onEscape, which shows our
--- window and the root; Hide UI unticks).
local function escape(why)
	core.log("ui: " .. why .. " while hidden, bringing the UI back")
	S.watch = nil
	try("escape", function() H.onEscape(why) end)
	if S.tourWindow or S.tourUi then H.tourHide(false) end
	if S.ui ~= nil then H.showUi(why) end
	if rootHidden() then S.ui, S.tourUi = nil, false updateRoot() end
end

function H.step()
	if S.tool ~= nil and S.toolGone then
		S.tool, S.toolGone = nil, false
		S.toolCtx = nil
		local L = S.lock
		if S.auto ~= nil and L ~= nil and L.repush < H.LOCK_REPUSH then
			-- round 15: during a move ours goes back on top at once (stacking: a tool below comes back when ours
			-- pops at the move's end); the 0658 click that cleared the stack can't happen with the lock, this is
			-- the guard for anything else
			L.repush = L.repush + 1
			core.log(string.format("view tool: removed by another tool during a move, pushed again (%d of %d)",
				L.repush, H.LOCK_REPUSH))
			pushTool("world lock")
		else
			-- in the normal game (labels hidden) another tool (a build menu) keeps the map: not pushed again until
			-- a new request
			S.toolRefused = true
			core.log("view tool: removed by another tool (hover back until a new request)")
		end
		H.changed()
	end
	local L = S.lock
	if L ~= nil then
		-- round 15: the safety check: no lock without a move of ours running
		if S.auto == nil then
			lockWorld(false, "no camera move running")
		elseif not L.checked then
			-- one frame later: did the features event reach the game (game.tl's handler replaces its table)?
			L.checked = true
			local f = readFeatures()
			core.log("world lock check: entity windows " .. (f == nil and "unreadable"
				or (f.OpenEntityWindow == true and "off (the event reached the game)" or "STILL ON (the event did not arrive)")))
		end
	end
	if S.refresh > 0 then
		S.refresh = S.refresh - 1
		if S.refresh <= 0 then allowSelector() end
	end
	local a = S.auto
	if a ~= nil then
		a.frames = a.frames + 1
		if H.AUTO_REASSERT[a.frames] then preventSelector() end
	end
	if S.reprevent > 0 then
		S.reprevent = S.reprevent - 1
		if S.reprevent <= 0 and (S.auto ~= nil or S.labels) then preventSelector() end
	end
	local m = S.camManual
	if m ~= nil then
		-- the footer's camera mode: logged when the player leaves it (Esc / back pops the tool natively)
		m.frames = m.frames + 1
		if m.frames > H.ACTIVE_GRACE and freeCamActive() == false then
			S.camManual = nil
			core.log("camera mode: left (button session)")
			H.changed()
		end
	end
	local w = S.watch
	if w ~= nil then
		local paused = pausedNow()
		if w.frames < H.ESCAPE_SETTLE_FRAMES then
			w.frames = w.frames + 1
			w.paused = paused
		elseif paused ~= nil and w.paused ~= nil and paused ~= w.paused then
			escape("pause key")
		end
	end
end

---------------------------------------------------------------------------
-- Exits

--- The pause menu (every quit opens it first): labels back, UI and window shown, at once.
function H.pauseMenu()
	if S.tourWindow or S.tourUi then H.tourHide(false) end
	-- the camera moves stopped first (pm_driver.stopAll -> setAutoHover(false)); this only makes sure
	if S.auto ~= nil then H.setAutoHover(false) end
	if S.labels then try("labels show", function() showLabels("pause menu") end) try("save data", H.persist) end
	S.tourLabels = false
	if S.refresh > 0 then allowSelector() end
	if S.ui ~= nil then H.showUi("pause menu") end
	if S.camManual ~= nil then
		S.camManual = nil
		popFreeCam("pause menu")
	end
	S.toolRefused = false
	if S.tool ~= nil then popTool("pause menu") end
	lockWorld(false, "pause menu")
	H.changed()
end

--- First frame of a game: nothing hidden; labels a save left hidden (autosave while hidden) come back.
function H.start()
	S.labels, S.orig, S.had, S.ui, S.tourWindow, S.tourUi = false, nil, false, nil, false, false
	S.watch, S.tourLabels, S.camManual, S.auto, S.reprevent = nil, false, nil, nil, 0
	-- a new game has a new tool stack: ours is gone with the old one
	S.tool, S.toolGone, S.toolRefused, S.toolCtx = nil, false, false, nil
	-- round 15: a new game has a new game context (filter and features fresh); undone anyway if a lock was left
	if S.lock ~= nil then lockWorld(false, "game start") end
	if S.refresh > 0 then allowSelector() end
	setVisible(H.UI_ROOT, true)
	try("labels recover", function()
		local mine = api.gui.game.getGuiSaveData(core.MOD_ID)
		local m = type(mine) == "table" and mine.hud or nil
		if type(m) ~= "table" or m.hidden ~= true then return end
		local data = baseData()
		local cur = data and data.hudFilter or nil
		if core.isHiddenHudFilter(cur, hudTypes(), hudCarriers()) then
			writeFilter(m.had == true and core.deepCopy(m.orig) or nil)
			refreshSelector()
			core.log("labels: a save made while hidden; the player's filter restored")
		else
			core.log("labels: marker found, the filter was changed since; kept")
		end
		H.persist()
	end)
end

return H
