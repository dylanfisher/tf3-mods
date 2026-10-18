-- Line Manager Plus, feature "Vehicle list: vehicle info on hover" (setting vehicle_list_hover_info): hovering a
-- vehicle's picture cell in the Line Manager's vehicle list shows an info block about the vehicle OUTSIDE the Line
-- Manager, right of it (left when the window is in the right half of the screen), top aligned with the hovered row:
-- its name, its line (or In Depot / Going to Depot), its parts by model (a train: every locomotive and wagon kind,
-- "2× Class 01" per run of equal models), then Top speed, Power, Weight / Age, Condition / Running costs, Value,
-- Last year. The same block, look and behaviour as the line list's (line_list_hover.lua), through lmp_callout.lua;
-- no stylesheet rule of its own. Player request 2026-10-11 (the game's picture only says "Open Vehicle Window").
-- GUI only: reads the game state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace).
--
-- Where the cell comes from: VehicleList (base gui/line_vehicle_mgmt/vehicle_list_react_util.tl:525-605) renders
-- builtin.DataTable{ columns = { checkbox, VehicleLineSmall, VehicleName, VehicleIcon } }; VehicleIcon (:375-520)
-- is the picture (a Button "Open Vehicle Window"), a filler, the notification widget, Locate and Remove. The cell
-- param is { rowKey = vehicle, colKey, userParam = { commonParams, ... } } (VehicleListUserParams, :12-23).
--
-- Hook: as line_list_hover.lua (its header has the details), the MODULE FIELD builtin.ColumnDesc is wrapped; for the
-- column whose recipe is VehicleIcon, the cell is called as inner(react.ref({ holder }), { ..., meta = {
-- onMouseOver } }): no extra node, the vanilla cell and its own mouse listener untouched. A third ColumnDesc wrapper
-- next to line_list_hover's and vehicle_cargo's; each only touches its own column. The hover covers the whole picture
-- cell (picture, gap, Locate, Remove): onMouseOver is per node, the picture Button is inside the vanilla recipe.
--
-- Position: x = the line list's edge (commonParams.lineAndDepotListRef: the window is one column, so it is the
-- window's edge too; without it the cell's own edge), y = the hovered row's top; M.GAP as line_list_hover.
-- Expiry: the holder expires once the vehicle is gone (sold while hovered) or the list ref has expired.
--
-- Data (as the vehicle window, base entity_window/vehicle/vehicle_eow.script.tl, vehicle_store_util.tl:284-370,
-- vehicle_util.tl): parts = transportVehicleConfig.vehicles[i].part.modelId -> modelRep metadata (description.name,
-- already shown untranslated by base, as stli_core.modelName); top speed = the slowest part's land/water/air
-- topSpeed (m/s, api.util.formatSpeed); power = the sum of land engines' power (kW) or water availPower (W);
-- weight = the sum of weightEmpty (kg -> t, formatWeight); age = formatAge(oldest purchaseTime, game time);
-- condition = the parts' mean maintenanceState with the game's own level word (vehicle_util.getConditionText,
-- already translated); running costs = api.engine.util.vehicle.getRunningCost (per year); value =
-- getDepreciatedValue; last year = finance.calculateBalance({ vehicle }, now - year, now, true) (maintenance and
-- income only, as the vehicle window's "Last Year"). Every value is read on its own in pcall: a failing one is left
-- out (logged once), the rest still shows. Built only when a row is hovered (GUI thread, onMouseOver).
-- SQPERF section "vehicle_hover": building the hovered vehicle's block text.

local PREFIX = "[LineManagerPlus] vehicle hover: "

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
local callout = ug_require "square_line_manager_plus::/line_manager_plus/lmp_callout.lua"
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local function optional(path)
	local ok, mod = pcall(ug_require, path)
	if ok and type(mod) == "table" then return mod end
	warnOnce("require " .. path, mod)
	return nil
end
local lang_util = optional("::/scripts/lang_util.tl")
local vehicle_util = optional("::/gui/line_vehicle_mgmt/vehicle_util.tl")

local M = {}

M.ROW_RECIPE = "VehicleIcon"
M.BUILTIN = "::/gui/main/builtin.lua"
M.GAP = 18 -- UI px from the line list's edge, as line_list_hover.lua
M.SEPARATOR = "  ·  " -- between the stats, as stli_core.SEPARATOR

local function format(s, t)
	if lang_util then return lang_util.format(s, t) end
	return (s:gsub("{(%w+)}", function(k) return tostring(t[k]) end))
end
local function int(n)
	if lang_util then return lang_util.formatInt(n) end
	return tostring(math.floor(n + 0.5))
end

-- one value, or nil (logged once) if its call fails
local function try(key, fn)
	local ok, v = pcall(fn)
	if ok then return v end
	warnOnce(key, v)
	return nil
end

local function metadataOf(modelId)
	return api.res.modelRep.get(modelId).metadata
end

--- The parts lines: one per run of equal model names, "Name" for a single part, "{count}× {name}" for a run.
--- names: the parts' model names in train order.
function M.partLines(names)
	local out, run, count = {}, nil, 0
	local function flush()
		if run == nil then return end
		if count == 1 then out[#out + 1] = run
		else out[#out + 1] = format(_("{count}× {name}"), { count = int(count), name = run }) end
	end
	for _i, n in ipairs(names) do
		if n == run then
			count = count + 1
		else
			flush()
			run, count = n, 1
		end
	end
	flush()
	return out
end

--- The vehicle's model names (1 per part) and its summed physics, from the parts' metadata. Errors propagate.
function M.parts(tv)
	local names = {}
	local speed, power, weight = nil, 0, 0
	for _i, p in ipairs(tv.transportVehicleConfig.vehicles) do
		local md = metadataOf(p.part.modelId)
		local desc = md.description
		names[#names + 1] = (desc and desc.name) or "?"
		local body = md.landVehicle or md.waterVehicle or md.airVehicle
		if body then
			if type(body.topSpeed) == "number" and body.topSpeed > 0 then
				speed = speed and math.min(speed, body.topSpeed) or body.topSpeed
			end
			if type(body.weightEmpty) == "number" then weight = weight + body.weightEmpty end
		end
		if md.landVehicle and md.landVehicle.engines then
			for _k, e in ipairs(md.landVehicle.engines) do
				if type(e.power) == "number" then power = power + e.power end
			end
		elseif md.waterVehicle and type(md.waterVehicle.availPower) == "number" then
			power = power + 1e-3 * md.waterVehicle.availPower
		end
	end
	return { names = names, speed = speed, power = power, weight = 1e-3 * weight }
end

local function gameTime()
	return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME).gameTime
end

--- Where the vehicle is: its line's name, "In Depot" or "Going to Depot". nil when unknown.
function M.placeText(tv)
	local S = api.type.enum.TransportVehicleState
	if tv.state == S.EN_ROUTE or tv.state == S.AT_TERMINAL then
		if type(tv.line) == "number" and tv.line > 0 and api.engine.entityExists(tv.line) then
			return api.engine.util.getEntityName(tv.line)
		end
		return nil
	end
	if tv.state == S.GOING_TO_DEPOT then return _("Going to Depot") end
	return _("In Depot")
end

--- The block text for `vehicle`, or nil when it isn't a vehicle (sold). Single values that fail are left out.
function M.panelText(vehicle)
	if type(vehicle) ~= "number" or not api.engine.entityExists(vehicle) then return nil end
	local tv = api.engine.getComponent(vehicle, api.type.ComponentType.TRANSPORT_VEHICLE)
	if tv == nil then return nil end
	local lines = {}
	local name = try("name", function() return api.engine.util.getEntityName(vehicle) end)
	if type(name) == "string" and name ~= "" then lines[#lines + 1] = name end
	local place = try("place", function() return M.placeText(tv) end)
	if type(place) == "string" and place ~= "" then lines[#lines + 1] = place end

	local parts = try("parts", function() return M.parts(tv) end)
	if parts then
		for _i, s in ipairs(M.partLines(parts.names)) do lines[#lines + 1] = s end
	end

	local function row(items)
		local r = {}
		for _i, it in ipairs(items) do
			if it[2] then r[#r + 1] = format(_("{label}: {value}"), { label = it[1], value = it[2] }) end
		end
		if #r > 0 then lines[#lines + 1] = table.concat(r, M.SEPARATOR) end
	end

	row({
		{ _("Top Speed"), parts and parts.speed and try("speed", function() return api.util.formatSpeed(parts.speed) end) },
		{ _("Power"), parts and parts.power > 0 and try("power", function() return api.util.formatPower(parts.power) end) or nil },
		{ _("Weight"), parts and parts.weight > 0 and try("weight", function() return api.util.formatWeight(parts.weight) end) or nil },
	})

	local now = try("time", gameTime)
	local age = now and try("age", function()
		local oldest
		for _i, p in ipairs(tv.transportVehicleConfig.vehicles) do
			if type(p.purchaseTime) == "number" and (oldest == nil or p.purchaseTime < oldest) then oldest = p.purchaseTime end
		end
		return oldest and api.engine.util.formatAge(oldest, now)
	end)
	local condition = try("condition", function()
		local n, sum = 0, 0
		for _i, p in ipairs(tv.transportVehicleConfig.vehicles) do
			n, sum = n + 1, sum + p.maintenanceState
		end
		if n == 0 then return nil end
		local state = sum / n
		local pct = api.util.toStringPercentPrecision(state, 0)
		if vehicle_util and vehicle_util.getConditionText then
			return format(_("{condition} ({percent})"), { condition = vehicle_util.getConditionText(state), percent = pct })
		end
		return pct
	end)
	row({ { _("Age"), age }, { _("Condition"), condition } })

	local running = try("running", function()
		local c = api.engine.util.vehicle.getRunningCost(vehicle)
		return format(_("{amount}/year"), { amount = api.util.formatMoney(math.floor(c + 0.5)) })
	end)
	local value = try("value", function()
		return api.util.formatMoney(math.floor(api.engine.util.vehicle.getDepreciatedValue(vehicle) + 0.5))
	end)
	local lastYear = now and try("balance", function()
		local from = math.max(now - api.util.getDefaultYearDuration(), 0)
		return api.util.formatMoney(api.engine.util.finance.calculateBalance({ vehicle }, from, now, true))
	end)
	row({ { _("Running Costs"), running }, { _("Value"), value }, { _("Last Year"), lastYear } })

	if #lines == 0 then return nil end
	return table.concat(lines, "\n")
end

--- The block text, timed as SQPERF section "vehicle_hover".
M.timedText = perf:wrap("vehicle_hover", M.panelText)

-- the one block of the vehicle list (the Line Manager is a single window); textFn gets (vehicle, nil)
local shown = callout.newShown(function(vehicle) return M.timedText(vehicle) end, warnOnce)

local function liveNode(ref)
	if ref == nil then return nil end
	if ref.hasExpired ~= nil and ref:hasExpired() == true then return nil end
	return ref:get()
end

--- A ref for react.ref() (as line_list_hover.newHolder): expired once the node is unset, the vehicle is gone or the
--- list ref has expired.
function M.newHolder(vehicle, listRef)
	local h = { node = nil }
	function h:set(node) self.node = node end
	function h:get() return self.node end
	function h:expire() self.node = nil end
	function h:hasExpired()
		if self.node == nil then return true end
		local okE, exists = pcall(api.engine.entityExists, vehicle)
		if not (okE and exists)
				or (listRef ~= nil and listRef.hasExpired ~= nil and listRef:hasExpired() == true) then
			self.node = nil
			return true
		end
		return false
	end
	return h
end

--- Callout params for `text` beside the Line Manager, top aligned with the cell node of `holder`. Errors propagate.
function M.place(holder, listRef, text)
	local edge = liveNode(listRef) or holder:get()
	local onRight = callout.onRightOf(edge)
	local function position()
		local row = holder:get()
		local list = liveNode(listRef) or row
		return api.type.Vec2f.new(list:getPosition(onRight and 1 or 0, 0).x, row:getPosition(0, 0).y)
	end
	local last = position()
	local function getPositionFn()
		local ok, pos = pcall(position)
		if ok and pos ~= nil then
			last = pos
		else
			holder:expire()
		end
		return last
	end
	return callout.besideParams(holder, text, onRight, { gap = M.GAP, getPositionFn = getPositionFn })
end

--- The cell's hover changed: open the block for `vehicle` (hovered) or close the cell's block. Errors propagate.
function M.onHover(holder, vehicle, commonParams, hovered)
	local function getApi() return callout.api(commonParams.gameCtx) end
	if not hovered then return shown:hide(getApi, holder) end
	shown:show(getApi, vehicle, holder, nil, function(text) return M.place(holder, commonParams.lineAndDepotListRef, text) end)
end

--- For a cell param: the ref holder and the param copy with meta.onMouseOver, or nil (leave the call as is).
function M.decorate(cell)
	local kind = type(cell)
	if kind ~= "table" and kind ~= "userdata" then return nil end
	if kind == "table" and cell.meta ~= nil then return nil end
	local vehicle, colKey, up = cell.rowKey, cell.colKey, cell.userParam
	if type(vehicle) ~= "number" then return nil end
	local cp = type(up) == "table" and up.commonParams or nil
	if type(cp) ~= "table" or cp.gameCtx == nil then return nil end
	local holder = M.newHolder(vehicle, cp.lineAndDepotListRef)
	local param = { rowKey = vehicle, colKey = colKey, userParam = up }
	param.meta = { onMouseOver = function(isHovered)
		local ok, err = pcall(M.onHover, holder, vehicle, cp, isHovered == true)
		if not ok then warnOnce("hover", err) end
	end }
	return holder, param
end

local cellFns = setmetatable({}, { __mode = "k" }) -- inner recipe -> our cell function (stable per inner)

--- Our cell function around the picture recipe `inner` (the same function for the same inner).
function M.cellFn(inner)
	local fn = cellFns[inner]
	if fn then return fn end
	fn = function(cell, ...)
		if select("#", ...) == 0 then
			local ok, holder, param = pcall(M.decorate, cell)
			if not ok then
				warnOnce("cell", holder)
			elseif holder ~= nil then
				-- a table ref is a LIST of refs (line_list_hover.rowFn)
				return inner(react.ref({ holder }), param)
			end
		end
		return inner(cell, ...)
	end
	cellFns[inner] = fn
	return fn
end

--- A copy of the ColumnDesc param `p` with our cell function, or nil when it isn't the vehicle list's picture column.
function M.swap(p)
	if type(p) ~= "table" or type(p.recipe) ~= "function" then return nil end
	if react.GetRecipeName(p.recipe) ~= M.ROW_RECIPE then return nil end
	local copy = {}
	for k, v in pairs(p) do copy[k] = v end
	copy.recipe = M.cellFn(p.recipe)
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
		if type(react.GetRecipeName) ~= "function" or type(react.ref) ~= "function" then
			warnOnce("install", "react.GetRecipeName / react.ref missing; vehicle list left as is")
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
