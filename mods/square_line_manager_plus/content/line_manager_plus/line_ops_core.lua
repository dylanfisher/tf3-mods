-- Line Manager Plus, Duplicate / Reverse line (PLAN.md feature 4): pure functions, no game state.
-- Unit-tested in tests/square_line_manager_plus/test_line_ops_core.lua.
--
-- Works on undo_core snapshots (plain copies of an Engine.Component.Line, see undo_core.lua's header):
--   snap = { stops = { { stationGroup, station, terminal, alternativeTerminals, loadMode, waiting times,
--                        waypoints = { ... }, stopConfig } }, customFilters, reservationPriority }
-- A stop's `waypoints` are the waypoints AFTER that stop, on the way to the next one (the last stop's lead back to
-- stop 1): api/tealdef/api/engine.d.tl:542 "all waypoints after the stop", and base line_util.tl:128-160 builds
-- them that way from the editor's path.

local undo_core = ug_require "square_line_manager_plus::/line_manager_plus/undo_core.lua"

local M = {}

M.fill = undo_core.fill

-- deep copy of a snapshot value (plain tables; userdata such as loadMode or customFilters are kept as they are)
local function copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = copy(x) end
	return out
end
M.copy = copy

local function reversedList(list)
	local out = {}
	local n = #(list or {})
	for i = 1, n do out[i] = copy(list[n + 1 - i]) end
	return out
end

--- The stop order of a reversed line with n stops: stop 1 stays first, the rest run backwards:
--- { 1, n, n-1, ..., 2 }. order[j] = index of the old stop at new position j.
function M.reverseOrder(n)
	local order = {}
	if n < 1 then return order end
	order[1] = 1
	for j = 2, n do order[j] = n + 2 - j end
	return order
end

--- The line driven the other way round, as a new snapshot (`snap` is not changed). Stop 1 stays first (user decision
--- D4): [s1, s2, ..., sn] becomes [s1, sn, ..., s2]. Every stop keeps its own settings (terminal, alternatives, load
--- mode, waiting times, cargo config). Waypoints follow their segment: the old segment s(i) -> s(i+1) is now driven
--- s(i+1) -> s(i), so its waypoint list (stored on s(i)) moves to s(i+1), in reverse order. In the new order that is:
--- new stop 1 (s1) gets the old s(n)'s list (the segment back to s1), new stop j >= 2 (s(n+2-j)) gets old s(n+1-j)'s.
function M.reverse(snap)
	local stops = snap.stops or {}
	local n = #stops
	local out = {}
	for j, i in ipairs(M.reverseOrder(n)) do
		local s = copy(stops[i])
		-- the waypoints of the segment that now leaves this stop: the old segment that arrived at it
		local from = (j == 1) and n or (n + 1 - j)
		s.waypoints = reversedList(stops[from] and stops[from].waypoints)
		out[j] = s
	end
	local result = copy(snap)
	result.stops = out
	return result
end

--- Applies the engine's terminal choice (lineSystem.getBestLineAssignment, one StationTerminal per stop, 1-based,
--- read with # and [k]) to `snap` in place (user decision D5). A stop whose answer is missing or negative keeps the
--- player's terminal. When the new terminal was one of the stop's alternative terminals, that alternative becomes the
--- old main terminal, so the stop still offers the same set of terminals. Returns the number of stops changed.
function M.applyAssignment(snap, assignment)
	local changed = 0
	if assignment == nil then return 0 end
	local n = #assignment
	for k, s in ipairs(snap.stops or {}) do
		local a = k <= n and assignment[k] or nil
		local station, terminal = a and a.station, a and a.terminal
		if type(station) == "number" and type(terminal) == "number" and station >= 0 and terminal >= 0
			and (station ~= s.station or terminal ~= s.terminal) then
			for _i, alt in ipairs(s.alternativeTerminals or {}) do
				if alt.station == station and alt.terminal == terminal then
					alt.station, alt.terminal = s.station, s.terminal
					break
				end
			end
			s.station, s.terminal = station, terminal
			changed = changed + 1
		end
	end
	return changed
end

--- Name for a copy of a line called `name`: fill(fmtOne, {name}) ("{name} (copy)"), or when a line already has that
--- name fill(fmtN, {name, n}) ("{name} (copy {n})") with the smallest free n >= 2 (up to `limit`, default 99; past it
--- the plain copy name, as the base editor falls back to "New Line" after 999 tries, line_util.tl:66-80).
--- `taken` is a set of the names in use { [name] = true }.
function M.copyName(name, taken, fmtOne, fmtN, limit)
	taken = taken or {}
	local first = M.fill(fmtOne, { name = name })
	if not taken[first] then return first end
	for n = 2, limit or 99 do
		local candidate = M.fill(fmtN, { name = name, n = n })
		if not taken[candidate] then return candidate end
	end
	return first
end

--- Number of stops whose station no longer exists. `stops` is a snapshot's list or the live component's vector (read
--- with # and [i]); stationCount(group) returns the number of stations in the group, or nil when the group is gone.
function M.missingCount(stops, stationCount)
	local missing = 0
	for i = 1, #(stops or {}) do
		local s = stops[i]
		local n = stationCount(s.stationGroup)
		if n == nil or s.station == nil or s.station < 0 or s.station >= n then missing = missing + 1 end
	end
	return missing
end

--- Why an action can't run on a line with `stopCount` stops of which `missing` have no station any more, or nil.
--- Returns the English key of the reason (the caller translates it).
function M.blockReason(stopCount, missing)
	if (stopCount or 0) < 2 then return "The line needs at least 2 stops." end -- i18n: keys
	if (missing or 0) > 0 then return "A station of this line no longer exists." end -- i18n: keys
	return nil
end

return M
