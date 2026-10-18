-- Smart Lanes "Record traffic" (rev 8, PLAN.md "Traffic rate at a junction"): the pure part of the tool's traffic
-- recording. The measuring is Re-time's pass counting (sl_retimer.lua: a second sampler instance in the tool's
-- controller, sl_toolcore C.record; a node junction as Re-time measures it, a roundabout over its junctions with
-- only the vehicles entering it counted); this file holds the 30 s bucket ring, the rates, the saved records and
-- their texts. Pure (no game reads); Lua 5.1 syntax.
--
-- Recording: up to MAX_RUNNING at once (2026-10-16; before: one at a time), each at most MAX_S game s (20 min) from
-- its own start, a sample every EVERY_S game s (5 s: at 40 m/s a car first seen beyond the sampler's 200 m is still
-- seen ahead of the junction at the next sample). All running recordings share one sampler run (sl_retimer.lua
-- M.startShared): one pass reads every recording's candidates once, within BUDGET_S per frame in all. When a pass
-- needs more frames than EVERY_S game s allows (many busy junctions, a high game speed) the next sample starts when it
-- is done: every recording's interval stretches alike and the frame cost stays. The 5 s bound then no longer holds for
-- the fastest cars: a car is seen ahead while it is within 200 m, i.e. for 200 / v s (14 s at 50 km/h, 9 s at 80 km/h,
-- 5 s at 144 km/h), so a pass is missed only when the interval exceeds that; the done line logs every_max_s and late
-- (samples more than 2 x EVERY_S after the one before). Each sample's new passes go into the bucket of its game time (BUCKET_S = 30 s, a ring of MAX_S / BUCKET_S slots). Shown: vehicles
-- per minute over the last RECENT_S (3 min: the buckets from the one RECENT_S / BUCKET_S before the current to the
-- current one, so the span is 180 .. 210 s and the rate is exact over it) and over the whole recording.
--
-- Saved (game-script state, sl_lanes.script.lua handleAuto op "traffic"; written from the first saved recording on
-- only, never on load):
--   trec = { {n, x, y, t, k, d, v, d3, v3 [, pt, pd, pv]} }
--                                             per junction / roundabout ever recorded, the last result: node id (a
--                                             roundabout: its ring key, the least node id of the ring), position
--                                             (rounded to ROUND m; a roundabout: the mean of its junctions), game s
--                                             of the result (whole), k = KIND (1 junction, 2 roundabout), d = the
--                                             seconds recorded, v = vehicles counted in them, d3 / v3 = the same
--                                             for the last-3-minutes span (d3 <= d, v3 <= v); pt / pd / pv (all
--                                             three or none, 2026-10-16): the recording before it there (its game
--                                             s, seconds, vehicles), shown muted to compare ("Previous recording:
--                                             ..."). A record of 9 numbers (the first rev 8 builds): no previous.
--   tseq = n                                  +1 per change of trec (the tool re-reads it only then)
-- At most MAX records (the oldest dropped beyond: a record, not an opt-in). Matched per kind by id, or by position
-- within R m (a junction re-created at the same spot keeps its record). Size: MAX x 12 numbers, under 120 kB
-- serialized with the cap reached (test_record.lua "save safety").
-- Channel: SmartLanes.auto { op = "traffic", nodes = { {n, x, y, t, k, d, v, d3, v3 [, pt, pd, pv]}, ... },
-- src = "tool" }. The tool sends the previous result itself (it knows it at the start of a recording); a checkpoint
-- of the same recording sends the same previous, so it never becomes the recording's own earlier checkpoint.
-- (sl_auto.lua validates it with Rec.entryOf; at most Rec.EVENT_MAX records per event).

local Rec = {}

Rec.BUCKET_S = 30      -- game s per bucket
Rec.MAX_S = 1200       -- game s: a recording ends after 20 game minutes
Rec.RECENT_S = 180     -- game s: the "last 3 min" rate
Rec.EVERY_S = 5        -- game s between two samples
Rec.BUDGET_S = 0.001   -- s of clock per frame for the recordings' one shared sampler, however many run (Re-time's
                       -- has 1.5 ms of its own)
Rec.MAX_RUNNING = 20   -- recordings at once (each at its own junction or roundabout)
Rec.EXIST_MAX = 32     -- junction-still-there reads per sample over all running recordings (round robin)
Rec.MIN_SAVE_S = 30    -- game s: a recording stopped earlier is not saved
Rec.CHECKPOINT_S = 300 -- game s: a running recording saves its result this often (a quit keeps the last one)
Rec.MAX = 1000         -- saved records
Rec.EVENT_MAX = 60     -- records per event
Rec.R = 2              -- m, position match radius
Rec.ROUND = 0.1        -- m
Rec.KIND = { node = 1, ring = 2 }
Rec.KIND_NAME = { "node", "ring" }

local COORD_MAX, ID_MAX, T_MAX, COUNT_MAX = 1e6, 1e12, 1e10, 1e7

local function finite(v, max)
	return type(v) == "number" and v == v and math.abs(v) <= max
end

local function whole(v, max)
	return finite(v, max) and v >= 0 and v == math.floor(v)
end

local function round(v)
	local k = 1 / Rec.ROUND
	return math.floor(v * k + 0.5) / k
end

---------------------------------------------------------------------------
-- The bucket ring

--- A new ring of buckets: slots = MAX_S / BUCKET_S (40), counts by slot, total.
function Rec.newBuckets()
	local n = math.max(1, math.floor(Rec.MAX_S / Rec.BUCKET_S + 0.5))
	local b = { n = n, counts = {}, idx = {}, total = 0, last = -1 }
	for i = 1, n do b.counts[i], b.idx[i] = 0, -1 end
	return b
end

--- Adds k vehicles at `elapsed` game s since the start. A bucket index already passed by the ring is reused for its
-- new index (its old count dropped from the ring, kept in the total). Negative or NaN elapsed / k: ignored.
function Rec.add(b, elapsed, k)
	if type(b) ~= "table" or not finite(elapsed, T_MAX) or elapsed < 0 or not finite(k, COUNT_MAX) or k < 0 then return false end
	local i = math.floor(elapsed / Rec.BUCKET_S)
	local slot = i % b.n + 1
	if b.idx[slot] ~= i then
		b.idx[slot], b.counts[slot] = i, 0
	end
	b.counts[slot] = b.counts[slot] + k
	b.total = b.total + k
	if i > b.last then b.last = i end
	return true
end

--- The vehicles in the buckets with index first .. last (those still in the ring).
local function sumRange(b, first, last)
	local s = 0
	for slot = 1, b.n do
		local i = b.idx[slot]
		if i >= first and i <= last then s = s + b.counts[slot] end
	end
	return s
end

--- The result at `elapsed` game s: { d (s recorded), v (vehicles), d3 / v3 (the recent span: from the start of the
-- bucket RECENT_S / BUCKET_S before the current one, at most the whole) }.
function Rec.result(b, elapsed)
	if type(b) ~= "table" or not finite(elapsed, T_MAX) or elapsed < 0 then return { d = 0, v = 0, d3 = 0, v3 = 0 } end
	local cur = math.floor(elapsed / Rec.BUCKET_S)
	local k = math.floor(Rec.RECENT_S / Rec.BUCKET_S + 0.5)
	local first = math.max(0, cur - k)
	local d3 = elapsed - first * Rec.BUCKET_S
	return { d = elapsed, v = b.total, d3 = d3, v3 = sumRange(b, first, cur) }
end

--- Vehicles per minute of v vehicles in d game s (nil when d <= 0).
function Rec.rate(v, d)
	if not finite(v, COUNT_MAX) or not finite(d, T_MAX) or d <= 0 then return nil end
	return v * 60 / d
end

--- A rate as shown: one decimal under 10 per minute, whole numbers from 10.
function Rec.rateText(r)
	if type(r) ~= "number" or r ~= r then return "-" end
	if r < 9.95 then return string.format("%.1f", r) end
	return string.format("%d", math.floor(r + 0.5))
end

--- Whole minutes of d game s as shown (at least 1).
function Rec.minutes(d)
	if not finite(d, T_MAX) or d < 0 then return 1 end
	return math.max(1, math.floor(d / 60 + 0.5))
end

---------------------------------------------------------------------------
-- Saved records

Rec.FIELDS = 12 -- numbers in a record with its previous result (9 without)

--- One record {n, x, y, t, k, d, v, d3, v3 [, pt, pd, pv]} as a fresh table (whole numbers, position rounded), nil
-- when malformed. A malformed or partial previous (pt / pd / pv) is dropped, the record kept.
function Rec.entryOf(e)
	if type(e) ~= "table" then return nil end
	local n, x, y, t, k, d, v, d3, v3 = e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8], e[9]
	if not whole(n, ID_MAX) then return nil end
	if not finite(x, COORD_MAX) or not finite(y, COORD_MAX) then return nil end
	if not finite(t, T_MAX) or t < 0 then return nil end
	if Rec.KIND_NAME[k] == nil then return nil end
	if not finite(d, 2 * Rec.MAX_S) or d < 0 or not finite(d3, 2 * Rec.MAX_S) or d3 < 0 then return nil end
	if not whole(v, COUNT_MAX) or not whole(v3, COUNT_MAX) then return nil end
	d, d3 = math.floor(d + 0.5), math.floor(d3 + 0.5)
	if d3 > d or v3 > v then return nil end
	local r = { n, round(x), round(y), math.floor(t + 0.5), k, d, v, d3, v3 }
	local pt, pd, pv = e[10], e[11], e[12]
	if finite(pt, T_MAX) and pt >= 0 and finite(pd, 2 * Rec.MAX_S) and pd > 0 and whole(pv, COUNT_MAX) then
		r[10], r[11], r[12] = math.floor(pt + 0.5), math.max(1, math.floor(pd + 0.5)), pv
	end
	return r
end

--- A record of a recording's result (res: Rec.result) at game s t; kind "node" | "ring"; prev: the result it replaces
-- there ({ t, d, v }, as Rec.parts(...).prev or Rec.prevOf), nil: none. nil when malformed.
function Rec.record(kind, n, x, y, t, res, prev)
	if Rec.KIND[kind] == nil or type(res) ~= "table" then return nil end
	local e = { n, x, y, t, Rec.KIND[kind], res.d, res.v, res.d3, res.v3 }
	if type(prev) == "table" then e[10], e[11], e[12] = prev.t, prev.d, prev.v end
	return Rec.entryOf(e)
end

--- The parts of a record: { kind, n, t, d, v, d3, v3, prev = { t, d, v } | nil }, nil when malformed.
function Rec.parts(e)
	local r = Rec.entryOf(e)
	if r == nil then return nil end
	local prev = nil
	if r[10] ~= nil then prev = { t = r[10], d = r[11], v = r[12] } end
	return { kind = Rec.KIND_NAME[r[5]], n = r[1], t = r[4], d = r[6], v = r[7], d3 = r[8], v3 = r[9], prev = prev }
end

--- The previous result a new recording at a junction keeps: the saved record's own result ({ t, d, v }), nil without
-- a (well-formed) record.
function Rec.prevOf(e)
	local p = Rec.parts(e)
	if p == nil then return nil end
	return { t = p.t, d = p.d, v = p.v }
end

local CELL = 2 * Rec.R
local function cellKey(cx, cy) return (cx + 0) .. ":" .. (cy + 0) end

--- A lookup of a saved list: per kind, by id and a grid of CELL m; list = the cleaned entries (at most MAX).
function Rec.index(list)
	local idx = { n = 0, list = {}, byId = { {}, {} }, grid = { {}, {} } }
	if type(list) ~= "table" then return idx end
	for i = 1, math.min(#list, Rec.MAX) do
		local e = Rec.entryOf(list[i])
		if e ~= nil then
			idx.n = idx.n + 1
			idx.list[idx.n] = e
			local k = e[5]
			idx.byId[k][e[1]] = e
			local key = cellKey(math.floor(e[2] / CELL), math.floor(e[3] / CELL))
			local g = idx.grid[k]
			g[key] = g[key] or {}
			table.insert(g[key], e)
		end
	end
	return idx
end

--- The record of kind ("node" | "ring") with id n, else the nearest of that kind within R m of (x, y); nil.
function Rec.match(idx, kind, n, x, y)
	local k = Rec.KIND[kind]
	if type(idx) ~= "table" or k == nil or (idx.n or 0) == 0 then return nil end
	if n ~= nil and idx.byId[k][n] ~= nil then return idx.byId[k][n] end
	if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y then return nil end
	local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
	local best, bestD = nil, nil
	for dx = -1, 1 do
		for dy = -1, 1 do
			for _, e in ipairs(idx.grid[k][cellKey(cx + dx, cy + dy)] or {}) do
				local ex, ey = e[2] - x, e[3] - y
				local d = ex * ex + ey * ey
				if d <= Rec.R * Rec.R and (bestD == nil or d < bestD) then best, bestD = e, d end
			end
		end
	end
	return best
end

--- The records after a "traffic" event: a fresh list, the matched record (same kind, by id or within R m) replaced,
-- a new one appended; beyond MAX the oldest (least t) dropped. Returns the list and stats { replaced, added,
-- dropped, changed }. Bounded: one index of the list (MAX), EVENT_MAX lookups, at most one sort.
function Rec.apply(list, records)
	local idx = Rec.index(list)
	local cur = idx.list
	local st = { replaced = 0, added = 0, dropped = 0, changed = false }
	for i = 1, math.min(#(records or {}), Rec.EVENT_MAX) do
		local e = Rec.entryOf(records[i])
		if e ~= nil then
			local hit = Rec.match(idx, Rec.KIND_NAME[e[5]], e[1], e[2], e[3])
			if hit ~= nil then
				local same = true
				for j = 1, Rec.FIELDS do
					if hit[j] ~= e[j] then same = false end
				end
				if not same then
					local oldId = hit[1]
					for j = 1, Rec.FIELDS do hit[j] = e[j] end
					if oldId ~= e[1] then
						idx.byId[e[5]][oldId] = nil
						idx.byId[e[5]][e[1]] = hit
					end
					st.replaced = st.replaced + 1
				end
			else
				cur[#cur + 1] = e
				idx.n = idx.n + 1
				idx.byId[e[5]][e[1]] = e
				local key = cellKey(math.floor(e[2] / CELL), math.floor(e[3] / CELL))
				local g = idx.grid[e[5]]
				g[key] = g[key] or {}
				table.insert(g[key], e)
				st.added = st.added + 1
			end
		end
	end
	if #cur > Rec.MAX then
		local over = #cur - Rec.MAX
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

---------------------------------------------------------------------------
-- Texts (translated when called: the tool's GUI Lua state)

--- The rates line of a result (res: { d, v, d3, v3 } or a record's parts); kind "ring": the vehicles entering. With
-- the recent span covering the whole recording only one rate. nil before the first bucket is over.
function Rec.ratesLine(kind, res)
	if type(res) ~= "table" or not finite(res.d, T_MAX) or res.d < Rec.BUCKET_S then return nil end
	local all = Rec.rateText(Rec.rate(res.v, res.d))
	local ring = kind == "ring"
	if (res.d3 or 0) >= res.d or res.d <= Rec.RECENT_S then
		if ring then return string.format(_("Vehicles entering per minute: %s (%d min)"), all, Rec.minutes(res.d)) end
		return string.format(_("Vehicles per minute: %s (%d min)"), all, Rec.minutes(res.d))
	end
	local recent = Rec.rateText(Rec.rate(res.v3, res.d3))
	if ring then
		return string.format(_("Vehicles entering per minute: %s (last %d min), %s (all %d min)"), recent,
			Rec.minutes(res.d3), all, Rec.minutes(res.d))
	end
	return string.format(_("Vehicles per minute: %s (last %d min), %s (all %d min)"), recent, Rec.minutes(res.d3), all,
		Rec.minutes(res.d))
end

--- The running recording's head line: "Recording traffic: 7 of 20 min" (whole minutes elapsed).
function Rec.runningLine(elapsed)
	local el = (finite(elapsed, T_MAX) and elapsed > 0) and math.floor(elapsed / 60) or 0
	return string.format(_("Recording traffic: %d of %d min"), math.min(el, math.floor(Rec.MAX_S / 60)),
		math.floor(Rec.MAX_S / 60))
end

--- A saved record's lines: "Traffic recorded 12 min ago (20 min)" and its rates line. ago: the translated "12 min
-- ago" of its game s. nil when malformed.
function Rec.savedLines(e, ago)
	local p = Rec.parts(e)
	if p == nil then return nil end
	local lines = { string.format(_("Traffic recorded %s (%d min)"), tostring(ago), Rec.minutes(p.d)) }
	local r = Rec.ratesLine(p.kind, p)
	if r ~= nil then lines[#lines + 1] = r end
	return lines
end

--- The previous recording's line, to compare (shown muted): "Previous recording: 12 vehicles per minute (20 min, 2 h
-- ago)" (a roundabout: "vehicles entering per minute"); its whole-recording rate. prev: { t, d, v } (Rec.parts(...).prev
-- or Rec.prevOf); ago: the translated "2 h ago" of its game s. nil without a previous.
function Rec.prevLine(kind, prev, ago)
	if type(prev) ~= "table" then return nil end
	local r = Rec.rate(prev.v, prev.d)
	if r == nil then return nil end
	if kind == "ring" then
		return string.format(_("Previous recording: %s vehicles entering per minute (%d min, %s)"), Rec.rateText(r),
			Rec.minutes(prev.d), tostring(ago))
	end
	return string.format(_("Previous recording: %s vehicles per minute (%d min, %s)"), Rec.rateText(r),
		Rec.minutes(prev.d), tostring(ago))
end

return Rec
