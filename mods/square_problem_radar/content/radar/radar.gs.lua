-- Problem Radar game script registration (discovered by extension, not referenced from mod.json).
-- src: .cache/game/mods/release/urbangames_campaign_mission_08/content/mission/rocket/rocket.gs.lua:1-13
-- fileName is relative to this file's folder, as in every base/official .gs.lua
-- (e.g. .cache/game/base/content/terrain/reforestation.gs.lua:4).
-- Game-script name for getEntityForGameScript: "square_problem_radar::/radar/radar.gs"
function data()
	return {
		updateScript = {
			fileName = "radar.script@update",
		},
		handleEventScript = {
			fileName = "radar.script@handleEvent",
		},
	}
end
