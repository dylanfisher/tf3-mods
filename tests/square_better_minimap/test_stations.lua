-- minimap_stations (station icons, Stn, PLAN.md phase 8) against a fake engine:
-- path classification, icon choice, dedupe per construction, cargo vs passenger, only new stations
-- read, removals swept, frame structure (the list call alone in its frame), caps, back-off.

local stations = ug_require "square_better_minimap::/minimap/minimap_stations.tl"

-- fake world ---------------------------------------------------------------

local function newWorld()
	return { list = {}, con = {}, path = {}, pax = {}, pos = {}, reads = 0, lists = 0, failList = false, failCon = {} }
end

-- A construction `con` at path with stations { [id] = passenger }.
local function addCon(world, con, path, sts, x, y)
	world.path[con] = path
	world.pos[con] = x and { x, y } or nil
	for id, pax in pairs(sts) do
		world.con[id] = con
		world.pax[id] = pax
	end
end

local function relist(world)
	local ids = {}
	for id in pairs(world.con) do ids[#ids + 1] = id end
	table.sort(ids)
	world.list = ids
end

local function newIo(world)
	local t = 0
	local perf = { counts = {} }
	function perf:start() return 0 end
	function perf:stop() return 0 end
	function perf:count(name, n) self.counts[name] = (self.counts[name] or 0) + (n or 1) end
	local io = { passes = 0, frameLists = 0 }
	io.now = function() t = t + 0.01; return t end
	io.listStations = function()
		world.lists = world.lists + 1
		io.frameLists = io.frameLists + 1
		if world.failList then return nil end
		local copy = {}
		for i, id in ipairs(world.list) do copy[i] = id end
		return copy
	end
	io.conOf = function(id)
		world.reads = world.reads + 1
		if world.failCon[id] then return nil end
		local c = world.con[id]
		if c == nil then return -1 end
		return c
	end
	io.pathOf = function(con) world.reads = world.reads + 1; return world.path[con] end
	io.isPassenger = function(id) world.reads = world.reads + 1; return world.pax[id] end
	io.posOf = function(con)
		world.reads = world.reads + 1
		local p = world.pos[con]
		if p == nil then return nil end
		return p[1], p[2]
	end
	io.passDone = function() io.passes = io.passes + 1 end
	io.perf = perf
	return io
end

-- Runs frames until the pass ends; checks at most one list call per frame. Returns frames, changed.
local function runPass(st, io, budget)
	stations.startScan(st, io.now())
	local frames, changed = 0, false
	while st.phase ~= "idle" do
		io.frameLists = 0
		if stations.run(st, io, budget or 1e9) then changed = true end
		ok(io.frameLists <= 1, "at most one list call per frame")
		frames = frames + 1
		ok(frames < 10000, "pass ends")
		if frames >= 10000 then break end
	end
	return frames, changed
end

local ALL = { rail = true, air = true, water = true }

local function iconsOf(st)
	local out = {}
	for _, it in ipairs(stations.items(st)) do out[#out + 1] = it.entity .. "=" .. it.icon end
	return table.concat(out, " ")
end

-- tests ----------------------------------------------------------------------

test("kindOfPath: base, plain and mod paths; others nil", function()
	eq(stations.kindOfPath("::/stations/rail/modular_station/modular_station.con"), "rail")
	eq(stations.kindOfPath("stations/air/airport.con"), "air")
	eq(stations.kindOfPath("::/stations/air/airfield.con"), "air")
	eq(stations.kindOfPath("::/stations/water/harbor_modular.con"), "water")
	eq(stations.kindOfPath("some_mod::/stations/rail/my_station.con"), "rail")
	eq(stations.kindOfPath("::/stations/street/modular_street_station/modular_terminal.con"), nil)
	eq(stations.kindOfPath("::/industries/coal_mine/coal_mine.con"), nil)
	eq(stations.kindOfPath("::/landmarks/lighthouse/lighthouse.con"), nil)
	eq(stations.kindOfPath("::/depots/rail/rail_depot.con"), nil)
	eq(stations.kindOfPath("mystations/rail/x.con"), nil)
	eq(stations.kindOfPath(nil), nil)
	eq(stations.kindOfPath(""), nil)
end)

test("iconFor: the game's HUD station icons, passenger vs cargo", function()
	eq(stations.iconFor("rail", true), "::/gui/hud/icons/vehicle_train_front_32.tga")
	eq(stations.iconFor("rail", false), "::/gui/hud/icons/vehicle_train_front_32.tga")
	eq(stations.iconFor("air", true), "::/gui/hud/icons/vehicle_airplane_front_32.tga")
	eq(stations.iconFor("air", false), "::/gui/hud/icons/vehicle_airplane_front_32.tga")
	eq(stations.iconFor("water", true), "::/gui/hud/icons/vehicle_ship_front_32.tga")
	eq(stations.iconFor("water", false), "::/gui/hud/icons/vehicle_ship_front_32.tga")
	eq(stations.iconFor("street", true), nil)
end)

test("anyEnabled", function()
	eq(stations.anyEnabled(nil), false)
	eq(stations.anyEnabled({}), false)
	eq(stations.anyEnabled({ rail = false, air = false, water = false }), false)
	eq(stations.anyEnabled({ water = true }), true)
end)

local function sampleWorld()
	local w = newWorld()
	addCon(w, 100, "::/stations/rail/modular_station/modular_station.con", { [1] = true, [2] = false }, 10, 20) -- mixed: passenger
	addCon(w, 101, "::/stations/rail/modular_station/modular_station.con", { [3] = false }, 30, 40)            -- cargo
	addCon(w, 102, "::/stations/air/airport.con", { [4] = true, [5] = true }, 50, 60)
	addCon(w, 103, "::/stations/air/airfield.con", { [6] = false }, 70, 80)
	addCon(w, 104, "::/stations/water/harbor_modular.con", { [7] = true }, 90, 100)
	addCon(w, 105, "::/industries/coal_mine/coal_mine.con", { [8] = true }, 1, 1)                             -- industry: true/true, never shown
	addCon(w, 106, "::/stations/street/modular_street_station/modular_terminal.con", { [9] = true }, 2, 2)
	w.con[10] = nil -- curbside stop: no construction
	w.pax[10] = true
	relist(w)
	w.list[#w.list + 1] = 10
	return w
end

test("first pass: one icon per construction, passenger if any station is", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState(ALL)
	local _, changed = runPass(st, io)
	ok(changed, "version bumped")
	eq(st.version, 1)
	eq(iconsOf(st), table.concat({
		"100=::/gui/hud/icons/vehicle_train_front_32.tga",
		"101=::/gui/hud/icons/vehicle_train_front_32.tga",
		"102=::/gui/hud/icons/vehicle_airplane_front_32.tga",
		"103=::/gui/hud/icons/vehicle_airplane_front_32.tga",
		"104=::/gui/hud/icons/vehicle_ship_front_32.tga",
	}, " "))
	local per, pax = stations.counts(st)
	eq(per.rail, 2); eq(per.air, 2); eq(per.water, 1); eq(pax, 3)
	eq(st.stationCount, 10)
	local items = stations.items(st)
	eq(items[1].x, 10); eq(items[1].y, 20); eq(items[1].typeKey, "station:rail")
end)

test("settings: only enabled kinds are shown; their reads are skipped", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState({ air = true })
	runPass(st, io)
	eq(iconsOf(st), "102=::/gui/hud/icons/vehicle_airplane_front_32.tga 103=::/gui/hud/icons/vehicle_airplane_front_32.tga")
	-- 10 conOf + 7 pathOf (one per construction) + 3 isPassenger (air stations) + 2 posOf (air cons)
	eq(w.reads, 10 + 7 + 3 + 2)
end)

test("a second pass with nothing changed reads nothing and bumps no version", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState(ALL)
	runPass(st, io)
	local reads = w.reads
	local _, changed = runPass(st, io)
	eq(changed, false)
	eq(st.version, 1)
	eq(w.reads, reads, "no engine read for cached stations")
end)

test("only new stations are read; removed ones swept; icon follows the remaining stations", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState(ALL)
	runPass(st, io)
	-- New harbor, airport gone, rail 100 loses its passenger station (cargo only now).
	addCon(w, 107, "::/stations/water/harbor_modular.con", { [11] = false }, 5, 5)
	w.con[4], w.con[5] = nil, nil
	w.con[1] = nil
	relist(w)
	w.list[#w.list + 1] = 10
	local reads = w.reads
	local _, changed = runPass(st, io)
	ok(changed, "version bumped")
	eq(w.reads - reads, 4, "new station 11: conOf, pathOf, isPassenger, posOf")
	eq(iconsOf(st), table.concat({
		"100=::/gui/hud/icons/vehicle_train_front_32.tga",
		"101=::/gui/hud/icons/vehicle_train_front_32.tga",
		"103=::/gui/hud/icons/vehicle_airplane_front_32.tga",
		"104=::/gui/hud/icons/vehicle_ship_front_32.tga",
		"107=::/gui/hud/icons/vehicle_ship_front_32.tga",
	}, " "))
	eq(st.cons[102], nil, "empty construction dropped")
	eq(st.stationCount, 8)
end)

test("a new station joining a known construction reads no path or position", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState(ALL)
	runPass(st, io)
	w.con[12] = 103
	w.pax[12] = true
	w.list[#w.list + 1] = 12
	local reads = w.reads
	runPass(st, io)
	eq(w.reads - reads, 2, "conOf + isPassenger")
	ok(iconsOf(st):find("103=::/gui/hud/icons/vehicle_airplane_front_32.tga", 1, true), "airfield turns passenger")
end)

test("a failed list call removes nothing; a failed construction read is retried next pass", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState(ALL)
	w.failCon[3] = true
	runPass(st, io)
	eq(st.stats.readFailed, 1)
	ok(not iconsOf(st):find("101=", 1, true), "101 not read yet")
	w.failList = true
	local _, changed = runPass(st, io)
	eq(changed, false)
	eq(st.stationCount, 9)
	w.failList, w.failCon[3] = false, nil
	runPass(st, io)
	ok(iconsOf(st):find("101=::/gui/hud/icons/vehicle_train_front_32.tga", 1, true), "101 read on retry")
end)

test("a construction without position is never shown nor re-read", function()
	local w = sampleWorld()
	w.pos[104] = nil
	local io = newIo(w)
	local st = stations.newState(ALL)
	runPass(st, io)
	eq(st.stats.noPos, 1)
	ok(not iconsOf(st):find("104=", 1, true))
end)

test("duplicate ids in the list are counted once", function()
	local w = sampleWorld()
	w.list[#w.list + 1] = 1
	local io = newIo(w)
	local st = stations.newState(ALL)
	runPass(st, io)
	eq(st.cons[100].refs, 2)
	eq(st.stationCount, 10)
end)

test("frames: tiny budget slices the pass; list call first in its frame; step cap holds", function()
	local w = newWorld()
	for c = 1, 300 do
		local sts = {}
		for k = 1, 3 do sts[c * 10 + k] = (k == 1) end
		addCon(w, 1000 + c, c % 2 == 0 and "::/stations/rail/x.con" or "::/stations/street/y.con", sts, c, c)
	end
	relist(w)
	local io = newIo(w)
	local st = stations.newState(ALL)
	local frames = runPass(st, io, 0) -- budget 0: one step per frame
	ok(frames > 900 / stations.READ_CHUNK, "read spread over frames")
	eq(#stations.items(st), 150)
	-- A clock that never advances: run() still stops at MAX_STEPS_PER_FRAME.
	io.now = function() return 0 end
	w.con[99999] = 1002; w.pax[99999] = false
	relist(w)
	stations.startScan(st, 0)
	local guard = 0
	while st.phase ~= "idle" and guard < 100 do
		io.frameLists = 0
		stations.run(st, io, 1)
		ok(io.frameLists <= 1)
		guard = guard + 1
	end
	eq(st.phase, "idle")
end)

test("back-off doubles while nothing changes, back to base on a change", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState(ALL)
	runPass(st, io)
	eq(st.scanSeconds, stations.SCAN_SECONDS)
	runPass(st, io)
	eq(st.scanSeconds, stations.SCAN_SECONDS * 2)
	for _ = 1, 6 do runPass(st, io) end
	eq(st.scanSeconds, stations.BACKOFF_MAX_SECONDS)
	w.con[1] = nil
	relist(w)
	w.list[#w.list + 1] = 10
	runPass(st, io)
	eq(st.scanSeconds, stations.SCAN_SECONDS)
end)

test("endScan mid-pass (Net off) keeps the caches consistent", function()
	local w = sampleWorld()
	local io = newIo(w)
	local st = stations.newState(ALL)
	stations.startScan(st, 0)
	stations.run(st, io, 1e9) -- list
	stations.run(st, io, 1e9) -- flat .. read, partially
	stations.endScan(st, 0)
	runPass(st, io)
	runPass(st, io)
	eq(st.stationCount, 10)
	eq(#stations.items(st), 5)
	eq(st.cons[100].refs, 2)
end)
