-- Problem Radar notification type (Phase 5). The basename must match radar_notification.script.tl:
-- the notification system maps the type string "...radar_notification.script" to this ".res"
-- (.cache/game/base/content/game_mechanics/notifications/notification_util.tl:12-14).
-- Modelled on .cache/game/base/content/game_mechanics/notifications/types/stuck_vehicle.res.lua.
-- * label: the name in the game's notification log filter (notification_log.tl:227, via
--   notification_util.getNotificationType2Label), so players can mute "Problem Radar" there,
--   independently of every base type.
-- * guiType "Problem": only Critical kinds notify by default; the log filter groups types by it.
-- * initiallyIgnoredType = false: a new game tracks it (notification_util.getInitiallyIgnoredTypes).
--   Existing saves never had it in their ignored set, so it is tracked there too.
function data()
	return {
		type = "notification",
		data = {
			guiType = "Problem",
			label = _("Problem Radar"),
			initiallyIgnoredType = false,
		},
	}
end
