-- production_label_readcache: the per-entity read cache shared by every HUD label (PERF_REVIEW.md
-- 2026-10-10): hit within TTL_MS, miss from TTL_MS on, a cached nil is a hit, clock going back is a
-- miss, put reports new keys, expired entries are swept, reset gives empty caches.

local readcache = ug_require "square_industry_production_label::/production_label/production_label_readcache.tl"

before_each(function()
	readcache.TTL_MS = 1500
	readcache.SWEEP_MS = 30000
end)

test("TTL below the labels' 2 s poll", function()
	ok(readcache.TTL_MS > 0 and readcache.TTL_MS < 2000)
end)

test("empty cache: miss", function()
	local c = readcache.new()
	local found, v = readcache.get(c, 1, 0)
	eq(found, false)
	eq(v, nil)
end)

test("hit within the TTL, miss from the TTL on", function()
	local c = readcache.new()
	local view = { entries = { { cargoType = 7, value = 34, producing = true } } }
	readcache.put(c, 42, 1000, view)
	local found, v = readcache.get(c, 42, 1000)
	ok(found); ok(v == view, "the same table is served")
	found = readcache.get(c, 42, 2499.9)
	ok(found)
	found = readcache.get(c, 42, 2500)
	eq(found, false)
end)

test("a cached nil (no label for that entity) is a hit", function()
	local c = readcache.new()
	readcache.put(c, 5, 0, nil)
	local found, v = readcache.get(c, 5, 10)
	eq(found, true)
	eq(v, nil)
end)

test("keys are separate; put overwrites and restarts the TTL", function()
	local c = readcache.new()
	eq(readcache.put(c, 1, 0, "a"), true)
	eq(readcache.put(c, 2, 0, "b"), true)
	eq(readcache.put(c, 1, 1400, "a2"), false)
	local f1, v1 = readcache.get(c, 1, 2000)
	local f2 = readcache.get(c, 2, 2000)
	ok(f1); eq(v1, "a2")
	eq(f2, false)
end)

test("clock going back (a new Clock / restarted timer): miss", function()
	local c = readcache.new()
	readcache.put(c, 1, 5000, "x")
	eq((readcache.get(c, 1, 4999)), false)
end)

test("custom TTL per cache", function()
	local c = readcache.new(100)
	readcache.put(c, 1, 0, "x")
	ok((readcache.get(c, 1, 99)))
	eq((readcache.get(c, 1, 100)), false)
end)

test("expired entries are swept at most once per SWEEP_MS", function()
	local c = readcache.new()
	readcache.put(c, 1, 0, "a") -- first put sweeps (sweptAt = 0)
	readcache.put(c, 2, 10000, "b") -- 1 expired but no sweep yet
	ok(c.entries[1] ~= nil)
	readcache.put(c, 3, 30000, "c") -- sweep: 1 and 2 expired, 3 fresh
	eq(c.entries[1], nil)
	eq(c.entries[2], nil)
	ok(c.entries[3] ~= nil)
end)

test("reset gives fresh industry and warehouse caches", function()
	readcache.put(readcache.industry, 1, 0, "a")
	readcache.put(readcache.warehouse, 1, 0, "b")
	readcache.reset()
	eq((readcache.get(readcache.industry, 1, 0)), false)
	eq((readcache.get(readcache.warehouse, 1, 0)), false)
end)

test("micro-benchmark: get on a warm cache (informational)", function()
	local c = readcache.new()
	for e = 1, 200 do readcache.put(c, e, 0, { entries = {} }) end
	local n = 200000
	local t0 = os.clock()
	local hits = 0
	for i = 1, n do
		if readcache.get(c, (i % 200) + 1, 1000) then hits = hits + 1 end
	end
	local us = (os.clock() - t0) / n * 1e6
	eq(hits, n)
	print(string.format("readcache.get: %.3f us per call (offline Lua 5.4)", us))
	ok(us < 50, "get should be far below a 56 us engine read")
end)
