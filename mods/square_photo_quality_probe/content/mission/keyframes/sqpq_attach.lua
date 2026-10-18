-- DEV probe keyframe file, runs F T9 (plans/square_photo_quality_probe/TESTING.md "Runs F"). DEV only, never upload.
-- Format of the campaign cutscenes (urbangames_campaign_mission_01 keyframes/en/*.lua, typedef
-- base/tealdef/mission/tasks/mission_dialogue_data.d.tl). Positions are absolute world coordinates, so this file
-- computes its frames when data() runs, from (1) the table SQPQ_T9 the probe sets in _G right before
-- playCutscene (only visible if this file runs in the GUI Lua state), (2) api.gui.camera if this state has it,
-- (3) a fixed spot above the map origin. Its log lines tell which one was used and whether the chunk is loaded
-- once (cached) or per play. The eight files are copies of one template differing only in MODE and COPY (the en/
-- copies are what resolveLanguageFolder = true should pick). Edit all eight together.
local MODE = "attach"
local COPY = "keyframes/" -- which copy ran: "keyframes/" or "keyframes/en/"

local calls = 0

local function say(msg)
	local line = "[SQPQ] T9 file(" .. MODE .. " in " .. COPY .. ") " .. msg
	local ok = false
	if type(log) == "table" and type(log.message) == "function" then ok = pcall(log.message, line) end
	if not ok then print(line) end
end

local function typeOf(fn)
	local ok, v = pcall(fn)
	return ok and type(v) or "ERR"
end

say(string.format("chunk loaded: api=%s api.gui=%s api.gui.camera=%s ug_require=%s _=%s log=%s SQPQ_T9=%s",
	typeOf(function() return api end), typeOf(function() return api.gui end),
	typeOf(function() return api.gui.camera end), typeOf(function() return ug_require end),
	typeOf(function() return _ end), typeOf(function() return log end),
	typeOf(function() return rawget(_G, "SQPQ_T9") end)))

local atan2 = math.atan2 or math.atan

local function origin()
	local okG, g = pcall(function() return rawget(_G, "SQPQ_T9") end)
	if okG and type(g) == "table" and type(g.x) == "number" then return g, "global SQPQ_T9" end
	local okC, c = pcall(function()
		local e = api.gui.camera.getEye()
		local t = api.gui.camera.getCenter()
		local dx, dy, dz = t.x - e.x, t.y - e.y, t.z - e.z
		return { x = e.x, y = e.y, z = e.z, angle = atan2(dy, dx), pitch = atan2(dz, math.sqrt(dx * dx + dy * dy)) }
	end)
	if okC and type(c) == "table" then return c, "api.gui.camera" end
	return { x = 0, y = 0, z = 400, angle = 0, pitch = -0.6 }, "fallback map origin (" .. tostring(c) .. ")"
end

--- One camera frame at the origin, nudged `ahead` metres along the view so consecutive frames never coincide.
local function frame(o, t, fovY, roll, ahead)
	return {
		angle = o.angle,
		fovY = fovY,
		pitch = o.pitch,
		position = { o.x + math.cos(o.angle) * ahead, o.y + math.sin(o.angle) * ahead, o.z },
		roll = roll,
		speed = 0.1,
		time = t,
	}
end

--- Frame attached to the mapped entity 1 (playCutscene entityToEntityMap { [1] = runtime entity }); position is
--- local to that entity, as in MISSION_01_CUTSCENE_OUTRO_B.lua.
local function attached(t, x, y, z, angle, pitch)
	return {
		angle = angle,
		attachment = { entity = 1, group = 0, lockPitch = false, lockRoll = false, lockYaw = false },
		fovY = 0.8,
		pitch = pitch,
		position = { x, y, z },
		roll = 0,
		speed = 1,
		time = t,
	}
end

function data()
	calls = calls + 1
	local o, src = origin()
	say(string.format("data() call %d origin=%s pos=%.1f,%.1f,%.1f angle=%.3f pitch=%.3f", calls, src, o.x, o.y, o.z,
		o.angle, o.pitch))
	local camera, fades = {}, {}
	if MODE == "fov" then
		-- fovY 1.0 -> 0.3 rad over 4 s, same spot
		camera = { frame(o, 0, 1.0, 0, 0), frame(o, 4, 0.3, 0, 0.4), frame(o, 5, 0.3, 0, 0.5) }
	elseif MODE == "roll" then
		-- roll 0 -> 0.25 rad over 4 s
		camera = { frame(o, 0, 0.8, 0, 0), frame(o, 4, 0.8, 0.25, 0.4), frame(o, 5, 0.8, 0.25, 0.5) }
	elseif MODE == "fade" then
		-- static 6 s; fade in from black at 0 (1 s), fade out / in around 3 s
		camera = { frame(o, 0, 0.8, 0, 0), frame(o, 6, 0.8, 0, 0.6) }
		fades = {
			{ duration = 0, fadeIn = 0, fadeOut = 1, time = 0 },
			{ duration = 0.5, fadeIn = 1, fadeOut = 1, time = 3 },
		}
	elseif MODE == "attach" then
		-- 30 m behind / 8 m above the mapped entity, sliding 15 m sideways over 5 s
		camera = { attached(0, -30, 0, 8, 0, -0.2), attached(5, -30, 15, 8, -0.4, -0.2) }
	end
	return {
		camera = camera,
		environmentParams = {},
		fades = fades,
		music = "",
		portraits = {},
		subtitles = {},
		voiceOvers = {},
	}
end

return data
