-- Problem Radar notifications (GUI thread, read-only). Sent by radar.script.tl sendNotifications as
-- type "square_problem_radar::/radar/notify/radar_notification.script" with
-- params = ProblemRadarNotificationParams (one alert, or { more = n } for the summary toast).
-- The popup / log call "<type>@useDataState" (.cache/game/base/content/game_mechanics/notifications/gui/notification_popups.tl:62).
-- Contract: .cache/game/base/tealdef/game_mechanics/notifications/notifications.d.tl:4-49.
-- Modelled on .cache/game/base/content/game_mechanics/notifications/types/stuck_vehicle.script.tl.
-- No hooks: the texts
-- come from the params alone (radar_hud_model.notificationText, the same wording as the window rows).

local hud_model = ug_require "square_problem_radar::/radar/gui/radar_hud_model.tl" as ProblemRadarHudModel

-- Phase 7: line_unprofitable texts show money in the game's format (api/util.d.tl:58), as in the window.
hud_model.formatMoney = function(money : integer) : string
	return api.util.formatMoney(money)
end

--- The entity to select, or nil when it is gone or its id was reused (creation revision newer than
--- when the notification was sent; same test as entity_util.entityChanged0, entity_util.tl:35-39).
local function liveEntity(p : ProblemRadarNotificationParams) : integer
	local e = type(p.entity) == "number" and math.floor(p.entity) or nil
	if e == nil or e < 0 or not api.engine.entityExists(e) then return nil end
	if type(p.entityRev) == "number" then
		local rev = api.engine.getRevision(e)
		if rev ~= nil and rev.num ~= nil and rev.num[1] ~= nil and p.entityRev < rev.num[1] then return nil end
	end
	return e
end

local function position(p : ProblemRadarNotificationParams) : {number}
	local pos = p.pos
	if type(pos) ~= "table" or type(pos[1]) ~= "number" or type(pos[2]) ~= "number" or type(pos[3]) ~= "number" then
		return nil
	end
	return pos
end

--- Same action as a radar row click (radar_hud.script.tl focusRow): path problems focus the break
--- position, others the entity; the entity's window opens when the entity still exists.
--- src: notification_util.tl:425-445 (onClick: focusEntity + fireReactEvent "selectEntity" {entity, stack});
--- line_warning.script.tl:194 (focusPosition, distance 15). A gone entity: no error, no jump.
local function makeOnClick(p : ProblemRadarNotificationParams) : function(stack : boolean, dryRun? : boolean) : boolean
	return function(stack : boolean, dryRun? : boolean) : boolean
		local entity = liveEntity(p)
		local pos = position(p)
		if entity == nil and pos == nil then return false end
		if dryRun then return true end
		if pos ~= nil then
			api.gui.camera.focusPosition(api.type.Vec3f.new(pos[1], pos[2], pos[3]), 15)
		else
			api.gui.camera.focusEntity(entity)
		end
		if entity ~= nil then
			api.gui.fireReactEvent("selectEntity", { entity = entity, stack = stack })
		end
		return true
	end
end

local data : NotificationType<ProblemRadarNotificationParams> = {}

data.useDataState = function(p : ProblemRadarNotificationParams) : NotificationGuiData
	p = type(p) == "table" and p or {}
	local title, description, icon = hud_model.notificationText(p)
	local result : NotificationGuiData = {
		title = title,
		description = description,
		icon = icon,
	}
	if p.more == nil then
		local onClick = makeOnClick(p)
		result.onClick = onClick
		result.wouldClick = function() : boolean
			return onClick(false, true)
		end
	end
	return result
end

return data
