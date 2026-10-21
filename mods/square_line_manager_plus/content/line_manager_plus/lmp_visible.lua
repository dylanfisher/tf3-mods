-- Line Manager Plus: the Line Manager's "Show Only Visible Lines" (the eye in its filter bar, right of the carrier
-- buttons) is remembered with the savegame, and the Send to Line popover follows it.
--   * Line Manager: vanilla keeps the eye while the game runs (ManagerEntryPoint's lvmFilterStateRef, base
--     manager_window.tl:8349-8353, read at each open, :6117-6118) but starts Off after a load.
--   * Send to Line: vanilla starts its own eye Off at every open: SendToLineSelection (:4513-4690) seeds its state with
--     react.useState(params.onlyVisible) (:4515) and every caller passes onlyVisible = false (:7367, :7924). It now
--     opens with the Line Manager's value. A click on the popover's own eye works for that popover only and is not
--     recorded: recording it would mean wrapping builtin.ToggleButton for every toggle in the game (user decision
--     2026-10-17: not worth it).
-- The value is kept in the GUI save data (api.gui.game.setGuiSaveData(PREFS_KEY, { lineManager = bool }), gui.d.tl:
-- 773-781, as Photo Mode's bookmarks): per savegame, kept when the player saves; a new game starts with vanilla Off.
-- setGuiSaveData replaces the whole table for the modId, so every write carries the full prefs table. The game
-- settings are not used: mod.io's upload check rejects mods that write the game settings save. No setting: it only
-- repeats the player's own choice. Writes nothing to the game state.
--
-- Wrappers, all module fields looked up per call (as stl_list.lua and vehicle_cargo.lua do):
--   * manager_window.ManagerWindowContent (called per render by ManagerToolWindow, :8222): on the first call after a
--     load, the remembered value goes into toolParam.lvmFilterStateRef before the content mounts and reads it. Only
--     once per load (the GUI scripts reload with a game load): later the game's own memory holds.
--   * statistics_react_util.createCarrierCategoryFilter: the Line Manager's call (statsType "Lines", rendered by
--     LineManagerActionButtons, :1767-1789; the Statistics window's own call, statistics.tl:571, is left alone) gets
--     a transformState that records the onlyVisible its transform returns when it changed.
--   * popover_react_util.PopoverWindowContent: when the inner recipe is "SendToLineSelection" and a value is
--     remembered, a copy of the param goes on with a copy of its params carrying that onlyVisible. Installed after
--     stl_list.lua, so this wrapper is the outer one and stl_list.lua then gets the adjusted params.
-- Anything failing goes to the previous function unchanged (logged once).

local PREFIX = "[LineManagerPlus] visible lines: "

local warned = {}
local function warnOnce(key, err)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(err) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local react = ug_require "::/gui/main/react.lua"

local M = {}

M.BASE_RECIPE = "SendToLineSelection"
M.FILTER_RECIPE = "LineManagerActionButtons"
M.FILTER_STATS_TYPE = "Lines"
M.POP = "::/gui/main/popover_react_util.tl"
M.MANAGER = "::/gui/line_vehicle_mgmt/manager_window.tl"
M.STATS = "::/gui/statistics/statistics_react_util.tl"
M.PREFS_KEY = "square_line_manager_plus"

-- remembered settings ------------------------------------------------------------------------------------------------

-- { lineManager = bool|nil }: nil until read from the GUI save data (once per load)
local prefs = nil

local function readPrefs()
	local p = {}
	local ok, err = pcall(function()
		-- any shape may come back (another version, a corrupt save): only a boolean lineManager is kept
		local raw = api.gui.game.getGuiSaveData(M.PREFS_KEY)
		if type(raw) ~= "table" then return end
		local lm = raw.lineManager
		if type(lm) == "boolean" then p.lineManager = lm end
	end)
	if not ok then warnOnce("load settings", err) end
	return p
end

--- The remembered value for `which` ("lineManager"); nil when the player never set it. Never errors.
function M.get(which)
	if prefs == nil then prefs = readPrefs() end
	return prefs[which]
end

--- Remembers `value` for `which` and writes the GUI save data when it changed. Never errors.
function M.set(which, value)
	if M.get(which) == value then return end
	prefs[which] = value
	local ok, err = pcall(function()
		-- setGuiSaveData replaces our whole table: write every pref
		api.gui.game.setGuiSaveData(M.PREFS_KEY, { lineManager = prefs.lineManager })
	end)
	if ok then
		say("saved " .. which .. " = " .. tostring(value))
	else
		warnOnce("save settings", err)
	end
end

-- swaps --------------------------------------------------------------------------------------------------------------

local function copyOf(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function currentRecipeIs(name)
	if type(react.getCurrentRecipeName) ~= "function" then return true end
	local ok, current = pcall(react.getCurrentRecipeName)
	return not ok or current == nil or current == name -- unreadable: the class / statsType alone decides
end

--- A copy of the PopoverWindowContent param `p` whose params carry the Line Manager's remembered onlyVisible, or nil when `p` isn't
--- the Send to Line popover or nothing needs changing. Errors propagate.
function M.swapPopover(p)
	if type(p) ~= "table" or p.recipe == nil then return nil end
	local params = p.params
	if type(params) ~= "table" then return nil end
	if react.GetRecipeName(p.recipe) ~= M.BASE_RECIPE then return nil end
	local want = M.get("lineManager")
	if want == nil or params.onlyVisible == want then return nil end
	local copy = copyOf(p)
	copy.params = copyOf(params)
	copy.params.onlyVisible = want
	return copy
end

local managerApplied = false -- the remembered value went into the Line Manager's filter (once per load)

--- Puts the remembered value into the Line Manager's filter state on the first ManagerWindowContent call of the
--- load, before the content mounts. Errors propagate (the flag is set first: one try per load).
function M.applyManager(payload)
	if managerApplied then return end
	managerApplied = true
	local want = M.get("lineManager")
	if want == nil then return end
	local ref = payload.toolParam.lvmFilterStateRef
	local cur = ref:get()
	if cur.onlyVisible == want then return end
	local c = copyOf(cur)
	c.onlyVisible = want
	ref:set(c)
end

--- The transformState for the Line Manager's filter bar: records the onlyVisible a transform changes, or nil when
--- this isn't the Line Manager's call. Errors propagate.
function M.swapTransform(statsType, transformState)
	if statsType ~= M.FILTER_STATS_TYPE or type(transformState) ~= "function" then return nil end
	if not currentRecipeIs(M.FILTER_RECIPE) then return nil end
	return function(fn, ...)
		return transformState(function(cur, ...)
			local result = fn(cur, ...)
			if type(result) == "table" and type(cur) == "table" and result.onlyVisible ~= cur.onlyVisible then
				M.set("lineManager", result.onlyVisible == true)
			end
			return result
		end, ...)
	end
end

-- wrappers -----------------------------------------------------------------------------------------------------------

local prev, wrappers = {}, {} -- per wrapped field: the function we wrapped, ours

local function content(p, ...)
	if select("#", ...) == 0 then
		local ok, copy = pcall(M.swapPopover, p)
		if not ok then
			warnOnce("popover", copy)
		elseif copy ~= nil then
			return prev.pop(copy)
		end
	end
	return prev.pop(p, ...)
end

local function managerContent(payload, ...)
	if not managerApplied then
		local ok, err = pcall(M.applyManager, payload)
		if not ok then warnOnce("line manager", err) end
	end
	return prev.manager(payload, ...)
end

local function carrierFilter(categories, statsType, oldState, transformState, ...)
	local ok, wrapped = pcall(M.swapTransform, statsType, transformState)
	if not ok then
		warnOnce("filter", wrapped)
	elseif wrapped ~= nil then
		transformState = wrapped
	end
	return prev.filter(categories, statsType, oldState, transformState, ...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the function we wrapped instead (as stl_list.lua)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		for key, w in pairs(wrappers) do
			if original == w then original = prev[key] end
		end
		return replace(original, ...)
	end
end

--- Wraps the fields; true when installed (now or before). The Line Manager pair (content + filter) installs as a
--- whole or not at all; the popover on its own. Never errors.
function M.install(replacementApi)
	if prev.pop or prev.manager then return true end
	local ok, err = pcall(function()
		if type(react.GetRecipeName) ~= "function" then
			warnOnce("install", "react.GetRecipeName is missing; not installed")
			return
		end
		local done = {}
		local pop = ug_require(M.POP)
		local fnPop = type(pop) == "table" and pop.PopoverWindowContent or nil
		if type(fnPop) == "function" then
			prev.pop, wrappers.pop = fnPop, content
			pop.PopoverWindowContent = content
			done[#done + 1] = "send to line"
		else
			warnOnce("install stl", "PopoverWindowContent is " .. type(fnPop) .. "; Send to Line left as is")
		end
		local mw, sru = ug_require(M.MANAGER), ug_require(M.STATS)
		local fnManager = type(mw) == "table" and mw.ManagerWindowContent or nil
		local fnFilter = type(sru) == "table" and sru.createCarrierCategoryFilter or nil
		if type(fnManager) == "function" and type(fnFilter) == "function" then
			prev.manager, prev.filter = fnManager, fnFilter
			wrappers.manager, wrappers.filter = managerContent, carrierFilter
			mw.ManagerWindowContent = managerContent
			sru.createCarrierCategoryFilter = carrierFilter
			done[#done + 1] = "line manager"
		else
			warnOnce("install lm", "ManagerWindowContent is " .. type(fnManager) .. ", createCarrierCategoryFilter is "
				.. type(fnFilter) .. "; Line Manager filter not remembered")
		end
		if #done > 0 then
			shimReplacementApi(replacementApi)
			say("installed (" .. table.concat(done, ", ") .. ")")
		end
	end)
	if not ok then
		warnOnce("install", err)
	end
	return prev.pop ~= nil or prev.manager ~= nil
end

return M
