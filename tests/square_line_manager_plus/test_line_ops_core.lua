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

-- Set cargo for all stops ----------------------------------------------------------------------------------------
-- cargo ids: 0 passengers, 1 coal, 2 grain, 3 goods

local P = 0

-- stop facts as line_ops.stopInfos gives them
local function info(flags, input, output, load)
	local function set(list)
		local t = {}
		for _i, c in ipairs(list or {}) do t[c] = true end
		return t
	end
	return { pLoad = flags.p, pUnload = flags.pu, cLoad = flags.c, cUnload = flags.cu, input = set(input),
		output = set(output), load = set(load) }
end

local function cargoStop(g, load, maxLoad)
	return stop(g, nil, { loadMode = "LOAD_IF_AVAILABLE", stopConfig = { load = load, maxLoad = maxLoad,
		forceUnload = true, destroyForConfigChange = false, destroyForRefresh = true } })
end

test("supportsCargo: passengers need a passenger terminal; freight a cargo terminal plus catchment or another stop", function()
	local infos = {
		info({ p = true }),                                   -- bus stop
		info({ pu = true }),                                  -- unload-only passengers
		info({ c = true }, nil, { 1 }),                       -- loading terminal, coal mine in reach
		info({ cu = true }, { 3 }, nil),                      -- unloading terminal, goods consumer in reach
		info({ c = true, cu = true }, nil, nil, { 2 }),       -- loads grain already, nothing in reach
		info({}),                                             -- terminal unknown
	}
	eq(core.supportsCargo(infos, 1, P, P), true)
	eq(core.supportsCargo(infos, 2, P, P), true)
	eq(core.supportsCargo(infos, 3, P, P), false)
	eq(core.supportsCargo(infos, 6, P, P), false)
	eq(core.supportsCargo(infos, 1, 1, P), false, "no freight at a passenger-only terminal")
	eq(core.supportsCargo(infos, 3, 1, P), true, "loading + output stock")
	eq(core.supportsCargo(infos, 4, 1, P), false, "unloading terminal, coal not an input")
	eq(core.supportsCargo(infos, 4, 3, P), true, "unloading + input stock")
	eq(core.supportsCargo(infos, 3, 3, P), false, "loading terminal: an input stock alone doesn't count")
	eq(core.supportsCargo(infos, 3, 2, P), true, "another stop loads grain")
	eq(core.supportsCargo(infos, 5, 2, P), false, "its own load doesn't count")
	eq(core.supportsCargo(infos, 9, 2, P), false, "no such stop")
end)

test("cargoChoices: only supported types, passengers first then order; counts supported and done stops", function()
	local infos = {
		info({ p = true, c = true }, nil, { 1, 2 }, { 0 }),
		info({ p = true, c = true }, nil, { 2 }, { 0, 2 }),
		info({ c = true }, nil, { 2 }, { 2 }),
	}
	local types = { { id = 2, order = 10 }, { id = 1, order = 20 }, { id = 3, order = 5 }, { id = 0, order = 99 } }
	local choices = core.cargoChoices(infos, types, P)
	eq(#choices, 3, "goods: no stop takes it")
	eq(choices[1], { id = 0, order = 99, supported = 2, done = 1 })
	eq(choices[2], { id = 2, order = 10, supported = 3, done = 1 })
	eq(choices[3], { id = 1, order = 20, supported = 1, done = 0 }, "coal: only stop 1 has it in reach")
end)

test("loadingStops counts stops with any load", function()
	eq(core.loadingStops({ info({}, nil, nil, { 1 }), info({}), info({}, nil, nil, { 0, 3 }) }), 2)
	eq(core.loadingStops({}), 0)
end)

test("setAllStopsCargo: supported stops load only the cargo, the others stay; sizing, flags and maxLoad kept", function()
	local snap = { customFilters = false, reservationPriority = 3, stops = {
		cargoStop(1, { true, false, true }, { 1, 0.5, 0.25 }),
		cargoStop(2, { false, true }, { 0.8 }),
		cargoStop(3, { false, false, true }, { 1, 1, 1 }),
	} }
	local before = core.copy(snap)
	local new, changed = core.setAllStopsCargo(snap, 2, function(k) return k ~= 2 end, 4)
	eq(snap, before, "input unchanged")
	eq(changed, 1, "stop 3 already loads only grain")
	eq(new.customFilters, true)
	eq(new.reservationPriority, 3)
	eq(new.stops[1].stopConfig.load, { false, false, true, false })
	eq(new.stops[1].stopConfig.maxLoad, { 1, 0.5, 0.25, 1 }, "kept, padded with 100 %")
	eq(new.stops[1].stopConfig.forceUnload, true)
	eq(new.stops[1].stopConfig.destroyForConfigChange, false)
	eq(new.stops[1].stopConfig.destroyForRefresh, true)
	eq(new.stops[1].loadMode, "LOAD_IF_AVAILABLE")
	eq(new.stops[2], before.stops[2], "unsupported stop untouched")
	eq(new.stops[3].stopConfig.load, { false, false, true, false })
	eq(new.stops[1].waypoints, before.stops[1].waypoints)
end)

test("setAllStopsCargo: passengers, clear all, a longer old list, a missing stopConfig, nothing to change", function()
	local snap = { stops = { cargoStop(1, { false, true, false, false, true }, { 1 }), cargoStop(2, {}, {}) } }
	local new, changed = core.setAllStopsCargo(snap, P, function() return true end, 3)
	eq(changed, 2)
	eq(new.stops[1].stopConfig.load, { true, false, false, false, false }, "the old list's length kept")
	eq(new.stops[2].stopConfig.load, { true, false, false })
	eq(new.stops[2].stopConfig.maxLoad, { 1, 1, 1 })

	local cleared, n = core.setAllStopsCargo(snap, nil, function() error("not asked for clear all") end, 3)
	eq(n, 1, "stop 2 loads nothing already")
	eq(cleared.stops[1].stopConfig.load, { false, false, false, false, false })
	eq(cleared.stops[2].stopConfig.load, { false, false, false })
	eq(cleared.customFilters, true)

	local bare = stop(1)
	bare.stopConfig = nil
	local fromNil = core.setAllStopsCargo({ stops = { bare } }, 1, function() return true end, 2)
	eq(fromNil.stops[1].stopConfig, { load = { false, true }, maxLoad = { 1, 1 }, forceUnload = true,
		destroyForConfigChange = true, destroyForRefresh = true })

	local _same, none = core.setAllStopsCargo(new, P, function() return true end, 3)
	eq(none, 0)
	local _skip, zero = core.setAllStopsCargo(snap, 1, function() return false end, 3)
	eq(zero, 0, "no stop supports it")
end)
