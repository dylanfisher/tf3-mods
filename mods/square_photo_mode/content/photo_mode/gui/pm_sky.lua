-- Photo Mode: the Light tab's light and weather override and the freeze (GUI thread only: window clicks, the
-- plugin's onStep and its openPauseMenu event). Pure part and the state it reads / sets: ../pm_light.lua.
-- PLAN: plans/square_photo_mode/PLAN.md "Phase 3: Light & weather".
--
--   override  the first change (a preset, a step button, or ticking "Light & weather override") snapshots the
--             player's time, time cycle, cloud cover, weather cycle, day of year and sun rotation, switches both
--             cycles to Constant (the widget's "Custom", so the game's own cycles don't fight our values) and
--             writes the marker into our GUI save data (pm_window's save, field `light`). Calls as the base
--             Weather & Time window makes them (game_bar_widgets.tl ~404-560): makeGameSetTimeOfDayCmd, the
--             game_time.gs events ("GameTime" | "CloudCoverage", "SetMode"), the environment copy
--             (api.gui.rendering.getEnvironment / setEnvironment) for clouds, day of year and sun rotation, plus
--             makeGameSetCloudCoverageCmd so the sim's WORLD.cloudCoverage agrees.
--             Restore (untick, pause menu, next load): pm_light.recoverPlan: only values still ours go back
--             (time first, then its cycle; clouds, then the weather cycle; day, sun). Window close keeps it (as
--             High graphics mode).
--   freeze    "Freeze time": GAME_SPEED.speedup kept, makeGameSetSpeedCmd(0) (as the base GameSpeedHelper);
--             untick / pause menu / next load: the kept speed back if the game is still paused. While frozen the
--             step reads GAME_SPEED once a frame: the player unpausing ends it (nothing to restore then).
--   load      the marker of a save made while overridden (autosave, a crash) is repaired at the first frame.
--             Removing the mod while overridden leaves the cycles on "Custom"; the calendar widget switches them
--             back (description, PLAN).
--   looks,    gui/pm_weather.lua (plans/square_photo_mode/LOOKS.md): look environments (rendering only), weather
--   weather   animations, time-lapse, seasons, sun placement. It sets values through K.apply, so the override's
--             snapshot covers them; this module forwards the step, the pause menu, the start and the marker.
-- Every api call in pcall. Logs "[PhotoMode] light ...".

local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
local weather = ug_require "square_photo_mode::/photo_mode/gui/pm_weather.lua"

local K = {}

K.GAME_TIME_SCRIPT = "::/game_mechanics/game_time/game_time.gs"

-- Set by pm_window.lua: writes our GUI save data (views + markers).
K.persist = function() end
-- Set by the plugin: something the window shows changed.
K.changed = function() end
-- Set by gui/pm_setups.lua (round 16): the picture changed by a click (a value, a look, the freeze): the "last
-- setup" is captured. Not called while values are put back (restore, pause menu, load).
K.noteChange = function() end
-- Set by gui/pm_setups.lua (round 16): called right before an untick puts the player's values back, so "Restore last
-- setup" can bring the picture back (the pause menu captures in pm_button.script.lua, before anything goes).
K.beforeRestore = function() end

local S = {
	ov = nil,     -- the override: { orig, set } (pm_light.newOverride)
	freeze = nil, -- { prev = speedup } while frozen by us
}
K.S = S

local function try(what, fn)
	local ok, err = pcall(fn)
	if not ok then core.log("light " .. what .. " ERROR " .. tostring(err)) end
	return ok
end

local function world() return api.engine.util.getWorld() end
local function send(cmd) api.cmd.sendCommand(cmd) end

local function gameScriptState()
	local e = api.engine.system.gameScriptSystem.getEntityForGameScript(K.GAME_TIME_SCRIPT)
	local gs = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
	return gs and gs.state or nil
end

--- The current state (pm_light fields), each read on its own (a failing read leaves the field out).
function K.read()
	local t = {}
	pcall(function() t.time = api.engine.getComponent(world(), api.type.ComponentType.GAME_TIME).timeOfDaySec end)
	pcall(function()
		local st = gameScriptState()
		if st ~= nil then
			t.timeMode = st.timeOfDayMode
			t.weatherMode = st.weatherMode or "Constant" -- as the base widget reads it
		end
	end)
	pcall(function()
		local a = api.gui.rendering.getEnvironment().atmosphere
		t.cloud, t.day, t.sun = a.cloudCoverage, a.dayOfYear, a.sunRotation
		t.cloudBase, t.cloudTop = a.cloudBase, a.cloudTop
		t.cloudScattering = a.cloudScattering
	end)
	return L.validState(t)
end

local function speedNow()
	local ok, sp = pcall(function() return api.engine.getComponent(world(), api.type.ComponentType.GAME_SPEED).speedup end)
	if ok and type(sp) == "number" then return sp end
	return nil
end

---------------------------------------------------------------------------
-- Setters (one per field)

local function setTime(s) send(api.cmd.makeGameSetTimeOfDayCmd(L.wrapTime(s))) end
local function setTimeMode(m) send(api.cmd.makeScriptingSendEventCmd("", "GameTime", "SetMode", { mode = m })) end
local function setWeatherMode(m)
	send(api.cmd.makeScriptingSendEventCmd("", "CloudCoverage", "SetMode", { weatherMode = m }))
end

--- Environment fields (cloud, day, sun, cloud heights) on a copy of the current environment, as the base widget
--- sets clouds; the sim's WORLD.cloudCoverage too unless noWorld (weather animations send it once a second).
local function setEnv(values, noWorld)
	local e = api.gui.rendering.getEnvironment()
	if values.cloud ~= nil then e.atmosphere.cloudCoverage = values.cloud end
	if values.day ~= nil then e.atmosphere.dayOfYear = values.day end
	if values.sun ~= nil then e.atmosphere.sunRotation = values.sun end
	if values.cloudBase ~= nil then e.atmosphere.cloudBase = values.cloudBase end
	if values.cloudTop ~= nil then e.atmosphere.cloudTop = values.cloudTop end
	if values.cloudScattering ~= nil then e.atmosphere.cloudScattering = values.cloudScattering end
	api.gui.rendering.setEnvironment(e)
	if values.cloud ~= nil and not noWorld then send(api.cmd.makeGameSetCloudCoverageCmd(values.cloud)) end
end

--- Puts the values of `put` (pm_light fields) in the safe order: time, then its cycle; environment; weather cycle.
local function applyValues(put, noWorld)
	if put.time ~= nil then try("set time", function() setTime(put.time) end) end
	if put.timeMode ~= nil then try("set time cycle", function() setTimeMode(put.timeMode) end) end
	if put.cloud ~= nil or put.day ~= nil or put.sun ~= nil or put.cloudBase ~= nil or put.cloudTop ~= nil
		or put.cloudScattering ~= nil then
		try("set environment", function()
			setEnv({ cloud = put.cloud, day = put.day, sun = put.sun, cloudBase = put.cloudBase,
				cloudTop = put.cloudTop, cloudScattering = put.cloudScattering }, noWorld)
		end)
	end
	if put.weatherMode ~= nil then try("set weather cycle", function() setWeatherMode(put.weatherMode) end) end
end

local function saveMarkerNow()
	try("save data", K.persist)
end

---------------------------------------------------------------------------
-- Override

function K.active() return S.ov ~= nil end
function K.frozen() return S.freeze ~= nil end

--- Our save data's marker (pm_light.marker), nil when nothing is overridden, frozen or on a look.
function K.saveMarker() return L.marker(S.ov, S.freeze, weather.markerLook()) end

--- Starts the override (snapshot, both cycles Constant, marker saved). True when it is on.
function K.begin()
	if S.ov ~= nil then return true end
	local orig = K.read()
	S.ov = L.newOverride(orig)
	-- a cycle we couldn't read is left alone (it could not be put back)
	applyValues({ timeMode = (orig.timeMode ~= nil and orig.timeMode ~= "Constant") and "Constant" or nil,
		weatherMode = (orig.weatherMode ~= nil and orig.weatherMode ~= "Constant") and "Constant" or nil })
	saveMarkerNow()
	core.log("light override on: player's " .. L.text(orig))
	K.changed()
	return true
end

--- Sets values (pm_light fields) under the override (started first if needed). quiet (weather animations,
--- several times a second): no log line, no save-data write, no window refresh; noWorld: the sim's cloud cover
--- not sent this time.
function K.apply(changes, why, quiet, noWorld)
	if not K.begin() then return end
	local c = L.change(S.ov, changes)
	applyValues(c, noWorld)
	if quiet then return end
	try("note change", K.noteChange)
	saveMarkerNow()
	core.log("light " .. tostring(why) .. ": " .. L.text(c))
	K.changed()
end

--- Sets values (pm_light fields time / cloud / day / sun / cloudBase / cloudTop) for a click: a running weather
--- animation or time-lapse that moves the same field stops first.
function K.set(changes, why)
	try("weather interrupt", function() weather.interrupt(changes) end)
	K.apply(changes, why)
end

--- A slider's live value while it moves (round 15, gui/pm_slider.lua; throttled there, pm_light.throttleInput): as
--- K.set, but quiet (no log line, no save-data write, no window refresh), so a drag never re-renders the window. The
--- gesture ends with a K.set of the final value. Round 16: the sim's cloud cover isn't sent while the Clouds slider
--- moves (the final set sends it once), as the weather animations send it at most once a second.
function K.setLive(changes, why)
	try("weather interrupt", function() weather.interrupt(changes) end)
	K.apply(changes, why, true, true)
end

--- Persists the marker now (pm_weather: during animations every few seconds, and when a look changes).
function K.saveNow() saveMarkerNow() end

--- A preset (pm_light.PRESETS key); sun times use the current climate's latitude (pm_weather.latitude).
function K.preset(key)
	local day = (S.ov and S.ov.set.day) or K.read().day
	local v = L.presetValues(key, day, weather.latitude())
	if v ~= nil then K.set(v, "preset " .. key) end
end

--- A step button: field time / cloud / day / sun moved by delta from the value shown.
function K.nudge(field, delta)
	local cur = K.shown()[field]
	if cur == nil then return end
	K.set({ [field] = cur + delta }, "step " .. field)
end

--- The values the Light tab shows: what we set while overridden (commands land a tick later), else the state.
function K.shown()
	if S.ov ~= nil then return S.ov.set end
	return K.read()
end

--- Restores what is still ours (pm_light.recoverPlan) and ends the override.
function K.restore(why)
	-- round 16: an untick (not the pause menu, which captured before anything went) keeps the picture as the last setup
	if why == "checkbox" then try("before restore", K.beforeRestore) end
	try("weather stop", function() weather.stopAll(why) end)
	local ov = S.ov
	if ov == nil then return end
	S.ov = nil
	try("restore", function()
		local put, kept = L.recoverPlan(ov.orig, ov.set, K.read())
		applyValues(put)
		core.log("light override off (" .. why .. "): restored " .. L.text(put) .. " | kept (changed by the player) "
			.. (#kept > 0 and table.concat(kept, ",") or "-"))
	end)
	saveMarkerNow()
	K.changed()
end

---------------------------------------------------------------------------
-- Freeze

function K.setFreeze(on, why)
	why = why or "checkbox"
	if on then
		if S.freeze ~= nil then return end
		local sp = speedNow()
		S.freeze = { prev = sp or 1 }
		if sp ~= 0 then try("freeze", function() send(api.cmd.makeGameSetSpeedCmd(0)) end) end
		core.log("light freeze on (speed was " .. tostring(sp) .. ")")
		try("note change", K.noteChange)
	else
		local f = S.freeze
		if f == nil then return end
		S.freeze = nil
		local sp = speedNow()
		if sp == 0 and f.prev > 0 then
			try("unfreeze", function() send(api.cmd.makeGameSetSpeedCmd(f.prev)) end)
			core.log("light freeze off (" .. why .. "): speed " .. f.prev .. " back")
		else
			core.log("light freeze off (" .. why .. "): the game runs already (speed " .. tostring(sp) .. "), left as is")
		end
	end
	saveMarkerNow()
	K.changed()
end

function K.busy() return S.freeze ~= nil or weather.busy() end

--- Every frame while busy: weather animations / time-lapse step; while frozen: the player unpaused (game bar,
--- Space) = the freeze is over, nothing to restore.
function K.stepFrame()
	if weather.busy() then try("weather step", weather.step) end
	if S.freeze == nil then return end
	local sp = speedNow()
	if sp ~= nil and sp ~= 0 and S.freezeSeen then
		S.freeze = nil
		S.freezeSeen = nil
		core.log("light freeze ended by the player (speed " .. sp .. ")")
		saveMarkerNow()
		K.changed()
	elseif sp == 0 then
		S.freezeSeen = true -- our speed command has landed
	end
end

---------------------------------------------------------------------------
-- Exits

--- The pause menu (every quit opens it first): everything back at once: animations stop, the look goes (its
--- live values carried over), then the override's values.
function K.pauseMenu()
	try("weather pause menu", weather.pauseMenu)
	if S.ov ~= nil then K.restore("pause menu") end
	if S.freeze ~= nil then K.setFreeze(false, "pause menu") end
end

--- First frame of a game: a marker left in this save (saved while overridden or frozen, or a crash) is repaired.
function K.start()
	S.ov, S.freeze, S.freezeSeen = nil, nil, nil
	try("recover", function()
		local mine = api.gui.game.getGuiSaveData(core.MOD_ID)
		local raw = type(mine) == "table" and mine.light or nil
		local m = raw ~= nil and L.readMarker(raw) or nil
		-- looks first (a rendering environment of ours left from the last game, or the marker's look)
		try("look start", function() weather.start(m and m.look or nil) end)
		if raw == nil then return end
		if m == nil then
			core.log("light: marker unreadable, cleared")
		else
			if m.orig ~= nil then
				local put, kept = L.recoverPlan(m.orig, m.set, K.read())
				applyValues(put)
				core.log("light: a save made while overridden; restored " .. L.text(put) .. " | kept "
					.. (#kept > 0 and table.concat(kept, ",") or "-"))
			end
			if m.freezePrev ~= nil and m.freezePrev > 0 and speedNow() == 0 then
				send(api.cmd.makeGameSetSpeedCmd(m.freezePrev))
				core.log("light: a save made while frozen; speed " .. m.freezePrev .. " back")
			end
		end
		K.persist()
	end)
end

---------------------------------------------------------------------------
-- Looks, weather over time, time-lapse, seasons, sun placement (gui/pm_weather.lua; the window calls these)

--- The look layers the current climate has ({ sky = keys, haze = keys, water = keys }, pm_looks.SKY_ORDER /
--- HAZE_ORDER / WATER_ORDER; nil for an unknown climate).
function K.looks() return weather.looks() end
--- Switches to the sky + haze + water look (rendering only); nil for all three = the climate's own look back.
function K.look(sky, haze, water, why) weather.setLook(sky, haze, water, why or "button") end
--- One look layer ("sky", "haze" or "water") to `key`, the others kept; nil = that layer's original.
function K.layer(layer, key) weather.setLayer(layer, key, "button") end
--- Starts weather animation `kind` (pm_looks.WEATHER: storm, clearing, lowclouds); nil stops it.
function K.weather(kind) weather.startWeather(kind) end
--- Starts time-lapse `kind` (pm_looks.LAPSE: sunrise, sunset, run); nil stops it.
function K.lapse(kind) weather.startLapse(kind) end
--- Season preset (pm_looks.SEASONS: winter, spring, summer).
function K.season(kind) weather.season(kind) end
--- Sun placement for the current view (pm_looks.SUN_PLACES: back, side, front). Returns the sun's altitude
--- (radians; below 0: the sun is down, the window can say so) or nil.
function K.placeSun(kind) return weather.placeSun(kind) end
--- What the Light and Weather tabs show about these: { climate, look, sky, haze, water, weather, lapse,
--- looks }.
function K.status() return weather.status() end

weather.init(K)

return K
