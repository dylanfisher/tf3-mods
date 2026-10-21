-- Smart Lanes background step (rev 8, user 2026-10-14: "Re-time keeps running when the menu closes"): an invisible
-- root mounted with the game UI (::ModEntryPointExtension, base gui/main/game.tl:73-93; the pattern of
-- square_passenger_destinations paxdest_eow.script.tl PaxDestEntry), whose react.onStep (Main Thread, every frame)
-- calls the tool controller's C.bgStep (sl_toolcore.lua). bgStep does nothing while the tool's own step runs, so the
-- Re-time measurements, their writes and probes go on when the tool is closed; with none it returns at once. The
-- controller lives in the shared state (sl_toolstate.lua), set by the tool script once the tool was opened: in the
-- same Lua state as this plugin (unverified in game: TESTING.md "RT" step 9; RETIME op=bg in the log says it ran).
-- Otherwise this steps nothing and a run pauses while the tool is closed (sl_retimer extends its window by the gap).
-- Step B (RETIME_PLAN.md "Step B", "Keep timing adjusted"): the same onStep also steps the automatic re-timing runtime
-- (sl_autoretime.lua, g.auto, made here on the first frame, so it runs whether or not the tool was ever opened): the
-- standing queues on the enrolled junctions' approaches are counted in a snapshot every 2 game min and the junctions
-- re-timed now and then from their averages (step B v4); idle (nothing enrolled, or Automatic light timing Off) it only
-- reads the saved list now and then (sl_autoretime.lua "Idle"). It is told when the player builds (the base construction
-- menu's "constructionMenuActive" event, construction.tl:5060-5080, heard by any recipe, and the cursor's terrain
-- position while it is open, unless the open tool is Smart Lanes' own), and asks the tool's controller whether a
-- proposal of the tool is pending (writes wait) or the tool's own Re-time measures (no snapshot starts meanwhile).
-- The first-load welcome (PLAN.md "Automatic timing for all lights + first-load welcome"; sl_allmode.lua): the same
-- onStep reads the game-script state a few seconds after the game is up (AllMode.welcomeStep) and, in a save whose
-- state holds no answer yet (wel; new games included, never in the map editor), opens a small native window once: a
-- few lines on what Smart Lanes does, two ticked base CheckBoxes ("Smart lanes at all existing junctions", "Keep timing
-- adjusted at all traffic lights"), the base info hint "Save your game first ...", and [Apply] [Not now]. The answer
-- goes to the game script (SmartLanes.auto op=welcome; closing the window counts as Not now): asked once per save.
-- Base builtin widgets and inline styles only (no stylesheet rule: docs/ui-guide.md). Log: WELCOME op=show | skip
-- reason=unreadable (here), WELCOME op=answer ... (the game script).
-- Exports through data() like every .script.lua of this mod.

-- SQPERF (plans/sqperf/README.md): section auto = one frame of the automatic re-timing runtime (ctx bg); its parts
-- as auto_mirror / auto_new / auto_list / auto_snap / auto_write / auto_looks / auto_flush (sl_autoretime R.step).
local sqperf = ug_require "square_smart_lanes::/sqperf/square_smart_lanes.lua"
local perf = sqperf.new({ mod = "square_smart_lanes", ctx = "bg", paramKey = "sqperf_log", first = { "auto" } })

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local modEntryPoint = ug_require "::/gui/main/mod_entry_point.tl"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local g = ug_require "square_smart_lanes::/smart_lanes/sl_toolstate.lua"
local AutoRetime = ug_require "square_smart_lanes::/smart_lanes/sl_autoretime.lua"
local Auto = ug_require "square_smart_lanes::/smart_lanes/sl_auto.lua"
local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local content_card = ug_require "::/gui/main/content_card.tl"
-- (pcall: base GUI modules differ by platform, see infoHint below)
local okGru, gui_react_util = pcall(ug_require, "::/gui/main/gui_react_util.tl")
if not okGru or type(gui_react_util) ~= "table" then gui_react_util = {} end

local errors = 0

local function emit(kind, fields)
	pcall(function() log.message(Rules.line(kind, fields)) end)
end

--- The automatic re-timing runtime of this Lua state (shared with the tool through g when they share it).
local function autoRt()
	if g.auto == nil then
		g.auto = AutoRetime.new(api, emit, nil, {
			perf = perf, -- its parts as sections auto_* (the whole frame: auto, below)
			toolBusy = function(node)
				local c = g.core
				if c == nil or c.autoBusy == nil then return false end
				local ok, b = pcall(c.autoBusy, node)
				return ok and b == true
			end,
			-- any of the tool's Re-time runs measures (C.rtMeasuring; none running: false at once)
			manualBusy = function()
				local c = g.core
				if c == nil or c.rtMeasuring == nil then return false end
				local ok, b = pcall(c.rtMeasuring)
				return ok and b == true
			end,
			-- the tool's status reads our timing writes at once (Smart lights: ours vs the player's)
			lastSent = function(records)
				local c = g.core
				if c ~= nil and c.noteLast ~= nil then pcall(c.noteLast, records) end
			end,
		})
	end
	return g.auto
end

local menuActive = false
local seenSteps = nil

---------------------------------------------------------------------------
-- The first-load welcome

local welcome = AllMode.newWelcome()
local welcomeAnswered = false

--- readFn of AllMode.welcomeStep: readable, the saved answer (wel), the map editor.
local function readWelcome()
	local okP, all = pcall(function() return api.engine.config.getModParams() end)
	if okP and AllMode.isMapEditor(all) then return true, nil, true end
	local _, list, extra = Auto.readSaved(api, nil)
	if list == nil then return false, nil, false end
	return true, type(extra) == "table" and extra.wel or nil, false
end

local welcomeStyles = nil
local function wstyles()
	if welcomeStyles == nil then
		-- padding on a Component, never on a layout or the Window (docs/ui-guide.md "Spacing"); gaps are spacers
		local root = api.gui.StyleSheet.new()
		root.padding = api.type.Vec4f.new(8, 8, 8, 8)
		welcomeStyles = {
			root = root,
			gap = styleutil.makeStyle{ size = { 1, 6 } },
			wide = styleutil.makeStyle{ size = { 1, 12 } },
			hgap = styleutil.makeStyle{ size = { 6, 1 } },
		}
	end
	return welcomeStyles
end

local function spacer(style)
	return builtin.Component{ meta = { styleSheet = style }, layout = builtin.BoxLayout{ children = {} } }
end

-- The window's text lines don't wrap by themselves (TextView wraps only with a textAutoWrap stylesheet rule, none of
-- ours: rule cap) and the dialog window stops growing at its max width, so a long line was cut off (user 2026-10-16:
-- "...more waiti"). AllMode.wrapLine breaks them with "\n" (a base TextView shows it as a new line,
-- make_entity_debug_panel.tl:486) at WRAP_COLS columns.
local WRAP_COLS = 50
local function line(text)
	return builtin.TextView{ meta = { class = "font-scale-body" }, text = AllMode.wrapLine(text, WRAP_COLS) }
end

-- The base info hint, when this platform has it. The PS5 build's content_card has no makeInfoHint (player report
-- 2026-10-19, rev 9: "attempt to call field 'makeInfoHint' (a nil value)" reloaded the UI; docs/findings/gui.md
-- "Base GUI modules differ by platform"): then the base hint's own tree (content_card.tl:479-497) without the icon
-- image, whose texture may be missing there too. Its base classes style it where they exist; plain text otherwise.
local function infoHint(text)
	local make = content_card.makeInfoHint
	if type(make) == "function" then
		local ok, node = pcall(make, text, true)
		if ok and node ~= nil then return node end
	end
	return builtin.Component{
		meta = { class = "info-hint-comp" },
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.TextView{ meta = { class = "font-scale-body, info-hint-text, no-icon" }, text = AllMode.wrapLine(text, WRAP_COLS) },
			},
		},
	}
end

local SmartLanesWelcomeWindow -- set below (the Window wrapper)

--- Sends the answer once (Apply or Not now; closing the window is Not now) and closes the window.
local function answerWelcome(answer, lanes, lights)
	if welcomeAnswered then return end
	welcomeAnswered = true
	pcall(function()
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", Auto.EVENT_ID, Auto.EV_AUTO,
			AllMode.welcomePayload(answer, lanes, lights)))
	end)
	pcall(function()
		local wa = game_react_globals.getDefaultWindowApi()
		if wa ~= nil then wa.removeAllWindows(SmartLanesWelcomeWindow) end
	end)
end

local SmartLanesWelcome = react.RegisterRecipe("SmartLanesWelcome", function(_param)
	local lanes = react.useState(1)
	local lights = react.useState(0) -- opt-in: the light timing box starts unticked
	local S = wstyles()
	-- Gamepad (PS5: the window has no X there, and a window without the focus gets no controller input; LMP rev 8,
	-- docs/findings/gui.md "Gamepad windows"): as the base popover (popover_react_util.tl:8-15) the content is
	-- focusable (meta.forceFocusable, set by the window), takes the focus when it mounts, and the back button
	-- (IA_MENU_BACK: Circle / B / Esc) answers Not now
	-- (each piece only where this platform's react has it: the same hooks every render)
	if type(react.useInputAction) == "function" and type(react.iaHandler) == "function" then
		react.useInputAction("IA_MENU_BACK", react.iaHandler(function() answerWelcome("later", false, false) end))
	end
	if type(react.useSelfRef) == "function" and type(react.onMount) == "function" then
		local selfRef = react.useSelfRef()
		react.onMount(function()
			local okFocus, e = pcall(function() selfRef:get():focus() end)
			if not okFocus and errors < 3 then
				errors = errors + 1
				emit("ERROR", { { "where", "welcome_focus" }, { "err", tostring(e) } })
			end
		end)
	end
	local function box(label, tip, state)
		return builtin.CheckBox{
			meta = { tooltip = tip },
			value = state:old(),
			onValueChange = function(v) state:set(v == 1 and 1 or 0) end,
			label = label,
		}
	end
	local rows = {
		line(_("Smart Lanes sets up the lanes of each junction you build.")),
		spacer(S.gap),
		line(_("To change one junction, use the Smart Lanes tool (Roads, Tools).")),
		spacer(S.gap),
		line(_("Automatic light timing gives more green to roads with more waiting cars.")),
		spacer(S.wide),
		line(_("For what is already on this map:")),
		spacer(S.gap),
		box(_("Convert all existing junctions to Smart Lanes"),
			_("Junctions you edited by hand stay as they are.\nNo traffic lights are added or removed."), lanes),
		spacer(S.gap),
		box(_("Switch all traffic lights to automatic timing"),
			_("Also lights you build later. To leave one out,\nchoose No in the Smart Lanes tool."), lights),
		spacer(S.wide),
		infoHint(_("Save your game first, so you can go back if you change your mind.")),
		spacer(S.wide),
		builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.Button{
					meta = { class = "primary", tooltip = _("Applies the ticked options.") },
					content = line(_("Apply")),
					onClick = function()
						answerWelcome("apply", lanes:old() == 1, lights:old() == 1)
					end,
				},
				spacer(S.hgap),
				builtin.Button{
					meta = { class = "secondary",
						tooltip = _("Changes nothing. This window will not show again in this game.") },
					content = line(_("Not now")),
					onClick = function() answerWelcome("later", false, false) end,
				},
			},
		},
	}
	-- d-pad moves the focus between the boxes and the buttons (as the base mission end window,
	-- mission_framework_react.tl:823-826); a child, since the recipe's root must stay a layout
	local body = builtin.Component{
		meta = { styleSheet = S.root },
		layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = rows },
	}
	if type(gui_react_util.FocusTraversalScope) == "function" then
		body = gui_react_util.FocusTraversalScope{
			horizontal = true,
			vertical = true,
			layout = builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = { body } },
		}
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = { body } }
end)

-- Window fields differ by platform: PS5 rejects `closable` (docs/findings/gui.md). Each field is tried once on a
-- spare Window param object; a field the platform rejects is left out (as square_photo_mode pm_window.lua).
local windowFieldOk = {}
local function platformWindow(p)
	for k, v in pairs(p) do
		if k ~= "content" and k ~= "header" and k ~= "meta" then
			local key = k .. "=" .. (type(v) == "boolean" and tostring(v) or type(v))
			if windowFieldOk[key] == nil then
				local made, ud = pcall(function() return api.gui.react.params.builtin.Window.new() end)
				windowFieldOk[key] = not made or pcall(function() ud[k] = v end)
			end
			if not windowFieldOk[key] then p[k] = nil end
		end
	end
	return p
end

-- Centered as the base game's own dialogs: the base classes "popover, dialog" (dialog_react_util.tl DialogWindow;
-- popover_react_util.css.lua "Window!popover!dialog": anchorPoint and gravity 0.5, size 440 wide) center it on
-- screen with no rule of ours. Never an inline style on the Window: that crashed the game (2026-10-16,
-- docs/findings/map-camera.md "Full-screen overlay window crashed").
SmartLanesWelcomeWindow = react.RegisterWrapperRecipe("SmartLanesWelcomeWindow", builtin.Window, function(params)
	return builtin.Window(platformWindow{
		meta = { class = "popover, dialog" },
		id = "square_smart_lanes_welcome",
		title = _("Smart Lanes"),
		closable = true,
		movable = true,
		-- the base vehicle store and mission end windows (vehicle_store_window.tl:4611-4623)
		autoFocusOnBecomingVisible = true,
		onClose = params.onClose,
		content = SmartLanesWelcome{ meta = { forceFocusable = true } },
	})
end)

--- One frame of the welcome (AllMode.welcomeStep): opens the window once when the save has no answer.
local function welcomeFrame()
	local phase = AllMode.welcomeStep(welcome, readWelcome)
	if phase == "show" then
		local wa = game_react_globals.getDefaultWindowApi()
		if wa == nil then
			emit("WELCOME", { { "op", "skip" }, { "reason", "no_window_api" } })
			return
		end
		wa.addSingletonWindow(SmartLanesWelcomeWindow, { onClose = function() answerWelcome("later", false, false) end })
		wa.moveSingletonWindowToFront(SmartLanesWelcomeWindow)
		emit("WELCOME", { { "op", "show" } })
	elseif phase == "skip" and not welcome.logged then
		welcome.logged = true
		emit("WELCOME", { { "op", "skip" }, { "reason", tostring(welcome.reason) } })
	end
end

local SmartLanesBackground = react.RegisterPluginRecipe(modEntryPoint.ModEntryPointExtension, "SmartLanesBackground", function()
	react.onEvent("constructionMenuActive", function(_name, param)
		menuActive = type(param) == "table" and param.active == true
	end)
	react.onStep(function()
		local c = g.core
		if c ~= nil and c.bgStep ~= nil then
			local ok, e = pcall(c.bgStep)
			if not ok and errors < 3 then
				errors = errors + 1
				emit("ERROR", { { "where", "bg_step" }, { "err", tostring(e) } })
			end
		end
		-- step B: the player building nearby (the construction menu open with another tool than ours), then a frame of
		-- the runtime
		local okA, eA = pcall(function()
			local rt = autoRt()
			local steps = c ~= nil and c.toolSteps or nil
			local ownTool = steps ~= nil and seenSteps ~= nil and steps ~= seenSteps
			seenSteps = steps
			-- (idle: no write to hold, so no cursor read either)
			if menuActive and not ownTool and not rt.idle() then
				local okP, x, y = pcall(function()
					if not api.gui.mouse.hasTerrainPosition() then return nil end
					local p = api.gui.mouse.getTerrainPosition()
					return p.x, p.y
				end)
				if okP and x ~= nil then rt.setBuild(true, x, y) end
			end
			local t0 = perf:start()
			rt.step()
			perf:stop("auto", t0)
		end)
		if not okA and errors < 3 then
			errors = errors + 1
			emit("ERROR", { { "where", "auto_bg" }, { "err", tostring(eA) } })
		end
		-- the first-load welcome (cheap: a counter until it decides, then nothing)
		if welcome.phase == "wait" or welcome.phase == "show" or (welcome.phase == "skip" and not welcome.logged) then
			local okW, eW = pcall(welcomeFrame)
			if not okW then
				welcome.phase = "done"
				if errors < 3 then
					errors = errors + 1
					emit("ERROR", { { "where", "welcome" }, { "err", tostring(eW) } })
				end
			end
		end
	end)
	return builtin.BoxLayout{ children = {} }
end)

function data()
	return {
		SmartLanesBackground = SmartLanesBackground,
	}
end
