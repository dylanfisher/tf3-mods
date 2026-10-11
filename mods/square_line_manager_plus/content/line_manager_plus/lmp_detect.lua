-- Which of our GUI mods are active in the current game, and their mod settings. Pure logic over the `api` passed in
-- (no globals), so tests/square_line_manager_plus/test_detect.lua drives it with fakes. The same file ships in
-- square_line_revert as line_revert/line_revert_detect.lua (keep the two copies identical).
--
-- Why genericRep and not a presence file: a mod is active in this game exactly when its "react-replacement-config"
-- resource is in api.res.genericRep. The base GUI installs every config it finds there and nothing else
-- (base gui/main/bootstrap_game.tl:12-47: getAllOfType("react-replacement-config"), then each config's doReplaceFn
-- is called), so a config of a disabled mod in the repository would run that mod's code; and the base mission script
-- treats every "missiontask_boot" resource in the repository as the running mission's (base
-- mission/mission_sim.script.tl:206-210, :593-594), while all 8 campaign mission mods that declare one are always
-- installed (mods/release/urbangames_campaign_mission_0N/content/mission/mission.res.lua). Both only work if the
-- repository holds the resources of the active mods alone. Whether ug_require of a disabled mod's file fails is not
-- known, so a presence-file check is not used.
--
-- Mod settings: api.engine.config.getModParams() (api/engine.d.tl:1807, as square_better_minimap reads it in a GUI script)
-- gives each param as the 1-based index of the chosen value (docs/findings.md); an Off/On param is On at 2.

local M = {}

M.CONFIG_TYPE = "react-replacement-config"

--- The data tables of the "react-replacement-config" resources whose filePath belongs to modId ("<modId>::/...").
--- Same call as the base bootstrap (no includeInvisible), so it is exactly the set the game installs. Errors (no
--- api.res in this Lua state) propagate: callers decide the fallback.
function M.configsOf(api, modId)
	local rep = api.res.genericRep
	local prefix = modId .. "::"
	local out = {}
	for _i, id in ipairs(rep.getAllOfType(M.CONFIG_TYPE) or {}) do
		local res = rep.get(id)
		local data = res and res.data
		local path = data and data.filePath
		if type(path) == "string" and path:sub(1, #prefix) == prefix then out[#out + 1] = data end
	end
	return out
end

--- true when modId is active in this game (it has a react-replacement-config). Errors propagate.
function M.isActive(api, modId)
	return #M.configsOf(api, modId) > 0
end

--- true when modId is active and at least one of its configs does not declare `yieldsTo = myModId`, i.e. it will
--- install its own GUI changes even though myModId is active (an older revision without the hand-shake).
function M.activeWithoutYield(api, modId, myModId)
	for _i, data in ipairs(M.configsOf(api, modId)) do
		if data.yieldsTo ~= myModId then return true end
	end
	return false
end

--- The mod params table of modId ({ key = 1-based index }), or nil when missing or unreadable (never errors).
function M.modParams(api, modId)
	local ok, all = pcall(function() return api.engine.config.getModParams() end)
	if not ok or type(all) ~= "table" then return nil end
	local mine = all[modId]
	if type(mine) ~= "table" then return nil end
	return mine
end

--- An Off/On param (values {"Off", "On"}, default On): false only when it is explicitly 1 (Off). A missing table or
--- key (an older settings set, an unreadable table) counts as On, the default.
function M.paramOn(params, key)
	if type(params) ~= "table" then return true end
	return params[key] ~= 1
end

return M
