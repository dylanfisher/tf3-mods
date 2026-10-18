-- Organic Towns notification type (2026-10-17, rev 3): "a satellite town was founded". The basename must match
-- ot_new_town.script.tl: the notification system maps the type string "...ot_new_town.script" to this ".res"
-- (.cache/game/base/content/game_mechanics/notifications/notification_util.tl:12-14). Modelled on the base
-- game_mechanics/notifications/types/industry_spawn.res.lua (guiType "Info", no sim script: the texts come from the
-- params) and mods/square_problem_radar/content/radar/notify/radar_notification.res.lua.
-- * label: the name in the game's notification log filter, so players can mute it there.
-- * initiallyIgnoredType = false: a new game tracks it.
function data()
	return {
		type = "notification",
		data = {
			guiType = "Info",
			label = _("Organic Towns: new towns"),
			initiallyIgnoredType = false,
		},
	}
end
