-- Photo Mode: light and weather, the pure part (no api calls). Shared by gui/pm_sky.lua and the offline tests
-- (tests/square_photo_mode/test_light.lua). Plain Lua, pre-5.3. PLAN: plans/square_photo_mode/PLAN.md "Phase 3:
-- Light & weather".
--
-- State (what the base "Weather & Time" window shows and sets, base gui/game_bar/game_bar_widgets.tl ~404-560):
--   time         GAME_TIME.timeOfDaySec (0..86399), set with api.cmd.makeGameSetTimeOfDayCmd(integer seconds)
--   timeMode     the game script game_time.gs state.timeOfDayMode: "Constant" (the widget's "Custom"),
--                "Automatic", "Local", "Dynamic"; set with the scripting event ("", "GameTime", "SetMode",
--                { mode = m }) (game_time.script.tl handleEvent)
--   cloud        api.gui.rendering.getEnvironment().atmosphere.cloudCoverage (0..1); the sim's WORLD.cloudCoverage
--                follows makeGameSetCloudCoverageCmd (the game script's Dynamic weather sends it every update)
--   weatherMode  the same game script's state.weatherMode: "Constant" | "Dynamic"; set with ("", "CloudCoverage",
--                "SetMode", { weatherMode = m })
--   day, sun     the environment's atmosphere.dayOfYear (season; the base climates use 171) and .sunRotation
--                (radians, as base model_editor env files write math.rad(-60)); rendering only
--   cloudBase,   the environment's atmosphere.cloudBase / .cloudTop (m; base climates 1500 / 3600): Low clouds
--   cloudTop     (pm_looks.WEATHER, LOOKS.md); rendering only, a load resets them from the env file
--   cloudScattering  the environment's atmosphere.cloudScattering (round 16: the Weather tab's Cloud density; the
--                cloud march's scattering coefficient, atmosphere/cloud.h.glsl: extinction = scattering +
--                absorption, so more = denser clouds; engine default 0.005, probe T6); rendering only
-- An override snapshots all of them (orig), switches both cycles to Constant and remembers every value it set
-- (set). Restoring puts back only what is still ours (recoverPlan): a value or mode the player changed since
-- stays as they set it. The same plan repairs a savegame saved while overridden (the marker in our GUI save
-- data) on the next load.

local L = {}

L.DAY = 86400
L.TIME_MODES = { Constant = true, Automatic = true, Local = true, Dynamic = true }
L.WEATHER_MODES = { Constant = true, Dynamic = true }
-- The latitude of the sun model (radians): the Environment record exposes no latitude, so the base temperate
-- climate's (temperate.env.lua light.latitude; dry 0.62, tropical 0.42, subarctic 0.88).
L.LATITUDE = 0.7068
-- Steps of the window's step buttons.
L.STEP = { hour = 3600, minutes = 600, cloud = 0.1, day = 15, sun = math.rad(15) }

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
L.finite = finite

local function clamp(v, lo, hi)
	if v ~= v then return lo end
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

--- Seconds of the day wrapped into 0..86399, whole seconds (the command takes an integer).
function L.wrapTime(t)
	if not finite(t) then return 0 end
	local s = math.floor(t + 0.5) % L.DAY
	if s < 0 then s = s + L.DAY end
	return s
end

--- Day of the year wrapped into 1..365.
function L.wrapDay(d)
	if not finite(d) then return 171 end
	return (math.floor(d + 0.5) - 1) % 365 + 1
end

--- An angle wrapped into (-pi, pi].
function L.wrapSun(a)
	if not finite(a) then return 0 end
	local r = math.fmod(a + math.pi, 2 * math.pi)
	if r <= 0 then r = r + 2 * math.pi end
	return r - math.pi
end

--- "HH:MM" of a time of day.
function L.clockText(t)
	local s = L.wrapTime(t)
	return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

--- The time of day (s) at which the sun stands `alt` radians above the horizon on day `day`, in the afternoon
--- (pm = true) or morning; nil when the sun never gets there that day (polar day / night). Solar time, the
--- textbook declination; assumes the game's clock is solar time with noon at 12:00 (base game_time.script.tl's
--- "noon" phase is 86400 / 2) and its sun follows latitude and day of year (unverified: TESTING.md L3).
function L.sunTime(day, alt, pm, lat)
	lat = lat or L.LATITUDE
	if not (finite(day) and finite(alt) and finite(lat)) then return nil end
	local decl = math.rad(23.44) * math.sin(2 * math.pi * (284 + day) / 365)
	local den = math.cos(lat) * math.cos(decl)
	if math.abs(den) < 1e-9 then return nil end
	local cosH = (math.sin(alt) - math.sin(lat) * math.sin(decl)) / den
	if cosH < -1 or cosH > 1 then return nil end
	local hours = math.deg(math.acos(cosH)) / 15
	return L.wrapTime((pm == false and (12 - hours) or (12 + hours)) * 3600)
end

-- Presets: time presets set the time of day (sun altitude where the sun model gives one, else the fallback),
-- weather presets the cloud cover. Golden hour: the sun 6 degrees up in the evening; blue hour: 4 degrees below
-- the horizon after sunset. Storm: full cover (the base "rainy" weather's mean, game_time.script.tl).
L.PRESETS = {
	golden = { sunAlt = math.rad(6), fallback = 18 * 3600 + 30 * 60 },
	blue = { sunAlt = math.rad(-4), fallback = 20 * 3600 + 45 * 60 },
	noon = { time = 12 * 3600 },
	night = { time = 0 },
	clear = { cloud = 0.0 },
	overcast = { cloud = 0.7 },
	storm = { cloud = 1.0 },
}
L.PRESET_ORDER = { "golden", "blue", "noon", "night", "clear", "overcast", "storm" }

--- What preset `key` sets on day `day`: { time = s } or { cloud = c }; nil for an unknown key.
function L.presetValues(key, day, lat)
	local p = L.PRESETS[key]
	if p == nil then return nil end
	if p.cloud ~= nil then return { cloud = p.cloud } end
	if p.time ~= nil then return { time = p.time } end
	return { time = L.sunTime(L.wrapDay(day or 171), p.sunAlt, true, lat) or p.fallback }
end

---------------------------------------------------------------------------
-- Override bookkeeping and the save-data marker

local FIELDS = { "time", "timeMode", "cloud", "weatherMode", "day", "sun", "cloudBase", "cloudTop", "cloudScattering" }
L.FIELDS = FIELDS

--- A state table with only valid values (anything else left out): time 0..86399, the modes from their enums,
--- cloud 0..1, day 1..365, sun finite, cloudBase / cloudTop 0..20000 m, cloudScattering above 0 up to 0.1. Used on the
--- read state and on marker data read back from a save.
function L.validState(t)
	local out = {}
	if type(t) ~= "table" then return out end
	local ok = pcall(function()
		if finite(t.time) and t.time >= 0 and t.time < L.DAY then out.time = math.floor(t.time) end
		if type(t.timeMode) == "string" and L.TIME_MODES[t.timeMode] then out.timeMode = t.timeMode end
		if finite(t.cloud) and t.cloud >= 0 and t.cloud <= 1 then out.cloud = t.cloud end
		if type(t.weatherMode) == "string" and L.WEATHER_MODES[t.weatherMode] then out.weatherMode = t.weatherMode end
		if finite(t.day) and t.day >= 1 and t.day <= 366 then out.day = t.day end
		if finite(t.sun) and math.abs(t.sun) <= 7 then out.sun = t.sun end
		if finite(t.cloudBase) and t.cloudBase >= 0 and t.cloudBase <= 20000 then out.cloudBase = t.cloudBase end
		if finite(t.cloudTop) and t.cloudTop >= 0 and t.cloudTop <= 20000 then out.cloudTop = t.cloudTop end
		if finite(t.cloudScattering) and t.cloudScattering > 0 and t.cloudScattering <= 0.1 then
			out.cloudScattering = t.cloudScattering
		end
	end)
	if not ok then return {} end
	return out
end

--- A new override from the player's state `orig`: set = orig with both cycles Constant (what the override
--- starts by sending).
function L.newOverride(orig)
	orig = L.validState(orig)
	local set = {}
	for __, k in ipairs(FIELDS) do set[k] = orig[k] end
	set.timeMode, set.weatherMode = "Constant", "Constant"
	return { orig = orig, set = set }
end

--- The values a change asks for, normalised (time wrapped, cloud clamped, day wrapped, sun wrapped), written into
--- ov.set; returns the normalised changes.
function L.change(ov, changes)
	local out = {}
	if changes.time ~= nil then out.time = L.wrapTime(changes.time) end
	if changes.cloud ~= nil then out.cloud = clamp(tonumber(changes.cloud) or 0, 0, 1) end
	if changes.day ~= nil then out.day = L.wrapDay(changes.day) end
	if changes.sun ~= nil then out.sun = L.wrapSun(changes.sun) end
	if changes.cloudBase ~= nil then out.cloudBase = clamp(tonumber(changes.cloudBase) or 0, 0, 20000) end
	if changes.cloudTop ~= nil then out.cloudTop = clamp(tonumber(changes.cloudTop) or 0, 0, 20000) end
	if changes.cloudScattering ~= nil then
		out.cloudScattering = clamp(tonumber(changes.cloudScattering) or L.SCATTERING, L.SCATTERING_MIN, L.SCATTERING_MAX)
	end
	if ov ~= nil then for k, v in pairs(out) do ov.set[k] = v end end
	return out
end

--- The marker kept in our GUI save data while overridden, frozen or a look is on (plain numbers / strings
--- only), or nil. `look` is the look key (pm_looks; rendering only, so a load already shows the climate's own
--- environment: the start just checks it).
function L.marker(ov, freeze, look)
	if ov == nil and freeze == nil and look == nil then return nil end
	local m = { v = 1 }
	if type(look) == "string" then m.look = look end
	if ov ~= nil then
		m.orig, m.set = {}, {}
		for __, k in ipairs(FIELDS) do m.orig[k], m.set[k] = ov.orig[k], ov.set[k] end
	end
	if freeze ~= nil and finite(freeze.prev) then m.freezePrev = math.floor(freeze.prev) end
	return m
end

--- A marker read back from save data, validated: { orig, set, freezePrev, look } or nil.
function L.readMarker(m)
	if type(m) ~= "table" then return nil end
	local ok, r = pcall(function()
		local out = {}
		if type(m.orig) == "table" and type(m.set) == "table" then
			out.orig, out.set = L.validState(m.orig), L.validState(m.set)
		end
		if finite(m.freezePrev) and m.freezePrev >= 0 and m.freezePrev <= 16 then out.freezePrev = math.floor(m.freezePrev) end
		if type(m.look) == "string" and #m.look <= 40 and m.look:match("^[a-z_]+$") then out.look = m.look end
		if out.orig == nil and out.freezePrev == nil and out.look == nil then return nil end
		return out
	end)
	return ok and r or nil
end

-- How close a current value must be to the one we set to count as still ours.
L.TOL = { time = 120, cloud = 0.02, day = 0.5, sun = 0.01, cloudBase = 5, cloudTop = 5, cloudScattering = 0.00002 }

--- What to put back: for every field, the player's original value when the current value is still the one we
--- set (modes: still "Constant" and the original differs); a field the player changed since is kept. Returns
--- put (field -> value, only fields that differ from now) and kept (field names, FIELDS order).
function L.recoverPlan(orig, set, current)
	orig, set, current = L.validState(orig), L.validState(set), L.validState(current)
	local put, kept = {}, {}
	for __, k in ipairs(FIELDS) do
		local o, s, c = orig[k], set[k], current[k]
		if o ~= nil and s ~= nil then
			local ours
			if c == nil then
				ours = true -- unreadable now: put the player's value back
			elseif type(c) == "string" then
				ours = c == s
			elseif k == "time" then
				local d = math.abs(c - s) % L.DAY
				ours = math.min(d, L.DAY - d) <= L.TOL.time
			elseif k == "sun" then
				ours = math.abs(L.wrapSun(c - s)) <= L.TOL.sun
			else
				ours = math.abs(c - s) <= L.TOL[k]
			end
			local same = c ~= nil and (type(c) == "string" and c == o or (type(c) == "number" and math.abs(c - o) < 1e-6))
			if ours then
				if not same then put[k] = o end
			else
				kept[#kept + 1] = k
			end
		end
	end
	return put, kept
end

---------------------------------------------------------------------------
-- Sliders (round 15: the Light tab's time of day, season and sun direction; gui/pm_slider.lua)

-- The base builtin.Slider takes integer min / max / value (base tealdef scripts/builtin.d.tl SliderParam), so each
-- field gets an integer scale: time in minutes of the day, the day of the year, the sun rotation in whole degrees
-- 0..359 (absolute: 0 = the climate's own sun direction). step: the keyboard / gamepad step, pageStep the page
-- step (as the base: SliderWithLegend 1 % and 10 %, game_bar_widgets.tl ~38-40).
-- Round 16 (the Weather tab's Adjust rows): cloud cover in percent; the cloud deck's height (cloudBase) in 100 m
-- steps, 100-4000 m (the top follows at the deck's thickness, sliderChanges); the cloud density (cloudScattering)
-- in tenths of the engine default SCATTERING, 10 % to 400 %.
L.SLIDER = {
	time = { min = 0, max = 24 * 60 - 1, step = 10, pageStep = 60 },
	day = { min = 1, max = 365, step = 1, pageStep = 15 },
	sun = { min = 0, max = 359, step = 1, pageStep = 15 },
	cloud = { min = 0, max = 100, step = 1, pageStep = 10 },
	cloudBase = { min = 1, max = 40, step = 1, pageStep = 5 },
	cloudScattering = { min = 1, max = 40, step = 1, pageStep = 5 },
}
-- The cloud density's scale (round 16): the engine's default cloudScattering (Dry map, probe T6; no base env file
-- sets it) and the slider's ends (10 % .. 400 % of it).
L.SCATTERING = 0.005
L.SCATTERING_MIN = L.SCATTERING / 10
L.SCATTERING_MAX = L.SCATTERING * 4
-- The cloud deck's thickness kept when the height slider moves it (base climates: 1500 -> 3600 m), clamped.
L.DECK = { default = 2100, min = 500, max = 5000 }

--- A state value (time s, day, sun radians) as its slider's integer, clamped into the slider's range; nil for an
--- unknown field or a value that isn't a number.
function L.toSlider(field, v)
	local r = L.SLIDER[field]
	if r == nil or not finite(v) then return nil end
	local i
	if field == "time" then i = math.floor(L.wrapTime(v) / 60)
	elseif field == "day" then i = L.wrapDay(v)
	elseif field == "cloud" then i = math.floor(v * 100 + 0.5)
	elseif field == "cloudBase" then i = math.floor(v / 100 + 0.5)
	elseif field == "cloudScattering" then i = math.floor(v / L.SCATTERING * 10 + 0.5)
	else i = math.floor(math.deg(L.wrapSun(v)) + 0.5) % 360 end
	return math.floor(clamp(i, r.min, r.max))
end

--- A slider's integer as the state value (time s, day, sun radians in (-pi, pi]); nil for an unknown field.
function L.fromSlider(field, i)
	local r = L.SLIDER[field]
	if r == nil or not finite(i) then return nil end
	i = math.floor(clamp(i, r.min, r.max) + 0.5)
	if field == "time" then return i * 60 end
	if field == "day" then return i end
	if field == "cloud" then return i / 100 end
	if field == "cloudBase" then return i * 100 end
	if field == "cloudScattering" then return L.SCATTERING * i / 10 end
	return L.wrapSun(math.rad(i))
end

--- The changes a slider's integer `i` asks for (pm_sky.set / setLive): { [field] = value }; the cloud height moves
--- the whole deck, the top kept at the deck's thickness in `shown` (pm_light fields; clamped DECK, default when
--- unknown). nil for an unknown field.
function L.sliderChanges(field, i, shown)
	local v = L.fromSlider(field, i)
	if v == nil then return nil end
	if field ~= "cloudBase" then return { [field] = v } end
	local thick = L.DECK.default
	if type(shown) == "table" and finite(shown.cloudBase) and finite(shown.cloudTop) then
		thick = clamp(shown.cloudTop - shown.cloudBase, L.DECK.min, L.DECK.max)
	end
	return { cloudBase = v, cloudTop = v + thick }
end

L.MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

--- Month (1..12) and day of the month of day-of-year `d` (a 365-day year, as the game's dayOfYear 1..365).
function L.dayToDate(d)
	d = L.wrapDay(d)
	for m, n in ipairs(L.MONTH_DAYS) do
		if d <= n then return m, d end
		d = d - n
	end
	return 12, 31
end

-- A slider applies its value live but throttled (round 15, user: "Can season, time of day, and sun direction be
-- sliders?"): the base slider calls onValueChange for every value it passes while dragged (the base calendar's
-- time of day sends a command each time, game_bar_widgets.tl ~420-428), so a write goes out at most every
-- `interval` ms while the value moves, the value the player stopped on goes out once the interval is over (the
-- trailing write), and the gesture ends with one final write: at the mouse release (as the base construction
-- slider's coalescing, script_param_util.tl ~290-325) or, when no release comes (keyboard, gamepad, a release off
-- the slider), `settle` ms after the last move. Live writes are quiet; the final one logs, saves the marker and
-- refreshes the window.

--- A new throttle (pure: the caller passes the time in ms).
function L.newThrottle(interval, settle)
	return { interval = interval or 80, settle = settle or 400, lastWrite = nil, pending = nil, latest = nil,
		lastInput = nil, open = false }
end

--- A new value from the slider at `now`: returns it when it should be written live now, else nil (kept as the
--- pending value for L.throttleStep).
function L.throttleInput(t, v, now)
	if not finite(now) then now = 0 end
	t.latest, t.lastInput, t.open = v, now, true
	if t.lastWrite == nil or now - t.lastWrite >= t.interval or now < t.lastWrite then
		t.lastWrite, t.pending = now, nil
		return v
	end
	t.pending = v
	return nil
end

--- Every frame: the pending value once the interval is over (kind "live"), the gesture's final value once it
--- settled (kind "final"), else nil.
function L.throttleStep(t, now)
	if not t.open then return nil end
	if not finite(now) then now = 0 end
	if t.pending ~= nil and (now - t.lastWrite >= t.interval or now < t.lastWrite) then
		local v = t.pending
		t.lastWrite, t.pending = now, nil
		return v, "live"
	end
	if t.pending == nil and t.lastInput ~= nil and now - t.lastInput >= t.settle then
		t.open = false
		return t.latest, "final"
	end
	return nil
end

--- The mouse let go: the gesture's final value (nil when nothing moved since the last final write).
function L.throttleRelease(t, now)
	if not t.open then return nil end
	if not finite(now) then now = 0 end
	t.open, t.pending, t.lastWrite = false, nil, now
	return t.latest
end

--- "k=v k=v" in FIELDS order (log lines).
function L.text(t)
	local parts = {}
	for __, k in ipairs(FIELDS) do
		local v = t ~= nil and t[k] or nil
		if v ~= nil then
			if k == "time" then v = L.clockText(v)
			elseif type(v) == "number" then v = string.format("%.3f", v) end
			parts[#parts + 1] = k .. "=" .. tostring(v)
		end
	end
	return #parts > 0 and table.concat(parts, " ") or "-"
end

return L
