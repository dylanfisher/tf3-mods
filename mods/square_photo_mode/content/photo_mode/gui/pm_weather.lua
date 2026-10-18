-- Photo Mode: looks, weather over time, time-lapse, seasons and sun placement (GUI thread only: window clicks
-- through gui/pm_sky.lua, the plugin's onStep while busy, its openPauseMenu event, the game start). Pure part:
-- ../pm_looks.lua. Design and in-game checks: plans/square_photo_mode/LOOKS.md.
--
--   looks     rendering only: api.gui.rendering.setEnvironment(api.res.environmentRep.get(find(look ResName))),
--             then the live atmosphere values from before the switch put back (pm_looks.LIVE; a switch resets them
--             to the file's, probe T7). Never api.gui.game.setEnvironment: the save keeps the climate's ResName.
--             Back (button, pause menu, game start): the same with the game's ResName. The climate comes from that
--             ResName (pm_looks.climateOf); an unknown climate offers no looks.
--   weather   animations of cloud cover and cloud heights (pm_looks.WEATHER) and the time-lapse (pm_looks.LAPSE),
--             set through pm_sky.apply (quiet), so the light override's snapshot and restore cover them. At most
--             every STEP_MS; the sim's cloud cover once a second and at the end; the marker every PERSIST_MS.
--             Each animation logs its cost at the end (steps, ms per environment set).
--   sun       placement from the camera's look heading (getEye -> getCenter) and the sun's azimuth at the time
--             and day shown (pm_looks.solarPosition with the climate's latitude); logs the numbers (LOOKS.md K10).
-- Every api call in pcall. Logs "[PhotoMode] look ...", "weather ...", "lapse ...", "sun ...".

local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
local P = ug_require "square_photo_mode::/photo_mode/pm_looks.lua"

local W = {}

W.STEP_MS = 50       -- animations set the environment at most 20 times a second
W.WORLD_MS = 1000    -- the sim's cloud cover (WORLD.cloudCoverage) once a second during an animation
W.PERSIST_MS = 3000  -- the marker (override `set` values) during an animation
W.SLOW_MS = 8        -- one environment set slower than this is logged

local K = nil -- pm_sky (W.init)

local S = {
	look = nil,  -- { key, sky, haze, water, climate, res } while a look is on (key: pm_looks.lookKey)
	anim = nil,  -- { plan, t0, last, lastWorld, lastPersist, n, ms, maxMs } while a weather animation runs
	lapse = nil, -- { plan, t0, lastSent, lastPersist, n } while a time-lapse runs
	sideFlip = false,
}
W.S = S

function W.init(sky) K = sky end

local function try(what, fn)
	local ok, err = pcall(fn)
	if not ok then core.log(what .. " ERROR " .. tostring(err)) end
	return ok
end

local clock = nil
--- Milliseconds (api.type.Clock, as pm_world); a test may replace it.
W.nowMs = function()
	local ok, t = pcall(function()
		if clock == nil then clock = api.type.Clock.new() end
		return clock:getTime() / 1000
	end)
	return ok and t or 0
end

local function changed() if K ~= nil then try("weather changed", K.changed) end end
local function persist() if K ~= nil then try("weather save", K.saveNow) end end

---------------------------------------------------------------------------
-- Climate and looks

local function gameResName()
	local ok, r = pcall(function() return api.gui.game.getEnvironment() end)
	return ok and type(r) == "string" and r or nil
end

--- The base climate key of the game's environment, or nil (unknown climate / not readable).
function W.climate()
	return (P.climateOf(gameResName()))
end

--- The current climate's latitude (radians), nil when unknown (callers fall back to temperate's).
function W.latitude()
	local c = W.climate()
	return c and P.CLIMATES[c].lat or nil
end

--- The look layers offered now: { sky = SKY_ORDER, haze = HAZE_ORDER, water = WATER_ORDER keys } for a known
--- climate, nil for an unknown one (no look files for it).
function W.looks()
	if W.climate() == nil then return nil end
	-- round 16: the Sky menu ends with the whole looks (pm_looks.MENU: Legacy)
	return { sky = P.MENU.sky, haze = P.HAZE_ORDER, water = P.WATER_ORDER }
end

local function readLive()
	local live = {}
	pcall(function() live = P.liveOf(api.gui.rendering.getEnvironment().atmosphere) end)
	return live
end

--- Switches the rendering environment to `resName` and puts the live values back. Errors when not found.
local function switchTo(resName, live)
	local rep = api.res.environmentRep
	local id = rep.find(resName)
	if type(id) ~= "number" or id < 0 then error("environment not found: " .. tostring(resName)) end
	api.gui.rendering.setEnvironment(rep.get(id))
	local e = api.gui.rendering.getEnvironment()
	P.applyLive(e.atmosphere, live)
	api.gui.rendering.setEnvironment(e)
end

local function liveText(live)
	return string.format("cloud=%s base=%s top=%s day=%s sun=%s", tostring(live.cloudCoverage),
		tostring(live.cloudBase), tostring(live.cloudTop), tostring(live.dayOfYear), tostring(live.sunRotation))
end

--- Switches to the sky + haze + water look (pm_looks.SKY_ORDER / HAZE_ORDER / WATER_ORDER keys; nil or ORIG = that
--- layer's own) for the current climate; all three the climate's own = the climate's environment back.
function W.setLook(sky, haze, water, why)
	local key = P.lookKey(sky, haze, water)
	if key == nil then return W.restoreLook(why or "button") end
	if P.isWhole(sky) then
		haze, water = nil, nil -- round 16: a whole look brings its own haze and water
	else
		sky = P.SKY[sky or ""] and sky or nil
		haze, water = P.HAZE[haze or ""] and haze or nil, P.WATER[water or ""] and water or nil
	end
	local res0 = gameResName()
	local c, how = P.climateOf(res0)
	if c == nil then
		core.log("look " .. key .. ": unknown climate (environment " .. tostring(res0) .. "), no looks")
		return false
	end
	local res = P.lookResName(c, sky, haze, water)
	local live = readLive()
	local ok = try("look " .. key, function() switchTo(res, live) end)
	if ok then
		S.look = { key = key, sky = sky, haze = haze, water = water, climate = c, res = res }
		core.log(string.format("look %s on (%s, climate %s by %s): %s, live %s", key, why or "button", c, how, res,
			liveText(live)))
	elseif S.look ~= nil then
		-- a failed switch may have left the file's values: put the previous look's back on
		try("look back", function() switchTo(S.look.res, live) end)
	end
	if ok and K ~= nil then try("note change", K.noteChange) end -- round 16: the last setup
	persist()
	changed()
	return ok
end

--- One layer ("sky", "haze" or "water") to `key` (nil or ORIG = the climate's own), the other layers kept.
function W.setLayer(layer, key, why)
	if P.SET[layer] == nil then return false end
	local cur = { sky = S.look and S.look.sky or nil, haze = S.look and S.look.haze or nil,
		water = S.look and S.look.water or nil }
	cur[layer] = key
	-- round 16: a haze or water look ends a whole look (Legacy brings its own; the two don't mix)
	if layer ~= "sky" and P.isWhole(cur.sky) then cur.sky = nil end
	return W.setLook(cur.sky, cur.haze, cur.water, why)
end

--- The climate's own environment back (rendering only), the live values carried over.
function W.restoreLook(why)
	local lk = S.look
	if lk == nil then return false end
	S.look = nil
	local to = P.originalResName(gameResName(), lk.climate)
	local live = readLive()
	local ok = try("look off", function() switchTo(to, live) end)
	core.log(string.format("look %s off (%s): back to %s ok=%s, live %s", lk.key, tostring(why), tostring(to),
		tostring(ok), liveText(live)))
	persist()
	changed()
	return ok
end

--- The look key for our save-data marker (pm_light.marker), nil when none is on.
function W.markerLook() return S.look and S.look.key or nil end

---------------------------------------------------------------------------
-- Weather animations and time-lapse

function W.busy() return S.anim ~= nil or S.lapse ~= nil end

local function stopAnim(why)
	local a = S.anim
	if a == nil then return end
	S.anim = nil
	core.log(string.format("weather %s stopped (%s) after %d steps, setEnvironment avg=%.2f ms max=%.2f ms",
		a.plan.kind, why, a.n, a.n > 0 and a.ms / a.n or 0, a.maxMs))
end

local function stopLapse(why)
	local l = S.lapse
	if l == nil then return end
	S.lapse = nil
	core.log(string.format("lapse %s stopped (%s) after %d steps", l.plan.kind, why, l.n))
end

--- Stops animations and the time-lapse (the override's untick, the pause menu). The look stays.
function W.stopAll(why)
	local had = W.busy()
	stopAnim(why)
	stopLapse(why)
	if had then changed() end
end

--- A click sets fields itself (pm_sky.set): an animation moving one of them stops first.
function W.interrupt(changes)
	if S.anim ~= nil then
		for k in pairs(S.anim.plan.from) do
			if changes[k] ~= nil then stopAnim("replaced by a click"); changed(); break end
		end
	end
	if S.lapse ~= nil and changes.time ~= nil then stopLapse("replaced by a click"); changed() end
end

--- Starts weather animation `kind` (pm_looks.WEATHER) from the values shown; nil or the running kind stops it.
function W.startWeather(kind)
	if kind == nil or (S.anim ~= nil and S.anim.plan.kind == kind) then
		stopAnim("button")
		changed()
		return
	end
	if K == nil or not K.begin() then return end
	local plan = P.weatherPlan(kind, K.shown())
	if plan == nil then return end
	stopAnim("replaced")
	local now = W.nowMs()
	S.anim = { plan = plan, t0 = now, last = now, lastWorld = now, lastPersist = now, n = 0, ms = 0, maxMs = 0 }
	K.apply(plan.from, "weather " .. kind .. " start") -- logs, persists, sends the sim's cloud cover
	core.log(string.format("weather %s: over %d s from %s to %s", kind, plan.dur, L.text(plan.from), L.text(plan.to)))
end

--- Starts time-lapse `kind` (pm_looks.LAPSE); nil or the running kind stops it.
function W.startLapse(kind)
	if kind == nil or (S.lapse ~= nil and S.lapse.plan.kind == kind) then
		stopLapse("button")
		changed()
		return
	end
	if K == nil or not K.begin() then return end
	local st = K.shown()
	local plan = P.lapsePlan(kind, st.day, W.latitude(), st.time)
	if plan == nil then return end
	stopLapse("replaced")
	local now = W.nowMs()
	S.lapse = { plan = plan, t0 = now, lastSent = L.wrapTime(plan.from), lastPersist = now, n = 0 }
	K.apply({ time = plan.from }, "lapse " .. kind .. " start")
	if plan.rate ~= nil then
		core.log(string.format("lapse %s: from %s at %d game s per s", kind, L.clockText(plan.from), plan.rate))
	else
		core.log(string.format("lapse %s: %s to %s over %d s", kind, L.clockText(plan.from), L.clockText(plan.to),
			plan.dur))
	end
end

local function animStep(now)
	local a = S.anim
	if now - a.last < W.STEP_MS and now - a.t0 < a.plan.dur * 1000 then return end
	a.last = now
	local vals, done = P.weatherAt(a.plan, (now - a.t0) / 1000)
	local world = done or now - a.lastWorld >= W.WORLD_MS
	if world then a.lastWorld = now end
	local t0 = W.nowMs()
	K.apply(vals, "weather", true, not world)
	local ms = W.nowMs() - t0
	a.n, a.ms = a.n + 1, a.ms + ms
	if ms > a.maxMs then a.maxMs = ms end
	if ms > W.SLOW_MS then core.log(string.format("weather %s step slow: %.1f ms", a.plan.kind, ms)) end
	if done then
		S.anim = nil
		core.log(string.format("weather %s done: %s; %d steps, setEnvironment avg=%.2f ms max=%.2f ms", a.plan.kind,
			L.text(vals), a.n, a.ms / a.n, a.maxMs))
		persist()
		changed()
	elseif now - a.lastPersist >= W.PERSIST_MS then
		a.lastPersist = now
		persist()
	end
end

local function lapseStep(now)
	local l = S.lapse
	local t, done = P.lapseAt(l.plan, (now - l.t0) / 1000)
	local s = L.wrapTime(t)
	if s ~= l.lastSent or done then
		l.lastSent = s
		l.n = l.n + 1
		K.apply({ time = s }, "lapse", true)
	end
	if done then
		S.lapse = nil
		core.log(string.format("lapse %s done at %s after %d steps", l.plan.kind, L.clockText(s), l.n))
		persist()
		changed()
	elseif now - l.lastPersist >= W.PERSIST_MS then
		l.lastPersist = now
		persist()
	end
end

--- Every frame while busy (pm_sky.stepFrame).
function W.step()
	if K == nil then return end
	if not K.active() then
		-- the override ended under us (restored elsewhere): nothing of ours to move any more
		W.stopAll("override off")
		return
	end
	local now = W.nowMs()
	if S.anim ~= nil then try("weather step", function() animStep(now) end) end
	if S.lapse ~= nil then try("lapse step", function() lapseStep(now) end) end
end

---------------------------------------------------------------------------
-- Seasons and sun placement

--- Season preset `kind` (pm_looks.SEASONS).
function W.season(kind)
	local d = P.SEASONS[kind]
	if d == nil or K == nil then return end
	K.set({ day = d }, "season " .. kind)
end

--- The camera's look heading (world, radians): getEye -> getCenter, else getCameraData's angle + pi (findings
--- map-camera.md: the heading eye -> centre is the angle + pi).
function W.lookHeading()
	local ok, h = pcall(function()
		local e, c = api.gui.camera.getEye(), api.gui.camera.getCenter()
		local dx, dy = c.x - e.x, c.y - e.y
		if dx * dx + dy * dy < 1 then return nil end
		return P.atan2(dy, dx)
	end)
	if ok and h ~= nil then return h, "eye" end
	ok, h = pcall(function() return api.gui.camera.getCameraData().w + math.pi end)
	if ok and type(h) == "number" then return P.wrapAngle(h), "angle" end
	return nil
end

--- Puts the sun at `kind` (pm_looks.SUN_PLACES) relative to the view; side alternates left / right. Returns the
--- sun's altitude (radians; below 0 = the sun is down, nothing to see) or nil.
function W.placeSun(kind)
	local off = P.SUN_PLACES[kind]
	if off == nil or K == nil then return nil end
	if kind == "side" then
		S.sideFlip = not S.sideFlip
		if not S.sideFlip then off = -off end
	end
	local look, how = W.lookHeading()
	if look == nil then
		core.log("sun " .. kind .. ": camera heading not readable")
		return nil
	end
	local st = K.shown()
	local day, t = st.day or 171, st.time or 12 * 3600
	local lat = W.latitude() or L.LATITUDE
	local alt, az = P.solarPosition(day, t, lat)
	local rot = P.placeSun(off, look, az, P.SUN_CAL)
	K.set({ sun = rot }, "sun " .. kind)
	core.log(string.format("sun %s: look heading=%.3f rad (%d deg, from %s) sun azimuth=%.1f deg from north altitude=%.1f "
		.. "deg (day %d, %s, lat %.3f) -> sunRotation=%.3f (%d deg), cal north=%.3f sign=%d; expected sun heading %d deg",
		kind, look, math.floor(math.deg(look) + 0.5), how, math.deg(az), math.deg(alt), math.floor(day + 0.5),
		L.clockText(t), lat, rot, math.floor(math.deg(rot) + 0.5), P.SUN_CAL.north, P.SUN_CAL.sign,
		math.floor(math.deg(P.sunHeading(az, rot)) + 0.5)))
	return alt
end

---------------------------------------------------------------------------
-- Exits

--- The pause menu: animations stop, the look goes.
function W.pauseMenu()
	W.stopAll("pause menu")
	if S.look ~= nil then W.restoreLook("pause menu") end
end

--- First frame of a game: forget the last game's state; a rendering environment of ours (the GUI state outlived
--- a load) or the save's marker look puts the climate's environment back.
function W.start(markerLook)
	-- round 16: a look still on in this Lua state (it outlived the last game) counts as the marker's
	local had = S.look ~= nil and S.look.key or nil
	S.look, S.anim, S.lapse = nil, nil, nil
	local name = nil
	pcall(function() name = api.gui.rendering.getEnvironment().name end)
	local plan = P.startPlan(markerLook or had, name, gameResName())
	if plan == nil then return end
	local live = readLive()
	local ok = try("look start", function() switchTo(plan.to, live) end)
	core.log(string.format("look: game start (%s, marker look %s, rendering %s): back to %s ok=%s", plan.why,
		tostring(markerLook), tostring(name), plan.to, tostring(ok)))
end

--- What the Light tab shows.
function W.status()
	return {
		climate = W.climate(),
		look = S.look and S.look.key or nil,
		sky = S.look and S.look.sky or nil,
		haze = S.look and S.look.haze or nil,
		water = S.look and S.look.water or nil,
		weather = S.anim and S.anim.plan.kind or nil,
		lapse = S.lapse and S.lapse.plan.kind or nil,
		looks = W.looks(),
	}
end

return W
