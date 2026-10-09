-- No Factory Passengers: pure decision logic (no api.* calls), unit-tested in
-- tests/square_no_factory_passengers/. gui/nfp_patch.script.lua injects the engine lookups.
--
-- Runs on the GUI thread on every line edit, so every lookup is lazy and short-circuits: catchables
-- are fetched one station at a time, and homes are tested first. A town stop (the common case)
-- stops at its first town building, without scanning its cargo catchables (every town building in
-- reach) for an industry; cargo catchables are fetched only for groups that reach no homes.

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
-- "non-empty" test (line_util.tl:569-572). Homes are tested first: with a home in reach the stop
-- keeps passengers whatever else it reaches, so the industry test is skipped (industry is then
-- reported false). Returns clear, industry, home (booleans).
function logic.decide(stations, catchables, isIndustry, isHome)
	if logic.anyCatchable(stations, catchables, false, isHome) then
		return false, false, true
	end
	local industry = logic.anyCatchable(stations, catchables, true, isIndustry)
	return industry, industry, false
end

--- Decision for a whole line. groups: the station list of each distinct station group among the
-- line's passenger stops. A group is cleared when decide clears it (industry, no town buildings)
-- or, once the line has such an industry-only stop, when it reaches no town buildings either (a
-- dock or other transfer point on a factory line). Each group's catchables are fetched at most once
-- per kind. Returns clear, industry (arrays of booleans by index; industry is true only for a group
-- that reaches an industry and no homes).
function logic.decideLine(groups, catchables, isIndustry, isHome)
	local clear, industry, home = {}, {}, {}
	local industryOnly = false
	for i, stations in ipairs(groups) do
		clear[i], industry[i], home[i] = logic.decide(stations, catchables, isIndustry, isHome)
		industryOnly = industryOnly or clear[i]
	end
	if industryOnly then
		for i in ipairs(groups) do
			clear[i] = not home[i]
		end
	end
	return clear, industry
end

return logic
