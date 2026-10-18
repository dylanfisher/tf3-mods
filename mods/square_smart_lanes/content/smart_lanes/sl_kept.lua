-- Smart Lanes kept nodes (rev 7, plans/square_smart_lanes/PLAN.md "Reset sticks"): junctions the player gave the
-- game's lanes back with the tool's Reset. The automatic pass leaves them alone, as nodes in a `game` zone
-- (sl_zones.lua), until an Apply of the tool on them clears the mark. A build next to a kept junction (a bus stop
-- on an arm, an upgraded arm) then no longer brings smart lanes back.
--
-- Saved in the game-script state as its own list, never mixed into `zones` (another mod's zones `set` replaces
-- every zone): kept = { {n, x, y}, ... } (node id, position), kseq = +1 per change (the GUI mirrors re-read the
-- list only then). Nothing is written before the first Reset (a save that never used it gets no `kept`).
-- At most MAX entries: the oldest are dropped first (KEPT op=dropped).
--
-- Channel (the tool's GUI Lua state -> the saved state; the same as SmartLanes.zones):
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "square_smart_lanes", "SmartLanes.kept",
--     { op = "add" | "remove", nodes = { {n, x, y}, ... }, src = "tool" | "auto" | "prune" }))
-- At most EVENT_MAX nodes per event (the tool's selection cap; more go in several events). handleEvent of
-- sl_lanes.script.lua validates it (M.validate) and stores the result of M.apply.
--
-- Matching: by node id, or by position within R m (a rebuild may replace the node; a new junction built on a
-- kept spot is the place the player reset, so it inherits the mark). An add first removes every entry it matches
-- (no duplicates; the entry moves to the end, the newest), a remove removes every entry it matches.
--
-- Pure apart from M.readSaved (GUI thread). Lua 5.1 syntax (the game's Lua is pre-5.3).

local M = {}

M.EVENT_ID = "square_smart_lanes"
M.EV_KEPT = "SmartLanes.kept"
M.GS_NAME = "square_smart_lanes::/smart_lanes/sl_lanes.gs"
M.MAX = 2000         -- entries in the saved list (more: the oldest dropped)
M.EVENT_MAX = 60     -- nodes per event (more: the whole event is ignored)
M.R = 1              -- m, position match radius
M.COORD_MAX = 1e6    -- m, |x| and |y| at most
M.ID_MAX = 1e12      -- largest node id accepted
local CELL = 2 * M.R -- grid cell of M.index (a match lies in the 3 x 3 cells around a point)
local SRC = { tool = true, auto = true, prune = true }

local function finite(v, max)
	-- NaN fails every comparison, +-inf fails the bound
	return type(v) == "number" and v == v and math.abs(v) <= max
end

--- One entry {n, x, y} of an event or the saved list as a fresh table, nil when malformed (positional fields; named
-- n / x / y accepted too).
local function entryOf(e)
	if type(e) ~= "table" then return nil end
	local n, x, y = e[1], e[2], e[3]
	if n == nil then n, x, y = e.n, e.x, e.y end
	if not finite(n, M.ID_MAX) or n < 0 or n ~= math.floor(n) then return nil end
	if not finite(x, M.COORD_MAX) or not finite(y, M.COORD_MAX) then return nil end
	return { n, x, y }
end
M.entryOf = entryOf

--- Validates an event param. Returns op ("add" | "remove"), the nodes (fresh {n, x, y} tables) and src ("tool"
-- when none given); or nil and the reason (never logs the payload).
function M.validate(param)
	if type(param) ~= "table" then return nil, "not_table" end
	local op = param.op
	if op ~= "add" and op ~= "remove" then return nil, "op" end
	local src = param.src
	if src == nil then src = "tool" end
	if type(src) ~= "string" or not SRC[src] then return nil, "src" end
	local list = param.nodes
	if type(list) ~= "table" then return nil, "nodes" end
	local n = #list
	if n == 0 then return nil, "empty" end
	if n > M.EVENT_MAX then return nil, "too_many" end
	local out = {}
	for i = 1, n do
		local e = entryOf(list[i])
		if e == nil then return nil, "node" .. i end
		out[i] = e
	end
	return op, out, src
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

--- The list after an event: a fresh list (the input is not changed; malformed saved entries are dropped) and
-- stats { added, removed, dropped }. Bounded: at most (#list + EVENT_MAX) * #nodes comparisons.
function M.apply(list, op, nodes)
	local cur = {}
	if type(list) == "table" then
		for i = 1, math.min(#list, M.MAX + M.EVENT_MAX) do
			local e = entryOf(list[i])
			if e ~= nil then cur[#cur + 1] = e end
		end
	end
	local st = { added = 0, removed = 0, dropped = 0 }
	for i = 1, math.min(#(nodes or {}), M.EVENT_MAX) do
		local e = nodes[i]
		local keep = {}
		for _, a in ipairs(cur) do
			if M.matches(a, e[1], e[2], e[3]) then
				if op == "remove" then st.removed = st.removed + 1 end
			else
				keep[#keep + 1] = a
			end
		end
		cur = keep
		if op == "add" then
			cur[#cur + 1] = { e[1], e[2], e[3] }
			st.added = st.added + 1
		end
	end
	if #cur > M.MAX then
		local over = #cur - M.MAX
		local keep = {}
		for i = over + 1, #cur do keep[#keep + 1] = cur[i] end
		cur = keep
		st.dropped = over
	end
	return cur, st
end

local function cellKey(cx, cy) return cx .. ":" .. cy end

--- A lookup of a list for M.match: by id and a grid of CELL m. Built once per mirror read.
function M.index(list)
	local idx = { byId = {}, grid = {}, n = 0 }
	if type(list) ~= "table" then return idx end
	for i = 1, math.min(#list, M.MAX + M.EVENT_MAX) do
		local e = entryOf(list[i])
		if e ~= nil then
			idx.n = idx.n + 1
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

--- The entry node n at (x, y) matches (its id first, then the nearest within R m), else nil. x / y may be nil
-- (id only). Nil-safe.
function M.match(idx, n, x, y)
	if type(idx) ~= "table" or idx.byId == nil or (idx.n or 0) == 0 then return nil end
	if n ~= nil and idx.byId[n] ~= nil then return idx.byId[n] end
	if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
	local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
	local best, bestD = nil, nil
	for dx = -1, 1 do
		for dy = -1, 1 do
			local c = idx.grid[cellKey(cx + dx, cy + dy)]
			for _, e in ipairs(c or {}) do
				local ex, ey = e[2] - x, e[3] - y
				local d = ex * ex + ey * ey
				if d <= M.R * M.R and (bestD == nil or d < bestD) then best, bestD = e, d end
			end
		end
	end
	return best
end

--- The events of a node list: one payload per EVENT_MAX nodes.
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

--- The saved kseq and kept list from another Lua state (the tool's, GUI thread; the GAME_SCRIPT component as
-- Zones.readSaved). lastSeq: the kseq of the caller's last read; when the saved kseq is a number equal to it, the
-- list is not read (returns seq, nil). Returns seq (nil: none saved yet), list (possibly empty); nil, nil when
-- unreadable. Never throws.
function M.readSaved(api, lastSeq)
	local ok, seq, list = pcall(function()
		local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(M.GS_NAME)
		if entity == nil or entity < 0 then return "none" end
		local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT)
		if gs == nil then return "none" end
		local okN, s, l = pcall(function()
			local native = gs.state_native
			if native == nil then error("no state_native") end
			local q = native:find("kseq")
			if type(q) == "number" and q == lastSeq then return q, nil end
			local k = native:find("kept")
			if k == nil then return q, {} end
			return q, k:asTable()
		end)
		if okN then return s, l end
		local st = gs.state
		if type(st) ~= "table" then return "none" end
		if type(st.kseq) == "number" and st.kseq == lastSeq then return st.kseq, nil end
		return st.kseq, st.kept or {}
	end)
	if not ok or seq == "none" then return nil, nil end
	if type(seq) ~= "number" then seq = nil end
	if list ~= nil and type(list) ~= "table" then list = {} end
	if seq == nil and list == nil then list = {} end
	return seq, list
end

return M
