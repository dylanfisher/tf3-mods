-- Line Manager Plus: the Line Manager's vehicle list gives its spare width to the vehicle NAME column (rev 5, player
-- request 2026-10-11: short pictures left a wide empty strip while names were cut off). Always installed (no setting,
-- as the column rules in lmp.css.lua it goes with). GUI only.
--
-- VehicleList (base gui/line_vehicle_mgmt/vehicle_list_react_util.tl:525-605) builds its DataTable columns with
-- builtin.ColumnDesc and no weights. builtin.ColumnDescParam has `weight` (builtin.d.tl:1142; the statistics tables
-- weight every column, statistic_stations.tl:282-289). The MODULE FIELD builtin.ColumnDesc is wrapped (as
-- line_list_hover.lua / vehicle_cargo.lua / vehicle_hover.lua, chained with them): for the column whose recipe is
-- VehicleName, a copy with weight = M.NAME_WEIGHT. lmp.css.lua sizes the picture column to its content and lets
-- VehicleName (and the cargo badge's cell around it) stretch, so the name takes what the pictures leave.
-- Every other call goes to the previous function unchanged; a failure falls back to it (logged once).

local PREFIX = "[LineManagerPlus] vehicle columns: "

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

M.NAME_RECIPE = "VehicleName"
M.NAME_WEIGHT = 1.0
M.BUILTIN = "::/gui/main/builtin.lua"

--- A copy of the ColumnDesc param `p` with the name weight, or nil when it isn't the vehicle list's name column.
function M.swap(p)
	if type(p) ~= "table" or type(p.recipe) ~= "function" then return nil end
	if react.GetRecipeName(p.recipe) ~= M.NAME_RECIPE then return nil end
	local copy = {}
	for k, v in pairs(p) do copy[k] = v end
	copy.weight = M.NAME_WEIGHT
	return copy
end

local prev -- the ColumnDesc we wrapped, set by install()
local wrapper -- our function in builtin.ColumnDesc

local function columnDesc(...)
	if select("#", ...) == 1 then
		local ok, copy = pcall(M.swap, ...)
		if not ok then
			warnOnce("column", copy)
		elseif copy ~= nil then
			local okNode, node = pcall(prev, copy)
			if okNode then return node end
			warnOnce("column", node)
		end
	end
	return prev(...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the function we wrapped instead (as line_list_hover.lua)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		if wrapper ~= nil and original == wrapper then original = prev end
		return replace(original, ...)
	end
end

--- Wraps builtin.ColumnDesc; true when installed (now or before). Never errors.
function M.install(replacementApi)
	if prev then return true end
	local ok, err = pcall(function()
		local builtin = ug_require(M.BUILTIN)
		local fn = type(builtin) == "table" and builtin.ColumnDesc or nil
		if type(fn) ~= "function" then
			warnOnce("install", "builtin.ColumnDesc is " .. type(fn) .. "; vehicle list left as is")
			return
		end
		if type(react.GetRecipeName) ~= "function" then
			warnOnce("install", "react.GetRecipeName missing; vehicle list left as is")
			return
		end
		prev = fn
		wrapper = columnDesc
		builtin.ColumnDesc = wrapper
		shimReplacementApi(replacementApi)
		say("installed")
	end)
	if not ok then
		warnOnce("install", err)
	end
	return prev ~= nil
end

return M
