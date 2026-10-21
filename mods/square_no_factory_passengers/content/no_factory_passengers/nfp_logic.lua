-- No Factory Passengers: pure decision logic (no api.* calls), unit-tested in
-- tests/square_no_factory_passengers/. gui/nfp_patch.script.lua injects the engine lookups.
--
-- Rule (rev 5): a line that can load cargo anywhere is a cargo line, and gets no passengers at any
-- stop. A stop can load cargo when one of its stations is a cargo station with an industry or a
-- warehouse among its cargo catchables. Homes and towns in reach are not considered: passengers
-- stay on only on lines that cannot carry cargo at all (two bus stops, a passenger train line).
--
-- Runs on the GUI thread on every line edit, so every lookup is lazy and short-circuits: catchables
-- are fetched one station at a time, only for cargo stations, each distinct stop once, and the line
-- scan stops at its first cargo stop.

local logic = {}

--- True when any catchable of any station matches pred. catchables(station, cargo) -> list of
-- entity ids (getStationCatchables), fetched one station at a time and stopping at the first match.
-- stationPred (optional) skips stations before their catchables are fetched.
function logic.anyCatchable(stations, catchables, cargo, pred, stationPred)
	for __, station in ipairs(stations) do
		if not stationPred or stationPred(station) then
			for __, entity in ipairs(catchables(station, cargo) or {}) do
				if pred(entity) then
					return true
				end
			end
		end
	end
	return false
end

--- True when a stop with these stations can load cargo: a cargo station (isCargoStation) with a
-- cargo source (isCargoSource: industry or warehouse) among its cargo catchables.
function logic.isCargoStop(stations, catchables, isCargoStation, isCargoSource)
	return logic.anyCatchable(stations, catchables, true, isCargoSource, isCargoStation)
end

--- Decision for a whole line. stops: the station list of each distinct stop of the line, in path
-- order. Returns the index of the first cargo stop, or nil (a passenger-only line: keep passengers).
function logic.findCargoStop(stops, catchables, isCargoStation, isCargoSource)
	for i, stations in ipairs(stops) do
		if logic.isCargoStop(stations, catchables, isCargoStation, isCargoSource) then
			return i
		end
	end
	return nil
end

return logic
