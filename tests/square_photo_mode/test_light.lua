-- pm_light.lua (pure: presets, sun times, override bookkeeping, marker, restore plan) and gui/pm_sky.lua (the
-- Light tab's override and freeze) on a fake api: base game_time.gs events, environment copy, game speed.

local L

before_each(function()
	reset_modules()
	L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
end)

test("sun times: golden hour in the evening, earlier in winter; polar days fall back", function()
	local june = L.sunTime(172, math.rad(6), true)
	local dec = L.sunTime(355, math.rad(6), true)
	ok(june ~= nil and june > 18 * 3600 and june < 19.5 * 3600, "June golden hour " .. L.clockText(june))
	ok(dec ~= nil and dec > 14.5 * 3600 and dec < 16 * 3600, "December golden hour " .. L.clockText(dec))
	local blue = L.presetValues("blue", 172).time
	ok(blue > june, "blue hour after golden hour")
	local morning = L.sunTime(172, math.rad(6), false)
	near(morning + june, 24 * 3600, 2, "symmetric around noon")
	-- the sun never sets at 80 degrees north in June: -4 degrees never happens
	eq(L.sunTime(172, math.rad(-4), true, math.rad(80)), nil)
	eq(L.presetValues("blue", 172, math.rad(80)).time, L.PRESETS.blue.fallback)
	eq(L.presetValues("noon", 1).time, 12 * 3600)
	eq(L.presetValues("storm").cloud, 1.0)
	eq(L.presetValues("nonsense"), nil)
	for __, k in ipairs(L.PRESET_ORDER) do ok(L.PRESETS[k] ~= nil, k) end
end)

test("wrapping: time, day and sun angle", function()
	eq(L.wrapTime(-600), 86400 - 600)
	eq(L.wrapTime(86400 + 30), 30)
	eq(L.wrapTime(0 / 0), 0)
	eq(L.wrapDay(366), 1)
	eq(L.wrapDay(0), 365)
	near(L.wrapSun(math.pi + 0.1), -math.pi + 0.1, 1e-9)
	eq(L.clockText(18 * 3600 + 30 * 60), "18:30")
end)

local PLAYER = { time = 30000, timeMode = "Dynamic", cloud = 0.4, weatherMode = "Dynamic", day = 171, sun = 0 }

test("override: both cycles Constant; changes normalised into set", function()
	local ov = L.newOverride(PLAYER)
	eq(ov.set.timeMode, "Constant"); eq(ov.set.weatherMode, "Constant")
	eq(ov.orig.timeMode, "Dynamic")
	local c = L.change(ov, { time = -3600, cloud = 1.7, day = 400, sun = 4 })
	eq(c.time, 86400 - 3600); eq(c.cloud, 1); eq(c.day, 35)
	ok(math.abs(c.sun) <= math.pi)
	eq(ov.set.time, c.time)
end)

test("restore plan: only what is still ours goes back; the player's own changes stay", function()
	local ov = L.newOverride(PLAYER)
	L.change(ov, { time = 68000, cloud = 1.0 })
	-- now: everything as we set it
	local put, kept = L.recoverPlan(ov.orig, ov.set, ov.set)
	eq(put.time, 30000); eq(put.timeMode, "Dynamic"); eq(put.cloud, 0.4); eq(put.weatherMode, "Dynamic")
	eq(put.day, nil, "unchanged fields need no call"); eq(#kept, 0)
	-- the player switched the weather cycle back by hand and moved the clouds meanwhile
	local now = { time = 68030, timeMode = "Constant", cloud = 0.2, weatherMode = "Dynamic", day = 171, sun = 0 }
	put, kept = L.recoverPlan(ov.orig, ov.set, now)
	eq(put.time, 30000, "time within the tolerance is ours")
	eq(put.cloud, nil); eq(put.weatherMode, nil)
	eq(kept, { "cloud", "weatherMode" })
	-- time across midnight still counts as ours
	ov.set.time = 86390
	put = L.recoverPlan(ov.orig, ov.set, { time = 20 })
	eq(put.time, 30000)
end)

test("marker: round trip, corrupt data dropped, freeze kept", function()
	local ov = L.newOverride(PLAYER)
	L.change(ov, { time = 70000 })
	local m = L.marker(ov, { prev = 2 })
	local r = L.readMarker(m)
	eq(r.orig.timeMode, "Dynamic"); eq(r.set.time, 70000); eq(r.freezePrev, 2)
	eq(L.marker(nil, nil), nil)
	eq(L.readMarker("junk"), nil)
	eq(L.readMarker({}), nil)
	local bad = L.readMarker({ orig = { time = "x", timeMode = "Sideways", cloud = 9, day = 0 / 0 }, set = {} })
	eq(bad.orig, {}, "invalid values left out (nothing restored from them)")
	local put = L.recoverPlan(bad.orig, bad.set, PLAYER)
	eq(next(put), nil)
end)

---------------------------------------------------------------------------
-- pm_sky on a fake api

local sky, fake

local function newFake()
	local f = {
		time = 30000, speed = 2, sent = {}, save = {},
		gs = { timeOfDayMode = "Dynamic", weatherMode = "Dynamic" },
		env = { atmosphere = { cloudCoverage = 0.4, dayOfYear = 171, sunRotation = 0 } },
	}
	local function rec(x) f.sent[#f.sent + 1] = x end
	f.api = {
		type = { ComponentType = { GAME_TIME = "GAME_TIME", GAME_SPEED = "GAME_SPEED", GAME_SCRIPT = "GAME_SCRIPT" } },
		engine = {
			util = { getWorld = function() return 1 end },
			system = { gameScriptSystem = { getEntityForGameScript = function() return 9 end } },
			getComponent = function(e, t)
				if t == "GAME_TIME" then return { timeOfDaySec = f.time } end
				if t == "GAME_SPEED" then return { speedup = f.speed } end
				if t == "GAME_SCRIPT" then return { state = f.gs } end
			end,
		},
		cmd = {
			sendCommand = function(c) rec(c) c.apply() end,
			makeGameSetTimeOfDayCmd = function(s) return { k = "time", v = s, apply = function() f.time = s end } end,
			makeGameSetSpeedCmd = function(s) return { k = "speed", v = s, apply = function() f.speed = s end } end,
			makeGameSetCloudCoverageCmd = function(c) return { k = "cloudCmd", v = c, apply = function() end } end,
			makeScriptingSendEventCmd = function(src, id, name, p)
				return { k = id .. "." .. name, v = p.mode or p.weatherMode, apply = function()
					if id == "GameTime" then f.gs.timeOfDayMode = p.mode else f.gs.weatherMode = p.weatherMode end
				end }
			end,
		},
		gui = {
			rendering = {
				getEnvironment = function()
					local a = f.env.atmosphere
					return { atmosphere = { cloudCoverage = a.cloudCoverage, dayOfYear = a.dayOfYear, sunRotation = a.sunRotation } }
				end,
				setEnvironment = function(e) f.env = e; rec({ k = "env" }) end,
			},
			game = {
				getGuiSaveData = function(k) return f.save[k] end,
				setGuiSaveData = function(k, d) f.save[k] = d end,
			},
		},
	}
	return f
end

local function kinds()
	local out = {}
	for __, c in ipairs(fake.sent) do out[#out + 1] = c.k .. (c.v ~= nil and ("=" .. tostring(c.v)) or "") end
	return out
end

local function loadSky()
	sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
	sky.persist = function() fake.save["square_photo_mode"] = { v = 1, views = {}, light = sky.saveMarker() } end
end

local function startSky()
	reset_modules()
	L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
	set_global("api", fake.api)
	loadSky()
end

test("sky: a preset starts the override (cycles Constant, marker saved), untick restores in order", function()
	fake = newFake()
	startSky()
	sky.preset("golden")
	ok(sky.active())
	local k = kinds()
	eq(k[1], "GameTime.SetMode=Constant"); eq(k[2], "CloudCoverage.SetMode=Constant")
	eq(k[3]:sub(1, 5), "time=", "then the time")
	ok(fake.save["square_photo_mode"].light ~= nil, "marker in our save data")
	sky.preset("storm")
	eq(fake.env.atmosphere.cloudCoverage, 1.0)
	eq(kinds()[#kinds()], "cloudCmd=1.0", "the sim's cloud cover follows")
	fake.sent = {}
	sky.restore("checkbox")
	eq(kinds(), { "time=30000", "GameTime.SetMode=Dynamic", "env", "cloudCmd=0.4", "CloudCoverage.SetMode=Dynamic" })
	eq(sky.active(), false)
	eq(fake.save["square_photo_mode"].light, nil, "marker cleared")
end)

test("sky: values the player changed meanwhile stay; the pause menu restores at once", function()
	fake = newFake()
	startSky()
	sky.set({ cloud = 0.9 }, "test")
	fake.gs.weatherMode = "Dynamic" -- the player set the weather cycle back in the calendar widget
	fake.sent = {}
	sky.pauseMenu()
	local k = table.concat(kinds(), " ")
	ok(not k:find("CloudCoverage.SetMode", 1, true), "the player's weather cycle kept: " .. k)
	ok(k:find("GameTime.SetMode=Dynamic", 1, true), "time cycle back")
	eq(sky.active(), false)
end)

test("sky: step buttons move from the shown value; an unreadable cycle is never switched", function()
	fake = newFake()
	fake.gs = nil -- the game script state can't be read
	fake.api.engine.getComponent = (function(orig)
		return function(e, t) if t == "GAME_SCRIPT" then error("no script") end return orig(e, t) end
	end)(fake.api.engine.getComponent)
	startSky()
	sky.nudge("time", 3600)
	sky.nudge("time", 3600)
	eq(fake.time, 30000 + 7200)
	for __, c in ipairs(kinds()) do ok(not c:find("SetMode", 1, true), "no cycle switch: " .. c) end
	sky.restore("checkbox")
	eq(fake.time, 30000)
end)

test("sky: freeze pauses and gives the speed back; the player's unpause ends it", function()
	fake = newFake()
	startSky()
	sky.setFreeze(true)
	eq(fake.speed, 0); ok(sky.frozen()); ok(sky.busy())
	eq(fake.save["square_photo_mode"].light.freezePrev, 2)
	sky.setFreeze(false)
	eq(fake.speed, 2)
	sky.setFreeze(true)
	sky.stepFrame()
	fake.speed = 4 -- the player pressed play
	sky.stepFrame()
	eq(sky.frozen(), false)
	fake.sent = {}
	sky.pauseMenu()
	eq(#fake.sent, 0, "nothing to give back")
	eq(fake.speed, 4)
end)

test("sky: a save made while overridden and frozen is repaired on the next load", function()
	fake = newFake()
	startSky()
	sky.preset("night")
	sky.setFreeze(true)
	local saved = fake.save["square_photo_mode"]
	-- next load: the game comes back with our values (Constant cycles, night, paused)
	startSky()
	fake.save["square_photo_mode"] = saved
	fake.sent = {}
	sky.start()
	eq(fake.time, 30000); eq(fake.gs.timeOfDayMode, "Dynamic"); eq(fake.gs.weatherMode, "Dynamic")
	eq(fake.speed, 2)
	eq(fake.save["square_photo_mode"].light, nil, "marker cleared")
	-- a corrupt marker is dropped without a call
	fake.save["square_photo_mode"] = { light = "junk" }
	fake.sent = {}
	sky.start()
	eq(#fake.sent, 0)
	eq(fake.save["square_photo_mode"].light, nil)
end)
