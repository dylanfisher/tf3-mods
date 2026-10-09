-- Quota Run HUD plugin registration. Modelled on
-- .cache/game/base/content/gui/game_bar/game_bar_display_transported_plugin/game_bar_display_transported.res.lua
-- Extension point "::MainModButtonAreaExtension" (.cache/game/base/content/gui/main/main_mod_button_area.tl:7),
-- looked up by react.getPlugins as resource type "react-plugin " .. id (.cache/game/base/content/gui/main/react.lua:92-117).
-- getPlugins reads filePath, order and condition (react.lua:109); "priority" is ignored, so use order.
-- Not "::ModEntryPointExtension": those plugins are mounted invisible (game.tl:574-586); see quota_hud.script.tl.
-- Fallback if nothing renders: plans/square_quota_run/GUI_FALLBACK.md
function data()
	return {
		type = "react-plugin ::MainModButtonAreaExtension",
		data = {
			filePath = "square_quota_run::/quota/gui/quota_hud.script@QuotaRunHudPlugin",
			order = 0,
		}
	}
end
