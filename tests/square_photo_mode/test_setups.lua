-- Round 16: saved setups and the last setup (pm_setup.lua pure; gui/pm_setups.lua through gui/pm_sky.lua and
-- gui/pm_weather.lua on a fake api: the library and the last setup in our GUI save data, apply,
-- the pause menu, the untick, a game start), the Legacy whole look and the cloud sliders' scales.
-- plans/square_photo_mode/PLAN.md "Round 16 settings".

local P, L, LK

before_each(function()
	reset_modules()
	P = ug_require "square_photo_mode::/photo_mode/pm_setup.lua"
	L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
	LK = ug_require "square_photo_mode::/photo_mode/pm_looks.lua"
end)

---------------------------------------------------------------------------
-- Pure

test("setup records: names cleaned, junk dropped, values validated, only booleans for the switches", function()
	eq(P.cleanName("  my\tdark \n night  "), "my dark night")
	eq(P.cleanName(""), nil); eq(P.cleanName(42), nil)
	local long = P.cleanName(string.rep("é", 60))
	eq(#long, 2 * P.NAME_MAX, "cut on a UTF-8 character boundary at NAME_MAX characters")
	local s = P.valid({ id = 3.7, name = "Golden 1", look = { sky = "dramatic", haze = "BAD key", water = "orig" },
		values = { time = 64800, day = 172, cloud = 3, sun = 0 / 0, cloudScattering = 0.01, timeMode = "Constant" },
		freeze = "yes", hq = true, labels = 1 })
	eq(s.id, 3); eq(s.name, "Golden 1")
	eq(s.look.sky, "dramatic"); eq(s.look.haze, nil, "a malformed key dropped"); eq(s.look.water, nil, "orig = the climate's own")
	eq(s.values.time, 64800); eq(s.values.day, 172); eq(s.values.cloud, nil, "cloud above 1 dropped")
	eq(s.values.sun, nil, "NaN dropped"); eq(s.values.cloudScattering, 0.01); eq(s.values.timeMode, nil, "only the picture's values")
	eq(s.freeze, false, "only true is true"); eq(s.hq, true); eq(s.labels, false)
	eq(P.valid("x"), nil)
	local empty = P.valid({ look = { sky = "orig" }, values = {} })
	eq(empty.look, nil); eq(empty.values, nil)
end)

test("library: read back from the save data keeps valid named setups with unique ids, at most CAP", function()
	local raw = { v = 1, list = {
		{ id = 1, name = "a" }, { id = 1, name = "repeat" }, { name = "no id" }, { id = 2 }, "junk",
		{ id = 5, name = "b", look = { sky = "legacy" } },
	} }
	local list = P.readLibrary(raw)
	eq(#list, 2); eq(list[1].name, "a"); eq(list[2].look.sky, "legacy")
	eq(#P.readLibrary(nil), 0); eq(#P.readLibrary({ list = "x" }), 0)
	local big = { list = {} }
	for i = 1, 40 do big.list[i] = { id = i, name = "s" .. i } end
	eq(#P.readLibrary(big), P.CAP)
	-- storage is plain: no functions, no shared tables with the list
	local data = P.libraryData(list)
	eq(data.v, 1); eq(#data.list, 2); ok(data.list[2].look ~= list[2].look, "a copy")
end)

test("library: add, overwrite, rename, delete; full and empty names refused", function()
	local list, id = P.add({}, { look = { sky = "dramatic" } }, "One")
	eq(id, 1); eq(list[1].name, "One")
	local l2, id2 = P.add(list, { freeze = true }, "  ")
	eq(id2, nil, "an empty name adds nothing"); eq(#l2, 1)
	list, id2 = P.add(list, { freeze = true }, "Two")
	eq(id2, 2)
	local before = list
	list = P.overwrite(list, 1, { look = { haze = "misty_valley" } })
	eq(list[1].name, "One", "the name stays"); eq(list[1].look.haze, "misty_valley"); eq(list[1].look.sky, nil)
	eq(before[1].look.sky, "dramatic", "the old list is not changed")
	list = P.rename(list, 2, "My dark night")
	eq(list[2].name, "My dark night")
	local same, changed = P.rename(list, 2, "")
	eq(changed, false); eq(same, list)
	list = P.remove(list, 1)
	eq(#list, 1); eq(list[1].id, 2)
	eq(P.nextId(list), 3, "ids are never reused while a higher one is there")
	local full = {}
	for i = 1, P.CAP do full[i] = { id = i, name = "x" } end
	local f2, nid = P.add(full, {}, "more")
	eq(nid, nil); eq(#f2, P.CAP)
end)

test("capture: the last setup keeps values only under the override; a named setup always", function()
	local st = { override = false, values = { time = 3600, day = 10, cloud = 0.2 }, look = { sky = "storybook" } }
	eq(P.capture(st, false).values, nil, "last: the override was off")
	eq(P.capture(st, true).values.time, 3600, "named: the picture's time")
	ok(P.active(st)); ok(not P.active({ override = false })); ok(P.active({ freeze = true }))
	ok(P.same(P.capture(st, false), P.capture(st, false)))
	ok(not P.same(P.capture(st, true), P.capture(st, false)))
end)

test("round 16 cloud sliders: cover, the deck's height with its thickness, the density", function()
	eq(L.toSlider("cloud", 0.37), 37); eq(L.fromSlider("cloud", 80), 0.8)
	eq(L.toSlider("cloudBase", 1500), 15); eq(L.fromSlider("cloudBase", 5), 500)
	eq(L.toSlider("cloudScattering", 0.005), 10, "the engine default is 100 %"); near(L.fromSlider("cloudScattering", 40), 0.02, 1e-12)
	eq(L.fromSlider("cloudScattering", 99), L.SCATTERING_MAX, "clamped")
	local c = L.sliderChanges("cloudBase", 5, { cloudBase = 1500, cloudTop = 3600 })
	eq(c.cloudBase, 500); eq(c.cloudTop, 2600, "the deck keeps its 2100 m")
	c = L.sliderChanges("cloudBase", 20, { cloudBase = 1000, cloudTop = 1100 })
	eq(c.cloudTop, 2000 + L.DECK.min, "a thin deck is thickened to DECK.min")
	c = L.sliderChanges("cloudBase", 20, nil)
	eq(c.cloudTop, 2000 + L.DECK.default)
	eq(L.sliderChanges("cloud", 50).cloud, 0.5)
	eq(L.sliderChanges("nonsense", 1), nil)
	-- the override snapshots and restores the density like the cloud heights
	local ov = L.newOverride({ cloudScattering = 0.005, cloud = 0.3 })
	L.change(ov, { cloudScattering = 0.02 })
	local put = L.recoverPlan(ov.orig, ov.set, { cloudScattering = 0.02, cloud = 0.3 })
	eq(put.cloudScattering, 0.005)
	eq(L.change(nil, { cloudScattering = 5 }).cloudScattering, L.SCATTERING_MAX)
end)

test("round 16 Legacy: a whole look of the base game's own environment, no file of ours", function()
	eq(LK.lookKey("legacy", "misty_valley", "wild"), "legacy", "brings its own haze and water")
	eq(LK.lookResName("tropical", "legacy"), "::/climates/tropical/tropical_old.env")
	eq(LK.lookResName("nowhere", "legacy"), nil)
	ok(LK.isOurName("Dry (Legacy)")); ok(LK.isOurName("Photo Mode look: x")); ok(not LK.isOurName("Dry"))
	eq(LK.MENU.sky[#LK.MENU.sky], "legacy"); eq(LK.SKY.legacy, nil, "not a generated sky (no files for it)")
	eq(LK.parseOurs("::/climates/dry/dry_old.env"), nil)
	eq((LK.climateOf("::/climates/dry/dry_old.env")), "dry")
end)

---------------------------------------------------------------------------
-- Through pm_sky / pm_weather on a fake api

local G, sky, fake, H

local FILE_ATMO = { cloudCoverage = 0, cloudBase = 1500, cloudTop = 3600, cloudScattering = 0.005, dayOfYear = 171,
	sunRotation = 0 }

local function copy(t)
	local o = {}
	for k, v in pairs(t) do o[k] = type(v) == "table" and copy(v) or v end
	return o
end

local function newFake()
	local f = {
		time = 30000, speed = 2, save = {}, now = 0, gs = { timeOfDayMode = "Dynamic", weatherMode = "Dynamic" },
		gameRes = "::/climates/dry/dry.env", appCalls = 0, saveWrites = 0,
	}
	f.byId, f.ids = {}, {}
	local function add(res, name)
		f.byId[#f.byId + 1] = { res = res, name = name }
		f.ids[res] = #f.byId
	end
	for __, c in ipairs({ "dry", "temperate" }) do
		add("::/climates/" .. c .. "/" .. c .. ".env", c)
		add("::/climates/" .. c .. "/" .. c .. "_old.env", c .. " (Legacy)")
		for __, s in ipairs({ false, "dramatic", "storybook" }) do
			for __, h in ipairs({ false, "misty_valley" }) do
				for __, w in ipairs({ false, "wild" }) do
					local res = LK.lookResName(c, s or nil, h or nil, w or nil)
					if res ~= nil then add(res, "Photo Mode look: " .. LK.lookKey(s or nil, h or nil, w or nil)) end
				end
			end
		end
	end
	f.env = { name = "dry", atmosphere = copy(FILE_ATMO) }
	f.env.atmosphere.cloudCoverage = 0.4
	f.api = {
		type = {
			ComponentType = { GAME_TIME = "GAME_TIME", GAME_SPEED = "GAME_SPEED", GAME_SCRIPT = "GAME_SCRIPT" },
			Clock = { new = function() return { getTime = function() return f.now * 1000 end } end },
			AppConfig = { new = function() f.appCalls = f.appCalls + 1; error("setups never touch the AppConfig") end },
		},
		-- the setups never read or write the game's settings (mod.io review): any AppConfig call is counted
		util = setmetatable({}, { __index = function(__, k)
			return function() f.appCalls = f.appCalls + 1; error("api.util." .. tostring(k) .. " called") end
		end }),
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
			sendCommand = function(c) c.apply() end,
			makeGameSetTimeOfDayCmd = function(s) return { apply = function() f.time = s end } end,
			makeGameSetSpeedCmd = function(s) return { apply = function() f.speed = s end } end,
			makeGameSetCloudCoverageCmd = function() return { apply = function() end } end,
			makeScriptingSendEventCmd = function(__, id, __, p)
				return { apply = function()
					if id == "GameTime" then f.gs.timeOfDayMode = p.mode else f.gs.weatherMode = p.weatherMode end
				end }
			end,
		},
		res = {
			environmentRep = {
				find = function(res) return f.ids[res] or -1 end,
				get = function(id)
					local r = f.byId[id]
					return { name = r.name, res = r.res, atmosphere = copy(FILE_ATMO) }
				end,
			},
		},
		gui = {
			rendering = {
				getEnvironment = function() return { name = f.env.name, res = f.env.res, atmosphere = copy(f.env.atmosphere) } end,
				setEnvironment = function(e) f.env = { name = e.name, res = e.res, atmosphere = copy(e.atmosphere) } end,
			},
			game = {
				getEnvironment = function() return f.gameRes end,
				setEnvironment = function() error("game.setEnvironment must never be called") end,
				getGuiSaveData = function(k) return f.save[k] end,
				setGuiSaveData = function(k, d) f.save[k] = d; f.saveWrites = f.saveWrites + 1 end,
			},
			camera = {
				getEye = function() return { x = 0, y = 0 } end,
				getCenter = function() return { x = 0, y = -100 } end,
				getCameraData = function() return { w = 0 } end,
			},
		},
	}
	return f
end

--- pm_sky + pm_setups on a fake api; pm_hud stubbed (labels); our save data written as pm_window does.
local function start(keepFake)
	if not keepFake or fake == nil then fake = newFake() end
	reset_modules()
	P = ug_require "square_photo_mode::/photo_mode/pm_setup.lua"
	L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
	set_global("api", fake.api)
	H = { hidden = false }
	H.labelsHidden = function() return H.hidden end
	H.setLabels = function(on) H.hidden = on end
	stub_module("square_photo_mode::/photo_mode/gui/pm_hud.lua", H)
	sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
	G = ug_require "square_photo_mode::/photo_mode/gui/pm_setups.lua"
	G.hq = false
	G.hqOn = function() return G.hq end
	G.hqSwitchOn = function() G.hq = true end
	-- pm_window.lua's one writer: setGuiSaveData replaces the whole table, so every part goes out together
	local function persist()
		local old = fake.save["square_photo_mode"]
		local views = type(old) == "table" and type(old.views) == "table" and old.views or {}
		fake.save["square_photo_mode"] = { v = 1, views = views, light = sky.saveMarker(), last = G.lastData(),
			setups = G.libraryData() }
	end
	sky.persist = persist
	G.persist = persist
	G.start()
	sky.start()
end

--- What the pm_button.script.lua pause menu does (round 16 order): capture, then everything back.
local function pauseMenu()
	local kept = G.capture("pause menu")
	sky.pauseMenu()
	return kept
end

test("named setups: written at once into our GUI save data with the views and markers, read back at the game start", function()
	fake = newFake()
	fake.save["square_photo_mode"] = { v = 1, views = { { id = 1, name = "View" } } }
	start(true)
	sky.look("dramatic", "misty_valley")
	sky.set({ time = 64800, day = 300 }, "test")
	local id = G.saveNew("Golden 1")
	eq(id, 1); eq(G.editing(), 1, "the name field opens for the new setup"); eq(G.selected(), 1)
	local mine = fake.save["square_photo_mode"]
	eq(#mine.setups.list, 1, "written in the click (GUI save data: no frame rule)")
	eq(mine.views[1].name, "View", "the views kept"); ok(mine.light ~= nil, "the light marker kept")
	ok(mine.last ~= nil, "the last setup kept")
	G.saveNew("Two")
	local stored = fake.save["square_photo_mode"].setups
	eq(#stored.list, 2); eq(stored.list[1].name, "Golden 1"); eq(stored.list[1].look.sky, "dramatic")
	eq(stored.list[1].look.haze, "misty_valley"); eq(stored.list[1].values.time, 64800); eq(stored.list[1].values.day, 300)
	-- a light change rewrites the save data: the setups go with it
	sky.set({ time = 1000 }, "test")
	sky.pauseMenu()
	eq(#fake.save["square_photo_mode"].setups.list, 2, "a marker write keeps the setups")
	-- the same savegame loaded again: a fresh Lua state
	start(true)
	eq(#G.library(), 2); eq(G.library()[2].name, "Two")
	ok(G.rename(2, "My dark night")); ok(G.remove(1))
	eq(#fake.save["square_photo_mode"].setups.list, 1)
	eq(fake.save["square_photo_mode"].setups.list[1].name, "My dark night")
	eq(fake.save["square_photo_mode"].views[1].name, "View")
	eq(fake.appCalls, 0, "the game's settings never touched")
end)

test("named setups: per savegame; another save loaded in the same session has its own (none)", function()
	start()
	G.saveNew("Mine")
	eq(#G.library(), 1)
	local first = fake.save["square_photo_mode"]
	fake.save = {} -- another savegame, same Lua state (pm_button calls G.start at every game start)
	G.select(1)
	G.start()
	eq(#G.library(), 0, "no setups in the other save"); eq(G.selected(), nil)
	fake.save = { square_photo_mode = first }
	G.start()
	eq(#G.library(), 1, "the first save's setups again"); eq(G.library()[1].name, "Mine")
end)

test("named setups: malformed save data tolerated, the cap kept", function()
	for __, bad in ipairs({ "junk", 7, { setups = "x" }, { setups = { list = 5 } },
		{ setups = { list = { "junk", { id = 2, name = "ok" }, { id = 2, name = "repeat" } } } } }) do
		fake = newFake()
		fake.save["square_photo_mode"] = bad
		start(true)
		local n = (type(bad) == "table" and type(bad.setups) == "table" and type(bad.setups.list) == "table") and 1 or 0
		eq(#G.library(), n, "malformed: " .. tostring(bad))
	end
	fake = newFake()
	local big = { list = {} }
	for i = 1, 40 do big.list[i] = { id = i, name = "s" .. i } end
	fake.save["square_photo_mode"] = { setups = big }
	start(true)
	eq(#G.library(), P.CAP)
	eq(G.saveNew("more"), nil, "full: nothing added")
	ok(G.remove(1))
	eq(#fake.save["square_photo_mode"].setups.list, P.CAP - 1, "the next write keeps at most CAP")
	-- a failing write is logged, never retried in a loop
	local writes = fake.saveWrites
	fake.api.gui.game.setGuiSaveData = function() error("no save") end
	ok(G.remove(2)); eq(#G.library(), P.CAP - 2); eq(fake.saveWrites, writes)
end)

test("load: the look, the values, the freeze; High graphics mode and labels only switched on", function()
	start()
	sky.look("storybook", nil, "wild")
	sky.set({ time = 20000, day = 50, cloud = 0.8, cloudScattering = 0.01 }, "test")
	sky.setFreeze(true, "test")
	G.hq, H.hidden = true, true
	G.saveNew("Night")
	-- everything else now
	sky.pauseMenu()
	G.hq, H.hidden = false, false
	eq(fake.env.res, "::/climates/dry/dry.env"); ok(not sky.active()); ok(not sky.frozen())
	ok(G.load(1))
	eq(fake.env.res, LK.lookResName("dry", "storybook", nil, "wild"))
	eq(fake.time, 20000); eq(fake.env.atmosphere.dayOfYear, 50); eq(fake.env.atmosphere.cloudCoverage, 0.8)
	eq(fake.env.atmosphere.cloudScattering, 0.01, "the cloud density")
	ok(sky.frozen()); eq(fake.speed, 0)
	ok(G.hq, "High graphics mode switched on"); ok(H.hidden, "labels hidden")
	-- a setup saved with them off never switches them off
	G.saveNew("Plain")
	G.overwrite(2)
	local plain = P.find(G.library(), 2)
	plain.hq, plain.labels = false, false
	G.load(2)
	ok(G.hq); ok(H.hidden)
	-- a setup with the climate's own look turns the look off; one unfrozen unfreezes
	local list = G.library()
	list[2].look, list[2].freeze = nil, false
	G.load(2)
	eq(fake.env.res, "::/climates/dry/dry.env"); ok(not sky.frozen())
end)

test("last setup: the pause menu puts the player's values back, Restore last setup brings the picture back", function()
	start()
	eq(G.last(), nil)
	sky.look("dramatic", "misty_valley")
	sky.set({ time = 70000, cloud = 0.1 }, "test")
	sky.setFreeze(true, "test")
	ok(G.last() ~= nil, "captured at every change")
	ok(pauseMenu(), "the pause menu keeps the picture")
	eq(fake.env.res, "::/climates/dry/dry.env"); eq(fake.time, 30000); ok(not sky.frozen())
	local last = G.last()
	eq(last.look.sky, "dramatic", "the restore did not overwrite it"); eq(last.values.time, 70000); eq(last.freeze, true)
	eq(fake.save["square_photo_mode"].last.look.haze, "misty_valley", "kept in this save's GUI save data")
	ok(G.restoreLast())
	eq(fake.env.res, LK.lookResName("dry", "dramatic", "misty_valley", nil))
	eq(fake.time, 70000); eq(fake.env.atmosphere.cloudCoverage, 0.1); ok(sky.frozen())
	-- the pause menu with nothing of ours on keeps the last one
	pauseMenu()
	ok(not pauseMenu(), "nothing on: nothing captured"); eq(G.last().values.time, 70000)
end)

test("last setup: only a look on, the override off: Restore leaves the override alone", function()
	start()
	sky.look("storybook")
	pauseMenu()
	eq(G.last().values, nil); eq(G.last().look.sky, "storybook")
	G.restoreLast()
	ok(not sky.active(), "no override begun"); eq(fake.gs.timeOfDayMode, "Dynamic", "the day cycle untouched")
	eq(fake.env.res, LK.lookResName("dry", "storybook", nil, nil))
end)

test("last setup: an untick of the override keeps the picture first", function()
	start()
	sky.set({ time = 50000 }, "test")
	sky.set({ time = 51000 }, "test")
	sky.restore("checkbox")
	eq(fake.time, 30000); eq(G.last().values.time, 51000)
end)

test("last setup: read back from the save at the game start; junk ignored; a save from before round 16 has none", function()
	start()
	sky.look("dramatic")
	sky.set({ time = 4000 }, "test")
	pauseMenu()
	start(true) -- the same save loaded again
	eq(G.last().look.sky, "dramatic"); eq(G.last().values.time, 4000)
	fake.save["square_photo_mode"].last = { look = "junk", values = "x", freeze = "no" }
	start(true)
	eq(G.last(), nil)
	fake.save["square_photo_mode"] = { v = 1, views = {} }
	start(true)
	eq(G.last(), nil)
end)

test("an unknown climate: a setup's look is left out, its values still go on", function()
	start()
	fake.gameRes = "my_mod::/climates/moon/moon.env"
	G.S.lib = { P.valid({ id = 1, name = "x", look = { sky = "dramatic" }, values = { time = 1234 } }) }
	G.load(1)
	eq(fake.env.name, "dry", "no switch"); eq(fake.time, 1234)
end)

test("Legacy: switches to the base game's (Legacy) environment; a haze or water look ends it", function()
	start()
	sky.layer("sky", "legacy")
	eq(fake.env.res, "::/climates/dry/dry_old.env"); eq(sky.status().sky, "legacy")
	eq(fake.env.atmosphere.cloudCoverage, 0.4, "live values carried over")
	sky.layer("haze", "misty_valley")
	eq(fake.env.res, LK.lookResName("dry", nil, "misty_valley", nil), "Legacy ended by a haze look")
	sky.layer("sky", "legacy")
	sky.pauseMenu()
	eq(fake.env.res, "::/climates/dry/dry.env")
	-- a game start with Legacy still rendered (the GUI state outlived a load) switches back
	sky.layer("sky", "legacy")
	fake.save["square_photo_mode"] = nil
	sky.start()
	eq(fake.env.res, "::/climates/dry/dry.env")
end)
