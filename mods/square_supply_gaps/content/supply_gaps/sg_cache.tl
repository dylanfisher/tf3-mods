-- Supply Gaps catchment cache (PLAN "Cache"). getStationCatchables is the one per-station engine
-- call; this scheduler bounds how many run per tick:
--   * a station not cached yet is fetched in the tick it first appears (a stop just added to a line
--     shows within one tick)
--   * cached stations are refreshed round robin, `perTick` per tick, in ascending station order
--     (town growth, rebuilt buildings)
--   * stations no longer in a delivering group are dropped
-- Only `step`'s fetch argument touches the engine (engineFetch in game, a fake in
-- tests/square_supply_gaps/test_cache.lua). GUI memory only; nothing is saved.
-- Lua 5.1 safe: no integer division, math.type or utf8.

local cache : SupplyGapsCache = {}

cache.STATIONS_PER_TICK = 25
cache.MIN_STATIONS_PER_TICK = 5
-- Building re-read interval in ticks (1 s each). Spread round robin: 1/BUILDING_EVERY of the
-- buildings per tick (Phase 2b; before, all of them every 10th tick = the max-ms spikes).
cache.BUILDING_EVERY = 10
-- The overlay caps round-robin refreshes at ceil(n / STATION_CYCLE) a tick (cache.refreshCap), so every
-- station is refreshed about every STATION_CYCLE ticks, never faster (perf review 2026-10-09; before,
-- 25 a tick refreshed a 71-station map every 3 s).
cache.STATION_CYCLE = 10
-- Over this a tick halves perTick.
cache.BUDGET_MS = 8.0
-- Ticks per PERF line (sg_overlay DEBUG only).
cache.PERF_EVERY = 30

function cache.new() : SupplyGapsCatchCache
	return {
		entries = {}, tick = 0, cursor = -1, perTick = cache.STATIONS_PER_TICK,
		bCursor = 0, perfTicks = 0, perfMax = 0, perfSum = 0,
	}
end

local function sameList(a : {integer}, b : {integer}) : boolean
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i] ~= b[i] then return false end
	end
	return true
end

local function fetchInto(c : SupplyGapsCatchCache, station : integer, fetch : SupplyGapsFetchFn, stats : SupplyGapsStepStats)
	local ok, res = pcall(fetch, station)
	local entry = c.entries[station]
	if ok and type(res) == "table" then
		if entry ~= nil and sameList(entry.list, res as {integer}) then
			-- unchanged: keep the old list, so the model's inputs stay the same (perf review)
			entry.tick = c.tick
		else
			c.entries[station] = { list = res as {integer}, tick = c.tick }
			stats.changed = stats.changed + 1
		end
	else
		stats.errors = stats.errors + 1
		if entry == nil then
			c.entries[station] = { list = {}, tick = c.tick }
			stats.changed = stats.changed + 1
		else
			-- Keep the old list; count as fetched so the round robin moves on.
			entry.tick = c.tick
		end
	end
end

function cache.step(c : SupplyGapsCatchCache, stations : {integer}, fetch : SupplyGapsFetchFn, cap? : integer) : SupplyGapsStepStats
	c.tick = c.tick + 1
	local stats : SupplyGapsStepStats = { new = 0, refreshed = 0, dropped = 0, errors = 0, catchables = 0, changed = 0 }

	local wanted : {integer : boolean} = {}
	local order : {integer} = {}
	for __, s in ipairs(stations or {}) do
		if s ~= nil and s >= 0 and not wanted[s] then
			wanted[s] = true
			order[#order + 1] = s
		end
	end
	table.sort(order)

	local cached : {integer} = {}
	for s in pairs(c.entries) do cached[#cached + 1] = s end
	table.sort(cached)
	for __, s in ipairs(cached) do
		if not wanted[s] then
			c.entries[s] = nil
			stats.dropped = stats.dropped + 1
			stats.changed = stats.changed + 1
		end
	end

	for __, s in ipairs(order) do
		if c.entries[s] == nil then
			fetchInto(c, s, fetch, stats)
			stats.new = stats.new + 1
		end
	end

	-- Round robin over the stations not fetched this tick, starting after the cursor, wrapping once.
	local n = #order
	if n > 0 then
		local start = 1
		for i = 1, n do
			if order[i] > c.cursor then
				start = i
				break
			end
			if i == n then start = 1 end
		end
		local i = start
		for __ = 1, n do
			if stats.refreshed >= c.perTick or (cap ~= nil and stats.refreshed >= cap) then break end
			local s = order[i]
			if c.entries[s].tick ~= c.tick then
				fetchInto(c, s, fetch, stats)
				stats.refreshed = stats.refreshed + 1
				c.cursor = s
			end
			i = i % n + 1
		end
	end

	for __, e in pairs(c.entries) do stats.catchables = stats.catchables + #e.list end
	return stats
end

function cache.refreshCap(n : integer) : integer
	local k = math.floor((n + cache.STATION_CYCLE - 1) / cache.STATION_CYCLE)
	return math.max(k, cache.MIN_STATIONS_PER_TICK)
end

function cache.catchables(c : SupplyGapsCatchCache) : {integer : {integer}}
	local out : {integer : {integer}} = {}
	for s, e in pairs(c.entries) do out[s] = e.list end
	return out
end

function cache.buildingStep(c : SupplyGapsCatchCache, ids : {integer}, known : {integer : boolean}, due? : {integer : boolean}, maxUrgent? : integer) : {integer}
	local out : {integer} = {}
	local n = #(ids or {})
	if n == 0 then return out end
	known = known or {}
	local pick : {integer : boolean} = {}
	local urgent = 0
	for i = 1, n do
		local b = ids[i]
		if not known[b] or (due ~= nil and due[b]) then
			if maxUrgent == nil or urgent < maxUrgent then
				pick[i] = true
				urgent = urgent + 1
			end
		end
	end
	-- ceil(n / BUILDING_EVERY) without integer division (Lua 5.1)
	local k = math.floor((n + cache.BUILDING_EVERY - 1) / cache.BUILDING_EVERY)
	local cur = c.bCursor or 0
	if cur >= n then cur = 0 end
	for __ = 1, k do
		cur = cur + 1
		if cur > n then cur = 1 end
		pick[cur] = true
	end
	c.bCursor = cur
	for i = 1, n do
		if pick[i] then out[#out + 1] = i end
	end
	return out
end

function cache.noteTime(c : SupplyGapsCatchCache, ms : number) : boolean
	c.perfTicks = c.perfTicks + 1
	c.perfSum = c.perfSum + ms
	if ms > c.perfMax then c.perfMax = ms end
	if ms > cache.BUDGET_MS and c.perTick > cache.MIN_STATIONS_PER_TICK then
		c.perTick = math.max(cache.MIN_STATIONS_PER_TICK, math.floor(c.perTick / 2))
		return true
	end
	return false
end

function cache.perf(c : SupplyGapsCatchCache) : {number}
	if c.perfTicks < cache.PERF_EVERY then return nil end
	local out = { c.perfMax, c.perfSum / c.perfTicks }
	c.perfTicks, c.perfMax, c.perfSum = 0, 0, 0
	return out
end

-- api/tealdef/api/engine/system.d.tl:445-448: "entities holding a StockList or PersonCapacity";
-- cargo = true gives the cargo catchables (as cargo_util.getInputOutputStocksForStation,
-- .cache/game/base/content/gui/main/cargo_util.tl:543-563). Copied into a plain table.
function cache.engineFetch(station : integer) : {integer}
	local res = api.engine.system.catchmentAreaSystem.getStationCatchables(station, true)
	local out : {integer} = {}
	if res ~= nil then
		for i = 1, #res do out[i] = res[i] end
	end
	return out
end

return cache
