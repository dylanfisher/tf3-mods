-- Photo Mode round 13, DEV prototype (gui/pm_cutscene.lua C.playOrbit; only played with the DEV mod
-- square_photo_mode_dev active). A cutscene keyframe file in the campaign's format whose keys are ATTACHED to a
-- placeholder entity (ANCHOR): playCutscene's entityToEntityMap { [ANCHOR] = <live entity> } maps it to the
-- subject's carriage (or model entity) at each play, as the campaign maps its keyframe entities to live carriages
-- (urbangames_campaign_mission_01 mission_story.tl:86-97). The keys are computed here with plain math (the state
-- has no api; docs/findings/environment.md "Cutscenes from a mod"). One turn around the anchor at ORBIT.radius m,
-- ORBIT.height m above it, looking at it. Keep ANCHOR and ORBIT equal to pm_cutscene.lua C.ANCHOR / C.ORBIT. Two
-- copies (keyframes/ and keyframes/en/, the one resolveLanguageFolder picks): keep them identical.
--
-- Round 14 (session 2026-10-14_0633_session: attached and following, but "a strange glitchy movement like a
-- pulse"):
--   speed  every key's `speed` is the camera's speed there in m/s, which the engine moves the camera along its
--          spline with (binary: CameraAction `m_data->splineDist`; the Advanced Camera Tool's key columns "Time",
--          "Speed" and its "Auto Set Speed"). The campaign's keys hold exactly the chord to the next key over the
--          time to it (MISSION_01_CUTSCENE_OUTRO_A: 14.0347 m in 15 s, speed 0.935644; interior keys the mean of
--          their two segments, MISSION_07_CUTSCENE_BONUS_COMPLETE: 38.787 = (39.531 + 38.042) / 2). Round 13's
--          keys all said 1 m/s on segments of 31.4 m a second: the camera crawled at each key and rushed between
--          them, a pulse a second (the run's eye acceleration rms ~200 m/s2 against the 8 m/s2 of an even circle).
--          Now the speeds are the game's own "Auto Set Speed" (C.autoSpeed below): an even orbit.
--   locks  with lockYaw / lockPitch / lockRoll = false the offsets turned with the vehicle: the orbit's bearing
--          gained what the vehicle's heading turned (0633: bearing - heading +0.50 to +0.53 rad per 2 s, the
--          orbit's own 0.52, while the bearing alone went +1.11, +1.01, +0.45 ... +0.01). Locked now (inferred:
--          "Lock Yaw / Pitch / Roll" in the camera tool keep the camera's yaw / pitch / roll out of the entity's
--          turn), so the orbit's pace is its own and a bumpy road doesn't rock it. TESTING.md CC3 checks it.

local ANCHOR = 9999999
local ORBIT = { radius = 120, height = 50, seconds = 48, stepS = 1 }

local function say(msg)
	if type(print) == "function" then pcall(print, "[PhotoMode] cutscene orbit file: " .. msg) end
end

local function attach()
	-- round 17: lockYaw false (0842: with it true the offsets turned with a static anchor's yaw but the look kept
	-- world axes, past the anchor by its yaw; pm_lensdef.lua header)
	return { entity = ANCHOR, group = 0, lockPitch = true, lockRoll = true, lockYaw = false }
end

-- The camera tool's "Auto Set Speed" as the campaign's keys show it: a segment's speed is its chord over its time;
-- the first key takes the first segment's, the last key the last segment's, a key between two the mean of both; a
-- cut (two keys at one time) takes the segment on its side.
local function autoSpeed(keys)
	local n = #keys
	local seg = {}
	for i = 1, n - 1 do
		local a, b = keys[i], keys[i + 1]
		local dt = b.time - a.time
		if dt > 0 then
			local dx, dy, dz = b.position[1] - a.position[1], b.position[2] - a.position[2], b.position[3] - a.position[3]
			seg[i] = math.sqrt(dx * dx + dy * dy + dz * dz) / dt
		end
	end
	for i = 1, n do
		local l, r = seg[i - 1], seg[i]
		if l ~= nil and r ~= nil then
			keys[i].speed = (l + r) / 2
		else
			keys[i].speed = r or l or 1
		end
	end
	return keys
end

local function key(t, x, y, z, a, p)
	return { angle = a, attachment = attach(), fovY = 0.8, pitch = p, position = { x, y, z }, roll = 0, speed = 1,
		time = t }
end

local function orbitKeys()
	local ok, keys = pcall(function()
		local out = {}
		local n = math.floor(ORBIT.seconds / ORBIT.stepS + 0.5)
		local p = -math.atan(ORBIT.height / ORBIT.radius)
		for i = 0, n do
			local t = i * ORBIT.stepS
			local th = 2 * math.pi * t / ORBIT.seconds
			out[#out + 1] = key(t, ORBIT.radius * math.cos(th), ORBIT.radius * math.sin(th), ORBIT.height, th + math.pi, p)
		end
		return autoSpeed(out)
	end)
	if ok and type(keys) == "table" and #keys >= 2 then return keys, "math" end
	-- no math in this state: four fixed keys around the anchor (a square, looking in)
	local r, h, p = ORBIT.radius, ORBIT.height, -0.395
	return {
		key(0, r, 0, h, 3.14159, p), key(6, 0, r, h, -1.5708, p), key(12, -r, 0, h, 0, p), key(18, 0, -r, h, 1.5708, p),
		key(24, r, 0, h, 3.14159, p),
	}, "fixed (" .. tostring(keys) .. ")"
end

function data()
	local camera, how = orbitKeys()
	say(string.format("data() %d keys (%s), math=%s attached to entity %d, speed %.2f-%.2f m/s, locks yaw/pitch/roll %s",
		#camera, how, type(math), ANCHOR, camera[1].speed or 0, camera[#camera].speed or 0,
		tostring(camera[1].attachment.lockYaw)))
	return {
		camera = camera,
		environmentParams = {},
		fades = {},
		music = "",
		portraits = {},
		subtitles = {},
		voiceOvers = {},
	}
end

return data
