-- Minimap network layer (PLAN.md phase 6): the time-sliced scheduler. Pure: the engine reads, the
-- image hand-off, logging and SQPERF come in through `io` (SquareMinimapNetIo), so the whole pass
-- (list, flatten, sweep, remove, read, encode, hand-off) runs offline in
-- tests/square_better_minimap/test_netscan.lua. The game side is gui/minimap_hud.script.tl
-- ("Network layer"); the raster and encoder are minimap_net.tl.
--
-- A SCAN (every scanSeconds, see BACK-OFF):
--   list_s / list_t / list_b  one engine map call each (street edges, track edges, town buildings),
--                             each the only work of its frame (isHeavy): they can't be sliced
--   flat_s / flat_t / flat_b  walk the returned map in FLATTEN_CHUNK steps: cached ids get the new
--                             stamp, unknown ids are collected once (net.flattenStep)
--   sweep_e / sweep_b         cached ids without the stamp are removed (net.sweepStep)
--   remove_e / remove_b       subtract the removed items' pixels (REMOVE_CHUNK per step)
--   read_e / read_b           read and draw the new items (READ_CHUNK per step)
--   encode                    only if a pixel changed: re-encode the CHANGED bands of 8 rows into
--                             their strip's kept buffer (net STRIPS; a strip without a buffer is
--                             encoded whole into a new one; every strip on a palette switch)
--   handoff                   io.handoff of ONE changed strip per frame (the only work of that
--                             frame: one Lua -> C++ copy of w x 64 rows), then io.publish swaps all
--                             of them in at once (one new image version: no half-old picture)
-- Every step is small and run() checks the clock after each one (budget per frame).
--
-- BACK-OFF: a scan that changed nothing doubles the wait (base -> ... -> BACKOFF_MAX_SECONDS);
-- any change (or toggling on) goes back to the base interval (net.scanInterval of the list time).
-- The engine offers no cheaper change signal for the networks or town buildings (no global
-- revision in api/engine/system.d.tl; town entity revisions don't bump with building turnover,
-- PERF_REVIEW.md 2026-10-08), so the scan itself is the check.

local net = ug_require "square_better_minimap::/minimap/minimap_net.tl" as SquareMinimapNet

local netscan : SquareMinimapNetScan = {}

netscan.SCAN_SECONDS = 5.0
netscan.SCAN_MAX_SECONDS = 60.0
netscan.SCAN_FACTOR = 500
netscan.BACKOFF_MAX_SECONDS = 30.0
netscan.FLATTEN_CHUNK = 256  -- map entries per step
netscan.SWEEP_CHUNK = 256    -- cache entries per step
netscan.READ_CHUNK = 16      -- entities read (then drawn) per step
netscan.REMOVE_CHUNK = 16    -- items subtracted per step (a long edge is a few hundred pixels)

function netscan.newStats(now : number) : SquareMinimapNetStats
	return { startMs = now, frames = 0, listMs = 0, flattenMs = 0, sweepMs = 0, readMs = 0, rasterMs = 0,
		encodeMs = 0, handoffMs = 0, bands = 0, stripsHanded = 0, streets = 0, tracks = 0, tunnels = 0, noGeom = 0, noBox = 0, readFailed = 0 }
end

function netscan.newState(box : SquareMinimapBox, orient : SquareMinimapOrient, longSide : integer, hiVis : boolean, order : string) : SquareMinimapNetState
	local w, h = net.imageSize(box, orient, longSide)
	return {
		minX = box.minX, minY = box.minY, maxX = box.maxX, maxY = box.maxY,
		w = w, h = h,
		xf = net.makeXform(box, orient, w, h),
		grid = net.newGrid(w, h),
		strips = net.stripCount(h), bufs = {}, pending = {}, stripFull = {}, spareParams = {},
		palette = net.paletteFor(hiVis, order),
		hiVis = hiVis,
		edges = {}, buildings = {}, edgeCount = 0, buildingCount = 0,
		stamp = 0, phase = "idle", waitUntilMs = 0, yield = false,
		readBuf = {},
		dirty = false, version = 0, baseSeconds = netscan.SCAN_SECONDS, scanSeconds = netscan.SCAN_SECONDS,
		passes = 0, emptyScans = 0, updatesLogged = 0,
		stats = netscan.newStats(0),
	}
end

--- Starts a scan pass (list, flatten, sweep, remove, read, encode + hand-off if anything changed).
function netscan.startScan(st : SquareMinimapNetState, now : number)
	st.stamp = st.stamp + 1
	st.stats = netscan.newStats(now)
	st.recolor = false
	st.phase = "list_s"
end

--- Ends a pass: back to idle until the next scan.
function netscan.endScan(st : SquareMinimapNetState, now : number)
	st.phase = "idle"
	st.waitUntilMs = now + st.scanSeconds * 1000
	st.flat, st.sweep, st.addedSet = nil, nil, nil
	st.addE, st.addKindE, st.remE, st.addB, st.addKindB, st.remB = nil, nil, nil, nil, nil, nil
	st.handoffList, st.staged = nil, nil -- strips handed off but not published stay pending
	st.yield = true
end

--- Starts an encode. A strip is encoded when it changed (a flagged band), is still pending from
--- an unpublished pass, or `all` / the first image / a palette switch: only its changed bands
--- when its buffer is kept, else every band into a new buffer. Unchanged strips cost nothing.
function netscan.startEncode(st : SquareMinimapNetState, all : boolean)
	st.encAll = all or st.image == nil or st.bufHiVis ~= st.hiVis
	st.handoffList, st.staged = nil, nil
	for s = 1, st.strips do
		local touched = st.encAll or st.pending[s] or net.stripDirty(st.grid, s)
		st.stripFull[s] = touched and (st.encAll or st.bufs[s] == nil)
		if touched then st.pending[s] = true end
	end
	st.phase, st.encBand = "encode", 1
end

function netscan.isHeavy(phase : string) : boolean
	return phase == "list_s" or phase == "list_t" or phase == "list_b" or phase == "handoff"
end

local function changeCount(st : SquareMinimapNetState) : integer
	return (st.addE and #st.addE or 0) + (st.remE and #st.remE or 0) + (st.addB and #st.addB or 0) + (st.remB and #st.remB or 0)
end

--- End of a scan pass (published or not): pass log, back-off, idle.
local function finishPass(st : SquareMinimapNetState, io : SquareMinimapNetIo, published : boolean)
	if st.recolor then
		if published then io.passDone(st, true) end
		st.recolor = false
		netscan.endScan(st, io.now())
		return
	end
	local changed = changeCount(st) > 0
	if changed then
		st.emptyScans = 0
	else
		st.emptyScans = st.emptyScans + 1
		io.perf:count("net_scan_empty")
	end
	st.scanSeconds = net.nextScanSeconds(st.scanSeconds, st.baseSeconds, changed or published, netscan.BACKOFF_MAX_SECONDS)
	if published or (changed and st.passes > 0) then io.passDone(st, published) end
	netscan.endScan(st, io.now())
end

local function listPhase(st : SquareMinimapNetState, io : SquareMinimapNetIo, which : integer) : {any : {integer}}
	local perf = io.perf
	local t0 = io.now()
	local tAll = perf:start()
	local tOne = perf:start()
	local map : {any : {integer}}
	if which == net.KIND_STREET then
		map = io.listStreets()
		perf:stop("net_list_streets", tOne)
	elseif which == net.KIND_TRACK then
		map = io.listTracks()
		perf:stop("net_list_tracks", tOne)
	else
		map = io.listBuildings()
		perf:stop("net_list_buildings", tOne)
	end
	perf:stop("net_list", tAll)
	st.stats.listMs = st.stats.listMs + (io.now() - t0)
	st.yield = true -- an engine list call is the only work of its frame
	return map
end

--- One flatten step; true when the map is done.
local function flattenPhase(st : SquareMinimapNetState, io : SquareMinimapNetIo, cache : {integer : SquareMinimapNetItem}) : boolean
	local perf = io.perf
	local t0 = io.now()
	local tAll = perf:start()
	local tOne = perf:start()
	local done = net.flattenStep(st.flat, cache, netscan.FLATTEN_CHUNK)
	perf:stop("net_flatten", tOne)
	perf:stop("net_diff", tAll)
	st.stats.flattenMs = st.stats.flattenMs + (io.now() - t0)
	return done
end

local function sweepPhase(st : SquareMinimapNetState, io : SquareMinimapNetIo, cache : {integer : SquareMinimapNetItem}) : boolean
	local perf = io.perf
	local t0 = io.now()
	local tAll = perf:start()
	local tOne = perf:start()
	local done = net.sweepStep(st.sweep, cache, netscan.SWEEP_CHUNK)
	perf:stop("net_sweep", tOne)
	perf:stop("net_diff", tAll)
	st.stats.sweepMs = st.stats.sweepMs + (io.now() - t0)
	return done
end

--- Reads up to READ_CHUNK new ids of `ids` (from st.idx), then draws them. True when the list is done.
local function readChunk(st : SquareMinimapNetState, io : SquareMinimapNetIo, ids : {integer}, kinds : {integer},
		cache : {integer : SquareMinimapNetItem}, isEdge : boolean) : boolean
	local s = st.stats
	local perf = io.perf
	local first = st.idx
	local last = math.min(#ids, first + netscan.READ_CHUNK - 1)
	local items = st.readBuf
	local n = 0
	local t0 = io.now()
	local tPerf = perf:start()
	for i = first, last do
		n = n + 1
		if isEdge then
			items[n] = io.readEdge(st, ids[i], kinds[i])
		else
			items[n] = io.readBuilding(st, ids[i])
		end
	end
	perf:stop("net_read", tPerf)
	local t1 = io.now()
	tPerf = perf:start()
	local grid = st.grid
	for k = 1, n do
		local it = items[k]
		items[k] = nil
		cache[ids[first + k - 1]] = it
		if it.kind == net.KIND_NONE then
			if isEdge then s.noGeom = s.noGeom + 1 else s.noBox = s.noBox + 1 end
		else
			if net.drawItem(grid, it, 1) > 0 then st.dirty = true end
			if it.kind == net.KIND_STREET then
				s.streets = s.streets + 1
			elseif it.kind == net.KIND_TRACK then
				s.tracks = s.tracks + 1
			end
			if it.dashed then s.tunnels = s.tunnels + 1 end
		end
	end
	perf:stop("net_raster", tPerf)
	local t2 = io.now()
	s.readMs = s.readMs + (t1 - t0)
	s.rasterMs = s.rasterMs + (t2 - t1)
	if isEdge then st.edgeCount = st.edgeCount + n else st.buildingCount = st.buildingCount + n end
	st.idx = last + 1
	return st.idx > #ids
end

--- Removes up to REMOVE_CHUNK ids (subtracting their pixels). True when the list is done.
local function removeChunk(st : SquareMinimapNetState, io : SquareMinimapNetIo, ids : {integer},
		cache : {integer : SquareMinimapNetItem}, isEdge : boolean) : boolean
	local last = math.min(#ids, st.idx + netscan.REMOVE_CHUNK - 1)
	local t0 = io.now()
	local tPerf = io.perf:start()
	for i = st.idx, last do
		local id = ids[i]
		local it = cache[id]
		if it ~= nil then
			if net.drawItem(st.grid, it, -1) > 0 then st.dirty = true end
			cache[id] = nil
			if isEdge then st.edgeCount = st.edgeCount - 1 else st.buildingCount = st.buildingCount - 1 end
		end
	end
	io.perf:stop("net_raster", tPerf)
	st.stats.rasterMs = st.stats.rasterMs + (io.now() - t0)
	st.idx = last + 1
	return st.idx > #ids
end

--- One encode step: skips unchanged bands, encodes the next one that needs it. When all bands are
--- done the pending strips are handed off, one per frame (next frames).
local function encodeStep(st : SquareMinimapNetState, io : SquareMinimapNetIo)
	local perf = io.perf
	local t0 = io.now()
	local tPerf = perf:start()
	local g = st.grid
	local nb = net.bandCount(g)
	local b = st.encBand
	while b <= nb do
		local s = net.stripOfBand(b)
		local full = st.stripFull[s]
		local out = st.bufs[s]
		local done = false
		if full or out ~= nil then
			if out == nil then
				out = {}
				st.bufs[s] = out
			end
			done = net.encodeStripBand(g, out, b, st.palette, io.flipRows, full)
		end
		b = b + 1
		if done then
			st.stats.bands = st.stats.bands + 1
			perf:count("net_bands")
			break
		end
	end
	st.encBand = b
	if b > nb then
		if io.calibrate ~= nil then io.calibrate(st) end
		st.bufHiVis = st.hiVis
		local list : {integer} = {}
		for s = 1, st.strips do
			if st.pending[s] then list[#list + 1] = s end
		end
		st.handoffList, st.handoffIdx, st.staged = list, 1, {}
		st.phase = "handoff"
	end
	perf:stop("net_encode", tPerf)
	st.stats.encodeMs = st.stats.encodeMs + (io.now() - t0)
end

--- One hand-off step: strip handoffList[handoffIdx] to the engine (staged, not shown); after the
--- last one, publish them all together. True when a new image was published.
local function handoffStep(st : SquareMinimapNetState, io : SquareMinimapNetIo) : boolean
	st.yield = true -- one hand-off per frame, and the only work of it
	local list = st.handoffList
	local i = st.handoffIdx
	if i <= #list then
		local s = list[i]
		if not io.handoff(st, s) then
			st.staged = nil
			finishPass(st, io, false)
			return false
		end
		st.stats.stripsHanded = st.stats.stripsHanded + 1
		io.perf:count("net_strips_handed")
		st.handoffIdx = i + 1
		if i < #list then return false end
	end
	-- Every changed strip is staged (the last hand-off was this frame's; the publish itself is
	-- no copy: a version bump and a re-render that builds only the changed strips' nodes).
	local published = #list > 0 and io.publish(st)
	if published then
		for _, s in ipairs(list) do st.pending[s] = nil end
		st.dirty = false
		st.passes = st.passes + 1
		io.perf:count("net_publish")
	elseif #list == 0 then
		st.dirty = false -- nothing visible changed
	end
	st.staged = nil
	finishPass(st, io, published)
	return published
end

function netscan.work(st : SquareMinimapNetState, io : SquareMinimapNetIo, _deadline : number) : boolean
	local phase = st.phase
	if phase == "list_s" or phase == "list_t" then
		local isStreets = phase == "list_s"
		local map = listPhase(st, io, isStreets and net.KIND_STREET or net.KIND_TRACK)
		if map == nil then netscan.endScan(st, io.now()); return false end
		if isStreets then
			st.addE, st.addKindE, st.addedSet = {}, {}, {}
			io.perf:count("net_scan")
		end
		st.flat = net.newFlatten(map, isStreets and net.KIND_STREET or net.KIND_TRACK, st.stamp, st.addE, st.addKindE, st.addedSet)
		st.phase = isStreets and "flat_s" or "flat_t"
	elseif phase == "flat_s" then
		if flattenPhase(st, io, st.edges) then st.flat, st.phase = nil, "list_t" end
	elseif phase == "flat_t" then
		if flattenPhase(st, io, st.edges) then
			st.flat, st.remE = nil, {}
			st.sweep = net.newSweep(st.stamp, st.remE)
			st.phase = "sweep_e"
		end
	elseif phase == "sweep_e" then
		if sweepPhase(st, io, st.edges) then st.sweep, st.phase = nil, "list_b" end
	elseif phase == "list_b" then
		local map = listPhase(st, io, net.KIND_TOWN)
		if map == nil then netscan.endScan(st, io.now()); return false end
		st.baseSeconds = net.scanInterval(st.stats.listMs, netscan.SCAN_SECONDS, netscan.SCAN_MAX_SECONDS, netscan.SCAN_FACTOR)
		st.addB, st.addKindB, st.addedSet = {}, {}, {}
		st.flat = net.newFlatten(map, net.KIND_TOWN, st.stamp, st.addB, st.addKindB, st.addedSet)
		st.phase = "flat_b"
	elseif phase == "flat_b" then
		if flattenPhase(st, io, st.buildings) then
			st.flat, st.addedSet, st.remB = nil, nil, {}
			st.sweep = net.newSweep(st.stamp, st.remB)
			st.phase = "sweep_b"
		end
	elseif phase == "sweep_b" then
		if sweepPhase(st, io, st.buildings) then st.sweep, st.phase, st.idx = nil, "remove_e", 1 end
	elseif phase == "remove_e" then
		if removeChunk(st, io, st.remE, st.edges, true) then st.phase, st.idx = "remove_b", 1 end
	elseif phase == "remove_b" then
		if removeChunk(st, io, st.remB, st.buildings, false) then st.phase, st.idx = "read_e", 1 end
	elseif phase == "read_e" then
		if readChunk(st, io, st.addE, st.addKindE, st.edges, true) then st.phase, st.idx = "read_b", 1 end
	elseif phase == "read_b" then
		if readChunk(st, io, st.addB, st.addKindB, st.buildings, false) then
			if st.dirty then
				netscan.startEncode(st, io.calibrate ~= nil)
			else
				finishPass(st, io, false)
			end
		end
	elseif phase == "encode" then
		encodeStep(st, io)
	elseif phase == "handoff" then
		return handoffStep(st, io)
	end
	return false
end

function netscan.run(st : SquareMinimapNetState, io : SquareMinimapNetIo, budgetMs : number) : boolean
	local deadline = io.now() + budgetMs
	st.yield = false
	st.stats.frames = st.stats.frames + 1
	local published = false
	local first = true
	repeat
		-- An unsliced call (engine list, hand-off) only as the first work of a frame.
		if not first and netscan.isHeavy(st.phase) then break end
		if netscan.work(st, io, deadline) then published = true end
		first = false
	until st.phase == "idle" or st.yield or io.now() >= deadline
	return published
end

return netscan
