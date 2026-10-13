-- Stress Test traffic log, the pure part (plans/square_stress_test/FLOW_PLAN.md steps 4-5; the line contract is
-- plans/square_stress_test/FLOW.md): zones (from the session's Showcase or Smart Lanes' saved zones), the zone
-- lookup, per-sample aggregation of the sampled drivers, bus lap detection and every [SQST] FLOW_* line.
-- No api use: gui/stress_flow_log.tl reads the game (Main Thread, sliced) and feeds this module.
--
-- Units (docs/findings/lines-vehicles.md "Units", probe 11a): dyn.speed m/s, timeStanding s, GAME_TIME.gameTime
-- and lineStopDepartures game ms (GT_PER_S = 1000 per game second), sectionTimes s.

local flow : SquareStressFlow = {
	VERSION = 3,               -- FLOW_START v=: 2 = interval in game seconds, zone membership by position; 3 = every
	                           -- driver read (adaptive target), zones measured out along their arms (r_measure, q_arm)
	STAND_SPEED = 0.5,         -- m/s: a car below this stands
	QUEUE_S = 5.0,             -- s: a standing car with timeStanding >= this is queued (FLOW.md queue=)
	GRID_CELL = 250.0,         -- m: zone lookup bucket size
	GT_PER_S = 1000,           -- gameTime units per game second (ms)
	INTERVALS = { 10, 30, 60 },  -- game seconds between samples (Traffic tab), default index 2
	SUMMARY_EVERY = 10,        -- a FLOW_SUMMARY every this many samples (and at the stop)
	CAP = 0,                   -- drivers read (MOVE_PATH + position) per sweep at the start of a run: 0 = every one
	TARGET_MIN = 3000,         -- a lowered per-sweep target never goes below this (the v2 cap)
	TARGET_DROP = 0.75,        -- a sweep that could not finish within its interval: target = drivers read so far x this
	MEASURE_PAD = 200.0,       -- m: a zone is measured out to r + this along its arms (r_measure; FLOW.md)
	CORRIDOR_HALF = 15.0,      -- m: half the width of an arm's corridor (a 3-lanes-each-way country road is 30 m)
	IX_CORRIDOR_HALF = 25.0,   -- m: the same for an interchange's arms (a highway's two carriageways side by side)
	TOWN_LINES_MAX = 100,      -- FLOW_TOWNS scope=town lines per sample at most
	VALUE_MAX = 200,           -- characters of one value (lists cut with +N)
	DRIVE_SIDE = "right",      -- the map's driving side for q_in / q_out (the sampler sets it from rt.drivingSide)
	THRU_R = 40.0,             -- m: a junction's own streets (thru): street edges whose middle lies this close to its centre
	THRU_TRACK = 600.0,        -- m: drivers this close to a zone's centre are checked for a path through it (thru), at least;
	                           -- thruTrack(interval) widens it to THRU_SPEED x the interval (at most THRU_TRACK_MAX)
	THRU_SPEED = 20.0,         -- m/s: a car this fast covers the track radius within one interval (thruTrack)
	THRU_TRACK_MAX = 1200.0,   -- m: the widest track radius (the path window must still reach the junction)
	THRU_WINDOW = 32,          -- path edges looked at ahead of (and behind) a driver's position (thru)
}

---------------------------------------------------------------------------
-- Formatting

--- A number as FLOW.md writes it: "-" for nil / NaN / inf, integers "%d", others "%.3g".
function flow.num(v : number) : string
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return "-" end
	if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
	return string.format("%.3g", v)
end

--- A value without whitespace (spaces -> "_"), "-" when empty or nil, at most VALUE_MAX characters.
function flow.word(s : string) : string
	if s == nil then return "-" end
	local w = (tostring(s):gsub("%s+", "_"))
	if #w == 0 then return "-" end
	if #w > flow.VALUE_MAX then w = w:sub(1, flow.VALUE_MAX) end
	return w
end

--- "a,b,c" of numbers, at most max entries, "+N" for the rest ("-" when empty).
function flow.list(v : {number}, max : integer) : string
	if v == nil or #v == 0 then return "-" end
	local parts : {string} = {}
	for i, x in ipairs(v) do
		if i > max then parts[#parts + 1] = "+" .. tostring(#v - max) break end
		parts[#parts + 1] = flow.num(x)
	end
	return table.concat(parts, ",")
end

--- "k:v,..." most frequent first ("-" when empty).
function flow.counts(m : {string : integer}) : string
	local keys : {string} = {}
	for k, n in pairs(m or {}) do if n > 0 then keys[#keys + 1] = k end end
	if #keys == 0 then return "-" end
	table.sort(keys, function(a : string, b : string) : boolean
		if m[a] ~= m[b] then return m[a] > m[b] end
		return a < b
	end)
	local parts : {string} = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. tostring(m[k]) end
	return table.concat(parts, ",")
end

local function median(v : {number}) : number
	local n = #v
	if n == 0 then return nil end
	local s : {number} = {}
	for i, x in ipairs(v) do s[i] = x end
	table.sort(s)
	if n % 2 == 1 then return s[(n + 1) // 2] end
	return (s[n // 2] + s[n // 2 + 1]) / 2
end
flow.median = median

---------------------------------------------------------------------------
-- Zones

local KIND : {string : string} = { ix = "ix", rb = "rb", plain = "x" }

--- The FLOW_ZONE kind of a Showcase kind (ix / rb / plain -> ix / rb / x; anything else "other").
function flow.kindOf(k : string) : string
	return KIND[k] or "other"
end

local function finite(v : any) : boolean
	return type(v) == "number" and v == v and math.abs(v as number) < 1e9
end

local atan2 = math.atan2 or math.atan
local COMPASS : {string} = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

--- The compass point of a heading (map +y north, +x east): "N", "NE", ...
function flow.compass(hx : number, hy : number) : string
	local deg = math.deg(atan2(hy, hx))
	local bearing = (90 - deg) % 360
	return COMPASS[math.floor(bearing / 45 + 0.5) % 8 + 1]
end

--- A zone's measured area (FLOW.md "Measured area", v3): the junction's circle r, and along each of its arms
--- (unit headings, the read's measured arm directions) a corridor CORRIDOR_HALF to each side out to r_measure
--- = r + MEASURE_PAD from the centre (the approach roads, where the queues stand). Without arms (Smart Lanes'
--- saved zones after a reload: no headings) the whole circle r_measure ("circle"). Arms are sorted by compass
--- point (N, NE, E, ... order) so q_arm reads the same in every twin.
function flow.withMeasure(z : SquareStressFlowZone, arms : {{number}}) : SquareStressFlowZone
	z.rm = z.r + flow.MEASURE_PAD
	z.arms, z.armNames = nil, nil
	local list : {{number}} = {}
	for _, a in ipairs(arms or {}) do
		local hx, hy = a[1], a[2]
		local l = (finite(hx) and finite(hy)) and math.sqrt(hx * hx + hy * hy) or 0
		if l > 0 then list[#list + 1] = { hx / l, hy / l } end
	end
	if #list == 0 then
		z.measure = "circle"
		return z
	end
	local order : {string : integer} = {}
	for i, c in ipairs(COMPASS) do order[c] = i end
	table.sort(list, function(a : {number}, b : {number}) : boolean
		local ca, cb = order[flow.compass(a[1], a[2])], order[flow.compass(b[1], b[2])]
		if ca ~= cb then return ca < cb end
		if a[1] ~= b[1] then return a[1] < b[1] end
		return a[2] < b[2]
	end)
	z.measure = "corridor"
	z.arms = list
	z.armNames = {}
	for i, a in ipairs(list) do z.armNames[i] = flow.compass(a[1], a[2]) end
	return z
end

--- The traffic-log zones of the session's Showcase: only the twins whose zone line was written (built and
--- read), with the measured r and the read's arm headings. Zone numbers 1..n in list order.
function flow.zonesFromShowcase(list : {SquareStressShowcaseZone}, run : string) : {SquareStressFlowZone}
	local out : {SquareStressFlowZone} = {}
	for _, z in ipairs(list or {}) do
		if z.built and finite(z.x) and finite(z.y) and finite(z.r) and z.r > 0 then
			out[#out + 1] = flow.withMeasure({ zone = #out + 1, twin = z.id, pair = z.pair, ab = z.ab, kind = flow.kindOf(z.kind),
				src = "placement", label = flow.word(z.label), x = z.x, y = z.y, r = z.r, match = z.reason == nil and "yes" or "no",
				reason = z.reason, idFrom = "showcase", scRun = run, test = z.test, approach = z.approach }, z.arms)
		end
	end
	return out
end

-- twin letters per A/B mode (stress_logic SHOWCASE_AB: sl a, game b, sl_phases c; the Lights showcase's fourth
-- twin d: sl_lock since 2026-10-13, Smart Lanes' kerb-locked mode; sl_fan before, still read from older saves)
local TWIN_ORDER : {string : integer} = { sl = 1, game = 2, sl_phases = 3, sl_fan = 4, sl_lock = 5, sl_exitfan = 6, sl_keeplights = 7 }
-- sl_exitfan e: the mixed Lights showcase's third twin; sl_keeplights f: the bench's lights twin (BENCH.md)
local TWIN_LETTER : {string} = { "a", "b", "c", "d", "d", "e", "f" }

--- The zones Smart Lanes saved ({x, y, r, ab, id?, pair?}; r = the Showcase's reach estimate + 20 m pad),
--- after a reload. Twin ids: the stored id / pair labels (idFrom "sl"); without them (an older Smart Lanes)
--- recomputed from the payload order, which is the Showcase's group order (sets in order, each set's twins
--- in SHOWCASE_AB order sl, game, sl_phases): a new set starts whenever a twin does not come after the
--- previous one (idFrom "order"). Broken entries are skipped.
function flow.zonesFromSaved(list : {{string : any}}, run : string) : {SquareStressFlowZone}
	local out : {SquareStressFlowZone} = {}
	local set, prev = 0, 99
	for _, z in ipairs(list or {}) do
		local x, y, r, ab = z.x, z.y, z.r, z.ab
		if finite(x) and finite(y) and finite(r) and (r as number) > 0 and type(ab) == "string" then
			local abs = ab as string
			local o = TWIN_ORDER[abs] or 9
			if o <= prev then set = set + 1 end
			prev = o
			local id, pair = z.id, z.pair
			local from = "sl"
			if type(id) ~= "string" or type(pair) ~= "string" then
				id = string.format("g%d%s", set, TWIN_LETTER[o] or "x")
				pair = string.format("g%d", set)
				from = "order"
			end
			out[#out + 1] = flow.withMeasure({ zone = #out + 1, twin = id as string, pair = pair as string, ab = abs, kind = "other",
				src = "sl_zones", label = id as string, x = x as number, y = y as number, r = r as number, idFrom = from, scRun = run }, nil)
		end
	end
	return out
end

local function cellKey(cx : integer, cy : integer) : integer
	return (cx + 50000) * 100003 + (cy + 50000)
end

--- A grid of the zones (each in every cell its measured circle's box touches: r_measure), so a lookup tests
--- only the zones of one cell. Bounded: a zone wider than 40 cells is checked in every lookup instead (never
--- with real r).
function flow.newIndex(zones : {SquareStressFlowZone}, cell? : number) : SquareStressFlowIndex
	local c = cell or flow.GRID_CELL
	local idx : SquareStressFlowIndex = { cell = c, buckets = {}, zones = zones or {}, wide = {} }
	for i, z in ipairs(idx.zones) do
		local r = math.max(z.r, z.rm or z.r)
		local x0, x1 = math.floor((z.x - r) / c), math.floor((z.x + r) / c)
		local y0, y1 = math.floor((z.y - r) / c), math.floor((z.y + r) / c)
		if (x1 - x0) > 40 or (y1 - y0) > 40 then
			idx.wide[#idx.wide + 1] = i
		else
			for cx = x0, x1 do
				for cy = y0, y1 do
					local k = cellKey(cx, cy)
					local b = idx.buckets[k]
					if b == nil then b = {} idx.buckets[k] = b end
					b[#b + 1] = i
				end
			end
		end
	end
	return idx
end

--- Half the width of a zone's arm corridors: wider at an interchange (two carriageways per arm).
function flow.corridorHalf(z : SquareStressFlowZone) : number
	return z.kind == "ix" and flow.IX_CORRIDOR_HALF or flow.CORRIDOR_HALF
end

--- thru by position (BENCH.md, FLOW.md "thru"): where the offset (dx, dy) from zone z's centre lies on the way
--- through it. 0 the junction (within r), k > 0 inbound on arm k's approach (the corridor's inbound side, out to
--- the zone's approach length: in a square layout the straight link to the towns' entries, where every car on that
--- side is bound for the junction; else r_measure), -k outbound on arm k; nil elsewhere. A zone without arms: 0
--- within r_measure, else nil.
function flow.approachOf(z : SquareStressFlowZone, dx : number, dy : number) : integer
	local d2 = dx * dx + dy * dy
	if d2 <= z.r * z.r then return 0 end
	if z.arms == nil then
		local rm = z.rm or z.r
		return d2 <= rm * rm and 0 or nil
	end
	local len = z.approach or z.rm or z.r
	local half = flow.corridorHalf(z)
	for k, a in ipairs(z.arms) do
		local along = dx * a[1] + dy * a[2]
		if along >= 0 and along <= len then
			local side = dx * a[2] - dy * a[1]
			if side <= half and side >= -half then
				local inbound = side < 0
				if flow.DRIVE_SIDE == "left" then inbound = side > 0 end
				return inbound and k or -k
			end
		end
	end
	return nil
end

--- Cars through a junction between two samples by position: the drivers the previous sample saw on its way in
--- (an inbound approach or the junction itself: prev.posIn) that this one does not see there any more (passed:
--- out on an exit, beyond, or no longer driving: no car on an approach can arrive anywhere before the junction).
--- Every car spends longer than one interval on its approach at the bench's speeds and interval (approach ~520 m,
--- 10 game s), so each is seen at least once whatever the twin's speed. nil unless both samples read the same drivers.
function flow.posCount(prev : SquareStressFlowAcc, now : SquareStressFlowAcc, complete : boolean) : integer
	if not complete or prev == nil or now == nil or prev.posIn == nil or now.posIn == nil then return nil end
	local n = 0
	for d in pairs(prev.posIn) do
		if now.posIn[d] == nil then n = n + 1 end
	end
	return n
end

--- Which part of zone z's measured area holds the offset (dx, dy) from its centre: 0 the junction's circle r,
--- k its arm k's corridor (out to r_measure, CORRIDOR_HALF to each side), also 0 anywhere within r_measure
--- for a zone without arms ("circle"); nil outside.
--- Second result on an arm corridor: 1 inbound (the lane side of traffic towards the junction: right of the
--- heading in, for DRIVE_SIDE "right"; left for "left"), 2 outbound; nil elsewhere.
function flow.partOf(z : SquareStressFlowZone, dx : number, dy : number) : integer, integer
	local d2 = dx * dx + dy * dy
	if d2 <= z.r * z.r then return 0, nil end
	local rm = z.rm or z.r
	if d2 > rm * rm then return nil, nil end
	if z.arms == nil then return 0, nil end
	local half = flow.corridorHalf(z)
	for k, a in ipairs(z.arms) do
		local along = dx * a[1] + dy * a[2]
		if along >= 0 then
			local side = dx * a[2] - dy * a[1]
			if side <= half and side >= -half then
				-- side < 0: left of the outward heading = right of the way in
				local inbound = side < 0
				if flow.DRIVE_SIDE == "left" then inbound = side > 0 end
				return k, inbound and 1 or 2
			end
		end
	end
	return nil, nil
end

--- Fills out[1..n] with the zones (indices) whose measured area holds (x, y) (flow.partOf) and, when given,
--- parts[1..n] with the part (0 the junction, k arm k); returns n. A car in overlapping zones counts in each.
function flow.zonesAt(idx : SquareStressFlowIndex, x : number, y : number, out : {integer}, parts? : {integer}, dirs? : {integer}) : integer
	local n = 0
	if idx == nil or x == nil or y == nil then return 0 end
	local function test(i : integer)
		local z = idx.zones[i]
		local part, dir = flow.partOf(z, x - z.x, y - z.y)
		if part ~= nil then
			n = n + 1
			out[n] = i
			if parts ~= nil then parts[n] = part end
			if dirs ~= nil then dirs[n] = dir or 0 end
		end
	end
	local b = idx.buckets[cellKey(math.floor(x / idx.cell), math.floor(y / idx.cell))]
	if b ~= nil then for _, i in ipairs(b) do test(i) end end
	for _, i in ipairs(idx.wide) do test(i) end
	return n
end

---------------------------------------------------------------------------
-- Aggregation

function flow.newAcc() : SquareStressFlowAcc
	return { cars = 0, standing = 0, queue = 0, vSum = 0.0, speeds = {}, standSum = 0.0, standMax = nil, core = 0, qArm = {}, qIn = {}, qOut = {},
		ahead = {}, passed = {}, posIn = {} }
end

function flow.newSample(nZones : integer) : SquareStressFlowSample
	local zs : {SquareStressFlowAcc} = {}
	for i = 1, nZones do zs[i] = flow.newAcc() end
	return { zones = zs, all = flow.newAcc(), inZones = 0, drivers = 0, sampled = 0, posFail = 0, target = nil, stride = 1 }
end

--- One car into an acc; part (zones only): 0 in the junction's circle (core), k on arm k's corridor (a queued
--- car there counts in qArm[k]).
local function addTo(a : SquareStressFlowAcc, speed : number, ts : number, part : integer, dir? : integer)
	a.cars = a.cars + 1
	a.vSum = a.vSum + speed
	a.speeds[#a.speeds + 1] = speed
	if part == 0 then a.core = (a.core or 0) + 1 end
	if speed < flow.STAND_SPEED then
		a.standing = a.standing + 1
		local t = ts or 0
		a.standSum = a.standSum + t
		if a.standMax == nil or t > a.standMax then a.standMax = t end
		if t >= flow.QUEUE_S then
			a.queue = a.queue + 1
			if part ~= nil and part > 0 and a.qArm ~= nil then
				a.qArm[part] = (a.qArm[part] or 0) + 1
				if dir == 1 and a.qIn ~= nil then a.qIn[part] = (a.qIn[part] or 0) + 1 end
				if dir == 2 and a.qOut ~= nil then a.qOut[part] = (a.qOut[part] or 0) + 1 end
			end
		end
	end
end

--- One sampled car: into the map-wide totals and into each of the n zones in zs (zonesAt), parts[k] its part
--- of zone zs[k] (nil parts: the junction's circle). A nil speed (unreadable) is not counted at all.
function flow.addCar(s : SquareStressFlowSample, zs : {integer}, n : integer, speed : number, timeStanding : number, parts? : {integer},
		dirs? : {integer})
	if speed == nil or speed ~= speed then return end
	if speed < 0 then speed = -speed end
	addTo(s.all, speed, timeStanding, nil)
	if n > 0 then
		s.inZones = s.inZones + 1
		for k = 1, n do
			local a = s.zones[zs[k]]
			if a ~= nil then addTo(a, speed, timeStanding, parts ~= nil and parts[k] or 0, dirs ~= nil and dirs[k] or nil) end
		end
	end
end

--- Car-weighted mean speed (m/s), median, mean / max timeStanding of the standing cars (nil when none).
function flow.accStats(a : SquareStressFlowAcc) : number, number, number, number
	if a.cars == 0 then return nil, nil, nil, nil end
	local standMean : number = a.standing > 0 and a.standSum / a.standing or nil
	return a.vSum / a.cars, median(a.speeds), standMean, a.standMax
end

---------------------------------------------------------------------------
-- Lines (FLOW.md; keys are only ever added, never renamed)

local N = flow.num

local function twinKeys(z : SquareStressFlowZone) : string
	if z.twin == nil then return "twin=-" end
	return string.format("twin=%s pair=%s ab=%s", flow.word(z.twin), flow.word(z.pair), flow.word(z.ab))
end

function flow.startLine(o : SquareStressFlowStart) : string
	return string.format("[SQST] FLOW_START run=%d v=%d interval=%d interval_unit=game_s zones=%d towns=%s buses=%s speed=%s keep_cleared=%d cap=%d gt=%s gt_per_s=%d src=%s sc_run=%s budget_us=%d target_min=%d measure_pad=%.0f corridor_m=%.0f drive_side=%s thru_r=%.0f thru_track=%.0f thru_window=%d thru_m=pos ix_corridor_m=%.0f path_thru=%s",
		o.run, flow.VERSION, o.interval, o.zones, N(o.towns), N(o.buses), N(o.speed), o.keepCleared and 1 or 0, o.cap, N(o.gt),
		flow.GT_PER_S, flow.word(o.src), flow.word(o.scRun), o.budgetUs, flow.TARGET_MIN, flow.MEASURE_PAD, 2 * flow.CORRIDOR_HALF,
		flow.DRIVE_SIDE, flow.THRU_R, flow.thruTrack(o.interval), flow.THRU_WINDOW, 2 * flow.IX_CORRIDOR_HALF, o.pathThru == false and "off" or "on")
end

function flow.zoneLine(run : integer, z : SquareStressFlowZone) : string
	local s = string.format("[SQST] FLOW_ZONE run=%d zone=%d kind=%s src=%s label=%s x=%.0f y=%.0f r=%.0f %s sc_run=%s id_from=%s",
		run, z.zone, z.kind, z.src, flow.word(z.label), z.x, z.y, z.r, twinKeys(z), flow.word(z.scRun), z.idFrom or "-")
	if z.match ~= nil then s = s .. " match=" .. z.match end
	if z.reason ~= nil then s = s .. " reason=" .. flow.word(z.reason) end
	s = s .. string.format(" r_measure=%.0f measure=%s arms=%s", z.rm or z.r, z.measure or "circle",
		z.armNames ~= nil and #z.armNames > 0 and table.concat(z.armNames, ",") or "-")
	-- keys only added: the positional thru's approach length, the bench test
	s = s .. string.format(" approach=%s", z.approach ~= nil and string.format("%.0f", z.approach) or "-")
	if z.test ~= nil then s = s .. " test=" .. flow.word(z.test) end
	return s
end

local function accText(a : SquareStressFlowAcc) : string
	local v, med, sm, smax = flow.accStats(a)
	local pct : number = a.cars > 0 and math.floor(a.standing / a.cars * 1000 + 0.5) / 10 or nil
	return string.format("cars=%d standing=%d standing_pct=%s queue=%d v_mean=%s v_med=%s v_kmh=%s stand_mean=%s stand_max=%s",
		a.cars, a.standing, N(pct), a.queue, N(v), N(med), v ~= nil and N(math.floor(v * 36 + 0.5) / 10) or "-", N(sm), N(smax))
end

--- "N:3,E:0,S:12,W:1": queued cars (standing >= QUEUE_S) per arm corridor, in the zone's arm order ("-"
--- without arms).
--- which: the per-arm counts to write (nil: qArm, both directions; a.qIn / a.qOut: inbound / outbound only).
function flow.qArmText(z : SquareStressFlowZone, a : SquareStressFlowAcc, which? : {integer}) : string
	if z.armNames == nil or #z.armNames == 0 then return "-" end
	local m = which or a.qArm or {}
	local parts : {string} = {}
	for k, name in ipairs(z.armNames) do parts[k] = string.format("%s:%d", name, m[k] or 0) end
	return table.concat(parts, ",")
end

--- Where a driver stands relative to a junction on its path (thru): "ahead" when one of the next THRU_WINDOW
--- path edges (from its position, index cur, 0-based) is one of the junction's own (set), "passed" when none
--- ahead but one of the THRU_WINDOW behind it is, else nil (no path through it near here). get(i): the entity
--- of path edge i (0-based, nil when unreadable); n: the path's edge count.
--- ahead only (aheadOnly): no look behind (a driver that did not have it ahead last time: its pass would not count).
function flow.pathState(get : function(i : integer) : integer, n : integer, cur : integer, set : {integer : boolean}, w? : integer,
		aheadOnly? : boolean) : string
	if get == nil or set == nil or n == nil or cur == nil or cur < 0 then return nil end
	local win = w or flow.THRU_WINDOW
	for i = cur, math.min(n - 1, cur + win - 1) do
		local e = get(i)
		if e ~= nil and set[e] then return "ahead" end
	end
	if aheadOnly then return nil end
	for i = cur - 1, math.max(0, cur - win), -1 do
		local e = get(i)
		if e ~= nil and set[e] then return "passed" end
	end
	return nil
end

--- Cars through a junction between two samples: the drivers it had ahead (prev.ahead) that it has now passed
--- (now.passed). nil when either sample did not read every driver (a target or stride: drivers missing).
function flow.thruCount(prev : SquareStressFlowAcc, now : SquareStressFlowAcc, complete : boolean) : integer
	if not complete or prev == nil or now == nil or prev.ahead == nil or now.passed == nil then return nil end
	local n = 0
	for d in pairs(prev.ahead) do
		if now.passed[d] then n = n + 1 end
	end
	return n
end

--- One zone's line of a sample (also when no car was in it: cars=0, the rest "-" / 0). cars and the rest count
--- the whole measured area (v3); cars_core only the junction's circle r (the v2 zone); q_arm per arm corridor.
--- thru: cars through the junction since the previous sample (thruCount, already x thruScale; nil "-"), thruS its
--- game seconds, thruScale the stride it was counted on (1: every driver; k: every k-th by id, x k; nil "-").
--- thruPath: the same count from the drivers' paths (the first method; nil "-" while no path element reads).
function flow.flowLine(run : integer, s : integer, gt : number, z : SquareStressFlowZone, a : SquareStressFlowAcc, thru? : integer,
		thruS? : number, thruScale? : integer, thruPath? : integer) : string
	return string.format("[SQST] FLOW run=%d s=%d zone=%d %s gt=%s %s cars_core=%d q_arm=%s q_in=%s q_out=%s thru=%s thru_s=%s thru_scale=%s thru_path=%s", run, s,
		z.zone, twinKeys(z), N(gt), accText(a), a.core or 0, flow.qArmText(z, a), flow.qArmText(z, a, a.qIn or {}),
		flow.qArmText(z, a, a.qOut or {}), N(thru), N(thruS), N(thruScale), N(thruPath))
end

function flow.allLine(run : integer, s : integer, gt : number, smp : SquareStressFlowSample, sw : SquareStressFlowSweepCost) : string
	local a = smp.all
	return string.format("[SQST] FLOW_ALL run=%d s=%d gt=%s drivers=%d sampled=%d in_zones=%d %s persons=%d pos_fail=%d frames=%d sweep_ms=%s elapsed_ms=%s capped=%d target=%s stride=%d frame_ms_max=%s drivers_est=%d frame_phase=%s",
		run, s, N(gt), smp.drivers, smp.sampled, smp.inZones, (accText(a):gsub("^cars=%d+ ", "")), sw.persons, smp.posFail, sw.frames,
		N(math.floor(sw.busyUs / 100 + 0.5) / 10), N(math.floor(sw.elapsedUs / 1000 + 0.5)), smp.sampled < smp.drivers and 1 or 0,
		(smp.target == nil or smp.target <= 0) and "all" or tostring(smp.target), smp.stride or 1,
		N(math.floor((sw.frameMaxUs or 0) / 100 + 0.5) / 10), smp.driversEst and 1 or 0, flow.word(sw.framePhase))
end

---------------------------------------------------------------------------
-- The per-sweep target (v3: every driver read unless a sweep can't finish within its interval)

--- The lowered target after a sample came due while a sweep still ran: the drivers it had read by then x
--- TARGET_DROP, never below TARGET_MIN (nor above what it was).
function flow.lowerTarget(target : integer, read : integer) : integer
	local t = math.max(flow.TARGET_MIN, math.floor((read or 0) * flow.TARGET_DROP))
	if target ~= nil and target > 0 and t > target then t = target end
	return t
end

--- A lowered target back up after a sweep that finished in the first half of its interval: target / TARGET_DROP,
--- nil (every driver again) once that covers the drivers found. thru counts again from then on.
--- Whether a sweep that took elapsedGt game time for `sampled` drivers projects `count` drivers within half the
--- interval (intervalGt): elapsedGt x count / sampled <= intervalGt / 2 (count >= sampled; nothing read: no). With a
--- stride every per-person cost (the driver test too) is paid only for every stride-th person, so the sweep's whole
--- cost scales with count / sampled.
function flow.raiseOk(elapsedGt : number, sampled : integer, count : integer, intervalGt : number) : boolean
	if elapsedGt == nil or sampled == nil or sampled <= 0 or count == nil or intervalGt == nil or intervalGt <= 0 then return false end
	return elapsedGt * math.max(count, sampled) / sampled <= intervalGt / 2
end

function flow.raiseTarget(target : integer, drivers : integer) : integer
	if target == nil or target <= 0 then return nil end
	local t = math.ceil(target / flow.TARGET_DROP)
	if drivers == nil or t >= drivers then return nil end
	return t
end

--- The thru track radius for a sampling interval (game s): THRU_SPEED x interval, between THRU_TRACK and
--- THRU_TRACK_MAX (a car that far out at one sample can have passed by the next).
function flow.thruTrack(intervalS : number) : number
	local r = flow.THRU_SPEED * (intervalS or 0)
	return math.max(flow.THRU_TRACK, math.min(flow.THRU_TRACK_MAX, r))
end

--- Every how many drivers one is read so that about `target` of the previous sweep's `drivers` are (1: every
--- one; target nil / 0: no target). Spread over the whole list, so a capped sample is not just the persons
--- listed first.
function flow.stride(target : integer, drivers : integer) : integer
	if target == nil or target <= 0 or drivers == nil or drivers <= target then return 1 end
	return math.ceil(drivers / target)
end

--- "[SQST] FLOW_TARGET run= s= target= was= read= drivers_prev= reason=": the target lowered (FLOW.md).
function flow.targetLine(run : integer, s : integer, target : integer, was : integer, read : integer, driversPrev : integer, reason : string) : string
	return string.format("[SQST] FLOW_TARGET run=%d s=%d target=%s was=%s read=%d drivers_prev=%s reason=%s", run, s,
		(target == nil or target <= 0) and "all" or tostring(target),
		(was == nil or was <= 0) and "all" or tostring(was), read or 0, N(driversPrev), flow.word(reason))
end

---------------------------------------------------------------------------
-- Towns (computeTownsTrafficSpeedMap: {town: {speed, {streets per level}}})

--- The FLOW_TOWNS lines: one scope=all line, then one scope=town line per town (at most TOWN_LINES_MAX,
--- slowest first). names(town) gives a town's name (nil: its id).
function flow.townsLines(run : integer, s : integer, gt : number, m : {integer : {any}}, coef : number, ms : number,
		names : function(town : integer) : string) : {string}
	local towns : {{any}} = {}
	local levels : {number} = {}
	local sum, n = 0.0, 0
	local min : number = nil
	for town, v in pairs(m or {}) do
		local sp = type(v) == "table" and v[1] or nil
		local lv = type(v) == "table" and v[2] or nil
		if type(sp) == "number" then
			local x = sp as number
			sum, n = sum + x, n + 1
			if min == nil or x < min then min = x end
		end
		local lvl : {number} = {}
		if type(lv) == "table" then
			for i, c in ipairs(lv as {number}) do
				if type(c) ~= "number" then break end
				lvl[i] = c
				levels[i] = (levels[i] or 0) + c
			end
		end
		towns[#towns + 1] = { town, sp, lvl }
	end
	local out : {string} = {}
	out[1] = string.format("[SQST] FLOW_TOWNS run=%d s=%d gt=%s scope=all towns=%d speed_mean=%s speed_min=%s levels=%s coef=%s ms=%s",
		run, s, N(gt), #towns, N(n > 0 and sum / n or nil), N(min), flow.list(levels, 12), N(coef), N(ms))
	table.sort(towns, function(a : {any}, b : {any}) : boolean
		local sa, sb = a[2], b[2]
		if type(sa) ~= "number" then return false end
		if type(sb) ~= "number" then return true end
		if sa ~= sb then return (sa as number) < (sb as number) end
		return (a[1] as integer) < (b[1] as integer)
	end)
	for i, t in ipairs(towns) do
		if i > flow.TOWN_LINES_MAX then break end
		local id = t[1] as integer
		out[#out + 1] = string.format("[SQST] FLOW_TOWNS run=%d s=%d gt=%s scope=town town=%d name=%s speed=%s levels=%s",
			run, s, N(gt), id, flow.word(names ~= nil and names(id) or tostring(id)), N(type(t[2]) == "number" and t[2] as number or nil),
			flow.list(t[3] as {number}, 12))
	end
	return out
end

---------------------------------------------------------------------------
-- Buses

--- One vehicle of a bus line into the line's acc. laps: vehicle -> its last departure from the line's
--- first stop (lineStopDepartures[1], game ms) seen at an earlier sample (run state). A lap is completed
--- when that departure moved on: lap = new - old (game s, dwell included; one lap per sample at most, so
--- an interval longer than a round trip would count two laps as one: interval <= 60 s, Showcase laps ~6
--- min). A departure that went back (the vehicle's history was wiped, e.g. re-sent to its line) restarts.
--- Round trip rt = sum of sectionTimes (s, without dwell) when it has one entry per stop, all > 0.
--- depAge = gt - lastLineStopDeparture (game s) when that is set. **Provisional** (FLOW.md: probe 11f not run).
function flow.busVehicle(acc : SquareStressFlowBus, laps : {integer : number}, v : integer, tv : SquareStressFlowTv, stops : integer, gt : number)
	acc.vehicles = acc.vehicles + 1
	local dep = tv.deps ~= nil and tv.deps[1] or nil
	if type(dep) == "number" and dep > 0 then
		local prev = laps[v]
		if prev ~= nil and dep > prev then
			acc.laps[#acc.laps + 1] = (dep - prev) / flow.GT_PER_S
		end
		laps[v] = dep
	elseif dep ~= nil then
		laps[v] = nil
	end
	local secs = tv.sections or {}
	if stops ~= nil and stops > 0 and #secs == stops then
		local sum, all = 0.0, true
		for _, x in ipairs(secs) do
			if type(x) ~= "number" or x <= 0 then all = false break end
			sum = sum + x
		end
		if all then acc.rts[#acc.rts + 1] = sum end
	end
	if type(tv.last) == "number" and tv.last > 0 and gt ~= nil then
		local age = (gt - tv.last) / flow.GT_PER_S
		if acc.depAgeMax == nil or age > acc.depAgeMax then acc.depAgeMax = age end
	end
	if acc.rawLast == nil then
		acc.rawLast = tv.last
		acc.rawDeps = tv.deps
		acc.rawSecs = tv.sections
	end
end

function flow.newBus() : SquareStressFlowBus
	return { vehicles = 0, laps = {}, rts = {}, depAgeMax = nil }
end

local function minMaxMean(v : {number}) : number, number, number
	if #v == 0 then return nil, nil, nil end
	local lo, hi, sum = v[1], v[1], 0.0
	for _, x in ipairs(v) do
		if x < lo then lo = x end
		if x > hi then hi = x end
		sum = sum + x
	end
	return lo, hi, sum / #v
end

function flow.busLine(run : integer, s : integer, gt : number, line : integer, name : string, twin : SquareStressLineTwin,
		twinFrom : string, acc : SquareStressFlowBus, stops : integer, freq : number) : string
	local rlo, rhi, rmean = minMaxMean(acc.rts)
	local llo, lhi, lmean = minMaxMean(acc.laps)
	local tw = "twin=-"
	if twin ~= nil then
		tw = string.format("twin=%s pair=%s ab=%s twin_from=%s", flow.word(twin.twin), flow.word(twin.pair), flow.word(twin.ab), twinFrom or "-")
	end
	return string.format("[SQST] FLOW_BUS run=%d s=%d gt=%s line=%d name=%s %s vehicles=%d stops=%s rt_n=%d rt_mean=%s rt_min=%s rt_max=%s lap_n=%d lap_mean=%s lap_min=%s lap_max=%s dep_age_max=%s freq=%s raw_last=%s raw_deps=%s raw_sections=%s",
		run, s, N(gt), line, flow.word(name), tw, acc.vehicles, N(stops), #acc.rts, N(rmean), N(rlo), N(rhi), #acc.laps, N(lmean), N(llo), N(lhi),
		N(acc.depAgeMax), N(freq), N(acc.rawLast), flow.list(acc.rawDeps, 8), flow.list(acc.rawSecs, 8))
end

--- The zone a route line serves, from its two stops (after a reload, when the session's line -> twin map
--- is gone): the line runs between two towns on opposite arms of one junction, so the zone nearest the
--- stops' midpoint, if that is closer than half the stops' distance (else nil).
function flow.twinFromStops(zones : {SquareStressFlowZone}, ax : number, ay : number, bx : number, by : number) : SquareStressFlowZone
	if ax == nil or bx == nil then return nil end
	local mx, my = (ax + bx) / 2, (ay + by) / 2
	local half = math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) / 2
	local best : SquareStressFlowZone = nil
	local bestD : number = nil
	for _, z in ipairs(zones or {}) do
		local d = math.sqrt((z.x - mx) ^ 2 + (z.y - my) ^ 2)
		if d < half and (bestD == nil or d < bestD) then best, bestD = z, d end
	end
	return best
end

---------------------------------------------------------------------------
-- Run totals and FLOW_SUMMARY

function flow.newTotals() : SquareStressFlowTotals
	return { samples = 0, gt0 = nil, gt1 = nil, drivers = 0, sampled = 0, standing = 0, vSum = 0.0, capped = 0, skipped = 0,
		busyUs = 0, busyMaxUs = 0, frames = 0, warn = {}, wall0 = nil, frameMaxUs = 0, target = nil }
end

function flow.addSample(t : SquareStressFlowTotals, gt : number, smp : SquareStressFlowSample, sw : SquareStressFlowSweepCost)
	t.samples = t.samples + 1
	if t.gt0 == nil then t.gt0 = gt end
	t.gt1 = gt
	t.drivers = t.drivers + smp.drivers
	t.sampled = t.sampled + smp.all.cars
	t.standing = t.standing + smp.all.standing
	t.vSum = t.vSum + smp.all.vSum
	if smp.sampled < smp.drivers then t.capped = t.capped + 1 end
	t.busyUs = t.busyUs + sw.busyUs
	if sw.busyUs > t.busyMaxUs then t.busyMaxUs = sw.busyUs end
	t.frames = t.frames + sw.frames
	if (sw.frameMaxUs or 0) > (t.frameMaxUs or 0) then t.frameMaxUs = sw.frameMaxUs end
	t.target = smp.target
end

function flow.summaryLine(run : integer, t : SquareStressFlowTotals, zones : integer, wallS : number, final : boolean) : string
	local n = t.samples
	return string.format("[SQST] FLOW_SUMMARY run=%d samples=%d gt0=%s gt1=%s wall_s=%s zones=%d drivers_mean=%s standing_frac=%s v_mean=%s v_kmh=%s capped=%d skipped=%d sweep_ms_mean=%s sweep_ms_max=%s frames_mean=%s warn=%s final=%d frame_ms_max=%s target=%s",
		run, n, N(t.gt0), N(t.gt1), N(wallS ~= nil and math.floor(wallS + 0.5) or nil), zones, N(n > 0 and math.floor(t.drivers / n + 0.5) or nil),
		N(t.sampled > 0 and t.standing / t.sampled or nil), N(t.sampled > 0 and t.vSum / t.sampled or nil),
		t.sampled > 0 and N(math.floor(t.vSum / t.sampled * 36 + 0.5) / 10) or "-", t.capped, t.skipped,
		N(n > 0 and math.floor(t.busyUs / n / 100 + 0.5) / 10 or nil), N(math.floor(t.busyMaxUs / 100 + 0.5) / 10),
		N(n > 0 and math.floor(t.frames / n * 10 + 0.5) / 10 or nil), flow.counts(t.warn), final and 1 or 0,
		N(math.floor((t.frameMaxUs or 0) / 100 + 0.5) / 10), (t.target == nil or t.target <= 0) and "all" or tostring(t.target))
end

--- The Traffic tab's one-line status.
function flow.statusText(on : boolean, interval : integer, run : integer, samples : integer, zones : integer, lastMs : number,
		lastFrames : integer, drivers : integer) : string
	if not on then
		if run == 0 then return "Off" end
		return string.format("Off (run %d: %d samples)", run, samples)
	end
	local last = lastMs ~= nil and string.format(", last sweep %.1f ms in %d frames, %d drivers", lastMs, lastFrames or 0, drivers or 0) or ", first sweep running"
	return string.format("On, every %d game s: run %d, %d samples, %d zones%s", interval, run, samples, zones, last)
end

return flow
