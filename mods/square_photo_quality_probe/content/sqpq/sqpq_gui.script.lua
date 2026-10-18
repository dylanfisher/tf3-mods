-- Photo Quality probe GUI plugin (top-left mod button ridge). DEV only, never upload.
--
--   Q1  can a mod GUI state call api.util.getAppConfig / setAppConfig? ("start", "boost" lines, ERROR on failure)
--   Q2  does setAppConfig apply the graphics settings mid-game? Read-back after the write plus frame times
--       ("frames" every FRAME_LOG_US: a heavier preset should raise ms per frame), and what the player sees.
--   Q3  persistence: setAppConfig does not save (api/tealdef/api/util.d.tl:261), but the game saves values left
--       set (docs/findings/map-camera.md "Graphics settings from a mod"), and quitting to the main menu runs no
--       react.onUnmount (2026-10-13_0040_sqpq). So the probe restores when the pause menu opens (react event
--       "openPauseMenu", fired by the game bar's menu button that Esc / IA_MENU is forwarded to,
--       game_bar.tl:1195-1210; every quit goes through it), and keeps a safety net: boost on first saves
--       { boosted, orig } in AppConfig.mainMenuState[modId]; the next game start restores the keys still at the
--       boost value ("marker found"). Param restore_on_exit=No skips the pause-menu restore (safety net only).
--   Q4  geometry tiers written at load (mod.script.lua): "tiers" read-back from this state.
--
-- The button toggles boost on / off. Boost: snapshot the graphics keys, apply the Very High preset
-- (textures only with include_textures), the highest supported MSAA, resolution scale 100 % (not saved).
-- Off: the snapshot's keys on the current config, marker cleared, saved. Nothing goes into the savegame.
--
-- Second button "SQPQ tests": the runs E / F window (sqpq_tests.lua, T1-T12). Its timers run from this plugin's onStep;
-- the pause menu and unmount put back whatever a test left changed (tests.restoreAll).

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"
local common = require "square_photo_quality_probe::/sqpq/sqpq_common.lua"
local tests = require "square_photo_quality_probe::/sqpq/sqpq_tests.lua" -- runs E, F (Photo Mode tests)

local CONFIG_POLL_US = 1000000 -- compare the AppConfig every 1 s
local FRAME_LOG_US = 5000000 -- frame time summary every 5 s
local FRAME_MAX = 2000

local S = {
	started = false,
	settings = nil,
	clock = nil,
	snapshot = nil, -- AppConfig copy taken when boost turned on; nil = off
	lastText = nil,
	nextPollUs = 0,
	lastFrameUs = nil,
	frames = {},
	nextFrameLogUs = 0,
	shown = nil,
}

local function nowUs()
	if S.clock == nil then S.clock = api.type.Clock.new() end
	return S.clock:getTime()
end

local function buttonText()
	return S.snapshot ~= nil and "SQPQ boost ON" or "SQPQ boost off"
end

local function refreshButton()
	if S.shown ~= nil then
		local ok = pcall(function()
			if not S.shown:hasExpired() then S.shown:set(buttonText()) end
		end)
		if not ok then S.shown = nil end
	end
end

local function currentText()
	return common.configText(api.util.getAppConfig())
end

local function maxMsaa()
	local ok, list = pcall(function() return app.getSupportedMSAASampleCounts() end)
	if not ok or list == nil then return common.BOOST.numMSAASamples, "fallback(" .. tostring(list) .. ")" end
	local best, parts = nil, {}
	for i = 1, #list do
		local v = tonumber(list[i])
		parts[#parts + 1] = tostring(list[i])
		if v ~= nil and (best == nil or v > best) then best = v end
	end
	return best or common.BOOST.numMSAASamples, "supported=" .. table.concat(parts, ",")
end

-- Snapshot = plain table of the graphics keys only, so a restore never reverts other settings
-- (mainMenuState of other mods, audio, keys) changed in the meantime.
local function graphicsOf(cfg)
	local t = {}
	for _, key in ipairs(common.GRAPHICS_KEYS) do
		local ok, v = pcall(function() return cfg[key] end)
		if ok and v ~= nil then t[key] = v end
	end
	return t
end

local function snapshotText(t)
	local parts = {}
	for _, key in ipairs(common.GRAPHICS_KEYS) do
		if t[key] ~= nil then parts[#parts + 1] = key .. "=" .. tostring(t[key]) end
	end
	return table.concat(parts, " ")
end

--- Copy of the current AppConfig with our mainMenuState marker set (marker table) or cleared (nil).
local function configWithMarker(marker)
	local cfg = api.type.AppConfig.new(api.util.getAppConfig())
	local mm = cfg.mainMenuState
	local t = {}
	if mm ~= nil then for k, v in pairs(mm) do t[k] = v end end
	t[common.MOD_ID] = marker
	cfg.mainMenuState = t
	return cfg
end

local function readMarker()
	local ok, m = pcall(function()
		local mm = api.type.AppConfig.new(api.util.getAppConfig()).mainMenuState
		return mm ~= nil and mm[common.MOD_ID] or nil
	end)
	if ok then return m end
	common.log("marker read ERROR " .. tostring(m))
	return nil
end

local function apply(cfg, why, save)
	local t0 = nowUs()
	api.util.setAppConfig(cfg, false)
	local ms = (nowUs() - t0) / 1000
	if save then api.util.saveAppConfig() end
	S.lastText = currentText()
	common.log(string.format("%s setAppConfig ms=%.1f saved=%s readback %s", why, ms, tostring(save == true), S.lastText))
end

local function boostOn()
	S.snapshot = graphicsOf(api.util.getAppConfig())
	common.log("boost before " .. snapshotText(S.snapshot))
	-- 1) marker with the original values, saved to disk while the graphics are still the player's own
	apply(configWithMarker({ boosted = true, orig = S.snapshot }), "boost marker", true)
	-- 2) the boost itself, not saved
	local cfg = api.type.AppConfig.new(api.util.getAppConfig())
	for key, value in pairs(common.BOOST) do cfg[key] = value end
	local msaa, msaaNote = maxMsaa()
	cfg.numMSAASamples = msaa
	if S.settings.include_textures then cfg.textureQuality = common.BOOST_TEXTURES end
	common.log(string.format("boost want msaa=%s (%s) textures=%s", tostring(msaa), msaaNote,
		tostring(S.settings.include_textures)))
	apply(cfg, "boost on", false)
end

--- Puts the snapshot's graphics keys back on the current config, clears the marker and saves.
local function restore(orig, why)
	local cfg = configWithMarker(nil)
	for key, value in pairs(orig) do cfg[key] = value end
	apply(cfg, why, true)
end

local function boostOff(why)
	local snap = S.snapshot
	S.snapshot = nil
	restore(snap, "boost off(" .. why .. ")")
	refreshButton()
end

local function toggle()
	if S.snapshot == nil then boostOn() else boostOff("click") end
	refreshButton()
end

--- Safety net: a marker left from a session that ended boosted (Cmd+Q, crash, quit without the pause menu).
--- Restores only the keys still at the boost value, so changes the player made since are kept.
local function recoverMarker()
	local m = readMarker()
	if m == nil then
		common.log("marker none")
		return
	end
	local okO, orig = pcall(function() return m.orig end)
	if not okO or orig == nil then
		common.log("marker without orig, clearing")
		apply(configWithMarker(nil), "marker clear", true)
		return
	end
	local cur = api.util.getAppConfig()
	local put, kept = {}, {}
	for _, key in ipairs(common.GRAPHICS_KEYS) do
		local okV, v = pcall(function() return orig[key] end)
		if okV and v ~= nil then
			local boosted = common.BOOST[key]
			if key == "textureQuality" then boosted = common.BOOST_TEXTURES end
			if key == "numMSAASamples" then boosted = maxMsaa() end
			if boosted ~= nil and cur[key] == boosted and v ~= boosted then
				put[key] = v
			elseif boosted ~= nil and v ~= boosted then
				kept[#kept + 1] = key
			end
		end
	end
	common.log(string.format("marker found: restoring %s | kept (changed since) %s", snapshotText(put),
		#kept > 0 and table.concat(kept, ",") or "-"))
	restore(put, "recover")
end

local function start()
	S.started = true
	S.settings = common.runtimeSettings()
	common.log(string.format("gui start source=%s %s", S.settings.source, common.settingsText(S.settings)))
	S.lastText = currentText()
	common.log("start config " .. S.lastText)
	local okR, errR = pcall(recoverMarker)
	if not okR then common.log("recover ERROR " .. tostring(errR)) end
	local ok, text = pcall(function() return common.tiersText(api.res.getBaseConfig().settings) end)
	common.log("tiers " .. (ok and text or ("ERR " .. tostring(text))))
end

local function logFrames()
	local t = S.frames
	S.frames = {}
	if #t == 0 then return end
	local sum = 0
	for i = 1, #t do sum = sum + t[i] end
	table.sort(t)
	local p95 = t[math.max(1, math.min(#t, math.floor(0.95 * #t + 0.5)))]
	common.log(string.format("frames boost=%s n=%d meanMs=%.2f p50Ms=%.2f p95Ms=%.2f maxMs=%.2f",
		S.snapshot ~= nil and "on" or "off", #t, sum / #t, t[math.floor((#t + 1) / 2)], p95, t[#t]))
end

local function onFrame()
	if not S.started then start() end
	local now = nowUs()
	if S.lastFrameUs ~= nil and #S.frames < FRAME_MAX then
		S.frames[#S.frames + 1] = (now - S.lastFrameUs) / 1000
	end
	S.lastFrameUs = now
	if now >= S.nextFrameLogUs then
		S.nextFrameLogUs = now + FRAME_LOG_US
		logFrames()
	end
	if now >= S.nextPollUs then
		S.nextPollUs = now + CONFIG_POLL_US
		local text = currentText()
		if text ~= S.lastText then
			common.log("config changed outside the probe: " .. text)
			S.lastText = text
		end
	end
end

local function onUnmount()
	common.log(string.format("unmount boost=%s restore_on_exit=%s", S.snapshot ~= nil and "on" or "off",
		tostring(S.settings and S.settings.restore_on_exit)))
	if S.snapshot ~= nil and S.settings ~= nil and S.settings.restore_on_exit then boostOff("unmount") end
end

local PhotoQualityProbePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension,
	"PhotoQualityProbePlugin", function()
	local shown = react.useState(buttonText())
	S.shown = shown
	react.onStep(function()
		local ok, err = pcall(onFrame)
		if not ok and not S.frameErrorLogged then
			S.frameErrorLogged = true
			common.log("frame ERROR " .. tostring(err))
		end
		local okT, errT = pcall(tests.step)
		if not okT and not S.testsErrorLogged then
			S.testsErrorLogged = true
			common.log("T* step ERROR " .. tostring(errT))
		end
	end)
	react.onEvent("openPauseMenu", function()
		local ok, err = pcall(function()
			common.log(string.format("pause menu opened boost=%s", S.snapshot ~= nil and "on" or "off"))
			if S.snapshot ~= nil and S.settings ~= nil and S.settings.restore_on_exit then boostOff("pause menu") end
		end)
		if not ok then common.log("pause ERROR " .. tostring(err)) end
		local okT, errT = pcall(tests.restoreAll, "pause menu")
		if not okT then common.log("T* pause ERROR " .. tostring(errT)) end
	end)
	-- runs F T9: react events named like the cutscene task's GUI events; tests.onEvent logs them only while T9 runs
	for _, name in ipairs(tests.EVENT_NAMES) do
		react.onEvent(name, function(_evName, param)
			local okE, errE = pcall(tests.onEvent, name, param)
			if not okE then common.log("T9 event ERROR " .. tostring(errE)) end
		end)
	end
	react.onUnmount(function()
		local ok, err = pcall(onUnmount)
		if not ok then common.log("unmount ERROR " .. tostring(err)) end
		local okT, errT = pcall(tests.restoreAll, "unmount")
		if not okT then common.log("T* unmount ERROR " .. tostring(errT)) end
	end)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { tooltip = "DEV Photo Quality Probe. Click: graphics boost on / off\n(Very High preset, max MSAA, 100 % resolution scale).\nLogs [SQPQ] lines to stdout.txt." },
				content = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = shown:old() },
				onClick = function()
					local ok, err = pcall(toggle)
					if not ok then common.log("toggle ERROR " .. tostring(err)) end
				end,
			},
			builtin.Button{
				meta = { tooltip = "DEV Photo Mode tests (runs E, F): screenshots, hide UI,\ntime of day, pause, environment, camera tool, cutscene camera,\natmosphere, bloom / HDR keys, shader override.\nLogs [SQPQ] T<n> lines." },
				content = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = "SQPQ tests" },
				onClick = function()
					local ok, err = pcall(tests.toggleWindow)
					if not ok then common.log("T* window ERROR " .. tostring(err)) end
				end,
			},
		},
	}
end)

-- .script.lua resources expose their exports through data(), not a return value
function data()
	return {
		PhotoQualityProbePlugin = PhotoQualityProbePlugin,
	}
end
