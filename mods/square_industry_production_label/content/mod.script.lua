-- Industry Production Label: mod entry point (PLAN "Mechanism").
-- Referenced from mod.json as "square_industry_production_label::/mod.script@runFn"
-- (same shape as .cache/game/mods/release/urbangames_vehicles_no_end_year/mod.json + content/mod.script.lua).
--
-- runFn registers ONE "loadConstruction" resource modifier
-- (docs/wiki/modding/scripting/modifiersfilters.md, docs/wiki/modding/general/modscripts.md "runScript").
-- It gives every industry construction (data.isIndustry, set by all 32 base industries, e.g.
-- .cache/game/base/content/industries/fishing_grounds/fishing_grounds.con.lua:108) a hudIconScript,
-- unless the construction already has one (another mod's or a future base one): never overridden.
-- HudIconMasterGame appends the hudIconScript's result to the industry's HUD icon next to the stock
-- (.cache/game/base/content/gui/main/hud_icon_toolbox.tl:242-251, 353-356).
-- The construction resource is changed in memory only; nothing is written to the savegame.
--
-- Options (PLAN "Options", "Settings read live (2026-10-07)"): the mod.json params showProduction /
-- showPickup / showWarehouse are NOT baked in here any more. Revision 3 put them into the hudIconScript
-- params (or left the script off), and in game switching "Show warehouse rates" Off and loading did not
-- remove the warehouse pills: the game apparently keeps the loaded construction resources when only mod
-- params change. So the modifier always attaches the script, the params only carry the kind
-- ({kind = "industry"} / {kind = "warehouse"}), and production_label.script.tl reads the settings live
-- from api.engine.config.getModParams() each time a HUD icon is mounted. runFn still reads its
-- allModParams[modId] (1-based value index, values {"On", "Off"}: 1 = On, 2 = Off;
-- docs/wiki/modding/general/modscripts.md "Mod Params" and "runScript"), but only for the log line.
--
-- Warehouses (PLAN "Warehouse rates (2026-10-07)", option showWarehouse): the base warehouse
-- construction (.cache/game/base/content/warehouses/warehouse.con.lua) has no isIndustry and no
-- hudIconScript; its updateScript is "warehouse.script@updateFn". Every warehouse_era_*.metacon.tl preset
-- builds it through createTemplateFn (constructionFileName = "warehouse.con", warehouse.script.lua:42-54),
-- so placed warehouses are all that one construction resource. It is recognised either by its resource
-- name (ends in "warehouses/warehouse.con", optionally ".lua"; the exact fileName string the modifier
-- gets is not documented, base resource names look like "::/stations/.../x.con",
-- mission/guide_system/main/guide_system_story.tl:12, mission/modifier.lua:98-108 splits it at "::")
-- or by that updateScript. It gets the same hudIconFn with params {kind = "warehouse"}, which mounts the
-- warehouse recipe (incoming / outgoing per-year pills). The modifier is always registered and every
-- industry and warehouse gets the script, whatever the settings: the HUD decides what to draw.
--
-- Plain Lua that runs in the game: pre-5.3 only (no math.tointeger, //, bitwise ops, utf8.*).

local MOD_ID = "square_industry_production_label"
local HUD_ICON_FN = MOD_ID .. "::/production_label/production_label.script@hudIconFn"

-- mod.json param value for "Off" (values {"On", "Off"}, 1-based index). Anything else, including a
-- missing value (params table absent or from an older mod version), counts as On: the default.
-- Same rule as model.options, which the HUD uses.
local PARAM_OFF = 2

--- {showProduction, showPickup, showWarehouse} from runFn's allModParams, for the log line only
--- (the HUD reads the settings itself). Never errors.
local function readOptions(allModParams)
	local mine = type(allModParams) == "table" and allModParams[MOD_ID] or nil
	if type(mine) ~= "table" then
		mine = {}
	end
	return {
		showProduction = mine.showProduction ~= PARAM_OFF,
		showPickup = mine.showPickup ~= PARAM_OFF,
		showWarehouse = mine.showWarehouse ~= PARAM_OFF,
	}
end

local WAREHOUSE_CON = "warehouses/warehouse.con"
local WAREHOUSE_UPDATE_FN = "warehouse.script@updateFn"

--- True when `s` is `suffix` or ends in "/" .. suffix (also after a "::" resource prefix).
local function isPathSuffix(s, suffix)
	if type(s) ~= "string" then
		return false
	end
	if s == suffix then
		return true
	end
	local tail = "/" .. suffix
	return #s >= #tail and s:sub(-#tail) == tail
end

--- The base warehouse construction (or a copy of it), by resource name or by its updateScript.
--- Industries never count (they keep the industry label).
local function isWarehouse(fileName, data)
	if data.isIndustry then
		return false
	end
	if type(fileName) == "string" then
		local name = fileName
		if name:sub(-4) == ".lua" then
			name = name:sub(1, -5)
		end
		if isPathSuffix(name, WAREHOUSE_CON) then
			return true
		end
	end
	local update = data.updateScript
	return type(update) == "table" and isPathSuffix(update.fileName, WAREHOUSE_UPDATE_FN)
end

local function onOff(v)
	return v and "on" or "off"
end

--- True for a nil hudIconScript or one with an empty fileName (the ConstructionDesc default, see
--- the `desc.hudIconScript.fileName ~= ""` check in hud_icon_toolbox.tl:248). Anything else,
--- including a value of an unexpected type, counts as set and is left alone.
local function isEmptyScriptRef(ref)
	if ref == nil then
		return true
	end
	if type(ref) ~= "table" then
		return false
	end
	return ref.fileName == nil or ref.fileName == ""
end

--- The loadConstruction modifier. Independent of the settings (the HUD reads them live). Each
--- construction gets its own params table, so no two construction resources share a Lua table.
local function constructionModifier(fileName, data)
	if type(data) ~= "table" or not isEmptyScriptRef(data.hudIconScript) then
		return data
	end
	if data.isIndustry then
		data.hudIconScript = {
			fileName = HUD_ICON_FN,
			params = { kind = "industry" },
		}
	elseif isWarehouse(fileName, data) then
		data.hudIconScript = {
			fileName = HUD_ICON_FN,
			params = { kind = "warehouse" },
		}
	end
	return data
end

function data()
	return {
		runFn = function(configDict, allModParams)
			-- No "register once" guard: the game resets its modifier table on every load while this
			-- file stays cached, so a guard skipped registration on later loads. Base base_mod.lua
			-- and the official mods register unconditionally; the modifier itself is idempotent.
			-- Always registered: the settings only decide what the HUD draws (read there, live).
			addModifier("loadConstruction", constructionModifier)
			local options = readOptions(allModParams)
			log.message("square_industry_production_label: loadConstruction modifier registered (settings at load: production "
				.. onOff(options.showProduction) .. ", pickup " .. onOff(options.showPickup)
				.. ", warehouse " .. onOff(options.showWarehouse) .. ")")
		end,
	}
end
