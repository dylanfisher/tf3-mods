-- Organic Towns notifications (2026-10-17, rev 3; GUI thread, read-only): a Works or district town the mod founded.
-- Sent by ot_driver Driver:noteNewTown as type "square_organic_towns::/organic_towns/notify/ot_new_town.script" with
-- params = ot_card.noteParams (town, parent, kind, the names at the founding, the new town's creation revision).
-- The popup / log call "<type>@useDataState" (.cache/game/base/content/game_mechanics/notifications/gui/
-- notification_popups.tl:62). Contract: .cache/game/base/tealdef/game_mechanics/notifications/notifications.d.tl:4-49.
-- Modelled on the base types/industry_spawn.script.tl and mods/square_problem_radar/.../radar_notification.script.tl.
-- The texts use the towns' current names while they exist (a player may rename them), else the sent ones. A click
-- focuses the new town and opens its window (notification_util.tl onClick: focusEntity + "selectEntity"), unless the
-- town is gone or its id was reused (creation revision newer than the sent one, entity_util.entityChanged0).

local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil

local record OtNoteParams
	town : integer
	parent : integer
	kind : string
	name : string
	parentName : string
	rev : number
end

local record OtNoteModule
	noteText : function(p : OtNoteParams, name : string, parentName : string) : string, string
end

local card = ug_require "square_organic_towns::/organic_towns/ot_card.lua" as OtNoteModule

local ICON_TOWN <const> = "::/gui/entity_window/icons/building_town.tga"
local ICON_WORKS <const> = "::/game_mechanics/notifications/gui/icons/building_industry_plus.tga"

--- The town to select, or nil when it is gone or its id was reused.
local function liveTown(p : OtNoteParams) : integer
	local e = type(p.town) == "number" and math.floor(p.town) or nil
	if e == nil or e < 0 or not api.engine.entityExists(e) then return nil end
	if type(p.rev) == "number" then
		local rev = api.engine.getRevision(e)
		if rev ~= nil and rev.num ~= nil and rev.num[1] ~= nil and p.rev < rev.num[1] then return nil end
	end
	return e
end

local function nameOf(e : integer) : string
	if e == nil or e < 0 or not api.engine.entityExists(e) then return nil end
	local c = api.engine.getComponent(e, api.type.ComponentType.NAME) as Engine.Component.Name
	return c and c.name or nil
end

local record NoteState
	name : string
	parentName : string
	live : boolean
end

local data : NotificationType<OtNoteParams> = {}

data.useDataState = function(p : OtNoteParams) : NotificationGuiData
	p = type(p) == "table" and p or {}
	local state = engine_react_util.useStepStateTimer(function() : NoteState
		local ok, st = pcall(function() : NoteState
			local live = liveTown(p)
			return { name = live and nameOf(live) or nil, parentName = nameOf(p.parent), live = live ~= nil }
		end)
		if ok and st then return st end
		return { live = false }
	end)
	local st : NoteState = state:old() or { live = false }
	local title, description = card.noteText(p, st.name, st.parentName)
	local function onClick(stack : boolean, dryRun? : boolean) : boolean
		local e = liveTown(p)
		if e == nil then return false end
		if dryRun then return true end
		api.gui.camera.focusEntity(e)
		api.gui.fireReactEvent("selectEntity", { entity = e, stack = stack })
		return true
	end
	return {
		title = title,
		description = description,
		icon = p.kind == "works" and ICON_WORKS or ICON_TOWN,
		onClick = onClick,
		wouldClick = function() : boolean return onClick(false, true) end,
	}
end

return data
