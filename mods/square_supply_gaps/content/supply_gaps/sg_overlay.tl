-- Supply Gaps overlay (PLAN "Data flow"): session state and the 1 s tick pipeline.
-- GUI thread only (driven by the ridge plugin in gui/sg_window.script.tl: react.onStepTimer + onStep,
-- both joined onto the main thread). Read-only toward the simulation: no commands; markers are GUI-only
-- and removed when the overlay is switched off. Off by default (DEFAULT_ON); the window switches it on
-- at load when the save says so, and persists the checkbox (sg_saved.tl, PLAN "Per-save state").
--
--   tick: gather.lines -> model.deliveringGroups (+ addUnlinedGroups) -> gather.groupStations
--         -> cache.step (catchables) -> gather.buildingMap -> building boxes (once per id, budgeted) -> town
--         boxes -> sg_scope.select (camera footprint; "Only towns in view") -> cache.buildingStep
--         (reads only for towns in scope: new / due ids now, 1/BUILDING_EVERY of the rest round robin)
--         -> gather.readBuilding (needs + stock per need) -> counted towns = in scope and read once
--         (no partial flash) -> model.compute (unreached / starved) -> model.markerPlan (nearest
--         MAX_MARKERS to the camera) -> markers.apply (diff) -> sg_areas.labels -> labelStore (HUD)
--
-- Perf (plans/square_supply_gaps/PERF_REVIEW.md): lines come from a line cache (stop-map change = at
-- once, else round robin); station groups round robin; the flat id list, the scoped id list and the box
-- pass are rebuilt only when the building map / scope changes; boxes and building reads are budgeted
-- per tick; model.compute runs only when an input changed (dirty), the marker plan and the area labels
-- only when the view or (if it matters) the camera changed.
--
-- Log ([SQSG] prefix, stdout.txt): ERR where msg (first ERR_LOGS); with DEBUG = true also a PERF line
-- every cache.PERF_EVERY ticks with per-stage split times. Every step is in pcall: a failing tick never
-- reaches react.

local gather = ug_require "square_supply_gaps::/supply_gaps/sg_gather.tl" as SupplyGapsGather
local cache = ug_require "square_supply_gaps::/supply_gaps/sg_cache.tl" as SupplyGapsCache
local model = ug_require "square_supply_gaps::/supply_gaps/sg_model.tl" as SupplyGapsModel
local markers = ug_require "square_supply_gaps::/supply_gaps/sg_markers.tl" as SupplyGapsMarkers
local areas = ug_require "square_supply_gaps::/supply_gaps/sg_areas.tl" as SupplyGapsAreas
local scope = ug_require "square_supply_gaps::/supply_gaps/sg_scope.tl" as SupplyGapsScope
-- SQPERF (plans/sqperf/README.md), own instrument ctx "tick": the whole tick ("tick", around its pcall;
-- timer ticks and the paused fallback alike) and each stage of it (the DEBUG split's names, timed by
-- lap). The tick runs joined onto the Main Thread (react.enqueueJoin), so a tick over one 60 fps frame
-- (16 ms) is a slow call. The script's load time is in the window script's instrument (ctx gui).
local sqperf = ug_require "square_supply_gaps::/sqperf/square_supply_gaps.lua" as SquareSupplyGapsSqPerf
local perf = sqperf.new({ mod = "square_supply_gaps", ctx = "tick", paramKey = "sqperf_log", slowMs = 16, first = { "tick" } })

local overlay : SupplyGapsOverlay = {}

overlay.TICK = 1.0
-- The overlay is off when a game loads; the saved per-save flag (sg_saved.tl) switches it on.
overlay.DEFAULT_ON = false
-- Urgent building reads per tick (never-read ids, towns that just came into view). Round robin
-- re-reads of the rest come on top (cache.buildingStep).
overlay.PRIORITY_PER_TICK = 800
-- Building box pass (town extents, "Only towns in view"): at most this many reads per tick, and no
-- more once the tick has spent BOX_BUDGET_MS on them; the pass resumes next tick.
overlay.BOX_PER_TICK = 2000
overlay.BOX_BUDGET_MS = 3.0
-- Building reads stop once the tick has run READ_BUDGET_MS (after at least READ_MIN reads).
overlay.READ_BUDGET_MS = 6.0
overlay.READ_MIN = 100

local function defaultSession() : SupplyGapsSession
	return { on = overlay.DEFAULT_ON, unlined = false, starved = true, selection = nil, labels = true, scoped = true }
end

overlay.session = defaultSession()
overlay.cache = cache.new()
overlay.buildings = {}
overlay.seen = {}
overlay.view = nil
overlay.gapList = nil
overlay.ticks = 0
overlay.cargoNames = {}
overlay.cargoIcons = {}
overlay.labelStore = nil
overlay.boxes = {}
overlay.townBoxes = {}
overlay.scopeState = scope.newState()
overlay.scopeTowns = nil
overlay.ready = {}
overlay.due = {}
overlay.townNames = {}
overlay.viewText = ""
overlay.viewCount = 0
overlay.pending = 0
-- Wall clock: api.type.Clock (microseconds; works on the Main Thread, square_aat_perftest run1.log
-- "side=gui ... timer=clock"). os.clock is process CPU time over all threads on macOS (overstates).
local wallClock : Clock = nil
local wallTried = false
overlay.clock = function() : number
	if not wallTried then
		wallTried = true
		pcall(function() wallClock = api.type.Clock.new() end)
	end
	if wallClock ~= nil then return wallClock:getTime() / 1000000 end
	return os.clock()
end
overlay.now = function() : number return os.time() end

local LOG_PREFIX <const> = "[SQSG] "
local ERR_LOGS <const> = 20
-- true: a PERF line every cache.PERF_EVERY ticks (development only).
local DEBUG <const> = false
-- Paused this many wall seconds without a timer tick -> tick from onStep instead.
local PAUSE_WAIT <const> = 3

local errLogged = 0
local passenger : integer = nil
local lastTickWall : number = 0
local inTick = false
-- Sorted building ids, rebuilt only when the set of buildings with needs or the counted towns change.
local order : {integer} = nil
-- Towns counted (in scope and read once) when `order` was last built.
local orderTowns : {integer : boolean} = nil
local NO_BOX : SupplyGapsBox = {}

-- Perf review state (all reset by resetCaches): see the header.
local lineCache : SupplyGapsLineCache = gather.newLineCache()
local groupCargo : {integer : {integer : boolean}} = nil
local groups : {integer} = nil
local lastUnlined : boolean = nil
local groupStations : {integer : {integer}} = {}
local gsCursor = 0
local stations : {integer} = {}
local ids : {integer} = nil
local townOf : {integer} = nil
-- next index of the box pass over `ids`; nil = every id has its box
local boxScan : integer = nil
local sids : {integer} = {}
local stown : {integer} = {}
local sidsValid = false
-- model inputs changed since the last compute
local dirty = true
local lastSel : integer = nil
local lastInc : boolean = nil
local planView : SupplyGapsView = nil
local planX, planY : number, number = nil, nil
local labelView : SupplyGapsView = nil
local labelSel : integer = nil
local labelX, labelY : number, number = nil, nil
local labelCands : {SupplyGapsAreaLabel} = nil

-- DEBUG split: per stage {sum, max} ms since the last PERF line
local STAGES <const> = { "lines", "catch", "map", "boxes", "scope", "read", "model", "markers", "labels" }
local split : {string : {number}} = {}

local function newCounters() : {string : integer}
	return { computes = 0, skips = 0, plans = 0, labelBuilds = 0, boxReads = 0, reads = 0 }
end
overlay.counters = newCounters()

local function resetCaches()
	lineCache = gather.newLineCache()
	groupCargo, groups, lastUnlined = nil, nil, nil
	groupStations, gsCursor, stations = {}, 0, {}
	ids, townOf, boxScan = nil, nil, nil
	sids, stown, sidsValid = {}, {}, false
	dirty = true
	planView, planX, planY = nil, nil, nil
	labelView, labelSel, labelX, labelY, labelCands = nil, nil, nil, nil, nil
end

local record PauseState
	lastSec : number
	since : number
	tickSince : boolean
	fallback : boolean
end
local pause : PauseState = { lastSec = nil, since = nil, tickSince = false, fallback = false }

--- pcall for a function without results: ok, error text.
local function try(fn : function()) : boolean, string
	local ok, e = pcall(function() : boolean
		fn()
		return true
	end)
	if ok then return true, nil end
	return false, tostring(e)
end

local function msg(s : string)
	log.message(LOG_PREFIX .. s)
end

local function err(where : string, m : any)
	errLogged = errLogged + 1
	if errLogged <= ERR_LOGS then msg("ERR " .. where .. " " .. tostring(m)) end
end

local function fmt(v : number) : string
	return string.format("%.1f", v)
end

local function cargoName(c : integer) : string
	if c == nil then return "?" end
	local name = overlay.cargoNames[c]
	if name == nil then
		local ok, n = pcall(function() : string
			local ct = api.res.cargoTypeRep.get(c)
			return ct ~= nil and ct.name or nil
		end)
		name = (ok and n ~= nil and n ~= "") and n as string or ("cargo " .. tostring(c))
		overlay.cargoNames[c] = name
	end
	return name
end

--- CargoType.icon (GUI thread: the tick runs joined onto the main thread); "" if unknown.
local function cargoIcon(c : integer) : string
	local path = overlay.cargoIcons[c]
	if path == nil then
		local ok, p = pcall(function() : string
			local ct = api.res.cargoTypeRep.get(c)
			return ct ~= nil and ct.icon or nil
		end)
		path = (ok and p ~= nil) and p as string or ""
		overlay.cargoIcons[c] = path
	end
	return path
end

function overlay.makeLabelStore(list : {SupplyGapsAreaLabel}, nAreas : integer, iconOf : function(integer) : string) : SupplyGapsLabelStore
	local byTown : {integer : {SupplyGapsLabelRow}} = {}
	for __, l in ipairs(list or {}) do
		local chips : {SupplyGapsLabelChip} = {}
		for __, ch in ipairs(l.chips) do
			chips[#chips + 1] = { icon = iconOf(ch.cargo), text = tostring(ch.pct) .. "%", tone = ch.tone, cargo = ch.cargo }
		end
		local rows = byTown[l.town]
		if rows == nil then
			rows = {}
			byTown[l.town] = rows
		end
		rows[#rows + 1] = { landUse = l.landUse, chips = chips }
	end
	for __, rows in pairs(byTown) do
		table.sort(rows, function(a : SupplyGapsLabelRow, b : SupplyGapsLabelRow) : boolean return a.landUse < b.landUse end)
	end
	return { byTown = byTown, shown = #(list or {}), areas = nAreas or 0 }
end

local function vec3(v : Vec3f) : {number}
	if v == nil then return nil end
	return { v.x, v.y, v.z }
end

--- Camera centre, distance and ground footprint (GUI thread only: the tick runs joined onto the main
--- thread). Footprint as square_better_minimap's camera box: each screen corner's screen2World ray at
--- depth 0 / 1 (gui.d.tl:483-487) meets the plane at the terrain height under the centre
--- (engine.d.tl:1734), capped at CAP_FACTOR x distance. Never raises: the fallback is a square of
--- +- distance around the centre (or the origin when even getCameraData fails).
function overlay.readCamera() : SupplyGapsCameraView
	local okD, d = pcall(function() : Vec5f return api.gui.camera.getCameraData() end)
	if not okD or d == nil then
		err("camera", d)
		return { cx = 0, cy = 0, distance = scope.MIN_DIST, poly = scope.square(0, 0, scope.MIN_DIST), hits = 0, fallback = true }
	end
	local cam5 = d as Vec5f
	local cx, cy = cam5.x or 0, cam5.y or 0
	local dist = math.max(cam5.z or 0, scope.MIN_DIST)
	local ok, res = pcall(function() : SupplyGapsCameraView
		local cam = api.gui.camera
		local size = cam.getSize()
		local eye = vec3(cam.getEye())
		local planeZ : number
		local okH, h = pcall(api.engine.terrain.getHeightAt, api.type.Vec2f.new(cx, cy))
		if okH and h ~= nil then
			planeZ = h as number
		else
			planeZ = cam.getCenter().z
		end
		local corners : {{number}} = { { 0, 0 }, { size.x, 0 }, { size.x, size.y }, { 0, size.y } }
		local rays : {{{number}}} = {}
		for i, c in ipairs(corners) do
			rays[i] = {
				vec3(cam.screen2World(api.type.Vec3f.new(c[1], c[2], 0.0))),
				vec3(cam.screen2World(api.type.Vec3f.new(c[1], c[2], 1.0))),
			}
		end
		local poly, hits = scope.footprint(rays, eye, planeZ, cx, cy, scope.CAP_FACTOR * dist)
		return { cx = cx, cy = cy, distance = dist, poly = poly, hits = hits, fallback = false }
	end)
	if ok and res ~= nil and #(res as SupplyGapsCameraView).poly == 8 then return res as SupplyGapsCameraView end
	if not ok then err("footprint", res) end
	return { cx = cx, cy = cy, distance = dist, poly = scope.square(cx, cy, dist), hits = 0, fallback = true }
end

--- GAME_SPEED.speedup == 0 (api/tealdef/api/engine.d.tl:415-421; read as game_bar_widgets.tl:339).
local function readPaused() : boolean
	local ok, paused = pcall(function() : boolean
		local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED) as Engine.Component.GameSpeed
		return gs ~= nil and gs.speedup == 0
	end)
	return ok and paused == true
end

--- Continue the box pass over `ids` from index `from`: reads the 2D box of each id without one, at most
--- BOX_PER_TICK reads and BOX_BUDGET_MS per tick. Returns whether any box was read and where to resume
--- (nil = pass done).
local function readBoxes(from : integer) : boolean, integer
	local fresh = false
	local n = 0
	local t0 = overlay.clock()
	for i = from, #ids do
		local b = ids[i]
		if overlay.boxes[b] == nil then
			if n >= overlay.BOX_PER_TICK or (n % 50 == 49 and (overlay.clock() - t0) * 1000 > overlay.BOX_BUDGET_MS) then
				overlay.counters.boxReads = overlay.counters.boxReads + n
				return fresh, i
			end
			fresh = true
			n = n + 1
			local ok, bb = pcall(gather.buildingBox, b)
			if ok and bb ~= nil then
				overlay.boxes[b] = bb as SupplyGapsBox
			else
				if not ok then err("box " .. tostring(b), bb) end
				overlay.boxes[b] = NO_BOX
			end
		end
	end
	overlay.counters.boxReads = overlay.counters.boxReads + n
	return fresh, nil
end

--- Drop demolished buildings (an O(n) pass): only when the flat id list changed.
--- Returns whether the building set (with needs) changed and whether any box was dropped.
local function dropGone(ids : {integer}) : boolean, boolean
	local present : {integer : boolean} = {}
	for __, b in ipairs(ids) do present[b] = true end
	local changed, boxGone = false, false
	for b in pairs(overlay.seen) do
		if not present[b] then
			overlay.seen[b] = nil
			overlay.due[b] = nil
			if overlay.buildings[b] ~= nil then
				overlay.buildings[b] = nil
				changed = true
			end
		end
	end
	for b in pairs(overlay.boxes) do
		if not present[b] then
			overlay.boxes[b] = nil
			boxGone = true
		end
	end
	return changed, boxGone
end

--- Read this tick's slice of the town buildings of the towns in scope (`sids` / `stown`) into
--- overlay.buildings: never-read ids and `overlay.due` ones first (at most PRIORITY_PER_TICK), plus the
--- round robin; stops once the tick has run READ_BUDGET_MS (after READ_MIN reads). Returns how many
--- were read and whether the set of buildings with needs changed; a record whose model inputs changed
--- (model.sameBuilding) marks the model dirty.
local function readBuildings(tickStart : number) : integer, boolean
	local pick = cache.buildingStep(overlay.cache, sids, overlay.seen, overlay.due, overlay.PRIORITY_PER_TICK)
	local changed = false
	local n = 0
	for __, i in ipairs(pick) do
		if n >= overlay.READ_MIN and (overlay.clock() - tickStart) * 1000 > overlay.READ_BUDGET_MS then break end
		n = n + 1
		local b = sids[i]
		local prev = overlay.buildings[b]
		local info, okRead = gather.readBuilding(b, stown[i], prev, passenger)
		-- A failed read keeps the previous record; the round robin retries it.
		overlay.seen[b] = true
		overlay.due[b] = nil
		if okRead then
			if info ~= nil and #info.needs > 0 then
				if prev == nil then
					changed = true
					dirty = true
				elseif not dirty and not model.sameBuilding(prev, info) then
					dirty = true
				end
				overlay.buildings[b] = info
			elseif prev ~= nil then
				overlay.buildings[b] = nil
				changed = true
				dirty = true
			end
		end
	end
	overlay.counters.reads = overlay.counters.reads + n
	return n, changed
end

local function townName(t : integer) : string
	local name = overlay.townNames[t]
	if name == nil then
		local ok, nm = pcall(gather.townName, t)
		name = (ok and nm ~= nil and nm ~= "") and nm as string or ("town " .. tostring(t))
		if not ok then err("townName " .. tostring(t), nm) end
		overlay.townNames[t] = name
	end
	return name
end

--- Towns in scope this tick: in view (sg_scope.select) or, not scoped, every town with buildings.
--- Known buildings of towns that just came in are queued as due (prompt re-read). Returns the set and
--- whether it differs from the last tick's.
local function updateScope(map : {integer : {integer}}, cam : SupplyGapsCameraView) : {integer : boolean}, boolean
	local s = overlay.session
	local set : {integer : boolean}
	if s.scoped then
		set = scope.select(overlay.townBoxes, cam, overlay.scopeState, overlay.ticks)
	else
		set = {}
		for t in pairs(map) do set[t] = true end
	end
	local prev = overlay.scopeTowns or {}
	local added : {integer : boolean} = {}
	local nAdded, n = 0, 0
	for t in pairs(set) do
		n = n + 1
		if not prev[t] then
			added[t] = true
			nAdded = nAdded + 1
		end
	end
	local changed = nAdded > 0 or overlay.scopeTowns == nil
	if not changed then
		for t in pairs(prev) do
			if not set[t] then
				changed = true
				break
			end
		end
	end
	if nAdded > 0 then
		for i, b in ipairs(ids) do
			if added[townOf[i]] and overlay.seen[b] then overlay.due[b] = true end
		end
	end
	overlay.scopeTowns = set
	overlay.viewCount = n
	return set, changed
end

--- Deep equality of small plain tables (group -> cargo set, group -> stations).
local function same(a : any, b : any) : boolean
	if a == b then return true end
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	local ta, tb = a as {any : any}, b as {any : any}
	for k, v in pairs(ta) do
		if not same(v, tb[k]) then return false end
	end
	for k in pairs(tb) do
		if ta[k] == nil then return false end
	end
	return true
end

--- Delivering groups and their stations. Lines from the line cache; group -> cargo rebuilt only when
--- the lines or "Count stops without a line" changed (unlined: every tick, as unloadGroups reads all
--- groups); STATION_GROUP read at once for a new group, else ceil(n / BUILDING_EVERY) round robin.
local function updateGroups(s : SupplyGapsSession)
	local lines, linesChanged = gather.lines(lineCache)
	if linesChanged == nil then linesChanged = true end
	if linesChanged or s.unlined or groupCargo == nil or lastUnlined ~= s.unlined then
		local gc = model.deliveringGroups(lines, passenger)
		if s.unlined then gc = model.addUnlinedGroups(gc, gather.unloadGroups()) end
		lastUnlined = s.unlined
		if groupCargo == nil or not same(gc, groupCargo) then
			groupCargo = gc
			groups = model.sortedKeys(gc)
			dirty = true
		end
	end
	local want : {integer} = {}
	local inGroups : {integer : boolean} = {}
	for __, g in ipairs(groups) do
		inGroups[g] = true
		if groupStations[g] == nil then want[#want + 1] = g end
	end
	local n = #groups
	if n > 0 then
		local k = math.floor((n + cache.BUILDING_EVERY - 1) / cache.BUILDING_EVERY)
		local cur = gsCursor
		if cur >= n then cur = 0 end
		for __ = 1, k do
			cur = cur + 1
			if cur > n then cur = 1 end
			if groupStations[groups[cur]] ~= nil then want[#want + 1] = groups[cur] end
		end
		gsCursor = cur
	end
	local changed = false
	for g in pairs(groupStations) do
		if not inGroups[g] then
			groupStations[g] = nil
			changed = true
		end
	end
	if #want > 0 then
		local got = gather.groupStations(want)
		for __, g in ipairs(want) do
			local list = got[g]
			if not same(list, groupStations[g]) then
				changed = true
			end
			-- a failed / missing group is left out (as before); it is asked for again next tick
			groupStations[g] = list
		end
	end
	if changed then
		dirty = true
		local out : {integer} = {}
		for __, g in ipairs(groups) do
			for __, st in ipairs(groupStations[g] or {}) do out[#out + 1] = st end
		end
		stations = out
	end
end

local function stage(name : string, ms : number)
	local e = split[name]
	if e == nil then
		e = { 0, 0 }
		split[name] = e
	end
	e[1] = e[1] + ms
	if ms > e[2] then e[2] = ms end
end

local function splitText(ticks : integer) : string
	local parts : {string} = {}
	for __, name in ipairs(STAGES) do
		local e = split[name] or { 0, 0 }
		parts[#parts + 1] = name .. ":" .. fmt(e[1] / ticks) .. "/" .. fmt(e[2])
	end
	split = {}
	return table.concat(parts, " ")
end

local function runTick()
	local t0 = overlay.clock()
	local tl = t0
	local pt = perf:start()
	local function lap(name : string)
		local now = overlay.clock()
		stage(name, (now - tl) * 1000)
		tl = now
		-- SQPERF: the stage as its own section (name is one of the literals passed below)
		perf:stop(name, pt)
		pt = perf:start()
	end
	overlay.ticks = overlay.ticks + 1
	local s = overlay.session
	if passenger == nil then passenger = gather.passengerCargo() end

	updateGroups(s)
	lap("lines")
	local st = cache.step(overlay.cache, stations, cache.engineFetch, cache.refreshCap(#stations))
	if (st.changed or 1) > 0 then dirty = true end
	lap("catch")

	local count, map = gather.buildingMap()
	local nids, ntown, idsChanged = gather.flatten(map, ids, townOf)
	local setChanged, boxGone = false, false
	if idsChanged then
		ids, townOf = nids, ntown
		sidsValid = false
		boxScan = 1
		setChanged, boxGone = dropGone(ids)
		if setChanged then dirty = true end
	end
	lap("map")
	-- Boxes once per id, spread over ticks (BOX_PER_TICK / BOX_BUDGET_MS); only needed while scoped.
	local fresh = false
	if boxScan ~= nil and s.scoped then fresh, boxScan = readBoxes(boxScan) end
	if fresh or boxGone then overlay.townBoxes = scope.townBoxes(ids, townOf, overlay.boxes) end
	lap("boxes")

	local cam = overlay.readCamera()
	local camera : SupplyGapsCamera = { cam.cx, cam.cy }
	local scopeSet, scopeChanged = updateScope(map, cam)
	if scopeChanged or not sidsValid then
		local a : {integer} = {}
		local t : {integer} = {}
		for i, b in ipairs(ids) do
			if scopeSet[townOf[i]] then
				a[#a + 1] = b
				t[#t + 1] = townOf[i]
			end
		end
		sids, stown, sidsValid = a, t, true
	end
	lap("scope")
	local nRead, readChanged = readBuildings(t0)
	-- Counted towns: in scope and every building read once (sticky), so a town that just came
	-- into view never shows partial counts; the rest is "pending".
	local unseen : {integer : integer} = {}
	local pending = 0
	for i, b in ipairs(sids) do
		if not overlay.seen[b] then
			local tw = stown[i]
			unseen[tw] = (unseen[tw] or 0) + 1
			pending = pending + 1
		end
	end
	overlay.pending = pending
	local counted : {integer : boolean} = {}
	local countedChanged = orderTowns == nil
	for tw in pairs(scopeSet) do
		if unseen[tw] == nil then overlay.ready[tw] = true end
		if overlay.ready[tw] then
			counted[tw] = true
			if orderTowns ~= nil and not orderTowns[tw] then countedChanged = true end
		end
	end
	if orderTowns ~= nil then
		for tw in pairs(orderTowns) do
			if not counted[tw] then countedChanged = true end
		end
	end
	if order == nil or setChanged or readChanged or countedChanged then
		order = model.scopeOrder(overlay.buildings, counted)
		orderTowns = counted
		dirty = true
	end
	if overlay.session.scoped then
		local names : {string} = {}
		for __, tw in ipairs(scope.byDistance(scopeSet, overlay.townBoxes, cam.cx, cam.cy)) do names[#names + 1] = townName(tw) end
		overlay.viewText = scope.namesText(names, scope.NAMES_SHOWN)
	else
		overlay.viewText = ""
	end
	lap("read")

	-- Model only when an input changed: buildings (model.sameBuilding), catchables, groups, order,
	-- selection, "Include in-range but empty".
	if dirty or overlay.view == nil or s.selection ~= lastSel or s.starved ~= lastInc then
		overlay.view = model.compute({
			buildings = overlay.buildings,
			groupCargo = groupCargo,
			groupStations = groupStations,
			catchables = cache.catchables(overlay.cache),
			includeStarved = s.starved,
			order = order,
		}, s.selection)
		dirty, lastSel, lastInc = false, s.selection, s.starved
		overlay.counters.computes = overlay.counters.computes + 1
	else
		overlay.counters.skips = overlay.counters.skips + 1
	end
	local view = overlay.view
	overlay.gapList = view.gapList
	lap("model")

	-- Marker plan: the camera only matters when there are more gaps than markers.
	local ms : SupplyGapsMarkerStats = nil
	local camMoved = cam.cx ~= planX or cam.cy ~= planY
	if view ~= planView or (camMoved and #view.gapList > model.MAX_MARKERS) then
		local plan = model.markerPlan(view.gapList, overlay.buildings, camera, model.MAX_MARKERS)
		ms = markers.apply(plan, view.kind)
		overlay.counters.plans = overlay.counters.plans + 1
		-- a failed marker call is retried next tick
		if ms.errors > 0 then planView = nil else planView = view end
		planX, planY = cam.cx, cam.cy
	end
	lap("markers")

	-- Area labels: own pcall, so a failure only drops the labels (never the markers). Rebuilt when the
	-- view or the selection changed, or the camera moved while there are more areas than labels.
	if s.labels then
		local okL, mL = try(function()
			local fresh = labelCands == nil or view ~= labelView or s.selection ~= labelSel
			if fresh then
				-- chips per area depend on the view and the selection only, not on the camera
				labelCands = areas.candidates(view.areas, s.selection, areas.WORST)
				labelView, labelSel = view, s.selection
			end
			local moved = cam.cx ~= labelX or cam.cy ~= labelY
			if overlay.labelStore == nil or fresh or (moved and #labelCands > areas.MAX_LABELS) then
				local nAreas = 0
				for __ in pairs(view.areas or {}) do nAreas = nAreas + 1 end
				local list = areas.nearest(labelCands, camera, areas.MAX_LABELS)
				-- replaced as a whole: the HUD wrappers only ever see a complete store
				overlay.labelStore = overlay.makeLabelStore(list, nAreas, cargoIcon)
				labelX, labelY = cam.cx, cam.cy
				overlay.counters.labelBuilds = overlay.counters.labelBuilds + 1
			end
		end)
		if not okL then
			overlay.labelStore = nil
			err("labels", mL)
		end
	else
		overlay.labelStore = nil
	end
	lap("labels")

	local elapsed = (overlay.clock() - t0) * 1000
	cache.noteTime(overlay.cache, elapsed)
	local p = cache.perf(overlay.cache)
	if DEBUG and p ~= nil then
		local c = overlay.counters
		local nShown = 0
		for __ in pairs(markers.shown) do nShown = nShown + 1 end
		msg("PERF ticks=" .. tostring(cache.PERF_EVERY) .. " maxMs=" .. fmt(p[1]) .. " avgMs=" .. fmt(p[2])
			.. " split(avg/max)=" .. splitText(cache.PERF_EVERY)
			.. " perTick=" .. tostring(overlay.cache.perTick) .. " stations=" .. tostring(#stations)
			.. " catch=" .. tostring(st.catchables) .. " buildings=" .. tostring(view.buildings) .. "/" .. tostring(count)
			.. " read=" .. tostring(nRead) .. " reads=" .. tostring(c.reads) .. " towns=" .. tostring(overlay.viewCount)
			.. " pending=" .. tostring(pending) .. " boxReads=" .. tostring(c.boxReads)
			.. " boxPass=" .. (boxScan ~= nil and "running" or "done")
			.. " computes=" .. tostring(c.computes) .. " skips=" .. tostring(c.skips)
			.. " plans=" .. tostring(c.plans) .. " labelBuilds=" .. tostring(c.labelBuilds)
			.. " unreached=" .. tostring(view.unreachedTotal) .. " starved=" .. tostring(view.starvedTotal)
			.. " markers=" .. tostring(nShown) .. " clock=" .. (wallClock ~= nil and "wall" or "os")
			.. " gatherErr=" .. tostring(gather.errors))
		overlay.counters = newCounters()
	end
	lastTickWall = overlay.now()
end

function overlay.tick(source : string)
	if not overlay.session.on or inTick then return end
	inTick = true
	local tp = perf:start()
	local ok, m = try(runTick)
	perf:stop("tick", tp)
	inTick = false
	if not ok then err("tick", m) end
end

function overlay.timerTick()
	if not overlay.session.on then return end
	if pause.since ~= nil then pause.tickSince = true end
	overlay.tick("timer")
end

function overlay.stepCheck()
	if not overlay.session.on then
		pause.since, pause.fallback = nil, false
		return
	end
	local now = overlay.now()
	if pause.lastSec == now then return end
	pause.lastSec = now
	if readPaused() then
		if pause.since == nil then
			pause.since, pause.tickSince = now, false
		end
		if not pause.tickSince and now - pause.since >= PAUSE_WAIT then pause.fallback = true end
		if pause.fallback and now - lastTickWall >= 1 then overlay.tick("step") end
	else
		pause.since, pause.fallback = nil, false
	end
end

function overlay.setOn(on : boolean)
	on = on == true
	if on == overlay.session.on then return end
	overlay.session.on = on
	-- markers / labels are re-sent and the model recomputed on the next tick
	dirty, planView, labelView = true, nil, nil
	if on then
		-- Everything read while the overlay was off is stale: every town in scope is due again, and
		-- lines / station groups are read in full on the next tick.
		lineCache, groupCargo, groupStations = gather.newLineCache(), nil, {}
		overlay.scopeTowns = {}
		overlay.scopeState = scope.newState()
		overlay.townNames = {}
	else
		markers.clearAll()
		overlay.gapList = nil
		overlay.labelStore = nil
	end
end

function overlay.setUnlined(on : boolean)
	overlay.session.unlined = on == true
end

function overlay.setStarved(on : boolean)
	overlay.session.starved = on == true
end

function overlay.setLabels(on : boolean)
	overlay.session.labels = on == true
	if not overlay.session.labels then overlay.labelStore = nil end
end

function overlay.setScoped(on : boolean)
	overlay.session.scoped = on == true
end

function overlay.setSelection(cargo : integer)
	overlay.session.selection = cargo
end

function overlay.shutdown()
	-- No engine calls here: on a game unload the world may already be going away. Mission markers
	-- are GUI-only and die with the game. The next game starts with the defaults (off, then its saved flag).
	markers.forget()
	overlay.session = defaultSession()
	overlay.gapList = nil
	overlay.view = nil
	overlay.labelStore = nil
	overlay.cache = cache.new()
	overlay.buildings = {}
	overlay.seen = {}
	order, orderTowns = nil, nil
	overlay.boxes = {}
	overlay.townBoxes = {}
	overlay.scopeState = scope.newState()
	overlay.scopeTowns = nil
	overlay.ready = {}
	overlay.due = {}
	overlay.townNames = {}
	overlay.viewText = ""
	overlay.viewCount = 0
	overlay.pending = 0
	passenger = nil
	resetCaches()
	overlay.counters = newCounters()
	split = {}
	overlay.ticks = 0
	pause.since, pause.fallback = nil, false
end

function overlay.snapshot() : SupplyGapsSnapshot
	local s = overlay.session
	local view = overlay.view
	local rows : {SupplyGapsCargoRow} = {}
	local gaps, blds, unreached, starved = 0, 0, 0, 0
	local inc = s.starved == true
	if view ~= nil then
		gaps, blds, unreached, starved = view.total, view.buildings, view.unreachedTotal, view.starvedTotal
		for __, c in ipairs(model.sortedKeys(view.cargos)) do
			local cc = view.cargos[c]
			rows[#rows + 1] = { cargo = c, name = cargoName(c), needed = cc.needed, reached = cc.reached, starved = cc.starved }
		end
		-- The selected cargo keeps its row when no town in scope needs it.
		if s.selection ~= nil and view.cargos[s.selection] == nil then
			rows[#rows + 1] = { cargo = s.selection, name = cargoName(s.selection), needed = 0, reached = 0, starved = 0 }
		end
		table.sort(rows, function(a : SupplyGapsCargoRow, b : SupplyGapsCargoRow) : boolean
			local ua = a.needed - a.reached + (inc and a.starved or 0)
			local ub = b.needed - b.reached + (inc and b.starved or 0)
			if ua ~= ub then return ua > ub end
			if a.name ~= b.name then return a.name < b.name end
			return a.cargo < b.cargo
		end)
	end
	local shown = 0
	for __ in pairs(markers.shown) do shown = shown + 1 end
	return {
		on = s.on, unlined = s.unlined, selection = s.selection,
		ticks = overlay.ticks, gaps = gaps, unreached = unreached, starved = starved, includeStarved = inc,
		buildings = blds, markers = shown,
		capped = s.on and gaps > shown, rows = rows,
		labels = s.labels,
		labelsShown = overlay.labelStore ~= nil and overlay.labelStore.shown or 0,
		scoped = s.scoped == true, viewTowns = overlay.viewCount, viewText = overlay.viewText or "",
		pending = overlay.pending,
	}
end

return overlay
