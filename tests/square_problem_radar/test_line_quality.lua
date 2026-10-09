-- radar_checks Phase 4: line_overloaded, line_underused, line_bunching (pure metric + sustain
-- timers + carry-over for the rotating cursor), headways, lineRotation, formatSeconds.
-- Inputs mirror what radar.script.tl measureLine builds (radar_types ProblemRadarLineQuality).

local checks = ug_require "square_problem_radar::/radar/radar_checks.tl"
local settingsMod = ug_require "square_problem_radar::/radar/radar_settings.tl"

local MIN = 60000
local SUSTAIN = 10 * MIN          -- default lineSustainMin
local INTERVAL = 150000           -- 2:30 target headway

local function ids(alerts)
	local out = {}
	for i, a in ipairs(alerts) do out[i] = a.id end
	table.sort(out)
	return out
end

local function byId(alerts)
	local m = {}
	for _, a in ipairs(alerts) do m[a.id] = a end
	return m
end

local function settings(over)
	local s = settingsMod.defaults()
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

--- departures: one stop; `ago` = ms before `now` per vehicle.
local function deps(now, ago)
	local out = {}
	for i, a in ipairs(ago) do out[i] = { now - a } end
	return out
end

--- A line measured this pass; defaults are healthy (no alert).
local function q(over)
	local l = { name = "Bus 14", vehicles = 5, used = 50, capacity = 100, stops = {}, intervalMs = INTERVAL,
		fullLoad = false, departures = {} }
	for k, v in pairs(over or {}) do l[k] = v end
	return l
end

local function run(now, lines, memory, extra)
	local input = {
		now = now,
		settings = settings(extra and extra.settings),
		lines = lines,
		eligible = (extra and extra.eligible) or (function()
			local e = {}
			for l in pairs(lines) do e[l] = true end
			return e
		end)(),
		keep = extra and extra.keep or {},
		memory = memory or checks.freshMemory(),
	}
	return checks.lineQuality(input)
end

-- even spacing at 2:30 with 5 vehicles
local EVEN = { 10000, 160000, 310000, 460000, 610000 }
-- 3 of 5 within 40 s (headways 20 s, 20 s), then 350 s and 200 s
local CLUMP = { 10000, 30000, 50000, 400000, 600000 }
-- 3 vehicles evenly 2:30 apart, but the last departed 500 s ago (open gap 3.3x)
local GAP = { 500000, 650000, 800000 }

-- headways ----------------------------------------------------------------------

test("headways: even spacing, a clump, an open gap", function()
	local now = 10000000
	local h = checks.headways(deps(now, EVEN), now, INTERVAL, 30000)
	eq(h, { stopsUsed = 1, minGapMs = 150000, maxGapMs = 150000, clump = 1, clumpSpanMs = 0 })
	local c = checks.headways(deps(now, CLUMP), now, INTERVAL, 30000)
	eq(c.minGapMs, 20000)
	eq(c.maxGapMs, 350000)
	eq(c.clump, 3)
	eq(c.clumpSpanMs, 40000)
	local g = checks.headways(deps(now, GAP), now, INTERVAL, 30000)
	eq(g.minGapMs, 150000)
	eq(g.maxGapMs, 500000, "the gap still open since the last departure counts")
end)

test("headways: stops with a missing / stale / future departure are skipped; median over stops", function()
	local now = 10000000
	-- stop 1 clumped, stop 2 clumped, stop 3 even: median = clumped
	local d = {
		{ now - 10000, now - 10000, now - 10000 },
		{ now - 20000, now - 25000, now - 160000 },
		{ now - 30000, now - 35000, now - 310000 },
	}
	local h = checks.headways(d, now, INTERVAL, 30000)
	eq(h.stopsUsed, 3)
	eq(h.minGapMs, 10000)
	eq(h.clump, 3)
	-- vehicle 3 never departed stop 2 (0), stop 3 is stale (> 3 round trips), stop 1 in the future
	local d2 = {
		{ now + 5, now - 10000, now - 10000 },
		{ now - 20000, now - 25000, now - 9999999 },
		{ now - 30000, 0, now - 310000 },
	}
	eq(checks.headways(d2, now, INTERVAL, 30000), nil)
	eq(checks.headways({ { 1 } }, now, INTERVAL, 30000), nil, "one vehicle")
	eq(checks.headways(deps(now, EVEN), now, 0, 30000), nil, "no interval")
	-- garbage from the API
	eq(checks.headways({ "x", { now - 1 } }, now, INTERVAL, 30000), nil)
end)

-- bunching ------------------------------------------------------------------------

test("line_bunching: clump flagged only after the sustain time; detail packs counts and times", function()
	local t0 = 10000000
	local out, mem, changed = run(t0, { [7] = q({ departures = deps(t0, CLUMP) }) })
	eq(out, {}, "timer started, nothing listed yet")
	eq(mem.bunchingSince, { [7] = t0 })
	ok(changed)
	local t1 = t0 + SUSTAIN - 1
	out, mem, changed = run(t1, { [7] = q({ departures = deps(t1, CLUMP) }) }, mem)
	eq(out, {}, "one ms short")
	eq(mem.bunchingSince, { [7] = t0 }, "timer continues")
	eq(changed, false)
	local t2 = t0 + SUSTAIN
	out, mem = run(t2, { [7] = q({ departures = deps(t2, CLUMP) }) }, mem)
	eq(ids(out), { "line_bunching:7" })
	local a = out[1]
	eq(a.tab, "lines")
	eq(a.tier, 2)
	eq(a.entity, 7)
	eq(a.etype, "Line")
	eq(a.label, "Bus 14")
	eq(a.code, "Clump")
	eq(a.arg, "3|5|40|150")
	eq(a.metric, "3/5")
end)

test("line_bunching: gap far over the target", function()
	local t0 = 10000000
	local mem = checks.freshMemory()
	mem.bunchingSince[8] = t0 - SUSTAIN
	local out = run(t0, { [8] = q({ vehicles = 3, departures = deps(t0, GAP) }) }, mem)
	eq(ids(out), { "line_bunching:8" })
	eq(out[1].code, "Gap")
	eq(out[1].arg, "500|150")
	eq(out[1].metric, "3.3×")
end)

test("line_bunching: no flag for even spacing; < 3 vehicles, full-load and unknown interval skipped", function()
	local t0 = 10000000
	local old = checks.freshMemory()
	for l = 1, 5 do old.bunchingSince[l] = t0 - SUSTAIN end
	local out, mem = run(t0, {
		[1] = q({ departures = deps(t0, EVEN) }),
		[2] = q({ vehicles = 2, departures = deps(t0, { 10000, 15000 }) }),        -- 2 vehicles bunched
		[3] = q({ fullLoad = true, departures = deps(t0, CLUMP) }),                 -- full load: demand-paced
		[4] = q({ intervalMs = 0, departures = deps(t0, CLUMP) }),                  -- no frequency yet
		[5] = q({ departures = deps(t0, { 10000, 20000, 9999999 }) }),              -- stale data
	}, old)
	eq(out, {})
	eq(mem.bunchingSince, {}, "every timer reset")
end)

test("line_bunching: hysteresis holds a running timer just above the clump threshold, never starts it", function()
	local t0 = 10000000
	-- headway 35 s: above the 30 s clump threshold (20% of 2:30) but below 30 / 0.75 = 40 s
	local NEAR = { 10000, 45000, 300000, 450000, 600000 }
	local out, mem = run(t0, { [7] = q({ departures = deps(t0, NEAR) }) })
	eq(mem.bunchingSince, {}, "does not start")
	local running = checks.freshMemory()
	running.bunchingSince[7] = t0 - SUSTAIN
	out, mem = run(t0, { [7] = q({ departures = deps(t0, NEAR) }) }, running)
	eq(mem.bunchingSince, { [7] = t0 - SUSTAIN }, "holds")
	eq(out[1].code, "Clump")
	eq(out[1].arg, "2|5|35|150", "a held clump reports at least the closest pair")
end)

test("line_bunching: thresholds follow the settings", function()
	local t0 = 10000000
	local mem = checks.freshMemory()
	mem.bunchingSince[7] = t0 - MIN
	local out = run(t0, { [7] = q({ departures = deps(t0, EVEN) }) }, mem,
		{ settings = { lineClumpPct = 90, lineSustainMin = 1 } })
	-- 90% of 2:30 = 135 s > every 150 s headway? no: 150 >= 135, but hold = 135 / 0.75 = 180 s
	eq(ids(out), { "line_bunching:7" })
	local out2 = run(t0, { [7] = q({ departures = deps(t0, GAP) }) }, nil, { settings = { lineGapPct = 400 } })
	eq(out2, {}, "3.3x < 4x")
end)

-- overload ------------------------------------------------------------------------

test("line_overloaded: worst stop by waiting / capacity per trip, after the sustain time", function()
	local t0 = 5000000
	local stops = {
		{ stop = 0, name = "", waiting = 49, perTrip = 1 },            -- under MIN_OVERLOAD_WAITING
		{ stop = 2, name = "Central", waiting = 420, perTrip = 150 },  -- 2.8x
		{ stop = 4, name = "Harbour", waiting = 600, perTrip = 150 },  -- 4.0x  (worst)
		{ stop = 5, name = "Depot", waiting = 900, perTrip = 0 },      -- no capacity for that cargo: ignored
	}
	local out, mem = run(t0, { [3] = q({ stops = stops }) })
	eq(out, {})
	eq(mem.overloadSince, { [3] = t0 })
	out, mem = run(t0 + SUSTAIN, { [3] = q({ stops = stops }) }, mem)
	eq(ids(out), { "line_overloaded:3" })
	local a = out[1]
	eq(a.tier, 2)
	eq(a.code, "Overloaded")
	eq(a.arg, "5|600|Harbour", "1-based stop number | waiting | name")
	eq(a.metric, "4.0×")
end)

test("line_overloaded: below the factor or the minimum count never starts; hold at 0.75x; reset", function()
	local t0 = 5000000
	local function stops(waiting, perTrip) return { { stop = 1, name = "A", waiting = waiting, perTrip = perTrip } } end
	local _, mem = run(t0, { [3] = q({ stops = stops(420, 150) }) })        -- 2.8x < 3x
	eq(mem.overloadSince, {})
	_, mem = run(t0, { [3] = q({ stops = stops(40, 5) }) })                 -- 8x but only 40 waiting
	eq(mem.overloadSince, {})
	local running = checks.freshMemory()
	running.overloadSince[3] = t0 - 1000
	_, mem = run(t0, { [3] = q({ stops = stops(340, 150) }) }, running)     -- 2.27x >= 2.25x: holds
	eq(mem.overloadSince, { [3] = t0 - 1000 })
	local _, mem2, changed = run(t0, { [3] = q({ stops = stops(330, 150) }) }, running) -- 2.2x: reset
	eq(mem2.overloadSince, {})
	ok(changed)
	_, mem = run(t0, { [3] = q({ stops = stops(60, 20) }) }, nil, { settings = { lineOverloadFactor = 2 } })
	eq(mem.overloadSince, { [3] = t0 }, "factor from the settings")
end)

-- underuse ------------------------------------------------------------------------

test("line_underused: utilisation below the threshold for the sustain time; >= 2 vehicles", function()
	local t0 = 5000000
	local old = checks.freshMemory()
	old.underusedSince[1] = t0 - SUSTAIN
	old.underusedSince[2] = t0 - SUSTAIN
	old.underusedSince[3] = t0 - SUSTAIN
	old.underusedSince[4] = t0 - SUSTAIN
	local out, mem = run(t0, {
		[1] = q({ vehicles = 10, used = 8, capacity = 100 }),   -- 8%: listed
		[2] = q({ vehicles = 1, used = 0, capacity = 50 }),     -- one bus running empty is normal
		[3] = q({ vehicles = 4, used = 0, capacity = 0 }),      -- no capacity data
		[4] = q({ vehicles = 4, used = 14, capacity = 100 }),   -- 14% >= 10 / 0.75 = 13.3%: clears
	}, old)
	eq(ids(out), { "line_underused:1" })
	eq(out[1].tier, 3)
	eq(out[1].code, "Underused")
	eq(out[1].metric, "8%")
	eq(out[1].arg, "10")
	eq(mem.underusedSince, { [1] = t0 - SUSTAIN })
	-- 12% holds a running timer but does not start one
	local _, m2 = run(t0, { [1] = q({ used = 12, capacity = 100 }) }, old)
	eq(m2.underusedSince, { [1] = t0 - SUSTAIN })
	local _, m3 = run(t0, { [1] = q({ used = 12, capacity = 100 }) })
	eq(m3.underusedSince, {})
	-- threshold from the settings
	local _, m4 = run(t0, { [1] = q({ used = 30, capacity = 100 }) }, nil, { settings = { lineUnderusedPct = 40 } })
	eq(m4.underusedSince, { [1] = t0 })
end)

-- carry-over, pruning, caps -------------------------------------------------------------

test("lineQuality: lines not measured this pass keep their timers and alerts; ineligible lines are pruned", function()
	local now = 9000000
	local mem = checks.freshMemory()
	mem.overloadSince = { [1] = 100, [2] = 200, [3] = 300 }
	mem.underusedSince = { [1] = 100, [9] = 900 }
	mem.bunchingSince = { [2] = 200 }
	mem.stoppedSince = { [77] = 5 }
	local keep = {
		{ id = "line_overloaded:1", kind = "line_overloaded", tab = "lines", tier = 2, entity = 1.0, code = "Overloaded", firstSeen = 1 },
		{ id = "line_bunching:2", kind = "line_bunching", tab = "lines", tier = 2, entity = 2, code = "Gap", firstSeen = 2 },
		{ id = "line_underused:9", kind = "line_underused", tab = "lines", tier = 3, entity = 9, code = "Underused", firstSeen = 3 },
		{ id = "line_broken:1", kind = "line_broken", tab = "lines", tier = 1, entity = 1, code = "NO_PATH", firstSeen = 4 },
	}
	-- line 2 measured (healthy now), 1 not measured but eligible, 3 measured healthy, 9 gone
	local out, m, changed = run(now, { [2] = q(), [3] = q() }, mem,
		{ eligible = { [1] = true, [2] = true, [3] = true }, keep = keep })
	eq(ids(out), { "line_overloaded:1" }, "only quality alerts of unmeasured eligible lines carry over")
	eq(out[1].firstSeen, 1)
	ok(out[1] ~= keep[1], "a copy")
	eq(m.overloadSince, { [1] = 100 })
	eq(m.underusedSince, { [1] = 100 })
	eq(m.bunchingSince, {})
	eq(m.stoppedSince, { [77] = 5 }, "vehicle timers untouched")
	eq(m.lineCursor, nil, "no cursor in memory (v5: module-local in radar.script.tl)")
	ok(changed)
	eq(mem.overloadSince[2], 200, "input memory not mutated")
end)

test("lineQuality: timer maps capped at MAX_LINE_TIMERS (oldest kept); floats and future times sanitised", function()
	eq(checks.MAX_LINE_TIMERS, 300)
	local now = 100000
	local mem = checks.freshMemory()
	local lines, eligible = {}, {}
	for l = 1, 305 do
		lines[l] = q({ vehicles = 3, used = 0, capacity = 10 })
		eligible[l] = true
		mem.underusedSince[l] = l * 10.0 -- line 1 oldest
	end
	mem.underusedSince[305] = now + 999 -- from the future: clamps to now
	local _, m = run(now, lines, mem, { eligible = eligible })
	local n = 0
	for _ in pairs(m.underusedSince) do n = n + 1 end
	eq(n, 300)
	eq(m.underusedSince[1], 10)
	eq(m.underusedSince[300], 3000)
	eq(m.underusedSince[305], nil, "the newest (clamped to now) fall off")
end)

-- rotation + formatting -----------------------------------------------------------------

test("lineRotation: ids after the cursor first, then wrap; nil/garbage cursor starts at the lowest", function()
	local r = checks.lineRotation
	eq(r({ 5, 1, 9, 3 }, 3), { 5, 9, 1, 3 })
	eq(r({ 5, 1, 9, 3 }, 9), { 1, 3, 5, 9 })
	eq(r({ 5, 1, 9, 3 }, 4.0), { 5, 9, 1, 3 }, "a removed line as cursor")
	eq(r({ 5, 1, 9, 3 }, nil), { 1, 3, 5, 9 })
	eq(r({ 5, 1, 9, 3 }, -1), { 1, 3, 5, 9 })
	eq(r({}, 3), {})
	eq(r(nil, 3), {})
	-- a full rotation in slices of 2 visits every line once
	local all = { 4, 8, 15, 16, 23 }
	local cursor, seen = -1, {}
	for _ = 1, 3 do
		local order = r(all, cursor)
		for i = 1, math.min(2, #order) do
			seen[#seen + 1] = order[i]
			cursor = order[i]
		end
	end
	eq(seen, { 4, 8, 15, 16, 23, 4 })
end)

test("formatSeconds", function()
	eq(checks.formatSeconds(0), "0:00")
	eq(checks.formatSeconds(40), "0:40")
	eq(checks.formatSeconds(150), "2:30")
	eq(checks.formatSeconds(430), "7:10")
	eq(checks.formatSeconds(3725), "1:02:05")
	eq(checks.formatSeconds(nil), "0:00")
end)

test("merge: Phase 4 kinds belong to the lines group", function()
	local st = checks.freshState()
	st.settings.smoothSec = 0 -- smoothing off: listed on the first scan (smoothing: test_checks.lua)
	local s = checks.merge(st, "lines", {
		{ id = "line_bunching:7", kind = "line_bunching", tab = "lines", tier = 2, entity = 7, code = "Gap" },
		{ id = "line_underused:8", kind = "line_underused", tab = "lines", tier = 3, entity = 8, code = "Underused" },
	}, 10)
	eq(s.kindCounts, { line_bunching = 1, line_underused = 1 })
	s = checks.merge(s, "lines", {}, 20)
	eq(s.total, 0)
end)
