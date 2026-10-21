-- Better Auto Vehicle Renamer: which type letter a vehicle gets. Pure: no api.*, Lua 5.1 syntax. PLAN.md "Types and
-- letters".
--
-- Entry points:
--   Classify.letter(carrier, hasPassengers, isHeli) -> "B" | "T" | "R" | "L" | "S" | "A" | "H" | nil
--       carrier: api.type.enum.Carrier value (ROAD 0, RAIL 1, TRAM 2, AIR 3, WATER 4; console 2026-10-20).
--   Classify.isHeliModel(metadata, path) -> bool: metadata.airVehicle.isHelicopter, else "vehicle/helicopter/" in
--       the model path (api.res.modelRep.getName).
--   Classify.lead(n, isPowered) -> index: the first part with power (loco / power car), else 1. isPowered(i) -> bool.
--   Classify.hasPassengers(metadata): the model carries passengers (bus vs truck; any PASSENGERS capacity).

local M = {}

M.ROAD, M.RAIL, M.TRAM, M.AIR, M.WATER = 0, 1, 2, 3, 4
M.LETTERS = { "B", "T", "R", "L", "S", "A", "H" } -- = Settings.LETTERS
M.MAX_PARTS = 256 -- loop cap on a consist's parts

function M.letter(carrier, hasPassengers, isHeli)
	if carrier == M.ROAD then return hasPassengers and "B" or "T" end
	if carrier == M.RAIL then return "L" end
	if carrier == M.TRAM then return "R" end
	if carrier == M.WATER then return "S" end
	if carrier == M.AIR then return isHeli and "H" or "A" end
	return nil
end

function M.isHeliModel(metadata, path)
	local av = type(metadata) == "table" and metadata.airVehicle or nil
	if type(av) == "table" and av.isHelicopter ~= nil then return av.isHelicopter == true end
	return type(path) == "string" and string.find(path, "vehicle/helicopter/", 1, true) ~= nil
end

--- The lead part's index (1-based) among n parts.
function M.lead(n, isPowered)
	if type(n) ~= "number" or n < 1 then return 1 end
	if n > M.MAX_PARTS then n = M.MAX_PARTS end
	for i = 1, n do
		if isPowered(i) then return i end
	end
	return 1
end

--- Whether a model carries passengers: any metadata.transportVehicle.compartments[i].loadConfigs[j].cargoEntry with a
--- capacity > 0 whose cargoTypeSet includes the PASSENGERS class or cargo type (base `.mdl` layout, tealdef type.d.tl
--- TransportVehicle). Takes plain tables; the game script hands it a converted copy (api.res may give userdata).
local function listHas(list, want)
	if type(list) ~= "table" then return false end
	for i = 1, math.min(#list, M.MAX_PARTS) do
		if list[i] == want then return true end
	end
	return false
end

function M.hasPassengers(metadata)
	local tv = type(metadata) == "table" and metadata.transportVehicle or nil
	local comps = type(tv) == "table" and tv.compartments or nil
	if type(comps) ~= "table" then return false end
	for i = 1, math.min(#comps, M.MAX_PARTS) do
		local lcs = type(comps[i]) == "table" and comps[i].loadConfigs or nil
		if type(lcs) == "table" then
			for j = 1, math.min(#lcs, M.MAX_PARTS) do
				local ce = type(lcs[j]) == "table" and lcs[j].cargoEntry or nil
				local set = type(ce) == "table" and ce.cargoTypeSet or nil
				if type(set) == "table" and (tonumber(ce.capacity) or 0) > 0
					and (listHas(set.cargoClassesIncluded, "PASSENGERS") or listHas(set.cargoTypesIncluded, "PASSENGERS")) then
					return true
				end
			end
		end
	end
	return false
end

return M
