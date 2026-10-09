-- No Factory Passengers: pure decision logic (no api.* calls), unit-tested in
-- tests/square_no_factory_passengers/. gui/nfp_patch.script.lua injects the engine lookups.
--
-- Runs on the GUI thread on every line edit, so every lookup is lazy and short-circuits: catchables
-- are fetched one station at a time, and passenger catchables only once an industry is in reach.

local logic = {}

--- True when any catchable of any station matches pred. catchables(station, cargo) -> list of
-- entity ids (getStationCatchables), fetched one station at a time and stopping at the first match.
function logic.anyCatchable(stations, catchables, cargo, pred)
	for __, station in ipairs(stations) do
		for __, entity in ipairs(catchables(station, cargo) or {}) do
			if pred(entity) then
				return true
			end
		end
	end
	return false
end

--- Decision for one station group: clear passengers when an industry is among the cargo
-- catchables AND no town building is among the passenger catchables. Passenger catchables include
-- the industry's own workplaces (api/engine/system.d.tl:445-448), hence isHome rather than the base
-- "non-empty" test (line_util.tl:569-572). Returns clear, industry (booleans).
function logic.decide(stations, catchables, isIndustry, isHome)
	if not logic.anyCatchable(stations, catchables, true, isIndustry) then
		return false, false
	end
	return not logic.anyCatchable(stations, catchables, false, isHome), true
end

--- Decision for a whole line. groups: the station list of each distinct station group among the
-- line's passenger stops. A group is cleared when decide clears it (industry, no town buildings)
-- or, once the line has such an industry-only stop, when it reaches no town buildings either (a
-- dock or other transfer point on a factory line). Passenger catchables of groups without an
-- industry are fetched only in that case. Returns clear, industry (arrays of booleans by index).
function logic.decideLine(groups, catchables, isIndustry, isHome)
	local clear, industry = {}, {}
	local industryOnly = false
	for i, stations in ipairs(groups) do
		clear[i], industry[i] = logic.decide(stations, catchables, isIndustry, isHome)
		industryOnly = industryOnly or clear[i]
	end
	if industryOnly then
		for i, stations in ipairs(groups) do
			if not industry[i] then
				clear[i] = not logic.anyCatchable(stations, catchables, false, isHome)
			end
		end
	end
	return clear, industry
end

return logic
