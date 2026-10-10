-- minimap_netscan (network layer scheduler) against a fake engine: frame structure (list calls and
-- the hand-off alone in their frames), no work when nothing changed, back-off, partial encodes that
-- equal a full one, list failures. The game side (minimap_hud.script.tl) only adds the real io.

local net = ug_require "square_better_minimap::/minimap/minimap_net.tl"
local netscan = ug_require "square_better_minimap::/minimap/minimap_netscan.tl"
local geom = ug_require "square_better_minimap::/minimap/minimap_geom.tl"

local ORIENT = geom.DEFAULT_ORIENT
local BOX = geom.boxFromBounds(0, 0, 2000, 2000)
local LONG = 200 -- 200 x 200 image: 4 strips, the last one 8 rows

-- fake world ---------------------------------------------------------------

local function newWorld()
	return { streets = {}, tracks = {}, buildings = {}, edge = {}, bld = {}, failTracks = false }
end

-- An edge between two nodes (listed at both, like the street system's node maps).
local function addEdge(world, id, kind, x0, y0, x1, y1, tunnel)
	local map = kind == net.KIND_TRACK and world.tracks or world.streets
	local na, nb = 100000 + id * 2, 100001 + id * 2
	map[na] = { id }
	map[nb] = { id }
	world.edge[id] = { x0, y0, x1, y1, tunnel or false, map, na, nb }
end

local function removeEdge(world, id)
	local e = world.edge[id]
	e[6][e[7]] = nil
	e[6][e[8]] = nil
	world.edge[id] = nil
end

local function addBuilding(world, id, town, x, y, s)
	world.buildings[town] = world.buildings[town] or {}
	table.insert(world.buildings[town], id)
	world.bld[id] = { x - s, y - s, x + s, y + s, town }
end

local function removeBuilding(world, id)
	local b = world.bld[id]
	local list = world.buildings[b[5]]
	for i = #list, 1, -1 do if list[i] == id then table.remove(list, i) end end
	world.bld[id] = nil
end

--- Copies of the maps, as the engine returns a fresh table per call.
local function copyMap(m)
	local c = {}
	for k, v in pairs(m) do
		local a = {}
		for i, e in ipairs(v) do a[i] = e end
		c[k] = a
	end
	return c
end

local function edgeItem(st, e, kind)
	return {
		seen = st.stamp, kind = kind, dashed = e[5],
		pts = net.hermitePolyline(st.xf, e[1], e[2], e[3] - e[1], e[4] - e[2], e[3], e[4], e[3] - e[1], e[4] - e[2]),
	}
end

local function bldItem(st, b)
	local x0, y0, x1, y1 = net.rectFromBounds(st.xf, b[1], b[2], b[3], b[4])
	return { seen = st.stamp, kind = net.KIND_TOWN, x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

-- fake io ------------------------------------------------------------------

local function newIo(world)
	local io = { T = 0, events = nil, counts = {}, published = {}, reads = 0, flipRows = true }
	local function ev(name)
		if io.events then io.events[#io.events + 1] = name end
		io.counts[name] = (io.counts[name] or 0) + 1
	end
	io.now = function()
		io.T = io.T + 0.01 -- every clock read is 10 us of "work": a 2 ms frame is ~200 reads
		return io.T
	end
	io.listStreets = function() ev("listS"); return copyMap(world.streets) end
	io.listTracks = function()
		ev("listT")
		if world.failTracks then return nil end
		return copyMap(world.tracks)
	end
	io.listBuildings = function() ev("listB"); return copyMap(world.buildings) end
	io.readEdge = function(st, id, kind)
		ev("read"); io.reads = io.reads + 1
		return edgeItem(st, world.edge[id], kind)
	end
	io.readBuilding = function(st, id)
		ev("read"); io.reads = io.reads + 1
		return bldItem(st, world.bld[id])
	end
	-- The params path: a hand-off copies the strip (the Lua buffer is kept and reused); the publish
	-- swaps every staged strip in at once. io.shown holds what the engine shows per strip.
	io.shown = {}
	io.handed = {}
	io.handoff = function(st, s)
		ev("handoff")
		io.handed[#io.handed + 1] = s
		if io.failHandoff == s then return false end
		local buf = st.bufs[s]
		local r0, r1 = net.stripRange(st.h, s)
		assert(#buf == net.expectedLength(st.w, r1 - r0), "strip " .. s .. " length")
		local snap = {}
		for i = 1, #buf do snap[i] = buf[i] end
		st.staged[s] = { data = snap, r0 = r0, r1 = r1 }
		return true
	end
	io.publish = function(st)
		ev("publish")
		st.version = st.version + 1
		local strips = {}
		for s = 1, st.strips do
			if st.staged[s] then
				st.staged[s].version = st.version
				io.shown[s] = st.staged[s]
			end
			strips[s] = io.shown[s]
		end
		st.image = { strips = strips, w = st.w, h = st.h, version = st.version, atMs = io.T }
		-- the whole picture as one bottom-up image: the strips last to first (flipRows)
		local full = {}
		for s = st.strips, 1, -1 do
			local d = io.shown[s].data
			for i = 1, #d do full[#full + 1] = d[i] end
		end
		io.published[#io.published + 1] = full
		return true
	end
	io.passes = 0
	io.passDone = function(st, published) io.passes = io.passes + 1 end
	local perfCounts = {}
	io.perfCounts = perfCounts
	io.perf = {
		start = function() return 0 end,
		stop = function(_, name) perfCounts[name] = (perfCounts[name] or 0) + 1; return 0 end,
		count = function(_, name, n) perfCounts[name] = (perfCounts[name] or 0) + (n or 1) end,
	}
	return io
end

--- One scan from idle to idle; returns the per-frame io events.
local function scan(st, io)
	if st.waitUntilMs > io.T then io.T = st.waitUntilMs end
	assert(st.phase == "idle")
	netscan.startScan(st, io.T)
	local frames = {}
	for _ = 1, 100000 do
		io.events = {}
		netscan.run(st, io, 2.0)
		frames[#frames + 1] = io.events
		if st.phase == "idle" then break end
	end
	io.events = nil
	assert(st.phase == "idle", "scan did not finish")
	return frames
end

local function resetCounts(io)
	io.counts = {}
	for k in pairs(io.perfCounts) do io.perfCounts[k] = nil end
	io.reads = 0
end

--- The image a direct raster + full encode of the world gives (reference).
local function reference(st, world)
	local g = net.newGrid(st.w, st.h)
	local ids = {}
	for id in pairs(world.edge) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do
		local e = world.edge[id]
		net.drawItem(g, edgeItem(st, e, e[6] == world.tracks and net.KIND_TRACK or net.KIND_STREET), 1)
	end
	for _, b in pairs(world.bld) do net.drawItem(g, bldItem(st, b), 1) end
	local out = {}
	net.encodeRows(g, out, 0, st.h, st.palette, true)
	return out
end

local function sampleWorld()
	local w = newWorld()
	local seed = 99
	local function rnd(n) seed = (seed * 1103515245 + 12345) % 2147483648; return seed % n end
	for id = 1, 120 do
		local x, y = rnd(2000), rnd(2000)
		addEdge(w, id, (id % 4 == 0) and net.KIND_TRACK or net.KIND_STREET, x, y, x + rnd(300) - 150, y + rnd(300) - 150, id % 9 == 0)
	end
	for id = 1001, 1080 do addBuilding(w, id, 1 + id % 5, rnd(2000), rnd(2000), 10 + rnd(30)) end
	return w
end

local function newSt()
	return netscan.newState(BOX, ORIENT, LONG, false, "RGBA")
end

-- tests ----------------------------------------------------------------------

test("first scan: one image equal to a direct raster; list calls and the hand-off alone in their frames", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	local frames = scan(st, io)
	eq(#io.published, 1)
	eq(st.edgeCount, 120)
	eq(st.buildingCount, 80)
	eq(io.reads, 200, "every id read once (edges are listed at both nodes)")
	eq(io.published[1], reference(st, world))
	eq(st.strips, 4)
	local heavy = { listS = true, listT = true, listB = true, handoff = true }
	local order = {}
	for _, evs in ipairs(frames) do
		for i, e in ipairs(evs) do
			if heavy[e] then
				-- the publish (no copy) follows the last strip's hand-off in the same frame
				local alone = #evs == 1 or (e == "handoff" and #evs == 2 and evs[2] == "publish")
				ok(alone, e .. " shares its frame with " .. table.concat(evs, ","))
				order[#order + 1] = e
			elseif e == "publish" then
				order[#order + 1] = e
			end
		end
	end
	eq(order, { "listS", "listT", "listB", "handoff", "handoff", "handoff", "handoff", "publish" })
	eq(io.handed, { 1, 2, 3, 4 })
	eq(io.perfCounts.net_strips_handed, 4)
	eq(io.perfCounts.net_bands, net.bandCount(st.grid), "a fresh buffer: every band encoded")
	eq(st.scanSeconds, netscan.SCAN_SECONDS)
end)

test("nothing changed: the scan lists but reads, encodes and publishes nothing; it backs off to the cap", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	local seen = {}
	for i = 1, 6 do
		resetCounts(io)
		local before = #io.published
		local frames = scan(st, io)
		eq(io.counts.listS, 1); eq(io.counts.listT, 1); eq(io.counts.listB, 1)
		eq(io.reads, 0)
		eq(io.perfCounts.net_bands, nil, "no band encoded")
		eq(io.perfCounts.net_encode, nil, "no encode step")
		eq(#io.published, before, "no publish")
		eq(io.counts.handoff, nil, "no hand-off")
		eq(io.perfCounts.net_scan_empty, 1)
		ok(#frames <= 12, "a quiet scan is a handful of frames, got " .. #frames)
		seen[i] = st.scanSeconds
	end
	eq(seen, { 10, 20, 30, 30, 30, 30 })
	-- a change resets the interval
	addEdge(world, 500, net.KIND_STREET, 100, 100, 400, 300)
	scan(st, io)
	eq(st.scanSeconds, netscan.SCAN_SECONDS)
	eq(st.emptyScans, 0)
end)

test("an update re-encodes only the changed bands and the kept buffer equals a full encode", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	-- a short street in one corner, a building removed elsewhere, an edge removed
	addEdge(world, 900, net.KIND_STREET, 50, 1900, 120, 1950)
	removeBuilding(world, 1010)
	removeEdge(world, 7)
	resetCounts(io)
	scan(st, io)
	eq(#io.published, 2)
	eq(io.reads, 1)
	eq(st.edgeCount, 120)
	eq(st.buildingCount, 79)
	ok(io.perfCounts.net_bands < net.bandCount(st.grid), "partial: " .. tostring(io.perfCounts.net_bands) .. " of " .. net.bandCount(st.grid) .. " bands")
	eq(io.published[2], reference(st, world))
	-- and back
	removeEdge(world, 900)
	resetCounts(io)
	scan(st, io)
	eq(io.published[3], reference(st, world))
end)

test("a change that touches no pixel publishes nothing (and is not an empty scan)", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	-- an edge outside the image
	addEdge(world, 901, net.KIND_STREET, 5000, 5000, 5100, 5100)
	resetCounts(io)
	scan(st, io)
	eq(#io.published, 1)
	eq(io.reads, 1)
	eq(io.passes, 2, "logged as an update without a visible change")
	eq(st.scanSeconds, netscan.SCAN_SECONDS)
end)

test("a failed list call skips the scan: nothing removed, nothing published", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	removeEdge(world, 3)
	world.failTracks = true
	resetCounts(io)
	scan(st, io)
	eq(io.counts.listB, nil, "stops at the failed call")
	eq(st.edgeCount, 120)
	eq(#io.published, 1)
	world.failTracks = false
	scan(st, io)
	eq(st.edgeCount, 119)
	eq(io.published[2], reference(st, world))
end)

test("palette switch: an encode-only pass of every band, no list call, no read", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	resetCounts(io)
	st.hiVis = true
	st.palette = net.paletteFor(true, "RGBA")
	eq(net.recolorAction(st.phase, true), "encode")
	st.recolor = true
	netscan.startEncode(st, true)
	for _ = 1, 1000 do
		netscan.run(st, io, 2.0)
		if st.phase == "idle" then break end
	end
	eq(st.phase, "idle")
	eq(io.counts.listS, nil)
	eq(io.reads, 0)
	eq(io.perfCounts.net_bands, net.bandCount(st.grid))
	eq(io.published[2], reference(st, world))
	-- a later quiet scan keeps the hi-vis buffer and encodes nothing
	resetCounts(io)
	scan(st, io)
	eq(io.perfCounts.net_bands, nil)
end)

test("a palette change during a scan makes that pass encode every band", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	addEdge(world, 902, net.KIND_TRACK, 10, 10, 30, 30)
	if st.waitUntilMs > io.T then io.T = st.waitUntilMs end
	netscan.startScan(st, io.T)
	netscan.run(st, io, 2.0) -- list_s
	ok(st.phase ~= "idle")
	st.hiVis = true
	st.palette = net.paletteFor(true, "RGBA")
	eq(net.recolorAction(st.phase, true), "dirty")
	st.dirty = true
	resetCounts(io)
	for _ = 1, 1000 do
		netscan.run(st, io, 2.0)
		if st.phase == "idle" then break end
	end
	eq(io.perfCounts.net_bands, net.bandCount(st.grid))
	eq(io.published[2], reference(st, world))
end)

test("a frame never runs past its budget by more than one small step", function()
	local world = newWorld()
	for id = 1, 3000 do addEdge(world, id, net.KIND_STREET, (id * 37) % 2000, (id * 91) % 2000, (id * 53) % 2000, (id * 17) % 2000) end
	local io = newIo(world)
	local st = newSt()
	if st.waitUntilMs > io.T then io.T = st.waitUntilMs end
	netscan.startScan(st, io.T)
	local worst = 0
	for _ = 1, 100000 do
		local t0 = io.T
		netscan.run(st, io, 2.0)
		local dt = io.T - t0
		if dt > worst then worst = dt end
		if st.phase == "idle" then break end
	end
	eq(#io.published, 1)
	-- fake clock: 10 us per read; a read chunk is READ_CHUNK reads + a few clock reads
	ok(worst < 2.0 + 0.5, "worst frame " .. worst .. " ms")
end)

-- strips -------------------------------------------------------------------

--- Runs a scan and returns the frames' events plus the image versions seen after each frame.
local function scanVersions(st, io)
	if st.waitUntilMs > io.T then io.T = st.waitUntilMs end
	netscan.startScan(st, io.T)
	local frames, versions = {}, {}
	for _ = 1, 100000 do
		io.events = {}
		netscan.run(st, io, 2.0)
		frames[#frames + 1] = io.events
		versions[#versions + 1] = st.image and st.image.version or 0
		if st.phase == "idle" then break end
	end
	io.events = nil
	return frames, versions
end

test("an update in one strip hands off only that strip; the others keep their version", function()
	local world = newWorld()
	for id = 1, 40 do addEdge(world, id, net.KIND_STREET, 100 + id * 40, 100, 100 + id * 40, 1900) end -- all strips
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	eq(#io.published, 1)
	local before = {}
	for s = 1, st.strips do before[s] = st.image.strips[s] end
	-- a short street near the map's top edge: world y 1900+ is image row ~0 (north up)
	addEdge(world, 500, net.KIND_STREET, 900, 1960, 960, 1980)
	resetCounts(io)
	io.handed = {}
	local frames, versions = scanVersions(st, io)
	eq(#io.published, 2)
	eq(io.handed, { 1 }, "only the top strip")
	ok(io.perfCounts.net_bands <= 2, "1-2 bands, got " .. tostring(io.perfCounts.net_bands))
	eq(io.published[2], reference(st, world))
	eq(st.image.strips[1].version, st.image.version)
	for s = 2, st.strips do
		ok(st.image.strips[s] == before[s], "strip " .. s .. " is the same object (its node is reused)")
		ok(st.image.strips[s].version < st.image.version)
	end
	-- and one in the bottom strip (8 rows), then the middle: one strip each
	addEdge(world, 501, net.KIND_TRACK, 300, 5, 340, 12)
	resetCounts(io); io.handed = {}
	scan(st, io)
	eq(io.handed, { 4 })
	eq(io.published[3], reference(st, world))
	removeEdge(world, 500)
	addBuilding(world, 7001, 1, 1000, 1000, 15)
	resetCounts(io); io.handed = {}
	scan(st, io)
	eq(io.handed, { 1, 2 })
	eq(io.published[4], reference(st, world))
end)

test("one hand-off per frame, and the picture switches only once every changed strip is ready", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	-- palette switch: every strip changes
	st.hiVis = true
	st.palette = net.paletteFor(true, "RGBA")
	st.recolor = true
	netscan.startEncode(st, true)
	resetCounts(io); io.handed = {}
	local v0 = st.image.version
	local frames, versions = {}, {}
	for _ = 1, 1000 do
		io.events = {}
		netscan.run(st, io, 2.0)
		frames[#frames + 1] = io.events
		versions[#versions + 1] = st.image.version
		if st.phase == "idle" then break end
	end
	io.events = nil
	eq(io.handed, { 1, 2, 3, 4 })
	local handoffFrames = 0
	for i, evs in ipairs(frames) do
		local n = 0
		for _, e in ipairs(evs) do if e == "handoff" then n = n + 1 end end
		ok(n <= 1, "frame " .. i .. " has " .. n .. " hand-offs")
		if n == 1 then
			handoffFrames = handoffFrames + 1
			local last = handoffFrames == 4
			eq(versions[i], last and v0 + 1 or v0, "version after hand-off " .. handoffFrames)
		end
	end
	eq(handoffFrames, 4)
	eq(io.published[2], reference(st, world))
end)

test("a failed hand-off publishes nothing; the next scan hands the pending strips off again", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	addEdge(world, 600, net.KIND_STREET, 100, 1950, 1900, 1950) -- top strip
	addEdge(world, 601, net.KIND_STREET, 100, 30, 1900, 30)     -- bottom strips
	resetCounts(io); io.handed = {}
	io.failHandoff = 4
	local v = st.image.version
	scan(st, io)
	eq(st.image.version, v, "nothing shown")
	eq(#io.published, 1)
	ok(st.pending[1] and st.pending[4], "both strips still pending")
	eq(st.dirty, true)
	io.failHandoff = nil
	resetCounts(io); io.handed = {}
	scan(st, io) -- the world didn't change: no read, but the pending strips go out
	eq(io.reads, 0)
	ok(#io.handed >= 2 and io.handed[1] == 1 and io.handed[#io.handed] == 4, "strips 1 .. 4 handed: " .. table.concat(io.handed, ","))
	eq(#io.published, 2)
	eq(io.published[2], reference(st, world))
	eq(next(st.pending), nil)
	-- and quiet afterwards
	resetCounts(io); io.handed = {}
	scan(st, io)
	eq(#io.handed, 0)
end)

test("after the encode buffers are dropped (Net parked), a change re-encodes only its strip, whole", function()
	local world = sampleWorld()
	local io = newIo(world)
	local st = newSt()
	scan(st, io)
	st.bufs = {} -- netPark drops them
	addEdge(world, 700, net.KIND_STREET, 900, 1960, 960, 1980) -- top strip only
	resetCounts(io); io.handed = {}
	scan(st, io)
	eq(io.handed, { 1 })
	eq(io.perfCounts.net_bands, net.STRIP_BANDS, "strip 1 encoded whole (8 bands), nothing else")
	eq(io.published[2], reference(st, world))
	ok(st.bufs[1] ~= nil and st.bufs[2] == nil and st.bufs[3] == nil, "only strip 1 has a buffer again")
	-- a later change in strip 1 only rewrites its changed band
	addEdge(world, 701, net.KIND_STREET, 1500, 1960, 1520, 1965)
	resetCounts(io); io.handed = {}
	scan(st, io)
	eq(io.handed, { 1 })
	ok(io.perfCounts.net_bands <= 2)
	eq(io.published[3], reference(st, world))
end)

test("the unflipped row order: strips joined first to last equal the reference", function()
	local world = sampleWorld()
	local io = newIo(world)
	io.flipRows = false
	local st = newSt()
	scan(st, io)
	local full = {}
	for s = 1, st.strips do
		local d = st.image.strips[s].data
		for i = 1, #d do full[#full + 1] = d[i] end
	end
	local g = st.grid
	local ref = {}
	net.encodeRows(g, ref, 0, st.h, st.palette, false)
	eq(full, ref)
end)
