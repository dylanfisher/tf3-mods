-- Line Rate Matcher: mounts the toolbar button left of Auto-Rename ("A+") in the Line Manager's line details
-- (plans/square_line_rate_matcher/PLAN.md phase 3). GUI only: no game script, nothing in the savegame.
--
-- Mount: the technique of square_line_revert (line_revert.script.lua) and the in-game-verified DEV probe
-- square_line_rate_matcher_probe (rmprobe.script.lua, docs/findings.md "Line Rate, cloning onto a line, sell on
-- arrival"): two module-function wrappers installed by doReplace (rate_matcher_replace.res.lua, order 260):
-- * line_util.makeLineActionDescriptor captures the manager's commonParams; the line in the details panel is
--   commonParams.lineState:old().entityAndRevision.entity (manager_window.tl:458-459).
-- * button_react_util.makeIconToggleButton: when it builds the A+ icon (symbol_autorename.tga) inside the
--   LinePanelActionButtons recipe (lines only; depots use LinePanelDepotActionButtons, manager_window.tl:3323), our
--   button is put to its left. The button hides itself unless exactly one line is selected.
-- doReplace reads the current module functions, so the wrappers of Line Editor Undo (200), Line Manager Plus (250)
-- and others stay in the chain. The DEV probe (250) mounts its own "RM" row the same way: disable it (mod.json lists
-- it as incompatible; a log line says so when both are active).
--
-- The button and the window are Teal modules (rate_matcher_window.tl); this file only wires them in.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local button_react_util = ug_require "::/gui/main/button_react_util.tl"
local line_util = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
local window = ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher_window.tl"

local AUTO_RENAME_ICON = "::/gui/line_vehicle_mgmt/icons/symbol_autorename.tga"
local RECIPE_ACTION_BUTTONS = "LinePanelActionButtons"
local PREFIX = "[RateMatcher] "
local PROBE_MOD = "square_line_rate_matcher_probe"

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local warned = {}
local function warnOnce(key, msg)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

-- Context ------------------------------------------------------------------------------------------------------
local managerParams -- latest commonParams seen by makeLineActionDescriptor

local function selectedCount(params)
	local st = params and params.lineManagerStateRef and params.lineManagerStateRef:get()
	return st and st.lineListEntitiesSelected and #st.lineListEntitiesSelected or 0
end

local function shownLine(params)
	local ls = params and params.lineState and params.lineState:old()
	local e = ls and ls.entityAndRevision and ls.entityAndRevision.entity or nil
	if type(e) == "number" and e >= 0 then return e end
	return nil
end

-- The Line Manager's vehicle list, as vanilla Clone's onBuy adds its new vehicles (manager_window.tl:5108-5117):
-- commonParams.addOrRemoveVehicleToVehicleList({entity, removeFromList}) (manager_window.tl:7000-7017,
-- line_util.d.tl:525-527) calls the vehicle manager's addVehiclesToVehicleListAndSelect /
-- removeVehiclesFromVehicleList. The list is otherwise only filled when a line is selected (:1405-1410).
local function listFn(params, remove)
	local fn = params and params.addOrRemoveVehicleToVehicleList
	if type(fn) ~= "function" then return nil end
	return function(ids)
		for _i, id in ipairs(ids or {}) do
			fn({ entity = id, removeFromList = remove })
		end
	end
end

--- SquareRateMatcherContext: the line (exactly one selected), protected entities, the mission vehicle filter and
--- the vehicle list functions.
local function context()
	local params = managerParams
	if not params then return nil end
	local line = nil
	if selectedCount(params) == 1 then line = shownLine(params) end
	local filters = params.gameCtx and params.gameCtx.filters and params.gameCtx.filters:get()
	return {
		line = line,
		protected = filters and filters.protectedEntities or nil,
		vehicleFilter = filters and filters.vehicleFilter or nil,
		listAdd = listFn(params, false),
		listRemove = listFn(params, true),
	}
end

-- Wrappers -----------------------------------------------------------------------------------------------------
local origDescriptor -- set in doReplace
local function lineActionDescriptor(commonParams, ...)
	local ok, err = pcall(function()
		if type(commonParams) == "table" and commonParams.lineManagerStateRef then managerParams = commonParams end
	end)
	if not ok then warnOnce("descriptor", err) end
	return origDescriptor(commonParams, ...)
end

local origToggle -- set in doReplace
local function iconToggleButton(className, path, ...)
	local node = origToggle(className, path, ...)
	if path ~= AUTO_RENAME_ICON then return node end
	local ok, wrapped = pcall(function()
		if react.getCurrentRecipeName() ~= RECIPE_ACTION_BUTTONS or not managerParams then return nil end
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			-- the recipe is the item itself, never a Component layout (memory: recipe-not-component-layout)
			children = { window.ToolbarButton{}, node },
		}
	end)
	if not ok then
		warnOnce("button", wrapped)
		return node
	end
	return wrapped or node
end

local function probeActive()
	local ok, active = pcall(function()
		local rep = api.res.genericRep
		local prefix = PROBE_MOD .. "::"
		for _i, id in ipairs(rep.getAllOfType("react-replacement-config") or {}) do
			local res = rep.get(id)
			local path = res and res.data and res.data.filePath
			if type(path) == "string" and path:sub(1, #prefix) == prefix then return true end
		end
		return false
	end)
	return ok and active
end

local function doReplace(_replacementApi)
	if origToggle or origDescriptor then return end -- already installed
	-- read the current functions now, not at load, so wrappers installed earlier stay in the chain
	local toggle, descriptor = button_react_util.makeIconToggleButton, line_util.makeLineActionDescriptor
	if type(toggle) ~= "function" or type(descriptor) ~= "function" then
		warnOnce("install", "makeIconToggleButton " .. type(toggle) .. ", makeLineActionDescriptor " .. type(descriptor))
		return
	end
	origToggle, origDescriptor = toggle, descriptor
	button_react_util.makeIconToggleButton = iconToggleButton
	line_util.makeLineActionDescriptor = lineActionDescriptor
	window.setContextFn(context)
	say("installed (order 260)")
	if probeActive() then
		log.warning(PREFIX .. "the DEV probe " .. PROBE_MOD .. " is active too and adds its own RM buttons;"
			.. " disable it (it is only for development)")
	end
end

-- .script.lua resources expose their exports through data(), not a return value (memory: script-lua-exports-via-data)
function data()
	return {
		doReplace = doReplace,
	}
end
