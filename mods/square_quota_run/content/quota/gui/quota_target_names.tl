-- Quota Run rule-target names (v2.1 addendum, PLAN §9.3). GUI thread, read-only: used by the HUD
-- (quota_hud.script.tl getFromEngine) and the notification script, so both name the same target
-- the same way. quota_hud_model stays pure: it only exposes ruleTarget + ruleTargetKind.
-- Every lookup is nil-safe (nil / non-number id, unknown kind, deleted town, invalid cargo id,
-- engine error) and cheap (one engine call), so it can run in the 0.5 s HUD poll.
--
-- Town: api.engine.util.getEntityName (.cache/game/api/tealdef/api/engine/util.d.tl:1038-1040),
--   the call the base town HUD uses on the GUI thread for a town entity
--   (.cache/game/base/content/gui/main/town_hud_react_util.tl:57-61).
-- Cargo type: api.res.cargoTypeRep.get(id).name (.cache/game/api/tealdef/api/res.d.tl:13-18,82;
--   CargoType.name "Display name", .cache/game/api/tealdef/api/type.d.tl:5254-5255). Base GUI uses
--   it untranslated inside lang_util.format (.cache/game/base/content/game_mechanics/towns/town_react_util.tl:194;
--   also .cache/game/base/content/gui/main/cargo_react_util.tl:27-28): the resource already holds
--   the localised text (name = _("Beverages"), .cache/game/base/content/cargos/beverages/beverages.cargo.lua:4).
-- Neither name is wrapped in _() again.

local function nonEmpty(v : any) : string
	if type(v) == "string" and v ~= "" then return v as string end
	return nil
end

local function townName(entity : integer) : string
	if not api.engine.entityExists(entity) then return nil end
	return nonEmpty(api.engine.util.getEntityName(entity))
end

local function cargoTypeName(id : integer) : string
	if id < 0 then return nil end
	local cargoType = api.res.cargoTypeRep.get(id)
	return cargoType and nonEmpty(cargoType.name) or nil
end

local names : QuotaRunTargetNames = {}

function names.resolve(kind : string, id : integer) : string
	if type(id) ~= "number" then return nil end
	-- ids may come back as floats after save/load (QuotaRunTally note)
	local n = math.floor(id)
	local lookup : function(integer) : string = nil
	if kind == "town" then
		lookup = townName
	elseif kind == "cargoType" then
		lookup = cargoTypeName
	else
		return nil
	end
	-- pcall: an invalid id may raise in the engine binding; a missing name must never break the GUI.
	local okCall, result = pcall(lookup, n)
	if okCall then return nonEmpty(result) end
	return nil
end

return names
