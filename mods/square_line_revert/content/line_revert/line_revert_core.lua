-- Line Editor Undo core: pure functions, no game state. Unit-tested in tests/square_line_revert/test_core.lua.
--
-- A snapshot is a plain Lua copy of an Engine.Component.Line (api/tealdef/api/engine.d.tl:492-557). It must be a
-- copy, field by field: a reference to the userdata would follow the live line.
--
--   snapshot = {
--     stops = { {
--       stationGroup, station, terminal,                         -- integers (station/terminal zero-based)
--       alternativeTerminals = { { station, terminal } },        -- StationTerminal, type.d.tl:1009-1024
--       loadMode,                                                -- Line.LoadMode value as read
--       minWaitingTime, maxWaitingTime, maxAdditionalWaitingTime,
--       waypoints = { { tag, edgePos = { entity, index, param } | nil, pos = { x, y, z } | nil } },
--                                                                -- Waypoint, type.d.tl:1243-1257: edgePos (lanes)
--                                                                -- OR pos (ships, aircraft); the other is nil, as
--                                                                -- line_manager_panel.tl:1112-1114 reads it
--       stopConfig = { load = {bool}, maxLoad = {number}, forceUnload, destroyForConfigChange, destroyForRefresh },
--     } },
--     customFilters, reservationPriority,
--   }
--
-- build(snapshot, T) turns a snapshot back into an Engine.Component.Line with the constructors in T (= api.type in
-- game, fakes in tests), the same ones the base editor uses (see build below).

local core = {}

-- Engine vectors are userdata with # and 1-based [i] (comp.stops, as manager_window.tl / line_util.tl index them);
-- plain tables work the same way.
local function count(v)
	if v == nil then return 0 end
	return #v
end

local function copyList(v)
	local out = {}
	for i = 1, count(v) do
		out[i] = v[i]
	end
	return out
end

local function copyStopConfig(c)
	if c == nil then return nil end
	return {
		load = copyList(c.load),
		maxLoad = copyList(c.maxLoad),
		forceUnload = c.forceUnload,
		destroyForConfigChange = c.destroyForConfigChange,
		destroyForRefresh = c.destroyForRefresh,
	}
end

local function copyWaypoint(w)
	local out = { tag = w.tag }
	local ep = w.edgePos
	if ep ~= nil and ep.edgeId ~= nil then
		out.edgePos = { entity = ep.edgeId.entity, index = ep.edgeId.index, param = ep.param }
	end
	local p = w.pos
	if p ~= nil then
		out.pos = { x = p.x, y = p.y, z = p.z }
	end
	return out
end

local function copyStop(s)
	local alts = {}
	for i = 1, count(s.alternativeTerminals) do
		local t = s.alternativeTerminals[i]
		alts[i] = { station = t.station, terminal = t.terminal }
	end
	local wps = {}
	for i = 1, count(s.waypoints) do
		wps[i] = copyWaypoint(s.waypoints[i])
	end
	return {
		stationGroup = s.stationGroup,
		station = s.station,
		terminal = s.terminal,
		alternativeTerminals = alts,
		loadMode = s.loadMode,
		minWaitingTime = s.minWaitingTime,
		maxWaitingTime = s.maxWaitingTime,
		maxAdditionalWaitingTime = s.maxAdditionalWaitingTime,
		waypoints = wps,
		stopConfig = copyStopConfig(s.stopConfig),
	}
end

--- Plain deep copy of a LINE component (or nil).
function core.snapshot(lineComp)
	if lineComp == nil then return nil end
	local stops = {}
	for i = 1, count(lineComp.stops) do
		stops[i] = copyStop(lineComp.stops[i])
	end
	return {
		stops = stops,
		customFilters = lineComp.customFilters,
		reservationPriority = lineComp.reservationPriority,
	}
end

local function deepEqual(a, b)
	if a == b then return true end
	if type(a) == "userdata" and type(b) == "userdata" then
		-- an engine enum value (loadMode) read twice may be two userdata objects without __eq
		return tostring(a) == tostring(b)
	end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

core.stopEqual = deepEqual

--- Two snapshots describe the same line (stops in order, every field, plus the line settings).
function core.equal(a, b)
	return deepEqual(a, b)
end

-- Fast "unchanged?" check against the live component, for the per-step poll (line_revert.script.lua observe):
-- walks the userdata like snapshot() but builds nothing. Sound, not complete: true only when snapshot(lineComp)
-- would be core.equal to `snap` (field by field with the same deepEqual rules), so a false just means "take the
-- full snapshot". `snap` must come from core.snapshot (no keys beyond the ones it writes).

local function sameScalarList(v, list)
	local n = count(v)
	if list == nil or n ~= #list then return false end
	for i = 1, n do
		if not deepEqual(v[i], list[i]) then return false end
	end
	return true
end

local function sameStopConfig(c, t)
	if c == nil or t == nil then return c == nil and t == nil end
	return sameScalarList(c.load, t.load) and sameScalarList(c.maxLoad, t.maxLoad)
		and deepEqual(c.forceUnload, t.forceUnload)
		and deepEqual(c.destroyForConfigChange, t.destroyForConfigChange)
		and deepEqual(c.destroyForRefresh, t.destroyForRefresh)
end

local function sameWaypoint(w, t)
	if not deepEqual(w.tag, t.tag) then return false end
	local ep = w.edgePos
	if ep ~= nil and ep.edgeId ~= nil then
		local te = t.edgePos
		if te == nil or not (deepEqual(ep.edgeId.entity, te.entity) and deepEqual(ep.edgeId.index, te.index)
			and deepEqual(ep.param, te.param)) then return false end
	elseif t.edgePos ~= nil then
		return false
	end
	local p = w.pos
	if p ~= nil then
		local tp = t.pos
		if tp == nil or not (deepEqual(p.x, tp.x) and deepEqual(p.y, tp.y) and deepEqual(p.z, tp.z)) then return false end
	elseif t.pos ~= nil then
		return false
	end
	return true
end

local function sameStop(s, t)
	if not (deepEqual(s.stationGroup, t.stationGroup) and deepEqual(s.station, t.station)
		and deepEqual(s.terminal, t.terminal) and deepEqual(s.loadMode, t.loadMode)
		and deepEqual(s.minWaitingTime, t.minWaitingTime) and deepEqual(s.maxWaitingTime, t.maxWaitingTime)
		and deepEqual(s.maxAdditionalWaitingTime, t.maxAdditionalWaitingTime)) then return false end
	local alts, talts = s.alternativeTerminals, t.alternativeTerminals
	local n = count(alts)
	if talts == nil or n ~= #talts then return false end
	for i = 1, n do
		local a, b = alts[i], talts[i]
		if not (deepEqual(a.station, b.station) and deepEqual(a.terminal, b.terminal)) then return false end
	end
	local wps, twps = s.waypoints, t.waypoints
	n = count(wps)
	if twps == nil or n ~= #twps then return false end
	for i = 1, n do
		if not sameWaypoint(wps[i], twps[i]) then return false end
	end
	return sameStopConfig(s.stopConfig, t.stopConfig)
end

--- True when the live LINE component equals the snapshot `snap` (see above: false may still mean equal).
function core.matchesLive(lineComp, snap)
	if lineComp == nil or snap == nil or snap.stops == nil then return false end
	if not (deepEqual(lineComp.customFilters, snap.customFilters)
		and deepEqual(lineComp.reservationPriority, snap.reservationPriority)) then return false end
	local stops, n = lineComp.stops, count(lineComp.stops)
	if n ~= #snap.stops then return false end
	for i = 1, n do
		if not sameStop(stops[i], snap.stops[i]) then return false end
	end
	return true
end

--- Fills the named placeholders of a translated string: fill(_("{n} stops removed"), { n = 3 }). Whole phrases with
--- named placeholders let a translation reorder them (no sentence building; the game's own lang_util.format idea).
--- A placeholder without a value stays as it is.
function core.fill(text, values)
	return (text:gsub("{(%w+)}", function(k)
		local v = values[k]
		if v == nil then return nil end
		return tostring(v)
	end))
end

--- "1 stop removed" or "{n} stops removed": one key per form (translations use number-neutral wording).
local function counted(n, one, many)
	if n == 1 then return one end
	return core.fill(many, { n = n })
end

--- Joins display phrases with the translated list separator ("{list}, {item}"; CJK uses its own comma).
local function joinList(parts)
	local out = parts[1]
	for i = 2, #parts do out = core.fill(_("{list}, {item}"), { list = out, item = parts[i] }) end
	return out
end

--- Short human summary of how `now` differs from `snap`, "" when they are equal.
-- Stops are matched by station group: groups missing from `now` count as removed, extra ones as added.
-- With the same groups, a different order is "stops reordered", and stops at the same place with other
-- settings (terminal, load mode, waiting time, waypoints, cargo) are "N stops changed".
function core.diffSummary(snap, now)
	if core.equal(snap, now) then return "" end
	if snap == nil or now == nil then return _("line changed") end
	local a, b = snap.stops or {}, now.stops or {}
	local countA, countB = {}, {}
	for _i, s in ipairs(a) do countA[s.stationGroup] = (countA[s.stationGroup] or 0) + 1 end
	for _i, s in ipairs(b) do countB[s.stationGroup] = (countB[s.stationGroup] or 0) + 1 end
	local removed, added = 0, 0
	for g, n in pairs(countA) do
		local m = countB[g] or 0
		if n > m then removed = removed + n - m end
	end
	for g, n in pairs(countB) do
		local m = countA[g] or 0
		if n > m then added = added + n - m end
	end

	local parts = {}
	if removed > 0 then parts[#parts + 1] = counted(removed, _("1 stop removed"), _("{n} stops removed")) end
	if added > 0 then parts[#parts + 1] = counted(added, _("1 stop added"), _("{n} stops added")) end
	if removed == 0 and added == 0 then
		local reordered, changed = false, 0
		for i = 1, #a do
			if a[i].stationGroup ~= b[i].stationGroup then
				reordered = true
			elseif not deepEqual(a[i], b[i]) then
				changed = changed + 1
			end
		end
		if reordered then parts[#parts + 1] = _("stops reordered") end
		if changed > 0 then parts[#parts + 1] = counted(changed, _("1 stop changed"), _("{n} stops changed")) end
	end
	if snap.customFilters ~= now.customFilters or snap.reservationPriority ~= now.reservationPriority then
		parts[#parts + 1] = _("line settings changed")
	end
	if #parts == 0 then parts[1] = _("line changed") end
	return joinList(parts)
end

--- Stops whose station is gone. stationCount(group) returns the number of stations in the group, or nil when
-- the group entity no longer exists. Returns a list of { index, stationGroup, station } (empty when all exist).
function core.missingStops(snap, stationCount)
	local missing = {}
	for i, s in ipairs(snap and snap.stops or {}) do
		local n = stationCount(s.stationGroup)
		if n == nil or s.station == nil or s.station < 0 or s.station >= n then
			missing[#missing + 1] = { index = i, stationGroup = s.stationGroup, station = s.station }
		end
	end
	return missing
end

-- Undo / redo history ----------------------------------------------------------------------------------------
-- One history per session (line_revert.script.lua). The base editor commits every edit as its own
-- makeLineUpdateCmd (manager_window.tl:6526-6561), so each change seen between two steps is one undo step.
--
--   h = {
--     states  = { snapshot, ... },   -- states[1] = the line when the session started (never dropped)
--     dropped = n,                   -- entries dropped by the cap (only for the change count)
--     redo    = { snapshot, ... },   -- undone states, redo[#redo] = the next one to redo
--     redoDropped = n,               -- `dropped` parked while an undo reached states[1] (back on redo)
--     expected = snapshot | nil,     -- an undo or redo is in flight: the state we sent
--     stale    = snapshot | nil,     -- the line as it was when we sent it (still live until the engine applies it)
--     pending  = { prev, prevDropped, prevRedo, prevRedoDropped, pushed } | nil, -- restore if the command fails
--   }
--
-- Undo moves the state it leaves onto `redo`; redo pops it back onto `states`. A user edit clears `redo`. The
-- cap applies to both lists; together they never hold more than the history did before the undos.

core.HISTORY_CAP = 50

local function copyArray(t)
	local out = {}
	for i = 1, #t do out[i] = t[i] end
	return out
end

local function trim(h, cap)
	cap = cap or core.HISTORY_CAP
	while #h.states > cap do
		-- drop the oldest edit but keep states[1], so "revert all" still reaches the session start
		table.remove(h.states, 2)
		h.dropped = h.dropped + 1
	end
	while #h.redo > cap do
		-- redo[1] is the farthest step forward
		table.remove(h.redo, 1)
	end
end

local function clearRedo(h)
	h.redo = {}
	h.redoDropped = 0
end

--- A new history whose first entry is `snap`.
function core.newHistory(snap)
	return { states = { snap }, dropped = 0, redo = {}, redoDropped = 0 }
end

--- Number of recorded changes since the session started (including ones the cap dropped).
function core.changeCount(h)
	return h.dropped + #h.states - 1
end

--- True when there is something to undo and no command is in flight.
function core.canUndo(h)
	return #h.states > 1 and h.expected == nil
end

--- True when there is something to redo and no command is in flight.
function core.canRedo(h)
	return #h.redo > 0 and h.expected == nil
end

--- Feed the live line (a snapshot) once per step. Returns true when it was recorded as a new edit.
-- Our own undo / redo is not recorded: while `expected` is set, the live line equal to `stale` (not applied yet)
-- is ignored and the live line equal to `expected` ends the command. Anything else is a user edit that came in
-- between: the command is no longer awaited and the edit is recorded normally. A recorded edit clears the redo stack.
function core.observe(h, live, cap)
	if live == nil then return false end
	if h.expected ~= nil then
		if deepEqual(live, h.expected) then
			h.expected, h.stale = nil, nil
			return false
		end
		if h.stale ~= nil and deepEqual(live, h.stale) then return false end
		h.expected, h.stale = nil, nil
	end
	if deepEqual(live, h.states[#h.states]) then return false end
	h.states[#h.states + 1] = live
	clearRedo(h)
	if h.pending then
		local p = h.pending.pushed
		p[#p + 1] = live
	end
	trim(h, cap)
	return true
end

--- observe() for a live LINE component (the per-step poll). When the line still equals the newest state, that
-- state stands in for the snapshot (observe compares with deepEqual only, so it decides the same way), and the
-- step costs a walk over the component without building a copy. Otherwise the full snapshot is observed.
function core.observeLive(h, lineComp, cap)
	if lineComp == nil then return false end
	local top = h.states[#h.states]
	if core.matchesLive(lineComp, top) then return core.observe(h, top, cap) end
	return core.observe(h, core.snapshot(lineComp), cap)
end

--- The state an undo (or, with `all`, a revert all) would restore, or nil when there is nothing to undo.
function core.undoTarget(h, all)
	if #h.states <= 1 then return nil end
	if all then return h.states[1] end
	return h.states[#h.states - 1]
end

--- The state a redo would restore, or nil when there is nothing to redo.
function core.redoTarget(h)
	return h.redo[#h.redo]
end

local function newToken(h)
	return {
		prev = copyArray(h.states), prevDropped = h.dropped,
		prevRedo = copyArray(h.redo), prevRedoDropped = h.redoDropped,
		pushed = {},
	}
end

--- Starts an undo (or revert all): pops the history onto the redo stack and marks the target as expected. `live`
-- is the line now. Returns the target to send and a token for finishCommand, or nil when there is nothing to undo.
-- Revert all moves every undone state, top first, so redo then steps forward one state at a time.
function core.beginUndo(h, live, all, cap)
	local target = core.undoTarget(h, all)
	if target == nil then return nil end
	local pending = newToken(h)
	local keep = all and 1 or #h.states - 1
	for i = #h.states, keep + 1, -1 do
		h.redo[#h.redo + 1] = h.states[i]
		h.states[i] = nil
	end
	if #h.states == 1 then
		-- the edits the cap dropped lie between states[1] and the next redo state: park their count
		h.redoDropped, h.dropped = h.dropped, 0
	end
	h.expected, h.stale, h.pending = target, live, pending
	trim(h, cap)
	return target, pending
end

--- Starts a redo: pops the redo stack back onto the history and marks the target as expected. Returns the target
-- to send and a token for finishCommand, or nil when there is nothing to redo.
function core.beginRedo(h, live, cap)
	local target = core.redoTarget(h)
	if target == nil then return nil end
	local pending = newToken(h)
	h.redo[#h.redo] = nil
	if #h.states == 1 then
		h.dropped, h.redoDropped = h.redoDropped, 0
	end
	h.states[#h.states + 1] = target
	h.expected, h.stale, h.pending = target, live, pending
	trim(h, cap)
	return target, pending
end

--- The command's result. On failure both stacks come back as they were (plus edits recorded since, which also
-- leave the redo stack empty), and the command is no longer awaited. A token from an older command is ignored.
function core.finishCommand(h, token, success, cap)
	if token == nil or h.pending ~= token then return end
	h.pending = nil
	if success then return end
	local states = copyArray(token.prev)
	for _i, s in ipairs(token.pushed) do
		if not deepEqual(s, states[#states]) then states[#states + 1] = s end
	end
	h.states, h.dropped = states, token.prevDropped
	if #token.pushed == 0 then
		h.redo, h.redoDropped = copyArray(token.prevRedo), token.prevRedoDropped
	else
		clearRedo(h)
	end
	h.expected, h.stale = nil, nil
	trim(h, cap)
end

-- kept for the undo-only callers and tests
core.finishUndo = core.finishCommand

-- Restore -----------------------------------------------------------------------------------------------------

local function buildWaypoint(w, T)
	-- api.type.Waypoint.new() then set edgePos OR pos, as the editor builds one (manager_window.tl:695-697 lanes,
	-- :717-718 ships/aircraft); tag kept so it stays "the same waypoint" (manager_window.tl:6955-6957).
	local wp = T.Waypoint.new()
	if w.edgePos then
		local ep = T.EdgePos.new()
		ep.edgeId = T.EdgeId.new(w.edgePos.entity, w.edgePos.index)
		ep.param = w.edgePos.param
		wp.edgePos = ep
	elseif w.pos then
		wp.pos = T.Vec3f.new(w.pos.x, w.pos.y, w.pos.z)
	end
	if w.tag ~= nil then
		wp.tag = w.tag
	end
	return wp
end

local function buildStopConfig(c, T)
	-- api.type.Line.StopConfig.new() with fields set from plain tables, as line_util.tl:469-474 and
	-- cargofilter_window.tl:403 do (load/maxLoad are assigned Lua lists there too).
	local cfg = T.Line.StopConfig.new()
	cfg.load = copyList(c.load)
	cfg.maxLoad = copyList(c.maxLoad)
	cfg.forceUnload = c.forceUnload
	cfg.destroyForConfigChange = c.destroyForConfigChange
	cfg.destroyForRefresh = c.destroyForRefresh
	return cfg
end

local function buildStop(s, T)
	-- api.type.Line.Stop.new() + field by field, as line_util.autoAssignTerminals does (line_util.tl:170-212).
	-- Unlike the editor, terminals are never auto-assigned: the snapshot's exact terminals are restored.
	local stop = T.Line.Stop.new()
	stop.stationGroup = s.stationGroup
	stop.station = s.station
	stop.terminal = s.terminal
	local alts = {}
	for i, t in ipairs(s.alternativeTerminals or {}) do
		-- api.type.StationTerminal.new(station, terminal), manager_window.tl:6901
		alts[i] = T.StationTerminal.new(t.station, t.terminal)
	end
	stop.alternativeTerminals = alts
	if s.loadMode ~= nil then
		stop.loadMode = s.loadMode
	end
	stop.minWaitingTime = s.minWaitingTime
	stop.maxWaitingTime = s.maxWaitingTime
	stop.maxAdditionalWaitingTime = s.maxAdditionalWaitingTime
	local wps = {}
	for i, w in ipairs(s.waypoints or {}) do
		wps[i] = buildWaypoint(w, T)
	end
	stop.waypoints = wps
	if s.stopConfig then
		stop.stopConfig = buildStopConfig(s.stopConfig, T)
	end
	return stop
end

--- Engine.Component.Line from a snapshot, built like the editor's commit (manager_window.tl:6526-6530):
-- api.type.Line.new(), stops, customFilters, reservationPriority. T is api.type.
function core.build(snap, T)
	local comp = T.Line.new()
	local stops = {}
	for i, s in ipairs(snap.stops) do
		stops[i] = buildStop(s, T)
	end
	comp.stops = stops
	comp.customFilters = snap.customFilters
	comp.reservationPriority = snap.reservationPriority
	return comp
end

return core
