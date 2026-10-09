-- Quota Run notification type. The basename must match quota_notification.script.tl: the
-- notification system maps the type string "...quota_notification.script" to this ".res"
-- (.cache/game/base/content/game_mechanics/notifications/notification_util.tl:12-14).
-- Modelled on .cache/game/base/content/game_mechanics/company/company_notification_rank_up.res.lua.
function data()
	return {
		type = "notification",
		data = {
			guiType = "Info",
			label = _("Quota Run"),
			initiallyIgnoredType = false,
		},
	}
end
