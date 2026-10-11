-- line_ops_core.lua (Duplicate / Reverse line, pure): reverse order with stop 1 first, waypoint migration, per-stop
-- settings stay with their stop, terminal re-pick (with and without an answer, alternatives), copy names, guards.

local core

before_each(function()
	reset_modules()
	core = ug_require "square_line_manager_plus::/line_manager_plus/line_ops_core.lua"
end)

local function wp(tag) return { tag = tag, pos = { x = tag, y = 0, z = 0 } } end

-- stop for group g; waypoints after it given as tags
local function stop(g, wps, extra)
	local w = {}
	for i, t in ipairs(wps or {}) do w[i] = wp(t) end
	local s = { stationGroup = g, station = 0, terminal = g % 3, alternativeTerminals = {}, loadMode = 0,
		minWaitingTime = g, maxWaitingTime = 600, maxAdditionalWaitingTime = 30, waypoints = w,
		stopConfig = { load = { g == 2 }, maxLoad = { g }, forceUnload = false, destroyForConfigChange = false,
			destroyForRefresh = false } }
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

local function groups(snap)
	local out = {}
	for i, s in ipairs(snap.stops) do out[i] = s.stationGroup end
	return out
end

local function tags(s)
	local out = {}
	for i, w in ipairs(s.waypoints) do out[i] = w.tag end
	return out
end

test("reverseOrder: stop 1 stays first, the rest backwards", function()
	eq(core.reverseOrder(0), {})
	eq(core.reverseOrder(1), { 1 })
	eq(core.reverseOrder(2), { 1, 2 })
	eq(core.reverseOrder(3), { 1, 3, 2 })
	eq(core.reverseOrder(5), { 1, 5, 4, 3, 2 })
end)

test("reverse: 3 and n stops keep stop 1 first; the input stays unchanged", function()
	local snap = { stops = { stop(1), stop(2), stop(3) }, customFilters = false, reservationPriority = 2 }
	local before = core.copy(snap)
	local r = core.reverse(snap)
	eq(groups(r), { 1, 3, 2 })
	eq(snap, before)
	eq(r.reservationPriority, 2)
	eq(r.customFilters, false)
	local big = { stops = {} }
	for i = 1, 7 do big.stops[i] = stop(i) end
	eq(groups(core.reverse(big)), { 1, 7, 6, 5, 4, 3, 2 })
end)

test("reverse: every stop keeps its own settings", function()
	local snap = { stops = { stop(1), stop(2, nil, { alternativeTerminals = { { station = 0, terminal = 4 } } }),
		stop(3, nil, { loadMode = 2 }) } }
	local r = core.reverse(snap)
	for _i, s in ipairs(r.stops) do
		local orig = snap.stops[s.stationGroup]
		eq(s.terminal, orig.terminal)
		eq(s.minWaitingTime, orig.minWaitingTime)
		eq(s.loadMode, orig.loadMode)
		eq(s.stopConfig, orig.stopConfig)
		eq(s.alternativeTerminals, orig.alternativeTerminals)
		ok(s.stopConfig ~= orig.stopConfig, "a copy, not the same table")
	end
end)

test("reverse: waypoints move with their segment, reversed (first and last segment too)", function()
	-- s1 -[10,11]-> s2 -[20]-> s3 -[30,31,32]-> back to s1
	local snap = { stops = { stop(1, { 10, 11 }), stop(2, { 20 }), stop(3, { 30, 31, 32 }) } }
	local r = core.reverse(snap)
	-- new: s1 -> s3 (old s3 -> s1 reversed), s3 -> s2 (old s2 -> s3 reversed), s2 -> s1 (old s1 -> s2 reversed)
	eq(groups(r), { 1, 3, 2 })
	eq(tags(r.stops[1]), { 32, 31, 30 })
	eq(tags(r.stops[2]), { 20 })
	eq(tags(r.stops[3]), { 11, 10 })
	-- the waypoint's data travels with it
	eq(r.stops[1].waypoints[1].pos, { x = 32, y = 0, z = 0 })
end)

test("reverse: 2 stops swap only the waypoint lists; empty lists stay empty", function()
	local r = core.reverse({ stops = { stop(1, { 1, 2 }), stop(2, {}) } })
	eq(groups(r), { 1, 2 })
	eq(tags(r.stops[1]), {})
	eq(tags(r.stops[2]), { 2, 1 })
	local plain = core.reverse({ stops = { stop(1), stop(2), stop(3), stop(4) } })
	for _i, s in ipairs(plain.stops) do eq(s.waypoints, {}) end
end)

test("reverse twice restores the line", function()
	local snap = { stops = { stop(1, { 10 }), stop(2, { 20, 21 }), stop(3), stop(4, { 40 }) } }
	eq(core.reverse(core.reverse(snap)), snap)
end)

test("applyAssignment: new terminals where the engine answers, the player's where it doesn't", function()
	local snap = { stops = { stop(1), stop(2), stop(3) } }
	local n = core.applyAssignment(snap, {
		{ station = 1, terminal = 5 },
		{ station = -1, terminal = -1 },
		-- no answer for stop 3
	})
	eq(n, 1)
	eq({ snap.stops[1].station, snap.stops[1].terminal }, { 1, 5 })
	eq({ snap.stops[2].station, snap.stops[2].terminal }, { 0, 2 })
	eq({ snap.stops[3].station, snap.stops[3].terminal }, { 0, 0 })
	eq(core.applyAssignment(snap, nil), 0)
	eq(core.applyAssignment(snap, { { station = 1, terminal = 5 } }), 0, "same terminal: not counted")
end)

test("applyAssignment: a new terminal taken from the alternatives swaps with the old main one", function()
	local s = stop(1, nil, { alternativeTerminals = { { station = 0, terminal = 7 }, { station = 1, terminal = 2 } } })
	local snap = { stops = { s } }
	core.applyAssignment(snap, { { station = 1, terminal = 2 } })
	eq({ s.station, s.terminal }, { 1, 2 })
	eq(s.alternativeTerminals, { { station = 0, terminal = 7 }, { station = 0, terminal = 1 } })
end)

test("applyAssignment reads userdata-like vectors through # and [i]", function()
	local snap = { stops = { stop(1), stop(2) } }
	local vec = setmetatable({}, {
		__len = function() return 2 end,
		__index = function(_t, k) return ({ { station = 0, terminal = 9 }, { station = 0, terminal = 8 } })[k] end,
	})
	eq(core.applyAssignment(snap, vec), 2)
	eq(snap.stops[2].terminal, 8)
end)

test("copyName: plain copy, then the smallest free number; a fake language's placeholder order", function()
	local one, many = "{name} (copy)", "{name} (copy {n})"
	eq(core.copyName("Bus 1", {}, one, many), "Bus 1 (copy)")
	eq(core.copyName("Bus 1", { ["Bus 1 (copy)"] = true }, one, many), "Bus 1 (copy 2)")
	eq(core.copyName("Bus 1", { ["Bus 1 (copy)"] = true, ["Bus 1 (copy 2)"] = true, ["Bus 1 (copy 4)"] = true },
		one, many), "Bus 1 (copy 3)")
	eq(core.copyName("A", { ["kopia A"] = true }, "kopia {name}", "kopia {n} {name}"), "kopia 2 A")
	eq(core.copyName("100% line", {}, one, many), "100% line (copy)")
	-- all numbers taken: the plain copy name (as the base editor falls back)
	eq(core.copyName("X", { ["X (copy)"] = true, ["X (copy 2)"] = true }, one, many, 2), "X (copy)")
end)

test("missingCount and blockReason", function()
	local counts = { [1] = 1, [2] = 2 } -- group 3 is gone
	local stops = { stop(1), stop(2, nil, { station = 1 }), stop(2, nil, { station = 2 }), stop(3) }
	eq(core.missingCount(stops, function(g) return counts[g] end), 2)
	eq(core.missingCount({}, function() return nil end), 0)
	eq(core.missingCount(nil, function() return nil end), 0)
	eq(core.blockReason(0, 0), "The line needs at least 2 stops.")
	eq(core.blockReason(1, 0), "The line needs at least 2 stops.")
	eq(core.blockReason(3, 1), "A station of this line no longer exists.")
	eq(core.blockReason(2, 0), nil)
end)
