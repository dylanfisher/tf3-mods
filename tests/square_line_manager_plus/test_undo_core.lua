-- undo_core.lua (Line Manager Plus, from square_line_revert's line_revert_core.lua): snapshot / equal / diffSummary / missingStops / build on fake LINE components.
-- Shapes: engine.d.tl:492-557 (Line, Stop, StopConfig), type.d.tl:1009 (StationTerminal), :1243 (Waypoint).

local core = ug_require "square_line_manager_plus::/line_manager_plus/undo_core.lua"

local function stop(group, extra)
	local s = {
		stationGroup = group, station = 0, terminal = 1,
		alternativeTerminals = { { station = 0, terminal = 2 } },
		loadMode = 0,
		minWaitingTime = 0, maxWaitingTime = 600, maxAdditionalWaitingTime = 30,
		waypoints = {},
		stopConfig = { load = { true, false }, maxLoad = { 1, 0.5 }, forceUnload = false,
			destroyForConfigChange = false, destroyForRefresh = true },
	}
	for k, v in pairs(extra or {}) do s[k] = v end
	return s
end

local function line(stops, extra)
	local l = { stops = stops, customFilters = false, reservationPriority = 0, vehicleInfo = { ignored = true } }
	for k, v in pairs(extra or {}) do l[k] = v end
	return l
end

local function wpEdge(tag, entity, index, param)
	return { tag = tag, edgePos = { edgeId = { entity = entity, index = index }, param = param } }
end

local function wpPos(tag, x, y, z)
	return { tag = tag, pos = { x = x, y = y, z = z } }
end

-- snapshot ------------------------------------------------------------------------------------------------------

test("snapshot copies every stop field", function()
	local comp = line({ stop(10, { waypoints = { wpEdge(3, 77, 4, 0.25), wpPos(4, 1, 2, 3) } }) },
		{ customFilters = true, reservationPriority = 2 })
	local s = core.snapshot(comp)
	eq(s, {
		customFilters = true, reservationPriority = 2,
		stops = { {
			stationGroup = 10, station = 0, terminal = 1,
			alternativeTerminals = { { station = 0, terminal = 2 } },
			loadMode = 0, minWaitingTime = 0, maxWaitingTime = 600, maxAdditionalWaitingTime = 30,
			waypoints = {
				{ tag = 3, edgePos = { entity = 77, index = 4, param = 0.25 } },
				{ tag = 4, pos = { x = 1, y = 2, z = 3 } },
			},
			stopConfig = { load = { true, false }, maxLoad = { 1, 0.5 }, forceUnload = false,
				destroyForConfigChange = false, destroyForRefresh = true },
		} },
	})
end)

test("snapshot is a deep copy: later edits to the component don't reach it", function()
	local comp = line({ stop(10, { waypoints = { wpEdge(1, 5, 6, 0.5) } }), stop(20) })
	local s = core.snapshot(comp)
	comp.stops[1].alternativeTerminals[1].terminal = 9
	comp.stops[1].stopConfig.load[1] = false
	comp.stops[1].waypoints[1].edgePos.param = 0.9
	comp.stops[2] = nil
	eq(#s.stops, 2)
	eq(s.stops[1].alternativeTerminals[1].terminal, 2)
	eq(s.stops[1].stopConfig.load[1], true)
	eq(s.stops[1].waypoints[1].edgePos.param, 0.5)
end)

test("snapshot reads userdata-like vectors through # and [i]", function()
	local backing = { stop(10), stop(20) }
	local vec = setmetatable({}, { __len = function() return #backing end, __index = function(_t, i) return backing[i] end })
	local s = core.snapshot({ stops = vec, customFilters = false, reservationPriority = 0 })
	eq(#s.stops, 2)
	eq(s.stops[2].stationGroup, 20)
end)

test("snapshot of nil is nil; missing stopConfig stays nil", function()
	eq(core.snapshot(nil), nil)
	local comp = line({ stop(10) })
	comp.stops[1].stopConfig = nil
	eq(core.snapshot(comp).stops[1].stopConfig, nil)
end)

-- equal / diffSummary -------------------------------------------------------------------------------------------

local function snap(stops, extra) return core.snapshot(line(stops, extra)) end

test("equal snapshots: equal and empty diff", function()
	local a = snap({ stop(10), stop(20) })
	local b = snap({ stop(10), stop(20) })
	ok(core.equal(a, b))
	eq(core.diffSummary(a, b), "")
end)

test("removed stop", function()
	local a = snap({ stop(10), stop(20), stop(30) })
	local b = snap({ stop(10), stop(30) })
	ok(not core.equal(a, b))
	eq(core.diffSummary(a, b), "1 stop removed")
end)

test("added stops", function()
	local a = snap({ stop(10) })
	local b = snap({ stop(10), stop(20), stop(10) })
	eq(core.diffSummary(a, b), "2 stops added")
end)

test("removed and added", function()
	eq(core.diffSummary(snap({ stop(10), stop(20) }), snap({ stop(10), stop(30) })), "1 stop removed, 1 stop added")
end)

test("reordered", function()
	eq(core.diffSummary(snap({ stop(10), stop(20), stop(30) }), snap({ stop(30), stop(20), stop(10) })), "stops reordered")
end)

test("changed stop settings", function()
	local a = snap({ stop(10), stop(20), stop(30) })
	local b = snap({ stop(10, { terminal = 3 }), stop(20, { loadMode = 1 }), stop(30) })
	eq(core.diffSummary(a, b), "2 stops changed")
	eq(core.diffSummary(a, snap({ stop(10), stop(20), stop(30, { maxWaitingTime = 120 }) })), "1 stop changed")
end)

test("waypoint, alternative terminal and cargo changes count as changed", function()
	local a = snap({ stop(10) })
	eq(core.diffSummary(a, snap({ stop(10, { waypoints = { wpEdge(1, 5, 6, 0.5) } }) })), "1 stop changed")
	eq(core.diffSummary(a, snap({ stop(10, { alternativeTerminals = {} }) })), "1 stop changed")
	local cfg = stop(10).stopConfig
	cfg.maxLoad = { 1, 0.75 }
	eq(core.diffSummary(a, snap({ stop(10, { stopConfig = cfg }) })), "1 stop changed")
end)

test("line settings", function()
	local a = snap({ stop(10) })
	eq(core.diffSummary(a, snap({ stop(10) }, { reservationPriority = 1 })), "line settings changed")
	eq(core.diffSummary(a, snap({ stop(10) }, { customFilters = true })), "line settings changed")
end)

test("fill: named placeholders, any order, missing ones kept, % in values", function()
	eq(core.fill("{b} then {a}", { a = 1, b = "x" }), "x then 1")
	eq(core.fill("{n} and {gone}", { n = 2 }), "2 and {gone}")
	eq(core.fill("{diff}", { diff = "50%" }), "50%")
end)

test("diffSummary translates each phrase and the list separator", function()
	local T = {
		["{list}, {item}"] = "{list}、{item}",
		["{n} stops removed"] = "removed: {n}",
		["1 stop added"] = "one added",
	}
	local orig = _
	set_global("_", function(s) return T[s] or s end)
	local okRun, err = pcall(function()
		eq(core.diffSummary(snap({ stop(10), stop(20), stop(30) }), snap({ stop(10), stop(40) })), "removed: 2、one added")
	end)
	set_global("_", orig)
	if not okRun then error(err, 0) end
end)

test("equal: extra or missing keys differ", function()
	ok(core.equal({ a = 1 }, { a = 1 }))
	ok(not core.equal({ a = 1 }, { a = 1, b = 2 }))
	ok(not core.equal({ a = 1, b = 2 }, { a = 1 }))
	ok(not core.equal(nil, {}))
end)

-- missingStops --------------------------------------------------------------------------------------------------

test("missingStops: gone group and gone station index", function()
	local s = snap({ stop(10), stop(20, { station = 2 }), stop(30) })
	local counts = { [10] = 1, [20] = 2 } -- 30 gone, 20 has stations 0..1 only
	local missing = core.missingStops(s, function(g) return counts[g] end)
	eq(missing, { { index = 2, stationGroup = 20, station = 2 }, { index = 3, stationGroup = 30, station = 0 } })
	eq(core.missingStops(s, function() return 5 end), {})
end)

-- build ---------------------------------------------------------------------------------------------------------

-- Fake api.type: every constructor tags its object, so the test can tell which one built what.
local function fakeTypes(log)
	local function ctor(name)
		return { new = function(...)
			log[#log + 1] = name
			local o = { _type = name }
			if name == "StationTerminal" then o.station, o.terminal = ... end
			if name == "EdgeId" then o.entity, o.index = ... end
			if name == "Vec3f" then o.x, o.y, o.z = ... end
			if name == "Waypoint" then o.tag = -1 end
			return o
		end }
	end
	local Line = ctor("Line")
	Line.Stop = ctor("Stop")
	Line.StopConfig = ctor("StopConfig")
	return {
		Line = Line,
		StationTerminal = ctor("StationTerminal"),
		Waypoint = ctor("Waypoint"),
		EdgePos = ctor("EdgePos"),
		EdgeId = ctor("EdgeId"),
		Vec3f = ctor("Vec3f"),
	}
end

test("build round-trips: snapshot(build(s)) == s", function()
	local s = snap({
		stop(10, { waypoints = { wpEdge(3, 77, 4, 0.25) } }),
		stop(20, { loadMode = 2, alternativeTerminals = { { station = 1, terminal = 0 }, { station = 1, terminal = 1 } } }),
		stop(30, { waypoints = { wpPos(7, 1.5, -2, 0) } }),
	}, { customFilters = true, reservationPriority = 3 })
	local comp = core.build(s, fakeTypes({}))
	ok(core.equal(core.snapshot(comp), s))
	eq(comp._type, "Line")
	eq(comp.stops[1]._type, "Stop")
	eq(comp.stops[1].stopConfig._type, "StopConfig")
	eq(comp.stops[2].alternativeTerminals[2]._type, "StationTerminal")
	eq(comp.stops[1].waypoints[1]._type, "Waypoint")
	eq(comp.stops[1].waypoints[1].edgePos._type, "EdgePos")
	eq(comp.stops[1].waypoints[1].edgePos.edgeId._type, "EdgeId")
	eq(comp.stops[1].waypoints[1].pos, nil)
	eq(comp.stops[3].waypoints[1].pos._type, "Vec3f")
	eq(comp.stops[3].waypoints[1].edgePos, nil)
end)

test("build copies lists, so the snapshot survives edits of the built component", function()
	local s = snap({ stop(10) })
	local comp = core.build(s, fakeTypes({}))
	comp.stops[1].stopConfig.load[1] = false
	eq(s.stops[1].stopConfig.load[1], true)
	local again = core.build(s, fakeTypes({}))
	eq(again.stops[1].stopConfig.load[1], true)
end)

test("build of an empty line", function()
	local comp = core.build(snap({}), fakeTypes({}))
	eq(comp.stops, {})
end)

-- undo history ---------------------------------------------------------------------------------------------------

local function hs(...) -- snapshots from lists of station groups
	local out = {}
	for i, groups in ipairs({ ... }) do
		local stops = {}
		for j, g in ipairs(groups) do stops[j] = stop(g) end
		out[i] = snap(stops)
	end
	return (table.unpack or unpack)(out)
end

test("history: observe pushes each change once, ignores repeats", function()
	local a, b, c = hs({ 10, 20 }, { 10 }, { 10, 30 })
	local h = core.newHistory(a)
	eq(core.canUndo(h), false)
	eq(core.observe(h, hs({ 10, 20 })), false)
	eq(core.observe(h, b), true)
	eq(core.observe(h, hs({ 10 })), false)
	eq(core.observe(h, c), true)
	eq(#h.states, 3)
	eq(core.changeCount(h), 2)
	ok(core.canUndo(h))
	eq(core.observe(h, nil), false)
end)

test("history: undo pops one step and our own result isn't recorded", function()
	local a, b, c = hs({ 10, 20 }, { 10 }, { 10, 30 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	local target, token = core.beginUndo(h, c, false)
	ok(core.equal(target, b))
	eq(#h.states, 2)
	eq(core.canUndo(h), false) -- in flight
	-- engine not applied yet: the old state is ignored
	eq(core.observe(h, c), false)
	eq(#h.states, 2)
	core.finishUndo(h, token, true)
	-- applied: matches expected, not pushed
	eq(core.observe(h, b), false)
	eq(#h.states, 2)
	eq(h.expected, nil)
	ok(core.canUndo(h))
	-- the next undo goes back to the start
	target = core.beginUndo(h, b, false)
	ok(core.equal(target, a))
	eq(#h.states, 1)
	eq(core.changeCount(h), 0)
end)

test("history: a failed command puts the popped entry back", function()
	local a, b, c = hs({ 10, 20 }, { 10 }, { 10, 30 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	local _t, token = core.beginUndo(h, c, false)
	core.finishUndo(h, token, false)
	eq(#h.states, 3)
	ok(core.equal(h.states[3], c))
	eq(h.expected, nil)
	ok(core.canUndo(h))
	eq(core.observe(h, c), false)
	-- a stale token (already finished) is ignored
	core.finishUndo(h, token, false)
	eq(#h.states, 3)
end)

test("history: a failed revert all restores the whole history", function()
	local a, b, c = hs({ 10, 20 }, { 10 }, { 10, 30 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	local target, token = core.beginUndo(h, c, true)
	ok(core.equal(target, a))
	eq(#h.states, 1)
	core.finishUndo(h, token, false)
	eq(#h.states, 3)
	eq(core.changeCount(h), 2)
end)

test("history: a user edit before the engine applies the undo is recorded normally", function()
	local a, b, c, d = hs({ 10, 20 }, { 10 }, { 10, 30 }, { 40 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	local _t, token = core.beginUndo(h, c, false)
	eq(core.observe(h, d), true)
	eq(h.expected, nil)
	eq(#h.states, 3)
	ok(core.equal(h.states[3], d))
	-- the undo then fails: the popped entry comes back below the new edit
	core.finishUndo(h, token, false)
	eq(#h.states, 4)
	ok(core.equal(h.states[3], c))
	ok(core.equal(h.states[4], d))
end)

test("history: revert all keeps only the first entry", function()
	local a, b, c = hs({ 10, 20 }, { 10 }, { 10, 30 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	local target, token = core.beginUndo(h, c, true)
	ok(target == a)
	eq(#h.states, 1)
	core.finishUndo(h, token, true)
	eq(core.observe(h, a), false)
	eq(#h.states, 1)
	eq(core.undoTarget(h, true), nil)
	eq(core.undoTarget(h, false), nil)
	eq(core.beginUndo(h, a, false), nil)
end)

test("history: the cap drops the oldest edit but keeps the first entry", function()
	local first = snap({ stop(1) })
	local h = core.newHistory(first)
	for i = 1, 60 do core.observe(h, snap({ stop(1), stop(100 + i) })) end
	eq(#h.states, core.HISTORY_CAP)
	ok(h.states[1] == first)
	eq(h.states[2].stops[2].stationGroup, 100 + 60 - core.HISTORY_CAP + 2)
	eq(h.states[#h.states].stops[2].stationGroup, 160)
	eq(core.changeCount(h), 60)
	ok(core.undoTarget(h, true) == first)
	-- a small cap through the parameter
	local h2 = core.newHistory(first)
	for i = 1, 5 do core.observe(h2, snap({ stop(i + 1) }), 3) end
	eq(#h2.states, 3)
	eq(h2.dropped, 3)
	-- undo down to the first entry resets the dropped count
	core.beginUndo(h2, h2.states[3], false)
	core.beginUndo(h2, h2.states[2], false)
	eq(#h2.states, 1)
	eq(core.changeCount(h2), 0)
end)

-- redo ----------------------------------------------------------------------------------------------------------

test("redo: undo moves the left state onto redo; redo puts it back", function()
	local a, b, c = hs({ 10, 20 }, { 10 }, { 10, 30 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	eq(core.canRedo(h), false)
	eq(core.beginRedo(h, c), nil)
	local _t, token = core.beginUndo(h, c, false)
	core.finishCommand(h, token, true)
	eq(core.canRedo(h), false) -- in flight until the engine applies it
	core.observe(h, b)
	ok(core.canRedo(h))
	ok(core.redoTarget(h) == c)
	local target
	target, token = core.beginRedo(h, b)
	ok(target == c)
	eq(#h.states, 3)
	eq(#h.redo, 0)
	eq(core.canUndo(h), false)
	eq(core.observe(h, b), false) -- stale
	core.finishCommand(h, token, true)
	eq(core.observe(h, c), false) -- our own redo isn't recorded
	eq(h.expected, nil)
	eq(core.changeCount(h), 2)
	ok(core.canUndo(h))
end)

test("redo: a user edit clears the redo stack", function()
	local a, b, c, d = hs({ 10, 20 }, { 10 }, { 10, 30 }, { 40 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	core.beginUndo(h, c, false)
	core.observe(h, b)
	eq(#h.redo, 1)
	eq(core.observe(h, d), true)
	eq(#h.redo, 0)
	eq(core.redoTarget(h), nil)
end)

test("redo: revert all stacks every undone state so redo steps forward in order", function()
	local a, b, c, d = hs({ 10, 20 }, { 10 }, { 10, 30 }, { 10, 30, 40 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	core.observe(h, d)
	core.beginUndo(h, d, true)
	core.observe(h, a)
	eq(#h.redo, 3)
	local live = a
	for _i, want in ipairs({ b, c, d }) do
		local target = core.beginRedo(h, live)
		ok(target == want)
		core.observe(h, target)
		live = target
	end
	eq(#h.redo, 0)
	eq(#h.states, 4)
end)

test("redo: a failed redo restores both stacks; an edit in between leaves redo empty", function()
	local a, b, c, d = hs({ 10, 20 }, { 10 }, { 10, 30 }, { 40 })
	local h = core.newHistory(a)
	core.observe(h, b)
	core.observe(h, c)
	core.beginUndo(h, c, false)
	core.observe(h, b)
	core.beginUndo(h, b, false)
	core.observe(h, a)
	local _t, token = core.beginRedo(h, a)
	core.finishCommand(h, token, false)
	eq(#h.states, 1)
	eq(#h.redo, 2)
	ok(core.redoTarget(h) == b)
	eq(h.expected, nil)
	-- failed redo after a user edit came in: the edit stays, redo stays cleared
	_t, token = core.beginRedo(h, a)
	core.observe(h, d)
	core.finishCommand(h, token, false)
	eq(#h.redo, 0)
	ok(core.equal(h.states[#h.states], d))
end)

test("redo: the cap holds for the redo stack and the dropped count comes back with redo", function()
	local first = snap({ stop(1) })
	local h = core.newHistory(first)
	for i = 1, 5 do core.observe(h, snap({ stop(i + 1) }), 3) end
	eq(h.dropped, 3)
	eq(core.changeCount(h), 5)
	core.beginUndo(h, h.states[3], true, 3)
	eq(#h.redo, 2)
	eq(core.changeCount(h), 0)
	core.beginRedo(h, first, 3)
	eq(core.changeCount(h), 4)
	-- an oversized redo stack is trimmed from the far end
	local h2 = core.newHistory(first)
	for i = 1, 5 do core.observe(h2, snap({ stop(i + 1) })) end
	core.beginUndo(h2, h2.states[6], true, 2)
	eq(#h2.redo, 2)
	eq(h2.redo[2].stops[1].stationGroup, 2)
end)

-- matchesLive / observeLive (per-step fast path) ---------------------------------------------------------------------

-- every single-field mutation of a rich line, plus structural ones; matchesLive must agree with
-- equal(snapshot(comp), snap) (it may only say false when they are equal, never true when they differ)
local function richLine()
	return line({
		stop(10, { waypoints = { wpEdge(3, 77, 4, 0.25), wpPos(4, 1, 2, 3) } }),
		stop(20, { stopConfig = nil }),
		stop(30, { alternativeTerminals = {} }),
	}, { customFilters = true, reservationPriority = 2 })
end

local MUTATIONS = {
	function(c) c.customFilters = false end,
	function(c) c.reservationPriority = 3 end,
	function(c) c.stops[3] = nil end,
	function(c) c.stops[4] = stop(40) end,
	function(c) c.stops[1], c.stops[2] = c.stops[2], c.stops[1] end,
	function(c) c.stops[1].stationGroup = 11 end,
	function(c) c.stops[1].station = 1 end,
	function(c) c.stops[1].terminal = 5 end,
	function(c) c.stops[1].loadMode = 1 end,
	function(c) c.stops[1].minWaitingTime = 5 end,
	function(c) c.stops[1].maxWaitingTime = 5 end,
	function(c) c.stops[1].maxAdditionalWaitingTime = 5 end,
	function(c) c.stops[1].alternativeTerminals[1].terminal = 7 end,
	function(c) c.stops[1].alternativeTerminals[1].station = 7 end,
	function(c) c.stops[1].alternativeTerminals[2] = { station = 0, terminal = 3 } end,
	function(c) c.stops[3].alternativeTerminals[1] = { station = 0, terminal = 3 } end,
	function(c) c.stops[1].waypoints[1].tag = 9 end,
	function(c) c.stops[1].waypoints[1].edgePos.param = 0.5 end,
	function(c) c.stops[1].waypoints[1].edgePos.edgeId.entity = 78 end,
	function(c) c.stops[1].waypoints[1].edgePos.edgeId.index = 5 end,
	function(c) c.stops[1].waypoints[1].edgePos = nil end,
	function(c) c.stops[1].waypoints[1].edgePos.edgeId = nil end,
	function(c) c.stops[1].waypoints[1].pos = { x = 0, y = 0, z = 0 } end,
	function(c) c.stops[1].waypoints[2].pos.z = 4 end,
	function(c) c.stops[1].waypoints[2].pos = nil end,
	function(c) c.stops[1].waypoints[2].edgePos = { edgeId = { entity = 1, index = 0 }, param = 0 } end,
	function(c) c.stops[1].waypoints[3] = wpPos(5, 0, 0, 0) end,
	function(c) c.stops[1].waypoints[2] = nil end,
	function(c) c.stops[1].stopConfig.load[2] = true end,
	function(c) c.stops[1].stopConfig.load[3] = true end,
	function(c) c.stops[1].stopConfig.maxLoad[1] = 0.75 end,
	function(c) c.stops[1].stopConfig.forceUnload = true end,
	function(c) c.stops[1].stopConfig.destroyForConfigChange = true end,
	function(c) c.stops[1].stopConfig.destroyForRefresh = false end,
	function(c) c.stops[1].stopConfig = nil end,
	function(c) c.stops[2].stopConfig = { load = {}, maxLoad = {} } end,
	function(_c) end, -- unchanged
}

test("matchesLive agrees with equal(snapshot(comp), snap) for every mutation", function()
	local snap = core.snapshot(richLine())
	for i, mutate in ipairs(MUTATIONS) do
		local comp = richLine()
		mutate(comp)
		local want = core.equal(core.snapshot(comp), snap)
		eq(core.matchesLive(comp, snap), want, "mutation " .. i)
		-- and the other way round: the mutated line as the stored state, the original as live
		eq(core.matchesLive(richLine(), core.snapshot(comp)), want, "reverse mutation " .. i)
	end
	ok(core.matchesLive(richLine(), snap))
	eq(core.matchesLive(nil, snap), false)
	eq(core.matchesLive(richLine(), nil), false)
end)

test("matchesLive reads userdata-like vectors and compares userdata values by tostring", function()
	local mode = setmetatable({}, { __tostring = function() return "LoadMode(1)" end })
	local comp = line({ stop(10, { loadMode = mode }) })
	local snap = core.snapshot(comp)
	local other = setmetatable({}, { __tostring = function() return "LoadMode(1)" end })
	local backing = { stop(10, { loadMode = other }) }
	local vec = setmetatable({}, { __len = function() return #backing end, __index = function(_t, i) return backing[i] end })
	ok(core.matchesLive({ stops = vec, customFilters = false, reservationPriority = 0 }, snap))
end)

test("observeLive records exactly what observe(snapshot) records", function()
	for i, mutate in ipairs(MUTATIONS) do
		local hA = core.newHistory(core.snapshot(richLine()))
		local hB = core.newHistory(core.snapshot(richLine()))
		local comp = richLine()
		mutate(comp)
		eq(core.observeLive(hA, comp), core.observe(hB, core.snapshot(comp)), "mutation " .. i)
		eq(hA.states, hB.states, "mutation " .. i)
		-- unchanged afterwards: no new entry, and the stored state is not replaced
		local top = hA.states[#hA.states]
		eq(core.observeLive(hA, comp), false)
		ok(hA.states[#hA.states] == top)
	end
end)

test("observeLive: our in-flight undo lands (live equals the top) and clears expected", function()
	local h = core.newHistory(core.snapshot(line({ stop(10), stop(20) })))
	core.observeLive(h, line({ stop(10) }))
	local _t, token = core.beginUndo(h, core.snapshot(line({ stop(10) })), false)
	ok(h.expected ~= nil)
	eq(core.observeLive(h, line({ stop(10) })), false) -- stale: not applied yet
	ok(h.expected ~= nil)
	eq(core.observeLive(h, line({ stop(10), stop(20) })), false) -- applied
	eq(h.expected, nil)
	eq(#h.states, 1)
	core.finishCommand(h, token, true)
end)
