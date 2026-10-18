-- pm_button.script.lua (Photo Mode top-bar button + "Highest graphics" switch) on fake react / api / window /
-- driver. The button only opens / closes the window; the window's toggle runs the staged switch (marker, then
-- pm_core.STAGES one setAppConfig each, STAGE_DELAY_FRAMES apart); off = one restore. No window open / close in
-- a frame with a setAppConfig of ours (the switch crashed the renderer twice in game, docs/findings/map-camera.md
-- "Graphics settings from a mod"). Shadows, geometry, terrain and grass are never written (docs/findings/
-- map-camera.md "Changing render-buffer settings at runtime crashes").

local PLAYER = {
	textureQuality = 1, terrainTextureQuality = 1, numMSAASamples = 1, useSsao = false, ssrQuality = 1,
	shadowQuality = 0, geometryQuality = 1, terrainQuality = 0, grassQuality = 1, resolutionScale = 0.75,
}
local GRAPHICS = {
	"textureQuality", "terrainTextureQuality", "numMSAASamples", "useSsao", "ssrQuality",
	"shadowQuality", "geometryQuality", "terrainQuality", "grassQuality", "resolutionScale",
}

local ev, plugin, cfg, onSet, frame, saved, core, D, startEv

local function copyCfg(c)
	local t = {}
	for k, v in pairs(c) do t[k] = v end
	local mm = {}
	for k, v in pairs(c.mainMenuState or {}) do mm[k] = v end
	t.mainMenuState = mm
	return t
end

local function record(e) ev[#ev + 1] = e end

--- What a setAppConfig call changed: "marker" / "restore" (the marker set / cleared), else the graphics keys.
local function classify(old, new)
	local had = old.mainMenuState["square_photo_mode"] ~= nil
	local has = new.mainMenuState["square_photo_mode"] ~= nil
	if has and not had then return "marker" end
	if had and not has then return "restore" end
	local keys = {}
	for __, k in ipairs(GRAPHICS) do
		if old[k] ~= new[k] then keys[#keys + 1] = k end
	end
	return table.concat(keys, ",")
end

before_each(function()
	reset_modules()
	ev = {}
	onSet = nil
	frame = 0
	saved = nil
	cfg = copyCfg(PLAYER)
	set_global("app", { getSupportedMSAASampleCounts = function() return { 1, 2, 4, 8 } end })
	set_global("api", {
		type = {
			AppConfig = { new = function(c) return copyCfg(c) end },
			Clock = { new = function() return { getTime = function() return 0 end } end },
			Vec4f = { new = function() return {} end },
		},
		gui = {
			StyleSheet = { new = function() return {} end },
			genericRep = {
				find = function() return 1 end,
				get = function() return { data = { Ok = { 0, 1, 0, 1 } } } end,
			},
		},
		engine = { config = { getModParams = function() return {} end } },
		util = {
			getAppConfig = function() return cfg end,
			setAppConfig = function(c, __)
				local kind = classify(cfg, c)
				record("set@" .. frame .. ":" .. kind)
				cfg = copyCfg(c)
				if onSet ~= nil then onSet(kind) end
			end,
			saveAppConfig = function() saved = copyCfg(cfg) end,
		},
	})
	local recipe
	local react = {
		RegisterPluginRecipe = function(__, __, fn) recipe = fn return fn end,
		useRefLazy = function(f)
			local v = f()
			return { get = function() return v end, set = function(__, x) v = x end, hasExpired = function() return false end }
		end,
		useRef = function(v0)
			local v = v0
			return { get = function() return v end, set = function(__, x) v = x end, hasExpired = function() return false end }
		end,
		useState = function(v0)
			local v = v0
			return {
				old = function() return v end,
				set = function(__, x) v = x end,
				hasExpired = function() return false end,
			}
		end,
	}
	local steps, events = {}, {}
	react.onStep = function(fn) steps[#steps + 1] = fn end
	react.onEvent = function(name, fn) events[name] = fn end
	stub_module("::/gui/main/react.lua", react)
	local pass = function(t) return t end
	stub_module("::/gui/main/builtin.lua", {
		ToggleButton = pass, Button = pass, ImageView = pass, TextView = pass, BoxLayout = pass,
		type = { Orientation = { Horizontal = 0 } },
	})
	stub_module("::/gui/main/main_mod_button_area.tl", { MainModButtonAreaExtension = {} })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { style = t } end })
	local timer = { start = function() return 0 end, stop = function() end, phase = function() end }
	stub_module("square_photo_mode::/photo_mode/gui/pm_perf.lua", { perf = timer, perfStep = timer })
	stub_module("square_photo_mode::/photo_mode/gui/pm_driver.lua", {
		stopAll = function(why) record("stopAll:" .. tostring(why)) end,
		busy = function() return false end,
		step = function() end,
		setStatus = function() end,
		followEnded = function() end,
	})
	local window = {
		open = function() record("window.open@" .. frame) return true end,
		close = function() record("window.close@" .. frame) end,
		resetGame = function() end,
		changed = function() end,
	}
	stub_module("square_photo_mode::/photo_mode/gui/pm_window.lua", window)
	stub_module("square_photo_mode::/photo_mode/gui/pm_hud.lua", {
		busy = function() return false end,
		step = function() end,
		start = function() record("hud.start") end,
		pauseMenu = function() record("hud.pauseMenu") end,
		tourHide = function() end,
	})
	stub_module("square_photo_mode::/photo_mode/gui/pm_sky.lua", {
		busy = function() return false end,
		stepFrame = function() end,
		start = function() record("sky.start") end,
		pauseMenu = function() record("sky.pauseMenu") end,
	})
	core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
	D = core.STAGE_DELAY_FRAMES
	ug_require "square_photo_mode::/photo_mode/gui/pm_button.script.lua"
	ok(recipe ~= nil, "plugin registered")
	plugin = {
		window = window,
		render = function() return recipe() end,
		step = function()
			frame = frame + 1
			for __, fn in ipairs(steps) do fn() end
		end,
		event = function(name) events[name]() end,
	}
	plugin.root = plugin.render()
	plugin.click = function() plugin.root.children[1].onValueChange(1) end
	plugin.step() -- first frame: start (no marker, nothing to recover)
	startEv = ev
	ev = {}
end)

local function only(prefixes)
	local out = {}
	for __, e in ipairs(ev) do
		for __, p in ipairs(prefixes) do
			if e:sub(1, #p) == p then out[#out + 1] = e break end
		end
	end
	return out
end

local function steps(n)
	for __ = 1, n do plugin.step() end
end

--- setAppConfig calls without the frame numbers.
local function sets()
	local out = {}
	for __, e in ipairs(only({ "set@" })) do out[#out + 1] = e:gsub("^set@%d+:", "") end
	return out
end

local function openWindow()
	plugin.click()
	plugin.step()
	ev = {}
end

local function hqOnFully()
	plugin.window.onHqToggle()
	steps(D * #core.STAGES + 2)
end

local function frameOf(e) return tonumber(e:match("@(%d+)")) end

test("button click opens the window in the next frame, no graphics change; click again closes it", function()
	plugin.click()
	eq(only({ "window", "set@" }), {}, "nothing on the click itself")
	plugin.step()
	eq(only({ "window", "set@" }), { "window.open@" .. frame })
	steps(10)
	eq(sets(), {}, "no setAppConfig from opening the window")
	plugin.click()
	plugin.step()
	eq(only({ "window.close", "stopAll" }), { "stopAll:window", "window.close@" .. frame })
	eq(sets(), {})
	eq(cfg.textureQuality, 1)
end)

test("HQ toggle: marker before stage 1, then the stages in order, each its own call, delay frames apart", function()
	openWindow()
	plugin.window.onHqToggle()
	ok(plugin.window.hqOn(), "toggle shows on at once")
	plugin.step()
	eq(sets(), {}, "nothing on the next frame")
	steps(D * #core.STAGES + 2)
	eq(sets(), {
		"marker",
		"textureQuality,terrainTextureQuality",
		"useSsao,ssrQuality",
		"numMSAASamples,resolutionScale",
		"geometryQuality",
		"terrainQuality",
		"grassQuality",
	})
	local fr = {}
	for __, e in ipairs(only({ "set@" })) do fr[#fr + 1] = frameOf(e) end
	eq(fr[1], fr[2], "marker in the frame of stage 1, before it")
	for i = 3, #fr do eq(fr[i] - fr[i - 1], D, "stage " .. (i - 1) .. " " .. D .. " frames after the one before") end
	ok(D >= 2, "at least 2 frames apart")
	eq(cfg.textureQuality, 2)
	eq(cfg.numMSAASamples, 8)
	eq(cfg.resolutionScale, 1.0)
	eq(cfg.shadowQuality, 0, "shadows never changed (runtime change crashed the renderer)")
	eq(cfg.geometryQuality, 2, "geometry raised, alone in its stage")
	eq(cfg.terrainQuality, 2)
	eq(cfg.grassQuality, 2)
	ok(saved.mainMenuState["square_photo_mode"] ~= nil, "marker saved")
	eq(saved.mainMenuState["square_photo_mode"].orig.textureQuality, 1, "saved with the player's values")
	eq(saved.textureQuality, 1, "the boost itself never saved")
end)

test("stages with nothing to change make no call", function()
	cfg.useSsao, cfg.ssrQuality = true, 2
	openWindow()
	hqOnFully()
	eq(sets(), {
		"marker",
		"textureQuality,terrainTextureQuality",
		"numMSAASamples,resolutionScale",
		"geometryQuality",
		"terrainQuality",
		"grassQuality",
	})
end)

test("toggle off mid-sequence: no further stage, the staged restore with the player's values", function()
	openWindow()
	plugin.window.onHqToggle()
	steps(D + D) -- marker, stage 1, stage 2
	eq(#sets(), 3)
	plugin.window.onHqToggle()
	eq(plugin.window.hqOn(), false, "toggle shows off at once")
	steps(D * #core.STAGES + 2)
	eq(sets(), { "marker", "textureQuality,terrainTextureQuality", "useSsao,ssrQuality",
		"useSsao,ssrQuality", "restore" }, "restore stages with nothing to change make no call")
	for k, v in pairs(PLAYER) do eq(cfg[k], v, k) end
	eq(cfg.mainMenuState["square_photo_mode"], nil, "marker cleared")
	eq(saved.mainMenuState["square_photo_mode"], nil, "and saved")
end)

test("toggle off before stage 1: nothing changed, no call", function()
	openWindow()
	plugin.window.onHqToggle()
	plugin.step()
	plugin.window.onHqToggle()
	steps(20)
	eq(sets(), {})
end)

test("pause menu mid-sequence restores at once and stops the rest", function()
	openWindow()
	plugin.window.onHqToggle()
	steps(D) -- marker + stage 1
	ev = {}
	plugin.event("openPauseMenu")
	eq(sets(), { "restore" }, "in the event itself")
	eq(only({ "stopAll" }), { "stopAll:pause menu" })
	eq(only({ "hud" }), { "hud.pauseMenu" }, "labels / UI back on the pause menu")
	steps(20)
	eq(sets(), { "restore" }, "no stage after it")
	eq(plugin.window.hqOn(), false, "toggle shows off afterwards")
	for k, v in pairs(PLAYER) do eq(cfg[k], v, k) end
end)

test("pause menu with HQ on restores; the window is not closed in that frame", function()
	openWindow()
	hqOnFully()
	ev = {}
	plugin.event("openPauseMenu")
	eq(sets(), { "restore" })
	eq(only({ "window" }), {})
	eq(cfg.textureQuality, 1)
end)

test("an off asked for inside a stage's stall runs right after it", function()
	openWindow()
	onSet = function(kind)
		if kind == "textureQuality,terrainTextureQuality" then onSet = nil; plugin.event("openPauseMenu") end
	end
	plugin.window.onHqToggle()
	steps(D * #core.STAGES + 2)
	eq(sets(), { "marker", "textureQuality,terrainTextureQuality", "restore" })
	eq(cfg.textureQuality, 1)
end)

test("closing the window keeps HQ on; the button shows it", function()
	openWindow()
	hqOnFully()
	ev = {}
	plugin.click()
	plugin.step()
	ok(#only({ "window.close" }) == 1, "window closed")
	eq(only({ "stopAll" }), { "stopAll:window" }, "camera moves stopped")
	eq(sets(), {}, "no restore")
	eq(cfg.textureQuality, 2)
	local root = plugin.render()
	local b = root.children[1]
	eq(b.value, 0, "button released: window closed")
	ok(b.meta.styleSheet.style ~= nil and b.meta.styleSheet.style.borderColor ~= nil, "green contour while HQ is on")
	ok(b.meta.tooltip:find("High graphics mode: on", 1, true) ~= nil, "tooltip says so")
end)

test("the player's X keeps HQ on and stops the camera", function()
	openWindow()
	hqOnFully()
	ev = {}
	plugin.window.onUserClose()
	steps(5)
	eq(sets(), {})
	eq(only({ "stopAll" }), { "stopAll:window" })
	eq(cfg.textureQuality, 2)
end)

test("button state: pressed while the window is open, plain while HQ is off", function()
	-- (each render() of the fake makes fresh hooks, so render only after the actions)
	local b = plugin.root.children[1]
	eq(b.value, 0)
	eq(b.meta.tooltip:find("High graphics mode: on", 1, true), nil)
	openWindow()
	b = plugin.render().children[1]
	eq(b.value, 1)
	ok(b.meta.styleSheet.style == nil, "no contour while HQ is off")
end)

test("no window open / close in a frame with a setAppConfig", function()
	plugin.click() -- open request
	plugin.window.onHqToggle()
	for __ = 1, D * #core.STAGES + 4 do
		plugin.step()
		if frame % 2 == 0 then plugin.click() end -- open / close requests all through the sequence
	end
	plugin.window.onHqToggle()
	steps(D * #core.STAGES + 4)
	local setFrames, winFrames = {}, {}
	for __, e in ipairs(ev) do
		if e:sub(1, 4) == "set@" then setFrames[frameOf(e)] = true end
		if e:sub(1, 7) == "window." then winFrames[frameOf(e)] = true end
	end
	ok(next(winFrames) ~= nil and next(setFrames) ~= nil, "both happened")
	for f in pairs(winFrames) do eq(setFrames[f], nil, "frame " .. f) end
	eq(cfg.textureQuality, 1, "restored at the end")
	eq(cfg.numMSAASamples, 1)
end)

test("a stage waits a frame after the player's X", function()
	openWindow()
	plugin.window.onHqToggle()
	steps(D - 1)
	plugin.window.onUserClose() -- in the frame before stage 1
	plugin.step()
	eq(sets(), {}, "stage 1 postponed")
	plugin.step()
	eq(sets(), { "marker", "textureQuality,terrainTextureQuality" })
end)

-- Rev 1 feedback round 2 (2026-10-13): the staged restore

test("toggle off: the staged restore, stages in reverse, delay frames apart, marker cleared with the last", function()
	openWindow()
	hqOnFully()
	ev = {}
	plugin.window.onHqToggle()
	eq(plugin.window.hqOn(), false, "the checkbox shows off at once")
	eq(sets(), {}, "nothing on the click itself")
	plugin.step()
	eq(sets(), { "grassQuality" }, "first restore stage in the next frame")
	steps(D * #core.STAGES + 2)
	eq(sets(), {
		"grassQuality",
		"terrainQuality",
		"geometryQuality",
		"numMSAASamples,resolutionScale",
		"useSsao,ssrQuality",
		"restore",
	})
	local fr = {}
	for __, e in ipairs(only({ "set@" })) do fr[#fr + 1] = frameOf(e) end
	for i = 2, #fr do eq(fr[i] - fr[i - 1], D, "restore stage " .. i .. " " .. D .. " frames after the one before") end
	for k, v in pairs(PLAYER) do eq(cfg[k], v, k) end
	eq(cfg.mainMenuState["square_photo_mode"], nil, "marker cleared")
	eq(saved.mainMenuState["square_photo_mode"], nil, "and saved")
	eq(saved.textureQuality, 1, "saved with the player's values")
end)

test("the marker stays until the last restore stage (a crash mid-restore is repaired on the next load)", function()
	openWindow()
	hqOnFully()
	plugin.window.onHqToggle()
	steps(D * 5)
	ok(cfg.mainMenuState["square_photo_mode"] ~= nil, "still marked")
	eq(cfg.grassQuality, 1, "grass already back")
	eq(cfg.numMSAASamples, 1, "anti-aliasing already back")
	eq(cfg.textureQuality, 2, "textures not yet")
end)

test("pause menu during the staged restore: the rest in one call at once", function()
	openWindow()
	hqOnFully()
	plugin.window.onHqToggle()
	steps(D + 1) -- two restore stages
	ev = {}
	plugin.event("openPauseMenu")
	eq(sets(), { "restore" }, "one call, in the event")
	steps(20)
	eq(sets(), { "restore" }, "no stage after it")
	for k, v in pairs(PLAYER) do eq(cfg[k], v, k) end
	eq(plugin.window.hqOn(), false)
end)

test("ticked again during the staged restore: the stages run again and end on", function()
	openWindow()
	hqOnFully()
	plugin.window.onHqToggle()
	steps(D * 4 + 1) -- grass, terrain, geometry, MSAA / scale and SSAO / reflections back
	ev = {}
	plugin.window.onHqToggle()
	ok(plugin.window.hqOn(), "shows on")
	steps(D * #core.STAGES + 2)
	eq(sets(), { "useSsao,ssrQuality", "numMSAASamples,resolutionScale", "geometryQuality", "terrainQuality",
		"grassQuality" }, "only the keys the restore had put back")
	eq(cfg.numMSAASamples, 8); eq(cfg.textureQuality, 2)
	ok(cfg.mainMenuState["square_photo_mode"] ~= nil, "the marker of this boost kept")
	-- and off again: everything back
	plugin.window.onHqToggle()
	steps(D * #core.STAGES + 2)
	for k, v in pairs(PLAYER) do eq(cfg[k], v, k) end
end)

-- Changing render-buffer settings at runtime crashed the game (docs/findings/map-camera.md "Changing render-buffer
-- settings at runtime crashes"): shadows are never touched; geometry, terrain and grass one key per stage (round 19).
local UNSAFE = { "shadowQuality" }

test("safety net: a marker holding shadows / geometry / terrain / grass restores all but shadows", function()
	-- a session that ended boosted (old build)
	cfg.textureQuality, cfg.numMSAASamples = 2, 8
	cfg.shadowQuality, cfg.geometryQuality, cfg.terrainQuality, cfg.grassQuality = 2, 2, 2, 2
	cfg.mainMenuState["square_photo_mode"] = { boosted = true, orig = { textureQuality = 1, numMSAASamples = 1,
		shadowQuality = 0, geometryQuality = 1, terrainQuality = 0, grassQuality = 1 } }
	ev = {}
	plugin.render() -- a new mount: start runs on its first frame
	plugin.step()
	eq(sets(), { "restore" }, "one call: the marker cleared with the restore")
	eq(cfg.textureQuality, 1); eq(cfg.numMSAASamples, 1)
	eq(cfg.geometryQuality, 1); eq(cfg.terrainQuality, 0); eq(cfg.grassQuality, 1)
	for __, k in ipairs(UNSAFE) do eq(cfg[k], 2, k .. " left as it is") end
	eq(cfg.mainMenuState["square_photo_mode"], nil, "marker cleared")
end)

test("toggle on and off never changes shadows", function()
	cfg.shadowQuality = 1
	local function same(what)
		eq(cfg.shadowQuality, 1, what)
	end
	openWindow()
	hqOnFully()
	same("on")
	plugin.window.onHqToggle()
	steps(D * #core.STAGES + 2)
	same("staged restore")
	plugin.window.onHqToggle()
	steps(D)
	plugin.event("openPauseMenu")
	same("the pause menu's one-call restore")
	-- the player raises shadows while boosted: the restore puts back only our keys, never shadows
	plugin.window.onHqToggle()
	steps(D * #core.STAGES + 2)
	cfg.shadowQuality = 2
	plugin.event("openPauseMenu")
	eq(cfg.shadowQuality, 2, "the player's own shadow change kept")
	for __, e in ipairs(only({ "set@" })) do
		for __, k in ipairs(UNSAFE) do ok(not e:find(k, 1, true), e .. " wrote " .. k) end
	end
end)

test("light: restored on the pause menu; its save-data marker repaired before the labels' at a start", function()
	plugin.event("openPauseMenu")
	eq(only({ "hud.pauseMenu", "sky.pauseMenu" }), { "hud.pauseMenu", "sky.pauseMenu" })
	-- at the start: sky.start before hud.start (hud.start may rewrite our save data with an empty light marker)
	local order = {}
	for __, e in ipairs(startEv) do if e == "sky.start" or e == "hud.start" then order[#order + 1] = e end end
	eq(order, { "sky.start", "hud.start" })
end)

test("round 16: saved setups are written in a frame of their own, never mid-switch; saved only with the player's graphics", function()
	local G = ug_require "square_photo_mode::/photo_mode/gui/pm_setups.lua"
	local KEY = (ug_require "square_photo_mode::/photo_mode/pm_setup.lua").KEY
	G.S.lib = {}
	G.saveNew("A")
	eq(sets(), {}, "nothing in the click")
	plugin.step()
	eq(sets(), { "" }, "one setAppConfig with no graphics change")
	eq(saved.mainMenuState[KEY].list[1].name, "A", "saved to settings.lua")
	eq(cfg.textureQuality, 1)
	-- during the high graphics stages: waits; while on: in the config, not saved (it would save the boost)
	ev = {}
	openWindow()
	plugin.window.onHqToggle()
	G.saveNew("B")
	plugin.step()
	steps(D * #core.STAGES + 2)
	local s = sets()
	eq(s[1], "marker"); eq(s[#s], "", "written once the stages are done")
	for i = 2, #s - 1 do ok(s[i] ~= "", "no write between the stages") end
	eq(#saved.mainMenuState[KEY].list, 1, "not saved while the graphics are boosted")
	eq(#cfg.mainMenuState[KEY].list, 2, "but in the config")
	eq(saved.textureQuality, 1, "the boost never saved")
	-- the pause menu: the restore saves the current config, the setups with it
	G.saveNew("C")
	plugin.event("openPauseMenu")
	eq(#saved.mainMenuState[KEY].list, 3, "saved with the restore at the pause menu")
	eq(saved.textureQuality, 1)
	eq(saved.mainMenuState["square_photo_mode"], nil, "the high graphics marker cleared")
end)
