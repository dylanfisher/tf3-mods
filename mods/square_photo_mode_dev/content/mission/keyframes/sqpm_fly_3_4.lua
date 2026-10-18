local HEADING, TURN = 3, 2
-- Photo Mode round 15 / 16, DEV prototype (square_photo_mode gui/pm_cutscene.lua "cutscene aerial", C.FLY /
-- C.planFly; played only with this DEV mod active). One flight of FLY.keys keys whose key i is ATTACHED to its own
-- placeholder entity FLY.anchorBase + i - 1, FLY.height m straight above it (an offset that is the same in any
-- entity frame), looking FLY.pitch down along a heading that goes from HEADING to HEADING + TURN (in 45-degree
-- steps, +x = 0, counter-clockwise; the keys' `angle`, unwrapped) evenly over the keys (round 16: a flight can
-- turn away from the map edge, and the next one starts on this one's end heading). The GUI maps placeholder i to
-- a real entity one leg on from the last along the leg's heading (playCutscene's entityToEntityMap), so the
-- flight goes where the GUI chose although this file is static (the GUI has no io to write one). Every key's
-- speed is FLY.leg / FLY.legS (the GUI picks anchors about one leg apart). The yaw / pitch / roll locks keep the
-- look out of the anchor's own rotation. Files sqpm_fly_<h>_<TURN + 2>.lua (h 0..7, TURN -2..2) are identical but
-- for line 1, and keyframes/ and keyframes/en/ (the one resolveLanguageFolder picks) hold identical copies. Keep
-- FLY equal to pm_cutscene.lua C.FLY. No math library needed (plain arithmetic).

local FLY = { keys = 6, leg = 600, legS = 15, height = 250, pitch = -0.35, headings = 8, anchorBase = 9999900 }
local STEP = 0.78539816339745 -- 2 pi / FLY.headings

function data()
	local camera = {}
	for i = 0, FLY.keys - 1 do
		camera[#camera + 1] = {
			angle = (HEADING + TURN * i / (FLY.keys - 1)) * STEP,
			attachment = { entity = FLY.anchorBase + i, group = 0, lockPitch = true, lockRoll = true, lockYaw = true },
			fovY = 0.8,
			pitch = FLY.pitch,
			position = { 0, 0, FLY.height },
			roll = 0,
			speed = FLY.leg / FLY.legS,
			time = i * FLY.legS,
		}
	end
	if type(print) == "function" then
		pcall(print, "[PhotoMode] cutscene fly file: data() heading " .. tostring(HEADING) .. " turn " .. tostring(TURN)
			.. " angle " .. tostring(camera[1].angle) .. " -> " .. tostring(camera[#camera].angle) .. ", " .. #camera
			.. " keys attached to " .. FLY.anchorBase .. ".." .. (FLY.anchorBase + FLY.keys - 1) .. ", speed "
			.. tostring(FLY.leg / FLY.legS) .. " m/s")
	end
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
