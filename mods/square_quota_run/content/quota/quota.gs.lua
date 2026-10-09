-- Quota Run game script registration (discovered by extension, not referenced from mod.json).
-- src: .cache/game/mods/release/urbangames_campaign_mission_08/content/mission/rocket/rocket.gs.lua:1-13
-- Game-script name for getEntityForGameScript: "square_quota_run::/quota/quota.gs"
function data()
	return {
		updateScript = {
			fileName = "quota.script@update",
		},
		handleEventScript = {
			fileName = "quota.script@handleEvent",
		},
	}
end
