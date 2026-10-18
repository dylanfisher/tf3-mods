-- Photo Mode round 13, DEV prototype (gui/pm_cutscene.lua C.abort; only played with the DEV mod
-- square_photo_mode_dev active): a 0.1 s still frame played over an orbit cutscene whose attachment the engine
-- could not resolve ("Invalid entity for attachment" every frame), to end it early: the api has no call that
-- stops a cutscene. Whether a second playCutscene replaces a running one is what TESTING.md CB2 logs. Two copies
-- (keyframes/ and keyframes/en/, the one resolveLanguageFolder picks): keep them identical.

local function key(t)
	return { angle = 0, fovY = 0.8, pitch = -0.6, position = { 0, 0, 400 }, roll = 0, speed = 1, time = t }
end

function data()
	return {
		camera = { key(0), key(0.1) },
		environmentParams = {},
		fades = {},
		music = "",
		portraits = {},
		subtitles = {},
		voiceOvers = {},
	}
end

return data
