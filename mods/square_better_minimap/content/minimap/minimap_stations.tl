-- Minimap station icons (PLAN.md phase 8): airports, train stations and harbors drawn as icons on
-- the minimap while the Stn checkbox is ticked, each kind behind its own mod.json setting (default
-- On). Pure: the engine reads,
-- logging and SQPERF come in through `io` (SquareMinimapStationIo), so a whole pass runs offline in
-- tests/square_better_minimap/test_stations.lua. The game side is gui/minimap_hud.script.tl
-- ("Station icons"), which runs a frame of this only when the network scan did no work that frame
-- (at most one engine list call per frame).
--
-- A PASS (every scanSeconds):
--   list    getEntitiesWithComponent(STATION): one engine call, the only work of its frame
--   flat    cached station ids get the new stamp, unknown ids are collected (FLATTEN_CHUNK per step)
--   sweep   cached ids without the stamp are collected (SWEEP_CHUNK per step, next() resume)
--   remove  removed stations leave their construction; an empty construction is dropped
--   read    new stations only (READ_CHUNK per step): construction (1 call; curbside stops end
--           here), its path once per construction, and for a shown kind the passenger flag and
--           (once per construction) the position
-- Nothing is re-read for a cached station. Several STATION entities share one construction, so
-- the icons are per construction: passenger icon when any of its stations takes passengers.
-- BACK-OFF: a pass that changed nothing doubles the wait up to BACKOFF_MAX_SECONDS; a change goes
-- back to SCAN_SECONDS.

local stations : SquareMinimapStations = {}

stations.SCAN_SECONDS = 10.0
stations.BACKOFF_MAX_SECONDS = 40.0
stations.FLATTEN_CHUNK = 256
stations.SWEEP_CHUNK = 256
stations.REMOVE_CHUNK = 64
stations.READ_CHUNK = 8 -- up to 4 engine reads each
stations.MAX_STEPS_PER_FRAME = 64

-- The game's own HUD vehicle glyphs (base gui.zip gui/hud/icons/vehicle_*_front_32@2x.tga). The
-- station_<kind>[_cargo].tga names in base line_util.tl don't exist in gui.zip ("Could not find
-- texture" in game, 2026-10-22), and no cargo variant exists, so both entries are the same icon.
local RAIL_ICON <const> = "::/gui/hud/icons/vehicle_train_front_32.tga"
local AIR_ICON <const> = "::/gui/hud/icons/vehicle_airplane_front_32.tga"
local WATER_ICON <const> = "::/gui/hud/icons/vehicle_ship_front_32.tga"
stations.ICONS = {
	rail = { RAIL_ICON, RAIL_ICON },
	air = { AIR_ICON, AIR_ICON },
	water = { WATER_ICON, WATER_ICON },
}

local KINDS : {string} = { "rail", "air", "water" }

function stations.kindOfPath(path : string) : string
	if type(path) ~= "string" then return nil end
	for _, kind in ipairs(KINDS) do
		local seg = "stations/" .. kind .. "/"
		if path:sub(1, #seg) == seg or path:find("/" .. seg, 1, true) ~= nil then return kind end
	end
	return nil
end

function stations.iconFor(kind : string, passenger : boolean) : string
	local pair = stations.ICONS[kind]
	if pair == nil then return nil end
	return passenger and pair[1] or pair[2]
end

function stations.anyEnabled(enabled : {string : boolean}) : boolean
	if enabled == nil then return false end
	for _, kind in ipairs(KINDS) do
		if enabled[kind] then return true end
	end
	return false
end

local function newStats(now : number) : SquareMinimapStationStats
	return { startMs = now, frames = 0, listMs = 0, readMs = 0, listed = 0, added = 0, removed = 0, readFailed = 0, noPos = 0 }
end

function stations.newState(enabled : {string : boolean}) : SquareMinimapStationState
	return {
		enabled = enabled or {},
		stations = {}, cons = {}, stationCount = 0,
		stamp = 0, phase = "idle", idx = 1,
		changed = false, version = 0,
		waitUntilMs = 0, scanSeconds = stations.SCAN_SECONDS, passes = 0, yield = false,
		stats = newStats(0),
	}
end

function stations.startScan(st : SquareMinimapStationState, now : number)
	st.stamp = st.stamp + 1
	st.stats = newStats(now)
	st.changed = false
	st.phase = "list"
end

function stations.endScan(st : SquareMinimapStationState, now : number)
	st.phase = "idle"
	st.waitUntilMs = now + st.scanSeconds * 1000
	st.list, st.add, st.rem, st.sweepKey = nil, nil, nil, nil
	st.idx = 1
	st.yield = true
end

function stations.isHeavy(phase : string) : boolean
	return phase == "list"
end

local function finishPass(st : SquareMinimapStationState, io : SquareMinimapStationIo)
	local s = st.stats
	local changedAny = s.added > 0 or s.removed > 0
	if st.changed then st.version = st.version + 1 end
	if changedAny then
		st.scanSeconds = stations.SCAN_SECONDS
	else
		local nxt = st.scanSeconds * 2
		if nxt ~= nxt or nxt <= 0 then nxt = stations.SCAN_SECONDS end -- NaN / zero guard
		st.scanSeconds = math.min(stations.BACKOFF_MAX_SECONDS, nxt)
	end
	st.passes = st.passes + 1
	io.passDone(st)
	stations.endScan(st, io.now())
end

--- A cached station leaves its construction (the icons are laid out again on a version bump).
local function dropStation(st : SquareMinimapStationState, id : integer)
	local rec = st.stations[id]
	if rec == nil then return end
	st.stations[id] = nil
	st.stationCount = st.stationCount - 1
	st.stats.removed = st.stats.removed + 1
	if rec.con < 0 then return end
	local c = st.cons[rec.con]
	if c == nil then return end
	c.refs = c.refs - 1
	if rec.pax then c.pax = c.pax - 1 end
	if c.kind ~= "" then st.changed = true end
	if c.refs <= 0 then st.cons[rec.con] = nil end
end

--- Reads one new station (see the header). False when its construction read failed (not cached:
--- read again by the next pass).
local function readStation(st : SquareMinimapStationState, io : SquareMinimapStationIo, id : integer) : boolean
	if st.stations[id] ~= nil then return true end -- listed twice: counted once
	local con = io.conOf(id)
	if con == nil then return false end
	if con < 0 then con = -1 end
	local rec : SquareMinimapStationRec = { con = con, pax = false, stamp = st.stamp }
	if con >= 0 then
		local c = st.cons[con]
		if c == nil then
			local kind = stations.kindOfPath(io.pathOf(con)) or ""
			if kind ~= "" and not st.enabled[kind] then kind = "" end
			c = { kind = kind, refs = 0, pax = 0 }
			if kind ~= "" then
				local x, y = io.posOf(con)
				if x == nil or y == nil or x ~= x or y ~= y then
					c.kind = "" -- no position: never shown (cached, not retried while it exists)
					st.stats.noPos = st.stats.noPos + 1
				else
					c.x, c.y = x, y
				end
			end
			st.cons[con] = c
		end
		c.refs = c.refs + 1
		if c.kind ~= "" then
			rec.pax = io.isPassenger(id) == true
			if rec.pax then c.pax = c.pax + 1 end
			st.changed = true
		end
	end
	st.stations[id] = rec
	st.stationCount = st.stationCount + 1
	st.stats.added = st.stats.added + 1
	return true
end

function stations.work(st : SquareMinimapStationState, io : SquareMinimapStationIo)
	local phase = st.phase
	local perf = io.perf
	if phase == "list" then
		local t0 = io.now()
		local tPerf = perf:start()
		local list = io.listStations()
		perf:stop("st_list", tPerf)
		perf:count("st_scan")
		st.stats.listMs = st.stats.listMs + (io.now() - t0)
		st.yield = true -- the engine list call is the only work of its frame
		if list == nil then
			stations.endScan(st, io.now()) -- nothing removed on an API error
			return
		end
		st.list, st.idx, st.add = list, 1, {}
		st.stats.listed = #list
		st.phase = "flat"
	elseif phase == "flat" then
		local list = st.list
		local last = math.min(#list, st.idx + stations.FLATTEN_CHUNK - 1)
		for i = st.idx, last do
			local id = list[i]
			local rec = st.stations[id]
			if rec ~= nil then
				rec.stamp = st.stamp
			elseif type(id) == "number" then
				st.add[#st.add + 1] = id
			end
		end
		st.idx = last + 1
		if st.idx > #list then
			st.list, st.rem, st.sweepKey = nil, {}, nil
			st.phase = "sweep"
		end
	elseif phase == "sweep" then
		-- Read-only walk (nothing is added or removed until it is done), resumed with next().
		local key = st.sweepKey
		local n = 0
		local done = false
		while n < stations.SWEEP_CHUNK do
			local id, rec = next(st.stations, key)
			if id == nil then
				done = true
				break
			end
			if rec.stamp ~= st.stamp then st.rem[#st.rem + 1] = id end
			key = id
			n = n + 1
		end
		st.sweepKey = key
		if done then st.sweepKey, st.phase, st.idx = nil, "remove", 1 end
	elseif phase == "remove" then
		local rem = st.rem
		local last = math.min(#rem, st.idx + stations.REMOVE_CHUNK - 1)
		for i = st.idx, last do dropStation(st, rem[i]) end
		st.idx = last + 1
		if st.idx > #rem then st.phase, st.idx = "read", 1 end
	elseif phase == "read" then
		local add = st.add
		local last = math.min(#add, st.idx + stations.READ_CHUNK - 1)
		local t0 = io.now()
		local tPerf = perf:start()
		for i = st.idx, last do
			if not readStation(st, io, add[i]) then st.stats.readFailed = st.stats.readFailed + 1 end
		end
		perf:stop("st_read", tPerf)
		st.stats.readMs = st.stats.readMs + (io.now() - t0)
		st.idx = last + 1
		if st.idx > #add then finishPass(st, io) end
	end
end

function stations.run(st : SquareMinimapStationState, io : SquareMinimapStationIo, budgetMs : number) : boolean
	local version = st.version
	local deadline = io.now() + budgetMs
	st.yield = false
	st.stats.frames = st.stats.frames + 1
	local steps = 0
	repeat
		-- The engine list call only as the first work of a frame.
		if steps > 0 and stations.isHeavy(st.phase) then break end
		stations.work(st, io)
		steps = steps + 1
	until st.phase == "idle" or st.yield or io.now() >= deadline or steps >= stations.MAX_STEPS_PER_FRAME
	return st.version ~= version
end

function stations.items(st : SquareMinimapStationState) : {SquareMinimapIndustry}
	local out : {SquareMinimapIndustry} = {}
	for con, c in pairs(st.cons) do
		if c.kind ~= "" and c.refs > 0 then
			out[#out + 1] = {
				entity = con, x = c.x, y = c.y,
				icon = stations.iconFor(c.kind, c.pax > 0),
				typeKey = "station:" .. c.kind,
			}
		end
	end
	table.sort(out, function(a : SquareMinimapIndustry, b : SquareMinimapIndustry) : boolean return a.entity < b.entity end)
	return out
end

function stations.counts(st : SquareMinimapStationState) : {string : integer}, integer
	local per : {string : integer} = { rail = 0, air = 0, water = 0 }
	local pax = 0
	for _, c in pairs(st.cons) do
		if c.kind ~= "" and c.refs > 0 then
			per[c.kind] = (per[c.kind] or 0) + 1
			if c.pax > 0 then pax = pax + 1 end
		end
	end
	return per, pax
end

return stations
