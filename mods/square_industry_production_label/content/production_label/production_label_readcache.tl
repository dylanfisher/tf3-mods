-- Industry Production Label: per-entity read cache shared by every HUD label (PERF_REVIEW.md 2026-10-10).
--
-- Why: in game (desert save, 107 industries) the industry read ran ~220 times/s while labels were on
-- screen, about 4 reads per industry per 2 s REFRESH_INTERVAL, i.e. several label instances (or timer
-- firings) per industry each doing the full engine read. One read per entity per TTL_MS now serves them
-- all; the label output is the same, at most TTL_MS older.
--
-- Threads: every HUD label of a load runs in ONE Lua state (SQPERF lines ctx=hud all carry the same
-- vm= id while the thread column changes, "Main Pool 1".."Main Pool 10"), and the engine runs one
-- callback at a time in a Lua state. get/put never yield, so no two reads interleave inside them and an
-- entry is never seen half written; a plain module table is enough (like pickup.cache).
--
-- Pure: no api.* (the caller passes the time in ms), unit-tested in
-- tests/square_industry_production_label/test_readcache.lua.

local readcache : SquareProductionLabelReadCache = {}

-- Max age (ms) of a cached read. Below the labels' 2 s poll (production_label.script.tl
-- REFRESH_INTERVAL), so a label never shows data older than it already could plus TTL_MS.
readcache.TTL_MS = 1500.0

-- Expired entries (industries no label reads any more) are dropped at most once per SWEEP_MS.
readcache.SWEEP_MS = 30000.0

function readcache.new(ttlMs? : number) : SquareProductionLabelReadCacheInst
	return { entries = {}, ttlMs = ttlMs or readcache.TTL_MS, sweptAt = nil }
end

local function fresh(c : SquareProductionLabelReadCacheInst, at : number, now : number) : boolean
	return now >= at and now - at < c.ttlMs
end

--- found, value. A cached nil (entity without a label) is found too.
function readcache.get(c : SquareProductionLabelReadCacheInst, key : integer, now : number) : boolean, any
	local e = c.entries[key]
	if e ~= nil and fresh(c, e.at, now) then
		return true, e.value
	end
	return false, nil
end

--- Store a read; true when the key was not cached before (a new entity, for the SQPERF counter).
function readcache.put(c : SquareProductionLabelReadCacheInst, key : integer, now : number, value : any) : boolean
	local e = c.entries[key]
	local isNew = e == nil
	if isNew then
		c.entries[key] = { at = now, value = value }
	else
		e.at, e.value = now, value
	end
	local swept = c.sweptAt
	if swept == nil or now < swept or now - swept >= readcache.SWEEP_MS then
		c.sweptAt = now
		for k, entry in pairs(c.entries) do
			if not fresh(c, entry.at, now) then
				c.entries[k] = nil
			end
		end
	end
	return isNew
end

-- The two caches of the HUD state (module-level, so tests can reset them with readcache.reset()).
readcache.industry = readcache.new()
readcache.warehouse = readcache.new()

function readcache.reset()
	readcache.industry = readcache.new()
	readcache.warehouse = readcache.new()
end

return readcache
