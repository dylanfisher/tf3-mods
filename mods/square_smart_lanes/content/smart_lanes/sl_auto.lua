-- Smart Lanes "Keep timing adjusted" (rev 8, RETIME_PLAN.md "Step B" and "Step B v4", PLAN.md "Keep timing adjusted"):
-- the junctions whose light phase lengths are re-timed automatically now and then (sl_autoretime.lua, the runtime),
-- and the "last measured" record of every junction either mode measured (the tool's Re-time and the runtime). This
-- file is the saved lists and their event; pure apart from M.readSaved / M.readLast (GUI thread). Lua 5.1 syntax.
--
-- Saved in the game-script state (sl_lanes.script.lua handleEvent), never mixed into `zones` or `kept`:
--   auto = { {n, x, y}, ... }             node id (the last one seen there) and position (rounded to ROUND m); older
--                                        rev 8 builds stored {n, x, y, t, e, c}: the extra fields are dropped on read
--   aseq = n                              +1 per change of auto / aall / areq (the GUI mirrors re-read the list only then)
--   aall = { seq = n, run = "<id>" }      the last "enroll every lit junction" request (the runtime answers it once)
--   areq = { seq = n, nodes = { {n, x, y} } } the last "decide now" request (the runtime decides there at its next look,
--                                        once the junction has enough snapshots)
--   arun = "<id>"                         run id of the last all / clear (the Stress Test reads it back, as zrun)
--   rlast = { {n, x, y, t, k, c0, c1, d} } the last measurement of each junction either mode measured: node id,
--                                        position, game s (whole), k = source x 10 + outcome (SRC, OUT below), the
--                                        cycle before and after (whole s; equal unless written), d = the signature
--                                        of the durations Smart Lanes last wrote there (M.durSig; 0: none written
--                                        yet; a not-written outcome carries the previous record's, M.carrySig).
--                                        d is optional: records of builds before 2026-10-16 have 7 fields
--                                        (M.timingOf then compares the cycle with c1). PLAN.md "Smart lights stays
--                                        on after its timing changed": our timing vs the player's.
--   lseq = n                              +1 per change of rlast (the tool re-reads it only then)
-- Nothing is written before the first enroll / measurement (a save that never used either gets none of these keys).
-- "Automatic light timing" and the first-load welcome add amode, aout, wel and mpass (sl_allmode.lua header).
-- The in-game settings panel adds sset and sseq (sl_settings.lua header).
-- The tool's "Record traffic" adds trec and tseq (sl_record.lua header: the last recording of each junction).
-- At most MAX enrolled junctions: an add beyond it is refused (never the oldest dropped: every entry is the player's
-- opt-in). At most LAST_MAX records: the oldest is dropped (a record, not an opt-in).
-- Size bound: MAX x 3 numbers + LAST_MAX x 8 numbers + 60 x 3 numbers (areq) + two short strings: under 120 kB
-- serialized with both caps reached (test_auto.lua "save safety"; a save without the feature: nothing).
--
-- Keyed by position (RETIME_PLAN.md "Open in-game questions" 1: whether a phases-only write re-creates the node is
-- unknown): an entry matches a node by id, or by position within R m (a node re-created at the same spot, under a
-- new id, keeps its entry; the runtime re-attaches it and sends the new id with an update).
--
-- Channel (any GUI Lua state -> the saved state; the pattern of SmartLanes.zones / SmartLanes.kept):
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.auto", payload))
--   payload:
--     { op = "add",    nodes = { {n, x, y}, ... }, src = "tool" | "zone" | "all" | "stress" | "build" | "select" }
--                      enroll (build: all lights, a new light the runtime found at a build's nodes; select: all
--                      lights, the tool selected an eligible lit junction; both only while all lights are in force)
--     { op = "remove", nodes = { {n, x, y}, ... }, src = "tool" | "prune" | "stress" }         unenroll
--     { op = "update", nodes = { {n, x, y}, ... }, src = "auto" }   the runtime re-attached a junction (the matched
--                      entry gets the new id / position; nothing is added)
--     { op = "now",    nodes = { {n, x, y} }, src = "tool" | "stress" }   decide at these junctions at the next look
--     { op = "all",    run = "<id>", src = "stress" }   enroll every lit junction on the map (the runtime finds them,
--                      then sends add events with src = "all"; at most MAX in all)
--     { op = "clear",  run = "<id>", src = "stress" }   unenroll every junction
--     { op = "last",   nodes = { {n, x, y, t, k, c0, c1, d}, ... }, src = "tool" | "auto" }   last-measured records
--     { op = "mode",   mode = "all" | "pick" | "off", src = "tool" }   the per-save override of "Automatic light
--                      timing" (sl_allmode.lua: amode; all clears the opt-outs; pick from all also unenrolls every
--                      junction; off keeps the list and the opt-outs, nothing is timed until another mode)
--     { op = "welcome", answer = "apply" | "later", lanes = bool, lights = bool, src = "welcome" }   the first-load
--                      welcome's answer (wel; apply + lights: amode all; apply + lanes: mpass requested)
--     { op = "pass",   phase = "done", seq = n, src = "auto" }   the existing-junctions pass seq finished (mpass.done)
--     { op = "setting", key = "lights" | "freeTurn" | "phases" | "every", value = i, src = "tool" | "crossing" }
--                      an in-game setting of this save (sl_settings.lua: sset / sseq; the panel in the Smart Lanes
--                      tool or the Crossing Tool, sl_settingsui.lua)
--     { op = "traffic", nodes = { {n, x, y, t, k, d, v, d3, v3}, ... }, src = "tool" }   the last traffic recording of
--                      each junction / roundabout (sl_record.lua: trec / tseq)
--   At most EVENT_MAX nodes per event (more go in several events). run: [%w._-], at most 40 characters (sl_zones).

local Settings = ug_require "square_smart_lanes::/smart_lanes/sl_settings.lua"
local AllMode = ug_require "square_smart_lanes::/smart_lanes/sl_allmode.lua"
local Rec = ug_require "square_smart_lanes::/smart_lanes/sl_record.lua"

local M = {}

M.EVENT_ID = "square_smart_lanes"
M.EV_AUTO = "SmartLanes.auto"
M.GS_NAME = "square_smart_lanes::/smart_lanes/sl_lanes.gs"
M.MAX = 1000         -- enrolled junctions (an add beyond is refused: AUTORETIME op=refuse reason=cap)
M.LAST_MAX = 1000    -- last-measured records (the oldest dropped beyond)
M.EVENT_MAX = 60     -- nodes per event (more: the whole event is ignored)
M.R = 2              -- m, position match radius
M.ROUND = 0.1        -- m, stored positions are rounded to this
M.COORD_MAX = 1e6
M.ID_MAX = 1e12
M.T_MAX = 1e10       -- game s
M.CYCLE_MAX = 1000   -- s, a record's cycle fields
M.DSIG_MAX = 1e8     -- a record's durations signature (M.durSig: at most 64 phases of at most 1000 s)
M.DSIG_PHASES = 64   -- phases a signature reads
M.CYCLE_TOL = 0.5    -- s, a 7-field record's cycle vs the phases' (M.timingOf)
M.RUN_MAX = 40

-- Interval (game s) between two decisions at a junction (RETIME_PLAN.md "Step B v4", "Decisions"):
M.EVERY_FIRST = 0     -- a junction with enough snapshots is decided at the next look
M.EVERY_SOON = 300    -- a long cycle not confirmed yet: 5 game min
M.EVERY_WRITE = 600   -- after a write: 10 game min (also the least time between two writes there)
M.EVERY_BACKOFF = 600 -- the first "fits": 10 min, then doubled
M.EVERY_MAX = 3600    -- at most 60 game min
M.RETRY_S = 120       -- a decision or write skipped (the player builds nearby, a change pending, the junction changed)
-- Setting "Keep timing adjusted: check interval" (mod.json sqrl_auto_every, values x0.5 / x1 / x2 / x4, default x1):
-- a factor on EVERY_SOON, EVERY_WRITE, EVERY_BACKOFF and EVERY_MAX (M.every); EVERY_FIRST, RETRY_S, the snapshots
-- (sl_autoretime SNAP_EVERY_S), the averages (TAU_S) and the map-wide write gap are not scaled. Set once per Lua state
-- by the runtime (sl_autoretime T.new, from getModParams); the tool's manual Re-time does not use it.
M.PARAM_EVERY = "sqrl_auto_every"
M.EVERY_FACTORS = { 0.5, 1, 2, 4 }
M.EVERY_DEFAULT = 2   -- 1-based index: x1
M.EVERY_FACTOR_MIN, M.EVERY_FACTOR_MAX = 0.5, 4
M.everyFactor = 1
-- last-measured records: k = SRC x 10 + OUT
M.SRC = { manual = 1, auto = 2 }
M.OUT = { written = 1, fits = 2, small = 3, notwritten = 4 }
M.SRC_NAME, M.OUT_NAME = {}, {}
for k, v in pairs(M.SRC) do M.SRC_NAME[v] = k end
for k, v in pairs(M.OUT) do M.OUT_NAME[v] = k end

local CELL = 2 * M.R
local SRC = {
	add = { tool = true, zone = true, all = true, stress = true, build = true, select = true },
	remove = { tool = true, prune = true, stress = true },
	update = { auto = true },
	now = { tool = true, stress = true },
	all = { stress = true, tool = true },
	clear = { stress = true, tool = true },
	last = { tool = true, auto = true },
	mode = { tool = true, welcome = true, crossing = true },
	welcome = { welcome = true },
	pass = { auto = true },
	setting = { tool = true, crossing = true },
	traffic = { tool = true },
}
local DEFAULT_SRC = { add = "tool", remove = "tool", update = "auto", now = "tool", all = "stress", clear = "stress",
	last = "tool", mode = "tool", welcome = "welcome", pass = "auto", setting = "tool", traffic = "tool" }

local function finite(v, max)
	return type(v) == "number" and v == v and math.abs(v) <= max
end

--- A coordinate rounded to ROUND m (the stored form).
function M.round(v)
	local k = 1 / M.ROUND
	return math.floor(v * k + 0.5) / k
end

--- The position key of the log (pos=) and the runtime's records: "x,y" with one decimal.
function M.posKey(x, y)
	if type(x) ~= "number" or type(y) ~= "number" then return "-" end
	return string.format("%.1f,%.1f", M.round(x), M.round(y))
end

--- One entry {n, x, y} as a fresh table, nil when malformed (extra fields of older builds are dropped).
local function entryOf(e)
	if type(e) ~= "table" then return nil end
	local n, x, y = e[1], e[2], e[3]
	if n == nil and e.n ~= nil then n, x, y = e.n, e.x, e.y end
	if not finite(n, M.ID_MAX) or n < 0 or n ~= math.floor(n) then return nil end
	if not finite(x, M.COORD_MAX) or not finite(y, M.COORD_MAX) then return nil end
	return { n, M.round(x), M.round(y) }
end
M.entryOf = entryOf

--- One last-measured record {n, x, y, t, k, c0, c1[, d]} as a fresh table (t, c0, c1 whole numbers), nil when
-- malformed. d (the durations signature) is kept when it is a whole number 0..DSIG_MAX, else left out (the record
-- stays: it reads as a record of an older build).
function M.lastEntryOf(e)
	local b = entryOf(e)
	if b == nil then return nil end
	local t, k, c0, c1, d = e[4], e[5], e[6], e[7], e[8]
	if not finite(t, M.T_MAX) or t < 0 then return nil end
	if not finite(k, 100) or k ~= math.floor(k) or M.SRC_NAME[math.floor(k / 10)] == nil or M.OUT_NAME[k % 10] == nil then
		return nil
	end
	if not finite(c0, M.CYCLE_MAX) or c0 < 0 or not finite(c1, M.CYCLE_MAX) or c1 < 0 then return nil end
	local r = { b[1], b[2], b[3], math.floor(t + 0.5), k, math.floor(c0 + 0.5), math.floor(c1 + 0.5) }
	if finite(d, M.DSIG_MAX) and d >= 0 and d == math.floor(d) then r[8] = d end
	return r
end

--- A record for node n at (x, y): src "manual" | "auto", out "written" | "fits" | "small" | "notwritten", t game s,
-- c0 / c1 the cycle before / after (s; c1 defaults to c0), d the durations signature (M.durSig of the written
-- durations, or M.carrySig; nil: none, a 7-field record). nil when malformed.
function M.record(n, x, y, t, src, out, c0, c1, d)
	if M.SRC[src] == nil or M.OUT[out] == nil then return nil end
	return M.lastEntryOf({ n, x, y, t, M.SRC[src] * 10 + M.OUT[out], c0 or 0, c1 or c0 or 0, d })
end

--- The parts of a record: { src, out (names), t, c0, c1, d (nil in a 7-field record) }, nil when malformed.
function M.recordParts(e)
	local r = type(e) == "table" and M.lastEntryOf(e) or nil
	if r == nil then return nil end
	return { src = M.SRC_NAME[math.floor(r[5] / 10)], out = M.OUT_NAME[r[5] % 10], t = r[4], c0 = r[6], c1 = r[7], d = r[8] }
end

---------------------------------------------------------------------------
-- Our timing vs the player's (PLAN.md "Smart lights stays on after its timing changed"): a hand edit in the
-- Crossing window keeps the phases' structure, so only the durations tell it from Re-time / Keep timing adjusted.
-- The engine flag userModifiedTrafficLightStates is set by every phases write, ours too (docs/findings/roads.md):
-- the record's signature of the durations we last wrote decides.

--- The signature of a phase list's durations (numbers, or tables with .duration): sum of i x round(2 x d_i) over at
-- most DSIG_PHASES phases (half seconds: what the engine reads back of a whole-second write; a swap of two phases
-- or one changed green changes it). At least 2 for any phases of 1 s or more; nil when unreadable or empty.
function M.durSig(durations)
	if type(durations) ~= "table" or #durations == 0 then return nil end
	local s = 0
	for i = 1, math.min(#durations, M.DSIG_PHASES) do
		local d = durations[i]
		if type(d) == "table" then d = d.duration end
		if not finite(d, M.CYCLE_MAX) or d < 0 then return nil end
		s = s + i * math.floor(2 * d + 0.5)
	end
	if s > M.DSIG_MAX then return nil end
	return s
end

local function cycleOf(durations)
	if type(durations) ~= "table" then return nil end
	local c = 0
	for i = 1, math.min(#durations, M.DSIG_PHASES) do
		local d = durations[i]
		if type(d) == "table" then d = d.duration end
		if not finite(d, M.CYCLE_MAX) then return nil end
		c = c + d
	end
	return c
end

--- Who timed phases with these durations, by the junction's record rec: "ours" (the durations Smart Lanes last
-- wrote there), "other" (we wrote others since: the player's Crossing window, or a Smart lights / plan write),
-- "unknown" (no record, or Smart Lanes never wrote durations there). A 7-field record (an older build): its written
-- cycle c1 within CYCLE_TOL s of these durations' sum is "ours", another sum "other"; a not-written one "unknown".
function M.timingOf(rec, durations)
	local r = type(rec) == "table" and M.lastEntryOf(rec) or nil
	if r == nil then return "unknown" end
	local d = r[8]
	if d ~= nil then
		if d == 0 then return "unknown" end
		local s = M.durSig(durations)
		if s ~= nil and s == d then return "ours" end
		return "other"
	end
	if M.OUT_NAME[r[5] % 10] ~= "written" then return "unknown" end
	local c = cycleOf(durations)
	if c ~= nil and math.abs(c - r[7]) <= M.CYCLE_TOL then return "ours" end
	return "other"
end

--- The signature a not-written outcome's record carries (the durations we last wrote stay the reference): the
-- previous record's d; a 7-field one: these (current) durations' signature when M.timingOf calls them ours, else 0;
-- no previous record: 0.
function M.carrySig(prev, durations)
	local r = type(prev) == "table" and M.lastEntryOf(prev) or nil
	if r == nil then return 0 end
	if r[8] ~= nil then return r[8] end
	if M.timingOf(r, durations) == "ours" then return M.durSig(durations) or 0 end
	return 0
end

local function validRun(run)
	if type(run) == "number" then
		if not finite(run, 1e15) then return nil end
		return string.format("%d", math.floor(run))
	end
	if type(run) ~= "string" or #run == 0 or #run > M.RUN_MAX then return nil end
	if not run:match("^[%w%._%-]+$") then return nil end
	return run
end

--- Validates an event param. Returns op, nodes (fresh entries; {} for all / clear / mode / welcome / pass), src, run
-- ("-" when none), and for mode / welcome / pass the checked fields { mode } | { answer, lanes, lights } | { seq };
-- or nil and the reason (never logs the payload).
function M.validate(param)
	if type(param) ~= "table" then return nil, "not_table" end
	local op = param.op
	if type(op) ~= "string" or SRC[op] == nil then return nil, "op" end
	local src = param.src
	if src == nil then src = DEFAULT_SRC[op] end
	if type(src) ~= "string" or not SRC[op][src] then return nil, "src" end
	local run = "-"
	if param.run ~= nil then
		run = validRun(param.run)
		if run == nil then return nil, "run" end
	end
	if op == "all" or op == "clear" then return op, {}, src, run end
	if op == "mode" then
		if not AllMode.isMode(param.mode) then return nil, "mode" end
		return op, {}, src, run, { mode = param.mode }
	end
	if op == "welcome" then
		if param.answer ~= "apply" and param.answer ~= "later" then return nil, "answer" end
		for _, k in ipairs({ "lanes", "lights" }) do
			if param[k] ~= nil and type(param[k]) ~= "boolean" then return nil, k end
		end
		return op, {}, src, run, { answer = param.answer, lanes = param.lanes == true, lights = param.lights == true }
	end
	if op == "setting" then
		local name, value = Settings.validate(param)
		if name == nil then return nil, value end
		return op, {}, src, run, { key = name, value = value }
	end
	if op == "pass" then
		local q = param.seq
		if param.phase ~= "done" then return nil, "phase" end
		if not finite(q, 1e9) or q < 1 or q ~= math.floor(q) then return nil, "seq" end
		return op, {}, src, run, { seq = q }
	end
	local list = param.nodes
	if type(list) ~= "table" then return nil, "nodes" end
	local n = #list
	if n == 0 then return nil, "empty" end
	if n > M.EVENT_MAX then return nil, "too_many" end
	local out = {}
	for i = 1, n do
		local e
		if op == "last" then e = M.lastEntryOf(list[i])
		elseif op == "traffic" then e = Rec.entryOf(list[i])
		else e = entryOf(list[i]) end
		if e == nil then return nil, "node" .. i end
		out[i] = e
	end
	return op, out, src, run
end

local function near(a, x, y)
	local dx, dy = a[2] - x, a[3] - y
	return dx * dx + dy * dy <= M.R * M.R
end

--- Whether entry a matches node n at (x, y): the same id, or within R m.
function M.matches(a, n, x, y)
	if type(a) ~= "table" then return false end
	if n ~= nil and a[1] == n then return true end
	return type(x) == "number" and type(y) == "number" and type(a[2]) == "number" and type(a[3]) == "number" and near(a, x, y)
end

--- The saved list cleaned (malformed entries dropped, at most MAX), as fresh tables {n, x, y}.
function M.clean(list)
	local cur = {}
	if type(list) ~= "table" then return cur end
	for i = 1, math.min(#list, M.MAX) do
		local e = entryOf(list[i])
		if e ~= nil then cur[#cur + 1] = e end
	end
	return cur
end

local function cellKey(cx, cy) return (cx + 0) .. ":" .. (cy + 0) end

--- A lookup of a list for M.match: by id and a grid of CELL m. entryFn: how entries are cleaned (default: enrolled
-- entries {n, x, y}; M.lastIndex passes M.lastEntryOf); max: entries read (default MAX).
function M.index(list, entryFn, max)
	entryFn = entryFn or entryOf
	local idx = { byId = {}, grid = {}, n = 0, list = {} }
	if type(list) ~= "table" then return idx end
	for i = 1, math.min(#list, max or M.MAX) do
		local e = entryFn(list[i])
		if e ~= nil then
			idx.n = idx.n + 1
			idx.list[idx.n] = e
			idx.byId[e[1]] = e
			local k = cellKey(math.floor(e[2] / CELL), math.floor(e[3] / CELL))
			local c = idx.grid[k]
			if c == nil then
				c = {}
				idx.grid[k] = c
			end
			c[#c + 1] = e
		end
	end
	return idx
end

--- M.index over a saved rlast list.
function M.lastIndex(list) return M.index(list, M.lastEntryOf, M.LAST_MAX) end

--- The entry node n at (x, y) matches (its id first, then the nearest within R m), else nil. Nil-safe.
function M.match(idx, n, x, y)
	if type(idx) ~= "table" or idx.byId == nil or (idx.n or 0) == 0 then return nil end
	if n ~= nil and idx.byId[n] ~= nil then return idx.byId[n] end
	if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
	local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
	local best, bestD = nil, nil
	for dx = -1, 1 do
		for dy = -1, 1 do
			for _, e in ipairs(idx.grid[cellKey(cx + dx, cy + dy)] or {}) do
				local ex, ey = e[2] - x, e[3] - y
				local d = ex * ex + ey * ey
				if d <= M.R * M.R and (bestD == nil or d < bestD) then best, bestD = e, d end
			end
		end
	end
	return best
end

--- The list after an add / remove / update: a fresh list (the input is not changed) and stats { added, removed,
-- updated, already, refused = { entries refused by the cap }, changed (bool) }. An add of a junction already in the
-- list (by id or position) refreshes its id and position only; an update re-keys the matched entry. Bounded: one
-- index of the list (MAX) and EVENT_MAX lookups (a remove rebuilds the index).
function M.apply(list, op, nodes)
	local idx = M.index(list)
	local cur = idx.list
	local st = { added = 0, removed = 0, updated = 0, already = 0, refused = {}, changed = false }
	for i = 1, math.min(#(nodes or {}), M.EVENT_MAX) do
		local e = nodes[i]
		if op == "remove" then
			local keep = {}
			for _, a in ipairs(cur) do
				if M.matches(a, e[1], e[2], e[3]) then st.removed = st.removed + 1 else keep[#keep + 1] = a end
			end
			if #keep ~= #cur then
				cur = keep
				idx = M.index(cur)
				cur = idx.list
			end
		else
			local hit = M.match(idx, e[1], e[2], e[3])
			if op == "update" then
				if hit ~= nil and (hit[1] ~= e[1] or hit[2] ~= e[2] or hit[3] ~= e[3]) then
					hit[1], hit[2], hit[3] = e[1], e[2], e[3]
					st.updated = st.updated + 1
					idx = M.index(cur)
					cur = idx.list
				end
			elseif hit ~= nil then
				if hit[1] ~= e[1] then
					hit[1], hit[2], hit[3] = e[1], e[2], e[3]
					st.updated = st.updated + 1
					idx = M.index(cur)
					cur = idx.list
				end
				st.already = st.already + 1
			elseif #cur >= M.MAX then
				st.refused[#st.refused + 1] = e
			else
				local a = { e[1], e[2], e[3] }
				cur[#cur + 1] = a
				idx.n = idx.n + 1
				idx.byId[a[1]] = a
				local k = cellKey(math.floor(a[2] / CELL), math.floor(a[3] / CELL))
				idx.grid[k] = idx.grid[k] or {}
				table.insert(idx.grid[k], a)
				st.added = st.added + 1
			end
		end
	end
	st.changed = st.added > 0 or st.removed > 0 or st.updated > 0
	return cur, st
end

--- The records after a "last" event: a fresh list, the matched record (by id or within R m) replaced, a new one
-- appended; beyond LAST_MAX the oldest (least t) dropped. Returns the list and stats { replaced, added, dropped,
-- changed }. Bounded: one index of the list (LAST_MAX), EVENT_MAX lookups, at most one sort.
function M.applyLast(list, records)
	local idx = M.lastIndex(list)
	local cur = idx.list
	local st = { replaced = 0, added = 0, dropped = 0, changed = false }
	for i = 1, math.min(#(records or {}), M.EVENT_MAX) do
		local e = M.lastEntryOf(records[i])
		if e ~= nil then
			local hit = M.match(idx, e[1], e[2], e[3])
			if hit ~= nil then
				local same = true
				for j = 1, 8 do
					if hit[j] ~= e[j] then same = false end
				end
				if not same then
					-- (a re-keyed record: the grid cell of its old position keeps it until the next index)
					for j = 1, 8 do hit[j] = e[j] end
					st.replaced = st.replaced + 1
				end
			else
				cur[#cur + 1] = e
				idx.n = idx.n + 1
				idx.byId[e[1]] = e
				local k = cellKey(math.floor(e[2] / CELL), math.floor(e[3] / CELL))
				idx.grid[k] = idx.grid[k] or {}
				table.insert(idx.grid[k], e)
				st.added = st.added + 1
			end
		end
	end
	if #cur > M.LAST_MAX then
		local over = #cur - M.LAST_MAX
		local times = {}
		for i, e in ipairs(cur) do times[i] = e[4] end
		table.sort(times)
		local cut = times[over]
		local keep = {}
		for _, e in ipairs(cur) do
			if over > 0 and e[4] <= cut then
				over = over - 1
				st.dropped = st.dropped + 1
			else
				keep[#keep + 1] = e
			end
		end
		cur = keep
	end
	st.changed = st.replaced > 0 or st.added > 0 or st.dropped > 0
	return cur, st
end

--- The payloads of a node list: one per EVENT_MAX nodes.
function M.payloads(op, nodes, src)
	local out = {}
	local i, n = 1, #(nodes or {})
	while i <= n do
		local part = {}
		for j = i, math.min(i + M.EVENT_MAX - 1, n) do part[#part + 1] = nodes[j] end
		out[#out + 1] = { op = op, nodes = part, src = src }
		i = i + M.EVENT_MAX
	end
	return out
end

--- The factor of the setting from this mod's raw mod params (nil or a table of 1-based indices): 1 (x1) when missing
-- or not one of the values.
function M.everyFactorOf(raw)
	local i = type(raw) == "table" and tonumber(raw[M.PARAM_EVERY]) or nil
	if i == nil or i ~= math.floor(i) or i < 1 or i > #M.EVERY_FACTORS then i = M.EVERY_DEFAULT end
	return M.EVERY_FACTORS[i]
end

--- Sets the interval factor of this Lua state, clamped to [EVERY_FACTOR_MIN, EVERY_FACTOR_MAX]; anything not a
-- number (or NaN) gives 1. Returns the factor set.
function M.setEveryFactor(f)
	if type(f) ~= "number" or f ~= f then f = 1 end
	M.everyFactor = math.max(M.EVERY_FACTOR_MIN, math.min(M.EVERY_FACTOR_MAX, f))
	return M.everyFactor
end

--- An interval (game s) scaled by the setting's factor: M.every(M.EVERY_WRITE) etc.
function M.every(base)
	return base * M.everyFactor
end

--- The next interval (game s) between decisions after one with outcome `kind` ("write" | "fits" | "small" | other),
-- from the current one: a write -> EVERY_WRITE; fits / too little traffic -> doubled from EVERY_BACKOFF (10, 20, 40
-- min), at most EVERY_MAX; anything else (refused, error) -> EVERY_BACKOFF. All times the setting's factor (x0.5:
-- write 5 min, back-off 5, 10, 20, 30 min; x4: 40 min, back-off 40 .. 240 min). A skipped decision keeps its
-- interval (the caller retries after RETRY_S, not scaled).
function M.nextEvery(every, kind)
	local backoff, max = M.every(M.EVERY_BACKOFF), M.every(M.EVERY_MAX)
	if kind == "write" then return M.every(M.EVERY_WRITE) end
	if kind == "fits" or kind == "small" then
		local e = type(every) == "number" and every or 0
		if e < backoff then return backoff end
		return math.min(max, e * 2)
	end
	return backoff
end

--- The game-script state component (another Lua state: the GAME_SCRIPT component, as Kept.readSaved); "none" when
-- there is none.
local function gsComp(api)
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(M.GS_NAME)
	if entity == nil or entity < 0 then return "none" end
	local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
	if gs == nil then return "none" end
	return gs
end

--- The change stamp of the saved state from another Lua state: its sequence numbers (seq: build jobs, zseq, kseq,
-- sseq, aseq: amode, mpass and the list) read with state_native:find, joined in one string; nil when unreadable. The
-- game script's GUI poll (sl_lanes.script.lua guiBody) copies the whole state (state:get) only when it moved.
M.STAMP_KEYS = { "seq", "zseq", "kseq", "sseq", "aseq" }
function M.readStamp(api)
	local ok, stamp = pcall(function()
		local gs = gsComp(api)
		if gs == "none" then return nil end
		local native = gs.state_native
		if native == nil then return nil end
		local parts = {}
		for i, k in ipairs(M.STAMP_KEYS) do parts[i] = tostring(native:find(k)) end
		return table.concat(parts, ",")
	end)
	if ok then return stamp end
	return nil
end

--- The saved aseq, the list and the requests from another Lua state. lastSeq: the caller's last aseq; when it is
-- unchanged nothing else is read (returns seq, nil). Returns seq (nil: none saved), list (possibly empty), extra
-- { all = aall, req = areq, run = arun, mode = amode, out = aout, wel = wel, pass = mpass, lit = alit } (sl_allmode.lua: tables /
-- strings / numbers or nil); nil, nil when unreadable. Never throws. (A change of amode, aout, wel or alit bumps aseq;
-- mpass.done alone does not: read it with lastSeq nil.)
function M.readSaved(api, lastSeq)
	local ok, seq, list, extra = pcall(function()
		local gs = gsComp(api)
		if gs == "none" then return "none" end
		local okN, s, l, x = pcall(function()
			local native = gs.state_native
			if native == nil then error("no state_native") end
			local q = native:find("aseq")
			if type(q) == "number" and q == lastSeq then return q, nil, nil end
			local function tbl(key)
				local v = native:find(key)
				if v == nil then return nil end
				if type(v) == "string" or type(v) == "number" then return v end
				return v:asTable()
			end
			return q, tbl("auto") or {}, { all = tbl("aall"), req = tbl("areq"), run = tbl("arun"), mode = tbl("amode"),
				out = tbl("aout"), wel = tbl("wel"), pass = tbl("mpass"), lit = tbl("alit") }
		end)
		if okN then return s, l, x end
		local st = gs.state
		-- the component without a state yet (a new game, nothing saved by our game script): an empty list
		if st == nil then return nil, {}, {} end
		if type(st) ~= "table" then return "none" end
		if type(st.aseq) == "number" and st.aseq == lastSeq then return st.aseq, nil, nil end
		return st.aseq, st.auto or {}, { all = st.aall, req = st.areq, run = st.arun, mode = st.amode, out = st.aout,
			wel = st.wel, pass = st.mpass, lit = st.alit }
	end)
	if not ok or seq == "none" then return nil, nil, nil end
	if type(seq) ~= "number" then seq = nil end
	if list ~= nil and type(list) ~= "table" then list = {} end
	if seq == nil and list == nil then list = {} end
	return seq, list, extra or {}
end

--- A saved list and its sequence number (seqKey / listKey of the game-script state; as M.readSaved): lastSeq
-- unchanged reads nothing else (returns seq, nil); nil, nil when unreadable; seq nil and {} when nothing was saved.
-- Never throws.
local function readList(api, seqKey, listKey, lastSeq)
	local ok, seq, list = pcall(function()
		local gs = gsComp(api)
		if gs == "none" then return "none" end
		local okN, q, l = pcall(function()
			local native = gs.state_native
			if native == nil then error("no state_native") end
			local s = native:find(seqKey)
			if type(s) == "number" and s == lastSeq then return s, nil end
			local v = native:find(listKey)
			if v == nil then return s, {} end
			return s, v:asTable()
		end)
		if okN then return q, l end
		local st = gs.state
		if st == nil then return nil, {} end
		if type(st) ~= "table" then return "none" end
		if type(st[seqKey]) == "number" and st[seqKey] == lastSeq then return st[seqKey], nil end
		return st[seqKey], st[listKey] or {}
	end)
	if not ok or seq == "none" then return nil, nil end
	if type(seq) ~= "number" then seq = nil end
	if list ~= nil and type(list) ~= "table" then list = {} end
	if seq == nil and list == nil then list = {} end
	return seq, list
end

--- The saved lseq and rlast list (readList).
function M.readLast(api, lastSeq) return readList(api, "lseq", "rlast", lastSeq) end

--- The saved tseq and trec list of the traffic recordings (readList; sl_record.lua).
function M.readTraffic(api, lastSeq) return readList(api, "tseq", "trec", lastSeq) end

return M
