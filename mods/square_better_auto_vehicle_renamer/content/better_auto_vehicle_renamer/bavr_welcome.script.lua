-- Better Auto Vehicle Renamer first-load welcome (PLAN.md "First load of a save", "Phase 3"; the pattern of
-- square_smart_lanes sl_bg.script.lua): an invisible root mounted with the game UI (bavr_welcome.res.lua) whose
-- react.onStepTimer (about once a second, a worker thread) joins one tick onto the main thread while the welcome is
-- undecided: the game-script state is read a few seconds after the game is up (bavr_welcome.lua Welcome.tick), and
-- then never again in this load. No per-frame work (no onStep); after the decision the timer only returns.
-- It opens a small native window once per save when the state holds no answer and the save has vehicles: what the
-- mod does (an example under the current settings), a ticked base CheckBox "Number your N existing vehicles, oldest
-- first", the base info hint "Save your game first ...", and [Apply] [Not now]; closing the window is Not now. The
-- same window shows for "Number existing vehicles on next load" = Yes after a Not now, and, while Destination
-- Displays is active, a one-line notice with [OK] (once per save). The answer goes to the game script as an event
-- (bavr_game.lua handleEvent, op=welcome / sdseen). The same tick sends the full type words in the player's language
-- (op=words) when the state holds other ones: the game script's own _() is unverified (docs/findings/scripting.md).
-- Base builtin widgets and inline styles only (no stylesheet rule: docs/ui-guide.md). Log: welcome op=show | done |
-- skip reason= (here), welcome op=answer (the game script).
-- Exports through data().

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local modEntryPoint = ug_require "::/gui/main/mod_entry_point.tl"
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local content_card = ug_require "::/gui/main/content_card.tl"
-- (pcall: base GUI modules differ by platform, see infoHint below)
local okGru, gui_react_util = pcall(ug_require, "::/gui/main/gui_react_util.tl")
if not okGru or type(gui_react_util) ~= "table" then gui_react_util = {} end

local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
local Welcome = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_welcome.lua"
local Game = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_game.lua"

local errors = 0
local function emit(text)
	pcall(function() log.message(Game.TAG .. " " .. text) end)
end
local function fail(where, e)
	if errors >= 3 then return end
	errors = errors + 1
	emit("error where=" .. where .. " err=" .. tostring(e))
end

-- the welcome of this load: W.phase (Welcome.tick), W.kind, W.read; cfg and the translated words, made on the
-- first tick
local W = Welcome.new()
local G = { cfg = nil, words = nil, wordsDone = false, logged = false, answered = false }

local function translatedWords()
	return { B = _("Bus"), T = _("Truck"), R = _("Tram"), L = _("Train"), S = _("Ship"), A = _("Aircraft"),
		H = _("Helicopter"), O = _("(old)") }
end

--- readFn of Welcome.tick: the game-script state's fields (state_native:find, the GUI-side read the base game
--- uses; never a full copy), { editor = true } in the map editor, nil while unreadable.
local function readState()
	local okP, all = pcall(function() return api.engine.config.getModParams() end)
	if okP and type(all) == "table" and type(all[""]) == "table" and all[""].isMapEditor == true then
		return { editor = true }
	end
	local e = api.engine.system.gameScriptSystem.getEntityForGameScript(Game.GS_NAME)
	if e == nil or e < 0 then return nil end
	local gs = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
	if gs == nil then return nil end
	local native = gs.state_native
	if native == nil then return nil end
	local r = { ver = native:find("ver"), welcome = native:find("welcome"), count = native:find("count"),
		standDown = native:find("standDown"), sdSeen = native:find("sdSeen") }
	r.pass = native:find("pass") ~= nil and {} or nil
	local w = native:find("words")
	if w ~= nil then
		local okW, t = pcall(function() return w:asTable() end)
		r.words = okW and t or nil
	end
	return r
end

local function sendEvent(payload)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", Game.EVENT_ID, Game.EV, payload))
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

-- text lines are broken with "\n" in code: a TextView wraps only with a textAutoWrap stylesheet rule (none of ours:
-- rule cap), and the dialog stops growing at its max width (square_smart_lanes rev 9: "...more waiti")
local function line(text)
	return builtin.TextView{ meta = { class = "font-scale-body" }, text = Welcome.wrapLine(text, Welcome.WRAP_COLS) }
end

-- The base info hint, when this platform has it (the PS5 content_card has no makeInfoHint: square_smart_lanes rev 9,
-- docs/findings/gui.md "Base GUI modules differ by platform"); else the base hint's tree without the icon.
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
				builtin.TextView{ meta = { class = "font-scale-body, info-hint-text, no-icon" },
					text = Welcome.wrapLine(text, Welcome.WRAP_COLS) },
			},
		},
	}
end

local BavrWelcomeWindow -- set below (the Window wrapper)

local function closeWindow()
	pcall(function()
		local wa = game_react_globals.getDefaultWindowApi()
		if wa ~= nil then wa.removeAllWindows(BavrWelcomeWindow) end
	end)
end

--- Sends the answer once (Apply or Not now; closing the window is Not now; the stand-down notice: seen) and closes
--- the window.
local function answer(kind, button, number)
	if G.answered then return end
	G.answered = true
	local ok, e = pcall(function()
		if kind == "standDown" then
			sendEvent(Welcome.sdSeenPayload())
		else
			sendEvent(Welcome.payload(button, number))
		end
	end)
	if not ok then fail("answer", e) end
	closeWindow()
end

local function button(label, class, tip, onClick)
	return builtin.Button{
		meta = { class = class, tooltip = tip },
		content = line(label),
		onClick = onClick,
	}
end

local BavrWelcome = react.RegisterRecipe("BavrWelcome", function(_param)
	local number = react.useState(1)
	local S = wstyles()
	local kind = W.kind
	local cfg = G.cfg or Settings.parse(nil, translatedWords())
	-- Gamepad (PS5: no X on the window; a window without the focus gets no controller input; square_smart_lanes'
	-- welcome): the content takes the focus when it mounts, and the back button (IA_MENU_BACK) answers Not now
	if type(react.useInputAction) == "function" and type(react.iaHandler) == "function" then
		react.useInputAction("IA_MENU_BACK", react.iaHandler(function() answer(kind, "later", false) end))
	end
	if type(react.useSelfRef) == "function" and type(react.onMount) == "function" then
		local selfRef = react.useSelfRef()
		react.onMount(function()
			local okFocus, e = pcall(function() selfRef:get():focus() end)
			if not okFocus then fail("welcome_focus", e) end
		end)
	end
	local rows
	if kind == "standDown" then
		rows = {
			line(_("Destination Displays is active. It names vehicles too, so Better Auto Vehicle Renamer renames nothing while it is active.")),
			spacer(S.wide),
			builtin.BoxLayout{
				orientation = builtin.type.Orientation.Horizontal,
				children = { button(_("OK"), "primary", nil, function() answer(kind, "later", false) end) },
			},
		}
	else
		local count = W.read ~= nil and tonumber(W.read.count) or 0
		rows = {}
		local function add(node) rows[#rows + 1] = node end
		if kind == "renumber" then
			add(line(_("You asked to number the existing vehicles on this load.")))
			add(spacer(S.gap))
		end
		add(line(string.format(_("Every vehicle gets a fleet number and its model name, like %s."), Welcome.example(cfg))))
		add(spacer(S.gap))
		add(line(_("New vehicles get their number when you buy them.")))
		if not cfg.takeOver then
			add(spacer(S.gap))
			add(line(_("Names you typed yourself are kept.")))
		end
		add(spacer(S.wide))
		add(builtin.CheckBox{
			meta = { tooltip = _("They are numbered in the order they were bought.") },
			value = number:old(),
			onValueChange = function(v) number:set(v == 1 and 1 or 0) end,
			label = Welcome.wrapLine(string.format(_("Number your %d existing vehicles, oldest first"), count),
				Welcome.WRAP_COLS),
		})
		add(spacer(S.wide))
		add(infoHint(_("Save your game first, so you can go back if you change your mind.")))
		add(spacer(S.wide))
		add(builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				button(_("Apply"), "primary",
					_("Numbers the existing vehicles when the box is ticked.\nNew vehicles get numbers either way."),
					function() answer(kind, "apply", number:old() == 1) end),
				spacer(S.hgap),
				button(_("Not now"), "secondary",
					_("Leaves the existing vehicles as they are; only new\nvehicles get numbers. To number them later, set \"Number\nexisting vehicles on next load\" to Yes in the mod settings."),
					function() answer(kind, "later", false) end),
			},
		})
	end
	-- d-pad moves the focus between the box and the buttons (square_smart_lanes' welcome); a child, since the
	-- recipe's root must stay a layout
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
-- spare Window param object; a field the platform rejects is left out (square_smart_lanes sl_bg.script.lua).
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

-- Centered as the base dialogs: the base classes "popover, dialog" (no rule of ours); never an inline style on the
-- Window (that crashed the game: docs/findings/map-camera.md "Full-screen overlay window crashed").
BavrWelcomeWindow = react.RegisterWrapperRecipe("BavrWelcomeWindow", builtin.Window, function(params)
	return builtin.Window(platformWindow{
		meta = { class = "popover, dialog" },
		id = "square_better_auto_vehicle_renamer_welcome",
		title = _("Better Auto Vehicle Renamer"),
		closable = true,
		movable = true,
		autoFocusOnBecomingVisible = true,
		onClose = params.onClose,
		content = BavrWelcome{ meta = { forceFocusable = true } },
	})
end)

--- One welcome tick (main thread, joined from the timer).
local function welcomeTick()
	if G.cfg == nil then
		G.words = translatedWords()
		local okP, all = pcall(function() return api.engine.config.getModParams() end)
		G.cfg = Settings.parse(okP and type(all) == "table" and all[Settings.MOD_ID] or nil, G.words)
	end
	local phase = Welcome.tick(W, readState, G.cfg)
	-- the full type words in the player's language, once per load when the state holds other ones
	if not G.wordsDone and W.read ~= nil and W.read.ver ~= nil then
		G.wordsDone = true
		if Welcome.wordsDiffer(W.read.words, G.words) then
			local ok, e = pcall(sendEvent, Welcome.wordsPayload(G.words))
			if not ok then fail("words", e) end
		end
	end
	if phase == "show" then
		local wa = game_react_globals.getDefaultWindowApi()
		if wa == nil then
			W.phase, W.reason = "skip", "no_window_api"
		else
			local kind = W.kind
			wa.addSingletonWindow(BavrWelcomeWindow, { onClose = function() answer(kind, "later", false) end })
			wa.moveSingletonWindowToFront(BavrWelcomeWindow)
			emit(string.format("welcome op=show kind=%s count=%s tries=%d", tostring(kind),
				tostring(W.read ~= nil and W.read.count or nil), W.tries))
			G.logged = true
		end
	end
	if (W.phase == "done" or W.phase == "skip") and not G.logged then
		G.logged = true
		emit(string.format("welcome op=%s reason=%s tries=%d", W.phase, tostring(W.reason), W.tries))
	end
end

local BavrWelcomeEntry = react.RegisterPluginRecipe(modEntryPoint.ModEntryPointExtension, "BavrWelcomeEntry", function()
	-- worker thread: only decide whether a tick is due, then join it onto the main thread (window, state read)
	react.onStepTimer(function()
		if W.phase ~= "wait" and G.logged then return end
		react.enqueueJoin(function()
			local ok, e = pcall(welcomeTick)
			if not ok then
				W.phase, G.logged = "done", true
				fail("welcome", e)
			end
		end, "BAVR:welcome")
	end, 1.0)
	return builtin.BoxLayout{ children = {} }
end)

function data()
	return {
		BavrWelcomeEntry = BavrWelcomeEntry,
	}
end
