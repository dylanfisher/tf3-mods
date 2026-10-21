-- Line Manager Plus, feature "Buy Vehicles: line's cargo filter" (setting buy_vehicles_line_filter): Buy Vehicles for a
-- single selected line opens the vehicle store with the line's cargo already set in its cargo filter (the passenger
-- toggle for a bus line), when the line carries exactly one cargo type; so do Replace / Modify for vehicles of one line
-- (Line Manager and vehicle window, 2026-10-20). The player can untick it as usual. GUI only:
-- reads the game state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace) through install().
--
-- Where the store comes from: the line editor's Buy Vehicles button (base manager_window.tl:7395-7410
-- btnBuyVehiclesOnClick) calls line_util.getBestDepotForLine(line) and then opens the store at that depot. That click
-- is the only caller of getBestDepotForLine in the base GUI. The store's browser (vehicle_store_window.tl:2459,
-- file-local VehicleStoreBrowser) builds its first filter with cargoFilters = {} and passes it through
-- vehicle_store_util.handleRailCarrier / handleTramCarrier / handleDefaultCarrier (:2523-2539), again on every tab
-- change with a deep copy of the current filter (:2829). Those are module fields looked up per call.
--
-- How:
-- * getBestDepotForLine is wrapped: after the base picked a depot, the line's cargo types are the ones its stops load
--   (Line.Stop.stopConfig.load: exactly the player's load settings, passengers on every bus stop, the cargo at the
--   loading stop of a cargo line; docs/findings/lines-vehicles.md, console 2026-10-20). Stops that load nothing fall
--   back to the line's cargo icons' source (line_react_util.tl:687-693 LineCargoDisplay:
--   cargo_util.getSortedProducedCargoTypes with the line, "CAPACITY", allLineCapacities). Exactly one type arms a pending filter for that depot's carrier and
--   filter tags, valid PENDING_US (the store mounts a frame or two after the click). More than one type arms
--   nothing: the store's cargo filter keeps only vehicles that carry EVERY ticked type (vehicle_store_util.tl:750-756),
--   so ticking a passenger + mail line's two types would hide most of its vehicles.
-- * getVehicleFilterTags is wrapped the same way: the base calls it only when it opens the Replace / Modify store for
--   chosen vehicles; when they are all on one line, that line's cargo arms the pending filter for their carrier and
--   the tags the base returned (the store's filter gets exactly those, vehicle_store_window.tl:2511-2539).
-- * The three handle*Carrier functions are wrapped: a fresh filter (no marker) of the same carrier and tags while a
--   pending filter is valid gets the marker field MARK = the cargo type. table_util.copy is a deep copy, so the
--   marker stays with that store's filter state and its tab changes; another store never gets it. Whenever a marked
--   filter turns from "no cargo filter bar" (the fresh filter, or a locomotive tab) to one with the bar (the
--   default carrier, a wagon / multiple unit / railcar tab) and has no cargo ticked, the line's cargo is ticked.
--   Renders that rebuild the discarded initial filter (useState argument) get it too: harmless.
--
-- Failure handling: both wrappers call the base function outside pcall (its errors stay the base's) and do our part
-- in pcall, logged once per kind. A failing install leaves the base functions as they were.
-- The Rate Matcher's empty-line estimate reads the depot through M.bestDepotQuiet: that read arms nothing.
-- SQPERF section "buy_filter": the depot / vehicles wrappers' cargo lookup (one per click). The handle*Carrier
-- wrappers run on every render of an open store (its useState argument rebuilds the initial filter): two table
-- lookups and showCargoFilters, not timed.

local PREFIX = "[LineManagerPlus] buy filter: "
local MARK = "sqLmpLineCargo"
local PENDING_US = 3000000 -- 3 s from the click to the store's first render

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

local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local M = { MARK = MARK, PENDING_US = PENDING_US }

local clock
local function nowUs()
	-- api.type.Clock: wall clock in microseconds, safe on every thread (as lmp_stats.lua)
	if not clock then clock = api.type.Clock.new() end
	return clock:getTime()
end

local quiet = 0 -- > 0 while bestDepotQuiet runs: the depot wrapper arms nothing
local pending -- { cargo, carrier, tags, untilUs } after a Buy Vehicles click for a one-cargo line, else nil
local storeUtil, lineUtil, cargoUtil, vehicleUtil -- base modules, set by install

-- Cargo types the line's stops are set to load (Line.Stop.stopConfig.load, index = cargo + 1), sorted.
local function stopLoadTypes(line)
	local L = api.engine.getComponent(line, api.type.ComponentType.LINE)
	if not L or not L.stops then return {} end
	local set, out = {}, {}
	for _i, s in ipairs(L.stops) do
		local load = s.stopConfig and s.stopConfig.load
		if load then
			for k, b in ipairs(load) do
				if b == true and not set[k - 1] then
					set[k - 1] = true
					out[#out + 1] = k - 1
				end
			end
		end
	end
	table.sort(out)
	return out
end

--- The line's single cargo type id, or nil when it carries none or several. The cargo its stops load decides (exactly
--- what the player set, also on a line without vehicles); a line whose stops load nothing falls back to its vehicles'
--- capacity.
function M.lineCargo(line)
	local ok, types = pcall(stopLoadTypes, line)
	if not ok then
		warnOnce("stop loads", types)
		types = {}
	end
	if #types == 0 then
		types = cargoUtil.getSortedProducedCargoTypes({
			lineEntity = line,
			getTendency = true,
			showEmpty = true,
		}, "CAPACITY", nil, nil, true)
	end
	if type(types) ~= "table" or #types ~= 1 then return nil end
	return types[1]
end

local function sameTags(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local armTimed = perf:wrap("buy_filter", function(line, depot)
	pending = nil
	if type(line) ~= "number" or type(depot) ~= "number" or depot < 0 then return end
	local cargo = M.lineCargo(line)
	if cargo == nil then return end
	pending = {
		cargo = cargo,
		carrier = vehicleUtil.getDepotCarrier(depot),
		tags = storeUtil.getDepotFilterTags(depot),
		untilUs = nowUs() + PENDING_US,
	}
end)

--- Our part of the getBestDepotForLine wrapper: arms (or clears) the pending filter.
function M.arm(line, depot)
	local ok, err = pcall(armTimed, line, depot)
	if not ok then
		pending = nil
		warnOnce("line cargo", err)
	end
end

--- lu.getBestDepotForLine(line) for a read (the Rate Matcher's empty-line estimate): the wrapper leaves the pending
--- filter alone, so a store opened soon after doesn't get this line's cargo. Errors pass through.
function M.bestDepotQuiet(lu, line)
	quiet = quiet + 1
	local ok, depot = pcall(lu.getBestDepotForLine, line)
	quiet = quiet - 1
	if not ok then error(depot, 0) end
	return depot
end

local MAX_VEHICLES = 500 -- a Replace / Modify selection larger than this arms nothing

-- The one line every vehicle is on and their one carrier, else nil.
local function lineAndCarrierOf(vehicles)
	if type(vehicles) ~= "table" or #vehicles == 0 or #vehicles > MAX_VEHICLES then return nil end
	local line, carrier
	for _i, v in ipairs(vehicles) do
		local tv = api.engine.getComponent(v, api.type.ComponentType.TRANSPORT_VEHICLE)
		if not tv or type(tv.line) ~= "number" or tv.line < 0 then return nil end
		if line == nil then
			line, carrier = tv.line, tv.carrier
		elseif tv.line ~= line or tv.carrier ~= carrier then
			return nil
		end
	end
	return line, carrier
end

local armVehiclesTimed = perf:wrap("buy_filter", function(vehicles, tags)
	pending = nil
	local line, carrier = lineAndCarrierOf(vehicles)
	if line == nil then return end
	local cargo = M.lineCargo(line)
	if cargo == nil then return end
	pending = { cargo = cargo, carrier = carrier, tags = tags, untilUs = nowUs() + PENDING_US }
end)

--- Our part of the getVehicleFilterTags wrapper (the Replace / Modify store for chosen vehicles: manager_window.tl
--- :5206 / :5257, the vehicle window vehicle.tl:456 / :491): the vehicles' line decides the cargo, as for Buy Vehicles.
function M.armVehicles(vehicles, tags)
	local ok, err = pcall(armVehiclesTimed, vehicles, tags)
	if not ok then
		pending = nil
		warnOnce("vehicles cargo", err)
	end
end

--- Our part of the handle*Carrier wrappers: res is the filter the base returned, hadBar whether the filter passed in
--- already showed the cargo filter bar.
function M.apply(res, hadBar)
	if type(res) ~= "table" then return end
	local cargo = res[MARK]
	if cargo == nil and pending then
		if nowUs() > pending.untilUs then
			pending = nil
		elseif res.carrier == pending.carrier and sameTags(res.filterTags, pending.tags) then
			cargo = pending.cargo
			res[MARK] = cargo
		end
	end
	if cargo == nil or hadBar or not storeUtil.showCargoFilters(res) then return end
	if type(res.cargoFilters) == "table" and next(res.cargoFilters) ~= nil then return end
	res.cargoFilters = { [cargo] = true }
end

local function hadBarOf(filter)
	if type(filter) ~= "table" then return false end
	local ok, bar = pcall(storeUtil.showCargoFilters, filter)
	return ok and bar == true
end

local function wrapHandler(name)
	local orig = storeUtil[name]
	if type(orig) ~= "function" then
		warnOnce("install", "vehicle_store_util." .. name .. " is " .. type(orig))
		return false
	end
	storeUtil[name] = function(filter, ...)
		local hadBar = hadBarOf(filter)
		local res = orig(filter, ...)
		local ok, err = pcall(M.apply, res, hadBar)
		if not ok then warnOnce("filter", err) end
		return res
	end
	return true
end

local installed = false
--- Wraps getBestDepotForLine, getVehicleFilterTags and the three handle*Carrier functions; true when it did (or already had). Never errors.
function M.install()
	if installed then return true end
	local ok, err = pcall(function()
		local su = ug_require "::/gui/line_vehicle_mgmt/vehicle_store_util.tl"
		local lu = ug_require "::/gui/line_vehicle_mgmt/line_util.tl"
		local cu = ug_require "::/gui/main/cargo_util.tl"
		local vu = ug_require "::/gui/line_vehicle_mgmt/vehicle_util.tl"
		local needs = {
			{ su, "showCargoFilters" }, { su, "getDepotFilterTags" }, { su, "handleRailCarrier" },
			{ su, "handleTramCarrier" }, { su, "handleDefaultCarrier" }, { lu, "getBestDepotForLine" },
			{ cu, "getSortedProducedCargoTypes" }, { vu, "getDepotCarrier" },
		}
		for _i, n in ipairs(needs) do
			if type(n[1]) ~= "table" or type(n[1][n[2]]) ~= "function" then
				warnOnce("install", n[2] .. " missing; store filter left as is")
				return
			end
		end
		storeUtil, lineUtil, cargoUtil, vehicleUtil = su, lu, cu, vu
		-- read now, not at load, so other mods' wrappers stay in the chain
		local origDepot = lu.getBestDepotForLine
		lu.getBestDepotForLine = function(line, ...)
			local depot = origDepot(line, ...)
			if quiet == 0 then M.arm(line, depot) end
			return depot
		end
		-- Replace / Modify: optional, Buy Vehicles keeps working without it
		local origTags = su.getVehicleFilterTags
		if type(origTags) == "function" then
			su.getVehicleFilterTags = function(vehicles, ...)
				local tags = origTags(vehicles, ...)
				M.armVehicles(vehicles, tags)
				return tags
			end
		else
			warnOnce("install", "getVehicleFilterTags missing; Replace / Modify store not filtered")
		end
		for _i, name in ipairs({ "handleRailCarrier", "handleTramCarrier", "handleDefaultCarrier" }) do
			wrapHandler(name)
		end
		installed = true
		say("installed")
	end)
	if not ok then warnOnce("install", err) end
	return installed
end

return M
