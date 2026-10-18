-- Photo Quality probe, runs E (Photo Mode phases 2-4): the "SQPQ tests" window. DEV only, never upload.
-- Plain Lua, pre-5.3. Steps and expected log lines: plans/square_photo_quality_probe/TESTING.md "Runs E".
--
-- Every action logs "[SQPQ] T<n> ..." with read-backs; every API call is in pcall; everything runs on the Main
-- Thread (button onClick and the plugin's react.onStep, which calls M.step). Each test keeps what it changed in
-- R.<test> and puts it back with its restore button, its timer, or M.restoreAll (pause menu, plugin unmount).
--
--   T1 screenshots    api.gui.camera.takeScreenshot(scale) (api/gui.d.tl:453; base uses 2: free_cam_options.tl:20-22)
--   T2 hide UI        setVisibilityByClass / setVisible on react.game-ui-root (game.tl:873), menu.gamebar
--                     (game.tl:421), menu.gamebar.bottom (game_bar.tl:204); toggleFreeCamera. Auto-restore 5 s.
--   T3 grid overlay   a full-screen compact mod Window, transparent inline background, mouse-transparent lines
--   T4 time of day    makeGameSetTimeOfDayCmd + GameTime SetMode Constant (game_bar_widgets.tl:408-431)
--   T5 pause          makeGameSetSpeedCmd(0) and back (GAME_SPEED.speedup)
--   T6 env live edits api.gui.rendering.get/setEnvironment atmosphere fields; CloudCoverage SetMode
--                     (game_bar_widgets.tl:520-556; the id is "CloudCoverage", key weatherMode)
--   T7 env resources  api.res.environmentRep (res.d.tl:135) + content/environments/sqpq_test.env.lua;
--                     switch as game_bar_widgets.tl:640-650 (rendering.setEnvironment + game.setEnvironment)
--   T8 camera tool    isVisibleRecursive("cameraManagerWindow") polled 2x/s; setVisible(..., true)
--                     (game_bar_widgets.tl:115-142), AppConfig.cameraTool
--
-- Runs F (camera effects), TESTING.md "Runs F":
--   T9 cutscene       api.gui.mission.playCutscene(filePath, resolveLanguageFolder, entityToEntityMap) (gui.d.tl:750-761)
--                     with content/mission/keyframes/[en/]sqpq_<mode>.lua; base task: clearToolStack +
--                     disableToolActions first, game speed after (mission/tasks/cutscene/cutscene.tl:35-40).
--                     Frames are computed in the file from _G.SQPQ_T9 / api.gui.camera / the map origin.
--   T10 atmosphere    untyped atmosphere fields (fogScaleLow/High, sunBloom, miePhaseG ...) on a getEnvironment copy
--   T11 AppConfig     dev keys bloomQuality / useLegacyHdr, one key per setAppConfig, one changed key at a time
--   T12 shader        presence of the opt-in DEV mod square_shader_override_probe (its compose.fs); instructions only

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl"
local common = require "square_photo_quality_probe::/sqpq/sqpq_common.lua"

local M = {}

local GAME_TIME_GS = "::/game_mechanics/game_time/game_time.gs"
local HIDE_US = 5000000
local CAMTOOL_POLL_US = 500000
local ENV_AUTO_BACK_US = 30000000 -- T7: a switched environment goes back by itself after 30 s (autosave safety)
local GRID_AUTO_CLOSE_US = 60000000 -- T3: in case the grid window catches the mouse and covers the probe window
local LINE_PX = 2
local STATUS_LINES = 4
local ENV_FILE = "environments/sqpq_test.env"

local R = {} -- what each test changed: R.t2 ... R.t8, R.t9 (cutscene), R.t10 (atmosphere), R.t11 (AppConfig key)
local tasks = {} -- { at = us, label = string, fn = function }
local status = {} -- last log lines shown in the window
local clock = nil
local version = 0
local windowState = nil

local function nowUs()
	if clock == nil then clock = api.type.Clock.new() end
	return clock:getTime()
end

local function log(tag, msg)
	local line = tag .. " " .. msg
	common.log(line)
	status[#status + 1] = line
	while #status > STATUS_LINES do table.remove(status, 1) end
	version = version + 1
end

local function try(tag, what, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then log(tag, what .. " ERROR " .. tostring(a)) end
	return ok, a, b
end

local function later(us, label, fn)
	tasks[#tasks + 1] = { at = nowUs() + us, label = label, fn = fn }
end

local function cancel(prefix)
	local keep = {}
	for _, t in ipairs(tasks) do
		if string.sub(t.label, 1, #prefix) ~= prefix then keep[#keep + 1] = t end
	end
	tasks = keep
end

local function fmt(v)
	if type(v) == "number" then
		if v == math.floor(v) and math.abs(v) < 1e9 then return string.format("%d", v) end
		return string.format("%.3f", v)
	end
	return tostring(v)
end

local function clockText(sec)
	if type(sec) ~= "number" then return tostring(sec) end
	local s = math.floor(sec)
	return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

---------------------------------------------------------------------------
-- Reads (each returns a value or a string starting with "ERR")

local function world() return api.engine.util.getWorld() end

local function readTimeOfDay()
	local ok, v = pcall(function()
		return api.engine.getComponent(world(), api.type.ComponentType.GAME_TIME).timeOfDaySec
	end)
	return ok and v or ("ERR " .. tostring(v))
end

local function readGameTimeState()
	local ok, st = pcall(function()
		local e = api.engine.system.gameScriptSystem.getEntityForGameScript(GAME_TIME_GS)
		local gs = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
		return gs.state
	end)
	if not ok then return { err = tostring(st) } end
	local out = {}
	for _, k in ipairs({ "timeOfDayMode", "timeOfDayTarget", "nextTimeOfDayChange", "weatherMode", "cloudCoverageTarget", "nextChange" }) do
		local okK, v = pcall(function() return st[k] end)
		out[k] = okK and v or "ERR"
	end
	return out
end

local function readSpeed()
	local ok, v = pcall(function()
		local s = api.engine.getComponent(world(), api.type.ComponentType.GAME_SPEED)
		return { speedup = s.speedup, millisPerDay = s.millisPerDay }
	end)
	return ok and v or { err = tostring(v) }
end

local function readWorldCloud()
	local ok, v = pcall(function() return api.engine.getComponent(world(), api.type.ComponentType.WORLD).cloudCoverage end)
	return ok and v or ("ERR " .. tostring(v))
end

local ATMO_KEYS = { "cloudCoverage", "cloudBase", "cloudTop", "cloudScattering", "dayOfYear", "sunRotation" }

--- Plain copy of the live environment's atmosphere fields + name.
local function readEnv()
	local ok, t = pcall(function()
		local e = api.gui.rendering.getEnvironment()
		local out = { name = e.name, isToolEnvironment = e.isToolEnvironment }
		for _, k in ipairs(ATMO_KEYS) do out[k] = e.atmosphere[k] end
		return out
	end)
	return ok and t or { err = tostring(t) }
end

local function envText(t)
	if t.err ~= nil then return "env ERR " .. t.err end
	local parts = { "name=" .. tostring(t.name), "tool=" .. tostring(t.isToolEnvironment) }
	for _, k in ipairs(ATMO_KEYS) do parts[#parts + 1] = k .. "=" .. fmt(t[k]) end
	return table.concat(parts, " ")
end

local function readEnvResName()
	local ok, v = pcall(function() return api.gui.game.getEnvironment() end)
	return ok and tostring(v) or ("ERR " .. tostring(v))
end

local function timeText()
	local st = readGameTimeState()
	if st.err ~= nil then return "time=" .. clockText(readTimeOfDay()) .. " state ERR " .. st.err end
	return string.format("time=%s (%s s) mode=%s target=%s weatherMode=%s", clockText(readTimeOfDay()),
		fmt(readTimeOfDay()), tostring(st.timeOfDayMode), fmt(st.timeOfDayTarget), tostring(st.weatherMode))
end

local function weatherText()
	local st = readGameTimeState()
	return string.format("weatherMode=%s cloudTarget=%s worldCloud=%s %s", tostring(st.weatherMode),
		fmt(st.cloudCoverageTarget), fmt(readWorldCloud()), envText(readEnv()))
end

local function visText(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		local ok1, v1 = pcall(function() return api.gui.byId.isVisible(id) end)
		local ok2, v2 = pcall(function() return api.gui.byId.isVisibleRecursive(id) end)
		parts[#parts + 1] = string.format("%s=%s/%s", id, ok1 and tostring(v1) or "ERR", ok2 and tostring(v2) or "ERR")
	end
	return "visible(own/recursive) " .. table.concat(parts, " ")
end

local function send(tag, what, cmd)
	return try(tag, what, function() api.cmd.sendCommand(cmd) end)
end

---------------------------------------------------------------------------
-- T1 screenshots

local function shot(scale, why)
	local s = nil
	pcall(function() s = api.gui.camera.getSize() end)
	local ok = try("T1", "takeScreenshot", function() api.gui.camera.takeScreenshot(scale) end)
	log("T1", string.format("screenshot scale=%d %s at us=%d os.time=%d viewport=%sx%s ok=%s (expect a stdout line "
		.. "'Screenshot: wrote ...'; the PNG should be %sx%s x scale; sips -g pixelWidth -g pixelHeight <file>)",
		scale, why or "", nowUs(), os.time(), s and fmt(s.x) or "?", s and fmt(s.y) or "?", tostring(ok),
		s and fmt(s.x) or "?", s and fmt(s.y) or "?"))
end

local function burst()
	log("T1", "burst: scales 1, 2, 4 at +0 / +3 / +6 s (click 'scale 1' once before: the first shot of a session is dropped)")
	shot(1, "burst 1/3")
	later(3000000, "T1 burst", function() shot(2, "burst 2/3") end)
	later(6000000, "T1 burst", function() shot(4, "burst 3/3") end)
end

---------------------------------------------------------------------------
-- T2 hide UI

local T2_IDS = { "react.game-ui-root", "menu.gamebar", "menu.gamebar.bottom", "cameraManagerWindow" }

local T2_VARIANTS = {
	a = {
		label = "setVisibilityByClass(react.game-ui-root, false)",
		hide = function() api.gui.byId.setVisibilityByClass("react.game-ui-root", false) end,
		show = function() api.gui.byId.setVisibilityByClass("react.game-ui-root", nil) end,
	},
	b = {
		label = "setVisibilityByClass(menu.gamebar + menu.gamebar.bottom, false, idOnly)",
		hide = function()
			api.gui.byId.setVisibilityByClass("menu.gamebar", false, true)
			api.gui.byId.setVisibilityByClass("menu.gamebar.bottom", false, true)
		end,
		show = function()
			api.gui.byId.setVisibilityByClass("menu.gamebar", nil, true)
			api.gui.byId.setVisibilityByClass("menu.gamebar.bottom", nil, true)
		end,
	},
	c = {
		label = "toggleFreeCamera()",
		hide = function() api.gui.camera.toggleFreeCamera() end,
		show = function() api.gui.camera.toggleFreeCamera() end,
	},
	d = {
		label = "setVisible(react.game-ui-root, false)",
		hide = function() api.gui.byId.setVisible("react.game-ui-root", false) end,
		show = function() api.gui.byId.setVisible("react.game-ui-root", true) end,
	},
}

local function t2Restore(why)
	local r = R.t2
	if r == nil then return end
	R.t2 = nil
	cancel("T2")
	local v = T2_VARIANTS[r.variant]
	local ok = try("T2", "restore " .. r.variant, v.show)
	log("T2", string.format("%s restored (%s) after %.1f s ok=%s %s", r.variant, why, (nowUs() - r.at) / 1e6,
		tostring(ok), visText(T2_IDS)))
	if r.variant == "c" then
		local okM, m = pcall(function() return api.gui.camera.isFreeCameraMouseAttached() end)
		log("T2", "c freeMouseAttached=" .. (okM and tostring(m) or "ERR"))
		-- the base free-cam tool leaves with leaveFollowCameraCockpit (free_cam_options.tl:44-46): fall back to it
		-- when the game bar is still hidden 1 s after the second toggle
		later(1000000, "T2c check", function()
			local okV, vis = pcall(function() return api.gui.byId.isVisibleRecursive("menu.gamebar") end)
			log("T2", "c +1 s " .. visText(T2_IDS))
			if okV and vis == false then
				local okL = try("T2", "leaveFollowCameraCockpit", function() api.gui.camera.leaveFollowCameraCockpit() end)
				log("T2", "c fallback leaveFollowCameraCockpit ok=" .. tostring(okL))
				later(500000, "T2c check2", function() log("T2", "c after fallback " .. visText(T2_IDS)) end)
			end
		end)
	end
end

local function t2Hide(variant, keepUs, after)
	if R.t2 ~= nil then t2Restore("next variant") end
	local v = T2_VARIANTS[variant]
	log("T2", variant .. " before " .. visText(T2_IDS))
	local ok = try("T2", "hide " .. variant, v.hide)
	R.t2 = { variant = variant, at = nowUs() }
	log("T2", string.format("%s %s ok=%s, auto-restore in %.1f s (if the UI stays hidden: Esc)", variant, v.label,
		tostring(ok), (keepUs or HIDE_US) / 1e6))
	later(0, "T2 frame", function() log("T2", variant .. " +1 frame " .. visText(T2_IDS)) end)
	later(1000000, "T2 tick", function() log("T2", variant .. " +1 s onStep still runs while hidden " .. visText(T2_IDS)) end)
	if after ~= nil then after() end
	later(keepUs or HIDE_US, "T2 restore", function() t2Restore("timer") end)
end

--- T1 + T2a: the clean shot a photo mode needs (UI hidden, shot, UI back).
local function cleanShot()
	t2Hide("a", 3500000, function()
		later(1000000, "T2 shot", function() shot(2, "clean (UI hidden by T2a)") end)
	end)
end

---------------------------------------------------------------------------
-- T3 grid overlay window

local function transparentStyle(w, h)
	local st = api.gui.StyleSheet.new()
	st.backgroundColor1 = api.type.Vec4f.new(0, 0, 0, 0)
	st.borderColor = api.type.Vec4f.new(0, 0, 0, 0)
	if w ~= nil then st.size = api.type.Vec2f.new(w, h) end
	return st
end

local function solid(w, h)
	local st = api.gui.StyleSheet.new()
	st.backgroundColor1 = api.type.Vec4f.new(1, 1, 1, 0.55)
	st.size = api.type.Vec2f.new(w, h)
	return st
end

--- One full-size layer whose content sits at left/top (better_minimap layerAt: size + padding, not h/v placement).
local function layerAt(key, left, top, w, h, pw, ph)
	local st = api.gui.StyleSheet.new()
	st.size = api.type.Vec2f.new(pw, ph)
	st.padding = api.type.Vec4f.new(top, math.max(0, pw - left - w), math.max(0, ph - top - h), left)
	return builtin.FloatingLayoutChild{
		localKey = key,
		h = -1,
		v = -1,
		item = builtin.Component{
			meta = { styleSheet = st },
			mouseTransparent = true,
			layout = builtin.BoxLayout{
				orientation = builtin.type.Orientation.Vertical,
				children = { builtin.Component{ meta = { styleSheet = solid(w, h) }, mouseTransparent = true } },
			},
		},
	}
end

local GridContent = react.RegisterRecipe("SqpqGridContent", function(p)
	pcall(function() react.setMouseTransparent(true) end)
	local selfRef = react.useSelfRef()
	local measured = react.useRef(false)
	react.onStep(function()
		if measured:get() then return end
		local ok, err = pcall(function()
			local node = selfRef:get()
			if node == nil then return end
			local p0 = node:getPosition(0, 0)
			local p1 = node:getPosition(1, 1)
			if p1.x - p0.x <= 0 then return end
			measured:set(true)
			M.gridMeasured(p0.x, p0.y, p1.x, p1.y)
		end)
		if not ok then
			measured:set(true)
			log("T3", "measure ERROR " .. tostring(err))
		end
	end)
	local w, h = p.w, p.h
	local x1, x2 = math.floor(w / 3), math.floor(2 * w / 3)
	local y1, y2 = math.floor(h / 3), math.floor(2 * h / 3)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.Component{
				meta = {
					styleSheet = transparentStyle(w, h),
					onMouseOver = function(hovered)
						if hovered then common.log("T3 grid content got mouse-over (NOT mouse-transparent)") end
					end,
				},
				mouseTransparent = true,
				layout = builtin.FloatingLayout{
					children = {
						layerAt("v1", x1, 0, LINE_PX, h, w, h),
						layerAt("v2", x2, 0, LINE_PX, h, w, h),
						layerAt("h1", 0, y1, w, LINE_PX, w, h),
						layerAt("h2", 0, y2, w, LINE_PX, w, h),
					},
				},
			},
		},
	}
end)

local GridWindow = react.RegisterWrapperRecipe("SqpqGridWindow", builtin.Window, function(params)
	pcall(function() react.setMouseTransparent(true) end)
	return builtin.Window{
		id = "sqpq.grid",
		title = "",
		compact = true,
		movable = false,
		closable = true,
		pinnable = false,
		initialX = params.x or 0,
		initialY = params.y or 0,
		meta = { styleSheet = transparentStyle() },
		onClose = params.onClose,
		content = GridContent{ w = params.w, h = params.h },
	}
end)

local TestsWindow -- forward (the grid brings it back to the front)

local function windowApi() return game_react_globals.getDefaultWindowApi() end

local function gridClose(why)
	local r = R.t3
	if r == nil then return end
	R.t3 = nil
	cancel("T3")
	try("T3", "close", function() windowApi().removeAllWindows(GridWindow) end)
	log("T3", "grid closed (" .. why .. ")")
end

local function gridOpen(w, h, x, y, why)
	local wa = windowApi()
	if wa == nil then
		log("T3", "no window container")
		return
	end
	R.t3 = { w = w, h = h, x = x, y = y, refits = R.t3 and R.t3.refits or 0 }
	wa.addSingletonWindow(GridWindow, { w = w, h = h, x = x, y = y, onClose = function() gridClose("close button") end })
	if TestsWindow ~= nil then pcall(function() wa.moveSingletonWindowToFront(TestsWindow) end) end
	log("T3", string.format("grid open (%s) content=%sx%s initial=%s,%s; auto-close in %d s", why, fmt(w), fmt(h),
		fmt(x), fmt(y), math.floor(GRID_AUTO_CLOSE_US / 1e6)))
	cancel("T3")
	later(GRID_AUTO_CLOSE_US, "T3 auto", function() gridClose("timer") end)
end

local function gridToggle()
	if R.t3 ~= nil then
		gridClose("click")
		return
	end
	local ok, s = pcall(function() return api.gui.camera.getSize() end)
	if not ok or s == nil then
		log("T3", "camera.getSize ERROR " .. tostring(s))
		return
	end
	log("T3", string.format("camera.getSize=%sx%s (viewport px)", fmt(s.x), fmt(s.y)))
	gridOpen(s.x, s.y, 0, 0, "first, size = viewport px")
end

--- Called from the grid content's onStep: where the content landed, in screen fractions (better_minimap: 0..1).
--- One refit: content size scaled so it covers the screen, initial position moved by the frame offset.
function M.gridMeasured(x0, y0, x1, y1)
	local r = R.t3
	if r == nil then return end
	local covW, covH = x1 - x0, y1 - y0
	log("T3", string.format("grid content at screen fractions x %.4f..%.4f y %.4f..%.4f (covers %.3f x %.3f)",
		x0, x1, y0, y1, covW, covH))
	if r.refits >= 1 then
		log("T3", "after refit: lines at 1/3 and 2/3 of the screen? clicks and drags reach the map? (a 'mouse-over' line = no)")
		return
	end
	if math.abs(covW - 1) < 0.01 and math.abs(covH - 1) < 0.01 and math.abs(x0) < 0.005 and math.abs(y0) < 0.005 then
		log("T3", "grid fits the screen")
		return
	end
	local w = math.floor(r.w / covW + 0.5)
	local h = math.floor(r.h / covH + 0.5)
	local nx, ny = (r.x or 0) - x0, (r.y or 0) - y0
	log("T3", string.format("refit: screen fraction per requested px %.3f x %.3f -> content %dx%d, initial %.4f,%.4f "
		.. "(assumes initialX/Y in screen fractions, findings/gui.md)", covW, covH, w, h, nx, ny))
	R.t3.refits = 1
	-- labels without the "T3" prefix: a close callback (gridClose -> cancel("T3")) must not drop the reopen
	later(0, "grid refit", function()
		try("T3", "refit close", function() windowApi().removeAllWindows(GridWindow) end)
		later(100000, "grid refit open", function()
			gridOpen(w, h, nx, ny, "refit")
			if R.t3 ~= nil then R.t3.refits = 1 end
		end)
	end)
end

---------------------------------------------------------------------------
-- T4 time of day

local function t4Log(why)
	log("T4", why .. " " .. timeText())
end

local function t4Set(sec, label)
	if R.t4 == nil then
		local st = readGameTimeState()
		R.t4 = { time = readTimeOfDay(), mode = st.timeOfDayMode }
		log("T4", "saved for restore: time=" .. fmt(R.t4.time) .. " mode=" .. tostring(R.t4.mode))
	end
	t4Log(label .. " before")
	send("T4", "SetMode Constant", api.cmd.makeScriptingSendEventCmd("", "GameTime", "SetMode", { mode = "Constant" }))
	send("T4", "SetTimeOfDay", api.cmd.makeGameSetTimeOfDayCmd(sec))
	log("T4", string.format("%s sent time=%s (%d s) + GameTime SetMode Constant", label, clockText(sec), sec))
	cancel("T4")
	later(0, "T4 frame", function() t4Log(label .. " +1 frame") end)
	later(5000000, "T4 5s", function() t4Log(label .. " +5 s") end)
end

local function t4Restore(why)
	local r = R.t4
	if r == nil then
		log("T4", "restore: nothing to restore (" .. why .. ")")
		return
	end
	R.t4 = nil
	cancel("T4")
	if type(r.time) == "number" then send("T4", "SetTimeOfDay", api.cmd.makeGameSetTimeOfDayCmd(math.floor(r.time + 0.5))) end
	if type(r.mode) == "string" then
		send("T4", "SetMode", api.cmd.makeScriptingSendEventCmd("", "GameTime", "SetMode", { mode = r.mode }))
		-- as the base slider: the Dynamic cycle holds the restored time for a while instead of jumping at once
		send("T4", "OnManualGameTimeChanged",
			api.cmd.makeScriptingSendEventCmd("", "GameTime", "OnManualGameTimeChanged", math.floor(r.time + 0.5)))
	end
	log("T4", string.format("restored (%s) time=%s mode=%s", why, clockText(r.time), tostring(r.mode)))
	later(0, "T4 frame", function() t4Log("restore +1 frame") end)
	later(5000000, "T4 5s", function() t4Log("restore +5 s") end)
end

---------------------------------------------------------------------------
-- T5 pause

local function speedText()
	local s = readSpeed()
	if s.err ~= nil then return "speed ERR " .. s.err end
	return string.format("speedup=%s millisPerDay=%s", fmt(s.speedup), fmt(s.millisPerDay))
end

local function t5Restore(why)
	local r = R.t5
	if r == nil then return end
	R.t5 = nil
	if type(r.speedup) == "number" and r.speedup > 0 then
		send("T5", "SetSpeed", api.cmd.makeGameSetSpeedCmd(r.speedup))
	end
	log("T5", string.format("unfreeze (%s) back to speedup=%s", why, fmt(r.speedup)))
	later(0, "T5 frame", function() log("T5", "unfreeze +1 frame " .. speedText()) end)
	later(2000000, "T5 2s", function() log("T5", "unfreeze +2 s " .. speedText()) end)
end

local function t5Toggle()
	if R.t5 ~= nil then
		t5Restore("click")
		return
	end
	local s = readSpeed()
	R.t5 = { speedup = s.speedup }
	log("T5", "freeze before " .. speedText())
	send("T5", "SetSpeed 0", api.cmd.makeGameSetSpeedCmd(0))
	later(0, "T5 frame", function() log("T5", "freeze +1 frame " .. speedText()) end)
	later(2000000, "T5 2s", function() log("T5", "freeze +2 s " .. speedText() .. " (game bar shows paused?)") end)
end

---------------------------------------------------------------------------
-- T6 environment live edits

local function t6Save()
	if R.t6 ~= nil then return end
	local st = readGameTimeState()
	R.t6 = { env = readEnv(), weatherMode = st.weatherMode, worldCloud = readWorldCloud() }
	log("T6", "saved for restore: weatherMode=" .. tostring(R.t6.weatherMode) .. " worldCloud="
		.. fmt(R.t6.worldCloud) .. " " .. envText(R.t6.env))
end

local function t6Follow(label)
	cancel("T6")
	later(0, "T6 frame", function() log("T6", label .. " +1 frame " .. weatherText()) end)
	later(3000000, "T6 3s", function() log("T6", label .. " +3 s " .. weatherText()) end)
end

--- fn(e) edits the live Environment (rendering.getEnvironment copy), which is set back.
local function t6Edit(label, fn)
	t6Save()
	log("T6", label .. " before " .. weatherText())
	local ok = try("T6", label, function()
		local e = api.gui.rendering.getEnvironment()
		fn(e)
		api.gui.rendering.setEnvironment(e)
	end)
	log("T6", label .. " set ok=" .. tostring(ok) .. " immediately " .. envText(readEnv()))
	t6Follow(label)
end

local function t6Cloud(v)
	t6Edit("cloudCoverage=" .. fmt(v), function(e) e.atmosphere.cloudCoverage = v end)
end

local function t6CloudCmd(v)
	t6Save()
	log("T6", "cloud via makeGameSetCloudCoverageCmd(" .. fmt(v) .. ") before " .. weatherText())
	send("T6", "SetCloudCoverage", api.cmd.makeGameSetCloudCoverageCmd(v))
	t6Follow("cloud cmd " .. fmt(v))
end

local function t6Day(d)
	t6Edit("dayOfYear=" .. fmt(d), function(e) e.atmosphere.dayOfYear = d end)
end

local function t6Sun(delta, label)
	t6Edit("sunRotation " .. label, function(e) e.atmosphere.sunRotation = (e.atmosphere.sunRotation or 0) + delta end)
end

local function t6WeatherMode(mode)
	t6Save()
	send("T6", "CloudCoverage SetMode", api.cmd.makeScriptingSendEventCmd("", "CloudCoverage", "SetMode", { weatherMode = mode }))
	log("T6", "sent CloudCoverage SetMode weatherMode=" .. mode)
	t6Follow("weather " .. mode)
end

local function t6Restore(why)
	local r = R.t6
	if r == nil then
		if why == "click" then log("T6", "restore: nothing to restore") end
		return
	end
	R.t6 = nil
	local ok = try("T6", "restore env", function()
		local e = api.gui.rendering.getEnvironment()
		for _, k in ipairs(ATMO_KEYS) do
			if type(r.env[k]) == "number" then e.atmosphere[k] = r.env[k] end
		end
		api.gui.rendering.setEnvironment(e)
	end)
	if type(r.worldCloud) == "number" then
		send("T6", "SetCloudCoverage", api.cmd.makeGameSetCloudCoverageCmd(r.worldCloud))
	end
	if type(r.weatherMode) == "string" then
		send("T6", "CloudCoverage SetMode", api.cmd.makeScriptingSendEventCmd("", "CloudCoverage", "SetMode",
			{ weatherMode = r.weatherMode }))
	end
	log("T6", string.format("restored (%s) ok=%s weatherMode=%s worldCloud=%s", why, tostring(ok),
		tostring(r.weatherMode), fmt(r.worldCloud)))
	t6Follow("restore")
end

---------------------------------------------------------------------------
-- T7 environment resources

local function envRep() return api.res.environmentRep end

local function t7List()
	log("T7", "current resName=" .. readEnvResName() .. " live " .. envText(readEnv()))
	for _, inv in ipairs({ false, true }) do
		local ok, all = pcall(function() return envRep().getAll(inv) end)
		if not ok then
			log("T7", "getAll(" .. tostring(inv) .. ") ERROR " .. tostring(all))
		else
			local n = 0
			for id, resName in pairs(all) do
				n = n + 1
				local okG, info = pcall(function()
					local e = envRep().get(id)
					return string.format("name=%s isToolEnvironment=%s cloud=%s dayOfYear=%s", tostring(e.name),
						tostring(e.isToolEnvironment), fmt(e.atmosphere.cloudCoverage), fmt(e.atmosphere.dayOfYear))
				end)
				common.log(string.format("T7 env getAll(%s) id=%s resName=%s %s", tostring(inv), tostring(id),
					tostring(resName), okG and info or ("get ERR " .. tostring(info))))
			end
			log("T7", string.format("getAll(%s): %d environments (lines above)", tostring(inv), n))
		end
	end
end

--- Tries the ResName forms of our env file, then any getAll(true) name containing "sqpq".
local function t7Find()
	local cands = {
		common.MOD_ID .. "::/" .. ENV_FILE,
		common.MOD_ID .. "::" .. ENV_FILE,
		"::/" .. ENV_FILE,
		"/" .. ENV_FILE,
		ENV_FILE,
		common.MOD_ID .. "::/" .. ENV_FILE .. ".lua",
		"sqpq_test.env",
	}
	local okA, all = pcall(function() return envRep().getAll(true) end)
	if okA and all ~= nil then
		for _, resName in pairs(all) do
			if string.find(string.lower(tostring(resName)), "sqpq", 1, true) then cands[#cands + 1] = tostring(resName) end
		end
	end
	for _, c in ipairs(cands) do
		local ok, id = pcall(function() return envRep().find(c) end)
		common.log(string.format("T7 find(%s) -> %s", c, ok and tostring(id) or ("ERR " .. tostring(id))))
		if ok and type(id) == "number" and id >= 0 then return c, id end
	end
	return nil, nil
end

local function t7Restore(why)
	local r = R.t7
	if r == nil then
		if why == "click" then log("T7", "switch back: nothing to restore") end
		return
	end
	R.t7 = nil
	cancel("T7")
	local ok = try("T7", "switch back", function()
		local id = envRep().find(r.resName)
		if id ~= nil and id >= 0 then
			api.gui.rendering.setEnvironment(envRep().get(id))
		elseif r.envObj ~= nil then
			api.gui.rendering.setEnvironment(r.envObj)
		end
		-- the resource's defaults, then the live atmosphere values from before the switch
		local e = api.gui.rendering.getEnvironment()
		for _, k in ipairs(ATMO_KEYS) do
			if type(r.env[k]) == "number" then e.atmosphere[k] = r.env[k] end
		end
		api.gui.rendering.setEnvironment(e)
		if r.persisted then api.gui.game.setEnvironment(r.resName) end
	end)
	log("T7", string.format("switched back (%s) ok=%s to resName=%s; now resName=%s %s", why, tostring(ok),
		tostring(r.resName), readEnvResName(), envText(readEnv())))
end

local function t7Switch(persist)
	if R.t7 ~= nil then t7Restore("re-switch") end
	local name, id = t7Find()
	if name == nil then
		log("T7", "SQPQ test env not found under any candidate ResName (find lines above); run 'list' to see names")
		return
	end
	local envObj = nil
	pcall(function() envObj = api.gui.rendering.getEnvironment() end)
	R.t7 = { resName = api.gui.game.getEnvironment(), env = readEnv(), envObj = envObj, persisted = persist }
	log("T7", string.format("matched ResName=%s id=%s; before resName=%s %s", name, tostring(id),
		tostring(R.t7.resName), envText(R.t7.env)))
	local ok = try("T7", "switch", function()
		api.gui.rendering.setEnvironment(envRep().get(id))
		if persist then api.gui.game.setEnvironment(name) end
	end)
	log("T7", string.format("switched (%s) ok=%s now resName=%s %s; auto switch-back in %d s",
		persist and "rendering + game.setEnvironment" or "rendering only", tostring(ok), readEnvResName(),
		envText(readEnv()), math.floor(ENV_AUTO_BACK_US / 1e6)))
	later(3000000, "T7 3s", function() log("T7", "+3 s resName=" .. readEnvResName() .. " " .. envText(readEnv())) end)
	later(ENV_AUTO_BACK_US, "T7 auto", function() t7Restore("timer") end)
end

---------------------------------------------------------------------------
-- T8 camera tool

local function camToolEnabled()
	local ok, v = pcall(function() return api.util.getAppConfig().cameraTool end)
	return ok and tostring(v) or ("ERR " .. tostring(v))
end

local function camToolVisible()
	local ok, v = pcall(function() return api.gui.byId.isVisibleRecursive("cameraManagerWindow") end)
	return ok and v or ("ERR " .. tostring(v))
end

local function t8Open()
	log("T8", "open: AppConfig.cameraTool=" .. camToolEnabled() .. " visible before=" .. tostring(camToolVisible()))
	local ok = try("T8", "setVisible", function() api.gui.byId.setVisible("cameraManagerWindow", true) end)
	R.t8opened = true
	log("T8", "setVisible(cameraManagerWindow, true) ok=" .. tostring(ok) .. " visible after=" .. tostring(camToolVisible()))
end

local function t8Close(why)
	if not R.t8opened then return end
	R.t8opened = nil
	try("T8", "setVisible false", function() api.gui.byId.setVisible("cameraManagerWindow", false) end)
	log("T8", "closed (" .. why .. ") visible=" .. tostring(camToolVisible()))
end

local function t8Poll(now)
	if R.t8next ~= nil and now < R.t8next then return end
	R.t8next = now + CAMTOOL_POLL_US
	local v = tostring(camToolVisible())
	if v ~= R.t8last then
		log("T8", string.format("cameraManagerWindow visible %s -> %s (AppConfig.cameraTool=%s, freeMouse=%s)",
			tostring(R.t8last), v, camToolEnabled(),
			tostring(select(2, pcall(function() return api.gui.camera.isFreeCameraMouseAttached() end)))))
		R.t8last = v
	end
end

---------------------------------------------------------------------------
-- T9 cutscene camera (runs F)

local T9_DIR = common.MOD_ID .. "::/mission/keyframes/sqpq_"
-- A is the campaign's own form (mission_story_cutscenes_only.tl:276 + cutscene.tl:40: ".lua", language folder on)
local T9_FORMS = {
	{ key = "A", ext = ".lua", lang = true, note = ".lua + language folder (campaign form)" },
	{ key = "B", ext = ".lua", lang = false, note = ".lua, no language folder" },
	{ key = "C", ext = "", lang = true, note = "no .lua + language folder" },
	{ key = "D", ext = "", lang = false, note = "no .lua, no language folder" },
}
local T9_POLL_US = 500000
local T9_START_GRACE_US = 3000000 -- not playing by then: the call did nothing
local T9_TIMEOUT_US = 20000000 -- still playing by then: try the stop candidates
local T9_CAMERA_BACK_US = 500000 -- after the end: compare the camera, then put it back
local T9_STOP_NAMES = { "stopCutscene", "skipCutscene", "abortCutscene", "cancelCutscene", "endCutscene", "stop", "skip" }
local t9FormIndex = 1

local function t9Playing()
	local ok, v = pcall(function() return api.gui.mission.isCutscenePlaying() end)
	return ok and v or ("ERR " .. tostring(v))
end

local function t9Elapsed()
	local ok, v = pcall(function() return api.gui.mission.getCutsceneElapsedTime() end)
	return ok and fmt(v) or ("ERR " .. tostring(v))
end

local function readCam()
	local ok, t = pcall(function()
		local d = api.gui.camera.getCameraData()
		local e = api.gui.camera.getEye()
		local c = api.gui.camera.getCenter()
		return { x = d.x, y = d.y, dist = d.z, angle = d.w, pitch = d.q, ex = e.x, ey = e.y, ez = e.z, cx = c.x,
			cy = c.y, cz = c.z }
	end)
	return ok and t or { err = tostring(t) }
end

local function camText(c)
	if c.err ~= nil then return "cam ERR " .. c.err end
	return string.format("camData=%.1f,%.1f dist=%.1f angle=%.3f pitch=%.3f eye=%.1f,%.1f,%.1f center=%.1f,%.1f,%.1f",
		c.x, c.y, c.dist, c.angle, c.pitch, c.ex, c.ey, c.ez, c.cx, c.cy, c.cz)
end

local function t9State()
	local ok, ui = pcall(function() return api.gui.byId.isVisibleRecursive("react.game-ui-root") end)
	return string.format("playing=%s elapsed=%s %s ui-root=%s", tostring(t9Playing()), t9Elapsed(), speedText(),
		ok and tostring(ui) or "ERR")
end

--- Every member of api.gui.mission (a stop / skip function would be the "stop" button's answer).
local function t9Members()
	local ok, text = pcall(function()
		local m = api.gui.mission
		local names = {}
		for k, v in pairs(m) do names[#names + 1] = tostring(k) .. ":" .. type(v) end
		table.sort(names)
		return type(m) .. " {" .. table.concat(names, " ") .. "}"
	end)
	log("T9", "api.gui.mission = " .. (ok and text or ("not iterable: " .. tostring(text))))
end

--- Camera handed to the keyframe file through _G (read there only if it runs in this Lua state).
local function t9Handoff(c)
	if c.err ~= nil then return "no camera: " .. c.err end
	local dx, dy, dz = c.cx - c.ex, c.cy - c.ey, c.cz - c.ez
	local atan2 = math.atan2 or math.atan
	local o = { x = c.ex, y = c.ey, z = c.ez, angle = atan2(dy, dx), pitch = atan2(dz, math.sqrt(dx * dx + dy * dy)) }
	local ok, err = pcall(function() rawset(_G, "SQPQ_T9", o) end)
	return string.format("SQPQ_T9 set=%s pos=%.1f,%.1f,%.1f angle=%.3f pitch=%.3f (camData angle=%.3f pitch=%.3f)%s",
		tostring(ok), o.x, o.y, o.z, o.angle, o.pitch, c.angle, c.pitch, ok and "" or (" " .. tostring(err)))
end

local t9Poll -- forward

local function t9Finish(why)
	local r = R.t9
	if r == nil then return end
	R.t9 = nil
	cancel("T9")
	log("T9", string.format("%s end (%s) after %.1f s, was playing=%s; %s; camera now %s", r.mode, why,
		(nowUs() - r.at) / 1e6, tostring(r.sawPlaying), t9State(), camText(readCam())))
	if r.toolsDisabled then
		try("T9", "disableToolActions false", function() api.gui.fireReactEvent("disableToolActions", false) end)
	end
	local s = readSpeed()
	if type(r.speedup) == "number" and s.speedup ~= r.speedup then
		send("T9", "SetSpeed", api.cmd.makeGameSetSpeedCmd(r.speedup))
		log("T9", string.format("game speed was changed: %s -> back to %s", fmt(s.speedup), fmt(r.speedup)))
	else
		log("T9", "game speed unchanged speedup=" .. fmt(s.speedup))
	end
	pcall(function() rawset(_G, "SQPQ_T9", nil) end)
	local cam = r.cam
	-- the camera may still be blending back when the cutscene ends: compare, then put it back a moment later
	later(T9_CAMERA_BACK_US, "T9 camera", function()
		local now = readCam()
		log("T9", "+0.5 s after end " .. camText(now))
		if cam.err == nil and now.err == nil then
			local moved = math.abs(now.ex - cam.ex) + math.abs(now.ey - cam.ey) + math.abs(now.ez - cam.ez)
			local ok = try("T9", "setCameraData", function()
				api.gui.camera.setCameraData(api.type.Vec5f.new(cam.x, cam.y, cam.dist, cam.angle, cam.pitch))
			end)
			log("T9", string.format("camera put back (eye had moved %.1f m from before) ok=%s", moved, tostring(ok)))
			later(0, "T9 camera frame", function() log("T9", "camera +1 frame after put-back " .. camText(readCam())) end)
		end
	end)
end

function t9Poll()
	local r = R.t9
	if r == nil then return end
	local playing = t9Playing()
	local age = nowUs() - r.at
	common.log(string.format("T9 %s +%.1f s %s eye=%s", r.mode, age / 1e6, t9State(), camText(readCam())))
	if playing == true then
		r.sawPlaying = true
	elseif r.sawPlaying then
		t9Finish("isCutscenePlaying went false")
		return
	elseif age >= T9_START_GRACE_US then
		log("T9", string.format("%s never playing after %.1f s: form %s (%s) did nothing visible to the API", r.mode,
			age / 1e6, r.form.key, r.form.note))
		t9Finish("never started")
		return
	end
	if age >= T9_TIMEOUT_US and not r.timedOut then
		r.timedOut = true
		log("T9", "still playing after " .. math.floor(T9_TIMEOUT_US / 1e6) .. " s: trying the stop candidates")
		M.t9Stop("timeout")
	end
	later(T9_POLL_US, "T9 poll", t9Poll)
end

local function t9Play(mode)
	if R.t9 ~= nil then
		log("T9", "a cutscene test is still running (" .. R.t9.mode .. "); wait for its end line or click stop")
		return
	end
	local form = T9_FORMS[t9FormIndex]
	local path = T9_DIR .. mode .. form.ext
	local map = nil
	if mode == "attach" then
		local okF, target, note = pcall(function()
			local f = api.gui.camera.getFollowEntity()
			local e = f ~= nil and f[1] or nil
			if e == nil or e < 0 then return nil, "no followed entity" end
			-- the campaign maps to a carriage of the train (mission_story_cutscenes_only.tl:85-97)
			local okC, cl = pcall(function() return api.engine.getComponent(e, api.type.ComponentType.CARRIAGE_LIST) end)
			if okC and cl ~= nil and cl.carriages ~= nil and cl.carriages[1] ~= nil then
				return cl.carriages[1], "carriage 1 of followed vehicle " .. tostring(e)
			end
			return e, "followed entity " .. tostring(e) .. " (no CARRIAGE_LIST)"
		end)
		if not okF or target == nil then
			log("T9", "attach: follow a vehicle first (select it, follow camera): " .. tostring(okF and note or target))
			return
		end
		map = { [1] = target }
		log("T9", "attach: entityToEntityMap { [1] = " .. tostring(target) .. " } (" .. tostring(note) .. ")")
	end
	local cam = readCam()
	local s = readSpeed()
	R.t9 = { mode = mode, form = form, at = nowUs(), cam = cam, speedup = s.speedup, sawPlaying = false }
	log("T9", string.format("%s before: %s %s", mode, t9State(), camText(cam)))
	log("T9", t9Handoff(cam))
	-- as the base cutscene task (cutscene.tl:37-38)
	try("T9", "clearToolStack", function() api.gui.fireReactEvent("clearToolStack", nil) end)
	R.t9.toolsDisabled = try("T9", "disableToolActions", function() api.gui.fireReactEvent("disableToolActions", true) end)
	local t0 = nowUs()
	local ok = try("T9", "playCutscene", function() api.gui.mission.playCutscene(path, form.lang, map) end)
	log("T9", string.format("%s playCutscene(%s, %s%s) form %s returned ok=%s ms=%.1f; immediately %s", mode, path,
		tostring(form.lang), map ~= nil and ", map" or "", form.key, tostring(ok), (nowUs() - t0) / 1000, t9State()))
	if not ok then
		t9Finish("call failed")
		return
	end
	later(0, "T9 frame", function()
		if R.t9 ~= nil then log("T9", mode .. " +1 frame " .. t9State() .. " " .. camText(readCam())) end
	end)
	later(T9_POLL_US, "T9 poll", t9Poll)
end

function M.t9Stop(why)
	t9Members()
	local called = {}
	for _, name in ipairs(T9_STOP_NAMES) do
		local okT, fn = pcall(function() return api.gui.mission[name] end)
		if okT and type(fn) == "function" then
			local ok, err = pcall(fn)
			called[#called + 1] = name .. "=" .. tostring(ok) .. (ok and "" or ("(" .. tostring(err) .. ")"))
		end
	end
	log("T9", string.format("stop (%s): %s; now %s", why,
		#called > 0 and ("called " .. table.concat(called, " ")) or "no stop/skip function in api.gui.mission",
		t9State()))
end

local function t9NextForm()
	t9FormIndex = t9FormIndex % #T9_FORMS + 1
	local f = T9_FORMS[t9FormIndex]
	log("T9", "path form now " .. f.key .. ": " .. f.note .. " -> " .. T9_DIR .. "<mode>" .. f.ext
		.. " resolveLanguageFolder=" .. tostring(f.lang))
end

--- The dialogue overlay loads keyframe files with ug_require in this GUI state (mission_react_util.tl:264-267):
--- does it run here, with api, and is the chunk cached (no second "chunk loaded" line)?
local function t9Require()
	local c = readCam()
	log("T9", "ug_require test: " .. t9Handoff(c))
	for _, sub in ipairs({ "", "en/" }) do
		local path = common.MOD_ID .. "::/mission/keyframes/" .. sub .. "sqpq_fov.lua"
		local ok, res = pcall(ug_require, path)
		local info = tostring(res)
		if ok and type(res) == "function" then
			local okD, d = pcall(res)
			if okD and type(d) == "table" and type(d.camera) == "table" and d.camera[1] ~= nil then
				local f = d.camera[1]
				info = string.format("function; data() -> %d camera frames, first pos=%.1f,%.1f,%.1f fovY=%s", #d.camera,
					f.position[1], f.position[2], f.position[3], fmt(f.fovY))
			else
				info = "function; data() " .. (okD and type(d) or ("ERROR " .. tostring(d)))
			end
		end
		log("T9", string.format("ug_require(%s) ok=%s -> %s", path, tostring(ok), ok and info or ("ERROR " .. info)))
	end
	pcall(function() rawset(_G, "SQPQ_T9", nil) end)
end

--- Plugin react events named like the cutscene task's GUI events (cutscene.tl:51-58); logged only while T9 runs.
M.EVENT_NAMES = { "cutscene", "play", "end", "deactivate" }

function M.onEvent(name, param)
	if R.t9 == nil then return end
	local p = param
	if type(param) == "table" then
		local parts = {}
		for k, v in pairs(param) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
		p = "{" .. table.concat(parts, " ") .. "}"
	end
	log("T9", string.format("react event %s param=%s while %s", tostring(name), tostring(p), t9State()))
end

---------------------------------------------------------------------------
-- T10 atmosphere extras: fields the Environment typedef doesn't list (type.d.tl:5326-5343)

local T10_FIELDS = { "fogScaleLow", "fogScaleHigh", "sunBloom", "sunBloomScale", "miePhaseG", "mieScatteringScale",
	"rayScatteringScale", "sunsetBoostScale" }
local T10_OTHER = { "light", "water", "shadows", "skyBox" }

local function t10Read()
	local out = {}
	local okE, e = pcall(function() return api.gui.rendering.getEnvironment() end)
	if not okE then return { err = tostring(e) } end
	for _, k in ipairs(T10_FIELDS) do
		local ok, v = pcall(function() return e.atmosphere[k] end)
		out[k] = ok and v or ("ERR " .. tostring(v))
	end
	return out
end

local function t10Text(t, fields)
	if t.err ~= nil then return "env ERR " .. t.err end
	local parts = {}
	for _, k in ipairs(fields or T10_FIELDS) do parts[#parts + 1] = k .. "=" .. fmt(t[k]) end
	return table.concat(parts, " ")
end

local function t10Probe()
	log("T10", "read " .. t10Text(t10Read()))
	local ok, text = pcall(function()
		local e = api.gui.rendering.getEnvironment()
		local parts = {}
		for _, k in ipairs(T10_OTHER) do
			local okK, v = pcall(function() return e[k] end)
			parts[#parts + 1] = k .. "=" .. (okK and type(v) or ("ERR " .. tostring(v)))
		end
		return table.concat(parts, " ")
	end)
	log("T10", "other Environment members: " .. (ok and text or ("ERROR " .. tostring(text))))
end

--- changes: { field = function(old) return new end }; one setEnvironment per click.
local function t10Set(label, changes)
	local before = t10Read()
	if before.err ~= nil then
		log("T10", label .. " env ERR " .. before.err)
		return
	end
	if R.t10 == nil then R.t10 = { orig = {} } end
	local fields = {}
	for k, _ in pairs(changes) do fields[#fields + 1] = k end
	table.sort(fields)
	log("T10", label .. " before " .. t10Text(before, fields))
	local results = {}
	local ok = try("T10", label, function()
		local e = api.gui.rendering.getEnvironment()
		for _, k in ipairs(fields) do
			local old = before[k]
			if type(old) == "number" then
				if R.t10.orig[k] == nil then R.t10.orig[k] = old end
				local okW, err = pcall(function() e.atmosphere[k] = changes[k](old) end)
				results[#results + 1] = k .. (okW and " written" or (" write ERR " .. tostring(err)))
			else
				results[#results + 1] = k .. " skipped (read " .. tostring(old) .. ")"
			end
		end
		api.gui.rendering.setEnvironment(e)
	end)
	log("T10", string.format("%s setEnvironment ok=%s %s; immediately %s", label, tostring(ok),
		table.concat(results, ", "), t10Text(t10Read(), fields)))
	cancel("T10")
	later(0, "T10 frame", function() log("T10", label .. " +1 frame " .. t10Text(t10Read(), fields)) end)
	later(3000000, "T10 3s", function()
		log("T10", label .. " +3 s " .. t10Text(t10Read(), fields) .. " (still the written values = it sticks)")
	end)
end

local function times(f) return function(old) return old * f end end
local function value(v) return function(_) return v end end

local function t10Restore(why)
	local r = R.t10
	if r == nil then
		if why == "click" then log("T10", "restore: nothing to restore") end
		return
	end
	R.t10 = nil
	cancel("T10")
	local fields = {}
	for k, _ in pairs(r.orig) do fields[#fields + 1] = k end
	table.sort(fields)
	local ok = try("T10", "restore", function()
		local e = api.gui.rendering.getEnvironment()
		for _, k in ipairs(fields) do
			local v = r.orig[k]
			pcall(function() e.atmosphere[k] = v end)
		end
		api.gui.rendering.setEnvironment(e)
	end)
	log("T10", string.format("restored (%s) ok=%s %s", why, tostring(ok), t10Text(t10Read(), fields)))
	later(3000000, "T10 3s", function() log("T10", "restore +3 s " .. t10Text(t10Read(), fields)) end)
end

---------------------------------------------------------------------------
-- T11 AppConfig dev keys (settings.lua, not in the AppConfig typedef). Crash history (findings/map-camera.md
-- "Graphics settings from a mod"): one key per setAppConfig, and only one changed key at a time, so every
-- restore is a single one-key call too.

local T11_KEYS = { "bloomQuality", "useLegacyHdr" }

local function t11Read(key)
	local ok, v = pcall(function() return api.util.getAppConfig()[key] end)
	return ok and v or ("ERR " .. tostring(v))
end

local function t11Text()
	local parts = {}
	for _, k in ipairs(T11_KEYS) do parts[#parts + 1] = k .. "=" .. tostring(t11Read(k)) end
	return table.concat(parts, " ")
end

local function t11Write(key, v, why)
	local t0 = nowUs()
	local ok = try("T11", "setAppConfig " .. key, function()
		local cfg = api.type.AppConfig.new(api.util.getAppConfig())
		cfg[key] = v
		api.util.setAppConfig(cfg, false)
	end)
	local ms = (nowUs() - t0) / 1000
	log("T11", string.format("%s %s=%s setAppConfig ok=%s ms=%.1f readback %s", why, key, tostring(v), tostring(ok),
		ms, t11Text()))
	later(0, "T11 frame", function() log("T11", why .. " +1 frame " .. t11Text()) end)
	later(1000000, "T11 1s", function() log("T11", why .. " +1 s " .. t11Text()) end)
	return ok
end

local function t11Set(key, v)
	local r = R.t11
	if r ~= nil and r.key ~= key then
		log("T11", "restore " .. r.key .. " first (one changed key at a time)")
		return
	end
	local cur = t11Read(key)
	if cur == nil or (type(cur) == "string" and string.sub(cur, 1, 3) == "ERR") then
		log("T11", key .. " read " .. tostring(cur) .. "; not writing (could not restore it)")
		return
	end
	if r == nil then
		R.t11 = { key = key, orig = cur }
		log("T11", string.format("saved for restore: %s=%s (all: %s)", key, tostring(cur), t11Text()))
	end
	t11Write(key, v, "set")
end

local function t11Restore(why)
	local r = R.t11
	if r == nil then
		if why == "click" then log("T11", "restore: nothing to restore " .. t11Text()) end
		return
	end
	R.t11 = nil
	cancel("T11")
	if t11Read(r.key) == r.orig then
		log("T11", string.format("restore (%s): %s already %s, no call", why, r.key, tostring(r.orig)))
		return
	end
	t11Write(r.key, r.orig, "restore(" .. why .. ")")
end

---------------------------------------------------------------------------
-- T12 shader override (opt-in DEV mod square_shader_override_probe)

local SHADER_MOD = "square_shader_override_probe"

local function t12Check()
	local ok, res = pcall(ug_require, SHADER_MOD .. "::/" .. SHADER_MOD .. "_presence.lua")
	local present = ok and type(res) == "table" and res.modId == SHADER_MOD
	local okD, dbg = pcall(function() return api.util.getAppConfig().debugMode end)
	log("T12", string.format("%s active=%s (presence: %s) AppConfig.debugMode=%s", SHADER_MOD, tostring(present),
		ok and type(res) or ("ERR " .. tostring(res)), okD and tostring(dbg) or "ERR"))
	if present then
		log("T12", "magenta tint since load = the mod's compose.fs replaced the base one at start. If not: press AltGr+R"
			.. " (debug mode: recompiles shaders), look for a strong magenta tint over the 3D view, report")
	else
		log("T12", "opt-in: enable the DEV mod 'DEV Shader Override Probe' in the mod list for this save and reload;"
			.. " this check only says whether it is active")
	end
	log("T12", "no api.res lookup exists for shader files (res.d.tl has no program/shader rep); judge by eye")
end

---------------------------------------------------------------------------
-- Restore everything (pause menu, unmount, "restore all" button)

function M.restoreAll(why)
	local any = R.t2 ~= nil or R.t3 ~= nil or R.t4 ~= nil or R.t5 ~= nil or R.t6 ~= nil or R.t7 ~= nil or R.t8opened
		or R.t9 ~= nil or R.t10 ~= nil or R.t11 ~= nil
	if not any then return end
	common.log("T* restore all (" .. why .. ")")
	for _, fn in ipairs({ t9Finish, t2Restore, gridClose, t7Restore, t10Restore, t6Restore, t4Restore, t5Restore, t8Close,
		t11Restore }) do
		local ok, err = pcall(fn, why)
		if not ok then common.log("T* restore ERROR " .. tostring(err)) end
	end
end

--- Called from the plugin's react.onStep (Main Thread).
function M.step()
	local now = nowUs()
	if #tasks > 0 then
		local due, keep = {}, {}
		for _, t in ipairs(tasks) do
			if now >= t.at then due[#due + 1] = t else keep[#keep + 1] = t end
		end
		tasks = keep
		for _, t in ipairs(due) do
			local ok, err = pcall(t.fn)
			if not ok then log(t.label, "task ERROR " .. tostring(err)) end
		end
	end
	t8Poll(now)
	if windowState ~= nil then
		local ok = pcall(function()
			if not windowState:hasExpired() and windowState:old() ~= version then windowState:set(version) end
		end)
		if not ok then windowState = nil end
	end
end

---------------------------------------------------------------------------
-- Window

local function text(s, class)
	return builtin.TextView{ meta = { class = class or "font-scale-body" }, text = s }
end

local function button(label, fn, tooltip)
	return builtin.Button{
		meta = { tooltip = tooltip },
		content = text(label),
		onClick = function()
			local ok, err = pcall(fn)
			if not ok then log("T?", label .. " ERROR " .. tostring(err)) end
		end,
	}
end

local function row(title, buttons)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = { text(title, "font-scale-annotation"), builtin.FlowLayout{ children = buttons } },
	}
end

local PI = math.pi

local TestsContent = react.RegisterRecipe("SqpqTestsContent", function()
	local st = react.useState(version)
	windowState = st
	local lines = {}
	for i = 1, STATUS_LINES do
		lines[i] = builtin.TextView{
			meta = { class = "font-scale-annotation", styleSheet = (function()
				local s = api.gui.StyleSheet.new()
				s.size = api.type.Vec2f.new(560, 18)
				return s
			end)() },
			text = status[i] or "",
		}
	end
	local children = {
		row("T1 screenshots (the first of a session is dropped: click scale 1 once first)", {
			button("scale 1", function() shot(1) end),
			button("scale 2", function() shot(2) end),
			button("scale 3", function() shot(3) end),
			button("scale 4", function() shot(4) end),
			button("burst 1,2,4", burst, "Scales 1, 2, 4 three seconds apart"),
			button("clean shot", cleanShot, "Hide UI (T2a), scale 2 after 1 s, UI back after 3.5 s"),
		}),
		row("T2 hide UI (each comes back after 5 s; Esc if not)", {
			button("b gamebar", function() t2Hide("b") end, "setVisibilityByClass on menu.gamebar and menu.gamebar.bottom"),
			button("a ui-root class", function() t2Hide("a") end, "setVisibilityByClass(react.game-ui-root, false)"),
			button("d ui-root setVisible", function() t2Hide("d") end, "setVisible(react.game-ui-root, false)"),
			button("c free camera", function() t2Hide("c") end, "api.gui.camera.toggleFreeCamera(), twice"),
		}),
		-- T3 removed 2026-10-13: opening GridWindow crashed the game ("Wrapper recipe must return child",
		-- session 2026-10-13_0339_sqpq); the grid was dropped from Photo Mode. Code kept for reference.
		row("T4 time of day (sets the cycle to Custom)", {
			button("golden hour 18:30", function() t4Set(18 * 3600 + 30 * 60, "golden") end),
			button("noon", function() t4Set(12 * 3600, "noon") end),
			button("night 23:00", function() t4Set(23 * 3600, "night") end),
			button("read", function() t4Log("read") end),
			button("restore", function() t4Restore("click") end),
		}),
		row("T5 pause", { button("freeze / unfreeze", t5Toggle) }),
		row("T6 environment live edits (weather mode as is, unless 'weather Constant')", {
			button("cloud 0", function() t6Cloud(0) end),
			button("cloud 0.3", function() t6Cloud(0.3) end),
			button("cloud 0.48", function() t6Cloud(0.48) end, "0.48: rain threshold"),
			button("cloud 0.48 cmd", function() t6CloudCmd(0.48) end, "makeGameSetCloudCoverageCmd instead of setEnvironment"),
			button("winter (15)", function() t6Day(15) end),
			button("summer (172)", function() t6Day(172) end),
			button("sun +pi/2", function() t6Sun(PI / 2, "+pi/2") end, "sunRotation + 1.5708 (if it is radians)"),
			button("sun +90", function() t6Sun(90, "+90") end, "sunRotation + 90 (if it is degrees)"),
			button("weather Constant", function() t6WeatherMode("Constant") end),
			button("read", function() log("T6", "read " .. weatherText()) end),
			button("restore", function() t6Restore("click") end),
		}),
		row("T7 environment resources (switches back by itself after 30 s)", {
			button("list", t7List),
			button("SQPQ test (render only)", function() t7Switch(false) end, "rendering.setEnvironment only"),
			button("SQPQ test (+ game)", function() t7Switch(true) end, "rendering.setEnvironment + game.setEnvironment (saved in the savegame)"),
			button("switch back", function() t7Restore("click") end),
		}),
		row("T8 camera tool (visibility changes are logged)", {
			button("open camera tool", t8Open),
			button("close", function() t8Close("click") end),
		}),
		row("T9 cutscene camera (follow a vehicle first for 'attach'; each ends by itself in 5-6 s)", {
			button("play FOV test", function() t9Play("fov") end, "fovY 1.0 -> 0.3 over 4 s at the current camera"),
			button("play roll test", function() t9Play("roll") end, "roll 0 -> 0.25 over 4 s"),
			button("play fade test", function() t9Play("fade") end, "fade in from black, fade out / in at 3 s"),
			button("play attach test", function() t9Play("attach") end,
				"Frames relative to the followed vehicle\n(entityToEntityMap { [1] = its first carriage })"),
			button("next path form", t9NextForm, "A .lua + language folder, B .lua, C no .lua + language folder,\nD no .lua"),
			button("ug_require file", t9Require, "Load the keyframe file as the dialogue overlay does (GUI state)"),
			button("api members", t9Members),
			button("stop", function() M.t9Stop("click") end, "Calls any stop / skip function api.gui.mission has"),
		}),
		row("T10 atmosphere extras (one setEnvironment per click; read-back now and +3 s)", {
			button("read fields", t10Probe),
			button("fog x3", function() t10Set("fog x3", { fogScaleLow = times(3), fogScaleHigh = times(3) }) end),
			button("sunBloom 50", function() t10Set("sunBloom 50", { sunBloom = value(50) }) end,
				"Base 350; lower = bigger sun haze (if it works like a Phong exponent)"),
			button("sunBloomScale x3", function() t10Set("sunBloomScale x3", { sunBloomScale = times(3) }) end),
			button("miePhaseG 0.9", function() t10Set("miePhaseG 0.9", { miePhaseG = value(0.9) }) end,
				"Base ~0.7; higher = tighter, brighter glow around the sun"),
			button("mieScattering x3", function() t10Set("mieScattering x3", { mieScatteringScale = times(3) }) end,
				"Denser haze"),
			button("restore", function() t10Restore("click") end),
		}),
		row("T11 AppConfig dev keys (one setAppConfig per click, one changed key at a time)", {
			button("bloom 0", function() t11Set("bloomQuality", 0) end),
			button("bloom 1", function() t11Set("bloomQuality", 1) end),
			button("bloom 2", function() t11Set("bloomQuality", 2) end),
			button("legacyHdr true", function() t11Set("useLegacyHdr", true) end),
			button("legacyHdr false", function() t11Set("useLegacyHdr", false) end),
			button("read", function() log("T11", "read " .. t11Text()) end),
			button("restore", function() t11Restore("click") end),
		}),
		row("T12 shader override (opt-in: DEV Shader Override Probe mod)", {
			button("check + instructions", t12Check),
		}),
		row("All", { button("restore all", function() M.restoreAll("click") end) }),
	}
	for i = 1, #lines do children[#children + 1] = lines[i] end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = children,
	}
end)

local function closeTests()
	windowState = nil
	local wa = windowApi()
	if wa ~= nil then wa.removeAllWindows(TestsWindow) end
end

TestsWindow = react.RegisterWrapperRecipe("SqpqTestsWindow", builtin.Window, function(params)
	return builtin.Window{
		id = "sqpq.tests",
		title = "DEV SQPQ tests (runs E, F)",
		closable = true,
		movable = true,
		onClose = params.onClose,
		content = TestsContent(),
	}
end)

function M.toggleWindow()
	if windowState ~= nil then
		local open = false
		pcall(function() open = not windowState:hasExpired() end)
		if open then
			closeTests()
			return
		end
	end
	local wa = windowApi()
	if wa == nil then
		common.log("T* no window container")
		return
	end
	wa.addSingletonWindow(TestsWindow, { onClose = closeTests })
	wa.moveSingletonWindowToFront(TestsWindow)
	log("T*", "tests window open; AppConfig.cameraTool=" .. camToolEnabled() .. " " .. timeText() .. " " .. speedText())
end

return M
