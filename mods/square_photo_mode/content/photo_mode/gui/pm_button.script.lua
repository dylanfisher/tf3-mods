-- Photo Mode: the top-bar button and the "High graphics mode" switch (plans/square_photo_mode/PLAN.md). The button
-- only opens / closes the Photo Mode window (pm_window.lua); the window's "High graphics mode" checkbox turns every
-- texture / effect / anti-aliasing setting (pm_core.KEYS) to its highest (in stages) and back. Shadows, geometry,
-- terrain and grass are never touched: changing them at runtime crashed the renderer (docs/findings/map-camera.md
-- "Changing render-buffer settings at runtime crashes").
-- Built on the DEV probe mods/square_photo_quality_probe (verified in game, docs/findings/map-camera.md "Graphics settings from a mod: api.util.setAppConfig").
--
-- Everything runs on the GUI Main Thread (plugin onStep, button callbacks, onEvent; docs/findings.md "Timers and
-- threads in GUI contexts"), every api call in pcall. Nothing goes into the simulation; the savegame only gets
-- GUI save data: the window's saved views and setups (pm_window.lua) and, while "Hide labels" is on, the base
-- HUD filter (pm_hud.lua). One setAppConfig call at a time (pm_core gate, "switch" below); crash guards: plans/square_photo_mode/PLAN.md "Crash safety".
--
--   button  click = open / close the window (pressed while open). No graphics change. The open / close itself
--           runs in the next onStep, in a frame with no setAppConfig.
--   window  closing it stops every camera move (pm_driver.stopAll) and KEEPS the highest graphics. While they
--           are on, the button shows it (green contour, tooltip line).
--   HQ on   the window's checkbox (footer): S.hq = "staging"; pm_core.STAGE_DELAY_FRAMES frames later the onStep runs
--           stage 1 (before it: 1. snapshot of the graphics keys, 2. the marker { boosted = true, orig =
--           snapshot } into AppConfig.mainMenuState[modId], its own setAppConfig while the graphics are still the
--           player's own), then stage 2 .. 3, each its own setAppConfig(cfg, false), each logged "hq stage N",
--           STAGE_DELAY_FRAMES frames apart. Then S.hq = "on". Photo Mode never writes settings.lua itself (the
--           mod.io review: no game settings save from a mod); see "marker" below.
--   HQ off  the toggle: further stages dropped, then the staged restore (S.hq = "unstaging"): the stages in
--           reverse (pm_core.RESTORE_STAGES: anti-aliasing and resolution scale first, textures last), one
--           setAppConfig each, STAGE_DELAY_FRAMES apart, the first in the next onStep; the last one also clears
--           the marker. Each logged "hq restore stage N". Why: spread the renderer's work, as on.
--           The pause menu (at once) and a new game ("stale") keep the one-call restore: the snapshot's keys on
--           a copy of the CURRENT config (never the whole old AppConfig: it holds other mods' mainMenuState
--           prefs, audio, keys), marker cleared, one setAppConfig. Toggled on again during
--           the staged restore: the stages run again from stage 1 (keys already high are skipped).
--   Esc     quitting runs no react.onUnmount (docs/findings/gui.md "Quitting runs no react.onUnmount"), but
--           every quit opens the pause menu first: react event "openPauseMenu" stops the camera moves and turns
--           the highest graphics off; the toggle shows off afterwards.
--   marker  lives only in the in-memory AppConfig, set with the same kind of setAppConfig as the stages, before
--           the first boost, and cleared in the restore's last setAppConfig. The game writes settings.lua with
--           whatever the AppConfig holds (at launch, at a normal quit, from the settings page or another mod's
--           settings save), so whenever the boosted values reach the file the marker goes with them; a normal
--           quit after the pause-menu restore writes the player's values with no marker.
--   load    first frame of a game: a marker left by a session that ended boosted (crash, kill) restores the
--           keys still at their boosted value (pm_core.recoverKeys) and is cleared (in memory; the game's next
--           settings write, at the latest the normal quit, puts the repaired values in settings.lua).
--   frames  no window opens or closes in a frame with a setAppConfig of ours (a stage or a toggle restore): the
--           onStep does one or the other, and a stage waits a frame after any window open / close (S.windowTouched).
--           Why: kept as a precaution from before the crash causes were found (docs/findings/map-camera.md
--           "Changing render-buffer settings at runtime crashes"). The pause menu restore is the
--           exception: it can't wait (a quit may follow).
--
-- Log lines start with "[PhotoMode] " (English, never translated).
--
-- Per frame (plugin onStep): window closed and no switch = a few Lua compares, no api call. Window open = the
-- camera driver's step (returns at once while no orbit / tour / glide / drift / follow release runs), timed by
-- SQPERF (pm_perf.lua, section camera_step).
-- While the game UI is hidden: pm_hud's escape hatch reads GAME_SPEED once a frame (the pause key brings the UI
-- back; Esc can't reach a hidden UI root, docs/findings/gui.md). While frozen (Light tab): pm_sky reads it too.
-- The pause menu also restores the Light tab's override and freeze (pm_sky.pauseMenu); a game start repairs a
-- light marker in the save (pm_sky.start, before pm_hud.start, which may rewrite our save data).

local PERF = ug_require "square_photo_mode::/photo_mode/gui/pm_perf.lua"
local perfInit = PERF.perf:start()

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
local window = ug_require "square_photo_mode::/photo_mode/gui/pm_window.lua"
local hud = ug_require "square_photo_mode::/photo_mode/gui/pm_hud.lua"
local sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
-- round 16b: the Foreground items (veil, rain), the added animals and the Lens (each its own module)
local fg = ug_require "square_photo_mode::/photo_mode/gui/pm_foreground.lua"
local animals = ug_require "square_photo_mode::/photo_mode/gui/pm_animals.lua"
local lens = ug_require "square_photo_mode::/photo_mode/gui/pm_lens.lua"
local setups = ug_require "square_photo_mode::/photo_mode/gui/pm_setups.lua"

-- Icon style: white 48x48 mask (camera@2x.tga, tools/render_icon_ridge.py), shown at 24 UI px; the game picks @2x.
local RIDGE_ICON = "square_photo_mode::/photo_mode/gui/camera.tga"

local NSTAGES = #core.STAGES

local S = {
	snapshot = nil, -- the player's graphics values while the highest graphics are (partly) on; nil = theirs
	hq = "off", -- "off" | "staging" (stages running) | "on" | "unstaging" (restore stages running)
	stage = nil, -- next stage to apply while staging (or restore stage while unstaging)
	offWhy = nil, -- why the staged restore runs
	offApplied = 0, -- stages that were on when the staged restore began
	wait = nil, -- frames left before that stage
	hqMs = 0, -- setAppConfig time of the stages so far
	boost = nil, -- the boost values of this switch (MSAA read once at stage 1)
	offRequest = nil, -- the toggle asked for off: run by the next onStep
	windowWanted = false, -- the button's state: the window is (to be) open
	windowOpen = false, -- the window is open (our open, not yet closed by us or the player)
	windowTouched = false, -- a window opened / closed since the last onStep: no stage this frame
	clock = nil,
	styles = nil,
	gate = core.newGate(), -- one switch at a time (pm_core.gateEnter / gateLeave)
	renderErrorLogged = false,
}

local function try(what, fn)
	local ok, err = pcall(fn)
	if not ok then core.log(what .. " ERROR " .. tostring(err)) end
	return ok
end

local function clockMs()
	if S.clock == nil then S.clock = api.type.Clock.new() end
	return S.clock:getTime() / 1000
end

local function nowMs()
	local ok, t = pcall(clockMs)
	return ok and t or 0
end

local function currentConfig()
	return api.type.AppConfig.new(api.util.getAppConfig())
end

local function graphicsOf(cfg)
	return core.snapshot(function(key) return cfg[key] end)
end

--- Copy of the current AppConfig with our mainMenuState marker set (marker table) or cleared (nil).
local function configWithMarker(marker)
	local cfg = currentConfig()
	local mm = core.withMarker(cfg.mainMenuState, marker)
	-- never write back a partial copy: it would wipe other mods' prefs (raises; callers run inside try)
	if mm == nil then error("mainMenuState unreadable, not changed", 0) end
	cfg.mainMenuState = mm
	return cfg
end

--- setAppConfig (in memory only: Photo Mode never writes settings.lua); returns its time in ms.
local function set(cfg)
	local t0 = nowMs()
	api.util.setAppConfig(cfg, false)
	return nowMs() - t0
end

local function apply(cfg, why)
	local ms = set(cfg)
	core.log(string.format("%s ms=%.1f now %s", why, ms, core.text(graphicsOf(api.util.getAppConfig()))))
end

local function maxMsaa()
	local ok, list = pcall(function() return app.getSupportedMSAASampleCounts() end)
	return core.maxOf(ok and list or nil, core.MSAA_FALLBACK)
end

--- Puts the original values on the current config and clears the marker (one setAppConfig).
local function restore(orig, why)
	local cfg = configWithMarker(nil)
	for key, value in pairs(orig) do cfg[key] = value end
	apply(cfg, why)
end

--- The window shows the toggle from S.hq: tell it to render again.
local function windowChanged()
	try("window changed", window.changed)
end

local hqOff

--- Runs one switch (fn) behind the gate. An "off" asked for while a switch runs (an engine callback inside
--- setAppConfig's stall) is kept and run right after it.
local function switch(name, fn, offWhy)
	if not core.gateEnter(S.gate) then
		if offWhy ~= nil then S.gate.pendingOff = offWhy end
		core.log(name .. ": a switch is running, " .. (offWhy ~= nil and "off queued" or "ignored"))
		return
	end
	try(name, fn)
	local pending = core.gateLeave(S.gate)
	if pending ~= nil and S.hq ~= "off" then hqOff(pending) end
end

--- Stage S.stage (stage 1: snapshot and marker first). Skips keys already at their highest; a stage with
--- nothing to change makes no call and the next one follows in the same frame.
local function runStage()
	if S.stage == 1 and S.snapshot == nil then
		local snap = graphicsOf(api.util.getAppConfig())
		core.log("hq on: player's settings " .. core.text(snap))
		-- the marker, set while the graphics are still the player's own: any later settings write carries it
		apply(configWithMarker({ boosted = true, orig = snap }), "hq on: marker")
		S.snapshot = snap
		S.boost = core.boostValues(maxMsaa())
		S.hqMs = 0
	end
	while S.stage <= NSTAGES do
		local i = S.stage
		local cfg = currentConfig()
		local changes, names = core.stageChanges(i, graphicsOf(cfg), S.boost)
		S.stage = i + 1
		if #names > 0 then
			for key, value in pairs(changes) do cfg[key] = value end
			local ms = set(cfg)
			S.hqMs = S.hqMs + ms
			core.log(string.format("hq stage %d/%d keys=%s ms=%.1f", i, NSTAGES, table.concat(names, ","), ms))
			break
		end
		core.log(string.format("hq stage %d/%d keys=- (already highest)", i, NSTAGES))
	end
	if S.stage > NSTAGES then
		S.hq = "on"
		S.stage = nil
		S.wait = nil
		core.log(string.format("hq on: %d stages ms=%.1f now %s", NSTAGES, S.hqMs,
			core.text(graphicsOf(api.util.getAppConfig()))))
	else
		S.wait = core.STAGE_DELAY_FRAMES
	end
end

local function stageNow()
	local ok = try("hq stage " .. tostring(S.stage), runStage)
	if not ok and S.hq == "staging" then
		-- a failed stage: everything back at once (the marker stays if that fails too)
		local snap = S.snapshot
		S.hq, S.stage, S.wait, S.snapshot = "off", nil, nil, nil
		if snap ~= nil then try("hq undo", function() restore(snap, "hq undo") end) end
		windowChanged()
	end
end

local function hqOffNow(why)
	if S.hq == "off" then return end
	local applied = S.hq == "on" and NSTAGES or (S.hq == "unstaging" and S.offApplied or ((S.stage or 1) - 1))
	if S.hq == "unstaging" then why = why .. ", during the staged restore" end
	local snap = S.snapshot
	S.hq, S.stage, S.wait, S.snapshot = "off", nil, nil, nil
	S.offRequest = nil
	windowChanged()
	if snap == nil then
		core.log("hq on cancelled (" .. why .. ") before stage 1")
		return
	end
	-- On failure the marker stays, so the next game load puts the settings back.
	try("hq off(" .. why .. ")", function()
		restore(snap, string.format("hq off(%s) after stage %d of %d", why, applied, NSTAGES))
	end)
end

hqOff = function(why)
	switch("hq off(" .. why .. ")", function() hqOffNow(why) end, why)
end

--- The toggle's off: the staged restore begins (its first stage runs at once, in this onStep). Before stage 1
--- (nothing changed yet) it is a plain cancel.
local function beginUnstage(why)
	S.offRequest = nil
	if S.hq == "off" or S.hq == "unstaging" then return end
	if S.snapshot == nil then hqOff(why) return end
	S.offApplied = S.hq == "on" and NSTAGES or ((S.stage or 1) - 1)
	S.hq, S.stage, S.wait, S.offWhy, S.hqMs = "unstaging", 1, 0, why, 0
	core.log(string.format("hq off(%s) after stage %d of %d: %d restore stages, %d frames apart", why,
		S.offApplied, NSTAGES, NSTAGES, core.STAGE_DELAY_FRAMES))
	windowChanged()
end

--- Restore stage S.stage: the stage's keys back to the player's values; the last one also clears the marker.
--- A stage with nothing to change makes no call (the next follows in the same frame); the last always
--- runs (the marker).
local function runRestoreStage()
	local snap = S.snapshot
	while S.stage <= NSTAGES do
		local i = S.stage
		S.stage = i + 1
		local last = i == NSTAGES
		local cfg = last and configWithMarker(nil) or currentConfig()
		local changes, names = core.restoreChanges(i, graphicsOf(cfg), snap)
		if #names > 0 or last then
			for key, value in pairs(changes) do cfg[key] = value end
			local ms = set(cfg)
			S.hqMs = S.hqMs + ms
			core.log(string.format("hq restore stage %d/%d keys=%s ms=%.1f%s", i, NSTAGES,
				#names > 0 and table.concat(names, ",") or "-", ms, last and " (marker cleared)" or ""))
			if not last then break end
		else
			core.log(string.format("hq restore stage %d/%d keys=- (already the player's)", i, NSTAGES))
		end
	end
	if S.stage > NSTAGES then
		core.log(string.format("hq off(%s) restored in %d stages ms=%.1f now %s", tostring(S.offWhy), NSTAGES,
			S.hqMs, core.text(graphicsOf(api.util.getAppConfig()))))
		S.hq, S.stage, S.wait, S.snapshot, S.offWhy = "off", nil, nil, nil, nil
		windowChanged()
	else
		S.wait = core.STAGE_DELAY_FRAMES
	end
end

local function unstageNow()
	local ok = try("hq restore stage " .. tostring(S.stage), runRestoreStage)
	if not ok and S.hq == "unstaging" then
		-- a failed restore stage: the rest in one call (the marker stays if that fails too)
		hqOffNow(tostring(S.offWhy) .. ", restore stage failed")
	end
end

--- The window's toggle. On: the stages start STAGE_DELAY_FRAMES frames later (the pressed toggle is drawn
--- before the first stall). Off: the restore runs in the next onStep.
local function hqToggle()
	if S.offRequest ~= nil then
		S.offRequest = nil -- clicked again before the off ran: stays on (or goes on staging)
	elseif S.hq == "unstaging" then
		-- on again during the staged restore: the stages run again (keys still high are skipped; the snapshot
		-- and the marker are still those of this boost)
		if S.gate.busy then return end
		S.hq, S.stage, S.wait, S.offWhy = "staging", 1, core.STAGE_DELAY_FRAMES, nil
		core.log("hq on again during the staged restore")
	elseif S.hq == "off" then
		if S.gate.busy then return end
		S.hq = "staging"
		S.stage = 1
		S.wait = core.STAGE_DELAY_FRAMES
		S.offRequest = nil
		core.log(string.format("hq on: %d stages, %d frames apart", NSTAGES, core.STAGE_DELAY_FRAMES))
	else
		S.offRequest = "toggle"
	end
	windowChanged()
end

-- A tour hides our window (and optionally the game UI); the hud tells the window to render when its state changes.
-- A tour starts / ends (pm_driver): our window, the hidden UI root, the labels (pm_hud); "Pause the
-- game during the tour" freezes the game with the Light tab's freeze (pm_sky) and unfreezes it when the tour ends,
-- only if the freeze is still the tour's own (a freeze the player ticked before the tour stays).
local tourFroze = false
driver.onTourHide = function(on, opts)
	try("tour hud", function() hud.tourHide(on, opts) end)
	if on then
		if type(opts) == "table" and opts.pause and not sky.frozen() then
			try("tour pause", function() sky.setFreeze(true, "tour") end)
			tourFroze = sky.frozen()
		end
	elseif tourFroze then
		tourFroze = false
		if sky.frozen() then try("tour unpause", function() sky.setFreeze(false, "tour ended") end) end
	end
end
-- Round 9: hover, tooltips and click-to-select off while an automated camera move runs (pm_hud.setAutoHover).
driver.onAutoMode = function(on) try("auto hover", function() hud.setAutoHover(on) end) end
hud.changed = function() try("window changed", window.changed) end
sky.changed = function() try("window changed", window.changed) end
-- Round 16: saved setups (gui/pm_setups.lua) read High graphics mode and switch it on (never off).
setups.hqOn = function() return S.hq == "staging" or S.hq == "on" end
setups.hqSwitchOn = function()
	if S.hq == "off" or S.hq == "unstaging" or S.offRequest ~= nil then hqToggle() end
end
-- The pause key while the UI is hidden (pm_hud escape hatch): the tour stops (the window and the UI show again).
hud.onEscape = function(why)
	driver.stopTour(why)
end
-- Round 11: the back of our view tool's action (a right click; pm_hud "tool"): the camera move ends (the window
-- and the UI show again through their own hooks). Round 13: the action has a back only while a move runs.
hud.onBack = function(why)
	if not driver.stopMoves(why) then core.log("back (" .. why .. "): nothing to end") end
end

window.hqOn = function() return (S.hq == "staging" or S.hq == "on") and S.offRequest == nil end
window.onHqToggle = hqToggle

-- The player closed the window (X, or Esc closing the top window): camera moves stop; the graphics stay.
window.onUserClose = function()
	S.windowWanted = false
	S.windowOpen = false
	S.windowTouched = true
	try("camera stop", function() driver.stopAll("window") end)
end

--- The top-bar click: the window opens / closes in the next onStep (windowStep).
local function toggleWindow()
	S.windowWanted = not S.windowWanted
end

--- Opens / closes the window to match S.windowWanted. Called only in a frame with no setAppConfig of ours.
local function windowStep()
	if S.windowWanted == S.windowOpen then return end
	S.windowTouched = true
	if S.windowWanted then
		S.windowOpen = true
		if not try("window open", function() window.open() end) then S.windowOpen = false; S.windowWanted = false end
	else
		S.windowOpen = false
		try("camera stop", function() driver.stopAll("window") end)
		try("window close", window.close)
		core.log("window closed (button)")
	end
end

--- Every frame: the toggle's off, then a due stage, else the window's open / close (never both in one frame).
local function frameStep()
	local touched = S.windowTouched
	S.windowTouched = false
	local setThisFrame = false
	if S.offRequest ~= nil then
		-- no further stage; the restore waits a frame after a window open / close
		if not touched then
			beginUnstage(S.offRequest)
			if S.hq == "unstaging" then switch("hq restore stage", unstageNow, nil) end
			setThisFrame = true
		end
	elseif S.hq == "staging" or S.hq == "unstaging" then
		S.wait = (S.wait or 0) - 1
		if S.wait <= 0 then
			if touched then
				S.wait = 1 -- a window opened / closed since the last frame: the stage waits a frame
			elseif S.hq == "staging" then
				switch("hq stage", stageNow, nil)
				setThisFrame = true
			else
				switch("hq restore stage", unstageNow, nil)
				setThisFrame = true
			end
		end
	end
	if not setThisFrame then windowStep() end
end

--- Safety net: a marker left by a session that ended with the highest graphics on (crash, kill -9: every
--- normal quit opens the pause menu first). Only the keys still at the boost value go back; changes the player
--- made since stay.
local function recoverMarker()
	local mm = currentConfig().mainMenuState
	local marker = nil
	if mm ~= nil then
		local okM, m = pcall(function() return mm[core.MOD_ID] end)
		if okM then marker = m end
	end
	if marker == nil then return end
	local orig = core.markerOrig(marker)
	if orig == nil then
		core.log("marker without original values, clearing")
		apply(configWithMarker(nil), "marker clear")
		return
	end
	local put, kept = core.recoverKeys(orig, graphicsOf(api.util.getAppConfig()), core.boostValues(maxMsaa()))
	core.log(string.format("marker found: restoring %s | kept (not at the highest) %s", core.text(put),
		#kept > 0 and table.concat(kept, ",") or "-"))
	restore(put, "recover")
end

--- First frame of every mount (every game load). S lives as long as this Lua state; a snapshot still set here
--- means an earlier mount ended without the pause menu, so it is put back first.
local function start()
	try("start log", function() core.log("start: " .. core.text(graphicsOf(api.util.getAppConfig()))) end)
	S.gate = core.newGate() -- a switch can't still run at a mount; a stuck gate must not lock the toggle
	S.offRequest = nil
	if S.hq ~= "off" then hqOff("stale") end
	S.windowWanted, S.windowOpen, S.windowTouched = false, false, false
	try("camera reset", function() driver.stopAll("new game") end)
	try("round 16b reset", function() fg.reset() animals.reset() lens.reset() end)
	window.resetGame()
	-- round 16: this save's last setup before anything rewrites our save data (it is written with the markers)
	try("setups start", setups.start)
	-- the light marker first: hud.start may rewrite our save data (with the current, empty light marker)
	try("light start", sky.start)
	try("hud start", hud.start)
	try("recover", recoverMarker)
end

local function styles()
	if S.styles == nil then
		-- Icon ToggleButton: only its size inline, 8 px padding around the 24 px icon (a 40 px tile like the
		-- layers button and our other top-bar buttons). Tile, pressed / hover states and the white icon come from
		-- the base ToggleButton rules (builtin.css.lua:138-240); no inline colour on the tile or icon (it would
		-- override them). While the highest graphics are on, the button's contour (the base border image,
		-- invisible except on hover) is drawn in the base Ok green, as Supply Gaps shows its overlay
		-- (plans/ui_style/PLAN.md "Top-bar buttons").
		local toggleButton = api.gui.StyleSheet.new()
		toggleButton.padding = api.type.Vec4f.new(8, 8, 8, 8)
		local okC, green = pcall(function()
			return api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data.Ok
		end)
		local toggleButtonHq = styleutil.makeStyle{ borderColor = okC and green or { 0.45, 0.85, 0.55, 1.0 } }
		toggleButtonHq.padding = api.type.Vec4f.new(8, 8, 8, 8)
		S.styles = {
			toggleButton = toggleButton,
			toggleButtonHq = toggleButtonHq,
			icon = styleutil.makeStyle{ size = { 24, 24 } },
		}
	end
	return S.styles
end

local PhotoModePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension,
	"PhotoModePlugin", function()
	-- Hooks first, unconditionally.
	local startedRef = react.useRef(false)
	local openState = react.useState(S.windowWanted)
	local hqState = react.useState(S.hq == "staging" or S.hq == "on")
	-- Read once per render; the callbacks below compare these Lua upvalues, so a frame with nothing going on
	-- makes no react / api call. A set() re-renders, which reads them again.
	local started = startedRef:get() == true
	local shownOpen = openState:old() == true
	local shownHq = hqState:old() == true
	local function sync()
		local open = S.windowWanted
		if open ~= shownOpen then
			shownOpen = open
			-- an expired state (unmounted plugin) logs a traceback on set (docs/findings/gui.md)
			if not openState:hasExpired() then openState:set(open) end
		end
		local hq = S.hq == "staging" or S.hq == "on"
		if hq ~= shownHq then
			shownHq = hq
			if not hqState:hasExpired() then hqState:set(hq) end
		end
	end
	react.onStep(function()
		if not started then
			started = true
			if not startedRef:hasExpired() then startedRef:set(true) end
			try("start", start)
		end
		if S.offRequest ~= nil or S.hq == "staging" or S.hq == "unstaging" or S.windowWanted ~= S.windowOpen
			or S.windowTouched then
			try("frame", frameStep)
		end
		if hud.busy() then try("hud step", hud.step) end
		if sky.busy() then try("light step", sky.stepFrame) end
		if fg.busy() then try("foreground step", fg.step) end
		if animals.busy() then try("animals step", animals.step) end
		if S.windowOpen or driver.busy() then
			local t = PERF.perfStep:start()
			try("camera step", driver.step)
			PERF.perfStep:stop("camera_step", t)
		end
		sync()
	end)
	react.onEvent("openPauseMenu", function()
		-- the safe point before any quit, save or settings page: at once, not in the next frame
		-- round 16: the picture as it is now becomes the last setup, before anything is put back
		local kept = false
		try("setups capture", function() kept = setups.capture("pause menu") end)
		try("camera stop", function() driver.stopAll("pause menu") end)
		try("foreground pause menu", function() fg.stopAll("pause menu") end) -- before pm_sky puts values back
		if S.hq ~= "off" then hqOff("pause menu") end
		try("hud pause menu", hud.pauseMenu)
		try("light pause menu", sky.pauseMenu)
		if kept then
			try("setups status", function()
				driver.setStatus(_("The menu put your own light, weather and look back. Settings > Restore last setup brings this picture back."))
			end)
		end
		sync()
	end)
	-- The game's follow / cockpit camera ended by itself (base gui/main/free_cam_options.tl).
	react.onEvent("stoppedFollowAction", function()
		try("follow ended", driver.followEnded)
	end)

	local open, hq = shownOpen, shownHq
	local tooltip = hq
		and _("Photo Mode: a window to find and frame your shot,\nwith a high graphics mode for screenshots.\nHigh graphics mode: on.")
		or _("Photo Mode: a window to find and frame your shot,\nwith a high graphics mode for screenshots.")
	-- The button is built in pcall: an error thrown in a render takes the UI down ("Script component root
	-- failed"). On a failure a plain text button (the same toggle) stands in, logged once.
	local function onClick()
		try("toggle window", toggleWindow)
		sync()
	end
	local okB, button = pcall(function()
		-- always the icon (round 21, the user: no mod settings but the debug one; the Text style is gone)
		return builtin.ToggleButton{
			meta = { class = "sqpm-ridge-icon-button", tooltip = tooltip,
				styleSheet = hq and styles().toggleButtonHq or styles().toggleButton },
			content = builtin.ImageView{
				meta = { class = "sqpm-ridge-icon", styleSheet = styles().icon },
				path = RIDGE_ICON,
			},
			value = open and 1 or 0,
			onValueChange = function(__) onClick() end,
		}
	end)
	if not okB then
		if not S.renderErrorLogged then
			S.renderErrorLogged = true
			core.log("button render ERROR " .. tostring(button))
		end
		button = builtin.Button{
			content = builtin.TextView{ text = hq and _("Photo: HQ") or _("Photo") },
			onClick = onClick,
		}
	end
	-- A plugin recipe's root must be a layout (MainModButtonArea mounts plugins as BoxLayout children).
	return builtin.BoxLayout{
		meta = { class = "sqpm-ridge" },
		orientation = builtin.type.Orientation.Horizontal,
		children = { button },
	}
end)

PERF.perf:phase("init", perfInit)

-- .script.lua resources expose their exports through data(), not a return value
function data()
	return {
		PhotoModePlugin = PhotoModePlugin,
	}
end
