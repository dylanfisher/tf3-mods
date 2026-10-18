-- Photo Mode round 18: the cutscene bar. Wraps the base FreeCamOptions recipe (gui/main/free_cam_options.tl, mounted
-- in GameUIProxyRoot OUTSIDE the UI root a cutscene hides: gui/main/game.tl:893-901) with the official react
-- replacement mechanism: a "react-replacement-config" resource names a script function that gets the replacement
-- api (base gui/main/bootstrap_game.tl getReplacementConfigs / doReplacements; the campaign's
-- urbangames_campaign_mission_01 hud_replacement.res.lua wraps HudIconMasterGame the same way). The wrapper renders
-- the original unchanged (its Esc / back / F9 screenshot input actions included) plus Photo Mode's small bar while
-- one of its cutscenes plays (gui/pm_bar.script.lua).
function data()
	return {
		type = "react-replacement-config",
		data = {
			filePath = "square_photo_mode::/photo_mode/gui/pm_bar.script",
			doReplaceFn = "doReplaceFn",
			order = 40,
		}
	}
end
