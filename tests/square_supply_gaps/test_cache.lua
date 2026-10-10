-- sg_cache: the catchment scheduler (PLAN "Cache"): new stations at once, round robin, dropped
-- stations, fetch errors, building re-read schedule, budget halving, PERF window.

local cache = ug_require "square_supply_gaps::/supply_gaps/sg_cache.tl"

-- fetch fake: station -> {station * 10}, records calls; `fail` set raises.
local function fetcher(fail)
	local calls = {}
	local f = function(s)
		calls[#calls + 1] = s
		if fail and fail[s] then error("boom " .. s) end
		return { s * 10 }
	end
	return f, calls
end

local function range(a, b)
	local out = {}
	for i = a, b do out[#out + 1] = i end
	return out
end

before_each(function()
	cache.STATIONS_PER_TICK = 25
	cache.MIN_STATIONS_PER_TICK = 5
	cache.BUILDING_EVERY = 10
	cache.BUDGET_MS = 8.0
	cache.PERF_EVERY = 30
	cache.STATION_CYCLE = 10
	clear_logs()
end)

test("new stations are fetched in the tick they appear", function()
	local c = cache.new()
	local f, calls = fetcher()
	local st = cache.step(c, { 3, 1, 2, 2 }, f)
	eq(calls, { 1, 2, 3 })
	eq(st.new, 3)
	eq(st.refreshed, 0)
	eq(cache.catchables(c), { [1] = { 10 }, [2] = { 20 }, [3] = { 30 } })
	eq(st.catchables, 3)
	-- one more station later: fetched at once, even with perTick spent
	c.perTick = 0
	local f2, calls2 = fetcher()
	st = cache.step(c, { 1, 2, 3, 9 }, f2)
	eq(calls2, { 9 })
	eq(st.new, 1)
end)

test("all new stations are fetched even beyond perTick", function()
	local c = cache.new()
	local f, calls = fetcher()
	cache.step(c, range(1, 60), f)
	eq(#calls, 60)
end)

test("round robin refreshes perTick stations per tick, in order, wrapping", function()
	local c = cache.new()
	c.perTick = 4
	local f = fetcher()
	cache.step(c, range(1, 10), f)
	local f2, calls = fetcher()
	cache.step(c, range(1, 10), f2)
	eq(calls, { 1, 2, 3, 4 })
	local f3, calls3 = fetcher()
	cache.step(c, range(1, 10), f3)
	eq(calls3, { 5, 6, 7, 8 })
	local f4, calls4 = fetcher()
	local st = cache.step(c, range(1, 10), f4)
	eq(calls4, { 9, 10, 1, 2 })
	eq(st.refreshed, 4)
end)

test("round robin covers every station within ceil(n / perTick) ticks", function()
	local c = cache.new()
	local stations = range(100, 199)
	cache.step(c, stations, (fetcher()))
	local seen = {}
	for _ = 1, 4 do
		local f, calls = fetcher()
		cache.step(c, stations, f)
		for _, s in ipairs(calls) do seen[s] = true end
	end
	for _, s in ipairs(stations) do ok(seen[s], "station " .. s .. " refreshed") end
end)

test("refreshed stations pick up new catchables", function()
	local c = cache.new()
	cache.step(c, { 1 }, function() return { 5 } end)
	eq(cache.catchables(c)[1], { 5 })
	cache.step(c, { 1 }, function() return { 5, 6 } end)
	eq(cache.catchables(c)[1], { 5, 6 })
end)

test("a station fetched new is not refreshed again in the same tick", function()
	local c = cache.new()
	cache.step(c, { 1, 2 }, (fetcher()))
	local f, calls = fetcher()
	cache.step(c, { 1, 2, 3 }, f)
	-- 3 is new; round robin then takes 1 and 2 only
	eq(calls, { 3, 1, 2 })
end)

test("stations no longer wanted are dropped", function()
	local c = cache.new()
	cache.step(c, { 1, 2, 3 }, (fetcher()))
	local st = cache.step(c, { 2 }, (fetcher()))
	eq(st.dropped, 2)
	eq(cache.catchables(c), { [2] = { 20 } })
	st = cache.step(c, {}, (fetcher()))
	eq(st.dropped, 1)
	eq(cache.catchables(c), {})
end)

test("negative station ids are ignored", function()
	local c = cache.new()
	local f, calls = fetcher()
	cache.step(c, { -1, 4 }, f)
	eq(calls, { 4 })
end)

test("fetch errors: new station gets {}, cached keeps its old list", function()
	local c = cache.new()
	cache.step(c, { 1 }, (fetcher()))
	local f = fetcher({ [1] = true, [2] = true })
	local st = cache.step(c, { 1, 2 }, f)
	eq(st.errors, 2)
	eq(cache.catchables(c), { [1] = { 10 }, [2] = {} })
end)

test("a non-table fetch result counts as an error", function()
	local c = cache.new()
	local st = cache.step(c, { 1 }, function() return nil end)
	eq(st.errors, 1)
	eq(cache.catchables(c)[1], {})
end)

test("buildingStep: every unknown id now, 1/BUILDING_EVERY of the rest round robin", function()
	local c = cache.new()
	local ids = {}
	for i = 1, 25 do ids[i] = 100 + i end
	-- first tick: nothing known -> all 25
	eq(#cache.buildingStep(c, ids, {}), 25)
	local known = {}
	for _, b in ipairs(ids) do known[b] = true end
	-- then ceil(25 / 10) = 3 per tick, wrapping; every index read once per 9 ticks
	local seen = {}
	for t = 1, 9 do
		local pick = cache.buildingStep(c, ids, known)
		ok(#pick == 3, "3 per tick")
		for _, i in ipairs(pick) do seen[i] = (seen[i] or 0) + 1 end
	end
	for i = 1, 25 do ok(seen[i] ~= nil, "index " .. i .. " read") end
	-- a new id is read at once, on top of the round robin
	ids[26] = 999
	local pick = cache.buildingStep(c, ids, known)
	local has = false
	for _, i in ipairs(pick) do if i == 26 then has = true end end
	ok(has, "new id read")
	ok(#pick == 3 or #pick == 4, "round robin slice + the new id")
end)

test("buildingStep: empty list, and a cursor past a shrunken list restarts", function()
	local c = cache.new()
	eq(cache.buildingStep(c, {}, {}), {})
	c.bCursor = 50
	eq(cache.buildingStep(c, { 1, 2 }, { [1] = true, [2] = true }), { 1 })
	eq(cache.buildingStep(c, { 1, 2 }, { [1] = true, [2] = true }), { 2 })
end)

test("buildingStep: due ids are urgent; maxUrgent caps urgent reads, the rest wait", function()
	local c = cache.new()
	local ids = {}
	local known = {}
	for i = 1, 20 do
		ids[i] = 100 + i
		known[100 + i] = true
	end
	-- 2 per tick round robin (ceil(20 / 10)) plus the due ids 105 and 115
	local pick = cache.buildingStep(c, ids, known, { [105] = true, [115] = true }, 10)
	local has = {}
	for _, i in ipairs(pick) do has[i] = true end
	ok(has[5] and has[15], "due ids read")
	eq(#pick, 4)
	-- unknown ids: at most maxUrgent of them (lowest indices first), plus the round robin
	known = {}
	c = cache.new()
	pick = cache.buildingStep(c, ids, known, {}, 5)
	has = {}
	for _, i in ipairs(pick) do has[i] = true end
	for i = 1, 5 do ok(has[i], "urgent index " .. i) end
	ok(#pick <= 7, "5 urgent + at most 2 round robin, got " .. #pick)
	ok(not has[20], "index 20 waits")
	-- no cap: every unknown id (the old behaviour)
	eq(#cache.buildingStep(cache.new(), ids, {}), 20)
end)

test("noteTime: over budget halves perTick down to the minimum", function()
	local c = cache.new()
	ok(not cache.noteTime(c, 3))
	eq(c.perTick, 25)
	ok(cache.noteTime(c, 12))
	eq(c.perTick, 12)
	ok(cache.noteTime(c, 12))
	eq(c.perTick, 6)
	ok(cache.noteTime(c, 12))
	eq(c.perTick, 5)
	ok(not cache.noteTime(c, 50))
	eq(c.perTick, 5)
end)

test("perf: nil until PERF_EVERY ticks, then {max, avg} and reset", function()
	local c = cache.new()
	cache.PERF_EVERY = 3
	cache.noteTime(c, 1)
	cache.noteTime(c, 4)
	eq(cache.perf(c), nil)
	cache.noteTime(c, 1)
	local p = cache.perf(c)
	eq(p[1], 4)
	near(p[2], 2)
	eq(cache.perf(c), nil)
	eq(c.perfTicks, 0)
end)

test("engineFetch copies getStationCatchables(station, true) into a plain list", function()
	local got
	set_global("api", { engine = { system = { catchmentAreaSystem = {
		getStationCatchables = function(s, cargo) got = { s, cargo }; return { 7, 8 } end,
	} } } })
	eq(cache.engineFetch(42), { 7, 8 })
	eq(got, { 42, true })
end)

-- perf review (2026-10-09) ------------------------------------------------------------------

test("an unchanged refresh keeps the list (same table) and reports changed = 0", function()
	local c = cache.new()
	local st = cache.step(c, { 1, 2 }, function(s) return { s, 7 } end)
	eq(st.changed, 2)
	local before = cache.catchables(c)[1]
	st = cache.step(c, { 1, 2 }, function(s) return { s, 7 } end)
	eq(st.refreshed, 2)
	eq(st.changed, 0)
	ok(cache.catchables(c)[1] == before, "same table kept")
	st = cache.step(c, { 1, 2 }, function(s) return s == 2 and { 2, 8 } or { s, 7 } end)
	eq(st.changed, 1)
	st = cache.step(c, { 2 }, function(s) return { 2, 8 } end)
	eq(st.changed, 1) -- station 1 dropped
end)

test("cap: round-robin refreshes limited to cap; new stations still all fetched", function()
	local c = cache.new()
	cache.step(c, range(1, 30), (fetcher()))
	local f, calls = fetcher()
	cache.step(c, range(1, 32), f, 3)
	eq(calls, { 31, 32, 1, 2, 3 })
end)

test("refreshCap: ceil(n / STATION_CYCLE), at least MIN_STATIONS_PER_TICK", function()
	eq(cache.refreshCap(0), 5)
	eq(cache.refreshCap(71), 8)
	eq(cache.refreshCap(355), 36)
end)
